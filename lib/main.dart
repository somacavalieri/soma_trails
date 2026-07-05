import 'package:flutter/material.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

import 'map_screen.dart';
import 'theme.dart';
import 'tile_source.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Backend de cache offline (ObjectBox). Precisa vir antes de qualquer store.
  await FMTCObjectBoxBackend().initialise();

  // Um store por fonte de tiles. `create()` é idempotente (não recria se já existe).
  for (final source in TileSources.all) {
    await FMTCStore(source.storeName).manage.create();
  }

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
