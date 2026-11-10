// 9/11: «Πρόοδος»: περπάτημα (ίδιος έλεγχος με τις Τάσεις, παλμοί μαζί με ρυθμό) και δύναμη (γεγονότα).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/exercise/ex_data.dart';
import 'package:ygeia_forma/pages/training/progress_page.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/training/progress.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/training_store.dart';
import 'package:ygeia_forma/trends.dart';
import 'package:ygeia_forma/widgets.dart';

final now = DateTime(2026, 12, 31, 20, 0);

const _noise = [2, -2, 1, -1, 0, 2, -1, -2, 1, 0, -1, 2];

/// Περπάτημα [daysAgo] μέρες πριν: 30′ ενεργά, [km] km, παλμοί σταθερού βαδίσματος [hr], πτώση στο 1′ [hrr].
/// Έλεγχος 9/11 (V-B-11): η Πρόοδος συγκρίνει πια τους παλμούς από το 5′ και μετά, από τις τιμές· γι' αυτό τιμές ανά 10″
/// (τα πρώτα 5′ πιο χαμηλά, όπως στο ζέσταμα, χωρίς να μετρούν).
Session walk(int daysAgo, {int hr = 110, double km = 2.3, int? hrr, bool gps = true, int sec = 1800, String? activity, bool stopped = false}) {
  final start = DateTime(now.year, now.month, now.day - daysAgo, 18);
  return Session(
    id: 'w$daysAgo-$hr',
    workout: 'walk',
    name: 'Περπάτημα',
    programId: '',
    start: start,
    end: start.add(Duration(seconds: sec + 60)),
    cardioMinutes: sec ~/ 60,
    cardioSec: sec,
    meters: km * 1000,
    gps: gps,
    hrAvg: hr,
    hr: [for (var t = 0; t <= sec; t += 10) [t, t < 300 ? hr - 12 : hr]],
    hrrEnd: hrr == null ? null : 120,
    hrr1: hrr == null ? null : 120 - hrr,
    activity: activity,
    stopped: stopped,
    source: 'watch',
  );
}

/// 6 περπατήματα σε κάθε περίοδο του μήνα (κάθε 5 μέρες).
List<Session> twoMonths({required int hrBefore, required int hrNow, double kmBefore = 2.3, double kmNow = 2.3, int hrrBefore = 16, int hrrNow = 16}) => [
      for (var i = 0; i < 6; i++) walk(32 + i * 5, hr: hrBefore + _noise[i], km: kmBefore, hrr: hrrBefore + _noise[i + 6]),
      for (var i = 0; i < 6; i++) walk(1 + i * 5, hr: hrNow + _noise[i + 3], km: kmNow, hrr: hrrNow + _noise[i]),
    ];

Session lift(int daysAgo, List<ExLog> items) {
  final start = DateTime(now.year, now.month, now.day - daysAgo, 18);
  return Session(id: 's$daysAgo', workout: 'A', name: 'Προπόνηση Α', programId: 'p', start: start, end: start.add(const Duration(minutes: 50)), items: items);
}

ExLog ex(String id, double? load, List<int> reps) =>
    ExLog(ex: id, sets: reps.length, lo: 8, hi: 12, rir: 2, rest: 90, log: [for (final r in reps) SetLog(load: load, reps: r, done: true)]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ποια περπατήματα μετράνε', () {
    test('μόνο με GPS, πάνω από 15′, όχι «Σταμάτησα», μόνο περπάτημα', () {
      expect(countsAsWalk(walk(1)), isTrue);
      expect(countsAsWalk(walk(1, gps: false)), isFalse);
      expect(countsAsWalk(walk(1, sec: 14 * 60)), isFalse);
      expect(countsAsWalk(walk(1, stopped: true)), isFalse);
      expect(countsAsWalk(walk(1, activity: 'run')), isFalse);
      expect(countsAsWalk(walk(1, activity: 'walk')), isTrue);
    });

    test('το είδος από το ρολόι γράφεται και μένει μετά από φόρτωμα', () async {
      final io = MemoryTrainingIO();
      final t = TrainingStore(io: io, clock: () => now);
      final start = now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch;
      t.importWatch({
        'v': 1, 'kind': 'cardio', 'id': 'a1', 'start': start, 'end': start + 1900000, 'hrAvg': 104,
        'cardio': {'activity': 'walk', 'sec': 1800, 'm': 2300.0, 'gps': true},
      });
      await t.save();
      final back = TrainingStore(io: io, clock: () => now);
      await back.load();
      expect(back.sessions.single.activity, 'walk');
      expect(countsAsWalk(back.sessions.single), isTrue);
    });

    test('δύο περπατήματα την ίδια μέρα: μία τιμή (μέσος όρος)', () {
      final h = walkHistory([walk(1, hr: 100), walk(1, hr: 110)]);
      expect(h.length, 1);
      expect(h.values.single['pw.hr'], 105);
    });
  });

  group('περπάτημα', () {
    test('παλμοί −8 (μεσαία τιμή) στον ίδιο ρυθμό: «καλύτερα»', () {
      final w = walkProgress(twoMonths(hrBefore: 112, hrNow: 105), now, TrendPeriod.month);
      expect(w.hr.status, TrendStatus.down);
      expect(w.paceRel, PaceRel.same);
      expect(w.hrGoodness, 1);
      expect(w.pace.status, TrendStatus.stable);
      expect(w.hrr.status, TrendStatus.stable);
      expect((w.countNow, w.countBefore), (6, 6));
    });

    test('παλμοί −7 αλλά πιο αργό βάδισμα: όχι βελτίωση', () {
      final w = walkProgress(twoMonths(hrBefore: 112, hrNow: 105, kmBefore: 2.5, kmNow: 2.2), now, TrendPeriod.month);
      expect(w.hr.status, TrendStatus.down);
      expect(w.paceRel, PaceRel.slower);
      expect(w.hrGoodness, 0);
    });

    test('παλμοί +7 με πιο γρήγορο βάδισμα: ουδέτερο· +7 στον ίδιο ρυθμό: χειρότερα', () {
      expect(walkProgress(twoMonths(hrBefore: 105, hrNow: 112, kmBefore: 2.2, kmNow: 2.5), now, TrendPeriod.month).hrGoodness, 0);
      expect(walkProgress(twoMonths(hrBefore: 105, hrNow: 112), now, TrendPeriod.month).hrGoodness, -1);
    });

    test('μικρή διαφορά (2 παλμοί, κάτω από το ελάχιστο 3): «Σταθερό»', () {
      expect(walkProgress(twoMonths(hrBefore: 110, hrNow: 109), now, TrendPeriod.month).hr.status, TrendStatus.stable);
    });

    // Έλεγχος 9/11 (V-B-08): πριν «καλύτερα» (goodness 1)· τώρα ουδέτερο, γιατί εξαρτάται κυρίως από την ένταση.
    test('μεγαλύτερη πτώση παλμών στο 1′ (16 → 24): φαίνεται, αλλά ουδέτερα', () {
      final w = walkProgress(twoMonths(hrBefore: 110, hrNow: 110, hrrBefore: 16, hrrNow: 24), now, TrendPeriod.month);
      expect(w.hrr.status, TrendStatus.up);
      expect(w.hrr.goodness, 0);
      expect(w.hrrEnd.current, 120);
    });

    test('λιγότερες από 4 μέρες σε μία περίοδο: «Λίγα δεδομένα», κανένα συμπέρασμα', () {
      final s = [for (var i = 0; i < 6; i++) walk(1 + i * 4, hr: 100), for (var i = 0; i < 3; i++) walk(35 + i * 4, hr: 120)];
      final w = walkProgress(s, now, TrendPeriod.month);
      expect(w.insufficient, isTrue);
      expect(w.hr.changed, isFalse);
      expect((w.hr.nCurrent, w.hr.nPrevious), (6, 3));
    });

    test('περπατήματα χωρίς GPS δεν μπαίνουν στη σύγκριση', () {
      final s = [for (final x in twoMonths(hrBefore: 112, hrNow: 105)) x..gps = false];
      expect(walkProgress(s, now, TrendPeriod.month).insufficient, isTrue);
    });
  });

  group('δύναμη', () {
    final sessions = [
      lift(40, [ex('db_press', 9.3, [8, 8, 7]), ex('hammer_curl', 6.8, [12, 11, 11]), ex('goblet', 12, [12, 12, 12]), ex('assisted_pullup', 40, [8, 8, 8])]),
      lift(20, [ex('db_press', 10.3, [8, 8, 8]), ex('lateral_raise', 4.3, [10, 10, 10])]),
      lift(3, [
        ex('db_press', 11.3, [10, 9, 9]),
        ex('hammer_curl', 6.8, [10, 9, 9]),
        ex('goblet', 14, [9, 9, 8]),
        ex('assisted_pullup', 30, [8, 8, 8]),
        ex('lateral_raise', 4.3, [12, 11, 10]),
        ex('db_curl', 6.8, [10, 10, 10]),
      ]),
    ];
    final r = {for (final p in strengthProgress(sessions, now, TrendPeriod.month)) p.ex: p};

    test('πριν = η τελευταία φορά πριν από τον μήνα, τώρα = η πιο πρόσφατη', () {
      expect(r['db_press']!.before.workLoad, 9.3);
      expect(r['db_press']!.now.workLoad, 11.3);
      expect(r['db_press']!.change, StrengthChange.up);
      expect(strengthPill(r['db_press']!).$1, '2 kg');
    });

    test('ίδιο βάρος, λιγότερες επαναλήψεις: πτώση (φαίνεται)', () {
      expect(r['hammer_curl']!.change, StrengthChange.down);
      expect(r['hammer_curl']!.repsDiff, -6);
      expect(strengthPill(r['hammer_curl']!), ('6 επαν.', TrendKind.bad, false));
    });

    // Έλεγχος 9/11 (V-B-12): πριν «μικτό». 12 → 14 kg με 9, 9, 8 (κάτω όριο 8) είναι η κανονική πρόοδος του προγράμματος.
    test('περισσότερο βάρος, λιγότερες επαναλήψεις αλλά μέσα στο εύρος: πρόοδος', () {
      expect(r['goblet']!.change, StrengthChange.up);
      expect(strengthPill(r['goblet']!), ('2 kg', TrendKind.good, true));
    });

    test('περισσότερο βάρος με σετ κάτω από το εύρος: ούτε καλύτερα ούτε χειρότερα', () {
      final p = strengthProgress([
        lift(40, [ex('goblet', 12, [12, 12, 12])]),
        lift(2, [ex('goblet', 14, [9, 8, 7])]),
      ], now, TrendPeriod.month).single;
      expect(p.change, StrengthChange.mixed);
      expect(strengthPill(p).$2, TrendKind.neutral);
    });

    test('λάστιχο βοήθειας: λιγότερη βοήθεια = πρόοδος', () {
      expect(r['assisted_pullup']!.change, StrengthChange.up);
      expect(strengthPill(r['assisted_pullup']!).$1, 'λιγότερη βοήθεια');
    });

    test('άσκηση που ξεκίνησε μέσα στον μήνα: πρώτη → πιο πρόσφατη· μία μόνο φορά: δεν φαίνεται', () {
      expect(r['lateral_raise']!.repsDiff, 3);
      expect(r.containsKey('db_curl'), isFalse);
    });

    test('μία επανάληψη πάνω-κάτω: «Ίδιο»· με περισσότερο βάρος και −1: πρόοδος', () {
      final p = strengthProgress([
        lift(40, [ex('db_row', 14.3, [10, 10, 10]), ex('db_curl', 6.8, [10, 10, 10])]),
        lift(2, [ex('db_row', 14.3, [10, 10, 9]), ex('db_curl', 7.8, [10, 10, 9])]),
      ], now, TrendPeriod.month);
      final m = {for (final x in p) x.ex: x};
      expect(m['db_row']!.change, StrengthChange.same);
      expect(m['db_curl']!.change, StrengthChange.up);
    });

    test('διαφορετικό πλήθος σετ: συγκρίνονται τα κοινά', () {
      final p = strengthProgress([
        lift(40, [ex('db_row', 14.3, [10, 10])]),
        lift(2, [ex('db_row', 14.3, [10, 10, 6])]),
      ], now, TrendPeriod.month).single;
      expect(p.repsDiff, 0);
      expect(p.change, StrengthChange.same);
    });
  });

  group('οθόνη', () {
    testWidgets('κινητό: σύνοψη, περπάτημα, δύναμη, ⓘ', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 2600);
      addTearDown(tester.view.reset);
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => now)..ready = true;
      t.sessions.addAll([...twoMonths(hrBefore: 112, hrNow: 105), lift(40, [ex('db_press', 9.3, [8, 8, 7])]), lift(3, [ex('db_press', 11.3, [10, 9, 9])])]);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: ProgressPage(training: t, now: now)));
      await tester.pumpAndSettle();
      // Από προεπιλογή 3 μήνες (έλεγχος 9/11, V-B-10)· τα δεδομένα εδώ είναι για τον μήνα.
      await tester.tap(find.byKey(const ValueKey('prog-month')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('prog-summary')), findsOneWidget);
      expect(find.textContaining('έπεσαν 8'), findsOneWidget);
      expect(find.byKey(const ValueKey('prog-walk-hr')), findsOneWidget);
      expect(find.byKey(const ValueKey('prog-ex-db_press')), findsOneWidget);
      expect(find.byKey(const ValueKey('prog-body')), findsNothing, reason: 'χωρίς δεδομένα υγείας δεν δείχνει την κάρτα');
      await tester.tap(find.byKey(const ValueKey('prog-walk-info')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('prog-walk-sheet')), findsOneWidget);
    });

    testWidgets('λίγα δεδομένα: εξήγηση με το πόσα έχουν γίνει', (tester) async {
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => now)..ready = true;
      t.sessions.addAll([walk(1), walk(3)]);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: ProgressPage(training: t, now: now)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('prog-walk-few')), findsOneWidget);
      expect(find.text('Καμία ξεκάθαρη αλλαγή ακόμα.'), findsOneWidget);
      expect(find.byType(TrendPill), findsNothing);
    });
  });
}
