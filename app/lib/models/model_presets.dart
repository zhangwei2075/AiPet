import 'package:flutter/foundation.dart';

import 'settings.dart';

/// 对话模型预设：把「协议 + 地址 + 默认模型名」打包成一个可插拔单元。
///
/// 设计来源：`docs/super-agent-refactor.md` 里 DeepSeek Harness 的
/// 「Agent = Model + Harness、一切皆插件」——模型是可替换的插件，
/// 用户只填 Key，不需要知道每种服务的 baseUrl 要不要带 /v1、
/// Anthropic 兼容端点是 /anthropic 还是 /apps/anthropic。
///
/// 端点均为 2026-11 官方公开地址，见各服务的 API 文档。
/// 地址/模型名会随服务商调整，选中预设后仍可手动改（改了就变成「自定义」）。
@immutable
class ModelPreset {
  const ModelPreset({
    required this.id,
    required this.label,
    required this.protocol,
    required this.baseUrl,
    required this.model,
    required this.tools,
    this.keyHint = '',
    this.note = '',
  });

  final String id;

  /// 设置页下拉显示的短名，如「DeepSeek（OpenAI）」。
  final String label;

  /// 与 [AppSettings.apiProtocol] 同值域：'openai' / 'anthropic'。
  final String protocol;

  final String baseUrl;
  final String model;

  /// 工具调用能力标注，直接显示在设置页。
  ///
  /// 注意：[ToolProbe]（app/lib/agent/tool_probe.dart）当前只发
  /// OpenAI 协议的 /chat/completions + tools，所以 Anthropic 协议下
  /// 「提醒我…」这类工具意图会静默降级为普通聊天。这里必须如实标注，
  /// 不能让用户以为选了 Coding Plan 就什么都能干。
  final String tools;

  /// API Key 获取位置 / Key 类型提示。
  final String keyHint;

  /// 端点配套注意事项（如百炼 Key 类型与 baseUrl 必须匹配）。
  final String note;

  bool get supportsTools => protocol == 'openai';

  /// 把预设套到现有设置上：只动对话模型三件套，其余字段（宠物、外观、
  /// PetForge、更新地址）原样保留。不覆盖 API Key —— 换模型不该把 Key 清空。
  AppSettings apply(AppSettings settings) => settings.copyWith(
        chatBackend: ChatBackendKind.openai,
        apiProtocol: protocol,
        baseUrl: baseUrl,
        model: model,
      );
}

/// 「自定义」不是真预设，只是下拉里的哨兵项：选中它不覆盖任何字段。
const String customPresetId = 'custom';

const List<ModelPreset> modelPresets = [
  ModelPreset(
    id: 'deepseek-openai',
    label: 'DeepSeek（OpenAI 协议）',
    protocol: 'openai',
    baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-v4-flash',
    tools: '支持工具调用',
    keyHint: 'Key：platform.deepseek.com → API keys',
    note: 'deepseek-chat / deepseek-reasoner 已于 2026-07-24 弃用；思考模式改用 deepseek-v4-pro。',
  ),
  ModelPreset(
    id: 'deepseek-anthropic',
    label: 'DeepSeek（Anthropic 协议）',
    protocol: 'anthropic',
    baseUrl: 'https://api.deepseek.com/anthropic',
    model: 'deepseek-v4-flash',
    tools: '工具调用暂不可用（探测仅支持 OpenAI 协议）',
    keyHint: 'Key：platform.deepseek.com → API keys',
    note: 'Anthropic 兼容端点，走 /messages；Key 与 OpenAI 协议通用。',
  ),
  ModelPreset(
    id: 'openai',
    label: 'OpenAI',
    protocol: 'openai',
    baseUrl: 'https://api.openai.com/v1',
    model: 'gpt-4o-mini',
    tools: '支持工具调用',
    keyHint: 'Key：platform.openai.com → API keys',
    note: '模型名按账号可用清单改（gpt-4o / gpt-5 系列均可）。',
  ),
  ModelPreset(
    id: 'ollama',
    label: 'Ollama（本机）',
    protocol: 'openai',
    baseUrl: 'http://127.0.0.1:11434/v1',
    model: 'qwen2.5:3b',
    tools: '工具调用弱（小模型不稳定，建议用内置规则表）',
    keyHint: '无需 Key；先 ollama serve 并 pull 模型',
    note: '完全离线，不产生费用；模型名必须是本机 ollama list 里的名字。',
  ),
  ModelPreset(
    id: 'bailian-openai',
    label: '百炼按量（OpenAI 兼容）',
    protocol: 'openai',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    model: 'qwen3.8-flash',
    tools: '支持工具调用',
    keyHint: 'Key：百炼控制台 → API Key（sk- 开头）',
    note: '按量付费通用端点；模型名按账号开通清单改。',
  ),
  ModelPreset(
    id: 'bailian-coding-anthropic',
    label: '百炼 Coding Plan（Anthropic）',
    protocol: 'anthropic',
    baseUrl: 'https://coding.dashscope.aliyuncs.com/apps/anthropic',
    model: 'qwen3.8-max',
    tools: '工具调用暂不可用（探测仅支持 OpenAI 协议）',
    keyHint: 'Key：Coding Plan 专用 Key（sk-sp- 开头）',
    note: 'Key 类型必须与端点配套：Coding Plan Key + /apps/anthropic，混用会 401/403；模型名按套餐支持列表改。',
  ),
  ModelPreset(
    id: 'glm-coding-openai',
    label: 'GLM Coding Plan（OpenAI）',
    protocol: 'openai',
    baseUrl: 'https://open.bigmodel.cn/api/coding/paas/v4',
    model: 'glm-5.2',
    tools: '支持工具调用',
    keyHint: 'Key：智谱控制台 → 编程套餐 → 新建 API Key',
    note: 'Coding Plan 专用端点；不能用普通开放平台 Key，否则不扣套餐额度。',
  ),
  ModelPreset(
    id: 'glm-coding-anthropic',
    label: 'GLM Coding Plan（Anthropic）',
    protocol: 'anthropic',
    baseUrl: 'https://open.bigmodel.cn/api/anthropic',
    model: 'glm-5.2',
    tools: '工具调用暂不可用（探测仅支持 OpenAI 协议）',
    keyHint: 'Key：智谱控制台 → 编程套餐 → 新建 API Key',
    note: 'Claude Code 同款端点，走 /messages。',
  ),
  ModelPreset(
    id: 'kimi-openai',
    label: 'Kimi（OpenAI 协议）',
    protocol: 'openai',
    baseUrl: 'https://api.moonshot.cn/v1',
    model: 'kimi-k3.1-pro',
    tools: '支持工具调用',
    keyHint: 'Key：platform.moonshot.cn → API Keys',
  ),
  ModelPreset(
    id: 'kimi-anthropic',
    label: 'Kimi（Anthropic 协议）',
    protocol: 'anthropic',
    baseUrl: 'https://api.moonshot.cn/anthropic',
    model: 'kimi-k3.1-pro',
    tools: '工具调用暂不可用（探测仅支持 OpenAI 协议）',
    keyHint: 'Key：platform.moonshot.cn → API Keys',
    note: '若报 404，把地址末尾补成 /anthropic/v1。',
  ),
];

/// 供应商 = 一个 Key + 一组模型目录。
///
/// 复刻 DeepSeek Harness 的接入体验：设置 → 模型 → 选供应商 → 粘贴 Key，
/// 模型从目录里挑。OpenCode Go 就是典型——订阅一个 Key，一个网关访问
/// DeepSeek / GLM / Kimi / Qwen 等几十个模型，不用为每个模型单独配地址和 Key。
@immutable
class ModelProvider {
  const ModelProvider({
    required this.id,
    required this.label,
    required this.keyHint,
    required this.models,
    this.note = '',
  });

  final String id;
  final String label;

  /// Key 获取位置 / 格式提示（设置页直接显示）。
  final String keyHint;

  /// 该供应商 Key 能访问的模型 ID（OpenCode 的目录，2026-11）。
  /// 只放精选常用项，目录会变，选「自定义模型」可手填任意 ID。
  final List<ModelPreset> models;

  final String note;

  /// Key 的前缀校验提示；留空表示不校验。
  String get keyPrefixHint {
    if (id == 'opencode-go' || id == 'opencode-payg') return 'oc_sk_';
    if (id == 'bailian-coding') return 'sk-sp-';
    return '';
  }
}

/// 供应商列表，OpenCode 排在前面（用户点名的接入方式）。
final List<ModelProvider> modelProviders = [
  ModelProvider(
    id: 'opencode-go',
    label: 'OpenCode Go（订阅，一个 Key 多模型）',
    keyHint: 'Key：opencode.ai/auth → 订阅 Go / Go Plus 后复制（oc_sk_ 开头）',
    note: '一个 Key 走遍 DeepSeek / GLM / Kimi / Qwen；Go 要求带稳定会话头，程序已自动处理。'
        '注意流量须像编码 Agent，普通聊天滥用可能触发风控。',
    models: [
      ModelPreset(
        id: 'oc-go-deepseek-v4.1-flash',
        label: 'DeepSeek V4.1 Flash',
        protocol: 'openai',
        baseUrl: 'https://opencode.ai/inference/go/openai/v1',
        model: 'deepseek-v4.1-flash',
        tools: '支持工具调用',
      ),
      ModelPreset(
        id: 'oc-go-deepseek-v4-pro',
        label: 'DeepSeek V4 Pro',
        protocol: 'openai',
        baseUrl: 'https://opencode.ai/inference/go/openai/v1',
        model: 'deepseek-v4-pro',
        tools: '支持工具调用',
      ),
      ModelPreset(
        id: 'oc-go-glm-5.2',
        label: 'GLM 5.2',
        protocol: 'openai',
        baseUrl: 'https://opencode.ai/inference/go/openai/v1',
        model: 'glm-5.2',
        tools: '支持工具调用',
      ),
      ModelPreset(
        id: 'oc-go-kimi-k2.7',
        label: 'Kimi K2.7 Code',
        protocol: 'openai',
        baseUrl: 'https://opencode.ai/inference/go/openai/v1',
        model: 'kimi-k2.7-code',
        tools: '支持工具调用',
      ),
      ModelPreset(
        id: 'oc-go-qwen3.7-max',
        label: 'Qwen 3.7 Max',
        protocol: 'openai',
        baseUrl: 'https://opencode.ai/inference/go/openai/v1',
        model: 'qwen3.7-max',
        tools: '支持工具调用',
      ),
      ModelPreset(
        id: 'oc-go-anthropic',
        label: 'Anthropic 协议（Claude / 兼容模型）',
        protocol: 'anthropic',
        baseUrl: 'https://opencode.ai/inference/go/anthropic/v1',
        model: 'claude-sonnet-4-6',
        tools: '工具调用暂不可用（探测仅支持 OpenAI 协议）',
      ),
    ],
  ),
  ModelProvider(
    id: 'opencode-payg',
    label: 'OpenCode 按量（一个 Key 多模型）',
    keyHint: 'Key：opencode.ai/auth → 按量付费 Key（oc_sk_ 开头）',
    note: '与 Go 同一网关、不同计费端点（/inference 无 /go）。模型目录相同。',
    models: [
      ModelPreset(
        id: 'oc-payg-deepseek-v4.1-flash',
        label: 'DeepSeek V4.1 Flash',
        protocol: 'openai',
        baseUrl: 'https://opencode.ai/inference/openai/v1',
        model: 'deepseek-v4.1-flash',
        tools: '支持工具调用',
      ),
      ModelPreset(
        id: 'oc-payg-glm-5.2',
        label: 'GLM 5.2',
        protocol: 'openai',
        baseUrl: 'https://opencode.ai/inference/openai/v1',
        model: 'glm-5.2',
        tools: '支持工具调用',
      ),
      ModelPreset(
        id: 'oc-payg-anthropic',
        label: 'Anthropic 协议',
        protocol: 'anthropic',
        baseUrl: 'https://opencode.ai/inference/anthropic/v1',
        model: 'claude-sonnet-4-6',
        tools: '工具调用暂不可用（探测仅支持 OpenAI 协议）',
      ),
    ],
  ),
  ModelProvider(
    id: 'deepseek',
    label: 'DeepSeek 官方',
    keyHint: 'Key：platform.deepseek.com → API keys',
    models: [
      modelPresets.firstWhere((p) => p.id == 'deepseek-openai'),
      modelPresets.firstWhere((p) => p.id == 'deepseek-anthropic'),
    ],
  ),
  ModelProvider(
    id: 'glm-coding',
    label: 'GLM Coding Plan',
    keyHint: 'Key：智谱控制台 → 编程套餐 → 新建 API Key',
    note: 'Coding Plan 专用端点，普通开放平台 Key 不扣套餐额度。',
    models: [
      modelPresets.firstWhere((p) => p.id == 'glm-coding-openai'),
      modelPresets.firstWhere((p) => p.id == 'glm-coding-anthropic'),
    ],
  ),
  ModelProvider(
    id: 'bailian-coding',
    label: '百炼 Coding Plan',
    keyHint: 'Key：百炼控制台 → Coding Plan（sk-sp- 开头）',
    note: 'Key 类型必须与 /apps/anthropic 配套，混用会 401/403。',
    models: [modelPresets.firstWhere((p) => p.id == 'bailian-coding-anthropic')],
  ),
  ModelProvider(
    id: 'kimi',
    label: 'Kimi 官方',
    keyHint: 'Key：platform.moonshot.cn → API Keys',
    models: [
      modelPresets.firstWhere((p) => p.id == 'kimi-openai'),
      modelPresets.firstWhere((p) => p.id == 'kimi-anthropic'),
    ],
  ),
  ModelProvider(
    id: 'openai',
    label: 'OpenAI 官方',
    keyHint: 'Key：platform.openai.com → API keys',
    models: [modelPresets.firstWhere((p) => p.id == 'openai')],
  ),
  ModelProvider(
    id: 'ollama',
    label: 'Ollama（本机离线）',
    keyHint: '无需 Key；先 ollama serve 并 pull 模型',
    models: [modelPresets.firstWhere((p) => p.id == 'ollama')],
  ),
];

/// 按当前设置反查下拉该显示哪个预设；三件套有任一不符就是「自定义」。
String findPresetId(AppSettings settings) {
  for (final provider in modelProviders) {
    for (final preset in provider.models) {
      if (preset.protocol == settings.apiProtocol &&
          preset.baseUrl == settings.baseUrl.replaceAll(RegExp(r'/+$'), '') &&
          preset.model == settings.model) {
        return preset.id;
      }
    }
  }
  for (final preset in modelPresets) {
    if (preset.protocol == settings.apiProtocol &&
        preset.baseUrl == settings.baseUrl.replaceAll(RegExp(r'/+$'), '') &&
        preset.model == settings.model) {
      return preset.id;
    }
  }
  return customPresetId;
}

ModelPreset? presetById(String id) {
  for (final provider in modelProviders) {
    for (final preset in provider.models) {
      if (preset.id == id) return preset;
    }
  }
  for (final preset in modelPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}

ModelProvider? providerById(String id) {
  for (final provider in modelProviders) {
    if (provider.id == id) return provider;
  }
  return null;
}

/// 当前设置属于哪个供应商；自定义配置返回 null。
ModelProvider? providerOf(AppSettings settings) {
  final id = findPresetId(settings);
  if (id == customPresetId) return null;
  for (final provider in modelProviders) {
    if (provider.models.any((p) => p.id == id)) return provider;
  }
  return null;
}
