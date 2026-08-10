enum StudentNavSection {
  dashboard,
  uploadMaterial,
  aiFeedback,
  reviewSchedule,
  analytics,
  settings,
}

enum ConceptVisualStyle { mathematics, neuroscience }

class RetentionPoint {
  final String label;
  final double retentionPercent;
  final bool highlighted;

  const RetentionPoint({
    required this.label,
    required this.retentionPercent,
    this.highlighted = false,
  });

  factory RetentionPoint.fromJson(Map<String, dynamic> json) {
    return RetentionPoint(
      label: json['label'] as String,
      retentionPercent: (json['retentionPercent'] as num).toDouble(),
      highlighted: json['highlighted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'retentionPercent': retentionPercent,
      'highlighted': highlighted,
    };
  }
}

class DashboardKeyMetric {
  final String id;
  final String label;
  final String value;
  final String tone;

  const DashboardKeyMetric({
    required this.id,
    required this.label,
    required this.value,
    required this.tone,
  });

  factory DashboardKeyMetric.fromJson(Map<String, dynamic> json) {
    return DashboardKeyMetric(
      id: json['id'] as String,
      label: json['label'] as String,
      value: json['value'] as String,
      tone: json['tone'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'label': label, 'value': value, 'tone': tone};
  }
}

class RecommendedConcept {
  final String id;
  final String courseId;
  final String category;
  final String title;
  final String retentionNote;
  final String actionLabel;
  final String feedbackId;
  final ConceptVisualStyle visualStyle;

  const RecommendedConcept({
    required this.id,
    required this.courseId,
    required this.category,
    required this.title,
    required this.retentionNote,
    required this.actionLabel,
    required this.feedbackId,
    required this.visualStyle,
  });

  factory RecommendedConcept.fromJson(Map<String, dynamic> json) {
    return RecommendedConcept(
      id: json['id'] as String,
      courseId: json['courseId'] as String,
      category: json['category'] as String,
      title: json['title'] as String,
      retentionNote: json['retentionNote'] as String,
      actionLabel: json['actionLabel'] as String,
      feedbackId: json['feedbackId'] as String,
      visualStyle: ConceptVisualStyle.values.byName(
        json['visualStyle'] as String,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'courseId': courseId,
      'category': category,
      'title': title,
      'retentionNote': retentionNote,
      'actionLabel': actionLabel,
      'feedbackId': feedbackId,
      'visualStyle': visualStyle.name,
    };
  }
}

class QuizPrompt {
  final String id;
  final String tag;
  final String title;
  final String subtitle;
  final String actionLabel;

  const QuizPrompt({
    required this.id,
    required this.tag,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
  });

  factory QuizPrompt.fromJson(Map<String, dynamic> json) {
    return QuizPrompt(
      id: json['id'] as String,
      tag: json['tag'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String,
      actionLabel: json['actionLabel'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tag': tag,
      'title': title,
      'subtitle': subtitle,
      'actionLabel': actionLabel,
    };
  }
}

class ProgressStat {
  final String id;
  final String label;
  final String value;
  final String tone;

  const ProgressStat({
    required this.id,
    required this.label,
    required this.value,
    required this.tone,
  });

  factory ProgressStat.fromJson(Map<String, dynamic> json) {
    return ProgressStat(
      id: json['id'] as String,
      label: json['label'] as String,
      value: json['value'] as String,
      tone: json['tone'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'label': label, 'value': value, 'tone': tone};
  }
}

class TopicMastery {
  final String topic;
  final int masteryPercent;
  final String trend; // 'Improving' | 'Stable' | 'Declining'

  const TopicMastery({
    required this.topic,
    required this.masteryPercent,
    required this.trend,
  });

  factory TopicMastery.fromJson(Map<String, dynamic> json) {
    return TopicMastery(
      topic: json['topic'] as String,
      masteryPercent: json['masteryPercent'] as int,
      trend: json['trend'] as String? ?? 'Stable',
    );
  }

  Map<String, dynamic> toJson() {
    return {'topic': topic, 'masteryPercent': masteryPercent, 'trend': trend};
  }
}

class StudentDashboardData {
  final String studentId;
  final String displayName;
  final int notificationCount;
  final int currentStreakDays;
  final int retentionPercent;
  final String retentionDeltaLabel;
  final List<RetentionPoint> retentionTrend;
  final List<DashboardKeyMetric> keyMetrics;
  final List<RecommendedConcept> recommendedConcepts;
  final QuizPrompt quickCheck;
  final List<ProgressStat> progressStats;
  final int overallMasteryPercent;
  final int problemsSolved;
  final double studyTimeHours;
  final List<RetentionPoint> masteryProgressTrend;
  final List<TopicMastery> topicMastery;

  const StudentDashboardData({
    required this.studentId,
    required this.displayName,
    required this.notificationCount,
    required this.currentStreakDays,
    required this.retentionPercent,
    required this.retentionDeltaLabel,
    required this.retentionTrend,
    required this.keyMetrics,
    required this.recommendedConcepts,
    required this.quickCheck,
    required this.progressStats,
    this.overallMasteryPercent = 0,
    this.problemsSolved = 0,
    this.studyTimeHours = 0,
    this.masteryProgressTrend = const [],
    this.topicMastery = const [],
  });

  factory StudentDashboardData.fromJson(Map<String, dynamic> json) {
    return StudentDashboardData(
      studentId: json['studentId'] as String,
      displayName: json['displayName'] as String,
      notificationCount: json['notificationCount'] as int,
      currentStreakDays: json['currentStreakDays'] as int,
      retentionPercent: json['retentionPercent'] as int,
      retentionDeltaLabel: json['retentionDeltaLabel'] as String,
      retentionTrend: (json['retentionTrend'] as List<dynamic>)
          .map((item) => RetentionPoint.fromJson(item as Map<String, dynamic>))
          .toList(),
      keyMetrics: (json['keyMetrics'] as List<dynamic>)
          .map(
            (item) => DashboardKeyMetric.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      recommendedConcepts: (json['recommendedConcepts'] as List<dynamic>)
          .map(
            (item) => RecommendedConcept.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      quickCheck: QuizPrompt.fromJson(
        json['quickCheck'] as Map<String, dynamic>,
      ),
      progressStats: (json['progressStats'] as List<dynamic>)
          .map((item) => ProgressStat.fromJson(item as Map<String, dynamic>))
          .toList(),
      // Newer analytics fields — default gracefully so existing Firestore
      // docs (seeded before these existed) don't crash the app.
      overallMasteryPercent: json['overallMasteryPercent'] as int? ?? 0,
      problemsSolved: json['problemsSolved'] as int? ?? 0,
      studyTimeHours: (json['studyTimeHours'] as num?)?.toDouble() ?? 0,
      masteryProgressTrend: (json['masteryProgressTrend'] as List<dynamic>?)
              ?.map(
                (item) => RetentionPoint.fromJson(item as Map<String, dynamic>),
              )
              .toList() ??
          const [],
      topicMastery: (json['topicMastery'] as List<dynamic>?)
              ?.map(
                (item) => TopicMastery.fromJson(item as Map<String, dynamic>),
              )
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'studentId': studentId,
      'displayName': displayName,
      'notificationCount': notificationCount,
      'currentStreakDays': currentStreakDays,
      'retentionPercent': retentionPercent,
      'retentionDeltaLabel': retentionDeltaLabel,
      'retentionTrend': retentionTrend.map((item) => item.toJson()).toList(),
      'keyMetrics': keyMetrics.map((item) => item.toJson()).toList(),
      'recommendedConcepts': recommendedConcepts
          .map((item) => item.toJson())
          .toList(),
      'quickCheck': quickCheck.toJson(),
      'progressStats': progressStats.map((item) => item.toJson()).toList(),
      'overallMasteryPercent': overallMasteryPercent,
      'problemsSolved': problemsSolved,
      'studyTimeHours': studyTimeHours,
      'masteryProgressTrend': masteryProgressTrend
          .map((item) => item.toJson())
          .toList(),
      'topicMastery': topicMastery.map((item) => item.toJson()).toList(),
    };
  }
}

class RetentionCurvePoint {
  final String label;
  final double day;
  final double predictedRetention;
  final double idealRetention;
  final bool isCurrent;

  const RetentionCurvePoint({
    required this.label,
    required this.day,
    required this.predictedRetention,
    required this.idealRetention,
    this.isCurrent = false,
  });

  factory RetentionCurvePoint.fromJson(Map<String, dynamic> json) {
    return RetentionCurvePoint(
      label: json['label'] as String,
      day: (json['day'] as num).toDouble(),
      predictedRetention: (json['predictedRetention'] as num).toDouble(),
      idealRetention: (json['idealRetention'] as num).toDouble(),
      isCurrent: json['isCurrent'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'day': day,
      'predictedRetention': predictedRetention,
      'idealRetention': idealRetention,
      'isCurrent': isCurrent,
    };
  }
}

class QuestionFeedback {
  final String questionId;
  final String questionText;
  final String topic;
  final bool isCorrect;
  final String yourAnswer;
  final String correctAnswer;
  final String xaiText;
  final int hintsUsed;

  const QuestionFeedback({
    required this.questionId,
    required this.questionText,
    required this.topic,
    required this.isCorrect,
    required this.yourAnswer,
    required this.correctAnswer,
    required this.xaiText,
    required this.hintsUsed,
  });

  factory QuestionFeedback.fromJson(Map<String, dynamic> json) {
    return QuestionFeedback(
      questionId: json['questionId'] as String,
      questionText: json['questionText'] as String,
      topic: json['topic'] as String,
      isCorrect: json['isCorrect'] as bool,
      yourAnswer: json['yourAnswer'] as String,
      correctAnswer: json['correctAnswer'] as String,
      xaiText: json['xaiText'] as String,
      hintsUsed: json['hintsUsed'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'questionId': questionId,
      'questionText': questionText,
      'topic': topic,
      'isCorrect': isCorrect,
      'yourAnswer': yourAnswer,
      'correctAnswer': correctAnswer,
      'xaiText': xaiText,
      'hintsUsed': hintsUsed,
    };
  }
}

class ExplanationFactor {
  final String id;
  final String title;
  final String value;
  final String description;
  final String tone;

  const ExplanationFactor({
    required this.id,
    required this.title,
    required this.value,
    required this.description,
    required this.tone,
  });

  factory ExplanationFactor.fromJson(Map<String, dynamic> json) {
    return ExplanationFactor(
      id: json['id'] as String,
      title: json['title'] as String,
      value: json['value'] as String,
      description: json['description'] as String,
      tone: json['tone'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'value': value,
      'description': description,
      'tone': tone,
    };
  }
}

class ReportMetricRow {
  final String metric;
  final String value;
  final String interpretation;
  final String recommendation;

  const ReportMetricRow({
    required this.metric,
    required this.value,
    required this.interpretation,
    required this.recommendation,
  });

  factory ReportMetricRow.fromJson(Map<String, dynamic> json) {
    return ReportMetricRow(
      metric: json['metric'] as String,
      value: json['value'] as String,
      interpretation: json['interpretation'] as String,
      recommendation: json['recommendation'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'metric': metric,
      'value': value,
      'interpretation': interpretation,
      'recommendation': recommendation,
    };
  }
}

class AiFeedbackData {
  final String id;
  final String studentId;
  final String courseTitle;
  final String conceptTitle;
  final String badgeLabel;
  final String headline;
  final String summary;
  final int currentRetentionPercent;
  final int declinePercent;
  final int recoveryRetentionPercent;
  final String retentionDescription;
  final List<RetentionCurvePoint> curve;
  final List<ExplanationFactor> factors;
  final String guidanceTitle;
  final String guidanceBody;
  final List<ReportMetricRow> reportRows;
  final DateTime generatedAt;
  // Real next-review scheduling, and the step-by-step breakdown of how it
  // was calculated (accuracy, hints, memory strength, the study
  // mode/period the student chose at upload time) — see
  // compute_forgetting_curve() in backend/app.py for the source formula.
  final String? nextReviewDate;
  final int? nextReviewDays;
  final List<ExplanationFactor> schedulingFactors;
  // One entry per question in the session — not just the single weakest
  // "focus" question. Each carries that question's own real XAI text
  // (Gemini's per-question explanation from backend/app.py's batch XAI
  // call), so every question gets a real explanation, not just one.
  final List<QuestionFeedback> questionFeedback;

  const AiFeedbackData({
    required this.id,
    required this.studentId,
    required this.courseTitle,
    required this.conceptTitle,
    required this.badgeLabel,
    required this.headline,
    required this.summary,
    required this.currentRetentionPercent,
    required this.declinePercent,
    required this.recoveryRetentionPercent,
    required this.retentionDescription,
    required this.curve,
    required this.factors,
    required this.guidanceTitle,
    required this.guidanceBody,
    required this.reportRows,
    required this.generatedAt,
    this.nextReviewDate,
    this.nextReviewDays,
    this.schedulingFactors = const [],
    this.questionFeedback = const [],
  });

  RetentionCurvePoint get currentPoint {
    return curve.firstWhere(
      (point) => point.isCurrent,
      orElse: () => curve[curve.length ~/ 2],
    );
  }

  factory AiFeedbackData.fromJson(Map<String, dynamic> json) {
    return AiFeedbackData(
      id: json['id'] as String,
      studentId: json['studentId'] as String,
      courseTitle: json['courseTitle'] as String,
      conceptTitle: json['conceptTitle'] as String,
      badgeLabel: json['badgeLabel'] as String,
      headline: json['headline'] as String,
      summary: json['summary'] as String,
      currentRetentionPercent: json['currentRetentionPercent'] as int,
      declinePercent: json['declinePercent'] as int,
      recoveryRetentionPercent: json['recoveryRetentionPercent'] as int,
      retentionDescription: json['retentionDescription'] as String,
      curve: (json['curve'] as List<dynamic>)
          .map(
            (item) =>
                RetentionCurvePoint.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      factors: (json['factors'] as List<dynamic>)
          .map(
            (item) => ExplanationFactor.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      guidanceTitle: json['guidanceTitle'] as String,
      guidanceBody: json['guidanceBody'] as String,
      reportRows: (json['reportRows'] as List<dynamic>)
          .map((item) => ReportMetricRow.fromJson(item as Map<String, dynamic>))
          .toList(),
      generatedAt: DateTime.parse(json['generatedAt'] as String),
      nextReviewDate: json['nextReviewDate'] as String?,
      nextReviewDays: json['nextReviewDays'] as int?,
      schedulingFactors: (json['schedulingFactors'] as List<dynamic>?)
              ?.map(
                (item) => ExplanationFactor.fromJson(item as Map<String, dynamic>),
              )
              .toList() ??
          const [],
      questionFeedback: (json['questionFeedback'] as List<dynamic>?)
              ?.map(
                (item) => QuestionFeedback.fromJson(item as Map<String, dynamic>),
              )
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'studentId': studentId,
      'courseTitle': courseTitle,
      'conceptTitle': conceptTitle,
      'badgeLabel': badgeLabel,
      'headline': headline,
      'summary': summary,
      'currentRetentionPercent': currentRetentionPercent,
      'declinePercent': declinePercent,
      'recoveryRetentionPercent': recoveryRetentionPercent,
      'retentionDescription': retentionDescription,
      'curve': curve.map((item) => item.toJson()).toList(),
      'factors': factors.map((item) => item.toJson()).toList(),
      'guidanceTitle': guidanceTitle,
      'guidanceBody': guidanceBody,
      'reportRows': reportRows.map((item) => item.toJson()).toList(),
      'generatedAt': generatedAt.toIso8601String(),
      'nextReviewDate': nextReviewDate,
      'nextReviewDays': nextReviewDays,
      'schedulingFactors': schedulingFactors.map((item) => item.toJson()).toList(),
      'questionFeedback': questionFeedback.map((item) => item.toJson()).toList(),
    };
  }
}

class FeedbackReport {
  final String title;
  final String generatedFor;
  final DateTime generatedAt;
  final List<ReportMetricRow> rows;

  const FeedbackReport({
    required this.title,
    required this.generatedFor,
    required this.generatedAt,
    required this.rows,
  });

  String asMarkdownTable() {
    final buffer = StringBuffer()
      ..writeln('# $title')
      ..writeln('Student: $generatedFor')
      ..writeln('Generated: ${generatedAt.toIso8601String()}')
      ..writeln()
      ..writeln('| Metric | Value | Interpretation | Recommendation |')
      ..writeln('| --- | --- | --- | --- |');

    for (final row in rows) {
      buffer.writeln(
        '| ${_escape(row.metric)} | ${_escape(row.value)} | ${_escape(row.interpretation)} | ${_escape(row.recommendation)} |',
      );
    }

    return buffer.toString();
  }

  static String _escape(String value) {
    return value.replaceAll('|', r'\|').replaceAll('\n', ' ');
  }
}
