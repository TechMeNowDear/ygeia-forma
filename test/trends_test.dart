import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/trends.dart';
import 'package:ygeia_forma/weekly.dart';

/// Συνθετικό ιστορικό με γνωστές αλλαγές, για να ελέγχουμε ότι οι κανόνες των τάσεων κάνουν ό,τι λένε.
void main() {
  final today = DateTime(2026, 10, 24);
  final rnd = math.Random(3);
  final history = <String, Map<String, double>>{};
  DateTime day(int ago) => DateTime(today.year, today.month, today.day - ago);

  for (var ago = 0; ago < 365; ago++) {
    final row = <String, double>{};
    // Παλμοί στον ύπνο: 63 ±1 πριν, 60 ±1 τις τελευταίες 30 μέρες → πραγματική πτώση.
    row[K.sleepHr] = (ago < 30 ? 60 : 63) + rnd.nextDouble() * 2 - 1;
    // Βήματα: ίδια κατανομή παντού, με μεγάλο θόρυβο → σταθερό.
    row[K.steps] = 5000.0 + ((ago * 1103515245) % 4001) - 2000;
    // Διάρκεια ύπνου: διαφορά 8 λεπτά (κάτω από το ελάχιστο των 15) → σταθερό.
    row[K.sleepMin] = (ago < 30 ? 428 : 420) + rnd.nextDouble() * 4 - 2;
    // Energy Score: μόνο 10 μέρες στον τελευταίο μήνα → λίγα δεδομένα.
    if (ago >= 30 || ago % 3 == 0) row[K.energy] = 70;
    history[dateKey(day(ago))] = row;
  }
  // Βάρος: 2 ζυγίσεις τον τελευταίο μήνα → λίγα δεδομένα για «Μήνας».
  history[dateKey(day(2))]![K.weight] = 82.2;
  history[dateKey(day(20))]![K.weight] = 82.6;

  MetricDef def(String key) => trendMetrics.firstWhere((m) => m.key == key);

  test('Πραγματική πτώση παλμών στον ύπνο', () {
    final t = computeTrend(def(K.sleepHr), history, today, TrendPeriod.month);
    expect(t.status, TrendStatus.down);
    expect(t.diff!, closeTo(-3, 0.6));
    // Από 4/11 (κλινικός έλεγχος M4): η πτώση των παλμών ύπνου είναι ουδέτερη, μόνο η άνοδος είναι «προσοχή».
    expect(t.goodness, 0, reason: 'λιγότεροι παλμοί δεν είναι πάντα καλύτερα');
  });

  test('Θόρυβος χωρίς αλλαγή → σταθερό', () {
    final t = computeTrend(def(K.steps), history, today, TrendPeriod.month);
    expect(t.status, TrendStatus.stable);
  });

  test('Μικρή διαφορά κάτω από το ελάχιστο → σταθερό', () {
    final t = computeTrend(def(K.sleepMin), history, today, TrendPeriod.month);
    expect(t.status, TrendStatus.stable);
  });

  test('Λίγες μέρες με δεδομένα → λίγα δεδομένα', () {
    final t = computeTrend(def(K.energy), history, today, TrendPeriod.month);
    expect(t.status, TrendStatus.insufficient);
    expect(t.needed, 20);
  });

  test('Λίγες ζυγίσεις → λίγα δεδομένα', () {
    final t = computeTrend(def(K.weight), history, today, TrendPeriod.month);
    expect(t.status, TrendStatus.insufficient);
  });

  test('Λίγες ζυγίσεις με πραγματική αλλαγή 2 kg → φαίνεται', () {
    final h = <String, Map<String, double>>{};
    const now = [80.1, 79.8, 80.2, 79.9], before = [82.2, 81.9, 82.0, 82.3];
    for (var i = 0; i < 4; i++) {
      h[dateKey(day(1 + 7 * i))] = {K.weight: now[i]};
      h[dateKey(day(32 + 7 * i))] = {K.weight: before[i]};
    }
    final t = computeTrend(def(K.weight), h, today, TrendPeriod.month);
    expect(t.status, TrendStatus.down);
    // και χωρίς αλλαγή, ίδιος θόρυβος → σταθερό
    for (var i = 0; i < 4; i++) {
      h[dateKey(day(32 + 7 * i))] = {K.weight: now[3 - i]};
    }
    expect(computeTrend(def(K.weight), h, today, TrendPeriod.month).status, TrendStatus.stable);
  });

  test('Βαθμολογία ύπνου: αρκεί το 1/3 των νυχτών (οι χωρισμένες δεν έχουν βαθμολογία)', () {
    final h = <String, Map<String, double>>{};
    for (var ago = 0; ago < 60; ago++) {
      if (ago % 2 == 0) h[dateKey(day(ago))] = {K.sleepScore: 80.0 + (ago % 6)};
    }
    final t = computeTrend(def(K.sleepScore), h, today, TrendPeriod.month);
    expect(t.needed, 10);
    expect(t.status, isNot(TrendStatus.insufficient));
  });

  test('Αραιές μετρήσεις: η αυτοσυσχέτιση βγαίνει και από τιμές που απέχουν μέρες (όχι 0)', () {
    // Πριν (έλεγχος F4): χωρίς διαδοχικές μέρες, φ = 0, σαν να ήταν ανεξάρτητες. Τώρα: φ^g από τα κενά.
    final w = <(DateTime, double)>[];
    var x = 0.0;
    final r = math.Random(5);
    for (var ago = 120; ago >= 0; ago -= 2) {
      x = 0.81 * x + (r.nextDouble() - 0.5); // φ ημέρας 0,9 → φ² = 0,81 ανά δύο μέρες
      w.add((day(ago), 80 + x));
    }
    final phi = dailyCorrelation([w])!;
    expect(phi, greaterThan(0.6));
    // Λίγα ζευγάρια: δεν βγαίνει εκτίμηση (και η σύγκριση παίρνει συντηρητική τιμή).
    expect(dailyCorrelation([
      [(day(1), 80.0), (day(8), 81.0), (day(15), 80.0)],
    ]), isNull);
  });

  test('Πραγματικό πλήθος με κενά: λιγότερο από n, ίσο με n όταν φ = 0', () {
    final days = [for (var i = 0; i < 30; i += 2) day(i)].reversed.toList();
    expect(effectiveN(days, 0), days.length);
    // 15 τιμές μέρα παρά μέρα με φ = 0,5: φ² = 0,25 ανά ζευγάρι → ≈ 9,3.
    expect(effectiveN(days, 0.5), closeTo(9.33, 0.05));
  });

  // B1 (έλεγχος υπολογισμών F2, 4/11): πριν, το «άλλαξε» έβγαινε στο 2–10% των συγκρίσεων χωρίς καμία
  // αλλαγή, όταν έλειπαν μέρες. Προσομοίωση με σταθερό σπόρο: AR(1), 75% των ημερών με τιμή, 180 μέρες.
  double falseChangeRate(MetricDef def, double phi, int sims, int seed, {double sd = 1, double coverage = 0.75, int every = 1}) {
    final r = math.Random(seed);
    double normal() => math.sqrt(-2 * math.log(1 - r.nextDouble())) * math.cos(2 * math.pi * r.nextDouble());
    var tested = 0, changed = 0;
    for (var s = 0; s < sims; s++) {
      final h = <String, Map<String, double>>{};
      var x = normal() * sd;
      for (var ago = 179; ago >= 0; ago--) {
        x = phi * x + math.sqrt(1 - phi * phi) * sd * normal();
        if (ago % every == 0 && r.nextDouble() < coverage) h[dateKey(day(ago))] = {def.key: 60 + x};
      }
      final t = computeTrend(def, h, today, TrendPeriod.month);
      if (t.status == TrendStatus.insufficient) continue;
      tested++;
      if (t.changed) changed++;
    }
    return changed / tested;
  }

  test('Αυτοσυσχέτιση με κενές μέρες: ψεύτικο «άλλαξε» ≤ ~1,5% (προσομοίωση)', () {
    // Μόνο ο στατιστικός έλεγχος (ελάχιστη διαφορά 0): το αυστηρότερο σενάριο.
    const pure = MetricDef(key: K.sleepHr, label: 'x', section: TrendSection.heart, minDiff: 0, unit: 'bpm');
    final rates = [
      for (final (i, phi) in [0.3, 0.6, 0.85].indexed) falseChangeRate(pure, phi, 600, 7000 + i),
    ];
    final overall = rates.reduce((a, b) => a + b) / rates.length;
    expect(overall, lessThanOrEqualTo(0.015), reason: 'ανά φ: $rates (πριν: ~2%, ~3,5%, ~10%)');
    for (final v in rates) {
      expect(v, lessThanOrEqualTo(0.025), reason: 'ανά φ: $rates');
    }
    // Με τα πραγματικά όρια (παλμοί ύπνου: τυπική απόκλιση 3 bpm, ελάχιστο 2 bpm), φ = 0,85.
    expect(falseChangeRate(def(K.sleepHr), 0.85, 400, 7100, sd: 3), lessThanOrEqualTo(0.015));
  });

  test('Ζυγίσεις μέρα παρά μέρα: ψεύτικο «Βάρος άλλαξε» ≤ ~1,5% (πριν: ~20–25%)', () {
    expect(falseChangeRate(def(K.weight), 0.95, 400, 7200, sd: 0.5, coverage: 1, every: 2), lessThanOrEqualTo(0.015));
  });

  test('Μεσαία τιμή πάνω, μέσος όρος κάτω → όχι «άλλαξε» (έλεγχος F3)', () {
    // Πριν: 16 νύχτες 20 λεπτά και 14 νύχτες 80 (μεσαία 20, μέσος 48)· τώρα 30 λεπτά κάθε νύχτα.
    // Ο έλεγχος βρίσκει πτώση του μέσου όρου, η κάρτα θα έλεγε «↑ 10 λεπτά». Τώρα: «Σταθερό».
    final h = <String, Map<String, double>>{};
    final prev = [for (var i = 0; i < 14; i++) ...[20.0, 80.0], 20.0, 20.0];
    for (var i = 0; i < 30; i++) {
      h[dateKey(day(59 - i))] = {K.awakeMin: prev[i]};
      h[dateKey(day(29 - i))] = {K.awakeMin: 30};
    }
    final t = computeTrend(def(K.awakeMin), h, today, TrendPeriod.month);
    expect(t.diff, 10);
    expect(t.status, TrendStatus.stable);
  });

  test('Ώρες γύρω στις 18:00: κυκλικός μέσος όρος (έλεγχος F13)', () {
    final v = [for (final (h, m) in [(17, 40), (18, 20), (17, 50), (18, 10)]) minutesFromSix(DateTime(2026, 1, 1, h, m)).toDouble()];
    expect(clockFromSix(circularMeanMinutes(v)), '18:00');
    expect(unwrapMinutes(1420, 5), -20);
    expect(unwrapMinutes(390, 360), 390);
  });

  test('Απόκλιση θερμοκρασίας του Oura με πρόσημο· χωρίς «-0,0» (έλεγχος F12, F14)', () {
    final skin = def(K.skinTemp);
    expect(skin.formatAs(0.3, Source.oura), '+0,3 °C');
    expect(skin.formatAs(-0.04, Source.oura), '0 °C');
    expect(skin.formatAs(34.2, Source.watch), '34,2 °C');
    expect(dec(-0.04), '0,0');
    expect(hoursMinutes(-5), '−5 λεπτά');
    expect(hoursMinutes(-65), '−1 ώρα 5 λεπτά');
  });

  test('Χρώματα: βαθύς ύπνος, ξύπνιος και πτώση παλμών ουδέτερα· άνοδος παλμών «προσοχή» (κλινικός έλεγχος M3/M4)', () {
    expect(def(K.deepPct).better, 0);
    expect(def(K.awakeMin).better, 0);
    final h = <String, Map<String, double>>{};
    for (var ago = 0; ago < 60; ago++) {
      h[dateKey(day(ago))] = {K.sleepHr: (ago < 30 ? 66 : 60) + (ago % 3) * 0.3};
    }
    final up = computeTrend(def(K.sleepHr), h, today, TrendPeriod.month);
    expect(up.status, TrendStatus.up);
    expect(up.goodness, -1);
  });

  test('Χρόνος: τελευταίοι 3 μήνες με τους ίδιους μήνες πέρσι', () {
    final t = computeTrend(def(K.sleepHr), history, today, TrendPeriod.year);
    expect(t.end, today);
    expect(t.currentFrom, DateTime(2026, 7, 27));
    expect(t.previousEnd, DateTime(2025, 10, 25));
    expect(t.previousFrom, DateTime(2025, 7, 28));
  });

  test('Διαδοχικές μέρες που μοιάζουν (αυτοσυσχέτιση) δεν βγάζουν ψεύτικο «άλλαξε»', () {
    // Τυχαίος περίπατος γύρω από σταθερό επίπεδο (AR(1), φ = 0,7), χωρίς καμία αλλαγή.
    var falseChanges = 0;
    for (var seed = 0; seed < 200; seed++) {
      final r = math.Random(seed);
      final h = <String, Map<String, double>>{};
      var x = 0.0;
      for (var ago = 70; ago >= 0; ago--) {
        // κανονικός θόρυβος (Box–Muller)
        final n = math.sqrt(-2 * math.log(1 - r.nextDouble())) * math.cos(2 * math.pi * r.nextDouble());
        x = 0.7 * x + n * 4;
        h[dateKey(day(ago))] = {K.sleepHr: 62 + x};
      }
      if (computeTrend(def(K.sleepHr), h, today, TrendPeriod.month).changed) falseChanges++;
    }
    expect(falseChanges, lessThanOrEqualTo(14), reason: 'το πολύ ~7% ψεύτικα «άλλαξε» (πριν: 12–25%)');
  });

  test('Απολογισμός: εβδομάδα χωρίς αλλαγή σπάνια δείχνει «άλλαξε»', () {
    var cardsWithFalseChange = 0;
    for (var seed = 0; seed < 200; seed++) {
      final r = math.Random(1000 + seed);
      final h = <String, Map<String, double>>{};
      final xs = <String, double>{for (final k in weekKeys) k: 0};
      for (var ago = 40; ago >= 0; ago--) {
        final row = <String, double>{};
        for (final k in weekKeys) {
          final n = math.sqrt(-2 * math.log(1 - r.nextDouble())) * math.cos(2 * math.pi * r.nextDouble());
          xs[k] = 0.4 * xs[k]! + n;
          row[k] = 100 + xs[k]! * 30;
        }
        h[dateKey(day(ago))] = row;
      }
      final sunday = DateTime(2026, 10, 18);
      final w = buildWeekReview(h, sunday, DateTime(2026, 10, 19, 9));
      if (w.items.any((t) => t.changed)) cardsWithFalseChange++;
    }
    expect(cardsWithFalseChange, lessThanOrEqualTo(36), reason: 'πριν: ~42–76% των καρτών· τώρα το πολύ ~18%');
  });

  test('Ώρα ύπνου μετά τα μεσάνυχτα', () {
    expect(minutesFromSix(DateTime(2026, 1, 1, 0, 30)), 390);
    expect(clockFromSix(390), '00:30');
    expect(clockFromSix(300), '23:00');
  });

  test('Απολογισμός: πότε φαίνεται', () {
    expect(reviewWeekSunday(DateTime(2026, 10, 25, 17, 59)), isNull);
    expect(reviewWeekSunday(DateTime(2026, 10, 25, 18, 0)), DateTime(2026, 10, 25));
    expect(reviewWeekSunday(DateTime(2026, 10, 26, 9)), DateTime(2026, 10, 25));
    expect(reviewWeekSunday(DateTime(2026, 10, 27, 9)), isNull);
  });

  test('Απολογισμός: εβδομάδα Δευτέρα–Κυριακή, η Κυριακή δεν μετρά στα βήματα', () {
    final sunday = DateTime(2026, 10, 18);
    final r = buildWeekReview(history, sunday, DateTime(2026, 10, 18, 19));
    expect(r.monday, DateTime(2026, 10, 12));
    final steps = r.items.firstWhere((t) => t.def.key == K.steps);
    expect(steps.end, DateTime(2026, 10, 17));
    expect(steps.nCurrent, 6);
    final hr = r.items.firstWhere((t) => t.def.key == K.sleepHr);
    expect(hr.end, sunday);
    expect(hr.nCurrent, 7);
    expect(hr.nPrevious, 28);
  });
}
