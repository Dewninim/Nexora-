import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  // ── Brand Palette ──
  static const Color primary      = Color(0xFF0F172A); // Deep Slate Navy
  static const Color sidebarNavy  = Color(0xFF060B19); // Midnight Deep Navy
  static const Color accent       = Color(0xFF2563EB); // Vibrant Royal Blue
  static const Color accentGradientStart = Color(0xFF3B82F6);
  static const Color accentGradientEnd   = Color(0xFF1D4ED8);

  // ── Luxury Gold Palette ──
  static const Color gold         = Color(0xFFD4AF37); // Champagne Gold
  static const Color goldAccent   = Color(0xFFDFB24E); // Warm Metallic Gold
  static const Color goldLight    = Color(0xFFFEF9EE); // Subtle Soft Gold Tint
  static const Color goldBorder   = Color(0xFFE5C158); // Refined Gold Border

  static const Color textDark     = Color(0xFF000000); // Pure Black #000000
  static const Color textMuted    = Color(0xFF64748B); // Slate 500
  static const Color textFaint    = Color(0xFF94A3B8); // Slate 400
  static const Color border       = Color(0xFFE2E8F0); // Slate 200
  static const Color borderLight  = Color(0xFFF1F5F9); // Slate 100
  static const Color surface      = Color(0xFFF8FAFC); // Slate 50

  // ── Status & Accent Colors ──
  static const Color success      = Color(0xFF10B981); // Emerald 500
  static const Color successBg    = Color(0xFFECFDF5); // Emerald 50
  static const Color error        = Color(0xFFEF4444); // Red 500
  static const Color errorBg      = Color(0xFFFEF2F2); // Red 50
  static const Color warning      = Color(0xFFF59E0B); // Amber 500
  static const Color warningBg    = Color(0xFFFFFBEB); // Amber 50
  static const Color info         = Color(0xFF8B5CF6); // Violet 500
  static const Color infoBg       = Color(0xFFF5F3FF); // Violet 50

  // ── Backgrounds ──
  static const Color bgPage       = Color(0xFFF3F5F9); // Premium Soft Off-White
  static const Color bgCard       = Colors.white;
}

/// STRICT UNIFIED TYPOGRAPHY HIERARCHY WITH OPEN SANS FONT FAMILY EXCLUSIVELY
class AppText {
  AppText._();

  // 0. HERO & PAGE HEADINGS -> Open Sans 32px - 26px Bold
  static TextStyle get heroSerif => GoogleFonts.openSans(
      fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.textDark, height: 1.2);

  static TextStyle get pageTitleSerif => GoogleFonts.openSans(
      fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.textDark, height: 1.25);

  // 1. PAGE TITLE -> 24px Bold
  static TextStyle get pageTitle => GoogleFonts.openSans(
      fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textDark, height: 1.25);

  static TextStyle get display => heroSerif;
  static TextStyle get h1 => pageTitleSerif;
  static TextStyle get h2 => sectionHeader;
  static TextStyle get h3 => cardTitle;

  // 2. SECTION TOPIC / HEADER -> 18px SemiBold
  static TextStyle get sectionHeader => GoogleFonts.openSans(
      fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textDark, height: 1.3);

  // 3. CARD TITLE / SUB-HEADER -> 15px SemiBold
  static TextStyle get cardTitle => GoogleFonts.openSans(
      fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textDark, height: 1.35);

  // 4. PARAGRAPH / BODY TEXT -> 14px Regular
  static TextStyle get body => GoogleFonts.openSans(
      fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textDark, height: 1.5);

  // 5. BODY MUTED -> 14px Regular Muted
  static TextStyle get bodyMuted => GoogleFonts.openSans(
      fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textMuted, height: 1.5);

  static TextStyle get bodySmall => bodyMuted;

  // 6. BODY MEDIUM -> 14px SemiBold
  static TextStyle get bodyMedium => GoogleFonts.openSans(
      fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textDark, height: 1.5);

  // 7. CAPTION & BADGES -> 12px SemiBold
  static TextStyle get caption => GoogleFonts.openSans(
      fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted);

  // 8. EYEBROW / SMALL LABEL -> 11px Bold Spaced
  static TextStyle get eyebrow => GoogleFonts.openSans(
      fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint, letterSpacing: 0.8);

  // 9. METRIC / LARGE NUMBER -> 28px Bold
  static TextStyle get metricValue => GoogleFonts.openSans(
      fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.textDark, height: 1.1);

  // 10. BUTTON TEXT -> 14px SemiBold
  static TextStyle get button => GoogleFonts.openSans(
      fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white);
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.accent,
        error: AppColors.error,
      ),
      scaffoldBackgroundColor: AppColors.bgPage,
    );

    return base.copyWith(
      textTheme: GoogleFonts.openSansTextTheme(base.textTheme).apply(
        bodyColor: AppColors.textDark,
        displayColor: AppColors.textDark,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        titleTextStyle: AppText.sectionHeader,
      ),
      cardTheme: CardThemeData(
        color: AppColors.bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }
}
