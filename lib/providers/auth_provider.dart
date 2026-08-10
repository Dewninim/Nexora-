import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth_service.dart';

class AppAuthProvider extends ChangeNotifier {
  final AuthService _auth = AuthService();

  bool isLoading = false;
  String? errorMessage;

  User? get user => FirebaseAuth.instance.currentUser;
  Stream<User?> get userStream => _auth.userStream;

  Future<bool> login(String email, String password) async {
    return _run(() => _auth.login(email, password));
  }

  // Public sign-up always creates a student account — teacher accounts are
  // provisioned separately via admin_tools/create_teacher.py.
  Future<bool> signUpStudent({
    required String email,
    required String password,
    required String displayName,
  }) async {
    return _run(
      () => _auth.signUpStudent(
        email: email,
        password: password,
        displayName: displayName,
      ),
    );
  }

  Future<bool> sendPasswordReset(String email) async {
    return _run(() => _auth.sendPasswordReset(email));
  }

  Future<bool> resendVerificationEmail() async {
    return _run(_auth.resendVerificationEmail);
  }

  Future<bool> refreshEmailVerification() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      return await _auth.refreshEmailVerification();
    } on FirebaseAuthException catch (error) {
      errorMessage = getFirebaseErrorMessage(error);
      return false;
    } on AuthFlowException catch (error) {
      errorMessage = error.message;
      return false;
    } catch (_) {
      errorMessage = 'Could not refresh verification status.';
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _auth.logout();
  }

  Future<bool> _run(Future<void> Function() action) async {
    try {
      isLoading = true;
      errorMessage = null;
      notifyListeners();
      await action();
      return true;
    } on FirebaseAuthException catch (error) {
      errorMessage = getFirebaseErrorMessage(error);
      return false;
    } on AuthFlowException catch (error) {
      errorMessage = error.message;
      return false;
    } catch (error) {
      errorMessage = error.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // Firebase Auth SDK v10+ consolidates some codes into 'invalid-credential'.
  // Keep legacy codes as fallbacks for older SDK versions.
  String getFirebaseErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-credential':
      case 'user-not-found':
      case 'wrong-password':
        return 'Invalid email or password.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again.';
      case 'email-already-in-use':
        return 'This email address is already registered.';
      case 'weak-password':
        return 'Use a stronger password with at least 8 characters.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'network-request-failed':
        return 'Check your internet connection.';
      case 'operation-not-allowed':
        return 'Email/password authentication is not enabled.';
      default:
        return error.message ?? 'Authentication failed. Please try again.';
    }
  }
}
