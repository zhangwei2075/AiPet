import 'package:flutter/foundation.dart';

import 'pet.dart';

/// 对话后端：local = 内置小脑（离线），openai = 任意 OpenAI 兼容接口
/// （OpenAI / DeepSeek / 通义 / Ollama / LM Studio 都可以）。
enum ChatBackendKind { local, openai }

@immutable
class AppSettings {

  /// 在线聊天通道是否可用（openai 兼容后端 + 非空地址）。
  bool get onlineAvailable =>
      chatBackend == ChatBackendKind.openai && baseUrl.trim().isNotEmpty;

  /// 是否走 OpenCode 网关（Go 订阅 / 按量付费）。
  ///
  /// OpenCode Go 要求每个请求带 `x-opencode-session` 稳定会话头，
  /// 用于路由一致性和 prompt 缓存复用；缺失会影响缓存甚至被风控。
  bool get isOpencodeGateway => baseUrl.toLowerCase().contains('opencode.ai/inference');

  /// 派生稳定会话 ID：同一 Key + 地址永远得到同一个值。
  ///
  /// 不新增持久化字段的好处：跨重启稳定（缓存复用）、换 Key 自动换会话、
  /// 不会把原始 Key 发到网关（只发 FNV-1a 哈希）。
  /// 桌面宠物是单会话场景，一个 Key 一个 session 足够；多会话场景才需要
  /// 把 sessionId 提升为独立字段。
  String get opencodeSessionId {
    var hash = 0x811c9dc5; // FNV-1a 32
    final source = '$baseUrl|$apiKey';
    for (final unit in source.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return 'ses_${hash.toRadixString(16).padLeft(8, '0')}';
  }

  const AppSettings({
    this.activePetId,
    this.scale = 0.25,
    this.alwaysOnTop = true,
    this.clickThrough = true,
    this.wander = true,
    this.autoSleep = true,
    this.proactive = true,
    this.perceptionEnabled = true,
    this.autonomyEnabled = true,
    this.chatBackend = ChatBackendKind.local,
    this.apiProtocol = 'openai',
    this.baseUrl = 'http://127.0.0.1:11434/v1',
    this.apiKey = '',
    this.model = 'qwen2.5:3b',
    this.forgeUrl = 'http://127.0.0.1:8787',
    this.tts = false,
    this.voice = 'default',
    this.updateManifestUrl = '',
    this.autoCheckUpdates = true,
    this.petWindowPosition,
    this.petNames = const {},
    this.petPersonas = const {},
  });

  final String? activePetId;
  final double scale;
  final bool alwaysOnTop;
  final bool clickThrough;

  /// 空闲时在桌面上小幅走动
  final bool wander;
  final bool autoSleep;

  /// 空闲时按宠物性格主动搭话 / 讨食 / 求摸 / 小跑
  final bool proactive;

  /// 环境感知（剪贴板 / 前台应用）总开关。M5 起默认开启（全权限方向），
  /// 关闭后所有感知 Trigger 立即停止轮询；配额与静默由 QuietHours 配置。
  final bool perceptionEnabled;

  /// 自主执行总开关：允许智能体自己发起目标、多步调用工具、在后台持续推进。
  /// 关掉后只响应主人当轮指令，不再自驱。
  final bool autonomyEnabled;

  final ChatBackendKind chatBackend;

  /// 在线接口协议：'openai'（/chat/completions）或 'anthropic'（/messages，
  /// 百炼 / GLM / Kimi 的 Coding Plan 都兼容此协议）。
  final String apiProtocol;

  final String baseUrl;
  final String apiKey;
  final String model;

  /// PetForge 图像生成服务地址
  final String forgeUrl;

  final bool tts;

  /// 朗读声线（default/gentle/lively/calm），由 SpeechService 映射成语速+音调。
  final String voice;

  /// 版本检查接口（JSON）；留空表示关闭自动更新。
  final String updateManifestUrl;

  /// 启动时自动检查更新（需要先填写 [updateManifestUrl]）。
  final bool autoCheckUpdates;

  /// 宠物窗口上次的位置（"x,y"）
  final String? petWindowPosition;

  /// 自定义宠物名字：petId -> 昵称（未设置时用宠物包里的名字）
  final Map<String, String> petNames;

  /// 自定义人设：petId -> 人设（未设置时用宠物包自带的人格）
  final Map<String, PetPersonality> petPersonas;

  AppSettings copyWith({
    String? activePetId,
    double? scale,
    bool? alwaysOnTop,
    bool? clickThrough,
    bool? wander,
    bool? autoSleep,
    bool? proactive,
    bool? perceptionEnabled,
    bool? autonomyEnabled,
    ChatBackendKind? chatBackend,
    String? apiProtocol,
    String? baseUrl,
    String? apiKey,
    String? model,
    String? forgeUrl,
    bool? tts,
    String? voice,
    String? updateManifestUrl,
    bool? autoCheckUpdates,
    String? petWindowPosition,
    Map<String, String>? petNames,
    Map<String, PetPersonality>? petPersonas,
  }) {
    return AppSettings(
      activePetId: activePetId ?? this.activePetId,
      scale: scale ?? this.scale,
      alwaysOnTop: alwaysOnTop ?? this.alwaysOnTop,
      clickThrough: clickThrough ?? this.clickThrough,
      wander: wander ?? this.wander,
      autoSleep: autoSleep ?? this.autoSleep,
      proactive: proactive ?? this.proactive,
      perceptionEnabled: perceptionEnabled ?? this.perceptionEnabled,
      autonomyEnabled: autonomyEnabled ?? this.autonomyEnabled,
      chatBackend: chatBackend ?? this.chatBackend,
      apiProtocol: apiProtocol ?? this.apiProtocol,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      forgeUrl: forgeUrl ?? this.forgeUrl,
      tts: tts ?? this.tts,
      voice: voice ?? this.voice,
      updateManifestUrl: updateManifestUrl ?? this.updateManifestUrl,
      autoCheckUpdates: autoCheckUpdates ?? this.autoCheckUpdates,
      petWindowPosition: petWindowPosition ?? this.petWindowPosition,
      petNames: petNames ?? this.petNames,
      petPersonas: petPersonas ?? this.petPersonas,
    );
  }

  Map<String, dynamic> toJson() => {
        'activePetId': activePetId,
        'scale': scale,
        'alwaysOnTop': alwaysOnTop,
        'clickThrough': clickThrough,
        'wander': wander,
        'autoSleep': autoSleep,
        'proactive': proactive,
        'perceptionEnabled': perceptionEnabled,
        'autonomyEnabled': autonomyEnabled,
        'chatBackend': chatBackend.name,
        'apiProtocol': apiProtocol,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'forgeUrl': forgeUrl,
        'tts': tts,
        'voice': voice,
        'updateManifestUrl': updateManifestUrl,
        'autoCheckUpdates': autoCheckUpdates,
        'petWindowPosition': petWindowPosition,
        'petNames': petNames,
        'petPersonas': {
          for (final entry in petPersonas.entries)
            entry.key: entry.value.toJson(),
        },
        'scaleV': 2,
      };

  /// 解析时对每个字段做容错：配置文件被手改坏 / 旧版本字段缺失时，
  /// 只丢掉出问题的字段，不让整个设置回退成默认值。
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    // scaleV=2：scale 语义改为「相对设计尺寸的倍数」，默认 0.25（当前的 1/4）。
    // 旧版本（scaleV 缺失）保存的值一律回到默认，避免旧刻度被误读。
    final scale = json['scaleV'] == 2 ? _asDouble(json['scale'], 0.25).clamp(0.1, 3.0) : 0.25;
    final rawNames = (json['petNames'] as Map?) ?? const {};
    final petNames = <String, String>{};
    rawNames.forEach((key, value) {
      final name = value?.toString().trim() ?? '';
      if (name.isNotEmpty) petNames[key.toString()] = name;
    });
    final position = json['petWindowPosition']?.toString();
    final rawPersonas = (json['petPersonas'] as Map?) ?? const {};
    final petPersonas = <String, PetPersonality>{};
    rawPersonas.forEach((key, value) {
      if (value is Map) {
        petPersonas[key.toString()] =
            PetPersonality.fromJson(value.cast<String, dynamic>());
      }
    });
    return AppSettings(
      activePetId: json['activePetId']?.toString(),
      scale: scale,
      alwaysOnTop: _asBool(json['alwaysOnTop'], true),
      clickThrough: _asBool(json['clickThrough'], true),
      wander: _asBool(json['wander'], true),
      autoSleep: _asBool(json['autoSleep'], true),
      proactive: _asBool(json['proactive'], true),
      perceptionEnabled: _asBool(json['perceptionEnabled'], true),
      autonomyEnabled: _asBool(json['autonomyEnabled'], true),
      chatBackend: json['chatBackend'] == 'openai' ? ChatBackendKind.openai : ChatBackendKind.local,
      apiProtocol: json['apiProtocol']?.toString() == 'anthropic' ? 'anthropic' : 'openai',
      baseUrl: _asString(json['baseUrl'], 'http://127.0.0.1:11434/v1'),
      apiKey: _asString(json['apiKey'], ''),
      model: _asString(json['model'], 'qwen2.5:3b'),
      forgeUrl: _asString(json['forgeUrl'], 'http://127.0.0.1:8787'),
      tts: _asBool(json['tts'], false),
      voice: const {'default', 'gentle', 'lively', 'calm'}.contains(json['voice']?.toString())
          ? json['voice'] as String
          : 'default',
      updateManifestUrl: _asString(json['updateManifestUrl'], ''),
      autoCheckUpdates: _asBool(json['autoCheckUpdates'], true),
      petWindowPosition: (position == null || position.isEmpty) ? null : position,
      petNames: petNames,
      petPersonas: petPersonas,
    );
  }
}

/// 人设查询：设置里自定义的优先，没有就用宠物包自带的。
///
/// 全站在需要「它是什么性格 / 怎么说话」的地方都走这里，保证改了人设后
/// 聊天、打招呼、主动搭话、卡片标签用的是同一份数据。
extension PetPersonaLookup on AppSettings {
  PetPersonality personaOf(Pet pet) => petPersonas[pet.id] ?? pet.personality;

  bool hasCustomPersona(String petId) => petPersonas.containsKey(petId);
}

double _asDouble(Object? value, double fallback) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim()) ?? fallback;
  return fallback;
}

bool _asBool(Object? value, bool fallback) {
  if (value is bool) return value;
  if (value is String) {
    final text = value.trim().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;
  }
  if (value is num) return value != 0;
  return fallback;
}

String _asString(Object? value, String fallback) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

/// 一次生成请求的结果（PetForge 返回的宠物包 + 解码后的图片）
class GeneratedPet {
  const GeneratedPet({required this.pack, required this.images, this.elapsedMs = 0});

  final Map<String, dynamic> pack;
  final Map<String, Uint8List> images;
  final int elapsedMs;
}
