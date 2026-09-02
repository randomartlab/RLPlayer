import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 免费翻译服务（照抄 kikoflu 思路：Google 免费端点 + 失败回退原文）。
///
/// 端点选择（实测 2026-09-02，中国大陆直连）：
/// - translate.googleapis.com/translate_a/single → 429（不可用）
/// - translate.google.com/m（网页端点）→ 200 可用 ✅
///
/// 仅对非中文文本生效（[isMostlyChinese] 判定），翻译结果带内存缓存。
class TranslationService {
  TranslationService._();

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
    // 网页端点需要浏览器 UA。
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
    },
  ));

  /// 翻译缓存（进程内存级；同名文件树反复进出不再请求）。
  static final Map<String, String> _cache = <String, String>{};

  /// 判断文本是否主要为中日韩表意文字（是则无需翻译）。
  ///
  /// kikoflu 同款思路：仅对非中文标题/文件名生效（用户需求 2026-09-02）。
  /// 日文假名也算"无需翻译"以外的情形——但用户明确要求翻译日文文件名，
  /// 所以只豁免中文汉字为主（含少量假名混排时若汉字占比高也豁免）。
  static bool isMostlyChinese(String text) {
    final chars = text.replaceAll(RegExp(r'[\s\d\p{P}]', unicode: true), '');
    if (chars.isEmpty) return false;
    final cjk =
        chars.runes.where((r) => r >= 0x4E00 && r <= 0x9FFF).length;
    final kana = chars.runes
        .where((r) => (r >= 0x3040 && r <= 0x30FF) || r == 0x30FC)
        .length;
    // 无假名且汉字占绝大多数 → 中文。
    if (kana == 0) return cjk / chars.length > 0.5;
    // 有假名：假名占比低且汉字多 → 疑似中文夹杂符号，视为中文。
    return kana / chars.length < 0.15 && cjk / chars.length > 0.6;
  }

  /// 翻译文本；中文/失败返回 null（调用方保持原文）。
  static Future<String?> translate(String text, {String to = 'zh-CN'}) async {
    if (text.trim().isEmpty || isMostlyChinese(text)) return null;

    final cacheKey = '$to|$text';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    try {
      final response = await _dio.get(
        'https://translate.google.com/m',
        queryParameters: {'sl': 'auto', 'tl': to, 'q': text},
        options: Options(responseType: ResponseType.plain),
      );
      final html = response.data as String?;
      if (html == null) return null;
      // 网页端点结果在 <div class="result-container">…</div>。
      final match = RegExp(
              r'class="result-container">([^<]*)</div>',
              caseSensitive: false)
          .firstMatch(html);
      final result = match?.group(1)?.trim();
      if (result == null || result.isEmpty || result == text) return null;
      _cache[cacheKey] = result;
      return result;
    } catch (e) {
      debugPrint('[Translate] 失败: $e');
      return null;
    }
  }

  /// 批量翻译（文件树整树翻译；逐条并发受限，分批小并发）。
  ///
  /// 返回 原文 → 译文 映射；失败/中文条目不在结果中。
  static Future<Map<String, String>> translateBatch(
    List<String> texts, {
    String to = 'zh-CN',
    void Function(int done, int total)? onProgress,
  }) async {
    final result = <String, String>{};
    final pending = texts.where((t) => !isMostlyChinese(t)).toList();
    if (pending.isEmpty) return result;

    var done = 0;
    // 小并发（网页端点对高频请求敏感）。
    const concurrency = 3;
    var index = 0;
    Future<void> worker() async {
      while (index < pending.length) {
        final i = index++;
        final translated = await translate(pending[i], to: to);
        if (translated != null) result[pending[i]] = translated;
        done++;
        onProgress?.call(done, pending.length);
      }
    }

    await Future.wait(
        List.generate(concurrency.clamp(1, pending.length), (_) => worker()));
    return result;
  }

  /// 仅供测试清缓存。
  static void clearCache() => _cache.clear();
}
