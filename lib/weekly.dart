/// Απολογισμός εβδομάδας: η εβδομάδα (Δευτέρα–Κυριακή) μπροστά στις 4 προηγούμενες.
/// Ίδιοι κανόνες με τις Τάσεις (διάμεσος, ελάχιστη διαφορά, στατιστικός έλεγχος).
library;

import 'format.dart';
import 'history.dart';
import 'sources.dart';
import 'trends.dart';

class WeekReview {
  WeekReview({
    required this.monday,
    required this.sunday,
    required this.items,
    this.bestNight,
    this.bestNightScore,
    this.mostSteps,
    this.mostStepsValue,
    this.activeTotal,
    this.activeDays = 0,
    this.weightFirst,
    this.weightLast,
  });

  final DateTime monday;
  final DateTime sunday;
  final List<TrendResult> items;

  final DateTime? bestNight;
  final double? bestNightScore;
  final DateTime? mostSteps;
  final double? mostStepsValue;

  /// Σύνολο ενεργού χρόνου στις ολοκληρωμένες μέρες.
  final double? activeTotal;
  final int activeDays;

  /// Πρώτη και τελευταία ζύγιση της εβδομάδας.
  final (DateTime, double)? weightFirst;
  final (DateTime, double)? weightLast;
}

const weekKeys = [K.sleepMin, K.bedtime, K.sleepScore, K.sleepHr, K.steps, K.activeMin, K.energy];

/// Πότε φαίνεται: Κυριακή από τις 18:00 και όλη τη Δευτέρα.
DateTime? reviewWeekSunday(DateTime now) {
  final today = dayOf(now);
  if (now.weekday == DateTime.sunday && now.hour >= 18) return today;
  if (now.weekday == DateTime.monday) return DateTime(today.year, today.month, today.day - 1);
  return null;
}

WeekReview buildWeekReview(Map<String, Map<String, double>> history, DateTime sunday, DateTime now, {SourcePlan? plan}) {
  final p = plan ?? SourcePlan.samsungOnly;
  DateTime add(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
  final monday = add(sunday, -6);
  final today = dayOf(now);

  final items = <TrendResult>[];
  for (final key in weekKeys) {
    final def = trendMetrics.firstWhere((m) => m.key == key);
    // Μέρα που δεν έχει τελειώσει (Κυριακή βράδυ) δεν μετρά για βήματα, ενεργό χρόνο, παλμούς ημέρας.
    final end = (!def.includeToday && !sunday.isBefore(today)) ? add(sunday, -1) : sunday;
    final len = daysBetween(monday, end) + 1;
    items.add(compareWindows(
      def,
      history,
      currentFrom: monday,
      end: end,
      previousFrom: add(monday, -28),
      previousEnd: add(monday, -1),
      needed: def.neededFor(len),
      neededPrevious: def.neededFor(28), // 19 από τις 28 (10 για τη βαθμολογία ύπνου)
      plan: p,
    ));
  }

  DateTime? bestNight;
  double? bestScore;
  DateTime? mostSteps;
  double? mostStepsValue;
  double? active;
  var activeDays = 0;
  (DateTime, double)? wFirst;
  (DateTime, double)? wLast;

  // «Καλύτερη βαθμολογία»: μόνο αν όλη η εβδομάδα έχει την ίδια πηγή βαθμολογίας (ποτέ Samsung δίπλα σε Oura).
  final scoreMixed = p.changeWithin(K.sleepScore, monday, sunday) != null;
  for (var d = monday; !d.isAfter(sunday); d = add(d, 1)) {
    final row = history[dateKey(d)];
    if (row == null) continue;
    final complete = d.isBefore(today);
    final s = scoreMixed ? null : p.value(history, K.sleepScore, d);
    if (s != null && (bestScore == null || s > bestScore)) {
      bestScore = s;
      bestNight = d;
    }
    final st = p.value(history, K.steps, d);
    if (complete && st != null && (mostStepsValue == null || st > mostStepsValue)) {
      mostStepsValue = st;
      mostSteps = d;
    }
    final a = p.value(history, K.activeMin, d);
    if (complete && a != null) {
      active = (active ?? 0) + a;
      activeDays++;
    }
    final w = p.value(history, K.weight, d);
    // Round 1 (S11-2): ζύγιση που μοιάζει ξένη δεν μπαίνει στο «Βάρος μέσα στην εβδομάδα».
    if (w != null && !foreignWeighIn(history, p, d)) {
      wFirst ??= (d, w);
      wLast = (d, w);
    }
  }

  return WeekReview(
    monday: monday,
    sunday: sunday,
    items: items,
    bestNight: bestNight,
    bestNightScore: bestScore,
    mostSteps: mostSteps,
    mostStepsValue: mostStepsValue,
    activeTotal: active,
    activeDays: activeDays,
    weightFirst: wFirst,
    weightLast: wLast,
  );
}
