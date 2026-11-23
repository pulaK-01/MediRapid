import 'package:flutter/material.dart';
import 'package:medirapid/core/network/api_client.dart';
import 'package:medirapid/features/auth/models/driver_verification_info.dart';
import 'package:medirapid/features/auth/models/driver_verification_status.dart';
import 'package:medirapid/features/auth/repositories/driver_verification_repository.dart';

/// Driver verification state, backed by the server (the admin approves/rejects
/// there; this app only submits documents and reads the result).
class DriverVerificationProvider extends ChangeNotifier {
  DriverVerificationProvider({DriverVerificationRepository? repository})
    : _repository = repository ?? ApiDriverVerificationRepository();

  static final DriverVerificationProvider instance =
      DriverVerificationProvider();

  final DriverVerificationRepository _repository;

  DriverVerificationInfo _info = DriverVerificationInfo.notStarted;
  bool _loading = false;
  String? _error;

  DriverVerificationStatus get status => _info.status;
  String? get reason => _info.reason;
  DateTime? get submittedAt => _info.submittedAt;
  bool get isLoading => _loading;
  String? get error => _error;

  bool get isApproved => status == DriverVerificationStatus.approved;
  bool get isPending => status == DriverVerificationStatus.pending;
  bool get isRejected => status == DriverVerificationStatus.rejected;

  /// Reads the current status from the server. Returns false on failure
  /// (the previous status is kept and [error] explains why).
  Future<bool> refresh() async {
    _loading = true;
    notifyListeners();
    try {
      _info = await _repository.fetch();
      _error = null;
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Sends vehicle details and documents. On success the status becomes
  /// `pending` (or stays `approved` if the admin had already approved).
  Future<bool> submit({
    required String vehicleNumber,
    required String licenseNumber,
    required List<VerificationUpload> documents,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _info = await _repository.submit(
        vehicleNumber: vehicleNumber,
        licenseNumber: licenseNumber,
        documents: documents,
      );
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Forget everything (log out).
  void reset() {
    _info = DriverVerificationInfo.notStarted;
    _error = null;
    _loading = false;
    notifyListeners();
  }
}
