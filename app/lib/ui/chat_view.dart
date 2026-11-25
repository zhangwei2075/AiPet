import 'package:flutter/material.dart';

import '../models/chat.dart';
import '../models/pet.dart';
import '../models/pet_memory.dart';
import '../models/settings.dart';
import '../state/app_controller.dart';
import 'common.dart';
import 'memory_page.dart';
import 'speech_bubble.dart';
import 'theme.dart';

class ChatView extends StatefulWidget {
  const ChatView({super.key, required this.controller});

  final AppController controller;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  int _lastCount = 0;
  bool _hadTyping = false;
  String? _lastStream;

  AppController get controller => widget.controller;
  Pet? get pet => controller.active;

  @override
  void initState() {
    super.initState();
    _input.addListener(_onInputChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _onInputChanged() => setState(() {});

  @override
  void dispose() {
    _input.removeListener(_onInputChanged);
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scroll.hasClients) return;
    final target = _scroll.position.maxScrollExtent;
    if (animate) {
      _scroll.animateTo(target, duration: Motion.base, curve: Motion.curve);
    } else {
      _scroll.jumpTo(target);
    }
  }

  Future<void> _send([String? preset]) async {
    final text = preset ?? _input.text;
    if (text.trim().isEmpty || controller.typing) return;
    _input.clear();
    await controller.sendMessage(text);
    if (mounted) _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final accent = pet?.accent ?? Theme.of(context).colorScheme.primary;
    if (pet == null) {
      return const Padding(
          padding: EdgeInsets.all(Insets.x3), child: EmptyHint(text: '还没有宠物'));
    }

    if (_lastCount != controller.messages.length ||
        _hadTyping != controller.typing ||
        _lastStream != controller.streamingText) {
      final streamingStarted =
          controller.streamingText != null && _lastStream == null;
      _lastCount = controller.messages.length;
      _hadTyping = controller.typing;
      _lastStream = controller.streamingText;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToBottom(animate: !streamingStarted),
      );
    }

    final empty =
        controller.messages.isEmpty && controller.streamingText == null;

    return Padding(
      padding: const EdgeInsets.all(Insets.x2),
      child: GlassCard(
        padding: EdgeInsets.zero,
        radius: Radii.panel,
        child: Column(
          children: [
            // 聊天窗没有标题栏，给一条细抓手，否则窗口没法挪位置。
            if (controller.isDesktop)
              MouseRegion(
                cursor: SystemMouseCursors.move,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanDown: (_) => controller.beginWindowDrag(),
                  child: SizedBox(
                    height: 12,
                    child: Center(
                      child: Container(
                        width: 32,
                        height: 3,
                        decoration: BoxDecoration(
                          color: AppColors.line,
                          borderRadius: BorderRadius.circular(Radii.pill),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            _header(accent),
            const Divider(height: 1),
            _statusBanner(accent),
            Expanded(child: _messages(accent)),
            if (controller.typing) _typingRow(accent),
            if (controller.chatError != null) _errorBanner(),
            if (!empty) _quickChips(accent),
            _inputBar(accent),
          ],
        ),
      ),
    );
  }

  Widget _header(Color accent) {
    final backend = controller.settings.chatBackend;
    final status = backend == ChatBackendKind.openai
        ? '${controller.settings.model} · 可执行工具'
        : '本地小脑 · 也能操作电脑';
    final growth = memory?.growth.label;
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(Insets.x4, Insets.x3, Insets.x2, Insets.x3),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tintOf(accent, 0.16),
              border: Border.all(color: AppColors.surface, width: 2),
            ),
            child: ClipOval(
                child: Image(
                    image: pet!.imageFor(PetMood.idle), fit: BoxFit.cover)),
          ),
          const SizedBox(width: Insets.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        pet!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.2),
                      ),
                    ),
                    if (growth != null) ...[
                      const SizedBox(width: 6),
                      TagChip(label: growth, color: accent, dense: true),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: controller.typing
                            ? AppColors.warning
                            : AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        controller.typing ? '正在想…' : status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.inkSoft),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          RoundIconButton(
            icon: controller.settings.tts
                ? Icons.volume_up_rounded
                : Icons.volume_off_outlined,
            tooltip: controller.settings.tts ? '关闭朗读' : '朗读回复',
            size: 32,
            iconColor:
                controller.settings.tts ? inkOn(accent) : AppColors.inkFaint,
            onPressed: () async {
              await controller.toggleTts();
              if (mounted) setState(() {});
            },
          ),
          RoundIconButton(
            icon: Icons.psychology_alt_outlined,
            tooltip: '它记得什么',
            size: 32,
            onPressed: _showMemory,
          ),
          if (controller.messages.isNotEmpty)
            RoundIconButton(
              icon: Icons.delete_outline_rounded,
              tooltip: '清空记录',
              size: 32,
              onPressed: () {
                controller.clearChat();
                setState(() {});
              },
            ),
          RoundIconButton(
            icon: Icons.close_rounded,
            tooltip: '收起（Esc）',
            size: 32,
            onPressed: controller.closeChat,
          ),
        ],
      ),
    );
  }

  /// 当前正在执行的任务状态：目标、第几步、正在调用的工具、最近动作。
  Widget _statusBanner(Color accent) {
    final activity = controller.agentActivity;
    final detail = activity.statusDetail;
    if (detail == null) return const SizedBox.shrink();
    final recent = activity.recent.take(2).toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(Insets.x4, 9, Insets.x4, 10),
      decoration: BoxDecoration(
        color: tintOf(accent, 0.06),
        border: const Border(bottom: BorderSide(color: AppColors.lineSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.auto_mode_rounded, size: 13, color: inkOn(accent)),
              const SizedBox(width: 6),
              Text(
                detail.title,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: inkOn(accent)),
              ),
              const Spacer(),
              if (activity.goalTitle != null && activity.stepLimit > 0)
                Text(
                  '${activity.step}/${activity.stepLimit} 步',
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.inkSoft),
                ),
            ],
          ),
          const SizedBox(height: 6),
          TaskStatusChip(
            status: detail.detail,
            accent: accent,
            busy: activity.busy,
            ok: activity.lastOk,
            maxWidth: 340,
          ),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 4),
            for (final line in recent)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Text(line.timeLabel,
                        style: const TextStyle(
                            fontSize: 10.5, color: AppColors.inkFaint)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        line.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: line.ok ? AppColors.inkSoft : AppColors.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  PetMemory? get memory => controller.activeMemory;

  Future<void> _showMemory() async {
    final memory = controller.activeMemory;
    if (memory == null) return;
    final accent = pet?.accent ?? Theme.of(context).colorScheme.primary;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${pet == null ? '它' : controller.displayName(pet!)}记得的事'),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TagChip(label: memory.growth.label, color: accent),
                  const SizedBox(width: Insets.x2),
                  Expanded(
                    child: Text(
                      memory.growth.hint,
                      style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.inkSoft,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Insets.x3),
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.pill),
                child: LinearProgressIndicator(
                    value: memory.growthProgress, minHeight: 6),
              ),
              const SizedBox(height: Insets.x3),
              Row(
                children: [
                  _stat('${memory.daysTogether}', '天', '认识'),
                  _stat('${memory.taps}', '次', '摸过'),
                  _stat('${memory.chats}', '轮', '聊过'),
                ],
              ),
              if (memory.topics.isNotEmpty) ...[
                const SizedBox(height: Insets.x3),
                const Text('常聊的话题',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.inkSoft)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    for (final topic in memory.topics.keys.take(4))
                      TagChip(label: topic, dense: true, color: accent),
                  ],
                ),
              ],
              if (memory.notes.isNotEmpty) ...[
                const SizedBox(height: Insets.x3),
                const Text('记下的事',
                    style:
                        TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(
                      Insets.x3, Insets.x2, Insets.x3, Insets.x2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(Radii.xs),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final note in memory.notes.reversed.take(5))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Container(
                                  width: 4,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: tintOf(accent, 0.55),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(note,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        height: 1.5,
                                        color: AppColors.ink)),
                              ),
                            ],
                          ),
                        ),
                      if (memory.notes.length > 5)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text('更早的记在「情景记忆」里',
                              style: TextStyle(
                                  fontSize: 10.5, color: AppColors.inkFaint)),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              MemoryPage.open(context, controller);
            },
            child: const Text('情景记忆…'),
          ),
          TextButton(
            onPressed: () async {
              await controller.clearMemory();
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              if (mounted) setState(() {});
            },
            child: const Text('让它忘掉'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _stat(String value, String unit, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700, height: 1.2)),
              const SizedBox(width: 2),
              Text(unit,
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.inkFaint)),
            ],
          ),
          Text(label,
              style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
        ],
      ),
    );
  }

  Widget _messages(Color accent) {
    if (controller.messages.isEmpty && controller.streamingText == null) {
      return _emptyState(accent);
    }
    final streaming = controller.streamingText;
    final extra = streaming == null ? 0 : 1;
    return SelectionArea(
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(
            Insets.x4, Insets.x4, Insets.x4, Insets.x2),
        itemCount: controller.messages.length + extra,
        itemBuilder: (context, index) {
          if (index >= controller.messages.length) {
            return _bubble(
              ChatMessage(
                  role: ChatRole.pet,
                  text: streaming!.isEmpty ? '…' : streaming,
                  at: DateTime.now()),
              accent,
            );
          }
          return _bubble(controller.messages[index], accent);
        },
      ),
    );
  }

  /// 空态：不只是摆一张图，直接给三个能点的开场，省掉用户想话题的成本。
  Widget _emptyState(Color accent) {
    const starters = <(IconData, String, String)>[
      (Icons.waving_hand_rounded, '摸摸头', '先让它开心一下'),
      (Icons.storage_rounded, '看看磁盘空间', '顺手办件正事'),
      (Icons.emoji_emotions_outlined, '讲个笑话', '随便聊两句'),
    ];
    return SingleChildScrollView(
      padding:
          const EdgeInsets.fromLTRB(Insets.x5, Insets.x5, Insets.x5, Insets.x3),
      child: Column(
        children: [
          Image(image: pet!.imageFor(PetMood.idle), width: 96, height: 96),
          const SizedBox(height: Insets.x3),
          Text(
            '「${controller.settings.personaOf(pet!).catchphrase}」',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 13, height: 1.6, color: AppColors.inkSoft),
          ),
          const SizedBox(height: Insets.x5),
          for (final item in starters)
            Padding(
              padding: const EdgeInsets.only(bottom: Insets.x2),
              child: _StarterRow(
                icon: item.$1,
                title: item.$2,
                hint: item.$3,
                accent: accent,
                onTap: () => _send(item.$2),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bubble(ChatMessage message, Color accent) {
    final isUser = message.role == ChatRole.user;
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.x3),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth * 0.78;
          final bubble = Container(
            constraints: BoxConstraints(maxWidth: maxWidth),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: isUser ? accent : AppColors.surfaceAlt,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(14),
                topRight: const Radius.circular(14),
                bottomLeft: Radius.circular(isUser ? 14 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 14),
              ),
            ),
            child: Text(
              message.text,
              style: TextStyle(
                fontSize: 13,
                height: 1.55,
                color: isUser ? readableOn(accent) : AppColors.ink,
              ),
            ),
          );
          return Row(
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isUser) ...[
                ClipOval(
                  child: Image(
                      image: pet!.imageFor(PetMood.idle),
                      width: 26,
                      height: 26,
                      fit: BoxFit.cover),
                ),
                const SizedBox(width: Insets.x2),
              ],
              Flexible(child: bubble),
            ],
          );
        },
      ),
    );
  }

  Widget _typingRow(Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.x4, 0, Insets.x4, Insets.x2),
      child: Row(
        children: [
          ClipOval(
            child: Image(
                image: pet!.imageFor(PetMood.idle),
                width: 26,
                height: 26,
                fit: BoxFit.cover),
          ),
          const SizedBox(width: Insets.x2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
            ),
            child: TypingDots(color: accent),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner() {
    final long = (controller.chatError ?? '').length > 90;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.x4, 0, Insets.x4, Insets.x2),
      child: AppBanner(
        tone: BannerTone.warning,
        icon: Icons.cloud_off_rounded,
        text: long
            ? '在线模型没连上，先用本地小脑回答。'
            : (controller.chatError ?? '在线模型没连上，先用本地小脑回答。'),
        action: TextButton(
          onPressed: () => controller.openPanel(PanelTab.settings),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 28),
            foregroundColor: AppColors.warning,
            textStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          child: const Text('去设置'),
        ),
      ),
    );
  }

  Widget _quickChips(Color accent) {
    const quick = ['摸摸头', '看看磁盘空间', '列出工作区文件', '讲个笑话'];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Insets.x4),
        itemCount: quick.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) => Center(
          child: PillButton(
            label: quick[index],
            dense: true,
            filled: false,
            color: accent,
            onPressed: () => _send(quick[index]),
          ),
        ),
      ),
    );
  }

  Widget _inputBar(Color accent) {
    final canSend = _input.text.trim().isNotEmpty && !controller.typing;
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(Insets.x3, Insets.x1, Insets.x3, Insets.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              focusNode: _focus,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: '跟它说点什么，或让它操作电脑…',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: Insets.x2),
          AnimatedContainer(
            duration: Motion.fast,
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: canSend ? accent : AppColors.surfaceSunken,
              shape: BoxShape.circle,
            ),
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: canSend ? () => _send() : null,
                child: Icon(
                  Icons.arrow_upward_rounded,
                  color: canSend ? readableOn(accent) : AppColors.inkFaint,
                  size: 19,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 空态里的开场建议行：图标 + 标题 + 说明，右侧箭头。
class _StarterRow extends StatefulWidget {
  const _StarterRow({
    required this.icon,
    required this.title,
    required this.hint,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String hint;
  final Color accent;
  final VoidCallback onTap;

  @override
  State<_StarterRow> createState() => _StarterRowState();
}

class _StarterRowState extends State<_StarterRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: Motion.fast,
          padding:
              const EdgeInsets.symmetric(horizontal: Insets.x3, vertical: 10),
          decoration: BoxDecoration(
            color: _hover ? AppColors.surfaceAlt : AppColors.surface,
            borderRadius: BorderRadius.circular(Radii.control),
            border: Border.all(
                color: _hover
                    ? Color.lerp(AppColors.line, widget.accent, 0.4)!
                    : AppColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                    color: tintOf(widget.accent, 0.14), shape: BoxShape.circle),
                child: Icon(widget.icon, size: 15, color: inkOn(widget.accent)),
              ),
              const SizedBox(width: Insets.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                    Text(widget.hint,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.inkFaint)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 16, color: AppColors.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}
