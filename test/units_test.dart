// Κομμάτια, «Ζύγισα ένα» και «Εκτίμηση» (16/11). Επινοημένα δεδομένα.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/adaptive_check.dart' show estimatedShare, estimatedShareText;
import 'package:ygeia_forma/backup.dart';
import 'package:ygeia_forma/food/dishes.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/food/units.dart';
import 'package:ygeia_forma/pages/food_add.dart';
import 'package:ygeia_forma/theme.dart';

import 'sample_food.dart';

final now = DateTime(2026, 11, 18, 14);
final today = DateTime(2026, 11, 18);

Food f(String id) => basicFoods().firstWhere((x) => x.id == id);

void main() {
  test('Ο πίνακας κομματιών δείχνει μόνο τρόφιμα της βάσης, με βάρη σε σειρά', () {
    final ids = basicFoods().map((x) => x.id).toSet();
    for (final e in pieceUnits.entries) {
      expect(ids, contains(e.key), reason: e.key);
      final g = [for (final s in e.value.sizes) s.grams];
      expect(g, [...g]..sort(), reason: e.key);
      expect(g.every((x) => x > 0 && x < 400), isTrue, reason: e.key);
    }
  });

  test('Κείμενο κομματιών: γένος και αριθμός', () {
    final b = pieceUnits['C13005']!;
    expect(pieceText(b, b.sizes[1], 1), '1 μεσαία μπανάνα');
    expect(pieceText(b, b.sizes[1], 2), '2 μεσαίες μπανάνες');
    final a = pieceUnits['C13039']!;
    expect(pieceText(a, a.sizes[2], 3), '3 μεγάλα μήλα');
    final egg = pieceUnits['C22000']!;
    expect(pieceText(egg, egg.sizes[1], 2), '2 αυγά L');
    final k = pieceUnits['C13021']!;
    expect(pieceText(k, k.sizes.single, 2), '2 ακτινίδια');
  });

  test('Εκτίμηση: γράφεται και διαβάζεται· τα σύνολα ξέρουν πόσο ήταν εκτίμηση', () {
    final e = LogEntry(id: 'a', day: '2026-11-18', meal: Meal.lunch, food: f('C13005'), grams: 118, time: now, est: true);
    final j = jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>;
    expect(j['est'], true);
    expect(LogEntry.fromJson(j).est, isTrue);
    final plain = e.copyWith(est: false);
    expect(plain.toJson().containsKey('est'), isFalse, reason: 'οι παλιές εγγραφές μένουν ίδιες');
    final t = Totals([e, plain.copyWith(id: 'b')]);
    expect(t.estKcal, closeTo(t.kcal / 2, 0.001));
  });

  group('Ζύγισα ένα', () {
    test('Μένει στο αρχείο των φαγητών, ξαναδιαβάζεται, σβήνει· λάθος τιμή δεν γράφεται', () async {
      final io = MemoryDishIO();
      final s = FoodStore.preloaded(foods: basicFoods(), dishIO: io, now: now);
      await s.loadDishes();
      expect(await s.setMyUnit('C13005', 125), isTrue);
      expect(await s.setMyUnit('C13039', 0.2), isFalse);
      expect(jsonDecode(io.json!)['units'], {'C13005': 125.0});
      final s2 = FoodStore.preloaded(foods: basicFoods(), dishIO: MemoryDishIO(io.json), now: now);
      await s2.loadDishes();
      expect(s2.myUnit('C13005'), 125);
      expect(await s2.setMyUnit('C13005', null), isTrue);
      expect(s2.myUnit('C13005'), isNull);
    });

    test('Αντίγραφο: γράφεται, και στην επαναφορά μπαίνουν μόνο όσα λείπουν', () async {
      final text = buildBackup(
          foodLog: const [], myFoods: const [], prefs: const {}, now: now, foodUnits: const {'C13005': 125, 'C13039': 190});
      final b = parseBackup(text);
      final s = FoodStore.preloaded(foods: basicFoods(), dishIO: MemoryDishIO(), now: now);
      await s.loadDishes();
      await s.setMyUnit('C13005', 110);
      expect(await s.importUnits(b.units), 1);
      expect(s.myUnit('C13005'), 110);
      expect(s.myUnit('C13039'), 190);
    });
  });

  test('Φαγητό της βιβλιοθήκης που παραγγέλνεις: γράφεται πάντα ως εκτίμηση', () async {
    final s = FoodStore.preloaded(foods: basicFoods(), dishIO: MemoryDishIO(), now: now);
    await s.loadDishes();
    Dish dish(String id, String cook) => Dish(
          id: id,
          name: 'Σουβλάκι $id',
          kind: DishKind.plate,
          items: const [DishItem('C13005', 'Μπανάνα', 100)],
          created: now.millisecondsSinceEpoch,
          extra: {
            'plan': {'key': id, 'cook': cook}
          },
        );
    final out = await s.logDish(dish('o', 'out'), const [DishItem('C13005', 'Μπανάνα', 100)], meal: Meal.lunch, qty: 100, now: now);
    expect(out!.single.est, isTrue);
    final home =
        await s.logDish(dish('h', 'home'), const [DishItem('C13005', 'Μπανάνα', 100)], meal: Meal.lunch, qty: 100, now: now);
    expect(home!.single.est, isFalse);
    final asked = await s.logDish(dish('h', 'home'), const [DishItem('C13005', 'Μπανάνα', 100)],
        meal: Meal.lunch, qty: 100, now: now, est: true);
    expect(asked!.single.est, isTrue);
  });

  test('Μερίδιο εκτίμησης στον έλεγχο: μόνο από 15% και πάνω', () async {
    final s = FoodStore.preloaded(foods: basicFoods(), now: now);
    await s.add(f('C13005'), 900, Meal.lunch, on: today, now: now);
    await s.add(f('C13005'), 100, Meal.lunch, on: today, now: now, est: true);
    final share = estimatedShare(s, today, today)!;
    expect(share, closeTo(0.1, 0.0001));
    expect(estimatedShareText(share), isNull);
    await s.add(f('C13005'), 300, Meal.dinner, on: today, now: now, est: true);
    expect(estimatedShareText(estimatedShare(s, today, today)), startsWith('Το 31% των θερμίδων'));
  });

  testWidgets('Φύλλο ποσότητας: 2 μεσαίες μπανάνες = 236 g, εκτίμηση· «Ζύγισα ένα» → το δικό σου, όχι εκτίμηση', (t) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(420, 2600);
    addTearDown(t.view.reset);
    final s = FoodStore.preloaded(foods: basicFoods(), dishIO: MemoryDishIO(), now: now);
    await s.loadDishes();
    Object? got;
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              got = await showModalBottomSheet<Object>(
                context: ctx,
                isScrollControlled: true,
                builder: (_) => QuantitySheet(food: s, item: f('C13005'), initialGrams: 100, meal: Meal.snack),
              );
            },
            child: const Text('άνοιγμα'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('άνοιγμα'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('piece-1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('piece-more')));
    await t.pumpAndSettle();
    expect(find.text('2 μεσαίες μπανάνες'), findsOneWidget);
    expect(find.widgetWithText(TextField, '236'), findsOneWidget);
    expect(t.widget<SwitchListTile>(find.byKey(const ValueKey('estimate-switch'))).value, isTrue);

    await t.tap(find.byKey(const ValueKey('unit-weigh')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('unit-weigh-field')), '125');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('unit-weigh-save')));
    await t.pumpAndSettle();
    expect(s.myUnit('C13005'), 125);
    expect(find.widgetWithText(TextField, '250'), findsOneWidget, reason: '2 × 125 g');
    expect(t.widget<SwitchListTile>(find.byKey(const ValueKey('estimate-switch'))).value, isFalse);

    await t.ensureVisible(find.text('Προσθήκη στο Σνακ'));
    await t.tap(find.text('Προσθήκη στο Σνακ'));
    await t.pumpAndSettle();
    expect((got as dynamic).grams, 250);
    expect((got as dynamic).est, isFalse);
  });
}
