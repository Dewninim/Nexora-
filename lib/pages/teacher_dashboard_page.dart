import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/teacher_models.dart';
import '../services/teacher_service.dart';
import '../theme/app_theme.dart';
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
          onNotificationTap: () => setState(() => _active = TeacherNavSection.helpRequests),
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
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Hero Banner ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF060B19), Color(0xFF0E1A38), Color(0xFF1E3A8A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.goldBorder.withValues(alpha: 0.4), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.25),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Teacher Dashboard',
                                style: GoogleFonts.openSans(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Monitor student cohort mastery, retention, overdue reviews, and active help requests.',
                                style: GoogleFonts.openSans(
                                  fontSize: 14,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                            shadowColor: AppColors.accent.withValues(alpha: 0.4),
                          ),
                          onPressed: _assignStudent,
                          icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                          label: Text('Assign Student', style: AppText.button),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _metricCards(students),
                  const SizedBox(height: 24),
                  _WhiteCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Student Cohort Overview', style: AppText.sectionHeader),
                        const SizedBox(height: 16),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final search = TextField(
                              onChanged: (value) =>
                                  setState(() => _query = value),
                              style: AppText.body,
                              decoration: InputDecoration(
                                hintText: 'Search student, email, or topic...',
                                hintStyle: AppText.bodyMuted,
                                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted),
                                filled: true,
                                fillColor: AppColors.surface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: AppColors.border,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: AppColors.border,
                                  ),
                                ),
                              ),
                            );
                            final filter = DropdownButtonFormField<StudentRiskLevel?>(
                              initialValue: _riskFilter,
                              style: AppText.body,
                              decoration: InputDecoration(
                                labelText: 'Risk level',
                                labelStyle: AppText.caption,
                                filled: true,
                                fillColor: AppColors.surface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppColors.border),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppColors.border),
                                ),
                              ),
                              items: [
                                DropdownMenuItem<StudentRiskLevel?>(
                                  value: null,
                                  child: Text('All risk levels', style: AppText.body),
                                ),
                                ...StudentRiskLevel.values.map(
                                  (value) => DropdownMenuItem<StudentRiskLevel?>(
                                    value: value,
                                    child: Text(value.label, style: AppText.body),
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
                        const SizedBox(height: 20),
                        if (students.isEmpty)
                          _NoStudents(onAssign: _assignStudent)
                        else if (filtered.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: Text(
                                'No students match the selected filters.',
                                style: AppText.bodyMuted,
                              ),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth < 700
            ? (constraints.maxWidth - 16) / 2
            : (constraints.maxWidth - 64) / 5;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                icon: Icons.groups_rounded,
                value: '${students.length}',
                label: 'Assigned Students',
                color: AppColors.accent,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                icon: Icons.warning_amber_rounded,
                value: '$urgent',
                label: 'Urgent Risk',
                color: AppColors.error,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                icon: Icons.event_busy_rounded,
                value: '$overdue',
                label: 'Overdue Reviews',
                color: AppColors.warning,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                icon: Icons.support_agent_rounded,
                value: '$pending',
                label: 'Help Requests',
                color: AppColors.info,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                icon: Icons.workspace_premium_rounded,
                value: '$average%',
                label: 'Average Mastery',
                color: AppColors.success,
              ),
            ),
          ],
        );
      },
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
                  Text(
                    'Student Help Requests',
                    style: GoogleFonts.openSans(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Review student question context, XAI diagnostic metrics, and send immediate teacher interventions.',
                    style: GoogleFonts.openSans(color: AppColors.textMuted, fontSize: 15),
                  ),
                  const SizedBox(height: 24),
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
    final teacherName = user?.displayName ?? 'Teacher';
    final teacherEmail = user?.email ?? 'teacher@neuromathix.edu';
    final initial = teacherName.trim().isEmpty ? 'T' : teacherName.trim()[0].toUpperCase();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 950),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Standard Page Header
              Text(
                'Teacher Settings & Classroom',
                style: GoogleFonts.openSans(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Manage your educator profile, classroom assignment ID, and notification preferences.',
                style: GoogleFonts.openSans(color: AppColors.textMuted, fontSize: 15),
              ),
              const SizedBox(height: 24),

              // Educator Profile Banner Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.sidebarNavy,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.goldAccent, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.goldAccent.withValues(alpha: 0.3),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initial,
                        style: GoogleFonts.openSans(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                teacherName,
                                style: GoogleFonts.openSans(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textDark,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFECFDF5),
                                  borderRadius: BorderRadius.circular(100),
                                  border: Border.all(color: const Color(0xFFA7F3D0)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.check_circle, size: 14, color: Color(0xFF10B981)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Verified Educator',
                                      style: GoogleFonts.openSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF047857),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            teacherEmail,
                            style: GoogleFonts.openSans(
                              fontSize: 14,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Teacher ID & Classroom Join Code Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.goldBorder.withValues(alpha: 0.7)),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.goldAccent.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.goldLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.qr_code_2_rounded, color: AppColors.goldAccent, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Teacher Assignment ID',
                              style: GoogleFonts.openSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textDark,
                              ),
                            ),
                            Text(
                              'Share this code with students to connect them to your classroom.',
                              style: GoogleFonts.openSans(fontSize: 13, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              _teacherId.isNotEmpty ? _teacherId : 'aA1BzR0E9pd9fb1r8hh8BinMOzF3',
                              style: GoogleFonts.openSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.accent,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _teacherId));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Teacher ID copied to clipboard!'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            label: const Text('Copy ID'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Notification & Automated Alert Settings
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Classroom Alerts & Notifications',
                      style: GoogleFonts.openSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SwitchListTile(
                      value: true,
                      onChanged: (val) {},
                      title: Text('Student Practice Submissions', style: GoogleFonts.openSans(fontWeight: FontWeight.w600)),
                      subtitle: Text('Receive notifications when a student completes a assigned question set.', style: GoogleFonts.openSans(fontSize: 13, color: AppColors.textMuted)),
                      activeThumbColor: AppColors.accent,
                    ),
                    const Divider(),
                    SwitchListTile(
                      value: true,
                      onChanged: (val) {},
                      title: Text('Low Memory Retention Warnings', style: GoogleFonts.openSans(fontWeight: FontWeight.w600)),
                      subtitle: Text('Alert when a student falls below 50% predicted retention on key topics.', style: GoogleFonts.openSans(fontSize: 13, color: AppColors.textMuted)),
                      activeThumbColor: AppColors.accent,
                    ),
                    const Divider(),
                    SwitchListTile(
                      value: true,
                      onChanged: (val) {},
                      title: Text('AI Auto-Grading & Help Requests', style: GoogleFonts.openSans(fontWeight: FontWeight.w600)),
                      subtitle: Text('Allow NeuroMathix AI to assist with step-by-step student diagnostic explanations.', style: GoogleFonts.openSans(fontSize: 13, color: AppColors.textMuted)),
                      activeThumbColor: AppColors.accent,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  'Teacher accounts are managed securely under NeuroMathix Administrative License.',
                  style: GoogleFonts.openSans(color: AppColors.textMuted, fontSize: 13),
                ),
              ),
            ],
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
                        style: const TextStyle(fontWeight: FontWeight.w600),
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
    final initial = request.studentName.trim().isEmpty ? 'S' : request.studentName.trim()[0].toUpperCase();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: resolved ? AppColors.border : AppColors.goldBorder.withValues(alpha: 0.6),
          width: resolved ? 1 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.sidebarNavy,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.goldAccent, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: GoogleFonts.openSans(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          request.studentName,
                          style: GoogleFonts.openSans(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            request.conceptName,
                            style: GoogleFonts.openSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    if (request.createdAt != null)
                      Text(
                        DateFormat('dd MMM yyyy, h:mm a').format(request.createdAt!),
                        style: GoogleFonts.openSans(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              _StatusChip(status: request.status),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              request.studentMessage,
              style: GoogleFonts.openSans(
                fontSize: 14,
                height: 1.5,
                color: AppColors.textDark,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ContextPill(label: 'Score', value: '${request.sessionScore.round()}%'),
              _ContextPill(label: 'Hints Used', value: '${request.hintsUsed}'),
              _ContextPill(label: 'Diagnostic Error', value: request.errorType),
            ],
          ),
          if (request.questionText.isNotEmpty) ...[
            const SizedBox(height: 14),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                'View Diagnostic Question Context',
                style: GoogleFonts.openSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.accent,
                ),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(request.questionText, style: GoogleFonts.openSans(fontSize: 13, height: 1.4)),
                        if (request.studentAnswer.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('Student answer: ${request.studentAnswer}', style: GoogleFonts.openSans(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFFEF4444))),
                          ),
                        if (request.correctAnswer.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Text('Correct answer: ${request.correctAnswer}', style: GoogleFonts.openSans(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF10B981))),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!resolved)
                OutlinedButton.icon(
                  onPressed: onResolve,
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                  label: const Text('Mark Resolved'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF10B981),
                    side: const BorderSide(color: Color(0xFF10B981)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: resolved ? null : onRespond,
                icon: const Icon(Icons.reply_rounded, size: 16),
                label: Text(resolved ? 'Resolved' : 'Respond to Student'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 2,
                ),
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
  final TeacherService _service = TeacherService();
  List<Map<String, String>> _allStudents = [];
  Map<String, String>? _selectedStudent;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchStudents();
  }

  Future<void> _fetchStudents() async {
    try {
      final students = await _service.getAllRegisteredStudents();
      if (!mounted) return;
      setState(() {
        _allStudents = students;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Assign Registered Student', style: AppText.sectionHeader),
      content: SizedBox(
        width: 480,
        child: _loading
            ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
            : _error != null
                ? Text('Error loading students: $_error', style: AppText.bodyMuted)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Type a student\'s name or email to view instant registered suggestions:',
                        style: AppText.bodyMuted,
                      ),
                      const SizedBox(height: 16),
                      Autocomplete<Map<String, String>>(
                        displayStringForOption: (s) => '${s['displayName']} (${s['email']})',
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          final query = textEditingValue.text.trim().toLowerCase();
                          if (query.isEmpty) {
                            return _allStudents;
                          }
                          return _allStudents.where((s) {
                            final name = s['displayName']?.toLowerCase() ?? '';
                            final email = s['email']?.toLowerCase() ?? '';
                            return name.contains(query) || email.contains(query);
                          });
                        },
                        onSelected: (Map<String, String> selection) {
                          setState(() => _selectedStudent = selection);
                        },
                        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            autofocus: true,
                            style: AppText.body,
                            decoration: InputDecoration(
                              labelText: 'Type Student Name or Email...',
                              labelStyle: AppText.caption,
                              prefixIcon: const Icon(Icons.person_search_rounded, color: AppColors.primary),
                              filled: true,
                              fillColor: AppColors.surface,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: AppColors.border),
                              ),
                            ),
                          );
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 6,
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.white,
                              child: Container(
                                width: 440,
                                constraints: const BoxConstraints(maxHeight: 220),
                                decoration: BoxDecoration(
                                  border: Border.all(color: AppColors.border),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ListView.separated(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  separatorBuilder: (context, index) => const Divider(height: 1, color: AppColors.border),
                                  itemBuilder: (BuildContext context, int index) {
                                    final option = options.elementAt(index);
                                    return ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                        child: Text(
                                          (option['displayName'] ?? 'S')[0].toUpperCase(),
                                          style: GoogleFonts.openSans(color: AppColors.primary, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      title: Text(option['displayName'] ?? '', style: AppText.body),
                                      subtitle: Text(option['email'] ?? '', style: AppText.bodyMuted),
                                      onTap: () => onSelected(option),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: AppText.bodyMuted),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _selectedStudent == null ? null : _submit,
          child: Text('Assign Student', style: AppText.button),
        ),
      ],
    );
  }

  void _submit() {
    final email = _selectedStudent?['email'];
    if (email == null || email.isEmpty) return;
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
                    fontWeight: FontWeight.w600,
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
          fontWeight: FontWeight.w600,
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
          fontWeight: FontWeight.w600,
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
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
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
