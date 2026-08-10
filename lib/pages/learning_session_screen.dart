// lib/screens/learning_session_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// LEARNING SESSION / QUIZ PAGE
//  - Session title + progress % top bar
//  - Numbered step indicators (1–N), sequential unlock
//  - Question cards: COMPLETED / TIME EXCEEDED / timer / PENDING states
//  - Three question formats, matching the backend exactly:
//      fill_blank   -> multiple choice (A/B/C/D)
//      short_answer -> single typed answer
//      multi_part   -> 4 typed sub-answers (a/b/c/d)
//  - Hint button -> calls the real /hint endpoint, progressive levels, XAI-explained
//  - Per-question timer that only runs for the ACTIVE question. On timeout,
//    the student is asked to continue (tracked as red "overtime") or move on.
//  - Submit Final Answer button
//  - Results view with XAI explanations, Model 1 difficulty, timeout/overtime badges
//  - Forgetting curve + next session schedule
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/student_learning_models.dart';
import '../services/review_schedule_service.dart';
import '../theme/app_theme.dart';
import 'explainable_ai_feedback_page.dart';

// ══════════════════════════════════════════════════════════════════════════════
// DATA MODELS
// ══════════════════════════════════════════════════════════════════════════════

class SubPart {
  final String id;
  final String prompt;
  const SubPart({required this.id, required this.prompt});

  factory SubPart.fromJson(Map<String, dynamic> j) => SubPart(
        id:     j['id'] as String? ?? '',
        prompt: j['prompt'] as String? ?? '',
      );
}

class SessionQuestion {
  final String id;
  final String topic;
  final List<String> topicTags;
  final String questionType;   // easy / medium / hard  (difficulty tier)
  final String format;         // fill_blank / short_answer / multi_part
  final String questionText;
  final List<String> options;      // fill_blank only
  final List<SubPart> subParts;    // multi_part only
  final int difficultyScore;
  final String difficultyLevel;
  final int timeAllottedSeconds;
  final int? model1DifficultyScore;
  final String? model1DifficultyLevel;
  final double? model1Confidence;
  final String? model1Source;
  final bool grounded;

  const SessionQuestion({
    required this.id,
    required this.topic,
    required this.topicTags,
    required this.questionType,
    required this.format,
    required this.questionText,
    required this.options,
    required this.subParts,
    required this.difficultyScore,
    required this.difficultyLevel,
    required this.timeAllottedSeconds,
    this.model1DifficultyScore,
    this.model1DifficultyLevel,
    this.model1Confidence,
    this.model1Source,
    this.grounded = true,
  });

  factory SessionQuestion.fromJson(Map<String, dynamic> j) => SessionQuestion(
        id:              j['id'] as String? ?? 'q1',
        topic:           j['topic'] as String? ?? 'General',
        topicTags:       List<String>.from(j['topic_tags'] as List? ?? []),
        questionType:    j['question_type'] as String? ?? 'medium',
        format:          j['format'] as String? ?? 'fill_blank',
        questionText:    j['question_text'] as String? ?? '',
        options:         List<String>.from(j['options'] as List? ?? []),
        subParts:        (j['sub_parts'] as List? ?? [])
            .map((sp) => SubPart.fromJson(sp as Map<String, dynamic>))
            .toList(),
        difficultyScore: j['difficulty_score'] as int? ?? 3,
        difficultyLevel: j['difficulty_level'] as String? ?? 'medium',
        timeAllottedSeconds: (j['time_allotted_seconds'] as num?)?.toInt() ?? 90,
        model1DifficultyScore: (j['model1_difficulty_score'] as num?)?.toInt(),
        model1DifficultyLevel: j['model1_difficulty_level'] as String?,
        model1Confidence: (j['model1_confidence'] as num?)?.toDouble(),
        model1Source: j['model1_source'] as String?,
        grounded: j['grounded'] as bool? ?? true,
      );
}

class QuestionResult {
  final String questionId;
  final String questionText;
  final String topic;
  final String format;
  final Map<String, dynamic> answer;         // what the student submitted
  final Map<String, dynamic> correctAnswer;  // revealed only after grading
  final bool isCorrect;
  final double score;
  final double timeTaken;
  final int timeAllottedSeconds;
  final bool timedOut;
  final double overtimeSeconds;
  final bool continuedAfterTimeout;
  final List<Map<String, dynamic>> hintsUsed;
  final Map<String, dynamic> xai;
  final int? model1DifficultyScore;
  final String? model1DifficultyLevel;
  final double? model1Confidence;
  final String? model1Source;

  const QuestionResult({
    required this.questionId,
    required this.questionText,
    required this.topic,
    required this.format,
    required this.answer,
    required this.correctAnswer,
    required this.isCorrect,
    required this.score,
    required this.timeTaken,
    required this.timeAllottedSeconds,
    required this.timedOut,
    required this.overtimeSeconds,
    required this.continuedAfterTimeout,
    required this.hintsUsed,
    required this.xai,
    this.model1DifficultyScore,
    this.model1DifficultyLevel,
    this.model1Confidence,
    this.model1Source,
  });

  factory QuestionResult.fromJson(Map<String, dynamic> j) => QuestionResult(
        questionId:    j['question_id'] as String? ?? '',
        questionText:  j['question_text'] as String? ?? '',
        topic:         j['topic'] as String? ?? '',
        format:        j['format'] as String? ?? 'fill_blank',
        answer:        Map<String, dynamic>.from(j['answer'] as Map? ?? {}),
        correctAnswer: Map<String, dynamic>.from(j['correct_answer'] as Map? ?? {}),
        isCorrect:     j['is_correct'] as bool? ?? false,
        score:         (j['score'] as num?)?.toDouble() ?? 0.0,
        timeTaken:     (j['time_taken'] as num?)?.toDouble() ?? 0,
        timeAllottedSeconds: (j['time_allotted_seconds'] as num?)?.toInt() ?? 90,
        timedOut:      j['timed_out'] as bool? ?? false,
        overtimeSeconds: (j['overtime_seconds'] as num?)?.toDouble() ?? 0.0,
        continuedAfterTimeout: j['continued_after_timeout'] as bool? ?? false,
        hintsUsed: (j['hints_used'] as List? ?? [])
            .map((h) => Map<String, dynamic>.from(h as Map))
            .toList(),
        xai:           Map<String, dynamic>.from(j['xai'] as Map? ?? {}),
        model1DifficultyScore: (j['model1_difficulty_score'] as num?)?.toInt(),
        model1DifficultyLevel: j['model1_difficulty_level'] as String?,
        model1Confidence: (j['model1_confidence'] as num?)?.toDouble(),
        model1Source: j['model1_source'] as String?,
      );

  /// Human-readable "what the student answered", per format.
  String get yourAnswerText {
    switch (format) {
      case 'fill_blank':
        return answer['selected_text'] as String? ?? '(no answer)';
      case 'short_answer':
        final t = answer['answer_text'] as String? ?? '';
        return t.trim().isEmpty ? '(no answer)' : t;
      case 'multi_part':
        final subs = Map<String, dynamic>.from(answer['sub_answers'] as Map? ?? {});
        if (subs.isEmpty) return '(no answer)';
        return subs.entries.map((e) => '${e.key}) ${e.value}').join('   ');
      default:
        return '(no answer)';
    }
  }

  /// Human-readable correct answer, per format.
  String get correctAnswerText {
    switch (format) {
      case 'fill_blank':
        return correctAnswer['correct_text'] as String? ?? '—';
      case 'short_answer':
        return correctAnswer['expected_answer']?.toString() ?? '—';
      case 'multi_part':
        final subs = (correctAnswer['sub_parts'] as List? ?? [])
            .map((sp) => Map<String, dynamic>.from(sp as Map));
        if (subs.isEmpty) return '—';
        return subs
            .map((sp) => '${sp['id']}) ${sp['expected_answer']}')
            .join('   ');
      default:
        return '—';
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// API SERVICE
// ══════════════════════════════════════════════════════════════════════════════

const String _base = kApiBaseUrl;

Future<List<SessionQuestion>> apiStartSession(String sessionId) async {
  final r = await http.get(
    Uri.parse('$_base/session/$sessionId/questions'),
    headers: {'Content-Type': 'application/json'},
  ).timeout(const Duration(seconds: 90));

  if (r.statusCode != 200) {
    final b = jsonDecode(r.body);
    throw Exception(b['error'] ?? 'Failed to start session');
  }
  final data = jsonDecode(r.body) as Map<String, dynamic>;
  return (data['questions'] as List)
      .map((q) => SessionQuestion.fromJson(q as Map<String, dynamic>))
      .toList();
}

/// Fetches ONE progressive hint from the backend's real XAI hint endpoint.
/// [currentAnswer] is whatever the student has typed/selected so far, so the
/// hint can be contextual (e.g. "you're on the right track" vs "start here").
Future<Map<String, dynamic>> apiGetHint({
  required String sessionId,
  required String questionId,
  required int hintLevel,
  required String currentAnswer,
}) async {
  final r = await http.post(
    Uri.parse('$_base/session/$sessionId/question/$questionId/hint'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'hint_level': hintLevel, 'current_answer': currentAnswer}),
  ).timeout(const Duration(seconds: 30));

  if (r.statusCode != 200) {
    final b = jsonDecode(r.body);
    throw Exception(b['error'] ?? 'Failed to get hint');
  }
  return jsonDecode(r.body) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> apiSubmitAnswers(
    String sessionId, List<Map<String, dynamic>> answers) async {
  final r = await http.post(
    Uri.parse('$_base/session/$sessionId/submit'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'answers': answers}),
  ).timeout(const Duration(seconds: 120));

  if (r.statusCode != 200) {
    final b = jsonDecode(r.body);
    throw Exception(b['error'] ?? 'Failed to submit');
  }
  return jsonDecode(r.body) as Map<String, dynamic>;
}

// ══════════════════════════════════════════════════════════════════════════════
// STATE
// ══════════════════════════════════════════════════════════════════════════════

enum SessionPhase { loading, questioning, submitting, results, error }

class _QuestionRuntime {
  // fill_blank
  final int? selectedIndex;
  // short_answer
  final String answerText;
  // multi_part  (sub-part id -> typed value)
  final Map<String, String> subAnswers;

  final bool hintLoading;
  final List<Map<String, dynamic>> hintsUsed; // [{level, hint_text}]
  final DateTime? startedAt;   // null until this question becomes ACTIVE
  final bool confirmed;        // answer locked in (by student, or by "move on")
  final bool timedOut;         // allotted time reached at least once
  final bool continuedAfterTimeout; // student chose to keep trying past the limit
  final bool timeoutPromptShown;    // so the dialog only fires once
  final int overtimeSeconds;        // extra time spent AFTER timedOut, tracked separately

  const _QuestionRuntime({
    this.selectedIndex,
    this.answerText = '',
    this.subAnswers = const {},
    this.hintLoading = false,
    this.hintsUsed = const [],
    this.startedAt,
    this.confirmed = false,
    this.timedOut = false,
    this.continuedAfterTimeout = false,
    this.timeoutPromptShown = false,
    this.overtimeSeconds = 0,
  });

  _QuestionRuntime copyWith({
    int? selectedIndex,
    bool clearSelectedIndex = false,
    String? answerText,
    Map<String, String>? subAnswers,
    bool? hintLoading,
    List<Map<String, dynamic>>? hintsUsed,
    DateTime? startedAt,
    bool? confirmed,
    bool? timedOut,
    bool? continuedAfterTimeout,
    bool? timeoutPromptShown,
    int? overtimeSeconds,
  }) =>
      _QuestionRuntime(
        selectedIndex: clearSelectedIndex ? null : (selectedIndex ?? this.selectedIndex),
        answerText:    answerText    ?? this.answerText,
        subAnswers:    subAnswers    ?? this.subAnswers,
        hintLoading:   hintLoading   ?? this.hintLoading,
        hintsUsed:     hintsUsed     ?? this.hintsUsed,
        startedAt:     startedAt     ?? this.startedAt,
        confirmed:     confirmed     ?? this.confirmed,
        timedOut:      timedOut      ?? this.timedOut,
        continuedAfterTimeout: continuedAfterTimeout ?? this.continuedAfterTimeout,
        timeoutPromptShown:    timeoutPromptShown    ?? this.timeoutPromptShown,
        overtimeSeconds:       overtimeSeconds        ?? this.overtimeSeconds,
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class LearningSessionScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final String studyMode;
  final int    studyDays;
  final String fileName;

  const LearningSessionScreen({
    super.key,
    required this.sessionId,
    required this.studyMode,
    required this.studyDays,
    required this.fileName,
  });

  @override
  ConsumerState<LearningSessionScreen> createState() =>
      _LearningSessionScreenState();
}

class _LearningSessionScreenState
    extends ConsumerState<LearningSessionScreen> {
  // ── State ─────────────────────────────────────────────────────────────────
  SessionPhase           _phase    = SessionPhase.loading;
  List<SessionQuestion>  _questions = [];
  List<_QuestionRuntime> _runtimes  = [];
  Map<String, dynamic>?  _submitResult;
  String?                _error;

  // Per-question timers (elapsed seconds) — ONLY the active question's
  // entry advances. Locked/pending questions never accumulate time, so
  // one question timing out can never cascade into every later question
  // showing "TIME EXCEEDED" before the student has even seen them.
  final Map<int, int> _elapsed = {};
  Timer? _globalTimer;

  // ── Init ──────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  @override
  void dispose() {
    _globalTimer?.cancel();
    super.dispose();
  }

  // ── Load questions ───────────────────────────────────────────────────────
  Future<void> _loadQuestions() async {
    setState(() { _phase = SessionPhase.loading; _error = null; });
    try {
      final qs = await apiStartSession(widget.sessionId);
      setState(() {
        _questions = qs;
        _elapsed.clear();
        // Only question 0 starts "active" (its clock begins now). Every
        // other question stays unstarted (startedAt: null) until it's
        // unlocked, which is when we stamp its startedAt in _activateNext().
        _runtimes = List.generate(qs.length, (i) =>
            _QuestionRuntime(startedAt: i == 0 ? DateTime.now() : null));
        _phase = SessionPhase.questioning;
      });
      _startGlobalTimer();
    } catch (e) {
      setState(() { _phase = SessionPhase.error; _error = e.toString(); });
    }
  }

  // ── Which question is currently active (unlocked + not yet confirmed) ────
  int? get _activeIndex {
    for (int i = 0; i < _questions.length; i++) {
      if (!_runtimes[i].confirmed) return i;
    }
    return null;
  }

  void _startGlobalTimer() {
    _globalTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_phase != SessionPhase.questioning) return;
      final active = _activeIndex;
      if (active == null) return;
      final rt = _runtimes[active];
      if (rt.startedAt == null) return; // safety guard

      setState(() {
        _elapsed[active] = (_elapsed[active] ?? 0) + 1;
        final allotted = _questions[active].timeAllottedSeconds;
        final e = _elapsed[active]!;

        if (e >= allotted && !rt.timedOut) {
          // First time crossing the limit on THIS question only.
          _runtimes[active] = rt.copyWith(timedOut: true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showTimeoutPrompt(active);
          });
        } else if (rt.timedOut && rt.continuedAfterTimeout) {
          // Past the limit and the student chose to keep going —
          // track this extra time separately (shown in red).
          final overtime = e - allotted;
          _runtimes[active] =
              _runtimes[active].copyWith(overtimeSeconds: overtime);
        }
      });
    });
  }

  // ── Timeout decision dialog ──────────────────────────────────────────────
  void _showTimeoutPrompt(int qIndex) {
    if (!mounted) return;
    final rt = _runtimes[qIndex];
    if (rt.confirmed || rt.timeoutPromptShown) return;
    setState(() {
      _runtimes[qIndex] = _runtimes[qIndex].copyWith(timeoutPromptShown: true);
    });

    final q = _questions[qIndex];
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            const Icon(Icons.timer_off_outlined, color: Color(0xFFDC2626)),
            const SizedBox(width: 10),
            Text('Time\'s up!',
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w800)),
          ],
        ),
        content: Text(
          'You\'ve used the allotted ${q.timeAllottedSeconds}s for this question '
          '(${q.topic}). You can keep trying — the extra time will be tracked '
          'separately and shown in red — or move on and come back to it later.',
          style: GoogleFonts.dmSans(fontSize: 13.5, height: 1.5),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _moveOnFromTimeout(qIndex);
            },
            child: Text('Move On',
                style: GoogleFonts.dmSans(
                    color: const Color(0xFF6B7280), fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() {
                _runtimes[qIndex] =
                    _runtimes[qIndex].copyWith(continuedAfterTimeout: true);
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Continue Trying'),
          ),
        ],
      ),
    );
  }

  /// Student chose to skip a timed-out question rather than keep trying.
  /// Locks in whatever (possibly empty) answer they had, marks it timed
  /// out with no continuation, and unlocks the next question.
  void _moveOnFromTimeout(int qIndex) {
    setState(() {
      _runtimes[qIndex] = _runtimes[qIndex].copyWith(
        confirmed: true,
        continuedAfterTimeout: false,
      );
      _activateNext(qIndex);
    });
  }

  void _activateNext(int justConfirmedIndex) {
    final next = justConfirmedIndex + 1;
    if (next < _runtimes.length && _runtimes[next].startedAt == null) {
      _runtimes[next] = _runtimes[next].copyWith(startedAt: DateTime.now());
    }
  }

  // ── Answer interactions ───────────────────────────────────────────────────
  void _selectOption(int qIndex, int optIndex) {
    if (_runtimes[qIndex].confirmed) return;
    setState(() {
      _runtimes[qIndex] = _runtimes[qIndex].copyWith(selectedIndex: optIndex);
    });
  }

  void _setAnswerText(int qIndex, String text) {
    if (_runtimes[qIndex].confirmed) return;
    setState(() {
      _runtimes[qIndex] = _runtimes[qIndex].copyWith(answerText: text);
    });
  }

  void _setSubAnswer(int qIndex, String subId, String text) {
    if (_runtimes[qIndex].confirmed) return;
    setState(() {
      final updated = Map<String, String>.from(_runtimes[qIndex].subAnswers);
      updated[subId] = text;
      _runtimes[qIndex] = _runtimes[qIndex].copyWith(subAnswers: updated);
    });
  }

  bool _hasAnswer(int qIndex) {
    final q  = _questions[qIndex];
    final rt = _runtimes[qIndex];
    switch (q.format) {
      case 'fill_blank':
        return rt.selectedIndex != null;
      case 'short_answer':
        return rt.answerText.trim().isNotEmpty;
      case 'multi_part':
        return q.subParts.any((sp) => (rt.subAnswers[sp.id] ?? '').trim().isNotEmpty);
      default:
        return false;
    }
  }

  void _confirmAnswer(int qIndex) {
    if (!_hasAnswer(qIndex)) return;
    setState(() {
      _runtimes[qIndex] = _runtimes[qIndex].copyWith(confirmed: true);
      _activateNext(qIndex);
    });
  }

  // ── Hints — real progressive XAI hints from the backend ─────────────────
  String _currentAnswerForHint(int qIndex) {
    final q  = _questions[qIndex];
    final rt = _runtimes[qIndex];
    switch (q.format) {
      case 'fill_blank':
        return (rt.selectedIndex != null && rt.selectedIndex! < q.options.length)
            ? q.options[rt.selectedIndex!]
            : '';
      case 'short_answer':
        return rt.answerText;
      case 'multi_part':
        return rt.subAnswers.entries.map((e) => '${e.key}=${e.value}').join(', ');
      default:
        return '';
    }
  }

  Future<void> _useHint(int qIndex) async {
    final rt = _runtimes[qIndex];
    if (rt.hintLoading || rt.confirmed) return;
    if (rt.hintsUsed.length >= 10) return; // MAX_HINT_LEVEL on the backend

    setState(() {
      _runtimes[qIndex] = rt.copyWith(hintLoading: true);
    });
    final nextLevel = rt.hintsUsed.length + 1;
    try {
      final res = await apiGetHint(
        sessionId: widget.sessionId,
        questionId: _questions[qIndex].id,
        hintLevel: nextLevel,
        currentAnswer: _currentAnswerForHint(qIndex),
      );
      if (!mounted) return;
      setState(() {
        final updated = List<Map<String, dynamic>>.from(_runtimes[qIndex].hintsUsed)
          ..add({'level': nextLevel, 'hint_text': res['hint_text']});
        _runtimes[qIndex] =
            _runtimes[qIndex].copyWith(hintsUsed: updated, hintLoading: false);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _runtimes[qIndex] = _runtimes[qIndex].copyWith(hintLoading: false); });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load hint: $e')),
      );
    }
  }

  // ── Submit all ────────────────────────────────────────────────────────────
  Future<void> _submitAll() async {
    setState(() { _phase = SessionPhase.submitting; });
    _globalTimer?.cancel();

    final answers = <Map<String, dynamic>>[];
    for (int i = 0; i < _questions.length; i++) {
      final rt = _runtimes[i];
      final q  = _questions[i];
      final totalTime = (_elapsed[i] ?? 0).toDouble();

      final ans = <String, dynamic>{
        'question_id': q.id,
        'time_taken': totalTime,
        'timed_out': rt.timedOut,
        'overtime_seconds': rt.overtimeSeconds.toDouble(),
        'continued_after_timeout': rt.continuedAfterTimeout,
        'hints_used': rt.hintsUsed,
      };
      switch (q.format) {
        case 'fill_blank':
          ans['selected_index'] = rt.selectedIndex ?? -1;
          break;
        case 'short_answer':
          ans['answer_text'] = rt.answerText;
          break;
        case 'multi_part':
          ans['sub_answers'] = rt.subAnswers;
          break;
      }
      answers.add(ans);
    }

    try {
      final result = await apiSubmitAnswers(widget.sessionId, answers);
      setState(() {
        _submitResult = result;
        _phase        = SessionPhase.results;
      });
      // Mirror the completed session into Firestore so the teacher
      // dashboard and Cloud Functions notifications have real data — the
      // Flask/Mongo response above stays the source of truth either way,
      // so a failure here must never block the student seeing results.
      unawaited(
        ReviewScheduleService()
            .saveFromSessionResult(result: result, fileName: widget.fileName)
            .then((_) {})
            .catchError((_) {}),
      );
    } catch (e) {
      setState(() { _phase = SessionPhase.error; _error = e.toString(); });
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  int get _answeredCount => _runtimes.where((r) => r.confirmed).length;
  double get _progress   => _questions.isEmpty ? 0 : _answeredCount / _questions.length;

  String _fmtTime(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F8),
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios,
                color: Colors.white, size: 16),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 12),
          Text('NUROMATHIX',
              style: GoogleFonts.dmSans(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 1.5)),
          const Spacer(),
          if (_phase == SessionPhase.questioning) ...[
            Icon(Icons.notifications_outlined,
                color: Colors.white.withOpacity(0.7), size: 20),
            const SizedBox(width: 16),
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                  color: AppColors.accent, shape: BoxShape.circle),
              child: const Center(
                child: Text('R',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Body router ───────────────────────────────────────────────────────────
  Widget _buildBody() {
    return switch (_phase) {
      SessionPhase.loading     => _LoadingView(key: const ValueKey('l')),
      SessionPhase.questioning => _buildQuizBody(),
      SessionPhase.submitting  => _SubmittingView(key: const ValueKey('s')),
      SessionPhase.results     => _ResultsView(
          key: const ValueKey('r'),
          result: _submitResult!,
          questions: _questions,
          studyMode: widget.studyMode,
          studyDays: widget.studyDays,
        ),
      SessionPhase.error => _buildErrorView(),
    };
  }

  // ══════════════════════════════════════════════════════════════════════════
  // QUIZ BODY
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildQuizBody() {
    final sessionTitle = widget.fileName.replaceAll('.pdf', '');

    return Column(
      key: const ValueKey('quiz'),
      children: [
        // ── Session header bar ────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          color: Colors.white,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      sessionTitle.length > 50
                          ? '${sessionTitle.substring(0, 50)}…'
                          : sessionTitle,
                      style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary),
                    ),
                  ),
                  Text(
                    'Session Progress ${(_progress * 100).round()}%',
                    style: GoogleFonts.dmSans(
                        fontSize: 11.5,
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 5,
                  backgroundColor: const Color(0xFFE5E7EB),
                  valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                ),
              ),
              const SizedBox(height: 12),
              // Step dots
              _StepIndicatorRow(
                  total: _questions.length,
                  confirmed: _runtimes.map((r) => r.confirmed).toList()),
              const SizedBox(height: 12),
            ],
              ),
            ),
          ),
        ),

        // ── Question list ─────────────────────────────────────────────────
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
                itemCount: _questions.length,
                itemBuilder: (ctx, i) => _buildQuestionCard(i),
              ),
            ),
          ),
        ),

        // ── Submit bar ────────────────────────────────────────────────────
        _SubmitBar(
          answeredCount: _answeredCount,
          total:         _questions.length,
          onSubmit:      _answeredCount == _questions.length ? _submitAll : null,
        ),
      ],
    );
  }

  // ── Question card ─────────────────────────────────────────────────────────
  Widget _buildQuestionCard(int i) {
    final q  = _questions[i];
    final rt = _runtimes[i];
    final elapsed = _elapsed[i] ?? 0;

    final isCompleted    = rt.confirmed;
    // "Time exceeded" is shown ONLY for the specific question that hit its
    // own limit and has NOT been told to continue — never for any other
    // question, and never for one that's still locked/pending.
    final isTimeExceeded = rt.timedOut && !rt.continuedAfterTimeout && !isCompleted;
    final isPending      = rt.startedAt == null && !isCompleted;
    final isActive       = !isPending && !isCompleted;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCompleted
              ? const Color(0xFFD1FAE5)
              : isTimeExceeded
                  ? const Color(0xFFFECACA)
                  : const Color(0xFFE5E7EB),
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Text(
                  'QUESTION ${i + 1} · ${_formatLabel(q.format)}',
                  style: GoogleFonts.dmSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textFaint,
                      letterSpacing: 0.5),
                ),
                Text(
                  q.topic.toUpperCase(),
                  style: GoogleFonts.dmSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF6366F1),
                      letterSpacing: 0.5),
                ),
                if (q.model1DifficultyLevel != null)
                  _Model1Badge(
                    score: q.model1DifficultyScore ?? q.difficultyScore,
                    level: q.model1DifficultyLevel!,
                    confidence: q.model1Confidence,
                    source: q.model1Source,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: _buildStatusBadge(
                  isCompleted, isTimeExceeded, isPending, rt, elapsed, q),
            ),
          ),

          // Topic heading
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(q.topic,
                style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary)),
          ),

          if (isPending)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Text(
                'This question unlocks once you confirm question $i.',
                style: GoogleFonts.dmSans(
                    fontSize: 13, color: AppColors.textFaint),
              ),
            )
          else ...[
            // Question text
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: _buildQuestionText(q.questionText),
            ),

            // Answer input — format-aware
            if (!isCompleted)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                child: _buildAnswerInput(i, q, rt, isActive),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: _buildConfirmedAnswerSummary(q, rt),
              ),

            // Hint banner(s) — real progressive XAI hints
            if (rt.hintsUsed.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: _HintBanner(hints: rt.hintsUsed),
              ),
            ],
            if (rt.hintLoading)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: LinearProgressIndicator(minHeight: 3),
              ),

            // Action row (Hint + Confirm)
            if (!isCompleted && isActive)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    if (rt.hintsUsed.length < 10)
                      _HintButton(
                        onTap: rt.hintLoading ? null : () => _useHint(i),
                        nextLevel: rt.hintsUsed.length + 1,
                        loading: rt.hintLoading,
                      ),
                    const Spacer(),
                    if (_hasAnswer(i))
                      _ConfirmButton(onTap: () => _confirmAnswer(i)),
                  ],
                ),
              )
            else
              const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  String _formatLabel(String format) {
    switch (format) {
      case 'fill_blank':   return 'MULTIPLE CHOICE';
      case 'short_answer': return 'SHORT ANSWER';
      case 'multi_part':   return 'MULTI-PART PROBLEM';
      default:              return format.replaceAll('_', ' ').toUpperCase();
    }
  }

  Widget _buildStatusBadge(bool isCompleted, bool isTimeExceeded, bool isPending,
      _QuestionRuntime rt, int elapsed, SessionQuestion q) {
    if (isCompleted) {
      final overtimeTag = rt.overtimeSeconds > 0
          ? ' (+${_fmtTime(rt.overtimeSeconds)} overtime)'
          : '';
      return _StatusBadge(
        label: 'COMPLETED · ${_fmtTime(elapsed)}$overtimeTag',
        color: const Color(0xFF16A34A),
        bg:    const Color(0xFFDCFCE7),
        icon:  Icons.check_circle_outline,
      );
    }
    if (isTimeExceeded) {
      return _StatusBadge(
        label: 'TIME EXCEEDED · ${_fmtTime(elapsed)} / ${_fmtTime(q.timeAllottedSeconds)}',
        color: const Color(0xFFDC2626),
        bg:    const Color(0xFFFEE2E2),
        icon:  Icons.timer_off_outlined,
      );
    }
    if (isPending) {
      return const _StatusBadge(
        label: 'Pending',
        color: Color(0xFF6B7280),
        bg:    Color(0xFFF3F4F6),
        icon:  Icons.lock_outline,
      );
    }
    if (rt.continuedAfterTimeout) {
      // Over the allotted time and still going — show the base allotment
      // in the normal colour and the extra time in red, as requested.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusBadge(
            label: _fmtTime(q.timeAllottedSeconds),
            color: const Color(0xFF0EA5E9),
            bg:    const Color(0xFFE0F2FE),
            icon:  Icons.timer_outlined,
          ),
          const SizedBox(width: 6),
          _StatusBadge(
            label: '+${_fmtTime(rt.overtimeSeconds)} overtime',
            color: const Color(0xFFDC2626),
            bg:    const Color(0xFFFEE2E2),
            icon:  Icons.hourglass_bottom,
          ),
        ],
      );
    }
    return _StatusBadge(
      label: '${_fmtTime(elapsed)} / ${_fmtTime(q.timeAllottedSeconds)}',
      color: const Color(0xFF0EA5E9),
      bg:    const Color(0xFFE0F2FE),
      icon:  Icons.timer_outlined,
    );
  }

  // ── Answer input — one branch per backend `format` ──────────────────────
  Widget _buildAnswerInput(int i, SessionQuestion q, _QuestionRuntime rt, bool isActive) {
    switch (q.format) {
      case 'fill_blank':
        return _OptionsGrid(
          options:       q.options,
          selectedIndex: rt.selectedIndex,
          onSelect:      isActive ? (idx) => _selectOption(i, idx) : null,
        );
      case 'short_answer':
        return _ShortAnswerField(
          key: ValueKey('sa_$i'),
          initialValue: rt.answerText,
          enabled: isActive,
          onChanged: (v) => _setAnswerText(i, v),
        );
      case 'multi_part':
        return _MultiPartFields(
          key: ValueKey('mp_$i'),
          subParts: q.subParts,
          values: rt.subAnswers,
          enabled: isActive,
          onChanged: (subId, v) => _setSubAnswer(i, subId, v),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildConfirmedAnswerSummary(SessionQuestion q, _QuestionRuntime rt) {
    String text;
    switch (q.format) {
      case 'fill_blank':
        text = (rt.selectedIndex != null && rt.selectedIndex! < q.options.length)
            ? q.options[rt.selectedIndex!]
            : '(no answer given)';
        break;
      case 'short_answer':
        text = rt.answerText.trim().isEmpty ? '(no answer given)' : rt.answerText;
        break;
      case 'multi_part':
        text = q.subParts
            .map((sp) => '${sp.id}) ${rt.subAnswers[sp.id]?.trim().isNotEmpty == true ? rt.subAnswers[sp.id] : '—'}')
            .join('   ');
        break;
      default:
        text = '';
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Your answer: $text',
                style: GoogleFonts.dmSans(
                    fontSize: 12.5,
                    color: const Color(0xFF166534),
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionText(String text) {
    final parts = text.split('_____');
    if (parts.length < 2) {
      return Text(text,
          style: GoogleFonts.dmSans(
              fontSize: 14, color: const Color(0xFF374151), height: 1.55));
    }
    return RichText(
      text: TextSpan(
        style: GoogleFonts.dmSans(
            fontSize: 14, color: const Color(0xFF374151), height: 1.55),
        children: [
          TextSpan(text: parts[0]),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
              decoration: const BoxDecoration(
                color: Color(0xFFEFF6FF),
                border: Border(
                  bottom: BorderSide(color: AppColors.accent, width: 2),
                ),
              ),
              child: Text('      ?      ',
                  style: GoogleFonts.dmSans(
                      color: AppColors.accent, fontSize: 14)),
            ),
          ),
          TextSpan(text: parts.length > 1 ? parts[1] : ''),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      key: const ValueKey('err'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 48),
          const SizedBox(height: 16),
          Text('Something went wrong',
              style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(_error ?? 'Unknown error',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                    fontSize: 13, color: const Color(0xFF6B7280))),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _loadQuestions,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SUB-WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

class _StepIndicatorRow extends StatelessWidget {
  final int total;
  final List<bool> confirmed;
  const _StepIndicatorRow({required this.total, required this.confirmed});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final done = i < confirmed.length && confirmed[i];
        return Flexible(
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: done
                      ? AppColors.accent
                      : const Color(0xFFE5E7EB),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                        color: done ? Colors.white : AppColors.textFaint,
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              if (i < total - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    color: done
                        ? AppColors.accent
                        : const Color(0xFFE5E7EB),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color, bg;
  final IconData icon;
  const _StatusBadge({
    required this.label,
    required this.color,
    required this.bg,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Small badge that surfaces Model 1's actual per-chunk difficulty output
/// (score, level, confidence, and whether it came from the trained Random
/// Forest or the heuristic fallback) directly on each question, so it's
/// independently visible/checkable that Model 1's result is really being
/// used to build the session — not just asserted in a log file.
class _Model1Badge extends StatelessWidget {
  final int score;
  final String level;
  final double? confidence;
  final String? source;
  const _Model1Badge({required this.score, required this.level, this.confidence, this.source});

  @override
  Widget build(BuildContext context) {
    final isRf = source == 'model1_rf';
    return Tooltip(
      message: 'Model 1 (difficulty prediction): $score/5 · $level'
          '${confidence != null ? ' · ${(confidence! * 100).round()}% confidence' : ''}'
          '\nSource: ${isRf ? 'trained Random Forest' : 'heuristic fallback'}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F3FF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFDDD6FE)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isRf ? Icons.model_training : Icons.functions,
                size: 11, color: const Color(0xFF7C3AED)),
            const SizedBox(width: 3),
            Text('M1: $score/5',
                style: const TextStyle(
                    color: Color(0xFF7C3AED), fontSize: 9.5, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _OptionsGrid extends StatelessWidget {
  final List<String> options;
  final int? selectedIndex;
  final void Function(int)? onSelect;

  const _OptionsGrid({
    required this.options,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final labels = ['A', 'B', 'C', 'D'];
    // Previously a GridView with childAspectRatio: 3.5 — that derives cell
    // HEIGHT from the container's WIDTH, so on a wide desktop browser each
    // option ballooned to 250-300px tall for a single line of text like
    // "175". Fixed-height rows (in pairs of 2) stay a sensible ~64px
    // regardless of window width.
    final rows = <Widget>[];
    for (int i = 0; i < options.length; i += 2) {
      final hasSecond = i + 1 < options.length;
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _OptionCell(label: labels[i], text: options[i], selected: selectedIndex == i, onTap: () => onSelect?.call(i))),
              if (hasSecond) ...[
                const SizedBox(width: 8),
                Expanded(child: _OptionCell(label: labels[i + 1], text: options[i + 1], selected: selectedIndex == i + 1, onTap: () => onSelect?.call(i + 1))),
              ],
            ],
          ),
        ),
      ));
    }
    return Column(children: rows);
  }
}

class _OptionCell extends StatelessWidget {
  final String label;
  final String text;
  final bool selected;
  final VoidCallback onTap;
  const _OptionCell({required this.label, required this.text, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        constraints: const BoxConstraints(minHeight: 52),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEFF6FF) : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.accent : const Color(0xFFE5E7EB),
            width: selected ? 1.5 : 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '$label) ',
              style: TextStyle(
                  color: selected ? AppColors.accent : const Color(0xFF6B7280),
                  fontWeight: FontWeight.w700,
                  fontSize: 13),
            ),
            Expanded(
              child: Text(
                text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: selected ? AppColors.primary : const Color(0xFF374151),
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 6),
              Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                child: const Icon(Icons.check, color: Colors.white, size: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Free-text input for `short_answer` format questions. This is what was
/// entirely missing before — the old screen only ever rendered an options
/// grid, so short-answer questions had no way to type an answer at all.
class _ShortAnswerField extends StatefulWidget {
  final String initialValue;
  final bool enabled;
  final ValueChanged<String> onChanged;
  const _ShortAnswerField({
    super.key,
    required this.initialValue,
    required this.enabled,
    required this.onChanged,
  });

  @override
  State<_ShortAnswerField> createState() => _ShortAnswerFieldState();
}

class _ShortAnswerFieldState extends State<_ShortAnswerField> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextField(
        controller: _ctrl,
        enabled: widget.enabled,
        onChanged: widget.onChanged,
        inputFormatters: [LengthLimitingTextInputFormatter(200)],
        style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.primary),
        decoration: InputDecoration(
          hintText: 'Type your answer (a number or short expression)…',
          hintStyle: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textFaint),
          filled: true,
          fillColor: const Color(0xFFF9FAFB),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// Four typed sub-answers for `multi_part` format questions (Part a/b/c/d).
/// Also entirely missing before — multi_part questions rendered as an empty
/// options grid since `options` is never populated for this format.
class _MultiPartFields extends StatefulWidget {
  final List<SubPart> subParts;
  final Map<String, String> values;
  final bool enabled;
  final void Function(String subId, String value) onChanged;
  const _MultiPartFields({
    super.key,
    required this.subParts,
    required this.values,
    required this.enabled,
    required this.onChanged,
  });

  @override
  State<_MultiPartFields> createState() => _MultiPartFieldsState();
}

class _MultiPartFieldsState extends State<_MultiPartFields> {
  late final Map<String, TextEditingController> _ctrls = {
    for (final sp in widget.subParts)
      sp.id: TextEditingController(text: widget.values[sp.id] ?? ''),
  };

  @override
  void dispose() {
    for (final c in _ctrls.values) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: widget.subParts.map((sp) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sp.prompt,
                    style: GoogleFonts.dmSans(
                        fontSize: 13, color: const Color(0xFF374151), height: 1.4)),
                const SizedBox(height: 6),
                TextField(
                  controller: _ctrls[sp.id],
                  enabled: widget.enabled,
                  onChanged: (v) => widget.onChanged(sp.id, v),
                  inputFormatters: [LengthLimitingTextInputFormatter(80)],
                  style: GoogleFonts.dmSans(fontSize: 13.5, color: AppColors.primary),
                  decoration: InputDecoration(
                    hintText: 'Part ${sp.id}) answer…',
                    hintStyle: GoogleFonts.dmSans(fontSize: 12.5, color: AppColors.textFaint),
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Shows every progressive hint requested so far (level 1, 2, 3…), each
/// from the real backend XAI hint endpoint — not a single static string.
class _HintBanner extends StatelessWidget {
  final List<Map<String, dynamic>> hints;
  const _HintBanner({required this.hints});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: hints.map((h) {
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lightbulb_outline,
                  color: Color(0xFFF59E0B), size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('HINT · LEVEL ${h['level']}',
                        style: GoogleFonts.dmSans(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: const Color(0xFFB45309))),
                    const SizedBox(height: 3),
                    Text(h['hint_text']?.toString() ?? '',
                        style: GoogleFonts.dmSans(
                            fontSize: 12.5,
                            color: const Color(0xFF92400E),
                            height: 1.5)),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _HintButton extends StatelessWidget {
  final VoidCallback? onTap;
  final int nextLevel;
  final bool loading;
  const _HintButton({required this.onTap, required this.nextLevel, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(
                width: 12, height: 12,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF59E0B)),
              )
            else
              const Icon(Icons.lightbulb_outline, color: Color(0xFFF59E0B), size: 14),
            const SizedBox(width: 6),
            Text(nextLevel == 1 ? 'Hint' : 'Next hint (Lv $nextLevel)',
                style: GoogleFonts.dmSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFB45309))),
          ],
        ),
      ),
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ConfirmButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('Confirm',
            style: GoogleFonts.dmSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
      ),
    );
  }
}

class _SubmitBar extends StatelessWidget {
  final int answeredCount, total;
  final VoidCallback? onSubmit;
  const _SubmitBar(
      {required this.answeredCount,
      required this.total,
      required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, -2))],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Text(
              '$answeredCount / $total answered',
              style: GoogleFonts.dmSans(
                  fontSize: 13, color: const Color(0xFF6B7280)),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: onSubmit,
              icon: const Icon(Icons.send_rounded, size: 15),
              label: const Text('Submit Final Answer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: onSubmit != null
                    ? AppColors.primary
                    : AppColors.textFaint,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// LOADING / SUBMITTING VIEWS
// ══════════════════════════════════════════════════════════════════════════════

class _LoadingView extends StatefulWidget {
  const _LoadingView({super.key});
  @override State<_LoadingView> createState() => _LoadingViewState();
}

class _LoadingViewState extends State<_LoadingView>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  int _msgIdx = 0;
  static const _msgs = [
    'Running Model 1 difficulty analysis…',
    'Building your learner profile…',
    'Model 2 generating personalised questions via Gemini…',
    'Checking generated questions against your material…',
    'Adapting question difficulty and language…',
    'Almost ready — preparing your session…',
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 1))
      ..repeat();
    _cycle();
  }

  void _cycle() {
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _msgIdx = (_msgIdx + 1) % _msgs.length);
      _cycle();
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RotationTransition(
              turns: _ctrl,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const SweepGradient(
                    colors: [AppColors.accent, Color(0xFFF3F4F8)],
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.accent.withOpacity(0.25),
                        blurRadius: 20)
                  ],
                ),
                child: const Center(
                    child: Icon(Icons.psychology_outlined,
                        color: AppColors.primary, size: 26)),
              ),
            ),
            const SizedBox(height: 28),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: Text(_msgs[_msgIdx],
                  key: ValueKey(_msgIdx),
                  textAlign: TextAlign.center,
                  style: AppText.h3.copyWith(color: AppColors.primary)),
            ),
            const SizedBox(height: 10),
            Text('This may take up to 30 seconds', style: AppText.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// A "thought process" trace for the wait between Submit and results —
/// each line names a real stage of what backend/app.py's /submit route
/// actually does, in the order it does it (grade every answer first, one
/// batched Gemini call for XAI across all questions, then the forgetting
/// curve + mastery computation). This isn't decorative filler: it's meant
/// to make the wait legible, the same way a reasoning trace does.
class _SubmittingView extends StatefulWidget {
  const _SubmittingView({super.key});
  @override
  State<_SubmittingView> createState() => _SubmittingViewState();
}

class _SubmittingViewState extends State<_SubmittingView> {
  static const _steps = [
    (
      title: 'Grading every answer',
      detail: 'Checking each response against the accepted solution methods.',
      subPoints: [
        'Fill-in-the-blank and short-answer responses matched against the expected value',
        'Partial credit applied where a multi-part answer is partly right',
      ],
    ),
    (
      title: 'Generating XAI explanations',
      detail: 'One Gemini call covering every question — why each answer was right or wrong.',
      subPoints: [
        'Every question gets its own explanation, not just the ones you missed',
        'Wrong answers get the full step-by-step correct solution',
      ],
    ),
    (
      title: 'Calculating your forgetting curve',
      detail: 'Ebbinghaus retention model, using this session\'s accuracy, hints and timing.',
      subPoints: [
        'Weighs this session against your accuracy, mistake rate and hint usage',
        'Produces your personal memory-strength estimate for this material',
      ],
    ),
    (
      title: 'Updating your mastery profile',
      detail: 'Comparing this session against your history to schedule the next review.',
      subPoints: [
        'Checks your last 3 sessions for sustained accuracy before marking mastery',
        'Schedules your next review at the point retention is predicted to dip',
      ],
    ),
  ];

  int _step = 0;

  @override
  void initState() {
    super.initState();
    _advance();
  }

  void _advance() {
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (!mounted || _step >= _steps.length - 1) return;
      setState(() => _step++);
      _advance();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('QUEUED', style: AppText.eyebrow),
              const SizedBox(height: 6),
              Text('Analysing your answers…', style: AppText.h1),
              const SizedBox(height: 4),
              Text('Here\'s what\'s happening while you wait.', style: AppText.bodySmall),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3))],
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < _steps.length; i++)
                      _ThoughtStep(
                        title: _steps[i].title,
                        detail: _steps[i].detail,
                        subPoints: _steps[i].subPoints,
                        status: i < _step
                            ? _ThoughtStatus.done
                            : i == _step
                                ? _ThoughtStatus.active
                                : _ThoughtStatus.pending,
                        isLast: i == _steps.length - 1,
                      ),
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

enum _ThoughtStatus { done, active, pending }

class _ThoughtStep extends StatelessWidget {
  final String title;
  final String detail;
  final List<String> subPoints;
  final _ThoughtStatus status;
  final bool isLast;

  const _ThoughtStep({
    required this.title,
    required this.detail,
    required this.subPoints,
    required this.status,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final active = status == _ThoughtStatus.active;
    final done = status == _ThoughtStatus.done;
    final dimmed = status == _ThoughtStatus.pending;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done
                    ? AppColors.success
                    : active
                        ? AppColors.accent
                        : AppColors.bgPage,
                border: Border.all(
                  color: dimmed ? AppColors.border : Colors.transparent,
                ),
              ),
              child: Center(
                child: done
                    ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                    : active
                        ? const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : null,
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 34,
                color: done ? AppColors.success : AppColors.border,
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: dimmed ? 0.45 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.h3),
                  const SizedBox(height: 3),
                  Text(detail, style: AppText.bodySmall),
                  if (active || done) ...[
                    const SizedBox(height: 8),
                    for (final point in subPoints)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: AppColors.textFaint,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(point, style: AppText.caption.copyWith(fontWeight: FontWeight.w500)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}


// ══════════════════════════════════════════════════════════════════════════════
// RESULTS VIEW — one unified page (no tabs): score, per-question review with
// inline XAI, then a plain-language "next review" card. No internal method
// names (Ebbinghaus / stability / raw formula) are shown to the student —
// those are implementation details that power the scheduling, not something
// the student needs to see or should have to interpret.
// ══════════════════════════════════════════════════════════════════════════════

class _ResultsView extends StatelessWidget {
  final Map<String, dynamic> result;
  final List<SessionQuestion> questions;
  final String studyMode;
  final int studyDays;
  const _ResultsView({
    super.key,
    required this.result,
    required this.questions,
    required this.studyMode,
    required this.studyDays,
  });

  @override
  Widget build(BuildContext context) {
    final score   = (result['score'] as num?)?.toDouble() ?? 0;
    final correct = result['correct'] as int? ?? 0;
    final total   = result['total'] as int? ?? 0;
    final pct     = (score * 100).round();
    final results = (result['results'] as List? ?? [])
        .map((r) => QuestionResult.fromJson(r as Map<String, dynamic>))
        .toList();
    final curve         = result['forgetting_curve'] as Map<String, dynamic>? ?? {};
    final mastery       = result['mastery_reached'] as bool? ?? false;
    final timeoutCount  = results.where((r) => r.timedOut).length;
    final nextDays      = result['next_review_days'];
    final nextDate      = result['next_review_date'] as String?;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        // ── Score header card — big, bold score front and centre ──────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$pct%',
                      style: GoogleFonts.dmSans(
                          fontSize: 56, fontWeight: FontWeight.w900, height: 1,
                          color: pct >= 70 ? const Color(0xFF16A34A) : const Color(0xFFDC2626))),
                  const SizedBox(width: 14),
                  Text('$correct / $total correct',
                      style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textFaint, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                mastery ? '🎓 Mastery Achieved!' : pct >= 70 ? '🎯 Great Session!' : '📖 Keep Practising!',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary),
              ),
              const SizedBox(height: 8),
              if (nextDate != null)
                Text(
                  'Next review in $nextDays day${nextDays == 1 ? '' : 's'} · $nextDate',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(fontSize: 12.5, color: AppColors.accent, fontWeight: FontWeight.w600),
                ),
              if (timeoutCount > 0) ...[
                const SizedBox(height: 10),
                Center(child: _Chip(label: '⏱ $timeoutCount question${timeoutCount == 1 ? '' : 's'} timed out', color: const Color(0xFFDC2626))),
              ],
            ],
          ),
        ),

        const SizedBox(height: 18),
        Text('QUESTION REVIEW',
            style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint, letterSpacing: 1)),
        const SizedBox(height: 10),

        ...results.asMap().entries.map((e) => _ResultCard(index: e.key, result: e.value)),

        const SizedBox(height: 8),
        _NextReviewCard(curve: curve, nextDays: nextDays, nextDate: nextDate, mastery: mastery),

        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _ResultsNavButton(
                icon: Icons.psychology_outlined,
                label: 'View AI Feedback',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ExplainableAiFeedbackPage(
                      initialData: buildRealAiFeedbackData(
                        result,
                        results,
                        studyMode: studyMode,
                        studyDays: studyDays,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ResultsNavButton(
                icon: Icons.bar_chart_rounded,
                label: 'View Analytics',
                onTap: () => Navigator.pushNamed(context, '/analytics'),
              ),
            ),
          ],
        ),
      ],
        ),
      ),
    );
  }
}

/// Builds a REAL AiFeedbackData from this session's actual /submit response
/// — not the mock FirestoreStudentLearningService. Every field here is
/// either pulled directly from the backend result, or (for the retention
/// curve points beyond "now") computed by evaluating the backend's own
/// Ebbinghaus formula R(t)=e^(-t/S) using its real, just-computed stability
/// value — the same formula the backend documents using for scheduling.
/// This is a single-session snapshot, not multi-session history (the app
/// doesn't have that yet), so the curve plots one real trajectory rather
/// than tracking retention across several past sessions.
AiFeedbackData buildRealAiFeedbackData(
  Map<String, dynamic> result,
  List<QuestionResult> results, {
  String studyMode = 'fixed',
  int studyDays = 7,
}) {
  final curve = result['forgetting_curve'] as Map<String, dynamic>? ?? {};
  final profile = result['learner_profile'] as Map<String, dynamic>? ?? {};
  final stability = (curve['stability'] as num?)?.toDouble() ?? 5.0;
  final nextReviewDays = (result['next_review_days'] as num?)?.toDouble() ?? stability;
  final nextReviewDate = result['next_review_date'] as String?;
  final uid = FirebaseAuth.instance.currentUser?.uid ?? 'student';

  // Focus concept = the weakest-scoring question this session (or the first
  // one if everything was correct) — the one actually worth a deep-dive.
  final sorted = [...results]..sort((a, b) => a.score.compareTo(b.score));
  final focus = sorted.isNotEmpty ? sorted.first : null;

  double retentionAt(double days) => math.exp(-days / stability) * 100;

  final curvePoints = <RetentionCurvePoint>[
    RetentionCurvePoint(label: 'Today', day: 0, predictedRetention: retentionAt(0), idealRetention: 95, isCurrent: true),
    RetentionCurvePoint(label: '${(nextReviewDays / 2).round()}d', day: nextReviewDays / 2, predictedRetention: retentionAt(nextReviewDays / 2), idealRetention: 85),
    RetentionCurvePoint(label: '${nextReviewDays.round()}d (review)', day: nextReviewDays, predictedRetention: retentionAt(nextReviewDays), idealRetention: 70),
  ];

  final factors = <ExplanationFactor>[
    ExplanationFactor(
      id: 'accuracy',
      title: 'Session Accuracy',
      value: '${((result['score'] as num? ?? 0) * 100).round()}%',
      description: '${result['correct']} of ${result['total']} questions correct this session.',
      tone: ((result['score'] as num? ?? 0) >= 0.7) ? 'green' : 'orange',
    ),
    if (focus != null)
      ExplanationFactor(
        id: 'pastPerformance',
        title: 'Hint Usage',
        value: '${focus.hintsUsed.length} hint${focus.hintsUsed.length == 1 ? '' : 's'}',
        description: focus.hintsUsed.isEmpty
            ? 'You solved this without needing a hint.'
            : 'You used ${focus.hintsUsed.length} progressive hints before answering.',
        tone: focus.hintsUsed.length >= 3 ? 'orange' : 'blue',
      ),
    if (focus != null)
      ExplanationFactor(
        id: 'timeLapse',
        title: 'Time Taken',
        value: '${focus.timeTaken.toStringAsFixed(0)}s / ${focus.timeAllottedSeconds}s',
        description: focus.timedOut
            ? 'You went over the allotted time for this question.'
            : 'Within the allotted time for this question\'s difficulty.',
        tone: focus.timedOut ? 'orange' : 'green',
      ),
  ];

  final reportRows = results
      .map((r) => ReportMetricRow(
            metric: r.topic,
            value: r.isCorrect ? 'Correct' : 'Incorrect',
            interpretation: '${r.timeTaken.toStringAsFixed(0)}s, ${r.hintsUsed.length} hint(s)',
            recommendation: r.isCorrect ? 'Maintain with periodic review' : 'Review this concept before next session',
          ))
      .toList();

  // Every question's own real XAI text (from backend/app.py's batch XAI
  // call — each question got its own Gemini-written explanation, keyed by
  // question_id) — not just the single "focus" question above. This is
  // what actually answers "why was I right/wrong on THIS one" for every
  // question in the session, not only the weakest one.
  final questionFeedback = results
      .map((r) => QuestionFeedback(
            questionId: r.questionId,
            questionText: r.questionText,
            topic: r.topic,
            isCorrect: r.isCorrect,
            yourAnswer: r.yourAnswerText,
            correctAnswer: r.correctAnswerText,
            xaiText: (r.xai['xai_text'] as String?)?.trim().isNotEmpty == true
                ? r.xai['xai_text'] as String
                : (r.isCorrect
                    ? 'Correct — well done.'
                    : 'Compare your answer above against the correct one and re-trace where your working diverged.'),
            hintsUsed: r.hintsUsed.length,
          ))
      .toList();

  // "How your next review was calculated" — a real, honest breakdown of the
  // backend/app.py:compute_forgetting_curve() inputs (not decorative):
  // S = 1.0 + avg_score*3.5 - mistake_rate*2.0 - hint_press_rate*1.5 +
  //     session_count*0.4, then paced by the study mode/period chosen at
  // upload time. Same numbers the backend actually used, just explained.
  final avgScore = (profile['avg_score'] as num?)?.toDouble() ??
      (result['score'] as num?)?.toDouble() ?? 0;
  final mistakeRate = (profile['mistake_rate'] as num?)?.toDouble() ?? 0;
  final hintRate = (profile['hint_press_rate'] as num?)?.toDouble() ?? 0;
  final sessionCount = (profile['session_count'] as num?)?.toInt() ?? 1;
  final modeLabel =
      studyMode == 'until_mastery' ? 'Study until mastery' : 'Fixed $studyDays-day plan';

  final schedulingFactors = <ExplanationFactor>[
    ExplanationFactor(
      id: 'memoryAccuracy',
      title: 'Accuracy history',
      value: '${(avgScore * 100).round()}%',
      description:
          'Higher accuracy strengthens memory — contributes +${(avgScore * 3.5).toStringAsFixed(1)} days to your stability.',
      tone: avgScore >= 0.7 ? 'green' : 'orange',
    ),
    ExplanationFactor(
      id: 'memoryMistakes',
      title: 'Mistake rate',
      value: '${(mistakeRate * 100).round()}%',
      description:
          'Mistakes shorten how long you retain this — subtracts ${(mistakeRate * 2.0).toStringAsFixed(1)} days.',
      tone: mistakeRate <= 0.3 ? 'green' : 'orange',
    ),
    ExplanationFactor(
      id: 'memoryHints',
      title: 'Hint dependency',
      value: '${(hintRate * 100).round()}%',
      description:
          'Leaning on hints signals shakier recall — subtracts ${(hintRate * 1.5).toStringAsFixed(1)} days.',
      tone: hintRate <= 0.3 ? 'green' : 'orange',
    ),
    ExplanationFactor(
      id: 'memorySessions',
      title: 'Sessions completed',
      value: '$sessionCount',
      description:
          'Each completed session builds durability — adds ${(sessionCount * 0.4).toStringAsFixed(1)} days.',
      tone: 'blue',
    ),
    ExplanationFactor(
      id: 'studyPlan',
      title: 'Your study plan',
      value: modeLabel,
      description: studyMode == 'until_mastery'
          ? 'You chose to study until mastery — review gaps are paced between 1 and 14 days until you get there.'
          : 'You chose a $studyDays-day plan — review gaps are capped so every session fits inside it.',
      tone: 'purple',
    ),
    ExplanationFactor(
      id: 'memoryStrength',
      title: 'Resulting memory strength',
      value: '${stability.toStringAsFixed(1)} days',
      description: nextReviewDate != null
          ? 'Combining all of the above: your next review is scheduled for $nextReviewDate — in ${nextReviewDays.round()} day${nextReviewDays.round() == 1 ? '' : 's'}.'
          : 'This is how long your memory of this material is predicted to stay strong before it needs reinforcing.',
      tone: 'blue',
    ),
  ];

  return AiFeedbackData(
    id: result['session_id'] as String? ?? 'session',
    studentId: uid,
    courseTitle: 'This Session',
    conceptTitle: focus?.topic ?? 'Session Overview',
    badgeLabel: 'THIS SESSION',
    headline: focus != null && !focus.isCorrect
        ? 'Focus Area: ${focus.topic}'
        : 'Nice work this session!',
    summary: focus?.xai['xai_text'] as String? ??
        'You completed this session — here\'s the AI\'s read on how it went.',
    currentRetentionPercent: retentionAt(0).round(),
    declinePercent: (100 - retentionAt(nextReviewDays)).round(),
    recoveryRetentionPercent: retentionAt(0).round(),
    retentionDescription:
        'Right after finishing, recall is fresh. Based on this session, your memory strength here is ${stability.toStringAsFixed(1)} days, so without review it\'s predicted to fade to about ${retentionAt(nextReviewDays).round()}% by ${nextReviewDate ?? 'your next scheduled review'}.',
    nextReviewDate: nextReviewDate,
    nextReviewDays: nextReviewDays.round(),
    schedulingFactors: schedulingFactors,
    questionFeedback: questionFeedback,
    curve: curvePoints,
    factors: factors,
    guidanceTitle: focus != null && !focus.isCorrect ? 'How to improve on ${focus.topic}' : 'Keep up the momentum',
    guidanceBody: focus?.xai['xai_text'] as String? ??
        'Review your session summary above, and come back for your next scheduled review to lock in what you\'ve learned.',
    reportRows: reportRows,
    generatedAt: DateTime.now(),
  );
}

class _ResultsNavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ResultsNavButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, fontSize: 13)),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Text(label, style: GoogleFonts.dmSans(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      );
}

/// One question's full review, merged into a single card: your answer vs
/// correct answer up front, then an expandable section with the XAI
/// explanation, hints used, and timing — replacing what used to be two
/// separate tabs (Summary + XAI Explanations) the student had to flip between.
class _ResultCard extends StatefulWidget {
  final int index;
  final QuestionResult result;
  const _ResultCard({required this.index, required this.result});

  @override
  State<_ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends State<_ResultCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final r     = widget.result;
    final color = r.isCorrect ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final xai   = r.xai;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.vertical(top: const Radius.circular(12), bottom: Radius.circular(_expanded ? 0 : 12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(r.isCorrect ? Icons.check_circle : Icons.cancel, color: color, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Q${widget.index + 1}. ${r.topic}',
                            style: GoogleFonts.dmSans(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
                      ),
                      if (r.hintsUsed.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text('💡${r.hintsUsed.length}',
                              style: GoogleFonts.dmSans(fontSize: 11, color: const Color(0xFFF59E0B))),
                        ),
                      if (r.timedOut)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(Icons.timer_off_outlined, size: 14, color: const Color(0xFFDC2626)),
                        ),
                      Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: AppColors.textFaint),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _AnswerBadge(label: 'YOUR ANSWER', text: r.yourAnswerText, color: color, bg: color.withOpacity(0.06)),
                      ),
                      if (!r.isCorrect) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: _AnswerBadge(
                              label: 'CORRECT', text: r.correctAnswerText, color: const Color(0xFF16A34A), bg: const Color(0xFFDCFCE7)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(color: color.withOpacity(0.15)),
                  const SizedBox(height: 4),
                  if (r.timedOut) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.timer_off_outlined, color: Color(0xFFDC2626), size: 13),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              r.continuedAfterTimeout
                                  ? 'Timed out at ${r.timeAllottedSeconds}s — you continued for +${r.overtimeSeconds.toStringAsFixed(0)}s more'
                                  : 'Timed out at ${r.timeAllottedSeconds}s — moved on without finishing',
                              style: GoogleFonts.dmSans(fontSize: 11.5, color: const Color(0xFFB91C1C), fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (r.hintsUsed.isNotEmpty) ...[
                    Text('HINTS USED (${r.hintsUsed.length})',
                        style: GoogleFonts.dmSans(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: const Color(0xFFB45309))),
                    const SizedBox(height: 4),
                    ...r.hintsUsed.map((h) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('Lv ${h['level']}: ${h['hint_text']}',
                              style: GoogleFonts.dmSans(fontSize: 11.5, color: const Color(0xFF92400E), height: 1.4)),
                        )),
                    const SizedBox(height: 10),
                  ],
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F4FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.accent.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.psychology_outlined, color: AppColors.accent, size: 15),
                            const SizedBox(width: 6),
                            Text('WHY',
                                style: GoogleFonts.dmSans(
                                    color: AppColors.accent, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(xai['xai_text'] as String? ?? '',
                            style: GoogleFonts.dmSans(fontSize: 13, color: const Color(0xFF374151), height: 1.6)),
                        if ((xai['review_topics'] as List?)?.isNotEmpty == true) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            children: (xai['review_topics'] as List)
                                .map((t) => Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEFF6FF),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFFBFDBFE)),
                                      ),
                                      child: Text(t.toString(), style: GoogleFonts.dmSans(fontSize: 11, color: const Color(0xFF1D4ED8))),
                                    ))
                                .toList(),
                          ),
                        ],
                      ],
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

class _AnswerBadge extends StatelessWidget {
  final String label, text;
  final Color color, bg;
  const _AnswerBadge({required this.label, required this.text, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
            const SizedBox(height: 3),
            Text(text, style: GoogleFonts.dmSans(fontSize: 12.5, color: AppColors.primary, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

/// Plain-language "when to come back" card. Intentionally does NOT expose
/// the internal method name (Ebbinghaus), the raw decay formula, or the
/// "stability" number — those are how the system computes the date, not
/// something the student needs to interpret. It only ever shows the ONE
/// upcoming date that's actually confirmed for this student right now;
/// see the note below about why further-out dates aren't listed here.
class _NextReviewCard extends StatelessWidget {
  final Map<String, dynamic> curve;
  final dynamic nextDays;
  final String? nextDate;
  final bool mastery;
  const _NextReviewCard({required this.curve, required this.nextDays, required this.nextDate, required this.mastery});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.primary, Color(0xFF2D4A7A)]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_available_outlined, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text('Your Next Review',
                  style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            mastery
                ? 'You\'ve mastered this topic — we\'ll check back with a light maintenance review.'
                : 'Timed to when you\'re most likely to be about to forget this — reviewing now locks it in.',
            style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.75), fontSize: 12.5, height: 1.5),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.notifications_active_outlined, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('In $nextDays day${nextDays == 1 ? '' : 's'}',
                          style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                      if (nextDate != null)
                        Text(nextDate!, style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.65), fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text('We\'ll also remind you on your dashboard when it\'s time.',
              style: GoogleFonts.dmSans(color: Colors.white.withOpacity(0.55), fontSize: 11)),
        ],
      ),
    );
  }
}