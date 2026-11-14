// Round 8 · f5: Σήμερα, widgets αρχικής οθόνης, Σώμα. Φανταστικές τιμές (δημόσιο repo).
// R8-U1-1/2/4/5/6/8, R8-A4-1/2/3, R8-A10-1, R8-A2-2/3, R8-U4-10, R8-U4-3 (body_trend), A4 Β2 / U4 Β4.
// (R8-U1-3, R8-U1-7, R8-A10-2: Kotlin, R8F5Test.kt.) Οι αναμενόμενες τιμές από τον κανόνα (python:
// /home/claude/scratch/f5r8/*.py), όχι από τον νέο κώδικα.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/body_trend.dart'
    show bodyNoPermissionShort, bodyNoPermissionText, bodyNoPermissionTitle, bodyNotPermitted, bodyTrendNote;
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/food/food_model.dart' show Food, LogEntry, Meal, NValue, Nk, Nutrients;
import 'package:ygeia_forma/food/food_store.dart' show FoodStore;
import 'package:ygeia_forma/format.dart' show dayMonth, shortDayDate;
import 'package:ygeia_forma/history.dart' show dateKey;
import 'package:ygeia_forma/home_widgets/widget_bridge.dart' show WidgetConfigBridge, WidgetPublisher, WidgetTarget, widgetChannel;
import 'package:ygeia_forma/home_widgets/widget_snapshot.dart' show buildWidgetSnapshot;
import 'package:ygeia_forma/home_widgets/widget_style.dart' show WKind, WTap, WidgetStyle, wMetricPages;
import 'package:ygeia_forma/pages/body.dart' show BodyPage, bodyEstimatesBmrText;
import 'package:ygeia_forma/pages/metric_page.dart' show metricSpecs;
import 'package:ygeia_forma/pages/nutrition.dart' show FoodTodayCard;
import 'package:ygeia_forma/pages/today.dart' show TodayPage;
import 'package:ygeia_forma/pages/widget_config_page.dart' show WidgetConfigApp;
import 'package:ygeia_forma/profile.dart' show Profile;
import 'package:ygeia_forma/reference.dart' show RefRange, bmiOf, bmiRange, bmiShown, bmiText, healthyWeight;
import 'package:ygeia_forma/sources.dart' show SourcePlan;
import 'package:ygeia_forma/theme.dart' show Aigaio, buildTheme;
import 'package:ygeia_forma/widgets.dart' show InfoRow, StatCard, TrendPill, stageOrder;

import 'sample_data.dart' show sampleDashboardJson, sampleHistory;
import 'sample_food.dart' show basicFoods, foodNamed, sampleFoodStore;

const _inbody = 'com.inbody2014.inbody';

BodyMeasurement _m(DateTime t, double kg, [double? fat]) => BodyMeasurement(time: t, weight: kg, fatPct: fat, app: _inbody);

/// Ανάγνωση της στιγμής [at] με τις ζυγίσεις [rows] (όπως r7_f5_test), ύψος 180 cm, γεννημένος 12/1985 (φανταστικός).
/// [bmr]: βασικός μεταβολισμός σε κάθε ζύγιση. [withBody] false: χωρίς κλειδί «body» (άδεια «Σύσταση σώματος» κλειστή).
HealthStore _store(DateTime at, List<BodyMeasurement> rows, {Profile? profile, int? bmr, bool withBody = true}) {
  final json = {
    ...sampleDashboardJson(at),
    'body': [
      for (final b in rows)
        {
          'time': b.time.millisecondsSinceEpoch,
          'weight': b.weight,
          if (b.fatPct != null) 'fatPct': b.fatPct,
          if (bmr != null) 'bmr': bmr,
          'app': _inbody,
        },
    ],
  };
  if (!withBody) json.remove('body');
  final s = HealthStore()..data = Dashboard.fromJson(json);
  s.history = sampleHistory(at, s.data!);
  applyRecentRead(s.history, s.data!, plan: SourcePlan.samsungOnly);
  s.setProfile(profile ?? const Profile(birthYear: 1985, birthMonth: 12, sex: 'm', heightCm: 180));
  return s;
}

/// Δε/Τε/Πα 07:15 από Δευτέρα 16/11 (ίδιες τιμές με το r7_f5_test).
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

Widget _today(HealthStore s, {DateTime? now, DateTime Function()? clock, FoodStore? food}) => TodayPage(
      store: s,
      food: food ?? sampleFoodStore(now ?? clock!()),
      open: (_, [__]) {},
      openSettings: () {},
      now: now,
      clock: clock,
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

/// Η εφαρμογή στο παρασκήνιο και πίσω, όπως το στέλνει το Android (κανάλι «flutter/lifecycle»).
Future<void> _lifecycle(WidgetTester t, AppLifecycleState s) => t.binding.defaultBinaryMessenger
    .handlePlatformMessage(SystemChannels.lifecycle.name, const StringCodec().encodeMessage(s.toString()), (_) {});

class _NoRender extends WidgetConfigBridge {
  const _NoRender();

  @override
  Future<Uint8List?> render(WidgetStyle style, double w, double h, {required bool dark}) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // -------------------------------------------------------------------------------------------------------------------
  group('R8-U1-1: κάρτα ύπνου (ρολόι): «χθες βράδυ» σε σχέση με ΤΩΡΑ, όχι με την ώρα της ανάγνωσης', () {
    // Τελευταία ανάγνωση Παρ 13/11 22:00· η νύχτα με ξύπνημα Παρ 13/11.
    final read = DateTime(2026, 11, 13, 22);

    testWidgets('Σάβ 14/11 07:30 με τη χθεσινή ανάγνωση: «ξύπνημα χθες» (πριν «χθες βράδυ»)', (t) async {
      await _pump(t, _today(_store(read, const []), now: DateTime(2026, 11, 14, 7, 30)));
      expect(find.text('Ύπνος · ξύπνημα χθες'), findsOneWidget);
      expect(find.text('Ύπνος · χθες βράδυ'), findsNothing);
    });

    testWidgets('Παρ 13/11 23:00: «χθες βράδυ»', (t) async {
      await _pump(t, _today(_store(read, const []), now: DateTime(2026, 11, 13, 23)));
      expect(find.text('Ύπνος · χθες βράδυ'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('R8-U1-2: μπάρα φάσεων στη σκούρα νυχτερινή κάρτα', () {
    test('κάθε φάση ≥ 3:1 με το πάνω ΚΑΙ το κάτω χρώμα της κάρτας, σε όλα τα θέματα· ο βαθύς ο πιο σκούρος', () {
      for (final c in [...Aigaio.dayThemes, ...Aigaio.nightThemes]) {
        for (final k in stageOrder) {
          final s = c.stageOnNight(k);
          expect(Aigaio.contrast(s, c.nightTop), greaterThanOrEqualTo(3.0), reason: '${c.name}/${c.dark}/$k πάνω');
          expect(Aigaio.contrast(s, c.nightBottom), greaterThanOrEqualTo(3.0), reason: '${c.name}/${c.dark}/$k κάτω');
        }
        final deep = c.stageOnNight('DEEP').computeLuminance();
        for (final k in ['LIGHT', 'REM', 'AWAKE']) {
          expect(deep, lessThan(c.stageOnNight(k).computeLuminance()), reason: '${c.name}/${c.dark}: ο βαθύς ο πιο σκούρος');
        }
      }
      // Πριν (Αιγαίο φωτεινό, το προεπιλεγμένο): REM 2,17:1 και βαθύς 1,03:1 με το κάτω χρώμα της κάρτας.
      expect(Aigaio.contrast(Aigaio.light.stage('REM'), Aigaio.light.nightBottom), lessThan(3.0));
      // Τα χρώματα της λευκής κάρτας (R7-U4-9) δεν άλλαξαν.
      expect(Aigaio.light.stage('REM'), const Color(0xFF1681A8));
      expect(Aigaio.light.stage('AWAKE'), const Color(0xFFCB7E66));
    });

    testWidgets('η κάρτα ύπνου της Σήμερα ζωγραφίζει με τα χρώματα της νυχτερινής κάρτας', (t) async {
      final now = DateTime(2026, 11, 13, 23);
      await _pump(t, _today(_store(now, const []), now: now));
      const c = Aigaio.light;
      bool box(Widget w, Color color) => w is ColoredBox && w.color == color;
      expect(find.byWidgetPredicate((w) => box(w, c.stageOnNight('REM'))), findsWidgets);
      expect(find.byWidgetPredicate((w) => box(w, c.stage('REM'))), findsNothing);
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('R8-U1-4: σύντομη πηγή (μόνο η μέρα) για τη στήλη 1×3', () {
    test('Σώμα: ζύγιση Τετ 18/11 → «InBody · Τετ 18/11» και σύντομα «Τετ 18/11»', () {
      final now = DateTime(2026, 11, 18, 9);
      final body = _kinds(_store(now, _ownUpTo(now)), now)[WKind.body] as Map;
      expect(body['src'], 'InBody · Τετ 18/11');
      expect(body['srcShort'], 'Τετ 18/11');
    });

    test('Ύπνος: η μέρα της νύχτας, χωρίς την πηγή', () {
      final now = DateTime(2026, 11, 18, 9);
      final sleep = _kinds(_store(now, const []), now)[WKind.sleep] as Map;
      final src = sleep['src'] as String;
      expect(src, startsWith('ρολόι · '));
      expect(sleep['srcShort'], src.substring('ρολόι · '.length));
      expect(sleep['srcShort'], anyOf(shortDayDate(DateTime(2026, 11, 18)), shortDayDate(DateTime(2026, 11, 17))));
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('R8-U1-5: η «Σήμερα» αλλάζει μέρα στα μεσάνυχτα', () {
    // Σάββατο 14/11: ένα φαγητό στο Σάββατο (καμία καταχώριση την Κυριακή).
    final sat = DateTime(2026, 11, 14, 23, 57);
    FoodStore food() => FoodStore.preloaded(
          foods: basicFoods(),
          entries: [
            LogEntry(
                id: 's1', day: dateKey(sat), meal: Meal.dinner, food: foodNamed('Μπανάνα'), grams: 120, time: DateTime(2026, 11, 14, 21)),
          ],
          now: sat,
        );
    Finder emptyFood() => find.descendant(of: find.byType(FoodTodayCard), matching: find.text('Δεν έχεις γράψει τίποτα ακόμα σήμερα.'));

    testWidgets('οθόνη ανοιχτή στα μεσάνυχτα: Κυριακή, και η κάρτα φαγητού με τα σύνολα της Κυριακής', (t) async {
      var clock = DateTime(2026, 11, 14, 23, 59, 30);
      await _pump(t, _today(_store(sat, const []), clock: () => clock, food: food()));
      expect(find.text('Σάββατο 14 Νοεμβρίου'), findsOneWidget);
      expect(emptyFood(), findsNothing, reason: 'το φαγητό του Σαββάτου');
      clock = DateTime(2026, 11, 15, 0, 0, 31);
      await t.pump(const Duration(seconds: 32));
      await t.pump();
      expect(find.text('Κυριακή 15 Νοεμβρίου'), findsOneWidget);
      expect(find.text('Σάββατο 14 Νοεμβρίου'), findsNothing);
      expect(emptyFood(), findsOneWidget);
    });

    testWidgets('επιστροφή στην εφαρμογή στις 00:02 (χωρίς νέα ανάγνωση): Κυριακή', (t) async {
      var clock = sat;
      await _pump(t, _today(_store(sat, const []), clock: () => clock, food: food()));
      expect(find.text('Σάββατο 14 Νοεμβρίου'), findsOneWidget);
      await _lifecycle(t, AppLifecycleState.paused);
      clock = DateTime(2026, 11, 15, 0, 2);
      await _lifecycle(t, AppLifecycleState.resumed);
      await t.pump();
      expect(find.text('Κυριακή 15 Νοεμβρίου'), findsOneWidget);
      expect(emptyFood(), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('R8-U1-6 / R8-U1-8: ρύθμιση widget', () {
    Future<void> config(WidgetTester t, String kind) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(400, 4000);
      addTearDown(t.view.reset);
      // Κλειδί ανά είδος: νέα οθόνη (αλλιώς η Flutter κρατά την προηγούμενη κατάσταση, με το προηγούμενο είδος).
      await t.pumpWidget(WidgetConfigApp(key: ValueKey(kind), bridge: const _NoRender(), initial: WidgetTarget(id: 0, kind: kind)));
      await t.pumpAndSettle();
    }

    test('οι τιμές με σελίδα = τα κλειδιά του metricSpecs', () {
      expect(wMetricPages, metricSpecs.keys.toSet());
      // Αποθηκευμένο «metric» για τιμή χωρίς σελίδα: η ενότητα (αυτό ανοίγει ήδη το πάτημα).
      expect(WidgetStyle.fromJson({'kind': WKind.food, 'hero': 'kcal', 'tap': WTap.metric}).tap, WTap.section);
      expect(WidgetStyle.fromJson({'kind': WKind.sleep, 'hero': 'hrv', 'tap': WTap.metric}).tap, WTap.metric);
    });

    testWidgets('Φαγητό: χωρίς «Τη σελίδα της κεντρικής τιμής»· Ύπνος: με', (t) async {
      await config(t, WKind.food);
      expect(find.text('Τη σελίδα της κεντρικής τιμής'), findsNothing);
      expect(find.text('Την ενότητα'), findsOneWidget);
      await config(t, WKind.sleep);
      expect(find.text('Τη σελίδα της κεντρικής τιμής'), findsOneWidget);
    });

    testWidgets('κεντρική τιμή χωρίς σελίδα: η επιλογή φεύγει', (t) async {
      await config(t, WKind.sleep);
      await t.tap(find.widgetWithText(ChoiceChip, 'Τη σελίδα της κεντρικής τιμής'));
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(find.widgetWithText(ChoiceChip, 'Χαμηλότεροι παλμοί'));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Τη σελίδα της κεντρικής τιμής'), findsNothing);
      final selected = t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Την ενότητα'));
      expect(selected.selected, isTrue);
    });

    testWidgets('U1-8: η κουκκίδα χρώματος είναι 48 × 48 dp με περίγραμμα που φαίνεται', (t) async {
      await config(t, WKind.sleep);
      final dot = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Χρώμα για Ετοιμότητα / Energy Score');
      expect(dot, findsOneWidget);
      expect(t.getSize(dot), const Size(48, 48));
      final circle = t.widget<Container>(find.descendant(of: dot, matching: find.byType(Container)).first);
      final border = (circle.decoration! as BoxDecoration).border! as Border;
      expect(border.top.color, Aigaio.light.textTertiary);
      for (final c in [...Aigaio.dayThemes, ...Aigaio.nightThemes]) {
        expect(Aigaio.contrast(c.textTertiary, c.card), greaterThanOrEqualTo(3.0), reason: c.name);
      }
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('R8-A4-1: δείκτης και βάρος, μία κρίση από τον αριθμό που φαίνεται', () {
    test('160 cm, 64,0 kg: «25,0 · πάνω από το εύρος» και στο βάρος «πάνω από το εύρος»', () {
      final now = DateTime(2026, 11, 20, 9);
      final rows = [
        _m(DateTime(2026, 11, 16, 7, 15), 64.2),
        _m(DateTime(2026, 11, 18, 7, 15), 64.1),
        _m(DateTime(2026, 11, 20, 7, 15), 64.0),
      ];
      final s = _store(now, rows, profile: const Profile(birthYear: 1985, birthMonth: 12, sex: 'm', heightCm: 160));
      final m = (_kinds(s, now)[WKind.body] as Map)['m'] as Map;
      expect((m['weight'] as Map)['v'], '64,0');
      expect((m['weight'] as Map)['r'], 'πάνω από το εύρος');
      expect((m['bmi'] as Map)['v'], '25,0');
      expect((m['bmi'] as Map)['r'], 'πάνω από το εύρος', reason: 'πριν «μέσα στο εύρος» (24,999999999999996)');
    });

    test('σάρωση 150–200 cm ανά 0,5 × 40,0–120,0 kg ανά 0,1: κρίση δείκτη = κρίση βάρους, αριθμός = κρίση', () {
      var checked = 0;
      for (var h10 = 1500; h10 <= 2000; h10 += 5) {
        final h = h10 / 10;
        final (lo, hi) = healthyWeight(h)!;
        final weightRange = RefRange(low: lo, high: hi, text: '', cite: '');
        for (var w10 = 400; w10 <= 1200; w10++) {
          final w = w10 / 10;
          final shown = bmiShown(bmiOf(w, h)!);
          expect(bmiRange.place(shown), weightRange.place(w), reason: '$h cm, $w kg');
          // Ο αριθμός που γράφεται και η κρίση του: «25,0» ποτέ «μέσα», «24,9» ποτέ «πάνω».
          expect(bmiText(bmiOf(w, h)!) == '25,0' ? bmiRange.place(shown) : 1, 1);
          checked++;
        }
      }
      expect(checked, 101 * 801);
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('R8-A4-2 / R8-U4-10 / B2: Σώμα · κάρτα της ζύγισης', () {
    testWidgets('A4-2: χωρίς «±10%»· η σημείωση λέει ότι οι Στόχοι έχουν άλλο τύπο', (t) async {
      final now = DateTime(2026, 12, 4, 9);
      await _pump(t, BodyPage(store: _store(now, _ownUpTo(now), bmr: 1692), now: now));
      expect(find.textContaining('±10'), findsNothing);
      expect(_row(t, 'Βασικός μεταβολισμός (εκτίμηση)'), '1.692 kcal');
      expect(t.widget<Text>(find.byKey(const ValueKey('body-estimates-note'))).data, bodyEstimatesBmrText);
      expect(bodyEstimatesBmrText, contains('Mifflin-St Jeor'));
    });

    testWidgets('U4-10: πρωινή και βραδινή ζύγιση: «Ζύγιση της μέρας», όχι «Τελευταία ζύγιση»', (t) async {
      final now = DateTime(2026, 12, 4, 21);
      final rows = [..._ownUpTo(now), _m(DateTime(2026, 12, 4, 20, 30), 82.1, 27.6)];
      await _pump(t, BodyPage(store: _store(now, rows), now: now));
      expect(find.text('Ζύγιση της μέρας'), findsOneWidget);
      expect(find.text('Τελευταία ζύγιση'), findsNothing);
      expect(find.byKey(const ValueKey('body-later-weighin')), findsOneWidget);
    });

    testWidgets('U4-10: μία ζύγιση τη μέρα: «Τελευταία ζύγιση»· B2: ίδια μορφή μέρας στο χάπι και στη σημείωση', (t) async {
      final now = DateTime(2026, 12, 4, 9);
      await _pump(t, BodyPage(store: _store(now, _ownUpTo(now)), now: now));
      expect(find.text('Τελευταία ζύγιση'), findsOneWidget);
      final pills = [for (final p in t.widgetList<TrendPill>(find.byType(TrendPill))) if (p.text.contains(' kg από ')) p.text];
      expect(pills, ['−0,2 kg από 2/12']);
      final note = t.widget<Text>(find.byKey(const ValueKey('body-trend-note'))).data!;
      expect(note, contains('σε παρένθεση η αλλαγή από τις 2/12.'), reason: 'πριν «από τις 2 Δεκ.» κάτω από το «από 2/12»');
    });

    test('U4-3: ο αριθμός μένει με τη μονάδα/τον μήνα του (αδιάσπαστο κενό)', () {
      final full = bodyTrendNote(previous: DateTime(2026, 8, 13), days: 8, date: dayMonth);
      expect(full, contains('από τις 13\u00A0Αυγ.'));
      expect(full, contains('2\u00A0μονάδες στο λίπος ή 1,7\u00A0kg και πάνω'));
      expect(full, isNot(contains('13 Αυγ')));
      final few = bodyTrendNote(previous: null, days: 2, date: dayMonth);
      expect(few, contains('μετά από 6\u00A0μέρες ζύγισης (έχεις 2)'));
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('R8-A4-3: κλειστή άδεια «Σύσταση σώματος»', () {
    // Δευτέρα 16/11 09:00 (μέρα ζυγίσματος): η ανάγνωση χωρίς κλειδί «body», με όλα τα άλλα.
    final mon = DateTime(2026, 11, 16, 9);

    test('ο κανόνας: χωρίς «body» και χωρίς σφάλμα· όχι με σφάλμα, όχι με κενή λίστα, όχι χωρίς καμία άδεια', () {
      expect(bodyNotPermitted(_store(mon, const [], withBody: false).data), isTrue);
      expect(bodyNotPermitted(_store(mon, const []).data), isFalse, reason: 'άδεια υπάρχει, απλώς καμία ζύγιση');
      final failed = Dashboard.fromJson({
        ...sampleDashboardJson(mon),
        'body': {'error': 'x'},
      });
      expect(bodyNotPermitted(failed), isFalse);
      final none = Dashboard.fromJson({...sampleDashboardJson(mon), 'granted': 0}..remove('body'));
      expect(bodyNotPermitted(none), isFalse);
      expect(bodyNotPermitted(null), isFalse);
    });

    testWidgets('Σώμα: η κάρτα της άδειας, όχι «Δεν υπάρχει ζύγιση · Ζυγίσου στην InBody»', (t) async {
      await _pump(t, BodyPage(store: _store(mon, const [], withBody: false), now: mon));
      expect(find.text(bodyNoPermissionTitle), findsOneWidget);
      expect(find.text(bodyNoPermissionText), findsOneWidget);
      expect(find.text('Άδειες Samsung Health'), findsOneWidget);
      expect(find.text('Δεν υπάρχει ζύγιση'), findsNothing);
    });

    testWidgets('Σώμα: με άδεια και χωρίς ζύγιση: όπως πριν', (t) async {
      await _pump(t, BodyPage(store: _store(mon, const []), now: mon));
      expect(find.text('Δεν υπάρχει ζύγιση'), findsOneWidget);
      expect(find.text(bodyNoPermissionTitle), findsNothing);
    });

    testWidgets('Σήμερα: η κάρτα «Βάρος» και η «Σήμερα ζύγιση» το λένε', (t) async {
      await _pump(t, _today(_store(mon, const [], withBody: false), now: mon));
      expect(_weightCard(t).empty, bodyNoPermissionShort);
      expect(find.byKey(const ValueKey('today-weigh')), findsOneWidget);
      expect(find.byKey(const ValueKey('today-weigh-no-permission')), findsOneWidget);
    });

    testWidgets('Σήμερα με άδεια: «Ζυγίσου στην InBody», χωρίς τη σημείωση της άδειας', (t) async {
      await _pump(t, _today(_store(mon, const []), now: mon));
      expect(_weightCard(t).empty, 'Ζυγίσου στην InBody. Η μέτρηση φτάνει εδώ σε λίγα λεπτά.');
      expect(find.byKey(const ValueKey('today-weigh-no-permission')), findsNothing);
    });

    test('widget: «χωρίς άδεια ζυγίσεων» / «χωρίς άδεια»', () {
      final body = _kinds(_store(mon, const [], withBody: false), mon)[WKind.body] as Map;
      expect(body['src'], 'χωρίς άδεια ζυγίσεων');
      expect(body['srcShort'], 'χωρίς άδεια');
      expect((body['m'] as Map).isEmpty, isTrue);
      final withPermission = _kinds(_store(mon, const []), mon)[WKind.body] as Map;
      expect(withPermission['src'], 'καμία ζύγιση ακόμα');
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('R8-A2-2 / R8-A2-3: widget «Φαγητό»', () {
    final now = DateTime(2026, 11, 16, 13);
    // Δικό μου προϊόν χωρίς ίνες, αλάτι και σάκχαρα (συχνό στο Open Food Facts). Φανταστικό.
    final mine = Food(
      id: 'Mtest1',
      name: 'Μπάρα δημητριακών',
      cat: 'Τα προϊόντα μου',
      source: 'Open Food Facts',
      n: Nutrients({Nk.kcal: const NValue(400), Nk.protein: const NValue(8), Nk.carbs: const NValue(60), Nk.fat: const NValue(12)}),
    );
    LogEntry entry(String id, Food f, double g) =>
        LogEntry(id: id, day: dateKey(now), meal: Meal.lunch, food: f, grams: g, time: DateTime(2026, 11, 16, 13));

    Map food(List<LogEntry> entries) =>
        (_kinds(HealthStore(), now, food: FoodStore.preloaded(foods: basicFoods(), entries: entries, now: now))[WKind.food]
            as Map)['m'] as Map;

    test('A2-2: τρόφιμο χωρίς τιμή → «≥» σε ίνες, αλάτι, σάκχαρα (όπως η Διατροφή)· χωρίς αυτό, ακριβές', () {
      // Φακές (βρασμένες) 200 g: ίνες 8,45 × 2 = 16,9 → «17»· σάκχαρα 0,2 × 2 = 0,4· αλάτι 0,014 × 2 = 0,028 → «0,0».
      final lentils = entry('l1', foodNamed('Φακές (βρασμένες)'), 200);
      final exact = food([lentils]);
      expect((exact['fiber'] as Map)['v'], '17');
      expect((exact['sugars'] as Map)['v'], '0,4');
      expect((exact['salt'] as Map)['v'], '0,0');
      final atLeast = food([lentils, entry('m1', mine, 40)]);
      expect((atLeast['fiber'] as Map)['v'], '≥ 17');
      expect((atLeast['sugars'] as Map)['v'], '≥ 0,4');
      expect((atLeast['salt'] as Map)['v'], '≥ 0,0');
      expect((atLeast['protein'] as Map)['v'], isNot(startsWith('≥')));
    });

    test('A2-3: ημερολόγιο που διαβάζεται ακόμα ή δεν διαβάστηκε: «—», ποτέ «0 kcal · τίποτα ακόμα σήμερα»', () {
      final store = FoodStore();
      var k = _kinds(HealthStore(), now, food: store)[WKind.food] as Map;
      expect(k['src'], 'διαβάζεται…');
      for (final e in (k['m'] as Map).values) {
        expect((e as Map)['v'], '—');
        expect(e['cap'], 'διαβάζεται…');
      }
      store.error = 'Δεν διαβάστηκε το ημερολόγιο φαγητού.';
      k = _kinds(HealthStore(), now, food: store)[WKind.food] as Map;
      expect(k['src'], 'δεν διαβάστηκε');
      expect(k['srcShort'], 'πρόβλημα');
      final m = k['m'] as Map;
      expect(m.keys.toSet(), {'kcal', 'protein', 'carbs', 'fat', 'fiber', 'salt', 'sugars'});
      expect((m['kcal'] as Map)['v'], '—');
      expect((m['kcal'] as Map)['cap'], 'άνοιξε την εφαρμογή');
      expect((m['kcal'] as Map)['capShort'], 'άνοιξέ με');
      expect((m['kcal'] as Map)['l'], 'Θερμίδες');
      expect((m['fiber'] as Map)['l'], 'Ίνες');
    });

    testWidgets('A2-3: η κάρτα «Διατροφή · σήμερα» δεν γράφει τίποτα σαν να έφαγες 0', (t) async {
      final store = FoodStore();
      await _pump(t, FoodTodayCard(food: store, onOpen: () {}, now: now));
      expect(t.widget<Text>(find.byKey(const ValueKey('today-food-not-read'))).data, 'Διαβάζεται το ημερολόγιο φαγητού…');
      expect(find.text('Δεν έχεις γράψει τίποτα ακόμα σήμερα.'), findsNothing);
      store.error = 'x';
      await _pump(t, FoodTodayCard(key: const ValueKey('again'), food: store, onOpen: () {}, now: now));
      expect(t.widget<Text>(find.byKey(const ValueKey('today-food-not-read'))).data, contains('Δεν διαβάστηκε'));
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  testWidgets('R8-A10-1: επιστροφή στην εφαρμογή → το νέο widget γεμίζει (μία ζωγραφική)· ξανά χωρίς αλλαγή → καμία',
      (t) async {
    final calls = <String>[];
    var count = 0;
    final messenger = t.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(widgetChannel, (call) async {
      calls.add(call.method);
      return call.method == 'count' ? count : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(widgetChannel, null));
    addTearDown(() => widgetChannel.setMethodCallHandler(null));
    final read = DateTime(2026, 11, 16, 10);
    final store = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(read));
    final publisher = WidgetPublisher(store, sampleFoodStore(read), clock: () => DateTime(2026, 11, 16, 10, 1));
    int updates() => calls.where((c) => c == 'update').length;

    // 10:00: κανένα widget ακόμα («count» 0): τίποτα δεν γράφεται.
    publisher.start();
    await t.pump(const Duration(seconds: 2));
    expect(updates(), 0);
    expect(WidgetsBinding.instance.removeObserver(publisher), isTrue, reason: 'ακούει την επιστροφή στην εφαρμογή');
    WidgetsBinding.instance.addObserver(publisher);

    // 10:01 μπαίνει widget· 10:03 η εφαρμογή ξανά μπροστά, χωρίς καμία αλλαγή δεδομένων.
    count = 1;
    publisher.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await t.pump(const Duration(seconds: 2));
    expect(updates(), 1, reason: 'πριν: 0 (έμενε «άνοιξε την εφαρμογή»)');
    publisher.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await t.pump(const Duration(seconds: 2));
    expect(updates(), 1, reason: 'ίδια δεδομένα: καμία νέα ζωγραφική (R7-A10-1)');

    publisher.stop();
    expect(WidgetsBinding.instance.removeObserver(publisher), isFalse);
  });
}
