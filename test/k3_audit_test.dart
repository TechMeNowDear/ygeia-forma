// Έλεγχος 17/11, κατηγορία 3 (βάρος και σύσταση σώματος). Φανταστικά βάρη.
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/weight_guard.dart';

DateTime _d(int n) => DateTime(2026, 1, 1 + n);

void main() {
  test('Κ3-H1: άλλος ζυγίζεται ΠΡΩΤΟΣ κάθε μέρα: μετρά πάντα το δικό σου βάρος', () {
    final days = [
      for (var n = 0; n < 42; n++) (_d(n), [80.0]),
      for (var n = 42; n < 72; n++) (_d(n), [65.0, 80.0]),
    ];
    final r = guardDays(days);
    for (var n = 42; n < 72; n++) {
      expect(days[n].$2[r[n].pick], 80.0, reason: 'μέρα $n');
      expect(r[n].status, WeighStatus.counted, reason: 'μέρα $n');
    }
  });

  test('Κ3-M2: κάποιος 6 kg ελαφρύτερος την επόμενη μέρα από την τελευταία σου ζύγιση δεν μετρά μετά από 3 μέρες', () {
    final base = [for (var n = 0; n < 40; n++) (_d(n), [80.0])];
    for (var t = 40; t < 47; t++) {
      final days = [...base, for (var n = 40; n <= t; n++) (_d(n), [74.0])];
      final r = guardDays(days);
      expect(r.last.status, isNot(WeighStatus.counted), reason: 'μέρα $t');
    }
  });

  test('Κ3-M2: αληθινή αλλαγή μετά από κενό (αρρώστια) μετρά όπως πριν', () {
    final days = [
      for (var n = 0; n < 40; n += 2) (_d(n), [82.0]),
      for (var n = 52; n < 80; n += 2) (_d(n), [77.0]),
    ];
    final r = guardDays(days);
    expect(r.last.status, WeighStatus.counted);
  });
}
