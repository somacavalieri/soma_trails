import 'package:flutter/material.dart';

import 'download_controller.dart';
import 'format.dart';
import 'models/download_region.dart';
import 'theme.dart';

/// Tela "Regiões baixadas": armazenamento total + lista, com excluir.
class RegionsScreen extends StatelessWidget {
  const RegionsScreen({super.key, required this.controller});

  final OfflineDownloadController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Regiões baixadas'),
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, child) {
          final regions = controller.regions;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Armazenamento usado',
                              style: TextStyle(color: AppColors.textDim)),
                          const SizedBox(height: 4),
                          FutureBuilder<double>(
                            future: controller.totalStorageKiB(),
                            builder: (context, snap) => Text(
                              snap.hasData ? formatSizeKiB(snap.data!) : '…',
                              style: const TextStyle(
                                  fontSize: 26, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.storage, color: AppColors.ok, size: 36),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (regions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text('Nenhuma região baixada ainda.',
                        style: TextStyle(color: AppColors.textDim)),
                  ),
                )
              else ...[
                for (final r in regions)
                  _RegionCard(
                    region: r,
                    onRemove: () => _confirmRemove(context, r),
                  ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: () => _clearAll(context),
                    icon: const Icon(Icons.delete_sweep_outlined,
                        color: Color(0xFFFF6B6B)),
                    label: const Text('Limpar todos os downloads',
                        style: TextStyle(color: Color(0xFFFF6B6B))),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _clearAll(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpar todos os downloads?'),
        content: const Text(
            'Todas as regiões e seus tiles serão apagados, liberando o espaço. As trilhas e trajetos não são afetados.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Limpar tudo'),
          ),
        ],
      ),
    );
    if (ok == true) await controller.clearAllDownloads();
  }

  Future<void> _confirmRemove(BuildContext context, DownloadRegion r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir região?'),
        content: Text(r.shared
            ? '"${r.name}" sai da lista. Como os tiles são compartilhados, o espaço só é liberado ao remover a última região da fonte (ou em "Limpar todos os downloads").'
            : '"${r.name}" e ${formatSizeKiB(r.sizeKiB)} de cache serão removidos.'),
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
    if (ok == true) await controller.removeRegion(r.id);
  }
}

class _RegionCard extends StatelessWidget {
  const _RegionCard({required this.region, required this.onRemove});

  final DownloadRegion region;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.ok.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.map, color: AppColors.ok),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(region.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                Text(
                  '${formatSizeKiB(region.sizeKiB)} · z${region.minZoom}–${region.maxZoom} · ${formatWhen(region.createdAt)}',
                  style: const TextStyle(color: AppColors.textDim, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline, color: Color(0xFFFF6B6B)),
          ),
        ],
      ),
    );
  }
}
