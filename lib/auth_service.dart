import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'user_role.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Stream of auth state changes
  Stream<User?> get userStream => _auth.authStateChanges();

  // Sign up
  Future<String?> signUp({
    required String email,
    required String password,
    required String name,
    required String organization,
    required UserRole role,
  }) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      User? user = result.user;

      if (user != null) {
        // Store extra details in Firestore
        await _firestore.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'name': name,
          'email': email,
          'organization': organization,
          'role': role.name, // Store role as string (supervisor or worker)
          'createdAt': FieldValue.serverTimestamp(),
        });
        return null; // Success
      }
      return 'User creation failed';
    } on FirebaseAuthException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  // Sign in with role verification
  Future<String?> signIn({
    required String email,
    required String password,
    required UserRole expectedRole,
  }) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      User? user = result.user;
      if (user != null) {
        // Fetch user data to verify role
        DocumentSnapshot doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          final dynamic roleData = doc.get('role');
          String actualRole;
          
          // Safely handle both legacy (int) and new (String) role formats
          if (roleData is int) {
            actualRole = UserRole.values[roleData].name;
          } else {
            actualRole = roleData.toString();
          }

          if (actualRole != expectedRole.name) {
            // Role mismatch - logout and return error
            await _auth.signOut();
            return 'Access Denied: You are registered as a $actualRole. Please login through the correct portal.';
          }
        } else {
          await _auth.signOut();
          return 'User profile not found.';
        }
      }
      return null; // Success
    } on FirebaseAuthException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Get current user data from Firestore
  Future<DocumentSnapshot?> getUserData() async {
    User? user = _auth.currentUser;
    if (user != null) {
      return await _firestore.collection('users').doc(user.uid).get();
    }
    return null;
  }
}
