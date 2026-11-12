// Εβδομαδιαίος έλεγχος θερμίδων στην εφαρμογή (σχέδια A1–A4, 12/11). Φανταστικά δεδομένα (δημόσιο repo).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/adaptive.dart';
import 'package:ygeia_forma/adaptive_check.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/goals.dart';
import 'package:ygeia_forma/main.dart';
import 'package:ygeia_forma/nav.dart';
import 'package:ygeia_forma/pages/goals_page.dart';
import 'package:ygeia_forma/profile.dart';
import 'package:ygeia_forma/theme.dart';

import 'sample_checkin.dart';
import 'sample_data.dart';

final _check = DateTime(2026, 12, 7, 8, 20); // Δευτέρα, 21 μέρες μετά τις 16/11
const _me = Profile(birthYear: 1986, birthMonth: 1, sex: 'm', heightCm: 180);

CheckIn? _pending(Goals g, DateTime today, {double eat = 2250, double tdee = 2600, Set<int> skip = const {}, int weighs = 99}) {
  final food = checkinFood(today, eat: eat, skip: skip);
  final w = simWeights(today, eat: eat, tdee: tdee);
  return pendingCheckIn(
    goals: g,
    today: today,
    weights: dailyWeights(Dashboard.fromJson({...sampleDashboardJson(today), 'body': bodyJson(w.take(weighs).toList())}).body),
    intake: (a, b) => dailyIntake(food, a, b),
  );
}

HealthStore _store(DateTime at, {double eat = 2250, double tdee = 2600, Goals? goals}) {
  final s = HealthStore()
    ..data = Dashboard.fromJson({...sampleDashboardJson(at), 'body': bodyJson(simWeights(at, eat: eat, tdee: tdee))});
  s
    ..history = sampleHistory(at, s.data!)
    ..setProfile(_me)
    ..setGoals(goals ?? checkinGoals());
  return s;
}

Future<void> _today(WidgetTester t, HealthStore s, FoodStore food, DateTime at, {Size size = const Size(400, 2600), double text = 1}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  addTearDown(() => FoodStore.shared = null);
  await t.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.light),
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(text)), child: child!),
    home: Shell(store: s, food: food, initialIndex: Cat.today, now: at),
  ));
  await t.pumpAndSettle();
}

void main() {
  group('δεδομένα', () {
    test('μία ζύγιση τη μέρα: η πρώτη (πρωινή)', () {
      final d = Dashboard.fromJson({
        ...sampleDashboardJson(_check),
        'body': [
          {'time': DateTime(2026, 12, 1, 7, 30).millisecondsSinceEpoch, 'weight': 88.4, 'app': inbodyApp},
          {'time': DateTime(2026, 12, 1, 19, 0).millisecondsSinceEpoch, 'weight': 89.6, 'app': inbodyApp},
          {'time': DateTime(2026, 12, 3, 7, 30).millisecondsSinceEpoch, 'weight': 88.1, 'app': inbodyApp},
        ],
      });
      expect(dailyWeights(d.body), [(DateTime(2026, 12, 1), 88.4), (DateTime(2026, 12, 3), 88.1)]);
    });

    test('θερμίδες ανά μέρα όπως στη Διατροφή· μέρες χωρίς φαγητό λείπουν', () {
      final f = checkinFood(_check, eat: 2250, skip: {2});
      final m = dailyIntake(f, DateTime(2026, 12, 4), DateTime(2026, 12, 6));
      expect(m.keys, [DateTime(2026, 12, 4), DateTime(2026, 12, 6)]);
      expect(m[DateTime(2026, 12, 4)]!, closeTo(2250, 1));
    });
  });

  group('τι εκκρεμεί', () {
    test('μέρα ελέγχου με αρκετά δεδομένα: νέος στόχος ~2.110 (−140)', () {
      final c = _pending(checkinGoals(), _check)!;
      expect(c.kind, CheckKind.proposal);
      expect(c.est!.tdee, closeTo(2600, 30));
      expect(c.proposal!.current, 2250);
      expect(c.proposal!.target, inInclusiveRange(2100, 2120));
      expect((c.days, c.weighs), (21, 9));
    });

    test('«Εφάρμοσε»: ισχύει ο νέος, γράφεται στο ιστορικό, ο δικός σου αριθμός αντικαθίσταται· ξανά σε 7 μέρες', () {
      final c = _pending(checkinGoals(kcalSet: 2400), _check)!;
      expect(c.proposal!.current, 2400);
      final g = applyCheckIn(c, _check);
      expect(g.kcalSet, isNull);
      expect(g.kcal, c.proposal!.target);
      expect(g.checkIn, '2026-12-07');
      expect(g.log.single.applied, isTrue);
      expect(Goals.fromJson(g.toJson())!.toJson(), g.toJson(), reason: 'αποθηκεύεται και διαβάζεται ίδιο');
      expect(_pending(g, _check), isNull, reason: 'μία φορά τη μέρα ελέγχου');
      expect(_pending(g, DateTime(2026, 12, 10)), isNull);
      expect(nextCheckDay(g, DateTime(2026, 12, 10)), DateTime(2026, 12, 14));
      expect(_pending(g, DateTime(2026, 12, 14))?.kind, isNotNull);
    });

    test('«Όχι τώρα»: ο στόχος μένει, η εκτίμηση κρατιέται', () {
      final c = _pending(checkinGoals(), _check)!;
      final g = dismissCheckIn(c, _check);
      expect(g.kcal, 2250);
      expect(g.tdeeEst, closeTo(2600, 30));
      expect((g.log.single.applied, g.log.single.after), (false, 2250));
      expect(_pending(g, _check), isNull);
    });

    test('λίγα δεδομένα: κάρτα «λίγα δεδομένα», όχι πρόταση· «Εντάξει» την κλείνει ως την επόμενη εβδομάδα', () {
      final c = _pending(checkinGoals(), _check, skip: {for (var k = 1; k <= 21; k += 2) k})!;
      expect((c.kind, c.status, c.days), (CheckKind.fewData, AdaptStatus.fewIntakeDays, 10));
      final g = dismissCheckIn(c, _check);
      expect((g.kcal, g.checkIn), (2250, '2026-12-07'));
      expect(g.log, isEmpty);
      final w = _pending(checkinGoals(), _check, weighs: 4)!;
      expect((w.kind, w.status), (CheckKind.fewData, AdaptStatus.fewWeighIns));
    });

    test('πριν από την 21η μέρα: τίποτα (εκτός από γρήγορη απώλεια)', () {
      expect(_pending(checkinGoals(), DateTime(2026, 11, 30)), isNull);
      expect(nextCheckDay(checkinGoals(), DateTime(2026, 11, 20)), DateTime(2026, 12, 7));
    });

    test('γρήγορη απώλεια: άλλη μέρα, +150, μία φορά την εβδομάδα', () {
      final wed = DateTime(2026, 12, 2);
      final c = _pending(checkinGoals(), wed, eat: 1600, tdee: 2900)!;
      expect(c.kind, CheckKind.fast);
      expect(c.proposal!.change, 150);
      expect(c.fastSlope!, lessThan(-0.9));
      final g = applyCheckIn(c, wed);
      expect((g.kcal, g.fastAt, g.checkIn), (2400, '2026-12-02', null));
      expect(_pending(g, DateTime(2026, 12, 3), eat: 1600, tdee: 2900), isNull, reason: 'όχι ξανά μέσα στην εβδομάδα');
      final later = dismissCheckIn(c, wed);
      expect((later.kcal, later.fastAt), (2250, '2026-12-02'));
    });

    test('ιστορικό: το πολύ $adaptLogMax, ίδια μέρα αντικαθίσταται, άκυρα πετιούνται', () {
      var g = checkinGoals();
      for (var i = 0; i < 30; i++) {
        final d = DateTime(2027, 1, 4 + 7 * i);
        g = g.copyWith(addLog: AdaptLog(day: '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}', tdee: 2600, before: 2250, after: 2200, applied: true));
      }
      expect(g.log.length, adaptLogMax);
      g = g.copyWith(addLog: AdaptLog(day: g.log.last.day, tdee: 2500, before: 2200, after: 2150, applied: true));
      expect((g.log.length, g.log.last.after), (adaptLogMax, 2150));
      final j = g.toJson();
      (j['log'] as List).add({'d': 'χθες', 'te': 2600, 'k0': 2000, 'k1': 2000});
      expect(Goals.fromJson(j)!.log.length, adaptLogMax);
      expect(Goals.fromJson({...j, 'fa': '2/12'})!.fastAt, isNull);
    });
  });

  group('οθόνες', () {
    testWidgets('Σήμερα: κάρτα ελέγχου κάτω από τη ζύγιση· «Εφάρμοσε» αλλάζει τον στόχο', (t) async {
      final s = _store(_check);
      await _today(t, s, checkinFood(_check), _check);
      expect(find.byKey(const ValueKey('today-checkin')), findsOneWidget);
      expect(find.text('Έλεγχος θερμίδων · κάθε Δευτέρα'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('checkin-how')));
      await t.pumpAndSettle();
      expect(find.text('Πώς βγήκε ο νέος στόχος'), findsOneWidget);
      await t.tapAt(const Offset(200, 20));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('checkin-apply')));
      await t.tap(find.byKey(const ValueKey('checkin-apply')));
      await t.pumpAndSettle();
      expect(s.goals!.kcalAdapt, inInclusiveRange(2100, 2120));
      expect(find.byKey(const ValueKey('today-checkin')), findsNothing);
    });

    testWidgets('γρήγορη απώλεια: «Όχι τώρα» κλείνει την κάρτα χωρίς αλλαγή', (t) async {
      final wed = DateTime(2026, 12, 2, 8, 20);
      final s = _store(wed, eat: 1600, tdee: 2900);
      await _today(t, s, checkinFood(wed, eat: 1600), wed);
      expect(find.text('Χάνεις πιο γρήγορα από το ασφαλές'), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('checkin-later')));
      await t.tap(find.byKey(const ValueKey('checkin-later')));
      await t.pumpAndSettle();
      expect((s.goals!.kcal, s.goals!.fastAt), (2250, '2026-12-02'));
      expect(find.byKey(const ValueKey('today-checkin')), findsNothing);
    });

    testWidgets('χωρίς στόχους ή πριν φορτωθεί το φαγητό: καμία κάρτα', (t) async {
      final s = _store(_check)..setGoals(null);
      await _today(t, s, checkinFood(_check), _check);
      expect(find.byKey(const ValueKey('today-checkin')), findsNothing);
    });

    testWidgets('360 dp, γράμματα 1,3×: χωρίς ξεχείλισμα', (t) async {
      await _today(t, _store(_check), checkinFood(_check), _check, size: const Size(360, 3000), text: 1.3);
      expect(find.byKey(const ValueKey('today-checkin')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('Στόχοι: μετά τον έλεγχο φαίνεται η εκτίμηση και ο επόμενος έλεγχος', (t) async {
      final c = _pending(checkinGoals(), _check)!;
      final s = _store(_check, goals: applyCheckIn(c, _check));
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(400, 2400);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: GoalsPage(store: s, now: DateTime(2026, 12, 8))));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('goals-adapt-log')), findsOneWidget);
      expect(find.text('Επόμενος έλεγχος: Δευτέρα 14 Δεκεμβρίου'), findsOneWidget);
      expect(find.textContaining('Από τα δεδομένα σου'), findsOneWidget);
    });
  });
}
