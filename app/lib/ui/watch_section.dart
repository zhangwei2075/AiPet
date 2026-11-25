import 'package:flutter/material.dart';

import '../agent/watch.dart';
import '../state/app_controller.dart';
import 'common.dart';
import 'theme.dart';

/// 设置页的「简讯订阅」分组。
///
/// 智能体在聊天里用 `watch_create` 开通的订阅也出现在这里 —— 主人能看见、
/// 能暂停、能立刻抓一次、能删掉，不至于变成「它自己偷偷在跑」。
class WatchSection extends StatefulWidget {
  const WatchSection({
    super.key,
    required this.controller,
    required this.accent,
  });

  final AppController controller;
  final Color accent;

  @override
  State<WatchSection> createState() => _WatchSectionState();
}

class _WatchSectionState extends State<WatchSection> {
  List<Watch> _watches = const [];
  bool _loading = true;
  String? _busyId;

  WatchService? get _service => widget.controller.watchService;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final service = _service;
    if (service == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final list = await service.list();
    if (!mounted) return;
    setState(() {
      _watches = list;
      _loading = false;
    });
  }

  Future<void> _runNow(Watch watch) async {
    setState(() => _busyId = watch.id);
    final result = await _service?.runNow(watch.id);
    if (!mounted) return;
    setState(() => _busyId = null);
    await _refresh();
    if (!mounted) return;
    final error = result?.watch.lastError;
    _toast(error == null
        ? '抓到 ${result?.fetched ?? 0} 条，命中 ${result?.hits ?? 0} 条'
        : '抓取失败：$error');
  }

  Future<void> _toggle(Watch watch, bool enabled) async {
    await _service?.setEnabled(watch.id, enabled);
    await _refresh();
  }

  Future<void> _delete(Watch watch) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删掉「${watch.name}」？'),
        content: const Text('删掉后就不再抓取，历史推送记录保留在记忆里。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('算了')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删掉')),
        ],
      ),
    );
    if (ok != true) return;
    await _service?.remove(watch.id);
    await _refresh();
  }

  Future<void> _create() async {
    final draft = await showDialog<_Draft>(
      context: context,
      builder: (context) => const _CreateWatchDialog(),
    );
    if (draft == null) return;
    final service = _service;
    if (service == null) return;
    final watch = await service.create(
      name: draft.name,
      keywords: draft.keywords,
      intervalMinutes: draft.intervalMinutes,
    );
    await service.runNow(watch.id);
    await _refresh();
    if (!mounted) return;
    _toast('已开通「${watch.name}」，之后命中关键词会主动提醒你');
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Insets.x3),
            child: Text('正在读取订阅…',
                style: TextStyle(fontSize: 12, color: AppColors.inkFaint)),
          )
        else if (_watches.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Insets.x2, bottom: Insets.x2),
            child: Text(
              '还没有订阅。可以让它自己建：「订阅财联社，关注光模块、光通信和 AI」。\n'
              '也能在这里手动加 —— 它会按间隔抓取，命中关键词就主动告诉你。',
              style: const TextStyle(
                  fontSize: 12, height: 1.6, color: AppColors.inkSoft),
            ),
          )
        else
          for (final watch in _watches) ...[
            _WatchRow(
              watch: watch,
              accent: accent,
              busy: _busyId == watch.id,
              onRun: () => _runNow(watch),
              onToggle: (value) => _toggle(watch, value),
              onDelete: () => _delete(watch),
            ),
            if (watch != _watches.last) const Divider(height: Insets.x4),
          ],
        const SizedBox(height: Insets.x2),
        Align(
          alignment: Alignment.centerLeft,
          child: PillButton(
            label: '新建订阅',
            icon: Icons.add_rounded,
            dense: true,
            filled: false,
            onPressed: _service == null ? null : _create,
          ),
        ),
      ],
    );
  }
}

class _WatchRow extends StatelessWidget {
  const _WatchRow({
    required this.watch,
    required this.accent,
    required this.busy,
    required this.onRun,
    required this.onToggle,
    required this.onDelete,
  });

  final Watch watch;
  final Color accent;
  final bool busy;
  final VoidCallback onRun;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final keys = watch.keywords.isEmpty ? '全部消息' : watch.keywords.join(' · ');
    final last = watch.lastRunAt == null ? '还没抓过' : '上次 ${_ago(watch.lastRunAt!)}';
    final error = watch.lastError;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        watch.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            height: 1.3),
                      ),
                    ),
                    const SizedBox(width: 6),
                    TagChip(
                        label: watch.source.label, color: accent, dense: true),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '$keys · 每 ${watch.intervalMinutes} 分钟 · $last'
                  '${error == null ? '' : ' · $error'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: error == null ? AppColors.inkSoft : AppColors.danger,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Insets.x2),
          Tooltip(
            message: '立刻抓一次',
            child: RoundIconButton(
              icon: busy ? Icons.hourglass_top_rounded : Icons.refresh_rounded,
              onPressed: busy ? null : onRun,
            ),
          ),
          const SizedBox(width: 4),
          Switch(value: watch.enabled, onChanged: onToggle),
          Tooltip(
            message: '删掉这条订阅',
            child: RoundIconButton(
              icon: Icons.delete_outline_rounded,
              onPressed: onDelete,
            ),
          ),
        ],
      ),
    );
  }

  static String _ago(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }
}

class _Draft {
  const _Draft({
    required this.name,
    required this.keywords,
    required this.intervalMinutes,
  });

  final String name;
  final List<String> keywords;
  final int intervalMinutes;
}

class _CreateWatchDialog extends StatefulWidget {
  const _CreateWatchDialog();

  @override
  State<_CreateWatchDialog> createState() => _CreateWatchDialogState();
}

class _CreateWatchDialogState extends State<_CreateWatchDialog> {
  final _name = TextEditingController(text: '财联社·光模块');
  final _keywords = TextEditingController(text: '光模块, 光通信, AI, 股票');
  final _interval = TextEditingController(text: '30');

  @override
  void dispose() {
    _name.dispose();
    _keywords.dispose();
    _interval.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final minutes = int.tryParse(_interval.text.trim()) ??
        WatchService.minIntervalMinutes;
    Navigator.pop(
      context,
      _Draft(
        name: name,
        keywords: [
          for (final k in _keywords.text.split(RegExp(r'[,，、\s]+')))
            if (k.trim().isNotEmpty) k.trim(),
        ],
        intervalMinutes: minutes < WatchService.minIntervalMinutes
            ? WatchService.minIntervalMinutes
            : minutes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建简讯订阅'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppField(
              label: '名称',
              child: TextField(
                controller: _name,
                decoration: const InputDecoration(hintText: '例如：财联社·光模块'),
              ),
            ),
            AppField(
              label: '关键词',
              hint: '用逗号或空格分隔，命中任一就提醒；留空表示全部推送',
              child: TextField(
                controller: _keywords,
                decoration:
                    const InputDecoration(hintText: '光模块, 光通信, AI, 股票'),
              ),
            ),
            AppField(
              label: '间隔（分钟）',
              hint: '最小 ${WatchService.minIntervalMinutes} 分钟',
              child: TextField(
                controller: _interval,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: '30'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        TextButton(onPressed: _submit, child: const Text('开通')),
      ],
    );
  }
}
