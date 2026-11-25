# M5 本机全权限与自主执行规格

> 状态：已实施（2026-11-24）。设计总纲见 [super-agent-refactor.md](super-agent-refactor.md)，
> 架构位置见 [architecture.md](architecture.md)。
> 本文是 M5 的**唯一权威规格**：权限矩阵、工具清单、执行链路、熔断与验收都以这里为准。

## 1. 方向变更

M1–M4 把宠物做成了「会提醒、会感知、有记忆的陪伴助理」，但能力被三层东西锁住：

| 旧边界 | 具体代码 | M5 的结论 |
| --- | --- | --- |
| 工具只有 3 个 | `brain.dart` 构造里注册 `reminder / clipboard / pet_control` | 扩到 16 个内置工具，覆盖命令、进程、文件、窗口、键鼠、网络、截屏 |
| 模型点名的工具大多不会被执行 | `brain.dart::_executeIntent` 的 `default` 只处理 `slow=true`，其余返回 `null` | 先改为通用执行通道 `GenericToolIntent`；M5.1 起聊天由 `ChatAgent` 按工具 schema 直接调用，`_executeIntent` 的参数映射已移除 |
| 感知与主动性被压制 | `QuietHours` 默认 22–08 静默 / 每日 6 次 / 90 秒冷却；`perceptionEnabled` 默认 false；`brainpack` 白名单被当成能力上限 | 默认全天可行动、配额 240 次只防抖、感知默认开；白名单降级为「开关表」 |
| 没有「自己找事做」 | 只有定时提醒 + 事件冒气泡 | 新增 `AutonomyLoop`：目标队列 + 多步 ReAct + 空闲自驱巡检 |

**新目标**：智能体对这台电脑拥有完整操作面，能自己接活、拆步、调用工具、复盘并持续推进；
同时保证「能力可一键回收、每次动作可追溯、失控能熔断」。全权限不等于无痕迹，也不等于无刹车。

## 2. 权限矩阵

授权单位是 `AgentCapability`（`app/lib/agent/permissions.dart`），默认 **12 项全开**。
`AgentPermissions.enabled` 是真相源；`fullAccess` 是「是否全部已授予」的计算属性，不是运行时优先级。

| 能力 | 工具 | 默认 | 关掉后 |
| --- | --- | --- | --- |
| `command` | `run_command` | 开 | 拒绝任意 shell 命令 |
| `process` | `process`（list / kill） | 开 | 拒绝查/杀进程 |
| `launch` | `launch` | 开 | 拒绝启动程序、打开文件与网址 |
| `fileRead` | `file_read` / `file_list` / `file_search` | 开 | 拒绝读取与列举 |
| `fileWrite` | `file_write` | 开 | 拒绝写入 |
| `fileDelete` | `file_delete` | 开 | 拒绝删除（**只接受单文件，不接受目录**） |
| `clipboardWrite` | `clipboard_write` | 开 | 拒绝写剪贴板 |
| `network` | `http_request` | 开 | 拒绝任意 HTTP 请求 |
| `window` | `window` | 开 | 拒绝窗口列举/置前/最小化/关闭 |
| `input` | `input` | 开 | 拒绝键鼠模拟 |
| `screen` | `screenshot` | 开 | 拒绝截屏 |
| `mcp` | 已连接 MCP 服务器的远程工具 | 开 | 拒绝远程工具调用 |

其它全局策略：

| 策略 | 默认 | 说明 |
| --- | --- | --- |
| `paused`（一键急停） | false | true 时工具、自主循环、感知全部停摆，界面仍可操作 |
| `auditEnabled` | true | 每次工具调用写审计；关掉不再写入，历史不清 |
| `blockIrreversible` | true | 拦截 `format C:`、`rm -rf /`、`rd /s /q C:\` 等一次性抹掉整台机器的命令；**关掉即完全放行** |
| `blockedPatterns` | 6 条正则 | 可清空；普通 `del` / `Remove-Item` / `rm` 一律不拦 |
| `maxStepsPerGoal` | 12 | 单目标步数上限；自驱巡检固定为 3 |
| `commandTimeoutSeconds` | 120 | 超时 `Process.kill`，避免 `ping -t` 挂死智能体 |
| `maxOutputChars` | 8000 | 工具输出回灌模型的硬上限 |
| `selfDriveIntervalMinutes` | 30 | 空闲自驱节流；0 = 不自驱 |

配置落盘 `agent.permissions.v1`（`PermissionStore`）。旧配置缺 `enabled` 字段时**回落全开**，
不会因为一次升级悄悄收回权限。

## 3. 执行链路

```
用户文本（聊天） / Trigger 事件 / 空闲自驱
        │
        ├─ ① PetBrain.handleUserText（确定性规则，零模型成本）
        │     ├─ parseOfflineIntent：提醒 / 宠物动作 / 剪贴板
        │     ├─ parseOfflineAction：离线本机操作（文件/命令/进程/窗口/截屏/网址…）
        │     └─ AutonomyLoop.submit：离线兜底，规则接不住的待办转后台目标
        │
        ├─ ② ChatAgent.respond（在线 + 全权限的聊天主通道，M5.1）
        │     system = 高权限身份 + 能力清单 + 工具清单 + 记忆 + 技能 + 经验
        │     └─ 多轮 function calling：tool_calls → ToolRuntime 执行
        │          → 结果以 tool 消息回灌 → 继续，直到给出结论（≤6 轮）
        │
        └─ ③ 降级：流式聊天（带高权限 preamble，如实说明本轮未执行）
        │
        ▼
  ToolRegistry（所有工具都是 ToolRuntime.wrap 后的受管治版本）
        │
        ▼
  ToolRuntime.execute   ── 能力校验 → validate 策略 → 执行 → 审计 → 状态上报
        │                     │            │                    │
        │                     │            └─ 命令黑名单 / 目录删除 / URL 合法性
        │                     └─ paused / enabled / MCP 能力     └─ AgentActivity
        ▼
  SystemCommandRunner / dart:io / Win32 FFI / http.Client
        │
        ▼
  AuditLog（agent.audit.v1）+ 气泡 / 聊天状态条 / TTS / 情景记忆 / ExperienceBank
```

关键实现文件：

| 文件 | 职责 |
| --- | --- |
| `app/lib/agent/permissions.dart` | 能力枚举、`AgentPermissions`、黑名单、限额、`PermissionStore` |
| `app/lib/agent/audit_log.dart` | `AuditEntry`、参数脱敏 `summarizeArgs`、滚动日志 `AuditLog` |
| `app/lib/agent/tool_runtime.dart` | `_GovernedTool` 装饰者 + 统一执行入口，`executeTracked` 标注来源 |
| `app/lib/agent/tools/system_tools.dart` | 命令 / 进程 / 启动 / HTTP，含可注入的 `CommandRunner` |
| `app/lib/agent/tools/file_tools.dart` | 文件读/写/列/搜/删、剪贴板写入 |
| `app/lib/agent/tools/desktop_tools.dart` | user32 FFI 封装、窗口控制、键鼠模拟、PowerShell 截屏 |
| `app/lib/agent/autonomy.dart` | `Goal` / `GoalStep` / `GoalStore` / `AutonomyLoop` / `offlinePlan` |
| `app/lib/agent/tool_probe.dart` | `probe()` 单轮意图 + `plan()` 多轮规划（注入经验）+ `PlanDecision` 三态 |
| `app/lib/agent/chat_agent.dart` | **聊天级 ReAct**：带 tools 的多轮请求、执行回灌、OpenAI / Anthropic 双协议 |
| `app/lib/agent/system_prompt.dart` | 高权限系统提示词 + 降级通道的精简 preamble |
| `app/lib/agent/offline_intent.dart` | 中文规则表 + `parseOfflineAction` 离线本机操作路由 |
| `app/lib/agent/activity.dart` | `AgentActivity`：目标 / 步骤 / 当前工具 / 最近动作，实时驱动状态条 |
| `app/lib/agent/experience.dart` | `Experience` / `ExperienceBank`：目标级复盘与相似目标召回 |
| `app/lib/agent/brain.dart` | 注册全部工具、通用执行通道、心跳驱动自主循环 |
| `app/lib/state/app_controller.dart` | 权限恢复与装配、聊天执行器装配、感知事件转目标、UI 操作方法 |
| `app/lib/state/chat_coordinator.dart` | 聊天主链路：规则 → ChatAgent → 降级流式；组装高权限提示词 |
| `app/lib/ui/manage_page.dart` | 第五个分段「权限」：总开关、急停、能力清单、目标队列、审计、学习沉淀 |
| `app/lib/ui/chat_view.dart` | 聊天窗口顶部任务状态条、可操作示例快捷指令 |
| `app/lib/pet/pet_view.dart` | 气泡底部锚在宠物上沿，紧贴图片上方 |
| `app/lib/ui/speech_bubble.dart` | 气泡 / 提示胶囊内嵌 `TaskStatusChip` |
| `app/lib/ui/settings_tab.dart` | 主设置页新增「完整本机权限」「自主执行」两个开关 |
| `app/lib/ui/feature_help.dart` | 功能开关说明：`FeatureHelp`（整行 Tooltip）、`HelpBadge`（ⓘ 标记）、`helpTitle` |
| `app/lib/ui/common.dart` | `SettingRow.help` 可选说明，带 help 时自动挂 Tooltip |

**开关说明的呈现**：所有功能开关（设置页 17 个 `SettingRow` + 对话后端分段、
插件分段 16+2 项、权限分段 4+12+1 急停+3 留痕动作、技能列表）都带一份中文说明，只放在 Tooltip 里——鼠标悬停（触屏长按）才弹出，
标题右侧有一个 ⓘ 标记提示「这项有说明」。说明内容覆盖「能做什么 / 关掉会怎样 / 风险边界」，
例如「拦截不可逆命令」会写明黑名单范围与关闭后的后果，避免用户误关全权限。
`test/feature_help_test.dart` 覆盖无 help 不渲染、richMessage 内容、悬停实际弹出。

**一个入口都不漏**：M1 的老工具、M5 的新工具、MCP 远程工具全部通过 `ToolRuntime.wrap()`
注册（MCP 在 `AppController.connectMcpServer` 里包装），因此不存在绕过权限校验的路径。
`BrainPack.builtInTools` 只是「模型工具清单的开关表」，不再承担授权职责。

### 3.1 为什么以前「通过对话不能操作电脑」

不止是提示词，是三条链路缺口叠加（2026-11-24 排查结论）：

| # | 根因 | 位置 |
| --- | --- | --- |
| 1 | 默认 `chatBackend = ChatBackendKind.local`，本机配置里也没有覆盖项；本地小脑只回固定文案，完全不接触工具 | `models/settings.dart`、`services/chat/local_brain.dart` |
| 2 | 在线聊天是**纯文本流式请求**，没带 `tools`、也没有执行回路；系统提示词是宠物人格「每次不超过 40 字 / 永远保持角色」，模型既不知道有工具，也不会真的去调用 | `chat_coordinator.dart` → `openai_backend.dart` → `persona.dart` |
| 3 | 16 个 M5 工具只在「`looksLikeCommand` 命中 **且** 在线后端可用」时被 `ToolProbe.probe` 探测，且探测是单步、命中后直接截断聊天 | `brain.dart`、`tool_probe.dart` |

对应改造：

- **系统提示词**：`system_prompt.dart` 的 `buildAgentSystemPrompt` 把高权限身份放在最高优先级，
  明确「文件 / 命令 / 进程 / 程序 / 网络 / 窗口 / 键鼠 / 剪贴板 / 屏幕都可以使用」，
  列出当前授予的 12 项能力与全部工具名，并给出 7 条执行准则——禁止回答「我只是宠物 / 我做不到 /
  我没有权限」、先执行后汇报、多步连续调用、如实转达拒绝原因、不做自我审查（权限由运行时负责）、
  闲聊不调工具、汇报结果可超过 40 字。人格 `systemPrompt` 降级为「仅作语气参考」。
  降级通道也带 `buildAgentPreamble`，不再把自己描述成玩具。
- **聊天执行回路**：在线 + 未急停时，`ChatAgent.respond` 接管聊天，请求带 `tools`，
  解析 `tool_calls`（OpenAI）/ `tool_use`（Anthropic）→ `ToolRuntime.executeTracked` 真实执行 →
  以 `tool` / `tool_result` 消息回灌 → 最多 6 轮，直到模型给出结论。
  模型不支持 tools / 400 / 超时 → 抛 `ChatAgentException`，上层退回流式聊天并在界面如实提示。
- **离线也能操作**：`parseOfflineAction` 把常见中文指令（磁盘、进程、窗口、列目录、读文件、
  搜索、截图、网址、跑命令、启动程序）直接映射成一次工具调用，零模型成本、即时执行；
  规则接不住的待办交给 `AutonomyLoop.submit`，由 `offlinePlan` 复用同一规则表降级。
- **不再双打模型**：`ToolProbe.probe` 退出聊天主路径（保留实例供自主循环 `plan()`）；
  `plan()` 的 system 改为高权限口径并注入同类经验。
- 聊天输入框提示改为「跟它说点什么，或让它操作电脑…」，快捷指令新增
  「看看磁盘空间 / 列出工作区文件 / 查看进程」，点一下就能看到真实执行结果。

### 3.2 对话框内的任务状态

`AgentActivity`（`ChangeNotifier`）记录目标标题、`n/max` 步、当前工具与参数摘要、
成功/失败、最近 40 条动作；`ToolRuntime.execute` 在每次调用前后 `beginTool/endTool`，
`AutonomyLoop` 在 `submit/tick/_step/_finish/cancel` 时 `beginGoal/updateGoal/endGoal`。
界面直接监听它，工具一开始执行就刷新，不必等 20 秒心跳。

- `SpeechBubble` / `BubbleHint` 内嵌 `TaskStatusChip`（进行中转圈、完成绿勾、失败红标）。
- `ChatView._statusBanner` 显示目标、步数、当前工具与最近 2 条动作。
- **气泡位置**：`PetView` 把气泡从 `top: 4` 改为 `bottom: petSize + 6`，尾巴朝下紧贴宠物头顶；
  按 `petHeight - petSize` 自动把正文收缩到 2 / 3 / 5 行，避免溢出；
  穿透模式的可点击区域 `uiRect` 由 `GlobalKey` 实测上报，随位置自动跟随。

## 4. 自主循环

### 4.1 状态机

```
queued ──tick──▶ running ──PlanToolCall──▶ running（下一步）
                    ├──PlanFinish────────▶ done ──▶ 气泡/TTS/记忆
                    ├──PlanFail──────────▶ failed
                    └──熔断（步数/连败）─▶ failed
任意活动态 ──cancel()──▶ cancelled
```

### 4.2 单步算法（`AutonomyLoop._step`）

1. 取第一个 `queued / running` 目标（队列天然串行，避免并发子进程堆积）。
2. 熔断检查：步数 ≥ `maxSteps`、或末尾连续 2 次工具失败 → `failed` 并汇报。
3. 组装 `history`：每步的「工具 + 参数摘要 + 成功/失败 + 输出摘要」。
4. 在线 → `ToolProbe.plan()`（OpenAI `/chat/completions` + `tools`，带历史，20 秒超时）；
   离线 → `offlinePlan()` 关键字映射成一次**只读**工具调用。
5. `PlanToolCall` → `ToolRuntime.executeTracked(..., source: 'goal')` → 记进 `Goal.steps`。
6. `PlanFinish` → `done`，气泡汇报 + TTS + `MemoryService.recordTask(..., tag: 'goal')`。
7. 每 20 秒由 `PetBrain._onTick` 推进；`submit()` 会立刻推一步，不必等心跳。

`plan()` 的 system prompt 要求模型「每一步只选一个工具、确认完成才用纯文本总结、
不编造结果、不重复同一失败调用、删除覆盖前先只读确认」。模型返回纯文本即视为完成，
因此循环天然会终止，不依赖猜步数。

### 4.3 空闲自驱

队列空、在线可用、距上次超过 `selfDriveIntervalMinutes` 时，从 `selfDriveGoals` 轮一条
**只读巡检**目标（磁盘剩余 / 高内存进程 / 工作区最近修改 / 系统启动时间），
`maxSteps = 3`。自驱目标完成后才汇报，中途不刷屏；`selfDriveIntervalMinutes = 0` 可完全关闭。

### 4.4 感知事件转目标

`AppController._listenPerceptionEvents` 把 Trigger 摘要翻译成目标：
复制英文 → 「读剪贴板翻译成中文」、复制 URL → 「用 http_request 看页面」、
复制数字串 → 「判断是电话/金额/编号」。事件本身仍只带模式标签，
原文由模型按需调用 `clipboard` 工具读取，不常驻事件与持久化记录。
气泡只在桌面宠物形态显示，自主执行不受窗口形态影响。

### 4.5 自主干活 / 学习沉淀闭环审查（2026-11-24）

| 能力 | 改造前 | 现在 | 落点 |
| --- | --- | --- | --- |
| 目标队列、重启续跑 | ✅ | ✅ | `GoalStore` / `agent.goals.v1` |
| 多步 ReAct 规划 | ✅（仅 OpenAI 协议） | ✅ + 经验注入 | `ToolProbe.plan` |
| 空闲自驱只读巡检 | ✅（仅在线） | ✅ | `selfDriveGoals` / `_maybeSelfDrive` |
| 感知事件转目标 | ✅ | ✅ | `_listenPerceptionEvents` |
| 步数 / 连败 / 超时熔断 | ✅ | ✅ | `AutonomyLoop._step` |
| **通过对话执行工具** | ❌ | ✅ | `ChatAgent` + `parseOfflineAction` |
| 情景记忆（事实抽取 / 日结 digest / 检索） | ✅ | ✅ | `MemoryService` |
| 任务结果进记忆 | ✅（一句话） | ✅ | `recordTask(tag: 'goal')` |
| **目标级经验复盘** | ❌ | ✅ | `ExperienceBank.record` |
| **经验回灌聊天 / 规划** | ❌ | ✅ | `recallForPrompt` → system / plan |
| **失败教训沉淀** | ❌ | ✅ | `ok=false` + 失败原因 |
| 经验可视化 / 清空 | ❌ | ✅ | 管理页「权限 → 学习沉淀」 |

学习闭环：`AutonomyLoop._finish` 与 `ChatAgent._afterRun` 把「目标 + 工具链 + 结论」写入
`agent.experience.v1`（滚动 200 条）→ 下次聊天 `buildAgentSystemPrompt` 与自主规划
`ToolProbe.plan` 都按中文双字 / 英文词元相似度召回最多 3 条，成功经验加权 → 模型复用走通的做法。

**刻意未做**：不自动把经验写成新的 `Skill`（动态提示词注入）。Skill 仍是 4 个静态文本模板，
避免模型自我扩权与提示词漂移；「越用越会」的收益由经验召回覆盖。日结 digest 仍只汇总事件，
但目标结论已通过 `recordTask` 进入事件流。

## 5. 审计

每次工具调用写一条 `AuditEntry`（`agent.audit.v1`，滚动 500 条）：

| 字段 | 说明 |
| --- | --- |
| `id` / `at` / `elapsedMs` | 时间戳与耗时 |
| `tool` / `source` | 工具名；`user` / `goal` / `trigger` / `mcp` 来源 |
| `argsSummary` | 稳定 JSON，**敏感键**（key/token/password/secret/authorization…）打码，截断 400 字 |
| `ok` / `outputSummary` | 成功与否、输出压缩空白后截断 500 字 |

审计失败只 `debugPrint`，绝不拖垮工具执行本身。管理页「最近动作」按时间倒序展示，
支持一键清空。

## 6. 安全边界：不是沙箱，是可撤销的授权

M5 明确**不**给能力设上限，改用三件事兜底：

1. **留痕**：所有调用可追溯，含自主发起的动作（来源 `goal`）。
2. **可撤销**：设置页「完整本机权限」一键全关、「一键暂停」立即停摆；细粒度 12 项可单独关。
3. **可熔断**：步数上限、连续失败、命令超时 kill、目标队列上限 50、
   模型输出截断、工具输出截断、自驱只读且限 3 步。

`file_delete` 刻意只接受单文件并拒绝目录；目录级删除必须走 `run_command` 明确写出整条命令，
由黑名单与审计兜住。`LaunchTool` 在 Windows 上经 `explorer.exe` 拉起 GUI 程序，
避免宿主 Job 对象回收子进程（2026-11-24 构建实测结论）。

## 7. 验收清单

- 「帮我看看 D 盘还剩多少」→ 自主目标 → `run_command` → 气泡汇报结果 → 审计里出现 `source=goal`。
- 「把这段文字写到 D:/AiPet/notes.md」→ `file_write` → 文件真实生成。
- 「打开记事本」→ `launch` 经 explorer.exe 启动，进程不被回收。
- 「截个屏」→ `screenshot` 在临时目录生成 PNG 并返回路径。
- 设置页关掉「完整本机权限」→ 再下指令得到「能力未授予」提示，审计记录失败原因。
- 点「一键暂停」→ 工具、感知、自主循环全部停摆；「恢复运行」后继续。
- 复制一段英文 → 自主目标读取剪贴板并尝试翻译；桌面形态同时冒气泡。
- 重启 App → 未完成目标从 `agent.goals.v1` 恢复并继续推进。
- **默认本地小脑**：在聊天里点「看看磁盘空间」→ `parseOfflineAction` 直接执行 `run_command`
  → 对话里返回真实磁盘数据，状态条显示「执行命令」。
- **在线模型**：「读一下 D:/AiPet/CHANGELOG.md 并总结最近三条」→ `ChatAgent` 多轮调用
  `file_read` → 结果回灌 → 给出总结；请求里带 `tools`，审计里 `source=user`。
- 执行过程中气泡 / 聊天窗口显示目标名、第几步、正在调用的工具；结束后显示完成或失败。
- 气泡紧贴宠物头顶（缩放宠物后仍然贴合），状态条不遮挡宠物。
- 完成一个目标后「权限 → 学习沉淀」出现记录；再派同类目标时，`plan` 请求里带「以往的经验」段。
- 系统提示词包含「完整本机权限」与工具清单，模型不再回答「我只是宠物 / 我没有权限」。

## 8. 已知边界

| 边界 | 说明 |
| --- | --- |
| 自主多步规划依赖 OpenAI 兼容协议 | `ToolProbe.plan()` 只发 `/chat/completions + tools`；Anthropic 协议下返回 `PlanFail`，自主循环走 `offlinePlan` 降级。**聊天主通道不受此限**：`ChatAgent` 同时实现 OpenAI `tool_calls` 与 Anthropic `tool_use` |
| 在线聊天依赖模型支持 function calling | 模型返回 400 / 忽略 tools 时，`ChatAgent` 抛错并退回流式聊天，界面提示「这轮没能走工具通道」；此时只有本地规则通道能执行操作 |
| 离线一次只做一步 | `parseOfflineAction` 是关键词 + 路径映射，可执行任意单步本机操作（含写操作），但不做多步推理；复杂任务交给在线模型或在后台排队 |
| 窗口/键鼠/截屏仅 Windows | 非 Windows 返回明确失败文案并建议改用 `run_command`；其余工具跨平台 |
| `input` 的打字走剪贴板 + Ctrl+V | 为支持中文；执行后会尽量还原原剪贴板内容（120ms 延迟） |
| 感知事件不存原文 | 原文按需由 `clipboard` 工具读取，避免事件流成为第二份隐私副本 |
| 黑名单不是沙箱 | 只拦 6 条不可逆系统级命令；关掉 `blockIrreversible` 后无任何命令拦截 |
| 长期在线依赖 App 常驻 | 执行循环就是 App 进程；M5 未做开机自启 / 独立后台服务 / 锁屏后继续运行。重启后未做完的目标会从 `agent.goals.v1` 恢复 |
