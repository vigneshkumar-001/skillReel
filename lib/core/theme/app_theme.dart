import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  static const String _fontFamily = 'Roboto';

  static TextTheme _textTheme(Color textColor) {
    // Keep the system font, but make typography more modern + consistent.
    const tight = -0.2;
    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 52,
        height: 1.08,
        letterSpacing: -0.6,
        fontWeight: FontWeight.w900,
        color: textColor,
      ),
      displayMedium: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 44,
        height: 1.10,
        letterSpacing: -0.4,
        fontWeight: FontWeight.w900,
        color: textColor,
      ),
      displaySmall: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 36,
        height: 1.12,
        letterSpacing: -0.3,
        fontWeight: FontWeight.w900,
        color: textColor,
      ),
      headlineLarge: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 30,
        height: 1.18,
        letterSpacing: -0.2,
        fontWeight: FontWeight.w900,
        color: textColor,
      ),
      headlineMedium: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 26,
        height: 1.18,
        letterSpacing: -0.1,
        fontWeight: FontWeight.w900,
        color: textColor,
      ),
      headlineSmall: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 22,
        height: 1.20,
        letterSpacing: tight,
        fontWeight: FontWeight.w900,
        color: textColor,
      ),
      titleLarge: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 18,
        height: 1.25,
        letterSpacing: tight,
        fontWeight: FontWeight.w800,
        color: textColor,
      ),
      titleMedium: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 16,
        height: 1.25,
        letterSpacing: tight,
        fontWeight: FontWeight.w800,
        color: textColor,
      ),
      titleSmall: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 14,
        height: 1.25,
        letterSpacing: 0,
        fontWeight: FontWeight.w800,
        color: textColor,
      ),
      bodyLarge: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 16,
        height: 1.35,
        letterSpacing: 0,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
      bodyMedium: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 14,
        height: 1.35,
        letterSpacing: 0,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
      bodySmall: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 12,
        height: 1.35,
        letterSpacing: 0,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
      labelLarge: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 14,
        height: 1.2,
        letterSpacing: 0.1,
        fontWeight: FontWeight.w900,
        color: textColor,
      ),
      labelMedium: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 12,
        height: 1.2,
        letterSpacing: 0.1,
        fontWeight: FontWeight.w900,
        color: textColor,
      ),
      labelSmall: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 11,
        height: 1.2,
        letterSpacing: 0.1,
        fontWeight: FontWeight.w900,
        color: textColor,
      ),
    );
  }

  static ThemeData get light => ThemeData(
        fontFamily: _fontFamily,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          background: AppColors.bg,
        ),
        textTheme: _textTheme(AppColors.textPrimary),
        scaffoldBackgroundColor: AppColors.bg,
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF0B1220),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          contentTextStyle: const TextStyle(
            fontFamily: _fontFamily,
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.bg,
          foregroundColor: AppColors.textPrimary,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontFamily: _fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          labelStyle: const TextStyle(
            fontFamily: _fontFamily,
            fontWeight: FontWeight.w800,
            color: AppColors.textSecondary,
          ),
          hintStyle: const TextStyle(
            fontFamily: _fontFamily,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            textStyle: WidgetStateProperty.all(
              const TextStyle(
                fontFamily: _fontFamily,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.1,
              ),
            ),
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontFamily: _fontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        useMaterial3: true,
      );
}
