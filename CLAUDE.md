# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`soma_trails` is a **personal, single-user offline mountain-bike trails app** for Android (Galaxy S24 Ultra, APK sideload — no iOS, no Play Store). It replaces the aging **My Trails (Frogsparks)** app, replicating only the workflow the owner actually uses.

The three features that define success:
1. **Show my GPS position over offline satellite tiles** while on a trail with no signal.
2. **Download satellite tiles by area from inside the app** (no generating `.mbtiles` on a PC).
3. **Open many GPX tracks at once**, overlaid with distinct colors, plus record a lightweight breadcrumb of the path traveled ("where did I come from?").

> Note: this project is unrelated to the `/My Drive/CLAUDE.md` in a parent folder (that one covers a different 3D-printed-boxes project). Treat this directory as its own project.

## Current state

**Scaffolded and building (plan step 1 done).** The Flutter project lives at the repo root (Android-only, package `dev.soma.soma_trails`). `flutter build apk --release` produces a signed APK at `build/app/outputs/flutter-apk/app-release.apk`; since the repo sits inside Google Drive, the APK auto-syncs — install on the S24 Ultra straight from the Drive app. `lib/main.dart` is still the step-1 "hello map" (online Esri tiles); FMTC browse caching is the next step (plan step 2).

Planning material:
- `PRD-app-trilhas-offline.md` — the full PRD, locked decisions, MVP scope, architecture, and incremental implementation plan. **Read this first for any implementation work** — it is the source of truth.
- `Soma Trails.html` — interactive UI prototype (Claude Design export, JS-rendered; open in a browser). **The prototype is the source of truth for UI/UX** — the PRD's "Especificação de UI" section transcribes it screen by screen; where they diverge, the prototype wins. Only two deliberate deviations: no Bing tile source (discontinued, quadkey format) and an added download-progress state with cancel.
- `soma_trails.pdf` — companion reference/mockup export for the PRD.

## Toolchain (pinned — durability)

macOS arm64, installed via Homebrew. If a build breaks after an environment change, re-check these:
- **Flutter 3.44.4 stable** at `/opt/homebrew/share/flutter` (Dart 3.12.2).
- **OpenJDK 21** at `/opt/homebrew/opt/openjdk@21` — wired via `flutter config --jdk-dir` (no Android Studio installed). The Temurin cask fails here (needs interactive sudo); use the `openjdk@21` formula.
- **Android SDK** at `/opt/homebrew/share/android-commandlinetools` (platforms 35+36, build-tools 35+36, platform-tools) — wired via `flutter config --android-sdk`.
- **AGP pinned to 8.12.0 + Gradle 8.14.2** (`android/settings.gradle.kts` + `android/gradle/wrapper/gradle-wrapper.properties`). The Flutter 3.44 template ships AGP 9.0, which breaks plugins with legacy Gradle files (file_picker's plugin classes never reach the app classpath). **Don't bump AGP to 9.x** without verifying every plugin.
- **Dependency overrides:** `package_info_plus: ^8.3.0` in pubspec.yaml (transitive dep, only used by geolocator's Linux-desktop implementation, never compiled on Android; needed so file_picker ≥11 can have win32 ^5.9). **No wakelock package** — "keep screen on" is `FLAG_KEEP_SCREEN_ON` via a tiny MethodChannel in MainActivity (dependency-free; wakelock_plus conflicts with file_picker over win32).
- **Release signing:** keystore `android/keys/soma_trails-release.jks` + passwords in `android/key.properties` — both git-ignored but inside Drive (that's the backup; **never delete or rotate casually** — losing the keystore means uninstall/reinstall and losing app data).

## Locked stack (do not swap without asking)

Flutter + `flutter_map` + `flutter_map_tile_caching` (FMTC) + `geolocator` + `gpx` + `file_picker`. These were chosen because the hard parts (offline tile caching by area, multi-polyline render, offline GPS) come from these libraries out of the box.

Standard Flutter commands apply: `flutter pub get`, `flutter run`, `flutter test` (single test: `flutter test test/foo_test.dart`), and `flutter build apk --release` for the sideload artifact.

## Architecture (planned)

Single-screen-centric app. Map layers, bottom to top: **offline-aware base tiles → imported-GPX polylines → GPX waypoints → user-marked points → the recorded "my track" polyline → location marker.** Map is north-up (no rotation); the position arrow rotates with heading. Screen stays awake (wakelock) while the app is foregrounded. Long-press on the map marks a personal point (name + category).

Components (see PRD for detail):
- **MapScreen** — full-screen `FlutterMap` + controls (zoom, recenter, tracks panel, download, record FAB, HUD).
- **TileSourceConfig** — list of configurable tile sources (name, URL template, max zoom, attribution); each source gets its own FMTC store. A simple "Fontes do mapa" screen in v1: one source active at a time (toggle), add/edit by URL. Defaults: Esri World Imagery + OSM Topo (no Bing — discontinued, quadkey format). If a source breaks (ToS/URL), swap the URL. The tile provider goes through FMTC (browse caching) from the very first map step, and `maxNativeZoom` enables overzoom (download slider z12–z18, default z12–z15; scale up to ~z20 — never a gray screen).
- **OfflineDownloadController** — two selection modes: **by area** (draggable rectangle) and **by track** (track bbox + margin); computes tile range for a bbox + zoom span, estimates count/size/time, runs the FMTC download with progress, persists region metadata, exposes total storage used.
- **PointManager** — user-marked points (map long-press): name, category, lat/lon; persisted as JSON; exposes map markers and the "Pontos" panel list.
- **TrackManager** — imports multiple GPX via `file_picker`, parses with `gpx` (tracks, routes, and waypoints; multiple `<trk>`/`<trkseg>` per file), holds list (path, name, color, visible, folder), supports folders, multi-select, and bulk show/hide-all, exposes polylines + waypoint markers. Applies polyline simplification so 10+ long tracks render smoothly.
- **LocationService** — single `geolocator` stream → position + heading; handles permissions and distance/accuracy filtering (defaults: distanceFilter 5–10 m, drop points with accuracy > ~30 m). Works offline (GPS is satellite positioning, no network). **While recording, runs as an Android foreground service with a persistent notification** — Samsung One UI aggressively kills background apps, and without this the breadcrumb stops minutes after the screen turns off. This is the product's #1 risk, not an implementation detail.
- **TrackRecorder** — consumes the `LocationService` stream (no duplicate GPS), builds the "my track" polyline, controls record/pause/resume/stop, and **auto-saves GPX directly to disk every ~30 s** so the track survives the app being closed/killed; auto-resumes on reopen with the gap as a new segment (no false straight line). Exports saved tracks to `Downloads/` via MediaStore.
- **Persistence** — source config in `shared_preferences`; imported tracks and recorded tracks as plain files (GPX + a JSON metadata file). No Isar (effectively unmaintained). Tiles live in FMTC's store (**ObjectBox** backend — accepted lock-in, since tiles are re-downloadable; what must survive are the GPX files and config, which are plain files).

## Scope discipline

The breadcrumb recorder is deliberately **light**: its purpose is orientation, not activity data. **Rich activity recording (detailed stats, segments, charts), turn-by-turn navigation/routing, search/geocoding, social sharing, iOS/multiplatform, cloud sync, map rotation (course-up), and "open with" GPX intents are out of scope for v1** — the owner already uses Strava/Wikiloc for rich recording. Don't add them without an explicit decision to change scope.

## Definition of success (the verification that matters)

**Airplane-mode test:** close and reopen the app with no network → the map renders from the FMTC cache, the GPS dot moves, imported tracks stay visible. Plus: start a recording, move (or simulate), kill and reopen the app → the recorded track persists, stays drawn, and recording resumes with no lost trail.

**Screen-off test (critical on One UI):** record ≥1h with the screen off and the phone pocketed → continuous track, no gaps (validates the foreground service + battery-optimization exemption). Battery target while recording: ≲10%/h. Overzoom test: zooming past the downloaded level shows scaled imagery, never a gray screen. Final validation is a real ride on a known trail with no signal.
