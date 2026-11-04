import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:path_provider/path_provider.dart';

import '../models/pet.dart';
import 'overlay_pet_data.dart';

/// Android 系统级悬浮窗（真正浮在其它 App 之上）。
///
/// iOS 不允许跨 App 悬浮窗，这里会直接返回 false，
/// 详见 docs/platforms.md。
class MobileOverlay {
  /// 悬浮窗是独立 Flutter Engine，拿不到主 App 的内存状态，也拿不到
  /// path_provider / shared_preferences 这些插件（overlay 引擎不会注册它们）。
  /// 所以主 App 把当前宠物写成一份 JSON，悬浮窗只靠 dart:io 读文件；
  /// 同时用 shareData 再推一份，防止两个引擎的临时目录不一致。
  static const String descriptorName = 'overlay_pet.json';

  static Future<File> descriptorFile() async {
    final dir = await getTemporaryDirectory();
    return File('${dir.path}${Platform.pathSeparator}$descriptorName');
  }

  /// 把当前宠物同步给已经打开的悬浮窗（切宠物 / 改名 / 删除后调用）。
  static Future<void> sync(Pet pet) async {
    if (!Platform.isAndroid) return;
    final payload = overlayPayload(pet, updatedAt: DateTime.now().millisecondsSinceEpoch);
    try {
      final file = await descriptorFile();
      await file.writeAsString(jsonEncode(payload), flush: true);
    } catch (error) {
      debugPrint('overlay descriptor write failed: $error');
    }
    try {
      // 悬浮窗已打开时直接推一份，不依赖两个引擎的临时目录是否一致。
      await FlutterOverlayWindow.shareData({...payload, 'type': 'overlay_pet'});
    } catch (error) {
      debugPrint('overlay sync push failed: $error');
    }
  }

  static Future<bool> show({Pet? pet}) async {
    if (!Platform.isAndroid) return false;
    var granted = await FlutterOverlayWindow.isPermissionGranted();
    if (!granted) granted = await FlutterOverlayWindow.requestPermission() ?? false;
    if (!granted) return false;

    if (pet != null) await sync(pet);

    await FlutterOverlayWindow.showOverlay(
      height: 260,
      width: 220,
      alignment: OverlayAlignment.bottomRight,
      flag: OverlayFlag.defaultFlag,
      enableDrag: true,
      overlayTitle: '摸摸宠正在桌面上陪你',
      overlayContent: '点一下互动，长按可以收回',
    );

    if (pet != null) unawaited(_broadcast(pet));
    return true;
  }

  /// 悬浮窗引擎启动需要时间，早发的消息会被丢掉，所以重试几次。
  static Future<void> _broadcast(Pet pet) async {
    final payload = {
      ...overlayPayload(pet, updatedAt: DateTime.now().millisecondsSinceEpoch),
      'type': 'overlay_pet',
    };
    for (var attempt = 0; attempt < 10; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      try {
        await FlutterOverlayWindow.shareData(payload);
      } catch (_) {
        // 悬浮窗还没准备好，下一次重试
      }
    }
  }

  static Future<void> hide() async {
    if (!Platform.isAndroid) return;
    await FlutterOverlayWindow.closeOverlay();
  }

  static Future<bool> get isShowing async {
    if (!Platform.isAndroid) return false;
    return FlutterOverlayWindow.isActive();
  }
}

/// 悬浮窗 UI：显示主 App 当前宠物，点击换表情 + 冒泡，长按关闭。
class OverlayPet extends StatefulWidget {
  const OverlayPet({super.key});

  @override
  State<OverlayPet> createState() => _OverlayPetState();
}

class _OverlayPetState extends State<OverlayPet> with SingleTickerProviderStateMixin {
  late final AnimationController _bob =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
  final math.Random _random = math.Random();
  late Pet _pet = _fallbackPet();
  PetMood _mood = PetMood.idle;
  String? _bubble;
  Timer? _reset;
  Timer? _watch;
  StreamSubscription<dynamic>? _subscription;
  int _descriptorStamp = 0;
  bool _loading = false;

  /// 读不到主 App 的数据时退回内置 momo，保证悬浮窗永远有东西可显示。
  static Pet _fallbackPet() => Pet.fromPack(
        {
          'name': '橘子团子',
          'frames': {
            'idle': 'idle.png',
            'happy': 'happy.png',
            'love': 'love.png',
            'angry': 'angry.png',
            'sleepy': 'sleepy.png',
            'blink': 'blink.png',
          },
        },
        id: 'momo',
        builtin: true,
        assetRoot: 'assets/pets/momo',
      );

  @override
  void initState() {
    super.initState();
    _subscription = FlutterOverlayWindow.overlayListener.listen(_onSharedData);
    unawaited(_loadDescriptor());
    // 主 App 切换宠物后只改文件，这里轮询 mtime，避免依赖插件通道。
    _watch = Timer.periodic(const Duration(seconds: 2), (_) => unawaited(_loadDescriptor()));
  }

  @override
  void dispose() {
    _reset?.cancel();
    _watch?.cancel();
    _subscription?.cancel();
    _bob.dispose();
    super.dispose();
  }

  void _onSharedData(dynamic data) {
    if (data is! Map) return;
    final map = Map<String, dynamic>.from(data);
    if (map['type'] == 'overlay_pet') {
      _apply(map);
    } else if (map['path'] is String) {
      unawaited(_loadFromPath(map['path'] as String));
    }
  }

  Future<void> _loadFromPath(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _apply(data);
    } catch (error) {
      debugPrint('overlay read $path failed: $error');
    }
  }

  Future<void> _loadDescriptor() async {
    if (_loading) return;
    _loading = true;
    try {
      final file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}${MobileOverlay.descriptorName}',
      );
      if (!await file.exists()) return;
      final stamp = (await file.stat()).modified.millisecondsSinceEpoch;
      if (stamp == _descriptorStamp) return;
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _apply(data);
      _descriptorStamp = stamp;
    } catch (error) {
      debugPrint('overlay descriptor read failed: $error');
    } finally {
      _loading = false;
    }
  }

  void _apply(Map<String, dynamic> data) {
    final pet = petFromOverlayPayload(data);
    if (pet == null || !mounted) return;
    setState(() {
      _pet = pet;
      _mood = PetMood.idle;
    });
  }

  void _react() {
    final candidates = [PetMood.happy, PetMood.love, PetMood.angry]
        .where((mood) => _pet.frames.containsKey(mood))
        .toList();
    setState(() {
      _mood = candidates.isEmpty ? PetMood.idle : candidates[_random.nextInt(candidates.length)];
      _bubble = ['咕？', '嘿嘿', '在呢', '摸摸～', '陪我玩'][_random.nextInt(5)];
    });
    _reset?.cancel();
    _reset = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      setState(() {
        _mood = PetMood.idle;
        _bubble = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _react,
          onLongPress: () async {
            await FlutterOverlayWindow.closeOverlay();
          },
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _bob,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(0, -4 * _bob.value),
                    child: Transform.scale(
                      scaleX: 1 + 0.02 * _bob.value,
                      scaleY: 1 - 0.02 * _bob.value,
                      child: child,
                    ),
                  ),
                  child: Image(
                    image: _pet.imageFor(_mood),
                    width: 190,
                    height: 190,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
                if (_bubble != null)
                  Positioned(
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8)],
                      ),
                      child: Text(_bubble!, style: const TextStyle(fontSize: 11, color: Color(0xFF3F2E28))),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
