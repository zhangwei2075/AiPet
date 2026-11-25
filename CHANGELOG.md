# 更新日志

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号见 `app/pubspec.yaml`。

## [未发布]

## [0.2.0] - 2026-11-25

### 新增

- **M5.1：让对话真的能操作电脑 + 任务状态可视化 + 学习沉淀**。
  - **根因修复**：默认聊天后端是「本地小脑」，在线聊天又是纯文本流式请求（不带 `tools`、
    没有执行回路），系统提示词还写着「每次不超过 40 字 / 永远保持角色」——
    所以 M5 的 16 个工具在对话里根本用不上。新增 `agent/chat_agent.dart` 把聊天改成
    带 function calling 的多轮 ReAct（OpenAI `tool_calls` / Anthropic `tool_use` 双协议，
    最多 6 轮，结果回灌，工具统一走 `ToolRuntime`），失败时退回流式聊天并如实提示。
  - **系统提示词**：新增 `agent/system_prompt.dart`，最高优先级声明「完整本机权限」、
    列出 12 项能力与全部工具名、7 条执行准则（禁止说做不到、先做后说、多步连续调用、
    不做自我审查等），人格降级为语气参考；流式降级通道也带 `buildAgentPreamble`。
  - **离线可用**：`agent/offline_intent.dart` 新增 `parseOfflineAction`，把磁盘 / 进程 /
    窗口 / 列目录 / 读文件 / 搜索 / 截图 / 网址 / 跑命令 / 启动程序等中文指令直接映射成
    工具调用，**同步回结果到对话框**（本机工具都标了 slow，不做后台气泡汇报）；
    `autonomy.offlinePlan` 复用同一规则表。`ToolProbe.probe` 退出聊天主路径，
    不再让一句话打两次模型；`plan()` 改为高权限口径。
    Brain 里已失效的 `_executeIntent` 参数映射同步删除。
  - **任务状态**：新增 `agent/activity.dart`（`AgentActivity`），由 `ToolRuntime` 与
    `AutonomyLoop` 实时驱动；`SpeechBubble` / `BubbleHint` 内嵌 `TaskStatusChip`，
    `ChatView` 顶部新增状态条（目标、n/max 步、当前工具、最近动作）。
    气泡从窗口顶端改为 `bottom: petSize + 6`，紧贴宠物图片上方并按可用高度收缩行数。
  - **学习沉淀**：新增 `agent/experience.dart`（`ExperienceBank`，`agent.experience.v1`
    滚动 200 条）。目标完成/失败与带工具执行的聊天都会复盘「目标 + 工具链 + 结论」；
    下次聊天提示词与自主规划按词元相似度召回最多 3 条经验。
    管理页「权限」新增「学习沉淀」入口（查看 / 清空）。自主干活与记忆闭环的逐项审查见
    `docs/autonomy.md` §4.5。
  - **UI 提示**：聊天输入框改为「跟它说点什么，或让它操作电脑…」，快捷指令新增
    「看看磁盘空间 / 列出工作区文件 / 查看进程」；本地小脑状态文案改为「也能操作电脑」。
  - **测试**：新增 `test/agent_chat_test.dart`（提示词、离线路由、ChatAgent 工具回路与降级、
    审计来源、状态机、经验召回）。`flutter analyze` 零问题；`flutter test` 仍被本机
    Windows SDK 头文件缺失与 `reg.exe` 命令黑名单挡住，未绕过，需本地手动跑。
  - **文档**：`docs/autonomy.md` 新增 §3.1 / §3.2 / §4.5 并更新验收与边界；
    `docs/architecture.md` 同步 M1 链路图、权限执行图、聊天链路。

- **智能体 M5：本机全权限 + 自主执行（方向性变更）**。目标从「被约束的陪伴助理」改为
  「对这台电脑有完整操作面、能自己接活并持续推进」，规格见 `docs/autonomy.md`。
  - **权限与审计**：新增 `agent/permissions.dart`（12 项 `AgentCapability` 默认全开、
    一键急停、6 条不可逆命令黑名单、步数/超时/输出限额，落盘 `agent.permissions.v1`）、
    `agent/audit_log.dart`（参数脱敏、滚动 500 条、来源 user/goal/trigger/mcp）、
    `agent/tool_runtime.dart`（`_GovernedTool` 装饰者：能力校验 → validate → 执行 → 审计）。
    M1 老工具与 MCP 远程工具也全部经 `wrap()` 注册，不存在绕过权限的入口。
  - **13 个本机工具**：`agent/tools/system_tools.dart`
    （`run_command` / `process` / `launch` / `http_request`，`Process.start` + 超时 kill，
    GUI 经 explorer.exe 启动）、`file_tools.dart`
    （读/写/列/搜/删单文件/写剪贴板）、`desktop_tools.dart`
    （user32 FFI 窗口与键鼠、PowerShell 截屏）。`PetTool` 新增 `capability` / `validate`。
  - **通用执行通道**：`Brain._executeIntent` 的 `default` 不再返回 null，
    改为 `GenericToolIntent`（快工具同步回结果）/ `SlowToolIntent`（慢工具后台汇报），
    任意注册工具都能被模型点名执行；`looksLikeCommand` 扩了本机操作词表但不误伤闲聊。
  - **自主循环**：`agent/autonomy.dart` 的 `Goal` / `GoalStore`（`agent.goals.v1`，重启续跑）/
    `AutonomyLoop`（目标 → 规划 → 工具 → 复盘 → 继续），`ToolProbe.plan()` 带历史做多步
    function calling；步数上限 12、连续 2 次失败熔断、20 秒计划超时、离线 `offlinePlan()`
    只读降级、空闲 30 分钟自发只读巡检（固定 3 步）。由 Brain 的 20 秒心跳驱动，串行后台执行。
  - **感知转目标**：`AppController._listenPerceptionEvents` 把剪贴板模式事件翻译成自主目标
    （翻译 / 看网页 / 识别数字串），由模型决定调哪个工具，不再只是冒气泡。
  - **默认策略变更**：`QuietHours` 22–08 静默 / 6 次 / 90 秒 → 全天允许 / 240 次 / 10 秒；
    `perceptionEnabled`、`autonomyEnabled`、`BrainPack` 工具与 Trigger 缺省全部启用；
    `speculative` 每日草稿 3 → 12。旧陪伴模式仍可在 `brainpack.quietHours` 配回。
  - **UI**：设置页新增「完整本机权限」「自主执行」；管理页新增第五分段「权限」
    （总开关、一键暂停、12 项能力、拦截不可逆命令、派目标、目标队列、最近动作）。
  - **文档**：新增 `docs/autonomy.md`；`super-agent-refactor.md` 升 v2 并修订 §3/§6 旧边界结论，
    `architecture.md` 新增 M5 章节，`roadmap.md` §6 同步 M1–M5 状态。
  - **测试**：新增 `test/autonomy_test.dart`（权限/审计/工具/目标/循环 14 个用例），
    同步改写 `test/superagent_test.dart`、`test/manage_test.dart` 里依赖旧默认值的断言。
    `flutter analyze` 零问题；`flutter test` 仍被本机 Windows SDK 头文件缺失
    （`windows.h` / `crtdbg.h` / `dwmapi.h`）与命令黑名单挡住，未绕过，需在本地环境手动跑。

- **功能开关说明（Tooltip）**：新增 `ui/feature_help.dart`（`FeatureHelp` 整行 Tooltip、
  `HelpBadge` ⓘ 标记、`helpTitle`），`SettingRow` 增加可选 `help`。
  设置页 17 个 SettingRow + 对话后端分段（大小 / 置顶 / 穿透 / 散步 / 睡觉 / 主动互动 /
  环境感知 / 完整本机权限 / 自主执行 / 悬浮窗 / 接口协议 / 朗读 / 声线 / 启动检查更新 /
  清空对话 / 供应商 / 模型）、
  插件分段 16 个工具 + 2 个触发器、权限分段 4 个总开关 + 12 项能力 + 一键暂停 +
  3 个留痕动作、技能列表，全部配有中文说明，悬停或长按显示，不占常驻版面。
  说明写清「能做什么 / 关掉会怎样 / 风险边界」。新增 `test/feature_help_test.dart` 4 个用例。

- **托盘与任务栏图标换成「有财」**：新增幂等脚本 `tools/make_youcai_icons.py`，
  以 `exports/有财/base.png` 为母版生成暖色圆角底板的 256×256 `app_icon.png` 和
  8 帧多尺寸 ICO（`app_icon.ico` / `tray.ico` / `windows/runner/resources/app_icon.ico`）。
  小尺寸（≤32px）改用头部特写 + 纯奶油底，托盘里脸更清楚；托盘 tooltip 改为
  「有财 · 摸摸宠 MomoPet」。任务栏走 `Runner.rc` 的 `IDI_APP_ICON`，与托盘同源。

- **声线设置**：设置 → 语音新增「声线」下拉（默认/温柔/活泼/沉稳）。Windows SAPI 不支持
  枚举 voice，改用 `flutter_tts` 的语速+音调组合实现，全平台可用；切换即时生效，
  选择随设置落盘。新增 2 个往返/参数用例。
- **面板拖动**：设置/画廊等面板模式新增顶部拖动把手（宠物模式的拖拽手势在面板下不可用），
  接 `beginWindowDrag()`，面板也可随意移动。
- **界面优化**：插件分段的同名 `clipboard` 改造为「剪贴板 · 工具 / 剪贴板 · 感知」并分组
  （工具/触发器）；设置页与各卡片间距整体收紧；面板卡片 padding 缩小。

- **智能体管理页**（设置 → 智能体）：技能 / 记忆 / 插件 / MCP 四合一。
  `agent/skill.dart` 技能系统（翻译/总结/解释/续写 4 个内置提示词模板，按触发词注入
  system prompt，开关落盘 `skill_store.dart`）；`agent/mcp/` MCP 客户端（JSON-RPC 2.0，
  initialize + tools/list + tools/call，远程工具包装成慢工具进 Brain 注册表，
  URL 只允许 https 或本机、远程工具不得覆盖内置工具名）；插件分段复用 brainpack 白名单开关；
  记忆分段直达现有情景记忆页。新增 10 个用例（`test/manage_test.dart`）。
- **界面极简**：移除设置/画廊/生成/记忆/侧栏中的解释性副标题与说明段落（19 处副标题降到 6，
  保留的是状态值与平台必要提示），删掉侧栏「小提示」卡片与 PetForge 启动命令说明。

- **Super-agent M3 感知与自治**：`agent/triggers/` 新增 `PetTrigger` 抽象与事件总线；
  `ClipboardTrigger` 只检测 URL / 英文 / 数字模式（原文不落盘）、`AppFocusTrigger` 用
  dart:ffi 读前台窗口并只分类不存标题；  `QuietHours` 静默时段 22:00–08:00 +
  每日 6 次预算 + 90 秒冷却，`perceptionEnabled` 总开关默认关闭。
  （以上为 M3 实施时默认值，M5 已改为全天允许 / 240 次防抖 / 10 秒冷却、感知默认开启。）
  `agent/watchdog.dart` 巡视卡死（2 分钟）/ 重试超限（3 次）/ 错过（30 分钟）三类异常，
  写回任务表并给一句降级台词。异步 ReAct：`SlowToolIntent` 让慢工具先回「我去看看」，
  后台执行完再汇报，聊天流不阻塞。
- **Super-agent M4 插件化与预判**：`agent/brainpack.dart` 仿 petpack 的声明式能力清单，
  白名单外条目跳过并记 warning（配置不是代码，不执行任意 Dart / 不接受任意 URL）；
  `agent/speculative.dart` 投机执行按时段与临近日程预生成关怀草稿，缓存后由 Trigger
  消费输出，每天最多 3 条、静默时段不生成。  新增 12 个 M3/M4 用例
  （`test/superagent_test.dart`），`flutter analyze` 零问题。
  `docs/super-agent-refactor.md` 当时标记 M1–M4 全部实施（M5 后已升 v2，标记 M1–M5）。

- **对话模型供应商化（按 DeepSeek Harness 接入模式）**：`lib/models/model_presets.dart`
  改为「供应商 = 一个 Key + 一组模型目录」——设置页两级下拉（供应商 → 模型），
  选中供应商只填 Key，协议与地址自动套用，和 Harness「设置 → 模型 → 选供应商 → 粘贴 Key」
  一致。**OpenCode Go / 按量排在前面**：一个 `oc_sk_` Key 走遍 DeepSeek / GLM / Kimi /
  Qwen，目录含 6 个常用模型；Go 端点 `/inference/go/{openai|anthropic}/v1`，
  按量去掉 `/go`。Go 要求的 `x-opencode-session` 稳定会话头由 Key+地址派生 FNV-1a
  （跨重启稳定、不泄露 Key），聊天 / 流式 / 工具探测 / Anthropic 全部自动带。
  其余供应商：DeepSeek / GLM Coding Plan / 百炼 Coding Plan / Kimi / OpenAI / Ollama。
  端点按 2026-11 官方文档核对（DeepSeek 已弃用 `deepseek-chat`，百炼 Coding Plan 的
  `sk-sp-` Key 必须与 `/apps/anthropic` 配套）。`ToolProbe` 只支持 OpenAI 协议，
  Anthropic 下工具调用降级，设置页如实标注。修复「测试连接」漏带 `apiProtocol` 的 bug。
  新增 12 个预设/会话头单测（`settings_test.dart`）与 4 个请求头集成测试
  （`opencode_headers_test.dart`，MockClient 校验路径与头）。

- **智能体 M2 情景记忆**：`lib/agent/memory/` 新增按天分区的情景存储、规则抽取器
  （敏感信息过滤）、打分检索（importance + 时间衰减 + 中文 bigram）、日结摘要
  （在线 LLM 精摘 / 离线模板兜底）。对宠物说「我明天要早点睡」「我最喜欢吃辣」
  会被记成第三人称事实，隔天聊天能接上；设提醒等任务结果也进入记忆。
  聊天面板新增情景记忆管理页（按天查看/单日清除/一键全清/记录总开关），
  「让它忘掉」同时清计数与情景两层。容量护栏：单日 80 / 总量 400 / 上下文 2000 字符硬预算。
  新增 24 个用例，全量 149 全绿。

- **智能体 M1 最小闭环（Super-agent 化第一期）**：`lib/agent/` 新增 Brain(Router)/
  TaskSession/TaskStore/工具注册表。对宠物说「提醒我 15:30 喝水」「每天早上 8 点叫我跑步」
  「取消提醒」「陪我散个步」「跳一下」「剪贴板里有什么」即可触发对应任务；
  提醒任务持久化，重启不丢，错过的在 30 分钟内补报。中文时间解析覆盖
  HH:MM / X点半 / 中文数字 / 上午下午 / X分钟后 / 明天后天。
  在线模型走 function calling，本地模型走规则表双通道。新增 33 个用例，全量 136 全绿。

- **有财动画 v2 重制（形象不变）**：111 帧 / 17 个动作，由分部件蒙皮重新生成 ——
  walk/run 改用纯侧面底图 + 大摆幅步态（摆腿 0.14→0.22/0.27 rad、抬脚 16→24/30px、
  躯干俯仰），run 改为**飞奔步态**（前后腿各自成对、腾空相身体伸展）；
  idle 加耳朵周期抖动与尾巴摇摆，eat/angry/lie 全面加大幅度。
  修复向右走时朝向翻反的 bug：侧面帧统一镜像成「原画朝左」（项目约定），
  `walk_left` / `run_left` 改为直接引用朝左的同一批文件。
- **六个新交互动作**：`stretch` 伸懒腰（play bow）/ `wag` 开心摇尾 / `shake` 抖毛 /
  `bark` 汪汪叫 / `sniff` 嗚探 / `celebrate` 作揆庆祝（全部有程序化姿态兑底，
  旧宠物包也能响应新交互）。
- **对应的新交互逻辑**：拖拽快速左右甩动后落地抖毛（+晕乎乎气泡）、
  吃到零食作揖庆祝 + 摇尾巴、睡醒伸懒腰 + 打哈欠、躺倒时点击 = 揉肚子（双倍好感 + 摇尾）、
  摸头好感 >10 摇尾巴、长按抚摸松手后摇尾、漫步落点两成概率嗅探、
  精力旺盛时先汪一声再跑、戳它有四成概率汪汪回应。
  `PetStage` 一次性帧动作（spin/shake/celebrate/stretch/bark）按 petpack 帧数/fps 精确对齐时长。
- 踩坑沉淀：嘴部椭圆在头部饱和权重区内，头部大变换时嘴/耳必须继承完整变换，
  否则拉扯出鬼影；大位移部件要提 gain 饱和椭圆消残影（详见 docs/petpack.md）。
- 测试：`motion_test.dart` 补 6 个新动作姿态用例，`app/test` 共 103 个用例全绿，`dart analyze` 零问题。

- 宠物主动行为：按宠物性格触发主动搭话 / 讨食 / 求摸 / 小跑，可在设置里开关。
- 有财专属动作帧：待机呼吸、进食、打盹、说话与转圈，配合贪吃／元气／黏人性格的专属台词。
- `LICENSE`（MIT）与本更新日志；仓库初始化，补齐发布产物的忽略规则。
- 新增 7 个单元测试（主动行为权重 / 开关持久化 / eat 姿态），`app/test` 共 93 个用例。
- 双击可用的 Windows 产物：`scripts/build-portable.ps1` 出绿色版目录（含中文名 exe 副本），
  `scripts/build-single-exe.ps1` 出真正的单文件 `MomoPet.exe`（内嵌绿色版，首次运行自释放）。
  两者都在 `dist/`，属构建产物不进版本库。
  启动器加固：释放写完整性标记（防半成品运行时被当成已装好）、自动清理旧版本释放目录、
  子进程带 `CREATE_BREAKAWAY_FROM_JOB`（防宿主 Job 对象连带回收，被拒绝时退回普通创建）、
  启动后观察 3 秒记录子进程早退；诊断信息写 `%LOCALAPPDATA%\MomoPet\launcher.log`。
- 有财的 AI 视角底图：用内置出图模型（多图参考）生成**四张**视角图 ——
  走路的四足站姿侧前 3/4 与背面、转圈的**坐姿**侧前与**坐姿**背面。
  四足站姿四腿分开、服装与毛色与主帧一致；坐姿两张把臀部落点、后腿折叠、前爪撑地
  写死进提示词，姿态才和 `base.png` 对齐（只说「same dog, side view」会出四足站立）。
  产物在 `exports/有财/_ai/`，对照见 `docs/images/youcai-ai-views.jpg`（站姿）与
  `docs/images/youcai-sit-views.jpg`（坐姿）。
- `tools/normalize_ai_frames.py`：`background: transparent` 时灵时不灵，会返回
  **真透明通道 / 纯白底 / 画进图片里的假棋盘格**三种东西，分别处理：原生 alpha 直接沿用、
  纯白底走四角泛洪、棋盘格按「中性灰」判定后泛洪（亮格纯白、暗格约 220，与白描边同为中性色，
  颜色阈值分不开）。去背后丢掉面积 < 最大前景 1% 的碎块，否则棋盘格角落的一两个残点
  会把 bbox 拉到画布边缘、让对齐缩放整体算错；去背失败时直接报错退出，不再静默产出烂图。
  `--align-to` 按参考帧主体高度占比缩放并对齐贴地线，保证换视角不跳大小。
- 转圈改用**坐姿四视角**：八帧 = 正面 / 坐姿侧前 / 坐姿背面 / 侧前镜像 4 个真实视角
  + 4 个柱面压窄过渡帧，180° 看到的是真背面（后脑、耳背、连帽、胸背带交叉、尾巴居中），
  不再是一张压窄的正脸。过渡帧不做淡化 —— 两视角各半 alpha 会重影成双头双尾；
  压窄是单调变化，12fps 下读得出「正在侧过去」。缺视角或加 `--no-spin-views` 时退回单图蒙皮。

### 优化
- 动作帧生成器支持**三套部件标定**：`FRONT`（正面坐姿）、`SIDE`（四足站立侧前 3/4）与
  `PROFILE`（**纯侧面 90°**，`_ai/side_profile_raw_cut.png`，后腿不被下摆遮挡）。
  `walk` / `run` 优先走 `PROFILE`，腿绕肩 / 胯前后摆动、对角成对，
  修掉「只有一只脚在动」——正面坐姿的四条腿在画面上本就叠在一起。
  侧面步态补了四处必要修正：绕枢轴旋转会让脚沿圆弧下移、底图脚底又贴着画布底边，
  故做垂直反向补偿把支撑相的脚锁在地面；超高斯权重的长尾会把卫衣下摆像素搬成半透明拖影，
  故做 smoothstep 软截断；腿 / 尾改用**椭圆内饱和的 rigid 权重**，
  消灭原位描边与旋转后描边的双重曝光；**摆幅上限 0.14 rad**（run 0.19）——
  椭圆遮罩固定而内容随腿旋转，摆幅一大腿的白描边就扫进空档拖出弧形细丝。
- `walk_left` / `run_left` 改为真正的水平镜像帧文件（共 83 帧），
  不再用倒序播放假装反向 —— 倒序会让脚往回迈。

### 优化

- `AppController` 按「宠物行为 / 聊天 / 生成 / 更新」拆分为独立 mixin，状态中枢只保留装配与窗口形态。
- `panel_view.dart` 按 Tab 拆为独立组件文件，入口路径保持不变。
- 动作帧生成器从「局部位移场」升级为**分部件蒙皮**：身体拆成 head / 双耳 / 嘴 / 躯干 /
  左右前脚 / 后脚 / 尾巴 九个部件，各有自己的关节枢轴，可独立旋转、平移、缩放、压暗后
  按权重合成。耳朵滞后甩动、尾巴摇、嘴张合、四肢各自动，都不再牵动整张图。
- 走路步态改为「竖直抬脚 + 内收 + 脚掌拉伸 + 2 倍频重心转移」：绕肩大角度旋转会让脚向两侧甩
  （读起来像劈叉），改为竖直抬脚后才是正面视角的迈步；2 倍频重心转移把两个半周期区分开。
- `spin` 帧号改为按圆周等分，让 90°/270° 最窄帧正好落在镜像切换点，消掉硬切跳变。

### 修正

- 文档与实际代码对齐：Dart 用例数 60 → 93、`AppController` 行数、缩放范围 0.6~1.8 → 0.15~1.5。
- 删除 `docs/platforms.md` Android 章节里误重复的 Windows nuget 段落，补齐路线图章节编号。
- 桌面端有财宠物包声明了 `run` 动画却缺 `run_*.png`，已补齐帧文件；原 `petpack.json`
  备份为同目录 `petpack.json.bak`。
- 修正 `showBubble` 的挤压格式；设置开关变化后重排空闲定时器，避免旧定时器沿用旧配置。
- 有财转圈帧 `spin_2` / `spin_6` 原本被压成约 100px 的竖条；先改为「倾斜 + 小跳 + 半程翻面」
  过渡，最终改成绕垂直轴的分部件偏转（头保持宽度、躯干按 |cos| 收窄），形象不再被压扁。
- 按 [Petdex](docs/petdex.md) 范式重做动画：旧版对整张图做仿射变形，
  walk 帧差异区域恒为 `x=59~512, y=22~512`（整只狗一起动），导致只有一只脚在动；
  转圈用 `rotation: 2πp` 是绕图像中心的 2D 旋转而非水平面转身。
  现改为头/躯干/四足/尾/嘴的**局部位移场**（67 帧、脚底锚定、四足相位差 π），
  `spin` 改为绕垂直轴的方向帧序列（y 恒定、无 2D 旋转），
  左右朝向各一条独立序列 `walk_left` / `run_left`；`PetdexImporter` 同步支持第 2 行。

## [0.1.0] - 2026-11-01

首个可运行版本：

- Windows 透明置顶桌宠（鼠标穿透、托盘、拖动、游走、睡觉、多显示器）。
- 照片生成宠物（PetForge 抠图 / 贴纸化 / 配色 / 性格 / 锚点）与离线徽章兜底。
- 逐帧动画 walk / run / lie / hop / drop，拖动走路与朝向翻转。
- 聊天：本地小脑、OpenAI 兼容后端、流式输出、失败降级。
- 长期记忆、成长阶段、语音朗读、昵称、自动更新、Petdex 导入。
- Android 系统悬浮窗、MSIX / 免安装压缩包打包、GitHub Actions CI。
