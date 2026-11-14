// Προπόνηση (8/11): εξοπλισμός, πρόοδος, πρόγραμμα, αποθήκη, οθόνες.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/exercise/ex_data.dart';
import 'package:ygeia_forma/exercise/ex_player.dart';
import 'package:ygeia_forma/pages/training/program_paste.dart';
import 'package:ygeia_forma/pages/training/session_page.dart';
import 'package:ygeia_forma/pages/training/training_page.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/training/equipment.dart';
import 'package:ygeia_forma/training/progression.dart';
import 'package:ygeia_forma/training/program.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/training_store.dart';

import 'training_sample.dart';

final now = DateTime(2026, 11, 20, 18, 0); // Παρασκευή

ExLog log(String ex, double? load, List<int> reps, {int? rir, int lo = 8, int hi = 12, List<String> pain = const []}) => ExLog(
      ex: ex,
      sets: reps.length,
      lo: lo,
      hi: hi,
      rir: 2,
      rest: 90,
      rirAnswer: rir,
      pain: List.of(pain),
      log: [for (final r in reps) SetLog(load: load, reps: r, done: true)],
    );

void main() {
  final lib = ExLibrary.fromJson(jsonDecode(File('assets/exercises/exercises.json').readAsStringSync()) as Map<String, dynamic>);
  final ids = {for (final e in lib.list) e.id};

  group('εξοπλισμός', () {
    test('κάθε άσκηση της βιβλιοθήκης έχει είδος φορτίου', () {
      for (final id in ids) {
        expect(exerciseLoad.containsKey(id), isTrue, reason: id);
      }
    });

    test('βάρη από τους δίσκους: αλτήρες, μπάρα, kettlebell, λάστιχα', () {
      final db = available(LoadKind.dbPair);
      expect(db, containsAll([1.8, 2.8, 4.3, 5.3, 6.8, 9.3, 11.8, 14.3, 16.8, 20.3]));
      expect(db.last, 20.3);
      final bar = available(LoadKind.bar);
      expect(bar.first, 10);
      expect(bar.last, 47);
      expect(bar, contains(21));
      expect(stepUp(LoadKind.bar, 20), 21);
      expect(stepUp(LoadKind.dbPair, 9.3), 10.3);
      expect(stepUp(LoadKind.kb, 12), 16);
      expect(stepUp(LoadKind.kb, 16), isNull);
      expect(stepUp(LoadKind.bandAssist, 50), 40);
      expect(stepUp(LoadKind.bandAssist, 10), 0);
      expect(bandText(60), 'μαύρο + μπλε (60 lb)');
      expect(bandText(0), 'χωρίς λάστιχο');
    });

    test('στήσιμο και αλλαγή δίσκων σε απλά λόγια', () {
      expect(setupText(LoadKind.bar, 20), 'μπάρα 10 + ανά πλευρά 5');
      expect(setupText(LoadKind.bar, 21), 'μπάρα 10 + ανά πλευρά 5 + 0,5');
      expect(setupText(LoadKind.dbPair, 14.3), 'λαβή + ανά άκρη 5 + 1,25, και στους δύο αλτήρες');
      expect(setupText(LoadKind.db, 14.3), 'λαβή + ανά άκρη 5 + 1,25');
      expect(plateChange(LoadKind.dbPair, 11.8, LoadKind.db, 14.3), 'βάλε 1,25 σε κάθε άκρη');
      expect(plateChange(LoadKind.dbPair, 14.3, LoadKind.dbPair, 11.8), 'βγάλε 1,25 σε κάθε άκρη');
      expect(plateChange(LoadKind.dbPair, 9.3, LoadKind.dbPair, 9.3), 'ίδιοι δίσκοι');
      expect(plateChange(LoadKind.kb, 12, LoadKind.dbPair, 9.3), isNull);
      expect(kgText(11.8), '11,8');
      expect(kgText(1.25), '1,25');
    });
  });

  group('πρόοδος', () {
    PlanItem item(String ex, {double? load, int lo = 8, int hi = 12, String? next}) =>
        PlanItem(ex: ex, sets: 3, lo: lo, hi: hi, rir: 2, rest: 90, load: load, next: next);
    final d = now.subtract(const Duration(days: 3));

    test('πρώτη φορά: από το πρόγραμμα, στο πλησιέστερο που βγαίνει', () {
      final t = nextTarget(item('db_press', load: 10), const [], now);
      expect(t.change, Change.first);
      expect(t.load, 9.3);
      expect(t.reps, [8, 8, 8]);
    });

    test('όλα στο πάνω όριο με ρεζέρβα → ανεβαίνει το βάρος, ξανά από το κάτω όριο', () {
      final t = nextTarget(item('db_press'), [(d, log('db_press', 9.3, [12, 12, 12], rir: 2))], now);
      expect(t.change, Change.up);
      expect(t.load, 10.3);
      expect(t.reps, [8, 8, 8]);
    });

    test('μέσα στο εύρος → ίδιο βάρος, +1 επανάληψη', () {
      final t = nextTarget(item('db_press'), [(d, log('db_press', 9.3, [10, 10, 9], rir: 2))], now);
      expect(t.change, Change.more);
      expect(t.load, 9.3);
      expect(t.reps, [11, 11, 10]);
    });

    test('στο πάνω όριο αλλά χωρίς ρεζέρβα → μένει', () {
      final t = nextTarget(item('db_press'), [(d, log('db_press', 9.3, [12, 12, 12], rir: 0))], now);
      expect(t.change, Change.hold);
      expect(t.load, 9.3);
    });

    test('δύο φορές κάτω από το εύρος με το ίδιο βάρος → ένα σκαλί κάτω', () {
      final h = [(d, log('db_press', 11.8, [8, 7, 6])), (d.subtract(const Duration(days: 3)), log('db_press', 11.8, [8, 7, 7]))];
      final t = nextTarget(item('db_press'), h, now);
      expect(t.change, Change.down);
      expect(t.load, 10.3);
    });

    test('μία φορά κάτω από το εύρος → μένει, στόχος το κάτω όριο', () {
      final t = nextTarget(item('db_press'), [(d, log('db_press', 11.8, [8, 7, 6]))], now);
      expect(t.change, Change.hold);
      expect(t.reps, [8, 8, 8]);
    });

    test('ενόχληση → ένα σκαλί πιο ελαφριά (R7-A6-3, f2: πριν «τίποτα δεν ανεβαίνει», ίδια κιλά)', () {
      final t = nextTarget(item('db_press'), [(d, log('db_press', 9.3, [12, 12, 12], rir: 3, pain: ['shoulderR']))], now);
      expect(t.change, Change.pain);
      expect(t.load, 7.8);
      expect(t.reason, contains('δεξιός ώμος'));
    });

    test('διάλειμμα πάνω από 2 εβδομάδες → περίπου 10% κάτω', () {
      final t = nextTarget(item('db_press'), [(now.subtract(const Duration(days: 20)), log('db_press', 11.8, [12, 12, 12], rir: 2))], now);
      expect(t.change, Change.back);
      expect(t.load, 10.3);
    });

    test('μπάρα: με ρεζέρβα κάτω από 2 ποτέ αύξηση', () {
      final t = nextTarget(item('rdl'), [(d, log('rdl', 20, [12, 12, 12], rir: 1))], now);
      expect(t.change, Change.hold);
      expect(t.load, 20);
    });

    test('χωρίς απάντηση για ρεζέρβα: ποτέ περισσότερα κιλά', () {
      final t = nextTarget(item('db_press'), [(d, log('db_press', 9.3, [12, 12, 12]))], now);
      expect(t.change, Change.hold);
      expect(t.load, 9.3);
      expect(t.reason, contains('δεν ξέρουμε'));
    });

    test('χωρίς απάντηση, μέσα στο εύρος: +1 μόνο σε απλή άσκηση, όχι σε μπάρα ή άσκηση προσοχής', () {
      final plain = nextTarget(item('db_press'), [(d, log('db_press', 9.3, [10, 10, 9]))], now);
      expect(plain.change, Change.more);
      expect(plain.reps, [11, 11, 10]);
      final bar = nextTarget(item('rdl'), [(d, log('rdl', 20, [10, 10, 9]))], now);
      expect(bar.change, Change.hold);
      expect(bar.reps, [10, 10, 9]);
      final careful = nextTarget(item('dips'), [(d, log('dips', null, [10, 10, 9]))], now, caution: true);
      expect(careful.change, Change.hold);
    });

    test('στο όριο (0 ρεζέρβα) μέσα στο εύρος: ίδιες επαναλήψεις, όχι +1', () {
      final t0 = nextTarget(item('db_press'), [(d, log('db_press', 9.3, [10, 10, 9], rir: 0))], now);
      expect(t0.change, Change.hold);
      expect(t0.reps, [10, 10, 9]);
      final t1 = nextTarget(item('db_press'), [(d, log('db_press', 9.3, [10, 10, 9], rir: 1))], now);
      expect(t1.change, Change.hold);
    });

    test('kettlebell: πριν το μεγάλο άλμα 12 → 16, πρώτα 3 επαναλήψεις παραπάνω', () {
      final t1 = nextTarget(item('goblet'), [(d, log('goblet', 12, [12, 12, 12], rir: 3))], now);
      expect(t1.change, Change.more);
      expect(t1.reps, [13, 13, 13]);
      final t2 = nextTarget(item('goblet'), [(d, log('goblet', 12, [15, 15, 15], rir: 2))], now);
      expect(t2.change, Change.up);
      expect(t2.load, 16);
    });

    // Round 1 (f6a · S7-03): η παραλλαγή είναι μεγάλο σκαλί (πάτωμα ≈ +39% του βάρους που σηκώνεις, Ebben 2011)· πρώτα
    // 5 επαναλήψεις πάνω από το εύρος (πριν: στο πάνω όριο, 15).
    test('σώμα: 5 επαναλήψεις πάνω από το εύρος → πρόταση για πιο δύσκολη παραλλαγή', () {
      final at15 = nextTarget(item('pushup_bench', lo: 10, hi: 15, next: 'pushup_handles'), [(d, log('pushup_bench', null, [15, 15, 15], rir: 2, lo: 10, hi: 15))], now);
      expect(at15.change, Change.more);
      expect(at15.reps, [16, 16, 16]);
      final t = nextTarget(item('pushup_bench', lo: 10, hi: 15, next: 'pushup_handles'), [(d, log('pushup_bench', null, [20, 20, 20], rir: 2, lo: 10, hi: 15))], now);
      expect(t.change, Change.variant);
      expect(t.variant, 'pushup_handles');
    });

    test('λάστιχο βοήθειας: η πρόοδος είναι λιγότερη βοήθεια', () {
      final t = nextTarget(item('assisted_pullup', lo: 5, hi: 8), [(d, log('assisted_pullup', 50, [8, 8, 8], rir: 2, lo: 5, hi: 8))], now);
      expect(t.change, Change.up);
      expect(t.load, 40);
    });

    test('βαθμονόμηση πρώτης φοράς μετά το 1ο σετ', () {
      final i = item('db_press', load: 9.3);
      expect(calibrate(i, 9.3, 10, 4), 10.3);
      expect(calibrate(i, 9.3, 6, 0), 7.8);
      expect(calibrate(i, 9.3, 10, 2), isNull);
    });
  });

  group('πρόγραμμα', () {
    test('επικόλληση με κείμενο γύρω του', () {
      final r = parseProgram(sampleProgramText, ids);
      expect(r.ok, isTrue, reason: r.errors.join('\n'));
      final p = r.program!;
      expect(p.author, 'claude');
      expect(p.forDay(DateTime(2026, 11, 13))!.id, 'A'); // Παρασκευή
      expect(p.forDay(DateTime(2026, 11, 17))!.isCardio, isTrue); // Τρίτη
      expect(p.workout('B')!.items.length, 7);
    });

    test('λάθη σε απλά ελληνικά', () {
      expect(parseProgram('καλημέρα', ids).errors.single, contains('Δεν βρέθηκε πρόγραμμα'));
      expect(parseProgram('{"kind":"ygeia-program",', ids).ok, isFalse);
      final bad = parseProgram('{"kind":"ygeia-program","workouts":[{"id":"A","name":"Α","items":[{"ex":"bench_press","sets":3,"reps":[5,5]}]}],"days":{"mon":"Z"}}', ids);
      expect(bad.errors.join(' '), contains('Άγνωστη άσκηση «bench_press»'));
      expect(bad.errors.join(' '), contains('Δευτέρα'));
    });

    test('Β4: τα λεπτά της αερόβιας σε πρόγραμμα που επικολλάς, από 1 ως 600 (κείμενο εγκρίθηκε 12/11)', () {
      PasteResult paste(Object minutes) => parseProgram(
          '{"kind":"ygeia-program","workouts":[{"id":"W","name":"Περπάτημα","cardio":{"activity":"walk","minutes":$minutes}}]}', ids);
      expect((cardioMinMinutes, cardioMaxMinutes), (1, 600));
      for (final ok in [1, 30, 180, 600]) {
        expect(paste(ok).ok, isTrue, reason: '$ok');
      }
      for (final bad in [0, -5, 601, 100000]) {
        final r = paste(bad);
        expect(r.ok, isFalse, reason: '$bad');
        expect(r.errors.single, 'Περπάτημα: τα λεπτά της αερόβιας πρέπει να είναι από 1 ως 600.', reason: '$bad');
      }
      // Αριθμός που δεν στέκει καθόλου («άπειρο»): το πρόγραμμα έχει λάθος μορφή, όχι σφάλμα της εφαρμογής.
      expect(paste('1e999').errors.single, contains('λάθος μορφή'));
      // Η προπόνηση με βάρη δεν επηρεάζεται.
      expect(parseProgram(sampleProgramText, ids).ok, isTrue);
    });

    test('ασφάλεια: μπάρα με ρεζέρβα 2, βάρη που βγαίνουν με τους δίσκους', () {
      final r = parseProgram('{"kind":"ygeia-program","workouts":[{"id":"A","name":"Α","items":[{"ex":"rdl","rir":0,"load":20},{"ex":"db_press","load":10}]}]}', ids);
      expect(r.ok, isTrue);
      final items = r.program!.workout('A')!.items;
      expect(items[0].rir, 2);
      expect(items[1].load, 9.3);
      expect(r.warnings.length, 2);
    });

    test('JSON μπρος-πίσω χωρίς απώλειες', () {
      final p = sampleProgram();
      final q = Program.fromJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
      expect(jsonEncode(q.toJson()), jsonEncode(p.toJson()));
    });
  });

  group('αποθήκη', () {
    test('προπόνηση: στόχοι από την πρόοδο, σετ, τέλος, ιστορικό, αποθήκευση', () async {
      final io = MemoryTrainingIO();
      final t = sampleTraining(now);
      final t2 = TrainingStore(io: io, clock: () => now)..replaceAll(jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>);
      final s = t2.start(t2.program!.workout('A')!);
      final press = s.items.first;
      expect(press.log.first.load, 10.3); // 12, 12, 12 την προηγούμενη φορά
      expect(press.reason, contains('ανέβα'));
      final push = s.items.firstWhere((e) => e.ex == 'band_pushdown');
      // Round 7 (f2 · R7-A6-3): μετά από ενόχληση ένα σκαλί πιο ελαφριά· η πρόταση μπορεί να αρχίζει με «Ενόχληση…».
      expect(push.reason!.toLowerCase(), contains('ενόχληση'));
      for (var i = 0; i < 3; i++) {
        t2.tick(press, i);
      }
      t2.answer(press, 2);
      t2.finish(feel: 3);
      await t2.save();
      expect(t2.current, isNull);
      expect(t2.historyOf('db_press').first.$2.workLoad, 10.3);
      final back = TrainingStore(io: io, clock: () => now);
      await back.load();
      expect(back.sessions.length, 3);
      expect(back.program!.name, 'Πρόγραμμα 1');
      expect(back.hrLimit, 140);
    });

    test('νέα έκδοση προγράμματος: το ιστορικό μένει', () {
      final t = sampleTraining(now);
      final p = t.program!.copy()..name = 'Πρόγραμμα 1β';
      final saved = t.saveProgram(p);
      expect(saved.version, 2);
      expect(t.program!.name, 'Πρόγραμμα 1β');
      expect(t.historyOf('db_press').length, 2);
    });

    test('αν το αρχείο δεν διαβάζεται, δεν γράφεται τίποτα', () async {
      final io = MemoryTrainingIO('{χαλασμένο');
      final t = TrainingStore(io: io, clock: () => now);
      await t.load();
      expect(t.readError, isTrue);
      t.setHrLimit(150);
      await t.save();
      expect(io.json, '{χαλασμένο');
    });

    test('σύνοψη για τον Claude', () {
      final t = sampleTraining(now);
      final text = t.exportForClaude(names: {for (final e in lib.list) e.id: e.name});
      expect(text, contains('Πρόγραμμα 1'));
      expect(text, contains('Πιεστικό με αλτήρες'));
      expect(text, contains('ενόχληση'));
      expect(text, contains('"kind":"ygeia-program"'));
    });
  });

  group('όριο παλμών από τον γιατρό', () {
    test('αποθηκεύεται, φτάνει στη σύνοψη, σβήνει', () async {
      final io = MemoryTrainingIO();
      final t = TrainingStore(io: io, clock: () => now)..replaceAll({'v': 1});
      expect(t.hrLimit, isNull);
      t.setHrLimit(128);
      await t.save();
      final back = TrainingStore(io: io, clock: () => now);
      await back.load();
      expect(back.hrLimit, 128);
      expect(back.exportForClaude(), contains('Όριο παλμών γιατρού: 128'));
      back.setHrLimit(null);
      expect(back.toJson().containsKey('hrLimit'), isFalse);
      expect(back.exportForClaude(), isNot(contains('Όριο παλμών')));
    });
  });

  group('οθόνες', () {
    setUp(() => ExClock.frozen = true);

    Future<void> pump(WidgetTester t, Widget w, {Size size = const Size(400, 900)}) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = size;
      addTearDown(t.view.reset);
      await t.runAsync(() => ExLibrary.load(inline: true));
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: w)));
      await t.pumpAndSettle();
    }

    Future<void> tapKey(WidgetTester t, String key) async {
      final f = find.byKey(ValueKey(key));
      await t.ensureVisible(f);
      await t.pumpAndSettle();
      await t.tap(f);
      await t.pump();
    }

    testWidgets('χωρίς κλείδωμα· χωρίς όριο γιατρού καμία κάρτα· το όριο μπαίνει από τις Ρυθμίσεις (12/11)', (tester) async {
      final store = sampleTraining(now)..setHrLimit(null);
      await pump(tester, TrainingPage(training: store, now: now));
      expect(find.text('Ξεκίνα την προπόνηση'), findsOneWidget);
      expect(find.byKey(const ValueKey('train-hrlimit')), findsNothing);
      // Ρυθμίσεις › Για προχωρημένους › «Όριο παλμών από γιατρό» καλεί το ίδιο φύλλο.
      await pump(tester, Builder(builder: (context) => FilledButton(
            key: const ValueKey('open-limit'),
            onPressed: () => editDoctorLimit(context, store),
            child: const Text('όριο'),
          )));
      await tapKey(tester, 'open-limit');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('train-hr-clear')), findsNothing, reason: 'χωρίς όριο: τίποτα να σβήσεις');
      await tester.enterText(find.byKey(const ValueKey('train-hr')), '135');
      await tester.pump();
      await tapKey(tester, 'train-hr-save');
      await tester.pumpAndSettle();
      expect(store.hrLimit, 135);
      await pump(tester, TrainingPage(training: store, now: now));
      expect(find.textContaining('135 bpm'), findsOneWidget);
    });

    testWidgets('προπόνηση: ✓ ξεκινά διάλειμμα, το τελευταίο σετ ρωτά τη ρεζέρβα, τέλος → αποθήκευση', (tester) async {
      final store = sampleTraining(now);
      await pump(tester, TrainingPage(training: store, now: now));
      await tapKey(tester, 'train-start');
      await tester.pumpAndSettle();
      expect(find.byType(SessionPage), findsOneWidget);
      await tapKey(tester, 'sess-tick-0');
      await tester.pump();
      expect(find.byKey(const ValueKey('rest-stop')), findsOneWidget);
      await tapKey(tester, 'sess-tick-1');
      await tester.pump();
      await tapKey(tester, 'sess-tick-2');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rir-2')), findsOneWidget);
      await tapKey(tester, 'rir-2');
      await tester.pump();
      await tapKey(tester, 'rir-ok');
      await tester.pumpAndSettle();
      expect(store.current!.items.first.rirAnswer, 2);
      await tapKey(tester, 'sess-finish');
      await tester.pumpAndSettle();
      // μόνο η 1η άσκηση: ερώτηση πριν από το τέλος
      expect(find.text('Τελείωσες νωρίτερα;'), findsOneWidget);
      await tapKey(tester, 'sess-finish-ok');
      await tester.pumpAndSettle();
      expect(find.byType(SummaryPage), findsOneWidget);
      await tapKey(tester, 'summary-save');
      await tester.pumpAndSettle();
      expect(store.current, isNull);
      expect(store.sessions.length, 3);
      // ο χρονοδιακόπτης της σελίδας σταμάτησε μαζί της
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('όριο: λάθος αριθμός δεν περνά, χαμηλό θέλει επιβεβαίωση, «Χωρίς όριο» σβήνει', (tester) async {
      final store = sampleTraining(now);
      expect(store.hrLimit, 140);
      await pump(tester, TrainingPage(training: store, now: now));
      await tapKey(tester, 'train-hrlimit');
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('train-hr')), '70');
      await tester.pump();
      expect(find.text('Γράψε αριθμό από 80 έως 220'), findsOneWidget);
      await tapKey(tester, 'train-hr-save');
      expect(store.hrLimit, 140);
      await tester.enterText(find.byKey(const ValueKey('train-hr')), '95');
      await tester.pump();
      await tapKey(tester, 'train-hr-save');
      expect(store.hrLimit, 140, reason: 'κάτω από 100 θέλει «Σωστά;»');
      await tapKey(tester, 'train-hr-low');
      await tester.pump();
      await tapKey(tester, 'train-hr-save');
      await tester.pumpAndSettle();
      expect(store.hrLimit, 95);
      await tapKey(tester, 'train-hrlimit');
      await tester.pumpAndSettle();
      await tapKey(tester, 'train-hr-clear');
      await tester.pumpAndSettle();
      expect(store.hrLimit, isNull);
    });

    testWidgets('ρεζέρβα: δεν κλείνει κατά λάθος, «Δεν ξέρω» → χωρίς απάντηση', (tester) async {
      final store = sampleTraining(now);
      await pump(tester, TrainingPage(training: store, now: now));
      await tapKey(tester, 'train-start');
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tapKey(tester, 'sess-tick-$i');
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const ValueKey('rir-unknown')), findsOneWidget);
      await tester.tapAt(const Offset(200, 40)); // πάτημα έξω από το φύλλο
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('rir-unknown')), findsOneWidget);
      await tapKey(tester, 'rir-unknown');
      await tester.pumpAndSettle();
      expect(store.current!.items.first.complete, isTrue);
      expect(store.current!.items.first.rirAnswer, isNull);
    });

    testWidgets('επικόλληση: προεπισκόπηση και αποθήκευση', (tester) async {
      final store = sampleTraining(now, program: false, history: false);
      await pump(tester, Builder(builder: (context) => TextButton(
            key: const ValueKey('open'),
            onPressed: () => Navigator.of(context).push(ProgramPastePage.route(store, text: sampleProgramText)),
            child: const Text('άνοιγμα'),
          )));
      await tapKey(tester, 'open');
      await tester.pumpAndSettle();
      expect(find.text('Πρόγραμμα 1'), findsOneWidget);
      await tapKey(tester, 'paste-save');
      await tester.pumpAndSettle();
      expect(store.program!.author, 'claude');
    });
  });
}
