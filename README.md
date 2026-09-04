# RLPlayer

> 面向同人音声 / ASMR 的 Android 本地播放器。灵感与协议对齐 [kikoeru](https://github.com/kikoeru-project) / [kikoflu](https://github.com/kikoeru-project/kikoflu)，但在"本地优先 + 账号可同步"的思路上做成了独立、功能完整的作品管理播放器。
> 当前版本 **v1.6.6**（内部 versionCode 36）。
> English: [README.en.md](README.en.md)

## 特性总览

### 本地库
- 按扫描根目录入库，自动识别 **RJ/BJ/VJ 号**、读取 `metadata.json`（标题/社团/CV/标签）
- **来源文件夹标签**：作品自动归属其"扫描根目录"（如一批文件来自 `文件夹1` → 标签 `文件夹1`），本地库可组合筛选（全部/已识别/未识别 × 来源文件夹 × ♥ 喜欢）
- 手动补录 RJ（支持纯数字自动补前缀）、未识别作品批量补录引导、扫描增量
- 扫描后**自动后台拉取全部网络元数据**（asmr.one → DLsite 兜底），无需逐一点进详情即可在筛选中看到标签/CV/社团；也可手动「刷新全部网络元数据」

### 搜索
- 本地与**全网**双模式；多条件 AND/OR 常显可切换，长按条件切换"排除"
- 支持 关键词 / RJ 号 / 标签 / 社团 / 声优 条件，本地+全站实时补全
- **CV 合作检索**：一次输入 `声优A×声优B` 自动拆条件并切 AND，顶部显示"CV 合作检索"指示
- 全网组合真分页（每源游标 + 内存过滤，不受"只拉前 40"限制）、高级筛选（评分≥/全年龄/R18/销量）、实时推荐

### 播放
- just_audio 内核（音频服务后台播放、断点续播、历史）
- 全局**悬浮播放球**：环状进度 + 中心播放/暂停，下方按钮进入全屏播放页
- 全屏播放页：歌词/字幕视图（GBK/Shift-JIS 字幕自动转码）、迷你歌词、封面等
- 支持在线作品流播与**下载即入库**（下载后自动获得本地来源标签）

### 文件树
- 音频行点播；**词/字/图/🎬 预览**：歌词字幕预览（可翻译）、图片全屏浏览、视频预览播放（本地/在线 URL，video_player）
- 字幕与音频按文件名自动匹配（在线优先用本地已有字幕/歌词）
- 文件名批量翻译（译文/原文切换）

### 账号与云端（kikoeru 系服务器 / asmr.one 等）
- 多镜像站点与登录管理（Bearer Token；请求自动走已登录镜像）
- **作品标记五态与账号同步**：想听(marked)/在听(listening)/听过(listened)/回味(replay)/搁置(postponed) + 我的评分 + 评语，`PUT /api/review`；支持自建 kikoeru-express 的完整协议
- **账号播放列表**：浏览/新建/加入作品（兼容 `/api/playlist/get-playlists` 与官方 `/api/playlists` 两种实现）
- 收藏 Tab = 账号标记瀑布（状态/评分徽章 + 移除），按五态筛选
- 作品内页评论区（asmr.one → DLsite 评论 API 兜底，可单条翻译）
- 相关推荐（本地同社团 + asmr.one 同社团，5 分钟会话缓存）

### 「我的」
- 状态（本机五态分组）/ 收藏（账号标记瀑布）/ 喜欢（♥ 本机独立双轨）/ 本地库（视角×来源筛选）/ 历史 / 播放列表（本地+账号）/ 字幕库 / 下载管理（进行中/已完成/全部 分流）
- Tab 显示可配置（隐藏不需要的 Tab）、右上设置直达

### 设置 / 外观
- 主题模式/配色、界面与歌词字体缩放（0.7–1.4/0.7–2.0，适配大字体实机）
- 网络元数据开关、仅 Wi-Fi、DLsite 代理自检、音频增益
- 数据与历史：刷新全部元数据 / 清空播放历史
- 扫描根目录多目录管理、存储统计

## 技术要点
- Flutter（当前 3.44.x）+ 插件：just_audio、video_player、sqflite（本地单库 v11：works/net_meta/work_status/local_likes/source_root…）、shared_preferences、flutter_secure_storage 等
- 元数据/评论/标记/歌单全部按 kikoeru-express 开放协议实现，服务器需登录的端点一律"已登录镜像"执行并回切

## 构建
```bash
# 需要：Flutter SDK + JDK17 + Android SDK
# 注意 pub.dev 网络不稳时可用镜像
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
cd kiko_local && flutter pub get
# flutter build 包装器可能卡联网 pub；可直接走 gradle（按需目标架构）
cd android
./gradlew :app:assembleRelease -Ptarget-platform=android-arm64
# 产物 build/app/outputs/flutter-apk/app-release.apk
```
测试基线：`flutter analyze` / `flutter test`（64/64）。

## 路线图 / 规划文档
- [搜索模块迭代方案](docs/搜索模块迭代方案.md)
- [我的模块迭代方案](docs/我的模块迭代方案.md)

## 致谢
- [kikoeru](https://github.com/kikoeru-project) 系列（协议与设计启发）
- [kikoflu](https://github.com/kikoeru-project/kikoflu)（客户端交互参考）
