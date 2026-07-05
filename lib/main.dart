import 'package:flutter/material.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

import 'map_screen.dart';
import 'source_manager.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Backend de cache offline (ObjectBox). Precisa vir antes de qualquer store.
  await FMTCObjectBoxBackend().initialise();

  // Cria os stores das fontes padrão antes do primeiro tile.
  await SourceManager.ensureDefaultStores();

  runApp(const SomaTrailsApp());
}

class SomaTrailsApp extends StatelessWidget {
  const SomaTrailsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'soma_trails',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const MapScreen(),
    );
  }
}
