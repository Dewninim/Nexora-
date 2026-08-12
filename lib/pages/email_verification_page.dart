import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';

class EmailVerificationPage extends StatelessWidget {
  const EmailVerificationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    final email = FirebaseAuth.instance.currentUser?.email ?? 'your email address';

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/bg2.jpg',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0d1f3c), Color(0xFF1a2f5e)],
                ),
              ),
            ),
          ),
          Container(color: Colors.black.withValues(alpha: 0.50)),
          Row(
            children: [
              // Left branding panel (identical to LoginPage / SignupPage)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 48),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Image.asset('assets/images/neuromathix_logo.png', width: 44, height: 44),
                          const SizedBox(width: 12),
                          Text(
                            'NEUROMATHIX',
                            style: AppText.sectionHeader.copyWith(
                              color: Colors.white,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 80),
                      Text(
                        'Verify your email to\nactivate your account',
                        style: GoogleFonts.dmSans(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 32),
                      ...[
                        'Secure role-based access for students and teachers',
                        'Personalized forgetting-curve review scheduling',
                        'Explainable AI tutoring tailored to your progress',
                        'Real-time student and teacher dashboards',
                      ].map(
                        (s) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                s,
                                style: GoogleFonts.dmSans(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Right card
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 520,
                  margin: const EdgeInsets.symmetric(vertical: 40, horizontal: 40),
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 40,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.mark_email_read_outlined,
                          size: 38,
                          color: AppColors.accent,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Verify your email',
                        style: GoogleFonts.dmSans(
                          color: AppColors.textDark,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'A verification link was sent to $email. Open the link, then return here and check the verification status.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.dmSans(
                          color: AppColors.textMuted,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      if (auth.errorMessage != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          auth.errorMessage!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.dmSans(
                            color: AppColors.error,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: auth.isLoading
                              ? null
                              : () async {
                                  final verified = await context
                                      .read<AppAuthProvider>()
                                      .refreshEmailVerification();
                                  if (!context.mounted) return;
                                  if (verified) {
                                    Navigator.pushNamedAndRemoveUntil(
                                      context,
                                      '/dashboard',
                                      (_) => false,
                                    );
                                  } else if (auth.errorMessage == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Email is not verified yet. Open the link and try again.',
                                        ),
                                      ),
                                    );
                                  }
                                },
                          icon: auth.isLoading
                              ? const SizedBox(
                                  width: 17,
                                  height: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(
                            'I have verified my email',
                            style: GoogleFonts.dmSans(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: const BorderSide(color: AppColors.border),
                          ),
                          onPressed: auth.isLoading
                              ? null
                              : () async {
                                  final ok = await context
                                      .read<AppAuthProvider>()
                                      .resendVerificationEmail();
                                  if (!context.mounted || !ok) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Verification email sent again.'),
                                    ),
                                  );
                                },
                          child: Text(
                            'Resend verification email',
                            style: GoogleFonts.dmSans(
                              color: AppColors.textDark,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextButton(
                        onPressed: auth.isLoading
                            ? null
                            : () async {
                                await context.read<AppAuthProvider>().logout();
                                if (!context.mounted) return;
                                Navigator.pushNamedAndRemoveUntil(
                                  context,
                                  '/landing',
                                  (_) => false,
                                );
                              },
                        child: Text(
                          'Use another account',
                          style: GoogleFonts.dmSans(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
