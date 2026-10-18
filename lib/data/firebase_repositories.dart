import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/models.dart';
import '../domain/repositories.dart';
import '../user_role.dart';

final class FirebaseAuthenticationRepository
    implements AuthenticationRepository {
  FirebaseAuthenticationRepository({FirebaseAuth? firebaseAuth})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;

  Future<AuthenticatedIdentity?> _identity(
    User? user, {
    bool forceRefresh = false,
  }) async {
    if (user == null) return null;
    final token = await user.getIdTokenResult(forceRefresh);
    final claims = token.claims ?? const <String, dynamic>{};
    final claimedRole =
        userRoleFromTrustedClaim(claims['role']) ??
        (claims['admin'] == true
            ? UserRole.administrator
            : claims['supervisor'] == true
            ? UserRole.supervisor
            : null);
    return AuthenticatedIdentity(
      uid: user.uid,
      email: user.email,
      emailVerified: user.emailVerified,
      trustedRole: claimedRole,
    );
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthException catch (error) {
      throw _mapFailure(error);
    }
  }

  AuthFailure _mapFailure(FirebaseAuthException error) => switch (error.code) {
    'user-disabled' => const AuthFailure(
      AuthFailureCode.disabledAccount,
      'This account has been disabled. Contact an administrator.',
    ),
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' => const AuthFailure(
      AuthFailureCode.invalidCredentials,
      'The email or password is incorrect.',
    ),
    'invalid-email' => const AuthFailure(
      AuthFailureCode.invalidEmail,
      'Enter a valid email address.',
    ),
    'email-already-in-use' => const AuthFailure(
      AuthFailureCode.emailAlreadyInUse,
      'An account already exists for this email address.',
    ),
    'weak-password' => const AuthFailure(
      AuthFailureCode.weakPassword,
      'Use a stronger password with at least six characters.',
    ),
    'too-many-requests' => const AuthFailure(
      AuthFailureCode.rateLimited,
      'Too many attempts. Wait before trying again.',
    ),
    'network-request-failed' => const AuthFailure(
      AuthFailureCode.network,
      'Network unavailable. Check your connection and retry.',
    ),
    _ => const AuthFailure(
      AuthFailureCode.unknown,
      'Authentication could not be completed. Try again.',
    ),
  };

  @override
  Stream<AuthenticatedIdentity?> get authStateChanges =>
      _firebaseAuth.idTokenChanges().asyncMap(_identity);

  @override
  Future<AuthenticatedIdentity> signIn({
    required String email,
    required String password,
  }) async {
    return _guard(() async {
      final result = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return await _identity(result.user) ??
          (throw const AuthFailure(
            AuthFailureCode.noCurrentUser,
            'Authentication returned no user.',
          ));
    });
  }

  @override
  Future<AuthenticatedIdentity> registerWorker({
    required String email,
    required String password,
  }) async {
    return _guard(() async {
      final result = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return await _identity(result.user) ??
          (throw const AuthFailure(
            AuthFailureCode.noCurrentUser,
            'Registration returned no user.',
          ));
    });
  }

  @override
  Future<void> sendPasswordResetEmail(String email) =>
      _guard(() => _firebaseAuth.sendPasswordResetEmail(email: email));

  @override
  Future<void> sendEmailVerification() => _guard(() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw const AuthFailure(
        AuthFailureCode.noCurrentUser,
        'Sign in before requesting email verification.',
      );
    }
    await user.sendEmailVerification();
  });

  @override
  Future<void> deleteCurrentUser() => _guard(() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw const AuthFailure(
        AuthFailureCode.noCurrentUser,
        'There is no newly created account to remove.',
      );
    }
    await user.delete();
  });

  @override
  Future<AuthenticatedIdentity?> refreshIdentity() => _guard(() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return null;
    await user.reload();
    return _identity(_firebaseAuth.currentUser, forceRefresh: true);
  });

  @override
  Future<void> signOut() => _firebaseAuth.signOut();
}

final class FirestoreUserRepository implements UserRepository {
  FirestoreUserRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  Map<String, dynamic> _normalize(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final source = snapshot.data();
    if (source == null) throw StateError('User profile does not exist.');
    final data = Map<String, dynamic>.from(source);
    data['schemaVersion'] ??= currentSchemaVersion;
    data['uid'] ??= snapshot.id;
    data['active'] ??= true;
    final updatedAt = data['updatedAt'] ?? data['createdAt'];
    if (updatedAt is Timestamp) {
      data['updatedAt'] = updatedAt.millisecondsSinceEpoch;
    }
    data['updatedAt'] ??= 0;
    return data;
  }

  @override
  Future<UserProfile?> getProfile(String uid) async {
    final snapshot = await _users.doc(uid).get();
    return snapshot.exists ? UserProfile.fromJson(_normalize(snapshot)) : null;
  }

  @override
  Stream<UserProfile?> watchProfile(String uid) => _users
      .doc(uid)
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.exists ? UserProfile.fromJson(_normalize(snapshot)) : null,
      );

  @override
  Future<void> createWorkerProfile(UserProfile profile) async {
    if (profile.role != UserRole.worker) {
      throw const RepositoryAccessException(
        'FORBIDDEN_ROLE',
        'The client may only create worker profiles.',
      );
    }
    await _users.doc(profile.uid).set({
      'schemaVersion': profile.schemaVersion,
      'uid': profile.uid,
      'name': profile.displayName,
      'email': profile.email,
      'organization': profile.organizationName,
      'role': UserRole.worker.name,
      'active': true,
      'siteIds': const <String>[],
      'authorizedHelmetIds': const <String>[],
      'pushAlertsEnabled': profile.pushAlertsEnabled,
      'criticalAlertsOnly': profile.criticalAlertsOnly,
      'vibrationEnabled': profile.vibrationEnabled,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> updateNotificationPreferences({
    required UserProfile actor,
    required bool pushAlertsEnabled,
    required bool criticalAlertsOnly,
    required bool vibrationEnabled,
  }) => _users.doc(actor.uid).update({
    'pushAlertsEnabled': pushAlertsEnabled,
    'criticalAlertsOnly': criticalAlertsOnly,
    'vibrationEnabled': vibrationEnabled,
    'updatedAt': FieldValue.serverTimestamp(),
  });
}
