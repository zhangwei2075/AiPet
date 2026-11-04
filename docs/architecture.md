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
- **兜底**：照片生成的自定义宠物没有动画帧时（旧宠物包 / 生成时关闭动画），动作走纯程序化姿态
  （挤压 / 摆动 / 旋转）。
- **扩展动作**：`animations` 现在也认 `idle`（呼吸）、`talk`（说话）、`sleepy`（打盹）、
  `spin`（转圈）、`eat`（讨食点头）。有财的这 5 组帧由
  `tools/generate_pet_motion_frames.py` 从 `base.png` 程序化变形生成（20 帧，幂等可重跑），
  不依赖 ComfyUI。`PetMotion` 新增 `eat`，由主动讨食行为驱动，无帧时回退到 `motion.dart` 的点头姿态。
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
| `begging` | AppController | 躺倒求摸持续状态：`lieDown()` 触发，6 秒气泡 + 14 秒收起，任何互动（`wake()`）打断；躺倒时被摸奖励翻倍 |
| `eating` / `awaitingTreat` | AppController | 讨食动画播放中 / 12 秒投喂窗口；窗口内点击走 `feedTreat()`（好感 +3 并播开心跳） |

定时行为都集中在 `pet_behavior.dart` 的 `startIdleTimers()`：自动睡觉（90 秒无互动）、
桌面走动（26~56 秒随机一次，其中 30% 为小跑）、自动躺倒求摸（首次 35~75 秒，之后 80~150 秒）、
主动行为（180~360 秒一次）。仅在桌面宠物形态且空闲时触发，设置变化会重排定时器。

主动行为按 `personality.traits` 加权抽取（`controller_types.dart` 里的纯函数，可单测）：

```
traits（贪吃 / 黏人 / 元气 …）
   → proactiveWeights → random ticket → ProactiveKind
       chat    冒泡一句 catchphrase / 闲聊
       treat   begForTreat()：eat 帧 + 12 秒投喂窗口，点一下 = 投喂
       cuddle  lieDown() 求摸
       zoomies stroll(run: true) 小跑一圈
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
   ├─ 本地模式 → ChatService.local → LocalBrain.reply（关键词规则，永不失联）
   └─ 在线模式 → ChatService.sendStream → OpenAiBackend.streamReply
         ├─ 拼 systemPrompt（含记忆片段）+ 最近 10 条历史
         ├─ POST {baseUrl}/chat/completions，stream: true（25s 超时）
         ├─ 解析 SSE 增量逐段 yield，聊天页显示流式气泡
         └─ 出错 / 空回复 → 整段降级到 LocalBrain.reply
```

收尾统一走 `_finishReply`：落一条宠物消息、切情绪、（开了语音就）朗读、冒气泡、
把这一轮记进长期记忆。

`ChatResult.degraded` 标记是否走了兜底，`ChatView` 据此显示「在线模型没连上」的提示条。

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
