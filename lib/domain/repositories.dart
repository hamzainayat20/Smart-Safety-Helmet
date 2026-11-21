import '../user_role.dart';
import 'models.dart';

final class AuthenticatedIdentity {
  const AuthenticatedIdentity({
    required this.uid,
    required this.email,
    required this.emailVerified,
    this.trustedRole,
  });

  final String uid;
  final String? email;
  final bool emailVerified;
  final UserRole? trustedRole;
}

enum AuthFailureCode {
  disabledAccount,
  invalidCredentials,
  invalidEmail,
  emailAlreadyInUse,
  weakPassword,
  rateLimited,
  network,
  noCurrentUser,
  unknown,
}

final class AuthFailure implements Exception {
  const AuthFailure(this.code, this.message);

  final AuthFailureCode code;
  final String message;

  @override
  String toString() => 'AuthFailure(${code.name}): $message';
}

abstract interface class AuthenticationRepository {
  Stream<AuthenticatedIdentity?> get authStateChanges;

  Future<AuthenticatedIdentity> signIn({
    required String email,
    required String password,
  });

  Future<AuthenticatedIdentity> registerWorker({
    required String email,
    required String password,
  });

  Future<void> sendPasswordResetEmail(String email);

  Future<void> sendEmailVerification();

  Future<void> deleteCurrentUser();

  Future<AuthenticatedIdentity?> refreshIdentity();

  Future<void> signOut();
}

abstract interface class UserRepository {
  Future<UserProfile?> getProfile(String uid);

  Stream<UserProfile?> watchProfile(String uid);

  Future<void> createWorkerProfile(UserProfile profile);

  Future<void> updateNotificationPreferences({
    required UserProfile actor,
    required bool pushAlertsEnabled,
    required bool criticalAlertsOnly,
    required bool vibrationEnabled,
  });
}

abstract interface class SiteRepository {
  Stream<List<Site>> watchAuthorizedSites(UserProfile actor);
}

abstract interface class HelmetRepository {
  Stream<List<Helmet>> watchAuthorizedHelmets(UserProfile actor);

  Future<Helmet?> getAuthorizedHelmet(UserProfile actor, String helmetId);
}

abstract interface class ReadingRepository {
  Stream<bool> watchBackendConnection();

  Stream<Map<String, SensorReading>> watchLatestReadings(UserProfile actor);

  Stream<List<SensorReading>> watchHelmetReadings(
    UserProfile actor,
    String helmetId,
  );
}

abstract interface class WorkerLocationRepository {
  Stream<Map<String, WorkerLocation>> watchLatestLocations(UserProfile actor);

  Future<void> writeLocation({
    required UserProfile actor,
    required Helmet helmet,
    required double latitudeDegrees,
    required double longitudeDegrees,
    required double accuracyM,
  });
}

final class NoopWorkerLocationRepository implements WorkerLocationRepository {
  const NoopWorkerLocationRepository();

  @override
  Stream<Map<String, WorkerLocation>> watchLatestLocations(UserProfile actor) =>
      Stream.value(const {});

  @override
  Future<void> writeLocation({
    required UserProfile actor,
    required Helmet helmet,
    required double latitudeDegrees,
    required double longitudeDegrees,
    required double accuracyM,
  }) async {}
}

enum WorkerLocationTrackingStatus {
  idle,
  needsBackgroundExplanation,
  foregroundOnly,
  background,
  permissionDenied,
  serviceDisabled,
  unavailable,
}

final class WorkerLocationTrackingState {
  const WorkerLocationTrackingState(this.status, {this.message});

  final WorkerLocationTrackingStatus status;
  final String? message;
}

abstract interface class WorkerLocationTracker {
  Stream<WorkerLocationTrackingState> get states;
  WorkerLocationTrackingState get state;

  Future<void> activate({
    required UserProfile actor,
    required Helmet helmet,
  });

  Future<void> requestBackgroundAccess();
  Future<void> refreshPermission();
  Future<void> openBatterySettings();
  Future<void> deactivate();
  void dispose();
}

final class NoopWorkerLocationTracker implements WorkerLocationTracker {
  const NoopWorkerLocationTracker();

  static const _state = WorkerLocationTrackingState(
    WorkerLocationTrackingStatus.unavailable,
  );

  @override
  WorkerLocationTrackingState get state => _state;

  @override
  Stream<WorkerLocationTrackingState> get states => Stream.value(_state);

  @override
  Future<void> activate({
    required UserProfile actor,
    required Helmet helmet,
  }) async {}

  @override
  Future<void> requestBackgroundAccess() async {}

  @override
  Future<void> refreshPermission() async {}

  @override
  Future<void> openBatterySettings() async {}

  @override
  Future<void> deactivate() async {}

  @override
  void dispose() {}
}

abstract interface class AssessmentRepository {
  Stream<Map<String, SafetyAssessment>> watchLatestAssessments(
    UserProfile actor,
  );

  Stream<List<SafetyAssessment>> watchHelmetAssessments(
    UserProfile actor,
    String helmetId,
  );
}

final class NoopAssessmentRepository implements AssessmentRepository {
  const NoopAssessmentRepository();

  @override
  Stream<Map<String, SafetyAssessment>> watchLatestAssessments(
    UserProfile actor,
  ) => Stream.value(const {});

  @override
  Stream<List<SafetyAssessment>> watchHelmetAssessments(
    UserProfile actor,
    String helmetId,
  ) => Stream.value(const []);
}

abstract interface class AlertRepository {
  Stream<List<SafetyAlert>> watchAuthorizedAlerts(UserProfile actor);

  Stream<SafetyAlert?> watchAuthorizedAlert(UserProfile actor, String alertId);

  Future<SafetyAlert?> getAuthorizedAlert(UserProfile actor, String alertId);

  Future<SafetyAlert> markViewed({
    required UserProfile actor,
    required String alertId,
  });

  Future<SafetyAlert> acknowledge({
    required UserProfile actor,
    required String alertId,
  });

  Future<SafetyAlert> resolve({
    required UserProfile actor,
    required String alertId,
    required String resolutionNote,
  });

  Future<SafetyAlert> retryDelivery({
    required UserProfile actor,
    required String alertId,
  });
}

enum NotificationOpenSource { foreground, background, terminated }

final class AlertNotificationIntent {
  const AlertNotificationIntent({
    required this.alertId,
    required this.source,
    this.severity,
  });

  final String alertId;
  final NotificationOpenSource source;
  final SafetySeverity? severity;
}

abstract interface class NotificationRepository {
  Stream<AlertNotificationIntent> get alertIntents;

  Future<void> initialize();

  Future<void> activateForSupervisor(UserProfile actor);

  Future<void> deactivate({UserProfile? actor});

  void dispose();
}

final class NoopNotificationRepository implements NotificationRepository {
  const NoopNotificationRepository();

  @override
  Stream<AlertNotificationIntent> get alertIntents => const Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> activateForSupervisor(UserProfile actor) async {}

  @override
  Future<void> deactivate({UserProfile? actor}) async {}

  @override
  void dispose() {}
}

abstract interface class ConfigurationRepository {
  Stream<HelmetConfiguration?> watchConfiguration(
    UserProfile actor,
    String helmetId,
  );

  Future<void> updateConfiguration({
    required UserProfile actor,
    required HelmetConfiguration configuration,
  });
}

abstract interface class AssistantRepository {
  Future<AssistantReply> ask({
    required String helmetId,
    required String question,
  });
}

final class NoopAssistantRepository implements AssistantRepository {
  const NoopAssistantRepository();

  @override
  Future<AssistantReply> ask({
    required String helmetId,
    required String question,
  }) => throw const RepositoryAccessException(
    'ASSISTANT_UNAVAILABLE',
    'The safety assistant is not configured for this build.',
  );
}

bool userCanAccessHelmet(UserProfile actor, Helmet helmet) {
  if (!actor.active) return false;
  switch (actor.role) {
    case UserRole.administrator:
      return true;
    case UserRole.supervisor:
      return actor.siteIds.contains(helmet.siteId) &&
          actor.authorizedHelmetIds.contains(helmet.helmetId);
    case UserRole.worker:
      return helmet.assignedWorkerId == actor.uid &&
          actor.authorizedHelmetIds.contains(helmet.helmetId);
  }
}

bool userCanManageHelmet(UserProfile actor, Helmet helmet) {
  if (!actor.active) return false;
  return actor.role == UserRole.administrator ||
      actor.role == UserRole.supervisor &&
          actor.siteIds.contains(helmet.siteId) &&
          actor.authorizedHelmetIds.contains(helmet.helmetId);
}

final class RepositoryAccessException implements Exception {
  const RepositoryAccessException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}
