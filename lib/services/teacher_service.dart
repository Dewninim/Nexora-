import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/review_schedule_models.dart';
import '../models/teacher_models.dart';

class TeacherService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  TeacherService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  String get currentTeacherId {
    final id = _auth.currentUser?.uid;
    if (id == null) throw StateError('Teacher is not signed in.');
    return id;
  }

  Stream<List<TeacherStudentSummary>> watchAssignedStudents(String teacherId) {
    return _firestore
        .collection('teacherStudentSummaries')
        .where('teacherId', isEqualTo: teacherId)
        .snapshots()
        .map((snapshot) {
      final rows = snapshot.docs
          .map(TeacherStudentSummary.fromDocument)
          .toList(growable: false);
      rows.sort((a, b) {
        final riskCompare = a.riskLevel.index.compareTo(b.riskLevel.index);
        if (riskCompare != 0) return riskCompare;
        return a.displayName.compareTo(b.displayName);
      });
      return rows;
    });
  }

  Stream<List<TeacherHelpRequest>> watchHelpRequests({
    required String teacherId,
    bool includeResolved = false,
  }) {
    return _firestore
        .collection('helpRequests')
        .where('teacherId', isEqualTo: teacherId)
        .snapshots()
        .map((snapshot) {
      final requests = snapshot.docs
          .map(TeacherHelpRequest.fromDocument)
          .where(
            (item) => includeResolved ||
                item.status != HelpRequestStatus.resolved,
          )
          .toList();
      requests.sort((a, b) {
        final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad);
      });
      return requests;
    });
  }

  Stream<List<ReviewSchedule>> watchStudentSchedules(String studentId) {
    return _firestore
        .collection('reviewSchedules')
        .where('studentId', isEqualTo: studentId)
        .snapshots()
        .map((snapshot) {
      final schedules = snapshot.docs
          .map(ReviewSchedule.fromDocument)
          .toList(growable: false);
      schedules.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
      return schedules;
    });
  }

  Stream<List<TeacherMessage>> watchMessagesForStudent(String studentId) {
    return _firestore
        .collection('teacherMessages')
        .where('teacherId', isEqualTo: currentTeacherId)
        .where('studentId', isEqualTo: studentId)
        .snapshots()
        .map((snapshot) {
      final messages = snapshot.docs.map((doc) {
        final data = doc.data();
        return TeacherMessage(
          id: doc.id,
          teacherId: data['teacherId']?.toString() ?? '',
          studentId: data['studentId']?.toString() ?? '',
          subject: data['subject']?.toString() ?? 'Teacher message',
          message: data['message']?.toString() ?? '',
          practiceQuestion: data['practiceQuestion']?.toString(),
          helpRequestId: data['helpRequestId']?.toString(),
          isRead: data['isRead'] as bool? ?? false,
          createdAt: firestoreDate(data['createdAt']),
        );
      }).toList();
      messages.sort((a, b) {
        final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad);
      });
      return messages;
    });
  }

  /// Assigns an existing student account to the signed-in teacher.
  /// This is suitable for the university prototype. A production institution
  /// should move assignment approval to an administrator workflow.
  Future<void> assignStudentByEmail(String email) async {
    final teacherId = currentTeacherId;
    final normalized = email.trim().toLowerCase();
    final query = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'student')
        .where('emailLower', isEqualTo: normalized)
        .limit(1)
        .get();

    QueryDocumentSnapshot<Map<String, dynamic>>? student;
    if (query.docs.isNotEmpty) {
      student = query.docs.first;
    } else {
      final fallback = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'student')
          .where('email', isEqualTo: email.trim())
          .limit(1)
          .get();
      if (fallback.docs.isNotEmpty) student = fallback.docs.first;
    }

    if (student == null) {
      throw StateError('No student account was found for that email.');
    }
    final data = student.data();
    if ((data['role']?.toString() ?? 'student') != 'student') {
      throw StateError('The selected account is not a student account.');
    }

    final studentId = student.id;
    final userRef = _firestore.collection('users').doc(studentId);
    final summaryRef =
        _firestore.collection('teacherStudentSummaries').doc(studentId);
    final batch = _firestore.batch();
    batch.update(userRef, {
      'teacherId': teacherId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(
      summaryRef,
      {
        'studentId': studentId,
        'teacherId': teacherId,
        'displayName': data['displayName'] ?? data['email'] ?? 'Student',
        'email': data['email'] ?? '',
        'currentTopic': 'No active topic',
        'masteryPercent': 0,
        'retentionPercent': 0,
        'overdueReviews': 0,
        'pendingHelpRequests': 0,
        'completedReviews': 0,
        'riskLevel': 'reviewSoon',
        'riskReasons': ['No learning-session data has been recorded yet.'],
        'lastActiveAt': data['lastLoginAt'] ?? data['createdAt'],
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Future<void> removeStudentAssignment(String studentId) async {
    final teacherId = currentTeacherId;
    final summary = await _firestore
        .collection('teacherStudentSummaries')
        .doc(studentId)
        .get();
    if (!summary.exists || summary.data()?['teacherId'] != teacherId) {
      throw StateError('This student is not assigned to the current teacher.');
    }

    final batch = _firestore.batch();
    batch.update(_firestore.collection('users').doc(studentId), {
      'teacherId': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.delete(
      _firestore.collection('teacherStudentSummaries').doc(studentId),
    );
    await batch.commit();
  }

  Future<void> sendDirectMessage({
    required String studentId,
    required String subject,
    required String message,
    String? practiceQuestion,
  }) async {
    final teacherId = currentTeacherId;
    final document = _firestore.collection('teacherMessages').doc();
    final notification = _firestore.collection('notifications').doc();
    final batch = _firestore.batch();
    batch.set(document, {
      'teacherId': teacherId,
      'studentId': studentId,
      'subject': subject.trim(),
      'message': message.trim(),
      'practiceQuestion': practiceQuestion?.trim(),
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(notification, {
      'userId': studentId,
      'type': 'teacher_message',
      'title': subject.trim().isEmpty ? 'Message from your teacher' : subject,
      'message': message.trim(),
      'relatedMessageId': document.id,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> markHelpRequestViewed(String requestId) async {
    final document =
        _firestore.collection('helpRequests').doc(requestId);
    final current = await document.get();
    if (!current.exists) return;
    final status = HelpRequestStatusX.fromValue(current.data()?['status']);
    if (status == HelpRequestStatus.pending) {
      await document.update({
        'status': HelpRequestStatus.viewed.value,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> respondToHelpRequest({
    required TeacherHelpRequest request,
    required String message,
    String? practiceQuestion,
  }) async {
    final teacherId = currentTeacherId;
    final requestRef =
        _firestore.collection('helpRequests').doc(request.id);
    final messageRef = requestRef.collection('messages').doc();
    final directMessageRef = _firestore.collection('teacherMessages').doc();
    final notificationRef = _firestore.collection('notifications').doc();

    final batch = _firestore.batch();
    batch.set(messageRef, {
      'senderId': teacherId,
      'senderRole': 'teacher',
      'message': message.trim(),
      'practiceQuestion': practiceQuestion?.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(requestRef, {
      'status': HelpRequestStatus.responded.value,
      'respondedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(directMessageRef, {
      'teacherId': teacherId,
      'studentId': request.studentId,
      'subject': 'Help response: ${request.conceptName}',
      'message': message.trim(),
      'practiceQuestion': practiceQuestion?.trim(),
      'helpRequestId': request.id,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(notificationRef, {
      'userId': request.studentId,
      'type': 'teacher_response',
      'title': 'Teacher response received',
      'message': 'Your teacher responded about ${request.conceptName}.',
      'relatedHelpRequestId': request.id,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> markHelpRequestResolved(String requestId) async {
    await _firestore.collection('helpRequests').doc(requestId).update({
      'status': HelpRequestStatus.resolved.value,
      'resolvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> createStudentHelpRequest({
    required String conceptName,
    required String studentMessage,
    String? materialId,
    String? sessionId,
    String? questionId,
    String questionText = '',
    String studentAnswer = '',
    String correctAnswer = '',
    String errorType = '',
    int hintsUsed = 0,
    double sessionScore = 0,
  }) async {
    final student = _auth.currentUser;
    if (student == null) throw StateError('Student is not signed in.');
    final userDoc =
        await _firestore.collection('users').doc(student.uid).get();
    final data = userDoc.data() ?? const <String, dynamic>{};
    final teacherId = data['teacherId']?.toString();
    if (teacherId == null || teacherId.isEmpty) {
      throw StateError('No teacher is assigned to this student yet.');
    }

    await _firestore.collection('helpRequests').add({
      'studentId': student.uid,
      'teacherId': teacherId,
      'studentName': data['displayName'] ??
          student.displayName ??
          student.email ??
          'Student',
      'conceptName': conceptName,
      'materialId': materialId,
      'sessionId': sessionId,
      'questionId': questionId,
      'questionText': questionText,
      'studentAnswer': studentAnswer,
      'correctAnswer': correctAnswer,
      'errorType': errorType,
      'hintsUsed': hintsUsed,
      'sessionScore': sessionScore,
      'studentMessage': studentMessage.trim(),
      'status': HelpRequestStatus.pending.value,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
