import 'package:medirapid/core/network/api_client.dart';
import 'package:medirapid/features/auth/models/driver_verification_info.dart';

class VerificationUpload {
  const VerificationUpload({required this.type, required this.fileName});

  /// DriverVerificationDocument.apiType
  final String type;
  final String fileName;
}

abstract class DriverVerificationRepository {
  Future<DriverVerificationInfo> fetch();

  /// Saves vehicle + licence details, then submits the document list.
  Future<DriverVerificationInfo> submit({
    required String vehicleNumber,
    required String licenseNumber,
    required List<VerificationUpload> documents,
  });
}

class ApiDriverVerificationRepository implements DriverVerificationRepository {
  ApiDriverVerificationRepository({ApiClient? api}) : _injected = api;

  final ApiClient? _injected;
  ApiClient get _api => _injected ?? ApiClient.instance;

  @override
  Future<DriverVerificationInfo> fetch() async {
    final json = await _api.get('/drivers/me/verification');
    return DriverVerificationInfo.fromJson(json);
  }

  @override
  Future<DriverVerificationInfo> submit({
    required String vehicleNumber,
    required String licenseNumber,
    required List<VerificationUpload> documents,
  }) async {
    await _api.post(
      '/drivers/profile',
      body: {
        'vehicle_number': vehicleNumber,
        'license_number': licenseNumber,
        'vehicle_type': 'ambulance',
      },
    );
    await _api.post(
      '/drivers/me/verification',
      body: {
        'documents': [
          for (final doc in documents)
            {'type': doc.type, 'file_name': doc.fileName},
        ],
      },
    );
    return fetch();
  }
}
