// Round 7 · f5: Σήμερα, widgets αρχικής οθόνης, Σώμα. Φανταστικές τιμές (δημόσιο repo).
// R7-U1-1/2/3/5/6/7/8/10/11/12/14, R7-A4-1/2/3 (+B2), R7-A2-1, R7-A10-1, R7-A12-7. Οι αναμενόμενες τιμές από τον κανόνα
// (python: /home/claude/scratch/f5r7/*.py), όχι από τον νέο κώδικα.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/food/food_model.dart' show LogEntry, Meal, Totals;
import 'package:ygeia_forma/food/food_store.dart' show FoodStore;
import 'package:ygeia_forma/format.dart' show dayOf;
import 'package:ygeia_forma/history.dart' show K, bodyRows, dateKey, mergeBody;
import 'package:ygeia_forma/home_widgets/widget_bridge.dart' show WidgetPublisher, widgetChannel;
import 'package:ygeia_forma/home_widgets/widget_snapshot.dart' show buildWidgetSnapshot, workoutSnapshot;
import 'package:ygeia_forma/home_widgets/widget_style.dart' show WKind, wMetrics;
import 'package:ygeia_forma/nav.dart' show Cat, FoodTab;
import 'package:ygeia_forma/pages/body.dart' show BodyPage, laterWeighInText;
import 'package:ygeia_forma/pages/metric_page.dart' show MetricPage, metricSpecs;
import 'package:ygeia_forma/pages/nutrition.dart' show FoodTodayCard;
import 'package:ygeia_forma/pages/today.dart' show TodayPage, waistTodayHint;
import 'package:ygeia_forma/pages/training/today_training_card.dart' show TodayTrainingCard;
import 'package:ygeia_forma/pages/week_card.dart' show WeekCard;
import 'package:ygeia_forma/profile.dart' show Profile;
import 'package:ygeia_forma/reference.dart' show bmiOf, bmiText, healthyWeight, healthyWeightText;
import 'package:ygeia_forma/sources.dart' show SourcePlan;
import 'package:ygeia_forma/theme.dart' show Aigaio, buildTheme;
import 'package:ygeia_forma/training/session.dart' show Session;
import 'package:ygeia_forma/training/training_store.dart' show MemoryTrainingIO, TrainingStore;
import 'package:ygeia_forma/waist.dart' show WaistEntry;
import 'package:ygeia_forma/weight_guard.dart' show WeighStatus, weighStatusAt, weightsAgree;
import 'package:ygeia_forma/widgets.dart' show BigValue, InfoRow, LineChart, StatCard, TrendPill;

import 'sample_data.dart' show sampleDashboardJson, sampleHistory;
import 'sample_food.dart' show basicFoods, foodNamed, sampleFoodStore;
import 'training_sample.dart' show sampleProgram, sampleTraining;

const _inbody = 'com.inbody2014.inbody';

BodyMeasurement _m(DateTime t, double kg, [double? fat]) => BodyMeasurement(time: t, weight: kg, fatPct: fat, app: _inbody);

/// Ανάγνωση της στιγμής [at] με τις ζυγίσεις [rows] (όπως r6_body_test), ύψος 180 cm, γεννημένος 12/1985 (φανταστικός).
HealthStore _store(DateTime at, List<BodyMeasurement> rows, {Profile? profile}) {
  final s = HealthStore()
    ..data = Dashboard.fromJson({
      ...sampleDashboardJson(at),
      'body': [
        for (final b in rows)
          {
            'time': b.time.millisecondsSinceEpoch,
            'weight': b.weight,
            if (b.fatPct != null) 'fatPct': b.fatPct,
            'app': _inbody,
          },
      ],
    });
  s.history = sampleHistory(at, s.data!);
  applyRecentRead(s.history, s.data!, plan: SourcePlan.samsungOnly);
  s.setProfile(profile ?? const Profile(birthYear: 1985, birthMonth: 12, sex: 'm', heightCm: 180));
  return s;
}

/// Δε/Τε/Πα 07:15 από Δευτέρα 16/11, −0,5 kg την εβδομάδα (ίδιες τιμές με το r6_body_test). Λίπος 27,0· 29,0 από 30/11.
final _own = <(DateTime, double, double)>[
  (DateTime(2026, 11, 16, 7, 15), 82.0, 27.0),
  (DateTime(2026, 11, 18, 7, 15), 81.9, 27.0),
  (DateTime(2026, 11, 20, 7, 15), 81.7, 27.0),
  (DateTime(2026, 11, 23, 7, 15), 81.5, 27.0),
  (DateTime(2026, 11, 25, 7, 15), 81.4, 27.0),
  (DateTime(2026, 11, 27, 7, 15), 81.2, 27.0),
  (DateTime(2026, 11, 30, 7, 15), 81.0, 29.0),
  (DateTime(2026, 12, 2, 7, 15), 80.9, 29.0),
  (DateTime(2026, 12, 4, 7, 15), 80.7, 29.0),
];

List<BodyMeasurement> _ownUpTo(DateTime last) => [
      for (final (t, kg, fat) in _own)
        if (!t.isAfter(last)) _m(t, kg, fat),
    ];

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 4000)}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: w)));
  await t.pumpAndSettle();
}

Widget _today(HealthStore s, DateTime now, {FoodStore? food, TrainingStore? training, void Function(int, [int?])? open}) =>
    TodayPage(
      store: s,
      food: food ?? sampleFoodStore(now),
      training: training,
      open: open ?? (_, [__]) {},
      openSettings: () {},
      now: now,
    );

StatCard _weightCard(WidgetTester t) =>
    t.widgetList<StatCard>(find.byType(StatCard)).firstWhere((c) => c.icon == Icons.monitor_weight_rounded);

String? _row(WidgetTester t, String label) {
  for (final r in t.widgetList<InfoRow>(find.byType(InfoRow))) {
    if (r.label == label) return r.value;
  }
  return null;
}

Map _kinds(HealthStore s, DateTime now, {FoodStore? food}) =>
    buildWidgetSnapshot(s, food ?? sampleFoodStore(now), now)['kinds'] as Map;

Map _widgetBody(HealthStore s, DateTime now) => (_kinds(s, now)[WKind.body] as Map)['m'] as Map;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // -------------------------------------------------------------------------------------------------------------------
  group('U1-1 / U1-11: «Η εβδομάδα σου»', () {
    // Δευτέρα: η κάρτα της εβδομάδας φαίνεται (reviewWeekSunday).
    final mon = DateTime(2026, 11, 16, 9);

    // Round 9 (R9-U1-2): ούτε στη δεξιά στήλη (τρύπα ~750 dp αριστερά, στιγμιότυπο 68e): κάτω από τις δύο στήλες, σε όλο
    // το πλάτος. Η παλιά προσδοκία («ίδια στήλη με τη Διατροφή», dx > 430) κλείδωνε τη διάταξη με την τρύπα.
    testWidgets('U1-1 / R9-U1-2: ανοιχτό Fold (860 dp): κάτω από τις δύο στήλες, σε όλο το πλάτος (πριν αριστερά ή δεξιά)',
        (t) async {
      await _pump(t, _today(_store(mon, _ownUpTo(mon)), mon), size: const Size(860, 4000));
      expect(find.byType(WeekCard), findsOneWidget);
      final week = t.getRect(find.byType(WeekCard));
      final food = t.getRect(find.byType(FoodTodayCard));
      expect(week.left, lessThan(food.left), reason: 'ξεκινά από την αριστερή στήλη');
      expect(week.right, closeTo(food.right, 1), reason: 'ως το δεξί άκρο της δεξιάς στήλης');
      expect(week.top, greaterThan(food.bottom));
    });

    testWidgets('U1-11: «4 προηγούμενες: …», ποτέ «πριν 7 ώρες…» / «πριν 23:40»', (t) async {
      await _pump(t, _today(_store(mon, _ownUpTo(mon)), mon));
      final card = find.byType(WeekCard);
      expect(card, findsOneWidget);
      expect(find.descendant(of: card, matching: find.textContaining(RegExp(r'^πριν \d'))), findsNothing);
      expect(find.descendant(of: card, matching: find.textContaining('4 προηγούμενες: ')), findsWidgets);
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('U1-2: τίτλος «Βάρος» σε σχέση με τώρα, με τη μορφή «Δευ 16/11»', () {
    final rows = [_m(DateTime(2026, 11, 13, 7, 15), 82.3), _m(DateTime(2026, 11, 16, 7, 15), 82.0)];

    testWidgets('Τετ 18/11 07:10 με αποθηκευμένη ανάγνωση Τρί 23:40: «Βάρος · Δευ 16/11» (πριν «Βάρος · Χθες»)', (t) async {
      final now = DateTime(2026, 11, 18, 7, 10);
      await _pump(t, _today(_store(DateTime(2026, 11, 17, 23, 40), rows), now));
      expect(_weightCard(t).title, 'Βάρος · Δευ 16/11');
    });

    testWidgets('Τρί 17/11 09:00: «Βάρος · Δευ 16/11» (πριν «Βάρος · Χθες»)· σημερινή ζύγιση: σκέτο «Βάρος»', (t) async {
      final now = DateTime(2026, 11, 17, 9);
      await _pump(t, _today(_store(now, rows), now));
      expect(_weightCard(t).title, 'Βάρος · Δευ 16/11');
      final mon = DateTime(2026, 11, 16, 9);
      await _pump(t, _today(_store(mon, rows), mon));
      expect(_weightCard(t).title, 'Βάρος');
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('U1-3 / U1-8: κάρτα «Σήμερα ζύγιση και μέση»', () {
    final fri = DateTime(2026, 12, 4);
    String hint(WidgetTester t) => t.widget<Text>(find.byKey(const ValueKey('today-weigh-hint'))).data!;

    testWidgets('Παρασκευή μετά τη ζύγιση: μένει η μέση → η οδηγία της μέσης, όχι «με τα ίδια ρούχα»', (t) async {
      final now = DateTime(2026, 12, 4, 9);
      await _pump(t, _today(_store(now, _ownUpTo(now)), now));
      expect(find.byKey(const ValueKey('today-weigh')), findsOneWidget);
      expect(hint(t), waistTodayHint);
      expect(find.textContaining('με τα ίδια ρούχα'), findsNothing);
      expect(fri.weekday, DateTime.friday);
    });

    testWidgets('Παρασκευή πριν τη ζύγιση: η οδηγία ζυγίσματος', (t) async {
      final now = DateTime(2026, 12, 4, 6, 30);
      await _pump(t, _today(_store(now, _ownUpTo(DateTime(2026, 12, 3))), now));
      expect(hint(t), contains('με τα ίδια ρούχα'));
    });

    testWidgets('μέρα ΜΟΝΟ μέσης (ζύγισμα Δε/Τε): η οδηγία της μέσης', (t) async {
      final now = DateTime(2026, 12, 4, 6, 30);
      final p = const Profile(birthYear: 1985, birthMonth: 12, sex: 'm', heightCm: 180, weighDays: {DateTime.monday, DateTime.wednesday});
      await _pump(t, _today(_store(now, _ownUpTo(DateTime(2026, 12, 3)), profile: p), now));
      expect(hint(t), waistTodayHint);
      expect(find.textContaining('με τα ίδια ρούχα'), findsNothing);
    });

    testWidgets('U1-8: το περίγραμμα του «Γράψε τη μέση» στο πλήρες χρώμα του Σώματος', (t) async {
      final now = DateTime(2026, 12, 4, 9);
      await _pump(t, _today(_store(now, _ownUpTo(now)), now));
      final btn = find.byKey(const ValueKey('today-waist'));
      final side = t.widget<OutlinedButton>(btn).style!.side!.resolve(<WidgetState>{})!;
      expect(side.color, Aigaio.of(t.element(btn)).body);
    });

    test('U1-8: περίγραμμα ≥ 3:1 (WCAG 1.4.11) πάνω στο φόντο της κάρτας, σε όλα τα θέματα (πριν 1,86–3,05:1)', () {
      for (final th in [...Aigaio.dayThemes, ...Aigaio.nightThemes]) {
        final bg = Color.alphaBlend(th.tint(th.body), th.background);
        expect(Aigaio.contrast(th.body, bg), greaterThanOrEqualTo(3.0), reason: th.id);
      }
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('U1-12 / U1-14: Διατροφή από τη Σήμερα', () {
    testWidgets('U1-12: η κάρτα «Διατροφή · σήμερα» ανοίγει το ημερολόγιο στη ΣΗΜΕΡΙΝΗ μέρα (πριν: όποια είχε μείνει)', (t) async {
      final now = DateTime(2026, 11, 16, 13, 30);
      final food = sampleFoodStore(now)..setDay(DateTime(2026, 11, 15));
      final opened = <(int, int?)>[];
      await _pump(t, _today(_store(now, _ownUpTo(now)), now, food: food, open: (c, [tab]) => opened.add((c, tab))));
      expect(food.day, DateTime(2026, 11, 15));
      t.widget<FoodTodayCard>(find.byType(FoodTodayCard)).onOpen();
      expect(food.day, dayOf(now));
      expect(opened, [(Cat.food, FoodTab.diary)]);
    });

    testWidgets('U1-14: χωρίς άδεια της Samsung Health: «+ Φαγητό» και η προπόνηση της μέρας μένουν', (t) async {
      final now = DateTime(2026, 11, 16, 10); // Δευτέρα: «Προπόνηση Β» στο δοκιμαστικό πρόγραμμα
      final s = HealthStore();
      expect(s.data, isNull);
      await _pump(t, _today(s, now, training: sampleTraining(now)));
      expect(find.text('Σύνδεση με Samsung Health'), findsWidgets);
      expect(find.byKey(const ValueKey('today-add-food')), findsOneWidget);
      expect(find.byType(TodayTrainingCard), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('U1-5: widget «Προπόνηση σήμερα» = κάρτα «Άσκηση σήμερα»', () {
    // Δοκιμαστικό πρόγραμμα: Δευτέρα «Προπόνηση Β» (βάρη), Τρίτη περπάτημα 30′.
    TrainingStore store(DateTime now, List<Session> sessions) {
      final p = sampleProgram()
        ..version = 1
        ..savedAt = now.subtract(const Duration(days: 20));
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => now)
        ..replaceAll({
          'v': 1,
          'programs': [p.toJson()],
          'active': p.id,
          'sessions': [for (final s in sessions) s.toJson()],
        });
      t.ready = true;
      return t;
    }

    Session walk(DateTime start, int activeMin, int totalMin) => Session(
        id: 'w${start.day}',
        workout: 'walk',
        name: 'Περπάτημα',
        programId: 'p-claude-1',
        start: start,
        end: start.add(Duration(minutes: totalMin)),
        cardioMinutes: activeMin);

    Session weights(DateTime start, int minutes) => Session(
        id: 'b${start.day}',
        workout: 'B',
        name: 'Προπόνηση Β',
        programId: 'p-claude-1',
        start: start,
        end: start.add(Duration(minutes: minutes)));

    test('Δευτέρα (βάρη) με πρωινό περπάτημα: ΟΧΙ «έγινε» (πριν «Έγινε σήμερα · Περπάτημα · 40 λεπτά»)', () {
      final mon = DateTime(2026, 11, 16);
      final w = workoutSnapshot(store(DateTime(2026, 11, 16, 9), [walk(DateTime(2026, 11, 16, 7, 30), 30, 40)]), mon);
      expect(w.containsKey('done'), isFalse);
      expect(w.containsKey('doneText'), isFalse);
      expect(((w['week'] as Map)['1'] as Map)['t'], 'Προπόνηση Β', reason: 'το widget λέει την προπόνηση της μέρας');
    });

    test('Δευτέρα: μετά τα βάρη «έγινε», με τη διάρκεια της προπόνησης', () {
      final mon = DateTime(2026, 11, 16);
      final w = workoutSnapshot(
          store(DateTime(2026, 11, 16, 19), [walk(DateTime(2026, 11, 16, 7, 30), 30, 40), weights(DateTime(2026, 11, 16, 18), 52)]),
          mon);
      expect(w['done'], '2026-11-16');
      expect(w['doneText'], 'Προπόνηση Β · 52 λεπτά');
    });

    test('Τρίτη (περπάτημα): «έγινε» με τα ΕΝΕΡΓΑ λεπτά (30, όχι λήξη − αρχή 38)', () {
      final tue = DateTime(2026, 11, 17);
      final w = workoutSnapshot(store(DateTime(2026, 11, 17, 9), [walk(DateTime(2026, 11, 17, 7, 30), 30, 38)]), tue);
      expect(w['done'], '2026-11-17');
      expect(w['doneText'], 'Περπάτημα · 30 λεπτά');
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('U1-7 / U1-10: κείμενα των widgets', () {
    final now = DateTime(2026, 11, 7, 10, 20);

    test('U1-7: «Βαθμολογία», όχι «Σκορ»· U1-10: πηγή κίνησης «Samsung · 10:20» με σύντομη «10:20»', () {
      final s = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(now));
      s.history = sampleHistory(now, s.data!);
      final snap = buildWidgetSnapshot(s, sampleFoodStore(now), now);
      expect(jsonEncode(snap), isNot(contains('Σκορ')));
      final kinds = snap['kinds'] as Map;
      final score = ((kinds[WKind.sleep] as Map)['m'] as Map)['sleepScore'] as Map?;
      if (score != null) expect(score['l'], 'Βαθμολογία');
      expect(wMetrics[WKind.sleep]!.firstWhere((m) => m.key == K.sleepScore).name, 'Βαθμολογία ύπνου');
      final move = kinds[WKind.move] as Map;
      expect(move['src'], 'Samsung · 10:20');
      expect(move['srcShort'], '10:20');
    });

    test('U1-7: ζωγράφος (Kotlin) και «Γρήγορο φαγητό»: «Βαθμολογία», «Σάρωση»', () {
      final kt = File('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/WidgetRenderer.kt').readAsStringSync();
      expect(kt, contains('"sleepScore" -> "Βαθμολογία"'));
      expect(kt, isNot(contains('"Σκορ"')));
      expect(kt, isNot(contains('"ρολόι · ')));
      final xml = File('tools/android/layout/quick_food_widget.xml').readAsStringSync();
      expect(xml, contains('android:text="Σάρωση"'));
      expect(xml, isNot(contains('android:text="Barcode"')));
      final hw = File('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/HomeWidgets.kt').readAsStringSync();
      expect(hw, isNot(contains('"ρολόι · ')));
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  test('A2-1: θερμίδες του widget = της εφαρμογής (άθροισμα των στρογγυλεμένων ανά καταχώριση)', () {
    final now = DateTime(2026, 11, 16, 13);
    // 3 × 10 g φιλέτο μοσχαριού (153 kcal / 100 g): 15,3 → 15 ανά καταχώριση· η εφαρμογή γράφει 45, το σύνολο 45,9 → 46.
    final beef = foodNamed('Μοσχαρίσιο φιλέτο, άπαχο (ωμό)');
    final entries = [
      for (var i = 0; i < 3; i++)
        LogEntry(id: 'k$i', day: dateKey(now), meal: Meal.lunch, food: beef, grams: 10, time: DateTime(2026, 11, 16, 13, i)),
    ];
    final food = FoodStore.preloaded(foods: basicFoods(), entries: entries, now: now);
    final t = Totals(entries);
    expect(t.shownKcal, 45);
    expect(t.kcal.round(), 46, reason: 'η δοκιμή έχει νόημα μόνο αν διαφέρουν');
    final kcal = ((_kinds(HealthStore(), now, food: food)[WKind.food] as Map)['m'] as Map)['kcal'] as Map;
    expect(kcal['v'], '45');
    expect((kcal['s'] as List).last, 45.0, reason: 'και το γράφημα 7 ημερών με τον ίδιο κανόνα');
  });

  // -------------------------------------------------------------------------------------------------------------------
  test('A10-1: ίδια δεδομένα → ΚΑΜΙΑ νέα ζωγραφική των widgets, ας άλλαξε η ώρα· άλλα δεδομένα → μία', () async {
    final calls = <String>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(widgetChannel, (call) async {
      calls.add(call.method);
      return call.method == 'count' ? 1 : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(widgetChannel, null));
    final read = DateTime(2026, 11, 16, 9);
    var clock = DateTime(2026, 11, 16, 9, 30);
    final store = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(read));
    final publisher = WidgetPublisher(store, sampleFoodStore(read), clock: () => clock);
    int updates() => calls.where((c) => c == 'update').length;

    await publisher.publish();
    expect(updates(), 1);
    clock = clock.add(const Duration(seconds: 2));
    await publisher.publish();
    clock = clock.add(const Duration(minutes: 5));
    await publisher.publish();
    expect(updates(), 1, reason: 'πριν: 3 (το «at» άλλαζε σε κάθε δημοσίευση)');

    store.data = Dashboard.fromJson({
      ...sampleDashboardJson(read),
      'activity': {'calories': 1500.0, 'activeCalories': 120.0, 'activeMinutes': 25, 'distance': 2100.0},
    });
    clock = clock.add(const Duration(seconds: 2));
    await publisher.publish();
    expect(updates(), 2);
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('A4-1: το Σώμα δείχνει τη ζύγιση της μέρας, όπως η Σήμερα και το widget', () {
    // Πα 4/12 07:15 80,7 (λίπος 29,0) και 20:30 82,1 (λίπος 27,6) μετά το φαγητό: συμφωνούν (1,4 kg), δεν είναι ξένη.
    final now = DateTime(2026, 12, 4, 21);
    final rows = [..._ownUpTo(now), _m(DateTime(2026, 12, 4, 20, 30), 82.1, 27.6)];

    testWidgets('Σώμα: 80,7 με «−0,2 kg από 2/12», δείκτης 24,9, «Μέσα στο εύρος», λίπος 29,0 (+2,0)· η βραδινή σε γκρι', (t) async {
      await _pump(t, BodyPage(store: _store(now, rows), now: now));
      expect(t.widgetList<BigValue>(find.byType(BigValue)).first.value, '80,7', reason: 'πριν 82,1');
      final pills = [for (final p in t.widgetList<TrendPill>(find.byType(TrendPill))) if (p.text.contains(' kg από ')) p.text];
      expect(pills, ['−0,2 kg από 2/12'], reason: 'πριν «+1,2 kg από 2/12»');
      expect(_row(t, 'Βάρος'), '80,7 kg  (−0,2)');
      expect(_row(t, 'Λίπος'), '29,0%  (+2,0)', reason: 'πριν «27,6%  (+2,0)»: τάση δίπλα σε τιμή που δεν μετρά');
      expect(_row(t, 'Δείκτης μάζας σώματος'), '24,9', reason: 'πριν 25,3');
      expect(find.text('Μέσα στο εύρος · φυσιολογικός δείκτης για το ύψος σου: 60,0–80,9 kg'), findsOneWidget,
          reason: 'πριν «Πάνω από το εύρος»');
      expect(t.widget<Text>(find.byKey(const ValueKey('body-later-weighin'))).data,
          'Και 20:30: 82,1 kg· μετρά μία ζύγιση τη μέρα, η πρώτη.');
      expect(laterWeighInText(rows.last), 'Και 20:30: 82,1 kg· μετρά μία ζύγιση τη μέρα, η πρώτη.');
    });

    testWidgets('Σήμερα και widget: η ίδια τιμή 80,7', (t) async {
      final s = _store(now, rows);
      await _pump(t, _today(s, now));
      expect(_weightCard(t).value, '80,7');
      expect((_weightCard(t).trend! as TrendPill).text, '−0,2 kg από 2/12');
      final m = _widgetBody(s, now);
      expect((m['weight'] as Map)['v'], '80,7');
      expect((m['bmi'] as Map)['v'], '24,9');
      expect((m['bmi'] as Map)['r'], 'μέσα στο εύρος');
    });

    testWidgets('μία ζύγιση τη μέρα: καμία γκρι γραμμή', (t) async {
      await _pump(t, BodyPage(store: _store(DateTime(2026, 12, 4, 9), _ownUpTo(now)), now: DateTime(2026, 12, 4, 9)));
      expect(find.byKey(const ValueKey('body-later-weighin')), findsNothing);
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('A4-2: δείκτης και εύρος βάρους στο όριο του 25', () {
    test('ο δείκτης κόβεται στο 0,1 (ποτέ «25,0» για 24,97)· τα άκρα του βάρους = οι τιμές που κρίνονται «μέσα»', () {
      expect(bmiText(bmiOf(80.9, 180)!), '24,9'); // 24,969
      expect(bmiText(bmiOf(81.0, 180)!), '25,0');
      expect(bmiText(bmiOf(78.3, 177)!), '24,9'); // 24,993
      expect(bmiText(bmiOf(80.676, 180)!), '24,9'); // ακριβώς 24,9
      expect(bmiText(bmiOf(59.9, 180)!), '18,4'); // 18,488: «κάτω από το εύρος»
      final (lo180, hi180) = healthyWeight(180)!;
      expect(healthyWeightText(lo180, hi180), '60,0–80,9'); // 59,94–81,0
      final (lo177, hi177) = healthyWeight(177)!;
      expect(healthyWeightText(lo177, hi177), '58,0–78,3'); // 57,96–78,32
      final (lo170, hi170) = healthyWeight(170)!;
      expect(healthyWeightText(lo170, hi170), '53,5–72,2'); // 53,465–72,25
      expect(metricSpecs[K.weight]!.range!(const Profile(heightCm: 180), DateTime(2026, 12, 2))!.text,
          'φυσιολογικός δείκτης για το ύψος σου: 60,0–80,9 kg');
    });

    testWidgets('180 cm, 80,9 kg: Σώμα «24,9» και «Μέσα στο εύρος»· widget «24,9», «μέσα στο εύρος»', (t) async {
      final now = DateTime(2026, 12, 2, 9);
      final s = _store(now, _ownUpTo(now));
      await _pump(t, BodyPage(store: s, now: now));
      expect(_row(t, 'Δείκτης μάζας σώματος'), '24,9', reason: 'πριν «25,0»');
      expect(find.text('Μέσα στο εύρος · φυσιολογικός δείκτης για το ύψος σου: 60,0–80,9 kg'), findsOneWidget);
      final m = _widgetBody(s, now);
      expect((m['bmi'] as Map)['v'], '24,9');
      expect((m['bmi'] as Map)['r'], 'μέσα στο εύρος');
    });

    testWidgets('180 cm, 81,0 kg: «Πάνω από το εύρος» με εύρος ως 80,9 (πριν «…–81,0 kg»)', (t) async {
      final now = DateTime(2026, 12, 4, 9);
      final s = _store(now, [..._ownUpTo(DateTime(2026, 12, 3)), _m(DateTime(2026, 12, 4, 7, 15), 81.0, 29.0)]);
      await _pump(t, BodyPage(store: s, now: now));
      expect(_row(t, 'Δείκτης μάζας σώματος'), '25,0');
      expect(find.text('Πάνω από το εύρος · φυσιολογικός δείκτης για το ύψος σου: 60,0–80,9 kg'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  testWidgets('A4-3: σελίδα «Λίπος σώματος»: «27,0%» χωρίς κενό, όπως το Σώμα', (t) async {
    final now = DateTime(2026, 12, 4, 10);
    final h = <String, Map<String, double>>{};
    mergeBody(h, bodyRows(_ownUpTo(now)));
    final s = HealthStore()..history = h;
    await _pump(t, MetricPage(store: s, spec: metricSpecs[K.fatPct]!, now: now));
    final values = [for (final r in t.widgetList<InfoRow>(find.byType(InfoRow))) r.value];
    expect(values, contains('29,0%'), reason: '«Τελευταίες τιμές»');
    expect(values.where((v) => RegExp(r'\d %').hasMatch(v)), isEmpty, reason: 'πριν «27,0 %»');
    expect(_row(t, 'Μέσος όρος'), matches(RegExp(r'^\d+,\d%$')));
    expect(find.textContaining(RegExp(r'συνήθως \d+,\d %')), findsNothing);
    expect(metricSpecs[K.weight]!.unitSuffix, ' kg');
    expect(metricSpecs[K.steps]!.unitSuffix, '');
  });

  // -------------------------------------------------------------------------------------------------------------------
  testWidgets('A4 · B2: γράφημα μέσης με ελάχιστο εύρος 3 cm (όπως βάρος και λίπος)', (t) async {
    final now = DateTime(2026, 12, 4, 9);
    final s = _store(now, _ownUpTo(now))
      ..saveWaist(const WaistEntry('2026-11-20', [98.6, 99.0]))
      ..saveWaist(const WaistEntry('2026-11-27', [98.0, 98.2]));
    await _pump(t, BodyPage(store: s, now: now));
    final chart = t.widget<LineChart>(find.descendant(of: find.byKey(const ValueKey('body-waist')), matching: find.byType(LineChart)));
    expect(chart.minRange, 3);
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('A12-7: ο κανόνας που τρέχει, [weightsAgree], στα όριά του', () {
    test('ως 4 kg ή ως 5% της ΜΕΓΑΛΥΤΕΡΗΣ, με το ίσον', () {
      expect(weightsAgree(82.0, 86.1), isTrue); // 4,1 ≤ 5% × 86,1 = 4,305
      expect(weightsAgree(86.1, 82.0), isTrue);
      expect(weightsAgree(82.0, 86.4), isFalse); // 4,4 > 4,32
      expect(weightsAgree(60.0, 64.0), isTrue, reason: 'ακριβώς 4 kg: συμφωνούν (≤)');
      expect(weightsAgree(60.0, 64.1), isFalse);
      // 5% της μεγαλύτερης (84,15 → 4,2075), όχι της μικρότερης (80 → 4,0): 4,15 kg συμφωνούν.
      expect(weightsAgree(80.0, 84.15), isTrue);
      expect(weightsAgree(84.15, 80.0), isTrue);
    });

    test('λιγότερες από 3 άλλες ζυγίσεις σε ±14 μέρες: δεν κρίνεται (μετρά)', () {
      final days = [(DateTime(2026, 11, 2), 90.0), (DateTime(2026, 11, 4), 89.8), (DateTime(2026, 11, 6), 45.0)];
      expect(weighStatusAt(days, 2), WeighStatus.counted);
    });
  });
}
