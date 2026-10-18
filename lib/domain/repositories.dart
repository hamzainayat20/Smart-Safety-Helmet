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
