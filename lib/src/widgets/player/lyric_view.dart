import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/ui_settings_provider.dart';

import '../../models/lyric.dart';
import '../../utils/ui_tokens.dart';

/// 歌词视图控制器：seek 事件与播放 tick 事件走同一条
/// "定位到时刻 t"的统一入口（PRD §5.6.4 实现提示）。
class LyricController extends ChangeNotifier {
  Lyrics? _lyrics;
  int activeIndex = -1;

  Lyrics? get lyrics => _lyrics;

  bool get hasLyrics => _lyrics != null && _lyrics!.lines.isNotEmpty;

  /// 当前活动行文本（迷你播放条歌词行同源）。
  String? get activeText {
    if (!hasLyrics || activeIndex < 0) return null;
    return _lyrics!.lines[activeIndex].text;
  }

  set lyrics(Lyrics? value) {
    _lyrics = value;
    activeIndex = -1;
    notifyListeners();
  }

  /// 定位到时刻 [t]：二分查找时间戳 ≤ t 的最后一行作为目标活动行。
  ///
  /// 拖动中连续调用时直接覆盖目标行（不排队、不抖动），滚动动画由
  /// 视图层在收到通知后立即发起，新的 animateTo 会取消未完成的动画。
  void locateTo(Duration t) {
    final lyrics = _lyrics;
    if (lyrics == null || lyrics.isEmpty) {
      debugPrint('[Lyric] locateTo 跳过：无歌词 t=${t.inSeconds}s');
      return;
    }

    final index = lyrics.lineIndexAt(t);
    if (index != activeIndex) {
      activeIndex = index;
      notifyListeners();
    }
  }
}

/// 歌词视图（PRD §5.6.4 像素级规格）。
///
/// - 活动行 18sp bold primary；非活动行 16sp onSurfaceVariant；行高 1.5；
/// - 当前行背景 primaryContainer @ 30% 透明度，圆角 8dp；
/// - 换行 / seek 定位 300ms 平滑滚动，目标行居中；
/// - 进入方式：点按全屏播放器大封面切换（再点切回封面）。
class LyricView extends StatefulWidget {
  const LyricView({
    super.key,
    required this.controller,
    required this.positionStream,
    required this.seekEventStream,
    this.onActiveTextChanged,
    this.onSeekTo,
  });

  final LyricController controller;

  /// 播放位置流（自然推进换行）。
  final Stream<Duration> positionStream;

  /// seek 事件流（进度条拖动 / 快进快退 / 通知栏 seek，立即定位）。
  final Stream<Duration> seekEventStream;

  final ValueChanged<String?>? onActiveTextChanged;

  /// 点击歌词行 → seek 到该行时间戳（零延迟跳转）。
  final ValueChanged<Duration>? onSeekTo;

  @override
  State<LyricView> createState() => _LyricViewState();
}

class _LyricViewState extends State<LyricView> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  final List<StreamSubscription<Duration>> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _subscriptions.addAll([
      widget.positionStream.listen(widget.controller.locateTo),
      widget.seekEventStream.listen(widget.controller.locateTo),
    ]);
    // 初始定位（恢复断点时立即到位）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onActiveTextChanged?.call(widget.controller.activeText);
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    widget.onActiveTextChanged?.call(widget.controller.activeText);
    if (!mounted) return;
    _scrollToActiveLine();
  }

  GlobalKey _keyFor(int index) =>
      _itemKeys.putIfAbsent(index, () => GlobalKey(debugLabel: 'lyric_$index'));

  /// 滚动使目标行居中（300ms 平滑）；连续触发时新动画覆盖旧动画（不排队）。
  ///
  /// 实现说明：不用 Scrollable.ensureVisible（部分模拟器上调用后无效果，
  /// 实测 offset 不变）；改为 localToGlobal 精确计算目标行在内容坐标中的
  /// 位置，直接 animateTo —— 行为可控且对所有行（含离屏）有效。
  void _scrollToActiveLine() {
    final controller = widget.controller;
    final index = controller.activeIndex;
    if (index < 0 || !_scrollController.hasClients) return;

    final key = _keyFor(index);
    final context = key.currentContext;
    if (context == null) {
      // 首帧尚未布局：下一帧再滚动。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToActiveLine();
      });
      return;
    }

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return;

    final scrollRenderObject =
        _scrollController.position.context.storageContext.findRenderObject();
    if (scrollRenderObject is! RenderBox) return;

    // 行在滚动内容坐标系中的位置（含当前滚动偏移）。
    final lineY = renderObject
        .localToGlobal(Offset.zero, ancestor: scrollRenderObject)
        .dy;
    // 目标：行中心对齐视口中心。
    final position = _scrollController.position;
    final target = (position.pixels + lineY - position.viewportDimension / 2)
        .clamp(position.minScrollExtent, position.maxScrollExtent);

    _scrollController.animateTo(
      target.toDouble(),
      duration: UiMotion.lyricScroll,
      curve: UiMotion.lyricScrollCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final lyrics = controller.lyrics;

    if (lyrics == null || lyrics.isEmpty) {
      // 无歌词占位（PRD §5.6.4：无关联 lrc 时显示"无歌词"占位）。
      return Center(
        child: Text(
          '无歌词',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    // 真正的全量构建：SingleChildScrollView + Column。
    // 注意 ListView(children:) 仍是 sliver 惰性挂载（离屏行 context 为 null，
    // ensureVisible 滚不过去）；Column 才会构建全部行，任意行可定位。
    return SingleChildScrollView(
      controller: _scrollController,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 96),
        child: Column(
          children: [
            for (var index = 0; index < lyrics.lines.length; index++)
              _buildLine(context, controller, lyrics, index),
          ],
        ),
      ),
    );
  }

  Widget _buildLine(
    BuildContext context,
    LyricController controller,
    Lyrics lyrics,
    int index,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final line = lyrics.lines[index];
    final isActive = index == controller.activeIndex;
    // 歌词独立字体缩放（用户设置，不影响其他界面）。
    final fontScale =
        context.watch<UiSettingsProvider>().lyricFontScale;

      return GestureDetector(
          // 点击歌词行 → 立即 seek 到该行（用户反馈：点击歌词跳转进度）。
          onTap: () {
            final callback = widget.onSeekTo;
            if (callback != null) {
              debugPrint('[Lyric] 点击行 $index → seek ${line.timestamp}');
              callback(line.timestamp);
            }
          },
          child: Padding(
          key: _keyFor(index),
          padding: const EdgeInsets.symmetric(vertical: UiSpacing.medium),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: UiSpacing.medium,
              vertical: UiSpacing.small,
            ),
            decoration: BoxDecoration(
              color: isActive
                  ? scheme.primaryContainer.withValues(alpha: 0.3)
                  : null,
              borderRadius: BorderRadius.circular(UiRadii.control),
            ),
            child: Text(
              line.text,
              // 逐字符断行（不做单词边界保护），避免超长 CJK 串溢出（PRD §4.7）。
              softWrap: true,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: (isActive ? 18 : 16) * fontScale,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w400,
                color: isActive ? scheme.primary : scheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
          ),
      );
  }
}

/// 拖动预览节流帮助函数（PRD §5.6.4：手指按住拖动期间 ≤ 50ms/次）。
class LyricPreviewThrottle {
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  bool shouldUpdate() {
    final now = DateTime.now();
    if (now.difference(_last).inMilliseconds >= 50) {
      _last = now;
      return true;
    }
    return false;
  }
}
