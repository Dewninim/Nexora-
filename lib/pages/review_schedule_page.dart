import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../config/api_config.dart';
import '../theme/app_theme.dart';

class ReviewSchedulePage extends StatefulWidget {
  const ReviewSchedulePage({super.key});

  @override
  State<ReviewSchedulePage> createState() => _ReviewSchedulePageState();
}

class _ReviewSchedulePageState extends State<ReviewSchedulePage> {
  // Previously this entire page was hardcoded sample data copied from a
  // Figma mockup (a static Feb 2026 calendar with "Linear Algebra" /
  // "Integration" entries that never changed no matter what the student
  // actually studied). Everything below marked REAL now comes from
  // GET /user/<uid>/materials — the same real forgetting-curve data that
  // powers the dashboard's Next Reviews section.
  DateTime _focusedDay = _dateOnly(DateTime.now());
  DateTime _selectedDay = _dateOnly(DateTime.now());
  CalendarFormat _format = CalendarFormat.month;

  bool _loading = true;
  String? _loadError;
  List<_MaterialSchedule> _materials = [];

  _PriorityFilter _filter = _PriorityFilter.all;
  late List<_ScheduleRowState> _scheduleRows = [];

  // Assumed per-review study duration — the backend tracks each session's
  // actual time_taken historically, but doesn't currently expose a
  // per-material "expected next session length" figure via
  // /user/<uid>/materials, so this is a reasonable flat estimate rather
  // than a real per-material number. Flagged here so it isn't mistaken for
  // measured data.
  static const Duration _assumedReviewDuration = Duration(minutes: 30);

  @override
  void initState() {
    super.initState();
    _loadMaterials();
  }

  Future<void> _loadMaterials() async {
    setState(() { _loading = true; _loadError = null; });
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
      final r = await http
          .get(Uri.parse('$kApiBaseUrl/user/$uid/materials'))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw Exception('Could not load schedule (${r.statusCode})');
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      final list = (data['materials'] as List? ?? []).cast<Map<String, dynamic>>();
      _materials = list
          .map((m) => _MaterialSchedule.fromJson(m))
          .where((m) => m.nextReviewDate != null)
          .toList();
      if (!mounted) return;
      setState(() { _loading = false; _loadScheduleForSelectedDay(); });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _loadError = e.toString(); });
    }
  }

  // ── REAL, derived from _materials — replaces the old static maps ──
  Map<DateTime, List<_Topic>> get _topicsByDay {
    final map = <DateTime, List<_Topic>>{};
    for (final m in _materials) {
      final day = _dateOnly(m.nextReviewDate!);
      map.putIfAbsent(day, () => []).add(_Topic(
        name: m.filename,
        duration: _assumedReviewDuration,
        priority: m.priority,
      ));
    }
    return map;
  }

  Map<DateTime, List<String>> get _events {
    final map = <DateTime, List<String>>{};
    for (final m in _materials) {
      map[_dateOnly(m.nextReviewDate!)] = const ['Revision'];
    }
    return map;
  }

  int get urgentModules => _materials.where((m) => m.priority == _Priority.urgent).length;
  int get thisWeekCount => _materials
      .where((m) => m.nextReviewDate!.difference(DateTime.now()).inDays <= 7)
      .length;
  Duration get plannedTimeWeek => _assumedReviewDuration * thisWeekCount;
  int get materialsTracked => _materials.length;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF5F6FA),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PageHeader(),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_loadError != null)
              _LoadErrorCard(message: _loadError!, onRetry: _loadMaterials)
            else ...[
              _StatsRow(
                urgentModules: urgentModules,
                thisWeekCount: thisWeekCount,
                plannedTime: plannedTimeWeek,
                materialsTracked: materialsTracked,
              ),
              const SizedBox(height: 14),
              _calendarCard(),
              const SizedBox(height: 14),
              _selectedDaySummaryCard(),
              const SizedBox(height: 14),
              _topicsCard(),
              const SizedBox(height: 14),
              _scheduleTableCard(),
            ],
          ],
        ),
      ),
    );
  }

  /* ------------------------------ Calendar card ------------------------------ */

  Widget _calendarCard() {
    List<String> getEvents(DateTime d) => _events[_dateOnly(d)] ?? const [];

    return _CardShell(
      title: 'Calendar',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Month view', style: GoogleFonts.dmSans(fontSize: 11, color: Colors.black45)),
          const SizedBox(width: 10),
          _Segmented(
            left: 'Month',
            right: 'Week',
            isLeftSelected: _format == CalendarFormat.month,
            onChanged: (isMonth) {
              setState(() => _format = isMonth ? CalendarFormat.month : CalendarFormat.week);
            },
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _CircleIconButton(
                icon: Icons.chevron_left_rounded,
                onTap: () {
                  setState(() {
                    _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1, 1);
                  });
                },
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE6E9F2)),
                ),
                child: Text(
                  DateFormat('MMMM yyyy').format(_focusedDay),
                  style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
              const SizedBox(width: 10),
              _CircleIconButton(
                icon: Icons.chevron_right_rounded,
                onTap: () {
                  setState(() {
                    _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1, 1);
                  });
                },
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          TableCalendar<String>(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2035, 12, 31),
            focusedDay: _focusedDay,
            calendarFormat: _format,
            headerVisible: false,
            availableCalendarFormats: const {
              CalendarFormat.month: 'Month',
              CalendarFormat.week: 'Week',
            },
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            eventLoader: getEvents,
            onDaySelected: (selected, focused) {
              setState(() {
                _selectedDay = _dateOnly(selected);
                _focusedDay = focused;
                _filter = _PriorityFilter.all;

                // (Demo) if day has different topics, swap schedule rows too
                _loadScheduleForSelectedDay();
              });
            },
            onPageChanged: (focused) {
              setState(() => _focusedDay = focused);
            },
            daysOfWeekHeight: 20,
            rowHeight: 35,
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: GoogleFonts.dmSans(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600),
              weekendStyle: GoogleFonts.dmSans(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600),
            ),
            calendarStyle: const CalendarStyle(
              outsideDaysVisible: false,
              defaultDecoration: BoxDecoration(color: Colors.transparent),
              weekendDecoration: BoxDecoration(color: Colors.transparent),
              todayDecoration: BoxDecoration(color: Colors.transparent),
              selectedDecoration: BoxDecoration(color: Colors.transparent),
              markersMaxCount: 1,
            ),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, _) {
                return _DayCell(day: day, isSelected: false, hasMarker: getEvents(day).isNotEmpty);
              },
              selectedBuilder: (context, day, _) {
                return _DayCell(day: day, isSelected: true, hasMarker: getEvents(day).isNotEmpty);
              },
              todayBuilder: (context, day, _) {
                return _DayCell(
                  day: day,
                  isSelected: isSameDay(_selectedDay, day),
                  hasMarker: getEvents(day).isNotEmpty,
                );
              },
              markerBuilder: (context, day, events) => null,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const _LegendDot(label: 'Revisions Scheduled Dates'),
              const Spacer(),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _focusedDay = _dateOnly(DateTime.now());
                    _selectedDay = _dateOnly(DateTime.now());
                    _filter = _PriorityFilter.all;
                    _loadScheduleForSelectedDay();
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: Text('Back to Today', style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _loadScheduleForSelectedDay() {
    // Real topics for the selected day (from _materials), each given a
    // sequential default start time from 18:00 — the backend has no concept
    // of "what hour of day you personally prefer to study", so the actual
    // clock time here remains a local starting suggestion the student can
    // drag via _autoArrange / the time picker, same as before.
    final topics = _topicsByDay[_dateOnly(_selectedDay)] ?? const <_Topic>[];
    var cursor = const TimeOfDay(hour: 18, minute: 0);
    _scheduleRows = topics.map((t) {
      final row = _ScheduleRowState(
        subject: t.name,
        startTime: cursor,
        duration: t.duration,
        reminder: _Reminder.off,
      );
      final end = DateTime(2026, 1, 1, cursor.hour, cursor.minute).add(t.duration);
      cursor = TimeOfDay(hour: end.hour, minute: end.minute);
      return row;
    }).toList();
  }

  /* -------------------------- Selected Day Summary -------------------------- */

  Widget _selectedDaySummaryCard() {
    final topicsForDay = _topicsByDay[_dateOnly(_selectedDay)] ?? const <_Topic>[];
    final sessions = topicsForDay.length;
    final planned = topicsForDay.fold<Duration>(Duration.zero, (sum, t) => sum + t.duration);
    final mainFocus = topicsForDay.isEmpty ? '-' : topicsForDay.last.name;
    // No per-day completion tracking exists yet on the backend for a
    // scheduled-but-not-yet-started review, so this stays 0% until that's
    // built — shown honestly rather than a fabricated progress value.
    final completion = 0.0;

    return _CardShell(
      title: 'Selected Day Summary',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _InfoPill(bg: const Color(0xFFCFFFD1), title: 'Sessions', value: '$sessions Sessions')),
              const SizedBox(width: 10),
              Expanded(child: _InfoPill(bg: const Color(0xFFDFF5FF), title: 'Planned time', value: _fmtDuration(planned))),
              const SizedBox(width: 10),
              Expanded(child: _InfoPill(bg: const Color(0xFFFFD8D8), title: 'Main focus', value: mainFocus)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('Completion', style: GoogleFonts.dmSans(fontSize: 11, color: Colors.black54)),
              const Spacer(),
              Text('${(completion * 100).round()}%', style: GoogleFonts.dmSans(fontSize: 11, color: Colors.black54)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: completion,
              minHeight: 6,
              backgroundColor: const Color(0xFFE9EDF6),
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  /* -------------------------------- Topics -------------------------------- */

  Widget _topicsCard() {
    final all = _topicsByDay[_dateOnly(_selectedDay)] ?? const <_Topic>[];
    final filtered = all.where((t) => _matchesFilter(t.priority, _filter)).toList();

    final filteredSum = filtered.fold<Duration>(Duration.zero, (sum, t) => sum + t.duration);
    final allSum = all.fold<Duration>(Duration.zero, (sum, t) => sum + t.duration);

    return _CardShell(
      title: 'Topics for Selected Day',
      subtitle: 'Filter topics by priority',
      trailing: Text(
        'Showing ${filtered.length}/${all.length} topics • ${_fmtMinutes(filteredSum)} / ${_fmtDuration(allSum)} • ${_filterLabel(_filter)}',
        style: GoogleFonts.dmSans(fontSize: 10.5, color: Colors.black45),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _FilterChip(label: 'All', selected: _filter == _PriorityFilter.all, onTap: () => setState(() => _filter = _PriorityFilter.all)),
              const SizedBox(width: 8),
              _FilterChip(label: 'Urgent', selected: _filter == _PriorityFilter.urgent, onTap: () => setState(() => _filter = _PriorityFilter.urgent)),
              const SizedBox(width: 8),
              _FilterChip(label: 'Review soon', selected: _filter == _PriorityFilter.reviewSoon, onTap: () => setState(() => _filter = _PriorityFilter.reviewSoon)),
              const SizedBox(width: 8),
              _FilterChip(label: 'Safe', selected: _filter == _PriorityFilter.safe, onTap: () => setState(() => _filter = _PriorityFilter.safe)),
            ],
          ),
          const SizedBox(height: 10),
          for (final t in filtered) _TopicRow(topic: t),
        ],
      ),
    );
  }

  /* ----------------------------- Schedule table ----------------------------- */

  Widget _scheduleTableCard() {
    return _CardShell(
      title: 'Schedule time per subject',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFE9EEF7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Row(
              children: [
                Text('Tip:', style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 11)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Set your hardest module for your best focus time. Consistency beats intensity.',
                    style: GoogleFonts.dmSans(fontSize: 11, color: Colors.black54),
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose the start time for each subject. End time is calculated automatically. Use the bell to set a reminder',
            style: GoogleFonts.dmSans(fontSize: 10.5, color: Colors.black45),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < _scheduleRows.length; i++)
            _ScheduleRowWidget(
              row: _scheduleRows[i],
              onChangeTime: (t) => setState(() => _scheduleRows[i] = _scheduleRows[i].copyWith(startTime: t)),
              onChangeReminder: (r) => setState(() => _scheduleRows[i] = _scheduleRows[i].copyWith(reminder: r)),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Spacer(),
              OutlinedButton(
                onPressed: _autoArrange,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  side: const BorderSide(color: Color(0xFFE6E9F2)),
                ),
                child: Text('Auto Arrange', style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 12)),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Time plan saved successfully! Reminders updated.'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: Text('Save Time Plan', style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '• Auto Arrange gives  non overlap time  • After all save time plan',
              style: GoogleFonts.dmSans(fontSize: 10, color: Colors.black45),
            ),
          ),
        ],
      ),
    );
  }

  void _autoArrange() {
    // Demo: keep first start time, then stack sequentially by duration.
    if (_scheduleRows.isEmpty) return;

    final sorted = [..._scheduleRows];
    sorted.sort((a, b) => a.startTime.hour != b.startTime.hour
        ? a.startTime.hour.compareTo(b.startTime.hour)
        : a.startTime.minute.compareTo(b.startTime.minute));

    final first = sorted.first.startTime;
    var cursor = _toDateTime(_selectedDay, first);

    final arranged = <_ScheduleRowState>[];
    for (final row in sorted) {
      final start = TimeOfDay(hour: cursor.hour, minute: cursor.minute);
      arranged.add(row.copyWith(startTime: start));
      cursor = cursor.add(row.duration);
    }

    setState(() => _scheduleRows = arranged);
  }

  /* ------------------------------- Helpers -------------------------------- */

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _toDateTime(DateTime day, TimeOfDay t) =>
      DateTime(day.year, day.month, day.day, t.hour, t.minute);

  static bool _matchesFilter(_Priority p, _PriorityFilter f) {
    switch (f) {
      case _PriorityFilter.all:
        return true;
      case _PriorityFilter.urgent:
        return p == _Priority.urgent;
      case _PriorityFilter.reviewSoon:
        return p == _Priority.reviewSoon;
      case _PriorityFilter.safe:
        return p == _Priority.safe;
    }
  }

  static String _filterLabel(_PriorityFilter f) {
    switch (f) {
      case _PriorityFilter.all:
        return 'All';
      case _PriorityFilter.urgent:
        return 'Urgent';
      case _PriorityFilter.reviewSoon:
        return 'Review soon';
      case _PriorityFilter.safe:
        return 'Safe';
    }
  }

  static String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h <= 0) return '${d.inMinutes}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
    // Figma shows "1h 5m"
  }

  static String _fmtMinutes(Duration d) => '${d.inMinutes}min';
}

/* --------------------------- UI building blocks -------------------------- */

class _PageHeader extends StatelessWidget {
  const _PageHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Review Schedule', style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(
          'View your review schedule with subjects, dates, and time blocks',
          style: GoogleFonts.dmSans(color: Colors.black54, fontSize: 12),
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  final int urgentModules;
  final int thisWeekCount;
  final Duration plannedTime;
  final int materialsTracked;

  const _StatsRow({
    required this.urgentModules,
    required this.thisWeekCount,
    required this.plannedTime,
    required this.materialsTracked,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final isNarrow = c.maxWidth < 900;
        final children = [
          _StatCard(icon: Icons.assignment_late_outlined, title: '$urgentModules', subtitle: 'Urgent modules'),
          _StatCard(icon: Icons.calendar_today_outlined, title: '$thisWeekCount', subtitle: 'This week'),
          _StatCard(icon: Icons.timer_outlined, title: '${plannedTime.inMinutes}m', subtitle: 'Planned time'),
          _StatCard(icon: Icons.folder_outlined, title: '$materialsTracked', subtitle: 'Materials tracked'),
        ];

        if (!isNarrow) {
          return Row(
            children: children
                .asMap()
                .entries
                .map((e) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: e.key == children.length - 1 ? 0 : 10),
                        child: e.value,
                      ),
                    ))
                .toList(),
          );
        }

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: children.map((w) => SizedBox(width: (c.maxWidth - 10) / 2, child: w)).toList(),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _StatCard({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EAF0)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF1D4ED8)),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title, style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 16)),
              Text(subtitle, style: GoogleFonts.dmSans(color: Colors.black54, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  const _CardShell({
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EAF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 13)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!, style: GoogleFonts.dmSans(fontSize: 11, color: Colors.black45)),
                    ),
                ],
              ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  final String left;
  final String right;
  final bool isLeftSelected;
  final ValueChanged<bool> onChanged;

  const _Segmented({
    required this.left,
    required this.right,
    required this.isLeftSelected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6E9F2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => onChanged(true),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isLeftSelected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  left,
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isLeftSelected ? Colors.white : Colors.black54,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => onChanged(false),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: !isLeftSelected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  right,
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: !isLeftSelected ? Colors.white : Colors.black54,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFE6E9F2)),
        ),
        child: Icon(icon, size: 20),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool isSelected;
  final bool hasMarker;

  const _DayCell({
    required this.day,
    required this.isSelected,
    required this.hasMarker,
  });

  @override
  Widget build(BuildContext context) {
    // Selected in Figma looks dark-blue filled; unselected is white with border.
    final bg = isSelected ? AppColors.primary : Colors.white;
    final border = const Color(0xFFE6E9F2);
    final textColor = isSelected ? Colors.white : Colors.black87;

    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Stack(
        children: [
          Center(
            child: Text(
              '${day.day}',
              style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 11, color: textColor),
            ),
          ),
          if (hasMarker)
            Positioned(
              bottom: 3,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.amberAccent : AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final String label;
  const _LegendDot({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(8)),
        ),
        const SizedBox(width: 8),
        Text(label, style: GoogleFonts.dmSans(fontSize: 11, color: Colors.black45)),
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  final Color bg;
  final String title;
  final String value;

  const _InfoPill({required this.bg, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: GoogleFonts.dmSans(fontSize: 11, color: Colors.black54)),
          const SizedBox(height: 2),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? AppColors.primary : const Color(0xFFE6E9F2)),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w700, color: selected ? Colors.white : Colors.black87),
        ),
      ),
    );
  }
}

class _TopicRow extends StatelessWidget {
  final _Topic topic;
  const _TopicRow({required this.topic});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6E9F2)),
      ),
      child: Row(
        children: [
          Expanded(child: Text(topic.name, style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, fontSize: 12.5))),
          Text('${topic.duration.inMinutes}m', style: GoogleFonts.dmSans(color: Colors.black54, fontWeight: FontWeight.w600, fontSize: 11)),
        ],
      ),
    );
  }
}

/* ---------------------- Schedule row: time + reminder --------------------- */

class _ScheduleRowWidget extends StatelessWidget {
  final _ScheduleRowState row;
  final ValueChanged<TimeOfDay> onChangeTime;
  final ValueChanged<_Reminder> onChangeReminder;

  const _ScheduleRowWidget({
    required this.row,
    required this.onChangeTime,
    required this.onChangeReminder,
  });

  @override
  Widget build(BuildContext context) {
    final end = _addDuration(row.startTime, row.duration);
    final endLabel = 'Ends ${_fmtTime(end)}';

    return Container(
      height: 48,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6E9F2)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(row.subject, style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 12.5)),
          ),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Text('Start time', style: GoogleFonts.dmSans(fontSize: 10.5, color: Colors.black45)),
                const SizedBox(width: 10),
                _TimeDropdownButton(
                  value: row.startTime,
                  onChanged: onChangeTime,
                ),
                const SizedBox(width: 10),
                const Icon(Icons.access_time_rounded, size: 18, color: Colors.black54),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(endLabel, style: GoogleFonts.dmSans(fontSize: 11, color: Colors.black54)),
          ),
          _ReminderMenuButton(
            value: row.reminder,
            onChanged: onChangeReminder,
          ),
        ],
      ),
    );
  }

  static TimeOfDay _addDuration(TimeOfDay start, Duration d) {
    final dt = DateTime(2026, 1, 1, start.hour, start.minute).add(d);
    return TimeOfDay(hour: dt.hour, minute: dt.minute);
  }

  static String _fmtTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _TimeDropdownButton extends StatelessWidget {
  final TimeOfDay value;
  final ValueChanged<TimeOfDay> onChanged;

  const _TimeDropdownButton({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final label = '${value.hour.toString().padLeft(2, '0')} : ${value.minute.toString().padLeft(2, '0')}';

    return PopupMenuButton<TimeOfDay>(
      tooltip: 'Select start time',
      offset: const Offset(0, 38),
      onSelected: onChanged,
      itemBuilder: (context) {
        // Figma shows hour+minute picker; simulate with prebuilt times.
        final items = <PopupMenuEntry<TimeOfDay>>[];
        for (int h = 18; h <= 23; h++) {
          for (final m in const [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55]) {
            final t = TimeOfDay(hour: h % 24, minute: m);
            items.add(
              PopupMenuItem(
                value: t,
                child: Text('${t.hour.toString().padLeft(2, '0')} : ${t.minute.toString().padLeft(2, '0')}'),
              ),
            );
          }
        }
        return items;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE6E9F2)),
        ),
        child: Text(label, style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 11)),
      ),
    );
  }
}

class _ReminderMenuButton extends StatelessWidget {
  final _Reminder value;
  final ValueChanged<_Reminder> onChanged;

  const _ReminderMenuButton({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_Reminder>(
      tooltip: 'Reminder',
      offset: const Offset(0, 38),
      onSelected: onChanged,
      itemBuilder: (context) {
        return const [
          PopupMenuItem(
            value: _Reminder.off,
            child: _ReminderMenuRow(title: 'Off', subtitle: 'No reminder', selected: true),
          ),
          PopupMenuItem(
            value: _Reminder.min30,
            child: _ReminderMenuRow(title: '30 minutes', subtitle: 'Before start'),
          ),
          PopupMenuItem(
            value: _Reminder.hour1,
            child: _ReminderMenuRow(title: '1 hour', subtitle: 'Before start'),
          ),
        ];
      },
      child: const Icon(Icons.notifications_none_rounded),
    );
  }
}

class _ReminderMenuRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;

  const _ReminderMenuRow({
    required this.title,
    required this.subtitle,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: GoogleFonts.dmSans(fontWeight: FontWeight.w700))),
        Text(subtitle, style: GoogleFonts.dmSans(color: Colors.black54, fontSize: 12)),
      ],
    );
  }
}

/* -------------------------------- Models -------------------------------- */

enum _Priority { urgent, reviewSoon, safe }
enum _PriorityFilter { all, urgent, reviewSoon, safe }

/// One material's real, backend-computed review schedule entry — replaces
/// the hardcoded `_Topic` sample list that used to populate this whole page.
class _MaterialSchedule {
  final String materialId;
  final String filename;
  final DateTime? nextReviewDate;
  final double? score;

  _MaterialSchedule({
    required this.materialId,
    required this.filename,
    required this.nextReviewDate,
    required this.score,
  });

  factory _MaterialSchedule.fromJson(Map<String, dynamic> j) {
    final latest = j['latest_session'] as Map<String, dynamic>?;
    DateTime? nextReview;
    final raw = latest?['next_review_date'] as String?;
    if (raw != null) {
      try { nextReview = DateTime.parse(raw); } catch (_) {}
    }
    return _MaterialSchedule(
      materialId: j['material_id'] as String? ?? '',
      filename: (j['filename'] as String? ?? 'Untitled.pdf').replaceAll('.pdf', ''),
      nextReviewDate: nextReview,
      score: (latest?['score'] as num?)?.toDouble(),
    );
  }

  /// Urgent = overdue or due today; review-soon = within 3 days; else safe.
  /// Mirrors the "1 timed out" / next-review framing already used on the
  /// session results screen, so the definition of "urgent" is consistent
  /// across the app rather than each screen inventing its own threshold.
  _Priority get priority {
    if (nextReviewDate == null) return _Priority.safe;
    final days = nextReviewDate!.difference(DateTime.now()).inDays;
    if (days <= 0) return _Priority.urgent;
    if (days <= 3) return _Priority.reviewSoon;
    return _Priority.safe;
  }
}

class _LoadErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _LoadErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EAF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Couldn\'t load your schedule',
              style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 6),
          Text(message, style: GoogleFonts.dmSans(color: Colors.black54, fontSize: 12)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _Topic {
  final String name;
  final Duration duration;
  final _Priority priority;
  const _Topic({required this.name, required this.duration, required this.priority});
}

enum _Reminder { off, min30, hour1 }

class _ScheduleRowState {
  final String subject;
  final TimeOfDay startTime;
  final Duration duration;
  final _Reminder reminder;

  const _ScheduleRowState({
    required this.subject,
    required this.startTime,
    required this.duration,
    required this.reminder,
  });

  _ScheduleRowState copyWith({
    TimeOfDay? startTime,
    Duration? duration,
    _Reminder? reminder,
  }) {
    return _ScheduleRowState(
      subject: subject,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      reminder: reminder ?? this.reminder,
    );
  }
}