/// 「我的-喜欢」Tab（2026-09-03 C）：本机独立喜欢（♥，不与 one 站收藏混）。
/// 有本地版本 → 打开本地详情；无本地 → 以 RJ 打开在线详情。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/online_models.dart';
import '../models/work.dart';
import '../providers/library_provider.dart';
import '../utils/ui_tokens.dart';
import 'online_work_detail_screen.dart';
import 'work_detail_screen.dart';

class LikedTab extends StatelessWidget {
  const LikedTab({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final library = context.watch<LibraryProvider>();
    final liked = library.likedRjCodes.toList();

    if (liked.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(UiSpacing.xLarge),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.favorite_border,
                  size: 56, color: scheme.onSurfaceVariant),
              const SizedBox(height: UiSpacing.medium),
              Text('还没有喜欢的作品',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: UiSpacing.xSmall),
              Text('作品详情页点 ♥ 标记；这是本机标记，不与账号收藏混淆',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    final byRj = <String, Work>{};
    for (final w in library.works) {
      final rj = w.rjCode;
      if (rj != null) byRj[rj.toUpperCase()] = w;
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: UiSpacing.small),
      itemCount: liked.length,
      itemBuilder: (context, index) {
        final rj = liked[index];
        final local = byRj[rj];
        final title =
            local?.title ?? library.likedTitles[rj] ?? rj;
        final numeric = int.tryParse(
            rj.replaceFirst(RegExp(r'^(RJ|BJ|VJ)', caseSensitive: false), ''));
        return ListTile(
          leading: local?.coverPath != null
              ? SizedBox(
                  width: 46,
                  height: 46,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(
                      File(local!.coverPath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Icon(Icons.album,
                          color: scheme.onSurfaceVariant),
                    ),
                  ),
                )
              : CircleAvatar(
                  backgroundColor: scheme.surfaceContainerHighest,
                  child: Icon(Icons.album,
                      size: 20, color: scheme.onSurfaceVariant),
                ),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [rj, if (local != null) '本地' else '在线'].join(' · '),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.favorite, color: Colors.pinkAccent),
            tooltip: '取消喜欢',
            onPressed: () =>
                library.toggleLike(rj, library.likedTitles[rj] ?? rj),
          ),
          onTap: () {
            if (local != null) {
              Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => WorkDetailScreen(work: local)));
            } else if (numeric != null) {
              Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => OnlineWorkDetailScreen(
                      work: OnlineWork(id: numeric, title: title))));
            }
          },
        );
      },
    );
  }
}
