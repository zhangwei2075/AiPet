import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/settings.dart';
import '../state/app_controller.dart';
import 'common.dart';
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
  Timer? _debounce;
  late double _scale;

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
    _debounce = Timer(const Duration(milliseconds: 550), () => controller.updateSettings(next));
  }

  void _applyPreset(String url, String model) {
    _baseUrl.text = url;
    _model.text = model;
    _commit(settings.copyWith(baseUrl: url, model: model, chatBackend: ChatBackendKind.openai), immediate: true);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('设置', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        const Text('外观、对话模型和形象工坊', style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('外观与行为'),
                _card(
                  Column(
                    children: [
                      SettingRow(
                        title: '宠物大小',
                        subtitle: '当前 ${(_scale * 100).round()}%',
                        child: SizedBox(
                          width: 190,
                          child: Slider(
                            value: _scale,
                            min: 0.15,
                            max: 1.5,
                            divisions: 27,
                            onChanged: (value) => setState(() => _scale = value),
                            onChangeEnd: (value) => _commit(settings.copyWith(scale: value), immediate: true),
                          ),
                        ),
                      ),
                      const Divider(),
                      SettingRow(
                        title: '始终置顶',
                        subtitle: '宠物一直浮在其他窗口上方',
                        child: Switch(
                          value: settings.alwaysOnTop,
                          onChanged: (value) => _commit(settings.copyWith(alwaysOnTop: value), immediate: true),
                        ),
                      ),
                      SettingRow(
                        title: '鼠标穿透',
                        subtitle: '宠物以外的透明区域不挡住鼠标点击',
                        child: Switch(
                          value: settings.clickThrough,
                          onChanged: (value) => _commit(settings.copyWith(clickThrough: value), immediate: true),
                        ),
                      ),
                      SettingRow(
                        title: '桌面散步',
                        subtitle: '空闲时在桌面上走一小段',
                        child: Switch(
                          value: settings.wander,
                          onChanged: (value) => _commit(settings.copyWith(wander: value), immediate: true),
                        ),
                      ),
                      SettingRow(
                        title: '自动睡觉',
                        subtitle: '90 秒没有互动就打个盹',
                        child: Switch(
                          value: settings.autoSleep,
                          onChanged: (value) => _commit(settings.copyWith(autoSleep: value), immediate: true),
                        ),
                      ),
                      SettingRow(
                        title: '主动互动',
                        subtitle: '空闲时按性格搭话、讨食、求摸或小跑',
                        child: Switch(
                          value: settings.proactive,
                          onChanged: (value) => _commit(settings.copyWith(proactive: value), immediate: true),
                        ),
                      ),
                      SettingRow(
                        title: '朗读回复',
                        subtitle: '用系统语音把宠物的话念出来',
                        child: Switch(
                          value: settings.tts,
                          onChanged: (value) => _commit(settings.copyWith(tts: value), immediate: true),
                        ),
                      ),
                      if (controller.isMobile)
                        SettingRow(
                          title: '桌面悬浮窗',
                          subtitle: Platform.isAndroid
                              ? '需要「显示在其他应用上层」权限；关闭 App 后仍会显示'
                              : 'iOS 系统限制，无法浮在其它 App 上方',
                          child: Switch(
                            value: controller.overlayActive,
                            onChanged: Platform.isAndroid ? (_) => controller.toggleMobileOverlay() : null,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const SectionLabel('对话'),
                _card(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: SegmentedButton<ChatBackendKind>(
                              segments: const [
                                ButtonSegment(value: ChatBackendKind.local, label: Text('本地小脑', style: TextStyle(fontSize: 12)), icon: Icon(Icons.offline_bolt_rounded, size: 15)),
                                ButtonSegment(value: ChatBackendKind.openai, label: Text('在线模型', style: TextStyle(fontSize: 12)), icon: Icon(Icons.cloud_rounded, size: 15)),
                              ],
                              selected: {settings.chatBackend},
                              showSelectedIcon: false,
                              style: ButtonStyle(
                                textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12)),
                                visualDensity: VisualDensity.compact,
                                backgroundColor: WidgetStateProperty.resolveWith(
                                  (states) => states.contains(WidgetState.selected) ? accent.withValues(alpha: 0.14) : Colors.transparent,
                                ),
                              ),
                              onSelectionChanged: (value) => _commit(
                                settings.copyWith(chatBackend: value.first),
                                immediate: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '本地小脑完全离线；在线模型支持任意 OpenAI 兼容接口（OpenAI / DeepSeek / Ollama / LM Studio）。',
                        style: TextStyle(fontSize: 10.5, color: AppColors.inkSoft, height: 1.5),
                      ),
                      if (settings.chatBackend == ChatBackendKind.openai) ...[
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 6,
                          children: [
                            PillButton(label: 'Ollama', dense: true, filled: false, onPressed: () => _applyPreset('http://127.0.0.1:11434/v1', 'qwen2.5:3b')),
                            PillButton(label: 'DeepSeek', dense: true, filled: false, onPressed: () => _applyPreset('https://api.deepseek.com/v1', 'deepseek-chat')),
                            PillButton(label: 'OpenAI', dense: true, filled: false, onPressed: () => _applyPreset('https://api.openai.com/v1', 'gpt-4o-mini')),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _field('API 地址', _baseUrl, (value) => _commit(settings.copyWith(baseUrl: value.trim()))),
                        const SizedBox(height: 10),
                        _field('模型名', _model, (value) => _commit(settings.copyWith(model: value.trim()))),
                        const SizedBox(height: 10),
                        _field(
                          'API Key（本地模型可留空）',
                          _apiKey,
                          (value) => _commit(settings.copyWith(apiKey: value.trim())),
                          obscure: true,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const SectionLabel('形象工坊 PetForge'),
                _card(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: controller.forgeOnline ? const Color(0xFF57B87A) : const Color(0xFFE0A83C),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            controller.forgeOnline ? '已连接' : '未连接（仍可用本地徽章模式）',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          PillButton(
                            label: '测试连接',
                            dense: true,
                            filled: false,
                            onPressed: () async {
                              await controller.updateSettings(settings.copyWith(forgeUrl: _forgeUrl.text.trim()));
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(controller.forgeOnline ? '形象工坊在线，抠图质量最佳' : '连不上，请先启动 Python 服务'),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _field('服务地址', _forgeUrl, (value) => _commit(settings.copyWith(forgeUrl: value.trim()))),
                      const SizedBox(height: 8),
                      const Text(
                        '启动方式：进入 services/petforge，执行\npython -m pip install -r requirements.txt\npython -m petforge',
                        style: TextStyle(fontSize: 10, height: 1.6, color: AppColors.inkSoft, fontFamily: 'Consolas'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const SectionLabel('更新'),
                _card(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '当前版本 v${controller.currentVersion.isEmpty ? '0.1.0' : controller.currentVersion}',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
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
                      const SizedBox(height: 10),
                      _field(
                        '版本检查地址（JSON，留空关闭）',
                        _updateUrl,
                        (value) => _commit(settings.copyWith(updateManifestUrl: value.trim())),
                      ),
                      SettingRow(
                        title: '启动时检查更新',
                        subtitle: '需要先填写检查地址',
                        child: Switch(
                          value: settings.autoCheckUpdates,
                          onChanged: (value) => _commit(
                            settings.copyWith(autoCheckUpdates: value),
                            immediate: true,
                          ),
                        ),
                      ),
                      if (controller.updateStatus != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            controller.updateStatus!,
                            style: const TextStyle(fontSize: 11, color: AppColors.inkSoft),
                          ),
                        ),
                      if (controller.updateError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            controller.updateError!,
                            style: TextStyle(fontSize: 11, color: Colors.red.shade600),
                          ),
                        ),
                      if (controller.availableUpdate != null) ...[
                        if (controller.availableUpdate!.notes.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              controller.availableUpdate!.notes,
                              style: const TextStyle(fontSize: 11, height: 1.5),
                            ),
                          ),
                        if (controller.downloadingUpdate) ...[
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: controller.updateProgress > 0 ? controller.updateProgress : null,
                          ),
                        ],
                        const SizedBox(height: 10),
                        PillButton(
                          label: controller.downloadingUpdate
                              ? '下载中…'
                              : (controller.availableUpdate!.isInstaller ? '下载并安装' : '打开下载页'),
                          dense: true,
                          enabled: !controller.downloadingUpdate,
                          onPressed: controller.downloadAndInstallUpdate,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const SectionLabel('数据'),
                _card(
                  SettingRow(
                    title: '清空对话记录',
                    subtitle: '只删除聊天内容，宠物形象保留',
                    child: PillButton(
                      label: '清空',
                      dense: true,
                      filled: false,
                      onPressed: () {
                        controller.clearChat();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('对话已清空')));
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    '摸摸宠 MomoPet v${controller.currentVersion.isEmpty ? '0.1.0' : controller.currentVersion} · Flutter · 参考 VPet / Shimeji / Live2D 的设计',
                    style: const TextStyle(fontSize: 9.5, color: AppColors.inkSoft),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _card(Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line.withValues(alpha: 0.9)),
      ),
      child: child,
    );
  }

  Widget _field(String label, TextEditingController controller, ValueChanged<String> onChanged, {bool obscure = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.inkSoft)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: const TextStyle(fontSize: 12),
          onChanged: onChanged,
          decoration: const InputDecoration(isDense: true),
        ),
      ],
    );
  }
}
