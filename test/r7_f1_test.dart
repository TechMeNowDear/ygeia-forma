// Round7 (f1, φαγητό): R7-A2, R7-A3 και R7-U2 (καταχώριση, χοληστερίνη, «Πώς βγήκε» της Διατροφής).
// Όλες οι αναμενόμενες τιμές βγήκαν με το χέρι (python) από τον γραμμένο κανόνα και τις τιμές της βάσης, όχι από τον κώδικα.
// Τα «Τρόφιμο …» και τα δικά μου προϊόντα είναι φανταστικά (δημόσιο repo).
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
import 'package:ygeia_forma/pages/goals_page.dart';
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

const _samsung = MethodChannel('ygeia/samsung');
TestDefaultBinaryMessenger get _messenger => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

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
Food _mine(String id, String name, Map<String, double> n, {String? ck}) =>
    _f(id, n, name: name, cat: myFoodsCategory, source: 'Ετικέτα', ck: ck);

var _seq = 0;
LogEntry _le(DateTime d, Food f, double grams, {int hour = 13, Meal meal = Meal.lunch}) => LogEntry(
      id: 'r7f1-${_seq++}',
      day: dateKey(d),
      meal: meal,
      food: f,
      grams: grams,
      time: DateTime(d.year, d.month, d.day, hour),
    );

Food _byId(String id) => basicFoods().firstWhere((f) => f.id == id);

/// Φανταστικός χρήστης με οδηγία γιατρού για την LDL και στόχο 2.090 kcal (κορεσμένα έως 14 g = 6%).
Goals _goals2090() => Goals(
      aim: GoalAim.lose,
      rate: 0.005,
      activity: 1.5,
      doctor: true,
      since: '2026-11-12',
      kg: 90,
      age: 40,
      heightCm: 180,
      male: true,
      kcalSet: 2090,
    );

const _me = Profile(birthYear: 1985, birthMonth: 12, sex: 'm', heightCm: 180);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
  });

  // ---------------------------------------------------------------------------------------------------------------- A2
  group('R7-A2-2: «Άλλα x% θερμίδων» λέει μόνο ό,τι υπάρχει', () {
    Future<String> other(WidgetTester t, List<(String, double)> items) async {
      final d = DateTime(2026, 11, 10);
      await _pump(
          t, Scaffold(body: SingleChildScrollView(child: MacroBreakdown(totals: Totals([for (final (id, g) in items) _le(d, _byId(id), g)])))));
      return t.widget<Text>(find.byKey(const ValueKey('macro-other'))).data!;
    }

    // Πρωτεΐνη 64% + λιπαρά 34% = 98%· οι ίνες (0,1 g) δίνουν 0%: το 2% είναι οξέα της CIQUAL, όχι ίνες.
    testWidgets('κοτόπουλο ψητό 200 g + φέτα 50 g: όχι «φυτικές ίνες»', (t) async {
      expect(await other(t, [('C36018', 200), ('C12066', 50)]), 'Άλλα 2% θερμίδων: ό,τι άλλο μετρά η πηγή.');
    });
    // 32 + 52 + 4 = 88%· οι ίνες 25,35 g × 2 = 13,5% ≥ 12%.
    testWidgets('φακές βρασμένες 300 g: μόνο ίνες', (t) async {
      expect(await other(t, [('C20360', 300)]), 'Άλλα 12% θερμίδων: φυτικές ίνες.');
    });
    // USDA: 27 + 48 + 3 = 78%· ίνες 12%, μένουν 10% (ειδικοί συντελεστές ενέργειας της USDA).
    testWidgets('γίγαντες βρασμένοι 300 g: ίνες και ό,τι άλλο', (t) async {
      expect(await other(t, [('U174253', 300)]), 'Άλλα 22% θερμίδων: φυτικές ίνες και ό,τι άλλο μετρά η πηγή.');
    });
    testWidgets('κρασί 300 g: μόνο αλκοόλ', (t) async {
      expect(await other(t, [('C5214', 300)]), 'Άλλα 99% θερμίδων: αλκοόλ.');
    });
  });

  group('R7-A2-3: «Σωστή ποσότητα;» και για το μηδενικό παραπάνω στις μικρές μερίδες', () {
    test('πυκνό τρόφιμο από 300 g', () {
      expect(entryLooksLikeTypo(_byId('C32140'), 500), isTrue, reason: 'βρώμη 50 → 500 g = 1.845 kcal');
      expect(entryLooksLikeTypo(_byId('C32140'), 80), isFalse);
      expect(entryLooksLikeTypo(_byId('C15000'), 300), isTrue, reason: 'αμύγδαλα 30 → 300 g');
      expect(entryLooksLikeTypo(_byId('C12066'), 500), isTrue, reason: 'φέτα 50 → 500 g');
      expect(entryLooksLikeTypo(_byId('C9640'), 300), isTrue, reason: 'πίτουρο 30 → 300 g');
      expect(entryLooksLikeTypo(_byId('C36017'), 300), isFalse, reason: 'κοτόπουλο ωμό 110 kcal/100 g');
      expect(entryLooksLikeTypo(_byId('C12066'), 299), isFalse);
    });
    test('5 φορές η τελευταία ποσότητα, από 400 kcal', () {
      expect(entryLooksLikeTypo(_byId('C7110'), 600), isFalse, reason: 'χωρίς ιστορικό: 1.404 kcal, 234 kcal/100 g');
      expect(entryLooksLikeTypo(_byId('C7110'), 600, lastGrams: 60), isTrue, reason: 'ψωμί 60 → 600 g');
      expect(entryLooksLikeTypo(_byId('C26039'), 800, lastGrams: 80), isTrue, reason: 'τόνος 80 → 800 g = 1.144 kcal');
      expect(entryLooksLikeTypo(_byId('C22010'), 600, lastGrams: 60), isTrue, reason: 'αυγό 60 → 600 g = 804 kcal');
      expect(entryLooksLikeTypo(_byId('C19033'), 250, lastGrams: 30), isFalse, reason: 'γάλα 30 → 250 ml = 119 kcal');
      expect(entryLooksLikeTypo(_byId('C32140'), 150, lastGrams: 40), isFalse, reason: '3,75 φορές');
      expect(entryLooksLikeTypo(_byId('C32140'), 200, lastGrams: 40), isTrue, reason: '5 φορές, 738 kcal');
    });
    test('το όριο των 2.000 kcal μένει (τρόφιμο 240 kcal/100 g, κάτω από το «πυκνό»)', () {
      final x = _f('X', {Nk.kcal: 240});
      expect(entryLooksLikeTypo(x, 833), isFalse); // 1.999,2 kcal
      expect(entryLooksLikeTypo(x, 834), isTrue); // 2.001,6 kcal
    });
  });

  group('R7-A2-4: φαγητό μετά τα μεσάνυχτα γραμμένο «Χθες»', () {
    test('παίρνει την πραγματική ώρα: τελευταίο στη χθεσινή μέρα, πρώτο στα «Πρόσφατα», και η ποσότητά του μένει', () async {
      final thu = _yesterday;
      final fri0020 = DateTime(2026, 11, 13, 0, 20);
      final walnuts = _byId('C15005'), yogurt = _byId('U170903');
      final s = FoodStore.preloaded(
        foods: basicFoods(),
        entries: [_le(thu, walnuts, 25, hour: 10, meal: Meal.breakfast), _le(thu, yogurt, 170, hour: 21, meal: Meal.dinner)],
        now: fri0020,
      );
      final e = await s.add(walnuts, 30, Meal.dinner, on: thu, now: fri0020);
      expect(e.day, '2026-11-12', reason: 'η μέρα της καταχώρισης δεν αλλάζει');
      final day = s.entriesFor(thu);
      expect((day.last.food.id, day.last.grams), ('C15005', 30.0));
      expect(s.recent().first.id, 'C15005');
      expect(s.lastGrams('C15005'), 30);
    });
    test('entryTime: μόνο χθες και 00:00–03:59 κρατά την ώρα· αλλιώς η ώρα πάνω στη μέρα', () {
      final thu = _yesterday;
      expect(FoodStore.entryTime(thu, DateTime(2026, 11, 13, 0, 20)), DateTime(2026, 11, 13, 0, 20));
      expect(FoodStore.entryTime(thu, DateTime(2026, 11, 13, 3, 59)), DateTime(2026, 11, 13, 3, 59));
      expect(FoodStore.entryTime(thu, DateTime(2026, 11, 13, 4)), DateTime(2026, 11, 12, 4));
      expect(FoodStore.entryTime(DateTime(2026, 11, 10), DateTime(2026, 11, 13, 0, 20)), DateTime(2026, 11, 10, 0, 20));
      expect(FoodStore.entryTime(_today, DateTime(2026, 11, 13, 9, 5, 7)), DateTime(2026, 11, 13, 9, 5, 7));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- A3
  group('R7-A3-1: «Τίποτα» σταματά το πίτουρο από το όνομα', () {
    final d = DateTime(2026, 11, 10);

    test('μόνο όνομα που ΑΡΧΙΖΕΙ «πίτουρο βρώμης»· το «Τίποτα» (none) νικά το όνομα', () {
      final toast = _mine('M8', 'Ψωμί τοστ ολικής με πίτουρο βρώμης', {Nk.kcal: 250});
      expect(CholDay([_le(d, toast, 60)]).branG, 0);
      final toastNone = _mine('M8', 'Ψωμί τοστ ολικής με πίτουρο βρώμης', {Nk.kcal: 250}, ck: CholKind.none);
      expect(CholDay([_le(d, toastNone, 60)]).branG, 0);
      expect(CholDay([_le(d, _mine('M9', 'Πίτουρο βρώμης Χ', {Nk.kcal: 360}), 40)]).branG, 40);
      expect(CholDay([_le(d, _mine('M9', '  ΠΙΤΟΥΡΟ ΒΡΩΜΗΣ', {Nk.kcal: 360}), 40)]).branG, 40);
      expect(CholDay([_le(d, _mine('M9', 'Πίτουρο βρώμης Χ', {Nk.kcal: 360}, ck: CholKind.none), 40)]).branG, 0);
      expect(CholDay([_le(d, _byId('C9640'), 40)]).branG, 40, reason: 'το πίτουρο της βάσης με το id');
      // «Τίποτα» σε τρόφιμο με κατηγορία που μετρά: δεν μετρά.
      final nutsNone = _f('N1', {Nk.kcal: 650}, cat: 'Ξηροί καρποί', ck: CholKind.none);
      expect((isNuts(nutsNone), isBran(nutsNone), isLegumes(nutsNone), isFish(nutsNone)), (false, false, false, false));
      expect(branByName('Πίτουρο βρώμης'), isTrue);
      expect(branByName('Μπάρα με πίτουρο βρώμης'), isFalse);
    });

    test('JSON «ck»: «none» διαβάζεται και γράφεται (νέα τιμή, προαιρετική)', () {
      final base = {'id': 'M1', 'name': 'Κράκερ', 'cat': myFoodsCategory, 'source': 'Ετικέτα', 'n': {'kcal': 420}};
      final f = Food.fromJson({...base, 'ck': 'none'});
      expect(f.cholKind, CholKind.none);
      expect(f.toJson()['ck'], 'none');
      final e = LogEntry.fromJson(jsonDecode(jsonEncode(_le(d, f, 30).toJson())) as Map<String, dynamic>);
      expect(e.food.cholKind, CholKind.none);
      expect(Food.fromJson(base).cholKind, isNull, reason: 'παλιό προϊόν χωρίς «ck»');
    });

    test('Open Food Facts: ό,τι απλώς περιέχει → «Τίποτα»· με κατηγορία πίτουρου → κρίνει το όνομα', () {
      expect(cholKindFromOffTags(['en:breads']), CholKind.none);
      expect(cholKindFromOffTags(['en:crackers', 'en:cereals-and-their-products']), CholKind.none);
      // Round8 (R8-A3-1): σκέτο πίτουρο που μπαίνει και στα «δημητριακά πρωινού» μετρά ως πίτουρο (πριν null).
      expect(cholKindFromOffTags(['en:breakfast-cereals', 'en:oat-bran']), CholKind.bran);
      expect(cholKindFromOffTags(['en:oat-bran']), CholKind.bran);
      expect(cholKindFromOffTags(['en:yogurts']), isNull);
    });

    testWidgets('φόρμα: το «Τίποτα» αποθηκεύεται ως «none» και δεν μετρά', (t) async {
      Food? saved;
      final draft = FoodDraft(
          name: 'Ψωμί τοστ με πίτουρο βρώμης',
          values: {Nk.kcal: 250, Nk.protein: 9, Nk.carbs: 45, Nk.fat: 4},
          cholKind: CholKind.bran);
      await _pumpHost(t, (ctx) async {
        saved = await Navigator.of(ctx).push<Food>(MaterialPageRoute(builder: (_) => FoodFormScreen(draft: draft, cholChoice: true)));
      });
      await t.tap(find.text('άνοιξε'));
      await t.pumpAndSettle();
      final none = find.descendant(of: find.byKey(const ValueKey('chol-kind')), matching: find.text('Τίποτα'));
      await t.ensureVisible(none);
      await t.tap(none);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Αποθήκευση'));
      await t.tap(find.text('Αποθήκευση'));
      await t.pumpAndSettle();
      expect(saved!.cholKind, CholKind.none);
      expect(CholDay([_le(d, saved!, 60)]).branG, 0);
    });

    testWidgets('φόρμα: όνομα «Πίτουρο βρώμης …» χωρίς επιλογή δείχνει «Πίτουρο βρώμης» (αυτό θα μετρήσει)', (t) async {
      Food? saved;
      final draft = FoodDraft(name: 'Πίτουρο βρώμης Χ', values: {Nk.kcal: 360, Nk.protein: 17, Nk.carbs: 50, Nk.fat: 7});
      await _pumpHost(t, (ctx) async {
        saved = await Navigator.of(ctx).push<Food>(MaterialPageRoute(builder: (_) => FoodFormScreen(draft: draft, cholChoice: true)));
      });
      await t.tap(find.text('άνοιξε'));
      await t.pumpAndSettle();
      ChoiceChip chip(String label) => t.widget<ChoiceChip>(find.ancestor(
          of: find.descendant(of: find.byKey(const ValueKey('chol-kind')), matching: find.text(label)), matching: find.byType(ChoiceChip)));
      expect(chip('Πίτουρο βρώμης').selected, isTrue);
      expect(chip('Τίποτα').selected, isFalse);
      await t.ensureVisible(find.text('Αποθήκευση'));
      await t.tap(find.text('Αποθήκευση'));
      await t.pumpAndSettle();
      expect(saved!.cholKind, isNull);
      expect(isBran(saved!), isTrue);
    });
  });

  group('R7-A3-2: ίδιος κανόνας «έπιασες τα γραμμάρια» στην κάρτα και στη σελίδα', () {
    test('29,6 g καρύδια = «30 g / 30 g»: μετρά και ως μέρα με ξηρούς καρπούς', () {
      expect(reachedGrams(29.6, 30), isTrue);
      expect(reachedGrams(29.4, 30), isFalse);
      expect(reachedGrams(39.5, 40), isTrue);
      expect(reachedGrams(30, 0), isFalse);
      final mon = DateTime(2026, 11, 9);
      final filler = _f('F', {Nk.kcal: 1000, Nk.satFat: 1, Nk.fiber: 1, Nk.salt: 0.1});
      final w = CholWeek([(mon, CholDay([_le(mon, _byId('C15005'), 29.6), _le(mon, filler, 100)]))], goalKcal: 1500);
      expect(w.fullDays, 1);
      expect(w.daysWithNuts(30), 1);
    });
    testWidgets('η κάρτα δείχνει «έγινε» για την ίδια μέρα', (t) async {
      final store = FoodStore.preloaded(foods: basicFoods(), entries: [_le(_today, _byId('C15005'), 29.6)], now: _now);
      await _pump(t, Scaffold(body: SingleChildScrollView(child: CholCard(food: store, goals: _goals2090(), day: _today, today: _today))));
      final row = find.ancestor(of: find.text('Ξηροί καρποί'), matching: find.byType(CholRow));
      expect(t.widget<CholRow>(row).done, isTrue);
    });
  });

  group('R7-A3-3: ο αριθμός που φαίνεται και η απόφαση συμφωνούν', () {
    Future<void> card(WidgetTester t, Map<String, double> per100, {bool today = true}) async {
      final f = _f('D', per100);
      await _pump(
          t,
          Scaffold(
              body: SingleChildScrollView(
                  child: GoalsSummaryCard(totals: Totals([_le(_today, f, 100)]), goals: _goals2090(), today: today, health: HealthStore()))));
    }

    const base = {Nk.kcal: 1500.0, Nk.protein: 60.0, Nk.carbs: 150.0, Nk.fat: 50.0, Nk.fiber: 20.0, Nk.sugars: 30.0};

    // Round 9 (R9-A3-2): το όριο είναι το ακριβές 2.090 × 6% ÷ 9 = 13,93 → «έως 13,9 g» (πριν στρογγυλεμένο «έως 14 g»).
    testWidgets('κορεσμένα 14,3 g (όριο 13,9 g): «14,3 g» με «0,4 g πάνω»', (t) async {
      await card(t, {...base, Nk.satFat: 14.3, Nk.salt: 3});
      expect(find.text('14,3 g / έως 13,9 g', findRichText: true), findsOneWidget);
      expect(find.text('0,4 g πάνω από το όριο'), findsOneWidget);
      expect(find.text('14 g / έως 13,9 g', findRichText: true), findsNothing);
    });
    testWidgets('κορεσμένα 13,6 g: «13,6 g», χωρίς προειδοποίηση· 20 g: «20 g»', (t) async {
      await card(t, {...base, Nk.satFat: 13.6, Nk.salt: 3});
      expect(find.text('13,6 g / έως 13,9 g', findRichText: true), findsOneWidget);
      expect(find.textContaining('πάνω από το όριο'), findsNothing);
      await card(t, {...base, Nk.satFat: 20, Nk.salt: 3});
      expect(find.text('20 g / έως 13,9 g', findRichText: true), findsOneWidget);
    });
    testWidgets('αλάτι 4,96 g: γράφεται «5,0 g» και ΔΕΝ είναι «κάτω από 5 g»', (t) async {
      await card(t, {...base, Nk.satFat: 10, Nk.salt: 4.96});
      expect(t.widget<Text>(find.text('5,0 g / κάτω από 5 g')).style!.color, Aigaio.light.warn);
      await card(t, {...base, Nk.satFat: 10, Nk.salt: 4.94});
      expect(t.widget<Text>(find.text('4,9 g / κάτω από 5 g')).style!.color, isNot(Aigaio.light.warn));
    });
    test('η εβδομάδα με το ίδιο αλάτι', () {
      expect(saltShown(4.96), 5.0);
      expect(saltShown(4.94), 4.9);
      final mon = DateTime(2026, 11, 9), tue = DateTime(2026, 11, 10);
      CholDay day(DateTime d, double salt) => CholDay([_le(d, _f('S$salt', {Nk.kcal: 1500, Nk.satFat: 5, Nk.fiber: 5, Nk.salt: salt}), 100)]);
      final w = CholWeek([(mon, day(mon, 4.96)), (tue, day(tue, 4.94))], goalKcal: 2090);
      expect(w.fullDays, 2);
      expect(w.daysSaltOk(5), 1);
    });
    testWidgets('μπάρα εβδομάδας: 6,03% γράφεται «6,0» και δεν είναι πάνω από το 6%· 6,06% είναι', (t) async {
      const ok = Color(0xFF00AA00), over = Color(0xFFAA0000);
      Finder bar(Color color) =>
          find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == color);
      Future<void> bars(double v) => _pump(
          t,
          Scaffold(
              body: MiniBars(
                  key: ValueKey(v),
                  values: [v],
                  labels: const ['Δε'],
                  target: 6,
                  color: ok,
                  over: over,
                  higherIsWorse: true,
                  format: (x) => x.toStringAsFixed(1),
                  shownValue: oneDecimal)));
      // Η μέρα των 2.090 kcal με 14 g κορεσμένα: 14 × 9 / 2.090 = 6,03%.
      await bars(14 * 9 / 2090 * 100);
      expect(bar(over), findsNothing);
      expect(bar(ok), findsOneWidget);
      await bars(6.06);
      expect(bar(over), findsOneWidget);
    });
  });

  group('R7-A3-4: μέρα που τελείωσε: κορεσμένα ως % των θερμίδων, όπως η σελίδα «Χοληστερίνη»', () {
    Future<void> card(WidgetTester t, double kcal, double sat, {required bool today}) async {
      final f = _f('E', {Nk.kcal: kcal, Nk.satFat: sat, Nk.protein: 80, Nk.carbs: 200, Nk.fat: 60, Nk.fiber: 25, Nk.sugars: 40, Nk.salt: 4});
      await _pump(
          t,
          Scaffold(
              body: SingleChildScrollView(
                  child: GoalsSummaryCard(totals: Totals([_le(_yesterday, f, 100)]), goals: _goals2090(), today: today, health: HealthStore()))));
    }

    testWidgets('2.600 kcal, 16 g = 5,5%: χωρίς προειδοποίηση (η σελίδα: κάτω από το 6%)', (t) async {
      await card(t, 2600, 16, today: false);
      expect(find.byKey(const ValueKey('goals-sat-pct')), findsOneWidget);
      expect(find.text('5,5% / έως 6% των θερμίδων', findRichText: true), findsOneWidget);
      expect(find.textContaining('Πάνω από το 6%'), findsNothing);
      expect(CholDay([_le(_yesterday, _f('E', {Nk.kcal: 2600, Nk.satFat: 16}), 100)]).satPct! > 6, isFalse);
    });
    testWidgets('1.300 kcal (πλήρης μέρα, ≥ 1.254), 12 g = 8,3%: προειδοποίηση', (t) async {
      await card(t, 1300, 12, today: false);
      expect(find.text('8,3% / έως 6% των θερμίδων', findRichText: true), findsOneWidget);
      expect(find.text('Πάνω από το 6% των θερμίδων που έφαγες'), findsOneWidget);
    });
    testWidgets('σήμερα (η μέρα δεν τελείωσε): τα γραμμάρια του στόχου, όπως πριν', (t) async {
      await card(t, 2600, 16, today: true);
      expect(find.byKey(const ValueKey('goals-sat-pct')), findsNothing);
      // Round 9 (R9-A3-2): όριο 13,9 g (ακριβές), 16 − 13,9 = 2,1.
      expect(find.text('16 g / έως 13,9 g', findRichText: true), findsOneWidget);
      expect(find.text('2,1 g πάνω από το όριο'), findsOneWidget);
    });
    testWidgets('μέρα με λίγη καταγραφή (1.000 kcal < 1.254): γραμμάρια, όπως η σελίδα που δεν τη μετρά', (t) async {
      await card(t, 1000, 9, today: false);
      expect(find.byKey(const ValueKey('goals-sat-pct')), findsNothing);
      expect(find.text('9 g / έως 13,9 g', findRichText: true), findsOneWidget);
    });
  });

  group('R7-A3-5 / A3-9: «4 εβδομάδες» από όλες τις μέρες· όσπρια μία φορά τη μέρα', () {
    testWidgets('1 μέρα 12% + 21 μέρες 5% → 5,3% (όχι 6,8%)· ίνες 45 + 21 × 22 → 23 g (όχι 28)', (t) async {
      final tue = DateTime(2026, 11, 24);
      // 200 g = 2.000 kcal. Α: 26,67 g κορεσμένα = 12%, 45 g ίνες. Β: 11,11 g = 5%, 22 g ίνες.
      final a = _f('A', {Nk.kcal: 1000, Nk.satFat: 40 / 3, Nk.fiber: 22.5, Nk.salt: 1});
      final b = _f('B', {Nk.kcal: 1000, Nk.satFat: 50 / 9, Nk.fiber: 11, Nk.salt: 1});
      final entries = [
        _le(DateTime(2026, 11, 23), a, 200),
        for (var k = 2; k <= 22; k++) _le(DateTime(2026, 11, k), b, 200),
      ];
      final store = FoodStore.preloaded(foods: [a, b], entries: entries, now: tue);
      await _pump(t, CholesterolPage(food: store, goals: _goals2090(), today: tue), size: const Size(400, 3000));
      expect(find.text('μέσος όρος 12,0% · στόχος έως 6%'), findsOneWidget);
      expect(find.textContaining('μετρά μία φορά κάθε μέρα με τουλάχιστον 40 g ξερά'), findsOneWidget);
      await t.tap(find.text('4 εβδομάδες'));
      await t.pumpAndSettle();
      expect(find.text('μέσος όρος 5,3% · στόχος έως 6%'), findsOneWidget);
      expect(find.text('μέσος όρος 23 g · στόχος 30 g'), findsOneWidget);
    });
  });

  group('R7-A3-6: σε άλλη μέρα η κάρτα λέει ποιες μέρες μετρά', () {
    Future<void> card(WidgetTester t, DateTime day, DateTime today) => _pump(
        t,
        Scaffold(
            body: SingleChildScrollView(
                child: CholCard(food: FoodStore.preloaded(foods: basicFoods(), now: today), goals: _goals2090(), day: day, today: today))));

    testWidgets('Τετ 18/11 από την Πέμ 26/11: «από 16 Νοε ως 18 Νοε»', (t) async {
      final thu = DateTime(2026, 11, 26);
      await card(t, DateTime(2026, 11, 18), thu);
      expect(find.text('από 16 Νοε ως 18 Νοε'), findsNWidgets(2));
      expect(find.text('αυτή την εβδομάδα'), findsNothing);
      await card(t, DateTime(2026, 11, 16), thu);
      expect(find.text('Δευτέρα 16 Νοε'), findsNWidgets(2));
      await card(t, thu, thu);
      expect(find.text('αυτή την εβδομάδα'), findsNWidgets(2));
    });
  });

  group('R7-A3-7 / A3-8 / B2: τι λέει το ⓘ', () {
    test('ψάρι: όχι «βοηθά τα τριγλυκερίδια»· portfolio με στερόλες και σόγια· αλάτι του μαγειρέματος', () {
      expect(cholInfo.what, isNot(contains('βοηθά τα τριγλυκερίδια')));
      expect(cholInfo.what, contains('δεν ρίχνει την LDL'));
      expect(cholInfo.what, contains('φυτικές στερόλες και σόγια'));
      expect(cholInfo.compare, contains('Chiavaroli 2018'));
      expect(cholInfo.compare, isNot(contains('(Jenkins 2003)')));
      expect(cholInfo.cite, contains('Jenkins 2003 και 2011'));
      expect(cholInfo.accuracy, contains('αλάτι που βάζεις στο μαγείρεμα'));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- U2
  group('R7-U2-1: υπενθύμιση λαδιού και στα όσπρια', () {
    testWidgets('φακές βρασμένες και φασόλια ξερά', (t) async {
      final store = FoodStore.preloaded(foods: basicFoods(), now: _now);
      for (final id in ['C20360', 'C20501']) {
        await _pump(t, Scaffold(body: QuantitySheet(key: ValueKey(id), food: store, item: _byId(id), initialGrams: 100, meal: Meal.lunch)));
        expect(find.byKey(const ValueKey('oil-note')), findsOneWidget, reason: id);
      }
    });
  });

  group('R7-U2-2: «πριν ή μετά το μαγείρεμα;» μία φορά ανά τρόφιμο', () {
    test('ποιο τρόφιμο, πόσα γραμμάρια, πότε', () {
      expect(askRawOrCooked(_byId('C20359'), 300, timesEaten: 0), isTrue);
      expect(askRawOrCooked(_byId('C20359'), 150, timesEaten: 0), isTrue);
      expect(askRawOrCooked(_byId('C20359'), 149, timesEaten: 0), isFalse);
      expect(askRawOrCooked(_byId('C20359'), 80, timesEaten: 0), isFalse);
      expect(askRawOrCooked(_byId('C20359'), 300, timesEaten: 1), isFalse, reason: 'μία φορά: το έχεις ήδη γράψει');
      expect(askRawOrCooked(_byId('C20360'), 300, timesEaten: 0), isFalse, reason: 'η μαγειρεμένη μορφή');
      expect(askRawOrCooked(_byId('C9100'), 200, timesEaten: 0), isTrue, reason: 'ρύζι ωμό');
      expect(askRawOrCooked(_byId('C36017'), 300, timesEaten: 0), isFalse, reason: 'κοτόπουλο ωμό: 110 kcal/100 g');
      expect(rawOrCookedQuestion(300, [(_byId('C20359'), 'Ξερές'), (_byId('C20360'), 'Βρασμένες')]),
          '300 g ξερές = 981 kcal\n300 g βρασμένες = 375 kcal');
    });

    Future<FoodStore> addLentils(WidgetTester t, String grams) async {
      final store = FoodStore.preloaded(foods: basicFoods(), now: _now);
      await _pump(t, AddFoodScreen(food: store, meal: Meal.lunch, day: _today));
      await t.enterText(find.byType(TextField), 'φακές');
      await t.pumpAndSettle();
      await t.tap(find.text('Φακές (ξερές)').first);
      await t.pumpAndSettle();
      await t.enterText(find.descendant(of: find.byType(QuantitySheet), matching: find.byType(TextField)), grams);
      await t.pumpAndSettle();
      final add = find.text('Προσθήκη στο Μεσημέρι');
      await t.ensureVisible(add);
      await t.tap(add);
      await t.pumpAndSettle();
      return store;
    }

    testWidgets('300 g → ερώτηση· «Βρασμένες» → γράφονται 300 g βρασμένες', (t) async {
      final store = await addLentils(t, '300');
      expect(find.text('Ζύγισες πριν ή μετά το μαγείρεμα;'), findsOneWidget);
      expect(find.text('300 g ξερές = 981 kcal\n300 g βρασμένες = 375 kcal'), findsOneWidget);
      await t.tap(find.widgetWithText(TextButton, 'Βρασμένες'));
      await t.pumpAndSettle();
      final e = store.entriesFor(_today).single;
      expect((e.food.id, e.grams), ('C20360', 300.0));
    });
    testWidgets('«Ξερές» → γράφονται ξερές, χωρίς δεύτερη ερώτηση «Σωστή ποσότητα;»', (t) async {
      final store = await addLentils(t, '300');
      await t.tap(find.widgetWithText(FilledButton, 'Ξερές'));
      await t.pumpAndSettle();
      expect(find.text('Σωστή ποσότητα;'), findsNothing);
      expect(store.entriesFor(_today).single.food.id, 'C20359');
    });
    testWidgets('80 g ξερές: καμία ερώτηση', (t) async {
      final store = await addLentils(t, '80');
      expect(find.text('Ζύγισες πριν ή μετά το μαγείρεμα;'), findsNothing);
      expect(store.entriesFor(_today).single.food.id, 'C20359');
    });
  });

  group('R7-U2-3: «Αποθήκευση» με λάθος έξω από την οθόνη', () {
    testWidgets('προϊόν από barcode χωρίς όνομα: μήνυμα και κύλιση στο «Όνομα»', (t) async {
      Food? saved;
      await _pumpHost(t, (ctx) async {
        saved = await Navigator.of(ctx)
            .push<Food>(MaterialPageRoute(builder: (_) => FoodFormScreen(draft: FoodDraft(barcode: '5200000000123'), cholChoice: true)));
      }, size: const Size(400, 700));
      await t.tap(find.text('άνοιξε'));
      await t.pumpAndSettle();
      for (final (k, v) in [(Nk.kcal, '450'), (Nk.fat, '18'), (Nk.carbs, '60'), (Nk.protein, '8')]) {
        final f = find.byKey(ValueKey('field-$k'));
        await t.ensureVisible(f);
        await t.enterText(f, v);
        await t.pumpAndSettle();
      }
      final save = find.text('Αποθήκευση');
      await t.ensureVisible(save);
      await t.pumpAndSettle();
      await t.tap(save);
      await t.pumpAndSettle();
      expect(saved, isNull);
      expect(find.text('Συμπλήρωσε: όνομα.'), findsOneWidget);
      final err = t.getRect(find.text('Χρειάζεται όνομα'));
      expect(err.top, greaterThanOrEqualTo(0));
      expect(err.bottom, lessThanOrEqualTo(700));
    });
    testWidgets('Β-1: τα πεδία με τη σειρά της ετικέτας της ΕΕ και «Επόμενο» στο πληκτρολόγιο', (t) async {
      await _pump(t, FoodFormScreen(draft: FoodDraft(name: 'Κράκερ')), size: const Size(400, 3000));
      final order = [Nk.kcal, Nk.fat, Nk.satFat, Nk.carbs, Nk.sugars, Nk.fiber, Nk.protein, Nk.salt];
      final tops = [for (final k in order) t.getRect(find.byKey(ValueKey('field-$k'))).top];
      for (var i = 1; i < tops.length; i++) {
        expect(tops[i], greaterThan(tops[i - 1]), reason: order[i]);
      }
      expect(t.widget<TextField>(find.byKey(const ValueKey('field-kcal'))).textInputAction, TextInputAction.next);
    });
  });

  group('R7-U2-4: πρώτη ποσότητα για ξηρούς καρπούς και λάδι', () {
    test('30 g καρποί και σπόροι· 10 g λάδι, βούτυρο, «Λιπαρά»· 100 g τα άλλα', () {
      expect(firstGrams(_byId('C15005')), 30);
      expect(firstGrams(_byId('C15011')), 30, reason: 'ηλιόσποροι');
      expect(firstGrams(_byId('C17270')), 10);
      expect(firstGrams(_byId('C16400')), 10, reason: 'βούτυρο');
      expect(firstGrams(_byId('C11054')), 10, reason: 'μαγιονέζα (Λιπαρά)');
      expect(firstGrams(_byId('C13005')), 100, reason: 'μπανάνα');
      expect(firstGrams(_mine('M5', 'Καρύδια ψίχα', {Nk.kcal: 690, Nk.fat: 65}, ck: CholKind.nuts)), 30);
    });
    testWidgets('καρύδια χωρίς ιστορικό: πεδίο «30» και κουμπιά 15/30/45/60 g', (t) async {
      final store = FoodStore.preloaded(foods: basicFoods(), now: _now);
      await _pump(t, AddFoodScreen(food: store, meal: Meal.snack, day: _today));
      await t.enterText(find.byType(TextField), 'καρύδια');
      await t.pumpAndSettle();
      await t.tap(find.text('Καρύδια').first);
      await t.pumpAndSettle();
      final field = find.descendant(of: find.byType(QuantitySheet), matching: find.byType(TextField));
      expect(t.widget<TextField>(field).controller!.text, '30');
      for (final v in ['15 g', '30 g', '45 g', '60 g']) {
        expect(find.descendant(of: find.byType(QuantitySheet), matching: find.text(v)), findsOneWidget, reason: v);
      }
      expect(find.descendant(of: find.byType(QuantitySheet), matching: find.text('200 g')), findsNothing);
    });
  });

  group('R7-U2-5: το μαγειρεμένο που γράφεις συνέχεια βγαίνει πρώτο', () {
    test('3 φορές ψητό στήθος, ποτέ ωμό → «κοτόπουλο»: πρώτο το ψητό· αλλιώς το ωμό, όπως πριν', () {
      List<LogEntry> times(String id, int n) => [for (var k = 0; k < n; k++) _le(DateTime(2026, 11, 1 + k), _byId(id), 150)];
      FoodStore s(List<LogEntry> e) => FoodStore.preloaded(foods: basicFoods(), entries: e, now: _now);
      expect(s(const []).search('κοτόπουλο').first.id, 'C36017');
      expect(s(times('C36018', 2)).search('κοτόπουλο').first.id, 'C36017');
      expect(s(times('C36018', 3)).search('κοτόπουλο').first.id, 'C36018');
      expect(s(times('C36018', 3)).search('kotopoulo').first.id, 'C36018');
      expect(s([...times('C36018', 3), _le(_yesterday, _byId('C36017'), 150)]).search('κοτόπουλο').first.id, 'C36017',
          reason: 'γράφεις και ωμό: μένει πρώτο το ωμό');
    });
  });

  group('R7-U2-6: «φρέντο καπουτσίνο» → έντονη προειδοποίηση', () {
    test('καπουτσίνο και λάτε αλλάζουν τη διατροφή', () {
      final store = FoodStore.preloaded(foods: basicFoods(), now: _now);
      final r = store.find('φρέντο καπουτσίνο');
      expect(r.foods, isNotEmpty);
      expect(strongSearchWarning(r), isTrue);
      for (final w in ['καπουτσίνο', 'cappuccino', 'kaputsino', 'λάτε', 'latte']) {
        expect(changesNutrition(w), isTrue, reason: w);
      }
    });
  });

  group('R7-U2-7: «Όλα» των δικών μου από το «+ Φαγητό»: πάτημα = γράψε το', () {
    testWidgets('πάτημα σε προϊόν ανοίγει την ποσότητα', (t) async {
      await _pump(t, AddFoodScreen(food: sampleFoodStore(_now), meal: Meal.snack, day: _today));
      final all = find.byKey(const ValueKey('add-mine-all'));
      await t.ensureVisible(all);
      await t.tap(all);
      await t.pumpAndSettle();
      expect(find.byType(MyFoodsScreen), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('my-food-Mdemo2')));
      await t.pumpAndSettle();
      expect(find.byType(MyFoodsScreen), findsNothing);
      expect(find.descendant(of: find.byType(QuantitySheet), matching: find.text('Ανθότυρο')), findsOneWidget);
    });
    testWidgets('από «Τα στοιχεία μου» (όχι για γράψιμο): το πάτημα ανοίγει τις επιλογές, όπως πριν', (t) async {
      await _pump(t, MyFoodsScreen(food: sampleFoodStore(_now)));
      await t.tap(find.byKey(const ValueKey('my-food-Mdemo2')));
      await t.pumpAndSettle();
      expect(find.text('Διόρθωση'), findsOneWidget);
    });
  });

  group('R7-U2-8: «Όπως …» λέει τη μέρα που αντιγράφει', () {
    Future<void> page(WidgetTester t, FoodStore food) => _pump(
        t,
        Scaffold(
            body: PageHeaderScope(
                header: const SizedBox.shrink(), child: FoodTheme(child: NutritionPage(food: food, now: _now)))));

    testWidgets('βλέπω «Χθες · Πέμ 12/11»: «Όπως Τετ 11/11», και το μήνυμα το ίδιο', (t) async {
      final wed = DateTime(2026, 11, 11);
      final food = FoodStore.preloaded(foods: basicFoods(), entries: [
        _le(wed, _byId('C26039'), 80, hour: 20, meal: Meal.dinner),
        _le(wed, _byId('C20385'), 150, hour: 20, meal: Meal.dinner),
      ], now: _yesterday);
      await page(t, food);
      expect(find.textContaining('Όπως Τετ 11/11 · '), findsOneWidget);
      expect(find.textContaining('Όπως χθες'), findsNothing);
      final copy = find.byKey(const ValueKey('copy-dinner'));
      await t.ensureVisible(copy);
      await t.tap(copy);
      await t.pumpAndSettle();
      expect(find.text('Βράδυ: 2 τρόφιμα όπως Τετ 11/11'), findsOneWidget);
      expect(food.entriesFor(_yesterday).length, 2);
    });
    testWidgets('βλέπω τη σημερινή μέρα: «Όπως χθες», όπως πριν', (t) async {
      final food = FoodStore.preloaded(
          foods: basicFoods(), entries: [_le(_yesterday, _byId('C26039'), 80, hour: 20, meal: Meal.dinner)], now: _now);
      await page(t, food);
      expect(find.textContaining('Όπως χθες · '), findsOneWidget);
    });
  });

  group('R7-U2-9 / U2-14 / U2-15: διάταξη και κείμενα', () {
    testWidgets('U2-9: 360 dp με γράμματα 2×: τα γεύματα σε κουμπιά 2 × 2, γράμματα στο 2×', (t) async {
      await _pump(t, AddFoodScreen(food: sampleFoodStore(_now), meal: Meal.snack, day: _today),
          size: const Size(360, 2400), textScale: 2.0);
      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('meal-lunch')), findsOneWidget);
      final label = find.descendant(of: find.byType(MealPicker), matching: find.text('Μεσημέρι'));
      expect(t.getRect(label).height, greaterThanOrEqualTo(28));
    });
    testWidgets('U2-14: «Δεν βρέθηκε «σαλάτα»» χωρίς το κενό του πληκτρολογίου', (t) async {
      await _pump(t, AddFoodScreen(food: sampleFoodStore(_now), meal: Meal.snack, day: _today));
      await t.enterText(find.byType(TextField), 'σαλάτα ');
      await t.pumpAndSettle();
      expect(find.textContaining('Δεν βρέθηκε «σαλάτα» στη βάση.'), findsOneWidget);
    });
    testWidgets('U2-15: «τι τη ρίχνει» δεν σπάει (αδιάσπαστα κενά)', (t) async {
      await _pump(
          t,
          Scaffold(
              body: SingleChildScrollView(
                  child: CholCard(food: FoodStore.preloaded(foods: basicFoods(), now: _now), goals: _goals2090(), day: _today, today: _today))),
          size: const Size(360, 1600),
          textScale: 1.3);
      expect(find.text('Χοληστερίνη · τι τη ρίχνει'), findsOneWidget);
    });
  });

  group('R7-U2-13: πίτουρο: άκυρα γραμμάρια λένε τι θέλουν', () {
    testWidgets('200 g → «Από 0 ως 150 g.» και ο διάλογος μένει· β-γλυκάνες 0 → «πάνω από 0»', (t) async {
      final store = HealthStore()..setProfile(_me)..setGoals(_goals2090());
      await _pump(t, GoalsPage(store: store, now: _now), size: const Size(400, 3000));
      final row = find.byKey(const ValueKey('goals-bran'));
      await t.ensureVisible(row);
      await t.tap(row);
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('bran-beta')), '0');
      await t.pumpAndSettle();
      expect(find.text('Δεν μοιάζει σωστό (πάνω από 0 και ως 40 g).'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('bran-grams')), '200');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('bran-ok')));
      await t.pumpAndSettle();
      expect(find.text('Από 0 ως 150 g.'), findsOneWidget);
      expect(find.byKey(const ValueKey('bran-ok')), findsOneWidget);
      expect(store.goals!.branG, 40);
    });
  });

  group('R7-U2-17: «Αναίρεση» διαγραφής σκεύους αφού κλείσει η οθόνη', () {
    testWidgets('κανένα σφάλμα και το σκεύος ξαναγράφεται', (t) async {
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
      final item = find.text('Κατσαρόλα · Μάρκα Τ');
      await t.ensureVisible(item);
      await t.tap(item);
      await t.pumpAndSettle();
      final delete = find.text('Διαγραφή');
      await t.ensureVisible(delete);
      await t.tap(delete);
      await t.pumpAndSettle();
      expect(Kitchen.fromJson(store.prefs.kitchen).cookware, isEmpty);
      await t.state<NavigatorState>(find.byType(Navigator)).maybePop();
      await t.pumpAndSettle();
      expect(find.byType(KitchenScreen), findsNothing);
      await t.tap(find.text('Αναίρεση'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(Kitchen.fromJson(store.prefs.kitchen).cookware.map((c) => c.id), ['x1']);
    });
  });
}
