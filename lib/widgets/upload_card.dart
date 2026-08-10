import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/upload_provider.dart';

// ── Color constants (matches neuromathix palette) ─────────────────────────────
const Color _accentBlue  = Color(0xFF1B63E8);
const Color _bgLight     = Color(0xFFEEF4FF);
const Color _bgHover     = Color(0xFFDBEAFE);
const Color _borderLight = Color(0xFFBDD3FF);
const Color _textPrimary = Color(0xFF0F172A);
const Color _textMuted   = Color(0xFF94A3B8);
const Color _errorRed    = Color(0xFFEF4444);

// ── Public entry ──────────────────────────────────────────────────────────────

class UploadCard extends StatelessWidget {
  const UploadCard({super.key});

  void _pickFile(BuildContext context) {
    final input = html.FileUploadInputElement()
      ..accept = '.pdf,.jpg,.jpeg,.png'
      ..click();
    input.onChange.listen((_) {
      final f = input.files?.first;
      if (f == null) return;

      final reader = html.FileReader();
      reader.readAsArrayBuffer(f);
      reader.onLoadEnd.listen((_) {
        final bytes = Uint8List.fromList(reader.result as List<int>);
        context
            .read<UploadProvider>()
            .processFile(f.name, bytes, f.size / 1048576);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UploadProvider>(
      builder: (context, provider, _) {
        final status   = provider.state.status;
        final progress = provider.state.progress;
        final error    = provider.state.error;

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          switchInCurve: Curves.easeOut,
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: status == UploadStatus.uploading
              ? _ProgressCard(key: const ValueKey('prog'), progress: progress)
              : _DropZone(
                  key: const ValueKey('drop'),
                  error: error,
                  onPick: () => _pickFile(context),
                ),
        );
      },
    );
  }
}

// ── Drop zone ─────────────────────────────────────────────────────────────────

class _DropZone extends StatefulWidget {
  final String? error;
  final VoidCallback onPick;
  const _DropZone({super.key, this.error, required this.onPick});
  @override
  State<_DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<_DropZone> {
  bool _hover    = false;
  bool _btnHover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit:  (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 40),
        decoration: BoxDecoration(
          color: _hover ? _bgHover : _bgLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _hover ? _accentBlue : _borderLight,
            width: _hover ? 2 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: _accentBlue.withOpacity(0.07),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cloud icon
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: _hover
                    ? _accentBlue.withOpacity(0.12)
                    : Colors.white.withOpacity(0.85),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.cloud_upload_outlined,
                  size: 52,
                  color: _hover ? _accentBlue : const Color(0xFF6B8FBF)),
            ),

            const SizedBox(height: 24),

            Text('Drag and drop your file here',
                style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary)),

            const SizedBox(height: 6),

            Text('Supported: PDF, JPG, PNG  (Max 60 MB)',
                style: GoogleFonts.dmSans(
                    fontSize: 13.5, color: _textMuted)),

            if (widget.error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: _errorRed.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: _errorRed.withOpacity(0.3)),
                ),
                child: Text(widget.error!,
                    style: GoogleFonts.dmSans(
                        fontSize: 12.5,
                        color: _errorRed,
                        fontWeight: FontWeight.w500)),
              ),
            ],

            const SizedBox(height: 28),

            // Select file button
            MouseRegion(
              onEnter: (_) => setState(() => _btnHover = true),
              onExit:  (_) => setState(() => _btnHover = false),
              child: GestureDetector(
                onTap: widget.onPick,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 13),
                  decoration: BoxDecoration(
                    color: _btnHover ? _accentBlue : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _btnHover ? _accentBlue : _borderLight,
                      width: 1.5,
                    ),
                    boxShadow: _btnHover
                        ? [
                            BoxShadow(
                                color: _accentBlue.withOpacity(0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4))
                          ]
                        : [],
                  ),
                  child: Text('+ Select File',
                      style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color:
                              _btnHover ? Colors.white : _accentBlue)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Progress card ─────────────────────────────────────────────────────────────

// The real progress fraction only moves at 0.15 -> 0.55 -> 1.0 (see
// UploadProvider.processFile) because it tracks two backend HTTP calls, not
// bytes — so it sits at 0.55 for the bulk of the wait. This caption cycles
// on a timer instead, naming each real backend/app.py pipeline stage in the
// order upload_provider.dart actually calls them: POST /upload (extract
// text, OCR fallback, math-doc gate, Model 1 difficulty per chunk) then
// POST /material/<id>/session/start (Gemini question generation).
const _uploadStages = [
  'Uploading your PDF…',
  'Extracting text and checking it\'s math content…',
  'Running Model 1 difficulty analysis on each section…',
  'Generating your first personalised session with Gemini…',
];

class _ProgressCard extends StatefulWidget {
  final double progress;
  const _ProgressCard({super.key, required this.progress});

  @override
  State<_ProgressCard> createState() => _ProgressCardState();
}

class _ProgressCardState extends State<_ProgressCard> {
  int _stageIdx = 0;

  @override
  void initState() {
    super.initState();
    _cycle();
  }

  void _cycle() {
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted || _stageIdx >= _uploadStages.length - 1) return;
      setState(() => _stageIdx++);
      _cycle();
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(vertical: 56, horizontal: 40),
      decoration: BoxDecoration(
        color: _bgLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _borderLight, width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: _accentBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.cloud_upload_outlined,
                size: 52, color: _accentBlue),
          ),
          const SizedBox(height: 22),
          Text('Processing your file…',
              style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary)),
          const SizedBox(height: 4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(_uploadStages[_stageIdx],
                key: ValueKey(_stageIdx),
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                    fontSize: 13, color: _textMuted)),
          ),
          const SizedBox(height: 30),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: _bgHover,
              valueColor:
                  const AlwaysStoppedAnimation(_accentBlue),
            ),
          ),
          const SizedBox(height: 10),
          Text('${(progress * 100).toInt()}%',
              style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _accentBlue)),
        ],
      ),
    );
  }
}
