import '../../models/chat.dart';
import '../../models/pet.dart';
import '../../models/settings.dart';
import 'local_brain.dart';
import 'openai_backend.dart';

class ChatResult {
  const ChatResult({required this.reply, this.degraded = false, this.error});

  final PetReply reply;
  final bool degraded;
  final String? error;
}

class ChatService {
  ChatService({LocalBrain? brain, OpenAiBackend? backend})
      : _brain = brain ?? LocalBrain(),
        _backend = backend ?? OpenAiBackend();

  final LocalBrain _brain;
  final OpenAiBackend _backend;

  Future<ChatResult> send({
    required String input,
    required Pet pet,
    required List<ChatMessage> history,
    required AppSettings settings,
    int affection = 0,
    String memory = '',
    String systemPreamble = '',
  }) async {
    if (settings.chatBackend == ChatBackendKind.openai) {
      try {
        final reply = await _backend.reply(
          input: input,
          pet: pet,
          history: history,
          settings: settings,
          memory: memory,
          systemPreamble: systemPreamble,
        );
        return ChatResult(reply: reply);
      } catch (error) {
        return ChatResult(
          reply: _brain.reply(input, pet, affection: affection),
          degraded: true,
          error: error.toString(),
        );
      }
    }
    return ChatResult(reply: _brain.reply(input, pet, affection: affection));
  }

  /// 在线模式下逐段吐字；本地小脑一次性给完。
  Stream<String> sendStream({
    required String input,
    required Pet pet,
    required List<ChatMessage> history,
    required AppSettings settings,
    int affection = 0,
    String memory = '',
    String systemPreamble = '',
  }) async* {
    if (settings.chatBackend != ChatBackendKind.openai) {
      yield _brain.reply(input, pet, affection: affection).text;
      return;
    }
    yield* _backend.streamReply(
      input: input,
      pet: pet,
      history: history,
      settings: settings,
      memory: memory,
      systemPreamble: systemPreamble,
    );
  }

  PetReply local(String input, Pet pet, {int affection = 0}) =>
      _brain.reply(input, pet, affection: affection);
}
