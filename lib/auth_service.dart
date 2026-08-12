import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthFlowException implements Exception {
  final String message;
  const AuthFlowException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = firestore ?? FirebaseFirestore.instance;

  // Public sign-up always creates a STUDENT account. Teacher accounts can
  // only be created by admin_tools/create_teacher.py (sets a custom claim +
  // Firestore accountStatus:'active'), so a caller can never self-escalate
  // to the teacher role through this path.
  Future<void> signUpStudent({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final cleanName = displayName.trim();
    if (cleanName.length < 2) {
      throw const AuthFlowException('Enter your full name.');
    }
    if (password.length < 8) {
      throw const AuthFlowException('Password must contain at least 8 characters.');
    }

    UserCredential? credential;
    try {
      credential = await _auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      final user = credential.user!;
      await user.updateDisplayName(cleanName);

      final parts = cleanName.split(RegExp(r'\s+'));
      final firstName = parts.first;
      final lastName = parts.length > 1 ? parts.skip(1).join(' ') : '';

      // Automatically assign new registered student to teacher
      String? assignedTeacherId;

      final teacherQuery = await _db
          .collection('users')
          .where('role', isEqualTo: 'teacher')
          .limit(1)
          .get();

      if (teacherQuery.docs.isNotEmpty) {
        assignedTeacherId = teacherQuery.docs.first.id;
      }

      await _db.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': normalizedEmail,
        'emailLower': normalizedEmail,
        'displayName': cleanName,
        'firstName': firstName,
        'lastName': lastName,
        'role': 'student',
        'teacherId': assignedTeacherId,
        'accountStatus': 'active',
        'emailVerified': false,
        'settings': {
          'difficulty': 'Adaptive (AI-controlled)',
          'focusMode': true,
          'reviewReminders': true,
          'weeklyReport': true,
          'newFeatures': false,
          'emailDigest': true,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
      });

      if (assignedTeacherId != null) {
        await _db.collection('teacherStudentSummaries').doc(user.uid).set({
          'studentId': user.uid,
          'teacherId': assignedTeacherId,
          'displayName': cleanName,
          'email': normalizedEmail,
          'currentTopic': 'No active topic',
          'masteryPercent': 0,
          'retentionPercent': 0,
          'overdueReviews': 0,
          'pendingHelpRequests': 0,
          'completedReviews': 0,
          'riskLevel': 'reviewSoon',
          'riskReasons': ['Newly registered student'],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await user.sendEmailVerification();
    } catch (_) {
      // Roll back the Auth user if the Firestore write (or verification
      // email) failed, so we don't leave an orphaned Auth-only account.
      if (credential?.user != null) {
        try {
          await credential!.user!.delete();
        } catch (_) {
          // The original error is more useful than a cleanup failure.
        }
      }
      rethrow;
    }
  }

  Future<void> login(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    final user = credential.user!;
    await user.reload();

    final userRef = _db.collection('users').doc(user.uid);
    final document = await userRef.get();

    // Auto-fetch default teacher
    String? defaultTeacherId;
    final teacherQuery = await _db
        .collection('users')
        .where('role', isEqualTo: 'teacher')
        .limit(1)
        .get();
    if (teacherQuery.docs.isNotEmpty) {
      defaultTeacherId = teacherQuery.docs.first.id;
    }

    if (!document.exists) {
      // Account exists in Firebase Auth but has no profile doc yet (e.g.
      // pre-existing account from before this schema) — backfill it.
      await userRef.set({
        'uid': user.uid,
        'email': user.email,
        'emailLower': user.email?.toLowerCase(),
        'displayName': user.displayName ?? user.email?.split('@').first,
        'role': 'student',
        'teacherId': defaultTeacherId,
        'accountStatus': 'active',
        'emailVerified': user.emailVerified,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      final data = document.data() ?? {};
      final status = data['accountStatus']?.toString() ?? 'active';
      final role = data['role']?.toString() ?? 'student';
      if (status != 'active') {
        await _auth.signOut();
        throw const AuthFlowException('This account is not active. Contact the administrator.');
      }

      final updates = <String, dynamic>{
        'emailVerified': user.emailVerified,
        'lastLoginAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (role == 'student' && (data['teacherId'] == null || data['teacherId'].toString().isEmpty)) {
        if (defaultTeacherId != null) {
          updates['teacherId'] = defaultTeacherId;
        }
      }

      await userRef.update(updates);
    }

    // Ensure teacherStudentSummaries doc exists if student has an assigned teacher
    if (defaultTeacherId != null) {
      final summaryRef = _db.collection('teacherStudentSummaries').doc(user.uid);
      final summaryDoc = await summaryRef.get();
      if (!summaryDoc.exists) {
        final displayName = user.displayName ?? user.email?.split('@').first ?? 'Student';
        await summaryRef.set({
          'studentId': user.uid,
          'teacherId': defaultTeacherId,
          'displayName': displayName,
          'email': user.email ?? '',
          'currentTopic': 'No active topic',
          'masteryPercent': 0,
          'retentionPercent': 0,
          'overdueReviews': 0,
          'pendingHelpRequests': 0,
          'completedReviews': 0,
          'riskLevel': 'reviewSoon',
          'riskReasons': ['Registered student'],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
  }

  Future<void> resendVerificationEmail() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthFlowException('No signed-in user was found.');
    }
    await user.sendEmailVerification();
  }

  Future<bool> refreshEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    final refreshed = _auth.currentUser;
    final verified = refreshed?.emailVerified ?? false;
    await _db.collection('users').doc(user.uid).set({
      'emailVerified': verified,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return verified;
  }

  Future<void> logout() => _auth.signOut();

  User? get currentUser => _auth.currentUser;

  Stream<User?> get userStream => _auth.authStateChanges();
}
