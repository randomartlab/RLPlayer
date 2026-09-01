import 'package:flutter/material.dart';

import '../utils/ui_tokens.dart';

/// Tab2 搜索页（M1 骨架；M4 里程碑实现本地库多条件搜索，PRD §5.7）。
class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('搜索', style: UiTextStyles.pageTitle),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: scheme.onSurfaceVariant),
            const SizedBox(height: UiSpacing.medium),
            Text(
              '搜索（M4 里程碑）',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: UiSpacing.xSmall),
            Text(
              '关键词 / RJ 号 / 标签 / 社团 / 声优 五条件本地搜索',
              style: UiTextStyles.supporting
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
