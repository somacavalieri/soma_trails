import 'dart:async';
import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';

/// Resultado de tentar obter permissão + serviço de localização ligados.
enum LocationReadyResult {
  ready,
  denied,
  deniedForever,
  serviceDisabled,
}

/// Fonte única de localização do app. Publica posições num broadcast estável
/// ([positions]) e troca a fonte interna do geolocator conforme o modo:
///
/// - **Normal:** só ver a posição no mapa.
/// - **Foreground (gravação):** roda como *foreground service* com notificação
///   persistente + wakelock, para o One UI (Samsung) não matar o GPS com a tela
///   apagada. Como o stream público não muda, o marcador de GPS e o gravador
///   seguem lendo a MESMA leitura — sem GPS duplicado.
class LocationService {
  final _controller = StreamController<Position>.broadcast();
  StreamSubscription<Position>? _source;
  bool _foreground = false;
  bool _bound = false;

  Position? _last;
  Position? get last => _last;

  // Diagnóstico (painel de depuração)
  int _fixCount = 0;
  DateTime? _lastFixAt;
  Object? _lastError;
  int get fixCount => _fixCount;
  DateTime? get lastFixAt => _lastFixAt;
  bool get isForeground => _foreground;
  Object? get lastError => _lastError;

  Stream<Position> get positions => _controller.stream;

  static const LocationSettings _normal = LocationSettings(
    accuracy: LocationAccuracy.best,
    distanceFilter: 5,
  );

  LocationSettings _settings() {
    if (_foreground && Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'soma_trails — gravando trajeto',
          notificationText: 'Registrando seu caminho, mesmo com a tela apagada.',
          notificationChannelName: 'Gravação de trajeto',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    return _normal;
  }

  Future<LocationReadyResult> ensureReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationReadyResult.serviceDisabled;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return switch (permission) {
      LocationPermission.denied => LocationReadyResult.denied,
      LocationPermission.deniedForever => LocationReadyResult.deniedForever,
      LocationPermission.always ||
      LocationPermission.whileInUse =>
        LocationReadyResult.ready,
      LocationPermission.unableToDetermine => LocationReadyResult.denied,
    };
  }

  /// Liga o stream de posições (idempotente). Chamar após [ensureReady].
  void start({bool foreground = false}) {
    _foreground = foreground;
    _bind();
  }

  /// Alterna entre modo normal e foreground service (gravação). Recria a fonte
  /// interna; o stream público [positions] permanece o mesmo.
  Future<void> setForeground(bool value) async {
    if (_bound && _foreground == value) return;
    _foreground = value;
    _bind();
  }

  void _bind() {
    _bound = true;
    _source?.cancel();
    _source = Geolocator.getPositionStream(locationSettings: _settings())
        .listen(
      (p) {
        _last = p;
        _fixCount++;
        _lastFixAt = DateTime.now();
        _controller.add(p);
      },
      onError: (Object e) {
        _lastError = e;
        _controller.addError(e);
      },
    );
  }

  Future<Position?> lastKnown() => Geolocator.getLastKnownPosition();

  Future<void> openAppSettings() => Geolocator.openAppSettings();

  Future<void> dispose() async {
    await _source?.cancel();
    await _controller.close();
  }
}
