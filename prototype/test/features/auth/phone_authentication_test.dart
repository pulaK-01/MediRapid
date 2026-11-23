import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medirapid/features/auth/screens/phone_authentication.dart';
import 'package:medirapid/models/user_model.dart';

import '../../helpers/fakes.dart';

Future<void> pump(
  WidgetTester tester, {
  required FakeAuthFlow auth,
  UserRole role = UserRole.patient,
  AuthenticationMode mode = AuthenticationMode.signUp,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      routes: {'/next': (_) => const Scaffold(body: Text('NEXT SCREEN'))},
      home: PhoneAuthenticationScreen(role: role, initialMode: mode, auth: auth),
    ),
  );
}

Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sign-up: validates, shows the OTP step, then calls the backend', (tester) async {
    final auth = FakeAuthFlow();
    await pump(tester, auth: auth);

    // empty form is rejected
    await tapText(tester, 'Continue');
    expect(find.text('Please enter your name'), findsOneWidget);
    expect(find.text('Enter a valid phone number with country code'), findsOneWidget);

    // too-short number is rejected
    await tester.enterText(find.byType(TextFormField).at(0), 'Rahul Das');
    await tester.enterText(find.byType(TextFormField).at(1), '98765 43210');
    await tapText(tester, 'Continue');
    expect(find.text('Enter a valid phone number with country code'), findsOneWidget);

    // valid number (12 digits with country code, formatted with spaces/+)
    await tester.enterText(find.byType(TextFormField).at(1), '+91 98765 43210');
    await tapText(tester, 'Continue');
    expect(find.text('Verify your number'), findsOneWidget);

    // OTP must be 4 digits
    await tester.enterText(find.byType(TextFormField), '12');
    await tapText(tester, 'Create account');
    expect(find.text('Enter the 4-digit code'), findsOneWidget);
    expect(auth.calls, isEmpty, reason: 'nothing is sent until the code is complete');

    await tester.enterText(find.byType(TextFormField), '1234');
    await tapText(tester, 'Create account');

    expect(auth.calls, hasLength(1));
    final call = auth.calls.single;
    expect(call.role, UserRole.patient);
    expect(call.phone, '919876543210', reason: 'digits only, same as login');
    expect(call.name, 'Rahul Das');
    expect(call.signUp, isTrue);
    expect(find.text('NEXT SCREEN'), findsOneWidget);
  });

  testWidgets('login has no name field and sends no name', (tester) async {
    final auth = FakeAuthFlow();
    await pump(tester, auth: auth, role: UserRole.driver, mode: AuthenticationMode.login);

    expect(find.byType(TextFormField), findsOneWidget); // phone only
    await tester.enterText(find.byType(TextFormField), '919876543210');
    await tapText(tester, 'Continue');
    await tester.enterText(find.byType(TextFormField), '0000');
    await tapText(tester, 'Log in');

    final call = auth.calls.single;
    expect(call.role, UserRole.driver);
    expect(call.name, isNull);
    expect(call.signUp, isFalse);
  });

  testWidgets('a backend error is shown and the user stays on the screen', (tester) async {
    final auth = FakeAuthFlow(
      failure: apiError(404, 'ACCOUNT_NOT_FOUND', 'No account found for this phone number. Please sign up first.'),
    );
    await pump(tester, auth: auth, mode: AuthenticationMode.login);

    await tester.enterText(find.byType(TextFormField), '919876543210');
    await tapText(tester, 'Continue');
    await tester.enterText(find.byType(TextFormField), '1234');
    await tapText(tester, 'Log in');

    expect(find.textContaining('No account found'), findsOneWidget);
    expect(find.text('NEXT SCREEN'), findsNothing);
    // the button works again so the user can retry
    final button = find.byWidgetPredicate((w) => w is FilledButton);
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
  });

  testWidgets('"Change phone number" goes back to the first step', (tester) async {
    await pump(tester, auth: FakeAuthFlow(), mode: AuthenticationMode.login);
    await tester.enterText(find.byType(TextFormField), '919876543210');
    await tapText(tester, 'Continue');
    expect(find.text('Verify your number'), findsOneWidget);

    await tapText(tester, 'Change phone number');
    expect(find.text('Welcome Back'), findsOneWidget);
  });
}
