/// 应用界面形态：只有宠物 / 聊天 / 管理面板。
enum WindowMode { pet, chat, panel }

extension WindowModeSize on WindowMode {
  bool get isPanel => this == WindowMode.panel;
}
