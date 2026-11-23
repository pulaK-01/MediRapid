import 'package:medirapid/core/network/api_client.dart';
import 'package:medirapid/features/driver/models/driver_profile_model.dart';
import 'package:medirapid/models/user_model.dart';

class AuthSession {
  const AuthSession({required this.token, required this.user, this.driver});

  final String token;
  final UserModel user;
  final DriverProfile? driver;
}

class MeResult {
  const MeResult({required this.user, this.driver});

  final UserModel user;
  final DriverProfile? driver;
}

/// Talks to /auth/*. The backend's login is a demo login (no SMS): the phone
/// number identifies the account, scoped by role.
class AuthRepository {
  AuthRepository({ApiClient? api}) : _injected = api;

  final ApiClient? _injected;
  ApiClient get _api => _injected ?? ApiClient.instance;

  /// Creates the account (or updates the name of an existing one).
  Future<AuthSession> signUp({
    required String name,
    required String phone,
    required UserRole role,
  }) => _login({'name': name, 'phone': phone, 'role': role.apiName});

  /// Phone-only login; fails with ACCOUNT_NOT_FOUND for unknown numbers.
  Future<AuthSession> logIn({
    required String phone,
    required UserRole role,
  }) => _login({'phone': phone, 'role': role.apiName});

  Future<AuthSession> _login(Map<String, Object?> body) async {
    final json = await _api.post('/auth/demo', body: body, auth: false);
    final driver = json['driver'];
    return AuthSession(
      token: json['access_token'] as String,
      user: UserModel.fromJson(json['user'] as Map<String, dynamic>),
      driver: driver is Map<String, dynamic>
          ? DriverProfile.fromJson(driver)
          : null,
    );
  }

  Future<MeResult> me() async {
    final json = await _api.get('/auth/me');
    final driver = json['driver'];
    return MeResult(
      user: UserModel.fromJson(json['user'] as Map<String, dynamic>),
      driver: driver is Map<String, dynamic>
          ? DriverProfile.fromJson(driver)
          : null,
    );
  }

  Future<void> logout() async {
    await _api.post('/auth/logout');
  }
}
