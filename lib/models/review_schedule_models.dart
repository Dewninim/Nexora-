import 'package:cloud_firestore/cloud_firestore.dart';

enum ReviewPriority { urgent, reviewSoon, safe }

enum ReviewStatus {
  scheduled,
  available,
  completed,
  missed,
  rescheduled,
  cancelled,
}

extension ReviewPriorityX on ReviewPriority {
  String get value {
    switch (this) {
      case ReviewPriority.urgent:
        return 'urgent';
      case ReviewPriority.reviewSoon:
        return 'reviewSoon';
      case ReviewPriority.safe:
        return 'safe';
    }
  }

  String get label {
    switch (this) {
      case ReviewPriority.urgent:
        return 'Urgent';
      case ReviewPriority.reviewSoon:
        return 'Review soon';
      case ReviewPriority.safe:
        return 'Safe';
    }
  }

  static ReviewPriority fromValue(Object? value) {
    switch (value?.toString()) {
      case 'urgent':
        return ReviewPriority.urgent;
      case 'reviewSoon':
      case 'review_soon':
        return ReviewPriority.reviewSoon;
      default:
        return ReviewPriority.safe;
    }
  }
}

extension ReviewStatusX on ReviewStatus {
  String get value => name;

  String get label {
    switch (this) {
      case ReviewStatus.scheduled:
        return 'Scheduled';
      case ReviewStatus.available:
        return 'Available';
      case ReviewStatus.completed:
        return 'Completed';
      case ReviewStatus.missed:
        return 'Missed';
      case ReviewStatus.rescheduled:
        return 'Rescheduled';
      case ReviewStatus.cancelled:
        return 'Cancelled';
    }
  }

  static ReviewStatus fromValue(Object? value) {
    final raw = value?.toString();
    return ReviewStatus.values.firstWhere(
      (item) => item.name == raw,
      orElse: () => ReviewStatus.scheduled,
    );
  }
}

DateTime? firestoreDate(Object? value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

class ReviewSchedule {
  final String id;
  final String studentId;
  final String? teacherId;
  final String? materialId;
  final String? conceptId;
  final String conceptName;
  final String? sourceSessionId;
  final int sessionNumber;
  final double masteryScore;
  final double memoryStrength;
  final double reviewThreshold;
  final double predictedRetention;
  final DateTime scheduledAt;
  final DateTime? reminderAt;
  final int durationMinutes;
  final ReviewPriority priority;
  final ReviewStatus status;
  final String reason;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;

  const ReviewSchedule({
    required this.id,
    required this.studentId,
    required this.conceptName,
    required this.scheduledAt,
    this.teacherId,
    this.materialId,
    this.conceptId,
    this.sourceSessionId,
    this.sessionNumber = 1,
    this.masteryScore = 0,
    this.memoryStrength = 0,
    this.reviewThreshold = 0.8,
    this.predictedRetention = 0.8,
    this.reminderAt,
    this.durationMinutes = 30,
    this.priority = ReviewPriority.reviewSoon,
    this.status = ReviewStatus.scheduled,
    this.reason = '',
    this.createdAt,
    this.updatedAt,
    this.completedAt,
  });

  bool get isOverdue {
    final active = status == ReviewStatus.scheduled ||
        status == ReviewStatus.available ||
        status == ReviewStatus.rescheduled;
    return active && scheduledAt.isBefore(DateTime.now());
  }

  bool get canStart {
    return status == ReviewStatus.available || isOverdue;
  }

  Duration get timeUntilReview => scheduledAt.difference(DateTime.now());

  factory ReviewSchedule.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return ReviewSchedule.fromMap(document.id, data);
  }

  factory ReviewSchedule.fromMap(String id, Map<String, dynamic> data) {
    final scheduled = firestoreDate(data['scheduledAt']) ?? DateTime.now();
    return ReviewSchedule(
      id: id,
      studentId: data['studentId']?.toString() ?? '',
      teacherId: data['teacherId']?.toString(),
      materialId: data['materialId']?.toString(),
      conceptId: data['conceptId']?.toString(),
      conceptName: data['conceptName']?.toString() ?? 'Mathematics Review',
      sourceSessionId: data['sourceSessionId']?.toString(),
      sessionNumber: (data['sessionNumber'] as num?)?.toInt() ?? 1,
      masteryScore: (data['masteryScore'] as num?)?.toDouble() ?? 0,
      memoryStrength: (data['memoryStrength'] as num?)?.toDouble() ?? 0,
      reviewThreshold: (data['reviewThreshold'] as num?)?.toDouble() ?? 0.8,
      predictedRetention:
          (data['predictedRetention'] as num?)?.toDouble() ?? 0.8,
      scheduledAt: scheduled,
      reminderAt: firestoreDate(data['reminderAt']),
      durationMinutes: (data['durationMinutes'] as num?)?.toInt() ?? 30,
      priority: ReviewPriorityX.fromValue(data['priority']),
      status: ReviewStatusX.fromValue(data['status']),
      reason: data['reason']?.toString() ?? '',
      createdAt: firestoreDate(data['createdAt']),
      updatedAt: firestoreDate(data['updatedAt']),
      completedAt: firestoreDate(data['completedAt']),
    );
  }

  Map<String, dynamic> toFirestore({bool includeId = false}) {
    return {
      if (includeId) 'id': id,
      'studentId': studentId,
      'teacherId': teacherId,
      'materialId': materialId,
      'conceptId': conceptId,
      'conceptName': conceptName,
      'sourceSessionId': sourceSessionId,
      'sessionNumber': sessionNumber,
      'masteryScore': masteryScore,
      'memoryStrength': memoryStrength,
      'reviewThreshold': reviewThreshold,
      'predictedRetention': predictedRetention,
      'scheduledAt': Timestamp.fromDate(scheduledAt),
      'reminderAt': reminderAt == null ? null : Timestamp.fromDate(reminderAt!),
      'durationMinutes': durationMinutes,
      'priority': priority.value,
      'status': status.value,
      'reason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
      if (createdAt == null) 'createdAt': FieldValue.serverTimestamp(),
      if (completedAt != null) 'completedAt': Timestamp.fromDate(completedAt!),
    };
  }

  ReviewSchedule copyWith({
    String? teacherId,
    String? conceptName,
    DateTime? scheduledAt,
    DateTime? reminderAt,
    int? durationMinutes,
    ReviewPriority? priority,
    ReviewStatus? status,
    String? reason,
    DateTime? completedAt,
  }) {
    return ReviewSchedule(
      id: id,
      studentId: studentId,
      teacherId: teacherId ?? this.teacherId,
      materialId: materialId,
      conceptId: conceptId,
      conceptName: conceptName ?? this.conceptName,
      sourceSessionId: sourceSessionId,
      sessionNumber: sessionNumber,
      masteryScore: masteryScore,
      memoryStrength: memoryStrength,
      reviewThreshold: reviewThreshold,
      predictedRetention: predictedRetention,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      reminderAt: reminderAt ?? this.reminderAt,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      reason: reason ?? this.reason,
      createdAt: createdAt,
      updatedAt: updatedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}
