import 'package:audio_service/audio_service.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'src/models/work.dart';
import 'src/providers/audio_provider.dart';
import 'src/providers/download_provider.dart';
import 'src/providers/library_provider.dart';
import 'src/providers/mirror_provider.dart';
import 'src/providers/online_provider.dart';
import 'src/providers/playlist_provider.dart';
import 'src/providers/preferences_provider.dart';
import 'src/providers/theme_mode.dart';
import 'src/providers/theme_provider.dart';
import 'src/providers/ui_settings_provider.dart';
import 'src/screens/audio_player_screen.dart';
import 'src/screens/main_screen.dart';
import 'src/widgets/mini_player.dart';
import 'src/services/audio_player_service.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'src/services/download_service.dart';
import 'src/services/history_service.dart';
import 'src/services/net_meta_service.dart';
import 'src/utils/theme.dart';
import 'src/widgets/storage_permission_gate.dart';

/// KikoLocal —— KikoFlu 像素级复刻的本地播放安卓音乐播放器。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 播放后端：ExoPlayer（Android 默认）。
  // 实测 MuMu ARM64：音频实际在播（AudioTrack 已建），但平台位置事件不回调
  // → positionStream 冻结；已用 createPositionStream 本地外推修复（见 AudioPlayerProvider）。
  // media_kit 后端在该环境卡 idle，仅留 fork 备用（不启用）。

  // 播放内核：audio_service 后台服务 + just_audio（KikoFlu 播放组合沿用）。
  // 初始化失败时降级为无后台通知栏模式，保证 App 正常启动（防启动卡 splash）。
  AudioPlayerHandler handler;
  try {
    handler = await AudioService.init(
      builder: AudioPlayerHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'dev.kikolocal.channel.audio',
        androidNotificationChannelName: 'RLPlayer 播放',
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

/// 全局路由深度观察者（被 MaterialApp 引用）。
final _RouteDepthObserver _routeObserver = _RouteDepthObserver();

/// 记录根导航器真实路由栈（主页之上有无二级页面）。
///
/// 用「真实栈」而非计数器：didPush/didPop/didRemove/didReplace/didShow
/// 全量维护，任何路径（含系统返回/手势）都不会产生 depth 残留——
/// 修复实机反馈 2026-09-02：切页面后出现两个迷你条（计数器多计导致
/// 主页 overlay 条与自带条共存）。
class _RouteDepthObserver extends NavigatorObserver {
  final List<Route<dynamic>> _stack = <Route<dynamic>>[];

  /// 栈深度（0 = 只有主页）。
  final ValueNotifier<int> depth = ValueNotifier<int>(0);

  /// 路由变化通知：push/pop 立即触发一次，500ms 后再触发一次，
  /// 让新页面 initState（如播放页 active=true）完成后全局条重新判断。
  final ValueNotifier<int> version = ValueNotifier<int>(0);

  /// 路由变化后的全局条刷新入口。
  void _notify() {
    depth.value = _stack.isEmpty ? 0 : _stack.length - 1;
    version.value++;
  }

  void _notifyDelayed() {
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      version.value++;
    });
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_stack.isNotEmpty && identical(_stack.last, route)) {
      _stack.removeLast();
    } else {
      _stack.remove(route);
    }
    _notify();
    _notifyDelayed();
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _notify();
    _notifyDelayed();
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) {
      final i = _stack.indexOf(oldRoute);
      if (i >= 0 && newRoute != null) {
        _stack[i] = newRoute;
      }
    } else if (newRoute != null) {
      _stack.add(newRoute);
    }
    _notify();
    _notifyDelayed();
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
    _notify();
    _notifyDelayed();
    super.didPush(route, previousRoute);
  }
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
        ChangeNotifierProvider(create: (_) => PreferencesProvider()),
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
              ChangeNotifierProxyProvider2<LibraryProvider,
                  AudioPlayerProvider, PlaylistProvider>(
                create: (context) => PlaylistProvider(
                  library: context.read<LibraryProvider>(),
                  audio: context.read<AudioPlayerProvider>(),
                ),
                update: (context, library, audio, previous) => previous!,
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

                return _NetMetaBackfillScheduler(
                  child: MaterialApp(
                    navigatorObservers: [_routeObserver],
                    title: 'RLPlayer',
                  debugShowCheckedModeBanner: false,
                  // 全局字体缩放（用户设置，叠加系统缩放；上限 2.0 与 PRD §4.7 一致）。
                  builder: (context, child) {
                    final scale =
                        context.watch<UiSettingsProvider>().uiFontScale;
                    final mediaQuery = MediaQuery.of(context);
                    final scaled = (mediaQuery.textScaler.scale(14) / 14) *
                        scale; // 系统缩放 × 用户缩放
                    return MediaQuery(
                      data: mediaQuery.copyWith(
                        textScaler:
                            TextScaler.linear(scaled.clamp(0.5, 2.0)),
                      ),
                      // 全局迷你播放条（2026-09-02 实机需求：任何页面
                      // 一键返回正在播放页；播放页自身隐藏）。
                      child: Stack(
                        children: [
                          if (child != null) Positioned.fill(child: child),
                          const Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: _GlobalMiniPlayer(),
                          ),
                        ],
                      ),
                    );
                  },
                  theme: AppTheme.lightTheme(
                    useDynamic ? lightDynamic : null,
                    settings.colorSchemeType,
                  ),
                  darkTheme: AppTheme.darkTheme(
                    useDynamic ? darkDynamic : null,
                    settings.colorSchemeType,
                  ),
                  themeMode: settings.toThemeMode(),
                    home: StoragePermissionGate(
                      child: _HistoryRecorder(child: MainScreen()),
                    ),
                  ),
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


/// 悬浮桌面歌词独立入口（flutter_overlay_window 要求，overlay isolate 运行）。
@pragma('vm:entry-point')
void overlayMain() {
  runApp(const _OverlayLyricApp());
}

class _OverlayLyricApp extends StatelessWidget {
  const _OverlayLyricApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF146683)),
      home: const _OverlayLyricPage(),
    );
  }
}

class _OverlayLyricPage extends StatelessWidget {
  const _OverlayLyricPage();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<dynamic>(
      initialData: '',
      stream: FlutterOverlayWindow.overlayListener,
      builder: (context, snapshot) {
        final text = (snapshot.data ?? '').toString();
        return Material(
          color: Colors.transparent,
          child: Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                text.isEmpty ? '♪' : text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.4,
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}


/// 启动后调度 NetMeta 后台回填（筛选/排序数据源，一次即可）。
class _NetMetaBackfillScheduler extends StatefulWidget {
  const _NetMetaBackfillScheduler({required this.child});

  final Widget child;

  @override
  State<_NetMetaBackfillScheduler> createState() =>
      _NetMetaBackfillSchedulerState();
}

class _NetMetaBackfillSchedulerState extends State<_NetMetaBackfillScheduler> {
  bool _scheduled = false;

  @override
  Widget build(BuildContext context) {
    if (!_scheduled) {
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(const Duration(seconds: 8), () async {
          bool _needsCover(LibraryProvider lib, String rj) {
            final w = lib.works
                .where((x) => x.rjCode == rj)
                .firstOrNull;
            return w != null &&
                w.coverSource == CoverSource.placeholder;
          }

          try {
            final library = context.read<LibraryProvider>();
            final service = context.read<NetMetaService>();
            final db = library.database;
            if (db == null) return;
            final existing = (await db.queryAllNetMeta())
                .map((m) => m.rjCode)
                .toSet();
            // 回填条件：缺 NetMeta，或有 NetMeta 但作品仍无封面
            // （实机反馈 2026-09-02：回填先于扫描落库的时序会让封面兜底
            // 落空——getMeta 缓存命中也会跑封面兜底，这里补触发）。
            final missing = library.works
                .where((w) => w.rjCode != null)
                .map((w) => w.rjCode!)
                .where((rj) =>
                    !existing.contains(rj) ||
                    _needsCover(library, rj))
                .toList();
            if (missing.isEmpty) return;
            debugPrint('[NetMeta] 后台回填 ${missing.length} 个作品');
            await service.backfillAll(missing);
            // 回填含封面落盘（cover_source → network）——刷新作品列表。
            if (missing.isNotEmpty) {
              await library.reloadWorks();
            }
          } catch (_) {}
        });
      });
    }
    return widget.child;
  }
}


/// 全局迷你播放条宿主：有播放且不在播放页时显示。
class _GlobalMiniPlayer extends StatefulWidget {
  const _GlobalMiniPlayer();

  @override
  State<_GlobalMiniPlayer> createState() => _GlobalMiniPlayerState();
}

class _GlobalMiniPlayerState extends State<_GlobalMiniPlayer>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 路由变化时重建（检测播放页入栈/出栈）。
    final modal = ModalRoute.of(context);
    // ignore: unnecessary_statements
    modal != null;
    // 订阅路由变化：用 NavigatorObserver 代价高，此处依赖
    // audioProvider 通知 + 周期重建即可（播放页切换必然伴随状态变化）。
  }

  @override
  Widget build(BuildContext context) {
    // 监听路由版本 + 播放页开关信号；音频状态 builder 内现取。
    return ValueListenableBuilder<int>(
      valueListenable: _routeObserver.version,
      builder: (context, _, _) => ValueListenableBuilder<int>(
        valueListenable: audioPlayerActiveSignal,
        builder: (context, _, _) {
          final depth = _routeObserver.depth.value;
          final audio = context.read<AudioPlayerProvider>();
          final hasTrack = audio.currentTrack != null;
          final playerOn = AudioPlayerScreen.active;
          if (depth <= 0 || !hasTrack || playerOn) {
            return const SizedBox.shrink();
          }
          return const MiniPlayer();
        },
      ),
    );
  }
}
