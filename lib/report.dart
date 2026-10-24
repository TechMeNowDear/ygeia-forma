/// Αναφορά για γιατρό: τι μπαίνει και πώς υπολογίζεται. Μόνο από τις ημερήσιες συνόψεις
/// (ίδια νούμερα με την εφαρμογή). Οι πειραματικοί δείκτες (ηρεμία ξύπνιος) ΔΕΝ μπαίνουν.
library;

import 'dart:math' as math;

import 'format.dart';
import 'history.dart';
import 'trends.dart';

const reportDays = 90;

/// Στατιστικά ενός δείκτη στο διάστημα της αναφοράς.
class ReportStat {
  ReportStat({required this.values, this.trend});

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

class ReportData {
  ReportData({
    required this.from,
    required this.to,
    required this.created,
    required this.stats,
    required this.lowOxygenNights,
    required this.weighIns,
  });

  /// Οι τελευταίες ζυγίσεις (έως 8, όποτε κι αν έγιναν), η νεότερη πρώτη: (μέρα, βάρος, λίπος %, μύες).
  final List<(DateTime, double?, double?, double?)> weighIns;

  final DateTime from;
  final DateTime to;
  final DateTime created;

  /// Κλειδί (K.*) → στατιστικά.
  final Map<String, ReportStat> stats;

  /// Νύχτες με ελάχιστο οξυγόνο κάτω από 90%, (μέρα, ελάχιστο), η χαμηλότερη πρώτη.
  final List<(DateTime, double)> lowOxygenNights;

  ReportStat stat(String key) => stats[key] ?? ReportStat(values: const []);
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

ReportData buildReport(Map<String, Map<String, double>> history, DateTime now) {
  DateTime add(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
  final to = dayOf(now);
  final from = add(to, -(reportDays - 1));
  final stats = <String, ReportStat>{};

  for (final key in reportKeys) {
    // Βήματα: η σημερινή μέρα δεν έχει τελειώσει.
    final end = key == K.steps ? add(to, -1) : to;
    final values = <(DateTime, double)>[
      for (var d = from; !d.isAfter(end); d = add(d, 1))
        if (history[dateKey(d)]?[key] case final v?) (d, v),
    ];
    MetricDef? def;
    for (final m in trendMetrics) {
      if (m.key == key) def = m;
    }
    final trend = def == null ? null : computeTrend(def, history, now, TrendPeriod.quarter);
    stats[key] = ReportStat(values: values, trend: trend);
  }

  final low = [
    for (final v in stats[K.spo2Min]!.values)
      if (v.$2 < 90) v,
  ]..sort((a, b) => a.$2.compareTo(b.$2));

  final weighDays = history.keys.where((k) => history[k]![K.weight] != null).toList()..sort();
  final weighIns = [
    for (final k in weighDays.reversed.take(8))
      (parseDateKey(k), history[k]![K.weight], history[k]![K.fatPct], history[k]![K.smm]),
  ];

  return ReportData(
    from: from,
    to: to,
    created: now,
    stats: stats,
    lowOxygenNights: low,
    weighIns: weighIns,
  );
}
