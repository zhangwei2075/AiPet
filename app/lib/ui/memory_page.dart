import 'package:flutter/material.dart';

import '../agent/memory/episodic_event.dart';
import '../agent/memory/memory_service.dart';
import '../models/pet.dart';
import '../state/app_controller.dart';
import 'common.dart';
import 'theme.dart';

/// 情景记忆管理页（M2）：按天查看 digest 与情景，单日清除 / 一键全清，
/// 顶部带「记录新记忆」总开关。从聊天面板的记忆对话框进入。
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
                _header(days.isNotEmpty),
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

  Widget _header(bool hasDays) {
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
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('它记得什么', style: AppType.titleColor),
                SizedBox(height: 2),
                Text('按天归档的情景记忆',
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
              ],
            ),
          ),
          if (hasDays)
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

  Widget _dayCard(MemoryDayView day) {
    final digest = day.digest;
    final events = day.events;
    final label = _dayLabel(day.day);
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.x3),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(
            Insets.x4, Insets.x3, Insets.x3, Insets.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                const SizedBox(width: Insets.x2),
                Text(
                  '${events.length} 条',
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.inkFaint),
                ),
                const Spacer(),
                if (label != day.day)
                  Padding(
                    padding: const EdgeInsets.only(right: Insets.x2),
                    child: Text(day.day,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.inkFaint)),
                  ),
                RoundIconButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: '忘掉这一天',
                  size: 30,
                  onPressed: () => _clearDay(context, day.day),
                ),
              ],
            ),
            if (digest != null && digest.isNotEmpty) ...[
              const SizedBox(height: Insets.x2),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: Insets.x3, vertical: Insets.x2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(Radii.xs),
                ),
                child: Text(
                  digest,
                  style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.6,
                      fontStyle: FontStyle.italic,
                      color: AppColors.inkSoft),
                ),
              ),
            ],
            const SizedBox(height: Insets.x3),
            for (var i = 0; i < events.length; i++)
              _eventRow(events[i], last: i == events.length - 1),
          ],
        ),
      ),
    );
  }

  /// 一条情景：圆点 + 文本。不做竖线连轨 —— 文本行高不固定，
  /// 用 IntrinsicHeight 撑线既慢又容易在窄窗口里抖。
  Widget _eventRow(EpisodicEvent event, {bool last = false}) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : Insets.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                  color: tintOf(accent, 0.6), shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: Insets.x3),
          Expanded(
            child: Text(
              event.content,
              style: const TextStyle(fontSize: 12.5, height: 1.55),
            ),
          ),
        ],
      ),
    );
  }

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
      _ => day,
    };
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
