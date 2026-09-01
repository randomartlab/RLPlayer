import 'package:flutter/material.dart';

import '../utils/ui_tokens.dart';

/// Tab3 我的页（M1 骨架；M4 里程碑实现历史 / 播放列表 / 本地库 / 字幕库，PRD §5.8）。
class MyScreen extends StatelessWidget {
  const MyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('我的', style: UiTextStyles.pageTitle),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_border,
                size: 64, color: scheme.onSurfaceVariant),
            const SizedBox(height: UiSpacing.medium),
            Text(
              '我的（M4 里程碑）',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: UiSpacing.xSmall),
            Text(
              '历史 / 播放列表 / 本地库 / 字幕库',
              style: UiTextStyles.supporting
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
