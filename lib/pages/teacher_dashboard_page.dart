import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/teacher_models.dart';
import '../services/teacher_service.dart';
import '../widgets/teacher_app_shell.dart';
import 'teacher_message_dialog.dart';
import 'teacher_student_detail_page.dart';

class TeacherDashboardPage extends StatefulWidget {
  const TeacherDashboardPage({super.key});

  @override
  State<TeacherDashboardPage> createState() => _TeacherDashboardPageState();
}

class _TeacherDashboardPageState extends State<TeacherDashboardPage> {
  final TeacherService _service = TeacherService();
  TeacherNavSection _active = TeacherNavSection.dashboard;
  String _query = '';
  StudentRiskLevel? _riskFilter;

  String get _teacherId => FirebaseAuth.instance.currentUser?.uid ?? '';

  String get _displayName {
    final user = FirebaseAuth.instance.currentUser;
    return user?.displayName?.split(' ').first ??
        user?.email?.split('@').first ??
        'Teacher';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TeacherHelpRequest>>(
      stream: _teacherId.isEmpty
          ? const Stream<List<TeacherHelpRequest>>.empty()
          : _service.watchHelpRequests(teacherId: _teacherId),
      builder: (context, helpSnapshot) {
        final notificationCount = helpSnapshot.data
                ?.where((request) => request.status == HelpRequestStatus.pending)
                .length ??
            0;
        return TeacherAppShell(
          activeSection: _active,
          userName: _displayName,
          notificationCount: notificationCount,
          onSectionSelected: (section) => setState(() => _active = section),
          child: switch (_active) {
            TeacherNavSection.dashboard => _dashboardBody(),
            TeacherNavSection.helpRequests => _helpRequestsBody(),
            TeacherNavSection.settings => _settingsBody(),
          },
        );
      },
    );
  }

  Widget _dashboardBody() {
    return StreamBuilder<List<TeacherStudentSummary>>(
      stream: _service.watchAssignedStudents(_teacherId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ErrorState(message: snapshot.error.toString());
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final students = snapshot.data!;
        final filtered = students.where((student) {
          final q = _query.trim().toLowerCase();
          if (q.isNotEmpty &&
              !student.displayName.toLowerCase().contains(q) &&
              !student.email.toLowerCase().contains(q) &&
              !student.currentTopic.toLowerCase().contains(q)) {
            return false;
          }
          if (_riskFilter != null && student.riskLevel != _riskFilter) {
            return false;
          }
          return true;
        }).toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 36),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Teacher Dashboard',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: neuromathixText,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Monitor mastery, retention, overdue reviews, and student help requests.',
                              style: TextStyle(
                                color: neuromathixMuted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _assignStudent,
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: const Text('Assign student'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _metricCards(students),
                  const SizedBox(height: 16),
                  _WhiteCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final search = TextField(
                              onChanged: (value) =>
                                  setState(() => _query = value),
                              decoration: InputDecoration(
                                hintText: 'Search student, email, or topic...',
                                prefixIcon: const Icon(Icons.search_rounded),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: neuromathixBorder,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: neuromathixBorder,
                                  ),
                                ),
                              ),
                            );
                            final filter = DropdownButtonFormField<StudentRiskLevel?>(
                              initialValue: _riskFilter,
                              decoration: InputDecoration(
                                labelText: 'Risk level',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              items: [
                                const DropdownMenuItem<StudentRiskLevel?>(
                                  value: null,
                                  child: Text('All risk levels'),
                                ),
                                ...StudentRiskLevel.values.map(
                                  (value) => DropdownMenuItem<StudentRiskLevel?>(
                                    value: value,
                                    child: Text(value.label),
                                  ),
                                ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _riskFilter = value),
                            );
                            if (constraints.maxWidth < 760) {
                              return Column(
                                children: [
                                  search,
                                  const SizedBox(height: 10),
                                  filter,
                                ],
                              );
                            }
                            return Row(
                              children: [
                                Expanded(child: search),
                                const SizedBox(width: 12),
                                SizedBox(width: 240, child: filter),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        if (students.isEmpty)
                          _NoStudents(onAssign: _assignStudent)
                        else if (filtered.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: Text('No students match the selected filters.'),
                            ),
                          )
                        else
                          _StudentsTable(
                            students: filtered,
                            onOpen: _openStudent,
                            onMessage: _messageStudent,
                          ),
                      ],
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

  Widget _metricCards(List<TeacherStudentSummary> students) {
    final urgent = students
        .where((student) => student.riskLevel == StudentRiskLevel.urgent)
        .length;
    final overdue = students.fold<int>(
      0,
      (sum, student) => sum + student.overdueReviews,
    );
    final pending = students.fold<int>(
      0,
      (sum, student) => sum + student.pendingHelpRequests,
    );
    final average = students.isEmpty
        ? 0
        : (students.fold<int>(0, (sum, item) => sum + item.masteryPercent) /
                students.length)
            .round();

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _MetricCard(
          icon: Icons.groups_rounded,
          value: '${students.length}',
          label: 'Assigned students',
          color: neuromathixBlue,
        ),
        _MetricCard(
          icon: Icons.warning_amber_rounded,
          value: '$urgent',
          label: 'Urgent risk',
          color: const Color(0xFFDC2626),
        ),
        _MetricCard(
          icon: Icons.event_busy_rounded,
          value: '$overdue',
          label: 'Overdue reviews',
          color: const Color(0xFFD97706),
        ),
        _MetricCard(
          icon: Icons.support_agent_rounded,
          value: '$pending',
          label: 'Help requests',
          color: const Color(0xFF7C3AED),
        ),
        _MetricCard(
          icon: Icons.workspace_premium_outlined,
          value: '$average%',
          label: 'Average mastery',
          color: const Color(0xFF059669),
        ),
      ],
    );
  }

  Widget _helpRequestsBody() {
    return StreamBuilder<List<TeacherHelpRequest>>(
      stream: _service.watchHelpRequests(
        teacherId: _teacherId,
        includeResolved: true,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ErrorState(message: snapshot.error.toString());
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final requests = snapshot.data!;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Student Help Requests',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Review the question context, XAI data, and send a teacher response.',
                    style: TextStyle(color: neuromathixMuted),
                  ),
                  const SizedBox(height: 18),
                  if (requests.isEmpty)
                    const _WhiteCard(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text('No student help requests yet.'),
                        ),
                      ),
                    )
                  else
                    for (final request in requests) ...[
                      _HelpRequestCard(
                        request: request,
                        onRespond: () => _respondToRequest(request),
                        onResolve: () => _resolveRequest(request),
                      ),
                      const SizedBox(height: 12),
                    ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _settingsBody() {
    final user = FirebaseAuth.instance.currentUser;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: _WhiteCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Teacher Account',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 18),
                ListTile(
                  leading: const Icon(Icons.person_outline_rounded),
                  title: Text(user?.displayName ?? 'Teacher'),
                  subtitle: const Text('Display name'),
                ),
                ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: Text(user?.email ?? ''),
                  subtitle: const Text('Email address'),
                ),
                ListTile(
                  leading: const Icon(Icons.verified_user_outlined),
                  title: Text(user?.emailVerified == true ? 'Verified' : 'Not verified'),
                  subtitle: const Text('Email verification'),
                ),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: Text(_teacherId),
                  subtitle: const Text('Teacher ID used for student assignment'),
                ),
                const Divider(),
                const Text(
                  'Teacher accounts should be created by an administrator. Public signup creates student accounts only.',
                  style: TextStyle(color: neuromathixMuted, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _assignStudent() async {
    final email = await showDialog<String>(
      context: context,
      builder: (_) => const _AssignStudentDialog(),
    );
    if (email == null || email.trim().isEmpty) return;
    try {
      await _service.assignStudentByEmail(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Student assigned successfully.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  void _openStudent(TeacherStudentSummary student) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeacherStudentDetailPage(student: student),
      ),
    );
  }

  Future<void> _messageStudent(TeacherStudentSummary student) async {
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) => TeacherMessageDialog(
        studentId: student.studentId,
        studentName: student.displayName,
      ),
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message sent.')),
      );
    }
  }

  Future<void> _respondToRequest(TeacherHelpRequest request) async {
    await _service.markHelpRequestViewed(request.id);
    if (!mounted) return;
    final response = await showDialog<_HelpResponse>(
      context: context,
      builder: (_) => _HelpResponseDialog(request: request),
    );
    if (response == null) return;
    try {
      await _service.respondToHelpRequest(
        request: request,
        message: response.message,
        practiceQuestion: response.practiceQuestion,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Response sent to student.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _resolveRequest(TeacherHelpRequest request) async {
    try {
      await _service.markHelpRequestResolved(request.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }
}

class _StudentsTable extends StatelessWidget {
  final List<TeacherStudentSummary> students;
  final ValueChanged<TeacherStudentSummary> onOpen;
  final ValueChanged<TeacherStudentSummary> onMessage;

  const _StudentsTable({
    required this.students,
    required this.onOpen,
    required this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
        columns: const [
          DataColumn(label: Text('Student')),
          DataColumn(label: Text('Current topic')),
          DataColumn(label: Text('Mastery')),
          DataColumn(label: Text('Retention')),
          DataColumn(label: Text('Next review')),
          DataColumn(label: Text('Risk')),
          DataColumn(label: Text('Actions')),
        ],
        rows: students.map((student) {
          return DataRow(
            onSelectChanged: (_) => onOpen(student),
            cells: [
              DataCell(
                SizedBox(
                  width: 180,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        student.email,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: neuromathixMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              DataCell(SizedBox(width: 160, child: Text(student.currentTopic))),
              DataCell(Text('${student.masteryPercent}%')),
              DataCell(Text('${student.retentionPercent}%')),
              DataCell(
                Text(
                  student.nextReviewAt == null
                      ? 'Not scheduled'
                      : DateFormat('dd MMM, h:mm a').format(student.nextReviewAt!),
                ),
              ),
              DataCell(_RiskChip(level: student.riskLevel)),
              DataCell(
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Open student',
                      onPressed: () => onOpen(student),
                      icon: const Icon(Icons.open_in_new_rounded),
                    ),
                    IconButton(
                      tooltip: 'Send message',
                      onPressed: () => onMessage(student),
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                    ),
                  ],
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _HelpRequestCard extends StatelessWidget {
  final TeacherHelpRequest request;
  final VoidCallback onRespond;
  final VoidCallback onResolve;

  const _HelpRequestCard({
    required this.request,
    required this.onRespond,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = request.status == HelpRequestStatus.resolved;
    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${request.studentName} • ${request.conceptName}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (request.createdAt != null)
                      Text(
                        DateFormat('dd MMM yyyy, h:mm a')
                            .format(request.createdAt!),
                        style: const TextStyle(
                          color: neuromathixMuted,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              _StatusChip(status: request.status),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            request.studentMessage,
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ContextPill(label: 'Score', value: '${request.sessionScore.round()}%'),
              _ContextPill(label: 'Hints', value: '${request.hintsUsed}'),
              _ContextPill(label: 'Error', value: request.errorType),
            ],
          ),
          if (request.questionText.isNotEmpty) ...[
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text(
                'Question context',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(request.questionText),
                      if (request.studentAnswer.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('Student answer: ${request.studentAnswer}'),
                        ),
                      if (request.correctAnswer.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text('Correct answer: ${request.correctAnswer}'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!resolved)
                TextButton(
                  onPressed: onResolve,
                  child: const Text('Mark resolved'),
                ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: resolved ? null : onRespond,
                icon: const Icon(Icons.reply_rounded),
                label: const Text('Respond'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HelpResponseDialog extends StatefulWidget {
  final TeacherHelpRequest request;
  const _HelpResponseDialog({required this.request});

  @override
  State<_HelpResponseDialog> createState() => _HelpResponseDialogState();
}

class _HelpResponseDialogState extends State<_HelpResponseDialog> {
  final TextEditingController _message = TextEditingController();
  final TextEditingController _practice = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    _practice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Respond to ${widget.request.studentName}'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: neuromathixBorder),
                ),
                child: Text(widget.request.studentMessage),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _message,
                minLines: 5,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Teacher explanation',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _practice,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Optional practice question',
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
            if (_message.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              _HelpResponse(
                message: _message.text.trim(),
                practiceQuestion: _practice.text.trim().isEmpty
                    ? null
                    : _practice.text.trim(),
              ),
            );
          },
          child: const Text('Send response'),
        ),
      ],
    );
  }
}

class _HelpResponse {
  final String message;
  final String? practiceQuestion;
  const _HelpResponse({required this.message, this.practiceQuestion});
}

class _AssignStudentDialog extends StatefulWidget {
  const _AssignStudentDialog();

  @override
  State<_AssignStudentDialog> createState() => _AssignStudentDialogState();
}

class _AssignStudentDialogState extends State<_AssignStudentDialog> {
  final TextEditingController _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Assign existing student'),
      content: SizedBox(
        width: 440,
        child: TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Student email address',
            hintText: 'student@example.com',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Assign'),
        ),
      ],
    );
  }

  void _submit() {
    final email = _email.text.trim();
    if (email.isEmpty) return;
    Navigator.pop(context, email);
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _MetricCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 235,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: neuromathixBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 11),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: neuromathixMuted,
                    fontSize: 11,
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

class _RiskChip extends StatelessWidget {
  final StudentRiskLevel level;
  const _RiskChip({required this.level});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: level.chipColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        level.label,
        style: TextStyle(
          color: level.chipColor,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final HelpRequestStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      HelpRequestStatus.pending => const Color(0xFFDC2626),
      HelpRequestStatus.viewed => const Color(0xFFD97706),
      HelpRequestStatus.responded => const Color(0xFF2563EB),
      HelpRequestStatus.resolved => const Color(0xFF059669),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ContextPill extends StatelessWidget {
  final String label;
  final String value;
  const _ContextPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _WhiteCard extends StatelessWidget {
  final Widget child;
  const _WhiteCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: neuromathixBorder),
      ),
      child: child,
    );
  }
}

class _NoStudents extends StatelessWidget {
  final VoidCallback onAssign;
  const _NoStudents({required this.onAssign});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 42),
      child: Center(
        child: Column(
          children: [
            const Icon(
              Icons.group_add_outlined,
              size: 48,
              color: neuromathixMuted,
            ),
            const SizedBox(height: 12),
            const Text(
              'No students assigned yet',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 5),
            const Text(
              'Assign an existing student account using the student email address.',
              textAlign: TextAlign.center,
              style: TextStyle(color: neuromathixMuted),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onAssign,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Assign student'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Could not load teacher data.\n$message'),
      ),
    );
  }
}
