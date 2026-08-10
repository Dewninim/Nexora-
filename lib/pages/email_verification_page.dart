import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

class EmailVerificationPage extends StatelessWidget {
  const EmailVerificationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppAuthProvider>();
    final email = FirebaseAuth.instance.currentUser?.email ?? 'your email address';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F4E95).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.mark_email_read_outlined,
                    size: 38,
                    color: Color(0xFF1F4E95),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Verify your email',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Text(
                  'A verification link was sent to $email. Open the link, then return here and check the verification status.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    height: 1.55,
                  ),
                ),
                if (auth.errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    auth.errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFDC2626)),
                  ),
                ],
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: auth.isLoading
                        ? null
                        : () async {
                            final verified =
                                await context.read<AppAuthProvider>().refreshEmailVerification();
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
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                    label: const Text('I have verified my email'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
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
                    child: const Text('Resend verification email'),
                  ),
                ),
                const SizedBox(height: 8),
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
                  child: const Text('Use another account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
