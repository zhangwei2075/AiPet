import '../models/pet.dart';

/// 主 App 与悬浮窗之间传递宠物所需的纯数据，方便单测覆盖。
Map<String, dynamic> overlayPayload(Pet pet, {int? updatedAt}) => {
      'version': 1,
      'directory': pet.directory,
      'assetRoot': pet.assetRoot,
      'pack': pet.toPack(),
      if (updatedAt != null) 'updatedAt': updatedAt,
    };

/// 从共享数据恢复宠物；数据不合法时返回 null，让调用方回退到内置形象。
Pet? petFromOverlayPayload(Map<String, dynamic> data) {
  final rawPack = data['pack'];
  if (rawPack is! Map) return null;
  try {
    return Pet.fromPack(
      Map<String, dynamic>.from(rawPack),
      id: 'overlay',
      directory: data['directory']?.toString(),
      builtin: (data['assetRoot']?.toString().isNotEmpty ?? false),
      assetRoot: data['assetRoot']?.toString() ?? '',
    );
  } catch (_) {
    return null;
  }
}
