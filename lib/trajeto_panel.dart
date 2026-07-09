import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'format.dart';
import 'models/recorded_track.dart';
import 'theme.dart';
import 'track_recorder.dart';

/// Abre o painel "Meu trajeto" (bottom sheet): gravar novo + trajetos salvos.
Future<void> showTrajetoPanel(
  BuildContext context,
  TrackRecorder recorder, {
  required Set<String> shownIds,
  required VoidCallback onStartRecording,
  required void Function(RecordedTrack) onToggleTrack,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.panel,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _TrajetoPanel(
      recorder: recorder,
      shownIds: shownIds,
      onStartRecording: onStartRecording,
      onToggleTrack: onToggleTrack,
    ),
  );
}

class _TrajetoPanel extends StatelessWidget {
  const _TrajetoPanel({
    required this.recorder,
    required this.shownIds,
    required this.onStartRecording,
    required this.onToggleTrack,
  });

  final TrackRecorder recorder;
  final Set<String> shownIds;
  final VoidCallback onStartRecording;
  final void Function(RecordedTrack) onToggleTrack;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return ListenableBuilder(
          listenable: recorder,
          builder: (context, child) {
            final saved = recorder.saved;
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                Row(
                  children: [
                    const Icon(Icons.timeline, color: AppColors.accent),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('Meu trajeto',
                            style: TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold)),
                        Text('Rastro de orientação · de onde eu vim',
                            style: TextStyle(
                                color: AppColors.textDim, fontSize: 13)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _RecordButton(
                  recorder: recorder,
                  onStartRecording: () {
                    Navigator.pop(context);
                    onStartRecording();
                  },
                ),
                const SizedBox(height: 20),
                const Text('TRAJETOS SALVOS',
                    style: TextStyle(
                        color: AppColors.textDim,
                        fontSize: 12,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (saved.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('Nenhum trajeto salvo ainda.',
                          style: TextStyle(color: AppColors.textDim)),
                    ),
                  )
                else
                  for (final t in saved)
                    _SavedRow(
                      track: t,
                      recorder: recorder,
                      shown: shownIds.contains(t.id),
                      onToggle: () {
                        Navigator.pop(context);
                        onToggleTrack(t);
                      },
                    ),
              ],
            );
          },
        );
      },
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.recorder, required this.onStartRecording});
  final TrackRecorder recorder;
  final VoidCallback onStartRecording;

  @override
  Widget build(BuildContext context) {
    if (recorder.isActive) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0x22FF6B6B),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x55FF6B6B)),
        ),
        child: Center(
          child: Text(
            recorder.isRecording
                ? 'Gravação em andamento — use os botões no mapa'
                : 'Gravação pausada — retome pelos botões no mapa',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFFF6B6B)),
          ),
        ),
      );
    }
    return InkWell(
      onTap: onStartRecording,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0x14FF6B6B),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0x66FF6B6B),
            width: 1.5,
            style: BorderStyle.solid,
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.fiber_manual_record, color: Color(0xFFFF4D4D), size: 16),
            SizedBox(width: 10),
            Text('Gravar novo trajeto',
                style: TextStyle(
                    color: Color(0xFFFF6B6B),
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _SavedRow extends StatelessWidget {
  const _SavedRow({
    required this.track,
    required this.recorder,
    required this.shown,
    required this.onToggle,
  });

  final RecordedTrack track;
  final TrackRecorder recorder;
  final bool shown;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0x22F57C1F),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.timeline, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(formatWhen(track.startedAt),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    Text(
                      '${formatKm(track.distanceKm)} · ${formatDurationShort(track.duration)}',
                      style: const TextStyle(
                          color: AppColors.textDim, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: shown ? AppColors.accent : Colors.white,
                    side: BorderSide(
                        color: shown
                            ? AppColors.accent
                            : Colors.white.withValues(alpha: 0.12)),
                  ),
                  onPressed: onToggle,
                  icon: Icon(shown ? Icons.visibility_off : Icons.location_on,
                      size: 18),
                  label: Text(shown ? 'Ocultar' : 'Mostrar'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _export(context),
                icon: const Icon(Icons.ios_share, color: AppColors.textDim),
              ),
              IconButton(
                onPressed: () => _confirmRemove(context),
                icon: const Icon(Icons.delete_outline, color: Color(0xFFFF6B6B)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final gpx = await recorder.gpxOf(track.id);
    if (gpx == null) return;
    final safeName =
        track.name.replaceAll(RegExp(r'[^\w\- ]'), '').trim().replaceAll(' ', '_');
    final path = await FilePicker.saveFile(
      dialogTitle: 'Exportar trajeto',
      fileName: '$safeName.gpx',
      type: FileType.custom,
      allowedExtensions: ['gpx'],
      bytes: Uint8List.fromList(utf8.encode(gpx)),
    );
    messenger.showSnackBar(
      SnackBar(content: Text(path == null ? 'Exportação cancelada' : 'Trajeto exportado')),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir trajeto?'),
        content: Text('"${track.name}" será removido.'),
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
    if (ok == true) await recorder.removeSaved(track.id);
  }
}
