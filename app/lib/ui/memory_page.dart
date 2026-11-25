import 'package:flutter/material.dart';

import '../agent/memory/episodic_event.dart';
import '../agent/memory/memory_service.dart';
import '../models/pet.dart';
import '../state/app_controller.dart';
import 'common.dart';
import 'theme.dart';

/// 情景记忆管理页（M2）：按天查看 digest 与情景，单日清除 / 一键全清，
/// 顶部带「记录新记忆」总开关。从聊天面板的记忆对话框进入。
///
/// 版式目标：一条情景能一眼看清「什么时候 / 什么类型 / 说了什么」，
/// 所以固定「时间列 → 圆点 → 正文」三栏，不要弹性的行内拼接 ——
/// 之前时间、类型、正文挤在一行，长短不一，整页看起来就是一团。
class MemoryPage extends StatefulWidget {
  const MemoryPage({super.key, required this.controller});

  final AppController controller;

  static Future<void> open(BuildContext context, AppController controller) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
          builder: (_) => MemoryPage(controller: controller)),
    );
  }

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
  AppController get controller => widget.controller;
  Pet? get pet => controller.active;

  @override
  Widget build(BuildContext context) {
    final service = controller.memoryService;
    final days = (service != null && pet != null)
        ? service.viewDays(pet!.id)
        : const <MemoryDayView>[];
    return Scaffold(
      // 全局主题底色透明（桌宠窗口用），整页导航必须显式给不透明底色。
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 660),
            child: Column(
              children: [
                _header(days),
                Expanded(
                  child: service == null || pet == null
                      ? const EmptyHint(text: '当前没有激活的宠物')
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(
                              Insets.x5, 0, Insets.x5, Insets.x5),
                          children: [
                            AppCard(
                              padding: const EdgeInsets.fromLTRB(
                                  Insets.x4, Insets.x1, Insets.x4, Insets.x1),
                              child: SettingRow(
                                title: '记录新记忆',
                                subtitle: '关掉后不再写入新的情景，已有记录保留',
                                child: Switch(
                                  value: service.extractionEnabled,
                                  onChanged: (value) async {
                                    await service.setExtractionEnabled(value);
                                    if (mounted) setState(() {});
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: Insets.x4),
                            if (days.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 56),
                                child: EmptyHint(
                                  text: '还没有情景记忆\n聊聊天、设个提醒，它就会开始记事',
                                  icon: Icons.psychology_outlined,
                                ),
                              )
                            else
                              for (final day in days) _dayCard(day),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(List<MemoryDayView> days) {
    final total = days.fold<int>(0, (sum, day) => sum + day.events.length);
    final summary = days.isEmpty
        ? '按天归档的情景记忆'
        : '按天归档 · ${days.length} 天 · $total 条';
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(Insets.x3, Insets.x3, Insets.x3, Insets.x4),
      child: Row(
        children: [
          RoundIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: '返回',
              onPressed: () => Navigator.of(context).pop()),
          const SizedBox(width: Insets.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('它记得什么', style: AppType.titleColor),
                const SizedBox(height: 2),
                Text(summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.inkSoft)),
              ],
            ),
          ),
          if (days.isNotEmpty)
            PillButton(
              label: '全部忘掉',
              dense: true,
              filled: false,
              color: AppColors.danger,
              onPressed: () => _clearAll(context),
            ),
        ],
      ),
    );
  }

  /// 一天 = 一张卡：日期头 → 日结摘要 → 逐条情景（按时间正序）。
  Widget _dayCard(MemoryDayView day) {
    final accent = Theme.of(context).colorScheme.primary;
    final digest = day.digest?.trim() ?? '';
    final events = List<EpisodicEvent>.of(day.events)
      ..sort((a, b) => a.at.compareTo(b.at));
    final label = _dayLabel(day.day);
    final isToday = label == '今天';
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.x3),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(
            Insets.x4, Insets.x3, Insets.x3, Insets.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.3,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            day.day,
                            style: const TextStyle(
                                fontSize: 11.5,
                                height: 1.3,
                                color: AppColors.inkFaint,
                                letterSpacing: 0.2),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          TagChip(
                            label: _weekdayLabel(day.day),
                            dense: true,
                            color: isToday ? accent : null,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${events.length} 条',
                            style: const TextStyle(
                                fontSize: 11,
                                height: 1.3,
                                color: AppColors.inkFaint),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                RoundIconButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: '忘掉这一天',
                  size: 30,
                  onPressed: () => _clearDay(context, day.day),
                ),
              ],
            ),
            if (digest.isNotEmpty) ...[
              const SizedBox(height: Insets.x3),
              _digestBlock(digest, accent),
            ],
            if (events.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: Insets.x3),
                child: Text('这天只留下了小结，没有单独的情景。',
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint)),
              )
            else ...[
              const SizedBox(height: Insets.x3),
              for (var i = 0; i < events.length; i++)
                _eventRow(events[i], accent: accent, last: i == events.length - 1),
            ],
          ],
        ),
      ),
    );
  }

  /// 日结摘要：左侧一根 accent 竖条当引文标记，正文不用斜体 ——
  /// 斜体中文在 12px 下笔画糊成一团，读起来比正文还累。
  Widget _digestBlock(String digest, Color accent) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tintOf(accent, 0.06),
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: tintOf(accent, 0.55),
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    Insets.x3, Insets.x2, Insets.x3, Insets.x2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_awesome_rounded,
                            size: 11, color: inkOn(accent)),
                        const SizedBox(width: 4),
                        Text(
                          '一天小结',
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            color: inkOn(accent),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      digest,
                      style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.7,
                          color: AppColors.inkSoft),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 一条情景：固定时间列 + 圆点 + 正文。
  /// importance ≥ 3 的强约定用实心 accent 圆点与更深的字色，扫一眼就能挑出来。
  Widget _eventRow(EpisodicEvent event,
      {required Color accent, bool last = false}) {
    final strong = event.importance >= 3;
    final meta = <String>[
      if (event.kind != EpisodeKind.chat) _kindLabel(event.kind),
      if ((event.tag ?? '').trim().isNotEmpty) '#${event.tag!.trim()}',
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : Insets.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _timeLabel(event.at),
                style: const TextStyle(
                  fontSize: 10.5,
                  height: 1.5,
                  color: AppColors.inkFaint,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: strong ? 7 : 5,
              height: strong ? 7 : 5,
              decoration: BoxDecoration(
                color: strong ? accent : tintOf(accent, 0.42),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: Insets.x2 + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.content,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
                    color: strong ? AppColors.ink : AppColors.inkSoft,
                  ),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    meta.join(' · '),
                    style: const TextStyle(
                        fontSize: 10.5,
                        height: 1.4,
                        color: AppColors.inkFaint,
                        letterSpacing: 0.2),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _timeLabel(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';

  String _kindLabel(EpisodeKind kind) => switch (kind) {
        EpisodeKind.chat => '聊到',
        EpisodeKind.interaction => '互动',
        EpisodeKind.task => '任务',
        EpisodeKind.digest => '摘要',
      };

  /// 「今天 / 昨天 / 前天」，更早的直接显示日期。
  String _dayLabel(String day) {
    final today = DateTime.now();
    final parsed = DateTime.tryParse(day);
    if (parsed == null) return day;
    final diff = DateTime(today.year, today.month, today.day)
        .difference(DateTime(parsed.year, parsed.month, parsed.day))
        .inDays;
    return switch (diff) {
      0 => '今天',
      1 => '昨天',
      2 => '前天',
      _ => '${parsed.month} 月 ${parsed.day} 日',
    };
  }

  String _weekdayLabel(String day) {
    final parsed = DateTime.tryParse(day);
    if (parsed == null) return '';
    return const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][
        parsed.weekday - 1];
  }

  Future<void> _clearDay(BuildContext context, String day) async {
    final pet = this.pet;
    final service = controller.memoryService;
    if (pet == null || service == null) return;
    final ok = await _confirm(context, '忘掉 $day 的事？');
    if (!ok) return;
    await service.clearDay(pet.id, day);
    if (mounted) setState(() {});
  }

  Future<void> _clearAll(BuildContext context) async {
    final pet = this.pet;
    final service = controller.memoryService;
    if (pet == null || service == null) return;
    final ok = await _confirm(context, '让它忘掉所有情景记忆？（成长进度保留）');
    if (!ok) return;
    await service.clearAll(pet.id);
    if (mounted) setState(() {});
  }

  Future<bool> _confirm(BuildContext context, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认一下'),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('再想想')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确定')),
        ],
      ),
    );
    return result ?? false;
  }
}
