import 'dart:convert';

import 'package:charset/charset.dart' as charset;

/// 本地识别引擎的纯逻辑规则层（PRD §5.9）。
///
/// 全部为无 IO 的纯函数，便于单元测试；IO 部分见
/// `local_library_scanner.dart`。

/// RJ 号正则：RJ/BJ/VJ 前缀 + 6~8 位数字，不区分大小写（PRD 决策 5）。
final RegExp rjPattern = RegExp(r'(RJ|BJ|VJ)(\d{6,8})', caseSensitive: false);

/// 音频扩展名（PRD §5.9.2 + 实机反馈 2026-09-01：扩展常见格式）。
const Set<String> audioExtensions = {
  '.mp3', '.m4a', '.flac', '.wav', '.ogg', '.opus',
  '.aac', // 无损/有损常见（实机反馈）。
  '.wma',
  '.aiff',
  '.tak',
};

/// 歌词 / 字幕扩展名。
const String lyricExtension = '.lrc';
const Set<String> subtitleExtensions = {'.vtt', '.srt'};

/// 封面图片扩展名。
const Set<String> imageExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.avif'};

/// metadata.json 候选文件名（Kikoeru 导出格式为主，PRD 决策 7）。
const Set<String> metadataFileNames = {
  'metadata.json',
  'work_metadata.json',
  'work.json',
  'work_info.json',
};

/// 封面优先命中的关键词（中英日，不区分大小写；PRD §5.9.2 优先级 1）。
/// 用户确认（2026-09-01）：优先识别名字带「封面」或相关字样的图片。
/// 匹配两级：基础名精确等于关键词 > 基础名包含关键词（如 封面1.png /
/// cover_02.jpg / 表紙.jpg）。
const Set<String> coverKeywords = {
  // 英文（KikoFlu _coverBaseNames 全集）。
  'cover', 'folder', 'front', 'main', 'poster', 'thumbnail',
  // 中文。
  '封面',
  // 日文（音声作品常见命名）。
  'カバー', '表紙', '表纸',
};

/// 兼容旧引用。
const Set<String> coverBaseNames = coverKeywords;

/// 小文件过滤阈值（PRD §5.9.2：体积 < 100KB 且时长 < 10s 默认过滤）。
const int tinyAudioSizeLimit = 100 * 1024;
const int tinyAudioDurationLimitSeconds = 10;

/// 从文件夹/文件名解析 RJ 信息。
class RjInfo {
  const RjInfo({required this.code, required this.title});

  /// 标准化编号，如 "RJ123456"（前缀大写）。
  final String code;

  /// 编号之外的文字（去除分隔符后），为空则调用方应回退到完整文件夹名。
  final String title;
}

/// 从名称解析 RJ 号与标题候选；无 RJ 返回 null（表层优先，PRD 决策 5）。
RjInfo? parseRjInfo(String name) {
  final match = rjPattern.firstMatch(name);
  if (match == null) return null;

  final code = '${match.group(1)!.toUpperCase()}${match.group(2)}';
  // 编号之外的部分作为标题候选（去首尾空白/连字符/下划线，保留括号等语义字符）。
  var title = (name.substring(0, match.start) + name.substring(match.end))
      .trim();
  title = title.replaceAll(RegExp(r'^[\s_\-]+|[\s_\-]+$'), '');
  return RjInfo(code: code, title: title);
}

enum FileClass { audio, lyric, subtitle, image, metadata, other }

/// 文件分类（按扩展名；隐藏文件调用方自行过滤）。
FileClass classifyFile(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot >= 0 ? fileName.substring(dot).toLowerCase() : '';
  if (audioExtensions.contains(ext)) return FileClass.audio;
  if (ext == lyricExtension) return FileClass.lyric;
  if (subtitleExtensions.contains(ext)) return FileClass.subtitle;
  if (imageExtensions.contains(ext)) return FileClass.image;
  if (metadataFileNames.contains(fileName.toLowerCase())) {
    return FileClass.metadata;
  }
  return FileClass.other;
}

/// 隐藏文件/文件夹与下载中临时文件跳过（PRD §5.9.2）。
bool isHiddenEntry(String name) =>
    name.startsWith('.') || name.endsWith('.downloading');

/// 小音轨过滤：体积 < 100KB 且（已知时长 < 10s）（PRD §5.9.2，可关闭防误杀）。
bool isTinyAudio(int sizeBytes, int? durationSeconds) {
  if (sizeBytes >= tinyAudioSizeLimit) return false;
  if (durationSeconds == null) return false; // 时长未知时不过滤（保守）
  return durationSeconds < tinyAudioDurationLimitSeconds;
}

/// 音轨行显示名：去扩展名。
String trackDisplayName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot > 0 ? fileName.substring(0, dot) : fileName;
}

/// 数字感知自然排序：track2 < track10（PRD §5.9.2 文件树默认排序）。
int compareNatural(String a, String b) {
  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    final ca = a.codeUnitAt(i);
    final cb = b.codeUnitAt(j);
    final aDigit = ca >= 0x30 && ca <= 0x39;
    final bDigit = cb >= 0x30 && cb <= 0x39;

    if (aDigit && bDigit) {
      // 抽取两段完整数字串做数值比较。
      var ai = i;
      while (ai < a.length &&
          a.codeUnitAt(ai) >= 0x30 &&
          a.codeUnitAt(ai) <= 0x39) {
        ai++;
      }
      var bj = j;
      while (bj < b.length &&
          b.codeUnitAt(bj) >= 0x30 &&
          b.codeUnitAt(bj) <= 0x39) {
        bj++;
      }
      final na = a.substring(i, ai);
      final nb = b.substring(j, bj);
      final lenCompare = na.length.compareTo(nb.length);
      if (lenCompare != 0) return lenCompare;
      final valueCompare = na.compareTo(nb);
      if (valueCompare != 0) return valueCompare;
      i = ai;
      j = bj;
    } else {
      if (ca != cb) return ca.compareTo(cb);
      i++;
      j++;
    }
  }
  return (a.length - i).compareTo(b.length - j);
}

/// 音轨-歌词/字幕同名自动关联（PRD §5.9.2）。
///
/// 输入同一目录内的音频名与歌词/字幕名（均含扩展名），
/// 返回 音频名 → 关联文件名 的映射：
/// - 第一优先：完全同名（不含扩展名）；
/// - 第二优先：目录内音频唯一且歌词/字幕唯一（单音轨文件夹常见形态）。
Map<String, String> associateSameName(
  List<String> audioFileNames,
  List<String> sidecarFileNames,
) {
  final result = <String, String>{};
  if (audioFileNames.isEmpty || sidecarFileNames.isEmpty) return result;

  // 第一优先：完全同名。
  final sidecarByBase = <String, String>{
    for (final name in sidecarFileNames) trackDisplayName(name): name,
  };
  final unmatched = <String>[];
  for (final audio in audioFileNames) {
    final sidecar = sidecarByBase[trackDisplayName(audio)];
    if (sidecar != null) {
      result[audio] = sidecar;
    } else {
      unmatched.add(audio);
    }
  }
  if (unmatched.isEmpty) return result;

  // 第二优先：唯一音频 ↔ 唯一旁车文件。
  if (audioFileNames.length == 1 && sidecarFileNames.length == 1) {
    result[audioFileNames.first] = sidecarFileNames.first;
  }
  return result;
}

/// 封面候选（供 5 级降级链挑选，PRD §5.9.2）。
class CoverCandidate {
  const CoverCandidate({
    required this.relativePath,
    required this.absolutePath,
    required this.baseName,
    required this.sizeBytes,
    required this.depth,
    required this.sameNameAsAudio,
  });

  final String relativePath;
  final String absolutePath;
  final String baseName; // 小写
  final int sizeBytes;
  final int depth; // 0 = 作品文件夹顶层
  final bool sameNameAsAudio; // 与任一音频同名（01.mp3 ↔ 01.jpg）
}

/// 从候选图片中选出本地封面（优先级 1→3）。
///
/// 1. 名为 cover / folder 的图片（顶层优先，按深度）；
/// 2. 与任一音频同名的图片；
/// 3. 最大字节数的图片（启发式：封面通常远大于缩略图）。
///
/// 返回 null 表示无本地图片文件 → 调用方继续走内嵌封面（4）/占位（5）。
String? pickLocalCover(List<CoverCandidate> candidates) {
  if (candidates.isEmpty) return null;

  // 优先级 1：命名含封面关键词（中英日，用户确认 2026-09-01）。
  // 两级匹配：精确等于 > 名字包含关键词；各层级内浅层优先、取大。
  final exact = candidates
      .where((c) => coverKeywords.contains(c.baseName))
      .toList()
    ..sort((a, b) {
      final depth = a.depth.compareTo(b.depth);
      if (depth != 0) return depth;
      return a.sizeBytes.compareTo(b.sizeBytes);
    });
  if (exact.isNotEmpty) return exact.last.absolutePath;

  final contains = candidates
      .where((c) => coverKeywords
          .any((kw) => c.baseName.contains(kw)))
      .toList()
    ..sort((a, b) {
      final depth = a.depth.compareTo(b.depth);
      if (depth != 0) return depth;
      return a.sizeBytes.compareTo(b.sizeBytes);
    });
  if (contains.isNotEmpty) return contains.last.absolutePath;

  // 优先级 2：与音频同名。
  final sameName = candidates.where((c) => c.sameNameAsAudio).toList()
    ..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
  if (sameName.isNotEmpty) return sameName.first.absolutePath;

  // 优先级 3：最大字节数。
  final bySize = candidates.toList()
    ..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
  return bySize.first.absolutePath;
}

/// 文本编码嗅探：UTF-8 → Shift-JIS / GBK 评分选优（PRD §5.9.2）。
///
/// 返回解码后的文本；无法产出有效文本时返回 null，
/// 调用方标记"编码未知"。
String? decodeTextWithFallback(List<int> bytes) {
  // 1. 严格 UTF-8。
  try {
    return utf8.decode(bytes);
  } on FormatException {
    // 不是合法 UTF-8，继续。
  }

  // 2. Shift-JIS / GBK 双解码后评分选优。
  //
  // 无法仅靠"能否解码"区分两者（码位高度重叠）：Shift-JIS 会把 GBK 文本
  // 解成半角片假名乱码，GBK 会把日文解成无关汉字。评分依据：
  // - 日文文本几乎必含假名（平/片假名加分）；
  // - 中文文本几乎不含半角片假名（强减分）；
  // - CJK 统一表意文字作基础分。
  final candidates = <String>[];
  for (final decode in [_shiftJisDecode, _gbkDecode]) {
    try {
      final text = decode(bytes);
      if (text.isNotEmpty && _replacementRatio(text) <= 0.05) {
        candidates.add(text);
      }
    } catch (_) {
      // 当前编码解码失败，跳过。
    }
  }
  if (candidates.isEmpty) return null;
  if (candidates.length == 1) return candidates.first;

  candidates.sort((a, b) => _cjkScore(b).compareTo(_cjkScore(a)));
  return candidates.first;
}

double _replacementRatio(String text) {
  if (text.isEmpty) return 0;
  var replacements = 0;
  for (final rune in text.runes) {
    if (rune == 0xFFFD) replacements++;
  }
  return replacements / text.runes.length;
}

int _cjkScore(String text) {
  var score = 0;
  for (final rune in text.runes) {
    if (rune >= 0x3040 && rune <= 0x30FF) {
      score += 2; // 平假名 / 片假名（日文特征）
    } else if (rune >= 0x4E00 && rune <= 0x9FFF) {
      score += 1; // CJK 统一表意文字
    } else if (rune >= 0xFF61 && rune <= 0xFF9F) {
      score -= 5; // 半角片假名（GBK 文本被 Shift-JIS 误解的典型乱码）
    }
  }
  return score;
}

String _shiftJisDecode(List<int> bytes) {
  return const charset.ShiftJISCodec().decode(bytes);
}

String _gbkDecode(List<int> bytes) {
  return const charset.GbkCodec().decode(bytes);
}
