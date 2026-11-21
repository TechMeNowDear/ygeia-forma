// Βαθύς έλεγχος 20/11/2026, κατηγορία 2 (διατροφή): οι διορθώσεις K2-C-01…K2-C-17 και K2-S-01…K2-S-12. Μόνο επινοημένα
// φαγητά και σταθερές ημερομηνίες. Οι αριθμοί των σχολίων βγήκαν από τις αναφορές k2-calc / k2-science και από τη βάση.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/food/ai_food.dart';
import 'package:ygeia_forma/food/chol.dart';
import 'package:ygeia_forma/food/dishes.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/food/library.dart';
import 'package:ygeia_forma/food/off.dart';
import 'package:ygeia_forma/food/recipe.dart';
import 'package:ygeia_forma/food/week.dart';
import 'package:ygeia_forma/food/week_auto.dart' show portionRange;
import 'package:ygeia_forma/food/week_calc.dart';
import 'package:ygeia_forma/history.dart' show dateKey;

import 'sample_food.dart';

final _monday = DateTime(2026, 11, 23);

const _chicken = 'C36017', _rice = 'C9100', _oil = 'C17270', _yogurt = 'U170894', _apple = 'C13039', _salmon = 'C26036';
const _cod = 'C26043', _sardine = 'C26065', _feta = 'C12066', _tomato = 'C20385', _lentils = 'C20359', _onion = 'C20034';
const _cannedChickpeas = 'C20532', _pasta = 'C9810', _beef5 = 'C6250', _cucumber = 'C20019';

Food _food(String id) => basicFoods().firstWhere((f) => f.id == id);

Map<String, Object?> _dish(String key, String type, List<(String, double)> items,
        {List<String> meals = const ['lunch', 'dinner'], int? servings, String cook = 'home'}) =>
    {
      'key': key,
      'name': 'Φαγητό $key',
      'type': type,
      if (servings != null) 'servings': servings,
      'meals': meals,
      'cook': cook,
      'items': [for (final (id, g) in items) {'id': id, 'name': _food(id).name, 'g': g}],
      if (cook == 'home')
        'steps': [
          {'text': 'Μαγείρεψέ το.', 'min': 20}
        ],
    };

final _lib = [
  _dish('kotopoulo-ryzi', 'plate', [(_chicken, 200), (_rice, 90), (_oil, 10)]),
  _dish('giaourti', 'plate', [(_yogurt, 250), (_apple, 150)], meals: ['snack'], cook: 'none'),
  _dish('solomos', 'plate', [(_salmon, 200), (_rice, 80)]),
  _dish('bakaliaros', 'plate', [(_cod, 180), (_rice, 80), (_oil, 10)]),
  _dish('sardeles', 'plate', [(_sardine, 180), (_rice, 80)]),
  _dish('feta-salata', 'plate', [(_feta, 200), (_tomato, 300), (_oil, 20)]),
  _dish('salata', 'plate', [(_tomato, 200), (_cucumber, 150), (_chicken, 200), (_rice, 100), (_oil, 10)]),
  _dish('revithosalata', 'plate', [(_cannedChickpeas, 60), (_tomato, 200), (_oil, 10)], cook: 'none'),
  _dish('revithosalata-megali', 'plate', [(_cannedChickpeas, 100), (_tomato, 200), (_oil, 10)], cook: 'none'),
  _dish('pastitsio', 'portions', [(_pasta, 500), (_beef5, 600), (_oil, 40), (_tomato, 400)], servings: 6),
  _dish('fakes', 'pot', [(_lentils, 500), (_onion, 150), (_oil, 40)], servings: 6),
];

FoodStore _store({List<LogEntry> entries = const [], List<Dish>? dishes}) {
  var n = 0;
  final s0 = FoodStore.preloaded(foods: basicFoods(), now: _monday);
  final r = planLibraryImport(
    parseLibrary(jsonEncode({'kind': libraryKind, 'dishes': _lib})),
    existing: const [],
    food: (id) => s0.itemFood(DishItem(id, id, 1)),
    likes: const FoodLikes(),
    now: 1,
    newId: () => 'K${n++}',
  );
  expect(r.problems, isEmpty, reason: r.problems.map((p) => p.errors).join());
  return FoodStore.preloaded(foods: basicFoods(), dishes: dishes ?? r.added, entries: entries, now: _monday);
}

Dish _byKey(FoodStore s, String key) => s.dishes.firstWhere((d) => planInfoOf(d)?.key == key);

WeekPlan _week(List<List<PlanSlot>> days, {List<Meal> meals = const [Meal.lunch, Meal.snack, Meal.dinner]}) =>
    WeekPlan(from: dateKey(_monday), days: days, created: 1, source: 'test', meals: meals);

var _entryId = 0;
LogEntry _entry(String id, double g, Meal m, {DateTime? day, DishTag? dish}) {
  final d = day ?? _monday;
  return LogEntry(id: 'e${_entryId++}', day: dateKey(d), meal: m, food: _food(id), grams: g, time: DateTime(d.year, d.month, d.day, 14), dish: dish);
}

const AiTargets _targets = (kcal: 2150, protein: 140, satMax: 14.3, fiber: 30, salt: 5.0);

void main() {
  // ---------------------------------------------------------------------------------------------------------- K2-C-01
  group('K2-C-01: «Έφαγα κάτι άλλο» δεν μετρά δύο φορές γεύμα που γράφτηκε με «+ Φαγητό»', () {
    // Πρόγραμμα Δευτέρας: μεσημέρι κοτόπουλο με ρύζι, σνακ γιαούρτι, βράδυ σολομός. Το μεσημεριανό γράφτηκε με «+ Φαγητό»
    // (τα ίδια γραμμάρια), και στο σνακ «Έφαγα κάτι άλλο».
    final lunchEntries = [_entry(_chicken, 200, Meal.lunch), _entry(_rice, 90, Meal.lunch), _entry(_oil, 10, Meal.lunch)];
    final snackEntries = [_entry(_yogurt, 200, Meal.snack), _entry(_apple, 120, Meal.snack)];

    WeekPlan plan(FoodStore s, {SlotState lunch = SlotState.open, String? lunchGrp}) => _week([
          [
            PlanSlot(meal: Meal.lunch, dishId: _byKey(s, 'kotopoulo-ryzi').id, kcal: 700, state: lunch, grp: lunchGrp),
            PlanSlot(meal: Meal.snack, dishId: _byKey(s, 'giaourti').id, kcal: 300, state: SlotState.other),
            PlanSlot(meal: Meal.dinner, dishId: _byKey(s, 'solomos').id, kcal: 700),
          ],
        ]);

    test('mealsEatenOutsidePlan: μόνο προηγούμενο γεύμα, με ανοιχτές θέσεις και αρκετό φαγητό στο ημερολόγιο', () {
      final s = _store(entries: [...lunchEntries, ...snackEntries]);
      final w = plan(s);
      expect(mealsEatenOutsidePlan(s, w, 0, before: Meal.snack), {Meal.lunch});
      expect(mealsEatenOutsidePlan(s, w, 0, before: Meal.lunch), isEmpty, reason: 'το ίδιο το γεύμα δεν είναι «προηγούμενο»');
      // Μόνο ένας καφές με γάλα στο μεσημέρι (κάτω από το μισό της θέσης): η θέση μένει «θα φαγωθεί ακόμα».
      final coffee = _store(entries: [_entry(_yogurt, 50, Meal.lunch), ...snackEntries]);
      expect(mealsEatenOutsidePlan(coffee, plan(coffee), 0, before: Meal.snack), isEmpty);
      // Χωρίς τίποτα στο μεσημέρι: όπως πριν.
      final none = _store(entries: snackEntries);
      expect(mealsEatenOutsidePlan(none, plan(none), 0, before: Meal.snack), isEmpty);
      expect(rebalanceEatenShare, 0.5);
    });

    test('rebalanceDay: η μέρα κλείνει κοντά στον στόχο (πριν: το βραδινό κοβόταν στο ελάχιστο)', () {
      final s = _store(entries: [...lunchEntries, ...snackEntries]);
      final w = plan(s);
      final t = Totals(s.entriesFor(_monday));
      expect(t.kcal, greaterThan(700));
      final r = rebalanceDay(s, w, 0, eaten: t.kcal, eatenProtein: t.protein, target: 2150, after: Meal.snack, now: _monday);
      expect(r, isNotNull);
      final (meal, _, before, after) = r!.changes.single;
      expect(meal, Meal.dinner);
      expect(after, greaterThan(before), reason: 'μένουν θερμίδες για το βράδυ: η μερίδα μεγαλώνει, δεν μικραίνει');
      // Η μέρα = ό,τι γράφτηκε + το νέο βραδινό, χωρίς το μεσημεριανό δεύτερη φορά.
      expect(r.dayKcal, closeTo(t.kcal + after, 1.0));
      final range = portionRange(s, _byKey(s, 'solomos'))!;
      expect(after, inInclusiveRange(range.lo - 10, range.hi + 10));
    });

    test('με «Το έφαγα» στο μεσημεριανό (θέση «ate»): ίδιο αποτέλεσμα με πριν τη διόρθωση', () {
      const grp = 'g1';
      final tagged = [
        for (final e in lunchEntries)
          LogEntry(id: '${e.id}t', day: e.day, meal: e.meal, food: e.food, grams: e.grams, time: e.time,
              dish: DishTag(id: 'x', name: 'Φαγητό', kind: DishKind.plate, grp: grp, qty: 300)),
      ];
      final s = _store(entries: [...tagged, ...snackEntries]);
      final w = plan(s, lunch: SlotState.ate, lunchGrp: grp);
      expect(mealsEatenOutsidePlan(s, w, 0, before: Meal.snack), isEmpty);
      final t = Totals(s.entriesFor(_monday));
      final r = rebalanceDay(s, w, 0, eaten: t.kcal, eatenProtein: t.protein, target: 2150, after: Meal.snack, now: _monday);
      expect(r, isNotNull);
      expect(r!.dayKcal, closeTo(t.kcal + r.changes.single.$4, 1.0));
    });
  });

  // ---------------------------------------------------------------------------------------------------------- K2-C-02
  group('K2-C-02: το πρόγραμμα δείχνει ό,τι θα γράψει το «Το έφαγα»', () {
    test('ίσες μερίδες: ίδιες θερμίδες στο πρόγραμμα και στο ημερολόγιο για κάθε τιμή θέσης (πριν: ως ±220 kcal)', () {
      final s = _store();
      final d = _byKey(s, 'pastitsio');
      final one = itemsTotals(s, dishAmounts(d, servings: 1))!.kcal;
      for (var kcal = 150.0; kcal <= 1600; kcal += 73) {
        final slot = PlanSlot(meal: Meal.lunch, dishId: d.id, kcal: kcal);
        final planned = plannedTotals(s, d, slot)!;
        final log = slotLog(s, d, slot, _monday)!;
        expect(planned.kcal, closeTo(Totals(s.previewDish(log.amounts)!).kcal, 0.01), reason: '$kcal');
        expect(log.qty, servingsFor(kcal, one), reason: '$kcal');
        expect((log.qty * 2).roundToDouble(), log.qty * 2, reason: 'μισές μερίδες');
        expect(planned.kcal, closeTo(log.qty * one, 1.0), reason: '$kcal');
      }
      // Το παράδειγμα της αναφοράς: θέση κοντά σε 1,25 μερίδες γράφεται 1 ή 1,5, και το πρόγραμμα λέει το ίδιο.
      final near = PlanSlot(meal: Meal.lunch, dishId: d.id, kcal: one * 1.2);
      expect(plannedTotals(s, d, near)!.kcal, closeTo(one, 1.0));
      expect(servingsFor(10, one), 0.5, reason: 'ποτέ κάτω από μισή μερίδα');
    });

    test('πιάτο και κατσαρόλα: όπως πριν (ακριβής κλιμάκωση στο πρόγραμμα)', () {
      final s = _store();
      final plate = _byKey(s, 'kotopoulo-ryzi');
      final natural = itemsTotals(s, plate.items)!.kcal;
      expect(plannedTotals(s, plate, PlanSlot(meal: Meal.lunch, dishId: plate.id, kcal: natural * 1.3))!.kcal, closeTo(natural * 1.3, 2.0));
      final pot = _byKey(s, 'fakes');
      final all = itemsTotals(s, pot.items)!.kcal;
      expect(plannedTotals(s, pot, PlanSlot(meal: Meal.lunch, dishId: pot.id, kcal: 500))!.kcal, closeTo(500, 2.0));
      expect(plannedTotals(s, pot, PlanSlot(meal: Meal.lunch, dishId: pot.id))!.kcal, closeTo(all / 6, 2.0));
    });
  });

  // ---------------------------------------------------------------------------------------------------------- K2-C-11
  test('K2-C-11: κατσαρόλα σε θέση χωρίς θερμίδες: η μερίδα της συνταγής από ΑΥΤΟ το μαγείρεμα (διπλή δόση)', () {
    final s = _store();
    final pot = _byKey(s, 'fakes');
    final one = itemsTotals(s, naturalRaw(pot)!)!.kcal; // 1 από τις 6 μερίδες της συνταγής
    // Ίδια δόση με τη συνταγή: έτοιμο 2.400 g → 400 g, όπως πριν.
    final same = PotBatch(at: _monday.millisecondsSinceEpoch, cooked: 2400, items: pot.items);
    expect(potPortion(s, pot, same, null), 400);
    // Διπλή δόση: έτοιμο 4.800 g. Η μερίδα της συνταγής είναι πάλι 400 g (πριν: 4.800 ÷ 6 = 800 g, διπλές θερμίδες).
    final twice = PotBatch(at: _monday.millisecondsSinceEpoch, cooked: 4800, items: [for (final i in pot.items) i.withAmount(i.amount * 2)]);
    final g = potPortion(s, pot, twice, null)!;
    expect(g, 400);
    expect(Totals(s.previewDish(dishAmounts(pot, portion: g, batch: twice))!).kcal, closeTo(one, one * 0.03));
  });

  // ------------------------------------------------------------------------------------------- K2-C-03 / K2-S-04, K2-S-02
  group('βάση: ζευγάρια ωμό/ψητό και κορεσμένα γαλακτοκομικών', () {
    test('K2-C-03: κάθε ζευγάρι κρέατος, πουλερικού, ψαριού, αυγού είναι το ίδιο κομμάτι (διατήρηση πρωτεΐνης)', () {
      final byId = {for (final f in basicFoods()) f.id: f};
      var checked = 0;
      for (final f in basicFoods()) {
        if (!const {'Κρέας', 'Πουλερικά', 'Ψάρια', 'Θαλασσινά', 'Αυγά'}.contains(f.cat)) continue;
        for (final (id, _) in f.cooked) {
          final g = byId[id]!;
          if (f.id == 'C10001' && g.id == 'C10084') continue; // καλαμάρι τηγανητό: κουρκούτι και λάδι
          final keep = g.n.amount(Nk.kcal) * (f.n.amount(Nk.protein) / g.n.amount(Nk.protein)) / f.n.amount(Nk.kcal);
          expect(keep, inInclusiveRange(0.65, 1.35), reason: '${f.name} → ${g.name}');
          checked++;
        }
      }
      expect(checked, greaterThan(30));
      // Τα δύο που δεν ήταν το ίδιο κομμάτι δεν είναι πια ζευγάρι, και τα ονόματα λένε τι είναι.
      expect(byId['C21500']!.name, 'Αρνίσια παϊδάκια (ωμά, με το λίπος)');
      expect(byId['C21501']!.name, 'Αρνίσια παϊδάκια (ψητά, μόνο το ψαχνό)');
      expect(byId['C6510']!.name, 'Μοσχαράκι μπριζόλα (ωμή, με το λίπος)');
      expect(byId['C6511']!.name, 'Μοσχαράκι μπριζόλα (ψητή, μόνο το ψαχνό)');
      for (final id in ['C21500', 'C6510']) {
        expect(aiNeedsCooking(byId[id]!), isTrue, reason: 'το ωμό θέλει ακόμα μαγείρεμα ($id)');
      }
    });

    test('K2-S-02: κορεσμένα 52–78% του λίπους στα γαλακτοκομικά και τα τυριά· το γιαούρτι 5% λέει «γενική τιμή»', () {
      for (final f in basicFoods()) {
        if (!const {'Γαλακτοκομικά', 'Τυριά'}.contains(f.cat) || f.id == 'U171304') continue;
        if (!f.n.has(Nk.fat) || !f.n.has(Nk.satFat) || f.n.amount(Nk.fat) < 2) continue;
        expect(f.n.amount(Nk.satFat) / f.n.amount(Nk.fat), inInclusiveRange(0.52, 0.78), reason: f.name);
      }
      expect(_food('U171304').name, 'Γιαούρτι στραγγιστό πλήρες 5% (γενική τιμή· προτίμησε το barcode)');
      expect(_food('C19863').name, 'Τζατζίκι έτοιμο (γενική τιμή· προτίμησε το barcode)');
    });

    test('K2-C-12: «άπαχο» είναι άλλο όνομα των 0%', () {
      for (final id in ['C19051', 'U170894', 'C19594']) {
        expect(_food(id).aliases, contains('άπαχο'), reason: id);
      }
    });
  });

  // ------------------------------------------------------------------------------------------------- K2-S-01, K2-S-03
  group('υδράργυρος και λιπαρό ψάρι', () {
    List<AiProblem> check(FoodStore s, List<String> dinners, {int fishWeek = 0, int legumesWeek = 0}) {
      final w = _week([
        for (final key in dinners) [PlanSlot(meal: Meal.dinner, dishId: _byKey(s, key).id)],
      ], meals: const [Meal.dinner]);
      return aiCheckWeek(s, w, const [],
          t: _targets, meals: const [Meal.dinner], checkDays: {for (var i = 0; i < dinners.length; i++) i}, fishWeek: fishWeek,
          legumesWeek: legumesWeek, bodyKg: 82.0);
    }

    test('K2-S-01: κάθε ψάρι και θαλασσινό της βάσης έχει τιμή· τα άλλα τρόφιμα 0', () {
      for (final f in basicFoods()) {
        if (f.cat == 'Ψάρια' || f.cat == 'Θαλασσινά') {
          expect(mercuryPpm(f), greaterThan(0), reason: f.name);
        } else {
          expect(mercuryPpm(f), 0, reason: f.name);
        }
      }
      expect(aiMercuryPpm.keys.every((id) => basicFoods().any((f) => f.id == id)), isTrue, reason: 'κάθε id του πίνακα υπάρχει');
      expect((mercuryPpm(_food(_cod)), mercuryPpm(_food(_sardine)), mercuryPpm(_food(_salmon))), (0.111, 0.013, 0.022));
      expect((mercuryPpm(_food('C26082')), mercuryPpm(_food('C26179')), mercuryPpm(_food('C26039'))), (0.995, 0.35, 0.126));
      expect(mercuryPpm(_food('C26088')), aiMercuryDefaultPpm, reason: 'τσιπούρα: δεν υπάρχει στον πίνακα της FDA');
    });

    test('K2-S-01: 6 × 180 g μπακαλιάρος με 82 kg → πάνω από το όριο EFSA (πριν: 0 µg)· 6 × 180 g σαρδέλα → εντάξει', () {
      final s = _store();
      // 6 × 180 × 0,111 = 119,9 µg· όριο 1,3 × 82 = 106,6.
      final cod = check(s, List.filled(6, 'bakaliaros')).where((p) => p.tag == 'mercury').toList();
      expect(cod, hasLength(1));
      expect(cod.single.user, contains('120 µg'));
      expect(cod.single.user, contains('όριο EFSA 106'), reason: 'K2-R-11: η τιμή προς τα πάνω, το όριο (106,6) προς τα κάτω');
      expect(cod.single.user, contains('μπακαλιάρος'));
      expect(check(s, List.filled(6, 'sardeles')).where((p) => p.tag == 'mercury'), isEmpty);
      expect(check(s, List.filled(5, 'bakaliaros')).where((p) => p.tag == 'mercury'), isEmpty, reason: '5 × 180 × 0,111 = 99,9');
    });

    test('K2-S-03: λιπαρό ψάρι πάνω από 720 g ωμό την εβδομάδα → σημείωση (NHS: ως 4 μερίδες)', () {
      final s = _store();
      final six = check(s, List.filled(6, 'solomos')).where((p) => p.tag == 'oily').toList();
      expect(six, hasLength(1));
      expect(six.single.user, contains('1200 g'));
      expect(check(s, List.filled(3, 'solomos')).where((p) => p.tag == 'oily'), isEmpty, reason: '600 g');
      expect(check(s, List.filled(6, 'bakaliaros')).where((p) => p.tag == 'oily'), isEmpty, reason: 'ο μπακαλιάρος δεν είναι λιπαρό');
      expect(aiOilyFishWeekG, 720);
      expect(aiOilyFishIds.every((id) => basicFoods().any((f) => f.id == id && f.cat == 'Ψάρια')), isTrue);
    });

    test('K2-C-05: ρεβίθια κονσέρβα μετρούν ως βρασμένα (÷ 2,5), όπως στην κάρτα «Χοληστερίνη»', () {
      final s = _store();
      expect(cookedLegumes(_food(_cannedChickpeas)), isTrue);
      expect(cookedLegumes(_food(_lentils)), isFalse);
      // 60 g κονσέρβας = 24 g ξερά: δεν είναι «μέρα οσπρίων» (πριν: ναι)· 100 g = 40 g ξερά: είναι.
      final small = check(s, ['revithosalata'], legumesWeek: 1).map((p) => p.user).join('\n');
      expect(small, contains('Όσπρια 0 μέρες (στόχος 1).'));
      final big = check(s, ['revithosalata-megali'], legumesWeek: 1).map((p) => p.user).join('\n');
      expect(big, isNot(contains('Όσπρια 0 μέρες')));
      expect(CholDay([_entry(_cannedChickpeas, 60, Meal.lunch)]).legumes, isFalse);
      expect(CholDay([_entry(_cannedChickpeas, 100, Meal.lunch)]).legumes, isTrue);
    });

    test('K2-C-10: σημειώσεις υγείας για πρόγραμμα με κανόνες ή επικολλημένο (κορεσμένα, αλάτι, υδράργυρος, λιπαρό ψάρι)', () {
      final s = _store();
      // 200 g φέτα σε ένα γεύμα: πολύ πάνω από το όριο κορεσμένων της μέρας.
      final fatty = _week([
        [PlanSlot(meal: Meal.lunch, dishId: _byKey(s, 'feta-salata').id)],
      ]);
      final notes = weekHealthNotes(s, fatty, t: _targets, bodyKg: 82.0);
      expect(notes.where((n) => n.contains('κορεσμένα')), hasLength(1));
      expect(notes.where((n) => n.contains('αλάτι')), hasLength(1));
      expect(notes.join(), isNot(contains('kcal')), reason: 'θερμίδες και πρωτεΐνη τα λέει ήδη το αυτόματο πρόγραμμα');
      final lean = _week([
        [PlanSlot(meal: Meal.lunch, dishId: _byKey(s, 'kotopoulo-ryzi').id)],
      ]);
      expect(weekHealthNotes(s, lean, t: _targets, bodyKg: 82.0), isEmpty);
      expect(weekHealthNotes(s, _week(const [[], []], meals: const []), t: _targets), isEmpty);
    });

    test('K2-S-08: μέρα με 300–399 g φρούτα και λαχανικά περνά τον έλεγχο, αλλά το λέει (στόχος της μέρας 400 g)', () {
      final s = _store();
      // «salata»: 200 g ντομάτα + 150 g αγγούρι = 350 g.
      final w = _week([
        [PlanSlot(meal: Meal.dinner, dishId: _byKey(s, 'salata').id)],
      ], meals: const [Meal.dinner]);
      final ps = aiCheckWeek(s, w, const [], t: _targets, meals: const [Meal.dinner], checkDays: {0});
      final note = ps.where((p) => p.user.startsWith('Φρούτα και λαχανικά: 1 μέρα')).toList();
      expect(note, hasLength(1));
      expect((note.single.weight, note.single.ai), (0, ''));
      expect(ps.where((p) => p.user.contains('φρούτα και λαχανικά 350 g')), isEmpty, reason: 'δεν είναι πρόβλημα για το AI');
    });
  });

  // ------------------------------------------------------------------------------------------------------ μικρότερα
  test('K2-S-07: κατεψυγμένος αρακάς, ωμό φύλλο και λουκάνικο θέλουν μαγείρεμα', () {
    for (final id in ['C20084', 'C23445', 'C30780']) {
      expect(aiNeedsCooking(_food(id)), isTrue, reason: _food(id).name);
    }
    // Όπως πριν: κονσέρβα, ζαμπόν, ψωμί, ωμή ντομάτα δεν θέλουν.
    for (final id in [_cannedChickpeas, 'C28900', 'C7110', _tomato, 'C26039']) {
      expect(aiNeedsCooking(_food(id)), isFalse, reason: _food(id).name);
    }
  });

  test('K2-C-06: υλικό που στρογγυλεύει στο 0 g απορρίπτεται (πριν: το φαγητό χανόταν στο επόμενο άνοιγμα)', () {
    final errors = <String>[];
    final items = parsePastedItems([
      {'id': _chicken, 'name': 'Κοτόπουλο', 'g': 150},
      {'id': 'C11035', 'name': 'Ρίγανη', 'g': 0.004},
      {'id': _oil, 'name': 'Ελαιόλαδο', 'g': 0.005},
    ], errors);
    expect(items.map((i) => (i.id, i.amount)), [(_chicken, 150.0), (_oil, 0.01)]);
    expect(errors.single, contains('από 0,01 ως'));
    expect(DishItem.fromJson({'id': _oil, 'n': 'Ελαιόλαδο', 'g': 0.01}), isNotNull);
  });

  test('K2-C-08: «minutes»: 1e999 σε νέο φαγητό του σχεδίου δεν πετά εξαίρεση', () {
    AiNewDish d(Object? minutes) => AiNewDish(key: 'ai-x', name: 'Χ', idea: '', json: {'minutes': minutes});
    expect(d(jsonDecode('1e999')).minutes, isNull);
    expect(d(double.nan).minutes, isNull);
    expect(d(-5).minutes, isNull);
    expect(d(100000).minutes, isNull);
    expect(d('30').minutes, isNull);
    expect(d(null).minutes, isNull);
    expect(d(30).minutes, 30);
    expect(d(29.6).minutes, 30);
  });

  test('K2-C-13: αλάτι πάνω από 10 g στα 100 g → «μήπως είναι νάτριο σε mg;» (δεν μπλοκάρει)', () {
    expect(doubtfulValues({Nk.salt: 40, Nk.protein: 2})[Nk.salt], contains('Νάτριο mg'));
    expect(doubtfulValues({Nk.salt: 10.0})[Nk.salt], isNull);
    expect(doubtfulValues({Nk.salt: 2.3})[Nk.salt], isNull);
    expect(impossibleValues({Nk.salt: 40}), isEmpty, reason: 'μόνο προειδοποίηση');
    expect(impossibleValues({Nk.salt: 140})[Nk.salt], isNotNull);
  });

  test('K2-S-10: αριθμοί διατροφής στο ελεύθερο κείμενο του AI («why», «tips») πιάνονται· τα υπόλοιπα όχι', () {
    bool bad({String? why, List<String> tips = const []}) => aiTextHasNutritionNumbers(Recipe(why: why, tips: tips));
    expect(bad(why: 'Μόνο 420 kcal και 4 g κορεσμένα.'), isTrue);
    expect(bad(why: 'Έχει 35 γραμμάρια πρωτεΐνης στη μερίδα.'), isTrue);
    expect(bad(tips: ['Με 30 g πρωτεΐνη ανά μερίδα.']), isTrue);
    expect(bad(tips: ['Περίπου 500 θερμίδες.']), isTrue);
    expect(bad(why: 'Πολλή πρωτεΐνη και ίνες, λίγα κορεσμένα.'), isFalse);
    expect(bad(tips: ['Ψήσε 20 λεπτά στους 200 °C.', 'Κράτα 100 g ρύζι για αύριο.']), isFalse);
    expect(aiTextHasNutritionNumbers(null), isFalse);
  });

  test('K2-S-06: οι οδηγίες προς άλλον βοηθό λένε «ως 2 μέρες», όπως το AI της εφαρμογής', () {
    expect(aiKeepsText(false), contains('2 μέρες'));
    expect(aiKeepsText(true), contains('την επόμενη μέρα'));
    expect((aiPotMaxGap, aiPotRiceGap), (2, 1));
  });

  // ---------------------------------------------------------------------------- ανεξάρτητος έλεγχος των διορθώσεων (K2-R)
  group('ανεξάρτητος έλεγχος των διορθώσεων (K2-R)', () {
    test('K2-R-01: δύο φαγητά στο ίδιο γεύμα δεν φουσκώνουν το όριο της μέρας (πριν: 20,3 g κορεσμένα αντί για 14,3)', () {
      final s = _store();
      final w = _week([
        [
          PlanSlot(meal: Meal.lunch, dishId: _byKey(s, 'feta-salata').id),
          PlanSlot(meal: Meal.lunch, dishId: _byKey(s, 'kotopoulo-ryzi').id),
          PlanSlot(meal: Meal.snack, dishId: _byKey(s, 'giaourti').id),
          PlanSlot(meal: Meal.dinner, dishId: _byKey(s, 'solomos').id),
        ],
      ]);
      final notes = weekHealthNotes(s, w, t: _targets, bodyKg: 82.0);
      final sat = notes.where((n) => n.contains('κορεσμένα') && n.contains('όριο')).toList();
      expect(sat, hasLength(1));
      expect(sat.single, contains('(όριο 14,3)'));
      expect(notes.join('\n'), isNot(contains('20,3')));
      expect(notes.join('\n'), isNot(contains('όριο 7,1')), reason: 'και το αλάτι με το όριο της μέρας (5 g)');
    });

    test('K2-R-02: δικό σου προϊόν «ΞΙΦΙΑΣ» χωρίς τόνο στο γράμμα ή «Swordfish» παίρνει την τιμή του ξιφία', () {
      Food own(String name) =>
          Food(id: 'own-$name', name: name, cat: 'Ψάρια', source: 'Ετικέτα', n: Nutrients({Nk.kcal: const NValue(120)}));
      expect(mercuryPpm(own('ΞΙΦΙΑΣ ΦΕΤΕΣ')), 0.995);
      expect(mercuryPpm(own('Swordfish steak')), 0.995);
      expect(mercuryPpm(own('Ξιφίας κατεψυγμένος')), 0.995);
      expect(mercuryPpm(own('Τόνος σε νερό Χ')), 0.35, reason: 'άγνωστο είδος τόνου: η συντηρητική τιμή');
      expect(mercuryPpm(own('Λαβράκι φιλέτο')), aiMercuryDefaultPpm);
    });

    test('K2-R-04: το φίλτρο αριθμών διατροφής πιάνει και «θρεπτικό πρώτα», και όχι ποσότητες υλικών', () {
      const caught = [
        'Μόνο 420 kcal και 4 g κορεσμένα.', 'Έχει 35 γραμμάρια πρωτεΐνης στη μερίδα.', 'Περίπου 500 θερμίδες.',
        'Πρωτεΐνη 35 g, κορεσμένα 4 g.', 'Πολλή πρωτεΐνη (38 g) και λίγα κορεσμένα (3 g).', 'Κορεσμένα μόνο 3,5 g στη μερίδα.',
        'Δίνει ίνες 12 g.', 'Με 40g πρωτεΐνης.', '35 γρ. πρωτεΐνη.', 'Αλάτι κάτω από 1 g.', 'Θερμίδες: 450.',
        'Έχει το 30% της πρωτεΐνης της μέρας.', 'Χαμηλό σε θερμίδες (περίπου 450).', '12 g of protein', 'Protein 30 g, 450 calories',
        '12 g λιπαρά στη μερίδα.', 'Λιπαρά 12 g.', 'Υδατάνθρακες 60 g.', 'Πρωτεΐνη: 35 g.', 'Πρωτεΐνη περίπου 35 g.',
        'Υδατάνθρακες ως 60 g.', 'πρωτεΐνης = 30%', 'Θερμίδες περίπου 450.', 'Ίνες 12 g.', 'Φυτικές ίνες: 9 g.',
      ];
      const passes = [
        'Ψήσε 20 λεπτά στους 200 °C.', 'Κράτα 100 g ρύζι για αύριο.', 'Πολλή πρωτεΐνη και ίνες, λίγα κορεσμένα.',
        'Αν το θες πιο νόστιμο, πρόσθεσε 1 g αλάτι στο τέλος.', 'Μη βάλεις πάνω από 1 g αλάτι.',
        'Στο τέλος 5 g ζάχαρη για την οξύτητα της ντομάτας.', 'Αντί για γιαούρτι, 150 g φυτικό επιδόρπιο σόγιας.',
        'Βάλε 10 g λιπαρό τυρί λιγότερο.', 'Γίνεται και με 200 g λίπος… όχι: με 20 g ελαιόλαδο.', 'Κόψε 300 g ντομάτα σε κύβους.',
        'Σέρβιρε με 30 g φέτα.', 'Καλή πηγή πρωτεΐνης. Βράσε 10 λεπτά.', 'Λίγα κορεσμένα· με 150 g γιαούρτι γίνεται πιο χορταστικό.',
        'Πλούσιο σε ίνες: πρόσθεσε 2 κουταλιές βρώμη.', 'Τα λιπαρά ψάρια θέλουν 12 λεπτά στους 180 °C.',
        'Η πρωτεΐνη έρχεται από 2 αυγά.', 'Πλούσιο σε πρωτεΐνη με 150 g κοτόπουλο.', 'Λίγες θερμίδες· ψήσε 20 λεπτά.',
        'Λίγες θερμίδες, 20 λεπτά δουλειά.', 'Κλημεντίνες 150 g για επιδόρπιο.', 'Κράτα 2 μερίδες στο ψυγείο ως 2 μέρες.',
      ];
      for (final t in caught) {
        expect(aiSentenceHasNutritionNumber(t), isTrue, reason: t);
      }
      for (final t in passes) {
        expect(aiSentenceHasNutritionNumber(t), isFalse, reason: t);
      }
    });

    test('K2-R-09: «από αυτά 1 ως 3 λιπαρά» με στόχο 3 ψάρια (πριν: «2 ως 4»)· χωρίς λιπαρό ψάρι το λέει, χωρίς διόρθωση', () {
      final s = _store();
      List<AiProblem> check(List<String> dinners, int fishWeek) {
        final w = _week([
          for (final key in dinners) [PlanSlot(meal: Meal.dinner, dishId: _byKey(s, key).id)],
        ], meals: const [Meal.dinner]);
        return aiCheckWeek(s, w, const [],
            t: _targets, meals: const [Meal.dinner], checkDays: {for (var i = 0; i < dinners.length; i++) i}, fishWeek: fishWeek,
            bodyKg: 82.0);
      }

      final none = check(['bakaliaros', 'bakaliaros', 'kotopoulo-ryzi'], 2).where((p) => p.user.contains('Κανένα λιπαρό ψάρι')).toList();
      expect(none, hasLength(1));
      expect((none.single.weight, none.single.ai), (0, ''), reason: 'μόνο ενημέρωση');
      expect(check(['bakaliaros', 'solomos'], 2).where((p) => p.user.contains('Κανένα λιπαρό ψάρι')), isEmpty);
      expect(check(['bakaliaros', 'bakaliaros'], 0).where((p) => p.user.contains('Κανένα λιπαρό ψάρι')), isEmpty,
          reason: 'χωρίς στόχο ψαριού δεν λέει τίποτα');
    });

    test('K2-R-10: πρόγραμμα 14 ημερών: τα εβδομαδιαία όρια μετριούνται ανά εβδομάδα (πριν: 800 g λιπαρό «την εβδομάδα»)', () {
      final s = _store();
      // 2 × 200 g σολομό την εβδομάδα, 14 μέρες: 800 g συνολικά = 400 g την εβδομάδα (όριο 720).
      final w = _week([
        for (var i = 0; i < 14; i++)
          [PlanSlot(meal: Meal.dinner, dishId: _byKey(s, i % 7 < 2 ? 'solomos' : 'kotopoulo-ryzi').id)],
      ], meals: const [Meal.dinner]);
      expect(weekHealthNotes(s, w, t: _targets, bodyKg: 82.0).where((n) => n.contains('Λιπαρό ψάρι')), isEmpty);
      // 6 × 180 g μπακαλιάρο ΚΑΘΕ εβδομάδα για 14 μέρες: 119,9 µg την εβδομάδα, πάνω από το όριο και τις δύο.
      final cod = _week([
        for (var i = 0; i < 14; i++)
          [PlanSlot(meal: Meal.dinner, dishId: _byKey(s, i % 7 < 6 ? 'bakaliaros' : 'kotopoulo-ryzi').id)],
      ], meals: const [Meal.dinner]);
      final hg = weekHealthNotes(s, cod, t: _targets, bodyKg: 82.0).where((n) => n.contains('Υδράργυρος')).toList();
      expect(hg, hasLength(1));
      expect(hg.single, contains('120 µg την εβδομάδα'));
    });

    test('K2-R-11: ένα όνομα ανά είδος, και «(εκτίμηση)» για είδος χωρίς τιμή στον πίνακα της FDA', () {
      final s = _store();
      // Τσιπούρα (προεπιλογή 0,10): 6 × 180 g = 108 µg, πάνω από το όριο 106,6.
      final lib = [
        _dish('tsipoura', 'plate', [('C26088', 180), (_rice, 80)]),
      ];
      var n = 0;
      final r = planLibraryImport(
        parseLibrary(jsonEncode({'kind': libraryKind, 'dishes': lib})),
        existing: const [],
        food: (id) => s.itemFood(DishItem(id, id, 1)),
        likes: const FoodLikes(),
        now: 1,
        newId: () => 'T${n++}',
      );
      expect(r.problems, isEmpty);
      final s2 = _store(dishes: [...s.dishes, ...r.added]);
      final w = _week([
        for (var i = 0; i < 6; i++) [PlanSlot(meal: Meal.dinner, dishId: _byKey(s2, 'tsipoura').id)],
      ], meals: const [Meal.dinner]);
      final hg = weekHealthNotes(s2, w, t: _targets, bodyKg: 82.0).where((x) => x.contains('Υδράργυρος')).toList();
      expect(hg, hasLength(1));
      expect(hg.single, contains('(εκτίμηση)'));
      expect(hg.single, contains('108 µg'));
      expect(hg.single, contains('όριο EFSA 106'));
    });

    test('K2-R-07: το «light» δεν είναι άλλο όνομα του γάλακτος 0% (στα ράφια «light» είναι συνήθως το 1,5%)', () {
      expect(_food('C19051').aliases, isNot(contains('light')));
      expect(_food('C19051').aliases, contains('άπαχο'));
    });
  });
}
