import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../domain/models.dart';
import '../domain/repositories.dart';

final class AwsAssistantRepository implements AssistantRepository {
  AwsAssistantRepository({
    FirebaseAuth? auth,
    http.Client? client,
    Uri? endpoint,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _client = client ?? http.Client(),
       _endpoint = endpoint ?? Uri.parse(_configuredEndpoint);

  static const _configuredEndpoint = String.fromEnvironment(
    'ASSISTANT_ENDPOINT',
    defaultValue:
        'https://3sqh6oq2i5.execute-api.us-east-1.amazonaws.com/staging/v1/assistant',
  );

  final FirebaseAuth _auth;
  final http.Client _client;
  final Uri _endpoint;

  @override
  Future<AssistantReply> ask({
    required String helmetId,
    required String question,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const RepositoryAccessException(
        'UNAUTHENTICATED',
        'Sign in again before using the safety assistant.',
      );
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const RepositoryAccessException(
        'UNAUTHENTICATED',
        'Your sign-in session could not be verified. Sign in again.',
      );
    }

    try {
      final response = await _client
          .post(
            _endpoint,
            headers: {
              'authorization': 'Bearer $token',
              'content-type': 'application/json',
            },
            body: jsonEncode({'helmetId': helmetId, 'question': question}),
          )
          .timeout(const Duration(seconds: 30));
      final decoded = jsonDecode(response.body);
      final body = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = body['error'];
        final errorMap = error is Map
            ? Map<String, dynamic>.from(error)
            : <String, dynamic>{};
        throw RepositoryAccessException(
          errorMap['code']?.toString() ?? 'ASSISTANT_ERROR',
          errorMap['message']?.toString() ??
              'The safety assistant could not answer right now.',
        );
      }
      return AssistantReply(
        answer: _requiredString(body, 'answer'),
        disclaimer: _requiredString(body, 'disclaimer'),
        helmetId: _requiredString(body, 'helmetId'),
        sourceEventId: _requiredString(body, 'sourceEventId'),
        generatedAt: DateTime.fromMillisecondsSinceEpoch(
          _requiredInt(body, 'generatedAt'),
          isUtc: true,
        ),
      );
    } on RepositoryAccessException {
      rethrow;
    } on Object {
      throw const RepositoryAccessException(
        'ASSISTANT_UNAVAILABLE',
        'The safety assistant is temporarily unavailable. Try again.',
      );
    }
  }

  String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    throw const RepositoryAccessException(
      'INVALID_RESPONSE',
      'The safety assistant returned an incomplete response.',
    );
  }

  int _requiredInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    throw const RepositoryAccessException(
      'INVALID_RESPONSE',
      'The safety assistant returned an incomplete response.',
    );
  }
}
