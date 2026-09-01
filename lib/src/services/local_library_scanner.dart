import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/work.dart';
import 'scan_rules.dart';

/// 穿透扫描引擎（PRD §5.9）。
///
/// 识别完全离线、不依赖任何网络：
/// - 递归下钻全部层级子目录发现 RJ 作品文件夹（验收 #17）；
/// - RJ 号取值优先级：①表层文件夹名 > ②metadata.json > ③内部文件兜底（决策 5）；
/// - 单文件夹内识别音频/歌词/字幕/封面并做同名自动关联；
/// - 封面 5 级降级链（本地图片 → 内嵌 → 占位；网络兜底属 M11）。
class LocalLibraryScanner {
  LocalLibraryScanner({this.embeddedCoverDir});

  /// 内嵌封面提取落盘目录（app 支持目录下 covers/）。
  final Directory? embeddedCoverDir;

  /// 扫描进度回调。
  void Function(String currentPath, int foundWorks)? onProgress;

  /// 取消标记；外部置 true 后扫描尽快收尾。
  bool cancelled = false;

  final Set<String> _embeddedCoverWritten = {};

  /// 已有作品签名（rootPath → 文件数:总字节），增量扫描比对用。
  final Map<String, String> existingSignatures = {};

  /// 计算目录签名（文件数 + 总字节；快速变更检测，增量扫描优化）。
  Future<String> _dirSignature(String dirPath) async {
    var count = 0;
    var bytes = 0;
    final dir = Directory(dirPath);
    if (!await dir.exists()) return '';
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        count++;
        try {
          bytes += await entity.length();
        } catch (_) {}
      }
    }
    return '$count:$bytes';
  }

  /// 穿透扫描多个根目录，返回全部识别结果。
  Future<List<ScannedWork>> scanRoots(List<String> rootPaths) async {
    final works = <ScannedWork>[];
    for (final rootPath in rootPaths) {
      final root = Directory(rootPath);
      final exists = await root.exists();
      debugPrint('[KikoScan] root=$rootPath exists=$exists');
      if (!exists) continue;
      try {
        await _scanDirectory(root, works);
      } catch (e, stack) {
        // 单个根目录失败不影响其他根目录（权限/IO 异常不静默丢失）。
        debugPrint('[KikoScan] 根目录扫描失败 root=$rootPath: $e');
        debugPrintStack(stackTrace: stack, maxFrames: 6);
      }
      if (cancelled) break;
    }
    debugPrint('[KikoScan] 扫描完成，共 ${works.length} 个作品');
    return works;
  }

  Future<void> _scanDirectory(
    Directory directory,
    List<ScannedWork> works,
  ) async {
    if (cancelled) return;

    final entries = await _listEntries(directory);
    final dirs = entries.whereType<Directory>().toList();
    final files = entries.whereType<File>().toList();
    final folderName = p.basename(directory.path);

    debugPrint('[KikoScan] dir=$folderName entries=${entries.length} '
        'audio=${files.where((f) => classifyFile(p.basename(f.path)) == FileClass.audio).length}');

    onProgress?.call(directory.path, works.length);

    // ① 表层文件夹名含 RJ 号 → 作品层，不再向下找 RJ（PRD 决策 5）。
    if (parseRjInfo(folderName) != null) {
      final work = await _buildWork(
        directory,
        files: files,
        dirs: dirs,
        rjFromFolder: parseRjInfo(folderName),
      );
      if (work != null) {
        debugPrint('[KikoScan] 作品=${work.rjCode ?? work.title} '
            'tracks=${work.trackCount} cover=${work.coverSource.name}');
        works.add(work);
      }
      return;
    }

    // ② metadata.json（Kikoeru 导出格式）存在 → 作品。
    final hasMetadata =
        files.any((f) => classifyFile(p.basename(f.path)) == FileClass.metadata);
    if (hasMetadata) {
      final work = await _buildWork(directory, files: files, dirs: dirs);
      if (work != null) works.add(work);
      return;
    }

    // ③ 含音频文件 → 以文件夹名为标题的待整理作品（不再下钻）。
    final hasAudio = files.any(
      (f) => classifyFile(p.basename(f.path)) == FileClass.audio,
    );
    if (hasAudio) {
      final work = await _buildWork(directory, files: files, dirs: dirs);
      if (work != null) works.add(work);
      return;
    }

    // 无音频、无 metadata → 继续下钻子目录（穿透扫描）。
    for (final dir in dirs) {
      await _scanDirectory(dir, works);
      if (cancelled) return;
    }
  }

  Future<List<FileSystemEntity>> _listEntries(Directory directory) async {
    final entries = <FileSystemEntity>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (isHiddenEntry(p.basename(entity.path))) continue;
      entries.add(entity);
    }
    return entries;
  }

  /// 在作品文件夹内完成识别与组装（递归全部子目录，PRD §5.9.2）。
  Future<ScannedWork?> _buildWork(
    Directory workDir, {
    required List<File> files,
    required List<Directory> dirs,
    RjInfo? rjFromFolder,
  }) async {
    // ---- 1. 递归收集文件 ----
    final audioFiles = <File>[];
    final sidecarFiles = <File>[]; // lrc / vtt / srt
    final imageFiles = <File>[];
    File? metadataFile;

    void classify(File file) {
      switch (classifyFile(p.basename(file.path))) {
        case FileClass.audio:
          audioFiles.add(file);
        case FileClass.lyric || FileClass.subtitle:
          sidecarFiles.add(file);
        case FileClass.image:
          imageFiles.add(file);
        case FileClass.metadata:
          metadataFile ??= file;
        case FileClass.other:
          break;
      }
    }

    for (final file in files) {
      classify(file);
    }
    await _collectRecursive(dirs, classify);

    if (audioFiles.isEmpty) return null;

    // ---- 2. metadata.json 解析（Kikoeru 格式，PRD §5.9.2 字段映射） ----
    Map<String, dynamic>? metadata;
    if (metadataFile != null) {
      metadata = _tryParseJson(await _readText(metadataFile!));
    }

    // ---- 3. RJ 号仲裁：表层文件夹名 > metadata.json > 内部文件兜底 ----
    String? rjCode = rjFromFolder?.code;
    rjCode ??= _rjFromMetadata(metadata);

    // ---- 4. 音轨时长提取（元数据读取；失败标记未知） ----
    // 增量优化：目录签名未变（文件数+总字节相同）时跳过逐文件元数据解析
    // （最耗时阶段），识别速度大幅提升；时长视为未知由首次播放回写。
    final signature = await _dirSignature(workDir.path);
    final unchanged =
        existingSignatures[workDir.path] == signature && signature.isNotEmpty;
    if (signature.isNotEmpty) existingSignatures[workDir.path] = signature;

    final durations = <File, int?>{};
    final keepAudio = <File>[];
    for (final audio in audioFiles) {
      final size = await audio.length();
      int? durationSeconds;
      if (!unchanged) {
        try {
          final meta = readMetadata(audio);
          durationSeconds = meta.duration?.inSeconds;
        } catch (_) {
          // 时长提取失败 → 未知；首次播放后回写。
        }
      }
      if (isTinyAudio(size, durationSeconds)) continue; // 小文件过滤
      durations[audio] = durationSeconds;
      keepAudio.add(audio);
    }
    audioFiles
      ..clear()
      ..addAll(keepAudio);
    if (audioFiles.isEmpty) return null;

    if (rjCode == null) {
      // ③ 兜底：内部音频文件名含 RJ 号。
      for (final audio in audioFiles) {
        final info = parseRjInfo(p.basename(audio.path));
        if (info != null) {
          rjCode = info.code;
          break;
        }
      }
    }

    // ---- 5. 标题：metadata.title > 文件夹名（去 RJ 前缀） ----
    final folderName = p.basename(workDir.path);
    var title = _stringOf(metadata?['title']);
    if (title == null || title.trim().isEmpty) {
      title = rjFromFolder != null && rjFromFolder.title.isNotEmpty
          ? rjFromFolder.title
          : folderName;
    }

    // ---- 6. 歌词/字幕同名自动关联（按目录分组） ----
    final lyricMap = <File, File>{};
    final subtitleMap = <File, File>{};
    final byDirAudio = <String, List<File>>{};
    final byDirLyrics = <String, List<File>>{};
    final byDirSubtitles = <String, List<File>>{};
    for (final audio in audioFiles) {
      byDirAudio.putIfAbsent(audio.parent.path, () => []).add(audio);
    }
    for (final sidecar in sidecarFiles) {
      final kind = classifyFile(p.basename(sidecar.path));
      if (kind == FileClass.lyric) {
        byDirLyrics.putIfAbsent(sidecar.parent.path, () => []).add(sidecar);
      } else if (kind == FileClass.subtitle) {
        byDirSubtitles
            .putIfAbsent(sidecar.parent.path, () => [])
            .add(sidecar);
      }
    }
    for (final entry in byDirAudio.entries) {
      final dirPath = entry.key;
      final audioNames = entry.value.map((f) => p.basename(f.path)).toList();

      final lyricNames = (byDirLyrics[dirPath] ?? const [])
          .map((f) => p.basename(f.path))
          .toList();
      final lyricAssoc = associateSameName(audioNames, lyricNames);
      for (final audio in entry.value) {
        final lyricName = lyricAssoc[p.basename(audio.path)];
        if (lyricName != null) {
          lyricMap[audio] = File(p.join(dirPath, lyricName));
        }
      }

      final subtitleNames = (byDirSubtitles[dirPath] ?? const [])
          .map((f) => p.basename(f.path))
          .toList();
      final subtitleAssoc = associateSameName(audioNames, subtitleNames);
      for (final audio in entry.value) {
        final subtitleName = subtitleAssoc[p.basename(audio.path)];
        if (subtitleName != null) {
          subtitleMap[audio] = File(p.join(dirPath, subtitleName));
        }
      }
    }

    // ---- 7. 封面 5 级降级链（本地图片 → 内嵌 → 占位） ----
    final audioBases = audioFiles
        .map((f) => p.basenameWithoutExtension(f.path).toLowerCase())
        .toSet();
    final coverCandidates = <CoverCandidate>[];
    for (final image in imageFiles) {
      coverCandidates.add(CoverCandidate(
        relativePath: p.relative(image.path, from: workDir.path),
        absolutePath: image.path,
        baseName: p.basenameWithoutExtension(image.path).toLowerCase(),
        sizeBytes: await image.length(),
        depth: p
            .relative(image.parent.path, from: workDir.path)
            .split(p.separator)
            .length,
        sameNameAsAudio: audioBases
            .contains(p.basenameWithoutExtension(image.path).toLowerCase()),
      ));
    }
    // metadata 指明的封面路径优先（PRD：本地无图片文件时）。
    String? coverPath = pickLocalCover(coverCandidates);
    if (coverPath == null && metadata != null) {
      final mainCover = _stringOf(metadata['mainCover']);
      if (mainCover != null) {
        final candidate = File(p.join(workDir.path, mainCover));
        if (await candidate.exists()) coverPath = candidate.path;
      }
    }
    var coverSource = CoverSource.localFile;
    if (coverPath == null) {
      // 优先级 4：音频内嵌封面提取落盘。
      coverPath = await _extractEmbeddedCover(audioFiles, workDir.path);
      coverSource =
          coverPath != null ? CoverSource.embedded : CoverSource.placeholder;
    }

    // ---- 8. 构建文件树（目录 + 音轨，自然排序） ----
    final nodes = _buildNodes(workDir, audioFiles, durations,
        lyricMap: lyricMap, subtitleMap: subtitleMap);

    // ---- 9. 汇总（全部时长未知时总时长为 null，不崩溃）----
    final knownDurations = durations.values.whereType<int>().toList();
    final totalDuration =
        knownDurations.isEmpty ? null : knownDurations.reduce((a, b) => a + b);

    return ScannedWork(
      rjCode: rjCode,
      title: title,
      circleName: _stringOf(
          (metadata?['circle'] as Map<String, dynamic>?)?['name']),
      vasNames: _stringsOf(metadata?['vas']),
      tags: _stringsOf(metadata?['tags']),
      rootPath: workDir.path,
      coverPath: coverPath,
      coverSource: coverSource,
      durationSeconds: totalDuration,
      trackCount: audioFiles.length,
      hasLyric: lyricMap.isNotEmpty,
      hasSubtitle: subtitleMap.isNotEmpty,
      nsfw: _boolOf(metadata?['nsfw']),
      nodes: nodes,
    );
  }

  Future<void> _collectRecursive(
    List<Directory> dirs,
    void Function(File) onFile,
  ) async {
    for (final dir in dirs) {
      if (cancelled) return;
      final entries = await _listEntries(dir);
      for (final entry in entries) {
        if (entry is File) {
          onFile(entry);
        } else if (entry is Directory) {
          await _collectRecursive([entry], onFile);
        }
      }
    }
  }

  /// 构建文件树：仅保留包含音轨的目录链，目录与音轨同级自然排序。
  List<ScannedNode> _buildNodes(
    Directory workDir,
    List<File> audioFiles,
    Map<File, int?> durations, {
    required Map<File, File> lyricMap,
    required Map<File, File> subtitleMap,
  }) {
    final nodes = <ScannedNode>[];

    // 包含音轨的目录集合（含其祖先链）。
    final dirsWithAudio = <String>{};
    for (final audio in audioFiles) {
      var dir = audio.parent.path;
      while (dir.length > workDir.path.length &&
          dir.startsWith(workDir.path)) {
        dirsWithAudio.add(dir);
        dir = p.dirname(dir);
      }
    }

    for (final dir in dirsWithAudio) {
      nodes.add(ScannedNode(
        isDirectory: true,
        name: p.basename(dir),
        relativePath: p.relative(dir, from: workDir.path),
        // p.relative(工作目录自身) 返回 '.'，归一为 ''（根）。
        parentPath:
            _normalizeRelative(p.dirname(dir), workDir.path),
      ));
    }
    for (final audio in audioFiles) {
      nodes.add(ScannedNode(
        isDirectory: false,
        name: p.basename(audio.path),
        relativePath: p.relative(audio.path, from: workDir.path),
        parentPath:
            _normalizeRelative(audio.parent.path, workDir.path),
        filePath: audio.path,
        durationSeconds: durations[audio],
        lyricPath: lyricMap[audio]?.path,
        subtitlePath: subtitleMap[audio]?.path,
      ));
    }

    nodes.sort(compareNode);
    return nodes;
  }

  /// 相对路径归一：工作目录自身（'.'）返回 ''（根）。
  /// POSIX p.relative(x, from: x) 返回 '.'，历史数据中 parent_path 存过 '.'。
  static String _normalizeRelative(String path, String from) {
    final result = p.relative(path, from: from);
    return result == '.' ? '' : result;
  }

  /// 目录在前、同级自然排序。
  static int compareNode(ScannedNode a, ScannedNode b) {
    final dirCompare =
        (a.isDirectory ? 0 : 1).compareTo(b.isDirectory ? 0 : 1);
    if (dirCompare != 0) return dirCompare;
    final natural = compareNatural(a.name, b.name);
    if (natural != 0) return natural;
    return a.relativePath.compareTo(b.relativePath);
  }

  Future<String?> _extractEmbeddedCover(
    List<File> audioFiles,
    String workDirPath,
  ) async {
    final coverDir = embeddedCoverDir;
    if (coverDir == null) return null;

    for (final audio in audioFiles) {
      try {
        final metadata = readMetadata(audio, getImage: true);
        final pictures = metadata.pictures;
        if (pictures.isEmpty) continue;

        final picture = pictures.first;
        final bytes = picture.bytes;
        if (bytes.isEmpty) continue;

        final ext = switch (picture.mimetype) {
          'image/png' => '.png',
          'image/webp' => '.webp',
          _ => '.jpg',
        };
        final key = _coverKey(workDirPath);
        if (_embeddedCoverWritten.contains(key)) return _lastEmbeddedPath;
        final file = File(p.join(coverDir.path, '$key$ext'));
        await file.writeAsBytes(bytes, flush: true);
        _embeddedCoverWritten.add(key);
        _lastEmbeddedPath = file.path;
        return file.path;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  String? _lastEmbeddedPath;

  /// 清理本次扫描之外的内嵌封面文件（扫描开始时调用）。
  Future<void> cleanOrphanEmbeddedCovers() async {
    final coverDir = embeddedCoverDir;
    if (coverDir == null) return;
    if (!await coverDir.exists()) return;
    await for (final entity in coverDir.list()) {
      if (entity is File) {
        final base = p.basenameWithoutExtension(entity.path);
        if (!_embeddedCoverWritten.contains(base)) {
          await entity.delete().catchError((_) => entity);
        }
      }
    }
  }

  String _coverKey(String workDirPath) {
    // 目录路径哈希做封面文件名，避免特殊字符问题。
    return workDirPath.hashCode.toRadixString(36).replaceAll('-', 'm');
  }

  String? _rjFromMetadata(Map<String, dynamic>? metadata) {
    if (metadata == null) return null;
    final id = metadata['id'];
    if (id is num && id > 0) {
      return 'RJ${id.toString().padLeft(6, '0')}';
    }
    final sourceId = _stringOf(metadata['source_id']);
    if (sourceId != null) {
      final info = parseRjInfo(sourceId);
      if (info != null) return info.code;
    }
    return null;
  }

  Map<String, dynamic>? _tryParseJson(String? content) {
    if (content == null) return null;
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // 本地 metadata 解析 best-effort，非法文件不阻塞导入。
    }
    return null;
  }

  /// 读文本文件：编码嗅探 UTF-8 → Shift-JIS → GBK（PRD §5.9.2）。
  Future<String?> _readText(File file) async {
    final bytes = await file.readAsBytes();
    return decodeTextWithFallback(bytes);
  }

  static String? _stringOf(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  /// vas: [{name: ...}] → 名字列表。
  static List<String> _stringsOf(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((e) => e is Map ? ((e['name'] ?? '') as String).trim() : '')
        .where((name) => name.isNotEmpty)
        .toList();
  }

  static bool? _boolOf(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return null;
  }
}
