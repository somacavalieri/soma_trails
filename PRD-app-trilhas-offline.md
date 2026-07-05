# PRD + Plano — App de Trilhas Offline ("soma_trails")

## Contexto

O usuário pedala/faz trilhas de mountain bike e depende há anos do app **My Trails (Frogsparks)**. O app está defasado, dá problemas crescentes, não está na Play Store (provavelmente por baixar tiles de satélite de forma cinza juridicamente) e pode parar de funcionar a qualquer momento.

O que prende o usuário a ele **não é tecnologia exclusiva**, e sim **conveniência de workflow**:
1. **Baixar satélite offline selecionando a área dentro do próprio app** (sem ter que gerar `.mbtiles` no PC com SAS.Planet/MOBAC).
2. **Abrir muitas trilhas GPX ao mesmo tempo** (sobreposição de camadas) sem dor.

Apps existentes (OruxMaps, Locus, AlpineQuest) já fazem isso tecnicamente, mas o usuário testou e o **fluxo** não o atendeu. Como ele programa com ajuda de IA e quer manter o app sozinho, decidiu-se construir um app **fino, de uso estritamente pessoal (sem comercialização), instalado por APK** no **Galaxy S24 Ultra**, replicando só o que ele realmente usa.

**Resultado esperado:** um app que, no meio da trilha sem sinal, mostra onde ele está sobre satélite offline, exibe várias trilhas planejadas ao mesmo tempo e grava um rastro do trajeto para ele se orientar.

## Veredito de viabilidade

Viável e de esforço moderado, porque as features-chave vêm de bibliotecas maduras:
- Download de tiles por área offline → `flutter_map_tile_caching` (FMTC) **de fábrica**.
- Render de N trilhas → `PolylineLayer` (trivial).
- Posição GPS + gravação de trajeto → `geolocator` (funciona offline; GPS é posicionamento por satélite, não precisa de internet). O breadcrumb reusa o mesmo stream de localização.

**Riscos reais** (não "dá pra fazer", mas "como durar"):
- **Android matando a gravação em background (risco nº 1)** — o S24 Ultra roda One UI, a skin mais agressiva do mercado em matar apps em background. Sem *foreground service* + isenção de otimização de bateria, o breadcrumb para de gravar minutos depois de a tela apagar — exatamente o cenário-alvo. Tratado na seção "Requisitos de plataforma".
- **Manutenção solo / quebra do Android** — foi o que matou o My Trails. Mitigado por Flutter (evolução rápida com IA), escopo mínimo e a seção "Durabilidade".
- **Durabilidade/legalidade das fontes de tiles** (ToS cinza pra cache offline). Mitigado por **fontes configuráveis**: se uma quebrar, troca a URL. Uso é pessoal e por sideload (sem distribuição), o que reduz muito o risco prático.
- **Tamanho de armazenamento** — satélite em zoom alto sobre área grande pode chegar a vários GB. Mitigado por estimativa de tamanho antes do download e pelo teto de zoom (z17 + overzoom). S24 Ultra tem espaço de sobra.
- **Confiabilidade da gravação** — o rastro não pode ser perdido se o app for fechado/morto no meio da trilha. Mitigado por auto-save periódico em disco (GPX direto) + retomada automática.

## Decisões travadas (com o usuário)

- **Stack:** Flutter + `flutter_map` + `flutter_map_tile_caching` (FMTC) + `geolocator` + `gpx` + `file_picker`.
- **Distribuição:** APK sideload, só Android (S24 Ultra). Sem iOS, sem Play Store. Uso pessoal, sem comercialização — a licença GPL-v3 do FMTC não impõe nenhuma obrigação prática nesse cenário (sem distribuição).
- **Fontes de satélite:** **configuráveis**, com **tela simples "Fontes do mapa" no v1** (lista de fontes, toggle de qual está ativa — uma por vez —, adicionar/editar por URL template). Defaults: **Esri World Imagery** (satélite) e **OSM Topo** (alternativa topográfica). Bing foi descartado (descontinuado para contas free/basic e usa quadkey, incompatível com URL template `{x}/{y}/{z}` simples).
- **O protótipo `Soma Trails.html` é a FONTE DA VERDADE de UI/UX** (export interativo do Claude Design; abrir no browser). Onde este PRD e o protótipo divergirem, vale o protótipo. A seção "Especificação de UI" abaixo descreve todas as telas. Únicos desvios deliberados, por motivo técnico: (1) Bing Aerial não entra na lista de fontes (serviço descontinuado + formato quadkey); (2) o download em massa ganha um estado de progresso com cancelar (o protótipo pula direto para "Pronto!").
- **Orientação do mapa: norte fixo.** A seta de posição gira com o heading; o mapa não rotaciona. Course-up (mapa girando com o movimento) fica no backlog.
- **Waypoints dos GPX: sim, simples.** Pin discreto na cor da trilha; nome aparece ao tocar. Nada além disso.
- **Pontos do usuário no v1: SIM.** Segurar no mapa marca um ponto pessoal (nome + categoria curta, ex.: água, mirante, perigo/bifurcação); painel "Pontos" lista com coordenadas e excluir. Persistem como arquivo local e aparecem offline.
- **Download "por trilha" no v1: SIM.** Além do retângulo, dá para escolher uma trilha importada e a área de download se ajusta ao redor do traçado (bounding box + margem).
- **Organização de trilhas no v1: como no protótipo** — pastas (agrupar trilhas, ex. por região), seleção múltipla ("Selecionar") e ações em massa ("Mostrar todas / Ocultar todas").
- **Tela sempre acesa** (wakelock) enquanto o app está em primeiro plano.
- **"Abrir com / Compartilhar para" fica no backlog.** No v1 a importação é pelo botão do app (`file_picker`, múltiplos arquivos).
- **Gravação de trajeto (breadcrumb) no v1: SIM, mas leve.** O objetivo é **orientação** ("de onde eu vim?") para não se perder — não dados de atividade. Não precisa de precisão alta. Gravação rica (estatísticas detalhadas, segmentos, análise) fica fora; o usuário já grava no Strava/Wikiloc.
- **Persistência: sem Isar** (projeto praticamente abandonado; e o FMTC já embute ObjectBox de qualquer forma). Config → `shared_preferences`; trilhas importadas e trajetos gravados → **arquivos no disco** (GPX + um JSON de metadados). Tiles ficam no store do FMTC (backend **ObjectBox** — vendor-lock aceito porque tiles são re-baixáveis; o que precisa sobreviver são GPX e configs, que são arquivos simples).
- **Zoom de download: slider z12–z18, default z12–z15 (como no protótipo).** Esri em zona rural do Brasil raramente resolve melhor que z17, e cada nível a menos divide o nº de tiles por ~4. Overzoom (escala) até ~z20 via `maxNativeZoom` — nunca tela cinza ao dar zoom além do baixado.
- **Amostragem do GPS (defaults, ajustáveis em campo):** `distanceFilter` 5–10 m; descartar pontos com accuracy > ~30 m (evita o "novelo" quando parado); flush do auto-save a cada ~30 s.

## Escopo do MVP (v1)

Features essenciais ("me salvar na trilha"):

1. **Ver minha posição (GPS) no mapa** — ponto/seta de localização com heading (mapa norte fixo), botão "recentralizar em mim". Funciona offline.
2. **Baixar satélite por área (offline)** — wizard em 3 passos: selecionar região (retângulo arrastável **ou "por trilha"**, com a área ajustada ao redor do traçado), escolher faixa de zoom (slider z12–z18, default z12–z15) com comparação visual de detalhe, ver estimativa de nº de tiles/tamanho/tempo, baixar com progresso, gerenciar/excluir regiões baixadas (com total de armazenamento usado).
3. **Carregar vários GPX de uma vez** — importar múltiplos arquivos, parsear, exibir todas as trilhas sobrepostas com cores distintas (cor editável) + waypoints (pin simples, nome ao tocar), ligar/desligar individualmente e em massa ("Mostrar todas / Ocultar todas"), organizar em pastas, seleção múltipla e remover trilhas. Edge cases tratados: múltiplos `<trk>`/`<trkseg>` por arquivo e `<rte>` (rotas) renderizados como trilha. Simplificação de polyline para não engasgar com 10+ trilhas longas.
4. **Gravar meu trajeto (breadcrumb) para me orientar** — gravar/pausar/retomar/parar; registra as posições do GPS e desenha o caminho percorrido como uma linha destacada ("meu trajeto", cor de acento, visualmente distinta das trilhas importadas), começando num pino de início. **Auto-salva em GPX direto no disco** (recovery = reler o arquivo; export sai de graça). Se o app for morto com gravação ativa, ao reabrir **retoma automaticamente**, marcando o gap como novo segmento (sem linha reta falsa). HUD glanceable com distância e tempo. Trajetos salvos ficam numa lista (mostrar no mapa / exportar GPX para `Downloads/` / excluir).
5. **Marcar pontos no mapa** — segurar no mapa cria um ponto pessoal (nome + categoria); painel "Pontos" com lista, coordenadas e excluir. Visíveis offline, persistem entre sessões.

### Fora de escopo (backlog)
Gravação rica de atividade (estatísticas detalhadas, segmentos, gráficos), navegação turn-by-turn/roteamento, busca/geocoding, compartilhamento social, iOS/multiplataforma, sincronização em nuvem, rotação do mapa (course-up), "abrir com / compartilhar para" GPX vindo de outros apps.

## Arquitetura

App Flutter single-screen-cêntrico. Camadas do mapa (de baixo pra cima): **tiles base (offline-aware)** → **polylines dos GPX importados** → **waypoints dos GPX** → **pontos do usuário** → **polyline do "meu trajeto" gravado** → **marcador de localização**.

### Componentes
- **MapScreen** — `FlutterMap` em tela cheia + barra inferior (Trilhas / Meu trajeto / Baixar satélite / Ajustes), controles (zoom, recentralizar, FAB de gravação, HUD), painéis em bottom sheet (trilhas, meu trajeto, pontos) e long-press para marcar ponto. Mantém wakelock em primeiro plano.
- **TileSourceConfig** — lista de fontes (nome, URL template, zoom máx, atribuição) com **tela "Fontes do mapa"** no v1: uma fonte ativa por vez (toggle), adicionar/editar por URL. Defaults: Esri World Imagery e OSM Topo. Cada fonte tem seu store no FMTC. **Desde o passo 2, o tile provider passa pelo FMTC (browse caching)** — o que for navegado já fica cacheado, e a dependência mais arriscada é validada cedo.
- **OfflineDownloadController** — dois modos de seleção: **por área** (retângulo) e **por trilha** (bbox do traçado + margem); calcula range de tiles para bbox + zooms, estima contagem/tamanho/tempo, dispara download FMTC com progresso, persiste metadados das regiões e expõe total de armazenamento usado.
- **PointManager** — pontos marcados pelo usuário (long-press): nome, categoria, lat/lon; persiste em JSON; expõe markers para o mapa e a lista do painel "Pontos".
- **TrackManager** — importa via `file_picker`, parseia com `gpx` (tracks, rotas e waypoints), guarda lista (caminho, nome, cor, visível, pasta), organiza em pastas, suporta seleção múltipla e ações em massa, expõe polylines + markers de waypoint. Aplica simplificação de polyline.
- **LocationService** — stream do `geolocator` → posição + heading; trata permissões; aplica filtros de distância/accuracy. **Durante gravação roda como foreground service com notificação persistente** (`foregroundNotificationConfig`).
- **TrackRecorder** — consome o stream do `LocationService`; acumula os pontos do trajeto, gera a polyline "meu trajeto", controla gravar/pausar/retomar/parar e **auto-salva o GPX em disco a cada ~30 s** (resiliente a fechar/matar o app; retoma automaticamente ao reabrir, gap vira novo segmento). Reusa o LocationService (sem GPS duplicado). Exporta GPX dos trajetos salvos para `Downloads/` via MediaStore.
- **Persistência local** — config de fontes em `shared_preferences`; trilhas/trajetos como arquivos (GPX + JSON de metadados); tiles no store do FMTC (ObjectBox).

### Fluxo de dados
- **Pré-trilha (com wi-fi):** importar GPX → selecionar área → baixar tiles.
- **Na trilha (offline):** abrir app → mapa renderiza do cache FMTC → ponto de GPS → trilhas visíveis → (opcional) iniciar gravação, que vai sendo desenhada e auto-salva continuamente. Zero rede.

## Especificação de UI (fonte: protótipo `Soma Trails.html`)

Tema escuro com acento laranja; painéis em bottom sheet com alça de arrastar; telas secundárias em tela cheia com botão voltar (chevron) no cabeçalho.

### Tela principal (mapa)
- **Barra do título:** pin laranja + nome da região ativa ("Serra do Cipó · MG") + chip verde **"Offline pronto"** quando a área visível está coberta pelo cache. À direita: **botão contador de Pontos** (pin rosa + nº de pontos marcados; abre o painel Pontos) e **botão de camadas** (abre "Fontes do mapa").
- **Mapa:** polylines coloridas com marcadores de início/fim (bolinha/quadradinho nas pontas); pins de waypoints dos GPX; pontos do usuário; posição GPS como **ponto azul com círculo de precisão e seta de heading**; norte fixo.
- **Controles:** zoom **+/−** empilhado à direita; **FAB laranja de recentralizar** (canto inferior direito); **FAB vermelho de gravação** (canto inferior esquerdo).
- **Dica flutuante:** "Segure no mapa para marcar um ponto" (long-press cria ponto do usuário).
- **Barra inferior (4 itens):** Trilhas (badge verde com nº de trilhas visíveis) · Meu trajeto (ponto vermelho quando gravando) · Baixar satélite · Ajustes.

### Estado gravando
- **HUD** logo abaixo da barra do título: chip "● Gravando" pulsante, **TEMPO** (cronômetro) e **TRAJETO** (km, em laranja).
- FABs viram **pausar** (vermelho) + **parar** (escuro, quadrado branco).
- Linha do trajeto na cor de acento (laranja), crescendo a partir de um **pino de início**.

### Painel Trilhas (bottom sheet)
- Cabeçalho: título, contagem "**N de M visíveis**", botão laranja **"+ Importar"**.
- Linha de ações: **Nova pasta** · **Selecionar** (seleção múltipla) · **Mostrar todas** · **Ocultar todas**.
- Item de trilha: **swatch de cor com lápis (cor editável)**, nome, **distância + nome do arquivo** ("8,4 km · trilha_1.gpx"), **olhinho** de visibilidade, menu **⋮**.
- **Pastas** agrupam trilhas e mostram resumo ("Serra do Cipó — 3 trilhas · 1 visíveis"), expansíveis.

### Painel Meu trajeto (bottom sheet)
- Subtítulo: "Rastro de orientação · de onde eu vim".
- Botão tracejado **"● Gravar novo trajeto"**.
- Lista **"Trajetos salvos"**: data/hora relativa ("Ontem · 16:20"), **distância + duração** ("12,4 km · 1h 02"), botões **Mostrar** · **exportar** · **excluir**.

### Painel Pontos (bottom sheet)
- Cabeçalho: "Pontos — N marcados no mapa" + botão **Concluir**.
- Item: bolinha colorida, **nome**, **coordenadas** ("-19.3088, -43.6116") + **categorias** ("Água · Descanso", "Mirante · Vista", "Perigo · Bifurcação"), botão excluir.
- Criação: long-press no mapa; nome + categoria.

### Wizard "Baixar satélite" (tela cheia, 3 passos com indicador de progresso; botão "Regiões" no cabeçalho de todos os passos)
1. **Selecionar área** — tabs **"Por área"** (retângulo com alças nos cantos arrastáveis + slider **"Tamanho da área"** mostrando km² + dica "Arraste para ajustar a área") e **"Por trilha"** ("Escolha a trilha — a área será ajustada ao redor dela"; lista das trilhas importadas com rádio). Botão **"Próximo: Detalhe"**.
2. **Detalhe (zoom)** — quando "por trilha", banner "MAPA A PARTIR DA TRILHA — área ajustada automaticamente ao redor do traçado"; **comparação visual de dois níveis de zoom** (thumbnails lado a lado); slider **z12–z18** (default **12 → 15**); cards de estimativa: **nº de tiles · tamanho (MB) · tempo estimado**; botão **"Baixar · X MB"** + voltar.
3. **Pronto!** — check verde, "Área pronta para offline", resumo (tiles · MB), botões **Concluir** e **Ver regiões baixadas**. *(Desvio deliberado: na implementação entra um estado de progresso com cancelar entre os passos 2 e 3.)*

### Tela "Regiões baixadas"
- Card **"Armazenamento usado"** com total (ex.: 4,5 GB).
- Item de região: nome (herda o nome da trilha quando baixada "por trilha"), **tamanho · faixa de zoom · data** ("16 MB · z12–15 · 5 jul"), botão excluir.
- Botão tracejado **"+ Baixar nova área"**.

### Tela "Ajustes"
- **Armazenamento:** "Uso total do cache" + barra de uso + botão **"Limpar cache"**.
- **Preferências:** **Modo de alto contraste** ("cores mais fortes para uso no sol", default off) · **Manter tela ligada** ("não apagar durante a trilha", default on) · **Unidades** (toggle km/mi, default km).
- Rodapé: "soma_trails · v1.0 · offline-first".

### Tela "Fontes do mapa"
- Subtítulo: "Camada base do satélite. Apenas uma fica ativa por vez — toque para trocar."
- Card por fonte: **nome + badge "ATIVA" + zoom máx + URL template visível** + toggle.
- Botão tracejado **"+ Adicionar fonte"**.
- *(Desvio deliberado: Bing Aerial, mostrado no protótipo, não entra — descontinuado e usa quadkey. Defaults: Esri World Imagery + OSM Topo.)*

## Requisitos de plataforma (Android 14+ / One UI)

- **Permissões:** `ACCESS_FINE_LOCATION` (+ `ACCESS_COARSE_LOCATION`); `POST_NOTIFICATIONS` (Android 13+ — exigida pela notificação do foreground service).
- **Manifest:** `foregroundServiceType="location"` (obrigatório no Android 14+ para serviço de localização).
- **Gravação = foreground service com notificação persistente.** Sem isso, a One UI corta o GPS minutos depois de a tela apagar — é o risco nº 1 do produto, não um detalhe de implementação.
- **Otimização de bateria:** pedir isenção (`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`) e, se necessário, instruir a remover o app da lista de "apps suspensos/otimizados" da One UI.
- **Wakelock** (tela acesa) enquanto o app está em primeiro plano.
- **Storage:** `file_picker` usa SAF (sem permissão de storage); export de GPX para `Downloads/` via MediaStore (sem permissão extra). Trajetos vivem na pasta do app + export fácil — desinstalar o app sem exportar perde os trajetos, por isso o export é 1 toque.

## Durabilidade (o app precisa durar mais que o My Trails)

- Commitar o `pubspec.lock`; registrar a versão exata do Flutter no README (reconstruir daqui a anos sem caça ao tesouro).
- Gerar keystore de release próprio e **fazer backup** (perder o keystore = impossível atualizar por cima; teria que desinstalar e perder dados locais).
- **Arquivar o último APK bom** a cada versão que funcionou na trilha — se a toolchain apodrecer, o APK continua instalável.
- Atualizar dependências raramente e de propósito (quando algo quebrar ou for necessário), não por rotina.

## Plano de implementação (incremental)

1. **Scaffold Flutter** + dependências; keystore de release + backup; build/sideload de APK "hello map" no S24 Ultra (valida toolchain cedo).
2. **MapScreen com Esri já via FMTC (browse caching)** + controles de zoom/pan + `maxNativeZoom`/overzoom. Valida a dependência mais arriscada no início.
3. **LocationService** — ponto de GPS + recentralizar (testar permissões no device real).
4. **TrackManager** — importar múltiplos GPX + render multi-polyline + waypoints + painel ligar/desligar/cor + "Mostrar/Ocultar todas"; depois pastas + seleção múltipla.
5. **TrackRecorder** — gravar/pausar/parar + foreground service + polyline "meu trajeto" crescendo + HUD (distância/tempo) + auto-save GPX e retomada após reabrir o app.
6. **PointManager** — long-press marca ponto + painel "Pontos" (lista/excluir) + persistência.
7. **TileSourceConfig** — abstrair fonte por URL template + tela "Fontes do mapa" (ativa/adicionar/editar).
8. **OfflineDownloadController** — wizard: seleção por área e por trilha + estimativa + download em massa FMTC + progresso + gerenciar regiões.
9. **Offline real** — garantir render 100% do cache em modo avião; persistência de trilhas/regiões/trajetos/pontos entre sessões.
10. **Ajustes + polimento** — tela Ajustes completa (uso do cache + limpar cache, alto contraste, manter tela ligada, unidades km/mi), cores/legendas, indicador "offline pronto", export de GPX do trajeto, medição de bateria.

## Verificação (end-to-end)

- **Toolchain:** `flutter build apk` e instalar o APK no S24 Ultra.
- **Em casa (wi-fi):** importar 10+ GPX simultâneos e confirmar todas sobrepostas (com waypoints); baixar uma região de satélite com progresso e ver tamanho estimado.
- **Modo avião (crítico):** fechar e reabrir o app sem rede → mapa renderiza do cache, ponto de GPS se move, trilhas e pontos marcados continuam visíveis. Este teste é a definição de sucesso.
- **Overzoom:** dar zoom além do nível baixado → imagem escalada, nunca tela cinza.
- **Gravação:** iniciar a gravação, mover-se (ou simular), fechar/matar o app e reabrir → o trajeto gravado persiste, continua desenhado e a gravação retoma. Sem perda de rastro.
- **Tela desligada (crítico p/ One UI):** gravar ≥1h com a tela apagada e o celular no bolso → rastro contínuo, sem buracos (valida foreground service + isenção de bateria).
- **Bateria:** 3–4h gravando com tela majoritariamente apagada → consumo aceitável (alvo: ≲10%/h).
- **Campo:** teste real em uma trilha conhecida sem sinal.

## Perguntas em aberto (resolver na implementação)
- Confirmar URL/zoom máx exatos do Esri World Imagery (e eventuais fontes extras a incluir por padrão).
- Ajustar em campo os defaults de amostragem (distanceFilter, corte de accuracy, frequência de flush).
- Definir se há aviso/teto de tamanho por download (ex.: alertar acima de ~2 GB).
