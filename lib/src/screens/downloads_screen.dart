import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/download_provider.dart';
import '../services/download_service.dart';
import '../utils/ui_tokens.dart';

/// 下载管理 Tab（2026-09-03 M3：分流 进行中/已完成/全部）。
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

enum _DlFilter { active, done, all }

class _DownloadsScreenState extends State<DownloadsScreen> {
  _DlFilter _filter = _DlFilter.active;

  List<DownloadTask> _filtered(List<DownloadTask> tasks) {
    switch (_filter) {
      case _DlFilter.active:
        return tasks.where((t) =>
                t.status == DownloadStatus.queued ||
                t.status == DownloadStatus.running)
            .toList();
      case _DlFilter.done:
        return tasks.where((t) => t.status == DownloadStatus.completed).toList();
      case _DlFilter.all:
        return tasks.toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloads = context.watch<DownloadProvider>();
    final tasks = downloads.tasks;
    final list = _filtered(tasks);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('下载管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: '清理已完成',
            onPressed: tasks.isEmpty ? null : () => downloads.clearFinished(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                UiSpacing.medium, UiSpacing.small, UiSpacing.medium, 0),
            child: SegmentedButton<_DlFilter>(
              segments: const [
                ButtonSegment(value: _DlFilter.active, label: Text('进行中')),
                ButtonSegment(value: _DlFilter.done, label: Text('已完成')),
                ButtonSegment(value: _DlFilter.all, label: Text('全部')),
              ],
              selected: {_filter},
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              onSelectionChanged: (v) => setState(() => _filter = v.first),
            ),
          ),
          Expanded(
            child: tasks.isEmpty
                ? Center(
                    child: Text(
                      '暂无下载任务\n在线作品详情页点「下载全部」加入队列',
                      textAlign: TextAlign.center,
                      style: UiTextStyles.supporting
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                  )
                : list.isEmpty
                    ? Center(
                        child: Text('该分组下暂无任务',
                            style: TextStyle(
                                color: scheme.onSurfaceVariant)),
                      )
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (context, index) =>
                            _DownloadTaskTile(task: list[index]),
                      ),
          ),
        ],
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
    final isDone = task.status == DownloadStatus.completed;

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
          Row(
            children: [
              Flexible(
                child: Text(
                  '${task.workDirName} · $statusText',
                  style: UiTextStyles.supporting
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              if (isDone)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('✓ 已保存',
                      style: TextStyle(
                          fontSize: 10,
                          color: scheme.onPrimaryContainer)),
                ),
            ],
          ),
          if (task.status == DownloadStatus.running)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(
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
    final icon = switch (status) {
      DownloadStatus.queued => Icons.schedule,
      DownloadStatus.running => Icons.downloading,
      DownloadStatus.completed => Icons.check_circle,
      DownloadStatus.failed => Icons.error_outline,
      DownloadStatus.cancelled => Icons.cancel_outlined,
    };
    final color = switch (status) {
      DownloadStatus.completed => Colors.green.shade600,
      DownloadStatus.failed => scheme.error,
      DownloadStatus.cancelled => scheme.onSurfaceVariant,
      _ => scheme.primary,
    };
    return Icon(icon, size: 26, color: color);
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '\$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
