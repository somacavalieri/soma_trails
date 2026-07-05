import 'package:flutter/material.dart';

import '../theme.dart';

/// Barra inferior do protótipo: Trilhas · Meu trajeto · Baixar satélite · Ajustes.
/// Só "Trilhas" está funcional no passo 4; os outros chamam callbacks (ainda
/// "em breve") e serão ligados nos próximos passos.
class BottomNav extends StatelessWidget {
  const BottomNav({
    super.key,
    required this.visibleTrackCount,
    required this.recording,
    required this.onTrilhas,
    required this.onTrajeto,
    required this.onBaixar,
    required this.onAjustes,
  });

  final int visibleTrackCount;
  final bool recording;
  final VoidCallback onTrilhas;
  final VoidCallback onTrajeto;
  final VoidCallback onBaixar;
  final VoidCallback onAjustes;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      margin: EdgeInsets.fromLTRB(10, 0, 10, 10 + bottomInset),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.panel.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(
            icon: Icons.route,
            label: 'Trilhas',
            badge: visibleTrackCount > 0 ? '$visibleTrackCount' : null,
            onTap: onTrilhas,
          ),
          _NavItem(
            icon: Icons.timeline,
            label: 'Meu trajeto',
            dotIndicator: recording,
            onTap: onTrajeto,
          ),
          _NavItem(
            icon: Icons.download,
            label: 'Baixar satélite',
            onTap: onBaixar,
          ),
          _NavItem(
            icon: Icons.settings,
            label: 'Ajustes',
            onTap: onAjustes,
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
    this.dotIndicator = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? badge;

  /// Ponto vermelho pulsante (gravação em andamento).
  final bool dotIndicator;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, color: AppColors.accent, size: 24),
                  if (badge != null)
                    Positioned(
                      right: -10,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        constraints:
                            const BoxConstraints(minWidth: 18, minHeight: 18),
                        decoration: const BoxDecoration(
                          color: AppColors.ok,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          badge!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  if (dotIndicator)
                    Positioned(
                      right: -6,
                      top: -4,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF4D4D),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
