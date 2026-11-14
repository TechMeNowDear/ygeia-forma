// Round 7 · f6: θερμίδες και στόχοι. R7-A1-1/2/3/4, R7-U2-10/11/12/16/18, R7-A12-1/2/3/4 και το κομμάτι «θερμίδες» του
// R7-A12-9 (αλλαγή ώρας 25/10 και 28/3, 29/2/2028, αλλαγή χρόνου). Φανταστικοί άνθρωποι και αριθμοί (δημόσιο repo).
// Οι αναμενόμενες τιμές βγήκαν από τον κανόνα, σε αντίγραφο Python έξω από το repo (/home/claude/scratch/f6/testvals*.py
// πάνω στο ανεξάρτητο αντίγραφο του #104 του R7-A1), όχι από τον κώδικα που δοκιμάζεται.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/adaptive.dart';
import 'package:ygeia_forma/adaptive_check.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/food/chol.dart' show weekStart;
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/format.dart' show daysBetween;
import 'package:ygeia_forma/goals.dart';
import 'package:ygeia_forma/pages/checkin_card.dart';
import 'package:ygeia_forma/pages/goals_page.dart';
import 'package:ygeia_forma/profile.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/waist.dart' show isDayKey;

import 'sample_checkin.dart';
import 'sample_data.dart';

/// Φανταστικός άνθρωπος Γ: άνδρας 45 ετών (γεννημένος 1/1981), 176 cm.
const _p = Profile(birthYear: 1981, birthMonth: 1, sex: 'm', heightCm: 176);

/// Ο άνθρωπος των [checkinGoals]: άνδρας 40 ετών, 180 cm.
const _p90 = Profile(birthYear: 1985, birthMonth: 12, sex: 'm', heightCm: 180);

final _start = DateTime(2026, 11, 16); // Δευτέρα
final _mon = DateTime(2026, 12, 14); // Δευτέρα, 28η μέρα: πρώτη μέρα με εκτίμηση

/// Στόχοι του Γ από 16/11: 96 kg, μέτρια κίνηση. Τύπος 10·96 + 6,25·176 − 5·45 + 5 = 1.840 × 1,5 = 2.760 kcal· στόχος
/// 2.760 − 96·0,5%·7.700/7 (528) = 2.232 → 2.230. Η εκτίμηση γίνεται δεκτή από 70% του τύπου: 1.932.
Goals _lg({GoalAim aim = GoalAim.lose, double rate = 0.005, int? kcalAdapt, int? kcalSet, String? fastAt, AdaptLog? addLog}) {
  final g = Goals(
    aim: aim,
    rate: aim == GoalAim.keep ? 0 : rate,
    activity: 1.5,
    doctor: false,
    since: '2026-11-16',
    kg: 96,
    age: 45,
    heightCm: 176,
    male: true,
    kcalAdapt: kcalAdapt,
    kcalSet: kcalSet,
    fastAt: fastAt,
  );
  return addLog == null ? g : g.copyWith(addLog: addLog);
}

bool _mwf(DateTime d) => d.weekday == DateTime.monday || d.weekday == DateTime.wednesday || d.weekday == DateTime.friday;

/// Από 16/11 ως 13/12 γράφονται [eat] kcal κάθε μέρα. Ζυγίσεις Δε/Τε/Πα 16/11–14/12: 96 + [slope] kg/εβδ., και
/// ±[noise] εναλλάξ (η πρώτη +).
({Map<DateTime, double> intake, List<(DateTime, double)> weights}) _world(double eat, double slope, {double noise = 0}) {
  final intake = <DateTime, double>{};
  final weights = <(DateTime, double)>[];
  var i = 0;
  for (var d = _start; !d.isAfter(_mon); d = DateTime(d.year, d.month, d.day + 1)) {
    if (d.isBefore(_mon)) intake[d] = eat;
    if (_mwf(d)) {
      weights.add((d, 96.0 + slope * daysBetween(_start, d) / 7 + (i.isEven ? noise : -noise)));
      i++;
    }
  }
  return (intake: intake, weights: weights);
}

Map<DateTime, double> Function(DateTime, DateTime) _intakeOf(Map<DateTime, double> m) => (a, b) => {
      for (final e in m.entries)
        if (!e.key.isBefore(a) && !e.key.isAfter(b)) e.key: e.value,
    };

CheckIn _at(Goals g, ({Map<DateTime, double> intake, List<(DateTime, double)> weights}) w, {DateTime? today}) =>
    pendingCheckIn(goals: g, today: today ?? _mon, weights: w.weights, intake: _intakeOf(w.intake))!;

/// Ζυγίσεις Δε/Τε/Πα από [from] ως [to] με βάρος [kg] (μέρες από την [from]).
List<(DateTime, double)> _weighs(DateTime from, DateTime to, double Function(int day, int i) kg) {
  final out = <(DateTime, double)>[];
  var i = 0;
  for (var d = from; !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
    if (_mwf(d)) out.add((d, kg(daysBetween(from, d), i++)));
  }
  return out;
}

/// [eat] kcal κάθε μέρα από [from] ως και [to].
Map<DateTime, double> _daily(DateTime from, DateTime to, double eat) => {
      for (var d = from; !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) d: eat,
    };

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

const _lowText = 'Τις 3 τελευταίες εβδομάδες το βάρος σου ανέβαινε 0,30\u00A0kg την εβδομάδα, ενώ ο στόχος σου είναι να πέφτει '
    '0,48\u00A0kg την εβδομάδα. Με όσα γράφτηκαν στο ημερολόγιο, η ζυγαριά θα έπρεπε να δείχνει λιγότερα: μάλλον λείπουν '
    'κάποια γεύματα, σνακ ή ποτά, κάτι που συμβαίνει σχεδόν σε όλους. Ο στόχος κατεβαίνει με βάση τη ζυγαριά.';

void main() {
  // ------------------------------------------------------------------------------------------------ R7-A1-1
  group('R7-A1-1: λίγη καταγραφή, βάρος πιο ψηλά από τον ρυθμό → ο στόχος κατεβαίνει από τη ζυγαριά', () {
    test('γράφει τον στόχο (2.230), το βάρος ανεβαίνει 0,30 kg/εβδ.: πρόταση 2.080, όχι «κάτι λείπει»', () {
      final c = _at(_lg(), _world(2230, 0.30, noise: 0.15));
      expect((c.kind, c.lowLog, c.status), (CheckKind.proposal, true, AdaptStatus.implausible));
      expect((c.proposal!.current, c.proposal!.target, c.proposal!.floored), (2230, 2080, false));
      // 2.230 − 0,30 × 7.700 ÷ 7 = 1.900 < 1.932 (70% του τύπου): ο παλιός κανόνας έλεγε μόνο «κάτι λείπει».
      expect(c.est!.tdee, closeTo(1900, 0.01));
      expect(c.est!.tdee, lessThan(adaptLowShare * 2760));
      expect(c.est!.slopeKgWeek, closeTo(0.30, 1e-4));
      expect(c.est!.guardKcal, closeTo(145.97, 0.01));
      expect(c.kgNow!, closeTo(96.9214, 1e-3));
      // (0,30 + 96,92 × 0,5%) × 7.700 ÷ 7 = 863 kcal πάνω από τον ρυθμό, πέρα από το περιθώριο (146): −150.
      expect(lowLogText(c), _lowText);
    });

    test('με τον στόχο του χρήστη ([kcalSet]) η πρόταση ξεκινά από αυτόν', () {
      final c = _at(_lg(kcalSet: 2300), _world(2230, 0.30, noise: 0.15));
      expect((c.kind, c.lowLog, c.proposal!.current, c.proposal!.target), (CheckKind.proposal, true, 2300, 2150));
    });

    test('βάρος στον ρυθμό με λίγο γραμμένο φαγητό: «κάτι λείπει» όπως πριν', () {
      // 1.350 + 0,5 × 1.100 = 1.900 < 1.932, αλλά το βάρος πέφτει 0,50 kg/εβδ. (ο ρυθμός θέλει 0,47–0,48).
      final c = _at(_lg(), _world(1350, -0.50));
      expect((c.kind, c.lowLog, c.status, c.proposal), (CheckKind.implausible, false, AdaptStatus.implausible, null));
    });

    test('μέσα στο περιθώριο των ζυγίσεων (±0,8 kg): «κάτι λείπει» όπως πριν', () {
      // 1.800 − 0,10 × 1.100 = 1.690· 643 kcal πάνω από τον ρυθμό, αλλά περιθώριο 779.
      final c = _at(_lg(), _world(1800, 0.10, noise: 0.8));
      expect((c.kind, c.lowLog, c.proposal), (CheckKind.implausible, false, null));
      expect(c.est!.guardKcal, closeTo(778.52, 0.01));
    });

    test('πολύ ψηλή εκτίμηση (πάνω από 140%): «κάτι λείπει» όπως πριν', () {
      final c = _at(_lg(), _world(4000, 0, noise: 0.1));
      expect((c.kind, c.lowLog, c.proposal), (CheckKind.implausible, false, null));
    });

    test('όχι αλλαγή 3 μέρες μετά από αλλαγή (S1-4)· 4 μέρες μετά ναι', () {
      Goals afterFast(String day) => _lg(
          kcalAdapt: 2380,
          fastAt: day,
          addLog: AdaptLog(day: day, tdee: 2760, before: 2230, after: 2380, applied: true, fast: true));
      final held = _at(afterFast('2026-12-11'), _world(2230, 0.30, noise: 0.15));
      expect((held.kind, held.lowLog, held.proposal), (CheckKind.implausible, false, null));
      final ok = _at(afterFast('2026-12-10'), _world(2230, 0.30, noise: 0.15));
      expect((ok.kind, ok.lowLog, ok.proposal!.current, ok.proposal!.target), (CheckKind.proposal, true, 2380, 2230));
    });

    test('ποτέ κάτω από 1.500 (άνδρας)· κάτω από 30 kcal ως το όριο, καμία πρόταση', () {
      final at = _at(_lg(kcalAdapt: 1560), _world(1560, 0.30, noise: 0.15));
      expect((at.kind, at.lowLog, at.proposal!.target, at.proposal!.floored), (CheckKind.proposal, true, 1500, true));
      final near = _at(_lg(kcalAdapt: 1520), _world(1520, 0.30, noise: 0.15));
      expect((near.kind, near.proposal), (CheckKind.implausible, null));
    });

    test('«ίδιο βάρος» και «περισσότεροι μύες»: ο ρυθμός τους μετρά', () {
      final keep = _at(_lg(aim: GoalAim.keep), _world(2200, 0.40, noise: 0.1));
      expect((keep.kind, keep.lowLog, keep.proposal!.current, keep.proposal!.target), (CheckKind.proposal, true, 2760, 2610));
      expect(lowLogText(keep), contains('ανέβαινε 0,40\u00A0kg την εβδομάδα, ενώ ο στόχος σου είναι να μένει ίδιο.'));
      final gain = _at(_lg(aim: GoalAim.gain, rate: 0.0025), _world(2500, 1.0, noise: 0.1));
      expect((gain.kind, gain.lowLog, gain.proposal!.current, gain.proposal!.target), (CheckKind.proposal, true, 3020, 2870));
      expect(lowLogText(gain), contains('ανέβαινε 1,00\u00A0kg την εβδομάδα, ενώ ο στόχος σου είναι να ανεβαίνει 0,25\u00A0kg'));
    });

    test('lowLogProposal: όρια (70% του τύπου, περιθώριο, 30 kcal)', () {
      Expenditure est(double tdee, double slope, {double se = 0}) => Expenditure(
          tdee: tdee,
          meanIntake: 2230,
          slopeKgWeek: slope,
          intakeDays: 21,
          weighIns: 9,
          from: DateTime(2026, 11, 23),
          to: DateTime(2026, 12, 13),
          seKcal: se);
      final g = _lg();
      // (0,3 + 97 × 0,5%) × 1.100 = 863,5 → −150.
      expect(lowLogProposal(goals: g, est: est(1900, 0.3), kgNow: 97)?.target, 2080);
      expect(lowLogProposal(goals: g, est: est(1931, 0.3), kgNow: 97)?.target, 2080, reason: 'κάτω από 1.932');
      expect(lowLogProposal(goals: g, est: est(1940, 0.3), kgNow: 97), isNull, reason: 'η εκτίμηση γίνεται δεκτή');
      expect(lowLogProposal(goals: g, est: est(1900, 0.3, se: 450), kgNow: 97), isNull, reason: 'περιθώριο 900 > 863,5');
      expect(lowLogProposal(goals: g, est: est(1900, -0.465), kgNow: 97), isNull, reason: '22 kcal → 20 < 30');
      expect(lowLogProposal(goals: g, est: est(1900, -0.455), kgNow: 97)?.target, 2200, reason: '33 kcal → 30');
      expect(plannedKgWeek(g, 97), closeTo(-0.485, 1e-12));
      expect(plannedKgWeek(_lg(aim: GoalAim.keep), 97), 0);
    });

    test('«Εφάρμοσε»: νέος στόχος, γραμμή «lo» στο ιστορικό, η εκτίμηση ΔΕΝ κρατιέται· JSON προς τα πίσω', () {
      final c = _at(_lg(kcalSet: 2300), _world(2230, 0.30, noise: 0.15));
      final g = applyCheckIn(c, _mon);
      expect((g.kcal, g.kcalAdapt, g.kcalSet, g.tdeeEst, g.checkIn), (2150, 2150, null, null, '2026-12-14'));
      final l = g.log.single;
      expect((l.day, l.tdee, l.before, l.after, l.applied, l.fast, l.lowLog), ('2026-12-14', 2760.0, 2300, 2150, true, false, true));
      expect(g.toJson()['log'], [
        {'d': '2026-12-14', 'te': 2760.0, 'k0': 2300, 'k1': 2150, 'ap': true, 'lo': true},
      ]);
      final back = Goals.fromJson(g.toJson())!;
      expect(back.log.single.lowLog, isTrue);
      expect(back.toJson(), g.toJson());
      // Παλιά γραμμή χωρίς «lo»: διαβάζεται όπως πριν.
      final old = AdaptLog.fromJson({'d': '2026-12-07', 'te': 2600, 'k0': 2230, 'k1': 2100, 'ap': true})!;
      expect((old.lowLog, old.fast, old.applied), (false, false, true));
      expect(old.toJson().containsKey('lo'), isFalse);
      // Ίδιοι κανόνες απόστασης με κάθε άλλη αλλαγή.
      expect(lastChangeDay(g), _mon);
      expect(pendingCheckIn(goals: g, today: _mon, weights: const [], intake: _intakeOf(const {})), isNull);
      expect(nextCheckDay(g, DateTime(2026, 12, 15)), DateTime(2026, 12, 21));
    });

    test('«Όχι τώρα»: ο στόχος μένει, γραμμή «lo» χωρίς αλλαγή, καμία εκτίμηση', () {
      final c = _at(_lg(), _world(2230, 0.30, noise: 0.15));
      final g = dismissCheckIn(c, _mon);
      expect((g.kcal, g.kcalAdapt, g.tdeeEst, g.checkIn), (2230, null, null, '2026-12-14'));
      final l = g.log.single;
      expect((l.before, l.after, l.applied, l.lowLog), (2230, 2230, false, true));
    });

    testWidgets('η κάρτα: τι έκανε το βάρος, χωρίς «καις …», χωρίς «Πώς βγήκε»· «Εφάρμοσε» → 2.080', (t) async {
      final c = _at(_lg(), _world(2230, 0.30, noise: 0.15));
      final store = HealthStore();
      await _pump(t, Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: CheckInCard(check: c, store: store, now: _mon))));
      expect(find.text(_lowText), findsOneWidget);
      expect(find.textContaining('καις περίπου', findRichText: true), findsNothing);
      expect(find.text('Νέος στόχος'), findsOneWidget);
      expect(find.text('−150 από 2.230'), findsOneWidget);
      expect(find.byKey(const ValueKey('checkin-how')), findsNothing);
      expect(find.byKey(const ValueKey('checkin-later')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('checkin-apply')));
      await t.pumpAndSettle();
      final g = store.goals!;
      expect((g.kcal, g.tdeeEst, g.log.single.lowLog, g.log.single.applied), (2080, null, true, true));
    });

    testWidgets('η σελίδα «Στόχοι» μετά: γιατί κατέβηκε, «λείπει φαγητό» στο ιστορικό, επόμενος έλεγχος 21/12', (t) async {
      final c = _at(_lg(), _world(2230, 0.30, noise: 0.15));
      final s = HealthStore()
        ..setProfile(_p)
        ..setGoals(applyCheckIn(c, _mon));
      await _pump(t, GoalsPage(store: s, now: DateTime(2026, 12, 15, 9)));
      expect(find.text('Κατέβηκε από 2.230 σε 2.080 (14/12), γιατί το βάρος σου πήγαινε πιο ψηλά από τον στόχο'), findsOneWidget);
      expect(find.text('λείπει φαγητό'), findsOneWidget);
      expect(find.text('στόχος 2.230 → 2.080'), findsOneWidget);
      expect(find.text('Επόμενος έλεγχος: Δευτέρα 21 Δεκεμβρίου'), findsOneWidget);
      expect(find.textContaining('1.900'), findsNothing, reason: 'η εκτίμηση που δεν μέτρησε δεν γράφεται ως «πόσο καις»');
    });

    testWidgets('η σελίδα «Στόχοι» μετά το «Όχι τώρα»: όχι «τα δεδομένα σου δεν ζήτησαν αλλαγή»', (t) async {
      final c = _at(_lg(), _world(2230, 0.30, noise: 0.15));
      final s = HealthStore()
        ..setProfile(_p)
        ..setGoals(dismissCheckIn(c, _mon));
      await _pump(t, GoalsPage(store: s, now: DateTime(2026, 12, 15, 9)));
      expect(find.text('Από τον τύπο· δεν εφάρμοσες τη μείωση που πρότεινε η ζυγαριά (14/12)'), findsOneWidget);
      expect(find.textContaining('δεν ζήτησαν αλλαγή'), findsNothing);
      expect(find.text('ο στόχος έμεινε 2.230'), findsOneWidget);
      expect(find.text('Επόμενος έλεγχος: Δευτέρα 21 Δεκεμβρίου'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------------------------------------ R7-A1-2
  group('R7-A1-2: η σελίδα «Στόχοι» μετά από κενό στο φαγητό λέει την ίδια μέρα με τη Σήμερα', () {
    final at = DateTime(2026, 12, 15, 9);

    HealthStore store(Goals g) {
      final s = HealthStore()..data = Dashboard.fromJson({...sampleDashboardJson(at), 'body': bodyJson(simWeights(at))});
      s
        ..setProfile(_p90)
        ..setGoals(g);
      return s;
    }

    test('readiness: μετρούν οι μέρες από 12/12· η εκτίμηση βγαίνει 4/1, όπως στον έλεγχο της Σήμερα', () {
      final food = checkinFood(at, days: 29, skip: {4, 5, 6, 7, 8}); // καμία καταγραφή 7–11/12
      final g = checkinGoals().copyWith(checkIn: '2026-12-14');
      final w = dailyWeights(Dashboard.fromJson({...sampleDashboardJson(at), 'body': bodyJson(simWeights(at))}).body);
      final r = readiness(goals: g, today: at, weights: w, intake: (a, b) => dailyIntake(food, a, b));
      expect((r.intakeDays, r.weighIns, r.first), (3, 1, DateTime(2026, 12, 14)));
      expect((r.gap!.from, r.gap!.to, r.gap!.restart), (DateTime(2026, 12, 7), DateTime(2026, 12, 11), DateTime(2026, 12, 12)));
      expect(nextCheckDay(g, at), DateTime(2026, 12, 21));
      expect(estimateDayAfterGap(g, DateTime(2026, 12, 21), r.gap), DateTime(2027, 1, 4));
      expect(estimateDayAfterGap(g, DateTime(2027, 1, 11), r.gap), DateTime(2027, 1, 11), reason: 'ήδη αργότερα');
      expect(estimateDayAfterGap(g, DateTime(2026, 12, 21), null), DateTime(2026, 12, 21));
      expect(estimateDayAfterGap(g, DateTime(2026, 12, 21), (from: DateTime(2026, 12, 9), to: DateTime(2026, 12, 14), restart: null)),
          isNull);
      // Ο έλεγχος της Σήμερα με τα ίδια δεδομένα (και φαγητό κάθε μέρα μετά): 21/12 και 28/12 «afterGap», 4/1 εκτίμηση.
      for (final (day, status) in [
        (DateTime(2026, 12, 21), AdaptStatus.afterGap),
        (DateTime(2026, 12, 28), AdaptStatus.afterGap),
        (DateTime(2027, 1, 4), AdaptStatus.ok),
      ]) {
        final eaten = {
          for (final e in _daily(_start, DateTime(day.year, day.month, day.day - 1), 2250).entries)
            if (e.key.isBefore(DateTime(2026, 12, 7)) || e.key.isAfter(DateTime(2026, 12, 11))) e.key: e.value,
        };
        final ws = [for (final (d, kg) in simWeights(day, days: daysBetween(_start, day))) (DateTime(d.year, d.month, d.day), kg)];
        final r2 = estimateExpenditure(intake: eaten, weights: ws, today: day, formulaTdee: g.calc.tdee, goalKcal: g.kcal, since: _start);
        expect(r2.status, status, reason: '$day');
        if (status == AdaptStatus.ok) expect((r2.est!.from, r2.est!.windowDays), (DateTime(2026, 12, 14), 21));
      }
    });

    testWidgets('κενό 7–11/12: «Πρώτη εκτίμηση: Δευτέρα 4 Ιανουαρίου», μέρες «3 από 14», το κενό γραμμένο', (t) async {
      FoodStore.shared = checkinFood(at, days: 29, skip: {4, 5, 6, 7, 8});
      addTearDown(() => FoodStore.shared = null);
      await _pump(t, GoalsPage(store: store(checkinGoals().copyWith(checkIn: '2026-12-14')), now: at));
      expect(find.text('Πρώτη εκτίμηση: Δευτέρα 4 Ιανουαρίου'), findsOneWidget, reason: 'πριν: Δευτέρα 21 Δεκεμβρίου');
      expect(find.text('3 από 14'), findsOneWidget);
      expect(find.text('1 από 6'), findsOneWidget);
      expect(find.text('σε 20 μέρες'), findsOneWidget);
      expect(
          find.text('Από 7 Δεκ ως 11 Δεκ δεν γράφτηκε φαγητό που να μετρά: μετράνε οι μέρες από 12 Δεκ και μετά, και η '
              'εκτίμηση θέλει 3 εβδομάδες.'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('goals-adapt-missed')), findsNothing);
      // R7-U2-18: η φράση «η πρώτη εβδομάδα δεν μετρά» μία φορά.
      expect(find.text('Τι έχει μαζευτεί ως χθες:'), findsOneWidget);
      expect(find.textContaining('(η πρώτη εβδομάδα δεν μετρά)'), findsNothing);
      expect(find.textContaining('Η πρώτη εβδομάδα δεν μετρά: τότε φεύγουν κυρίως νερά.'), findsOneWidget);
    });

    testWidgets('κενό που κρατά ως χθες: «3 εβδομάδες αφού ξαναρχίσει η καταγραφή», τίποτα δεν μετρά ακόμα', (t) async {
      FoodStore.shared = checkinFood(at, days: 29, skip: {1, 2, 3, 4, 5, 6}); // καμία καταγραφή 9–14/12
      addTearDown(() => FoodStore.shared = null);
      await _pump(t, GoalsPage(store: store(checkinGoals().copyWith(checkIn: '2026-12-14')), now: at));
      expect(find.text('Πρώτη εκτίμηση: 3 εβδομάδες αφού ξαναρχίσει η καταγραφή φαγητού'), findsOneWidget);
      expect(find.text('0 από 14'), findsOneWidget);
      expect(find.text('0 από 6'), findsOneWidget);
      expect(find.text('μετά το κενό'), findsOneWidget);
      expect(
          find.text('Από 9 Δεκ δεν έχει γραφτεί φαγητό που να μετρά. Η εκτίμηση ξαναρχίζει από τη μέρα που θα ξαναγράψεις '
              'φαγητό και θέλει 3 εβδομάδες.'),
          findsOneWidget);
    });

    testWidgets('έλεγχος που έγινε χωρίς εκτίμηση: η κάρτα το λέει, όχι «όλα έτοιμα» σιωπηλά', (t) async {
      FoodStore.shared = checkinFood(at, days: 29);
      addTearDown(() => FoodStore.shared = null);
      await _pump(t, GoalsPage(store: store(checkinGoals().copyWith(checkIn: '2026-12-14')), now: at));
      expect(find.text('Πρώτη εκτίμηση: Δευτέρα 21 Δεκεμβρίου'), findsOneWidget);
      expect(find.text('21 από 14'), findsOneWidget);
      expect(find.text('Ο έλεγχος στις 14/12 δεν έβγαλε εκτίμηση· η κάρτα της Σήμερα έγραψε γιατί.'), findsOneWidget);
      expect(find.byKey(const ValueKey('goals-adapt-gap')), findsNothing);
    });
  });

  // ------------------------------------------------------------------------------------------------ R7-A1-3
  group('R7-A1-3: «Ξανά ο οδηγός» με ίδιο σκοπό πριν από την πρώτη εκτίμηση κρατά την αρχή', () {
    Goals old(String since) => Goals(
        aim: GoalAim.lose,
        rate: 0.005,
        activity: 1.5,
        doctor: true,
        since: since,
        kg: 96,
        age: 45,
        heightCm: 176,
        male: true);

    Future<HealthStore> rerunWithLittleMovement(WidgetTester t, String since) async {
      final store = HealthStore()
        ..setProfile(_p)
        ..setGoals(old(since));
      await _pump(t, GoalsWizard(store: store, now: DateTime(2026, 12, 2, 9)));
      await t.enterText(find.byKey(const ValueKey('wizard-kg')), '96');
      await t.pumpAndSettle();
      for (var k = 0; k < 3; k++) {
        await _next(t);
      }
      await t.tap(find.byKey(const ValueKey('opt-act-0')));
      await t.pumpAndSettle();
      await _next(t); // → γιατρός (το «Ναι» είναι ήδη επιλεγμένο από τους παλιούς στόχους)
      await _next(t); // → σύνοψη
      return store;
    }

    testWidgets('αρχή 16/11, αλλαγή μόνο της κίνησης στις 2/12: αρχή 16/11, πρώτη εκτίμηση 14/12 (όχι 30/12)', (t) async {
      final store = await rerunWithLittleMovement(t, '2026-11-16');
      expect(find.textContaining('τη Δευτέρα 14 Δεκεμβρίου'), findsOneWidget);
      expect(find.textContaining('συνεχίζει όπως πριν'), findsNothing);
      expect(find.textContaining('30 Δεκεμβρίου'), findsNothing);
      await _next(t);
      final g = store.goals!;
      // 1.840 × 1,4 = 2.576 − 528 = 2.048 → 2.050.
      expect((g.since, g.activity, g.kcal, g.checkIn), ('2026-11-16', 1.4, 2050, null));
      expect(firstEstimateDay(g), DateTime(2026, 12, 14));
    });

    testWidgets('παλιοί στόχοι (αρχή 1/9) χωρίς εκτίμηση: νέα αρχή σήμερα, όπως πριν', (t) async {
      final store = await rerunWithLittleMovement(t, '2026-09-01');
      expect(find.textContaining('την Τετάρτη 30 Δεκεμβρίου'), findsOneWidget);
      await _next(t);
      expect(store.goals!.since, '2026-12-02');
    });
  });

  // ------------------------------------------------------------------------------------------------ R7-A1-4
  group('R7-A1-4: το κάτω όριο με τα λόγια της οδηγίας AHA/ACC/TOS 2013, όχι «όριο ασφαλείας»', () {
    test('κανένα «όριο ασφαλείας» στους κανόνες και στις οθόνες των θερμίδων', () {
      for (final f in [
        'lib/goals.dart',
        'lib/adaptive.dart',
        'lib/adaptive_check.dart',
        'lib/pages/checkin_card.dart',
        'lib/pages/goals_page.dart',
      ]) {
        expect(File(f).readAsStringSync().contains('όριο ασφαλείας'), isFalse, reason: f);
      }
      expect(floorWhy(true), 'το λιγότερο που προτείνουν οι οδηγίες για άνδρες');
      expect(floorWhy(false), 'το λιγότερο που προτείνουν οι οδηγίες για γυναίκες');
      expect((kcalFloorMale, kcalFloorFemale), (1500, 1200));
    });

    testWidgets('κάρτα στο κάτω όριο: «Δεν κατεβαίνει κάτω από 1.500 kcal, το λιγότερο που προτείνουν οι οδηγίες για άνδρες.»',
        (t) async {
      final c = _at(_lg(kcalAdapt: 1560), _world(1560, 0.30, noise: 0.15));
      await _pump(t, Scaffold(body: SingleChildScrollView(child: CheckInCard(check: c, store: HealthStore(), now: _mon))));
      expect(find.text('Δεν κατεβαίνει κάτω από 1.500\u00A0kcal, το λιγότερο που προτείνουν οι οδηγίες για άνδρες.'), findsOneWidget);
      expect(find.textContaining('ασφαλείας', findRichText: true), findsNothing);
    });

    testWidgets('«Πώς υπολογίστηκε» στο κάτω όριο (γυναίκα): «Ανέβηκε στις 1.200 kcal, …για γυναίκες.»', (t) async {
      // 10×45 + 6,25×150 − 5×60 − 161 = 926,5 × 1,4 = 1.297 − 45×0,75%×1.100 (371) = 926 → 930 < 1.200.
      final g = Goals(
          aim: GoalAim.lose, rate: 0.0075, activity: 1.4, doctor: false, since: '2026-11-16', kg: 45, age: 60, heightCm: 150, male: false);
      expect((g.calc.kcal, g.calc.floored), (1200, true));
      final s = HealthStore()
        ..setProfile(const Profile(birthYear: 1966, birthMonth: 1, sex: 'f', heightCm: 150))
        ..setGoals(g);
      await _pump(t, GoalsPage(store: s, now: DateTime(2026, 11, 20, 9)));
      await t.tap(find.byKey(const ValueKey('goals-how')));
      await t.pumpAndSettle();
      expect(find.text('Ανέβηκε στις 1.200 kcal, το λιγότερο που προτείνουν οι οδηγίες για γυναίκες.'), findsOneWidget);
      expect(find.textContaining('ασφαλείας'), findsNothing);
    });
  });

  // ------------------------------------------------------------------------------------------------ R7-U2-10/11/12/16
  group('R7-U2: οδηγός και σελίδα «Στόχοι»', () {
    testWidgets('U2-10: «περίπου 495 kcal» στον ρυθμό, όπως το «−495» της σύνοψης· U2-11: το «Ναι» λέει μόνο τα κορεσμένα',
        (t) async {
      final store = HealthStore()..setProfile(_p);
      await _pump(t, GoalsWizard(store: store, now: DateTime(2026, 11, 16, 9)));
      await t.enterText(find.byKey(const ValueKey('wizard-kg')), '90');
      await t.pumpAndSettle();
      await _next(t);
      await _next(t);
      // 90 × 0,5% × 7.700 ÷ 7 = 495· 90 × 0,25% × 7.700 ÷ 7 = 247,5 → 248.
      expect(find.textContaining('περίπου 495 kcal λιγότερες τη μέρα'), findsOneWidget);
      expect(find.textContaining('περίπου 248 kcal λιγότερες τη μέρα'), findsOneWidget);
      expect(find.textContaining('περίπου 500 kcal'), findsNothing);
      expect(find.textContaining('Ποτέ κάτω από 1.500 kcal, το λιγότερο που προτείνουν οι οδηγίες για άνδρες.'), findsOneWidget);
      await _next(t);
      await _next(t);
      expect(find.textContaining('Κορεσμένα έως 6% των θερμίδων (αντί για 10%)'), findsOneWidget);
      expect(find.textContaining('φυτικές ίνες 30 g'), findsNothing);
      await t.tap(find.byKey(const ValueKey('opt-doc-no')));
      await t.pumpAndSettle();
      await _next(t);
      expect(find.textContaining('−495 για 0,45 kg την εβδομάδα'), findsOneWidget);
    });

    test('U2-12: «β‑γλυκάνες» πάντα με αδιάσπαστο ενωτικό στη σελίδα «Στόχοι»', () {
      expect(File('lib/pages/goals_page.dart').readAsStringSync().contains('β-γλυκ'), isFalse);
    });

    testWidgets('U2-12: «γράψε τις β‑γλυκάνες» με αδιάσπαστο ενωτικό', (t) async {
      final s = HealthStore()
        ..setProfile(_p90)
        ..setGoals(checkinGoals());
      await _pump(t, GoalsPage(store: s, now: DateTime(2026, 11, 20, 9)));
      expect(find.textContaining('γράψε τις β\u2011γλυκάνες'), findsOneWidget);
      expect(find.textContaining('β-γλυκ'), findsNothing);
    });

    testWidgets('U2-16: ανοιχτό Fold: θρεπτικά αριστερά κάτω από τις θερμίδες· τα κουμπιά στο τέλος της δεξιάς στήλης', (t) async {
      final s = HealthStore()
        ..setProfile(_p90)
        ..setGoals(checkinGoals());
      await _pump(t, GoalsPage(store: s, now: DateTime(2026, 11, 20, 9)), size: const Size(860, 2000));
      final mid = 860 / 2;
      expect(t.getTopLeft(find.byKey(const ValueKey('goals-kcal'))).dx, lessThan(mid));
      expect(t.getTopLeft(find.byKey(const ValueKey('goals-protein'))).dx, lessThan(mid));
      expect(t.getTopLeft(find.byKey(const ValueKey('goals-nuts'))).dx, greaterThan(mid));
      expect(t.getTopLeft(find.byKey(const ValueKey('goals-weigh'))).dx, greaterThan(mid));
      expect(t.getTopLeft(find.byKey(const ValueKey('goals-delete'))).dx, greaterThan(mid));
      expect(t.getTopLeft(find.byKey(const ValueKey('goals-wizard'))).dy,
          greaterThan(t.getTopLeft(find.byKey(const ValueKey('goals-weigh'))).dy));
      expect(t.getTopLeft(find.byKey(const ValueKey('goals-delete'))).dy,
          greaterThan(t.getTopLeft(find.byKey(const ValueKey('goals-wizard'))).dy));
      expect(t.takeException(), isNull);
    });
  });

  // ------------------------------------------------------------------------------------------------ R7-A12-1
  group('R7-A12-1: ο στόχος δεν κατεβαίνει όσο χάνεις > 1%/εβδ. (S1-3), κάθε κλάδος μόνος του', () {
    test('(α) μόνο η κλίση της εκτίμησης περνά το 1% (η «γρήγορη απώλεια» όχι, λόγω περιθωρίου)', () {
      // 90 kg, −0,909 kg/εβδ., ±0,3 εναλλάξ· φαγητό 1.400/μέρα 23/11–13/12· Δευτέρα 14/12.
      final w = _weighs(_start, _mon, (d, i) => 90 - 0.909 * d / 7 + (i.isEven ? 0.3 : -0.3));
      final food = _daily(DateTime(2026, 11, 23), DateTime(2026, 12, 13), 1400);
      final g = checkinGoals();
      final c = pendingCheckIn(goals: g, today: _mon, weights: w, intake: _intakeOf(food))!;
      expect((c.kind, c.tooFast, c.proposal!.target), (CheckKind.same, true, 2250));
      expect(c.est!.slopeKgWeek, closeTo(-0.909, 1e-6));
      expect(c.est!.slopeKgWeek, lessThan(-0.01 * c.kgNow!), reason: 'κλάδος 1: −0,909 < −0,865');
      expect(fastLossSlope(goals: g, weights: w, today: _mon), isNull, reason: 'κλάδος 2 δεν ισχύει');
      expect(proposeTarget(goals: g, est: c.est!, kgNow: c.kgNow!).target, 2100, reason: 'χωρίς τον κανόνα: −150');
    });

    test('(β) μόνο οι τελευταίες εβδομάδες περνούν το 1% (παράθυρο 42 μερών κάτω από 1%)', () {
      // 0,5%/εβδ. ως 19/12, 1,3%/εβδ. μετά· φαγητό 1.450/μέρα από 16/11· Δευτέρα 11/1/2027.
      final today = DateTime(2027, 1, 11);
      final w = <(DateTime, double)>[];
      var kg = 90.0;
      for (var d = _start; !d.isAfter(today); d = DateTime(d.year, d.month, d.day + 1)) {
        if (_mwf(d)) w.add((d, kg));
        kg += -(d.isBefore(DateTime(2026, 12, 20)) ? 0.005 : 0.013) * kg / 7;
      }
      final food = _daily(_start, DateTime(2027, 1, 10), 1450);
      final g = checkinGoals();
      final c = pendingCheckIn(goals: g, today: today, weights: w, intake: _intakeOf(food))!;
      expect((c.kind, c.status, c.tooFast, c.proposal!.target, c.est!.windowDays), (CheckKind.same, AdaptStatus.ok, true, 2250, 42));
      expect(c.est!.slopeKgWeek, closeTo(-0.7721, 1e-3));
      expect(c.est!.slopeKgWeek, greaterThan(-0.01 * c.kgNow!), reason: 'κλάδος 1 δεν ισχύει: −0,772 > −0,848');
      expect(fastLossSlope(goals: g, weights: w, today: today), isNotNull, reason: 'κλάδος 2');
      expect(proposeTarget(goals: g, est: c.est!, kgNow: c.kgNow!).target, 2100, reason: 'χωρίς τον κανόνα: −150');
    });
  });

  // ------------------------------------------------------------------------------------------------ R7-A12-2/3
  group('R7-A12-2 / R7-A12-3: γρήγορη απώλεια, μόνο σε «λιγότερο λίπος» και στα όριά της', () {
    // Όπως το _sim της adaptive_test: 21 μέρες πριν από 7/12, τρως 1.600 και καις 2.900 (−1,18 kg/εβδ.).
    final today = DateTime(2026, 12, 7);
    final fast = <(DateTime, double)>[];
    var kg = 90.0;
    for (var k = 21; k >= 1; k--) {
      final d = DateTime(today.year, today.month, today.day - k);
      if (_mwf(d)) fast.add((d, kg));
      kg += (1600 - 2900) / kcalPerKg;
    }
    Goals aimed(GoalAim aim) => Goals(
        aim: aim,
        rate: aim == GoalAim.keep ? 0 : 0.005,
        activity: 1.5,
        doctor: false,
        since: '2026-11-16',
        kg: 90,
        age: 40,
        heightCm: 180,
        male: true);

    test('A12-2: «ίδιο βάρος» / «περισσότεροι μύες»: καμία «γρήγορη απώλεια», ούτε κάρτα', () {
      expect(fastLossSlope(goals: aimed(GoalAim.lose), weights: fast, today: today)!.slopeKgWeek, closeTo(-1.1818, 1e-3),
          reason: 'οι ζυγίσεις πέφτουν πράγματι γρήγορα');
      expect(fastLossSlope(goals: aimed(GoalAim.keep), weights: fast, today: today), isNull);
      expect(fastLossSlope(goals: aimed(GoalAim.gain), weights: fast, today: today), isNull);
      final next = DateTime(2026, 12, 8);
      for (final aim in [GoalAim.keep, GoalAim.gain]) {
        expect(pendingCheckIn(goals: aimed(aim).copyWith(checkIn: '2026-12-07'), today: next, weights: fast, intake: _intakeOf(const {})),
            isNull,
            reason: '$aim');
      }
      expect(pendingCheckIn(goals: aimed(GoalAim.lose).copyWith(checkIn: '2026-12-07'), today: next, weights: fast, intake: _intakeOf(const {}))!
          .kind, CheckKind.fast);
    });

    test('A12-3: τουλάχιστον 4 ζυγίσεις· περιθώριο ενός τυπικού σφάλματος· «λιγότερες από 30» ως το όριο', () {
      final day = DateTime(2026, 12, 4);
      final three = [
        (DateTime(2026, 11, 23), 88.0),
        (DateTime(2026, 11, 28), 88 - 1.5 * 5 / 7),
        (DateTime(2026, 12, 3), 88 - 1.5 * 10 / 7),
      ];
      expect(weightFit(three)!.slope * 7, closeTo(-1.5, 1e-9));
      expect(fastLossCheck(goals: checkinGoals(), weights: three, today: day), isNull, reason: 'μόνο 3 ζυγίσεις');
      List<(DateTime, double)> a3(double last) => [
            (DateTime(2026, 11, 23), 88.0),
            (DateTime(2026, 11, 25), 87.8),
            (DateTime(2026, 11, 27), 87.6),
            (DateTime(2026, 11, 30), 87.3),
            (DateTime(2026, 12, 2), 87.1),
            (DateTime(2026, 12, 4), last),
          ];
      final f = weightFit(a3(85.9))!;
      expect(f.slope * 7, closeTo(-1.1302, 1e-4));
      expect(f.se! * 7, closeTo(0.2604, 1e-4));
      expect((f.slope + f.se!) * 7, lessThan(-0.01 * 85.9), reason: '−0,870 < −0,859');
      expect((f.slope + 1.1 * f.se!) * 7, greaterThan(-0.01 * 85.9), reason: 'με 1,1 σφάλματα δεν θα έβγαινε');
      expect(fastLossCheck(goals: checkinGoals(), weights: a3(85.9), today: day)?.change, 150);
      final line = [for (final d in [0, 2, 4, 7, 9, 11]) (DateTime(2026, 11, 23 + d), 88.0 - 0.9 * d / 7)];
      final p = fastLossCheck(goals: checkinGoals(kcalAdapt: 2720), weights: line, today: day)!;
      expect((p.current, p.target, p.change), (2720, 2750, 30), reason: 'μένουν ακριβώς 30: όχι «λιγότερες από 30»');
      expect(fastLossCheck(goals: checkinGoals(kcalAdapt: 2730), weights: line, today: day), isNull);
    });
  });

  // ------------------------------------------------------------------------------------------------ R7-A12-4
  group('R7-A12-4: «κάτω από 30 μένει ίδιος» και «όχι αλλαγή κάτω από 4 μέρες» στο όριο', () {
    test('−28 → ίδιος· −31 → αλλαγή', () {
      final est = Expenditure(
          tdee: 2600, meanIntake: 2250, slopeKgWeek: -0.32, intakeDays: 21, weighIns: 9, from: DateTime(2026, 11, 23), to: DateTime(2026, 12, 13));
      // 2.600 − 89 × 0,5% × 1.100 = 2.110,5 → 2.110.
      final same = proposeTarget(goals: checkinGoals(kcalAdapt: 2138), est: est, kgNow: 89);
      expect((same.target, same.same), (2138, true));
      final moved = proposeTarget(goals: checkinGoals(kcalAdapt: 2141), est: est, kgNow: 89);
      expect((moved.target, moved.same), (2110, false));
    });

    test('«γρήγορη απώλεια» Πέμπτη 10/12 → τη Δευτέρα 14/12 (4 μέρες) αλλάζει· Παρασκευή 11/12 (3 μέρες) όχι', () {
      final w = _weighs(_start, _mon, (d, i) => 90 - 0.318 * d / 7);
      final food = _daily(DateTime(2026, 11, 23), DateTime(2026, 12, 13), 2250);
      Goals fastOn(String day) => checkinGoals(kcalAdapt: 2400).copyWith(
          fastAt: day, addLog: AdaptLog(day: day, tdee: 2750, before: 2250, after: 2400, applied: true, fast: true));
      final four = pendingCheckIn(goals: fastOn('2026-12-10'), today: _mon, weights: w, intake: _intakeOf(food))!;
      expect((four.kind, four.heldDays, four.proposal!.current, four.proposal!.target), (CheckKind.proposal, null, 2400, 2250));
      expect(four.est!.tdee, closeTo(2599.8, 0.1));
      final three = pendingCheckIn(goals: fastOn('2026-12-11'), today: _mon, weights: w, intake: _intakeOf(food))!;
      expect((three.kind, three.heldDays, three.proposal!.target), (CheckKind.same, 3, 2400));
    });
  });

  // ------------------------------------------------------------------------------------------------ R7-A12-9
  group('R7-A12-9: αλλαγή ώρας, 29/2/2028 και αλλαγή χρόνου στον έλεγχο θερμίδων (TZ Europe/Athens στο CI)', () {
    Goals since(String day) => checkinGoals(since: day);

    test('αλλαγή ώρας 25/10/2026: αρχή Δευτέρα 5/10 → έλεγχος 26/10· απαντημένος, ξανά 2/11· εκτίμηση 12/10–1/11', () {
      final g = since('2026-10-05');
      expect(checkInDue(goals: g, today: DateTime(2026, 10, 26)), isTrue, reason: '21 μέρες μέσα από την αλλαγή ώρας');
      expect(checkInDue(goals: g, today: DateTime(2026, 10, 25)), isFalse);
      for (var d = 27; d <= 31; d++) {
        expect(checkInDue(goals: g, today: DateTime(2026, 10, d), lastCheckIn: '2026-10-26'), isFalse, reason: '$d/10');
      }
      expect(checkInDue(goals: g, today: DateTime(2026, 11, 1), lastCheckIn: '2026-10-26'), isFalse);
      expect(checkInDue(goals: g, today: DateTime(2026, 11, 2), lastCheckIn: '2026-10-26'), isTrue);
      expect(nextCheckDay(g.copyWith(checkIn: '2026-10-26'), DateTime(2026, 10, 27)), DateTime(2026, 11, 2));
      final food = _daily(DateTime(2026, 10, 12), DateTime(2026, 11, 1), 2250);
      final w = _weighs(DateTime(2026, 10, 5), DateTime(2026, 11, 2), (d, i) => 90 - 0.3 * d / 7);
      final r = estimateExpenditure(
          intake: food, weights: w, today: DateTime(2026, 11, 2), formulaTdee: g.calc.tdee, goalKcal: g.kcal, since: DateTime(2026, 10, 5));
      expect((r.status, r.est!.from, r.est!.to, r.est!.windowDays, r.est!.intakeDays, r.est!.weighIns),
          (AdaptStatus.ok, DateTime(2026, 10, 12), DateTime(2026, 11, 1), 21, 21, 9));
      expect(r.est!.tdee, closeTo(2580, 0.01));
    });

    test('αλλαγή ώρας 28/3/2027: αρχή 8/3 → έλεγχος 29/3· εκτίμηση 5/4 με παράθυρο 15/3–4/4', () {
      final g = since('2027-03-08');
      expect(checkInDue(goals: g, today: DateTime(2027, 3, 29)), isTrue);
      expect(checkInDue(goals: g, today: DateTime(2027, 3, 28)), isFalse);
      final food = _daily(DateTime(2027, 3, 15), DateTime(2027, 4, 4), 2250);
      final w = _weighs(DateTime(2027, 3, 8), DateTime(2027, 4, 5), (d, i) => 90 - 0.3 * d / 7);
      final r = estimateExpenditure(
          intake: food, weights: w, today: DateTime(2027, 4, 5), formulaTdee: g.calc.tdee, goalKcal: g.kcal, since: DateTime(2027, 3, 8));
      expect((r.status, r.est!.from, r.est!.to, r.est!.windowDays, r.est!.intakeDays, r.est!.weighIns),
          (AdaptStatus.ok, DateTime(2027, 3, 15), DateTime(2027, 4, 4), 21, 21, 9));
      expect(r.est!.tdee, closeTo(2580, 0.01));
    });

    test('29/2/2028', () {
      expect(isDayKey('2028-02-29'), isTrue);
      expect(isDayKey('2027-02-29'), isFalse);
      final g = since('2028-02-08');
      expect((firstCheckDay(g), firstEstimateDay(g)), (DateTime(2028, 2, 29), DateTime(2028, 3, 7)));
      final leap = since('2028-02-29');
      expect(firstCheckDay(leap), DateTime(2028, 3, 21));
      expect(checkInDue(goals: leap, today: DateTime(2028, 3, 21)), isTrue);
      expect(checkInDue(goals: leap, today: DateTime(2028, 3, 20)), isFalse);
      expect(weekStart(DateTime(2028, 3, 1)), DateTime(2028, 2, 28));
      final back = Goals.fromJson({...checkinGoals().toJson(), 'since': '2028-02-29'});
      expect(back?.since, '2028-02-29');
    });

    test('αλλαγή χρόνου', () {
      final g = since('2026-12-14');
      expect((firstCheckDay(g), firstEstimateDay(g)), (DateTime(2027, 1, 4), DateTime(2027, 1, 11)));
      expect(nextCheckDay(g, DateTime(2026, 12, 31)), DateTime(2027, 1, 4));
      expect(nextCheckDay(g.copyWith(checkIn: '2027-01-04'), DateTime(2027, 1, 5)), DateTime(2027, 1, 11));
    });
  });
}
