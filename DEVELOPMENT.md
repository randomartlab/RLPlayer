# KikoLocal 开发说明

KikoFlu 像素级复刻的本地播放安卓音乐播放器。

- 产品依据：`../PRD-KikoFlu像素级复刻-本地播放安卓播放器.md`（v1.3，已定稿）
- 视觉依据：`../UI设计规范-KikoFlu像素级复刻.md`（v1.0）
- 复刻参考源码：`../kikoflu-analysis/`（KikoFlu v3.8.2 克隆，只读）

## 开发环境（2026-09-01 搭建）

| 组件 | 位置 / 版本 |
|---|---|
| Flutter SDK | `~/development/flutter`（3.44.7，对齐 kikoflu-analysis/.fvmrc） |
| JDK | openjdk@17（Homebrew） |
| Android SDK | `/opt/homebrew/share/android-commandlinetools`（platform 35/36 + build-tools 36） |
| 环境变量 | 已写入 `~/.zshrc`（JAVA_HOME / ANDROID_HOME / PATH） |

常用命令（项目根 = `kiko_local/`）：

```bash
flutter pub get
flutter build apk --debug     # 中文路径下正常
flutter test                  # 中文路径下正常
./tool/analyze.sh             # 静态分析（见下方已知问题）
```

### 已知问题：flutter analyze 在中文路径下崩溃

`flutter analyze` 的 LSP 消息分帧对非 ASCII 项目路径有 bug
（`FormatException: Unterminated string`）。**build / test 不受影响**。
静态分析请使用 `./tool/analyze.sh`（同步到 ASCII 临时路径后执行）。

## 里程碑进度（对齐 PRD §10）

| 里程碑 | 状态 | 说明 |
|---|---|---|
| M1 主框架 + 主题 + 迷你播放条 + 全屏播放器 | **已完成（代码级）** | 2026-09-01：analyze 零问题、单测 9/9、debug APK 构建通过；真机/模拟器视觉比对（验收 #1/#2/#5/#13）待执行 |
| M2 本地识别引擎 + 数据库 + 封面墙 + 详情页 | 未开始 | M8 + M3 + M4 + M10 |
| M3 在线模块 + 下载即入库 | 未开始 | M12 |
| M4 元数据补全 + 搜索 + 我的 | 未开始 | M11 + M6 + M7 |
| M5 歌词字幕全功能 + 悬浮歌词 + 性能 | 未开始 | M5 完整版 |

## 已实现内容（M1）

- `lib/src/utils/ui_tokens.dart`：设计令牌（间距/圆角/控件/字号/动效，UI 规范 §1/§6）
- `lib/src/utils/theme.dart` + `providers/theme_mode.dart` + `providers/theme_provider.dart`：
  5 主题 × 亮暗 21 色槽 + 动态取色，海洋蓝默认，持久化切换
- `providers/ui_settings_provider.dart`：导航样式（经典 58dp / 液态玻璃胶囊）+ 玻璃强度/模糊模式
- `screens/main_screen.dart`：四 Tab IndexedStack 保活 + PageStorageBucket + 横屏 NavigationRail
- `widgets/main_bottom_navigation_bar.dart`：经典 + 液态玻璃（Android BackdropFilter 降级，PRD §3.3 参数）
- `widgets/mini_player.dart`：72/88dp、48 封面 r8、4dp 进度条、Dismissible 下滑关闭、
  Hero 封面、400ms 自定义路由转场
- `screens/audio_player_screen.dart`：大封面 0.4 屏高 r16、点按切歌词、长按沉浸模式、
  横屏 2:3 分栏、进度 seek、快进快退 10s
- `widgets/player/lyric_view.dart` + `models/lyric.dart`：LRC 解析（多时间戳/增强格式）
  + 歌词视图 + **seek 联动统一入口**（二分定位、300ms 滚动、拖动 50ms 节流预览）
- `services/audio_player_service.dart` + `providers/audio_provider.dart`：
  just_audio + audio_service 播放内核（MediaSession 通知栏控制）
- `assets/demo/`：演示音轨 + 歌词（作品页「演示播放」入口验证 M1 端到端链路）

## M1 待办（真机验证）

- [ ] 连接 Android 设备/模拟器运行，执行验收 #1/#2/#5 视觉比对
- [ ] 验收 #13 歌词 seek 联动专项（拖动/快进快退/越界/通知栏 seek 四用例）
- [ ] 悬浮歌词位置的实际手感复核（玻璃降级参数微调）
