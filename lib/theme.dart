import 'package:flutter/material.dart';

/// Flashback Cam color palette following modern, minimal, premium design
class AppColors {
  // Core background colors - deep dark theme
  static const Color deepCharcoal = Color(0xFF0A0A0A);
  static const Color charcoal = Color(0xFF121212);
  static const Color lightCharcoal = Color(0xFF1A1A1A);
  static const Color surfaceCard = Color(0xFF1E1E1E);

  // Neon accent colors for premium feel
  static const Color electricBlue = Color(0xFF00E5FF);
  static const Color neonCyan = Color(0xFF64FFDA);
  static const Color vibrantPurple = Color(0xFFFFBF00);
  static const Color neonGreen = Color(0xFF69F0AE);

  // Recording and status colors
  static const Color recordRed = Color(0xFFFF1744);
  static const Color recordRedGlow = Color(0x40FF1744);
  static const Color warningOrange = Color(0xFFFF6D00);
  static const Color successGreen = Color(0xFF00E676);
  static const Color proGold = Color(0xFFFFD700);

  // Glassmorphism effect colors
  static const Color glassWhite = Color(0x0DFFFFFF);
  static const Color glassDark = Color(0x0D000000);
  static const Color glassLight = Color(0x1AFFFFFF);
  static const Color glassBorder = Color(0x33FFFFFF);

  // Text hierarchy
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xB3FFFFFF);
  static const Color textTertiary = Color(0x66FFFFFF);
  static const Color textDisabled = Color(0x42FFFFFF);

  // Interactive states
  static const Color buttonPrimary = Color(0xFF00E5FF);
  static const Color buttonSecondary = Color(0x1AFFFFFF);
  static const Color buttonDisabled = Color(0x0DFFFFFF);
  static const Color rippleColor = Color(0x1AFFFFFF);

  // Legacy color properties for widgets (backwards compatibility)
  static const Color darkGlassOverlay = glassWhite;
  static const Color glassOverlay = glassLight;
  static const Color darkGlassBorder = glassBorder;
  static const Color cardDark = surfaceCard;
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color borderDark = glassBorder;
  static const Color borderLight = Color(0x1A000000);
  static const Color textPrimaryDark = textPrimary;
}

/// Complete theme system for Flashback Cam
class FlashbackTheme {
  static const String fontFamily = 'Inter';

  /// Dark theme (primary theme as per spec)
  static ThemeData get darkTheme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.deepCharcoal,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.electricBlue,
          secondary: AppColors.neonCyan,
          surface: AppColors.charcoal,
          background: AppColors.deepCharcoal,
          error: AppColors.recordRed,
          onPrimary: AppColors.deepCharcoal,
          onSecondary: AppColors.deepCharcoal,
          onSurface: AppColors.textPrimary,
          onBackground: AppColors.textPrimary,
          onError: AppColors.textPrimary,
        ),
        fontFamily: fontFamily,
        splashFactory: InkRipple.splashFactory,
      );

  /// Light theme (fallback, but app defaults to dark)
  static ThemeData get lightTheme => ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFFAFAFA),
        colorScheme: const ColorScheme.light(
          primary: AppColors.electricBlue,
          secondary: AppColors.neonCyan,
          surface: Colors.white,
          background: Color(0xFFFAFAFA),
          error: AppColors.recordRed,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Color(0xFF1A1A1A),
          onBackground: Color(0xFF1A1A1A),
          onError: Colors.white,
        ),
        fontFamily: fontFamily,
      );
}
