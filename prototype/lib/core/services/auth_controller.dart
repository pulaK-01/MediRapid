import 'package:medirapid/core/network/api_client.dart';
import 'package:medirapid/core/routes/app_routes.dart';
import 'package:medirapid/core/services/session_service.dart';
import 'package:medirapid/features/auth/models/driver_verification_status.dart';
import 'package:medirapid/features/auth/providers/driver_verification_provider.dart';
import 'package:medirapid/features/auth/repositories/auth_repository.dart';
import 'package:medirapid/features/driver/models/driver_profile_model.dart';
import 'package:medirapid/features/driver/providers/driver_provider.dart';
import 'package:medirapid/features/patient/providers/patient_provider.dart';
import 'package:medirapid/models/user_model.dart';

/// What the phone-auth screen needs (lets widget tests swap in a fake).
abstract class AuthFlow {
  /// Signs in/up and returns the route to open next.
  Future<String> authenticate({
    required UserRole role,
    required String phone,
    String? name,
    required bool signUp,
  });
}

/// Owns login, logout, and "which screen should the app open on?".
class AuthController implements AuthFlow {
  AuthController({
    AuthRepository? auth,
    SessionService? session,
    DriverVerificationProvider? verification,
    DriverProvider? driver,
    PatientProvider? patient,
  }) : _auth = auth ?? AuthRepository(),
       _session = session ?? SessionService.instance,
       _verification = verification ?? DriverVerificationProvider.instance,
       _driver = driver ?? DriverProvider.instance,
       _patient = patient ?? PatientProvider.instance;

  static final AuthController instance = AuthController();

  final AuthRepository _auth;
  final SessionService _session;
  final DriverVerificationProvider _verification;
  final DriverProvider _driver;
  final PatientProvider _patient;

  @override
  Future<String> authenticate({
    required UserRole role,
    required String phone,
    String? name,
    required bool signUp,
  }) async {
    final result = signUp
        ? await _auth.signUp(name: name ?? '', phone: phone, role: role)
        : await _auth.logIn(phone: phone, role: role);
    await _session.save(token: result.token, user: result.user);
    return _enter(result.user.role, driver: result.driver);
  }

  /// App start: decide where to go from the stored session.
  /// Throws [ApiException] for network problems (the splash offers a retry).
  Future<String> bootstrap() async {
    if (!_session.isLoggedIn) return AppRoutes.roleSelection;
    try {
      final me = await _auth.me();
      await _session.save(token: _session.token!, user: me.user);
      return _enter(me.user.role, driver: me.driver);
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await clearLocalSession();
        return AppRoutes.roleSelection;
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.logout();
    } on ApiException {
      // Offline or already expired: still sign out locally.
    }
    await clearLocalSession();
  }

  /// Forgets the login and all cached state (no network call).
  Future<void> clearLocalSession() async {
    final cleared = _session.clear(); // flips the token off synchronously
    _driver.resetSession();
    _patient.reset();
    _verification.reset();
    await cleared;
  }

  Future<String> _enter(UserRole role, {DriverProfile? driver}) async {
    if (role == UserRole.patient) {
      _driver.resetSession();
      _verification.reset();
      await _patient.restore();
      return AppRoutes.patientHome;
    }

    _patient.reset();
    final ok = await _verification.refresh();
    if (!ok) {
      throw ApiException(
        statusCode: 0,
        code: 'NETWORK',
        message:
            _verification.error ?? 'Could not load your verification status.',
      );
    }
    switch (_verification.status) {
      case DriverVerificationStatus.approved:
        await _driver.restore(isAvailable: driver?.isAvailable ?? false);
        return AppRoutes.driverHome;
      case DriverVerificationStatus.pending:
        return AppRoutes.driverVerificationPending;
      case DriverVerificationStatus.notStarted:
      case DriverVerificationStatus.rejected:
        return AppRoutes.driverVerification;
    }
  }
}
