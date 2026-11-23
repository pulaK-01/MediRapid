import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:medirapid/core/config/api_config.dart';

/// Any failed call: HTTP error from the backend (`{"error":{"code","message"}}`)
/// or a transport problem (statusCode 0).
class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  bool get isNetworkError => statusCode == 0;
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}

/// Thin JSON client for the MediRapid backend. Every backend response is a
/// JSON object, so every call returns `Map<String, dynamic>`.
class ApiClient {
  ApiClient({http.Client? httpClient, String? baseUrl, Duration? timeout})
    : _http = httpClient ?? http.Client(),
      baseUrl = baseUrl ?? ApiConfig.baseUrl,
      timeout = timeout ?? ApiConfig.timeout;

  /// App-wide client. Tests build their own instances instead.
  static ApiClient instance = ApiClient();

  final http.Client _http;
  final String baseUrl;
  final Duration timeout;

  /// Bearer token; set by SessionService.
  String? token;

  /// Called when an authenticated request comes back 401 (expired/invalid session).
  void Function()? onUnauthorized;

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, Object?>? query,
    bool auth = true,
  }) => _send('GET', path, query: query, auth: auth);

  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    bool auth = true,
  }) => _send('POST', path, body: body ?? const {}, auth: auth);

  Future<Map<String, dynamic>> patch(
    String path, {
    Object? body,
    bool auth = true,
  }) => _send('PATCH', path, body: body ?? const {}, auth: auth);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, Object?>? query,
    Object? body,
    bool auth = true,
  }) async {
    var uri = Uri.parse('$baseUrl$path');
    debugPrint('POST $uri body=$body');
    final params = <String, String>{
      for (final entry in query?.entries ?? const <MapEntry<String, Object?>>[])
        if (entry.value != null) entry.key: '${entry.value}',
    };
    if (params.isNotEmpty) uri = uri.replace(queryParameters: params);

    final request = http.Request(method, uri)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'application/json';
    final bearer = token;
    if (auth && bearer != null) {
      request.headers['Authorization'] = 'Bearer $bearer';
    }
    if (body != null) request.body = jsonEncode(body);

    final http.Response response;
    try {
      final streamed = await _http.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw const ApiException(
        statusCode: 0,
        code: 'TIMEOUT',
        message: 'The server took too long to respond. Please try again.',
      );
    } on SocketException {
      throw _offline();
    } on http.ClientException {
      throw _offline();
    }

    return _parse(response, hadToken: auth && bearer != null);
  }

  ApiException _offline() => const ApiException(
    statusCode: 0,
    code: 'NETWORK',
    message: 'Cannot reach the server. Check your connection and try again.',
  );

  Map<String, dynamic> _parse(http.Response response, {required bool hadToken}) {
    final status = response.statusCode;

    // The backend sends `application/json` without a charset; decode as UTF-8
    // ourselves so names and the ₹ sign survive.
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    Map<String, dynamic> decoded = const {};
    if (text.trim().isNotEmpty) {
      try {
      debugPrint('RESPONSE ${response.statusCode} ${response.request?.url} ${response.body}');
        final json = jsonDecode(text);
        if (json is Map<String, dynamic>) decoded = json;
      } on FormatException {
        // fall through: handled below
      }
    }

    if (status >= 200 && status < 300) return decoded;

    var code = 'HTTP_$status';
    var message = 'Request failed ($status).';
    final error = decoded['error'];
    if (error is Map) {
      code = (error['code'] as String?) ?? code;
      message = (error['message'] as String?) ?? message;
    }
    if (status == 401 && hadToken) onUnauthorized?.call();
    throw ApiException(statusCode: status, code: code, message: message);
  }
}
