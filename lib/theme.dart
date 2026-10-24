import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

/// Θέμα «Αιγαίο», έκδοση 2: ήρεμη βάση, ένα χρώμα ανά ενότητα, νυχτερινή κάρτα ύπνου.
class Aigaio {
  const Aigaio._({
    required this.dark,
    required this.background,
    required this.card,
    required this.hairline,
    required this.text,
    required this.textSecondary,
    required this.textTertiary,
    required this.primary,
    required this.onPrimary,
    required this.sleep,
    required this.heart,
    required this.body,
    required this.move,
    required this.energy,
    required this.good,
    required this.bad,
    required this.nav,
    required this.nightTop,
    required this.nightBottom,
  });

  final bool dark;
  final Color background;
  final Color card;
  final Color hairline;
  final Color text;
  final Color textSecondary;
  final Color textTertiary;
  final Color primary;
  final Color onPrimary;

  /// Ένα χρώμα ανά ενότητα.
  final Color sleep;
  final Color heart;
  final Color body;
  final Color move;
  final Color energy;

  /// Καλή / κακή τάση.
  final Color good;
  final Color bad;

  final Color nav;
  final Color nightTop;
  final Color nightBottom;

  // Παλιά ονόματα, για να μη σπάσει ο υπόλοιπος κώδικας.
  Color get terracotta => heart;
  Color get wheat => move;
  Color get olive => body;

  static const light = Aigaio._(
    dark: false,
    background: Color(0xFFF4F6FA),
    card: Color(0xFFFFFFFF),
    hairline: Color(0xFFE6EAF1),
    text: Color(0xFF0F172A),
    textSecondary: Color(0xFF5B6576),
    textTertiary: Color(0xFF94A0B4),
    primary: Color(0xFF1D5BD8),
    onPrimary: Color(0xFFFFFFFF),
    sleep: Color(0xFF4F63D9),
    heart: Color(0xFFD9673F),
    body: Color(0xFF5E7E2E),
    move: Color(0xFFB8860B),
    energy: Color(0xFF1D5BD8),
    good: Color(0xFF3F7D20),
    bad: Color(0xFFC2410C),
    nav: Color(0xFF111827),
    nightTop: Color(0xFF141C45),
    nightBottom: Color(0xFF2A3C96),
  );

  static const darkTheme = Aigaio._(
    dark: true,
    background: Color(0xFF0B1020),
    card: Color(0xFF141B2D),
    hairline: Color(0xFF232C42),
    text: Color(0xFFE8ECF5),
    textSecondary: Color(0xFF9AA4B8),
    textTertiary: Color(0xFF6B7690),
    primary: Color(0xFF4C8DFF),
    onPrimary: Color(0xFF04122E),
    sleep: Color(0xFF8C9CFF),
    heart: Color(0xFFF08A63),
    body: Color(0xFF9DBA63),
    move: Color(0xFFE0BC4A),
    energy: Color(0xFF6FA2FF),
    good: Color(0xFF9DBA63),
    bad: Color(0xFFF08A63),
    nav: Color(0xFF1A2236),
    nightTop: Color(0xFF111735),
    nightBottom: Color(0xFF1F2C6E),
  );

  static Aigaio of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkTheme : light;

  /// Απαλό φόντο για εικονίδια και «χάπια» (pills).
  Color tint(Color c) => c.withValues(alpha: dark ? 0.18 : 0.12);
}

/// Φάσεις ύπνου: νυχτερινή κλίμακα, ίδια σε ανοιχτό και σκοτεινό.
class StageColors {
  static const deep = Color(0xFF3B2FB5);
  static const light = Color(0xFF6F8CF6);
  static const rem = Color(0xFF6CC9F2);
  static const awake = Color(0xFFF4A38A);
}

/// Αριθμοί με σταθερό πλάτος, ώστε να μη «χορεύουν».
const tabular = [FontFeature.tabularFigures()];

const fontFamily = 'Inter';

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? Aigaio.darkTheme : Aigaio.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.primary,
    onPrimary: c.onPrimary,
    secondary: c.body,
    onSecondary: c.onPrimary,
    error: c.bad,
    onError: Colors.white,
    surface: c.card,
    onSurface: c.text,
    surfaceContainerHighest: c.background,
    outline: c.hairline,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: fontFamily,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.background,
    splashFactory: InkSparkle.splashFactory,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: c.text, displayColor: c.text),
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: c.text,
      ),
      iconTheme: IconThemeData(color: c.text),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 50),
        foregroundColor: c.primary,
        side: BorderSide(color: c.hairline, width: 1.5),
        textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.primary,
        textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    dividerTheme: DividerThemeData(color: c.hairline, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.nav,
      contentTextStyle: const TextStyle(fontFamily: fontFamily, color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
