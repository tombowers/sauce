import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData build() {
    const white = Color(0xFFFFFFFF);
    const mist = Color(0xFFF6F8FB);
    const hairline = Color(0xFFE7ECF2);
    const ink = Color(0xFF231F1B);
    const mint = Color(0xFF1F9D74);
    const coral = Color(0xFFF26B5E);
    const blue = Color(0xFF3B82F6);

    final scheme =
        ColorScheme.fromSeed(
          seedColor: blue,
          brightness: Brightness.light,
          surface: white,
        ).copyWith(
          primary: blue,
          secondary: mint,
          tertiary: coral,
          surface: white,
          onSurface: ink,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: white,
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          fontFamily: 'Georgia',
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          color: ink,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'Georgia',
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: ink,
        ),
        titleLarge: TextStyle(fontWeight: FontWeight.w700, color: ink),
        titleMedium: TextStyle(fontWeight: FontWeight.w600, color: ink),
        bodyLarge: TextStyle(height: 1.35, color: ink),
        bodyMedium: TextStyle(height: 1.35, color: ink),
        labelLarge: TextStyle(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: ink,
        ),
      ),
      cardTheme: CardThemeData(
        color: white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(
        color: hairline,
        space: 1,
        thickness: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: mist,
        selectedColor: blue.withValues(alpha: 0.12),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, color: ink),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: mist,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0x14000000), width: 1),
        ),
      ),
      iconTheme: const IconThemeData(color: ink),
    );
  }
}
