// Αυτόματο πρόγραμμα εβδομάδας με κανόνες (16/11). Βιβλιοθήκη επινοημένη.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/food/dishes.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/food/library.dart';
import 'package:ygeia_forma/food/recipe.dart';
import 'package:ygeia_forma/food/week.dart';
import 'package:ygeia_forma/food/week_auto.dart';
import 'package:ygeia_forma/food/week_calc.dart';

import 'sample_food.dart';

final now = DateTime(2026, 11, 16, 13); // Δευτέρα

String nameOf(String id) => basicFoods().firstWhere((f) => f.id == id).name;

Map<String, Object?> dish(String key, String type, List<(String, double)> items,
        {List<String> meals = const [], List<String> tags = const [], bool office = false, int? servings, String cook = 'home'}) =>
    {
      'key': key,
      'name': 'Φαγητό $key',
      'type': type,
      if (servings != null) 'servings': servings,
      'meals': meals,
      'tags': tags,
      'office': office,
      'cook': cook,
      if (cook == 'out') 'order': 'Ψητό, λάδι στο πλάι.',
      'items': [for (final (id, g) in items) {'id': id, 'name': nameOf(id), 'g': g}],
      if (cook == 'home')
        'steps': [
          {'text': 'Μαγείρεψέ το.', 'min': 20}
        ],
    };

const lentils = 'C20359', chickpeas = 'C20516', beans = 'C20501', oil = 'C17270', onion = 'C20034', tomato = 'C20385';
const chicken = 'C36017', rice = 'C9100', yogurt = 'U170894', feta = 'C12066', salmon = 'C26036', bream = 'C26088';
const beef = 'C6206', apple = 'C13039', rusks = 'C7340';

final lib = [
  dish('fakes', 'pot', [(lentils, 500), (onion, 150), (oil, 40)], meals: ['lunch', 'dinner'], tags: ['όσπρια'], office: true, servings: 4),
  dish('revithia', 'pot', [(chickpeas, 500), (onion, 150), (oil, 40)], meals: ['lunch', 'dinner'], tags: ['όσπρια'], office: true, servings: 4),
  dish('fasolada', 'pot', [(beans, 500), (tomato, 300), (oil, 40)], meals: ['lunch', 'dinner'], tags: ['όσπρια'], office: true, servings: 4),
  dish('kotopoulo-ryzi', 'plate', [(chicken, 200), (rice, 90), (oil, 10)], meals: ['lunch', 'dinner']),
  dish('kotopoulo-salata', 'plate', [(chicken, 200), (tomato, 250), (oil, 20), (feta, 40)], meals: ['lunch', 'dinner'], office: true),
  dish('solomos', 'plate', [(salmon, 200), (rice, 80)], meals: ['dinner'], tags: ['λιπαρό ψάρι']),
  dish('tsipoura', 'plate', [(bream, 350), (tomato, 150), (oil, 15)], meals: ['dinner'], tags: ['ψάρι']),
  dish('tsipoura-exo', 'plate', [(bream, 350), (rice, 80)], meals: ['lunch', 'dinner'], tags: ['ψάρι'], cook: 'out'),
  dish('mosxari', 'plate', [(beef, 200), (rice, 80)], meals: ['dinner'], tags: ['κόκκινο κρέας']),
  dish('giaourti', 'plate', [(yogurt, 250), (apple, 150), (rusks, 30)], meals: ['snack'], cook: 'none'),
  dish('frygania', 'plate', [(rusks, 40), (feta, 40), (tomato, 100)], meals: ['snack'], cook: 'none'),
  dish('milo-giaourti', 'plate', [(yogurt, 250), (rusks, 40)], meals: ['snack'], cook: 'none'),
  dish('kotopoulo-tortilla', 'plate', [(chicken, 180), (rusks, 60), (tomato, 100)], meals: ['lunch'], office: true, cook: 'none'),
];

FoodStore store({FoodLikes likes = const FoodLikes()}) {
  var n = 0;
  final s0 = FoodStore.preloaded(foods: basicFoods(), now: now);
  final r = planLibraryImport(
    parseLibrary(jsonEncode({'kind': libraryKind, 'dishes': lib})),
    existing: const [],
    food: (id) => s0.itemFood(DishItem(id, id, 1)),
    likes: const FoodLikes(),
    now: 1,
    newId: () => 'L${n++}',
  );
  expect(r.problems, isEmpty, reason: r.problems.map((p) => p.errors).join());
  return FoodStore.preloaded(foods: basicFoods(), dishes: r.added, likes: likes, now: now);
}

String keyOf(FoodStore s, String dishId) => planInfoOf(s.dishById(dishId)!)!.key!;

AutoWeek make(FoodStore s, {int seed = 1, WeekPlan? keep}) => autoWeek(
      s,
      from: now,
      meals: const [Meal.lunch, Meal.snack, Meal.dinner],
      kcalTarget: 2100,
      proteinTarget: 130,
      legumesWeek: 3,
      fishWeek: 2,
      seed: seed,
      keep: keep,
      now: 1,
    );

void main() {
  test('Κάθε μέρα: 3 γεύματα, θερμίδες ±5%, γεύμα που ταιριάζει, γραφείο Τρ–Πε', () {
    final s = store();
    final r = make(s);
    final w = r.plan;
    expect(w.source, 'auto');
    expect(w.days, hasLength(7));
    for (var i = 0; i < 7; i++) {
      final day = w.days[i];
      expect(day.map((x) => x.meal), [Meal.lunch, Meal.snack, Meal.dinner], reason: 'μέρα $i');
      final kcal = plannedDay(s, w, i).totals.kcal;
      expect((kcal - 2100).abs(), lessThanOrEqualTo(2100 * 0.05 + 5), reason: 'μέρα $i: $kcal');
      for (final slot in day) {
        final info = planInfoOf(s.dishById(slot.dishId)!)!;
        expect(info.fits(slot.meal), isTrue);
        if (slot.meal == Meal.lunch && {DateTime.tuesday, DateTime.wednesday, DateTime.thursday}.contains(w.dayAt(i).weekday)) {
          expect(info.office, isTrue, reason: 'μέρα $i: ${info.key}');
        }
      }
    }
  });

  test('Ποικιλία: ως 2 φορές την εβδομάδα, όχι δύο μέρες στη σειρά (εκτός από ταπεράκι)· όσπρια και ψάρι όσα ζητούνται', () {
    final s = store();
    for (final seed in [1, 2, 3, 4, 5]) {
      final w = make(s, seed: seed).plan;
      final days = <String, List<int>>{};
      for (var i = 0; i < 7; i++) {
        for (final slot in w.days[i]) {
          (days[slot.dishId] ??= []).add(i);
        }
      }
      var legumes = 0, fish = 0;
      for (final MapEntry(key: id, value: d) in days.entries) {
        expect(d.length, lessThanOrEqualTo(2), reason: '${keyOf(s, id)} seed $seed');
        if (d.length == 2) {
          final d2 = s.dishById(id)!;
          if (d2.kind == DishKind.pot) {
            expect(d[1] - d[0], lessThan(4));
            if (d[1] - d[0] == 1) {
              final lunch = w.days[d[1]].firstWhere((x) => x.dishId == id).meal == Meal.lunch;
              expect(lunch && {2, 3, 4}.contains(w.dayAt(d[1]).weekday), isTrue, reason: 'συνεχόμενες μόνο για ταπεράκι');
            }
          } else {
            expect(d[1] - d[0], greaterThanOrEqualTo(2), reason: '${keyOf(s, id)} seed $seed');
          }
        }
        final info = planInfoOf(s.dishById(id)!)!;
        if (info.hasTag('όσπρια')) legumes += d.length;
        if (info.hasTag('ψάρι') || info.hasTag('λιπαρό ψάρι')) fish += d.length;
      }
      expect(legumes, greaterThanOrEqualTo(3), reason: 'seed $seed');
      expect(fish, greaterThanOrEqualTo(2), reason: 'seed $seed');
    }
  });

  test('Δε μου αρέσει: φαγητό με τέτοιο υλικό δεν μπαίνει', () {
    final s = store(likes: const FoodLikes(dislike: [salmon]));
    final w = make(s).plan;
    for (final d in w.days) {
      for (final slot in d) {
        expect(keyOf(s, slot.dishId), isNot('solomos'));
      }
    }
  });

  test('Ξανά: οι κλειδωμένες θέσεις μένουν· άλλο seed δίνει άλλη εβδομάδα', () {
    final s = store();
    final first = make(s).plan;
    final locked = first.withSlot(0, 0, first.days[0][0].copyWith(locked: true));
    final again = make(s, seed: 7, keep: locked).plan;
    expect(again.days[0][0].dishId, first.days[0][0].dishId);
    expect(again.days[0][0].locked, isTrue);
    final a = [for (final d in first.days) for (final x in d) x.dishId].join();
    final b = [for (final d in make(s, seed: 9).plan.days) for (final x in d) x.dishId].join();
    expect(a == b, isFalse);
  });

  test('Χωρίς φαγητά για γραφείο: τα μεσημεριανά Τρ–Πε μένουν κενά και το λέει', () {
    var n = 0;
    final s0 = FoodStore.preloaded(foods: basicFoods(), now: now);
    final r = planLibraryImport(
      parseLibrary(jsonEncode({
        'kind': libraryKind,
        'dishes': [for (final d in lib) {...d, 'office': false}]
      })),
      existing: const [],
      food: (id) => s0.itemFood(DishItem(id, id, 1)),
      likes: const FoodLikes(),
      now: 1,
      newId: () => 'L${n++}',
    );
    final s = FoodStore.preloaded(foods: basicFoods(), dishes: r.added, now: now);
    final auto = make(s);
    expect(auto.notes.first, contains('για γραφείο'));
    expect(auto.plan.days[1].map((x) => x.meal), isNot(contains(Meal.lunch)));
    expect(usableLibrary(s), lib.length);
  });
}
