import 'package:medirapid/core/network/api_client.dart';
import 'package:medirapid/features/patient/models/emergency_model.dart';

abstract class PatientRepository {
  Future<Emergency> createEmergency({
    required double latitude,
    required double longitude,
    String address = '',
    String incidentType = 'medical',
    String description = '',
    int patientCount = 1,
  });

  Future<Emergency> getEmergency(String id);

  /// Only allowed while the emergency is still `requested`.
  Future<Emergency> cancel(String id, {String? reason});

  /// Newest first.
  Future<List<Emergency>> myEmergencies({int limit = 50, int offset = 0});
}

class ApiPatientRepository implements PatientRepository {
  ApiPatientRepository({ApiClient? api}) : _injected = api;

  final ApiClient? _injected;
  ApiClient get _api => _injected ?? ApiClient.instance;

  @override
  Future<Emergency> createEmergency({
    required double latitude,
    required double longitude,
    String address = '',
    String incidentType = 'medical',
    String description = '',
    int patientCount = 1,
  }) async {
    final json = await _api.post(
      '/emergencies',
      body: {
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'incident_type': incidentType,
        'description': description,
        'patient_count': patientCount,
      },
    );
    return Emergency.fromJson(json);
  }

  @override
  Future<Emergency> getEmergency(String id) async =>
      Emergency.fromJson(await _api.get('/emergencies/$id'));

  @override
  Future<Emergency> cancel(String id, {String? reason}) async =>
      Emergency.fromJson(
        await _api.post(
          '/emergencies/$id/cancel',
          body: {if (reason != null && reason.isNotEmpty) 'reason': reason},
        ),
      );

  @override
  Future<List<Emergency>> myEmergencies({int limit = 50, int offset = 0}) async {
    final json = await _api.get(
      '/emergencies/my',
      query: {'limit': limit, 'offset': offset},
    );
    final items = json['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(Emergency.fromJson)
        .toList();
  }
}
