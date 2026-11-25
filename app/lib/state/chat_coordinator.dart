import 'dart:async';

import 'package:flutter/foundation.dart';

import '../agent/activity.dart';
import '../agent/brain.dart';
import '../agent/chat_agent.dart';
import '../agent/experience.dart';
import '../agent/memory/memory_service.dart';
import '../agent/pet_tool.dart';
import '../agent/skill.dart';
import '../agent/system_prompt.dart';
import '../agent/tool_runtime.dart';
import '../core/app_mode.dart';
import '../data/memory_store.dart';
import '../data/settings_store.dart';
import '../models/chat.dart';
import '../models/pet.dart';
import '../models/settings.dart';
import '../services/chat/chat_service.dart';
import '../services/chat/openai_backend.dart';
import '../services/speech_service.dart';
import 'controller_types.dart';

/// 聊天收发、流式输出、朗读与历史持久化。
mixin ChatCoordinator on ChangeNotifier {
  AppSettings get settings;
  Pet? get active;
  List<ChatMessage> get messages;
  set messages(List<ChatMessage> value);
  bool get typing;
  set typing(bool value);
  String? get streamingText;
  set streamingText(String? value);
  String? get bubble;
  set bubble(String? value);
  PetMood get mood;
  set mood(PetMood value);
  String? get chatError;
  set chatError(String? value);
  WindowMode get mode;
  int get affection;
  Map<String, List<ChatMessage>> get history;
  MemoryStore get memory;
  SettingsStore get store;
  ChatService get chatService;
  SpeechService get speech;
  PetBrain? get brain;
  ChatAgent? get chatAgent;
  ToolRuntime get toolRuntime;
  ExperienceBank get experienceBank;
  AgentActivity get agentActivity;
  bool get autonomyEnabled;
  MemoryService? get memoryService;
  SkillRegistry get skillRegistry;
  void emitBurst(PetBurst kind);
  void scheduleIdleReturn();
  void wake();

  Timer? _historyDebounce;

  Future<void> sendMessage(String raw) async {
    final text = raw.trim();
    final pet = active;
    if (text.isEmpty || pet == null || typing) return;
    wake();

    // 1) Brain 的确定性规则：提醒 / 宠物动作 / 剪贴板；离线时还承担
    //    本机操作路由与自主目标派发（见 brain.dart）。
    final brainHandle = brain;
    if (brainHandle != null) {
      typing = true;
      notifyListeners();
      final brainReply = await brainHandle.handleUserText(text);
      if (brainReply != null) {
        bubble = null;
        chatError = null;
        _finishReply(PetReply(brainReply.text, brainReply.mood), pet, text);
        return;
      }
      typing = false; // 不是确定性规则，交还给下面的聊天主通道
    }
    // 情景记忆：异步抽取这句话里值得长期记住的事实，不阻塞聊天。
    unawaited(memoryService?.recordFromChat(petId: pet.id, userText: text, settings: settings));

    final userMessage = ChatMessage(role: ChatRole.user, text: text, at: DateTime.now());
    final history = List<ChatMessage>.of(messages);
    messages = [...messages, userMessage];
    typing = true;
    bubble = null;
    mood = PetMood.talk;
    chatError = null;
    notifyListeners();

    // 情景记忆组装：计数记忆 + 近几天 digest + top-K 情景（M2）。
    final remembered = memoryService?.assemble(
          petId: pet.id,
          query: text,
          countMemory: memory.promptFor(pet.id),
        ) ??
        memory.promptFor(pet.id);
    final skillPrompt = skillRegistry.buildPromptFragmentFor(text);
    final note = skillPrompt.isEmpty ? remembered : '$remembered\n\n$skillPrompt';
    final online = settings.chatBackend == ChatBackendKind.openai;
    final tools = brainHandle?.registry.all ?? const <PetTool>[];
    final permissions = toolRuntime.permissions;

    // 高权限系统提示词：明确「可以操作整台电脑」，人格描述降级为语气参考。
    // 同类目标的既往经验也在这里回灌，形成学习沉淀的使用侧。
    String lessons = '';
    try {
      lessons = await experienceBank.recallForPrompt(text);
    } catch (_) {
      // 经验读不出来不影响聊天。
    }
    final preamble = buildAgentPreamble(
      permissions: permissions,
      tools: tools,
      petName: pet.name,
    );
    final systemPrompt = buildAgentSystemPrompt(
      personalityPrompt: pet.personality.systemPrompt,
      tools: tools,
      permissions: permissions,
      memory: remembered,
      skills: skillPrompt,
      experience: lessons,
      activity: [
        agentActivity.statusLine ?? '',
        '后台自主执行：${autonomyEnabled ? '开启' : '关闭'}',
      ].where((line) => line.isNotEmpty).join('\n'),
      petName: pet.name,
    );

    // 2) 在线 + 全权限：聊天级 ReAct，模型点名工具 → ToolRuntime 真实执行
    //    → 结果回灌 → 直到给出结论。这才是「通过对话操作电脑」。
    final agent = chatAgent;
    if (online && agent != null && !permissions.paused && tools.isNotEmpty) {
      try {
        final result = await agent.respond(
          input: text,
          history: history,
          settings: settings,
          systemPrompt: systemPrompt,
        );
        _finishReply(OpenAiBackend.parseReply(result.text), pet, text);
        return;
      } catch (error) {
        chatError = '这轮没能走工具通道：${_short(error.toString(), 80)}（已切回普通聊天）';
        notifyListeners();
      }
    }

    // 3) 本地小脑：没有在线模型，只做陪伴式回答；本机操作已在第 1 步由
    //    Brain 的离线规则 / 自主循环接住。
    if (!online) {
      _finishReply(chatService.local(text, pet, affection: affection), pet, text);
      return;
    }

    // 4) 在线模型不支持 tools / 工具通道失败：退回流式聊天，但提示词仍是
    //    高权限版，并且如实告诉主人这一轮没有实际执行。
    final buffer = StringBuffer();
    try {
      await for (final delta in chatService.sendStream(
        input: text,
        pet: pet,
        history: history,
        settings: settings,
        affection: affection,
        memory: note,
        systemPreamble: preamble,
      )) {
        buffer.write(delta);
        streamingText = OpenAiBackend.parseReply(buffer.toString()).text;
        notifyListeners();
      }
      streamingText = null;
      _finishReply(
        OpenAiBackend.parseReply(buffer.toString().trim()),
        pet,
        text,
        degradedError: chatError,
      );
    } catch (error) {
      streamingText = null;
      _finishReply(
        chatService.local(text, pet, affection: affection),
        pet,
        text,
        degradedError: error.toString(),
      );
    }
  }

  String _short(String text, int limit) =>
      text.length <= limit ? text : '${text.substring(0, limit)}…';

  /// 收尾：落一条宠物消息、切情绪、朗读、冒气泡、记一笔记忆。
  void _finishReply(PetReply reply, Pet pet, String userText, {String? degradedError}) {
    typing = false;
    messages = [
      ...messages,
      ChatMessage(role: ChatRole.pet, text: reply.text, at: DateTime.now(), mood: reply.mood),
    ];
    mood = reply.mood;
    chatError = degradedError;
    if (settings.tts) unawaited(speech.speak(reply.text));
    if (mode != WindowMode.chat) {
      bubble = reply.text;
      emitBurst(_burstFor(reply.mood));
      scheduleIdleReturn();
    }
    notifyListeners();
    unawaited(memory.chat(pet.id, userText));
    _scheduleHistorySave();
  }

  PetBurst _burstFor(PetMood mood) => switch (mood) {
        PetMood.love => PetBurst.hearts,
        PetMood.happy => PetBurst.note,
        PetMood.angry => PetBurst.anger,
        PetMood.sleepy => PetBurst.sleep,
        _ => PetBurst.stars,
      };

  void _scheduleHistorySave() {
    _historyDebounce?.cancel();
    _historyDebounce = Timer(const Duration(milliseconds: 800), () => unawaited(saveHistory()));
  }

  Future<void> saveHistory() async {
    final pet = active;
    if (pet == null) return;
    history[pet.id] = messages.length > 60 ? messages.sublist(messages.length - 60) : messages;
    await store.saveHistory(history);
  }

  void clearChat() {
    messages = [];
    if (active != null) history.remove(active!.id);
    unawaited(store.saveHistory(history));
    notifyListeners();
  }

  void disposeChat() {
    _historyDebounce?.cancel();
  }
}
