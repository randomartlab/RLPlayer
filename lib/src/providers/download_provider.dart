import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/download_service.dart';

/// 下载队列状态提供者（M12 下载管理 + 下载即入库触发）。
class DownloadProvider extends ChangeNotifier {
  DownloadProvider(this.service) {
    service.addListener(_onServiceChanged);
  }

  final DownloadService service;

  List<DownloadTask> get tasks => service.tasks;
  bool get isDownloading => service.tasks.any(
      (t) => t.status == DownloadStatus.queued || t.status == DownloadStatus.running);

  /// 队列空闲过一次（触发入库扫描的钩子）。
  bool _wasBusy = false;
  Future<void> Function(Set<int> completedWorkIds)? onQueueIdle;

  void _onServiceChanged() {
    final busy = isDownloading;
    if (_wasBusy && !busy) {
      final completed = service.completedWorkIds();
      if (completed.isNotEmpty && onQueueIdle != null) {
        debugPrint('[Download] 队列空闲，触发入库扫描: $completed');
        unawaited(onQueueIdle!(completed));
      }
    }
    _wasBusy = busy;
    notifyListeners();
  }

  void cancel(DownloadTask task) => service.cancel(task);
  void remove(DownloadTask task) => service.remove(task);
  void clearFinished() => service.clearFinished();

  @override
  void dispose() {
    service.removeListener(_onServiceChanged);
    super.dispose();
  }
}
