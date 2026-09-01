import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/download_provider.dart';
import '../services/download_service.dart';
import '../utils/ui_tokens.dart';

/// 下载管理页（M12：队列 / 进度 / 取消 / 清理）。
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final downloads = context.watch<DownloadProvider>();
    final scheme = Theme.of(context).colorScheme;
    final tasks = downloads.tasks;

    return Scaffold(
      appBar: AppBar(
        title: const Text('下载管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: '清理已完成',
            onPressed:
                tasks.isEmpty ? null : () => downloads.clearFinished(),
          ),
        ],
      ),
      body: tasks.isEmpty
          ? Center(
              child: Text(
                '暂无下载任务\n在线作品详情页点「下载全部」加入队列',
                textAlign: TextAlign.center,
                style: UiTextStyles.supporting
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            )
          : ListView.builder(
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final task = tasks[index];
                return _DownloadTaskTile(task: task);
              },
            ),
    );
  }
}

class _DownloadTaskTile extends StatelessWidget {
  const _DownloadTaskTile({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final downloads = context.read<DownloadProvider>();
    final scheme = Theme.of(context).colorScheme;

    final statusText = switch (task.status) {
      DownloadStatus.queued => '排队中',
      DownloadStatus.running => task.progress > 0
          ? '下载中 ${(task.progress * 100).toInt()}%'
          : '下载中 ${_formatBytes(task.receivedBytes)}',
      DownloadStatus.completed => '已完成',
      DownloadStatus.failed => '失败',
      DownloadStatus.cancelled => '已取消',
    };

    return ListTile(
      leading: _statusIcon(context, task.status),
      title: Text(
        task.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${task.workDirName} · $statusText',
            style: UiTextStyles.supporting
                .copyWith(color: scheme.onSurfaceVariant),
          ),
          if (task.status == DownloadStatus.running)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(
                // 无 Content-Length 时显示不确定进度条。
                value: task.progress > 0 ? task.progress : null,
                minHeight: 4,
              ),
            ),
          if (task.status == DownloadStatus.failed && task.error != null)
            Text(
              task.error!,
              style: UiTextStyles.supporting.copyWith(color: scheme.error),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      trailing: task.status == DownloadStatus.running ||
              task.status == DownloadStatus.queued
          ? IconButton(
              icon: const Icon(Icons.close),
              tooltip: '取消',
              onPressed: () => downloads.cancel(task),
            )
          : IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '移除',
              onPressed: () => downloads.remove(task),
            ),
    );
  }

  Widget _statusIcon(BuildContext context, DownloadStatus status) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      DownloadStatus.queued => Icon(Icons.schedule,
          color: scheme.onSurfaceVariant),
      DownloadStatus.running => const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2.5)),
      DownloadStatus.completed => Icon(Icons.check_circle,
          color: scheme.primary),
      DownloadStatus.failed => Icon(Icons.error_outline, color: scheme.error),
      DownloadStatus.cancelled => Icon(Icons.cancel_outlined,
          color: scheme.onSurfaceVariant),
    };
  }
}


String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
