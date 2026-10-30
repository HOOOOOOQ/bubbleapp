import 'dart:async';
import 'dart:io';

/// Lightweight connectivity check — no extra dependency required.
///
/// Uses DNS lookup + socket probe. Works on all platforms without native plugins.
class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  final _controller = StreamController<bool>.broadcast();
  Timer? _timer;
  bool _isOnline = true;

  bool get isOnline => _isOnline;
  Stream<bool> get onStatusChange => _controller.stream;

  void start({Duration interval = const Duration(seconds: 8)}) {
    _checkNow();
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _checkNow());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<bool> checkNow() => _checkNow();

  Future<bool> _checkNow() async {
    bool online;
    try {
      final result = await InternetAddress.lookup('supabase.co').timeout(const Duration(seconds: 4));
      online = result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      online = false;
    }
    if (online != _isOnline) {
      _isOnline = online;
      _controller.add(online);
    }
    return online;
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
