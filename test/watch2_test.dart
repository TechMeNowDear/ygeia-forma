// Έλεγχος γ2 του ρολογιού (κλάδος fix-watch2), η πλευρά του κινητού: W2-06 παράλειψη, W2-08 πόσες φορές ήρθαν
// παλμοί, W2-11 περπάτημα 0 λεπτών, W2-14 σφάλμα ρολογιού, W2-15 κάρτα περπατήματος χωρίς παλμούς, W2-19 σειρά των
// επαναλήψεων, W3-15 «κοιτάζω». Όλα τα νούμερα είναι δοκιμαστικά.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/exercise/ex_data.dart';
import 'package:ygeia_forma/pages/training/hr_widgets.dart';
import 'package:ygeia_forma/pages/training/session_page.dart';
import 'package:ygeia_forma/pages/training/training_page.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/wear_link.dart';

import 'training_sample.dart';

final now = DateTime(2026, 11, 20, 18, 0);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ρολόι γ2 · κινητό', () {
    test('W2-06: η παράλειψη πάει στο ρολόι· ✓ από το ρολόι σε παραλειμμένη άσκηση δεν χάνεται', () {
      final t = sampleTraining(now);
      final s = t.start(t.program!.workout('A')!);
      t.skip(s.items[1], true);
      final items = watchSession(t, (id) => id)['items'] as List;
      expect((items[1] as Map)['skip'], 1);
      expect((items[0] as Map).containsKey('skip'), isFalse);
      // ρολόι παλιότερης έκδοσης: ✓ στην άσκηση που παραλείφθηκε εδώ
      final link = WearLink()..attachForTest(t);
      link.apply(t, WatchCmd('tick', {'op': 'tick', 'i': 1, 's': 0, 'sid': s.id}));
      expect(s.items[1].skipped, isFalse);
      expect(s.items[1].log[0].done, isTrue);
    });

    test('W2-19: παλιότερη εντολή επαναλήψεων που φτάνει αργότερα δεν σβήνει τη νεότερη', () {
      final t = sampleTraining(now);
      final s = t.start(t.program!.workout('A')!);
      final link = WearLink()..attachForTest(t);
      void reps(int v, int? q) => link.apply(t, WatchCmd('reps', {'op': 'reps', 'i': 0, 's': 0, 'v': v, 'sid': s.id, if (q != null) 'q': q}));
      reps(9, 101);
      reps(11, 103);
      reps(10, 102); // έφυγε πριν από το 11, έφτασε μετά
      expect(s.items[0].log[0].reps, 11);
      // ρολόι παλιότερης έκδοσης (χωρίς «q»): όπως πριν
      reps(7, null);
      expect(s.items[0].log[0].reps, 7);
    });

    test('W2-11: περπάτημα με «sec» 0 από το ρολόι: τα λεπτά από τις ώρες, όχι 0', () {
      final t = sampleTraining(now);
      final start = now.millisecondsSinceEpoch;
      expect(t.importWatch({'v': 1, 'kind': 'cardio', 'id': 'walk$start', 'start': start, 'end': start + 1800000, 'cardio': {'sec': 0, 'm': 0}}), isTrue);
      final w = t.sessions.firstWhere((x) => x.id == 'w-walk$start');
      expect(w.cardioMinutes, 30);
      expect(w.cardioSec, isNull);
    });

    test('W2-08/W2-14: πόσες φορές ήρθαν παλμοί, τι μπορεί το ρολόι, σφάλμα: μένουν στην προπόνηση', () {
      final t = sampleTraining(now);
      final start = now.millisecondsSinceEpoch;
      expect(
          t.importWatch({
            'v': 1, 'kind': 'cardio', 'id': 'walk$start', 'start': start, 'end': start + 600000, 'cardio': {'sec': 600},
            'hrMode': 'default', 'hrGap': 590, 'hrDel': 1, 'diag': '5s=0 wake=0', 'err': 'SecurityException: location',
          }),
          isTrue);
      final w = t.sessions.firstWhere((x) => x.id == 'w-walk$start');
      final back = Session.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>);
      expect(back.hrDel, 1);
      expect(back.watchDiag, '5s=0 wake=0');
      expect(back.watchErr, 'SecurityException: location');
    });

    test('W2-08: κείμενο κενού: μία φορά ≠ «κάθε λίγα δευτερόλεπτα»· χωρίς όριο δεν «άργησε» καμία ειδοποίηση', () {
      expect(hrGapText(1, '5s', 1, true).$1, 'Οι παλμοί ήρθαν όλοι μαζί, μία φορά. Η ειδοποίηση μπορεί να άργησε.');
      expect(hrGapText(1, '5s', 1, true).$2, isTrue);
      expect(hrGapText(5, '5s', 400, true).$1, startsWith('Οι παλμοί έφταναν κάθε λίγα δευτερόλεπτα'));
      expect(hrGapText(1800, 'default', 300, false).$1, 'Οι παλμοί έλειπαν έως 30′.');
      expect(hrGapText(95, 'default', null, true).$1, 'Μεγαλύτερο κενό στους παλμούς: 95″. Τόσο μπορεί να άργησε η ειδοποίηση.');
    });

    test('W3-15: «κοιτάζω» στο ρολόι μόνο αν υπάρχει ρολόι, με το πόσο ισχύει', () async {
      const ch = MethodChannel('test/wear2');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (c) async {
        calls.add(c);
        return true;
      });
      final link = WearLink(channel: ch, events: const EventChannel('test/wear2/events'));
      await link.sendWatching(const Duration(seconds: 60));
      expect(calls, isEmpty);
      link.knownForTest = true;
      await link.sendWatching(const Duration(seconds: 60));
      await link.sendWatching(Duration.zero);
      expect(calls.map((c) => c.method), ['watching', 'watching']);
      expect(jsonDecode((calls[0].arguments as Map)['json'] as String), {'v': 1, 'ttl': 60000});
      expect(jsonDecode((calls[1].arguments as Map)['json'] as String), {'v': 1, 'ttl': 0});
    });

    testWidgets('W2-15: κάρτα περπατήματος στην Άσκηση, με όριο και χωρίς παλμούς: «δεν σε προσέχει», όχι κενό', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 1600);
      addTearDown(tester.view.reset);
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final t = sampleTraining(now);
      expect(t.hrLimit, isNotNull);
      WearLink.main.live.value = {'kind': 'walk', 'sec': 120, 'm': 300.0, 'bpm': 0, 'at': DateTime.now().millisecondsSinceEpoch};
      addTearDown(() => WearLink.main.live.value = null);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: TrainingPage(training: t, now: now))));
      await tester.pump();
      expect(find.text('ΠΕΡΠΑΤΗΜΑ ΣΤΟ ΡΟΛΟΪ · ΖΩΝΤΑΝΑ'), findsOneWidget);
      expect(find.byType(HrStale), findsOneWidget);
      expect(find.byKey(const ValueKey('hr-limit-off')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  
    test('S3/S4: ώρα του σετ προς το ρολόι· διόρθωση επαναλήψεων μόνο στο ίδιο σετ της ίδιας άσκησης', () {
      final t = sampleTraining(now);
      final s = t.start(t.program!.workout('A')!);
      final e = s.items[0];
      t.tick(e, 0);
      final at = e.log[0].at!;
      final sets = ((watchSession(t, (id) => id)['items'] as List)[0] as Map)['sets'] as List;
      expect((sets[0] as Map)['at'], at);
      expect((sets[1] as Map).containsKey('at'), isFalse);
      final link = WearLink()..attachForTest(t);
      void reps(int v, Map<String, dynamic> extra) => link.apply(t, WatchCmd('reps', {'op': 'reps', 'i': 0, 's': 0, 'v': v, 'sid': s.id, ...extra}));
      // άλλη άσκηση στη θέση 0 (εναλλακτική): αγνοείται
      reps(5, {'ex': 'άλλη', 'at': at});
      expect(e.log[0].reps, isNot(5));
      // άλλη ώρα σετ: αγνοείται
      reps(5, {'ex': e.ex, 'at': at - 60000});
      expect(e.log[0].reps, isNot(5));
      // ίδια άσκηση και ίδιο σετ: γράφεται
      reps(5, {'ex': e.ex, 'at': at});
      expect(e.log[0].reps, 5);
      // ρολόι παλιότερης έκδοσης (χωρίς ex/at): όπως πριν
      reps(6, {});
      expect(e.log[0].reps, 6);
    });

    test('NIT 1: «q» πολύ πιο πίσω (η ώρα του ρολογιού άλλαξε) γίνεται δεκτό', () {
      final t = sampleTraining(now);
      final s = t.start(t.program!.workout('A')!);
      final link = WearLink()..attachForTest(t);
      void reps(int v, int q) => link.apply(t, WatchCmd('reps', {'op': 'reps', 'i': 0, 's': 0, 'v': v, 'sid': s.id, 'q': q}));
      reps(9, 10000000);
      reps(7, 9999000);
      expect(s.items[0].log[0].reps, 9);
      reps(8, 1000);
      expect(s.items[0].log[0].reps, 8);
    });

    testWidgets('S1: «αργή δόνηση» από το ρολόι στην κάρτα ορίου και στη σύνοψη, χωρίς αριθμό', (tester) async {
      expect(RegExp(r'\d').hasMatch(slowAlarmText), isFalse);
      final link = WearLink();
      link.applyWatchState('{"v":1,"lim":140,"planAt":5,"slow":1}');
      expect(link.watchSlow.value, isTrue);
      link.applyWatchState('{"v":1,"lim":140,"planAt":5}');
      expect(link.watchSlow.value, isFalse);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 1600);
      addTearDown(tester.view.reset);
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final t = sampleTraining(now);
      WearLink.main.watchSlow.value = true;
      addTearDown(() => WearLink.main.watchSlow.value = false);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: TrainingPage(training: t, now: now))));
      await tester.pump();
      expect(find.byKey(const ValueKey('train-hr-slow')), findsOneWidget);
      final s = t.sessions.last
        ..limit = 140
        ..hrMode = 'default'
        ..hrGap = 4
        ..hrAvg = 118
        ..hrMax = 130;
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: SummaryPage(training: t, session: s)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('hr-slow')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
});
}
