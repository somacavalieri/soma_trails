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

**Pre-code.** The repo currently contains only planning material:
- `PRD-app-trilhas-offline.md` — the full PRD, locked decisions, MVP scope, architecture, and incremental implementation plan. **Read this first for any implementation work** — it is the source of truth.
- `soma_trails.pdf` — companion reference/mockup export for the PRD.

There is no Flutter project scaffolded yet, so no build/lint/test commands exist. Step 1 of the plan is to scaffold Flutter, add dependencies, and confirm an APK builds and sideloads on the S24 Ultra before writing feature code.

## Locked stack (do not swap without asking)

Flutter + `flutter_map` + `flutter_map_tile_caching` (FMTC) + `geolocator` + `gpx` + `file_picker`. These were chosen because the hard parts (offline tile caching by area, multi-polyline render, offline GPS) come from these libraries out of the box.

Once scaffolded, the standard Flutter commands apply: `flutter pub get`, `flutter run`, `flutter test` (single test: `flutter test test/foo_test.dart`), and `flutter build apk` for the sideload artifact.

## Architecture (planned)

Single-screen-centric app. Map layers, bottom to top: **offline-aware base tiles → imported-GPX polylines → the recorded "my track" polyline → location marker.**

Components (see PRD for detail):
- **MapScreen** — full-screen `FlutterMap` + controls (zoom, recenter, tracks panel, download, record FAB, HUD).
- **TileSourceConfig** — list of configurable tile sources (name, URL template, max zoom, attribution); each source gets its own FMTC store. Sources are **configurable by design** — if one breaks (ToS/URL), swap the URL. No runtime source-switcher UI in v1.
- **OfflineDownloadController** — computes tile range for a bbox + zoom span, estimates count/size, runs the FMTC download with progress, persists region metadata.
- **TrackManager** — imports multiple GPX via `file_picker`, parses with `gpx`, holds list (path, name, color, visible), exposes polylines.
- **LocationService** — single `geolocator` stream → position + heading; handles permissions. Works offline (GPS is satellite positioning, no network).
- **TrackRecorder** — consumes the `LocationService` stream (no duplicate GPS), builds the "my track" polyline, controls record/pause/resume/stop, and **auto-saves to disk periodically** so the track survives the app being closed/killed; resumes on reopen. Exports saved tracks as GPX.
- **Persistence** — source config + track/region metadata + recorded tracks (shared_prefs or Isar/sqlite); tiles live in FMTC's own SQLite store (portable, no vendor lock).

## Scope discipline

The breadcrumb recorder is deliberately **light**: its purpose is orientation, not activity data. **Rich activity recording (detailed stats, segments, charts), turn-by-turn navigation/routing, search/geocoding, social sharing, iOS/multiplatform, and cloud sync are out of scope for v1** — the owner already uses Strava/Wikiloc for rich recording. Don't add them without an explicit decision to change scope.

## Definition of success (the verification that matters)

**Airplane-mode test:** close and reopen the app with no network → the map renders from the FMTC cache, the GPS dot moves, imported tracks stay visible. Plus: start a recording, move (or simulate), kill and reopen the app → the recorded track persists, stays drawn, and recording can resume with no lost trail. Final validation is a real ride on a known trail with no signal.
