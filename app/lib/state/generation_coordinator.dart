import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/memory_store.dart';
import '../data/pet_repository.dart';
import '../data/settings_store.dart';
import '../mobile/overlay_pet.dart';
import '../models/chat.dart';
import '../models/pet.dart';
import '../models/settings.dart';
import '../services/badge_pet_factory.dart';
import '../services/petforge_client.dart';
import 'controller_types.dart';

/// 照片生成宠物：选图、调用 PetForge / 徽章兜底、收养。
mixin GenerationCoordinator on ChangeNotifier {
  AppSettings get settings;
  set settings(AppSettings value);
  List<Pet> get pets;
  set pets(List<Pet> value);
  Pet? get active;
  set active(Pet? value);
  bool get overlayActive;
  bool get generating;
  set generating(bool value);
  double get generationProgress;
  set generationProgress(double value);
  String get generationStage;
  set generationStage(String value);
  String? get generationError;
  set generationError(String? value);
  String? get generationNotice;
  set generationNotice(String? value);
  bool get forgeOnline;
  set forgeOnline(bool value);
  GeneratedPet? get preview;
  set preview(GeneratedPet? value);
  Uint8List? get sourceBytes;
  set sourceBytes(Uint8List? value);
  String? get sourceName;
  set sourceName(String? value);
  List<ChatMessage> get messages;
  set messages(List<ChatMessage> value);
  int get affection;
  set affection(int value);
  PetRepository get repo;
  SettingsStore get store;
  MemoryStore get memory;
  PetForgeClient get forge;
  BadgePetFactory get badge;
  String displayName(Pet pet);
  Future<void> closePanel();
  void showBubble(String text, {PetMood mood = PetMood.talk, int duration = 6});
  void emitBurst(PetBurst kind);

  void loadSource(Uint8List bytes, String name) {
    sourceBytes = bytes;
    sourceName = name;
    preview = null;
    generationError = null;
    generationNotice = null;
    notifyListeners();
  }

  void resetGeneration() {
    sourceBytes = null;
    sourceName = null;
    preview = null;
    generationError = null;
    generationNotice = null;
    generationProgress = 0;
    generating = false;
    notifyListeners();
  }

  Future<void> checkForge() async {
    final health = await forge.health(settings.forgeUrl);
    forgeOnline = health.online;
    notifyListeners();
  }

  Future<void> generate({String style = 'sticker', String? name}) async {
    final bytes = sourceBytes;
    if (bytes == null || generating) return;
    generating = true;
    generationError = null;
    generationNotice = null;
    preview = null;
    generationStage = '正在连接形象工坊…';
    generationProgress = 0.12;
    notifyListeners();

    try {
      final health = await forge.health(settings.forgeUrl);
      forgeOnline = health.online;
      generationStage = '抠图 & 生成动作帧';
      generationProgress = 0.42;
      notifyListeners();

      if (health.online) {
        final result = await forge.generate(
          bytes: bytes,
          baseUrl: settings.forgeUrl,
          filename: sourceName ?? 'upload.png',
          style: style,
          name: name,
          animate: true,
        );
        generationStage = '设计性格 & 调色板';
        generationProgress = 0.9;
        preview = result;
        final cutout = result.pack['metrics']?['cutout']?.toString();
        final animations = (result.pack['animations'] as Map?)?.keys.toList() ?? const [];
        if (cutout == 'oval') {
          generationNotice = '背景比较复杂，先用了圆形徽章兜底。安装 rembg 后效果会更好。';
        } else if (cutout != 'rembg') {
          generationNotice = '服务端没装 rembg（当前用 $cutout 抠图），毛发边缘可能不干净；装上 rembg 效果最好。';
        } else if (animations.isNotEmpty) {
          generationNotice = '已生成 ${animations.join(' / ')} 逐帧动画。';
        }
      } else {
        generationStage = '本地徽章模式';
        generationProgress = 0.6;
        preview = await badge.build(bytes, name: name);
        generationNotice = '没有连上 PetForge 服务，已用本地徽章模式生成。启动服务可获得贴纸抠图效果。';
      }
      generationProgress = 1;
    } catch (error) {
      generationError = '生成失败：$error';
      try {
        preview = await badge.build(bytes, name: name);
        generationNotice = '远程生成失败，已退回本地徽章模式。';
      } catch (_) {
        preview = null;
      }
    } finally {
      generating = false;
      notifyListeners();
    }
  }

  Future<Pet?> adoptPreview({String? name}) async {
    final result = preview;
    if (result == null) return null;
    final pet = await repo.saveGenerated(result, name: name);
    pets = await repo.loadAll();
    settings = settings.copyWith(activePetId: pet.id);
    active = pet;
    if (overlayActive) unawaited(MobileOverlay.sync(pet));
    messages = [];
    await store.saveSettings(settings);
    resetGeneration();
    await store.saveSettings(settings);
    notifyListeners();
    emitBurst(PetBurst.hearts);
    await closePanel();
    showBubble('我是${displayName(pet)}！以后就住在你的桌面啦。', mood: PetMood.love, duration: 6);
    return pet;
  }

}
