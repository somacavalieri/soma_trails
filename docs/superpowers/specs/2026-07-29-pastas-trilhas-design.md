# Pastas de trilhas + ações em massa — design

**Data:** 2026-07-29
**Contexto:** sobra do passo 4 do plano do PRD ("depois pastas + seleção múltipla"). O painel Trilhas hoje é uma lista plana; com 50+ GPX importados fica impossível de navegar. O protótipo `docs/prototype.html` é a fonte de verdade do UI e já mostra pastas expansíveis, "Nova pasta · Selecionar" e o sheet "Pastas desta trilha".

## Objetivo

Organizar as trilhas do painel em **pastas** (1 nível, sem aninhamento), com:

1. Criar/renomear/excluir pastas.
2. Uma trilha pode pertencer a **várias pastas ao mesmo tempo** (ou a nenhuma).
3. Mostrar/ocultar **em massa por pasta** (olho na linha da pasta).
4. Modo **Selecionar** com ações em massa: adicionar à pasta e excluir trilhas.

## Decisões travadas (com o dono)

- **Olho da pasta é ação em massa, não estado.** Tocar mostra/oculta todas as trilhas da pasta naquele momento. A visibilidade continua sendo propriedade da trilha (fonte única — sem conflito quando a trilha está em duas pastas). O ícone da pasta reflete o agregado: todas visíveis, nenhuma visível, ou parcial (ícone diferenciado).
- **Trilhas sem pasta ficam soltas na raiz**, listadas depois das pastas.
- **Excluir pasta pergunta na hora**: diálogo com "Só a pasta" (trilhas ficam no app), "Pasta e trilhas" (exclui os GPX das trilhas dela) e Cancelar. O texto mostra a contagem de trilhas e avisa se alguma também pertence a outra pasta (ela some de lá também).
- **Ações em massa do v1:** Adicionar à pasta… e Excluir selecionadas. (Mostrar/ocultar selecionadas e remover-de-pasta em massa ficam de fora.)

## Modelo de dados e persistência

Abordagem escolhida: **pertencimento na trilha** (alternativa "pasta guarda trackIds" descartada — exigiria lookup reverso e limpeza em toda exclusão).

- `Track.folderId: String?` → **`folderIds: List<String>`**. Migração automática no `load()`: `folderId` presente vira `[folderId]`; o JSON novo grava `folderIds`.
- Novo model **`TrackFolder { id, name }`** em `lib/models/track_folder.dart`, persistido em **`folders.json`** ao lado do `tracks.json` (mesmo diretório `tracks/`). Ordem da lista = ordem de exibição (criação; sem reordenar no v1).
- `folderIds` que apontam para pasta inexistente são ignorados na renderização e limpos no próximo save.

## TrackManager (única fonte de estado, como hoje)

Novas APIs (todas com `_save()` + `notifyListeners()`):

- `List<TrackFolder> get folders`
- `Future<TrackFolder> createFolder(String name)`
- `Future<void> renameFolder(String id, String name)`
- `Future<void> deleteFolder(String id, {required bool deleteTracks})` — com `deleteTracks: true`, exclui (GPX + metadados) toda trilha que pertença à pasta, mesmo que também esteja em outra.
- `Future<void> setTrackFolders(String trackId, Set<String> folderIds)` — aplica o resultado do sheet de checkboxes.
- `Future<void> addToFolder(List<String> trackIds, String folderId)` — ação em massa (adiciona sem tirar das outras pastas).
- `Future<void> setFolderVisible(String folderId, bool visible)` — liga/desliga todas as trilhas da pasta.
- `Future<void> removeMany(List<String> trackIds)` — exclusão em massa (GPX + metadados).
- Helpers de leitura: `tracksInFolder(String folderId)`, `looseTracks` (sem pasta), e o agregado de visibilidade por pasta (`all | none | partial`) para o ícone do olho.

## UI — painel Trilhas (`tracks_panel.dart`)

Segue o protótipo:

- **Linhas de ação:** "Nova pasta · Selecionar" acima de "Mostrar/Ocultar todas". "Nova pasta" abre diálogo de nome (mesmo estilo do renomear atual).
- **Lista raiz:** pastas primeiro (expansíveis), depois trilhas avulsas. Pastas abrem **colapsadas** (estado não persiste).
- **Linha de pasta:** chevron + ícone de pasta + nome + resumo "N trilhas · M visíveis" + olho agregado + menu ⋮ (Renomear, Excluir). Tocar na linha expande/colapsa; tocar no olho aplica mostrar/ocultar em massa.
- **Trilhas dentro da pasta:** mesmas linhas de trilha atuais, indentadas. Trilha em 2 pastas aparece sob as duas (e também não aparece nas avulsas).
- **Menu ⋮ da trilha:** ganha o item **"Pastas…"**, que abre o sheet **"Pastas desta trilha"** (referência de design): checkboxes com as pastas existentes (marcadas as atuais), botão "+ Criar nova pasta" inline (cria e já marca), botão **Concluir** aplica via `setTrackFolders`.

## UI — modo Selecionar

- Botão "Selecionar" entra no modo: as linhas de trilha ganham checkbox (pastas não são selecionáveis no v1), o header vira "N selecionadas" + "Cancelar".
- Barra fixa no rodapé do sheet com duas ações:
  - **Adicionar à pasta…** — abre o mesmo sheet de pastas (checkboxes, sem pré-marcação; "+ Criar nova pasta" disponível); Concluir chama `addToFolder` para cada pasta marcada.
  - **Excluir** — confirmação com contagem ("Excluir N trilhas? Os arquivos serão removidos do app.") → `removeMany`.
- Concluir qualquer ação (ou Cancelar) sai do modo seleção.

## Erros e casos-limite

- Nome de pasta vazio → não cria/renomeia (mesmo comportamento do renomear trilha atual).
- Nomes duplicados de pasta são permitidos (ids distintos); sem validação extra no v1.
- Pasta vazia é válida (resumo "0 trilhas") e pode ser excluída direto (diálogo simples, sem opção "pasta e trilhas").
- `folders.json` corrompido/ausente → lista de pastas vazia, trilhas todas avulsas (nunca derruba o app; mesmo padrão do `load()` atual).

## Testes

- Migração `folderId` → `folderIds` no load.
- CRUD de pasta + `deleteFolder` com e sem `deleteTracks` (incluindo trilha em 2 pastas).
- `setTrackFolders` / `addToFolder` (idempotente: adicionar à pasta já pertencida não duplica).
- `setFolderVisible` e o agregado all/none/partial.
- `removeMany` apaga arquivos e metadados.
- Persistência round-trip de `folders.json` + `tracks.json`.

## Fora de escopo (v1)

Aninhamento e reordenação de pastas, mostrar/ocultar selecionadas, remover-de-pasta em massa, seleção de pasta inteira no modo Selecionar, importar direto para uma pasta, persistir estado expandido.
