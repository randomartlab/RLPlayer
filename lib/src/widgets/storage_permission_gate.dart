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

    // 全量权限检查（用户需求 2026-09-02：启动时统一检查所有功能所需权限）。
    final pending = <Permission, String>{};

    // 1. 存储（本地扫描核心）。
    if (!await Permission.storage.status.isGranted) {
      pending[Permission.manageExternalStorage] = '文件访问（本地扫描必需）';
    }
    // 2. 通知（媒体控制通知栏 + Android 13+ 必需）。
    if (!await Permission.notification.status.isGranted) {
      pending[Permission.notification] = '通知（播放控制通知栏）';
    }

    if (pending.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_promptedKey) ?? false) return; // 只引导一次。

    if (!mounted) return;
    final granted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('应用权限'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('以下权限影响对应功能，建议授权：'),
            const SizedBox(height: 12),
            for (final desc in pending.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(desc)),
                  ],
                ),
              ),
          ],
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
      // 逐项请求（manageExternalStorage 跳系统设置页；notification 弹系统弹窗）。
      for (final permission in pending.keys) {
        await permission.request();
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
