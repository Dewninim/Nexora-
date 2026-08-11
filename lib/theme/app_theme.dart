import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  // ── Brand Palette ──
  static const Color primary      = Color(0xFF0F172A); // Deep Slate Navy
  static const Color accent       = Color(0xFF2563EB); // Vibrant Royal Blue
  static const Color accentGradientStart = Color(0xFF3B82F6);
  static const Color accentGradientEnd   = Color(0xFF1D4ED8);

  static const Color textDark     = Color(0xFF0F172A); // Slate 900
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
  static const Color bgPage       = Color(0xFFF1F5F9);
  static const Color bgCard       = Colors.white;
}

/// STRICT TYPOGRAPHY HIERARCHY
/// Use these exact styles everywhere for 100% consistency across Student & Teacher screens.
class AppText {
  AppText._();

  // 1. PAGE TITLE (e.g., "Teacher Dashboard", "Student Dashboard") -> Always 24px Bold
  static TextStyle get pageTitle => GoogleFonts.dmSans(
      fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textDark, height: 1.25);

  static TextStyle get display => pageTitle;

  // 2. SECTION TOPIC / HEADER (e.g., "Recommended Now", "Student Help Requests") -> Always 18px Bold
  static TextStyle get sectionHeader => GoogleFonts.dmSans(
      fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textDark, height: 1.3);

  // 3. CARD TITLE / SUB-HEADER (e.g., Student Name, Concept Name, Metric Label) -> Always 15px SemiBold
  static TextStyle get cardTitle => GoogleFonts.dmSans(
      fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark, height: 1.35);

  // 4. PARAGRAPH / BODY TEXT (Standard readable description text) -> Always 13.5px Regular
  static TextStyle get body => GoogleFonts.dmSans(
      fontSize: 13.5, fontWeight: FontWeight.w400, color: AppColors.textDark, height: 1.55);

  // 5. BODY MUTED (Subtitles, secondary descriptions) -> Always 13.5px Regular Faded
  static TextStyle get bodyMuted => GoogleFonts.dmSans(
      fontSize: 13.5, fontWeight: FontWeight.w400, color: AppColors.textMuted, height: 1.5);

  // 6. BODY MEDIUM / BOLD (Emphasized text inside paragraphs) -> Always 13.5px SemiBold
  static TextStyle get bodyMedium => GoogleFonts.dmSans(
      fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textDark, height: 1.5);

  // 7. CAPTION & BADGES (Timestamp, tags, status pills) -> Always 12px Medium
  static TextStyle get caption => GoogleFonts.dmSans(
      fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textMuted);

  // 8. EYEBROW / SMALL LABEL (Upper-case section labels) -> Always 11px Bold Spaced
  static TextStyle get eyebrow => GoogleFonts.dmSans(
      fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint, letterSpacing: 0.8);

  // 9. METRIC / LARGE NUMBER -> 26px ExtraBold
  static TextStyle get metricValue => GoogleFonts.dmSans(
      fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textDark, height: 1.1);

  // 10. BUTTON TEXT -> 13.5px Bold
  static TextStyle get button => GoogleFonts.dmSans(
      fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white);
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
      textTheme: GoogleFonts.dmSansTextTheme(base.textTheme).apply(
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