import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkMonitor {
  static final NetworkMonitor instance = NetworkMonitor._internal();
  NetworkMonitor._internal() {
    _init();
  }

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  final _statusController = StreamController<bool>.broadcast();
  Stream<bool> get onStatusChanged => _statusController.stream;

  final _connectionLostController = StreamController<void>.broadcast();
  Stream<void> get onConnectionLost => _connectionLostController.stream;

  final _connectionRestoredController = StreamController<void>.broadcast();
  Stream<void> get onConnectionRestored => _connectionRestoredController.stream;

  Future<void> _init() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _isOnline = _checkIsConnected(results);
    } catch (_) {
      _isOnline = true;
    }

    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final connected = _checkIsConnected(results);
      if (connected != _isOnline) {
        _isOnline = connected;
        _statusController.add(_isOnline);

        if (!_isOnline) {
          _connectionLostController.add(null);
        } else {
          _connectionRestoredController.add(null);
        }
      }
    });
  }

  bool _checkIsConnected(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    // If any connection is NOT .none, we have connectivity
    return results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet);
  }

  Future<bool> checkConnection() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _isOnline = _checkIsConnected(results);
      return _isOnline;
    } catch (_) {
      return _isOnline;
    }
  }

  Future<bool> hasActualInternet() async {
    try {
      final results = await _connectivity.checkConnectivity();
      if (!_checkIsConnected(results)) {
        _isOnline = false;
        return false;
      }
      final lookup = await InternetAddress.lookup('clients3.google.com')
          .timeout(const Duration(milliseconds: 2000));
      final success = lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty;
      _isOnline = success;
      return success;
    } catch (_) {
      try {
        final lookup2 = await InternetAddress.lookup('yandex.ru')
            .timeout(const Duration(milliseconds: 2000));
        final success = lookup2.isNotEmpty && lookup2[0].rawAddress.isNotEmpty;
        _isOnline = success;
        return success;
      } catch (_) {
        _isOnline = false;
        return false;
      }
    }
  }

  void dispose() {
    _subscription?.cancel();
    _statusController.close();
    _connectionLostController.close();
    _connectionRestoredController.close();
  }
}
