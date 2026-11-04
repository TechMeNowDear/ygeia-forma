/// Αναφορά για γιατρό: τι μπαίνει και πώς υπολογίζεται. Μόνο από τις ημερήσιες συνόψεις
/// (ίδια νούμερα με την εφαρμογή). Οι πειραματικοί δείκτες (ηρεμία ξύπνιος) ΔΕΝ μπαίνουν.
library;

import 'dart:math' as math;

import 'format.dart';
import 'history.dart';
import 'sources.dart';
import 'trends.dart';

const reportDays = 90;

/// Στατιστικά ενός δείκτη στο διάστημα της αναφοράς.
class ReportStat {
  ReportStat({required this.values, this.trend, this.source = Source.watch, this.since, this.periods = const []});

  /// Οξυγόνο (ίδιος αισθητήρας, άλλος ορισμός νύχτας μετά το Oura): οι τιμές ΟΛΩΝ των 90 ημερών στο [values], και
  /// εδώ ένα κομμάτι για κάθε ορισμό της νύχτας, παλιότερο πρώτο (κενό αν ο ορισμός δεν άλλαξε μέσα στο διάστημα).
  final List<ReportPeriod> periods;

  /// Από ποια συσκευή είναι όλες οι τιμές (μία, πάντα).
  final Source source;

  /// Αν η πηγή άλλαξε μέσα στο διάστημα της αναφοράς: από πότε μετρούν οι τιμές (μόνο της νέας πηγής).
  final DateTime? since;

  /// (μέρα, τιμή), παλιότερη πρώτη.
  final List<(DateTime, double)> values;

  /// Σύγκριση με τους 3 προηγούμενους μήνες (αν υπάρχουν αρκετά δεδομένα).
  final TrendResult? trend;

  int get n => values.length;
  double? get median => n == 0 ? null : _quantile(0.5);
  double? get low => n == 0 ? null : values.map((e) => e.$2).reduce(math.min);
  double? get high => n == 0 ? null : values.map((e) => e.$2).reduce(math.max);

  /// Τυπικό εύρος: από το 10ο ως το 90ό εκατοστημόριο (οι 8 στις 10 μέρες).
  double? get p10 => n < 5 ? null : _quantile(0.1);
  double? get p90 => n < 5 ? null : _quantile(0.9);

  double _quantile(double q) {
    final s = values.map((e) => e.$2).toList()..sort();
    final pos = (s.length - 1) * q;
    final i = pos.floor();
    final f = pos - i;
    return i + 1 < s.length ? s[i] + (s[i + 1] - s[i]) * f : s[i];
  }
}

/// Ένα κομμάτι του διαστήματος με τον ίδιο ορισμό της νύχτας (μόνο για το οξυγόνο).
class ReportPeriod {
  ReportPeriod({required this.from, required this.to, required this.night, required this.stat});
  final DateTime from;
  final DateTime to;

  /// Από πού ορίζεται η νύχτα: ρολόι (ο ύπνος του ρολογιού) ή Oura (οι ώρες ύπνου του Oura).
  final Source night;
  final ReportStat stat;
}

/// Μετρήσεις του ίδιου αισθητήρα (ρολόι, καρπός) με ορισμό νύχτας που αλλάζει με την πηγή του ύπνου. Στην αναφορά
/// μπαίνουν ΟΛΕΣ οι 90 μέρες, με ετικέτα για κάθε ορισμό· ποτέ κομμένες στη σύνδεση του Oura (δεύτερος κλινικός
/// έλεγχος K1: οι νύχτες με 72% και 74% πριν από το Oura είναι ο λόγος της επίσκεψης). Η «Διαφορά» μένει «Αλλαγή
/// ορισμού»: δεν συγκρίνεται πάνω από την αλλαγή.
const reportSensorKeys = {K.spo2Avg, K.spo2Min};

class ReportData {
  ReportData({
    required this.from,
    required this.to,
    required this.created,
    required this.stats,
    required this.lowOxygenNights,
    required this.weighIns,
    this.plan,
  });

  /// Οι πηγές (για τη σημείωση «Πώς μετρήθηκαν»).
  final SourcePlan? plan;

  /// Οι τελευταίες ζυγίσεις (έως 6, όποτε κι αν έγιναν), η νεότερη πρώτη: (μέρα, βάρος, λίπος %, μύες).
  final List<(DateTime, double?, double?, double?)> weighIns;

  final DateTime from;
  final DateTime to;
  final DateTime created;

  /// Κλειδί (K.*) → στατιστικά.
  final Map<String, ReportStat> stats;

  /// Νύχτες με ελάχιστο οξυγόνο κάτω από 90%, (μέρα, ελάχιστο), με χρονολογική σειρά (δεύτερος κλινικός έλεγχος M4).
  final List<(DateTime, double)> lowOxygenNights;

  ReportStat stat(String key) => stats[key] ?? ReportStat(values: const []);

  /// Οι νύχτες με χαμηλότερη μέτρηση οξυγόνου κάτω από [limit]%, με χρονολογική σειρά (σύγκριση πριν από
  /// στρογγυλοποίηση: 84,6 μετρά ως κάτω από 85).
  List<(DateTime, double)> oxygenBelow(double limit) => [
        for (final v in stat(K.spo2Min).values)
          if (v.$2 < limit) v,
      ];

  /// Νύχτες χωρίς φάσεις: έχουν ώρα ύπνου αλλά όχι διάρκεια (η διάρκεια μετρά μόνο τον πραγματικό ύπνο από τις
  /// φάσεις). Γράφεται στην αναφορά (δεύτερος έλεγχος υπολογισμών C10).
  int get nightsWithoutStages => math.max(0, stat(K.bedtime).n - stat(K.sleepMin).n);
}

const reportKeys = [
  K.sleepHr,
  K.spo2Avg,
  K.spo2Min,
  K.sleepMin,
  K.bedtime,
  K.wake,
  K.steps,
  K.weight,
  K.fatPct,
  K.smm,
];

/// Μετά τη σύνδεση του Oura η αναφορά δείχνει και ό,τι δίνει μόνο αυτό.
List<String> reportKeysFor(SourcePlan plan) => plan.hasOura ? [...reportKeys, K.lowHr, K.hrv, K.breath] : reportKeys;

/// [end]: η τελευταία μέρα του διαστήματος, ίδια με τις Τάσεις από όπου ανοίγει η αναφορά (δεύτερος έλεγχος
/// υπολογισμών C12: μετά τα μεσάνυχτα, πριν από ανανέωση, οι Τάσεις τελείωναν χθες και η αναφορά σήμερα). Χωρίς
/// [end]: η μέρα του [now]. Το [now] είναι πάντα η ώρα δημιουργίας.
ReportData buildReport(Map<String, Map<String, double>> history, DateTime now, {SourcePlan? plan, DateTime? end}) {
  final p = plan ?? SourcePlan.samsungOnly;
  DateTime add(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
  final to = dayOf(end ?? now);
  final from = add(to, -(reportDays - 1));
  final stats = <String, ReportStat>{};

  for (final key in reportKeysFor(p)) {
    // Βήματα: η σημερινή μέρα δεν έχει τελειώσει.
    final last = key == K.steps ? add(to, -1) : to;
    // Πάντα 90 μέρες ως το [last], ίδιο διάστημα με τη «Διαφορά» της ίδιας γραμμής (έλεγχος υπολογισμών F11:
    // πριν, τα βήματα είχαν 89 μέρες στον πίνακα και 90 στη σύγκριση).
    final start = add(last, -(reportDays - 1));
    final def = metricDef(key);
    final trend = def == null ? null : computeTrend(def, history, to, TrendPeriod.quarter, plan: p);
    if (reportSensorKeys.contains(key)) {
      stats[key] = _sensorStat(history, p, key, start, last, trend);
      continue;
    }
    // Μόνο μία πηγή ανά δείκτη: αν άλλαξε μέσα στους 3 μήνες, μετρούν μόνο οι μέρες της νέας.
    final series = planSeries(history, p, key, start, last);
    stats[key] = ReportStat(values: series.points, trend: trend, source: series.source, since: series.cut);
  }

  // Χρονολογική σειρά (M4): ο γιατρός διαβάζει το μοτίβο και τη σχέση με φάρμακα και συμπτώματα.
  final low = [
    for (final v in stats[K.spo2Min]!.values)
      if (v.$2 < 90) v,
  ];

  final weighDays = history.keys.where((k) => p.value(history, K.weight, parseDateKey(k)) != null).toList()..sort();
  final weighIns = [
    for (final k in weighDays.reversed.take(6))
      (
        parseDateKey(k),
        p.value(history, K.weight, parseDateKey(k)),
        p.value(history, K.fatPct, parseDateKey(k)),
        p.value(history, K.smm, parseDateKey(k)),
      ),
  ];

  return ReportData(
    from: from,
    to: to,
    created: now,
    stats: stats,
    lowOxygenNights: low,
    weighIns: weighIns,
    plan: p,
  );
}

/// Οξυγόνο: όλες οι 90 μέρες του ρολογιού (ίδιος αισθητήρας), και ένα κομμάτι για κάθε ορισμό της νύχτας.
ReportStat _sensorStat(
  Map<String, Map<String, double>> history,
  SourcePlan p,
  String key,
  DateTime start,
  DateTime last,
  TrendResult? trend,
) {
  DateTime add(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
  final values = <(DateTime, double)>[];
  for (var d = start; !d.isAfter(last); d = add(d, 1)) {
    final v = p.value(history, key, d);
    if (v != null) values.add((d, v));
  }
  final cuts = [for (final c in p.changeDates(key)) if (c.isAfter(start) && !c.isAfter(last)) c];
  final periods = <ReportPeriod>[];
  if (cuts.isNotEmpty) {
    final bounds = [start, ...cuts, add(last, 1)];
    for (var i = 0; i + 1 < bounds.length; i++) {
      final from = bounds[i];
      final to = add(bounds[i + 1], -1);
      periods.add(ReportPeriod(
        from: from,
        to: to,
        night: p.nightSource(from) == Source.oura ? Source.oura : Source.watch,
        stat: ReportStat(values: [for (final v in values) if (!v.$1.isBefore(from) && !v.$1.isAfter(to)) v]),
      ));
    }
  }
  return ReportStat(values: values, trend: trend, source: p.sourceFor(key, last), periods: periods);
}
