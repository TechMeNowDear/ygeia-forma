// Γύρος 9, f2 (προπόνηση, πλευρά κινητού): δοκιμές για τα R9-A6-1…10, R9-A7-1/3/4, R9-A8-1/2, R9-A8-3 (κινητό),
// R9-U3-03…08. Οι αναμενόμενες τιμές βγαίνουν από τους κανόνες όπως γράφονται (σκαλιά του εξοπλισμού, Epley του
// repsBeforeStep, ρεζέρβα ≥ 2, ±1′ μετά το τέλος για τους παλμούς), όχι από την υλοποίηση. Όλες οι τιμές είναι επινοημένες.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/exercise/ex_data.dart';
import 'package:ygeia_forma/exercise/ex_names.dart' show exNamesById;
import 'package:ygeia_forma/exercise/ex_player.dart' show ExClock;
import 'package:ygeia_forma/pages/training/session_page.dart';
import 'package:ygeia_forma/pages/training/today_training_card.dart';
import 'package:ygeia_forma/pages/training/training_page.dart';
import 'package:ygeia_forma/pages/training/walk_widgets.dart' show RecoveryCard;
import 'package:ygeia_forma/pages/training/zone_widgets.dart' show talkMovesZone, talkProposal;
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/training/equipment.dart';
import 'package:ygeia_forma/training/hr_quality.dart' show HrQualityCounts, hrQualityText;
import 'package:ygeia_forma/training/program.dart';
import 'package:ygeia_forma/training/progress.dart';
import 'package:ygeia_forma/training/progression.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/training_store.dart';

import 'training_sample.dart';

final now = DateTime(2026, 11, 20, 18); // Παρασκευή
DateTime ago(int days) => DateTime(2026, 11, 20 - days, 18);

PlanItem it(String ex, {int sets = 2, int lo = 10, int hi = 15, int rir = 3, double? load}) =>
    PlanItem(ex: ex, sets: sets, lo: lo, hi: hi, rir: rir, rest: 90, load: load);

/// Μία άσκηση που έγινε: [sets] = τα σετ του προγράμματος εκείνη τη μέρα (ως προεπιλογή όσα και τα [reps]).
ExLog done(String ex, double? load, List<int> reps, {int? ra, int? fa, int lo = 10, int hi = 15, int? sets}) => ExLog(
      ex: ex,
      sets: sets ?? reps.length,
      lo: lo,
      hi: hi,
      rir: 3,
      rest: 90,
      rirAnswer: ra,
      firstAnswer: fa,
      log: [for (final r in reps) SetLog(load: load, reps: r, done: true)],
    );

/// Σετ με διαφορετικά φορτία: [(φορτίο, επαναλήψεις)]· [sets] = τα σετ του προγράμματος.
ExLog mixed(String ex, List<(double, int)> sets, {required int planned, int? ra, int? fa, int lo = 8, int hi = 12}) => ExLog(
      ex: ex,
      sets: planned,
      lo: lo,
      hi: hi,
      rir: 3,
      rest: 90,
      rirAnswer: ra,
      firstAnswer: fa,
      log: [for (final (l, r) in sets) SetLog(load: l, reps: r, done: true)],
    );

Session finished(String id, DateTime start, List<ExLog> items) =>
    Session(id: id, workout: 'A', name: 'Δοκιμή', programId: 'p', start: start, end: start.add(const Duration(hours: 1)), items: items);

/// Πρόγραμμα με ημερομηνία έναρξης Δευτέρα 16/11 (επινοημένες ασκήσεις): Δευτέρα LA, Τρίτη περπάτημα, Σάββατο LB.
const _v2 = '{"kind":"ygeia-program","v":1,"id":"p-v2","name":"Δοκιμή","author":"claude","from":"2026-11-16",'
    '"days":{"mon":"LA","tue":"walk","sat":"LB"},'
    '"workouts":[{"id":"LA","name":"Κάτω μέρος Α","items":[{"ex":"leg_ext","sets":2,"reps":[10,15],"rir":3,"rest":90}]},'
    '{"id":"LB","name":"Κάτω μέρος Β","items":[{"ex":"goblet","sets":2,"reps":[8,12],"rir":3,"rest":90}]},'
    '{"id":"walk","name":"Περπάτημα","cardio":{"activity":"walk","minutes":30,"plan":[30,35,40,45]}}]}';

final _ids = exNamesById.keys.toSet();

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 1400)}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: w));
  await t.pump();
}

Future<void> _tapKey(WidgetTester t, String key) async {
  final f = find.byKey(ValueKey(key));
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pump();
}

void main() {
  // Το κινούμενο σχέδιο των ασκήσεων σταματημένο: οι οθόνες «ησυχάζουν» (pumpAndSettle).
  setUp(() => ExClock.frozen = true);
  tearDown(() => ExClock.frozen = false);

  // ---------------------------------------------------------------- R9-A6-1
  group('R9-A6-1: «4+» στο 1ο σετ με σκαλί που δεν μπαίνει ποτέ μόνο του', () {
    test('λάστιχο 20 → 30 lb: «πολύ μεγάλο… ως τις 20», όπως ο στόχος της πρώτης φοράς· όχι «θέλει πρώτα περισσότερες»', () {
      // 20 → 30 lb = ×1,5: ⌈1,5 × (30 + 10 + 3) − 33⌉ = 32 > 15 + 10 → ποτέ αυτόματα, ως τις 15 + 5 = 20.
      expect(calibrate(it('band_pulldown'), 20, 10, 4), isNull);
      expect(
          calibrateNote(it('band_pulldown'), 20, 10, 4),
          'Τα επόμενα σετ μένουν μπλε (20 lb): το επόμενο σκαλί, πράσινο (30 lb), είναι πολύ μεγάλο για να μπει μόνο του· '
          'εδώ ανεβαίνουν οι επαναλήψεις, ως τις 20. Αν είναι πολύ ελαφρύ, πάτα «+» στο βάρος.');
      final first = nextTarget(it('band_pulldown'), const [], now);
      expect(first.reason, contains('πολύ μεγάλο για να μπει μόνο του'));
      expect(first.reason, contains('ως τις 20'));
      // pallof 10–12: ως τις 12 + 5 = 17
      final p = calibrateNote(it('pallof', lo: 10, hi: 12), 20, 10, 4)!;
      expect(p, contains('ως τις 17'));
      expect(p, isNot(contains('θέλει πρώτα')));
    });

    test('face pull: το ίδιο, χωρίς «+»· αλτήρες 4,3 → 5,3 kg (το σκαλί μπαίνει στις 18): το κείμενο μένει', () {
      final f = calibrateNote(it('face_pull', lo: 12), 10, 12, 4)!;
      expect(f, contains('πολύ μεγάλο'));
      expect(f, isNot(contains('«+»')));
      expect(calibrateNote(it('db_press', lo: 8, hi: 12), 4.3, 8, 4),
          'Τα επόμενα σετ μένουν 4,3 kg: το επόμενο σκαλί, 5,3 kg, θέλει πρώτα περισσότερες επαναλήψεις με αυτό. '
          'Αν είναι πολύ ελαφρύ, πάτα «+» στο βάρος.');
    });
  });

  // ---------------------------------------------------------------- R9-A6-2
  group('R9-A6-2: «Πρόοδος» και πρόοδος της εφαρμογής κρίνουν τα ίδια σετ (όχι ένα «+ Σετ»)', () {
    final before = done('db_press', 9.3, [10, 10, 10], ra: 3, lo: 8, hi: 12);
    // 3 σετ του προγράμματος 9,3 × 11 και ένα παραπάνω με «+ Σετ» στα 7,8 × 12
    final after = mixed('db_press', [(9.3, 11), (9.3, 11), (9.3, 11), (7.8, 12)], planned: 3, ra: 3);

    test('τελικό φορτίο 9,3 kg (όχι 7,8)· «+3 επαναλήψεις με το ίδιο βάρος»', () {
      expect(after.judged.length, 3);
      expect(after.endLoad, 9.3);
      final x = ExProgress(ex: 'db_press', kind: LoadKind.dbPair, beforeDay: ago(7), before: before, nowDay: ago(0), now: after);
      expect(x.loadDiff, 0);
      expect(x.repsDiff, 3);
      expect(x.change, StrengthChange.up);
    });

    test('η επόμενη φορά: 9,3 kg × 12, 12, 12 (+1, ίδιο βάρος)', () {
      final tg = nextTarget(it('db_press', sets: 3, lo: 8, hi: 12), [(ago(0), after), (ago(7), before)], now);
      expect(tg.change, Change.more);
      expect(tg.load, 9.3);
      expect(tg.reps, [12, 12, 12]);
    });

    test('η σύνοψη για τον Claude: «9,3 kg → 9,3 kg»', () {
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => now)..ready = true;
      t.sessions
        ..add(finished('a', ago(7), [before]))
        ..add(finished('b', ago(0), [after]));
      expect(t.exportForClaude(), contains('9,3 kg → 9,3 kg'));
      expect(t.exportForClaude(), isNot(contains('9,3 kg → 7,8 kg')));
    });
  });

  // ---------------------------------------------------------------- R9-A6-3
  group('R9-A6-3: δίσκος στο crunch: κείμενο και συμπεριφορά λένε το ίδιο', () {
    final lib = ExLibrary.fromJson(jsonDecode(File('assets/exercises/exercises.json').readAsStringSync()) as Map<String, dynamic>);

    test('το «Πώς γίνεται» λέει και το 1ο σετ της πρώτης φοράς', () {
      final tip = lib.byId('crunch')!.tips.first;
      expect(tip, contains('Αν στο 1ο σετ της πρώτης φοράς σου μένουν 4 ή περισσότερες'));
      expect(tip, contains('από 0,5 kg'));
    });

    test('πρώτη φορά χωρίς δίσκο, «4+» στο 1ο σετ: τα επόμενα σετ με 0,5 kg', () {
      const prog = '{"kind":"ygeia-program","v":1,"id":"p-c","name":"Δοκιμή","author":"claude",'
          '"days":{"fri":"A"},"workouts":[{"id":"A","name":"Κοιλιακοί","items":[{"ex":"crunch","sets":2,"reps":[10,15],"rir":3,"rest":60}]}]}';
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => now)..ready = true;
      t.saveProgram(parseProgram(prog, _ids).program!, author: 'claude');
      final s = t.start(t.program!.workout('A')!);
      final e = s.items.single;
      expect(e.log.first.load, 0);
      expect(t.firstPending(e), isTrue, reason: 'η ερώτηση γίνεται και χωρίς δίσκο');
      t.tick(e, 0);
      final r = t.answerFirst(e, 4);
      expect(r.load, 0.5);
      expect(e.log[1].load, 0.5);
    });
  });

  // ---------------------------------------------------------------- R9-A6-4
  group('R9-A6-4: φορτίο που έγινε με «1» στο 1ο σετ δεν μετρά ως «το έχεις ήδη κάνει»', () {
    // Πιεστικό 3 × 8–12 με αρχικό 6,8 kg: 1ο σετ 6,8 × 8 με «1» → τα επόμενα 5,3 kg.
    final cal = mixed('db_press', [(6.8, 8), (5.3, 8), (5.3, 8)], planned: 3, ra: 3, fa: 1);
    final press = it('db_press', sets: 3, lo: 8, hi: 12);

    test('5,3 kg × 12 με «3»: όχι 6,8 kg αμέσως· πρώτα ως τις 20 (6,8 / 5,3 = +28%)', () {
      expect(calibrate(it('db_press', sets: 3, lo: 8, hi: 12, load: 6.8), 6.8, 8, 1), 5.3);
      // ⌈(6,8 / 5,3) × (30 + 8 + 3) − 33⌉ = ⌈52,6 − 33⌉ = 20
      expect(repsBeforeStep(6.8 / 5.3, 8, 3), 20);
      final tg = nextTarget(press, [(ago(7), done('db_press', 5.3, [12, 12, 12], ra: 3, lo: 8, hi: 12)), (ago(28), cal)], now);
      expect((tg.change, tg.load), (Change.more, 5.3));
      expect(tg.reps, [13, 13, 13]);
      final at20 = nextTarget(press, [(ago(7), done('db_press', 5.3, [20, 20, 20], ra: 3, lo: 8, hi: 12)), (ago(28), cal)], now);
      expect((at20.change, at20.load), (Change.up, 6.8));
      expect(at20.reps, [8, 8, 8]);
    });

    test('παλιό αρχείο χωρίς «fa»: όπως πριν (6,8 kg έγινε στο κάτω όριο → ξαναμπαίνει στο πάνω όριο)', () {
      final old = mixed('db_press', [(6.8, 8), (5.3, 8), (5.3, 8)], planned: 3, ra: 3);
      final tg = nextTarget(press, [(ago(7), done('db_press', 5.3, [12, 12, 12], ra: 3, lo: 8, hi: 12)), (ago(28), old)], now);
      expect((tg.change, tg.load), (Change.up, 6.8));
    });

    test('λάστιχο 20 → 10 lb με «1» στο 1ο σετ: με 10 lb στο πάνω όριο ΔΕΝ γυρνά στα 20 lb μόνο του', () {
      final calB = ExLog(ex: 'band_pushdown', sets: 2, lo: 10, hi: 15, rir: 3, rest: 60, rirAnswer: 3, firstAnswer: 1, log: [
        SetLog(load: 20, reps: 10, done: true),
        SetLog(load: 10, reps: 12, done: true),
      ]);
      final tg = nextTarget(it('band_pushdown'), [(ago(3), done('band_pushdown', 10, [15, 15], ra: 3)), (ago(6), calB)], now);
      // 10 → 20 lb = ×2: ποτέ αυτόματα· ως τις 15 + 5 = 20, +1 τη φορά
      expect((tg.change, tg.load), (Change.more, 10.0));
      expect(tg.reps, [16, 16]);
    });

    test('«άφησα 1» στο τέλος με το βαρύτερο: ούτε αυτό μετρά', () {
      final hard = done('db_press', 6.8, [8, 8, 8], ra: 1, lo: 8, hi: 12);
      final tg = nextTarget(press, [(ago(7), done('db_press', 5.3, [12, 12, 12], ra: 3, lo: 8, hi: 12)), (ago(14), hard)], now);
      expect((tg.change, tg.load), (Change.more, 5.3));
    });
  });

  // ---------------------------------------------------------------- R9-A6-5
  testWidgets('R9-A6-5: «+ Σετ» σε μία άσκηση δεν κρύβει το σετ που λείπει σε άλλη: «Τελείωσες νωρίτερα;»', (tester) async {
    await tester.runAsync(() => ExLibrary.load(inline: true));
    final store = sampleTraining(now);
    final s = store.start(store.program!.workout('A')!);
    final a = s.items[0], b = s.items[1];
    store.addSet(a);
    for (var i = 0; i < a.log.length; i++) {
      store.tick(a, i);
    }
    store.tick(b, 0);
    store.tick(b, 1);
    for (final e in s.items.skip(2)) {
      for (var i = 0; i < e.log.length; i++) {
        store.tick(e, i);
      }
    }
    // 6 ασκήσεις × 3 σετ = 18 = όσα έγιναν (4 + 2 + 12): το παλιό «σύνολο» δεν έβλεπε τίποτα να λείπει.
    expect(s.setsDone, 18);
    await _pump(tester, SessionPage(training: store));
    await _tapKey(tester, 'sess-finish');
    await tester.pumpAndSettle();
    expect(find.text('Τελείωσες νωρίτερα;'), findsOneWidget);
    // γραμμές: 4 + 3 + 12 = 19, έγιναν 18
    expect(find.textContaining('Έγιναν 18 από 19 σετ.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  // ---------------------------------------------------------------- R9-A6-6
  group('R9-A6-6: «Η εβδομάδα» πριν από την έναρξη του προγράμματος', () {
    Finder inWeek(int d, String text) => find.descendant(of: find.byKey(ValueKey('train-week-$d')), matching: find.text(text));

    testWidgets('Σάββατο 14/11 (έναρξη Δευ 16/11): καμία προπόνηση στις μέρες της εβδομάδας· από 16/11 κανονικά', (tester) async {
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final sat = DateTime(2026, 11, 14, 10);
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => sat)..ready = true;
      t.saveProgram(parseProgram(_v2, _ids).program!, author: 'claude');
      await _pump(tester, Scaffold(body: TrainingPage(training: t, now: sat)), size: const Size(400, 2400));
      expect(find.byKey(const ValueKey('train-not-started')), findsOneWidget);
      for (final d in [1, 6]) {
        expect(inWeek(d, '—'), findsOneWidget, reason: 'μέρα $d');
      }
      expect(inWeek(1, 'ΚΑ'), findsNothing);
      expect(inWeek(6, 'ΚΒ'), findsNothing);
      await tester.pumpWidget(const SizedBox());

      final mon = DateTime(2026, 11, 16, 10);
      final t2 = TrainingStore(io: MemoryTrainingIO(), clock: () => mon)..ready = true;
      t2.saveProgram(parseProgram(_v2, _ids).program!, author: 'claude');
      await _pump(tester, Scaffold(body: TrainingPage(training: t2, now: mon)), size: const Size(400, 2400));
      expect(inWeek(1, 'ΚΑ'), findsOneWidget);
      expect(inWeek(6, 'ΚΒ'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  // ---------------------------------------------------------------- R9-A6-7 = R9-U3-05
  test('R9-A6-7 / U3-05: στην επικόλληση τα μηνύματα έχουν το όνομα της άσκησης, και «άφησε», όχι «ρεζέρβα»', () {
    const prog = '{"kind":"ygeia-program","v":1,"id":"p-w","name":"Δοκιμή","author":"claude","days":{"mon":"A"},'
        '"workouts":[{"id":"A","name":"Α","items":['
        '{"ex":"db_press","sets":3,"reps":[8,12],"rir":3,"rest":90,"load":11},'
        '{"ex":"goblet","sets":3,"reps":[8,12],"rir":1,"rest":90},'
        '{"ex":"rdl","sets":3,"reps":[8,12],"rir":1,"rest":90},'
        '{"ex":"band_pulldown","sets":2,"reps":[10,15],"rir":3,"rest":90,"load":25}]}]}';
    final r = parseProgram(prog, _ids);
    expect(r.ok, isTrue, reason: r.errors.join('\n'));
    expect(r.warnings, containsAll([
      '11 kg δεν βγαίνει με τους δίσκους σου· στο «Πιεστικό με αλτήρες» μπήκε 10,3 kg.',
      'Άφησε τουλάχιστον 2 (ως να πει άλλα ο γιατρός σου): στο «Goblet squat» έγινε 2.',
      'Μπάρα χωρίς βραχίονες ασφαλείας: στο «Romanian deadlift» το «άφησε» έγινε 2.',
      '25 lb δεν βγαίνει με τα λάστιχά σου· στο «Έλξεις τροχαλίας με λάστιχο» μπήκε μπλε (20 lb).',
    ]));
    for (final w in r.warnings) {
      for (final code in ['db_press', 'goblet', 'rdl', 'band_pulldown', 'Ρεζέρβα', 'ρεζέρβα']) {
        expect(w, isNot(contains(code)), reason: w);
      }
    }
    // άγνωστη άσκηση: ο κωδικός μένει (δεν υπάρχει όνομα)
    final bad = parseProgram(prog.replaceFirst('"ex":"goblet"', '"ex":"xyz_ex"'), _ids);
    expect(bad.errors.any((e) => e.contains('«xyz_ex»')), isTrue);
    // βάρος που δεν είναι σωστός αριθμός: με το όνομα
    final neg = parseProgram(prog.replaceFirst('"load":11', '"load":-2'), _ids);
    expect(neg.errors, contains('Α: το βάρος στο «Πιεστικό με αλτήρες» δεν μπορεί να είναι αρνητικό.'));
  });

  // ---------------------------------------------------------------- R9-A6-8
  testWidgets('R9-A6-8: σύνοψη παλιότερης προπόνησης: κανένας στόχος βγαλμένος από μεταγενέστερες φορές', (tester) async {
    await tester.runAsync(() => ExLibrary.load(inline: true));
    final t = sampleTraining(now);
    // το δείγμα: η ίδια προπόνηση πριν από 9 και πριν από 2 μέρες, με τις ίδιες ασκήσεις
    final older = t.sessions.firstWhere((x) => x.id == 's9');
    final latest = t.sessions.firstWhere((x) => x.id == 's2');
    await _pump(tester, SummaryPage(training: t, session: older), size: const Size(400, 2400));
    await tester.pumpAndSettle();
    expect(find.text('Την επόμενη φορά'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, SummaryPage(training: t, session: latest), size: const Size(400, 2400));
    await tester.pumpAndSettle();
    expect(find.text('Την επόμενη φορά'), findsOneWidget, reason: 'η τελευταία φορά: ο στόχος είναι πράγματι ο επόμενος');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  // ---------------------------------------------------------------- R9-A6-9
  group('R9-A6-9: κάτω από το εύρος ΚΑΙ ως την εξάντληση: ένα σκαλί πιο ελαφριά', () {
    final press = it('db_press', sets: 3, lo: 8, hi: 12);

    test('πιεστικό 9,3 kg × 8, 7, 6 με «0» → 7,8 kg από 8, με την οδηγία για τα 2', () {
      final tg = nextTarget(press, [(ago(3), done('db_press', 9.3, [8, 7, 6], ra: 0, lo: 8, hi: 12))], now);
      expect(tg.change, Change.down);
      expect(tg.load, 7.8);
      expect(tg.reps, [8, 8, 8]);
      expect(tg.reason, contains('Δεν άφησες καμία'));
      expect(tg.reason, contains('σταμάτα το σετ όταν σου μένουν 2'));
    });

    test('μπάρα (RDL) 15 kg × 8, 7, 7 με «1» → 14,5 kg', () {
      final tg = nextTarget(it('rdl', sets: 3, lo: 8, hi: 12), [(ago(3), done('rdl', 15, [8, 7, 7], ra: 1, lo: 8, hi: 12))], now);
      expect((tg.change, tg.load), (Change.down, 14.5));
      expect(tg.reps, [8, 8, 8]);
      expect(tg.reason, contains('Άφησες 1'));
    });

    test('μέσα στο εύρος με «0»: όπως πριν (ίδια, όχι +1)· χωρίς απάντηση κάτω από το εύρος: όπως πριν', () {
      final inRange = nextTarget(press, [(ago(3), done('db_press', 9.3, [9, 8, 8], ra: 0, lo: 8, hi: 12))], now);
      expect((inRange.change, inRange.load), (Change.hold, 9.3));
      expect(inRange.reps, [9, 8, 8]);
      final noAnswer = nextTarget(press, [(ago(3), done('db_press', 11.8, [8, 7, 6], lo: 8, hi: 12))], now);
      expect((noAnswer.change, noAnswer.load), (Change.hold, 11.8));
      expect(noAnswer.reps, [8, 8, 8]);
    });

    test('άσκηση σώματος: ίδια, όχι περισσότερες, με την οδηγία', () {
      final tg = nextTarget(it('pushup_bench'), [(ago(3), done('pushup_bench', null, [9, 8], ra: 1))], now);
      expect(tg.change, Change.hold);
      expect(tg.load, isNull);
      expect(tg.reps, [9, 8]);
      expect(tg.reason, contains('όχι περισσότερες επαναλήψεις'));
    });
  });

  // ---------------------------------------------------------------- R9-A6-10
  group('R9-A6-10: «4+» δύο φορές στη σειρά: η συμβουλή του «+» και στα πόδια', () {
    const twice = 'Άφησες 4+ και τις δύο τελευταίες φορές';

    test('RDL 11 kg, hip thrust 7,8 kg, κέρατο 3 kg, goblet 10 kg: λέει ότι υπάρχει το «+»', () {
      final rdl = nextTarget(it('rdl', sets: 3, lo: 8, hi: 12), [
        (ago(7), done('rdl', 11, [10, 10, 10], ra: 4, lo: 8, hi: 12)),
        (ago(14), done('rdl', 11, [9, 9, 9], ra: 4, lo: 8, hi: 12)),
      ], now);
      expect((rdl.change, rdl.load), (Change.more, 11.0));
      expect(rdl.reps, [11, 11, 11]);
      expect(rdl.reason, contains(twice));
      expect(rdl.reason, contains('«+»'));
      final hip = nextTarget(it('hip_thrust'), [(ago(7), done('hip_thrust', 7.8, [12, 12], ra: 4)), (ago(14), done('hip_thrust', 7.8, [11, 11], ra: 4))], now);
      expect(hip.reason, contains(twice));
      final ext = nextTarget(it('leg_ext'), [(ago(7), done('leg_ext', 3, [12, 12], ra: 4)), (ago(14), done('leg_ext', 3, [11, 11], ra: 4))], now);
      expect(ext.reason, contains(twice));
      final gob = nextTarget(it('goblet', lo: 8, hi: 12), [
        (ago(7), done('goblet', 10, [10, 10], ra: 4, lo: 8, hi: 12)),
        (ago(14), done('goblet', 10, [9, 9], ra: 4, lo: 8, hi: 12)),
      ], now);
      expect(gob.reason, contains(twice));
    });

    test('μόνο μία φορά «4+», ή «3»: όχι· άσκηση προσοχής: όχι· face pull: ποτέ «+»', () {
      final rdl = it('rdl', sets: 3, lo: 8, hi: 12);
      final once = nextTarget(rdl, [
        (ago(7), done('rdl', 11, [10, 10, 10], ra: 4, lo: 8, hi: 12)),
        (ago(14), done('rdl', 11, [9, 9, 9], ra: 3, lo: 8, hi: 12)),
      ], now);
      expect(once.reason, isNot(contains(twice)));
      final three = nextTarget(rdl, [
        (ago(7), done('rdl', 11, [10, 10, 10], ra: 3, lo: 8, hi: 12)),
        (ago(14), done('rdl', 11, [9, 9, 9], ra: 4, lo: 8, hi: 12)),
      ], now);
      expect(three.reason, isNot(contains(twice)));
      final careful = nextTarget(it('shoulder_press', lo: 8, hi: 12), [
        (ago(7), done('shoulder_press', 4.3, [10, 10], ra: 4, lo: 8, hi: 12)),
        (ago(14), done('shoulder_press', 4.3, [9, 9], ra: 4, lo: 8, hi: 12)),
      ], now, caution: true);
      expect(careful.reason, isNot(contains('«+»')));
      final face = nextTarget(it('face_pull', lo: 12), [
        (ago(7), done('face_pull', 10, [13, 13], ra: 4, lo: 12)),
        (ago(14), done('face_pull', 10, [12, 12], ra: 4, lo: 12)),
      ], now);
      expect(face.reason, isNot(contains('«+»')));
    });

    test('αλτήρες με τη συμβουλή «τριπλάσιες» (S7-22): αυτή μένει, χωρίς δεύτερη', () {
      final tg = nextTarget(it('db_press', sets: 3, lo: 8, hi: 12), [
        (ago(7), done('db_press', 4.3, [10, 10, 10], ra: 4, lo: 8, hi: 12)),
        (ago(14), done('db_press', 4.3, [9, 9, 9], ra: 4, lo: 8, hi: 12)),
      ], now);
      expect(tg.reason, contains('τριπλάσιες'));
      expect(tg.reason, isNot(contains(twice)));
    });
  });

  // ---------------------------------------------------------------- R9-A7-1
  group('R9-A7-1: «τεστ ομιλίας»: ποτέ αντίθετα από την απάντηση', () {
    test('«τραγουδούσα» με ζώνη περπατήματος πάνω από υπολογισμό + 10: καμία πρόταση (όχι 118–140)', () {
      expect(talkProposal(answer: 'sing', walkLo: 120, walkHi: 142, baseLo: 108, baseHi: 131, nearSec: 300, aboveSec: 0), isNull);
      expect(talkProposal(answer: 'sing', walkLo: 125, walkHi: 145, baseLo: 113, baseHi: 131, nearSec: 300, aboveSec: 0), isNull);
    });

    test('«λαχάνιαζα» με ζώνη περπατήματος κάτω από υπολογισμό − 10: καμία πρόταση (όχι 94–117)', () {
      expect(talkProposal(answer: 'no', walkLo: 91, walkHi: 114, baseLo: 104, baseHi: 127, nearSec: 300, aboveSec: 0), isNull);
    });

    test('ζώνη περπατήματος 115–137, τωρινή 108–131: «λαχάνιαζα» → πρόταση 110–132 που θα ΑΝΕΒΑΖΕ την τωρινή: όχι', () {
      final p = talkProposal(answer: 'no', walkLo: 115, walkHi: 137, baseLo: 108, baseHi: 131, nearSec: 600, aboveSec: 0);
      expect(p, (110, 132));
      expect(talkMovesZone(-5, 110, 132, 108, 131), isFalse);
      // ίδια κατεύθυνση με την απάντηση: ναι
      expect(talkMovesZone(-5, 99, 122, 104, 127), isTrue);
      expect(talkMovesZone(5, 109, 132, 104, 127), isTrue);
      // ήδη εκεί, ή ανάποδα: όχι
      expect(talkMovesZone(5, 104, 127, 104, 127), isFalse);
      expect(talkMovesZone(5, 118, 140, 120, 142), isFalse);
    });
  });

  // ---------------------------------------------------------------- R9-A7-3
  testWidgets('R9-A7-3: μερικό περπάτημα: η πτώση παλμών λέει ότι η εφαρμογή του ρολογιού έκλεισε', (tester) async {
    final start = DateTime(2026, 11, 17, 18);
    final s = Session(
      id: 'w-1',
      workout: 'walk',
      name: 'Περπάτημα',
      programId: 'p',
      start: start,
      end: start.add(const Duration(minutes: 30)),
      cardioMinutes: 30,
      cardioSec: 1800,
      partial: true,
    );
    expect(RecoveryCard.shows(s), isTrue);
    await _pump(tester, Scaffold(body: SingleChildScrollView(child: RecoveryCard(session: s))));
    final text = tester.widget<Text>(find.byKey(const ValueKey('hrr-none'))).data!;
    expect(text, 'Δεν μετρήθηκε: η εφαρμογή του ρολογιού έκλεισε πριν το «Τέλος».');
    expect(text, isNot(contains('Παράλειψη')));
    // κανονικό «Τέλος» χωρίς αριθμό: οι τρεις αιτίες, όπως πριν
    s.partial = false;
    await _pump(tester, Scaffold(body: SingleChildScrollView(child: RecoveryCard(session: s, key: UniqueKey()))));
    expect(tester.widget<Text>(find.byKey(const ValueKey('hrr-none'))).data, contains('Παράλειψη'));
  });

  // ---------------------------------------------------------------- R9-A7-4
  test('R9-A7-4: «χωρίς επαφή ή αναξιόπιστες»: το τρίτο νούμερο του ρολογιού μετρά και τις δύο', () {
    expect(hrQualityText(const HrQualityCounts(10, 0, 3)), 'Μετρήσεις ρολογιού: 10 με καλή επαφή · 3 χωρίς επαφή ή αναξιόπιστες (δεν μέτρησαν).');
  });

  // ---------------------------------------------------------------- R9-A8-1
  group('R9-A8-1: «Συνέχεια» δεν μεταφέρει το τέλος της ξεχασμένης προπόνησης', () {
    final t0 = DateTime(2026, 11, 16, 18);
    (TrainingStore, Session, void Function(Duration)) setup() {
      var at = t0;
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => at)..replaceAll(sampleTraining(t0).toJson());
      t.ready = true;
      final s = t.start(t.program!.workout('A')!);
      at = t0.add(const Duration(hours: 1));
      t.tick(s.items.first, 0);
      // ξεχάστηκε· την επομένη στις 08:00 «Συνέχεια», καμία κίνηση μετά
      at = t0.add(const Duration(hours: 14));
      t.resume(s);
      return (t, s, (d) => at = t0.add(d));
    }

    test('«Τέλος» στο κινητό 3,5 ώρες μετά τη «Συνέχεια»: τέλος στο τελευταίο ✓ (19:00), όχι 08:00', () {
      final (t, s, clock) = setup();
      clock(const Duration(hours: 17, minutes: 30));
      t.finish();
      expect(s.end, t0.add(const Duration(hours: 1)));
    });

    test('«Τέλος» 1 ώρα μετά τη «Συνέχεια», χωρίς ✓: πάλι στο τελευταίο ✓, όχι διάρκεια 15 ωρών', () {
      final (t, s, clock) = setup();
      clock(const Duration(hours: 15));
      t.finish();
      expect(s.end, t0.add(const Duration(hours: 1)));
    });

    test('«Τέλος» στο ρολόι 3,5 ώρες μετά τη «Συνέχεια»: τέλος στο τελευταίο ✓', () {
      final (t, s, clock) = setup();
      clock(const Duration(hours: 17, minutes: 30));
      expect(t.endFromWatch(s.id, t0.add(const Duration(hours: 17, minutes: 30)).millisecondsSinceEpoch), isTrue);
      expect(s.end, t0.add(const Duration(hours: 1)));
    });

    test('«Τέλος (στις 19:00)» της κάρτας και μετά το αποτέλεσμα του ρολογιού: το τέλος δεν «επεκτείνεται» στη «Συνέχεια»', () {
      final (t, s, clock) = setup();
      clock(const Duration(hours: 17, minutes: 30));
      t.finish(end: s.lastTick);
      expect(s.end, t0.add(const Duration(hours: 1)));
      expect(
          t.importWatch({
            'v': 1,
            'kind': 'hr',
            'sid': s.id,
            'hrT0': t0.millisecondsSinceEpoch,
            'hr': const <List<int>>[],
            'fin': t0.add(const Duration(hours: 17, minutes: 30)).millisecondsSinceEpoch,
          }),
          isTrue);
      expect(s.end, t0.add(const Duration(hours: 1)));
    });
  });

  // ---------------------------------------------------------------- R9-A8-2
  group('R9-A8-2: ξεχασμένη προπόνηση με το ρολόι να μετρά: μέσος/υψηλότερος μόνο ως το τέλος', () {
    final t0 = DateTime(2026, 11, 16, 18);
    // Παλμοί 115 ως το 61′ (ανά 10″, ✓ στο 60′), μετά 75 (καθισμένος) ως το 240′.
    (TrainingStore, Session) setup(void Function(DateTime) setClock, TrainingStore t) {
      final s = t.start(t.program!.workout('A')!);
      for (var k = 0; k < 1440; k++) {
        final at = t0.add(Duration(seconds: 10 * k));
        setClock(at);
        if (k == 360) t.tick(s.items.first, 0);
        t.addHr(k <= 366 ? 115 : 75, at, sid: s.id);
      }
      return (t, s);
    }

    Map<String, dynamic> hrResult(Session s, DateTime fin) => {
          'v': 1,
          'kind': 'hr',
          'sid': s.id,
          'hrT0': t0.millisecondsSinceEpoch,
          'hrAvg': 85,
          'hrMax': 140,
          'hr': [
            for (var k = 0; k < 14460; k += 5) [k, k <= 3660 ? 115 : (k == 7200 ? 140 : 75)],
          ],
          'fin': fin.millisecondsSinceEpoch,
        };

    test('«Τέλος» στο ρολόι στις 22:01 → τέλος 19:00 και μέσος 115 (όχι 85)· μετά το αποτέλεσμα «hr»: ίδια', () {
      var at = t0;
      final store = TrainingStore(io: MemoryTrainingIO(), clock: () => at)..replaceAll(sampleTraining(t0).toJson());
      store.ready = true;
      final (t, s) = setup((v) => at = v, store);
      final fin = t0.add(const Duration(minutes: 241));
      at = fin;
      expect(t.endFromWatch(s.id, fin.millisecondsSinceEpoch), isTrue);
      expect(s.end, t0.add(const Duration(minutes: 60)));
      expect(s.hrAvg, 115);
      expect(s.hrMax, 115);
      expect(s.hr.last[0], lessThanOrEqualTo(3660));
      expect(t.importWatch(hrResult(s, fin)), isTrue);
      expect(s.end, t0.add(const Duration(minutes: 60)));
      expect(s.hrAvg, 115);
      expect(s.hrMax, 115, reason: 'η κορυφή 140 στις 20:00 δεν είναι της προπόνησης');
      expect(s.hr.last[0], lessThanOrEqualTo(3660));
    });

    test('«Τέλος (στις 19:00)» της κάρτας «Ξεχασμένη προπόνηση;» όσο το ρολόι μετρά: ίδια', () {
      var at = t0;
      final store = TrainingStore(io: MemoryTrainingIO(), clock: () => at)..replaceAll(sampleTraining(t0).toJson());
      store.ready = true;
      final (t, s) = setup((v) => at = v, store);
      at = t0.add(const Duration(minutes: 241));
      t.finish(end: s.lastTick);
      expect(s.hrAvg, 115);
      expect(s.hrMax, 115);
      t.importWatch(hrResult(s, t0.add(const Duration(minutes: 241))));
      expect(s.hrAvg, 115);
      expect(s.hrMax, 115);
    });

    test('κανονικό «Τέλος» (παλμοί ως το τέλος): ο μέσος και ο υψηλότερος του ρολογιού, όπως πριν', () {
      final s = Session(id: 's1', workout: 'A', name: 'Α', programId: 'p', start: t0, end: t0.add(const Duration(minutes: 60)));
      TrainingStore.mergeHrSegment(s, [for (var k = 0; k <= 3600; k += 5) [k, 110]], watchAvg: 108, watchMax: 131);
      expect(s.hrAvg, 108);
      expect(s.hrMax, 131);
    });
  });

  // ---------------------------------------------------------------- R9-A8-3 (κινητό)
  group('R9-A8-3: η απάντηση «Πρώτο σετ» του ρολογιού και μέσα στο αποτέλεσμα («fr»)', () {
    final t0 = DateTime(2026, 11, 20, 17, 30);
    Map<String, dynamic> result(Session s, List<Map<String, dynamic>> items) =>
        {'v': 1, 'kind': 'hr', 'sid': s.id, 'hrT0': t0.millisecondsSinceEpoch, 'hr': const <List<int>>[], 'items': items};
    Map<String, dynamic> withFr(ExLog e, int fr) => {...jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>, 'fr': fr};

    test('η «rir1» χάθηκε, η ερώτηση εκκρεμεί: «fr» 0 → τα επόμενα σετ ένα σκαλί πιο ελαφριά (9,3 → 7,8 kg)', () {
      final t = sampleTraining(t0, history: false);
      final s = t.start(t.program!.workout('A')!);
      final e = s.items.first;
      t.tick(e, 0);
      expect(t.firstPending(e), isTrue);
      expect(t.importWatch(result(s, [withFr(e, 0)])), isTrue);
      expect(e.firstAnswer, 0);
      expect(e.log[1].load, 7.8);
      expect(e.log[2].load, 7.8);
      // το ίδιο αποτέλεσμα ξανά: τίποτα
      t.importWatch(result(s, [withFr(e, 4)]));
      expect(e.firstAnswer, 0);
      expect(e.log[1].load, 7.8);
    });

    test('το κινητό έχει ήδη απάντηση: η πρώτη κερδίζει· δεν εκκρεμεί πια: μόνο για το αρχείο', () {
      final t = sampleTraining(t0, history: false);
      final s = t.start(t.program!.workout('A')!);
      final a = s.items[0], b = s.items[1];
      t.tick(a, 0);
      t.answerFirst(a, 3);
      t.tick(b, 0);
      t.tick(b, 1);
      expect(t.firstPending(b), isFalse);
      t.importWatch(result(s, [withFr(a, 0), withFr(b, 1)]));
      expect(a.firstAnswer, 3);
      expect(a.log[1].load, 9.3);
      expect(b.firstAnswer, 1);
      expect(b.log[2].load, 14.3, reason: 'τα σετ έγιναν ήδη: καμία αλλαγή βάρους');
    });

    test('τιμές: −3 → −1 («Δεν ξέρω»), 7 → 4, όχι αριθμός → τίποτα· προπόνηση μόνο στο ρολόι: «fr» → «fa»', () {
      ExLog w(Object? fr) => ExLog.fromJson({'ex': 'db_press', 'sets': 3, 'lo': 8, 'hi': 12, 'log': const [], 'fr': fr});
      expect(TrainingStore.watchFirstAnswer(w(-3)), -1);
      expect(TrainingStore.watchFirstAnswer(w(7)), 4);
      expect(TrainingStore.watchFirstAnswer(w(2)), 2);
      expect(TrainingStore.watchFirstAnswer(w('x')), isNull);
      final t = sampleTraining(t0, history: false);
      expect(
          t.importWatch({
            'v': 1,
            'kind': 'strength',
            'id': 'x1',
            'start': t0.millisecondsSinceEpoch,
            'end': t0.add(const Duration(minutes: 40)).millisecondsSinceEpoch,
            'items': [
              {'ex': 'db_press', 'sets': 3, 'lo': 8, 'hi': 12, 'rir': 3, 'rest': 90, 'fr': 4, 'log': [
                {'l': 9.3, 'r': 8, 'd': 1, 't': t0.add(const Duration(minutes: 5)).millisecondsSinceEpoch},
              ]},
              {'ex': 'db_row', 'sets': 3, 'lo': 8, 'hi': 12, 'rir': 3, 'rest': 90, 'fa': 2, 'fr': 4, 'log': [
                {'l': 14.3, 'r': 8, 'd': 1, 't': t0.add(const Duration(minutes: 15)).millisecondsSinceEpoch},
              ]},
            ],
          }),
          isTrue);
      final f = t.sessions.firstWhere((x) => x.id == 'w-x1');
      expect(f.items[0].firstAnswer, 4);
      expect(f.items[1].firstAnswer, 2, reason: 'η απάντηση που υπάρχει κερδίζει');
    });
  });

  // ---------------------------------------------------------------- R9-U3-04
  group('R9-U3-04: «πάτα «Περπάτημα»» μαζί, ποτέ η λέξη μόνη της στη 2η γραμμή', () {
    testWidgets('Σήμερα και Άσκηση, μέρα βαρών', (tester) async {
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final fri = DateTime(2026, 11, 13, 17, 30);
      await _pump(tester, Scaffold(body: SingleChildScrollView(child: TodayTrainingCard(training: sampleTraining(fri), now: fri))),
          size: const Size(360, 1400));
      expect(find.text('Για περπάτημα: στο ρολόι πάτα «Περπάτημα».'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, Scaffold(body: TrainingPage(training: sampleTraining(fri), now: fri)), size: const Size(360, 2400));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const ValueKey('train-today')), matching: find.text('Για περπάτημα: στο ρολόι πάτα «Περπάτημα».')),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  // ---------------------------------------------------------------- R9-U3-06
  group('R9-U3-06: η προπόνηση «για σήμερα» της Άσκησης είναι και της Σήμερα', () {
    final fri = DateTime(2026, 11, 13, 17, 30); // «A» στο δείγμα

    test('η επιλογή ισχύει μόνο εκείνη τη μέρα και τελειώνει με την έναρξη', () {
      final t = sampleTraining(fri);
      expect(t.chosenOn(fri), isNull);
      t.choose('B', fri);
      expect(t.chosenOn(fri), 'B');
      expect(t.chosenOn(fri.add(const Duration(days: 1))), isNull);
      t.start(t.program!.workout('A')!);
      expect(t.chosenOn(fri), isNull);
      // πριν από την έναρξη του προγράμματος (13/11): χωρίς επιλογή καμία κάρτα, με επιλογή η κάρτα
      final thu = DateTime(2026, 11, 12, 10);
      final t2 = sampleTraining(thu, history: false);
      expect(TodayTrainingCard.shows(t2, thu), isFalse);
      t2.choose('A', thu);
      expect(TodayTrainingCard.shows(t2, thu), isTrue);
    });

    testWidgets('«Σήμερα: Προπόνηση Β» → η Σήμερα δείχνει τη Β, και το «Ξεκίνα» ξεκινά τη Β', (tester) async {
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final t = sampleTraining(fri);
      t.choose('B', fri);
      await _pump(tester, Scaffold(body: SingleChildScrollView(child: TodayTrainingCard(training: t, now: fri))));
      expect(find.text('Προπόνηση Β'), findsOneWidget);
      expect(find.text('Προπόνηση Α'), findsNothing);
      expect(find.byKey(const ValueKey('today-train-chosen')), findsOneWidget);
      await _tapKey(tester, 'today-train-start');
      await tester.pumpAndSettle();
      expect(t.current!.workout, 'B');
      expect(t.chosenOn(fri), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  // ---------------------------------------------------------------- R9-U3-07
  test('R9-U3-07: οι οδηγίες των ασκήσεων γράφουν τα δευτερόλεπτα ολογράφως (κανένα «1″», «2–3″»)', () {
    final lib = ExLibrary.fromJson(jsonDecode(File('assets/exercises/exercises.json').readAsStringSync()) as Map<String, dynamic>);
    final mark = RegExp(r'\d[″′]');
    for (final e in lib.list) {
      final texts = [
        e.feel,
        if (e.caution != null) e.caution!,
        ...e.setup,
        ...e.steps,
        for (final c in e.cues) c.text,
        ...e.mistakes,
        ...e.tips,
        for (final p in e.tempo) p.name,
        for (final m in [...e.primary, ...e.secondary]) m.note,
      ];
      for (final x in texts) {
        expect(mark.hasMatch(x), isFalse, reason: '${e.id}: $x');
      }
    }
    expect(lib.byId('db_curl')!.cues.map((c) => c.text), contains('Κατέβασε σε 2–3 δευτερόλεπτα, ως κάτω.'));
    expect(lib.byId('crunch')!.steps, contains('Κράτα 1 δευτερόλεπτο και κατέβα αργά.'));
  });

  // ---------------------------------------------------------------- R9-U3-08
  group('R9-U3-08: «+ Σετ»: η άσκηση τελειώνει με την τελευταία γραμμή, όπως στο ρολόι', () {
    test('3 σετ + 1: μετά το 3ο τα σετ του προγράμματος έγιναν, η άσκηση όχι', () {
      final e = done('db_press', 9.3, [10, 10, 10], lo: 8, hi: 12)..log.add(SetLog(load: 9.3, reps: 10));
      expect(e.complete, isTrue);
      expect(e.rowsDone, isFalse);
      e.log.last.done = true;
      expect(e.rowsDone, isTrue);
    });

    testWidgets('✓ 1–3: καμία ερώτηση, μένει στην άσκηση («3/4»)· ✓ 4: «Τελευταίο σετ», μετά η επόμενη', (tester) async {
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final store = sampleTraining(now);
      final s = store.start(store.program!.workout('A')!);
      final e = s.items.first;
      store.addSet(e);
      expect(e.log.length, 4);
      await _pump(tester, SessionPage(training: store));
      for (var i = 0; i < 3; i++) {
        await _tapKey(tester, 'sess-tick-$i');
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('Τελευταίο σετ: πόσες ακόμα θα έβγαζες;'), findsNothing);
      expect(store.focus, 0);
      expect(e.rirAnswer, isNull);
      expect(find.descendant(of: find.byKey(const ValueKey('sess-ex-0')), matching: find.text('3/4')), findsOneWidget);
      await _tapKey(tester, 'sess-tick-3');
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Τελευταίο σετ: πόσες ακόμα θα έβγαζες;'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rir-3')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rir-ok')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(e.rirAnswer, 3);
      expect(store.focus, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
