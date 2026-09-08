import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:soma_trails/theme.dart';

/// Abaixo desta rotação (em graus) o mapa é considerado "no norte":
/// a bússola some e o ponteiro não vale a pena mostrar.
const double kCompassNorthTolerance = 0.5;

/// Normaliza um ângulo em graus para a faixa `[0, 360)`.
///
/// O `%` do Dart com divisor positivo já devolve resultado em `[0, 360)`,
/// inclusive para entrada negativa: `-90 % 360 == 270`.
double normalizeDegrees(double degrees) => degrees % 360;

/// Giro mínimo (em graus) para sair de [from] e chegar em [to],
/// no intervalo `(-180, 180]`. Positivo = sentido horário.
///
/// É o que faz 350° → 0° girar +10°, e não −350°.
double shortestTurn(double from, double to) {
  final diff = normalizeDegrees(to - from);
  return diff > 180 ? diff - 360 : diff;
}

/// Desvio do norte, com sinal, em `(-180, 180]`.
///
/// A rotação da câmera do flutter_map **não é normalizada** (o gesto vai
/// somando), então ela pode valer −47,3 ou 412,8. Toda comparação com o
/// norte tem que passar por aqui: `359.7.abs()` seria "girado", mas o mapa
/// está a 0,3° do norte.
double offsetFromNorth(double rotation) => shortestTurn(0, rotation);

const List<String> _labels = ['N', 'NE', 'L', 'SE', 'S', 'SO', 'O', 'NO'];

/// Rótulo da direção que está **no topo da tela**, dado o `rotation` da
/// câmera do flutter_map (graus, horário).
///
/// O mapa gira no sentido horário, então o topo da tela aponta para
/// `-rotation`. Ex.: girado −90 (norte à esquerda) o topo é leste.
String compassLabel(double rotation) {
  final bearing = normalizeDegrees(-rotation);
  final index = ((bearing + 22.5) / 45).floor() % 8;
  return _labels[index];
}

/// Bússola do mapa: disco que gira junto com o mapa, ponteiro vermelho
/// apontando o norte e, no centro, a letra da direção que está para cima.
///
/// Só mostra a rotação — quem decide se ela aparece é quem a posiciona.
class MapCompass extends StatelessWidget {
  const MapCompass({
    super.key,
    required this.rotation,
    required this.onTap,
    this.highContrast = false,
  });

  /// Rotação da câmera do flutter_map, em graus (horário).
  final double rotation;

  /// Chamado ao tocar: espera-se que anime o mapa de volta ao norte.
  final VoidCallback onTap;

  /// Reforça o contraste (Ajustes → "Alto contraste").
  final bool highContrast;

  static const double size = 48;

  @override
  Widget build(BuildContext context) {
    final radians = rotation * math.pi / 180;
    return Semantics(
      button: true,
      label: 'Voltar o mapa para o norte',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.panel.withValues(alpha: highContrast ? 1.0 : 0.92),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: highContrast ? 0.9 : 0.25),
              width: highContrast ? 2 : 1,
            ),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Ponteiro e ticks giram junto com o mapa...
              Transform.rotate(
                angle: radians,
                child: CustomPaint(
                  size: const Size(size, size),
                  painter: _CompassNeedlePainter(highContrast: highContrast),
                ),
              ),
              // ...mas a letra fica sempre em pé.
              Text(
                compassLabel(rotation),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompassNeedlePainter extends CustomPainter {
  _CompassNeedlePainter({required this.highContrast});

  final bool highContrast;

  static const _north = Color(0xFFE03131);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;

    // Ticks nas quatro direções principais.
    final tick = Paint()
      ..color = Colors.white.withValues(alpha: highContrast ? 0.8 : 0.45)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final angle = i * math.pi / 2;
      final dir = Offset(math.sin(angle), -math.cos(angle));
      canvas.drawLine(
        center + dir * (radius - 7),
        center + dir * (radius - 4),
        tick,
      );
    }

    // Ponteiro vermelho para o norte (para cima antes da rotação).
    final needle = Path()
      ..moveTo(center.dx, 4)
      ..lineTo(center.dx - 4.5, 13)
      ..lineTo(center.dx + 4.5, 13)
      ..close();
    canvas.drawPath(needle, Paint()..color = _north);
  }

  @override
  bool shouldRepaint(_CompassNeedlePainter oldDelegate) =>
      oldDelegate.highContrast != highContrast;
}

/// Decide quando a bússola aparece e quando some.
///
/// Regra (igual à do Strava): aparece assim que o mapa sai do norte e,
/// quando volta ao norte, some [hideDelay] depois. Girar de novo nesse
/// meio-tempo cancela o desaparecimento.
class CompassVisibility extends ChangeNotifier {
  CompassVisibility({this.hideDelay = const Duration(seconds: 3)});

  final Duration hideDelay;

  Timer? _hideTimer;
  bool _visible = false;

  bool get visible => _visible;

  /// Chamar sempre que a rotação da câmera mudar.
  void onRotation(double rotation) {
    if (offsetFromNorth(rotation).abs() > kCompassNorthTolerance) {
      _hideTimer?.cancel();
      _hideTimer = null;
      _setVisible(true);
    } else if (_visible && _hideTimer == null) {
      _hideTimer = Timer(hideDelay, () {
        _hideTimer = null;
        _setVisible(false);
      });
    }
  }

  void _setVisible(bool value) {
    if (_visible == value) return;
    _visible = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _hideTimer = null;
    super.dispose();
  }
}
