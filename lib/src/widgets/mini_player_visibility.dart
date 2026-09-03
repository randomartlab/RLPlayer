/// 迷你条显隐控制器（2026-09-02 重新设计）。
///
/// 全局迷你条由 MaterialApp.builder 的 overlay 渲染（覆盖所有路由）。
/// 为防止遮住「底部主操作按钮」类页面（如扫描根目录选择器的
/// 「设为扫描根目录」），页面在拥有底部关键操作时通过
/// [MiniPlayerController.hold] 暂时隐藏迷你条（引用计数，dispose 释放）。
library;

import 'package:flutter/foundation.dart';

/// 全局迷你条控制器。
///
/// 规则：
/// - 主页（路由深度 0）：主页自身在底部导航栏渲染迷你条，overlay 不重复；
/// - 全屏播放页：由 AudioPlayerScreen 生命周期隐藏；
/// - 带底部主按钮的页面（FolderPicker 等）：调用 [hold] / [release]。
class MiniPlayerController {
  MiniPlayerController._();

  /// 隐藏计数（>0 时全局迷你条隐藏）。引用计数便于嵌套页面。
  static final ValueNotifier<int> holdCount = ValueNotifier<int>(0);

  /// 进入隐藏区（如页面 initState）。
  static void hold() {
    holdCount.value++;
  }

  /// 离开隐藏区（如页面 dispose）。
  static void release() {
    if (holdCount.value > 0) holdCount.value--;
  }
}
