import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medirapid/features/auth/models/driver_verification_status.dart';
import 'package:medirapid/features/auth/providers/driver_verification_provider.dart';
import 'package:medirapid/features/driver/screens/driver_profile_screen.dart';

void main() {
  testWidgets('driver profile shows activity and updates verification status', (
    tester,
  ) async {
    final verification = DriverVerificationProvider.instance;
    await verification.resetVerification();

    await tester.pumpWidget(const MaterialApp(home: DriverProfileScreen()));

    expect(find.text('Driver account'), findsOneWidget);
    expect(find.text('Not submitted'), findsOneWidget);
    expect(find.text('Your activity'), findsOneWidget);
    expect(find.text('Completed trips'), findsOneWidget);
    expect(find.text('Session earnings'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Verification documents'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Verification documents'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await verification.submitForReview();
    expect(verification.status, DriverVerificationStatus.pending);
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('View review status'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('View review status'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await verification.resetVerification();
  });
}
