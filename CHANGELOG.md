# 更新日志

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号见 `app/pubspec.yaml`。

## [未发布]

### 新增

- 宠物主动行为：按宠物性格触发主动搭话 / 讨食 / 求摸 / 小跑，可在设置里开关。
- 有财专属动作帧：待机呼吸、进食、打盹、说话与转圈，配合贪吃／元气／黏人性格的专属台词。
- `LICENSE`（MIT）与本更新日志；仓库初始化，补齐发布产物的忽略规则。
- 新增 7 个单元测试（主动行为权重 / 开关持久化 / eat 姿态），`app/test` 共 93 个用例。
- 双击可用的 Windows 产物：`scripts/build-portable.ps1` 出绿色版目录（含中文名 exe 副本），
  `scripts/build-single-exe.ps1` 出真正的单文件 `MomoPet.exe`（内嵌绿色版，首次运行自释放）。
  两者都在 `dist/`，属构建产物不进版本库。

### 优化

- `AppController` 按「宠物行为 / 聊天 / 生成 / 更新」拆分为独立 mixin，状态中枢只保留装配与窗口形态。
- `panel_view.dart` 按 Tab 拆为独立组件文件，入口路径保持不变。

### 修正

- 文档与实际代码对齐：Dart 用例数 60 → 93、`AppController` 行数、缩放范围 0.6~1.8 → 0.15~1.5。
- 删除 `docs/platforms.md` Android 章节里误重复的 Windows nuget 段落，补齐路线图章节编号。
- 桌面端有财宠物包声明了 `run` 动画却缺 `run_*.png`，已补齐帧文件；原 `petpack.json`
  备份为同目录 `petpack.json.bak`。
- 修正 `showBubble` 的挤压格式；设置开关变化后重排空闲定时器，避免旧定时器沿用旧配置。
- 有财转圈帧 `spin_2` / `spin_6` 原本被压成约 100px 的竖条；改用倾斜 + 小跳 + 半程翻面，
  8 帧最窄 0.86 倍，形象完整（几何问题，非画质问题，无需上生成模型）。
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
