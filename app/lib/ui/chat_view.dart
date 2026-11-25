import 'package:flutter/material.dart';

import '../models/chat.dart';
import '../models/settings.dart';
import '../models/pet.dart';
import '../models/pet_memory.dart';
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
      _scroll.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
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
      return const EmptyHint(text: '还没有宠物');
    }

    if (_lastCount != controller.messages.length ||
        _hadTyping != controller.typing ||
        _lastStream != controller.streamingText) {
      final streamingStarted = controller.streamingText != null && _lastStream == null;
      _lastCount = controller.messages.length;
      _hadTyping = controller.typing;
      _lastStream = controller.streamingText;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToBottom(animate: !streamingStarted),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(10),
      child: GlassCard(
        padding: EdgeInsets.zero,
        radius: 26,
        child: Column(
          children: [
            _header(accent),
            const Divider(height: 1),
            _statusBanner(accent),
            Expanded(child: _messages(accent)),
            if (controller.typing) _typingRow(accent),
            if (controller.chatError != null) _errorBanner(),
            _quickChips(accent),
            _inputBar(accent),
          ],
        ),
      ),
    );
  }

  Widget _header(Color accent) {
    final backend = controller.settings.chatBackend;
    final status = backend == ChatBackendKind.openai
        ? 'AI · ${controller.settings.model} · 可执行工具'
        : '本地小脑 · 也能操作电脑';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.14),
            ),
            child: ClipOval(
              child: Image(image: pet!.imageFor(PetMood.idle), fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pet!.name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: controller.typing ? const Color(0xFFE9A23B) : const Color(0xFF57B87A),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        controller.typing ? '正在想…' : '${memory?.growth.label ?? ''} · $status',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppColors.inkSoft),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          RoundIconButton(
            icon: controller.settings.tts ? Icons.volume_up_rounded : Icons.volume_off_outlined,
            tooltip: controller.settings.tts ? '关闭朗读' : '朗读回复',
            color: Colors.transparent,
            iconColor: controller.settings.tts ? accent : AppColors.inkSoft,
            onPressed: () async {
              await controller.toggleTts();
              if (mounted) setState(() {});
            },
          ),
          RoundIconButton(
            icon: Icons.psychology_alt_outlined,
            tooltip: '它记得什么',
            color: Colors.transparent,
            iconColor: AppColors.inkSoft,
            onPressed: _showMemory,
          ),
          if (controller.messages.isNotEmpty)
            RoundIconButton(
              icon: Icons.delete_outline_rounded,
              tooltip: '清空记录',
              color: Colors.transparent,
              iconColor: AppColors.inkSoft,
              onPressed: () {
                controller.clearChat();
                setState(() {});
              },
            ),
          RoundIconButton(
            icon: Icons.close_rounded,
            tooltip: '收起（Esc）',
            color: Colors.transparent,
            iconColor: AppColors.inkSoft,
            onPressed: controller.closeChat,
          ),
        ],
      ),
    );
  }

  /// 当前正在执行的任务状态：目标、第几步、正在调用的工具、最近动作。
  /// 与桌面气泡共用 TaskStatusChip，数据来自 AgentActivity。
  Widget _statusBanner(Color accent) {
    final activity = controller.agentActivity;
    final detail = activity.statusDetail;
    if (detail == null) return const SizedBox.shrink();
    final recent = activity.recent.take(2).toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 9),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.045),
        border: Border(bottom: BorderSide(color: accent.withValues(alpha: 0.12))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.auto_mode_rounded, size: 13, color: accent),
              const SizedBox(width: 6),
              Text(
                detail.title,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: accent),
              ),
              const Spacer(),
              if (activity.goalTitle != null && activity.stepLimit > 0)
                Text(
                  '${activity.step}/${activity.stepLimit} 步',
                  style: const TextStyle(fontSize: 10.5, color: AppColors.inkSoft),
                ),
            ],
          ),
          const SizedBox(height: 6),
          TaskStatusChip(
            status: detail.detail,
            accent: accent,
            busy: activity.busy,
            ok: activity.lastOk,
            maxWidth: 360,
          ),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 5),
            ...recent.map((line) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      Text(line.timeLabel,
                          style: const TextStyle(fontSize: 10, color: AppColors.inkSoft)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          line.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: line.ok ? AppColors.inkSoft : const Color(0xFFC45B4A),
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
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
        backgroundColor: const Color(0xFFFFFBF4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('${pet?.name ?? '它'}记得的事'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TagChip(label: memory.growth.label, color: accent),
                  const SizedBox(width: 8),
                  Text(memory.growth.hint, style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: memory.growthProgress,
                  minHeight: 6,
                  backgroundColor: const Color(0xFFF0E7DA),
                  color: pet?.accent ?? Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '认识 ${memory.daysTogether} 天 · 摸过 ${memory.taps} 次 · 聊过 ${memory.chats} 轮',
                style: const TextStyle(fontSize: 12.5),
              ),
              if (memory.topics.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '常聊的话题：${memory.topics.keys.take(4).join('、')}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                ),
              ],
              if (memory.notes.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('记下的事', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                ...memory.notes.reversed.take(5).map(
                      (note) => Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text('· $note', style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
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

  Widget _messages(Color accent) {
    if (controller.messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: 0.9,
              child: Image(image: pet!.imageFor(PetMood.idle), width: 110, height: 110),
            ),
            const SizedBox(height: 8),
            Text(
              '「${pet!.personality.catchphrase}」',
              style: const TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
            ),
          ],
        ),
      );
    }
    final streaming = controller.streamingText;
    final extra = streaming == null ? 0 : 1;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 10),
      itemCount: controller.messages.length + extra,
      itemBuilder: (context, index) {
        if (index >= controller.messages.length) {
          return _bubble(
            ChatMessage(role: ChatRole.pet, text: streaming!.isEmpty ? '…' : streaming, at: DateTime.now()),
            accent,
          );
        }
        final message = controller.messages[index];
        return _bubble(message, accent);
      },
    );
  }

  Widget _bubble(ChatMessage message, Color accent) {
    final isUser = message.role == ChatRole.user;
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 268),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: isUser ? accent : accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(15),
          topRight: const Radius.circular(15),
          bottomLeft: Radius.circular(isUser ? 15 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 15),
        ),
      ),
      child: Text(
        message.text,
        style: TextStyle(
          fontSize: 13,
          height: 1.5,
          color: isUser ? Colors.white : AppColors.ink,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            ClipOval(
              child: Image(image: pet!.imageFor(PetMood.idle), width: 26, height: 26, fit: BoxFit.cover),
            ),
            const SizedBox(width: 7),
          ],
          Flexible(child: bubble),
        ],
      ),
    );
  }

  Widget _typingRow(Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Row(
        children: [
          ClipOval(
            child: Image(image: pet!.imageFor(PetMood.idle), width: 26, height: 26, fit: BoxFit.cover),
          ),
          const SizedBox(width: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(15),
            ),
            child: TypingDots(color: accent),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF0D3A8)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 14, color: Color(0xFFB57B2A)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              (controller.chatError ?? '').length <= 90
                  ? (controller.chatError ?? '在线模型没连上，先用本地小脑回答。')
                  : '在线模型没连上，先用本地小脑回答。',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Color(0xFF8A5D1E)),
            ),
          ),
          InkWell(
            onTap: () => controller.openPanel(PanelTab.settings),
            child: const Text('去设置', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF8A5D1E))),
          ),
        ],
      ),
    );
  }

  Widget _quickChips(Color accent) {
    const quick = ['摸摸头', '看看磁盘空间', '列出工作区文件', '查看进程', '讲个笑话'];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: quick.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
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
          const SizedBox(width: 8),
          Material(
            color: accent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: controller.typing ? null : () => _send(),
              child: const SizedBox(
                width: 42,
                height: 42,
                child: Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
