import 'package:flutter_test/flutter_test.dart';
import 'package:medirapid/features/auth/models/driver_verification_info.dart';
import 'package:medirapid/features/auth/models/driver_verification_status.dart';
import 'package:medirapid/features/driver/models/trip_model.dart';
import 'package:medirapid/features/patient/models/emergency_model.dart';

void main() {
  group('Trip.statusFromBackend', () {
    test('maps every backend status', () {
      expect(Trip.statusFromBackend('requested'), TripStatus.requested);
      for (final s in ['accepted', 'arrived', 'patient_loaded', 'en_route']) {
        expect(Trip.statusFromBackend(s), TripStatus.inProgress, reason: s);
      }
      expect(Trip.statusFromBackend('completed'), TripStatus.completed);
      expect(Trip.statusFromBackend('cancelled'), TripStatus.cancelled);
    });
  });

  group('Trip.prettyIncident', () {
    test('formats incident types', () {
      expect(Trip.prettyIncident('medical'), 'Medical Emergency');
      expect(Trip.prettyIncident(''), 'Medical Emergency');
      expect(Trip.prettyIncident('road_accident'), 'Road Accident');
      expect(Trip.prettyIncident('CARDIAC arrest'), 'Cardiac Arrest');
    });
  });

  group('Trip.fromEmergencyJson', () {
    final json = {
      'id': 'e1',
      'status': 'arrived',
      'latitude': 23.5204,
      'longitude': 87.3119,
      'address': 'Benachity, Durgapur',
      'incident_type': 'medical',
      'patient_count': 3,
      'checklist': {
        'patient_assessed': true,
        'first_aid_given': false,
        'patient_loaded': false,
      },
      'fare': 250,
      'patient': {'name': 'Rahul', 'phone': '919000000001'},
      'created_at': '2026-11-01T10:00:00Z',
      'accepted_at': '2026-11-01T10:02:00Z',
      'completed_at': null,
    };

    test('parses all fields', () {
      final trip = Trip.fromEmergencyJson(json);
      expect(trip.id, 'e1');
      expect(trip.backendStatus, 'arrived');
      expect(trip.status, TripStatus.inProgress);
      expect(trip.pickup, 'Benachity, Durgapur');
      expect(trip.patientName, 'Rahul');
      expect(trip.patientPhone, '919000000001');
      expect(trip.patientCount, 3);
      expect(trip.fare, 250.0);
      expect(trip.patientAssessed, isTrue);
      expect(trip.firstAidGiven, isFalse);
      expect(trip.acceptedAt, isNotNull);
      expect(trip.completedAt, isNull);
      expect(trip.destination, Trip.defaultDestination);
    });

    test('falls back to coordinates when the address is blank', () {
      final trip = Trip.fromEmergencyJson({...json, 'address': '  '});
      expect(trip.pickup, '23.52040, 87.31190');
    });

    test('unknown distance shows a dash', () {
      expect(Trip.fromEmergencyJson(json).distanceLabel, '—');
      expect(Trip.fromEmergencyJson(json, distanceKm: 4.26).distanceLabel, '4.3 km');
    });

    test('tolerates a missing patient and checklist', () {
      final trip = Trip.fromEmergencyJson({
        'id': 'x',
        'status': 'requested',
        'latitude': 1,
        'longitude': 2,
      });
      expect(trip.patientName, 'Patient');
      expect(trip.patientAssessed, isFalse);
    });
  });

  test('copyWith keeps unrelated fields', () {
    final trip = Trip.fromEmergencyJson({
      'id': 'e1',
      'status': 'accepted',
      'latitude': 1,
      'longitude': 2,
      'patient': {'name': 'Rahul', 'phone': '9'},
    });
    final next = trip.copyWith(backendStatus: 'arrived', fare: 250);
    expect(next.id, 'e1');
    expect(next.patientName, 'Rahul');
    expect(next.backendStatus, 'arrived');
    expect(next.fare, 250);
  });

  group('DriverVerificationInfo.fromJson', () {
    test('"pending" without a submission means not started', () {
      final info = DriverVerificationInfo.fromJson({
        'verification_status': 'pending',
        'reason': null,
        'submitted_at': null,
      });
      expect(info.status, DriverVerificationStatus.notStarted);
    });

    test('pending after submission', () {
      final info = DriverVerificationInfo.fromJson({
        'verification_status': 'pending',
        'submitted_at': '2026-11-01T10:00:00Z',
      });
      expect(info.status, DriverVerificationStatus.pending);
      expect(info.submittedAt, isNotNull);
    });

    test('approved and rejected (with reason)', () {
      expect(
        DriverVerificationInfo.fromJson({'verification_status': 'approved'}).status,
        DriverVerificationStatus.approved,
      );
      final rejected = DriverVerificationInfo.fromJson({
        'verification_status': 'rejected',
        'reason': 'Licence photo is blurry',
      });
      expect(rejected.status, DriverVerificationStatus.rejected);
      expect(rejected.reason, 'Licence photo is blurry');
    });
  });

  group('EmergencyStatus', () {
    test('parses backend values', () {
      expect(EmergencyStatus.parse('patient_loaded'), EmergencyStatus.patientLoaded);
      expect(EmergencyStatus.parse('en_route'), EmergencyStatus.enRoute);
      expect(EmergencyStatus.parse('cancelled'), EmergencyStatus.cancelled);
      expect(EmergencyStatus.parse('nonsense'), EmergencyStatus.requested);
    });

    test('terminal states and progress', () {
      expect(EmergencyStatus.completed.isTerminal, isTrue);
      expect(EmergencyStatus.cancelled.isTerminal, isTrue);
      expect(EmergencyStatus.enRoute.isTerminal, isFalse);
      expect(
        [for (final s in EmergencyStatus.values) s.progress],
        [0, 1, 2, 2, 3, 4, 0],
      );
    });
  });

  test('Emergency.fromJson parses a completed trip with driver and fare', () {
    final e = Emergency.fromJson({
      'id': 'e1',
      'status': 'completed',
      'latitude': 23.5,
      'longitude': 87.3,
      'created_at': '2026-11-01T10:00:00Z',
      'fare': 250,
      'driver': {'name': 'Asha', 'phone': '9', 'vehicle_number': 'WB01AB1234'},
    });
    expect(e.isTerminal, isTrue);
    expect(e.fare, 250.0);
    expect(e.driver!.name, 'Asha');
  });
}
