// Έλεγχος #2 (8/11): συμπτώματα, διακοπή παντού μετά από σύμπτωμα, ρολόι, πρόοδος, οξυγόνο.
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/reference.dart';
import 'package:ygeia_forma/training/progression.dart';
import 'package:ygeia_forma/training/program.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/symptoms.dart';
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
  group('συμπτώματα (M2-01, M2-02)', () {
    test('ο πόνος στο στήθος μετρά και σε ηρεμία· νέα συμπτώματα', () {
      final chest = symptomDef('chest')!;
      expect(chest.red, isTrue);
      expect(chest.text, contains('σε ηρεμία'));
      expect(symptomDef('breath')!.text, contains('ξαπλώνω'));
      expect(symptomDef('dizzyx')!.red, isTrue, reason: 'ζάλη στην προσπάθεια: κλειδώνει από την πρώτη φορά');
      expect(symptomDef('dizzy')!.red, isFalse);
      expect(symptomDef('swell')!.red, isFalse);
      expect(symptomDef('other'), isNotNull);
    });

    test('166 τώρα: μόνο του ή στήθος/ταχυπαλμία με συνοδά', () {
      expect(callNowFor(['faint']), isTrue);
      expect(callNowFor(['chest']), isFalse);
      expect(callNowFor(['chest', 'nausea']), isTrue);
      expect(callNowFor(['chest', 'sweat']), isTrue);
      expect(callNowFor(['chest', 'breath']), isTrue);
      expect(callNowFor(['palp', 'dizzy']), isTrue);
      expect(callNowFor(['palp']), isFalse);
      expect(callNowFor(['tired', 'nausea']), isFalse);
    });

    test('ζάλη στην προσπάθεια: κλείδωμα από την πρώτη φορά', () {
      final t = sampleTraining(now);
      expect(t.reportSymptoms(['dizzyx']), SymptomOutcome.red);
      expect(t.lockReason, 'red');
    });
  });

  group('διακοπή μετά από σύμπτωμα (T2-01, X1, U2-04, T2-02)', () {
    test('η προπόνηση που σταμάτησε από σύμπτωμα δεν μετρά για την πρόοδο', () {
      final t = sampleTraining(now);
      final before = t.historyOf('db_press').length;
      final s = t.start(t.program!.workout('A')!);
      final e = s.items.first;
      for (var i = 0; i < e.log.length; i++) {
        t.tick(e, i);
      }
      t.answer(e, 3);
      expect(t.reportSymptoms(['nausea'], where: 'session'), SymptomOutcome.amber);
      expect(t.sessions.last.stopped, isTrue);
      expect(t.historyOf('db_press').length, before, reason: 'σταματημένη προπόνηση: όχι στο ιστορικό της προόδου');
      // και μετά από αποθήκευση/φόρτωμα
      final back = Session.fromJson(t.sessions.last.toJson());
      expect(back.stopped, isTrue);
      // παλιά καταγραφή (#81–#83) με σημείωση μόνο
      final old = Session.fromJson({...t.sessions.last.toJson()..remove('stop'), 'note': 'Σταμάτησε: σύμπτωμα'});
      expect(old.stopped, isTrue);
    });

    test('«Σταμάτησα» στο ρολόι σταματά και την προπόνηση του κινητού', () {
      final t = sampleTraining(now);
      final s = t.start(t.program!.workout('A')!);
      t.tick(s.items.first, 0);
      t.restEnd = now.add(const Duration(seconds: 90));
      final at = now.add(const Duration(minutes: 1));
      expect(t.importWatch({'v': 1, 'kind': 'sym', 'at': at.millisecondsSinceEpoch, 'sid': s.id}), isTrue);
      expect(t.current, isNull);
      expect(t.restEnd, isNull);
      expect(t.sessions.last.stopped, isTrue);
      expect(t.pendingWatchSymptom, isNotNull);
      expect(t.watchSeenAt, at.millisecondsSinceEpoch);
    });

    test('παλιό «Σταμάτησα» (πριν ξεκινήσει η τωρινή) δεν τη σταματά', () {
      final t = sampleTraining(now);
      t.start(t.program!.workout('A')!);
      t.importWatch({'v': 1, 'kind': 'sym', 'at': now.subtract(const Duration(days: 2)).millisecondsSinceEpoch});
      expect(t.current, isNotNull);
    });

    test('τι επιτρέπει το ρολόι: lock, pending, today, check', () {
      var at = now;
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => at)..replaceAll({'v': 1, 'approved': true});
      expect(t.watchHold, isNull);
      t.importWatch({'v': 1, 'kind': 'sym', 'at': at.millisecondsSinceEpoch});
      expect(t.watchHold, 'pending');
      t.reportSymptoms(['tired'], where: 'watch');
      expect(t.watchHold, 'today', reason: 'πορτοκαλί: καμία άσκηση σήμερα');
      at = now.add(const Duration(days: 1));
      expect(t.watchHold, 'check', reason: 'την επόμενη μέρα: «Πώς είσαι σήμερα;» από το κινητό');
      t.reportSymptoms(['chest']);
      expect(t.watchHold, 'lock');
      final plan = watchPlan(t, at, (x) => x);
      expect(plan['hold'], 'lock');
      expect(plan['symSeen'], now.millisecondsSinceEpoch);
      t.approve(hr: 130);
      expect(t.watchHold, 'check', reason: 'πρώτες 4 εβδομάδες μετά την έγκριση');
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
