import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/teacher_models.dart';
import '../theme/app_theme.dart';

// Previously this file DUPLICATED these six constants as its own separate
// declaration (student_app_shell.dart had an identical-but-independent
// copy) — editing one palette without the other is exactly how the student
// and teacher shells drifted into looking different. Both now point at the
// same single source: lib/theme/app_theme.dart.
const Color neuromathixNavy = AppColors.primary;
const Color neuromathixBlue = AppColors.accent;
const Color neuromathixText = AppColors.textDark;
const Color neuromathixMuted = AppColors.textMuted;
const Color neuromathixBorder = AppColors.border;
const Color neuromathixSurface = AppColors.surface;

class TeacherAppShell extends StatelessWidget {
  final TeacherNavSection activeSection;
  final String userName;
  final int notificationCount;
  final Widget child;
  final ValueChanged<TeacherNavSection> onSectionSelected;
  final VoidCallback? onNotificationTap;

  const TeacherAppShell({
    super.key,
    required this.activeSection,
    required this.userName,
    required this.notificationCount,
    required this.child,
    required this.onSectionSelected,
    this.onNotificationTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final isCompact = w < 760;

        if (isCompact) {
          return Scaffold(
            backgroundColor: Colors.white,
            drawer: SizedBox(
              width: 240,
              child: TeacherSidebar(
                activeSection: activeSection,
                expanded: true,
                onSectionSelected: (section) {
                  Navigator.pop(context);
                  onSectionSelected(section);
                },
              ),
            ),
            appBar: AppBar(
              backgroundColor: Colors.white,
              foregroundColor: neuromathixText,
              elevation: 0,
              centerTitle: false,
              title: Text(
                'Hi, $userName',
                style: GoogleFonts.dmSans(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
              actions: [
                NotificationBell(
                  count: notificationCount,
                  onTap: onNotificationTap,
                ),
                const SizedBox(width: 8),
                UserInitialAvatar(userName: userName),
                const SizedBox(width: 12),
              ],
              bottom: const PreferredSize(
                preferredSize: Size.fromHeight(1),
                child: Divider(height: 1, color: neuromathixBorder),
              ),
            ),
            body: child,
          );
        }

        return Scaffold(
          backgroundColor: Colors.white,
          body: Row(
            children: [
              TeacherSidebar(
                activeSection: activeSection,
                onSectionSelected: onSectionSelected,
              ),
              Expanded(
                child: Column(
                  children: [
                    TeacherTopBar(
                      userName: userName,
                      notificationCount: notificationCount,
                      onNotificationTap: onNotificationTap,
                    ),
                    Expanded(child: child),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class TeacherTopBar extends StatelessWidget {
  final String userName;
  final int notificationCount;
  final VoidCallback? onNotificationTap;

  const TeacherTopBar({
    super.key,
    required this.userName,
    required this.notificationCount,
    this.onNotificationTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final isSmall = c.maxWidth < 1000;

        return Container(
          height: isSmall ? 56 : 64,
          padding: EdgeInsets.symmetric(horizontal: isSmall ? 18 : 44),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: neuromathixBorder)),
          ),
          child: Row(
            children: [
              Text(
                'Hi, $userName',
                style: GoogleFonts.dmSans(
                  fontSize: isSmall ? 22 : 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
              const Spacer(),
              NotificationBell(
                count: notificationCount,
                onTap: onNotificationTap,
              ),
              const SizedBox(width: 14),
              UserInitialAvatar(userName: userName),
            ],
          ),
        );
      },
    );
  }
}

Future<void> _logout(BuildContext context) async {
  await FirebaseAuth.instance.signOut();
  if (context.mounted) {
    Navigator.pushNamedAndRemoveUntil(context, '/landing', (_) => false);
  }
}

class TeacherSidebar extends StatelessWidget {
  final TeacherNavSection activeSection;
  final bool expanded;
  final ValueChanged<TeacherNavSection> onSectionSelected;

  const TeacherSidebar({
    super.key,
    required this.activeSection,
    required this.onSectionSelected,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      _SidebarItem(TeacherNavSection.dashboard, Icons.grid_view_rounded, 'Dashboard'),
      _SidebarItem(TeacherNavSection.helpRequests, Icons.support_agent_rounded, 'Help Requests'),
      _SidebarItem(TeacherNavSection.settings, Icons.settings_outlined, 'Settings'),
    ];

    return Container(
      width: expanded ? 260 : 128,
      color: neuromathixNavy,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: expanded ? 18 : 0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset(
                              'assets/images/neuromathix_logo.png',
                              width: 40,
                              height: 40,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.psychology_outlined,
                                color: Colors.white,
                                size: 34,
                              ),
                            ),
                            if (expanded) ...[
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'NEUROMATHIX',
                                  style: GoogleFonts.dmSans(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (!expanded) ...[
                        const SizedBox(height: 6),
                        Text(
                          'NEUROMATHIX',
                          style: GoogleFonts.dmSans(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      for (final item in items)
                        _SidebarButton(
                          item: item,
                          expanded: expanded,
                          selected: activeSection == item.section,
                          onTap: () => onSectionSelected(item.section),
                        ),
                      const Spacer(),
                      _SidebarLogoutButton(
                        expanded: expanded,
                        onTap: () => _logout(context),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SidebarLogoutButton extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;

  const _SidebarLogoutButton({
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: expanded ? double.infinity : 54,
      height: 54,
      margin: EdgeInsets.symmetric(horizontal: expanded ? 14 : 0),
      padding: EdgeInsets.symmetric(horizontal: expanded ? 16 : 0),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisAlignment: expanded
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: [
          const Icon(Icons.logout_rounded, color: Colors.white, size: 26),
          if (expanded) ...[
            const SizedBox(width: 14),
            Text(
              'Logout',
              style: GoogleFonts.dmSans(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );

    return Tooltip(
      message: 'Logout',
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  final _SidebarItem item;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  const _SidebarButton({
    required this.item,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: expanded ? double.infinity : 54,
      height: 54,
      margin: EdgeInsets.symmetric(horizontal: expanded ? 14 : 0, vertical: 9),
      padding: EdgeInsets.symmetric(horizontal: expanded ? 16 : 0),
      decoration: BoxDecoration(
        color: selected ? neuromathixBlue : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisAlignment: expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: [
          Icon(item.icon, color: Colors.white, size: 28),
          if (expanded) ...[
            const SizedBox(width: 14),
            Text(item.label, style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          ],
        ],
      ),
    );

    return Tooltip(
      message: item.label,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

class _SidebarItem {
  final TeacherNavSection section;
  final IconData icon;
  final String label;
  const _SidebarItem(this.section, this.icon, this.label);
}

class NotificationBell extends StatelessWidget {
  final int count;
  final VoidCallback? onTap;
  const NotificationBell({super.key, required this.count, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Align(
              alignment: Alignment.center,
              child: Icon(Icons.notifications_none_rounded, size: 32, color: Colors.black),
            ),
            if (count > 0)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(16)),
                  child: Text('$count', style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class UserInitialAvatar extends StatelessWidget {
  final String userName;
  const UserInitialAvatar({super.key, required this.userName});

  @override
  Widget build(BuildContext context) {
    final initial = userName.trim().isEmpty ? 'T' : userName.trim()[0].toUpperCase();
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? '';

    return PopupMenuButton<int>(
      offset: const Offset(0, 56),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      child: Tooltip(
        message: 'Signed in as $userName',
        child: Container(
          width: 46,
          height: 46,
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
          ),
        ),
      ),
      onSelected: (val) {
        if (val == 1) {
          _logout(context);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<int>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(userName, style: GoogleFonts.dmSans(fontWeight: FontWeight.w800, color: AppColors.textDark, fontSize: 14)),
              if (email.isNotEmpty)
                Text(email, style: GoogleFonts.dmSans(color: AppColors.textMuted, fontSize: 12)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Approved Teacher', style: GoogleFonts.dmSans(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<int>(
          value: 1,
          child: Row(
            children: [
              const Icon(Icons.logout_rounded, color: AppColors.error, size: 18),
              const SizedBox(width: 10),
              Text('Sign Out', style: GoogleFonts.dmSans(color: AppColors.error, fontWeight: FontWeight.w700, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}