import 'package:medirapid/core/network/api_client.dart';
import 'package:medirapid/core/services/auth_controller.dart';
import 'package:medirapid/features/auth/models/driver_verification_info.dart';
import 'package:medirapid/features/auth/repositories/auth_repository.dart';
import 'package:medirapid/features/auth/repositories/driver_verification_repository.dart';
import 'package:medirapid/features/driver/models/driver_profile_model.dart';
import 'package:medirapid/features/driver/models/trip_model.dart';
import 'package:medirapid/features/driver/repositories/driver_repository.dart';
import 'package:medirapid/features/patient/models/emergency_model.dart';
import 'package:medirapid/features/patient/repositories/patient_repository.dart';
import 'package:medirapid/models/user_model.dart';

ApiException apiError(int status, String code, [String message = 'error']) =>
    ApiException(statusCode: status, code: code, message: message);

const networkError = ApiException(
  statusCode: 0,
  code: 'NETWORK',
  message: 'Cannot reach the server.',
);

Trip makeTrip({
  String id = 'e1',
  String backendStatus = 'requested',
  TripStatus status = TripStatus.requested,
  double distanceKm = 4.2,
  bool patientAssessed = false,
  bool firstAidGiven = false,
  bool patientLoaded = false,
  double? fare,
  DateTime? completedAt,
}) => Trip(
  id: id,
  patientName: 'Rahul',
  patientPhone: '919000000001',
  distanceKm: distanceKm,
  requestedAt: DateTime(2026, 11, 1, 10),
  pickup: 'Durgapur',
  destination: Trip.defaultDestination,
  status: status,
  backendStatus: backendStatus,
  patientAssessed: patientAssessed,
  firstAidGiven: firstAidGiven,
  patientLoaded: patientLoaded,
  fare: fare,
  completedAt: completedAt,
);

Emergency makeEmergency({
  String id = 'e1',
  EmergencyStatus status = EmergencyStatus.requested,
  EmergencyDriver? driver,
}) => Emergency(
  id: id,
  status: status,
  latitude: 23.52,
  longitude: 87.31,
  createdAt: DateTime(2026, 11, 1, 10),
  driver: driver,
);

/// Scriptable stand-in for the driver endpoints.
class FakeDriverRepository implements DriverRepository {
  final List<String> calls = [];
  List<Trip> requests = [];
  List<Trip> trips = [];
  Trip? active;
  double fare = 250;

  /// Key = method name ("availability", "requests", "accept", "decline",
  /// "status", "status:en_route", "checklist", "trips", "active").
  /// Each entry throws once, then is removed.
  final Map<String, ApiException> failures = {};

  void _maybeFail(String key, [String? specific]) {
    final error =
        (specific == null ? null : failures.remove(specific)) ??
        failures.remove(key);
    if (error != null) throw error;
  }

  @override
  Future<void> setAvailability(bool online) async {
    calls.add('availability:$online');
    _maybeFail('availability');
  }

  @override
  Future<List<Trip>> fetchRequests({double? lat, double? lng}) async {
    calls.add('requests');
    _maybeFail('requests');
    return List.of(requests);
  }

  @override
  Future<void> accept(String emergencyId) async {
    calls.add('accept:$emergencyId');
    _maybeFail('accept');
  }

  @override
  Future<void> decline(String emergencyId, {String? reason}) async {
    calls.add('decline:$emergencyId');
    _maybeFail('decline');
  }

  @override
  Future<StatusUpdateResult> updateStatus(
    String emergencyId,
    String status,
  ) async {
    calls.add('status:$status');
    _maybeFail('status', 'status:$status');
    final done = status == 'completed';
    return StatusUpdateResult(
      status: status,
      fare: done ? fare : null,
      completedAt: done ? DateTime.now() : null,
    );
  }

  @override
  Future<void> updateChecklist(
    String emergencyId, {
    bool? patientAssessed,
    bool? firstAidGiven,
    bool? patientLoaded,
  }) async {
    calls.add(
      'checklist:${patientAssessed ?? '-'}/${firstAidGiven ?? '-'}/${patientLoaded ?? '-'}',
    );
    _maybeFail('checklist');
  }

  @override
  Future<List<Trip>> fetchTrips({String? status, int limit = 100}) async {
    calls.add('trips:${status ?? 'all'}');
    _maybeFail('trips');
    return List.of(trips);
  }

  @override
  Future<Trip?> fetchActiveTrip() async {
    calls.add('active');
    _maybeFail('active');
    return active;
  }
}

class FakePatientRepository implements PatientRepository {
  final List<String> calls = [];
  Emergency? created;
  Emergency? current;
  List<Emergency> history = [];
  final Map<String, ApiException> failures = {};
  ({double lat, double lng})? lastCreate;

  void _maybeFail(String key) {
    final error = failures.remove(key);
    if (error != null) throw error;
  }

  @override
  Future<Emergency> createEmergency({
    required double latitude,
    required double longitude,
    String address = '',
    String incidentType = 'medical',
    String description = '',
    int patientCount = 1,
  }) async {
    calls.add('create');
    lastCreate = (lat: latitude, lng: longitude);
    _maybeFail('create');
    current = created ?? makeEmergency();
    return current!;
  }

  @override
  Future<Emergency> getEmergency(String id) async {
    calls.add('get:$id');
    _maybeFail('get');
    return current!;
  }

  @override
  Future<Emergency> cancel(String id, {String? reason}) async {
    calls.add('cancel:$id');
    _maybeFail('cancel');
    current = makeEmergency(id: id, status: EmergencyStatus.cancelled);
    return current!;
  }

  @override
  Future<List<Emergency>> myEmergencies({int limit = 50, int offset = 0}) async {
    calls.add('my');
    _maybeFail('my');
    return List.of(history);
  }
}

class FakeVerificationRepository implements DriverVerificationRepository {
  DriverVerificationInfo info = DriverVerificationInfo.notStarted;
  ApiException? failure;
  final List<List<VerificationUpload>> submissions = [];
  String? lastVehicle;
  String? lastLicense;

  @override
  Future<DriverVerificationInfo> fetch() async {
    final error = failure;
    if (error != null) throw error;
    return info;
  }

  @override
  Future<DriverVerificationInfo> submit({
    required String vehicleNumber,
    required String licenseNumber,
    required List<VerificationUpload> documents,
  }) async {
    final error = failure;
    if (error != null) throw error;
    lastVehicle = vehicleNumber;
    lastLicense = licenseNumber;
    submissions.add(documents);
    info = DriverVerificationInfo(
      status: info.status,
      submittedAt: DateTime.now(),
    );
    return info;
  }
}

class FakeAuthRepository extends AuthRepository {
  UserModel user = const UserModel(
    id: 'u1',
    name: 'Rahul',
    phone: '919000000001',
    role: UserRole.patient,
  );
  DriverProfile? driver;
  ApiException? loginFailure;
  ApiException? meFailure;
  ApiException? logoutFailure;
  final List<String> calls = [];

  @override
  Future<AuthSession> signUp({
    required String name,
    required String phone,
    required UserRole role,
  }) async {
    calls.add('signUp:$name:$phone:${role.name}');
    final error = loginFailure;
    if (error != null) throw error;
    return AuthSession(
      token: 'tok',
      user: UserModel(id: 'u1', name: name, phone: phone, role: role),
      driver: driver,
    );
  }

  @override
  Future<AuthSession> logIn({
    required String phone,
    required UserRole role,
  }) async {
    calls.add('logIn:$phone:${role.name}');
    final error = loginFailure;
    if (error != null) throw error;
    return AuthSession(
      token: 'tok',
      user: UserModel(id: 'u1', name: user.name, phone: phone, role: role),
      driver: driver,
    );
  }

  @override
  Future<MeResult> me() async {
    calls.add('me');
    final error = meFailure;
    if (error != null) throw error;
    return MeResult(user: user, driver: driver);
  }

  @override
  Future<void> logout() async {
    calls.add('logout');
    final error = logoutFailure;
    if (error != null) throw error;
  }
}

class FakeAuthFlow implements AuthFlow {
  FakeAuthFlow({this.route = '/next', this.failure});

  final String route;
  final ApiException? failure;
  final List<({UserRole role, String phone, String? name, bool signUp})> calls =
      [];

  @override
  Future<String> authenticate({
    required UserRole role,
    required String phone,
    String? name,
    required bool signUp,
  }) async {
    calls.add((role: role, phone: phone, name: name, signUp: signUp));
    if (failure != null) throw failure!;
    return route;
  }
}
