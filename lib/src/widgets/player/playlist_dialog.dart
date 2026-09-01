import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/audio_provider.dart';
import '../../utils/ui_tokens.dart';

/// 播放队列弹窗（PRD §5.6.5 / UI 规范 §4.6）。
///
/// - 圆角 18dp，最大高度 70% 屏高；
/// - ReorderableListView 长按拖拽排序；
/// - 左滑删除；
/// - 当前播放行高亮（primary 色 + 音符图标）；
/// - 点击行跳播。
Future<void> showPlaylistDialog(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.7,
    ),
    builder: (context) => const _PlaylistSheet(),
  );
}

class _PlaylistSheet extends StatelessWidget {
  const _PlaylistSheet();

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioPlayerProvider>();
    final scheme = Theme.of(context).colorScheme;
    final queue = audio.queue;
    final currentId = audio.currentTrack?.id;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(UiSpacing.medium),
          child: Row(
            children: [
              Icon(Icons.queue_music, color: scheme.primary),
              const SizedBox(width: UiSpacing.small),
              Expanded(
                child: Text('播放队列（${queue.length}）',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ),
        if (queue.isEmpty)
          const Padding(
            padding: EdgeInsets.all(UiSpacing.xLarge),
            child: Text('队列为空'),
          )
        else
          Flexible(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: UiSpacing.large),
              itemCount: queue.length,
              onReorderItem: (oldIndex, newIndex) =>
                  audio.reorderQueue(oldIndex, newIndex),
              itemBuilder: (context, index) {
                final track = queue[index];
                final isCurrent = track.id == currentId;
                return Dismissible(
                  key: Key('queue_${track.id}_$index'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: scheme.errorContainer,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: UiSpacing.large),
                    child: Icon(Icons.delete_outline,
                        color: scheme.onErrorContainer),
                  ),
                  onDismissed: (_) => audio.removeFromQueue(index),
                  child: ListTile(
                    dense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: UiSpacing.medium),
                    leading: isCurrent
                        ? Icon(Icons.music_note, color: scheme.primary)
                        : Text('$index',
                            style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 13)),
                    title: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        color: isCurrent ? scheme.primary : null,
                        fontWeight:
                            isCurrent ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    subtitle: track.artist != null
                        ? Text(track.artist!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12))
                        : null,
                    trailing: ReorderableDragStartListener(
                      index: index,
                      child: Icon(Icons.drag_handle,
                          size: 20, color: scheme.onSurfaceVariant),
                    ),
                    onTap: isCurrent ? null : () => audio.jumpTo(index),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// 倍速滑杆弹窗（PRD §5.6.3：0.25–2.5 步进 0.25，生效值钳制 0.5–2.0）。
Future<void> showSpeedSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => const _SpeedSheet(),
  );
}

class _SpeedSheet extends StatefulWidget {
  const _SpeedSheet();

  @override
  State<_SpeedSheet> createState() => _SpeedSheetState();
}

class _SpeedSheetState extends State<_SpeedSheet> {
  double _value = 1.0;

  @override
  void initState() {
    super.initState();
    _value = context.read<AudioPlayerProvider>().speed;
  }

  @override
  Widget build(BuildContext context) {
    final audio = context.read<AudioPlayerProvider>();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          UiSpacing.xLarge, 0, UiSpacing.xLarge, UiSpacing.xLarge),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('播放速度',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w500)),
          const SizedBox(height: UiSpacing.small),
          Row(
            children: [
              const Text('0.5×'),
              Expanded(
                child: Slider(
                  value: _value.clamp(0.5, 2.5),
                  min: 0.5,
                  max: 2.5,
                  divisions: 8,
                  label: '${_value.toStringAsFixed(2)}×',
                  activeColor: scheme.primary,
                  onChanged: (value) =>
                      setState(() => _value = (value * 4).round() / 4),
                  onChangeEnd: (value) => audio.setSpeed(value),
                ),
              ),
              const Text('2.5×'),
            ],
          ),
          const SizedBox(height: UiSpacing.small),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                setState(() => _value = 1.0);
                audio.setSpeed(1.0);
              },
              child: const Text('恢复 1.0×'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 睡眠定时弹窗（PRD §5.6.6：预设时长 / 指定时刻 / 取消）。
Future<void> showSleepTimerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => const _SleepTimerSheet(),
  );
}

class _SleepTimerSheet extends StatelessWidget {
  const _SleepTimerSheet();

  static const _presets = [
    (5, '5 分钟'),
    (10, '10 分钟'),
    (15, '15 分钟'),
    (30, '30 分钟'),
    (60, '1 小时'),
    (120, '2 小时'),
  ];

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioPlayerProvider>();
    final scheme = Theme.of(context).colorScheme;
    final sleepAt = audio.sleepAt;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          UiSpacing.xLarge, 0, UiSpacing.xLarge, UiSpacing.xLarge),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('睡眠定时',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w500)),
          if (sleepAt != null) ...[
            const SizedBox(height: UiSpacing.small),
            Container(
              padding: const EdgeInsets.all(UiSpacing.medium),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(UiRadii.control),
              ),
              child: Row(
                children: [
                  Icon(Icons.bedtime, color: scheme.onPrimaryContainer),
                  const SizedBox(width: UiSpacing.small),
                  Expanded(
                    child: Text(
                      '已设置：${sleepAt.hour.toString().padLeft(2, '0')}:${sleepAt.minute.toString().padLeft(2, '0')} 停止播放',
                      style:
                          TextStyle(color: scheme.onPrimaryContainer),
                    ),
                  ),
                  TextButton(
                    onPressed: () => audio.cancelSleepTimer(),
                    child: const Text('取消定时'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: UiSpacing.medium),
          Text('按时长', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: UiSpacing.xSmall),
          Wrap(
            spacing: UiSpacing.small,
            runSpacing: UiSpacing.small,
            children: [
              for (final (minutes, label) in _presets)
                ActionChip(
                  label: Text(label),
                  onPressed: () {
                    audio.setSleepTimerMinutes(minutes);
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ),
          const SizedBox(height: UiSpacing.medium),
          Text('指定时刻', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: UiSpacing.xSmall),
          OutlinedButton.icon(
            icon: const Icon(Icons.schedule),
            label: const Text('选择时间（24 小时制）'),
            onPressed: () async {
              final now = TimeOfDay.now();
              final picked = await showTimePicker(
                context: context,
                initialTime: now,
              );
              if (picked == null) return;
              audio.setSleepTimerAt(picked.hour, picked.minute);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}
