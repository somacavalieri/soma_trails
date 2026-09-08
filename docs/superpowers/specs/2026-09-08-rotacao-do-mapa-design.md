# Rotação do mapa (gesto de dois dedos) + bússola — design

**Data:** 2026-09-08
**Contexto:** pedalando, o dono sente falta de virar o mapa para alinhá-lo com o que ele
está vendo à frente. O Strava faz isso com dois dedos e mostra uma bússola no canto
superior direito; tocar na bússola volta ao norte e ela some 3 s depois
(`docs/ref-strava/Screenshot_20260907_162645_Strava.jpg`, `..._162658_...`, `..._162701_...`).

Hoje o soma_trails **desliga** a rotação de propósito em `map_screen.dart`
(`InteractiveFlag.all & ~InteractiveFlag.rotate`), e o PRD trava "norte fixo" em duas
linhas. **Este spec muda esse escopo**: rotação manual entra; course-up (mapa girando
sozinho com o movimento) continua fora.

## Objetivo

1. Girar o mapa com dois dedos, como no Strava.
2. Uma bússola que aparece quando o mapa sai do norte e mostra para onde ele está apontado.
3. Tocar na bússola anima a volta ao norte; 3 s depois ela some.

## Decisões travadas (com o dono)

- **Posição da bússola: acima do FAB laranja de recentralizar** (canto inferior direito),
  não no canto superior direito do Strava — lá já moram o zoom +/- e o badge de nível.
  Fica no alcance do polegar e agrupa os dois controles de orientação. O FAB **não se move**
  quando a bússola aparece ou some.
- **Girar NÃO desliga o modo "seguir".** Girar é orientar o mapa, não assumir o controle da
  câmera. Só arrastar (pan) desliga o seguir, como hoje.
- **Sem extras:** a rotação **não** é persistida (o app sempre abre no norte), **não** há
  chave nos Ajustes para desabilitar o gesto, e **não** há course-up.

## Abordagem

Rotação nativa do `flutter_map` 8.3.1 + bússola própria em `CustomPaint`, com a animação de
volta ao norte feita por um `AnimationController` local (~25 linhas).

Descartadas:
- **`flutter_map_animations`** — daria `animatedRotateTo` pronto, mas adiciona dependência a
  um stack que o `CLAUDE.md` manda não trocar sem perguntar, por pouco código.
- **`rotate(0)` seco, sem animação** — o salto instantâneo de até 180° faz perder a
  referência visual de onde o mapa estava. É o que a animação existe para evitar.

## Gesto

Em `map_screen.dart`, a `InteractionOptions` passa a ser:

```dart
interactionOptions: const InteractionOptions(
  flags: InteractiveFlag.all,
  enableMultiFingerGestureRace: true,
  rotationThreshold: 20.0,
  rotationWinGestures: MultiFingerGesture.all,
),
```

Por quê cada peça (verificado no pacote instalado,
`~/.pub-cache/hosted/pub.dev/flutter_map-8.3.1/lib/src/map/options/interaction.dart`):

- `enableMultiFingerGestureRace` é `false` por padrão, e **`rotationThreshold` só tem efeito
  com a corrida ligada**. Sem isso, qualquer torção durante um pinch-zoom já gira o mapa —
  exatamente o acidente que se quer evitar de luva, no meio da trilha.
- `rotationThreshold: 20.0` (o default) é a torção mínima para a rotação "ganhar" a corrida.
- `rotationWinGestures` default é **só** `MultiFingerGesture.rotate`: se a rotação ganhasse
  sozinha, o pinch-zoom ficaria bloqueado pelo resto daquele gesto. `MultiFingerGesture.all`
  (= `rotate | pinchZoom | pinchMove`) deixa girar e continuar dando zoom sem levantar os dedos.

**Efeito colateral da corrida de gestos (registrado na revisão final):** ligar
`enableMultiFingerGestureRace` também ativa os OUTROS limiares, que antes eram inertes.
`pinchZoomThreshold` (default 0.5) é medido em níveis de zoom via `log2(scale)`, ou seja, os
dedos precisam se afastar ~41% antes de o zoom começar; `pinchMoveThreshold` (default 40 px)
passa a valer para o pan de dois dedos. Enquanto ninguém vence a corrida, nenhum gesto
multi-toque tem efeito. Na prática o `pinchMove` costuma vencer antes (o foco quase sempre
desliza 40 px num pinch real, e `pinchMoveWinGestures` já libera o zoom junto), mas um pinch
centrado e deliberado pode ter um começo morto perceptível. **Conferir no teste de campo**; se
ficar lerdo, o ajuste é `pinchZoomThreshold: 0.2` (≈15% de abertura).

## Estado no MapScreen

- Novo campo `double _rotation = 0` em `_MapScreenState`.
- `_onMapEvent` hoje só chama `setState` quando o zoom **inteiro** muda ou ao sair do seguir.
  Passa a chamar também quando `event.camera.rotation` difere de `_rotation` em mais de 0,5° —
  sem isso a bússola não acompanha o dedo.
- A condição de unfollow continua **exatamente** `event.source == MapEventSource.onDrag`
  (girar preserva o seguir).
- `_onPosition` segue chamando `_mapController.move(...)`, que não mexe na rotação: seguir com
  o mapa girado funciona sem tratamento especial.
- **Snap:** ao terminar um gesto (`MapEventSource.multiFingerEnd`), se o desvio do norte for
  menor que 1° a rotação é zerada. Sem isso sobra um 0,4° teimoso e a bússola nunca some.
- **Cuidado: `camera.rotation` não é normalizada.** O gesto faz `_camera.rotation + diff` e
  acumula (`map_interactive_viewer.dart:733`), então o valor pode ser `-47.3` ou `412.8`.
  Toda comparação com o norte passa por um helper que devolve o desvio com sinal em
  `(-180°, 180°]` — comparar `rotation.abs()` direto trataria 359,7° como "girado".

## Bússola — `lib/map_compass.dart` (novo)

`MapCompass extends StatelessWidget`, sem estado próprio:

- **Entradas:** `double rotation` (graus, sentido do `camera.rotation`), `bool highContrast`,
  `VoidCallback onTap`.
- **Visual:** disco de 46 px no mesmo vocabulário dos `_MapIconButton` / `_ZoomBadge`
  existentes (fundo escuro translúcido, sombra, borda), ponteiro **vermelho** apontando para o
  norte geográfico e, no centro, a letra da direção que está **para cima** na tela.
- **Rótulos em português:** N, NE, L, SE, S, SO, O, NO — faixas de 45° centradas
  (N = [-22,5°, 22,5°)).
- **Sinal da rotação:** o `MobileLayerTransformer` do flutter_map aplica
  `Transform.rotate(angle: camera.rotationRad)`, que no Flutter gira no **sentido horário**.
  Ou seja, o norte fica na direção `+rotation` na tela e a direção **no topo da tela** é
  `-rotation`. Confere com a screenshot do Strava (ponteiro vermelho à esquerda + letra "E":
  norte à esquerda = rotação −90 = leste para cima). O ponteiro e os ticks giram junto com o
  mapa (`Transform.rotate(angle: rotationRad)`); a **letra fica sempre em pé**.
- **Alvo de toque de 48 px** mesmo com o disco de 46, via `Semantics(button: true)` +
  `GestureDetector` com `behavior: HitTestBehavior.opaque`.
- **Posição:** `Positioned(right: 16, bottom: 96 + 56 + 12 + bottomInset)` — colada acima do
  FAB de recentralizar, alinhada ao centro dele.

## Visibilidade (a regra dos 3 s)

Estado no `_MapScreenState`, não dentro da bússola:

- Bússola visível enquanto `|_rotation| > 0,5°`.
- Quando a rotação volta a 0 (por toque na bússola ou por gesto), um `Timer` de **3 s** agenda
  o fade-out (`AnimatedOpacity`/`AnimatedScale`, 200 ms).
- Qualquer rotação nova **cancela** o timer e traz a bússola de volta na hora.
- Se nunca se girou o mapa, ela nunca apareceu — não há estado inicial visível.
- O timer é cancelado em `dispose()`.

## Voltar ao norte

Toque na bússola dispara um `AnimationController` (300 ms, `Curves.easeOutCubic`) que
interpola do ângulo atual até 0 **pelo caminho curto** — a diferença é normalizada para
`(-180°, 180°]`, então 350° gira +10° e não −350°. A cada tick chama `_mapController.rotate(v)`.

A animação é cancelada — `controller.stop()`, mantendo a rotação onde parou — se chegar um
`MapEvent` com origem `multiFingerGestureStart`, `onMultiFinger`, `dragStart` ou `onDrag`
enquanto ela roda, e também no `dispose()`. Os eventos que a própria animação emite têm origem
`mapController`, então ela não se cancela sozinha.

## Marcadores: o que gira e o que fica em pé

`Marker.rotate` no flutter_map significa **contra-rotacionar para ficar em pé**, e o default é
`false` (o marcador gira junto com o mapa). Então:

- `rotate: true` nos **pinos**: pontos marcados (`_pointMarkers`), waypoints do GPX
  (`_waypointMarkers`) e o marcador de início do trajeto. Sem isso eles deitam junto com o mapa.
- `rotate: false` (default, **sem mudança**) no `LocationDot`: a seta de heading é geográfica
  (0 = norte), então, girando junto com o mapa, ela continua apontando para a direção certa
  sem nenhuma conta de compensação. **`lib/location_marker.dart` não é tocado.**
- Polylines (trilhas, trajeto gravado) não são afetadas por rotação.

## Efeito colateral aceito: download por área

`_openDownload` parte de `_mapController.camera.visibleBounds`, que — conforme a doc do
pacote — já leva a rotação em conta e devolve o **bbox alinhado ao norte que contém** a tela
girada. Com o mapa a 45°, esse bbox chega a ~1,4× a área visível.

Nada quebra (o wizard mostra km² e tamanho estimado antes de baixar), mas baixa-se mais tile do
que o esperado. **Decisão: aceitar e documentar.** Se incomodar em campo, a correção é zerar a
rotação ao abrir o wizard de download.

Sem impacto em: `onLongPress` para marcar ponto (já devolve LatLng correto com rotação), badge
de zoom e chip "Offline pronto" (usam `camera.center`).

## Testes

**Unidade** (`test/map_compass_test.dart`) — helpers puros, sem mapa:
- normalização do caminho curto: 350 → 0 percorre +10; 10 → 0 percorre −10; 180 é estável.
- rótulo de direção por faixa (lembrando que a direção no topo é `-rotation`):
  0→N, −90→L, 90→O, −45→NE, 180→S.
- regra do auto-esconder isolada num pequeno controlador testável (rotação ≠ 0 mostra;
  voltar a 0 agenda 3 s; girar de novo cancela).

**Widget** — bússola: `rotation: -90` renderiza "L"; `rotation: 90` renderiza "O"; norte +
timer vencido → opacidade 0.

**Campo (S24 Ultra):**
- girar de luva funciona; pinch-zoom **puro** não gira mais o mapa;
- girar durante gravação **não** derruba o modo seguir nem a gravação;
- tocar na bússola anima suave e ela some 3 s depois.

## Docs a atualizar junto

- `docs/prd.md:35` e `docs/prd.md:58` — "norte fixo / rotação (course-up) fora do escopo" vira
  "norte por padrão, rotação manual por gesto de dois dedos; course-up continua no backlog".
- `CLAUDE.md` — as mesmas duas frases em "Architecture (planned)" e "Scope discipline".
- Criar a issue correspondente no board Linear (time SOM, projeto soma_trails).

## Arquivos

| Arquivo | O quê |
|---|---|
| `lib/map_compass.dart` | novo — widget da bússola + helpers puros (rótulo, caminho curto) |
| `lib/map_screen.dart` | edição — interaction options, `_rotation`, `_onMapEvent`, timer dos 3 s, animação, `rotate: true` nos pinos, posicionar a bússola |
| `test/map_compass_test.dart` | novo — testes de unidade e widget |
| `docs/prd.md` | edição — desfaz a trava de "norte fixo" |
| `CLAUDE.md` | edição — idem |

## Fora de escopo

Course-up (mapa girando com o movimento), rotação persistida entre aberturas do app, chave nos
Ajustes para desabilitar o gesto, e inclinação/3D.
