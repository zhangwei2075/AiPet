import 'package:flutter/foundation.dart';

/// 对话后端：local = 内置小脑（离线），openai = 任意 OpenAI 兼容接口
/// （OpenAI / DeepSeek / 通义 / Ollama / LM Studio 都可以）。
enum ChatBackendKind { local, openai }

@immutable
class AppSettings {
  const AppSettings({
    this.activePetId,
    this.scale = 0.25,
    this.alwaysOnTop = true,
    this.clickThrough = true,
    this.wander = true,
    this.autoSleep = true,
    this.proactive = true,
    this.chatBackend = ChatBackendKind.local,
    this.baseUrl = 'http://127.0.0.1:11434/v1',
    this.apiKey = '',
    this.model = 'qwen2.5:3b',
    this.forgeUrl = 'http://127.0.0.1:8787',
    this.tts = false,
    this.updateManifestUrl = '',
    this.autoCheckUpdates = true,
    this.petWindowPosition,
    this.petNames = const {},
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

  final ChatBackendKind chatBackend;
  final String baseUrl;
  final String apiKey;
  final String model;

  /// PetForge 图像生成服务地址
  final String forgeUrl;

  final bool tts;

  /// 版本检查接口（JSON）；留空表示关闭自动更新。
  final String updateManifestUrl;

  /// 启动时自动检查更新（需要先填写 [updateManifestUrl]）。
  final bool autoCheckUpdates;

  /// 宠物窗口上次的位置（"x,y"）
  final String? petWindowPosition;

  /// 自定义宠物名字：petId -> 昵称（未设置时用宠物包里的名字）
  final Map<String, String> petNames;

  AppSettings copyWith({
    String? activePetId,
    double? scale,
    bool? alwaysOnTop,
    bool? clickThrough,
    bool? wander,
    bool? autoSleep,
    bool? proactive,
    ChatBackendKind? chatBackend,
    String? baseUrl,
    String? apiKey,
    String? model,
    String? forgeUrl,
    bool? tts,
    String? updateManifestUrl,
    bool? autoCheckUpdates,
    String? petWindowPosition,
    Map<String, String>? petNames,
  }) {
    return AppSettings(
      activePetId: activePetId ?? this.activePetId,
      scale: scale ?? this.scale,
      alwaysOnTop: alwaysOnTop ?? this.alwaysOnTop,
      clickThrough: clickThrough ?? this.clickThrough,
      wander: wander ?? this.wander,
      autoSleep: autoSleep ?? this.autoSleep,
      proactive: proactive ?? this.proactive,
      chatBackend: chatBackend ?? this.chatBackend,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      forgeUrl: forgeUrl ?? this.forgeUrl,
      tts: tts ?? this.tts,
      updateManifestUrl: updateManifestUrl ?? this.updateManifestUrl,
      autoCheckUpdates: autoCheckUpdates ?? this.autoCheckUpdates,
      petWindowPosition: petWindowPosition ?? this.petWindowPosition,
      petNames: petNames ?? this.petNames,
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
        'chatBackend': chatBackend.name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'forgeUrl': forgeUrl,
        'tts': tts,
        'updateManifestUrl': updateManifestUrl,
        'autoCheckUpdates': autoCheckUpdates,
        'petWindowPosition': petWindowPosition,
        'petNames': petNames,
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
    return AppSettings(
      activePetId: json['activePetId']?.toString(),
      scale: scale,
      alwaysOnTop: _asBool(json['alwaysOnTop'], true),
      clickThrough: _asBool(json['clickThrough'], true),
      wander: _asBool(json['wander'], true),
      autoSleep: _asBool(json['autoSleep'], true),
      proactive: _asBool(json['proactive'], true),
      chatBackend: json['chatBackend'] == 'openai' ? ChatBackendKind.openai : ChatBackendKind.local,
      baseUrl: _asString(json['baseUrl'], 'http://127.0.0.1:11434/v1'),
      apiKey: _asString(json['apiKey'], ''),
      model: _asString(json['model'], 'qwen2.5:3b'),
      forgeUrl: _asString(json['forgeUrl'], 'http://127.0.0.1:8787'),
      tts: _asBool(json['tts'], false),
      updateManifestUrl: _asString(json['updateManifestUrl'], ''),
      autoCheckUpdates: _asBool(json['autoCheckUpdates'], true),
      petWindowPosition: (position == null || position.isEmpty) ? null : position,
      petNames: petNames,
    );
  }
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
