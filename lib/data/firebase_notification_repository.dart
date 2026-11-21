import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';
import '../firebase_options.dart';
import '../user_role.dart';
import 'aws_api_client.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Notification payloads are rendered by the operating system. Sensitive
  // alert details are deliberately fetched only after authenticated app open.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

final class FirebaseSupervisorNotificationRepository
    implements NotificationRepository {
  FirebaseSupervisorNotificationRepository({
    FirebaseMessaging? messaging,
    AwsApiClient? apiClient,
  }) : _messaging = messaging ?? FirebaseMessaging.instance,
       _apiClient = apiClient ?? AwsApiClient();

  final FirebaseMessaging _messaging;
  final AwsApiClient _apiClient;
  final StreamController<AlertNotificationIntent> _intents =
      StreamController.broadcast();

  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  UserProfile? _actor;
  String? _associatedToken;
  bool _initialized = false;
  bool _disposed = false;
  AlertNotificationIntent? _pendingInitialIntent;

  @override
  Stream<AlertNotificationIntent> get alertIntents async* {
    final pending = _pendingInitialIntent;
    _pendingInitialIntent = null;
    if (pending != null) yield pending;
    yield* _intents.stream;
  }

  @override
  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _initialized = true;
    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      (message) => _emitIntent(message, NotificationOpenSource.foreground),
    );
    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _emitIntent(message, NotificationOpenSource.background),
    );
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _emitIntent(initialMessage, NotificationOpenSource.terminated);
    }
  }

  void _emitIntent(RemoteMessage message, NotificationOpenSource source) {
    if (_disposed) return;
    final alertId = message.data['alertId']?.toString().trim();
    if (alertId == null || alertId.isEmpty || alertId.length > 128) return;
    final severityName = message.data['severity']?.toString();
    final severity = SafetySeverity.values
        .where((value) => value.name == severityName)
        .firstOrNull;
    final intent = AlertNotificationIntent(
      alertId: alertId,
      source: source,
      severity: severity,
    );
    if (source == NotificationOpenSource.terminated && !_intents.hasListener) {
      _pendingInitialIntent = intent;
    } else {
      _intents.add(intent);
    }
  }

  @override
  Future<void> activateForSupervisor(UserProfile actor) async {
    if (_disposed ||
        !actor.active ||
        actor.role != UserRole.supervisor ||
        !actor.pushAlertsEnabled) {
      await deactivate(actor: _actor);
      return;
    }
    await initialize();
    if (_actor?.uid == actor.uid && _associatedToken != null) {
      _actor = actor;
      return;
    }
    _actor = actor;
    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      await deactivate(actor: actor);
      throw const RepositoryAccessException(
        'NOTIFICATION_PERMISSION_DENIED',
        'Notification permission is disabled for this device.',
      );
    }
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    final token = await _messaging.getToken();
    if (token != null && token.isNotEmpty) await _associate(token);
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((
      refreshed,
    ) async {
      try {
        final previous = _associatedToken;
        if (previous != null && previous != refreshed) {
          await _removeAssociation(previous);
        }
        await _associate(refreshed);
      } on Object {
        // The next refresh or authenticated app start retries association.
      }
    });
  }

  Future<void> _associate(String token) async {
    final actor = _actor;
    if (actor == null || actor.role != UserRole.supervisor) return;
    await _apiClient.request('POST', '/v1/fcm-token', {
      'token': token,
      'platform': _platformName,
    });
    _associatedToken = token;
  }

  Future<void> _removeAssociation(String token) async {
    try {
      await _apiClient.request('DELETE', '/v1/fcm-token', {'token': token});
    } on Object {
      // Deleting the local registration token below invalidates delivery even
      // when the server association cannot be reached during sign-out.
    }
  }

  String get _platformName {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }

  @override
  Future<void> deactivate({UserProfile? actor}) async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    final token = _associatedToken;
    _associatedToken = null;
    _actor = null;
    if (token != null) await _removeAssociation(token);
    try {
      await _messaging.deleteToken();
    } on Object {
      // Session cleanup must continue even if the platform service is offline.
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _foregroundSubscription?.cancel();
    _openedSubscription?.cancel();
    _tokenRefreshSubscription?.cancel();
    _intents.close();
  }
}
