import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'alert_detail_screen.dart';
import 'application/app_dependencies.dart';
import 'application/gps_map_view_model.dart';
import 'application/session_controller.dart';
import 'data/firebase_repositories.dart';
import 'data/firebase_notification_repository.dart';
import 'data/firebase_realtime_repositories.dart';
import 'dashboard_screen.dart';
import 'domain/models.dart';
import 'domain/repositories.dart';
import 'firebase_options.dart';
import 'role_selection_screen.dart';
import 'splash_screen.dart';
import 'user_role.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const useDemoData = bool.fromEnvironment(
    'USE_DEMO_DATA',
    defaultValue: false,
  );
  if (useDemoData) {
    runApp(MyApp(dependencies: AppDependencies.allMocks()));
    return;
  }
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    }
    final functions = FirebaseFunctions.instance;
    final notifications = FirebaseSupervisorNotificationRepository(
      functions: functions,
    );
    runApp(
      MyApp(
        dependencies: AppDependencies(
          authentication: FirebaseAuthenticationRepository(),
          users: RtdbUserRepository(),
          sites: RtdbSiteRepository(),
          helmets: RtdbHelmetRepository(),
          readings: RtdbReadingRepository(),
          assessments: RtdbAssessmentRepository(),
          alerts: RtdbAlertRepository(functions: functions),
          configuration: RtdbConfigurationRepository(),
          notifications: notifications,
          dataSourceKind: DataSourceKind.liveFirebase,
        ),
      ),
    );
  } on Object {
    runApp(const _FirebaseInitializationFailureApp());
  }
}

class _FirebaseInitializationFailureApp extends StatelessWidget {
  const _FirebaseInitializationFailureApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: const Color(0xFF07152C),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_off_outlined,
                  color: Color(0xFF77A6D7),
                  size: 52,
                ),
                const SizedBox(height: 18),
                const Text(
                  'Firebase unavailable',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'SafeHelmet Pro could not initialize the live backend. '
                  'Check the Firebase configuration and network, then restart the app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    required this.dependencies,
    this.splashDuration = const Duration(seconds: 3),
  });

  final AppDependencies dependencies;
  final Duration? splashDuration;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final SessionController _session;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final MapFocusController _mapFocusController = MapFocusController();
  StreamSubscription<AlertNotificationIntent>? _notificationSubscription;
  AlertNotificationIntent? _pendingNotification;
  bool _openingNotification = false;

  @override
  void initState() {
    super.initState();
    _session = SessionController(widget.dependencies)..start();
    _session.addListener(_handleSessionChange);
    _notificationSubscription = widget.dependencies.notifications.alertIntents
        .listen(_handleNotificationIntent);
    unawaited(widget.dependencies.notifications.initialize());
  }

  void _handleSessionChange() {
    if (_session.status == SessionStatus.authenticated) {
      unawaited(_openPendingNotification());
    } else {
      _mapFocusController.clear();
    }
  }

  void _handleNotificationIntent(AlertNotificationIntent intent) {
    if (intent.source == NotificationOpenSource.foreground) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(
              intent.severity == SafetySeverity.critical
                  ? 'Critical safety alert received.'
                  : 'New safety alert received.',
            ),
            action: SnackBarAction(
              label: 'View',
              onPressed: () {
                _pendingNotification = intent;
                unawaited(_openPendingNotification());
              },
            ),
          ),
        );
      });
      return;
    }
    _pendingNotification = intent;
    unawaited(_openPendingNotification());
  }

  Future<void> _openPendingNotification() async {
    if (_openingNotification ||
        _session.status != SessionStatus.authenticated ||
        _session.profile == null ||
        _session.profile!.role == UserRole.administrator) {
      return;
    }
    final intent = _pendingNotification;
    if (intent == null) return;
    _openingNotification = true;
    try {
      final alert = await widget.dependencies.alerts.getAuthorizedAlert(
        _session.profile!,
        intent.alertId,
      );
      if (alert == null) {
        _pendingNotification = null;
        _showNeutralAccessMessage();
        return;
      }
      final navigator = _navigatorKey.currentState;
      if (navigator == null) return;
      _pendingNotification = null;
      final mapFocus = criticalNotificationMapFocus(
        actor: _session.profile!,
        alert: alert,
      );
      if (mapFocus != null) {
        navigator.popUntil((route) => route.isFirst);
        _mapFocusController.focus(mapFocus);
        return;
      }
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => AlertDetailScreen(
            profile: _session.profile!,
            alertId: alert.alertId,
            dependencies: widget.dependencies,
          ),
        ),
      );
    } on Object {
      _pendingNotification = null;
      _showNeutralAccessMessage();
    } finally {
      _openingNotification = false;
    }
  }

  void _showNeutralAccessMessage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text(
            'This alert is unavailable or outside your assigned scope.',
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _session.removeListener(_handleSessionChange);
    _notificationSubscription?.cancel();
    widget.dependencies.notifications.dispose();
    _mapFocusController.dispose();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      debugShowCheckedModeBanner: false,
      title: 'SafeHelmet Pro',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      builder: (context, child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _session.recordUserActivity(),
        child: child,
      ),
      // Always show splash screen on app start
      home: SplashScreen(
        builder: (context) => AuthWrapper(
          session: _session,
          mapFocusController: _mapFocusController,
        ),
        duration: widget.splashDuration,
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({
    super.key,
    required this.session,
    required this.mapFocusController,
  });

  final SessionController session;
  final MapFocusController mapFocusController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        if (session.status == SessionStatus.loading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (session.status == SessionStatus.authenticated &&
            session.profile != null &&
            session.profile!.role != UserRole.administrator) {
          final profile = session.profile!;
          return DashboardScreen(
            key: ValueKey(
              '${profile.uid}-${profile.updatedAt.millisecondsSinceEpoch}-'
              '${profile.role.name}-${profile.siteIds.join(',')}-'
              '${profile.authorizedHelmetIds.join(',')}',
            ),
            session: session,
            profile: profile,
            mapFocusController: mapFocusController,
          );
        }

        if (session.status == SessionStatus.authenticated &&
            session.profile?.role == UserRole.administrator) {
          return _SessionMessageScreen(
            icon: Icons.admin_panel_settings_outlined,
            title: 'Administrator access confirmed',
            message:
                'The mobile administrator portal is not part of this phase. '
                'No operational data is exposed here.',
            actionLabel: 'Sign out',
            onAction: session.signOut,
          );
        }

        if (session.status == SessionStatus.error ||
            session.status == SessionStatus.accessDenied ||
            session.status == SessionStatus.disabled) {
          return _SessionMessageScreen(
            icon: session.status == SessionStatus.disabled
                ? Icons.block_outlined
                : Icons.lock_outline_rounded,
            title: session.status == SessionStatus.disabled
                ? 'Account disabled'
                : session.status == SessionStatus.accessDenied
                ? 'Access denied'
                : 'Unable to continue',
            message: session.errorMessage ?? 'Unable to load your profile.',
            actionLabel: 'Return to sign in',
            onAction: session.signOut,
          );
        }

        return RoleSelectionScreen(session: session);
      },
    );
  }
}

class _SessionMessageScreen extends StatelessWidget {
  const _SessionMessageScreen({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final Future<void> Function() onAction;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07152C),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 52, color: const Color(0xFF77A6D7)),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                ElevatedButton(onPressed: onAction, child: Text(actionLabel)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
