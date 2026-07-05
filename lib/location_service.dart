import 'package:geolocator/geolocator.dart';

/// Resultado de tentar obter permissão + serviço de localização ligados.
enum LocationReadyResult {
  ready,

  /// Usuário negou nesta sessão (pode pedir de novo).
  denied,

  /// Negado permanentemente — só resolve nas configurações do sistema.
  deniedForever,

  /// GPS/localização desligado no aparelho.
  serviceDisabled,
}

/// Fonte única de localização do app. Um só `getPositionStream` do geolocator,
/// exposto como broadcast para que o marcador de GPS (passo 3) e o gravador de
/// trajeto (passo 5) consumam a MESMA leitura, sem duplicar o GPS.
///
/// Funciona offline: GPS é posicionamento por satélite, não precisa de rede.
class LocationService {
  Stream<Position>? _positions;

  /// Amostragem: ~5 m entre pontos, precisão máxima. Filtros mais finos (corte
  /// de accuracy) ficam no gravador, onde importam para não fazer "novelo".
  static const LocationSettings _settings = LocationSettings(
    accuracy: LocationAccuracy.best,
    distanceFilter: 5,
  );

  /// Garante permissão e serviço ligados. Chamar antes de assinar [positions].
  Future<LocationReadyResult> ensureReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationReadyResult.serviceDisabled;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    switch (permission) {
      case LocationPermission.denied:
        return LocationReadyResult.denied;
      case LocationPermission.deniedForever:
        return LocationReadyResult.deniedForever;
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationReadyResult.ready;
      case LocationPermission.unableToDetermine:
        return LocationReadyResult.denied;
    }
  }

  /// Stream compartilhado de posições. Criado sob demanda; broadcast para
  /// múltiplos ouvintes (marcador + gravador).
  Stream<Position> get positions =>
      _positions ??= Geolocator.getPositionStream(locationSettings: _settings)
          .asBroadcastStream();

  /// Última posição conhecida (rápida, pode ser levemente defasada). Útil para
  /// centralizar o mapa imediatamente ao tocar em "recentralizar".
  Future<Position?> lastKnown() => Geolocator.getLastKnownPosition();

  /// Abre as configurações do app (quando permissão foi negada permanentemente).
  Future<void> openAppSettings() => Geolocator.openAppSettings();
}
