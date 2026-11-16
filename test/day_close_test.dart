// «Τελείωσα για σήμερα», φρούτα/λαχανικά, αντιγραφή/μετακίνηση (16/11). Επινοημένα δεδομένα.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/adaptive_check.dart' show dailyIntake;
import 'package:ygeia_forma/backup.dart';
import 'package:ygeia_forma/food/dishes.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/pages/day_close.dart';
import 'package:ygeia_forma/pages/transfer.dart';
import 'package:ygeia_forma/theme.dart';

import 'sample_food.dart';

final now = DateTime(2026, 11, 18, 21);
final today = DateTime(2026, 11, 18);
final yesterday = DateTime(2026, 11, 17);

Food f(String id) => basicFoods().firstWhere((x) => x.id == id);

void main() {
  group('Σημάδι μέρας', () {
    test('Αποθηκεύεται στο αρχείο των φαγητών, ξαναδιαβάζεται, σβήνει', () async {
      final io = MemoryDishIO();
      final s = FoodStore.preloaded(foods: basicFoods(), dishIO: io, now: now);
      await s.loadDishes();
      expect(s.dayMark(today), isNull);
      expect(await s.setDayMark(today, DayMark.done), isTrue);
      expect(await s.setDayMark(yesterday, DayMark.part), isTrue);
      expect(jsonDecode(io.json!)['days'], {'2026-11-18': 'done', '2026-11-17': 'part'});
      final s2 = FoodStore.preloaded(foods: basicFoods(), dishIO: MemoryDishIO(io.json), now: now);
      await s2.loadDishes();
      expect(s2.dayMark(today), DayMark.done);
      expect(s2.dayMark(yesterday), DayMark.part);
      expect(await s2.setDayMark(today, null), isTrue);
      expect(s2.dayMark(today), isNull);
    });

    test('Επαναφορά: μπαίνουν μόνο οι μέρες χωρίς σημάδι· τα λάθος δεν μπαίνουν', () async {
      final s = FoodStore.preloaded(foods: basicFoods(), dishIO: MemoryDishIO(), now: now);
      await s.loadDishes();
      await s.setDayMark(today, DayMark.done);
      final n = await s.importDayMarks({'2026-11-18': 'part', '2026-11-16': 'part', '2026-11-15': 'κάτι', 5: 'done'});
      expect(n, 1);
      expect(s.dayMark(today), DayMark.done);
      expect(s.dayMark(DateTime(2026, 11, 16)), DayMark.part);
      expect(s.dayMark(DateTime(2026, 11, 15)), isNull);
    });

    test('Στο αρχείο αντιγράφου και πίσω', () {
      final text = buildBackup(
        foodLog: const [],
        myFoods: const [],
        prefs: const {},
        now: now,
        foodDays: const {'2026-11-17': 'part'},
      );
      expect(parseBackup(text).dayMarks, {'2026-11-17': 'part'});
      final old = buildBackup(foodLog: const [], myFoods: const [], prefs: const {}, now: now);
      expect(parseBackup(old).dayMarks, isEmpty);
    });

    test('Μέρα με «λείπουν γεύματα» δεν μετρά στον έλεγχο θερμίδων· οι άλλες μετρούν όπως πριν', () async {
      final s = FoodStore.preloaded(foods: basicFoods(), dishIO: MemoryDishIO(), now: now);
      await s.loadDishes();
      await s.add(f('C13005'), 200, Meal.snack, on: yesterday, now: now);
      await s.add(f('C13005'), 100, Meal.snack, on: today, now: now);
      expect(dailyIntake(s, yesterday, today).keys, [yesterday, today]);
      await s.setDayMark(yesterday, DayMark.part);
      expect(dailyIntake(s, yesterday, today).keys, [today]);
      await s.setDayMark(yesterday, DayMark.done);
      expect(dailyIntake(s, yesterday, today).keys, [yesterday, today]);
    });
  });

  test('Φρούτα και λαχανικά: μόνο οι δύο κατηγορίες, και ως υλικά φαγητών· όχι πατάτες ή όσπρια', () {
    LogEntry e(String id, double g, {DishTag? dish}) =>
        LogEntry(id: id + g.toString(), day: '2026-11-18', meal: Meal.lunch, food: f(id), grams: g, time: now, dish: dish);
    final list = [
      e('C13005', 120), // μπανάνα
      e('C20385', 150), // ντομάτα
      e('C4008', 300), // πατάτα: όχι
      e('C20359', 80), // φακές: όχι
      e('C20034', 50, dish: const DishTag(id: 'd', name: 'Φακές', kind: DishKind.pot, grp: 'g', qty: 300)),
    ];
    expect(fruitVegGrams(list), 120 + 150 + 50);
  });

  group('Αντιγραφή και μετακίνηση', () {
    test('Μετακίνηση: ίδιες καταχωρίσεις σε άλλη μέρα και γεύμα· αντιγραφή: νέες, με νέο «grp» ανά φαγητό', () async {
      final s = FoodStore.preloaded(foods: basicFoods(), now: now);
      final a = await s.add(f('C13005'), 120, Meal.lunch, on: today, now: now);
      const tag = DishTag(id: 'd1', name: 'Σαλάτα', kind: DishKind.plate, grp: 'g1', qty: 250);
      final b1 = a.copyWith(id: 'x1', food: f('C20385'), grams: 150, dish: tag);
      final b2 = a.copyWith(id: 'x2', food: f('C20019'), grams: 100, dish: tag);
      await s.updateGroup([b1, b2]);
      final moved = await s.transferEntries([a], yesterday, Meal.dinner, move: true, now: now);
      expect(moved!.single.id, a.id);
      expect(s.entriesFor(today).map((x) => x.id), isNot(contains(a.id)));
      expect(s.entriesFor(yesterday).single.meal, Meal.dinner);
      final copied = await s.transferEntries([b1, b2], yesterday, Meal.lunch, move: false, now: now);
      expect(copied, hasLength(2));
      expect(copied!.map((x) => x.id).toSet().intersection({'x1', 'x2'}), isEmpty);
      expect(copied.map((x) => x.dish!.grp).toSet(), hasLength(1));
      expect(copied.first.dish!.grp, isNot('g1'));
      expect(s.entriesFor(today).map((x) => x.id).toSet(), {'x1', 'x2'}, reason: 'η αντιγραφή αφήνει τα αρχικά');
      expect(s.entriesFor(yesterday), hasLength(3));
    });

    testWidgets('Το φύλλο: μετακίνηση στο ίδιο σημείο δεν γίνεται· χθες, βράδυ → αποτέλεσμα', (t) async {
      TransferChoice? got;
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                got = await showModalBottomSheet<TransferChoice>(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) => TransferSheet(from: today, meal: Meal.lunch, today: today),
                );
              },
              child: const Text('άνοιγμα'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('άνοιγμα'));
      await t.pumpAndSettle();
      await t.tap(find.text('Μετακίνηση').first);
      await t.pumpAndSettle();
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('transfer-go'))).onPressed, isNull);
      await t.tap(find.byKey(const ValueKey('transfer-day-2026-11-17')));
      await t.tap(find.text('Βράδυ'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('transfer-go')));
      await t.pumpAndSettle();
      expect(got, (day: yesterday, meal: Meal.dinner, move: true));
    });
  });

  group('Κάρτες', () {
    Future<void> pump(WidgetTester t, Widget w) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(420, 1600);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: SingleChildScrollView(child: w))));
      await t.pumpAndSettle();
    }

    testWidgets('Η μέρα: φρούτα/λαχανικά και «Τελείωσα για σήμερα» → σημάδι, «Αλλαγή» → πάλι ερώτηση', (t) async {
      final s = FoodStore.preloaded(foods: basicFoods(), dishIO: MemoryDishIO(), now: now);
      await s.loadDishes();
      await s.add(f('C13005'), 120, Meal.snack, on: today, now: now);
      await pump(
          t,
          ListenableBuilder(
              listenable: s, builder: (c, _) => DayCard(food: s, day: today, entries: s.entriesFor(today), today: true)));
      expect(find.text('120 / 400 g'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('day-done')));
      await t.pumpAndSettle();
      expect(s.dayMark(today), DayMark.done);
      expect(find.text('Η μέρα γράφτηκε ολόκληρη.'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('day-mark-change')));
      await t.pumpAndSettle();
      expect(s.dayMark(today), isNull);
      await t.tap(find.byKey(const ValueKey('day-part')));
      await t.pumpAndSettle();
      expect(s.dayMark(today), DayMark.part);
    });

    testWidgets('Χθες: η ερώτηση μόνο αν χθες έχει καταχωρίσεις και δεν απαντήθηκε', (t) async {
      final s = FoodStore.preloaded(foods: basicFoods(), dishIO: MemoryDishIO(), now: now);
      await s.loadDishes();
      Widget card() => ListenableBuilder(listenable: s, builder: (c, _) => YesterdayCard(food: s, today: today));
      await pump(t, card());
      expect(find.byKey(const ValueKey('yesterday-card')), findsNothing);
      await s.add(f('C13005'), 120, Meal.snack, on: yesterday, now: now);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('yesterday-card')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('yesterday-part')));
      await t.pumpAndSettle();
      expect(s.dayMark(yesterday), DayMark.part);
      expect(find.byKey(const ValueKey('yesterday-card')), findsNothing);
    });
  });
}
