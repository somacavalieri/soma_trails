import 'package:flutter/material.dart';

import 'models/track.dart';
import 'theme.dart';
import 'track_manager.dart';

/// Abre o painel de Trilhas (bottom sheet). `onZoomToTrack` centraliza o mapa
/// na trilha escolhida (fecha o painel antes).
Future<void> showTracksPanel(
  BuildContext context,
  TrackManager manager, {
  required void Function(Track) onZoomToTrack,
  required void Function(List<Track>) onImported,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.panel,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _TracksPanel(
      manager: manager,
      onZoomToTrack: onZoomToTrack,
      onImported: onImported,
    ),
  );
}

class _TracksPanel extends StatelessWidget {
  const _TracksPanel({
    required this.manager,
    required this.onZoomToTrack,
    required this.onImported,
  });

  final TrackManager manager;
  final void Function(Track) onZoomToTrack;
  final void Function(List<Track>) onImported;

  Future<void> _import(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await manager.importFromPicker();
    if (result.imported == 0 && result.skipped == 0) return; // cancelou
    final parts = <String>[];
    if (result.imported > 0) parts.add('${result.imported} importada(s)');
    if (result.skipped > 0) parts.add('${result.skipped} ignorada(s)');
    messenger.showSnackBar(SnackBar(content: Text(parts.join(' · '))));
    // Move o mapa para as trilhas recém-importadas (aparecem ao fechar o painel).
    if (result.tracks.isNotEmpty) onImported(result.tracks);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return ListenableBuilder(
          listenable: manager,
          builder: (context, child) {
            final tracks = manager.tracks;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Trilhas',
                                style: TextStyle(
                                    fontSize: 24, fontWeight: FontWeight.bold)),
                            Text(
                              '${manager.visibleCount} de ${tracks.length} visíveis',
                              style: const TextStyle(color: AppColors.textDim),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => _import(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Importar'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SecondaryButton(
                          label: 'Mostrar todas',
                          onTap: tracks.isEmpty
                              ? null
                              : () => manager.setAllVisible(true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SecondaryButton(
                          label: 'Ocultar todas',
                          onTap: tracks.isEmpty
                              ? null
                              : () => manager.setAllVisible(false),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: tracks.isEmpty
                      ? _EmptyState(onImport: () => _import(context))
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                          itemCount: tracks.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 4),
                          itemBuilder: (context, i) => _TrackRow(
                            track: tracks[i],
                            manager: manager,
                            onZoomToTrack: onZoomToTrack,
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.track,
    required this.manager,
    required this.onZoomToTrack,
  });

  final Track track;
  final TrackManager manager;
  final void Function(Track) onZoomToTrack;

  @override
  Widget build(BuildContext context) {
    final dim = !track.visible;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _ColorSwatch(
            color: track.color,
            onTap: () => _editColor(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: dim ? AppColors.textDim : Colors.white,
                  ),
                ),
                Text(
                  '${track.distanceKm.toStringAsFixed(1)} km · ${track.fileName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.textDim, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => manager.toggleVisible(track.id),
            icon: Icon(
              track.visible ? Icons.visibility : Icons.visibility_off,
              color: track.visible ? AppColors.accent : AppColors.textDim,
            ),
          ),
          _TrackMenu(
            track: track,
            manager: manager,
            onZoomToTrack: onZoomToTrack,
          ),
        ],
      ),
    );
  }

  Future<void> _editColor(BuildContext context) async {
    final chosen = await showDialog<Color>(
      context: context,
      builder: (context) => _ColorPickerDialog(current: track.color),
    );
    if (chosen != null) await manager.setColor(track.id, chosen);
  }
}

class _TrackMenu extends StatelessWidget {
  const _TrackMenu({
    required this.track,
    required this.manager,
    required this.onZoomToTrack,
  });

  final Track track;
  final TrackManager manager;
  final void Function(Track) onZoomToTrack;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: AppColors.textDim),
      onSelected: (value) async {
        switch (value) {
          case 'show':
            onZoomToTrack(track);
          case 'rename':
            await _rename(context);
          case 'remove':
            await _confirmRemove(context);
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'show', child: Text('Mostrar no mapa')),
        PopupMenuItem(value: 'rename', child: Text('Renomear')),
        PopupMenuItem(value: 'remove', child: Text('Excluir')),
      ],
    );
  }

  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: track.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renomear trilha'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (name != null) await manager.rename(track.id, name);
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir trilha?'),
        content: Text('"${track.name}" será removida do app.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok == true) await manager.remove(track.id);
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.color, required this.onTap});
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.edit, size: 15, color: Colors.black54),
      ),
    );
  }
}

class _ColorPickerDialog extends StatelessWidget {
  const _ColorPickerDialog({required this.current});
  final Color current;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cor da trilha'),
      content: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final c in trackPalette)
            InkWell(
              onTap: () => Navigator.pop(context, c),
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: c.toARGB32() == current.toARGB32()
                        ? Colors.white
                        : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      onPressed: onTap,
      child: Text(label),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onImport});
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.route, size: 48, color: AppColors.textDim),
          const SizedBox(height: 12),
          const Text(
            'Nenhuma trilha ainda',
            style: TextStyle(fontSize: 16, color: AppColors.textDim),
          ),
          const SizedBox(height: 4),
          const Text(
            'Importe arquivos .gpx para vê-los no mapa.',
            style: TextStyle(color: AppColors.textDim),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
            ),
            onPressed: onImport,
            icon: const Icon(Icons.add),
            label: const Text('Importar GPX'),
          ),
        ],
      ),
    );
  }
}
