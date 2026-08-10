import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/student_learning_models.dart';
abstract class StudentLearningService {
  Future<StudentDashboardData> getDashboard(String studentId);

  Future<AiFeedbackData> getFeedbackForConcept({
    required String studentId,
    required String feedbackId,
  });

  Future<FeedbackReport> buildFeedbackReport({
    required String studentId,
    required String feedbackId,
  });
}

/// Real implementation — every field is computed from the Flask/Mongo
/// backend (GET /user/<uid>/analytics, GET /user/<uid>/materials) and the
/// signed-in Firebase user, with unread notification count read from
/// Firestore. Replaces the old FirestoreStudentLearningService, which just
/// cached MockStudentLearningService's hand-authored numbers on first load.
class BackendStudentLearningService implements StudentLearningService {
  final http.Client _client;
  final FirebaseFirestore _firestore;

  BackendStudentLearningService({http.Client? client, FirebaseFirestore? firestore})
      : _client = client ?? http.Client(),
        _firestore = firestore ?? FirebaseFirestore.instance;

  @override
  Future<StudentDashboardData> getDashboard(String studentId) async {
    final analyticsRes = await _client
        .get(Uri.parse('$kApiBaseUrl/user/$studentId/analytics'))
        .timeout(const Duration(seconds: 20));
    if (analyticsRes.statusCode != 200) {
      throw Exception('Could not load analytics (${analyticsRes.statusCode})');
    }
    final analytics = jsonDecode(analyticsRes.body) as Map<String, dynamic>;

    List<Map<String, dynamic>> materials = const [];
    try {
      final materialsRes = await _client
          .get(Uri.parse('$kApiBaseUrl/user/$studentId/materials'))
          .timeout(const Duration(seconds: 20));
      if (materialsRes.statusCode == 200) {
        final body = jsonDecode(materialsRes.body) as Map<String, dynamic>;
        materials = (body['materials'] as List? ?? const [])
            .cast<Map<String, dynamic>>();
      }
    } catch (_) {
      // Dashboard still renders with analytics-only data if this fails.
    }

    final trend = (analytics['masteryProgressTrend'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(RetentionPoint.fromJson)
        .toList();
    final topics = (analytics['topicMastery'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(TopicMastery.fromJson)
        .toList();

    final overallMastery = analytics['overallMasteryPercent'] as int? ?? 0;
    final problemsSolved = analytics['problemsSolved'] as int? ?? 0;
    final studyTimeHours = (analytics['studyTimeHours'] as num?)?.toDouble() ?? 0;
    final streak = analytics['currentStreakDays'] as int? ?? 0;

    final retentionPercent =
        trend.isNotEmpty ? trend.last.retentionPercent.round() : overallMastery;
    final retentionDeltaLabel = trend.length >= 2
        ? _deltaLabel(trend.last.retentionPercent - trend[trend.length - 2].retentionPercent)
        : (trend.length == 1 ? 'First session recorded' : 'No sessions yet');

    final now = DateTime.now();
    final reviewCandidates = materials
        .map(_ReviewCandidate.fromMaterialJson)
        .whereType<_ReviewCandidate>()
        .toList()
      ..sort((a, b) => a.urgencyRank(now).compareTo(b.urgencyRank(now)));

    final recommended = <RecommendedConcept>[
      for (final entry in reviewCandidates.take(2).indexed)
        RecommendedConcept(
          id: entry.$2.materialId,
          courseId: entry.$2.materialId,
          category: 'Mathematics',
          title: entry.$2.title,
          retentionNote: entry.$2.retentionNote(now),
          actionLabel: 'Review Concept',
          feedbackId: entry.$2.materialId,
          visualStyle:
              entry.$1.isEven ? ConceptVisualStyle.mathematics : ConceptVisualStyle.neuroscience,
        ),
    ];

    final quickCheck = reviewCandidates.isNotEmpty
        ? QuizPrompt(
            id: reviewCandidates.first.materialId,
            tag: 'QUICK CHECK',
            title: reviewCandidates.first.title,
            subtitle: reviewCandidates.first.retentionNote(now),
            actionLabel: 'Go to Review Schedule',
          )
        : const QuizPrompt(
            id: 'upload-first',
            tag: 'GET STARTED',
            title: 'Upload your first material',
            subtitle: 'Add a PDF to generate your first personalised session.',
            actionLabel: 'Upload Material',
          );

    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName?.trim().split(RegExp(r'\s+')).first ??
        user?.email?.split('@').first ??
        'Student';

    return StudentDashboardData(
      studentId: studentId,
      displayName: displayName,
      notificationCount: await _unreadNotificationCount(studentId),
      currentStreakDays: streak,
      retentionPercent: retentionPercent,
      retentionDeltaLabel: retentionDeltaLabel,
      retentionTrend: trend,
      keyMetrics: [
        DashboardKeyMetric(
          id: 'materials',
          label: 'Materials Uploaded',
          value: '${materials.length}',
          tone: 'blue',
        ),
        DashboardKeyMetric(
          id: 'concepts',
          label: 'Problems Solved',
          value: '$problemsSolved',
          tone: 'green',
        ),
        DashboardKeyMetric(
          id: 'nextReview',
          label: 'Next Review',
          value: reviewCandidates.isEmpty ? 'None scheduled' : reviewCandidates.first.dueLabel(now),
          tone: 'orange',
        ),
      ],
      recommendedConcepts: recommended,
      quickCheck: quickCheck,
      progressStats: [
        ProgressStat(
          id: 'modules',
          label: 'Materials Tracked',
          value: '${materials.length}',
          tone: 'blue',
        ),
        ProgressStat(
          id: 'studyTime',
          label: 'Study Time',
          value: '${studyTimeHours.toStringAsFixed(1)} hrs',
          tone: 'green',
        ),
        ProgressStat(
          id: 'mastery',
          label: 'Overall Mastery',
          value: '$overallMastery%',
          tone: 'purple',
        ),
      ],
      overallMasteryPercent: overallMastery,
      problemsSolved: problemsSolved,
      studyTimeHours: studyTimeHours,
      masteryProgressTrend: trend,
      topicMastery: topics,
    );
  }

  @override
  Future<AiFeedbackData> getFeedbackForConcept({
    required String studentId,
    required String feedbackId,
  }) {
    // Real per-session AI feedback is served by ExplainableAiFeedbackPage's
    // own session browser (GET /user/<uid>/sessions + GET /session/<sid>),
    // not by this generic single-concept lookup — there is no equivalent
    // backend concept to fetch here, so callers should not reach this path
    // for a student with real session history.
    throw StateError('No AI feedback is available yet — complete a learning session first.');
  }

  @override
  Future<FeedbackReport> buildFeedbackReport({
    required String studentId,
    required String feedbackId,
  }) {
    throw StateError('No AI feedback is available yet — complete a learning session first.');
  }

  Future<int> _unreadNotificationCount(String studentId) async {
    try {
      final snapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: studentId)
          .where('isRead', isEqualTo: false)
          .get();
      return snapshot.docs.length;
    } catch (_) {
      return 0;
    }
  }

  static String _deltaLabel(double diff) {
    if (diff > 0.4) return '+${diff.round()}% vs last session';
    if (diff < -0.4) return '${diff.round()}% vs last session';
    return 'Steady vs last session';
  }
}

class _ReviewCandidate {
  final String materialId;
  final String title;
  final DateTime? nextReviewDate;

  _ReviewCandidate({
    required this.materialId,
    required this.title,
    required this.nextReviewDate,
  });

  static _ReviewCandidate? fromMaterialJson(Map<String, dynamic> json) {
    final materialId = json['material_id'] as String?;
    if (materialId == null) return null;
    final latest = json['latest_session'] as Map<String, dynamic>?;
    DateTime? nextReview;
    final raw = latest?['next_review_date'] as String?;
    if (raw != null) {
      try {
        nextReview = DateTime.parse(raw);
      } catch (_) {}
    }
    return _ReviewCandidate(
      materialId: materialId,
      title: (json['filename'] as String? ?? 'Untitled.pdf').replaceAll('.pdf', ''),
      nextReviewDate: nextReview,
    );
  }

  /// Lower = more urgent. Overdue/soonest reviews sort first; materials with
  /// no scheduled review yet (never studied) sort last.
  double urgencyRank(DateTime now) {
    if (nextReviewDate == null) return double.infinity;
    return nextReviewDate!.difference(now).inMinutes.toDouble();
  }

  String retentionNote(DateTime now) {
    if (nextReviewDate == null) return 'Start a session to build a review schedule.';
    final days = nextReviewDate!.difference(now).inDays;
    if (days < 0) return 'Review overdue — retention is dropping.';
    if (days == 0) return 'Review due today.';
    return 'Review due in $days day${days == 1 ? '' : 's'}.';
  }

  String dueLabel(DateTime now) {
    if (nextReviewDate == null) return 'Not scheduled';
    final diff = nextReviewDate!.difference(now);
    if (diff.isNegative) return 'Overdue';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}
