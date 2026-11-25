# MomoPet 智能体重构设计：参考 DeepSeek Super-agent 与 DSH

> 状态：设计稿 v2 — **M1 / M2 / M3 / M4 / M5 均已实施**（2026-11-24）
> 实施记录见 `CHANGELOG.md`；代码在 `app/lib/agent/`，测试在 `app/test/superagent_test.dart`
> 与 `app/test/autonomy_test.dart`。
> **M5 是方向性变更**：从「被沙箱约束的陪伴助理」转为「本机全权限、可自主执行」，
> 完整规格见 [autonomy.md](autonomy.md)；本文 §3/§6 的旧边界结论已按 M5 修订。
> 参考材料：
> - DeepSeek Harness 团队《Super-agent 设计探索：迈向更自主的 Agent 系统》（2026-10-31 公众号文章）
> - 开源原型 `dsh-superagent-prototype`（验证技术路线，非正式产品）
> - DeepSeek Harness（DSH）框架：Agent = Model + Harness，「一切皆插件」（2026-08 开发者预览版）

## 1. 参考架构要点

### 1.1 Super-agent 五大机制

| 机制 | DeepSeek 的做法 | 一句话 |
| --- | --- | --- |
| **双层架构** | Router 承接人类交互、维护全局上下文、分派任务；Worker 相互隔离并发执行，不直接回复用户，状态汇报给 Router | 调度与执行分离 |
| **事件驱动** | 群聊/邮件/日程/GitHub 评论/CI 结果都是 Trigger；程序规则先过滤，再由模型判断是否行动；无人要求的任务需事先声明策略（如「静默复现并修复」） | 消息找活，而不是人派活 |
| **存算分离** | 执行循环、会话状态、工具环境三者分开；进程可重启，依据持久化记录恢复任务；目标环境离线则等待重连 | 挂了能原地复活 |
| **Watchdog** | 独立监督者，定期检查 Agent 是否卡死、重复无效尝试、偏离目标，并介入恢复 | 兜底自治 |
| **异步 ReAct + 投机执行** | 耗时工具调用转后台（>5s 转后台），会话继续收新消息；不确定是否有价值的活先在后台试（静默复现 Bug，确认后才提交） | 等待不阻塞，闲时不空转 |

四项基础特征：**连续**（跨渠道是同一个 Agent）、**高效**（并行多任务）、**主动**（观察环境自行推进）、**持久**（长期在线、异常可恢复）。

### 1.2 DSH 的工程理念

- **Agent = Model + Harness**：模型负责推理，Harness 负责接真实世界（文件、终端、浏览器）。
- **一切皆插件**：工具、技能、会话、沙箱、Agent 循环本身都是可插拔单元（DSH 用 npm 插件 + Cordis 内核，运行时可装卸、可自我改造）。
- 对我们的启示不是「用 npm」，而是：**能力单元化 + 运行时可组装**。MomoPet 的 petpack（宠物包 = 元数据 + 帧 + 性格声明）已经是这个思路在内容侧的先例。

## 2. 现状盘点：MomoPet 智能体栈 v0

```
用户输入 / 定时器
   │
   ├─ ChatCoordinator  聊天状态机：流式输出、TTS、历史(60条/宠物)持久化
   │     └─ ChatService ─ OpenAiBackend（OpenAI 兼容接口 + [情绪]正文协议）
   │                   └ LocalBrain（关键词规则小脑，离线/降级兜底）
   ├─ PetBehavior      定时器驱动：自动睡觉(90s)、漫步(26~56s)、求摸(35~75s)、
   │                   主动行为(180~360s，按性格 traits 加权：讨食/求摸/小跑/搭话)
   └─ MemoryStore      摘要级记忆：摸头次数、聊天次数、里程碑 → promptFor() 拼进 system prompt
```

**已有、且与 Super-agent 思想同构的部分**（不需要推翻，需要收编）：

| Super-agent 概念 | MomoPet v0 里已有的雏形 |
| --- | --- |
| 事件驱动 | 定时器 + 点击/拖拽/长按手势，已经是 Trigger，只是类型太少 |
| 主动行为 | `scheduleProactive` 按性格加权发起——就是「无人要求也自行推进」的宠物版 |
| 持久化 | 历史/记忆/设置均已落盘 shared_preferences |
| 人格一致性 | petpack 的 personality.systemPrompt 全局生效，相当于 Router 的全局上下文 |

**核心差距**（以下为 M1 之前的 v0 盘点，M1–M5 已逐项解决，保留用于说明分期动机）：

1. **没有工具**：模型只会说话，不能「做事」（查天气、设提醒、读剪贴板、看屏幕前的主人）。
2. **没有任务概念**：一切即答即弃；「提醒我三点开会」这种带时间的意图无处安放，重启即失忆。
3. **事件源贫乏**：只有定时器和手势，感知不到时间点、剪贴板、前台应用、天气、电源状态。
4. **行为系统与聊天系统割裂**：PetBehavior 的主动行为是硬编码规则，跟大脑（模型）无关；模型没有「发起动作」的通道。
5. **记忆是计数器不是记忆**：只有次数和里程碑，没有情景（「主人今天说过明天要开会」）。
6. **单轮思维**：一条消息一次回复，没有多步推理（ReAct），更没有后台执行。

## 3. 设计判断：哪些思想直接搬，哪些要裁剪

Super-agent 是为「跨 GitHub/IM 持续跑代码工单」设计的。M1–M4 阶段桌面宠物的定位是
「单机、陪伴为主、轻任务」，因此**照搬会过度设计，裁剪才有生命力**；
M5 起定位升级为「单机、本机全权限、重执行」，下表保留原裁剪判断，
并在末尾补一行 M5 的方向修订（完整规格见 [autonomy.md](autonomy.md)）：

| 机制 | 决策 | 理由 |
| --- | --- | --- |
| Router/Worker 双层 | ✅ 采纳但轻量化：单进程内 **Brain（Router）+ TaskSession（Worker）**，Worker 是隔离的异步任务，不是多进程 | 宠物任务轻（提醒/查询/感知），无需进程级隔离；但要「多件事互不干扰」（提醒响铃时仍能陪聊） |
| 事件驱动 | ✅ 核心采纳：**Trigger 插件化**，程序规则过滤在前、模型判断在后 | 与 PetBehavior 现有定时器天然兼容，收编而非重写 |
| 存算分离 | 🔪 裁剪为「**状态外置**」：任务与记忆持久化到 JSON 文件，执行循环就是 App 进程 | 单机应用没有「云端执行循环」诉求；但「重启后提醒任务仍在」是真实需求（现在设了提醒重启就没） |
| Watchdog | ✅ 采纳轻量版：任务超时/重试上限/卡死检测，由 Brain 统一巡视 | 长期任务（每日提醒）必须能从异常恢复 |
| 异步 ReAct | ✅ 采纳：工具调用异步化，等待中仍可聊天 | 宠物「去查一下再回来告诉你」比卡住不说话更自然 |
| 投机执行 | 🔪 后置到 M3+：宠物版是「预判式关怀」（下班时间快到 → 提前拟好问候草稿） | 有趣但非刚需，依赖事件源成熟度 |
| DSH 一切皆插件 | ✅ 采纳接口化思路：Tool / Trigger / Skill 全部是注册式插件，**用 Dart 抽象类而非 npm**；不引入外部内核 | Flutter 单体应用，进程内插件注册表足够；保留未来热加载的可能 |
| **本机全权限（M5）** | ✅ 采纳：工具扩到命令/进程/文件/窗口/键鼠/网络/截屏，`ToolRuntime` 统一授权与审计；默认全开、可一键回收 | 目标改为「能自主操作这台电脑」。边界从「能力上限」换成「可撤销授权 + 全程留痕 + 可熔断」，见 autonomy.md §6 |
| **目标驱动自治（M5）** | ✅ 采纳：`GoalStore` + `AutonomyLoop` 多步 ReAct + 空闲自驱只读巡检 | 从「等人派活」变成「消息找活、自己找活」，同时保持串行与熔断 |

**仍然不做**：跨设备调度、云端执行循环、多 Agent 协作团队、npm 生态兼容。这些属于 Super-agent 的
「团队协作」场景，与单机桌面产品定位不符；架构上留接口（`TaskSession` / `Goal` 抽象）不铺实现。
注意 M5 已把「轻任务」这一条去掉——本机重执行是现在的核心场景。

## 4. 目标架构（v1）

```
┌────────────────────────── 触发层 Trigger（插件） ──────────────────────────┐
│ TimerTrigger(定时/闹钟)  GestureTrigger(点击/拖拽)  ClipboardTrigger      │
│ PowerTrigger(开机/电池)   AppFocusTrigger(前台应用)   WeatherTrigger(定时天气) │
│      程序规则过滤（白名单/静默时段/勿扰）→ 候选事件                        │
└──────────────────────────────┬───────────────────────────────────────────┘
                               ▼  PetEvent
┌────────────────────────── 大脑层 Brain（Router） ─────────────────────────┐
│ · 全局上下文：persona(systemPrompt) + 情景记忆检索 + 当前状态(mood/任务)   │
│ · 意图判定：模型判断事件是否行动（两级过滤的第二级；离线时退化为规则表）    │
│ · 任务分派：创建 TaskSession，选择工具，设定允许策略（是否需要汇报）       │
│ · 汇报出口：Worker 结果 → 气泡/聊天流/动作（mood、particles、stroll）      │
└──────────┬──────────────────────────────────────────────┬────────────────┘
           ▼                                              ▼
┌──────────── Worker 层 TaskSession ──────┐   ┌──────── 记忆层 Memory ────────┐
│ 独立上下文 + 独立生命周期（一次性/定时/  │   │ 情景记忆(事件日志,可检索)      │
│ 循环型），异步 ReAct Loop：              │   │ + 现有计数记忆(收编)           │
│   LLM ⇄ Tools（await 不阻塞 Brain）      │   │ JSON 落盘，重启恢复            │
│ 超时/重试上限 → 降级 → 汇报失败          │   └────────────────────────────────┘
└──────────────┬───────────────────────────┘
               ▼
┌────────────────────── 工具层 Tool（插件，M5 扩充） ───────────────────────┐
│ M1 陪伴：reminder / clipboard / pet_control                              │
│ M5 本机：run_command / process / launch / http_request                   │
│          file_read / file_write / file_list / file_search / file_delete  │
│          clipboard_write / window / input / screenshot                   │
│ 远程：已连接 MCP 服务器的工具（不得覆盖内置工具名）                       │
│ 统一协议：name/description/JSON schema → OpenAI function calling         │
│ 离线小脑：关键词 → 工具 的规则映射（qwen2.5:3b 级本地模型工具调用弱）      │
└──────────────────────────────┬──────────────────────────────────────────┘
                               ▼
┌────────────── 权限与审计层 ToolRuntime（M5，所有工具必经） ──────────────┐
│ AgentPermissions：12 项能力默认全开 / paused 急停 / 不可逆命令黑名单      │
│ validate → invoke → AuditLog（参数脱敏、输出截断、来源 user/goal/trigger）│
└──────────────────────────────┬──────────────────────────────────────────┘
                               ▼
              Watchdog（超时/重试/错过）  +  AutonomyLoop（目标队列）
              后者把「目标 → 规划 → 工具 → 复盘」跑成后台多步循环
```

M5 之后这张图的读法：**任何**工具调用（用户指令、自主目标、感知事件、MCP 远程）
都会汇入 `ToolRuntime`，权限校验与审计留痕不存在旁路。

关键接口草图（Dart，示意）：

```dart
abstract class PetTool {
  String get name;
  String get description;
  Map<String, dynamic> get parametersSchema;      // JSON Schema
  Future<ToolResult> invoke(Map<String, dynamic> args, TaskContext ctx);
}

abstract class PetTrigger {
  String get name;
  Stream<PetEvent> get events;                    // 已经过第一级程序过滤
}

class TaskSession {
  final String id;                                // 重启恢复的持久键
  final TaskKind kind;                            // oneShot / scheduled / recurring
  final String goal;                              // 自然语言目标（喂给模型）
  final List<ToolCall> transcript;                // 过程留痕（Watchdog 依据）
  Future<TaskReport> run();                       // 异步 ReAct，不阻塞 Brain
}
```

**工具调用协议**（M5.1 现状）：在线模型走 `ChatAgent` 的多轮 function calling（OpenAI
`tool_calls` / Anthropic `tool_use`，工具结果回灌，最多 6 轮）；本地小脑/弱模型走
`parseOfflineAction` 的「意图关键词 + 路径 → 工具 + 槽位」规则表；后台自主目标走
`ToolProbe.plan` 的多步规划。三条路都汇入同一个 `ToolRegistry` + `ToolRuntime`，
模型强弱只影响意图解析质量，不影响权限校验、审计与执行框架。详见 `docs/autonomy.md` §3。

## 5. 分期路线图

### M1 最小闭环：会做事的宠物（先做这个）
- `PetEvent` 事件总线 + Brain（Router）骨架：收编 PetBehavior 的定时器为 `TimerTrigger`
- `TaskSession` 单 Worker（串行队列即可）+ 持久化任务表（重启恢复）
- 3 个内置工具：**reminder**（一次性/每日提醒）、**clipboard**（读取/监听）、**pet_control**（让宠物自己走/跳/睡）
- 在线模型 function calling + 离线规则映射双通道
- 验收：**「提醒我 15:30 喝水」→ 重启 App → 15:30 宠物主动冒气泡提醒**；「陪我散个步」→ 宠物自己走一圈

### M2 记忆升级：记得住主人的宠物
- 情景记忆：事件日志（聊天摘要、互动、任务结果）按天分区落盘
- 检索：Brain 组装上下文时按相关度 + 时间衰减取记忆；计数记忆收编为其中一类
- 记忆查看/清除入口（设置页，延续现有 clearMemory）
- 验收：隔天对话能接上「昨天你说要早点睡」；记忆占用与检索延迟有上限保护
- 详细开发方案：[m2-memory-plan.md](m2-memory-plan.md)（2026-11-12 方案稿，**已实施**）

### M3 感知与自治：有环境的宠物 ✅ 已实施
- `agent/triggers/`：`PetTrigger` 抽象 + 事件总线；`ClipboardTrigger`（只检测 URL/英文/数字
  三类模式，**原文不落盘**）、`AppFocusTrigger`（win32 FFI 读前台窗口，只分类不存标题）。
  `QuietHours` 实施时为 22:00–08:00 静默 / 每日 6 次 / 90 秒冷却、感知总开关默认关闭；
  **M5 已改为全天允许 / 240 次防抖 / 10 秒、感知默认开启**（旧值可在 brainpack 配回）。
- `agent/watchdog.dart`：running 卡死超时（2 分钟）→ failed、重试上限 3 次 → failed、
  错过超 30 分钟 → expired；巡视结果带降级台词，不刷屏。
- 异步 ReAct：`SlowToolIntent` + `PetBrain._startBackgroundTool`，慢工具先回「我去看看」，
  完成后台任务表记账 + 气泡汇报，聊天流不阻塞。
- 验收：复制英文句子 → 宠物主动提议翻译；卡死任务被巡视捕获并标记 failed。

### M4 插件化与预判 ✅ 已实施
- `agent/brainpack.dart`：仿 petpack 的 `brainpack.json` 声明式配置。白名单内置工具/Trigger
  才能开关，未知条目跳过并记 warning，不执行任意代码（不做 npm 插件兼容，见 §3）。
  **M5 修订**：白名单扩到 16 个工具并降级为「开关表」，不再承担授权职责；
  真正的边界是 `AgentPermissions` + `ToolRuntime` 的可撤销授权与审计（autonomy.md §6）。
- `agent/speculative.dart`：投机执行 = 预判式关怀。基于时段（下班前/睡前）与临近日程
  预生成关怀草稿，缓存后由 Trigger 触发才输出；静默时段与每日配额同样生效。
- 沙箱评估结论（M4 时）：不需要。所有插件都是白名单内的 Dart 类，无外部代码执行路径。
  **M5 之后这条结论不再适用**：工具已能真实操作本机，改为 `ToolRuntime` 授权 + 审计
  + 一键急停（见 [autonomy.md](autonomy.md) §6），不再依赖「无外部执行路径」做安全前提。

### M5 本机全权限与自主执行 ✅ 已实施（方向性变更）

完整规格：[autonomy.md](autonomy.md)。要点：

- **权限**：`agent/permissions.dart` 定义 12 项 `AgentCapability`，默认全开；
  `agent/tool_runtime.dart` 用装饰者包住注册表中每一个工具（含 M1 老工具与 MCP 远程工具），
  统一做能力校验、策略校验、审计留痕。`agent/audit_log.dart` 滚动 500 条，敏感参数打码。
- **工具**：`agent/tools/system_tools.dart`（命令/进程/启动/HTTP）、
  `file_tools.dart`（读/写/列/搜/删/写剪贴板）、
  `desktop_tools.dart`（user32 FFI 窗口与键鼠、PowerShell 截屏），共 13 个新工具。
  命令用 `Process.start` + 超时 kill，输出截断；GUI 程序经 `explorer.exe` 启动。
- **通用执行通道**：M5 把 `Brain._executeIntent` 的 `default` 改为
  `GenericToolIntent` / `SlowToolIntent`，消除「注册表里有、Brain 没硬编码就不执行」的限制。
  M5.1 聊天改由 `ChatAgent` 按工具 schema 多轮直接调用，这段参数映射已删除；
  `GenericToolIntent` 保留为 Brain 的同步执行通道（离线规则与后台回执）。
- **自主循环**：`agent/autonomy.dart` 的 `GoalStore` + `AutonomyLoop`，
  `ToolProbe.plan()` 带历史做多步规划；步数上限、连续失败熔断、目标持久化重启续跑；
  离线由 `offlinePlan()` 降级成一次只读检查。空闲 30 分钟自发一条只读巡检目标。
- **感知转目标**：`AppController._listenPerceptionEvents` 把剪贴板模式事件翻译成目标，
  由模型决定调哪个工具，不再只是冒一句气泡。
- **默认策略调整**：`QuietHours` 默认全天允许 / 240 次防抖 / 10 秒冷却；
  `perceptionEnabled`、`autonomyEnabled`、`BrainPack` 工具与 Trigger 缺省全部启用；
  `speculative` 每日草稿 3 → 12。旧陪伴模式仍可在 brainpack 里配回 22–08 / 6 次。
- **UI**：设置页新增「完整本机权限」「自主执行」；管理页新增第五分段「权限」
  （总开关、急停、12 项能力、拦截不可逆命令、派目标、目标队列、最近动作）。
- 验收：`flutter analyze` 零问题；新增 `test/autonomy_test.dart` 覆盖权限/审计/工具/循环，
  `test/superagent_test.dart`、`test/manage_test.dart` 的旧默认断言同步改写。

## 6. 风险与对策

| 风险 | 对策 |
| --- | --- |
| 本地小模型（qwen2.5:3b）工具调用不可靠 | 三通道设计：在线走 `ChatAgent` 多轮 function calling、本地走 `parseOfflineAction` 规则映射、后台走自主目标规划；模型不支持 tools 时如实降级，任务框架不依赖模型强弱 |
| 主动打扰引起反感（Super-agent 文章同款问题） | M5 起「自主」优先：默认全天可行动、配额 240 次只防抖；需要陪伴模式时在 `brainpack.quietHours` 配回 22–08 / 6 次 / 90 秒，或关掉 `autonomyEnabled` |
| 任务堆积 / 内存增长 | 自主循环串行（一次一个目标）、`maxStepsPerGoal` 12、目标表保留最近 50 条、工具输出截断 8000 字、审计滚动 500 条、情景记忆仍按天滚动 |
| 隐私（剪贴板/前台应用） | M5 起感知默认开启（全权限方向）；剪贴板事件仍只带模式标签，原文由模型按需用 `clipboard` 工具读取，不常驻事件/持久化；所有工具调用进审计（敏感参数打码）。要恢复旧行为关「环境感知」即可 |
| **命令误执行 / 不可逆操作（M5 新增）** | 6 条不可逆命令黑名单（可关）、`file_delete` 只接受单文件并拒绝目录、命令超时 kill、GUI 经 explorer.exe 启动；其余靠审计可追溯 |
| **自主循环失控（M5 新增）** | 步数上限、连续 2 次失败即终止、计划请求 20 秒超时、自驱目标固定 3 步且只读、一键急停 `paused` 停掉工具/感知/循环 |
| 重构与现有行为系统冲突 | PetBehavior 不重写，逐个定时器「收编」为 Trigger；每期保持测试全绿 + 新增用例（`flutter analyze` 零问题） |

## 7. 与现有文档的关系

- `architecture.md` 的「状态与行为」章节在 M1 实施时同步改写（Brain/Task 取代散落的 Timer 描述），
  M5 新增「本机全权限与自主执行」章节。
- `petpack.md` 在 M4 扩展 `brainpack.json` 一节；M5 之后 brainpack 只是开关表，授权看 `permissions.dart`。
- **`autonomy.md` 是 M5 的唯一权威规格**（权限矩阵、工具清单、执行链路、熔断、验收、已知边界）；
  本文只保留分期决策与裁剪判断，具体参数以 autonomy.md 为准。
- `roadmap.md` §6 同步 M5 条目；`CHANGELOG.md` 记录本次默认策略变更
  （感知/自主/工具全开、QuietHours 不再默认限流、投机草稿 3→12）。
- 每期实施完成后更新 CHANGELOG，并按协作习惯检查需求文档一致性。
