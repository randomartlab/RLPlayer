import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/library_provider.dart';
import '../providers/audio_provider.dart';
import '../providers/preferences_provider.dart';
import '../providers/mirror_provider.dart';
import '../providers/theme_mode.dart';
import '../providers/theme_provider.dart';
import '../providers/ui_settings_provider.dart';
import '../utils/ui_tokens.dart';
import 'folder_picker_screen.dart';
import 'mirror_management_screen.dart';
import 'package:kiko_local/src/services/net_meta_service.dart';

/// Tab4 设置页（M1 实现外观主题 + 导航样式；M3/M4 里程碑补齐服务器账号、
/// 下载存储、偏好分组，PRD §5.10）。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeSettings = context.watch<ThemeSettingsProvider>();
    final uiSettings = context.watch<UiSettingsProvider>();
    final library = context.watch<LibraryProvider>();
    final mirror = context.watch<MirrorProvider>();
    final audio = context.watch<AudioPlayerProvider>();
    final prefs = context.watch<PreferencesProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text('设置', style: UiTextStyles.pageTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(UiSpacing.medium),
        children: [
          _SettingsCard(
            title: '服务器与账号',
            children: [
              ListTile(
                leading: _LeadingIcon(icon: Icons.dns_outlined, context: context),
                title: const Text('镜像站点与登录'),
                subtitle: Text(
                  mirror.currentUser != null
                      ? '${mirror.activeHost} · 已登录'
                      : '${mirror.activeHost} · 游客浏览',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const MirrorManagementScreen(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: UiSpacing.medium),
          _SettingsCard(
            title: '偏好',
            children: [
              ListTile(
                leading: _LeadingIcon(
                    icon: Icons.cloud_outlined, context: context),
                title: const Text('网络元数据'),
                subtitle: const Text('详情页拉取 CV/标签/封面参考信息'),
                trailing: Switch(
                  value: prefs.metaEnabled,
                  onChanged: prefs.setMetaEnabled,
                ),
              ),
              ListTile(
                leading: _LeadingIcon(
                    icon: Icons.wifi_outlined, context: context),
                title: const Text('仅 Wi-Fi 拉取'),
                subtitle: const Text('移动网络下不请求元数据/封面'),
                trailing: Switch(
                  value: prefs.wifiOnly,
                  onChanged: prefs.setWifiOnly,
                ),
              ),
              ListTile(
                leading: _LeadingIcon(
                    icon: Icons.subtitles_outlined, context: context),
                title: const Text('默认显示字幕'),
                subtitle: const Text('播放器打开时直接进入歌词/字幕视图'),
                trailing: Switch(
                  value: prefs.subtitleDefault,
                  onChanged: prefs.setSubtitleDefault,
                ),
              ),
              ListTile(
                leading: _LeadingIcon(
                    icon: Icons.cleaning_services_outlined, context: context),
                title: const Text('清理元数据缓存'),
                subtitle: const Text('清空 NetMeta 表与网络封面（本地数据不受影响）'),
                onTap: () async {
                  final meta = context.read<NetMetaService>();
                  await meta.clearCache();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('元数据缓存已清理'),
                        duration: Duration(seconds: 2)));
                  }
                },
              ),
              ListTile(
                leading: _LeadingIcon(
                    icon: Icons.graphic_eq_outlined, context: context),
                title: const Text('音频增益'),
                subtitle: Slider(
                  value: audio.gainDb,
                  min: -12,
                  max: 12,
                  divisions: 48,
                  label:
                      '${audio.gainDb > 0 ? '+' : ''}${audio.gainDb.toStringAsFixed(1)} dB',
                  onChanged: audio.setGainDb,
                ),
                trailing: Text(
                  '${audio.gainDb > 0 ? '+' : ''}${audio.gainDb.toStringAsFixed(1)} dB',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: UiSpacing.medium),
          _SettingsCard(
            title: '本地库',
            children: [
              ListTile(
                leading:
                    _LeadingIcon(icon: Icons.folder_outlined, context: context),
                title: const Text('扫描根目录'),
                subtitle: Text(
                  library.roots.isEmpty
                      ? '未设置（支持多目录、穿透扫描）'
                      : '${library.roots.length} 个目录',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openRootsManager(context),
              ),
              ListTile(
                leading:
                    _LeadingIcon(icon: Icons.refresh, context: context),
                title: const Text('重新扫描'),
                subtitle: Text('已入库 ${library.works.length} 个作品'),
                onTap: () => _rescan(context),
              ),
              ListTile(
                leading:
                    _LeadingIcon(icon: Icons.pie_chart_outline, context: context),
                title: const Text('存储统计'),
                onTap: () => _showStats(context),
              ),
            ],
          ),
          const SizedBox(height: UiSpacing.medium),
          _SettingsCard(
            title: '外观',
            children: [
              ListTile(
                leading: _LeadingIcon(
                    icon: Icons.dark_mode_outlined, context: context),
                title: const Text('主题模式'),
                // SegmentedButton 放 subtitle 位（下方独立行）：
                // 大字体下不再挤压 leading/标题区（实机反馈适配修复）。
                subtitle: SegmentedButton<AppThemeMode>(
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
                title: const Text('主题'),
                // 10 款预设主题下拉（实机需求 2026-09-02；
                // 液态玻璃设置已移除）。
                trailing: DropdownButton<ColorSchemeType>(
                  value: themeSettings.settings.colorSchemeType,
                  items: [
                    for (final type in ColorSchemeType.values)
                      DropdownMenuItem(
                        value: type,
                        child: Text(_schemeLabel(type),
                            style: const TextStyle(fontSize: 14)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      themeSettings.setColorSchemeType(value);
                    }
                  },
                ),
              ),
              ListTile(
                leading: _LeadingIcon(
                    icon: Icons.format_size_outlined, context: context),
                title: const Text('界面字体大小'),
                subtitle: Slider(
                  value: uiSettings.uiFontScale,
                  min: 0.8,
                  max: 1.4,
                  divisions: 12,
                  label:
                      '${(uiSettings.uiFontScale * 100).toInt()}%',
                  onChanged: uiSettings.setUiFontScale,
                ),
                trailing: Text(
                    '${(uiSettings.uiFontScale * 100).toInt()}%'),
              ),
              ListTile(
                leading: _LeadingIcon(
                    icon: Icons.lyrics_outlined, context: context),
                title: const Text('歌词字体大小'),
                subtitle: Slider(
                  value: uiSettings.lyricFontScale,
                  min: 0.8,
                  max: 2.0,
                  divisions: 12,
                  label:
                      '${(uiSettings.lyricFontScale * 100).toInt()}%',
                  onChanged: uiSettings.setLyricFontScale,
                ),
                trailing: Text(
                    '${(uiSettings.lyricFontScale * 100).toInt()}%'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 扫描根目录管理（多目录增删，PRD §5.10）。
  Future<void> _openRootsManager(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => const _RootsManagerSheet(),
    );
  }

  Future<void> _rescan(BuildContext context) async {
    final library = context.read<LibraryProvider>();
    if (library.roots.isEmpty) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => const FolderPickerScreen(),
        ),
      );
      return;
    }
    unawaited(library.rescan());
  }

  Future<void> _showStats(BuildContext context) async {
    final library = context.read<LibraryProvider>();
    final stats = await library.stats();
    if (!context.mounted || stats == null) return;

    final gb = stats.totalBytes / (1024 * 1024 * 1024);
    final mb = stats.totalBytes / (1024 * 1024);
    final sizeText = gb >= 1
        ? '${gb.toStringAsFixed(2)} GB'
        : '${mb.toStringAsFixed(1)} MB';

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('存储统计'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatRow(label: '作品数', value: '${stats.workCount}'),
            _StatRow(label: '音轨数', value: '${stats.trackCount}'),
            _StatRow(label: '已关联歌词', value: '${stats.lyricCount}'),
            _StatRow(label: '无封面作品', value: '${stats.noCoverCount}'),
            _StatRow(label: '音频总容量', value: sizeText),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
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
      case ColorSchemeType.inkBlack:
        return '墨玉黑';
      case ColorSchemeType.roseGold:
        return '玫瑰金';
      case ColorSchemeType.tealMint:
        return '青碧薄荷';
      case ColorSchemeType.amberHoney:
        return '琥珀蜜黄';
      case ColorSchemeType.deepSpace:
        return '深空紫夜';
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

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: UiSpacing.xSmall),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// 扫描根目录管理 Sheet（顶圆角 20dp，全局 BottomSheet 主题）。
class _RootsManagerSheet extends StatelessWidget {
  const _RootsManagerSheet();

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(UiSpacing.medium),
            child: Row(
              children: [
                Expanded(
                  child: Text('扫描根目录',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => const FolderPickerScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('添加'),
                ),
              ],
            ),
          ),
          if (library.roots.isEmpty)
            Padding(
              padding: const EdgeInsets.all(UiSpacing.large),
              child: Text(
                '尚未添加扫描根目录。\n扫描引擎会穿透下钻所有层级子目录，\n发现以 RJ 号命名的作品文件夹。',
                textAlign: TextAlign.center,
                style: UiTextStyles.supporting
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: library.roots.length,
                itemBuilder: (context, index) => ListTile(
                  leading: const Icon(Icons.folder),
                  title: Text(library.roots[index]),
                  dense: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: '移除',
                    onPressed: () => library.removeRoot(library.roots[index]),
                  ),
                ),
              ),
            ),
          const SizedBox(height: UiSpacing.medium),
        ],
      ),
    );
  }
}
