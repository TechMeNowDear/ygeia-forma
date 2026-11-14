// Round8 (f1, φαγητό): R8-A2-1/A2-4, R8-A3-1/A3-3/A3-4, R8-A1-5, R8-U2-1…U2-10, R8-U2 Β1, R8-A6-6 (τα προϊόντα μου).
// Όλες οι αναμενόμενες τιμές βγήκαν με το χέρι (python) από τον γραμμένο κανόνα και τις τιμές της βάσης, όχι από τον κώδικα.
// Τα «Τρόφιμο …», τα δικά μου προϊόντα και οι στόχοι είναι φανταστικά (δημόσιο repo).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/food/chol.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/food/kitchen.dart';
import 'package:ygeia_forma/food/off.dart';
import 'package:ygeia_forma/goals.dart';
import 'package:ygeia_forma/history.dart' show dateKey;
import 'package:ygeia_forma/pages/food_add.dart';
import 'package:ygeia_forma/pages/kitchen.dart';
import 'package:ygeia_forma/pages/my_foods.dart';
import 'package:ygeia_forma/pages/nutrition.dart';
import 'package:ygeia_forma/pages/nutrition_goals.dart';
import 'package:ygeia_forma/profile.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/widgets.dart' show PageHeaderScope;

import 'sample_food.dart';

/// Παρασκευή 13/11/2026, μεσημέρι.
final _now = DateTime(2026, 11, 13, 12);
final _today = DateTime(2026, 11, 13);
final _yesterday = DateTime(2026, 11, 12);

const _foodChannel = MethodChannel('ygeia/food');
const _samsung = MethodChannel('ygeia/samsung');
TestDefaultBinaryMessenger get _messenger => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

void _mockFood(Future<Object?> Function(MethodCall call) handler) {
  _messenger.setMockMethodCallHandler(_foodChannel, handler);
  addTearDown(() => _messenger.setMockMethodCallHandler(_foodChannel, null));
}

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

/// Μια οθόνη με ένα κουμπί «άνοιξε» που τρέχει το [onOpen] (για ροές που ανοίγουν δική τους οθόνη).
Future<void> _pumpHost(WidgetTester t, Future<void> Function(BuildContext ctx) onOpen, {Size size = const Size(400, 2400)}) =>
    _pump(
      t,
      Scaffold(
        body: Builder(
          builder: (ctx) => Center(child: TextButton(onPressed: () => onOpen(ctx), child: const Text('άνοιξε'))),
        ),
      ),
      size: size,
    );

/// Φανταστικό τρόφιμο με τιμές ανά 100 g.
Food _f(String id, Map<String, double> n, {String? name, String cat = 'Άλλα', String source = 'CIQUAL 2025', String? ck}) => Food(
      id: id,
      name: name ?? 'Τρόφιμο $id',
      cat: cat,
      source: source,
      cholKind: ck,
      n: Nutrients({for (final e in n.entries) e.key: NValue(e.value)}),
    );

/// Δικό μου προϊόν (από ετικέτα).
Food _mine(String id, String name, Map<String, double> n, {String? ck, String? barcode}) => Food(
      id: id,
      name: name,
      cat: myFoodsCategory,
      source: 'Ετικέτα',
      cholKind: ck,
      barcode: barcode,
      n: Nutrients({for (final e in n.entries) e.key: NValue(e.value)}),
    );

var _seq = 0;
LogEntry _le(DateTime d, Food f, double grams, {int hour = 13, Meal meal = Meal.lunch}) => LogEntry(
      id: 'r8f1-${_seq++}',
      day: dateKey(d),
      meal: meal,
      food: f,
      grams: grams,
      time: DateTime(d.year, d.month, d.day, hour),
    );

Food _byId(String id) => basicFoods().firstWhere((f) => f.id == id);

/// Φανταστικός χρήστης με στόχο 2.090 kcal· [doctor]: οδηγία γιατρού για την LDL (κορεσμένα έως 6%, αλλιώς κάτω από 10%).
Goals _goals2090({bool doctor = true, String since = '2026-11-12'}) => Goals(
      aim: GoalAim.lose,
      rate: 0.005,
      activity: 1.5,
      doctor: doctor,
      since: since,
      kg: 90,
      age: 40,
      heightCm: 180,
      male: true,
      kcalSet: 2090,
    );

const _me = Profile(birthYear: 1985, birthMonth: 12, sex: 'm', heightCm: 180);

Finder _inSheet(Finder f) => find.descendant(of: find.byType(QuantitySheet), matching: f);

/// Κουμπί ποσότητας («30 g») στο φύλλο: όχι οι τιμές των θρεπτικών (π.χ. «20 g» υδατάνθρακες).
Finder _chip(String text) => find.descendant(of: _inSheet(find.byType(OutlinedButton)), matching: find.text(text));

/// «+ Φαγητό» → αναζήτηση [query] → πάτημα στο [name]: ανοίγει η ποσότητα.
Future<void> _open(WidgetTester t, String query, String name) async {
  await t.enterText(find.byType(TextField).first, query);
  await t.pumpAndSettle();
  await t.tap(find.text(name).first);
  await t.pumpAndSettle();
}

/// Στην ποσότητα: γράφει [grams] (αν δοθεί) και πατά «Προσθήκη στο …».
Future<void> _addFromSheet(WidgetTester t, String meal, {String? grams}) async {
  if (grams != null) {
    await t.enterText(_inSheet(find.byType(TextField)), grams);
    await t.pumpAndSettle();
  }
  final add = find.text('Προσθήκη στο $meal');
  await t.ensureVisible(add);
  await t.tap(add);
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
  });

  // ---------------------------------------------------------------------------------------------------------- A2-1 / U2-3
  group('R8-A2-1 / R8-U2-3: ό,τι μετριέται με το κουτάλι: ίδια πρώτη ποσότητα, κουμπιά και έλεγχος λάθους', () {
    test('κανόνας: λίπη, «Λιπαρά» εκτός ελιών, αλείμματα από 500 kcal', () {
      for (final id in ['C17270', 'C16400', 'C11054', 'C11079', 'C16591', 'C15202', 'C15203', 'C31032']) {
        expect(isSpoonFood(_byId(id)), isTrue, reason: id);
      }
      // Χούμους 258 kcal (αλείμματα κάτω από 500), ελιές, καρύδια, τυρί: όχι.
      for (final id in ['C25621', 'C13033', 'C13032', 'C13131', 'C15005', 'C12066']) {
        expect(isSpoonFood(_byId(id)), isFalse, reason: id);
      }
      expect(isOlives(_byId('C13131')), isTrue);
      expect(isOlives(_byId('C11054')), isFalse);
    });

    test('πρώτη ποσότητα: 10 g λίπη/μαγιονέζα/μαργαρίνη/ελιές, 15 g ταχίνι και φυστικοβούτυρο, 100 g χούμους', () {
      expect(firstGrams(_byId('C11054')), 10, reason: 'μαγιονέζα');
      expect(firstGrams(_byId('C11079')), 10, reason: 'μαγιονέζα light (28,5 g λιπαρά)');
      expect(firstGrams(_byId('C16591')), 10, reason: 'μαργαρίνη');
      expect(firstGrams(_byId('C13033')), 10, reason: 'ελιές');
      expect(firstGrams(_byId('C15202')), 15, reason: 'φυστικοβούτυρο');
      expect(firstGrams(_byId('C15203')), 15, reason: 'ταχίνι');
      expect(firstGrams(_byId('C31032')), 15, reason: 'πραλίνα');
      expect(firstGrams(_byId('C25621')), 100, reason: 'χούμους');
    });

    test('«Σωστή ποσότητα;» από 100 g για ό,τι μετριέται με το κουτάλι (όχι για ελιές)', () {
      expect(entryLooksLikeTypo(_byId('C11054'), 100), isTrue, reason: 'μαγιονέζα 10 → 100 g = 692 kcal');
      expect(entryLooksLikeTypo(_byId('C11054'), 15), isFalse);
      expect(entryLooksLikeTypo(_byId('C11054'), 99), isFalse);
      expect(entryLooksLikeTypo(_byId('C15202'), 150), isTrue, reason: 'φυστικοβούτυρο 15 → 150 g = 964,5 kcal');
      expect(entryLooksLikeTypo(_byId('C15202'), 99), isFalse, reason: '636,6 kcal, κάτω από 300 g');
      expect(entryLooksLikeTypo(_byId('C16591'), 100), isTrue, reason: 'μαργαρίνη');
      expect(entryLooksLikeTypo(_byId('C13131'), 100), isFalse, reason: 'ελιές 100 g = 349 kcal: κανονικό');
      expect(entryLooksLikeTypo(_byId('C25621'), 150), isFalse, reason: 'χούμους 387 kcal');
    });

    testWidgets('μαγιονέζα από το «+ Φαγητό»: πεδίο «10», κουμπιά 5/10/15/30 g, και τα 100 g ρωτούν', (t) async {
      final store = FoodStore.preloaded(foods: basicFoods(), now: _now);
      await _pump(t, AddFoodScreen(food: store, meal: Meal.lunch, day: _today));
      await _open(t, 'μαγιονέζα', 'Μαγιονέζα');
      expect(t.widget<TextField>(_inSheet(find.byType(TextField))).controller!.text, '10');
      for (final v in ['5 g', '10 g', '15 g', '30 g']) {
        expect(_chip(v), findsOneWidget, reason: v);
      }
      expect(_chip('200 g'), findsNothing);
      await _addFromSheet(t, 'Μεσημέρι', grams: '100');
      expect(find.text('Σωστή ποσότητα;'), findsOneWidget);
      expect(find.text('100 g «Μαγιονέζα» = 692 kcal σε μία καταχώριση. Είναι σωστό;'), findsOneWidget);
    });

    testWidgets('φυστικοβούτυρο: πεδίο «15»· ελιές: κουμπιά 10/20/30/50 g', (t) async {
      final store = FoodStore.preloaded(foods: basicFoods(), now: _now);
      final pb = _byId('C15202');
      await _pump(t, Scaffold(body: QuantitySheet(food: store, item: pb, initialGrams: firstGrams(pb), meal: Meal.snack)));
      expect(t.widget<TextField>(_inSheet(find.byType(TextField))).controller!.text, '15');
      expect(_chip('30 g'), findsOneWidget);
      expect(_chip('200 g'), findsNothing);
      final olives = _byId('C13033');
      await _pump(t,
          Scaffold(body: QuantitySheet(key: const ValueKey('olives'), food: store, item: olives, initialGrams: firstGrams(olives), meal: Meal.snack)));
      for (final v in ['10 g', '20 g', '30 g', '50 g']) {
        expect(_chip(v), findsOneWidget, reason: v);
      }
      expect(_chip('5 g'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------------------------------------- A2-4 / U2-2
  group('R8-A2-4 / R8-U2-2: «ωμ…» στο γένος και τον αριθμό του ονόματος', () {
    final s = FoodStore.preloaded(foods: basicFoods(), now: _now);
    test('ετικέτα της ωμής μορφής', () {
      String raw(String id) => s.statesOf(_byId(id)).first.$2;
      expect(raw('C9810'), 'Ωμά', reason: 'Μακαρόνια (ξηρά, ωμά)');
      expect(raw('C9821'), 'Ωμά', reason: 'Χυλοπίτες (ξηρά, ωμά)');
      expect(raw('C9340'), 'Ωμή', reason: 'Κινόα (ωμή)');
      expect(raw('C6250'), 'Ωμός', reason: 'Κιμάς … (ωμός)');
      expect(raw('C28100'), 'Ωμή', reason: 'Χοιρινή μπριζόλα (ωμή)');
      expect(raw('C10026'), 'Ωμά', reason: 'Μύδια (ωμά)');
      expect(raw('C4008'), 'Ωμή', reason: 'Πατάτα (ωμή, ξεφλουδισμένη)');
      expect(raw('C9100'), 'Ωμό', reason: 'Ρύζι λευκό (ωμό)');
      expect(raw('C20034'), 'Ωμό', reason: 'Κρεμμύδι ξερό (ωμό): το «ξερό» είναι είδος, όχι κατάσταση');
      expect(raw('C20359'), 'Ξερές (πριν το βράσιμο)', reason: 'όσπρια όπως πριν');
      expect(raw('C9811'), 'Ωμά', reason: 'και όταν ανοίγει η βρασμένη μορφή');
      // Κάθε ωμή μορφή της βάσης: η λέξη της ετικέτας είναι στην παρένθεση του ονόματος.
      for (final f in basicFoods().where((f) => f.isRawWithCooked)) {
        final label = s.statesOf(f).first.$2.split(' (').first.toLowerCase();
        expect(f.name.toLowerCase(), contains(label), reason: f.name);
      }
    });
    test('η ερώτηση «πριν ή μετά το μαγείρεμα;»', () {
      expect(rawOrCookedQuestion(300, [(_byId('C9810'), 'Ωμά'), (_byId('C9811'), 'Βρασμένα')]),
          '300 g ωμά = 1.092 kcal\n300 g βρασμένα = 501 kcal');
    });
    testWidgets('μακαρόνια 300 g: «Ζύγισα: Ωμά» και διάλογος «300 g ωμά = 1.092 kcal»', (t) async {
      final store = FoodStore.preloaded(foods: basicFoods(), now: _now);
      await _pump(t, AddFoodScreen(food: store, meal: Meal.lunch, day: _today));
      await _open(t, 'μακαρόνια', 'Μακαρόνια (ξηρά, ωμά)');
      expect(_inSheet(find.text('Ωμά')), findsOneWidget);
      expect(_inSheet(find.text('Ωμό')), findsNothing);
      await _addFromSheet(t, 'Μεσημέρι', grams: '300');
      expect(find.text('300 g ωμά = 1.092 kcal\n300 g βρασμένα = 501 kcal'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Ωμά'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Βρασμένα'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- A3-1
  group('R8-A3-1: ελληνικό πίτουρο βρώμης από barcode μετρά ως πίτουρο', () {
    // Κατηγορίες όπως ενός ελληνικού πίτουρου στο Open Food Facts: «δημητριακά πρωινού», χωρίς «oat-brans».
    const greekTags = [
      'en:plant-based-foods-and-beverages', 'en:plant-based-foods', 'en:breakfasts', 'en:cereals-and-potatoes', 'en:seeds',
      'en:cereals-and-their-products', 'en:breakfast-cereals', 'en:cereal-grains', 'en:oats',
    ];
    const quakerTags = [
      'en:plant-based-foods-and-beverages', 'en:plant-based-foods', 'en:breakfasts', 'en:cereals-and-potatoes',
      'en:cereals-and-their-products', 'en:breakfast-cereals', 'en:oat-brans',
    ];

    test('όνομα: «πίτουρο» και «πίτυρο», κεφαλαία, τελικό «ς»· μόνο στην αρχή', () {
      expect(branByName('Πίτυρο Βρώμης Ψιλοαλεσμένος φλοιός βρώμης'), isTrue);
      expect(branByName('ΠΙΤΥΡΟ ΒΡΩΜΗΣ'), isTrue);
      expect(branByName('  πίτυρο βρώμης'), isTrue);
      expect(branByName('Πίτουρο βρώμης'), isTrue);
      expect(branByName('Μπάρα με πίτυρο βρώμης'), isFalse);
      expect(branByName('Oat bran flakes'), isFalse, reason: 'αγγλικά: μόνο από την κατηγορία του Open Food Facts');
    });

    test('κατηγορίες + όνομα', () {
      expect(cholKindFromOffTags(greekTags, name: 'Πίτυρο Βρώμης Ψιλοαλεσμένος'), CholKind.bran);
      expect(cholKindFromOffTags(greekTags), CholKind.none, reason: 'χωρίς όνομα πίτουρου: δημητριακά πρωινού');
      expect(cholKindFromOffTags(greekTags, name: 'Νιφάδες βρώμης'), CholKind.none);
      expect(cholKindFromOffTags(quakerTags, name: 'Oat Bran'), CholKind.bran);
      expect(cholKindFromOffTags(['en:flours', 'en:oat-brans']), CholKind.bran);
      expect(cholKindFromOffTags(['en:flours', 'en:oat-flours'], name: 'Αλεύρι βρώμης'), CholKind.none);
      // Σύνθετα με πίτουρο: «Τίποτα», και με κατηγορία πίτουρου ή όνομα που αρχίζει «πίτυρο βρώμης».
      expect(cholKindFromOffTags(['en:cereal-bars', 'en:oat-brans']), CholKind.none);
      expect(cholKindFromOffTags(['en:breakfast-cereals', 'en:mueslis', 'en:oat-brans']), CholKind.none);
      expect(cholKindFromOffTags(['en:crackers'], name: 'Πίτυρο βρώμης κράκερ'), CholKind.none);
      // Χωρίς κατηγορίες: null, και μετρά το όνομα.
      expect(cholKindFromOffTags(null, name: 'Πίτυρο βρώμης'), isNull);
    });

    test('από το Open Food Facts ως το «Χοληστερίνη»: 40 g μετρούν 40 g', () {
      final d = draftFromOff('5200000000017', {
        'product_name_el': 'Πίτυρο Βρώμης Χ',
        'categories_tags': greekTags,
        'nutriments': {'energy-kcal_100g': 360, 'proteins_100g': 17, 'carbohydrates_100g': 50, 'fat_100g': 7},
      });
      expect(d.cholKind, CholKind.bran);
      final saved = foodFromDraft(d, 'M90');
      expect(CholDay([_le(_today, saved, 40)]).branG, 40);
      // Παλιό δικό μου προϊόν χωρίς «μετρά ως», με τη γραφή «πίτυρο»: μετρά από το όνομα.
      expect(CholDay([_le(_today, _mine('M91', 'Πίτυρο βρώμης Χ', {Nk.kcal: 360}), 40)]).branG, 40);
    });

    test('αναζήτηση «πίτυρο» → πίτουρο βρώμης', () {
      final store = FoodStore.preloaded(foods: basicFoods(), now: _now);
      expect(store.search('πίτυρο').first.id, 'C9640');
      expect(store.search('πίτυρο βρώμης').first.id, 'C9640');
    });

    testWidgets('φόρμα: όνομα «Πίτυρο βρώμης …» δείχνει «Πίτουρο βρώμης»', (t) async {
      final draft = FoodDraft(name: 'Πίτυρο βρώμης Χ', values: {Nk.kcal: 360, Nk.protein: 17, Nk.carbs: 50, Nk.fat: 7});
      await _pump(t, FoodFormScreen(draft: draft, cholChoice: true), size: const Size(400, 3000));
      ChoiceChip chip(String label) => t.widget<ChoiceChip>(find.ancestor(
          of: find.descendant(of: find.byKey(const ValueKey('chol-kind')), matching: find.text(label)), matching: find.byType(ChoiceChip)));
      expect(chip('Πίτουρο βρώμης').selected, isTrue);
      expect(chip('Τίποτα').selected, isFalse);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- A3-3
  group('R8-A3-3: χωρίς οδηγία γιατρού: κορεσμένα «κάτω από 10%» (ΠΟΥ)', () {
    Future<void> card(WidgetTester t, double sat, {bool doctor = false}) async {
      final f = _f('S$sat', {Nk.kcal: 2000, Nk.satFat: sat, Nk.protein: 90, Nk.carbs: 220, Nk.fat: 70, Nk.fiber: 25, Nk.sugars: 40, Nk.salt: 4});
      await _pump(
          t,
          Scaffold(
              body: SingleChildScrollView(
                  child: GoalsSummaryCard(
                      key: ValueKey('$sat-$doctor'),
                      totals: Totals([_le(_yesterday, f, 100)]),
                      goals: _goals2090(doctor: doctor),
                      today: false,
                      health: HealthStore()))));
    }

    testWidgets('22,2 g σε 2.000 kcal = 9,99% → «10,0%»: δεν είναι κάτω από 10%', (t) async {
      await card(t, 22.2);
      expect(find.text('10,0% / κάτω από 10% των θερμίδων', findRichText: true), findsOneWidget);
      expect(find.text('Στο 10% των θερμίδων που έφαγες· ο στόχος είναι κάτω από 10%'), findsOneWidget);
    });
    testWidgets('21,6 g = 9,72% → «9,7%», χωρίς προειδοποίηση· 26,7 g = 12% → «Πάνω από το 10%»', (t) async {
      await card(t, 21.6);
      expect(find.text('9,7% / κάτω από 10% των θερμίδων', findRichText: true), findsOneWidget);
      expect(find.textContaining('10% των θερμίδων που έφαγες'), findsNothing);
      await card(t, 26.7);
      expect(find.text('Πάνω από το 10% των θερμίδων που έφαγες'), findsOneWidget);
    });
    testWidgets('με οδηγία γιατρού: «έως 6%», και το 6,0% δεν είναι πάνω', (t) async {
      // 13,34 g × 9 / 2.000 = 6,003% → «6,0%».
      await card(t, 13.34, doctor: true);
      expect(find.text('6,0% / έως 6% των θερμίδων', findRichText: true), findsOneWidget);
      expect(find.textContaining('των θερμίδων που έφαγες'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- A3-4
  test('R8-A3-4: τα τριγλυκερίδια όπως ο πίνακας 7 των ESC/EAS 2019 (αλκοόλ, άσκηση, υδατάνθρακες· και το βάρος)', () {
    expect(cholInfo.what, contains('λιγότερο αλκοόλ'));
    expect(cholInfo.what, contains('τακτική άσκηση'));
    expect(cholInfo.what, contains('υδατάνθρακες'));
    expect(cholInfo.what, contains('βοηθά και το χάσιμο βάρους'));
    expect(cholInfo.what, isNot(contains('ζάχαρη και το χάσιμο βάρους')));
  });

  // ---------------------------------------------------------------------------------------------------------------- A1-5
  group('R8-A1-5: μέρα που πέρασε με τον στόχο που ίσχυε τότε', () {
    final sun = DateTime(2026, 12, 13), tue = DateTime(2026, 12, 15);
    Goals applied() => Goals(
          aim: GoalAim.lose,
          rate: 0.005,
          activity: 1.5,
          doctor: true,
          since: '2026-11-16',
          kg: 90,
          age: 40,
          heightCm: 180,
          male: true,
          kcalAdapt: 2010,
          log: const [AdaptLog(day: '2026-12-14', tdee: 2400, before: 2160, after: 2010, applied: true)],
        );
    final f = _f('K', {Nk.kcal: 2100, Nk.protein: 120, Nk.carbs: 220, Nk.fat: 70, Nk.satFat: 12, Nk.fiber: 30, Nk.sugars: 40, Nk.salt: 4});

    Future<void> card(WidgetTester t, DateTime day) => _pump(
        t,
        Scaffold(
            body: SingleChildScrollView(
                child: GoalsSummaryCard(
                    key: ValueKey(day),
                    totals: Totals([_le(day, f, 100)]),
                    goals: applied(),
                    today: false,
                    day: day,
                    health: HealthStore()))));

    testWidgets('Κυρ 13/12, 2.100 kcal, στόχος τότε 2.160: «Κάτω από τον στόχο», λιπαρά 60–84 g', (t) async {
      await card(t, sun);
      expect(find.text('Κάτω από τον στόχο'), findsOneWidget);
      expect(find.text('Πάνω από τον στόχο'), findsNothing);
      expect(find.text('στόχος 2.160'), findsOneWidget);
      // 2.160 × 0,25 / 9 = 60· 2.160 × 0,35 / 9 = 84.
      expect(find.text('70 g / 60–84 g'), findsOneWidget);
    });
    testWidgets('Τρί 15/12 (μετά την αλλαγή): στόχος 2.010, «Πάνω από τον στόχο»', (t) async {
      await card(t, tue);
      expect(find.text('Πάνω από τον στόχο'), findsOneWidget);
      expect(find.text('στόχος 2.010'), findsOneWidget);
      // 2.010 × 0,25 / 9 = 55,8 → 56· 2.010 × 0,35 / 9 = 78,2 → 78.
      expect(find.text('70 g / 56–78 g'), findsOneWidget);
    });
    test('πριν από τους στόχους', () {
      expect(beforeGoals(applied(), DateTime(2026, 11, 15, 23)), isTrue);
      expect(beforeGoals(applied(), DateTime(2026, 11, 16)), isFalse);
      expect(beforeGoals(applied(), sun), isFalse);
      expect(beforeGoals(_goals2090(since: ''), sun), isFalse, reason: 'χωρίς ημερομηνία: όπως πριν');
    });
    testWidgets('Διατροφή: μέρα πριν από τους στόχους δείχνει το απλό «Σύνολο ημέρας»', (t) async {
      Future<void> page(String since) async {
        final food = FoodStore.preloaded(foods: basicFoods(), entries: [_le(_yesterday, _byId('C13005'), 120)], now: _yesterday);
        final health = HealthStore()
          ..setProfile(_me)
          ..setGoals(_goals2090(since: since));
        await _pump(
            t,
            Scaffold(
                key: ValueKey(since),
                body: PageHeaderScope(
                    header: const SizedBox.shrink(),
                    child: FoodTheme(child: NutritionPage(food: food, health: health, now: _now)))));
      }

      await page('2026-11-13');
      expect(find.byKey(const ValueKey('nutrition-goals')), findsNothing);
      expect(find.text('Σύνολο ημέρας'), findsWidgets);
      await page('2026-11-12');
      expect(find.byKey(const ValueKey('nutrition-goals')), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- U2-1
  group('R8-U2-1: «Αναίρεση» μετά από δεύτερο φαγητό σβήνει το δεύτερο', () {
    testWidgets('μπανάνα και μετά μήλο: φαίνεται μόνο το μήνυμα του μήλου· «Αναίρεση» σβήνει το μήλο', (t) async {
      final store = FoodStore.preloaded(foods: basicFoods(), now: _now);
      await _pump(t, AddFoodScreen(food: store, meal: Meal.snack, day: _today));
      await _open(t, 'μπανάνα', 'Μπανάνα');
      await _addFromSheet(t, 'Σνακ');
      expect(find.textContaining('Προστέθηκε: Μπανάνα'), findsOneWidget);
      await _open(t, 'μήλο', 'Μήλο (με φλούδα)');
      await _addFromSheet(t, 'Σνακ');
      expect(find.textContaining('Προστέθηκε: Μήλο'), findsOneWidget);
      expect(find.textContaining('Προστέθηκε: Μπανάνα'), findsNothing);
      await t.tap(find.text('Αναίρεση'));
      await t.pumpAndSettle();
      expect([for (final e in store.entriesFor(_today)) e.food.id], ['C13005']);
    });
    testWidgets('το μήνυμα κλείνει μόνο του (6 δευτερόλεπτα)', (t) async {
      final store = FoodStore.preloaded(foods: basicFoods(), now: _now);
      await _pump(t, AddFoodScreen(food: store, meal: Meal.snack, day: _today));
      await _open(t, 'μπανάνα', 'Μπανάνα');
      await _addFromSheet(t, 'Σνακ');
      expect(find.byType(SnackBar), findsOneWidget);
      await t.pump(const Duration(seconds: 7));
      await t.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(store.entriesFor(_today).length, 1);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- U2-4
  group('R8-U2-4: η τιμή της μπάρας στόχου στη δεξιά άκρη', () {
    testWidgets('μέρα που τελείωσε: «8,3% / έως 6% των θερμίδων» στη δεξιά άκρη της μπάρας', (t) async {
      final f = _f('E', {Nk.kcal: 1300, Nk.satFat: 12, Nk.protein: 80, Nk.carbs: 200, Nk.fat: 60, Nk.fiber: 25, Nk.sugars: 40, Nk.salt: 4});
      await _pump(
          t,
          Scaffold(
              body: SingleChildScrollView(
                  child: GoalsSummaryCard(
                      totals: Totals([_le(_yesterday, f, 100)]), goals: _goals2090(), today: false, health: HealthStore()))),
          size: const Size(400, 900));
      final bar = find.byKey(const ValueKey('goals-sat-pct'));
      final value = find.descendant(of: bar, matching: find.text('8,3% / έως 6% των θερμίδων', findRichText: true));
      expect(value, findsOneWidget);
      expect(t.getTopRight(value).dx, closeTo(t.getTopRight(bar).dx, 1));
    });
    testWidgets('360 dp με γράμματα 1,3×: «13 g / έως 14 g» στη δεξιά άκρη', (t) async {
      final f = _f('G', {Nk.kcal: 1500, Nk.satFat: 13, Nk.protein: 60, Nk.carbs: 150, Nk.fat: 50, Nk.fiber: 20, Nk.sugars: 30, Nk.salt: 3});
      await _pump(
          t,
          Scaffold(
              body: SingleChildScrollView(
                  child: GoalsSummaryCard(totals: Totals([_le(_today, f, 100)]), goals: _goals2090(), today: true, health: HealthStore()))),
          size: const Size(360, 1200),
          textScale: 1.3);
      expect(t.takeException(), isNull);
      final value = find.text('13 g / έως 14 g', findRichText: true);
      final bar = find.ancestor(of: value, matching: find.byType(GoalBar));
      expect(t.getTopRight(value).dx, closeTo(t.getTopRight(bar).dx, 1));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- U2-5
  testWidgets('R8-U2-5: «Ξερές (πριν το βράσιμο)» με γράμματα 2×: κενό πάνω και κάτω μέσα στο κουμπί', (t) async {
    final store = FoodStore.preloaded(foods: basicFoods(), now: _now);
    await _pump(t, Scaffold(body: QuantitySheet(food: store, item: _byId('C20360'), initialGrams: 200, meal: Meal.lunch)),
        size: const Size(360, 3000), textScale: 2.0);
    expect(t.takeException(), isNull);
    final text = find.text('Ξερές (πριν το βράσιμο)');
    final button = find.ancestor(of: text, matching: find.byType(OutlinedButton));
    final tr = t.getRect(text), br = t.getRect(button);
    expect(tr.top - br.top, greaterThanOrEqualTo(8));
    expect(br.bottom - tr.bottom, greaterThanOrEqualTo(8));
  });

  // ---------------------------------------------------------------------------------------------------------------- U2-6
  testWidgets('R8-U2-6: μπάρα γευμάτων: κάθε γεύμα πατιέται σε ≥ 48 dp και το TalkBack λέει ποιο είναι επιλεγμένο', (t) async {
    final handle = t.ensureSemantics();
    var picked = Meal.breakfast;
    await _pump(t, Scaffold(body: Center(child: SizedBox(width: 368, child: MealPicker(value: Meal.breakfast, onChanged: (m) => picked = m)))));
    for (final m in Meal.values) {
      expect(t.getSize(find.byKey(ValueKey('meal-bar-${m.name}'))).height, greaterThanOrEqualTo(48), reason: m.name);
    }
    expect(t.getSemantics(find.byKey(const ValueKey('meal-bar-breakfast'))),
        containsSemantics(label: 'Πρωινό', isButton: true, isSelected: true, hasTapAction: true));
    expect(t.getSemantics(find.byKey(const ValueKey('meal-bar-dinner'))),
        containsSemantics(label: 'Βράδυ', isButton: true, isSelected: false));
    // Πάτημα 2 dp κάτω από την πάνω άκρη του κουμπιού (το παλιό περιθώριο του πλαισίου) πιάνει.
    final r = t.getRect(find.byKey(const ValueKey('meal-bar-dinner')));
    await t.tapAt(Offset(r.center.dx, r.top + 2));
    expect(picked, Meal.dinner);
    handle.dispose();
  });

  // ---------------------------------------------------------------------------------------------------------- U2-7 / Β1
  group('R8-U2-7: αλάτι και μπαχαρικά με την πρέζα', () {
    test('πρώτη ποσότητα 2 g και έλεγχος λάθους από 10 g αλάτι σε μία καταχώριση', () {
      expect(firstGrams(_byId('C11017')), 2);
      expect(firstGrams(_byId('C11015')), 2, reason: 'πιπέρι (Καρυκεύματα)');
      expect(firstGrams(_byId('C11035')), 2, reason: 'ρίγανη');
      expect(entryLooksLikeTypo(_byId('C11017'), 100), isTrue, reason: '97,75 g αλάτι');
      expect(entryLooksLikeTypo(_byId('C11017'), 3), isFalse);
      expect(entryLooksLikeTypo(_byId('C11017'), 10), isFalse, reason: '9,775 g < 10 g');
      expect(entryLooksLikeTypo(_byId('C11017'), 11), isTrue, reason: '10,75 g');
      expect(entryLooksLikeTypo(_byId('C26694'), 100), isFalse, reason: 'αντζούγιες 13,6 g/100 g: όχι «τρόφιμο αλάτι»');
      expect(typoQuestion(_byId('C11017'), 50), '50 g «Αλάτι» = 48,9 g αλάτι σε μία καταχώριση. Είναι σωστό;');
    });
    testWidgets('«Αλάτι» από το «+ Φαγητό»: πεδίο «2», κουμπιά 1/2/3/5 g, πλακίδιο αλατιού, 50 g ρωτούν', (t) async {
      final store = FoodStore.preloaded(foods: basicFoods(), now: _now);
      await _pump(t, AddFoodScreen(food: store, meal: Meal.lunch, day: _today));
      await _open(t, 'αλάτι', 'Αλάτι');
      expect(t.widget<TextField>(_inSheet(find.byType(TextField))).controller!.text, '2');
      for (final v in ['1 g', '2 g', '3 g', '5 g']) {
        expect(_chip(v), findsOneWidget, reason: v);
      }
      expect(_chip('50 g'), findsNothing);
      // 2 g × 97,75 / 100 = 1,955 → «2,0 g»· στη θέση των λιπαρών (0 g).
      expect(_inSheet(find.text('2,0 g')), findsOneWidget);
      expect(_inSheet(find.text('Λιπαρά')), findsNothing);
      await _addFromSheet(t, 'Μεσημέρι', grams: '50');
      expect(find.text('Σωστή ποσότητα;'), findsOneWidget);
      expect(find.text('50 g «Αλάτι» = 48,9 g αλάτι σε μία καταχώριση. Είναι σωστό;'), findsOneWidget);
    });
  });

  group('R8-U2 Β1: πίτουρο και νιφάδες βρώμης ανοίγουν με τη μερίδα του πλάνου', () {
    test('40 g, ή όσο λέει το πλάνο σου', () {
      expect(firstGrams(_byId('C9640')), 40);
      expect(firstGrams(_byId('C9640'), branG: 30), 30);
      expect(firstGrams(_byId('C9640'), branG: 0), 40, reason: 'πλάνο χωρίς πίτουρο: η προεπιλογή');
      expect(firstGrams(_byId('C32140')), 40, reason: 'νιφάδες βρώμης');
      expect(firstGrams(_mine('M92', 'Πίτυρο βρώμης Χ', {Nk.kcal: 360})), 40);
      expect(firstGrams(_byId('C9313')), 100, reason: 'χυλός βρώμης: όπως πριν');
    });
    testWidgets('«πίτουρο» από το «+ Φαγητό»: πεδίο «40», κουμπιά 20/30/40/50 g', (t) async {
      final store = FoodStore.preloaded(foods: basicFoods(), now: _now);
      await _pump(t, AddFoodScreen(food: store, meal: Meal.breakfast, day: _today));
      await _open(t, 'πίτουρο', 'Πίτουρο βρώμης');
      expect(t.widget<TextField>(_inSheet(find.byType(TextField))).controller!.text, '40');
      for (final v in ['20 g', '30 g', '40 g', '50 g']) {
        expect(_chip(v), findsOneWidget, reason: v);
      }
      expect(_chip('200 g'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------------------------------------- U2-8 / A6-6
  group('R8-U2-8: «Τα προϊόντα μου» από το «+ Φαγητό»: «Σάρωση» και «Από ετικέτα» το γράφουν', () {
    final known = _mine('M77', 'Κράκερ σίκαλης Χ', {Nk.kcal: 400, Nk.protein: 10, Nk.carbs: 70, Nk.fat: 8}, barcode: '5200000000123');

    Future<void> openMine(WidgetTester t, FoodStore store) async {
      await _pump(t, AddFoodScreen(food: store, meal: Meal.snack, day: _today));
      final all = find.byKey(const ValueKey('add-mine-all'));
      await t.ensureVisible(all);
      await t.tap(all);
      await t.pumpAndSettle();
      expect(find.byType(MyFoodsScreen), findsOneWidget);
    }

    testWidgets('σάρωση προϊόντος που έχεις ήδη → η ποσότητα του, όχι «Διόρθωση προϊόντος»', (t) async {
      _mockFood((call) async => call.method == 'scanBarcode' ? jsonEncode({'ok': true, 'code': '5200000000123'}) : jsonEncode({'ok': true}));
      final store = FoodStore.preloaded(foods: basicFoods(), mine: [known], now: _now);
      await openMine(t, store);
      await t.tap(find.text('Σάρωση'));
      await t.pumpAndSettle();
      expect(find.byType(FoodFormScreen), findsNothing);
      expect(find.byType(MyFoodsScreen), findsNothing);
      expect(_inSheet(find.text('Κράκερ σίκαλης Χ')), findsOneWidget);
    });

    testWidgets('«Από ετικέτα» → αποθήκευση → η ποσότητα του νέου προϊόντος', (t) async {
      final store = FoodStore.preloaded(foods: basicFoods(), mine: [known], now: _now);
      await openMine(t, store);
      await t.tap(find.text('Από ετικέτα'));
      await t.pumpAndSettle();
      expect(find.byType(FoodFormScreen), findsOneWidget);
      await t.enterText(find.widgetWithText(TextField, 'Όνομα'), 'Κριτσίνια Χ');
      for (final (k, v) in [(Nk.kcal, '410'), (Nk.fat, '9'), (Nk.carbs, '70'), (Nk.protein, '12')]) {
        final field = find.byKey(ValueKey('field-$k'));
        await t.ensureVisible(field);
        await t.enterText(field, v);
        await t.pumpAndSettle();
      }
      final save = find.text('Αποθήκευση');
      await t.ensureVisible(save);
      await t.tap(save);
      await t.pumpAndSettle();
      expect(find.byType(MyFoodsScreen), findsNothing);
      expect(_inSheet(find.text('Κριτσίνια Χ')), findsOneWidget);
      expect(store.mine.map((f) => f.name), contains('Κριτσίνια Χ'));
    });

    testWidgets('R8-A6-6: η οδηγία χωρίς «⋮» (δεν υπάρχει στη γραμματοσειρά)', (t) async {
      await _pump(t, MyFoodsScreen(food: sampleFoodStore(_now), pick: true));
      expect(find.textContaining('⋮'), findsNothing);
      expect(find.textContaining('τρεις τελείες'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- U2-9
  testWidgets('R8-U2-9: «Χοληστερίνη» και «εκ των οποίων» στις τιμές του τροφίμου', (t) async {
    await _pump(t, FoodDetailScreen(food: _byId('C11054')));
    expect(find.textContaining('Χοληστερίνη'), findsOneWidget);
    expect(find.textContaining('Χοληστερόλη'), findsNothing);
    expect(find.textContaining('εκ των οποίων κορεσμένα'), findsOneWidget);
    expect(find.textContaining('από τα οποία'), findsNothing);
  });

  // --------------------------------------------------------------------------------------------------------------- U2-10
  testWidgets('R8-U2-10: «Αναίρεση» από κλειστή «Η κουζίνα μου»: στις τωρινές ρυθμίσεις, και η ανοιχτή οθόνη το βλέπει', (t) async {
    _messenger.setMockMethodCallHandler(_samsung, (call) async {
      if (call.method == 'loadPrefs') {
        return jsonEncode({
          'kitchen': {
            'seed': 2,
            'devices': ['scale'],
            'cookware': [
              {'id': 'x1', 'kind': 'pot', 'brand': 'Μάρκα Τ'},
            ],
          },
        });
      }
      return '{"ok":true}';
    });
    addTearDown(() => _messenger.setMockMethodCallHandler(_samsung, null));
    final store = HealthStore();
    await t.runAsync(() => store.loadPrefs());
    expect(store.prefsLoaded, isTrue);
    await _pumpHost(t, (ctx) => Navigator.of(ctx).push<void>(MaterialPageRoute(builder: (_) => KitchenScreen(store: store))));
    await t.tap(find.text('άνοιξε'));
    await t.pumpAndSettle();
    final pot = find.text('Κατσαρόλα · Μάρκα Τ');
    await t.ensureVisible(pot);
    await t.tap(pot);
    await t.pumpAndSettle();
    final delete = find.text('Διαγραφή');
    await t.ensureVisible(delete);
    await t.tap(delete);
    await t.pumpAndSettle();
    await t.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await t.pumpAndSettle();
    // Νέα «Η κουζίνα μου» χωρίς την κατσαρόλα· τσεκάρεις φριτέζα αέρος.
    await t.tap(find.text('άνοιξε'));
    await t.pumpAndSettle();
    expect(find.text('Κατσαρόλα · Μάρκα Τ'), findsNothing);
    final fryer = find.text('Φριτέζα αέρος (air fryer)');
    await t.ensureVisible(fryer);
    await t.tap(fryer);
    await t.pumpAndSettle();
    expect(Kitchen.fromJson(store.prefs.kitchen).has('airFryer'), isTrue);
    // Το «Αναίρεση» της πρώτης οθόνης: η κατσαρόλα ξαναμπαίνει ΚΑΙ η φριτέζα μένει.
    await t.tap(find.text('Αναίρεση'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    var k = Kitchen.fromJson(store.prefs.kitchen);
    expect(k.has('airFryer'), isTrue);
    expect(k.cookware.map((c) => c.id), ['x1']);
    // Η ανοιχτή οθόνη τη δείχνει, και η επόμενη αλλαγή της δεν τη σβήνει.
    await t.ensureVisible(find.text('Κατσαρόλα · Μάρκα Τ'));
    expect(find.text('Κατσαρόλα · Μάρκα Τ'), findsOneWidget);
    final kettle = find.text('Βραστήρας');
    await t.ensureVisible(kettle);
    await t.tap(kettle);
    await t.pumpAndSettle();
    k = Kitchen.fromJson(store.prefs.kitchen);
    expect(k.has('kettle'), isTrue);
    expect(k.has('airFryer'), isTrue);
    expect(k.cookware.map((c) => c.id), ['x1']);
  });
}
