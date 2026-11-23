import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:medirapid/features/patient/models/emergency_model.dart';
import 'package:medirapid/features/patient/providers/patient_provider.dart';
import 'package:medirapid/services/location_service.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakePatientRepository repo;
  late PatientProvider patient;

  PatientProvider build({PatientLocator? locator}) => PatientProvider(
    repository: repo,
    locator:
        locator ??
        () async => const PatientFix(latitude: 23.5204, longitude: 87.3119, accuracy: 8),
    pollInterval: null,
  );

  setUp(() {
    repo = FakePatientRepository();
    patient = build();
  });

  tearDown(() => patient.dispose());

  group('sendSos', () {
    test('sends the GPS position and starts tracking', () async {
      expect(await patient.sendSos(), isTrue);

      expect(repo.lastCreate, (lat: 23.5204, lng: 87.3119));
      expect(patient.emergency!.status, EmergencyStatus.requested);
      expect(patient.hasActiveEmergency, isTrue);
      expect(patient.canCancel, isTrue);
      expect(patient.error, isNull);
      expect(patient.isSending, isFalse);
    });

    test('a second tap while a request is active does nothing', () async {
      await patient.sendSos();
      repo.calls.clear();

      expect(await patient.sendSos(), isFalse);
      expect(repo.calls, isEmpty);
    });

    test('location permission denied: no request is created', () async {
      patient = build(
        locator: () async =>
            throw const LocationServiceException(LocationFailure.permissionDenied),
      );

      expect(await patient.sendSos(), isFalse);

      expect(repo.calls, isEmpty);
      expect(patient.error, 'Allow location access to send emergency help');
      expect(patient.statusMessage, 'Location permission denied');
      expect(patient.emergency, isNull);
    });

    test('location services off / permanently denied have their own messages', () async {
      for (final entry in {
        LocationFailure.servicesDisabled: 'Location services are disabled',
        LocationFailure.permissionPermanentlyDenied:
            'Enable location access in your device settings',
      }.entries) {
        patient = build(locator: () async => throw LocationServiceException(entry.key));
        await patient.sendSos();
        expect(patient.error, entry.value);
      }
    });

    test('GPS timeout is reported', () async {
      patient = build(locator: () async => throw TimeoutException('no fix'));
      expect(await patient.sendSos(), isFalse);
      expect(patient.error, 'Could not get a GPS fix in time');
    });

    test('a server error leaves the SOS button usable', () async {
      repo.failures['create'] = networkError;

      expect(await patient.sendSos(), isFalse);

      expect(patient.error, networkError.message);
      expect(patient.emergency, isNull);
      expect(patient.isSending, isFalse);

      expect(await patient.sendSos(), isTrue, reason: 'retry works');
    });
  });

  group('tracking', () {
    test('refresh shows the assigned driver and later progress', () async {
      await patient.sendSos();

      repo.current = makeEmergency(
        status: EmergencyStatus.accepted,
        driver: const EmergencyDriver(
          name: 'Asha',
          phone: '919000000002',
          vehicleNumber: 'WB01AB1234',
        ),
      );
      await patient.refresh();

      expect(patient.emergency!.status, EmergencyStatus.accepted);
      expect(patient.emergency!.driver!.name, 'Asha');
      expect(patient.canCancel, isFalse, reason: 'cannot cancel once accepted');

      repo.current = makeEmergency(status: EmergencyStatus.enRoute);
      await patient.refresh();
      expect(patient.emergency!.status, EmergencyStatus.enRoute);
    });

    test('a finished trip stops being "active"', () async {
      await patient.sendSos();
      repo.current = makeEmergency(status: EmergencyStatus.completed);
      await patient.refresh();

      expect(patient.hasActiveEmergency, isFalse);
      repo.calls.clear();
      await patient.refresh(); // terminal: no more requests
      expect(repo.calls, isEmpty);
    });

    test('network loss shows "reconnecting" and recovers', () async {
      await patient.sendSos();

      repo.failures['get'] = networkError;
      await patient.refresh();
      expect(patient.connectionLost, isTrue);
      expect(patient.emergency, isNotNull, reason: 'the request is not forgotten');

      await patient.refresh();
      expect(patient.connectionLost, isFalse);
    });

    test('dismissFinished returns to the SOS screen', () async {
      await patient.sendSos();
      repo.current = makeEmergency(status: EmergencyStatus.completed);
      await patient.refresh();

      patient.dismissFinished();

      expect(patient.emergency, isNull);
      expect(patient.statusMessage, PatientProvider.idleMessage);
    });

    test('dismissFinished ignores a request that is still active', () async {
      await patient.sendSos();
      patient.dismissFinished();
      expect(patient.emergency, isNotNull);
    });
  });

  group('cancel', () {
    test('cancels while waiting for a driver', () async {
      await patient.sendSos();

      expect(await patient.cancel(reason: 'false alarm'), isTrue);

      expect(repo.calls, contains('cancel:e1'));
      expect(patient.emergency!.status, EmergencyStatus.cancelled);
      expect(patient.hasActiveEmergency, isFalse);
    });

    test('refused (driver just accepted) -> shows the error and re-syncs', () async {
      await patient.sendSos();
      repo.current = makeEmergency(status: EmergencyStatus.accepted);
      repo.failures['cancel'] = apiError(
        422,
        'INVALID_STATE',
        'This emergency can no longer be cancelled.',
      );

      expect(await patient.cancel(), isFalse);

      expect(patient.error, contains('can no longer be cancelled'));
      expect(patient.emergency!.status, EmergencyStatus.accepted);
    });

    test('is not offered after acceptance', () async {
      await patient.sendSos();
      repo.current = makeEmergency(status: EmergencyStatus.accepted);
      await patient.refresh();

      repo.calls.clear();
      expect(await patient.cancel(), isFalse);
      expect(repo.calls, isEmpty);
    });
  });

  group('restore / reset', () {
    test('resumes the newest unfinished request after an app restart', () async {
      repo.history = [
        makeEmergency(id: 'new', status: EmergencyStatus.accepted),
        makeEmergency(id: 'old', status: EmergencyStatus.completed),
      ];
      await patient.restore();
      expect(patient.emergency!.id, 'new');
    });

    test('nothing to resume when everything is finished', () async {
      repo.history = [makeEmergency(status: EmergencyStatus.completed)];
      await patient.restore();
      expect(patient.emergency, isNull);
    });

    test('a failed restore is not fatal', () async {
      repo.failures['my'] = networkError;
      await patient.restore();
      expect(patient.emergency, isNull);
    });

    test('reset (logout) clears the request', () async {
      await patient.sendSos();
      patient.reset();
      expect(patient.emergency, isNull);
      expect(patient.location, isNull);
    });
  });
}
