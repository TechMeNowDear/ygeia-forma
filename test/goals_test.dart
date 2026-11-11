// Στόχοι, χοληστερίνη, ζώνη περπατήματος, μέση (12/11). Όλοι οι αριθμοί εδώ είναι φανταστικοί (δημόσιο repo).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/backup.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/food/chol.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/goals.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/pages/goals_page.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/main.dart';
import 'package:ygeia_forma/nav.dart';
import 'package:ygeia_forma/pages/waist_sheet.dart';
import 'package:ygeia_forma/profile.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/zone.dart';
import 'package:ygeia_forma/waist.dart';

import 'sample_data.dart';
import 'sample_food.dart';

final _now = DateTime(2026, 11, 12, 10);

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 2400), double textScale = 1.0}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: w,
  ));
  await t.pumpAndSettle();
}

/// Η Διατροφή όπως στην εφαρμογή (μέσα στο Shell, με την κεφαλίδα της κατηγορίας).
Widget _shell(HealthStore store) {
  store
    ..data ??= Dashboard.fromJson(sampleDashboardJson(_now))
    ..history = sampleHistory(_now, store.data!);
  addTearDown(() => FoodStore.shared = null);
  return Shell(store: store, food: sampleFoodStore(_now), initialIndex: Cat.food, now: _now);
}

/// Φανταστικός χρήστης: άνδρας 40 ετών, 180 cm.
const _me = Profile(birthYear: 1986, birthMonth: 1, sex: 'm', heightCm: 180);

Goals _goals({bool doctor = true, int? kcalSet}) => Goals(
      aim: GoalAim.lose,
      rate: 0.005,
      activity: 1.5,
      doctor: doctor,
      since: '2026-11-12',
      kg: 90,
      age: 40,
      heightCm: 180,
      male: true,
      nutsG: 30,
      branG: 40,
      legumesWeek: 4,
      fishWeek: 6,
      kcalSet: kcalSet,
    );

LogEntry _e(DateTime d, String name, double grams) =>
    LogEntry(id: '$name$grams${d.day}', day: dateKey(d), meal: Meal.lunch, food: foodNamed(name), grams: grams, time: d);

void main() {
  group('Στόχοι: υπολογισμός', () {
    test('άνδρας 40, 180 cm, 90 kg, −0,5%/εβδ., μέτρια κίνηση, με οδηγία γιατρού', () {
      final g = computeGoals(male: true, age: 40, heightCm: 180, kg: 90, aim: GoalAim.lose, rate: 0.005, activity: 1.5, doctor: true);
      // Mifflin: 900 + 1125 − 200 + 5 = 1830 · × 1,5 = 2745 · 90 × 0,005 × 7700 / 7 = 495
      expect(g.bmr, closeTo(1830, 1e-9));
      expect(g.tdee, closeTo(2745, 1e-9));
      expect(g.delta, closeTo(-495, 1e-9));
      expect(g.kcal, 2250);
      expect(g.floored, isFalse);
      expect(g.protein, 145); // 1,6 × 90 = 144 → στα 5
      expect(g.fatLo, 63);
      expect(g.fatHi, 88);
      expect(g.satPct, 6);
      expect(g.satMax, 15); // 6% × 2250 / 9
      expect(g.fiber, 30);
      expect(g.salt, 5);
    });

    test('χωρίς οδηγία γιατρού: κορεσμένα κάτω από 10%', () {
      final g = computeGoals(male: true, age: 40, heightCm: 180, kg: 90, aim: GoalAim.keep, rate: 0, activity: 1.5, doctor: false);
      expect(g.kcal, 2750); // 2745 → στα 10
      expect(g.satPct, 10);
      expect(g.satMax, 31);
    });

    test('κάτω όριο ασφαλείας: 1.200 για γυναίκες, 1.500 για άνδρες', () {
      final f = computeGoals(male: false, age: 60, heightCm: 150, kg: 50, aim: GoalAim.lose, rate: 0.0075, activity: 1.4, doctor: false);
      expect(f.kcal, 1200);
      expect(f.floored, isTrue);
      final m = computeGoals(male: true, age: 70, heightCm: 160, kg: 55, aim: GoalAim.lose, rate: 0.0075, activity: 1.4, doctor: false);
      expect(m.kcal, 1500);
      expect(m.floored, isTrue);
    });

    test('αύξηση: πλεόνασμα, όχι έλλειμμα', () {
      final g = computeGoals(male: true, age: 40, heightCm: 180, kg: 90, aim: GoalAim.gain, rate: 0.0025, activity: 1.5, doctor: false);
      expect(g.delta, greaterThan(0));
      expect(g.kcal, 2990); // 2745 + 247,5 = 2992,5 → 2990
    });

    test('αποθήκευση και ανάγνωση· άκυρα δεδομένα δίνουν null (ξανά ο οδηγός, όχι λάθος αριθμοί)', () {
      final g = _goals(kcalSet: 2100).copyWith(betaPer100: 6);
      final back = Goals.fromJson(g.toJson())!;
      expect(back.toJson(), g.toJson());
      expect(back.kcal, 2100);
      expect(back.calc.kcal, 2250);
      expect(back.satMax, (2100 * 0.06 / 9).round(), reason: 'τα κορεσμένα ακολουθούν τις θερμίδες που ισχύουν');
      expect(back.copyWith(clearKcal: true).kcal, 2250);
      expect(back.copyWith(clearBeta: true).betaPer100, isNull);
      expect(Goals.fromJson({...g.toJson(), 'kg': 5}), isNull);
      expect(Goals.fromJson({...g.toJson(), 'aim': 'x'}), isNull);
      expect(Goals.fromJson({...g.toJson(), 'age': 15}), isNull);
      expect(Goals.fromJson('x'), isNull);
    });

    test('πίτουρο από την ετικέτα: γραμμάρια για 3 g β-γλυκάνες, στρογγυλεμένα προς τα πάνω', () {
      expect(branGramsFor(7), 45); // 42,9
      expect(branGramsFor(4.5), 70); // 66,7
      expect(branGramsFor(0), isNull);
      expect(branGramsFor(50), isNull);
    });

    test('κείμενα ρυθμού', () {
      expect(ratePctText(0.0025), '0,25%');
      expect(ratePctText(0.005), '0,5%');
      expect(ratePctText(0.0075), '0,75%');
      expect(rateKgText(90, 0.005), '0,5 kg την εβδομάδα');
      expect(missingForGoals(age: 40, sex: 'm', heightCm: 180, kg: null), ['βάρος']);
    });
  });

  group('Χοληστερίνη: τρόφιμα που ρίχνουν την LDL', () {
    test('ξηροί καρποί, πίτουρο, όσπρια (βρασμένα ÷ 2,5), ψάρι', () {
      final d = DateTime(2026, 11, 10, 13);
      final day = CholDay([
        _e(d, 'Καρύδια', 30),
        _e(d, 'Πίτουρο βρώμης', 40),
        _e(d, 'Φακές (βρασμένες)', 100), // = 40 g ξερές
        _e(d, 'Σολομός (σχάρα ή τηγάνι χωρίς λάδι)', 100),
      ]);
      expect(day.nutsG, 30);
      expect(day.branG, 40);
      expect(day.legumesDryG, closeTo(40, 1e-9));
      expect(day.legumes, isTrue);
      expect(day.fish, isTrue);
      expect(day.full, isFalse, reason: 'λιγότερες από 1.200 kcal: δεν μπαίνει στους μέσους όρους');
      expect(CholDay([_e(d, 'Φακές (βρασμένες)', 90)]).legumes, isFalse);
      expect(CholDay([_e(d, 'Φακές (ξερές)', 40)]).legumes, isTrue);
    });

    test('εβδομάδα: μέσοι όροι μόνο από γεμάτες μέρες', () {
      final mon = DateTime(2026, 11, 9);
      final full = CholDay([_e(mon, 'Καρύδια', 200), _e(mon, 'Πίτουρο βρώμης', 40)]); // 1.418 + 144 kcal
      final thin = CholDay([_e(mon, 'Καρύδια', 10)]);
      final w = CholWeek([(mon, full), (DateTime(2026, 11, 10), thin)]);
      expect(full.full, isTrue);
      expect(w.fullDays, 1);
      expect(w.daysWithNuts(30), 1);
      expect(w.daysWithBran(40), 1);
      expect(w.satPctMean, closeTo(full.satPct!, 1e-9));
      expect(weekStart(DateTime(2026, 11, 15)), DateTime(2026, 11, 9));
    });
  });

  group('Ζώνη περπατήματος', () {
    test('Karvonen 40–59% με ηρεμία, αλλιώς 64–76% των μέγιστων (Tanaka)', () {
      expect(tanakaMax(40), 180);
      final z = computeZone(age: 40, restHr: 60, s: const ZoneSettings())!;
      expect((z.lo, z.hi, z.rest, z.max, z.manual), (108, 131, 60, 180, false));
      final f = computeZone(age: 40, restHr: null, s: const ZoneSettings())!;
      expect((f.lo, f.hi, f.rest), (115, 137, null));
      final m = computeZone(age: 40, restHr: 60, s: const ZoneSettings(lo: 100, hi: 125))!;
      expect((m.lo, m.hi, m.manual), (100, 125, true));
      final t = computeZone(age: 40, restHr: 60, s: const ZoneSettings(maxHr: 190))!;
      expect((t.lo, t.max, t.maxMeasured), (112, 190, true));
      expect(computeZone(age: null, restHr: 60, s: const ZoneSettings()), isNull);
    });

    test('χρόνος κάτω/μέσα/πάνω: παύσεις, κενά και το λεπτό αποκατάστασης δεν μετρούν', () {
      final a = zoneTimes([[0, 100], [10, 120], [20, 140]], [], 108, 131, endSec: 30);
      expect((a.below, a.inZone, a.above), (10, 10, 10));
      final b = zoneTimes([[0, 100], [10, 120], [20, 140]], [[10, 15]], 108, 131, endSec: 30);
      expect(b.inZone, 5);
      final c = zoneTimes([[0, 120], [100, 120], [130, 160]], [], 108, 131, endSec: 110);
      expect((c.inZone, c.above), (25, 0), reason: 'τιμή ισχύει το πολύ 15″· μετά το τέλος τίποτα');
    });

    test('τεστ ομιλίας και ρυθμίσεις', () {
      expect(talkShift('sing'), 5);
      expect(talkShift('no'), -5);
      expect(talkShift('talk'), 0);
      const s = ZoneSettings(lo: 100, hi: 125, maxHr: 185, alertLow: true, talk: [['w1', 'talk']]);
      final back = ZoneSettings.fromJson(s.toJson());
      expect((back.lo, back.hi, back.maxHr, back.alertHigh, back.alertLow), (100, 125, 185, true, true));
      expect(back.talk, [['w1', 'talk']]);
      expect(ZoneSettings.fromJson({'lo': 130, 'hi': 120}).manual, isFalse);
      expect(WalkZone.fromJson({'lo': 108, 'hi': 131}), const WalkZone(108, 131));
      expect(WalkZone.fromJson({'lo': 131, 'hi': 108}), isNull);
    });

    test('η εβδομάδα: λεπτά στη ζώνη ή πιο πάνω, μέρες με βάρη, περπατήματα χωρίς μέτρηση', () {
      Session walk(int day, List<int>? zt) => Session(
            id: 'w$day',
            workout: 'walk',
            name: 'Περπάτημα',
            programId: 'p',
            start: DateTime(2026, 11, day, 8),
            end: DateTime(2026, 11, day, 9),
            cardioMinutes: 40,
            activity: 'walk',
          )..zoneTimes = zt;
      final out = weekMovement([
        walk(9, [120, 1800, 300]),
        walk(10, null),
        walk(2, [0, 3000, 0]), // προηγούμενη εβδομάδα
      ], DateTime(2026, 11, 12));
      expect(out.moderateMin, 35);
      expect(out.unmeasuredWalks, 1);
      expect(out.strengthDays, 0);
    });
  });

  group('Μέση και μέρες ζυγίσματος', () {
    test('μέσος όρος· με 3 μετρήσεις, των δύο πιο κοντινών', () {
      expect(const WaistEntry('2026-11-13', [98, 99]).cm, 98.5);
      expect(const WaistEntry('2026-11-13', [98, 100.5, 99]).cm, 98.5);
      expect(needsThird(98, 99), isFalse);
      expect(needsThird(98, 99.5), isTrue);
      expect(WaistEntry.fromJson({'d': '2026-11-13', 'v': [20]}), isNull);
    });

    test('επαναφορά: οι μέρες του κινητού μένουν, μπαίνουν όσες λείπουν', () {
      final merged = mergeWaist([
        {'d': '2026-11-13', 'v': [98, 98]},
      ], [
        {'d': '2026-11-13', 'v': [90, 90]},
        {'d': '2026-11-06', 'v': [99, 99]},
      ]);
      expect(merged.map((e) => e['d']), ['2026-11-06', '2026-11-13']);
      expect(merged.last['v'], [98.0, 98.0]);
      expect(backupPrefKeys, containsAll(['goals', 'zone', 'waist']));
    });

    test('παλιές ρυθμίσεις: μία μέρα ζυγίσματος γίνεται η λίστα', () {
      expect(Profile.fromJson({'wd': 3}).weighDays, {3});
      expect(Profile.fromJson({'wd': 5}).weighDays, Profile.defaultWeighDays);
      expect(Profile.fromJson({}).weighDays, {1, 3, 5});
      expect(Profile.fromJson({'wds': [2, 4]}).weighDays, {2, 4});
      expect(Profile.fromJson({}).waistDay, DateTime.friday);
      final p = Profile.fromJson(const Profile(weighDays: {1, 4}, waistDay: 6).toJson());
      expect(p.weighDays, {1, 4});
      expect(p.waistDay, 6);
    });
  });

  group('Οθόνες', () {
    testWidgets('ο οδηγός: βάρος με το χέρι, γιατρός «Ναι» → 2.250 kcal και η σελίδα «Στόχοι»', (t) async {
      final store = HealthStore()..setProfile(_me);
      await _pump(t, Builder(builder: (context) => Scaffold(body: Center(child: FilledButton(
        key: const ValueKey('open'),
        onPressed: () => openGoals(context, store, now: _now),
        child: const Text('open'),
      )))));
      await t.tap(find.byKey(const ValueKey('open')));
      await t.pumpAndSettle();
      expect(find.byType(GoalsWizard), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('wizard-next'))).onPressed, isNull, reason: 'χωρίς βάρος δεν προχωρά');
      await t.enterText(find.byKey(const ValueKey('wizard-kg')), '90');
      await t.pumpAndSettle();
      Future<void> next() async {
        await t.tap(find.byKey(const ValueKey('wizard-next')));
        await t.pumpAndSettle();
      }

      await next(); // στόχος (προεπιλογή: λιγότερο λίπος)
      await next(); // ρυθμός (προεπιλογή: μέτρια, 0,5%)
      await next(); // κίνηση (προεπιλογή: μέτρια)
      await next(); // γιατρός
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('wizard-next'))).onPressed, isNull, reason: 'πρέπει να απαντήσει');
      await t.tap(find.byKey(const ValueKey('opt-doc-yes')));
      await t.pumpAndSettle();
      await next();
      expect(find.text('2.250 kcal', findRichText: true), findsOneWidget);
      expect(find.text('έως 15 g · 6%'), findsOneWidget);
      await next();
      expect(find.byType(GoalsPage), findsOneWidget);
      final g = store.goals!;
      expect((g.kcal, g.protein, g.doctor, g.kg, g.since), (2250, 145, true, 90.0, '2026-11-12'));
      expect(find.byKey(const ValueKey('goals-bran')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('«Ίδιο βάρος» παραλείπει την ερώτηση για τον ρυθμό', (t) async {
      final store = HealthStore()..setProfile(_me);
      await _pump(t, GoalsWizard(store: store, now: _now));
      await t.enterText(find.byKey(const ValueKey('wizard-kg')), '90');
      await t.pumpAndSettle();
      expect(find.textContaining('1 από 6'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('wizard-next')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('opt-aim-keep')));
      await t.pumpAndSettle();
      expect(find.textContaining('2 από 5'), findsOneWidget);
    });

    testWidgets('σελίδα «Στόχοι»: αλλαγή θερμίδων και επιστροφή στον υπολογισμό', (t) async {
      final store = HealthStore()..setProfile(_me)..setGoals(_goals());
      await _pump(t, GoalsPage(store: store, now: _now));
      await t.tap(find.byKey(const ValueKey('goals-kcal')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('number-field')), '2100');
      await t.tap(find.byKey(const ValueKey('number-ok')));
      await t.pumpAndSettle();
      expect(store.goals!.kcal, 2100);
      expect(find.textContaining('ο υπολογισμός λέει 2.250'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('goals-how')));
      await t.pumpAndSettle();
      expect(find.text('Πώς υπολογίστηκαν οι θερμίδες'), findsOneWidget);
    });

    testWidgets('πίτουρο από την ετικέτα: 7 g β-γλυκάνες → 45 g', (t) async {
      final store = HealthStore()..setProfile(_me)..setGoals(_goals());
      await _pump(t, GoalsPage(store: store, now: _now));
      await t.tap(find.byKey(const ValueKey('goals-bran')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('bran-beta')), '7');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('bran-ok')));
      await t.pumpAndSettle();
      expect((store.goals!.branG, store.goals!.betaPer100), (45, 7.0));
    });

    testWidgets('Διατροφή με στόχους: «Μένουν», μπάρες και κάρτα «Χοληστερίνη»', (t) async {
      final store = HealthStore()..setProfile(_me)..setGoals(_goals());
      await _pump(t, _shell(store), size: const Size(400, 3000));
      expect(find.byKey(const ValueKey('nutrition-goals')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('nutrition-goals')), matching: find.text('Μένουν')), findsOneWidget);
      expect(find.text('Πρωτεΐνη'), findsWidgets);
      expect(find.byKey(const ValueKey('nutrition-chol')), findsOneWidget);
      await t.tap(find.text('Χοληστερίνη · τι τη ρίχνει'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('chol-range')), findsOneWidget);
      await t.tap(find.text('4 εβδομάδες'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });

    testWidgets('Διατροφή χωρίς στόχους: πρόσκληση στον οδηγό, χωρίς κάρτα χοληστερίνης', (t) async {
      final store = HealthStore()..setProfile(_me);
      await _pump(t, _shell(store), size: const Size(400, 3000));
      expect(find.byKey(const ValueKey('nutrition-goals-cta')), findsOneWidget);
      expect(find.byKey(const ValueKey('nutrition-chol')), findsNothing);
    });

    testWidgets('Διατροφή με 2,0× γράμματα στο 360: τίποτα δεν ξεχειλίζει', (t) async {
      final store = HealthStore()..setProfile(_me)..setGoals(_goals());
      await _pump(t, _shell(store),
          size: const Size(360, 5000), textScale: 2.0);
      expect(t.takeException(), isNull);
    });

    testWidgets('φύλλο «Μέση»: τρίτη μέτρηση όταν διαφέρουν πάνω από 1 cm', (t) async {
      final store = HealthStore()..setProfile(_me);
      await _pump(t, Builder(builder: (context) => Scaffold(body: Center(child: FilledButton(
        key: const ValueKey('open'),
        onPressed: () => openWaistSheet(context, store, now: _now),
        child: const Text('open'),
      )))));
      await t.tap(find.byKey(const ValueKey('open')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('waist-0')), '98');
      await t.enterText(find.byKey(const ValueKey('waist-1')), '100');
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('waist-2')), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('waist-save'))).onPressed, isNull);
      await t.enterText(find.byKey(const ValueKey('waist-2')), '99');
      await t.pumpAndSettle();
      expect(find.text('98,5 cm'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('waist-save')));
      await t.pumpAndSettle();
      expect(store.waist.single.day, '2026-11-12');
      expect(store.waist.single.cm, 98.5);
    });
  });
}
