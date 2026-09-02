import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

import '../models/online_models.dart';
import '../models/work.dart';
import '../providers/library_provider.dart';
import '../providers/mirror_provider.dart';
import '../utils/ui_tokens.dart';
import 'online_work_detail_screen.dart';
import 'work_detail_screen.dart';

/// 标签筛选页（用户需求 2026-09-01：点标签直接过滤）。
///
/// 双模式：
/// - 本地：works.tags（metadata.json）+ NetMeta.netTags 内存过滤 → 本地作品网格；
/// - 在线：asmr.one 关键词搜索（标签名）→ 在线作品网格。
class TagFilterScreen extends StatefulWidget {
  const TagFilterScreen({super.key, required this.tag, this.online = false});

  final String tag;
  final bool online;

  @override
  State<TagFilterScreen> createState() => _TagFilterScreenState();
}

class _TagFilterScreenState extends State<TagFilterScreen> {
  List<Work> _localWorks = const [];
  List<OnlineWork> _onlineWorks = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.online) {
      try {
        final works =
            await context.read<MirrorProvider>().api.searchWorks(widget.tag);
        if (mounted) {
          setState(() {
            _onlineWorks = works;
            _loading = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }

    // 本地模式：works.tags + NetMeta.netTags。
    final library = context.read<LibraryProvider>();
    final db = library.database;
    final result = <Work>[];
    for (final work in library.works) {
      var hit = work.tags.contains(widget.tag);
      if (!hit && db != null && work.rjCode != null) {
        final meta = await db.queryNetMeta(work.rjCode!);
        hit = meta?.netTags.contains(widget.tag) ?? false;
      }
      if (hit) result.add(work);
    }
    if (mounted) {
      setState(() {
        _localWorks = result;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = widget.online ? _onlineWorks.length : _localWorks.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('标签：${widget.tag}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : count == 0
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.label_off_outlined,
                          size: 56, color: scheme.onSurfaceVariant),
                      const SizedBox(height: UiSpacing.medium),
                      Text(
                        widget.online ? 'asmr.one 未搜到该标签作品' : '本地库没有该标签的作品',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              : MasonryGridView.count(
                  padding: const EdgeInsets.all(UiSpacing.small),
                  crossAxisCount: 2,
                  mainAxisSpacing: UiSpacing.small,
                  crossAxisSpacing: UiSpacing.small,
                  itemCount: count,
                  itemBuilder: (context, index) => widget.online
                      ? _OnlineTagCard(work: _onlineWorks[index])
                      : _LocalTagCard(work: _localWorks[index]),
                ),
    );
  }
}

class _LocalTagCard extends StatelessWidget {
  const _LocalTagCard({required this.work});

  final Work work;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
            builder: (context) => WorkDetailScreen(work: work)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Container(
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(UiRadii.control),
              ),
              child: work.coverPath != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(UiRadii.control),
                      child: Image.file(
                        File(work.coverPath!),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (_, _, _) =>
                            const SizedBox.shrink(),
                      ),
                    )
                  : Center(
                      child: Text(work.rjCode ?? '',
                          style: TextStyle(
                              color: scheme.onPrimaryContainer,
                              fontSize: 12)),
                    ),
            ),
          ),
          const SizedBox(height: UiSpacing.xSmall),
          Text(work.title,
              maxLines: null,
              style: const TextStyle(
                  fontSize: 13, height: 1.3, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _OnlineTagCard extends StatelessWidget {
  const _OnlineTagCard({required this.work});

  final OnlineWork work;

  @override
  Widget build(BuildContext context) {
    final mirror = context.read<MirrorProvider>();
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
            builder: (context) => OnlineWorkDetailScreen(work: work)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(UiRadii.control),
              child: CachedNetworkImage(
                imageUrl: mirror.api.coverUrl(work.id),
                fit: BoxFit.cover,
                width: double.infinity,
                placeholder: (context, url) =>
                    Container(color: scheme.surfaceContainerHighest),
                errorWidget: (context, url, error) => Container(
                    color: scheme.surfaceContainerHighest,
                    child: Icon(Icons.album,
                        color: scheme.onSurfaceVariant)),
              ),
            ),
          ),
          const SizedBox(height: UiSpacing.xSmall),
          Text(work.title,
              maxLines: null,
              style: const TextStyle(
                  fontSize: 13, height: 1.3, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
