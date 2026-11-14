// Γύρος 8, f2 (προπόνηση, πλευρά κινητού): δοκιμές για τα R8-A6-1…6, R8-A7-1…5, R8-U3-01/02/04/05/07/08/09, R8-U3-Β1,
// R8-A8-2 (κινητό), R8-A8-3, R8-A8-5. Οι αναμενόμενες τιμές βγαίνουν από τους κανόνες όπως γράφονται (σκαλιά του
// εξοπλισμού, Karvonen 40–59%, Tanaka 208 − 0,7 × ηλικία), όχι από την υλοποίηση. Όλες οι τιμές είναι επινοημένες.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart' show HealthStore;
import 'package:ygeia_forma/exercise/ex_data.dart';
import 'package:ygeia_forma/exercise/ex_player.dart' show ExClock;
import 'package:ygeia_forma/format.dart' show shortDayDate;
import 'package:ygeia_forma/history.dart' show K, dateKey;
import 'package:ygeia_forma/pages/exercise_detail.dart';
import 'package:ygeia_forma/pages/training/hr_widgets.dart' show HrStale;
import 'package:ygeia_forma/pages/training/progress_page.dart' show progressHighlights;
import 'package:ygeia_forma/pages/training/session_page.dart';
import 'package:ygeia_forma/pages/training/training_common.dart' show BandDots, ForgottenWorkout;
import 'package:ygeia_forma/pages/training/training_page.dart';
import 'package:ygeia_forma/pages/training/zone_widgets.dart';
import 'package:ygeia_forma/profile.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/training/equipment.dart';
import 'package:ygeia_forma/training/program.dart';
import 'package:ygeia_forma/training/progress.dart';
import 'package:ygeia_forma/training/progression.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/training_store.dart';
import 'package:ygeia_forma/training/wear_link.dart';
import 'package:ygeia_forma/training/zone.dart';
import 'package:ygeia_forma/trends.dart' show TrendPeriod;
import 'package:ygeia_forma/widgets.dart' show InfoRow, LineChart, TrendKind;

import 'training_sample.dart';

final now = DateTime(2026, 11, 20, 18); // Παρασκευή
DateTime ago(int days) => DateTime(2026, 11, 20 - days, 18);

PlanItem it(String ex, {int sets = 2, int lo = 10, int hi = 15, int rir = 3, double? load, String? next}) =>
    PlanItem(ex: ex, sets: sets, lo: lo, hi: hi, rir: rir, rest: 90, load: load, next: next);

/// Μία άσκηση που έγινε: [sets] = τα σετ του προγράμματος εκείνη τη μέρα (ως προεπιλογή όσα και τα [reps]).
ExLog done(String ex, double? load, List<int> reps, {int? ra, int lo = 10, int hi = 15, List<String>? pain, int? sets}) => ExLog(
      ex: ex,
      sets: sets ?? reps.length,
      lo: lo,
      hi: hi,
      rir: 3,
      rest: 90,
      rirAnswer: ra,
      pain: pain,
      log: [for (final r in reps) SetLog(load: load, reps: r, done: true)],
    );

/// Σετ με διαφορετικά φορτία: [(φορτίο, επαναλήψεις)].
ExLog mixed(String ex, List<(double, int)> sets, {int lo = 8, int hi = 12}) => ExLog(
      ex: ex,
      sets: sets.length,
      lo: lo,
      hi: hi,
      rir: 3,
      rest: 90,
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

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 1400), double scale = 1}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.light),
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
    home: w,
  ));
  await t.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Η γραμματοσειρά της εφαρμογής (όπως στα στιγμιότυπα): τα πλάτη και οι αλλαγές γραμμής όπως στη συσκευή.
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
  });

  // ---------------------------------------------------------------- R8-A6-1 / R8-U3-08
  group('R8-A6-1 / U3-08: «Η πρόοδός σου» μόνο με φορές που έγιναν σετ, με το φορτίο που κατέληξε', () {
    late TrainingStore previous;
    setUp(() {
      previous = TrainingStore.main;
      ExClock.frozen = true;
    });
    tearDown(() {
      TrainingStore.main = previous;
      ExClock.frozen = false;
    });

    testWidgets('παράλειψη στη μέση: κανένα «0 kg», 2 γραμμές, γράφημα 4,3 → 5,3 (τελικό φορτίο)', (t) async {
      await t.runAsync(() => ExLibrary.load(inline: true));
      final a = ago(7), b = ago(4), c = ago(0);
      final skipped = ExLog(ex: 'db_press', sets: 2, lo: 8, hi: 12, rir: 3, rest: 90, skipped: true, log: [
        SetLog(load: 4.3, reps: 10),
        SetLog(load: 4.3, reps: 10),
      ]);
      final store = TrainingStore(io: MemoryTrainingIO(), clock: () => now)..ready = true;
      store.sessions
        ..add(finished('a', a, [done('db_press', 4.3, [10, 10], lo: 8, hi: 12)]))
        ..add(finished('b', b, [skipped]))
        ..add(finished('c', c, [mixed('db_press', [(6.8, 8), (5.3, 10)])]));
      TrainingStore.main = store;
      final l = ExLibrary.loaded!;
      await _pump(t, ExerciseDetailPage(ex: l.byId('db_press')!, lib: l), size: const Size(860, 1400));
      expect(find.text('Η πρόοδός σου'), findsOneWidget);
      final rows = [for (final r in t.widgetList<InfoRow>(find.byType(InfoRow))) (r.label, r.value)];
      expect(rows, [
        (shortDayDate(c), '6,8 kg × 8 · 5,3 kg × 10'),
        (shortDayDate(a), '4,3 kg · 10, 10'),
      ]);
      expect(rows.any((r) => r.$2.startsWith('0 kg')), isFalse);
      final chart = t.widget<LineChart>(find.byType(LineChart));
      expect(chart.points, [(a, 4.3), (c, 5.3)]);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('μόνο μια παράλειψη: καμία κάρτα· ενόχληση χωρίς σετ: η κάρτα λέει «ενόχληση»', (t) async {
      await t.runAsync(() => ExLibrary.load(inline: true));
      final store = TrainingStore(io: MemoryTrainingIO(), clock: () => now)..ready = true;
      store.sessions.add(finished('a', ago(3), [
        ExLog(ex: 'db_press', sets: 2, lo: 8, hi: 12, rir: 3, rest: 90, skipped: true, log: [SetLog(load: 4.3, reps: 10)]),
      ]));
      TrainingStore.main = store;
      final l = ExLibrary.loaded!;
      await _pump(t, ExerciseDetailPage(ex: l.byId('db_press')!, lib: l), size: const Size(860, 1400));
      expect(find.text('Η πρόοδός σου'), findsNothing);
      store.sessions.add(finished('b', ago(1), [
        ExLog(ex: 'db_press', sets: 2, lo: 8, hi: 12, rir: 3, rest: 90, skipped: true, pain: ['shoulderR'], log: [SetLog(load: 4.3, reps: 10)]),
      ]));
      await _pump(t, ExerciseDetailPage(ex: l.byId('db_press')!, lib: l, key: UniqueKey()), size: const Size(860, 1400));
      expect(find.text('Τελευταία φορά: ενόχληση'), findsOneWidget);
      expect(find.byType(InfoRow), findsNothing);
      await t.pumpWidget(const SizedBox());
    });
  });

  // ---------------------------------------------------------------- R8-A6-2 / R8-U3-09
  group('R8-A6-2 / U3-09: «Τι άλλαξε» με το φορτίο που κατέληξε, όπως η κρίση', () {
    final walk = walkProgress(const <Session>[], now, TrendPeriod.quarter);
    ExProgress p(ExLog before, ExLog after) =>
        ExProgress(ex: 'db_press', kind: LoadKind.dbPair, beforeDay: ago(7), before: before, nowDay: ago(0), now: after);

    test('πριν 6,8 × 8 → 5,3 × 10, τώρα 6,8 × 8, 8: «5,3 kg → 6,8 kg» με πράσινο (όχι «6,8 kg → 6,8 kg»)', () {
      final x = p(mixed('db_press', [(6.8, 8), (5.3, 10)]), mixed('db_press', [(6.8, 8), (6.8, 8)]));
      expect(x.change, StrengthChange.up);
      final h = progressHighlights(walk, [x], const []);
      expect(h.single.$1, endsWith(': 5,3 kg → 6,8 kg'));
      expect(h.single.$2, TrendKind.good);
    });

    test('πριν 6,8 × 8, 8, τώρα 6,8 × 8 → 5,3 × 8: «6,8 kg → 5,3 kg»', () {
      final x = p(mixed('db_press', [(6.8, 8), (6.8, 8)]), mixed('db_press', [(6.8, 8), (5.3, 8)]));
      expect(x.change, StrengthChange.down);
      expect(progressHighlights(walk, [x], const []).single.$1, endsWith(': 6,8 kg → 5,3 kg'));
    });
  });

  // ---------------------------------------------------------------- R8-A6-3
  group('R8-A6-3: ένα σετ παραπάνω («+ Σετ») δεν κρίνεται', () {
    test('goblet 2 × 10–15, 10 kg: 15, 15 και ένα τρίτο 13 (άφησε 3) → ανεβαίνει σε 12 kg, ξανά από 10', () {
      // όπως χωρίς το τρίτο σετ: kettlebell 10 → 12 (+20%, όχι πάνω από 20%: το πάνω όριο 15 φτάνει)
      final tg = nextTarget(it('goblet'), [(ago(3), done('goblet', 10, [15, 15, 13], ra: 3, sets: 2))], now);
      expect(tg.change, Change.up);
      expect(tg.load, 12);
      expect(tg.reps, [10, 10]);
      final ref = nextTarget(it('goblet'), [(ago(3), done('goblet', 10, [15, 15], ra: 3))], now);
      expect((ref.change, ref.load), (tg.change, tg.load));
      expect(ref.reps, tg.reps);
    });

    test('ένα τρίτο σετ των 5, δύο φορές στη σειρά: ποτέ «ένα σκαλί κάτω»', () {
      final tg = nextTarget(it('goblet'), [
        (ago(3), done('goblet', 10, [15, 15, 5], ra: 3, sets: 2)),
        (ago(6), done('goblet', 10, [15, 15, 5], ra: 3, sets: 2)),
      ], now);
      expect(tg.change, isNot(Change.down));
      expect((tg.change, tg.load), (Change.up, 12.0));
    });

    test('αλτήρες 9,3 kg × 12, 12 και ένα τρίτο 10 (άφησε 4+) → 10,3 kg (+10,8%, όχι μεγάλο σκαλί), από 8', () {
      final tg = nextTarget(it('db_press', lo: 8, hi: 12), [(ago(3), done('db_press', 9.3, [12, 12, 10], ra: 4, lo: 8, hi: 12, sets: 2))], now);
      expect((tg.change, tg.load), (Change.up, 10.3));
      expect(tg.reps, [8, 8]);
    });

    test('αλλαγή άσκησης στη μέση (R7-A8-4): 2 από τα 3 σετ του προγράμματος μένουν «δεν έγιναν όλα»', () {
      final e = done('db_press', 9.3, [12, 12], ra: 3, lo: 8, hi: 12)..plannedSets = 3;
      final tg = nextTarget(it('db_press', sets: 3, lo: 8, hi: 12), [(ago(3), e)], now);
      expect((tg.change, tg.load), (Change.hold, 9.3));
    });
  });

  // ---------------------------------------------------------------- R8-A6-4
  group('R8-A6-4: δίσκος στο στήθος από δύο δίσκους', () {
    test('1,75 kg = 1,25 + 0,5· 1 kg = 0,5 + 0,5· 2,5 kg ένας δίσκος', () {
      expect(setupText(LoadKind.plate, 1.75), 'δύο δίσκοι μαζί: 1,25 + 0,5 kg');
      expect(setupText(LoadKind.plate, 1.0), 'δύο δίσκοι μαζί: 0,5 + 0,5 kg');
      expect(setupText(LoadKind.plate, 2.5), 'δίσκος 2,5 kg');
      expect(setupText(LoadKind.plate, 0), 'χωρίς βάρος');
      expect(loadLabel(LoadKind.plate, 1.75), 'δίσκοι 1,25 + 0,5 kg');
      expect(loadLabel(LoadKind.plate, 0.5), 'δίσκος 0,5 kg');
      expect(loadLabel(LoadKind.plate, 0), 'χωρίς δίσκο');
    });

    test('κάθε βάρος που βγαίνει: το πολύ δύο δίσκοι που υπάρχουν, με άθροισμα ίσο με το βάρος', () {
      for (final v in available(LoadKind.plate)) {
        if (v <= 0) continue;
        final p = platesPerSide(LoadKind.plate, v);
        expect(p, isNotNull, reason: '$v');
        expect(p!.length, inInclusiveRange(1, 2), reason: '$v');
        expect(p.every(plateKinds.contains), isTrue, reason: '$v');
        expect(p.fold<double>(0, (s, x) => s + x), closeTo(v, 1e-9), reason: '$v');
      }
    });
  });

  // ---------------------------------------------------------------- R8-A6-5
  group('R8-A6-5: «4+» στο 1ο σετ χωρίς αλλαγή βάρους: λέγεται γιατί', () {
    test('αλτήρες 4,3 kg × 8 (8–12, άφησε 3): μένει, και το «+»', () {
      // 4,3 → 5,3 kg = +23%: θέλει 18 επαναλήψεις (Epley)· 8 + (4 − 3) = 9 < 18
      expect(calibrate(it('db_press', lo: 8, hi: 12), 4.3, 8, 4), isNull);
      expect(calibrateNote(it('db_press', lo: 8, hi: 12), 4.3, 8, 4),
          'Τα επόμενα σετ μένουν 4,3 kg: το επόμενο σκαλί, 5,3 kg, θέλει πρώτα περισσότερες επαναλήψεις με αυτό. '
          'Αν είναι πολύ ελαφρύ, πάτα «+» στο βάρος.');
    });

    test('face pull κίτρινο: χωρίς «+» (η βιβλιοθήκη θέλει πάντα ελαφρύ)· εξωτερική στροφή: «μένει ελαφρύ»', () {
      final f = calibrateNote(it('face_pull', lo: 12), 10, 12, 4)!;
      expect(f, startsWith('Τα επόμενα σετ μένουν κίτρινο (10 lb): το επόμενο σκαλί, μπλε (20 lb),'));
      expect(f, isNot(contains('«+»')));
      expect(calibrateNote(it('band_er', lo: 12), 10, 12, 4), 'Τα επόμενα σετ μένουν κίτρινο (10 lb): σε αυτή την άσκηση το λάστιχο μένει ελαφρύ.');
    });

    test('όταν το βάρος αλλάζει ή η απάντηση δεν είναι «4+»: κανένα μήνυμα', () {
      expect(calibrate(it('goblet'), 8, 10, 4), 10);
      expect(calibrateNote(it('goblet'), 8, 10, 4), isNull);
      expect(calibrateNote(it('db_press', lo: 8, hi: 12), 4.3, 8, 3), isNull);
      expect(calibrateNote(it('db_press', lo: 8, hi: 12), 4.3, 8, 1), isNull);
      expect(calibrateNote(it('pushup_bench'), null, 10, 4), isNull);
    });

    testWidgets('πρώτη φορά, ✓ στο κινητό, «4+» με 9,3 kg × 8: μένει 9,3 kg και το λέει', (tester) async {
      final at = DateTime(2026, 11, 13, 17, 30);
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final store = sampleTraining(at, history: false);
      final s = store.start(store.program!.workout('A')!);
      await _pump(tester, SessionPage(training: store));
      await tester.ensureVisible(find.byKey(const ValueKey('sess-tick-0')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('sess-tick-0')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Πρώτο σετ: πόσες ακόμα θα έβγαζες;'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rir-4')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rir-ok')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // 9,3 → 10,3 kg (+10,8%): το πάνω όριο 12· 8 + (4 − 2) = 10 < 12 → μένει
      expect(s.items.first.log[1].load, 9.3);
      expect(find.textContaining('Τα επόμενα σετ μένουν 9,3 kg: το επόμενο σκαλί, 10,3 kg'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  // ---------------------------------------------------------------- R8-A6-6
  test('R8-A6-6: κανένα «⋮», «✓», «♥» (δεν υπάρχουν στο Inter) στους λόγους του στόχου', () {
    final press = it('db_press', lo: 8, hi: 12);
    final pain1 = nextTarget(press, [(ago(3), done('db_press', 9.3, [12, 12], ra: 3, lo: 8, hi: 12, pain: ['shoulderR']))], now);
    final pain2 = nextTarget(press, [
      (ago(3), done('db_press', 7.8, [12, 12], ra: 3, lo: 8, hi: 12, pain: ['shoulderR'])),
      (ago(6), done('db_press', 9.3, [12, 12], ra: 3, lo: 8, hi: 12, pain: ['shoulderR'])),
    ], now);
    // σώμα με πιο δύσκολη παραλλαγή: 2 × 20 (πάνω όριο 15 + 5) με «άφησα 3» → πρόταση παραλλαγής
    final variant = nextTarget(it('pushup_bench', next: 'pushup_handles'), [(ago(3), done('pushup_bench', null, [20, 20], ra: 3))], now);
    expect(variant.change, Change.variant);
    for (final r in [pain1.reason, pain2.reason, variant.reason]) {
      expect(r.contains('⋮') || r.contains('✓') || r.contains('♥'), isFalse, reason: r);
      expect(r, contains('τρεις τελείες, πάνω δεξιά › «Αλλαγή άσκησης»'));
    }
  });

  testWidgets('R8-A6-6: ασκήσεις μίας πλευράς: «μετά «Έγινε»», όχι «✓»', (tester) async {
    final at = DateTime(2026, 11, 13, 17, 30);
    await tester.runAsync(() => ExLibrary.load(inline: true));
    final store = sampleTraining(at);
    store.start(store.program!.workout('A')!);
    await _pump(tester, SessionPage(training: store));
    store.focus = 1; // κωπηλασία με αλτήρα
    await tester.pump();
    final text = tester.widget<Text>(find.byKey(const ValueKey('sess-per-side'))).data!;
    expect(text, 'Κάθε σετ: δεξιά και αριστερά, μετά «Έγινε».');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  // ---------------------------------------------------------------- R8-A7
  group('R8-A7: κείμενα της ζώνης που λένε ό,τι κάνει ο κώδικας', () {
    const me = Profile(birthYear: 1985, birthMonth: 1, sex: 'm', heightCm: 180);
    final day = DateTime(2026, 11, 13);
    final when = DateTime(2026, 11, 13, 10);

    /// 9 νύχτες παλμών ύπνου 58 (λιγότερες από 14, τουλάχιστον 7).
    HealthStore nine() {
      final h = HealthStore()
        ..history = {
          for (var i = 1; i <= 9; i++) dateKey(DateTime(day.year, day.month, day.day - i)): {K.sleepHr: 58.0},
        };
      h.setProfile(me);
      return h;
    }

    testWidgets('A7-1 / U3-04: «παλμοί ύπνου, 9 νύχτες» (όχι «14 νύχτες»)· ζώνη 106–129', (t) async {
      final h = nine();
      expect(h.restHrForZone(when), 58);
      expect(h.restHrNights(when), 9);
      // ηλικία 41: μέγιστοι round(208 − 28,7) = 179· 58 + 0,40 × 121 = 106,4 → 106· 58 + 0,59 × 121 = 129,39 → 129
      final z = h.zoneOn(when)!;
      expect((z.lo, z.hi, z.rest, z.max), (106, 129, 58, 179));
      await _pump(t, Scaffold(body: ZoneSheet(health: h, now: when)), size: const Size(400, 3000));
      final rest = t.widgetList<InfoRow>(find.byType(InfoRow)).firstWhere((r) => r.label == 'Παλμοί ηρεμίας').value;
      expect(rest, '58 · παλμοί ύπνου, 9 νύχτες');
      expect(find.textContaining('τύπος Karvonen'), findsOneWidget);
    });

    test('A7-1: 20 νύχτες → μετρά 14· 5 νύχτες → καμία', () {
      final many = HealthStore()
        ..history = {for (var i = 1; i <= 20; i++) dateKey(DateTime(day.year, day.month, day.day - i)): {K.sleepHr: 60.0}};
      expect(many.restHrNights(when), 14);
      final few = HealthStore()
        ..history = {for (var i = 1; i <= 5; i++) dateKey(DateTime(day.year, day.month, day.day - i)): {K.sleepHr: 60.0}};
      expect(few.restHrNights(when), 0);
      expect(few.restHrForZone(when), isNull);
    });

    test('A7-2: μέγιστοι από τεστ (185) χωρίς παλμούς ηρεμίας: όχι «από την ηλικία»', () {
      final z = computeZone(age: 41, restHr: null, s: const ZoneSettings(maxHr: 185))!;
      // 64–76% των 185: 118,4 → 118, 140,6 → 141
      expect((z.lo, z.hi, z.maxMeasured, z.rest), (118, 141, true, null));
      final text = zoneProvisionalText(z);
      expect(text, isNot(contains('ηλικία')));
      expect(text, contains('μέγιστους παλμούς σου'));
      expect(text, contains('παλμούς ηρεμίας σου ξύπνιος'));
      final byAge = computeZone(age: 41, restHr: null, s: const ZoneSettings())!;
      expect(zoneProvisionalText(byAge), startsWith('Προσωρινά από την ηλικία'));
    });

    testWidgets('A7-2: η κάρτα της ζώνης με μέγιστους από τεστ', (t) async {
      final h = HealthStore();
      h.setProfile(me);
      h.setZoneSettings(const ZoneSettings(maxHr: 185));
      final tr = TrainingStore(io: MemoryTrainingIO(), clock: () => when)..ready = true;
      await _pump(t, Scaffold(body: SingleChildScrollView(child: ZoneCard(health: h, training: tr, now: when))));
      final text = t.widget<Text>(find.byKey(const ValueKey('zone-provisional'))).data!;
      expect(text, isNot(contains('από την ηλικία')));
    });

    testWidgets('A7-3: ζώνη που όρισες εσύ: όχι ο τύπος, αλλά «ο υπολογισμός θα έδινε 106–129»', (t) async {
      final h = nine();
      h.setZoneSettings(const ZoneSettings(lo: 110, hi: 132));
      await _pump(t, Scaffold(body: ZoneSheet(health: h, now: when)), size: const Size(400, 3000));
      final how = t.widget<Text>(find.byKey(const ValueKey('zone-sheet-how'))).data!;
      expect(how, 'Τη ζώνη την όρισες εσύ. Ο υπολογισμός θα έδινε 106–129.');
      expect(find.textContaining('Karvonen'), findsNothing);
      expect(t.widgetList<InfoRow>(find.byType(InfoRow)).where((r) => r.label == 'Μέτρια ένταση'), isEmpty);
    });

    test('A7-4: κάτω από τη ζώνη, όχι τα πρώτα 5 λεπτά (όπως το ρολόι)', () {
      expect(zoneLowText, 'Μία δόνηση όταν μείνεις κάτω 1 λεπτό. Ξανά μετά από 5 λεπτά. Όχι τα πρώτα 5 λεπτά.');
      expect(zoneWarmupSec, 300);
    });

    test('A7-5: η ερώτηση μετρά απαντήσεις, όχι «πρώτα περπατήματα»', () {
      expect(talkLeftText(0, answered: false), 'Η ερώτηση έρχεται ώσπου να απαντήσεις 3 φορές· απομένουν 3.');
      expect(talkLeftText(2, answered: false), 'Η ερώτηση έρχεται ώσπου να απαντήσεις 3 φορές· απομένει 1.');
      expect(talkLeftText(1, answered: true), 'Η ερώτηση έρχεται ώσπου να απαντήσεις 3 φορές.');
      for (final x in [talkLeftText(0, answered: false), talkLeftText(3, answered: true)]) {
        expect(x, isNot(contains('πρώτα περπατήματα')));
      }
    });
  });

  // ---------------------------------------------------------------- R8-U3-01
  group('R8-U3-01: 1ο σετ «πρώτης φοράς» με ✓ στο ρολόι: η ερώτηση έρχεται στο κινητό', () {
    testWidgets('✓ του ρολογιού → «Πρώτο σετ: πόσες ακόμα;» → «0» → τα επόμενα σετ 7,8 kg', (tester) async {
      final at = DateTime(2026, 11, 13, 17, 30);
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final store = sampleTraining(at, history: false);
      final s = store.start(store.program!.workout('A')!);
      final link = WearLink()..attachForTest(store);
      await _pump(tester, SessionPage(training: store));
      link.apply(store, WatchCmd('tick', {'i': 0, 's': 0, 'sid': s.id, 'ex': 'db_press'}));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(s.items.first.log.first.done, isTrue);
      expect(find.text('Πρώτο σετ: πόσες ακόμα θα έβγαζες;'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rir-0')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rir-ok')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // «0» (λιγότερη από 2 ρεζέρβα): ένα σκαλί πιο ελαφριά, 9,3 → 7,8 kg (λαβή 1,8 + 2 × 3)
      expect(s.items.first.log[1].load, 7.8);
      expect(s.items.first.log[2].load, 7.8);
      expect(find.text('Τα επόμενα σετ: 7,8 kg.'), findsOneWidget);
      expect(store.firstAsk, isNull);
      // απαντήθηκε στο κινητό: το ρολόι δεν ρωτά πια («f» φεύγει)
      expect(s.items.first.firstAnswer, 0);
      expect(((watchSession(store, (x) => x)['items'] as List).first as Map).containsKey('f'), isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('η απάντηση έρχεται από το ρολόι («rir1») με το φύλλο ανοιχτό στο κινητό: κλείνει, ισχύει του ρολογιού', (tester) async {
      final at = DateTime(2026, 11, 13, 17, 30);
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final store = sampleTraining(at, history: false);
      final s = store.start(store.program!.workout('A')!);
      final link = WearLink()..attachForTest(store);
      await _pump(tester, SessionPage(training: store));
      link.apply(store, WatchCmd('tick', {'i': 0, 's': 0, 'sid': s.id, 'ex': 'db_press'}));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Πρώτο σετ: πόσες ακόμα θα έβγαζες;'), findsOneWidget);
      link.apply(store, WatchCmd('rir1', {'op': 'rir1', 'i': 0, 'v': 0, 'sid': s.id, 'ex': 'db_press'}));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Πρώτο σετ: πόσες ακόμα θα έβγαζες;'), findsNothing);
      expect(find.byType(SessionPage), findsOneWidget, reason: 'κλείνει μόνο το φύλλο, όχι η προπόνηση');
      expect(s.items.first.firstAnswer, 0);
      expect(s.items.first.log[1].load, 7.8);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    group('πρωτόκολλο με το ρολόι: «f» στην προπόνηση, εντολή «rir1»', () {
      final at = DateTime(2026, 11, 13, 17, 30);
      Map<dynamic, dynamic> item(TrainingStore t, int i) => (watchSession(t, (x) => x)['items'] as List)[i] as Map;
      WatchCmd rir1(Session s, int i, int v, {String? ex}) =>
          WatchCmd('rir1', {'op': 'rir1', 'i': i, 'v': v, 'sid': s.id, if (ex != null) 'ex': ex});

      test('«f»: 1 όσο εκκρεμεί η ερώτηση (πρώτη φορά, με βάρος, > 1 σετ), όχι στο σώμα· «rir1» 0 → 7,8 kg και «f» φεύγει', () {
        final t = sampleTraining(at, history: false);
        final s = t.start(t.program!.workout('A')!);
        final link = WearLink()..attachForTest(t);
        expect(item(t, 0)['f'], 1);
        expect(item(t, 5).containsKey('f'), isFalse, reason: 'ανάποδοι κοιλιακοί: σώμα, καμία βαθμονόμηση');
        link.apply(t, WatchCmd('tick', {'op': 'tick', 'i': 0, 's': 0, 'sid': s.id, 'ex': 'db_press'}));
        expect(item(t, 0)['f'], 1, reason: 'μετά το ✓, ως την απάντηση');
        final e = s.items.first;
        // ίδιο με την απάντηση στο κινητό: «0» → ένα σκαλί κάτω (9,3 → 7,8 kg) για τα σετ 2–3
        final want = calibrate(t.program!.workout('A')!.items.first, 9.3, e.log.first.reps, 0);
        expect(want, 7.8);
        link.apply(t, rir1(s, 0, 0, ex: 'db_press'));
        expect([for (final x in e.log) x.load], [9.3, 7.8, 7.8]);
        expect(e.firstAnswer, 0);
        expect(item(t, 0).containsKey('f'), isFalse);
        expect((item(t, 0)['sets'] as List)[1]['label'], '7,8 kg');
        // δεύτερη απάντηση (ξανασταλμένη, ή από το κινητό): καμία αλλαγή
        link.apply(t, rir1(s, 0, 4, ex: 'db_press'));
        expect([for (final x in e.log) x.load], [9.3, 7.8, 7.8]);
        expect(e.firstAnswer, 0);
        expect(t.answerFirst(e, 1).applied, isFalse);
        expect([for (final x in e.log) x.load], [9.3, 7.8, 7.8]);
      });

      test('«rir1» −1 («Δεν ξέρω»): καμία αλλαγή, αλλά απαντήθηκε· μετά τίποτα δεν αλλάζει', () {
        final t = sampleTraining(at, history: false);
        final s = t.start(t.program!.workout('A')!);
        final link = WearLink()..attachForTest(t);
        final e = s.items[3]; // κάμψεις σε κλίση: πρώτη φορά, 5,3 kg, 3 σετ
        final before = [for (final x in e.log) x.load];
        link.apply(t, WatchCmd('tick', {'op': 'tick', 'i': 3, 's': 0, 'sid': s.id}));
        link.apply(t, rir1(s, 3, -1));
        expect([for (final x in e.log) x.load], before);
        expect(e.firstAnswer, -1);
        expect(item(t, 3).containsKey('f'), isFalse);
        link.apply(t, rir1(s, 3, 0));
        expect([for (final x in e.log) x.load], before);
        expect(e.firstAnswer, -1);
      });

      test('δεν εκκρεμεί (με ιστορικό) ή άλλη άσκηση στη θέση: «rir1» αγνοείται', () {
        final old = sampleTraining(at);
        final s = old.start(old.program!.workout('A')!);
        expect(item(old, 0).containsKey('f'), isFalse);
        final link = WearLink()..attachForTest(old);
        final before = [for (final x in s.items.first.log) x.load];
        link.apply(old, rir1(s, 0, 0));
        expect([for (final x in s.items.first.log) x.load], before);
        expect(s.items.first.firstAnswer, isNull);
        final t = sampleTraining(at, history: false);
        final s2 = t.start(t.program!.workout('A')!);
        (WearLink()..attachForTest(t)).apply(t, rir1(s2, 0, 0, ex: 'db_row'));
        expect(s2.items.first.firstAnswer, isNull);
        expect(item(t, 0)['f'], 1);
      });

      test('«fa» στο αρχείο: γράφεται και διαβάζεται· παλιό αρχείο χωρίς αυτό: όπως πριν', () {
        final e = done('db_press', 9.3, [8], sets: 3)..firstAnswer = -1;
        expect(ExLog.fromJson(jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>).firstAnswer, -1);
        final old = ExLog.fromJson({'ex': 'db_press', 'sets': 3, 'lo': 8, 'hi': 12, 'log': []});
        expect(old.firstAnswer, isNull);
        expect(old.toJson().containsKey('fa'), isFalse);
      });
    });

    test('μόνο για 1ο σετ, με βάρος, πρώτη φορά· όχι για ✓ που ξαναστάλθηκε αργότερα', () {
      final at = DateTime(2026, 11, 13, 17, 30);
      final store = sampleTraining(at, history: false);
      final s = store.start(store.program!.workout('A')!);
      final link = WearLink()..attachForTest(store);
      link.apply(store, WatchCmd('tick', {'i': 1, 's': 0, 'sid': s.id, 'late': true}));
      expect(store.firstAsk, isNull);
      link.apply(store, WatchCmd('tick', {'i': 2, 's': 1, 'sid': s.id}));
      expect(store.firstAsk, isNull, reason: 'όχι το 2ο σετ');
      link.apply(store, WatchCmd('tick', {'i': 5, 's': 0, 'sid': s.id}));
      expect(store.firstAsk, isNull, reason: 'άσκηση σώματος: καμία βαθμονόμηση');
      link.apply(store, WatchCmd('tick', {'i': 3, 's': 0, 'sid': s.id}));
      expect(store.firstAsk, same(s.items[3]));
      // με ιστορικό (όχι πρώτη φορά): καμία ερώτηση
      final old = sampleTraining(at);
      final s2 = old.start(old.program!.workout('A')!);
      (WearLink()..attachForTest(old)).apply(old, WatchCmd('tick', {'i': 0, 's': 0, 'sid': s2.id}));
      expect(old.firstAsk, isNull);
    });
  });

  // ---------------------------------------------------------------- R8-U3-02
  group('R8-U3-02: χωρίς όριο, «σφίξε το λουράκι» μόνο για παλμούς ΑΥΤΗΣ της προπόνησης', () {
    testWidgets('παλμοί πριν από την αρχή: τίποτα· παλμοί μέσα της που σταμάτησαν: το πλαίσιο', (tester) async {
      final started = DateTime.now().subtract(const Duration(minutes: 10));
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final store = sampleTraining(started)..setHrLimit(null);
      final s = store.start(store.program!.workout('A')!);
      WearLink.main.ready.value = true;
      WearLink.main.hr.value = (104, s.start.subtract(const Duration(hours: 2)));
      addTearDown(() {
        WearLink.main.hr.value = null;
        WearLink.main.ready.value = false;
      });
      await _pump(tester, SessionPage(training: store));
      expect(find.byKey(const ValueKey('hr-stale')), findsNothing);
      WearLink.main.hr.value = (120, s.start.add(const Duration(minutes: 1)));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('hr-stale')), findsOneWidget);
      expect(find.textContaining('Σφίξε λίγο το λουράκι'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  test('R8-U3-Β1: «λουράκι» και στα κείμενα των παλμών', () {
    expect(const HrStale().hint, contains('Σφίξε λίγο το λουράκι'));
    expect(hrLimitMoreText, contains('χαλαρό λουράκι'));
    expect(hrLimitMoreText.contains('λουρί'), isFalse);
  });

  // ---------------------------------------------------------------- R8-U3-05
  testWidgets('R8-U3-05: «Σήμερα: …» από το ⋮ ισχύει μόνο εκείνη τη μέρα, με «Πίσω στο πρόγραμμα»', (tester) async {
    await tester.runAsync(() => ExLibrary.load(inline: true));
    final ids = {for (final e in ExLibrary.loaded!.list) e.id};
    final fri = DateTime(2026, 11, 20, 10), sat = DateTime(2026, 11, 21, 10);
    final t = TrainingStore(io: MemoryTrainingIO(), clock: () => fri)..ready = true;
    t.saveProgram(parseProgram(_v2, ids).program!, author: 'claude');
    Finder inToday(String text) => find.descendant(of: find.byKey(const ValueKey('train-today')), matching: find.text(text));
    await _pump(tester, Scaffold(body: TrainingPage(training: t, now: fri)), size: const Size(400, 2400));
    expect(find.byKey(const ValueKey('train-chosen')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('train-today-more')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('train-pick-LA')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(inToday('Κάτω μέρος Α'), findsOneWidget);
    expect(find.byKey(const ValueKey('train-chosen')), findsOneWidget);
    // την επόμενη μέρα (η εφαρμογή έμεινε ανοιχτή): η προπόνηση του Σαββάτου, όχι η χθεσινή επιλογή
    // ίδιο δέντρο (ίδια κατάσταση της σελίδας), μόνο άλλη μέρα
    await _pump(tester, Scaffold(body: TrainingPage(training: t, now: sat)), size: const Size(400, 2400));
    expect(inToday('Κάτω μέρος Β'), findsOneWidget);
    expect(inToday('Κάτω μέρος Α'), findsNothing);
    expect(find.byKey(const ValueKey('train-chosen')), findsNothing);
    // «Πίσω στο πρόγραμμα» την ίδια μέρα
    await tester.tap(find.byKey(const ValueKey('train-today-more')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('train-pick-LA')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(inToday('Κάτω μέρος Α'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('train-chosen-reset')));
    await tester.pump();
    expect(inToday('Κάτω μέρος Β'), findsOneWidget);
    expect(find.byKey(const ValueKey('train-chosen')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  // ---------------------------------------------------------------- R8-U3-07
  testWidgets('R8-U3-07: 360 dp, γράμματα 1,3×: η κουκκίδα του λάστιχου στην 1η γραμμή του ονόματος', (tester) async {
    final at = DateTime(2026, 11, 13, 17, 30);
    await tester.runAsync(() => ExLibrary.load(inline: true));
    final store = sampleTraining(at);
    store.start(store.program!.workout('A')!);
    await _pump(tester, SessionPage(training: store), size: const Size(360, 1600), scale: 1.3);
    store.focus = 4; // λάστιχο (pushdown)
    await tester.pump();
    final cur = find.byKey(const ValueKey('sess-current-0'));
    final name = find.descendant(of: cur, matching: find.textContaining('λάστιχο ·'));
    expect(name, findsOneWidget);
    final tr = tester.getRect(name);
    final dots = find.descendant(of: cur, matching: find.byType(BandDots));
    Rect? dot;
    for (var i = 0; i < dots.evaluate().length; i++) {
      final r = tester.getRect(dots.at(i));
      if ((r.right - tr.left).abs() < 1.5) dot = r;
    }
    expect(dot, isNotNull, reason: 'η κουκκίδα δίπλα στο όνομα');
    expect(dot!.top - tr.top, inInclusiveRange(0, 4), reason: 'στην 1η γραμμή (ύψος ονόματος ${tr.height})');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  // ---------------------------------------------------------------- R8-A8-2
  test('R8-A8-2: ✓ που το κινητό είχε δει και έσβησε δεν ξαναμπαίνει από το ρολόι· ✓ μόνο του ρολογιού μπαίνει', () {
    final t = sampleTraining(now);
    final s = t.start(t.program!.workout('A')!);
    final press = s.items.first;
    t.tick(press, 0);
    t.tick(press, 1);
    t.untick(press, 1);
    t.finish();
    final items = [for (final e in s.items) jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>];
    final log = (items.first['log'] as List).cast<Map<String, dynamic>>();
    final at = now.millisecondsSinceEpoch;
    log[1] = {...log[1], 'd': 1, 't': at, 'c': 1}; // το κινητό το είχε δει: το έσβησε ο χρήστης
    log[2] = {...log[2], 'd': 1, 't': at + 20000}; // μόνο στο ρολόι
    t.importWatch({'v': 1, 'kind': 'hr', 'sid': s.id, 'hrT0': s.start.millisecondsSinceEpoch, 'hr': <Object>[], 'items': items});
    final f = t.sessions.firstWhere((x) => x.id == s.id);
    expect([for (final x in f.items.first.log) x.done], [true, false, true]);
    // ρολόι παλιότερης έκδοσης (χωρίς «c»): όπως πριν, το ✓ μπαίνει
    final t2 = sampleTraining(now);
    final s2 = t2.start(t2.program!.workout('A')!);
    t2.finish();
    final items2 = [for (final e in s2.items) jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>];
    final log2 = (items2.first['log'] as List).cast<Map<String, dynamic>>();
    log2[0] = {...log2[0], 'd': 1, 't': at};
    t2.importWatch({'v': 1, 'kind': 'hr', 'sid': s2.id, 'hrT0': s2.start.millisecondsSinceEpoch, 'hr': <Object>[], 'items': items2});
    expect(t2.sessions.firstWhere((x) => x.id == s2.id).items.first.log.first.done, isTrue);
  });

  // ---------------------------------------------------------------- R8-A8-3
  group('R8-A8-3: «Συνέχεια» στην ξεχασμένη προπόνηση την κάνει ξανά ενεργή', () {
    test('4 ώρες χωρίς ✓ → «Συνέχεια»: παλμοί και ✓ του ρολογιού γράφονται· στο ρολόι πάει το «res»', () {
      var at = now;
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => at)..replaceAll(sampleTraining(now).toJson());
      t.ready = true;
      final s = t.start(t.program!.workout('A')!);
      at = now.add(const Duration(hours: 4));
      expect(t.isStale(s), isTrue);
      t.addHr(120, at, sid: s.id);
      expect(s.hr, isEmpty, reason: 'πριν τη «Συνέχεια»: όχι δικοί της');
      t.resume(s);
      expect(s.resumedAt, at.millisecondsSinceEpoch);
      expect(t.isStale(s), isFalse);
      expect(t.belongs(s, at.millisecondsSinceEpoch), isTrue);
      t.addHr(120, at, sid: s.id);
      expect(s.hr, [
        [4 * 3600, 120],
      ]);
      final link = WearLink()..attachForTest(t);
      link.apply(t, WatchCmd('tick', {'i': 0, 's': 0, 'sid': s.id, 'ex': s.items.first.ex}));
      expect(s.items.first.log.first.done, isTrue);
      expect(watchSession(t, (x) => x)['res'], at.millisecondsSinceEpoch);
      // «Τελευταίο σετ» / «Τέλος (στις …)»: το ✓, όχι η «Συνέχεια»
      expect(s.lastTick, at);
    });

    test('«res» στο αρχείο: γράφεται και διαβάζεται· παλιό αρχείο χωρίς αυτό: όπως πριν', () {
      final s = Session(id: 's1', workout: 'A', name: 'Α', programId: 'p', start: now)..resumedAt = now.add(const Duration(hours: 4)).millisecondsSinceEpoch;
      final back = Session.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.resumedAt, s.resumedAt);
      expect(back.lastActivity, now.add(const Duration(hours: 4)));
      expect(back.lastTick, now);
      final old = Session.fromJson({'id': 's2', 'start': now.millisecondsSinceEpoch});
      expect(old.resumedAt, isNull);
      expect(old.toJson().containsKey('res'), isFalse);
      expect(old.lastActivity, now);
    });

    testWidgets('το κουμπί «Συνέχεια» της κάρτας', (tester) async {
      var at = now;
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => at)..replaceAll(sampleTraining(now).toJson());
      t.ready = true;
      final s = t.start(t.program!.workout('A')!);
      at = now.add(const Duration(hours: 4));
      var opened = false;
      await _pump(
          tester,
          Scaffold(
              body: ForgottenWorkout(training: t, session: s, now: at, watchReady: true, onResume: () => opened = true)));
      await tester.tap(find.byKey(const ValueKey('train-forgotten-resume')));
      await tester.pump();
      expect(opened, isTrue);
      expect(t.isStale(s), isFalse);
    });
  });

  // ---------------------------------------------------------------- R8-A8-5
  group('R8-A8-5: αλλαγή ζώνης/προγράμματος φτάνει στο ρολόι «urgent»', () {
    const ch = MethodChannel('test/r8-wear-plan');
    test('νέα ζώνη → urgent· ίδιο περιεχόμενο ξανά (επιστροφή στην εφαρμογή) → όχι', () async {
      final urgent = <bool>[];
      final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      m.setMockMethodCallHandler(ch, (call) async {
        switch (call.method) {
          case 'status':
            return {'nodes': 1, 'app': 1};
          case 'takeResults':
            return <Object>[];
          case 'putPlan':
            urgent.add((call.arguments as Map)['urgent'] == true);
            return true;
        }
        return true;
      });
      const events = MethodChannel('test/r8-wear-plan-events');
      m.setMockMethodCallHandler(events, (call) async => null);
      addTearDown(() {
        m.setMockMethodCallHandler(ch, null);
        m.setMockMethodCallHandler(events, null);
      });
      final t = sampleTraining(now);
      final link = WearLink(channel: ch, events: const EventChannel('test/r8-wear-plan-events'));
      link.start(t);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(urgent, isNotEmpty);
      expect(urgent.first, isTrue, reason: 'το πρώτο του ανοίγματος');
      t.setZone(const WalkZone(110, 130, down: true));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(urgent.last, isTrue, reason: 'πριν: όχι (μόνο το όριο γιατρού ήταν urgent)');
      final before = urgent.length;
      await link.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(urgent.length, greaterThan(before));
      expect(urgent.last, isFalse, reason: 'ίδιο περιεχόμενο: χωρίς βιασύνη');
      link.dispose();
    });
  });
}
