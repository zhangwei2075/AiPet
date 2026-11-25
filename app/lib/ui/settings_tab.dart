import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app_version.dart';
import '../models/model_presets.dart';
import '../models/settings.dart';
import '../services/chat/openai_backend.dart';
import '../services/speech_service.dart';
import '../state/app_controller.dart';
import 'common.dart';
import 'feature_help.dart';
import 'manage_page.dart';
import 'theme.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsTab> createState() => SettingsTabState();
}

class SettingsTabState extends State<SettingsTab> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  late final TextEditingController _apiKey;
  late final TextEditingController _forgeUrl;
  late final TextEditingController _updateUrl;
  final _scroll = ScrollController();
  final _appearanceKey = GlobalKey();
  final _chatKey = GlobalKey();
  final _voiceKey = GlobalKey();
  final _forgeKey = GlobalKey();
  final _updateKey = GlobalKey();
  final _dataKey = GlobalKey();
  Timer? _debounce;
  late double _scale;
  bool _testingModel = false;
  String? _modelTestResult;

  AppController get controller => widget.controller;
  AppSettings get settings => controller.settings;

  @override
  void initState() {
    super.initState();
    _baseUrl = TextEditingController(text: settings.baseUrl);
    _model = TextEditingController(text: settings.model);
    _apiKey = TextEditingController(text: settings.apiKey);
    _forgeUrl = TextEditingController(text: settings.forgeUrl);
    _updateUrl = TextEditingController(text: settings.updateManifestUrl);
    _scale = settings.scale;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    _forgeUrl.dispose();
    _updateUrl.dispose();
    super.dispose();
  }

  void _commit(AppSettings next, {bool immediate = false}) {
    if (immediate) {
      controller.updateSettings(next);
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 550),
        () => controller.updateSettings(next));
  }

  /// 设置页很长，顶部给一排分区入口：点一下滚到对应分组，不用一路滑到底。
  void _jump(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: Motion.slow,
      curve: Motion.curve,
      alignment: 0.02,
    );
  }

  /// 一键套用预设：协议 / 地址 / 模型名一起写入，输入框同步刷新。
  /// Key 不动（换服务商 Key 本来就不通用，但要让用户自己决定何时清）。
  void _applyPreset(String id) {
    final preset = presetById(id);
    if (preset == null) return; // 「自定义」哨兵：不改任何字段
    final next = preset.apply(settings);
    _debounce?.cancel(); // 丢掉尚未落盘的输入框改动，避免覆盖预设
    _baseUrl.text = next.baseUrl;
    _model.text = next.model;
    setState(() {
      _modelTestResult = null;
    });
    _commit(next, immediate: true);
  }

  /// 协议切换后，测试连接必须走新协议 —— snapshot 要带上 apiProtocol，
  /// 否则切到 Anthropic 后仍拿 openai 的 /chat/completions 去测，结果假的。
  Future<void> _testModelConnection() async {
    final pet = controller.active;
    if (pet == null) {
      setState(() => _modelTestResult = '还没有选中的宠物，先在画廊里选一只');
      return;
    }
    // 取消尚未落盘的输入框防抖，否则测试中途旧值会被写回去。
    _debounce?.cancel();
    final snapshot = settings.copyWith(
      baseUrl: _baseUrl.text.trim(),
      model: _model.text.trim(),
      apiKey: _apiKey.text.trim(),
      apiProtocol: settings.apiProtocol, // 关键：协议必须跟着走
      chatBackend: ChatBackendKind.openai,
    );
    setState(() {
      _testingModel = true;
      _modelTestResult = null;
    });
    await controller.updateSettings(snapshot);
    try {
      final reply = await OpenAiBackend().reply(
        input: '请只回复两个字：正常',
        pet: pet,
        history: const [],
        settings: snapshot,
      );
      setState(() => _modelTestResult = '连接成功：${reply.text}');
    } catch (error) {
      setState(() => _modelTestResult = '连接失败：$error');
    } finally {
      setState(() => _testingModel = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppPageHeader(
          title: '设置',
          subtitle: '外观、对话、语音与更新',
          actions: [
            PillButton(
              label: '智能体',
              icon: Icons.psychology_alt_outlined,
              filled: false,
              onPressed: () => ManagePage.open(context, controller),
            ),
          ],
        ),
        _sectionNav(),
        const SizedBox(height: Insets.x2),
        Expanded(
          child: Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: Insets.x4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _appearance(accent),
                  _chat(accent),
                  _voice(),
                  _forge(),
                  _update(),
                  _data(),
                  const SizedBox(height: Insets.x5),
                  Center(
                    child: Text(
                      '摸摸宠 MomoPet v${controller.currentVersion.isEmpty ? kAppVersion : controller.currentVersion} · Flutter',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.inkFaint),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionNav() {
    const items = <(String, IconData)>[
      ('外观', Icons.palette_outlined),
      ('对话', Icons.forum_outlined),
      ('语音', Icons.graphic_eq_rounded),
      ('形象', Icons.face_retouching_natural_outlined),
      ('更新', Icons.system_update_alt_rounded),
      ('数据', Icons.storage_rounded),
    ];
    final keys = [
      _appearanceKey,
      _chatKey,
      _voiceKey,
      _forgeKey,
      _updateKey,
      _dataKey
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: Insets.x2),
              child: _NavChip(
                icon: items[i].$2,
                label: items[i].$1,
                onTap: () => _jump(keys[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _appearance(Color accent) {
    return _section(
      key: _appearanceKey,
      title: '外观与行为',
      description: '桌面上怎么显示、怎么互动',
      children: [
        SettingRow(
          title: '宠物大小',
          subtitle: '${(_scale * 100).round()}%',
          help: '拖动调整桌面上宠物的显示尺寸，范围 15%–150%，改完立即生效并保存。',
          child: SizedBox(
            width: 180,
            child: Slider(
              value: _scale,
              min: 0.15,
              max: 1.5,
              divisions: 27,
              onChanged: (value) => setState(() => _scale = value),
              onChangeEnd: (value) =>
                  _commit(settings.copyWith(scale: value), immediate: true),
            ),
          ),
        ),
        SettingRow(
          title: '始终置顶',
          help: '宠物窗口始终浮在其他程序窗口之上；关掉后会被普通窗口盖住，但不会消失。',
          divider: true,
          child: Switch(
            value: settings.alwaysOnTop,
            onChanged: (value) =>
                _commit(settings.copyWith(alwaysOnTop: value), immediate: true),
          ),
        ),
        SettingRow(
          title: '鼠标穿透',
          help: '开启后鼠标点击会穿过宠物落到下面的窗口，宠物不再拦截点击与拖动；托盘菜单里也能随时切换。',
          divider: true,
          child: Switch(
            value: settings.clickThrough,
            onChanged: (value) => _commit(
                settings.copyWith(clickThrough: value),
                immediate: true),
          ),
        ),
        SettingRow(
          title: '桌面散步',
          help: '宠物会按自身性格在屏幕上自主走动、切换动作；关掉后停在原地，只保留点击互动。',
          divider: true,
          child: Switch(
            value: settings.wander,
            onChanged: (value) =>
                _commit(settings.copyWith(wander: value), immediate: true),
          ),
        ),
        SettingRow(
          title: '自动睡觉',
          help: '长时间没人互动时自动切到睡觉姿态，被点击或搭话后醒来；不影响提醒与自主任务。',
          divider: true,
          child: Switch(
            value: settings.autoSleep,
            onChanged: (value) =>
                _commit(settings.copyWith(autoSleep: value), immediate: true),
          ),
        ),
        SettingRow(
          title: '主动互动',
          help: '允许宠物按心情、时段与投机草稿主动冒泡搭话；关掉后只在你找它时回应，提醒仍会照常触发。',
          divider: true,
          child: Switch(
            value: settings.proactive,
            onChanged: (value) =>
                _commit(settings.copyWith(proactive: value), immediate: true),
          ),
        ),
        SettingRow(
          title: '环境感知',
          help:
              '轮询剪贴板模式（网址 / 英文 / 数字串）与前台窗口类别，用于主动提议；开启「自主执行」后还会把这些信号转成待办目标。原文不落盘。',
          divider: true,
          child: Switch(
            value: settings.perceptionEnabled,
            onChanged: (value) => _commit(
                settings.copyWith(perceptionEnabled: value),
                immediate: true),
          ),
        ),
        SettingRow(
          title: '完整本机权限',
          help:
              '一次授予 12 项本机能力（终端命令、进程、文件读写删、网络、窗口、键鼠、截屏、剪贴板、远程 MCP）。关掉后所有工具调用都会被权限层拦截，细粒度开关在「智能体 → 权限」里。',
          divider: true,
          child: Switch(
            value: controller.fullAccess,
            onChanged: (value) => controller.setFullAccess(value),
          ),
        ),
        SettingRow(
          title: '自主执行',
          help:
              '开启目标队列与多步规划循环：可自己拆解步骤、调用工具、复盘，空闲 30 分钟还会发起只读巡检；关掉后只执行你当场下达的单条指令。目标重启后续跑。',
          divider: controller.isMobile,
          child: Switch(
            value: settings.autonomyEnabled,
            onChanged: (value) => _commit(
                settings.copyWith(autonomyEnabled: value),
                immediate: true),
          ),
        ),
        if (controller.isMobile)
          SettingRow(
            title: '桌面悬浮窗',
            subtitle: Platform.isAndroid
                ? '需要「显示在其他应用上层」权限；关闭 App 后仍会显示'
                : 'iOS 系统限制，无法浮在其它 App 上方',
            help: '安卓上申请「显示在其他应用上层」权限，把宠物浮在别的应用上方；首次开启会跳转系统授权页。iOS 因系统限制不可用。',
            child: Switch(
              value: controller.overlayActive,
              onChanged: Platform.isAndroid
                  ? (_) => controller.toggleMobileOverlay()
                  : null,
            ),
          ),
      ],
    );
  }

  Widget _chat(Color accent) {
    final online = settings.chatBackend == ChatBackendKind.openai;
    return _section(
      key: _chatKey,
      title: '对话',
      description: '宠物用什么大脑回你',
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Insets.x1),
          child: FeatureHelp(
            label: '对话后端',
            description:
                '本地小脑：纯离线规则回复，不联网、不消耗模型额度。在线模型：把聊天与工具意图交给 OpenAI / Anthropic 兼容接口，多步自主规划也只在这档可用。',
            child: Row(
              children: [
                AppSegmented<ChatBackendKind>(
                  values: const [ChatBackendKind.local, ChatBackendKind.openai],
                  value: settings.chatBackend,
                  labelOf: (value) =>
                      value == ChatBackendKind.local ? '本地小脑' : '在线模型',
                  iconOf: (value) => value == ChatBackendKind.local
                      ? Icons.offline_bolt_rounded
                      : Icons.cloud_rounded,
                  onChanged: (value) => _commit(
                      settings.copyWith(chatBackend: value),
                      immediate: true),
                ),
                const SizedBox(width: Insets.x3),
                Expanded(
                  child: Text(
                    online ? '可执行工具与自主规划' : '离线可用，不耗额度',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.inkFaint),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (online) ...[
          const SizedBox(height: Insets.x3),
          _presetRow(),
          SettingRow(
            title: '接口协议',
            subtitle: settings.apiProtocol == 'anthropic'
                ? 'Anthropic 兼容（/messages）'
                : 'OpenAI 兼容（/chat/completions）',
            help:
                '选接口的消息格式：/chat/completions 或 /messages。注意：多步自主规划目前只在 OpenAI 兼容协议下生成，Anthropic 会退化为离线单步只读检查。',
            divider: true,
            child: _dropdown<String>(
              value: settings.apiProtocol,
              items: const {'openai': 'OpenAI 兼容', 'anthropic': 'Anthropic 兼容'},
              onChanged: (value) => _commit(
                  settings.copyWith(apiProtocol: value),
                  immediate: true),
              width: 170,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Insets.x3),
            child: Row(
              children: [
                PillButton(
                  label: _testingModel ? '测试中…' : '测试连接',
                  dense: true,
                  filled: false,
                  icon: Icons.bolt_rounded,
                  enabled: !_testingModel,
                  onPressed: _testModelConnection,
                ),
                const SizedBox(width: Insets.x3),
                if (_modelTestResult != null)
                  Expanded(
                    child: Text(
                      _modelTestResult!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: _modelTestResult!.startsWith('连接成功')
                            ? AppColors.success
                            : AppColors.danger,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          AppField(
            label: 'API 地址',
            child: TextField(
              controller: _baseUrl,
              style: const TextStyle(fontSize: 12.5),
              onChanged: (value) =>
                  _commit(settings.copyWith(baseUrl: value.trim())),
            ),
          ),
          const SizedBox(height: Insets.x3),
          AppField(
            label: '模型名',
            child: TextField(
              controller: _model,
              style: const TextStyle(fontSize: 12.5),
              onChanged: (value) =>
                  _commit(settings.copyWith(model: value.trim())),
            ),
          ),
          const SizedBox(height: Insets.x3),
          AppField(
            label: 'API Key',
            hint: '本地模型可留空',
            child: TextField(
              controller: _apiKey,
              obscureText: true,
              style: const TextStyle(fontSize: 12.5),
              onChanged: (value) =>
                  _commit(settings.copyWith(apiKey: value.trim())),
            ),
          ),
        ],
      ],
    );
  }

  Widget _voice() {
    return _section(
      key: _voiceKey,
      title: '语音',
      description: '让它把回复念出来',
      children: [
        SettingRow(
          title: '朗读回复',
          help: '用系统语音把宠物的回复念出来（Windows SAPI / 移动端 TTS），声线可在下方选择；关掉后只显示文字气泡。',
          divider: settings.tts,
          child: Switch(
            value: settings.tts,
            onChanged: (value) =>
                _commit(settings.copyWith(tts: value), immediate: true),
          ),
        ),
        if (settings.tts)
          SettingRow(
            title: '声线',
            help:
                '切换朗读时的语气预设（默认 / 温柔 / 活泼 / 沉稳）。Windows SAPI 不支持直接调音色，这里通过语速与音量组合模拟。',
            child: _dropdown<String>(
              value: settings.voice,
              items: SpeechService.voiceLabels,
              onChanged: (value) =>
                  _commit(settings.copyWith(voice: value), immediate: true),
              width: 120,
            ),
          ),
      ],
    );
  }

  Widget _forge() {
    return _section(
      key: _forgeKey,
      title: '形象工坊',
      description: 'PetForge 本地抠图服务',
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Insets.x3),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: controller.forgeOnline
                      ? AppColors.success
                      : AppColors.warning,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  controller.forgeOnline ? '已连接' : '未连接（仍可用本地徽章模式）',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
              PillButton(
                label: '测试连接',
                dense: true,
                filled: false,
                onPressed: () async {
                  await controller.updateSettings(
                      settings.copyWith(forgeUrl: _forgeUrl.text.trim()));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(controller.forgeOnline
                            ? '形象工坊在线，抠图质量最佳'
                            : '连不上，请先启动 Python 服务')),
                  );
                },
              ),
            ],
          ),
        ),
        AppField(
          label: '服务地址',
          child: TextField(
            controller: _forgeUrl,
            style: const TextStyle(fontSize: 12.5),
            onChanged: (value) =>
                _commit(settings.copyWith(forgeUrl: value.trim())),
          ),
        ),
      ],
    );
  }

  Widget _update() {
    return _section(
      key: _updateKey,
      title: '更新',
      description: '版本检查与安装',
      children: [
        Row(
          children: [
            Text(
              '当前版本 v${controller.currentVersion.isEmpty ? kAppVersion : controller.currentVersion}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            PillButton(
              label: controller.checkingUpdate ? '检查中…' : '检查更新',
              dense: true,
              filled: false,
              enabled: !controller.checkingUpdate,
              onPressed: controller.checkForUpdates,
            ),
          ],
        ),
        const SizedBox(height: Insets.x3),
        AppField(
          label: '版本检查地址',
          hint: '留空关闭自动更新检查',
          child: TextField(
            controller: _updateUrl,
            style: const TextStyle(fontSize: 12.5),
            onChanged: (value) =>
                _commit(settings.copyWith(updateManifestUrl: value.trim())),
          ),
        ),
        SettingRow(
          title: '启动时检查更新',
          help: '每次启动后请求上方填写的版本清单（JSON），发现新版本才提示下载；地址留空时本开关不生效。',
          child: Switch(
            value: settings.autoCheckUpdates,
            onChanged: (value) => _commit(
                settings.copyWith(autoCheckUpdates: value),
                immediate: true),
          ),
        ),
        if (controller.updateStatus != null)
          Padding(
            padding: const EdgeInsets.only(top: Insets.x2),
            child: Text(controller.updateStatus!,
                style:
                    const TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
          ),
        if (controller.updateError != null)
          Padding(
            padding: const EdgeInsets.only(top: Insets.x2),
            child: Text(controller.updateError!,
                style:
                    const TextStyle(fontSize: 11.5, color: AppColors.danger)),
          ),
        if (controller.availableUpdate != null) ...[
          if (controller.availableUpdate!.notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Insets.x3),
              child: Text(
                controller.availableUpdate!.notes,
                style: const TextStyle(
                    fontSize: 12, height: 1.55, color: AppColors.inkSoft),
              ),
            ),
          if (controller.downloadingUpdate) ...[
            const SizedBox(height: Insets.x3),
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.pill),
              child: LinearProgressIndicator(
                  value: controller.updateProgress > 0
                      ? controller.updateProgress
                      : null),
            ),
          ],
          const SizedBox(height: Insets.x3),
          Align(
            alignment: Alignment.centerLeft,
            child: PillButton(
              label: controller.downloadingUpdate
                  ? '下载中…'
                  : (controller.availableUpdate!.isInstaller
                      ? '下载并安装'
                      : '打开下载页'),
              dense: true,
              enabled: !controller.downloadingUpdate,
              onPressed: controller.downloadAndInstallUpdate,
            ),
          ),
        ],
      ],
    );
  }

  Widget _data() {
    return _section(
      key: _dataKey,
      title: '数据',
      description: '清空只影响当前这一项，不可撤销',
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('清空对话记录',
                      style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600)),
                  SizedBox(height: 2),
                  Text(
                    '不影响情景记忆、技能、目标队列与审计日志',
                    style: TextStyle(
                        fontSize: 11.5, color: AppColors.inkSoft, height: 1.45),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Insets.x4),
            PillButton(
              label: '清空',
              dense: true,
              filled: false,
              color: AppColors.danger,
              onPressed: () {
                controller.clearChat();
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('对话已清空')));
              },
            ),
          ],
        ),
      ],
    );
  }

  /// 供应商 + 模型两级选择，复刻 DeepSeek Harness 的接入路径：
  /// 选供应商 → 粘贴 Key → 从目录挑模型。协议/地址由供应商自动决定。
  Widget _presetRow() {
    final currentProvider = providerOf(settings);
    final providerId = currentProvider?.id ?? customPresetId;
    final modelId = findPresetId(settings);
    // 供应商自定义时，模型下拉仍可用，但展示全部模型的平铺列表。
    final catalog = currentProvider?.models ?? modelPresets;
    final modelExists = catalog.any((p) => p.id == modelId);

    return Column(
      children: [
        SettingRow(
          title: '供应商',
          help: '一键套用该服务商的协议、接口地址与默认模型；切换会覆盖下方的地址与模型名，API Key 保持不动。选「自定义」可手填。',
          divider: true,
          child: _dropdown<String>(
            value: providerId,
            items: {
              customPresetId: '自定义',
              for (final item in modelProviders)
                item.id: item.label
                    .replaceAll('（订阅，一个 Key 多模型）', '')
                    .replaceAll('（一个 Key 多模型）', ''),
            },
            onChanged: (value) {
              if (value == customPresetId) return;
              final provider = providerById(value);
              if (provider != null && provider.models.isNotEmpty) {
                _applyPreset(provider.models.first.id);
              }
            },
            width: 190,
          ),
        ),
        SettingRow(
          title: '模型',
          help: '从当前供应商的模型目录里挑一个；切换会同时写入模型名与对应地址。列表外的模型可在下方「模型名」里手填。',
          child: _dropdown<String>(
            value: modelExists ? modelId : catalog.first.id,
            items: {for (final item in catalog) item.id: item.label},
            onChanged: (value) => _applyPreset(value),
            width: 190,
          ),
        ),
      ],
    );
  }

  /// 统一下拉样式：无下划线、无边框，右侧一个 chevron，落在浅底里当控件用。
  Widget _dropdown<T>({
    required T value,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
    double width = 160,
  }) {
    return Container(
      width: width,
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          borderRadius: BorderRadius.circular(Radii.control),
          icon: const Icon(Icons.expand_more_rounded,
              size: 16, color: AppColors.inkSoft),
          style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.ink,
              fontWeight: FontWeight.w500),
          items: [
            for (final entry in items.entries)
              DropdownMenuItem<T>(
                  value: entry.key,
                  child: Text(entry.value, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ),
    );
  }

  /// 一个分组 = 小标题 + 白卡。卡片里的行用发丝线分隔，删掉 Material 的默认空隙。
  Widget _section({
    required GlobalKey key,
    required String title,
    required List<Widget> children,
    String? description,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: Insets.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(title, description: description),
          AppCard(
            padding: const EdgeInsets.fromLTRB(
                Insets.x4, Insets.x1, Insets.x4, Insets.x3),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children),
          ),
        ],
      ),
    );
  }
}

class _NavChip extends StatefulWidget {
  const _NavChip(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_NavChip> createState() => _NavChipState();
}

class _NavChipState extends State<_NavChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _hover ? AppColors.surfaceAlt : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.pill),
            border:
                Border.all(color: _hover ? AppColors.line : Colors.transparent),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 14, color: AppColors.inkSoft),
              const SizedBox(width: 5),
              Text(
                widget.label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
