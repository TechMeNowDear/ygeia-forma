/// Τάσεις: σύγκριση ίσων περιόδων πάνω στις ημερήσιες συνόψεις.
///
/// Κανόνες ακρίβειας (έγγραφο › «Τάσεις και επόμενα»):
/// - Σύγκριση ίσων περιόδων με τη μεσαία τιμή (διάμεσο) κάθε περιόδου.
/// - Δεδομένα τουλάχιστον τις 2 στις 3 μέρες κάθε περιόδου (στο σώμα: τουλάχιστον 3 ζυγίσεις).
/// - «Άλλαξε» μόνο όταν η διαφορά ξεπερνά ένα ελάχιστο ΚΑΙ τις καθημερινές διακυμάνσεις.
///   Στατιστικός έλεγχος (από 1/11, μετά τον έλεγχο): t-test Welch με επίπεδο 1% (όχι 5%, γιατί
///   ελέγχονται πολλοί δείκτες μαζί), και με «πραγματικό» πλήθος ημερών: οι διαδοχικές μέρες
///   μοιάζουν μεταξύ τους (αυτοσυσχέτιση), άρα 30 μέρες δεν είναι 30 ανεξάρτητες μετρήσεις.
library;

import 'dart:math' as math;

import 'format.dart';
import 'history.dart';

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
    this.kind = ValueKind.number,
    this.sparse = false,
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
  final ValueKind kind;

  /// Αραιές μετρήσεις (ζυγίσεις): αρκούν 3 τιμές ανά περίοδο.
  final bool sparse;

  /// Αν η σημερινή τιμή είναι ήδη τελική (ο ύπνος του πρωινού ναι, τα βήματα της μέρας όχι).
  final bool includeToday;

  String format(double v) => switch (kind) {
        ValueKind.duration => hoursMinutes(v.round()),
        ValueKind.clock => clockFromSix(v),
        ValueKind.number => _num(v),
      };

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
  MetricDef(key: K.sleepHr, label: 'Παλμοί στον ύπνο', section: TrendSection.heart, minDiff: 2, unit: 'bpm', better: -1),
  MetricDef(key: K.restHr, label: 'Ηρεμία, ξύπνιος', section: TrendSection.heart, minDiff: 2, unit: 'bpm', better: -1, includeToday: false),
  MetricDef(key: K.walkHr, label: 'Παλμοί στο περπάτημα', section: TrendSection.heart, minDiff: 3, unit: 'bpm', better: -1, includeToday: false),
  MetricDef(key: K.dayHr, label: 'Μέσος όρος ημέρας', section: TrendSection.heart, minDiff: 2, unit: 'bpm', better: -1, includeToday: false),
  // Ύπνος
  MetricDef(key: K.sleepMin, label: 'Διάρκεια ύπνου', section: TrendSection.sleep, minDiff: 15, better: 1, kind: ValueKind.duration),
  MetricDef(key: K.sleepScore, label: 'Βαθμολογία ύπνου', section: TrendSection.sleep, minDiff: 3, better: 1),
  MetricDef(key: K.deepPct, label: 'Βαθύς ύπνος', section: TrendSection.sleep, minDiff: 2, unit: '%', better: 1),
  MetricDef(key: K.remPct, label: 'REM', section: TrendSection.sleep, minDiff: 2, unit: '%', better: 1),
  MetricDef(key: K.awakeMin, label: 'Ξύπνιος μέσα στη νύχτα', section: TrendSection.sleep, minDiff: 5, better: -1, kind: ValueKind.duration),
  MetricDef(key: K.bedtime, label: 'Ώρα ύπνου', section: TrendSection.sleep, minDiff: 15, kind: ValueKind.clock),
  // Σώμα
  MetricDef(key: K.weight, label: 'Βάρος', section: TrendSection.body, minDiff: 0.5, unit: 'kg', digits: 1, sparse: true),
  MetricDef(key: K.fatPct, label: 'Λίπος', section: TrendSection.body, minDiff: 0.5, unit: '%', digits: 1, better: -1, sparse: true),
  MetricDef(key: K.smm, label: 'Σκελετικοί μύες', section: TrendSection.body, minDiff: 0.3, unit: 'kg', digits: 1, better: 1, sparse: true),
  MetricDef(key: K.skinTemp, label: 'Θερμοκρασία δέρματος', section: TrendSection.body, minDiff: 0.2, unit: '°C', digits: 1),
  // Κίνηση
  MetricDef(key: K.steps, label: 'Βήματα', section: TrendSection.move, minDiff: 500, better: 1, includeToday: false),
  MetricDef(key: K.activeMin, label: 'Ενεργός χρόνος', section: TrendSection.move, minDiff: 5, better: 1, kind: ValueKind.duration, includeToday: false),
  // Άλλα
  MetricDef(key: K.energy, label: 'Energy Score', section: TrendSection.other, minDiff: 3, better: 1),
  MetricDef(key: K.spo2Avg, label: 'Οξυγόνο στον ύπνο', section: TrendSection.other, minDiff: 1, unit: '%', better: 1),
];

enum TrendStatus { up, down, stable, insufficient }

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
  });

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
    if (!changed || def.better == 0) return 0;
    final up = status == TrendStatus.up;
    return (up ? 1 : -1) * def.better;
  }
}

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

/// Αυτοσυσχέτιση διαδοχικών ημερών (lag 1), από τα ζευγάρια συνεχόμενων ημερών των δύο περιόδων.
/// Στο [0, 0,8]· με λιγότερα από 6 ζευγάρια, 0,3 (συντηρητική τιμή για καθημερινές μετρήσεις).
double lagOneCorrelation(List<List<(DateTime, double)>> windows) {
  var num = 0.0, den = 0.0, pairs = 0;
  for (final w in windows) {
    if (w.length < 2) continue;
    final m = _mean([for (final e in w) e.$2]);
    for (final e in w) {
      den += (e.$2 - m) * (e.$2 - m);
    }
    for (var i = 1; i < w.length; i++) {
      final a = w[i - 1], b = w[i];
      if (daysBetween(a.$1, b.$1) == 1) {
        num += (a.$2 - m) * (b.$2 - m);
        pairs++;
      }
    }
  }
  if (pairs < 6 || den <= 0) return 0.3;
  return (num / den).clamp(0.0, 0.8);
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
  TrendPeriod period,
) {
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
    needed: def.sparse ? 3 : (len * 2 / 3).ceil(),
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
}) {
  List<(DateTime, double)> collect(DateTime from, DateTime to) {
    final out = <(DateTime, double)>[];
    for (var d = from; !d.isAfter(to); d = _add(d, 1)) {
      final v = history[dateKey(d)]?[def.key];
      if (v != null) out.add((d, v));
    }
    return out;
  }

  final cw = collect(currentFrom, end);
  final pw = collect(previousFrom, previousEnd);
  final c = cw.map((e) => e.$2).toList();
  final p = pw.map((e) => e.$2).toList();
  final points = collect(previousFrom.isBefore(currentFrom) ? previousFrom : currentFrom, end);
  final mc = median(c);
  final mp = median(p);

  TrendStatus status;
  var z = 0.0;
  if (c.length < needed || p.length < (neededPrevious ?? needed) || mc == null || mp == null) {
    status = TrendStatus.insufficient;
  } else {
    // Πραγματικό πλήθος ανεξάρτητων τιμών: n × (1 − r) / (1 + r).
    final r = lagOneCorrelation([cw, pw]);
    double eff(int n) => math.max(2, n * (1 - r) / (1 + r));
    final nc = eff(c.length), np = eff(p.length);
    final vc = _variance(c) / nc, vp = _variance(p) / np;
    final se = math.sqrt(vc + vp);
    final meanDiff = (_mean(c) - _mean(p)).abs();
    z = se == 0 ? (meanDiff > 0 ? double.infinity : 0) : meanDiff / se;
    // Βαθμοί ελευθερίας Welch–Satterthwaite.
    final df = (vc + vp) == 0 ? 1000.0 : math.pow(vc + vp, 2) / (vc * vc / (nc - 1) + vp * vp / (np - 1));
    final d = mc - mp;
    if (d.abs() >= def.minDiff && z >= tCritical01(df.toDouble())) {
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
  );
}

List<TrendResult> computeAllTrends(Map<String, Map<String, double>> history, DateTime today, TrendPeriod period) =>
    [for (final m in trendMetrics) computeTrend(m, history, today, period)];
