import 'package:flutter/material.dart';

enum TripStatus { requested, inProgress, completed, cancelled }

class Trip {
  /// The backend has no hospital routing yet; every dispatch uses this.
  static const String defaultDestination = 'City General Hospital';

  final String id;
  final String patientName;
  final String patientPhone;
  final double distanceKm;
  final DateTime requestedAt;
  final String pickup;
  final String destination;
  final TripStatus status;
  final DateTime? completedAt;
  final DateTime? acceptedAt;
  final double? fare;
  final String incidentType;
  final int patientCount;
  final bool isDemo;
  final double? latitude;
  final double? longitude;

  /// Raw backend status: requested, accepted, arrived, patient_loaded,
  /// en_route, completed, cancelled. [status] is the coarse UI version.
  final String backendStatus;
  final bool patientAssessed;
  final bool firstAidGiven;
  final bool patientLoaded;

  const Trip({
    required this.id,
    required this.patientName,
    required this.distanceKm,
    required this.requestedAt,
    required this.pickup,
    required this.destination,
    required this.status,
    this.completedAt,
    this.acceptedAt,
    this.fare,
    this.incidentType = 'Medical Emergency',
    this.patientCount = 1,
    this.isDemo = false,
    this.patientPhone = '',
    this.latitude,
    this.longitude,
    this.backendStatus = 'requested',
    this.patientAssessed = false,
    this.firstAidGiven = false,
    this.patientLoaded = false,
  });

  Trip copyWith({
    TripStatus? status,
    String? backendStatus,
    DateTime? completedAt,
    DateTime? acceptedAt,
    double? fare,
    double? distanceKm,
    bool? patientAssessed,
    bool? firstAidGiven,
    bool? patientLoaded,
  }) {
    return Trip(
      id: id,
      patientName: patientName,
      patientPhone: patientPhone,
      distanceKm: distanceKm ?? this.distanceKm,
      requestedAt: requestedAt,
      pickup: pickup,
      destination: destination,
      status: status ?? this.status,
      completedAt: completedAt ?? this.completedAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      fare: fare ?? this.fare,
      incidentType: incidentType,
      patientCount: patientCount,
      isDemo: isDemo,
      latitude: latitude,
      longitude: longitude,
      backendStatus: backendStatus ?? this.backendStatus,
      patientAssessed: patientAssessed ?? this.patientAssessed,
      firstAidGiven: firstAidGiven ?? this.firstAidGiven,
      patientLoaded: patientLoaded ?? this.patientLoaded,
    );
  }

  /// One item of `GET /driver/emergencies`.
  factory Trip.fromDispatchJson(Map<String, dynamic> json) {
    final lat = _toDouble(json['latitude']);
    final lng = _toDouble(json['longitude']);
    final destination = (json['destination'] as String?)?.trim() ?? '';
    return Trip(
      id: json['id'] as String,
      patientName: _nonEmpty(json['patient_name'] as String?, 'Patient'),
      patientPhone: json['patient_phone'] as String? ?? '',
      distanceKm: _toDouble(json['distance_km']) ?? 0,
      requestedAt: _toDate(json['created_at']) ?? DateTime.now(),
      pickup: _pickup(json['address'] as String?, lat, lng),
      destination: destination.isEmpty ? defaultDestination : destination,
      status: statusFromBackend(json['status'] as String? ?? 'requested'),
      backendStatus: json['status'] as String? ?? 'requested',
      incidentType: prettyIncident(json['incident_type'] as String? ?? ''),
      patientCount: (json['patient_count'] as num?)?.toInt() ?? 1,
      latitude: lat,
      longitude: lng,
    );
  }

  /// A full emergency object (`/driver/trips`, `/driver/trips/{id}`).
  factory Trip.fromEmergencyJson(
    Map<String, dynamic> json, {
    double distanceKm = 0,
  }) {
    final lat = _toDouble(json['latitude']);
    final lng = _toDouble(json['longitude']);
    final patient = json['patient'];
    final checklist = json['checklist'];
    final backendStatus = json['status'] as String? ?? 'requested';
    return Trip(
      id: json['id'] as String,
      patientName: patient is Map
          ? _nonEmpty(patient['name'] as String?, 'Patient')
          : 'Patient',
      patientPhone: patient is Map ? (patient['phone'] as String? ?? '') : '',
      distanceKm: distanceKm,
      requestedAt: _toDate(json['created_at']) ?? DateTime.now(),
      pickup: _pickup(json['address'] as String?, lat, lng),
      destination: defaultDestination,
      status: statusFromBackend(backendStatus),
      backendStatus: backendStatus,
      completedAt: _toDate(json['completed_at']),
      acceptedAt: _toDate(json['accepted_at']),
      fare: _toDouble(json['fare']),
      incidentType: prettyIncident(json['incident_type'] as String? ?? ''),
      patientCount: (json['patient_count'] as num?)?.toInt() ?? 1,
      latitude: lat,
      longitude: lng,
      patientAssessed: checklist is Map && checklist['patient_assessed'] == true,
      firstAidGiven: checklist is Map && checklist['first_aid_given'] == true,
      patientLoaded: checklist is Map && checklist['patient_loaded'] == true,
    );
  }

  static TripStatus statusFromBackend(String status) => switch (status) {
    'requested' => TripStatus.requested,
    'completed' => TripStatus.completed,
    'cancelled' => TripStatus.cancelled,
    _ => TripStatus.inProgress,
  };

  static String prettyIncident(String raw) {
    final text = raw.trim();
    if (text.isEmpty || text.toLowerCase() == 'medical') {
      return 'Medical Emergency';
    }
    return text
        .replaceAll('_', ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map((word) => '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
        .join(' ');
  }

  static String _pickup(String? address, double? lat, double? lng) {
    final text = address?.trim() ?? '';
    if (text.isNotEmpty) return text;
    if (lat != null && lng != null) {
      return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
    }
    return 'Unknown location';
  }

  static String _nonEmpty(String? value, String fallback) =>
      (value == null || value.trim().isEmpty) ? fallback : value;

  static double? _toDouble(Object? value) => value is num ? value.toDouble() : null;

  static DateTime? _toDate(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;

  bool get isCompleted => status == TripStatus.completed;

  /// The backend does not return route distance for trips, so 0 means unknown.
  String get distanceLabel =>
      distanceKm > 0 ? '${distanceKm.toStringAsFixed(1)} km' : '—';

  String get statusText {
    switch (status) {
      case TripStatus.requested:
        return 'Requested';
      case TripStatus.inProgress:
        return 'In Progress';
      case TripStatus.completed:
        return 'Completed';
      case TripStatus.cancelled:
        return 'Cancelled';
    }
  }

  Color get statusColor {
    switch (status) {
      case TripStatus.requested:
      case TripStatus.inProgress:
        return Colors.orange;
      case TripStatus.completed:
        return Colors.green;
      case TripStatus.cancelled:
        return Colors.red;
    }
  }

  Color get statusBackgroundColor {
    switch (status) {
      case TripStatus.requested:
      case TripStatus.inProgress:
        return Colors.orange.shade100;
      case TripStatus.completed:
        return Colors.green.shade100;
      case TripStatus.cancelled:
        return Colors.red.shade100;
    }
  }
}
