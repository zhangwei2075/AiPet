import 'package:flutter/material.dart';

import '../agent/memory/memory_service.dart';
import '../models/pet.dart';
import '../state/app_controller.dart';
import 'theme.dart';

/// 情景记忆管理页（M2）：按天查看 digest 与情景，单日清除 / 一键全清，
/// 顶部带「记录新记忆」总开关。从聊天面板的记忆对话框进入。
class MemoryPage extends StatefulWidget {
  const MemoryPage({super.key, required this.controller});

  final AppController controller;

  static Future<void> open(BuildContext context, AppController controller) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => MemoryPage(controller: controller)),
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
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('它记得什么', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        actions: [
          if (days.isNotEmpty)
            TextButton(
              onPressed: () => _clearAll(context),
              child: const Text('全部忘掉', style: TextStyle(color: AppColors.danger)),
            ),
        ],
      ),
      body: service == null || pet == null
          ? const Center(child: Text('当前没有激活的宠物'))
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('记录新记忆', style: TextStyle(fontSize: 14.5)),
                  value: service.extractionEnabled,
                  onChanged: (value) async {
                    await service.setExtractionEnabled(value);
                    if (mounted) setState(() {});
                  },
                ),
                const Divider(height: 20),
                if (days.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Text(
                        '还没有情景记忆。\n聊聊天、设个提醒，它就会开始记事。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.inkSoft, fontSize: 13, height: 1.8),
                      ),
                    ),
                  )
                else
                  ...[for (final day in days) _dayCard(context, day)],
                const SizedBox(height: 10),
              ],
            ),
    );
  }

  Widget _dayCard(BuildContext context, MemoryDayView day) {
    final digest = day.digest;
    final events = day.events;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(_dayLabel(day.day),
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                const Spacer(),
                InkWell(
                  onTap: () => _clearDay(context, day.day),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.delete_outline_rounded, size: 17, color: AppColors.inkSoft),
                  ),
                ),
              ],
            ),
            if (digest != null && digest.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('「$digest」',
                  style: const TextStyle(
                      fontSize: 12.5, fontStyle: FontStyle.italic, color: AppColors.inkSoft)),
            ],
            const SizedBox(height: 6),
            ...events.map((event) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '· ${event.content}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                )),
          ],
        ),
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
    final ok = await _confirm(context, '忘掉$day的事？');
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
        content: Text(message, style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('再想想')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('确定')),
        ],
      ),
    );
    return result ?? false;
  }
}
