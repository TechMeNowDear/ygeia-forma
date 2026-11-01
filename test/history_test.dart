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

  test('Σφάλμα σε είδος ύπνου: δεν αντικαθίστανται οι τιμές ύπνου', () {
    expect(sleepReadFailed({'ok': true, 'sleep': [], 'heart': []}), isFalse);
    expect(sleepReadFailed({'ok': true, 'sleep': [], 'energy': {'error': 'x'}}), isFalse,
        reason: 'η Energy Score δεν αγγίζει τον ύπνο');
    for (final k in sleepReadKeys) {
      expect(sleepReadFailed({'ok': true, 'sleep': [], k: {'error': 'x'}}), isTrue, reason: k);
    }
  });

  test('Χωρίς αντικατάσταση ο ύπνος μένει όπως ήταν', () {
    final h = sample();
    mergeHistory(h, {'2026-10-10': {K.steps: 7000}});
    expect(h['2026-10-10']![K.sleepMin], isNotNull);
    expect(h['2026-10-10']![K.steps], 7000);
  });

  test('Ίδιες τιμές: η μέρα δεν ξαναγράφεται', () {
    final h = sample();
    final changed = mergeHistory(h, {'2026-10-31': {K.steps: 7100}});
    expect(changed, isEmpty);
  });

  test('Ζύγιση που σβήστηκε στη Samsung φεύγει από το ιστορικό, οι άλλες τιμές μένουν', () {
    final h = <String, Map<String, double>>{
      '2026-10-01': {K.weight: 31.4, K.steps: 4000},
      '2026-10-08': {K.weight: 82.2, K.fatPct: 25.4},
      '2024-01-01': {K.weight: 85},
    };
    final changed = removeMissingBody(h, {'2026-10-08'}, from: DateTime(2024, 11, 2));
    expect(changed, {'2026-10-01'});
    expect(h['2026-10-01'], {K.steps: 4000});
    expect(h['2026-10-08']![K.weight], 82.2);
    expect(h['2024-01-01']![K.weight], 85, reason: 'έξω από τα 2 χρόνια της ανάγνωσης: δεν αγγίζεται');
  });

  test('Πόσες μέρες έχουν ήδη ύπνο σε ένα διάστημα', () {
    final h = sample();
    expect(sleepDaysIn(h, DateTime(2026, 10, 1), DateTime(2026, 10, 31)), 3);
    expect(sleepDaysIn(h, DateTime(2026, 10, 21), DateTime(2026, 10, 29)), 0);
  });
}
