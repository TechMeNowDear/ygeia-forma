/// Τάσεις: σύγκριση ίσων περιόδων πάνω στις ημερήσιες συνόψεις.
///
/// Κανόνες ακρίβειας (έγγραφο › «Τάσεις και επόμενα»):
/// - Σύγκριση ίσων περιόδων με τη μεσαία τιμή (διάμεσο) κάθε περιόδου.
/// - Δεδομένα τουλάχιστον τις 2 στις 3 μέρες κάθε περιόδου (στο σώμα: τουλάχιστον 3 ζυγίσεις).
/// - «Άλλαξε» μόνο όταν η διαφορά ξεπερνά ένα ελάχιστο ΚΑΙ τις καθημερινές διακυμάνσεις.
///   Στατιστικός έλεγχος (από 1/11, μετά τον έλεγχο): t-test Welch με επίπεδο 1% (όχι 5%, γιατί
///   ελέγχονται πολλοί δείκτες μαζί), και με «πραγματικό» πλήθος ημερών: οι διαδοχικές μέρες
///   μοιάζουν μεταξύ τους (αυτοσυσχέτιση), άρα 30 μέρες δεν είναι 30 ανεξάρτητες μετρήσεις.
///   Από 4/11 (έλεγχος υπολογισμών F2–F4): αυτοσυσχέτιση σωστή και με κενά ή αραιές μετρήσεις, διόρθωση της
///   διακύμανσης, και «άλλαξε» μόνο όταν μέσος όρος και μεσαία τιμή δείχνουν προς την ίδια κατεύθυνση.
///   Προσομοίωση (test/trends_test.dart): ψεύτικο «άλλαξε» κατά προσέγγιση ≤ 1,5% ανά δείκτη, χωρίς καμία αλλαγή,
///   ΟΤΑΝ οι μέρες μοιάζουν μεταξύ τους όπως στο μοντέλο AR(1). Δεν ισχύει για όλες τις συνθήκες (δεύτερος έλεγχος
///   υπολογισμών C4): αργές μεταβολές εβδομάδων (εποχή, φυσική κατάσταση) δεν φαίνονται στο φ από κοντινές μέρες, και
///   στους 3 μήνες / στο έτος μπορεί να βγει «άλλαξε» για μια τέτοια αργή, πραγματική μεταβολή (προσομοίωση με δύο
///   κλίμακες: 12–22%). Είναι ένδειξη ανά δείκτη, όχι ιατρικός έλεγχος· με 16–19 δείκτες μαζί, κάποιος μπορεί να
///   βγει τυχαία.
library;

import 'dart:math' as math;

import 'format.dart';
import 'history.dart';
import 'sources.dart';

enum TrendSection { heart, sleep, body, move, other }

String sectionLabel(TrendSection s) => switch (s) {
      TrendSection.heart => 'Καρδιά',
      TrendSection.sleep => 'Ύπνος',
      TrendSection.body => 'Σώμα',
      TrendSection.move => 'Κίνηση',
      TrendSection.other => 'Ενέργεια και οξυγόνο',
    };

enum ValueKind { number, duration, clock }

class MetricDef {
  const MetricDef({
    required this.key,
    required this.label,
    required this.section,
    required this.minDiff,
    this.unit = '',
    this.digits = 0,
    this.better = 0,
    this.flagRiseOnly = false,
    this.kind = ValueKind.number,
    this.sparse = false,
    this.partial = false,
    this.includeToday = true,
  });

  final String key;
  final String label;
  final TrendSection section;

  /// Ελάχιστη διαφορά για να πούμε «άλλαξε».
  final double minDiff;
  final String unit;
  final int digits;

  /// 1 = καλύτερα όσο ανεβαίνει, −1 = καλύτερα όσο πέφτει, 0 = ουδέτερο.
  final int better;

  /// Μόνο η άνοδος έχει χρώμα «προσοχή»· η πτώση είναι ουδέτερη (παλμοί ύπνου: η πτώση δεν είναι πάντα
  /// καλό σημάδι, π.χ. φάρμακα ή διαταραχή αγωγής· κλινικός έλεγχος M4, 4/11).
  final bool flagRiseOnly;
  final ValueKind kind;

  /// Αραιές μετρήσεις (ζυγίσεις): αρκούν 3 τιμές ανά περίοδο.
  final bool sparse;

  /// Τιμή μόνο κάποιες μέρες (βαθμολογία ύπνου: μόνο νύχτες που η Samsung δεν χώρισε σε κομμάτια):
  /// αρκεί το 1/3 των ημερών κάθε περιόδου.
  final bool partial;

  /// Πόσες τιμές χρειάζεται ένα διάστημα [len] ημερών.
  int neededFor(int len) => sparse ? 3 : partial ? (len / 3).ceil() : (len * 2 / 3).ceil();

  /// Αν η σημερινή τιμή είναι ήδη τελική (ο ύπνος του πρωινού ναι, τα βήματα της μέρας όχι).
  final bool includeToday;

  String format(double v) => switch (kind) {
        ValueKind.duration => hoursMinutes(v.round()),
        ValueKind.clock => clockFromSix(v),
        ValueKind.number => _num(v),
      };

  /// Η τιμή όπως τη λέει η πηγή της: η θερμοκρασία του Oura είναι απόκλιση, με πρόσημο («+0,3 °C»).
  String formatAs(double v, Source s) =>
      s == Source.oura && key == K.skinTemp ? '${signedDec(v, digits)} $unit' : format(v);

  String _num(double v) {
    final n = digits == 0 && v.abs() >= 1000 ? thousands(v.round()) : dec(v, digits);
    if (unit.isEmpty) return n;
    return unit == '%' ? '$n%' : '$n $unit';
  }

  String formatDiff(double d) => switch (kind) {
        ValueKind.duration => hoursMinutes(d.abs().round()),
        ValueKind.clock => hoursMinutes(d.abs().round()),
        // Διαφορά ποσοστών: σε μονάδες («↓6 μονάδες»), ώστε να μη διαβάζεται ως σχετική πτώση 6%.
        ValueKind.number when unit == '%' => '${dec(d.abs(), digits)} ${d.abs() == 1 ? 'μονάδα' : 'μονάδες'}',
        ValueKind.number => _num(d.abs()),
      };

  /// Η τιμή όπως φαίνεται στην οθόνη (στρογγυλεμένη), ώστε η διαφορά να συμφωνεί με τα δύο νούμερα.
  double rounded(double v) => switch (kind) {
        ValueKind.duration || ValueKind.clock => v.roundToDouble(),
        ValueKind.number => digits == 0 ? v.roundToDouble() : double.parse(v.toStringAsFixed(digits)),
      };
}

const trendMetrics = <MetricDef>[
  // Καρδιά
  MetricDef(key: K.sleepHr, label: 'Παλμοί στον ύπνο', section: TrendSection.heart, minDiff: 2, unit: 'bpm', flagRiseOnly: true),
  // «Ξύπνιος, χωρίς βήματα» και «Παλμοί στο περπάτημα» βγήκαν (2/11): δικοί μας ορισμοί, χωρίς επαλήθευση.
  // Η ηρεμία θα έρθει από το Oura (παλμοί ύπνου του δαχτυλιδιού).
  // Ουδέτερο: μεγαλύτερος μέσος όρος ημέρας συνήθως σημαίνει περισσότερη κίνηση, όχι χειρότερη υγεία.
  MetricDef(key: K.dayHr, label: 'Μέσος όρος ημέρας', section: TrendSection.heart, minDiff: 2, unit: 'bpm', includeToday: false),
  // Ύπνος
  MetricDef(key: K.sleepMin, label: 'Διάρκεια ύπνου', section: TrendSection.sleep, minDiff: 15, better: 1, kind: ValueKind.duration),
  MetricDef(key: K.sleepScore, label: 'Βαθμολογία ύπνου', section: TrendSection.sleep, minDiff: 3, better: 1, partial: true),
  // Βαθύς ύπνος και ξύπνιος: ουδέτερο χρώμα (κλινικός έλεγχος M3, 4/11). Οι συσκευές χάνουν τα μισά ξυπνήματα και
  // υπερεκτιμούν τον βαθύ ύπνο· μια ενημέρωση λογισμικού θα έβγαζε ψεύτικη «βελτίωση».
  MetricDef(key: K.deepPct, label: 'Βαθύς ύπνος', section: TrendSection.sleep, minDiff: 2, unit: '%'),
  // REM: ουδέτερο χρώμα· επηρεάζεται από φάρμακα (π.χ. αντικαταθλιπτικά), όχι μόνο από την ποιότητα του ύπνου.
  MetricDef(key: K.remPct, label: 'REM', section: TrendSection.sleep, minDiff: 2, unit: '%'),
  MetricDef(key: K.awakeMin, label: 'Ξύπνιος μέσα στη νύχτα', section: TrendSection.sleep, minDiff: 5, kind: ValueKind.duration),
  MetricDef(key: K.bedtime, label: 'Ώρα ύπνου', section: TrendSection.sleep, minDiff: 15, kind: ValueKind.clock),
  // Σώμα
  MetricDef(key: K.weight, label: 'Βάρος', section: TrendSection.body, minDiff: 0.5, unit: 'kg', digits: 1, sparse: true),
  MetricDef(key: K.fatPct, label: 'Λίπος', section: TrendSection.body, minDiff: 0.5, unit: '%', digits: 1, better: -1, sparse: true),
  MetricDef(key: K.smm, label: 'Σκελετικοί μύες', section: TrendSection.body, minDiff: 0.3, unit: 'kg', digits: 1, better: 1, sparse: true),
  MetricDef(key: K.skinTemp, label: 'Θερμοκρασία καρπού στον ύπνο', section: TrendSection.sleep, minDiff: 0.2, unit: '°C', digits: 1),
  // Κίνηση
  MetricDef(key: K.steps, label: 'Βήματα', section: TrendSection.move, minDiff: 500, better: 1, includeToday: false),
  MetricDef(key: K.activeMin, label: 'Ενεργός χρόνος', section: TrendSection.move, minDiff: 5, better: 1, kind: ValueKind.duration, includeToday: false),
  // Άλλα
  MetricDef(key: K.energy, label: 'Energy Score', section: TrendSection.other, minDiff: 3, better: 1),
  // Οξυγόνο: ουδέτερο χρώμα (δεύτερος κλινικός έλεγχος M8). Μια διαφορά 1–2% είναι μέσα στο λάθος του καρπού
  // (RMSE ~2%), και αν κόψεις το κάπνισμα η ένδειξη πέφτει (λιγότερη καρβοξυαιμοσφαιρίνη): δεν είναι «χειρότερα».
  MetricDef(key: K.spo2Avg, label: 'Οξυγόνο στον ύπνο', section: TrendSection.other, minDiff: 1, unit: '%'),
];

/// Μετρήσεις που υπάρχουν μόνο με το Oura.
const ouraTrendMetrics = <MetricDef>[
  // HRV: ουδέτερο χρώμα· ανεβαίνει και με φάρμακα ή ακανόνιστο ρυθμό, όχι μόνο με την ξεκούραση (κλινικός έλεγχος H5).
  MetricDef(key: K.hrv, label: 'HRV νύχτας (RMSSD)', section: TrendSection.heart, minDiff: 3, unit: 'ms'),
  MetricDef(key: K.lowHr, label: 'Χαμηλότεροι παλμοί στον ύπνο', section: TrendSection.heart, minDiff: 2, unit: 'bpm'),
  MetricDef(key: K.breath, label: 'Αναπνοές στον ύπνο', section: TrendSection.other, minDiff: 0.5, unit: 'το λεπτό', digits: 1),
];

/// Ο ορισμός μιας μέτρησης (και όσων υπάρχουν μόνο με το Oura).
MetricDef? metricDef(String key) {
  for (final m in [...trendMetrics, ...ouraTrendMetrics]) {
    if (m.key == key) return m;
  }
  return null;
}

/// Το όνομα μιας μέτρησης όπως το λέει η πηγή της (π.χ. «Energy Score» → «Ετοιμότητα (εκτίμηση του Oura)»).
String metricLabel(MetricDef def, Source s) {
  // Ρολόι: οι βαθμολογίες και τα στάδια είναι εκτιμήσεις της Samsung, όπως και του Oura (κλινικός έλεγχος M2, 4/11).
  if (s != Source.oura) {
    return switch (def.key) {
      K.sleepScore => 'Βαθμολογία ύπνου (εκτίμηση της Samsung)',
      K.energy => 'Energy Score (εκτίμηση της Samsung)',
      K.deepPct => 'Βαθύς ύπνος (εκτίμηση)',
      K.remPct => 'REM (εκτίμηση)',
      K.awakeMin => 'Ξύπνιος μέσα στη νύχτα (τουλάχιστον)',
      _ => def.label,
    };
  }
  return switch (def.key) {
    K.energy => 'Ετοιμότητα (εκτίμηση του Oura)',
    K.sleepScore => 'Βαθμολογία ύπνου (εκτίμηση του Oura)',
    K.skinTemp => 'Θερμοκρασία δέρματος, απόκλιση',
    K.deepPct => 'Βαθύς ύπνος (εκτίμηση του Oura)',
    K.remPct => 'REM (εκτίμηση του Oura)',
    K.awakeMin => 'Ξύπνιος μέσα στη νύχτα (τουλάχιστον)',
    _ => def.label,
  };
}

/// [sourceChange]: η πηγή της μέτρησης άλλαξε μέσα στα διαστήματα της σύγκρισης· δεν συγκρίνεται.
enum TrendStatus { up, down, stable, insufficient, sourceChange }

class TrendResult {
  TrendResult({
    required this.def,
    required this.status,
    required this.current,
    required this.previous,
    required this.nCurrent,
    required this.nPrevious,
    required this.needed,
    required this.z,
    required this.points,
    required this.currentFrom,
    required this.previousFrom,
    required this.previousEnd,
    required this.end,
    this.source = Source.watch,
    this.changedOn,
    this.rereading = false,
    this.effectiveCurrent,
    this.tCritical,
  });

  /// Έλεγχος 2, C4: η «αλλαγή» είναι το όριο της επανανάγνωσης του ιστορικού με νέους κανόνες, όχι αλλαγή πηγής:
  /// «Ενημερώνεται το ιστορικό».
  final bool rereading;

  /// «Πραγματικό» πλήθος ανεξάρτητων ημερών του τρέχοντος διαστήματος και η κρίσιμη τιμή του ελέγχου (null όταν δεν
  /// έγινε έλεγχος). Για την εβδομάδα (δεύτερος έλεγχος υπολογισμών C1): με 7 μέρες που μοιάζουν πολύ μεταξύ τους
  /// μένουν ~2 «πραγματικές», και ο έλεγχος σχεδόν ποτέ δεν λέει «άλλαξε», ακόμα και για +5 bpm.
  final double? effectiveCurrent;
  final double? tCritical;

  /// «Σταθερό» που δεν σημαίνει τίποτα: πολύ λίγες ανεξάρτητες μέρες για να φανεί αλλαγή. Λέγεται «Λίγες μέρες για
  /// συμπέρασμα», όχι «Σταθερό» (που διαβάζεται σαν «χωράει στις διακυμάνσεις σου»).
  bool get inconclusive =>
      status == TrendStatus.stable &&
      ((effectiveCurrent != null && effectiveCurrent! < minEffectiveDays) || (tCritical != null && tCritical! > maxTCritical));

  /// Από πού είναι οι τιμές (η πηγή του τρέχοντος διαστήματος).
  final Source source;

  /// Η μέρα που άλλαξε πηγή μέσα στη σύγκριση (μόνο με [TrendStatus.sourceChange]).
  final DateTime? changedOn;

  final MetricDef def;
  final TrendStatus status;
  final double? current;
  final double? previous;
  final int nCurrent;
  final int nPrevious;

  /// Πόσες τιμές χρειάζεται κάθε περίοδος.
  final int needed;
  final double z;

  /// Όλες οι τιμές των δύο περιόδων (για γράφημα), παλιότερη πρώτη.
  final List<(DateTime, double)> points;
  final DateTime currentFrom;
  final DateTime previousFrom;
  final DateTime previousEnd;
  final DateTime end;

  bool get changed => status == TrendStatus.up || status == TrendStatus.down;
  double? get diff => (current != null && previous != null) ? current! - previous! : null;

  /// Η διαφορά των δύο τιμών όπως φαίνονται (στρογγυλεμένες): «63 → 60» δίνει πάντα «3».
  double? get displayDiff =>
      (current != null && previous != null) ? def.rounded(current!) - def.rounded(previous!) : null;

  /// Καλό (1), κακό (−1) ή ουδέτερο (0).
  int get goodness {
    if (!changed) return 0;
    final up = status == TrendStatus.up;
    if (def.flagRiseOnly) return up ? -1 : 0;
    if (def.better == 0) return 0;
    return (up ? 1 : -1) * def.better;
  }
}

/// Κάτω από τόσες «πραγματικές» μέρες, ή πάνω από τόση κρίσιμη τιμή (βαθμοί ελευθερίας < 5), ένα «Σταθερό» δεν λέει
/// τίποτα ([TrendResult.inconclusive]).
const minEffectiveDays = 4.0;
const maxTCritical = 4.1;

/// Περίοδος: πόσες μέρες, και πόσες μέρες πίσω αρχίζει η προηγούμενη για σύγκριση.
enum TrendPeriod { month, quarter, year }

String periodLabel(TrendPeriod p) => switch (p) {
      TrendPeriod.month => 'Μήνας',
      TrendPeriod.quarter => '3 μήνες',
      TrendPeriod.year => 'Χρόνος',
    };

/// Πώς συγκρίνει κάθε περίοδος, σε απλά ελληνικά.
String periodExplanation(TrendPeriod p) => switch (p) {
      TrendPeriod.month => 'τις τελευταίες 30 μέρες με τις 30 πριν',
      TrendPeriod.quarter => 'τους τελευταίους 3 μήνες με τους 3 πριν',
      TrendPeriod.year => 'τους τελευταίους 3 μήνες με τους ίδιους μήνες πέρσι',
    };

double? median(List<double> v) {
  if (v.isEmpty) return null;
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

double _mean(List<double> v) => v.reduce((a, b) => a + b) / v.length;

/// Πόσες μέρες το πολύ απέχουν δύο γειτονικές τιμές για να μετρήσουν στην αυτοσυσχέτιση.
const _maxCorrelationGap = 7;

/// Το πολύ τόση αυτοσυσχέτιση (πάνω από αυτήν, τα 30 «πραγματικά» δεδομένα γίνονται < 1).
const _maxCorrelation = 0.95;

/// Όταν δεν βγαίνει εκτίμηση (π.χ. ζυγίσεις κάθε 10 μέρες): συντηρητικά, σαν οι μέρες να μοιάζουν πολύ.
const _fallbackCorrelation = 0.9;

/// Κάτω από τόσες τιμές ανά κομμάτι 30 ημερών (κατά μέσο όρο) ο μέσος όρος κάθε κομματιού είναι πολύ θορυβώδης για
/// το φ ([_correlationFor]).
const _minBlockPoints = 8;

/// Αυτοσυσχέτιση από μέρα σε μέρα (φ, μοντέλο AR(1): δύο τιμές που απέχουν g μέρες έχουν συσχέτιση φ^g).
///
/// Διόρθωση μετά τον έλεγχο 4/11 (έλεγχος υπολογισμών F2, F4):
/// - Ο μέσος όρος των γινομένων είναι ανά ζευγάρι και η διακύμανση ανά τιμή (πριν, οι μέρες που έλειπαν
///   «μίκραιναν» το φ, και το «άλλαξε» έβγαινε στο 4–10% χωρίς καμία αλλαγή αντί για 1%).
/// - Μετρούν και γειτονικές τιμές που απέχουν ως 7 μέρες (αραιές ζυγίσεις: πριν, φ = 0, σαν να ήταν ανεξάρτητες).
///   Το φ βγαίνει με ελάχιστα τετράγωνα πάνω στο φ^g (βήμα 0,01).
/// - Διόρθωση της γνωστής υποεκτίμησης σε μικρά δείγματα (Kendall/Marriott–Pope): φ + (1 + 4φ)/n.
/// - Στο [0, 0,95]. null = λιγότερα από 6 ζευγάρια (δεν βγαίνει εκτίμηση).
/// [blocks]: κομμάτια με τον δικό τους μέσο όρο (π.χ. 30 ημερών), ώστε μια πραγματική αλλαγή επιπέδου να μη
/// μοιάζει με συσχέτιση· παλιότερη τιμή πρώτη μέσα σε κάθε κομμάτι.
double? dailyCorrelation(List<List<(DateTime, double)>> blocks) {
  final products = <double>[];
  final gaps = <int>[];
  var den = 0.0;
  var points = 0;
  var used = 0;
  for (final w in blocks) {
    if (w.length < 2) continue;
    final m = _mean([for (final e in w) e.$2]);
    for (final e in w) {
      den += (e.$2 - m) * (e.$2 - m);
    }
    points += w.length;
    used++;
    for (var i = 1; i < w.length; i++) {
      final g = daysBetween(w[i - 1].$1, w[i].$1);
      if (g >= 1 && g <= _maxCorrelationGap) {
        products.add((w[i - 1].$2 - m) * (w[i].$2 - m));
        gaps.add(g);
      }
    }
  }
  if (products.length < 6 || den <= 0) return null;
  final variance = den / points;
  final c = [for (final x in products) x / variance];
  var best = 0.0;
  var bestErr = double.infinity;
  for (var k = 0; k <= (_maxCorrelation * 100).round(); k++) {
    final f = k / 100;
    final pow = [1.0];
    for (var g = 1; g <= _maxCorrelationGap; g++) {
      pow.add(pow.last * f);
    }
    var err = 0.0;
    for (var i = 0; i < c.length; i++) {
      final d = c[i] - pow[gaps[i]];
      err += d * d;
    }
    if (err < bestErr) {
      bestErr = err;
      best = f;
    }
  }
  final n = points / used;
  return (best + (1 + 4 * best) / n).clamp(0.0, _maxCorrelation);
}

/// «Πραγματικό» πλήθος ανεξάρτητων τιμών για τις μέρες [days] με αυτοσυσχέτιση [phi] (AR(1)):
/// n² / Σᵢ Σⱼ φ^|tᵢ − tⱼ|. Λαμβάνει υπόψη τα κενά: δύο τιμές που απέχουν 2 μέρες μοιάζουν λιγότερο από δύο
/// διαδοχικές. Με φ = 0 δίνει n.
double effectiveN(List<DateTime> days, double phi) {
  final n = days.length;
  if (n == 0) return 0;
  if (phi <= 0) return n.toDouble();
  final t = [for (final d in days) daysBetween(days.first, d)];
  final span = t.reduce(math.max) - t.reduce(math.min);
  final pow = List<double>.filled(span + 1, 0);
  pow[0] = 1;
  for (var g = 1; g < pow.length; g++) {
    pow[g] = pow[g - 1] * phi;
  }
  var s = 0.0;
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      s += pow[(t[i] - t[j]).abs()];
    }
  }
  return n * n / s;
}

/// Κρίσιμη τιμή t για έλεγχο δύο πλευρών στο 1%. Για βαθμούς ελευθερίας ανάμεσα στις τιμές του
/// πίνακα παίρνουμε την προηγούμενη (μεγαλύτερη) τιμή: λίγο αυστηρότερα, ποτέ πιο χαλαρά.
double tCritical01(double df) {
  const table = <(double, double)>[
    (1, 63.657), (2, 9.925), (3, 5.841), (4, 4.604), (5, 4.032), (6, 3.707), (7, 3.499), (8, 3.355),
    (9, 3.250), (10, 3.169), (12, 3.055), (15, 2.947), (20, 2.845), (25, 2.787), (30, 2.750),
    (40, 2.704), (60, 2.660), (120, 2.617),
  ];
  if (df.isNaN || df < 1) return table.first.$2;
  var crit = table.first.$2;
  for (final (d, t) in table) {
    if (df >= d) crit = t;
  }
  return df >= 1000 ? 2.576 : crit;
}

double _variance(List<double> v) {
  if (v.length < 2) return 0;
  final m = _mean(v);
  return v.fold<double>(0, (s, x) => s + (x - m) * (x - m)) / (v.length - 1);
}

TrendResult computeTrend(
  MetricDef def,
  Map<String, Map<String, double>> history,
  DateTime today,
  TrendPeriod period, {
  SourcePlan? plan,
}) {
  final end = def.includeToday ? dayOf(today) : _add(dayOf(today), -1);
  final len = period == TrendPeriod.month ? 30 : 90;
  final currentFrom = _add(end, -(len - 1));
  // Χρόνος: οι ίδιοι μήνες πέρσι (ίδια εποχή), όχι μήνες με άλλο καιρό και άλλη μέρα/νύχτα.
  final previousEnd = period == TrendPeriod.year ? _add(end, -364) : _add(currentFrom, -1);
  final previousFrom = _add(previousEnd, -(len - 1));
  return compareWindows(
    def,
    history,
    currentFrom: currentFrom,
    end: end,
    previousFrom: previousFrom,
    previousEnd: previousEnd,
    needed: def.neededFor(len),
    plan: plan,
  );
}

DateTime _add(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// Σύγκριση δύο διαστημάτων (με τις άκρες), με τους κανόνες των Τάσεων.
/// [needed]: πόσες τιμές χρειάζεται κάθε διάστημα.
TrendResult compareWindows(
  MetricDef def,
  Map<String, Map<String, double>> history, {
  required DateTime currentFrom,
  required DateTime end,
  required DateTime previousFrom,
  required DateTime previousEnd,
  required int needed,
  int? neededPrevious,
  SourcePlan? plan,
}) {
  final sp = plan ?? SourcePlan.samsungOnly;
  // Κάθε τιμή ΜΟΝΟ από την πηγή της εκείνη τη μέρα (ένα κλειδί ανά μέρα, δες sources.dart).
  List<(DateTime, double)> collect(DateTime from, DateTime to) {
    final out = <(DateTime, double)>[];
    for (var d = from; !d.isAfter(to); d = _add(d, 1)) {
      final v = sp.value(history, def.key, d);
      if (v != null) out.add((d, v));
    }
    return out;
  }

  // Η σύγκριση δεν περνά ποτέ πάνω από αλλαγή πηγής: αν η πηγή άλλαξε από την αρχή του παλιότερου
  // διαστήματος ως το τέλος του νεότερου, δεν συγκρίνεται. Το γράφημα δείχνει μόνο τη νέα πηγή.
  final earliest = previousFrom.isBefore(currentFrom) ? previousFrom : currentFrom;
  final change = sp.changeWithin(def.key, earliest, end);
  if (change != null) {
    final pts = collect(change, end);
    final c = [for (final e in pts) if (!e.$1.isBefore(currentFrom)) e.$2];
    return TrendResult(
      def: def,
      status: TrendStatus.sourceChange,
      current: median(c),
      previous: null,
      nCurrent: c.length,
      nPrevious: 0,
      needed: needed,
      z: 0,
      points: pts,
      currentFrom: currentFrom,
      previousFrom: previousFrom,
      previousEnd: previousEnd,
      end: end,
      source: sp.sourceFor(def.key, end),
      changedOn: change,
      rereading: sp.isRulesChange(change),
    );
  }

  var cw = collect(currentFrom, end);
  var pw = collect(previousFrom, previousEnd);
  var points = collect(previousFrom.isBefore(currentFrom) ? previousFrom : currentFrom, end);
  // Ώρες (π.χ. ώρα ύπνου): γύρω από τον «κυκλικό» μέσο όρο, ώστε τιμές εκατέρωθεν των 18:00 να μη
  // δίνουν μέσο όρο 12 ώρες μακριά (έλεγχος υπολογισμών F13). Στις συνηθισμένες ώρες δεν αλλάζει τίποτα.
  if (def.kind == ValueKind.clock && points.isNotEmpty) {
    final center = circularMeanMinutes([for (final e in points) e.$2]);
    List<(DateTime, double)> unwrap(List<(DateTime, double)> v) => [for (final e in v) (e.$1, unwrapMinutes(e.$2, center))];
    cw = unwrap(cw);
    pw = unwrap(pw);
    points = unwrap(points);
  }
  final c = cw.map((e) => e.$2).toList();
  final p = pw.map((e) => e.$2).toList();
  final mc = median(c);
  final mp = median(p);

  TrendStatus status;
  var z = 0.0;
  double? effCurrent;
  double? tCrit;
  if (c.length < needed || p.length < (neededPrevious ?? needed) || mc == null || mp == null) {
    status = TrendStatus.insufficient;
  } else {
    // Πραγματικό πλήθος ανεξάρτητων τιμών, με την αυτοσυσχέτιση από έως 180 μέρες της ίδιας πηγής
    // (έλεγχος υπολογισμών F2/F4, 4/11): το φ από δύο μόνο διαστήματα ήταν πολύ θορυβώδες.
    final r = _correlationFor(def, sp, collect, end: end, previousFrom: previousFrom, previousEnd: previousEnd);
    final nc = math.max(2.0, effectiveN([for (final e in cw) e.$1], r));
    final np = math.max(2.0, effectiveN([for (final e in pw) e.$1], r));
    // Με αυτοσυσχέτιση η διακύμανση του δείγματος βγαίνει μικρότερη από την πραγματική:
    // E[s²] = σ² (n − n/n_eff) / (n − 1). Διορθώνεται, αλλιώς ο έλεγχος είναι πιο χαλαρός απ' όσο λέει.
    double corrected(List<double> v, double ne) {
      final k = v.length - v.length / ne;
      return k > 0 ? _variance(v) * (v.length - 1) / k : _variance(v);
    }

    final vc = corrected(c, nc) / nc, vp = corrected(p, np) / np;
    final se = math.sqrt(vc + vp);
    final meanDiff = _mean(c) - _mean(p);
    z = se == 0 ? (meanDiff != 0 ? double.infinity : 0) : meanDiff.abs() / se;
    // Βαθμοί ελευθερίας Welch–Satterthwaite.
    final df = (vc + vp) == 0 ? 1000.0 : math.pow(vc + vp, 2) / (vc * vc / (nc - 1) + vp * vp / (np - 1));
    final d = mc - mp;
    // Ο έλεγχος είναι στους μέσους όρους, η τιμή που φαίνεται είναι η μεσαία: «άλλαξε» μόνο όταν δείχνουν
    // προς την ίδια κατεύθυνση (έλεγχος υπολογισμών F3).
    final agree = d.sign == meanDiff.sign;
    effCurrent = nc;
    tCrit = tCritical01(df.toDouble());
    if (d.abs() >= def.minDiff && agree && z >= tCrit) {
      status = d > 0 ? TrendStatus.up : TrendStatus.down;
    } else {
      status = TrendStatus.stable;
    }
  }

  return TrendResult(
    def: def,
    status: status,
    current: mc,
    previous: mp,
    nCurrent: c.length,
    nPrevious: p.length,
    needed: needed,
    z: z,
    points: points,
    currentFrom: currentFrom,
    previousFrom: previousFrom,
    previousEnd: previousEnd,
    end: end,
    source: sp.sourceFor(def.key, end),
    effectiveCurrent: effCurrent,
    tCritical: tCrit,
  );
}

/// Η αυτοσυσχέτιση μιας μέτρησης: από κομμάτια 30 ημερών (το καθένα με τον δικό του μέσο όρο) στις 180 μέρες
/// ως το [end], και στο προηγούμενο διάστημα αν είναι πιο πίσω (σύγκριση με πέρσι). Μόνο από την ίδια πηγή
/// (μετά την τελευταία αλλαγή πηγής). Χωρίς αρκετά ζευγάρια: συντηρητική τιμή.
double _correlationFor(
  MetricDef def,
  SourcePlan sp,
  List<(DateTime, double)> Function(DateTime, DateTime) collect, {
  required DateTime end,
  required DateTime previousFrom,
  required DateTime previousEnd,
}) {
  final seg = sp.segmentStart(def.key, end);
  final window = daysBetween(previousFrom, previousEnd) + 1;
  List<List<(DateTime, double)>> blocksOf(int size) {
    final blocks = <List<(DateTime, double)>>[];
    void add(DateTime last, int count) {
      for (var b = 0; b < count; b++) {
        final to = _add(last, -size * b);
        if (seg != null && to.isBefore(seg)) break;
        final from = _add(to, -(size - 1));
        blocks.add(collect(seg != null && from.isBefore(seg) ? seg : from, to));
      }
    }

    add(end, 180 ~/ size);
    if (previousEnd.isBefore(_add(end, -179))) add(previousEnd, math.max(1, window ~/ size));
    return blocks;
  }

  var blocks = blocksOf(30);
  // Έλεγχος 4 (2_calcs M1): αραιές τιμές (π.χ. ζύγιση μία φορά την εβδομάδα, ~4 ανά 30 μέρες). Ο μέσος όρος κάθε
  // κομματιού 30 ημερών έριχνε το φ (0,95 → ~0,24) και το «Βάρος άλλαξε» έβγαινε ψεύτικα στο ~10–15% των τριμήνων. Στο
  // τρίμηνο και στον χρόνο τα κομμάτια γίνονται όσο το διάστημα της σύγκρισης (90 μέρες, ~13 ζυγίσεις, ένας μέσος όρος
  // στο καθένα· η πραγματική αλλαγή ανάμεσα στα δύο διαστήματα δεν μετρά ως συσχέτιση). Στον μήνα μένουν 30 μέρες: με
  // 4 + 4 ζυγίσεις ένα συντηρητικό φ δεν θα έδειχνε ούτε καθαρή αλλαγή 2 kg (γνωστό όριο, ~2,5% ψεύτικα «άλλαξε»).
  final full = blocks.where((w) => w.length >= 2).toList();
  final points = full.fold<int>(0, (n, w) => n + w.length);
  if (window > 30 && full.isNotEmpty && points < _minBlockPoints * full.length) blocks = blocksOf(window);
  return dailyCorrelation(blocks) ?? _fallbackCorrelation;
}

/// Κυκλικός μέσος όρος λεπτών μέσα στο 24ωρο (0–1439), π.χ. 23:50 και 00:10 → 00:00.
double circularMeanMinutes(List<double> minutes) {
  var x = 0.0, y = 0.0;
  for (final m in minutes) {
    final a = 2 * math.pi * m / 1440;
    x += math.cos(a);
    y += math.sin(a);
  }
  if (x == 0 && y == 0) return minutes.isEmpty ? 0 : minutes.first;
  final a = math.atan2(y, x);
  return ((a < 0 ? a + 2 * math.pi : a) * 1440 / (2 * math.pi)) % 1440;
}

/// Η τιμή [m] (λεπτά στο 24ωρο) μετακινημένη κατά ±1440 ώστε να απέχει το πολύ 12 ώρες από το [center].
/// (Μόνο ολόκληρες μέρες προστίθενται ή αφαιρούνται: η τιμή μένει ακριβώς ίδια όταν δεν χρειάζεται μετακίνηση.)
double unwrapMinutes(double m, double center) {
  var v = m;
  while (v - center >= 720) {
    v -= 1440;
  }
  while (v - center < -720) {
    v += 1440;
  }
  return v;
}

/// Το «συνήθως» μιας νύχτας ή μέρας, ΕΝΑ σε όλη την εφαρμογή (Σήμερα, Καρδιά, «Εκτός συνηθισμένου», Oura):
/// η μεσαία τιμή των έως [usualNights] προηγούμενων τιμών, μόνο με τουλάχιστον [usualMinNights] (έλεγχος υπολογισμών
/// F8, κλινικός M10· δεύτερος έλεγχος C7/U7: πριν, η ίδια λέξη σήμαινε μέσο όρο 14 νυχτών σε μια κάρτα και μεσαία
/// τιμή 28 ημερών σε άλλη, με άλλο νούμερο στην ίδια οθόνη). Μεσαία τιμή: μια περίεργη νύχτα δεν το μετακινεί.
const usualNights = 14;
const usualMinNights = 7;

/// [previous]: οι τιμές πριν από τη νύχτα/μέρα που δείχνουμε, παλιότερη πρώτη (τα κενά αγνοούνται).
double? usualOf(Iterable<double?> previous) {
  final all = previous.whereType<double>().toList();
  final v = all.length <= usualNights ? all : all.sublist(all.length - usualNights);
  if (v.length < usualMinNights) return null;
  return median(v);
}

/// Παλιό όνομα του [usualOf] (το χρησιμοποιεί το data.dart). Είναι η ΜΕΣΑΙΑ τιμή, όχι ο μέσος όρος.
double? usualMean(Iterable<double?> previous) => usualOf(previous);

/// Οι μετρήσεις των Τάσεων για το σχέδιο πηγών: όσο το Oura δεν έχει συνδεθεί, όπως πάντα· μετά, και
/// οι μετρήσεις που δίνει μόνο το Oura (HRV, αναπνοές, χαμηλότεροι παλμοί).
List<MetricDef> trendMetricsFor(SourcePlan plan) =>
    plan.hasOura ? [...trendMetrics, ...ouraTrendMetrics] : trendMetrics;

List<TrendResult> computeAllTrends(Map<String, Map<String, double>> history, DateTime today, TrendPeriod period,
        {SourcePlan? plan}) =>
    [for (final m in trendMetricsFor(plan ?? SourcePlan.samsungOnly)) computeTrend(m, history, today, period, plan: plan)];

/// Έλεγχος 2, C4: το κείμενο όσο το ιστορικό ξαναϋπολογίζεται με νέους κανόνες.
String rereadNote(DateTime from) =>
    'Ενημερώνεται το ιστορικό: οι μέρες πριν από τις ${from.day}/${from.month}/${from.year} υπολογίζονται ξανά με τους νέους '
    'κανόνες ύπνου. Ως τότε δεν συγκρίνω τιμές από πριν και μετά, ούτε στην αναφορά για τον γιατρό.';

/// Έλεγχος 2, C4: κομμάτια του ιστορικού που κράτησαν τον παλιό ορισμό (3 αποτυχίες ανάγνωσης).
String staleMonthsNote(List<String> keys) {
  final months = <String>{
    for (final k in keys)
      () {
        final p = k.split('-');
        return p.length == 3 ? '${int.tryParse(p[1]) ?? p[1]}/${p[0]}' : k;
      }(),
  }.toList();
  return 'Δεν ξαναϋπολογίστηκαν (η Samsung δεν τα έδωσε όλα): οι 30 μέρες ως ${months.join(', ')}. Κρατούν τον παλιό ορισμό '
      'του ύπνου (με τα ξυπνήματα).';
}
