/// Uma pasta do painel Trilhas. Só agrupa: a visibilidade continua sendo
/// propriedade de cada trilha, e uma trilha pode estar em várias pastas
/// (`Track.folderIds`). Um nível só — pastas não aninham.
class TrackFolder {
  TrackFolder({required this.id, required this.name});

  final String id;
  String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  static TrackFolder fromJson(Map<String, dynamic> e) =>
      TrackFolder(id: e['id'] as String, name: e['name'] as String);
}
