import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';

/// 系统托盘：显示/隐藏、打开聊天、管理、退出。
///
/// 用的是 `tray_manager` 0.8 的 nativeapi 新 API（TrayIcon / Menu / MenuItem），
/// 不再走 0.5.x 的 deprecated 兼容桥。菜单项用 `MenuItemClickedEvent.itemId`
/// 路由到对应的回调；鼠标穿透是一个可勾选菜单项，状态由 [setClickThrough] 同步。
class TrayService {
  TrayService({
    required this.onToggleVisibility,
    required this.onOpenChat,
    required this.onOpenPanel,
    required this.onToggleClickThrough,
    required this.onQuit,
  });

  final VoidCallback onToggleVisibility;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenPanel;
  final VoidCallback onToggleClickThrough;
  final VoidCallback onQuit;

  TrayIcon? _trayIcon;
  Menu? _menu;
  final Map<MenuItemId, String> _keysByItem = {};
  final Map<String, MenuItem> _itemsByKey = {};
  final List<ListenerId> _listeners = [];
  bool _ready = false;

  static const _keyToggle = 'toggle';
  static const _keyChat = 'chat';
  static const _keyPanel = 'panel';
  static const _keyClickThrough = 'clickThrough';
  static const _keyQuit = 'quit';

  Future<void> init() async {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;
    try {
      final trayIcon = TrayIcon.create();
      if (trayIcon == null) return;
      _trayIcon = trayIcon;

      // 图标直接用打进包里的 png，不再落临时文件。
      final icon = ImageAsset.fromAsset('assets/icons/app_icon.png');
      if (icon != null) trayIcon.icon = icon;
      trayIcon.setTooltip('摸摸宠 · MomoPet');
      trayIcon.setContextMenuTrigger(ContextMenuTrigger.rightClicked);

      final menu = Menu.create();
      if (menu == null) {
        trayIcon.dispose();
        _trayIcon = null;
        return;
      }
      _menu = menu;
      _addItem(_keyToggle, '显示 / 隐藏宠物');
      _addItem(_keyChat, '和它说说话');
      _addItem(_keyPanel, '宠物与设置');
      menu.addSeparator();
      final clickItem = _addItem(_keyClickThrough, '鼠标穿透（点穿桌面）');
      clickItem?.state = MenuItemState.checked;
      menu.addSeparator();
      _addItem(_keyQuit, '退出');

      trayIcon.setContextMenu(menu);
      _listeners.add(trayIcon.addListener(_onTrayEvent));
      trayIcon.setVisible(true);
      _ready = true;
    } catch (error) {
      debugPrint('tray init failed: $error');
    }
  }

  MenuItem? _addItem(String key, String label) {
    final menu = _menu;
    if (menu == null) return null;
    final item = MenuItem.createWithLabelAndType(label, MenuItemType.normal);
    if (item == null) return null;
    menu.addItem(item);
    _itemsByKey[key] = item;
    _keysByItem[item.id] = key;
    _listeners.add(item.addListener((event) {
      if (event is MenuItemClickedEvent) _onItemClicked(key);
    }));
    return item;
  }

  void _onTrayEvent(TrayIconEvent event) {
    if (event is TrayIconClickedEvent) {
      onToggleVisibility();
    } else if (event is TrayIconRightClickedEvent) {
      _trayIcon?.openContextMenu();
    } else if (event is TrayIconDoubleClickedEvent) {
      onOpenChat();
    }
  }

  void _onItemClicked(String key) {
    switch (key) {
      case _keyToggle:
        onToggleVisibility();
      case _keyChat:
        onOpenChat();
      case _keyPanel:
        onOpenPanel();
      case _keyClickThrough:
        onToggleClickThrough();
      case _keyQuit:
        onQuit();
    }
  }

  /// 鼠标穿透状态变化时，同步菜单项的勾选与文案。
  void setClickThrough(bool enabled) {
    final item = _itemsByKey[_keyClickThrough];
    if (item == null) return;
    item.state = enabled ? MenuItemState.checked : MenuItemState.unchecked;
    item.label = enabled ? '鼠标穿透（已开启）' : '鼠标穿透（已关闭）';
  }

  Future<void> destroy() async {
    if (!_ready) return;
    _ready = false;
    final trayIcon = _trayIcon;
    final menu = _menu;
    for (final listener in _listeners) {
      if (trayIcon != null) trayIcon.removeListener(listener);
      for (final item in _itemsByKey.values) {
        item.removeListener(listener);
      }
    }
    _listeners.clear();
    _keysByItem.clear();
    _itemsByKey.clear();
    menu?.clear();
    menu?.dispose();
    trayIcon?.setVisible(false);
    trayIcon?.dispose();
    _trayIcon = null;
    _menu = null;
  }
}
