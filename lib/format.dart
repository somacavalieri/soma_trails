// Formatação leve para HUD e listas (sem dependência de intl).

/// Cronômetro: `M:SS` abaixo de 1 h, `H:MM:SS` acima.
String formatElapsed(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// Duração amigável para trajeto salvo: "47 min", "1h 02".
String formatDurationShort(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}';
  return '$m min';
}

/// Unidade de distância. Alterado pelas configurações (default: km).
bool useMilesUnit = false;

String formatKm(double km) {
  if (useMilesUnit) return '${(km * 0.621371).toStringAsFixed(1)} mi';
  return '${km.toStringAsFixed(1)} km';
}

/// Data/hora relativa: "Hoje · 14:05", "Ontem · 16:20", "24/06 · 07:45".
String formatWhen(DateTime when, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final today = DateTime(ref.year, ref.month, ref.day);
  final day = DateTime(when.year, when.month, when.day);
  final diff = today.difference(day).inDays;
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${two(when.hour)}:${two(when.minute)}';
  if (diff == 0) return 'Hoje · $time';
  if (diff == 1) return 'Ontem · $time';
  return '${two(when.day)}/${two(when.month)} · $time';
}
