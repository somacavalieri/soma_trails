import 'package:flutter/material.dart';

import 'source_manager.dart';
import 'theme.dart';
import 'tile_source.dart';

/// Tela "Fontes do mapa": camada base ativa (uma por vez) + adicionar/remover.
class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key, required this.manager});

  final SourceManager manager;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Row(
          children: [
            Icon(Icons.layers, color: AppColors.accent),
            SizedBox(width: 10),
            Text('Fontes do mapa'),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: manager,
        builder: (context, child) {
          final sources = manager.sources;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Camada base do mapa. Apenas uma fica ativa por vez — toque para trocar.',
                style: TextStyle(color: AppColors.textDim),
              ),
              const SizedBox(height: 16),
              for (final s in sources)
                _SourceCard(
                  source: s,
                  active: s.id == manager.activeId,
                  onSelect: () => manager.setActive(s.id),
                  onRemove:
                      s.custom ? () => _confirmRemove(context, s) : null,
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.ok,
                  side: BorderSide(color: AppColors.ok.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: () => _addSource(context),
                icon: const Icon(Icons.add),
                label: const Text('Adicionar fonte'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, TileSource s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover fonte?'),
        content: Text('"${s.name}" será removida (o cache dela é descartado).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok == true) await manager.removeCustom(s.id);
  }

  Future<void> _addSource(BuildContext context) async {
    final added = await showDialog<bool>(
      context: context,
      builder: (context) => _AddSourceDialog(manager: manager),
    );
    if (added == true && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Fonte adicionada.')));
    }
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.source,
    required this.active,
    required this.onSelect,
    this.onRemove,
  });

  final TileSource source;
  final bool active;
  final VoidCallback onSelect;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active ? AppColors.accent : Colors.white.withValues(alpha: 0.06),
          width: active ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          source.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (active) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.ok.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('ATIVA',
                              style: TextStyle(
                                  color: AppColors.ok,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                ),
                Switch(
                  value: active,
                  activeThumbColor: AppColors.accent,
                  onChanged: active ? null : (_) => onSelect(),
                ),
              ],
            ),
            Text('zoom máx ${source.maxNativeZoom}',
                style: const TextStyle(color: AppColors.textDim, fontSize: 13)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                source.urlTemplate,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 12,
                    fontFamily: 'monospace'),
              ),
            ),
            if (onRemove != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: Color(0xFFFF6B6B)),
                  label: const Text('Remover',
                      style: TextStyle(color: Color(0xFFFF6B6B))),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddSourceDialog extends StatefulWidget {
  const _AddSourceDialog({required this.manager});
  final SourceManager manager;

  @override
  State<_AddSourceDialog> createState() => _AddSourceDialogState();
}

class _AddSourceDialogState extends State<_AddSourceDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _zoom = TextEditingController(text: '18');
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _zoom.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _url.text.trim();
    if (!url.contains('{x}') || !url.contains('{y}') || !url.contains('{z}')) {
      setState(() => _error = 'A URL precisa conter {x}, {y} e {z}.');
      return;
    }
    final zoom = int.tryParse(_zoom.text.trim()) ?? 18;
    await widget.manager.addCustom(
      name: _name.text,
      urlTemplate: url,
      maxNativeZoom: zoom.clamp(1, 22),
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.panel,
      title: const Text('Adicionar fonte'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nome'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _url,
            decoration: const InputDecoration(
              labelText: 'URL template',
              hintText: 'https://.../{z}/{x}/{y}.png',
              errorMaxLines: 2,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _zoom,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Zoom máximo'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Color(0xFFFF6B6B))),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
          ),
          onPressed: _save,
          child: const Text('Adicionar'),
        ),
      ],
    );
  }
}
