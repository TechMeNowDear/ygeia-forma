/// Οι μερίδες του προγράμματος εβδομάδας: από τις θερμίδες της θέσης στα γραμμάρια που ζυγίζεις, πάντα από τη βάση.
///
/// - Πιάτο: όλα τα υλικά στην ίδια αναλογία (θερμίδες της θέσης ÷ θερμίδες όλου του πιάτου).
/// - Ίσες μερίδες: πόσες μερίδες, ανά μισή (π.χ. 1,5 μπιφτέκι).
/// - Κατσαρόλα: «Η μερίδα σου: … g» από το έτοιμο φαγητό, μόλις ζυγιστεί όλο (θερμίδες της θέσης × έτοιμο ÷ θερμίδες όλων
///   των υλικών του μαγειρέματος). Χωρίς ζυγισμένο μαγείρεμα των τελευταίων [potQuickDays] ημερών δεν βγαίνει νούμερο:
///   πρώτα ζυγίζεις όλο το φαγητό.
library;

import 'dart:math' as math;

import '../format.dart' show daysBetween, thousands;
import '../history.dart' show dateKey;
import 'dishes.dart';
import 'food_model.dart';
import 'food_store.dart';
import 'library.dart';
import 'recipe.dart' show recipeOf;
import 'week.dart';

/// Τα σύνολα μιας λίστας υλικών (τιμές της βάσης όπως είναι τώρα), ή null αν λείπει υλικό.
Totals? itemsTotals(FoodStore food, List<DishItem> items) {
  final p = food.previewDish(items);
  return p == null ? null : Totals(p);
}

/// Γραμμάρια για ζύγισμα: ακέραια από 10 g και πάνω, ανά μισό κάτω από 10 g (αλάτι, μπαχαρικά), τουλάχιστον 0,5 g.
double weighRound(double g) => g >= 10 ? g.roundToDouble() : math.max(0.5, (g * 2).round() / 2);

/// Μερίδα από την κατσαρόλα: ανά 5 g (η ζυγαριά κουζίνας δεν δείχνει πιο ακριβή μερίδα που να έχει νόημα).
double portionRound(double g) => math.max(5.0, (g / 5).round() * 5.0);

/// Τα ωμά υλικά της μερίδας της συνταγής (χωρίς στόχο θερμίδων): όλο το πιάτο, 1 μερίδα, ή 1 από τις μερίδες της
/// κατσαρόλας (όσες γράφει η συνταγή). null: κατσαρόλα χωρίς μερίδες στη συνταγή.
List<DishItem>? naturalRaw(Dish d) {
  List<DishItem> scaled(double f) => [
        for (final i in d.items)
          if (roundAmount(i.amount * f) > 0) i.withAmount(roundAmount(i.amount * f)),
      ];
  switch (d.kind) {
    case DishKind.plate:
      return d.items;
    case DishKind.portions:
      return scaled(1 / d.servings);
    case DishKind.pot:
      final sv = recipeOf(d)?.servings;
      return sv == null ? null : scaled(1 / sv);
  }
}

/// Πόσες μερίδες φαγητού «ίσων μερίδων» αντιστοιχούν σε [kcal] θερμίδες, όταν η μία μερίδα έχει [oneKcal]: η
/// πλησιέστερη μισή μερίδα, από μισή ως [maxEatenServings]. Ο ίδιος κανόνας για το πρόγραμμα ([plannedRaw]) και για το
/// «Το έφαγα» ([slotLog]).
double servingsFor(double kcal, double oneKcal) => math.min(maxEatenServings, math.max(0.5, (kcal / oneKcal * 2).round() / 2));

/// Τα ωμά υλικά που αντιστοιχούν στη θέση (για τα σύνολα του προγράμματος, πριν φας). null αν δεν βγαίνει (λείπει υλικό,
/// κατσαρόλα χωρίς μερίδες και χωρίς θερμίδες).
///
/// Έλεγχος 20/11 (K2-C-02): στα φαγητά «ίσων μερίδων» το πρόγραμμα δείχνει πια ό,τι θα γράψει το «Το έφαγα»: την
/// πλησιέστερη μισή μερίδα ([servingsFor]). Πριν κλιμάκωνε τα υλικά ακριβώς στις θερμίδες της θέσης, και όταν αυτές δεν
/// ήταν πολλαπλάσιο μισής μερίδας («Άλλαξέ το», «Διάλεξε φαγητό», επικόλληση) η γραμμή έγραφε «699 kcal» ενώ γράφονταν
/// 560 (παστίτσιο, 1 μερίδα): διαφορά ως ±220 kcal ανάμεσα στο πρόγραμμα της μέρας και στο ημερολόγιο.
List<DishItem>? plannedRaw(FoodStore food, Dish d, double? kcal) {
  if (kcal == null) return naturalRaw(d);
  if (d.kind == DishKind.portions) {
    final one = itemsTotals(food, dishAmounts(d, servings: 1));
    if (one == null || one.kcal <= 0) return null;
    return dishAmounts(d, servings: servingsFor(kcal, one.kcal));
  }
  final all = d.items;
  final t = itemsTotals(food, all);
  if (t == null || t.kcal <= 0) return null;
  final f = kcal / t.kcal;
  return [
    for (final i in all)
      if (roundAmount(i.amount * f) > 0) i.withAmount(roundAmount(i.amount * f)),
  ];
}

/// Τα σύνολα της θέσης όπως είναι στο πρόγραμμα (ή null).
Totals? plannedTotals(FoodStore food, Dish? d, PlanSlot s) {
  if (d == null) return null;
  final raw = plannedRaw(food, d, s.kcal);
  return raw == null ? null : itemsTotals(food, raw);
}

/// Η μερίδα σου από το μαγείρεμα [b] (g του έτοιμου φαγητού), ή null αν δεν βγαίνει.
///
/// Έλεγχος 20/11 (K2-C-11): θέση χωρίς θερμίδες (επικολλημένο πρόγραμμα) σημαίνει «μία μερίδα της συνταγής»: τόσα γραμμάρια
/// από ΑΥΤΟ το μαγείρεμα, όσα έχουν τις θερμίδες της μερίδας της συνταγής ([naturalRaw]), που δείχνει και η γραμμή του
/// προγράμματος. Πριν έπαιρνε «έτοιμο ÷ μερίδες», και με διπλή δόση στην κατσαρόλα η γραμμή έγραφε 399 kcal ενώ γράφονταν 796.
double? potPortion(FoodStore food, Dish d, PotBatch b, double? kcal) {
  if (kcal == null) {
    final sv = recipeOf(d)?.servings;
    if (sv == null) return null;
    final natural = naturalRaw(d);
    final one = natural == null ? null : itemsTotals(food, natural);
    if (one == null || one.kcal <= 0) return math.min(b.cooked, portionRound(b.cooked / sv));
    kcal = one.kcal;
  }
  final t = itemsTotals(food, b.items);
  if (t == null || t.kcal <= 0) return null;
  return math.min(b.cooked, portionRound(kcal * b.cooked / t.kcal));
}

/// Τα υλικά έχουν ρύζι (τρόφιμο της βάσης που το όνομά του αρχίζει με «Ρύζι»): το περίσσευμα μόνο ως την επόμενη μέρα.
bool itemsHaveRice(FoodStore food, Iterable<DishItem> items) => items.any((i) => isRiceName(food.itemFood(i)?.name));

/// Το όνομα ενός τροφίμου λέει «ρύζι» ως λέξη (αρχή ή μέση, πεζά ή κεφαλαία): «Ρύζι basmati», «Basmati ρύζι», «ΡΥΖΙ».
/// Όχι «ρυζιού» (γάλα ρυζιού), «ρυζόγαλο», «ρυζογκοφρέτες». Ανεξάρτητος έλεγχος 21/11 (Α2-4): πριν μόνο όνομα που ΑΡΧΙΖΕ
/// με «Ρύζι» (όλα τα ρύζια της βάσης)· ένα δικό σου προϊόν «Basmati ρύζι» έπαιρνε 3 μέρες αντί για 2.
bool isRiceName(String? name) => name != null && _riceWord.hasMatch(name.toLowerCase());

final _riceWord = RegExp(r'(^|[^a-zα-ωάέήίόύώϊϋΐΰ])ρ[υύ]ζι($|[^a-zα-ωάέήίόύώϊϋΐΰ])');

/// Πόσες μέρες μετρά ένα μαγείρεμα με αυτά τα [items]: [potQuickDays], ή [potRiceQuickDays] αν έχει ρύζι (Α2, 21/11).
int potKeepDays(FoodStore food, Iterable<DishItem> items) => itemsHaveRice(food, items) ? potRiceQuickDays : potQuickDays;

/// Το μαγείρεμα [b] είναι πιο παλιό από όσο κρατούν τα περισσεύματα (τα υλικά του ίδιου του μαγειρέματος κρίνουν το ρύζι).
bool potBatchOld(FoodStore food, PotBatch b, DateTime now) =>
    daysBetween(DateTime.fromMillisecondsSinceEpoch(b.at), now) >= potKeepDays(food, b.items);

/// Το μαγείρεμα της κατσαρόλας που μετρά για το πρόγραμμα: ζυγισμένο, και όχι πιο παλιό από όσο κρατούν τα περισσεύματα
/// ([potKeepDays]: ως 2 μέρες μετά, με ρύζι ως την επόμενη).
PotBatch? freshBatch(FoodStore food, Dish d, DateTime now) {
  final b = d.batch;
  if (d.kind != DishKind.pot || b == null) return null;
  return potBatchOld(food, b, now) ? null : b;
}

/// Τι γράφεται με «Το έφαγα».
class SlotLog {
  const SlotLog({required this.amounts, required this.qty, this.plate});
  final List<DishItem> amounts;
  final double qty;
  final List<double>? plate;
}

/// Η καταγραφή της θέσης με ένα πάτημα, ή null όταν χρειάζεται η οθόνη του φαγητού (λείπει υλικό· κατσαρόλα που δεν
/// έχει ζυγιστεί πρόσφατα· καταγραφή που μοιάζει με λάθος).
SlotLog? slotLog(FoodStore food, Dish d, PlanSlot s, DateTime now) {
  if (food.missingItems(d.items).isNotEmpty) return null;
  List<DishItem> amounts;
  double qty;
  List<double>? plate;
  switch (d.kind) {
    case DishKind.plate:
      var f = 1.0;
      if (s.kcal != null) {
        final t = itemsTotals(food, d.items);
        if (t == null || t.kcal <= 0) return null;
        f = s.kcal! / t.kcal;
      }
      plate = [for (final i in d.items) weighRound(i.amount * f)];
      amounts = dishAmounts(d, plate: plate);
      qty = itemsSum(amounts);
    case DishKind.portions:
      var sv = 1.0;
      if (s.kcal != null) {
        final t = itemsTotals(food, dishAmounts(d, servings: 1));
        if (t == null || t.kcal <= 0) return null;
        sv = servingsFor(s.kcal!, t.kcal);
      }
      qty = sv;
      amounts = dishAmounts(d, servings: sv);
    case DishKind.pot:
      final b = freshBatch(food, d, now);
      if (b == null) return null;
      final g = potPortion(food, d, b, s.kcal);
      if (g == null) return null;
      qty = g;
      amounts = dishAmounts(d, portion: g, batch: b);
  }
  if (amounts.isEmpty) return null;
  final t = itemsTotals(food, amounts);
  if (t == null || dishLooksLikeTypo(t.kcal)) return null;
  return SlotLog(amounts: amounts, qty: qty, plate: plate);
}

/// Η κατάσταση της θέσης όπως φαίνεται: «Το έφαγα» μετρά μόνο όσο οι καταχωρίσεις του είναι ακόμα στο ημερολόγιο (αν τις
/// έσβησες, η θέση ξαναγίνεται ανοιχτή).
SlotState slotStateNow(FoodStore food, WeekPlan w, int day, PlanSlot s) {
  if (s.state != SlotState.ate) return s.state;
  final g = s.grp;
  if (g == null) return SlotState.open;
  return food.entriesFor(w.dayAt(day)).any((e) => e.dish?.grp == g) ? SlotState.ate : SlotState.open;
}

/// Σύνολα της μέρας του προγράμματος: όσα έχει το πρόγραμμα (χωρίς τα «Δεν το έφαγα»). [unknown]: θέσεις χωρίς νούμερο.
({Totals totals, int unknown}) plannedDay(FoodStore food, WeekPlan w, int day, {List<Dish> extra = const []}) {
  final items = <DishItem>[];
  var unknown = 0;
  for (final s in w.days[day]) {
    if (s.state == SlotState.skip) continue;
    final d = food.dishById(s.dishId) ?? extra.where((x) => x.id == s.dishId).firstOrNull;
    final raw = d == null ? null : plannedRaw(food, d, s.kcal);
    final p = raw == null ? null : food.previewDish(raw);
    if (p == null) {
      unknown++;
    } else {
      items.addAll(raw!);
    }
  }
  return (totals: Totals(food.previewDish(items) ?? const []), unknown: unknown);
}

// ---------------------------------------------------------------------------
// Οδηγίες για τον βοηθό: πρόγραμμα εβδομάδας από τη βιβλιοθήκη
// ---------------------------------------------------------------------------

/// Η πρώτη μέρα που προτείνουμε για νέο πρόγραμμα: σήμερα αν είναι Δευτέρα, αλλιώς η επόμενη Δευτέρα.
DateTime nextMonday(DateTime now) {
  final d = DateTime(now.year, now.month, now.day);
  return d.weekday == DateTime.monday ? d : DateTime(d.year, d.month, d.day + (8 - d.weekday));
}

/// Το κείμενο που αντιγράφεται για τον βοηθό AI: φτιάξε πρόγραμμα από τη βιβλιοθήκη μου. Για κάθε φαγητό δίνουμε τα
/// θρεπτικά της μερίδας της συνταγής, από τη βάση, ώστε ο βοηθός να διαλέξει θερμίδες ανά θέση χωρίς να μαντεύει.
String weekPrompt({
  required FoodStore food,
  required DateTime from,
  ({int kcal, int protein, int satMax, int fiber, double salt})? targets,
  int? legumesWeek,
  int? fishWeek,
}) {
  String n(double v) => v.round().toString();
  final b = StringBuffer()
    ..writeln(weekPromptTitle)
    ..writeln()
    ..writeln('Φτιάξε το πρόγραμμα φαγητού μου από τη ${dateKey(from)} (7 μέρες), ΜΟΝΟ με φαγητά της «ΒΙΒΛΙΟΘΗΚΗΣ» πιο κάτω. '
        'Πόσα γεύματα τη μέρα και τι άλλο ισχύει, θα σου τα πω στη συζήτησή μας.')
    ..writeln()
    ..writeln('Κανόνες:')
    ..writeln('1. Κάθε γεύμα: "meal" ("lunch" μεσημέρι, "dinner" βράδυ, "snack" σνακ, "breakfast" πρωινό), "key" ενός φαγητού '
        'της βιβλιοθήκης ακριβώς όπως είναι, και προαιρετικά "kcal": θερμίδες για τη μερίδα μου. Χωρίς "kcal", μετρά η μερίδα '
        'της συνταγής. Η εφαρμογή βγάζει τα γραμμάρια από τη βάση· ΜΗ γράψεις γραμμάρια ή άλλα θρεπτικά.')
    ..writeln('2. Οι θερμίδες κάθε μέρας κοντά στον στόχο, και κατά μέσο όρο της εβδομάδας πάνω του· πρωτεΐνη μοιρασμένη στα '
        'γεύματα· κορεσμένα κάτω από το όριο· αρκετές ίνες.')
    // Έλεγχος 20/11 (K2-S-06): ίδιο πρότυπο με το AI της εφαρμογής (FSA: περισσεύματα ως 48 ώρες, ρύζι ως την επόμενη μέρα).
    ..writeln('3. Φαγητό κατσαρόλας ("pot"): μαγειρεύεται μία φορά και τρώγεται ως 2 μέρες μετά (με ρύζι μόνο την επόμενη '
        'μέρα), με το ίδιο key.')
    ..writeln('4. Απάντησε με ΕΝΑ μπλοκ JSON σε αυτή ακριβώς τη μορφή. Στη θέση του «…» βάλε όλα τα γεύματα και όλες τις μέρες:')
    ..writeln('```json')
    ..writeln('{')
    ..writeln('  "kind": "$weekKind",')
    ..writeln('  "from": "${dateKey(from)}",')
    ..writeln('  "days": [')
    ..writeln('    [{"meal": "lunch", "key": "fakes-kokkinistes", "kcal": 650}, {"meal": "snack", "key": "…"}, …],')
    ..writeln('    …')
    ..writeln('  ]')
    ..writeln('}')
    ..writeln('```')
    ..writeln();
  if (targets != null) {
    b.writeln('ΟΙ ΣΤΟΧΟΙ ΜΟΥ ΑΝΑ ΜΕΡΑ: ${thousands(targets.kcal)} kcal · πρωτεΐνη ${targets.protein} g · κορεσμένα έως '
        '${targets.satMax} g · ίνες τουλάχιστον ${targets.fiber} g · αλάτι κάτω από ${targets.salt.toStringAsFixed(0)} g.');
  }
  if (legumesWeek != null || fishWeek != null) {
    b.writeln('ΤΗΝ ΕΒΔΟΜΑΔΑ: ${[
      if (legumesWeek != null) 'όσπρια $legumesWeek φορές',
      if (fishWeek != null) 'ψάρι $fishWeek φορές',
    ].join(' · ')}.');
  }
  b
    ..writeln()
    ..writeln('ΒΙΒΛΙΟΘΗΚΗ (key · όνομα · είδος · γεύματα · γραφείο · ετικέτες · η μερίδα της συνταγής από τη βάση):');
  for (final d in libraryDishes(food.dishes)) {
    final p = planInfoOf(d)!;
    final raw = naturalRaw(d);
    final t = raw == null ? null : itemsTotals(food, raw);
    final kind = switch (d.kind) {
      DishKind.plate => 'πιάτο',
      DishKind.portions => '${d.servings} μερίδες',
      DishKind.pot => 'κατσαρόλα${recipeOf(d)?.servings == null ? '' : ' ~${recipeOf(d)!.servings} μερίδες'}',
    };
    b.writeln([
      p.key,
      d.name,
      '$kind, ${cookWayLabel(p.cook).toLowerCase()}',
      p.meals.isEmpty ? 'όλα τα γεύματα' : p.meals.map((m) => m.name).join('/'),
      if (p.office) 'γραφείο',
      if (p.tags.isNotEmpty) p.tags.join(', '),
      if (dishRating(d) > 0) 'ΜΟΥ ΑΡΕΣΕ',
      if (dishRating(d) < 0)
        'ΔΕΝ ΜΟΥ ΑΡΕΣΕ: μην το βάλεις'
      else if (food.missingItems(d.items).isNotEmpty)
        'ΛΕΙΠΕΙ ΥΛΙΚΟ: μην το βάλεις'
      else if (t == null)
        'μερίδα: άγνωστη (βάλε "kcal")'
      else
        // Κ2-L4 (17/11): «≥» όταν σε κάποιο υλικό λείπει η τιμή, όπως στις οθόνες.
        'μερίδα ${n(t.kcal)} kcal, πρωτεΐνη ${n(t.protein)} g, '
            'κορεσμένα ${(t.missing[Nk.satFat] ?? 0) > 0 ? '≥ ' : ''}${t.satFat.toStringAsFixed(1)} g, '
            'ίνες ${(t.missing[Nk.fiber] ?? 0) > 0 ? '≥ ' : ''}${n(t.fiber)} g',
    ].join(' · '));
  }
  return b.toString();
}

// ---------------------------------------------------------------------------
// Λίστα ψωνιών (από το πρόγραμμα)
// ---------------------------------------------------------------------------

/// Κατηγορίες που αγοράζονται τη μέρα που μαγειρεύονται (απόφαση χρήστη 15/11: ψάρι, κρέας, κοτόπουλο φρέσκα).
const freshShopCats = {'Κρέας', 'Πουλερικά', 'Ψάρια', 'Θαλασσινά'};

/// Φρέσκο: ωμό κρέας, πουλερικό, ψάρι ή θαλασσινό («(ωμό)», «(ωμή)»…). Κονσέρβες, καπνιστά, μαρινάτα και έτοιμα
/// μένουν στα ψώνια της αρχής.
bool isFreshBuy(Food f) => freshShopCats.contains(f.cat) && f.name.contains('(ωμ');

/// Ένα τρόφιμο της λίστας: πόσο χρειάζεται (g ή ml, ωμό, όπως ζυγίζεται).
class ShopLine {
  const ShopLine(this.food, this.amount);
  final Food food;
  final double amount;
}

class ShoppingList {
  const ShoppingList({this.main = const [], this.fresh = const {}, this.ordered = 0, this.unknown = const []});

  /// Όλα τα υπόλοιπα, για τα ψώνια της αρχής (ταξινομημένα ανά κατηγορία και όνομα).
  final List<ShopLine> main;

  /// Τα φρέσκα (ψάρι, κρέας, κοτόπουλο), ανά μέρα του προγράμματος (θέση της μέρας).
  final Map<int, List<ShopLine>> fresh;

  /// Πόσα γεύματα είναι από παραγγελία (δεν αγοράζονται).
  final int ordered;

  /// Φαγητά που δεν μπήκαν στη λίστα (δεν υπάρχουν πια, λείπει υλικό, κατσαρόλα χωρίς μερίδες και θερμίδες).
  final List<String> unknown;

  bool get isEmpty => main.isEmpty && fresh.isEmpty;
}

/// Η λίστα ψωνιών για τις μέρες του προγράμματος από τη θέση [fromDay] και μετά, για τα γεύματα που δεν έχουν σημειωθεί.
/// - Πιάτο και μερίδες: τα ωμά υλικά της μερίδας του προγράμματος.
/// - Κατσαρόλα: όλη η συνταγή (για όλους), μία φορά για κάθε μαγείρεμα· το ίδιο φαγητό σε λιγότερες από [potQuickDays]
///   μέρες είναι περισσεύματα. Αν υπάρχει ήδη πρόσφατο μαγείρεμα, η πρώτη φορά είναι περισσεύματα.
/// - Παραγγελία: τίποτα.
ShoppingList shoppingList(FoodStore food, WeekPlan w, {int fromDay = 0, DateTime? now}) {
  final main = <String, double>{};
  final fresh = <int, Map<String, double>>{};
  final unknown = <String>[];
  final cookedOn = <String, DateTime>{};
  var ordered = 0;
  for (var i = fromDay; i < w.days.length; i++) {
    final day = w.dayAt(i);
    for (final s in w.days[i]) {
      if (s.state != SlotState.open) continue;
      final d = food.dishById(s.dishId);
      if (d == null) {
        unknown.add('Φαγητό που δεν υπάρχει πια (${mealLabel(s.meal)}, μέρα ${i + 1})');
        continue;
      }
      if (planInfoOf(d)?.cook == CookWay.out) {
        ordered++;
        continue;
      }
      List<DishItem>? items;
      if (d.kind == DishKind.pot) {
        final last = cookedOn[d.id] ??
            (freshBatch(food, d, now ?? day) == null ? null : DateTime.fromMillisecondsSinceEpoch(d.batch!.at));
        if (last != null && daysBetween(last, day) < potKeepDays(food, d.items)) continue;
        cookedOn[d.id] = day;
        items = d.items;
      } else {
        items = plannedRaw(food, d, s.kcal);
      }
      if (items == null || food.missingItems(d.items).isNotEmpty) {
        unknown.add(d.name);
        continue;
      }
      for (final it in items) {
        final f = food.itemFood(it);
        if (f == null) continue;
        final target = isFreshBuy(f) ? fresh.putIfAbsent(i, () => {}) : main;
        target[f.id] = (target[f.id] ?? 0) + it.amount;
      }
    }
  }
  List<ShopLine> lines(Map<String, double> m) {
    final out = [
      for (final e in m.entries)
        if (food.byId(e.key) case final f?) ShopLine(f, e.value),
    ];
    out.sort((a, b) {
      final c = a.food.cat.compareTo(b.food.cat);
      return c != 0 ? c : a.food.name.compareTo(b.food.name);
    });
    return out;
  }

  return ShoppingList(
    main: lines(main),
    fresh: {for (final e in fresh.entries) e.key: lines(e.value)},
    ordered: ordered,
    unknown: unknown,
  );
}

/// Ποσότητα για τα ψώνια: προς τα πάνω, ανά 10 g (ανά 1 g κάτω από 10 g, π.χ. μπαχαρικά).
double shopRound(double g) => g < 10 ? g.ceilToDouble() : (g / 10).ceil() * 10.0;

/// Η λίστα ως κείμενο, για αντιγραφή (σημειώσεις, μήνυμα).
String shoppingText(ShoppingList l, WeekPlan w) {
  String line(ShopLine s) => '- ${s.food.name}: ${thousands(shopRound(s.amount).round())} ${s.food.unit}';
  final b = StringBuffer()..writeln('Ψώνια για το πρόγραμμα ${dateKey(w.start)} – ${dateKey(w.end)}');
  String? cat;
  for (final s in l.main) {
    if (s.food.cat != cat) {
      cat = s.food.cat;
      b
        ..writeln()
        ..writeln(cat.isEmpty ? 'Άλλα' : cat);
    }
    b.writeln(line(s));
  }
  final days = l.fresh.keys.toList()..sort();
  for (final i in days) {
    b
      ..writeln()
      ..writeln('Φρέσκα, τη μέρα που μαγειρεύεις (${dateKey(w.dayAt(i))})');
    for (final s in l.fresh[i]!) {
      b.writeln(line(s));
    }
  }
  return b.toString();
}
