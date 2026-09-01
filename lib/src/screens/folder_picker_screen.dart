import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/library_provider.dart';
import '../services/storage_permission.dart';
import '../utils/ui_tokens.dart';

/// 扫描根目录选择器（M2：文件路径直访版；SAF 持久化 URI 随后续版本升级）。
///
/// 从 /storage/emulated/0 开始浏览目录树，选择当前目录作为扫描根目录；
/// 选中后自动添加根目录并触发扫描。
class FolderPickerScreen extends StatefulWidget {
  const FolderPickerScreen({super.key});

  @override
  State<FolderPickerScreen> createState() => _FolderPickerScreenState();
}

class _FolderPickerScreenState extends State<FolderPickerScreen> {
  String _currentPath = defaultStorageRoot;
  List<Directory> _subdirs = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() => _error = null);
    // 进入选择器前确保存储权限已授予。
    final granted = await ensureStoragePermission();
    if (!granted) {
      setState(() => _error = '未获得存储访问权限\n请在系统设置中授予"所有文件访问"权限');
      return;
    }
    try {
      final dir = Directory(_currentPath);
      final exists = await dir.exists();
      if (!exists) {
        // 设备无该路径时回退到 /storage。
        _currentPath = '/storage';
      }
      final entries = await Directory(_currentPath)
          .list(followLinks: false)
          .where((entity) => entity is Directory)
          .map((entity) => entity as Directory)
          .where((dir) =>
              !dir.path.split('/').last.startsWith('.'))
          .toList();
      entries.sort((a, b) => a.path.compareTo(b.path));
      setState(() => _subdirs = entries);
    } catch (e) {
      setState(() => _error = '无法读取目录：$e');
    }
  }

  void _enter(Directory dir) {
    _currentPath = dir.path;
    _open();
  }

  void _goUp() {
    if (_currentPath == defaultStorageRoot || _currentPath == '/storage') {
      return;
    }
    _currentPath = Directory(_currentPath).parent.path;
    _open();
  }

  Future<void> _selectCurrent() async {
    final library = context.read<LibraryProvider>();
    final added = await library.addRoot(_currentPath);
    if (!mounted) return;
    if (!added) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(library.roots.contains(_currentPath)
              ? '该目录已在扫描根目录中'
              : '目录不可用'),
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(32),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: UiSpacing.medium),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _currentPath,
                style: UiTextStyles.supporting.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
      body: _error != null
          ? Center(
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
            )
          : ListView.builder(
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
}
