// AI για το φαγητό (19/11, βαθύς έλεγχος 19/11): έλεγχοι χωρίς δίκτυο, με ψεύτικο AI. Βιβλιοθήκη και προτιμήσεις επινοημένες.
import 'dart:convert';
import 'dart:io';

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
const beef = 'C6206', apple = 'C13039', rusks = 'C7340', salt = 'C11017', egg = 'C22000', tunaCan = 'C26039';

final lib = [
  dish('fakes', 'pot', [(lentils, 500), (onion, 150), (oil, 40)], meals: ['lunch', 'dinner'], office: true, servings: 6, tags: ['όσπρια']),
  dish('revithia', 'pot', [(chickpeas, 500), (onion, 150), (oil, 40)], meals: ['lunch', 'dinner'], office: true, servings: 6, tags: ['όσπρια']),
  dish('fasolada', 'pot', [(beans, 500), (tomato, 300), (oil, 40)], meals: ['lunch', 'dinner'], office: true, servings: 6, tags: ['όσπρια']),
  dish('kotopoulo-ryzi', 'plate', [(chicken, 200), (rice, 90), (oil, 10)], meals: ['lunch', 'dinner'], minutes: 25),
  dish('kotopoulo-salata', 'plate', [(chicken, 200), (tomato, 250), (oil, 20), (feta, 40)], meals: ['lunch', 'dinner'], office: true, minutes: 10),
  dish('solomos', 'plate', [(salmon, 200), (rice, 80)], meals: ['dinner'], tags: ['λιπαρό ψάρι']),
  dish('solomos-ryzi', 'plate', [(salmon, 200), (rice, 80)], meals: ['dinner'], tags: ['λιπαρό ψάρι']),
  dish('tsipoura', 'plate', [(bream, 350), (tomato, 150), (oil, 15)], meals: ['dinner'], tags: ['ψάρι']),
  dish('mosxari', 'plate', [(beef, 200), (rice, 80)], meals: ['dinner'], tags: ['κόκκινο κρέας']),
  dish('giaourti', 'plate', [(yogurt, 250), (apple, 150), (rusks, 30)], meals: ['snack'], cook: 'none'),
  dish('frygania', 'plate', [(rusks, 40), (feta, 40), (tomato, 100)], meals: ['snack'], cook: 'none'),
  dish('milo-giaourti', 'plate', [(yogurt, 250), (rusks, 40)], meals: ['snack'], cook: 'none'),
];

/// Μου αρέσουν όλα εκτός από μοσχάρι· ελαιόλαδο, κρεμμύδι και αλάτι είναι «βασικά κουζίνας».
const likes = FoodLikes(
  like: [lentils, chickpeas, beans, tomato, chicken, rice, yogurt, feta, salmon, bream, apple, rusks, egg, tunaCan],
  staple: [oil, onion, salt],
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

const AiTargets targets = (kcal: 2100, protein: 130, satMax: 22.0, fiber: 30, salt: 6.0);
const meals = [Meal.lunch, Meal.snack, Meal.dinner];

String fence(Object j) => 'Ορίστε:\n```json\n${jsonEncode(j)}\n```';

const newKey = 'ai-kotopoulo-fournou';

/// Οι μέρες του σχεδίου (Δευτέρα 23/11 ως Κυριακή 29/11): [μεσημέρι, σνακ, βράδυ]. Τρ–Πε μεσημέρι γραφείο: κατσαρόλα μόνο
/// ως περίσσευμα του προηγούμενου βραδιού.
final planDays = [
  ['kotopoulo-ryzi', 'giaourti', 'fakes'],
  ['fakes', 'frygania', newKey],
  [newKey, 'giaourti', 'tsipoura'],
  ['kotopoulo-salata', 'milo-giaourti', 'kotopoulo-ryzi'],
  ['fasolada', 'frygania', 'solomos'],
  ['revithia', 'giaourti', 'fasolada'],
  ['kotopoulo-salata', 'milo-giaourti', 'revithia'],
];

Map<String, Object> newJson({String key = newKey}) => {
      'key': key,
      'name': 'Κοτόπουλο φούρνου με ντομάτα',
      'type': 'pot',
      'cook': 'home',
      'minutes': 50,
      'meals': ['lunch', 'dinner'],
      'office': true,
      'idea': 'κοτόπουλο, ντομάτα, κρεμμύδι, ελαιόλαδο',
    };

Map<String, Object> planJson({List<List<String>>? days, List<Map<String, Object>>? news}) => {
      'kind': aiWeekKind,
      'new': news ?? [newJson()],
      'days': [
        for (final d in days ?? planDays)
          [
            {'meal': 'lunch', 'key': d[0]},
            {'meal': 'snack', 'key': d[1]},
            {'meal': 'dinner', 'key': d[2]},
          ],
      ],
    };

Map<String, Object> recipeJson(List<(String, double)> items, {String key = newKey, String type = 'pot', String cook = 'home', bool office = true}) => {
      'kind': libraryKind,
      'dishes': [
        {
          ...dish(key, type, items, meals: ['lunch', 'dinner'], office: office, servings: type == 'plate' ? null : 4, minutes: 50, cook: cook),
          'name': 'Κοτόπουλο φούρνου με ντομάτα',
          // Αριθμοί του AI: πρέπει να αγνοηθούν.
          'kcal': 99999,
        }
      ],
    };

AiNewDish want({String key = newKey}) => AiNewDish(key: key, name: 'Κοτόπουλο φούρνου με ντομάτα', idea: '', json: newJson(key: key));

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

AiWeekAsk askOf([Map<(int, Meal), String> kept = const {}]) => (from: monday, days: 7, meals: meals, kept: kept);

void main() {
  test('Επιτρεπόμενα: μου αρέσει + βασικά, ποτέ «δε μου αρέσει»· με το τωρινό id και την ωμή μορφή', () {
    final s = store();
    final a = aiAllowedIds(s);
    expect(a, containsAll([chicken, oil, salt]));
    expect(a, isNot(contains(beef)));
    // Μαγειρεμένη μορφή στα «Μου αρέσει» → η ωμή επιτρέπεται (I-17). «Δε μου αρέσει» το ψητό → ούτε το ωμό.
    final s2 = store(l: const FoodLikes(like: ['C6207'], staple: [oil]));
    expect(aiAllowedIds(s2), contains('C6206'));
    final s3 = store(l: const FoodLikes(like: [chicken, beef], dislike: ['C6207']));
    expect(aiAllowedIds(s3), isNot(contains(beef)));
    // Το «δε μου αρέσει» βγάζει ένα υλικό και από τα βασικά όταν διαβάζεται.
    final l = FoodLikes.fromJson({'like': ['A'], 'dislike': ['C'], 'staple': ['C', 'D']});
    expect(l.staple, ['D']);
    expect(FoodLikes.fromJson(l.toJson()).staple, ['D']);
    // Αντικατεστημένα id (I-2): mapIds.
    final m = const FoodLikes(like: ['OLD', 'NEW'], staple: ['OLD'], dislike: ['X']).mapIds((id) => id == 'OLD' ? 'NEW' : id);
    expect(m.like, ['NEW']);
    expect(m.staple, ['NEW']);
  });

  test('Η βιβλιοθήκη του AI: μόνο φαγητά με επιτρεπόμενα υλικά, όχι «Δεν μου άρεσε»', () {
    final s = store();
    final keys = {for (final d in aiLibrary(s, aiAllowedIds(s))) planInfoOf(d)!.key};
    expect(keys, isNot(contains('mosxari')));
    expect(keys, contains('fakes'));
    final s2 = store(l: likes.copyWith(staple: [onion]));
    final keys2 = {for (final d in aiLibrary(s2, aiAllowedIds(s2))) planInfoOf(d)!.key};
    expect(keys2, isNot(contains('fakes')));
    expect(keys2, contains('solomos'));
    final sol = s.dishes.firstWhere((d) => planInfoOf(d)?.key == 'solomos');
    final s3 = FoodStore.preloaded(
        foods: basicFoods(), dishes: [for (final d in s.dishes) d.id == sol.id ? withRating(d, -1) : d], likes: likes, now: monday);
    expect({for (final d in aiLibrary(s3, aiAllowedIds(s3))) planInfoOf(d)!.key}, isNot(contains('solomos')));
  });

  test('Οι οδηγίες: μόνο επιτρεπόμενα τρόφιμα· στόχοι μόνο ως θερμίδες ανά γεύμα (όχι πρωτεΐνη/κορεσμένα, X-3)', () {
    final s = store();
    final sys = aiSystem(s, aiAllowedIds(s), Kitchen.initial());
    expect(sys, contains(chicken));
    expect(sys, isNot(contains(beef)));
    expect(sys, contains('ΠΟΤΕ ωμό'));
    final p = aiPlanPrompt(food: s, ask: askOf(), library: aiLibrary(s, aiAllowedIds(s)), dayKcal: 2090);
    expect(p, contains('μεσημέρι ~850 kcal'));
    expect(p, isNot(contains('mosxari')));
    expect(p, isNot(contains('2.090')));
    for (final w in ['Oura', 'ύπνος', 'παλμ', 'πίεση', 'σάκχαρ', 'πρωτεΐνη 130', 'κορεσμένα έως']) {
      expect('$sys$p'.contains(w), isFalse, reason: w);
    }
  });

  test('Ωμά που θέλουν μαγείρεμα (S-1)', () {
    final f = {for (final x in basicFoods()) x.id: x};
    for (final id in [chicken, egg, salmon, lentils, rice, 'C9810', 'C4008', 'C20061', 'U168277', 'C9436']) {
      expect(aiNeedsCooking(f[id]!), isTrue, reason: f[id]!.name);
    }
    for (final id in [tunaCan, yogurt, feta, tomato, apple, rusks, 'C26037', 'C26700', 'C28900', 'C20532', 'C32140', 'C22010']) {
      expect(aiNeedsCooking(f[id]!), isFalse, reason: f[id]!.name);
    }
  });

  test('Μία συνταγή: εκτός λίστας, ωμό σε «χωρίς μαγείρεμα», αλάτι, λάδι, ίδια με το σχέδιο', () {
    final s = store();
    var n = 0;
    final allowed = aiAllowedIds(s);
    ({Dish? dish, List<String> errors}) read(Map<String, Object> j, {AiNewDish? w, Set<Meal> needMeals = const {}, bool office = false}) =>
        aiReadDish(fence(j), food: s, allowed: allowed, now: 1, newId: () => 'N${n++}', want: w, needMeals: needMeals, needOffice: office);
    expect(read(recipeJson([(chicken, 800), (beef, 200), (oil, 30)]), w: want()).errors.join(), contains(nameOf(beef)));
    // «Κοτοσαλάτα» χωρίς μαγείρεμα με ωμό στήθος: ποτέ.
    final raw = read(recipeJson([(chicken, 250), (tomato, 200), (oil, 10)], key: 'ai-kotosalata', type: 'plate', cook: 'none'));
    expect(raw.dish, isNull);
    expect(raw.errors.join(), contains('θέλουν μαγείρεμα'));
    // Τόνος κονσέρβα χωρίς μαγείρεμα: εντάξει.
    expect(read(recipeJson([(tunaCan, 150), (tomato, 200), (oil, 10), (rusks, 40)], key: 'ai-tonosalata', type: 'plate', cook: 'none')).errors, isEmpty);
    // 60 g αλάτι (αντί για 6) ή 120 g λάδι στο πιάτο: πίσω στο AI (L-1).
    expect(read(recipeJson([(chicken, 200), (rice, 90), (oil, 10), (salt, 60)], key: 'ai-a', type: 'plate')).errors.join(), contains('αλάτι'));
    expect(read(recipeJson([(chicken, 200), (rice, 90), (oil, 120)], key: 'ai-b', type: 'plate')).errors.join(), contains('Λάδι'));
    // Το σχέδιο είπε κατσαρόλα για γραφείο· η συνταγή γυρνά πιάτο όχι για γραφείο (L-3).
    final diff = read(recipeJson([(chicken, 900), (tomato, 400), (onion, 150), (oil, 30)], type: 'plate', office: false),
        w: want(), needMeals: {Meal.lunch}, office: true);
    expect(diff.errors.join(), contains('"type"'));
    expect(diff.errors.join(), contains('"office": true'));
    // Νέο φαγητό χωρίς «ai-»: όχι.
    expect(read(recipeJson([(chicken, 900), (tomato, 400)], key: 'kotopoulo')).errors.join(), contains('ai-'));
    final ok = read(recipeJson([(chicken, 900), (tomato, 400), (onion, 150), (oil, 30)]), w: want(), needMeals: {Meal.lunch, Meal.dinner}, office: true);
    expect(ok.errors, isEmpty);
    expect(planInfoOf(ok.dish!)!.key, newKey);
    expect(ok.dish!.extra['by'], 'ai');
    expect(recipeOf(ok.dish!)!.keeps, contains('2 μέρες'));
    expect(ok.dish!.extra.toString(), isNot(contains('99999')));
  });

  test('Το σχέδιο: δομή, γραφείο, κανόνες επανάληψης και κατσαρόλας', () {
    final s = store();
    final libMap = {for (final d in aiLibrary(s, aiAllowedIds(s))) planInfoOf(d)!.key!: d};
    final all = {for (final d in libraryDishes(s.dishes)) planInfoOf(d)!.key!};
    final ok = parseAiPlan(fence(planJson()), askOf(), libMap, all);
    expect(ok.errors, isEmpty);
    expect(ok.plan!.newDishes.single.key, newKey);

    List<List<String>> edit(void Function(List<List<String>> d) f) {
      final d = [for (final x in planDays) List.of(x)];
      f(d);
      return d;
    }

    String errs(List<List<String>> d, {List<Map<String, Object>>? news}) =>
        parseAiPlan(fence(planJson(days: d, news: news)), askOf(), libMap, all).errors.join(' | ');
    expect(errs(edit((d) => d[0][2] = 'mosxari')), contains('«mosxari»'));
    expect(errs(edit((d) => d[1][0] = 'kotopoulo-ryzi')), contains('γραφείο'));
    // Κατσαρόλα 3 μέρες μετά (fakes Δε και Πε): όχι.
    expect(errs(edit((d) => d[3][2] = 'fakes')), contains('το πολύ 2'));
    // Κατσαρόλα πρώτη φορά στο γραφείο (Τετάρτη μεσημέρι, νέα): όχι.
    expect(errs(edit((d) {
      d[1][2] = 'tsipoura';
      d[2][2] = 'kotopoulo-ryzi';
      d[3][2] = 'solomos';
    })), contains('πρώτη φορά στο γραφείο'));
    // Πιάτο σε συνεχόμενες μέρες: όχι.
    expect(errs(edit((d) => d[4][2] = 'kotopoulo-ryzi')), contains('συνεχόμενη'));
    // Σνακ κάθε μέρα: εντάξει.
    expect(errs(edit((d) {
      for (final x in d) {
        x[1] = 'giaourti';
      }
    })), isEmpty);
    expect(errs(planDays, news: [newJson(key: 'kotopoulo-fournou')]), contains('ai-'));
    final j = planJson();
    ((j['days'] as List)[3] as List).removeAt(1);
    expect(parseAiPlan(fence(j), askOf(), libMap, all).errors.join(), contains('λείπει το σνακ'));
    // Στη διόρθωση: το νέο φαγητό ξαναγραμμένο στο "new" δεν είναι λάθος (L-8).
    final extraDish = s.dishes.firstWhere((d) => planInfoOf(d)?.key == 'fasolada');
    expect(parseAiPlan(fence(planJson()), askOf(), {...libMap, newKey: extraDish}, {...all, newKey}, extra: {newKey: extraDish}).errors, isEmpty);
  });

  test('Όλη η εβδομάδα: σχέδιο → συνταγή (με μία διόρθωση) → μερίδες από τη βάση → έλεγχοι', () async {
    final s = store();
    var recipeTries = 0;
    final ai = FakeAi((a, n) {
      if (isRecipe(a)) {
        recipeTries++;
        // 1η φορά με μοσχάρι (απαγορεύεται)· 2η σωστά.
        return fence(recipeJson(recipeTries == 1 ? [(chicken, 800), (beef, 200), (oil, 30)] : [(chicken, 900), (tomato, 400), (onion, 150), (oil, 30)]));
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
      bodyKg: 80,
      now: 1,
      today: monday,
      newId: () => 'N${n++}',
      progress: (st, _, __, ___) => stages.add(st),
    );
    expect(r.fail, isNull);
    expect(r.errors, isEmpty);
    expect(recipeTries, 2);
    final retry = ai.asks.where(isRecipe).last;
    expect(retry.messages, hasLength(3));
    expect(retry.messages.last.$2, contains(nameOf(beef)));
    expect(stages.first, AiStage.plan);
    expect(stages, contains(AiStage.recipes));

    final w = r.plan!;
    expect(w.source, 'ai');
    expect(w.meals, meals);
    expect(w.days, hasLength(7));
    expect(r.newDishes.single.name, 'Κοτόπουλο φούρνου με ντομάτα');
    final byId = {for (final d in [...s.dishes, ...r.newDishes]) d.id: d};
    for (var i = 0; i < 7; i++) {
      final got = {for (final x in w.days[i]) x.meal: planInfoOf(byId[x.dishId]!)!.key};
      expect(got, {Meal.lunch: planDays[i][0], Meal.snack: planDays[i][1], Meal.dinner: planDays[i][2]}, reason: 'μέρα $i');
      for (final x in w.days[i]) {
        final range = portionRange(s, byId[x.dishId]!)!;
        expect(x.kcal!, inInclusiveRange(range.lo - 10, range.hi + 10), reason: 'μέρα $i ${x.meal}');
      }
      // Θερμίδες της μέρας από τη βάση κοντά στον στόχο (όχι από τα «99999» του AI).
      final day = plannedDay(s, w, i, extra: r.newDishes).totals.kcal;
      expect(day, closeTo(2100, 2100 * 0.12), reason: 'μέρα $i');
    }
    // Ο έλεγχος του προγράμματος έτρεξε (π.χ. η κατσαρόλα των φακών: ο χρήστης τρώει πάνω από το μισό).
    expect(r.notes.join(), contains('της κατσαρόλας'));
  });

  test('Μέρες πριν από σήμερα μένουν όπως είναι (U-23)', () async {
    final s = store();
    final ai = FakeAi((a, n) => isRecipe(a)
        ? fence(recipeJson([(chicken, 900), (tomato, 400), (onion, 150), (oil, 30)]))
        : fence(planJson()));
    final first = await aiBuildWeek(
        call: ai.call, food: s, kitchen: Kitchen.initial(), targets: targets, from: monday, meals: meals, now: 1, today: monday, newId: () => 'x1');
    final w0 = first.plan!;
    // Πέμπτη: ξανά με AI. Δε–Τε μένουν (και ξεκλείδωτα όπως ήταν).
    final ai2 = FakeAi((a, n) => fence(planJson()));
    final s2 = FoodStore.preloaded(foods: basicFoods(), dishes: [...s.dishes, ...first.newDishes], likes: likes, now: monday, week: w0);
    final again = await aiBuildWeek(
        call: ai2.call, food: s2, kitchen: Kitchen.initial(), targets: targets, from: monday, meals: meals, keep: w0, now: 1,
        today: DateTime(2026, 11, 26), newId: () => 'x2');
    expect(again.plan, isNotNull, reason: again.errors.join());
    for (var i = 0; i < 3; i++) {
      expect([for (final x in again.plan!.days[i]) x.dishId], [for (final x in w0.days[i]) x.dishId], reason: 'μέρα $i');
      expect(again.plan!.days[i].every((x) => !x.locked), isTrue);
    }
    expect(ai2.asks.first.messages.first.$2, contains('ΜΕΝΟΥΝ ΙΔΙΑ'));
  });

  test('Λάθος σχέδιο 3 φορές → καμία εβδομάδα, το λέει', () async {
    final s = store();
    final bad = [for (final d in planDays) List.of(d)]..[0][2] = 'mosxari';
    final ai = FakeAi((a, n) => fence(planJson(days: bad)));
    final r = await aiBuildWeek(
        call: ai.call, food: s, kitchen: Kitchen.initial(), targets: targets, from: monday, meals: meals, now: 1, today: monday, newId: () => 'x');
    expect(r.plan, isNull);
    expect(ai.asks, hasLength(1 + aiMaxRetries));
    expect(r.errors.first, contains('ούτε στην 3η'));
    expect(r.errors.join(), contains('mosxari'));
  });

  test('autoWeek με aiOnly και χωρίς φαγητά: όλα κενά, τίποτα «κρυφά» (L-2)', () {
    final s = store();
    final r = autoWeek(s, from: monday, meals: meals, kcalTarget: 2100, proteinTarget: 130, now: 1, aiOnly: true);
    expect(r.plan.days.every((d) => d.isEmpty), isTrue);
  });

  test('Χωρίς «Μου αρέσει»: δεν ρωτά καν το AI', () async {
    final s = store(l: const FoodLikes());
    final ai = FakeAi((a, n) => '');
    final r = await aiBuildWeek(
        call: ai.call, food: s, kitchen: Kitchen.initial(), targets: targets, from: monday, meals: meals, now: 1, newId: () => 'x');
    expect(r.plan, isNull);
    expect(ai.asks, isEmpty);
    expect(r.errors.single, contains('τι σου αρέσει'));
  });

  test('Σφάλμα σύνδεσης και ακύρωση: σταματά αμέσως, καμία νέα κλήση', () async {
    final s = store();
    Future<AiReply> credits(AiAsk a) async => const AiReply.failed(AiFail.credits);
    final r = await aiBuildWeek(
        call: credits, food: s, kitchen: Kitchen.initial(), targets: targets, from: monday, meals: meals, now: 1, newId: () => 'x');
    expect(r.fail, AiFail.credits);
    var calls = 0;
    final cancel = AiCancel();
    final call = cancel.wrap((a) async {
      calls++;
      cancel.cancel();
      return AiReply.ok(fence(planJson()));
    });
    final r2 = await aiBuildWeek(call: call, food: s, kitchen: Kitchen.initial(), targets: targets, from: monday, meals: meals, now: 1, newId: () => 'x');
    expect(r2.fail, AiFail.cancelled);
    expect(calls, 1);
  });

  test('Κενή απάντηση: ξανά η ίδια ερώτηση, όχι κενό μήνυμα (X-2)· άρνηση: ξανά', () async {
    final seen = <AiAsk>[];
    var k = 0;
    Future<AiReply> call(AiAsk a) async {
      seen.add(a);
      k++;
      return k == 1 ? const AiReply.cutOff('') : k == 2 ? const AiReply.failed(AiFail.refused) : const AiReply.ok('ΟΚ');
    }

    final (v, _, f) = await aiAskUntilValid<String>(call, model: aiModelRecipe, system: 's', prompt: 'p', read: (t) => (t, const <String>[]));
    expect(f, isNull);
    expect(v, 'ΟΚ');
    for (final a in seen) {
      expect(a.messages.every((m) => m.$2.trim().isNotEmpty), isTrue);
      expect(a.messages, hasLength(1));
    }
  });

  test('Έλεγχος εβδομάδας: στόχος μέρας με μερίδιο γεύματος (L-6), κενό γεύμα, χωρίς αριθμούς στόχων για το AI', () {
    final s = store();
    WeekPlan weekWith(List<List<PlanSlot>> days) => WeekPlan(from: '2026-11-23', days: days, created: 1, meals: meals);
    Dish k(String key) => s.dishes.firstWhere((d) => planInfoOf(d)?.key == key);
    // Μέρα χωρίς μεσημεριανό: σνακ 440 + βράδυ 770 = σωστό για τα δύο γεύματα· όχι ψευδές πρόβλημα θερμίδων.
    final w = weekWith([
      [PlanSlot(meal: Meal.snack, dishId: k('giaourti').id, kcal: 440), PlanSlot(meal: Meal.dinner, dishId: k('tsipoura').id, kcal: 770)],
      for (var i = 1; i < 7; i++) const <PlanSlot>[],
    ]);
    final p = aiCheckWeek(s, w, const [], t: (kcal: 2200, protein: 130, satMax: 22, fiber: 30, salt: 6), meals: meals, checkDays: {0});
    expect(p.any((x) => x.user.contains('μεσημέρι έμεινε χωρίς φαγητό')), isTrue);
    expect(p.any((x) => x.day == 0 && x.user.contains('kcal (στόχος')), isFalse);
    for (final x in p) {
      expect(x.ai.contains('2200') || x.ai.contains('2.200') || x.ai.contains('130 g'), isFalse, reason: x.ai);
    }
  });

  test('Ανάλογο γεύμα: όρια θερμίδων, πρωτεΐνης, κορεσμένων', () {
    const old = (kcal: 600.0, protein: 45.0, sat: 5.0, salt: 1.0, fiber: 5.0);
    expect(analogProblems(old, (kcal: 650.0, protein: 41.0, sat: 6.0, salt: 1.0, fiber: 5.0)), isEmpty);
    expect(analogProblems(old, (kcal: 670.0, protein: 45.0, sat: 5.0, salt: 1.0, fiber: 5.0)), hasLength(1));
    expect(analogProblems(old, (kcal: 600.0, protein: 40.0, sat: 5.0, salt: 1.0, fiber: 5.0)), hasLength(1));
    expect(analogProblems(old, (kcal: 600.0, protein: 45.0, sat: 6.1, salt: 1.0, fiber: 5.0)), hasLength(1));
  });

  test('Μερίδα της αλλαγής: στρογγυλή όπως αποθηκεύεται (L-9/L-10)', () {
    final s = store();
    final d = s.dishes.firstWhere((x) => planInfoOf(x)?.key == 'kotopoulo-ryzi');
    final p = portionFor(s, d, 643)!;
    expect(p.kcal % 10, 0);
    final r = portionRange(s, d)!;
    expect(p.kcal, inInclusiveRange(r.lo, r.hi + 10));
  });

  WeekPlan weekOf(FoodStore s) {
    final r = autoWeek(s, from: monday, meals: meals, kcalTarget: 2100, proteinTarget: 130, now: 1, aiOnly: true, forced: {
      for (var i = 0; i < 7; i++)
        for (final (k, m) in [(0, Meal.lunch), (1, Meal.snack), (2, Meal.dinner)])
          if (planDays[i][k] != newKey) (i, m): s.dishes.firstWhere((d) => planInfoOf(d)?.key == planDays[i][k]).id,
    });
    return r.plan;
  }

  test('Αλλαγή γεύματος: φαγητό της βιβλιοθήκης που περνά τους ελέγχους (κλάδος επιτυχίας, L-15)', () async {
    final s = store();
    final w = weekOf(s);
    const day = 4; // Παρασκευή βράδυ: σολομός
    final idx = w.days[day].indexWhere((x) => x.meal == Meal.dinner);
    final locked = w.withSlot(day, idx, w.days[day][idx].copyWith(locked: true));
    String? offered;
    final ai = FakeAi((a, n) {
      offered = a.messages.first.$2;
      return fence({'kind': aiSwapKind, 'key': 'solomos-ryzi'});
    });
    final r = await aiSwapSlot(
        call: ai.call, food: s, kitchen: Kitchen.initial(), w: locked, day: day, index: idx, reason: SwapReason.appetite, now: 1, newId: () => 'x');
    expect(r.dish, isNotNull, reason: r.errors.join());
    expect(planInfoOf(r.dish!)!.key, 'solomos-ryzi');
    expect(r.isNew, isFalse);
    expect(offered, contains('solomos-ryzi ·'));
    expect(offered, isNot(contains('mosxari')));
    final w2 = applySwap(locked, day, idx, r.dish!, r.kcal!);
    expect(w2.days[day][idx].dishId, r.dish!.id);
    expect(w2.days[day][idx].locked, isTrue); // το κλείδωμα μένει (U-19)
    expect(w2.days[day][idx].kcal, r.kcal);
  });

  test('Αλλαγή γεύματος: «Δεν έχω χρόνο» θέλει ως 15′, «Λείπει υλικό» το αποκλείει', () {
    final s = store();
    const old = (kcal: 600.0, protein: 50.0, sat: 6.0, salt: 1.0, fiber: 5.0);
    final allowed = aiAllowedIds(s);
    Dish k(String key) => s.dishes.firstWhere((d) => planInfoOf(d)?.key == key);
    List<String> check(String key, SwapReason why, {String? missing}) => swapChecks(s, k(key),
        meal: Meal.lunch, office: false, reason: why, missingId: missing, old: old, allowed: allowed, currentId: 'none');
    expect(check('kotopoulo-ryzi', SwapReason.time).join(), contains('15 λεπτά'));
    expect(check('kotopoulo-salata', SwapReason.time).join(), isNot(contains('15 λεπτά')));
    expect(check('kotopoulo-salata', SwapReason.missing, missing: feta).join(), contains('υλικό που λείπει'));
    expect(check('solomos', SwapReason.appetite).join(), contains('δεν είναι για μεσημέρι'));
  });

  test('«Έφαγα κάτι άλλο»: μόνο τα επόμενα γεύματα, μέσα στα όριά τους, όχι κλειδωμένα', () {
    final s = store();
    final w = weekOf(s);
    final lunch = w.days[0].indexWhere((x) => x.meal == Meal.lunch);
    final ate = w.withSlot(0, lunch, w.days[0][lunch].copyWith(state: SlotState.other));
    final r = rebalanceDay(s, ate, 0, eaten: 1100, eatenProtein: 40, target: 2100, after: Meal.lunch, now: monday);
    expect(r, isNotNull);
    expect(r!.changes, isNotEmpty);
    for (final (m, _, before, after) in r.changes) {
      expect(m, isNot(Meal.lunch));
      expect(after, lessThan(before));
    }
    final byId = {for (final d in s.dishes) d.id: d};
    for (final x in r.plan.days[0]) {
      if (x.state != SlotState.open) continue;
      final range = portionRange(s, byId[x.dishId]!)!;
      expect(x.kcal!, inInclusiveRange(range.lo - 10, range.hi + 10));
    }
    expect(r.proteinAfter, lessThan(r.proteinBefore));
    // Μετά το βραδινό δεν έρχεται κανένα: τίποτα να αλλάξει.
    expect(rebalanceDay(s, ate, 0, eaten: 2500, eatenProtein: 80, target: 2100, after: Meal.dinner, now: monday), isNull);
    var lockedAll = ate;
    for (var k = 0; k < lockedAll.days[0].length; k++) {
      lockedAll = lockedAll.withSlot(0, k, lockedAll.days[0][k].copyWith(locked: true));
    }
    expect(rebalanceDay(s, lockedAll, 0, eaten: 1100, eatenProtein: 40, target: 2100, after: Meal.lunch, now: monday), isNull);
  });

  test('Ονόματα route χωρίς «:» (μάθημα: σπάει την αναφορά της πλοήγησης)', () {
    final re = RegExp(r"""RouteSettings\(name:\s*'[^']*:""");
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      expect(re.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
    }
  });

  test('Ο κώδικας του AI δεν διαβάζει δεδομένα υγείας ή Oura', () {
    for (final p in ['lib/food/ai_food.dart', 'lib/ai/ai_bridge.dart']) {
      final src = File(p).readAsStringSync();
      for (final bad in ['vitals.dart', 'training/', "import '../oura/oura_store", 'health_store', "import '../data.dart'", "import '../goals.dart'"]) {
        expect(src.contains(bad), isFalse, reason: '$p: $bad');
      }
    }
  });

  group('Γέφυρα', () {
    test('Διεύθυνση: μόνο https://<20>.supabase.co(/functions/v1/ai-food) ή σκέτο Project ID', () {
      const id = 'abcdefghij0123456789';
      expect(bridgeUrl(id).toString(), 'https://$id.supabase.co/functions/v1/ai-food');
      expect(bridgeUrl(' https://$id.supabase.co/functions/v1/ai-food/ ').toString(), 'https://$id.supabase.co/functions/v1/ai-food');
      expect(bridgeUrl('https://$id.supabase.co').toString(), 'https://$id.supabase.co/functions/v1/ai-food');
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

    test('Απαντήσεις της γέφυρας και της πύλης του Supabase (X-5)', () {
      expect(parseBridgeReply(200, '{"ok":true,"text":"x","stop":"end_turn"}').ok, isTrue);
      expect(parseBridgeReply(200, '{"ok":true,"text":"x","stop":"max_tokens"}').cut, isTrue);
      expect(parseBridgeReply(200, '{"ok":true,"text":"","stop":"refusal"}').fail, AiFail.refused);
      expect(parseBridgeReply(401, '{"ok":false,"kind":"token"}').fail, AiFail.token);
      expect(parseBridgeReply(401, '{"code":401,"message":"Missing authorization header"}').fail, AiFail.jwt);
      expect(parseBridgeReply(404, '{"code":"NOT_FOUND","message":"Requested function was not found"}').fail, AiFail.notDeployed);
      expect(parseBridgeReply(500, '{"ok":false,"kind":"setup"}').fail, AiFail.setup);
      expect(parseBridgeReply(402, '{"ok":false,"kind":"credits"}').fail, AiFail.credits);
      expect(parseBridgeReply(502, '{"ok":false,"kind":"apikey"}').fail, AiFail.apiKey);
      expect(parseBridgeReply(502, '{"ok":false,"kind":"model"}').fail, AiFail.model);
      expect(parseBridgeReply(503, '{"ok":false,"kind":"busy"}').fail, AiFail.busy);
      expect(parseBridgeReply(540, 'paused').fail, AiFail.paused);
      expect(parseBridgeReply(502, '<html>').fail, AiFail.server);
      expect(parseBridgeReply(303, '').fail, AiFail.server);
      for (final f in AiFail.values) {
        expect(aiErrorText(f), isNotEmpty);
      }
      expect(aiErrorText(AiFail.paused), contains('Resume project'));
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
      await b.markOk('2026-11-19');
      expect(b.okDay, '2026-11-19');
      expect(await b.setUrl('zzzzzzzzzz0123456789'), isTrue);
      expect(b.okDay, isNull); // άλλη διεύθυνση: ξανά δοκιμή
      await b.disconnect();
      expect(b.ready, isFalse);
    });

    test('Ασφαλής αποθήκευση που δεν απαντά: ποτέ νέο κλειδί πάνω στο παλιό (X-11)', () async {
      final v = MemoryVault();
      final t0 = await AiBridge(v).ensureToken();
      v.failLoads = true;
      final b = AiBridge(v);
      expect(await b.ensureToken(), isNull);
      expect((await b.call(const AiAsk(model: aiModelRecipe, system: 's', messages: [('user', 'x')]))).fail, AiFail.vault);
      v.failLoads = false;
      expect(await AiBridge(v).ensureToken(), t0);
    });

    test('Ακύρωση: καμία νέα κλήση μετά', () async {
      var calls = 0;
      final c = AiCancel();
      final call = c.wrap((a) async {
        calls++;
        return const AiReply.ok('x');
      });
      const a = AiAsk(model: aiModelRecipe, system: 's', messages: [('user', 'x')]);
      expect((await call(a)).text, 'x');
      c.cancel();
      expect((await call(a)).fail, AiFail.cancelled);
      expect(calls, 1);
    });
  });
}
