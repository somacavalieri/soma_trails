import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'format.dart';
import 'source_manager.dart';

/// Preferências do app (Ajustes): manter tela ligada, alto contraste, unidades.
/// Persiste em `shared_preferences`. Também expõe uso/limpeza do cache de
/// navegação (os tiles auto-cacheados; regiões baixadas têm tela própria).
class SettingsController extends ChangeNotifier {
  SettingsController(this._sources);

  final SourceManager _sources;

  static const _screenChannel = MethodChannel('dev.soma.soma_trails/screen');
  static const _kKeepOn = 'keep_screen_on';
  static const _kContrast = 'high_contrast';
  static const _kMiles = 'use_miles';

  bool _keepScreenOn = true; // decisão travada: tela sempre acesa
  bool _highContrast = false;
  bool _useMiles = false;

  bool get keepScreenOn => _keepScreenOn;
  bool get highContrast => _highContrast;
  bool get useMiles => _useMiles;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _keepScreenOn = prefs.getBool(_kKeepOn) ?? true;
    _highContrast = prefs.getBool(_kContrast) ?? false;
    _useMiles = prefs.getBool(_kMiles) ?? false;
    useMilesUnit = _useMiles;
    await _applyKeepScreenOn();
    notifyListeners();
  }

  Future<void> setKeepScreenOn(bool value) async {
    _keepScreenOn = value;
    await _applyKeepScreenOn();
    await _persistBool(_kKeepOn, value);
    notifyListeners();
  }

  Future<void> setHighContrast(bool value) async {
    _highContrast = value;
    await _persistBool(_kContrast, value);
    notifyListeners();
  }

  Future<void> setUseMiles(bool value) async {
    _useMiles = value;
    useMilesUnit = value;
    await _persistBool(_kMiles, value);
    notifyListeners();
  }

  Future<void> _applyKeepScreenOn() async {
    try {
      await _screenChannel.invokeMethod('setKeepOn', _keepScreenOn);
    } catch (_) {
      // Sem canal nativo (ex.: em teste): ignora.
    }
  }

  Future<void> _persistBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  /// Tamanho (KiB) do cache de navegação = soma dos stores das fontes.
  Future<double> browseCacheKiB() async {
    var total = 0.0;
    for (final s in _sources.sources) {
      try {
        total += await FMTCStore(s.storeName).stats.size;
      } catch (_) {}
    }
    return total;
  }

  /// Esvazia o cache de navegação (mantém as regiões baixadas).
  Future<void> clearBrowseCache() async {
    for (final s in _sources.sources) {
      try {
        await FMTCStore(s.storeName).manage.reset();
      } catch (_) {}
    }
    notifyListeners();
  }
}
