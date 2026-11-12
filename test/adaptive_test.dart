// Αυτόματη διόρθωση θερμίδων (12/11). Φανταστικά δεδομένα (δημόσιο repo).
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/adaptive.dart';
import 'package:ygeia_forma/goals.dart';

Goals _g({GoalAim aim = GoalAim.lose, String since = '2026-11-16', int? kcalSet, int? kcalAdapt, bool male = true}) => Goals(
      aim: aim,
      rate: aim == GoalAim.keep ? 0 : 0.005,
      activity: 1.5,
      doctor: false,
      since: since,
      kg: 90,
      age: 40,
      heightCm: 180,
      male: male,
      kcalSet: kcalSet,
      kcalAdapt: kcalAdapt,
    );

/// [days] μέρες πριν από [today], με σταθερό φαγητό [eat] και πραγματική κατανάλωση [tdee]: το βάρος πέφτει όσο λέει
/// το ισοζύγιο. Ζυγίσεις Δευτέρα, Τετάρτη, Παρασκευή.
({Map<DateTime, double> intake, List<(DateTime, double)> weights}) _sim(DateTime today, {int days = 21, double eat = 2250, double tdee = 2600, double kg0 = 90, double noise = 0}) {
  final intake = <DateTime, double>{};
  final weights = <(DateTime, double)>[];
  var kg = kg0;
  for (var k = days; k >= 1; k--) {
    final d = DateTime(today.year, today.month, today.day - k);
    intake[d] = eat;
    if (d.weekday == 1 || d.weekday == 3 || d.weekday == 5) weights.add((d, kg + (weights.length.isEven ? noise : -noise)));
    kg += (eat - tdee) / kcalPerKg;
  }
  return (intake: intake, weights: weights);
}

void main() {
  final today = DateTime(2026, 12, 7); // Δευτέρα, 21 μέρες μετά τις 16/11

  test('κλίση βάρους με ελάχιστα τετράγωνα', () {
    final w = [(DateTime(2026, 1, 1), 90.0), (DateTime(2026, 1, 8), 89.3), (DateTime(2026, 1, 15), 88.6)];
    expect(weightSlope(w)! * 7, closeTo(-0.7, 1e-9));
    expect(weightSlope([(DateTime(2026, 1, 1), 90.0)]), isNull);
  });

  test('ισοζύγιο: τρως 2.250, καις 2.600 → εκτίμηση ~2.600', () {
    final s = _sim(today);
    final r = estimateExpenditure(intake: s.intake, weights: s.weights, today: today, formulaTdee: 2745, goalKcal: 2250);
    expect(r.status, AdaptStatus.ok);
    expect(r.est!.tdee, closeTo(2600, 5));
    expect(r.est!.intakeDays, 21);
    expect(r.est!.weighIns, 9);
    expect(r.est!.slopeKgWeek, closeTo(-350 * 7 / kcalPerKg, 0.01));
    expect(r.est!.to, DateTime(2026, 12, 6), reason: 'όχι σήμερα, που δεν τελείωσε');
  });

  test('τα νερά (±0,6 kg) δεν αλλάζουν πολύ την εκτίμηση', () {
    final s = _sim(today, noise: 0.6);
    final r = estimateExpenditure(intake: s.intake, weights: s.weights, today: today, formulaTdee: 2745, goalKcal: 2250);
    expect(r.status, AdaptStatus.ok);
    expect(r.est!.tdee, closeTo(2600, 150));
  });

  test('λίγα δεδομένα: καμία πρόταση', () {
    final s = _sim(today);
    // Μέρες με λίγη καταγραφή (κάτω από 60% του στόχου) δεν μετρούν.
    final thin = {for (final e in s.intake.entries) e.key: e.key.day.isEven ? 900.0 : e.value};
    expect(estimateExpenditure(intake: thin, weights: s.weights, today: today, formulaTdee: 2745, goalKcal: 2250).status,
        AdaptStatus.fewIntakeDays);
    expect(estimateExpenditure(intake: s.intake, weights: s.weights.take(4).toList(), today: today, formulaTdee: 2745, goalKcal: 2250).status,
        AdaptStatus.fewWeighIns);
  });

  test('παράλογη εκτίμηση (π.χ. ξεχασμένα γεύματα): καμία πρόταση', () {
    final s = _sim(today, eat: 1500, tdee: 4500);
    final r = estimateExpenditure(intake: s.intake, weights: s.weights, today: today, formulaTdee: 2745, goalKcal: 2250);
    expect(r.status, AdaptStatus.implausible);
  });

  test('πρόταση: εκτίμηση − ρυθμός, το πολύ ±150 την εβδομάδα, όχι κάτω από το όριο', () {
    final s = _sim(today);
    final est = estimateExpenditure(intake: s.intake, weights: s.weights, today: today, formulaTdee: 2745, goalKcal: 2250).est!;
    final p = proposeTarget(goals: _g(), est: est, kgNow: 89);
    // 2.600 − 89 × 0,5% × 7.700 / 7 ≈ 2.110 → −140 από 2.250
    expect((p.current, p.target), (2250, 2110));
    final big = proposeTarget(goals: _g(kcalAdapt: 2600), est: est, kgNow: 89);
    expect(big.change, -150, reason: 'το πολύ 150 τη φορά');
    final small = proposeTarget(goals: _g(kcalAdapt: 2120), est: est, kgNow: 89);
    expect(small.same, isTrue, reason: 'κάτω από 30 kcal: μένει ίδιος');
    final f = proposeTarget(goals: _g(male: false, kcalAdapt: 1250), est: Expenditure(tdee: 1300, meanIntake: 1250, slopeKgWeek: 0, intakeDays: 20, weighIns: 9, from: DateTime(2026), to: DateTime(2026)), kgNow: 60);
    expect(f.target, greaterThanOrEqualTo(kcalFloorFemale));
    expect(f.floored, isTrue);
  });

  test('ο δικός σου στόχος νικά· ο αυτόματος νικά τον τύπο', () {
    expect(_g().kcal, 2250);
    expect(_g(kcalAdapt: 2110).kcal, 2110);
    expect(_g(kcalAdapt: 2110, kcalSet: 2000).kcal, 2000);
    final j = _g(kcalAdapt: 2110).copyWith(tdeeEst: 2600.4, checkIn: '2026-12-07').toJson();
    final back = Goals.fromJson(j)!;
    expect((back.kcalAdapt, back.tdeeEst, back.checkIn), (2110, 2600.4, '2026-12-07'));
    expect(Goals.fromJson({...j, 'ka': 50})!.kcalAdapt, isNull);
    expect(Goals.fromJson({...j, 'ci': 'Δευτέρα'})!.checkIn, isNull);
    expect(back.copyWith(clearAdapt: true).kcal, 2250);
  });

  test('γρήγορη απώλεια: > 1% την εβδομάδα στις 14 μέρες → +150', () {
    final fast = _sim(today, eat: 1600, tdee: 2900); // −1.300/μέρα ≈ −1,2 kg/εβδ. σε 90 kg
    final p = fastLossCheck(goals: _g(), weights: fast.weights, today: today);
    expect(p, isNotNull);
    expect((p!.fastLoss, p.change), (true, 150));
    final normal = _sim(today);
    expect(fastLossCheck(goals: _g(), weights: normal.weights, today: today), isNull);
    expect(fastLossCheck(goals: _g(aim: GoalAim.keep), weights: fast.weights, today: today), isNull);
    expect(fastLossCheck(goals: _g(since: '2026-12-01'), weights: fast.weights, today: today), isNull, reason: 'όχι πριν τη 14η μέρα');
  });

  test('μέρα ελέγχου: ίδια μέρα της εβδομάδας με την αρχή, από την 21η μέρα, μία φορά', () {
    final g = _g(); // 16/11, Δευτέρα
    expect(checkInDue(goals: g, today: DateTime(2026, 11, 30)), isFalse, reason: '14 μέρες');
    expect(checkInDue(goals: g, today: DateTime(2026, 12, 7)), isTrue);
    expect(checkInDue(goals: g, today: DateTime(2026, 12, 7), lastCheckIn: '2026-12-07'), isFalse);
    expect(checkInDue(goals: g, today: DateTime(2026, 12, 9)), isTrue, reason: 'χάθηκε η Δευτέρα: μένει ανοιχτός');
    expect(checkInDue(goals: g, today: DateTime(2026, 12, 9), lastCheckIn: '2026-12-07'), isFalse);
    expect(checkInDue(goals: g, today: DateTime(2026, 12, 14), lastCheckIn: '2026-12-07'), isTrue);
  });
}
