import 'dart:convert';

import 'package:medirapid/core/network/api_client.dart';
import 'package:medirapid/core/services/app_state_service.dart';
import 'package:medirapid/models/user_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the login (token + user) so the app reopens signed in.
class SessionService {
  SessionService();

  static final SessionService instance = SessionService();

  static const _tokenKey = 'session_token';
  static const _userKey = 'session_user';

  String? _token;
  UserModel? _user;

  String? get token => _token;
  UserModel? get user => _user;
  bool get isLoggedIn => _token != null && _user != null;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    final raw = prefs.getString(_userKey);
    if (raw != null) {
      try {
        _user = UserModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        _user = null;
        _token = null;
      }
    }
    _apply();
  }

  Future<void> save({required String token, required UserModel user}) async {
    _token = token;
    _user = user;
    _apply();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
  }

  /// Clears synchronously first (so concurrent 401 handlers see "logged out"
  /// immediately), then removes the stored copy.
  Future<void> clear() async {
    _token = null;
    _user = null;
    _apply();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }

  void _apply() {
    ApiClient.instance.token = _token;
    AppStateService.isAuthenticated = _token != null;
    AppStateService.currentRole = _user?.role.apiName ?? 'patient';
  }
}
