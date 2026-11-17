// Έλεγχος 17/11, κατηγορία 1 (θερμίδες, στόχοι, εβδομαδιαίος έλεγχος). Μόνο το επινοημένο προφίλ (90 kg, 180 cm).
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/adaptive.dart';
import 'package:ygeia_forma/goals.dart';

Goals _g() => Goals(
      aim: GoalAim.lose,
      rate: 0.005,
      activity: 1.5,
      doctor: false,
      since: '2026-11-16',
      kg: 90,
      age: 40,
      heightCm: 180,
      male: true,
    );

double _plainSe(List<(DateTime, double)> w) {
  final n = w.length;
  final xs = [for (final p in w) p.$1.difference(w.first.$1).inDays.toDouble()];
  final ys = [for (final p in w) p.$2];
  final mx = xs.reduce((a, b) => a + b) / n, my = ys.reduce((a, b) => a + b) / n;
  var sxx = 0.0, sxy = 0.0;
  for (var i = 0; i < n; i++) {
    sxx += (xs[i] - mx) * (xs[i] - mx);
    sxy += (xs[i] - mx) * (ys[i] - my);
  }
  final s = sxy / sxx;
  var rss = 0.0;
  for (var i = 0; i < n; i++) {
    final r = ys[i] - (my + s * (xs[i] - mx));
    rss += r * r;
  }
  return math.sqrt(rss / (n - 2) / sxx);
}

void main() {
  group('Κ1-H1: ζυγίσεις που μοιάζουν μεταξύ τους', () {
    test('απόκλιση που κρατά μέρες (νερά): το σφάλμα μεγαλώνει', () {
      // Ευθεία −0,05 kg τη μέρα και ένα «κύμα» νερών που κρατά μια εβδομάδα πάνω και μια κάτω.
      final w = [
        for (var d = 0; d < 21; d++)
          (DateTime(2026, 12, 1 + d), 90 - 0.05 * d + ((d ~/ 7).isEven ? 0.4 : -0.4)),
      ];
      final f = weightFit(w)!;
      expect(f.se!, greaterThan(_plainSe(w) * 1.5));
    });

    test('απόκλιση που αλλάζει κάθε μέρα: ίδιο σφάλμα με πριν', () {
      final w = [
        for (var d = 0; d < 21; d++) (DateTime(2026, 12, 1 + d), 90 - 0.05 * d + (d.isEven ? 0.3 : -0.3)),
      ];
      expect(weightFit(w)!.se!, closeTo(_plainSe(w), 1e-12));
    });
  });

  group('Κ1-L6: ο τύπος με το τωρινό βάρος', () {
    test('κοντά στο βάρος του οδηγού: ο ίδιος αριθμός', () {
      final f = formulaNow(_g(), [(DateTime(2026, 12, 1), 89.0)]);
      expect(f.tdee, _g().calc.tdee);
      expect(f.kg, isNull);
    });

    test('7 kg κάτω: Mifflin με το νέο βάρος (−10 kcal ανά kg × κίνηση)', () {
      final f = formulaNow(_g(), [(DateTime(2026, 12, 1), 88.0), (DateTime(2027, 3, 1), 83.0)]);
      expect(f.kg, 83.0);
      expect(f.tdee, closeTo(_g().calc.tdee - 70 * 1.5, 1e-9));
    });

    test('άκυρο βάρος ή χωρίς ζυγίσεις: ο τύπος του οδηγού', () {
      expect(formulaNow(_g(), const []).tdee, _g().calc.tdee);
      expect(formulaNow(_g(), [(DateTime(2026, 12, 1), double.nan)]).tdee, _g().calc.tdee);
    });
  });
}
