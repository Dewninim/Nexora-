// Analytics Page - Tharuka Karunarathne
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/student_learning_models.dart';
import '../services/student_learning_service.dart';
import '../theme/app_theme.dart';
import '../widgets/student_app_shell.dart';

class AnalyticsPage extends StatefulWidget {
  final String studentId;
  final StudentLearningService? service;

  const AnalyticsPage({super.key, required this.studentId, this.service});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  late final StudentLearningService _service;
  late final Future<StudentDashboardData> _dashboardFuture;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? BackendStudentLearningService();
    _dashboardFuture = _service.getDashboard(widget.studentId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StudentDashboardData>(
      future: _dashboardFuture,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final hasError = snapshot.connectionState == ConnectionState.done &&
            snapshot.hasError;

        return StudentAppShell(
          activeSection: StudentNavSection.analytics,
          userName: currentAuthUserName(
            fallback: data?.displayName ?? 'Student',
          ),
          notificationCount: data?.notificationCount ?? 0,
          onSectionSelected: (section) => _openSection(context, section),
          child: hasError
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      "Couldn't load your analytics right now. Please try again later.",
                      style: GoogleFonts.openSans(color: AppColors.textMuted),
                    ),
                  ),
                )
              : data == null
                  ? const Center(child: CircularProgressIndicator())
                  : _AnalyticsContent(data: data),
        );
      },
    );
  }

  static void _openSection(BuildContext context, StudentNavSection section) {
    if (section == StudentNavSection.analytics) return;
    Navigator.pushNamed(context, _routeForSection(section));
  }

  static String _routeForSection(StudentNavSection section) {
    switch (section) {
      case StudentNavSection.dashboard:
        return '/student-dashboard';
      case StudentNavSection.teacherMessages:
        return '/teacher-messages';
      case StudentNavSection.uploadMaterial:
        return '/upload';
      case StudentNavSection.aiFeedback:
        return '/ai-feedback';
      case StudentNavSection.reviewSchedule:
        return '/review';
      case StudentNavSection.analytics:
        return '/analytics';
      case StudentNavSection.settings:
        return '/profile';
    }
  }
}

/// Blue shades cycled across however many topics come back from the backend
/// (mock data happens to have 6, but this no longer assumes a fixed count).
const _topicBarPalette = [
  Color(0xFF1a2f5e),
  AppColors.accent,
  Color(0xFF2E86AB),
  Color(0xFF3A9BBF),
  Color(0xFF4DB8D4),
  Color(0xFF6DD4E8),
];

(Color, Color) _trendColors(String trend) {
  switch (trend) {
    case 'Improving':
      return (AppColors.success, const Color(0xFFDCFCE7));
    case 'Declining':
      return (AppColors.error, const Color(0xFFFEE2E2));
    default:
      return (const Color(0xFF374151), AppColors.bgPage);
  }
}

/// Real per-material progress, straight from GET /user/<uid>/materials —
/// see the comment where this is inserted in _AnalyticsContent for why the
/// rest of this page (mastery trend, topic breakdown) is still mock.
class _MaterialsOverviewSection extends StatefulWidget {
  final String studentId;
  const _MaterialsOverviewSection({required this.studentId});

  @override
  State<_MaterialsOverviewSection> createState() => _MaterialsOverviewSectionState();
}

class _MaterialsOverviewSectionState extends State<_MaterialsOverviewSection> {
  late Future<List<_MaterialProgress>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<_MaterialProgress>> _fetch() async {
    final r = await http
        .get(Uri.parse('$kApiBaseUrl/user/${widget.studentId}/materials'))
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw Exception('Could not load materials (${r.statusCode})');
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    return (data['materials'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .map((m) => _MaterialProgress.fromJson(m))
        .toList();
  }

  Widget _cardWrap({required Widget child}) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_MaterialProgress>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _cardWrap(
            child: const SizedBox(height: 60, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        final materials = snap.data ?? [];
        if (snap.hasError || materials.isEmpty) return const SizedBox.shrink();

        return _cardWrap(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.menu_book_outlined, size: 18, color: AppColors.textMuted),
                  const SizedBox(width: 8),
                  Text('Your Materials',
                      style: GoogleFonts.openSans(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textDark)),
                ],
              ),
              const SizedBox(height: 14),
              ...materials.map((m) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(m.filename,
                              style: GoogleFonts.openSans(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textDark),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text('${m.sessionCount} session${m.sessionCount == 1 ? '' : 's'}',
                              style: GoogleFonts.openSans(fontSize: 11.5, color: AppColors.textMuted)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text('${m.coveragePercent.toStringAsFixed(0)}% covered',
                              style: GoogleFonts.openSans(fontSize: 11.5, color: AppColors.textMuted)),
                        ),
                        SizedBox(
                          width: 60,
                          child: m.latestScore == null
                              ? Text('—', style: GoogleFonts.openSans(fontSize: 11.5, color: AppColors.textFaint))
                              : Text('${(m.latestScore! * 100).round()}%',
                                  textAlign: TextAlign.right,
                                  style: GoogleFonts.openSans(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: m.latestScore! >= 0.7 ? AppColors.success : AppColors.error)),
                        ),
                      ],
                    ),
                  )),
            ],
          ),
        );
      },
    );
  }
}

class _MaterialProgress {
  final String filename;
  final int sessionCount;
  final double coveragePercent;
  final double? latestScore;

  _MaterialProgress({
    required this.filename,
    required this.sessionCount,
    required this.coveragePercent,
    required this.latestScore,
  });

  factory _MaterialProgress.fromJson(Map<String, dynamic> j) {
    final latest = j['latest_session'] as Map<String, dynamic>?;
    return _MaterialProgress(
      filename: (j['filename'] as String? ?? 'Untitled.pdf').replaceAll('.pdf', ''),
      sessionCount: j['session_count'] as int? ?? 0,
      coveragePercent: (j['material_coverage_percent'] as num?)?.toDouble() ?? 0,
      latestScore: (latest?['score'] as num?)?.toDouble(),
    );
  }
}

class _AnalyticsContent extends StatelessWidget {
  final StudentDashboardData data;

  const _AnalyticsContent({required this.data});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            'Progress & Analytics',
            style: GoogleFonts.openSans(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Track your personalized learning journey, synaptic retention, and topic mastery.',
            style: GoogleFonts.openSans(color: AppColors.textMuted, fontSize: 14),
          ),
          const SizedBox(height: 28),

          // Per-material session count, latest score, and coverage — from
          // GET /user/<uid>/materials. The mastery trend / topic breakdown /
          // stat cards below come from GET /user/<uid>/analytics via
          // BackendStudentLearningService — also real, computed from this
          // student's actual stored sessions.
          _MaterialsOverviewSection(studentId: data.studentId),
          const SizedBox(height: 24),

          // ── Stat cards row ──
          Row(
            children: [
              _statCard(
                Icons.trending_up_rounded,
                '${data.overallMasteryPercent}%',
                'Overall Mastery',
              ),
              const SizedBox(width: 16),
              _statCard(
                Icons.adjust_rounded,
                '${data.problemsSolved}',
                'Problems Solved',
              ),
              const SizedBox(width: 16),
              _statCard(
                Icons.access_time_rounded,
                '${data.studyTimeHours.round()}h',
                'Study Time',
              ),
              const SizedBox(width: 16),
              _statCard(
                Icons.calendar_today_rounded,
                '${data.currentStreakDays}',
                'Day Streak',
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Charts row ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Line chart card
              Expanded(
                child: _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.trending_up_rounded,
                            size: 18,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Mastery Progress Over Time',
                            style: GoogleFonts.openSans(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: AppColors.textDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 200,
                        child: data.masteryProgressTrend.isEmpty
                            ? Center(
                                child: Text(
                                  'No progress data yet — complete a\nlearning session to see your trend.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.openSans(
                                    fontSize: 12,
                                    color: AppColors.textFaint,
                                  ),
                                ),
                              )
                            : CustomPaint(
                                painter: _LineChartPainter(
                                  values: data.masteryProgressTrend
                                      .map((p) => p.retentionPercent)
                                      .toList(),
                                ),
                                size: Size.infinite,
                              ),
                      ),
                      const SizedBox(height: 8),
                      // X-axis labels
                      if (data.masteryProgressTrend.isNotEmpty)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: data.masteryProgressTrend
                              .map(
                                (p) => Text(
                                  p.label,
                                  style: GoogleFonts.openSans(
                                    fontSize: 10,
                                    color: AppColors.textFaint,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 12,
                            height: 2,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Mastery Progress Over Time',
                            style: GoogleFonts.openSans(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Horizontal bar chart card
              Expanded(
                child: _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.adjust_rounded,
                            size: 18,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Topic Mastery Breakdown',
                            style: GoogleFonts.openSans(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: AppColors.textDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // X-axis labels at top
                      Padding(
                        padding: const EdgeInsets.only(left: 90),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: ['0', '20', '40', '60', '80', '100']
                              .map(
                                (l) => Text(
                                  l,
                                  style: GoogleFonts.openSans(
                                    fontSize: 10,
                                    color: AppColors.textFaint,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (data.topicMastery.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'No topic data yet.',
                            style: GoogleFonts.openSans(
                              fontSize: 12,
                              color: AppColors.textFaint,
                            ),
                          ),
                        )
                      else
                        ...List.generate(data.topicMastery.length, (i) {
                          final topic = data.topicMastery[i];
                          final barColor =
                              _topicBarPalette[i % _topicBarPalette.length];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 90,
                                  child: Text(
                                    topic.topic,
                                    style: GoogleFonts.openSans(
                                      fontSize: 11,
                                      color: const Color(0xFF374151),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Expanded(
                                  child: Stack(
                                    children: [
                                      Container(
                                        height: 20,
                                        decoration: BoxDecoration(
                                          color: AppColors.bgPage,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                      ),
                                      FractionallySizedBox(
                                        widthFactor:
                                            topic.masteryPercent / 100,
                                        child: Container(
                                          height: 20,
                                          decoration: BoxDecoration(
                                            color: barColor,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${topic.masteryPercent}',
                                  style: GoogleFonts.openSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF374151),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Topic Mastery Breakdown',
                            style: GoogleFonts.openSans(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── AI Insights section ──
          Text(
            'Insights',
            style: GoogleFonts.openSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: _buildInsightCards(this)
                .expand((w) => [Expanded(child: w), const SizedBox(width: 16)])
                .toList()
              ..removeLast(),
          ),
          const SizedBox(height: 28),

          // ── Detailed Topic Analysis ──
          Text(
            'Detailed Topic Analysis',
            style: GoogleFonts.openSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 16),
          if (data.topicMastery.isEmpty)
            Text(
              'Complete a learning session to see a per-topic breakdown here.',
              style: GoogleFonts.openSans(fontSize: 13, color: AppColors.textMuted),
            )
          else
            ...data.topicMastery.map((topic) {
              final (textColor, bgColor) = _trendColors(topic.trend);
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      topic.topic,
                      style: GoogleFonts.openSans(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Stack(
                            children: [
                              Container(
                                height: 10,
                                decoration: BoxDecoration(
                                  color: AppColors.bgPage,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: topic.masteryPercent / 100,
                                child: Container(
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: AppColors.accent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${topic.masteryPercent}',
                          style: GoogleFonts.openSans(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            topic.trend,
                            style: GoogleFonts.openSans(
                              color: textColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  /// Derives up to 3 human-readable insight cards straight from the topic
  /// mastery + streak data — nothing here is hardcoded copy anymore.
  List<Widget> _buildInsightCards(_AnalyticsContent content) {
    final topics = content.data.topicMastery;
    final improving = topics.where((t) => t.trend == 'Improving').toList()
      ..sort((a, b) => b.masteryPercent.compareTo(a.masteryPercent));
    final declining = topics.where((t) => t.trend == 'Declining').toList()
      ..sort((a, b) => a.masteryPercent.compareTo(b.masteryPercent));

    final cards = <Widget>[];

    if (improving.isNotEmpty) {
      final t = improving.first;
      cards.add(
        _insightCard(
          color: const Color(0xFFF0FDF4),
          borderColor: const Color(0xFF86EFAC),
          icon: Icons.trending_up_rounded,
          iconColor: AppColors.success,
          title: '${t.topic} Improving',
          body:
              'Your mastery in ${t.topic} is trending up — now at ${t.masteryPercent}%. Keep it going!',
        ),
      );
    }

    if (declining.isNotEmpty) {
      final t = declining.first;
      cards.add(
        _insightCard(
          color: const Color(0xFFFFF7ED),
          borderColor: const Color(0xFFFDBA74),
          icon: Icons.adjust_rounded,
          iconColor: const Color(0xFFEA580C),
          title: '${t.topic} Needs Attention',
          body:
              '${t.topic} has dropped to ${t.masteryPercent}% mastery. A focused review session should help.',
        ),
      );
    }

    if (content.data.currentStreakDays > 0) {
      cards.add(
        _insightCard(
          color: const Color(0xFFF0FDF4),
          borderColor: const Color(0xFF86EFAC),
          icon: Icons.emoji_events_outlined,
          iconColor: AppColors.success,
          title: 'Streak Achievement',
          body:
              "You've maintained a ${content.data.currentStreakDays}-day study streak! Consistency is key to retention.",
        ),
      );
    }

    if (cards.isEmpty) {
      cards.add(
        _insightCard(
          color: AppColors.bgPage,
          borderColor: AppColors.border,
          icon: Icons.insights_outlined,
          iconColor: AppColors.textMuted,
          title: 'Not enough data yet',
          body:
              'Complete a few learning sessions and check back — your personalised insights will show up here.',
        ),
      );
    }

    return cards;
  }

  Widget _statCard(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppColors.textMuted),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: GoogleFonts.openSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
                Text(
                  label,
                  style: GoogleFonts.openSans(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }

  Widget _insightCard({
    required Color color,
    required Color borderColor,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.openSans(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: GoogleFonts.openSans(
              fontSize: 13,
              color: Color(0xFF374151),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Simple line chart painter ──
class _LineChartPainter extends CustomPainter {
  final List<double> values;

  _LineChartPainter({required this.values});

  @override
  void paint(Canvas canvas, Size size) {
    final data = values;
    final maxVal = 100.0;
    final minVal = 0.0;
    final range = maxVal - minVal;

    // Y-axis grid lines
    final gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height - (i / 4) * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      // Y labels
      final tp = TextPainter(
        text: TextSpan(
          text: '${(i * 25).toInt()}',
          style: GoogleFonts.openSans(color: AppColors.textFaint, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-32, y - 6));
    }

    if (data.length < 2) {
      // Not enough points to draw a line — just leave the grid.
      return;
    }

    final points = <Offset>[];
    for (var i = 0; i < data.length; i++) {
      final x = i / (data.length - 1) * size.width;
      final y = size.height - ((data[i] - minVal) / range) * size.height;
      points.add(Offset(x, y));
    }

    // Fill
    final fillPath = Path()..moveTo(points.first.dx, size.height);
    for (final p in points) {
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath.lineTo(points.last.dx, size.height);
    fillPath.close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.accent.withValues(alpha: 0.25),
            AppColors.accent.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Line
    final linePaint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      linePath.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(linePath, linePaint);

    // Dots
    for (final p in points) {
      canvas.drawCircle(
        p,
        4,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        p,
        4,
        Paint()
          ..color = AppColors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.values != values;
}
