import 'package:flutter/material.dart';
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

    testWidgets('ocupa 48x48 e é anunciada como botão', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(wrap(MapCompass(rotation: 45, onTap: () {})));
      expect(tester.getSize(find.byType(MapCompass)), const Size(48, 48));

      final semantics = tester.getSemantics(find.byType(MapCompass));
      expect(semantics.flagsCollection.isButton, isTrue);
      
      handle.dispose();
    });
  });
}
