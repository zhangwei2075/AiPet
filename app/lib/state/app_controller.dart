import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../agent/activity.dart';
import '../agent/autonomy.dart';
import '../agent/brain.dart';
import '../agent/brain_host.dart';
import '../agent/brainpack.dart';
import '../agent/chat_agent.dart';
import '../agent/experience.dart';
import '../agent/mcp/mcp_client.dart';
import '../agent/mcp/mcp_server.dart';
import '../agent/memory/episodic_store.dart';
import '../agent/memory/memory_service.dart';
import '../agent/permissions.dart';
import '../agent/skill.dart';
import '../agent/skill_store.dart';
import '../agent/speculative.dart';
import '../agent/task_store.dart';
import '../agent/tool_probe.dart';
import '../agent/tool_runtime.dart';
import '../agent/triggers/app_focus_trigger.dart';
import '../agent/triggers/clipboard_trigger.dart';
import '../agent/triggers/quiet_hours.dart';
import '../agent/watchdog.dart';
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
    with PetBehavior, ChatCoordinator, GenerationCoordinator, UpdateCoordinator
    implements BrainHost {
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
        random = random ?? math.Random() {
    // 状态变化让监听 controller 的界面（聊天窗口等）也一起刷新。
    agentActivity.addListener(notifyListeners);
  }

  @override
  final PetRepository repo;
  @override
  final SettingsStore store;

  /// 长期记忆：认识多久、被摸过几次、聊过什么。
  @override
  final MemoryStore memory;
  @override
  final ChatService chatService;

  /// 智能体大脑（M1：提醒/剪贴板/自我动作）。随 init 创建，dispose 销毁。
  @override
  PetBrain? brain;

  /// 情景记忆服务（M2）。
  @override
  MemoryService? memoryService;

  /// M3 自治组件：看门狗 / 环境感知 / 投机执行。
  Watchdog? watchdog;
  ClipboardTrigger? clipboardTrigger;
  AppFocusTrigger? appFocusTrigger;
  SpeculativeEngine? speculative;

  /// M4 能力清单：配置化的工具/Trigger 开关（M5 起缺省即启用）。
  BrainPack brainPack = BrainPack.defaults;

  /// M5 全权限运行时：能力授予 / 一键急停 / 不可逆命令黑名单 / 审计留痕。
  AgentPermissions agentPermissions = AgentPermissions.defaults;
  final PermissionStore _permissionStore = PermissionStore();

  /// 「此刻在干什么」：气泡 / 聊天窗口的状态条直接监听它，工具调用即时刷新。
  @override
  final AgentActivity agentActivity = AgentActivity();

  @override
  late final ToolRuntime toolRuntime = ToolRuntime(activity: agentActivity);

  /// 目标级复盘（学习沉淀）：聊天与自主规划都会召回同类经验。
  @override
  final ExperienceBank experienceBank = ExperienceBank();

  /// 聊天级 function calling 执行器，在 initialize 里用 Brain 的注册表装配。
  @override
  ChatAgent? chatAgent;

  /// M5 自主循环：目标队列 + 多步规划 + 后台执行。随 initialize 创建。
  AutonomyLoop? autonomy;

  /// 技能注册表：提示词模板，按用户请求注入 system prompt。
  @override
  final SkillRegistry skillRegistry = SkillRegistry(builtInSkills);
  final SkillStore _skillStore = SkillStore();

  /// MCP 服务器清单与工具目录。连接是显式动作，不在启动时自动发起网络请求。
  final McpStore _mcpStore = McpStore();
  final McpClient mcpClient = McpClient();
  List<McpServer> mcpServers = const [];
  Map<String, List<McpTool>> mcpTools = const {};
  String? mcpError;

  /// 感知类 Trigger 开关。M5 默认开启，急停时一并停摆。
  bool get perceptionEnabled => settings.perceptionEnabled && !agentPermissions.paused;

  /// 自主执行开关：设置打开且没有急停。
  @override
  bool get autonomyEnabled => settings.autonomyEnabled && !agentPermissions.paused;

  /// 是否处于「全部能力都已授予」状态（权限页总开关）。
  bool get fullAccess => agentPermissions.isFullAccess && !agentPermissions.paused;

  /// 权限热改：立即作用于 ToolRuntime，不需要重建 Brain / 重新注册工具。
  Future<void> applyPermissions(AgentPermissions next) async {
    agentPermissions = next;
    toolRuntime.applyPermissions(next);
    await _permissionStore.save(next);
    notifyListeners();
  }

  Future<void> setCapabilityEnabled(AgentCapability cap, bool value) =>
      applyPermissions(agentPermissions.withCapability(cap, value));

  Future<void> setFullAccess(bool value) =>
      applyPermissions(agentPermissions.withAll(value));

  Future<void> setPaused(bool value) =>
      applyPermissions(agentPermissions.copyWith(paused: value));

  Future<void> setAutonomyEnabled(bool value) =>
      updateSettings(settings.copyWith(autonomyEnabled: value));

  Future<void> setPerceptionEnabled(bool value) =>
      updateSettings(settings.copyWith(perceptionEnabled: value));

  Future<void> clearAudit() async {
    await toolRuntime.audit.clear();
    notifyListeners();
  }

  /// 清掉沉淀的经验（不影响情景记忆与审计）。
  Future<void> clearExperience() async {
    await experienceBank.clear();
    notifyListeners();
  }

  /// 管理页直接给智能体派一个目标（后台多步执行）。
  Future<String> submitAgentGoal(String title) async {
    final activeBrain = brain;
    if (activeBrain == null) return '智能体还没准备好，稍等一下。';
    return activeBrain.submitGoal(title);
  }

  Future<void> setSkillEnabled(String id, bool value) async {
    skillRegistry.setEnabled(id, value);
    await _skillStore.save({for (final s in skillRegistry.all) s.id: s.enabled});
    notifyListeners();
  }

  // ------------------------------------------------------------------ MCP

  Future<void> saveMcpServer(McpServer server) async {
    final list = List<McpServer>.of(mcpServers);
    final index = list.indexWhere((s) => s.id == server.id);
    if (index >= 0) {
      list[index] = server;
    } else {
      list.add(server);
    }
    mcpServers = list;
    await _mcpStore.save(list);
    notifyListeners();
  }

  Future<void> removeMcpServer(String id) async {
    mcpServers = mcpServers.where((s) => s.id != id).toList();
    mcpTools = Map.of(mcpTools)..remove(id);
    await _mcpStore.save(mcpServers);
    notifyListeners();
  }

  Future<void> connectMcpServer(String id) async {
    final server = mcpServers.firstWhere((s) => s.id == id);
    mcpError = null;
    notifyListeners();
    try {
      final tools = await mcpClient.connect(server);
      mcpTools = Map.of(mcpTools)..[id] = tools;
      // 接入 Brain 注册表：远程工具走异步后台执行（McpTool.slow=true），
      // 且同样经 ToolRuntime 包装，受 mcp 能力开关与审计约束（M5）。
      for (final tool in tools) {
        // 远程工具不得覆盖内置工具（防诱导同名劫持提醒/剪贴板）。
        if (BrainPack.builtInTools.contains(tool.name)) continue;
        brain?.registry.register(toolRuntime.wrap(tool));
      }
    } catch (error) {
      mcpError = error.toString();
    }
    notifyListeners();
  }
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

  /// 开心摇尾巴（互动后的余韵，几秒后自动停）。
  @override
  bool wagging = false;

  /// 原地嗅探（漫步途中的好奇时刻）。
  @override
  bool sniffing = false;
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
  PetPersonality? get personality =>
      active == null ? null : settings.personaOf(active!);

  Future<void> initialize() async {
    settings = await store.loadSettings();
    // M5：权限独立落盘，先恢复再装配工具，保证启动瞬间规则就生效。
    agentPermissions = await _permissionStore.load();
    toolRuntime.applyPermissions(agentPermissions);
    unawaited(speech.setVoice(settings.voice)); // 未初始化时只记下声线，_ensure 时生效
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
    memoryService = MemoryService(store: EpisodicStore());
    unawaited(memoryService!.load());
    brain = PetBrain(
      host: this,
      store: TaskStore(),
      probe: ToolProbe(),
      memoryService: memoryService,
      runtime: toolRuntime,
    );
    chatAgent = ChatAgent(
      registry: brain!.registry,
      runtime: toolRuntime,
      activity: agentActivity,
      experience: experienceBank,
    );
    // 先有 Brain（工具已注册）→ 再用它的注册表建自主循环 → 挂回 Brain。
    autonomy = AutonomyLoop(
      host: this,
      registry: brain!.registry,
      runtime: toolRuntime,
      store: GoalStore(),
      probe: ToolProbe(),
      // 自驱节流必须落盘：否则每次重启 _lastSelfDrive 归零，
      // 起来第一个心跳就去查磁盘，看着像「开机自动清理磁盘」。
      selfDriveStore: SelfDriveStore(),
      isEnabled: () => autonomyEnabled,
      settings: () => settings,
      permissions: () => agentPermissions,
      memory: memoryService,
      activity: agentActivity,
      experience: experienceBank,
    );
    brain!.attachLoop(autonomy!);
    unawaited(brain!.start());

    // M3 自治：Watchdog 巡视 + 感知 Trigger + 投机执行。
    // 感知类默认关闭，开启与否由设置热控制（isEnabled 回调实时读取）。
    final taskStore = TaskStore();
    watchdog = Watchdog(store: taskStore, host: this);
    brain!.attachWatchdog(watchdog!);
    watchdog!.start();

    // M5 默认全天可行动、配额 240 次只防抖；brainpack 里配了旧规则就按配置走。
    final quietRules = QuietHours(
      startHour: (brainPack.quietHours['start'] as num?)?.toInt() ?? 0,
      endHour: (brainPack.quietHours['end'] as num?)?.toInt() ?? 0,
      dailyBudget: (brainPack.quietHours['dailyBudget'] as num?)?.toInt() ?? 240,
    );
    final policy = QuietPolicy(rules: quietRules);
    clipboardTrigger = ClipboardTrigger(
      isEnabled: () => perceptionEnabled && brainPack.triggerEnabled('clipboard'),
      policy: policy,
    )..start();
    appFocusTrigger = AppFocusTrigger(
      isEnabled: () => perceptionEnabled && brainPack.triggerEnabled('app_focus'),
      policy: policy,
    )..start();
    _listenPerceptionEvents();

    speculative = SpeculativeEngine(host: this, store: taskStore, policy: policy);
    unawaited(speculative!.consider());
    unawaited(_skillStore.load().then(skillRegistry.applySwitches));
    unawaited(_mcpStore.load().then((servers) {
      mcpServers = servers;
      notifyListeners();
    }));

    checkForge();
    if (settings.autoCheckUpdates && settings.updateManifestUrl.trim().isNotEmpty) {
      unawaited(checkForUpdates(silent: true));
    }
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (active == null) return;
      showBubble(settings.personaOf(active!).greeting,
          mood: PetMood.happy, duration: 5);
      emitBurst(PetBurst.stars);
    });
  }

  // ------------------------------------------------------------------ 智能体宿主

  /// M3/M5：感知事件既接到宠物反应，也接到自主循环。
  ///
  /// 「消息找活」的关键：Trigger 只发模式标签，Brain 收到后把线索变成一个目标，
  /// 由模型决定调哪个工具（剪贴板原文按需用 clipboard 工具读，不常驻事件里）。
  /// 气泡只在桌面宠物形态出现，自主执行不受窗口形态影响。
  void _listenPerceptionEvents() {
    clipboardTrigger?.events.listen((event) {
      if (agentPetMode) {
        showBubble(event.summary, mood: PetMood.talk, duration: 6);
        if (event.payload['kind'] == 'english') {
          final draft = speculative?.takeDraft();
          showBubble(draft?.text ?? '要我帮你翻译吗？', mood: PetMood.talk, duration: 8);
        }
      }
      if (!autonomyEnabled) return;
      final goal = switch (event.payload['kind']) {
        'english' => '读取系统剪贴板里的英文内容，帮主人翻译成中文并给一句话摘要',
        'url' => '读取系统剪贴板里的网址，用 http_request 查看页面并给一句话摘要',
        'number' => '读取系统剪贴板里的数字串，判断它可能是电话号码、金额还是编号',
        _ => null,
      };
      if (goal != null) unawaited(brain?.submitGoal(goal));
    });
    appFocusTrigger?.events.listen((event) {
      if (agentPetMode && event.payload['category'] == 'editor') {
        showBubble('写代码辛苦了，要不要伸个懒腰？', mood: PetMood.talk, duration: 6);
      }
    });
  }

  @override
  String get agentPetId => active?.id ?? '';

  @override
  bool get agentOnlineAvailable =>
      settings.chatBackend == ChatBackendKind.openai && settings.baseUrl.trim().isNotEmpty;

  @override
  AppSettings get agentSettings => settings;

  @override
  bool get agentPetMode => window.isDesktop && mode == WindowMode.pet;

  @override
  void agentBubble(String text, {PetMood mood = PetMood.talk}) {
    showBubble(text, mood: mood, duration: 8);
  }

  @override
  void agentHop() {
    action = PetAction.hop;
    actionSeed++;
    notifyListeners();
  }

  @override
  void agentStroll({bool run = false}) => unawaited(stroll(run: run));

  @override
  void agentBeg() => lieDown();

  @override
  void agentSleep() {
    if (mode != WindowMode.pet || dragging || typing) return;
    mood = PetMood.sleepy;
    bubble = pick(['Zzz……（睡着了）']);
    emitBurst(PetBurst.sleep);
    notifyListeners();
  }

  @override
  void agentWake() => wake();

  @override
  void agentSpeak(String text) {
    if (settings.tts) unawaited(speech.speak(text));
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
        ChatMessage(role: ChatRole.pet, text: settings.personaOf(active!).greeting, at: DateTime.now(), mood: PetMood.happy),
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

  /// 写入 / 清除自定义人设。传 null 表示恢复宠物包自带的默认人设。
  Future<void> updatePersona(String petId, PetPersonality? persona) async {
    final map = Map<String, PetPersonality>.from(settings.petPersonas);
    if (persona == null) {
      map.remove(petId);
    } else {
      map[petId] = persona;
    }
    settings = settings.copyWith(petPersonas: map);
    await store.saveSettings(settings);
    notifyListeners();
  }

  /// 某人设是否是「改过的」：与宠物包默认不同才算自定义。
  bool isPersonaCustomized(Pet pet) {
    final override = settings.petPersonas[pet.id];
    return override != null && !override.sameAs(pet.personality);
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
    final voiceChanged = next.voice != settings.voice;
    settings = next;
    await store.saveSettings(settings);
    if (settings.tts == false) unawaited(speech.stop());
    if (voiceChanged) unawaited(speech.setVoice(next.voice));
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
    unawaited(memoryService?.flush());
    memoryService?.dispose();
    watchdog?.dispose();
    clipboardTrigger?.dispose();
    appFocusTrigger?.dispose();
    autonomy?.dispose();
    brain?.dispose();
    disposeBehavior();
    disposeChat();
    burstController.close();
    _tray?.destroy();
    window.dispose();
    super.dispose();
  }
}
