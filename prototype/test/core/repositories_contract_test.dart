// Contract tests: the Flutter repositories must call the backend with exactly
// the paths, methods and JSON shapes defined in medirapid/internal/api.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medirapid/core/network/api_client.dart';
import 'package:medirapid/features/auth/models/driver_verification_status.dart';
import 'package:medirapid/features/auth/repositories/auth_repository.dart';
import 'package:medirapid/features/auth/repositories/driver_verification_repository.dart';
import 'package:medirapid/features/driver/repositories/driver_repository.dart';
import 'package:medirapid/features/patient/models/emergency_model.dart';
import 'package:medirapid/features/patient/repositories/patient_repository.dart';
import 'package:medirapid/models/user_model.dart';

class Recorder {
  final List<http.Request> requests = [];
  final List<http.Response> queue = [];

  ApiClient client({String? token = 'tok'}) => ApiClient(
    httpClient: MockClient((request) async {
      requests.add(request);
      return queue.isEmpty ? reply({}) : queue.removeAt(0);
    }),
    baseUrl: 'http://test/api/v1',
  )..token = token;

  void enqueue(Object body, [int status = 200]) => queue.add(reply(body, status));

  static http.Response reply(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json'});

  http.Request get last => requests.last;
  Map<String, dynamic> get lastBody =>
      jsonDecode(last.body) as Map<String, dynamic>;
}

Map<String, dynamic> emergencyJson({
  String id = 'e1',
  String status = 'accepted',
  Map<String, dynamic>? driver,
  int? fare,
}) => {
  'id': id,
  'patient_id': 'p1',
  'driver_id': driver == null ? null : 'd1',
  'status': status,
  'latitude': 23.5204,
  'longitude': 87.3119,
  'address': 'Durgapur',
  'incident_type': 'medical',
  'description': 'Chest pain',
  'patient_count': 1,
  'checklist': {
    'patient_assessed': false,
    'first_aid_given': false,
    'patient_loaded': false,
  },
  'fare': fare,
  'patient': {'name': 'Rahul', 'phone': '919000000001'},
  'driver': driver,
  'cancel_reason': null,
  'created_at': '2026-11-01T10:00:00Z',
  'updated_at': '2026-11-01T10:00:00Z',
  'accepted_at': null,
  'arrived_at': null,
  'en_route_at': null,
  'completed_at': null,
  'cancelled_at': null,
};

void main() {
  group('AuthRepository', () {
    test('signUp sends name, phone and role without a token', () async {
      final rec = Recorder()
        ..enqueue({
          'access_token': 'abc',
          'user': {'id': 'u1', 'name': 'Rahul', 'phone': '919000000001', 'role': 'patient'},
        });
      final session = await AuthRepository(api: rec.client()).signUp(
        name: 'Rahul',
        phone: '919000000001',
        role: UserRole.patient,
      );

      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/api/v1/auth/demo');
      expect(rec.lastBody, {
        'name': 'Rahul',
        'phone': '919000000001',
        'role': 'patient',
      });
      expect(rec.last.headers.containsKey('Authorization'), isFalse);
      expect(session.token, 'abc');
      expect(session.user.role, UserRole.patient);
      expect(session.driver, isNull);
    });

    test('logIn sends no name and parses the driver profile', () async {
      final rec = Recorder()
        ..enqueue({
          'access_token': 'abc',
          'user': {'id': 'u2', 'name': 'Asha', 'phone': '919000000002', 'role': 'driver'},
          'driver': {
            'id': 'd1',
            'user_id': 'u2',
            'vehicle_number': 'WB01AB1234',
            'vehicle_type': 'ambulance',
            'license_number': 'DL123',
            'verification_status': 'approved',
            'is_available': true,
          },
        });
      final session = await AuthRepository(api: rec.client()).logIn(
        phone: '919000000002',
        role: UserRole.driver,
      );

      expect(rec.lastBody, {'phone': '919000000002', 'role': 'driver'});
      expect(session.driver!.id, 'd1');
      expect(session.driver!.licenseNumber, 'DL123');
      expect(session.driver!.isAvailable, isTrue);
    });

    test('ACCOUNT_NOT_FOUND surfaces as an ApiException', () async {
      final rec = Recorder()
        ..enqueue({'error': {'code': 'ACCOUNT_NOT_FOUND', 'message': 'No account'}}, 404);
      expect(
        () => AuthRepository(api: rec.client()).logIn(phone: '1', role: UserRole.patient),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'ACCOUNT_NOT_FOUND')),
      );
    });

    test('me and logout use the token', () async {
      final rec = Recorder()
        ..enqueue({'user': {'id': 'u1', 'name': 'R', 'phone': '1', 'role': 'patient'}})
        ..enqueue({'message': 'Logged out'});
      final repo = AuthRepository(api: rec.client());
      await repo.me();
      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/api/v1/auth/me');
      expect(rec.last.headers['Authorization'], 'Bearer tok');
      await repo.logout();
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/api/v1/auth/logout');
    });
  });

  group('ApiDriverRepository', () {
    test('setAvailability -> PATCH /drivers/me/availability', () async {
      final rec = Recorder();
      await ApiDriverRepository(api: rec.client()).setAvailability(true);
      expect(rec.last.method, 'PATCH');
      expect(rec.last.url.path, '/api/v1/drivers/me/availability');
      expect(rec.lastBody, {'is_available': true});
    });

    test('fetchRequests passes lat/lng and parses dispatch items', () async {
      final rec = Recorder()
        ..enqueue({
          'items': [
            {
              'id': 'e1',
              'patient_name': 'Rahul',
              'patient_phone': '919000000001',
              'incident_type': 'medical',
              'patient_count': 2,
              'latitude': 23.5204,
              'longitude': 87.3119,
              'address': '',
              'destination': 'City General Hospital',
              'distance_km': 3.4,
              'status': 'requested',
              'created_at': '2026-11-01T10:00:00Z',
            },
          ],
          'total': 1,
        });
      final trips = await ApiDriverRepository(api: rec.client())
          .fetchRequests(lat: 23.5, lng: 87.3);

      expect(rec.last.method, 'GET');
      expect(rec.last.url.path, '/api/v1/driver/emergencies');
      expect(rec.last.url.queryParameters, {'lat': '23.5', 'lng': '87.3'});
      expect(trips, hasLength(1));
      expect(trips.single.id, 'e1');
      expect(trips.single.distanceKm, 3.4);
      expect(trips.single.patientCount, 2);
      expect(trips.single.incidentType, 'Medical Emergency');
      expect(trips.single.pickup, '23.52040, 87.31190'); // empty address -> coordinates
    });

    test('fetchRequests without GPS sends no query', () async {
      final rec = Recorder()..enqueue({'items': [], 'total': 0});
      await ApiDriverRepository(api: rec.client()).fetchRequests();
      expect(rec.last.url.hasQuery, isFalse);
    });

    test('accept / decline / status / checklist endpoints', () async {
      final rec = Recorder()
        ..enqueue({'status': 'accepted'})
        ..enqueue({'message': 'declined'})
        ..enqueue({'status': 'completed', 'fare': 250, 'completed_at': '2026-11-01T11:00:00Z'})
        ..enqueue({'patient_assessed': true, 'first_aid_given': false, 'patient_loaded': false});
      final repo = ApiDriverRepository(api: rec.client());

      await repo.accept('e1');
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/api/v1/driver/emergencies/e1/accept');

      await repo.decline('e1', reason: 'too far');
      expect(rec.last.url.path, '/api/v1/driver/emergencies/e1/decline');
      expect(rec.lastBody, {'reason': 'too far'});

      final result = await repo.updateStatus('e1', 'completed');
      expect(rec.last.method, 'PATCH');
      expect(rec.last.url.path, '/api/v1/driver/emergencies/e1/status');
      expect(rec.lastBody, {'status': 'completed'});
      expect(result.fare, 250);
      expect(result.completedAt, isNotNull);

      await repo.updateChecklist('e1', patientAssessed: true);
      expect(rec.last.url.path, '/api/v1/driver/emergencies/e1/checklist');
      expect(rec.lastBody, {'patient_assessed': true}, reason: 'only changed fields');
    });

    test('fetchActiveTrip asks for status=active and parses the trip', () async {
      final rec = Recorder()
        ..enqueue({'items': [emergencyJson(status: 'en_route', driver: {'name': 'A'})], 'total': 1});
      final trip = await ApiDriverRepository(api: rec.client()).fetchActiveTrip();
      expect(rec.last.url.path, '/api/v1/driver/trips');
      expect(rec.last.url.queryParameters['status'], 'active');
      expect(trip!.backendStatus, 'en_route');
    });

    test('fetchActiveTrip returns null when there is none', () async {
      final rec = Recorder()..enqueue({'items': [], 'total': 0});
      expect(await ApiDriverRepository(api: rec.client()).fetchActiveTrip(), isNull);
    });
  });

  group('ApiDriverVerificationRepository', () {
    test('submit saves profile, sends documents, then re-reads status', () async {
      final rec = Recorder()
        ..enqueue({'vehicle_number': 'WB01AB1234'})
        ..enqueue({'verification_status': 'pending', 'submitted_at': '2026-11-01T10:00:00Z'})
        ..enqueue({'verification_status': 'pending', 'reason': null, 'submitted_at': '2026-11-01T10:00:00Z'});
      final info = await ApiDriverVerificationRepository(api: rec.client()).submit(
        vehicleNumber: 'WB01AB1234',
        licenseNumber: 'WB0120200001234',
        documents: const [
          VerificationUpload(type: 'driving_licence', fileName: 'dl.jpg'),
          VerificationUpload(type: 'vehicle_registration', fileName: 'rc.pdf'),
        ],
      );

      expect(rec.requests.map((r) => '${r.method} ${r.url.path}').toList(), [
        'POST /api/v1/drivers/profile',
        'POST /api/v1/drivers/me/verification',
        'GET /api/v1/drivers/me/verification',
      ]);
      expect(jsonDecode(rec.requests[0].body), {
        'vehicle_number': 'WB01AB1234',
        'license_number': 'WB0120200001234',
        'vehicle_type': 'ambulance',
      });
      expect(jsonDecode(rec.requests[1].body), {
        'documents': [
          {'type': 'driving_licence', 'file_name': 'dl.jpg'},
          {'type': 'vehicle_registration', 'file_name': 'rc.pdf'},
        ],
      });
      expect(info.status, DriverVerificationStatus.pending);
    });
  });

  group('ApiPatientRepository', () {
    test('createEmergency posts the coordinates and parses the response', () async {
      final rec = Recorder()..enqueue(emergencyJson(status: 'requested'), 201);
      final e = await ApiPatientRepository(api: rec.client())
          .createEmergency(latitude: 23.5204, longitude: 87.3119);

      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/api/v1/emergencies');
      expect(rec.lastBody['latitude'], 23.5204);
      expect(rec.lastBody['longitude'], 87.3119);
      expect(rec.lastBody['incident_type'], 'medical');
      expect(e.status, EmergencyStatus.requested);
      expect(e.driver, isNull);
    });

    test('getEmergency parses driver details', () async {
      final rec = Recorder()
        ..enqueue(emergencyJson(status: 'accepted', driver: {
          'id': 'd1',
          'name': 'Asha',
          'phone': '919000000002',
          'vehicle_number': 'WB01AB1234',
        }));
      final e = await ApiPatientRepository(api: rec.client()).getEmergency('e1');
      expect(rec.last.url.path, '/api/v1/emergencies/e1');
      expect(e.status, EmergencyStatus.accepted);
      expect(e.driver!.vehicleNumber, 'WB01AB1234');
    });

    test('cancel and history endpoints', () async {
      final rec = Recorder()
        ..enqueue(emergencyJson(status: 'cancelled'))
        ..enqueue({'items': [emergencyJson()], 'total': 1});
      final repo = ApiPatientRepository(api: rec.client());

      final cancelled = await repo.cancel('e1', reason: 'false alarm');
      expect(rec.last.method, 'POST');
      expect(rec.last.url.path, '/api/v1/emergencies/e1/cancel');
      expect(rec.lastBody, {'reason': 'false alarm'});
      expect(cancelled.status, EmergencyStatus.cancelled);

      final history = await repo.myEmergencies(limit: 10);
      expect(rec.last.url.path, '/api/v1/emergencies/my');
      expect(rec.last.url.queryParameters['limit'], '10');
      expect(history, hasLength(1));
    });
  });
}
