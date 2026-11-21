// Βαθύς έλεγχος 20/11/2026, κατηγορία 1 (θερμίδες, στόχοι, βάρος): δοκιμές για τις διορθώσεις K1-C-01…08 και K1-S-01…08.
// Μόνο επινοημένα δεδομένα (δημόσιο repo). Οι αναμενόμενες τιμές των K1-C-01, K1-C-02, K1-S-05 επαληθεύτηκαν πρώτα στη
// μεταφορά του developer σε Python, και ΟΛΕΣ (και των K1-C-06/07/08, K1-S-02) ξανά από τον ανεξάρτητο ελεγκτή (22 από 22).
// Παλιά κεφαλίδα: οι αναμενόμενες τιμές επαληθεύτηκαν πρώτα σε ανεξάρτητη μεταφορά σε Python.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/adaptive.dart';
import 'package:ygeia_forma/adaptive_check.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/goals.dart';
import 'package:ygeia_forma/history.dart' show K;
import 'package:ygeia_forma/pages/checkin_card.dart';
import 'package:ygeia_forma/pages/goals_page.dart';
import 'package:ygeia_forma/profile.dart';
import 'package:ygeia_forma/reference.dart';
import 'package:ygeia_forma/theme.dart';

import 'sample_checkin.dart' show checkinFood;

/// Επινοημένοι στόχοι: άνδρας 40 ετών, 180 cm, 90 kg, −0,5% την εβδομάδα (τύπος 2.745 → στόχος 2.250).
Goals _g({String since = '2026-11-16', int? kcalSet, GoalAim aim = GoalAim.lose}) => Goals(
      aim: aim,
      rate: aim == GoalAim.keep ? 0 : 0.005,
      activity: 1.5,
      doctor: false,
      since: since,
      kg: 90,
      age: 40,
      heightCm: 180,
      male: true,
      kcalSet: kcalSet,
    );

Expenditure _est(double tdee,
        {double meanIntake = 2250, double slopeKgWeek = -0.4, double seKcal = 20, int windowDays = 21, int intakeDays = 20}) =>
    Expenditure(
      tdee: tdee,
      meanIntake: meanIntake,
      slopeKgWeek: slopeKgWeek,
      intakeDays: intakeDays,
      weighIns: 9,
      from: DateTime(2027, 1, 11),
      to: DateTime(2027, 1, 31),
      seKcal: seKcal,
      windowDays: windowDays,
    );

/// [days] μέρες πριν από [today]: τρως 2.250, καις 2.600· ζυγίσεις Δευτέρα, Τετάρτη, Παρασκευή. Οι μέρες από [gapFrom] ως
/// [gapTo] ΠΡΙΝ από σήμερα δεν έχουν φαγητό (κενό καταγραφής).
({Map<DateTime, double> intake, List<(DateTime, double)> weights}) _sim(DateTime today, {required int gapFrom, required int gapTo}) {
  final intake = <DateTime, double>{};
  final weights = <(DateTime, double)>[];
  var kg = 90.0;
  for (var k = 60; k >= 1; k--) {
    final d = DateTime(today.year, today.month, today.day - k);
    if (k < gapFrom || k > gapTo) intake[d] = 2250;
    if (d.weekday == 1 || d.weekday == 3 || d.weekday == 5) weights.add((d, kg));
    kg += (2250 - 2600) / kcalPerKg;
  }
  return (intake: intake, weights: weights);
}

const _me = Profile(birthYear: 1985, birthMonth: 12, sex: 'm', heightCm: 180);

Future<void> _wizard(WidgetTester t, HealthStore store, DateTime now) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = const Size(400, 3000);
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: GoalsWizard(store: store, now: now, fromPage: true)));
  await t.pumpAndSettle();
  await t.enterText(find.byKey(const ValueKey('wizard-kg')), '90');
  await t.pumpAndSettle();
  for (var k = 0; k < 4; k++) {
    await t.tap(find.byKey(const ValueKey('wizard-next')));
    await t.pumpAndSettle();
  }
}

Future<void> _save(WidgetTester t) async {
  await t.ensureVisible(find.byKey(const ValueKey('wizard-next')));
  await t.tap(find.byKey(const ValueKey('wizard-next')));
  await t.pumpAndSettle();
}

void main() {
  group('K1-C-01: «γρήγορη απώλεια» με περιθώριο δύο τυπικών σφαλμάτων', () {
    final day18 = DateTime(2026, 12, 4);
    List<(DateTime, double)> ws(double last) => [
          (DateTime(2026, 11, 23), 88.0),
          (DateTime(2026, 11, 25), 87.8),
          (DateTime(2026, 11, 27), 87.6),
          (DateTime(2026, 11, 30), 87.3),
          (DateTime(2026, 12, 2), 87.1),
          (DateTime(2026, 12, 4), last),
        ];

    test('το περιθώριο είναι 2 τυπικά σφάλματα, όσο και στον εβδομαδιαίο έλεγχο', () {
      expect(adaptFastGuardSe, 2.0);
      expect(adaptFastGuardSe, adaptGuardSe);
    });

    test('μία ρηχή ζύγιση (ως 3,5 kg κάτω από την τάση) δεν βγάζει ειδοποίηση· η τάση είναι 0,8% την εβδομάδα', () {
      for (final last in [86.3, 86.0, 85.8, 85.5, 85.0, 84.5]) {
        expect(fastLossCheck(goals: _g(), weights: ws(last), today: day18), isNull, reason: 'τελευταία ζύγιση $last');
      }
    });

    test('όλες οι ζυγίσεις πάνω σε ευθεία −1,2% την εβδομάδα: +150', () {
      final line = [
        for (final d in [0, 2, 4, 7, 9, 11]) (DateTime(2026, 11, 23 + d), 88.0 - 0.151 * d),
      ];
      final p = fastLossCheck(goals: _g(), weights: line, today: day18)!;
      expect((p.current, p.target, p.change, p.fastLoss), (2250, 2400, 150, true));
    });

    test('ζυγίσεις με θόρυβο γύρω από αληθινή απώλεια 0,4%: καμία ειδοποίηση (με 1 σφάλμα έβγαινε «1,2% του βάρους»)', () {
      final w = [
        (DateTime(2027, 3, 22), 75.0),
        (DateTime(2027, 3, 24), 74.8),
        (DateTime(2027, 3, 26), 73.9),
        (DateTime(2027, 3, 29), 73.9),
        (DateTime(2027, 3, 31), 73.8),
        (DateTime(2027, 4, 2), 74.1),
        (DateTime(2027, 4, 5), 73.2),
        (DateTime(2027, 4, 7), 72.8),
        (DateTime(2027, 4, 9), 72.4),
      ];
      final f = weightFit(w)!;
      expect(f.slope * 7, closeTo(-0.8915, 1e-3));
      expect(f.se! * 7, closeTo(0.1374, 1e-3));
      // Με ένα σφάλμα: −0,754 < −0,724 (1% των 72,4 kg) → ειδοποίηση. Με δύο: −0,617 → καμία.
      expect((f.slope + f.se!) * 7, lessThan(-0.01 * 72.4));
      expect((f.slope + 2 * f.se!) * 7, greaterThan(-0.01 * 72.4));
      expect(fastLossSlope(goals: _g(since: '2026-11-23'), weights: w, today: DateTime(2027, 4, 10)), isNull);
    });
  });

  group('K1-C-02: μετά από κενό καταγραφής η πρώτη εβδομάδα της επιστροφής δεν μετρά', () {
    final today = DateTime(2027, 2, 1); // Δευτέρα
    final since = DateTime(2026, 11, 23);

    test('η εκτίμηση θέλει 21 μέρες ΜΕΤΑ τις 7 πρώτες της επιστροφής', () {
      // Κενό 10 ημερών· η καταγραφή ξαναρχίζει 27 μέρες πριν από σήμερα (5/1): μετρούν 20 μέρες → όχι ακόμα.
      final a = _sim(today, gapFrom: 28, gapTo: 37);
      final gapA = foodGap(intake: a.intake, today: today, formulaTdee: 2745, goalKcal: 2250, since: since)!;
      expect((gapA.from, gapA.to, gapA.restart), (DateTime(2026, 12, 26), DateTime(2027, 1, 4), DateTime(2027, 1, 5)));
      expect(afterGapStart(gapA.restart!), DateTime(2027, 1, 12));
      final ra = estimateExpenditure(intake: a.intake, weights: a.weights, today: today, formulaTdee: 2745, goalKcal: 2250, since: since);
      expect(ra.status, AdaptStatus.afterGap, reason: 'πριν: εκτίμηση με τα νερά της επιστροφής μέσα στο παράθυρο');
      // Μία μέρα νωρίτερα (4/1): μετρούν ακριβώς 21 μέρες (11/1–31/1).
      final b = _sim(today, gapFrom: 29, gapTo: 38);
      final rb = estimateExpenditure(intake: b.intake, weights: b.weights, today: today, formulaTdee: 2745, goalKcal: 2250, since: since);
      expect(rb.status, AdaptStatus.ok);
      expect((rb.est!.windowDays, rb.est!.from, rb.est!.intakeDays, rb.est!.weighIns), (21, DateTime(2027, 1, 11), 21, 9));
      expect(rb.est!.tdee, closeTo(2600, 1));
    });

    test('η μέρα της πρώτης εκτίμησης μετά το κενό: επιστροφή + 7 + 21 μέρες, στη μέρα ελέγχου', () {
      final g = _g(since: '2026-11-23');
      final FoodGap gap = (from: DateTime(2026, 12, 24), to: DateTime(2027, 1, 2), restart: DateTime(2027, 1, 3));
      expect(estimateDayAfterGap(g, DateTime(2027, 1, 4), gap), DateTime(2027, 2, 1), reason: 'πριν: 25 Ιανουαρίου');
      expect(estimateDayAfterGap(g, DateTime(2027, 2, 8), gap), DateTime(2027, 2, 8), reason: 'ήδη αργότερα');
      final FoodGap open = (from: DateTime(2026, 12, 24), to: DateTime(2027, 1, 2), restart: null);
      expect(estimateDayAfterGap(g, DateTime(2027, 1, 4), open), isNull);
    });

    test('«τι έχει μαζευτεί»: μετρούν μόνο οι μέρες μετά την πρώτη εβδομάδα της επιστροφής', () {
      final g = _g(since: '2026-11-23');
      final now = DateTime(2027, 1, 13);
      final intake = <DateTime, double>{};
      for (var k = 70; k >= 1; k--) {
        final d = DateTime(now.year, now.month, now.day - k);
        if (d.isBefore(DateTime(2026, 12, 24)) || d.isAfter(DateTime(2027, 1, 2))) intake[d] = 2250;
      }
      final weights = [(DateTime(2027, 1, 4), 85.3), (DateTime(2027, 1, 6), 84.6), (DateTime(2027, 1, 8), 84.0), (DateTime(2027, 1, 11), 83.6)];
      final r = readiness(
          goals: g,
          today: now,
          weights: weights,
          intake: (a, b) => {
                for (final e in intake.entries)
                  if (!e.key.isBefore(a) && !e.key.isAfter(b)) e.key: e.value,
              });
      expect(r.gap!.restart, DateTime(2027, 1, 3));
      // Από 10/1 (3/1 + 7) ως χθες 12/1: τρεις μέρες φαγητού και μία ζύγιση (11/1). Πριν: 10 μέρες και 4 ζυγίσεις.
      expect((r.intakeDays, r.weighIns, r.weighSpan), (3, 1, 0));
    });

    test('«γρήγορη απώλεια»: οι μέρες πριν από το [notBefore] δεν κρίνονται', () {
      final g = _g(since: '2026-11-23');
      expect(fastLossWindow(goals: g, today: DateTime(2027, 1, 20)), (DateTime(2026, 12, 30), DateTime(2027, 1, 20)));
      expect(fastLossWindow(goals: g, today: DateTime(2027, 1, 20), notBefore: DateTime(2027, 1, 10)),
          (DateTime(2027, 1, 10), DateTime(2027, 1, 20)));
      final FoodGap gap = (from: DateTime(2026, 12, 24), to: DateTime(2027, 1, 2), restart: DateTime(2027, 1, 3));
      final FoodGap open = (from: DateTime(2026, 12, 24), to: DateTime(2027, 1, 2), restart: null);
      expect(fastNotBefore(gap), DateTime(2027, 1, 10));
      expect(fastNotBefore(open), isNull);
      expect(fastNotBefore(null), isNull);
      // Ευθεία −1,5% την εβδομάδα από 4/1 (τα νερά των γιορτών που φεύγουν): χωρίς όριο βγάζει ειδοποίηση.
      List<(DateTime, double)> line(int lastDay) => [
            for (final d in [4, 6, 8, 11, 13, 15, 18, 20, 22])
              if (d <= lastDay) (DateTime(2027, 1, d), 86.0 - 0.18 * (d - 4)),
          ];
      expect(fastLossSlope(goals: g, weights: line(18), today: DateTime(2027, 1, 18)), isNotNull);
      // Με όριο 10/1: στις 18/1 υπάρχουν 4 ζυγίσεις σε 7 μέρες (θέλει 10) → καμία κρίση ακόμα.
      expect(fastLossSlope(goals: g, weights: line(18), today: DateTime(2027, 1, 18), notBefore: DateTime(2027, 1, 10)), isNull);
      // Στις 22/1 (11 μέρες μετά το όριο) η απώλεια συνεχίζει ίδια: τώρα είναι αληθινή και βγαίνει.
      expect(fastLossSlope(goals: g, weights: line(22), today: DateTime(2027, 1, 22), notBefore: DateTime(2027, 1, 10)), isNotNull);
      expect(fastLossCheck(goals: g, weights: line(22), today: DateTime(2027, 1, 22), notBefore: DateTime(2027, 1, 10))?.change, 150);
    });
  });

  group('K1-C-02: πρόταση από μεγάλο παράθυρο μόνο όταν συμφωνούν και οι 21 τελευταίες μέρες', () {
    final g = _g();
    final big = _est(2900, slopeKgWeek: -0.65, windowDays: 42, intakeDays: 40);
    final p = proposeTarget(goals: g, est: big, kgNow: 88);

    test('η πρόταση του μεγάλου παραθύρου', () {
      expect((p.current, p.target, p.withinNoise, p.recentDiffers), (2250, 2400, false, false));
    });

    test('οι 21 τελευταίες μέρες δείχνουν προς τα κάτω ή τίποτα: ο στόχος μένει, με τον λόγο γραμμένο', () {
      for (final recent in [2700.0, 2740.0, 2745.0, 2750.0]) {
        final q = recentAgrees(p: p, goals: g, recent: _est(recent, seKcal: 300), kgNow: 88);
        expect((q.current, q.target, q.recentDiffers), (2250, 2250, true), reason: 'εκτίμηση 21 ημερών $recent');
        expect(q.est, same(big), reason: 'η κάρτα δείχνει την εκτίμηση του μεγάλου παραθύρου');
      }
    });

    test('συμφωνούν (το περιθώριο των ζυγίσεων των 21 ημερών δεν μετρά εδώ): η πρόταση μένει', () {
      final q = recentAgrees(p: p, goals: g, recent: _est(2800, seKcal: 300), kgNow: 88);
      expect(q, same(p));
    });

    test('χωρίς εκτίμηση 21 ημερών, ή χωρίς πρόταση: τίποτα δεν αλλάζει', () {
      expect(recentAgrees(p: p, goals: g, recent: null, kgNow: 88), same(p));
      final none = proposeTarget(goals: g, est: _est(2745, windowDays: 42), kgNow: 88);
      expect(none.change, 0);
      expect(recentAgrees(p: none, goals: g, recent: _est(2000), kgNow: 88), same(none));
    });
  });

  group('K1-S-05 / K1-C-04: κάτω από δείκτη μάζας σώματος 18,5 ο στόχος δεν κατεβαίνει', () {
    final g = _g(); // 180 cm: ΔΜΣ 18,5 = 59,94 kg
    final low = _est(2000, meanIntake: 1900, slopeKgWeek: -0.1);

    test('εβδομαδιαίος έλεγχος', () {
      final under = proposeTarget(goals: g, est: low, kgNow: 59.9);
      expect((under.target, under.change, under.underweight), (2250, 0, true));
      final ok = proposeTarget(goals: g, est: low, kgNow: 60.0);
      expect((ok.target, ok.change, ok.underweight), (2100, -150, false));
      // Προς τα πάνω επιτρέπεται πάντα.
      final up = proposeTarget(goals: g, est: _est(3200), kgNow: 59.9);
      expect((up.change, up.underweight), (150, false));
    });

    test('πρόταση από τη ζυγαριά (λίγη καταγραφή)', () {
      final e = _est(1800, meanIntake: 1700, slopeKgWeek: 0.2);
      expect(lowLogProposal(goals: g, est: e, kgNow: 60.0)?.change, -150);
      expect(lowLogProposal(goals: g, est: e, kgNow: 59.9), isNull);
    });

    test('μόνο στο «λιγότερο λίπος»', () {
      expect(belowHealthyWeight(g, 59.9), isTrue);
      expect(belowHealthyWeight(g, 60.0), isFalse);
      expect(belowHealthyWeight(_g(aim: GoalAim.keep), 55), isFalse);
      expect(belowHealthyWeight(_g(aim: GoalAim.gain), 55), isFalse);
    });
  });

  group('K1-S-01, K1-S-02, K1-S-03: τι λέει η κάρτα', () {
    CheckIn card(Expenditure e, {int target = 2250, CheckKind kind = CheckKind.same, bool lowLog = false, double? estTarget, double kg = 80}) {
      final g = _g(kcalSet: 2250);
      return CheckIn(
          kind: kind,
          goals: g,
          est: e,
          proposal: AdaptProposal(current: 2250, target: target, est: e, fastLoss: false, floored: false),
          kgNow: kg,
          estTarget: estTarget ?? 2250,
          lowLog: lowLog);
    }

    test('εκτίμηση πολύ κάτω από τον τύπο (και πέρα από το περιθώριο): «σαν να καις», όχι «ο τύπος έπεφτε έξω»', () {
      // Τύπος 2.745· 87% = 2.388.
      expect(likelyUnderlogged(card(_est(2080, seKcal: 50))), isTrue);
      expect(likelyUnderlogged(card(_est(2380, seKcal: 50))), isTrue);
      expect(likelyUnderlogged(card(_est(2390, seKcal: 50))), isFalse, reason: 'μέσα σε ένα τυπικό σφάλμα των εξισώσεων');
      expect(likelyUnderlogged(card(_est(2080, seKcal: 400))), isFalse, reason: 'μέσα στο περιθώριο των ζυγίσεων');
      expect(likelyUnderlogged(card(_est(3100, seKcal: 50))), isFalse, reason: 'προς τα πάνω δεν είναι υποκαταγραφή');
    });

    test('τρως 350 kcal κάτω από τον στόχο και χάνεις σχεδόν διπλάσια από τον ρυθμό σου: η κάρτα το λέει', () {
      final k = card(_est(2600, meanIntake: 1800, slopeKgWeek: -0.73));
      final b = eatingFarBelow(k)!;
      expect((b.eaten, b.target, b.under), (1800, 2250, 450));
      expect(b.plannedKgWeek, closeTo(-0.4, 1e-9));
      final text = farBelowText(k)!;
      expect(text, contains('Τρως όμως κατά μέσο όρο 1.800 kcal, 450 λιγότερες από τον στόχο σου'));
      expect(text, contains('γι’ αυτό χάνεις 0,73 kg την εβδομάδα αντί για 0,40'));
      expect(text, contains('φάε πιο κοντά στον στόχο'));
      // Οι στόχοι άλλαξαν μέσα στο διάστημα: γράφεται ο μέσος όρος τους.
      final moved = farBelowText(card(_est(2600, meanIntake: 1800, slopeKgWeek: -0.73), estTarget: 2150))!;
      expect(moved, contains('350 λιγότερες από τους στόχους σου αυτές τις εβδομάδες (κατά μέσο όρο 2.150)'));
    });

    test('όχι όταν τρως κοντά στον στόχο, όταν ο ρυθμός είναι κοντά στον δικό σου, ή όταν η πρόταση βγήκε από τη ζυγαριά', () {
      expect(eatingFarBelow(card(_est(2600, meanIntake: 2100, slopeKgWeek: -0.73))), isNull, reason: '150 κάτω: στο όριο');
      expect(eatingFarBelow(card(_est(2600, meanIntake: 1800, slopeKgWeek: -0.6))), isNull, reason: 'ακριβώς 1,5 × 0,40');
      expect(eatingFarBelow(card(_est(2600, meanIntake: 1800, slopeKgWeek: -0.61))), isNotNull);
      expect(eatingFarBelow(card(_est(2600, meanIntake: 1800, slopeKgWeek: -0.73), lowLog: true)), isNull);
      expect(farBelowText(card(_est(2600, meanIntake: 2100, slopeKgWeek: -0.73))), isNull);
    });

    test('πρόταση προς τα κάτω στις 12 πρώτες εβδομάδες: θυμίζει τους νέους μύες και τη μέση', () {
      final down = card(_est(2500), target: 2100, kind: CheckKind.proposal);
      expect(newMuscleNote(down, DateTime(2026, 12, 14)), contains('Αν η μέση σου πέφτει'));
      expect(newMuscleNote(down, DateTime(2027, 2, 8)), isNotNull, reason: '84 μέρες από 16/11');
      expect(newMuscleNote(down, DateTime(2027, 2, 9)), isNull, reason: 'μετά τις 12 εβδομάδες');
      expect(newMuscleNote(card(_est(2900), target: 2400, kind: CheckKind.proposal), DateTime(2026, 12, 14)), isNull, reason: 'προς τα πάνω');
      expect(newMuscleNote(card(_est(2500), target: 2100, kind: CheckKind.proposal, lowLog: true), DateTime(2026, 12, 14)), isNull);
      expect(newMuscleNote(card(_est(2500)), DateTime(2026, 12, 14)), isNull, reason: 'μένει ίδιος');
    });
  });

  group('K1-C-06, K1-C-07, K1-C-08: στόχοι', () {
    test('όρια λιπαρών με ακριβή αριθμητική στις ισοβαθμίες', () {
      expect(fatHiFor(2610), 102, reason: 'πριν 101 (2.610 × 35% ÷ 9 = 101,5)');
      expect((fatLoFor(2150), fatHiFor(2150)), (60, 84));
      expect((fatLoFor(2250), fatHiFor(2250)), (63, 88));
      final c = computeGoals(male: true, age: 40, heightCm: 180, kg: 90, aim: GoalAim.lose, rate: 0.005, activity: 1.5, doctor: false);
      expect((c.kcal, c.fatLo, c.fatHi), (2250, 63, 88));
      expect((_g(kcalSet: 2610).fatLo, _g(kcalSet: 2610).fatHi), (73, 102));
    });

    test('«Εφάρμοσε» και μετά «Ξανά ο οδηγός → Σήμερα» την ίδια μέρα: το ιστορικό μένει σε σειρά', () {
      final today = DateTime(2027, 4, 11, 12);
      final o = _g(since: '2027-03-01', kcalSet: 1850);
      final applied = o.copyWith(kcalSet: 1800).recordChangeFrom(o, today);
      expect([for (final h in applied.hist) (h.day, h.before, h.after)], [('2027-04-11', 1850, 1800)]);
      final wizard = _g(since: '2027-04-11', kcalSet: 2130).recordChangeFrom(applied, today);
      expect([for (final h in wizard.hist) (h.day, h.before, h.after)], [('2027-04-10', 1850, 2130)],
          reason: 'πριν: [(11/4: 1.850 → 1.800), (10/4: 1.800 → 2.130)], εκτός σειράς');
      expect(targetOn(wizard, DateTime(2027, 4, 10)), 1850, reason: 'χθες ίσχυε ο παλιός');
      expect(targetOn(wizard, DateTime(2027, 4, 11)), 2130, reason: 'σήμερα κρίνεται με τον νέο (V-2)');
      // Ο οδηγός με τον ΙΔΙΟ αριθμό μετά από αλλαγή της ίδιας μέρας: η σημερινή μέρα κρίνεται με τον στόχο που ισχύει.
      final sameNumber = _g(since: '2027-04-11', kcalSet: 1800).recordChangeFrom(applied, today);
      expect([for (final h in sameNumber.hist) (h.day, h.before, h.after)], [('2027-04-10', 1850, 1800)]);
      expect(targetOn(sameNumber, DateTime(2027, 4, 11)), 1800);
      // Παλιότερες γραμμές μένουν όπως ήταν, πριν από τη νέα.
      final older = _g(since: '2027-03-01', kcalSet: 1850).copyWith(hist: const [TargetChange(day: '2027-03-20', before: 2000, after: 1850)]);
      final next = _g(since: '2027-04-11', kcalSet: 2130).recordChangeFrom(older, today);
      expect([for (final h in next.hist) (h.day, h.before, h.after)], [('2027-03-20', 2000, 1850), ('2027-04-10', 1850, 2130)]);
    });

    test('ιστορικό με μη πεπερασμένη τιμή: η γραμμή πέφτει, χωρίς σφάλμα', () {
      expect(TargetChange.fromJson({'d': '2027-01-01', 'k0': double.nan, 'k1': 2000}), isNull);
      expect(TargetChange.fromJson({'d': '2027-01-01', 'k0': 2100, 'k1': double.infinity}), isNull);
      expect(TargetChange.fromJson({'d': '2027-01-01', 'k0': 2100, 'k1': 2000})?.after, 2000);
      expect(AdaptLog.fromJson({'d': '2027-01-01', 'te': double.nan, 'k0': 2100, 'k1': 2000}), isNull);
      expect(AdaptLog.fromJson({'d': '2027-01-01', 'te': 2500, 'k0': double.nan, 'k1': 2000}), isNull);
      expect(AdaptLog.fromJson({'d': '2027-01-01', 'te': 2500, 'k0': 2100, 'k1': 2000})?.tdee, 2500);
    });

    test('ο ρυθμός στη σελίδα «Στόχοι» με το τωρινό βάρος, όταν απέχει από του οδηγού', () {
      expect(rateNowText(84.0, 0.005), '0,42 kg την εβδομάδα');
      expect(rateNowText(84.0, 0.005, kgNow: 83.3), '0,42 kg την εβδομάδα', reason: 'κάτω από 1 kg διαφορά');
      expect(rateNowText(84.0, 0.005, kgNow: 78), '0,5% του βάρους την εβδομάδα (τώρα περίπου 0,39 kg)');
      expect(rateNowText(84.0, 0.005, kgNow: double.nan), '0,42 kg την εβδομάδα');
    });
  });

  group('K1-S-06: κείμενα ακρίβειας της ζυγαριάς για το λίπος', () {
    test('δεν λένε πια «συνήθως λιγότερο»· λένε ότι το λάθος πάει και προς τις δύο μεριές', () {
      final r = fatRange(const Profile(birthYear: 1980, birthMonth: 1, sex: 'm', heightCm: 180), DateTime(2026, 11, 20))!;
      expect(r.text, isNot(contains('συνήθως')));
      expect(r.text, contains('η ζυγαριά μπορεί να απέχει αρκετές μονάδες'));
      final info = metricInfos[K.fatPct]!;
      expect(info.accuracy, isNot(contains('συνήθως λιγότερο')));
      expect(info.accuracy, contains('προς τα πάνω ή προς τα κάτω'));
    });
  });

  group('K1-C-03: «Ξανά ο οδηγός» κρατά από προεπιλογή την αρχή που δεν έχει περάσει την πρώτη της εβδομάδα', () {
    Goals monday() => Goals(
        aim: GoalAim.lose,
        rate: 0.005,
        activity: 1.53,
        doctor: false,
        since: '2026-11-23',
        kg: 90,
        age: 40,
        heightCm: 180,
        male: true);

    testWidgets('Σάββατο 21/11, στόχοι με αρχή τη Δευτέρα 23/11: προεπιλογή «Συνεχίζω», η αρχή μένει 23/11', (t) async {
      final store = HealthStore()..setProfile(_me)..setGoals(monday());
      await _wizard(t, store, DateTime(2026, 11, 21, 18));
      await _save(t);
      expect(t.widget<ChoiceChip>(find.byKey(const ValueKey('wizard-start-keep'))).selected, isTrue);
      expect(t.widget<ChoiceChip>(find.byKey(const ValueKey('wizard-start-today'))).selected, isFalse);
      await _save(t);
      expect(store.goals!.since, '2026-11-23', reason: 'πριν: 21/11, με έλεγχο κάθε Σάββατο');
      expect(firstCheckDay(store.goals!).weekday, DateTime.monday);
    });

    testWidgets('Πέμπτη 26/11, μέσα στην πρώτη εβδομάδα, με φαγητό γραμμένο από τη Δευτέρα: «Συνεχίζω», η αρχή μένει 23/11', (t) async {
      FoodStore.shared = checkinFood(DateTime(2026, 11, 26), days: 3); // φαγητό 23–25/11
      addTearDown(() => FoodStore.shared = null);
      final store = HealthStore()..setProfile(_me)..setGoals(monday());
      await _wizard(t, store, DateTime(2026, 11, 26, 18));
      await _save(t);
      expect(t.widget<ChoiceChip>(find.byKey(const ValueKey('wizard-start-keep'))).selected, isTrue);
      expect(find.text('Συνεχίζω (από 23/11)'), findsOneWidget);
      await _save(t);
      expect(store.goals!.since, '2026-11-23', reason: 'πριν: 26/11, δεύτερη «πρώτη εβδομάδα»');
    });

    testWidgets('K1R-09: Πέμπτη 26/11 ΧΩΡΙΣ φαγητό γραμμένο: η δίαιτα δεν έχει αρχίσει, προεπιλογή «Σήμερα» (κανόνας V-1)', (t) async {
      final store = HealthStore()..setProfile(_me)..setGoals(monday());
      await _wizard(t, store, DateTime(2026, 11, 26, 18));
      await _save(t);
      expect(t.widget<ChoiceChip>(find.byKey(const ValueKey('wizard-start-today'))).selected, isTrue);
      expect(t.widget<ChoiceChip>(find.byKey(const ValueKey('wizard-start-keep'))).selected, isFalse);
    });

    testWidgets('K1R-09: αρχή στο μέλλον: το κουμπί γράφει «Όπως το όρισα (από 23/11)»', (t) async {
      final store = HealthStore()..setProfile(_me)..setGoals(monday());
      await _wizard(t, store, DateTime(2026, 11, 21, 18));
      await _save(t);
      expect(find.text('Όπως το όρισα (από 23/11)'), findsOneWidget);
      expect(find.textContaining('Συνεχίζω (από'), findsNothing);
    });
  });

  // ------------------------------------------------------------------------------------- ανεξάρτητος έλεγχος K1 (K1R)
  group('ανεξάρτητος έλεγχος των διορθώσεων (K1R)', () {
    Map<DateTime, double> Function(DateTime, DateTime) reader(Map<DateTime, double> m) =>
        (a, b) => {for (final e in m.entries) if (!e.key.isBefore(a) && !e.key.isAfter(b)) e.key: e.value};

    test('K1R-01: έξι εβδομάδες μετά από κενό, το παράθυρο ΔΕΝ ξαναμπαίνει στην εβδομάδα της επιστροφής', () {
      // Στόχοι 23/11· γιορτές 24/12–2/1 χωρίς φαγητό και ζυγίσεις· επιστροφή 3/1 με +1 kg νερά που φεύγουν ως τις 8/1.
      final g = _g(since: '2026-11-23');
      final tdee = g.calc.tdee;
      final intake = <DateTime, double>{};
      final weights = <(DateTime, double)>[];
      var kg = 90.0;
      for (var d = DateTime(2026, 11, 23); !d.isAfter(DateTime(2027, 2, 28)); d = DateTime(d.year, d.month, d.day + 1)) {
        final off = !d.isBefore(DateTime(2026, 12, 24)) && !d.isAfter(DateTime(2027, 1, 2));
        final water = d.year == 2027 && d.month == 1 && d.day >= 3 && d.day <= 8 ? (8 - d.day) / 5.0 : 0.0;
        if (!off) {
          intake[d] = g.kcal.toDouble();
          if (d.weekday == 1 || d.weekday == 3 || d.weekday == 5) weights.add((d, kg + water));
        }
        kg += ((off ? g.kcal + 600 : g.kcal) - tdee) / kcalPerKg;
      }
      expect(adaptScanDays, 53, reason: '42 + 5 − 1 + 7 (πριν: 46)');
      for (final (day, window) in [(DateTime(2027, 2, 1), 21), (DateTime(2027, 2, 8), 28), (DateTime(2027, 2, 15), 35), (DateTime(2027, 2, 22), 42)]) {
        final r = estimateExpenditure(
            intake: intake,
            weights: [for (final w in weights) if (!w.$1.isAfter(day)) w],
            today: day,
            formulaTdee: tdee,
            goalKcal: g.kcal,
            since: DateTime(2026, 11, 23));
        expect((r.status, r.est!.from, r.est!.windowDays), (AdaptStatus.ok, DateTime(2027, 1, 11), window),
            reason: '$day (πριν, στις 15/2: 42 μέρες από 4/1, μέσα στα νερά της επιστροφής)');
        expect(r.est!.tdee, closeTo(tdee, 1));
      }
      final gap = foodGap(intake: intake, today: DateTime(2027, 2, 15), formulaTdee: tdee, goalKcal: g.kcal, since: DateTime(2026, 11, 23))!;
      expect((gap.from, gap.to, gap.restart), (DateTime(2026, 12, 24), DateTime(2027, 1, 2), DateTime(2027, 1, 3)));
    });

    test('K1R-05: ζυγίσεις πριν από το όριο του κενού δεν κρύβουν την κάρτα «χάνεις γρήγορα»', () {
      // Κενό 15–21/1· −0,5% την εβδομάδα ως 28/1 και −1,6% από 29/1. Ο εβδομαδιαίος έλεγχος της 8/2 έχει απαντηθεί.
      final g = _g().copyWith(checkIn: '2027-02-08');
      final intake = <DateTime, double>{};
      final weights = <(DateTime, double)>[];
      var kg = 90.0;
      for (var d = DateTime(2026, 11, 16); !d.isAfter(DateTime(2027, 2, 12)); d = DateTime(d.year, d.month, d.day + 1)) {
        if (d.isBefore(DateTime(2027, 1, 15)) || d.isAfter(DateTime(2027, 1, 21))) intake[d] = g.kcal.toDouble();
        if (d.weekday == 1 || d.weekday == 3 || d.weekday == 5) weights.add((d, (kg * 10).round() / 10));
        kg -= (d.isBefore(DateTime(2027, 1, 29)) ? 0.005 : 0.016) * kg / 7;
      }
      final today = DateTime(2027, 2, 9);
      final ws = [for (final w in weights) if (!w.$1.isAfter(today)) w];
      expect(fastLossSlope(goals: g, weights: ws, today: today), isNull,
          reason: 'το πλήρες παράθυρο (με τις ζυγίσεις πριν από τις 29/1) δεν είναι «γρήγορο»');
      expect(fastLossPossible(goals: g, weights: ws, today: today), isTrue);
      final c = pendingCheckIn(goals: g, today: today, weights: ws, intake: reader(intake))!;
      expect((c.kind, c.proposal!.current, c.proposal!.target, c.fastDays, c.kgNow), (CheckKind.fast, 2250, 2400, 11, 83.4),
          reason: 'πριν από τη διόρθωση: καμία κάρτα ως τις 11/2');
      expect(c.fastSlope!, closeTo(-1.4, 0.001));
      // Αναγκαίος όρος: σκοπός, μέρα των στόχων, ≥ 4 ζυγίσεις σε ≥ 10 μέρες.
      expect(fastLossPossible(goals: _g(aim: GoalAim.keep), weights: ws, today: today), isFalse);
      expect(fastLossPossible(goals: g, weights: ws.sublist(ws.length - 3), today: today), isFalse);
      expect(fastLossPossible(goals: _g(since: '2027-02-01'), weights: ws, today: today), isFalse);
    });

    CheckIn same({bool tooFast = false, bool recentDiffers = false, bool underweight = false}) {
      final e = _est(2600, windowDays: 42);
      return CheckIn(
          kind: CheckKind.same,
          goals: _g(kcalSet: 2250),
          status: AdaptStatus.ok,
          est: e,
          proposal: AdaptProposal(
              current: 2250, target: 2250, est: e, fastLoss: false, floored: false, recentDiffers: recentDiffers, underweight: underweight),
          kgNow: 80,
          tooFast: tooFast,
          estTarget: 2250);
    }

    Future<void> card(WidgetTester t, CheckIn c) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(400, 2600);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
              body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16), child: CheckInCard(check: c, store: HealthStore(), now: DateTime(2027, 2, 1, 9))))));
      await t.pumpAndSettle();
    }

    testWidgets('K1R-02: κάτω από ΔΜΣ 18,5 η κάρτα γράφει αυτόν τον λόγο, και όταν χάνεις πάνω από 1%', (t) async {
      await card(t, same(tooFast: true, underweight: true));
      expect(find.textContaining('κάτω από το φυσιολογικό για το ύψος σου', findRichText: true), findsOneWidget);
      expect(find.textContaining('πάνω από 1% του βάρους', findRichText: true), findsNothing);
    });

    testWidgets('K1R-02: «οι 3 τελευταίες εβδομάδες όχι» γράφεται με το νέο κείμενο', (t) async {
      await card(t, same(recentDiffers: true));
      expect(
          find.textContaining('Όλο το διάστημα δείχνει ότι ο στόχος θέλει αλλαγή, οι 3 τελευταίες εβδομάδες όμως όχι',
              findRichText: true),
          findsOneWidget);
      expect(find.textContaining('πάνω από 1% του βάρους', findRichText: true), findsNothing);
    });

    testWidgets('όπως πριν: χάνεις πάνω από 1% χωρίς άλλο λόγο → το κείμενο του 1%', (t) async {
      await card(t, same(tooFast: true));
      expect(find.textContaining('Χάνεις όμως πάνω από 1% του βάρους την εβδομάδα', findRichText: true), findsOneWidget);
    });

    test('K1R-03: τα όρια λιπαρών βγαίνουν από μία συνάρτηση (2.610 kcal: 73–102 g παντού)', () {
      expect((fatLoFor(2610), fatHiFor(2610)), (73, 102));
      expect((fatLoFor(2790), fatHiFor(2790)), (78, 109));
      final g = _g(kcalSet: 2610);
      expect((g.fatLo, g.fatHi), (73, 102));
    });

    test('K1R-11: «φάε πιο κοντά στον στόχο» δεν γράφεται μαζί με «λείπει φαγητό από το ημερολόγιο»', () {
      CheckIn k(double tdee) {
        final e = _est(tdee, meanIntake: 1700, slopeKgWeek: -0.7, seKcal: 50);
        return CheckIn(
            kind: CheckKind.same,
            goals: _g(kcalSet: 2250),
            est: e,
            proposal: AdaptProposal(current: 2250, target: 2250, est: e, fastLoss: false, floored: false),
            kgNow: 80,
            estTarget: 2250);
      }

      expect(likelyUnderlogged(k(2300)), isTrue);
      expect(eatingFarBelow(k(2300)), isNotNull);
      expect(farBelowText(k(2300)), isNull, reason: 'δύο αντίθετες συμβουλές στην ίδια κάρτα');
      expect(likelyUnderlogged(k(2600)), isFalse);
      expect(farBelowText(k(2600)), isNotNull);
    });

    test('K1R-11: «τώρα περίπου Χ kg» μόνο με πρόσφατη ζύγιση', () {
      expect(rateNowMaxAgeDays, 14);
      expect(rateNowText(84.0, 0.005, kgNow: 78.0), contains('τώρα περίπου 0,39'));
      expect(rateNowText(84.0, 0.005), isNot(contains('τώρα')));
    });
  });
}
