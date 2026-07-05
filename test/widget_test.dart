import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soma_trails/theme.dart';
import 'package:soma_trails/tile_source.dart';

void main() {
  test('tema usa fundo escuro e acento laranja', () {
    final theme = buildTheme();
    expect(theme.scaffoldBackgroundColor, AppColors.bg);
    expect(theme.colorScheme.primary, AppColors.accent);
    expect(theme.brightness, Brightness.dark);
  });

  test('cada fonte de tiles tem um storeName único', () {
    final names = TileSources.defaults.map((s) => s.storeName).toSet();
    expect(names.length, TileSources.defaults.length);
  });
}
