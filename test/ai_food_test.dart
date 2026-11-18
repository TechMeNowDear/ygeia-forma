// AI για το φαγητό (19/11): έλεγχοι χωρίς δίκτυο, με ψεύτικο AI. Βιβλιοθήκη και προτιμήσεις επινοημένες.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/ai/ai_bridge.dart';
import 'package:ygeia_forma/food/ai_food.dart';
import 'package:ygeia_forma/food/dishes.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/food/kitchen.dart';
import 'package:ygeia_forma/food/library.dart';
import 'package:ygeia_forma/food/recipe.dart';
import 'package:ygeia_forma/food/week.dart';
import 'package:ygeia_forma/food/week_auto.dart';
import 'package:ygeia_forma/food/week_calc.dart';
import 'package:ygeia_forma/oura/oura_api.dart' show MemoryVault;

import 'sample_food.dart';

final monday = DateTime(2026, 11, 23);

String nameOf(String id) => basicFoods().firstWhere((f) => f.id == id).name;

Map<String, Object?> dish(String key, String type, List<(String, double)> items,
        {List<String> meals = const [], bool office = false, int? servings, String cook = 'home', int? minutes, List<String> tags = const []}) =>
    {
      'key': key,
      'name': 'Φαγητό $key',
      'type': type,
      if (servings != null) 'servings': servings,
      if (minutes != null) 'minutes': minutes,
      'meals': meals,
      'tags': tags,
      'office': office,
      'cook': cook,
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
  dish('fakes', 'pot', [(lentils, 500), (onion, 150), (oil, 40)], meals: ['lunch', 'dinner'], office: true, servings: 4, tags: ['όσπρια']),
  dish('revithia', 'pot', [(chickpeas, 500), (onion, 150), (oil, 40)], meals: ['lunch', 'dinner'], office: true, servings: 4, tags: ['όσπρια']),
  dish('fasolada', 'pot', [(beans, 500), (tomato, 300), (oil, 40)], meals: ['lunch', 'dinner'], office: true, servings: 4, tags: ['όσπρια']),
  dish('kotopoulo-ryzi', 'plate', [(chicken, 200), (rice, 90), (oil, 10)], meals: ['lunch', 'dinner'], minutes: 25),
  dish('kotopoulo-salata', 'plate', [(chicken, 200), (tomato, 250), (oil, 20), (feta, 40)], meals: ['lunch', 'dinner'], office: true, minutes: 10),
  dish('solomos', 'plate', [(salmon, 200), (rice, 80)], meals: ['dinner'], tags: ['λιπαρό ψάρι']),
  dish('tsipoura', 'plate', [(bream, 350), (tomato, 150), (oil, 15)], meals: ['dinner'], tags: ['ψάρι']),
  dish('mosxari', 'plate', [(beef, 200), (rice, 80)], meals: ['dinner'], tags: ['κόκκινο κρέας']),
  dish('giaourti', 'plate', [(yogurt, 250), (apple, 150), (rusks, 30)], meals: ['snack'], cook: 'none'),
  dish('frygania', 'plate', [(rusks, 40), (feta, 40), (tomato, 100)], meals: ['snack'], cook: 'none'),
  dish('milo-giaourti', 'plate', [(yogurt, 250), (rusks, 40)], meals: ['snack'], cook: 'none'),
];

/// Μου αρέσουν όλα εκτός από μοσχάρι· το ελαιόλαδο και το κρεμμύδι είναι «βασικά κουζίνας».
const likes = FoodLikes(
  like: [lentils, chickpeas, beans, tomato, chicken, rice, yogurt, feta, salmon, bream, apple, rusks],
  staple: [oil, onion],
  dislike: [beef],
);

FoodStore store({FoodLikes l = likes}) {
  var n = 0;
  final s0 = FoodStore.preloaded(foods: basicFoods(), now: monday);
  final r = planLibraryImport(
    parseLibrary(jsonEncode({'kind': libraryKind, 'dishes': lib})),
    existing: const [],
    food: (id) => s0.itemFood(DishItem(id, id, 1)),
    likes: const FoodLikes(),
    now: 1,
    newId: () => 'L${n++}',
  );
  expect(r.problems, isEmpty, reason: r.problems.map((p) => p.errors).join());
  return FoodStore.preloaded(foods: basicFoods(), dishes: r.added, likes: l, now: monday);
}

const RecipeTargets targets = (kcal: 2100, protein: 130, satMax: 22, fiber: 30, salt: 6.0);
const meals = [Meal.lunch, Meal.snack, Meal.dinner];

String fence(Object j) => 'Ορίστε:\n```json\n${jsonEncode(j)}\n```';

/// Οι μέρες του σχεδίου (Δευτέρα 23/11 ως Κυριακή 29/11). Τρ–Πε μεσημέρι: φαγητά για γραφείο.
final planDays = [
  ['kotopoulo-ryzi', 'giaourti', 'solomos'],
  ['fakes', 'frygania', 'kotopoulo-fournou'],
  ['kotopoulo-salata', 'giaourti', 'tsipoura'],
  ['fakes', 'milo-giaourti', 'kotopoulo-ryzi'],
  ['fasolada', 'frygania', 'kotopoulo-fournou'],
  ['revithia', 'giaourti', 'tsipoura'],
  ['kotopoulo-salata', 'milo-giaourti', 'revithia'],
];

Map<String, Object> planJson({List<List<String>>? days, List<Map<String, Object>>? news}) => {
      'kind': aiWeekKind,
      'new': news ??
          [
            {
              'key': 'kotopoulo-fournou',
              'name': 'Κοτόπουλο φούρνου με ντομάτα',
              'type': 'pot',
              'cook': 'home',
              'minutes': 50,
              'meals': ['lunch', 'dinner'],
              'office': true,
              'idea': 'κοτόπουλο, ντομάτα, κρεμμύδι, ελαιόλαδο',
            }
          ],
      'days': [
        for (final d in days ?? planDays)
          [
            {'meal': 'lunch', 'key': d[0]},
            {'meal': 'snack', 'key': d[1]},
            {'meal': 'dinner', 'key': d[2]},
          ],
      ],
    };

Map<String, Object> recipeJson(List<(String, double)> items) => {
      'kind': libraryKind,
      'dishes': [
        {
          ...dish('kotopoulo-fournou', 'pot', items, meals: ['lunch', 'dinner'], office: true, servings: 4, minutes: 50),
          'name': 'Κοτόπουλο φούρνου με ντομάτα',
          // Αριθμοί του AI: πρέπει να αγνοηθούν.
          'kcal': 99999,
        }
      ],
    };

/// Ψεύτικο AI: απαντά ανάλογα με την ερώτηση και κρατά ό,τι του στάλθηκε.
class FakeAi {
  FakeAi(this.answer);
  final String Function(AiAsk ask, int n) answer;
  final asks = <AiAsk>[];
  Future<AiReply> call(AiAsk a) async {
    asks.add(a);
    return AiReply.ok(answer(a, asks.length));
  }
}

bool isPlan(AiAsk a) => a.messages.first.$2.startsWith('Φτιάξε το πρόγραμμα');
bool isRecipe(AiAsk a) => a.messages.first.$2.startsWith('Γράψε τη συνταγή');

void main() {
  test('Επιτρεπόμενα: μου αρέσει + βασικά, ποτέ «δε μου αρέσει»', () {
    final a = aiAllowedIds(const FoodLikes(like: ['A', 'B'], staple: ['C', 'B'], dislike: ['B']));
    expect(a, {'A', 'C'});
    // Το «δε μου αρέσει» βγάζει ένα υλικό και από τα βασικά όταν διαβάζεται.
    final l = FoodLikes.fromJson({'like': ['A'], 'dislike': ['C'], 'staple': ['C', 'D']});
    expect(l.staple, ['D']);
    expect(FoodLikes.fromJson(l.toJson()).staple, ['D']);
  });

  test('Η βιβλιοθήκη του AI: μόνο φαγητά με επιτρεπόμενα υλικά, όχι «Δεν μου άρεσε»', () {
    final s = store();
    final keys = {for (final d in aiLibrary(s, aiAllowedIds(s.likes))) planInfoOf(d)!.key};
    expect(keys, isNot(contains('mosxari')));
    expect(keys, contains('fakes'));
    // Χωρίς το ελαιόλαδο στα βασικά: φεύγουν όσα το έχουν.
    final s2 = store(l: likes.copyWith(staple: [onion]));
    final keys2 = {for (final d in aiLibrary(s2, aiAllowedIds(s2.likes))) planInfoOf(d)!.key};
    expect(keys2, isNot(contains('fakes')));
    expect(keys2, contains('solomos'));
    // «Δεν μου άρεσε»
    final sol = s.dishes.firstWhere((d) => planInfoOf(d)?.key == 'solomos');
    final s3 = FoodStore.preloaded(
        foods: basicFoods(), dishes: [for (final d in s.dishes) d.id == sol.id ? withRating(d, -1) : d], likes: likes, now: monday);
    expect({for (final d in aiLibrary(s3, aiAllowedIds(likes))) planInfoOf(d)!.key}, isNot(contains('solomos')));
  });

  test('Οι οδηγίες: μόνο επιτρεπόμενα τρόφιμα, χωρίς δεδομένα υγείας', () {
    final s = store();
    final sys = aiSystem(s, aiAllowedIds(s.likes), Kitchen.initial());
    expect(sys, contains(chicken));
    expect(sys, contains(oil));
    expect(sys, isNot(contains(beef)));
    final p = aiPlanPrompt(
        food: s, ask: (from: monday, days: 7, meals: meals, kept: const {}), library: aiLibrary(s, aiAllowedIds(likes)), targets: targets);
    expect(p, contains('2.100 kcal'));
    expect(p, isNot(contains('mosxari')));
    for (final w in ['Oura', 'ύπνος', 'παλμ', 'πίεση', 'σάκχαρ']) {
      expect('$sys$p'.contains(w), isFalse, reason: w);
    }
  });

  test('Το σχέδιο: άγνωστο φαγητό, γραφείο, γεύμα που λείπει → προβλήματα', () {
    final s = store();
    final libMap = {for (final d in aiLibrary(s, aiAllowedIds(likes))) planInfoOf(d)!.key!: d};
    final all = {for (final d in libraryDishes(s.dishes)) planInfoOf(d)!.key!};
    final ask = (from: monday, days: 7, meals: meals, kept: <(int, Meal), String>{});
    final ok = parseAiPlan(fence(planJson()), ask, libMap, all);
    expect(ok.errors, isEmpty);
    expect(ok.plan!.newDishes.single.key, 'kotopoulo-fournou');

    final bad = [for (final d in planDays) List.of(d)];
    bad[0][2] = 'mosxari'; // δεν επιτρέπεται (μοσχάρι)
    bad[1][0] = 'kotopoulo-ryzi'; // Τρίτη μεσημέρι στο γραφείο, όχι για γραφείο
    final r = parseAiPlan(fence(planJson(days: bad)), ask, libMap, all);
    expect(r.plan, isNull);
    expect(r.errors.join(), contains('«mosxari»'));
    expect(r.errors.join(), contains('γραφείο'));

    final j = planJson();
    ((j['days'] as List)[3] as List).removeAt(1);
    expect(parseAiPlan(fence(j), ask, libMap, all).errors.join(), contains('λείπει το σνακ'));

    // Νέο φαγητό με key που υπάρχει ήδη.
    final dup = planJson(news: [
      {'key': 'fakes', 'name': 'Φακές 2', 'type': 'pot', 'cook': 'home'}
    ]);
    expect(parseAiPlan(fence(dup), ask, libMap, all).errors.join(), contains('υπάρχει ήδη'));
  });

  test('Μία συνταγή: υλικό εκτός λίστας δεν περνά', () {
    final s = store();
    var n = 0;
    final r = aiReadDish(fence(recipeJson([(chicken, 800), (beef, 200), (oil, 30)])),
        food: s, allowed: aiAllowedIds(likes), now: 1, newId: () => 'N${n++}', wantKey: 'kotopoulo-fournou');
    expect(r.dish, isNull);
    expect(r.errors.join(), contains(nameOf(beef)));
    final ok = aiReadDish(fence(recipeJson([(chicken, 800), (tomato, 400), (onion, 150), (oil, 30)])),
        food: s, allowed: aiAllowedIds(likes), now: 1, newId: () => 'N${n++}', wantKey: 'kotopoulo-fournou');
    expect(ok.errors, isEmpty);
    expect(planInfoOf(ok.dish!)!.key, 'kotopoulo-fournou');
    expect(ok.dish!.extra.toString(), isNot(contains('99999')));
  });

  test('Όλη η εβδομάδα: σχέδιο → συνταγή (με μία διόρθωση) → μερίδες από τη βάση', () async {
    final s = store();
    var recipeTries = 0;
    final ai = FakeAi((a, n) {
      if (isRecipe(a)) {
        recipeTries++;
        // 1η φορά με μοσχάρι (απαγορεύεται)· 2η σωστά.
        return fence(recipeJson(recipeTries == 1
            ? [(chicken, 800), (beef, 200), (oil, 30)]
            : [(chicken, 900), (tomato, 400), (onion, 150), (oil, 30)]));
      }
      return fence(planJson());
    });
    var n = 0;
    final stages = <AiStage>[];
    final r = await aiBuildWeek(
      call: ai.call,
      food: s,
      kitchen: Kitchen.initial(),
      targets: targets,
      from: monday,
      meals: meals,
      legumesWeek: 4,
      fishWeek: 2,
      now: 1,
      newId: () => 'N${n++}',
      progress: (st, _, __) => stages.add(st),
    );
    expect(r.fail, isNull);
    expect(r.errors, isEmpty);
    expect(recipeTries, 2);
    // Η 2η ερώτηση της συνταγής έχει την απάντηση και τα προβλήματα.
    final retry = ai.asks.where(isRecipe).last;
    expect(retry.messages, hasLength(3));
    expect(retry.messages.last.$2, contains(nameOf(beef)));
    expect(stages.first, AiStage.plan);
    expect(stages, contains(AiStage.recipes));

    final w = r.plan!;
    expect(w.source, 'ai');
    expect(w.days, hasLength(7));
    expect(r.newDishes.single.name, 'Κοτόπουλο φούρνου με ντομάτα');
    final byId = {for (final d in [...s.dishes, ...r.newDishes]) d.id: d};
    for (var i = 0; i < 7; i++) {
      final got = {for (final x in w.days[i]) x.meal: planInfoOf(byId[x.dishId]!)!.key};
      expect(got, {Meal.lunch: planDays[i][0], Meal.snack: planDays[i][1], Meal.dinner: planDays[i][2]}, reason: 'μέρα $i');
      for (final x in w.days[i]) {
        final range = portionRange(s, byId[x.dishId]!)!;
        expect(x.kcal, isNotNull);
        expect(x.kcal!, inInclusiveRange(range.lo - 10, range.hi + 10), reason: 'μέρα $i ${x.meal}');
      }
    }
    // Οι θερμίδες της μέρας από τη βάση, όχι από το AI.
    final sum = w.days[0].fold(0.0, (a, x) => a + plannedTotals(s, byId[x.dishId], x)!.kcal);
    expect(sum, lessThan(5000));
  });

  test('Λάθος σχέδιο 3 φορές → καμία εβδομάδα, το λέει', () async {
    final s = store();
    final bad = [for (final d in planDays) List.of(d)]..[0][2] = 'mosxari';
    final ai = FakeAi((a, n) => fence(planJson(days: bad)));
    final r = await aiBuildWeek(
        call: ai.call, food: s, kitchen: Kitchen.initial(), targets: targets, from: monday, meals: meals, now: 1, newId: () => 'x');
    expect(r.plan, isNull);
    expect(ai.asks, hasLength(1 + aiMaxRetries));
    expect(r.errors.join(), contains('mosxari'));
  });

  test('Χωρίς «Μου αρέσει»: δεν ρωτά καν το AI', () async {
    final s = store(l: const FoodLikes());
    final ai = FakeAi((a, n) => '');
    final r = await aiBuildWeek(
        call: ai.call, food: s, kitchen: Kitchen.initial(), targets: targets, from: monday, meals: meals, now: 1, newId: () => 'x');
    expect(r.plan, isNull);
    expect(ai.asks, isEmpty);
    expect(r.errors.single, contains('Τι μου αρέσει'));
  });

  test('Σφάλμα σύνδεσης: σταματά αμέσως', () async {
    final s = store();
    Future<AiReply> call(AiAsk a) async => const AiReply.failed(AiFail.credits);
    final r = await aiBuildWeek(
        call: call, food: s, kitchen: Kitchen.initial(), targets: targets, from: monday, meals: meals, now: 1, newId: () => 'x');
    expect(r.fail, AiFail.credits);
    expect(r.plan, isNull);
  });

  test('Ανάλογο γεύμα: όρια θερμίδων, πρωτεΐνης, κορεσμένων', () {
    const old = (kcal: 600.0, protein: 45.0, sat: 5.0);
    expect(analogProblems(old, (kcal: 650.0, protein: 41.0, sat: 6.0)), isEmpty);
    expect(analogProblems(old, (kcal: 670.0, protein: 45.0, sat: 5.0)), hasLength(1));
    expect(analogProblems(old, (kcal: 600.0, protein: 40.0, sat: 5.0)), hasLength(1));
    expect(analogProblems(old, (kcal: 600.0, protein: 45.0, sat: 6.1)), hasLength(1));
  });

  WeekPlan weekOf(FoodStore s) {
    final r = autoWeek(s,
        from: monday, meals: meals, kcalTarget: 2100, proteinTarget: 130, now: 1, forced: {
      for (var i = 0; i < 7; i++)
        for (final (k, m) in [(0, Meal.lunch), (1, Meal.snack), (2, Meal.dinner)])
          if (planDays[i][k] != 'kotopoulo-fournou')
            (i, m): s.dishes.firstWhere((d) => planInfoOf(d)?.key == planDays[i][k]).id,
    });
    return r.plan;
  }

  test('Αλλαγή γεύματος: φαγητό της βιβλιοθήκης που περνά τους ελέγχους', () async {
    final s = store();
    final w = weekOf(s);
    final dinner = w.days[0].indexWhere((x) => x.meal == Meal.dinner); // Δευτέρα βράδυ: σολομός
    String? offered;
    final ai = FakeAi((a, n) {
      offered = a.messages.first.$2;
      return fence({'kind': aiSwapKind, 'key': 'tsipoura'});
    });
    final r = await aiSwapSlot(
        call: ai.call, food: s, kitchen: Kitchen.initial(), w: w, day: 0, index: dinner, reason: SwapReason.appetite, now: 1, newId: () => 'x');
    if (r.dish == null) {
      // Η τσιπούρα δεν ήταν ανάλογη (δεν δόθηκε στη λίστα): τότε το AI ξαναρωτήθηκε και κανένα δεν πέρασε.
      expect(offered, isNot(contains('tsipoura ·')));
      expect(r.errors, isNotEmpty);
    } else {
      expect(planInfoOf(r.dish!)!.key, 'tsipoura');
      expect(r.isNew, isFalse);
      final old = plannedTotals(s, s.dishById(w.days[0][dinner].dishId), w.days[0][dinner])!;
      final pf = portionFor(s, r.dish!, old.kcal)!;
      expect(analogProblems((kcal: old.kcal, protein: old.protein, sat: old.satFat), pf.n), isEmpty);
      final w2 = applySwap(w, 0, dinner, r.dish!, r.kcal!);
      expect(w2.days[0][dinner].dishId, r.dish!.id);
      expect(w2.days[0][dinner].locked, isFalse);
    }
    // Ποτέ φαγητό με «δε μου αρέσει» ή το ίδιο φαγητό στη λίστα.
    expect(offered, isNot(contains('mosxari')));
    expect(offered, isNot(contains('solomos ·')));
  });

  test('Αλλαγή γεύματος: «Δεν έχω χρόνο» θέλει ως 15′, «Λείπει υλικό» το αποκλείει', () {
    final s = store();
    const old = (kcal: 600.0, protein: 50.0, sat: 6.0);
    final allowed = aiAllowedIds(likes);
    Dish k(String key) => s.dishes.firstWhere((d) => planInfoOf(d)?.key == key);
    List<String> check(String key, SwapReason why, {String? missing}) => swapChecks(s, k(key),
        meal: Meal.lunch, office: false, reason: why, missingId: missing, old: old, allowed: allowed, currentId: 'none');
    expect(check('kotopoulo-ryzi', SwapReason.time).join(), contains('15 λεπτά'));
    expect(check('kotopoulo-salata', SwapReason.time).join(), isNot(contains('15 λεπτά')));
    expect(check('kotopoulo-salata', SwapReason.missing, missing: feta).join(), contains('υλικό που λείπει'));
    expect(check('solomos', SwapReason.appetite).join(), contains('δεν είναι για μεσημέρι'));
  });

  test('«Έφαγα κάτι άλλο»: οι υπόλοιπες μερίδες της μέρας μικραίνουν, μέσα στα όριά τους', () {
    final s = store();
    final w = weekOf(s);
    final byId = {for (final d in s.dishes) d.id: d};
    final lunch = w.days[0].indexWhere((x) => x.meal == Meal.lunch);
    final ate = w.withSlot(0, lunch, w.days[0][lunch].copyWith(state: SlotState.other));
    final r = rebalanceDay(s, ate, 0, 1100, 2100); // μεσημέρι 1.100 kcal αντί για ~800
    expect(r, isNotNull);
    final (w2, changes) = r!;
    expect(changes, isNotEmpty);
    for (final (_, before, after) in changes) {
      expect(after, lessThan(before));
    }
    for (final x in w2.days[0]) {
      if (x.state != SlotState.open) continue;
      final range = portionRange(s, byId[x.dishId]!)!;
      expect(x.kcal!, inInclusiveRange(range.lo - 10, range.hi + 10));
    }
    // Τίποτα ανοιχτό: τίποτα να αλλάξει.
    var closed = ate;
    for (var k = 0; k < closed.days[0].length; k++) {
      closed = closed.withSlot(0, k, closed.days[0][k].copyWith(state: SlotState.ate));
    }
    expect(rebalanceDay(s, closed, 0, 2500, 2100), isNull);
  });

  group('Γέφυρα', () {
    test('Διεύθυνση: μόνο https://<20>.supabase.co/functions/v1/ai-food ή σκέτο Project ID', () {
      const id = 'abcdefghij0123456789';
      expect(bridgeUrl(id).toString(), 'https://$id.supabase.co/functions/v1/ai-food');
      expect(bridgeUrl(' https://$id.supabase.co/functions/v1/ai-food/ ').toString(), 'https://$id.supabase.co/functions/v1/ai-food');
      expect(bridgeUrl('http://$id.supabase.co/functions/v1/ai-food'), isNull);
      expect(bridgeUrl('https://$id.supabase.co.evil.com/functions/v1/ai-food'), isNull);
      expect(bridgeUrl('https://$id.supabase.co/functions/v1/other'), isNull);
      expect(bridgeUrl('https://evil.com/?$id.supabase.co/functions/v1/ai-food'), isNull);
    });

    test('Κλειδί γέφυρας: 43 χαρακτήρες, κάθε φορά άλλο', () {
      final a = newBridgeToken(), b = newBridgeToken();
      expect(a, hasLength(43));
      expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(a), isTrue);
      expect(a, isNot(b));
    });

    test('Απαντήσεις της γέφυρας', () {
      expect(parseBridgeReply(200, '{"ok":true,"text":"x","stop":"end_turn"}').ok, isTrue);
      expect(parseBridgeReply(200, '{"ok":true,"text":"x","stop":"max_tokens"}').cut, isTrue);
      expect(parseBridgeReply(200, '{"ok":true,"text":"","stop":"refusal"}').fail, AiFail.refused);
      expect(parseBridgeReply(401, '{"ok":false,"kind":"token"}').fail, AiFail.token);
      expect(parseBridgeReply(402, '{"ok":false,"kind":"credits"}').fail, AiFail.credits);
      expect(parseBridgeReply(502, '{"ok":false,"kind":"apikey"}').fail, AiFail.apiKey);
      expect(parseBridgeReply(503, '{"ok":false,"kind":"busy"}').fail, AiFail.busy);
      expect(parseBridgeReply(540, 'paused').fail, AiFail.paused);
      expect(parseBridgeReply(502, '<html>').fail, AiFail.server);
      expect(parseBridgeReply(404, 'not found').fail, AiFail.bad);
      for (final f in AiFail.values) {
        expect(aiErrorText(f), isNotEmpty);
      }
    });

    test('Σύνδεση: χωρίς διεύθυνση δεν στέλνει τίποτα· με διεύθυνση στέλνει το κλειδί στη γέφυρα', () async {
      final sent = <(Uri, String, String)>[];
      final b = AiBridge(MemoryVault(), send: (u, t, body) async {
        sent.add((u, t, body));
        return (200, '{"ok":true,"text":"γεια","stop":"end_turn"}');
      });
      const ask = AiAsk(model: aiModelRecipe, system: 's', messages: [('user', 'γεια')]);
      expect((await b.call(ask)).fail, AiFail.notSetUp);
      expect(await b.setUrl('https://evil.com'), isFalse);
      expect(await b.setUrl('abcdefghij0123456789'), isTrue);
      final t = await b.ensureToken();
      expect(await b.ensureToken(), t);
      final r = await b.call(ask);
      expect(r.text, 'γεια');
      expect(sent.single.$1.host, 'abcdefghij0123456789.supabase.co');
      expect(sent.single.$2, t);
      final j = jsonDecode(sent.single.$3) as Map;
      expect(j['model'], aiModelRecipe);
      expect(j['messages'], [
        {'role': 'user', 'content': 'γεια'}
      ]);
      await b.disconnect();
      expect(b.ready, isFalse);
    });
  });
}
