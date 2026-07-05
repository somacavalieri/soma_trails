# PRD + Plano — App de Trilhas Offline ("soma_trails")

## Contexto

O usuário pedala/faz trilhas de mountain bike e depende há anos do app **My Trails (Frogsparks)**. O app está defasado, dá problemas crescentes, não está na Play Store (provavelmente por baixar tiles de satélite de forma cinza juridicamente) e pode parar de funcionar a qualquer momento.

O que prende o usuário a ele **não é tecnologia exclusiva**, e sim **conveniência de workflow**:
1. **Baixar satélite offline selecionando a área dentro do próprio app** (sem ter que gerar `.mbtiles` no PC com SAS.Planet/MOBAC).
2. **Abrir muitas trilhas GPX ao mesmo tempo** (sobreposição de camadas) sem dor.

Apps existentes (OruxMaps, Locus, AlpineQuest) já fazem isso tecnicamente, mas o usuário testou e o **fluxo** não o atendeu. Como ele programa com ajuda de IA e quer manter o app sozinho, decidiu-se construir um app **fino, de uso pessoal, instalado por APK** no **Galaxy S24 Ultra**, replicando só o que ele realmente usa.

**Resultado esperado:** um app que, no meio da trilha sem sinal, mostra onde ele está sobre satélite offline, exibe várias trilhas planejadas ao mesmo tempo e grava um rastro do trajeto para ele se orientar.

## Veredito de viabilidade

Viável e de esforço moderado, porque as features-chave vêm de bibliotecas maduras:
- Download de tiles por área offline → `flutter_map_tile_caching` (FMTC) **de fábrica**.
- Render de N trilhas → `PolylineLayer` (trivial).
- Posição GPS + gravação de trajeto → `geolocator` (funciona offline; GPS é posicionamento por satélite, não precisa de internet). O breadcrumb reusa o mesmo stream de localização.

**Riscos reais** (não "dá pra fazer", mas "como durar"):
- **Manutenção solo / quebra do Android** — foi o que matou o My Trails. Mitigado por Flutter (evolução rápida com IA) e escopo mínimo.
- **Durabilidade/legalidade das fontes de tiles** (Esri/Bing/Google têm ToS cinza pra cache offline). Mitigado por **fontes configuráveis**: se uma quebrar, troca a URL. Uso é pessoal e por sideload (sem distribuição), o que reduz muito o risco prático.
- **Tamanho de armazenamento** — satélite em zoom alto sobre área grande pode chegar a vários GB. Mitigado por estimativa de tamanho antes do download. S24 Ultra tem espaço de sobra.
- **Confiabilidade da gravação** — o rastro não pode ser perdido se o app for fechado/morto no meio da trilha. Mitigado por auto-save periódico em disco.

## Decisões travadas (com o usuário)

- **Stack:** Flutter + `flutter_map` + `flutter_map_tile_caching` (FMTC) + `geolocator` + `gpx` + `file_picker`.
- **Distribuição:** APK sideload, só Android (S24 Ultra). Sem iOS, sem Play Store.
- **Fontes de satélite:** **configuráveis** (lista de URLs de tiles). Não há botão de troca em tempo real no v1 — é configuração.
- **Gravação de trajeto (breadcrumb) no v1: SIM, mas leve.** O objetivo é **orientação** ("de onde eu vim?") para não se perder — não dados de atividade. Não precisa de precisão alta. Gravação rica (estatísticas detalhadas, segmentos, análise) fica fora; o usuário já grava no Strava/Wikiloc.

## Escopo do MVP (v1)

Features essenciais ("me salvar na trilha"):

1. **Ver minha posição (GPS) no mapa** — ponto/seta de localização + heading, botão "recentralizar em mim". Funciona offline.
2. **Baixar satélite por área (offline)** — selecionar região (viewport atual ou retângulo), escolher faixa de zoom, ver estimativa de nº de tiles e tamanho, baixar com barra de progresso, gerenciar/excluir regiões baixadas.
3. **Carregar vários GPX de uma vez** — importar múltiplos arquivos (ou pasta), parsear, exibir todas as trilhas sobrepostas com cores distintas, ligar/desligar e remover trilhas.
4. **Gravar meu trajeto (breadcrumb) para me orientar** — gravar/pausar/retomar/parar; registra as posições do GPS e desenha o caminho percorrido como uma linha destacada ("meu trajeto", cor de acento, visualmente distinta das trilhas importadas), começando num pino de início. **Auto-salva periodicamente** (não pode perder o trajeto se o app fechar). HUD glanceable com distância e tempo. Sem precisão alta nem estatísticas ricas — foco em "de onde vim". Trajetos salvos ficam numa lista (mostrar no mapa / exportar GPX / excluir).

### Fora de escopo (backlog)
Gravação rica de atividade (estatísticas detalhadas, segmentos, gráficos), navegação turn-by-turn/roteamento, busca/geocoding, compartilhamento social, iOS/multiplataforma, troca de fonte de tiles em runtime com UI polida, sincronização em nuvem.

## Arquitetura

App Flutter single-screen-cêntrico. Camadas do mapa (de baixo pra cima): **tiles base (offline-aware)** → **polylines dos GPX importados** → **polyline do "meu trajeto" gravado** → **marcador de localização**.

### Componentes
- **MapScreen** — `FlutterMap` em tela cheia + controles (zoom, recentralizar, painel de trilhas, painel "meu trajeto", download, FAB de gravação, HUD).
- **TileSourceConfig** — lista de fontes (nome, URL template, zoom máx, atribuição). Ex.: Esri World Imagery, Bing, OSM Topo. Editável; cada fonte tem seu store no FMTC.
- **OfflineDownloadController** — calcula range de tiles para bbox + zooms, estima contagem/tamanho, dispara download FMTC com progresso, persiste metadados das regiões.
- **TrackManager** — importa via `file_picker`, parseia com `gpx`, guarda lista (caminho, nome, cor, visível), expõe polylines.
- **LocationService** — stream do `geolocator` → posição + heading; trata permissões.
- **TrackRecorder** — consome o stream do `LocationService`; acumula os pontos do trajeto, gera a polyline "meu trajeto", controla gravar/pausar/retomar/parar e **auto-salva em disco periodicamente** (resiliente a fechar/matar o app, retomando a gravação ao reabrir). Reusa o LocationService (sem GPS duplicado). Exporta GPX dos trajetos salvos.
- **Persistência local** — config de fontes + metadados de trilhas/regiões + trajetos gravados (shared_prefs ou Isar/sqlite); tiles ficam no store próprio do FMTC (SQLite — portável, não vendor-lock).

### Fluxo de dados
- **Pré-trilha (com wi-fi):** importar GPX → selecionar área → baixar tiles.
- **Na trilha (offline):** abrir app → mapa renderiza do cache FMTC → ponto de GPS → trilhas visíveis → (opcional) iniciar gravação, que vai sendo desenhada e auto-salva continuamente. Zero rede.

## Plano de implementação (incremental)

1. **Scaffold Flutter** + dependências; build/sideload de APK "hello map" no S24 Ultra (valida toolchain cedo).
2. **MapScreen com tile online** de 1 fonte (Esri) + controles de zoom/pan.
3. **LocationService** — ponto de GPS + recentralizar (testar permissões no device real).
4. **TrackManager** — importar múltiplos GPX + render multi-polyline + painel ligar/desligar/cor.
5. **TrackRecorder** — gravar/pausar/parar + polyline "meu trajeto" crescendo + HUD (distância/tempo) + auto-save e retomada após reabrir o app.
6. **TileSourceConfig** — abstrair fonte por URL template; lista configurável.
7. **OfflineDownloadController** — seleção de área + estimativa + download FMTC + progresso + gerenciar regiões.
8. **Offline real** — garantir render 100% do cache em modo avião; persistência de trilhas/regiões/trajetos entre sessões.
9. **Polimento** — cores/legendas, indicador "offline pronto", export de GPX do trajeto, limpeza de armazenamento.

## Verificação (end-to-end)

- **Toolchain:** `flutter build apk` e instalar o APK no S24 Ultra.
- **Em casa (wi-fi):** importar 10+ GPX simultâneos e confirmar todas sobrepostas; baixar uma região de satélite com progresso e ver tamanho estimado.
- **Modo avião (crítico):** fechar e reabrir o app sem rede → mapa renderiza do cache, ponto de GPS se move, trilhas continuam visíveis. Este teste é a definição de sucesso.
- **Gravação:** iniciar a gravação, mover-se (ou simular), fechar/matar o app e reabrir → o trajeto gravado persiste, continua desenhado e a gravação pode ser retomada. Sem perda de rastro.
- **Campo:** teste real em uma trilha conhecida sem sinal.

## Perguntas em aberto (resolver na implementação)
- Confirmar URLs/zoom-máx exatos de cada fonte de tiles a incluir por padrão.
- Definir limite de zoom default no download pra equilibrar nitidez x tamanho.
- Frequência de auto-save e amostragem de pontos do trajeto (equilíbrio bateria x detalhe).
- Escolher persistência (shared_prefs simples vs. Isar) conforme volume de trilhas/trajetos.
