// Round 9 · f6: θερμίδες και στόχοι. R9-A1-1 («Ξανά ο οδηγός» δεν μετρά δεύτερη φορά το βάρος), R9-A1-2 = R9-A12-4 (ο
// στόχος που ίσχυε κάθε μέρα, για ΚΑΘΕ αλλαγή του στόχου: [Goals.hist]) και R9-A1-5 («−0,00 kg» στο «Πώς βγήκε»).
// Φανταστικοί άνθρωποι και αριθμοί (δημόσιο repo). Οι αναμενόμενες τιμές βγήκαν από τον γραμμένο κανόνα σε αντίγραφο Python
// έξω από το repo (/home/claude/scratch/f6r9/check.py πάνω στο ανεξάρτητο αντίγραφο του R9-A1), όχι από τον κώδικα.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/adaptive.dart';
import 'package:ygeia_forma/adaptive_check.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/goals.dart';
import 'package:ygeia_forma/history.dart' show dateKey;
import 'package:ygeia_forma/pages/checkin_card.dart';
import 'package:ygeia_forma/pages/goals_page.dart';
import 'package:ygeia_forma/pages/nutrition.dart';
import 'package:ygeia_forma/profile.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/widgets.dart' show PageHeaderScope;

import 'sample_checkin.dart';
import 'sample_food.dart';

/// Ο φανταστικός άνθρωπος των δοκιμών: άνδρας, 180 cm, γεννημένος τον Δεκέμβριο του 1985 (41 ετών τον Μάρτιο του 2027).
const _p = Profile(birthYear: 1985, birthMonth: 12, sex: 'm', heightCm: 180);

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 2600)}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: w));
  await t.pumpAndSettle();
}

Future<void> _next(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey('wizard-next')));
  await t.pumpAndSettle();
}

/// Το ιστορικό του στόχου όπως αποθηκεύεται (για σύγκριση).
List<Map<String, dynamic>> _hist(Goals g) => [for (final h in g.hist) h.toJson()];

Map<DateTime, double> Function(DateTime, DateTime) _intakeOf(Map<DateTime, double> m) => (a, b) => {
      for (final e in m.entries)
        if (!e.key.isBefore(a) && !e.key.isAfter(b)) e.key: e.value,
    };

/// [eat] kcal κάθε μέρα από [from] ως και [to].
Map<DateTime, double> _daily(DateTime from, DateTime to, double eat) => {
      for (var d = from; !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) d: eat,
    };

/// Ζυγίσεις Δευτέρα, Τετάρτη, Παρασκευή από [kg0] με απώλεια [pctWeek] του βάρους την εβδομάδα, στα 0,1 kg.
List<(DateTime, double)> _losing(DateTime from, DateTime to, double kg0, double pctWeek) {
  final out = <(DateTime, double)>[];
  var kg = kg0;
  for (var d = from; !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
    if (d.weekday == 1 || d.weekday == 3 || d.weekday == 5) out.add((d, (kg * 10).round() / 10));
    kg -= pctWeek * kg / 7;
  }
  return out;
}

// ------------------------------------------------------------------------------------------------------------ R9-A1-1

/// Στόχοι από 16/11/2026 με 82 kg (40 ετών, 180 cm, −0,5%, μέτρια κίνηση)· ο εβδομαδιαίος έλεγχος της 1/3/2027, με 76 kg
/// στη ζυγαριά, έφερε τον στόχο από τα δεδομένα στις 2.010 («Εφάρμοσε»: 2.160 → 2.010).
Goals _old82() => Goals(
      aim: GoalAim.lose,
      rate: 0.005,
      activity: 1.5,
      doctor: true,
      since: '2026-11-16',
      kg: 82,
      age: 40,
      heightCm: 180,
      male: true,
      kcalAdapt: 2010,
      tdeeEst: 2420,
      checkIn: '2027-03-01',
      log: const [AdaptLog(day: '2027-03-01', tdee: 2420, before: 2160, after: 2010, applied: true)],
    );

/// «Ξανά ο οδηγός» την Τετάρτη 3/3/2027 με 76 kg, ίδιος σκοπός και ρυθμός· [activity]: άλλη κίνηση (0 = «Λίγο»).
/// Σταματά στη σύνοψη.
Future<HealthStore> _rerun76(WidgetTester t, {int? activity}) async {
  final store = HealthStore()
    ..setProfile(_p)
    ..setGoals(_old82());
  await _pump(t, GoalsWizard(store: store, now: DateTime(2027, 3, 3, 9)));
  await t.enterText(find.byKey(const ValueKey('wizard-kg')), '76');
  await t.pumpAndSettle();
  await _next(t); // → σκοπός
  await _next(t); // → ρυθμός
  await _next(t); // → κίνηση
  if (activity != null) {
    await t.tap(find.byKey(ValueKey('opt-act-$activity')));
    await t.pumpAndSettle();
  }
  await _next(t); // → γιατρός (το «Ναι» είναι ήδη επιλεγμένο)
  await _next(t); // → σύνοψη
  return store;
}

void main() {
  group('R9-A1-1: «Ξανά ο οδηγός» δεν μετακινεί τη διόρθωση για βάρος που οι εκτιμήσεις μέτρησαν ήδη', () {
    test('keptKcalAdapt: ο παλιός και ο νέος τύπος με το ίδιο (τωρινό) βάρος· αλλάζουν μόνο οι απαντήσεις', () {
      // 76 kg, 41 ετών, 180 cm: Mifflin 760 + 1.125 − 205 + 5 = 1.685· −0,5% = −418.
      GoalCalc at76(double activity, double rate) =>
          computeGoals(male: true, age: 41, heightCm: 180, kg: 76, aim: GoalAim.lose, rate: rate, activity: activity, doctor: true);
      // Οι παλιοί στόχοι έχουν το παλιό «Μέτρια» (1,5): ο οδηγός το διαβάζει ως την ίδια απάντηση, 1,65 (R9-A1-3).
      expect(currentActivityLevel(_old82().activity), 1.65);
      ({int kcal, bool floored})? kept(GoalCalc calc) =>
          keptKcalAdapt(old: _old82(), calc: calc, male: true, age: 41, heightCm: 180, oldActivity: 1.65);
      final same = at76(1.65, 0.005);
      expect(same.kg, 76);
      expect(same.bmr, closeTo(1685, 1e-9));
      // 1.685 × 1,65 = 2.780,25 − 418 = 2.362,25 → 2.360.
      expect(same.kcal, 2360);
      // Ίδιες απαντήσεις: 2.010 (με το βάρος του παλιού οδηγού: −60 για τα 6 κιλά, δεύτερη φορά).
      expect(kept(same), (kcal: 2010, floored: false));
      // «Λίγο»: 1.685 × (1,53 − 1,65) = −202,2 → −200 → 1.810.
      expect(kept(at76(1.53, 0.005)), (kcal: 1810, floored: false));
      // «Πολύ»: 1.685 × (1,76 − 1,65) = +185,35 → +190 → 2.200.
      expect(kept(at76(1.76, 0.005)), (kcal: 2200, floored: false));
      // Ρυθμός 0,25% με 76 kg: −209 αντί για −418, δηλαδή +209 → +210 → 2.220.
      expect(kept(at76(1.65, 0.0025)), (kcal: 2220, floored: false));
    });

    testWidgets('ίδιες απαντήσεις με 76 kg: μένει 2.010, καμία «αλλαγή στόχου»', (t) async {
      final store = await _rerun76(t);
      expect(find.text('2.010 kcal', findRichText: true), findsOneWidget);
      expect(find.byKey(const ValueKey('wizard-from-data')), findsOneWidget);
      expect(find.textContaining('ο τύπος μόνος θα έδινε 2.360 kcal'), findsOneWidget);
      expect(find.byKey(const ValueKey('wizard-change')), findsNothing);
      await _next(t);
      final g = store.goals!;
      expect((g.kcal, g.kcalAdapt, g.kg), (2010, 2010, 76.0));
      expect(g.hist, isEmpty, reason: 'ο στόχος δεν άλλαξε');
    });

    testWidgets('«Λίγο» με 76 kg: 1.810· η αλλαγή γράφεται με τη μέρα της (R9-A1-2)', (t) async {
      final store = await _rerun76(t, activity: 0);
      expect(find.text('1.810 kcal', findRichText: true), findsOneWidget);
      expect(find.text('Ο στόχος αλλάζει από 2.010 σε 1.810 kcal.'), findsOneWidget);
      await _next(t);
      final g = store.goals!;
      expect((g.kcal, g.kcalAdapt, g.activity), (1810, 1810, 1.53));
      // Πρώτη γραμμή: η αλλαγή από κάρτα του παλιού ιστορικού· μετά, του οδηγού.
      expect(_hist(g), [
        {'d': '2027-03-01', 'k0': 2160, 'k1': 2010},
        {'d': '2027-03-03', 'k0': 2010, 'k1': 1810},
      ]);
      expect(targetOn(g, DateTime(2027, 2, 28)), 2160);
      expect(targetOn(g, DateTime(2027, 3, 1)), 2160, reason: 'η μέρα της αλλαγής μετρά με τον παλιό στόχο');
      expect(targetOn(g, DateTime(2027, 3, 2)), 2010);
      expect(targetOn(g, DateTime(2027, 3, 3, 21)), 2010);
      expect(targetOn(g, DateTime(2027, 3, 4)), 1810);
      expect(lastChangeDay(g), DateTime(2027, 3, 1), reason: 'ο οδηγός δεν είναι «αλλαγή από κάρτα» (κανένα κράτημα 4 ημερών)');
    });
  });

  // ------------------------------------------------------------------------------------------------------------ R9-A1-3
  group('R9-A1-3: επίπεδα κίνησης από τα παραδείγματα της FAO/WHO/UNU 2004 (1,53 / 1,65 / 1,76)', () {
    test('τιμές, απαντήσεις (και των παλιών 1,4 / 1,5 / 1,7), ονόματα, πώς γράφονται', () {
      expect(activityLevels, [1.53, 1.65, 1.76]);
      expect([for (final p in [1.53, 1.65, 1.76, 1.4, 1.5, 1.7, 1.6]) activityAnswer(p)], [0, 1, 2, 0, 1, 2, null]);
      expect([for (final p in [1.4, 1.5, 1.7, 1.53, 1.6, 1.8]) currentActivityLevel(p)], [1.53, 1.65, 1.76, 1.53, 1.6, 1.8]);
      expect([for (final p in [1.53, 1.65, 1.76, 1.4, 1.5, 1.7, 1.58, 1.6, 1.71]) activityText(p)], [
        'Λίγη κίνηση',
        'Μέτρια κίνηση',
        'Πολλή κίνηση',
        'Λίγη κίνηση',
        'Μέτρια κίνηση',
        'Πολλή κίνηση',
        'Λίγη κίνηση',
        'Μέτρια κίνηση',
        'Πολλή κίνηση',
      ]);
      expect([for (final p in [1.53, 1.65, 1.76, 1.5, 1.4]) palText(p)], ['1,53', '1,65', '1,76', '1,5', '1,4']);
      // Άνδρας 40 ετών, 180 cm, 90 kg, −0,5%: Mifflin 1.830· −495.
      int target(double pal) =>
          computeGoals(male: true, age: 40, heightCm: 180, kg: 90, aim: GoalAim.lose, rate: 0.005, activity: pal, doctor: true).kcal;
      // 1.830 × 1,53 = 2.799,9 − 495 → 2.300· × 1,65 = 3.019,5 − 495 → 2.520· × 1,76 = 3.220,8 − 495 → 2.730.
      expect([for (final p in activityLevels) target(p)], [2300, 2520, 2730]);
      expect(target(1.5), 2250, reason: 'αποθηκευμένοι στόχοι με το παλιό 1,5 δεν αλλάζουν σιωπηλά');
    });

    testWidgets('«Πώς υπολογίστηκε»: «× 1,65» (όχι «× 1,6» ή «× 1,7»)· παλιοί στόχοι «× 1,5», ίδια απάντηση', (t) async {
      Goals at(double pal) => Goals(
          aim: GoalAim.lose, rate: 0.005, activity: pal, doctor: true, since: '2026-11-16', kg: 90, age: 40, heightCm: 180, male: true);
      for (final (pal, shown, tdee) in [(1.65, '1,65', '3.020 kcal'), (1.5, '1,5', '2.745 kcal')]) {
        final s = HealthStore()
          ..setProfile(_p)
          ..setGoals(at(pal));
        await _pump(t, GoalsPage(key: ValueKey(pal), store: s, now: DateTime(2026, 11, 20, 9)));
        await t.tap(find.byKey(const ValueKey('goals-how')));
        await t.pumpAndSettle();
        expect(find.text('2 ·\u00A0Με την κίνησή σου (× $shown)'), findsOneWidget);
        expect(find.text(tdee), findsOneWidget);
        expect(find.textContaining('«Μέτρια κίνηση»'), findsOneWidget);
        Navigator.of(t.element(find.text('Πώς υπολογίστηκαν οι θερμίδες'))).pop();
        await t.pumpAndSettle();
      }
    });
  });

  // ---------------------------------------------------------------------------------------------- R9-A1-2 / R9-A12-4
  group('R9-A1-2 / R9-A12-4: κάθε αλλαγή του στόχου γράφεται· οι περασμένες μέρες κρίνονται με τον στόχο τους', () {
    test('δικός σου στόχος 2.000 την Τετ 25/11: η Δευ 23/11 και η ίδια η 25/11 με 2.250, η 26/11 με 2.000', () {
      final g = checkinGoals(kcalSet: 2000).recordChangeFrom(checkinGoals(), DateTime(2026, 11, 25, 20));
      expect(_hist(g), [
        {'d': '2026-11-25', 'k0': 2250, 'k1': 2000},
      ]);
      expect(targetOn(g, DateTime(2026, 11, 23)), 2250, reason: 'πριν: 2.000, ο τωρινός');
      expect(targetOn(g, DateTime(2026, 11, 25)), 2250);
      expect(targetOn(g, DateTime(2026, 11, 26)), 2000);
      expect(meanTargetOn(g, [DateTime(2026, 11, 24), DateTime(2026, 11, 26)]), 2125);
      expect(lastChangeDay(g), isNull, reason: 'όχι AdaptLog.applied: ο εβδομαδιαίος έλεγχος δεν κρατιέται 4 μέρες');
      expect(g.log, isEmpty);
    });

    test('ίδια μέρα: μία γραμμή (και πίσω στον ίδιο στόχο)· άλλη μέρα: δεύτερη γραμμή', () {
      final base = checkinGoals();
      final own = checkinGoals(kcalSet: 2000).recordChangeFrom(base, DateTime(2026, 11, 25, 9));
      final lower = own.copyWith(kcalSet: 1900).recordChangeFrom(own, DateTime(2026, 11, 25, 21));
      expect(_hist(lower), [
        {'d': '2026-11-25', 'k0': 2250, 'k1': 1900},
      ]);
      // Πίσω στο 2.250 την ίδια μέρα: η γραμμή μένει (2.250 → 2.250), ώστε το ιστορικό να μη διαβαστεί ποτέ σαν στόχοι
      // παλιότερης έκδοσης· ο στόχος κάθε μέρας είναι ο σωστός.
      final reset = own.copyWith(clearKcal: true).recordChangeFrom(own, DateTime(2026, 11, 25, 22));
      expect(reset.kcal, 2250);
      expect(_hist(reset), [
        {'d': '2026-11-25', 'k0': 2250, 'k1': 2250},
      ]);
      expect(targetOn(reset, DateTime(2026, 11, 24)), 2250);
      expect(targetOn(reset, DateTime(2026, 11, 26)), 2250);
      final nextDay = own.copyWith(clearKcal: true).recordChangeFrom(own, DateTime(2026, 11, 26, 8));
      expect(_hist(nextDay), [
        {'d': '2026-11-25', 'k0': 2250, 'k1': 2000},
        {'d': '2026-11-26', 'k0': 2000, 'k1': 2250},
      ]);
      expect(targetOn(nextDay, DateTime(2026, 11, 26)), 2000);
      expect(targetOn(nextDay, DateTime(2026, 11, 27)), 2250);
      // Χωρίς παλιούς στόχους ή χωρίς αλλαγή: τίποτα νέο.
      expect(base.recordChangeFrom(null, DateTime(2026, 11, 16)).hist, isEmpty);
      expect(own.copyWith(nutsG: 20).recordChangeFrom(own, DateTime(2026, 11, 27)).hist.length, 1);
    });

    test('στόχοι παλιότερης έκδοσης (χωρίς ιστορικό): πρώτα οι αλλαγές από κάρτα, μετά η νέα· ως τότε όπως πριν', () {
      final legacy = checkinGoals(kcalAdapt: 2100).copyWith(
          checkIn: '2026-12-21',
          addLog: const AdaptLog(day: '2026-12-14', tdee: 2600, before: 2250, after: 2100, applied: true))
          .copyWith(addLog: const AdaptLog(day: '2026-12-21', tdee: 2620, before: 2100, after: 2100, applied: false));
      expect(legacy.hist, isEmpty);
      expect(targetOn(legacy, DateTime(2026, 12, 13)), 2250, reason: 'όπως πριν: από το log');
      expect(targetOn(legacy, DateTime(2026, 12, 15)), 2100);
      final own = legacy.copyWith(kcalSet: 2000).recordChangeFrom(legacy, DateTime(2026, 12, 23));
      expect(_hist(own), [
        {'d': '2026-12-14', 'k0': 2250, 'k1': 2100},
        {'d': '2026-12-23', 'k0': 2100, 'k1': 2000},
      ]);
      expect(targetOn(own, DateTime(2026, 12, 13)), 2250);
      expect(targetOn(own, DateTime(2026, 12, 22)), 2100);
      expect(targetOn(own, DateTime(2026, 12, 24)), 2000);
    });

    test('«Εφάρμοσε» γράφεται και στο ιστορικό του στόχου', () {
      final g0 = checkinGoals(kcalSet: 2000).recordChangeFrom(checkinGoals(), DateTime(2026, 12, 1));
      const p = AdaptProposal(current: 2000, target: 2150, est: null, fastLoss: true, floored: false);
      final g1 = applyCheckIn(CheckIn(kind: CheckKind.fast, goals: g0, proposal: p, kgNow: 88), DateTime(2026, 12, 11, 18));
      expect((g1.kcal, g1.kcalSet, g1.kcalAdapt), (2150, null, 2150));
      expect(_hist(g1), [
        {'d': '2026-12-01', 'k0': 2250, 'k1': 2000},
        {'d': '2026-12-11', 'k0': 2000, 'k1': 2150},
      ]);
      expect(targetOn(g1, DateTime(2026, 11, 30)), 2250);
      expect(targetOn(g1, DateTime(2026, 12, 11)), 2000);
      expect(targetOn(g1, DateTime(2026, 12, 12)), 2150);
      expect(lastChangeDay(g1), DateTime(2026, 12, 11));
    });

    test('το πολύ 400 γραμμές: φεύγουν οι παλιότερες', () {
      final start = DateTime(2020, 1, 1);
      final full = [
        for (var i = 0; i < targetHistMax; i++)
          TargetChange(day: dateKey(DateTime(start.year, start.month, start.day + i)), before: 2000 + i % 2 * 100, after: 2100 - i % 2 * 100),
      ];
      final out = addTargetChange(full, const [], const TargetChange(day: '2026-01-01', before: 2000, after: 1900));
      expect(out.length, targetHistMax);
      expect(out.first.day, dateKey(DateTime(2020, 1, 2)));
      expect(out.last.toJson(), {'d': '2026-01-01', 'k0': 2000, 'k1': 1900});
    });

    test('JSON: προσθετικό κλειδί «th»· παλιοί στόχοι χωρίς αυτό· άκυρες γραμμές δεν διαβάζονται', () {
      expect(checkinGoals().toJson().containsKey('th'), isFalse, reason: 'χωρίς αλλαγές, το αρχείο μένει όπως πριν');
      final g = checkinGoals(kcalSet: 2000).recordChangeFrom(checkinGoals(), DateTime(2026, 11, 25));
      final j = g.toJson();
      expect(j['th'], [
        {'d': '2026-11-25', 'k0': 2250, 'k1': 2000},
      ]);
      expect(_hist(Goals.fromJson(j)!), j['th']);
      expect(Goals.fromJson(checkinGoals().toJson())!.hist, isEmpty);
      final bad = Map<String, dynamic>.from(j)
        ..['th'] = [
          {'d': '2026-11-25', 'k0': 2250, 'k1': 2000},
          {'d': '25/11', 'k0': 2250, 'k1': 2000},
          'x',
          {'d': '2026-11-26', 'k0': 2000, 'k1': double.infinity},
          {'d': '2026-11-27', 'k0': 2000, 'k1': 400},
          {'d': '2026-11-28', 'k0': 2000},
        ];
      expect(_hist(Goals.fromJson(bad)!), [
        {'d': '2026-11-25', 'k0': 2250, 'k1': 2000},
      ]);
      final many = Map<String, dynamic>.from(j)
        ..['th'] = [
          for (var i = 0; i <= targetHistMax; i++)
            {'d': dateKey(DateTime(2020, 1, 1 + i)), 'k0': 2000, 'k1': 2100},
        ];
      final kept = Goals.fromJson(many)!.hist;
      expect((kept.length, kept.first.day), (targetHistMax, '2020-01-02'), reason: 'μένουν οι πιο πρόσφατες');
    });

    test('γρήγορη απώλεια μετά από δικό σου στόχο: έτρωγες τον στόχο σου → +150, όχι «τρως πολύ λίγο»', () {
      // Τρως 2.250 (τον στόχο) κάθε μέρα και χάνεις 1,3% την εβδομάδα· την Πέμ 3/12 γράφεις δικό σου στόχο 2.450.
      final weights = _losing(DateTime(2026, 11, 16), DateTime(2026, 12, 4), 90, 0.013);
      final intake = _intakeOf(_daily(DateTime(2026, 11, 16), DateTime(2026, 12, 3), 2250));
      final own = checkinGoals(kcalSet: 2450).recordChangeFrom(checkinGoals(), DateTime(2026, 12, 3, 20));
      final c = pendingCheckIn(goals: own, today: DateTime(2026, 12, 4), weights: weights, intake: intake)!;
      expect((c.kind, c.proposal?.current, c.proposal?.target), (CheckKind.fast, 2450, 2600));
      expect(c.fastTarget!, closeTo(2250, 1e-9), reason: 'οι 11 μέρες 23/11–3/12 είχαν στόχο 2.250');
      expect(c.fastIntake!, closeTo(2250, 1e-9));
      expect(c.fastIntakeDays, 11);
      // Οι ίδιοι στόχοι χωρίς την αλλαγή γραμμένη (παλιότερη έκδοση): όπως πριν, με τον τωρινό στόχο.
      final legacy = pendingCheckIn(goals: checkinGoals(kcalSet: 2450), today: DateTime(2026, 12, 4), weights: weights, intake: intake)!;
      expect((legacy.kind, legacy.proposal), (CheckKind.fast, null));
      expect(legacy.fastTarget!, closeTo(2450, 1e-9));
    });

    testWidgets('σελίδα «Στόχοι»: «Θερμίδες τη μέρα» γράφει την αλλαγή· «Από τον υπολογισμό» την ίδια μέρα: μία γραμμή', (t) async {
      final store = HealthStore()
        ..setProfile(_p)
        ..setGoals(checkinGoals());
      await _pump(t, GoalsPage(store: store, now: DateTime(2026, 11, 25, 20)));
      await t.tap(find.byKey(const ValueKey('goals-kcal')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('number-field')), '2000');
      await t.tap(find.byKey(const ValueKey('number-ok')));
      await t.pumpAndSettle();
      expect((store.goals!.kcal, store.goals!.kcalSet), (2000, 2000));
      expect(_hist(store.goals!), [
        {'d': '2026-11-25', 'k0': 2250, 'k1': 2000},
      ]);
      expect(targetOn(store.goals!, DateTime(2026, 11, 23)), 2250);
      await t.tap(find.byKey(const ValueKey('goals-kcal')));
      await t.pumpAndSettle();
      await t.tap(find.text('Από τον υπολογισμό (2.250)'));
      await t.pumpAndSettle();
      expect((store.goals!.kcal, store.goals!.kcalSet), (2250, null));
      expect(_hist(store.goals!), [
        {'d': '2026-11-25', 'k0': 2250, 'k1': 2250},
      ], reason: 'ίδια μέρα: μία γραμμή, από τον στόχο της αρχής της μέρας στον τελευταίο');
    });

    testWidgets('«Υπολόγισε ξανά» (ύψος 178 → 180 cm) γράφει την αλλαγή 2.230 → 2.250', (t) async {
      final store = HealthStore()
        ..setProfile(_p)
        ..setGoals(Goals(
            aim: GoalAim.lose,
            rate: 0.005,
            activity: 1.5,
            doctor: true,
            since: '2026-11-16',
            kg: 90,
            age: 40,
            heightCm: 178,
            male: true));
      // 900 + 1.112,5 − 200 + 5 = 1.817,5 × 1,5 = 2.726,25 − 495 → 2.230.
      expect(store.goals!.kcal, 2230);
      await _pump(t, GoalsPage(store: store, now: DateTime(2026, 11, 25, 9)));
      await t.ensureVisible(find.byKey(const ValueKey('goals-recompute')));
      await t.tap(find.byKey(const ValueKey('goals-recompute')));
      await t.pumpAndSettle();
      expect((store.goals!.heightCm, store.goals!.kcal), (180.0, 2250));
      expect(_hist(store.goals!), [
        {'d': '2026-11-25', 'k0': 2230, 'k1': 2250},
      ]);
      expect(targetOn(store.goals!, DateTime(2026, 11, 24)), 2230);
    });

    group('Διατροφή: μέρα που πέρασε με τον στόχο που ίσχυε τότε (η σύνδεση της σελίδας)', () {
      final food = Food(
        id: 'R9F6',
        name: 'Τρόφιμο R9F6',
        cat: 'Άλλα',
        source: 'CIQUAL 2025',
        n: Nutrients({
          Nk.kcal: const NValue(2100),
          Nk.protein: const NValue(120),
          Nk.carbs: const NValue(220),
          Nk.fat: const NValue(70),
          Nk.satFat: const NValue(12),
          Nk.fiber: const NValue(30),
          Nk.sugars: const NValue(40),
          Nk.salt: const NValue(4),
        }),
      );

      /// Η Διατροφή την [now], ανοιγμένη στη μέρα [day] με 2.100 kcal (100 g του τροφίμου).
      Future<void> page(WidgetTester t, Goals goals, DateTime day, DateTime now) async {
        final entry = LogEntry(
            id: 'r9f6-${dateKey(day)}', day: dateKey(day), meal: Meal.lunch, food: food, grams: 100, time: DateTime(day.year, day.month, day.day, 13));
        final store = FoodStore.preloaded(foods: basicFoods(), entries: [entry], now: day);
        final health = HealthStore()
          ..setProfile(_p)
          ..setGoals(goals);
        await _pump(
            t,
            Scaffold(
                key: ValueKey('${dateKey(day)}-${goals.kcal}'),
                body: PageHeaderScope(
                    header: const SizedBox.shrink(),
                    child: FoodTheme(child: NutritionPage(food: store, health: health, now: now)))),
            size: const Size(400, 2400));
      }

      Finder inCard(Finder f) => find.descendant(of: find.byKey(const ValueKey('nutrition-goals')), matching: f);

      testWidgets('δικός σου στόχος 2.000 από 25/11: η Δευ 23/11 (2.100 kcal) είναι «Κάτω από τον στόχο» 2.250', (t) async {
        final g = checkinGoals(kcalSet: 2000).recordChangeFrom(checkinGoals(), DateTime(2026, 11, 25, 20));
        await page(t, g, DateTime(2026, 11, 23), DateTime(2026, 11, 26, 12));
        expect(inCard(find.text('Κάτω από τον στόχο')), findsOneWidget);
        expect(inCard(find.text('Πάνω από τον στόχο')), findsNothing, reason: 'πριν: «Πάνω από τον στόχο 100 · στόχος 2.000»');
        expect(inCard(find.text('στόχος 2.250')), findsOneWidget);
        // 2.250 × 0,25 / 9 = 62,5 → 63· 2.250 × 0,35 / 9 = 87,5 → 88.
        expect(inCard(find.text('70 g / 63–88 g')), findsOneWidget);
        // Η Πέμ 26/11 (μετά την αλλαγή) με 2.000.
        await page(t, g, DateTime(2026, 11, 26), DateTime(2026, 11, 27, 12));
        expect(inCard(find.text('Πάνω από τον στόχο')), findsOneWidget);
        expect(inCard(find.text('στόχος 2.000')), findsOneWidget);
      });

      testWidgets('«Εφάρμοσε» 14/12 (2.160 → 2.010): η Κυρ 13/12 στη Διατροφή με στόχο 2.160', (t) async {
        final g = Goals(
          aim: GoalAim.lose,
          rate: 0.005,
          activity: 1.5,
          doctor: true,
          since: '2026-11-16',
          kg: 90,
          age: 40,
          heightCm: 180,
          male: true,
          kcalAdapt: 2010,
          log: const [AdaptLog(day: '2026-12-14', tdee: 2400, before: 2160, after: 2010, applied: true)],
        );
        await page(t, g, DateTime(2026, 12, 13), DateTime(2026, 12, 16, 12));
        expect(inCard(find.text('στόχος 2.160')), findsOneWidget);
        expect(inCard(find.text('Κάτω από τον στόχο')), findsOneWidget);
        expect(inCard(find.text('70 g / 60–84 g')), findsOneWidget);
      });
    });
  });

  // ------------------------------------------------------------------------------------------------------------ R9-A1-5
  group('R9-A1-5: «Πώς βγήκε» χωρίς «−0,00 kg»', () {
    Future<void> how(WidgetTester t, double slope) async {
      final e = Expenditure(
          tdee: 2745,
          meanIntake: 2745,
          slopeKgWeek: slope,
          intakeDays: 21,
          weighIns: 9,
          from: DateTime(2026, 12, 14),
          to: DateTime(2027, 1, 3),
          seKcal: 40);
      final k = CheckIn(
          kind: CheckKind.same,
          goals: checkinGoals(),
          status: AdaptStatus.ok,
          est: e,
          proposal: AdaptProposal(current: 2250, target: 2250, est: e, fastLoss: false, floored: false, withinNoise: true),
          kgNow: 88);
      await _pump(
          t,
          Scaffold(
              key: ValueKey(slope),
              body: Builder(
                  builder: (ctx) =>
                      Center(child: TextButton(onPressed: () => showHowAdapted(ctx, k), child: const Text('άνοιξε'))))));
      await t.tap(find.text('άνοιξε'));
      await t.pumpAndSettle();
    }

    for (final (slope, shown) in [(-0.004, '0 kg'), (0.004, '0 kg'), (-0.25, '−0,25 kg'), (0.3, '+0,30 kg')]) {
      testWidgets('$slope kg την εβδομάδα → «$shown»', (t) async {
        await how(t, slope);
        expect(find.text('2 ·\u00A0Αλλαγή βάρους την εβδομάδα'), findsOneWidget);
        expect(find.text(shown), findsOneWidget);
        expect(find.text('−0,00 kg'), findsNothing);
        expect(find.text('+0,00 kg'), findsNothing);
        expect(find.text('0,00 kg'), findsNothing);
      });
    }
  });
}
