# Pastas de trilhas + ações em massa — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Organizar o painel Trilhas em pastas (1 nível, trilha em várias pastas), com mostrar/ocultar em massa por pasta e modo Selecionar com "Adicionar à pasta…" e "Excluir".

**Architecture:** Pertencimento na trilha (`Track.folderIds: List<String>`) + `folders.json` ao lado do `tracks.json`; tudo dentro do `TrackManager` (único `ChangeNotifier`, como hoje). UI segue o protótipo `Soma Trails.html`: pastas expansíveis no topo do painel, trilhas avulsas abaixo, sheet reutilizável de checkboxes de pastas.

**Tech Stack:** Flutter 3.44.4 / Dart 3.12 — sem nenhum pacote novo. Spec aprovado: `docs/superpowers/specs/2026-07-29-pastas-trilhas-design.md`.

## Global Constraints

- **Nenhuma dependência nova** no `pubspec.yaml` (restrições de win32/file_picker — ver CLAUDE.md).
- Estado via `ChangeNotifier` + `ListenableBuilder` (padrão do projeto; sem package de state management).
- Textos de UI em **pt-BR**; cores via `AppColors` de `lib/theme.dart` (`AppColors.accent`, `AppColors.textDim`, `AppColors.panel`).
- Pastas têm **1 nível** (sem aninhamento). Visibilidade é **propriedade da trilha**; olho da pasta é ação em massa.
- Persistência nunca derruba o app: JSON corrompido/ausente → estado vazio (mesmo padrão do `load()` atual).
- Ao final de cada task: `flutter analyze` sem issues e `flutter test` verde.
- Comandos rodam na raiz do repo: `/Users/somacavalieri/Library/CloudStorage/GoogleDrive-somacavalieri@gmail.com/My Drive/_claude/soma_trails` (o caminho tem espaços — sempre entre aspas).

## File Structure

- `lib/models/track_folder.dart` — **criar**: model `TrackFolder` (id, name, JSON).
- `lib/models/track.dart` — **modificar**: `folderId: String?` → `folderIds: List<String>`.
- `lib/track_manager.dart` — **modificar**: `dirOverride` para testes, migração, CRUD de pastas, APIs de pertencimento/visibilidade/exclusão em massa.
- `lib/folder_picker_sheet.dart` — **criar**: sheet reutilizável "Pastas desta trilha" / "Adicionar à pasta" (checkboxes + criar pasta inline + Concluir).
- `lib/tracks_panel.dart` — **modificar**: vira stateful; pastas expansíveis, olho agregado, Nova pasta, modo Selecionar com barra de ações.
- `test/track_manager_test.dart` — **criar**: testes de model/manager (migração, CRUD, agregados, exclusões).
- `test/tracks_panel_test.dart` — **criar**: widget tests do painel (pasta expande, olho agregado, modo seleção).
- `-management/CHANGELOG.md` — **modificar** ao final.

---

### Task 1: `Track.folderIds` + migração + `dirOverride` de teste

**Files:**
- Modify: `lib/models/track.dart`
- Modify: `lib/track_manager.dart`
- Test: `test/track_manager_test.dart` (criar)

**Interfaces:**
- Consumes: nada novo.
- Produces: `Track.folderIds: List<String>` (mutável, nunca null); `TrackManager({Directory? dirOverride})`; migração de `folderId` legado no `load()`.

- [ ] **Step 1: Escrever os testes que falham**

Criar `test/track_manager_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soma_trails/models/track.dart';
import 'package:soma_trails/track_manager.dart';

const _gpx = '''<?xml version="1.0"?>
<gpx version="1.1" creator="test">
  <trk><name>Trilha teste</name><trkseg>
    <trkpt lat="-19.300" lon="-43.600"/>
    <trkpt lat="-19.301" lon="-43.601"/>
  </trkseg></trk>
</gpx>''';

/// Escreve um GPX + entrada de metadados no diretório de teste, sem passar
/// pelo file_picker. `meta` é mesclado por cima dos campos padrão.
Future<void> seedTrack(Directory dir, String id,
    {Map<String, dynamic> meta = const {}}) async {
  final gpxFile = File('${dir.path}/$id.gpx');
  await gpxFile.writeAsString(_gpx);
  final metaFile = File('${dir.path}/tracks.json');
  final existing = await metaFile.exists()
      ? (jsonDecode(await metaFile.readAsString()) as List<dynamic>)
      : <dynamic>[];
  existing.add({
    'id': id,
    'name': 'Trilha $id',
    'fileName': '$id.gpx',
    'storedPath': gpxFile.path,
    'color': 0xFFFF2DAA,
    'visible': true,
    ...meta,
  });
  await metaFile.writeAsString(jsonEncode(existing));
}

void main() {
  late Directory dir;
  late TrackManager manager;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('soma_trails_test');
    manager = TrackManager(dirOverride: dir);
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  group('migração folderId -> folderIds', () {
    test('folderId legado vira lista com um item', () async {
      await seedTrack(dir, 't1', meta: {'folderId': 'f1'});
      // Migração pressupõe a pasta existente (órfãos são limpos no load).
      await File('${dir.path}/folders.json')
          .writeAsString(jsonEncode([{'id': 'f1', 'name': 'Serra'}]));
      await manager.load();
      expect(manager.tracks.single.folderIds, ['f1']);
    });

    test('sem folderId nem folderIds vira lista vazia', () async {
      await seedTrack(dir, 't1');
      await manager.load();
      expect(manager.tracks.single.folderIds, isEmpty);
    });

    test('toJson grava folderIds e não folderId', () {
      final t = Track(
        id: 'x', name: 'x', fileName: 'x.gpx', storedPath: '/x',
        color: const Color(0xFFFF2DAA), visible: true,
        segments: const [], waypoints: const [], distanceMeters: 0,
        folderIds: ['a', 'b'],
      );
      final json = t.toJson();
      expect(json['folderIds'], ['a', 'b']);
      expect(json.containsKey('folderId'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/track_manager_test.dart`
Expected: falha de compilação (`folderIds` e `dirOverride` não existem).

- [ ] **Step 3: Implementar model + manager**

Em `lib/models/track.dart` — trocar o campo `folderId` (constructor, campo e `toJson`):

```dart
  Track({
    required this.id,
    required this.name,
    required this.fileName,
    required this.storedPath,
    required this.color,
    required this.visible,
    required this.segments,
    required this.waypoints,
    required this.distanceMeters,
    List<String>? folderIds,
  }) : folderIds = folderIds ?? [];
```

```dart
  /// Ids das pastas às quais a trilha pertence (pode ser mais de uma; vazia =
  /// trilha avulsa na raiz do painel).
  List<String> folderIds;
```

```dart
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'fileName': fileName,
        'storedPath': storedPath,
        'color': color.toARGB32(),
        'visible': visible,
        'folderIds': folderIds,
      };
```

Atualizar o doc comment da classe: "(id, nome, arquivo, cor, visível, pastas)".

Em `lib/track_manager.dart`:

```dart
class TrackManager extends ChangeNotifier {
  /// [dirOverride] troca o diretório de dados (testes usam um temp dir e assim
  /// não dependem do path_provider).
  TrackManager({Directory? dirOverride}) : _dirOverride = dirOverride;

  final Directory? _dirOverride;
```

`_dir()` passa a usar o override:

```dart
  Future<Directory> _dir() async {
    if (_tracksDir != null) return _tracksDir!;
    final dir = _dirOverride ??
        Directory('${(await getApplicationDocumentsDirectory()).path}/tracks');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _tracksDir = dir;
  }
```

`_trackFromMeta` migra o formato antigo:

```dart
        folderIds: (e['folderIds'] as List<dynamic>?)?.cast<String>().toList() ??
            [if (e['folderId'] is String) e['folderId'] as String],
```

No `importFromPicker`, nada muda (trilha nova nasce com `folderIds` vazio pelo default do constructor).

Obs.: o teste de migração já escreve um `folders.json`; até a Task 2 esse arquivo é ignorado pelo manager e o teste passa mesmo assim (a limpeza de órfãos só chega na Task 2 — por isso a pasta `f1` já é criada no fixture, para o teste não quebrar depois).

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test && flutter analyze`
Expected: tudo verde, 0 issues.

- [ ] **Step 5: Commit**

```bash
git add lib/models/track.dart lib/track_manager.dart test/track_manager_test.dart
git commit -m "feat: Track.folderIds (multi-pasta) + migração do folderId legado"
```

---

### Task 2: `TrackFolder` + CRUD e persistência de pastas

**Files:**
- Create: `lib/models/track_folder.dart`
- Modify: `lib/track_manager.dart`
- Test: `test/track_manager_test.dart`

**Interfaces:**
- Consumes: `Track.folderIds` (Task 1).
- Produces: `class TrackFolder { final String id; String name; }` com `toJson()`/`fromJson`; no `TrackManager`: `List<TrackFolder> get folders`, `Future<TrackFolder?> createFolder(String name)`, `Future<void> renameFolder(String id, String name)`, `Future<void> deleteFolder(String id, {required bool deleteTracks})`, `Future<void> removeMany(List<String> trackIds)`; `load()` carrega `folders.json` e limpa `folderIds` órfãos.

- [ ] **Step 1: Escrever os testes que falham**

Adicionar ao `main()` de `test/track_manager_test.dart` (novo import: `package:soma_trails/models/track_folder.dart`):

```dart
  group('pastas: CRUD e persistência', () {
    test('createFolder cria, persiste e recarrega', () async {
      final f = await manager.createFolder('Serra do Cipó');
      expect(f!.name, 'Serra do Cipó');
      final reloaded = TrackManager(dirOverride: dir);
      await reloaded.load();
      expect(reloaded.folders.single.name, 'Serra do Cipó');
      expect(reloaded.folders.single.id, f.id);
    });

    test('createFolder com nome vazio não cria', () async {
      expect(await manager.createFolder('   '), isNull);
      expect(manager.folders, isEmpty);
    });

    test('renameFolder muda o nome; vazio é ignorado', () async {
      final f = await manager.createFolder('A');
      await manager.renameFolder(f!.id, 'B');
      expect(manager.folders.single.name, 'B');
      await manager.renameFolder(f.id, '  ');
      expect(manager.folders.single.name, 'B');
    });

    test('deleteFolder(deleteTracks: false) mantém as trilhas', () async {
      await seedTrack(dir, 't1', meta: {'folderIds': ['f1']});
      await File('${dir.path}/folders.json')
          .writeAsString(jsonEncode([{'id': 'f1', 'name': 'Serra'}]));
      await manager.load();
      await manager.deleteFolder('f1', deleteTracks: false);
      expect(manager.folders, isEmpty);
      expect(manager.tracks.single.folderIds, isEmpty);
      expect(File('${dir.path}/t1.gpx').existsSync(), isTrue);
    });

    test('deleteFolder(deleteTracks: true) exclui GPX, mesmo em 2 pastas',
        () async {
      await seedTrack(dir, 't1', meta: {'folderIds': ['f1', 'f2']});
      await seedTrack(dir, 't2', meta: {'folderIds': ['f2']});
      await File('${dir.path}/folders.json').writeAsString(jsonEncode([
        {'id': 'f1', 'name': 'A'},
        {'id': 'f2', 'name': 'B'},
      ]));
      await manager.load();
      await manager.deleteFolder('f1', deleteTracks: true);
      // t1 estava em f1 (e também em f2): excluída por completo.
      expect(manager.tracks.map((t) => t.id), ['t2']);
      expect(File('${dir.path}/t1.gpx').existsSync(), isFalse);
      expect(manager.folders.map((f) => f.id), ['f2']);
    });

    test('folders.json corrompido -> sem pastas, trilhas carregam', () async {
      await seedTrack(dir, 't1');
      await File('${dir.path}/folders.json').writeAsString('{nope');
      await manager.load();
      expect(manager.folders, isEmpty);
      expect(manager.tracks, hasLength(1));
    });

    test('folderIds órfãos são limpos no load', () async {
      await seedTrack(dir, 't1', meta: {'folderIds': ['fantasma']});
      await manager.load();
      expect(manager.tracks.single.folderIds, isEmpty);
    });
  });
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/track_manager_test.dart`
Expected: falha de compilação (`TrackFolder`, `folders`, `createFolder` não existem).

- [ ] **Step 3: Implementar**

Criar `lib/models/track_folder.dart`:

```dart
/// Uma pasta do painel Trilhas. Só agrupa: a visibilidade continua sendo
/// propriedade de cada trilha, e uma trilha pode estar em várias pastas
/// (`Track.folderIds`). Um nível só — pastas não aninham.
class TrackFolder {
  TrackFolder({required this.id, required this.name});

  final String id;
  String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  static TrackFolder fromJson(Map<String, dynamic> e) =>
      TrackFolder(id: e['id'] as String, name: e['name'] as String);
}
```

Em `lib/track_manager.dart` (novo import `models/track_folder.dart`):

```dart
  final List<TrackFolder> _folders = [];

  /// Pastas na ordem de exibição (ordem de criação; sem reordenar no v1).
  List<TrackFolder> get folders => List.unmodifiable(_folders);

  File _foldersFile(Directory dir) => File('${dir.path}/folders.json');
```

`load()` reestruturado — pastas carregam mesmo sem `tracks.json`, e órfãos são limpos ao final:

```dart
  Future<void> load() async {
    final dir = await _dir();
    await _loadFolders(dir);
    final meta = _metadataFile(dir);
    if (await meta.exists()) {
      final raw = jsonDecode(await meta.readAsString()) as List<dynamic>;
      _tracks.clear();
      for (final entry in raw.cast<Map<String, dynamic>>()) {
        final stored = File(entry['storedPath'] as String);
        if (!await stored.exists()) continue; // arquivo sumiu: pula
        try {
          final parsed = parseGpx(await stored.readAsString());
          _tracks.add(_trackFromMeta(entry, parsed));
        } catch (_) {
          // GPX corrompido: ignora em vez de derrubar o app.
        }
      }
    }
    final valid = _folders.map((f) => f.id).toSet();
    for (final t in _tracks) {
      t.folderIds.removeWhere((id) => !valid.contains(id));
    }
    notifyListeners();
  }

  Future<void> _loadFolders(Directory dir) async {
    final file = _foldersFile(dir);
    if (!await file.exists()) return;
    try {
      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      _folders
        ..clear()
        ..addAll(raw.cast<Map<String, dynamic>>().map(TrackFolder.fromJson));
    } catch (_) {
      _folders.clear(); // corrompido: segue sem pastas
    }
  }
```

CRUD + exclusão em massa (o `remove` atual vira um caso do `removeMany`):

```dart
  Future<void> _saveFolders() async {
    final dir = await _dir();
    await _foldersFile(dir)
        .writeAsString(jsonEncode(_folders.map((f) => f.toJson()).toList()));
  }

  Future<TrackFolder?> createFolder(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final folder = TrackFolder(id: _newId(), name: trimmed);
    _folders.add(folder);
    await _saveFolders();
    notifyListeners();
    return folder;
  }

  Future<void> renameFolder(String id, String name) async {
    final trimmed = name.trim();
    final folder = _folderById(id);
    if (folder == null || trimmed.isEmpty) return;
    folder.name = trimmed;
    await _saveFolders();
    notifyListeners();
  }

  /// Exclui a pasta. Com [deleteTracks], exclui também (GPX + metadados) toda
  /// trilha que pertença a ela — mesmo que a trilha esteja em outras pastas.
  Future<void> deleteFolder(String id, {required bool deleteTracks}) async {
    final folder = _folderById(id);
    if (folder == null) return;
    if (deleteTracks) {
      final ids = _tracks
          .where((t) => t.folderIds.contains(id))
          .map((t) => t.id)
          .toList();
      await removeMany(ids);
    } else {
      for (final t in _tracks) {
        t.folderIds.remove(id);
      }
      await _save();
    }
    _folders.remove(folder);
    await _saveFolders();
    notifyListeners();
  }

  /// Exclui várias trilhas de uma vez (GPX + metadados).
  Future<void> removeMany(List<String> trackIds) async {
    final toRemove = trackIds.toSet();
    final victims = _tracks.where((t) => toRemove.contains(t.id)).toList();
    if (victims.isEmpty) return;
    for (final t in victims) {
      _tracks.remove(t);
      try {
        final f = File(t.storedPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await _save();
    notifyListeners();
  }

  TrackFolder? _folderById(String id) {
    for (final f in _folders) {
      if (f.id == id) return f;
    }
    return null;
  }
```

E simplificar o `remove` existente para delegar:

```dart
  Future<void> remove(String id) => removeMany([id]);
```

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test && flutter analyze`
Expected: tudo verde, 0 issues.

- [ ] **Step 5: Commit**

```bash
git add lib/models/track_folder.dart lib/track_manager.dart test/track_manager_test.dart
git commit -m "feat: pastas de trilhas — model, CRUD e persistência (folders.json)"
```

---

### Task 3: Pertencimento, visibilidade agregada e ações em massa

**Files:**
- Modify: `lib/track_manager.dart`
- Test: `test/track_manager_test.dart`

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces: `enum FolderVisibility { all, none, partial }` (em `track_manager.dart`); no `TrackManager`: `List<Track> tracksInFolder(String folderId)`, `List<Track> get looseTracks`, `FolderVisibility folderVisibility(String folderId)`, `Future<void> setFolderVisible(String folderId, bool visible)`, `Future<void> setTrackFolders(String trackId, Set<String> folderIds)`, `Future<void> addToFolder(List<String> trackIds, String folderId)`.

- [ ] **Step 1: Escrever os testes que falham**

Adicionar ao `main()`:

```dart
  group('pertencimento e visibilidade por pasta', () {
    setUp(() async {
      await File('${dir.path}/folders.json').writeAsString(jsonEncode([
        {'id': 'f1', 'name': 'A'},
        {'id': 'f2', 'name': 'B'},
      ]));
      await seedTrack(dir, 't1', meta: {'folderIds': ['f1']});
      await seedTrack(dir, 't2', meta: {'folderIds': ['f1'], 'visible': false});
      await seedTrack(dir, 't3');
      await manager.load();
    });

    test('tracksInFolder e looseTracks', () {
      expect(manager.tracksInFolder('f1').map((t) => t.id), ['t1', 't2']);
      expect(manager.looseTracks.map((t) => t.id), ['t3']);
    });

    test('folderVisibility: all / none / partial', () async {
      expect(manager.folderVisibility('f1'), FolderVisibility.partial);
      await manager.toggleVisible('t2');
      expect(manager.folderVisibility('f1'), FolderVisibility.all);
      await manager.setFolderVisible('f1', false);
      expect(manager.folderVisibility('f1'), FolderVisibility.none);
      expect(manager.folderVisibility('f2'), FolderVisibility.none); // vazia
    });

    test('setFolderVisible liga todas as trilhas da pasta', () async {
      await manager.setFolderVisible('f1', true);
      expect(manager.tracksInFolder('f1').every((t) => t.visible), isTrue);
      // t3 (avulsa) não é afetada.
      expect(manager.looseTracks.single.visible, isTrue);
    });

    test('setTrackFolders substitui o conjunto', () async {
      await manager.setTrackFolders('t1', {'f2'});
      expect(manager.tracksInFolder('f1').map((t) => t.id), ['t2']);
      expect(manager.tracksInFolder('f2').map((t) => t.id), ['t1']);
    });

    test('addToFolder é idempotente e preserva outras pastas', () async {
      await manager.addToFolder(['t1', 't3'], 'f2');
      await manager.addToFolder(['t1'], 'f2'); // repetido: não duplica
      final t1 = manager.tracks.firstWhere((t) => t.id == 't1');
      expect(t1.folderIds, ['f1', 'f2']);
      expect(manager.tracksInFolder('f2').map((t) => t.id), ['t1', 't3']);
    });

    test('removeMany apaga arquivos e metadados', () async {
      await manager.removeMany(['t1', 't3']);
      expect(manager.tracks.map((t) => t.id), ['t2']);
      expect(File('${dir.path}/t1.gpx').existsSync(), isFalse);
      expect(File('${dir.path}/t3.gpx').existsSync(), isFalse);
      final reloaded = TrackManager(dirOverride: dir);
      await reloaded.load();
      expect(reloaded.tracks.map((t) => t.id), ['t2']);
    });
  });
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/track_manager_test.dart`
Expected: falha de compilação (`FolderVisibility`, `tracksInFolder` etc. não existem).

- [ ] **Step 3: Implementar**

Em `lib/track_manager.dart`, acima da classe:

```dart
/// Estado agregado de visibilidade das trilhas de uma pasta (para o olho da
/// pasta no painel). Pasta vazia conta como [none].
enum FolderVisibility { all, none, partial }
```

Na classe:

```dart
  List<Track> tracksInFolder(String folderId) =>
      _tracks.where((t) => t.folderIds.contains(folderId)).toList();

  /// Trilhas fora de qualquer pasta (listadas soltas na raiz do painel).
  List<Track> get looseTracks =>
      _tracks.where((t) => t.folderIds.isEmpty).toList();

  FolderVisibility folderVisibility(String folderId) {
    final ts = tracksInFolder(folderId);
    final visible = ts.where((t) => t.visible).length;
    if (visible == 0) return FolderVisibility.none;
    return visible == ts.length
        ? FolderVisibility.all
        : FolderVisibility.partial;
  }

  /// Ação em massa do olho da pasta: liga/desliga todas as trilhas dela.
  Future<void> setFolderVisible(String folderId, bool visible) async {
    for (final t in tracksInFolder(folderId)) {
      t.visible = visible;
    }
    await _save();
    notifyListeners();
  }

  /// Aplica o resultado do sheet "Pastas desta trilha" (substitui o conjunto).
  Future<void> setTrackFolders(String trackId, Set<String> folderIds) async {
    final t = _byId(trackId);
    if (t == null) return;
    t.folderIds = folderIds.toList();
    await _save();
    notifyListeners();
  }

  /// Ação em massa "Adicionar à pasta": adiciona sem tirar das outras pastas.
  Future<void> addToFolder(List<String> trackIds, String folderId) async {
    for (final id in trackIds) {
      final t = _byId(id);
      if (t != null && !t.folderIds.contains(folderId)) {
        t.folderIds.add(folderId);
      }
    }
    await _save();
    notifyListeners();
  }
```

Atenção: `setTrackFolders` reatribui `t.folderIds` — o campo já é mutável (`List<String> folderIds`, Task 1), nada a mudar no model.

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test && flutter analyze`
Expected: tudo verde, 0 issues.

- [ ] **Step 5: Commit**

```bash
git add lib/track_manager.dart test/track_manager_test.dart
git commit -m "feat: pertencimento a pastas, olho agregado e ações em massa no TrackManager"
```

---

### Task 4: Painel — pastas expansíveis, olho agregado e "Nova pasta"

**Files:**
- Modify: `lib/tracks_panel.dart`
- Test: `test/tracks_panel_test.dart` (criar)

**Interfaces:**
- Consumes: `folders`, `tracksInFolder`, `looseTracks`, `folderVisibility`, `setFolderVisible`, `createFolder`, `renameFolder`, `deleteFolder` (Tasks 2–3).
- Produces: `_TracksPanel` vira `StatefulWidget` com `Set<String> _expanded` (estado local, abre colapsado); linha de ação "Nova pasta"; widget interno `_FolderRow`. A assinatura pública `showTracksPanel(...)` **não muda**.

- [ ] **Step 1: Escrever o widget test que falha**

Criar `test/tracks_panel_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soma_trails/track_manager.dart';
import 'package:soma_trails/tracks_panel.dart';

const _gpx = '''<?xml version="1.0"?>
<gpx version="1.1" creator="test">
  <trk><name>T</name><trkseg>
    <trkpt lat="-19.300" lon="-43.600"/>
    <trkpt lat="-19.301" lon="-43.601"/>
  </trkseg></trk>
</gpx>''';

Future<void> seedTrack(Directory dir, String id,
    {Map<String, dynamic> meta = const {}}) async {
  final gpxFile = File('${dir.path}/$id.gpx');
  await gpxFile.writeAsString(_gpx);
  final metaFile = File('${dir.path}/tracks.json');
  final existing = await metaFile.exists()
      ? (jsonDecode(await metaFile.readAsString()) as List<dynamic>)
      : <dynamic>[];
  existing.add({
    'id': id,
    'name': 'Trilha $id',
    'fileName': '$id.gpx',
    'storedPath': gpxFile.path,
    'color': 0xFFFF2DAA,
    'visible': true,
    ...meta,
  });
  await metaFile.writeAsString(jsonEncode(existing));
}

/// Monta um app mínimo e abre o painel de Trilhas.
Future<void> pumpPanel(WidgetTester tester, TrackManager manager) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: ElevatedButton(
          onPressed: () => showTracksPanel(
            context,
            manager,
            onZoomToTrack: (_) {},
            onImported: (_) {},
          ),
          child: const Text('abrir'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  late Directory dir;
  late TrackManager manager;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('soma_trails_panel');
    manager = TrackManager(dirOverride: dir);
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  testWidgets('pasta aparece colapsada com resumo e expande ao tocar',
      (tester) async {
    await File('${dir.path}/folders.json')
        .writeAsString(jsonEncode([{'id': 'f1', 'name': 'Serra do Cipó'}]));
    await seedTrack(dir, 't1', meta: {'folderIds': ['f1']});
    await seedTrack(dir, 't2', meta: {'folderIds': ['f1'], 'visible': false});
    await seedTrack(dir, 't3');
    await manager.load();

    await pumpPanel(tester, manager);

    expect(find.text('Serra do Cipó'), findsOneWidget);
    expect(find.text('2 trilhas · 1 visíveis'), findsOneWidget);
    expect(find.text('Trilha t1'), findsNothing); // colapsada
    expect(find.text('Trilha t3'), findsOneWidget); // avulsa na raiz

    await tester.tap(find.text('Serra do Cipó'));
    await tester.pumpAndSettle();
    expect(find.text('Trilha t1'), findsOneWidget);
    expect(find.text('Trilha t2'), findsOneWidget);
  });

  testWidgets('Nova pasta cria pasta pelo diálogo', (tester) async {
    await manager.load();
    await pumpPanel(tester, manager);

    await tester.tap(find.text('Nova pasta'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Circuito das Águas');
    await tester.tap(find.text('Criar'));
    await tester.pumpAndSettle();

    expect(manager.folders.single.name, 'Circuito das Águas');
    expect(find.text('Circuito das Águas'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/tracks_panel_test.dart`
Expected: FAIL — "Nova pasta" não existe e a lista é plana (resumo não encontrado).

- [ ] **Step 3: Implementar o painel**

Em `lib/tracks_panel.dart` (novos imports: `models/track_folder.dart`, `folder_picker_sheet.dart` só na Task 5):

1. **`_TracksPanel` vira `StatefulWidget`.** Estado:

```dart
class _TracksPanelState extends State<_TracksPanel> {
  /// Pastas expandidas (abre tudo colapsado; estado não persiste).
  final Set<String> _expanded = {};
```

`build` mantém o `DraggableScrollableSheet` + `ListenableBuilder` atuais; `_import` vira método do state usando `widget.manager`.

2. **Linha de ação "Nova pasta"**, acima de "Mostrar/Ocultar todas" (mesma `Row` de `_SecondaryButton`s, com `Icons.create_new_folder_outlined`):

```dart
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SecondaryButton(
                          label: 'Nova pasta',
                          onTap: () => _createFolder(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
```

```dart
  Future<void> _createFolder(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nova pasta'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nome da pasta'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Criar'),
          ),
        ],
      ),
    );
    if (name != null) await widget.manager.createFolder(name);
  }
```

3. **Lista raiz com pastas + avulsas.** No `builder` do `ListenableBuilder`, substituir o `ListView.separated` por uma lista achatada (pastas primeiro, trilhas da pasta indentadas quando expandida, depois avulsas):

```dart
            final rows = <Widget>[];
            for (final folder in manager.folders) {
              final inFolder = manager.tracksInFolder(folder.id);
              rows.add(_FolderRow(
                folder: folder,
                trackCount: inFolder.length,
                visibleCount: inFolder.where((t) => t.visible).length,
                visibility: manager.folderVisibility(folder.id),
                expanded: _expanded.contains(folder.id),
                onTap: () => setState(() {
                  _expanded.contains(folder.id)
                      ? _expanded.remove(folder.id)
                      : _expanded.add(folder.id);
                }),
                onToggleVisible: () => manager.setFolderVisible(
                  folder.id,
                  manager.folderVisibility(folder.id) != FolderVisibility.all,
                ),
                onRename: () => _renameFolder(context, folder),
                onDelete: () => _deleteFolder(context, folder),
              ));
              if (_expanded.contains(folder.id)) {
                rows.addAll(inFolder.map((t) => Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: _TrackRow(
                        track: t,
                        manager: manager,
                        onZoomToTrack: widget.onZoomToTrack,
                      ),
                    )));
              }
            }
            rows.addAll(manager.looseTracks.map((t) => _TrackRow(
                  track: t,
                  manager: manager,
                  onZoomToTrack: widget.onZoomToTrack,
                )));
```

E o corpo da lista — atenção: o estado vazio agora exige **nem trilhas nem
pastas** (uma pasta criada num app sem trilhas precisa aparecer na lista):

```dart
                Expanded(
                  child: tracks.isEmpty && manager.folders.isEmpty
                      ? _EmptyState(onImport: () => _import(context))
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                          itemCount: rows.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 4),
                          itemBuilder: (context, i) => rows[i],
                        ),
                ),
```

4. **`_FolderRow`** (novo widget no mesmo arquivo, visual análogo ao `_TrackRow`):

```dart
class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.folder,
    required this.trackCount,
    required this.visibleCount,
    required this.visibility,
    required this.expanded,
    required this.onTap,
    required this.onToggleVisible,
    required this.onRename,
    required this.onDelete,
  });

  final TrackFolder folder;
  final int trackCount;
  final int visibleCount;
  final FolderVisibility visibility;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onToggleVisible;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    // Olho agregado: aceso (todas), apagado (nenhuma), meio aceso (parcial).
    final (eyeIcon, eyeColor) = switch (visibility) {
      FolderVisibility.all => (Icons.visibility, AppColors.accent),
      FolderVisibility.none => (Icons.visibility_off, AppColors.textDim),
      FolderVisibility.partial =>
        (Icons.visibility, AppColors.accent.withValues(alpha: 0.45)),
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Icon(
              expanded ? Icons.expand_more : Icons.chevron_right,
              color: AppColors.textDim,
            ),
            const SizedBox(width: 4),
            const Icon(Icons.folder_outlined, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '$trackCount trilhas · $visibleCount visíveis',
                    style:
                        const TextStyle(color: AppColors.textDim, fontSize: 13),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: trackCount == 0 ? null : onToggleVisible,
              icon: Icon(eyeIcon, color: eyeColor),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.textDim),
              onSelected: (value) {
                switch (value) {
                  case 'rename':
                    onRename();
                  case 'delete':
                    onDelete();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'rename', child: Text('Renomear')),
                PopupMenuItem(value: 'delete', child: Text('Excluir')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

5. **Diálogos de pasta** no `_TracksPanelState`:

```dart
  Future<void> _renameFolder(BuildContext context, TrackFolder folder) async {
    final controller = TextEditingController(text: folder.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renomear pasta'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (name != null) await widget.manager.renameFolder(folder.id, name);
  }

  Future<void> _deleteFolder(BuildContext context, TrackFolder folder) async {
    final manager = widget.manager;
    final inFolder = manager.tracksInFolder(folder.id);
    if (inFolder.isEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Excluir pasta?'),
          content: Text('"${folder.name}" está vazia.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Excluir'),
            ),
          ],
        ),
      );
      if (ok == true) await manager.deleteFolder(folder.id, deleteTracks: false);
      return;
    }
    final shared = inFolder.where((t) => t.folderIds.length > 1).length;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir pasta?'),
        content: Text(
          '"${folder.name}" tem ${inFolder.length} trilha(s).\n\n'
          '"Pasta e trilhas" remove os arquivos GPX do app'
          '${shared > 0 ? ' — $shared também estão em outras pastas e '
              'sumirão de lá' : ''}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'folder'),
            child: const Text('Só a pasta'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'both'),
            child: const Text('Pasta e trilhas'),
          ),
        ],
      ),
    );
    if (choice != null) {
      await manager.deleteFolder(folder.id, deleteTracks: choice == 'both');
    }
  }
```

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test && flutter analyze`
Expected: tudo verde, 0 issues.

- [ ] **Step 5: Verificação visual no app**

Run: `flutter build apk --release` (só compilar já pega erro de integração; instalar no S24 é opcional aqui — a validação de campo fica no final).

- [ ] **Step 6: Commit**

```bash
git add lib/tracks_panel.dart test/tracks_panel_test.dart
git commit -m "feat: painel Trilhas com pastas expansíveis, olho agregado e Nova pasta"
```

---

### Task 5: Sheet "Pastas desta trilha" (reutilizável)

**Files:**
- Create: `lib/folder_picker_sheet.dart`
- Modify: `lib/tracks_panel.dart` (item "Pastas…" no menu da trilha)
- Test: `test/tracks_panel_test.dart`

**Interfaces:**
- Consumes: `folders`, `createFolder` (Task 2), `setTrackFolders` (Task 3).
- Produces:

```dart
Future<void> showFolderPickerSheet(
  BuildContext context,
  TrackManager manager, {
  required String title,
  String? subtitle,
  Set<String> initiallySelected,
  required Future<void> Function(Set<String> folderIds) onConfirm,
})
```

- [ ] **Step 1: Escrever o widget test que falha**

Adicionar a `test/tracks_panel_test.dart`:

```dart
  testWidgets('menu "Pastas…" marca a trilha em uma pasta', (tester) async {
    await File('${dir.path}/folders.json')
        .writeAsString(jsonEncode([{'id': 'f1', 'name': 'Serra do Cipó'}]));
    await seedTrack(dir, 't1');
    await manager.load();
    await pumpPanel(tester, manager);

    await tester.tap(find.byIcon(Icons.more_vert).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pastas…'));
    await tester.pumpAndSettle();

    expect(find.text('Pastas desta trilha'), findsOneWidget);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Concluir'));
    await tester.pumpAndSettle();

    expect(manager.tracks.single.folderIds, ['f1']);
  });
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/tracks_panel_test.dart`
Expected: FAIL — item "Pastas…" não existe.

- [ ] **Step 3: Implementar o sheet**

Criar `lib/folder_picker_sheet.dart`:

```dart
import 'package:flutter/material.dart';

import 'theme.dart';
import 'track_manager.dart';

/// Sheet de escolha de pastas (checkboxes) usado em dois fluxos:
/// - "Pastas desta trilha" (menu da trilha): pré-marca as pastas atuais e o
///   Concluir SUBSTITUI o conjunto (via setTrackFolders).
/// - "Adicionar à pasta" (modo Selecionar): nada pré-marcado e o Concluir
///   ADICIONA às pastas marcadas (via addToFolder).
/// O comportamento fica no [onConfirm]; o sheet só coleta o conjunto.
Future<void> showFolderPickerSheet(
  BuildContext context,
  TrackManager manager, {
  required String title,
  String? subtitle,
  Set<String> initiallySelected = const {},
  required Future<void> Function(Set<String> folderIds) onConfirm,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.panel,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _FolderPickerSheet(
      manager: manager,
      title: title,
      subtitle: subtitle,
      initiallySelected: initiallySelected,
      onConfirm: onConfirm,
    ),
  );
}

class _FolderPickerSheet extends StatefulWidget {
  const _FolderPickerSheet({
    required this.manager,
    required this.title,
    required this.subtitle,
    required this.initiallySelected,
    required this.onConfirm,
  });

  final TrackManager manager;
  final String title;
  final String? subtitle;
  final Set<String> initiallySelected;
  final Future<void> Function(Set<String>) onConfirm;

  @override
  State<_FolderPickerSheet> createState() => _FolderPickerSheetState();
}

class _FolderPickerSheetState extends State<_FolderPickerSheet> {
  late final Set<String> _selected = {...widget.initiallySelected};

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nova pasta'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nome da pasta'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Criar'),
          ),
        ],
      ),
    );
    if (name == null) return;
    final folder = await widget.manager.createFolder(name);
    if (folder != null) setState(() => _selected.add(folder.id));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: ListenableBuilder(
          listenable: widget.manager,
          builder: (context, child) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
              if (widget.subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(widget.subtitle!,
                      style: const TextStyle(color: AppColors.textDim)),
                ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final folder in widget.manager.folders)
                      CheckboxListTile(
                        value: _selected.contains(folder.id),
                        onChanged: (checked) => setState(() {
                          checked == true
                              ? _selected.add(folder.id)
                              : _selected.remove(folder.id);
                        }),
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: AppColors.accent,
                        secondary: const Icon(Icons.folder_outlined,
                            color: AppColors.accent),
                        title: Text(folder.name),
                        subtitle: Text(
                          '${widget.manager.tracksInFolder(folder.id).length} trilhas',
                          style: const TextStyle(
                              color: AppColors.textDim, fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: const BorderSide(color: AppColors.accent, width: 1),
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _createFolder,
                icon: const Icon(Icons.add),
                label: const Text('Criar nova pasta'),
              ),
              const SizedBox(height: 10),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: () async {
                  await widget.onConfirm(_selected);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Concluir'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

Em `lib/tracks_panel.dart`: import `folder_picker_sheet.dart`; no `_TrackMenu`, novo item entre "Renomear" e "Excluir":

```dart
        PopupMenuItem(value: 'folders', child: Text('Pastas…')),
```

e no `onSelected`:

```dart
          case 'folders':
            await showFolderPickerSheet(
              context,
              manager,
              title: 'Pastas desta trilha',
              subtitle: '${track.name} · pode estar em várias',
              initiallySelected: track.folderIds.toSet(),
              onConfirm: (ids) => manager.setTrackFolders(track.id, ids),
            );
```

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test && flutter analyze`
Expected: tudo verde, 0 issues.

- [ ] **Step 5: Commit**

```bash
git add lib/folder_picker_sheet.dart lib/tracks_panel.dart test/tracks_panel_test.dart
git commit -m "feat: sheet Pastas desta trilha (multi-pasta por checkbox)"
```

---

### Task 6: Modo Selecionar — adicionar à pasta e excluir em massa

**Files:**
- Modify: `lib/tracks_panel.dart`
- Test: `test/tracks_panel_test.dart`

**Interfaces:**
- Consumes: `addToFolder`, `removeMany` (Tasks 2–3), `showFolderPickerSheet` (Task 5).
- Produces: modo seleção interno ao painel (`_selecting: bool`, `_selected: Set<String>`); botão "Selecionar" ao lado de "Nova pasta"; barra de ações no rodapé.

- [ ] **Step 1: Escrever os widget tests que falham**

Adicionar a `test/tracks_panel_test.dart`:

```dart
  testWidgets('modo Selecionar: excluir em massa', (tester) async {
    await seedTrack(dir, 't1');
    await seedTrack(dir, 't2');
    await seedTrack(dir, 't3');
    await manager.load();
    await pumpPanel(tester, manager);

    await tester.tap(find.text('Selecionar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trilha t1'));
    await tester.tap(find.text('Trilha t3'));
    await tester.pumpAndSettle();
    expect(find.text('2 selecionadas'), findsOneWidget);

    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir 2 trilhas'));
    await tester.pumpAndSettle();

    expect(manager.tracks.map((t) => t.id), ['t2']);
    expect(find.text('2 selecionadas'), findsNothing); // saiu do modo
  });

  testWidgets('modo Selecionar: adicionar à pasta', (tester) async {
    await File('${dir.path}/folders.json')
        .writeAsString(jsonEncode([{'id': 'f1', 'name': 'Serra do Cipó'}]));
    await seedTrack(dir, 't1');
    await seedTrack(dir, 't2');
    await manager.load();
    await pumpPanel(tester, manager);

    await tester.tap(find.text('Selecionar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trilha t1'));
    await tester.tap(find.text('Trilha t2'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Adicionar à pasta…'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Concluir'));
    await tester.pumpAndSettle();

    expect(manager.tracksInFolder('f1').map((t) => t.id), ['t1', 't2']);
  });
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/tracks_panel_test.dart`
Expected: FAIL — botão "Selecionar" não existe.

- [ ] **Step 3: Implementar**

Em `_TracksPanelState`:

1. Estado novo:

```dart
  bool _selecting = false;
  final Set<String> _selected = {};

  void _exitSelection() => setState(() {
        _selecting = false;
        _selected.clear();
      });
```

2. Linha de ação vira "Nova pasta | Selecionar" (a `Row` da Task 4 ganha o segundo botão; em modo seleção o botão vira "Cancelar"):

```dart
                      Expanded(
                        child: _SecondaryButton(
                          label: _selecting ? 'Cancelar' : 'Selecionar',
                          onTap: tracks.isEmpty
                              ? null
                              : () => _selecting
                                  ? _exitSelection()
                                  : setState(() => _selecting = true),
                        ),
                      ),
```

3. Subtítulo do header em modo seleção: trocar `'${manager.visibleCount} de ${tracks.length} visíveis'` por

```dart
                            Text(
                              _selecting
                                  ? '${_selected.length} selecionadas'
                                  : '${manager.visibleCount} de ${tracks.length} visíveis',
                              style: const TextStyle(color: AppColors.textDim),
                            ),
```

4. Linhas de trilha em modo seleção: `_TrackRow` ganha os parâmetros `selecting`, `selected` e `onSelectToggle` (default `false`/`null` para os usos existentes). No `build` do `_TrackRow`, quando `selecting`:
   - a linha inteira vira `InkWell(onTap: onSelectToggle)`;
   - um `Checkbox(value: selected, onChanged: (_) => onSelectToggle!(), activeColor: AppColors.accent)` entra antes do `_ColorSwatch`;
   - o olho e o menu ⋮ ficam ocultos (`if (!selecting) ...`), para não disparar ações individuais no meio da seleção.

   Ao montar `rows` (Task 4), passar `selecting: _selecting`, `selected: _selected.contains(t.id)` e `onSelectToggle: () => setState(() { _selected.contains(t.id) ? _selected.remove(t.id) : _selected.add(t.id); })` em todos os `_TrackRow` (dentro de pasta e avulsos). Trilha em 2 pastas expandidas aparece 2x — o toggle é pelo id, então as duas linhas marcam juntas (correto).

5. Barra de ações no rodapé (último filho da `Column` principal, visível só em modo seleção):

```dart
                if (_selecting)
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.accent,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: _selected.isEmpty
                                  ? null
                                  : () => _addSelectedToFolder(context),
                              icon: const Icon(Icons.folder_outlined),
                              label: const Text('Adicionar à pasta…'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: const BorderSide(color: Colors.redAccent),
                              ),
                              onPressed: _selected.isEmpty
                                  ? null
                                  : () => _deleteSelected(context),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Excluir'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
```

6. Ações:

```dart
  Future<void> _addSelectedToFolder(BuildContext context) async {
    final ids = _selected.toList();
    await showFolderPickerSheet(
      context,
      widget.manager,
      title: 'Adicionar à pasta',
      subtitle: '${ids.length} trilha(s) selecionada(s)',
      onConfirm: (folderIds) async {
        for (final folderId in folderIds) {
          await widget.manager.addToFolder(ids, folderId);
        }
      },
    );
    _exitSelection();
  }

  Future<void> _deleteSelected(BuildContext context) async {
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Excluir $count trilha(s)?'),
        content: const Text('Os arquivos serão removidos do app.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Excluir $count trilhas'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.manager.removeMany(_selected.toList());
      _exitSelection();
    }
  }
```

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test && flutter analyze`
Expected: tudo verde, 0 issues.

- [ ] **Step 5: Commit**

```bash
git add lib/tracks_panel.dart test/tracks_panel_test.dart
git commit -m "feat: modo Selecionar no painel — adicionar à pasta e excluir em massa"
```

---

### Task 7: Verificação final, APK e changelog

**Files:**
- Modify: `-management/CHANGELOG.md`

**Interfaces:**
- Consumes: tudo acima.
- Produces: build de release validado + changelog atualizado.

- [ ] **Step 1: Suíte completa + análise**

Run: `flutter test && flutter analyze`
Expected: todos os testes verdes, 0 issues.

- [ ] **Step 2: Build de release**

Run: `flutter build apk --release`
Expected: `build/app/outputs/flutter-apk/app-release.apk` gerado sem erros (o Drive sincroniza para instalar no S24 Ultra).

- [ ] **Step 3: Atualizar o changelog**

Em `-management/CHANGELOG.md`, seção `## [Não lançado]` → `### Melhorias`, adicionar no topo (substituir `<hash>` pelo hash curto do commit da Task 6):

```markdown
- `<hash>` — **Pastas de trilhas + ações em massa** (sobra do passo 4): pastas
  no painel Trilhas (1 nível, trilha pode estar em várias), olho agregado
  mostra/oculta a pasta inteira, sheet "Pastas desta trilha", modo Selecionar
  com "Adicionar à pasta…" e exclusão em massa. Migração automática do
  `folderId` legado; pastas em `folders.json`.
```

E remover a linha correspondente do `### Backlog (próximo)`:

```markdown
- Pastas de trilhas + seleção múltipla no painel Trilhas (sobra do passo 4).
```

- [ ] **Step 4: Commit**

```bash
git add -- "-management/CHANGELOG.md"
git commit -m "changelog: registra pastas de trilhas + ações em massa"
```

- [ ] **Step 5: Validação manual no aparelho (fora do código)**

No S24 Ultra: criar 2 pastas, marcar uma trilha nas duas, conferir que ela aparece sob as duas e some das avulsas; olho da pasta com estado parcial; excluir pasta nas duas variantes; selecionar 3+ trilhas → adicionar à pasta e excluir. Reabrir o app e conferir persistência.
