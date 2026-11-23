enum EmergencyStatus {
  requested,
  accepted,
  arrived,
  patientLoaded,
  enRoute,
  completed,
  cancelled;

  static EmergencyStatus parse(String? value) => switch (value) {
    'accepted' => EmergencyStatus.accepted,
    'arrived' => EmergencyStatus.arrived,
    'patient_loaded' => EmergencyStatus.patientLoaded,
    'en_route' => EmergencyStatus.enRoute,
    'completed' => EmergencyStatus.completed,
    'cancelled' => EmergencyStatus.cancelled,
    _ => EmergencyStatus.requested,
  };

  bool get isTerminal =>
      this == EmergencyStatus.completed || this == EmergencyStatus.cancelled;

  String get title => switch (this) {
    EmergencyStatus.requested => 'Finding an ambulance…',
    EmergencyStatus.accepted => 'Ambulance is on the way',
    EmergencyStatus.arrived => 'Ambulance has arrived',
    EmergencyStatus.patientLoaded => 'Getting you ready for transport',
    EmergencyStatus.enRoute => 'On the way to the hospital',
    EmergencyStatus.completed => 'Trip completed',
    EmergencyStatus.cancelled => 'Request cancelled',
  };

  String get message => switch (this) {
    EmergencyStatus.requested =>
      'Your request was sent to nearby drivers. Stay where you are.',
    EmergencyStatus.accepted => 'A driver accepted your request and is heading to you.',
    EmergencyStatus.arrived => 'The crew is with you.',
    EmergencyStatus.patientLoaded => 'The crew is preparing to leave.',
    EmergencyStatus.enRoute => 'You are being taken to the hospital.',
    EmergencyStatus.completed => 'You have reached the hospital.',
    EmergencyStatus.cancelled => 'This request is no longer active.',
  };

  /// 0..4: how many progress steps are done (used by the tracker UI).
  int get progress => switch (this) {
    EmergencyStatus.requested => 0,
    EmergencyStatus.accepted => 1,
    EmergencyStatus.arrived || EmergencyStatus.patientLoaded => 2,
    EmergencyStatus.enRoute => 3,
    EmergencyStatus.completed => 4,
    EmergencyStatus.cancelled => 0,
  };
}

class EmergencyDriver {
  const EmergencyDriver({
    required this.name,
    required this.phone,
    required this.vehicleNumber,
  });

  final String name;
  final String phone;
  final String vehicleNumber;

  factory EmergencyDriver.fromJson(Map<String, dynamic> json) =>
      EmergencyDriver(
        name: json['name'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        vehicleNumber: json['vehicle_number'] as String? ?? '',
      );
}

/// A patient's emergency request (`/emergencies/...`).
class Emergency {
  const Emergency({
    required this.id,
    required this.status,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.address = '',
    this.incidentType = 'medical',
    this.description = '',
    this.patientCount = 1,
    this.driver,
    this.fare,
    this.cancelReason,
  });

  final String id;
  final EmergencyStatus status;
  final double latitude;
  final double longitude;
  final DateTime createdAt;
  final String address;
  final String incidentType;
  final String description;
  final int patientCount;
  final EmergencyDriver? driver;
  final double? fare;
  final String? cancelReason;

  bool get isTerminal => status.isTerminal;

  factory Emergency.fromJson(Map<String, dynamic> json) {
    final driver = json['driver'];
    final fare = json['fare'];
    return Emergency(
      id: json['id'] as String,
      status: EmergencyStatus.parse(json['status'] as String?),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      address: json['address'] as String? ?? '',
      incidentType: json['incident_type'] as String? ?? 'medical',
      description: json['description'] as String? ?? '',
      patientCount: (json['patient_count'] as num?)?.toInt() ?? 1,
      driver: driver is Map<String, dynamic>
          ? EmergencyDriver.fromJson(driver)
          : null,
      fare: fare is num ? fare.toDouble() : null,
      cancelReason: json['cancel_reason'] as String?,
    );
  }
}
