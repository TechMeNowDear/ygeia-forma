// Γύρος 7, f2 (προπόνηση, πλευρά κινητού): δοκιμές για τα R7-A6, R7-A8-3/4, R7-A7-4/5, R7-A12-5/6, R7-U3, R7-U1-9.
// Οι αναμενόμενες τιμές βγαίνουν από τους κανόνες όπως γράφονται (τύπος Epley του repsBeforeStep, σκαλιά του
// εξοπλισμού), όχι από την υλοποίηση. Όλες οι τιμές είναι επινοημένες.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/exercise/ex_data.dart';
import 'package:ygeia_forma/exercise/ex_player.dart';
import 'package:ygeia_forma/pages/category.dart' show TabChip;
import 'package:ygeia_forma/pages/training/program_editor.dart';
import 'package:ygeia_forma/pages/training/program_paste.dart';
import 'package:ygeia_forma/pages/training/session_page.dart';
import 'package:ygeia_forma/pages/training/today_training_card.dart';
import 'package:ygeia_forma/pages/training/training_page.dart';
import 'package:ygeia_forma/pages/training/zone_widgets.dart' show zoneInfo;
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/training/equipment.dart';
import 'package:ygeia_forma/training/program.dart';
import 'package:ygeia_forma/training/progress.dart';
import 'package:ygeia_forma/training/progression.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/training_store.dart';
import 'package:ygeia_forma/training/wear_link.dart';

import 'training_sample.dart';

final now = DateTime(2026, 11, 20, 18); // Παρασκευή
DateTime ago(int days) => DateTime(2026, 11, 20 - days, 18);

PlanItem it(String ex, {int sets = 2, int lo = 10, int hi = 15, int rir = 3, double? load}) =>
    PlanItem(ex: ex, sets: sets, lo: lo, hi: hi, rir: rir, rest: 90, load: load);

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

final _libJson = File('assets/exercises/exercises.json').readAsStringSync();
ExLibrary _lib() => ExLibrary.fromJson(jsonDecode(_libJson) as Map<String, dynamic>);

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 1400)}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: w));
  await t.pump();
}

/// Πρόγραμμα με ημερομηνία έναρξης Δευτέρα 16/11 (όπως το v2 του χρήστη, με επινοημένες ασκήσεις).
const _v2 = '{"kind":"ygeia-program","v":1,"id":"p-v2","name":"Δοκιμή","author":"claude","from":"2026-11-16",'
    '"days":{"mon":"LA","tue":"walk","sat":"LB"},'
    '"workouts":[{"id":"LA","name":"Κάτω μέρος Α","items":[{"ex":"leg_ext","sets":2,"reps":[10,15],"rir":3,"rest":90}]},'
    '{"id":"LB","name":"Κάτω μέρος Β","items":[{"ex":"goblet","sets":2,"reps":[8,12],"rir":3,"rest":90}]},'
    '{"id":"walk","name":"Περπάτημα","cardio":{"activity":"walk","minutes":30,"plan":[30,35,40,45]}}]}';

void main() {
  final lib = _lib();
  final ids = {for (final e in lib.list) e.id};

  // ---------------------------------------------------------------- R7-A6-1
  group('R7-A6-1: φορτίο που κατέβασε η εφαρμογή ξανανεβαίνει', () {
    test('διάλειμμα 28 μερών στο ελαφρύ ξεκίνημα (4,3 kg): ίδια κιλά, ξανά από το κάτω όριο, και το λέει', () {
      final t = nextTarget(it('db_curl'), [(ago(28), done('db_curl', 4.3, [13, 13], ra: 4))], now);
      expect(t.load, 4.3);
      expect(t.reps, [10, 10]);
      expect(t.change, Change.hold);
      expect(t.reason, contains('28 μέρες'));
      expect(t.reason, contains('ίδια κιλά'));
    });

    test('διάλειμμα πάνω από το ξεκίνημα: πιο ελαφριά με το πραγματικό μέγεθος (11,8 → 10,3 kg)', () {
      final t = nextTarget(it('db_press', sets: 3, lo: 8, hi: 12), [(ago(20), done('db_press', 11.8, [12, 12, 12], ra: 3, lo: 8, hi: 12))], now);
      expect((t.change, t.load), (Change.back, 10.3));
      expect(t.reason, contains('10,3 kg αντί για 11,8 kg'));
    });

    test('2,8 kg στο πάνω όριο, ενώ τα 4,3 kg έχουν ήδη γίνει: ανεβαίνει στα 4,3 (όχι «πολύ μεγάλο σκαλί»)', () {
      final h = [(ago(3), done('db_curl', 2.8, [15, 15], ra: 4)), (ago(33), done('db_curl', 4.3, [13, 13], ra: 4))];
      final t = nextTarget(it('db_curl'), h, now);
      expect(t.change, Change.up);
      expect(t.load, closeTo(4.3, 1e-9));
      expect(t.reps, [10, 10]);
      // ένα κάτω από το πάνω όριο: +1 επανάληψη, όπως κάθε σκαλί
      final m = nextTarget(it('db_curl'), [(ago(3), done('db_curl', 2.8, [14, 14], ra: 4)), h[1]], now);
      expect((m.change, m.load), (Change.more, 2.8));
      expect(m.reps, [15, 15]);
    });

    test('χωρίς να έχει γίνει ποτέ το βαρύτερο: στο ανώτατο λέει «πες μου» και ότι υπάρχει το «+»', () {
      final t = nextTarget(it('db_curl'), [(ago(3), done('db_curl', 2.8, [20, 20], ra: 4))], now);
      expect(t.change, Change.max);
      expect(t.reason, contains('πες μου'));
      expect(t.reason, contains('«+»'));
    });

    test('απάντηση «1» στο 1ο σετ (20 → 10 lb): με 10 lb στο πάνω όριο, πίσω στα 20 lb αυτόματα', () {
      final cal = ExLog(ex: 'band_pushdown', sets: 2, lo: 10, hi: 15, rir: 3, rest: 60, rirAnswer: 3, log: [
        SetLog(load: 20, reps: 10, done: true),
        SetLog(load: 10, reps: 12, done: true),
      ]);
      expect(calibrate(it('band_pushdown'), 20, 10, 1), 10);
      final t = nextTarget(it('band_pushdown'), [(ago(3), done('band_pushdown', 10, [15, 15], ra: 3)), (ago(6), cal)], now);
      expect((t.change, t.load), (Change.up, 20.0));
      expect(t.reps, [10, 10]);
    });

    test('λάστιχο 20 lb: από την πρώτη φορά λέει ότι το επόμενο (30 lb) δεν μπαίνει μόνο του', () {
      // 20 → 30 lb = ×1,5: repsBeforeStep = ⌈1,5 × (30 + 10 + 3) − 33⌉ = 32 > 15 + 10 → ποτέ αυτόματα, ως τις 15 + 5 = 20.
      final t = nextTarget(it('band_pushdown'), const [], now);
      expect(t.change, Change.first);
      expect(t.reason, contains('πράσινο (30 lb)'));
      expect(t.reason, contains('ως τις 20'));
      expect(t.reason, contains('πες μου'));
      final m = nextTarget(it('band_pushdown'), [(ago(3), done('band_pushdown', 20, [12, 12], ra: 3))], now);
      expect(m.change, Change.more);
      expect(m.reason, contains('πες μου'));
      // στο face pull η βιβλιοθήκη θέλει πάντα ελαφρύ λάστιχο: χωρίς «ανέβασε εσύ με το +»
      final f = nextTarget(it('face_pull', lo: 12), [(ago(3), done('face_pull', 10, [20, 20], ra: 3, lo: 12))], now);
      expect(f.change, Change.max);
      expect(f.reason, isNot(contains('«+»')));
    });

    test('δύο φορές κάτω με τα βαρύτερα (πιο πρόσφατη φορά κάτω από το εύρος): ΔΕΝ μετρά ως «έγινε»', () {
      final h = [
        (ago(3), done('db_press', 4.3, [12, 12], ra: 3, lo: 8, hi: 12)),
        (ago(6), done('db_press', 5.3, [5, 5], ra: 3, lo: 8, hi: 12)),
        (ago(9), done('db_press', 5.3, [5, 5], ra: 3, lo: 8, hi: 12)),
      ];
      final t = nextTarget(it('db_press', lo: 8, hi: 12), h, now);
      // 4,3 → 5,3 (+23%) θέλει ⌈1,2326 × 41 − 33⌉ = 18 επαναλήψεις: εδώ +1
      expect((t.change, t.load), (Change.more, 4.3));
      expect(t.reps, [13, 13]);
    });
  });

  // ---------------------------------------------------------------- R7-A6-3 / A6-2
  group('R7-A6-3: μετά από ενόχληση πιο ελαφριά', () {
    final press = it('db_press', lo: 8, hi: 12);
    test('ώμος: ένα σκαλί κάτω (9,3 → 7,8 kg), ίδιες επαναλήψεις, με την ημερομηνία', () {
      final t = nextTarget(press, [(ago(3), done('db_press', 9.3, [12, 12], ra: 3, lo: 8, hi: 12, pain: ['shoulderR']))], now);
      expect((t.change, t.load), (Change.pain, 7.8));
      expect(t.reps, [12, 12]);
      expect(t.reason, contains('δεξιός ώμος'));
      expect(t.reason, contains('Τρί 17/11'));
      expect(t.reason, contains('Αλλαγή άσκησης'));
    });

    test('δεύτερη φορά: ξανά πιο ελαφριά και πρόταση για εναλλακτική', () {
      final t = nextTarget(press, [
        (ago(3), done('db_press', 7.8, [12, 12], ra: 3, lo: 8, hi: 12, pain: ['shoulderR'])),
        (ago(6), done('db_press', 9.3, [12, 12], ra: 3, lo: 8, hi: 12, pain: ['shoulderR'])),
      ], now);
      expect((t.change, t.load), (Change.pain, 6.8));
      expect(t.reason, contains('δύο τελευταίες'));
      expect(t.reason, contains('εναλλακτική'));
    });

    test('χωρίς πιο ελαφρύ (κίτρινο 10 lb): ίδιο φορτίο, 2 επαναλήψεις λιγότερες', () {
      final t = nextTarget(it('band_pushdown'), [(ago(3), done('band_pushdown', 10, [12, 11], ra: 3, pain: ['elbow']))], now);
      expect((t.change, t.load), (Change.pain, 10.0));
      expect(t.reps, [10, 9]);
    });

    test('ενόχληση χωρίς κανένα σετ (σταμάτησε, μετά «Παράλειψη»): μετρά, από το φορτίο εκείνης της μέρας', () {
      final e = ExLog(ex: 'db_press', sets: 2, lo: 8, hi: 12, rir: 3, rest: 90, skipped: true, pain: ['shoulderR'], log: [
        SetLog(load: 9.3, reps: 10),
        SetLog(load: 9.3, reps: 10),
      ]);
      final t = nextTarget(press, [(ago(3), e)], now);
      expect((t.change, t.load), (Change.pain, 7.8));
      expect(t.reps, [8, 8]);
    });

    test('ενόχληση την Παρ 13/11, την Τρί 17/11 εναλλακτική: σήμερα ο λόγος λέει πότε ήταν η ενόχληση', () {
      // το πιεστικό δεν έγινε στις 17/11 (εναλλακτική στη θέση του): η τελευταία του φορά είναι η 13/11
      final t = nextTarget(press, [(ago(7), done('db_press', 9.3, [12, 12], ra: 3, lo: 8, hi: 12, pain: ['shoulderR']))], now);
      expect(t.change, Change.pain);
      expect(t.reason, contains('Παρ 13/11'));
    });

    test('ενόχληση χωρίς σετ και μετά εναλλακτική στην ίδια προπόνηση: η ενόχληση μένει και μετρά', () {
      final t = sampleTraining(now);
      final s = t.start(t.program!.workout('A')!);
      final press0 = s.items.first;
      t.togglePain(press0, 'shoulderR');
      t.swap(press0, 'pushup_bench');
      t.finish();
      // η επόμενη φορά του πιεστικού: από την ενόχληση της 20/11, πιο ελαφριά
      final tg = t.targetFor(t.program!.workout('A')!.items.first);
      expect(tg.change, Change.pain);
      expect(tg.reason, contains('Παρ 20/11'));
    });
  });

  group('R7-A6-2: «Πόνεσε κάπου» σε κάθε σημείο της άσκησης', () {
    testWidgets('μετά από 1 από 3 σετ: ⋮ › «Πόνεσε κάπου» → δεξιός ώμος → μένει στην άσκηση και στον επόμενο στόχο', (tester) async {
      final at = DateTime(2026, 11, 13, 17, 30);
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final store = sampleTraining(at);
      final s = store.start(store.program!.workout('A')!);
      store.tick(s.items.first, 0);
      await _pump(tester, SessionPage(training: store));
      expect(find.byKey(const ValueKey('sess-pain-btn')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sess-more')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const ValueKey('sess-pain')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const ValueKey('pain-shoulderR')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pain-ok')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(s.items.first.pain, ['shoulderR']);
      expect(find.byKey(const ValueKey('sess-pain-line')), findsOneWidget);
      store.finish();
      final tg = store.targetFor(store.program!.workout('A')!.items.first);
      expect(tg.change, Change.pain);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  // ---------------------------------------------------------------- R7-A8-4
  group('R7-A8-4: «Αλλαγή άσκησης» μετά από ✓ δεν σβήνει σετ και ενόχληση', () {
    test('2 σετ + ενόχληση → εναλλακτική: το πιεστικό μένει (στο τέλος) με 2 σετ, την ενόχληση και τα 3 σετ του προγράμματος', () {
      final t = sampleTraining(now);
      final s = t.start(t.program!.workout('A')!);
      final before = [for (final e in s.items) e.ex];
      final press = s.items.first;
      expect(press.log.first.load, 10.3); // 12, 12, 12 με 9,3 την προηγούμενη φορά
      t.tick(press, 0);
      t.tick(press, 1);
      t.togglePain(press, 'shoulderR');
      t.swap(press, 'pushup_bench');
      expect(s.items.length, before.length + 1);
      expect(s.items.first.ex, 'pushup_bench');
      expect(s.items.first.swappedFrom, 'db_press');
      expect([for (final e in s.items.skip(1).take(before.length - 1)) e.ex], before.skip(1).toList(), reason: 'οι θέσεις δεν αλλάζουν');
      final kept = s.items.last;
      expect((kept.ex, kept.done.length, kept.sets, kept.plannedSets), ('db_press', 2, 2, 3));
      expect(kept.pain, ['shoulderR']);
      expect(ExLog.fromJson(jsonDecode(jsonEncode(kept.toJson())) as Map<String, dynamic>).plannedSets, 3);
      t.finish();
      expect(t.historyOf('db_press').first.$2.done.length, 2);
      final tg = t.targetFor(t.program!.workout('A')!.items.first);
      expect((tg.change, tg.load), (Change.pain, 9.3));
    });

    test('χωρίς ενόχληση: την επόμενη φορά «δεν έγιναν όλα τα σετ», ίδιο βάρος (όχι +1)', () {
      final t = sampleTraining(now);
      final s = t.start(t.program!.workout('A')!);
      final press = s.items.first;
      t.tick(press, 0);
      t.tick(press, 1);
      t.swap(press, 'pushup_bench');
      t.finish();
      final tg = t.targetFor(t.program!.workout('A')!.items.first);
      expect((tg.change, tg.load), (Change.hold, 10.3));
      expect(tg.reason, contains('δεν έγιναν όλα τα σετ'));
    });

    test('παλιό αρχείο χωρίς «ps»: διαβάζεται όπως πριν', () {
      final e = ExLog.fromJson({'ex': 'db_press', 'sets': 3, 'lo': 8, 'hi': 12, 'log': []});
      expect(e.plannedSets, isNull);
      expect(e.toJson().containsKey('ps'), isFalse);
    });
  });

  // ---------------------------------------------------------------- R7-A8-3
  group('R7-A8-3: ξεχασμένη προπόνηση δεν «καταπίνει» τη σημερινή', () {
    test('✓/παλμοί του ρολογιού 25 ώρες μετά: όχι μέσα της· ✓ που άργησε (ίδια ώρα): ναι· «Τέλος» στο τελευταίο ✓', () {
      var at = now;
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => at)..replaceAll(sampleTraining(now).toJson());
      final link = WearLink()..attachForTest(t);
      final s = t.start(t.program!.workout('A')!);
      at = now.add(const Duration(minutes: 5));
      t.tick(s.items.first, 0);
      at = now.add(const Duration(hours: 25));
      expect(t.isStale(s), isTrue);
      link.apply(t, WatchCmd('tick', {'i': 0, 's': 1, 'sid': s.id, 'ex': s.items.first.ex}));
      link.apply(t, WatchCmd('tick', {'i': 0, 's': 1, 'sid': s.id, 'at': at.millisecondsSinceEpoch}));
      expect(s.items.first.log[1].done, isFalse);
      expect(t.isStale(s), isTrue, reason: 'η χθεσινή μένει «ξεχασμένη»');
      t.addHr(120, at, sid: s.id);
      expect(s.hr, isEmpty);
      // ✓ του ρολογιού από την ίδια προπόνηση που άργησε να φτάσει (στο 8′): γράφεται
      link.apply(t, WatchCmd('tick', {'i': 0, 's': 1, 'sid': s.id, 'late': true, 'at': now.add(const Duration(minutes: 8)).millisecondsSinceEpoch}));
      expect(s.items.first.log[1].done, isTrue);
      // το αποτέλεσμα του ρολογιού με ένα ✓ και παλμούς της επομένης, και «Τέλος» της επομένης
      final items = [for (final e in s.items) jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>];
      final log = (items.first['log'] as List).cast<Map<String, dynamic>>();
      log[2] = {...log[2], 'd': 1, 't': at.millisecondsSinceEpoch};
      t.importWatch({
        'v': 1,
        'kind': 'hr',
        'sid': s.id,
        'hrT0': s.start.millisecondsSinceEpoch,
        'hr': [
          [60, 100],
          [25 * 3600, 130],
        ],
        'items': items,
        'fin': at.millisecondsSinceEpoch,
      });
      final f = t.sessions.firstWhere((x) => x.id == s.id);
      expect(f.setsDone, 2);
      expect(f.end, now.add(const Duration(minutes: 8)));
      expect([for (final p in f.hr) p[0]], [60]);
    });
  });

  // ---------------------------------------------------------------- R7-A7
  group('R7-A7', () {
    test('A7-5: μία τιμή πάνω από το όριο και 55″ χωρίς επαφή = 15″ (όπως ο χρόνος ζώνης), όχι 55″', () {
      final s = Session(id: 'x', workout: 'A', name: 'Α', programId: 'p', start: now, hr: [
        [0, 141],
        [55, 120],
      ]);
      expect(HrSummary(s, 140).overSec, 15);
    });

    test('A7-4: το ⓘ της ζώνης λέει ότι η δική σου μέτρηση ξύπνιος νικά τους παλμούς ύπνου', () {
      expect(zoneInfo.accuracy, contains('δική σου μέτρηση ξύπνιος'));
      expect(zoneInfo.accuracy, contains('τουλάχιστον 7'));
    });
  });

  // ---------------------------------------------------------------- R7-A12-5 / 6
  group('R7-A12-5: λίγο κάτω από τον στόχο ΜΕ τη ρεζέρβα του προγράμματος δεν είναι αποτυχία', () {
    final i3 = it('db_press', sets: 3, lo: 8, hi: 12, rir: 3);
    (DateTime, ExLog) at93(int days, List<int> reps) => (ago(days), done('db_press', 9.3, reps, ra: 3, lo: 8, hi: 12));
    test('[7, 7, 7] με ρεζέρβα 3 → +1, ίδια κιλά· και δύο φορές στη σειρά → πάλι +1 (όχι κάτω)', () {
      final a = nextTarget(i3, [at93(3, [7, 7, 7])], now);
      expect((a.change, a.load), (Change.more, 9.3));
      expect(a.reps, [8, 8, 8]);
      expect(a.reason, contains('Σταμάτησες λίγο πριν'));
      final b = nextTarget(i3, [at93(3, [7, 7, 7]), at93(6, [7, 7, 7])], now);
      expect((b.change, b.load), (Change.more, 9.3));
      expect(b.reps, [8, 8, 8]);
    });

    test('[5, 5, 5] (3 κάτω) → ίδια, στόχος 8· δύο φορές → ένα σκαλί κάτω, 7,8 kg', () {
      final a = nextTarget(i3, [at93(3, [5, 5, 5])], now);
      expect((a.change, a.load), (Change.hold, 9.3));
      expect(a.reps, [8, 8, 8]);
      final b = nextTarget(i3, [at93(3, [5, 5, 5]), at93(6, [5, 5, 5])], now);
      expect((b.change, b.load), (Change.down, 7.8));
      expect(b.reps, [8, 8, 8]);
    });
  });

  test('R7-A12-6: «μεγάλο σκαλί» +11,7% και +14,6%: όριο από τον τύπο (Epley)', () {
    // 14,3 / 12,8 = 1,1172 → ⌈1,1172 × 41 − 33⌉ = 13 · 11,8 / 10,3 = 1,1456 → ⌈1,1456 × 41 − 33⌉ = 14
    expect(stepCeiling('db_press', LoadKind.dbPair, 12.8, 14.3, 8, 12, 3), (reps: 13, step: true));
    expect(stepCeiling('db_press', LoadKind.dbPair, 10.3, 11.8, 8, 12, 3), (reps: 14, step: true));
  });

  // ---------------------------------------------------------------- R7-A6-5 / 6 / 7 / 10 / 11
  group('R7-A6-5: επικόλληση όλου του μηνύματος', () {
    test('με «{» και «}» στο κείμενο πριν από το ```json', () {
      final r = parseProgram('Αντέγραψε (από το πρώτο `{` ως το τελευταίο `}`):\n```json\n$_v2\n```\nΚαλή προπόνηση!', ids);
      expect(r.ok, isTrue, reason: r.errors.join('\n'));
      expect(r.program!.id, 'p-v2');
    });

    test('χωρίς ```: το πρώτο «{» που κλείνει σε πρόγραμμα', () {
      final r = parseProgram('Οδηγία: από το πρώτο `{` ως το τελευταίο `}`.\n$_v2\nΤέλος `}`.', ids);
      expect(r.ok, isTrue, reason: r.errors.join('\n'));
    });

    test('μισό πρόγραμμα: το ίδιο μήνυμα λάθους', () {
      final r = parseProgram(_v2.substring(0, _v2.length - 20), ids);
      expect(r.ok, isFalse);
      expect(r.errors.single, contains('μισό'));
    });
  });

  group('R7-A6-6: καμία προπόνηση πριν από την έναρξη του προγράμματος', () {
    test('Σάββατο 14/11 (έναρξη Δευ 16/11): ξεκούραση, ούτε στο ρολόι· από 16/11 κανονικά', () {
      final p = parseProgram(_v2, ids).program!;
      expect(p.forDay(DateTime(2026, 11, 14, 10)), isNull);
      expect(p.forDay(DateTime(2026, 11, 16, 0, 5))!.id, 'LA');
      expect(p.forDay(DateTime(2026, 11, 21))!.id, 'LB');
      expect(p.planWeekText(p.workout('walk')!.cardio!, DateTime(2026, 11, 10)), isNull);
      expect(p.planWeekText(p.workout('walk')!.cardio!, DateTime(2026, 11, 17)), 'εβδομάδα 1 από 4');
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => DateTime(2026, 11, 14, 10))..ready = true;
      t.saveProgram(p, author: 'claude');
      expect(watchPlan(t, DateTime(2026, 11, 14, 10), (x) => x).containsKey('today'), isFalse);
      expect(watchPlan(t, DateTime(2026, 11, 21, 10), (x) => x)['today'], 'LB');
      expect(TodayTrainingCard.shows(t, DateTime(2026, 11, 14, 10)), isFalse);
    });

    testWidgets('η Άσκηση το λέει: «Το πρόγραμμα ξεκινά τη Δευτέρα 16 Νοεμβρίου»', (tester) async {
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final at = DateTime(2026, 11, 14, 10);
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => at)..ready = true;
      t.saveProgram(parseProgram(_v2, ids).program!, author: 'claude');
      await _pump(tester, Scaffold(body: TrainingPage(training: t, now: at)), size: const Size(400, 2400));
      expect(find.byKey(const ValueKey('train-not-started')), findsOneWidget);
      expect(find.textContaining('τη Δευτέρα 16 Νοεμβρίου'), findsOneWidget);
    });
  });

  group('R7-A6-7: ασκήσεις μίας πλευράς: ένα ✓ = δεξιά και αριστερά', () {
    test('κωπηλασία 9,3 kg × 10, 10: 372 kg (όχι 186)· χρόνος με τις δύο πλευρές', () {
      final e = done('db_row', 9.3, [10, 10], lo: 8, hi: 12);
      expect(e.volume, closeTo(9.3 * 10 * 2 * 2, 1e-9));
      expect(done('db_press', 9.3, [10, 10], lo: 8, hi: 12).volume, closeTo(9.3 * 10 * 2 * 2, 1e-9), reason: 'ζευγάρι: όπως πριν');
      // 3 × (2 × 40″ + 5″ + 90″) + 120″ = 645″ ≈ 11 λεπτά· η ίδια με δύο χέρια: 3 × (40 + 90) + 120 = 510″ ≈ 9
      expect(Workout(id: 'a', name: 'α', items: [PlanItem(ex: 'db_row', sets: 3, rest: 90)]).minutes, 11);
      expect(Workout(id: 'a', name: 'α', items: [PlanItem(ex: 'db_press', sets: 3, rest: 90)]).minutes, 9);
    });
  });

  test('R7-A6-10: λάστιχο / kettlebell με τις δικές τους λέξεις, αρνητικό βάρος = λάθος', () {
    final ok = parseProgram('{"kind":"ygeia-program","workouts":[{"id":"A","name":"Α","items":'
        '[{"ex":"band_pulldown","load":25},{"ex":"goblet","load":7}]}]}', ids);
    expect(ok.ok, isTrue, reason: ok.errors.join('\n'));
    expect(ok.warnings.any((w) => w.contains('δεν βγαίνει με τα λάστιχά σου') && w.contains('μπλε (20 lb)')), isTrue, reason: ok.warnings.join('\n'));
    expect(ok.warnings.any((w) => w.contains('Δεν υπάρχει kettlebell 7 kg') && w.contains('6 kg')), isTrue, reason: ok.warnings.join('\n'));
    expect(ok.warnings.any((w) => w.contains('δίσκους')), isFalse);
    final neg = parseProgram('{"kind":"ygeia-program","workouts":[{"id":"A","name":"Α","items":[{"ex":"db_press","load":-5}]}]}', ids);
    expect(neg.ok, isFalse);
    expect(neg.errors.any((e) => e.contains('αρνητικό')), isTrue);
  });

  test('R7-A6-11: βάρος που άλλαξε μέσα στην άσκηση: κάθε σετ με το δικό του, η πρόοδος με το τελικό', () {
    final mixed = ExLog(ex: 'db_curl', sets: 2, lo: 10, hi: 15, rir: 3, rest: 90, log: [
      SetLog(load: 4.3, reps: 10, done: true),
      SetLog(load: 2.8, reps: 12, done: true),
    ]);
    expect(mixed.mixedLoads, isTrue);
    expect(mixed.endLoad, 2.8);
    expect(mixed.doneText(), '4,3 kg × 10 · 2,8 kg × 12');
    expect(done('db_curl', 2.8, [12, 12]).doneText(), '2,8 kg · 12, 12');
    final p = ExProgress(ex: 'db_curl', kind: LoadKind.dbPair, beforeDay: ago(10), before: done('db_curl', 2.8, [12, 12]), nowDay: ago(3), now: mixed);
    expect(p.loadDiff, 0, reason: 'τελείωσε με 2,8 kg και τις δύο φορές (με το μεγαλύτερο θα έβγαινε +1,5)');
  });

  // ---------------------------------------------------------------- R7-A6-4
  testWidgets('R7-A6-4: «Την επόμενη φορά» = ο στόχος της επόμενης προπόνησης (εύρος του προγράμματος, όχι της μέρας)', (tester) async {
    await tester.runAsync(() => ExLibrary.load(inline: true));
    var at = DateTime(2026, 11, 16, 18);
    final t = TrainingStore(io: MemoryTrainingIO(), clock: () => at)..ready = true;
    t.saveProgram(parseProgram(_v2, ids).program!, author: 'claude');
    t.sessions.add(Session(
      id: 'h1',
      workout: 'LA',
      name: 'Κάτω μέρος Α',
      programId: 'p-v2',
      start: DateTime(2026, 11, 16, 18),
      end: DateTime(2026, 11, 16, 19),
      items: [done('leg_ext', 3, [9, 8], ra: 3)],
    ));
    at = DateTime(2026, 11, 23, 18);
    final s = t.start(t.program!.workout('LA')!);
    final e = s.items.single;
    expect(e.lo, 9, reason: 'ο στόχος της μέρας 10, 9 (σταμάτησε λίγο πριν, +1)');
    t.tick(e, 0);
    t.tick(e, 1);
    t.setReps(e, 0, 15);
    t.setReps(e, 1, 15);
    t.answer(e, 4);
    await _pump(tester, SummaryPage(training: t, session: s, live: true), size: const Size(400, 2400));
    // 15, 15 με «4+» στο πάνω όριο (15) → κέρατο 3 → 3,5 kg (+0,5), ξανά από το κάτω όριο του ΠΡΟΓΡΑΜΜΑΤΟΣ (10)
    expect(find.textContaining('3,5 kg · 2 × 10'), findsOneWidget);
    expect(find.textContaining('3,5 kg · 2 × 9'), findsNothing);
    t.finish();
    final real = t.targetFor(t.program!.workout('LA')!.items.single);
    expect(real.load, 3.5);
    expect(real.reps, [10, 10]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  // ---------------------------------------------------------------- R7-A6-8 / 9 (βιβλιοθήκη)
  group('R7-A6-8 / A6-9: κείμενα βιβλιοθήκης που συμφωνούν με την εφαρμογή', () {
    test('κάμψεις πάγκου: όχι «3 σετ των 15»· κοιλιακοί: δίσκος από 0,5 kg, όχι «3 × 20»', () {
      expect(lib.byId('pushup_bench')!.tips.any((x) => x.contains('3 σετ των 15')), isFalse);
      expect(lib.byId('pushup_bench')!.tips.any((x) => x.contains('Στο ανώτατο')), isTrue);
      expect(lib.byId('crunch')!.tips.any((x) => x.contains('3 × 20')), isFalse);
      expect(lib.byId('crunch')!.tips.any((x) => x.contains('0,5 kg')), isTrue);
      // η εφαρμογή: κοιλιακοί χωρίς δίσκο → πρώτο σκαλί 0,5 kg
      expect(stepUp(LoadKind.plate, 0), 0.5);
    });

    test('εξωτερική στροφή στον στύλο της βάσης: «Δίσκοι στη βάση για να μη γείρει»', () {
      expect(lib.byId('band_er')!.setup.first, contains('για να μη γείρει'));
    });

    testWidgets('αλλαγή άσκησης: οι «με προσοχή» στο τέλος, με την προειδοποίησή τους', (tester) async {
      final at = DateTime(2026, 11, 13, 17, 30);
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final store = sampleTraining(at);
      store.start(store.program!.workout('A')!);
      await _pump(tester, SessionPage(training: store), size: const Size(400, 2400));
      await tester.tap(find.byKey(const ValueKey('sess-more')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const ValueKey('sess-swap')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('swap-caution-dips')), findsOneWidget);
      final dips = tester.getTopLeft(find.byKey(const ValueKey('swap-dips'))).dy;
      expect(tester.getTopLeft(find.byKey(const ValueKey('swap-pushup_bench'))).dy, lessThan(dips));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  // ---------------------------------------------------------------- R7-U3 / U1-9
  group('R7-U3 / R7-U1-9: κείμενα και διάταξη', () {
    testWidgets('U3-09 «ξεκούραση 2:00» αδιάσπαστο· Β-Α2 «Πάμε» στο διάλειμμα', (tester) async {
      final at = DateTime(2026, 11, 13, 17, 30);
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final store = sampleTraining(at);
      store.start(store.program!.workout('A')!);
      store.restEnd = at.add(const Duration(seconds: 90));
      await _pump(tester, SessionPage(training: store));
      final plan = tester.widget<Text>(find.byKey(const ValueKey('sess-plan'))).textSpan!.toPlainText();
      expect(plan, contains('ξεκούραση '));
      expect(find.descendant(of: find.byKey(const ValueKey('rest-stop')), matching: find.text('Πάμε')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('U3-11: σε άλλη όψη το «Οδηγοί» δεν μένει αναμμένο· το πάτημα γυρίζει στην κύρια όψη με οδηγούς', (tester) async {
      ExClock.frozen = true;
      addTearDown(() => ExClock.frozen = false);
      await _pump(tester, Scaffold(body: SingleChildScrollView(child: ExPlayer(ex: lib.byId('db_press')!))));
      bool on() => tester.widget<TabChip>(find.byKey(const ValueKey('ex-guides'))).selected;
      await tester.tap(find.byKey(const ValueKey('ex-view')));
      await tester.pump();
      expect(on(), isFalse);
      await tester.tap(find.byKey(const ValueKey('ex-guides')));
      await tester.pump();
      expect(on(), isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('U3-12: η εβδομάδα της επικόλλησης χωρίς εσωτερικούς κωδικούς και «Περ.»', (tester) async {
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => DateTime(2026, 11, 14, 10))..ready = true;
      final text = _v2.replaceAll('"LA"', '"UA"').replaceAll('Κάτω μέρος Α', 'Πάνω μέρος Α');
      await _pump(tester, ProgramPastePage(training: t, initial: text), size: const Size(400, 2400));
      expect(find.text('UA'), findsNothing);
      expect(find.text('Περ.'), findsNothing);
      expect(tester.widget<Text>(find.byKey(const ValueKey('paste-week-1'))).data, 'ΠΑ');
      expect(find.byKey(const ValueKey('paste-week-2')), findsOneWidget);
      expect(tester.widget(find.byKey(const ValueKey('paste-week-2'))), isA<Icon>());
    });

    test('U3-13: «Αντίγραψε», όχι «Αντίγραφε»', () {
      expect(File('lib/pages/training/program_paste.dart').readAsStringSync().contains('Αντίγραφε'), isFalse);
    });

    testWidgets('U3-15: ο επεξεργαστής δείχνει το πλάνο περπατήματος (30 → 45), όχι μόνο «30 λεπτά»', (tester) async {
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => DateTime(2026, 11, 14, 10))..ready = true;
      await _pump(tester, ProgramEditorPage(training: t, program: parseProgram(_v2, ids).program!), size: const Size(400, 2400));
      expect(find.textContaining('30 → 45 λεπτά'), findsOneWidget);
    });

    testWidgets('U1-9: «όριο παλμών 140» με αδιάσπαστα κενά και στις δύο θέσεις', (tester) async {
      final fri = DateTime(2026, 11, 13, 17, 30);
      await tester.runAsync(() => ExLibrary.load(inline: true));
      await _pump(tester, Scaffold(body: SingleChildScrollView(child: TodayTrainingCard(training: sampleTraining(fri), now: fri))));
      expect(find.textContaining('όριο παλμών 140'), findsOneWidget);
    });
  });
}
