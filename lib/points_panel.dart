import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'models/map_point.dart';
import 'point_manager.dart';
import 'theme.dart';

/// Dados retornados pelo diálogo de criação de ponto.
class NewPointData {
  const NewPointData(this.name, this.category);
  final String name;
  final PointCategory category;
}

/// Diálogo para criar um ponto: nome (opcional) + categoria.
Future<NewPointData?> showAddPointDialog(BuildContext context, LatLng at) {
  return showDialog<NewPointData>(
    context: context,
    builder: (context) => _AddPointDialog(at: at),
  );
}

class _AddPointDialog extends StatefulWidget {
  const _AddPointDialog({required this.at});
  final LatLng at;

  @override
  State<_AddPointDialog> createState() => _AddPointDialogState();
}

class _AddPointDialogState extends State<_AddPointDialog> {
  final _controller = TextEditingController();
  PointCategory _category = PointCategory.outro;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.panel,
      title: const Text('Marcar ponto'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nome (opcional)',
              hintText: 'Ex.: bifurcação onde errei',
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in PointCategory.values)
                ChoiceChip(
                  label: Text(c.label),
                  avatar: Icon(c.icon, size: 18, color: c.color),
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = c),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${widget.at.latitude.toStringAsFixed(5)}, ${widget.at.longitude.toStringAsFixed(5)}',
            style: const TextStyle(color: AppColors.textDim, fontSize: 12),
          ),
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
          onPressed: () =>
              Navigator.pop(context, NewPointData(_controller.text, _category)),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

/// Painel "Pontos" (bottom sheet): lista dos pontos marcados.
Future<void> showPointsPanel(
  BuildContext context,
  PointManager manager, {
  required void Function(MapPoint) onShow,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.panel,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _PointsPanel(manager: manager, onShow: onShow),
  );
}

class _PointsPanel extends StatelessWidget {
  const _PointsPanel({required this.manager, required this.onShow});

  final PointManager manager;
  final void Function(MapPoint) onShow;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return ListenableBuilder(
          listenable: manager,
          builder: (context, child) {
            final points = manager.points;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on, color: AppColors.accentAlt),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Pontos',
                                style: TextStyle(
                                    fontSize: 22, fontWeight: FontWeight.bold)),
                            Text('${points.length} marcados no mapa',
                                style: const TextStyle(
                                    color: AppColors.textDim, fontSize: 13)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Concluir'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: points.isEmpty
                      ? const _EmptyPoints()
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                          itemCount: points.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 6),
                          itemBuilder: (context, i) => _PointRow(
                            point: points[i],
                            manager: manager,
                            onShow: () {
                              Navigator.pop(context);
                              onShow(points[i]);
                            },
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

class _PointRow extends StatelessWidget {
  const _PointRow({
    required this.point,
    required this.manager,
    required this.onShow,
  });

  final MapPoint point;
  final PointManager manager;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration:
                BoxDecoration(color: point.category.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(point.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                Text(
                  '${point.point.latitude.toStringAsFixed(4)}, ${point.point.longitude.toStringAsFixed(4)} · ${point.category.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textDim, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onShow,
            icon: const Icon(Icons.location_on, color: AppColors.textDim),
          ),
          IconButton(
            onPressed: () => _confirmRemove(context),
            icon: const Icon(Icons.delete_outline, color: Color(0xFFFF6B6B)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir ponto?'),
        content: Text('"${point.displayName}" será removido.'),
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
    if (ok == true) await manager.remove(point.id);
  }
}

class _EmptyPoints extends StatelessWidget {
  const _EmptyPoints();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_on, size: 44, color: AppColors.textDim),
          SizedBox(height: 12),
          Text('Nenhum ponto ainda',
              style: TextStyle(fontSize: 16, color: AppColors.textDim)),
          SizedBox(height: 4),
          Text('Segure no mapa para marcar um ponto.',
              style: TextStyle(color: AppColors.textDim)),
        ],
      ),
    );
  }
}
