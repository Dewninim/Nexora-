import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserRoleService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  UserRoleService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  /// Returns `teacher` or `student`. Teacher custom claims are checked first,
  /// while Firestore remains the display/profile source of truth.
  Future<String> getCurrentUserRole({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) return 'student';

    try {
      final token = await user.getIdTokenResult(forceRefresh);
      final claimRole = token.claims?['role']?.toString().trim().toLowerCase();
      if (claimRole == 'teacher') return 'teacher';
    } catch (_) {
      // Fall back to Firestore when claims cannot be refreshed.
    }

    final document =
        await _firestore.collection('users').doc(user.uid).get();
    final role = document.data()?['role']?.toString().trim().toLowerCase();
    return role == 'teacher' ? 'teacher' : 'student';
  }
}
