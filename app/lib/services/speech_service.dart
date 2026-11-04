import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 把宠物的话读出来。
///
/// 只用系统 TTS（Windows SAPI / Android TextToSpeech），不联网、不占体积。
/// 任何一步失败都静默降级——语音是锦上添花，不能影响聊天。
class SpeechService {
  SpeechService({FlutterTts? engine}) : _engine = engine;

  FlutterTts? _engine;
  bool _ready = false;
  bool _speaking = false;

  bool get isSpeaking => _speaking;

  bool get supported => Platform.isWindows || Platform.isAndroid || Platform.isMacOS || Platform.isIOS;

  Future<FlutterTts> _ensure() async {
    final engine = _engine ??= FlutterTts();
    if (_ready) return engine;
    await engine.setLanguage('zh-CN');
    await engine.setSpeechRate(0.52);
    await engine.setPitch(1.05);
    await engine.setVolume(1.0);
    // 不要开启 awaitSpeakCompletion(true)：flutter_tts 4.2.5 的 Windows 实现会把
    // Dart result 存进成员 speakResult（永不置空），而 stop() 与朗读完成回调
    // （媒体线程）都会对它 Success(reply) → 同一 MethodResult 被二次 reply，
    // response handle 已被引擎释放 → UAF 崩溃（flutter_windows.dll 0xc0000005）。
    // 保持默认 false：result 在 speak() 内立即单次 reply，speakResult 路径不可达；
    // 朗读状态仍由 start/completion/cancel handler 维护。
    // await engine.awaitSpeakCompletion(true);  // 禁用：见上，双 reply UAF
    engine.setStartHandler(() => _speaking = true);
    engine.setCompletionHandler(() => _speaking = false);
    engine.setCancelHandler(() => _speaking = false);
    engine.setErrorHandler((_) => _speaking = false);
    _ready = true;
    return engine;
  }

  Future<void> speak(String text) async {
    if (!supported) return;
    final clean = cleanForSpeech(text);
    if (clean.isEmpty) return;
    try {
      final engine = await _ensure();
      await engine.stop();
      await engine.speak(clean);
    } catch (error) {
      debugPrint('tts speak failed: $error');
    }
  }

  Future<void> stop() async {
    if (_engine == null) return;
    try {
      await _engine!.stop();
    } catch (error) {
      debugPrint('tts stop failed: $error');
    }
    _speaking = false;
  }

  /// 去掉情绪标签、颜文字和 markdown，控制长度——直接念「[happy]」会很怪。
  static String cleanForSpeech(String raw) {
    var text = raw
        .replaceAll(RegExp(r'^\s*[\[【]\s*(happy|love|angry|sleepy|idle|talk)\s*[\]】]\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'[*_`#>~]'), '')
        .replaceAll(RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}]', unicode: true), '')
        .trim();
    if (text.length > 90) text = '${text.substring(0, 90)}…';
    return text;
  }
}
