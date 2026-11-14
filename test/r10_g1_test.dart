// Round 10 · g1 (φαγητό, θερμίδες, «Αναφορά για έλεγχο»): R10-B1-1, R10-B1-2 (= R10-B7-3), R10-B1-3, R10-B1-4 και οι δύο
// δοκιμές του R10-B7-5. Όλες οι αναμενόμενες τιμές βγήκαν με το χέρι (python) από τον γραμμένο κανόνα και τις τιμές της
// βάσης, όχι από τον κώδικα. Προϊόντα, στόχοι και άνθρωπος φανταστικά (δημόσιο repo).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/adaptive_check.dart' show targetOn;
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/diagnostics.dart';
import 'package:ygeia_forma/food/chol.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/food/off.dart';
import 'package:ygeia_forma/goals.dart';
import 'package:ygeia_forma/history.dart' show dateKey;
import 'package:ygeia_forma/pages/food_add.dart';
import 'package:ygeia_forma/pages/goals_page.dart';
import 'package:ygeia_forma/pages/nutrition_goals.dart';
import 'package:ygeia_forma/profile.dart';
import 'package:ygeia_forma/theme.dart';

import 'sample_checkin.dart';
import 'sample_data.dart';
import 'sample_food.dart';

/// Παρασκευή 20/11/2026, μεσημέρι.
final _now = DateTime(2026, 11, 20, 12);
final _today = DateTime(2026, 11, 20);

const _me = Profile(birthYear: 1985, birthMonth: 12, sex: 'm', heightCm: 180);

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 2600)}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: w));
  await t.pumpAndSettle();
}

/// Μια οθόνη με ένα κουμπί «άνοιξε» που τρέχει το [onOpen] (για τη φόρμα, που ανοίγει δική της οθόνη).
Future<void> _pumpHost(WidgetTester t, Future<void> Function(BuildContext ctx) onOpen) => _pump(
      t,
      Scaffold(
        body: Builder(
          builder: (ctx) => Center(child: TextButton(onPressed: () => onOpen(ctx), child: const Text('άνοιξε'))),
        ),
      ),
    );

/// Φανταστικό τρόφιμο με τιμές ανά 100 g.
Food _f(String id, Map<String, double> n) => Food(
      id: id,
      name: 'Τρόφιμο $id',
      cat: 'Άλλα',
      source: 'CIQUAL 2025',
      n: Nutrients({for (final e in n.entries) e.key: NValue(e.value)}),
    );

/// Δικό μου προϊόν (από ετικέτα).
Food _mine(String id, String name, Map<String, double> n, {String? ck}) => Food(
      id: id,
      name: name,
      cat: myFoodsCategory,
      source: 'Ετικέτα',
      cholKind: ck,
      n: Nutrients({for (final e in n.entries) e.key: NValue(e.value)}),
    );

var _seq = 0;
LogEntry _le(DateTime d, Food f, double grams) => LogEntry(
      id: 'r10g1-${_seq++}',
      day: dateKey(d),
      meal: Meal.lunch,
      food: f,
      grams: grams,
      time: DateTime(d.year, d.month, d.day, 13),
    );

Food _byId(String id) => basicFoods().firstWhere((f) => f.id == id);

Finder _spoonChip(String label) =>
    find.descendant(of: find.byKey(const ValueKey('spoon-kind')), matching: find.widgetWithText(ChoiceChip, label));

Future<void> _next(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey('wizard-next')));
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------------------------------------------- B1-1
  group('R10-B1-1: «Μετριέται με το κουτάλι»: ολόκληρη λέξη από το όνομα, και το «Όχι» κρατιέται στη «Διόρθωση»', () {
    test('όνομα: η πρώτη λέξη ολόκληρη (ελληνικά) ή η αρχή της (λατινικά)', () {
      for (final n in ['Βουτυρόγαλα ΜΕΒΓΑΛ', 'ΒΟΥΤΥΡΟΓΑΛΑ', 'Βουτυρομπισκότα Χ', 'Βουτυρόψωμο', 'Ταχινόπιτα', 'Βουτυράκια Χ']) {
        expect(spoonByName(n), isFalse, reason: n);
      }
      for (final n in [
        'Βούτυρο αγελάδος',
        'ΒΟΥΤΥΡΟ',
        'Ταχίνι ολικής',
        'Πραλίνα φουντουκιού',
        'Μαργαρίνη light',
        '«Μαγιονέζα» Χ',
        'Φυστικοβούτυρο',
        'Tahini X',
        'Margarine X',
        'Mayonnaise X',
      ]) {
        expect(spoonByName(n), isTrue, reason: n);
      }
    });

    test('JSON: «sp»: false μόνο για το «Όχι» που διάλεξες· οι παλιές εκδόσεις το διαβάζουν «όχι»', () {
      final no = foodFromDraft(
          FoodDraft(name: 'Μαγιονέζα light Χ', values: {Nk.kcal: 300, Nk.protein: 1, Nk.carbs: 9, Nk.fat: 30}, spoon: false), 'M1');
      expect((no.spoon, no.spoonNo, isSpoonFood(no)), (false, true, false));
      final j = jsonDecode(jsonEncode(no.toJson())) as Map<String, dynamic>;
      expect(j['sp'], isFalse);
      expect(j['sp'] == true, isFalse, reason: 'ο κανόνας ανάγνωσης ως το #108 (j[sp] == true): «όχι», όπως πριν');
      final back = Food.fromJson(j);
      expect((back.spoon, back.spoonNo), (false, true));
      expect(draftFromFood(back).spoon, isFalse, reason: 'η «Διόρθωση» ξεκινά από το «Όχι»');
      final e = LogEntry.fromJson(jsonDecode(jsonEncode(_le(_today, back, 10).toJson())) as Map<String, dynamic>);
      expect((e.food.spoon, e.food.spoonNo), (false, true));

      // Χωρίς απάντηση: κανένα «sp», και η φόρμα προτείνει από το όνομα, όπως πριν.
      final none = foodFromDraft(FoodDraft(name: 'Γιαούρτι Χ', values: {Nk.kcal: 95}), 'M2');
      expect((none.spoon, none.spoonNo, none.toJson().containsKey('sp')), (false, false, false));
      expect(draftFromFood(none).spoon, isNull);
      // «Ναι»: όπως πριν.
      final yes = foodFromDraft(FoodDraft(name: 'Ταχίνι Χ', values: {Nk.kcal: 640}, spoon: true), 'M3');
      expect((yes.toJson()['sp'], yes.spoonNo, draftFromFood(yes).spoon), (true, false, true));
    });

    testWidgets('νέο «Βουτυρόγαλα»: η φόρμα προτείνει «Όχι» και δεν γράφει «sp»', (t) async {
      Food? saved;
      await _pumpHost(t, (ctx) async {
        saved = await Navigator.of(ctx).push<Food>(MaterialPageRoute(
            builder: (_) => FoodFormScreen(
                draft: FoodDraft(name: 'Βουτυρόγαλα Χ', values: {Nk.kcal: 40, Nk.protein: 3.3, Nk.carbs: 4.8, Nk.fat: 1}))));
      });
      await t.tap(find.text('άνοιξε'));
      await t.pumpAndSettle();
      expect(t.widget<ChoiceChip>(_spoonChip('Όχι')).selected, isTrue);
      expect(t.widget<ChoiceChip>(_spoonChip('Ναι')).selected, isFalse);
      await t.ensureVisible(find.text('Αποθήκευση'));
      await t.tap(find.text('Αποθήκευση'));
      await t.pumpAndSettle();
      final f = saved!;
      expect((f.spoon, f.spoonNo, isSpoonFood(f), f.toJson().containsKey('sp')), (false, false, false, false));
    });

    testWidgets('«Μαγιονέζα light» με «Όχι» → «Διόρθωση»: η φόρμα δείχνει «Όχι» και η αποθήκευση το κρατά', (t) async {
      Food? saved;
      var draft = FoodDraft(name: 'Μαγιονέζα light Χ', values: {Nk.kcal: 300, Nk.protein: 1, Nk.carbs: 9, Nk.fat: 30});
      String? id;
      await _pumpHost(t, (ctx) async {
        saved = await Navigator.of(ctx).push<Food>(MaterialPageRoute(builder: (_) => FoodFormScreen(draft: draft, existingId: id)));
      });
      Future<void> open() async {
        await t.tap(find.text('άνοιξε'));
        await t.pumpAndSettle();
      }

      Future<void> save() async {
        await t.ensureVisible(find.text('Αποθήκευση'));
        await t.tap(find.text('Αποθήκευση'));
        await t.pumpAndSettle();
      }

      await open();
      expect(t.widget<ChoiceChip>(_spoonChip('Ναι')).selected, isTrue, reason: 'από το όνομα');
      await t.ensureVisible(_spoonChip('Όχι'));
      await t.tap(_spoonChip('Όχι'));
      await t.pumpAndSettle();
      await save();
      final first = saved!;
      expect((first.spoon, first.spoonNo, first.toJson()['sp']), (false, true, false));

      // «Διόρθωση» (my_foods.dart, editMyFood: draftFromFood + ίδιο id), π.χ. για να διορθωθεί το αλάτι.
      draft = draftFromFood(first);
      id = first.id;
      saved = null;
      await open();
      expect(t.widget<ChoiceChip>(_spoonChip('Όχι')).selected, isTrue);
      expect(t.widget<ChoiceChip>(_spoonChip('Ναι')).selected, isFalse);
      await save();
      final second = saved!;
      expect((second.id, second.spoon, second.spoonNo, isSpoonFood(second)), (first.id, false, true, false));
      expect(firstGrams(second), 100, reason: 'όχι κουτάλι: πρώτη ποσότητα όπως κάθε άλλο τρόφιμο');
      expect(entryLooksLikeTypo(second, 100), isFalse, reason: '100 g μαγιονέζα light (300 kcal) δεν ρωτά πια');
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- B1-2
  group('R10-B1-2 (= R10-B7-3): η «Αναφορά για έλεγχο» με τον στόχο και το όριο κορεσμένων που δείχνει η Διατροφή', () {
    test('ανά μέρα ο στόχος που ίσχυε τότε (σήμερα ο τωρινός, πριν από τους στόχους κανένας)· όριο με ένα δεκαδικό', () {
      final at = DateTime(2026, 11, 28, 12);
      // Στόχοι από 16/11 (τύπος: 1.830 × 1,5 − 495 = 2.250)· δικός σου 2.340 την Τετ 25/11 το βράδυ, 2.160 σήμερα το πρωί.
      final g1 = checkinGoals(kcalSet: 2340).recordChangeFrom(checkinGoals(), DateTime(2026, 11, 25, 20));
      final g2 = checkinGoals(kcalSet: 2160).recordChangeFrom(g1, DateTime(2026, 11, 28, 9));
      final s = HealthStore()..data = Dashboard.fromJson({...sampleDashboardJson(at), 'body': bodyJson(simWeights(at))});
      s
        ..history = sampleHistory(at, s.data!)
        ..setProfile(_me)
        ..setGoals(g2);
      final food = FoodStore.preloaded(foods: basicFoods(), now: at, entries: [
        for (final d in [14, 16, 23, 25, 27, 28]) _le(DateTime(2026, 11, d), _f('D$d', {Nk.kcal: 1800, Nk.satFat: 12}), 100),
      ]);
      final r = diagnosticsFrom(store: s, food: food, now: at);
      final calc = r['calc'] as Map;
      final days = {for (final d in calc['days'] as List) (d as Map)['d']: d};
      Object? key(Object? day, String k) => (days[day] as Map)[k];
      expect(days.keys.toList(), ['2026-11-14', '2026-11-16', '2026-11-23', '2026-11-25', '2026-11-27', '2026-11-28']);
      // 14/11 πριν από τους στόχους· ως και τη μέρα της αλλαγής (25/11) 2.250· 26–27/11 2.340· σήμερα ο τωρινός 2.160.
      expect([for (final d in days.keys) key(d, 'goalKcal')], [null, 2250, 2250, 2250, 2340, 2160]);
      // kcal × 6% ÷ 9: 2.160 → 14,4 σήμερα (όπως «έως 14,4 g» στη Διατροφή, όχι 14). Round11 (R11-C1-2): οι μέρες που
      // πέρασαν με 1.800 ≥ 60% × 2.160 κρίνονται στη Διατροφή με το % των θερμίδων, άρα χωρίς «satLimit» (γραμμάρια)·
      // το όριο σε γραμμάρια μιας μέρας που πέρασε (2.250 → 15,0· 2.340 → 15,6) στο r11_h1_test.dart.
      expect([for (final d in days.keys) key(d, 'satLimit')], [null, null, null, null, null, 14.4]);
      // Round11 (R11-C1-1): ο κανόνας της διόρθωσης θερμίδων: όχι πριν από την 8η μέρα των στόχων (23/11), όχι σήμερα·
      // 60% × 2.160 = 1.296 ≤ 1.800 ≤ 6.862,5. Πριν: true για όλες (μόνο το 60%).
      expect([for (final d in days.keys) key(d, 'countsForAdaptive')], [false, false, true, true, true, false]);
      final goals = calc['goals'] as Map;
      expect((goals['inForce'] as Map)['kcal'], 2160);
      expect((goals['inForce'] as Map)['satMax'], 14.4, reason: 'πριν (2.160 × 6% ÷ 9).round() = 14');
      expect((goals['formula'] as Map)['satMax'], 15.0);
      // Ο ίδιος κανόνας με τη Διατροφή (GoalsSummaryCard: targetOn για μέρα που πέρασε).
      expect([for (final d in [16, 23, 25, 27]) targetOn(g2, DateTime(2026, 11, d))], [2250, 2250, 2250, 2340]);
    });

    test('στόχοι 2.340 με γιατρό: «inForce.satMax» 15,6 όπως το «έως 15,6 g» της οθόνης', () {
      final at = DateTime(2026, 11, 28, 12);
      final s = HealthStore()..data = Dashboard.fromJson({...sampleDashboardJson(at), 'body': bodyJson(simWeights(at))});
      s
        ..history = sampleHistory(at, s.data!)
        ..setProfile(_me)
        ..setGoals(checkinGoals(kcalSet: 2340));
      final r = diagnosticsFrom(store: s, food: FoodStore.preloaded(foods: basicFoods(), now: at), now: at);
      final inForce = ((r['calc'] as Map)['goals'] as Map)['inForce'] as Map;
      expect((inForce['kcal'], inForce['satMax']), (2340, 15.6));
      expect(satLimitText(2340, 6), 'έως 15,6 g');
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- B1-3
  group('R10-B1-3: ζυμαρικό από όσπρια: ξερό και βρασμένο μετρούν το ίδιο στα «Όσπρια»', () {
    Food pasta(String name, {String? ck}) =>
        _mine('MP', name, {Nk.kcal: 334, Nk.protein: 24, Nk.carbs: 50, Nk.fat: 2, Nk.fiber: 8}, ck: ck);

    test('ποια ξερή μορφή της βάσης', () {
      const cases = {
        'Fusilli κόκκινες φακές': 'C9810',
        'Barilla Fusilli Κόκκινες Φακές': 'C9810',
        'Πένες από ρεβίθι': 'C9810',
        'Fusilli lenticchie rosse': 'C9810',
        'Red lentil pasta': 'C9810',
        'Σπαγγέτι ολικής από φακές': 'C9870',
        // Όσπρια χωρίς λέξη ζυμαρικού: όπως πριν.
        'Φακές ψιλές': 'C20359',
        'Ρεβίθια χοντρά': 'C20516',
        'Φασόλια μέτρια': 'C20501',
      };
      for (final e in cases.entries) {
        expect(dryStapleRawId(pasta(e.key)), e.value, reason: e.key);
      }
      // Όπως έρχεται από το Open Food Facts (κατηγορία «Pastas» → «Τίποτα»): ζυμαρικό.
      expect(cholKindFromOffTags(['en:plant-based-foods', 'en:cereals-and-potatoes', 'en:pastas', 'en:lentil-pasta']), CholKind.none);
      expect(dryStapleRawId(pasta('Fusilli κόκκινες φακές', ck: CholKind.none)), 'C9810');
      // Το είπες «Όσπρια» στη φόρμα: οι μορφές των οσπρίων, για να μετρούν ξερό και βρασμένο το ίδιο.
      expect(dryStapleRawId(pasta('Fusilli κόκκινες φακές', ck: CholKind.legumes)), 'C20359');
      expect(dryStapleRawId(pasta('Πένες από ρεβίθι', ck: CholKind.legumes)), 'C20516');
    });

    test('80 g ξερά ή 200 g «Βρασμένα»: ίδια απάντηση στα «Όσπρια», ό,τι κι αν λέει το προϊόν', () {
      for (final ck in [null, CholKind.none, CholKind.legumes]) {
        final p = pasta('Fusilli κόκκινες φακές', ck: ck);
        final s = FoodStore.preloaded(foods: basicFoods(), mine: [p], now: _now);
        final states = s.statesOf(p);
        expect(states.length, 2, reason: '$ck');
        expect(identical(states.first.$1, p), isTrue, reason: '$ck');
        final dryDay = CholDay([_le(_today, states[0].$1, 80)]);
        final cookedDay = CholDay([_le(_today, states[1].$1, 200)]);
        expect(dryDay.legumes, cookedDay.legumes, reason: '$ck');
        expect(dryDay.legumes, ck == CholKind.legumes, reason: '$ck');
      }
      // Η βρασμένη μορφή του ζυμαρικού: τα βρασμένα μακαρόνια της βάσης (167 kcal στα 100 g· οι βρασμένες φακές 125).
      final p = pasta('Fusilli κόκκινες φακές');
      final cooked = FoodStore.preloaded(foods: basicFoods(), mine: [p], now: _now).statesOf(p)[1];
      expect((cooked.$1.id, cooked.$2, cooked.$1.n.amount(Nk.kcal)), ('C9811', 'Βρασμένα', 167.0));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- B1-4
  group('R10-B1-4: σαρωμένη μαργαρίνη και μαγιονέζα ανοίγουν με 10 g, όπως στη βάση· τα αλείμματα με 15 g', () {
    Food scanned(String name, List<String> tags, {required double kcal, required double protein, required double carbs, required double fat}) {
      final d = draftFromOff('2000000000024', {
        'product_name': name,
        'nutriments': {'energy-kcal_100g': kcal, 'proteins_100g': protein, 'carbohydrates_100g': carbs, 'fat_100g': fat},
        'categories_tags': tags,
      });
      expect(d.spoon, isTrue, reason: name);
      return foodFromDraft(d, 'M-$name');
    }

    test('πρώτη ποσότητα ίδια με το ίδιο τρόφιμο της βάσης', () {
      final margarine = scanned('Μαργαρίνη Χ', const ['en:fats', 'en:spreadable-fats', 'en:margarines'],
          kcal: 540, protein: 0.2, carbs: 0.5, fat: 60);
      final mayo = scanned('Μαγιονέζα Χ', const ['en:sauces', 'en:emulsified-sauces', 'en:mayonnaises'],
          kcal: 680, protein: 1.3, carbs: 3, fat: 74);
      final lightMayo = scanned('Μαγιονέζα light Χ', const ['en:sauces', 'en:emulsified-sauces', 'en:mayonnaises', 'en:light-mayonnaises'],
          kcal: 300, protein: 1, carbs: 9, fat: 28.5);
      final pralina = scanned('Πραλίνα Χ', const ['en:spreads', 'en:sweet-spreads', 'en:hazelnut-spreads', 'en:cocoa-and-hazelnuts-spreads'],
          kcal: 540, protein: 6, carbs: 57, fat: 31);
      final peanut = scanned('Φυστικοβούτυρο Χ',
          const ['en:spreads', 'en:plant-based-spreads', 'en:oilseed-purees', 'en:legume-butters', 'en:peanut-butters'],
          kcal: 610, protein: 25, carbs: 12, fat: 50);
      final tahini = scanned('Ταχίνι Χ', const ['en:spreads', 'en:plant-based-spreads', 'en:oilseed-purees', 'en:tahini'],
          kcal: 640, protein: 24, carbs: 9, fat: 55);
      expect([for (final id in ['C16591', 'C11054', 'C11079', 'C31032', 'C15202', 'C15203']) firstGrams(_byId(id))], [10, 10, 10, 15, 15, 15]);
      expect([for (final f in [margarine, mayo, lightMayo, pralina, peanut, tahini]) firstGrams(f)], [10, 10, 10, 15, 15, 15]);
      for (final f in [margarine, mayo, lightMayo, pralina, peanut, tahini]) {
        expect(isSpoonFood(f), isTrue, reason: f.name);
      }
    });

    testWidgets('«+ Φαγητό» › σαρωμένη μαργαρίνη: το πεδίο ανοίγει με «10»', (t) async {
      final margarine = scanned('Μαργαρίνη Χ', const ['en:fats', 'en:spreadable-fats', 'en:margarines'],
          kcal: 540, protein: 0.2, carbs: 0.5, fat: 60);
      final store = FoodStore.preloaded(foods: basicFoods(), mine: [margarine], now: _now);
      await _pump(t, AddFoodScreen(food: store, meal: Meal.snack, day: _today), size: const Size(400, 2400));
      await t.tap(find.text('Μαργαρίνη Χ'));
      await t.pumpAndSettle();
      final field = find.descendant(of: find.byType(QuantitySheet), matching: find.byType(TextField));
      expect(t.widget<TextField>(field).controller!.text, '10');
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- B7-5
  group('R10-B7-5 (α): στόχοι με τα παλιά επίπεδα κίνησης ανοίγουν τον οδηγό στην ίδια απάντηση (R9-A1-3)', () {
    // Άνδρας 40 ετών, 180 cm, 90 kg, −0,5%: Mifflin 1.830· −495. «Λίγο» 1.830 × 1,53 − 495 = 2.304,9 → 2.300·
    // «Πολύ» 1.830 × 1,76 − 495 = 2.725,8 → 2.730. (Με το «Μέτρια» 1,65 θα ήταν 2.520.)
    for (final (old, opt, pal, kcal) in const [(1.4, 0, 1.53, 2300), (1.7, 2, 1.76, 2730)]) {
      testWidgets('αποθηκευμένο $old → «opt-act-$opt»· χωρίς άγγιγμα αποθηκεύεται $pal και $kcal kcal', (t) async {
        final store = HealthStore()
          ..setProfile(_me)
          ..setGoals(Goals(
              aim: GoalAim.lose,
              rate: 0.005,
              activity: old,
              doctor: true,
              since: '2026-11-16',
              kg: 90,
              age: 40,
              heightCm: 180,
              male: true));
        await _pump(t, GoalsWizard(store: store, now: DateTime(2026, 11, 20, 9)));
        await t.enterText(find.byKey(const ValueKey('wizard-kg')), '90');
        await t.pumpAndSettle();
        await _next(t); // → σκοπός
        await _next(t); // → ρυθμός
        await _next(t); // → κίνηση
        for (var k = 0; k < 3; k++) {
          expect(find.descendant(of: find.byKey(ValueKey('opt-act-$k')), matching: find.byIcon(Icons.radio_button_checked_rounded)),
              k == opt ? findsOneWidget : findsNothing,
              reason: '$old: επιλογή $k');
        }
        await _next(t); // → γιατρός (το «Ναι» είναι ήδη επιλεγμένο)
        await _next(t); // → σύνοψη
        await _next(t); // αποθήκευση
        final g = store.goals!;
        expect((g.activity, g.kcal), (pal, kcal));
      });
    }
  });

  testWidgets('R10-B7-5 (β): η σελίδα «Χοληστερίνη» κρίνει την «πλήρη μέρα» με τον τωρινό στόχο, όπως η Διατροφή (R9-U2-1)',
      (t) async {
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
    expect(targetOn(g, mon), 2250, reason: 'οι θερμίδες της μέρας κρίνονται με 2.250 (60% = 1.350 > 1.300)');
    final food = FoodStore.preloaded(foods: basicFoods(), now: DateTime(2026, 12, 17, 12), entries: [
      _le(mon, _f('S', {Nk.kcal: 1300, Nk.satFat: 13}), 100),
    ]);
    await _pump(t, CholesterolPage(food: food, goals: g, today: DateTime(2026, 12, 17)), size: const Size(400, 3000));
    // 60% × 2.100 = 1.260 ≤ 1.300: πλήρης μέρα· 13 × 9 / 1.300 = 9,0%. Με τον στόχο της μέρας (1.350) δεν θα μετρούσε.
    expect(find.text('μέσος όρος 9,0% ·\u00A0στόχος έως 6%'), findsOneWidget);
    expect(find.textContaining('κάτω από 1.260 kcal'), findsOneWidget);
  });
}
