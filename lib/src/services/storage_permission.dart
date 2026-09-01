import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// 存储权限助手（PRD §7：优先 SAF；M2 为文件路径直访版）。
///
/// - Android ≤ 12：READ_EXTERNAL_STORAGE（MuMu 模拟器等环境直接授予）；
/// - Android 13+：READ_EXTERNAL_STORAGE 不再授予 → 请求
///   MANAGE_EXTERNAL_STORAGE（所有文件访问，本地播放器通行做法）。
Future<bool> ensureStoragePermission() async {
  if (!Platform.isAndroid) return true;

  var status = await Permission.storage.status;
  if (status.isGranted) return true;
  status = await Permission.storage.request();
  if (status.isGranted) return true;

  // Android 13+ 路径。
  status = await Permission.manageExternalStorage.status;
  if (status.isGranted) return true;
  final result = await Permission.manageExternalStorage.request();
  return result.isGranted;
}

/// Android 外置存储根（目录选择器起始位置）。
const String defaultStorageRoot = '/storage/emulated/0';
