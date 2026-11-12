// Τελικός έλεγχος, Συμβούλιο 4 (αρχιτεκτονική Android 17 / Wear OS), η πλευρά του κινητού.
// W-4: επαναλήψεις που αλλάζεις στο ρολόι δεν χάνονται όταν χαθεί ένα μήνυμα (Bluetooth, κλειστή εφαρμογή):
// έρχονται μέσα στο ✓ («r») και, αν χρειαστεί, μέσα στο αποτέλεσμα του ρολογιού («rb»).
// Η πλευρά του ρολογιού: android/wear/src/test/…/AuditFinalS4Test.kt. Όλα τα νούμερα είναι δοκιμαστικά.
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/training/training_store.dart';
import 'package:ygeia_forma/training/wear_link.dart';

import 'training_sample.dart';

final now = DateTime(2026, 11, 20, 18, 0);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Συμβούλιο 4 · W-4: οι επαναλήψεις του ρολογιού μέσα στο ✓', () {
    test('το «r» διαβάζεται μόνο όταν είναι αριθμός και για την ίδια άσκηση· όρια 0–99', () {
      expect(watchTickReps({'r': 8}, 'db_press'), 8);
      expect(watchTickReps({'r': 8, 'ex': 'db_press'}, 'db_press'), 8);
      // άλλη άσκηση στο μεταξύ (εναλλακτική στο κινητό): όχι
      expect(watchTickReps({'r': 8, 'ex': 'db_row'}, 'db_press'), isNull);
      // ρολόι παλιότερης έκδοσης, ή δεν άλλαξες τίποτα στο ρολόι: κανένα «r»
      expect(watchTickReps({}, 'db_press'), isNull);
      expect(watchTickReps({'r': '8'}, 'db_press'), isNull);
      expect(watchTickReps({'r': null}, 'db_press'), isNull);
      expect(watchTickReps({'r': double.nan}, 'db_press'), isNull);
      expect(watchTickReps({'r': double.infinity}, 'db_press'), isNull);
      expect(watchTickReps({'r': 250}, 'db_press'), 99);
      expect(watchTickReps({'r': -4}, 'db_press'), 0);
      expect(watchTickReps({'r': 8.0}, 'db_press'), 8);
    });

    test('✓ με «r»: το σετ γράφεται με τις επαναλήψεις του ρολογιού, όχι με τις προγραμματισμένες', () {
      final t = sampleTraining(now);
      final s = t.start(t.program!.workout('A')!);
      final link = WearLink()..attachForTest(t);
      final e = s.items[0];
      final planned = e.log[0].reps, second = e.log[1].reps;
      final at = now.millisecondsSinceEpoch;
      // η εντολή «reps» χάθηκε· φτάνει μόνο το ✓, με τις επαναλήψεις μέσα
      link.apply(t, WatchCmd('tick', {'op': 'tick', 'i': 0, 's': 0, 'at': at, 'r': planned - 2, 'ex': e.ex, 'sid': s.id}));
      expect(e.log[0].done, isTrue);
      expect(e.log[0].reps, planned - 2);
      expect(e.log[0].at, at);
      // τα υπόλοιπα σετ δεν αλλάζουν
      expect(e.log[1].done, isFalse);
      expect(e.log[1].reps, second);
    });

    test('✓ χωρίς «r» (ρολόι παλιότερης έκδοσης, ή χωρίς αλλαγή): όπως πριν', () {
      final t = sampleTraining(now);
      final s = t.start(t.program!.workout('A')!);
      final link = WearLink()..attachForTest(t);
      final e = s.items[0];
      final planned = e.log[0].reps;
      link.apply(t, WatchCmd('tick', {'op': 'tick', 'i': 0, 's': 0, 'sid': s.id}));
      expect(e.log[0].done, isTrue);
      expect(e.log[0].reps, planned);
    });

    test('✓ με «r» για άλλη άσκηση: το ✓ γράφεται, οι επαναλήψεις όχι', () {
      final t = sampleTraining(now);
      final s = t.start(t.program!.workout('A')!);
      final link = WearLink()..attachForTest(t);
      final e = s.items[0];
      final planned = e.log[0].reps;
      link.apply(t, WatchCmd('tick', {'op': 'tick', 'i': 0, 's': 0, 'r': 3, 'ex': 'άλλη', 'sid': s.id}));
      expect(e.log[0].done, isTrue);
      expect(e.log[0].reps, planned);
    });

    test('ξανασταλμένο ✓ σε σετ που είναι ήδη ✓ δεν αλλάζει τίποτα (ούτε τις επαναλήψεις)', () {
      final t = sampleTraining(now);
      final s = t.start(t.program!.workout('A')!);
      final link = WearLink()..attachForTest(t);
      final e = s.items[0];
      t.tick(e, 0);
      t.setReps(e, 0, 11);
      link.apply(t, WatchCmd('tick', {'op': 'tick', 'i': 0, 's': 0, 'r': 5, 'ex': e.ex, 'late': true, 'sid': s.id}));
      expect(e.log[0].reps, 11);
    });
  });

  group('Συμβούλιο 4 · W-4: διόρθωση μέσα στο αποτέλεσμα του ρολογιού («rb»)', () {
    test('ο κανόνας: μόνο αν το κινητό δείχνει ακόμα τιμή που είχε πριν, και για το ίδιο ✓', () {
      int? f(int phone, Object? rb, {int? pAt = 5000, int? wAt = 5000, int watch = 8}) =>
          watchResultReps(phoneReps: phone, phoneAt: pAt, watchReps: watch, watchAt: wAt, before: rb);
      // το κινητό έχει ακόμα την παλιά τιμή: η διόρθωση εφαρμόζεται
      expect(f(10, [10]), 8);
      // ή μια ενδιάμεση που του είχε στείλει το ρολόι (10 → 9 → 8, έφτασε μόνο το 9)
      expect(f(9, [9, 10]), 8);
      // το κινητό έχει ήδη τη διόρθωση: τίποτα
      expect(f(8, [10]), isNull);
      // στο κινητό το άλλαξες εσύ σε κάτι άλλο: μένει του κινητού
      expect(f(12, [10]), isNull);
      // χωρίς «rb» (καμία διόρθωση που εκκρεμεί, ή ρολόι παλιότερης έκδοσης): τίποτα
      expect(f(10, null), isNull);
      expect(f(10, 10), isNull);
      // άλλο ✓ (ώρες πάνω από 2″ μακριά), ή χωρίς ώρα: τίποτα
      expect(f(10, [10], wAt: 9000), isNull);
      expect(f(10, [10], pAt: null), isNull);
      expect(f(10, [10], wAt: null), isNull);
      expect(f(10, [10], wAt: 6900), 8);
      // όρια 0–99
      expect(f(10, [10], watch: 400), 99);
    });

    test('αποτέλεσμα «hr» με «rb»: το σετ του κινητού παίρνει τη διόρθωση· τα άλλα μένουν', () {
      final t = sampleTraining(now);
      final s = t.start(t.program!.workout('A')!);
      final e = s.items[0];
      final at = now.millisecondsSinceEpoch;
      t.tick(e, 0, at: at);
      t.tick(e, 1, at: at + 30000);
      final planned = e.log[0].reps, second = e.log[1].reps;
      // Το ρολόι: σετ 1 διορθώθηκε (planned → planned − 3) και η εντολή δεν έφτασε· σετ 2 χωρίς διόρθωση αλλά με άλλη
      // τιμή στο ρολόι (δεν πρέπει να περάσει)· σετ 3 έγινε ✓ μόνο στο ρολόι (περνά όπως πριν).
      final ok = t.importWatch({
        'v': 1,
        'kind': 'hr',
        'sid': s.id,
        'id': 'hr${s.id}-$at',
        'items': [
          {
            'ex': e.ex,
            'sets': 3,
            'lo': e.lo,
            'hi': e.hi,
            'rir': 2,
            'rest': e.rest,
            'log': [
              {'r': planned - 3, 'l': 9.3, 'd': 1, 't': at, 'rb': [planned]},
              {'r': second - 1, 'l': 9.3, 'd': 1, 't': at + 30000},
              {'r': planned - 2, 'l': 9.3, 'd': 1, 't': at + 60000},
            ],
          },
        ],
      });
      expect(ok, isTrue);
      expect(e.log[0].reps, planned - 3);
      expect(e.log[1].reps, second);
      expect(e.log[2].done, isTrue);
      expect(e.log[2].reps, planned - 2);
      // το «rb» δεν μένει πουθενά στην προπόνηση του κινητού
      expect(e.log[0].toJson().containsKey('rb'), isFalse);
      // στο κινητό το άλλαξες εσύ μετά· το ίδιο αποτέλεσμα ξανά δεν το πειράζει (η τιμή δεν είναι πια στο «rb»)
      t.setReps(e, 0, planned + 5);
      t.importWatch({
        'v': 1,
        'kind': 'hr',
        'sid': s.id,
        'items': [
          {
            'ex': e.ex, 'sets': 3, 'lo': e.lo, 'hi': e.hi, 'rir': 2, 'rest': e.rest,
            'log': [
              {'r': planned - 3, 'd': 1, 't': at, 'rb': [planned]},
            ],
          },
        ],
      });
      expect(e.log[0].reps, planned + 5);
    });
  });
}
