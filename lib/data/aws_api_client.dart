import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../domain/repositories.dart';

abstract final class AwsApiConfiguration {
  static const baseUrl = String.fromEnvironment(
    'AWS_API_BASE_URL',
    defaultValue:
        'https://3sqh6oq2i5.execute-api.us-east-1.amazonaws.com/staging',
  );

  static Uri endpoint(String path) => Uri.parse('$baseUrl$path');
}

final class AwsApiClient {
  AwsApiClient({FirebaseAuth? auth, http.Client? client})
    : _auth = auth ?? FirebaseAuth.instance,
      _client = client ?? http.Client();

  final FirebaseAuth _auth;
  final http.Client _client;

  Future<Map<String, dynamic>> request(
    String method,
    String path,
    Map<String, Object?> data,
  ) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const RepositoryAccessException(
        'PERMISSION_DENIED',
        'Authentication is required.',
      );
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const RepositoryAccessException(
        'PERMISSION_DENIED',
        'The sign-in session is invalid or expired.',
      );
    }
    try {
      final endpoint = AwsApiConfiguration.endpoint(path);
      final headers = {
        'authorization': 'Bearer $token',
        'content-type': 'application/json',
      };
      final encoded = jsonEncode(data);
      final response = switch (method) {
        'POST' => await _client.post(endpoint, headers: headers, body: encoded),
        'DELETE' => await _client.delete(endpoint, headers: headers, body: encoded),
        _ => throw ArgumentError.value(method, 'method'),
      };
      final decoded = jsonDecode(response.body);
      final body = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = body['error'];
        final details = error is Map
            ? Map<String, dynamic>.from(error)
            : <String, dynamic>{};
        final serverCode = details['code']?.toString();
        final code = switch (serverCode) {
          'permission-denied' || 'unauthenticated' => 'PERMISSION_DENIED',
          'failed-precondition' => 'HAZARD_ONGOING',
          'not-found' => 'NOT_FOUND',
          _ => 'BACKEND_ERROR',
        };
        throw RepositoryAccessException(
          code,
          details['message']?.toString() ??
              'The alert operation could not be completed.',
        );
      }
      return body;
    } on RepositoryAccessException {
      rethrow;
    } on Object {
      throw const RepositoryAccessException(
        'BACKEND_ERROR',
        'The live monitoring backend is unavailable. Try again.',
      );
    }
  }
}
