import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/ui_settings_provider.dart';
import '../widgets/main_bottom_navigation_bar.dart';
import '../widgets/mini_player.dart';
import 'my_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'works_screen.dart';

/// 主框架：四 Tab（作品/搜索/我的/设置，PRD §3.1）。
///
/// - IndexedStack 保持四个 Tab 页面状态；PageStorageBucket 记忆滚动偏移；
/// - 横屏自动切换 NavigationRail（PRD §3.2）；
/// - 竖屏：经典 58dp / 液态玻璃 78dp 胶囊导航；
/// - 迷你播放条悬浮于底部导航上方，全局常驻。
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  // 使用 PageStorageBucket 来保存页面状态（滚动位置等）。
  final PageStorageBucket _bucket = PageStorageBucket();

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      const WorksScreen(key: PageStorageKey('works_screen')),
      const SearchScreen(key: PageStorageKey('search_screen')),
      MyScreen(
        key: const PageStorageKey('my_screen'),
        onOpenSettings: () => _goTab(3),
      ),
      const SettingsScreen(key: PageStorageKey('settings_screen')),
    ];
  }

  List<NavigationDestination> _buildDestinations(BuildContext context) {
    return [
      const NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: '作品',
      ),
      const NavigationDestination(
        icon: Icon(Icons.search_outlined),
        selectedIcon: Icon(Icons.search),
        label: '搜索',
      ),
      const NavigationDestination(
        icon: Icon(Icons.favorite_border),
        selectedIcon: Icon(Icons.favorite),
        label: '我的',
      ),
      const NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: '设置',
      ),
    ];
  }

  void _handleDestinationSelected(int index) {
    _switchTab(index);
  }

  /// 供子页（如我的页齿轮）切到指定主 Tab（2026-09-03）。
  void _goTab(int index) => _switchTab(index);

  void _switchTab(int index) {
    if (_currentIndex == index) return;
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final uiSettings = context.watch<UiSettingsProvider>();
    final useLiquidGlass = uiSettings.useLiquidGlass;
    final destinations = _buildDestinations(context);

    if (isLandscape) {
      // 横屏布局：NavigationRail 侧边栏模式（PRD §3.2）。
      return Scaffold(
        body: Row(
          children: [
            SafeArea(
              child: NavigationRail(
                selectedIndex: _currentIndex,
                onDestinationSelected: _handleDestinationSelected,
                labelType: NavigationRailLabelType.selected,
                destinations: destinations
                    .map((dest) => NavigationRailDestination(
                          icon: dest.icon,
                          selectedIcon: dest.selectedIcon,
                          label: Text(dest.label),
                        ))
                    .toList(),
              ),
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(
              child: SafeArea(
                top: false,
                bottom: !useLiquidGlass,
                child: Column(
                  children: [
                    Expanded(child: _buildPages()),
                    const MiniPlayer(),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 竖屏：液态玻璃模式把导航栏悬浮在页面内容上方，
    // 经典模式使用 Scaffold 的 bottomNavigationBar 插槽。
    final bottomNavigation = MainBottomNavigationBar(
      selectedIndex: _currentIndex,
      onDestinationSelected: _handleDestinationSelected,
      destinations: destinations,
      liquidGlass: useLiquidGlass,
      glassIntensity: uiSettings.glassIntensity,
      glassBlurMode: uiSettings.glassBlurMode,
      miniPlayer: const MiniPlayer(),
    );

    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: _buildPages(),
      ),
      bottomNavigationBar: bottomNavigation,
    );
  }

  Widget _buildPages() {
    return PageStorage(
      bucket: _bucket,
      child: IndexedStack(
        index: _currentIndex,
        children: List.generate(_screens.length, (index) {
          return HeroMode(
            enabled: index == _currentIndex,
            child: _screens[index],
          );
        }),
      ),
    );
  }
}

/// 迷你播放条常驻（有音轨且未被用户关闭时显示）。
/// [AudioPlayerProvider] 状态由 [MiniPlayer] 自行感知。
