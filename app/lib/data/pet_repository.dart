import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/pet.dart';
import '../models/settings.dart';

/// 管理内置宠物（assets）与照片生成的宠物（应用数据目录）。
class PetRepository {
  // 顺序决定默认宠物：新装用户第一眼看到的就是小黄豆（黄狗白面）
  static const builtinIds = ['doudou', 'momo', 'mint', 'taro'];

  List<Pet> _builtins = const [];
  Directory? _root;

  Future<Directory> _petsRoot() async {
    if (_root != null) return _root!;
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}${Platform.pathSeparator}pets');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _root = dir;
  }

  /// 目录名就是宠物 id。`Directory.uri` 末尾带 `/`，直接取 `pathSegments.last`
  /// 会得到空字符串，导致所有自定义宠物 id 都变成 ''，重启后无法按 id 选中。
  static String idForDirectory(Directory dir) {
    return dir.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty);
  }

  Future<List<Pet>> loadAll() async {
    await _loadBuiltins();
    final custom = <Pet>[];
    final root = await _petsRoot();
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      final packFile = File('${entity.path}${Platform.pathSeparator}petpack.json');
      if (!await packFile.exists()) continue;
      try {
        final pack = jsonDecode(await packFile.readAsString()) as Map<String, dynamic>;
        custom.add(Pet.fromPack(pack, id: idForDirectory(entity), directory: entity.path));
      } catch (error) {
        // 坏掉的宠物包不应该阻止 App 启动
        // ignore: avoid_print
        print('skip broken pet ${entity.path}: $error');
      }
    }
    custom.sort((a, b) => b.id.compareTo(a.id));
    return [..._builtins, ...custom];
  }

  Future<List<Pet>> _loadBuiltins() async {
    if (_builtins.isNotEmpty) return _builtins;
    final pets = <Pet>[];
    for (final id in builtinIds) {
      try {
        final raw = await rootBundle.loadString('assets/pets/$id/petpack.json');
        final pack = jsonDecode(raw) as Map<String, dynamic>;
        pets.add(
          Pet.fromPack(
            pack,
            id: id,
            builtin: true,
            assetRoot: 'assets/pets/$id',
          ),
        );
      } catch (_) {
        // asset 缺失时忽略
      }
    }
    _builtins = pets;
    return pets;
  }

  /// 把生成结果落盘，返回可直接使用的宠物对象。
  Future<Pet> saveGenerated(GeneratedPet generated, {String? name}) async {
    final root = await _petsRoot();
    final id = 'p${DateTime.now().millisecondsSinceEpoch}';
    final dir = Directory('${root.path}${Platform.pathSeparator}$id');
    await dir.create(recursive: true);
    for (final entry in generated.images.entries) {
      await File('${dir.path}${Platform.pathSeparator}${entry.key}.png').writeAsBytes(entry.value);
    }
    final pack = Map<String, dynamic>.from(generated.pack);
    if (name != null && name.trim().isNotEmpty) {
      pack['name'] = name.trim();
      final personality = Map<String, dynamic>.from(pack['personality'] as Map? ?? {});
      personality['greeting'] = '嗨，我是${name.trim()}！';
      pack['personality'] = personality;
    }
    await File('${dir.path}${Platform.pathSeparator}petpack.json')
        .writeAsString(jsonEncode(pack), encoding: utf8);
    return Pet.fromPack(pack, id: id, directory: dir.path);
  }

  Future<void> delete(Pet pet) async {
    if (pet.builtin || pet.directory == null) return;
    final dir = Directory(pet.directory!);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
