import 'package:flutter/material.dart';

/// Design language lifted from the reference mockup: a warm, cream
/// "outdoor journal" palette — forest green for trust/primary actions,
/// amber for caution, muted red for danger — with bold, tight-tracked
/// headlines and small uppercase "kicker" labels above section titles.
class AppColors {
  static const bg = Color(0xFFF4F5F0);
  static const ink = Color(0xFF132019);
  static const muted = Color(0xFF69756E);
  static const forest = Color(0xFF173B2B);
  static const green = Color(0xFF4D8063);
  static const mint = Color(0xFFDDECE0);
  static const line = Color(0xFFDDE3DE);
  static const white = Color(0xFFFFFFFF);
  static const amber = Color(0xFFE39A3B);
  static const amberBg = Color(0xFFFFF1DD);
  static const amberText = Color(0xFF86571E);
  static const red = Color(0xFFCB5148);
  static const blue = Color(0xFF4D8098);

  // Dark-mode counterpart: same accent hues, inverted base surfaces.
  static const bgDark = Color(0xFF11150F);
  static const inkDark = Color(0xFFEFF3EE);
  static const mutedDark = Color(0xFFA3ACA4);
  static const surfaceDark = Color(0xFF1B211C);
  static const lineDark = Color(0xFF2C342D);
}

/// Small helpers for the recurring text treatments in the reference: the
/// uppercase, letter-spaced "kicker" label and the bold, tight headline.
class AppText {
  static TextStyle kicker(Color color) => TextStyle(
        color: color,
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.35,
      );

  static TextStyle title(Color color, {double size = 28}) => TextStyle(
        color: color,
        fontSize: size,
        height: 1.15,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.6,
      );

  static TextStyle sectionMeta(Color color) => TextStyle(
        color: color,
        fontSize: 9,
        fontWeight: FontWeight.w900,
        letterSpacing: 1,
      );
}

ThemeData buildAppTheme({required bool isDark}) {
  final bg = isDark ? AppColors.bgDark : AppColors.bg;
  final surface = isDark ? AppColors.surfaceDark : AppColors.white;
  final ink = isDark ? AppColors.inkDark : AppColors.ink;
  final line = isDark ? AppColors.lineDark : AppColors.line;

  return ThemeData(
    brightness: isDark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: bg,
    useMaterial3: true,
    colorScheme: ColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: AppColors.forest,
      onPrimary: AppColors.white,
      secondary: AppColors.green,
      onSecondary: AppColors.white,
      error: AppColors.red,
      onError: AppColors.white,
      surface: surface,
      onSurface: ink,
      outline: line,
    ),
    fontFamily: 'Roboto',
    textTheme: TextTheme(bodyMedium: TextStyle(fontSize: 15, color: ink)),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: AppText.title(ink, size: 20),
    ),
  );
}
