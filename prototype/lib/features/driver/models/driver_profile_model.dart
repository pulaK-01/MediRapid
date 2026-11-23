/// The `driver` object returned by /auth/demo, /auth/me and /drivers/profile.
class DriverProfile {
  const DriverProfile({
    required this.id,
    this.vehicleNumber = '',
    this.vehicleType = 'ambulance',
    this.licenseNumber = '',
    this.verificationStatus = 'pending',
    this.isAvailable = false,
  });

  final String id;
  final String vehicleNumber;
  final String vehicleType;
  final String licenseNumber;
  final String verificationStatus;
  final bool isAvailable;

  factory DriverProfile.fromJson(Map<String, dynamic> json) => DriverProfile(
    id: json['id'] as String? ?? '',
    vehicleNumber: json['vehicle_number'] as String? ?? '',
    vehicleType: json['vehicle_type'] as String? ?? 'ambulance',
    licenseNumber: json['license_number'] as String? ?? '',
    verificationStatus: json['verification_status'] as String? ?? 'pending',
    isAvailable: json['is_available'] as bool? ?? false,
  );
}
