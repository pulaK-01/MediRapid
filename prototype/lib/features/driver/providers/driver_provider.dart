import 'dart:async';

import 'package:flutter/material.dart';
import 'package:medirapid/core/network/api_client.dart';
import 'package:medirapid/features/driver/models/trip_flow_model.dart';
import 'package:medirapid/features/driver/models/trip_model.dart';
import 'package:medirapid/features/driver/repositories/driver_repository.dart';
import 'package:medirapid/services/location_service.dart';

typedef DriverLocation = ({double lat, double lng});
typedef DriverLocator = Future<DriverLocation?> Function();

/// Driver-side state: availability, incoming requests, the active trip and
/// trip history. All state changes go through the backend first; the UI only
/// moves forward once the server accepted the change.
///
/// Methods that talk to the server return `true` on success. On failure they
/// return `false` and leave a message for the UI in [takeError].
class DriverProvider extends ChangeNotifier {
  DriverProvider({
    DriverRepository? repository,
    DriverLocator? locator,
    this.pollInterval = const Duration(seconds: 5),
    this.requestWindow = const Duration(seconds: 60),
  }) : _repo = repository ?? ApiDriverRepository(),
       _locator = locator ?? _defaultLocator,
       _requestSecondsRemaining = requestWindow.inSeconds;

  static final DriverProvider instance = DriverProvider();

  final DriverRepository _repo;
  final DriverLocator _locator;

  /// How often open requests are re-fetched while online. `null` disables
  /// automatic polling (tests call [refreshRequests] themselves).
  final Duration? pollInterval;

  /// How long a driver has to accept a request before it is hidden locally.
  final Duration requestWindow;

  bool isOnline = false;

  bool _busy = false;
  bool _polling = false;
  bool _pollFailed = false;
  String? _error;

  final List<Trip> _incomingRequests = [];
  final Set<String> _dismissed = {};
  List<Trip> _trips = [];
  bool _loadingTrips = false;
  String? _tripsError;

  Trip? _activeTrip;
  TripStage? _tripStage;
  DateTime? _tripStartedAt;
  DateTime? _tripEndedAt;
  bool _patientAssessed = false;
  bool _firstAidGiven = false;
  bool _patientLoaded = false;
  bool _lastRequestExpired = false;

  Timer? _requestTimer;
  DateTime? _requestDeadline;
  String? _countdownRequestId;
  int _requestSecondsRemaining;

  Timer? _pollTimer;
  DriverLocation? _lastLocation;
  DateTime? _lastLocationAt;

  // ------------------------------------------------------------- getters

  List<Trip> get incomingRequests => List.unmodifiable(_incomingRequests);
  List<Trip> get trips => List.unmodifiable(_trips);
  List<Trip> get completedTrips =>
      List.unmodifiable(_trips.where((trip) => trip.isCompleted));
  bool get isLoadingTrips => _loadingTrips;
  String? get tripsError => _tripsError;

  Trip? get activeTrip => _activeTrip;
  TripStage? get tripStage => _tripStage;
  DateTime? get tripStartedAt => _tripStartedAt;
  DateTime? get tripEndedAt => _tripEndedAt;
  bool get patientAssessed => _patientAssessed;
  bool get firstAidGiven => _firstAidGiven;
  bool get patientLoaded => _patientLoaded;
  bool get lastRequestExpired => _lastRequestExpired;
  int get requestSecondsRemaining => _requestSecondsRemaining;

  /// True while a server call is in flight (disable buttons).
  bool get isBusy => _busy;

  bool get isChecklistComplete =>
      _patientAssessed && _firstAidGiven && _patientLoaded;
  bool get isOnTrip => _activeTrip != null && _tripStage != TripStage.completed;

  double get totalEarnings =>
      completedTrips.fold<double>(0.0, (sum, trip) => sum + (trip.fare ?? 0.0));

  /// Earnings from trips completed today (device local time).
  double get todayEarnings {
    final now = DateTime.now();
    return completedTrips
        .where((trip) {
          final done = trip.completedAt;
          return done != null &&
              done.year == now.year &&
              done.month == now.month &&
              done.day == now.day;
        })
        .fold<double>(0.0, (sum, trip) => sum + (trip.fare ?? 0.0));
  }

  /// Returns the pending error message once, then clears it.
  String? takeError() {
    final message = _error;
    _error = null;
    return message;
  }

  // ----------------------------------------------------------- availability

  Future<bool> toggleOnlineStatus() async {
    if (isOnTrip || _busy) return false;
    final goOnline = !isOnline;
    _busy = true;
    notifyListeners();
    try {
      await _repo.setAvailability(goOnline);
      isOnline = goOnline;
      if (goOnline) {
        _startPolling();
      } else {
        _stopPolling();
        _cancelRequestCountdown();
        _incomingRequests.clear();
        _lastRequestExpired = false;
      }
    } on ApiException catch (e) {
      _error = e.message;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
    if (goOnline) await refreshRequests();
    return true;
  }

  // ---------------------------------------------------------------- requests

  /// Fetches open emergencies. Safe to call repeatedly (it ignores overlapping
  /// calls). Called by the poll timer and by the "Refresh" button.
  Future<void> refreshRequests() async {
    if (!isOnline || isOnTrip || _polling) return;
    _polling = true;
    try {
      final where = await _currentLocation();
      final fetched = await _repo.fetchRequests(
        lat: where?.lat,
        lng: where?.lng,
      );
      if (!isOnline || isOnTrip) return; // state changed while we waited

      _pollFailed = false;
      final visible = fetched
          .where((trip) => !_dismissed.contains(trip.id))
          .toList();
      _incomingRequests
        ..clear()
        ..addAll(visible);

      final counting = _countdownRequestId;
      if (counting != null && !visible.any((trip) => trip.id == counting)) {
        _cancelRequestCountdown(); // taken by someone else / cancelled
      }
      if (visible.isNotEmpty) {
        _lastRequestExpired = false;
        startRequestCountdown(visible.first);
      }
      notifyListeners();
    } on ApiException catch (e) {
      // One message per failure streak, not one per poll.
      if (!_pollFailed) _error = e.message;
      _pollFailed = true;
      notifyListeners();
    } finally {
      _polling = false;
    }
  }

  void startRequestCountdown(Trip trip) {
    if (_countdownRequestId == trip.id) return;
    _requestTimer?.cancel();
    _countdownRequestId = trip.id;
    _requestDeadline = DateTime.now().add(requestWindow);
    _requestSecondsRemaining = requestWindow.inSeconds;
    _requestTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final deadline = _requestDeadline;
      if (deadline == null) {
        timer.cancel();
        return;
      }
      final remaining = deadline.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) {
        timer.cancel();
        expireRequest(trip);
        return;
      }
      _requestSecondsRemaining = remaining;
      notifyListeners();
    });
  }

  Future<bool> acceptRequest(Trip trip) async {
    if (!isOnline ||
        isOnTrip ||
        _busy ||
        !_incomingRequests.any((request) => request.id == trip.id)) {
      return false;
    }
    _busy = true;
    notifyListeners();
    try {
      await _repo.accept(trip.id);
      _cancelRequestCountdown();
      _incomingRequests.clear();
      _stopPolling();
      _activeTrip = trip.copyWith(
        status: TripStatus.inProgress,
        backendStatus: 'accepted',
        acceptedAt: DateTime.now(),
      );
      _tripStage = TripStage.navigatingToPickup;
      _tripStartedAt = DateTime.now();
      _tripEndedAt = null;
      _patientAssessed = false;
      _firstAidGiven = false;
      _patientLoaded = false;
      _lastRequestExpired = false;
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      if (e.code == 'EMERGENCY_ALREADY_ASSIGNED' ||
          e.code == 'EMERGENCY_NOT_AVAILABLE') {
        // Lost the race (or the patient cancelled): drop it from the list.
        _removeRequest(trip.id);
      }
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> declineRequest(Trip trip) async {
    if (!_incomingRequests.any((request) => request.id == trip.id)) {
      return false;
    }
    _removeRequest(trip.id);
    notifyListeners();
    try {
      await _repo.decline(trip.id);
      return true;
    } on ApiException catch (e) {
      // Already hidden locally; the server just didn't record the decline.
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  void expireRequest(Trip trip) {
    if (!_incomingRequests.any((request) => request.id == trip.id)) return;
    _removeRequest(trip.id);
    _lastRequestExpired = _incomingRequests.isEmpty;
    notifyListeners();
  }

  void _removeRequest(String id) {
    _dismissed.add(id);
    _incomingRequests.removeWhere((request) => request.id == id);
    if (_countdownRequestId == id) _cancelRequestCountdown();
    if (_incomingRequests.isNotEmpty) {
      startRequestCountdown(_incomingRequests.first);
    }
  }

  // -------------------------------------------------------------- trip flow

  Future<bool> markArrived() async {
    final trip = _activeTrip;
    if (trip == null || _tripStage != TripStage.navigatingToPickup || _busy) {
      return false;
    }
    return _guard(() async {
      await _repo.updateStatus(trip.id, 'arrived');
      _activeTrip = trip.copyWith(backendStatus: 'arrived');
      _tripStage = TripStage.arrived;
    });
  }

  /// Local only: the backend has no "assessment started" state.
  void beginAssessment() {
    if (_tripStage == TripStage.arrived) _setStage(TripStage.active);
  }

  Future<bool> setPatientAssessed(bool value) =>
      _setChecklist(assessed: value);

  Future<bool> setFirstAidGiven(bool value) => _setChecklist(firstAid: value);

  Future<bool> setPatientLoaded(bool value) => _setChecklist(loaded: value);

  Future<bool> _setChecklist({
    bool? assessed,
    bool? firstAid,
    bool? loaded,
  }) async {
    final trip = _activeTrip;
    if (trip == null || _tripStage != TripStage.active) return false;

    final before = (_patientAssessed, _firstAidGiven, _patientLoaded);
    if (assessed != null) _patientAssessed = assessed;
    if (firstAid != null) _firstAidGiven = firstAid;
    if (loaded != null) _patientLoaded = loaded;
    notifyListeners(); // optimistic: the checkbox flips immediately

    try {
      await _repo.updateChecklist(
        trip.id,
        patientAssessed: assessed,
        firstAidGiven: firstAid,
        patientLoaded: loaded,
      );
      return true;
    } on ApiException catch (e) {
      _patientAssessed = before.$1;
      _firstAidGiven = before.$2;
      _patientLoaded = before.$3;

      _error = await _recoverFromTripError(e);
      notifyListeners();
      return false;
    }
  }

  /// Checklist done -> loads the patient (server state `patient_loaded`) and
  /// starts the drive to the hospital (`en_route`).
  Future<bool> navigateToDestination() async {
    final trip = _activeTrip;
    if (trip == null ||
        _tripStage != TripStage.active ||
        !isChecklistComplete ||
        _busy) {
      return false;
    }
    return _guard(() async {
      var current = trip;
      if (current.backendStatus != 'patient_loaded') {
        await _repo.updateStatus(current.id, 'patient_loaded');
        current = current.copyWith(backendStatus: 'patient_loaded');
        _activeTrip = current; // remembered even if the next call fails
      }
      await _repo.updateStatus(current.id, 'en_route');
      _activeTrip = current.copyWith(backendStatus: 'en_route');
      _tripStage = TripStage.navigatingToDestination;
    });
  }

  Future<bool> completeTrip() async {
    final trip = _activeTrip;
    if (trip == null ||
        _tripStage != TripStage.navigatingToDestination ||
        _busy) {
      return false;
    }
    return _guard(() async {
      final result = await _repo.updateStatus(trip.id, 'completed');
      final endedAt = result.completedAt ?? DateTime.now();
      final done = trip.copyWith(
        status: TripStatus.completed,
        backendStatus: 'completed',
        completedAt: endedAt,
        fare: result.fare ?? trip.fare,
      );
      _activeTrip = done;
      _tripEndedAt = endedAt;
      _trips = [done, ..._trips.where((t) => t.id != done.id)];
      _tripStage = TripStage.completed;
    });
  }

  void clearCompletedTrip() {
    _activeTrip = null;
    _tripStage = null;
    _tripStartedAt = null;
    _tripEndedAt = null;
    notifyListeners();
    // The server marked this driver available again when the trip completed.
    if (isOnline) {
      _startPolling();
      unawaited(refreshRequests());
    }
  }

  // --------------------------------------------------------------- history

  Future<void> refreshTrips() async {
    _loadingTrips = true;
    notifyListeners();
    try {
      _trips = await _repo.fetchTrips(limit: 200);
      _tripsError = null;
    } on ApiException catch (e) {
      _tripsError = e.message;
    } finally {
      _loadingTrips = false;
      notifyListeners();
    }
  }

  // -------------------------------------------------------- session control

  /// Call after login / app start for an approved driver: resumes an active
  /// trip if there is one, otherwise restores the online switch.
  Future<void> restore({required bool isAvailable}) async {
    _resetState();
    try {
      final active = await _repo.fetchActiveTrip();
      if (active != null) {
        _adoptActiveTrip(active);
        isOnline = true; // the server flips availability back on at completion
      } else {
        isOnline = isAvailable;
        if (isOnline) _startPolling();
      }
    } on ApiException catch (e) {
      isOnline = isAvailable;
      if (isOnline) _startPolling();
      _error = e.message;
    }
    notifyListeners();
    unawaited(refreshTrips());
    if (isOnline && !isOnTrip) unawaited(refreshRequests());
  }

  void resetSession() {
    _resetState();
    notifyListeners();
  }

  void _resetState() {
    _stopPolling();
    _cancelRequestCountdown();
    _incomingRequests.clear();
    _dismissed.clear();
    _trips = [];
    _tripsError = null;
    _loadingTrips = false;
    _activeTrip = null;
    _tripStage = null;
    _tripStartedAt = null;
    _tripEndedAt = null;
    _patientAssessed = false;
    _firstAidGiven = false;
    _patientLoaded = false;
    _lastRequestExpired = false;
    _pollFailed = false;
    _busy = false;
    _error = null;
    isOnline = false;
  }

  @override
  void dispose() {
    _stopPolling();
    _cancelRequestCountdown();
    super.dispose();
  }

  // ---------------------------------------------------------------- helpers

  void _adoptActiveTrip(Trip trip) {
    _cancelRequestCountdown();
    _incomingRequests.clear();
    _stopPolling();
    _activeTrip = trip;
    _patientAssessed = trip.patientAssessed;
    _firstAidGiven = trip.firstAidGiven;
    _patientLoaded =
        trip.patientLoaded ||
        trip.backendStatus == 'patient_loaded' ||
        trip.backendStatus == 'en_route';
    _tripStartedAt = trip.acceptedAt ?? DateTime.now();
    _tripEndedAt = null;
    _tripStage = switch (trip.backendStatus) {
      'arrived' =>
        (trip.patientAssessed || trip.firstAidGiven || trip.patientLoaded)
            ? TripStage.active
            : TripStage.arrived,
      'patient_loaded' => TripStage.active,
      'en_route' => TripStage.navigatingToDestination,
      _ => TripStage.navigatingToPickup,
    };
  }

  void _clearTrip() {
    _activeTrip = null;
    _tripStage = null;
    _tripStartedAt = null;
    _tripEndedAt = null;
    _patientAssessed = false;
    _firstAidGiven = false;
    _patientLoaded = false;
    if (isOnline) _startPolling();
  }

  /// Runs a trip step with the busy flag set; maps failures to [takeError].
  Future<bool> _guard(Future<void> Function() action) async {
    _busy = true;
    notifyListeners();
    try {
      await action();
      return true;
    } on ApiException catch (e) {
      _error = await _recoverFromTripError(e);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// If the server rejected a step because our picture of the trip is stale
  /// (e.g. an admin cancelled it), re-sync from the server.
  Future<String> _recoverFromTripError(ApiException e) async {
    const stale = {'INVALID_TRANSITION', 'NOT_FOUND', 'FORBIDDEN'};
    if (!stale.contains(e.code)) return e.message;
    try {
      final active = await _repo.fetchActiveTrip();
      if (active == null) {
        _clearTrip();
        return 'This trip is no longer active. It may have been cancelled.';
      }
      _adoptActiveTrip(active);
      return 'Trip refreshed from the server. Please try again.';
    } on ApiException {
      return e.message;
    }
  }

  void _setStage(TripStage stage) {
    _tripStage = stage;
    notifyListeners();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    final interval = pollInterval;
    if (interval == null) return;
    _pollTimer = Timer.periodic(interval, (_) => unawaited(refreshRequests()));
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _cancelRequestCountdown() {
    _requestTimer?.cancel();
    _requestTimer = null;
    _requestDeadline = null;
    _countdownRequestId = null;
  }

  /// GPS is only used for the "distance" shown on requests; it is refreshed at
  /// most once a minute, and a failure never blocks the list.
  Future<DriverLocation?> _currentLocation() async {
    final now = DateTime.now();
    final at = _lastLocationAt;
    if (at != null && now.difference(at) < const Duration(minutes: 1)) {
      return _lastLocation;
    }
    _lastLocationAt = now;
    final fresh = await _locator();
    if (fresh != null) _lastLocation = fresh;
    return _lastLocation;
  }

  static Future<DriverLocation?> _defaultLocator() async {
    try {
      final position = await LocationService().getCurrentLocation();
      return (lat: position.latitude, lng: position.longitude);
    } catch (_) {
      return null;
    }
  }
}
