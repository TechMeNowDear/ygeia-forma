// Τελικός έλεγχος, Συμβούλια 6–7 (ακραία σενάρια και μικρές αναβαθμίσεις), και οι τρεις εγκρίσεις του Συμβουλίου 5.
// Σ6-1: μήνυμα του ρολογιού με λάθος είδος τιμής (κείμενο αντί για αριθμό, 1e999) δεν πετά πια σφάλμα στη μέση της εντολής.
// Δ4: μικρή δόνηση αφής στα − / + της προπόνησης. Δ5: τίποτα στις «πρόσφατες εφαρμογές». Δ6α: το κείμενο της εξαγωγής.
// Όλα τα νούμερα είναι δοκιμαστικά.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/pages/training/training_common.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/training/wear_link.dart';

import 'training_sample.dart';

final now = DateTime(2026, 11, 20, 18, 0);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Συμβούλιο 6 · μηνύματα του ρολογιού με λάθος είδος τιμής', () {
    test('wearInt: μόνο πεπερασμένος αριθμός· wearTime: μόνο ώρα που χωρά σε ημερομηνία', () {
      expect(wearInt(7), 7);
      expect(wearInt(7.9), 7);
      expect(wearInt(-3), -3);
      expect(wearInt('7'), isNull);
      expect(wearInt(null), isNull);
      expect(wearInt(true), isNull);
      expect(wearInt(double.nan), isNull);
      expect(wearInt(double.infinity), isNull);
      expect(wearInt(double.negativeInfinity), isNull);
      expect(wearTime(now.millisecondsSinceEpoch), now);
      expect(wearTime('τώρα'), isNull);
      expect(wearTime(double.infinity), isNull);
      // πέρα από ό,τι χωρά σε ημερομηνία (το DateTime θα πετούσε σφάλμα)
      expect(wearTime(9e15), isNull);
      expect(wearTime(-9e15), isNull);
    });

    test('✓ με ώρα που δεν είναι αριθμός: γράφονται ΚΑΙ το ✓ ΚΑΙ οι επαναλήψεις (πριν: επαναλήψεις χωρίς ✓, και σφάλμα)', () {
      final t = sampleTraining(now);
      final s = t.start(t.program!.workout('A')!);
      final link = WearLink()..attachForTest(t);
      final e = s.items[0];
      final planned = e.log[0].reps;
      expect(
        () => link.apply(t, WatchCmd('tick', {'op': 'tick', 'i': 0, 's': 0, 'at': 'τώρα', 'r': planned - 2, 'ex': e.ex, 'sid': s.id})),
        returnsNormally,
      );
      expect(e.log[0].done, isTrue);
      expect(e.log[0].reps, planned - 2);
    });

    test('θέση άσκησης ή σετ που δεν είναι αριθμός: η εντολή αγνοείται ολόκληρη, χωρίς σφάλμα', () {
      final t = sampleTraining(now);
      final s = t.start(t.program!.workout('A')!);
      final link = WearLink()..attachForTest(t);
      final e = s.items[0];
      final planned = e.log[0].reps;
      for (final j in <Map<String, dynamic>>[
        {'i': '0', 's': 0, 'r': 3, 'sid': s.id},
        {'i': 0, 's': '0', 'r': 3, 'sid': s.id},
        {'i': double.infinity, 's': 0, 'r': 3, 'sid': s.id},
        {'i': 0, 's': double.nan, 'r': 3, 'sid': s.id},
        {'i': null, 's': null, 'sid': s.id},
        {'i': 999, 's': 0, 'sid': s.id},
        {'i': 0, 's': 999, 'sid': s.id},
      ]) {
        expect(() => link.apply(t, WatchCmd('tick', j)), returnsNormally, reason: '$j');
        expect(e.log[0].done, isFalse, reason: '$j');
        expect(e.log[0].reps, planned, reason: '$j');
      }
    });

    test('«Τέλος», ρεζέρβα και επαναλήψεις με τιμή που δεν είναι αριθμός: τίποτα δεν αλλάζει, κανένα σφάλμα', () {
      final t = sampleTraining(now);
      final s = t.start(t.program!.workout('A')!);
      final link = WearLink()..attachForTest(t);
      final e = s.items[0];
      final planned = e.log[0].reps;
      for (final c in [
        WatchCmd('end', {'at': 'τώρα', 'sid': s.id}),
        WatchCmd('end', {'at': double.infinity, 'sid': s.id}),
        WatchCmd('rir', {'i': 0, 'v': double.infinity, 'sid': s.id}),
        WatchCmd('rir', {'i': 0, 'v': '2', 'sid': s.id}),
        WatchCmd('reps', {'i': 0, 's': 0, 'v': double.infinity, 'sid': s.id}),
        WatchCmd('reps', {'i': 0, 's': 0, 'v': '9', 'sid': s.id}),
        WatchCmd('reps', {'i': 0, 's': 0, 'v': double.nan, 'q': double.infinity, 'at': 'x', 'sid': s.id}),
        // ταυτότητα προπόνησης που δεν είναι κείμενο
        WatchCmd('goto', {'i': 'δύο', 'sid': 5}),
      ]) {
        expect(() => link.apply(t, c), returnsNormally, reason: '${c.op} ${c.j}');
      }
      expect(t.current, isNotNull);
      expect(t.current!.id, s.id);
      expect(e.rirAnswer, isNull);
      expect(e.log[0].reps, planned);
      expect(e.log[0].done, isFalse);
    });

    test('επαναλήψεις με σωστές τιμές δουλεύουν όπως πριν', () {
      final t = sampleTraining(now);
      final s = t.start(t.program!.workout('A')!);
      final link = WearLink()..attachForTest(t);
      final e = s.items[0];
      link.apply(t, WatchCmd('reps', {'i': 0, 's': 0, 'v': 7, 'ex': e.ex, 'sid': s.id}));
      expect(e.log[0].reps, 7);
      link.apply(t, WatchCmd('reps', {'i': 0, 's': 0, 'v': 6.0, 'sid': s.id}));
      expect(e.log[0].reps, 6);
    });

    test('παλμοί και εντολή με λάθος είδη στο μήνυμα: κανένα σφάλμα· οι σωστοί παλμοί περνούν', () {
      final link = WearLink();
      expect(() => link.handle('/ygeia/hr', {'bpm': '80', 't': 'x', 'sid': 5}), returnsNormally);
      expect(link.hr.value, isNull);
      expect(() => link.handle('/ygeia/hr', {'bpm': double.infinity, 't': double.infinity}), returnsNormally);
      expect(link.hr.value, isNull);
      // ώρα που δεν χωρά σε ημερομηνία: οι παλμοί μετράνε με την ώρα του κινητού
      expect(() => link.handle('/ygeia/hr', {'bpm': 80, 't': 1e30}), returnsNormally);
      expect(link.hr.value?.$1, 80);
      expect(() => link.handle('/ygeia/cmd', {'op': 7, 'i': 'x', 'sid': 9}), returnsNormally);
    });
  });

  group('Συμβούλιο 5 · Δ4: δόνηση αφής στα − / + της προπόνησης', () {
    Future<List<MethodCall>> pumpStepper(WidgetTester tester, {required bool haptic, VoidCallback? onPlus, VoidCallback? onMinus}) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: Center(child: Stepper2(value: '8', onMinus: onMinus, onPlus: onPlus, button: 44, haptic: haptic))),
      ));
      return calls;
    }

    bool isClick(MethodCall c) => c.method == 'HapticFeedback.vibrate' && c.arguments == 'HapticFeedbackType.selectionClick';

    testWidgets('με haptic: κάθε πάτημα δονεί μία φορά και κάνει τη δουλειά του', (tester) async {
      var plus = 0, minus = 0;
      final calls = await pumpStepper(tester, haptic: true, onPlus: () => plus++, onMinus: () => minus++);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      expect(plus, 1);
      expect(calls.where(isClick).length, 1);
      await tester.tap(find.byIcon(Icons.remove_rounded));
      await tester.pump();
      expect(minus, 1);
      expect(calls.where(isClick).length, 2);
    });

    testWidgets('σβηστό κουμπί δεν δονεί· χωρίς haptic (π.χ. επεξεργαστής προγράμματος) όπως πριν', (tester) async {
      var plus = 0;
      var calls = await pumpStepper(tester, haptic: true, onPlus: () => plus++, onMinus: null);
      await tester.tap(find.byIcon(Icons.remove_rounded));
      await tester.pump();
      expect(calls.where(isClick), isEmpty);
      calls = await pumpStepper(tester, haptic: false, onPlus: () => plus++, onMinus: null);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      expect(plus, 1);
      expect(calls.where(isClick), isEmpty);
    });
  });

  group('Συμβούλιο 7 · ο κανόνας της αντίθεσης ελέγχεται μόνος του', () {
    test('κείμενο και χρώματα κατάστασης διαβάζονται (τουλάχιστον 4,5:1) σε κάθε θέμα, ημέρας και νύχτας', () {
      // Το λευκό ✓ στα σκούρα θέματα είχε γραφτεί ως εύρημα στις 8/11 και έμεινε ως το Συμβούλιο 5, γιατί καμία δοκιμή δεν
      // το έπιανε. Από εδώ και πέρα, ένα νέο θέμα ή μια αλλαγή χρώματος που ρίχνει την αντίθεση κάτω από το όριο κοκκινίζει.
      for (final t in [...Aigaio.dayThemes, ...Aigaio.nightThemes]) {
        final pairs = <(String, Color, Color)>[
          ('κείμενο σε φόντο', t.text, t.background),
          ('κείμενο σε κάρτα', t.text, t.card),
          ('δεύτερο κείμενο σε φόντο', t.textSecondary, t.background),
          ('δεύτερο κείμενο σε κάρτα', t.textSecondary, t.card),
          ('τρίτο κείμενο σε φόντο', t.textTertiary, t.background),
          ('τρίτο κείμενο σε κάρτα', t.textTertiary, t.card),
          ('γράμματα σε κύριο χρώμα', t.onPrimary, t.primary),
          ('προειδοποίηση στο πλαίσιό της', t.warn, t.warnBg),
          ('«καλό» σε κάρτα', t.good, t.card),
          ('«κακό» σε κάρτα', t.bad, t.card),
          ('γράμματα πάνω σε «καλό»', Aigaio.inkOn(t.good), t.good),
          ('γράμματα πάνω σε «κακό»', Aigaio.inkOn(t.bad), t.bad),
        ];
        for (final (name, fg, bg) in pairs) {
          expect(Aigaio.contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: '${t.id}: $name');
        }
      }
    });
  });

  group('Συμβούλιο 5 · Δ5 και Δ6α', () {
    test('οι «πρόσφατες εφαρμογές» δεν δείχνουν την οθόνη· τα στιγμιότυπα του χρήστη δεν κόβονται', () {
      final main = File('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/MainActivity.kt').readAsStringSync();
      expect(main, contains('if (Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)'));
      // όχι το πλήρες «κλείδωμα», που θα έκοβε και τα στιγμιότυπα οθόνης
      expect(main, isNot(contains('LayoutParams.FLAG_SECURE')));
    });

    test('η εξαγωγή λέει ότι το αρχείο δεν είναι κλειδωμένο (κείμενο εγκεκριμένο 13/11)', () {
      final settings = File('lib/pages/settings.dart').readAsStringSync();
      expect(
        settings,
        contains("'Ένα αρχείο στις Λήψεις: φαγητό, προϊόντα, προπονήσεις, ρυθμίσεις. Δεν είναι κλειδωμένο: όποιος το ανοίξει, τα διαβάζει.'"),
      );
    });
  });
}
