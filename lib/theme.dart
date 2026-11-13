import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

/// Ένα θέμα χρωμάτων. Το όνομα της κλάσης έμεινε «Aigaio» από το πρώτο θέμα, για να μη
/// σπάσει ο υπόλοιπος κώδικας· σήμερα κρατά όποιο θέμα έχει διαλέξει ο χρήστης.
///
/// Θέματα (απόφαση 1/11): φωτεινά «Αιγαίο», «Ελιά», «Αυγή» · σκοτεινά «Αιγαίο», «Στίβος», «Ανάσα».
/// Αλλάζουν μόνο τα χρώματα· η διάταξη και η γραμματοσειρά μένουν ίδιες.
/// Κανόνες: κάθε κείμενο ≥ 4,5:1 αντίθεση, και κάθε μέτρηση κρατά τη σημασία της σε όλα τα θέματα
/// (π.χ. βαθύς ύπνος πάντα το πιο σκούρο/έντονο, «ξύπνιος» πάντα ζεστό χρώμα).
/// Round 1 (U4-3, U1b-06, U6-13, U1a-17): το 4,5:1 ισχύει και για χρωματιστό κείμενο πάνω στο δικό του απαλό φόντο
/// ([tint] πάνω σε κάρτα: «+ Φαγητό», τα «χάπια» τάσης, «Στήσιμο:»). Γι' αυτό λίγο πιο σκούρα, ίδια απόχρωση: Αιγαίο
/// good/food/exercise, Ελιά food, Αυγή good/exercise/primary· στα σκούρα Αιγαίο primary, Στίβος/Ανάσα textSecondary.
/// Τα γεμάτα χρώματα (`*Solid`) δεν άλλαξαν. Υπολογισμός WCAG 2.x για τα 6 θέματα: δοκιμή test/r1_f9_test.dart.
class Aigaio extends ThemeExtension<Aigaio> {
  const Aigaio._({
    required this.id,
    required this.name,
    required this.mood,
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
    required this.warn,
    required this.warnBg,
    required this.warnLine,
    required this.nav,
    required this.navBorder,
    required this.navIdle,
    required this.navLabel,
    required this.navShadow,
    required this.todayPill,
    required this.todayPillInk,
    required this.snack,
    required this.nightTop,
    required this.nightBottom,
    required this.ring,
    required this.health,
    required this.food,
    required this.exercise,
    required this.healthSolid,
    required this.foodSolid,
    required this.exerciseSolid,
    required this.onSolid,
    required this.stageDeep,
    required this.stageLight,
    required this.stageRem,
    required this.stageAwake,
  });

  /// Σταθερό κλειδί για την αποθήκευση («elia»).
  final String id;

  /// Όνομα και μία λέξη για τον χαρακτήρα του, όπως φαίνονται στις Ρυθμίσεις.
  final String name;
  final String mood;

  final bool dark;
  final Color background;
  final Color card;
  final Color hairline;
  final Color text;
  final Color textSecondary;
  final Color textTertiary;
  final Color primary;
  final Color onPrimary;

  /// Ένα χρώμα ανά ενότητα (και για κείμενο).
  final Color sleep;
  final Color heart;
  final Color body;
  final Color move;
  final Color energy;

  /// Καλή / κακή τάση. [bad]: «χειρότερα» και κίνδυνος (σχέδια 9/11: δικό του κόκκινο, ΠΟΤΕ ίδιο με το
  /// πορτοκαλί της Άσκησης, και ποτέ για ουδέτερα πράγματα).
  final Color good;
  final Color bad;

  /// Κεχριμπάρι «προσοχή» (σχέδια 9/11): λείπει κάτι, κάτι δεν μετριέται, πόνος. [warn] για κείμενο/εικονίδιο,
  /// [warnBg] φόντο κουτιού, [warnLine] περίγραμμα.
  final Color warn;
  final Color warnBg;
  final Color warnLine;

  /// Η μπάρα πλοήγησης.
  final Color nav;
  final Color navBorder;
  final Color navIdle;
  final Color navLabel;
  final Color navShadow;

  /// Το «χάπι» του «Σήμερα» όταν είναι επιλεγμένο.
  final Color todayPill;
  final Color todayPillInk;

  /// Φόντο για τα μηνύματα κάτω (snackbar)· πάντα με λευκά γράμματα.
  final Color snack;

  /// Η νυχτερινή κάρτα ύπνου και ο κύκλος βαθμολογίας πάνω της.
  final Color nightTop;
  final Color nightBottom;
  final Color ring;

  /// Οι τρεις μεγάλες κατηγορίες: χρώμα για κείμενο και λεπτομέρειες.
  final Color health;
  final Color food;
  final Color exercise;

  /// Γεμάτα χρώματα κατηγοριών (κουμπιά, μπάρα), με [onSolid] από πάνω.
  final Color healthSolid;
  final Color foodSolid;
  final Color exerciseSolid;
  final Color onSolid;

  /// Φάσεις ύπνου.
  final Color stageDeep;
  final Color stageLight;
  final Color stageRem;
  final Color stageAwake;

  // Παλιά ονόματα, για να μη σπάσει ο υπόλοιπος κώδικας.
  Color get terracotta => heart;
  Color get wheat => move;
  Color get olive => body;

  Color stage(String name) => switch (name) {
        'DEEP' => stageDeep,
        'LIGHT' => stageLight,
        'REM' => stageRem,
        'AWAKE' => stageAwake,
        _ => textTertiary,
      };

  // --- Φωτεινά ---------------------------------------------------------------

  static const light = Aigaio._(
    id: 'aigaio',
    name: 'Αιγαίο',
    mood: 'Ήρεμο',
    dark: false,
    background: Color(0xFFF4F6FA),
    card: Color(0xFFFFFFFF),
    hairline: Color(0xFFE6EAF1),
    text: Color(0xFF0F172A),
    textSecondary: Color(0xFF5B6576),
    textTertiary: Color(0xFF69717F), // ≥4,5:1 σε κάρτα και φόντο (έλεγχος 1/11)
    primary: Color(0xFF1D5BD8),
    onPrimary: Color(0xFFFFFFFF),
    sleep: Color(0xFF4F63D9),
    heart: Color(0xFFB84F28),
    body: Color(0xFF557427),
    move: Color(0xFF8A6508),
    energy: Color(0xFF1D5BD8),
    good: Color(0xFF3C771F),
    bad: Color(0xFFB42318),
    warn: Color(0xFF8A4B06),
    warnBg: Color(0xFFFEF3DC),
    warnLine: Color(0xFFE9B45A),
    nav: Color(0xFF0F172A),
    navBorder: Color(0x00000000),
    navIdle: Color(0xFFA3AEC2),
    navLabel: Color(0xFFFFFFFF),
    navShadow: Color(0x400F172A),
    todayPill: Color(0xFFFFFFFF),
    todayPillInk: Color(0xFF0F172A),
    snack: Color(0xFF111827),
    nightTop: Color(0xFF141C45),
    nightBottom: Color(0xFF2A3C96),
    ring: Color(0xFFFFFFFF),
    health: Color(0xFF1D5BD8),
    food: Color(0xFF14793A),
    exercise: Color(0xFFBA3E0C),
    healthSolid: Color(0xFF1D5BD8),
    foodSolid: Color(0xFF15803D),
    exerciseSolid: Color(0xFFC2410C),
    onSolid: Color(0xFFFFFFFF),
    stageDeep: Color(0xFF3B2FB5),
    stageLight: Color(0xFF6F8CF6),
    stageRem: Color(0xFF6CC9F2),
    stageAwake: Color(0xFFF4A38A),
  );

  /// Πέτρα, λαδί, τερακότα: ήρεμο και φυσικό.
  static const elia = Aigaio._(
    id: 'elia',
    name: 'Ελιά',
    mood: 'Φυσικό',
    dark: false,
    background: Color(0xFFF2F1EA),
    card: Color(0xFFFFFFFF),
    hairline: Color(0xFFE3E1D6),
    text: Color(0xFF1E2318),
    textSecondary: Color(0xFF5E6354),
    textTertiary: Color(0xFF6C6F64), // ≥4,5:1 σε κάρτα και φόντο (έλεγχος 1/11)
    primary: Color(0xFF4E6526),
    onPrimary: Color(0xFFFFFFFF),
    sleep: Color(0xFF3D6A9E),
    heart: Color(0xFFA24E2C),
    body: Color(0xFF5C7425),
    move: Color(0xFF7A5E12),
    energy: Color(0xFF2F6E7E),
    good: Color(0xFF45601C),
    bad: Color(0xFFB3261E),
    warn: Color(0xFF7F4A0A),
    warnBg: Color(0xFFFBF0D9),
    warnLine: Color(0xFFDDB066),
    nav: Color(0xFF232A1C),
    navBorder: Color(0x00000000),
    navIdle: Color(0xFFAEB39E),
    navLabel: Color(0xFFFFFFFF),
    navShadow: Color(0x47232A1C),
    todayPill: Color(0xFFF2F1EA),
    todayPillInk: Color(0xFF1E2318),
    snack: Color(0xFF232A1C),
    nightTop: Color(0xFF1F2B33),
    nightBottom: Color(0xFF3A5566),
    ring: Color(0xFFD2E3A0),
    health: Color(0xFF2F5D7C),
    food: Color(0xFF3D772D),
    exercise: Color(0xFFA94C24),
    healthSolid: Color(0xFF2F5D7C),
    foodSolid: Color(0xFF3E7A2E),
    exerciseSolid: Color(0xFFA94C24),
    onSolid: Color(0xFFFFFFFF),
    stageDeep: Color(0xFF31578A),
    stageLight: Color(0xFF7FA6C8),
    stageRem: Color(0xFFB5CC6A),
    stageAwake: Color(0xFFE8946A),
  );

  /// Ζεστό λευκό και κοραλλί, κάρτα ύπνου σαν ξημέρωμα: ζωντανό.
  static const avgi = Aigaio._(
    id: 'avgi',
    name: 'Αυγή',
    mood: 'Ζωντανό',
    dark: false,
    background: Color(0xFFFFF7F2),
    card: Color(0xFFFFFFFF),
    hairline: Color(0xFFF3E2D8),
    text: Color(0xFF2B1B17),
    textSecondary: Color(0xFF6E5A53),
    textTertiary: Color(0xFF816E69), // ≥4,5:1 σε κάρτα και φόντο (έλεγχος 1/11)
    primary: Color(0xFFBA3E0C),
    onPrimary: Color(0xFFFFFFFF),
    sleep: Color(0xFF5B3FC4),
    heart: Color(0xFFB33B0C),
    body: Color(0xFF0F766E),
    move: Color(0xFF8C5A0B),
    energy: Color(0xFF1D4ED8),
    good: Color(0xFF14793A),
    bad: Color(0xFFB42318),
    warn: Color(0xFF8A4B06),
    warnBg: Color(0xFFFEF3DC),
    warnLine: Color(0xFFE9B45A),
    nav: Color(0xFFFFFFFF),
    navBorder: Color(0xFFF3E2D8),
    navIdle: Color(0xFF7A6058),
    navLabel: Color(0xFF2B1B17),
    navShadow: Color(0x24C2410C),
    todayPill: Color(0xFFC2410C),
    todayPillInk: Color(0xFFFFFFFF),
    snack: Color(0xFF2B1B17),
    nightTop: Color(0xFF2B1748),
    nightBottom: Color(0xFF7A3566),
    ring: Color(0xFFFFC36B),
    health: Color(0xFF5B3FC4),
    food: Color(0xFF1F7A4A),
    exercise: Color(0xFFBA3E0C),
    healthSolid: Color(0xFF5B3FC4),
    foodSolid: Color(0xFF1F7A4A),
    exerciseSolid: Color(0xFFC2410C),
    onSolid: Color(0xFFFFFFFF),
    stageDeep: Color(0xFF6A4BD8),
    stageLight: Color(0xFFA58CF0),
    stageRem: Color(0xFFE879A6),
    stageAwake: Color(0xFFF5A524),
  );

  // --- Σκοτεινά --------------------------------------------------------------

  static const darkTheme = Aigaio._(
    id: 'aigaio',
    name: 'Αιγαίο',
    mood: 'Κλασικό',
    dark: true,
    background: Color(0xFF0B1020),
    card: Color(0xFF141B2D),
    hairline: Color(0xFF232C42),
    text: Color(0xFFE8ECF5),
    textSecondary: Color(0xFF9AA4B8),
    textTertiary: Color(0xFF79839B), // ≥4,5:1 σε κάρτα και φόντο (έλεγχος 1/11)
    primary: Color(0xFF619BFF),
    onPrimary: Color(0xFF04122E),
    sleep: Color(0xFF8C9CFF),
    heart: Color(0xFFF08A63),
    body: Color(0xFF9DBA63),
    move: Color(0xFFE0BC4A),
    energy: Color(0xFF6FA2FF),
    good: Color(0xFF9DBA63),
    bad: Color(0xFFFF7A6E),
    warn: Color(0xFFF5BE5B),
    warnBg: Color(0xFF33260C),
    warnLine: Color(0xFF8A6420),
    nav: Color(0xFF1A2236),
    navBorder: Color(0x00000000),
    navIdle: Color(0xFFA3AEC2),
    navLabel: Color(0xFFFFFFFF),
    navShadow: Color(0x66000000),
    todayPill: Color(0xFFFFFFFF),
    todayPillInk: Color(0xFF0F172A),
    snack: Color(0xFF232C42),
    nightTop: Color(0xFF111735),
    nightBottom: Color(0xFF1F2C6E),
    ring: Color(0xFFFFFFFF),
    health: Color(0xFF6FA2FF),
    food: Color(0xFF5CC98A),
    exercise: Color(0xFFF0915A),
    healthSolid: Color(0xFF1D5BD8),
    foodSolid: Color(0xFF15803D),
    exerciseSolid: Color(0xFFC2410C),
    onSolid: Color(0xFFFFFFFF),
    // Round 1 (U4-12, U2a-10): το #3B2FB5 του φωτεινού είχε 1,85:1 στη σκούρα κάρτα· ίδια απόχρωση, ≥ 3:1, πάντα η πιο σκούρα φάση.
    stageDeep: Color(0xFF5F54D3),
    stageLight: Color(0xFF6F8CF6),
    stageRem: Color(0xFF6CC9F2),
    stageAwake: Color(0xFFF4A38A),
  );

  /// Σχεδόν μαύρο με κίτρινο-λάιμ: αθλητικό.
  static const stivos = Aigaio._(
    id: 'stivos',
    name: 'Στίβος',
    mood: 'Αθλητικό',
    dark: true,
    background: Color(0xFF0B0C0E),
    card: Color(0xFF16181C),
    hairline: Color(0xFF24272D),
    text: Color(0xFFF2F4F0),
    textSecondary: Color(0xFFA2A8A1),
    textTertiary: Color(0xFF7E827D), // ≥4,5:1 σε κάρτα και φόντο (έλεγχος 1/11)
    primary: Color(0xFFC8F04A),
    onPrimary: Color(0xFF0B0C0E),
    sleep: Color(0xFF8AB4FF),
    heart: Color(0xFFFF8A65),
    body: Color(0xFFB8A3FF),
    move: Color(0xFFF2C94C),
    energy: Color(0xFF6FE3F5),
    good: Color(0xFFC8F04A),
    bad: Color(0xFFFF6B6B),
    warn: Color(0xFFF5BE5B),
    warnBg: Color(0xFF2E2410),
    warnLine: Color(0xFF7E6122),
    nav: Color(0xFF16181C),
    navBorder: Color(0xFF24272D),
    navIdle: Color(0xFF8A9089),
    navLabel: Color(0xFFF2F4F0),
    navShadow: Color(0x80000000),
    todayPill: Color(0xFFC8F04A),
    todayPillInk: Color(0xFF0B0C0E),
    snack: Color(0xFF24272D),
    nightTop: Color(0xFF151833),
    nightBottom: Color(0xFF232A5E),
    ring: Color(0xFFC8F04A),
    health: Color(0xFF8AB4FF),
    food: Color(0xFF5EE0B0),
    exercise: Color(0xFFC8F04A),
    healthSolid: Color(0xFF8AB4FF),
    foodSolid: Color(0xFF5EE0B0),
    exerciseSolid: Color(0xFFC8F04A),
    onSolid: Color(0xFF0B0C0E),
    stageDeep: Color(0xFF6D6BFF),
    stageLight: Color(0xFF9DB4FF),
    stageRem: Color(0xFF6FE3F5),
    stageAwake: Color(0xFFFF9D7A),
  );

  /// Βαθύ πετρόλ με μέντα: χαλαρό, για ύπνο και ανάκαμψη.
  static const anasa = Aigaio._(
    id: 'anasa',
    name: 'Ανάσα',
    mood: 'Χαλαρό',
    dark: true,
    background: Color(0xFF061416),
    card: Color(0xFF0D2124),
    hairline: Color(0xFF183337),
    text: Color(0xFFE6F2F1),
    textSecondary: Color(0xFF9AB3B0),
    textTertiary: Color(0xFF738B88), // ≥4,5:1 σε κάρτα και φόντο (έλεγχος 1/11)
    primary: Color(0xFF5EEAD4),
    onPrimary: Color(0xFF04201C),
    sleep: Color(0xFF7DD3FC),
    heart: Color(0xFFFDA48A),
    body: Color(0xFFE2C27A),
    move: Color(0xFFFDE68A),
    energy: Color(0xFF5EEAD4),
    good: Color(0xFFA3E07A),
    bad: Color(0xFFFF8A80),
    warn: Color(0xFFF5C46B),
    warnBg: Color(0xFF2C2A12),
    warnLine: Color(0xFF7D6A2A),
    nav: Color(0xFF0D2124),
    navBorder: Color(0xFF183337),
    navIdle: Color(0xFF8AA5A2),
    navLabel: Color(0xFFE6F2F1),
    navShadow: Color(0x80000000),
    todayPill: Color(0xFF5EEAD4),
    todayPillInk: Color(0xFF04201C),
    snack: Color(0xFF183337),
    nightTop: Color(0xFF0B2A3A),
    nightBottom: Color(0xFF14506A),
    ring: Color(0xFF5EEAD4),
    health: Color(0xFF7DD3FC),
    food: Color(0xFFA3E07A),
    exercise: Color(0xFFFDBA74),
    healthSolid: Color(0xFF7DD3FC),
    foodSolid: Color(0xFFA3E07A),
    exerciseSolid: Color(0xFFFDBA74),
    onSolid: Color(0xFF04201C),
    stageDeep: Color(0xFF4F7DF0),
    stageLight: Color(0xFF7FC8E8),
    stageRem: Color(0xFF5EEAD4),
    stageAwake: Color(0xFFFDBA74),
  );

  static const dayThemes = [light, elia, avgi];
  static const nightThemes = [darkTheme, stivos, anasa];

  static Aigaio day(String? id) => dayThemes.firstWhere((t) => t.id == id, orElse: () => light);
  static Aigaio night(String? id) => nightThemes.firstWhere((t) => t.id == id, orElse: () => darkTheme);

  static Aigaio of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<Aigaio>() ?? (theme.brightness == Brightness.dark ? darkTheme : light);
  }

  /// Απαλό φόντο για εικονίδια και «χάπια» (pills).
  Color tint(Color c) => c.withValues(alpha: dark ? 0.18 : 0.12);

  /// Το σκούρο «μελάνι» για γράμματα πάνω σε ανοιχτό γεμάτο χρώμα (το ίδιο με τη λωρίδα του διαλείμματος).
  static const ink = Color(0xFF0F172A);

  /// Γράμματα και εικονίδια πάνω σε γεμάτο χρώμα [solid]: λευκό ή σκούρο, όποιο έχει μεγαλύτερη αντίθεση (τύπος WCAG).
  /// Τελικός έλεγχος, Συμβούλιο 5 (U-3): στα σκούρα θέματα τα «good» και «bad» είναι ανοιχτά (φτιαγμένα για κείμενο πάνω
  /// σε σκούρη κάρτα)· τα λευκά γράμματα πάνω τους («Έγινε», το ✓ του σετ, «Διαγραφή όλων») είχαν αντίθεση 1,3–2,8:1.
  static Color inkOn(Color solid) {
    final l = solid.computeLuminance();
    final withWhite = 1.05 / (l + 0.05);
    final withInk = (l + 0.05) / (ink.computeLuminance() + 0.05);
    return withWhite >= withInk ? Colors.white : ink;
  }

  /// Η αντίθεση δύο χρωμάτων κατά WCAG (1 ως 21), για τους ελέγχους.
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
  }

  @override
  Aigaio copyWith() => this;

  /// Χωρίς σβήσιμο από θέμα σε θέμα: η αλλαγή γίνεται καθαρά.
  @override
  Aigaio lerp(ThemeExtension<Aigaio>? other, double t) => other is Aigaio && t >= 0.5 ? other : this;
}

/// Αριθμοί με σταθερό πλάτος, ώστε να μη «χορεύουν».
const tabular = [FontFeature.tabularFigures()];

const fontFamily = 'Inter';

final _cache = <Aigaio, ThemeData>{};

/// Το θέμα της εφαρμογής. Χωρίς [palette]: Αιγαίο φωτεινό ή σκοτεινό (π.χ. η αναφορά για γιατρό).
ThemeData buildTheme(Brightness brightness, [Aigaio? palette]) {
  final c = palette ?? (brightness == Brightness.dark ? Aigaio.darkTheme : Aigaio.light);
  return _cache[c] ??= _build(c);
}

ThemeData _build(Aigaio c) {
  final brightness = c.dark ? Brightness.dark : Brightness.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.primary,
    onPrimary: c.onPrimary,
    secondary: c.body,
    onSecondary: c.onPrimary,
    error: c.bad,
    onError: c.dark ? c.background : Colors.white,
    surface: c.card,
    onSurface: c.text,
    surfaceContainerHighest: c.background,
    outline: c.hairline,
    // Round 1 (U4-1, U3a-11, U7-21): οι επιλεγμένες ετικέτες (ChoiceChip), τα SegmentedButton και τα «−/+» γεμίζουν με το
    // secondaryContainer· χωρίς αυτό έπαιρναν το secondary (= χρώμα του «Σώματος», λαδί δίπλα στα μπλε κουμπιά). Τώρα ίδιο
    // με την επιλογή του «Φωτεινό/Σκοτεινό» (κύριο χρώμα, onPrimary από πάνω, ≥ 4,5:1 σε όλα τα θέματα).
    secondaryContainer: c.primary,
    onSecondaryContainer: c.onPrimary,
    // Το περίγραμμα των μη επιλεγμένων ετικετών: λεπτή γραμμή όπως όλα τα περιγράμματα (πριν: το χρώμα του κειμένου).
    outlineVariant: c.hairline,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: fontFamily,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.background,
    canvasColor: c.background,
    splashFactory: InkSparkle.splashFactory,
    extensions: [c],
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
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.card, surfaceTintColor: Colors.transparent),
    // Round 1 (U5-31, U2b-20): οι τίτλοι των διαλόγων ήταν 24 px κανονικά (προεπιλογή Material)· τώρα όπως οι τίτλοι των φύλλων.
    dialogTheme: DialogThemeData(
      backgroundColor: c.card,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 20, height: 1.25, fontWeight: FontWeight.w800, color: c.text),
      contentTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 15, height: 1.4, color: c.textSecondary),
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
    // Round 1 (U4-2, U5-05): ο ΚΛΕΙΣΤΟΣ διακόπτης δεν φαινόταν (κουκκίδα/ράγα 1,1–1,4:1, WCAG 1.4.11 θέλει 3:1). Τώρα
    // κουκκίδα και περίγραμμα στο textTertiary (≥ 4,5:1 σε κάρτα και φόντο σε όλα τα θέματα)· ο ανοιχτός μένει ίδιος.
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) || s.contains(WidgetState.disabled) ? Colors.transparent : c.textTertiary),
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) || s.contains(WidgetState.disabled) ? null : c.textTertiary),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary),
    dividerTheme: DividerThemeData(color: c.hairline, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.snack,
      actionTextColor: c.dark ? c.primary : Colors.white,
      contentTextStyle: const TextStyle(fontFamily: fontFamily, color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

/// Οθόνες μιας κατηγορίας: κουμπιά, επιλογές και πεδία στο χρώμα της ([solid] γεμάτο, [text] για γράμματα).
ThemeData _categoryTheme(ThemeData t, Aigaio c, {required Color solid, required Color text}) => t.copyWith(
      colorScheme: t.colorScheme.copyWith(
        primary: solid,
        onPrimary: c.onSolid,
        secondary: solid,
        onSecondary: c.onSolid,
        // Round 1 (U4-1, U3a-11): το copyWith κρατούσε το secondaryContainer του βασικού θέματος, άρα οι επιλεγμένες
        // ετικέτες και τα «−/+» της Διατροφής έμεναν στο χρώμα του «Σώματος».
        secondaryContainer: solid,
        onSecondaryContainer: c.onSolid,
      ),
      textButtonTheme: TextButtonThemeData(
        style: (t.textButtonTheme.style ?? const ButtonStyle()).copyWith(
          foregroundColor: WidgetStatePropertyAll(text),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: (t.outlinedButtonTheme.style ?? const ButtonStyle()).copyWith(
          foregroundColor: WidgetStatePropertyAll(text),
        ),
      ),
      // Round 1 (U3a-15): η ετικέτα πεδίου με το «μάτι» πάνω της και ο κέρσορας έπαιρναν το γεμάτο χρώμα (σκούρο Αιγαίο:
      // #15803D σε #0B1020 = 3,8:1)· τώρα το χρώμα κειμένου της κατηγορίας (≥ 4,5:1). Στις άλλες καταστάσεις (και στο
      // λάθος, κόκκινο) μένει η προεπιλογή.
      inputDecorationTheme: t.inputDecorationTheme.copyWith(
        floatingLabelStyle: WidgetStateTextStyle.resolveWith((s) => TextStyle(
            color: s.contains(WidgetState.focused) && !s.contains(WidgetState.error) ? text : null)),
      ),
      textSelectionTheme: t.textSelectionTheme.copyWith(cursorColor: text),
    );

/// Οθόνες της Διατροφής: τα κουμπιά και οι επιλογές στο χρώμα της κατηγορίας.
class FoodTheme extends StatelessWidget {
  const FoodTheme({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Theme(data: _categoryTheme(Theme.of(context), c, solid: c.foodSolid, text: c.food), child: child);
  }
}

/// Οθόνες της Άσκησης (round 1, U5-30): όπως η [FoodTheme], στο πορτοκαλί της Άσκησης· αλλιώς διακόπτες και
/// δευτερεύοντα κουμπιά έβγαιναν μπλε δίπλα στα πορτοκαλί.
class ExerciseTheme extends StatelessWidget {
  const ExerciseTheme({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Theme(data: _categoryTheme(Theme.of(context), c, solid: c.exerciseSolid, text: c.exercise), child: child);
  }
}
