import 'package:flutter/material.dart';

class WaterTheme {
  static const Color background = Color(0xFFFFFFFF);
  static const Color foreground = Color(0xFF000000);
  static const Color muted = Color(0xFF000000);
  static const Color hairline = Color(0xFFE6E6E6);

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.light(
        primary: foreground,
        onPrimary: background,
        surface: background,
        onSurface: foreground,
      ),
      fontFamily: 'Inter',
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500, fontSize: 40, color: foreground, letterSpacing: -1.0),
        displayMedium: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500, fontSize: 32, color: foreground, letterSpacing: -0.5),
        headlineLarge: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 22, color: foreground),
        headlineMedium: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 18, color: foreground),
        titleLarge: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 16, color: foreground),
        titleMedium: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 14, color: foreground),
        bodyLarge: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500, fontSize: 15, color: foreground, height: 1.5),
        bodyMedium: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500, fontSize: 13, color: foreground, height: 1.5),
        bodySmall: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500, fontSize: 11, color: foreground, height: 1.4),
        labelSmall: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 10, color: foreground, letterSpacing: 1.2),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      dividerColor: hairline,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
    );
  }
}
