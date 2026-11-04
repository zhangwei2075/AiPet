import 'dart:math' as math;

/// 成长阶段：由「摸头 + 聊天」累计出来的互动量决定。
enum PetGrowth {
  stranger('初识', '刚搬进来，还有点拘谨', 0),
  familiar('熟络', '会主动蹭过来了', 10),
  attached('黏人', '你去哪它都想跟着', 30),
  inseparable('形影不离', '已经把你当成全世界', 70);

  const PetGrowth(this.label, this.hint, this.minPoints);

  final String label;
  final String hint;
  final int minPoints;

  static PetGrowth forPoints(int points) {
    var result = PetGrowth.stranger;
    for (final stage in PetGrowth.values) {
      if (points >= stage.minPoints) result = stage;
    }
    return result;
  }

  PetGrowth? get next => this == PetGrowth.values.last ? null : PetGrowth.values[index + 1];

  /// 在当前阶段里的进度 0~1。
  double progressOf(int points) {
    final nextStage = next;
    if (nextStage == null) return 1;
    final span = nextStage.minPoints - minPoints;
    if (span <= 0) return 1;
    return ((points - minPoints) / span).clamp(0.0, 1.0);
  }

  /// 距离下一阶段还差多少点（已满级返回 0）。
  int remainingToNext(int points) {
    final nextStage = next;
    if (nextStage == null) return 0;
    return math.max(0, nextStage.minPoints - points);
  }
}

/// 一只宠物的长期记忆：见面多久、被摸过几次、聊过什么、记下了哪些里程碑。
///
/// 只保存「摘要级」的信息，不保存完整对话（对话本身在 `aipet.history.v1`）。
class PetMemory {
  PetMemory({
    required this.petId,
    required this.firstMet,
    required this.lastSeen,
    this.taps = 0,
    this.chats = 0,
    List<String>? notes,
    Map<String, int>? topics,
  })  : notes = notes ?? <String>[],
        topics = topics ?? <String, int>{};

  final String petId;
  DateTime firstMet;
  DateTime lastSeen;
  int taps;
  int chats;
  final List<String> notes;
  final Map<String, int> topics;

  /// 互动点：摸一下算 1，聊一轮算 2（说话比摸头更亲近）。
  int get points => taps + chats * 2;

  PetGrowth get growth => PetGrowth.forPoints(points);

  int get daysTogether {
    final days = DateTime.now().difference(firstMet).inDays;
    return days < 0 ? 0 : days + 1;
  }

  /// 阶段进度 0~1，用于界面上的小进度条。
  double get growthProgress => growth.progressOf(points);

  /// 拼进 system prompt 的记忆片段。没有实质内容时返回空串，避免污染提示词。
  String get promptSummary {
    if (taps == 0 && chats == 0 && topics.isEmpty) return '';
    final buffer = StringBuffer();
    buffer.writeln('你和主人已经认识 $daysTogether 天了（第一次见面：${_date(firstMet)}）。');
    buffer.writeln('主人摸过你 $taps 次，和你说过 $chats 轮话，你们现在是「${growth.label}」阶段。');
    if (topics.isNotEmpty) {
      final top = topics.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      buffer.writeln('主人最近常提到：${top.take(3).map((e) => e.key).join('、')}。');
    }
    if (notes.isNotEmpty) {
      buffer.writeln('你记得这些事：${notes.take(3).join('；')}。');
    }
    return buffer.toString().trim();
  }

  /// 界面上展示的一行摘要。
  String get shortLine =>
      '认识 $daysTogether 天 · 摸过 $taps 次 · 聊过 $chats 轮 · ${growth.label}';

  PetMemory copyWith({
    DateTime? lastSeen,
    int? taps,
    int? chats,
  }) =>
      PetMemory(
        petId: petId,
        firstMet: firstMet,
        lastSeen: lastSeen ?? this.lastSeen,
        taps: taps ?? this.taps,
        chats: chats ?? this.chats,
        notes: List<String>.from(notes),
        topics: Map<String, int>.from(topics),
      );

  Map<String, dynamic> toJson() => {
        'petId': petId,
        'firstMet': firstMet.toIso8601String(),
        'lastSeen': lastSeen.toIso8601String(),
        'taps': taps,
        'chats': chats,
        'notes': notes,
        'topics': topics,
      };

  factory PetMemory.fromJson(Map<String, dynamic> json, {required String petId}) {
    final now = DateTime.now();
    return PetMemory(
      petId: petId,
      firstMet: DateTime.tryParse(json['firstMet']?.toString() ?? '') ?? now,
      lastSeen: DateTime.tryParse(json['lastSeen']?.toString() ?? '') ?? now,
      taps: _asInt(json['taps']),
      chats: _asInt(json['chats']),
      notes: (json['notes'] as List?)?.map((e) => e.toString()).where((e) => e.isNotEmpty).toList() ?? [],
      topics: (json['topics'] as Map?)?.map((key, value) => MapEntry(key.toString(), _asInt(value))) ?? {},
    );
  }

  static String _date(DateTime time) => '${time.month} 月 ${time.day} 日';

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
