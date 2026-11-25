import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'episodic_event.dart';

/// 一条命中检索的情景。
@immutable
class RetrievedEpisode {
  const RetrievedEpisode(this.event, this.score);

  final EpisodicEvent event;
  final double score;
}

/// 情景检索：importance + recency 半衰期 + 中文 bigram 词面重叠（docs/m2-memory-plan.md §6）。
///
/// 不用 embedding 的理由写在了方案里：语料 ≤400 条时，词面 + 时间衰减够用且零依赖。
class EpisodeRetrieval {
  const EpisodeRetrieval({
    this.topK = 6,
    this.contextBudget = 600,
    this.halfLifeDays = 3,
  });

  final int topK;
  final int contextBudget;
  final double halfLifeDays;

  /// 对当前输入分词：CJK 连续段切 bigram，拉丁/数字按词。
  @visibleForTesting
  Set<String> tokenize(String text) {
    final tokens = <String>{};
    for (final match in RegExp(r'[a-zA-Z0-9]+|\p{Script=Han}+', unicode: true)
        .allMatches(text.toLowerCase())) {
      final run = match.group(0)!;
      if (RegExp(r'^[a-zA-Z0-9]+$').hasMatch(run)) {
        tokens.add(run);
      } else {
        if (run.length == 1) {
          tokens.add(run);
        } else {
          for (var i = 0; i < run.length - 1; i++) {
            tokens.add(run.substring(i, i + 2));
          }
        }
      }
    }
    return tokens;
  }

  List<RetrievedEpisode> retrieve({
    required List<EpisodicEvent> events,
    required String query,
    required DateTime now,
  }) {
    if (events.isEmpty) return const [];
    final queryTokens = tokenize(query);
    final scored = <RetrievedEpisode>[];
    for (final event in events) {
      final days = math.max(0, now.difference(event.at).inMinutes / 1440);
      final recency = math.exp(-days / halfLifeDays);
      final eventTokens = tokenize(event.content);
      final overlap = queryTokens.isEmpty || eventTokens.isEmpty
          ? 0.0
          : queryTokens.intersection(eventTokens).length /
              math.max(4, math.min(10, eventTokens.length)).clamp(1.0, 10.0);
      var score = 1.0 * event.importance + 1.2 * recency + 2.0 * overlap.clamp(0.0, 1.0);
      if (event.kind == EpisodeKind.digest && overlap > 0) score += 0.8;
      scored.add(RetrievedEpisode(event, score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(topK).toList(growable: false);
  }

  /// 在 topK 基础上做字符预算截断（每条前面加「· 」算 2 字符）。
  List<RetrievedEpisode> withinBudget(List<RetrievedEpisode> episodes) {
    var used = 0;
    final result = <RetrievedEpisode>[];
    for (final episode in episodes) {
      final cost = episode.event.content.length + 2;
      if (used + cost > contextBudget) break;
      used += cost;
      result.add(episode);
    }
    return result;
  }
}
