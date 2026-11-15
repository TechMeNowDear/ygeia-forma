// Πρόγραμμα εβδομάδας (15/11): επικόλληση, μερίδες από τη βάση, «Το έφαγα». Φαγητά και πρόγραμμα επινοημένα.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/food/dishes.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/food/library.dart';
import 'package:ygeia_forma/food/recipe.dart';
import 'package:ygeia_forma/food/week.dart';
import 'package:ygeia_forma/food/week_calc.dart';
import 'package:ygeia_forma/pages/dishes.dart';
import 'package:ygeia_forma/pages/week.dart';
import 'package:ygeia_forma/theme.dart';

import 'sample_food.dart';

const lentils = 'C20359';
const onion = 'C20034';
const oil = 'C17270';
const rusks = 'C7340';
const apple = 'C13039';
const bream = 'C26088'; // Τσιπούρα υδατοκαλλιέργειας (ωμή)
const tuna = 'C26039'; // Τόνος σε νερό (κονσέρβα)
final now = DateTime(2026, 11, 16, 13);

final _lib = <Map<String, Object?>>[
  {
    'key': 'fakes',
    'name': 'Φακές κοκκινιστές',
    'type': 'pot',
    'servings': 4,
    'meals': ['lunch', 'dinner'],
    'office': true,
    'tags': ['όσπρια'],
    'items': [
      {'id': lentils, 'name': 'Φακές (ξερές)', 'g': 250},
      {'id': onion, 'name': 'Κρεμμύδι', 'g': 100},
      {'id': oil, 'name': 'Ελαιόλαδο', 'g': 20},
    ],
    'steps': [
      {'text': 'Βράσε τις φακές.', 'min': 30}
    ],
  },
  {
    'key': 'frygania-milo',
    'name': 'Φρυγανιές με μήλο',
    'cook': 'none',
    'type': 'plate',
    'meals': ['snack'],
    'items': [
      {'id': rusks, 'name': 'Φρυγανιές ολικής', 'g': 30},
      {'id': apple, 'name': 'Μήλο', 'g': 150},
    ],
  },
  {
    'key': 'tsipoura',
    'name': 'Τσιπούρα με τόνο',
    'type': 'plate',
    'meals': ['dinner'],
    'tags': ['ψάρι'],
    'items': [
      {'id': bream, 'name': 'Τσιπούρα', 'g': 300},
      {'id': tuna, 'name': 'Τόνος', 'g': 50},
    ],
    'steps': [
      {'text': 'Ψήσε την τσιπούρα.', 'min': 20}
    ],
  },
  {
    'key': 'tsipoura-exo',
    'name': 'Τσιπούρα από ψητοπωλείο',
    'cook': 'out',
    'type': 'plate',
    'order': 'Ψητή, λάδι στο πλάι.',
    'items': [
      {'id': bream, 'name': 'Τσιπούρα', 'g': 300},
    ],
  },
  {
    'key': 'mpiftekia',
    'name': 'Μπιφτέκια',
    'type': 'portions',
    'servings': 4,
    'cook': 'none',
    'items': [
      {'id': lentils, 'name': 'Φακές', 'g': 200},
    ],
  },
];

List<Dish> library() {
  var n = 0;
  final s = FoodStore.preloaded(foods: basicFoods(), now: now);
  final r = planLibraryImport(
    parseLibrary(jsonEncode({'kind': libraryKind, 'dishes': _lib})),
    existing: const [],
    food: (id) => s.itemFood(DishItem(id, id, 1)),
    likes: const FoodLikes(),
    now: 1,
    newId: () => 'L${n++}',
  );
  expect(r.problems, isEmpty, reason: r.problems.map((p) => p.errors).join());
  return r.added;
}

String weekText({Object? from = '2026-11-16', List<Object?>? days}) => '```json\n${jsonEncode({
      'kind': weekKind,
      if (from != null) 'from': from,
      'days': days ??
          [
            [
              {'meal': 'lunch', 'key': 'fakes', 'kcal': 600},
              {'meal': 'snack', 'key': 'frygania-milo', 'kcal': 300},
              {'meal': 'dinner', 'key': 'mpiftekia'},
            ],
            [
              {'meal': 'lunch', 'key': 'fakes', 'kcal': 600},
            ],
          ],
    })}\n```';

FoodStore store({List<Dish>? dishes, WeekPlan? week, DishIO? io}) =>
    FoodStore.preloaded(foods: basicFoods(), dishes: dishes ?? library(), week: week, dishIO: io, now: now);

void main() {
  group('Επικόλληση προγράμματος', () {
    test('Τα κλειδιά της βιβλιοθήκης γίνονται φαγητά μου, με θερμίδες ανά θέση', () {
      final dishes = library();
      final p = parseWeek(weekText(), dishes, now: 5);
      expect(p.errors, isEmpty);
      final w = p.plan!;
      expect(w.from, '2026-11-16');
      expect(w.days, hasLength(2));
      expect(w.days[0].map((s) => s.meal), [Meal.lunch, Meal.snack, Meal.dinner]);
      expect(w.days[0][0].dishId, dishes.firstWhere((d) => planInfoOf(d)!.key == 'fakes').id);
      expect(w.days[0][0].kcal, 600);
      expect(w.days[0][2].kcal, isNull);
      expect(w.indexOf(DateTime(2026, 11, 17, 9)), 1);
      expect(w.indexOf(DateTime(2026, 11, 18)), -1);
    });

    test('Ένα λάθος και δεν περνά τίποτα: το λέει', () {
      final dishes = library();
      expect(parseWeek(weekText(from: null), dishes, now: 0).errors.join(), contains('«from»'));
      expect(parseWeek(weekText(from: '2026-02-30'), dishes, now: 0).plan, isNull);
      final bad = parseWeek(
          weekText(days: [
            [
              {'meal': 'brunch', 'key': 'fakes'},
              {'meal': 'lunch', 'key': 'pizza'},
              {'meal': 'dinner', 'key': 'fakes', 'kcal': 9000},
            ]
          ]),
          dishes,
          now: 0);
      expect(bad.plan, isNull);
      final e = bad.errors.join(' | ');
      expect(e, contains('brunch'));
      expect(e, contains('«pizza»'));
      expect(e, contains('«kcal»'));
      expect(parseWeek('{"kind":"ygeia-library"}', dishes, now: 0).errors.single, contains('δεν είναι πρόγραμμα'));
      final prompt = weekPrompt(food: store(dishes: dishes), from: DateTime(2026, 11, 16));
      expect(parseWeek(prompt, dishes, now: 0).errors.single, contains('οδηγίες'));
    });

    test('Νέο πρόγραμμα πάνω σε παλιό: τα σημειωμένα γεύματα των ίδιων ημερών μένουν', () {
      final dishes = library();
      final old = parseWeek(weekText(), dishes, now: 1).plan!;
      final marked = old.withSlot(0, 0, old.days[0][0].copyWith(state: SlotState.ate, grp: 'g1'));
      final next = keepDone(parseWeek(weekText(), dishes, now: 2).plan!, marked);
      expect(next.days[0][0].state, SlotState.ate);
      expect(next.days[0][0].grp, 'g1');
      expect(next.days[0][1].state, SlotState.open);
    });

    test('Στο αρχείο μαζί με τα φαγητά και το «Τι μου αρέσει»· ξαναδιαβάζεται ίδιο', () async {
      final io = MemoryDishIO();
      final s = FoodStore.preloaded(foods: basicFoods(), dishIO: io, now: now);
      await s.loadDishes();
      expect(await s.saveDishes(library()), isTrue);
      await s.saveLikes(const FoodLikes(like: [lentils]));
      final w = parseWeek(weekText(), s.dishes, now: 9).plan!;
      expect(await s.saveWeek(w.withSlot(0, 1, w.days[0][1].copyWith(locked: true))), isTrue);
      final io2 = MemoryDishIO(io.json);
      final s2 = FoodStore.preloaded(foods: basicFoods(), dishIO: io2, now: now);
      await s2.loadDishes();
      expect(s2.dishes, hasLength(5));
      expect(s2.likes.like, [lentils]);
      expect(jsonEncode(s2.week!.toJson()), jsonEncode(s.week!.toJson()));
      expect(s2.week!.days[0][1].locked, isTrue);
      // Μία αλλαγή στα φαγητά δεν σβήνει το πρόγραμμα.
      await s2.saveDish(s2.dishes.first.copyWith(name: 'Άλλο όνομα'));
      final s3 = FoodStore.preloaded(foods: basicFoods(), dishIO: MemoryDishIO(io2.json), now: now);
      await s3.loadDishes();
      expect(s3.week, isNotNull);
      expect(s3.dishes.any((d) => d.name == 'Άλλο όνομα'), isTrue);
      expect(await s3.saveWeek(null), isTrue);
    });
  });

  group('Μερίδες από τη βάση', () {
    test('Πιάτο: όλα τα υλικά στην ίδια αναλογία, όσες θερμίδες λέει το πρόγραμμα', () {
      final s = store();
      final d = s.dishes.firstWhere((d) => d.name == 'Φρυγανιές με μήλο');
      final full = itemsTotals(s, d.items)!.kcal;
      final l = slotLog(s, d, PlanSlot(meal: Meal.snack, dishId: d.id, kcal: full * 1.5), now)!;
      expect(l.plate, [45, 225]);
      expect(itemsTotals(s, l.amounts)!.kcal, closeTo(full * 1.5, 2));
      final natural = slotLog(s, d, PlanSlot(meal: Meal.snack, dishId: d.id), now)!;
      expect(natural.plate, [30, 150]);
    });

    test('Ίσες μερίδες: ανά μισή μερίδα, τουλάχιστον μισή', () {
      final s = store();
      final d = s.dishes.firstWhere((d) => d.name == 'Μπιφτέκια');
      final one = itemsTotals(s, dishAmounts(d, servings: 1))!.kcal;
      expect(slotLog(s, d, PlanSlot(meal: Meal.dinner, dishId: d.id, kcal: one * 1.6), now)!.qty, 1.5);
      expect(slotLog(s, d, PlanSlot(meal: Meal.dinner, dishId: d.id, kcal: one * 0.1), now)!.qty, 0.5);
      expect(slotLog(s, d, PlanSlot(meal: Meal.dinner, dishId: d.id), now)!.qty, 1);
    });

    test('Κατσαρόλα: χωρίς ζυγισμένο μαγείρεμα δεν βγαίνει μερίδα· μετά, γραμμάρια από το έτοιμο, ανά 5 g', () {
      final s = store();
      final d = s.dishes.firstWhere((d) => d.kind == DishKind.pot);
      final slot = PlanSlot(meal: Meal.lunch, dishId: d.id, kcal: 600);
      expect(slotLog(s, d, slot, now), isNull);
      final b = PotBatch(at: now.subtract(const Duration(days: 1)).millisecondsSinceEpoch, cooked: 1500, items: d.items);
      final cooked = d.copyWith(batch: b);
      final all = itemsTotals(s, d.items)!.kcal;
      final g = potPortion(s, cooked, b, 600)!;
      expect(g % 5, 0);
      expect(g, closeTo(600 * 1500 / all, 2.5));
      final l = slotLog(s, cooked, slot, now)!;
      expect(l.qty, g);
      expect(itemsTotals(s, l.amounts)!.kcal, closeTo(600, 4));
      // Χωρίς θερμίδες: 1 από τις μερίδες της συνταγής (4).
      expect(potPortion(s, cooked, b, null), 375);
      // Μαγείρεμα πριν από 4 μέρες: όχι πια (ζύγισε ξανά).
      final old = d.copyWith(batch: PotBatch(at: now.subtract(const Duration(days: 4)).millisecondsSinceEpoch, cooked: 1500, items: d.items));
      expect(slotLog(s, old, slot, now), isNull);
    });

    test('Σύνολα της μέρας του προγράμματος, χωρίς τα «Δεν το έφαγα»', () {
      final s = store();
      final w = parseWeek(weekText(), s.dishes, now: 0).plan!;
      final p = plannedDay(s, w, 0);
      expect(p.unknown, 0);
      final one = itemsTotals(s, dishAmounts(s.dishes.firstWhere((d) => d.name == 'Μπιφτέκια'), servings: 1))!.kcal;
      expect(p.totals.kcal, closeTo(600 + 300 + one, 3));
      final skipped = w.withSlot(0, 0, w.days[0][0].copyWith(state: SlotState.skip));
      expect(plannedDay(s, skipped, 0).totals.kcal, closeTo(300 + one, 3));
    });

    test('Οδηγίες προγράμματος: κλειδιά, μερίδα κάθε φαγητού από τη βάση, πρώτη μέρα, στόχοι', () {
      final s = store();
      final text = weekPrompt(
        food: s,
        from: nextMonday(DateTime(2026, 11, 18)),
        targets: (kcal: 2150, protein: 130, satMax: 14, fiber: 30, salt: 5.0),
        legumesWeek: 4,
        fishWeek: 2,
      );
      expect(text, startsWith(weekPromptTitle));
      expect(text, contains('"from": "2026-11-23"'));
      expect(text, contains('όσπρια 4 φορές · ψάρι 2 φορές'));
      final d = s.dishes.firstWhere((d) => d.name == 'Φρυγανιές με μήλο');
      final kcal = itemsTotals(s, d.items)!.kcal.round();
      expect(text, contains('frygania-milo · Φρυγανιές με μήλο · πιάτο, χωρίς μαγείρεμα · snack'));
      expect(text, contains('μερίδα $kcal kcal'));
      expect(text, contains('fakes · Φακές κοκκινιστές · κατσαρόλα ~4 μερίδες'));
      expect(nextMonday(DateTime(2026, 11, 16, 23)), DateTime(2026, 11, 16));
    });
  });

  group('Λίστα ψωνιών', () {
    test('Κατσαρόλα μία φορά ανά μαγείρεμα· φρέσκο ψάρι τη μέρα του· κονσέρβα και παραγγελία όχι στα φρέσκα', () {
      final s = store();
      final w = parseWeek(
        weekText(days: [
          [
            {'meal': 'lunch', 'key': 'fakes'},
            {'meal': 'snack', 'key': 'frygania-milo'},
            {'meal': 'dinner', 'key': 'tsipoura'},
          ],
          [
            {'meal': 'lunch', 'key': 'fakes'},
            {'meal': 'dinner', 'key': 'tsipoura-exo'},
          ],
          [
            {'meal': 'lunch', 'key': 'mpiftekia'},
          ],
          [],
          [
            {'meal': 'lunch', 'key': 'fakes'},
          ],
        ]),
        s.dishes,
        now: 0,
      ).plan!;
      final l = shoppingList(s, w, now: now);
      final main = {for (final x in l.main) x.food.id: x.amount};
      // Φακές: 2 μαγειρέματα (μέρα 1 και μέρα 5) × 250 + μπιφτέκια 1 μερίδα (200 ÷ 4).
      expect(main[lentils], 2 * 250 + 50);
      expect(main[onion], 200);
      expect(main[rusks], 30);
      expect(main[tuna], 50, reason: 'κονσέρβα: στα ψώνια της αρχής');
      expect(main.containsKey(bream), isFalse);
      expect(l.fresh.keys, [0]);
      expect(l.fresh[0]!.single.food.id, bream);
      expect(l.fresh[0]!.single.amount, 300, reason: 'η τσιπούρα από ψητοπωλείο δεν αγοράζεται');
      expect(l.ordered, 1);
      final text = shoppingText(l, w);
      expect(text, contains('Τσιπούρα υδατοκαλλιέργειας (ωμή): 300 g'));
      expect(text, contains('Φακές (ξερές): 550 g'));
      // Από τη 2η μέρα και μετά: η κατσαρόλα της 1ης είναι περισσεύματα, μένει μόνο το μαγείρεμα της 5ης.
      final later = shoppingList(s, w, fromDay: 1, now: now);
      expect({for (final x in later.main) x.food.id: x.amount}[lentils], 250 + 50);
      expect(shopRound(3.2), 4);
      expect(shopRound(201), 210);
    });

    test('Υπάρχει ήδη πρόσφατο μαγείρεμα: η πρώτη φορά είναι περισσεύματα· τα σημειωμένα γεύματα δεν μετρούν', () {
      final dishes = library();
      final pot = dishes.firstWhere((d) => d.kind == DishKind.pot);
      final b = PotBatch(at: now.millisecondsSinceEpoch, cooked: 1500, items: pot.items);
      final cooked = [for (final d in dishes) d.id == pot.id ? d.copyWith(batch: b) : d];
      final s = store(dishes: cooked);
      final w = parseWeek(weekText(), cooked, now: 0).plan!;
      final l = shoppingList(s, w, now: now);
      expect({for (final x in l.main) x.food.id: x.amount}.containsKey(onion), isFalse);
      final ate = w.withSlot(0, 1, w.days[0][1].copyWith(state: SlotState.ate, grp: 'x'));
      expect(shoppingList(s, ate, now: now).main.any((x) => x.food.id == rusks), isFalse);
    });
  });

  group('Οθόνες', () {
    Future<void> pump(WidgetTester t, Widget w) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(420, 2600);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: SingleChildScrollView(child: w))));
      await t.pumpAndSettle();
    }

    testWidgets('«Το έφαγα»: όλο το γεύμα στο ημερολόγιο με ένα πάτημα, και η «Αναίρεση» το βγάζει', (t) async {
      final dishes = library();
      final s = store(dishes: dishes, week: parseWeek(weekText(), dishes, now: 0).plan);
      await pump(t, FoodTheme(child: ListenableBuilder(listenable: s, builder: (c, _) => PlanDayCard(food: s, day: now, clock: () => now))));
      expect(find.byKey(const ValueKey('plan-day-card')), findsOneWidget);
      expect(find.text('Φρυγανιές με μήλο'), findsOneWidget);
      // Κατσαρόλα χωρίς μαγείρεμα: λέει τι να κάνεις.
      expect(find.textContaining('ζύγισε όλο το έτοιμο φαγητό'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('slot-ate-0-1')));
      await t.pumpAndSettle();
      final e = s.entriesFor(now);
      expect(e.map((x) => x.food.id).toSet(), {rusks, apple});
      expect(e.every((x) => x.meal == Meal.snack), isTrue);
      expect(Totals(e).kcal, closeTo(300, 3));
      expect(s.week!.days[0][1].state, SlotState.ate);
      expect(find.byKey(const ValueKey('slot-ate-0-1')), findsNothing);
      await t.tap(find.text('Αναίρεση'));
      await t.pumpAndSettle();
      expect(s.entriesFor(now), isEmpty);
      expect(s.week!.days[0][1].state, SlotState.open);
    });

    testWidgets('Σβήνεις από το ημερολόγιο ό,τι έγραψε το «Το έφαγα»: το γεύμα ξανανοίγει', (t) async {
      final dishes = library();
      final s = store(dishes: dishes, week: parseWeek(weekText(), dishes, now: 0).plan);
      await pump(t, FoodTheme(child: ListenableBuilder(listenable: s, builder: (c, _) => PlanDayCard(food: s, day: now, clock: () => now))));
      await t.tap(find.byKey(const ValueKey('slot-ate-0-1')));
      await t.pumpAndSettle();
      expect(slotStateNow(s, s.week!, 0, s.week!.days[0][1]), SlotState.ate);
      await s.removeGroup(s.entriesFor(now));
      await t.pumpAndSettle();
      expect(slotStateNow(s, s.week!, 0, s.week!.days[0][1]), SlotState.open);
      expect(find.byKey(const ValueKey('slot-ate-0-1')), findsOneWidget);
    });

    testWidgets('Κατσαρόλα στο πρόγραμμα: μετά το ζύγισμα, «Η μερίδα σου: … g»', (t) async {
      final dishes = library();
      final pot = dishes.firstWhere((d) => d.kind == DishKind.pot);
      final b = PotBatch(at: now.millisecondsSinceEpoch, cooked: 1500, items: pot.items);
      final cooked = [for (final d in dishes) d.id == pot.id ? d.copyWith(batch: b) : d];
      final s = store(dishes: cooked, week: parseWeek(weekText(), cooked, now: 0).plan);
      final g = potPortion(s, s.dishById(pot.id)!, b, 600)!;
      await pump(t, FoodTheme(child: PlanDayCard(food: s, day: now, clock: () => now)));
      expect(find.text('Η μερίδα σου: ${g.round()} g'), findsOneWidget);
      // Το φύλλο του φαγητού με τις θερμίδες του προγράμματος: η μερίδα έτοιμη.
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: DishLogSheet(food: s, dish: s.dishById(pot.id)!, meal: Meal.lunch, now: () => now, targetKcal: 600)),
      ));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('dish-want')), findsOneWidget);
      expect(find.textContaining('Η μερίδα σου για το πρόγραμμα (600 kcal): ${g.round()} g'), findsOneWidget);
    });

    testWidgets('Η εβδομάδα: επικόλληση, μέρες, κλείδωμα, σβήσιμο', (t) async {
      final dishes = library();
      final s = store(dishes: dishes);
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(420, 3000);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: WeekPlanScreen(food: s, clock: () => now)));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('week-copy')), findsOneWidget);
      final st = t.state(find.byType(WeekPlanScreen)) as dynamic;
      await st.read(weekText());
      await t.pumpAndSettle();
      expect(s.week, isNotNull);
      expect(find.byKey(const ValueKey('week-day-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('week-day-1')), findsOneWidget);
      expect(find.textContaining('Σήμερα'), findsWidgets);
      // Αύριο: χωρίς «Το έφαγα» (τίποτα στο ημερολόγιο του μέλλοντος).
      expect(find.byKey(const ValueKey('slot-ate-0-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('slot-ate-1-0')), findsNothing);
      await t.tap(find.byKey(const ValueKey('slot-lock-0-0')));
      await t.pumpAndSettle();
      expect(s.week!.days[0][0].locked, isTrue);
      // Λάθος πρόγραμμα: το λέει, και το παλιό μένει.
      await st.read(weekText(days: [
        [
          {'meal': 'lunch', 'key': 'pizza'}
        ]
      ]));
      await t.pumpAndSettle();
      expect(find.textContaining('«pizza»'), findsOneWidget);
      expect(s.week!.days, hasLength(2));
      await t.tap(find.byKey(const ValueKey('week-delete')));
      await t.pumpAndSettle();
      await t.tap(find.text('Σβήσιμο').last);
      await t.pumpAndSettle();
      expect(s.week, isNull);
    });
  });
}
