# Changelog — soma_trails

App pessoal de trilhas offline (Android, S24 Ultra, sideload por APK). Formato
inspirado em [Keep a Changelog](https://keepachangelog.com/pt-BR/). O "MVP" cobre
os passos 1–10 do plano do PRD.

## [Não lançado]

### Melhorias
- `2a32420` — **SOM-328:** download por trilha baixa ~1 km de margem em volta da
  rota (era bug de unidade: raio do LineRegion é em metros, passava-se 0.6 como
  se fosse km → corredor de 0,6 m). Limites salvos expandidos para o "Offline
  pronto" bater com a faixa baixada.

### Backlog (próximo)
- Pastas de trilhas + seleção múltipla no painel Trilhas (sobra do passo 4).
- "Abrir com / compartilhar para" GPX vindo de outros apps.
- Validação de campo (issues SOM-329 a SOM-333 no Linear).

---

## MVP — feature-complete (pendente validação de campo)

O app entrega as três features que definem o sucesso: ver minha posição sobre
satélite offline, baixar satélite por área de dentro do app, e abrir muitos GPX
ao mesmo tempo + gravar o rastro percorrido.

### GPS de gravação — caçada ao bug de congelamento (S24 Ultra / One UI)
Sequência de correções depois que a gravação "não registrava e a localização
ficava estática". Cada camada foi revelada por um painel de diagnóstico
instrumentado (hoje em Ajustes → "Diagnóstico do GPS").
- `7e4d213` — painel de diagnóstico vira toggle nos Ajustes (default off) +
  lições de GPS registradas no CLAUDE.md.
- `5a0c9e6` — **Fix 4 (causa raiz):** faltava `WAKE_LOCK` no manifest. O
  geolocator adquire wakelock ao ligar o stream com notificação de foreground,
  mas não declara a permissão → `SecurityException` na gravação. Normal fluía,
  clicar em gravar congelava.
- `bf808d5` — Fix 3: pausa de 400 ms entre cancelar e religar o stream +
  watchdog de 30 s que religa sozinho se o GPS emudecer (rede de segurança
  permanente).
- `15ff537` — Fix 2: trocar `distanceFilter` por updates por tempo
  (`intervalDuration` ~2 s). Em Samsungs, `distanceFilter` vira
  `smallestDisplacement` e o fused provider suprime updates até congelar. Filtro
  de distância (≥5 m) passou para a camada do app (TrackRecorder).
- `ca0d967` — Fix 1: religação do stream idempotente e serializada, aguardando o
  cancelamento anterior (corrida real, mas não a causa principal).
- `895564e` — painel de diagnóstico do GPS (fixes, idade do último fix, modo,
  religações, erro) para depurar sem reproduzir localmente.

### Funcionalidades (passos do plano)
- `fbca50a` — indicador do nível de zoom abaixo dos botões, com aviso âmbar
  quando o zoom passa do máximo baixado (overzoom/imagem escalada).
- `411ba5a` — **Passo 10:** tela de Ajustes — manter tela ligada (via
  MethodChannel nativo, sem dependência), limpar cache de navegação, alto
  contraste para sol, unidades km/mi.
- `d99b8b1` — **Passo 8:** baixar satélite por área (viewport + slider) ou por
  trilha (corredor); estimativa de tiles/tamanho/tempo, download com progresso e
  cancelar, tela de Regiões (excluir libera espaço), chip "Offline pronto".
- `369fe41` — **Passo 7:** tela "Fontes do mapa" — trocar fonte ativa
  (Esri/OSM Topo) e adicionar por URL; persistência + store FMTC por fonte.
- `778c9a3` — **Passo 6:** marcar pontos no mapa (long-press) com categoria +
  painel Pontos.
- `b2bcee5` — **Passo 5:** gravar trajeto — foreground service, HUD, auto-save
  GPX a cada 30 s, retomada automática após o app ser morto (crash-resume),
  exportar GPX.
- `1492049` — fix: o mapa passa a se ajustar às trilhas ao importar/reabrir
  (antes abria fixo na Serra do Cipó e o GPX de outra região ficava fora da tela).
- `6d344dd` — **Passo 4:** importar múltiplos GPX, trilhas coloridas +
  waypoints, painel Trilhas (cor, olhinho, mostrar/ocultar todas), barra
  inferior; simplificação de polyline (Douglas-Peucker).
- `0e1fd84` — **Passo 3:** posição de GPS no mapa (ponto + precisão + heading),
  recentralizar e modo seguir.
- `13ff591` — **Passo 2:** cache offline por navegação (FMTC) + overzoom + botões
  de zoom.
- `384d4b5` — **Passo 1:** scaffold Flutter, toolchain pinada, keystore de
  release + APK assinado de sideload.
- `98f114b` — commit inicial: PRD, CLAUDE.md, protótipo de referência.

### Toolchain / stack (ver CLAUDE.md para detalhes)
- Flutter 3.44.4 · AGP 8.12 + Gradle 8.14.2 (AGP 9 do template quebra plugins).
- Stack: `flutter_map` + `flutter_map_tile_caching` (FMTC/ObjectBox) +
  `geolocator` + `gpx` + `file_picker`; estado em `ChangeNotifier`.
- Sem `wakelock_plus` (conflito de win32 com file_picker) — tela acesa via
  MethodChannel nativo. Override de `package_info_plus` para o file_picker.
