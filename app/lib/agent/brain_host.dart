import '../models/pet.dart';
import '../models/settings.dart';

/// Brain 与应用其他部分的边界。
///
/// 抽成接口有两个目的：一是切断 agent 模块对 AppController 的反向依赖
/// （避免循环 import），二是让 Brain 的单元测试可以用假宿主跑全流程。
abstract class BrainHost {
  /// 当前激活宠物的 id（记忆归属）。
  String get agentPetId;

  /// 在线探测是否可用（后端选了 openai 且地址非空）。
  bool get agentOnlineAvailable;

  /// 当前聊天设置（probe 每次实时读取，设置热改立即生效）。
  AppSettings get agentSettings;

  /// 桌面宠物形态才主动冒气泡/做动作；聊天面板打开时只走聊天流。
  bool get agentPetMode;

  /// 冒气泡（桌面形态）。
  void agentBubble(String text, {PetMood mood});

  /// 播放开心跳动作。
  void agentHop();

  /// 出门走一圈。
  void agentStroll({bool run});

  /// 趴下求摸。
  void agentBeg();

  /// 睡觉（走自动入睡路径，会停掉散步等状态）。
  void agentSleep();

  /// 叫醒（睡醒会伸懒腰）。
  void agentWake();

  /// 朗读（宿主自行判断设置里的 TTS 开关）。
  void agentSpeak(String text);
}
