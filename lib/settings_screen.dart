import 'package:flutter/material.dart';

import 'models/download_region.dart' show formatSizeKiB;
import 'settings_controller.dart';
import 'theme.dart';

/// Tela "Ajustes": armazenamento (cache) + preferências.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.settings});

  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Ajustes'),
      ),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _SectionLabel('ARMAZENAMENTO'),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Cache de navegação'),
                        FutureBuilder<double>(
                          future: settings.browseCacheKiB(),
                          builder: (context, snap) => Text(
                            snap.hasData ? formatSizeKiB(snap.data!) : '…',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tiles cacheados ao navegar. As regiões baixadas ficam em "Baixar satélite → Regiões".',
                      style: TextStyle(color: AppColors.textDim, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFFF6B6B),
                          side: const BorderSide(color: Color(0x55FF6B6B)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () => _clearCache(context),
                        child: const Text('Limpar cache'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const _SectionLabel('PREFERÊNCIAS'),
              _ToggleRow(
                icon: Icons.wb_sunny_outlined,
                title: 'Modo de alto contraste',
                subtitle: 'Trilhas mais grossas e vivas para uso no sol',
                value: settings.highContrast,
                onChanged: settings.setHighContrast,
              ),
              _ToggleRow(
                icon: Icons.smartphone,
                title: 'Manter tela ligada',
                subtitle: 'Não apagar enquanto o app está aberto',
                value: settings.keepScreenOn,
                onChanged: settings.setKeepScreenOn,
              ),
              _UnitsRow(
                useMiles: settings.useMiles,
                onChanged: settings.setUseMiles,
              ),
              const SizedBox(height: 32),
              const Center(
                child: Text('soma_trails · v1.0 · offline-first',
                    style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _clearCache(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpar cache de navegação?'),
        content: const Text(
            'Os tiles cacheados ao navegar serão apagados. As regiões baixadas não são afetadas.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await settings.clearBrowseCache();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Cache limpo.')));
      }
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text,
          style: const TextStyle(
              color: AppColors.textDim,
              fontSize: 12,
              letterSpacing: 1,
              fontWeight: FontWeight.w600)),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.accent),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: const TextStyle(
                        color: AppColors.textDim, fontSize: 12)),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: AppColors.accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _UnitsRow extends StatelessWidget {
  const _UnitsRow({required this.useMiles, required this.onChanged});
  final bool useMiles;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.straighten, color: AppColors.accent),
          const SizedBox(width: 14),
          const Expanded(
            child: Text('Unidades',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('km')),
              ButtonSegment(value: true, label: Text('mi')),
            ],
            selected: {useMiles},
            onSelectionChanged: (s) => onChanged(s.first),
          ),
        ],
      ),
    );
  }
}
