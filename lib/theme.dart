import 'package:flutter/material.dart';

/// Paleta do protótipo `Soma Trails.html`: fundo escuro esverdeado, acento laranja.
class AppColors {
  static const bg = Color(0xFF0B0F0C);
  static const panel = Color(0xFF161A17);
  static const accent = Color(0xFFF57C1F); // laranja
  static const accentAlt = Color(0xFFFF2DAA); // rosa (pontos)
  static const ok = Color(0xFF34D058); // verde "offline pronto"
  static const textDim = Color(0xFF8A938C);
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.accent,
      secondary: AppColors.accentAlt,
      surface: AppColors.panel,
    ),
  );
}
