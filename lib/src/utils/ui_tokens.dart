import 'package:flutter/material.dart';

/// 几何设计令牌（KikoFlu `ui_tokens.dart` 像素级移植，UI 规范 §1）。
///
/// 所有页面与组件必须引用令牌，禁止散落硬编码。
abstract final class UiSpacing {
  static const double xSmall = 4;
  static const double small = 8;
  static const double medium = 12;
  static const double large = 16;
  static const double xLarge = 24;
}

abstract final class UiRadii {
  static const double tag = 4;
  static const double control = 8;
  static const double list = 12;
  static const double card = 16;
  static const double capsule = 20;
}

abstract final class UiControlSize {
  static const double compact = 40;
  static const double standard = 48;
  static const double settingsLeading = 52;
  static const double iconButton = 40;
}

abstract final class UiIconSize {
  static const double small = 16;
  static const double standard = 20;
  static const double large = 24;
}

/// 动效令牌（UI 规范 §6：主节奏 180ms easeOutCubic 全局统一）。
abstract final class UiMotion {
  /// 主节奏：按钮、尺寸切换、AnimatedSize。
  static const Duration primary = Duration(milliseconds: 180);

  /// 曲线族：入场 easeOutCubic / 往复 easeInOut / 退场 easeInCubic。
  static const Curve entryCurve = Curves.easeOutCubic;
  static const Curve reversalsCurve = Curves.easeInOut;
  static const Curve exitCurve = Curves.easeInCubic;

  /// 歌词滚动定位（含 seek 联动，PRD §5.6.4）。
  static const Duration lyricScroll = Duration(milliseconds: 300);
  static const Curve lyricScrollCurve = Curves.easeOut;

  /// 迷你播放条 → 全屏播放器路由转场（PRD §5.3）。
  static const Duration playerRoute = Duration(milliseconds: 400);

  /// 歌词换行高亮淡入。
  static const Duration lyricFade = Duration(milliseconds: 200);
}

/// 普通控件的文字角色令牌；颜色与字体继承主题（UI 规范 §1.5）。
abstract final class UiTextStyles {
  static const TextStyle pageTitle = TextStyle(fontSize: 18);
  static const TextStyle supporting = TextStyle(fontSize: 12, height: 1.5);
  static const TextStyle filterChipLabel = TextStyle(fontSize: 12);
}
