// Γύρος 10, g3 (προπόνηση, πλευρά κινητού): δοκιμές για τα R10-B4-1 (= B7-4), R10-B4-2 (= B7-2), R10-B4-3, R10-B4-4,
// R10-B4-5 και τη σημείωση του B5 (η «Αλλαγή άσκησης» κρατά την απάντηση «Πρώτο σετ»). Οι αναμενόμενες τιμές βγαίνουν από
// τους κανόνες όπως γράφονται (σκαλιά του εξοπλισμού, ρεζέρβα ≥ 2 και όσες ζητά το πρόγραμμα, ±1′ μετά το τέλος για τους
// παλμούς), όχι από την υλοποίηση. Όλες οι τιμές είναι επινοημένες.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/exercise/ex_data.dart';
import 'package:ygeia_forma/exercise/ex_player.dart' show ExClock;
import 'package:ygeia_forma/pages/training/hr_widgets.dart' show HrCard;
import 'package:ygeia_forma/pages/training/session_page.dart';
import 'package:ygeia_forma/pages/training/today_training_card.dart';
import 'package:ygeia_forma/pages/training/training_common.dart' show exName;
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/training/program.dart';
import 'package:ygeia_forma/training/progression.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/training_store.dart';
import 'package:ygeia_forma/training/wear_link.dart' show watchSession;

import 'training_sample.dart';

final now = DateTime(2026, 11, 20, 18); // Παρασκευή
DateTime ago(int days) => DateTime(2026, 11, 20 - days, 18);

PlanItem it(String ex, {int sets = 3, int lo = 8, int hi = 12, int rir = 3}) => PlanItem(ex: ex, sets: sets, lo: lo, hi: hi, rir: rir, rest: 90);

/// Μία άσκηση που έγινε με ένα φορτίο.
ExLog done(String ex, double? load, List<int> reps, {int? ra, int lo = 8, int hi = 12}) => ExLog(
      ex: ex,
      sets: reps.length,
      lo: lo,
      hi: hi,
      rir: 3,
      rest: 90,
      rirAnswer: ra,
      log: [for (final r in reps) SetLog(load: load, reps: r, done: true)],
    );

/// Σετ με διαφορετικά φορτία: [(φορτίο, επαναλήψεις)]· [planned] = τα σετ του προγράμματος (τα υπόλοιπα: «+ Σετ»).
ExLog mixed(String ex, List<(double, int)> sets, {required int planned, int? ra}) => ExLog(
      ex: ex,
      sets: planned,
      lo: 8,
      hi: 12,
      rir: 3,
      rest: 90,
      rirAnswer: ra,
      log: [for (final (l, r) in sets) SetLog(load: l, reps: r, done: true)],
    );

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

const _lastSetQuestion = 'Τελευταίο σετ: πόσες ακόμα θα έβγαζες;';

void main() {
  // Το κινούμενο σχέδιο των ασκήσεων σταματημένο: οι οθόνες «ησυχάζουν» (pumpAndSettle).
  setUp(() => ExClock.frozen = true);
  tearDown(() => ExClock.frozen = false);

  // ---------------------------------------------------------------- R10-B4-1 / R10-B7-4
  group('R10-B4-1 / B7-4: γραμμή του «+ Σετ» που δεν έγινε', () {
    test('«− Σετ» βγάζει μόνο την τελευταία γραμμή του «+ Σετ» χωρίς ✓· ποτέ σετ του προγράμματος· το ρολόι παίρνει 3 σετ', () {
      final t = sampleTraining(now);
      final s = t.start(t.program!.workout('A')!);
      final e = s.items.first;
      expect(e.canRemoveRow, isFalse);
      expect(t.removeSet(e), isFalse);
      expect(e.log.length, 3);
      t.addSet(e);
      expect(e.canRemoveRow, isTrue);
      t.tick(e, 3);
      expect(t.removeSet(e), isFalse, reason: 'σετ με ✓ δεν βγαίνει');
      expect(e.log.length, 4);
      t.untick(e, 3);
      expect(t.removeSet(e), isTrue);
      expect(e.log.length, 3);
      expect(t.removeSet(e), isFalse, reason: 'ποτέ σετ του προγράμματος');
      final items = watchSession(t, (x) => x)['items'] as List;
      expect(((items.first as Map)['sets'] as List).length, 3);
    });

    testWidgets('✓ 1–3, «− Σετ» στην 4η γραμμή: η άσκηση τελειώνει, «Τελευταίο σετ», μετά η επόμενη άσκηση', (tester) async {
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final store = sampleTraining(now);
      final s = store.start(store.program!.workout('A')!);
      final e = s.items.first;
      await _pump(tester, SessionPage(training: store));
      expect(find.byKey(const ValueKey('sess-remove-set')), findsNothing, reason: 'μόνο τα σετ του προγράμματος: τίποτα να βγει');
      store.addSet(e);
      await tester.pump();
      expect(e.log.length, 4);
      for (var i = 0; i < 3; i++) {
        await _tapKey(tester, 'sess-tick-$i');
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text(_lastSetQuestion), findsNothing);
      expect(e.rowsDone, isFalse);
      await _tapKey(tester, 'sess-remove-set');
      await tester.pump(const Duration(seconds: 1));
      expect(e.log.length, 3);
      expect(e.rowsDone, isTrue);
      expect(find.text(_lastSetQuestion), findsOneWidget);
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

    testWidgets('«Τέλος» χωρίς να βγει η γραμμή: η ερώτηση «Τελευταίο σετ» γίνεται εκεί, με το όνομα της άσκησης', (tester) async {
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final store = sampleTraining(now);
      final s = store.start(store.program!.workout('A')!);
      final e = s.items.first;
      store.addSet(e);
      for (var i = 0; i < 3; i++) {
        store.tick(e, i);
      }
      expect((e.complete, e.rowsDone, e.rirAnswer), (true, false, null));
      await _pump(tester, SessionPage(training: store));
      await _tapKey(tester, 'sess-finish');
      await tester.pumpAndSettle();
      expect(find.text('Τελείωσες νωρίτερα;'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sess-finish-ok')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(_lastSetQuestion), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('rir-about'))).data, exName('db_press'));
      await tester.tap(find.byKey(const ValueKey('rir-3')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rir-ok')));
      await tester.pumpAndSettle();
      expect(e.rirAnswer, 3);
      expect(find.text('Την επόμενη φορά'), findsOneWidget, reason: 'μετά την απάντηση, η σύνοψη');
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  // ---------------------------------------------------------------- R10-B4-2 / R10-B7-2
  group('R10-B4-2 / B7-2: «άφησες» μετά από σετ παραπάνω πιο ελαφρύ', () {
    final press = it('db_press');

    test('9,3 × 12, 12, 12 + 7,8 × 12, «3»: ίδια, και ο λόγος λέει γιατί (όχι «δεν ξέρουμε… πες μετά το τελευταίο σετ»)', () {
      final tg = nextTarget(press, [(ago(3), mixed('db_press', [(9.3, 12), (9.3, 12), (9.3, 12), (7.8, 12)], planned: 3, ra: 3))], now);
      expect((tg.change, tg.load), (Change.hold, 9.3));
      expect(tg.reps, [12, 12, 12]);
      expect(tg.reason, isNot(contains('δεν ξέρουμε')));
      expect(
          tg.reason,
          'Έφτασες στις 12, αλλά το «άφησες 3» ήταν για το σετ παραπάνω, που έγινε πιο ελαφρύ: ίδια. '
          'Για να μετρά η απάντηση, κάνε και το σετ παραπάνω με το ίδιο φορτίο, ή μην το κάνεις.');
    });

    test('σετ παραπάνω με το ίδιο βάρος, «3»: ανεβαίνει σε 10,3 kg από 8', () {
      final tg = nextTarget(press, [(ago(3), mixed('db_press', [(9.3, 12), (9.3, 12), (9.3, 12), (9.3, 12)], planned: 3, ra: 3))], now);
      expect((tg.change, tg.load), (Change.up, 10.3));
      expect(tg.reps, [8, 8, 8]);
    });

    test('σετ παραπάνω πιο ελαφρύ με «1»: ο κανόνας ασφαλείας μένει (ίδια, «σου μένουν 3»)', () {
      final tg = nextTarget(press, [(ago(3), mixed('db_press', [(9.3, 12), (9.3, 12), (9.3, 12), (7.8, 12)], planned: 3, ra: 1))], now);
      expect((tg.change, tg.load), (Change.hold, 9.3));
      expect(tg.reason, startsWith('Άφησες 1. Ίδια κιλά, και σταμάτα το σετ όταν σου μένουν 3'));
    });

    test('μπάρα (RDL) 20 kg × 10, 10, 10 + 15 × 12, «3»: ίδια, με την αιτία (όχι «Δεν ξέρουμε πόσες άφησες»)', () {
      final tg = nextTarget(it('rdl'), [(ago(3), mixed('rdl', [(20, 10), (20, 10), (20, 10), (15, 12)], planned: 3, ra: 3))], now);
      expect((tg.change, tg.load), (Change.hold, 20.0));
      expect(tg.reps, [10, 10, 10]);
      expect(
          tg.reason,
          'Το «άφησες 3» ήταν για το σετ παραπάνω, που έγινε πιο ελαφρύ. Σε αυτή την άσκηση δεν ανεβαίνει τίποτα χωρίς απάντηση: ίδια. '
          'Για να μετρά η απάντηση, κάνε και το σετ παραπάνω με το ίδιο φορτίο, ή μην το κάνεις.');
    });

    test('χωρίς καμία απάντηση: όπως πριν', () {
      final tg = nextTarget(press, [(ago(3), mixed('db_press', [(9.3, 12), (9.3, 12), (9.3, 12)], planned: 3))], now);
      expect((tg.change, tg.load), (Change.hold, 9.3));
      expect(tg.reason, 'Έφτασες στις 12, αλλά δεν ξέρουμε πόσες άφησες: ίδια, και πες μετά το τελευταίο σετ.');
    });
  });

  // ---------------------------------------------------------------- R10-B4-3
  group('R10-B4-3: περπάτημα που διάλεξες για σήμερα σε μέρα βαρών', () {
    final fri = DateTime(2026, 11, 13, 17, 30); // «A» (βάρη) στο δείγμα
    TrainingStore withWalk() {
      final t = sampleTraining(fri);
      final walk = Session(
        id: 'w-r10',
        workout: 'walk',
        name: 'Περπάτημα',
        programId: 'p-claude-1',
        start: DateTime(2026, 11, 13, 8),
        end: DateTime(2026, 11, 13, 8, 30),
        cardioMinutes: 30,
        cardioSec: 1800,
        source: 'watch',
        activity: 'walk',
      );
      final j = t.toJson();
      j['sessions'] = [...(j['sessions'] as List), walk.toJson()];
      t.replaceAll(j);
      t.ready = true;
      return t;
    }

    test('με την επιλογή: «έγινε» σήμερα είναι το περπάτημα· χωρίς επιλογή: όπως πριν («Έγινε σήμερα και»)', () {
      final t = withWalk();
      expect(TodayTrainingCard.doneToday(t, fri), isNull);
      expect(TodayTrainingCard.otherToday(t, fri)?.id, 'w-r10');
      t.choose('walk', fri);
      expect(TodayTrainingCard.doneToday(t, fri)?.id, 'w-r10');
      expect(TodayTrainingCard.otherToday(t, fri), isNull);
    });

    testWidgets('η κάρτα «Άσκηση σήμερα»: «έγινε» με «Δες τη σύνοψη», όχι «πάτα «Περπάτημα»» ούτε «Έγινε σήμερα και»', (tester) async {
      final t = withWalk()..choose('walk', fri);
      await _pump(tester, Scaffold(body: SingleChildScrollView(child: TodayTrainingCard(training: t, now: fri))));
      expect(find.byKey(const ValueKey('today-training-summary')), findsOneWidget);
      expect(find.byKey(const ValueKey('today-train-walk-hint')), findsNothing);
      expect(find.byKey(const ValueKey('today-training-other')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  // ---------------------------------------------------------------- R10-B4-4
  testWidgets('R10-B4-4: σύνοψη ξεχασμένης προπόνησης πριν από την «Αποθήκευση»: μέσος 115 (όχι 85), ο ίδιος που γράφεται',
      (tester) async {
    await tester.runAsync(() => ExLibrary.load(inline: true));
    final t0 = DateTime(2026, 11, 16, 18);
    var at = t0;
    final store = TrainingStore(io: MemoryTrainingIO(), clock: () => at)..replaceAll(sampleTraining(t0).toJson());
    store.ready = true;
    final s = store.start(store.program!.workout('A')!);
    // Παλμοί 115 ως το 61′ (ανά 10″, ✓ στο 60′), μετά 75 (καθισμένος) ως το 240′: μέσος όλων 85, ως το τέλος + 1′ 115.
    for (var k = 0; k < 1440; k++) {
      at = t0.add(Duration(seconds: 10 * k));
      if (k == 360) store.tick(s.items.first, 0);
      store.addHr(k <= 366 ? 115 : 75, at, sid: s.id);
    }
    at = t0.add(const Duration(minutes: 241));
    expect(store.isStale(s), isTrue);
    await _pump(tester, SummaryPage(training: store, session: s, live: true), size: const Size(400, 2400));
    await tester.pumpAndSettle();
    final card = find.byType(HrCard);
    expect(card, findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('115')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('~115')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('85')), findsNothing);
    // «Αποθήκευση»: γράφεται ακριβώς ό,τι έδειξε η σύνοψη.
    store.finish();
    expect(s.end, t0.add(const Duration(minutes: 60)));
    expect((s.hrAvg, s.hrMax), (115, 115));
    expect(s.hr.last[0], lessThanOrEqualTo(3660));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  // ---------------------------------------------------------------- R10-B4-5
  group('R10-B4-5: «σταμάτα το σετ όταν σου μένουν …» όσες ζητά το πρόγραμμα, όχι πάντα 2', () {
    final heavy = [(ago(3), done('db_press', 9.3, [8, 7, 6], ra: 0))];

    test('πιεστικό «άφησε 3», 9,3 × 8, 7, 6 με «0»: 7,8 kg από 8 και «σου μένουν 3»· «άφησε 2»: «2»· «άφησε 1»: ποτέ κάτω από 2', () {
      final three = nextTarget(it('db_press', rir: 3), heavy, now);
      expect((three.change, three.load), (Change.down, 7.8));
      expect(three.reps, [8, 8, 8]);
      expect(three.reason, contains('σταμάτα το σετ όταν σου μένουν 3'));
      expect(three.reason, isNot(contains('μένουν 2')));
      expect(nextTarget(it('db_press', rir: 2), heavy, now).reason, contains('σταμάτα το σετ όταν σου μένουν 2'));
      expect(nextTarget(it('db_press', rir: 1), heavy, now).reason, contains('σταμάτα το σετ όταν σου μένουν 2'));
    });

    test('η οδηγία οδηγεί σε πρόοδο: 7,8 × 9, 9, 9 με «3» → +1 επανάληψη (με «2» θα έμενε ίδιο)', () {
      final followed = nextTarget(it('db_press'), [(ago(3), done('db_press', 7.8, [9, 9, 9], ra: 3)), ...heavy.map((h) => (ago(10), h.$2))], now);
      expect((followed.change, followed.load), (Change.more, 7.8));
      expect(followed.reps, [10, 10, 10]);
      final two = nextTarget(it('db_press'), [(ago(3), done('db_press', 7.8, [9, 9, 9], ra: 2)), ...heavy.map((h) => (ago(10), h.$2))], now);
      expect((two.change, two.load), (Change.hold, 7.8));
    });

    test('μέσα στο εύρος με «1» (το δίδυμο): «σου μένουν 3»· μπάρα: «άφηνε 3 ή περισσότερες»', () {
      final tg = nextTarget(it('db_press'), [(ago(3), done('db_press', 9.3, [10, 9, 9], ra: 1))], now);
      expect((tg.change, tg.load), (Change.hold, 9.3));
      expect(tg.reason, contains('σταμάτα το σετ όταν σου μένουν 3'));
      final bar = nextTarget(it('rdl'), [(ago(3), done('rdl', 20, [10, 9, 9], ra: 1))], now);
      expect((bar.change, bar.load), (Change.hold, 20.0));
      expect(bar.reason, 'Μπάρα χωρίς βραχίονες ασφαλείας: άφησες 1. Ίδια κιλά, και άφηνε 3 ή περισσότερες.');
      final bar2 = nextTarget(it('rdl', rir: 2), [(ago(3), done('rdl', 20, [10, 9, 9], ra: 1))], now);
      expect(bar2.reason, 'Μπάρα χωρίς βραχίονες ασφαλείας: άφησες 1. Ίδια κιλά, και άφηνε 2 ή περισσότερες.');
    });
  });

  // ---------------------------------------------------------------- σημείωση του B5
  test('R10 (σημείωση B5): «Αλλαγή άσκησης» μετά το «Πρώτο σετ» με «0»: η φορά που κρατιέται έχει την απάντηση', () {
    final t = sampleTraining(now, history: false);
    final s = t.start(t.program!.workout('A')!);
    final press = s.items.first;
    t.tick(press, 0);
    expect(t.firstPending(press), isTrue);
    expect(t.answerFirst(press, 0).applied, isTrue);
    t.swap(press, 'pushup_bench');
    final kept = s.items.last;
    expect((kept.ex, kept.done.length, kept.firstAnswer), ('db_press', 1, 0));
    expect(ExLog.fromJson(jsonDecode(jsonEncode(kept.toJson())) as Map<String, dynamic>).firstAnswer, 0);
    // Χωρίς απάντηση στο «Πρώτο σετ»: τίποτα (όπως πριν).
    final t2 = sampleTraining(now, history: false);
    final s2 = t2.start(t2.program!.workout('A')!);
    final p2 = s2.items.first;
    t2.tick(p2, 0);
    t2.swap(p2, 'pushup_bench');
    expect(s2.items.last.firstAnswer, isNull);
  });
}
