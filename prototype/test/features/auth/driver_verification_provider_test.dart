import 'package:flutter_test/flutter_test.dart';
import 'package:medirapid/features/auth/models/driver_verification_info.dart';
import 'package:medirapid/features/auth/models/driver_verification_status.dart';
import 'package:medirapid/features/auth/providers/driver_verification_provider.dart';
import 'package:medirapid/features/auth/repositories/driver_verification_repository.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeVerificationRepository repo;
  late DriverVerificationProvider provider;

  setUp(() {
    repo = FakeVerificationRepository();
    provider = DriverVerificationProvider(repository: repo);
  });

  test('starts as not started', () {
    expect(provider.status, DriverVerificationStatus.notStarted);
    expect(provider.isApproved, isFalse);
  });

  test('refresh reads the server status', () async {
    repo.info = const DriverVerificationInfo(status: DriverVerificationStatus.approved);

    expect(await provider.refresh(), isTrue);

    expect(provider.isApproved, isTrue);
    expect(provider.isLoading, isFalse);
    expect(provider.error, isNull);
  });

  test('refresh exposes the rejection reason', () async {
    repo.info = const DriverVerificationInfo(
      status: DriverVerificationStatus.rejected,
      reason: 'Licence photo is blurry',
    );
    await provider.refresh();

    expect(provider.isRejected, isTrue);
    expect(provider.reason, 'Licence photo is blurry');
  });

  test('a failed refresh keeps the last known status', () async {
    repo.info = const DriverVerificationInfo(status: DriverVerificationStatus.pending);
    await provider.refresh();

    repo.failure = networkError;
    expect(await provider.refresh(), isFalse);

    expect(provider.isPending, isTrue);
    expect(provider.error, networkError.message);
  });

  test('submit sends vehicle, licence and documents, then reports pending', () async {
    repo.info = const DriverVerificationInfo(status: DriverVerificationStatus.pending);

    final ok = await provider.submit(
      vehicleNumber: 'WB01AB1234',
      licenseNumber: 'WB0120200001234',
      documents: const [VerificationUpload(type: 'driving_licence', fileName: 'dl.jpg')],
    );

    expect(ok, isTrue);
    expect(repo.lastVehicle, 'WB01AB1234');
    expect(repo.lastLicense, 'WB0120200001234');
    expect(repo.submissions.single.single.type, 'driving_licence');
    expect(provider.isPending, isTrue);
  });

  test('a failed submit reports the error and keeps the status', () async {
    repo.failure = apiError(400, 'INVALID_REQUEST', 'At least one document is required.');

    final ok = await provider.submit(
      vehicleNumber: 'WB01AB1234',
      licenseNumber: 'X',
      documents: const [],
    );

    expect(ok, isFalse);
    expect(provider.error, 'At least one document is required.');
    expect(provider.status, DriverVerificationStatus.notStarted);
  });

  test('reset (logout) forgets the status', () async {
    repo.info = const DriverVerificationInfo(status: DriverVerificationStatus.approved);
    await provider.refresh();
    provider.reset();
    expect(provider.status, DriverVerificationStatus.notStarted);
  });

  test('notifies listeners while loading', () async {
    var notifications = 0;
    provider.addListener(() => notifications++);
    await provider.refresh();
    expect(notifications, greaterThanOrEqualTo(2)); // start + finish
  });
}
