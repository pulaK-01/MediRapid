import 'package:flutter_test/flutter_test.dart';
import 'package:medirapid/features/driver/models/trip_flow_model.dart';
import 'package:medirapid/features/driver/models/trip_model.dart';
import 'package:medirapid/features/driver/providers/driver_provider.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeDriverRepository repo;
  late DriverProvider driver;

  setUp(() {
    repo = FakeDriverRepository();
    driver = DriverProvider(
      repository: repo,
      locator: () async => (lat: 23.52, lng: 87.31),
      pollInterval: null, // no background timer; tests poll by hand
    );
  });

  tearDown(() => driver.dispose());

  /// Online + one open request + accepted -> stage navigatingToPickup.
  Future<Trip> acceptedTrip() async {
    final trip = makeTrip();
    repo.requests = [trip];
    await driver.toggleOnlineStatus();
    expect(await driver.acceptRequest(driver.incomingRequests.first), isTrue);
    return trip;
  }

  /// Walks an accepted trip to the "active" checklist stage.
  Future<void> reachChecklist() async {
    await acceptedTrip();
    expect(await driver.markArrived(), isTrue);
    driver.beginAssessment();
    expect(driver.tripStage, TripStage.active);
  }

  group('going online', () {
    test('calls the API, then loads open requests', () async {
      repo.requests = [makeTrip(id: 'a'), makeTrip(id: 'b')];

      expect(await driver.toggleOnlineStatus(), isTrue);

      expect(driver.isOnline, isTrue);
      expect(repo.calls, ['availability:true', 'requests']);
      expect(driver.incomingRequests.map((t) => t.id), ['a', 'b']);
    });

    test('stays offline and explains why when the server refuses', () async {
      repo.failures['availability'] =
          apiError(403, 'DRIVER_NOT_APPROVED', 'Only approved drivers can go online.');

      expect(await driver.toggleOnlineStatus(), isFalse);

      expect(driver.isOnline, isFalse);
      expect(driver.takeError(), 'Only approved drivers can go online.');
      expect(driver.takeError(), isNull, reason: 'errors are shown once');
      expect(repo.calls, ['availability:true']);
    });

    test('going offline clears requests', () async {
      repo.requests = [makeTrip()];
      await driver.toggleOnlineStatus();
      await driver.toggleOnlineStatus();

      expect(driver.isOnline, isFalse);
      expect(driver.incomingRequests, isEmpty);
      expect(repo.calls.contains('availability:false'), isTrue);
    });

    test('refreshRequests does nothing while offline', () async {
      await driver.refreshRequests();
      expect(repo.calls, isEmpty);
    });
  });

  group('requests', () {
    test('a request taken by someone else disappears on the next poll', () async {
      repo.requests = [makeTrip(id: 'a'), makeTrip(id: 'b')];
      await driver.toggleOnlineStatus();

      repo.requests = [makeTrip(id: 'b')];
      await driver.refreshRequests();

      expect(driver.incomingRequests.map((t) => t.id), ['b']);
    });

    test('decline hides it, tells the server, and it stays hidden', () async {
      final trip = makeTrip(id: 'a');
      repo.requests = [trip];
      await driver.toggleOnlineStatus();

      expect(await driver.declineRequest(trip), isTrue);
      expect(repo.calls.contains('decline:a'), isTrue);
      expect(driver.incomingRequests, isEmpty);

      // the server may still list it for a moment; we must not re-show it
      await driver.refreshRequests();
      expect(driver.incomingRequests, isEmpty);
    });

    test('expiring a request hides it and flags "expired"', () async {
      final trip = makeTrip(id: 'a');
      repo.requests = [trip];
      await driver.toggleOnlineStatus();

      driver.expireRequest(trip);

      expect(driver.incomingRequests, isEmpty);
      expect(driver.lastRequestExpired, isTrue);
      await driver.refreshRequests();
      expect(driver.incomingRequests, isEmpty);
    });

    test('a poll failure reports once per failure streak', () async {
      repo.requests = [makeTrip()];
      await driver.toggleOnlineStatus();
      driver.takeError();

      repo.failures['requests'] = networkError;
      await driver.refreshRequests();
      expect(driver.takeError(), isNotNull);

      repo.failures['requests'] = networkError;
      await driver.refreshRequests();
      expect(driver.takeError(), isNull, reason: 'no snackbar spam every 5 s');

      await driver.refreshRequests(); // recovers
      repo.failures['requests'] = networkError;
      await driver.refreshRequests();
      expect(driver.takeError(), isNotNull, reason: 'a new streak reports again');
    });
  });

  group('accepting', () {
    test('success starts the trip', () async {
      final trip = await acceptedTrip();

      expect(repo.calls, contains('accept:${trip.id}'));
      expect(driver.isOnTrip, isTrue);
      expect(driver.tripStage, TripStage.navigatingToPickup);
      expect(driver.activeTrip!.backendStatus, 'accepted');
      expect(driver.incomingRequests, isEmpty);
    });

    test('losing the race (409) keeps the driver free and drops the request', () async {
      final trip = makeTrip();
      repo.requests = [trip];
      await driver.toggleOnlineStatus();
      repo.failures['accept'] = apiError(
        409,
        'EMERGENCY_ALREADY_ASSIGNED',
        'Another driver has already accepted this emergency.',
      );

      expect(await driver.acceptRequest(trip), isFalse);

      expect(driver.isOnTrip, isFalse);
      expect(driver.activeTrip, isNull);
      expect(driver.incomingRequests, isEmpty);
      expect(driver.takeError(), contains('Another driver'));
    });

    test('a request that is not in the list cannot be accepted', () async {
      await driver.toggleOnlineStatus();
      expect(await driver.acceptRequest(makeTrip(id: 'ghost')), isFalse);
      expect(repo.calls.any((c) => c.startsWith('accept')), isFalse);
    });

    test('cannot go offline during a trip', () async {
      await acceptedTrip();
      expect(await driver.toggleOnlineStatus(), isFalse);
      expect(driver.isOnline, isTrue);
    });
  });

  group('trip flow', () {
    test('full happy path hits the backend in the right order', () async {
      await reachChecklist();
      expect(await driver.setPatientAssessed(true), isTrue);
      expect(await driver.setFirstAidGiven(true), isTrue);
      expect(driver.isChecklistComplete, isFalse);
      expect(await driver.setPatientLoaded(true), isTrue);
      expect(driver.isChecklistComplete, isTrue);

      expect(await driver.navigateToDestination(), isTrue);
      expect(driver.tripStage, TripStage.navigatingToDestination);

      expect(await driver.completeTrip(), isTrue);
      expect(driver.tripStage, TripStage.completed);
      expect(driver.activeTrip!.fare, 250);
      expect(driver.activeTrip!.status, TripStatus.completed);
      expect(driver.trips.first.id, driver.activeTrip!.id);
      expect(driver.isOnTrip, isFalse);

      expect(repo.calls.where((c) => c.startsWith('status:')).toList(), [
        'status:arrived',
        'status:patient_loaded',
        'status:en_route',
        'status:completed',
      ]);
      expect(repo.calls.where((c) => c.startsWith('checklist:')).toList(), [
        'checklist:true/-/-',
        'checklist:-/true/-',
        'checklist:-/-/true',
      ]);
    });

    test('arriving is not allowed before accepting', () async {
      expect(await driver.markArrived(), isFalse);
      expect(repo.calls, isEmpty);
    });

    test('cannot leave for the hospital until the checklist is complete', () async {
      await reachChecklist();
      await driver.setPatientAssessed(true);

      expect(await driver.navigateToDestination(), isFalse);

      expect(driver.tripStage, TripStage.active);
      expect(repo.calls.contains('status:patient_loaded'), isFalse);
    });

    test('checklist ticks are ignored outside the assessment stage', () async {
      await acceptedTrip(); // still heading to pickup
      expect(await driver.setPatientAssessed(true), isFalse);
      expect(driver.patientAssessed, isFalse);
    });

    test('a failed checklist update reverts the checkbox', () async {
      await reachChecklist();
      repo.failures['checklist'] = networkError;

      expect(await driver.setFirstAidGiven(true), isFalse);

      expect(driver.firstAidGiven, isFalse);
      expect(driver.takeError(), isNotNull);
    });

    test('retrying after a failed en_route does not repeat patient_loaded', () async {
      await reachChecklist();
      await driver.setPatientAssessed(true);
      await driver.setFirstAidGiven(true);
      await driver.setPatientLoaded(true);
      repo.failures['status:en_route'] = networkError;

      expect(await driver.navigateToDestination(), isFalse);
      expect(driver.tripStage, TripStage.active);
      expect(driver.activeTrip!.backendStatus, 'patient_loaded');

      expect(await driver.navigateToDestination(), isTrue);
      expect(
        repo.calls.where((c) => c == 'status:patient_loaded').length,
        1,
        reason: 'the server would answer INVALID_TRANSITION the second time',
      );
    });

    test('if the trip was cancelled server-side, the driver is released', () async {
      await acceptedTrip();
      repo.failures['status'] = apiError(422, 'INVALID_TRANSITION', "Cannot move from 'cancelled'");
      repo.active = null; // nothing active on the server any more

      expect(await driver.markArrived(), isFalse);

      expect(driver.activeTrip, isNull);
      expect(driver.isOnTrip, isFalse);
      expect(driver.takeError(), contains('no longer active'));
    });

    test('a non-state error leaves the trip untouched', () async {
      await acceptedTrip();
      repo.failures['status'] = networkError;

      expect(await driver.markArrived(), isFalse);

      expect(driver.tripStage, TripStage.navigatingToPickup);
      expect(driver.isOnTrip, isTrue);
    });

    test('clearing a finished trip returns to idle and polls again', () async {
      await reachChecklist();
      await driver.setPatientAssessed(true);
      await driver.setFirstAidGiven(true);
      await driver.setPatientLoaded(true);
      await driver.navigateToDestination();
      await driver.completeTrip();
      repo.calls.clear();

      driver.clearCompletedTrip();
      await Future<void>.delayed(Duration.zero);

      expect(driver.activeTrip, isNull);
      expect(driver.tripStage, isNull);
      expect(driver.isOnline, isTrue);
      expect(repo.calls, contains('requests'));
    });
  });

  group('restore (app restart / login)', () {
    test('resumes an en-route trip', () async {
      repo.active = makeTrip(
        backendStatus: 'en_route',
        status: TripStatus.inProgress,
        patientAssessed: true,
        firstAidGiven: true,
        patientLoaded: true,
      );

      await driver.restore(isAvailable: false);

      expect(driver.isOnline, isTrue);
      expect(driver.tripStage, TripStage.navigatingToDestination);
      expect(driver.isChecklistComplete, isTrue);
    });

    test('maps each server status to the right screen', () async {
      final cases = <String, TripStage>{
        'accepted': TripStage.navigatingToPickup,
        'arrived': TripStage.arrived,
        'patient_loaded': TripStage.active,
        'en_route': TripStage.navigatingToDestination,
      };
      for (final entry in cases.entries) {
        repo.active = makeTrip(backendStatus: entry.key, status: TripStatus.inProgress);
        await driver.restore(isAvailable: false);
        expect(driver.tripStage, entry.value, reason: entry.key);
      }
    });

    test('"arrived" with some checklist progress reopens the checklist', () async {
      repo.active = makeTrip(
        backendStatus: 'arrived',
        status: TripStatus.inProgress,
        patientAssessed: true,
      );
      await driver.restore(isAvailable: false);
      expect(driver.tripStage, TripStage.active);
      expect(driver.patientAssessed, isTrue);
    });

    test('"patient_loaded" counts the patient as loaded', () async {
      repo.active = makeTrip(backendStatus: 'patient_loaded', status: TripStatus.inProgress);
      await driver.restore(isAvailable: false);
      expect(driver.patientLoaded, isTrue);
    });

    test('with no trip, restores the online switch from the server', () async {
      repo.requests = [makeTrip()];
      await driver.restore(isAvailable: true);
      await Future<void>.delayed(Duration.zero);

      expect(driver.isOnline, isTrue);
      expect(driver.isOnTrip, isFalse);
      expect(driver.incomingRequests, hasLength(1));
    });

    test('with no trip and availability false, stays offline', () async {
      await driver.restore(isAvailable: false);
      expect(driver.isOnline, isFalse);
    });
  });

  group('history and earnings', () {
    test('totals only completed trips, "today" only counts today', () async {
      final now = DateTime.now();
      repo.trips = [
        makeTrip(id: 'a', status: TripStatus.completed, backendStatus: 'completed', fare: 250, completedAt: now),
        makeTrip(id: 'b', status: TripStatus.completed, backendStatus: 'completed', fare: 250, completedAt: now.subtract(const Duration(days: 2))),
        makeTrip(id: 'c', status: TripStatus.cancelled, backendStatus: 'cancelled'),
      ];

      await driver.refreshTrips();

      expect(driver.trips, hasLength(3));
      expect(driver.completedTrips, hasLength(2));
      expect(driver.totalEarnings, 500);
      expect(driver.todayEarnings, 250);
    });

    test('a failed history load keeps an error for the screen', () async {
      repo.failures['trips'] = networkError;
      await driver.refreshTrips();
      expect(driver.tripsError, networkError.message);
      expect(driver.isLoadingTrips, isFalse);
    });
  });

  test('resetSession (logout) clears everything', () async {
    await acceptedTrip();
    driver.resetSession();

    expect(driver.isOnline, isFalse);
    expect(driver.activeTrip, isNull);
    expect(driver.incomingRequests, isEmpty);
    expect(driver.trips, isEmpty);
  });
}
