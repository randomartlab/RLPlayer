# RLPlayer

> An Android-first player & library manager for doujin voice works / ASMR. Design and protocol align with [kikoeru](https://github.com/kikoeru-project) / [kikoflu](https://github.com/kikoeru-project/kikoflu), while this project is an independent, fully-featured product built on a "local-first + account-sync" philosophy.
> Current version **v1.6.6** (versionCode 36).
> 中文版: [README.md](README.md)

## Feature overview

### Local library
- Scans configured root folders and auto-detects **RJ/BJ/VJ codes**; reads `metadata.json` (title / circle / CV / tags)
- **Source-folder tags**: each work is attributed to its scan root (files from `folder-1` → tag `folder-1`); library filters combine view (all/identified/unidentified) × source folder × ♥ likes
- Manual RJ backfill (plain digits get `RJ` prefix), bulk backfill for unidentified works, incremental scanning
- **Automatic background metadata fetch after scan** (asmr.one, DLsite fallback) so tag/CV/circle filters work without opening every detail page; manual "refresh all metadata" also available

### Search
- Local & **all-site** modes; AND/OR toggled persistently; long-press a condition to make it an exclusion
- Conditions: keyword / RJ / tag / circle / VA, with realtime local + cloud suggestions
- **CV collaboration search**: type `VA-A×VA-B`, auto-split into AND conditions with an explicit "CV collaboration" indicator
- True pagination across sources (per-source cursor + in-memory filtering), advanced filters (rating≥/age/sales), realtime suggestions

### Playback
- just_audio engine (background playback, resume & history)
- Global **floating player orb**: ring progress + center play/pause, small button below opens the full-screen player
- Full-screen player: lyrics/subtitles view (GBK/Shift-JIS subtitle decode), floating lyrics, cover art
- Stream online works or **download-and-import** (auto gains its source-folder tag)

### File tree
- Tap audio rows to play; **词/字/图/🎬 previews**: lyrics & subtitle preview (translatable), image full-screen viewer, video preview (local file or online URL via video_player)
- Subtitles auto-matched to audio by filename (online playback prefers local subtitles/lyrics when present)
- Batch filename translation (translated/original toggle)

### Accounts & cloud (kikoeru-family servers / asmr.one etc.)
- Multi-mirror host & login management (Bearer tokens; authenticated requests automatically route through a logged-in mirror)
- **Five-state work marking synced with account**: marked / listening / listened / replay / postponed + personal rating + comment via `PUT /api/review`; full protocol support incl. self-hosted kikoeru-express
- **Account playlists**: browse / create / add works (supports both `/api/playlist/get-playlists` and official `/api/playlists`)
- Favorites tab = account marks waterfall (status/rating badges, removal, five-state filter)
- Per-work comment section (asmr.one, DLsite review API fallback; per-line translation)
- Related works (local same-circle + asmr.one same-circle, 5-minute session cache)

### "Mine" (我的)
- Status (local five-state groups) / Favorites (account marks waterfall) / Likes (♥ local-only) / Library (view × source-folder filters) / History / Playlists (local + account) / Subtitle library / Downloads (active/done/all segments)
- Configurable tab visibility; settings shortcut

### Settings / Appearance
- Theme mode & palette, UI & lyric font scaling (0.7–1.4 / 0.7–2.0)
- Network metadata toggle, Wi-Fi-only, DLsite proxy & self-test, audio gain
- Data & history: refresh all metadata / clear play history
- Multiple scan roots & storage stats

## Technical notes
- Flutter (3.44.x) with just_audio, video_player, sqflite (single local DB v11: works/net_meta/work_status/local_likes/source_root…), shared_preferences, flutter_secure_storage, etc.
- Metadata/comments/marks/playlists follow the open kikoeru-express protocol; authenticated endpoints run on the logged-in mirror and restore afterwards

## Build
```bash
# Requirements: Flutter SDK + JDK17 + Android SDK
# Use mirrors if pub.dev is slow/unreachable
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
cd kiko_local && flutter pub get
# If the flutter build wrapper hangs on network pub, drive gradle directly:
cd android
./gradlew :app:assembleRelease -Ptarget-platform=android-arm64
# Output: build/app/outputs/flutter-apk/app-release.apk
```
Test baseline: `flutter analyze` / `flutter test` (64/64).

## Planning docs (Chinese)
- [搜索模块迭代方案](docs/搜索模块迭代方案.md) (Search module iteration plan)
- [我的模块迭代方案](docs/我的模块迭代方案.md) ("Mine" module iteration plan)

## Credits
- [kikoeru](https://github.com/kikoeru-project) family (protocol & design inspiration)
- [kikoflu](https://github.com/kikoeru-project/kikoflu) (client interaction reference)
