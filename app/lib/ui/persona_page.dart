import 'package:flutter/material.dart';

import '../models/pet.dart';
import '../models/settings.dart';
import '../state/app_controller.dart';
import 'common.dart';
import 'theme.dart';

/// 宠物人设编辑器。
///
/// 人设存在设置里（`petPersonas`），不改宠物包：内置宠物是只读 asset，
/// 而且「恢复默认」只需要删掉覆盖项，不用备份原文件。
/// 改完立刻影响聊天、打招呼、主动搭话与卡片标签 —— 它们都走
/// `AppSettings.personaOf()`。
class PersonaPage extends StatefulWidget {
  const PersonaPage({super.key, required this.controller, required this.pet});

  final AppController controller;
  final Pet pet;

  static Future<void> open(
    BuildContext context,
    AppController controller, [
    Pet? pet,
  ]) {
    final target = pet ?? controller.active;
    if (target == null) return Future<void>.value();
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PersonaPage(controller: controller, pet: target),
      ),
    );
  }

  @override
  State<PersonaPage> createState() => _PersonaPageState();
}

class _PersonaPageState extends State<PersonaPage> {
  AppController get controller => widget.controller;
  Pet get pet => widget.pet;

  late final TextEditingController _name;
  late final TextEditingController _greeting;
  late final TextEditingController _catchphrase;
  late final TextEditingController _tone;
  late final TextEditingController _systemPrompt;
  final TextEditingController _traitInput = TextEditingController();

  late List<String> _traits;
  bool _saved = false;
  bool _showDefaultPrompt = false;

  /// 生效人设（设置优先）；编辑框的初值来自它。
  PetPersonality get _current => controller.settings.personaOf(pet);

  @override
  void initState() {
    super.initState();
    final persona = _current;
    _name = TextEditingController(text: controller.displayName(pet));
    _greeting = TextEditingController(text: persona.greeting);
    _catchphrase = TextEditingController(text: persona.catchphrase);
    _tone = TextEditingController(text: persona.tone);
    _systemPrompt = TextEditingController(text: persona.systemPrompt);
    _traits = List<String>.of(persona.traits);
  }

  @override
  void dispose() {
    _name.dispose();
    _greeting.dispose();
    _catchphrase.dispose();
    _tone.dispose();
    _systemPrompt.dispose();
    _traitInput.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------- 操作

  String _or(String value, String fallback) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    await controller.renamePet(pet.id, name);

    // 每一项都为空时视为「没改」，直接恢复默认，避免存一份全空的人设
    // 让招呼语、口头禅变成空字符串。
    final persona = PetPersonality(
      traits: _traits.isEmpty ? pet.personality.traits : _traits,
      tone: _or(_tone.text, pet.personality.tone),
      greeting: _or(_greeting.text, pet.personality.greeting),
      catchphrase: _or(_catchphrase.text, pet.personality.catchphrase),
      systemPrompt: _or(_systemPrompt.text, pet.personality.systemPrompt),
    );
    await controller.updatePersona(pet.id, persona);
    if (!mounted) return;
    setState(() => _saved = true);
  }

  Future<void> _reset() async {
    final ok = await _confirm('恢复 ${controller.displayName(pet)} 的默认人设和名字？');
    if (!ok) return;
    await controller.renamePet(pet.id, null);
    await controller.updatePersona(pet.id, null);
    if (!mounted) return;
    _reloadFrom(controller.settings.personaOf(pet));
    setState(() {
      _saved = false;
      _showDefaultPrompt = false;
    });
  }

  void _reloadFrom(PetPersonality persona) {
    _name.text = controller.displayName(pet);
    _greeting.text = persona.greeting;
    _catchphrase.text = persona.catchphrase;
    _tone.text = persona.tone;
    _systemPrompt.text = persona.systemPrompt;
    _traits = List<String>.of(persona.traits);
  }

  void _addTrait() {
    final value = _traitInput.text.trim();
    if (value.isEmpty) return;
    if (_traits.contains(value)) {
      _traitInput.clear();
      return;
    }
    setState(() {
      _traits = [..._traits, value];
      _saved = false;
    });
    _traitInput.clear();
  }

  void _removeTrait(String trait) {
    setState(() {
      _traits = _traits.where((item) => item != trait).toList();
      _saved = false;
    });
  }

  // -------------------------------------------------------------------- 视图

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 主题的 scaffoldBackgroundColor 是透明的（桌宠窗口用），整页导航要显式底色。
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                _header(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                        Insets.x5, 0, Insets.x5, Insets.x5),
                    children: [
                      if (_saved) ...[
                        AppBanner(
                          text: '人设已保存，下一句话就会按新的说法回你。',
                          tone: BannerTone.success,
                          action: TextButton(
                            onPressed: () => setState(() => _saved = false),
                            child: const Text('好'),
                          ),
                        ),
                        const SizedBox(height: Insets.x3),
                      ],
                      _identityCard(),
                      const SizedBox(height: Insets.x4),
                      _traitsCard(),
                      const SizedBox(height: Insets.x4),
                      _voiceCard(),
                      const SizedBox(height: Insets.x4),
                      PillButton(
                        label: '保存人设',
                        icon: Icons.check_rounded,
                        expand: true,
                        onPressed: _save,
                      ),
                      const SizedBox(height: Insets.x3),
                      const Text(
                        '人设只改变语气和自称，不会放宽或收紧本机权限；'
                        '要调整它能做什么，去「智能体 → 权限」。',
                        style: TextStyle(
                            fontSize: 11.5,
                            height: 1.6,
                            color: AppColors.inkFaint),
                      ),
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

  Widget _header() {
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
                Text('人设', style: AppType.titleColor),
                SizedBox(height: 2),
                Text('决定它怎么说话、怎么称呼你',
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
              ],
            ),
          ),
          PillButton(
            label: '恢复默认',
            icon: Icons.restart_alt_rounded,
            dense: true,
            filled: false,
            color: AppColors.danger,
            onPressed: _reset,
          ),
        ],
      ),
    );
  }

  Widget _identityCard() {
    final accent = pet.accent;
    final customized = controller.isPersonaCustomized(pet);
    return _card(
      title: '身份',
      description: '名字、打招呼与口头禅',
      children: [
        Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image(image: pet.imageFor(PetMood.idle), fit: BoxFit.cover),
            ),
            const SizedBox(width: Insets.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _name.text.trim().isEmpty ? pet.name : _name.text.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700, height: 1.3),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _traits.isEmpty ? '还没有性格标签' : _traits.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
            if (customized)
              TagChip(label: '自定义', color: accent, dense: true, icon: Icons.edit_rounded)
            else
              const TagChip(label: '默认', dense: true),
          ],
        ),
        const SizedBox(height: Insets.x4),
        AppField(
          label: '名字',
          hint: '桌面、对话标题与记忆页都用这个名字；留空会恢复宠物包里的名字。',
          child: TextField(
            controller: _name,
            style: const TextStyle(fontSize: 12.5),
            onChanged: (_) => setState(() => _saved = false),
          ),
        ),
        const SizedBox(height: Insets.x3),
        AppField(
          label: '招呼语',
          hint: '打开聊天、或者长时间没见你时说的第一句话。',
          child: TextField(
            controller: _greeting,
            maxLines: 2,
            style: const TextStyle(fontSize: 12.5, height: 1.5),
            onChanged: (_) => setState(() => _saved = false),
          ),
        ),
        const SizedBox(height: Insets.x3),
        AppField(
          label: '口头禅',
          hint: '主动搭话、讨零食时会挂在嘴边的一句短话。',
          child: TextField(
            controller: _catchphrase,
            style: const TextStyle(fontSize: 12.5),
            onChanged: (_) => setState(() => _saved = false),
          ),
        ),
      ],
    );
  }

  Widget _traitsCard() {
    final accent = Theme.of(context).colorScheme.primary;
    return _card(
      title: '性格',
      description: '会驱动主动行为的倾向',
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final trait in _traits) _traitChip(trait, accent),
            if (_traits.isEmpty)
              const Text('加两三个标签，它主动搭话时会更像这个性格。',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.inkFaint)),
          ],
        ),
        const SizedBox(height: Insets.x3),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _traitInput,
                style: const TextStyle(fontSize: 12.5),
                decoration: const InputDecoration(hintText: '加一个，比如「话痨」「爱操心」'),
                onSubmitted: (_) => _addTrait(),
              ),
            ),
            const SizedBox(width: Insets.x2),
            PillButton(
              label: '添加',
              icon: Icons.add_rounded,
              dense: true,
              filled: false,
              onPressed: _addTrait,
            ),
          ],
        ),
        const SizedBox(height: Insets.x2),
        const Text(
          '贪吃 / 黏人 / 元气 这类标签会让它更爱讨食、求摸、小跑；'
          '全部删掉时保存会退回宠物包自带的性格。',
          style: TextStyle(
              fontSize: 11.5, height: 1.55, color: AppColors.inkFaint),
        ),
      ],
    );
  }

  Widget _voiceCard() {
    return _card(
      title: '说话风格',
      description: '语气与人格提示词',
      children: [
        AppField(
          label: '语气',
          hint: '一句话概括，例如「短句、口语化、偶尔用颜文字」。',
          child: TextField(
            controller: _tone,
            style: const TextStyle(fontSize: 12.5),
            onChanged: (_) => setState(() => _saved = false),
          ),
        ),
        const SizedBox(height: Insets.x3),
        AppField(
          label: '人格提示词',
          hint: '直接拼进系统提示词。写清身份、口癖与禁区；留空会用宠物包自带的一段。',
          child: TextField(
            controller: _systemPrompt,
            maxLines: 10,
            minLines: 6,
            style: const TextStyle(fontSize: 12.5, height: 1.6),
            onChanged: (_) => setState(() => _saved = false),
          ),
        ),
        const SizedBox(height: Insets.x2),
        Row(
          children: [
            TextButton(
              onPressed: () =>
                  setState(() => _showDefaultPrompt = !_showDefaultPrompt),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _showDefaultPrompt
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: AppColors.inkSoft,
                  ),
                  const SizedBox(width: 4),
                  const Text('宠物包自带的写法',
                      style: TextStyle(
                          fontSize: 11.5, color: AppColors.inkSoft)),
                ],
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () {
                setState(() {
                  _systemPrompt.text = pet.personality.systemPrompt;
                  _saved = false;
                });
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('用默认',
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
            ),
          ],
        ),
        if (_showDefaultPrompt) ...[
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
              pet.personality.systemPrompt,
              style: const TextStyle(
                  fontSize: 11.5, height: 1.65, color: AppColors.inkSoft),
            ),
          ),
        ],
      ],
    );
  }

  Widget _card({
    required String title,
    required String description,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(title, description: description),
        AppCard(
          padding: const EdgeInsets.fromLTRB(
              Insets.x4, Insets.x3, Insets.x4, Insets.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _traitChip(String trait, Color accent) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 4, 5, 4),
      decoration: BoxDecoration(
        color: tintOf(accent, 0.13),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            trait,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: inkOn(accent),
            ),
          ),
          const SizedBox(width: 2),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _removeTrait(trait),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(Icons.close_rounded,
                    size: 12, color: inkOn(accent)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm(String message) async {
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
