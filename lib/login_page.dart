// Login Page — proj2 UI + proj1 real Firebase Auth
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'signup_page.dart';
import 'theme/app_theme.dart';

class LoginPage extends StatefulWidget {
  LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _showPass   = false;

  @override
  void dispose() { _emailCtrl.dispose(); _passCtrl.dispose(); super.dispose(); }

  Future<void> _signIn() async {
    final provider = Provider.of<AppAuthProvider>(context, listen: false);
    await provider.login(_emailCtrl.text.trim(), _passCtrl.text.trim());
    if (!mounted) return;
    if (provider.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(provider.errorMessage!)));
    } else {
      Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AppAuthProvider>(context);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/bg2.jpg', fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [Color(0xFF0d1f3c), Color(0xFF1a2f5e)])))),
          Container(color: Colors.black.withValues(alpha: 0.50)),
          Row(children: [
            // Left panel
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 48),
              child: Column(mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Image.asset('assets/images/neuromathix_logo.png', width: 44, height: 44),
                    const SizedBox(width: 12),
                    Text('NEUROMATHIX', style: AppText.sectionHeader.copyWith(color: Colors.white, letterSpacing: 1.5)),
                  ]),
                  const SizedBox(height: 80),
                  Text('Start your journey to\nmathematical mastery',
                    style: GoogleFonts.dmSans(color: Colors.white, fontSize: 36,
                        fontWeight: FontWeight.w800, height: 1.2)),
                  const SizedBox(height: 32),
                  ...['AI that adapts to your learning pace',
                    "Never forget what you've learned",
                    "Understand the 'why' behind every answer",
                    'Track your progress in real-time']
                    .map((s) => Padding(padding: const EdgeInsets.only(bottom: 14),
                      child: Row(children: [
                        Container(width: 6, height: 6,
                            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
                        const SizedBox(width: 12),
                        Text(s, style: GoogleFonts.dmSans(color: Colors.white,
                            fontSize: 16, fontWeight: FontWeight.w600)),
                      ]))),
                ]))),
            // Right card
            Align(alignment: Alignment.center,
              child: Container(width: 520,
                margin: const EdgeInsets.symmetric(vertical: 40, horizontal: 40),
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 40, offset: const Offset(0, 16))]),
                child: Column(mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sign in', style: GoogleFonts.dmSans(color: AppColors.textDark,
                        fontSize: 28, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text('Enter your credentials to continue',
                        style: GoogleFonts.dmSans(color: AppColors.textMuted, fontSize: 14)),
                    const SizedBox(height: 28),
                    _label('Email address'),
                    const SizedBox(height: 6),
                    _field(controller: _emailCtrl, hint: 'you@university.edu'),
                    const SizedBox(height: 16),
                    _label('Password'),
                    const SizedBox(height: 6),
                    _field(controller: _passCtrl, hint: '••••••••••',
                      obscure: !_showPass,
                      suffix: GestureDetector(
                        onTap: () => setState(() => _showPass = !_showPass),
                        child: Icon(_showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: const Color(0xFF9CA3AF), size: 20))),
                    const SizedBox(height: 24),
                    SizedBox(width: double.infinity, height: 50,
                      child: ElevatedButton(
                        onPressed: auth.isLoading ? null : _signIn,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          elevation: 0),
                        child: auth.isLoading
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text('Sign in →', style: GoogleFonts.dmSans(color: Colors.white,
                              fontWeight: FontWeight.w700, fontSize: 15)))),
                    const SizedBox(height: 20),
                    Center(child: Text('New to NeuroMathix?',
                        style: GoogleFonts.dmSans(color: AppColors.textMuted, fontSize: 14))),
                    const SizedBox(height: 10),
                    SizedBox(width: double.infinity, height: 50,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pushReplacement(
                            context, MaterialPageRoute(builder: (_) => SignupPage())),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.accent, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                        child: Text('Create account →', style: GoogleFonts.dmSans(
                            color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 15)))),
                  ]))),
          ]),
        ],
      ),
    );
  }

  Widget _label(String t) => Text(t,
    style: GoogleFonts.dmSans(color: AppColors.textDark, fontWeight: FontWeight.w500, fontSize: 14));

  Widget _field({required TextEditingController controller, required String hint,
      bool obscure = false, Widget? suffix}) {
    return TextField(controller: controller, obscureText: obscure,
      style: GoogleFonts.dmSans(color: AppColors.textDark, fontSize: 15),
      decoration: InputDecoration(hintText: hint,
        hintStyle: GoogleFonts.dmSans(color: AppColors.textFaint),
        suffixIcon: suffix != null ? Padding(padding: const EdgeInsets.only(right: 12), child: suffix) : null,
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        filled: true, fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(30),
          borderSide: const BorderSide(color: Color(0xFFD1D5DB))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30),
          borderSide: const BorderSide(color: Color(0xFFD1D5DB))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5))));
  }
}