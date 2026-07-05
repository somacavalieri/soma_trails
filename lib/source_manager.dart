import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tile_source.dart';

/// Gerencia as fontes de tiles: quais existem, qual está ativa, e as fontes
/// customizadas adicionadas pelo usuário. Persiste em `shared_preferences`.
///
/// Só uma fonte fica ativa por vez (o mapa usa [active]). Cada fonte tem seu
/// store no FMTC, garantido por [_ensureStore].
class SourceManager extends ChangeNotifier {
  static const _kActiveId = 'active_source_id';
  static const _kCustom = 'custom_sources';

  final List<TileSource> _sources = [...TileSources.defaults];
  String _activeId = TileSources.esri.id;

  List<TileSource> get sources => List.unmodifiable(_sources);
  TileSource get active => _byId(_activeId) ?? TileSources.esri;
  String get activeId => active.id;

  /// Cria os stores das fontes padrão (chamado no boot, antes do primeiro tile).
  static Future<void> ensureDefaultStores() async {
    for (final s in TileSources.defaults) {
      await FMTCStore(s.storeName).manage.create();
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final rawCustom = prefs.getString(_kCustom);
    if (rawCustom != null) {
      try {
        final list = (jsonDecode(rawCustom) as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(TileSource.fromJson);
        for (final s in list) {
          _sources.add(s);
          await _ensureStore(s);
        }
      } catch (_) {
        // Config corrompida: ignora as customizadas.
      }
    }

    final savedActive = prefs.getString(_kActiveId);
    if (savedActive != null && _byId(savedActive) != null) {
      _activeId = savedActive;
    }
    notifyListeners();
  }

  Future<void> setActive(String id) async {
    if (_byId(id) == null || id == _activeId) return;
    _activeId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActiveId, id);
    notifyListeners();
  }

  /// Adiciona uma fonte customizada por URL template ({x}/{y}/{z}).
  Future<TileSource> addCustom({
    required String name,
    required String urlTemplate,
    required int maxNativeZoom,
  }) async {
    final id = 'custom_${DateTime.now().microsecondsSinceEpoch}';
    final source = TileSource(
      id: id,
      name: name.trim().isEmpty ? 'Fonte custom' : name.trim(),
      urlTemplate: urlTemplate.trim(),
      maxNativeZoom: maxNativeZoom,
      attribution: name.trim(),
      custom: true,
    );
    _sources.add(source);
    await _ensureStore(source);
    await _persistCustom();
    notifyListeners();
    return source;
  }

  Future<void> removeCustom(String id) async {
    final s = _byId(id);
    if (s == null || !s.custom) return;
    _sources.remove(s);
    if (_activeId == id) {
      _activeId = TileSources.esri.id;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kActiveId, _activeId);
    }
    await _persistCustom();
    notifyListeners();
  }

  TileSource? _byId(String id) {
    for (final s in _sources) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> _ensureStore(TileSource s) =>
      FMTCStore(s.storeName).manage.create();

  Future<void> _persistCustom() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = _sources.where((s) => s.custom).map((s) => s.toJson()).toList();
    await prefs.setString(_kCustom, jsonEncode(custom));
  }
}
