import 'package:flutter/material.dart';

enum DriverVerificationDocument {
  drivingLicence(
    apiType: 'driving_licence',
    title: 'Driving licence',
    subtitle: 'A valid licence for ambulance driving',
    icon: Icons.badge_outlined,
  ),
  vehicleRegistration(
    apiType: 'vehicle_registration',
    title: 'Vehicle registration certificate',
    subtitle: 'Registration for the ambulance vehicle',
    icon: Icons.airport_shuttle_outlined,
  ),
  vehicleInsurance(
    apiType: 'vehicle_insurance',
    title: 'Vehicle insurance',
    subtitle: 'Current insurance document',
    icon: Icons.shield_outlined,
  ),
  ambulancePermit(
    apiType: 'ambulance_permit',
    title: 'Ambulance permit / fitness certificate',
    subtitle: 'Valid permit or fitness certification',
    icon: Icons.health_and_safety_outlined,
  );

  const DriverVerificationDocument({
    required this.apiType,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  /// Value sent to the backend as the document `type`.
  final String apiType;
  final String title;
  final String subtitle;
  final IconData icon;
}
