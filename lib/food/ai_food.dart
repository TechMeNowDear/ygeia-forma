/// AI για το φαγητό (19/11, έγγραφο προδιαγραφών › «AI για το φαγητό»).
///
/// Κανόνες που δεν αλλάζουν:
/// - Το AI ΔΙΑΛΕΓΕΙ (φαγητά, υλικά, ωμά γραμμάρια, βήματα). Οι θερμίδες και τα θρεπτικά βγαίνουν ΠΑΝΤΑ από τη βάση· ό,τι
///   αριθμό γράψει το AI αγνοείται. Οι μερίδες του προγράμματος βγαίνουν από τους ίδιους κανόνες με το «Φτιάξε πρόγραμμα».
/// - Υλικά: ΜΟΝΟ «Μου αρέσει» + «Βασικά κουζίνας», ποτέ «Δε μου αρέσει» ([aiAllowedIds]). Ελέγχεται εδώ, όχι με
///   εμπιστοσύνη στο AI. Φαγητό της βιβλιοθήκης με έστω ένα άλλο υλικό δεν προτείνεται.
/// - Ό,τι δεν περνά τους ελέγχους πάει πίσω στο AI με τα προβλήματα (ως 2 φορές)· αν ξανά δεν περνά, το λέμε. Ποτέ κάτι
///   «περίπου σωστό» στη θέση του.
/// - Τίποτα δεν γράφεται πριν πεις «Ναι»: οι συναρτήσεις εδώ ΜΟΝΟ ετοιμάζουν (πρόγραμμα, νέα φαγητά, αλλαγή γεύματος).
/// - Σε κάθε κλήση: λίγη δουλειά (σχέδιο ή ΜΙΑ συνταγή), ώστε να χωράει στα 150″ του Supabase.
library;

import 'dart:convert';
import 'dart:math' as math;

import '../ai/ai_bridge.dart';
import '../format.dart' show thousands;
import '../history.dart' show dateKey;
import 'dishes.dart';
import 'food_model.dart';
import 'food_store.dart';
import 'kitchen.dart';
import 'library.dart';
import 'recipe.dart';
import 'week.dart';
import 'week_auto.dart';
import 'week_calc.dart';

const aiWeekKind = 'ygeia-ai-week';
const aiSwapKind = 'ygeia-ai-swap';

/// Το πολύ τόσα νέα φαγητά σε ένα πρόγραμμα (το καθένα είναι μία κλήση).
const aiMaxNewDishes = 8;

/// Ως τόσες φορές ξαναρωτάμε το AI με τα προβλήματα μίας απάντησης.
const aiMaxRetries = 2;

/// Ως τόσες συνταγές ταυτόχρονα.
const aiParallel = 3;

/// «Ανάλογο» γεύμα (απόφαση χρήστη 19/11): θερμίδες ±10%, πρωτεΐνη τουλάχιστον 90%, κορεσμένα το πολύ +1 g.
const aiSwapKcalTol = 0.10;
const aiSwapProteinMin = 0.90;
const aiSwapSatExtra = 1.0;

/// «Δεν έχω χρόνο»: ως τόσα λεπτά (ή χωρίς μαγείρεμα).
const aiQuickMinutes = 15;

/// Έλεγχος κάθε μέρας του προγράμματος: θερμίδες ±10%, πρωτεΐνη τουλάχιστον 90%, κορεσμένα ως το όριο.
const aiDayKcalTol = 0.10;
const aiDayProteinMin = 0.90;

/// Βασικά κουζίνας που προτείνονται (id της βάσης). Μπαίνουν ΜΟΝΟ αν τα εγκρίνεις.
const stapleSuggestions = [
  'C17270', // Ελαιόλαδο
  'C11017', // Αλάτι
  'C11015', // Πιπέρι
  'C11035', // Ρίγανη
  'C11049', // Πάπρικα
  'C11025', // Κανέλα
  'C20034', // Κρεμμύδι ξερό
  'C11000', // Σκόρδο
  'C13009', // Λεμόνι
  'C11014', // Μαϊντανός
  'C11093', // Άνηθος
  'C11027', // Δυόσμος
  'C11033', // Βασιλικός
  'C20068', // Πελτές ντομάτας
];

/// Τα επιτρεπόμενα υλικά: «Μου αρέσει» + «Βασικά κουζίνας», χωρίς τα «Δε μου αρέσει».
Set<String> aiAllowedIds(FoodLikes l) => {...l.like, ...l.staple}..removeAll(l.dislike);

/// Το id ενός υλικού όπως είναι σήμερα στη βάση (αντικατεστημένα τρόφιμα: το νέο id).
String? _nowId(FoodStore food, DishItem i) => food.itemFood(i)?.id;

/// Όλα τα υλικά του φαγητού επιτρέπονται και υπάρχουν.
bool aiDishAllowed(FoodStore food, Dish d, Set<String> allowed) =>
    d.items.isNotEmpty && d.items.every((i) => allowed.contains(_nowId(food, i)));

/// Τα φαγητά της βιβλιοθήκης που μπορεί να διαλέξει το AI: όλα τα υλικά επιτρέπονται, όχι «Δεν μου άρεσε», μαγείρεμα στο
/// σπίτι ή χωρίς μαγείρεμα (η παραγγελία θέλει μαγειρεμένες μορφές, που δεν είναι στη λίστα σου).
List<Dish> aiLibrary(FoodStore food, Set<String> allowed) => [
      for (final d in libraryDishes(food.dishes))
        if (dishRating(d) >= 0 && planInfoOf(d)!.cook != CookWay.out && aiDishAllowed(food, d, allowed) && portionRange(food, d) != null) d,
    ];

/// Τα επιτρεπόμενα τρόφιμα (ωμές μορφές), μία γραμμή ανά κατηγορία, με id και όνομα.
List<String> aiFoodLines(FoodStore food, Set<String> allowed) {
  final foods = [
    for (final f in [...food.mine, ...food.basicFoods])
      if (allowed.contains(f.id)) f,
  ];
  return rawFoodLines(foods, food.likes);
}

String _n(double v) => v.round().toString();

/// Μία γραμμή για ένα φαγητό της βιβλιοθήκης (όπως στις οδηγίες «Πρόγραμμα εβδομάδας»): η μερίδα της συνταγής από τη βάση.
String aiDishLine(FoodStore food, Dish d) {
  final p = planInfoOf(d)!;
  final raw = naturalRaw(d);
  final t = raw == null ? null : itemsTotals(food, raw);
  final r = recipeOf(d);
  final kind = switch (d.kind) {
    DishKind.plate => 'πιάτο',
    DishKind.portions => '${d.servings} μερίδες',
    DishKind.pot => 'κατσαρόλα${r?.servings == null ? '' : ' ~${r!.servings} μερίδες'}',
  };
  return [
    p.key,
    d.name,
    kind,
    p.cook == CookWay.none ? 'χωρίς μαγείρεμα' : (r?.minutes == null ? 'μαγείρεμα' : 'μαγείρεμα ${r!.minutes}′'),
    p.meals.isEmpty ? 'όλα τα γεύματα' : p.meals.map((m) => m.name).join('/'),
    if (p.office) 'γραφείο',
    if (p.tags.isNotEmpty) p.tags.join(', '),
    if (dishRating(d) > 0) 'ΜΟΥ ΑΡΕΣΕ',
    if (t != null) 'μερίδα ${_n(t.kcal)} kcal, πρωτεΐνη ${_n(t.protein)} g, κορεσμένα ${t.satFat.toStringAsFixed(1)} g',
  ].join(' · ');
}

/// Το σταθερό κομμάτι κάθε ερώτησης (κρατιέται στην cache του API, ώστε οι συνταγές να έρχονται γρηγορότερα).
String aiSystem(FoodStore food, Set<String> allowed, Kitchen kitchen) {
  final devices = [
    for (final d in kitchenDevices)
      if (kitchen.has(d.$1)) d.$2,
  ];
  final b = StringBuffer()
    ..writeln('Είσαι ο μάγειρας και διατροφολόγος της προσωπικής εφαρμογής «Υγεία & Φόρμα». Γράφεις στα ελληνικά.')
    ..writeln()
    ..writeln('ΑΠΑΡΑΒΑΤΟΙ ΚΑΝΟΝΕΣ:')
    ..writeln('1. Υλικά ΜΟΝΟ από τη λίστα «ΕΠΙΤΡΕΠΟΜΕΝΑ ΥΛΙΚΑ», με το id ΚΑΙ το όνομα ακριβώς όπως είναι. Τίποτα άλλο, ούτε '
        '«λίγο». Αν ένα φαγητό θέλει κάτι που λείπει, διάλεξε άλλο φαγητό. Το νερό δεν γράφεται ως υλικό.')
    ..writeln('2. Ποσότητες σε γραμμάρια (ml όπου η λίστα γράφει «ml»), ΩΜΑ, όπως ζυγίζονται πριν το μαγείρεμα. Λάδι, αλάτι '
        'και μπαχαρικά είναι υλικά σε γραμμάρια.')
    ..writeln('3. ΜΗ γράψεις θερμίδες ή θρεπτικά: τα μετρά η εφαρμογή από τη βάση της. Η εφαρμογή βάζει και τις μερίδες.')
    ..writeln('4. Απαντάς ΜΟΝΟ με ένα μπλοκ JSON στη μορφή που ζητείται, χωρίς άλλο κείμενο.')
    ..writeln()
    ..writeln('ΚΟΥΖΙΝΑ: ${devices.isEmpty ? 'μάτια κουζίνας, φούρνος, κατσαρόλες, τηγάνια' : devices.join(', ')}'
        '${kitchen.cookware.isEmpty ? '' : '. Σκεύη: ${kitchen.cookware.map((c) => c.size == null ? c.kind : '${c.kind} ${c.size}').join(', ')}'}');
  if (food.likes.note.trim().isNotEmpty) b.writeln('ΣΗΜΕΙΩΣΕΙΣ ΤΟΥ ΧΡΗΣΤΗ: ${food.likes.note.trim()}');
  b
    ..writeln()
    ..writeln('ΕΠΙΤΡΕΠΟΜΕΝΑ ΥΛΙΚΑ (id όνομα), ωμά, ανά κατηγορία:');
  for (final l in aiFoodLines(food, allowed)) {
    b.writeln(l);
  }
  return b.toString();
}

// ---------------------------------------------------------------------------
// Το σχέδιο της εβδομάδας (βήμα 1)
// ---------------------------------------------------------------------------

/// Ένα νέο φαγητό που ζήτησε το AI στο σχέδιο (η συνταγή γράφεται μετά, χωριστά).
class AiNewDish {
  const AiNewDish({required this.key, required this.name, required this.idea, required this.json});
  final String key;
  final String name;
  final String idea;

  /// Ό,τι έγραψε για το φαγητό (είδος, γεύματα, γραφείο, ετικέτες, λεπτά), για να το ξαναδώσουμε στη συνταγή.
  final Map<String, dynamic> json;
}

class AiPlan {
  const AiPlan(this.newDishes, this.days);
  final List<AiNewDish> newDishes;

  /// Για κάθε μέρα: (γεύμα, key).
  final List<List<(Meal, String)>> days;
}

class AiPlanParse {
  const AiPlanParse(this.plan, this.errors);
  final AiPlan? plan;
  final List<String> errors;
}

final _keyRe = RegExp(r'^[a-z0-9][a-z0-9_-]*$');

/// Τι ζητήθηκε: [days] μέρες από τη [from], γεύματα [meals]. [kept]: θέσεις που μένουν (κλειδωμένες ή ήδη γραμμένες).
typedef AiWeekAsk = ({DateTime from, int days, List<Meal> meals, Map<(int, Meal), String> kept});

/// Διαβάζει το σχέδιο. [library]: τα φαγητά που επιτρέπεται να διαλέξει (key → φαγητό). [allKeys]: όλα τα κλειδιά της
/// βιβλιοθήκης (νέο φαγητό δεν παίρνει κλειδί που υπάρχει).
AiPlanParse parseAiPlan(String text, AiWeekAsk ask, Map<String, Dish> library, Set<String> allKeys) {
  final j = jsonOfKind(text, aiWeekKind);
  if (j == null) return const AiPlanParse(null, ['Η απάντηση δεν είναι στη μορφή "kind": "$aiWeekKind".']);
  final errors = <String>[];
  final news = <AiNewDish>[];
  final newKeys = <String, Map<String, dynamic>>{};
  final rawNew = j['new'];
  for (final x in (rawNew is List ? rawNew : const [])) {
    if (x is! Map<String, dynamic>) {
      errors.add('Ένα νέο φαγητό δεν διαβάζεται.');
      continue;
    }
    final key = x['key'] is String ? (x['key'] as String).trim() : '';
    final name = x['name'] is String ? (x['name'] as String).trim() : '';
    final idea = x['idea'] is String ? (x['idea'] as String).trim() : '';
    if (key.isEmpty || key.length > maxLibraryKeyLength || !_keyRe.hasMatch(key)) {
      errors.add('Νέο φαγητό «$name»: το "key" θέλει μόνο λατινικά μικρά, αριθμούς και «-».');
      continue;
    }
    if (allKeys.contains(key) || newKeys.containsKey(key)) {
      errors.add('Νέο φαγητό «$name»: το key «$key» υπάρχει ήδη· διάλεξε άλλο.');
      continue;
    }
    if (name.isEmpty) errors.add('Νέο φαγητό «$key»: λείπει το "name".');
    final cook = cookWayOf(x['cook'] ?? 'home');
    if (cook == null || cook == CookWay.out) errors.add('Νέο φαγητό «$name»: "cook" μόνο "home" ή "none".');
    if (dishKindOf(x['type']) == null) errors.add('Νέο φαγητό «$name»: "type" μόνο "plate", "portions" ή "pot".');
    newKeys[key] = x;
    news.add(AiNewDish(key: key, name: name, idea: idea, json: x));
  }
  if (news.length > aiMaxNewDishes) errors.add('Πολλά νέα φαγητά (${news.length}): το πολύ $aiMaxNewDishes.');
  final days = j['days'];
  if (days is! List || days.length != ask.days) {
    errors.add('Θέλω ακριβώς ${ask.days} μέρες στο "days".');
    return AiPlanParse(null, errors);
  }
  final out = <List<(Meal, String)>>[];
  final start = DateTime(ask.from.year, ask.from.month, ask.from.day);
  for (var i = 0; i < days.length; i++) {
    final date = DateTime(start.year, start.month, start.day + i);
    final label = _day(date);
    final d = days[i];
    final list = d is Map ? d['meals'] : d;
    final slots = <(Meal, String)>[];
    if (list is! List) {
      errors.add('$label: δεν διαβάζεται.');
      out.add(slots);
      continue;
    }
    final seen = <Meal>{};
    for (final s in list) {
      final meal = s is Map ? mealOfName(s['meal']) : null;
      final key = s is Map && s['key'] is String ? (s['key'] as String).trim() : '';
      if (meal == null || !ask.meals.contains(meal)) {
        errors.add('$label: γεύμα που δεν ζητήθηκε (${s is Map ? s['meal'] : '?'}).');
        continue;
      }
      if (!seen.add(meal)) {
        errors.add('$label: το ${mealLabel(meal).toLowerCase()} υπάρχει δύο φορές.');
        continue;
      }
      if (ask.kept.containsKey((i, meal))) continue; // μένει όπως ήταν
      final dish = library[key];
      final nj = newKeys[key];
      if (dish == null && nj == null) {
        errors.add('$label, ${mealLabel(meal).toLowerCase()}: δεν υπάρχει φαγητό με key «$key» (ούτε στη βιβλιοθήκη ούτε στα νέα).');
        continue;
      }
      final meals = dish != null ? planInfoOf(dish)!.meals : [for (final m in (nj!['meals'] is List ? nj['meals'] as List : const [])) if (mealOfName(m) case final mm?) mm];
      if (meals.isNotEmpty && !meals.contains(meal)) {
        errors.add('$label: το «${dish?.name ?? nj!['name']}» δεν είναι για ${mealLabel(meal).toLowerCase()}.');
      }
      final office = dish != null ? planInfoOf(dish)!.office : nj!['office'] == true;
      if (meal == Meal.lunch && officeWeekdays.contains(date.weekday) && !office) {
        errors.add('$label: μεσημέρι στο γραφείο, θέλει φαγητό με "office": true (όχι «${dish?.name ?? nj!['name']}»).');
      }
      slots.add((meal, key));
    }
    for (final m in ask.meals) {
      if (!seen.contains(m) && !ask.kept.containsKey((i, m))) errors.add('$label: λείπει το ${mealLabel(m).toLowerCase()}.');
    }
    out.add(slots);
  }
  // Νέο φαγητό που δεν μπήκε πουθενά: δεν το φτιάχνουμε.
  final used = {for (final d in out) for (final s in d) s.$2};
  news.removeWhere((n) => !used.contains(n.key));
  return AiPlanParse(errors.isEmpty ? AiPlan(news, out) : null, errors);
}

const _wd = ['Δευτέρα', 'Τρίτη', 'Τετάρτη', 'Πέμπτη', 'Παρασκευή', 'Σάββατο', 'Κυριακή'];
String _day(DateTime d) => '${_wd[d.weekday - 1]} ${d.day}/${d.month}';

/// Η ερώτηση του σχεδίου.
String aiPlanPrompt({
  required FoodStore food,
  required AiWeekAsk ask,
  required List<Dish> library,
  required RecipeTargets targets,
  int? legumesWeek,
  int? fishWeek,
}) {
  final start = DateTime(ask.from.year, ask.from.month, ask.from.day);
  final byId = {for (final d in food.dishes) d.id: d};
  final b = StringBuffer()
    ..writeln('Φτιάξε το πρόγραμμα φαγητού μου για ${ask.days} μέρες από τη ${dateKey(start)}, με γεύματα: '
        '${ask.meals.map((m) => '${m.name} (${mealLabel(m).toLowerCase()})').join(', ')}.')
    ..writeln()
    ..writeln('ΣΤΟΧΟΙ ΑΝΑ ΜΕΡΑ: ${thousands(targets.kcal)} kcal · πρωτεΐνη ${targets.protein} g (μοιρασμένη στα γεύματα) · '
        'κορεσμένα έως ${targets.satMax} g · ίνες τουλάχιστον ${targets.fiber} g · αλάτι κάτω από '
        '${targets.salt.toStringAsFixed(0)} g. Τις μερίδες τις βάζει η εφαρμογή· εσύ διαλέγεις φαγητά που ταιριάζουν.')
    ..writeln()
    ..writeln('ΚΑΝΟΝΕΣ ΠΡΟΓΡΑΜΜΑΤΟΣ:')
    ..writeln('- Τρίτη, Τετάρτη, Πέμπτη μεσημέρι είμαι στο γραφείο (ψυγείο και μικροκύματα): μόνο φαγητό με "office": true '
        '(π.χ. όσπρια ή φαγητό κατσαρόλας από το προηγούμενο βράδυ σε ταπεράκι, ή κάτι χωρίς μαγείρεμα).')
    ..writeln('- Καθημερινές ως 30 λεπτά μαγείρεμα, Σαββατοκύριακο ως 60.')
    ..writeln('- Φαγητό κατσαρόλας ("pot") μαγειρεύεται μία φορά και τρώγεται ως 2 φορές μέσα σε 3 μέρες (ίδιο key). Τα άλλα '
        'φαγητά το πολύ 2 φορές την εβδομάδα και όχι σε συνεχόμενες μέρες. Τα σνακ μπορούν να επαναλαμβάνονται.')
    ..writeln('- Ψώνια τη Δευτέρα: το φρέσκο ψάρι νωρίς στην εβδομάδα.')
    ..writeln('- Την εβδομάδα: ${[
      'όσπρια ${legumesWeek ?? 4} φορές',
      'ψάρι ${fishWeek ?? 2} φορές (το ένα λιπαρό)',
      'κόκκινο κρέας το πολύ 1',
      'κοτόπουλο 3–5',
    ].join(' · ')}.')
    ..writeln('- Προτίμησε φαγητά της ΒΙΒΛΙΟΘΗΚΗΣ (ειδικά όσα γράφουν «ΜΟΥ ΑΡΕΣΕ»). Νέα φαγητά μόνο όσα χρειάζονται για ποικιλία '
        'ή για τους κανόνες, το πολύ $aiMaxNewDishes, και ΜΟΝΟ με επιτρεπόμενα υλικά.');
  if (ask.kept.isNotEmpty) {
    b.writeln('- ΜΕΝΟΥΝ ΙΔΙΑ (μην τα γράψεις): ${[
      for (final e in ask.kept.entries)
        '${_day(DateTime(start.year, start.month, start.day + e.key.$1))} ${mealLabel(e.key.$2).toLowerCase()}: '
            '${byId[e.value]?.name ?? '—'}',
    ].join('; ')}.');
  }
  final disliked = [for (final d in food.dishes) if (dishRating(d) < 0) d.name];
  if (disliked.isNotEmpty) b.writeln('- ΔΕΝ ΜΟΥ ΑΡΕΣΑΝ (ποτέ ξανά, ούτε κάτι παρόμοιο με άλλο όνομα): ${disliked.join('; ')}.');
  b
    ..writeln()
    ..writeln('ΒΙΒΛΙΟΘΗΚΗ (key · όνομα · είδος · μαγείρεμα · γεύματα · γραφείο · ετικέτες · μερίδα της συνταγής):');
  if (library.isEmpty) b.writeln('(άδεια: όλα τα φαγητά θα είναι νέα)');
  for (final d in library) {
    b.writeln(aiDishLine(food, d));
  }
  b
    ..writeln()
    ..writeln('Απάντησε με ΕΝΑ μπλοκ JSON σε αυτή ακριβώς τη μορφή («days»: ${ask.days} λίστες, μία για κάθε μέρα με τη σειρά):')
    ..writeln('```json')
    ..writeln('{')
    ..writeln('  "kind": "$aiWeekKind",')
    ..writeln('  "new": [')
    ..writeln('    {"key": "kotopoulo-lemonato", "name": "Κοτόπουλο λεμονάτο με πατάτες", "type": "pot", "cook": "home", '
        '"minutes": 50, "meals": ["lunch", "dinner"], "office": true, "tags": ["κοτόπουλο"], '
        '"idea": "μπούτι κοτόπουλο, πατάτες, λεμόνι, ελαιόλαδο, ρίγανη· για 4 μερίδες"}')
    ..writeln('  ],')
    ..writeln('  "days": [')
    ..writeln('    [{"meal": "lunch", "key": "kotopoulo-lemonato"}, {"meal": "dinner", "key": "…"}],')
    ..writeln('    …')
    ..writeln('  ]')
    ..writeln('}')
    ..writeln('```')
    ..writeln('Το "key" ενός νέου φαγητού: μόνο λατινικά μικρά, αριθμοί, «-», ΔΙΑΦΟΡΕΤΙΚΟ από όσα υπάρχουν στη βιβλιοθήκη. '
        'Ετικέτες όπου ταιριάζουν: ${standardTags.join(', ')}.');
  return b.toString();
}

// ---------------------------------------------------------------------------
// Μία συνταγή (βήμα 2, και για «Άλλαξε αυτό το γεύμα»)
// ---------------------------------------------------------------------------

/// Η ερώτηση για τη συνταγή ενός νέου φαγητού του σχεδίου.
String aiRecipePrompt(AiNewDish n) {
  final j = n.json;
  return [
    'Γράψε τη συνταγή αυτού του φαγητού του προγράμματός μου, ΜΟΝΟ με τα ΕΠΙΤΡΕΠΟΜΕΝΑ ΥΛΙΚΑ (id και όνομα):',
    jsonEncode({
      'key': n.key,
      'name': n.name,
      for (final k in const ['type', 'cook', 'minutes', 'meals', 'office', 'tags', 'servings'])
        if (j[k] != null) k: j[k],
      'idea': n.idea,
    }),
    '',
    _recipeFormat(n.key, n.name),
  ].join('\n');
}

String _recipeFormat(String key, String name) => [
      'Κράτα ΙΔΙΑ τα "key", "name", "type", "cook", "meals", "office", "tags". "type": "plate" = ένα πιάτο για μένα· '
          '"portions" = ίσες μερίδες (γράψε "servings")· "pot" = κατσαρόλα για όλους (γράψε στο "servings" πόσες μερίδες '
          'περίπου βγάζει). Με "cook": "home" θέλει "steps" (συσκευή, φωτιά, λεπτά, πότε μπαίνει κάθε υλικό).',
      'Απάντησε με ΕΝΑ μπλοκ JSON σε αυτή ακριβώς τη μορφή:',
      '```json',
      '{"kind": "$libraryKind", "dishes": [{"key": "$key", "name": "$name", "type": "pot", "cook": "home", "servings": 4, '
          '"minutes": 40, "meals": ["lunch"], "office": true, "tags": ["…"], '
          '"items": [{"id": "C…", "name": "…", "g": 250}, …], '
          '"steps": [{"text": "…", "device": "…", "heat": "μέτρια", "min": 10}, …], '
          '"tips": ["…"], "keeps": "…", "why": "…"}]}',
      '```',
    ].join('\n');

/// Ένα φαγητό από την απάντηση (μορφή βιβλιοθήκης, ΕΝΑ φαγητό), ελεγμένο με τη βάση και τα επιτρεπόμενα υλικά.
/// [wantKey]: το κλειδί που ζητήθηκε (null: οποιοδήποτε νέο). Επιστρέφει το φαγητό ή τα προβλήματα.
({Dish? dish, List<String> errors}) aiReadDish(
  String text, {
  required FoodStore food,
  required Set<String> allowed,
  required int now,
  required String Function() newId,
  String? wantKey,
}) {
  final p = parseLibrary(text);
  if (p.errors.isNotEmpty) return (dish: null, errors: p.errors);
  if (p.entries.length != 1) return (dish: null, errors: const ['Θέλω ΕΝΑ φαγητό στο "dishes".']);
  final e = p.entries.first;
  if (wantKey != null && e.key != wantKey) return (dish: null, errors: ['Το "key" πρέπει να μείνει «$wantKey».']);
  if (e.plan.cook == CookWay.out) return (dish: null, errors: const ['"cook" μόνο "home" ή "none".']);
  if (libraryDishes(food.dishes).any((d) => planInfoOf(d)!.key == e.key)) {
    return (dish: null, errors: ['Το key «${e.key}» υπάρχει ήδη στη βιβλιοθήκη· διάλεξε άλλο.']);
  }
  final imp = planLibraryImport(
    p,
    existing: food.dishes,
    food: (id) => food.itemFood(DishItem(id, id, 1)),
    likes: food.likes,
    now: now,
    newId: newId,
  );
  if (imp.problems.isNotEmpty) return (dish: null, errors: imp.problems.first.errors);
  if (imp.added.length != 1) return (dish: null, errors: const ['Το φαγητό δεν διαβάστηκε.']);
  final d = imp.added.first;
  final bad = [
    for (final i in d.items)
      if (!allowed.contains(_nowId(food, i))) i.name,
  ];
  if (bad.isNotEmpty) {
    return (dish: null, errors: ['Υλικά εκτός λίστας «ΕΠΙΤΡΕΠΟΜΕΝΑ ΥΛΙΚΑ»: ${bad.join(', ')}. Βγάλ’ τα ή άλλαξε φαγητό.']);
  }
  if (portionRange(food, d) == null) return (dish: null, errors: const ['Δεν βγαίνουν θερμίδες από τα υλικά.']);
  return (dish: d, errors: const []);
}

/// Ρωτά το AI μέχρι να πάρει σωστή απάντηση ([read] → null προβλήματα), ως [aiMaxRetries] ξανά. Κάθε ξανά στέλνει πίσω την
/// απάντησή του και τα προβλήματα. Επιστρέφει το αποτέλεσμα ή (null, τελευταία προβλήματα / αποτυχία δικτύου).
Future<(T?, List<String>, AiFail?)> aiAskUntilValid<T>(
  AiCall call, {
  required String model,
  required String system,
  required String prompt,
  required (T?, List<String>) Function(String text) read,
  int maxTokens = 4000,
}) async {
  final messages = <(String, String)>[('user', prompt)];
  var last = const <String>[];
  for (var attempt = 0; attempt <= aiMaxRetries; attempt++) {
    final r = await call(AiAsk(model: model, system: system, messages: List.of(messages), maxTokens: maxTokens));
    if (r.fail != null) return (null, last, r.fail);
    final text = r.text!;
    if (r.cut) {
      last = const ['Η απάντηση κόπηκε (πολύ μεγάλη).'];
    } else {
      final (v, errs) = read(text);
      if (v != null) return (v, const <String>[], null);
      last = errs;
    }
    messages
      ..add(('assistant', text))
      ..add(('user', 'Η εφαρμογή δεν δέχτηκε την απάντηση:\n${[for (final e in last) '- $e'].join('\n')}\n'
          'Διόρθωσέ τα και στείλε ξανά ΟΛΟ το JSON, στην ίδια μορφή${r.cut ? ', πιο σύντομα (λιγότερα βήματα και συμβουλές)' : ''}.'));
  }
  return (null, last, null);
}

/// Τρέχει έως [aiParallel] εργασίες ταυτόχρονα, με τη σειρά τους στο αποτέλεσμα.
Future<List<R>> aiPool<A, R>(List<A> items, Future<R> Function(A) task, {void Function(int done)? progress}) async {
  final out = List<R?>.filled(items.length, null);
  var next = 0, done = 0;
  Future<void> worker() async {
    while (next < items.length) {
      final i = next++;
      out[i] = await task(items[i]);
      progress?.call(++done);
    }
  }

  await Future.wait([for (var w = 0; w < math.min(aiParallel, items.length); w++) worker()]);
  return [for (final r in out) r as R];
}

// ---------------------------------------------------------------------------
// Όλο το «Φτιάξε την εβδομάδα με AI»
// ---------------------------------------------------------------------------

class AiWeekResult {
  const AiWeekResult({this.plan, this.newDishes = const [], this.notes = const [], this.fail, this.errors = const []});

  /// Το πρόγραμμα (δεν έχει αποθηκευτεί) ή null αν δεν βγήκε.
  final WeekPlan? plan;

  /// Τα νέα φαγητά του προγράμματος (δεν έχουν αποθηκευτεί).
  final List<Dish> newDishes;

  /// Ό,τι δεν βγήκε όπως ζητούν οι κανόνες, σε απλά λόγια.
  final List<String> notes;
  final AiFail? fail;

  /// Γιατί δεν βγήκε (όταν [plan] είναι null και δεν φταίει η σύνδεση).
  final List<String> errors;
}

/// Τι έγινε μέχρι τώρα (για την οθόνη).
enum AiStage { plan, recipes, check, fix }

/// Οι έλεγχοι κάθε μέρας από τη βάση (θερμίδες, πρωτεΐνη, κορεσμένα). Επιστρέφει (μέρα, πρόβλημα).
List<(int, String)> aiDayProblems(FoodStore food, WeekPlan w, List<Dish> extra, RecipeTargets t, List<Meal> meals) {
  final byId = {for (final d in [...food.dishes, ...extra]) d.id: d};
  final out = <(int, String)>[];
  for (var i = 0; i < w.days.length; i++) {
    var kcal = 0.0, protein = 0.0, sat = 0.0;
    var unknown = false;
    for (final s in w.days[i]) {
      final tt = plannedTotals(food, byId[s.dishId], s);
      if (tt == null) {
        unknown = true;
        continue;
      }
      kcal += tt.kcal;
      protein += tt.protein;
      sat += tt.satFat;
    }
    if (unknown || w.days[i].isEmpty) continue;
    final share = w.days[i].length / math.max(1, meals.length);
    final f = share >= 1 ? 1.0 : share;
    final kt = t.kcal * f;
    final label = _day(w.dayAt(i));
    if ((kcal - kt).abs() > kt * aiDayKcalTol) out.add((i, '$label: ${_n(kcal)} kcal (στόχος ${_n(kt)}).'));
    if (protein < t.protein * f * aiDayProteinMin) {
      out.add((i, '$label: πρωτεΐνη ${_n(protein)} g (στόχος ${t.protein}): θέλει πιο πρωτεϊνούχα φαγητά.'));
    }
    if (sat > t.satMax) out.add((i, '$label: κορεσμένα ${sat.toStringAsFixed(1)} g (όριο ${t.satMax}): θέλει λιγότερα λιπαρά ζωικά.'));
  }
  return out;
}

/// «Φτιάξε την εβδομάδα με AI». [keep]: το τωρινό πρόγραμμα (μένουν κλειδωμένα και γραμμένα, αν είναι ίδια αρχή).
Future<AiWeekResult> aiBuildWeek({
  required AiCall call,
  required FoodStore food,
  required Kitchen kitchen,
  required RecipeTargets targets,
  required DateTime from,
  required List<Meal> meals,
  int? legumesWeek,
  int? fishWeek,
  WeekPlan? keep,
  required int now,
  required String Function() newId,
  void Function(AiStage stage, int done, int total)? progress,
}) async {
  final allowed = aiAllowedIds(food.likes);
  if (food.likes.like.isEmpty) {
    return const AiWeekResult(errors: ['Πρώτα διάλεξε τι σου αρέσει (Τα φαγητά μου › Τι μου αρέσει): μόνο από αυτά φτιάχνει.']);
  }
  final start = DateTime(from.year, from.month, from.day);
  final keepPlan = keep != null && keep.from == dateKey(start) ? keep : null;
  final kept = <(int, Meal), String>{
    if (keepPlan != null)
      for (var i = 0; i < keepPlan.days.length && i < 7; i++)
        for (final s in keepPlan.days[i])
          if (s.locked || s.state != SlotState.open) (i, s.meal): s.dishId,
  };
  final ask = (from: start, days: 7, meals: meals, kept: kept);
  final lib = aiLibrary(food, allowed);
  final libByKey = {for (final d in lib) planInfoOf(d)!.key!: d};
  final allKeys = {for (final d in libraryDishes(food.dishes)) planInfoOf(d)!.key!};
  final system = aiSystem(food, allowed, kitchen);

  progress?.call(AiStage.plan, 0, 1);
  var prompt = aiPlanPrompt(food: food, ask: ask, library: lib, targets: targets, legumesWeek: legumesWeek, fishWeek: fishWeek);
  final (plan0, errs0, fail0) = await aiAskUntilValid<AiPlan>(
    call,
    model: aiModelPlan,
    system: system,
    prompt: prompt,
    maxTokens: 3000,
    read: (t) {
      final p = parseAiPlan(t, ask, libByKey, allKeys);
      return (p.plan, p.errors);
    },
  );
  if (fail0 != null) return AiWeekResult(fail: fail0);
  if (plan0 == null) return AiWeekResult(errors: ['Το AI δεν έφτιαξε σωστό πρόγραμμα:', ...errs0]);

  final extra = <Dish>[];
  final notes = <String>[];
  Future<AiWeekResult?> recipes(AiPlan p) async {
    final want = [for (final n in p.newDishes) if (!extra.any((d) => planInfoOf(d)!.key == n.key)) n];
    if (want.isEmpty) return null;
    progress?.call(AiStage.recipes, 0, want.length);
    final res = await aiPool<AiNewDish, (Dish?, List<String>, AiFail?)>(
      want,
      (n) => aiAskUntilValid<Dish>(
        call,
        model: aiModelRecipe,
        system: system,
        prompt: aiRecipePrompt(n),
        read: (t) {
          final r = aiReadDish(t, food: food, allowed: allowed, now: now, newId: newId, wantKey: n.key);
          return (r.dish, r.errors);
        },
      ),
      progress: (done) => progress?.call(AiStage.recipes, done, want.length),
    );
    for (var k = 0; k < want.length; k++) {
      final (d, errs, fail) = res[k];
      if (fail != null) return AiWeekResult(fail: fail);
      if (d == null) {
        notes.add('Η συνταγή «${want[k].name}» δεν πέρασε τους ελέγχους (${errs.join(' ')}). Η θέση της μένει κενή· βάλε φαγητό '
            'με «Άλλαξέ το».');
      } else {
        extra.add(d);
      }
    }
    return null;
  }

  final stop = await recipes(plan0);
  if (stop != null) return stop;

  AutoWeek assemble(AiPlan p) {
    final byKey = {...libByKey, for (final d in extra) planInfoOf(d)!.key!: d};
    final forced = <(int, Meal), String>{
      for (var i = 0; i < p.days.length; i++)
        for (final (m, k) in p.days[i])
          if (byKey[k] case final d?) (i, m): d.id,
    };
    return autoWeek(
      food,
      from: start,
      meals: meals,
      kcalTarget: targets.kcal.toDouble(),
      proteinTarget: targets.protein.toDouble(),
      legumesWeek: legumesWeek ?? 0,
      fishWeek: fishWeek ?? 0,
      keep: keepPlan,
      now: now,
      extra: extra,
      forced: forced,
    );
  }

  progress?.call(AiStage.check, 0, 1);
  var plan = plan0;
  var built = assemble(plan);
  var problems = aiDayProblems(food, built.plan, extra, targets, meals);
  if (problems.isNotEmpty) {
    // Μία διόρθωση: πίσω στο AI το πρόγραμμα με τα προβλήματα των ημερών (από τη βάση).
    progress?.call(AiStage.fix, 0, 1);
    final byId = {for (final d in [...food.dishes, ...extra]) d.id: d};
    final current = {
      'kind': aiWeekKind,
      'new': const [],
      'days': [
        for (var i = 0; i < built.plan.days.length; i++)
          [
            for (final s in built.plan.days[i])
              if (!kept.containsKey((i, s.meal)) && byId[s.dishId] != null) {'meal': s.meal.name, 'key': planInfoOf(byId[s.dishId]!)?.key},
          ],
      ],
    };
    final fixLib = [...lib, ...extra];
    final fixByKey = {for (final d in fixLib) planInfoOf(d)!.key!: d};
    prompt = '${aiPlanPrompt(food: food, ask: ask, library: fixLib, targets: targets, legumesWeek: legumesWeek, fishWeek: fishWeek)}\n'
        'ΤΩΡΙΝΟ ΠΡΟΓΡΑΜΜΑ:\n```json\n${jsonEncode(current)}\n```\n'
        'Με τις μερίδες της εφαρμογής βγαίνουν αυτά τα προβλήματα:\n${[for (final p in problems) '- ${p.$2}'].join('\n')}\n'
        'Άλλαξε ΜΟΝΟ τα γεύματα αυτών των ημερών ώστε να διορθωθούν, και στείλε ΟΛΟ το πρόγραμμα στην ίδια μορφή.';
    final (plan1, _, fail1) = await aiAskUntilValid<AiPlan>(
      call,
      model: aiModelPlan,
      system: system,
      prompt: prompt,
      maxTokens: 3000,
      read: (t) {
        final p = parseAiPlan(t, ask, fixByKey, {...allKeys, for (final d in extra) planInfoOf(d)!.key!});
        return (p.plan, p.errors);
      },
    );
    if (fail1 == null && plan1 != null) {
      final stop1 = await recipes(plan1);
      if (stop1 != null) return stop1;
      final b1 = assemble(plan1);
      final p1 = aiDayProblems(food, b1.plan, extra, targets, meals);
      if (p1.length < problems.length) {
        plan = plan1;
        built = b1;
        problems = p1;
      }
    }
  }
  // Μόνο τα νέα φαγητά που μπήκαν τελικά στο πρόγραμμα.
  final usedIds = {for (final d in built.plan.days) for (final s in d) s.dishId};
  final keptNew = [for (final d in extra) if (usedIds.contains(d.id)) d];
  final allNotes = <String>{...notes, ...built.notes, for (final p in problems) p.$2}.toList();
  return AiWeekResult(
    plan: WeekPlan(from: built.plan.from, days: built.plan.days, created: built.plan.created, source: 'ai'),
    newDishes: keptNew,
    notes: allNotes,
  );
}

// ---------------------------------------------------------------------------
// «Άλλαξε αυτό το γεύμα»
// ---------------------------------------------------------------------------

/// Γιατί αλλάζει.
enum SwapReason { time, missing, appetite }

/// Τα νούμερα της θέσης από τη βάση: θερμίδες, πρωτεΐνη, κορεσμένα.
typedef SlotNumbers = ({double kcal, double protein, double sat});

/// Η μερίδα του [d] για [kcal] θερμίδες (μέσα στα όρια της μερίδας του) και τα νούμερά της από τη βάση. null αν δεν βγαίνει.
({double kcal, SlotNumbers n})? portionFor(FoodStore food, Dish d, double kcal) {
  final r = portionRange(food, d);
  if (r == null) return null;
  final k = kcal.clamp(r.lo, r.hi).toDouble();
  return (kcal: k, n: (kcal: k, protein: k * r.proteinPerKcal, sat: k * r.satPerKcal));
}

/// Είναι «ανάλογο»; Επιστρέφει τα προβλήματα (κενό = ναι).
List<String> analogProblems(SlotNumbers old, SlotNumbers cand) => [
      if ((cand.kcal - old.kcal).abs() > old.kcal * aiSwapKcalTol)
        'θερμίδες ${_n(cand.kcal)} αντί για περίπου ${_n(old.kcal)} (η μερίδα του δεν φτάνει εκεί)',
      if (cand.protein < old.protein * aiSwapProteinMin)
        'πρωτεΐνη ${_n(cand.protein)} g, χρειάζεται τουλάχιστον ${_n(old.protein * aiSwapProteinMin)} g',
      if (cand.sat > old.sat + aiSwapSatExtra)
        'κορεσμένα ${cand.sat.toStringAsFixed(1)} g, το πολύ ${(old.sat + aiSwapSatExtra).toStringAsFixed(1)} g',
    ];

class AiSwapResult {
  const AiSwapResult({this.dish, this.kcal, this.isNew = false, this.fail, this.errors = const []});
  final Dish? dish;
  final double? kcal;

  /// Νέο φαγητό (μπαίνει και στη βιβλιοθήκη με το «Ναι»).
  final bool isNew;
  final AiFail? fail;
  final List<String> errors;
}

/// Ελέγχει ένα υποψήφιο φαγητό για τη θέση.
List<String> swapChecks(FoodStore food, Dish d, {required Meal meal, required bool office, required SwapReason reason,
    String? missingId, required SlotNumbers old, required Set<String> allowed, required String currentId}) {
  final p = planInfoOf(d);
  final out = <String>[];
  if (d.id == currentId) out.add('είναι το ίδιο φαγητό');
  if (p != null && !p.fits(meal)) out.add('δεν είναι για ${mealLabel(meal).toLowerCase()}');
  if (office && !(p?.office ?? false)) out.add('θέλει φαγητό για γραφείο ("office": true)');
  if (!aiDishAllowed(food, d, allowed)) out.add('έχει υλικό εκτός λίστας');
  if (dishRating(d) < 0) out.add('είναι στα «Δεν μου άρεσε»');
  if (missingId != null && d.items.any((i) => _nowId(food, i) == missingId)) out.add('έχει το υλικό που λείπει');
  if (reason == SwapReason.time && p?.cook != CookWay.none) {
    final m = recipeOf(d)?.minutes;
    if (m == null || m > aiQuickMinutes) out.add('θέλει ως $aiQuickMinutes λεπτά μαγείρεμα (ή χωρίς μαγείρεμα)');
  }
  final pf = portionFor(food, d, old.kcal);
  if (pf == null) {
    out.add('δεν βγαίνουν θερμίδες');
  } else {
    out.addAll(analogProblems(old, pf.n));
  }
  return out;
}

/// «Άλλαξε αυτό το γεύμα» με AI: ένα ανάλογο φαγητό (της βιβλιοθήκης ή νέο) για τη θέση [day]/[index] του [w].
Future<AiSwapResult> aiSwapSlot({
  required AiCall call,
  required FoodStore food,
  required Kitchen kitchen,
  required WeekPlan w,
  required int day,
  required int index,
  required SwapReason reason,
  String? missingId,
  required int now,
  required String Function() newId,
}) async {
  final s = w.days[day][index];
  final byId = {for (final d in food.dishes) d.id: d};
  final cur = byId[s.dishId];
  final allowed = aiAllowedIds(food.likes);
  if (cur == null) return const AiSwapResult(errors: ['Το φαγητό αυτής της θέσης δεν υπάρχει πια.']);
  final curTotals = plannedTotals(food, cur, s);
  if (curTotals == null) return const AiSwapResult(errors: ['Δεν βγαίνουν θερμίδες για το τωρινό φαγητό.']);
  final old = (kcal: curTotals.kcal, protein: curTotals.protein, sat: curTotals.satFat);
  final date = w.dayAt(day);
  final office = s.meal == Meal.lunch && officeWeekdays.contains(date.weekday);
  List<String> check(Dish d) => swapChecks(food, d,
      meal: s.meal, office: office, reason: reason, missingId: missingId, old: old, allowed: allowed, currentId: cur.id);

  // Φαγητά της βιβλιοθήκης που περνούν ήδη όλους τους ελέγχους: δίνονται στο AI ως πρώτη επιλογή.
  final sameDay = {for (final x in w.days[day]) x.dishId};
  final ready = [
    for (final d in aiLibrary(food, allowed))
      if (!sameDay.contains(d.id) && check(d).isEmpty) d,
  ];
  final missingName = missingId == null ? null : food.itemFood(DishItem(missingId, missingId, 1))?.name;
  final why = switch (reason) {
    SwapReason.time => 'Δεν έχω χρόνο: θέλω κάτι ως $aiQuickMinutes λεπτά ή χωρίς μαγείρεμα.',
    SwapReason.missing => 'Μου λείπει υλικό${missingName == null ? '' : ': $missingName (να μην το έχει)'}.',
    SwapReason.appetite => 'Δεν μου κάνει όρεξη: κάτι διαφορετικό.',
  };
  final prompt = StringBuffer()
    ..writeln('Άλλαξε ένα γεύμα του προγράμματός μου με ΑΝΑΛΟΓΟ φαγητό.')
    ..writeln('Γεύμα: ${_day(date)}, ${mealLabel(s.meal).toLowerCase()}${office ? ' (στο γραφείο: θέλει "office": true)' : ''}.')
    ..writeln('Τώρα: «${cur.name}», μερίδα ${_n(old.kcal)} kcal, πρωτεΐνη ${_n(old.protein)} g, κορεσμένα '
        '${old.sat.toStringAsFixed(1)} g.')
    ..writeln('Αιτία: $why')
    ..writeln('Ανάλογο σημαίνει: ίδιο γεύμα, με μερίδα κοντά στις ίδιες θερμίδες, πρωτεΐνη τουλάχιστον '
        '${_n(old.protein * aiSwapProteinMin)} g και κορεσμένα το πολύ ${(old.sat + aiSwapSatExtra).toStringAsFixed(1)} g '
        'σε αυτή τη μερίδα. Η εφαρμογή βάζει τη μερίδα.')
    ..writeln();
  if (ready.isNotEmpty) {
    prompt
      ..writeln('ΦΑΓΗΤΑ ΤΗΣ ΒΙΒΛΙΟΘΗΚΗΣ ΠΟΥ ΤΑΙΡΙΑΖΟΥΝ ΗΔΗ (key · όνομα · …):')
      ..writeln([for (final d in ready.take(40)) aiDishLine(food, d)].join('\n'))
      ..writeln()
      ..writeln('Αν ένα από αυτά είναι καλή επιλογή, απάντησε: ```json\n{"kind": "$aiSwapKind", "key": "…"}\n```')
      ..writeln('Αλλιώς γράψε ΝΕΟ φαγητό:');
  } else {
    prompt.writeln('Γράψε ΝΕΟ φαγητό (στη βιβλιοθήκη δεν υπάρχει κάτι που ταιριάζει):');
  }
  prompt.writeln(_recipeFormat('neo-kleidi', 'Όνομα'));
  final system = aiSystem(food, allowed, kitchen);
  final readyByKey = {for (final d in ready) planInfoOf(d)!.key!: d};
  final (res, errs, fail) = await aiAskUntilValid<AiSwapResult>(
    call,
    model: aiModelRecipe,
    system: system,
    prompt: prompt.toString(),
    read: (t) {
      final sw = jsonOfKind(t, aiSwapKind);
      if (sw != null) {
        final d = readyByKey[sw['key']];
        if (d == null) return (null, ['Το key «${sw['key']}» δεν είναι στη λίστα «ΦΑΓΗΤΑ ΤΗΣ ΒΙΒΛΙΟΘΗΚΗΣ».']);
        final pf = portionFor(food, d, old.kcal)!;
        return (AiSwapResult(dish: d, kcal: pf.kcal), const <String>[]);
      }
      final r = aiReadDish(t, food: food, allowed: allowed, now: now, newId: newId);
      if (r.dish == null) return (null, r.errors);
      final c = check(r.dish!);
      if (c.isNotEmpty) return (null, ['Το «${r.dish!.name}» δεν είναι ανάλογο: ${c.join('· ')}.']);
      final pf = portionFor(food, r.dish!, old.kcal)!;
      return (AiSwapResult(dish: r.dish, kcal: pf.kcal, isNew: true), const <String>[]);
    },
  );
  if (fail != null) return AiSwapResult(fail: fail);
  if (res == null) {
    return AiSwapResult(errors: [
      'Δεν βρέθηκε ανάλογο φαγητό που να περνά όλους τους ελέγχους.',
      ...errs,
      if (ready.isEmpty) 'Μπορείς να διαλέξεις μόνος σου με «Άλλαξέ το».',
    ]);
  }
  return res;
}

/// Το πρόγραμμα με το νέο φαγητό στη θέση (μερίδα [kcal]· η θέση ξεκλειδώνει και ξανανοίγει).
WeekPlan applySwap(WeekPlan w, int day, int index, Dish d, double kcal) {
  final s = w.days[day][index];
  return w.withSlot(
      day, index, PlanSlot(meal: s.meal, dishId: d.id, kcal: ((kcal / 10).round() * 10).toDouble().clamp(minSlotKcal, maxSlotKcal)));
}

// ---------------------------------------------------------------------------
// «Έφαγα κάτι άλλο»: οι υπόλοιπες μερίδες της μέρας (κανόνες, χωρίς AI)
// ---------------------------------------------------------------------------

/// Ξαναμοιράζει τις θερμίδες των ανοιχτών γευμάτων της μέρας [day], ώστε [eaten] (ό,τι γράφτηκε ήδη στο ημερολόγιο τη μέρα)
/// + τα υπόλοιπα ≈ [target]. Κάθε μερίδα μέσα στα όριά της (0,6–1,6). Επιστρέφει το νέο πρόγραμμα και τις αλλαγές
/// (όνομα φαγητού, πριν, μετά)· null αν δεν άλλαξε τίποτα.
(WeekPlan, List<(String, double, double)>)? rebalanceDay(FoodStore food, WeekPlan w, int day, double eaten, double target) {
  final byId = {for (final d in food.dishes) d.id: d};
  final open = <int>[
    for (var k = 0; k < w.days[day].length; k++)
      if (w.days[day][k].state == SlotState.open) k,
  ];
  if (open.isEmpty) return null;
  final ranges = <int, ({double lo, double hi})>{};
  final cur = <int, double>{};
  for (final k in open) {
    final s = w.days[day][k];
    final d = byId[s.dishId];
    final r = d == null ? null : portionRange(food, d);
    final t = d == null ? null : plannedTotals(food, d, s);
    if (r == null || t == null) return null;
    ranges[k] = (lo: r.lo, hi: r.hi);
    cur[k] = t.kcal;
  }
  final left = target - eaten;
  final sum = cur.values.fold(0.0, (a, b) => a + b);
  if (sum <= 0) return null;
  final next = <int, double>{
    for (final k in open) k: (cur[k]! * (left <= 0 ? 0 : left / sum)).clamp(ranges[k]!.lo, ranges[k]!.hi).toDouble(),
  };
  final changes = <(String, double, double)>[];
  var out = w;
  for (final k in open) {
    final v = ((next[k]! / 10).round() * 10).toDouble().clamp(minSlotKcal, maxSlotKcal).toDouble();
    if ((v - cur[k]!).abs() < 20) continue; // μικρότερο από μία κουταλιά: δεν αλλάζει
    final s = w.days[day][k];
    out = out.withSlot(day, k, s.copyWith(kcal: v));
    changes.add((byId[s.dishId]!.name, cur[k]!, v));
  }
  return changes.isEmpty ? null : (out, changes);
}
