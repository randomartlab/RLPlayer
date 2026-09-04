/// 元数据预热器（2026-09-04）：扫描/启动后自动为缺失网络元数据的本地
/// RJ 排队拉取（asmr.one/DLsite），让本地标签/CV/社团筛选无需逐一点开
/// 详情即有数据。
///
/// - 挂载在应用根（MainScreen 外层），监听 LibraryProvider 变化
/// - 仅在「非扫描中且 works 已加载」时触发，每个 RJ 本次会话 20 分钟内
///   只尝试一次；逐条串行带 120ms 间隔，避免抢带宽
/// - 不阻塞 UI；无 RJ / 已缓存 / noResult 的作品自动跳过（getMeta 内）
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/library_provider.dart';
import '../providers/mirror_provider.dart';
import '../services/net_meta_service.dart';

class MetaWarmer extends StatefulWidget {
  const MetaWarmer({super.key, required this.child});

  final Widget child;

  @override
  State<MetaWarmer> createState() => _MetaWarmerState();
}

class _MetaWarmerState extends State<MetaWarmer> {
  Timer? _debounce;
  bool _running = false;
  final Map<String, DateTime> _lastAttempt = {};
  bool _subscribed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) => _schedule());
    // 监听变化（扫描完成 / reload 完成均会 notify）。
    if (!_subscribed) {
      context.read<LibraryProvider>().addListener(_onLibrary);
      _subscribed = true;
    }
  }

  void _onLibrary() {
    _schedule();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 900), () {
      _warmOnce();
    });
  }

  Future<void> _warmOnce() async {
    if (_running) return;
    final library = context.read<LibraryProvider>();
    if (library.scanning) return;
    final metaService = context.read<NetMetaService>();
    context.read<MirrorProvider>(); // 确保镜像就绪后取 metaService
    final rjs = <String>[];
    for (final w in library.works) {
      final rj = w.rjCode;
      if (rj == null || rj.isEmpty) continue;
      final last = _lastAttempt[rj];
      if (last != null &&
          DateTime.now().difference(last).inMinutes < 20) {
        continue;
      }
      rjs.add(rj);
    }
    if (rjs.isEmpty) return;
    _running = true;
    var done = 0;
    try {
      for (final rj in rjs.take(80)) {
        _lastAttempt[rj] = DateTime.now();
        try {
          await metaService.getMeta(rj);
        } catch (_) {
          // 单条失败不阻断后续。
        }
        done++;
        if (done % 5 == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 80));
        }
      }
      // 后台回填（vas/tags/封面）完成 → 刷新列表让筛选条件可见。
      if (mounted && done > 0) {
        await library.reloadWorks();
      }
    } finally {
      _running = false;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_subscribed) {
      context.read<LibraryProvider>().removeListener(_onLibrary);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
