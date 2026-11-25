import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../core/app_mode.dart';
import '../data/memory_store.dart';
import '../data/settings_store.dart';
import '../models/pet.dart';
import '../agent/memory/memory_service.dart';
import '../models/pet_memory.dart';
import '../models/settings.dart';
import '../services/window_service.dart';
import 'controller_types.dart';

/// 宠物互动、拖动与空闲定时行为。
/// 状态字段由 [ChangeNotifier] 子类（AppController）提供，mixin 只负责编排。
mixin PetBehavior on ChangeNotifier {
  AppSettings get settings;
  set settings(AppSettings value);
  Pet? get active;
  WindowMode get mode;
  bool get isDesktop;
  bool get isSleeping;
  PetMood get mood;
  set mood(PetMood value);
  String? get bubble;
  set bubble(String? value);
  bool get typing;
  bool get dragging;
  set dragging(bool value);
  bool get petting;
  set petting(bool value);
  bool get walking;
  set walking(bool value);
  bool get running;
  set running(bool value);
  bool get begging;
  set begging(bool value);
  bool get eating;
  set eating(bool value);
  bool get awaitingTreat;
  set awaitingTreat(bool value);
  bool get wagging;
  set wagging(bool value);
  bool get sniffing;
  set sniffing(bool value);
  PetAction get action;
  set action(PetAction value);
  int get actionSeed;
  set actionSeed(int value);
  int get affection;
  set affection(int value);
  int get facing;
  set facing(int value);
  MemoryStore get memory;
  MemoryService? get memoryService;
  WindowService get window;
  math.Random get random;
  StreamController<PetBurst> get burstController;
  SettingsStore get store;
  String displayName(Pet pet);

  Timer? _bubbleTimer;
  Timer? _moodTimer;
  Timer? _sleepTimer;
  Timer? _wanderTimer;
  Timer? _begTimer;
  Timer? _begScheduler;
  Timer? _dragWatch;
  Timer? _proactiveTimer;
  Timer? _eatTimer;
  Timer? _treatTimer;
  Timer? _wagTimer;
  Timer? _sniffTimer;
  int _dragFlipCount = 0;
  int _dragLastDxSign = 0;
  bool _shakeArmed = false;
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);

  void showBubble(String text, {PetMood mood = PetMood.talk, int duration = 6}) {
    bubble = text;
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

  /// 聊天 / 面板打开时收掉气泡定时器，避免它回头把 mood 改回 idle。
  void cancelBubbleTimer() {
    _bubbleTimer?.cancel();
  }

  void dismissBubble() {
    _bubbleTimer?.cancel();
    bubble = null;
    if (mood != PetMood.sleepy) mood = PetMood.idle;
    notifyListeners();
  }

  void emitBurst(PetBurst kind) {
    if (!burstController.isClosed) burstController.add(kind);
  }

  void wake() {
    _resetSleepTimer();
    _stopBegging();
    if (mood == PetMood.sleepy) {
      mood = PetMood.idle;
      // 睡醒先伸个懒腰再起
      action = PetAction.stretch;
      actionSeed++;
      showBubble(pick(['哈——睡得好饱。', '伸个懒腰～', '唔…醒了？']), mood: PetMood.idle, duration: 4);
      notifyListeners();
    }
  }

  void tapPet({required bool head}) {
    final wasBegging = begging;
    wake();
    if (awaitingTreat) {
      // 讨食窗口里点一下 = 投喂，走专属奖励，不按普通点击计分。
      feedTreat();
      return;
    }
    if (wasBegging) {
      // 冲着「求抚摸」来的：揉肚子双倍奖励，舒服到摇尾巴
      affection += 2;
      unawaited(_rememberTouch(2));
      emitBurst(PetBurst.hearts);
      _wag(2800);
      showBubble(pick(['嘿嘿，就是要这个～', '咕噜咕噜…', '肚子最舒服了！']),
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
      showBubble(pick(['转圈圈！', '看我看我～', '嘿咻——']), mood: PetMood.happy, duration: 3);
      return;
    }

    affection += head ? 2 : 1;
    unawaited(_rememberTouch(head ? 2 : 1));
    action = PetAction.hop;
    actionSeed++;
    if (affection % 19 == 0) {
      mood = PetMood.angry;
      emitBurst(PetBurst.anger);
      showBubble(pick(['不要再戳啦！', '哼，我生气了。', '摸够了没有…']), mood: PetMood.angry, duration: 3);
    } else if (head) {
      emitBurst(PetBurst.hearts);
      // 摸头 + 好感高：舒服到摇尾巴
      if (affection > 10) _wag(2000);
      showBubble(
        pick(['唔…好舒服。', '嘿嘿，再摸一下。', '眯起眼睛…', '最喜欢主人了。']),
        mood: affection > 10 ? PetMood.love : PetMood.happy,
        duration: 3,
      );
    } else {
      emitBurst(PetBurst.note);
      showBubble(
        pick(['！', '陪我玩？', '在呢在呢。', '今天也辛苦了。']),
        mood: PetMood.happy,
        duration: 3,
      );
    }
  }

  void doubleTapPet() {
    wake();
    action = PetAction.spin;
    actionSeed++;
    emitBurst(PetBurst.stars);
  }

  void startPetting() {
    wake();
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
    _wag(2200);
    scheduleIdleReturn();
    notifyListeners();
  }

  void completeAction() {
    if (action == PetAction.none) return;
    action = PetAction.none;
    notifyListeners();
  }

  void scheduleIdleReturn() {
    _moodTimer?.cancel();
    _moodTimer = Timer(const Duration(milliseconds: 2600), () {
      if (typing || petting || dragging) return;
      if (mode == WindowMode.chat) return;
      mood = PetMood.idle;
      notifyListeners();
    });
  }

  Future<void> beginWindowDrag() async {
    if (!isDesktop) return;
    wake();
    _stopBegging();
    dragging = true;
    _dragFlipCount = 0;
    _dragLastDxSign = 0;
    _shakeArmed = false;
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
    // 拖着快速左右甩过 → 落地抖毛 + 晕乎乎一句
    if (_shakeArmed) {
      _shakeArmed = false;
      action = PetAction.shake;
      showBubble(pick(['汪呜…头好晕…', '别再晃我啦！', '甩甩就精神了～']),
          mood: PetMood.happy, duration: 3);
    } else {
      action = PetAction.drop;
    }
    actionSeed++;
    persistWindowPosition();
    notifyListeners();
  }

  /// 拖动方向：不 notify，PetStage 的 ticker 每帧直接读取 facing。
  void _onDragMove(Offset delta) {
    if (delta.dx.abs() > 0.2) {
      facing = delta.dx > 0 ? 1 : -1;
    }
    // 甩动检测：拖拽中快速左右换向累计到 4 次就标记，松手时抖毛
    if (dragging) {
      final sign = delta.dx.sign.round();
      if (sign != 0) {
        if (_dragLastDxSign != 0 && sign != _dragLastDxSign) _dragFlipCount++;
        _dragLastDxSign = sign;
      }
      if (_dragFlipCount >= 4) _shakeArmed = true;
    }
  }

  Future<void> persistWindowPosition() async {
    if (!isDesktop) return;
    await window.rememberPosition();
    final position = window.positionString;
    if (position == null) return;
    settings = settings.copyWith(petWindowPosition: position);
    await store.saveSettings(settings);
  }

  void startIdleTimers() {
    _resetSleepTimer();
    _scheduleWander();
    _scheduleBeg(retry: true);
    scheduleProactive();
  }

  void _resetSleepTimer() {
    _sleepTimer?.cancel();
    if (!settings.autoSleep) return;
    _sleepTimer = Timer(const Duration(seconds: 90), () {
      if (mode != WindowMode.pet || dragging || typing) return;
      mood = PetMood.sleepy;
      bubble = pick(['呼…', 'Zzz…', '（睡着了）']);
      emitBurst(PetBurst.sleep);
      notifyListeners();
    });
  }

  void _scheduleWander() {
    _wanderTimer?.cancel();
    if (!settings.wander || !isDesktop) return;
    final delay = Duration(seconds: 26 + random.nextInt(30));
    _wanderTimer = Timer(delay, () {
      // 三成概率小跑，其余慢走；走完两成概率原地嗅探一会儿
      final doRun = random.nextInt(10) < 3;
      unawaited(stroll(run: doRun).then((_) {
        if (random.nextInt(10) < 2) _sniff(2200);
      }));
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
        ? (150 + random.nextInt(180)).toDouble()
        : (36 + random.nextInt(90)).toDouble();
    final dx = (random.nextBool() ? 1 : -1) * distance;
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
    wake();
    _stopBegging();
    begging = true;
    mood = PetMood.love;
    emitBurst(PetBurst.hearts);
    showBubble(
      pick(['摸摸肚子～', '躺平啦，快摸我！', '求摸摸！', '翻肚皮给你看。']),
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
    final seconds = retry ? 35 + random.nextInt(40) : 80 + random.nextInt(70);
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
    wake();
    affection += 1;
    unawaited(_rememberTouch(1));
    if (random.nextInt(10) < 4) {
      // 心情好就汪汪回应
      action = PetAction.bark;
      actionSeed++;
      showBubble(pick(['汪！', '汪汪！', '汪——在呢！']), mood: PetMood.happy, duration: 3);
    } else {
      showBubble(pick(['在呢。', '戳我做什么～', '汪？']), mood: PetMood.happy, duration: 3);
    }
  }

  /// 记录一次互动，撞到里程碑（第 20/50/100 次）时额外冒一句话。
  Future<void> _rememberTouch(int amount) async {
    final pet = active;
    if (pet == null) return;
    memoryService?.recordInteraction(pet.id, '被摸', amount: amount);
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
    await memoryService?.clearAll(pet.id);
    affection = 0;
    notifyListeners();
  }

  T pick<T>(List<T> options) => options[random.nextInt(options.length)];

  // ------------------------------------------------------------ 主动行为

  /// 按宠物性格给主动行为加权：贪吃→讨食，黏人→求摸，元气→小跑。
  ///  traits 来自 petpack，所以「有财」不用在代码里写死也能拿到专属倾向。
  ProactiveKind proactiveKindFor(Pet pet) {
    final weights = proactiveWeights(settings.personaOf(pet).traits);
    final total = weights.values.fold(0, (sum, w) => sum + w);
    return proactiveKindAt(weights, random.nextInt(total));
  }

  /// 3~6 分钟发起一次主动行为；关闭开关或切到移动端时自动停表。
  void scheduleProactive() {
    _proactiveTimer?.cancel();
    if (!settings.proactive || !isDesktop) return;
    final seconds = 180 + random.nextInt(180);
    _proactiveTimer = Timer(Duration(seconds: seconds), () {
      if (mode == WindowMode.pet &&
          !dragging &&
          !typing &&
          !isSleeping &&
          !petting &&
          !eating) {
        triggerProactive();
      }
      scheduleProactive();
    });
  }

  /// 立即发起一次主动行为（面板/调试也可直接调用）。
  void triggerProactive() {
    final pet = active;
    if (pet == null) return;
    final kind = proactiveKindFor(pet);
    if (kind == ProactiveKind.treat) {
      begForTreat(pet);
    } else if (kind == ProactiveKind.cuddle) {
      lieDown();
      showBubble('${displayName(pet)}想被摸摸～', mood: PetMood.love, duration: 5);
    } else if (kind == ProactiveKind.zoomies) {
      action = PetAction.bark;
      actionSeed++;
      unawaited(stroll(run: true));
      emitBurst(PetBurst.stars);
      showBubble(pick(['汪！憋不住啦，跑一圈！', '嗷呜——冲！', '汪汪，活动筋骨～']),
          mood: PetMood.happy, duration: 4);
    } else {
      emitBurst(PetBurst.note);
      showBubble(proactiveLine(pet), mood: PetMood.happy, duration: 5);
    }
  }

  /// 讨食：播 eat 逐帧动画，并开一个 12 秒的投喂窗口。
  void begForTreat(Pet pet) {
    wake();
    eating = true;
    awaitingTreat = true;
    showBubble('${settings.personaOf(pet).catchphrase} 有没有小零食？',
        mood: PetMood.love, duration: 5);
    emitBurst(PetBurst.note);
    notifyListeners();
    _eatTimer?.cancel();
    _eatTimer = Timer(const Duration(seconds: 4), () {
      eating = false;
      notifyListeners();
    });
    _treatTimer?.cancel();
    _treatTimer = Timer(const Duration(seconds: 12), () {
      awaitingTreat = false;
      notifyListeners();
    });
  }

  /// 投喂窗口内点一下宠物 = 吃到零食，额外奖励并收起讨食动画。
  void feedTreat() {
    memoryService?.recordInteraction(active?.id ?? '', '被投喂');
    awaitingTreat = false;
    eating = false;
    _eatTimer?.cancel();
    _treatTimer?.cancel();
    affection += 3;
    unawaited(_rememberTouch(3));
    // 吃到零食作揖庆祝，吃完意犹未尽摇尾巴
    action = PetAction.celebrate;
    actionSeed++;
    emitBurst(PetBurst.hearts);
    _wag(3200);
    showBubble(
      pick(['呜哇，是零食！谢谢主人～', '好好吃！再来一口嘛。', '最喜欢主人了！']),
      mood: PetMood.love,
      duration: 4,
    );
  }

  /// 开心摇尾巴一小段：互动后的余韵，PetStage 里作为循环帧动画表现。
  void _wag(int milliseconds) {
    wagging = true;
    notifyListeners();
    _wagTimer?.cancel();
    _wagTimer = Timer(Duration(milliseconds: milliseconds), () {
      wagging = false;
      notifyListeners();
    });
  }

  /// 原地嗅探一小段：漫步途中的好奇时刻。
  void _sniff(int milliseconds) {
    if (!isDesktop || mode != WindowMode.pet) return;
    if (dragging || typing || isSleeping || begging) return;
    sniffing = true;
    notifyListeners();
    _sniffTimer?.cancel();
    _sniffTimer = Timer(Duration(milliseconds: milliseconds), () {
      sniffing = false;
      notifyListeners();
    });
  }

  String proactiveLine(Pet pet) {
    return pick([
      settings.personaOf(pet).catchphrase,
      '${displayName(pet)}在呢，主人在忙吗？',
      '陪我待一会儿嘛～',
      '今天的天气很适合打盹。',
    ]);
  }

  void disposeBehavior() {
    _bubbleTimer?.cancel();
    _moodTimer?.cancel();
    _sleepTimer?.cancel();
    _wanderTimer?.cancel();
    _begTimer?.cancel();
    _begScheduler?.cancel();
    _dragWatch?.cancel();
    _proactiveTimer?.cancel();
    _eatTimer?.cancel();
    _treatTimer?.cancel();
    _wagTimer?.cancel();
    _sniffTimer?.cancel();
  }
}
