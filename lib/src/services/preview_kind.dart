/// 文件树附加文件分类（图片/字幕），带内容嗅探（2026-09-02）。
///
/// 仅凭扩展名会混淆（用户反馈：部分图被识别成歌词、部分歌词被标成
/// 图）。规则：图片魔数优先（无论扩展名）；字幕特征文本次之；再按
/// 扩展名兜底。
library;

import 'dart:io';

enum PreviewKind { image, subtitle, video, other }

extension PreviewKindX on PreviewKind {
  bool get isImage => this == PreviewKind.image;
  bool get isSubtitle => this == PreviewKind.subtitle;
  bool get isVideo => this == PreviewKind.video;
}

/// 读取文件头，返回分类。
PreviewKind classifyPreviewFile(File file) {
  RandomAccessFile? raf;
  try {
    raf = file.openSync();
    final head = raf.readSync(2048);
    if (head.isEmpty) {
      // 空文件按扩展名兜底。
      return _byExt(file.path);
    }
    // 0) 视频容器扩展（mp4/mkv 等二进制，无需内容魔数；在文本判断前）。
    if (_isVideoExt(file.path)) return PreviewKind.video;
    // 1) 图片魔数（内容优先）。
    if (_isImageMagic(head)) return PreviewKind.image;
    // 2) 字幕特征文本：WEBVTT / 时间轴 / LRC 标签。
    if (_looksLikeSubtitle(head)) return PreviewKind.subtitle;
    // 3) 文本内容但扩展名是图 → 不是图；扩展名字幕且纯文本 → 字幕。
    if (_isLikelyText(head)) {
      return _byExt(file.path) == PreviewKind.subtitle
          ? PreviewKind.subtitle
          : PreviewKind.other;
    }
    // 二进制且非图：可能音频/其它 → other。
    return PreviewKind.other;
  } catch (_) {
    return _byExt(file.path);
  } finally {
    try {
      raf?.closeSync();
    } catch (_) {}
  }
}

bool _isImageMagic(List<int> b) {
  if (b.length < 12) return false;
  if (b[0] == 0xFF && b[1] == 0xD8) return true; // JPEG
  if (b[0] == 0x89 && b[1] == 0x50) return true; // PNG
  if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return true; // GIF
  if (b[0] == 0x42 && b[1] == 0x4D) return true; // BMP
  if (b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
    return true; // WEBP（RIFF....WEBP）
  }
  return false;
}

/// 疑似字幕文本：WEBVTT 头 / hh:mm:ss --> / [mm:ss 歌词 / SRT 序号块。
bool _looksLikeSubtitle(List<int> head) {
  // 仅对文本内容判断（避免二进制误判）。
  if (!_isLikelyText(head)) return false;
  final text = String.fromCharCodes(head);
  return text.contains('WEBVTT') ||
      RegExp(r'\d{1,2}:\d{2}:\d{2}[.,]\d{1,3}\s*-->').hasMatch(text) ||
      RegExp(r'\d{1,2}:\d{2}[.,]\d{1,3}\s*-->').hasMatch(text) ||
      RegExp(r'\[\d{1,2}:\d{2}[.:]\d{1,3}\]').hasMatch(text);
}

bool _isVideoExt(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.mp4') ||
      lower.endsWith('.m4v') ||
      lower.endsWith('.mkv') ||
      lower.endsWith('.webm') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.avi') ||
      lower.endsWith('.wmv') ||
      lower.endsWith('.flv') ||
      lower.endsWith('.ts') ||
      lower.endsWith('.m2ts') ||
      lower.endsWith('.3gp') ||
      lower.endsWith('.mpg') ||
      lower.endsWith('.mpeg') ||
      lower.endsWith('.ogv');
}

bool _isLikelyText(List<int> head) {
  if (head.length < 4) return false;
  // 空字节占比高视为二进制。
  var nul = 0;
  for (var i = 0; i < head.length; i++) {
    if (head[i] == 0) nul++;
  }
  return nul / head.length < 0.1;
}

PreviewKind _byExt(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.bmp') ||
      lower.endsWith('.avif')) {
    return PreviewKind.image;
  }
  if (lower.endsWith('.lrc') ||
      lower.endsWith('.srt') ||
      lower.endsWith('.vtt')) {
    return PreviewKind.subtitle;
  }
  return PreviewKind.other;
}
