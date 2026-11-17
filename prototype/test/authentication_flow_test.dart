import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medirapid/features/auth/screens/phone_authentication.dart';
import 'package:medirapid/features/driver/screens/driver_settings_screen.dart';
import 'package:medirapid/models/user_model.dart';
import 'package:medirapid/features/patient/screens/patient_settings_screen.dart';

void main() {
  testWidgets('sign-up screen can switch to login and back', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PhoneAuthenticationScreen(role: UserRole.patient),
      ),
    );

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));

    await tester.tap(find.text('Already have an account? Log in'));
    await tester.pumpAndSettle();

    expect(find.text('Log in'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);

    await tester.tap(find.text('New here? Create an account'));
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
  });

  testWidgets('patient logout opens patient login screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PatientSettingsScreen()));

    await tester.tap(find.text('Log Out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();

    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Patient account'), findsOneWidget);
  });

  testWidgets('driver logout opens driver login screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DriverSettingsScreen()));

    await tester.tap(find.text('Log Out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();

    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Driver account'), findsOneWidget);
  });
}
