// Έλεγχος #2 (8/11): πρόοδος, κείμενα· απλοποίηση (9/11): χωρίς συμπτώματα και κλείδωμα.
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/reference.dart';
import 'package:ygeia_forma/training/progression.dart';
import 'package:ygeia_forma/training/program.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/training_store.dart';
import 'package:ygeia_forma/training/wear_link.dart';

import 'training_sample.dart';

final now = DateTime(2026, 11, 20, 18, 0);

ExLog _log(String ex, double? load, List<int> reps, {int? rir, int sets = 3}) => ExLog(
      ex: ex,
      sets: sets,
      lo: 8,
      hi: 12,
      rir: 2,
      rest: 90,
      rirAnswer: rir,
      log: [for (final r in reps) SetLog(load: load, reps: r, done: true)],
    );

PlanItem _item(String ex) => PlanItem(ex: ex, sets: 3, lo: 8, hi: 12, rir: 2, rest: 90);

void main() {
  group('απλοποίηση (9/11): χωρίς «Νιώθω κάτι» και κλείδωμα', () {
    test('παλιό «Σταμάτησα» από ρολόι αγνοείται· η προπόνηση συνεχίζει', () {
      final t = sampleTraining(now);
      final s = t.start(t.program!.workout('A')!);
      expect(t.importWatch({'v': 1, 'kind': 'sym', 'at': now.millisecondsSinceEpoch, 'sid': s.id}), isFalse);
      expect(t.current, isNotNull);
    });

    test('παλιά αρχεία: έγκριση, κλείδωμα, συμπτώματα αγνοούνται, το όριο μένει', () {
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => now)
        ..replaceAll({
          'v': 1,
          'approved': false,
          'lock': 'red',
          'hrLimit': 130,
          'sym': [
            {'at': now.millisecondsSinceEpoch, 'c': 'chest'}
          ],
        });
      expect(t.hrLimit, 130);
      final j = t.toJson();
      // Έλεγχος 9/11 (V-A-07): δεν χρησιμοποιούνται, αλλά ούτε σβήνονται σιωπηλά από το αρχείο: ξαναγράφονται αυτούσια.
      expect(j['sym'], [
        {'at': now.millisecondsSinceEpoch, 'c': 'chest'}
      ]);
      expect(j['lock'], 'red');
      expect(j['approved'], isFalse);
      final plan = watchPlan(t, now, (x) => x);
      expect(plan['approved'], isTrue, reason: 'ρολόι με παλιά έκδοση: ποτέ κλειδωμένο');
      expect(plan['hrLimit'], 130);
      expect(plan.containsKey('hold'), isFalse);
      t.setHrLimit(null);
      expect(watchPlan(t, now, (x) => x).containsKey('hrLimit'), isFalse);
    });

    test('σταματημένη προπόνηση (παλιές καταγραφές) δεν μετρά για την πρόοδο', () {
      final back = Session.fromJson({
        'id': 'x',
        'w': 'A',
        'name': 'Α',
        'start': now.millisecondsSinceEpoch,
        'end': now.millisecondsSinceEpoch,
        'items': [],
        'note': 'Σταμάτησε: σύμπτωμα',
      });
      expect(back.stopped, isTrue);
    });
  });

  group('πρόοδος (RIR ≥ 2, T2-03)', () {
    test('ρεζέρβα κάτω από 2 σε αλτήρες: ίδια κιλά, με τον λόγο της πίεσης', () {
      final t = nextTarget(_item('db_press'), [(now.subtract(const Duration(days: 3)), _log('db_press', 9.3, [12, 12, 12], rir: 1))], now);
      expect(t.change, Change.hold);
      expect(t.load, 9.3);
      expect(t.reason, contains('πίεση'));
    });

    test('δύο φορές «τελείωσες νωρίτερα» χωρίς σετ κάτω από το εύρος: όχι κατέβασμα', () {
      final d1 = now.subtract(const Duration(days: 3)), d2 = now.subtract(const Duration(days: 6));
      final h = [(d1, _log('db_press', 11.8, [9, 8])), (d2, _log('db_press', 11.8, [10]))];
      final t = nextTarget(_item('db_press'), h, now);
      expect(t.change, isNot(Change.down));
      expect(t.load, 11.8);
    });

    test('δύο φορές κάτω από το εύρος: ένα σκαλί κάτω (όπως πριν)', () {
      final d1 = now.subtract(const Duration(days: 3)), d2 = now.subtract(const Duration(days: 6));
      final h = [(d1, _log('db_press', 11.8, [8, 7, 6])), (d2, _log('db_press', 11.8, [8, 7, 7]))];
      expect(nextTarget(_item('db_press'), h, now).change, Change.down);
    });
  });

  group('κείμενα (έλεγχος #2)', () {
    test('αναπνοές στον ύπνο: όχι πια NEWS2', () {
      expect(breathRange.cite, isNot(contains('NEWS2')));
      expect(breathRange.text, contains('ύπνο'));
      expect(breathRange.place(15), isNot(breathRange.place(10)));
    });
  });
}
