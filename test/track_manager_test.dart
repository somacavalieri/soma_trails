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
