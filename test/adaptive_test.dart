// Αυτόματη διόρθωση θερμίδων (12/11). Φανταστικά δεδομένα (δημόσιο repo).
import 'dart:io';

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

  // ------------------------------------------------------------------ τελικός έλεγχος, Συμβούλιο 2

  test('Σ1: τα νερά της πρώτης εβδομάδας δεν βγάζουν «γρήγορη απώλεια» τη 14η μέρα', () {
    // Στόχοι από Δευτέρα 16/11. Πρώτη εβδομάδα −1,8 kg (νερά και γλυκογόνο), μετά −0,1 kg ανά ζύγιση (≈ 0,3 kg/εβδ.).
    final w = [
      (DateTime(2026, 11, 16), 90.0),
      (DateTime(2026, 11, 18), 89.2),
      (DateTime(2026, 11, 20), 88.6),
      (DateTime(2026, 11, 23), 88.2),
      (DateTime(2026, 11, 25), 88.1),
      (DateTime(2026, 11, 27), 88.0),
      (DateTime(2026, 11, 30), 87.9),
      (DateTime(2026, 12, 2), 87.8),
      (DateTime(2026, 12, 4), 87.7),
    ];
    List<(DateTime, double)> upTo(DateTime d) => [for (final x in w) if (!x.$1.isAfter(d)) x];
    // Τη 14η μέρα (30/11) οι 14 τελευταίες μέρες είναι ολόκληρη η πρώτη εβδομάδα μαζί: −1,0 kg/εβδ. στο σύνολο.
    final day14 = DateTime(2026, 11, 30);
    expect(weightSlope(upTo(day14))! * 7, lessThan(-0.01 * 87.9), reason: 'με την πρώτη εβδομάδα μέσα, η κλίση περνά το 1%');
    expect(fastLossWeights(goals: _g(), weights: upTo(day14), today: day14).first.$1, DateTime(2026, 11, 23));
    expect(fastLossCheck(goals: _g(), weights: upTo(day14), today: day14), isNull, reason: 'η πρώτη εβδομάδα δεν μετρά');
    // Τη 18η μέρα (4/12): 6 ζυγίσεις από τις 23/11, −0,3 kg/εβδ. Καμία ειδοποίηση.
    final day18 = DateTime(2026, 12, 4);
    expect(fastLossWeights(goals: _g(), weights: w, today: day18).length, 6);
    expect(fastLossCheck(goals: _g(), weights: w, today: day18), isNull);
    // Αληθινά γρήγορη απώλεια ΜΕΤΑ την πρώτη εβδομάδα πιάνεται κανονικά (−0,6 kg ανά ζύγιση ≈ 1,9 kg/εβδ.).
    final fast = [
      for (var k = 0; k < 6; k++) (DateTime(2026, 11, 23 + [0, 2, 4, 7, 9, 11][k]), 88.0 - 0.6 * k),
    ];
    final p = fastLossCheck(goals: _g(), weights: fast, today: day18);
    expect(p, isNotNull);
    expect(p!.change, 150);
  });

  test('μ1: «δεν κατεβαίνει κάτω από το όριο ασφαλείας» μόνο όταν ο νέος στόχος είναι στο όριο', () {
    final est = Expenditure(tdee: 1700, meanIntake: 1700, slopeKgWeek: 0, intakeDays: 20, weighIns: 9, from: DateTime(2026), to: DateTime(2026));
    // Θέλει 1.700 − 495 ≈ 1.210, κάτω από το όριο των 1.500. Από 2.000 το βήμα των 150 τον πάει στο 1.850: δεν είναι στο όριο.
    final far = proposeTarget(goals: _g(kcalAdapt: 2000), est: est, kgNow: 90);
    expect((far.target, far.floored), (1850, false));
    // Από 1.600 φτάνει στο 1.500: εκεί ισχύει το μήνυμα.
    final at = proposeTarget(goals: _g(kcalAdapt: 1600), est: est, kgNow: 90);
    expect((at.target, at.floored), (1500, true));
  });

  test('Σ2: οι μέρες μετριούνται ημερολογιακά, ποτέ «μείον n × 24 ώρες» (αλλαγή ώρας)', () {
    // Η ίδια η συμπεριφορά στην αλλαγή ώρας ελέγχθηκε με ώρα Ελλάδας (25/10/2026 και 28/3/2027) έξω από εδώ: οι δοκιμές
    // τρέχουν σε ζώνη χωρίς αλλαγή ώρας. Εδώ φυλάμε τον κανόνα στον κώδικα, για να μη γυρίσει πίσω.
    for (final f in ['lib/adaptive.dart', 'lib/adaptive_check.dart']) {
      final code = File(f).readAsStringSync();
      expect(RegExp(r'\.(subtract|add)\(\s*(const\s+)?Duration\(\s*days').hasMatch(code), isFalse, reason: f);
      expect(code.contains('.inDays'), isFalse, reason: '$f: μέρες με το daysBetween');
    }
    // Και οι μέρες ελέγχου πέφτουν πάντα σε τοπικά μεσάνυχτα.
    final g = _g();
    for (var d = 7; d <= 40; d++) {
      final day = DateTime(2026, 12, d);
      expect(checkInDue(goals: g, today: day, lastCheckIn: null), isTrue, reason: 'από την 21η μέρα εκκρεμεί ως να απαντηθεί');
    }
    expect(checkInDue(goals: g, today: DateTime(2026, 12, 12), lastCheckIn: '2026-12-07'), isFalse);
    expect(checkInDue(goals: g, today: DateTime(2026, 12, 13), lastCheckIn: '2026-12-07'), isFalse);
    expect(checkInDue(goals: g, today: DateTime(2026, 12, 14), lastCheckIn: '2026-12-07'), isTrue);
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
