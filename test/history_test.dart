import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/history.dart';

/// Κανόνες αποθήκευσης του ιστορικού: ο ύπνος κάθε μέρας έχει έναν ορισμό
/// (υπολογισμένος με βήματα ανά λεπτό) και δεν ξαναγράφεται από ανάγνωση χωρίς αυτά.
void main() {
  Map<String, Map<String, double>> sample() => {
        '2026-10-10': {K.sleepMin: 400, K.sleepScore: 70, K.steps: 5000, K.restHr: 60},
        '2026-10-20': {K.sleepMin: 380, K.steps: 6000},
        '2026-10-30': {K.sleepMin: 300, K.steps: 7000},
        '2026-10-31': {K.steps: 7100},
      };

  test('Ανανέωση: ο ύπνος ξαναγράφεται μόνο από τη μέρα με βήματα και μετά', () {
    final h = sample();
    final changed = mergeHistory(
      h,
      {
        '2026-10-20': {K.sleepMin: 200, K.steps: 6100},
        '2026-10-30': {K.sleepMin: 320, K.steps: 7200},
      },
      sleepFrom: DateTime(2026, 10, 26),
    );
    expect(changed, {'2026-10-20', '2026-10-30'});
    expect(h['2026-10-20']![K.sleepMin], 380, reason: 'παλιά μέρα: ο αποθηκευμένος ύπνος μένει');
    expect(h['2026-10-20']![K.steps], 6100, reason: 'οι υπόλοιπες τιμές ανανεώνονται κανονικά');
    expect(h['2026-10-30']![K.sleepMin], 320);
  });

  test('Ανανέωση: παλιά μέρα χωρίς ύπνο συμπληρώνεται', () {
    final h = sample();
    mergeHistory(h, {
      '2026-10-31': {K.sleepMin: 410, K.steps: 7100},
    }, sleepFrom: DateTime(2026, 11, 5));
    expect(h['2026-10-31']![K.sleepMin], 410);
  });

  test('Ανανέωση χωρίς βήματα (sleepFrom null): κανένας αποθηκευμένος ύπνος δεν αλλάζει', () {
    final h = sample();
    mergeHistory(h, {
      '2026-10-30': {K.sleepMin: 100},
    });
    expect(h['2026-10-30']![K.sleepMin], 300);
  });

  test('Μέρα με βήματα χωρίς νύχτα πια: οι παλιές τιμές ύπνου φεύγουν', () {
    final h = sample();
    mergeHistory(h, {
      '2026-10-30': {K.steps: 7300},
    }, sleepFrom: DateTime(2026, 10, 26));
    expect(h['2026-10-30']!.containsKey(K.sleepMin), isFalse);
    expect(h['2026-10-30']![K.steps], 7300);
  });

  test('Ξαναϋπολογισμός διαστήματος: όλος ο ύπνος αντικαθίσταται, τα άλλα μένουν', () {
    final h = sample();
    final changed = mergeHistory(
      h,
      {
        '2026-10-20': {K.sleepMin: 395},
      },
      replaceSleep: true,
      rangeFrom: DateTime(2026, 10, 1),
      rangeTo: DateTime(2026, 10, 25),
    );
    expect(changed, containsAll(['2026-10-10', '2026-10-20']));
    expect(h['2026-10-10']!.containsKey(K.sleepMin), isFalse);
    expect(h['2026-10-10']!.containsKey(K.sleepScore), isFalse);
    expect(h['2026-10-10']![K.restHr], 60);
    expect(h['2026-10-20']![K.sleepMin], 395);
    expect(h['2026-10-30']![K.sleepMin], 300, reason: 'έξω από το διάστημα: δεν αγγίζεται');
  });

  test('Νέοι κανόνες: σβήνονται μόνο οι τιμές ύπνου', () {
    final h = sample();
    final changed = clearSleepValues(h);
    expect(changed, {'2026-10-10', '2026-10-20', '2026-10-30'});
    for (final row in h.values) {
      expect(row.keys.any(sleepKeys.contains), isFalse);
    }
    expect(h['2026-10-10']![K.steps], 5000);
  });
}
