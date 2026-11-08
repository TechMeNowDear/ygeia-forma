// Ρολόι (8/11): τι στέλνει το κινητό, τι παίρνει από το ρολόι, παλμοί και εντολές στην προπόνηση.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/exercise/ex_data.dart';
import 'package:ygeia_forma/exercise/ex_player.dart';
import 'package:ygeia_forma/pages/training/hr_widgets.dart';
import 'package:ygeia_forma/pages/training/session_page.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/wear_link.dart';

import 'training_sample.dart';

final now = DateTime(2026, 11, 20, 18, 0); // Παρασκευή → Προπόνηση Α

void main() {
  String name(String id) => 'Όνομα $id';

  group('προς το ρολόι', () {
    test('πρόγραμμα με έτοιμους στόχους, όριο παλμών, σημερινή προπόνηση', () {
      final t = sampleTraining(now);
      final j = watchPlan(t, now, name);
      expect(j['approved'], isTrue);
      expect(j['hrLimit'], 140);
      expect(j['today'], 'A');
      final a = (j['workouts'] as List).first as Map;
      expect(a['id'], 'A');
      final press = (a['items'] as List).first as Map;
      expect(press['name'], 'Όνομα db_press');
      final sets = press['sets'] as List;
      expect(sets.length, 3);
      // ίδιος στόχος με του κινητού: 12, 12, 12 την προηγούμενη φορά → 10,3 kg × 8
      expect(sets.first, {'load': 10.3, 'label': '10,3 kg', 'reps': 8});
      final crunch = (a['items'] as List).last as Map;
      expect((crunch['sets'] as List).first['label'], '');
      final walk = (j['workouts'] as List).last as Map;
      expect(walk['cardio']['minutes'], 30);
      // ό,τι στέλνεται πρέπει να γίνεται JSON
      expect(() => jsonEncode(j), returnsNormally);
    });

    test('χωρίς έγκριση: το ρολόι το ξέρει', () {
      final j = watchPlan(sampleTraining(now, approved: false), now, name);
      expect(j['approved'], isFalse);
      expect(j.containsKey('hrLimit'), isFalse);
    });

    test('προπόνηση του κινητού: ενεργή με σετ που έγιναν, μετά ανενεργή', () {
      final t = sampleTraining(now);
      expect(watchSession(t, name), {'active': false});
      final s = t.start(t.program!.workout('A')!);
      t.tick(s.items.first, 0);
      t.restEnd = now.add(const Duration(seconds: 120));
      final j = watchSession(t, name);
      expect(j['active'], isTrue);
      expect(j['id'], s.id);
      expect(j['restEnd'], now.add(const Duration(seconds: 120)).millisecondsSinceEpoch);
      final sets = ((j['items'] as List).first as Map)['sets'] as List;
      expect(sets[0]['done'], isTrue);
      expect((sets[1] as Map).containsKey('done'), isFalse);
      t.discard();
      expect(watchSession(t, name)['active'], isFalse);
      expect(t.restEnd, isNull);
    });
  });

  group('από το ρολόι', () {
    Map<String, dynamic> strength() => {
          'v': 1,
          'id': 'w1',
          'kind': 'strength',
          'w': 'A',
          'name': 'Προπόνηση Α',
          'start': now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
          'end': now.millisecondsSinceEpoch,
          'items': [
            {
              'ex': 'db_press',
              'sets': 3,
              'lo': 8,
              'hi': 12,
              'rir': 2,
              'rest': 120,
              'ra': 2,
              'log': [
                for (var i = 0; i < 3; i++) {'l': 10.3, 'r': 8, 'd': 1, 't': 1},
              ],
            },
          ],
          'hrAvg': 112,
          'hrMax': 138,
          'hr': [
            [0, 100],
            [10, 120],
          ],
        };

    test('προπόνηση μόνο στο ρολόι: μπαίνει στο ιστορικό, μία φορά', () {
      final t = sampleTraining(now);
      expect(t.importWatch(strength()), isTrue);
      expect(t.importWatch(strength()), isFalse);
      final s = t.sessions.last;
      expect(s.source, 'watch');
      expect(s.hrMax, 138);
      expect(s.hr.length, 2);
      expect(t.historyOf('db_press').first.$2.workLoad, 10.3);
      // στη σωστή θέση με τη σειρά των ημερομηνιών
      for (var i = 1; i < t.sessions.length; i++) {
        expect(t.sessions[i].start.isBefore(t.sessions[i - 1].start), isFalse);
      }
    });

    test('περπάτημα: λεπτά, km, βήματα, χωρίς να πειράζει την πρόοδο', () {
      final t = sampleTraining(now);
      t.importWatch({
        'v': 1,
        'id': 'walk1',
        'kind': 'cardio',
        'w': 'walk',
        'name': 'Περπάτημα',
        'start': now.subtract(const Duration(minutes: 31)).millisecondsSinceEpoch,
        'end': now.millisecondsSinceEpoch,
        'items': [],
        'cardio': {'activity': 'walk', 'sec': 1830, 'm': 2180.0, 'steps': 3104},
        'hrAvg': 104,
        'hrMax': 118,
      });
      final s = t.sessions.last;
      expect(s.isCardio, isTrue);
      expect(s.cardioMinutes, 31);
      expect(s.meters, 2180);
      expect(s.steps, 3104);
      expect(t.historyOf('db_press').length, 2);
      final back = Session.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.steps, 3104);
      expect(back.source, 'watch');
      expect(t.exportForClaude(), contains('Περπάτημα: 1 φορές, 31 λεπτά, 2.2 km'));
    });

    test('παλμοί προπόνησης του κινητού: συμπληρώνονται αν χάθηκαν μηνύματα', () {
      final t = sampleTraining(now);
      final s = t.start(t.program!.workout('A')!);
      t.tick(s.items.first, 0);
      t.finish(feel: 3);
      expect(t.sessions.last.hrMax, isNull);
      expect(t.importWatch({'v': 1, 'kind': 'hr', 'sid': s.id, 'hrAvg': 115, 'hrMax': 141, 'hr': [[0, 110], [10, 141]]}), isTrue);
      expect(t.sessions.last.hrMax, 141);
      expect(t.sessions.last.hrAvg, 115);
      expect(HrSummary(t.sessions.last, 140).overSec, 10);
      expect(t.importWatch({'v': 1, 'kind': 'hr', 'sid': 'άγνωστο'}), isFalse);
      // πώς έφταναν οι παλμοί (8/11): μένει στην προπόνηση και φαίνεται στη σύνοψη
      expect(t.importWatch({'v': 1, 'kind': 'hr', 'sid': s.id, 'hrMode': '5s', 'hrGap': 6}), isTrue);
      expect(t.sessions.last.hrMode, '5s');
      expect(t.sessions.last.hrGap, 6);
      final back = Session.fromJson(jsonDecode(jsonEncode(t.sessions.last.toJson())) as Map<String, dynamic>);
      expect(back.hrGap, 6);
    });

    test('ζωντανοί παλμοί: δείγμα ανά 10″ στην προπόνηση που τρέχει', () {
      final t = sampleTraining(now);
      final link = WearLink()..attachForTest(t);
      final s = t.start(t.program!.workout('A')!);
      for (var i = 0; i < 6; i++) {
        link.handle('/ygeia/hr', {'bpm': 100 + i, 't': now.add(Duration(seconds: 5 * i)).millisecondsSinceEpoch, 'sid': s.id});
      }
      link.handle('/ygeia/hr', {'bpm': 150, 't': now.add(const Duration(seconds: 40)).millisecondsSinceEpoch, 'sid': 'άλλη'});
      expect(s.hr.map((p) => p[0]).toList(), [0, 10, 20]);
      expect(s.hrMax, 105);
      expect(link.bpmAt(now.add(const Duration(seconds: 30))), 150);
      expect(link.bpmAt(now.add(const Duration(seconds: 60))), isNull);
      t.finish();
      expect(t.sessions.last.hrAvg, ((100 + 102 + 104) / 3).round());
    });
  });

  group('έλεγχος 8/11', () {
    test('εντολές ρολογιού γράφονται και χωρίς ανοιχτή οθόνη προπόνησης', () {
      final t = sampleTraining(now);
      final link = WearLink()..attachForTest(t);
      final s = t.start(t.program!.workout('A')!);
      link.handle('/ygeia/cmd', {'op': 'tick', 'i': 0, 's': 0, 'sid': s.id});
      expect(s.items.first.log.first.done, isTrue);
      expect(t.restEnd, isNotNull);
      link.handle('/ygeia/cmd', {'op': 'rest', 'v': 'stop', 'sid': s.id});
      expect(t.restEnd, isNull);
      // ρεζέρβα για άσκηση που δεν τελείωσε: αγνοείται (να μη γραφτεί σε λάθος άσκηση)
      link.handle('/ygeia/cmd', {'op': 'rir', 'i': 1, 'v': 0, 'sid': s.id});
      expect(s.items[1].rirAnswer, isNull);
      link.handle('/ygeia/cmd', {'op': 'tick', 'i': 0, 's': 1, 'sid': s.id});
      link.handle('/ygeia/cmd', {'op': 'tick', 'i': 0, 's': 2, 'sid': s.id});
      expect(t.focus, 1);
      link.handle('/ygeia/cmd', {'op': 'rir', 'i': 0, 'v': 3, 'sid': s.id});
      expect(s.items.first.rirAnswer, 3);
      // δεύτερη απάντηση για την ίδια άσκηση δεν αλλάζει την πρώτη
      link.handle('/ygeia/cmd', {'op': 'rir', 'i': 0, 'v': 0, 'sid': s.id});
      expect(s.items.first.rirAnswer, 3);
    });

    test('στο τέλος, τα σετ του ρολογιού συμπληρώνουν όσα χάθηκαν στο κινητό', () {
      final t = sampleTraining(now);
      final s = t.start(t.program!.workout('A')!);
      t.tick(s.items.first, 0);
      final items = [
        for (final e in s.items) e.toJson(),
      ];
      final log = (items.first['log'] as List).cast<Map<String, dynamic>>();
      log[1] = {...log[1], 'd': 1, 'r': 9, 't': now.millisecondsSinceEpoch};
      log[2] = {...log[2], 'd': 1, 'r': 8, 't': now.millisecondsSinceEpoch};
      items.first['ra'] = 2;
      // το κινητό είχε ήδη γράψει το 1ο σετ με άλλες επαναλήψεις: μένει όπως είναι
      final first = s.items.first.log.first.reps;
      expect(t.importWatch({'v': 1, 'kind': 'hr', 'sid': s.id, 'items': jsonDecode(jsonEncode(items))}), isTrue);
      expect(s.items.first.done.length, 3);
      expect(s.items.first.log[1].reps, 9);
      expect(s.items.first.log.first.reps, first);
      expect(s.items.first.rirAnswer, 2);
      expect(s.items[1].done, isEmpty);
    });

    test('σύνοψη: όταν ο υψηλότερος έφτασε το όριο, όχι «Δεν ξεπέρασες»', () {
      final t = sampleTraining(now);
      final s = t.sessions.last
        ..hrMax = 141
        ..hr.addAll([
          [0, 100],
          [10, 130],
        ]);
      expect(HrSummary(s, 140).overSec, 0);
      expect(HrSummary(s, 140).max, 141);
    });
  });

  group('οθόνες', () {
    setUp(() => ExClock.frozen = true);

    testWidgets('✓ από το ρολόι: γράφεται στο κινητό και ξεκινά διάλειμμα· παλμοί πάνω', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 900);
      addTearDown(tester.view.reset);
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final t = sampleTraining(now);
      final s = t.start(t.program!.workout('A')!);
      WearLink.main.attachForTest(t);
      WearLink.main.hr.value = (128, DateTime.now());
      addTearDown(() => WearLink.main.hr.value = null);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: SessionPage(training: t)));
      await tester.pump();
      expect(find.byType(HrBar), findsOneWidget);
      expect(find.text('128'), findsOneWidget);
      WearLink.main.handle('/ygeia/cmd', {'op': 'tick', 'i': 0, 's': 0, 'sid': s.id});
      await tester.pump();
      await tester.pump();
      expect(s.items.first.log.first.done, isTrue);
      expect(t.restEnd, isNotNull);
      expect(find.byKey(const ValueKey('rest-stop')), findsOneWidget);
      WearLink.main.handle('/ygeia/cmd', {'op': 'rest', 'v': 'stop', 'sid': s.id});
      await tester.pump();
      await tester.pump();
      expect(t.restEnd, isNull);
      WearLink.main.handle('/ygeia/cmd', {'op': 'goto', 'i': 2, 'sid': s.id});
      await tester.pump();
      await tester.pump();
      expect(t.focus, 2);
      // ρεζέρβα από το ρολόι για άσκηση που δεν τελείωσε: αγνοείται (έλεγχος 8/11)
      WearLink.main.handle('/ygeia/cmd', {'op': 'rir', 'i': 0, 'v': 3, 'sid': s.id});
      await tester.pump();
      expect(s.items.first.rirAnswer, isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('σύνοψη: κάρτα παλμών με το όριο', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 1400);
      addTearDown(tester.view.reset);
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final t = sampleTraining(now);
      final s = t.sessions.last
        ..hrAvg = 118
        ..hrMax = 136
        ..hr.addAll([
          [0, 100],
          [600, 130],
          [1200, 136],
        ]);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: SummaryPage(training: t, session: s)));
      await tester.pumpAndSettle();
      expect(find.byType(HrCard), findsOneWidget);
      expect(find.text('Δεν ξεπέρασες το όριο (140).'), findsOneWidget);
      s.hrMax = 141;
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: SummaryPage(training: t, session: s, key: UniqueKey())));
      await tester.pumpAndSettle();
      expect(find.text('Δεν ξεπέρασες το όριο (140).'), findsNothing);
      expect(find.text('Έφτασες στιγμιαία το όριο (140).'), findsOneWidget);
      // μεγάλο κενό στους παλμούς: φαίνεται
      s.hrGap = 95;
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: SummaryPage(training: t, session: s, key: UniqueKey())));
      await tester.pumpAndSettle();
      expect(find.textContaining('Μεγαλύτερο κενό στους παλμούς: 95″'), findsOneWidget);
    });

    testWidgets('παλμοί που σταμάτησαν να έρχονται: πορτοκαλί μήνυμα, όχι κενό', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 900);
      addTearDown(tester.view.reset);
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final t = sampleTraining(now);
      t.start(t.program!.workout('A')!);
      WearLink.main.attachForTest(t);
      WearLink.main.hr.value = (128, DateTime.now().subtract(const Duration(minutes: 2)));
      addTearDown(() => WearLink.main.hr.value = null);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: SessionPage(training: t)));
      await tester.pump();
      expect(find.byType(HrBar), findsNothing);
      expect(find.byKey(const ValueKey('hr-stale')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
