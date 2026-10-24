import 'package:flutter/material.dart';

/// Τα χρώματα του θέματος «Αιγαίο» (εγκεκριμένα στο έγγραφο προδιαγραφών).
class Aigaio {
  const Aigaio._({
    required this.background,
    required this.card,
    required this.text,
    required this.textSecondary,
    required this.primary,
    required this.onPrimary,
    required this.terracotta,
    required this.wheat,
    required this.olive,
    required this.nav,
  });

  final Color background;
  final Color card;
  final Color text;
  final Color textSecondary;
  final Color primary;
  final Color onPrimary;
  final Color terracotta;
  final Color wheat;
  final Color olive;
  final Color nav;

  static const light = Aigaio._(
    background: Color(0xFFF3F5F9),
    card: Color(0xFFFFFFFF),
    text: Color(0xFF0F172A),
    textSecondary: Color(0xFF5B6474),
    primary: Color(0xFF1D5BD8),
    onPrimary: Color(0xFFFFFFFF),
    terracotta: Color(0xFFD9673F),
    wheat: Color(0xFFC9A227),
    olive: Color(0xFF6E8B3D),
    nav: Color(0xFF0F172A),
  );

  static const dark = Aigaio._(
    background: Color(0xFF0B1020),
    card: Color(0xFF151C2F),
    text: Color(0xFFE8ECF5),
    textSecondary: Color(0xFF9AA4B8),
    primary: Color(0xFF4C8DFF),
    onPrimary: Color(0xFF04122E),
    terracotta: Color(0xFFF08A63),
    wheat: Color(0xFFE0BC4A),
    olive: Color(0xFF9DBA63),
    nav: Color(0xFF1E2740),
  );

  static Aigaio of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? Aigaio.dark : Aigaio.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.primary,
    onPrimary: c.onPrimary,
    secondary: c.olive,
    onSecondary: c.onPrimary,
    error: c.terracotta,
    onError: c.onPrimary,
    surface: c.card,
    onSurface: c.text,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.background,
    cardTheme: CardThemeData(
      color: c.card,
      elevation: 1,
      shadowColor: Colors.black26,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}
