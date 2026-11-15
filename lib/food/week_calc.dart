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

/// Τα ωμά υλικά που αντιστοιχούν στη θέση (για τα σύνολα του προγράμματος, πριν φας). null αν δεν βγαίνει (λείπει υλικό,
/// κατσαρόλα χωρίς μερίδες και χωρίς θερμίδες).
List<DishItem>? plannedRaw(FoodStore food, Dish d, double? kcal) {
  if (kcal == null) return naturalRaw(d);
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
double? potPortion(FoodStore food, Dish d, PotBatch b, double? kcal) {
  if (kcal == null) {
    final sv = recipeOf(d)?.servings;
    return sv == null ? null : math.min(b.cooked, portionRound(b.cooked / sv));
  }
  final t = itemsTotals(food, b.items);
  if (t == null || t.kcal <= 0) return null;
  return math.min(b.cooked, portionRound(kcal * b.cooked / t.kcal));
}

/// Το μαγείρεμα της κατσαρόλας που μετρά για το πρόγραμμα: ζυγισμένο, των τελευταίων [potQuickDays] ημερών.
PotBatch? freshBatch(Dish d, DateTime now) {
  final b = d.batch;
  if (d.kind != DishKind.pot || b == null) return null;
  return daysBetween(DateTime.fromMillisecondsSinceEpoch(b.at), now) < potQuickDays ? b : null;
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
        sv = math.min(maxEatenServings, math.max(0.5, (s.kcal! / t.kcal * 2).round() / 2));
      }
      qty = sv;
      amounts = dishAmounts(d, servings: sv);
    case DishKind.pot:
      final b = freshBatch(d, now);
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
({Totals totals, int unknown}) plannedDay(FoodStore food, WeekPlan w, int day) {
  final items = <DishItem>[];
  var unknown = 0;
  for (final s in w.days[day]) {
    if (s.state == SlotState.skip) continue;
    final d = food.dishById(s.dishId);
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
    ..writeln('3. Φαγητό κατσαρόλας ("pot"): μαγειρεύεται μία φορά και τρώγεται ως 3 μέρες (ίδιο key σε συνεχόμενα γεύματα).')
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
      if (food.missingItems(d.items).isNotEmpty)
        'ΛΕΙΠΕΙ ΥΛΙΚΟ: μην το βάλεις'
      else if (t == null)
        'μερίδα: άγνωστη (βάλε "kcal")'
      else
        'μερίδα ${n(t.kcal)} kcal, πρωτεΐνη ${n(t.protein)} g, κορεσμένα ${t.satFat.toStringAsFixed(1)} g, ίνες ${n(t.fiber)} g',
    ].join(' · '));
  }
  return b.toString();
}
