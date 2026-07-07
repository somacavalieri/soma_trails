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
  DateTime? _lastBindAt;
  Object? _lastError;
  int _rebindCount = 0;
  int get fixCount => _fixCount;
  DateTime? get lastFixAt => _lastFixAt;
  bool get isForeground => _foreground;
  Object? get lastError => _lastError;
  int get rebindCount => _rebindCount;

  Timer? _watchdog;

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
    _startWatchdog();
    if (_bound) return;
    _bound = true;
    _foreground = foreground;
    await _bind();
  }

  /// Auto-cura: se o stream ficar mudo por muito tempo (morte silenciosa do
  /// serviço nativo — pior defeito possível na trilha), religa sozinho.
  void _startWatchdog() {
    _watchdog ??= Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_bound) return;
      // Referência = o evento mais recente (fix OU religação), para não
      // religar em loop quando o GPS legitimamente está sem sinal.
      final fix = _lastFixAt;
      final bind = _lastBindAt;
      final ref = switch ((fix, bind)) {
        (null, null) => null,
        (final f?, null) => f,
        (null, final b?) => b,
        (final f?, final b?) => f.isAfter(b) ? f : b,
      };
      if (ref == null) return;
      if (DateTime.now().difference(ref) > const Duration(seconds: 30)) {
        _rebindCount++;
        _bind();
      }
    });
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
      if (old != null) {
        await old.cancel();
        // O cancel do lado Dart retorna antes de o serviço nativo do plugin
        // terminar de desmontar; religar em cima disso deixa o novo stream
        // mudo (visto no S24 Ultra ao iniciar a gravação). A pausa dá tempo
        // do desmonte concluir; se ainda assim ficar mudo, o watchdog religa.
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      _lastBindAt = DateTime.now();
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
    _watchdog?.cancel();
    await _source?.cancel();
    await _controller.close();
  }
}
