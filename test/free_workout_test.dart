// 9/11: «Ελεύθερη άσκηση»: χωρίς πρόγραμμα, οι ασκήσεις μπαίνουν μία-μία· το ρολόι ακολουθεί.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/exercise/ex_data.dart';
import 'package:ygeia_forma/exercise/ex_player.dart';
import 'package:ygeia_forma/pages/training/ex_picker.dart';
import 'package:ygeia_forma/pages/training/session_page.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/training_store.dart';
import 'package:ygeia_forma/training/wear_link.dart';

import 'training_sample.dart';

final now = DateTime(2026, 11, 20, 18, 0);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('αποθήκη', () {
    test('ξεκινά άδεια· για το ρολόι: ενεργή, χωρίς ασκήσεις, θέση 0', () {
      final t = sampleTraining(now);
      final s = t.startFree();
      expect(s.isFree, isTrue);
      expect(s.workout, freeWorkoutId);
      expect(s.items, isEmpty);
      final w = watchSession(t, (x) => x);
      expect(w['active'], isTrue);
      expect(w['idx'], 0);
      expect(w['items'], isEmpty);
    });

    test('άσκηση του προγράμματος: σετ, επαναλήψεις, διάλειμμα όπως στο πρόγραμμα· κιλά από το ιστορικό', () {
      final t = sampleTraining(now);
      t.startFree();
      final e = t.addExercise('incline_curl')!;
      expect((e.sets, e.lo, e.hi, e.rest), (3, 10, 15, 75));
      // Ίδιος στόχος με την προπόνηση Α του προγράμματος.
      final a = t.program!.workout('A')!.items.firstWhere((i) => i.ex == 'incline_curl');
      expect(e.log.map((x) => x.load).toSet(), {t.targetFor(a).load});
      expect(t.focus, 0);
    });

    test('άσκηση εκτός προγράμματος: 3 σετ, 8–12, διάλειμμα 90″· γίνεται η τρέχουσα', () {
      final t = sampleTraining(now);
      t.startFree();
      t.addExercise('db_press');
      final e = t.addExercise('lateral_raise')!;
      expect((e.sets, e.lo, e.hi, e.rest), (3, 8, 12, 90));
      expect(t.focus, 1);
    });

    test('χωρίς πρόγραμμα δουλεύει κανονικά', () {
      final t = sampleTraining(now, program: false, history: false);
      t.startFree();
      expect(t.addExercise('goblet')!.sets, 3);
    });

    test('γράφεται, μένει μετά από φόρτωμα, μετρά στο ιστορικό της άσκησης', () async {
      final io = MemoryTrainingIO();
      final t = TrainingStore(io: io, clock: () => now)..replaceAll(sampleTraining(now).toJson());
      final before = t.historyOf('lateral_raise').length;
      t.startFree();
      final e = t.addExercise('lateral_raise')!;
      t.tick(e, 0);
      t.finish();
      await t.save();
      final back = TrainingStore(io: io, clock: () => now);
      await back.load();
      final s = back.sessions.last;
      expect(s.isFree, isTrue);
      expect(s.items.single.ex, 'lateral_raise');
      expect(back.historyOf('lateral_raise').length, before + 1);
    });

    test('✓ από το ρολόι στο τελευταίο σετ: διάλειμμα ως τη νέα άσκηση', () {
      final t = sampleTraining(now);
      t.ready = true;
      final s = t.startFree();
      final e = t.addExercise('lateral_raise')!;
      final link = WearLink();
      for (var k = 0; k < e.sets; k++) {
        link.apply(t, WatchCmd('tick', {'op': 'tick', 'i': 0, 's': k, 'sid': s.id}));
      }
      expect(e.complete, isTrue);
      expect(t.restEnd, now.add(Duration(seconds: e.rest)));
    });

    test('εντολές του ρολογιού σε άδεια ελεύθερη: τίποτα, χωρίς σφάλμα', () {
      final t = sampleTraining(now);
      final s = t.startFree();
      final link = WearLink();
      link.apply(t, WatchCmd('tick', {'op': 'tick', 'i': 0, 's': 0, 'sid': s.id}));
      link.apply(t, WatchCmd('goto', {'op': 'goto', 'i': 0, 'sid': s.id}));
      link.apply(t, WatchCmd('rir', {'op': 'rir', 'i': 0, 'v': 2, 'sid': s.id}));
      expect(s.items, isEmpty);
    });
  });

  group('αναζήτηση', () {
    test('χωρίς τόνους, με μυ, με όργανο', () async {
      final lib = await ExLibrary.load(inline: true);
      List<String> q(String s) => [for (final e in lib.list) if (exMatches(e, s)) e.id];
      expect(q('πιεστικο'), containsAll(['db_press', 'incline_press']));
      expect(q('ΚΟΙΛΙΑΚΟΙ'), contains('crunch'));
      expect(q('λαστιχο'), contains('band_pushdown'));
      expect(q('zzzz'), isEmpty);
    });
  });

  group('οθόνη', () {
    setUp(() => ExClock.frozen = true);

    testWidgets('άδεια → πρόσθεσε → άσκηση στην οθόνη · «Νέα άσκηση» · ίδια άσκηση ξανά: δεν διπλασιάζεται', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 900);
      addTearDown(tester.view.reset);
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final t = sampleTraining(now)..ready = true;
      t.startFree();
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: SessionPage(training: t)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('free-empty')), findsOneWidget);

      Future<void> pick(String search, String id) async {
        await tester.enterText(find.byKey(const ValueKey('pick-search')), search);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('pick-$id')));
        await tester.pumpAndSettle();
      }

      await tester.tap(find.byKey(const ValueKey('free-add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pick-sheet')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('pick-search')), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.textContaining('Καμία άσκηση'), findsOneWidget);
      await pick('πλαγιες', 'lateral_raise');
      expect(t.current!.items.single.ex, 'lateral_raise');
      expect(find.text('Πλάγιες ανυψώσεις'), findsWidgets);
      expect(find.text('Νέα άσκηση'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('sess-next')));
      await tester.pumpAndSettle();
      await pick('crunch', 'crunch');
      expect(t.current!.items.map((e) => e.ex), ['lateral_raise', 'crunch']);
      expect(t.focus, 1);

      // Ήδη μέσα: πάει σε αυτή, δεν μπαίνει δεύτερη φορά.
      await tester.tap(find.byKey(const ValueKey('sess-next')));
      await tester.pumpAndSettle();
      await pick('πλαγιες', 'lateral_raise');
      expect(t.current!.items.length, 2);
      expect(t.focus, 0);

      // Μεγάλη οθόνη (Fold ανοιχτό, tablet): «+ Άσκηση» κάτω από τη λίστα αριστερά.
      tester.view.physicalSize = const Size(1000, 800);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('free-add-chip')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('free-add-chip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pick-sheet')), findsOneWidget);
    });

    testWidgets('«Τέλος» χωρίς κανένα σετ: ρωτά για σβήσιμο', (tester) async {
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final t = sampleTraining(now)..ready = true;
      t.startFree();
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: SessionPage(training: t)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sess-finish')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sess-drop')));
      await tester.pumpAndSettle();
      expect(t.current, isNull);
    });
  });
}
