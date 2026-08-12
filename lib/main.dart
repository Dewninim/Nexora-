import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;

import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'pages/landing_page.dart';
import 'pages/analytics_page.dart';
import 'pages/profile_page.dart';
import 'pages/student_dashboard_page.dart';
import 'pages/teacher_dashboard_page.dart';
import 'pages/explainable_ai_feedback_page.dart';
import 'pages/review_schedule_page.dart';
import 'pages/student_teacher_messages_page.dart';
import 'pages/email_verification_page.dart';
import 'login_page.dart';
import 'signup_page.dart';
import 'models/student_learning_models.dart';
import 'services/user_role_service.dart';
import 'services/notification_service.dart';
import 'widgets/logo_popup.dart';
import 'widgets/student_app_shell.dart';
import 'pages/upload_material_page.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(
    // ProviderScope (Riverpod) wraps everything because the quiz/session
    // screen (lib/pages/learning_session_screen.dart) is Riverpod-based.
    // ChangeNotifierProvider (the `provider` package) is nested inside it
    // for the rest of the app's existing state management — both packages
    // coexist fine.
    ProviderScope(
      child: ChangeNotifierProvider(
        create: (_) => AppAuthProvider(),
        child: const MyApp(),
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NeuroMathix',
      theme: AppTheme.light().copyWith(
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: _NoPageTransitionBuilder(),
            TargetPlatform.iOS: _NoPageTransitionBuilder(),
            TargetPlatform.macOS: _NoPageTransitionBuilder(),
            TargetPlatform.windows: _NoPageTransitionBuilder(),
            TargetPlatform.linux: _NoPageTransitionBuilder(),
          },
        ),
      ),
      home: const SplashGate(),
      routes: {
        '/landing':   (_) => const LandingPage(),
        '/login':     (_) => LoginPage(),
        '/signup':    (_) => SignupPage(),
        '/verify-email': (_) => const EmailVerificationPage(),
        // ── Authenticated routes ──
        '/dashboard': (_) => const _RoleRouter(),
        '/student-dashboard': (_) => _StudentDashboardRoute(),
        '/teacher-messages': (_) => const _StudentShellRoute(
              activeSection: StudentNavSection.teacherMessages,
              child: StudentTeacherMessagesPage(),
            ),
        '/upload': (_) => const _StudentShellRoute(
              activeSection: StudentNavSection.uploadMaterial,
              child: UploadMaterialPage(),
            ),
        '/learning': (_) => const _StudentShellRoute(
              activeSection: StudentNavSection.aiFeedback,
              child: ExplainableAiFeedbackPage(),
            ),
        '/ai-feedback': (_) => const ExplainableAiFeedbackPage(),
        '/review': (_) => const _StudentShellRoute(
              activeSection: StudentNavSection.reviewSchedule,
              child: ReviewSchedulePage(),
            ),
        '/analytics': (_) => _AnalyticsRoute(),
        '/profile': (_) => const ProfilePage(),
      },
    );
  }
}

class _NoPageTransitionBuilder extends PageTransitionsBuilder {
  const _NoPageTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}

/// Shows splash logo, then checks auth state.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});
  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _showSplash = true;
  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return LogoPopup(onComplete: () {
        if (mounted) setState(() => _showSplash = false);
      });
    }
    return const AuthGate();
  }
}

/// After splash: not logged in → LandingPage.  Logged in → role-based dashboard.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: context.read<AppAuthProvider>().userStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!snapshot.hasData) return const LandingPage();

        final user = snapshot.data!;
        if (!user.emailVerified) return const EmailVerificationPage();

        final uid = user.uid;
        return FutureBuilder<String>(
          future: UserRoleService().getCurrentUserRole(),
          builder: (context, roleSnap) {
            if (roleSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final role = (roleSnap.data ?? 'student').toLowerCase();
            if (role == 'teacher') return const TeacherDashboardPage();
            return StudentDashboardPage(studentId: uid);
          },
        );
      },
    );
  }
}

/// Navigated to '/dashboard' — re-route by role.
class _RoleRouter extends StatelessWidget {
  const _RoleRouter();
  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null && !currentUser.emailVerified) {
      return const EmailVerificationPage();
    }
    final uid = currentUser?.uid ?? 'student-demo';
    return FutureBuilder<String>(
      future: UserRoleService().getCurrentUserRole(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final role = (snap.data ?? 'student').toLowerCase();
        if (role == 'teacher') return const TeacherDashboardPage();
        return StudentDashboardPage(studentId: uid);
      },
    );
  }
}

/// Route widget for '/student-dashboard' — reads UID from current auth session.
class _StudentDashboardRoute extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'student-demo';
    return StudentDashboardPage(studentId: uid);
  }
}

/// Route widget for '/analytics' — reads UID from current auth session,
/// same pattern as _StudentDashboardRoute.
class _AnalyticsRoute extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'student-demo';
    return AnalyticsPage(studentId: uid);
  }
}

class _StudentShellRoute extends StatelessWidget {
  final StudentNavSection activeSection;
  final Widget child;

  const _StudentShellRoute({
    required this.activeSection,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppNotification>>(
      stream: FirebaseAuth.instance.currentUser == null
          ? const Stream<List<AppNotification>>.empty()
          : NotificationService().watchCurrentUserNotifications(),
      builder: (context, snapshot) {
        final unread =
            snapshot.data?.where((n) => !n.isRead).length ?? 0;
        return StudentAppShell(
          activeSection: activeSection,
          userName: currentAuthUserName(),
          notificationCount: unread,
          onSectionSelected: (section) => _openSection(context, section),
          child: child,
        );
      },
    );
  }

  void _openSection(BuildContext context, StudentNavSection section) {
    if (section == activeSection) return;
    Navigator.pushNamed(context, _routeForSection(section));
  }

  static String _routeForSection(StudentNavSection section) {
    switch (section) {
      case StudentNavSection.dashboard:
        return '/student-dashboard';
      case StudentNavSection.teacherMessages:
        return '/teacher-messages';
      case StudentNavSection.uploadMaterial:
        return '/upload';
      case StudentNavSection.aiFeedback:
        return '/ai-feedback';
      case StudentNavSection.reviewSchedule:
        return '/review';
      case StudentNavSection.analytics:
        return '/analytics';
      case StudentNavSection.settings:
        return '/profile';
    }
  }
}

/// Generic placeholder for routes not yet built.
class _PlaceholderPage extends StatelessWidget {
  final String title;
  final String subtitle;
  const _PlaceholderPage(this.title, this.subtitle);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.construction_rounded, size: 48, color: AppColors.textFaint),
          const SizedBox(height: 16),
          Text(title, style: AppText.h1),
          const SizedBox(height: 8),
          Text(subtitle, style: AppText.bodySmall),
        ],
      ),
    );
  }
}
