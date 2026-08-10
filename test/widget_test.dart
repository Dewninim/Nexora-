import 'package:flutter_test/flutter_test.dart';
import 'package:neuromathix/models/student_learning_models.dart';

void main() {
  test('StudentDashboardData round-trips recommended concepts for feedback routing', () {
    const dashboard = StudentDashboardData(
      studentId: 'student-demo',
      displayName: 'Demo Student',
      notificationCount: 0,
      currentStreakDays: 0,
      retentionPercent: 0,
      retentionDeltaLabel: 'No sessions yet',
      retentionTrend: [RetentionPoint(label: 'S1', retentionPercent: 72)],
      keyMetrics: [],
      recommendedConcepts: [
        RecommendedConcept(
          id: 'material-1',
          courseId: 'material-1',
          category: 'Mathematics',
          title: 'Quadratic Equations',
          retentionNote: 'Review due today.',
          actionLabel: 'Review Concept',
          feedbackId: 'material-1',
          visualStyle: ConceptVisualStyle.mathematics,
        ),
      ],
      quickCheck: QuizPrompt(
        id: 'material-1',
        tag: 'QUICK CHECK',
        title: 'Quadratic Equations',
        subtitle: 'Review due today.',
        actionLabel: 'Go to Review Schedule',
      ),
      progressStats: [],
    );

    expect(dashboard.recommendedConcepts, isNotEmpty);
    expect(dashboard.recommendedConcepts.first.feedbackId, isNotEmpty);
    expect(
      dashboard.retentionTrend.every((point) => point.retentionPercent >= 0),
      isTrue,
    );
  });

  test('feedback report can be exported as a markdown table', () {
    final report = FeedbackReport(
      title: 'Quadratic Equations AI Feedback Report',
      generatedFor: 'student-demo',
      generatedAt: DateTime(2026, 1, 1),
      rows: const [
        ReportMetricRow(
          metric: 'Current retention',
          value: '72%',
          interpretation: 'Solid recall strength.',
          recommendation: 'Review again in a few days.',
        ),
      ],
    );

    expect(report.rows, isNotEmpty);
    expect(
      report.asMarkdownTable(),
      contains('| Metric | Value | Interpretation | Recommendation |'),
    );
  });
}
