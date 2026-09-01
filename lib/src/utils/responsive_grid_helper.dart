import 'package:flutter/widgets.dart';

/// 窗口宽度断点（UI 规范 §3.1，KikoFlu `responsive_grid_helper.dart` 移植）。
enum WindowWidthClass {
  compact, // < 600dp（竖屏手机）
  medium, // 600–839dp
  expanded, // 840–1199dp
  large, // ≥ 1200dp
}

class ResponsiveGridHelper {
  const ResponsiveGridHelper._({
    required this.widthClass,
    required this.largeGridColumns,
    required this.smallGridColumns,
  });

  final WindowWidthClass widthClass;

  /// 大网格（封面墙，中卡）：竖屏 2 / medium 3 / expanded+ 4 列。
  final int largeGridColumns;

  /// 小网格（紧凑卡）：竖屏 3 / 横屏 5 列。
  final int smallGridColumns;

  static ResponsiveGridHelper fromWidth(double width) {
    // 竖屏（compact）由调用方传入屏宽判断。
    if (width >= 1200) {
      return const ResponsiveGridHelper._(
        widthClass: WindowWidthClass.large,
        largeGridColumns: 4,
        smallGridColumns: 5,
      );
    }
    if (width >= 840) {
      return const ResponsiveGridHelper._(
        widthClass: WindowWidthClass.expanded,
        largeGridColumns: 4,
        smallGridColumns: 5,
      );
    }
    if (width >= 600) {
      return const ResponsiveGridHelper._(
        widthClass: WindowWidthClass.medium,
        largeGridColumns: 3,
        smallGridColumns: 5,
      );
    }
    return const ResponsiveGridHelper._(
      widthClass: WindowWidthClass.compact,
      largeGridColumns: 2,
      smallGridColumns: 3,
    );
  }

  /// 构建上下文感知的网格参数（横屏按横屏宽计算）。
  static ResponsiveGridHelper of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return fromWidth(width);
  }
}
