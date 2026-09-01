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
| M2 本地识别引擎 + 数据库 + 封面墙 + 详情页 | **已完成（代码级）** | 2026-09-01：analyze 零问题、单测 41/41（含扫描器集成测试）、debug APK 构建通过；MuMu 模拟器实测待执行 |
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

## 已实现内容（M2，2026-09-01）

**M8 本地识别引擎**
- `services/scan_rules.dart`：纯逻辑规则层 —— RJ 正则（RJ/BJ/VJ × 6~8 位，表层优先）、
  文件分类、同名自动关联（同名 → 唯一单音轨兜底）、封面 5 级降级链挑选、
  数字感知自然排序、小音轨过滤、编码嗅探（UTF-8 → Shift-JIS/GBK 评分选优：
  假名加分 / 半角片假名强减分）
- `services/local_library_scanner.dart`：穿透扫描引擎 —— 递归下钻任意层级发现 RJ 文件夹；
  RJ 仲裁（①表层文件夹名 > ②metadata.json > ③内部文件兜底）；嵌套 RJ 不重复入库；
  根目录散落音频按父目录聚合；音轨时长提取（audio_metadata_reader，失败标未知）；
  内嵌封面提取落盘；metadata.json Kikoeru 格式字段映射

**M10 存储层**
- `services/local_library_database.dart`：sqflite（works + file_nodes 两表，
  级联删除、root_path 唯一索引、存储统计、时长回写接口）
- `providers/library_provider.dart`：根目录管理（SharedPreferences 持久化）、
  扫描进度/取消、排序、移出库、同社团推荐
- `services/storage_permission.dart`：权限策略（≤Android 12 READ_EXTERNAL_STORAGE；
  13+ 回退 MANAGE_EXTERNAL_STORAGE）

**M3 封面墙**
- `widgets/enhanced_work_card.dart`：三变体卡片（中卡 1.3 / 紧凑卡 1.0 / 全卡 80×80），
  本地优先字段，NetMeta 未缓存行自动隐藏
- `screens/works_screen.dart`：瀑布流（大网格 2/3/4 列、小网格 3/5 列、间距 8/24）、
  悬浮工具栏（视图切换/排序/重扫）、扫描进度视图、空态引导直接选目录、随机播放
- `utils/responsive_grid_helper.dart`：窗口断点（compact/medium/expanded/large）

**M4 详情页**
- `screens/work_detail_screen.dart`：封面 r12 Hero、标题 16sp 完整换行、本地文件信息、
  可折叠文件树、同社团推荐位（190dp/120dp）、播放全部/移出库
- `widgets/file_tree_view.dart`：缩进 20dp、目录展开收起、音轨行（序号/两行名称/
  时长/歌词字幕图标）
- `screens/folder_picker_screen.dart`：应用内目录浏览器（从 /storage/emulated/0 开始）
- 我的页本地库 Tab（210dp extent / 0.72 网格）；设置页本地库管理（根目录增删/
  重新扫描/存储统计）

**播放联动**
- 点文件树音轨 → 整作品队列播放，音轨名/封面/歌词全部走本地值

## M2 决策记录（与 PRD 的偏差）

1. **扫描目录访问**：PRD 验收 #17 要求 SAF + 持久化 URI；M2 实现为
   文件路径直访（PRD §7 允许的回退路径）+ 应用内目录选择器。
   原因：SAF content URI 对 just_audio 播放/封面读取/万级文件遍历性能复杂度高；
   MuMu（Android 12）上 READ_EXTERNAL_STORAGE 即完整可用。
   SAF 正式接入排在后续里程碑（需引入 `saf` 包并做 URI→播放源适配）。
2. **重扫策略**：M2 为全量重建（works/file_nodes 整体替换）；增量扫描
   （mtime/size 检测）与播放进度/手动关联保留排 M4。

## M2 待办（模拟器实测）

- [ ] MuMu 安装 app-debug.apk，验证：授权 → 选根目录 → 扫描 → 封面墙 → 详情页 →
      文件树点音轨播放 → 歌词联动
- [ ] 用真实 RJ 文件夹结构抽样验证识别率（验收 #11：≥95%）
- [ ] 视觉比对验收 #3/#4/#8（封面墙列数间距、详情页区块、我的页）

## MuMu 模拟器实测环境（2026-09-01 确认）

- **MuMu Mac（Apple Silicon）= ARM64 Android 12（API 32）**，不是 x86_64！
  打包用 `app-arm64-v8a-debug.apk`；x86_64 包装不上（INSTALL_FAILED_NO_MATCHING_ABIS）。
- 官方 CLI：`/Applications/MuMuPlayer.app/Contents/MacOS/mumu-cli`
  - `control <idx> --action install_apk --path <apk>` 安装
  - `control <idx> --action run_cmd --cmd "<shell>"` 执行 shell（返回含 adb_port）
  - `open/close/info <idx>` 管理实例
- adb 端口：实例 1 = 16416（实例运行时才开放），`adb connect 127.0.0.1:16416`
- 样例测试库已推至 `/storage/emulated/0/Music/KikoLocal测试/kiko_testdata/`：
  含嵌套 RJ（合集分类/RJ123456）、同名 lrc 关联、唯一单音轨歌词关联（第二优先级）、
  同名封面（优先级 2）、cover.png（优先级 1）、metadata.json 标题/社团映射
