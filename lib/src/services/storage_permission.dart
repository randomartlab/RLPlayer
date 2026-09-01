import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// 存储权限助手（PRD §7：优先 SAF；M2 为文件路径直访版）。
///
/// Android 11+ 分区存储下，仅授予 READ_EXTERNAL_STORAGE 时 App 往往
/// **能列出 /storage/emulated/0 顶层但无法递归遍历子目录**（FUSE 按
/// MediaStore 可见性仲裁）。因此不能只看权限标志位，必须实测目录可读性；
/// 不可读时引导用户授予 MANAGE_EXTERNAL_STORAGE（所有文件访问）。

/// 验证 App 是否真的能列出某目录（权限标志位不可靠）。
Future<bool> canListDirectory(String path) async {
  try {
    await for (final _ in Directory(path).list(followLinks: false)) {
      break; // 只需确认能拿到第一个条目
    }
    return true;
  } catch (e) {
    debugPrint('canListDirectory($path) 失败：$e');
    return false;
  }
}

/// 确保对 [path] 有实际可读的目录访问权限。
///
/// 顺序：实测可读 → 请求 READ_EXTERNAL_STORAGE → 请求
/// MANAGE_EXTERNAL_STORAGE（所有文件访问，Android 11+ 必需）。
Future<bool> ensureStorageAccess(String path) async {
  if (!Platform.isAndroid) return true;

  if (await canListDirectory(path)) return true;

  // 低版本（≤ Android 10）：READ_EXTERNAL_STORAGE 即完整访问。
  if (await Permission.storage.request().isGranted &&
      await canListDirectory(path)) {
    return true;
  }

  // Android 11+：需要所有文件访问。
  if (await Permission.manageExternalStorage.request().isGranted &&
      await canListDirectory(path)) {
    return true;
  }

  return canListDirectory(path);
}

/// 目录选择器进入前的权限校验（实测 /storage/emulated/0 可读性）。
Future<bool> ensureStoragePermission() => ensureStorageAccess(defaultStorageRoot);

/// Android 外置存储根（目录选择器起始位置）。
const String defaultStorageRoot = '/storage/emulated/0';
