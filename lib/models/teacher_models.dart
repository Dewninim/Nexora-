import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'review_schedule_models.dart';

enum TeacherNavSection { dashboard, helpRequests, settings }

enum StudentRiskLevel { urgent, reviewSoon, safe }

extension StudentRiskLevelX on StudentRiskLevel {
  String get value {
    switch (this) {
      case StudentRiskLevel.urgent:
        return 'urgent';
      case StudentRiskLevel.reviewSoon:
        return 'reviewSoon';
      case StudentRiskLevel.safe:
        return 'safe';
    }
  }

  String get label {
    switch (this) {
      case StudentRiskLevel.urgent:
        return 'Urgent';
      case StudentRiskLevel.reviewSoon:
        return 'Review Soon';
      case StudentRiskLevel.safe:
        return 'Safe';
    }
  }

  Color get chipColor {
    switch (this) {
      case StudentRiskLevel.urgent:
        return const Color(0xFFFF6B6B);
      case StudentRiskLevel.reviewSoon:
        return const Color(0xFFFFD166);
      case StudentRiskLevel.safe:
        return const Color(0xFF36B37E);
    }
  }

  static StudentRiskLevel fromValue(Object? value) {
    switch (value?.toString()) {
      case 'urgent':
      case 'high':
        return StudentRiskLevel.urgent;
      case 'reviewSoon':
      case 'review_soon':
      case 'medium':
        return StudentRiskLevel.reviewSoon;
      default:
        return StudentRiskLevel.safe;
    }
  }
}

class TeacherStudentSummary {
  final String studentId;
  final String teacherId;
  final String displayName;
  final String email;
  final String currentTopic;
  final int masteryPercent;
  final int retentionPercent;
  final int overdueReviews;
  final int pendingHelpRequests;
  final int completedReviews;
  final DateTime? nextReviewAt;
  final DateTime? lastActiveAt;
  final StudentRiskLevel riskLevel;
  final List<String> riskReasons;

  const TeacherStudentSummary({
    required this.studentId,
    required this.teacherId,
    required this.displayName,
    required this.email,
    required this.currentTopic,
    required this.masteryPercent,
    required this.retentionPercent,
    required this.overdueReviews,
    required this.pendingHelpRequests,
    required this.completedReviews,
    required this.riskLevel,
    this.nextReviewAt,
    this.lastActiveAt,
    this.riskReasons = const [],
  });

  factory TeacherStudentSummary.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return TeacherStudentSummary.fromMap(document.id, data);
  }

  factory TeacherStudentSummary.fromMap(
    String id,
    Map<String, dynamic> data,
  ) {
    final mastery = (data['masteryPercent'] as num?)?.toInt() ?? 0;
    final retention = (data['retentionPercent'] as num?)?.toInt() ?? 0;
    final overdue = (data['overdueReviews'] as num?)?.toInt() ?? 0;
    final help = (data['pendingHelpRequests'] as num?)?.toInt() ?? 0;
    final riskReasons = (data['riskReasons'] as List?)
            ?.map((item) => item.toString())
            .toList(growable: false) ??
        const <String>[];

    final computedRisk = _calculateRisk(
      mastery: mastery,
      retention: retention,
      overdue: overdue,
      pendingHelp: help,
      explicit: data['riskLevel'],
    );

    return TeacherStudentSummary(
      studentId: data['studentId']?.toString() ?? id,
      teacherId: data['teacherId']?.toString() ?? '',
      displayName: data['displayName']?.toString() ?? 'Student',
      email: data['email']?.toString() ?? '',
      currentTopic: data['currentTopic']?.toString() ?? 'No active topic',
      masteryPercent: mastery,
      retentionPercent: retention,
      overdueReviews: overdue,
      pendingHelpRequests: help,
      completedReviews: (data['completedReviews'] as num?)?.toInt() ?? 0,
      nextReviewAt: firestoreDate(data['nextReviewAt']),
      lastActiveAt: firestoreDate(data['lastActiveAt']),
      riskLevel: computedRisk,
      riskReasons: riskReasons,
    );
  }

  static StudentRiskLevel _calculateRisk({
    required int mastery,
    required int retention,
    required int overdue,
    required int pendingHelp,
    Object? explicit,
  }) {
    if (explicit != null) return StudentRiskLevelX.fromValue(explicit);
    if (mastery < 50 || retention < 40 || overdue >= 2) {
      return StudentRiskLevel.urgent;
    }
    if (mastery < 70 || retention < 65 || overdue == 1 || pendingHelp > 0) {
      return StudentRiskLevel.reviewSoon;
    }
    return StudentRiskLevel.safe;
  }
}

enum HelpRequestStatus { pending, viewed, responded, resolved }

extension HelpRequestStatusX on HelpRequestStatus {
  String get value => name;

  String get label {
    switch (this) {
      case HelpRequestStatus.pending:
        return 'Pending';
      case HelpRequestStatus.viewed:
        return 'Viewed';
      case HelpRequestStatus.responded:
        return 'Responded';
      case HelpRequestStatus.resolved:
        return 'Resolved';
    }
  }

  static HelpRequestStatus fromValue(Object? value) {
    final raw = value?.toString();
    return HelpRequestStatus.values.firstWhere(
      (status) => status.name == raw,
      orElse: () => HelpRequestStatus.pending,
    );
  }
}

class TeacherHelpRequest {
  final String id;
  final String studentId;
  final String teacherId;
  final String studentName;
  final String conceptName;
  final String? materialId;
  final String? sessionId;
  final String? questionId;
  final String questionText;
  final String studentAnswer;
  final String correctAnswer;
  final String errorType;
  final int hintsUsed;
  final double sessionScore;
  final String studentMessage;
  final HelpRequestStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const TeacherHelpRequest({
    required this.id,
    required this.studentId,
    required this.teacherId,
    required this.studentName,
    required this.conceptName,
    required this.questionText,
    required this.studentAnswer,
    required this.correctAnswer,
    required this.errorType,
    required this.hintsUsed,
    required this.sessionScore,
    required this.studentMessage,
    required this.status,
    this.materialId,
    this.sessionId,
    this.questionId,
    this.createdAt,
    this.updatedAt,
  });

  factory TeacherHelpRequest.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return TeacherHelpRequest(
      id: document.id,
      studentId: data['studentId']?.toString() ?? '',
      teacherId: data['teacherId']?.toString() ?? '',
      studentName: data['studentName']?.toString() ?? 'Student',
      conceptName: data['conceptName']?.toString() ?? 'Mathematics',
      materialId: data['materialId']?.toString(),
      sessionId: data['sessionId']?.toString(),
      questionId: data['questionId']?.toString(),
      questionText: data['questionText']?.toString() ?? '',
      studentAnswer: data['studentAnswer']?.toString() ?? '',
      correctAnswer: data['correctAnswer']?.toString() ?? '',
      errorType: data['errorType']?.toString() ?? 'Not identified',
      hintsUsed: (data['hintsUsed'] as num?)?.toInt() ?? 0,
      sessionScore: (data['sessionScore'] as num?)?.toDouble() ?? 0,
      studentMessage: data['studentMessage']?.toString() ?? '',
      status: HelpRequestStatusX.fromValue(data['status']),
      createdAt: firestoreDate(data['createdAt']),
      updatedAt: firestoreDate(data['updatedAt']),
    );
  }
}

class TeacherMessage {
  final String id;
  final String teacherId;
  final String studentId;
  final String subject;
  final String message;
  final String? practiceQuestion;
  final String? helpRequestId;
  final bool isRead;
  final DateTime? createdAt;

  const TeacherMessage({
    required this.id,
    required this.teacherId,
    required this.studentId,
    required this.subject,
    required this.message,
    required this.isRead,
    this.practiceQuestion,
    this.helpRequestId,
    this.createdAt,
  });
}
