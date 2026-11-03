import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/unusual.dart';

/// Κανόνες «Εκτός συνηθισμένου» πάνω σε συνθετικό ιστορικό με γνωστές τιμές.
void main() {
  final today = DateTime(2026, 10, 24);
  DateTime day(int ago) => DateTime(today.year, today.month, today.day - ago);
  const wiggle = [-1.0, 0.0, 1.0, 0.5, -0.5];

  Map<String, Map<String, double>> base({double hrSwing = 1, int days = 40}) {
    final h = <String, Map<String, double>>{};
    for (var ago = 1; ago <= days; ago++) {
      final w = wiggle[ago % wiggle.length];
      h[dateKey(day(ago))] = {
        K.sleepHr: 60 + w * hrSwing,
        K.skinTemp: 34.0 + w * 0.1,
        K.energy: 75 + w * 3,
      };
    }
    return h;
  }

  test('Κανονικό πρωί → καμία κάρτα', () {
    final h = base()..[dateKey(today)] = {K.sleepHr: 61, K.skinTemp: 34.1, K.energy: 73};
    final r = checkUnusual(h, today);
    expect(r.signals.length, 3);
    expect(r.offCount, 0);
    expect(r.show, isFalse);
  });

  test('Παλμοί +6 και δέρμα +0,6 → κάρτα', () {
    final h = base()..[dateKey(today)] = {K.sleepHr: 66, K.skinTemp: 34.6, K.energy: 74};
    final r = checkUnusual(h, today);
    expect(r.offCount, 2);
    expect(r.show, isTrue);
    expect(r.signals.firstWhere((s) => s.rule.key == K.sleepHr).usual, 60);
  });

  test('Ένας μόνο δείκτης → καμία κάρτα', () {
    final h = base()..[dateKey(today)] = {K.sleepHr: 70, K.skinTemp: 34.0, K.energy: 75};
    expect(checkUnusual(h, today).show, isFalse);
  });

  test('Energy Score: μετράει μόνο η πτώση', () {
    final h = base()..[dateKey(today)] = {K.sleepHr: 66, K.energy: 95};
    final r = checkUnusual(h, today);
    expect(r.signals.firstWhere((s) => s.rule.key == K.energy).off, isFalse);
    expect(r.show, isFalse);
  });

  test('Πάνω από το ελάχιστο αλλά μέσα στις διακυμάνσεις σου → δεν μετράει', () {
    // Παλμοί που κάνουν ±6: +4 είναι πάνω από τα 3 bpm αλλά κάτω από 2 διακυμάνσεις.
    final h = base(hrSwing: 6)..[dateKey(today)] = {K.sleepHr: 64, K.skinTemp: 34.6};
    final s = checkUnusual(h, today).signals.firstWhere((s) => s.rule.key == K.sleepHr);
    expect(s.threshold, greaterThan(4));
    expect(s.off, isFalse);
  });

  test('Λίγο ιστορικό → ο δείκτης δεν ελέγχεται', () {
    final h = base(days: 10)..[dateKey(today)] = {K.sleepHr: 70, K.skinTemp: 35, K.energy: 50};
    final r = checkUnusual(h, today);
    expect(r.signals, isEmpty);
    expect(r.show, isFalse);
  });

  test('Και χθες εκτός συνηθισμένου', () {
    final h = base();
    h[dateKey(day(1))] = {K.sleepHr: 67, K.skinTemp: 34.7, K.energy: 60};
    h[dateKey(today)] = {K.sleepHr: 66, K.skinTemp: 34.6, K.energy: 62};
    final r = checkUnusual(h, today);
    expect(r.offCount, 3);
    expect(r.previousDayOff, isTrue);
  });

  test('Παλμοί και Energy Score μόνο (χωρίς θερμοκρασία) → καμία κάρτα (κλινικός έλεγχος M1)', () {
    // Το Energy Score βγαίνει εν μέρει από τους ίδιους παλμούς: δεν είναι δεύτερος ανεξάρτητος δείκτης.
    final h = base()..[dateKey(today)] = {K.sleepHr: 66, K.skinTemp: 34.0, K.energy: 55};
    final r = checkUnusual(h, today);
    expect(r.offCount, 2);
    expect(r.show, isFalse);
  });
}
