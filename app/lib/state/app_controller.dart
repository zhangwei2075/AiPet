import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/app_mode.dart';
import '../data/memory_store.dart';
import '../data/pet_repository.dart';
import '../data/settings_store.dart';
import '../mobile/overlay_pet.dart';
import '../models/chat.dart';
import '../models/pet.dart';
import '../models/pet_memory.dart';
import '../models/settings.dart';
import '../services/badge_pet_factory.dart';
import '../services/chat/chat_service.dart';
import '../services/chat/openai_backend.dart';
import '../services/petforge_client.dart';
import '../services/petdex_importer.dart';
import '../services/speech_service.dart';
import '../services/tray_service.dart';
import '../services/update_service.dart';
import '../services/window_service.dart';

enum PetBurst { hearts, stars, anger, sleep, note }

enum PanelTab { gallery, create, settings }

enum PetAction { none, hop, spin, drop }

/// 应用状态中枢：宠物、心情、聊天、窗口形态都收在这里。
class AppController extends ChangeNotifier {
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
        _store = store ?? SettingsStore(),
        memory = memoryStore ?? MemoryStore(),
        _chat = chat ?? ChatService(),
        _forge = forge ?? PetForgeClient(),
        petdex = petdexImporter ?? PetdexImporter(),
        window = windowService ?? WindowService(),
        _badge = badgeFactory ?? BadgePetFactory(),
        speech = speech ?? SpeechService(),
        updates = updateService ?? UpdateService(),
        _random = random ?? math.Random();

  final PetRepository repo;
  final SettingsStore _store;

  /// 长期记忆：认识多久、被摸过几次、聊过什么。
  final MemoryStore memory;
  final ChatService _chat;
  final PetForgeClient _forge;
  final PetdexImporter petdex;
  final WindowService window;
  final BadgePetFactory _badge;
  final SpeechService speech;
  final UpdateService updates;
  final math.Random _random;

  final StreamController<PetBurst> _burstController = StreamController<PetBurst>.broadcast();
  Stream<PetBurst> get bursts => _burstController.stream;

  AppSettings settings = const AppSettings();
  List<Pet> pets = const [];
  Pet? active;
  bool loading = true;

  WindowMode mode = WindowMode.pet;
  PanelTab panelTab = PanelTab.gallery;
  PetMood mood = PetMood.idle;
  String? bubble;
  bool typing = false;

  /// 在线模型正在逐字返回的内容（null 表示没有在流式输出）。
  String? streamingText;
  bool petting = false;
  bool dragging = false;
  bool walking = false;

  /// 小跑中（比走更快更颠，window 也滑得更快更远）。
  bool running = false;

  /// 躺倒求抚摸：压扁侧躺 + 冒爱心，任何互动都会打断它。
  bool begging = false;
  PetAction action = PetAction.none;
  int actionSeed = 0;
  int affection = 0;

  List<ChatMessage> messages = [];
  final Map<String, List<ChatMessage>> _history = {};
  String? chatError;

  bool forgeOnline = false;
  bool generating = false;
  double generationProgress = 0;
  String generationStage = '';
  String? generationError;
  String? generationNotice;
  GeneratedPet? preview;
  Uint8List? sourceBytes;
  String? sourceName;

  TrayService? _tray;
  Timer? _bubbleTimer;
  Timer? _moodTimer;
  Timer? _sleepTimer;
  Timer? _wanderTimer;
  Timer? _begTimer;
  Timer? _begScheduler;
  Timer? _dragWatch;
  Timer? _historyDebounce;
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
  bool _quitting = false;

  bool get isDesktop => window.isDesktop;
  bool get isMobile => window.isMobile;
  bool get isSleeping => mood == PetMood.sleepy;
  double get scale => settings.scale;

  /// 朝向：1 = 朝右，-1 = 朝左（由最近一次走动方向决定，渲染时水平镜像帧）。
  int facing = 1;
  PetPersonality? get personality => active?.personality;

  Future<void> initialize() async {
    settings = await _store.loadSettings();
    currentVersion = await updates.currentVersion();
    await memory.load();
    pets = await repo.loadAll();
    active = pets.where((pet) => pet.id == settings.activePetId).firstOrNull ??
        (pets.isNotEmpty ? pets.first : null);
    _history.addAll(await _store.loadHistory());
    messages = List.of(_history[active?.id] ?? const <ChatMessage>[]);
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

    _startIdleTimers();
    _checkForge();
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
    messages = List.of(_history[pet.id] ?? const <ChatMessage>[]);
    await _store.saveSettings(settings);
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
      await _store.saveSettings(settings);
      if (overlayActive && active != null) unawaited(MobileOverlay.sync(active!));
    }
    notifyListeners();
  }

  void showBubble(String text, {PetMood mood = PetMood.talk, int duration = 6}) {    bubble = text;
    this.mood = mood;
    _bubbleTimer?.cancel();
    _bubbleTimer = Timer(Duration(seconds: duration), () {
      if (mode.isPanel) return;
      bubble = null;
      if (this.mood == mood) this.mood = PetMood.idle;
      notifyListeners();
    });
    notifyListeners();
  }

  void dismissBubble() {
    _bubbleTimer?.cancel();
    bubble = null;
    if (mood != PetMood.sleepy) mood = PetMood.idle;
    notifyListeners();
  }

  void emitBurst(PetBurst kind) {
    if (!_burstController.isClosed) _burstController.add(kind);
  }

  void _wake() {
    _resetSleepTimer();
    _stopBegging();
    if (mood == PetMood.sleepy) {
      mood = PetMood.idle;
      notifyListeners();
    }
  }

  void tapPet({required bool head}) {
    final wasBegging = begging;
    _wake();
    if (wasBegging) {
      // 冲着「求抚摸」来的，给双倍奖励
      affection += 2;
      unawaited(_rememberTouch(2));
      emitBurst(PetBurst.hearts);
      action = PetAction.hop;
      actionSeed++;
      showBubble(_pick(['嘿嘿，就是要这个～', '咕噜咕噜…', '再摸两下嘛！']),
          mood: PetMood.love, duration: 3);
      return;
    }
    final now = DateTime.now();
    final isDouble = now.difference(_lastTap) < const Duration(milliseconds: 320);
    _lastTap = now;

    if (isDouble) {
      _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
      affection += 1;
      unawaited(_rememberTouch(1));
      action = PetAction.spin;
      actionSeed++;
      emitBurst(PetBurst.stars);
      showBubble(_pick(['转圈圈！', '看我看我～', '嘿咻——']), mood: PetMood.happy, duration: 3);
      return;
    }

    affection += head ? 2 : 1;
    unawaited(_rememberTouch(head ? 2 : 1));
    action = PetAction.hop;
    actionSeed++;
    if (affection % 19 == 0) {
      mood = PetMood.angry;
      emitBurst(PetBurst.anger);
      showBubble(_pick(['不要再戳啦！', '哼，我生气了。', '摸够了没有…']), mood: PetMood.angry, duration: 3);
    } else if (head) {
      emitBurst(PetBurst.hearts);
      showBubble(
        _pick(['唔…好舒服。', '嘿嘿，再摸一下。', '眯起眼睛…', '最喜欢主人了。']),
        mood: affection > 10 ? PetMood.love : PetMood.happy,
        duration: 3,
      );
    } else {
      emitBurst(PetBurst.note);
      showBubble(
        _pick(['！', '陪我玩？', '在呢在呢。', '今天也辛苦了。']),
        mood: PetMood.happy,
        duration: 3,
      );
    }
  }

  void doubleTapPet() {
    _wake();
    action = PetAction.spin;
    actionSeed++;
    emitBurst(PetBurst.stars);
  }

  void startPetting() {
    _wake();
    _stopBegging();
    petting = true;
    affection += 1;
    unawaited(_rememberTouch(1));
    emitBurst(PetBurst.hearts);
    mood = PetMood.love;
    notifyListeners();
  }

  void stopPetting() {
    petting = false;
    _scheduleIdleReturn();
    notifyListeners();
  }

  void completeAction() {
    if (action == PetAction.none) return;
    action = PetAction.none;
    notifyListeners();
  }

  void _scheduleIdleReturn() {
    _moodTimer?.cancel();
    _moodTimer = Timer(const Duration(milliseconds: 2600), () {
      if (typing || petting || dragging) return;
      if (mode == WindowMode.chat) return;
      mood = PetMood.idle;
      notifyListeners();
    });
  }

  // ------------------------------------------------------------------ 拖动

  Future<void> beginWindowDrag() async {
    if (!isDesktop) return;
    _wake();
    _stopBegging();
    dragging = true;
    window.onDragMove = _onDragMove;
    notifyListeners();
    await window.beginDrag();
    _dragWatch?.cancel();
    _dragWatch = Timer.periodic(const Duration(milliseconds: 110), (timer) {
      if (!window.mouseButtonDown) {
        timer.cancel();
        endWindowDrag();
      }
    });
    Future<void>.delayed(const Duration(seconds: 15), () {
      if (dragging) endWindowDrag();
    });
  }

  void endWindowDrag() {
    if (!dragging) return;
    _dragWatch?.cancel();
    dragging = false;
    window.onDragMove = null;
    window.endDrag();
    mood = PetMood.idle;
    action = PetAction.drop;
    actionSeed++;
    _persistWindowPosition();
    notifyListeners();
  }

  /// 拖动方向：不 notify，PetStage 的 ticker 每帧直接读取 facing。
  void _onDragMove(Offset delta) {
    if (delta.dx.abs() > 0.2) {
      facing = delta.dx > 0 ? 1 : -1;
    }
  }

  Future<void> _persistWindowPosition() async {
    if (!isDesktop) return;
    await window.rememberPosition();
    final position = window.positionString;
    if (position == null) return;
    settings = settings.copyWith(petWindowPosition: position);
    await _store.saveSettings(settings);
  }

  // ------------------------------------------------------------------ 窗口

  Future<void> openChat() async {
    await _persistWindowPosition();
    mode = WindowMode.chat;
    await window.applyMode(WindowMode.chat, scale: settings.scale);
    if (messages.isEmpty && active != null) {
      messages = [
        ChatMessage(role: ChatRole.pet, text: active!.personality.greeting, at: DateTime.now(), mood: PetMood.happy),
      ];
    }
    bubble = null;
    _bubbleTimer?.cancel();
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
    await _persistWindowPosition();
    mode = WindowMode.panel;
    panelTab = tab;
    bubble = null;
    _bubbleTimer?.cancel();
    await window.applyMode(WindowMode.panel, scale: settings.scale);
    _checkForge();
    notifyListeners();
  }

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
    await _store.saveSettings(settings);
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
    await _store.saveSettings(settings);
    notifyListeners();
  }

  bool overlayActive = false;

  /// 自动更新状态（设置页「更新」使用）。
  String currentVersion = '';
  UpdateInfo? availableUpdate;
  bool checkingUpdate = false;
  bool downloadingUpdate = false;
  double updateProgress = 0;
  String? updateError;
  String? updateStatus;

  bool importingPetdex = false;

  /// Android：申请「悬浮在其他应用上层」权限并显示系统悬浮窗。
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
      await _store.saveSettings(settings);
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

  Future<void> updateSettings(AppSettings next) async {
    final scaleChanged = next.scale != settings.scale;
    final topChanged = next.alwaysOnTop != settings.alwaysOnTop;
    final clickChanged = next.clickThrough != settings.clickThrough;
    settings = next;
    await _store.saveSettings(settings);
    if (settings.tts == false) unawaited(speech.stop());
    if (topChanged) await window.setAlwaysOnTop(next.alwaysOnTop);
    if (clickChanged) {
      await window.setClickThrough(next.clickThrough);
      _tray?.setClickThrough(next.clickThrough);
    }
    if (scaleChanged) await window.applyMode(mode, scale: next.scale);
    notifyListeners();
  }

  /// 语音开关：聊天页的小喇叭和设置页共用。
  Future<void> toggleTts() async {
    final next = settings.copyWith(tts: !settings.tts);
    settings = next;
    if (!next.tts) await speech.stop();
    await _store.saveSettings(settings);
    notifyListeners();
  }

  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    try {
      await _persistWindowPosition();
      await window.rememberPosition();
      final position = window.positionString;
      if (position != null) {
        settings = settings.copyWith(petWindowPosition: position);
        await _store.saveSettings(settings);
      }
      await _saveHistory();
    } finally {
      await _tray?.destroy();
      await window.quit();
    }
  }

  void _persistBeforeQuit() {
    // 系统关闭窗口时也保存位置
    unawaited(_persistWindowPosition());
  }

  // ------------------------------------------------------------------ 聊天

  Future<void> sendMessage(String raw) async {
    final text = raw.trim();
    final pet = active;
    if (text.isEmpty || pet == null || typing) return;
    _wake();

    final userMessage = ChatMessage(role: ChatRole.user, text: text, at: DateTime.now());
    final history = List<ChatMessage>.of(messages);
    messages = [...messages, userMessage];
    typing = true;
    bubble = null;
    mood = PetMood.talk;
    chatError = null;
    notifyListeners();

    final note = memory.promptFor(pet.id);
    final online = settings.chatBackend == ChatBackendKind.openai;

    if (!online) {
      _finishReply(_chat.local(text, pet, affection: affection), pet, text);
      return;
    }

    // 在线模型：逐字吐出来，让等待没那么难熬；失败就整段降级到本地小脑。
    final buffer = StringBuffer();
    try {
      await for (final delta in _chat.sendStream(
        input: text,
        pet: pet,
        history: history,
        settings: settings,
        affection: affection,
        memory: note,
      )) {
        buffer.write(delta);
        streamingText = OpenAiBackend.parseReply(buffer.toString()).text;
        notifyListeners();
      }
      streamingText = null;
      _finishReply(OpenAiBackend.parseReply(buffer.toString().trim()), pet, text);
    } catch (error) {
      streamingText = null;
      _finishReply(
        _chat.local(text, pet, affection: affection),
        pet,
        text,
        degradedError: error.toString(),
      );
    }
  }

  /// 收尾：落一条宠物消息、切情绪、朗读、冒气泡、记一笔记忆。
  void _finishReply(PetReply reply, Pet pet, String userText, {String? degradedError}) {
    typing = false;
    messages = [
      ...messages,
      ChatMessage(role: ChatRole.pet, text: reply.text, at: DateTime.now(), mood: reply.mood),
    ];
    mood = reply.mood;
    chatError = degradedError;
    if (settings.tts) unawaited(speech.speak(reply.text));
    if (mode != WindowMode.chat) {
      bubble = reply.text;
      emitBurst(_burstFor(reply.mood));
      _scheduleIdleReturn();
    }
    notifyListeners();
    unawaited(memory.chat(pet.id, userText));
    _scheduleHistorySave();
  }

  PetBurst _burstFor(PetMood mood) => switch (mood) {
        PetMood.love => PetBurst.hearts,
        PetMood.happy => PetBurst.note,
        PetMood.angry => PetBurst.anger,
        PetMood.sleepy => PetBurst.sleep,
        _ => PetBurst.stars,
      };

  void _scheduleHistorySave() {
    _historyDebounce?.cancel();
    _historyDebounce = Timer(const Duration(milliseconds: 800), () => unawaited(_saveHistory()));
  }

  Future<void> _saveHistory() async {
    final pet = active;
    if (pet == null) return;
    _history[pet.id] = messages.length > 60 ? messages.sublist(messages.length - 60) : messages;
    await _store.saveHistory(_history);
  }

  void clearChat() {
    messages = [];
    if (active != null) _history.remove(active!.id);
    unawaited(_store.saveHistory(_history));
    notifyListeners();
  }

  // ------------------------------------------------------------------ 生成

  void loadSource(Uint8List bytes, String name) {
    sourceBytes = bytes;
    sourceName = name;
    preview = null;
    generationError = null;
    generationNotice = null;
    notifyListeners();
  }

  void resetGeneration() {
    sourceBytes = null;
    sourceName = null;
    preview = null;
    generationError = null;
    generationNotice = null;
    generationProgress = 0;
    generating = false;
    notifyListeners();
  }

  Future<void> _checkForge() async {
    final health = await _forge.health(settings.forgeUrl);
    forgeOnline = health.online;
    notifyListeners();
  }

  Future<void> generate({String style = 'sticker', String? name}) async {
    final bytes = sourceBytes;
    if (bytes == null || generating) return;
    generating = true;
    generationError = null;
    generationNotice = null;
    preview = null;
    generationStage = '正在连接形象工坊…';
    generationProgress = 0.12;
    notifyListeners();

    try {
      final health = await _forge.health(settings.forgeUrl);
      forgeOnline = health.online;
      generationStage = '抠图 & 生成动作帧';
      generationProgress = 0.42;
      notifyListeners();

      if (health.online) {
        final result = await _forge.generate(
          bytes: bytes,
          baseUrl: settings.forgeUrl,
          filename: sourceName ?? 'upload.png',
          style: style,
          name: name,
          animate: true,
        );
        generationStage = '设计性格 & 调色板';
        generationProgress = 0.9;
        preview = result;
        final cutout = result.pack['metrics']?['cutout']?.toString();
        final animations = (result.pack['animations'] as Map?)?.keys.toList() ?? const [];
        if (cutout == 'oval') {
          generationNotice = '背景比较复杂，先用了圆形徽章兜底。安装 rembg 后效果会更好。';
        } else if (cutout != 'rembg') {
          generationNotice = '服务端没装 rembg（当前用 $cutout 抠图），毛发边缘可能不干净；装上 rembg 效果最好。';
        } else if (animations.isNotEmpty) {
          generationNotice = '已生成 ${animations.join(' / ')} 逐帧动画。';
        }
      } else {
        generationStage = '本地徽章模式';
        generationProgress = 0.6;
        preview = await _badge.build(bytes, name: name);
        generationNotice = '没有连上 PetForge 服务，已用本地徽章模式生成。启动服务可获得贴纸抠图效果。';
      }
      generationProgress = 1;
    } catch (error) {
      generationError = '生成失败：$error';
      try {
        preview = await _badge.build(bytes, name: name);
        generationNotice = '远程生成失败，已退回本地徽章模式。';
      } catch (_) {
        preview = null;
      }
    } finally {
      generating = false;
      notifyListeners();
    }
  }

  Future<Pet?> adoptPreview({String? name}) async {
    final result = preview;
    if (result == null) return null;
    final pet = await repo.saveGenerated(result, name: name);
    pets = await repo.loadAll();
    settings = settings.copyWith(activePetId: pet.id);
    active = pet;
    if (overlayActive) unawaited(MobileOverlay.sync(pet));
    messages = [];
    await _store.saveSettings(settings);
    resetGeneration();
    await _store.saveSettings(settings);
    notifyListeners();
    emitBurst(PetBurst.hearts);
    await closePanel();
    showBubble('我是${displayName(pet)}！以后就住在你的桌面啦。', mood: PetMood.love, duration: 6);
    return pet;
  }

  // ------------------------------------------------------------------ 定时行为

  void _startIdleTimers() {
    _resetSleepTimer();
    _scheduleWander();
    _scheduleBeg(retry: true);
  }

  void _resetSleepTimer() {
    _sleepTimer?.cancel();
    if (!settings.autoSleep) return;
    _sleepTimer = Timer(const Duration(seconds: 90), () {
      if (mode != WindowMode.pet || dragging || typing) return;
      mood = PetMood.sleepy;
      bubble = _pick(['呼…', 'Zzz…', '（睡着了）']);
      emitBurst(PetBurst.sleep);
      notifyListeners();
    });
  }

  void _scheduleWander() {
    _wanderTimer?.cancel();
    if (!settings.wander || !isDesktop) return;
    final delay = Duration(seconds: 26 + _random.nextInt(30));
    _wanderTimer = Timer(delay, () {
      // 三成概率小跑，其余慢走
      unawaited(stroll(run: _random.nextInt(10) < 3));
      _scheduleWander();
    });
  }

  /// 走一段 / 跑一段（在桌面上横着挪，附带走/跑的肢体动作）。
  /// [run] 为 true 时是小跑：位移更远、速度更快、姿态前倾。
  Future<void> stroll({bool run = false}) async {
    if (!isDesktop || mode != WindowMode.pet) return;
    if (dragging || typing || isSleeping || begging) return;
    walking = true;
    running = run;
    notifyListeners();
    final distance = run
        ? (150 + _random.nextInt(180)).toDouble()
        : (36 + _random.nextInt(90)).toDouble();
    final dx = (_random.nextBool() ? 1 : -1) * distance;
    facing = dx > 0 ? 1 : -1;
    await window.glideBy(
      dx,
      duration: Duration(milliseconds: run ? 420 : 900),
    );
    if (run) emitBurst(PetBurst.stars);
    walking = false;
    running = false;
    notifyListeners();
  }

  /// 躺倒求抚摸：压扁侧躺、冒爱心、冒气泡，约 14 秒后自己爬起来。
  void lieDown() {
    if (!isDesktop || mode != WindowMode.pet || dragging) return;
    _wake();
    _stopBegging();
    begging = true;
    mood = PetMood.love;
    emitBurst(PetBurst.hearts);
    showBubble(
      _pick(['摸摸肚子～', '躺平啦，快摸我！', '求摸摸！', '翻肚皮给你看。']),
      mood: PetMood.love,
      duration: 6,
    );
    notifyListeners();
    _begTimer?.cancel();
    _begTimer = Timer(const Duration(seconds: 14), () => _stopBegging());
    _scheduleBeg(retry: false);
  }

  void _stopBegging() {
    if (!begging) {
      _begTimer?.cancel();
      return;
    }
    begging = false;
    _begTimer?.cancel();
  }

  /// 自动行为：没被理会的时候，偶尔自己躺下求抚摸。
  void _scheduleBeg({bool retry = true}) {
    _begScheduler?.cancel();
    if (!isDesktop) return;
    // 首次/重试用短间隔（抢在 90 秒自动睡觉前）；求摸后用长间隔，给睡觉留机会。
    final seconds = retry ? 35 + _random.nextInt(40) : 80 + _random.nextInt(70);
    _begScheduler = Timer(Duration(seconds: seconds), () {
      if (mode == WindowMode.pet && !dragging && !typing && !isSleeping && !petting) {
        lieDown();
      } else {
        _scheduleBeg();
      }
    });
  }

  /// 外部（悬浮窗 / 托盘）戳一下宠物时的入口。
  void poke() {
    _wake();
    affection += 1;
    unawaited(_rememberTouch(1));
    showBubble(_pick(['在呢。', '戳我做什么～', '汪？']), mood: PetMood.happy, duration: 3);
  }

  /// 记录一次互动，撞到里程碑（第 20/50/100 次）时额外冒一句话。
  Future<void> _rememberTouch(int amount) async {
    final pet = active;
    if (pet == null) return;
    final milestone = await memory.tap(pet.id, amount: amount);
    if (milestone == null || mode == WindowMode.chat) return;
    showBubble('$milestone！我都记着呢。', mood: PetMood.love, duration: 4);
    emitBurst(PetBurst.hearts);
    notifyListeners();
  }

  /// 当前宠物的记忆（界面上展示成长阶段用）。
  PetMemory? get activeMemory => active == null ? null : memory.of(active!.id);

  Future<void> clearMemory() async {
    final pet = active;
    if (pet == null) return;
    await memory.clear(pet.id);
    affection = 0;
    notifyListeners();
  }

  String _pick(List<String> options) => options[_random.nextInt(options.length)];

  @override
  void dispose() {
    unawaited(speech.stop());
    _bubbleTimer?.cancel();
    _moodTimer?.cancel();
    _sleepTimer?.cancel();
    _wanderTimer?.cancel();
    _begTimer?.cancel();
    _begScheduler?.cancel();
    _dragWatch?.cancel();
    _historyDebounce?.cancel();
    _burstController.close();
    _tray?.destroy();
    window.dispose();
    super.dispose();
  }
}
