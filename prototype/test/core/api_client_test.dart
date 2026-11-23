import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medirapid/core/network/api_client.dart';

ApiClient clientFor(MockClient mock, {String? token}) =>
    ApiClient(httpClient: mock, baseUrl: 'http://test/api/v1')..token = token;

http.Response json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  test('sends bearer token, JSON body and drops null query values', () async {
    late http.Request seen;
    final client = clientFor(
      MockClient((request) async {
        seen = request;
        return json({'ok': true});
      }),
      token: 'abc',
    );

    final result = await client.get(
      '/driver/emergencies',
      query: {'lat': 23.5, 'lng': null, 'limit': 20},
    );

    expect(result, {'ok': true});
    expect(seen.method, 'GET');
    expect(seen.url.path, '/api/v1/driver/emergencies');
    expect(seen.url.queryParameters, {'lat': '23.5', 'limit': '20'});
    expect(seen.headers['Authorization'], 'Bearer abc');
    expect(seen.headers['Content-Type'], contains('application/json'));
  });

  test('POST encodes the body as JSON', () async {
    late http.Request seen;
    final client = clientFor(
      MockClient((request) async {
        seen = request;
        return json({'id': 'x'}, 201);
      }),
    );

    await client.post('/emergencies', body: {'latitude': 1.5, 'longitude': 2});

    expect(seen.method, 'POST');
    expect(jsonDecode(seen.body), {'latitude': 1.5, 'longitude': 2});
    expect(seen.headers.containsKey('Authorization'), isFalse);
  });

  test('auth: false never sends the token', () async {
    late http.Request seen;
    final client = clientFor(
      MockClient((request) async {
        seen = request;
        return json({});
      }),
      token: 'abc',
    );
    await client.post('/auth/demo', body: {'phone': '1'}, auth: false);
    expect(seen.headers.containsKey('Authorization'), isFalse);
  });

  test('maps the backend error envelope to ApiException', () async {
    final client = clientFor(
      MockClient(
        (_) async => json({
          'error': {
            'code': 'EMERGENCY_ALREADY_ASSIGNED',
            'message': 'Another driver has already accepted this emergency.',
          },
        }, 409),
      ),
    );

    expect(
      () => client.post('/driver/emergencies/1/accept'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 409)
            .having((e) => e.code, 'code', 'EMERGENCY_ALREADY_ASSIGNED')
            .having((e) => e.message, 'message', contains('Another driver')),
      ),
    );
  });

  test('a non-JSON error body still produces a usable exception', () async {
    final client = clientFor(
      MockClient((_) async => http.Response('<html>Bad gateway</html>', 502)),
    );
    expect(
      () => client.get('/health'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 502)
            .having((e) => e.code, 'code', 'HTTP_502'),
      ),
    );
  });

  test('401 with a token calls onUnauthorized; without a token it does not', () async {
    var calls = 0;
    final unauthorized = json({
      'error': {'code': 'UNAUTHORIZED', 'message': 'Invalid or expired token.'},
    }, 401);

    final withToken = clientFor(MockClient((_) async => unauthorized), token: 't')
      ..onUnauthorized = () => calls++;
    await expectLater(withToken.get('/auth/me'), throwsA(isA<ApiException>()));
    expect(calls, 1);

    final loginClient = clientFor(
      MockClient((_) async => unauthorized),
      token: 't',
    )..onUnauthorized = () => calls++;
    await expectLater(
      loginClient.post('/auth/demo', auth: false),
      throwsA(isA<ApiException>()),
    );
    expect(calls, 1, reason: 'a failed login must not log the user out');
  });

  test('transport failures become a network ApiException', () async {
    final client = clientFor(
      MockClient((_) async => throw http.ClientException('connection refused')),
    );
    expect(
      () => client.get('/health'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.isNetworkError, 'isNetworkError', isTrue)
            .having((e) => e.code, 'code', 'NETWORK'),
      ),
    );
  });

  test('decodes UTF-8 even when the server omits the charset', () async {
    final client = clientFor(
      MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(jsonEncode({'name': 'Nipa ₹250'})),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    final result = await client.get('/auth/me');
    expect(result['name'], 'Nipa ₹250');
  });
}
