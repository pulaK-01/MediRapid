import 'dart:async';

import 'package:flutter/material.dart';
import 'package:medirapid/core/network/api_client.dart';
import 'package:medirapid/features/patient/models/emergency_model.dart';
import 'package:medirapid/features/patient/repositories/patient_repository.dart';
import 'package:medirapid/services/location_service.dart';

class PatientFix {
  const PatientFix({
    required this.latitude,
    required this.longitude,
    this.accuracy = 0,
  });

  final double latitude;
  final double longitude;
  final double accuracy;
}

typedef PatientLocator = Future<PatientFix> Function();

/// Patient-side state: sending an SOS, tracking the request while a driver
/// is assigned, cancelling, and resuming after an app restart.
class PatientProvider extends ChangeNotifier {
  PatientProvider({
    PatientRepository? repository,
    PatientLocator? locator,
    this.pollInterval = const Duration(seconds: 4),
  }) : _repo = repository ?? ApiPatientRepository(),
       _locator = locator ?? _defaultLocator;

  static final PatientProvider instance = PatientProvider();

  static const idleMessage =
      'Press the button above and help will reach you shortly.';

  final PatientRepository _repo;
  final PatientLocator _locator;

  /// `null` disables automatic polling (tests call [refresh] themselves).
  final Duration? pollInterval;

  Emergency? _emergency;
  PatientFix? _location;
  bool _sending = false;
  bool _cancelling = false;
  bool _connectionLost = false;
  String _statusMessage = idleMessage;
  String? _error;
  Timer? _pollTimer;

  Emergency? get emergency => _emergency;
  PatientFix? get location => _location;
  bool get isSending => _sending;
  bool get isCancelling => _cancelling;
  bool get connectionLost => _connectionLost;
  String get statusMessage => _statusMessage;
  String? get error => _error;

  bool get hasActiveEmergency =>
      _emergency != null && !_emergency!.isTerminal;

  bool get canCancel => _emergency?.status == EmergencyStatus.requested;

  /// Gets a GPS fix and sends the SOS. Returns true when the request was
  /// created; on failure [error] / [statusMessage] explain why.
  Future<bool> sendSos({String description = ''}) async {
    if (_sending || hasActiveEmergency) return false;
    _sending = true;
    _error = null;
    _statusMessage = 'Getting your exact location...';
    notifyListeners();

    try {
      final PatientFix fix;
      try {
        fix = await _locator();
      } on LocationServiceException catch (e) {
        final (status, error) = describeLocationFailure(e.failure);
        _statusMessage = status;
        _error = error;
        return false;
      } on TimeoutException {
        _statusMessage = 'Move outdoors or near a window and try again';
        _error = 'Could not get a GPS fix in time';
        return false;
      } catch (e) {
        _statusMessage = 'Error getting location';
        _error = e.toString();
        return false;
      }

      _location = fix;
      try {
        _emergency = await _repo.createEmergency(
          latitude: fix.latitude,
          longitude: fix.longitude,
          description: description,
        );
        _statusMessage = 'Help is on the way!';
        _connectionLost = false;
        _startPolling();
        return true;
      } on ApiException catch (e) {
        _statusMessage = 'Could not send your request';
        _error = e.message;
        return false;
      }
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  /// Re-reads the current emergency from the server.
  Future<void> refresh() async {
    final current = _emergency;
    if (current == null || current.isTerminal) {
      _stopPolling();
      return;
    }
    try {
      final latest = await _repo.getEmergency(current.id);
      _emergency = latest;
      _connectionLost = false;
      if (latest.isTerminal) _stopPolling();
    } on ApiException catch (e) {
      // Transient problems show "reconnecting"; the poll keeps trying.
      if (e.isNetworkError) {
        _connectionLost = true;
      } else {
        _error = e.message;
      }
    }
    notifyListeners();
  }

  /// Cancels while still waiting for a driver. If a driver accepted in the
  /// meantime the server refuses, and we re-sync to show the new state.
  Future<bool> cancel({String? reason}) async {
    final current = _emergency;
    if (current == null || !canCancel || _cancelling) return false;
    _cancelling = true;
    _error = null;
    notifyListeners();
    try {
      _emergency = await _repo.cancel(current.id, reason: reason);
      _stopPolling();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      if (e.code == 'INVALID_STATE') await refresh();
      return false;
    } finally {
      _cancelling = false;
      notifyListeners();
    }
  }

  /// After a trip finished/cancelled, go back to the SOS screen.
  void dismissFinished() {
    if (_emergency?.isTerminal ?? false) {
      _emergency = null;
      _error = null;
      _statusMessage = idleMessage;
      notifyListeners();
    }
  }

  /// Picks up an in-progress request after login / app restart.
  Future<void> restore() async {
    try {
      final recent = await _repo.myEmergencies(limit: 10);
      final active = recent.where((e) => !e.isTerminal).toList();
      _emergency = active.isEmpty ? null : active.first;
      if (_emergency != null) {
        _statusMessage = 'Help is on the way!';
        _startPolling();
      }
    } on ApiException {
      // Not fatal: the SOS screen still works.
    }
    notifyListeners();
  }

  Future<List<Emergency>> loadHistory() => _repo.myEmergencies(limit: 50);

  void reset() {
    _stopPolling();
    _emergency = null;
    _location = null;
    _sending = false;
    _cancelling = false;
    _connectionLost = false;
    _error = null;
    _statusMessage = idleMessage;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    final interval = pollInterval;
    if (interval == null) return;
    _pollTimer = Timer.periodic(interval, (_) => unawaited(refresh()));
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  static (String status, String error) describeLocationFailure(
    LocationFailure failure,
  ) => switch (failure) {
    LocationFailure.servicesDisabled => (
      'Please enable location services',
      'Location services are disabled',
    ),
    LocationFailure.permissionDenied => (
      'Location permission denied',
      'Allow location access to send emergency help',
    ),
    LocationFailure.permissionPermanentlyDenied => (
      'Location permission permanently denied',
      'Enable location access in your device settings',
    ),
  };

  static Future<PatientFix> _defaultLocator() async {
    final position = await LocationService().getCurrentLocation();
    return PatientFix(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
    );
  }
}
