// Round9 (f1, φαγητό): R9-A2-1/A2-2/A2-3, R9-A3-1…A3-4, R9-U2-1…U2-6, R9-A1-4 (= U2-5), R9-A12-5 (δοκιμές για τις
// διορθώσεις του γύρου 8). Όλες οι αναμενόμενες τιμές βγήκαν με το χέρι (python) από τον γραμμένο κανόνα και τις τιμές
// της βάσης, όχι από τον κώδικα. Τα δικά μου προϊόντα, τα barcode και οι στόχοι είναι φανταστικά (δημόσιο repo).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/food/chol.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/food/off.dart';
import 'package:ygeia_forma/goals.dart';
import 'package:ygeia_forma/history.dart' show dateKey;
import 'package:ygeia_forma/pages/food_add.dart';
import 'package:ygeia_forma/pages/goals_page.dart';
import 'package:ygeia_forma/pages/nutrition.dart';
import 'package:ygeia_forma/pages/nutrition_goals.dart';
import 'package:ygeia_forma/profile.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/widgets.dart' show PageHeaderScope;

import 'sample_food.dart';

/// Παρασκευή 13/11/2026, μεσημέρι.
final _now = DateTime(2026, 11, 13, 12);
final _today = DateTime(2026, 11, 13);

const _foodChannel = MethodChannel('ygeia/food');
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
Future<void> _pumpHost(WidgetTester t, Future<void> Function(BuildContext ctx) onOpen) => _pump(
      t,
      Scaffold(
        body: Builder(
          builder: (ctx) => Center(child: TextButton(onPressed: () => onOpen(ctx), child: const Text('άνοιξε'))),
        ),
      ),
    );

/// Φανταστικό τρόφιμο με τιμές ανά 100 g.
Food _f(String id, Map<String, double> n, {String? name, String cat = 'Άλλα'}) => Food(
      id: id,
      name: name ?? 'Τρόφιμο $id',
      cat: cat,
      source: 'CIQUAL 2025',
      n: Nutrients({for (final e in n.entries) e.key: NValue(e.value)}),
    );

/// Δικό μου προϊόν (από ετικέτα).
Food _mine(String id, String name, Map<String, double> n, {double? serving, bool spoon = false, bool perMl = false}) => Food(
      id: id,
      name: name,
      cat: myFoodsCategory,
      source: 'Ετικέτα',
      servingGrams: serving,
      spoon: spoon,
      perMl: perMl,
      n: Nutrients({for (final e in n.entries) e.key: NValue(e.value)}),
    );

var _seq = 0;
LogEntry _le(DateTime d, Food f, double grams, {int hour = 13, Meal meal = Meal.lunch}) => LogEntry(
      id: 'r9f1-${_seq++}',
      day: dateKey(d),
      meal: meal,
      food: f,
      grams: grams,
      time: DateTime(d.year, d.month, d.day, hour),
    );

Food _byId(String id) => basicFoods().firstWhere((f) => f.id == id);

/// Φανταστικός χρήστης· [kcal]: ο δικός του στόχος θερμίδων· [doctor]: οδηγία γιατρού για την LDL.
Goals _goals({int kcal = 2090, bool doctor = true, String since = '2026-11-12', int branG = defaultBranG}) => Goals(
      aim: GoalAim.lose,
      rate: 0.005,
      activity: 1.5,
      doctor: doctor,
      since: since,
      kg: 90,
      age: 40,
      heightCm: 180,
      male: true,
      kcalSet: kcal,
      branG: branG,
    );

const _me = Profile(birthYear: 1985, birthMonth: 12, sex: 'm', heightCm: 180);

Finder _inSheet(Finder f) => find.descendant(of: find.byType(QuantitySheet), matching: f);

/// Κουμπί ποσότητας («30 g») στο φύλλο: όχι οι τιμές των θρεπτικών.
Finder _chip(String text) => find.descendant(of: _inSheet(find.byType(OutlinedButton)), matching: find.text(text));

String _sheetGrams(WidgetTester t) => t.widget<TextField>(_inSheet(find.byType(TextField))).controller!.text;

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

/// Η μπάρα «Κορεσμένα λιπαρά» της σύνοψης για μια μέρα με ένα φανταστικό τρόφιμο 100 g.
Future<void> _summary(WidgetTester t, Goals g, {required double kcal, required double sat, bool today = true, DateTime? day}) =>
    _pump(
        t,
        Scaffold(
            body: SingleChildScrollView(
                child: GoalsSummaryCard(
                    key: ValueKey('$kcal $sat $today ${g.kcal}'),
                    totals: Totals([
                      _le(day ?? _today,
                          _f('S', {Nk.kcal: kcal, Nk.satFat: sat, Nk.protein: 70, Nk.carbs: 150, Nk.fat: 40, Nk.fiber: 20, Nk.sugars: 30, Nk.salt: 4}),
                          100),
                    ]),
                    goals: g,
                    today: today,
                    day: day,
                    health: HealthStore()))));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
  });

  // ---------------------------------------------------------------------------------------------------------------- A2-1
  group('R9-A2-1: τα σάκχαρα δεν είναι ποτέ περισσότερα από τους υδατάνθρακες', () {
    test('κάθε τρόφιμο της βάσης (όπου η πηγή δίνει αριθμούς): σάκχαρα ≤ υδατάνθρακες, κορεσμένα ≤ λιπαρά', () {
      for (final f in basicFoods()) {
        for (final (part, whole) in const [(Nk.sugars, Nk.carbs), (Nk.satFat, Nk.fat)]) {
          final p = f.n[part], w = f.n[whole];
          if (p == null || w == null || w.traces || w.lessThan) continue;
          expect(p.amount, lessThanOrEqualTo(w.amount + 0.05), reason: '${f.id} ${f.name}: $part ${p.amount} > $whole ${w.amount}');
        }
      }
    });
    test('πεπόνι κανταλούπ (USDA SR 169092): υδατάνθρακες = σάκχαρα 7,86 g (το «1005 − ίνες» 7,26 ήταν κάτω από τα σάκχαρα)', () {
      final melon = _byId('U169092');
      expect(melon.n.amount(Nk.sugars), 7.86);
      expect(melon.n.amount(Nk.carbs), 7.86);
      expect(melon.n.amount(Nk.kcal), 34, reason: 'οι θερμίδες της πηγής δεν αλλάζουν');
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- A2-2
  group('R9-A2-2: σαρωμένο ταχίνι/φυστικοβούτυρο/μαργαρίνη μετριούνται με το κουτάλι, όπως στη βάση', () {
    // Φανταστικό ταχίνι με τιμές σαν της ετικέτας, και «μερίδα» 100 g όπως τη δίνει συχνά το Open Food Facts.
    final tahini = _mine('M1', 'Ταχίνι Χ', {Nk.kcal: 673, Nk.fat: 60.3, Nk.protein: 25.3, Nk.carbs: 3.6}, serving: 100, spoon: true);

    test('κανόνας: κουτάλι, πρώτη ποσότητα 15 g, η «μερίδα» των 100 g δεν γίνεται πρώτη ποσότητα, 100 g ρωτούν', () {
      expect(isSpoonFood(tahini), isTrue);
      expect(firstGrams(tahini), 15);
      expect(startServing(tahini), isNull);
      expect(entryLooksLikeTypo(tahini, 100), isTrue, reason: '100 g = 673 kcal: ρωτά');
      expect(entryLooksLikeTypo(tahini, 15), isFalse);
      // Χωρίς τη σήμανση (προϊόν από παλιότερη έκδοση): όπως πριν.
      final old = _mine('M1', 'Ταχίνι Χ', {Nk.kcal: 673, Nk.fat: 60.3, Nk.protein: 25.3, Nk.carbs: 3.6}, serving: 100);
      expect(isSpoonFood(old), isFalse);
      expect(startServing(old), 100);
      // Μερίδα κάτω από 100 g μένει πρώτη ποσότητα· σχεδόν καθαρό λίπος μένει στα 10 g.
      expect(startServing(_mine('M3', 'Ταχίνι Ψ', {Nk.kcal: 640, Nk.fat: 55}, serving: 15, spoon: true)), 15);
      expect(firstGrams(_mine('M4', 'Λάδι Χ', {Nk.kcal: 900, Nk.fat: 100}, spoon: true)), 10);
    });

    test('JSON: «sp» γράφεται μόνο όταν ισχύει, οι παλιές εγγραφές χωρίς αυτό διαβάζονται όπως πριν, και περνά στην καταχώριση', () {
      final j = tahini.toJson();
      expect(j['sp'], isTrue);
      final back = Food.fromJson(jsonDecode(jsonEncode(j)) as Map<String, dynamic>);
      expect(back.spoon, isTrue);
      final plainJ = Map<String, dynamic>.from(j)..remove('sp');
      expect(Food.fromJson(plainJ).spoon, isFalse);
      expect(_mine('M5', 'Γιαούρτι Χ', {Nk.kcal: 95}).toJson().containsKey('sp'), isFalse);
      final e = LogEntry.fromJson(jsonDecode(jsonEncode(_le(_today, tahini, 15).toJson())) as Map<String, dynamic>);
      expect(e.food.spoon, isTrue);
    });

    test('Open Food Facts: κατηγορίες λιπών πάντα, αλείμματα από 500 kcal· η φόρμα το κρατά', () {
      expect(spoonFromOffTags(['en:spreads', 'en:plant-based-spreads', 'en:oilseed-purees', 'en:tahini'], kcal: 673), isTrue);
      expect(spoonFromOffTags(['en:spreads', 'en:plant-based-spreads', 'en:oilseed-purees', 'en:legume-butters', 'en:peanut-butters'],
          kcal: 610), isTrue);
      expect(spoonFromOffTags(['en:spreads', 'en:sweet-spreads', 'en:hazelnut-spreads', 'en:cocoa-and-hazelnuts-spreads'], kcal: 540),
          isTrue);
      expect(spoonFromOffTags(['en:fats', 'en:spreads', 'en:spreadable-fats', 'en:margarines', 'en:light-margarines'], kcal: 350), isTrue,
          reason: 'μαργαρίνη light: όπως η κατηγορία «Λιπαρά» της βάσης');
      expect(spoonFromOffTags(['en:sauces', 'en:emulsified-sauces', 'en:mayonnaises', 'en:light-mayonnaises'], kcal: 300), isTrue);
      expect(spoonFromOffTags(['en:spreads', 'en:sweet-spreads', 'en:fruit-preserves', 'en:jams'], kcal: 250), isNull, reason: 'μαρμελάδα');
      expect(spoonFromOffTags(['en:spreads', 'en:salted-spreads', 'en:hummus'], kcal: 260), isNull, reason: 'χούμους');
      expect(spoonFromOffTags(['en:dairies', 'en:yogurts'], kcal: 95), isNull);
      expect(spoonFromOffTags(null, kcal: 673), isNull);

      final d = draftFromOff('2000000000017', {
        'product_name': 'Ταχίνι Χ',
        'serving_quantity': 100,
        'nutriments': {'energy-kcal_100g': 673, 'proteins_100g': 25.3, 'carbohydrates_100g': 3.6, 'fat_100g': 60.3},
        'categories_tags': ['en:plant-based-foods-and-beverages', 'en:spreads', 'en:plant-based-spreads', 'en:oilseed-purees', 'en:tahini'],
      });
      expect(d.spoon, isTrue);
      final f = foodFromDraft(d, 'M9');
      expect((f.spoon, isSpoonFood(f), startServing(f), firstGrams(f)), (true, true, null, 15.0));
      expect(draftFromFood(f).spoon, isTrue, reason: 'η διόρθωση κρατά τη σήμανση');
      expect(draftFromFood(_mine('M6', 'Ταχίνι Ψ', {Nk.kcal: 640})).spoon, isNull, reason: 'παλιό προϊόν: η φόρμα προτείνει από το όνομα');
    });

    test('όνομα: μόνο η πρώτη λέξη', () {
      expect(spoonByName('Ταχίνι ολικής Χ'), isTrue);
      expect(spoonByName('ΦΥΣΤΙΚΟΒΟΥΤΥΡΟ crunchy'), isTrue);
      expect(spoonByName('«Μαργαρίνη» Ψ'), isTrue);
      expect(spoonByName('Μαγιονέζα light'), isTrue);
      expect(spoonByName('Μπισκότα με ταχίνι'), isFalse);
      expect(spoonByName('Ταχινόπιτα'), isFalse);
      expect(spoonByName('Βουτυράκια Χ'), isFalse, reason: 'μπισκότα');
      expect(spoonByName('Βούτυρο αγελάδος'), isTrue);
      expect(spoonByName(''), isFalse);
    });

    testWidgets('«+ Φαγητό» › σαρωμένο ταχίνι: πεδίο «15», κουμπιά 5–30 g και «1 μερίδα (100 g)»· τα 100 g ρωτούν', (t) async {
      final store = FoodStore.preloaded(foods: basicFoods(), mine: [tahini], now: _now);
      await _pump(t, AddFoodScreen(food: store, meal: Meal.snack, day: _today));
      await t.tap(find.text('Ταχίνι Χ'));
      await t.pumpAndSettle();
      expect(_sheetGrams(t), '15');
      for (final v in ['5 g', '10 g', '15 g', '30 g']) {
        expect(_chip(v), findsOneWidget, reason: v);
      }
      expect(_chip('1 μερίδα (100 g)'), findsOneWidget);
      expect(_chip('200 g'), findsNothing);
      await _addFromSheet(t, 'Σνακ', grams: '100');
      expect(find.text('Σωστή ποσότητα;'), findsOneWidget);
      expect(store.entriesFor(_today), isEmpty);
    });

    testWidgets('φόρμα: «Μετριέται με το κουτάλι;» προτείνεται από το όνομα, αλλάζει, και αποθηκεύεται', (t) async {
      Food? saved;
      var draft = FoodDraft(name: 'Ταχίνι Χ', values: {Nk.kcal: 673, Nk.protein: 25.3, Nk.carbs: 3.6, Nk.fat: 60.3});
      await _pumpHost(t, (ctx) async {
        saved = await Navigator.of(ctx).push<Food>(MaterialPageRoute(builder: (_) => FoodFormScreen(draft: draft)));
      });
      Finder chip(String label) =>
          find.descendant(of: find.byKey(const ValueKey('spoon-kind')), matching: find.widgetWithText(ChoiceChip, label));
      Future<void> save() async {
        await t.ensureVisible(find.text('Αποθήκευση'));
        await t.tap(find.text('Αποθήκευση'));
        await t.pumpAndSettle();
      }

      await t.tap(find.text('άνοιξε'));
      await t.pumpAndSettle();
      expect(t.widget<ChoiceChip>(chip('Ναι')).selected, isTrue);
      await save();
      expect(saved?.spoon, isTrue);

      draft = FoodDraft(name: 'Γιαούρτι Χ', values: {Nk.kcal: 95, Nk.protein: 9, Nk.carbs: 4, Nk.fat: 5});
      await t.tap(find.text('άνοιξε'));
      await t.pumpAndSettle();
      expect(t.widget<ChoiceChip>(chip('Όχι')).selected, isTrue);
      await save();
      expect(saved?.spoon, isFalse);
      expect(saved?.toJson().containsKey('sp'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- A2-3
  group('R9-A2-3: δικό μου ξερό ζυμαρικό/ρύζι/όσπριο: «πριν ή μετά το μαγείρεμα;» με τη βρασμένη μορφή της βάσης', () {
    Food dry(String name, double kcal) => _mine('MD', name, {Nk.kcal: kcal, Nk.protein: 12, Nk.carbs: 65, Nk.fat: 2});

    test('ποια ξερή μορφή της βάσης αντιστοιχεί, από το όνομα', () {
      const cases = {
        'Σπαγγέτι ολικής άλεσης Νο 7': 'C9870',
        'Μακαρόνια Νο 10': 'C9810',
        'Πένες': 'C9810',
        'Κριθαράκι μέτριο': 'C9810-1',
        'Χυλοπίτες με αυγά': 'C9821',
        'Ρύζι καστανό parboiled': 'U168876',
        'Ρύζι Καρολίνα': 'C9100',
        'Ρύζι μπασμάτι': 'C9119',
        'Ρύζι ολικής άλεσης': 'C9102',
        'Ρύζι parboiled': 'C9101',
        'Φακές ψιλές': 'C20359',
        'ΡΕΒΥΘΙΑ ΧΟΝΔΡΑ': 'C20516',
        'Φασόλια μέτρια': 'C20501',
        'Γίγαντες Χ': 'U174252',
        'Φάβα Χ': 'C20515',
        'Μαυρομάτικα': 'U173758',
        'Κινόα λευκή': 'C9340',
        'Πλιγούρι χοντρό': 'C9690',
        'Κουσκούς': 'C9681',
        'Spaghetti n.5': 'C9810',
        'Penne integrali': 'C9870',
      };
      for (final e in cases.entries) {
        expect(dryStapleRawId(dry(e.key, 340)), e.value, reason: e.key);
        // Κάθε τέτοια μορφή υπάρχει στη βάση και έχει βρασμένη μορφή.
        expect(_byId(e.value).cooked, isNotEmpty, reason: e.value);
      }
      for (final name in ['Ρυζογκοφρέτες', 'Αλεύρι για όλες τις χρήσεις', 'Σοκολάτα γάλακτος', 'Macarons', 'Μπάρα δημητριακών με ρύζι']) {
        expect(dryStapleRawId(dry(name, 400)), isNull, reason: name);
      }
      expect(dryStapleRawId(dry('Φακές κονσέρβα', 90)), isNull, reason: 'μαγειρεμένο (κάτω από 300 kcal)');
      expect(dryStapleRawId(_mine('MR', 'Ρόφημα ρυζιού', {Nk.kcal: 300}, perMl: true)), isNull);
      expect(dryStapleRawId(_byId('C9810')), isNull, reason: 'τρόφιμο της βάσης: έχει ήδη τις μορφές του');
    });

    test('μορφές και ερώτηση: το ίδιο το προϊόν ως ξερή μορφή + η βρασμένη της βάσης', () {
      final spaghetti = _mine('M2', 'Σπαγγέτι ολικής άλεσης Νο 7', {Nk.kcal: 336, Nk.protein: 13, Nk.carbs: 64, Nk.fat: 2.5});
      final s = FoodStore.preloaded(foods: basicFoods(), mine: [spaghetti], now: _now);
      final states = s.statesOf(spaghetti);
      expect([for (final x in states) x.$2], ['Ωμά', 'Βρασμένα']);
      expect([for (final x in states) x.$1.id], ['M2', 'C9871']);
      expect(identical(states.first.$1, spaghetti), isTrue);
      expect(askRawOrCooked(spaghetti, 250, timesEaten: 0, dryMine: true), isTrue);
      expect(askRawOrCooked(spaghetti, 250, timesEaten: 0), isFalse, reason: 'χωρίς βρασμένη μορφή: όπως πριν');
      expect(askRawOrCooked(spaghetti, 100, timesEaten: 0, dryMine: true), isFalse, reason: 'κάτω από 150 g');
      expect(askRawOrCooked(spaghetti, 250, timesEaten: 1, dryMine: true), isFalse, reason: 'το έχεις ξαναγράψει');
      // Προϊόν που δεν είναι ξερό δημητριακό: καμία μορφή.
      expect(s.statesOf(_mine('M7', 'Γιαούρτι Χ', {Nk.kcal: 95})), isEmpty);
      // 250 g: 336 × 2,5 = 840 kcal· βρασμένα της βάσης 179 × 2,5 = 447,5 → 448.
      expect(rawOrCookedQuestion(250, [(spaghetti, 'Ωμά'), states[1]]), '250 g ωμά = 840 kcal\n250 g βρασμένα = 448 kcal');
    });

    testWidgets('250 g βρασμένα του σαρωμένου σπαγγέτι: ερώτηση, «Βρασμένα» → γράφεται η βρασμένη μορφή της βάσης', (t) async {
      final spaghetti = _mine('M2', 'Σπαγγέτι ολικής άλεσης Νο 7', {Nk.kcal: 336, Nk.protein: 13, Nk.carbs: 64, Nk.fat: 2.5});
      final store = FoodStore.preloaded(foods: basicFoods(), mine: [spaghetti], now: _now);
      await _pump(t, AddFoodScreen(food: store, meal: Meal.lunch, day: _today));
      await t.tap(find.text('Σπαγγέτι ολικής άλεσης Νο 7'));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const ValueKey('state-note'))).data,
          'Οι τιμές είναι για το ξερό προϊόν, όπως στη συσκευασία: βάρος πριν το μαγείρεμα.');
      expect(find.widgetWithText(ChoiceChip, 'Ωμά'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Βρασμένα'), findsOneWidget);
      await _addFromSheet(t, 'Μεσημέρι', grams: '250');
      expect(find.text('Ζύγισες πριν ή μετά το μαγείρεμα;'), findsOneWidget);
      expect(find.text('250 g ωμά = 840 kcal\n250 g βρασμένα = 448 kcal'), findsOneWidget);
      await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Βρασμένα')));
      await t.pumpAndSettle();
      final e = store.entriesFor(_today).single;
      expect((e.food.id, e.grams), ('C9871', 250.0));
      expect(e.total(Nk.kcal), closeTo(447.5, 1e-9));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- A3-1
  group('R9-A3-1: σαρωμένα πράσινα λαχανικά δεν μετρούν «Όσπρια» (πραγματικές κατηγορίες του Open Food Facts με τους γονείς τους)', () {
    // Από την ταξινομία κατηγοριών του Open Food Facts (taxonomies/food/categories.txt): κάθε κατηγορία με όλους τους γονείς
    // της, όπως τις βάζει το «categories_tags».
    const greenBeans = [
      'en:canned-foods', 'en:canned-legumes', 'en:canned-plant-based-foods', 'en:canned-vegetables',
      'en:fruits-and-vegetables-based-foods', 'en:green-beans', 'en:legumes', 'en:legumes-and-their-products', 'en:plant-based-foods',
      'en:plant-based-foods-and-beverages', 'en:processed-vegetables', 'en:vegetable-based-foods-and-beverages', 'en:vegetables',
      'en:vegetables-based-foods', 'en:canned-green-beans',
    ];
    const peas = [
      'en:canned-foods', 'en:canned-legumes', 'en:canned-plant-based-foods', 'en:canned-vegetables',
      'en:fruits-and-vegetables-based-foods', 'en:green-peas', 'en:legumes', 'en:legumes-and-their-products', 'en:plant-based-foods',
      'en:plant-based-foods-and-beverages', 'en:processed-vegetables', 'en:vegetable-based-foods-and-beverages', 'en:vegetables',
      'en:vegetables-based-foods', 'en:canned-peas',
    ];
    const freshBroad = [
      'en:broad-beans', 'en:fresh-foods', 'en:fresh-legumes', 'en:fresh-plant-based-foods', 'en:fruits-and-vegetables-based-foods',
      'en:legumes', 'en:legumes-and-their-products', 'en:plant-based-foods', 'en:plant-based-foods-and-beverages',
      'en:vegetable-based-foods-and-beverages', 'en:vegetables', 'en:vegetables-based-foods', 'en:fresh-broad-beans',
    ];
    const lentilSprouts = [
      'en:legume-seeds', 'en:legumes', 'en:legumes-and-their-products', 'en:lentils', 'en:plant-based-foods',
      'en:plant-based-foods-and-beverages', 'en:pulses', 'en:seeds', 'en:sprouts', 'en:lentil-sprouts',
    ];
    const snowPeas = [
      'en:legume-seeds', 'en:legumes', 'en:legumes-and-their-products', 'en:plant-based-foods', 'en:plant-based-foods-and-beverages',
      'en:pulses', 'en:seeds', 'en:snow-peas',
    ];
    const mungSprouts = [
      'en:legume-seeds', 'en:legumes', 'en:legumes-and-their-products', 'en:plant-based-foods', 'en:plant-based-foods-and-beverages',
      'en:pulses', 'en:seeds', 'en:sprouts', 'en:sprouted-mung-beans',
    ];
    const frozenBroad = [
      'en:broad-beans', 'en:frozen-foods', 'en:frozen-legumes', 'en:frozen-plant-based-foods', 'en:frozen-vegetables',
      'en:fruits-and-vegetables-based-foods', 'en:legumes-and-their-products', 'en:plant-based-foods', 'en:plant-based-foods-and-beverages',
      'en:vegetable-based-foods-and-beverages', 'en:vegetables', 'en:vegetables-based-foods', 'en:frozen-broad-beans',
    ];

    test('φασολάκια/αρακάς κονσέρβα, κουκιά φρέσκα/κατεψυγμένα, φύτρες, χιονομπίζελα: «Τίποτα»', () {
      for (final (name, tags) in const [
        ('φασολάκια κονσέρβα', greenBeans),
        ('αρακάς κονσέρβα', peas),
        ('κουκιά φρέσκα', freshBroad),
        ('κουκιά κατεψυγμένα', frozenBroad),
        ('φύτρες φακής', lentilSprouts),
        ('χιονομπίζελα', snowPeas),
        ('φύτρες μουνγκ', mungSprouts),
      ]) {
        expect(cholKindFromOffTags(tags), CholKind.none, reason: name);
      }
    });

    test('ξερά και κονσέρβα όσπρια μένουν «Όσπρια»', () {
      for (final (name, tags) in const [
        ('ρεβίθια κονσέρβα', [
          'en:canned-foods', 'en:canned-legumes', 'en:canned-plant-based-foods', 'en:chickpeas', 'en:legume-seeds', 'en:legumes',
          'en:legumes-and-their-products', 'en:plant-based-foods', 'en:plant-based-foods-and-beverages', 'en:pulses', 'en:seeds',
          'en:canned-chickpeas',
        ]),
        ('φακές κονσέρβα', [
          'en:canned-foods', 'en:canned-legumes', 'en:canned-plant-based-foods', 'en:legumes', 'en:legumes-and-their-products',
          'en:plant-based-foods', 'en:plant-based-foods-and-beverages', 'en:canned-lentils',
        ]),
        ('φακές ξερές', [
          'en:legume-seeds', 'en:legumes', 'en:legumes-and-their-products', 'en:lentils', 'en:plant-based-foods',
          'en:plant-based-foods-and-beverages', 'en:pulses', 'en:seeds', 'en:dried-lentils',
        ]),
        ('φασόλια κονσέρβα', [
          'en:canned-common-beans', 'en:canned-foods', 'en:canned-legumes', 'en:canned-plant-based-foods', 'en:legumes',
          'en:legumes-and-their-products', 'en:plant-based-foods', 'en:plant-based-foods-and-beverages', 'en:canned-white-common-beans',
        ]),
        ('γίγαντες κονσέρβα', [
          'en:canned-foods', 'en:canned-legumes', 'en:canned-plant-based-foods', 'en:legumes', 'en:legumes-and-their-products',
          'en:plant-based-foods', 'en:plant-based-foods-and-beverages', 'en:canned-scarlet-runner-beans',
        ]),
        ('κουκιά ξερά', [
          'en:broad-beans', 'en:fruits-and-vegetables-based-foods', 'en:plant-based-foods', 'en:plant-based-foods-and-beverages',
          'en:vegetable-based-foods-and-beverages', 'en:vegetables', 'en:vegetables-based-foods', 'en:dried-broad-beans',
        ]),
        ('φάβα', [
          'en:dried-peas', 'en:legume-seeds', 'en:legumes', 'en:legumes-and-their-products', 'en:plant-based-foods',
          'en:plant-based-foods-and-beverages', 'en:pulses', 'en:seeds', 'en:dried-split-peas',
        ]),
      ]) {
        expect(cholKindFromOffTags(tags), CholKind.legumes, reason: name);
      }
    });

    test('η κάρτα: 240 g σαρωμένα φασολάκια (25 kcal) δεν κάνουν μέρα «όσπρια»', () {
      final f = foodFromDraft(
          draftFromOff('2000000000024', {
            'product_name': 'Φασολάκια Χ',
            'nutriments': {'energy-kcal_100g': 25, 'proteins_100g': 1.5, 'carbohydrates_100g': 3.5, 'fat_100g': 0.2},
            'categories_tags': greenBeans,
          }),
          'M8');
      expect(f.cholKind, CholKind.none);
      expect(CholDay([_le(_today, f, 240)]).legumes, isFalse);
    });

    test('πανέ καραβίδες/γλώσσα/χωματίδα χωρίς γονέα «en:breaded-fish»: δεν μετρούν «ψάρι»', () {
      expect(cholKindFromOffTags(const ['en:crustaceans', 'en:seafood', 'en:breaded-scampi']), CholKind.none);
      expect(cholKindFromOffTags(const ['en:fishes', 'en:seafood', 'en:lemon-sole', 'en:breaded-lemon-sole']), CholKind.none);
      expect(cholKindFromOffTags(const ['en:fishes', 'en:seafood', 'en:european-plaice', 'en:breaded-fried-european-plaice']),
          CholKind.none);
      expect(cholKindFromOffTags(const ['en:crustaceans', 'en:seafood', 'en:shrimps']), CholKind.fish);
    });
  });

  // ------------------------------------------------------------------------------------------------- A3-2 / A1-4 / U2-5
  group('R9-A3-2 / R9-A1-4 / R9-U2-5: όριο κορεσμένων ακριβές, «κάτω από» για το 10%', () {
    test('το κείμενο του ορίου', () {
      expect(satLimitText(2160, 6), 'έως 14,4 g', reason: '2.160 × 6% ÷ 9 = 14,4');
      expect(satLimitText(2250, 6), 'έως 15 g', reason: 'ακέραιο χωρίς «,0»');
      expect(satLimitText(2090, 6), 'έως 13,9 g', reason: '13,93');
      expect(satLimitText(2120, 10), 'κάτω από 23,6 g', reason: '23,56: ΠΟΥ «λιγότερο από 10%»');
      expect(satLimitText(2600, 10), 'κάτω από 28,9 g');
    });

    testWidgets('γιατρός, 2.160 kcal: σήμερα 14,3 g δεν είναι «πάνω από το όριο» (5,96%)· 14,5 g είναι 0,1 g πάνω', (t) async {
      final g = _goals(kcal: 2160);
      await _summary(t, g, kcal: 1500, sat: 14.3);
      expect(find.text('14,3 g / έως 14,4 g', findRichText: true), findsOneWidget);
      expect(find.textContaining('πάνω από το όριο'), findsNothing);
      await _summary(t, g, kcal: 1500, sat: 14.5);
      expect(find.text('14,5 g / έως 14,4 g', findRichText: true), findsOneWidget);
      expect(find.text('0,1 g πάνω από το όριο'), findsOneWidget);
    });

    testWidgets('η ίδια μέρα όταν τελειώσει (2.160 kcal, 14,3 g): «6,0%», χωρίς προειδοποίηση — ίδια απόφαση', (t) async {
      await _summary(t, _goals(kcal: 2160), kcal: 2160, sat: 14.3, today: false);
      expect(find.text('6,0% / έως 6% των θερμίδων', findRichText: true), findsOneWidget);
      expect(find.textContaining('Πάνω από'), findsNothing);
    });

    testWidgets('χωρίς γιατρό, 2.120 kcal: «κάτω από 23,6 g»· 23,8 g πάνω, 23,6 g «στο όριο», 23,5 g εντάξει', (t) async {
      final g = _goals(kcal: 2120, doctor: false);
      await _summary(t, g, kcal: 1500, sat: 23.8);
      expect(find.text('23,8 g / κάτω από 23,6 g', findRichText: true), findsOneWidget);
      expect(find.text('0,2 g πάνω από το όριο'), findsOneWidget);
      await _summary(t, g, kcal: 1500, sat: 23.6);
      expect(find.text('Στο όριο· ο στόχος είναι κάτω από 23,6 g'), findsOneWidget);
      await _summary(t, g, kcal: 1500, sat: 23.5);
      expect(find.textContaining('όριο'), findsNothing);
      // Η μέρα όταν τελειώσει (2.120 kcal, 23,8 g = 10,1%): επίσης πάνω.
      await _summary(t, g, kcal: 2120, sat: 23.8, today: false);
      expect(find.text('Πάνω από το 10% των θερμίδων που έφαγες'), findsOneWidget);
    });

    testWidgets('R9-A1-4: χωρίς γιατρό, 2.600 kcal: 28,9 g (= 10,0%) σήμερα δεν είναι «εντάξει»', (t) async {
      // 2.600 × 10% ÷ 9 = 28,89 → «κάτω από 28,9 g»· πριν «έως 29 g» και 28,9 g χωρίς προειδοποίηση.
      await _summary(t, _goals(kcal: 2600, doctor: false), kcal: 1800, sat: 28.9);
      expect(find.text('28,9 g / κάτω από 28,9 g', findRichText: true), findsOneWidget);
      expect(find.text('Στο όριο· ο στόχος είναι κάτω από 28,9 g'), findsOneWidget);
    });

    testWidgets('σελίδα «Στόχοι»: «κάτω από 23,6 g · 10%» χωρίς γιατρό, «έως 14,4 g · 6%» με γιατρό', (t) async {
      await _pump(
          t,
          GoalsPage(
              store: HealthStore()
                ..setProfile(_me)
                ..setGoals(_goals(kcal: 2120, doctor: false)),
              now: _now));
      expect(find.text('κάτω από 23,6 g · 10%'), findsOneWidget);
      expect(find.textContaining('έως 24 g'), findsNothing);
      await _pump(
          t,
          GoalsPage(
              key: const ValueKey('doctor'),
              store: HealthStore()
                ..setProfile(_me)
                ..setGoals(_goals(kcal: 2160)),
              now: _now));
      expect(find.text('έως 14,4 g · 6%'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- A3-3
  testWidgets('R9-A3-3: παλιά μέρα (πριν από τις 90): η κάρτα «Χοληστερίνη» μετρά όλη την εβδομάδα της', (t) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Μια Τετάρτη 94–100 μέρες πριν: η Δευτέρα και η Τρίτη της είναι κι αυτές πριν από τις 90 μέρες που φορτώνονται.
    var wed = DateTime(today.year, today.month, today.day - 100);
    while (wed.weekday != DateTime.wednesday) {
      wed = DateTime(wed.year, wed.month, wed.day + 1);
    }
    final mon = DateTime(wed.year, wed.month, wed.day - 2), tue = DateTime(wed.year, wed.month, wed.day - 1);
    // Δευ: 150 g φακές βρασμένες (= 60 g ξερές)· Τρί: 50 g φακές ξερές· Τετ: 120 g ψάρι.
    final log = [_le(mon, _byId('C20360'), 150), _le(tue, _byId('C20359'), 50), _le(wed, _byId('C26136'), 120)];
    final ranges = <(String, String)>[];
    _mockFood((call) async {
      final args = call.arguments is Map ? Map<String, dynamic>.from(call.arguments as Map) : <String, dynamic>{};
      switch (call.method) {
        case 'logRange':
          final from = args['from'] as String, to = args['to'] as String;
          ranges.add((from, to));
          // Όπως η βάση στο κινητό (DayStore.logRange): από «from» ως «to», και τα δύο μέσα.
          return jsonEncode({
            'ok': true,
            'entries': [
              for (final e in log)
                if (e.day.compareTo(from) >= 0 && e.day.compareTo(to) <= 0) e.toJson(),
            ],
          });
        case 'myFoods':
          return jsonEncode({'ok': true, 'foods': <Object>[]});
      }
      return '{"ok":true}';
    });
    final s = FoodStore();
    addTearDown(s.dispose);
    await t.runAsync(() async {
      await s.start();
      s.setDay(wed);
      for (var i = 0; i < 200 && s.entriesFor(mon).isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    expect(ranges.last.$1, dateKey(mon), reason: 'φορτώνει από τη Δευτέρα της εβδομάδας');
    expect([s.entriesFor(mon).length, s.entriesFor(tue).length, s.entriesFor(wed).length], [1, 1, 1]);
    await _pump(t, Scaffold(body: SingleChildScrollView(child: CholCard(food: s, goals: _goals(), day: wed, today: today))));
    CholRow row(String label) => t.widget<CholRow>(find.ancestor(of: find.text(label), matching: find.byType(CholRow)));
    expect(row('Όσπρια').value, '2', reason: 'Δευτέρα και Τρίτη (πριν: «0»)');
    expect(row('Ψάρι').value, '1');
  });

  // ---------------------------------------------------------------------------------------------------------------- A3-4
  testWidgets('R9-A3-4: μέρα πριν από τους στόχους: ούτε η κάρτα «Χοληστερίνη»', (t) async {
    Future<void> page(DateTime day) async {
      final food = FoodStore.preloaded(foods: basicFoods(), entries: [_le(day, _byId('C13005'), 120)], now: day);
      final health = HealthStore()
        ..setProfile(_me)
        ..setGoals(_goals(since: '2026-11-16'));
      await _pump(
          t,
          Scaffold(
              key: ValueKey(day),
              body: PageHeaderScope(
                  header: const SizedBox.shrink(),
                  child: FoodTheme(child: NutritionPage(food: food, health: health, now: DateTime(2026, 11, 17, 12))))),
          size: const Size(400, 3000));
    }

    await page(DateTime(2026, 11, 13));
    expect(find.byKey(const ValueKey('nutrition-chol')), findsNothing);
    expect(find.byKey(const ValueKey('nutrition-goals')), findsNothing);
    await page(DateTime(2026, 11, 16));
    expect(find.byKey(const ValueKey('nutrition-chol')), findsOneWidget);
  });

  // ---------------------------------------------------------------------------------------------------------------- U2-1
  testWidgets('R9-U2-1: «πλήρης μέρα» με τον τωρινό στόχο, ίδια στη Διατροφή και στη σελίδα «Χοληστερίνη»', (t) async {
    // Στόχος 2.250· ο έλεγχος της Δευτέρας 14/12 πατήθηκε «Εφάρμοσε» την Τετάρτη 16/12 → 2.100. Δευ 14/12: 1.300 kcal, 13 g.
    final g = Goals(
      aim: GoalAim.lose,
      rate: 0.005,
      activity: 1.5,
      doctor: true,
      since: '2026-11-16',
      kg: 90,
      age: 40,
      heightCm: 180,
      male: true,
      kcalAdapt: 2100,
      log: const [AdaptLog(day: '2026-12-16', tdee: 2600, before: 2250, after: 2100, applied: true)],
    );
    final mon = DateTime(2026, 12, 14);
    await _summary(t, g, kcal: 1300, sat: 13, today: false, day: mon);
    // 60% × 2.100 = 1.260 ≤ 1.300: πλήρης μέρα· 13 × 9 / 1.300 = 9,0% (πριν: 60% × 2.250 = 1.350 → γραμμάρια, «εντάξει»).
    expect(find.byKey(const ValueKey('goals-sat-pct')), findsOneWidget);
    expect(find.text('9,0% / έως 6% των θερμίδων', findRichText: true), findsOneWidget);
    expect(find.text('Πάνω από το 6% των θερμίδων που έφαγες'), findsOneWidget);
    expect(find.text('στόχος 2.250'), findsOneWidget, reason: 'οι θερμίδες της μέρας μένουν με τον στόχο εκείνης της μέρας');
    final week = CholWeek([(mon, CholDay([_le(mon, _f('S', {Nk.kcal: 1300, Nk.satFat: 13}), 100)]))], goalKcal: g.kcal);
    expect(week.fullDays, 1);
    expect(week.satPctMean, closeTo(9.0, 1e-9));
  });

  // ---------------------------------------------------------------------------------------------------------------- U2-2
  group('R9-U2-2: «οι τιμές είναι για τη μορφή «…»» σε σωστά ελληνικά', () {
    test('κάθε μαγειρεμένη μορφή της βάσης', () {
      final cooked = basicFoods().where((f) => f.rawId != null).toList();
      expect(cooked, isNotEmpty);
      for (final f in cooked) {
        final note = stateNote(f);
        expect(note, contains('για τη μορφή «${f.cookedLabel}»'), reason: f.name);
        for (final bad in ['για στον', 'για φούρνου', 'για κατσαρόλας', 'για ψητός', 'για βρασμένοι', 'για μαγειρεμένος', 'για βραστός']) {
          expect(note, isNot(contains(bad)), reason: f.name);
        }
      }
      expect(stateNote(_byId('C20304')), 'Βάρος μετά το μαγείρεμα· οι τιμές είναι για τη μορφή «Στον ατμό».');
      final fried = cooked.firstWhere((f) => f.cookedLabel == 'Τηγανητό');
      expect(stateNote(fried), 'Βάρος μετά το μαγείρεμα· οι τιμές είναι για τη μορφή «Τηγανητό», μαζί με το λάδι που ρούφηξε.');
      final noOil = cooked.firstWhere((f) => f.cookedLabel == 'Τηγανητό χωρίς λάδι');
      expect(stateNote(noOil), isNot(contains('λάδι που ρούφηξε')));
      expect(stateNote(_byId('C20057')), 'Βάρος πριν το μαγείρεμα (το πιο ακριβές).');
    });
    testWidgets('μπρόκολο στον ατμό: η γραμμή κάτω από τα «Ζύγισα:»', (t) async {
      final store = FoodStore.preloaded(foods: basicFoods(), now: _now);
      await _pump(t, Scaffold(body: QuantitySheet(food: store, item: _byId('C20304'), initialGrams: 150, meal: Meal.lunch)));
      expect(t.widget<Text>(find.byKey(const ValueKey('state-note'))).data,
          'Βάρος μετά το μαγείρεμα· οι τιμές είναι για τη μορφή «Στον ατμό».');
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- U2-3
  testWidgets('R9-U2-3: «−»/«+» με την κλίμακα του τροφίμου: αλάτι 1 g, λάδι 5 g, τα άλλα 10 g', (t) async {
    final store = FoodStore.preloaded(foods: basicFoods(), now: _now);
    Future<void> sheet(String id, double grams) =>
        _pump(t, Scaffold(body: QuantitySheet(key: ValueKey(id), food: store, item: _byId(id), initialGrams: grams, meal: Meal.lunch)));
    Future<String> press(String tooltip) async {
      await t.tap(find.byTooltip(tooltip));
      await t.pumpAndSettle();
      return _sheetGrams(t);
    }

    await sheet('C11017', 2); // Αλάτι
    expect(await press('Περισσότερο'), '3');
    expect(await press('Λιγότερο'), '2');
    expect(await press('Λιγότερο'), '1');
    expect(await press('Λιγότερο'), '0,5');
    expect(await press('Λιγότερο'), '0,5');
    await sheet('C17270', 10); // Ελαιόλαδο
    expect(await press('Λιγότερο'), '5');
    expect(await press('Περισσότερο'), '10');
    expect(await press('Περισσότερο'), '15');
    await sheet('C13005', 100); // Μπανάνα
    expect(await press('Περισσότερο'), '110');
    expect(await press('Λιγότερο'), '100');
  });

  // ---------------------------------------------------------------------------------------------------------------- U2-4
  group('R9-U2-4: «+ Φαγητό» › ⋮ › «Διόρθωση»/«Διαγραφή» δικού μου προϊόντος', () {
    Food yogurt(double kcal) => _mine('MY', 'Γιαούρτι Χ', {Nk.kcal: kcal, Nk.protein: 9, Nk.carbs: 4, Nk.fat: 5});
    final other = _mine('MO', 'Ψωμί Χ', {Nk.kcal: 250, Nk.protein: 9, Nk.carbs: 45, Nk.fat: 3});

    test('pickable: η τωρινή μορφή, ή τίποτα αν σβήστηκε', () async {
      final s = FoodStore.preloaded(foods: basicFoods(), mine: [yogurt(730), other], now: _now);
      final old = s.mine.first;
      await s.saveMyFood(yogurt(73));
      expect(s.pickable(old)!.n.amount(Nk.kcal), 73);
      await s.deleteMyFood(old);
      expect(s.pickable(old), isNull);
      expect(s.pickable(_byId('C13005'))!.id, 'C13005');
    });

    testWidgets('«Διόρθωση» 730 → 73 kcal: η γραμμή ανανεώνεται και το πάτημα γράφει τα νέα kcal (200 g = 146)', (t) async {
      final store = FoodStore.preloaded(foods: basicFoods(), mine: [yogurt(730), other], now: _now);
      await _pump(t, AddFoodScreen(food: store, meal: Meal.breakfast, day: _today));
      expect(find.textContaining('730 kcal'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('mine-more-MY')));
      await t.pumpAndSettle();
      await t.tap(find.text('Διόρθωση'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('field-kcal')), '73');
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Αποθήκευση'));
      await t.tap(find.text('Αποθήκευση'));
      await t.pumpAndSettle();
      expect(find.textContaining('730 kcal'), findsNothing);
      expect(find.textContaining('73 kcal'), findsOneWidget);
      await t.tap(find.text('Γιαούρτι Χ'));
      await t.pumpAndSettle();
      await _addFromSheet(t, 'Πρωινό', grams: '200');
      final e = store.entriesFor(_today).single;
      expect(e.total(Nk.kcal), closeTo(146, 1e-9));
    });

    testWidgets('«Διαγραφή»: το προϊόν φεύγει αμέσως από τα «Δικά μου»', (t) async {
      final store = FoodStore.preloaded(foods: basicFoods(), mine: [yogurt(95), other], now: _now);
      await _pump(t, AddFoodScreen(food: store, meal: Meal.breakfast, day: _today));
      Finder inMine(String name) => find.descendant(of: find.byKey(const ValueKey('add-mine')), matching: find.text(name));
      expect(inMine('Γιαούρτι Χ'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('mine-more-MY')));
      await t.pumpAndSettle();
      await t.tap(find.text('Διαγραφή'));
      await t.pumpAndSettle();
      expect(inMine('Γιαούρτι Χ'), findsNothing);
      expect(inMine('Ψωμί Χ'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- U2-6
  group('R9-U2-6: TalkBack στη Διατροφή', () {
    testWidgets('μπάρα στόχου: «…, στόχος έως 13,9 g», όχι «από έως»', (t) async {
      final handle = t.ensureSemantics();
      await _summary(t, _goals(), kcal: 1500, sat: 13);
      expect(find.bySemanticsLabel(RegExp(r'Κορεσμένα λιπαρά: 13,0 g, στόχος έως 13,9 g')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'από έως')), findsNothing);
      handle.dispose();
    });

    testWidgets('σελίδα «Χοληστερίνη»: ολόκληρες μέρες, μονάδα και «πάνω από τον στόχο»· κάρτα: ολόκληρος ο μήνας', (t) async {
      final handle = t.ensureSemantics();
      final mon = DateTime(2026, 11, 16), wed = DateTime(2026, 11, 18);
      // Δευ 16/11: 1.500 kcal (πλήρης μέρα, ≥ 1.254), 17 g κορεσμένα = 10,2%, 20 g ίνες. Τρί 17/11: 150 g φακές βρασμένες
      // (60 g ξερές: μία φορά όσπρια· 187,5 kcal, λίγη καταγραφή).
      final day = _f('C', {Nk.kcal: 1500, Nk.satFat: 17, Nk.fiber: 20, Nk.protein: 60, Nk.carbs: 150, Nk.fat: 50, Nk.salt: 4});
      final store = FoodStore.preloaded(
          foods: basicFoods(), entries: [_le(mon, day, 100), _le(DateTime(2026, 11, 17), _byId('C20360'), 150)], now: wed);
      await _pump(t, CholesterolPage(food: store, goals: _goals(), today: wed), size: const Size(400, 3000));
      expect(find.bySemanticsLabel(RegExp(r'Δευτέρα 16 Νοεμβρίου: 10,2 τοις εκατό, πάνω από τον στόχο')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'Δευτέρα 16 Νοεμβρίου: 20 γραμμάρια')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'(^|; )Δε: ')), findsNothing);
      // Η κάρτα της Τετάρτης 18/11, βλέποντας από την Πέμπτη 26/11.
      await _pump(t,
          Scaffold(body: SingleChildScrollView(child: CholCard(food: store, goals: _goals(), day: wed, today: DateTime(2026, 11, 26)))));
      expect(find.text('από 16 Νοε ως 18 Νοε'), findsWidgets);
      expect(find.bySemanticsLabel(RegExp(r'Όσπρια, από 16 Νοεμβρίου ως 18 Νοεμβρίου: 1 από 4')), findsOneWidget);
      handle.dispose();
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- A12-5
  group('R9-A12-5: δοκιμές για τις διορθώσεις του γύρου 8', () {
    testWidgets('R8-U2-1 (διαγραφή): δύο διαγραφές → ένα μήνυμα, «Αναίρεση» φέρνει πίσω τη ΔΕΥΤΕΡΗ, και κλείνει μόνο του', (t) async {
      final banana = _le(_today, _byId('C13005'), 120, hour: 10);
      final apple = _le(_today, _byId('C13039'), 150, hour: 11);
      final store = FoodStore.preloaded(foods: basicFoods(), entries: [banana, apple], now: _now);
      var target = banana;
      await _pumpHost(t, (ctx) => openEditEntry(ctx, store, target));
      Future<void> delete() async {
        await t.tap(find.text('άνοιξε'));
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('Διαγραφή'));
        await t.tap(find.text('Διαγραφή'));
        await t.pumpAndSettle();
      }

      await delete();
      expect(find.text('Διαγράφηκε: ${banana.food.name}'), findsOneWidget);
      target = apple;
      await delete();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Διαγράφηκε: ${apple.food.name}'), findsOneWidget);
      expect(find.text('Διαγράφηκε: ${banana.food.name}'), findsNothing);
      await t.tap(find.text('Αναίρεση'));
      await t.pumpAndSettle();
      expect([for (final e in store.entriesFor(_today)) e.id], [apple.id]);
      // Το επόμενο μήνυμα κλείνει μόνο του (persist: false, 6″).
      target = apple;
      await delete();
      expect(find.byType(SnackBar), findsOneWidget);
      await t.pump(const Duration(seconds: 7));
      await t.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('R8-U2 Β1: πίτουρο από το «+ Φαγητό» με τη μερίδα του πλάνου (30 g)', (t) async {
      final before = HealthStore.shared;
      addTearDown(() => HealthStore.shared = before);
      HealthStore.shared = HealthStore()..setGoals(_goals(branG: 30));
      final store = FoodStore.preloaded(foods: basicFoods(), now: _now);
      await _pump(t, AddFoodScreen(food: store, meal: Meal.breakfast, day: _today));
      await _open(t, 'πίτουρο', 'Πίτουρο βρώμης');
      expect(_sheetGrams(t), '30');
    });
  });
}
