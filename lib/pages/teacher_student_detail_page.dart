import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/review_schedule_models.dart';
import '../models/teacher_models.dart';
import '../services/review_schedule_service.dart';
import '../services/teacher_service.dart';
import 'teacher_message_dialog.dart';

class TeacherStudentDetailPage extends StatefulWidget {
  final TeacherStudentSummary student;

  const TeacherStudentDetailPage({
    super.key,
    required this.student,
  });

  @override
  State<TeacherStudentDetailPage> createState() =>
      _TeacherStudentDetailPageState();
}

class _TeacherStudentDetailPageState extends State<TeacherStudentDetailPage> {
  final TeacherService _teacherService = TeacherService();
  final ReviewScheduleService _reviewService = ReviewScheduleService();

  @override
  Widget build(BuildContext context) {
    final student = widget.student;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: Text(student.displayName),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Send message',
            onPressed: _sendMessage,
            icon: const Icon(Icons.chat_bubble_outline_rounded),
          ),
          IconButton(
            tooltip: 'Remove student assignment',
            onPressed: _removeAssignment,
            icon: const Icon(Icons.person_remove_alt_1_outlined),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildOverview(),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 900;
                    final schedules = _buildSchedules();
                    final messages = _buildMessages();
                    if (narrow) {
                      return Column(
                        children: [
                          schedules,
                          const SizedBox(height: 16),
                          messages,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 6, child: schedules),
                        const SizedBox(width: 16),
                        Expanded(flex: 4, child: messages),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createReview,
        icon: const Icon(Icons.add_alarm_rounded),
        label: const Text('Schedule review'),
      ),
    );
  }

  Widget _buildOverview() {
    final student = widget.student;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFF153E7C),
                child: Text(
                  student.displayName.isEmpty
                      ? '?'
                      : student.displayName[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      student.displayName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      student.email,
                      style: const TextStyle(color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              _RiskBadge(level: student.riskLevel),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _InfoMetric(
                title: 'Current topic',
                value: student.currentTopic,
                icon: Icons.menu_book_rounded,
              ),
              _InfoMetric(
                title: 'Mastery',
                value: '${student.masteryPercent}%',
                icon: Icons.workspace_premium_outlined,
              ),
              _InfoMetric(
                title: 'Retention',
                value: '${student.retentionPercent}%',
                icon: Icons.psychology_alt_outlined,
              ),
              _InfoMetric(
                title: 'Overdue reviews',
                value: '${student.overdueReviews}',
                icon: Icons.warning_amber_rounded,
              ),
              _InfoMetric(
                title: 'Help requests',
                value: '${student.pendingHelpRequests}',
                icon: Icons.support_agent_rounded,
              ),
            ],
          ),
          if (student.riskReasons.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Why this student needs attention',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final reason in student.riskReasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 5),
                      child: Icon(
                        Icons.circle,
                        size: 7,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(reason)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildSchedules() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Review schedule',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _createReview,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add review'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          StreamBuilder<List<ReviewSchedule>>(
            stream: _teacherService.watchStudentSchedules(widget.student.studentId),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final schedules = snapshot.data!;
              if (schedules.isEmpty) {
                return const _EmptyState(
                  icon: Icons.event_note_outlined,
                  text: 'No review schedules recorded yet.',
                );
              }
              return Column(
                children: schedules.take(12).map((schedule) {
                  final overdue = schedule.isOverdue;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: overdue
                          ? const Color(0xFFFFF1F2)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: overdue
                            ? const Color(0xFFFCA5A5)
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFF153E7C)
                                .withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: const Icon(
                            Icons.event_repeat_rounded,
                            color: Color(0xFF153E7C),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                schedule.conceptName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${DateFormat('dd MMM yyyy, h:mm a').format(schedule.scheduledAt)} • ${schedule.durationMinutes} min',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              overdue ? 'Overdue' : schedule.status.label,
                              style: TextStyle(
                                color: overdue
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFF153E7C),
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              '${schedule.masteryScore.round()}% mastery',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Teacher messages',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Send message',
                onPressed: _sendMessage,
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          StreamBuilder<List<TeacherMessage>>(
            stream: _teacherService
                .watchMessagesForStudent(widget.student.studentId),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final messages = snapshot.data!;
              if (messages.isEmpty) {
                return const _EmptyState(
                  icon: Icons.mark_chat_unread_outlined,
                  text: 'No messages sent yet.',
                );
              }
              return Column(
                children: messages.take(10).map((message) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.subject,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 5),
                        Text(message.message),
                        if (message.practiceQuestion != null &&
                            message.practiceQuestion!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Practice: ${message.practiceQuestion}',
                            style: const TextStyle(
                              color: Color(0xFF153E7C),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 7),
                        Text(
                          message.createdAt == null
                              ? 'Sending...'
                              : DateFormat('dd MMM, h:mm a')
                                  .format(message.createdAt!),
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage() async {
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) => TeacherMessageDialog(
        studentId: widget.student.studentId,
        studentName: widget.student.displayName,
      ),
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message sent to the student.')),
      );
    }
  }

  Future<void> _removeAssignment() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove student assignment?'),
        content: Text(
          '${widget.student.displayName} will no longer appear on your teacher dashboard. Existing learning data will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _teacherService.removeStudentAssignment(widget.student.studentId);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Student assignment removed.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _createReview() async {
    final result = await showDialog<_ManualReviewResult>(
      context: context,
      builder: (_) => _ManualReviewDialog(
        defaultConcept: widget.student.currentTopic == 'No active topic'
            ? ''
            : widget.student.currentTopic,
      ),
    );
    if (result == null) return;

    try {
      await _reviewService.createManualSchedule(
        studentId: widget.student.studentId,
        conceptName: result.conceptName,
        scheduledAt: result.scheduledAt,
        durationMinutes: result.durationMinutes,
        reason: result.reason,
        priority: result.priority,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review schedule created.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }
}

class _ManualReviewDialog extends StatefulWidget {
  final String defaultConcept;
  const _ManualReviewDialog({required this.defaultConcept});

  @override
  State<_ManualReviewDialog> createState() => _ManualReviewDialogState();
}

class _ManualReviewDialogState extends State<_ManualReviewDialog> {
  late final TextEditingController _concept =
      TextEditingController(text: widget.defaultConcept);
  final TextEditingController _reason = TextEditingController(
    text: 'Teacher intervention based on current mastery and review progress.',
  );
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 18, minute: 0);
  int _duration = 30;
  ReviewPriority _priority = ReviewPriority.reviewSoon;

  @override
  void dispose() {
    _concept.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create review schedule'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _concept,
                decoration: const InputDecoration(
                  labelText: 'Mathematics topic',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_month_rounded),
                title: const Text('Date'),
                subtitle: Text(DateFormat('dd MMMM yyyy').format(_date)),
                onTap: _pickDate,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_rounded),
                title: const Text('Time'),
                subtitle: Text(_time.format(context)),
                onTap: _pickTime,
              ),
              DropdownButtonFormField<int>(
                initialValue: _duration,
                decoration: const InputDecoration(labelText: 'Duration'),
                items: const [20, 30, 45, 60]
                    .map((value) => DropdownMenuItem(
                          value: value,
                          child: Text('$value minutes'),
                        ))
                    .toList(),
                onChanged: (value) =>
                    setState(() => _duration = value ?? _duration),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ReviewPriority>(
                initialValue: _priority,
                decoration: const InputDecoration(labelText: 'Priority'),
                items: ReviewPriority.values
                    .map((value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ))
                    .toList(),
                onChanged: (value) =>
                    setState(() => _priority = value ?? _priority),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Reason shown to student',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final concept = _concept.text.trim();
            if (concept.isEmpty) return;
            final scheduledAt = DateTime(
              _date.year,
              _date.month,
              _date.day,
              _time.hour,
              _time.minute,
            );
            Navigator.pop(
              context,
              _ManualReviewResult(
                conceptName: concept,
                scheduledAt: scheduledAt,
                durationMinutes: _duration,
                reason: _reason.text.trim(),
                priority: _priority,
              ),
            );
          },
          child: const Text('Create'),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }
}

class _ManualReviewResult {
  final String conceptName;
  final DateTime scheduledAt;
  final int durationMinutes;
  final String reason;
  final ReviewPriority priority;

  const _ManualReviewResult({
    required this.conceptName,
    required this.scheduledAt,
    required this.durationMinutes,
    required this.reason,
    required this.priority,
  });
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: child,
    );
  }
}

class _InfoMetric extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _InfoMetric({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF153E7C)),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RiskBadge extends StatelessWidget {
  final StudentRiskLevel level;
  const _RiskBadge({required this.level});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: level.chipColor.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: level.chipColor),
      ),
      child: Text(
        level.label,
        style: TextStyle(
          color: level.chipColor,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyState({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 38, color: const Color(0xFF94A3B8)),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }
}
