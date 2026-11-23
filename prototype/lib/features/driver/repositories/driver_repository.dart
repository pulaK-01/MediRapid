import 'package:medirapid/core/network/api_client.dart';
import 'package:medirapid/features/driver/models/trip_model.dart';

class StatusUpdateResult {
  const StatusUpdateResult({required this.status, this.fare, this.completedAt});

  final String status;
  final double? fare;
  final DateTime? completedAt;
}

/// Everything the driver app does against the backend.
abstract class DriverRepository {
  Future<void> setAvailability(bool online);

  /// Open emergencies this driver may accept (oldest first).
  Future<List<Trip>> fetchRequests({double? lat, double? lng});

  Future<void> accept(String emergencyId);

  Future<void> decline(String emergencyId, {String? reason});

  /// [status] is one of arrived, patient_loaded, en_route, completed.
  Future<StatusUpdateResult> updateStatus(String emergencyId, String status);

  Future<void> updateChecklist(
    String emergencyId, {
    bool? patientAssessed,
    bool? firstAidGiven,
    bool? patientLoaded,
  });

  /// All of this driver's trips, newest first. [status] may be `active`.
  Future<List<Trip>> fetchTrips({String? status, int limit = 100});

  Future<Trip?> fetchActiveTrip();
}

class ApiDriverRepository implements DriverRepository {
  ApiDriverRepository({ApiClient? api}) : _injected = api;

  final ApiClient? _injected;
  ApiClient get _api => _injected ?? ApiClient.instance;

  @override
  Future<void> setAvailability(bool online) async {
    await _api.patch('/drivers/me/availability', body: {'is_available': online});
  }

  @override
  Future<List<Trip>> fetchRequests({double? lat, double? lng}) async {
    final json = await _api.get(
      '/driver/emergencies',
      query: {'lat': lat, 'lng': lng},
    );
    return _items(json).map(Trip.fromDispatchJson).toList();
  }

  @override
  Future<void> accept(String emergencyId) async {
    await _api.post('/driver/emergencies/$emergencyId/accept');
  }

  @override
  Future<void> decline(String emergencyId, {String? reason}) async {
    await _api.post(
      '/driver/emergencies/$emergencyId/decline',
      body: {if (reason != null && reason.isNotEmpty) 'reason': reason},
    );
  }

  @override
  Future<StatusUpdateResult> updateStatus(
    String emergencyId,
    String status,
  ) async {
    final json = await _api.patch(
      '/driver/emergencies/$emergencyId/status',
      body: {'status': status},
    );
    final fare = json['fare'];
    final completedAt = json['completed_at'];
    return StatusUpdateResult(
      status: json['status'] as String? ?? status,
      fare: fare is num ? fare.toDouble() : null,
      completedAt: completedAt is String
          ? DateTime.tryParse(completedAt)?.toLocal()
          : null,
    );
  }

  @override
  Future<void> updateChecklist(
    String emergencyId, {
    bool? patientAssessed,
    bool? firstAidGiven,
    bool? patientLoaded,
  }) async {
    await _api.patch(
      '/driver/emergencies/$emergencyId/checklist',
      body: {
        if (patientAssessed != null) 'patient_assessed': patientAssessed,
        if (firstAidGiven != null) 'first_aid_given': firstAidGiven,
        if (patientLoaded != null) 'patient_loaded': patientLoaded,
      },
    );
  }

  @override
  Future<List<Trip>> fetchTrips({String? status, int limit = 100}) async {
    final json = await _api.get(
      '/driver/trips',
      query: {'status': status, 'limit': limit},
    );
    return _items(json).map((item) => Trip.fromEmergencyJson(item)).toList();
  }

  @override
  Future<Trip?> fetchActiveTrip() async {
    final trips = await fetchTrips(status: 'active', limit: 1);
    return trips.isEmpty ? null : trips.first;
  }

  List<Map<String, dynamic>> _items(Map<String, dynamic> json) {
    final items = json['items'];
    if (items is! List) return const [];
    return items.whereType<Map<String, dynamic>>().toList();
  }
}
