import 'package:flutter_test/flutter_test.dart';
import 'package:medirapid/core/network/api_client.dart';
import 'package:medirapid/core/routes/app_routes.dart';
import 'package:medirapid/core/services/auth_controller.dart';
import 'package:medirapid/core/services/session_service.dart';
import 'package:medirapid/features/auth/models/driver_verification_info.dart';
import 'package:medirapid/features/auth/models/driver_verification_status.dart';
import 'package:medirapid/features/auth/providers/driver_verification_provider.dart';
import 'package:medirapid/features/driver/models/driver_profile_model.dart';
import 'package:medirapid/features/driver/providers/driver_provider.dart';
import 'package:medirapid/features/patient/models/emergency_model.dart';
import 'package:medirapid/features/patient/providers/patient_provider.dart';
import 'package:medirapid/models/user_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAuthRepository auth;
  late FakeVerificationRepository verificationRepo;
  late FakeDriverRepository driverRepo;
  late FakePatientRepository patientRepo;
  late SessionService session;
  late DriverProvider driver;
  late PatientProvider patient;
  late DriverVerificationProvider verification;
  late AuthController controller;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    auth = FakeAuthRepository();
    verificationRepo = FakeVerificationRepository();
    driverRepo = FakeDriverRepository();
    patientRepo = FakePatientRepository();
    session = SessionService();
    driver = DriverProvider(repository: driverRepo, locator: () async => null, pollInterval: null);
    patient = PatientProvider(repository: patientRepo, pollInterval: null);
    verification = DriverVerificationProvider(repository: verificationRepo);
    controller = AuthController(
      auth: auth,
      session: session,
      verification: verification,
      driver: driver,
      patient: patient,
    );
  });

  tearDown(() {
    driver.dispose();
    patient.dispose();
    ApiClient.instance.token = null;
  });

  void driverAccount({bool available = false}) {
    auth.user = const UserModel(id: 'u2', name: 'Asha', phone: '919000000002', role: UserRole.driver);
    auth.driver = DriverProfile(id: 'd1', isAvailable: available);
  }

  group('authenticate', () {
    test('patient sign-up saves the session and opens the SOS screen', () async {
      final route = await controller.authenticate(
        role: UserRole.patient,
        phone: '919000000001',
        name: 'Rahul',
        signUp: true,
      );

      expect(route, AppRoutes.patientHome);
      expect(auth.calls, ['signUp:Rahul:919000000001:patient']);
      expect(session.isLoggedIn, isTrue);
      expect(session.user!.name, 'Rahul');
      expect(ApiClient.instance.token, 'tok', reason: 'API calls are now authenticated');
    });

    test('patient login resumes an unfinished request', () async {
      patientRepo.history = [makeEmergency(id: 'live', status: EmergencyStatus.accepted)];

      await controller.authenticate(role: UserRole.patient, phone: '919000000001', signUp: false);

      expect(auth.calls, ['logIn:919000000001:patient'], reason: 'login sends no name');
      expect(patient.emergency!.id, 'live');
    });

    test('new driver goes to document verification', () async {
      driverAccount();
      verificationRepo.info = DriverVerificationInfo.notStarted;

      final route = await controller.authenticate(
        role: UserRole.driver,
        phone: '919000000002',
        name: 'Asha',
        signUp: true,
      );
      expect(route, AppRoutes.driverVerification);
    });

    test('driver under review goes to the pending screen', () async {
      driverAccount();
      verificationRepo.info = const DriverVerificationInfo(status: DriverVerificationStatus.pending);

      final route = await controller.authenticate(role: UserRole.driver, phone: '919000000002', signUp: false);
      expect(route, AppRoutes.driverVerificationPending);
    });

    test('rejected driver must resubmit', () async {
      driverAccount();
      verificationRepo.info = const DriverVerificationInfo(
        status: DriverVerificationStatus.rejected,
        reason: 'blurry',
      );

      final route = await controller.authenticate(role: UserRole.driver, phone: '919000000002', signUp: false);

      expect(route, AppRoutes.driverVerification);
      expect(verification.reason, 'blurry');
    });

    test('approved driver lands on the dashboard with the server availability', () async {
      driverAccount(available: true);
      verificationRepo.info = const DriverVerificationInfo(status: DriverVerificationStatus.approved);

      final route = await controller.authenticate(role: UserRole.driver, phone: '919000000002', signUp: false);

      expect(route, AppRoutes.driverHome);
      expect(driver.isOnline, isTrue);
    });

    test('approved driver with an unfinished trip resumes it', () async {
      driverAccount();
      verificationRepo.info = const DriverVerificationInfo(status: DriverVerificationStatus.approved);
      driverRepo.active = makeTrip(backendStatus: 'accepted');

      await controller.authenticate(role: UserRole.driver, phone: '919000000002', signUp: false);

      expect(driver.isOnTrip, isTrue);
    });

    test('unknown phone: error is passed on and nothing is saved', () async {
      auth.loginFailure = apiError(404, 'ACCOUNT_NOT_FOUND', 'No account found');

      await expectLater(
        controller.authenticate(role: UserRole.patient, phone: '919000009999', signUp: false),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'ACCOUNT_NOT_FOUND')),
      );
      expect(session.isLoggedIn, isFalse);
    });

    test('a driver whose status cannot be loaded gets a network error', () async {
      driverAccount();
      verificationRepo.failure = networkError;

      await expectLater(
        controller.authenticate(role: UserRole.driver, phone: '919000000002', signUp: false),
        throwsA(isA<ApiException>().having((e) => e.isNetworkError, 'network', isTrue)),
      );
    });
  });

  group('bootstrap (app start)', () {
    test('no saved login -> role selection, no network call', () async {
      expect(await controller.bootstrap(), AppRoutes.roleSelection);
      expect(auth.calls, isEmpty);
    });

    test('saved patient login -> SOS screen', () async {
      await session.save(token: 'tok', user: auth.user);
      expect(await controller.bootstrap(), AppRoutes.patientHome);
      expect(auth.calls, ['me']);
    });

    test('expired token -> cleared, role selection', () async {
      await session.save(token: 'old', user: auth.user);
      auth.meFailure = apiError(401, 'UNAUTHORIZED', 'Invalid or expired token.');

      expect(await controller.bootstrap(), AppRoutes.roleSelection);
      expect(session.isLoggedIn, isFalse);
    });

    test('no network -> the error is rethrown so the splash can offer retry', () async {
      await session.save(token: 'tok', user: auth.user);
      auth.meFailure = networkError;

      await expectLater(controller.bootstrap(), throwsA(isA<ApiException>()));
      expect(session.isLoggedIn, isTrue, reason: 'a flaky connection must not log you out');
    });
  });

  group('signOut', () {
    test('tells the server and wipes local state', () async {
      driverAccount(available: true);
      verificationRepo.info = const DriverVerificationInfo(status: DriverVerificationStatus.approved);
      await controller.authenticate(role: UserRole.driver, phone: '919000000002', signUp: false);

      await controller.signOut();

      expect(auth.calls.last, 'logout');
      expect(session.isLoggedIn, isFalse);
      expect(ApiClient.instance.token, isNull);
      expect(driver.isOnline, isFalse);
      expect(verification.status, DriverVerificationStatus.notStarted);
    });

    test('still signs out locally when the server is unreachable', () async {
      await controller.authenticate(role: UserRole.patient, phone: '1', signUp: false);
      auth.logoutFailure = networkError;

      await controller.signOut();

      expect(session.isLoggedIn, isFalse);
    });
  });
}
