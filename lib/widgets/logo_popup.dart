// Logo Popup - Tharuka Karunarathne
import 'package:flutter/material.dart';
import 'brain_logo.dart';

class LogoPopup extends StatefulWidget {
  final VoidCallback onComplete;
  const LogoPopup({super.key, required this.onComplete});

  @override
  State<LogoPopup> createState() => _LogoPopupState();
}

class _LogoPopupState extends State<LogoPopup> with TickerProviderStateMixin {
  late AnimationController _brainCtrl;
  late AnimationController _rippleCtrl;
  late AnimationController _textCtrl;
  late AnimationController _barCtrl;
  late AnimationController _exitCtrl;

  late Animation<double> _brainScale;
  late Animation<double> _brainOpacity;
  late Animation<double> _glowSize;
  late Animation<double> _ripple1;
  late Animation<double> _ripple2;
  late Animation<double> _ripple1Opacity;
  late Animation<double> _ripple2Opacity;
  late Animation<double> _titleOpacity;
  late Animation<Offset> _titleSlide;
  late Animation<double> _taglineOpacity;
  late Animation<double> _barProgress;
  late Animation<double> _exitOpacity;

  @override
  void initState() {
    super.initState();

    _brainCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _rippleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _textCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _barCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _exitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _brainScale = TweenSequence([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.0,
          end: 1.10,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 70,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.10,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
    ]).animate(_brainCtrl);

    _brainOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _brainCtrl,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
      ),
    );

    _glowSize = Tween(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _brainCtrl, curve: Curves.easeOut));

    _ripple1 = Tween(
      begin: 1.0,
      end: 2.2,
    ).animate(CurvedAnimation(parent: _rippleCtrl, curve: Curves.easeOut));
    _ripple1Opacity = Tween(
      begin: 0.6,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _rippleCtrl, curve: Curves.easeOut));
    _ripple2 = Tween(begin: 1.0, end: 1.7).animate(
      CurvedAnimation(
        parent: _rippleCtrl,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
      ),
    );
    _ripple2Opacity = Tween(begin: 0.4, end: 0.0).animate(
      CurvedAnimation(
        parent: _rippleCtrl,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
      ),
    );

    _titleOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _textCtrl,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );
    _titleSlide = Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _textCtrl,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );
    _taglineOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _textCtrl,
        curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
      ),
    );

    _barProgress = Tween(begin: 0.0, end: 1.0).animate(_barCtrl);

    _exitOpacity = Tween(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _exitCtrl, curve: Curves.easeInOut));

    _runSequence();
  }

  Future<void> _runSequence() async {
    await _brainCtrl.forward();
    _rippleCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 200));
    await _textCtrl.forward();
    _barCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 1400));
    await _exitCtrl.forward();
    widget.onComplete();
  }

  @override
  void dispose() {
    _brainCtrl.dispose();
    _rippleCtrl.dispose();
    _textCtrl.dispose();
    _barCtrl.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _brainCtrl,
        _rippleCtrl,
        _textCtrl,
        _barCtrl,
        _exitCtrl,
      ]),
      builder: (context, _) {
        return Opacity(
          opacity: _exitOpacity.value,
          child: Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: [Color(0xFF0d1f3c), Color(0xFF070f1e)],
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(child: _BackgroundGrid()),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Brain icon + ripples
                      SizedBox(
                        width: 200,
                        height: 200,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (_rippleCtrl.isAnimating ||
                                _rippleCtrl.isCompleted) ...[
                              Transform.scale(
                                scale: _ripple1.value,
                                child: Opacity(
                                  opacity: _ripple1Opacity.value,
                                  child: Container(
                                    width: 130,
                                    height: 130,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF3B82F6),
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Transform.scale(
                                scale: _ripple2.value,
                                child: Opacity(
                                  opacity: _ripple2Opacity.value,
                                  child: Container(
                                    width: 130,
                                    height: 130,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF60A5FA),
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            Opacity(
                              opacity: _glowSize.value * 0.6,
                              child: Container(
                                width: 160,
                                height: 160,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF3B82F6,
                                      ).withValues(alpha: 0.45),
                                      blurRadius: 80,
                                      spreadRadius: 20,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Transform.scale(
                              scale: _brainScale.value,
                              child: Opacity(
                                opacity: _brainOpacity.value,
                                child: Container(
                                  width: 120,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFF1e3a6e),
                                        Color(0xFF0d1f3c),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(32),
                                    border: Border.all(
                                      color: const Color(
                                        0xFF3B82F6,
                                      ).withValues(alpha: 0.45),
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF1F4E95,
                                        ).withValues(alpha: 0.5),
                                        blurRadius: 24,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  padding: const EdgeInsets.all(22),
                                  child: const BrainLogo(size: 76),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // App name — NO decoration, plain text with shader
                      FadeTransition(
                        opacity: _titleOpacity,
                        child: SlideTransition(
                          position: _titleSlide,
                          child: ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [
                                Color(0xFFFFFFFF),
                                Color(0xFF93C5FD),
                                Color(0xFFFFFFFF),
                              ],
                              stops: [0.0, 0.5, 1.0],
                            ).createShader(bounds),
                            child: const Text(
                              'NeuroMathix',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 40,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.5,
                                // explicitly no decoration
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      // Tagline — plain, no underline
                      FadeTransition(
                        opacity: _taglineOpacity,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 36,
                              height: 1,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    const Color(
                                      0xFF3B82F6,
                                    ).withValues(alpha: 0.7),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'AI · POWERED · LEARNING',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 3.5,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              width: 36,
                              height: 1,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(
                                      0xFF3B82F6,
                                    ).withValues(alpha: 0.7),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 48),

                      // Progress bar
                      FadeTransition(
                        opacity: _titleOpacity,
                        child: Column(
                          children: [
                            SizedBox(
                              width: 200,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Stack(
                                  children: [
                                    Container(
                                      height: 3,
                                      color: Colors.white.withValues(
                                        alpha: 0.08,
                                      ),
                                    ),
                                    FractionallySizedBox(
                                      widthFactor: _barProgress.value,
                                      child: Container(
                                        height: 3,
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Color(0xFF2563EB),
                                              Color(0xFF93C5FD),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Initialising your experience...',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.28),
                                fontSize: 11,
                                letterSpacing: 0.5,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BackgroundGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _GridPainter());
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;
    const spacing = 36.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
