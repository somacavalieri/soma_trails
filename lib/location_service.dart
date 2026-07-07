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

  /// Serializa as (re)ligações do stream para nunca rodarem em paralelo.
  Future<void> _bindLock = Future.value();

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

  /// No Android NÃO usamos distanceFilter: ele vira `smallestDisplacement` no
  /// fused provider, que em Samsungs suprime updates até congelar o stream
  /// (entrega poucos fixes e silencia mesmo em movimento — visto no S24 Ultra:
  /// "fixes 4 · último 916s"). Em vez disso, updates por TEMPO (~2 s) e o
  /// filtro de distância fica na camada do app (TrackRecorder, ~5 m).
  LocationSettings _settings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 2),
        foregroundNotificationConfig: _foreground
            ? const ForegroundNotificationConfig(
                notificationTitle: 'soma_trails — gravando trajeto',
                notificationText:
                    'Registrando seu caminho, mesmo com a tela apagada.',
                notificationChannelName: 'Gravação de trajeto',
                enableWakeLock: true,
                setOngoing: true,
              )
            : null,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
    );
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

  /// Liga o stream de posições. Idempotente: se já está ligado, não religa
  /// (evitar religar à toa é o que impede a corrida que congelava o GPS).
  /// Chamar após [ensureReady].
  Future<void> start({bool foreground = false}) async {
    if (_bound) return;
    _bound = true;
    _foreground = foreground;
    await _bind();
  }

  /// Alterna entre modo normal e foreground service (gravação). Só religa se o
  /// modo realmente mudou; o stream público [positions] permanece o mesmo.
  Future<void> setForeground(bool value) async {
    if (_foreground == value) return;
    _foreground = value;
    await _bind();
  }

  /// (Re)liga o stream do geolocator. Serializado e esperando o cancelamento
  /// do stream anterior TERMINAR antes de religar — senão o "stop" nativo
  /// atrasado do stream antigo mata o novo (no One UI: 1 fix e congela).
  Future<void> _bind() {
    return _bindLock = _bindLock.then((_) async {
      _bound = true;
      final old = _source;
      _source = null;
      await old?.cancel();
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
    });
  }

  Future<Position?> lastKnown() => Geolocator.getLastKnownPosition();

  Future<void> openAppSettings() => Geolocator.openAppSettings();

  Future<void> dispose() async {
    await _source?.cancel();
    await _controller.close();
  }
}
