// Premium επανασχεδιασμός (σχέδια 9/11): οδηγός σχεδίασης (χρώμα με σημασία, μορφές), μετακινήσεις οθονών.
// Όλα τα νούμερα είναι δοκιμαστικά.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/main.dart';
import 'package:ygeia_forma/nav.dart';
import 'package:ygeia_forma/pages/food_add.dart';
import 'package:ygeia_forma/pages/body.dart';
import 'package:ygeia_forma/pages/category.dart';
import 'package:ygeia_forma/pages/devices_page.dart';
import 'package:ygeia_forma/pages/info_sheet.dart';
import 'package:ygeia_forma/history.dart' show K, dateKey;
import 'package:ygeia_forma/trends.dart' show TrendPeriod, periodLabel;
import 'package:ygeia_forma/widgets.dart';
import 'package:ygeia_forma/pages/kitchen.dart';
import 'package:ygeia_forma/pages/oura_today.dart';
import 'package:ygeia_forma/oura/oura_model.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/exercise/ex_names.dart';
import 'package:ygeia_forma/pages/me_page.dart';
import 'package:ygeia_forma/pages/my_foods.dart';
import 'package:ygeia_forma/pages/training/today_training_card.dart';
import 'package:ygeia_forma/exercise/ex_data.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/training_store.dart';
import 'package:ygeia_forma/training/wear_link.dart';
import 'package:ygeia_forma/theme.dart';

import 'sample_data.dart';
import 'training_sample.dart';
import 'sample_food.dart';

final _now = DateTime(2026, 11, 9, 16, 5);

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

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

/// Λέξεις που σπάνε σε δύο γραμμές («Πρωτεΐν|η») μέσα στο [scope]: ελέγχει πού ζωγραφίστηκε κάθε λέξη, όχι μόνο αν
/// κάτι ξεχείλισε (έλεγχος premium, M3/S10).
List<String> brokenWords(WidgetTester t, Finder scope) {
  final out = <String>[];
  for (final e in find.descendant(of: scope, matching: find.byType(RichText)).evaluate()) {
    final p = e.renderObject! as RenderParagraph;
    final text = p.text.toPlainText();
    for (final m in RegExp(r'[^\s·,.:()/]+').allMatches(text)) {
      if (m.end - m.start < 2) continue;
      final boxes = p.getBoxesForSelection(TextSelection(baseOffset: m.start, extentOffset: m.end));
      if ({for (final b in boxes) b.top.round()}.length > 1) out.add(m.group(0)!);
    }
  }
  return out;
}

double contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  // Τα πλάτη των καρτελών μετριούνται με το Inter της εφαρμογής (όχι με τη γραμματοσειρά δοκιμών).
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
  });

  group('Ρυθμός και χρονόμετρο (σχέδια 9/11)', () {
    test('«11:15 /km» παντού', () {
      expect(paceText(675), '11:15 /km');
      expect(paceText(600), '10:00 /km');
      expect(paceText(61), '1:01 /km');
    });

    test('στρογγυλεύει πριν χωρίσει: 659,5″ → «11:00», ποτέ «10:60»', () {
      expect(paceText(659.5), '11:00 /km');
      expect(paceText(659.4), '10:59 /km');
      expect(paceText(1319 / 2), '11:00 /km');
    });

    test('χρονόμετρο λεπτά:δευτερόλεπτα', () {
      expect(clock(1471), '24:31');
      expect(clock(3730), '1:02:10');
      expect(clock(59.6), '1:00');
      expect(clock(0), '0:00');
    });
  });

  group('Χρώμα με σημασία (σχέδια 9/11)', () {
    const all = [...Aigaio.dayThemes, ...Aigaio.nightThemes];

    test('το «χειρότερα» έχει δικό του κόκκινο, ποτέ ίδιο με την Άσκηση ή την καρδιά', () {
      expect(Aigaio.light.bad, const Color(0xFFB42318));
      for (final t in all) {
        expect(t.bad, isNot(t.exercise), reason: '${t.name} ${t.dark}');
        expect(t.bad, isNot(t.exerciseSolid), reason: '${t.name} ${t.dark}');
        expect(t.bad, isNot(t.heart), reason: '${t.name} ${t.dark}');
        expect(t.warn, isNot(t.bad), reason: '${t.name} ${t.dark}');
      }
    });

    test('κόκκινο και κεχριμπάρι διαβάζονται (≥ 4,5:1) σε κάρτα και στο κουτί προσοχής', () {
      for (final t in all) {
        expect(contrast(t.bad, t.card), greaterThanOrEqualTo(4.5), reason: 'bad ${t.name} ${t.dark}');
        expect(contrast(t.warn, t.card), greaterThanOrEqualTo(4.5), reason: 'warn ${t.name} ${t.dark}');
        expect(contrast(t.warn, t.warnBg), greaterThanOrEqualTo(4.5), reason: 'warn/warnBg ${t.name} ${t.dark}');
        expect(contrast(t.text, t.warnBg), greaterThanOrEqualTo(4.5), reason: 'text/warnBg ${t.name} ${t.dark}');
      }
    });
  });

  group('«Δικά μου» στο «+ Φαγητό», κουζίνα στο «Τα στοιχεία μου» (σχέδια 9/11, 10α–10β)', () {
    testWidgets('το «+ Φαγητό» δείχνει «Δικά μου» με ⋮ και «Όλα (N)» που ανοίγει τη λίστα', (t) async {
      final food = sampleFoodStore(_now);
      await _pump(t, AddFoodScreen(food: food, meal: Meal.snack, day: dayOf(_now)));
      expect(find.byKey(const ValueKey('add-mine')), findsOneWidget);
      expect(find.text('ΔΙΚΑ ΜΟΥ'), findsOneWidget);
      expect(find.text('Όλα (${food.mine.length}) ›'), findsOneWidget);
      expect(find.byKey(const ValueKey('add-scan')), findsOneWidget);
      expect(find.byKey(const ValueKey('add-label')), findsOneWidget);
      // Κάθε δικό μου έχει ⋮ για αλλαγή.
      final more = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('mine-more-'));
      expect(more, findsWidgets);
      await t.tap(more.first);
      await t.pumpAndSettle();
      expect(find.text('Διόρθωση'), findsOneWidget);
      expect(find.text('Διαγραφή'), findsOneWidget);
      await t.tapAt(const Offset(10, 10));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('add-mine-all')));
      await t.pumpAndSettle();
      expect(find.byType(MyFoodsScreen), findsOneWidget);
    });

    testWidgets('ένα δικό μου που φαίνεται ήδη στα Πρόσφατα δεν ξαναμπαίνει στα «Δικά μου»', (t) async {
      final food = sampleFoodStore(_now);
      final mine = food.mine.first;
      // Μέρα μετά από όλο το δείγμα: σίγουρα η πιο πρόσφατη καταχώριση.
      await food.add(mine, 100, Meal.snack, on: DateTime(2026, 11, 12));
      expect(food.recent(limit: 10).map((f) => f.id), contains(mine.id));
      await _pump(t, AddFoodScreen(food: food, meal: Meal.snack, day: dayOf(_now)));
      final inMine = find.descendant(of: find.byKey(const ValueKey('add-mine')), matching: find.text(mine.name));
      expect(inMine, findsNothing);
      expect(find.text(mine.name), findsWidgets);
    });

    testWidgets('«Τα στοιχεία μου» έχει «Τα προϊόντα μου» και «Η κουζίνα μου»', (t) async {
      final food = sampleFoodStore(_now);
      await _pump(t, MePage(store: HealthStore(), food: food));
      expect(find.text('ΔΙΑΤΡΟΦΗ'), findsOneWidget);
      expect(find.byKey(const ValueKey('mine-products')), findsOneWidget);
      expect(find.textContaining('${food.mine.length} προϊόντα'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('mine-kitchen')));
      await t.pumpAndSettle();
      expect(find.byType(KitchenScreen), findsOneWidget);
    });

    testWidgets('από τις Ρυθμίσεις (χωρίς food) παίρνει την αποθήκη της εφαρμογής', (t) async {
      final food = sampleFoodStore(_now);
      FoodStore.shared = food;
      addTearDown(() => FoodStore.shared = null);
      await _pump(t, MePage(store: HealthStore()));
      await t.tap(find.byKey(const ValueKey('mine-products')));
      await t.pumpAndSettle();
      expect(find.byType(MyFoodsScreen), findsOneWidget);
    });

    testWidgets('η Διατροφή είναι μία σελίδα, χωρίς υπο-καρτέλα «Τα δικά μου»', (t) async {
      final store = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(_now));
      store.history = sampleHistory(_now, store.data!);
      await _pump(t, Shell(store: store, food: sampleFoodStore(_now), initialIndex: Cat.food, now: _now), size: const Size(400, 1900));
      expect(find.byKey(const ValueKey('tab-Τα δικά μου')), findsNothing);
      expect(find.byKey(const ValueKey('tab-Ημερολόγιο')), findsNothing);
      expect(FoodStore.shared, isNotNull, reason: 'το Shell δηλώνει την αποθήκη φαγητού για το «Τα στοιχεία μου»');
      FoodStore.shared = null;
    });

    testWidgets('«Τα στοιχεία μου» στο 360 με 2,0× γράμματα: τίποτα δεν ξεχειλίζει', (t) async {
      await _pump(t, MePage(store: HealthStore(), food: sampleFoodStore(_now)), size: const Size(360, 3000), textScale: 2.0);
      expect(t.takeException(), isNull);
    });

    testWidgets('«+ Φαγητό» στο 360 με 2,0× γράμματα: τίποτα δεν ξεχειλίζει', (t) async {
      await _pump(t, AddFoodScreen(food: sampleFoodStore(_now), meal: Meal.snack, day: dayOf(_now)), size: const Size(360, 3000), textScale: 2.0);
      expect(t.takeException(), isNull);
    });
  });

  group('«Άσκηση σήμερα» στη Σήμερα (σχέδια 9/11, 1β)', () {
    final fri = DateTime(2026, 11, 13, 17, 30); // «A» στο δείγμα
    final tue = DateTime(2026, 11, 10, 17, 30); // περπάτημα

    Future<void> card(WidgetTester t, TrainingStore s, DateTime at) async {
      await t.runAsync(() => ExLibrary.load(inline: true));
      await _pump(t, Scaffold(body: SingleChildScrollView(child: TodayTrainingCard(training: s, now: at))));
    }

    test('χωρίς πρόγραμμα ή μέρα ξεκούρασης: καμία κάρτα', () {
      expect(TodayTrainingCard.shows(sampleTraining(fri, program: false, history: false), fri), isFalse);
      expect(TodayTrainingCard.shows(TrainingStore(), fri), isFalse, reason: 'δεν έχει διαβαστεί ακόμα');
      expect(TodayTrainingCard.shows(sampleTraining(fri), fri), isTrue);
    });

    testWidgets('μέρα βαρών: όνομα, ασκήσεις, «Ξεκίνα την προπόνηση»', (t) async {
      await card(t, sampleTraining(fri), fri);
      expect(find.text('Άσκηση σήμερα'), findsOneWidget);
      expect(find.text('Προπόνηση Α'), findsOneWidget);
      expect(find.textContaining('όριο παλμών 140'), findsOneWidget);
      expect(find.byKey(const ValueKey('today-train-start')), findsOneWidget);
    });

    testWidgets('μέρα περπατήματος: ξεκινά από το ρολόι, χωρίς κουμπί', (t) async {
      await card(t, sampleTraining(tue), tue);
      expect(find.byKey(const ValueKey('today-train-walk-hint')), findsOneWidget);
      expect(find.byKey(const ValueKey('today-train-start')), findsNothing);
    });

    testWidgets('χωρίς παλμούς με όριο γιατρού: κεχριμπάρι, ποτέ πράσινο', (t) async {
      WearLink.main.live.value = {'kind': 'walk', 'sec': 120, 'm': 300.0, 'bpm': 0, 'at': DateTime.now().millisecondsSinceEpoch};
      addTearDown(() => WearLink.main.live.value = null);
      await card(t, sampleTraining(fri), fri);
      expect(find.byKey(const ValueKey('today-training-nohr')), findsOneWidget);
      expect(find.textContaining('Το όριο 140 δεν σε προστατεύει τώρα'), findsOneWidget);
    });

    testWidgets('περπάτημα ζωντανά: χρονόμετρο και ρυθμός «/km»', (t) async {
      WearLink.main.live.value = {'kind': 'walk', 'sec': 1471, 'm': 2180.0, 'bpm': 104, 'at': DateTime.now().millisecondsSinceEpoch};
      addTearDown(() => WearLink.main.live.value = null);
      await card(t, sampleTraining(fri), fri);
      expect(find.text('24:31'), findsOneWidget);
      expect(find.text('2,18 km'), findsOneWidget);
      expect(find.text(paceText(1471 / 2.18)), findsOneWidget);
    });

    testWidgets('τελείωσε σήμερα: «έγινε» και «Δες τη σύνοψη»', (t) async {
      final s = sampleTraining(fri);
      s.sessions.add(Session.fromJson({
        ...s.sessions.last.toJson(),
        'id': 'today',
        'start': fri.subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
        'end': fri.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
      }));
      await card(t, s, fri);
      expect(find.text('έγινε'), findsOneWidget);
      expect(find.byKey(const ValueKey('today-training-summary')), findsOneWidget);
      expect(find.text('σύνολο κιλών'), findsOneWidget);
    });
  });

  group('Υγεία: 4 καρτέλες, πάντα μία σειρά (σχέδια 9/11, 2β)', () {
    const tabs = ['Ύπνος', 'Καρδιά', 'Σώμα', 'Τάσεις'];
    Future<void> pump(WidgetTester t, double scale, {int selected = 0}) => _pump(
          t,
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentTabs(tabs: tabs, selected: selected, solid: Aigaio.light.healthSolid, onTap: (_) {}),
            ),
          ),
          size: const Size(360, 800),
          textScale: scale,
        );
    Finder scroll() => find.descendant(of: find.byKey(const ValueKey('segment-tabs')), matching: find.byType(SingleChildScrollView));

    testWidgets('360 dp, 1,0× και 1,3×: χωρούν σε μία σειρά, χωρίς κύλιση', (t) async {
      for (final scale in [1.0, 1.3]) {
        await pump(t, scale);
        expect(t.takeException(), isNull);
        expect(scroll(), findsNothing, reason: '$scale×');
        final ys = {for (final l in tabs) t.getCenter(find.byKey(ValueKey('tab-$l'))).dy.round()};
        expect(ys.length, 1, reason: 'μία σειρά στο $scale×');
      }
    });

    testWidgets('360 dp, 2,0×: η ίδια σειρά κυλά, ποτέ δύο σειρές ή κομμένη λέξη', (t) async {
      await pump(t, 2.0, selected: 3);
      expect(t.takeException(), isNull);
      expect(scroll(), findsOneWidget);
      for (final l in tabs) {
        final p = t.renderObject<RenderParagraph>(find.descendant(of: find.byKey(ValueKey('tab-$l')), matching: find.byType(RichText)));
        expect(p.didExceedMaxLines, isFalse, reason: l);
      }
      // Η επιλεγμένη («Τάσεις») ορατή μέσα στη σειρά.
      final box = t.getRect(find.byKey(const ValueKey('segment-tabs')));
      final sel = t.getRect(find.byKey(const ValueKey('tab-Τάσεις')));
      expect(sel.right, lessThanOrEqualTo(box.right + 0.5));
      expect(sel.left, greaterThanOrEqualTo(box.left - 0.5));
    });

    test('η «Ανάκαμψη» δεν είναι πια καρτέλα', () {
      expect([HealthTab.sleep, HealthTab.heart, HealthTab.body, HealthTab.trends], [0, 1, 2, 3]);
    });
  });

  test('διάρκεια σε λίστα: «1 ω 23 λ», «7 ω 05 λ», «45 λ»', () {
    expect(hmList(83), '1 ω 23 λ');
    expect(hmList(425), '7 ω 05 λ');
    expect(hmList(45), '45 λ');
  });

  group('Φύλλο ποσότητας με μεγάλα γράμματα (σχέδια 9/11, 9α)', () {
    Future<void> sheet(WidgetTester t, double scale, Size size) async {
      final food = sampleFoodStore(_now);
      final f = food.recent(limit: 1).first;
      await _pump(t, Scaffold(body: QuantitySheet(food: food, item: f, initialGrams: 300, meal: Meal.snack)),
          size: size, textScale: scale);
    }

    testWidgets('1,0×: θρεπτικά σε 4 στήλες, γεύματα σε μία σειρά', (t) async {
      await sheet(t, 1.0, const Size(400, 1400));
      expect(find.byKey(const ValueKey('qty-nutrients-grid')), findsNothing);
      expect(find.byKey(const ValueKey('meal-snack')), findsNothing);
    });

    testWidgets('1,3×: θρεπτικά 2×2 με ολόκληρη τη λέξη, γεύματα 2×2, τίποτα κομμένο', (t) async {
      await sheet(t, 1.3, const Size(400, 1800));
      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('qty-nutrients-grid')), findsOneWidget);
      expect(find.text('Υδατάνθρακες'), findsOneWidget);
      expect(find.byKey(const ValueKey('meal-snack')), findsOneWidget);
    });

    testWidgets('2,0× στα 360: τίποτα δεν ξεχειλίζει', (t) async {
      await sheet(t, 2.0, const Size(360, 2600));
      expect(t.takeException(), isNull);
    });
  });

  testWidgets('Ζυγίσεις σε πίνακα: μονάδες μία φορά επάνω, η άλλη χρονιά ως διαχωριστικό (σχέδια 9/11, 9β)', (t) async {
    final at = DateTime(2026, 10, 24, 16, 30);
    final store = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(at));
    await _pump(t, Scaffold(body: BodyPage(store: store)), size: const Size(750, 2400), textScale: 1.3);
    expect(t.takeException(), isNull);
    final table = find.byKey(const ValueKey('body-weighings'));
    expect(table, findsOneWidget);
    expect(find.descendant(of: table, matching: find.text('Βάρος\nkg')), findsOneWidget);
    expect(find.descendant(of: table, matching: find.text('2025')), findsOneWidget);
    expect(find.descendant(of: table, matching: find.textContaining(' kg')), findsNothing, reason: 'η μονάδα δεν επαναλαμβάνεται σε κάθε γραμμή');
  });

  group('Οι εξηγήσεις σε μία σελίδα (σχέδια 9/11, 4α)', () {
    testWidgets('ⓘ → «Τι μετράει κάθε συσκευή» στο σωστό σημείο', (t) async {
      await _pump(t, const Scaffold(body: Center(child: InfoButton(K.weight))), size: const Size(400, 900));
      await t.tap(find.byKey(const ValueKey('info-${K.weight}')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('info-devices')));
      await t.tap(find.byKey(const ValueKey('info-devices')));
      await t.pumpAndSettle();
      final page = t.widget<DevicesPage>(find.byType(DevicesPage));
      expect(page.focus, 'inbody');
      expect(find.text('InBody H40'), findsOneWidget);
    });

    test('κάθε μέτρηση δείχνει τη συσκευή της', () {
      expect(deviceOf(K.steps), 'watch');
      expect(deviceOf(K.ringSpo2), 'oxygen');
      expect(deviceOf(K.hrv), 'oura');
    });

    testWidgets('360 dp με 2,0×: τίποτα δεν ξεχειλίζει', (t) async {
      await _pump(t, const DevicesPage(), size: const Size(360, 6000), textScale: 2.0);
      expect(t.takeException(), isNull);
    });
  });

  group('Ένας επιλογέας περιόδου (σχέδια 9/11, οδηγός)', () {
    Widget picker(int sel) => Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: PeriodPicker<int>(values: const [7, 30, 90, 365], days: (d) => d, selected: sel, onChanged: (_) {}, color: Aigaio.light.health),
          ),
        );

    testWidgets('ένα λεξιλόγιο: «7 μέρες · 30 μέρες · 3 μήνες · 1 χρόνος»', (t) async {
      await _pump(t, picker(30), size: const Size(400, 300));
      for (final w in ['7 μέρες', '30 μέρες', '3 μήνες', '1 χρόνος']) {
        expect(find.text(w), findsOneWidget);
      }
      expect(periodLabel(TrendPeriod.month), '30 μέρες');
      expect(periodLabel(TrendPeriod.year), '1 χρόνος');
    });

    testWidgets('1,3× στα 360: αριθμός πάνω, λέξη κάτω, τίποτα κομμένο', (t) async {
      await _pump(t, picker(30), size: const Size(360, 300), textScale: 1.3);
      expect(t.takeException(), isNull);
      expect(find.text('30'), findsOneWidget);
      expect(find.text('χρόνος'), findsOneWidget);
    });
  });

  group('Έλεγχος premium: μεγάλα γράμματα χωρίς σπασμένες λέξεις και αριθμούς (M1–M3)', () {
    testWidgets('M1: ο αριθμός μένει μέσα στο δαχτυλίδι και στο 2,0×', (t) async {
      await _pump(
          t,
          Scaffold(
              body: Center(
                  child: ScoreRing(value: 83, size: 60, stroke: 6, color: Aigaio.light.sleep, track: Aigaio.light.hairline))),
          size: const Size(360, 400),
          textScale: 2.0);
      final r = t.getRect(find.text('83'));
      expect(r.width, lessThanOrEqualTo(60 - 2 * 6));
      expect(r.height, lessThanOrEqualTo(60 - 2 * 6));
    });

    testWidgets('M2: «Ετοιμότητα · HRV · Παλμοί ύπνου» στο 2,0×: ίδια στοίχιση σε κάθε γραμμή', (t) async {
      final day = DateTime(2026, 11, 14);
      final clock = DateTime(2026, 11, 14, 10);
      final s = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(clock));
      s.debugSetPlan(SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 1)));
      s.history = {dateKey(day): {'o.readiness': 65.0, 'o.hrv': 39.0, 'o.sleepHr': 59.0}};
      s.ouraNights = parseOura(sleep: [
        {
          'id': 'n',
          'day': dateKey(day),
          'type': 'long_sleep',
          'bedtime_start': DateTime(2026, 11, 13, 23).toUtc().toIso8601String(),
          'bedtime_end': DateTime(2026, 11, 14, 7).toUtc().toIso8601String(),
          'time_in_bed': 8 * 3600,
          'total_sleep_duration': 7 * 3600,
        },
      ], dailySleep: const [], readiness: const []).nights;
      await _pump(t, Scaffold(body: SingleChildScrollView(child: OuraSleepTodayCard(store: s, now: clock, onTap: () {}))),
          size: const Size(360, 2400), textScale: 2.0);
      expect(t.takeException(), isNull);
      final lefts = <double>{}, rights = <double>{};
      for (var i = 0; i < 3; i++) {
        final line = find.byKey(ValueKey('oura-today-night-line-$i'));
        expect(line, findsOneWidget, reason: 'στο 2,0× οι τρεις στήλες γίνονται γραμμές');
        final texts = find.descendant(of: line, matching: find.byType(RichText)).evaluate().toList();
        lefts.add(t.getRect(find.byWidget(texts.first.widget)).left.roundToDouble());
        rights.add(t.getRect(find.byWidget(texts.last.widget)).right.roundToDouble());
      }
      expect(lefts.length, 1, reason: 'ετικέτες στοιχισμένες αριστερά');
      expect(rights.length, 1, reason: 'τιμές στοιχισμένες δεξιά');
      expect(brokenWords(t, find.byType(OuraSleepTodayCard)), isEmpty);
    });

    for (final (scale, size) in [(1.0, const Size(360, 1400)), (1.3, const Size(360, 1800)), (2.0, const Size(360, 2800)), (1.3, const Size(400, 1800))]) {
      testWidgets('M3: φύλλο ποσότητας ${size.width.round()} dp, $scale×: καμία λέξη δεν σπάει στη μέση', (t) async {
        final food = sampleFoodStore(_now);
        final f = food.recent(limit: 1).first;
        await _pump(t, Scaffold(body: QuantitySheet(food: food, item: f, initialGrams: 300, meal: Meal.snack)), size: size, textScale: scale);
        expect(t.takeException(), isNull);
        expect(brokenWords(t, find.byType(QuantitySheet)), isEmpty);
      });
    }
  });

  group('Έλεγχος premium: SHOULD', () {
    test('S5: τα ονόματα της κάρτας «Άσκηση σήμερα» χωρίς να φορτωθεί η βιβλιοθήκη, ίδια με τη βιβλιοθήκη', () async {
      final lib = await ExLibrary.load(inline: true);
      for (final e in lib.list) {
        expect(exNamesById[e.id], e.name, reason: e.id);
      }
      expect(exNamesById.length, lib.list.length);
    });

    testWidgets('S3: τα «Δικά μου» φαίνονται στην πρώτη οθόνη του «+ Φαγητό»· «Περισσότερα πρόσφατα» ανοίγει τη λίστα', (t) async {
      final food = sampleFoodStore(_now);
      await _pump(t, AddFoodScreen(food: food, meal: Meal.snack, day: dayOf(_now)), size: const Size(400, 900));
      final mine = find.byKey(const ValueKey('add-mine'));
      expect(mine, findsOneWidget);
      expect(t.getRect(mine).top, lessThan(900));
      await t.tap(find.byKey(const ValueKey('add-more-recent')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('add-more-recent')), findsNothing);
    });

    testWidgets('M5: καμία σημείωση σχεδιασμού στη σελίδα συσκευών', (t) async {
      await _pump(t, const DevicesPage(), size: const Size(400, 4000));
      expect(find.textContaining('Ανοίγει από κάθε'), findsNothing);
      expect(find.textContaining('Στις κάρτες'), findsNothing);
      expect(find.textContaining('±10%'), findsNothing);
    });
  });
}
