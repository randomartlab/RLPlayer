import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Google 翻译（gtx 免费端点，无 Key 尝试；不可用则静默失败）。
class TranslationService {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
  ));

  /// 翻译文本；失败返回 null（调用方保持原文）。
  static Future<String?> translate(String text, {String to = 'zh-CN'}) async {
    try {
      final response = await _dio.get(
        'https://translate.googleapis.com/translate_a/single',
        queryParameters: {
          'client': 'gtx',
          'sl': 'auto',
          'tl': to,
          'dt': 't',
          'q': text,
        },
        options: Options(responseType: ResponseType.json),
      );
      final data = response.data;
      if (data is List && data.isNotEmpty && data[0] is List) {
        final parts = (data[0] as List)
            .whereType<List>()
            .map((seg) => (seg[0] ?? '') as String)
            .join();
        if (parts.trim().isNotEmpty) return parts;
      }
      return null;
    } catch (e) {
      debugPrint('[Translate] gtx 不可用: $e');
      return null;
    }
  }
}
