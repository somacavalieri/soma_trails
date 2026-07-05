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
  });

  /// Identificador estável usado como nome do store no FMTC. Não renomear.
  final String id;
  final String name;
  final String urlTemplate;
  final int maxNativeZoom;
  final String attribution;
  final List<String> subdomains;

  String get storeName => 'src_$id';
}

/// Fontes padrão do app. Bing ficou de fora de propósito (descontinuado + quadkey).
/// Editável no futuro pela tela "Fontes do mapa" (passo 7).
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

  static const all = [esri, osmTopo];

  /// Fonte ativa por padrão. Em passos futuros isso vem da persistência.
  static const active = esri;
}
