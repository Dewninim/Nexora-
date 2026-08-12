import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/upload_provider.dart';
import '../theme/app_theme.dart';

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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.goldBorder.withValues(alpha: 0.8), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: AppColors.gold.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit:  (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
          decoration: BoxDecoration(
            color: _hover ? const Color(0xFFEFF6FF) : const Color(0xFFFAF9F6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hover ? AppColors.accent : AppColors.border,
              width: _hover ? 2 : 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Cloud icon badge matching reference screenshot
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.cloud_upload_rounded,
                  size: 38,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 20),

              Text(
                'Drag & drop your file here',
                style: GoogleFonts.openSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                'Supported: PDF, JPG, PNG · Max 60 MB',
                style: GoogleFonts.openSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted,
                ),
              ),

              if (widget.error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    widget.error!,
                    style: GoogleFonts.openSans(
                      fontSize: 12.5,
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Select file primary button
              MouseRegion(
                onEnter: (_) => setState(() => _btnHover = true),
                onExit:  (_) => setState(() => _btnHover = false),
                child: GestureDetector(
                  onTap: widget.onPick,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 220,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _btnHover
                            ? [const Color(0xFF1D4ED8), const Color(0xFF1E40AF)]
                            : [const Color(0xFF2563EB), const Color(0xFF1D4ED8)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      '+ Select File',
                      style: GoogleFonts.openSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 22),

              Row(
                children: [
                  const Expanded(child: Divider(color: AppColors.border)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'or paste a file from clipboard',
                      style: GoogleFonts.openSans(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider(color: AppColors.border)),
                ],
              ),

              const SizedBox(height: 18),

              // File format pills (PDF, JPG, PNG) matching reference screenshot
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _FormatPill(label: 'PDF', icon: Icons.picture_as_pdf_outlined, color: Colors.red.shade700),
                  const SizedBox(width: 10),
                  _FormatPill(label: 'JPG', icon: Icons.image_outlined, color: const Color(0xFF047857)),
                  const SizedBox(width: 10),
                  _FormatPill(label: 'PNG', icon: Icons.collections_outlined, color: Colors.blue.shade700),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormatPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _FormatPill({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.openSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
        ],
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
              style: GoogleFonts.openSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary)),
          const SizedBox(height: 4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(_uploadStages[_stageIdx],
                key: ValueKey(_stageIdx),
                textAlign: TextAlign.center,
                style: GoogleFonts.openSans(
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
              style: GoogleFonts.openSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _accentBlue)),
        ],
      ),
    );
  }
}
