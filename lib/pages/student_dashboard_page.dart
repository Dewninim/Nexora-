import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/student_learning_models.dart';
import '../services/student_learning_service.dart';
import '../theme/app_theme.dart';
import '../widgets/student_app_shell.dart';
import 'explainable_ai_feedback_page.dart';
import 'learning_session_screen.dart';

class StudentDashboardPage extends StatefulWidget {
  final String studentId;
  final StudentLearningService? service;

  const StudentDashboardPage({
    super.key,
    required this.studentId,
    this.service,
  });

  @override
  State<StudentDashboardPage> createState() => _StudentDashboardPageState();
}

class _StudentDashboardPageState extends State<StudentDashboardPage> {
  // Last-known-good data only — purely so re-visiting the dashboard paints
  // instantly instead of an empty spinner while the fresh fetch below is
  // in flight. NOT a source of truth: every mount below always kicks off a
  // real fetch. This used to also cache the Future itself (via
  // putIfAbsent), which meant the dashboard showed the SAME stale data for
  // the rest of the app's lifetime after the first load — completing a
  // session never updated mastery/review numbers here without a full app
  // restart. That was the bug; this cache only ever holds what was really
  // fetched, refreshed on every visit.
  static final Map<String, StudentDashboardData> _dashboardCache = {};

  late final StudentLearningService _service;
  late final Future<StudentDashboardData> _dashboardFuture;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? BackendStudentLearningService();
    _dashboardFuture = _loadDashboard();
  }

  Future<StudentDashboardData> _loadDashboard() async {
    final data = await _service.getDashboard(widget.studentId);
    _dashboardCache[widget.studentId] = data;
    return data;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StudentDashboardData>(
      future: _dashboardFuture,
      builder: (context, snapshot) {
        final data = snapshot.data ?? _dashboardCache[widget.studentId];
        final userName = currentAuthUserName(
          fallback: data?.displayName ?? 'Student',
        );

        return StudentAppShell(
          activeSection: StudentNavSection.dashboard,
          userName: userName,
          notificationCount: data?.notificationCount ?? 0,
          onSectionSelected: (section) => _openSection(context, section),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 120),
            child: data == null
                ? const Center(
                    key: ValueKey('dashboard-loading'),
                    child: CircularProgressIndicator(),
                  )
                : KeyedSubtree(
                    key: const ValueKey('dashboard-content'),
                    child: _DashboardContent(data: data, service: _service),
                  ),
          ),
        );
      },
    );
  }

  static void _openSection(
    BuildContext context,
    StudentNavSection section,
  ) {
    if (section == StudentNavSection.dashboard) {
      return;
    }

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

class _DashboardContent extends StatelessWidget {
  final StudentDashboardData data;
  final StudentLearningService service;

  const _DashboardContent({required this.data, required this.service});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(36, 32, 36, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Luxury Hero Banner (Left 7) + Current Streak Card (Right 5)
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 960;
                  final heroBanner = _LuxuryHeroBanner(data: data);
                  final streakCard = _CurrentStreakCard(streakDays: data.currentStreakDays);

                  if (!isWide) {
                    return Column(
                      children: [
                        heroBanner,
                        const SizedBox(height: 20),
                        streakCard,
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 7, child: heroBanner),
                      const SizedBox(width: 24),
                      Expanded(flex: 4, child: streakCard),
                    ],
                  );
                },
              ),

              const SizedBox(height: 28),

              // Live forgetting-curve-computed next reviews from backend
              _NextReviewsSection(studentId: data.studentId),

              const SizedBox(height: 28),

              // Second Row: Memory Retention Overview + Key Metrics
              _RetentionOverview(data: data),

              const SizedBox(height: 28),

              // Stepper: Get Started
              const _GetStartedStepper(),

              const SizedBox(height: 28),

              // Bottom Stats Row: Materials Tracked, Study Time, Overall Mastery
              _ProgressStats(stats: data.progressStats),

              const SizedBox(height: 32),

              Text(
                'Recommended Now',
                style: AppText.sectionHeader,
              ),
              const SizedBox(height: 16),
              _RecommendedConceptGrid(
                concepts: data.recommendedConcepts,
                onConceptSelected: (concept) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ExplainableAiFeedbackPage(
                        service: service,
                        studentId: data.studentId,
                        feedbackId: concept.feedbackId,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 26),
              _QuickCheckCard(
                prompt: data.quickCheck,
                onAction: () => Navigator.pushNamed(
                  context,
                  data.recommendedConcepts.isEmpty ? '/upload' : '/review',
                ),
              ),
              const SizedBox(height: 26),
            ],
          ),
        ),
      ),
    );
  }
}

/// Luxury Dark Navy Hero Banner matching reference screenshot media_1786505866507.png
class _LuxuryHeroBanner extends StatelessWidget {
  final StudentDashboardData data;

  const _LuxuryHeroBanner({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF060B19),
            Color(0xFF0E1A38),
            Color(0xFF1E3A8A),
          ],
        ),
        border: Border.all(color: AppColors.goldBorder.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      child: Stack(
        children: [
          // Background Math Formulas Watermark
          Positioned(
            right: 20,
            bottom: 0,
            child: Opacity(
              opacity: 0.08,
              child: Text(
                'f(x)=x²   ∫x dx   a²+b²=c²   sin(x)',
                style: GoogleFonts.openSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Ready to strengthen your math memory?',
                      style: GoogleFonts.openSans(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Upload a lesson and NeuroMathix will build your personalized study path.',
                      style: GoogleFonts.openSans(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.8),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Wrap(
                      spacing: 14,
                      runSpacing: 10,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => Navigator.pushNamed(context, '/upload'),
                          icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                          label: Text(
                            'Upload Material',
                            style: GoogleFonts.openSans(fontWeight: FontWeight.w700, fontSize: 13.5),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 4,
                            shadowColor: AppColors.accent.withValues(alpha: 0.5),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.pushNamed(context, '/review'),
                          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                          label: Text(
                            'View Learning Path',
                            style: GoogleFonts.openSans(fontWeight: FontWeight.w700, fontSize: 13.5),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.6), width: 1.5),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _showStudentHelpDialog(context),
                          icon: const Icon(Icons.help_outline_rounded, size: 18),
                          label: Text(
                            'Ask Teacher for Help',
                            style: GoogleFonts.openSans(fontWeight: FontWeight.w700, fontSize: 13.5),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: AppColors.goldAccent, width: 1.5),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Glowing 3D Neural Brain Visual on Right
              const SizedBox(width: 20),
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8), Color(0xFF0F172A)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.6),
                      blurRadius: 28,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.psychology_outlined,
                  size: 64,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Current Streak Card matching reference screenshot media_1786505866507.png
class _CurrentStreakCard extends StatelessWidget {
  final int streakDays;

  const _CurrentStreakCard({required this.streakDays});

  @override
  Widget build(BuildContext context) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final todayIndex = DateTime.now().weekday - 1; // 0=Mon, 1=Tue, 2=Wed, etc.

    bool isDayActive(int i) {
      if (streakDays <= 0) return false;
      final startActive = todayIndex - streakDays + 1;
      return i >= startActive && i <= todayIndex;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Current Streak',
            style: GoogleFonts.openSans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.goldLight,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.goldBorder, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.goldBorder.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.local_fire_department_rounded,
                  size: 34,
                  color: Color(0xFFD97706),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '$streakDays Days',
                style: GoogleFonts.openSans(
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (int i = 0; i < days.length; i++)
                Column(
                  children: [
                    Text(
                      days[i],
                      style: GoogleFonts.openSans(
                        fontSize: 11,
                        fontWeight: i == todayIndex ? FontWeight.w600 : FontWeight.w600,
                        color: i == todayIndex ? AppColors.accent : AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDayActive(i) ? AppColors.accent : Colors.white,
                        border: Border.all(
                          color: isDayActive(i)
                              ? (i == todayIndex ? AppColors.goldBorder : AppColors.accent)
                              : AppColors.border,
                          width: i == todayIndex ? 2 : 1.5,
                        ),
                      ),
                      child: isDayActive(i)
                          ? const Icon(Icons.check, size: 13, color: Colors.white)
                          : null,
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Stepper Component for "Get Started" matching reference screenshot
class _GetStartedStepper extends StatelessWidget {
  const _GetStartedStepper();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Get Started',
            style: GoogleFonts.openSans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 600;

              final steps = [
                _StepTile(
                  num: '1',
                  icon: Icons.cloud_upload_outlined,
                  title: 'Upload material',
                  badge: 'Upload your first material',
                  active: true,
                  onTap: () => Navigator.pushNamed(context, '/upload'),
                ),
                _StepTile(
                  num: '2',
                  icon: Icons.description_outlined,
                  title: 'Generate practice',
                  badge: null,
                  active: false,
                  onTap: () => Navigator.pushNamed(context, '/review'),
                ),
                _StepTile(
                  num: '3',
                  icon: Icons.star_outline_rounded,
                  title: 'Build mastery',
                  badge: null,
                  active: false,
                  onTap: () {},
                ),
              ];

              if (isNarrow) {
                return Column(children: steps);
              }

              return Row(
                children: [
                  Expanded(child: steps[0]),
                  const Text('-------', style: TextStyle(color: AppColors.border)),
                  Expanded(child: steps[1]),
                  const Text('-------', style: TextStyle(color: AppColors.border)),
                  Expanded(child: steps[2]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final String num;
  final IconData icon;
  final String title;
  final String? badge;
  final bool active;
  final VoidCallback onTap;

  const _StepTile({
    required this.num,
    required this.icon,
    required this.title,
    required this.badge,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? AppColors.accent : const Color(0xFFF1F5F9),
              ),
              alignment: Alignment.center,
              child: Text(
                num,
                style: GoogleFonts.openSans(
                  color: active ? Colors.white : AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: active ? AppColors.accent.withValues(alpha: 0.1) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: active ? AppColors.accent : AppColors.textMuted),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.openSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badge!,
                        style: GoogleFonts.openSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fetches this student's actual materials from the Flask backend
/// (GET /user/<uid>/materials — see backend/app.py) and shows their real,
/// forgetting-curve-computed next review dates, with a "Continue" button
/// that starts a real session against that material.
class _NextReviewsSection extends StatefulWidget {
  final String studentId;
  const _NextReviewsSection({required this.studentId});

  @override
  State<_NextReviewsSection> createState() => _NextReviewsSectionState();
}

class _NextReviewsSectionState extends State<_NextReviewsSection> {
  late Future<List<_MaterialReview>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<_MaterialReview>> _fetch() async {
    final r = await http
        .get(Uri.parse('$kApiBaseUrl/user/${widget.studentId}/materials'))
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw Exception('Could not load materials (${r.statusCode})');
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    final materials = (data['materials'] as List? ?? []).cast<Map<String, dynamic>>();
    final reviews = materials
        .map((m) => _MaterialReview.fromJson(m))
        .where((m) => m.nextReviewDate != null)
        .toList()
      ..sort((a, b) => a.nextReviewDate!.compareTo(b.nextReviewDate!));
    return reviews;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_MaterialReview>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _WhiteCard(
            child: SizedBox(height: 64, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        if (snap.hasError) {
          // Backend not reachable — fail quiet, not loud. This section is
          // additive; the rest of the (mock) dashboard still renders fine.
          return const SizedBox.shrink();
        }
        final reviews = snap.data ?? [];
        if (reviews.isEmpty) return const SizedBox.shrink();

        final now = DateTime.now();
        final overdue = reviews.where((r) => r.nextReviewDate!.isBefore(now)).toList();
        final upcoming = reviews.where((r) => !r.nextReviewDate!.isBefore(now)).take(3).toList();
        final dueNow = [...overdue, ...upcoming];

        return _WhiteCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.event_available_outlined, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Your Next Reviews', style: AppText.h2)),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pushNamed(context, '/upload'),
                    icon: const Icon(Icons.add, size: 16),
                    label: Text('New Material', style: GoogleFonts.openSans(fontSize: 12, fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Timed to when you\'re about to forget each topic right on schedule.',
                style: AppText.bodySmall,
              ),
              const SizedBox(height: 14),
              ...dueNow.map((r) => _NextReviewRow(review: r)),
            ],
          ),
        );
      },
    );
  }
}

class _MaterialReview {
  final String materialId;
  final String filename;
  final DateTime? nextReviewDate;
  final double? score;
  final int sessionCount;
  final String mode;
  final int studyDays;
  final bool masteryReached;

  _MaterialReview({
    required this.materialId,
    required this.filename,
    required this.nextReviewDate,
    required this.score,
    required this.sessionCount,
    required this.mode,
    required this.studyDays,
    required this.masteryReached,
  });

  factory _MaterialReview.fromJson(Map<String, dynamic> j) {
    final latest = j['latest_session'] as Map<String, dynamic>?;
    DateTime? nextReview;
    final raw = latest?['next_review_date'] as String?;
    if (raw != null) {
      try {
        nextReview = DateTime.parse(raw);
      } catch (_) {}
    }
    return _MaterialReview(
      materialId: j['material_id'] as String? ?? '',
      filename: (j['filename'] as String? ?? 'Untitled.pdf').replaceAll('.pdf', ''),
      nextReviewDate: nextReview,
      score: (latest?['score'] as num?)?.toDouble(),
      sessionCount: j['session_count'] as int? ?? 0,
      mode: j['mode'] as String? ?? 'fixed',
      studyDays: j['study_days'] as int? ?? 7,
      masteryReached: latest?['mastery_reached'] as bool? ?? false,
    );
  }
}

class _NextReviewRow extends StatefulWidget {
  final _MaterialReview review;
  const _NextReviewRow({required this.review});

  @override
  State<_NextReviewRow> createState() => _NextReviewRowState();
}

class _NextReviewRowState extends State<_NextReviewRow> {
  bool _starting = false;

  // Starts a NEW session against this EXISTING material (no re-upload) and
  // jumps straight into it — this is the "continue without going through
  // upload again" flow.
  Future<void> _continueSession() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final r = await http
          .post(Uri.parse('$kApiBaseUrl/material/${widget.review.materialId}/session/start'))
          .timeout(const Duration(seconds: 260));
      if (r.statusCode != 200) throw Exception('Could not start session (${r.statusCode})');
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      final sessionId = data['session_id'] as String?;
      if (sessionId == null) throw Exception('No session_id returned');
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LearningSessionScreen(
            sessionId: sessionId,
            studyMode: widget.review.mode,
            studyDays: widget.review.studyDays,
            fileName: widget.review.filename,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start session: $e')),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final review = widget.review;
    final days = review.nextReviewDate!.difference(DateTime.now()).inDays;
    final isOverdue = days < 0;
    final label = isOverdue
        ? 'Due now'
        : days == 0
            ? 'Today'
            : 'In $days day${days == 1 ? '' : 's'}';
    final color = isOverdue ? AppColors.error : AppColors.accent;
    final bg = isOverdue ? AppColors.errorBg : AppColors.infoBg;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgPage,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(review.filename, style: AppText.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (review.masteryReached) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.workspace_premium, size: 14, color: Color(0xFFF59E0B)),
                    ],
                  ],
                ),
                if (review.score != null)
                  Text('Last score: ${(review.score! * 100).round()}%', style: AppText.caption),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
            child: Text(label, style: GoogleFonts.openSans(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
          SizedBox(
            height: 32,
            child: ElevatedButton(
              onPressed: _starting ? null : _continueSession,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              child: _starting
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('Continue', style: GoogleFonts.openSans(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _RetentionOverview extends StatelessWidget {
  final StudentDashboardData data;

  const _RetentionOverview({required this.data});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 980;

        return _WhiteCard(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
          child: isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RetentionTitle(data: data),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 310,
                      child: _RetentionTrendChart(points: data.retentionTrend),
                    ),
                    const SizedBox(height: 22),
                    _MetricRail(metrics: data.keyMetrics),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _RetentionTitle(data: data),
                          const SizedBox(height: 28),
                          SizedBox(
                            height: 450,
                            child: _RetentionTrendChart(
                              points: data.retentionTrend,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Container(width: 1, height: 280, color: neuromathixBorder),
                    const SizedBox(width: 28),
                    SizedBox(
                      width: 220,
                      child: _MetricRail(metrics: data.keyMetrics),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _RetentionTitle extends StatelessWidget {
  final StudentDashboardData data;

  const _RetentionTitle({required this.data});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Memory Retention Overview',
                style: AppText.sectionHeader,
              ),
              const SizedBox(height: 4),
              Text(
                'Real-time synaptic strength visualization',
                style: AppText.bodyMuted,
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${data.retentionPercent}%',
              style: AppText.metricValue,
            ),
            Text(
              data.retentionDeltaLabel,
              style: GoogleFonts.openSans(
                color: const Color(0xFF54A86F),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricRail extends StatelessWidget {
  final List<DashboardKeyMetric> metrics;

  const _MetricRail({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'KEY METRICS',
          style: GoogleFonts.openSans(
            color: neuromathixMuted,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.4,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 28),
        for (final metric in metrics) ...[
          _MetricItem(metric: metric),
          const SizedBox(height: 24),
        ],
      ],
    );
  }
}

class _MetricItem extends StatelessWidget {
  final DashboardKeyMetric metric;

  const _MetricItem({required this.metric});

  @override
  Widget build(BuildContext context) {
    final icon = switch (metric.id) {
      'focus' => Icons.psychology_outlined,
      'concepts' => Icons.school_outlined,
      'nextReview' => Icons.schedule_outlined,
      _ => Icons.insights_outlined,
    };
    final color = _toneColor(metric.tone);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          metric.label,
          style: GoogleFonts.openSans(
            color: neuromathixMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                metric.value,
                style: GoogleFonts.openSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: neuromathixText,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RetentionTrendChart extends StatelessWidget {
  final List<RetentionPoint> points;

  const _RetentionTrendChart({required this.points});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RetentionTrendPainter(points),
      child: const SizedBox.expand(),
    );
  }
}

class _RetentionTrendPainter extends CustomPainter {
  final List<RetentionPoint> points;

  _RetentionTrendPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    const labelHeight = 46.0;
    final chartRect = Rect.fromLTWH(
      0,
      0,
      size.width,
      size.height - labelHeight,
    );
    final leftPadding = 12.0;
    final rightPadding = 12.0;
    final usableWidth = chartRect.width - leftPadding - rightPadding;

    final gridPaint = Paint()
      ..color = const Color(0xFFEFF2F6)
      ..strokeWidth = 1;

    for (var i = 1; i <= 4; i++) {
      final y = chartRect.top + chartRect.height * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    Offset pointFor(int index) {
      final x = leftPadding + usableWidth * index / (points.length - 1);
      final normalized =
          points[index].retentionPercent.clamp(0, 100).toDouble() / 100;
      final y = chartRect.bottom - (chartRect.height * normalized);
      return Offset(x, y);
    }

    final linePath = Path()..moveTo(pointFor(0).dx, pointFor(0).dy);
    for (var i = 1; i < points.length; i++) {
      final previous = pointFor(i - 1);
      final current = pointFor(i);
      final controlX = (previous.dx + current.dx) / 2;
      linePath.cubicTo(
        controlX,
        previous.dy,
        controlX,
        current.dy,
        current.dx,
        current.dy,
      );
    }

    final areaPath = Path.from(linePath)
      ..lineTo(pointFor(points.length - 1).dx, chartRect.bottom)
      ..lineTo(pointFor(0).dx, chartRect.bottom)
      ..close();

    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          neuromathixBlue.withValues(alpha: 0.18),
          neuromathixBlue.withValues(alpha: 0.02),
        ],
      ).createShader(chartRect);
    canvas.drawPath(areaPath, areaPaint);

    final linePaint = Paint()
      ..color = neuromathixBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    for (var i = 0; i < points.length; i++) {
      final point = pointFor(i);
      if (points[i].highlighted) {
        final fill = i == points.length - 2 ? neuromathixBlue : Colors.white;
        canvas.drawCircle(point, 18, Paint()..color = fill);
        canvas.drawCircle(
          point,
          18,
          Paint()
            ..color = neuromathixBlue
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4,
        );
      }
    }

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    for (var i = 0; i < points.length; i++) {
      if (points[i].label.isEmpty) continue;
      textPainter.text = TextSpan(
        text: points[i].label,
        style: GoogleFonts.openSans(
          color: neuromathixMuted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      );
      textPainter.layout();
      final point = pointFor(i);
      textPainter.paint(
        canvas,
        Offset(point.dx - textPainter.width / 2, chartRect.bottom + 22),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RetentionTrendPainter oldDelegate) {
    return oldDelegate.points != points;
  }
}

class _RecommendedConceptGrid extends StatelessWidget {
  final List<RecommendedConcept> concepts;
  final ValueChanged<RecommendedConcept> onConceptSelected;

  const _RecommendedConceptGrid({
    required this.concepts,
    required this.onConceptSelected,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSingleColumn = constraints.maxWidth < 900;

        return Wrap(
          spacing: 26,
          runSpacing: 22,
          children: concepts
              .map(
                (concept) => SizedBox(
                  width: isSingleColumn
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 26) / 2,
                  child: _RecommendedConceptCard(
                    concept: concept,
                    onTap: () => onConceptSelected(concept),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _RecommendedConceptCard extends StatelessWidget {
  final RecommendedConcept concept;
  final VoidCallback onTap;

  const _RecommendedConceptCard({required this.concept, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _WhiteCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 182,
              width: double.infinity,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(10),
                ),
                child: _ConceptVisual(
                  style: concept.visualStyle,
                  label: concept.category,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    concept.title,
                    style: GoogleFonts.openSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: neuromathixText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        concept.visualStyle == ConceptVisualStyle.mathematics
                            ? Icons.history_toggle_off_rounded
                            : Icons.lightbulb_outline_rounded,
                        color:
                            concept.visualStyle ==
                                ConceptVisualStyle.mathematics
                            ? const Color(0xFFFF8A2A)
                            : const Color(0xFF48A96B),
                        size: 19,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          concept.retentionNote,
                          style: GoogleFonts.openSans(
                            color: neuromathixMuted,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton(
                      onPressed: onTap,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFF0F2F5),
                        foregroundColor: neuromathixText,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                      child: Text(
                        concept.actionLabel,
                        style: GoogleFonts.openSans(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConceptVisual extends StatelessWidget {
  final ConceptVisualStyle style;
  final String label;

  const _ConceptVisual({required this.style, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = style == ConceptVisualStyle.mathematics
        ? const [Color(0xFF2563EB), Color(0xFF0F172A)]
        : const [Color(0xFF3B82F6), Color(0xFF1E3A8A)];

    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: CustomPaint(painter: _ConceptVisualPainter(style)),
        ),
        Positioned(
          left: 22,
          bottom: 22,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: Colors.white.withValues(alpha: 0.42)),
            ),
            child: Text(
              label,
              style: GoogleFonts.openSans(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ConceptVisualPainter extends CustomPainter {
  final ConceptVisualStyle style;

  _ConceptVisualPainter(this.style);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(
        alpha: style == ConceptVisualStyle.mathematics ? 0.16 : 0.26,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    if (style == ConceptVisualStyle.mathematics) {
      for (var i = 0; i < 4; i++) {
        final x = size.width * (0.18 + i * 0.18);
        canvas.drawLine(
          Offset(x, 0),
          Offset(x + size.width * 0.18, size.height),
          paint,
        );
      }
      canvas.drawLine(
        Offset(0, size.height * 0.18),
        Offset(size.width, size.height * 0.18),
        paint,
      );
      canvas.drawLine(
        Offset(0, size.height * 0.5),
        Offset(size.width, size.height * 0.52),
        paint,
      );
      return;
    }

    final path = Path()
      ..moveTo(size.width * 0.08, size.height * 0.65)
      ..cubicTo(
        size.width * 0.18,
        size.height * 0.2,
        size.width * 0.42,
        size.height * 0.3,
        size.width * 0.55,
        size.height * 0.1,
      )
      ..cubicTo(
        size.width * 0.72,
        size.height * 0.46,
        size.width * 0.88,
        size.height * 0.12,
        size.width * 0.98,
        size.height * 0.32,
      );
    canvas.drawPath(path, paint);

    final path2 = Path()
      ..moveTo(size.width * 0.2, size.height * 0.1)
      ..cubicTo(
        size.width * 0.32,
        size.height * 0.5,
        size.width * 0.58,
        size.height * 0.22,
        size.width * 0.9,
        size.height * 0.78,
      );
    canvas.drawPath(path2, paint);

    for (final point in [
      Offset(size.width * 0.3, size.height * 0.44),
      Offset(size.width * 0.55, size.height * 0.24),
      Offset(size.width * 0.74, size.height * 0.48),
    ]) {
      canvas.drawCircle(
        point,
        5,
        Paint()..color = Colors.white.withValues(alpha: 0.24),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ConceptVisualPainter oldDelegate) {
    return oldDelegate.style != style;
  }
}

class _QuickCheckCard extends StatelessWidget {
  final QuizPrompt prompt;
  final VoidCallback onAction;

  const _QuickCheckCard({required this.prompt, required this.onAction});

  @override
  Widget build(BuildContext context) {
    return _WhiteCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 760;

          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                prompt.tag,
                style: GoogleFonts.openSans(
                  color: neuromathixBlue,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                prompt.title,
                style: GoogleFonts.openSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                prompt.subtitle,
                style: GoogleFonts.openSans(color: neuromathixMuted, fontSize: 15),
              ),
            ],
          );

          return Flex(
            direction: isNarrow ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: isNarrow
                ? CrossAxisAlignment.stretch
                : CrossAxisAlignment.center,
            children: [
              if (isNarrow) copy else Expanded(child: copy),
              if (isNarrow)
                const SizedBox(height: 18)
              else
                const SizedBox(width: 24),
              SizedBox(
                width: isNarrow ? double.infinity : 190,
                height: 64,
                child: FilledButton(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEAF1FF),
                    foregroundColor: neuromathixBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    prompt.actionLabel,
                    style: GoogleFonts.openSans(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProgressStats extends StatelessWidget {
  final List<ProgressStat> stats;

  const _ProgressStats({required this.stats});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSingleColumn = constraints.maxWidth < 760;

        return Wrap(
          spacing: 26,
          runSpacing: 18,
          children: stats
              .map(
                (stat) => SizedBox(
                  width: isSingleColumn
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 52) / 3,
                  child: _ProgressStatCard(stat: stat),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _ProgressStatCard extends StatelessWidget {
  final ProgressStat stat;

  const _ProgressStatCard({required this.stat});

  @override
  Widget build(BuildContext context) {
    final color = _toneColor(stat.tone);
    final icon = switch (stat.id) {
      'modules' => Icons.article_outlined,
      'studyTime' => Icons.timer_outlined,
      'mastery' => Icons.star_border_rounded,
      _ => Icons.insights_outlined,
    };

    return _WhiteCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 29,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stat.label,
                style: GoogleFonts.openSans(
                  color: neuromathixMuted,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                stat.value,
                style: GoogleFonts.openSans(
                  color: neuromathixText,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WhiteCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _WhiteCard({
    required this.child,
    this.padding = const EdgeInsets.all(22),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: neuromathixBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

Future<void> _showStudentHelpDialog(BuildContext context) async {
  final topicCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final studentName = FirebaseAuth.instance.currentUser?.displayName ??
      FirebaseAuth.instance.currentUser?.email?.split('@').first ??
      'Student';

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.goldBorder.withValues(alpha: 0.6), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.help_center_rounded,
                      color: AppColors.accent,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ask Teacher for Help',
                        style: GoogleFonts.openSans(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                      Text(
                        'Send a direct request to your assigned educator.',
                        style: GoogleFonts.openSans(fontSize: 13, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Mathematics Topic',
                style: GoogleFonts.openSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: topicCtrl,
                autofocus: true,
                style: GoogleFonts.openSans(fontSize: 14, color: AppColors.textDark),
                decoration: InputDecoration(
                  hintText: 'e.g. Integration by Parts or Matrix Transformations',
                  hintStyle: GoogleFonts.openSans(fontSize: 13, color: AppColors.textFaint),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Description / Question Details',
                style: GoogleFonts.openSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: descCtrl,
                minLines: 3,
                maxLines: 5,
                style: GoogleFonts.openSans(fontSize: 14, color: AppColors.textDark),
                decoration: InputDecoration(
                  hintText: 'Describe where you got stuck or what you need clarified...',
                  hintStyle: GoogleFonts.openSans(fontSize: 13, color: AppColors.textFaint),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogCtx, false),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textMuted,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                    child: Text('Cancel', style: GoogleFonts.openSans(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(dialogCtx, true),
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Send Help Request'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  if (result == true && context.mounted) {
    final topic = topicCtrl.text.trim();
    final desc = descCtrl.text.trim();
    if (topic.isEmpty || desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both topic name and description.')),
      );
      return;
    }

    try {
      // Fetch assigned teacherId if available
      String teacherId = '';
      if (uid.isNotEmpty) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        teacherId = userDoc.data()?['teacherId']?.toString() ?? '';
      }

      final docRef = FirebaseFirestore.instance.collection('helpRequests').doc();
      await docRef.set({
        'studentId': uid,
        'teacherId': teacherId,
        'studentName': studentName,
        'studentEmail': FirebaseAuth.instance.currentUser?.email ?? '',
        'conceptName': topic,
        'studentMessage': desc,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Help request sent! Your teacher will be notified.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send help request: $e')),
      );
    }
  }
}

Color _toneColor(String tone) {
  switch (tone) {
    case 'green':
      return const Color(0xFF4DA86C);
    case 'orange':
      return const Color(0xFFFF8126);
    case 'purple':
      return const Color(0xFF9A42F2);
    case 'blue':
    default:
      return neuromathixBlue;
  }
}
