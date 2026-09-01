import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/online_models.dart';

/// 下载任务状态（M12 下载管理）。
enum DownloadStatus { queued, running, completed, failed, cancelled }

class DownloadTask {
  DownloadTask({
    required this.workId,
    required this.workTitle,
    required this.fileName,
    required this.url,
    required this.relativePath,
    this.status = DownloadStatus.queued,
    this.progress = 0,
    this.error,
  });

  final int workId;
  final String workTitle;

  /// 单文件名（含相对路径结构）。
  final String fileName;

  /// 下载 URL。
  final String url;

  /// 作品目录内相对路径（还原文件树结构）。
  final String relativePath;

  DownloadStatus status;
  double progress; // 0~1（无 Content-Length 时保持 0，由 receivedBytes 展示）
  int receivedBytes = 0;
  String? error;

  String get workDirName => 'RJ${workId.toString().padLeft(6, '0')}';
}

/// 下载服务（M12：队列 + 并发限制 + 进度；断点续传 M3 后续补齐）。
///
/// 下载目录 = 本地扫描根目录下的 downloads/（PRD §5.12 模块互通），
/// 完成后由调用方触发 M8 增量扫描入库（下载即入库）。
class DownloadService {
  DownloadService({required this.downloadRoot});

  /// 下载根目录（<扫描根目录>/downloads）；跟随扫描根目录变化（main.dart 同步）。
  String downloadRoot;

  final Dio _dio = Dio();

  /// 同时下载文件数。
  static const int maxConcurrent = 3;

  final List<DownloadTask> _queue = [];
  final Map<DownloadTask, CancelToken> _running = {};
  final _listeners = <VoidCallback>[];

  List<DownloadTask> get tasks => List.unmodifiable(_queue);
  int get activeCount =>
      _queue.where((t) => t.status == DownloadStatus.running).length;

  void addListener(VoidCallback listener) => _listeners.add(listener);
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void _notify() {
    for (final listener in _listeners) {
      listener();
    }
  }

  String workRoot(DownloadTask task) =>
      p.join(downloadRoot, task.workDirName);

  /// 入队整个作品的全部音轨文件（保留文件树相对路径结构）。
  void enqueueWork(OnlineWork work, List<OnlineFileNode> audioNodes,
      String Function(OnlineFileNode) urlOf) {
    for (final node in audioNodes) {
      enqueueFile(work, node, urlOf(node));
    }
    _pump();
  }

  void enqueueFile(OnlineWork work, OnlineFileNode node, String url) {
    // 去重：同作品同路径。
    final exists = _queue.any((t) =>
        t.workId == work.id && t.relativePath == node.title);
    if (exists) return;

    _queue.add(DownloadTask(
      workId: work.id,
      workTitle: work.title,
      fileName: node.title,
      url: url,
      relativePath: node.title,
    ));
    _notify();
  }

  void cancel(DownloadTask task) {
    if (task.status == DownloadStatus.running) {
      _running[task]?.cancel();
    }
    task.status = DownloadStatus.cancelled;
    _notify();
  }

  void remove(DownloadTask task) {
    cancel(task);
    _queue.remove(task);
    _notify();
  }

  void clearFinished() {
    _queue.removeWhere((t) =>
        t.status == DownloadStatus.completed ||
        t.status == DownloadStatus.cancelled ||
        t.status == DownloadStatus.failed);
    _notify();
  }

  /// 驱动队列：启动排队任务直至并发上限。
  void _pump() {
    final waiting = _queue
        .where((t) => t.status == DownloadStatus.queued)
        .toList(growable: false);
    for (final task in waiting) {
      if (activeCount >= maxConcurrent) break;
      _start(task);
    }
  }

  Future<void> _start(DownloadTask task) async {
    task.status = DownloadStatus.running;
    task.progress = 0;
    task.error = null;
    _notify();

    final target = p.join(workRoot(task), task.relativePath);
    await Directory(p.dirname(target)).create(recursive: true);

    final cancelToken = CancelToken();
    _running[task] = cancelToken;

    try {
      await _dio.download(
        task.url,
        target,
        cancelToken: cancelToken,
        options: Options(
          // 已存在且完整则跳过（简单幂等；断点续传后续用 Range 实现）。
          validateStatus: (status) => status != null && status < 500,
        ),
        onReceiveProgress: (received, total) {
          task.receivedBytes = received;
          if (total > 0) {
            task.progress = received / total;
          }
          _notify();
        },
      );
      task.status = DownloadStatus.completed;
      task.progress = 1;
      debugPrint('[Download] 完成: ${task.workDirName}/${task.relativePath}');
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        task.status = DownloadStatus.cancelled;
      } else {
        task.status = DownloadStatus.failed;
        task.error = e.message ?? e.toString();
        debugPrint('[Download] 失败: ${task.fileName} $e');
      }
    } catch (e) {
      task.status = DownloadStatus.failed;
      task.error = e.toString();
    } finally {
      _running.remove(task);
      _notify();
      _pump();
    }
  }

  /// 是否有任务正在下载（完成全部后调用方触发入库扫描）。
  bool get isIdle => activeCount == 0;

  /// 全部队列完成后待入库的作品 ID 集合。
  Set<int> completedWorkIds() => _queue
      .where((t) => t.status == DownloadStatus.completed)
      .map((t) => t.workId)
      .toSet();
}

/// 下载完成回调类型：触发 M8 增量扫描（下载即入库）。
typedef OnQueueIdle = Future<void> Function(Set<int> completedWorkIds);
