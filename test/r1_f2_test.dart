// Έλεγχος round1 (f2): τρόφιμα, καταγραφή, αναζήτηση, κάρτα «Χοληστερίνη» (λογική), οθόνες της Διατροφής.
// Όλες οι αναμενόμενες τιμές είναι υπολογισμένες με το χέρι από τον γραμμένο κανόνα (όχι από τον κώδικα). Τα τρόφιμα
// «Τρόφιμο …» και τα δικά μου προϊόντα είναι φανταστικά.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/food/chol.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_search.dart';
import 'package:ygeia_forma/food/food_sources.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/food/kitchen.dart';
import 'package:ygeia_forma/food/off.dart';
import 'package:ygeia_forma/history.dart' show dateKey;
import 'package:ygeia_forma/home_widgets/widget_bridge.dart' show widgetOpenRequest;
import 'package:ygeia_forma/main.dart';
import 'package:ygeia_forma/nav.dart';
import 'package:ygeia_forma/pages/category.dart';
import 'package:ygeia_forma/pages/food_add.dart';
import 'package:ygeia_forma/pages/kitchen.dart';
import 'package:ygeia_forma/pages/me_page.dart';
import 'package:ygeia_forma/pages/my_foods.dart';
import 'package:ygeia_forma/pages/nutrition.dart';
import 'package:ygeia_forma/theme.dart';

import 'sample_data.dart';
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

/// Μια οθόνη με ένα κουμπί «άνοιξε» που τρέχει το [onOpen] (για ροές που ανοίγουν δική τους οθόνη ή φύλλο).
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

/// Φανταστικό τρόφιμο με τιμές ανά 100 g (ή ml).
Food _f(String id, Map<String, double> n,
        {String? name, String cat = 'Άλλα', String source = 'CIQUAL 2025', String? ck, bool perMl = false}) =>
    Food(
      id: id,
      name: name ?? 'Τρόφιμο $id',
      cat: cat,
      source: source,
      cholKind: ck,
      perMl: perMl,
      n: Nutrients({for (final e in n.entries) e.key: NValue(e.value)}),
    );

/// Δικό μου προϊόν (από ετικέτα).
Food _mine(String id, String name, Map<String, double> n, {String? ck}) =>
    _f(id, n, name: name, cat: 'Τα προϊόντα μου', source: 'Ετικέτα', ck: ck);

var _seq = 0;
LogEntry _le(DateTime d, Food f, double grams) => LogEntry(
      id: 'r1f2-${_seq++}',
      day: dateKey(d),
      meal: Meal.lunch,
      food: f,
      grams: grams,
      time: DateTime(d.year, d.month, d.day, 13),
    );

Food _byId(String id) => basicFoods().firstWhere((f) => f.id == id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('S2-8 / S11-1: το widget «+ Φαγητό» γράφει ΠΑΝΤΑ στη σημερινή μέρα', () {
    testWidgets('το ημερολόγιο έμεινε στο «Χθες»: το πάτημα του widget ανοίγει την προσθήκη για ΣΗΜΕΡΑ', (t) async {
      final store = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(_now));
      store.history = sampleHistory(_now, store.data!);
      final food = sampleFoodStore(_now);
      addTearDown(() {
        widgetOpenRequest.value = null;
        FoodStore.shared = null;
      });
      await _pump(t, Shell(store: store, food: food, initialIndex: Cat.food, now: _now), size: const Size(400, 1900));
      food.setDay(_yesterday);
      await t.pumpAndSettle();
      expect(food.day, _yesterday);

      widgetOpenRequest.value = 'w:food:add:';
      await t.pump();
      await t.pumpAndSettle();

      expect(find.byType(AddFoodScreen), findsOneWidget);
      expect(t.widget<AddFoodScreen>(find.byType(AddFoodScreen)).day, _today, reason: 'πριν: η μέρα που είχε μείνει (χθες)');
      expect(food.day, _today);
      expect(find.descendant(of: find.byKey(const ValueKey('add-day')), matching: find.text('Μέρα: Σήμερα · Παρ 13/11')),
          findsOneWidget);
    });

    test('και το «Barcode» του widget: πρώτα «Σήμερα», μετά ο σαρωτής (S2-8)· S2-5: κανένα setState σε κλειστή οθόνη', () {
      final main = File('lib/main.dart').readAsStringSync();
      final scan = main.indexOf('openAddFood(context, _food, scan: true)');
      expect(scan, greaterThan(0));
      final caseScan = main.lastIndexOf("case 'scan':", scan);
      final setDay = main.lastIndexOf('_food.setDay(widget.now ?? DateTime.now());', scan);
      expect(setDay, greaterThan(caseScan), reason: 'το setDay μέσα στο ίδιο case, πριν από τον σαρωτή');
      final src = File('lib/pages/food_add.dart').readAsStringSync();
      expect(src, contains('if (mounted) setState(() => _busy = b);'));
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('S2-11: κρύα εκκίνηση (η εφαρμογή ανοίγει από το widget)', () {
    test('waitLoaded περιμένει την πρώτη ανάγνωση και μετά λέει «διαβάστηκε»', () async {
      final gate = Completer<void>();
      _mockFood((call) async {
        if (call.method == 'logRange') {
          await gate.future;
          return jsonEncode({'ok': true, 'entries': <Object>[]});
        }
        if (call.method == 'myFoods') return jsonEncode({'ok': true, 'foods': <Object>[]});
        return jsonEncode({'ok': true});
      });
      final s = FoodStore();
      addTearDown(s.dispose);
      expect(s.loaded, isFalse);
      final started = s.start();
      var done = false;
      final waiting = s.waitLoaded().then((v) {
        done = true;
        return v;
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(done, isFalse, reason: 'το ημερολόγιο διαβάζεται ακόμα');
      gate.complete();
      expect(await waiting, isTrue);
      await started;
      expect(s.loaded, isTrue);
      expect(await s.waitLoaded(), isTrue);
    });

    test('η ανάγνωση απέτυχε: false και σφάλμα (η Διατροφή δείχνει «Ξαναδοκίμασε»)', () async {
      _mockFood((call) async => switch (call.method) {
            'logRange' => jsonEncode({'ok': false, 'kind': 'other', 'message': 'δοκιμή'}),
            'myFoods' => jsonEncode({'ok': true, 'foods': <Object>[]}),
            _ => jsonEncode({'ok': true}),
          });
      final s = FoodStore();
      addTearDown(s.dispose);
      await s.start();
      expect(await s.waitLoaded(), isFalse);
      expect(s.error, isNotNull);
    });

    test('δεν τελείωσε μέσα στο όριο: false χωρίς σφάλμα (τότε «διαβάζεται ακόμα»)', () async {
      final gate = Completer<void>();
      _mockFood((call) async {
        await gate.future;
        return jsonEncode(call.method == 'logRange' ? {'ok': true, 'entries': <Object>[]} : {'ok': true, 'foods': <Object>[]});
      });
      final s = FoodStore();
      addTearDown(s.dispose);
      final started = s.start();
      expect(await s.waitLoaded(timeout: const Duration(milliseconds: 30)), isFalse);
      expect(s.error, isNull);
      expect(diaryStillLoadingText, isNot(contains('Ξαναδοκίμασε')), reason: 'κουμπί που δεν υπάρχει ακόμα');
      // Η ανάγνωση τελειώνει κανονικά αργότερα.
      gate.complete();
      await started;
      expect(await s.waitLoaded(), isTrue);
    });

    test('αποθήκη που έχει ήδη διαβαστεί: αμέσως true', () async {
      expect(await sampleFoodStore(_now).waitLoaded(), isTrue);
    });

    testWidgets('«+ Φαγητό» με ημερολόγιο που δεν διαβάστηκε: μήνυμα, καμία οθόνη προσθήκης', (t) async {
      _mockFood((call) async => switch (call.method) {
            'logRange' => jsonEncode({'ok': false, 'kind': 'other', 'message': 'δοκιμή'}),
            'myFoods' => jsonEncode({'ok': true, 'foods': <Object>[]}),
            _ => jsonEncode({'ok': true}),
          });
      final s = FoodStore();
      addTearDown(s.dispose);
      await t.runAsync(() => s.start());
      await _pumpHost(t, (ctx) => openAddFood(ctx, s));
      await t.tap(find.text('άνοιξε'));
      await t.pumpAndSettle();
      expect(find.byType(AddFoodScreen), findsNothing);
      expect(find.text(diaryNotReadText), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('U3a-1 / U3a-20: η μέρα φαίνεται παντού, και ένα πάτημα γυρίζει στο «Σήμερα»', () {
    test('entryDayLabel', () {
      expect(entryDayLabel(_today, _now), 'Σήμερα · Παρ 13/11');
      expect(entryDayLabel(_yesterday, _now), 'Χθες · Πέμ 12/11');
      expect(entryDayLabel(DateTime(2026, 11, 10), _now), 'Τρί 10/11');
      // αλλαγή μήνα: 31/10/2026 είναι Σάββατο
      expect(entryDayLabel(DateTime(2026, 10, 31, 23, 59), DateTime(2026, 11, 1, 0, 5)), 'Χθες · Σάβ 31/10');
    });

    testWidgets('οθόνη προσθήκης για χθες: «Μέρα: Χθες · Πέμ 12/11» και το «Προστέθηκε» λέει τη μέρα', (t) async {
      final food = sampleFoodStore(_now);
      await _pump(t, AddFoodScreen(food: food, meal: Meal.snack, day: _yesterday, clock: () => _now));
      final line = find.descendant(of: find.byKey(const ValueKey('add-day')), matching: find.text('Μέρα: Χθες · Πέμ 12/11'));
      expect(line, findsOneWidget);
      expect(t.widget<Text>(line).style!.fontWeight, FontWeight.w700, reason: 'έντονο όταν δεν είναι η σημερινή');

      await t.enterText(find.byType(TextField), 'μπανάνα');
      await t.pumpAndSettle();
      await t.tap(find.text('Μπανάνα').first);
      await t.pumpAndSettle();
      final add = find.text('Προσθήκη στο Σνακ');
      await t.ensureVisible(add);
      await t.tap(add);
      await t.pumpAndSettle();
      expect(find.textContaining('Προστέθηκε (Χθες · Πέμ 12/11): Μπανάνα'), findsOneWidget);
      expect(food.entriesFor(_yesterday).where((e) => e.food.name == 'Μπανάνα').length, 2,
          reason: 'η χθεσινή του δείγματος και η νέα');
    });

    testWidgets('οθόνη προσθήκης για σήμερα: «Μέρα: Σήμερα · Παρ 13/11», όχι έντονο', (t) async {
      await _pump(t, AddFoodScreen(food: sampleFoodStore(_now), meal: Meal.snack, day: _today, clock: () => _now));
      final line = find.descendant(of: find.byKey(const ValueKey('add-day')), matching: find.text('Μέρα: Σήμερα · Παρ 13/11'));
      expect(line, findsOneWidget);
      expect(t.widget<Text>(line).style!.fontWeight, FontWeight.w500);
    });

    testWidgets('Διατροφή: η κεφαλίδα γράφει τη μέρα που φαίνεται· «Πίσω στο Σήμερα» με ένα πάτημα', (t) async {
      final store = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(_now));
      store.history = sampleHistory(_now, store.data!);
      final food = sampleFoodStore(_now);
      addTearDown(() => FoodStore.shared = null);
      await _pump(t, Shell(store: store, food: food, initialIndex: Cat.food, now: _now), size: const Size(400, 1900));
      final page = find.byWidgetPredicate((w) => w is CategoryPage && w.title == 'Διατροφή');
      expect(find.descendant(of: page, matching: find.text('Παρασκευή 13 Νοεμβρίου')), findsOneWidget);
      expect(find.byKey(const ValueKey('diary-today')), findsNothing);

      food.setDay(DateTime(2026, 11, 11));
      await t.pumpAndSettle();
      expect(find.descendant(of: page, matching: find.text('Τετάρτη 11 Νοεμβρίου')), findsOneWidget);
      expect(find.descendant(of: page, matching: find.text('Παρασκευή 13 Νοεμβρίου')), findsNothing);
      expect(t.widget<Text>(find.byKey(const ValueKey('diary-day'))).data, 'Τετ 11/11');

      final back = find.byKey(const ValueKey('diary-today'));
      await t.ensureVisible(back);
      await t.tap(back);
      await t.pumpAndSettle();
      expect(food.day, _today);
      expect(find.descendant(of: page, matching: find.text('Παρασκευή 13 Νοεμβρίου')), findsOneWidget);
      expect(find.byKey(const ValueKey('diary-day')), findsNothing);
    });

    testWidgets('U3a-20 χωρίς το Shell: δύο εβδομάδες πίσω → ένα πάτημα → σήμερα', (t) async {
      final food = sampleFoodStore(_now);
      await _pump(t, Scaffold(body: FoodTheme(child: NutritionPage(food: food, now: _now))));
      food.setDay(DateTime(2026, 10, 30));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const ValueKey('diary-day'))).data, 'Παρ 30/10');
      expect(find.text('Πίσω στο Σήμερα'), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('diary-today')));
      await t.tap(find.byKey(const ValueKey('diary-today')));
      await t.pumpAndSettle();
      expect(food.day, _today);
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('S2-1 / S1-9: τα δικά μου προϊόντα μετρούν στην κάρτα «Χοληστερίνη»', () {
    final d = DateTime(2026, 11, 10);

    test('ό,τι λέει το προϊόν: ξηροί καρποί, όσπρια (μαγειρεμένα ÷ 2,5), ψάρι, πίτουρο', () {
      final nuts = _mine('M1', 'Καρύδια ψίχα', {Nk.kcal: 690, Nk.fat: 65}, ck: CholKind.nuts);
      final cookedBeans = _mine('M2', 'Φασόλια γίγαντες βάζο', {Nk.kcal: 120}, ck: CholKind.legumes);
      final dryBeans = _mine('M3', 'Φακές ψιλές', {Nk.kcal: 340}, ck: CholKind.legumes);
      final fish = _mine('M4', 'Τόνος σε νερό', {Nk.kcal: 110}, ck: CholKind.fish);
      final bran = _mine('M5', 'Νιφάδες πρωινού', {Nk.kcal: 370}, ck: CholKind.bran);

      expect(CholDay([_le(d, nuts, 30)]).nutsG, 30);
      expect(CholDay([_le(d, cookedBeans, 100)]).legumesDryG, closeTo(40, 1e-9), reason: '120 kcal/100 g = μαγειρεμένα');
      expect(CholDay([_le(d, cookedBeans, 100)]).legumes, isTrue);
      expect(CholDay([_le(d, dryBeans, 40)]).legumesDryG, closeTo(40, 1e-9), reason: '340 kcal/100 g = ξερά');
      expect(CholDay([_le(d, fish, 100)]).fish, isTrue);
      expect(CholDay([_le(d, fish, 99)]).fish, isFalse);
      expect(CholDay([_le(d, bran, 45)]).branG, 45);
      // όριο ξερά/μαγειρεμένα: 250 kcal
      expect(CholDay([_le(d, _mine('M6', 'Όσπρια Α', {Nk.kcal: 249}, ck: CholKind.legumes), 100)]).legumesDryG, closeTo(40, 1e-9));
      expect(CholDay([_le(d, _mine('M7', 'Όσπρια Β', {Nk.kcal: 250}, ck: CholKind.legumes), 100)]).legumesDryG, closeTo(100, 1e-9));
    });

    test('χωρίς «μετρά ως»: όπως πριν (τίποτα)· με «μετρά ως» ισχύει μόνο αυτό', () {
      final plain = _mine('M1', 'Καρύδια ψίχα', {Nk.kcal: 690});
      expect(CholDay([_le(d, plain, 30)]).nutsG, 0);
      // Το όνομα λέει «πίτουρο βρώμης», αλλά το προϊόν ορίστηκε ξηροί καρποί: μετρά μόνο ως ξηροί καρποί.
      final mixed = _mine('M2', 'Πίτουρο βρώμης με καρύδια', {Nk.kcal: 450}, ck: CholKind.nuts);
      final day = CholDay([_le(d, mixed, 30)]);
      expect((day.nutsG, day.branG), (30.0, 0.0));
    });

    test('JSON «ck»: μόνο γνωστές τιμές· χωρίς αυτό (παλιό αρχείο) = null· περνά και στο αντίγραφο της καταχώρισης', () {
      final base = {'id': 'M1', 'name': 'Καρύδια', 'cat': 'Τα προϊόντα μου', 'source': 'Ετικέτα', 'n': {'kcal': 690}};
      expect(Food.fromJson({...base, 'ck': 'nuts'}).cholKind, CholKind.nuts);
      expect(Food.fromJson({...base, 'ck': 'σκουπίδι'}).cholKind, isNull);
      expect(Food.fromJson({...base, 'ck': 5}).cholKind, isNull);
      expect(Food.fromJson(base).cholKind, isNull);
      expect(Food.fromJson(base).toJson().containsKey('ck'), isFalse, reason: 'τίποτα νέο στα παλιά προϊόντα');
      final f = Food.fromJson({...base, 'ck': 'fish'});
      expect(f.toJson()['ck'], 'fish');
      final e = LogEntry.fromJson(jsonDecode(jsonEncode(_le(d, f, 100).toJson())) as Map<String, dynamic>);
      expect(e.food.cholKind, CholKind.fish);
      expect(CholDay([e]).fish, isTrue);
    });

    test('Open Food Facts: κατηγορίες → «μετρά ως», προσεκτικά', () {
      expect(cholKindFromOffTags(['en:plant-based-foods', 'en:nuts', 'en:walnuts']), CholKind.nuts);
      expect(cholKindFromOffTags([' EN:NUTS ']), CholKind.nuts);
      expect(cholKindFromOffTags(['en:canned-fishes', 'en:tunas']), CholKind.fish);
      expect(cholKindFromOffTags(['en:canned-chickpeas']), CholKind.legumes);
      expect(cholKindFromOffTags(['en:oat-bran']), CholKind.bran);
      expect(cholKindFromOffTags(['en:peanuts']), CholKind.nuts, reason: 'αράπικα φιστίκια: ξηροί καρποί, όπως στη βάση');
      // Ό,τι απλώς ΠΕΡΙΕΧΕΙ: τίποτα.
      expect(cholKindFromOffTags(['en:spreads', 'en:nut-butters', 'en:peanut-butters', 'en:peanuts']), isNull);
      expect(cholKindFromOffTags(['en:chocolates', 'en:nuts']), isNull);
      expect(cholKindFromOffTags(['en:breaded-fish', 'en:fishes']), isNull);
      expect(cholKindFromOffTags(['en:chestnuts', 'en:nuts']), isNull);
      expect(cholKindFromOffTags(['en:yogurts']), isNull);
      expect(cholKindFromOffTags(null), isNull);
      expect(cholKindFromOffTags('en:nuts'), isNull);
      expect(cholKindFromOffTags(<Object>[5, 'en:nuts']), CholKind.nuts);

      final draft = draftFromOff('5200000000000', {
        'product_name': 'Καρύδια',
        'nutriments': {'energy-kcal_100g': 690, 'proteins_100g': 15, 'carbohydrates_100g': 7, 'fat_100g': 65},
        'categories_tags': ['en:nuts', 'en:walnuts'],
      });
      expect(draft.cholKind, CholKind.nuts);
      final food = foodFromDraft(draft, 'M9');
      expect(food.cholKind, CholKind.nuts);
      expect(draftFromFood(food).cholKind, CholKind.nuts, reason: 'η διόρθωση το κρατά');
    });

    test('όταν ορίζεις «μετρά ως» αργότερα, βρίσκονται και οι μέρες που το είχες ήδη γράψει', () {
      final m = _mine('M1', 'Καρύδια ψίχα', {Nk.kcal: 690, Nk.fat: 65});
      final e = _le(_yesterday, m, 30);
      final s = FoodStore.preloaded(foods: basicFoods(), entries: [e], mine: [m], now: _now);
      expect(s.entriesWithOldValues(m), isEmpty);
      final edited = _mine('M1', 'Καρύδια ψίχα', {Nk.kcal: 690, Nk.fat: 65}, ck: CholKind.nuts);
      expect(s.entriesWithOldValues(edited).map((x) => x.id), [e.id]);
    });

    testWidgets('φόρμα προϊόντος: η επιλογή «μετρά ως» αποθηκεύεται· κρυμμένη, κρατά ό,τι είχε το προϊόν', (t) async {
      Food? saved;
      final draft = FoodDraft(name: 'Καρύδια ψίχα', values: {Nk.kcal: 690, Nk.protein: 15, Nk.carbs: 7, Nk.fat: 65});
      await _pumpHost(t, (ctx) async {
        saved = await Navigator.of(ctx).push<Food>(MaterialPageRoute(builder: (_) => FoodFormScreen(draft: draft, cholChoice: true)));
      });
      await t.tap(find.text('άνοιξε'));
      await t.pumpAndSettle();
      final nuts = find.descendant(of: find.byKey(const ValueKey('chol-kind')), matching: find.text('Ξηροί καρποί'));
      await t.ensureVisible(nuts);
      await t.tap(nuts);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Αποθήκευση'));
      await t.tap(find.text('Αποθήκευση'));
      await t.pumpAndSettle();
      expect(saved!.cholKind, CholKind.nuts);

      saved = null;
      final fishDraft = FoodDraft(name: 'Τόνος', values: {Nk.kcal: 110, Nk.protein: 25, Nk.carbs: 0, Nk.fat: 1}, cholKind: CholKind.fish);
      await _pumpHost(t, (ctx) async {
        saved = await Navigator.of(ctx).push<Food>(MaterialPageRoute(builder: (_) => FoodFormScreen(draft: fishDraft, cholChoice: false)));
      });
      await t.tap(find.text('άνοιξε'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('chol-kind')), findsNothing);
      await t.ensureVisible(find.text('Αποθήκευση'));
      await t.tap(find.text('Αποθήκευση'));
      await t.pumpAndSettle();
      expect(saved!.cholKind, CholKind.fish);
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('S2-2 / S12-02 (Τ2): κορεσμένα % των θερμίδων και μέσοι όροι εβδομάδας, με αριθμούς από το χέρι', () {
    final a = _f('A', {Nk.kcal: 250, Nk.satFat: 5, Nk.fiber: 4, Nk.salt: 1.2});
    final b = _f('B', {Nk.kcal: 200, Nk.satFat: 2, Nk.fiber: 3, Nk.salt: 1.0});
    final mon = DateTime(2026, 11, 9), tue = DateTime(2026, 11, 10), wed = DateTime(2026, 11, 11);

    test('μία μέρα', () {
      final d1 = CholDay([_le(mon, a, 400)]);
      expect(d1.kcal, closeTo(1000, 1e-9));
      expect(d1.satFat, closeTo(20, 1e-9));
      expect(d1.satPct, closeTo(18.0, 1e-9)); // 20 × 9 / 1000 × 100
      expect(d1.fiber, closeTo(16, 1e-9));
      expect(d1.salt, closeTo(4.8, 1e-9));
      final d2 = CholDay([_le(tue, b, 600)]);
      expect(d2.kcal, closeTo(1200, 1e-9));
      expect(d2.satPct, closeTo(9.0, 1e-9)); // 12 × 9 / 1200 × 100
      expect(d2.fiber, closeTo(18, 1e-9));
      expect(d2.salt, closeTo(6.0, 1e-9));
      final thin = CholDay([_le(wed, a, 100)]);
      expect(thin.satPct, closeTo(18.0, 1e-9));
      expect(thin.fullFor(1500), isFalse, reason: '250 < 900 kcal (60% του 1.500)');
      expect(CholDay(const []).satPct, isNull);
    });

    test('εβδομάδα: μόνο οι μέρες με πλήρη καταγραφή', () {
      final w = CholWeek([
        (mon, CholDay([_le(mon, a, 400)])),
        (tue, CholDay([_le(tue, b, 600)])),
        (wed, CholDay([_le(wed, a, 100)])),
      ], goalKcal: 1500);
      expect(w.fullDays, 2);
      expect(w.satPctMean, closeTo(13.5, 1e-9));
      expect(w.fiberMean, closeTo(17.0, 1e-9));
      expect(w.daysSaltOk(5), 1);
      expect(w.daysSaltUnknown, 0);
      expect((w.daysSatUnknown, w.daysFiberUnknown), (0, 0));
    });

    test('S2-2: τρόφιμο χωρίς τιμή κορεσμένων / ινών → η εβδομάδα το ξέρει («τουλάχιστον»)', () {
      final noSat = _f('C', {Nk.kcal: 300, Nk.fiber: 2, Nk.salt: 0.5});
      final noFiber = _f('D', {Nk.kcal: 300, Nk.satFat: 1, Nk.salt: 0.5});
      final w = CholWeek([
        (mon, CholDay([_le(mon, a, 400), _le(mon, noSat, 100)])), // 1.300 kcal, πλήρης
        (tue, CholDay([_le(tue, noFiber, 400)])), // 1.200 kcal, πλήρης
        (wed, CholDay([_le(wed, noSat, 50)])), // 150 kcal, όχι πλήρης: δεν μετρά
      ], goalKcal: 1500);
      expect(w.fullDays, 2);
      expect(w.daysSatUnknown, 1);
      expect(w.daysFiberUnknown, 1);
      // Δευτέρα 20 g κορεσμένα στις 1.300 kcal (το C μετρά 0): 13,846…%· Τρίτη 4 g στις 1.200: 3%.
      expect(w.satPctMean, closeTo((20 * 9 / 1300 * 100 + 4 * 9 / 1200 * 100) / 2, 1e-9));
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('S12-08 (Τ8): σύνολα φαγητού με αριθμούς από το χέρι', () {
    test('κάθε θρεπτικό', () {
      final f = _f('F', {
        Nk.kcal: 125, Nk.protein: 10, Nk.carbs: 20, Nk.sugars: 5, Nk.fiber: 4, Nk.fat: 8, Nk.satFat: 3, Nk.salt: 1.2,
        Nk.alcohol: 2,
      });
      final d = DateTime(2026, 11, 9);
      final t = Totals([_le(d, f, 10), _le(d, f, 10), _le(d, f, 10), _le(d, f, 150)]);
      expect(t.kcal, closeTo(225.0, 1e-9));
      expect(t.protein, closeTo(18.0, 1e-9));
      expect(t.carbs, closeTo(36.0, 1e-9));
      expect(t.sugars, closeTo(9.0, 1e-9));
      expect(t.fiber, closeTo(7.2, 1e-9));
      expect(t.fat, closeTo(14.4, 1e-9));
      expect(t.satFat, closeTo(5.4, 1e-9));
      expect(t.salt, closeTo(2.16, 1e-9));
      expect(t.alcohol, closeTo(3.6, 1e-9));
      expect(t.count, 4);
      expect(t.shownKcal, 227, reason: '13 + 13 + 13 + 188 (το 12,5 γίνεται 13)');
      expect(t.missing, isEmpty);
    });

    test('τιμές που λείπουν, «<» και «ίχνη»', () {
      final d = DateTime(2026, 11, 9);
      final g = _f('G', {Nk.kcal: 100, Nk.protein: 1, Nk.carbs: 1, Nk.fat: 1});
      expect(Totals([_le(d, g, 100)]).missing, {Nk.fiber: 1, Nk.sugars: 1, Nk.salt: 1, Nk.satFat: 1});
      final lt = Food(
          id: 'H', name: 'Τρόφιμο H', cat: 'Άλλα', source: 'CIQUAL 2025',
          n: Nutrients({Nk.kcal: const NValue(100), Nk.satFat: const NValue(0.5, lessThan: true)}));
      final tr = Food(
          id: 'J', name: 'Τρόφιμο J', cat: 'Άλλα', source: 'CIQUAL 2025',
          n: Nutrients({Nk.kcal: const NValue(100), Nk.satFat: const NValue(0, traces: true)}));
      final t = Totals([_le(d, lt, 100), _le(d, tr, 100)]);
      expect(t.satFat, 0);
      expect(t.missing.containsKey(Nk.satFat), isFalse);
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('S12-12 (Τ10) / S2-3: τι μετρά στην κάρτα «Χοληστερίνη»', () {
    final d = DateTime(2026, 11, 10);
    final salmon = foodNamed('Σολομός (σχάρα ή τηγάνι χωρίς λάδι)');
    final octopus = foodNamed('Χταπόδι (μαγειρεμένο)');
    final chickpeas = foodNamed('Ρεβίθια κονσέρβα (στραγγισμένα)');
    final lentilsDry = foodNamed('Φακές (ξερές)');

    test('ψάρι: 100 g η «φορά», και τα θαλασσινά', () {
      expect(CholDay([_le(d, salmon, 99)]).fish, isFalse);
      expect(CholDay([_le(d, salmon, 100)]).fish, isTrue);
      expect(CholDay([_le(d, octopus, 100)]).fish, isTrue);
      expect(CholDay([_le(d, salmon, 60), _le(d, octopus, 40)]).fish, isTrue);
    });

    test('όσπρια: κονσέρβα ÷ 2,5 (από το όνομα), ξερά όπως είναι, 40 g', () {
      expect(CholDay([_le(d, chickpeas, 100)]).legumesDryG, closeTo(40, 1e-9));
      expect(CholDay([_le(d, chickpeas, 100)]).legumes, isTrue);
      expect(CholDay([_le(d, chickpeas, 99)]).legumes, isFalse);
      expect(CholDay([_le(d, lentilsDry, 39)]).legumes, isFalse);
      expect(CholDay([_le(d, lentilsDry, 40)]).legumes, isTrue);
    });

    test('πίτουρο από δικό σου προϊόν με το όνομα, και με κεφαλαία (τελικό «Σ»)', () {
      for (final name in ['ΠΙΤΟΥΡΟ ΒΡΏΜΗΣ βιολογικό', 'ΠΙΤΟΥΡΟ ΒΡΩΜΗΣ', 'Πίτουρο βρώμης (μάρκα)']) {
        final day = CholDay([_le(d, _mine('M9', name, {Nk.kcal: 370}), 45)]);
        expect((day.branG, day.nutsG), (45.0, 0.0), reason: name);
      }
      expect(CholDay([_le(d, _mine('M9', 'Νιφάδες βρώμης', {Nk.kcal: 370}), 45)]).branG, 0);
    });

    test('S2-3: ξηροί καρποί = καρποί δέντρων και αράπικα φιστίκια, όχι σπόροι', () {
      for (final f in basicFoods().where(isNuts)) {
        expect(f.sourceName!.toLowerCase(), isNot(contains('seed')), reason: '${f.id} ${f.name}');
      }
      expect(isNuts(_byId('C15025')), isTrue, reason: 'κουκουνάρι');
      for (final id in ['C15011', 'C15045', 'U170557', 'U169415', 'C15010']) {
        expect(isNuts(_byId(id)), isFalse, reason: id);
      }
      expect(CholDay([_le(d, _byId('U170557'), 30)]).nutsG, 0, reason: 'πασατέμπος');
      expect(CholDay([_le(d, _byId('C15010'), 30)]).nutsG, 0, reason: 'σουσάμι');
      expect(CholDay([_le(d, _byId('C15025'), 30)]).nutsG, 30, reason: 'κουκουνάρι');
      // Παλιές καταχωρίσεις κρατούν την κατηγορία της #100 στο αντίγραφό τους: μετρούν με τον νέο κανόνα.
      Food withCat(Food f, String cat) => Food.fromJson({...f.toJson(), 'cat': cat});
      expect(isNuts(withCat(_byId('C15011'), 'Ξηροί καρποί')), isFalse);
      expect(isNuts(withCat(_byId('C15025'), 'Σπόροι')), isTrue);
    });

    test('ξηροί καρποί: ο στόχος 30 g πιάνεται από 30 g, όχι από 29,9', () {
      final walnuts = foodNamed('Καρύδια');
      final filler = _f('F', {Nk.kcal: 1000, Nk.satFat: 1, Nk.fiber: 1, Nk.salt: 0.1});
      final mon = DateTime(2026, 11, 9), tue = DateTime(2026, 11, 10);
      final w = CholWeek([
        (mon, CholDay([_le(mon, walnuts, 29.9), _le(mon, filler, 100)])),
        (tue, CholDay([_le(tue, walnuts, 30), _le(tue, filler, 100)])),
      ], goalKcal: 1500);
      expect(w.fullDays, 2);
      expect(w.daysWithNuts(30), 1);
      expect(w.daysWithNuts(0), 0);
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('S11-3: ποσότητα που μοιάζει με λάθος πληκτρολόγησης', () {
    final oil = foodNamed('Ελαιόλαδο εξαιρετικά παρθένο'); // 899 kcal, 99,9 g λιπαρά ανά 100 g

    test('τα όρια', () {
      final z = _f('Z', {Nk.kcal: 400});
      expect(entryLooksLikeTypo(z, 499), isFalse); // 1.996 kcal
      expect(entryLooksLikeTypo(z, 500), isTrue); // 2.000 kcal
      final y = _f('Y', {Nk.kcal: 50});
      expect(entryLooksLikeTypo(y, 1000), isFalse); // 500 kcal
      expect(entryLooksLikeTypo(y, 1002), isTrue); // 501 kcal, 1 κιλό και πάνω
      expect(entryLooksLikeTypo(y, 999), isFalse);
      final melon = _f('W', {Nk.kcal: 30});
      expect(entryLooksLikeTypo(melon, 1500), isFalse, reason: '450 kcal: καρπούζι με το κιλό είναι κανονικό');
      final butter = _f('B', {Nk.kcal: 717, Nk.fat: 81});
      expect(entryLooksLikeTypo(butter, 99), isFalse);
      expect(entryLooksLikeTypo(butter, 100), isTrue);
      expect(entryLooksLikeTypo(_f('C', {Nk.kcal: 700, Nk.fat: 79.9}), 100), isFalse);
      expect(entryLooksLikeTypo(oil, 20), isFalse);
      expect(entryLooksLikeTypo(oil, 100), isTrue);
      expect(entryLooksLikeTypo(oil, 2000), isTrue);
      expect(typoQuestion(oil, 2000),
          '2.000 g «Ελαιόλαδο εξαιρετικά παρθένο» = 17.980 kcal σε μία καταχώριση. Είναι σωστό;');
    });

    Future<(Object?, bool) Function()> sheet(WidgetTester t, Food item, double grams, {bool editing = false}) async {
      Object? result;
      var closed = false;
      final store = FoodStore.preloaded(foods: basicFoods(), now: _now);
      await _pumpHost(t, (ctx) async {
        result = await showModalBottomSheet<Object?>(
          context: ctx,
          isScrollControlled: true,
          builder: (_) => QuantitySheet(food: store, item: item, initialGrams: grams, meal: Meal.lunch, editing: editing),
        );
        closed = true;
      });
      await t.tap(find.text('άνοιξε'));
      await t.pumpAndSettle();
      return () => (result, closed);
    }

    Future<void> submit(WidgetTester t, String label) async {
      final b = find.text(label);
      await t.ensureVisible(b);
      await t.tap(b);
      await t.pumpAndSettle();
    }

    testWidgets('2.000 g λάδι: ΜΙΑ ερώτηση με τις θερμίδες· «Όχι» μένει για διόρθωση, «Ναι» γράφει', (t) async {
      final state = await sheet(t, oil, 20);
      await t.enterText(find.byType(TextField), '2000');
      await t.pumpAndSettle();
      await submit(t, 'Προσθήκη στο Μεσημέρι');
      expect(find.text('Σωστή ποσότητα;'), findsOneWidget);
      expect(find.text('2.000 g «Ελαιόλαδο εξαιρετικά παρθένο» = 17.980 kcal σε μία καταχώριση. Είναι σωστό;'), findsOneWidget);
      await t.tap(find.text('Όχι, θα τη διορθώσω'));
      await t.pumpAndSettle();
      expect(state().$2, isFalse);
      expect(find.byType(QuantitySheet), findsOneWidget);

      await submit(t, 'Προσθήκη στο Μεσημέρι');
      await t.tap(find.text('Ναι, σωστό'));
      await t.pumpAndSettle();
      expect(state().$2, isTrue);
      expect(state().$1, isNotNull, reason: 'γράφεται όπως είναι');
    });

    testWidgets('κανονική ποσότητα: καμία ερώτηση', (t) async {
      final state = await sheet(t, oil, 20);
      await submit(t, 'Προσθήκη στο Μεσημέρι');
      expect(find.text('Σωστή ποσότητα;'), findsNothing);
      expect(state().$2, isTrue);
    });

    testWidgets('παλιά καταχώριση που δεν άλλαξε ποσότητα: δεν ξαναρωτά', (t) async {
      final state = await sheet(t, oil, 2000, editing: true);
      await submit(t, 'Αποθήκευση');
      expect(find.text('Σωστή ποσότητα;'), findsNothing);
      expect(state().$2, isTrue);
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('S2-4: «Αποθηκεύτηκε» μόνο όταν αποθηκεύτηκε', () {
    void failingDb() => _mockFood((call) async => switch (call.method) {
          'myFoodPut' => jsonEncode({'ok': false, 'kind': 'other', 'message': 'γεμάτος χώρος'}),
          _ => jsonEncode({'ok': true}),
        });

    testWidgets('νέο προϊόν που δεν γράφτηκε: μήνυμα, κανένα αποτέλεσμα, τίποτα στα προϊόντα μου', (t) async {
      failingDb();
      final s = FoodStore();
      addTearDown(s.dispose);
      Food? created;
      var returned = false;
      await _pumpHost(t, (ctx) async {
        created = await createFood(ctx, s,
            draft: FoodDraft(name: 'Κράκερ', values: {Nk.kcal: 450, Nk.protein: 8, Nk.carbs: 60, Nk.fat: 18}));
        returned = true;
      });
      await t.tap(find.text('άνοιξε'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Αποθήκευση'));
      await t.tap(find.text('Αποθήκευση'));
      await t.pumpAndSettle();
      expect(returned, isTrue);
      expect(created, isNull);
      expect(find.text(productNotSavedText('Κράκερ')), findsOneWidget);
      expect(find.text('Δεν αποθηκεύτηκε: Κράκερ. Δοκίμασε ξανά.'), findsOneWidget);
      expect(s.mine, isEmpty);
    });

    testWidgets('διόρθωση που δεν γράφτηκε: μήνυμα και null (όχι «Αποθηκεύτηκε»)', (t) async {
      failingDb();
      final s = FoodStore();
      addTearDown(s.dispose);
      final f = _mine('M1', 'Κράκερ', {Nk.kcal: 450, Nk.protein: 8, Nk.carbs: 60, Nk.fat: 18});
      Food? edited = f;
      await _pumpHost(t, (ctx) async {
        edited = await editMyFood(ctx, s, f);
      });
      await t.tap(find.text('άνοιξε'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Αποθήκευση'));
      await t.tap(find.text('Αποθήκευση'));
      await t.pumpAndSettle();
      expect(edited, isNull);
      expect(find.text('Δεν αποθηκεύτηκε: Κράκερ. Δοκίμασε ξανά.'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('S2-6: «Πηγές και άδειες» λέει μόνο ό,τι είναι στη βάση', () {
    test('Foundation Foods μόνο αν υπάρχει τρόφιμο Foundation', () {
      final used = basicFoods().map((f) => f.source).toSet();
      expect(usdaInfo.version.contains('Foundation'), used.contains('USDA Foundation'));
      expect(usdaInfo.version, 'SR Legacy (2018)');
      expect(identical(sourceInfo('USDA SR Legacy'), usdaInfo), isTrue);
      expect(identical(sourceInfo('USDA Foundation'), usdaFoundationInfo), isTrue);
      expect(usdaFoundationInfo.version, contains('Foundation'));
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('S2-7 / U3a-10: αναζήτηση', () {
    final index = FoodIndex(basicFoods());

    test('επίθετο πριν από το τρόφιμο: κρατιέται το τρόφιμο', () {
      final r = index.find('μαύρο ρύζι');
      expect(r.foods.first.name, startsWith('Ρύζι'));
      expect(r.ignored, ['μαύρο']);
      final f = index.find('κόκκινες φακές');
      expect(f.foods.first.id, 'C20359');
      expect(f.ignored, ['κόκκινες']);
      expect(index.find('μαύρα μακαρόνια').foods.first.id, 'C9870');
    });

    test('άγνωστο τρόφιμο + τρόπος μαγειρέματος: «δεν βρέθηκε», όχι όλα τα ψητά', () {
      expect(index.find('λακέρδα ψητή').foods, isEmpty);
      // Υπάρχοντα τρόφιμα με τρόπο μαγειρέματος βρίσκονται όπως πριν.
      expect(index.find('βραστό χταπόδι').foods.first.id, 'C10079');
    });

    test('νέα τρόφιμα: ρέγγα (καπνιστή πρώτη στο «ψητή»), καστανό ρύζι parboiled', () {
      expect(index.find('ρέγγα').foods.map((f) => f.id).take(3), ['C26011', 'C26014', 'C25998']);
      expect(index.find('ρέγγα ψητή').foods.map((f) => f.id).take(2), ['C25998', 'C26014']);
      expect(_byId('U168876').cooked.map((c) => c.$1), ['U173263']);
    });

    test('U3a-10: το δικό μου προϊόν που ταιριάζει με το όνομά του βγαίνει ΠΡΩΤΟ', () {
      final s = sampleFoodStore(_now);
      expect(s.find('γιαούρτι').foods.first.id, 'Mdemo1', reason: 'πριν: 7ο, κάτω από πέντε γενικά');
      expect(s.find('γιαουρτι').foods.first.id, 'Mdemo1');
      expect(s.find('ανθότυρο').foods.first.id, 'Mdemo2');
      // Ό,τι δεν ταιριάζει με το όνομά του δεν ανεβαίνει.
      expect(s.find('φακές').foods.first.isMine, isFalse);
      expect(s.find('μέλι').foods.first.isMine, isFalse);
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  group('Οθόνες (U3a)', () {
    testWidgets('U3a-4: με 1,3× και 2,0× γράμματα το κουτί αναζήτησης χωρά ολόκληρο', (t) async {
      for (final scale in [1.0, 1.3, 2.0]) {
        await _pump(t, AddFoodScreen(food: sampleFoodStore(_now), meal: Meal.snack, day: _today),
            size: const Size(400, 1600), textScale: scale);
        expect(t.takeException(), isNull);
        final field = t.getRect(find.byType(TextField));
        final picker = t.getRect(find.byType(MealPicker));
        expect(field.top, greaterThanOrEqualTo(2), reason: '$scale×');
        expect(field.bottom + 2, lessThanOrEqualTo(picker.top), reason: '$scale×');
      }
    });

    testWidgets('U3a-5: «Σάρωση» / «Από ετικέτα» ολόκληρα· στα 360 με 2,0× το ένα κάτω από το άλλο', (t) async {
      await _pump(t, AddFoodScreen(food: sampleFoodStore(_now), meal: Meal.snack, day: _today),
          size: const Size(360, 1600), textScale: 2.0);
      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('add-tools-stacked')), findsOneWidget);
      expect(t.widget<Text>(find.text('Από ετικέτα')).maxLines, isNull, reason: 'χωρίς «…»');
      await _pump(t, AddFoodScreen(food: sampleFoodStore(_now), meal: Meal.snack, day: _today), size: const Size(400, 1600));
      expect(find.byKey(const ValueKey('add-tools-stacked')), findsNothing);
      // U3a-18: ίδιο εικονίδιο με το «Τα προϊόντα μου».
      expect(find.descendant(of: find.byKey(const ValueKey('add-label')), matching: find.byIcon(Icons.edit_note_rounded)),
          findsOneWidget);
    });

    test('U3a-6: ο αριθμός δεν χωρίζεται από τη λέξη του', () {
      final f = _f('S', {Nk.kcal: 125, Nk.protein: 10.1});
      expect(foodTileSubtitle(f, 6), '125 kcal · πρωτεΐνη 10,1 g ανά 100 g · 6 φορές');
      expect(foodTileSubtitle(f, 1), '125 kcal · πρωτεΐνη 10,1 g ανά 100 g · 1 φορά');
      expect(foodTileSubtitle(f, 0), '125 kcal · πρωτεΐνη 10,1 g ανά 100 g');
    });

    testWidgets('U3a-7: στενή κάρτα (κάτω από 300 dp): μία γραμμή ανά μακροθρεπτικό', (t) async {
      final totals = Totals([_le(_today, foodNamed('Φακές (βρασμένες)'), 300)]);
      await _pump(t, Scaffold(body: Center(child: SizedBox(width: 280, child: MacroBreakdown(totals: totals)))));
      expect(find.byKey(const ValueKey('macro-rows')), findsOneWidget);
      expect(find.text('Υδατάνθρακες'), findsOneWidget);
      await _pump(t, Scaffold(body: Center(child: SizedBox(width: 380, child: MacroBreakdown(totals: totals)))));
      expect(find.byKey(const ValueKey('macro-rows')), findsNothing);
      expect(find.text('Υδατάνθρ.'), findsOneWidget);
    });

    testWidgets('U3a-8: τα τέσσερα γεύματα έχουν ΠΑΝΤΑ το ίδιο μέγεθος γραμμάτων', (t) async {
      for (final (scale, width) in [(1.0, 400.0), (1.3, 360.0), (2.0, 360.0)]) {
        await _pump(t, AddFoodScreen(food: sampleFoodStore(_now), meal: Meal.snack, day: _today),
            size: Size(width, 1600), textScale: scale);
        final sizes = {
          for (final m in Meal.values)
            t.widget<Text>(find.descendant(of: find.byType(MealPicker), matching: find.text(mealLabel(m)))).style!.fontSize,
        };
        expect(sizes.length, 1, reason: '$scale× στα $width: $sizes');
        if (scale == 1.0) expect(sizes.single, 14);
      }
    });

    testWidgets('U3a-8: με μεγάλα γράμματα οι ποσότητες σε 2 × 2', (t) async {
      final store = FoodStore.preloaded(foods: basicFoods(), now: _now);
      await _pump(t, Scaffold(body: QuantitySheet(food: store, item: foodNamed('Φακές (βρασμένες)'), initialGrams: 200, meal: Meal.lunch)),
          size: const Size(400, 1800), textScale: 1.3);
      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('qty-chips-grid')), findsOneWidget);
    });

    testWidgets('U3a-12: πάνω από 5.000 λέει το όριο· το πρώτο άγγιγμα διαλέγει όλο τον αριθμό', (t) async {
      expect(quantityErrorText('6000', perMl: false), 'Ως 5.000 g τη φορά');
      expect(quantityErrorText('6.000', perMl: true), 'Ως 5.000 ml τη φορά');
      expect(quantityErrorText('', perMl: false), 'Γράψε γραμμάρια');
      expect(quantityErrorText('0', perMl: true), 'Γράψε ml');

      final store = FoodStore.preloaded(foods: basicFoods(), now: _now);
      await _pump(t, Scaffold(body: QuantitySheet(food: store, item: foodNamed('Φακές (βρασμένες)'), initialGrams: 300, meal: Meal.lunch)));
      final field = find.byType(TextField);
      await t.tap(field);
      await t.pump(const Duration(milliseconds: 500));
      final c = t.widget<TextField>(field).controller!;
      expect(c.text, '300');
      expect(c.selection, const TextSelection(baseOffset: 0, extentOffset: 3));

      await t.enterText(field, '6000');
      await t.pumpAndSettle();
      expect(find.text('Ως 5.000 g τη φορά'), findsOneWidget);
      final button = find.ancestor(of: find.text('Προσθήκη στο Μεσημέρι'), matching: find.byType(FilledButton));
      expect(t.widget<FilledButton>(button).onPressed, isNull);
    });

    testWidgets('U3a-13: λάδι και βούτυρο με το κουταλάκι· ποτήρι και κουτάκι μόνο στα άλλα υγρά', (t) async {
      final store = FoodStore.preloaded(foods: basicFoods(), now: _now);
      final oilMl = _f('O', {Nk.kcal: 824, Nk.fat: 91.6}, name: 'Ελαιόλαδο (μάρκα)', perMl: true);
      await _pump(t, Scaffold(body: QuantitySheet(food: store, item: oilMl, initialGrams: 15, meal: Meal.lunch)));
      for (final v in ['5 ml', '10 ml', '15 ml', '30 ml']) {
        expect(find.text(v), findsOneWidget, reason: v);
      }
      expect(find.text('330 ml'), findsNothing);
      final milk = _f('L', {Nk.kcal: 46, Nk.fat: 1.5}, name: 'Γάλα (μάρκα)', perMl: true);
      await _pump(t, Scaffold(body: QuantitySheet(food: store, item: milk, initialGrams: 250, meal: Meal.lunch)));
      expect(find.text('330 ml'), findsOneWidget);
      final butter = _f('V', {Nk.kcal: 717, Nk.fat: 81}, name: 'Βούτυρο (μάρκα)');
      await _pump(t, Scaffold(body: QuantitySheet(food: store, item: butter, initialGrams: 10, meal: Meal.lunch)));
      expect(find.text('5 g'), findsOneWidget);
      expect(find.text('200 g'), findsNothing);
    });

    test('U3a-14: «5 g», όχι «5,0 g»', () {
      expect(gramsText(5), '5');
      expect(gramsText(0), '0');
      expect(gramsText(1.26), '1,3');
      expect(gramsText(9.94), '9,9');
      expect(gramsText(9.96), '10');
      expect(gramsText(12.4), '12');
      expect(gramsText(150.6), '151');
    });

    testWidgets('U3a-18: ίδια λόγια για την ίδια ενέργεια', (t) async {
      await _pump(t, AddFoodScreen(food: sampleFoodStore(_now), meal: Meal.snack, day: _today));
      await t.enterText(find.byType(TextField), 'λακέρδα'); // δεν υπάρχει στη βάση
      await t.pumpAndSettle();
      expect(find.textContaining('Αν είναι συσκευασμένο, πάτα «Σάρωση» ή «Από ετικέτα».'), findsOneWidget);
      expect(find.textContaining('σκάναρε το barcode'), findsNothing);

      await _pump(t, MyFoodsScreen(food: sampleFoodStore(_now)));
      expect(find.textContaining('73 kcal ανά 100 g'), findsOneWidget);
      expect(find.textContaining('kcal/100'), findsNothing);

      await _pump(t, MePage(store: HealthStore(), food: FoodStore.preloaded(foods: basicFoods(), now: _now)),
          size: const Size(400, 3000));
      expect(find.text('Πέρασε ό,τι αγοράζεις, με «Σάρωση» ή από την ετικέτα, χωρίς να το καταγράψεις ως φαγητό.'), findsOneWidget);
      expect(find.text('Θερμίδες, πρωτεΐνη, χοληστερίνη · 2 λεπτά'), findsOneWidget, reason: 'U3a-6');
    });

    testWidgets('S2-10 / U3a-19: η κουζίνα κρατά τον αριθμό και όταν βγαίνεις με το «πίσω»', (t) async {
      _messenger.setMockMethodCallHandler(_samsung, (call) async {
        if (call.method == 'loadPrefs') {
          return jsonEncode({
            'kitchen': {'seed': 2, 'devices': ['scale'], 'cookware': <Object>[]},
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
      final field = find.widgetWithText(TextFormField, 'Μέγιστο βάρος');
      await t.ensureVisible(field);
      await t.enterText(field, '5,5');
      await t.pump();
      // «Πίσω» του κινητού: κανένα «Τέλος», κανένα άγγιγμα έξω από το πεδίο.
      await t.state<NavigatorState>(find.byType(Navigator)).maybePop();
      await t.pumpAndSettle();
      expect(find.byType(KitchenScreen), findsNothing);
      expect(Kitchen.fromJson(store.prefs.kitchen).scaleMaxKg, 5.5);
    });
  });
}
