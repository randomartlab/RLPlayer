import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import '../widgets/mini_player_visibility.dart';
import 'package:provider/provider.dart';

import '../providers/library_provider.dart';
import '../services/storage_permission.dart';
import '../utils/ui_tokens.dart';

/// MuMu 等模拟器的共享文件夹挂载点（9p，不走 Android FUSE 仲裁，
/// 对任意 App uid 可读写）。Mac 侧对应「MuMu 共享文件夹」。
const String mumuSharedPath = '/mnt/shared/MuMu12Shared';

/// 扫描根目录选择器（M2：文件路径直访版；SAF 持久化 URI 随后续版本升级）。
///
/// 模拟器兼容：部分模拟器（MuMu Mac）的标准共享存储 /storage/emulated/0
/// 受 FUSE 限制对 App 不可见；此类环境自动回退到共享文件夹挂载点。
class FolderPickerScreen extends StatefulWidget {
  const FolderPickerScreen({super.key});

  @override
  State<FolderPickerScreen> createState() => _FolderPickerScreenState();
}

class _FolderPickerScreenState extends State<FolderPickerScreen> {
  String _currentPath = defaultStorageRoot;
  List<Directory> _subdirs = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // 本页底部有主操作按钮（设为扫描根目录）→ 隐藏全局迷你条，
    // 防止遮挡确认按钮（2026-09-02 用户反馈）。
    MiniPlayerController.hold();
    _detectInitialPath();
  }

  @override
  void dispose() {
    MiniPlayerController.release();
    super.dispose();
  }

  /// 初始路径探测：优先 MuMu 共享文件夹（模拟器环境），否则标准存储根。
  void _detectInitialPath() {
    try {
      final shared = Directory(mumuSharedPath);
      if (shared.existsSync() && shared.listSync(followLinks: false).isNotEmpty) {
        _currentPath = mumuSharedPath;
      }
    } catch (_) {
      // 共享挂载不存在（真机环境），用默认根目录。
    }
    _open();
  }

  Future<void> _open() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    // 进入选择器前确保对当前目录有实际访问权限（实测而非权限标志位）。
    final granted = await ensureStorageAccess(_currentPath);
    if (!granted && !Directory(_currentPath).existsSync()) {
      setState(() {
        _error = '无法读取存储目录\n请在系统设置中授予「所有文件访问」权限';
        _loading = false;
      });
      return;
    }
    try {
      final entries = <Directory>[];
      await for (final entity
          in Directory(_currentPath).list(followLinks: false)) {
        if (entity is! Directory) continue;
        if (entity.path.split('/').last.startsWith('.')) continue;
        entries.add(entity);
      }
      entries.sort((a, b) => a.path.compareTo(b.path));
      debugPrint('[KikoPick] 打开 $_currentPath → ${entries.length} 个子目录');
      setState(() {
        _subdirs = entries;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[KikoPick] 读取失败 $_currentPath: $e');
      setState(() {
        _error = '无法读取目录：$e';
        _loading = false;
      });
    }
  }

  void _enter(Directory dir) {
    debugPrint('[KikoPick] 进入: ${dir.path}');
    _currentPath = dir.path;
    _open();
  }

  void _goUp() {
    final parent = Directory(_currentPath).parent.path;
    // 不越过共享挂载点与存储根。
    if (parent.length < _currentPath.length &&
        !_currentPath.startsWith('/mnt/shared') &&
        !_currentPath.startsWith(defaultStorageRoot)) {
      _currentPath = parent;
      _open();
    }
  }

  Future<void> _selectCurrent() async {
    final library = context.read<LibraryProvider>();
    final added = await library.addRoot(_currentPath);
    if (!mounted) return;
    if (!added) {
      final alreadyExists = library.roots.contains(_currentPath);
      if (alreadyExists) {
        // 已存在的根目录 → 直接触发重扫（避免"加了目录却不扫描"的死角）。
        unawaited(library.rescan());
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(alreadyExists ? '该目录已在扫描根目录中，开始重新扫描' : '目录不可用'),
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.of(context).pop();
      return;
    }
    unawaited(library.rescan());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已添加 $_currentPath，开始扫描'),
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择扫描根目录'),
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_upward),
            tooltip: '上一级',
            onPressed: _goUp,
          ),
        ],
      ),
      // 路径栏 + 快捷入口移到 body 顶部（大字体下固定 84 高的
      // AppBar bottom 会溢出挤压列表，实机反馈 2026-09-02：
      // 80 字体缩放下目录列表被挤没且无法上拉）。
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                UiSpacing.medium, UiSpacing.small, UiSpacing.medium, 0),
            child: Text(
              _currentPath,
              style: UiTextStyles.supporting.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: UiSpacing.small, vertical: UiSpacing.xSmall),
            child: Wrap(
              spacing: UiSpacing.small,
              runSpacing: UiSpacing.xSmall,
              children: [
                _QuickChip(
                  icon: Icons.folder_shared_outlined,
                  label: '共享文件夹',
                  active: _currentPath == mumuSharedPath,
                  onTap: () {
                    _currentPath = mumuSharedPath;
                    _open();
                  },
                ),
                _QuickChip(
                  icon: Icons.smartphone,
                  label: '内部存储',
                  active: _currentPath == defaultStorageRoot,
                  onTap: () {
                    _currentPath = defaultStorageRoot;
                    _open();
                  },
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(context)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(UiSpacing.medium),
          child: FilledButton.icon(
            onPressed: _selectCurrent,
            icon: const Icon(Icons.add),
            label: const Text('将此目录设为扫描根目录'),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(UiSpacing.xLarge),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: UiSpacing.medium),
              FilledButton(
                onPressed: _open,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_subdirs.isEmpty) {
      // 空列表引导：模拟器环境下标准存储可能对 App 不可见。
      final isStandardRoot = _currentPath == defaultStorageRoot;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(UiSpacing.xLarge),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.folder_off_outlined,
                  size: 48, color: scheme.onSurfaceVariant),
              const SizedBox(height: UiSpacing.medium),
              Text(
                isStandardRoot
                    ? '此目录对应用不可见（模拟器存储限制）\n试试上方「共享文件夹」，或直接扫描当前目录'
                    : '此目录为空',
                style: UiTextStyles.supporting
                    .copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _subdirs.length,
      itemBuilder: (context, index) {
        final dir = _subdirs[index];
        final name = dir.path.split('/').last;
        return ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text(name),
          onTap: () => _enter(dir),
        );
      },
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ActionChip(
      avatar: Icon(icon,
          size: UiIconSize.small,
          color: active ? scheme.onPrimary : scheme.primary),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: active ? scheme.primary : null,
      labelStyle: TextStyle(color: active ? scheme.onPrimary : null),
      onPressed: onTap,
    );
  }
}
