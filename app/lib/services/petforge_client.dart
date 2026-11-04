import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/settings.dart';

class ForgeHealth {
  const ForgeHealth({required this.online, this.version, this.rembg = false, this.message});

  final bool online;
  final String? version;
  final bool rembg;
  final String? message;
}

/// PetForge 本地服务客户端：照片 -> 宠物贴纸。
class PetForgeClient {
  PetForgeClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static Uri _endpoint(String baseUrl, String path) {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$path');
  }

  Future<ForgeHealth> health(String baseUrl) async {
    try {
      final response = await _client
          .get(_endpoint(baseUrl, '/api/health'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) {
        return ForgeHealth(online: false, message: 'HTTP ${response.statusCode}');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final caps = (data['capabilities'] as Map?) ?? const {};
      return ForgeHealth(
        online: data['ok'] == true,
        version: data['version']?.toString(),
        rembg: caps['rembg'] == true,
      );
    } catch (error) {
      return ForgeHealth(online: false, message: error.toString());
    }
  }

  Future<GeneratedPet> generate({
    required Uint8List bytes,
    required String baseUrl,
    String filename = 'upload.png',
    String style = 'sticker',
    String? name,
    bool animate = false,
    String engine = 'procedural',
    bool atlas = false,
  }) async {
    final request = http.MultipartRequest('POST', _endpoint(baseUrl, '/api/generate'));
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    request.fields['style'] = style;
    if (name != null && name.trim().isNotEmpty) request.fields['name'] = name.trim();
    request.fields['animate'] = animate ? 'true' : 'false';
    request.fields['engine'] = engine;
    request.fields['atlas'] = atlas ? 'true' : 'false';

    // rembg 首次推理要下载模型（约 170MB），3 分钟上限给足余量；
    // 超时抛 TimeoutException，AppController 会降级到本地徽章模式。
    final streamed = await _client.send(request).timeout(const Duration(minutes: 3));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      throw ForgeException('生成服务返回 ${response.statusCode}：${_shortBody(response.bodyBytes)}');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final rawImages = (data.remove('images') as Map?) ?? const {};
    final images = <String, Uint8List>{};
    rawImages.forEach((key, value) {
      final payload = value is Map ? value['data'] : value;
      if (payload is String && payload.isNotEmpty) {
        images[key.toString()] = base64Decode(payload);
      }
    });
    if (images['base'] == null) {
      throw const ForgeException('生成结果里没有图片');
    }
    return GeneratedPet(
      pack: data,
      images: images,
      elapsedMs: (data['elapsedMs'] as num?)?.toInt() ?? 0,
    );
  }

  String _shortBody(Uint8List bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    return text.length > 200 ? text.substring(0, 200) : text;
  }
}

class ForgeException implements Exception {
  const ForgeException(this.message);

  final String message;

  @override
  String toString() => message;
}
