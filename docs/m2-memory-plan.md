# M2 情景记忆：开发方案

> 状态：方案稿 v1（确认后实施）
> 上游设计：[super-agent-refactor.md](super-agent-refactor.md) M2 节
> 前置：M1 最小闭环已上线（Brain / TaskStore / 三工具 / 双通道意图）

## 1. 目标与验收

一句话：**让宠物记得住「主人说过的事」，隔天还能接上话**。

| # | 验收场景 | 判定 |
| --- | --- | --- |
| A1 | 今晚说「我明天要早点睡」，明天任意开一轮聊天 | 宠物回复能关联到这件事（上下文里出现该情景） |
| A2 | 说「我下周要去上海」，一周内再聊出差/上海 | 命中检索，自然提起 |
| A3 | 说「我最喜欢吃辣」，之后聊到吃的 | 命中检索 |
| A4 | 灌入 1000 条事件后做检索 | 单次检索 < 50ms，上下文不超预算 |
| A5 | 记忆管理入口 | 能按天查看、清除单日、一键全清 |

## 2. 现状与差距

现有三层（都不动语义，只做收编）：

| 层 | 现状 | M2 角色 |
| --- | --- | --- |
| `PetMemory`（aipet.memory.v1） | taps/chats 计数、notes≤12 里程碑、topics≤8、成长阶段 | 保留，作为「计数记忆」继续注入，M2 新情景是它的兄弟层 |
| 聊天历史（aipet.history.v1） | 每宠物 60 条滚动窗口，API 只带最近 10 条 | **工作记忆**，不动；M2 负责跨越这 10 条之外的部分 |
| system prompt 注入点 | `_buildMessages` 把 `memory` 字符串拼在人格后面 | **组装出口**：M2 把「计数 + digest + top-K 情景」合成后仍走这个参数，签名不变 |

差距：没有任何「主人说过的具体事实」的持久层；聊过即忘（60 条外）；任务结果（设过提醒）不在模型上下文里。

## 3. 数据模型

```dart
/// 一条情景：一句「以宠物视角记下的客观事实」，不是原始聊天记录。
class EpisodicEvent {
  final String id;            // '<epochMs>-<seq>'
  final String petId;
  final DateTime at;
  final EpisodeKind kind;     // chat | interaction | task | digest
  final String content;       // 「主人说明天要早点睡」（第三人称、去口语化）
  final int importance;       // 1 日常 / 2 有信息量 / 3 强约定（时间、偏好、计划）
  final String? tag;          // 可选：话题词（吃/睡/上海/提醒…），检索加分用
}
```

要点：
- **存事实不存原话**：写入时归一成第三人称短句（≤40 字），既是隐私降噪，也让检索词面更稳。
- **importance 写入时定**：规则抽取器给分（见 §4）；后续淘汰按 importance 升序。
- **digest 也是事件**（kind=digest），天然参与检索，且天然带时间。

## 4. 写入管道（三个来源 + 一次日结）

| 来源 | 时机 | 打分 | 降噪 |
| --- | --- | --- | --- |
| ① 聊天事实 | 每轮对话结束后**异步抽取**（不阻塞回复） | 规则命中时间/偏好词 → 3；一般自述 → 2 | 同 tag 当天合并；纯寒暄不写 |
| ② 互动事件 | PetBehavior 埋点：tap/喂食/求摸/摸肚子 | 1 | 同类一天只记一条汇总（「今天被摸了 23 次」） |
| ③ 任务结果 | Brain 创建/触发/取消提醒时 | 2 | 同一任务只记创建与（可选）触发 |
| ④ 日结 digest | 次日首次启动（或跨天首次心跳）时，把昨天全部事件卷成一段 ≤150 字摘要 | 3 | 在线走 LLM 摘要；离线用模板拼接（不丢事实） |

聊天抽取的实现取舍（关键决策）：

- **不改 `[情绪]` 回复协议**——动主链路协议会波及所有模型与测试。
- 采用**异步二次抽取**：回复完成后，若在线，发一个独立小请求（temperature 0、max_tokens 120、
  超时 6s）让模型输出 0~2 条值得记的事实（JSON 数组）；失败/离线则退回**规则抽取**：
  `我要/我想/我喜欢/我讨厌/我打算/记得/下周|明天|X号` 等模式 + 时间词解析（复用 M1 的 parseWhen）。
- 抽取结果先过**敏感过滤**：命中手机号/身份证/密码类模式的一律不落盘。

## 5. 存储与容量

- 落盘：`aipet.episodes.v1`（shared_preferences，单 key），结构
  `{ petId: { "days": { "<yyyy-MM-dd>": [event…] }, "digests": { "<yyyy-MM-dd>": "…" } } }`
- 上限：单日 ≤ 80 条；单宠物总量 ≤ 400 条；digest 保留 30 天。
- 淘汰：超限时先删 importance=1 的最旧事件，再删 2，digest 永不自动删。
- 写入去抖 2 秒合并；读路径全内存（启动加载一次），检索不做 IO。

## 6. 检索与上下文组装

打分（无 embedding，语料 ≤400 条时词面+时间足够，embedding 留 M4 评估）：

```
score = 1.0 * importance
      + 1.2 * recency        // 半衰期 3 天：exp(-Δday/3)
      + 2.0 * keywordOverlap // 当前输入的中文 bigram 与事件词面重叠率
      + 0.8 * digestBoost    // digest 命中再加分
```

组装出口（`MemoryService.assemble(petId, query)` → string，**替代**现在的 `promptFor(pet.id)` 调用点）：

```
计数记忆（PetMemory.promptSummary，现有）
+ 近 3 天 digest（每段 ≤150 字）
+ top-K ≤ 6 条情景（总字符 ≤ 600），按分数降序
整体 ≤ 2000 字符；超预算先砍 top-K 尾部，digest 永保
```

`chat_coordinator:77` 一行换成新调用，`chatService`/`openai_backend` 签名零改动。

## 7. 记忆管理 UI（最小可用）

- 入口：聊天面板工具区（现有「清空记忆」按钮处升级为「记忆」页）。
- 内容：按天折叠列表（digest 置顶 + 当天情景），单日清除、一键全清；
  全清需二次确认（延续现有 clearMemory 语义并扩展到情景层）。
- 手机端（overlay）：M2 不做记忆 UI，只有数据层共享。

## 8. 测试计划（约 25 用例）

| 模块 | 用例 |
| --- | --- |
| episodic_store | 分区读写、去抖合并、单日/总量淘汰顺序、digest 保留、坏数据容错 |
| extractor | 各句式（我要/我想/喜欢/计划+时间）、敏感信息拦截、去口语化、tag 提取 |
| retrieval | 打分公式各分量、topK 截断、600 字符预算、空查询（仅 recency+importance） |
| assemble | 三层拼接顺序、2000 字符硬预算、计数记忆兼容（老用户无情景时输出不变） |
| brain 接线 | 提醒创建/触发产生情景事件 |
| digest | 模板兜底（离线可测）、在线摘要调用参数 |

## 9. 实施步骤（确认后按序执行）

1. `lib/agent/memory/episodic_event.dart` —— 模型 + 枚举 + JSON
2. `lib/agent/memory/episodic_store.dart` —— 分区存储 / 上限 / 去抖 / 淘汰
3. `lib/agent/memory/extractor.dart` —— 规则抽取 + 敏感过滤 + 归一化
4. `lib/agent/memory/retrieval.dart` —— 打分 + topK + 预算
5. `lib/agent/memory/digest.dart` —— 模板兜底 + 在线摘要
6. `lib/agent/memory/memory_service.dart` —— 门面：record×3 / dailyRoll / assemble
7. 接线：chat_coordinator（异步抽取 + assemble 替换 77 行）、PetBehavior 埋点、Brain 任务结果、跨天日结挂到 Brain 心跳
8. UI：chat_view 记忆页（列表/单日清/全清）
9. 测试 + 全量回归（136 → 约 160 全绿）
10. 文档：architecture.md 智能体层补记忆小节、roadmap M2 打勾、CHANGELOG

规模预估：新增 ~900 行 + 测试 ~500 行；不改任何现有函数签名（除 77 行调用点换实现）。

## 10. 风险与边界

| 风险 | 对策 |
| --- | --- |
| 聊天内容明文落盘 | 敏感模式过滤 + 一键全清 + 「存事实不存原话」 |
| 抽取噪音（把寒暄记成事实） | 规则白名单句式 + 同 tag 当日合并 + importance 分层淘汰 |
| 本地 3B 模型抽取质量差 | 规则抽取保底；LLM 抽取失败静默回退，不阻塞主流程 |
| 上下文膨胀拖慢/加价 | 2000 字符硬预算 + 检索全内存 |
| shared_preferences 单 key 过大 | 总量 400 条上限 + 去抖；若实测超 500KB 再迁文件存储（接口已隔离，换实现不动调用方） |
| 隐私开关预期 | M2 提供「记忆总开关」（关停抽取，只保留计数），放记忆页顶部 |
