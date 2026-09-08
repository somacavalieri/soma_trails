# Rotação do mapa + bússola — plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** permitir girar o mapa com dois dedos e oferecer uma bússola que mostra a orientação atual e, ao ser tocada, anima a volta ao norte e some 3 s depois.

**Architecture:** rotação nativa do `flutter_map` (destravar o `InteractiveFlag.rotate` com corrida de gestos e limiar), um widget de bússola sem estado em `lib/map_compass.dart` (mais helpers puros e um controlador de visibilidade), e a orquestração — estado da rotação, timer dos 3 s e animação de volta ao norte — dentro do `_MapScreenState` que já existe.

**Tech Stack:** Flutter 3.44.4 / Dart 3.12.2, `flutter_map` 8.3.1, `flutter_test`. Nenhuma dependência nova.

**Spec:** `docs/superpowers/specs/2026-09-08-rotacao-do-mapa-design.md`

## Global Constraints

- **Sem dependência nova.** O stack é travado pelo `CLAUDE.md`; a animação é feita com `AnimationController` do próprio Flutter.
- **Sinal da rotação:** o flutter_map aplica `Transform.rotate(angle: camera.rotationRad)`, que gira no **sentido horário**. Logo o norte fica na direção `+rotation` na tela e **a direção no topo da tela é `-rotation`**. Rotação `90` ⇒ topo aponta para Oeste ("O"); rotação `-90` ⇒ topo aponta para Leste ("L").
- **Rótulos em português:** `N, NE, L, SE, S, SO, O, NO` (Leste = "L", Oeste = "O"), faixas de 45° centradas em cada direção.
- **Tolerância de norte:** `kCompassNorthTolerance = 0.5` graus. Abaixo disso o mapa é considerado "no norte".
- **Snap:** ao fim de um gesto, desvio do norte menor que `1.0` grau é zerado.
- **`camera.rotation` não é normalizada:** o gesto acumula (`_camera.rotation + diff`), então o valor pode ser `-47.3` ou `412.8`. Nunca comparar `rotation.abs()` com uma tolerância — usar sempre `offsetFromNorth`.
- **Atraso para esconder:** 3 s; fade de 200 ms.
- **Girar não desliga o modo "seguir".** A condição de unfollow continua sendo exatamente `event.source == MapEventSource.onDrag`.
- **Nada de persistência, nada de chave nos Ajustes, nada de course-up.**
- **Idioma:** todo comentário, docstring e string de UI em português (padrão do repo).
- Verificação em todo commit: `flutter analyze` sem issues e `flutter test` verde.

---

### Task 1: Helpers puros de ângulo e rótulo

**Files:**
- Create: `lib/map_compass.dart`
- Test: `test/map_compass_test.dart`

**Interfaces:**
- Consumes: nada.
- Produces:
  - `const double kCompassNorthTolerance = 0.5;`
  - `double normalizeDegrees(double degrees)` → sempre em `[0, 360)`.
  - `double shortestTurn(double from, double to)` → giro mínimo de `from` até `to`, em `(-180, 180]`.
  - `double offsetFromNorth(double rotation)` → desvio do norte com sinal, em `(-180, 180]`.
  - `String compassLabel(double rotation)` → rótulo da direção no topo da tela.

- [ ] **Step 1: Escrever os testes que falham**

Criar `test/map_compass_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:soma_trails/map_compass.dart';

void main() {
  group('normalizeDegrees', () {
    test('mantém a faixa [0, 360)', () {
      expect(normalizeDegrees(0), 0);
      expect(normalizeDegrees(359.5), closeTo(359.5, 0.001));
      expect(normalizeDegrees(360), 0);
      expect(normalizeDegrees(400), closeTo(40, 0.001));
      expect(normalizeDegrees(-90), closeTo(270, 0.001));
      expect(normalizeDegrees(-450), closeTo(270, 0.001));
    });
  });

  group('shortestTurn', () {
    test('vai pelo caminho curto', () {
      expect(shortestTurn(350, 0), closeTo(10, 0.001));
      expect(shortestTurn(10, 0), closeTo(-10, 0.001));
      expect(shortestTurn(0, 0), closeTo(0, 0.001));
      expect(shortestTurn(-350, 0), closeTo(-10, 0.001));
    });

    test('meia-volta resolve para +180, não -180', () {
      expect(shortestTurn(180, 0), closeTo(180, 0.001));
    });
  });

  group('offsetFromNorth', () {
    test('devolve o desvio com sinal, aceitando rotação acumulada', () {
      expect(offsetFromNorth(0), closeTo(0, 0.001));
      expect(offsetFromNorth(0.4), closeTo(0.4, 0.001));
      // O flutter_map acumula a rotação: 359.7 é "quase norte", não "girado".
      expect(offsetFromNorth(359.7), closeTo(-0.3, 0.001));
      expect(offsetFromNorth(720.2), closeTo(0.2, 0.001));
      expect(offsetFromNorth(-90), closeTo(-90, 0.001));
      expect(offsetFromNorth(412.8), closeTo(52.8, 0.001));
    });
  });

  group('compassLabel', () {
    test('norte quando o mapa não está girado', () {
      expect(compassLabel(0), 'N');
      expect(compassLabel(0.4), 'N');
      expect(compassLabel(-0.4), 'N');
    });

    test('a direção no topo da tela é -rotation', () {
      // Mapa girado -90 (norte à esquerda) => topo aponta para leste.
      expect(compassLabel(-90), 'L');
      // Mapa girado +90 (norte à direita) => topo aponta para oeste.
      expect(compassLabel(90), 'O');
      expect(compassLabel(-45), 'NE');
      expect(compassLabel(45), 'NO');
      expect(compassLabel(180), 'S');
      expect(compassLabel(-135), 'SE');
      expect(compassLabel(135), 'SO');
    });

    test('as bordas das faixas de 45 graus caem para o lado certo', () {
      expect(compassLabel(-22.4), 'N');
      expect(compassLabel(-22.6), 'NE');
      expect(compassLabel(-337.6), 'N');
    });
  });
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/map_compass_test.dart`
Expected: FAIL na compilação — `Target of URI doesn't exist: 'package:soma_trails/map_compass.dart'`.

- [ ] **Step 3: Implementar os helpers**

Criar `lib/map_compass.dart`:

```dart
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
```

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test test/map_compass_test.dart`
Expected: PASS, todos os testes dos três grupos.

- [ ] **Step 5: Analisar**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commitar**

```bash
git add lib/map_compass.dart test/map_compass_test.dart
git commit -m "feat: helpers de ângulo e rótulo da bússola"
```

---

### Task 2: Widget da bússola

**Files:**
- Modify: `lib/map_compass.dart`
- Test: `test/map_compass_test.dart`

**Interfaces:**
- Consumes: `compassLabel` (Task 1).
- Produces: `class MapCompass extends StatelessWidget` com o construtor
  `const MapCompass({super.key, required double rotation, required VoidCallback onTap, bool highContrast = false})`.
  Tamanho fixo de 48×48 px.

- [ ] **Step 1: Escrever os testes que falham**

Acrescentar ao final de `test/map_compass_test.dart` (dentro do `main()`, depois dos grupos existentes):

```dart
  group('MapCompass', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

    testWidgets('mostra a letra da direção no topo da tela', (tester) async {
      await tester.pumpWidget(wrap(MapCompass(rotation: -90, onTap: () {})));
      expect(find.text('L'), findsOneWidget);

      await tester.pumpWidget(wrap(MapCompass(rotation: 90, onTap: () {})));
      expect(find.text('O'), findsOneWidget);
    });

    testWidgets('avisa quando é tocada', (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(MapCompass(rotation: 45, onTap: () => taps++)));
      await tester.tap(find.byType(MapCompass));
      expect(taps, 1);
    });

    // `testWidgets` já roda com semanticsEnabled: true e cuida do handle
    // sozinho — criar um `ensureSemantics()` aqui quebraria a verificação
    // de descarte que ele faz antes dos teardowns.
    testWidgets('ocupa 48x48 e é anunciada como botão', (tester) async {
      await tester.pumpWidget(wrap(MapCompass(rotation: 45, onTap: () {})));
      expect(tester.getSize(find.byType(MapCompass)), const Size(48, 48));

      final semantics = tester.getSemantics(find.byType(MapCompass));
      expect(semantics.flagsCollection.isButton, isTrue);
    });
  });
```

Acrescentar o import que falta no topo do arquivo de teste:

```dart
import 'package:flutter/material.dart';
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/map_compass_test.dart`
Expected: FAIL — `Undefined class 'MapCompass'`. Os testes da Task 1 continuam passando.

- [ ] **Step 3: Implementar o widget**

Acrescentar ao final de `lib/map_compass.dart`, com estes imports no topo do arquivo:

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:soma_trails/theme.dart';
```

O widget:

```dart
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
```

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test test/map_compass_test.dart`
Expected: PASS, incluindo o grupo `MapCompass`.

- [ ] **Step 5: Analisar**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commitar**

```bash
git add lib/map_compass.dart test/map_compass_test.dart
git commit -m "feat: widget da bússola do mapa"
```

---

### Task 3: Controlador de visibilidade (a regra dos 3 s)

**Files:**
- Modify: `lib/map_compass.dart`
- Test: `test/map_compass_test.dart`

**Interfaces:**
- Consumes: `kCompassNorthTolerance`, `offsetFromNorth` (Task 1).
- Produces: `class CompassVisibility extends ChangeNotifier` com
  `CompassVisibility({Duration hideDelay = const Duration(seconds: 3)})`,
  `bool get visible`, `void onRotation(double rotation)`, `void dispose()`.

A lógica: rotação fora do norte ⇒ visível na hora e cancela qualquer timer pendente. Rotação de volta ao norte ⇒ agenda esconder daqui a `hideDelay` (sem reagendar se já houver timer pendente, para 3 s significarem 3 s).

- [ ] **Step 1: Escrever os testes que falham**

Acrescentar ao final de `test/map_compass_test.dart`, dentro do `main()`:

```dart
  group('CompassVisibility', () {
    test('começa escondida', () {
      final c = CompassVisibility();
      addTearDown(c.dispose);
      expect(c.visible, isFalse);
    });

    test('aparece na hora quando o mapa sai do norte', () {
      final c = CompassVisibility();
      addTearDown(c.dispose);
      var notifications = 0;
      c.addListener(() => notifications++);

      c.onRotation(30);
      expect(c.visible, isTrue);
      expect(notifications, 1);
    });

    test('ignora rotação dentro da tolerância do norte', () {
      final c = CompassVisibility();
      addTearDown(c.dispose);
      c.onRotation(0.4);
      expect(c.visible, isFalse);
    });

    test('entende rotação acumulada perto do norte', () {
      final c = CompassVisibility();
      addTearDown(c.dispose);
      // 359.7 é 0,3° do norte, não 359,7° de desvio.
      c.onRotation(359.7);
      expect(c.visible, isFalse);
      c.onRotation(360.9);
      expect(c.visible, isTrue);
    });

    test('some depois do atraso quando volta ao norte', () async {
      final c = CompassVisibility(hideDelay: const Duration(milliseconds: 30));
      addTearDown(c.dispose);

      c.onRotation(30);
      c.onRotation(0);
      expect(c.visible, isTrue, reason: 'ainda visível durante o atraso');

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(c.visible, isFalse);
    });

    test('girar de novo cancela o esconder agendado', () async {
      final c = CompassVisibility(hideDelay: const Duration(milliseconds: 30));
      addTearDown(c.dispose);

      c.onRotation(30);
      c.onRotation(0);
      c.onRotation(15);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(c.visible, isTrue);
    });

    test('dispose cancela o timer pendente', () async {
      final c = CompassVisibility(hideDelay: const Duration(milliseconds: 30));
      c.onRotation(30);
      c.onRotation(0);
      c.dispose();

      // Se o timer sobrevivesse, ele chamaria notifyListeners() depois do
      // dispose e o teste quebraria com "A CompassVisibility was used after
      // being disposed".
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
  });
```

Acrescentar o import que falta no topo do arquivo de teste:

```dart
import 'dart:async';
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `flutter test test/map_compass_test.dart`
Expected: FAIL — `Undefined class 'CompassVisibility'`.

- [ ] **Step 3: Implementar o controlador**

Acrescentar ao final de `lib/map_compass.dart` (e `import 'dart:async';` no topo):

```dart
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
```

- [ ] **Step 4: Rodar e ver passar**

Run: `flutter test test/map_compass_test.dart`
Expected: PASS, incluindo os seis testes de `CompassVisibility`.

- [ ] **Step 5: Analisar**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: Commitar**

```bash
git add lib/map_compass.dart test/map_compass_test.dart
git commit -m "feat: regra de visibilidade da bússola (some 3s depois)"
```

---

### Task 4: Destravar o gesto de girar e acompanhar a rotação

**Files:**
- Modify: `lib/map_screen.dart` (campo de estado perto da linha 53; `_onMapEvent` na linha 156; `interactionOptions` na linha 521)

**Interfaces:**
- Consumes: `kCompassNorthTolerance` de `lib/map_compass.dart` (Task 1).
- Produces: campo `double _rotation` em `_MapScreenState`, mantido em dia com `event.camera.rotation`.

Nesta task o mapa já gira, mas ainda não há bússola na tela: a verificação é `flutter analyze`, `flutter test` e um teste manual do gesto.

- [ ] **Step 1: Trocar as opções de interação**

Em `lib/map_screen.dart`, substituir:

```dart
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
```

por:

```dart
              // Girar é liberado, mas só ganha a "corrida" de gestos depois de
              // uma torção de 20°: sem isso um pinch-zoom torto já entortava o
              // mapa. rotationWinGestures = all mantém o zoom disponível depois
              // que a rotação ganha, sem precisar levantar os dedos.
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
                enableMultiFingerGestureRace: true,
                rotationThreshold: 20,
                rotationWinGestures: MultiFingerGesture.all,
              ),
```

- [ ] **Step 2: Acrescentar o campo de rotação**

Em `lib/map_screen.dart`, logo abaixo de `double _zoom = 13;`:

```dart
  /// Rotação atual da câmera em graus (horário). 0 = norte para cima.
  double _rotation = 0;
```

E no topo do arquivo, junto dos outros imports do projeto:

```dart
import 'package:soma_trails/map_compass.dart';
```

- [ ] **Step 3: Acompanhar a rotação no `_onMapEvent`**

Substituir o corpo de `_onMapEvent` por:

```dart
  void _onMapEvent(MapEvent event) {
    final z = event.camera.zoom;
    var r = event.camera.rotation;

    // Snap: um resto de 0,4° depois do gesto deixaria a bússola visível para
    // sempre. Ao terminar de girar, perto do norte vira norte.
    if (event.source == MapEventSource.multiFingerEnd &&
        offsetFromNorth(r).abs() < 1) {
      _mapController.rotate(0);
      r = 0;
    }

    final rotated = (r - _rotation).abs() > kCompassNorthTolerance;
    final unfollow = _follow && event.source == MapEventSource.onDrag;
    // Rebuild quando o zoom exibido muda, quando a rotação muda o bastante
    // para a bússola acompanhar, ou ao sair do modo seguir.
    // Girar de propósito NÃO desliga o seguir — só arrastar.
    if (unfollow || rotated || z.round() != _zoom.round()) {
      setState(() {
        if (unfollow) _follow = false;
        _zoom = z;
        _rotation = r;
      });
    } else {
      _zoom = z;
      _rotation = r;
    }
  }
```

- [ ] **Step 4: Analisar e rodar os testes**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` e todos os testes passando.

- [ ] **Step 5: Conferir no aparelho**

Run: `flutter run --release` (S24 Ultra conectado) ou instalar o APK.
Expected:
- dois dedos girando ⇒ o mapa gira;
- pinch-zoom **sem torcer** ⇒ o mapa **não** gira;
- depois de girar, ainda dá para dar zoom no mesmo gesto;
- com o modo seguir ligado (FAB preenchido), girar **não** desliga o seguir.

- [ ] **Step 6: Commitar**

```bash
git add lib/map_screen.dart
git commit -m "feat: girar o mapa com dois dedos"
```

---

### Task 5: Manter os pinos em pé com o mapa girado

**Files:**
- Modify: `lib/map_screen.dart` (`_pointMarkers`, `_waypointMarkers`, o marcador `_StartPin` dentro do `build`)

**Interfaces:**
- Consumes: a rotação já liberada na Task 4.
- Produces: nada de novo — só a propriedade `rotate: true` nos marcadores certos.

`Marker.rotate` significa **contra-rotacionar para ficar em pé**, e o default é `false` (o marcador gira junto com o mapa). Os pinos precisam de `true`; o `LocationDot` precisa continuar em `false`.

- [ ] **Step 1: Pinos dos pontos marcados**

Em `_pointMarkers()`, no `Marker(...)`, acrescentar depois de `height: 34,`:

```dart
          rotate: true,
```

- [ ] **Step 2: Pinos dos waypoints do GPX**

Em `_waypointMarkers()`, no `Marker(...)`, acrescentar depois de `alignment: Alignment.topCenter,`:

```dart
            rotate: true,
```

- [ ] **Step 3: Pino de início do trajeto**

No `build`, no `Marker` que usa `child: const _StartPin()`, acrescentar depois de `height: 22,`:

```dart
                      rotate: true,
```

- [ ] **Step 4: NÃO mexer no LocationDot**

Confirmar que o `Marker` com `child: LocationDot(...)` continua **sem** `rotate` (default `false`). A seta de heading é geográfica (0 = norte): girando junto com o mapa ela segue apontando para a direção certa, sem nenhuma compensação. `lib/location_marker.dart` não é tocado nesta task nem em nenhuma outra deste plano.

- [ ] **Step 5: Analisar e rodar os testes**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` e todos os testes passando.

- [ ] **Step 6: Conferir no aparelho**

Expected, com o mapa girado ~90°:
- pinos de pontos, waypoints e início do trajeto ficam **em pé**;
- a seta azul de heading aponta para a direção real do movimento (comparar com a bússola do celular ou com a direção da trilha).

- [ ] **Step 7: Commitar**

```bash
git add lib/map_screen.dart
git commit -m "fix: pinos ficam em pé com o mapa girado"
```

---

### Task 6: Bússola na tela + volta ao norte animada

**Files:**
- Modify: `lib/map_screen.dart` (declaração do `_MapScreenState`, `initState`, `dispose`, `build`)

**Interfaces:**
- Consumes: `MapCompass` (Task 2), `CompassVisibility` (Task 3), `_rotation` (Task 4), `shortestTurn` (Task 1).
- Produces: nada consumido por outras tasks — é a última peça de código.

- [ ] **Step 1: Adicionar o mixin de ticker**

Trocar a declaração do estado:

```dart
class _MapScreenState extends State<MapScreen> {
```

por:

```dart
class _MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin {
```

- [ ] **Step 2: Campos da bússola**

Logo abaixo do campo `_rotation`:

```dart
  /// Controla quando a bússola aparece e quando some (3 s no norte).
  final _compass = CompassVisibility();

  /// Animação de volta ao norte disparada pelo toque na bússola.
  AnimationController? _northAnimation;
```

- [ ] **Step 3: Ligar e desligar o controlador**

Em `initState`, junto dos outros `addListener`:

```dart
    _compass.addListener(_onChange);
```

Em `dispose`, antes de `_mapController.dispose();`:

```dart
    _compass.removeListener(_onChange);
    _compass.dispose();
    _northAnimation?.dispose();
```

- [ ] **Step 4: Alimentar o controlador e cancelar a animação no `_onMapEvent`**

Dentro de `_onMapEvent`, logo depois do bloco do snap (Step 3 da Task 4) e antes de `final rotated = ...`:

```dart
    // Encostou no mapa no meio da animação? A animação para onde está.
    if (_northAnimation != null &&
        (event.source == MapEventSource.multiFingerGestureStart ||
            event.source == MapEventSource.onMultiFinger ||
            event.source == MapEventSource.dragStart ||
            event.source == MapEventSource.onDrag)) {
      _cancelNorthAnimation();
    }

    _compass.onRotation(r);
```

Os eventos emitidos pela própria animação têm origem `MapEventSource.mapController`, então ela não se cancela sozinha.

- [ ] **Step 5: Implementar a volta ao norte**

Acrescentar estes dois métodos logo depois de `_onMapEvent`:

```dart
  void _cancelNorthAnimation() {
    _northAnimation?.dispose();
    _northAnimation = null;
  }

  /// Toque na bússola: anima o mapa de volta ao norte pelo caminho curto.
  void _rotateToNorth() {
    _cancelNorthAnimation();
    final from = _rotation;
    final turn = shortestTurn(from, 0);
    if (turn.abs() < kCompassNorthTolerance) {
      _mapController.rotate(0);
      return;
    }

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _northAnimation = controller;

    controller.addListener(() {
      final t = Curves.easeOutCubic.transform(controller.value);
      _mapController.rotate(from + turn * t);
    });

    // O TickerFuture do forward() nunca completa se a animação for cancelada
    // (o dispose em _cancelNorthAnimation), então isto só roda no fim de
    // verdade — e roda num microtask, fora da notificação do status, que é
    // onde dar dispose no controller estouraria.
    controller.forward().whenComplete(() {
      // A guarda de identidade evita que a conclusão de uma animação
      // obsoleta dê dispose no controller de uma animação nova.
      if (!mounted || _northAnimation != controller) return;
      _mapController.rotate(0);
      _cancelNorthAnimation();
    });
  }
```

- [ ] **Step 6: Posicionar a bússola no `build`**

No `Stack` do `build`, imediatamente **antes** do `Positioned` do FAB "Recentralizar" (o do comentário `// Recentralizar`):

```dart
          // Bússola: aparece quando o mapa sai do norte, logo acima do
          // botão de recentralizar (que não se mexe). Some 3 s depois de
          // voltar ao norte.
          Positioned(
            right: 16,
            bottom: 96 + 56 + 12 + bottomInset,
            child: IgnorePointer(
              ignoring: !_compass.visible,
              child: AnimatedOpacity(
                opacity: _compass.visible ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: MapCompass(
                  rotation: _rotation,
                  highContrast: _settings.highContrast,
                  onTap: _rotateToNorth,
                ),
              ),
            ),
          ),
```

(`96` é o `bottom` do FAB, `56` a altura dele e `12` a folga entre os dois.)

- [ ] **Step 7: Analisar e rodar os testes**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` e todos os testes passando.

- [ ] **Step 8: Conferir no aparelho**

Expected:
- app aberto sem girar nada ⇒ **nenhuma** bússola na tela;
- ao girar ⇒ bússola aparece acima do FAB laranja, ponteiro vermelho no norte, letra certa (girando até o norte ficar à esquerda, lê-se "L");
- tocar ⇒ o mapa volta ao norte de forma suave (~300 ms), pelo caminho curto;
- 3 s depois ⇒ some com fade;
- girar durante os 3 s ⇒ ela fica;
- encostar no mapa durante a animação ⇒ a animação para onde está, sem tranco;
- com "Alto contraste" ligado nos Ajustes ⇒ borda e fundo mais fortes.

- [ ] **Step 9: Commitar**

```bash
git add lib/map_screen.dart
git commit -m "feat: bússola do mapa com volta ao norte animada"
```

---

### Task 7: Atualizar PRD, CLAUDE.md e o board

**Files:**
- Modify: `docs/prd.md:35`, `docs/prd.md:58`
- Modify: `CLAUDE.md` (seções "Architecture (planned)" e "Scope discipline")

**Interfaces:**
- Consumes: a feature pronta das tasks 1–6.
- Produces: nada de código.

O PRD e o `CLAUDE.md` travam "norte fixo / rotação fora do escopo" — depois deste plano isso está desatualizado e vai confundir qualquer sessão futura.

- [ ] **Step 1: Corrigir o PRD**

Em `docs/prd.md:35`, trocar:

```
- **Orientação do mapa: norte fixo.** A seta de posição gira com o heading; o mapa não rotaciona. Course-up (mapa girando com o movimento) fica no backlog.
```

por:

```
- **Orientação do mapa: norte por padrão, rotação manual.** O mapa abre no norte e pode ser girado com dois dedos (limiar de 20° para não girar sem querer no pinch-zoom); uma bússola aparece quando ele sai do norte, volta ao norte no toque e some 3 s depois. A rotação não é persistida entre aberturas. Course-up (mapa girando sozinho com o movimento) continua no backlog. Ver `docs/superpowers/specs/2026-09-08-rotacao-do-mapa-design.md`.
```

Em `docs/prd.md:58`, remover `rotação do mapa (course-up), ` da lista de itens fora de escopo e acrescentar, no lugar, `course-up (mapa girando sozinho com o movimento — a rotação manual por gesto está implementada), `.

- [ ] **Step 2: Corrigir o CLAUDE.md**

Na seção "Architecture (planned)", trocar:

```
Map is north-up (no rotation); the position arrow rotates with heading.
```

por:

```
Map opens north-up and can be rotated with a two-finger gesture (20° threshold; a compass appears when off-north, taps back to north, hides after 3 s; rotation is not persisted). The position arrow rotates with heading.
```

Na seção "Scope discipline", remover `map rotation (course-up)` da lista e escrever `course-up (the map rotating on its own with movement — manual two-finger rotation ships)`.

- [ ] **Step 3: Conferir que não sobrou nada dizendo o contrário**

Run: `grep -rn -i "north-up\|norte fixo\|no rotation\|não rotaciona" docs/prd.md CLAUDE.md README.md`
Expected: nenhuma linha afirmando que o mapa não gira.

- [ ] **Step 4: Commitar**

```bash
git add docs/prd.md CLAUDE.md
git commit -m "docs: mapa passa a girar por gesto; course-up segue no backlog"
```

- [ ] **Step 5: Registrar no Linear**

Criar a issue no board (time `SOM`, projeto `soma_trails`, atribuída ao dono), título "Rotação do mapa com dois dedos + bússola", descrição com link para `docs/superpowers/specs/2026-09-08-rotacao-do-mapa-design.md` e para este plano. Criar já em **In Review** (o código está pronto neste ponto) e mover para **Done** quando o teste de campo do Step 6 passar.

- [ ] **Step 6: Teste de campo (fecha a feature)**

Em uma pedalada real:
- girar de luva funciona e não atrapalha o pinch-zoom;
- girar durante uma gravação não derruba o modo seguir nem a gravação;
- a orientação girada ajuda mesmo a se localizar na trilha.

Se o wizard de download por área incomodar com o mapa girado (ele parte de `camera.visibleBounds`, que com rotação devolve um bbox até ~1,4× maior que o visível), abrir uma issue à parte para zerar a rotação ao abrir o wizard. **Não** corrigir preventivamente.
