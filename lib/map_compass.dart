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
