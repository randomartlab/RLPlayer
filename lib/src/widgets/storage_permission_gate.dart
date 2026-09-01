import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 首启存储权限引导（实机反馈 2026-09-01：规避本地扫描无结果问题）。
///
/// Android 真机上未授予「所有文件访问」时，Dart File API 看不到共享存储
/// → 扫描静默零结果。首次启动自动检测并引导授权（一次性，拒绝后不再打扰）。
class StoragePermissionGate extends StatefulWidget {
  const StoragePermissionGate({super.key, required this.child});

  final Widget child;

  @override
  State<StoragePermissionGate> createState() => _StoragePermissionGateState();
}

class _StoragePermissionGateState extends State<StoragePermissionGate> {
  static const String _promptedKey = 'storage_permission_prompted';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (!Platform.isAndroid || !mounted) return;

    // 已有读取能力则跳过。
    if (await Permission.storage.status.isGranted) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_promptedKey) ?? false) return; // 只引导一次。

    if (!mounted) return;
    final granted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('授权文件访问'),
        content: const Text(
          'KikoLocal 需要访问设备上的音频文件以扫描本地作品库。\n\n'
          '请在接下来的系统设置中，为 KikoLocal 开启'
          '「允许管理所有文件」权限。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('暂不'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('去授权'),
          ),
        ],
      ),
    );

    await prefs.setBool(_promptedKey, true);

    if (granted == true) {
      // 跳转系统「所有文件访问」设置页；返回后自动重扫由用户操作触发。
      await Permission.manageExternalStorage.request();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
