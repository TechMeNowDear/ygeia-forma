// Round 2 (g3): «Προπόνηση — λογική στο κινητό». R2-C-1 = R2-E-1 (σβησμένη προπόνηση που ξαναγύριζε από τους παλμούς
// του ρολογιού) και R2-C-2 («♥ διάλειμμα» στις ασκήσεις μίας πλευράς τη φορά). Οι αναμενόμενες τιμές βγήκαν από τον
// γραμμένο κανόνα (Python: /home/claude/scratch/g3/sethr.py, με στρογγύλεμα όπως το Dart), όχι από τον κώδικα. Όλα τα
// νούμερα είναι δοκιμαστικά (κανένα πραγματικό δεδομένο υγείας).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/exercise/ex_data.dart';
import 'package:ygeia_forma/exercise/ex_player.dart';
import 'package:ygeia_forma/pages/training/today_training_card.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/training/progression.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/set_hr.dart';
import 'package:ygeia_forma/training/training_store.dart';
import 'package:ygeia_forma/training/wear_link.dart';

import 'training_sample.dart';

/// Δευτέρα 16/11, 17:30: στο δοκιμαστικό πρόγραμμα η Δευτέρα είναι «Προπόνηση Β» (πρώτη άσκηση incline_press, 3 σετ).
final t0 = DateTime(2026, 11, 16, 17, 30);

/// Η πρώτη μέρα: πρόγραμμα, κανένα ιστορικό. Ρολόι που αλλάζει ([clock]).
TrainingStore _firstDay(MemoryTrainingIO io, DateTime Function() clock) =>
    TrainingStore(io: io, clock: clock)
      ..replaceAll(sampleTraining(t0, history: false).toJson())
      ..ready = true;

/// Οι ασκήσεις της προπόνησης όπως τις στέλνει το ρολόι (χωρίς ✓).
List<Map<String, dynamic>> _items(Session s) => [for (final e in s.items) jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>];

/// Αποτέλεσμα «Παλμοί εδώ» όπως το φτιάχνει το ρολόι (Results.kt) όταν η προπόνηση του κινητού χάθηκε: παλμοί και οι
/// ασκήσεις, κανένα ✓.
Map<String, dynamic> _hrOnly(Session s, List<Map<String, dynamic>> items, {int? fin}) => {
      'v': 1,
      'kind': 'hr',
      'sid': s.id,
      'id': 'hr${s.id}-${t0.millisecondsSinceEpoch}',
      'hrT0': t0.millisecondsSinceEpoch,
      'hr': [
        for (var k = 0; k <= 180; k += 5) [k, 95 + k ~/ 20],
      ],
      'hrAvg': 99,
      'hrMax': 104,
      'items': items,
      'lim': 0,
      if (fin != null) 'fin': fin,
    };

/// Ζέσταμα με «Παλμοί εδώ» (παλμοί ανά 10″ για 3 λεπτά), κανένα σετ, και «Σβήσιμο» στο κινητό.
Session _startAndDrop(TrainingStore t, void Function(DateTime) setClock) {
  final s = t.start(t.program!.forDay(t0)!);
  for (var k = 0; k < 18; k++) {
    setClock(t0.add(Duration(seconds: 10 * k)));
    t.addHr(95 + k, t0.add(Duration(seconds: 10 * k)));
  }
  expect(s.hr.length, 18);
  setClock(t0.add(const Duration(minutes: 3)));
  t.discard();
  expect(t.current, isNull);
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ------------------------------------------------------------------ R2-C-1 = R2-E-1
  group('R2-C-1 = R2-E-1: «Σβήσιμο» χωρίς σετ και μετά μόνο παλμοί από το ρολόι', () {
    test('τίποτα δεν ξαναμπαίνει· η «Σήμερα» δεν τη βλέπει «έγινε»· η πρώτη φορά μένει πρώτη· το ρολόι παίρνει «ελήφθη»', () async {
      var at = t0;
      final io = MemoryTrainingIO();
      final t = _firstDay(io, () => at);
      final s = _startAndDrop(t, (v) => at = v);
      expect(await t.flush(), isTrue);
      final items = _items(s);
      at = t0.add(const Duration(minutes: 4));
      final result = _hrOnly(s, items);

      expect(t.importWatch(result), isFalse);
      expect(t.sessions, isEmpty);
      expect(t.current, isNull);
      expect(TodayTrainingCard.doneToday(t, at), isNull, reason: 'αλλιώς η «Σήμερα» κρύβει το «Ξεκίνα»');
      for (final e in s.items) {
        expect(t.isFirstTime(e.ex), isTrue, reason: '${e.ex}: η βαθμονόμηση πρώτης φοράς πρέπει να γίνει');
      }
      // Και με «Τέλος» από το ρολόι: τίποτα.
      expect(t.importWatch(_hrOnly(s, items, fin: t0.add(const Duration(minutes: 3)).millisecondsSinceEpoch)), isFalse);
      expect(t.sessions, isEmpty);

      // Το ρολόι παίρνει «ελήφθη» (δεν ξαναστέλνει για πάντα) και ακόμα τίποτα δεν ξαναμπαίνει.
      expect(await WearLink.importDurably(t, jsonEncode(result)), isTrue);
      expect(t.sessions, isEmpty);
      // Κανένα αρχείο παλμών για προπόνηση που δεν υπάρχει.
      expect(io.hrFiles, isEmpty);

      // Μετά από επανεκκίνηση, το ίδιο αποτέλεσμα ξανά: τίποτα.
      final back = TrainingStore(io: io, clock: () => at);
      await back.load();
      expect(back.importWatch(result), isFalse);
      expect(back.sessions, isEmpty);
      expect(TodayTrainingCard.doneToday(back, at), isNull);
      expect(back.isFirstTime(s.items.first.ex), isTrue);
      expect(await WearLink.importDurably(back, jsonEncode(result)), isTrue);
      expect(io.hrFiles, isEmpty);
    });

    test('δεύτερο «Παλμοί εδώ» της ίδιας προπόνησης με ✓, μετά από το αποτέλεσμα μόνο με παλμούς: ξαναμπαίνει με τα σετ', () async {
      var at = t0;
      final t = _firstDay(MemoryTrainingIO(), () => at);
      final s = _startAndDrop(t, (v) => at = v);
      expect(await t.flush(), isTrue);
      final items = _items(s);
      at = t0.add(const Duration(minutes: 4));
      expect(t.importWatch(_hrOnly(s, items)), isFalse);

      // Στο ρολόι (χωρίς σύνδεση) ξεκίνησε ξανά «Παλμοί εδώ» στο 5′ και πατήθηκαν 2 σετ (6′, 8′).
      final log = (items[0]['log'] as List).cast<Map<String, dynamic>>();
      log[0] = {...log[0], 'd': 1, 't': t0.add(const Duration(minutes: 6)).millisecondsSinceEpoch};
      log[1] = {...log[1], 'd': 1, 't': t0.add(const Duration(minutes: 8)).millisecondsSinceEpoch};
      final start2 = t0.add(const Duration(minutes: 5)).millisecondsSinceEpoch;
      at = t0.add(const Duration(minutes: 20));
      final withTicks = {
        'v': 1,
        'kind': 'hr',
        'sid': s.id,
        'id': 'hr${s.id}-$start2',
        'hrT0': start2,
        'hr': [
          [0, 110],
          [5, 112],
          [10, 115],
        ],
        'items': items,
      };
      expect(t.importWatch(withTicks), isTrue);
      final f = t.sessions.single;
      expect(f.id, s.id);
      expect(f.setsDone, 2);
      expect(f.items.first.log[0].done && f.items.first.log[1].done, isTrue);
      // Τέλος: το τελευταίο ✓ (8′), όχι ο τελευταίος παλμός (5′10″).
      expect(f.end, t0.add(const Duration(minutes: 8)));
      // 18 παλμοί του κινητού (ζέσταμα) + 3 του ρολογιού.
      expect(f.hr.length, 21);
      expect(t.isFirstTime(f.items.first.ex), isFalse);
      expect(identical(TodayTrainingCard.doneToday(t, at), f), isTrue);
      // Το ίδιο αποτέλεσμα ξανά: τίποτα διπλό.
      t.importWatch(withTicks);
      expect(t.sessions.length, 1);
      expect(t.sessions.single.setsDone, 2);
    });

    test('✓ του ρολογιού για άλλη άσκηση από αυτή του κινητού: δεν είναι σετ της προπόνησης, τίποτα δεν ξαναμπαίνει', () async {
      var at = t0;
      final t = _firstDay(MemoryTrainingIO(), () => at);
      final s = _startAndDrop(t, (v) => at = v);
      expect(await t.flush(), isTrue);
      final items = _items(s);
      final log = (items[0]['log'] as List).cast<Map<String, dynamic>>();
      log[0] = {...log[0], 'd': 1, 't': t0.add(const Duration(minutes: 2)).millisecondsSinceEpoch};
      items[0] = {...items[0], 'ex': 'db_press'};
      at = t0.add(const Duration(minutes: 4));
      expect(t.importWatch(_hrOnly(s, items)), isFalse);
      expect(t.sessions, isEmpty);
    });

    test('άμυνα: προπόνηση χωρίς σετ ή με την άσκηση παραλειμμένη δεν κάνει την άσκηση «όχι πρώτη φορά» (ίδιο με τον στόχο)', () {
      final t = _firstDay(MemoryTrainingIO(), () => t0);
      final b = t.program!.workout('B')!;
      final press = b.items.first; // incline_press
      final rdl = b.items[2]; // rdl
      ExLog log(String ex, List<bool> done, {bool skipped = false}) => ExLog(
            ex: ex,
            sets: 3,
            lo: 8,
            hi: 12,
            rir: 2,
            rest: 120,
            skipped: skipped,
            log: [for (final d in done) SetLog(load: 20, reps: 10, done: d)],
          );
      Session past(String id, int daysAgo, List<ExLog> items) => Session(
            id: id,
            workout: 'B',
            name: 'Προπόνηση Β',
            programId: 'p-claude-1',
            start: t0.subtract(Duration(days: daysAgo, hours: 1)),
            end: t0.subtract(Duration(days: daysAgo)),
            items: items,
          );
      t.sessions.addAll([
        past('e1', 3, [log(press.ex, [false, false, false]), log(rdl.ex, [false, false, false], skipped: true)]),
        past('e2', 2, [log(rdl.ex, [false, false, false], skipped: true)]),
      ]);
      expect(t.historyOf(press.ex), isNotEmpty);
      expect(t.isFirstTime(press.ex), isTrue);
      expect(t.isFirstTime(rdl.ex), isTrue);
      // Ο στόχος λέει το ίδιο: πρώτη φορά.
      expect(nextTarget(press, t.historyOf(press.ex), t0).change, Change.first);
      expect(nextTarget(rdl, t.historyOf(rdl.ex), t0).change, Change.first);
      // Με ένα σετ που έγινε: όχι πρώτη φορά.
      t.sessions.add(past('e3', 1, [log(press.ex, [true, false, false])]));
      expect(t.isFirstTime(press.ex), isFalse);
      expect(nextTarget(press, t.historyOf(press.ex), t0).change, isNot(Change.first));
    });

    testWidgets('οθόνες: η «Σήμερα» δείχνει «Ξεκίνα» και το 1ο σετ της πραγματικής προπόνησης ρωτά «Πρώτο σετ»', (tester) async {
      ExClock.frozen = true;
      addTearDown(() => ExClock.frozen = false);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 1400);
      addTearDown(tester.view.reset);
      await tester.runAsync(() => ExLibrary.load(inline: true));
      var at = t0;
      final t = _firstDay(MemoryTrainingIO(), () => at);
      final s = _startAndDrop(t, (v) => at = v);
      at = t0.add(const Duration(minutes: 10));
      expect(t.importWatch(_hrOnly(s, _items(s))), isFalse);

      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: SingleChildScrollView(child: TodayTrainingCard(training: t, now: at))),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('today-training-summary')), findsNothing);
      final start = find.byKey(const ValueKey('today-train-start'));
      expect(start, findsOneWidget);

      await tester.ensureVisible(start);
      await tester.pumpAndSettle();
      await tester.tap(start);
      await tester.pumpAndSettle();
      expect(t.current, isNotNull);
      final tick = find.byKey(const ValueKey('sess-tick-0'));
      await tester.ensureVisible(tick);
      await tester.pumpAndSettle();
      await tester.tap(tick);
      await tester.pumpAndSettle();
      expect(find.text('Πρώτο σετ: πόσες ακόμα θα έβγαζες;'), findsOneWidget);

      // κλείνει η οθόνη (σταματά το ρολόι του δευτερολέπτου)
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  // ------------------------------------------------------------------ R2-C-2
  group('R2-C-2: «♥ διάλειμμα» στις ασκήσεις μίας πλευράς τη φορά (ένα ✓ για δεξιά + αριστερά)', () {
    test('ο σταθερός πίνακας είναι ίδιος με τα βήματα της βιβλιοθήκης («Μετά το σετ, άλλαξε …» / «γύρνα …»)', () {
      final lib = ExLibrary.fromJson(jsonDecode(File('assets/exercises/exercises.json').readAsStringSync()) as Map<String, dynamic>);
      final rule = RegExp('Μετά το σετ, (άλλαξε|γύρνα)');
      expect(perSideExercises, {for (final e in lib.list) if (e.steps.any(rule.hasMatch)) e.id});
      expect(perSideExercises, {'db_row', 'band_er', 'split_squat', 'pallof'});
    });

    test('διάρκεια σετ: δύο πλευρές (η καθεμία 20–120″) και 5″ για την αλλαγή· οι άλλες ασκήσεις όπως πριν', () {
      expect(setSecondsOf('db_row', 10, 4.3), closeTo(91, 1e-9));
      expect(setSecondsOf('db_press', 10, 4.3), closeTo(43, 1e-9));
      expect(setSecondsOf('split_squat', 15, 4.6), closeTo(143, 1e-9));
      expect(setSecondsOf('split_squat', 40, 4.6), closeTo(245, 1e-9));
      expect(setSecondsOf('pallof', 2, 1.0), closeTo(45, 1e-9));
      expect(setSecondsOf('band_er', 12), closeTo(113, 1e-9));
      expect(setSecondsOf('goblet', 12), closeTo(setSeconds(12), 1e-9));
    });

    final start = DateTime(2026, 11, 16, 18);
    ExLog ex(String id, List<int> ticks) => ExLog(ex: id, sets: ticks.length, lo: 8, hi: 12, rir: 3, rest: 90, log: [
          for (final k in ticks) SetLog(load: 6.8, reps: 10, done: true, at: start.millisecondsSinceEpoch + k * 1000),
        ]);
    Session session(List<List<int>> hr, List<ExLog> items) =>
        Session(id: 'r2', workout: 'P', name: 'Π', programId: 'p', start: start, hr: hr, items: items);

    test('πιεστικό και μετά κωπηλασία 2 × 10 (σετ 130, διάλειμμα 100): το διάλειμμα διαβάζεται πριν από την πρώτη πλευρά', () {
      // πιεστικό ✓ 60″· διάλειμμα 60–150″· κωπηλασία σετ 1: δεξί 150–193, αλλαγή, αριστερό 197–240, ✓ 240″·
      // διάλειμμα 240–330″· σετ 2: 330–420, ✓ 420″.
      final hr = [
        for (var k = 0; k <= 420; k++) [k, (k >= 30 && k < 60) || (k >= 150 && k < 240) || k >= 330 ? 130 : 100],
      ];
      final r = sessionSetHr(session(hr, [ex('db_press', [60]), ex('db_row', [240, 420])]), repSeconds: (_) => 4.3);
      expect(r[0].sets[0]!.set, 130);
      expect(r[0].sets[0]!.rest, 100, reason: 'πριν: 130 (μέσα στο δεξί χέρι της κωπηλασίας)');
      expect(r[1].sets[0]!.rest, 100, reason: 'πριν: 130 (μέσα στο δεξί χέρι του 2ου σετ)');
      expect(r[1].sets[1]!.rest, isNull, reason: 'τελευταίο σετ');
    });

    test('ίχνος του συμβουλίου (R2-C): ανεβαίνει στο σετ, πέφτει στο διάλειμμα → 97 όπως στα τελευταία 10″, όχι 109', () {
      int at(int k) {
        if (k < 90) return (100 + 25 * k / 90).round();
        if (k < 180) return (125 - 30 * (k - 90) / 90).round();
        return (95 + 30 * (k - 180) / 90).round();
      }

      final hr = [
        for (var k = 0; k <= 270; k++) [k, at(k)],
      ];
      final r = sessionSetHr(session(hr, [ex('db_row', [90, 270])]), repSeconds: (_) => 4.3);
      expect(meanIn(hr, 170, 180), 97);
      expect(r[0].sets[0]!.rest, 97);
    });

    test('αν πατηθεί ✓ μετά από κάθε πλευρά: «—» ή τιμή μέσα στο διάλειμμα, ποτέ μέσα σε σετ', () {
      // δεξί 0–43 ✓43, αλλαγή, αριστερό 48–91 ✓91, διάλειμμα 91–181, δεξί 181–224 ✓224, αριστερό 229–272 ✓272
      final hr = [
        for (var k = 0; k <= 272; k++) [k, k < 43 || (k >= 48 && k < 91) || (k >= 181 && k < 224) || k >= 229 ? 130 : 100],
      ];
      final r = sessionSetHr(session(hr, [ex('db_row', [43, 91, 224, 272])]), repSeconds: (_) => 4.3);
      expect([for (final x in r[0].sets) x!.rest], [null, 100, null, null]);
    });
  });
}
