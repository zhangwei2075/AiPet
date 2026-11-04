import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/app_mode.dart';
import '../data/memory_store.dart';
import '../data/pet_repository.dart';
import '../data/settings_store.dart';
import '../mobile/overlay_pet.dart';
import '../models/chat.dart';
import '../models/pet.dart';
import '../models/settings.dart';
import '../services/badge_pet_factory.dart';
import '../services/chat/chat_service.dart';
import '../services/petdex_importer.dart';
import '../services/petforge_client.dart';
import '../services/speech_service.dart';
import '../services/tray_service.dart';
import '../services/update_service.dart';
import '../services/window_service.dart';
import 'chat_coordinator.dart';
import 'controller_types.dart';
import 'generation_coordinator.dart';
import 'pet_behavior.dart';
import 'update_coordinator.dart';

export 'controller_types.dart';

/// 应用状态中枢：宠物、心情、聊天、窗口形态都收在这里。
class AppController extends ChangeNotifier
    with PetBehavior, ChatCoordinator, GenerationCoordinator, UpdateCoordinator {
  AppController({
    PetRepository? repository,
    SettingsStore? store,
    MemoryStore? memoryStore,
    ChatService? chat,
    PetForgeClient? forge,
    PetdexImporter? petdexImporter,
    WindowService? windowService,
    BadgePetFactory? badgeFactory,
    SpeechService? speech,
    UpdateService? updateService,
    math.Random? random,
  })  : repo = repository ?? PetRepository(),
        store = store ?? SettingsStore(),
        memory = memoryStore ?? MemoryStore(),
        chatService = chat ?? ChatService(),
        forge = forge ?? PetForgeClient(),
        petdex = petdexImporter ?? PetdexImporter(),
        window = windowService ?? WindowService(),
        badge = badgeFactory ?? BadgePetFactory(),
        speech = speech ?? SpeechService(),
        updates = updateService ?? UpdateService(),
        random = random ?? math.Random();

  @override
  final PetRepository repo;
  @override
  final SettingsStore store;

  /// 长期记忆：认识多久、被摸过几次、聊过什么。
  @override
  final MemoryStore memory;
  @override
  final ChatService chatService;
  @override
  final PetForgeClient forge;
  @override
  final PetdexImporter petdex;
  @override
  final WindowService window;
  @override
  final BadgePetFactory badge;
  @override
  final SpeechService speech;
  @override
  final UpdateService updates;
  @override
  final math.Random random;

  @override
  final StreamController<PetBurst> burstController = StreamController<PetBurst>.broadcast();
  Stream<PetBurst> get bursts => burstController.stream;

  @override
  AppSettings settings = const AppSettings();
  @override
  List<Pet> pets = const [];
  @override
  Pet? active;
  bool loading = true;

  @override
  WindowMode mode = WindowMode.pet;
  PanelTab panelTab = PanelTab.gallery;
  @override
  PetMood mood = PetMood.idle;
  @override
  String? bubble;
  @override
  bool typing = false;

  /// 在线模型正在逐字返回的内容（null 表示没有在流式输出）。
  @override
  String? streamingText;
  @override
  bool petting = false;
  @override
  bool dragging = false;
  @override
  bool walking = false;

  /// 小跑中（比走更快更颠，window 也滑得更快更远）。
  @override
  bool running = false;

  /// 躺倒求抚摸：压扁侧躺 + 冒爱心，任何互动都会打断它。
  @override
  bool begging = false;

  /// 讨食动画播放中 / 等待主人投喂（由主动行为触发）。
  @override
  bool eating = false;
  @override
  bool awaitingTreat = false;
  @override
  PetAction action = PetAction.none;
  @override
  int actionSeed = 0;
  @override
  int affection = 0;

  @override
  List<ChatMessage> messages = [];
  @override
  final Map<String, List<ChatMessage>> history = {};
  @override
  String? chatError;

  @override
  bool forgeOnline = false;
  @override
  bool generating = false;
  @override
  double generationProgress = 0;
  @override
  String generationStage = '';
  @override
  String? generationError;
  @override
  String? generationNotice;
  @override
  GeneratedPet? preview;
  @override
  Uint8List? sourceBytes;
  @override
  String? sourceName;

  TrayService? _tray;
  bool _quitting = false;

  @override
  bool get isDesktop => window.isDesktop;
  @override
  bool get isMobile => window.isMobile;
  @override
  bool get isSleeping => mood == PetMood.sleepy;
  double get scale => settings.scale;

  /// 朝向：1 = 朝右，-1 = 朝左（由最近一次走动方向决定，渲染时水平镜像帧）。
  @override
  int facing = 1;
  PetPersonality? get personality => active?.personality;

  Future<void> initialize() async {
    settings = await store.loadSettings();
    currentVersion = await updates.currentVersion();
    await memory.load();
    pets = await repo.loadAll();
    active = pets.where((pet) => pet.id == settings.activePetId).firstOrNull ??
        (pets.isNotEmpty ? pets.first : null);
    history.addAll(await store.loadHistory());
    messages = List.of(history[active?.id] ?? const <ChatMessage>[]);
    if (active != null) affection = memory.of(active!.id).taps;

    // 前台服务可能比 Activity 活得久：重新打开 App 时同步悬浮窗状态与宠物。
    if (isMobile) {
      try {
        overlayActive = await MobileOverlay.isShowing;
        if (overlayActive && active != null) unawaited(MobileOverlay.sync(active!));
      } catch (error) {
        debugPrint('overlay state check failed: $error');
      }
    }

    if (window.isDesktop) {
      window.onQuit = _persistBeforeQuit;
      await window.init(
        scale: settings.scale,
        clickThrough: settings.clickThrough,
        savedPosition: settings.petWindowPosition,
      );
      await window.setAlwaysOnTop(settings.alwaysOnTop);
      window.startHitTesting();
      _tray = TrayService(
        onToggleVisibility: toggleVisibility,
        onOpenChat: openChat,
        onOpenPanel: () => openPanel(PanelTab.gallery),
        onToggleClickThrough: toggleClickThrough,
        onQuit: quit,
      );
      await _tray!.init();
      _tray!.setClickThrough(settings.clickThrough);
    }

    loading = false;
    notifyListeners();

    startIdleTimers();
    checkForge();
    if (settings.autoCheckUpdates && settings.updateManifestUrl.trim().isNotEmpty) {
      unawaited(checkForUpdates(silent: true));
    }
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (active == null) return;
      showBubble(active!.personality.greeting, mood: PetMood.happy, duration: 5);
      emitBurst(PetBurst.stars);
    });
  }

  // ------------------------------------------------------------------ 宠物

  Future<void> selectPet(Pet pet) async {
    if (active?.id == pet.id) return;
    active = pet;
    if (overlayActive) unawaited(MobileOverlay.sync(pet));
    settings = settings.copyWith(activePetId: pet.id);
    affection = memory.of(pet.id).taps;
    messages = List.of(history[pet.id] ?? const <ChatMessage>[]);
    await store.saveSettings(settings);
    mood = PetMood.happy;
    emitBurst(PetBurst.hearts);
    showBubble('我是${displayName(pet)}，以后请多关照！', mood: PetMood.happy);
    notifyListeners();
  }

  Future<void> deletePet(Pet pet) async {
    if (pet.builtin) return;
    await repo.delete(pet);
    await memory.clear(pet.id);
    pets = await repo.loadAll();
    if (active?.id == pet.id) {
      active = pets.firstOrNull;
      settings = settings.copyWith(activePetId: active?.id);
      await store.saveSettings(settings);
      if (overlayActive && active != null) unawaited(MobileOverlay.sync(active!));
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------ 窗口

  Future<void> openChat() async {
    await persistWindowPosition();
    mode = WindowMode.chat;
    await window.applyMode(WindowMode.chat, scale: settings.scale);
    if (messages.isEmpty && active != null) {
      messages = [
        ChatMessage(role: ChatRole.pet, text: active!.personality.greeting, at: DateTime.now(), mood: PetMood.happy),
      ];
    }
    bubble = null;
    cancelBubbleTimer();
    mood = PetMood.happy;
    notifyListeners();
  }

  Future<void> closeChat() async {
    mode = WindowMode.pet;
    chatError = null;
    await window.applyMode(WindowMode.pet, scale: settings.scale);
    await window.focus();
    mood = PetMood.idle;
    notifyListeners();
  }

  Future<void> openPanel(PanelTab tab) async {
    await persistWindowPosition();
    mode = WindowMode.panel;
    panelTab = tab;
    bubble = null;
    cancelBubbleTimer();
    await window.applyMode(WindowMode.panel, scale: settings.scale);
    checkForge();
    notifyListeners();
  }

  @override
  Future<void> closePanel() async {
    mode = WindowMode.pet;
    panelTab = PanelTab.gallery;
    await window.applyMode(WindowMode.pet, scale: settings.scale);
    await window.focus();
    notifyListeners();
  }

  Future<void> setPanelTab(PanelTab tab) async {
    panelTab = tab;
    notifyListeners();
  }

  /// 展示用名字：用户自定义昵称优先，否则用宠物包里的名字。
  @override
  String displayName(Pet pet) {
    final nick = settings.petNames[pet.id]?.trim();
    return (nick == null || nick.isEmpty) ? pet.name : nick;
  }

  /// 重命名宠物。传空/null 表示恢复默认名字。
  Future<void> renamePet(String id, String? name) async {
    final names = Map<String, String>.from(settings.petNames);
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) {
      names.remove(id);
    } else {
      names[id] = trimmed;
    }
    settings = settings.copyWith(petNames: names);
    await store.saveSettings(settings);
    notifyListeners();
  }

  bool _hidden = false;

  Future<void> toggleVisibility() async {
    if (!isDesktop) return;
    _hidden = !_hidden;
    if (_hidden) {
      await window.hide();
    } else {
      await window.show();
    }
  }

  Future<void> toggleClickThrough() async {
    settings = settings.copyWith(clickThrough: !settings.clickThrough);
    await window.setClickThrough(settings.clickThrough);
    _tray?.setClickThrough(settings.clickThrough);
    await store.saveSettings(settings);
    notifyListeners();
  }

  @override
  bool overlayActive = false;

  /// 自动更新状态（设置页「更新」使用）。
  @override
  String currentVersion = '';
  @override
  UpdateInfo? availableUpdate;
  @override
  bool checkingUpdate = false;
  @override
  bool downloadingUpdate = false;
  @override
  double updateProgress = 0;
  @override
  String? updateError;
  @override
  String? updateStatus;

  @override
  bool importingPetdex = false;

  /// Android：申请「悬浮在其他应用上层」权限并显示系统悬浮窗。

  Future<void> updateSettings(AppSettings next) async {
    final idleChanged = next.wander != settings.wander ||
        next.autoSleep != settings.autoSleep ||
        next.proactive != settings.proactive;
    final scaleChanged = next.scale != settings.scale;
    final topChanged = next.alwaysOnTop != settings.alwaysOnTop;
    final clickChanged = next.clickThrough != settings.clickThrough;
    settings = next;
    await store.saveSettings(settings);
    if (settings.tts == false) unawaited(speech.stop());
    if (topChanged) await window.setAlwaysOnTop(next.alwaysOnTop);
    if (clickChanged) {
      await window.setClickThrough(next.clickThrough);
      _tray?.setClickThrough(next.clickThrough);
    }
    if (scaleChanged) await window.applyMode(mode, scale: next.scale);
    // 空闲行为开关变了要按新配置重排定时器，否则旧定时器会沿用旧设置。
    if (idleChanged) startIdleTimers();
    notifyListeners();
  }

  /// 语音开关：聊天页的小喇叭和设置页共用。
  Future<void> toggleTts() async {
    final next = settings.copyWith(tts: !settings.tts);
    settings = next;
    if (!next.tts) await speech.stop();
    await store.saveSettings(settings);
    notifyListeners();
  }

  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    try {
      await persistWindowPosition();
      await window.rememberPosition();
      final position = window.positionString;
      if (position != null) {
        settings = settings.copyWith(petWindowPosition: position);
        await store.saveSettings(settings);
      }
      await saveHistory();
    } finally {
      await _tray?.destroy();
      await window.quit();
    }
  }

  void _persistBeforeQuit() {
    // 系统关闭窗口时也保存位置
    unawaited(persistWindowPosition());
  }

  // ---------------------------------------------------------------- 清理

  @override
  void dispose() {
    unawaited(speech.stop());
    disposeBehavior();
    disposeChat();
    burstController.close();
    _tray?.destroy();
    window.dispose();
    super.dispose();
  }
}
