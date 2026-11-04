# 更新日志

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号见 `app/pubspec.yaml`。

## [未发布]

### 新增

- 宠物主动行为：按宠物性格触发主动搭话 / 讨食 / 求摸 / 小跑，可在设置里开关。
- 有财专属动作帧：待机呼吸、进食、打盹、说话与转圈，配合贪吃／元气／黏人性格的专属台词。
- `LICENSE`（MIT）与本更新日志；仓库初始化，补齐发布产物的忽略规则。

### 优化

- `AppController` 按「宠物行为 / 聊天 / 生成 / 更新」拆分为独立 mixin，状态中枢只保留装配与窗口形态。
- `panel_view.dart` 按 Tab 拆为独立组件文件，入口路径保持不变。

### 修正

- 文档与实际代码对齐：Dart 用例数 60 → 86、`AppController` 行数、缩放范围 0.6~1.8 → 0.15~1.5。
- 删除 `docs/platforms.md` Android 章节里误重复的 Windows nuget 段落，补齐路线图章节编号。
- 修正 `showBubble` 的挤压格式。

## [0.1.0] - 2026-11-01

首个可运行版本：

- Windows 透明置顶桌宠（鼠标穿透、托盘、拖动、游走、睡觉、多显示器）。
- 照片生成宠物（PetForge 抠图 / 贴纸化 / 配色 / 性格 / 锚点）与离线徽章兜底。
- 逐帧动画 walk / run / lie / hop / drop，拖动走路与朝向翻转。
- 聊天：本地小脑、OpenAI 兼容后端、流式输出、失败降级。
- 长期记忆、成长阶段、语音朗读、昵称、自动更新、Petdex 导入。
- Android 系统悬浮窗、MSIX / 免安装压缩包打包、GitHub Actions CI。
