import 'package:flutter/foundation.dart';

import 'package:flutter_overlay_window/flutter_overlay_window.dart';

/// 悬浮桌面歌词服务（M5，PRD §5.6.7）。
///
/// - 系统悬浮窗（SYSTEM_ALERT_WINDOW）+ 可拖动；
/// - 歌词文本经 isolate 消息通道（shareData/overlayListener）推送；
/// - 未授权时引导系统设置页；关闭立即移除。
class FloatingLyricService {
  bool _showing = false;
  bool get showing => _showing;

  /// 开启悬浮窗；未授权返回 false（调用方引导授权后重试）。
  Future<bool> show() async {
    try {
      if (!await FlutterOverlayWindow.isPermissionGranted()) {
        final granted = await FlutterOverlayWindow.requestPermission();
        if (granted != true) return false;
      }
      await FlutterOverlayWindow.showOverlay(
        height: 120,
        alignment: OverlayAlignment.bottomCenter,
        flag: OverlayFlag.clickThrough, // 点击穿透，不打扰下层 App 操作。
        enableDrag: true,
        overlayTitle: 'KikoLocal 歌词',
        positionGravity: PositionGravity.none,
      );
      _showing = true;
      debugPrint('[Overlay] 悬浮歌词已开启');
      return true;
    } catch (e) {
      debugPrint('[Overlay] 开启失败: $e');
      return false;
    }
  }

  Future<void> hide() async {
    try {
      await FlutterOverlayWindow.closeOverlay();
    } catch (_) {}
    _showing = false;
    debugPrint('[Overlay] 悬浮歌词已关闭');
  }

  /// 推送当前歌词行（null = 暂停/无歌词态）。
  Future<void> pushLyric(String? text) async {
    if (!_showing) return;
    try {
      await FlutterOverlayWindow.shareData(text ?? '');
    } catch (_) {
      // overlay 已死/通道异常：忽略。
    }
  }
}
