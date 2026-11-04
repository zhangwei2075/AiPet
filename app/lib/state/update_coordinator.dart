import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/memory_store.dart';
import '../data/pet_repository.dart';
import '../data/settings_store.dart';
import '../mobile/overlay_pet.dart';
import '../models/chat.dart';
import '../models/pet.dart';
import '../models/settings.dart';
import '../services/petdex_importer.dart';
import '../services/update_service.dart';
import 'controller_types.dart';

/// 自动更新、Petdex 导入与 Android 悬浮窗开关。
mixin UpdateCoordinator on ChangeNotifier {
  AppSettings get settings;
  set settings(AppSettings value);
  String get currentVersion;
  UpdateInfo? get availableUpdate;
  set availableUpdate(UpdateInfo? value);
  bool get checkingUpdate;
  set checkingUpdate(bool value);
  bool get downloadingUpdate;
  set downloadingUpdate(bool value);
  double get updateProgress;
  set updateProgress(double value);
  String? get updateError;
  set updateError(String? value);
  String? get updateStatus;
  set updateStatus(String? value);
  bool get importingPetdex;
  set importingPetdex(bool value);
  bool get overlayActive;
  set overlayActive(bool value);
  bool get isMobile;
  Pet? get active;
  set active(Pet? value);
  List<Pet> get pets;
  set pets(List<Pet> value);
  List<ChatMessage> get messages;
  set messages(List<ChatMessage> value);
  int get affection;
  set affection(int value);
  String? get chatError;
  set chatError(String? value);
  UpdateService get updates;
  SettingsStore get store;
  PetRepository get repo;
  MemoryStore get memory;
  PetdexImporter get petdex;
  String displayName(Pet pet);
  Future<void> closePanel();
  void showBubble(String text, {PetMood mood = PetMood.talk, int duration = 6});
  void emitBurst(PetBurst kind);

  Future<void> toggleMobileOverlay() async {
    if (!isMobile) return;
    if (overlayActive) {
      await MobileOverlay.hide();
      overlayActive = false;
    } else {
      overlayActive = await MobileOverlay.show(pet: active);
      if (!overlayActive) {
        chatError = '没有获得悬浮窗权限，无法在其他 App 上方显示';
      }
    }
    notifyListeners();
  }

  /// 检查更新。`silent` 用于启动时自动检查，不把错误弹到设置页。
  Future<void> checkForUpdates({bool silent = false}) async {
    final url = settings.updateManifestUrl.trim();
    if (url.isEmpty) {
      if (!silent) {
        updateError = '请先填写版本检查地址';
        updateStatus = null;
        notifyListeners();
      }
      return;
    }
    if (checkingUpdate) return;

    checkingUpdate = true;
    updateError = null;
    if (!silent) {
      updateStatus = '正在检查更新…';
      notifyListeners();
    }
    try {
      final info = await updates.check(manifestUrl: url, currentVersion: currentVersion);
      availableUpdate = info;
      updateStatus = info == null
          ? '已是最新版本（v$currentVersion）'
          : '发现新版本 v${info.version}';
    } catch (error) {
      availableUpdate = null;
      if (!silent) updateError = '检查更新失败：$error';
    } finally {
      checkingUpdate = false;
      notifyListeners();
    }
  }

  /// 下载安装包并启动安装；非安装包链接改为打开下载页。
  Future<void> downloadAndInstallUpdate() async {
    final info = availableUpdate;
    if (info == null || downloadingUpdate) return;
    if (!info.isInstaller) {
      await openUpdatePage();
      return;
    }

    downloadingUpdate = true;
    updateProgress = 0;
    updateError = null;
    notifyListeners();
    try {
      final directory = await getTemporaryDirectory();
      var lastPercent = -1;
      final file = await updates.download(
        info,
        directory: directory,
        onProgress: (received, total) {
          if (total == null || total <= 0) return;
          final percent = (received * 100 / total).floor();
          if (percent == lastPercent) return;
          lastPercent = percent;
          updateProgress = received / total;
          notifyListeners();
        },
      );
      updateStatus = '下载完成，正在启动安装程序…';
      notifyListeners();
      await updates.launchInstaller(file);
      updateStatus = '安装程序已启动，请按提示完成更新';
    } catch (error) {
      updateError = '更新失败：$error';
    } finally {
      downloadingUpdate = false;
      notifyListeners();
    }
  }

  Future<void> openUpdatePage() async {
    final info = availableUpdate;
    if (info == null) return;
    try {
      await updates.openDownloadPage(info.downloadUrl);
    } catch (error) {
      updateError = '打开下载页失败：$error';
      notifyListeners();
    }
  }

  Future<List<PetdexPet>> scanPetdex() => petdex.scan();

  /// 导入本机 ~/.codex/pets 里已经安装的 Petdex 宠物。
  Future<void> importPetdex(PetdexPet source) async {
    if (importingPetdex) return;
    importingPetdex = true;
    notifyListeners();
    try {
      final generated = await petdex.import(source);
      final pet = await repo.saveGenerated(generated);
      pets = await repo.loadAll();
      active = pet;
      settings = settings.copyWith(activePetId: pet.id);
      affection = memory.of(pet.id).taps;
      messages = [];
      await store.saveSettings(settings);
      if (overlayActive) unawaited(MobileOverlay.sync(pet));
      notifyListeners();
      emitBurst(PetBurst.hearts);
      await closePanel();
      showBubble('我是${displayName(pet)}！以后就住在你的桌面啦。', mood: PetMood.love, duration: 5);
    } catch (error) {
      chatError = '导入 Petdex 宠物失败：$error';
    } finally {
      importingPetdex = false;
      notifyListeners();
    }
  }

}
