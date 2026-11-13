// Έλεγχος 13/11, round 1 (f1): στόχοι διατροφής, αυτόματη διόρθωση θερμίδων, μέση, «Τα στοιχεία μου».
// Όλοι οι αριθμοί είναι φανταστικοί (δημόσιο repo). Οι αναμενόμενες τιμές βγήκαν από τον κανόνα όπως γράφεται, σε
// αντίγραφο Python έξω από το repo, όχι από τον κώδικα που δοκιμάζεται.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/adaptive.dart';
import 'package:ygeia_forma/adaptive_check.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/food/chol.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/goals.dart';
import 'package:ygeia_forma/pages/checkin_card.dart';
import 'package:ygeia_forma/pages/goals_page.dart';
import 'package:ygeia_forma/pages/me_page.dart';
import 'package:ygeia_forma/pages/nutrition_goals.dart';
import 'package:ygeia_forma/pages/waist_sheet.dart';
import 'package:ygeia_forma/profile.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/waist.dart';
import 'package:ygeia_forma/weight_guard.dart';
import 'package:ygeia_forma/widgets.dart';

import 'sample_checkin.dart';
import 'sample_data.dart';
import 'sample_food.dart';

/// Φανταστικός χρήστης Α: άνδρας 38 ετών (στις 16/11/2026), 171 cm.
const _inv = Profile(birthYear: 1988, birthMonth: 1, sex: 'm', heightCm: 171);

/// Φανταστικός χρήστης Β: άνδρας 40 ετών, 180 cm (ίδιος με τις άλλες δοκιμές των στόχων).
const _me = Profile(birthYear: 1986, birthMonth: 1, sex: 'm', heightCm: 180);

final _now = DateTime(2026, 11, 12, 10);
final _check = DateTime(2026, 12, 14, 8, 20); // Δευτέρα, 28η μέρα των checkinGoals (από 16/11)

/// Στόχοι του χρήστη Α από Δευτέρα 16/11: 80 kg, −0,5%/εβδ., μέτρια κίνηση, με οδηγία γιατρού.
Goals _invGoals({double activity = 1.5}) => Goals(
      aim: GoalAim.lose,
      rate: 0.005,
      activity: activity,
      doctor: true,
      since: '2026-11-16',
      kg: 80,
      age: 38,
      heightCm: 171,
      male: true,
    );

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 2600), Brightness b = Brightness.light}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(b), home: w));
  await t.pumpAndSettle();
}

/// [days] μέρες πριν από [today] με [eat] kcal η καθεμία (χωρίς τις [skip]).
Map<DateTime, double> _food(DateTime today, {int days = 21, double eat = 2250, Set<int> skip = const {}}) => {
      for (var k = days; k >= 1; k--)
        if (!skip.contains(k)) DateTime(today.year, today.month, today.day - k): eat,
    };

Map<DateTime, double> Function(DateTime, DateTime) _intakeOf(Map<DateTime, double> m) => (a, b) => {
      for (final e in m.entries)
        if (!e.key.isBefore(a) && !e.key.isAfter(b)) e.key: e.value,
    };

List<BodyMeasurement> _body(DateTime today, List<(DateTime, double)> w) =>
    Dashboard.fromJson({...sampleDashboardJson(today), 'body': bodyJson(w)}).body;

/// Όπως ο έλεγχος της Σήμερα: ζυγίσεις μέσα από τον φύλακα (ξένες ζυγίσεις χωριστά).
CheckIn? _pending(
  Goals g,
  DateTime today, {
  double eat = 2250,
  double tdee = 2600,
  Set<int> skip = const {},
  Map<DateTime, double> extra = const {},
  List<(DateTime, double)> Function(List<(DateTime, double)>)? weights,
  bool read = true,
}) {
  final food = {..._food(today, eat: eat, skip: skip), ...extra};
  var w = simWeights(today, eat: eat, tdee: tdee);
  if (weights != null) w = weights(w);
  final split = guardedWeights(_body(today, w));
  return pendingCheckIn(
      goals: g, today: today, weights: split.used, foreign: split.foreign, weightsRead: read, intake: _intakeOf(food));
}

Future<void> _card(WidgetTester t, CheckIn c, DateTime now, {HealthStore? store}) => _pump(
    t, Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: CheckInCard(check: c, store: store ?? HealthStore(), now: now))));

/// Ο χρήστης Α από 16/11: φαγητό 2.090 kcal κάθε μέρα, καίει 2.540· ζυγίσεις Δευτέρα, Τετάρτη, Παρασκευή. Αν [away]:
/// 24/12–6/1 διακοπές χωρίς καταγραφή και χωρίς ζυγαριά, με 3.000 kcal τη μέρα.
({Map<DateTime, double> intake, List<(DateTime, double)> weights}) _world({bool away = false}) {
  final intake = <DateTime, double>{};
  final weights = <(DateTime, double)>[];
  var kg = 80.0;
  for (var d = DateTime(2026, 11, 16); !d.isAfter(DateTime(2027, 2, 28)); d = DateTime(d.year, d.month, d.day + 1)) {
    final off = away && !d.isBefore(DateTime(2026, 12, 24)) && !d.isAfter(DateTime(2027, 1, 6));
    if (!off && (d.weekday == 1 || d.weekday == 3 || d.weekday == 5)) weights.add((d, kg));
    if (!off) intake[d] = 2090;
    kg += ((off ? 3000 : 2090) - 2540) / kcalPerKg;
  }
  return (intake: intake, weights: weights);
}

List<(DateTime, double)> _upTo(List<(DateTime, double)> w, DateTime today) => [
      for (final x in w)
        if (!x.$1.isAfter(today)) x,
    ];

void main() {
  // ------------------------------------------------------------------------------------------------ ο χρήστης, 16/11
  group('οι αριθμοί της αρχής (16/11) δεν αλλάζουν', () {
    test('2.090 kcal με μέτρια κίνηση, 1.920 με λίγη· πρωτεΐνη 130 g· κορεσμένα έως 14 / 13 g', () {
      final m = computeGoals(male: true, age: 38, heightCm: 171, kg: 80, aim: GoalAim.lose, rate: 0.005, activity: 1.5, doctor: true);
      expect((m.kcal, m.protein, m.satMax, m.floored), (2090, 130, 14, false));
      final l = computeGoals(male: true, age: 38, heightCm: 171, kg: 80, aim: GoalAim.lose, rate: 0.005, activity: 1.4, doctor: true);
      expect((l.kcal, l.protein, l.satMax, l.floored), (1920, 130, 13, false));
      expect(_invGoals().kcal, 2090);
      expect(_invGoals(activity: 1.4).kcal, 1920);
    });

    test('αρχή Δευτέρα 16/11: «μαζεύω δεδομένα» στις 7/12, πρώτη εκτίμηση στις 14/12', () {
      final g = _invGoals();
      expect(firstCheckDay(g), DateTime(2026, 12, 7));
      expect(firstEstimateDay(g), DateTime(2026, 12, 14));
      final w = _world();
      CheckIn? at(DateTime d) => pendingCheckIn(goals: g, today: d, weights: _upTo(w.weights, d), intake: _intakeOf(w.intake));
      expect(at(DateTime(2026, 12, 4)), isNull);
      final gather = at(DateTime(2026, 12, 7))!;
      expect((gather.kind, gather.status, gather.days, gather.weighs), (CheckKind.gathering, AdaptStatus.tooEarly, 14, 6));
      final first = at(DateTime(2026, 12, 14))!;
      expect((first.kind, first.status, first.days, first.weighs), (CheckKind.same, AdaptStatus.ok, 21, 9));
      expect((first.est!.windowDays, first.est!.from, first.est!.to), (21, DateTime(2026, 11, 23), DateTime(2026, 12, 13)));
      expect(first.est!.tdee, closeTo(2540, 1));
      expect((first.proposal!.current, first.proposal!.target), (2090, 2090));
    });

    testWidgets('ο οδηγός στις 16/11: 2.090 kcal, 130 g, έως 14 g, πρώτη εκτίμηση «τη Δευτέρα 14 Δεκεμβρίου»', (t) async {
      final store = HealthStore()..setProfile(_inv);
      await _pump(t, GoalsWizard(store: store, now: DateTime(2026, 11, 16, 9)));
      await t.enterText(find.byKey(const ValueKey('wizard-kg')), '80');
      await t.pumpAndSettle();
      for (var k = 0; k < 4; k++) {
        await t.tap(find.byKey(const ValueKey('wizard-next')));
        await t.pumpAndSettle();
      }
      await t.tap(find.byKey(const ValueKey('opt-doc-yes')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('wizard-next')));
      await t.pumpAndSettle();
      expect(find.text('2.090 kcal', findRichText: true), findsOneWidget);
      expect(find.text('130 g'), findsOneWidget);
      expect(find.text('έως 14 g · 6%'), findsOneWidget);
      expect(find.text('80,0 kg · μέτρια κίνηση'), findsOneWidget);
      // S1-5 / S11-6 / U3b-2: η πρώτη εκτίμηση την 28η μέρα, όχι την 21η.
      expect(find.textContaining('τη Δευτέρα 14 Δεκεμβρίου'), findsOneWidget);
      expect(find.textContaining('7 Δεκεμβρίου'), findsNothing);
      expect(find.textContaining('η πρώτη εβδομάδα δεν μετρά'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('wizard-next')));
      await t.pumpAndSettle();
      final g = store.goals!;
      expect((g.kcal, g.protein, g.satMax, g.since, g.kcalAdapt), (2090, 130, 14, '2026-11-16', null));
      expect(firstEstimateDay(g), DateTime(2026, 12, 14));
    });

    testWidgets('ο οδηγός με «Λίγη κίνηση»: 1.920 kcal, έως 13 g', (t) async {
      final store = HealthStore()..setProfile(_inv);
      await _pump(t, GoalsWizard(store: store, now: DateTime(2026, 11, 16, 9)));
      await t.enterText(find.byKey(const ValueKey('wizard-kg')), '80');
      await t.pumpAndSettle();
      for (var k = 0; k < 3; k++) {
        await t.tap(find.byKey(const ValueKey('wizard-next')));
        await t.pumpAndSettle();
      }
      await t.tap(find.byKey(const ValueKey('opt-act-0')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('wizard-next')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('opt-doc-yes')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('wizard-next')));
      await t.pumpAndSettle();
      expect(find.text('1.920 kcal', findRichText: true), findsOneWidget);
      expect(find.text('έως 13 g · 6%'), findsOneWidget);
      expect(find.text('80,0 kg · λίγη κίνηση'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------------------------------------ S1-1 κενό
  group('S1-1: κενό καταγραφής (διακοπές)', () {
    final w = _world(away: true);
    final since = DateTime(2026, 11, 16);
    final formula = _invGoals().calc.tdee;
    ({AdaptStatus status, Expenditure? est}) at(DateTime d) =>
        estimateExpenditure(intake: w.intake, weights: w.weights, today: d, formulaTdee: formula, goalKcal: 2090, since: since);

    test('όσο το κενό κρατά και 3 εβδομάδες μετά: καμία εκτίμηση· μετά ξαναβγαίνει σωστή', () {
      expect(at(DateTime(2027, 1, 4)).status, AdaptStatus.gapOpen);
      expect(at(DateTime(2027, 1, 4)).est, isNull);
      for (final d in [DateTime(2027, 1, 11), DateTime(2027, 1, 18), DateTime(2027, 1, 25)]) {
        expect(at(d).status, AdaptStatus.afterGap, reason: '$d');
        expect(at(d).est, isNull, reason: '$d');
      }
      final back = at(DateTime(2027, 1, 28));
      expect((back.status, back.est!.windowDays, back.est!.from), (AdaptStatus.ok, 21, DateTime(2027, 1, 7)));
      expect(back.est!.tdee, closeTo(2540, 1));
      final later = at(DateTime(2027, 2, 8));
      expect((later.status, later.est!.windowDays, later.est!.from), (AdaptStatus.ok, 28, DateTime(2027, 1, 11)));
      expect(later.est!.tdee, closeTo(2540, 1));
    });

    test('foodGap: ανοιχτό ως χθες, ή κλειστό με τη μέρα που ξαναρχίζει', () {
      final open = foodGap(intake: w.intake, today: DateTime(2027, 1, 4), formulaTdee: formula, goalKcal: 2090, since: since)!;
      expect((open.from, open.to, open.restart), (DateTime(2026, 12, 24), DateTime(2027, 1, 3), null));
      final closed = foodGap(intake: w.intake, today: DateTime(2027, 1, 11), formulaTdee: formula, goalKcal: 2090, since: since)!;
      expect((closed.from, closed.to, closed.restart), (DateTime(2026, 12, 24), DateTime(2027, 1, 6), DateTime(2027, 1, 7)));
    });

    test('4 μέρες χωρίς φαγητό δεν είναι κενό· 5 είναι', () {
      final clean = _world();
      Map<DateTime, double> without(int n) => {
            for (final e in clean.intake.entries)
              if (e.key.isBefore(DateTime(2026, 12, 12)) || !e.key.isBefore(DateTime(2026, 12, 12 + n))) e.key: e.value,
          };
      final t = DateTime(2026, 12, 21);
      final four = estimateExpenditure(
          intake: without(4), weights: _upTo(clean.weights, t), today: t, formulaTdee: formula, goalKcal: 2090, since: since);
      expect((four.status, four.est!.windowDays, four.est!.intakeDays), (AdaptStatus.ok, 28, 24));
      final five = estimateExpenditure(
          intake: without(5), weights: _upTo(clean.weights, t), today: t, formulaTdee: formula, goalKcal: 2090, since: since);
      expect((five.status, five.est), (AdaptStatus.afterGap, null));
    });

    testWidgets('η κάρτα της Δευτέρας: «κενό στο φαγητό», χωρίς πρόταση, ο στόχος μένει', (t) async {
      final g = _invGoals();
      CheckIn at(DateTime d) => pendingCheckIn(goals: g, today: d, weights: _upTo(w.weights, d), intake: _intakeOf(w.intake))!;
      final open = at(DateTime(2027, 1, 4));
      expect((open.kind, open.status, open.proposal), (CheckKind.gap, AdaptStatus.gapOpen, null));
      expect(open.gap!.restart, isNull);
      final closed = at(DateTime(2027, 1, 11));
      expect((closed.kind, closed.status, closed.gap!.restart), (CheckKind.gap, AdaptStatus.afterGap, DateTime(2027, 1, 7)));
      await _card(t, open, DateTime(2027, 1, 4, 9));
      expect(find.text('Έλεγχος θερμίδων: κενό στο φαγητό'), findsOneWidget);
      expect(find.textContaining('(11 μέρες στη σειρά)'), findsOneWidget);
      expect(find.byKey(const ValueKey('checkin-apply')), findsNothing);
      expect(dismissCheckIn(open, DateTime(2027, 1, 4)).kcal, 2090);
    });
  });

  // ------------------------------------------------------------------------------------------------ S1-2, S1-3
  group('S1-2 / S1-3: γρήγορη απώλεια και φαγητό', () {
    test('S1-2: τρως πολύ κάτω από τον στόχο → καμία πρόταση· ο έλεγχος της Δευτέρας δεν τυφλώνεται', () {
      final c = _pending(checkinGoals(), DateTime(2026, 12, 4), eat: 1400, tdee: 2500)!;
      expect((c.kind, c.proposal), (CheckKind.fast, null));
      expect(c.fastIntake!, closeTo(1400, 1e-6));
      expect(c.fastIntakeDays, 11);
      final g = dismissCheckIn(c, DateTime(2026, 12, 4));
      expect((g.kcal, g.fastAt), (2250, '2026-12-04'));
      final m = _pending(g, _check, eat: 1400, tdee: 2500)!;
      expect((m.status, m.days, m.weighs), (AdaptStatus.ok, 21, 9), reason: 'πριν: «μετράνε 0 μέρες φαγητό»');
      expect(m.est!.tdee, closeTo(2504, 2));
    });

    test('S1-2: η πρόταση +150 δεν περνά ποτέ όσα καις', () {
      final g = checkinGoals();
      final fast = [for (final d in [0, 2, 4, 7, 9, 11]) (DateTime(2026, 11, 23 + d), 88.0 - 0.9 * d / 7)];
      final day = DateTime(2026, 12, 4);
      expect(fastLossCap(g), 2750, reason: 'τύπος 2.745 στα 10');
      expect(fastLossCheck(goals: g, weights: fast, today: day)!.target, 2400);
      expect(fastLossCheck(goals: checkinGoals(kcalAdapt: 2700), weights: fast, today: day)!.target, 2750);
      expect(fastLossCheck(goals: checkinGoals(kcalAdapt: 2730), weights: fast, today: day), isNull, reason: 'μένουν 20 kcal: κάτω από 30');
      final est = checkinGoals(kcalAdapt: 2500).copyWith(tdeeEst: 2600);
      expect(fastLossCheck(goals: est, weights: fast, today: day)!.target, 2600, reason: 'ως την εκτίμηση από τα δεδομένα');
    });

    test('S1-2 / S1-6: τρως κοντά στον στόχο και χάνεις γρήγορα → +150· το βήμα γράφεται στο ιστορικό', () {
      final c = _pending(checkinGoals(), DateTime(2026, 12, 4), eat: 2250, tdee: 3550)!;
      expect((c.kind, c.proposal!.current, c.proposal!.target, c.kgNow), (CheckKind.fast, 2250, 2400, 86.5));
      expect(c.fastSlope!, closeTo(-1.161, 0.002));
      expect(c.foreign, isEmpty);
      final g = applyCheckIn(c, DateTime(2026, 12, 4));
      expect((g.kcal, g.fastAt, g.checkIn), (2400, '2026-12-04', null));
      final l = g.log.single;
      expect((l.day, l.before, l.after, l.applied, l.fast), ('2026-12-04', 2250, 2400, true, true));
      final back = Goals.fromJson(g.toJson())!;
      expect(back.log.single.fast, isTrue);
      expect(back.toJson(), g.toJson());
      expect(_pending(g, DateTime(2026, 12, 5), eat: 2250, tdee: 3550), isNull, reason: 'μία φορά την εβδομάδα');
    });

    test('S1-3: ο εβδομαδιαίος έλεγχος δεν κατεβάζει τον στόχο όσο χάνεις πάνω από 1% την εβδομάδα', () {
      final c = _pending(checkinGoals(), _check, eat: 1400, tdee: 2500)!;
      expect((c.kind, c.tooFast, c.proposal!.current, c.proposal!.target), (CheckKind.same, true, 2250, 2250));
      expect(c.est!.slopeKgWeek, closeTo(-1.004, 0.01));
      expect(c.est!.tdee, closeTo(2504, 2));
    });

    testWidgets('οι κάρτες λένε τι μετρήθηκε, όχι «ασφαλές»', (t) async {
      final low = _pending(checkinGoals(), DateTime(2026, 12, 4), eat: 1400, tdee: 2500)!;
      await _card(t, low, DateTime(2026, 12, 4, 9));
      expect(find.text('Χάνεις πάνω από 1% του βάρους την εβδομάδα'), findsOneWidget);
      expect(find.textContaining('ασφαλές', findRichText: true), findsNothing);
      expect(find.textContaining('γίνεται πιο δύσκολο να κρατήσεις τους μύες', findRichText: true), findsOneWidget);
      expect(find.textContaining('γράφτηκαν κατά μέσο όρο 1.400 kcal τη μέρα, 850 λιγότερες από τον στόχο σου (2.250)', findRichText: true),
          findsOneWidget);
      expect(find.byKey(const ValueKey('checkin-apply')), findsNothing);
      expect(find.byKey(const ValueKey('checkin-ok')), findsOneWidget);

      final same = _pending(checkinGoals(), _check, eat: 1400, tdee: 2500)!;
      await _card(t, same, _check);
      expect(find.textContaining('ο στόχος δεν κατεβαίνει όσο χάνεις τόσο γρήγορα', findRichText: true), findsOneWidget);
      expect(find.textContaining('Τρως κατά μέσο όρο 1.400 kcal, 850 λιγότερες από τον στόχο σου', findRichText: true), findsOneWidget);

      // U3b-6: δύο δεκαδικά στα kg, ώστε το ποσοστό να βγαίνει από τον αριθμό που φαίνεται (1,16 ÷ 86,5 = 1,34%).
      final fast = _pending(checkinGoals(), DateTime(2026, 12, 4), eat: 2250, tdee: 3550)!;
      await _card(t, fast, DateTime(2026, 12, 4, 9));
      expect(find.textContaining('−1,16 kg την εβδομάδα (1,3% του βάρους)', findRichText: true), findsOneWidget);
      expect(find.byKey(const ValueKey('checkin-apply')), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------------------------------------ S1-4
  group('S1-4: όχι δύο αλλαγές μέσα σε λίγες μέρες', () {
    test('έλεγχος που απαντήθηκε λιγότερο από 4 μέρες πριν από μέρα ελέγχου την καλύπτει', () {
      // Γύρος 2 (R2-A-5): μόνο όταν η απάντηση άλλαξε τον στόχο («Εφάρμοσε», γραμμή στο ιστορικό εκείνη τη μέρα). Χωρίς
      // αλλαγή ισχύει ο κανόνας πριν από το S1-4 (δοκιμή στη r2_g1_test).
      Goals changedOn(String day) =>
          checkinGoals().copyWith(addLog: AdaptLog(day: day, tdee: 2600, before: 2250, after: 2100, applied: true));
      final mon = DateTime(2026, 12, 21);
      for (final (day, due) in [
        ('2026-12-20', false),
        ('2026-12-18', false),
        ('2026-12-17', true),
        ('2026-12-16', true),
        ('2026-12-14', true),
      ]) {
        expect(checkInDue(goals: changedOn(day), today: mon, lastCheckIn: day), due, reason: day);
      }
      final answered = changedOn('2026-12-20').copyWith(checkIn: '2026-12-20');
      expect(nextCheckDay(answered, DateTime(2026, 12, 20)), DateTime(2026, 12, 28));
      expect(nextCheckDay(answered, DateTime(2026, 12, 21)), DateTime(2026, 12, 28));
    });

    test('«γρήγορη απώλεια» με «Εφάρμοσε» την Παρασκευή: τη Δευτέρα ο στόχος μένει', () {
      final g = checkinGoals(kcalAdapt: 2400).copyWith(
          fastAt: '2026-12-11',
          addLog: const AdaptLog(day: '2026-12-11', tdee: 2750, before: 2250, after: 2400, applied: true, fast: true));
      expect(lastChangeDay(g), DateTime(2026, 12, 11));
      final c = _pending(g, _check)!;
      expect((c.kind, c.heldDays, c.proposal!.current, c.proposal!.target), (CheckKind.same, 3, 2400, 2400));
    });
  });

  // ------------------------------------------------------------------------------------------------ S1-6, S1-11, U3b-3
  group('σελίδα «Στόχοι»', () {
    testWidgets('S1-6: μετά από «γρήγορη απώλεια» λέει γιατί ανέβηκε, όχι «Από τον τύπο»', (t) async {
      final c = _pending(checkinGoals(), DateTime(2026, 12, 4), eat: 2250, tdee: 3550)!;
      final s = HealthStore()
        ..setProfile(_me)
        ..setGoals(applyCheckIn(c, DateTime(2026, 12, 4)));
      await _pump(t, GoalsPage(store: s, now: DateTime(2026, 12, 5, 9)));
      expect(find.text('2.400 kcal', findRichText: true), findsOneWidget);
      expect(find.textContaining('Από τον τύπο'), findsNothing);
      expect(find.text('Ανέβηκε από 2.250 σε 2.400 (4/12), γιατί έχανες βάρος πολύ γρήγορα'), findsOneWidget);
      expect(find.text('Γρήγορη απώλεια 4/12'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('goals-how')));
      await t.pumpAndSettle();
      expect(find.text('Στόχος από τον τύπο'), findsOneWidget, reason: 'U3b-24');
    });

    testWidgets('S1-11: «Ξανά ο οδηγός» κρατά τον στόχο από τα δεδομένα (εκτίμηση − ρυθμός) και τις μέρες ελέγχου', (t) async {
      final old = Goals(
        aim: GoalAim.lose,
        rate: 0.005,
        activity: 1.5,
        doctor: true,
        since: '2026-10-12',
        kg: 92,
        age: 40,
        heightCm: 180,
        male: true,
        kcalAdapt: 1800,
        tdeeEst: 2250,
        checkIn: '2026-11-09',
        log: const [AdaptLog(day: '2026-11-09', tdee: 2250, before: 1940, after: 1800, applied: true)],
      );
      final store = HealthStore()
        ..setProfile(_me)
        ..setGoals(old);
      await _pump(t, GoalsWizard(store: store, now: _now));
      await t.enterText(find.byKey(const ValueKey('wizard-kg')), '90');
      await t.pumpAndSettle();
      for (var k = 0; k < 5; k++) {
        await t.tap(find.byKey(const ValueKey('wizard-next')));
        await t.pumpAndSettle();
      }
      // 2.250 − 90 × 0,5% × 7.700 ÷ 7 = 1.755 → 1.760· ο τύπος θα έδινε 2.250.
      expect(find.text('1.760 kcal', findRichText: true), findsOneWidget);
      expect(find.byKey(const ValueKey('wizard-from-data')), findsOneWidget);
      expect(find.textContaining('ο τύπος θα έδινε 2.250 kcal'), findsOneWidget);
      expect(find.textContaining('Ο έλεγχος θερμίδων συνεχίζει όπως πριν'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('wizard-next')));
      await t.pumpAndSettle();
      final g = store.goals!;
      expect((g.kcal, g.kcalAdapt, g.tdeeEst, g.since, g.checkIn, g.kg), (1760, 1760, 2250.0, '2026-10-12', '2026-11-09', 90.0));
      expect(g.log.length, 1);
      // Μετά τον οδηγό: η σελίδα «Στόχοι» λέει την επόμενη Δευτέρα ελέγχου (16/11), όχι «πρώτη εκτίμηση».
      expect(find.text('Επόμενος έλεγχος: Δευτέρα 16 Νοεμβρίου'), findsOneWidget);
    });

    testWidgets('S1-11: αλλαγή σκοπού → νέα αρχή, με «Επόμενη εκτίμηση» την 28η μέρα', (t) async {
      final old = Goals(
        aim: GoalAim.lose,
        rate: 0.005,
        activity: 1.5,
        doctor: true,
        since: '2026-10-12',
        kg: 92,
        age: 40,
        heightCm: 180,
        male: true,
        kcalAdapt: 1800,
        tdeeEst: 2250,
        checkIn: '2026-11-09',
        log: const [AdaptLog(day: '2026-11-09', tdee: 2250, before: 1940, after: 1800, applied: true)],
      );
      final store = HealthStore()
        ..setProfile(_me)
        ..setGoals(old);
      await _pump(t, GoalsWizard(store: store, now: _now));
      await t.enterText(find.byKey(const ValueKey('wizard-kg')), '90');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('wizard-next')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('opt-aim-keep')));
      await t.pumpAndSettle();
      for (var k = 0; k < 4; k++) {
        await t.tap(find.byKey(const ValueKey('wizard-next')));
        await t.pumpAndSettle();
      }
      final g = store.goals!;
      expect((g.aim, g.since, g.checkIn, g.kcal), (GoalAim.keep, '2026-11-12', null, 2250));
      expect(find.text('Επόμενη εκτίμηση: Πέμπτη 10 Δεκεμβρίου'), findsOneWidget);
    });

    testWidgets('U3b-3: πριν από την πρώτη εκτίμηση η σελίδα λέει «εκτίμηση», όχι «έλεγχος»', (t) async {
      final s = HealthStore()
        ..setProfile(_me)
        ..setGoals(checkinGoals().copyWith(checkIn: '2026-12-07'));
      await _pump(t, GoalsPage(store: s, now: DateTime(2026, 12, 9, 9)));
      expect(find.text('Πρώτη εκτίμηση: Δευτέρα 14 Δεκεμβρίου'), findsOneWidget);
      expect(find.text('Από τον τύπο, ως την πρώτη εκτίμηση από τα δεδομένα σου'), findsOneWidget);
      expect(find.textContaining('πρώτο έλεγχο'), findsNothing);
    });

    testWidgets('S1-12 / U3b-19: «για 3 g β-γλυκάνες» μόνο με τιμή από την ετικέτα που φτάνει', (t) async {
      final s = HealthStore()
        ..setProfile(_me)
        ..setGoals(checkinGoals());
      await _pump(t, GoalsPage(store: s, now: _now));
      expect(find.textContaining('για 3 g β-γλυκάνες'), findsNothing);
      expect(find.text('40 g · γράψε την ετικέτα'), findsOneWidget);
      expect(find.textContaining('το ίδιο δεν ρίχνει την LDL'), findsOneWidget);
      s.setGoals(checkinGoals().copyWith(betaPer100: 7, branG: 45));
      await t.pumpAndSettle();
      expect(find.text('Πίτουρο βρώμης για 3 g β-γλυκάνες'), findsOneWidget);
      expect(find.text('45 g · από την ετικέτα'), findsOneWidget);
      // Ετικέτα με 5,5 g / 100 g: για 3 g χρειάζονται 55 g· τα 40 g δεν φτάνουν και η γραμμή το λέει.
      s.setGoals(checkinGoals().copyWith(betaPer100: 5.5));
      await t.pumpAndSettle();
      expect(find.text('Πίτουρο βρώμης'), findsOneWidget);
      expect(find.text('40 g · για 3 g β-γλυκάνες: 55 g'), findsOneWidget);
    });

    testWidgets('U3b-14 / U3b-28 / U3b-29 / U3b-12: γραμμές που αλλάζουν 48 dp, «το πλάνο σου», «Σβήσε» κόκκινο, χρώμα διατροφής',
        (t) async {
      final s = HealthStore()
        ..setProfile(_me)
        ..setGoals(checkinGoals().copyWith(legumesWeek: 1));
      await _pump(t, GoalsPage(store: s, now: _now));
      for (final k in ['goals-protein', 'goals-nuts', 'goals-bran', 'goals-legumes', 'goals-fish', 'goals-doc-targets']) {
        expect(t.getSize(find.byKey(ValueKey(k))).height, greaterThanOrEqualTo(48), reason: k);
      }
      expect(find.text(upperGr('Χοληστερίνη · το πλάνο σου')), findsOneWidget);
      // S11-9 / U3b-4: «1 φορά», όχι «1 φορές».
      expect(find.text('1 φορά την εβδομάδα'), findsOneWidget);
      expect(find.text('Λιπαρά'), findsOneWidget);
      expect(find.text('Κορεσμένα λιπαρά'), findsOneWidget);
      expect(find.text('Λίπος'), findsNothing);
      final del = t.widget<TextButton>(find.byKey(const ValueKey('goals-delete')));
      expect(del.style!.foregroundColor!.resolve(<WidgetState>{}), Aigaio.light.bad);
      final theme = Theme.of(t.element(find.byKey(const ValueKey('goals-wizard'))));
      expect(theme.colorScheme.primary, Aigaio.light.foodSolid);
    });

    testWidgets('U3b-22: όρια στο παράθυρο θερμίδων με τελεία χιλιάδων και μονάδα', (t) async {
      final s = HealthStore()
        ..setProfile(_me)
        ..setGoals(checkinGoals());
      await _pump(t, GoalsPage(store: s, now: _now));
      await t.tap(find.byKey(const ValueKey('goals-kcal')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('number-field')), '900');
      await t.tap(find.byKey(const ValueKey('number-ok')));
      await t.pumpAndSettle();
      expect(find.text('Από 1.500 ως 5.000 kcal.'), findsOneWidget);
    });

    testWidgets('S11-12: διορθωμένα στοιχεία μετά τους στόχους → ήρεμη κάρτα και «Υπολόγισε ξανά»', (t) async {
      final s = HealthStore()
        ..setProfile(_me)
        ..setGoals(Goals(
            aim: GoalAim.lose, rate: 0.005, activity: 1.5, doctor: true, since: '2026-11-12', kg: 90, age: 55, heightCm: 180, male: true));
      expect(s.goals!.kcal, 2140);
      await _pump(t, GoalsPage(store: s, now: _now));
      expect(find.byKey(const ValueKey('goals-profile-changed')), findsOneWidget);
      expect(find.textContaining('άνδρας, 55 ετών, 180 cm'), findsOneWidget);
      expect(find.textContaining('άνδρας, 40 ετών, 180 cm'), findsOneWidget);
      expect(s.goals!.age, 55, reason: 'τίποτα δεν αλλάζει μόνο του');
      await t.ensureVisible(find.byKey(const ValueKey('goals-recompute')));
      await t.tap(find.byKey(const ValueKey('goals-recompute')));
      await t.pumpAndSettle();
      expect((s.goals!.age, s.goals!.kcal, s.goals!.since), (40, 2250, '2026-11-12'));
      expect(find.byKey(const ValueKey('goals-profile-changed')), findsNothing);
    });

    test('S11-12: τα γενέθλια μετά την αρχή δεν είναι «αλλαγή στοιχείων»· το ύψος είναι', () {
      final g = Goals(
          aim: GoalAim.lose, rate: 0.005, activity: 1.5, doctor: true, since: '2026-11-12', kg: 90, age: 40, heightCm: 180, male: true);
      expect(goalsWithCurrentProfile(g, _me, DateTime(2027, 2, 1)), isNull);
      const taller = Profile(birthYear: 1986, birthMonth: 1, sex: 'm', heightCm: 181);
      final fixed = goalsWithCurrentProfile(g, taller, DateTime(2027, 2, 1))!;
      expect((fixed.heightCm, fixed.age, fixed.since, fixed.kg), (181.0, 40, '2026-11-12', 90.0));
      // Ένας στόχος κάτω από το όριο του νέου φύλου δεν μένει (1.300 ισχύει για γυναίκα, όχι για άνδρα).
      final woman = Goals(
          aim: GoalAim.lose,
          rate: 0.005,
          activity: 1.5,
          doctor: true,
          since: '2026-11-12',
          kg: 90,
          age: 40,
          heightCm: 180,
          male: false,
          kcalSet: 1300);
      expect(woman.withProfile(male: true, age: 40, heightCm: 180).kcalSet, isNull);
    });
  });

  // ------------------------------------------------------------------------------------------------ οδηγός
  group('οδηγός', () {
    testWidgets('S11-10 / U3b-25: λάθος βάρος → μήνυμα και «Συνέχεια» κλειστό· σωστό → αποθηκεύεται αυτό', (t) async {
      final store = HealthStore()
        ..data = Dashboard.fromJson({...sampleDashboardJson(_now), 'body': bodyJson([(DateTime(2026, 11, 10, 7, 30), 84.0)])})
        ..setProfile(_me);
      await _pump(t, GoalsWizard(store: store, now: _now));
      expect(find.textContaining('84,0 kg · ζυγαριά'), findsOneWidget);
      // U3b-15: το κουμπί για τα στοιχεία είναι πάντα εκεί.
      expect(find.text('Άλλαξε τα στοιχεία μου'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('wizard-kg')), '825');
      await t.pumpAndSettle();
      expect(find.text('Γράψε το βάρος από 30 ως 300 kg, π.χ. 82,5'), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('wizard-next'))).onPressed, isNull);
      await t.enterText(find.byKey(const ValueKey('wizard-kg')), '78,5');
      await t.pumpAndSettle();
      expect(find.text('Γράψε το βάρος από 30 ως 300 kg, π.χ. 82,5'), findsNothing);
      for (var k = 0; k < 4; k++) {
        await t.tap(find.byKey(const ValueKey('wizard-next')));
        await t.pumpAndSettle();
      }
      await t.tap(find.byKey(const ValueKey('opt-doc-no')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('wizard-next')));
      await t.pumpAndSettle();
      expect(find.text('78,5 kg · μέτρια κίνηση'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('wizard-next')));
      await t.pumpAndSettle();
      expect(store.goals!.kg, 78.5);
    });

    testWidgets('S11-2: ζύγιση που δεν μπορεί να είναι δική σου δεν προσυμπληρώνει τον οδηγό', (t) async {
      final store = HealthStore()
        ..data = Dashboard.fromJson({
          ...sampleDashboardJson(_now),
          'body': bodyJson([
            (DateTime(2026, 11, 2, 7, 30), 90.0),
            (DateTime(2026, 11, 4, 7, 30), 89.8),
            (DateTime(2026, 11, 6, 7, 30), 89.6),
            (DateTime(2026, 11, 9, 7, 30), 89.5),
            (DateTime(2026, 11, 11, 7, 0), 45.0),
          ]),
        })
        ..setProfile(_me);
      await _pump(t, GoalsWizard(store: store, now: _now));
      expect(find.textContaining('89,5 kg · ζυγαριά'), findsOneWidget);
      expect(find.textContaining('45,0 kg'), findsNothing);
    });

    testWidgets('U3b-23: «Προτείνεται» στο «λιγότερο λίπος» μόνο με δείκτη μάζας σώματος 25 και πάνω', (t) async {
      Future<int> recommended(String kg) async {
        final store = HealthStore()..setProfile(_me);
        await _pump(t, GoalsWizard(key: ValueKey(kg), store: store, now: _now));
        await t.enterText(find.byKey(const ValueKey('wizard-kg')), kg);
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('wizard-next')));
        await t.pumpAndSettle();
        return find.text('Προτείνεται').evaluate().length;
      }

      expect(await recommended('70'), 0, reason: '70 kg, 180 cm: 21,6');
      expect(await recommended('90'), 1, reason: '90 kg, 180 cm: 27,8');
    });

    testWidgets('S12-06: «Πολλή κίνηση» και «Γρήγορα» αποθηκεύονται ως 1,7 και 0,75% (2.370 kcal)', (t) async {
      final store = HealthStore()..setProfile(_me);
      await _pump(t, GoalsWizard(store: store, now: _now));
      await t.enterText(find.byKey(const ValueKey('wizard-kg')), '90');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('wizard-next')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('wizard-next')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('opt-rate-2')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('wizard-next')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('opt-act-2')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('wizard-next')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('opt-doc-yes')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('wizard-next')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('wizard-next')));
      await t.pumpAndSettle();
      final g = store.goals!;
      expect((g.activity, g.rate, g.kcal), (1.7, 0.0075, 2370));
    });
  });

  // ------------------------------------------------------------------------------------------------ S1-7, S1-8
  group('S1-7 / S1-8: αποθήκευση και κείμενα ρυθμού', () {
    test('S1-7: μη πεπερασμένος αριθμός στους αποθηκευμένους στόχους δεν ρίχνει την εφαρμογή', () {
      final j = checkinGoals().copyWith(kcalSet: 2100, proteinSet: 140, kcalAdapt: 2200).toJson();
      expect(Goals.fromJson({...j, 'age': double.infinity}), isNull, reason: 'απαραίτητο: ξανά ο οδηγός');
      expect(Goals.fromJson({...j, 'kg': double.nan}), isNull);
      for (final k in ['nuts', 'bran', 'leg', 'fish', 'kcal', 'prot', 'ka', 'te', 'beta']) {
        for (final v in [double.infinity, double.negativeInfinity, double.nan]) {
          expect(() => Goals.fromJson({...j, k: v}), returnsNormally, reason: '$k $v');
          expect(Goals.fromJson({...j, k: v}), isNotNull, reason: '$k $v');
        }
      }
      final g = Goals.fromJson({...j, 'nuts': double.infinity, 'kcal': double.infinity, 'ka': double.infinity, 'prot': double.nan})!;
      expect((g.nutsG, g.kcalSet, g.kcalAdapt, g.proteinSet, g.kcal), (defaultNutsG, null, null, null, 2250));
    });

    test('S1-8 / U3b-1: «kg την εβδομάδα» με δύο δεκαδικά, ίδιο με τις θερμίδες δίπλα', () {
      expect(rateKgText(90, 0.005), '0,45 kg την εβδομάδα');
      expect(rateKgText(82.2, 0.005), '0,41 kg την εβδομάδα');
      expect(rateKgText(80, 0.0075), '0,60 kg την εβδομάδα');
    });

    testWidgets('S1-8 / U3b-24: «Πώς υπολογίστηκε»: η γραμμή του ρυθμού ξαναβγάζει τον αριθμό', (t) async {
      final s = HealthStore()
        ..setProfile(_inv)
        ..setGoals(Goals(
            aim: GoalAim.lose, rate: 0.0075, activity: 1.5, doctor: true, since: '2026-11-16', kg: 80, age: 38, heightCm: 171, male: true));
      await _pump(t, GoalsPage(store: s, now: DateTime(2026, 11, 16, 9)));
      await t.tap(find.byKey(const ValueKey('goals-how')));
      await t.pumpAndSettle();
      // 0,75% × 80 × 7.700 ÷ 7 = 660
      expect(find.text('3 · Για 0,60 kg την εβδομάδα'), findsOneWidget);
      expect(find.text('−660 kcal'), findsOneWidget);
      expect(find.text('0,75% του βάρους: 0,75% × 80,0 kg × 7.700 kcal ÷ 7 μέρες'), findsOneWidget);
      expect(find.text('Τύπος Mifflin-St Jeor: 10 × βάρος 80,0 + 6,25 × ύψος 171 − 5 × ηλικία 38 + 5'), findsOneWidget);
      expect(find.text('Στόχος'), findsOneWidget);
    });

    test('S1-12: η EFSA δίνει 20–35% για τα λιπαρά· το ψάρι δεν ρίχνει την LDL', () {
      expect(goalsInfo.compare, contains('20–35%'));
      expect(cholInfo.what, contains('δεν ρίχνει την LDL'));
    });
  });

  // ------------------------------------------------------------------------------------------------ S11-2 φύλακας
  group('S11-2: ζυγίσεις που δεν μπορεί να είναι δικές σου', () {
    test('weightLooksForeign: πάνω από 5% και πάνω από 4 kg από τη διάμεσο, με τουλάχιστον 3 άλλες ζυγίσεις', () {
      expect(weightLooksForeign(45, [90, 89.8, 89.6]), isTrue);
      expect(weightLooksForeign(80, [89.4, 89.3, 89.1]), isTrue);
      expect(weightLooksForeign(85, [89.4, 89.3, 89.1]), isFalse, reason: '4,3 kg < 5% της διαμέσου (4,465)');
      expect(weightLooksForeign(85, [90, 90, 90]), isTrue, reason: '5 kg > 4,5');
      expect(weightLooksForeign(50, [60, 60, 60]), isTrue);
      expect(weightLooksForeign(56.5, [60, 60, 60]), isFalse, reason: '3,5 kg < 4 kg');
      expect(weightLooksForeign(45, [90, 89.8]), isFalse, reason: 'δύο γείτονες δεν φτάνουν για να κριθεί');
      expect(weightLooksForeign(double.nan, [90, 90, 90]), isFalse);
      expect(weightLooksForeign(45, [90, double.nan, 89.8, double.infinity]), isFalse);
      expect(weightGuardDays, 14);
    });

    test('guardedWeights: η ξένη ζύγιση δεν μετρά· αν την ίδια μέρα έγινε και δική σου, μετρά εκείνη', () {
      final day = DateTime(2026, 12, 9);
      final base = simWeights(day); // 18/11 … 9/12: 90,0 → 89,0 kg
      final child = [for (final (d, kg) in base) (d, d.day == 9 && d.month == 12 ? 45.0 : kg)];
      final a = guardedWeights(_body(day, child));
      // Round 2 (g4 · R2-E-2): η 45 kg είναι η ΤΕΛΕΥΤΑΙΑ ζύγιση (καμία μετά): «σε αναμονή», όχι ξένη· δεν μετρά στον έλεγχο
      // θερμίδων ώσπου να κριθεί από την επόμενη (πριν: `foreign == [(9/12, 45)]`).
      expect(a.foreign, isEmpty);
      expect(a.used.any((x) => x.$1 == DateTime(2026, 12, 9)), isFalse);
      expect(a.used.length, base.length - 1);
      final both = [...base, (DateTime(2026, 12, 9, 7, 0), 80.0)];
      final b = guardedWeights(_body(day, both));
      expect(b.foreign, isEmpty);
      expect(b.used.last, (DateTime(2026, 12, 9), 89.0));
      expect(dailyWeights(_body(day, child)), a.used);
    });

    testWidgets('η κάρτα λέει ποια ζύγιση δεν μέτρησε, μία φορά· όχι «γρήγορη απώλεια»', (t) async {
      final day = DateTime(2026, 12, 9);
      final g = checkinGoals().copyWith(checkIn: '2026-12-07');
      // Round 2 (g4 · R2-E-2): το παιδί τη Δευτέρα 7/12, ανάμεσα στις ζυγίσεις σου της 4/12 και της 9/12 (που συμφωνούν
      // μεταξύ τους): ξένη. Πριν ήταν στις 9/12, την τελευταία ζύγιση, που με τον νέο κανόνα είναι «σε αναμονή».
      List<(DateTime, double)> child(List<(DateTime, double)> w) => [for (final (d, kg) in w) (d, d.day == 7 && d.month == 12 ? 45.0 : kg)];
      final c = _pending(g, day, weights: child)!;
      expect((c.kind, c.proposal), (CheckKind.foreign, null));
      expect(c.foreign, [(DateTime(2026, 12, 7), 45.0)]);
      await _card(t, c, DateTime(2026, 12, 9, 9));
      expect(find.text('Μια ζύγιση δεν μέτρησε'), findsOneWidget);
      expect(find.textContaining(foreignWeighText([(DateTime(2026, 12, 7), 45.0)])), findsOneWidget);
      expect(foreignWeighText([(DateTime(2026, 12, 7), 45.0)]),
          'Η ζύγιση ${shortDayDate(DateTime(2026, 12, 7))} (45,0 kg) διαφέρει πολύ από τις άλλες σου ζυγίσεις και δεν μέτρησε.');
      final seen = dismissCheckIn(c, day);
      expect((seen.foreignSeen, seen.kcal, seen.checkIn), ('2026-12-07', 2250, '2026-12-07'));
      expect(Goals.fromJson(seen.toJson())!.foreignSeen, '2026-12-07');
      expect(_pending(seen, DateTime(2026, 12, 10), weights: child), isNull, reason: 'δεν ξαναγράφεται');
    });

    test('αληθινά γρήγορη απώλεια (1,3% την εβδομάδα) δεν κόβεται από τον φύλακα', () {
      final c = _pending(checkinGoals(), DateTime(2026, 12, 4), eat: 2250, tdee: 3550)!;
      expect((c.kind, c.proposal!.target), (CheckKind.fast, 2400));
      expect(c.foreign, isEmpty);
    });
  });

  // ------------------------------------------------------------------------------------------------ S11-3, S11-8, S11-9
  group('S11-3 / S11-8 / S11-9', () {
    test('S11-3: μέρα με αδύνατα πολλές θερμίδες (2.000 g λάδι) δεν μπαίνει στον μέσο όρο', () {
      expect(absurdDayKcal(2745), closeTo(6862.5, 1e-9));
      expect(absurdDayKcal(2000), 6000);
      final c = _pending(checkinGoals(), _check, extra: {DateTime(2026, 12, 2): 19710})!;
      expect((c.kind, c.est!.intakeDays, c.proposal!.target), (CheckKind.proposal, 20, 2100));
      expect(c.est!.meanIntake, closeTo(2250, 1e-6));
      expect(c.absurd, [(DateTime(2026, 12, 2), 19710.0)]);
    });

    testWidgets('S11-3: η κάρτα και το «Πώς βγήκε» τη γράφουν', (t) async {
      final c = _pending(checkinGoals(), _check, extra: {DateTime(2026, 12, 2): 19710})!;
      await _card(t, c, _check);
      expect(find.textContaining('(19.710 kcal) έχει πάρα πολλές θερμίδες για μία μέρα και δεν μέτρησε'), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('checkin-how')));
      await t.tap(find.byKey(const ValueKey('checkin-how')));
      await t.pumpAndSettle();
      expect(find.text('από 20 μέρες· 1 μέρα με πάρα πολλές θερμίδες δεν μέτρησε'), findsOneWidget);
    });

    test('S11-8: οι ζυγίσεις δεν διαβάστηκαν → κάρτα χωρίς κουμπί, ο έλεγχος της εβδομάδας δεν ξοδεύεται', () {
      final c = _pending(checkinGoals(), _check, read: false)!;
      expect(c.kind, CheckKind.unread);
      final g = dismissCheckIn(c, _check);
      expect(g.checkIn, isNull);
      expect(g.log, isEmpty);
      expect(_pending(checkinGoals().copyWith(checkIn: '2026-12-14'), DateTime(2026, 12, 16), read: false), isNull);
      final s = HealthStore()
        ..data = Dashboard.fromJson({...sampleDashboardJson(_check), 'body': {'error': 'x'}})
        ..setGoals(checkinGoals());
      final food = FoodStore.preloaded(foods: basicFoods(), now: _check);
      expect(CheckInSlot.pendingFor(s, food, _check)!.kind, CheckKind.unread);
      // Χωρίς ζυγίσεις στην ανάγνωση και χωρίς σφάλμα (δεν δόθηκε άδεια): καμία κάρτα, ο έλεγχος μένει ανοιχτός.
      final none = HealthStore()
        ..data = Dashboard.fromJson({...sampleDashboardJson(_check)}..remove('body'))
        ..setGoals(checkinGoals());
      expect(CheckInSlot.pendingFor(none, food, _check), isNull);
      expect(none.goals!.checkIn, isNull);
    });

    testWidgets('S11-8: η κάρτα «δεν διαβάστηκαν» δεν έχει κουμπί', (t) async {
      final c = _pending(checkinGoals(), _check, read: false)!;
      await _card(t, c, _check);
      expect(find.text('Έλεγχος θερμίδων: οι ζυγίσεις δεν διαβάστηκαν'), findsOneWidget);
      expect(find.byKey(const ValueKey('checkin-ok')), findsNothing);
      expect(find.byKey(const ValueKey('checkin-apply')), findsNothing);
    });

    test('S11-9 / S1-14 / U3b-16: «λίγα δεδομένα» με σωστό ενικό και χωρίς αντίφαση', () {
      final spread = fewDataText(AdaptStatus.fewWeighIns, days: 21, weighs: 9);
      expect(spread, isNot(contains('χρειάζονται τουλάχιστον 6')));
      expect(spread, contains('μαζεμένες σε λίγες μέρες'));
      expect(fewDataText(AdaptStatus.fewWeighIns, days: 21, weighs: 1), contains('έγινε 1 ζύγιση·'));
      expect(fewDataText(AdaptStatus.fewWeighIns, days: 21, weighs: 0), contains('δεν έγινε καμία ζύγιση'));
      expect(fewDataText(AdaptStatus.fewIntakeDays, days: 1, weighs: 9), contains('μετρά 1 μέρα με φαγητό'));
      expect(fewDataText(AdaptStatus.fewIntakeDays, days: 10, weighs: 9), contains('μετράνε 10 μέρες με φαγητό'));
      // Ακριβώς στο όριο: ποτέ «1,0% … πάνω από 1%».
      expect(lossPctText(1.34), '1,3%');
      expect(lossPctText(1.02), '1,02%');
      expect(lossPctText(1.001), 'λίγο πάνω από 1%');
    });

    testWidgets('S11-9 / U3b-20 / U3b-5 / U3b-27: «Πώς βγήκε» με 20 από 21 μέρες', (t) async {
      final c = _pending(checkinGoals(), _check, skip: {5})!;
      expect((c.kind, c.est!.intakeDays, c.kgNow), (CheckKind.proposal, 20, 89.2));
      await _card(t, c, _check);
      // U3b-27: ο τύπος με τον αριθμό του «Πώς υπολογίστηκε» (2.745), όχι 2.750.
      expect(find.textContaining('όχι 2.745 που υπολόγισε ο τύπος', findRichText: true), findsOneWidget);
      expect(t.widget<BigValue>(find.byKey(const ValueKey('checkin-target'))).unit, 'kcal', reason: 'U3b-7');
      await t.ensureVisible(find.byKey(const ValueKey('checkin-how')));
      await t.tap(find.byKey(const ValueKey('checkin-how')));
      await t.pumpAndSettle();
      expect(find.text('από 20 μέρες· 1 μέρα με λίγη ή καθόλου καταγραφή δεν μέτρησε'), findsOneWidget);
      expect(find.text('2 · Αλλαγή βάρους την εβδομάδα'), findsOneWidget);
      expect(find.textContaining('εβδ.'), findsNothing);
      // 89,2 × 0,5% × 7.700 ÷ 7 = 490,6 → 491
      expect(find.text('4 · Για 0,45 kg την εβδομάδα'), findsOneWidget);
      expect(find.text('−491 kcal'), findsOneWidget);
      expect(find.text('0,5% × 89,2 kg × 7.700 ÷ 7'), findsOneWidget);
      // U3b-5: η διαφορά των αριθμών όπως φαίνονται.
      final shown = (c.est!.tdee / 10).round() * 10;
      expect(find.textContaining('Ο τύπος έλεγε 2.745: έπεφτε ${thousands(2745 - shown)} kcal ψηλά'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------------------------------------ χοληστερίνη
  group('Χοληστερίνη (S2-2, S11-9, U3b-8)', () {
    final mon = DateTime(2026, 11, 16), tue = DateTime(2026, 11, 17);
    LogEntry e(DateTime d, Food f, double g) =>
        LogEntry(id: '${f.id}-${d.day}-$g', day: '${d.year}-${two(d.month)}-${two(d.day)}', meal: Meal.lunch, food: f, grams: g, time: DateTime(d.year, d.month, d.day, 13));
    Future<void> page(WidgetTester t, List<LogEntry> entries, DateTime today) =>
        _pump(t, CholesterolPage(food: FoodStore.preloaded(foods: basicFoods(), entries: entries, now: today), goals: checkinGoals(), today: today));

    testWidgets('S2-2: τρόφιμο χωρίς τιμή κορεσμένων → «≥» και η μέρα γράφεται', (t) async {
      final nuts = foodNamed('Καρύδια');
      final j = nuts.toJson();
      final noSat = Food.fromJson({...j, 'id': 'x-no-sat', 'n': {...(j['n'] as Map)}..remove(Nk.satFat)});
      expect(noSat.n.has(Nk.satFat), isFalse);
      final w = CholWeek([(mon, CholDay([e(mon, noSat, 250)]))], goalKcal: 2250);
      expect((w.fullDays, w.daysSatUnknown), (1, 1));
      await page(t, [e(mon, noSat, 250)], tue);
      expect(find.byKey(const ValueKey('chol-sat-unknown')), findsOneWidget);
      expect(find.textContaining('μέσος όρος ≥ '), findsOneWidget);
      await page(t, [e(mon, nuts, 250)], tue);
      expect(find.byKey(const ValueKey('chol-sat-unknown')), findsNothing);
      expect(find.textContaining('μέσος όρος ≥ '), findsNothing);
    });

    testWidgets('S11-9: «από 1 μέρα» την Τρίτη, «—» τη Δευτέρα (ποτέ «0 από 0 μέρες»)', (t) async {
      final nuts = foodNamed('Καρύδια');
      await page(t, [e(mon, nuts, 250)], tue);
      expect(find.textContaining('από 1 μέρα', findRichText: true), findsWidgets);
      expect(find.textContaining('από 1 μέρες', findRichText: true), findsNothing);
      await page(t, [], mon);
      expect(find.textContaining('από 0 μέρες', findRichText: true), findsNothing);
    });

    testWidgets('U3b-8: όσπρια μαζί με σήμερα, όπως στην κάρτα', (t) async {
      final lentils = foodNamed('Φακές (βρασμένες)');
      await page(t, [e(mon, lentils, 100), e(tue, lentils, 100)], tue);
      expect(find.textContaining('2 / 4 φορές', findRichText: true), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------------------------------------ Διατροφή με στόχους
  testWidgets('U3a-9 / U3b-21 / U3b-27: «Λιπαρά», «Κορεσμένα λιπαρά», ίνες 29,6 g = «Έπιασες τον στόχο»', (t) async {
    final fib = Food(
      id: 'x-fib',
      name: 'Δοκιμαστικό με ίνες',
      cat: 'Δοκιμή',
      source: 'Ετικέτα',
      n: Nutrients({
        Nk.kcal: const NValue(200),
        Nk.protein: const NValue(10),
        Nk.carbs: const NValue(20),
        Nk.sugars: const NValue(2),
        Nk.fat: const NValue(12),
        Nk.satFat: const NValue(1),
        Nk.fiber: const NValue(29.6),
        Nk.salt: const NValue(0.1),
      }),
    );
    final entry = LogEntry(id: 'f1', day: '2026-11-12', meal: Meal.lunch, food: fib, grams: 100, time: DateTime(2026, 11, 12, 13));
    await _pump(
        t,
        Scaffold(
            body: SingleChildScrollView(
                child: GoalsSummaryCard(totals: Totals([entry]), goals: checkinGoals(), today: true, health: HealthStore()))));
    expect(find.text('Κορεσμένα λιπαρά'), findsOneWidget);
    expect(find.text('Λιπαρά'), findsOneWidget);
    expect(find.text('Λίπος'), findsNothing);
    expect(find.text('Έπιασες τον στόχο'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.text('12 g / 63–88 g'), findsOneWidget);
    expect(find.text('0,1 g / κάτω από 5 g'), findsOneWidget);
  });

  // ------------------------------------------------------------------------------------------------ μέση
  group('μέση (S1-13, S12-04, U3b-17, U3b-25)', () {
    test('S1-13: τρεις μετρήσεις σε ίσες αποστάσεις → η μεσαία', () {
      expect(const WaistEntry('2026-11-13', [97, 98.5, 100]).cm, 98.5);
      expect(const WaistEntry('2026-11-13', [98, 100, 99]).cm, 99.0);
      expect(const WaistEntry('2026-11-13', [97.3, 98.1, 98.9]).cm, 98.1);
      expect(const WaistEntry('2026-11-13', [98, 100.5, 99]).cm, 98.5, reason: 'το χαμηλό ζευγάρι είναι πιο κοντά');
      expect(const WaistEntry('2026-11-13', [98, 101, 100.5]).cm, closeTo(100.75, 1e-9), reason: 'το ψηλό ζευγάρι είναι πιο κοντά');
    });

    test('S12-04: εύρος αναφοράς ESC 2021', () {
      final m = waistRef(true), f = waistRef(false);
      expect((m.ok, m.high), (94.0, 102.0));
      expect((f.ok, f.high), (80.0, 88.0));
    });

    testWidgets('U3b-17 / U3b-25: η υπόδειξη για την 3η φεύγει όταν ζητηθεί· λάθος τιμή → μήνυμα', (t) async {
      final store = HealthStore()..setProfile(_me);
      await _pump(
          t,
          Builder(
              builder: (context) => Scaffold(
                  body: Center(
                      child: FilledButton(
                          key: const ValueKey('open'), onPressed: () => openWaistSheet(context, store, now: _now), child: const Text('open'))))));
      await t.tap(find.byKey(const ValueKey('open')));
      await t.pumpAndSettle();
      expect(find.text('Αν διαφέρουν πάνω από 1 cm, θα ζητηθεί και τρίτη.'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('waist-0')), '97');
      await t.enterText(find.byKey(const ValueKey('waist-1')), '98,5');
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('waist-2')), findsOneWidget);
      expect(find.text('Αν διαφέρουν πάνω από 1 cm, θα ζητηθεί και τρίτη.'), findsNothing);
      await t.enterText(find.byKey(const ValueKey('waist-1')), '985');
      await t.pumpAndSettle();
      expect(find.text('Από 50 ως 200 cm'), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('waist-save'))).onPressed, isNull);
    });
  });

  // ------------------------------------------------------------------------------------------------ «Τα στοιχεία μου»
  group('«Τα στοιχεία μου» (U3a-2, U3a-16, U3a-17)', () {
    test('U3a-2 / U3b-18: γράμματα πάνω σε γεμάτο χρώμα με αντίθεση τουλάχιστον 4,5:1 σε όλα τα θέματα', () {
      for (final c in [...Aigaio.dayThemes, ...Aigaio.nightThemes]) {
        expect(Aigaio.contrast(Aigaio.inkOn(c.body), c.body), greaterThanOrEqualTo(4.5), reason: '${c.id} body');
        expect(Aigaio.contrast(c.onSolid, c.foodSolid), greaterThanOrEqualTo(4.5), reason: '${c.id} foodSolid');
      }
    });

    testWidgets('U3a-16 / U3a-17: λάθος ύψος → μήνυμα, τίποτα δεν αποθηκεύεται· μέρες 48 dp', (t) async {
      final store = HealthStore();
      await _pump(t, MePage(store: store));
      await t.enterText(find.byKey(const ValueKey('me-height')), '1,80');
      await t.pumpAndSettle();
      expect(find.text('Γράψε το ύψος σε εκατοστά, από 100 ως 250, π.χ. 180'), findsOneWidget);
      expect(store.profile.heightCm, isNull);
      await t.enterText(find.byKey(const ValueKey('me-height')), '180');
      await t.pumpAndSettle();
      expect(store.profile.heightCm, 180.0);
      expect(find.text('Γράψε το ύψος σε εκατοστά, από 100 ως 250, π.χ. 180'), findsNothing);
      for (final k in ['me-weigh-1', 'me-waist-5']) {
        expect(t.getSize(find.byKey(ValueKey(k))).height, greaterThanOrEqualTo(48), reason: k);
      }
    });
  });

  // ------------------------------------------------------------------------------------------------ S12-06, S12-07
  group('S12-06: στόχοι, όρια των τύπων', () {
    test('γυναίκα, κίνηση, ρυθμοί, όριο ασφαλείας', () {
      final f = computeGoals(male: false, age: 35, heightCm: 165, kg: 70, aim: GoalAim.keep, rate: 0, activity: 1.4, doctor: false);
      expect(f.bmr, closeTo(1395.25, 1e-9));
      expect(f.tdee, closeTo(1953.35, 1e-9));
      expect((f.kcal, f.protein, f.fatLo, f.fatHi, f.satMax, f.carbsEst), (1950, 110, 54, 76, 22, 231));
      final f2 = computeGoals(male: false, age: 35, heightCm: 165, kg: 70, aim: GoalAim.lose, rate: 0.005, activity: 1.5, doctor: true);
      expect(f2.delta, closeTo(-385, 1e-9));
      expect((f2.kcal, f2.floored, f2.satMax), (1710, false, 11));
      GoalCalc m(GoalAim aim, double rate, double pal) =>
          computeGoals(male: true, age: 40, heightCm: 180, kg: 90, aim: aim, rate: rate, activity: pal, doctor: true);
      expect(m(GoalAim.keep, 0, 1.4).kcal, 2560);
      expect(m(GoalAim.keep, 0, 1.7).kcal, 3110);
      expect(m(GoalAim.lose, 0.0025, 1.5).kcal, 2500);
      expect(m(GoalAim.lose, 0.0075, 1.5).kcal, 2000);
      expect(m(GoalAim.gain, 0.005, 1.5).kcal, 3240);
      expect(m(GoalAim.lose, 0.005, 1.5).carbsEst, 249);
      final edge = computeGoals(male: true, age: 70, heightCm: 160, kg: 41.5, aim: GoalAim.keep, rate: 0, activity: 1.4, doctor: false);
      expect((edge.kcal, edge.floored), (1500, false), reason: '1.498 → 1.500 στα 10: όχι «ανέβηκε στο όριο»');
      final under = computeGoals(male: true, age: 70, heightCm: 160, kg: 41, aim: GoalAim.keep, rate: 0, activity: 1.4, doctor: false);
      expect((under.kcal, under.floored), (1500, true));
      expect(loseRates, [0.0025, 0.005, 0.0075]);
      expect(gainRates, [0.0025, 0.005]);
      expect(activityLevels, [1.4, 1.5, 1.7]);
      final own = checkinGoals(kcalSet: 2100);
      expect((own.fatLo, own.fatHi, own.satMax), (58, 82, 14));
    });
  });

  group('S12-07: αυτόματη διόρθωση, όρια', () {
    final today = DateTime(2026, 12, 7);
    Goals g({int? kcalAdapt}) => checkinGoals(kcalAdapt: kcalAdapt);
    ({Map<DateTime, double> intake, List<(DateTime, double)> weights}) flat(double eat,
        {Set<int> low = const {}, double lowKcal = 1349, List<int>? weighDaysBack}) {
      final intake = <DateTime, double>{};
      final weights = <(DateTime, double)>[];
      for (var k = 21; k >= 1; k--) {
        final d = DateTime(today.year, today.month, today.day - k);
        intake[d] = low.contains(k) ? lowKcal : eat;
        if (weighDaysBack == null && (d.weekday == 1 || d.weekday == 3 || d.weekday == 5)) weights.add((d, 90.0));
      }
      if (weighDaysBack != null) {
        for (final k in weighDaysBack) {
          weights.add((DateTime(today.year, today.month, today.day - k), 90.0));
        }
      }
      return (intake: intake, weights: weights);
    }

    ({AdaptStatus status, Expenditure? est}) est(({Map<DateTime, double> intake, List<(DateTime, double)> weights}) s) =>
        estimateExpenditure(intake: s.intake, weights: s.weights, today: today, formulaTdee: 2745, goalKcal: 2250);

    test('70% και 140% του τύπου', () {
      expect(est(flat(1900)).status, AdaptStatus.implausible);
      expect((est(flat(1950)).status, est(flat(1950)).est!.tdee), (AdaptStatus.ok, 1950.0));
      expect(est(flat(3800)).status, AdaptStatus.ok);
      expect(est(flat(3900)).status, AdaptStatus.implausible);
    });

    test('ακριβώς 14 μέρες φαγητού, ακριβώς 1.350 kcal', () {
      const spread = {1, 4, 7, 10, 13, 16, 19};
      final r14 = est(flat(2250, low: spread));
      expect((r14.status, r14.est!.intakeDays), (AdaptStatus.ok, 14));
      expect(est(flat(2250, low: {...spread, 21})).status, AdaptStatus.fewIntakeDays);
      final at = est(flat(1350));
      expect((at.status, at.est!.intakeDays), (AdaptStatus.implausible, 21), reason: 'μετρούν (1.350 = 60%), αλλά 1.350 < 70% του τύπου');
      expect(est(flat(1349)).status, AdaptStatus.fewIntakeDays);
    });

    test('ακριβώς 6 ζυγίσεις σε 14 μέρες', () {
      expect(est(flat(2250, weighDaysBack: [21, 18, 15, 12, 9, 7])).status, AdaptStatus.ok);
      expect(est(flat(2250, weighDaysBack: [21, 18, 15, 12, 9])).status, AdaptStatus.fewWeighIns);
      expect(est(flat(2250, weighDaysBack: [21, 18, 15, 12, 10, 8])).status, AdaptStatus.fewWeighIns);
    });

    test('βήμα +150 και «κάτω από 30»', () {
      Expenditure e(double tdee) =>
          Expenditure(tdee: tdee, meanIntake: 2250, slopeKgWeek: 0, intakeDays: 21, weighIns: 9, from: DateTime(2026, 11, 16), to: DateTime(2026, 12, 6));
      final up = proposeTarget(goals: g(), est: e(3000), kgNow: 89);
      expect((up.target, up.change), (2400, 150));
      for (final (cur, target, same) in [(2140, 2110, false), (2130, 2130, true), (2080, 2110, false), (2090, 2090, true)]) {
        final p = proposeTarget(goals: g(kcalAdapt: cur), est: e(2600), kgNow: 89);
        expect((p.target, p.same, p.withinNoise), (target, same, false), reason: '$cur');
      }
    });

    test('γρήγορη απώλεια: μία φορά την εβδομάδα, κλίση στο όριο, άπλωμα 10 μέρες', () {
      final answered = checkinGoals().copyWith(fastAt: '2026-12-04', checkIn: '2026-12-07');
      expect(_pending(answered, DateTime(2026, 12, 10), eat: 2250, tdee: 3550), isNull, reason: '6 μέρες');
      expect(_pending(answered, DateTime(2026, 12, 11), eat: 2250, tdee: 3550)!.kind, CheckKind.fast, reason: '7 μέρες');
      List<(DateTime, double)> line(double s) => [for (final d in [0, 2, 4, 7, 9, 11]) (DateTime(2026, 11, 23 + d), 88.0 - s * d / 7)];
      final day = DateTime(2026, 12, 4);
      expect(fastLossCheck(goals: checkinGoals(), weights: line(0.86), today: day), isNull);
      expect(fastLossCheck(goals: checkinGoals(), weights: line(0.90), today: day)!.change, 150);
      final ten = [
        (DateTime(2026, 11, 23), 88.0),
        (DateTime(2026, 11, 25), 88.0 - 1.2 * 2 / 7),
        (DateTime(2026, 11, 30), 88.0 - 1.2),
        (DateTime(2026, 12, 3), 88.0 - 1.2 * 10 / 7),
      ];
      expect(fastLossCheck(goals: checkinGoals(), weights: ten, today: day)!.change, 150);
      final nine = [...ten.take(3), (DateTime(2026, 12, 2), 88.0 - 1.2 * 9 / 7)];
      expect(fastLossCheck(goals: checkinGoals(), weights: nine, today: day), isNull);
    });
  });
}
