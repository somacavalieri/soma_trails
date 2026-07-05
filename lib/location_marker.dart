import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Ponto azul de localização, opcionalmente com seta de heading.
/// O círculo de precisão é desenhado à parte (CircleLayer, em metros).
class LocationDot extends StatelessWidget {
  const LocationDot({super.key, this.headingRadians});

  /// Direção de movimento em radianos (0 = norte). Nulo = parado: sem seta.
  final double? headingRadians;

  static const _blue = Color(0xFF2F7BFF);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (headingRadians != null)
            Transform.rotate(
              angle: headingRadians!,
              child: CustomPaint(
                size: const Size(44, 44),
                painter: _HeadingArrowPainter(color: _blue),
              ),
            ),
          // Ponto azul com borda branca (bem visível sobre satélite).
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: _blue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeadingArrowPainter extends CustomPainter {
  _HeadingArrowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = color;
    // Um triângulo apontando para cima (norte antes da rotação).
    final path = Path()
      ..moveTo(center.dx, 2)
      ..lineTo(center.dx - 7, 15)
      ..lineTo(center.dx + 7, 15)
      ..close();
    canvas.drawShadow(path, Colors.black54, 2, false);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_HeadingArrowPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Converte heading em graus (geolocator, 0=norte, horário) para radianos,
/// ou nulo quando não deve mostrar seta (parado / heading inválido).
double? headingToRadians(double headingDegrees, double speedMetersPerSec) {
  const movingThreshold = 0.6; // ~2 km/h: abaixo disso a direção é ruído
  if (speedMetersPerSec < movingThreshold) return null;
  if (headingDegrees.isNaN || headingDegrees < 0) return null;
  return headingDegrees * math.pi / 180.0;
}
