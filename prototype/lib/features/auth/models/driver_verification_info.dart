import 'package:medirapid/features/auth/models/driver_verification_status.dart';

/// What `GET /drivers/me/verification` says.
class DriverVerificationInfo {
  const DriverVerificationInfo({
    required this.status,
    this.reason,
    this.submittedAt,
  });

  static const notStarted = DriverVerificationInfo(
    status: DriverVerificationStatus.notStarted,
  );

  final DriverVerificationStatus status;
  final String? reason;
  final DateTime? submittedAt;

  /// The backend creates every driver as `pending`, and only sets
  /// `submitted_at` once documents were sent. "pending" without a submission
  /// therefore means the driver has not started verification yet.
  factory DriverVerificationInfo.fromJson(Map<String, dynamic> json) {
    final raw = json['verification_status'] as String? ?? 'pending';
    final submitted = json['submitted_at'] is String
        ? DateTime.tryParse(json['submitted_at'] as String)?.toLocal()
        : null;
    final status = switch (raw) {
      'approved' => DriverVerificationStatus.approved,
      'rejected' => DriverVerificationStatus.rejected,
      _ =>
        submitted == null
            ? DriverVerificationStatus.notStarted
            : DriverVerificationStatus.pending,
    };
    final reason = json['reason'] as String?;
    return DriverVerificationInfo(
      status: status,
      reason: (reason == null || reason.trim().isEmpty) ? null : reason,
      submittedAt: submitted,
    );
  }
}
