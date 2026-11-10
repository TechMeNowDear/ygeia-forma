// Premium επανασχεδιασμός (σχέδια 9/11): οδηγός σχεδίασης (χρώμα με σημασία, μορφές), μετακινήσεις οθονών.
// Όλα τα νούμερα είναι δοκιμαστικά.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/main.dart';
import 'package:ygeia_forma/nav.dart';
import 'package:ygeia_forma/pages/food_add.dart';
import 'package:ygeia_forma/pages/category.dart';
import 'package:ygeia_forma/pages/kitchen.dart';
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

double contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
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
}
