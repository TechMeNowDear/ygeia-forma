// Round 9 · f5: Σώμα, Σήμερα, widgets, πλοήγηση. Φανταστικές τιμές (δημόσιο repo).
// R9-A4-1 (απορρίφθηκε· έλεγχος ότι μένει σωστό), R9-A4-2, R9-A4-3, R9-A4-4 (ο δείκτης από τους δεκαδικούς που στέλνει
// πια η Kotlin), R9-U4-7, R9-U1-1, R9-U1-2, R9-U1-3, R9-U1-4, R9-U1-6, R9-U1-7.
// (R9-A12-3, R9-U1-5, R9-A4-4 στην Kotlin, R9-A10-1/2: R9F5Test.kt.) Οι αναμενόμενες τιμές από τον κανόνα (python:
// /home/claude/scratch/f5r9/*.py), όχι από τον νέο κώδικα.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/body_trend.dart' show guardBody;
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/food/food_store.dart' show FoodStore;
import 'package:ygeia_forma/format.dart' show dayOf, sameDay;
import 'package:ygeia_forma/history.dart' show K, dateKey, mergeOura;
import 'package:ygeia_forma/home_widgets/widget_bridge.dart' show WidgetConfigBridge, WidgetTarget;
import 'package:ygeia_forma/home_widgets/widget_snapshot.dart' show buildWidgetSnapshot;
import 'package:ygeia_forma/home_widgets/widget_style.dart' show WKind, WidgetStyle, wMetrics;
import 'package:ygeia_forma/main.dart' show Shell;
import 'package:ygeia_forma/nav.dart' show Cat, useSideBar;
import 'package:ygeia_forma/oura/oura_api.dart' show MemoryVault, OuraLink;
import 'package:ygeia_forma/oura/oura_model.dart' show ouraRows, parseOura;
import 'package:ygeia_forma/pages/body.dart' show BodyPage, otherWeighIns, waistFromLabel, weighTableOtherText;
import 'package:ygeia_forma/pages/nutrition.dart' show FoodTodayCard;
import 'package:ygeia_forma/pages/oura_today.dart' show OuraSleepTodayCard;
import 'package:ygeia_forma/pages/today.dart' show TodayPage, sleepNightLabel;
import 'package:ygeia_forma/pages/week_card.dart' show WeekCard;
import 'package:ygeia_forma/pages/widget_config_page.dart' show WidgetConfigApp;
import 'package:ygeia_forma/profile.dart' show Profile;
import 'package:ygeia_forma/reference.dart' show bmiOf, bmiText;
import 'package:ygeia_forma/sources.dart' show Source, SourcePlan;
import 'package:ygeia_forma/theme.dart' show Aigaio, buildTheme;
import 'package:ygeia_forma/waist.dart' show WaistEntry;
import 'package:ygeia_forma/widgets.dart' show InfoRow, TrendPill;

import 'sample_data.dart' show sampleDashboardJson, sampleHistory, sampleOuraSleep;
import 'sample_food.dart' show sampleFoodStore;

const _inbody = 'com.inbody2014.inbody';

/// Το φανταστικό προφίλ των δοκιμών (R9-FIX): άνδρας, 180 cm, γεννημένος 12/1985.
const _me = Profile(birthYear: 1985, birthMonth: 12, sex: 'm', heightCm: 180);

BodyMeasurement _m(DateTime t, double kg, [double? fat]) => BodyMeasurement(time: t, weight: kg, fatPct: fat, app: _inbody);

/// Ανάγνωση της στιγμής [at] με τις ζυγίσεις [rows] (όπως r8_f5_test). [bmi]: ο δείκτης της ζυγαριάς σε κάθε ζύγιση.
HealthStore _store(DateTime at, List<BodyMeasurement> rows, {Profile profile = _me, double? bmi}) {
  final json = {
    ...sampleDashboardJson(at),
    'body': [
      for (final b in rows)
        {
          'time': b.time.millisecondsSinceEpoch,
          'weight': b.weight,
          if (b.fatPct != null) 'fatPct': b.fatPct,
          if (bmi != null) 'bmi': bmi,
          'app': _inbody,
        },
    ],
  };
  final s = HealthStore()..data = Dashboard.fromJson(json);
  s.history = sampleHistory(at, s.data!);
  applyRecentRead(s.history, s.data!, plan: SourcePlan.samsungOnly);
  s.setProfile(profile);
  return s;
}

/// Δε/Τε/Πα 07:15 από Δευτέρα 16/11 (ίδιες τιμές με το r7_f5_test / r8_f5_test).
final _own = <(DateTime, double, double)>[
  (DateTime(2026, 11, 16, 7, 15), 82.0, 27.0),
  (DateTime(2026, 11, 18, 7, 15), 81.9, 27.0),
  (DateTime(2026, 11, 20, 7, 15), 81.7, 27.0),
  (DateTime(2026, 11, 23, 7, 15), 81.5, 27.0),
  (DateTime(2026, 11, 25, 7, 15), 81.4, 27.0),
  (DateTime(2026, 11, 27, 7, 15), 81.2, 27.0),
  (DateTime(2026, 11, 30, 7, 15), 81.0, 29.0),
  (DateTime(2026, 12, 2, 7, 15), 80.9, 29.0),
];

List<BodyMeasurement> _ownRows() => [for (final (t, kg, fat) in _own) _m(t, kg, fat)];

/// Oura από 6/11 με νύχτες ως το πρωί του [at] (εκτός από [missing]), όπως το r1_f5_test.
final _ouraStart = DateTime(2026, 11, 6);

HealthStore _ouraStore(DateTime at, {Set<DateTime> missing = const {}}) {
  final today = DateTime(at.year, at.month, at.day);
  final s = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(at));
  s.history = sampleHistory(at, s.data!);
  s.debugSetPlan(SourcePlan.samsungOnly.withEra(Source.oura, _ouraStart));
  bool skip(DateTime d) => missing.any((m) => sameDay(m, d));
  final batch = parseOura(
    sleep: sampleOuraSleep(_ouraStart, at, missing: missing),
    dailySleep: [
      for (var d = _ouraStart; !d.isAfter(today); d = DateTime(d.year, d.month, d.day + 1))
        if (!skip(d)) {'id': 'ds${dateKey(d)}', 'day': dateKey(d), 'score': 70 + d.day % 15},
    ],
    readiness: [
      for (var d = _ouraStart; !d.isAfter(today); d = DateTime(d.year, d.month, d.day + 1))
        if (!skip(d)) {'id': 'dr${dateKey(d)}', 'day': dateKey(d), 'score': 64 + d.day % 12, 'temperature_deviation': 0.1},
    ],
  );
  s.ouraNights = batch.nights;
  mergeOura(s.history, ouraRows(batch.nights), from: _ouraStart, to: today, plan: s.plan);
  s.ouraHasTokens = true;
  s.ouraLink = OuraLink(vault: MemoryVault(), clientId: 'TEST');
  s.ouraClock = () => at;
  s.ouraSyncedMs = at.subtract(const Duration(minutes: 12)).millisecondsSinceEpoch;
  return s;
}

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 4000)}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: w)));
  await t.pumpAndSettle();
}

Widget _today(HealthStore s, DateTime now, {FoodStore? food}) => TodayPage(
      store: s,
      food: food ?? sampleFoodStore(now),
      open: (_, [__]) {},
      openSettings: () {},
      now: now,
    );

String? _row(WidgetTester t, String label) {
  for (final r in t.widgetList<InfoRow>(find.byType(InfoRow))) {
    if (r.label == label) return r.value;
  }
  return null;
}

List<String> _pills(WidgetTester t) => [for (final p in t.widgetList<TrendPill>(find.byType(TrendPill))) p.text];

Map _sleepWidget(HealthStore s, DateTime now) =>
    ((buildWidgetSnapshot(s, sampleFoodStore(now), now)['kinds'] as Map)[WKind.sleep] as Map)['m'] as Map;

class _NoRender extends WidgetConfigBridge {
  const _NoRender();

  @override
  Future<Uint8List?> render(WidgetStyle style, double w, double h, {required bool dark}) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // -------------------------------------------------------------------------------------------------------------------
  group('R9-A4-1 (απορρίφθηκε): Σώμα, θερμοκρασία καρπού μόνο όσο ο ύπνος είναι του ρολογιού', () {
    final now = DateTime(2026, 11, 20, 9);

    testWidgets('σχέδιο Oura: καμία κάρτα (οι νύχτες του ρολογιού δεν φτάνουν στις οθόνες, Dashboard.restrict)', (t) async {
      final s = _store(now, _ownRows().sublist(0, 3));
      s.debugSetPlan(SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 1)));
      expect(s.data!.nights, isEmpty, reason: 'ο φύλακας που κάνει την κάρτα να μη φαίνεται');
      await _pump(t, BodyPage(store: s, now: now));
      expect(find.byKey(const ValueKey('body-skin')), findsNothing);
    });

    testWidgets('μόνο ρολόι: η κάρτα φαίνεται (έλεγχος ότι η δοκιμή βλέπει την κάρτα)', (t) async {
      await _pump(t, BodyPage(store: _store(now, _ownRows().sublist(0, 3)), now: now));
      expect(find.byKey(const ValueKey('body-skin')), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('R9-A4-2: μέση, «από …» με έτος όταν η πρώτη μέτρηση είναι άλλης χρονιάς', () {
    test('ο κανόνας', () {
      expect(waistFromLabel(DateTime(2026, 11, 16), DateTime(2027, 11, 20)), '16 Νοε 2026');
      expect(waistFromLabel(DateTime(2026, 11, 16), DateTime(2027, 1, 8)), '16 Νοε 2026');
      expect(waistFromLabel(DateTime(2026, 10, 23), DateTime(2026, 11, 6)), '23 Οκτ');
    });

    testWidgets('16/11/2026 100,0 και 20/11/2027 96,0: «−4,0 cm από 16 Νοε 2026»', (t) async {
      final now = DateTime(2027, 11, 20, 10);
      final s = _store(now, const [])
        ..saveWaist(const WaistEntry('2026-11-16', [100.0, 100.0]))
        ..saveWaist(const WaistEntry('2027-11-20', [96.0, 96.0]));
      await _pump(t, BodyPage(store: s, now: now));
      expect(find.text('20 Νοε 2027 · −4,0 cm από 16 Νοε 2026'), findsOneWidget);
    });

    testWidgets('ίδια χρονιά: χωρίς έτος, όπως πριν', (t) async {
      final now = DateTime(2026, 11, 6, 10);
      final s = _store(now, const [])
        ..saveWaist(const WaistEntry('2026-10-23', [100.0, 100.0]))
        ..saveWaist(const WaistEntry('2026-11-06', [99.0, 99.0]));
      await _pump(t, BodyPage(store: s, now: now));
      expect(find.text('6 Νοε 2026 · −1,0 cm από 23 Οκτ'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('R9-A4-3: ίδιο βάρος με την προηγούμενη ζύγιση: «(0)» και «0 kg από …», όπως η Σήμερα', () {
    final now = DateTime(2026, 11, 20, 9);
    List<BodyMeasurement> rows() => [
          _m(DateTime(2026, 11, 16, 7, 15), 82.0, 27.0),
          _m(DateTime(2026, 11, 18, 7, 15), 82.2, 27.0),
          _m(DateTime(2026, 11, 20, 7, 15), 82.2, 27.0),
        ];

    testWidgets('Σώμα: «82,2 kg  (0)» και χάπι «0 kg από 18/11» (πριν: τίποτα, ενώ η σημείωση έλεγε «σε παρένθεση»)',
        (t) async {
      await _pump(t, BodyPage(store: _store(now, rows()), now: now));
      expect(_row(t, 'Βάρος'), '82,2 kg  (0)');
      expect(_pills(t), contains('0 kg από 18/11'));
      expect(find.textContaining('σε παρένθεση η αλλαγή από τις 18/11'), findsOneWidget);
    });

    testWidgets('Σήμερα: το ίδιο χάπι', (t) async {
      await _pump(t, _today(_store(now, rows()), now));
      expect(_pills(t), contains('0 kg από 18/11'));
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('R9-A4-4: ο δείκτης από τους δεκαδικούς της ζυγαριάς (η Kotlin στέλνει πια 89.1, όχι 89.0999984741211)', () {
    final now = DateTime(2026, 11, 16, 9);

    test('ο κανόνας του κομμένου δείκτη με ακριβείς δεκαδικούς', () {
      expect(bmiText(26.9), '26,9');
      expect(bmiText(bmiOf(89.1, 180)!), '27,5');
      expect(bmiText(bmiOf(88.2, 175)!), '28,8');
    });

    testWidgets('Σώμα, 180 cm και 89,1 kg: «27,5»', (t) async {
      await _pump(t, BodyPage(store: _store(now, [_m(DateTime(2026, 11, 16, 7, 15), 89.1)]), now: now));
      expect(_row(t, 'Δείκτης μάζας σώματος'), '27,5');
    });

    testWidgets('Σώμα χωρίς ύψος: ο δείκτης της InBody 26,9 → «26,9»', (t) async {
      final s = _store(now, [_m(DateTime(2026, 11, 16, 7, 15), 82.2)],
          profile: const Profile(birthYear: 1985, birthMonth: 12, sex: 'm'), bmi: 26.9);
      await _pump(t, BodyPage(store: s, now: now));
      expect(_row(t, 'Δείκτης μάζας σώματος'), '26,9');
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('R9-U4-7: πίνακας «Ζυγίσεις»: η δεύτερη ζύγιση της μέρας σε γκρι, με ώρα', () {
    // Πα 4/12 07:15 80,7 (η ζύγιση της μέρας) και 20:30 82,1 (το σενάριο του r7_f5_test).
    final now = DateTime(2026, 12, 4, 21);
    final morning = _m(DateTime(2026, 12, 4, 7, 15), 80.7, 29.0);
    final evening = _m(DateTime(2026, 12, 4, 20, 30), 82.1, 27.6);

    testWidgets('«4/12 20:30» σε γκρι πάνω από το «4/12» της μέρας, με σημείωση', (t) async {
      await _pump(t, BodyPage(store: _store(now, [..._ownRows(), morning, evening]), now: now));
      final table = find.byKey(const ValueKey('body-weighings'));
      final later = find.descendant(of: table, matching: find.text('4/12 20:30'));
      expect(later, findsOneWidget);
      expect(t.widget<Text>(later).style!.color, Aigaio.light.textTertiary);
      final day = find.descendant(of: table, matching: find.text('4/12'));
      expect(day, findsOneWidget);
      expect(t.widget<Text>(day).style!.color, Aigaio.light.text);
      expect(t.widget<Text>(find.descendant(of: table, matching: find.text('82,1'))).style!.color, Aigaio.light.textTertiary);
      expect(find.byKey(const ValueKey('body-weighings-other')), findsOneWidget);
      expect(find.text(weighTableOtherText), findsOneWidget);
    });

    testWidgets('μία ζύγιση τη μέρα: τίποτα γκρι, καμία σημείωση', (t) async {
      await _pump(t, BodyPage(store: _store(now, [..._ownRows(), morning]), now: now));
      expect(find.byKey(const ValueKey('body-weighings-other')), findsNothing);
      expect(find.text('4/12 20:30'), findsNothing);
    });

    test('οι ξένες (π.χ. 38,0 kg το ίδιο πρωί) μένουν ξένες, όχι «άλλη ζύγιση»', () {
      final child = _m(DateTime(2026, 12, 4, 7, 20), 38.0);
      final rows = [..._ownRows(), morning, child, evening];
      final g = guardBody(rows);
      expect(g.foreign.contains(child), isTrue);
      final other = otherWeighIns(rows, shown: g.shown, foreign: g.foreign, pending: g.pending);
      expect(other.length, 1);
      expect(identical(other.single, evening), isTrue);
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('R9-U1-1 / R9-U1-7: η νύχτα στον τίτλο της κάρτας ύπνου', () {
    test('ο κανόνας (ίδιος για ρολόι και Oura)', () {
      expect(sleepNightLabel(DateTime(2026, 11, 14), DateTime(2026, 11, 14, 7)), 'χθες βράδυ');
      expect(sleepNightLabel(DateTime(2026, 11, 13), DateTime(2026, 11, 14, 0, 30)), 'ξύπνημα χθες');
      expect(sleepNightLabel(DateTime(2026, 11, 11), DateTime(2026, 11, 14, 9)), 'ξύπνημα Τετ 11/11');
      expect(sleepNightLabel(DateTime(2026, 11, 3), DateTime(2026, 11, 14, 9)), 'ξύπνημα Τρί 3/11');
      // Αλλαγή ώρας (25/10/2026, μέρα 25 ωρών): ακόμα «χθες».
      expect(sleepNightLabel(DateTime(2026, 10, 25), DateTime(2026, 10, 26, 0, 30)), 'ξύπνημα χθες');
    });

    testWidgets('ρολόι, νύχτα Τετ 11/11, τώρα Σάβ 14/11: «Ύπνος · ξύπνημα Τετ 11/11» (πριν «ξύπνημα τετάρτη»)', (t) async {
      await _pump(t, _today(_store(DateTime(2026, 11, 11, 22), const []), DateTime(2026, 11, 14, 9)));
      expect(find.text('Ύπνος · ξύπνημα Τετ 11/11'), findsOneWidget);
      expect(find.textContaining('ξύπνημα τετάρτη'), findsNothing);
    });

    testWidgets('ρολόι, νύχτα Τρί 3/11: «Ύπνος · ξύπνημα Τρί 3/11» (πριν «ξύπνημα 3 νοε»)', (t) async {
      await _pump(t, _today(_store(DateTime(2026, 11, 3, 22), const []), DateTime(2026, 11, 14, 9)));
      expect(find.text('Ύπνος · ξύπνημα Τρί 3/11'), findsOneWidget);
      expect(find.textContaining('ξύπνημα 3 νοε'), findsNothing);
    });

    testWidgets('Oura, Κυρ 15/11 00:30 (η νύχτα της 15/11 δεν έχει έρθει): «ξύπνημα χθες», όχι «χθες βράδυ»', (t) async {
      final at = DateTime(2026, 11, 15, 0, 30);
      final s = _ouraStore(at, missing: {DateTime(2026, 11, 15)});
      expect(s.ouraNightDay(at), DateTime(2026, 11, 14));
      await _pump(t, SingleChildScrollView(child: OuraSleepTodayCard(store: s, now: at, onTap: () {})));
      expect(find.text('Ύπνος · ξύπνημα χθες'), findsOneWidget);
      expect(find.text('Ύπνος · χθες βράδυ'), findsNothing);
    });

    testWidgets('Oura, Σάβ 14/11 09:00: «χθες βράδυ», όπως πριν', (t) async {
      final at = DateTime(2026, 11, 14, 9);
      await _pump(t, SingleChildScrollView(child: OuraSleepTodayCard(store: _ouraStore(at), now: at, onTap: () {})));
      expect(find.text('Ύπνος · χθες βράδυ'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('R9-U1-2: «Η εβδομάδα σου» στο ανοιχτό Fold', () {
    final mon = DateTime(2026, 11, 16, 9);

    List<Rect> previous(WidgetTester t) => [
          for (final e in find.descendant(of: find.byType(WeekCard), matching: find.textContaining('4 προηγούμενες: ')).evaluate())
            t.getRect(find.byWidget(e.widget)),
        ];

    testWidgets('860 dp: κάτω από τις δύο στήλες, σε όλο το πλάτος, οι γραμμές σε δύο στήλες', (t) async {
      await _pump(t, _today(_store(mon, _ownRows().sublist(0, 1)), mon), size: const Size(860, 4000));
      final week = t.getRect(find.byType(WeekCard));
      final food = t.getRect(find.byType(FoodTodayCard));
      expect(week.width, greaterThan(600), reason: 'όλο το πλάτος (πριν ~390 dp, στη δεξιά στήλη)');
      expect(week.top, greaterThan(food.bottom));
      final rows = previous(t);
      expect(rows.length, greaterThanOrEqualTo(2));
      expect(rows.any((r) => r.left > week.center.dx), isTrue, reason: 'δεύτερη στήλη γραμμών');
      expect(rows.any((r) => r.left < week.center.dx), isTrue, reason: 'πρώτη στήλη γραμμών');
      expect(t.takeException(), isNull);
    });

    testWidgets('κινητό (400 dp): όπως πριν, μία στήλη γραμμών κάτω από τη Διατροφή', (t) async {
      await _pump(t, _today(_store(mon, _ownRows().sublist(0, 1)), mon));
      final week = t.getRect(find.byType(WeekCard));
      expect(week.top, greaterThan(t.getRect(find.byType(FoodTodayCard)).bottom));
      final lefts = {for (final r in previous(t)) r.left.round()};
      expect(lefts.length, 1, reason: 'όλες οι γραμμές στην ίδια στήλη');
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('R9-U1-3: πλαϊνή μπάρα μόνο με αρκετό ύψος', () {
    test('ο κανόνας', () {
      expect(useSideBar(const Size(860, 1500)), isTrue, reason: 'ανοιχτό Fold');
      expect(useSideBar(const Size(1280, 800)), isTrue);
      expect(useSideBar(const Size(880, 370)), isFalse, reason: 'κλειστό Fold οριζόντια');
      expect(useSideBar(const Size(400, 900)), isFalse, reason: 'κινητό όρθιο');
    });

    testWidgets('κλειστό Fold οριζόντια (880 × 370 μετά τη γραμμή κατάστασης): κάτω μπάρα, χωρίς υπερχείλιση', (t) async {
      final now = DateTime(2026, 11, 20, 9);
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(880, 370);
      addTearDown(t.view.reset);
      addTearDown(() => FoodStore.shared = null);
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Shell(store: _store(now, _ownRows().sublist(0, 3)), food: sampleFoodStore(now), initialIndex: Cat.today, now: now),
      ));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: 'πριν: η πλαϊνή μπάρα (≈ 384 dp) ξεχείλιζε');
      final ys = {
        for (final l in ['Σήμερα', 'Υγεία', 'Διατροφή', 'Άσκηση']) t.getCenter(find.byKey(ValueKey('nav-$l'))).dy.round(),
      };
      expect(ys.length, 1, reason: 'οι τέσσερις προορισμοί σε μία σειρά (κάτω μπάρα)');
      // Οι Ρυθμίσεις μένουν στη Σήμερα (στη φαρδιά διάταξη είναι μόνο στην πλαϊνή μπάρα).
      expect(find.byTooltip('Ρυθμίσεις'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('R9-U1-4: widget «Ύπνος»: «Energy Score» με το ρολόι, «Ετοιμότητα» με το Oura', () {
    test('ρολόι: «Energy Score», σύντομο «Energy»', () {
      final now = DateTime(2026, 11, 18, 9);
      final s = _store(now, const []);
      for (final d in [dayOf(now), DateTime(now.year, now.month, now.day - 1)]) {
        s.history[dateKey(d)] = {...?s.history[dateKey(d)], K.energy: 71.0};
      }
      final e = _sleepWidget(s, now)['energy'] as Map;
      expect(e['l'], 'Energy Score');
      expect(e['ls'], 'Energy');
      expect(e['v'], '71');
    });

    test('Oura: «Ετοιμότητα», χωρίς σύντομο', () {
      final at = DateTime(2026, 11, 14, 9);
      final e = _sleepWidget(_ouraStore(at), at)['energy'] as Map;
      expect(e['l'], 'Ετοιμότητα');
      expect(e.containsKey('ls'), isFalse);
    });

    test('η ρύθμιση λέει και τα δύο', () {
      expect(wMetrics[WKind.sleep]!.firstWhere((m) => m.key == 'energy').name, 'Ετοιμότητα / Energy Score');
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  testWidgets('R9-U1-6: ρύθμιση widget: διακόπτες και κουτάκια με όνομα για το TalkBack', (t) async {
    final handle = t.ensureSemantics();
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(400, 4000);
    addTearDown(t.view.reset);
    await t.pumpWidget(WidgetConfigApp(bridge: const _NoRender(), initial: WidgetTarget(id: 0, kind: WKind.sleep)));
    await t.pumpAndSettle();
    final switches = [for (var i = 0; i < find.byType(Switch).evaluate().length; i++) t.getSemantics(find.byType(Switch).at(i)).label];
    for (final title in ['Τιμές στα κουτάκια', 'Γράφημα 7 ημερών', '«Συνήθως» και εύρος']) {
      expect(switches.any((l) => l.contains(title)), isTrue, reason: '$title: $switches');
    }
    final boxes = [for (var i = 0; i < find.byType(Checkbox).evaluate().length; i++) t.getSemantics(find.byType(Checkbox).at(i)).label];
    expect(boxes, isNotEmpty);
    expect(boxes.any((l) => l.contains('Ετοιμότητα / Energy Score')), isTrue, reason: '$boxes');
    expect(boxes.every((l) => l.trim().isNotEmpty), isTrue, reason: 'κανένα κουτάκι χωρίς όνομα');
    handle.dispose();
  });
}
