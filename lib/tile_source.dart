/// Uma fonte de tiles configurável (satélite/topo).
///
/// Cada fonte tem seu próprio store no FMTC (`storeName`), para que baixar/limpar
/// uma não afete as outras. `maxNativeZoom` é o zoom máximo que a fonte serve de
/// verdade; acima disso o mapa faz overzoom (escala) em vez de mostrar tela cinza.
class TileSource {
  const TileSource({
    required this.id,
    required this.name,
    required this.urlTemplate,
    required this.maxNativeZoom,
    required this.attribution,
    this.subdomains = const [],
    this.custom = false,
  });

  /// Identificador estável usado como nome do store no FMTC. Não renomear.
  final String id;
  final String name;
  final String urlTemplate;
  final int maxNativeZoom;
  final String attribution;
  final List<String> subdomains;

  /// Fonte adicionada pelo usuário (pode ser removida).
  final bool custom;

  String get storeName => 'src_$id';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'urlTemplate': urlTemplate,
        'maxNativeZoom': maxNativeZoom,
        'attribution': attribution,
        'subdomains': subdomains,
      };

  factory TileSource.fromJson(Map<String, dynamic> j) => TileSource(
        id: j['id'] as String,
        name: j['name'] as String,
        urlTemplate: j['urlTemplate'] as String,
        maxNativeZoom: (j['maxNativeZoom'] as num?)?.toInt() ?? 18,
        attribution: j['attribution'] as String? ?? '',
        subdomains:
            (j['subdomains'] as List<dynamic>?)?.cast<String>() ?? const [],
        custom: true,
      );
}

/// Fontes padrão do app. Bing ficou de fora de propósito (descontinuado + quadkey).
class TileSources {
  static const esri = TileSource(
    id: 'esri_world_imagery',
    name: 'Esri World Imagery',
    urlTemplate:
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    maxNativeZoom: 19,
    attribution: 'Esri World Imagery',
  );

  static const osmTopo = TileSource(
    id: 'osm_topo',
    name: 'OSM Topo',
    urlTemplate: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
    maxNativeZoom: 17,
    attribution: 'OpenTopoMap (CC-BY-SA)',
    subdomains: ['a', 'b', 'c'],
  );

  static const defaults = [esri, osmTopo];
}
