import 'package:flutter_test/flutter_test.dart';
import 'package:medirapid/core/network/api_client.dart';
import 'package:medirapid/core/services/app_state_service.dart';
import 'package:medirapid/core/services/session_service.dart';
import 'package:medirapid/models/user_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const user = UserModel(id: 'u1', name: 'Asha', phone: '919000000002', role: UserRole.driver);

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => ApiClient.instance.token = null);

  test('a saved session survives an app restart', () async {
    await SessionService().save(token: 'tok', user: user);

    final restarted = SessionService();
    await restarted.load();

    expect(restarted.isLoggedIn, isTrue);
    expect(restarted.token, 'tok');
    expect(restarted.user!.name, 'Asha');
    expect(restarted.user!.role, UserRole.driver);
    expect(ApiClient.instance.token, 'tok');
    expect(AppStateService.currentRole, 'driver');
  });

  test('clear removes everything', () async {
    final session = SessionService();
    await session.save(token: 'tok', user: user);
    await session.clear();

    final restarted = SessionService();
    await restarted.load();
    expect(restarted.isLoggedIn, isFalse);
    expect(ApiClient.instance.token, isNull);
  });

  test('clear forgets the token immediately (before any await completes)', () async {
    final session = SessionService();
    await session.save(token: 'tok', user: user);

    final pending = session.clear();
    expect(session.isLoggedIn, isFalse);
    expect(ApiClient.instance.token, isNull);
    await pending;
  });

  test('corrupt stored data is treated as logged out', () async {
    SharedPreferences.setMockInitialValues({
      'session_token': 'tok',
      'session_user': '{not json',
    });
    final session = SessionService();
    await session.load();
    expect(session.isLoggedIn, isFalse);
  });

  test('an unknown role is treated as logged out', () async {
    SharedPreferences.setMockInitialValues({
      'session_token': 'tok',
      'session_user': '{"id":"1","name":"X","phone":"1","role":"admin"}',
    });
    final session = SessionService();
    await session.load();
    expect(session.isLoggedIn, isFalse);
  });
}
