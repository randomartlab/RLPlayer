import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../providers/ui_settings_provider.dart' show GlassBlurMode;
import '../utils/ui_tokens.dart';

/// 底部导航栏（KikoFlu `main_bottom_navigation_bar.dart` Android 版移植）。
///
/// - 经典模式：Material NavigationBar，高度 58dp（PRD §3.2）；
/// - 液态玻璃模式：胶囊形 78dp，Android 以 BackdropFilter 高斯模糊降级
///   （PRD §3.3：填充色 #F2F2F7/#1C1C1E、边框 0.8px、sigma 6/10 × intensity、
///   最大半透明度 0.92/0.96）。
class MainBottomNavigationBar extends StatelessWidget {
  const MainBottomNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.miniPlayer = const SizedBox.shrink(),
    this.liquidGlass = false,
    this.glassIntensity = 0.4,
    this.glassBlurMode = GlassBlurMode.clear,
  });

  static const double navigationBarHeight = 58;
  static const double glassNavigationBarHeight = 78;
  static const double glassHorizontalPadding = 12;
  static const double glassVerticalPadding = 6;

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;
  final Widget miniPlayer;
  final bool liquidGlass;
  final double glassIntensity;
  final GlassBlurMode glassBlurMode;

  @override
  Widget build(BuildContext context) {
    if (liquidGlass) {
      return _LiquidGlassBottomNavigation(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: destinations,
        miniPlayer: miniPlayer,
        glassIntensity: glassIntensity,
        glassBlurMode: glassBlurMode,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        miniPlayer,
        NavigationBar(
          height: navigationBarHeight,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: destinations,
        ),
      ],
    );
  }
}

class _LiquidGlassBottomNavigation extends StatelessWidget {
  const _LiquidGlassBottomNavigation({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.miniPlayer,
    required this.glassIntensity,
    required this.glassBlurMode,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;
  final Widget miniPlayer;
  final double glassIntensity;
  final GlassBlurMode glassBlurMode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;

    // Android 降级参数（PRD §3.3）。
    final fillBase =
        isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final maxOpacity = isDark ? 0.96 : 0.92;
    // intensity 越高玻璃越实：半透明度按 intensity 从 0.6 → maxOpacity 提升。
    final fillOpacity =
        0.6 + (maxOpacity - 0.6) * glassIntensity.clamp(0.0, 1.0);
    final sigmaMultiplier = glassBlurMode == GlassBlurMode.hazy ? 10.0 : 6.0;
    final sigma = sigmaMultiplier * glassIntensity.clamp(0.0, 1.0);

    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(
        MainBottomNavigationBar.glassNavigationBarHeight / 2,
      ),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.mirror,
        ),
        child: Container(
          height: MainBottomNavigationBar.glassNavigationBarHeight,
          decoration: BoxDecoration(
            color: fillBase.withValues(alpha: fillOpacity),
            border: Border.all(
              // 边框宽度 0.8px（PRD §3.3）。
              width: 0.8,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.6),
            ),
            borderRadius: BorderRadius.circular(
              MainBottomNavigationBar.glassNavigationBarHeight / 2,
            ),
          ),
          child: Row(
            children: [
              for (var index = 0; index < destinations.length; index++)
                Expanded(
                  child: _GlassNavItem(
                    destination: destinations[index],
                    selected: index == selectedIndex,
                    onTap: () => onDestinationSelected(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(
        left: MainBottomNavigationBar.glassHorizontalPadding,
        right: MainBottomNavigationBar.glassHorizontalPadding,
        top: MainBottomNavigationBar.glassVerticalPadding,
        bottom: MainBottomNavigationBar.glassVerticalPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: UiMotion.primary,
            curve: UiMotion.entryCurve,
            alignment: Alignment.bottomCenter,
            child: miniPlayer,
          ),
          bar,
        ],
      ),
    );
  }
}

class _GlassNavItem extends StatelessWidget {
  const _GlassNavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final NavigationDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color =
        selected ? scheme.onSurface : scheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(UiRadii.capsule),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconTheme.merge(
            data: IconThemeData(color: color, size: UiIconSize.large),
            child:
                (selected ? destination.selectedIcon : destination.icon) ??
                    const SizedBox.shrink(),
          ),
          const SizedBox(height: UiSpacing.xSmall),
          Text(
            destination.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
