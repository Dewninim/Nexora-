import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../config/api_config.dart';

// ── Upload state ──────────────────────────────────────────────────────────────
enum UploadStatus { idle, uploading, success, error }
enum StudyMode   { fixedPeriod, untilMastery }

class UploadState {
  final UploadStatus status;
  final String?  fileName;
  final double   progress;
  final String?  error;
  final StudyMode studyMode;
  final int?     learningDays;
  final bool     starting;

  // Populated once /upload succeeds — this is what the quiz screen needs.
  final String?  sessionId;
  final int?     totalChunks;
  final Map<String, dynamic>? difficultySummary;

  const UploadState({
    this.status    = UploadStatus.idle,
    this.fileName,
    this.progress  = 0,
    this.error,
    this.studyMode = StudyMode.fixedPeriod,
    this.learningDays,
    this.starting  = false,
    this.sessionId,
    this.totalChunks,
    this.difficultySummary,
  });

  UploadState copyWith({
    UploadStatus? status, String? fileName, double? progress,
    String? error, StudyMode? studyMode, int? learningDays, bool? starting,
    String? sessionId, int? totalChunks, Map<String, dynamic>? difficultySummary,
    bool clearError = false,
  }) => UploadState(
    status:             status             ?? this.status,
    fileName:           fileName           ?? this.fileName,
    progress:           progress           ?? this.progress,
    error:              clearError ? null : (error ?? this.error),
    studyMode:          studyMode          ?? this.studyMode,
    learningDays:       learningDays       ?? this.learningDays,
    starting:           starting           ?? this.starting,
    sessionId:          sessionId          ?? this.sessionId,
    totalChunks:        totalChunks        ?? this.totalChunks,
    difficultySummary:  difficultySummary  ?? this.difficultySummary,
  );
}

// ── UploadProvider (ChangeNotifier) ───────────────────────────────────────────
// Talks to POST /upload on the Flask backend (see /backend/app.py). The
// backend runs Model 1 (difficulty prediction) on the PDF and returns a
// material_id. We then call /material/<id>/session/start to actually create
// a session and get a session_id, which the quiz screen needs.
class UploadProvider extends ChangeNotifier {
  UploadState _state = const UploadState();
  UploadState get state => _state;
  Timer? _progressTicker;

  // Real backend calls here take 10s-260s (OCR + Model 1, then Gemini
  // question generation) with no byte-level progress to report — the old
  // code just set a fixed number (0.15 -> 0.55 -> 1.0) and left it parked
  // there for the entire duration of each call, which reads as "stuck" to
  // anyone watching the number not move for a minute+. This instead creeps
  // the value toward a ceiling on a timer while a call is in flight —
  // visibly alive the whole time, and it never overshoots past the ceiling
  // until the real response actually arrives.
  void _creepToward(double ceiling) {
    _progressTicker?.cancel();
    _progressTicker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final next = _state.progress + (ceiling - _state.progress) * 0.12;
      _state = _state.copyWith(progress: next);
      notifyListeners();
    });
  }

  void _stopCreep() {
    _progressTicker?.cancel();
    _progressTicker = null;
  }

  /// Uploads the picked file's raw bytes to the backend.
  /// [sizeMB] is only used for the client-side size check.
  Future<void> processFile(String name, Uint8List bytes, double sizeMB) async {
    if (sizeMB > 60) {
      _state = _state.copyWith(status: UploadStatus.error, error: 'File exceeds 60 MB limit.');
      notifyListeners();
      return;
    }
    _state = _state.copyWith(
      status: UploadStatus.uploading,
      fileName: name,
      progress: 0.08,
      clearError: true,
    );
    notifyListeners();

    try {
      final uri = Uri.parse('$kApiBaseUrl/upload');
      // Previously this never sent user_id at all, so the backend silently
      // filed every upload under its default "anonymous" bucket — meaning
      // /user/<uid>/materials could never find a real user's own uploads.
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
      final request = http.MultipartRequest('POST', uri)
        ..fields['user_id'] = uid
        ..fields['study_days'] = (_state.learningDays ?? 7).toString()
        ..fields['mode'] = _state.studyMode == StudyMode.untilMastery
            ? 'until_mastery'
            : 'fixed'
        ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: name));

      // Creep toward 55% for the extraction/OCR/Model-1 leg of the upload.
      _creepToward(0.55);

      // 60s was too tight once OCR (real per-page cost, up to 20 pages) got
      // added to upload processing — bumped to give large/scanned PDFs
      // realistic headroom instead of the app timing out on a request the
      // backend would have finished a bit later anyway.
      final streamed = await request.send().timeout(const Duration(seconds: 180));
      final response = await http.Response.fromStream(streamed);
      _stopCreep();

      if (response.statusCode != 200) {
        final body = _tryDecode(response.body);
        throw Exception(body?['error'] ?? 'Upload failed (${response.statusCode})');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final materialId = data['material_id'] as String?;
      if (materialId == null) {
        throw Exception('Upload succeeded but no material_id was returned.');
      }

      _state = _state.copyWith(progress: 0.58);
      notifyListeners();
      // Creep toward 97% (never quite "done") for the Gemini question-
      // generation leg — only the real response snaps it to 100%.
      _creepToward(0.97);

      // Also bumped — a real Gemini call generating ~15 rich questions can
      // take longer than 60s, especially the first request in a session.
      final sessionResp = await http
          .post(Uri.parse('$kApiBaseUrl/material/$materialId/session/start'))
          .timeout(const Duration(seconds: 260));
      _stopCreep();

      if (sessionResp.statusCode != 200) {
        final body = _tryDecode(sessionResp.body);
        throw Exception(body?['error'] ?? 'Could not start session (${sessionResp.statusCode})');
      }

      final sessionData = jsonDecode(sessionResp.body) as Map<String, dynamic>;

      _state = _state.copyWith(
        status: UploadStatus.success,
        progress: 1.0,
        sessionId: sessionData['session_id'] as String?,
        totalChunks: data['total_chunks'] as int?,
        difficultySummary: data['difficulty_summary'] as Map<String, dynamic>?,
      );
      notifyListeners();
    } catch (e) {
      _stopCreep();
      _state = _state.copyWith(
        status: UploadStatus.error,
        error: 'Could not reach the AI backend. Is it running on $kApiBaseUrl? ($e)',
      );
      notifyListeners();
    }
  }

  Map<String, dynamic>? _tryDecode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  void setMode(StudyMode m) {
    _state = _state.copyWith(studyMode: m);
    notifyListeners();
  }

  void setDays(int d) {
    _state = _state.copyWith(learningDays: d);
    notifyListeners();
  }

  /// Brief transition before navigating to the quiz screen. The quiz screen
  /// itself uses the session_id (already fetched during upload) to load
  /// questions, so this just needs to confirm we have one ready.
  Future<void> startLearning() async {
    if (_state.sessionId == null) return;
    _state = _state.copyWith(starting: true);
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 400));
    _state = _state.copyWith(starting: false);
    notifyListeners();
  }

  void reset() {
    _stopCreep();
    _state = const UploadState();
    notifyListeners();
  }

  @override
  void dispose() {
    _stopCreep();
    super.dispose();
  }
}