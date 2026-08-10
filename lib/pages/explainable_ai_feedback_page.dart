import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/student_learning_models.dart';
import '../services/student_learning_service.dart';
import '../theme/app_theme.dart';
import '../widgets/student_app_shell.dart';
import 'learning_session_screen.dart' show QuestionResult, buildRealAiFeedbackData;

class ExplainableAiFeedbackPage extends StatelessWidget {
  final String? studentId;
  final String feedbackId;
  final StudentLearningService? service;
  // When provided (e.g. navigated to from a just-submitted session), this
  // is used directly instead of fetching anything — same page, same
  // layout, real content built from that session's actual backend response.
  final AiFeedbackData? initialData;
  // When true (the default when reached from normal navigation, not from
  // a just-submitted session), shows a picker over this student's REAL
  // past sessions.
  final bool browseSessions;

  const ExplainableAiFeedbackPage({
    super.key,
    this.studentId,
    this.feedbackId = 'memory-types',
    this.service,
    this.initialData,
    this.browseSessions = true,
  });

  StudentLearningService get _service =>
      service ?? BackendStudentLearningService();

  String get _studentId =>
      studentId ?? FirebaseAuth.instance.currentUser?.uid ?? 'student-demo';

  @override
  Widget build(BuildContext context) {
    if (initialData != null) {
      return StudentAppShell(
        activeSection: StudentNavSection.aiFeedback,
        userName: currentAuthUserName(),
        notificationCount: 0,
        onSectionSelected: (section) => _openSection(context, section),
        child: _FeedbackContent(data: initialData!, service: _service),
      );
    }
    if (browseSessions) {
      return StudentAppShell(
        activeSection: StudentNavSection.aiFeedback,
        userName: currentAuthUserName(),
        notificationCount: 0,
        onSectionSelected: (section) => _openSection(context, section),
        child: _SessionHistoryBrowser(studentId: _studentId, service: _service, feedbackId: feedbackId),
      );
    }
    return FutureBuilder<AiFeedbackData>(
      future: _service.getFeedbackForConcept(
        studentId: _studentId,
        feedbackId: feedbackId,
      ),
      builder: (context, snapshot) {
        final data = snapshot.data;
        final done = snapshot.connectionState == ConnectionState.done;

        return StudentAppShell(
          activeSection: StudentNavSection.aiFeedback,
          userName: currentAuthUserName(),
          notificationCount: 0,
          onSectionSelected: (section) => _openSection(context, section),
          child: data != null
              ? _FeedbackContent(data: data, service: _service)
              : done
                  ? const _NoSessionsYetState(hasError: false)
                  : const Center(child: CircularProgressIndicator()),
        );
      },
    );
  }

  static void _openSection(
    BuildContext context,
    StudentNavSection section,
  ) {
    if (section == StudentNavSection.aiFeedback) {
      return;
    }

    Navigator.pushNamed(context, _routeForSection(section));
  }

  static String _routeForSection(StudentNavSection section) {
    switch (section) {
      case StudentNavSection.dashboard:
        return '/student-dashboard';
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

/// Lists this student's REAL past sessions (from GET /user/<uid>/sessions)
/// and lets them pick one to see its real, session-specific feedback —
/// this is what makes the AI Feedback page update "according to sessions"
/// instead of always showing one static mock concept. Falls back to the
/// mock single-concept view only if the student genuinely has no session
/// history yet (so the page still shows *something* on a first visit).
class _SessionHistoryBrowser extends StatefulWidget {
  final String studentId;
  final StudentLearningService service;
  final String feedbackId;
  const _SessionHistoryBrowser({required this.studentId, required this.service, required this.feedbackId});

  @override
  State<_SessionHistoryBrowser> createState() => _SessionHistoryBrowserState();
}

class _SessionHistoryBrowserState extends State<_SessionHistoryBrowser> {
  late Future<List<Map<String, dynamic>>> _historyFuture;
  String? _selectedSessionId;
  Future<AiFeedbackData>? _selectedFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = _fetchHistory();
  }

  Future<List<Map<String, dynamic>>> _fetchHistory() async {
    final r = await http
        .get(Uri.parse('$kApiBaseUrl/user/${widget.studentId}/sessions'))
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw Exception('Could not load session history (${r.statusCode})');
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    return (data['sessions'] as List? ?? []).cast<Map<String, dynamic>>();
  }

  // Fetches one session's full detail and normalizes it into the same
  // shape buildRealAiFeedbackData already expects (the /submit response
  // shape) — GET /session/<sid> uses slightly different key names
  // ('answers' vs 'results', no top-level correct/total), so this bridges
  // the two instead of duplicating the whole builder function.
  Future<AiFeedbackData> _loadSession(String sessionId) async {
    final r = await http
        .get(Uri.parse('$kApiBaseUrl/session/$sessionId'))
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw Exception('Could not load session (${r.statusCode})');
    final detail = jsonDecode(r.body) as Map<String, dynamic>;
    final answersRaw = (detail['answers'] as List? ?? []).cast<Map<String, dynamic>>();
    final results = answersRaw.map((a) => QuestionResult.fromJson(a)).toList();
    final curve = detail['forgetting_curve'] as Map<String, dynamic>? ?? {};
    final total = results.length;
    final correct = results.where((r) => r.isCorrect).length;
    final normalized = <String, dynamic>{
      'session_id': detail['session_id'],
      'score': detail['score'],
      'correct': correct,
      'total': total,
      'results': answersRaw,
      'forgetting_curve': curve,
      'next_review_days': curve['next_review_days'],
      'next_review_date': curve['next_review_date'],
    };
    return buildRealAiFeedbackData(normalized, results);
  }

  void _select(String sessionId) {
    setState(() {
      _selectedSessionId = sessionId;
      _selectedFuture = _loadSession(sessionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedSessionId != null) {
      return FutureBuilder<AiFeedbackData>(
        future: _selectedFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || snap.data == null) {
            return _errorState('Could not load that session\'s feedback.', () => setState(() => _selectedSessionId = null));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: TextButton.icon(
                  onPressed: () => setState(() => _selectedSessionId = null),
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: Text('All sessions', style: GoogleFonts.dmSans(fontWeight: FontWeight.w700)),
                  style: TextButton.styleFrom(foregroundColor: neuromathixText),
                ),
              ),
              Expanded(child: _FeedbackContent(data: snap.data!, service: widget.service)),
            ],
          );
        },
      );
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _historyFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final sessions = snap.data ?? [];
        if (snap.hasError || sessions.isEmpty) {
          // No real session history yet — show an honest empty state
          // instead of fabricated feedback content.
          return _NoSessionsYetState(hasError: snap.hasError);
        }
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Your Session Feedback', style: GoogleFonts.dmSans(fontSize: 24, fontWeight: FontWeight.w900, color: neuromathixText)),
            const SizedBox(height: 4),
            Text('Pick a past session to see its real, detailed AI feedback.',
                style: GoogleFonts.dmSans(fontSize: 14, color: neuromathixMuted)),
            const SizedBox(height: 20),
            ...sessions.map((s) => _SessionHistoryCard(session: s, onTap: () => _select(s['session_id'] as String))),
          ],
        );
      },
    );
  }

  Widget _errorState(String message, VoidCallback onBack) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: GoogleFonts.dmSans(color: neuromathixMuted)),
          const SizedBox(height: 12),
          TextButton(onPressed: onBack, child: const Text('Back')),
        ],
      ),
    );
  }
}

/// Honest empty state for a student with no completed sessions yet (or an
/// unreachable backend) — replaces the old behaviour of silently rendering
/// fabricated mock feedback in this slot.
class _NoSessionsYetState extends StatelessWidget {
  final bool hasError;
  const _NoSessionsYetState({required this.hasError});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasError ? Icons.cloud_off_rounded : Icons.auto_awesome_outlined,
              size: 40,
              color: neuromathixMuted,
            ),
            const SizedBox(height: 14),
            Text(
              hasError ? "Couldn't reach the server" : 'No AI feedback yet',
              style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w800, color: neuromathixText),
            ),
            const SizedBox(height: 8),
            Text(
              hasError
                  ? 'Check your connection and try again in a moment.'
                  : 'Complete a learning session to see detailed, session-specific AI feedback here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(fontSize: 13.5, color: neuromathixMuted, height: 1.5),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/upload'),
              icon: const Icon(Icons.upload_file_outlined, size: 16),
              label: Text('Upload Material', style: GoogleFonts.dmSans(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionHistoryCard extends StatelessWidget {
  final Map<String, dynamic> session;
  final VoidCallback onTap;
  const _SessionHistoryCard({required this.session, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final score = ((session['score'] as num? ?? 0) * 100).round();
    final filename = ((session['material_filename'] as String? ?? 'Untitled.pdf')).replaceAll('.pdf', '');
    final completedAt = session['completed_at'] as String?;
    String dateLabel = '';
    if (completedAt != null) {
      try {
        final dt = DateTime.parse(completedAt);
        dateLabel = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      } catch (_) {}
    }
    final topics = (session['topics'] as List? ?? []).cast<String>();
    final mastered = session['mastery_reached'] as bool? ?? false;
    final scoreColor = score >= 70 ? const Color(0xFF45B86B) : const Color(0xFFFF7B22);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: neuromathixBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: scoreColor.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Text('$score%', style: GoogleFonts.dmSans(color: scoreColor, fontWeight: FontWeight.w800, fontSize: 12)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(filename, style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: neuromathixText), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if (mastered) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.workspace_premium, size: 14, color: Color(0xFFF59E0B)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Session ${session['session_number']} · $dateLabel${topics.isNotEmpty ? ' · ${topics.join(', ')}' : ''}',
                    style: GoogleFonts.dmSans(fontSize: 12, color: neuromathixMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: neuromathixMuted),
          ],
        ),
      ),
    );
  }
}

class _FeedbackContent extends StatelessWidget {
  final AiFeedbackData data;
  final StudentLearningService service;

  const _FeedbackContent({required this.data, required this.service});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 34, 28, 44),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Breadcrumbs(data: data),
              const SizedBox(height: 24),
              _FeedbackHeader(
                data: data,
                onExport: () => _showReport(context, data),
              ),
              const SizedBox(height: 24),
              _RetentionExplanationCard(data: data),
              if (data.schedulingFactors.isNotEmpty) ...[
                const SizedBox(height: 34),
                _SchedulingExplanationCard(data: data),
              ],
              if (data.questionFeedback.isNotEmpty) ...[
                const SizedBox(height: 34),
                Text(
                  'Question-by-Question Feedback',
                  style: GoogleFonts.dmSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: neuromathixText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Every question in this session, explained individually — not just the one below.',
                  style: GoogleFonts.dmSans(fontSize: 14, color: neuromathixMuted),
                ),
                const SizedBox(height: 18),
                _QuestionFeedbackList(items: data.questionFeedback),
              ],
              const SizedBox(height: 34),
              Text(
                'Key Factors Analysis',
                style: GoogleFonts.dmSans(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: neuromathixText,
                ),
              ),
              const SizedBox(height: 18),
              _FactorGrid(factors: data.factors),
              const SizedBox(height: 28),
              _GuidanceCard(data: data),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showReport(BuildContext context, AiFeedbackData data) async {
    final report = await service.buildFeedbackReport(
      studentId: data.studentId,
      feedbackId: data.id,
    );

    if (!context.mounted) return;

    showDialog<void>(
      context: context,
      builder: (context) => _ReportDialog(report: report),
    );
  }
}

class _Breadcrumbs extends StatelessWidget {
  final AiFeedbackData data;

  const _Breadcrumbs({required this.data});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        Text(
          'Home',
          style: GoogleFonts.dmSans(
            color: neuromathixMuted,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          '/',
          style: GoogleFonts.dmSans(
            color: neuromathixMuted,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          data.courseTitle,
          style: GoogleFonts.dmSans(
            color: neuromathixMuted,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          '/',
          style: GoogleFonts.dmSans(
            color: neuromathixMuted,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          data.conceptTitle,
          style: GoogleFonts.dmSans(
            color: neuromathixText,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _FeedbackHeader extends StatelessWidget {
  final AiFeedbackData data;
  final VoidCallback onExport;

  const _FeedbackHeader({required this.data, required this.onExport});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 820;

        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFE4EEFF),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                data.badgeLabel,
                style: GoogleFonts.dmSans(
                  color: neuromathixBlue,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              data.headline,
              style: GoogleFonts.dmSans(
                fontSize: 36,
                fontWeight: FontWeight.w900,
                color: neuromathixText,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Text(
                data.summary,
                style: GoogleFonts.dmSans(
                  fontSize: 17,
                  color: neuromathixMuted,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );

        return Flex(
          direction: isNarrow ? Axis.vertical : Axis.horizontal,
          crossAxisAlignment: isNarrow
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.end,
          children: [
            if (isNarrow) copy else Expanded(child: copy),
            if (isNarrow)
              const SizedBox(height: 18)
            else
              const SizedBox(width: 24),
            OutlinedButton.icon(
              onPressed: onExport,
              icon: const Icon(Icons.file_download_outlined, size: 20),
              label: const Text('Export Report'),
              style: OutlinedButton.styleFrom(
                foregroundColor: neuromathixText,
                side: const BorderSide(color: neuromathixBorder),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 15,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: GoogleFonts.dmSans(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RetentionExplanationCard extends StatelessWidget {
  final AiFeedbackData data;

  const _RetentionExplanationCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return _WhitePanel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 960;

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: _RetentionSummary(data: data),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  height: 360,
                  width: double.infinity,
                  child: _ForgettingCurveChart(data: data),
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 470, child: _RetentionSummary(data: data)),
              const SizedBox(width: 30),
              Expanded(
                child: SizedBox(
                  height: 430,
                  child: _ForgettingCurveChart(data: data),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RetentionSummary extends StatelessWidget {
  final AiFeedbackData data;

  const _RetentionSummary({required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'RIGHT AFTER THIS SESSION',
          style: GoogleFonts.dmSans(
            color: neuromathixMuted,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 6,
          children: [
            Text(
              '${data.currentRetentionPercent}%',
              style: GoogleFonts.dmSans(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                color: neuromathixText,
              ),
            ),
            // Not a live decline — this is what the same Ebbinghaus curve
            // predicts happening BETWEEN now and the next review date if
            // you don't reinforce it, so it can't be misread as
            // simultaneous with the 100% above it.
            Text(
              '↓${data.declinePercent}% predicted by next review',
              style: GoogleFonts.dmSans(
                color: Color(0xFFFF414D),
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          data.retentionDescription,
          style: GoogleFonts.dmSans(
            color: neuromathixMuted,
            fontSize: 15,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 26),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 210),
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F6FF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD7E4FF)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.lightbulb_outline_rounded,
                color: neuromathixBlue,
                size: 25,
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Optimal Review Window',
                      style: GoogleFonts.dmSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: neuromathixText,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text.rich(
                      TextSpan(
                        style: GoogleFonts.dmSans(
                          color: neuromathixMuted,
                          fontSize: 15,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                        children: [
                          const TextSpan(
                            text:
                                'Reviewing now will boost your retention back to ',
                          ),
                          TextSpan(
                            text: '${data.recoveryRetentionPercent}%',
                            style: GoogleFonts.dmSans(
                              color: neuromathixBlue,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const TextSpan(
                            text: ' with less effort than relearning later.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "How we calculated this" reveal for the next-review date — a real,
/// step-by-step trace of the backend/app.py:compute_forgetting_curve()
/// inputs (accuracy, mistakes, hints, session count, the study mode/period
/// chosen at upload), not decorative copy. This is the direct answer to
/// "why this date" that the plain next-review card doesn't spell out.
class _SchedulingExplanationCard extends StatefulWidget {
  final AiFeedbackData data;
  const _SchedulingExplanationCard({required this.data});

  @override
  State<_SchedulingExplanationCard> createState() => _SchedulingExplanationCardState();
}

class _SchedulingExplanationCardState extends State<_SchedulingExplanationCard> {
  int _revealed = 0;

  @override
  void initState() {
    super.initState();
    _reveal();
  }

  void _reveal() {
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted || _revealed >= widget.data.schedulingFactors.length) return;
      setState(() => _revealed++);
      _reveal();
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return _WhitePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_alt_outlined, color: neuromathixBlue, size: 22),
              const SizedBox(width: 10),
              Text(
                'How we calculated your next review',
                style: GoogleFonts.dmSans(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: neuromathixText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Every input below came from this session — nothing here is a fixed schedule.',
            style: GoogleFonts.dmSans(fontSize: 13, color: neuromathixMuted),
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < data.schedulingFactors.length; i++)
            AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: i < _revealed ? 1 : 0.15,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      margin: const EdgeInsets.only(top: 1),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF16A34A),
                      ),
                      child: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                data.schedulingFactors[i].title,
                                style: GoogleFonts.dmSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: neuromathixText,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                data.schedulingFactors[i].value,
                                style: GoogleFonts.dmSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: neuromathixBlue,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            data.schedulingFactors[i].description,
                            style: GoogleFonts.dmSans(fontSize: 12.5, color: neuromathixMuted, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (data.nextReviewDate != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F6FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFD7E4FF)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_available_rounded, color: neuromathixBlue, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: GoogleFonts.dmSans(fontSize: 14, color: neuromathixText, fontWeight: FontWeight.w600),
                        children: [
                          const TextSpan(text: 'Next review scheduled for '),
                          TextSpan(
                            text: data.nextReviewDate,
                            style: GoogleFonts.dmSans(fontWeight: FontWeight.w900, color: neuromathixBlue),
                          ),
                          if (data.nextReviewDays != null)
                            TextSpan(
                              text: ' (in ${data.nextReviewDays} day${data.nextReviewDays == 1 ? '' : 's'}).',
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ForgettingCurveChart extends StatelessWidget {
  final AiFeedbackData data;

  const _ForgettingCurveChart({required this.data});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ForgettingCurvePainter(data),
      child: const SizedBox.expand(),
    );
  }
}

class _ForgettingCurvePainter extends CustomPainter {
  final AiFeedbackData data;

  _ForgettingCurvePainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.curve.length < 2) return;

    const bottomLabelHeight = 44.0;
    final chart = Rect.fromLTWH(
      0,
      18,
      size.width,
      size.height - bottomLabelHeight - 18,
    );
    final minDay = data.curve.first.day;
    final maxDay = data.curve.last.day;
    final leftPadding = 16.0;
    final rightPadding = 16.0;
    final usableWidth = chart.width - leftPadding - rightPadding;

    Offset pointFor(RetentionCurvePoint point, double value) {
      final x =
          leftPadding +
          usableWidth * ((point.day - minDay) / (maxDay - minDay));
      final normalized = value.clamp(0, 100).toDouble() / 100;
      final y = chart.bottom - chart.height * normalized;
      return Offset(x, y);
    }

    final gridPaint = Paint()
      ..color = const Color(0xFFEFF2F6)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = chart.top + chart.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final idealPath = Path()
      ..moveTo(
        pointFor(data.curve.first, data.curve.first.idealRetention).dx,
        pointFor(data.curve.first, data.curve.first.idealRetention).dy,
      );
    for (var i = 1; i < data.curve.length; i++) {
      final p = pointFor(data.curve[i], data.curve[i].idealRetention);
      idealPath.lineTo(p.dx, p.dy);
    }
    final idealArea = Path.from(idealPath)
      ..lineTo(
        pointFor(data.curve.last, data.curve.last.idealRetention).dx,
        chart.bottom,
      )
      ..lineTo(
        pointFor(data.curve.first, data.curve.first.idealRetention).dx,
        chart.bottom,
      )
      ..close();
    canvas.drawPath(
      idealArea,
      Paint()..color = neuromathixBlue.withValues(alpha: 0.11),
    );

    final predictedPath = Path();
    final first = pointFor(
      data.curve.first,
      data.curve.first.predictedRetention,
    );
    predictedPath.moveTo(first.dx, first.dy);
    for (var i = 1; i < data.curve.length; i++) {
      final previous = pointFor(
        data.curve[i - 1],
        data.curve[i - 1].predictedRetention,
      );
      final current = pointFor(data.curve[i], data.curve[i].predictedRetention);
      final controlX = (previous.dx + current.dx) / 2;
      predictedPath.cubicTo(
        controlX,
        previous.dy,
        controlX,
        current.dy,
        current.dx,
        current.dy,
      );
    }

    final linePaint = Paint()
      ..color = neuromathixBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(predictedPath, linePaint);

    final currentPoint = data.currentPoint;
    final currentOffset = pointFor(
      currentPoint,
      currentPoint.predictedRetention,
    );
    final dashPaint = Paint()
      ..color = neuromathixBlue.withValues(alpha: 0.45)
      ..strokeWidth = 1.5;
    _drawDashedLine(
      canvas,
      Offset(currentOffset.dx, chart.top),
      Offset(currentOffset.dx, chart.bottom),
      dashPaint,
    );

    canvas.drawCircle(currentOffset, 18, Paint()..color = Colors.white);
    canvas.drawCircle(
      currentOffset,
      18,
      Paint()
        ..color = neuromathixBlue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );

    _drawCallout(canvas, currentOffset, size);
    _drawLegend(canvas, size);
    _drawLabels(canvas, size, chart, pointFor);
  }

  void _drawCallout(Canvas canvas, Offset anchor, Size size) {
    const width = 156.0;
    const height = 58.0;
    final left = (anchor.dx - width / 2)
        .clamp(0, size.width - width)
        .toDouble();
    final top = (anchor.dy - 108)
        .clamp(18, size.height - height - 50)
        .toDouble();
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, width, height),
      const Radius.circular(8),
    );
    canvas.drawRRect(rect, Paint()..color = neuromathixBlue);

    final triangle = Path()
      ..moveTo(anchor.dx - 13, top + height)
      ..lineTo(anchor.dx + 13, top + height)
      ..lineTo(anchor.dx, top + height + 17)
      ..close();
    canvas.drawPath(triangle, Paint()..color = neuromathixBlue);

    final textPainter = TextPainter(
      text: TextSpan(
        text: 'YOU ARE HERE',
        style: GoogleFonts.dmSans(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 14,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(left + (width - textPainter.width) / 2, top + 20),
    );
  }

  void _drawLegend(Canvas canvas, Size size) {
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final y = 2.0;
    final right = size.width - 8;

    textPainter.text = TextSpan(
      text: 'Ideal',
      style: GoogleFonts.dmSans(
        color: neuromathixMuted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(right - textPainter.width, y));
    canvas.drawCircle(
      Offset(right - textPainter.width - 10, y + 7),
      4,
      Paint()..color = const Color(0xFFD2D7E0),
    );

    final idealStart = right - textPainter.width - 56;
    textPainter.text = TextSpan(
      text: 'Predicted',
      style: GoogleFonts.dmSans(
        color: neuromathixMuted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(idealStart - textPainter.width, y));
    canvas.drawCircle(
      Offset(idealStart - textPainter.width - 10, y + 7),
      4,
      Paint()..color = neuromathixBlue,
    );
  }

  void _drawLabels(
    Canvas canvas,
    Size size,
    Rect chart,
    Offset Function(RetentionCurvePoint point, double value) pointFor,
  ) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    for (final point in data.curve) {
      final offset = pointFor(point, 0);
      textPainter.text = TextSpan(
        text: point.label,
        style: GoogleFonts.dmSans(
          color: point.isCurrent ? neuromathixBlue : neuromathixMuted,
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      );
      textPainter.layout(maxWidth: 90);
      textPainter.paint(
        canvas,
        Offset(offset.dx - textPainter.width / 2, chart.bottom + 16),
      );
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashHeight = 8.0;
    const dashSpace = 8.0;
    var y = start.dy;
    while (y < end.dy) {
      canvas.drawLine(
        Offset(start.dx, y),
        Offset(start.dx, (y + dashHeight).clamp(start.dy, end.dy).toDouble()),
        paint,
      );
      y += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _ForgettingCurvePainter oldDelegate) {
    return oldDelegate.data != data;
  }
}

/// One expandable card per question in the session — every question gets
/// its own real XAI explanation here, not just the single "focus" concept
/// shown in the header above. Incorrect answers start expanded (that's
/// where the detail matters most); correct ones start collapsed.
class _QuestionFeedbackList extends StatelessWidget {
  final List<QuestionFeedback> items;
  const _QuestionFeedbackList({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          _QuestionFeedbackCard(index: i + 1, item: items[i]),
          if (i != items.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _QuestionFeedbackCard extends StatefulWidget {
  final int index;
  final QuestionFeedback item;
  const _QuestionFeedbackCard({required this.index, required this.item});

  @override
  State<_QuestionFeedbackCard> createState() => _QuestionFeedbackCardState();
}

class _QuestionFeedbackCardState extends State<_QuestionFeedbackCard> {
  late bool _expanded = !widget.item.isCorrect;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final statusColor = item.isCorrect ? AppColors.success : AppColors.error;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: item.isCorrect ? neuromathixBorder : statusColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), shape: BoxShape.circle),
                    child: Icon(
                      item.isCorrect ? Icons.check_rounded : Icons.close_rounded,
                      size: 18,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Question ${widget.index} · ${item.topic}',
                          style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700, color: neuromathixMuted),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.questionText,
                          maxLines: _expanded ? null : 1,
                          overflow: _expanded ? null : TextOverflow.ellipsis,
                          style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w700, color: neuromathixText),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: neuromathixMuted),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1, color: neuromathixBorder),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _AnswerPill(
                          label: 'Your answer',
                          value: item.yourAnswer,
                          color: statusColor,
                        ),
                      ),
                      if (!item.isCorrect) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: _AnswerPill(
                            label: 'Correct answer',
                            value: item.correctAnswer,
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    item.xaiText,
                    style: GoogleFonts.dmSans(fontSize: 13.5, color: neuromathixText, height: 1.55),
                  ),
                  if (item.hintsUsed > 0) ...[
                    const SizedBox(height: 10),
                    Text(
                      '💡 ${item.hintsUsed} hint${item.hintsUsed == 1 ? '' : 's'} used on this question.',
                      style: GoogleFonts.dmSans(fontSize: 12, color: neuromathixMuted, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AnswerPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _AnswerPill({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w800, color: neuromathixMuted, letterSpacing: 0.6)),
          const SizedBox(height: 3),
          Text(value, style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w700, color: neuromathixText)),
        ],
      ),
    );
  }
}

class _FactorGrid extends StatelessWidget {
  final List<ExplanationFactor> factors;

  const _FactorGrid({required this.factors});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 780 ? 1 : 3;
        final width = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - 32) / 3;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: factors
              .map(
                (factor) => SizedBox(
                  width: width,
                  child: _FactorCard(factor: factor),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _FactorCard extends StatelessWidget {
  final ExplanationFactor factor;

  const _FactorCard({required this.factor});

  @override
  Widget build(BuildContext context) {
    final color = _toneColor(factor.tone);
    final icon = switch (factor.id) {
      'timeLapse' => Icons.schedule_rounded,
      'complexity' => Icons.account_tree_outlined,
      'pastPerformance' => Icons.history_rounded,
      'transfer' => Icons.compare_arrows_rounded,
      _ => Icons.insights_outlined,
    };

    return _WhitePanel(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 168),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: color.withValues(alpha: 0.14),
              child: Icon(icon, color: color, size: 23),
            ),
            const SizedBox(height: 22),
            Text(
              factor.title,
              style: GoogleFonts.dmSans(
                color: neuromathixMuted,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              factor.value,
              style: GoogleFonts.dmSans(
                color: neuromathixText,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              factor.description,
              style: GoogleFonts.dmSans(
                color: neuromathixMuted,
                fontSize: 15,
                height: 1.38,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuidanceCard extends StatelessWidget {
  final AiFeedbackData data;

  const _GuidanceCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD6E7FF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.sentiment_satisfied_alt_rounded,
              color: neuromathixBlue,
            ),
          ),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.guidanceTitle,
                  style: GoogleFonts.dmSans(
                    color: neuromathixText,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  data.guidanceBody,
                  style: GoogleFonts.dmSans(
                    color: neuromathixMuted,
                    fontSize: 16,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportDialog extends StatelessWidget {
  final FeedbackReport report;

  const _ReportDialog({required this.report});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(report.title),
      content: SizedBox(
        width: 900,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Generated for ${report.generatedFor}',
                style: GoogleFonts.dmSans(
                  color: neuromathixMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingTextStyle: GoogleFonts.dmSans(
                    fontWeight: FontWeight.w900,
                    color: neuromathixText,
                  ),
                  dataTextStyle: GoogleFonts.dmSans(
                    color: neuromathixMuted,
                    fontWeight: FontWeight.w600,
                  ),
                  columns: const [
                    DataColumn(label: Text('Metric')),
                    DataColumn(label: Text('Value')),
                    DataColumn(label: Text('Interpretation')),
                    DataColumn(label: Text('Recommendation')),
                  ],
                  rows: report.rows
                      .map(
                        (row) => DataRow(
                          cells: [
                            DataCell(Text(row.metric)),
                            DataCell(Text(row.value)),
                            DataCell(
                              SizedBox(
                                width: 220,
                                child: Text(row.interpretation),
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 220,
                                child: Text(row.recommendation),
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: neuromathixSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: neuromathixBorder),
                ),
                child: SelectableText(
                  report.asMarkdownTable(),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: report.asMarkdownTable()),
            );
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Report copied to clipboard.')),
            );
          },
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Copy Report'),
        ),
      ],
    );
  }
}

class _WhitePanel extends StatelessWidget {
  final Widget child;

  const _WhitePanel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
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

Color _toneColor(String tone) {
  switch (tone) {
    case 'green':
      return const Color(0xFF45B86B);
    case 'orange':
      return const Color(0xFFFF7B22);
    case 'purple':
      return const Color(0xFF9A42F2);
    case 'blue':
    default:
      return neuromathixBlue;
  }
}