import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_mode.dart';
import '../providers/theme_provider.dart';
import '../providers/ui_settings_provider.dart';
import '../utils/ui_tokens.dart';

/// Tab4 设置页（M1 实现外观主题 + 导航样式；M3/M4 里程碑补齐服务器账号、
/// 下载存储、偏好分组，PRD §5.10）。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeSettings = context.watch<ThemeSettingsProvider>();
    final uiSettings = context.watch<UiSettingsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text('设置', style: UiTextStyles.pageTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(UiSpacing.medium),
        children: [
          _SettingsCard(
            title: '外观',
            children: [
              ListTile(
                leading: _LeadingIcon(
                    icon: Icons.dark_mode_outlined, context: context),
                title: const Text('主题模式'),
                trailing: SegmentedButton<AppThemeMode>(
                  segments: const [
                    ButtonSegment(value: AppThemeMode.system, label: Text('跟随')),
                    ButtonSegment(value: AppThemeMode.light, label: Text('亮色')),
                    ButtonSegment(value: AppThemeMode.dark, label: Text('暗色')),
                  ],
                  selected: {themeSettings.settings.themeMode},
                  onSelectionChanged: (selection) =>
                      themeSettings.setThemeMode(selection.first),
                ),
              ),
              ListTile(
                leading:
                    _LeadingIcon(icon: Icons.palette_outlined, context: context),
                title: const Text('配色方案'),
                subtitle: Text(_schemeLabel(
                    themeSettings.settings.colorSchemeType)),
                onTap: () => _showSchemePicker(context),
              ),
            ],
          ),
          const SizedBox(height: UiSpacing.medium),
          _SettingsCard(
            title: '导航样式',
            children: [
              ListTile(
                leading: _LeadingIcon(
                    icon: Icons.blur_on_outlined, context: context),
                title: const Text('液态玻璃导航栏'),
                subtitle: const Text('胶囊形玻璃导航（Android 模糊降级）'),
                trailing: Switch(
                  value: uiSettings.useLiquidGlass,
                  onChanged: (value) => uiSettings.setNavStyle(
                    value ? NavStyle.liquidGlass : NavStyle.classic,
                  ),
                ),
              ),
              if (uiSettings.useLiquidGlass) ...[
                ListTile(
                  leading: _LeadingIcon(
                      icon: Icons.tune_outlined, context: context),
                  title: const Text('玻璃强度'),
                  subtitle: Slider(
                    value: uiSettings.glassIntensity,
                    min: 0.2,
                    max: 1.0,
                    divisions: 8,
                    label: uiSettings.glassIntensity.toStringAsFixed(1),
                    onChanged: uiSettings.setGlassIntensity,
                  ),
                ),
                ListTile(
                  leading: _LeadingIcon(
                      icon: Icons.gradient_outlined, context: context),
                  title: const Text('模糊模式'),
                  trailing: SegmentedButton<GlassBlurMode>(
                    segments: const [
                      ButtonSegment(value: GlassBlurMode.clear, label: Text('清晰')),
                      ButtonSegment(value: GlassBlurMode.hazy, label: Text('朦胧')),
                    ],
                    selected: {uiSettings.glassBlurMode},
                    onSelectionChanged: (selection) =>
                        uiSettings.setGlassBlurMode(selection.first),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _schemeLabel(ColorSchemeType type) {
    switch (type) {
      case ColorSchemeType.oceanBlue:
        return '海洋蓝（默认）';
      case ColorSchemeType.forestGreen:
        return '森林绿';
      case ColorSchemeType.sunsetOrange:
        return '日落橙';
      case ColorSchemeType.lavenderPurple:
        return '薰衣草紫';
      case ColorSchemeType.sakuraPink:
        return '樱花粉';
      case ColorSchemeType.dynamic:
        return '动态取色（Android 12+）';
    }
  }

  Future<void> _showSchemePicker(BuildContext context) async {
    final themeSettings = context.read<ThemeSettingsProvider>();
    final types = ColorSchemeType.values;

    await showDialog<void>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('配色方案'),
        children: [
          RadioGroup<ColorSchemeType>(
            groupValue: themeSettings.settings.colorSchemeType,
            onChanged: (value) {
              if (value != null) {
                themeSettings.setColorSchemeType(value);
              }
              Navigator.of(context).pop();
            },
            child: Column(
              children: [
                for (final type in types)
                  RadioListTile<ColorSchemeType>(
                    value: type,
                    title: Text(_schemeLabel(type)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 设置分组卡片：圆角 16dp + 0.5dp 边框（UI 规范 §5.5）。
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: UiSpacing.small),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: UiSpacing.large),
              child: Text(
                title,
                style: UiTextStyles.supporting
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// 列表项 leading 图标容器 52dp（UiControlSize.settingsLeading）。
class _LeadingIcon extends StatelessWidget {
  const _LeadingIcon({required this.icon, required this.context});

  final IconData icon;
  final BuildContext context;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: UiControlSize.settingsLeading,
      height: UiControlSize.settingsLeading,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(UiRadii.control),
      ),
      child: Icon(icon, color: scheme.onPrimaryContainer),
    );
  }
}
