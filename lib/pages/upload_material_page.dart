import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/upload_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/upload_card.dart';
import '../widgets/learning_setup_card.dart';
import '../widgets/upload_feature_cards.dart';

class UploadMaterialPage extends StatelessWidget {
  const UploadMaterialPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => UploadProvider(),
      child: const _UploadMaterialView(),
    );
  }
}

class _UploadMaterialView extends StatelessWidget {
  const _UploadMaterialView();

  @override
  Widget build(BuildContext context) {
    final isSuccess = context.select<UploadProvider, bool>(
        (p) => p.state.status == UploadStatus.success);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Side-by-side 2-column layout (Hero + Graphic on Left, Upload Card on Right)
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 940;

                  final leftHero = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _HeroBadge(),
                      const SizedBox(height: 20),
                      const _HeroHeading(),
                      const SizedBox(height: 16),
                      const _HeroSubtext(),
                      const SizedBox(height: 24),
                      const _HeroFeaturePills(),
                      const SizedBox(height: 36),
                      if (isWide) const _NeuralPedestalGraphic(),
                    ],
                  );

                  final rightCard = AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    switchInCurve: Curves.easeOut,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: ScaleTransition(
                        scale: Tween(begin: 0.97, end: 1.0).animate(anim),
                        child: child,
                      ),
                    ),
                    child: isSuccess
                        ? const LearningSetupCard(key: ValueKey('setup'))
                        : const UploadCard(key: ValueKey('upload')),
                  );

                  if (!isWide) {
                    return Column(
                      children: [
                        leftHero,
                        const SizedBox(height: 32),
                        rightCard,
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: leftHero),
                      const SizedBox(width: 48),
                      Expanded(flex: 5, child: rightCard),
                    ],
                  );
                },
              ),

              if (!isSuccess) ...[
                const SizedBox(height: 48),
                const _SectionDivider(),
                const SizedBox(height: 40),
                const UploadFeatureCards(),
                const SizedBox(height: 36),
                Center(
                  child: Text(
                    '© 2026 NeuroMathix AI Learning System. All rights reserved.',
                    style: GoogleFonts.openSans(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.goldLight,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppColors.goldBorder.withValues(alpha: 0.7)),
      ),
      child: Text(
        'INTELLIGENCE MEETS EDUCATION',
        style: GoogleFonts.openSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _HeroHeading extends StatelessWidget {
  const _HeroHeading();

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: GoogleFonts.openSans(
          fontSize: 42,
          fontWeight: FontWeight.w600,
          color: AppColors.textDark,
          height: 1.15,
        ),
        children: const [
          TextSpan(text: 'Turn Study Material\nInto '),
          TextSpan(
            text: 'Math Mastery',
            style: TextStyle(color: AppColors.accent),
          ),
        ],
      ),
    );
  }
}

class _HeroSubtext extends StatelessWidget {
  const _HeroSubtext();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Upload your notes, worksheets, or textbook pages. NeuroMathix turns them into a personalized learning path built for your grade.',
      style: GoogleFonts.openSans(
        fontSize: 15,
        color: AppColors.textMuted,
        height: 1.6,
      ),
    );
  }
}

class _HeroFeaturePills extends StatelessWidget {
  const _HeroFeaturePills();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      children: const [
        _PillItem(icon: Icons.auto_awesome_outlined, label: 'AI analyzed'),
        _PillItem(icon: Icons.verified_user_outlined, label: 'Private & secure'),
        _PillItem(icon: Icons.cloud_done_outlined, label: 'Up to 60 MB'),
      ],
    );
  }
}

class _PillItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PillItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.accent),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.openSans(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pedestal 3D Neural Graphic with Floating Math Equation Cards (matching reference screenshot)
class _NeuralPedestalGraphic extends StatelessWidget {
  const _NeuralPedestalGraphic();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 280,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ambient soft blue & gold glow aura behind hero
          Container(
            width: 320,
            height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.accent.withValues(alpha: 0.18),
                  AppColors.goldAccent.withValues(alpha: 0.12),
                  Colors.transparent,
                ],
                radius: 0.85,
              ),
            ),
          ),

          // Central 16:9 Premium Luxury 3D AI Neural Math Brain
          Container(
            width: double.infinity,
            height: 260,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.goldBorder.withValues(alpha: 0.5), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.network(
                'assets/premium_luxury_math_brain.jpg',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.white,
                    child: const Icon(
                      Icons.psychology_outlined,
                      size: 80,
                      color: AppColors.accent,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppColors.border, thickness: 1)),
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(color: AppColors.goldAccent, shape: BoxShape.circle),
        ),
        Text(
          'Built for deeper understanding',
          style: GoogleFonts.openSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(color: AppColors.goldAccent, shape: BoxShape.circle),
        ),
        const Expanded(child: Divider(color: AppColors.border, thickness: 1)),
      ],
    );
  }
}
