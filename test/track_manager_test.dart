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
}
