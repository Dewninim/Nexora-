import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import '../services/teacher_service.dart';

class TeacherMessageDialog extends StatefulWidget {
  final String studentId;
  final String studentName;

  const TeacherMessageDialog({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<TeacherMessageDialog> createState() => _TeacherMessageDialogState();
}

class _TeacherMessageDialogState extends State<TeacherMessageDialog> {
  final TeacherService _service = TeacherService();
  final _subjectController = TextEditingController(text: 'Learning support');
  final _messageController = TextEditingController();
  final _practiceController = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    _practiceController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final subject = _subjectController.text.trim();
    final message = _messageController.text.trim();
    if (subject.isEmpty || message.isEmpty) {
      setState(() => _error = 'Enter a subject and message.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _service.sendDirectMessage(
        studentId: widget.studentId,
        subject: subject,
        message: message,
        practiceQuestion: _practiceController.text.trim().isEmpty
            ? null
            : _practiceController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: Container(
          padding: const EdgeInsets.fromLTRB(26, 26, 26, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 40,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Message',
                  style: GoogleFonts.openSans(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.studentName,
                  style: GoogleFonts.openSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 22),

                const _FieldLabel('Subject'),
                const SizedBox(height: 10),
                _InputPill(controller: _subjectController, hint: ''),
                const SizedBox(height: 22),

                Text(
                  'Quick templates',
                  style: GoogleFonts.openSans(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _TemplateButton(
                      label: 'Review Soon',
                      onTap: () => setState(() => _messageController.text =
                          'Please review the module soon and let me know if you need help.'),
                    ),
                    _TemplateButton(
                      label: 'Practice More!',
                      onTap: () => setState(() => _messageController.text =
                          'You should practice more questions to strengthen your understanding.'),
                    ),
                    _TemplateButton(
                      label: 'Good Progress',
                      onTap: () => setState(() => _messageController.text =
                          'You are improving well — keep following your review schedule.'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                Text(
                  'Message',
                  style: GoogleFonts.openSans(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                _BigMessageBox(
                  controller: _messageController,
                  hint: 'Type your message here..',
                ),
                const SizedBox(height: 18),

                const _FieldLabel('Optional practice question'),
                const SizedBox(height: 10),
                _InputPill(controller: _practiceController, hint: 'e.g. 2x² + 7x + 3 = 0'),

                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    style: GoogleFonts.openSans(color: AppColors.error, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ],
                const SizedBox(height: 22),

                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        label: 'Cancel',
                        primary: false,
                        onTap: _sending ? null : () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionButton(
                        label: _sending ? 'Sending...' : 'Send',
                        primary: true,
                        onTap: _sending ? null : _send,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ---------------- LABEL ---------------- */

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.openSans(fontSize: 13, fontWeight: FontWeight.w600),
    );
  }
}

/* ---------------- INPUT ---------------- */

class _InputPill extends StatelessWidget {
  final TextEditingController controller;
  final String hint;

  const _InputPill({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: TextField(
        controller: controller,
        style: GoogleFonts.openSans(fontSize: 12, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.openSans(color: Colors.black45, fontSize: 11),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
        ),
      ),
    );
  }
}

/* ---------------- TEMPLATE ---------------- */

class _TemplateButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _TemplateButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: GoogleFonts.openSans(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/* ---------------- MESSAGE BOX ---------------- */

class _BigMessageBox extends StatelessWidget {
  final TextEditingController controller;
  final String hint;

  const _BigMessageBox({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: controller,
        maxLines: null,
        style: GoogleFonts.openSans(fontSize: 12, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.openSans(color: Colors.black45, fontSize: 11),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

/* ---------------- ACTION BUTTON ---------------- */

class _ActionButton extends StatelessWidget {
  final String label;
  final bool primary;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          label,
          style: GoogleFonts.openSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: primary ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }
}
