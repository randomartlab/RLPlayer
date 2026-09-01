import 'package:audio_service/audio_service.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/providers/audio_provider.dart';
import 'src/providers/library_provider.dart';
import 'src/providers/theme_mode.dart';
import 'src/providers/theme_provider.dart';
import 'src/providers/ui_settings_provider.dart';
import 'src/screens/main_screen.dart';
import 'src/services/audio_player_service.dart';
import 'src/utils/theme.dart';

/// KikoLocal —— KikoFlu 像素级复刻的本地播放安卓音乐播放器。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 播放内核：audio_service 后台服务 + just_audio（KikoFlu 播放组合沿用）。
  // 初始化失败时降级为无后台通知栏模式，保证 App 正常启动（防启动卡 splash）。
  AudioPlayerHandler handler;
  try {
    handler = await AudioService.init(
      builder: AudioPlayerHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'dev.kikolocal.channel.audio',
        androidNotificationChannelName: 'KikoLocal 播放',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
  } catch (e) {
    debugPrint('AudioService.init 失败，降级为无后台服务模式：$e');
    handler = AudioPlayerHandler();
  }

  runApp(KikoLocalApp(handler: handler));
}

class KikoLocalApp extends StatelessWidget {
  const KikoLocalApp({super.key, required this.handler});

  final AudioPlayerHandler handler;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeSettingsProvider()),
        ChangeNotifierProvider(create: (_) => UiSettingsProvider()),
        ChangeNotifierProvider(create: (_) => AudioPlayerProvider(handler)),
        ChangeNotifierProvider(create: (_) => LibraryProvider()),
      ],
      child: DynamicColorBuilder(
        builder: (lightDynamic, darkDynamic) {
          return Consumer<ThemeSettingsProvider>(
            builder: (context, themeSettings, _) {
              final settings = themeSettings.settings;
              final useDynamic = settings.colorSchemeType ==
                  ColorSchemeType.dynamic;

              return MaterialApp(
                title: 'KikoLocal',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.lightTheme(
                  useDynamic ? lightDynamic : null,
                  settings.colorSchemeType,
                ),
                darkTheme: AppTheme.darkTheme(
                  useDynamic ? darkDynamic : null,
                  settings.colorSchemeType,
                ),
                themeMode: settings.toThemeMode(),
                home: const MainScreen(),
              );
            },
          );
        },
      ),
    );
  }
}
