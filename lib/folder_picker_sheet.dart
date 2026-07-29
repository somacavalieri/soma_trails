import 'package:flutter/material.dart';

import 'models/track_folder.dart';
import 'theme.dart';
import 'track_manager.dart';

/// Diálogo "Nova pasta" (nome + Cancelar/Criar) compartilhado entre o painel
/// de Trilhas e este sheet — evita duplicar o mesmo AlertDialog nos dois
/// lugares. Retorna a pasta criada, ou null se cancelado/nome vazio.
Future<TrackFolder?> promptCreateFolder(
    BuildContext context, TrackManager manager) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Nova pasta'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Nome da pasta'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Criar'),
        ),
      ],
    ),
  );
  if (name == null) return null;
  return manager.createFolder(name);
}

/// Sheet de escolha de pastas (checkboxes) usado em dois fluxos:
/// - "Pastas desta trilha" (menu da trilha): pré-marca as pastas atuais e o
///   Concluir SUBSTITUI o conjunto (via setTrackFolders).
/// - "Adicionar à pasta" (modo Selecionar): nada pré-marcado e o Concluir
///   ADICIONA às pastas marcadas (via addToFolder).
/// O comportamento fica no [onConfirm]; o sheet só coleta o conjunto.
Future<void> showFolderPickerSheet(
  BuildContext context,
  TrackManager manager, {
  required String title,
  String? subtitle,
  Set<String> initiallySelected = const {},
  required Future<void> Function(Set<String> folderIds) onConfirm,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.panel,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _FolderPickerSheet(
      manager: manager,
      title: title,
      subtitle: subtitle,
      initiallySelected: initiallySelected,
      onConfirm: onConfirm,
    ),
  );
}

class _FolderPickerSheet extends StatefulWidget {
  const _FolderPickerSheet({
    required this.manager,
    required this.title,
    required this.subtitle,
    required this.initiallySelected,
    required this.onConfirm,
  });

  final TrackManager manager;
  final String title;
  final String? subtitle;
  final Set<String> initiallySelected;
  final Future<void> Function(Set<String>) onConfirm;

  @override
  State<_FolderPickerSheet> createState() => _FolderPickerSheetState();
}

class _FolderPickerSheetState extends State<_FolderPickerSheet> {
  late final Set<String> _selected = {...widget.initiallySelected};

  Future<void> _createFolder() async {
    final folder = await promptCreateFolder(context, widget.manager);
    if (folder != null) setState(() => _selected.add(folder.id));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: ListenableBuilder(
          listenable: widget.manager,
          builder: (context, child) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
              if (widget.subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(widget.subtitle!,
                      style: const TextStyle(color: AppColors.textDim)),
                ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final folder in widget.manager.folders)
                      CheckboxListTile(
                        value: _selected.contains(folder.id),
                        onChanged: (checked) => setState(() {
                          checked == true
                              ? _selected.add(folder.id)
                              : _selected.remove(folder.id);
                        }),
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: AppColors.accent,
                        secondary: const Icon(Icons.folder_outlined,
                            color: AppColors.accent),
                        title: Text(folder.name),
                        subtitle: Text(
                          '${widget.manager.tracksInFolder(folder.id).length} trilhas',
                          style: const TextStyle(
                              color: AppColors.textDim, fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: const BorderSide(color: AppColors.accent, width: 1),
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _createFolder,
                icon: const Icon(Icons.add),
                label: const Text('Criar nova pasta'),
              ),
              const SizedBox(height: 10),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: () async {
                  await widget.onConfirm(_selected);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Concluir'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
