# 架构说明

## 分层

```
┌──────────────────────────── app/lib ────────────────────────────┐
│ ui/            PetShell / PetView / ChatView / PanelView / 气泡   │
│ pet/           PetStage（帧 + 程序化动作）、motion、particles     │
│ state/         AppController + 4 个 coordinator（ChangeNotifier）│
│ services/      WindowService、TrayService、Win32HitTest、        │
│                ChatService（LocalBrain / OpenAiBackend）、       │
│                PetForgeClient、BadgePetFactory、Persona          │
│ data/          PetRepository、SettingsStore                      │
│ models/        Pet / PetPack、ChatMessage、AppSettings           │
└─────────────────────────────────────────────────────────────────┘
                     │ HTTP                    │ HTTP
        ┌────────────▼──────────┐   ┌─────────▼──────────────┐
        │ 本地 / 在线 LLM 接口  │   │ PetForge（FastAPI）    │
        └───────────────────────┘   └────────────────────────┘
```

对话后端双协议：`openai_backend.dart` 同时支持 OpenAI 兼容（/chat/completions）与 Anthropic
兼容（/messages），由 `AppSettings.apiProtocol` 切换，地址 / 模型 / Key 共用一套配置。

**模型供应商（2026-11，按 DeepSeek Harness 的接入模式）**：`models/model_presets.dart`
把配置组织成「**供应商 = 一个 Key + 一组模型目录**」——复刻 Harness 的
`设置 → 模型 → 选供应商 → 粘贴 Key → 从目录挑模型`，用户不需要知道 baseUrl 要不要带
`/v1`、Anthropic 端点是 `/anthropic` 还是 `/apps/anthropic`。

- **OpenCode Go / 按量排在最前**：一个 `oc_sk_` Key 走遍 DeepSeek / GLM / Kimi / Qwen。
  Go 端点 `https://opencode.ai/inference/go/{openai|anthropic}/v1`，按量把 `/go` 去掉。
  Go 订阅要求 `x-opencode-session` 稳定会话头（路由 + prompt 缓存），由
  `AppSettings.opencodeSessionId` 从 Key+地址派生 FNV-1a 哈希：跨请求/跨重启稳定、
  换 Key 自动换会话、原始 Key 不外泄；`openai_backend.dart` 与 `agent/tool_probe.dart`
  的所有请求（含流式与 Anthropic）都自动带头。
- **其它供应商**：DeepSeek / GLM Coding Plan / 百炼 Coding Plan / Kimi / OpenAI / Ollama，
  各自带 Key 获取提示与端点配套注意事项（如百炼 `sk-sp-` Key 只能配 `/apps/anthropic`）。
- **能力标注**：`agent/tool_probe.dart` 目前只发 OpenAI 协议的 `/chat/completions` + `tools`，
  所以 Anthropic 协议下工具意图会静默降级为普通聊天，设置页如实标注，不误导。
- 选供应商只改模型三件套（协议/地址/模型），不动 Key；换模型时 Key 保留。
  `findPresetId()` 按三件套反查，手动改任一项即显示「自定义」（哨兵项，不覆盖字段）。
- 「测试连接」用当前输入框的值发一条极短消息，协议字段随快照一起走（曾漏带 `apiProtocol`
  导致切到 Anthropic 仍测旧协议）。

没有引入状态管理框架：`AppController extends ChangeNotifier`，`main.dart` 用 `ListenableBuilder` 包住整个 App。
状态字段全部留在 `AppController` 上，行为按职责拆成四个 `on ChangeNotifier` 的 mixin：

| coordinator | 负责 |
| --- | --- |
| `pet_behavior.dart` | 点击 / 抚摸 / 拖动 / 空闲定时器 / 主动行为 |
| `chat_coordinator.dart` | 收发消息、流式输出、朗读、历史持久化 |
| `generation_coordinator.dart` | 选图、PetForge / 徽章兜底、收养 |
| `update_coordinator.dart` | 版本检查、下载安装、Petdex 导入、悬浮窗开关 |

mixin 通过抽象 getter / setter 声明所需状态，由 `AppController` 的字段直接满足，
因此对外 API（`controller.tapPet()` / `sendMessage()` …）和 UI 代码完全不用改；
`controller_types.dart` 单放枚举与主动行为权重纯函数，避免循环 import。
面板同样按 Tab 拆成 `panel_chrome` / `gallery_tab` / `create_tab` / `settings_tab`，
`panel_view.dart` 只保留装配与桌面 / 移动端布局。
调试时看状态仍只需盯 `AppController`，改行为则去对应 coordinator。

## 窗口形态

一个窗口，三种形态（`WindowMode`），由 `WindowService.applyMode` 改尺寸并居中过渡：

| 形态 | 尺寸 | 内容 |
| --- | --- | --- |
| `pet` | 300+80·scale × 360+120·scale（夹在 300~460 / 360~500） | 宠物本体 + 气泡 |
| `chat` | max(410, 宠物宽) × 660 | 聊天面板 |
| `panel` | 900 × 680 | 宠物库 / 生成 / 设置 |

窗口属性：无边框、透明、置顶、不进任务栏、不可缩放。透明靠 `flutter_acrylic` 的 `WindowEffect.transparent`，
`window_manager` 负责尺寸、位置、置顶、显示隐藏。

## 鼠标穿透（仅 Windows）

宠物窗口大部分区域是空的，必须让点击继续落到下面的桌面图标上。

1. `PetStage` 每次布局后把宠物的全局矩形写进 `WindowService.hitRect`；
   `PetView` 另外把气泡与右上角按钮的并集写进 `uiRect`，两块都参与命中判定
   （只算宠物的话，那两个按钮在穿透模式下永远点不到）。
2. `Win32HitTest` 用 `FindWindow` 拿 HWND，每 120ms 读一次光标物理坐标与窗口矩形，
   按 `dpr = 窗口物理宽 / 窗口逻辑宽` 换算成窗口内逻辑坐标。
3. 光标在 `hitRect`（外扩 12px）内 → 取消穿透；否则 `setIgnoreMouseEvents(true)`。

用轮询而不是 Flutter 的 `MouseRegion`：穿透状态下 Flutter 收不到任何鼠标事件，只能从系统层面问。

拖动也没有用 `windowManager.startDragging()`（它进入 WM_NCLBUTTONDOWN 的模态循环，动画会停），
而是每 16ms 采样光标位移并 `setPosition`，所以被拎起来时宠物还能继续摆动。

## 动画引擎

动画是「逐帧动画 + 程序化微动」两层叠加：

- **逐帧动画（flipbook）**：`petpack.json` 的 `animations` 段声明动作序列，如
  `{"walk": {"fps": 8, "frames": ["walk_0.png", ...]}}`。内置宠物由
  `tools/make_builtin_pets.py` 逐帧重绘（walk 4 帧 @8fps、run 4 帧 @12fps、lie 2 帧 @2.5fps
  含呼吸、hop 4 帧 @12fps 开心跳、drop 2 帧 @3fps 委屈落地），腿 / 尾 / 耳 / 身体真实变化。
  动作集对齐灵犀桌宠的标准化动作（待机 / 开心 / 委屈 / 跑），自定义宠物（有财）的帧
  由图生图生成（基准图 + 绿幕抠图）。照片宠物由 PetForge `animate=true` 生成
  walk / run / lie（默认程序化仿射变形，512×512，带帧间去重；可选 ComfyUI 图生图），
  详见 [pet-generation.md](pet-generation.md)。`PetStage` 按 `(time * fps) % frames.length`
  循环取帧渲染（`Pet.imageForFile`）。
- **程序化微动**：`motion.dart` 姿态叠加在帧上；命中动画序列时姿态衰减到 25%
  （`const PetPose().lerp(pose, 0.25)`），只留轻微起伏 / 倾斜，避免与帧内已绘姿态
  （如躺倒歪头）叠加。无动画序列的动作（拖拽 / 点击 / 睡觉等）仍走纯程序化姿态。

- **方向化（Petdex 范式）**：帧原画朝左，`AppController.facing` 记录最近一次走动方向，
  渲染时水平镜像；`facing < 0` 时 `_animationFor` 会优先取 `<motion>_left` 这条
  **独立方向序列**（对应 Petdex 的 running-left 行），而不是只靠镜像。
  点击（hop）与松手落地（drop）的帧动画按 `motion.name` 自动命中 animations。
- **绕垂直轴转身**：`spin` 序列的帧号是**朝向索引**，`PetStage` 用 `_action.value` 取帧，
  不再按 fps 循环；帧内用柱面重映射做水平透视，y 恒定、脚底贴地。
  `MotionEngine.spin` 已移除 `rotation: 2πp`（那是绕图像中心的 2D 打转），
  只保留水平面内 ±3px 微动。详见 [petdex.md](petdex.md)。
- **拖动走路**：拖动时若 petpack 有 `walk`，`PetStage` 直接播 walk 真帧；`WindowService`
  每 16ms 把拖动位移回调给 `AppController`，按 `dx` 更新 `facing`，所以往左拖朝左、
  往右拖朝右。停住时仍继续迈步（当前实现不区分“拖动中是否移动”）。
- **甩动抖毛**：拖拽中左右快速换向累计 ≥4 次（`_onDragMove` 统计），松手时改播
  `shake`（抖毛）而不是 `drop`，附一句晕乎乎的气泡——像真狗被晃晕后甩毛。
- **兜底**：照片生成的自定义宠物没有动画帧时（旧宠物包 / 生成时关闭动画），动作走纯程序化姿态
  （挤压 / 摆动 / 旋转）。
## 智能体层（M1，2026-11-12）

参考 DeepSeek Super-agent（Router/Worker、事件驱动、存算分离、Watchdog、异步 ReAct）
与 DSH「一切皆插件」重构，完整设计与分期见 [super-agent-refactor.md](super-agent-refactor.md)。
M1 已落地最小闭环，代码在 `lib/agent/`：

```
用户文本 / 定时心跳
   │
   ├─ ChatCoordinator.sendMessage 先问 PetBrain.handleUserText()
   │    ├─ parseOfflineIntent（中文规则表：提醒 / 宠物动作 / 剪贴板）
   │    └─ parseOfflineAction（离线本机操作：文件 / 命令 / 进程 / 窗口 / 截屏…）
   │
   ├─ 在线 + 全权限 → ChatAgent.respond（聊天级 ReAct，见「聊天链路」）
   │
   ├─ PetBrain（agent/brain.dart，Router 职责）
   │    · 意图 → 任务执行 → 回复文案（聊天流与桌面气泡同内容）
   │    · TimerTrigger 心跳（20s）巡视到期任务；启动时补报 30 分钟内错过的提醒
   │
   └─ 任务持久化 TaskStore（shared_preferences JSON）
        · 重启恢复：到点的补发、每日的重排——「状态外置」即存算分离的落法
```

> M1 最初的「在线探测（ToolProbe.probe）」已在 M5.1 退出聊天主路径：
> 它只能单步、且会让一句话打两次模型；现由 `ChatAgent` 的多轮 function calling 承担。
> 详见 [autonomy.md](autonomy.md) §3.1。

### 情景记忆（M2，2026-11-12）

代码在 `lib/agent/memory/`，方案见 [m2-memory-plan.md](m2-memory-plan.md)。

```
聊天流(_finishReply后) ─┐
PetBehavior互动(摸/喂) ─┼→ MemoryService ─→ EpisodicStore（按天分区, aipet.episodes.v1）
Brain任务(提醒创建)   ─┘        │
心跳(20s) ─→ 跨天日结 digest ──┘
上下文组装 assemble()：计数记忆(PetMemory) + 近3天digest + top-K≤6情景 → system prompt
```

- **存事实不存原话**：写入时归一成第三人称短句（≤40 字），敏感模式（手机号/密码类）拦截。
- **抽取双保险**：规则表（我要/我想/喜欢/计划+时间词）保底；在线时对规则未命中的话做
  LLM 抓漏（独立小请求，失败静默回退）。
- **打分检索**：importance + 3 天半衰期 recency + 中文 bigram 词面重叠 + digest 加成；
  不用 embedding（语料 ≤400 条时词面足够，M4 再评估）。
- **容量护栏**：单日 ≤80 / 单宠物 ≤400 / digest 30 天；assemble 硬预算 2000 字符。
- **UI**：聊天面板「它记得什么」→「情景记忆…」：按天查看、单日清除、一键全清、记录总开关。
- **隐私语义**：「让它忘掉」（clearMemory）同时清计数记忆与情景记忆。

- **工具（插件化）**：`PetTool` 抽象 + 注册表，M1 内置 reminder / clipboard / pet_control。
  pet_control 让模型拥有「发起动作」的通道（散步/跳/睡/醒/求摸）。
- **宿主接口**：`BrainHost` 抽象切断 agent→AppController 反向依赖；AppController 实现之，
  气泡/动作/TTS 是否表现由形态（桌面宠物/聊天面板）决定。
- **三通道意图**：① 确定性规则表（提醒 / 动作 / 剪贴板 + 离线本机操作，零模型成本）；
  ② 在线 + 全权限时 `ChatAgent` 的多轮 function calling（聊天里真正执行工具）；
  ③ 后台 `AutonomyLoop` 的多步目标规划（离线时降级为 `offlinePlan` 单步）。
- 已知边界：Worker 串行（一次一个任务）；取消粒度为关键词匹配；剪贴板仅按需读取（监听在 M3）。

- **扩展动作**：`animations` 认 `idle`（呼吸）、`talk`（说话）、`sleepy`（打盹）、
  `spin`（转圈）、`eat`（讨食），以及 v2 交互动作 `stretch`（伸懒腰）/ `wag`（开心摇尾）/
  `shake`（抖毛）/ `bark`（汪汪叫）/ `sniff`（嗅探）/ `celebrate`（作揖庆祝）。
  有财的这 17 组帧由 `tools/generate_pet_motion_frames.py` 分部件蒙皮生成（111 帧，幂等可重跑），
  不依赖 ComfyUI；侧面视角动作统一「原画朝左」（见 petpack.md 朝向约定）。
  新动作都有 `MotionEngine` 程序化姿态兜底，旧宠物包也能响应新交互。
  一次性帧动作（spin / shake / celebrate / stretch / bark）按动作进度取帧播一遍，
  时长由 `PetStage._actionDuration` 按 petpack 的「帧数 / fps」精确对齐。
- **表情让位**：照片宠物通常只有 `idle` 一帧，其余情绪靠 `ExpressionOverlay` 叠加。
  当 `motion == idle` 且当前情绪没有对应表情帧时，`PetStage` 跳过 idle 呼吸帧，
  否则呼吸帧会把 happy / love 等表情盖住。其它动作（talk / sleepy / spin / eat）优先用帧。
- `motion.dart`：`idle` 呼吸、`hop` 跳跃、`spin` 水平面微动（无 2D 旋转）、`drop` 落地、
  `drag` 被拎起、`pat` 被摸、`walk` 走路、`run` 奔跑（前倾 + 颠簸）、
  `lie` 躺倒求摸（侧倾 0.52rad + 压扁 0.76 + 3.2s 呼吸）、`eat` 点头。
  这一层是**没有逐帧素材时的程序化兜底**；有 `animations` 的宠物姿态只叠加 25%，
  主要表现来自位移场生成的局部动作帧。
- 呼吸 / 摆动 / 逐帧播放用一条 20 秒循环的 `AnimationController`（`PetStage._clock`）驱动；
  `PetStage` 用 `AnimatedBuilder` 监听 `Listenable.merge([_clock, _action])` 逐帧重建
  （早先前只靠 `AppController.notifyListeners()` 触发，走动时帧并不会连续播放）。
  帧号用单调 `Stopwatch` 取（`PetAnimSequence.frameAt`），避免 `_clock` 每 20 秒回绕时跳帧；
  动作帧在进入舞台时 `precacheImage` 预解码，第一圈走动不会卡顿。
- 动作由 `AppController.action + actionSeed` 触发：seed 变化即播一次，播完回调 `completeAction()`。
- 眨眼随机 2.4~6 秒一次；有 `blink` 帧就换帧，没有就压扁一下。
- `particles.dart`：爱心 / 星星 / 怒气 / Zzz / 音符，按情绪由 `AppController.emitBurst` 派发。

## 感知、自治与插件化（M3/M4，2026-11-24）

设计来源：[super-agent-refactor.md](super-agent-refactor.md)（DeepSeek Super-agent 五大机制）。

- **Trigger 层**（`agent/triggers/`）：`PetTrigger` 抽象 + `PetEvent` 事件总线。
  `ClipboardTrigger` 轮询检测三类模式（URL / 英文句子 / 数字串），payload 只有模式标签、
  **原文不常驻事件与落盘**（M5 下模型可按需用 `clipboard` 工具读取原文）；
  `AppFocusTrigger` 用 `dart:ffi` 直接调 `user32.dll` 的
  `GetForegroundWindow` / `GetWindowTextW`，只把窗口标题归类（浏览器/编辑器/办公/游戏/聊天），
  不保留标题原文。两者受同一个 `QuietPolicy` 约束：M3 实施时是 22:00–08:00 静默 /
  每日 6 次 / 90 秒冷却、总开关 `perceptionEnabled` 默认 false；
  **M5 已改为全天允许 / 240 次防抖 / 10 秒冷却、感知与自主执行默认开启**
  （旧值仍可在 `brainpack.quietHours` 配回）。
- **Watchdog**（`agent/watchdog.dart`）：30 秒巡视，`PersistedTask` 新增
  `startedAt / attempts / lastError` 字段；running 超过 2 分钟判卡死、重试 ≥3 次判失败、
  scheduled 且错过 >30 分钟判过期。三种都写回任务表，宿主只收到一句汇总降级台词（防刷屏）。
- **异步 ReAct**：`SlowToolIntent` + `PetBrain._startBackgroundTool`——声明 `slow=true`
  的工具先回「我去看看」，后台执行完再 `agentBubble` 汇报，等待期间聊天流不阻塞。
  内置工具默认非 slow（提醒必须即时确认）。
- **brainpack.json**（`agent/brainpack.dart`）：仿 petpack 的声明式能力清单，白名单
  （`builtInTools` / `builtInTriggers`，M5 已扩到 16 个工具）外的条目跳过并记 warning。
  **这是配置不是代码**：不执行任意 Dart、不接受任意 URL。
  M5 之后它只是「模型工具清单的开关表」，不再是能力上限；授权看 `AgentPermissions`。
- **投机执行**（`agent/speculative.dart`）：基于时段（下班前 / 睡前）与 30 分钟内到期日程
  预生成关怀草稿，缓存后由 Trigger 消费输出；静默时段不生成也不输出（M5 默认无静默时段），
  每日上限由 3 提到 12。默认 generator 是本地文案兜底，离线不崩。

## 本机全权限与自主执行（M5，2026-11-24）

方向性变更：智能体从「被沙箱约束的陪伴助理」升级为「对这台电脑有完整操作面、能自主接活并执行」。
**唯一权威规格是 [autonomy.md](autonomy.md)**（权限矩阵、审计格式、验收、已知边界）；
本节只说明它在整体架构里的位置与装配顺序。

### 权限与执行链路

```
用户文本（聊天） / Trigger 事件 / 空闲自驱
   │
   ├─ ① PetBrain.handleUserText：parseOfflineIntent + parseOfflineAction（离线即时执行）
   ├─ ② ChatAgent.respond：高权限 system + tools → 多轮 ReAct（在线主通道）
   ├─ ③ AutonomyLoop.submit / tick：目标队列 + 多步规划（含经验召回）
   └─ ④ 降级：流式聊天（带高权限 preamble，如实说明本轮未执行）
   │
   ▼
ToolRegistry（16 个内置工具 + MCP 远程工具，全部是 ToolRuntime.wrap 后的受管治版本）
   │
   ▼
ToolRuntime.execute：能力校验 → validate 策略 → invoke → AuditLog → AgentActivity
   │                                                        └─ 气泡 / 聊天状态条
   ├─ SystemCommandRunner（Process.start + 超时 kill）
   ├─ dart:io File/Directory
   ├─ Win32Api（user32.dll FFI：窗口 / 键鼠）
   └─ http.Client / PowerShell（截屏）
   │
   ▼
ExperienceBank（agent.experience.v1）：目标级复盘 → 回灌聊天 / 规划提示词
```

`PetTool` 新增两个默认成员：`capability`（需要哪个能力域）与 `validate(args, permissions)`
（执行前策略校验）。旧工具不用改，`ToolRuntime` 的 `_GovernedTool` 装饰者负责转发与拦截。
`AppController.connectMcpServer` 注册远程工具时也走 `toolRuntime.wrap(tool)`，
因此**不存在绕过权限校验的入口**。

### 工具清单

| 分组 | 工具 | 文件 |
| --- | --- | --- |
| M1 陪伴 | `reminder` / `clipboard` / `pet_control` | `agent/tools/reminder_tool.dart`、`basic_tools.dart` |
| 本机执行 | `run_command` / `process` / `launch` / `http_request` | `agent/tools/system_tools.dart` |
| 文件与剪贴板 | `file_read` / `file_write` / `file_list` / `file_search` / `file_delete` / `clipboard_write` | `agent/tools/file_tools.dart` |
| 桌面交互 | `window` / `input` / `screenshot` | `agent/tools/desktop_tools.dart` |
| 远程 | 已连接 MCP 服务器的工具 | `agent/mcp/mcp_client.dart` |

`LaunchTool` 在 Windows 上统一经 `explorer.exe` 拉起 GUI 程序：
直接 `Start-Process` 出来的子进程会被宿主 Job 对象回收（2026-11-24 构建实测结论，
本会话里 GUI 程序也必须经 explorer.exe 启动才能稳定存活）。

### 自主循环

`agent/autonomy.dart` 的目标状态机与 `ToolProbe.plan()`：

```
queued ──tick──▶ running ──PlanToolCall──▶ running（下一步）
                    ├──PlanFinish────────▶ done ──▶ 气泡 / TTS / 情景记忆
                    ├──PlanFail──────────▶ failed
                    └──熔断（步数/连败）─▶ failed
```

- `GoalStore` 落盘 `agent.goals.v1`，重启后未完成目标续跑（「状态外置」的真正落法）。
- 由 `PetBrain._onTick` 的 20 秒心跳驱动；`submit()` 会立即推一步。
- 每步只调一个工具，串行执行；结果摘要回灌下一次 `plan()`，模型返回纯文本即判定完成。
- 熔断：步数 ≥ `maxStepsPerGoal`(12)、连续 2 次工具失败、计划请求 20 秒超时。
- 离线走 `offlinePlan()` 关键字映射，只做一次只读检查。
- 空闲 30 分钟自发一条只读巡检目标（`selfDriveGoals`），固定 3 步。

### 装配顺序（`AppController.initialize`）

1. `settings = await store.loadSettings()` → `agentPermissions = await _permissionStore.load()`
   → `toolRuntime.applyPermissions(...)`（启动瞬间规则就生效）。
2. 建 `PetBrain`（构造里 `_registerTools()` 注册全部工具，逐个 `wrap`）。
3. 用 `brain.registry` 建 `AutonomyLoop`，`brain.attachLoop(loop)` 挂回（避免循环依赖，
   与 `attachWatchdog` 同一手法），再 `brain.start()`。
4. `QuietPolicy` 按 `brainPack.quietHours` 构造；M5 默认全天允许、240 次防抖。
5. 感知 Trigger 启动；事件在 `_listenPerceptionEvents` 里既冒气泡也转自主目标。

设置页新增「完整本机权限」「自主执行」；管理页第五分段「权限」提供
总开关、一键急停、12 项细粒度能力、拦截不可逆命令、派目标、目标队列、最近动作（审计）。

### 与既有层的关系 / 边界

- M1 的 `TaskStore` 提醒、M2 的情景记忆、M3 的 Watchdog/Trigger、M4 的 brainpack 全部保留；
  brainpack 从「能力上限」降级为「模型工具清单的开关表」，授权看 `AgentPermissions`。
- `QuietHours` 默认从 22–08 静默 / 6 次 / 90 秒改为 0–0（全天允许）/ 240 次 / 10 秒；
  `perceptionEnabled`、`autonomyEnabled`、工具与 Trigger 缺省全部启用。
- 多步规划只支持 OpenAI 兼容协议；Anthropic 下 `plan()` 返回 `PlanFail` 并离线降级
  （与 `ToolProbe.probe` 同一能力边界，设置页已标注）。
- 窗口 / 键鼠 / 截屏仅 Windows；非 Windows 返回明确失败并建议用 `run_command`。
- `file_delete` 只接受单文件并拒绝目录；目录级操作必须走 `run_command` 明确写出整条命令。

## 状态与行为

| 状态 | 归属 | 说明 |
| --- | --- | --- |
| `active` / `pets` | AppController | 当前宠物与全部宠物（内置 + 用户目录扫描） |
| `mood` | AppController | idle / happy / love / angry / sleepy / blink / talk |
| `affection` | AppController | 互动次数，影响撒娇台词与生气阈值（每 19 次点出「别戳啦」） |
| `bubble` | AppController | 气泡文本，定时器到期自动收起 |
| `messages` / `history` | AppController | 当前宠物的会话；按宠物 id 分区，最多留 60 条 |
| `mode` / `panelTab` | AppController | 窗口形态与面板页签 |
| `walking` / `running` | AppController | 漫游状态：`stroll()` 用 `glideBy` 平移窗口 + 走/跑姿态，30% 概率小跑 |
| `begging` | AppController | 躺倒求摸持续状态：`lieDown()` 触发，6 秒气泡 + 14 秒收起，任何互动（`wake()`）打断；躺倒时点击 = 揉肚子（奖励翻倍 + 摇尾巴） |
| 睡醒伸懒腰 | PetBehavior | `wake()` 发现从 `sleepy` 醒来时播一次 `stretch` + 打哈欠气泡 |
| `eating` / `awaitingTreat` | AppController | 讨食动画播放中 / 12 秒投喂窗口；窗口内点击走 `feedTreat()`（好感 +3 并**作揖庆祝** + 摇尾巴） |
| `wagging` | AppController | 开心摇尾巴（循环 wag 动画几秒后自动停）：摸肚子 / 摸头（好感 >10）/ 长按抚摸松手 / 吃到零食后触发 |
| `sniffing` | AppController | 原地嗅探（循环 sniff 动画约 2.2 秒）：漫步落点两成概率触发 |

定时行为都集中在 `pet_behavior.dart` 的 `startIdleTimers()`：自动睡觉（90 秒无互动）、
桌面走动（26~56 秒随机一次，其中 30% 为小跑，走完两成概率原地嗅探）、
自动躺倒求摸（首次 35~75 秒，之后 80~150 秒）、主动行为（180~360 秒一次）。
仅在桌面宠物形态且空闲时触发，设置变化会重排定时器。

主动行为按 `personality.traits` 加权抽取（`controller_types.dart` 里的纯函数，可单测）：

```
traits（贪吃 / 黏人 / 元气 …）
   → proactiveWeights → random ticket → ProactiveKind
       chat    冒泡一句 catchphrase / 闲聊
       treat   begForTreat()：eat 帧 + 12 秒投喂窗口，点一下 = 投喂
       cuddle  lieDown() 求摸
       zoomies bark 一声 + stroll(run: true) 小跑一圈
```

设置页「主动互动」控制 `AppSettings.proactive`；面板「逗一下」直接调 `triggerProactive()`，
不必等定时器。

## 数据落盘

| 内容 | 位置 |
| --- | --- |
| 设置 | `shared_preferences` 键 `aipet.settings.v1`（JSON） |
| 聊天记录 | `shared_preferences` 键 `aipet.history.v1`（`{petId: [message]}`） |
| 长期记忆 | `shared_preferences` 键 `aipet.memory.v1`（`{petId: PetMemory}`） |
| 生成的自定义宠物 | `getApplicationSupportDirectory()/pets/<petId>/`（`petpack.json` + `base.png` 等帧） |
| 内置宠物 | `assets/pets/{momo,mint,taro}/` |

`MemoryStore` 存的是「摘要级」记忆（见面天数、摸头次数、话题计数、里程碑短句），
和完整对话分开存：清空对话不会把「认识了多久」一起清掉。话题提取是极简的关键词正则
（工作 / 学业 / 吃饭 / 睡觉 / 情绪 / 娱乐 / 天气 / 周末），只做计数、只留前 8 个。

`PetRepository` 扫描用户目录时逐个容错：某个宠物包坏掉只跳过这一只，不会拖垮启动。
`AppSettings.fromJson` 同样逐字段容错，配置文件被手改也不会整体重置。

## 聊天链路

```
AppController.sendMessage
   ├─ 1) PetBrain.handleUserText：确定性规则 / 离线本机操作（命中即执行并返回）
   ├─ 2) 组装高权限 systemPrompt
   │      = 全权限身份 + 12 项能力 + 工具清单 + 执行准则
   │        + 人格（仅语气参考）+ 记忆 + 技能 + 同类经验 + 当前状态
   ├─ 3) 在线 + 未急停 → ChatAgent.respond
   │      ├─ POST /chat/completions（或 /messages），带 tools，stream: false
   │      ├─ tool_calls / tool_use → ToolRuntime.executeTracked 真实执行
   │      ├─ 结果以 tool / tool_result 消息回灌 → 最多 6 轮
   │      └─ 400 / 超时 / 不支持 tools → 抛错，降级到 4)
   ├─ 4) 降级：ChatService.sendStream → OpenAiBackend.streamReply
   │      （system 带 buildAgentPreamble；界面提示「这轮没能走工具通道」）
   └─ 5) 本地小脑 → ChatService.local → LocalBrain.reply（陪伴式，永不失联）
```

收尾统一走 `_finishReply`：落一条宠物消息、切情绪、（开了语音就）朗读、冒气泡、
把这一轮记进长期记忆；带工具执行的一轮还会由 `ChatAgent` 写入 `ExperienceBank`。

`ChatView` 顶部 `_statusBanner` 与桌面气泡内的 `TaskStatusChip` 都监听 `AgentActivity`：
显示当前目标、`n/max` 步、正在调用的工具与最近动作，工具一开始执行就刷新。
气泡由 `PetView` 定位在 `bottom: petSize + 6`，紧贴宠物图片上方。

`ChatResult.degraded` 标记是否走了兜底，`ChatView` 据此显示降级提示条。

## 生成链路

```
PanelView 选图 → AppController.loadSource(bytes)
    → generate()
        ├─ PetForgeClient.health → 在线？
        │      ├─ 在线：POST /api/generate（multipart）→ GeneratedPet(pack + base.png)
        │      └─ 离线：BadgePetFactory.build → 圆形猫耳徽章 + 本地人格
        └─ adoptPreview → PetRepository.saveGenerated → 切到新宠物
```

离线徽章模式用 `dart:ui` 的 Canvas 直接绘制（猫耳 + 圆形裁剪 + 白描边 + 高光），
主色由照片像素的 HSV 加权平均得到，再交给 `persona.dart` 推导名字与性格——与 `services/petforge/petforge/persona.py` 同一套口味。

## 语音

`SpeechService` 包着 `flutter_tts`（Windows SAPI / Android 系统 TTS），任何一步失败都静默降级，
不影响聊天。念之前先 `cleanForSpeech`：去情绪标签、颜文字、markdown，超长截断。
开关存在 `AppSettings.tts`，聊天页小喇叭和设置页共用 `toggleTts()`。

## 测试

`app/test/` 覆盖纯 Dart 层，不依赖插件：

- `pet_pack_test.dart`：宠物包解析、缺帧回退、空包默认值、序列化往返。
- `chat_service_test.dart`：本地小脑分支、情绪标签解析、在线 200 正常路径、500 降级路径。
- `settings_test.dart`：设置默认值、JSON 往返、缩放夹取、坏数据容错、人格推导稳定性。
- `memory_test.dart`：成长阶段划分、互动点、提示词片段、话题/里程碑上限、持久化往返、按宠物清空。
- `stream_and_speech_test.dart`：SSE 增量解析、HTTP 错误与空回复抛错、本地模式一次性返回、语音文本清洗。
- `proactive_behavior_test.dart`：性格权重与 ticket 区间、有财专属倾向、开关持久化与旧配置回落、eat 姿态。
