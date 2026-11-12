// Τελικός έλεγχος, Συμβούλιο 4 (αρχιτεκτονική Android 17 / Wear OS), η πλευρά του κινητού.
// W-4: επαναλήψεις που αλλάζεις στο ρολόι δεν χάνονται όταν χαθεί ένα μήνυμα (Bluetooth, κλειστή εφαρμογή):
// έρχονται μέσα στο ✓ («r») και, αν χρειαστεί, μέσα στο αποτέλεσμα του ρολογιού («rb»).
// Η πλευρά του ρολογιού: android/wear/src/test/…/AuditFinalS4Test.kt. Όλα τα νούμερα είναι δοκιμαστικά.
// Μετά τις αποφάσεις της 12/11: Γ1 (επαναφορά φαγητού σε μία συναλλαγή) και το «+» των λεπτών αερόβιας ως 600.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/training/program.dart';
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

  group('Συμβούλιο 4 · Γ1: επαναφορά φαγητού από αντίγραφο σε μία κλήση', () {
    const channel = MethodChannel('ygeia/food');
    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    Map<String, Object> food(String id) => {
          'id': id,
          'name': 'Δοκιμαστικό $id',
          'cat': 'Τα προϊόντα μου',
          'source': 'Ετικέτα',
          'n': {'kcal': 70, 'protein': 10},
        };
    Map<String, Object> entry(String id, DateTime at) => {
          'id': id,
          'day': '${at.year.toString().padLeft(4, '0')}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}',
          'meal': 'lunch',
          'food': food('M1'),
          'grams': 170,
          'time': at.millisecondsSinceEpoch,
        };
    final today = DateTime.now();
    final recent = DateTime(today.year, today.month, today.day, 13);
    final old = DateTime(today.year, today.month, today.day - 400, 13);

    /// Το κινητό έχει ήδη την καταχώριση E1 και το προϊόν M1. [restore]: τι απαντά η βάση στην επαναφορά.
    List<MethodCall> phone(Map<String, Object?> restore) {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'logRange' => jsonEncode({
              'ok': true,
              'entries': [entry('E1', recent)],
            }),
          'myFoods' => jsonEncode({
              'ok': true,
              'foods': [food('M1')],
            }),
          'restorePut' => jsonEncode(restore),
          _ => jsonEncode({'ok': true}),
        };
      });
      return calls;
    }

    List<LogEntry> entries(List<Map<String, Object>> js) => [for (final j in js) LogEntry.fromJson(j)];
    List<Food> foods(List<Map<String, Object>> js) => [for (final j in js) Food.fromJson(j)];

    test('ό,τι λείπει πάει σε ΜΙΑ κλήση· ό,τι υπάρχει ήδη μένει· καμία εγγραφή μία-μία', () async {
      final calls = phone({'ok': true, 'entries': 2, 'foods': 1});
      final s = FoodStore();
      addTearDown(s.dispose);
      final res = await s.importBackup(
        entries([entry('E1', recent), entry('E2', recent), entry('E3', old), entry('E2', recent)]),
        foods([food('M1'), food('M2')]),
      );
      // (καταχωρίσεις, προϊόντα, αποτυχίες, υπήρχαν ήδη): E1, το δεύτερο E2 και το M1 υπήρχαν ήδη
      expect(res, (2, 1, 0, 3));
      final writes = calls.where((c) => c.method != 'logRange' && c.method != 'myFoods').toList();
      expect(writes.map((c) => c.method), ['restorePut']);
      final args = Map<String, dynamic>.from(writes.single.arguments as Map);
      expect([for (final x in jsonDecode(args['log'] as String) as List) (x as Map)['id']], ['E2', 'E3']);
      expect([for (final x in jsonDecode(args['foods'] as String) as List) (x as Map)['id']], ['M2']);
      // κάθε καταχώριση έχει «id» και «day», όπως τα θέλει το Kotlin (FoodRules.restoreRows)
      for (final x in jsonDecode(args['log'] as String) as List) {
        expect((x as Map)['day'], isA<String>());
      }
      // στη μνήμη: η πρόσφατη φαίνεται, η παλιά (πάνω από 90 μέρες) όχι· το νέο προϊόν πρώτο, το παλιό μένει
      expect(s.entriesFor(recent).map((x) => x.id), contains('E2'));
      expect(s.entriesFor(old), isEmpty);
      expect(s.mine.map((x) => x.id), ['M2', 'M1']);
    });

    test('η βάση αρνήθηκε: τίποτα στη μνήμη, όλα στις αποτυχίες (ή όλα ή τίποτα)', () async {
      phone({'ok': false, 'kind': 'other', 'message': 'δοκιμή'});
      final s = FoodStore();
      addTearDown(s.dispose);
      final res = await s.importBackup(entries([entry('E2', recent), entry('E3', old)]), foods([food('M2')]));
      expect(res, (0, 0, 3, 0));
      expect(s.entriesFor(recent), isEmpty);
      expect(s.mine.map((x) => x.id), ['M1']);
    });

    test('δεν λείπει τίποτα: καμία εγγραφή στη βάση', () async {
      final calls = phone({'ok': true, 'entries': 0, 'foods': 0});
      final s = FoodStore();
      addTearDown(s.dispose);
      final res = await s.importBackup(entries([entry('E1', recent)]), foods([food('M1')]));
      expect(res, (0, 0, 0, 2));
      expect(calls.where((c) => c.method == 'restorePut'), isEmpty);
    });

    test('η βάση βρήκε κάτι ήδη εκεί (γράφτηκε στο μεταξύ): μετρά στα «υπήρχαν ήδη», όχι στις αποτυχίες', () async {
      phone({'ok': true, 'entries': 1, 'foods': 0});
      final s = FoodStore();
      addTearDown(s.dispose);
      final res = await s.importBackup(entries([entry('E2', recent), entry('E3', old)]), foods([food('M2')]));
      expect(res, (1, 0, 0, 2));
    });

    test('απάντηση χωρίς αριθμούς (ή με άσχετους): μετρά όσα στάλθηκαν, ποτέ πάνω από αυτά', () async {
      phone({'ok': true});
      final s = FoodStore();
      addTearDown(s.dispose);
      expect(await s.importBackup(entries([entry('E2', recent)]), foods([food('M2')])), (1, 1, 0, 0));
      phone({'ok': true, 'entries': 99, 'foods': -3});
      final s2 = FoodStore();
      addTearDown(s2.dispose);
      expect(await s2.importBackup(entries([entry('E2', recent)]), foods([food('M2')])), (1, 0, 0, 1));
    });
  });

  group('Συμβούλιο 4 · απόφαση 3: τα λεπτά αερόβιας στον επεξεργαστή', () {
    test('το «+» φτάνει ως το όριο της επικόλλησης (600), με βήμα 5', () {
      expect(cardioMinutesPlus(5), 10);
      expect(cardioMinutesPlus(175), 180);
      expect(cardioMinutesPlus(180), 185, reason: 'πριν σταματούσε εδώ');
      expect(cardioMinutesPlus(240), 245);
      expect(cardioMinutesPlus(598), 600, reason: 'ποτέ πάνω από το όριο');
      expect(cardioMinutesPlus(600), isNull);
      expect(cardioMinutesPlus(601), isNull);
      expect(cardioMaxMinutes, 600);
    });

    test('το «−» όπως πριν (ως τα 5′)· από 240 με «−» και «+» γυρίζεις στο 240', () {
      expect(cardioMinutesMinus(240), 235);
      expect(cardioMinutesMinus(10), 5);
      expect(cardioMinutesMinus(5), isNull);
      expect(cardioMinutesMinus(3), isNull);
      expect(cardioMinutesPlus(cardioMinutesMinus(240)!), 240);
      // ό,τι δέχεται η επικόλληση, ο επεξεργαστής το δείχνει και το αλλάζει χωρίς να βγει από τα όρια
      for (var m = cardioMinMinutes; m <= cardioMaxMinutes; m++) {
        final up = cardioMinutesPlus(m), down = cardioMinutesMinus(m);
        if (up != null) expect(up > m && up <= cardioMaxMinutes, isTrue, reason: '$m');
        if (down != null) expect(down < m && down >= cardioMinMinutes, isTrue, reason: '$m');
      }
    });
  });
}
