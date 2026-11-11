import 'package:flutter/material.dart';

class AppTheme {
  static const _black = Color(0xFF0B0B0C);
  static const _white = Color(0xFFF5F5F5);

  static ThemeData _build(Brightness b) {
    final dark = b == Brightness.dark;
    final fg = dark ? _white : _black;
    final bg = dark ? _black : _white;
    final base = ThemeData(brightness: b, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: ColorScheme(
        brightness: b,
        primary: fg,
        onPrimary: bg,
        secondary: fg,
        onSecondary: bg,
        error: const Color(0xFFB3261E),
        onError: Colors.white,
        surface: bg,
        onSurface: fg,
      ),
      textTheme: base.textTheme.apply(bodyColor: fg, displayColor: fg),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark
            ? const Color.fromRGBO(255, 255, 255, .10)
            : const Color.fromRGBO(0, 0, 0, .06),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: fg,
          foregroundColor: bg,
          minimumSize: const Size.fromHeight(54),
          shape: const StadiumBorder(),
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  static final light = _build(Brightness.light);
  static final dark = _build(Brightness.dark);
}
