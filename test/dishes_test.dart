// «Τα φαγητά μου» (15/11): φαγητά από υλικά, που γράφονται με ένα πάτημα. Οι αναμενόμενες τιμές βγαίνουν με το χέρι
// από τις τιμές της βάσης (ανά 100 g) και τον κανόνα κάθε είδους (lib/food/dishes.dart), όχι από την υλοποίηση. Όλα τα
// φαγητά και οι ποσότητες είναι επινοημένα.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/backup.dart';
import 'package:ygeia_forma/food/dishes.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/food/week_calc.dart' show freshBatch, itemsHaveRice, potBatchOld, potKeepDays;
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/history.dart' show dateKey;
import 'package:ygeia_forma/pages/dishes.dart';
import 'package:ygeia_forma/pages/food_add.dart';
import 'package:ygeia_forma/pages/nutrition.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/widgets.dart' show PageHeaderScope;

import 'sample_food.dart';

final _now = DateTime(2026, 11, 16, 14, 5); // Δευτέρα μεσημέρι
final _today = DateTime(2026, 11, 16);

// Τιμές της βάσης ανά 100 g (assets/foods/basic_foods.json).
const lentils = 'C20359'; // Φακές (ξερές): 327 kcal, πρωτεΐνη 25,1
const onion = 'C20034'; // Κρεμμύδι ξερό (ωμό): 39 kcal
const tomato = 'C20385'; // Ντομάτα (ωμή): 19,2 kcal
const oil = 'C17270'; // Ελαιόλαδο: 899 kcal
const salt = 'C11017'; // Αλάτι: 0 kcal
const beef = 'U171812'; // Μοσχαρίσιο φιλέτο (ωμό): 153 kcal
const rice = 'C9102'; // Ρύζι καστανό (ωμό): 350 kcal
const broccoli = 'C20057'; // Μπρόκολο (ωμό): 31,9 kcal
const mince = 'C6250'; // Κιμάς 5% (ωμός): 130 kcal
const egg = 'C22000'; // Αυγό (ωμό): 140 kcal

Food f(String id) => basicFoods().firstWhere((x) => x.id == id);
DishItem it(String id, double g) => DishItem(id, f(id).name, g);

Dish lentilPot({PotBatch? batch, double? lastQty}) => Dish(
      id: 'D-lentils',
      name: 'Φακές με σάλτσα',
      kind: DishKind.pot,
      items: [it(lentils, 500), it(onion, 300), it(tomato, 400), it(oil, 60), it(salt, 8)],
      batch: batch,
      lastQty: lastQty,
      created: DateTime(2026, 11, 15).millisecondsSinceEpoch,
    );

Dish steakPlate() => Dish(
      id: 'D-steak',
      name: 'Φιλέτο με ρύζι',
      kind: DishKind.plate,
      items: [it(beef, 180), it(rice, 70), it(broccoli, 200), it(oil, 5)],
      created: DateTime(2026, 11, 14).millisecondsSinceEpoch,
    );

Dish burgers() => Dish(
      id: 'D-burgers',
      name: 'Μπιφτέκια',
      kind: DishKind.portions,
      items: [it(mince, 1000), it(onion, 100), it(egg, 100)],
      servings: 8,
      created: DateTime(2026, 11, 13).millisecondsSinceEpoch,
    );

PotBatch batchOf(Dish d, double cooked, DateTime at) => PotBatch(at: at.millisecondsSinceEpoch, cooked: cooked, items: d.items);

double kcalOf(List<DishItem> items) => Totals([
      for (final i in items) LogEntry(id: '', day: '', meal: Meal.lunch, food: f(i.id), grams: i.amount, time: DateTime(2000)),
    ]).kcal;

FoodStore store({List<Dish> dishes = const [], List<LogEntry> entries = const [], List<Food> mine = const [], DishIO? io}) =>
    FoodStore.preloaded(foods: basicFoods(), dishes: dishes, entries: entries, mine: mine, dishIO: io, now: _now);

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(420, 2400)}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: w)));
  await t.pumpAndSettle();
}

void main() {
  group('Ποσότητες: κάθε είδος με τον κανόνα του', () {
    test('Κατσαρόλα: υλικό × μερίδα ÷ έτοιμο φαγητό', () {
      final d = lentilPot();
      final b = batchOf(d, 2250, _today);
      final a = dishAmounts(d, portion: 350, batch: b);
      // 500 × 350 / 2250 = 77,777… → 77,78· 300 → 46,67· 400 → 62,22· 60 → 9,33· 8 → 1,24.
      expect([for (final i in a) i.amount], [77.78, 46.67, 62.22, 9.33, 1.24]);
      // Όλη η κατσαρόλα: 327×5 + 39×3 + 19,2×4 + 899×0,6 = 2.368,2 kcal· η μερίδα 350/2250 → 368,39 kcal.
      expect(kcalOf(a), closeTo(2368.2 * 350 / 2250, 0.3));
    });

    test('Ίσες μερίδες: υλικό × έφαγα ÷ μερίδες', () {
      final a = dishAmounts(burgers(), servings: 2);
      expect([for (final i in a) i.amount], [250, 25, 25]);
      // 130×2,5 + 39×0,25 + 140×0,25 = 369,75.
      expect(kcalOf(a), closeTo(369.75, 0.01));
    });

    test('Πιάτο: ό,τι έγραψες για κάθε υλικό· το 0 δεν γράφεται', () {
      final d = steakPlate();
      expect(kcalOf(dishAmounts(d)), closeTo(153 * 1.8 + 350 * 0.7 + 31.9 * 2 + 899 * 0.05, 0.01));
      final a = dishAmounts(d, plate: [200, 0, 150, 5]);
      expect([for (final i in a) i.id], [beef, broccoli, oil]);
      expect([for (final i in a) i.amount], [200, 150, 5]);
    });

    test('Ποσότητα που στρογγυλεύεται σε 0 δεν γράφεται ποτέ (η επαναφορά δεν θα τη δεχόταν)', () {
      final d = Dish(
        id: 'x',
        name: 'Μεγάλη κατσαρόλα',
        kind: DishKind.pot,
        items: [it(lentils, 2000), it(salt, 1)],
        created: 0,
      );
      final a = dishAmounts(d, portion: 20, batch: batchOf(d, 9000, _today));
      // αλάτι 1 × 20 / 9000 = 0,0022 g → 0,00: έξω. Οι φακές 4,44 g μένουν.
      expect([for (final i in a) i.id], [lentils]);
      expect(a.single.amount, 4.44);
    });

    test('Έτοιμο φαγητό πολύ πιο ελαφρύ από τα ωμά υλικά: ρωτά (κάτω από 40%)', () {
      expect(cookedLooksWrong(1268, 2250), isFalse);
      expect(cookedLooksWrong(1000, 700), isFalse, reason: 'ψητό: χάνει περίπου 30%');
      expect(cookedLooksWrong(1268, 450), isTrue);
    });
  });

  group('Αποθήκευση: το φαγητό όπως ήταν, και τίποτα παράλογο', () {
    test('JSON πάει και έρχεται, με κλειδιά νεότερης έκδοσης που μένουν', () {
      final d = lentilPot(batch: batchOf(lentilPot(), 2250, _today), lastQty: 350);
      final j = {...d.toJson(), 'steps': ['Πλύνε τις φακές']};
      final back = Dish.fromJson(jsonDecode(jsonEncode(j)))!;
      expect(back.name, d.name);
      expect(back.kind, DishKind.pot);
      expect([for (final i in back.items) i.amount], [500, 300, 400, 60, 8]);
      expect(back.batch!.cooked, 2250);
      expect(back.lastQty, 350);
      expect(back.toJson()['steps'], ['Πλύνε τις φακές'], reason: 'κλειδί νεότερης έκδοσης δεν χάνεται');
    });

    test('Χαλασμένο φαγητό δεν διαβάζεται', () {
      Map<String, Object?> ok() => steakPlate().toJson();
      expect(Dish.fromJson(ok()), isNotNull);
      for (final bad in <Map<String, Object?>>[
        {...ok(), 'name': '  '},
        {...ok(), 'kind': 'soup'},
        {...ok(), 'items': []},
        {
          ...ok(),
          'items': [
            {'id': beef, 'n': 'x', 'g': -5}
          ]
        },
        {
          ...ok(),
          'items': [
            {'id': beef, 'n': 'x', 'g': 1e9}
          ]
        },
        {...burgers().toJson(), 'serv': 0},
        {...burgers().toJson(), 'serv': 500},
      ]) {
        expect(Dish.fromJson(bad), isNull, reason: '$bad');
      }
    });

    test('Καταχώριση με σημάδι φαγητού: πάει και έρχεται· χαλασμένο σημάδι = απλό τρόφιμο, ποτέ χαμένη καταχώριση', () {
      final e = LogEntry(
        id: 'e1',
        day: '2026-11-16',
        meal: Meal.lunch,
        food: f(lentils),
        grams: 77.78,
        time: _now,
        dish: const DishTag(id: 'D-lentils', name: 'Φακές με σάλτσα', grp: 'g1', kind: DishKind.pot, qty: 350, batch: 123),
      );
      final back = LogEntry.fromJson(jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>);
      expect(back.dish!.grp, 'g1');
      expect(back.dish!.kind, DishKind.pot);
      expect(back.dish!.qty, 350);
      expect(back.dish!.batch, 123);
      final broken = {...e.toJson(), 'dish': {'grp': '', 'k': 'pot'}};
      final plain = LogEntry.fromJson(jsonDecode(jsonEncode(broken)) as Map<String, dynamic>);
      expect(plain.dish, isNull);
      expect(plain.grams, 77.78);
      // Χωρίς φαγητό: το JSON ίδιο με πριν (καμία αλλαγή για τις παλιές καταχωρίσεις).
      expect(LogEntry(id: 'a', day: '2026-11-16', meal: Meal.lunch, food: f(egg), grams: 50, time: _now).toJson().containsKey('dish'),
          isFalse);
    });
  });

  group('Καταγραφή: όλα τα υλικά μαζί, μετρούν όπως πάντα', () {
    test('Κατσαρόλα: 5 καταχωρίσεις, ίδια καταγραφή, θερμίδες όσο η μερίδα· το φαγητό θυμάται μαγείρεμα και μερίδα', () async {
      final d = lentilPot();
      final s = store(dishes: [d]);
      final b = batchOf(d, 2250, _now);
      final out = await s.logDish(d, dishAmounts(d, portion: 350, batch: b), meal: Meal.lunch, qty: 350, batch: b, now: _now);
      expect(out, hasLength(5));
      expect(out!.map((e) => e.dish!.grp).toSet(), hasLength(1));
      expect(out.every((e) => e.dish!.kind == DishKind.pot && e.dish!.qty == 350 && e.dish!.batch == b.at), isTrue);
      final day = s.entriesFor(_today);
      expect(day, hasLength(5));
      expect(Totals(day).kcal, closeTo(2368.2 * 350 / 2250, 0.3));
      final after = s.dishById(d.id)!;
      expect(after.uses, 1);
      expect(after.lastQty, 350);
      expect(after.batch!.cooked, 2250);
      expect(after.used, _now.millisecondsSinceEpoch);
    });

    test('Τα υλικά ενός φαγητού δεν μετρούν στα Συχνά/Πρόσφατα ούτε ως «ποσότητα της τελευταίας φοράς»', () async {
      final d = lentilPot();
      final s = store(dishes: [d]);
      final b = batchOf(d, 2250, _now);
      await s.logDish(d, dishAmounts(d, portion: 350, batch: b), meal: Meal.lunch, qty: 350, batch: b, now: _now);
      expect(s.lastGrams(lentils), isNull);
      expect(s.timesEaten(lentils), 0);
      expect(s.recent(), isEmpty);
      // Ένα απλό τρόφιμο μετρά κανονικά.
      await s.add(f(lentils), 60, Meal.dinner, now: _now);
      expect(s.lastGrams(lentils), 60);
      expect(s.recent().single.id, lentils);
    });

    test('Υλικό που δεν υπάρχει πια (σβησμένο προϊόν): το φαγητό δεν γράφεται', () async {
      final mine = Food(id: 'M-sauce', name: 'Σάλτσα (δοκιμή)', cat: 'Σάλτσες', source: 'Ετικέτα', n: Nutrients({Nk.kcal: const NValue(80)}));
      final d = Dish(id: 'D-m', name: 'Με σάλτσα', kind: DishKind.plate, items: [it(rice, 70), DishItem('M-sauce', 'Σάλτσα (δοκιμή)', 50)], created: 0);
      final s = store(dishes: [d], mine: [mine]);
      expect(s.missingItems(d.items), isEmpty);
      await s.deleteMyFood(mine);
      expect(s.missingItems(d.items), ['Σάλτσα (δοκιμή)']);
      expect(await s.logDish(d, dishAmounts(d), meal: Meal.lunch, qty: 120, now: _now), isNull);
      expect(s.entriesFor(_today), isEmpty);
    });

    test('«Όπως χθες»: το φαγητό ξαναγράφεται ως νέα καταγραφή· με υλικό που σβήστηκε, ούτε τα υπόλοιπα υλικά του', () async {
      final mine = Food(id: 'M-sauce', name: 'Σάλτσα (δοκιμή)', cat: 'Σάλτσες', source: 'Ετικέτα', n: Nutrients({Nk.kcal: const NValue(80)}));
      final steak = steakPlate();
      final withSauce =
          Dish(id: 'D-m', name: 'Με σάλτσα', kind: DishKind.plate, items: [it(rice, 70), DishItem('M-sauce', 'Σάλτσα (δοκιμή)', 50)], created: 0);
      final s = store(dishes: [steak, withSauce], mine: [mine]);
      final yesterday = DateTime(2026, 11, 15);
      final first = await s.logDish(steak, dishAmounts(steak), meal: Meal.lunch, qty: 455, on: yesterday, now: _now);
      await s.logDish(withSauce, dishAmounts(withSauce), meal: Meal.lunch, qty: 120, on: yesterday, now: _now);
      await s.add(f(egg), 50, Meal.lunch, on: yesterday, now: _now);
      await s.deleteMyFood(mine);
      // Από το «Με σάλτσα» δεν ξαναγράφεται τίποτα (ούτε το ρύζι του): 4 υλικά του φιλέτου + το αυγό.
      expect(s.copyable(yesterday, Meal.lunch), hasLength(5));
      expect(s.notCopyable(yesterday, Meal.lunch), 2);
      final copied = await s.copyMeal(yesterday, Meal.lunch, _today);
      expect(copied, hasLength(5));
      final dishCopies = copied.where((e) => e.dish != null).toList();
      expect(dishCopies, hasLength(4));
      expect(dishCopies.map((e) => e.dish!.grp).toSet(), hasLength(1));
      expect(dishCopies.first.dish!.grp, isNot(first!.first.dish!.grp), reason: 'νέα καταγραφή, όχι η χθεσινή');
      expect([for (final e in dishCopies) e.grams], [180, 70, 200, 5]);
    });

    test('Διαγραφή και «Αναίρεση» όλου του φαγητού', () async {
      final d = burgers();
      final s = store(dishes: [d]);
      final out = await s.logDish(d, dishAmounts(d, servings: 2), meal: Meal.dinner, qty: 2, now: _now);
      expect(s.groupOf(out!.first), hasLength(3));
      expect(await s.removeGroup(out), isTrue);
      expect(s.entriesFor(_today), isEmpty);
      expect(await s.restoreGroup(out), isTrue);
      expect(s.entriesFor(_today), hasLength(3));
    });

    test('Διαφορετικά id για όλα τα υλικά (ακόμα και στο ίδιο μικροδευτερόλεπτο)', () async {
      final d = Dish(id: 'D-big', name: 'Πολλά υλικά', kind: DishKind.plate, items: [for (var k = 0; k < 40; k++) it(broccoli, 10 + k.toDouble())], created: 0);
      final s = store(dishes: [d]);
      final out = await s.logDish(d, dishAmounts(d), meal: Meal.lunch, qty: 1180, now: _now);
      expect(out!.map((e) => e.id).toSet(), hasLength(40));
      expect(s.entriesFor(_today), hasLength(40));
    });
  });

  group('Το αρχείο των φαγητών', () {
    test('Γράφεται και ξαναδιαβάζεται', () async {
      final io = MemoryDishIO();
      final s = store(io: io);
      await s.loadDishes();
      expect(s.dishesRead, isTrue);
      expect(await s.saveDish(lentilPot()), isTrue);
      expect(await s.saveDish(steakPlate()), isTrue);
      final s2 = store(io: io);
      await s2.loadDishes();
      expect(s2.dishes.map((d) => d.id).toSet(), {'D-lentils', 'D-steak'});
      expect(await s2.deleteDish(s2.dishById('D-steak')!), isTrue);
      final s3 = store(io: io);
      await s3.loadDishes();
      expect(s3.dishes.single.id, 'D-lentils');
    });

    test('Δεν διαβάζεται καθόλου: μπαίνει στην άκρη (όχι σβήσιμο), η λίστα ξεκινά άδεια και ξαναγράφεται', () async {
      final io = MemoryDishIO('{χαλασμένο');
      final s = store(io: io);
      await s.loadDishes();
      expect(io.setAsideJson, '{χαλασμένο');
      expect(s.dishesRead, isTrue);
      expect(s.dishesNote, contains('Κρατήθηκε στην άκρη'));
      expect(await s.saveDish(steakPlate()), isTrue);
    });

    test('Δεν διαβάστηκε (σφάλμα ανάγνωσης): ΤΙΠΟΤΑ δεν γράφεται, για να μη χαθεί ό,τι έχει', () async {
      final io = MemoryDishIO('{"v":1,"dishes":[]}')..unreadable = true;
      final s = store(io: io);
      await s.loadDishes();
      expect(s.dishesRead, isFalse);
      expect(await s.saveDish(steakPlate()), isFalse);
      expect(io.writes, 0);
      expect(s.saveError, isNotNull);
      expect(s.dishesForBackup(), isNull);
    });

    test('Νεότερη έκδοση: διαβάζεται, αλλά δεν ξαναγράφεται', () async {
      final io = MemoryDishIO(jsonEncode({'v': 2, 'dishes': [steakPlate().toJson()]}));
      final s = store(io: io);
      await s.loadDishes();
      expect(s.dishes.single.id, 'D-steak');
      expect(s.dishesNote, FoodStore.dishesNewerText);
      expect(await s.saveDish(lentilPot()), isFalse);
      expect(io.writes, 0);
    });

    test('Ένα χαλασμένο φαγητό μένει όπως είναι και ξαναγράφεται όπως ήταν', () async {
      final bad = {'id': 'D-bad', 'name': 'Χωρίς υλικά', 'kind': 'plate', 'items': []};
      final io = MemoryDishIO(jsonEncode({'v': 1, 'dishes': [steakPlate().toJson(), bad]}));
      final s = store(io: io);
      await s.loadDishes();
      expect(s.dishes.single.id, 'D-steak');
      expect(s.skippedRows, 1);
      await s.saveDish(lentilPot());
      final written = (jsonDecode(io.json!) as Map)['dishes'] as List;
      expect(written, hasLength(3));
      expect(written.any((x) => (x as Map)['id'] == 'D-bad'), isTrue);
    });

    test('Αποτυχία εγγραφής: η λίστα γυρίζει όπως ήταν και βγαίνει μήνυμα', () async {
      final io = MemoryDishIO();
      final s = store(io: io);
      await s.loadDishes();
      io.failWrites = true;
      expect(await s.saveDish(steakPlate()), isFalse);
      expect(s.dishes, isEmpty);
      expect(s.saveError, contains('Φιλέτο με ρύζι'));
    });
  });

  group('Αντίγραφο', () {
    test('Τα φαγητά μπαίνουν στο αρχείο και διαβάζονται· χαλασμένο ή διπλό φαγητό μετρά ως χαλασμένη εγγραφή', () {
      final json = buildBackup(
        foodLog: const [],
        myFoods: const [],
        prefs: const {},
        now: _now,
        dishes: [lentilPot().toJson(), steakPlate().toJson(), steakPlate().toJson(), {'id': 'x'}],
      );
      final b = parseBackup(json);
      expect(b.dishes.map((d) => d.id), ['D-lentils', 'D-steak']);
      expect(b.skipped, 2);
    });

    test('Αντίγραφο χωρίς φαγητά (παλιό): καμία αλλαγή', () {
      final b = parseBackup(buildBackup(foodLog: const [], myFoods: const [], prefs: const {}, now: _now));
      expect(b.dishes, isEmpty);
      expect(b.skipped, 0);
    });

    test('Επαναφορά: μπαίνουν μόνο όσα λείπουν· όσα υπάρχουν μένουν όπως είναι', () async {
      final mineSteak = Dish(
        id: 'D-steak',
        name: 'Φιλέτο (αλλαγμένο στο κινητό)',
        kind: DishKind.plate,
        items: [it(beef, 200)],
        created: 0,
      );
      final s = store(dishes: [mineSteak]);
      final r = await s.importDishes([steakPlate(), lentilPot()]);
      expect(r, (1, 1));
      expect(s.dishById('D-steak')!.name, 'Φιλέτο (αλλαγμένο στο κινητό)');
      expect(s.dishById('D-lentils'), isNotNull);
    });
  });

  group('Αναζήτηση και «ένα πάτημα»', () {
    test('Χωρίς τόνους, σε greeklish, και με αρχή λέξης', () {
      final all = [lentilPot(), steakPlate(), burgers()];
      expect(searchDishes(all, 'fakes').single.id, 'D-lentils');
      expect(searchDishes(all, 'σαλτσα').single.id, 'D-lentils');
      expect(searchDishes(all, 'μπιφτ').single.id, 'D-burgers');
      expect(searchDishes(all, 'φιλετο ρυζι').single.id, 'D-steak');
      expect(searchDishes(all, 'ψάρι'), isEmpty);
    });

    test('Κατσαρόλα: από το ίδιο μαγείρεμα ως 2 μέρες μετά· από την 3η, ή χωρίς ζυγισμένο φαγητό, ανοίγει η οθόνη', () {
      final d0 = lentilPot();
      final s = store();
      expect(quickDishResult(s, d0, Meal.lunch, _now), isNull, reason: 'δεν έχει ζυγιστεί ποτέ');
      final fresh = lentilPot(batch: batchOf(d0, 2250, DateTime(2026, 11, 14, 20)), lastQty: 350);
      final r = quickDishResult(s, fresh, Meal.lunch, _now)!;
      expect(r.qty, 350);
      expect(r.amounts.first.amount, 77.78);
      final old = lentilPot(batch: batchOf(d0, 2250, DateTime(2026, 11, 13, 20)), lastQty: 350);
      expect(quickDishResult(s, old, Meal.lunch, _now), isNull);
    });

    test('Α2 (απόφαση 21/11): ένα πάτημα ως 2 μέρες μετά το μαγείρεμα· με ρύζι ως την επόμενη μέρα', () {
      // Πριν: ως 3 μέρες μετά, και για φαγητό με ρύζι· το πρόγραμμα του AI δεν βάζει ποτέ περίσσευμα τόσο αργά (FSA: 48 ώρες).
      final s = store();
      final d0 = lentilPot();
      bool quick(Dish d) => quickDishResult(s, d, Meal.lunch, _now) != null;
      Dish cooked(int daysAgo) =>
          lentilPot(batch: batchOf(d0, 2250, DateTime(_now.year, _now.month, _now.day - daysAgo, 20)), lastQty: 350);
      expect([for (final n in [0, 1, 2, 3, 4]) quick(cooked(n))], [true, true, true, false, false]);
      expect((potQuickDays, potRiceQuickDays), (3, 2));
      // Το ίδιο όριο και για τη θέση του προγράμματος («Το έφαγα») και για την κάρτα του μαγειρέματος.
      expect([for (final n in [0, 2, 3]) freshBatch(s, cooked(n), _now) != null], [true, true, false]);
      expect([for (final n in [2, 3]) potBatchOld(s, cooked(n).batch!, _now)], [false, true]);
      // Με ρύζι στο μαγείρεμα: τη μέρα του μαγειρέματος και την επόμενη.
      final rice = basicFoods().firstWhere((x) => x.name.startsWith('Ρύζι'));
      PotBatch riceBatch(int daysAgo) {
        final b = cooked(daysAgo).batch!;
        return PotBatch(items: [...b.items, DishItem(rice.id, rice.name, 300)], cooked: b.cooked, at: b.at);
      }

      expect(itemsHaveRice(s, riceBatch(0).items), isTrue);
      expect(itemsHaveRice(s, d0.items), isFalse);
      expect([for (final n in [0, 1, 2]) potBatchOld(s, riceBatch(n), _now)], [false, false, true]);
      expect((potKeepDays(s, riceBatch(0).items), potKeepDays(s, d0.items)), (2, 3));
      expect(potOldNote(true), 'Φαγητό με ρύζι κρατά στο ψυγείο ως την επόμενη μέρα.');
      expect(potOldNote(false), 'Τα περισσεύματα κρατούν στο ψυγείο ως 2 μέρες.');
    });

    test('Πιάτο: όπως την τελευταία φορά· μερίδες: όσες την τελευταία φορά (αλλιώς 1)', () {
      final s = store();
      final p = steakPlate().copyWith(lastPlate: [200, 70, 150, 5]);
      final r = quickDishResult(s, p, Meal.lunch, _now)!;
      expect([for (final i in r.amounts) i.amount], [200, 70, 150, 5]);
      expect(r.qty, 425);
      expect(quickDishResult(s, burgers(), Meal.dinner, _now)!.qty, 1);
    });
  });

  group('Οθόνες', () {
    testWidgets('Ημερολόγιο: το φαγητό είναι μία γραμμή, με τις θερμίδες όλων των υλικών του', (t) async {
      final d = lentilPot();
      final s = store(dishes: [d]);
      final b = batchOf(d, 2250, _now);
      final out = await s.logDish(d, dishAmounts(d, portion: 350, batch: b), meal: Meal.lunch, qty: 350, batch: b, now: _now);
      await s.add(f(egg), 50, Meal.lunch, now: _now);
      await _pump(
          t, PageHeaderScope(header: const SizedBox.shrink(), child: FoodTheme(child: NutritionPage(food: s, now: _now))));
      expect(find.byKey(ValueKey('dish-row-${out!.first.dish!.grp}')), findsOneWidget);
      expect(find.text('Φακές με σάλτσα'), findsOneWidget);
      expect(find.text('Φακές (ξερές)'), findsNothing, reason: 'τα υλικά δεν φαίνονται χωριστά');
      expect(find.text(thousands(Totals(out).shownKcal)), findsOneWidget);
      expect(find.textContaining('350 g'), findsOneWidget);
      // Δύο γραμμές στο γεύμα: «Κράτα το ως φαγητό».
      expect(find.byKey(const ValueKey('save-dish-lunch')), findsOneWidget);
    });

    testWidgets('Ημερολόγιο: αλλαγή μερίδας κατσαρόλας = όλα τα υλικά στην ίδια αναλογία', (t) async {
      final d = lentilPot();
      final s = store(dishes: [d]);
      final b = batchOf(d, 2250, _now);
      final out = await s.logDish(d, dishAmounts(d, portion: 350, batch: b), meal: Meal.lunch, qty: 350, batch: b, now: _now);
      await _pump(
          t, PageHeaderScope(header: const SizedBox.shrink(), child: FoodTheme(child: NutritionPage(food: s, now: _now))));
      await t.tap(find.byKey(ValueKey('dish-row-${out!.first.dish!.grp}')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('dish-entry-qty')), '175');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('dish-entry-save')));
      await t.pumpAndSettle();
      final day = s.entriesFor(_today);
      expect(day, hasLength(5));
      expect(day.first.grams, closeTo(77.78 / 2, 0.01));
      expect(day.every((e) => e.dish!.qty == 175), isTrue);
      expect(Totals(day).kcal, closeTo(2368.2 * 175 / 2250, 0.3));
    });

    testWidgets('Καταγραφή κατσαρόλας: βάρος του έτοιμου + μερίδα → σωστές ποσότητες', (t) async {
      final d = lentilPot();
      final s = store(dishes: [d]);
      DishLogResult? got;
      await _pump(
        t,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => got = await openDishLogSheet(context, s, d, meal: Meal.lunch, now: () => _now),
            child: const Text('άνοιξε'),
          ),
        ),
      );
      await t.tap(find.text('άνοιξε'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dish-cooked')), findsOneWidget, reason: 'πρώτη φορά: ζυγίζεις το έτοιμο φαγητό');
      await t.enterText(find.byKey(const ValueKey('dish-cooked')), '2.250');
      await t.enterText(find.byKey(const ValueKey('dish-portion')), '350');
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('dish-log-add')));
      await t.tap(find.byKey(const ValueKey('dish-log-add')));
      await t.pumpAndSettle();
      expect(got, isNotNull);
      expect(got!.qty, 350);
      expect(got!.batch!.cooked, 2250);
      expect([for (final i in got!.amounts) i.amount], [77.78, 46.67, 62.22, 9.33, 1.24]);
    });

    testWidgets('Καταγραφή κατσαρόλας: μερίδα μεγαλύτερη από όλο το φαγητό δεν γράφεται', (t) async {
      final d = lentilPot(batch: batchOf(lentilPot(), 600, _now));
      final s = store(dishes: [d]);
      await _pump(
        t,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => openDishLogSheet(context, s, d, meal: Meal.lunch, now: () => _now),
            child: const Text('άνοιξε'),
          ),
        ),
      );
      await t.tap(find.text('άνοιξε'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('dish-portion')), '700');
      await t.pumpAndSettle();
      expect(find.textContaining('μεγαλύτερη από όλο το φαγητό'), findsOneWidget);
      final add = t.widget<FilledButton>(find.byKey(const ValueKey('dish-log-add')));
      expect(add.onPressed, isNull);
    });

    testWidgets('Νέο φαγητό από υλικά: αποθηκεύεται με είδος και μερίδες', (t) async {
      final s = store();
      await _pump(t, DishEditScreen(food: s, items: [it(mince, 1000), it(onion, 100), it(egg, 100)], clock: () => _now));
      await t.enterText(find.byKey(const ValueKey('dish-name')), 'Μπιφτέκια φούρνου');
      await t.tap(find.byKey(const ValueKey('dish-kind-portions')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('dish-serv')), '8');
      await t.pumpAndSettle();
      // Μία μερίδα: (130×10 + 39×1 + 140×1) / 8 = 184,9 kcal.
      expect(find.text(kcalText((1300 + 39 + 140) / 8)), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('dish-save')));
      await t.tap(find.byKey(const ValueKey('dish-save')));
      await t.pumpAndSettle();
      final d = s.dishes.single;
      expect(d.name, 'Μπιφτέκια φούρνου');
      expect(d.kind, DishKind.portions);
      expect(d.servings, 8);
      expect(d.items.map((i) => i.id), [mince, onion, egg]);
    });

    testWidgets('Νέο φαγητό: χωρίς όνομα δεν αποθηκεύεται και το λέει', (t) async {
      final s = store();
      await _pump(t, DishEditScreen(food: s, items: [it(rice, 70)]));
      await t.ensureVisible(find.byKey(const ValueKey('dish-save')));
      await t.tap(find.byKey(const ValueKey('dish-save')));
      await t.pumpAndSettle();
      expect(s.dishes, isEmpty);
      expect(find.textContaining('Γράψε ένα όνομα'), findsOneWidget);
    });

    testWidgets('«+ Φαγητό»: το «+» του φαγητού το γράφει αμέσως, όπως την τελευταία φορά, με «Αναίρεση»', (t) async {
      final d = burgers().copyWith(lastQty: 2);
      final s = store(dishes: [d]);
      await _pump(t, AddFoodScreen(food: s, meal: Meal.dinner, day: _today));
      expect(find.byKey(const ValueKey('add-dishes')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('dish-quick-D-burgers')));
      await t.pumpAndSettle();
      final day = s.entriesFor(_today);
      expect(day, hasLength(3));
      expect(day.every((e) => e.meal == Meal.dinner && e.dish!.qty == 2), isTrue);
      expect(Totals(day).kcal, closeTo(369.75, 0.01));
      expect(find.textContaining('Μπιφτέκια, 2 μερίδες'), findsOneWidget);
      await t.tap(find.text('Αναίρεση'));
      await t.pumpAndSettle();
      expect(s.entriesFor(_today), isEmpty);
      expect(s.dishById('D-burgers')!.uses, 0, reason: 'το φαγητό γυρίζει όπως ήταν');
    });

    testWidgets('«+ Φαγητό»: τα φαγητά βγαίνουν και στην αναζήτηση, πρώτα', (t) async {
      final s = store(dishes: [lentilPot(), steakPlate()]);
      await _pump(t, AddFoodScreen(food: s, meal: Meal.lunch, day: _today));
      await t.enterText(find.byType(TextField).first, 'fakes');
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dish-D-lentils')), findsOneWidget);
      expect(find.byKey(const ValueKey('dish-D-steak')), findsNothing);
      final dishY = t.getTopLeft(find.byKey(const ValueKey('dish-D-lentils'))).dy;
      final foodY = t.getTopLeft(find.text('Φακές (ξερές)').first).dy;
      expect(dishY, lessThan(foodY));
    });

    testWidgets('Υλικό: η οθόνη επιλογής δεν έχει γεύμα ούτε φαγητά, και κλείνει με το υλικό', (t) async {
      final s = store(dishes: [steakPlate()]);
      IngredientPick? got;
      await _pump(
        t,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => got = await pickIngredient(context, s, dishName: 'Δοκιμή'),
            child: const Text('υλικό'),
          ),
        ),
      );
      await t.tap(find.text('υλικό'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('add-ingredient-for')), findsOneWidget);
      expect(find.byKey(const ValueKey('add-dishes')), findsNothing);
      expect(find.byKey(const ValueKey('meal-bar-lunch')), findsNothing);
      await t.enterText(find.byType(TextField).first, 'φακές ξερές');
      await t.pumpAndSettle();
      await t.tap(find.text('Φακές (ξερές)').first);
      await t.pumpAndSettle();
      expect(find.text('Βάλ’ το στο φαγητό'), findsOneWidget);
      await t.enterText(find.byType(TextField).last, '500');
      await t.pumpAndSettle();
      await t.tap(find.text('Βάλ’ το στο φαγητό'));
      await t.pumpAndSettle();
      expect(got!.food.id, lentils);
      expect(got!.amount, 500);
      expect(s.entriesFor(_today), isEmpty, reason: 'τίποτα στο ημερολόγιο');
    });
  });

  test('Fixtures: ημερομηνίες της δοκιμής', () {
    expect(dateKey(_today), '2026-11-16');
  });
}
