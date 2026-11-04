# 路线图

已经能跑通「照片 → 宠物 → 桌面陪伴 → 聊天 → 记住你 → 念给你听」的完整闭环。
下面是明确还没做、或只做了一半的部分，按建议的优先级排列。

## 已实现（本轮）

- **长期记忆**：`MemoryStore` 记录见面天数、摸头次数、聊过的话题（关键词正则）、里程碑短句，
  摘要拼进 system prompt；聊天页 🧠 按钮可查看 / 清除。
- **成长阶段**：互动点（摸头 1 / 聊一轮 2）驱动 初识 → 熟络 → 黏人 → 形影不离，
  进度条在记忆弹窗里，阶段写进提示词。
- **语音朗读**：`flutter_tts`（Windows SAPI / Android TTS），聊天页小喇叭 + 设置页开关，
  自动清洗情绪标签 / 颜文字 / markdown。
- **流式输出**：在线模型走 SSE 逐字吐字，聊天页显示流式气泡，失败整段降级到本地小脑。
- **托盘迁移到 nativeapi**：`TrayIcon` / `Menu` / `MenuItem` 新接口，鼠标穿透做成可勾选菜单项，
  图标直接用打进包里的 png；不再有 `deprecated_member_use` 忽略。
- **打包**：`scripts/build-msix.ps1` 生成 MSIX（测试证书签名，实测 22.3MB），
  `scripts/build-windows.ps1 -Zip` 出免安装压缩包（实测 17.4MB）。
- **CI**：`.github/workflows/ci.yml`（analyze + test + Windows 构建 + PetForge CLI 冒烟）。
- **照片宠物逐帧动画**（2026-11-01）：PetForge 新增 `animate=true`，默认用仿射变形生成
  `walk` / `run` / `lie` 帧（512×512、去重、可选 atlas），也可切 `engine=comfyui` 走本地
  ComfyUI（失败自动回退）；`PetStage` 修掉 `_clock` 无监听者的 bug，改用
  `AnimatedBuilder(Listenable.merge([_clock, _action]))` 真正逐帧播放。
  方案与免费生成途径见 [pet-generation.md](pet-generation.md)。
- **拖动走路 + 自定义宠物 id 修复**（2026-11-01）：拖动时复用 walk 真帧，朝向跟随
  拖动方向（`WindowService.onDragMove` → `AppController.facing`）；同时修复
  `Directory.uri.pathSegments.last` 末尾为空导致自定义宠物 id 全变成 `''`、
  重启后无法按 `activePetId` 选中的 bug。
- **Android 悬浮窗跟随当前宠物**（2026-11-01）：主 App 把 `petpack` + 目录写成
  `overlay_pet.json` 并用 `shareData` 推送，overlay 引擎只用 `dart:io` 读取；
  切宠物 2 秒内同步，读不到时回退内置 momo。已在 Android 15 模拟器验证
  `SYSTEM_ALERT_WINDOW`、覆盖桌面与点击互动。
- **多显示器游走**（2026-11-01）：`WindowService.glideBy` / 位置夹取改用窗口所在显示器的
  工作区（`visiblePosition + visibleSize`），不再固定 `getPrimaryDisplay()`；
  新增 `display_bounds.dart` 与 9 个边界单测（跨屏重叠、负坐标副屏、上方副屏、屏幕外回退）。
- **Windows 自动更新**（2026-11-01）：`UpdateService` 支持可配置 JSON 清单、语义化版本比较、
  下载到临时目录、sha256 / size 校验，以及启动 MSIX/EXE 或打开下载页；设置页新增「更新」卡片，
  启动时可自动检查。10 个单元测试覆盖版本、清单、HTTP 错误与下载校验。
- **Petdex 宠物导入**（2026-11-01）：读取本机 `~/.codex/pets/<slug>` 的 `pet.json` + 8×9/8×11
  图集，切成独立帧并映射成 walk / run / idle / hop / lie，照片宠物也能获得真帧动画；
  只导入本地素材，不打包画廊。3 个单元测试覆盖图集识别、扫描与真实 boba 导入。
- **ComfyUI 图生图流水线**（2026-11-01）：本机搭好 torch 2.11+cu128 / ComfyUI 0.14.1 /
  DreamShaper 8 / SD1.5 IP-Adapter；新增 `img2img_ipadapter.api.json` 与
  `tools/refine_pet_frames.py`。用已有姿势帧做低 denoise 精修，保留动作、锁住外形，
  已生成「有财（AI 精修）」walk/hop/lie 共 10 帧。

## 1. Android 验证（模拟器已通过，真机待验证）

APK 已出包（JDK 17 + Android SDK 36，`flutter build apk --release` →
`app/build/app/outputs/flutter-apk/app-release.apk`，60.3MB，悬浮窗服务与权限都已打进清单）。
已在 Android 15（API 35，x86_64 Google APIs）模拟器上验证：

- `SYSTEM_ALERT_WINDOW` 授权（`appops` = allow），`OverlayService` 以前台服务运行；
- 悬浮窗读取当前宠物（内置 doudou / mint / taro 与自定义照片宠物「有财」）；
- 主 App 切宠物后悬浮窗 2 秒内跟随；点击冒泡；按 Home 后仍覆盖在桌面上。

还需要真机确认：

- 部分厂商 ROM 对「后台启动前台服务 / 悬浮窗权限」的额外限制；
- 前台服务 `specialUse` 在 Play 上架时的说明文案要求；
- 桌面形态的 900×680 面板在小屏上是靠 `_MobileTab` 切换的，实际观感要再调。

## 2. 打包与分发（部分完成）

- Windows：MSIX + 压缩包都有了。MSIX 用的是 `msix` 包自动生成的**测试证书**，
  要正式分发得换代码签名证书（改 `pubspec.yaml` 的 `msix_config`）。
- Android 目前用 debug 签名，正式包要配 `key.properties`。
- 自动更新通道已实现：设置页可配置版本检查 JSON，支持下载、sha256 校验、启动 MSIX/EXE
  或打开下载页；详见 [update.md](update.md)。仍是整包更新，没有做增量补丁。

## 3. 体验细节

- 桌面上走动只做横向位移、碰到**当前显示器**的工作区边缘才停，不会避让窗口；
  已按窗口所在显示器夹取（支持左侧负坐标副屏、上下排列），但不会自动跨屏走到另一块屏。
  多显示器边界逻辑有独立单测 `app/test/display_bounds_test.dart`。
- 内置宠物的走 / 跑 / 躺已是逐帧动画（生成器逐帧重绘）；照片生成的宠物现在可由 PetForge
  输出 `walk` / `run` / `lie` 帧（默认程序化变形，0 成本；可选 ComfyUI 生成），
  详见 [pet-generation.md](pet-generation.md)。未开启动画时仍回退到纯程序化姿态。
- 记忆是「摘要级」的，没有用小模型做周期性压缩；话题提取只是关键词正则，够用但不聪明。
- 语音没有做「气泡还在、语音已结束」的对齐，也没有连续消息打断；长句不按标点切段。
- 主动行为已落地：按性格搭话 / 讨食 / 求摸 / 小跑，每 3~6 分钟一次，设置页「主动互动」可关；
  「宠物之间互动」「定时提醒」仍未做。

## 4. 工程质量

- 目前是 93 个 Dart 用例（含姿态数学、多显示器边界、自动更新、Petdex 导入、主动行为与 PetForge 端到端，服务未启动自动跳过）
  + 9 个 PetForge 单元测试（帧去重、图集、ComfyUI 占位符注入、假服务全链路）；没有 widget 测试和 Windows 端到端测试。
- 拆分前 `app_controller.dart` 1032 行、`panel_view.dart` 1546 行；拆分后见下方「本轮完善记录」。
- CI 已有 `.github/workflows/ci.yml`（analyze + test + Windows 构建 + PetForge CLI 冒烟），后续可补 widget 测试到流水线。
- 退出崩溃已修（2026-10-31）：托盘「退出」原走 `windowManager.destroy()`（内部 `PostQuitMessage(0)`，窗口未销毁即退出消息循环），runner 拆卸视图控制器时窗口过程向已释放引擎转发消息导致 APPCRASH（flutter_windows.dll）；改为 `close()` 走 WM_CLOSE 自然销毁路径，实测干净退出。
- 朗读闪退已修（2026-10-31）：flutter_tts 4.2.5 Windows 原生层把 Dart result 存进成员
  `speakResult` 且永不置空，`stop()` 与朗读完成回调（媒体线程）会对它二次 `Success(reply)`，
  同一 MethodResult 双重 reply → response handle UAF（flutter_windows.dll 0xc0000005）；
  快速连发消息（上一条未播完又 speak）时必踩。修复：`SpeechService` 不再开启
  `awaitSpeakCompletion(true)`，使 speakResult 保存/双 reply 路径不可达（result 立即单次
  reply），朗读状态由 start/completion handler 维护；已加回归测试锁定。
- 逐帧动画 / 昵称 / 默认小尺寸（2026-10-31）：petpack 新增 `animations` 段，内置宠物走 / 跑 / 躺
  为 flipbook 真帧动画（程序化姿态衰减到 25% 叠微动，自定义单图宠物仍走纯程序化姿态兜底）；
  宠物支持自定义昵称（`settings.petNames`，面板铅笔图标改名，空值恢复默认）；桌面默认大小改为
  原精灵的 1/4（`scale` 默认 0.25，`scaleV=2` 版本迁移，旧刻度一律废弃回默认），面板滑杆
  0.15~1.5 可调。
- 动作集扩充（2026-10-31，参考灵犀桌宠）：调研灵犀桌宠实现（xxlc.exe 原生壳 + ZIP 形象包 +
  AI 生成帧序列，标准动作：待机/工作/开心/失败/左右跑），对齐其动作集：新增开心跳（hop 4 帧）
  与委屈落地（drop 1~2 帧）逐帧动画（内置生成器程序化绘制，有财图生图生成），点击/松手落地
  自动播对应帧；`facing` 朝向 + 水平镜像实现「向左跑 / 向右跑」。

## 5. 剩余阻塞项（需要外部条件）

- **Android 真机**：模拟器（Android 15 / API 35）已验证悬浮窗授权、跟随当前宠物、
  点击互动和覆盖桌面；真机仍需确认厂商 ROM 的后台限制与小屏面板观感。
- **正式代码签名证书**：MSIX 目前用测试证书，正式分发需要购买证书并替换 `msix_config`。
- **ComfyUI checkpoint**：本机已装 ComfyUI Desktop，但 `models/checkpoints` 为空；
  默认程序化动画不依赖它，只有想用 AI 图生图补帧时才需要下载模型（SD1.5 约 2GB / SDXL 约 6.5GB）。

## 6. 本轮完善记录（2026-11-04）

### 架构拆分

| 文件 | 拆分后行数 | 职责 |
| --- | --- | --- |
| `state/app_controller.dart` | 1032 → 443 | 依赖装配、初始化、窗口形态、设置与退出 |
| `state/pet_behavior.dart` | 493 | 互动、拖动、空闲定时与主动行为 |
| `state/chat_coordinator.dart` | 146 | 聊天收发、流式输出、历史持久化 |
| `state/generation_coordinator.dart` | 162 | 照片生成与收养 |
| `state/update_coordinator.dart` | 187 | 自动更新、Petdex 导入、悬浮窗开关 |
| `state/controller_types.dart` | 47 | 枚举 + 主动行为权重纯函数 |

四个 coordinator 是 `on ChangeNotifier` 的 mixin，共享 `AppController` 的字段，
对外 API 完全不变（`app_controller.dart` 继续 `export` 枚举），UI 与测试无需改动。
`panel_view.dart` 1546 → 76 行，拆成 `panel_chrome.dart`（179）/`gallery_tab.dart`（436）/
`create_tab.dart`（486）/`settings_tab.dart`（420），入口路径不变。

### 新功能

- **主动行为**：`ProactiveKind { chat, treat, cuddle, zoomies }`，权重按 `personality.traits`
  计算（贪吃→讨食、黏人→求摸、元气→小跑），3~6 分钟触发一次；设置页「主动互动」可关，
  面板「逗一下」可立即触发。讨食期间点击 = 投喂，好感 +3 并播开心跳。
- **有财动作帧**：`tools/generate_pet_motion_frames.py` 用 Pillow 从 `base.png` 幂等生成
  `idle`(4) / `talk`(2) / `eat`(4) / `sleepy`(2) / `spin`(8) 共 20 帧，`PetMotion` 新增 `eat`；
  `PetStage` 在有 idle 呼吸帧时让位给表情 overlay，避免盖住 happy / love 等情绪。
  帧已同步到 `exports/有财` 与桌面端四个有财宠物目录。
- **按 Petdex 范式重做动画（后续反馈）**：上面的程序化整图仿射仍不对——
  walk 只有一只脚在动、其它动作果冻化，转圈是绕图像中心的 2D 旋转。
  改为 67 帧**分部件蒙皮**（九个部件、各自关节枢轴，可独立旋转/平移/缩放/压暗后加权合成）
  + 绕垂直轴的分部件偏转帧序列，左右朝向各一条独立序列，帧数对齐 Petdex 状态行；
  详见 [petdex.md](petdex.md) 与 [petpack.md](petpack.md#动画范式对齐-petdex)。
- **AI 补帧踩坑结论**：img2img 即使 denoise 提到 0.85 也换不出视角（仍是正面）；
  txt2img + IP-Adapter 能换姿态但身份漂移；求「四足站立」底图会得到拟人直立。
  单张正面图不含侧/背信息，真 8 方向只能靠单独绘制或训练角色 LoRA，
  详见 [petpack.md](petpack.md#方式四给已有的单图宠物补动作帧) 的对照表。
- **数据修复**：桌面端有财宠物包原本声明 `run` 动画却缺 `run_*.png`，已补齐；
  原 `petpack.json` 备份为同目录 `petpack.json.bak`。
- **设置**：新增 `proactive`（默认开、旧配置缺字段自动回落），开关变化会重排空闲定时器。

### 工程

- 初始化 Git 仓库并做基线提交；新增 `LICENSE`（MIT）、`CHANGELOG.md`；忽略发布产物。
- 文档与代码对齐：用例数 93、`scale` 范围、行数、章节编号，删除重复的 nuget 段落。
- 新增 7 个单元测试（主动行为权重 / 开关持久化 / eat 姿态）；`flutter analyze` 零问题。
- 交付形态：`scripts/build-portable.ps1` 出免安装绿色版（含中文名 exe 副本），
  `scripts/build-single-exe.ps1` 出单文件 `MomoPet.exe`（PyInstaller 自释放启动器，
  已实测从空目录单独运行可拉起宠物）。产物在 `dist/`，不进版本库。
- 修正 `scripts/plugin-links.ps1`：构建失败留下的「空普通目录」不再是链接，
  Flutter 会删掉它去建真符号链接而报 `ERROR_PRIVILEGE_NOT_HELD`；现在识别 reparse point
  并替换为目录联接，Flutter 3.47.9 重新构建通过（54.4s）。
