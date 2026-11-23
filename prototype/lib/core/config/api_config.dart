import 'package:flutter/foundation.dart';

/// Backend location.
///
/// Override at build/run time:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8080/api/v1
///
/// Defaults:
///   * Android emulator -> http://10.0.2.2:8080/api/v1 (host machine's localhost)
///   * everything else  -> http://localhost:8080/api/v1 (iOS simulator, desktop, web)
/// A physical phone needs your computer's LAN IP via --dart-define.
class ApiConfig {
  static const String _override = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080/api/v1';
    }
    return 'http://localhost:8080/api/v1';
  }

  static const Duration timeout = Duration(seconds: 15);
}
