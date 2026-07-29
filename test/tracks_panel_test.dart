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
    // Seed + load fazem I/O real (dart:io); testWidgets roda num fake-async
    // zone que nunca completa Futures de I/O real, então isso precisa rodar
    // fora dessa zona via runAsync (senão trava esperando para sempre).
    await tester.runAsync(() async {
      await File('${dir.path}/folders.json').writeAsString(
          jsonEncode([{'id': 'f1', 'name': 'Serra do Cipó'}]));
      await seedTrack(dir, 't1', meta: {'folderIds': ['f1']});
      await seedTrack(dir, 't2', meta: {'folderIds': ['f1'], 'visible': false});
      await seedTrack(dir, 't3');
      await manager.load();
    });

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
    await tester.runAsync(() => manager.load());
    await pumpPanel(tester, manager);

    // O fluxo inteiro (abrir diálogo -> criar -> I/O real de createFolder)
    // precisa rodar dentro do MESMO runAsync: o "zone" de uma função async é
    // fixado no momento em que ela começa a rodar (o tap em "Nova pasta"), e
    // o Future de I/O real (grava folders.json) só completa de fato fora do
    // fake-async zone dos testWidgets. Por isso o pump final também fica
    // dentro deste bloco.
    await tester.runAsync(() async {
      await tester.tap(find.text('Nova pasta'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Circuito das Águas');
      await tester.tap(find.text('Criar'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
    });

    expect(manager.folders.single.name, 'Circuito das Águas');
    expect(find.text('Circuito das Águas'), findsOneWidget);
  });

  testWidgets('menu "Pastas…" marca a trilha em uma pasta', (tester) async {
    await tester.runAsync(() async {
      await File('${dir.path}/folders.json')
          .writeAsString(jsonEncode([{'id': 'f1', 'name': 'Serra do Cipó'}]));
      await seedTrack(dir, 't1');
      await manager.load();
    });

    await pumpPanel(tester, manager);

    await tester.tap(find.byIcon(Icons.more_vert).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pastas…'));
    await tester.pumpAndSettle();

    expect(find.text('Pastas desta trilha'), findsOneWidget);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    // O tap final chama setTrackFolders (I/O real); precisa do mesmo runAsync
    // usado no teste "Nova pasta cria pasta pelo diálogo" acima.
    await tester.runAsync(() async {
      await tester.tap(find.text('Concluir'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
    });

    expect(manager.tracks.single.folderIds, ['f1']);
  });
}
