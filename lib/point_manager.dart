import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import 'models/map_point.dart';

/// Gerencia os pontos marcados pelo usuário (long-press no mapa).
/// Persiste tudo num único JSON; aparecem offline e sobrevivem entre sessões.
class PointManager extends ChangeNotifier {
  final List<MapPoint> _points = [];
  List<MapPoint> get points => List.unmodifiable(_points);
  int get count => _points.length;

  File? _file;
  int _counter = 0;

  Future<File> _storage() async {
    if (_file != null) return _file!;
    final docs = await getApplicationDocumentsDirectory();
    return _file = File('${docs.path}/points.json');
  }

  Future<void> load() async {
    final file = await _storage();
    if (!await file.exists()) return;
    try {
      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      _points
        ..clear()
        ..addAll(raw.cast<Map<String, dynamic>>().map(MapPoint.fromJson));
    } catch (_) {
      // JSON corrompido: começa vazio em vez de derrubar o app.
    }
    notifyListeners();
  }

  Future<MapPoint> add({
    required LatLng point,
    required String name,
    required PointCategory category,
  }) async {
    _counter++;
    final mp = MapPoint(
      id: '${DateTime.now().microsecondsSinceEpoch}_$_counter',
      name: name.trim(),
      category: category,
      point: point,
      createdAt: DateTime.now(),
    );
    _points.add(mp);
    await _save();
    notifyListeners();
    return mp;
  }

  Future<void> rename(String id, String name) async {
    final p = _byId(id);
    if (p == null) return;
    p.name = name.trim();
    await _save();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _points.removeWhere((p) => p.id == id);
    await _save();
    notifyListeners();
  }

  MapPoint? _byId(String id) {
    for (final p in _points) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> _save() async {
    final file = await _storage();
    await file.writeAsString(jsonEncode(_points.map((p) => p.toJson()).toList()));
  }
}
