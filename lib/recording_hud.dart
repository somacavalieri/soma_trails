import 'package:flutter/material.dart';

import 'format.dart';
import 'theme.dart';
import 'track_recorder.dart';

/// HUD de gravação no topo (protótipo): chip "● Gravando"/"Pausado",
/// TEMPO e TRAJETO (km em laranja).
class RecordingHud extends StatelessWidget {
  const RecordingHud({super.key, required this.recorder});

  final TrackRecorder recorder;

  @override
  Widget build(BuildContext context) {
    final recording = recorder.isRecording;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panel.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x33FF6B6B)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _StatusChip(recording: recording),
          const SizedBox(width: 16),
          Expanded(
            child: _Metric(label: 'TEMPO', value: formatElapsed(recorder.elapsed)),
          ),
          Container(width: 1, height: 34, color: Colors.white12),
          Expanded(
            child: _Metric(
              label: 'TRAJETO',
              value: formatKm(recorder.distanceKm),
              valueColor: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.recording});
  final bool recording;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: recording ? const Color(0xFFFF4D4D) : AppColors.textDim,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          recording ? 'Gravando' : 'Pausado',
          style: TextStyle(
            color: recording ? const Color(0xFFFF6B6B) : AppColors.textDim,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: valueColor ?? Colors.white,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
              color: AppColors.textDim, fontSize: 11, letterSpacing: 1),
        ),
      ],
    );
  }
}
