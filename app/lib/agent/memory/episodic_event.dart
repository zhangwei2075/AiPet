import 'package:flutter/foundation.dart';

/// 情景类型。
enum EpisodeKind { chat, interaction, task, digest }

/// 一条情景：一句「以宠物视角记下的客观事实」，不是原始聊天记录。
///
/// 设计要点（docs/m2-memory-plan.md §3）：
/// · 存事实不存原话——隐私降噪，检索词面更稳；
/// · importance 写入时定（1 日常 / 2 有信息量 / 3 强约定），淘汰按它升序；
/// · digest 本身也是事件，天然参与检索。
@immutable
class EpisodicEvent {
  const EpisodicEvent({
    required this.id,
    required this.petId,
    required this.at,
    required this.kind,
    required this.content,
    this.importance = 2,
    this.tag,
  });

  final String id;
  final String petId;
  final DateTime at;
  final EpisodeKind kind;
  final String content;
  final int importance;
  final String? tag;

  EpisodicEvent copyWith({String? content, int? importance, String? tag}) {
    return EpisodicEvent(
      id: id,
      petId: petId,
      at: at,
      kind: kind,
      content: content ?? this.content,
      importance: importance ?? this.importance,
      tag: tag ?? this.tag,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'petId': petId,
        'at': at.toIso8601String(),
        'kind': kind.name,
        'content': content,
        'importance': importance,
        if (tag != null) 'tag': tag,
      };

  static EpisodicEvent fromJson(Map<String, dynamic> json) {
    return EpisodicEvent(
      id: json['id'] as String,
      petId: json['petId'] as String,
      at: DateTime.parse(json['at'] as String),
      kind: EpisodeKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => EpisodeKind.chat,
      ),
      content: json['content'] as String,
      importance: (json['importance'] as num?)?.toInt() ?? 2,
      tag: json['tag'] as String?,
    );
  }
}

/// 单宠物情景数据的分区结构。
class PetEpisodes {
  PetEpisodes({
    Map<String, List<EpisodicEvent>>? days,
    Map<String, String>? digests,
  })  : days = days ?? <String, List<EpisodicEvent>>{},
        digests = digests ?? <String, String>{};

  /// 按天分区：key = 'yyyy-MM-dd'。
  final Map<String, List<EpisodicEvent>> days;

  /// 日结摘要：key = 'yyyy-MM-dd'（该日的事件摘要，次日生成）。
  final Map<String, String> digests;

  Map<String, dynamic> toJson() => {
        'days': {
          for (final entry in days.entries)
            entry.key: [for (final event in entry.value) event.toJson()],
        },
        'digests': digests,
      };

  static PetEpisodes fromJson(Map<String, dynamic> json) {
    final daysRaw = (json['days'] as Map?)?.cast<String, dynamic>() ?? const {};
    final digestsRaw = (json['digests'] as Map?)?.cast<String, dynamic>() ?? const {};
    return PetEpisodes(
      days: {
        for (final entry in daysRaw.entries)
          entry.key: [
            if (entry.value is List)
              for (final item in entry.value as List)
                if (item is Map) EpisodicEvent.fromJson(item.cast<String, dynamic>()),
          ],
      },
      digests: digestsRaw.map((k, v) => MapEntry(k, v.toString())),
    );
  }
}

String dayKeyOf(DateTime time) =>
    '${time.year.toString().padLeft(4, '0')}-'
    '${time.month.toString().padLeft(2, '0')}-'
    '${time.day.toString().padLeft(2, '0')}';
