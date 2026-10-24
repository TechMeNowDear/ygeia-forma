import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/trends.dart';

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
    expect(t.goodness, 1, reason: 'λιγότεροι παλμοί = καλύτερα');
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

  test('Χρόνος: τελευταίοι 3 μήνες με τους πρώτους 3', () {
    final t = computeTrend(def(K.sleepHr), history, today, TrendPeriod.year);
    expect(t.end, today);
    expect(t.currentFrom, DateTime(2026, 7, 27));
    expect(t.previousFrom, DateTime(2025, 10, 25));
  });

  test('Ώρα ύπνου μετά τα μεσάνυχτα', () {
    expect(minutesFromSix(DateTime(2026, 1, 1, 0, 30)), 390);
    expect(clockFromSix(390), '00:30');
    expect(clockFromSix(300), '23:00');
  });
}
