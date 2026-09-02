/// 搜索页的「全网」模式（2026-09-02 用户需求）：
/// - 条件类型对齐 asmr.one：关键词 / RJ 号 / 标签 / 声优 / 社团；
/// - 标签/声优/社团为「选择器」：拉全表（按作品数排序）供点选（kikoflu 同款）；
/// - 在线结果中本地已有的作品显示「本地」徽章。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/online_models.dart';
import '../providers/library_provider.dart';
import '../providers/mirror_provider.dart';
import '../utils/ui_tokens.dart';
import 'online_work_detail_screen.dart';
import 'work_detail_screen.dart';

class OnlineSearchSection extends StatefulWidget {
  const OnlineSearchSection({
    super.key,
    required this.conditionType,
    required this.query,
  });

  /// 与本地搜索共享的条件类型（2=标签 3=社团 4=声优）。
  final int conditionType;
  final String query;

  @override
  State<OnlineSearchSection> createState() => _OnlineSearchSectionState();
}

class _OnlineSearchSectionState extends State<OnlineSearchSection> {
  List<OnlineWork> _results = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_isPickerMode) {
      _loadPicker();
    } else if (widget.query.isNotEmpty) {
      _search();
    }
  }

  @override
  void didUpdateWidget(OnlineSearchSection old) {
    super.didUpdateWidget(old);
    if (old.conditionType != widget.conditionType) {
      _results = const [];
      _error = null;
      if (_isPickerMode) {
        _loadPicker();
      } else if (widget.query.isNotEmpty) {
        _search();
      }
    } else if (old.query != widget.query && !_isPickerMode) {
      _search();
    }
  }

  /// 标签/声优/社团 → 选择器模式（全表点选，kikoflu 同款交互）。
  bool get _isPickerMode =>
      widget.conditionType == 2 || widget.conditionType == 3 || widget.conditionType == 4;

  List<Map<String, dynamic>> _pickerItems = const [];
  bool _pickerLoading = false;

  Future<void> _loadPicker() async {
    setState(() => _pickerLoading = true);
    try {
      final mirror = context.read<MirrorProvider>();
      final items = switch (widget.conditionType) {
        2 => await mirror.api.getAllTags(),
        3 => await mirror.api.getAllCircles(),
        _ => await mirror.api.getAllVas(),
      };
      if (!mounted) return;
      setState(() {
        _pickerItems = items;
        _pickerLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _pickerLoading = false;
      });
    }
  }

  Future<void> _search() async {
    if (widget.query.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final mirror = context.read<MirrorProvider>();
      final q = widget.query;
      List<OnlineWork> works;
      if (widget.conditionType == 1 &&
          RegExp(r'^\d{5,8}$').hasMatch(q)) {
        // 纯数字 → RJ 号搜索。
        works = await mirror.api.searchWorks('RJ$q', pageSize: 40);
      } else {
        works = await mirror.api.searchWorks(q, pageSize: 40);
      }
      if (!mounted) return;
      setState(() {
        _results = works;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// 选择器点选 → 按标签/社团/CV 检索作品。
  Future<void> _pickAndSearch(Map<String, dynamic> item) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final mirror = context.read<MirrorProvider>();
      List<OnlineWork> works;
      switch (widget.conditionType) {
        case 2: // 标签：标签名作关键词。
          works = await mirror.api
              .searchWorks(item['name'] as String, pageSize: 40);
        case 3: // 社团：id 检索。
          works = await mirror.api.getCircleWorksPage(
              item['id'] as int, 1,
              pageSize: 40);
        default: // 声优：id 检索。
          works = await mirror.api.getVaWorks(
              item['id'] as String,
              pageSize: 40);
      }
      if (!mounted) return;
      setState(() {
        _results = works;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final library = context.watch<LibraryProvider>();
    // 本地已有 RJ 集合（徽章判定）。
    final localRjs = library.works
        .map((w) => w.rjCode?.toUpperCase())
        .whereType<String>()
        .toSet();

    if (_pickerLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(UiSpacing.large),
        child: Text('加载失败：$_error', style: TextStyle(color: scheme.error)),
      ));
    }

    // 选择器模式：全部标签/声优/社团列表。
    if (_isPickerMode && _results.isEmpty && !_loading) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: UiSpacing.small),
        itemCount: _pickerItems.length,
        itemBuilder: (context, index) {
          final item = _pickerItems[index];
          final name = item['name'] as String? ?? '';
          final count = item['count'] as int? ?? 0;
          return ListTile(
            dense: true,
            title: Text(name, maxLines: 1),
            trailing: Text('$count',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
            onTap: () => _pickAndSearch(item),
          );
        },
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(widget.query.isEmpty ? '输入关键词搜索全网' : '未搜到作品',
            style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(UiSpacing.small),
      itemCount: _results.length,
      itemBuilder: (context, index) =>
          _OnlineResultTile(work: _results[index], localRjs: localRjs),
    );
  }
}

/// 在线搜索结果行（封面 + 标题 + 元信息 + 本地徽章）。
class _OnlineResultTile extends StatelessWidget {
  const _OnlineResultTile({required this.work, required this.localRjs});

  final OnlineWork work;
  final Set<String> localRjs;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mirror = context.read<MirrorProvider>();
    final rjCode = 'RJ${work.id}'.toUpperCase();
    final hasLocal = localRjs.contains(rjCode);

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: UiSpacing.medium),
      leading: AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(UiRadii.control),
          child: Image.network(
            mirror.api.coverUrl(work.id),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
                color: scheme.surfaceContainerHighest,
                child: Icon(Icons.album, color: scheme.onSurfaceVariant)),
          ),
        ),
      ),
      title: Row(
        children: [
          if (hasLocal) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('本地',
                  style: TextStyle(
                      fontSize: 10,
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: UiSpacing.xSmall),
          ],
          Expanded(
            child: Text(work.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
      subtitle: Text(
        [
          if (work.circleName != null) work.circleName!,
          if (work.release != null)
            '${work.release!.year}-${work.release!.month.toString().padLeft(2, '0')}',
          if (work.dlCount != null) '${work.dlCount} 销量',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
      onTap: () {
        // 本地已有 → 进本地详情；否则在线详情。
        if (hasLocal) {
          final library = context.read<LibraryProvider>();
          final local = library.works
              .firstWhere((w) => w.rjCode?.toUpperCase() == rjCode);
          Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => WorkDetailScreen(work: local)));
        } else {
          Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => OnlineWorkDetailScreen(work: work)));
        }
      },
    );
  }
}
