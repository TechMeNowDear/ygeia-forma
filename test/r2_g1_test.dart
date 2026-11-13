// Έλεγχος 13/11, γύρος 2 (g1): διόρθωση θερμίδων (R2-A-1, R2-A-2, R2-A-3, R2-A-5) και «δικό μου πρώτο» στην αναζήτηση
// (R2-A-4). Όλοι οι αριθμοί είναι φανταστικοί (δημόσιο repo). Οι αναμενόμενες τιμές βγήκαν από τον κανόνα όπως γράφεται,
// σε αντίγραφο Python έξω από το repo, όχι από τον κώδικα που δοκιμάζεται. Σε κάθε δοκιμή γράφεται και τι έβγαινε πριν.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/adaptive.dart';
import 'package:ygeia_forma/adaptive_check.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/format.dart' show daysBetween;
import 'package:ygeia_forma/goals.dart';
import 'package:ygeia_forma/pages/checkin_card.dart';
import 'package:ygeia_forma/pages/goals_page.dart';
import 'package:ygeia_forma/profile.dart';
import 'package:ygeia_forma/theme.dart';

import 'sample_checkin.dart';
import 'sample_data.dart';
import 'sample_food.dart';

/// Φανταστικός χρήστης Β: άνδρας 40 ετών, 180 cm (ίδιος με τα checkinGoals: 90 kg, τύπος 2.745, στόχος 2.250).
const _me = Profile(birthYear: 1985, birthMonth: 12, sex: 'm', heightCm: 180);

/// Φανταστικός χρήστης Α από Δευτέρα 16/11: άνδρας 38 ετών, 171 cm, 80 kg, −0,5%/εβδ., μέτρια κίνηση (στόχος 2.090).
Goals _invGoals() => Goals(
      aim: GoalAim.lose,
      rate: 0.005,
      activity: 1.5,
      doctor: true,
      since: '2026-11-16',
      kg: 80,
      age: 38,
      heightCm: 171,
      male: true,
    );

Map<DateTime, double> Function(DateTime, DateTime) _intakeOf(Map<DateTime, double> m) => (a, b) => {
      for (final e in m.entries)
        if (!e.key.isBefore(a) && !e.key.isAfter(b)) e.key: e.value,
    };

/// Ζυγίσεις Δευτέρα, Τετάρτη, Παρασκευή (μία τη μέρα, όπως τις δίνει ο φύλακας), από [kg0] με απώλεια [pctWeek] του
/// βάρους την εβδομάδα, στρογγυλεμένες στα 0,1 kg· [dip]: τόσα kg κάτω από την τάση εκείνες τις μέρες.
List<(DateTime, double)> _weights(DateTime from, DateTime to, double kg0, double pctWeek, {Map<DateTime, double> dip = const {}}) {
  final out = <(DateTime, double)>[];
  var kg = kg0;
  for (var d = from; !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
    if (d.weekday == 1 || d.weekday == 3 || d.weekday == 5) out.add((d, ((kg - (dip[d] ?? 0.0)) * 10).round() / 10));
    kg -= pctWeek * kg / 7;
  }
  return out;
}

/// Ο χρήστης Α από 16/11: φαγητό 2.090 kcal κάθε μέρα (εκτός από [unlogged]), καίει 2.540· ζυγίσεις Δευτέρα, Τετάρτη,
/// Παρασκευή, [dip] kg κάτω από την τάση τις μέρες [unlogged] (αρρώστια: νερά, γλυκογόνο).
({Map<DateTime, double> intake, List<(DateTime, double)> weights}) _world(
    {bool Function(DateTime)? unlogged, double dip = 0}) {
  final intake = <DateTime, double>{};
  final weights = <(DateTime, double)>[];
  var kg = 80.0;
  for (var d = DateTime(2026, 11, 16); !d.isAfter(DateTime(2027, 3, 1)); d = DateTime(d.year, d.month, d.day + 1)) {
    final off = unlogged != null && unlogged(d);
    if (d.weekday == 1 || d.weekday == 3 || d.weekday == 5) weights.add((d, kg - (off ? dip : 0.0)));
    if (!off) intake[d] = 2090;
    kg += (2090 - 2540) / kcalPerKg;
  }
  return (intake: intake, weights: weights);
}

List<(DateTime, double)> _upTo(List<(DateTime, double)> w, DateTime today) => [
      for (final x in w)
        if (!x.$1.isAfter(today)) x,
    ];

Future<void> _pump(WidgetTester t, Widget w) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = const Size(400, 2600);
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: w));
  await t.pumpAndSettle();
}

Future<void> _card(WidgetTester t, CheckIn c, DateTime now) => _pump(
    t, Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: CheckInCard(check: c, store: HealthStore(), now: now))));

/// Τα checkinGoals μετά από δύο «+150» της γρήγορης απώλειας: 2.250 → 2.400 (Παρασκευή 11/12) → 2.550 (18/12).
Goals _raisedTwice() => checkinGoals(kcalAdapt: 2550)
    .copyWith(
        fastAt: '2026-12-18',
        checkIn: '2026-12-21',
        addLog: const AdaptLog(day: '2026-12-11', tdee: 2750, before: 2250, after: 2400, applied: true, fast: true))
    .copyWith(addLog: const AdaptLog(day: '2026-12-18', tdee: 2750, before: 2400, after: 2550, applied: true, fast: true));

/// Το ημερολόγιο του [_raisedTwice]: τρως ακριβώς τον στόχο που ίσχυε κάθε μέρα (μείον [less]), 4–24/12.
Map<DateTime, double> _ateTargets({double less = 0}) => {
      for (var d = 4; d <= 24; d++) DateTime(2026, 12, d): (d <= 11 ? 2250 : (d <= 18 ? 2400 : 2550)) - less,
    };

Food _own(String id, String name, double kcal, {String? brand}) => Food(
      id: id,
      name: name,
      cat: 'Τα προϊόντα μου',
      source: 'Ετικέτα',
      brand: brand,
      n: Nutrients({Nk.kcal: NValue(kcal)}),
    );

void main() {
  // ------------------------------------------------------------------------------------------------ R2-A-1
  group('R2-A-1: το φαγητό κάθε μέρας με τον στόχο που ίσχυε εκείνη τη μέρα', () {
    test('targetOn: το «πριν» της πρώτης αλλαγής εκείνη τη μέρα ή αργότερα· μετά την τελευταία, ο τωρινός', () {
      final g = _raisedTwice();
      expect(g.kcal, 2550);
      for (final (day, want) in [(4, 2250), (10, 2250), (11, 2250), (12, 2400), (17, 2400), (18, 2400), (19, 2550), (25, 2550)]) {
        expect(targetOn(g, DateTime(2026, 12, day)), want, reason: '$day/12');
      }
      // Χωρίς αλλαγές από κάρτα: πάντα ο τωρινός (και ο δικός σου αριθμός).
      expect(targetOn(checkinGoals(), DateTime(2026, 12, 1)), 2250);
      expect(targetOn(checkinGoals(kcalSet: 2300), DateTime(2026, 12, 1)), 2300);
      // «Όχι τώρα» (χωρίς αλλαγή) δεν μετρά.
      final declined = checkinGoals().copyWith(addLog: const AdaptLog(day: '2026-12-14', tdee: 2600, before: 2250, after: 2250, applied: false));
      expect(targetOn(declined, DateTime(2026, 12, 10)), 2250);
      expect(meanTargetOn(g, _ateTargets().keys), closeTo(2385.714, 0.001));
      expect(meanTargetOn(g, const []), 2550.0);
    });

    test('γρήγορη απώλεια: τρως ακριβώς τους στόχους σου → +150 (πριν: «τρως 160 λιγότερες», καμία πρόταση)', () {
      final g = _raisedTwice();
      final today = DateTime(2026, 12, 25);
      final c = pendingCheckIn(
          goals: g,
          today: today,
          weights: _weights(DateTime(2026, 11, 16), today, 90, 0.013),
          intake: _intakeOf(_ateTargets()))!;
      expect(c.kind, CheckKind.fast);
      expect((c.proposal!.current, c.proposal!.target), (2550, 2700));
      expect(c.fastIntake!, closeTo(2385.714, 0.001));
      expect(c.fastTarget!, closeTo(2385.714, 0.001));
      expect((c.fastIntakeDays, c.fastDays, c.kgNow), (21, 21, 83.7));
      expect(c.fastSlope!, closeTo(-1.1119, 0.0005));
    });

    testWidgets('γρήγορη απώλεια: τρως 300 κάτω από κάθε στόχο → καμία πρόταση, η διαφορά από τους στόχους εκείνων των ημερών', (t) async {
      final g = _raisedTwice();
      final today = DateTime(2026, 12, 25);
      final c = pendingCheckIn(
          goals: g,
          today: today,
          weights: _weights(DateTime(2026, 11, 16), today, 90, 0.013),
          intake: _intakeOf(_ateTargets(less: 300)))!;
      expect((c.kind, c.proposal), (CheckKind.fast, null));
      expect(c.fastIntake!, closeTo(2085.714, 0.001));
      expect(c.fastTarget!, closeTo(2385.714, 0.001));
      await _card(t, c, DateTime(2026, 12, 25, 9));
      expect(
          find.textContaining(
              'γράφτηκαν κατά μέσο όρο 2.090\u00A0kcal τη μέρα, 300 λιγότερες από τους στόχους σου αυτές τις μέρες (κατά μέσο όρο '
              '2.390). Αν τα έγραψες όλα, τρως πολύ λίγο: φάε πιο κοντά στον στόχο (2.550). Ο στόχος μένει ίδιος.',
              findRichText: true),
          findsOneWidget);
      expect(find.byKey(const ValueKey('checkin-apply')), findsNothing);
    });

    test('εβδομαδιαίος έλεγχος: ο μέσος στόχος των ημερών που μπήκαν στον μέσο όρο (estTarget)', () {
      // 2.250 → 2.400 (Δευτέρα 14/12) → 2.550 (γρήγορη απώλεια 18/12) → 2.700 (Δευτέρα 21/12)· τρως κάθε μέρα τον στόχο της.
      final g = checkinGoals(kcalAdapt: 2700)
          .copyWith(
              tdeeEst: 3300,
              checkIn: '2026-12-21',
              fastAt: '2026-12-18',
              addLog: const AdaptLog(day: '2026-12-14', tdee: 3300, before: 2250, after: 2400, applied: true))
          .copyWith(addLog: const AdaptLog(day: '2026-12-18', tdee: 2750, before: 2400, after: 2550, applied: true, fast: true))
          .copyWith(addLog: const AdaptLog(day: '2026-12-21', tdee: 3300, before: 2550, after: 2700, applied: true));
      final diary = <DateTime, double>{
        for (var d = DateTime(2026, 11, 23); !d.isAfter(DateTime(2026, 12, 27)); d = DateTime(d.year, d.month, d.day + 1))
          d: targetOn(g, d).toDouble(),
      };
      expect({...diary.values}, {2250.0, 2400.0, 2550.0, 2700.0});
      final mon = DateTime(2026, 12, 28);
      final c = pendingCheckIn(goals: g, today: mon, weights: _weights(DateTime(2026, 11, 16), mon, 90, 0.013), intake: _intakeOf(diary))!;
      expect((c.kind, c.est!.windowDays, c.est!.from, c.est!.intakeDays), (CheckKind.proposal, 35, DateTime(2026, 11, 23), 35));
      // (22 × 2.250 + 4 × 2.400 + 3 × 2.550 + 6 × 2.700) ÷ 35 = 2.370
      expect(c.est!.meanIntake, closeTo(2370, 1e-6));
      expect(c.estTarget!, closeTo(2370, 1e-6));
    });

    testWidgets('εβδομαδιαίος έλεγχος, «χάνεις πάνω από 1%»: «τρως λιγότερες» μόνο σε σχέση με τους στόχους των ημερών', (t) async {
      final g = checkinGoals(kcalAdapt: 2700);
      Expenditure est(double eaten) => Expenditure(
          tdee: 3100, meanIntake: eaten, slopeKgWeek: -1.0, intakeDays: 35, weighIns: 15, from: DateTime(2026, 11, 23), to: DateTime(2026, 12, 27));
      CheckIn same(double eaten, double? estTarget) => CheckIn(
          kind: CheckKind.same,
          goals: g,
          status: AdaptStatus.ok,
          est: est(eaten),
          proposal: AdaptProposal(current: 2700, target: 2700, est: est(eaten), fastLoss: false, floored: false),
          kgNow: 84,
          tooFast: true,
          estTarget: estTarget);
      final now = DateTime(2026, 12, 28, 9);
      // Έτρωγε ακριβώς τους στόχους του (μέσος όρος 2.370): μόνο ότι ο στόχος δεν κατεβαίνει. Πριν: «330 λιγότερες».
      await _card(t, same(2370, 2370), now);
      expect(find.textContaining('ο στόχος δεν κατεβαίνει όσο χάνεις τόσο γρήγορα', findRichText: true), findsOneWidget);
      expect(find.textContaining('λιγότερες', findRichText: true), findsNothing);
      // Ο στόχος δεν άλλαξε μέσα στο παράθυρο: το κείμενο όπως πριν.
      await _card(t, same(2370, 2700), now);
      expect(find.textContaining('Τρως κατά μέσο όρο 2.370\u00A0kcal, 330 λιγότερες από τον στόχο σου: φάε πιο κοντά στον στόχο.', findRichText: true),
          findsOneWidget);
      // Χωρίς estTarget (παλιά κάρτα): όπως πριν.
      await _card(t, same(2370, null), now);
      expect(find.textContaining('330 λιγότερες από τον στόχο σου', findRichText: true), findsOneWidget);
      // Έτρωγε 270 κάτω από τους στόχους εκείνων των ημερών: το λέει, με τον μέσο όρο τους.
      await _card(t, same(2100, 2370), now);
      expect(
          find.textContaining(
              'Τρως κατά μέσο όρο 2.100\u00A0kcal, 270 λιγότερες από τους στόχους σου αυτές τις εβδομάδες (κατά μέσο όρο 2.370): φάε πιο '
              'κοντά στον στόχο.',
              findRichText: true),
          findsOneWidget);
    });
  });

  // ------------------------------------------------------------------------------------------------ R2-A-2
  group('R2-A-2: κενό που άρχισε πριν από τις 42 μέρες κόβει και αυτό το παράθυρο', () {
    // Άρρωστος 11–20/1/2027: τίποτα στο ημερολόγιο, ζυγίζεται κανονικά, 1,5 kg κάτω από την τάση (νερά).
    final w = _world(unlogged: (d) => !d.isBefore(DateTime(2027, 1, 11)) && !d.isAfter(DateTime(2027, 1, 20)), dip: 1.5);
    final since = DateTime(2026, 11, 16);
    final formula = _invGoals().calc.tdee;

    test('1/3: παράθυρο 35 μερών από 25/1 με την αληθινή κατανάλωση (πριν: 42 μέρες από 18/1, 2.377)', () {
      final t = DateTime(2027, 3, 1);
      final r = estimateExpenditure(
          intake: w.intake, weights: _upTo(w.weights, t), today: t, formulaTdee: formula, goalKcal: 2090, since: since);
      expect((r.status, r.est!.windowDays, r.est!.from, r.est!.intakeDays), (AdaptStatus.ok, 35, DateTime(2027, 1, 25), 35));
      expect(r.est!.tdee, closeTo(2540, 1));
      final gap = foodGap(intake: w.intake, today: t, formulaTdee: formula, goalKcal: 2090, since: since)!;
      expect((gap.to, gap.restart), (DateTime(2027, 1, 20), DateTime(2027, 1, 21)));
      // Τις προηγούμενες Δευτέρες, όπως πριν (το κενό χωρούσε ολόκληρο στις 42 μέρες).
      for (final (day, window) in [(DateTime(2027, 2, 15), 21), (DateTime(2027, 2, 22), 28)]) {
        final e = estimateExpenditure(
            intake: w.intake, weights: _upTo(w.weights, day), today: day, formulaTdee: formula, goalKcal: 2090, since: since);
        expect((e.status, e.est!.windowDays, e.est!.from), (AdaptStatus.ok, window, DateTime(2027, 1, 25)), reason: '$day');
        expect(e.est!.tdee, closeTo(2540, 1));
      }
    });

    test('η κάρτα της Δευτέρας 1/3 διαβάζει και τις 4 μέρες πριν από το παράθυρο: σωστή εκτίμηση, όχι λάθος μείωση', () {
      final t = DateTime(2027, 3, 1);
      final c = pendingCheckIn(goals: _invGoals(), today: t, weights: _upTo(w.weights, t), intake: _intakeOf(w.intake))!;
      expect((c.kind, c.est!.windowDays, c.est!.from), (CheckKind.proposal, 35, DateTime(2027, 1, 25)));
      expect(c.est!.tdee, closeTo(2540, 1));
      // 2.540 − 73,9 kg × 0,5% × 7.700 ÷ 7 ≈ 2.130: λίγο πάνω, γιατί έχει χάσει βάρος (πριν: 2.090 → «μένει», από 2.377).
      expect((c.proposal!.current, c.proposal!.target), (2090, 2130));
      expect(adaptScanDays, 46);
    });

    test('χωρίς κενό: ίδια παράθυρα με πριν κάθε Δευτέρα ως 1/3', () {
      final clean = _world();
      for (var t = DateTime(2026, 12, 14); !t.isAfter(DateTime(2027, 3, 1)); t = DateTime(t.year, t.month, t.day + 7)) {
        final r = estimateExpenditure(
            intake: clean.intake, weights: _upTo(clean.weights, t), today: t, formulaTdee: formula, goalKcal: 2090, since: since);
        final avail = daysBetween(DateTime(2026, 11, 23), DateTime(t.year, t.month, t.day - 1)) + 1;
        final want = [for (final x in adaptWindows) if (x <= avail) x].first;
        expect((r.status, r.est!.windowDays), (AdaptStatus.ok, want), reason: '$t');
      }
    });
  });

  // ------------------------------------------------------------------------------------------------ R2-A-3
  group('R2-A-3: γρήγορη απώλεια χωρίς φαγητό γραμμένο τις τελευταίες μέρες', () {
    // Τρως 2.250 κάθε μέρα 23/11–10/1 (γραμμένα), χάνεις 0,5%/εβδ. Από 11/1 άρρωστος: τίποτα γραμμένο, ζυγίσεις 1 / 2 / 2,5 kg
    // κάτω από την τάση. Ο εβδομαδιαίος έλεγχος της 11/1 έχει απαντηθεί.
    final g = checkinGoals().copyWith(checkIn: '2027-01-11');
    final today = DateTime(2027, 1, 15);
    final weights = _weights(DateTime(2026, 11, 16), today, 90, 0.005,
        dip: {DateTime(2027, 1, 11): 1.0, DateTime(2027, 1, 13): 2.0, DateTime(2027, 1, 15): 2.5});
    Map<DateTime, double> diary(Set<int> alsoJan) => {
          for (var d = DateTime(2026, 11, 23); !d.isAfter(DateTime(2027, 1, 10)); d = DateTime(d.year, d.month, d.day + 1)) d: 2250,
          for (final day in alsoJan) DateTime(2027, 1, day): 2250,
        };

    testWidgets('3 από τις 7 τελευταίες μέρες γραμμένες: καμία πρόταση (πριν: +150 από τις μέρες πριν από την αρρώστια)', (t) async {
      expect(weights.sublist(weights.length - 3).map((x) => x.$2), [85.5, 84.3, 83.7]);
      final c = pendingCheckIn(goals: g, today: today, weights: weights, intake: _intakeOf(diary({})))!;
      expect((c.kind, c.proposal, c.fastIntake, c.fastTarget), (CheckKind.fast, null, null, null));
      expect((c.fastIntakeDays, c.kgNow), (17, 83.7));
      expect(c.fastSlope!, closeTo(-1.1807, 0.0005));
      await _card(t, c, DateTime(2027, 1, 15, 9));
      expect(find.textContaining('Τις τελευταίες μέρες δεν έχει γραφτεί αρκετό φαγητό για να φανεί πόσο τρως.', findRichText: true),
          findsOneWidget);
      expect(find.byKey(const ValueKey('checkin-apply')), findsNothing);
      expect(dismissCheckIn(c, today).kcal, 2250);
    });

    test('4 από τις 7: ακόμα όχι· 5 από τις 7: +150 όπως πριν', () {
      final four = pendingCheckIn(goals: g, today: today, weights: weights, intake: _intakeOf(diary({11})))!;
      expect((four.kind, four.proposal, four.fastIntake, four.fastIntakeDays), (CheckKind.fast, null, null, 18));
      final five = pendingCheckIn(goals: g, today: today, weights: weights, intake: _intakeOf(diary({11, 12})))!;
      expect((five.kind, five.proposal!.current, five.proposal!.target, five.fastIntakeDays), (CheckKind.fast, 2250, 2400, 19));
      expect(five.fastIntake!, closeTo(2250, 1e-6));
      expect((adaptFastRecentDays, adaptFastRecentMinDays), (7, 5));
    });
  });

  // ------------------------------------------------------------------------------------------------ R2-A-5
  group('R2-A-5: η απόσταση των 4 ημερών μόνο μετά από απάντηση που άλλαξε τον στόχο', () {
    test('«Εντάξει» στο «μαζεύω δεδομένα» την Παρασκευή 11/12: η πρώτη εκτίμηση μένει τη Δευτέρα 14/12', () {
      final g = _invGoals();
      expect(checkInDue(goals: g, today: DateTime(2026, 12, 14), lastCheckIn: '2026-12-11'), isTrue, reason: 'πριν: false');
      expect(nextCheckDay(g.copyWith(checkIn: '2026-12-11'), DateTime(2026, 12, 11)), DateTime(2026, 12, 14), reason: 'πριν: 21/12');
      expect(nextCheckDay(g.copyWith(checkIn: '2026-12-13'), DateTime(2026, 12, 13)), DateTime(2026, 12, 14));
      expect(nextCheckDay(g.copyWith(checkIn: '2026-12-14'), DateTime(2026, 12, 14)), DateTime(2026, 12, 21));
      // «Όχι τώρα» (γραμμή χωρίς αλλαγή) επίσης.
      final declined = g.copyWith(
          checkIn: '2026-12-11', addLog: const AdaptLog(day: '2026-12-11', tdee: 2400, before: 2090, after: 2090, applied: false));
      expect(checkInDue(goals: declined, today: DateTime(2026, 12, 14), lastCheckIn: '2026-12-11'), isTrue);
      // Με «Εφάρμοσε» την Παρασκευή: η Δευτέρα δεν μετρά (S1-4).
      final changed = g.copyWith(
          checkIn: '2026-12-11', addLog: const AdaptLog(day: '2026-12-11', tdee: 2400, before: 2090, after: 1940, applied: true));
      expect(answerChangedTarget(changed, DateTime(2026, 12, 11)), isTrue);
      expect(answerChangedTarget(declined, DateTime(2026, 12, 11)), isFalse);
      expect(checkInDue(goals: changed, today: DateTime(2026, 12, 14), lastCheckIn: '2026-12-11'), isFalse);
      expect(nextCheckDay(changed, DateTime(2026, 12, 11)), DateTime(2026, 12, 21));
    });

    test('η ροή: 7/12 «μαζεύω δεδομένα», «Εντάξει» στις 11/12, 14/12 η πρώτη εκτίμηση', () {
      final w = _world();
      final g = _invGoals();
      CheckIn? at(Goals goals, DateTime d) => pendingCheckIn(goals: goals, today: d, weights: _upTo(w.weights, d), intake: _intakeOf(w.intake));
      final gather = at(g, DateTime(2026, 12, 7))!;
      expect(gather.kind, CheckKind.gathering);
      final late = dismissCheckIn(gather, DateTime(2026, 12, 11));
      expect(late.checkIn, '2026-12-11');
      expect(late.log, isEmpty);
      expect(at(late, DateTime(2026, 12, 12)), isNull);
      final first = at(late, DateTime(2026, 12, 14))!;
      expect((first.kind, first.status, first.est!.windowDays, first.est!.from), (CheckKind.same, AdaptStatus.ok, 21, DateTime(2026, 11, 23)));
      expect(first.est!.tdee, closeTo(2540, 1));
    });

    testWidgets('η σελίδα «Στόχοι» μετά το «Εντάξει» της Παρασκευής: «Πρώτη εκτίμηση: Δευτέρα 14 Δεκεμβρίου»', (t) async {
      final at = DateTime(2026, 12, 11, 18);
      final s = HealthStore()
        ..data = Dashboard.fromJson({...sampleDashboardJson(at), 'body': bodyJson(simWeights(at))});
      s
        ..history = sampleHistory(at, s.data!)
        ..setProfile(_me)
        ..setGoals(checkinGoals().copyWith(checkIn: '2026-12-11'));
      await _pump(t, GoalsPage(store: s, now: at));
      expect(find.text('Πρώτη εκτίμηση: Δευτέρα 14 Δεκεμβρίου'), findsOneWidget, reason: 'πριν: 21 Δεκεμβρίου');
    });
  });

  // ------------------------------------------------------------------------------------------------ R2-A-4
  group('R2-A-4: «δικό μου πρώτο» μόνο με ολόκληρη λέξη, όχι με την αρχή άλλης λέξης', () {
    FoodStore store() => FoodStore.preloaded(foods: basicFoods(), mine: [
      _own('Mt1', 'Μελιτζανοσαλάτα', 180),
      _own('Mt2', 'Τονοσαλάτα', 220),
      _own('Mt3', 'Γαλακτομπούρεκο', 260),
      _own('Mt4', 'Μηλόπιτα', 280),
      _own('Mt5', 'Αυγολέμονο σούπα', 60),
      _own('Mt6', 'Σοκολατάκια γάλακτος', 540),
      _own('Mt7', 'Γιαούρτι στραγγιστό 2%', 73, brand: 'Μάρκα Β'),
    ]);

    test('λέξη που είναι τρόφιμο: πρώτο το ίδιο το τρόφιμο (πριν: το δικό μου που απλώς αρχίζει έτσι)', () {
      final s = store();
      for (final (q, id) in [
        ('μέλι', 'C31008'),
        ('μελ', 'C31008'),
        ('τόνος', 'C26039'),
        ('γάλα', 'C19033'),
        ('μήλο', 'C13039'),
        ('αυγό', 'C22000'),
        ('σοκολάτα', 'C31004'),
      ]) {
        expect(s.find(q).foods.first.id, id, reason: q);
      }
      // Το δικό μου βρίσκεται ακόμα, αμέσως μετά.
      expect(s.find('μέλι').foods.map((f) => f.id).take(2), ['C31008', 'Mt1']);
      expect(s.find('μήλο').foods.map((f) => f.id).take(2), ['C13039', 'Mt4']);
    });

    test('ολόκληρη λέξη, ίδια ρίζα, μάρκα ή λέξη που γράφεται ακόμα: το δικό μου πρώτο, όπως πριν', () {
      final s = store();
      for (final (q, id) in [
        ('γιαούρτι', 'Mt7'),
        ('γιαουρτ', 'Mt7'),
        ('γιαου', 'Mt7'),
        ('μάρκα β', 'Mt7'),
        ('μελιτζ', 'Mt1'),
        ('τονοσαλάτα', 'Mt2'),
        ('μηλοπιτα', 'Mt4'),
        ('σοκολατάκια', 'Mt6'),
      ]) {
        expect(s.find(q).foods.first.id, id, reason: q);
      }
    });
  });
}
