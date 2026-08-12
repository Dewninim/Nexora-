import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/upload_provider.dart';
import '../pages/learning_session_screen.dart';

const Color _accentBlue  = Color(0xFF1B63E8);
const Color _textPrimary = Color(0xFF0F172A);
const Color _textSub     = Color(0xFF64748B);
const Color _textMuted   = Color(0xFF94A3B8);
const Color _success     = Color(0xFF10B981);

// Reads backend/app.py's real SHAP TreeExplainer output for Model 1's
// difficulty prediction (difficulty_summary.difficulty_explanation, set in
// the /upload response) — not derived or invented here, just parsed.
List<Map<String, dynamic>> _shapWords(Map<String, dynamic>? difficultySummary) {
  final raw = difficultySummary?['difficulty_explanation'];
  if (raw is! List) return const [];
  return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

class LearningSetupCard extends StatefulWidget {
  const LearningSetupCard({super.key});

  @override
  State<LearningSetupCard> createState() => _SetupState();
}

class _SetupState extends State<LearningSetupCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 480))
    ..forward();
  late final Animation<double> _fade =
      CurvedAnimation(parent: _ac, curve: Curves.easeOut);
  late final Animation<Offset> _slide =
      Tween(begin: const Offset(0, .05), end: Offset.zero)
          .animate(CurvedAnimation(parent: _ac, curve: Curves.easeOut));

  final _daysCtrl = TextEditingController();

  @override
  void dispose() {
    _ac.dispose();
    _daysCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UploadProvider>(
      builder: (context, provider, _) {
        final s       = provider.state;
        final isFixed = s.studyMode == StudyMode.fixedPeriod;

        return FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 6))
                ],
              ),
              child: Column(
                children: [
                  // ── Success header ────────────────────────────────────
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(28, 36, 28, 24),
                    child: Column(children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: _success.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                            Icons.check_circle_rounded,
                            color: _success,
                            size: 32),
                      ),
                      const SizedBox(height: 14),
                      Text('File Successfully Uploaded',
                          style: GoogleFonts.openSans(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: _textPrimary)),
                      const SizedBox(height: 6),
                      Text(
                        'Your study materials have been processed.\nNow, let\'s customize your learning path.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.openSans(
                            fontSize: 13.5,
                            color: _textSub,
                            height: 1.55),
                      ),
                    ]),
                  ),

                  if (_shapWords(s.difficultySummary).isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
                      child: _DifficultyExplanationPanel(
                        avgScore: (s.difficultySummary?['avg_score'] as num?)?.toDouble(),
                        words: _shapWords(s.difficultySummary),
                      ),
                    ),
                  ],

                  const Divider(height: 1, color: Color(0xFFE8ECF0)),

                  // ── Form ──────────────────────────────────────────────
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(28, 26, 28, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Learning Setup',
                            style: GoogleFonts.openSans(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: _textPrimary)),

                        const SizedBox(height: 20),
                        _label('Study Mode'),
                        const SizedBox(height: 10),

                        _ModeOption(
                          selected: isFixed,
                          title: 'Learn for selected time period',
                          description:
                              'Focus on completing the curriculum within your specified deadline.',
                          onTap: () => provider
                              .setMode(StudyMode.fixedPeriod),
                        ),
                        const SizedBox(height: 8),

                        _ModeOption(
                          selected: !isFixed,
                          title:
                              'Continue until mastery is achieved',
                          description:
                              'AI dynamically adjusts content until you\'ve fully grasped the concepts.',
                          onTap: () => provider
                              .setMode(StudyMode.untilMastery),
                        ),

                        const SizedBox(height: 20),

                        AnimatedSwitcher(
                          duration:
                              const Duration(milliseconds: 280),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, anim) =>
                              FadeTransition(
                            opacity: anim,
                            child: SizeTransition(
                                sizeFactor: anim,
                                axisAlignment: -1,
                                child: child),
                          ),
                          child: isFixed
                              ? Column(
                                  key: const ValueKey('days'),
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    _label('Learning Time Period'),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: _daysCtrl,
                                      keyboardType:
                                          TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter
                                            .digitsOnly
                                      ],
                                      onChanged: (v) {
                                        final d = int.tryParse(v);
                                        if (d != null) {
                                          provider.setDays(d);
                                        }
                                      },
                                      style: GoogleFonts.openSans(
                                          fontSize: 14,
                                          color: _textPrimary),
                                      decoration: InputDecoration(
                                        hintText: 'e.g.  30',
                                        hintStyle:
                                            GoogleFonts.openSans(
                                                color: _textMuted),
                                        suffixText: 'Days',
                                        suffixStyle:
                                            GoogleFonts.openSans(
                                                color: _textMuted,
                                                fontSize: 13),
                                        filled: true,
                                        fillColor: const Color(
                                            0xFFF8F9FC),
                                        contentPadding:
                                            const EdgeInsets
                                                .symmetric(
                                                horizontal: 16,
                                                vertical: 14),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(
                                                  10),
                                          borderSide:
                                              const BorderSide(
                                                  color: Color(
                                                      0xFFE2E8F0)),
                                        ),
                                        enabledBorder:
                                            OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(
                                                  10),
                                          borderSide:
                                              const BorderSide(
                                                  color: Color(
                                                      0xFFE2E8F0)),
                                        ),
                                        focusedBorder:
                                            OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(
                                                  10),
                                          borderSide:
                                              const BorderSide(
                                                  color: _accentBlue,
                                                  width: 1.5),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                  ],
                                )
                              : Container(
                                  key: const ValueKey('mastery'),
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(
                                      bottom: 20),
                                  padding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius:
                                        BorderRadius.circular(12),
                                    border: Border.all(
                                        color: const Color(
                                            0xFFBFDBFE)),
                                  ),
                                  child: Row(children: [
                                    const Icon(
                                        Icons.auto_awesome_rounded,
                                        color: _accentBlue,
                                        size: 18),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Duration: Until mastery is achieved — AI will keep going until you\'re ready.',
                                        style: GoogleFonts.openSans(
                                            fontSize: 13,
                                            color: _accentBlue,
                                            fontWeight:
                                                FontWeight.w500,
                                            height: 1.4),
                                      ),
                                    ),
                                  ]),
                                ),
                        ),

                        // ── CTA ──────────────────────────────────────
                        _StartButton(
                          loading: s.starting,
                          onTap: () async {
                            final sessionId = s.sessionId;
                            if (sessionId == null) return;
                            await provider.startLearning();
                            if (!context.mounted) return;
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => LearningSessionScreen(
                                  sessionId: sessionId,
                                  studyMode: isFixed ? 'fixed' : 'until_mastery',
                                  studyDays: s.learningDays ?? 7,
                                  fileName: s.fileName ?? 'Study Material',
                                ),
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                            'You can change these settings later in your dashboard.',
                            style: GoogleFonts.openSans(
                                fontSize: 12, color: _textMuted),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Footer ────────────────────────────────────────────
                  Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FC),
                      border: Border(
                          top: BorderSide(color: Color(0xFFE2E8F0))),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(20),
                        bottomRight: Radius.circular(20),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '© 2026 NuroMathix AI Learning. All rights reserved.',
                        style: GoogleFonts.openSans(
                            fontSize: 11, color: _textMuted),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _label(String t) => Text(t,
      style: GoogleFonts.openSans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: _textSub));
}

// ── Mode option ───────────────────────────────────────────────────────────────

class _ModeOption extends StatefulWidget {
  final bool selected;
  final String title, description;
  final VoidCallback onTap;
  const _ModeOption(
      {required this.selected,
      required this.title,
      required this.description,
      required this.onTap});
  @override
  State<_ModeOption> createState() => _ModeOptionState();
}

class _ModeOptionState extends State<_ModeOption> {
  bool _hov = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit:  (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: widget.selected
                ? const Color(0xFFEFF6FF)
                : _hov
                    ? const Color(0xFFF8FAFF)
                    : const Color(0xFFF8F9FC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.selected
                  ? _accentBlue
                  : const Color(0xFFE2E8F0),
              width: widget.selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 20,
                height: 20,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.selected
                      ? _accentBlue
                      : Colors.white,
                  border: Border.all(
                    color: widget.selected
                        ? _accentBlue
                        : const Color(0xFFCBD5E1),
                    width: 2,
                  ),
                ),
                child: widget.selected
                    ? const Center(
                        child: CircleAvatar(
                            radius: 4,
                            backgroundColor: Colors.white))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: GoogleFonts.openSans(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: widget.selected
                                ? _accentBlue
                                : _textPrimary)),
                    const SizedBox(height: 3),
                    Text(widget.description,
                        style: GoogleFonts.openSans(
                            fontSize: 12.5,
                            height: 1.45,
                            color: widget.selected
                                ? const Color(0xFF3B82F6)
                                : _textMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Start button ──────────────────────────────────────────────────────────────

class _StartButton extends StatefulWidget {
  final bool loading;
  final VoidCallback onTap;
  const _StartButton({required this.loading, required this.onTap});
  @override
  State<_StartButton> createState() => _StartButtonState();
}

class _StartButtonState extends State<_StartButton> {
  bool _hov = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit:  (_) => setState(() => _hov = false),
      child: GestureDetector(
        onTap: widget.loading ? null : widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: _hov
                ? const Color(0xFF1D4ED8)
                : _accentBlue,
            borderRadius: BorderRadius.circular(12),
            boxShadow: _hov
                ? [
                    BoxShadow(
                        color: _accentBlue.withOpacity(0.38),
                        blurRadius: 18,
                        offset: const Offset(0, 6))
                  ]
                : [],
          ),
          child: widget.loading
              ? const Center(
                  child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5)))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Start Learning',
                        style: GoogleFonts.openSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded,
                        color: Colors.white, size: 18),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Real SHAP (TreeExplainer) feature attribution for Model 1's difficulty
/// score on this material's hardest sections — which words in the text
/// actually pushed the RandomForest toward that rating. Not Gemini-authored
/// text (SHAP doesn't apply to the free-text grading XAI shown elsewhere in
/// the app) — every word/number here comes straight from
/// backend/app.py:explain_difficulty().
class _DifficultyExplanationPanel extends StatelessWidget {
  final double? avgScore;
  final List<Map<String, dynamic>> words;

  const _DifficultyExplanationPanel({required this.avgScore, required this.words});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.query_stats_rounded, size: 17, color: _accentBlue),
              const SizedBox(width: 8),
              Text(
                'Why we rated the hardest sections this way (SHAP)',
                style: GoogleFonts.openSans(fontSize: 13, fontWeight: FontWeight.w700, color: _textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            avgScore != null
                ? 'Average difficulty ${avgScore!.toStringAsFixed(1)}/5 — feature attribution from Model 1\'s RandomForest classifier.'
                : 'Feature attribution from Model 1\'s RandomForest classifier.',
            style: GoogleFonts.openSans(fontSize: 11.5, color: _textMuted),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: words.map((w) {
              final increases = w['direction'] == 'increases';
              final color = increases ? const Color(0xFFDC2626) : const Color(0xFF16A34A);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(increases ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                        size: 12, color: color),
                    const SizedBox(width: 4),
                    Text(
                      '${w['word']}',
                      style: GoogleFonts.openSans(fontSize: 12, fontWeight: FontWeight.w700, color: _textPrimary),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
