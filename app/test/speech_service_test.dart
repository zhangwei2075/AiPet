import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:momopet/services/speech_service.dart';

/// 记录调用序列的假引擎；未显式实现的成员转发到 noSuchMethod。
class FakeTts implements FlutterTts {
  final List<String> calls = [];

  @override
  Future<dynamic> setLanguage(String language) async {
    calls.add('setLanguage:$language');
  }

  @override
  Future<dynamic> setSpeechRate(double rate) async {
    calls.add('setSpeechRate');
  }

  @override
  Future<dynamic> setPitch(double pitch) async {
    calls.add('setPitch');
  }

  @override
  Future<dynamic> setVolume(double volume) async {
    calls.add('setVolume');
  }

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async {
    calls.add('awaitSpeakCompletion:$awaitCompletion');
  }

  @override
  Future<dynamic> speak(String text, {bool focus = false}) async {
    calls.add('speak:$text');
  }

  @override
  Future<dynamic> stop() async {
    calls.add('stop');
  }

  @override
  void setStartHandler(VoidCallback callback) {
    calls.add('setStartHandler');
  }

  @override
  void setCompletionHandler(VoidCallback callback) {
    calls.add('setCompletionHandler');
  }

  @override
  void setCancelHandler(VoidCallback callback) {
    calls.add('setCancelHandler');
  }

  @override
  void setErrorHandler(ErrorHandler handler) {
    calls.add('setErrorHandler');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('SpeechService 行为（flutter_tts 双 reply UAF 回归）', () {
    test('初始化绝不开启 awaitSpeakCompletion，speak 先 stop 再 speak', () async {
      final fake = FakeTts();
      final speech = SpeechService(engine: fake);

      await speech.speak('你好');

      expect(
        fake.calls.where((c) => c.startsWith('awaitSpeakCompletion')),
        isEmpty,
        reason: '开启 awaitSpeakCompletion 会让插件保存 speakResult 并被 '
            'stop()/完成回调二次 reply，触发 UAF 闪退',
      );
      final stopIdx = fake.calls.indexOf('stop');
      final speakIdx = fake.calls.indexWhere((c) => c.startsWith('speak:'));
      expect(stopIdx, greaterThanOrEqualTo(0), reason: 'speak 前应 stop 打断上一条');
      expect(speakIdx, greaterThan(stopIdx), reason: 'stop 之后才 speak');
    });

    test('空文本不触发朗读也不初始化引擎', () async {
      final fake = FakeTts();
      final speech = SpeechService(engine: fake);

      await speech.speak('   [happy] 🐶');

      expect(fake.calls, isEmpty, reason: '清理后为空应直接返回');
    });

    test('朗读内容经过 cleanForSpeech 清理', () async {
      final fake = FakeTts();
      final speech = SpeechService(engine: fake);

      await speech.speak('[happy] 汪！**开心**');

      expect(fake.calls.where((c) => c.startsWith('speak:')), ['speak:汪！开心']);
    });
  });
}
