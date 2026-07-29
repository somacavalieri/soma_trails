import 'package:flutter/material.dart';

import 'models/track.dart';
import 'models/track_folder.dart';
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

class _TracksPanel extends StatefulWidget {
  const _TracksPanel({
    required this.manager,
    required this.onZoomToTrack,
    required this.onImported,
  });

  final TrackManager manager;
  final void Function(Track) onZoomToTrack;
  final void Function(List<Track>) onImported;

  @override
  State<_TracksPanel> createState() => _TracksPanelState();
}

class _TracksPanelState extends State<_TracksPanel> {
  /// Pastas expandidas (abre tudo colapsado; estado não persiste).
  final Set<String> _expanded = {};

  Future<void> _import(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await widget.manager.importFromPicker();
    if (result.imported == 0 && result.skipped == 0) return; // cancelou
    final parts = <String>[];
    if (result.imported > 0) parts.add('${result.imported} importada(s)');
    if (result.skipped > 0) parts.add('${result.skipped} ignorada(s)');
    messenger.showSnackBar(SnackBar(content: Text(parts.join(' · '))));
    // Move o mapa para as trilhas recém-importadas (aparecem ao fechar o painel).
    if (result.tracks.isNotEmpty) widget.onImported(result.tracks);
  }

  Future<void> _createFolder(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nova pasta'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nome da pasta'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Criar'),
          ),
        ],
      ),
    );
    if (name != null) await widget.manager.createFolder(name);
  }

  Future<void> _renameFolder(BuildContext context, TrackFolder folder) async {
    final controller = TextEditingController(text: folder.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renomear pasta'),
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
    if (name != null) await widget.manager.renameFolder(folder.id, name);
  }

  Future<void> _deleteFolder(BuildContext context, TrackFolder folder) async {
    final manager = widget.manager;
    final inFolder = manager.tracksInFolder(folder.id);
    if (inFolder.isEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Excluir pasta?'),
          content: Text('"${folder.name}" está vazia.'),
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
      if (ok == true) await manager.deleteFolder(folder.id, deleteTracks: false);
      return;
    }
    final shared = inFolder.where((t) => t.folderIds.length > 1).length;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir pasta?'),
        content: Text(
          '"${folder.name}" tem ${inFolder.length} trilha(s).\n\n'
          '"Pasta e trilhas" remove os arquivos GPX do app'
          '${shared > 0 ? ' — $shared também estão em outras pastas e '
              'sumirão de lá' : ''}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'folder'),
            child: const Text('Só a pasta'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'both'),
            child: const Text('Pasta e trilhas'),
          ),
        ],
      ),
    );
    if (choice != null) {
      await manager.deleteFolder(folder.id, deleteTracks: choice == 'both');
    }
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
          listenable: widget.manager,
          builder: (context, child) {
            final manager = widget.manager;
            final tracks = manager.tracks;

            // Lista raiz achatada: pastas primeiro (com suas trilhas
            // indentadas quando expandidas), depois as trilhas avulsas.
            final rows = <Widget>[];
            for (final folder in manager.folders) {
              final inFolder = manager.tracksInFolder(folder.id);
              rows.add(_FolderRow(
                folder: folder,
                trackCount: inFolder.length,
                visibleCount: inFolder.where((t) => t.visible).length,
                visibility: manager.folderVisibility(folder.id),
                expanded: _expanded.contains(folder.id),
                onTap: () => setState(() {
                  _expanded.contains(folder.id)
                      ? _expanded.remove(folder.id)
                      : _expanded.add(folder.id);
                }),
                onToggleVisible: () => manager.setFolderVisible(
                  folder.id,
                  manager.folderVisibility(folder.id) != FolderVisibility.all,
                ),
                onRename: () => _renameFolder(context, folder),
                onDelete: () => _deleteFolder(context, folder),
              ));
              if (_expanded.contains(folder.id)) {
                rows.addAll(inFolder.map((t) => Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: _TrackRow(
                        track: t,
                        manager: manager,
                        onZoomToTrack: widget.onZoomToTrack,
                      ),
                    )));
              }
            }
            rows.addAll(manager.looseTracks.map((t) => _TrackRow(
                  track: t,
                  manager: manager,
                  onZoomToTrack: widget.onZoomToTrack,
                )));

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
                          label: 'Nova pasta',
                          onTap: () => _createFolder(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
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
                  child: tracks.isEmpty && manager.folders.isEmpty
                      ? _EmptyState(onImport: () => _import(context))
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                          itemCount: rows.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 4),
                          itemBuilder: (context, i) => rows[i],
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

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.folder,
    required this.trackCount,
    required this.visibleCount,
    required this.visibility,
    required this.expanded,
    required this.onTap,
    required this.onToggleVisible,
    required this.onRename,
    required this.onDelete,
  });

  final TrackFolder folder;
  final int trackCount;
  final int visibleCount;
  final FolderVisibility visibility;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onToggleVisible;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    // Olho agregado: aceso (todas), apagado (nenhuma), meio aceso (parcial).
    final (eyeIcon, eyeColor) = switch (visibility) {
      FolderVisibility.all => (Icons.visibility, AppColors.accent),
      FolderVisibility.none => (Icons.visibility_off, AppColors.textDim),
      FolderVisibility.partial =>
        (Icons.visibility, AppColors.accent.withValues(alpha: 0.45)),
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Icon(
              expanded ? Icons.expand_more : Icons.chevron_right,
              color: AppColors.textDim,
            ),
            const SizedBox(width: 4),
            const Icon(Icons.folder_outlined, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '$trackCount trilhas · $visibleCount visíveis',
                    style:
                        const TextStyle(color: AppColors.textDim, fontSize: 13),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: trackCount == 0 ? null : onToggleVisible,
              icon: Icon(eyeIcon, color: eyeColor),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.textDim),
              onSelected: (value) {
                switch (value) {
                  case 'rename':
                    onRename();
                  case 'delete':
                    onDelete();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'rename', child: Text('Renomear')),
                PopupMenuItem(value: 'delete', child: Text('Excluir')),
              ],
            ),
          ],
        ),
      ),
    );
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
    // SingleChildScrollView: com a linha "Nova pasta" a mais acima, o painel
    // aberto sem trilhas/pastas fica mais apertado (folga zero em telas
    // baixas); isso evita overflow em vez de estourar o layout.
    return Center(
      child: SingleChildScrollView(
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
      ),
    );
  }
}
