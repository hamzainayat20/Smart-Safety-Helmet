import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';
import '../user_role.dart';
import 'app_dependencies.dart';

enum SessionStatus {
  loading,
  signedOut,
  authenticated,
  accessDenied,
  disabled,
  error,
}

enum SessionIssue {
  none,
  disabledAccount,
  inactiveProfile,
  roleMismatch,
  untrustedRole,
  profileMissing,
  invalidCredentials,
  invalidEmail,
  weakPassword,
  emailAlreadyInUse,
  rateLimited,
  network,
  unknown,
}

final class SessionActionResult {
  const SessionActionResult._({
    required this.succeeded,
    required this.issue,
    required this.message,
  });

  const SessionActionResult.success(String message)
    : this._(succeeded: true, issue: SessionIssue.none, message: message);

  const SessionActionResult.failure(SessionIssue issue, String message)
    : this._(succeeded: false, issue: issue, message: message);

  final bool succeeded;
  final SessionIssue issue;
  final String message;
}

final class SessionController extends ChangeNotifier {
  SessionController(
    this.dependencies, {
    this.inactivityTimeout = const Duration(minutes: 30),
  });

  final AppDependencies dependencies;
  final Duration inactivityTimeout;
  StreamSubscription<AuthenticatedIdentity?>? _authSubscription;
  StreamSubscription<UserProfile?>? _profileSubscription;
  Timer? _inactivityTimer;
  int _identityGeneration = 0;

  SessionStatus _status = SessionStatus.loading;
  UserProfile? _profile;
  AuthenticatedIdentity? _identity;
  String? _errorMessage;
  String? _sessionNotice;
  bool _busy = false;
  UserRole? _portalPreference;

  SessionStatus get status => _status;
  UserProfile? get profile => _profile;
  AuthenticatedIdentity? get identity => _identity;
  String? get errorMessage => _errorMessage;
  String? get sessionNotice => _sessionNotice;
  bool get busy => _busy;

  void start() {
    _authSubscription ??= dependencies.authentication.authStateChanges.listen(
      _handleIdentity,
      onError: (Object error) async {
        await _clearSensitiveSession();
        _status = SessionStatus.error;
        _errorMessage = _safeMessage(error);
        notifyListeners();
      },
    );
  }

  Future<void> _handleIdentity(AuthenticatedIdentity? identity) async {
    final generation = ++_identityGeneration;
    await _profileSubscription?.cancel();
    _profileSubscription = null;
    _inactivityTimer?.cancel();
    await dependencies.sensitiveData.clearAll();
    _profile = null;
    _identity = identity;
    _errorMessage = null;

    if (identity == null) {
      _status = SessionStatus.signedOut;
      notifyListeners();
      return;
    }
    _status = SessionStatus.loading;
    notifyListeners();
    _profileSubscription = dependencies.users
        .watchProfile(identity.uid)
        .listen(
          (profile) async {
            if (generation != _identityGeneration) return;
            await _applyTrustedProfile(identity, profile);
          },
          onError: (Object error) async {
            if (generation != _identityGeneration) return;
            await dependencies.sensitiveData.clearAll();
            _status = SessionStatus.error;
            _errorMessage = _safeMessage(error);
            notifyListeners();
          },
        );
  }

  Future<void> _applyTrustedProfile(
    AuthenticatedIdentity identity,
    UserProfile? profile,
  ) async {
    if (profile == null) {
      await dependencies.sensitiveData.clearAll();
      _profile = null;
      _status = SessionStatus.accessDenied;
      _errorMessage =
          'No trusted profile or assignment record exists for this account.';
      notifyListeners();
      return;
    }
    if (!profile.active) {
      await dependencies.sensitiveData.clearAll();
      _profile = null;
      _status = SessionStatus.disabled;
      _errorMessage =
          'This account has been disabled. Contact an administrator.';
      notifyListeners();
      return;
    }
    final effectiveRole = _effectiveRole(identity, profile);
    if (effectiveRole == null) {
      await dependencies.sensitiveData.clearAll();
      _profile = null;
      _status = SessionStatus.accessDenied;
      _errorMessage =
          'Trusted role authorization is missing or does not match the profile.';
      notifyListeners();
      return;
    }
    if (_portalPreference != null && effectiveRole != _portalPreference) {
      await dependencies.sensitiveData.clearAll();
      _profile = null;
      _status = SessionStatus.accessDenied;
      _errorMessage =
          'Role mismatch. This account is authorized as ${effectiveRole.label}.';
      notifyListeners();
      await dependencies.authentication.signOut();
      return;
    }

    final previous = _profile;
    if (previous != null && _authorizationChanged(previous, profile)) {
      await dependencies.sensitiveData.clearAll();
    }
    _profile = profile;
    _status = SessionStatus.authenticated;
    _errorMessage = null;
    if (effectiveRole == UserRole.supervisor) {
      try {
        await dependencies.notifications.activateForSupervisor(profile);
      } on Object {
        _sessionNotice =
            'Push notification registration is unavailable. Live alerts remain visible in the app.';
      }
    } else {
      await dependencies.notifications.deactivate(actor: previous);
    }
    _scheduleInactivityLock(effectiveRole);
    notifyListeners();
  }

  UserRole? _effectiveRole(
    AuthenticatedIdentity identity,
    UserProfile profile,
  ) {
    final claimedRole = identity.trustedRole;
    if (claimedRole == null) {
      return profile.role == UserRole.worker ? UserRole.worker : null;
    }
    return claimedRole == profile.role ? claimedRole : null;
  }

  bool _authorizationChanged(UserProfile before, UserProfile after) {
    return before.role != after.role ||
        before.active != after.active ||
        !listEquals(before.siteIds, after.siteIds) ||
        !listEquals(before.authorizedHelmetIds, after.authorizedHelmetIds);
  }

  Future<SessionActionResult> signIn({
    required String email,
    required String password,
    required UserRole expectedRole,
  }) async {
    _setBusy(true);
    _portalPreference = expectedRole;
    try {
      final identity = await dependencies.authentication.signIn(
        email: email,
        password: password,
      );
      final profile = await dependencies.users.getProfile(identity.uid);
      final authorizationFailure = _authorizationFailure(identity, profile);
      if (authorizationFailure != null) {
        await dependencies.authentication.signOut();
        return authorizationFailure;
      }
      final effectiveRole = _effectiveRole(identity, profile!);
      if (effectiveRole != expectedRole) {
        _portalPreference = null;
        await dependencies.authentication.signOut();
        return SessionActionResult.failure(
          SessionIssue.roleMismatch,
          'Access denied: this account is authorized as ${effectiveRole!.label}. '
          'Use the correct portal.',
        );
      }
      return const SessionActionResult.success('Signed in securely.');
    } on Object catch (error) {
      _portalPreference = null;
      return _resultForError(error);
    } finally {
      _setBusy(false);
    }
  }

  SessionActionResult? _authorizationFailure(
    AuthenticatedIdentity identity,
    UserProfile? profile,
  ) {
    if (profile == null) {
      return const SessionActionResult.failure(
        SessionIssue.profileMissing,
        'No trusted profile or assignment record exists for this account.',
      );
    }
    if (!profile.active) {
      return const SessionActionResult.failure(
        SessionIssue.inactiveProfile,
        'This account is inactive. Contact an administrator.',
      );
    }
    if (_effectiveRole(identity, profile) == null) {
      return const SessionActionResult.failure(
        SessionIssue.untrustedRole,
        'Supervisor or administrator access requires a trusted backend assignment.',
      );
    }
    return null;
  }

  Future<SessionActionResult> registerWorker({
    required String email,
    required String password,
    required String displayName,
    required String organizationName,
  }) async {
    _setBusy(true);
    try {
      final identity = await dependencies.authentication.registerWorker(
        email: email,
        password: password,
      );
      final profile = UserProfile(
        uid: identity.uid,
        displayName: displayName,
        email: identity.email ?? email,
        role: UserRole.worker,
        active: true,
        organizationName: organizationName.isEmpty ? null : organizationName,
        siteIds: const [],
        authorizedHelmetIds: const [],
        updatedAt: DateTime.now().toUtc(),
      );
      try {
        await dependencies.users.createWorkerProfile(profile);
      } on Object catch (profileError) {
        try {
          await dependencies.authentication.deleteCurrentUser();
        } on Object {
          return SessionActionResult.failure(
            SessionIssue.unknown,
            '${_safeMessage(profileError)} The incomplete authentication '
            'account could not be removed automatically. Contact an '
            'administrator before retrying with this email.',
          );
        }
        return _resultForError(profileError);
      }
      return const SessionActionResult.success(
        'Worker account created. You can sign in now.',
      );
    } on Object catch (error) {
      return _resultForError(error);
    } finally {
      await dependencies.authentication.signOut();
      _setBusy(false);
    }
  }

  Future<SessionActionResult> sendPasswordReset(String email) async {
    _setBusy(true);
    try {
      await dependencies.authentication.sendPasswordResetEmail(email);
      return const SessionActionResult.success(
        'If an account exists for that email, a password-reset message has been sent.',
      );
    } on Object catch (error) {
      return _resultForError(error);
    } finally {
      _setBusy(false);
    }
  }

  void recordUserActivity() {
    final role = _profile?.role;
    if (_status == SessionStatus.authenticated &&
        (role == UserRole.supervisor || role == UserRole.administrator)) {
      _scheduleInactivityLock(role!);
    }
  }

  void _scheduleInactivityLock(UserRole role) {
    _inactivityTimer?.cancel();
    if (role == UserRole.worker) return;
    _inactivityTimer = Timer(inactivityTimeout, () async {
      _sessionNotice =
          'The privileged session was locked after 30 minutes of inactivity.';
      await signOut();
    });
  }

  Future<void> signOut() async {
    await _clearSensitiveSession();
    _status = SessionStatus.signedOut;
    notifyListeners();
    await dependencies.authentication.signOut();
  }

  Future<void> _clearSensitiveSession() async {
    final previousProfile = _profile;
    _identityGeneration++;
    await _profileSubscription?.cancel();
    _profileSubscription = null;
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    await dependencies.sensitiveData.clearAll();
    await dependencies.notifications.deactivate(actor: previousProfile);
    _profile = null;
    _identity = null;
    _errorMessage = null;
    _portalPreference = null;
  }

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }

  SessionActionResult _resultForError(Object error) {
    if (error is AuthFailure) {
      final issue = switch (error.code) {
        AuthFailureCode.disabledAccount => SessionIssue.disabledAccount,
        AuthFailureCode.invalidCredentials => SessionIssue.invalidCredentials,
        AuthFailureCode.invalidEmail => SessionIssue.invalidEmail,
        AuthFailureCode.emailAlreadyInUse => SessionIssue.emailAlreadyInUse,
        AuthFailureCode.weakPassword => SessionIssue.weakPassword,
        AuthFailureCode.rateLimited => SessionIssue.rateLimited,
        AuthFailureCode.network => SessionIssue.network,
        AuthFailureCode.noCurrentUser ||
        AuthFailureCode.unknown => SessionIssue.unknown,
      };
      return SessionActionResult.failure(issue, error.message);
    }
    return SessionActionResult.failure(
      SessionIssue.unknown,
      _safeMessage(error),
    );
  }

  String _safeMessage(Object error) {
    if (error is RepositoryAccessException) return error.message;
    if (error is AuthFailure) return error.message;
    return 'The request could not be completed. Try again.';
  }

  @override
  void dispose() {
    _identityGeneration++;
    _inactivityTimer?.cancel();
    _authSubscription?.cancel();
    _profileSubscription?.cancel();
    super.dispose();
  }
}
