import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/review_schedule_models.dart';

class ReviewScheduleService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  ReviewScheduleService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _schedules =>
      _firestore.collection('reviewSchedules');

  CollectionReference<Map<String, dynamic>> get _notifications =>
      _firestore.collection('notifications');

  Stream<List<ReviewSchedule>> watchStudentSchedules(String studentId) {
    return _schedules
        .where('studentId', isEqualTo: studentId)
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs
          .map(ReviewSchedule.fromDocument)
          .toList(growable: false);
      items.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
      return items;
    });
  }

  Stream<int> watchActiveCount(String studentId) {
    return watchStudentSchedules(studentId).map(
      (items) => items
          .where(
            (item) => item.status == ReviewStatus.scheduled ||
                item.status == ReviewStatus.available ||
                item.status == ReviewStatus.rescheduled,
          )
          .length,
    );
  }

  Future<ReviewSchedule?> getById(String scheduleId) async {
    final document = await _schedules.doc(scheduleId).get();
    if (!document.exists) return null;
    return ReviewSchedule.fromDocument(document);
  }

  /// Converts the Flask `/session/<id>/submit` response into a persistent
  /// Firestore review schedule. It uses a deterministic document id, so a
  /// retry does not create duplicate schedules.
  Future<ReviewSchedule> saveFromSessionResult({
    required Map<String, dynamic> result,
    required String fileName,
    DateTime? preferredTime,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw StateError('A signed-in student is required to save a review.');
    }

    final studentId = currentUser.uid;
    final userDoc = await _firestore.collection('users').doc(studentId).get();
    final userData = userDoc.data() ?? const <String, dynamic>{};
    final teacherId = userData['teacherId']?.toString();

    final sessionId = result['session_id']?.toString() ?? '';
    final materialId = result['material_id']?.toString();
    final sessionNumber = (result['session_number'] as num?)?.toInt() ?? 1;
    final profile = (result['learner_profile'] as Map?)
            ?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final curve = (result['forgetting_curve'] as Map?)
            ?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    final score = ((profile['avg_score'] ?? result['score']) as num?)
            ?.toDouble() ??
        0;
    final masteryScore = score <= 1 ? score * 100 : score;
    final memoryStrength =
        (curve['stability'] as num?)?.toDouble() ?? 1.0;
    final reviewThreshold =
        (curve['threshold'] as num?)?.toDouble() ?? 0.8;
    final daysUntilReview =
        (result['next_review_days'] as num?)?.toInt() ?? 1;

    final scheduledAt = _parseReviewDate(
      result['next_review_date']?.toString(),
      daysUntilReview,
      preferredTime,
    );

    final conceptName = _extractConceptName(result, fileName);
    final priority = _priorityFor(
      masteryScore: masteryScore,
      reviewDays: daysUntilReview,
      mistakeRate: (profile['mistake_rate'] as num?)?.toDouble() ?? 0,
    );
    final reason = _buildReason(
      conceptName: conceptName,
      masteryScore: masteryScore,
      daysUntilReview: daysUntilReview,
      profile: profile,
    );

    final idBase = sessionId.isNotEmpty
        ? '${studentId}_$sessionId'
        : '${studentId}_${materialId ?? 'material'}_$sessionNumber';
    final documentId = _safeDocumentId(idBase);

    final schedule = ReviewSchedule(
      id: documentId,
      studentId: studentId,
      teacherId: teacherId,
      materialId: materialId,
      conceptId: _slug(conceptName),
      conceptName: conceptName,
      sourceSessionId: sessionId.isEmpty ? null : sessionId,
      sessionNumber: sessionNumber,
      masteryScore: masteryScore.clamp(0, 100).toDouble(),
      memoryStrength: memoryStrength,
      reviewThreshold: reviewThreshold,
      predictedRetention: reviewThreshold,
      scheduledAt: scheduledAt,
      reminderAt: scheduledAt.subtract(const Duration(hours: 2)),
      durationMinutes: _durationFor(priority),
      priority: priority,
      status: scheduledAt.isAfter(DateTime.now())
          ? ReviewStatus.scheduled
          : ReviewStatus.available,
      reason: reason,
    );

    final batch = _firestore.batch();
    batch.set(
      _schedules.doc(documentId),
      schedule.toFirestore(),
      SetOptions(merge: true),
    );

    final summaryRef =
        _firestore.collection('teacherStudentSummaries').doc(studentId);
    batch.set(
      summaryRef,
      {
        'studentId': studentId,
        'teacherId': teacherId,
        'displayName': userData['displayName'] ??
            currentUser.displayName ??
            currentUser.email ??
            'Student',
        'email': userData['email'] ?? currentUser.email,
        'currentTopic': conceptName,
        'masteryPercent': masteryScore.round(),
        'retentionPercent': (reviewThreshold * 100).round(),
        'nextReviewAt': Timestamp.fromDate(scheduledAt),
        'lastActiveAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await batch.commit();
    return schedule;
  }

  Future<void> saveTimePlan({
    required String scheduleId,
    required DateTime scheduledAt,
    required int durationMinutes,
    DateTime? reminderAt,
  }) async {
    final status = scheduledAt.isAfter(DateTime.now())
        ? ReviewStatus.rescheduled
        : ReviewStatus.available;
    await _schedules.doc(scheduleId).update({
      'scheduledAt': Timestamp.fromDate(scheduledAt),
      'reminderAt': reminderAt == null
          ? Timestamp.fromDate(scheduledAt.subtract(const Duration(hours: 2)))
          : Timestamp.fromDate(reminderAt),
      'durationMinutes': durationMinutes,
      'status': status.value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markCompleted(String scheduleId) async {
    await _schedules.doc(scheduleId).update({
      'status': ReviewStatus.completed.value,
      'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markMissed(String scheduleId) async {
    await _schedules.doc(scheduleId).update({
      'status': ReviewStatus.missed.value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> cancel(String scheduleId) async {
    await _schedules.doc(scheduleId).update({
      'status': ReviewStatus.cancelled.value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> snooze(String scheduleId, Duration duration) async {
    final document = await _schedules.doc(scheduleId).get();
    if (!document.exists) return;
    final schedule = ReviewSchedule.fromDocument(document);
    final next = DateTime.now().add(duration);
    await saveTimePlan(
      scheduleId: scheduleId,
      scheduledAt: next,
      durationMinutes: schedule.durationMinutes,
      reminderAt: next.subtract(const Duration(minutes: 30)),
    );
  }

  Future<ReviewSchedule> createManualSchedule({
    required String studentId,
    required String conceptName,
    required DateTime scheduledAt,
    required int durationMinutes,
    required String reason,
    ReviewPriority priority = ReviewPriority.reviewSoon,
  }) async {
    final teacherId = _auth.currentUser?.uid;
    if (teacherId == null) {
      throw StateError('A signed-in teacher is required.');
    }
    final document = _schedules.doc();
    final schedule = ReviewSchedule(
      id: document.id,
      studentId: studentId,
      teacherId: teacherId,
      conceptId: _slug(conceptName),
      conceptName: conceptName,
      scheduledAt: scheduledAt,
      reminderAt: scheduledAt.subtract(const Duration(hours: 2)),
      durationMinutes: durationMinutes,
      priority: priority,
      status: scheduledAt.isAfter(DateTime.now())
          ? ReviewStatus.scheduled
          : ReviewStatus.available,
      reason: reason,
    );
    await document.set(schedule.toFirestore());
    return schedule;
  }

  Future<void> createInAppNotification({
    required String userId,
    required String title,
    required String message,
    required String type,
    String? relatedScheduleId,
  }) async {
    await _notifications.add({
      'userId': userId,
      'title': title,
      'message': message,
      'type': type,
      'relatedScheduleId': relatedScheduleId,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  DateTime _parseReviewDate(
    String? raw,
    int daysUntilReview,
    DateTime? preferredTime,
  ) {
    DateTime date;
    if (raw != null && raw.trim().isNotEmpty) {
      date = DateTime.tryParse(raw)?.toLocal() ??
          DateTime.now().add(Duration(days: math.max(1, daysUntilReview)));
    } else {
      date = DateTime.now().add(Duration(days: math.max(1, daysUntilReview)));
    }

    final preferred = preferredTime ?? DateTime(2000, 1, 1, 18);
    return DateTime(
      date.year,
      date.month,
      date.day,
      preferred.hour,
      preferred.minute,
    );
  }

  String _extractConceptName(
    Map<String, dynamic> result,
    String fileName,
  ) {
    final results = result['results'];
    if (results is List) {
      final counts = <String, int>{};
      for (final item in results) {
        if (item is! Map) continue;
        final topic = item['topic']?.toString().trim();
        if (topic != null && topic.isNotEmpty) {
          counts[topic] = (counts[topic] ?? 0) + 1;
        }
      }
      if (counts.isNotEmpty) {
        final sorted = counts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        return sorted.first.key;
      }
    }
    return fileName
        .replaceAll(RegExp(r'\.[Pp][Dd][Ff]$'), '')
        .replaceAll('_', ' ')
        .trim();
  }

  ReviewPriority _priorityFor({
    required double masteryScore,
    required int reviewDays,
    required double mistakeRate,
  }) {
    if (masteryScore < 50 || reviewDays <= 1 || mistakeRate >= 0.5) {
      return ReviewPriority.urgent;
    }
    if (masteryScore < 75 || reviewDays <= 3 || mistakeRate >= 0.25) {
      return ReviewPriority.reviewSoon;
    }
    return ReviewPriority.safe;
  }

  int _durationFor(ReviewPriority priority) {
    switch (priority) {
      case ReviewPriority.urgent:
        return 45;
      case ReviewPriority.reviewSoon:
        return 30;
      case ReviewPriority.safe:
        return 20;
    }
  }

  String _buildReason({
    required String conceptName,
    required double masteryScore,
    required int daysUntilReview,
    required Map<String, dynamic> profile,
  }) {
    final mistakes = (profile['mistake_patterns'] as List?)
            ?.map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toList() ??
        const <String>[];
    final hintRate =
        ((profile['hint_usage_rate'] as num?)?.toDouble() ?? 0) * 100;

    final parts = <String>[
      '$conceptName mastery is ${masteryScore.round()}%.',
      'The forgetting-curve engine recommends reviewing in $daysUntilReview day${daysUntilReview == 1 ? '' : 's'}.',
    ];
    if (mistakes.isNotEmpty) {
      parts.add('Frequent weak areas: ${mistakes.join(', ')}.');
    }
    if (hintRate >= 30) {
      parts.add('Hint usage was ${hintRate.round()}%, so extra reinforcement is recommended.');
    }
    return parts.join(' ');
  }

  String _safeDocumentId(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  }

  String _slug(String value) {
    final slug = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'mathematics-review' : slug;
  }
}
