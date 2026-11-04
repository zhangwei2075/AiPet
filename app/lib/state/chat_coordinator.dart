import 'dart:async';

import 'package:flutter/foundation.dart';

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
  void emitBurst(PetBurst kind);
  void scheduleIdleReturn();
  void wake();

  Timer? _historyDebounce;

  Future<void> sendMessage(String raw) async {
    final text = raw.trim();
    final pet = active;
    if (text.isEmpty || pet == null || typing) return;
    wake();

    final userMessage = ChatMessage(role: ChatRole.user, text: text, at: DateTime.now());
    final history = List<ChatMessage>.of(messages);
    messages = [...messages, userMessage];
    typing = true;
    bubble = null;
    mood = PetMood.talk;
    chatError = null;
    notifyListeners();

    final note = memory.promptFor(pet.id);
    final online = settings.chatBackend == ChatBackendKind.openai;

    if (!online) {
      _finishReply(chatService.local(text, pet, affection: affection), pet, text);
      return;
    }

    // 在线模型：逐字吐出来，让等待没那么难熬；失败就整段降级到本地小脑。
    final buffer = StringBuffer();
    try {
      await for (final delta in chatService.sendStream(
        input: text,
        pet: pet,
        history: history,
        settings: settings,
        affection: affection,
        memory: note,
      )) {
        buffer.write(delta);
        streamingText = OpenAiBackend.parseReply(buffer.toString()).text;
        notifyListeners();
      }
      streamingText = null;
      _finishReply(OpenAiBackend.parseReply(buffer.toString().trim()), pet, text);
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
