import 'package:audio_service/audio_service.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:provider/provider.dart';

import 'src/providers/audio_provider.dart';
import 'src/providers/download_provider.dart';
import 'src/providers/library_provider.dart';
import 'src/providers/mirror_provider.dart';
import 'src/providers/online_provider.dart';
import 'src/providers/theme_mode.dart';
import 'src/providers/theme_provider.dart';
import 'src/providers/ui_settings_provider.dart';
import 'src/screens/main_screen.dart';
import 'src/services/audio_player_service.dart';
import 'src/services/download_service.dart';
import 'src/services/history_service.dart';
import 'src/services/net_meta_service.dart';
import 'src/utils/theme.dart';

/// KikoLocal —— KikoFlu 像素级复刻的本地播放安卓音乐播放器。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 播放后端：media_kit（libmpv）。ExoPlayer 在部分模拟器（如 MuMu ARM64）上
  // 音频渲染卡死（position 不推进）；libmpv 兼容性更好，全平台统一（KikoFlu 同款组合）。
  JustAudioMediaKit.ensureInitialized(android: true);

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
        ChangeNotifierProvider(create: (_) => MirrorProvider()),
      ],
      child: DynamicColorBuilder(
        builder: (lightDynamic, darkDynamic) {
          return MultiProvider(
            providers: [
              // 在线模块依赖镜像与本地库（已下载角标）。
              ChangeNotifierProxyProvider2<MirrorProvider,
                  LibraryProvider, OnlineProvider>(
                create: (context) => OnlineProvider(
                  mirror: context.read<MirrorProvider>(),
                  library: context.read<LibraryProvider>(),
                ),
                update: (context, mirror, library, online) => online!,
              ),
              // 下载即入库：下载目录跟随扫描根目录，队列空闲触发重扫（PRD §5.12）。
              // M11 网络元数据（依赖镜像 + 本地库 DB；DB 异步就绪后重建）。
              ProxyProvider2<MirrorProvider, LibraryProvider,
                  NetMetaService>(
                create: (context) => NetMetaService(
                  mirror: context.read<MirrorProvider>(),
                  db: context.read<LibraryProvider>().database,
                ),
                update: (context, mirror, library, previous) =>
                    library.database != null &&
                            previous?.db != library.database
                        ? NetMetaService(
                            mirror: mirror, db: library.database)
                        : previous!,
              ),
              ChangeNotifierProxyProvider<LibraryProvider, DownloadProvider>(
                create: (context) {
                  final library = context.read<LibraryProvider>();
                  final service = DownloadService(
                    downloadRoot:
                        p.join(library.roots.firstOrNull ?? '/storage/emulated/0/Download', 'downloads'),
                  );
                  final provider = DownloadProvider(service);
                  provider.onQueueIdle = (completed) async {
                    await library.rescan(); // 下载完成 → M8 增量扫描入库
                  };
                  // 扫描根目录变化时同步下载目录。
                  library.addListener(() {
                    final root = library.roots.firstOrNull;
                    if (root != null) {
                      service.downloadRoot = p.join(root, 'downloads');
                    }
                  });
                  return provider;
                },
                update: (context, library, previous) => previous!,
              ),
            ],
            child: Consumer<ThemeSettingsProvider>(
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
                  home: const _HistoryRecorder(child: MainScreen()),
                );
              },
            ),
          );
        },
      ),
    );
  }
}


/// 播放历史记录器：订阅播放位置流（≤5s 节流）与暂停/切歌事件写入断点。
class _HistoryRecorder extends StatefulWidget {
  const _HistoryRecorder({required this.child});

  final Widget child;

  @override
  State<_HistoryRecorder> createState() => _HistoryRecorderState();
}

class _HistoryRecorderState extends State<_HistoryRecorder> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _wire());
  }

  void _wire() {
    if (!mounted) return;
    final audio = context.read<AudioPlayerProvider>();
    final library = context.read<LibraryProvider>();
    HistoryService? service;
    void ensureService() {
      service ??= library.database != null
          ? HistoryService(library.database)
          : null;
    }


    // 位置流周期记录（service 内部 5s 节流）。
    audio.positionStream.listen((position) {
      ensureService();
      final track = audio.currentTrack;
      if (track == null) return;
      service?.record(
          track, position.inMilliseconds, audio.duration?.inMilliseconds ?? 0);
    });
    // 暂停时立即落一次断点（突破节流，直接写）。
    audio.playerStateStream.listen((state) {
      ensureService();
      final track = audio.currentTrack;
      if (track == null || state.playing) return;
      ensureService();
      final svc = service;
      if (svc == null) return;
      svc.lastWriteAt = DateTime.fromMillisecondsSinceEpoch(0);
      svc.record(track, audio.handler.player.position.inMilliseconds,
          audio.duration?.inMilliseconds ?? 0);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
