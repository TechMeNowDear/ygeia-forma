// Round 8 · f6: θερμίδες και στόχοι. R8-A1-1, R8-A1-2, R8-A1-3, R8-A1-4, R8-A1-6, R8-A1-7 και το κομμάτι «θερμίδες» του
// R8-A12-3 (όριο ±150 της γρήγορης απώλειας). Φανταστικοί άνθρωποι και αριθμοί (δημόσιο repo). Οι αναμενόμενες τιμές
// βγήκαν από τον κανόνα, σε αντίγραφο Python έξω από το repo (/home/claude/scratch/f6r8/check.py πάνω στο ανεξάρτητο
// αντίγραφο του #105 του R8-A1), όχι από τον κώδικα που δοκιμάζεται.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/adaptive.dart';
import 'package:ygeia_forma/adaptive_check.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/format.dart' show daysBetween;
import 'package:ygeia_forma/goals.dart';
import 'package:ygeia_forma/pages/checkin_card.dart';
import 'package:ygeia_forma/pages/goals_page.dart';
import 'package:ygeia_forma/profile.dart';
import 'package:ygeia_forma/theme.dart';

import 'sample_checkin.dart';
import 'sample_data.dart';

/// Ο φανταστικός άνθρωπος των [checkinGoals] (ίδιος με τις άλλες δοκιμές): άνδρας, 180 cm, 40 ετών ως τον Νοέμβριο και
/// 41 από τον Δεκέμβριο του 2026. Οι στόχοι (16/11, 40 ετών, 90 kg, μέτρια κίνηση): τύπος 1.830 × 1,5 = 2.745, −495 για 0,5%
/// την εβδομάδα → 2.250. Ο οδηγός τον Δεκέμβριο (41 ετών), με «Μέτρια» = 1,65 από τον γύρο 9 (R9-A1-3, FAO/WHO/UNU 2004):
/// 1.825 × 1,65 = 3.011,25 − 495 = 2.516,25 → 2.520 (πριν, με 1,5: 2.240). Οι αποθηκευμένοι στόχοι (1,5) δεν αλλάζουν.
const _p = Profile(birthYear: 1985, birthMonth: 12, sex: 'm', heightCm: 180);

final _start = DateTime(2026, 11, 16); // Δευτέρα

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

/// «Ξανά ο οδηγός» στις [now] με τους στόχους [old]: βάρος 90 kg, ίδιος σκοπός και ρυθμός. [activity]: άλλη κίνηση
/// (0 = «Λίγο»)· [doctorNo]: «Όχι» στην ερώτηση του γιατρού. Σταματά στη σύνοψη.
Future<HealthStore> _rerun(WidgetTester t, Goals old, DateTime now, {int? activity, bool doctorNo = false}) async {
  final store = HealthStore()
    ..setProfile(_p)
    ..setGoals(old);
  await _pump(t, GoalsWizard(store: store, now: now));
  await t.enterText(find.byKey(const ValueKey('wizard-kg')), '90');
  await t.pumpAndSettle();
  await _next(t); // → σκοπός
  await _next(t); // → ρυθμός
  await _next(t); // → κίνηση
  if (activity != null) {
    await t.tap(find.byKey(ValueKey('opt-act-$activity')));
    await t.pumpAndSettle();
  }
  await _next(t); // → γιατρός
  if (doctorNo) {
    await t.tap(find.byKey(const ValueKey('opt-doc-no')));
    await t.pumpAndSettle();
  }
  await _next(t); // → σύνοψη
  return store;
}

Map<DateTime, double> Function(DateTime, DateTime) _intakeOf(Map<DateTime, double> m) => (a, b) => {
      for (final e in m.entries)
        if (!e.key.isBefore(a) && !e.key.isAfter(b)) e.key: e.value,
    };

/// [eat] kcal κάθε μέρα από [from] ως και [to], εκτός από τις μέρες [skip].
Map<DateTime, double> _daily(DateTime from, DateTime to, double eat, {bool Function(DateTime)? skip}) => {
      for (var d = from; !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1))
        if (skip == null || !skip(d)) d: eat,
    };

/// Ζυγίσεις Δευτέρα, Τετάρτη, Παρασκευή από 16/11 ως [to]: 90 kg και [kgWeek] kg την εβδομάδα.
List<(DateTime, double)> _mwf(DateTime to, double kgWeek) => [
      for (var d = _start; !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1))
        if (d.weekday == 1 || d.weekday == 3 || d.weekday == 5) (d, 90 + kgWeek * daysBetween(_start, d) / 7),
    ];

// ------------------------------------------------------------------------- R8-A12-3: τα fixtures του r2_g1_test

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

/// Τα checkinGoals μετά από δύο «+150» της γρήγορης απώλειας: 2.250 → 2.400 (Παρασκευή 11/12) → 2.550 (18/12).
Goals _raisedTwice() => checkinGoals(kcalAdapt: 2550)
    .copyWith(
        fastAt: '2026-12-18',
        checkIn: '2026-12-21',
        addLog: const AdaptLog(day: '2026-12-11', tdee: 2750, before: 2250, after: 2400, applied: true, fast: true))
    .copyWith(addLog: const AdaptLog(day: '2026-12-18', tdee: 2750, before: 2400, after: 2550, applied: true, fast: true));

/// Τρως τον στόχο που ίσχυε κάθε μέρα μείον [less], 4–24/12 (μέσος όρος των στόχων: 2.385,71).
Map<DateTime, double> _ateTargets({double less = 0}) => {
      for (var d = 4; d <= 24; d++) DateTime(2026, 12, d): (d <= 11 ? 2250 : (d <= 18 ? 2400 : 2550)) - less,
    };

void main() {
  // ------------------------------------------------------------------------------------------------ R8-A1-1 / R8-A1-2
  group('R8-A1-1 / R8-A1-2: «Ξανά ο οδηγός» κρατά τη διόρθωση που ισχύει και δεν εφαρμόζει ποτέ μόνος του εκτίμηση', () {
    test('keptKcalAdapt: ίδιες απαντήσεις → ίδιος στόχος· αλλάζει μόνο όσο ο τύπος· κάτω όριο', () {
      final calc = checkinGoals().calc;
      expect(calc.tdee, closeTo(2745, 1e-9));
      expect(calc.delta, closeTo(-495, 1e-9));
      expect(calc.kcal, 2250);
      expect(keptKcalAdapt(old: null, calc: calc, male: true, age: 40, heightCm: 180), isNull);
      expect(keptKcalAdapt(old: checkinGoals().copyWith(tdeeEst: 2100), calc: calc, male: true, age: 40, heightCm: 180), isNull,
          reason: 'εκτίμηση χωρίς «Εφάρμοσε»: καμία διόρθωση σε ισχύ');
      expect(keptKcalAdapt(old: checkinGoals(kcalAdapt: 2100), calc: calc, male: true, age: 40, heightCm: 180), (kcal: 2100, floored: false));
      expect(keptKcalAdapt(old: checkinGoals(kcalAdapt: 2105), calc: calc, male: true, age: 40, heightCm: 180), (kcal: 2105, floored: false),
          reason: 'ίδιες απαντήσεις: ούτε στρογγύλεμα');
      // Λίγη κίνηση: 1.830 × 1,4 − 495 = 2.067 (τύπος 2.070), δηλαδή −183 → −180.
      final low = computeGoals(male: true, age: 40, heightCm: 180, kg: 90, aim: GoalAim.lose, rate: 0.005, activity: 1.4, doctor: true);
      expect(low.kcal, 2070);
      expect(keptKcalAdapt(old: checkinGoals(kcalAdapt: 2100), calc: low, male: true, age: 40, heightCm: 180), (kcal: 1920, floored: false));
      // Ρυθμός 0,25%: −247,5 αντί για −495, δηλαδή +247,5 → +250.
      final slow = computeGoals(male: true, age: 40, heightCm: 180, kg: 90, aim: GoalAim.lose, rate: 0.0025, activity: 1.5, doctor: true);
      expect(slow.kcal, 2500);
      expect(keptKcalAdapt(old: checkinGoals(kcalAdapt: 2100), calc: slow, male: true, age: 40, heightCm: 180), (kcal: 2350, floored: false));
      // «Ίδιο βάρος»: +495 → +500.
      final keep = computeGoals(male: true, age: 40, heightCm: 180, kg: 90, aim: GoalAim.keep, rate: 0, activity: 1.5, doctor: true);
      expect(keep.kcal, 2750);
      expect(keptKcalAdapt(old: checkinGoals(kcalAdapt: 2100), calc: keep, male: true, age: 40, heightCm: 180), (kcal: 2600, floored: false));
      // Κάτω όριο 1.500 (άνδρας): 1.690 − 180 = 1.510 μένει· 1.550 − 180 = 1.370 → 1.500.
      expect(keptKcalAdapt(old: checkinGoals(kcalAdapt: 1690), calc: low, male: true, age: 40, heightCm: 180), (kcal: 1510, floored: false));
      expect(keptKcalAdapt(old: checkinGoals(kcalAdapt: 1550), calc: low, male: true, age: 40, heightCm: 180), (kcal: 1500, floored: true));
      // Γενέθλια (41 ετών) και ύψος 182 cm: ο τύπος αλλάζει (−7,5 και +18,75), η διόρθωση από τα δεδομένα όχι.
      final older = computeGoals(male: true, age: 41, heightCm: 182, kg: 90, aim: GoalAim.lose, rate: 0.005, activity: 1.5, doctor: true);
      expect(older.kcal, 2260);
      expect(keptKcalAdapt(old: checkinGoals(kcalAdapt: 2100), calc: older, male: true, age: 41, heightCm: 182), (kcal: 2100, floored: false));
    });

    testWidgets('«Όχι τώρα» σε πρόταση −150 (εκτίμηση 2.100), ξανά ο οδηγός: μόνο ο τύπος (2.520), όχι 1.610', (t) async {
      final old = checkinGoals().copyWith(
          tdeeEst: 2100,
          checkIn: '2026-12-14',
          addLog: const AdaptLog(day: '2026-12-14', tdee: 2100, before: 2250, after: 2250, applied: false));
      final store = await _rerun(t, old, DateTime(2026, 12, 16, 9));
      // Ο τύπος με τα γενέθλια (41 ετών) και το νέο «Μέτρια» (1,65): 2.520· η εκτίμηση που δεν εφαρμόστηκε δεν μπαίνει (πριν:
      // 2.100 − 495 → 1.610).
      expect(find.text('2.520 kcal', findRichText: true), findsOneWidget);
      expect(find.byKey(const ValueKey('wizard-from-data')), findsNothing);
      expect(find.text('Ο στόχος αλλάζει από 2.250 σε 2.520 kcal.'), findsOneWidget);
      expect(find.textContaining('συνεχίζει όπως πριν'), findsOneWidget);
      await _next(t);
      final g = store.goals!;
      expect((g.kcal, g.kcalAdapt, g.tdeeEst, g.since, g.checkIn), (2520, null, 2100.0, '2026-11-16', '2026-12-14'));
    });

    testWidgets('«Εντάξει» στο «μέσα στο εύρος των ζυγίσεων» (εκτίμηση 2.600): ξανά ο οδηγός → ο τύπος 2.520 (πριν: 2.110)',
        (t) async {
      final old = checkinGoals().copyWith(
          tdeeEst: 2600,
          checkIn: '2026-12-14',
          addLog: const AdaptLog(day: '2026-12-14', tdee: 2600, before: 2250, after: 2250, applied: false));
      final store = await _rerun(t, old, DateTime(2026, 12, 16, 9));
      expect(find.text('2.520 kcal', findRichText: true), findsOneWidget);
      await _next(t);
      expect((store.goals!.kcal, store.goals!.kcalAdapt), (2520, null));
    });

    testWidgets('μετά από −150 με όριο (εκτίμηση 2.000): ξανά ο οδηγός μόνο για τον γιατρό → μένει 2.100 (πριν: 1.510)',
        (t) async {
      final old = checkinGoals(kcalAdapt: 2100).copyWith(
          tdeeEst: 2000,
          checkIn: '2026-12-14',
          addLog: const AdaptLog(day: '2026-12-14', tdee: 2000, before: 2250, after: 2100, applied: true));
      final store = await _rerun(t, old, DateTime(2026, 12, 16, 9), doctorNo: true);
      expect(find.text('2.100 kcal', findRichText: true), findsOneWidget);
      expect(find.byKey(const ValueKey('wizard-from-data')), findsOneWidget);
      expect(
          find.text('Από τα δεδομένα σου, όχι από τον τύπο: μένει η διόρθωση που εφάρμοσες στη Σήμερα (ο τύπος μόνος θα '
              'έδινε 2.520 kcal).'),
          findsOneWidget);
      // Τα γενέθλια και τα νέα επίπεδα (R9-A1-3: ίδια απάντηση «Μέτρια», 1,5 → 1,65) αλλάζουν τον τύπο (1.825 × 1,65 =
      // 3.011,25), όχι τη διόρθωση από τα δεδομένα.
      expect(find.text('καις περίπου 3.011 κατά τον τύπο · −495 για 0,45 kg την εβδομάδα'), findsOneWidget);
      expect(find.byKey(const ValueKey('wizard-change')), findsNothing);
      await _next(t);
      final g = store.goals!;
      expect((g.kcal, g.kcalAdapt, g.doctor, g.satPct, g.tdeeEst), (2100, 2100, false, 10, 2000.0));
    });

    testWidgets('μείωση από τη ζυγαριά (2.250 → 2.100), ξανά ο οδηγός μόνο για τον γιατρό: μένει, και η σελίδα το λέει',
        (t) async {
      final old = checkinGoals(kcalAdapt: 2100).copyWith(
          checkIn: '2026-12-14',
          addLog: const AdaptLog(day: '2026-12-14', tdee: 2750, before: 2250, after: 2100, applied: true, lowLog: true));
      final store = await _rerun(t, old, DateTime(2026, 12, 16, 9), doctorNo: true);
      expect(find.text('2.100 kcal', findRichText: true), findsOneWidget);
      await _next(t);
      expect((store.goals!.kcal, store.goals!.kcalAdapt, store.goals!.since), (2100, 2100, '2026-11-16'));
      // Η σελίδα «Στόχοι» μετά τον οδηγό (πριν: 2.250 και «τα δεδομένα σου δεν ζήτησαν αλλαγή»).
      expect(find.byType(GoalsPage), findsOneWidget);
      expect(find.text('Κατέβηκε από 2.250 σε 2.100 (14/12), γιατί το βάρος σου πήγαινε πιο ψηλά από τον στόχο'), findsOneWidget);
      expect(find.textContaining('δεν ζήτησαν αλλαγή'), findsNothing);
    });

    // Λίγη κίνηση στα 41 (R9-A1-3: 1,53): 1.825 × 1,53 − 495 = 2.297,25 → 2.300· σε σχέση με την ίδια απάντηση «Μέτρια»
    // στα νέα επίπεδα (1,65: 2.516,25): −219 → −220 (πριν, 1,4 έναντι 1,5: −180 → 1.920).
    testWidgets('μείωση από τη ζυγαριά, ξανά ο οδηγός με «Λίγη» κίνηση: η διόρθωση μένει, −220 του τύπου → 1.880', (t) async {
      final old = checkinGoals(kcalAdapt: 2100).copyWith(
          checkIn: '2026-12-14',
          addLog: const AdaptLog(day: '2026-12-14', tdee: 2750, before: 2250, after: 2100, applied: true, lowLog: true));
      final store = await _rerun(t, old, DateTime(2026, 12, 16, 9), activity: 0);
      expect(find.text('1.880 kcal', findRichText: true), findsOneWidget);
      expect(find.text('Ο στόχος αλλάζει από 2.100 σε 1.880 kcal.'), findsOneWidget);
      expect(find.textContaining('ο τύπος μόνος θα έδινε 2.300 kcal'), findsOneWidget);
      await _next(t);
      expect((store.goals!.kcal, store.goals!.activity), (1880, 1.53));
    });

    testWidgets('+150 της γρήγορης απώλειας (2.250 → 2.400): ξανά ο οδηγός χωρίς αλλαγές → μένει 2.400 (πριν: 2.250)', (t) async {
      final old = checkinGoals(kcalAdapt: 2400).copyWith(
          fastAt: '2026-12-11',
          addLog: const AdaptLog(day: '2026-12-11', tdee: 2750, before: 2250, after: 2400, applied: true, fast: true));
      final store = await _rerun(t, old, DateTime(2026, 12, 13, 9));
      expect(find.text('2.400 kcal', findRichText: true), findsOneWidget);
      expect(find.byKey(const ValueKey('wizard-change')), findsNothing);
      await _next(t);
      expect((store.goals!.kcal, store.goals!.kcalAdapt, store.goals!.fastAt), (2400, 2400, '2026-12-11'));
    });

    testWidgets('η σελίδα «Στόχοι»: αλλαγή από κάρτα που δεν ισχύει πια → όχι «δεν ζήτησαν αλλαγή»', (t) async {
      final s = HealthStore()
        ..setProfile(_p)
        ..setGoals(checkinGoals().copyWith(
            checkIn: '2026-12-14',
            addLog: const AdaptLog(day: '2026-12-14', tdee: 2600, before: 2250, after: 2100, applied: true)));
      await _pump(t, GoalsPage(store: s, now: DateTime(2026, 12, 15, 9)));
      expect(find.text('Από τον τύπο· η διόρθωση της 14/12 δεν ισχύει πια'), findsOneWidget);
      expect(find.textContaining('δεν ζήτησαν αλλαγή'), findsNothing);
    });
  });

  // ------------------------------------------------------------------------------------------------ R8-A1-3
  group('R8-A1-3: εκτίμηση πολύ ΨΗΛΑ → όχι «γεύματα που δεν γράφτηκαν»', () {
    test('γράφεις 3.200 και χάνεις 0,6 kg την εβδομάδα: εκτίμηση 3.860 > 140% του τύπου (3.843), «κάτι λείπει» ως είδος', () {
      final g = checkinGoals();
      final mon = DateTime(2026, 12, 14);
      final c = pendingCheckIn(
          goals: g,
          today: mon,
          weights: _mwf(mon, -0.6),
          intake: _intakeOf(_daily(_start, DateTime(2026, 12, 13), 3200)))!;
      expect((c.kind, c.status), (CheckKind.implausible, AdaptStatus.implausible));
      expect(c.est!.tdee, closeTo(3860, 0.5));
      expect(c.est!.tdee > adaptHighShare * g.calc.tdee, isTrue);
    });

    Expenditure est(double tdee) => Expenditure(
        tdee: tdee,
        meanIntake: 3200,
        slopeKgWeek: -0.6,
        intakeDays: 21,
        weighIns: 9,
        from: DateTime(2026, 11, 23),
        to: DateTime(2026, 12, 13));

    testWidgets('η κάρτα για πολύ ψηλή εκτίμηση: «κάτι δεν ταιριάζει», ποσότητες ή νερά', (t) async {
      final c = CheckIn(kind: CheckKind.implausible, goals: checkinGoals(), status: AdaptStatus.implausible, est: est(3860));
      await _pump(t, Scaffold(body: SingleChildScrollView(child: CheckInCard(check: c, store: HealthStore(), now: DateTime(2026, 12, 14, 9)))));
      expect(find.text('Έλεγχος θερμίδων: κάτι δεν ταιριάζει'), findsOneWidget);
      expect(
          find.text('Με όσα γράφτηκαν βγαίνει ότι καις 3.860\u00A0kcal, πολύ πιο ψηλά από τον τύπο (2.745). Συνήθως φταίνε '
              'ποσότητες γραμμένες μεγαλύτερες από όσο έφαγες (π.χ. μαγειρεμένο φαγητό γραμμένο σαν ωμό, ή κάτι γραμμένο δύο '
              'φορές) ή νερά που έφυγαν γρήγορα (π.χ. σε αρρώστια). Ο στόχος μένει ίδιος.'),
          findsOneWidget);
      expect(find.textContaining('δεν γράφτηκαν'), findsNothing);
      expect(find.text('Έλεγχος θερμίδων: κάτι λείπει'), findsNothing);
    });

    testWidgets('η κάρτα για πολύ χαμηλή εκτίμηση: «κάτι λείπει», γεύματα που δεν γράφτηκαν (όπως πριν)', (t) async {
      final c = CheckIn(kind: CheckKind.implausible, goals: checkinGoals(), status: AdaptStatus.implausible, est: est(1800));
      await _pump(t, Scaffold(body: SingleChildScrollView(child: CheckInCard(check: c, store: HealthStore(), now: DateTime(2026, 12, 14, 9)))));
      expect(find.text('Έλεγχος θερμίδων: κάτι λείπει'), findsOneWidget);
      expect(
          find.text('Με όσα γράφτηκαν βγαίνει ότι καις 1.800\u00A0kcal, πολύ μακριά από τον τύπο (2.745). Συνήθως φταίνε '
              'γεύματα ή σνακ που δεν γράφτηκαν. Ο στόχος μένει ίδιος.'),
          findsOneWidget);
    });
  });

  // ------------------------------------------------------------------------------------------------ R8-A1-4
  group('R8-A1-4: μετά από κενό στο φαγητό, «μαζεύω δεδομένα» και ο οδηγός λένε τη σωστή μέρα της πρώτης εκτίμησης', () {
    // Αρχή 16/11· φαγητό κάθε μέρα εκτός από 30/11–4/12 (5 μέρες: κενό)· ζυγίσεις Δε/Τε/Πα.
    bool hole(DateTime d) => !d.isBefore(DateTime(2026, 11, 30)) && !d.isAfter(DateTime(2026, 12, 4));
    final food = _daily(_start, DateTime(2027, 1, 10), 2250, skip: hole);
    final weights = _mwf(DateTime(2027, 1, 10), -0.42);
    List<(DateTime, double)> upTo(DateTime d) => [for (final w in weights) if (!w.$1.isAfter(d)) w];

    test('Δευτέρα 7/12: «μαζεύω δεδομένα» με το κενό· η εκτίμηση βγαίνει 28/12, όπως στον έλεγχο (14/12, 21/12 κενό)', () {
      final g = checkinGoals();
      final mon = DateTime(2026, 12, 7);
      final c = pendingCheckIn(goals: g, today: mon, weights: upTo(mon), intake: _intakeOf(food))!;
      expect((c.kind, c.status), (CheckKind.gathering, AdaptStatus.tooEarly));
      expect((c.gap!.from, c.gap!.to, c.gap!.restart), (DateTime(2026, 11, 30), DateTime(2026, 12, 4), DateTime(2026, 12, 5)));
      expect(estimateDayAfterGap(g, firstEstimateDay(g), c.gap), DateTime(2026, 12, 28));
      expect(
          gatheringText(c),
          'Η πρώτη εβδομάδα δεν μετρά: τότε φεύγουν κυρίως νερά, και η εκτίμηση θα έβγαινε πιο ψηλή από την αληθινή. Από 30 Νοε '
          'ως 4 Δεκ δεν γράφτηκε φαγητό που να μετρά, άρα η εκτίμηση θέλει 3 εβδομάδες από 5 Δεκ: η πρώτη βγαίνει τη Δευτέρα '
          '28 Δεκεμβρίου. Ο στόχος μένει ίδιος.');
      for (final (day, status) in [
        (DateTime(2026, 12, 14), AdaptStatus.afterGap),
        (DateTime(2026, 12, 21), AdaptStatus.afterGap),
        (DateTime(2026, 12, 28), AdaptStatus.ok),
      ]) {
        expect(pendingCheckIn(goals: g, today: day, weights: upTo(day), intake: _intakeOf(food))!.status, status, reason: '$day');
      }
    });

    test('χωρίς κενό: «την επόμενη Δευτέρα» όπως πριν· με κενό που κρατά: «3 εβδομάδες αφού ξαναρχίσει»', () {
      final g = checkinGoals();
      final mon = DateTime(2026, 12, 7);
      final full = pendingCheckIn(goals: g, today: mon, weights: upTo(mon), intake: _intakeOf(_daily(_start, mon, 2250)))!;
      expect((full.kind, full.gap), (CheckKind.gathering, null));
      expect(
          gatheringText(full),
          'Η πρώτη εβδομάδα δεν μετρά: τότε φεύγουν κυρίως νερά, και η εκτίμηση θα έβγαινε πιο ψηλή από την αληθινή. Η πρώτη '
          'εκτίμηση βγαίνει την επόμενη Δευτέρα, με 3 εβδομάδες δεδομένα. Ο στόχος μένει ίδιος.');
      final open = pendingCheckIn(
          goals: g, today: mon, weights: upTo(mon), intake: _intakeOf(_daily(_start, DateTime(2026, 11, 29), 2250)))!;
      expect((open.kind, open.gap!.from, open.gap!.restart), (CheckKind.gathering, DateTime(2026, 11, 30), null));
      expect(
          gatheringText(open),
          'Η πρώτη εβδομάδα δεν μετρά: τότε φεύγουν κυρίως νερά, και η εκτίμηση θα έβγαινε πιο ψηλή από την αληθινή. Από 30 Νοε '
          'δεν έχει γραφτεί φαγητό που να μετρά: η πρώτη εκτίμηση βγαίνει 3 εβδομάδες αφού ξαναρχίσει η καταγραφή. Ο στόχος '
          'μένει ίδιος.');
    });

    testWidgets('η κάρτα της Σήμερα στις 7/12 γράφει 28 Δεκεμβρίου, όχι «την επόμενη Δευτέρα»', (t) async {
      final mon = DateTime(2026, 12, 7);
      final c = pendingCheckIn(goals: checkinGoals(), today: mon, weights: upTo(mon), intake: _intakeOf(food))!;
      await _pump(t, Scaffold(body: SingleChildScrollView(child: CheckInCard(check: c, store: HealthStore(), now: DateTime(2026, 12, 7, 9)))));
      expect(find.text('Έλεγχος θερμίδων: μαζεύω δεδομένα'), findsOneWidget);
      expect(find.textContaining('τη Δευτέρα 28 Δεκεμβρίου'), findsOneWidget);
      expect(find.textContaining('την επόμενη Δευτέρα'), findsNothing);
    });

    testWidgets('ξανά ο οδηγός στις 8/12 (κενό 30/11–4/12): η σύνοψη λέει 28 Δεκεμβρίου, όχι 14', (t) async {
      FoodStore.shared = checkinFood(DateTime(2026, 12, 8), days: 22, skip: {4, 5, 6, 7, 8});
      addTearDown(() => FoodStore.shared = null);
      final store = await _rerun(t, checkinGoals(), DateTime(2026, 12, 8, 9));
      expect(find.textContaining('τη Δευτέρα 28 Δεκεμβρίου θα φανεί πόσες θερμίδες καις πραγματικά'), findsOneWidget);
      expect(find.textContaining('(η πρώτη εβδομάδα και το κενό στο φαγητό δεν μετράνε)'), findsOneWidget);
      expect(find.textContaining('14 Δεκεμβρίου'), findsNothing);
      await _next(t);
      expect(store.goals!.since, '2026-11-16');
    });
  });

  // ------------------------------------------------------------------------------------------------ R8-A1-6
  group('R8-A1-6: «Ζυγίσεις 8 από 6» μαζεμένες σε μία εβδομάδα → η κάρτα λέει και πόσο απλώνονται', () {
    // Ζυγίσεις κάθε μέρα 4/12–12/12 (καμία πριν)· φαγητό κάθε μέρα από 16/11.
    final ws = [for (var d = 4; d <= 12; d++) (DateTime(2026, 12, d), 90.0 - 0.05 * d)];
    final eaten = _daily(_start, DateTime(2026, 12, 13), 2250);

    test('readiness 12/12: 19 μέρες, 8 ζυγίσεις σε 7 μέρες· στις 14/12 ο έλεγχος λέει «λίγα δεδομένα» (ζυγίσεις)', () {
      final g = checkinGoals();
      final r = readiness(goals: g, today: DateTime(2026, 12, 12), weights: ws, intake: _intakeOf(eaten));
      expect((r.intakeDays, r.weighIns, r.weighSpan, r.gap), (19, 8, 7, null));
      final mon = DateTime(2026, 12, 14);
      final c = pendingCheckIn(
          goals: g, today: mon, weights: [...ws, (DateTime(2026, 12, 13), 89.3)], intake: _intakeOf(eaten))!;
      expect((c.kind, c.status, c.weighs), (CheckKind.fewData, AdaptStatus.fewWeighIns, 10));
      // Λιγότερες από 2 ζυγίσεις: άπλωμα 0.
      expect(readiness(goals: g, today: DateTime(2026, 12, 5), weights: ws, intake: _intakeOf(eaten)).weighSpan, 0);
    });

    testWidgets('η σελίδα «Στόχοι» στις 12/12: «Ζυγίσεις απλωμένες σε 7 από 14 μέρες»', (t) async {
      final at = DateTime(2026, 12, 12, 9);
      FoodStore.shared = checkinFood(at, days: 26);
      addTearDown(() => FoodStore.shared = null);
      final s = HealthStore()
        ..data = Dashboard.fromJson({
          ...sampleDashboardJson(at),
          'body': bodyJson([for (final (d, kg) in ws) (DateTime(d.year, d.month, d.day, 7, 30), kg)]),
        });
      s
        ..setProfile(_p)
        ..setGoals(checkinGoals());
      await _pump(t, GoalsPage(store: s, now: at));
      expect(find.text('8 από 6'), findsOneWidget);
      expect(find.byKey(const ValueKey('goals-adapt-span')), findsOneWidget);
      expect(find.text('Ζυγίσεις απλωμένες σε'), findsOneWidget);
      expect(find.text('7 από 14 μέρες'), findsOneWidget);
    });

    testWidgets('ζυγίσεις απλωμένες σωστά (Δε/Τε/Πα): καμία γραμμή «απλωμένες»', (t) async {
      final at = DateTime(2026, 12, 12, 9);
      FoodStore.shared = checkinFood(at, days: 26);
      addTearDown(() => FoodStore.shared = null);
      final s = HealthStore()..data = Dashboard.fromJson({...sampleDashboardJson(at), 'body': bodyJson(simWeights(at, days: 26))});
      s
        ..setProfile(_p)
        ..setGoals(checkinGoals());
      await _pump(t, GoalsPage(store: s, now: at));
      expect(find.byKey(const ValueKey('goals-adapt-span')), findsNothing);
    });
  });

  // ------------------------------------------------------------------------------------------------ R8-A1-7
  group('R8-A1-7: ο τύπος στο ιστορικό λέει με ποιο βάρος βγήκε, όχι «αρχή»', () {
    testWidgets('«Τύπος (με 88,0 kg)» για τους στόχους με 88 kg, χωρίς «αρχή»', (t) async {
      final g = Goals(
        aim: GoalAim.lose,
        rate: 0.005,
        activity: 1.5,
        doctor: true,
        since: '2026-11-16',
        kg: 88,
        age: 40,
        heightCm: 180,
        male: true,
        kcalAdapt: 2110,
        tdeeEst: 2600,
        checkIn: '2026-12-14',
        log: const [AdaptLog(day: '2026-12-14', tdee: 2600, before: 2250, after: 2110, applied: true)],
      );
      final s = HealthStore()
        ..setProfile(_p)
        ..setGoals(g);
      await _pump(t, GoalsPage(store: s, now: DateTime(2026, 12, 16, 9)));
      // 10 × 88 + 1.125 − 200 + 5 = 1.810 × 1,5 = 2.715.
      expect(find.text('Τύπος (με 88,0 kg)'), findsOneWidget);
      expect(find.text('2.715 kcal'), findsOneWidget);
      expect(find.textContaining('αρχή, 16/11'), findsNothing);
    });
  });

  // ------------------------------------------------------------------------------------------------ R8-A12-3
  group('R8-A12-3: γρήγορη απώλεια, «τρως περίπου όσο ο στόχος» = ως 150 κάτω από τους στόχους εκείνων των ημερών', () {
    CheckIn at(double less) => pendingCheckIn(
        goals: _raisedTwice(),
        today: DateTime(2026, 12, 25),
        weights: _losing(DateTime(2026, 11, 16), DateTime(2026, 12, 25), 90, 0.013),
        intake: _intakeOf(_ateTargets(less: less)))!;

    test('100 και 149 κάτω: +150 (2.550 → 2.700)· 151 κάτω: καμία πρόταση', () {
      for (final less in [100.0, 149.0]) {
        final c = at(less);
        expect((c.kind, c.proposal?.current, c.proposal?.target), (CheckKind.fast, 2550, 2700), reason: '$less');
        expect(c.fastTarget!, closeTo(2385.714, 0.001));
        expect(c.fastIntake!, closeTo(2385.714 - less, 0.001));
      }
      final c = at(151);
      expect((c.kind, c.proposal), (CheckKind.fast, null));
      expect(c.fastIntake!, closeTo(2234.714, 0.001));
    });
  });
}
