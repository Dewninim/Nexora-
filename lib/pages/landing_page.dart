// Landing Page - Tharuka Karunarathne
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import '../theme/app_theme.dart';
import '../widgets/brain_logo.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  late VideoPlayerController _videoController;
  bool _videoReady = false;
  bool _getStartedHovered = false;
  bool _signInHovered = false;
  bool _haveAccountHovered = false;

  @override
  void initState() {
    super.initState();
    _videoController =
        VideoPlayerController.asset('assets/videos/hero-video.mp4')
          ..initialize().then((_) {
            if (mounted) {
              setState(() => _videoReady = true);
              _videoController
                ..setLooping(true)
                ..setVolume(0)
                ..play();
            }
          });
  }

  @override
  void dispose() {
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Video background ──
          if (_videoReady)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _videoController.value.size.width,
                  height: _videoController.value.size.height,
                  child: VideoPlayer(_videoController),
                ),
              ),
            )
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0d1f3c), Color(0xFF1a2f5e)],
                ),
              ),
            ),

          // ── 70% black overlay ──
          Container(color: Colors.black.withValues(alpha: 0.80)),

          // ── All UI on top ──
          Column(
            children: [
              // Navbar
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 20,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const BrainLogo(size: 36),
                        const SizedBox(height: 4),
                        Text(
                          'NEUROMATHIX',
                          style: GoogleFonts.openSans(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                    MouseRegion(
                      onEnter: (_) => setState(() => _signInHovered = true),
                      onExit: (_) => setState(() => _signInHovered = false),
                      child: GestureDetector(
                        onTap: () => Navigator.pushNamed(context, '/login'),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: _signInHovered
                                ? Colors.white.withValues(alpha: 0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: Text(
                            'Sign in',
                            style: GoogleFonts.openSans(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Center content
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                        child: Text(
                          'AI-Powered Personalized Learning',
                          style: GoogleFonts.openSans(
                            color: Colors.white.withValues(alpha: 0.90),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Smarter learning',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.openSans(
                          color: Colors.white,
                          fontSize: 72,
                          fontWeight: FontWeight.w600,
                          height: 1.05,
                          letterSpacing: -1,
                        ),
                      ),
                      Text(
                        'Lasting memory',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.openSans(
                          color: Colors.white.withValues(alpha: 0.42),
                          fontSize: 72,
                          fontWeight: FontWeight.w600,
                          height: 1.05,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Master mathematics with AI that adapts to your unique learning style,\npredicts what you\'ll forget, and helps you truly understand.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.openSans(
                          color: Colors.white.withValues(alpha: 0.80),
                          fontSize: 16,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 40),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          MouseRegion(
                            onEnter: (_) =>
                                setState(() => _getStartedHovered = true),
                            onExit: (_) =>
                                setState(() => _getStartedHovered = false),
                            child: GestureDetector(
                              onTap: () =>
                                  Navigator.pushNamed(context, '/signup'),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: _getStartedHovered
                                      ? AppColors.accent
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(40),
                                ),
                                child: Text(
                                  'Get Started →',
                                  style: GoogleFonts.openSans(
                                    color: _getStartedHovered
                                        ? Colors.white
                                        : AppColors.accent,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          MouseRegion(
                            onEnter: (_) =>
                                setState(() => _haveAccountHovered = true),
                            onExit: (_) =>
                                setState(() => _haveAccountHovered = false),
                            child: GestureDetector(
                              onTap: () =>
                                  Navigator.pushNamed(context, '/login'),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: _haveAccountHovered
                                      ? Colors.white.withValues(alpha: 0.12)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(40),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.70),
                                    width: 1.5,
                                  ),
                                ),
                                child: Text(
                                  'I have an account',
                                  style: GoogleFonts.openSans(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text(
                  '© 2026 NeuroMathix. All rights reserved.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.openSans(
                    color: Colors.white.withValues(alpha: 0.50),
                    fontSize: 13,
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
