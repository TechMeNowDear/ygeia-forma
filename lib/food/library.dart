/// Βιβλιοθήκη φαγητών (15/11, υποδομή για το εβδομαδιαίο πρόγραμμα): πολλά φαγητά μαζί με μία επικόλληση.
///
/// Κανόνες (έγγραφο προδιαγραφών › «Διατροφή: εβδομαδιαίο πρόγραμμα από βιβλιοθήκη συνταγών»):
/// - Τα φαγητά τα γράφει ένας βοηθός AI σε άλλη συζήτηση· η εφαρμογή δίνει τις οδηγίες (μορφή, τρόφιμα της βάσης με το id
///   τους, κουζίνα, προτιμήσεις, στόχους). Οι αριθμοί θρεπτικών βγαίνουν ΠΑΝΤΑ από τη βάση· ό,τι γράψει ο βοηθός αγνοείται.
/// - Αυστηρός έλεγχος, χωρίς μαντέματα: κάθε υλικό πρέπει να έχει id που υπάρχει, όνομα που ταιριάζει με το id, να μην
///   είναι στα «Δε μου αρέσει», και (εκτός από φαγητά παραγγελίας) να είναι ωμή μορφή. Φαγητό με πρόβλημα δεν περνά· τα
///   υπόλοιπα περνούν. Τα προβλήματα αντιγράφονται για να τα διορθώσει ο βοηθός.
/// - Κάθε φαγητό έχει σταθερό κλειδί («key»): η ίδια επικόλληση ξανά αλλάζει το ίδιο φαγητό (κρατά ιστορικό, τελευταίο
///   μαγείρεμα, πόσες φορές το έγραψες), δεν φτιάχνει διπλό. Φαγητά που λείπουν από μια νέα επικόλληση δεν σβήνονται.
/// - Τα στοιχεία για το πρόγραμμα ([PlanInfo]) μπαίνουν στο φαγητό στο κλειδί «plan» ([Dish.extra]): οι παλιές εκδόσεις
///   τα κρατούν όπως είναι.
library;

import 'dart:convert';

import '../format.dart' show thousands;
import 'dishes.dart';
import 'food_model.dart';
import 'food_search.dart' show phonetic, stem;
import 'kitchen.dart';
import 'recipe.dart';

const libraryKind = 'ygeia-library';

/// Η πρώτη γραμμή των οδηγιών: αν επικολληθούν οι ίδιες οι οδηγίες (αντί για την απάντηση), το λέμε.
const libraryPromptTitle = 'ΒΙΒΛΙΟΘΗΚΗ ΦΑΓΗΤΩΝ ΓΙΑ ΤΗΝ ΕΦΑΡΜΟΓΗ «ΥΓΕΙΑ & ΦΟΡΜΑ»';

/// Όρια (δική μας επιλογή, ώστε ένα λάθος κείμενο να μη φτιάχνει παράλογη βιβλιοθήκη).
const maxLibraryDishes = 300;
const maxPlanTags = 12;
const maxTagLength = 30;
const maxOrderTextLength = 800;
const maxLibraryKeyLength = 60;

final _keyPattern = RegExp(r'^[a-z0-9][a-z0-9_-]*$');

/// Οι ετικέτες που προτείνουμε στον βοηθό, ώστε οι κανόνες του προγράμματος να τις βρίσκουν πάντα με το ίδιο όνομα.
const standardTags = [
  'όσπρια',
  'ψάρι',
  'λιπαρό ψάρι',
  'θαλασσινά',
  'κόκκινο κρέας',
  'κοτόπουλο',
  'αυγά',
  'γαλακτοκομικά',
  'λαχανικά',
  'φρούτα',
  'ζυμαρικά',
  'ρύζι',
];

/// Πώς φτιάχνεται ένα φαγητό: μαγείρεμα στο σπίτι, χωρίς μαγείρεμα (π.χ. φρυγανιές με cottage), ή παραγγελία.
enum CookWay { home, none, out }

CookWay? cookWayOf(Object? v) => switch (v) {
      'home' => CookWay.home,
      'none' => CookWay.none,
      'out' => CookWay.out,
      _ => null,
    };

String cookWayLabel(CookWay c) => switch (c) {
      CookWay.home => 'Μαγείρεμα στο σπίτι',
      CookWay.none => 'Χωρίς μαγείρεμα',
      CookWay.out => 'Από παραγγελία',
    };

Meal? mealOfName(Object? v) {
  for (final m in Meal.values) {
    if (m.name == v) return m;
  }
  return null;
}

/// Ετικέτα όπως αποθηκεύεται: χωρίς κενά στις άκρες, μικρά γράμματα, ένα κενό ανάμεσα στις λέξεις.
String normTag(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Ίδια ετικέτα, με ή χωρίς τόνους, σε ελληνικά ή greeklish («Όσπρια» = «οσπρια» = «ospria»).
bool sameTag(String a, String b) => phonetic(normTag(a)) == phonetic(normTag(b));

/// Τα στοιχεία ενός φαγητού για το εβδομαδιαίο πρόγραμμα.
class PlanInfo {
  const PlanInfo({this.key, this.meals = const [], this.tags = const [], this.office = false, this.cook = CookWay.home, this.order});

  /// Σταθερό κλειδί της βιβλιοθήκης (null: φαγητό που έφτιαξες εσύ στην εφαρμογή).
  final String? key;

  /// Σε ποια γεύματα ταιριάζει (κενό: σε όλα).
  final List<Meal> meals;

  /// Ετικέτες για τους κανόνες του προγράμματος (π.χ. «όσπρια», «λιπαρό ψάρι»).
  final List<String> tags;

  /// Ταιριάζει για μεσημεριανό στο γραφείο (χωρίς μαγείρεμα, ή όσπρια σε ταπεράκι).
  final bool office;
  final CookWay cook;

  /// Τι να ζητήσεις όταν το παραγγέλνεις (ψήσιμο, λάδι, αλάτι, συνοδευτικά).
  final String? order;

  bool hasTag(String t) => tags.any((x) => sameTag(x, t));
  bool fits(Meal m) => meals.isEmpty || meals.contains(m);

  Map<String, Object> toJson() => {
        if (key != null) 'key': key!,
        if (meals.isNotEmpty) 'meals': [for (final m in meals) m.name],
        if (tags.isNotEmpty) 'tags': tags,
        if (office) 'office': true,
        'cook': cook.name,
        if (order != null) 'order': order!,
      };

  /// null αν δεν υπάρχει ή δεν είναι αντικείμενο. Ό,τι μικρό δεν στέκει (άγνωστο γεύμα, μεγάλη ετικέτα) απλώς παραλείπεται.
  static PlanInfo? fromJson(Object? j) {
    if (j is! Map) return null;
    final k = j['key'];
    final meals = <Meal>[
      for (final m in (j['meals'] is List ? j['meals'] as List : const []))
        if (mealOfName(m) case final mm?) mm,
    ];
    final o = j['order'];
    return PlanInfo(
      key: k is String && k.length <= maxLibraryKeyLength && _keyPattern.hasMatch(k) ? k : null,
      meals: meals.toSet().toList(),
      tags: _tags(j['tags']),
      office: j['office'] == true,
      cook: cookWayOf(j['cook']) ?? CookWay.home,
      order: o is String && o.trim().isNotEmpty ? _cut(o, maxOrderTextLength) : null,
    );
  }

  @override
  bool operator ==(Object other) => other is PlanInfo && jsonEncode(toJson()) == jsonEncode(other.toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

List<String> _tags(Object? v) {
  final out = <String>[];
  for (final t in (v is List ? v : const [])) {
    if (t is! String) continue;
    final n = normTag(t);
    if (n.isEmpty || n.length > maxTagLength || out.any((x) => sameTag(x, n))) continue;
    out.add(n);
    if (out.length == maxPlanTags) break;
  }
  return out;
}

String _cut(String s, int max) {
  final t = s.trim();
  return t.length <= max ? t : t.substring(0, max);
}

/// Τα στοιχεία για το πρόγραμμα του φαγητού [d], αν έχει.
PlanInfo? planInfoOf(Dish d) => PlanInfo.fromJson(d.extra['plan']);

/// Το φαγητό [d] με τα στοιχεία [p] (ή χωρίς, αν null).
Dish withPlanInfo(Dish d, PlanInfo? p) => withExtra(d, 'plan', p?.toJson());

/// 19/11: «Μου άρεσε» (1), «Δεν μου άρεσε» (-1) ή τίποτα (0), στο κλειδί «rate» του φαγητού ([Dish.extra]). Φαγητό με
/// «Δεν μου άρεσε» δεν μπαίνει ποτέ σε πρόγραμμα (κανόνες ή AI)· το «Μου άρεσε» προτιμάται.
int dishRating(Dish d) => switch (d.extra['rate']) {
      1 => 1,
      -1 => -1,
      _ => 0,
    };

Dish withRating(Dish d, int r) => withExtra(d, 'rate', r == 1 || r == -1 ? r : null);

/// Τα φαγητά της βιβλιοθήκης (όσα ήρθαν με επικόλληση και έχουν κλειδί).
List<Dish> libraryDishes(Iterable<Dish> all) => [for (final d in all) if (planInfoOf(d)?.key != null) d];

// ---------------------------------------------------------------------------
// Η επικόλληση
// ---------------------------------------------------------------------------

/// Ένα φαγητό όπως διαβάστηκε από την επικόλληση (πριν τον έλεγχο με τη βάση).
class LibraryEntry {
  const LibraryEntry({required this.key, required this.name, required this.plan, this.recipe, this.errors = const []});
  final String key;

  /// Το όνομα για τα μηνύματα (ή «φαγητό 3», αν δεν έχει).
  final String name;
  final PlanInfo plan;
  final PastedRecipe? recipe;
  final List<String> errors;
}

class LibraryParse {
  const LibraryParse(this.entries, this.errors);
  final List<LibraryEntry> entries;

  /// Προβλήματα όλης της επικόλλησης (όχι ενός φαγητού): τότε δεν περνά τίποτα.
  final List<String> errors;
}

/// Διαβάζει μια βιβλιοθήκη από ό,τι επικόλλησες (όλο το μήνυμα του βοηθού).
LibraryParse parseLibrary(String text) {
  if (!text.contains('{')) {
    return const LibraryParse([], ['Δεν βρέθηκαν φαγητά στο κείμενο. Αντίγραψε ολόκληρη την απάντηση του βοηθού.']);
  }
  final j = jsonOfKind(text, libraryKind);
  if (j == null && text.contains(libraryPromptTitle)) {
    return const LibraryParse([], [
      'Αυτές είναι οι οδηγίες που αντιγράφηκαν, όχι η απάντηση. Επικόλλησέ τες στο AI, και μετά αντίγραψε την απάντησή του.'
    ]);
  }
  if (j == null) {
    return const LibraryParse([], [
      'Το κείμενο δεν είναι βιβλιοθήκη της εφαρμογής, ή αντιγράφηκε μισό. Αντίγραψε ολόκληρη την απάντηση· αν ξαναβγεί, ζήτα '
          'από τον βοηθό να τη γράψει ξανά στη μορφή των οδηγιών.'
    ]);
  }
  final list = j['dishes'];
  if (list is! List || list.isEmpty) return const LibraryParse([], ['Η βιβλιοθήκη δεν έχει φαγητά («dishes»).']);
  if (list.length > maxLibraryDishes) {
    return LibraryParse(const [], ['Πολλά φαγητά (${list.length}): το πολύ $maxLibraryDishes σε μία επικόλληση.']);
  }
  final out = <LibraryEntry>[];
  final keys = <String>{};
  for (var k = 0; k < list.length; k++) {
    final x = list[k];
    if (x is! Map<String, dynamic>) {
      out.add(LibraryEntry(key: '', name: 'Φαγητό ${k + 1}', plan: const PlanInfo(), errors: const ['Δεν διαβάζεται.']));
      continue;
    }
    final errors = <String>[];
    final rawName = x['name'] is String ? (x['name'] as String).trim() : '';
    final name = rawName.isEmpty ? 'Φαγητό ${k + 1}' : _cut(rawName, maxDishNameLength);
    final key = x['key'] is String ? (x['key'] as String).trim() : '';
    if (key.isEmpty) {
      errors.add('Λείπει το «key».');
    } else if (key.length > maxLibraryKeyLength || !_keyPattern.hasMatch(key)) {
      errors.add('Το «key» θέλει μόνο λατινικά μικρά, αριθμούς, «-» και «_» (ως $maxLibraryKeyLength χαρακτήρες).');
    } else if (!keys.add(key)) {
      errors.add('Το «key» «$key» υπάρχει δύο φορές.');
    }
    final cook = x.containsKey('cook') ? cookWayOf(x['cook']) : CookWay.home;
    if (cook == null) errors.add('Το «cook» πρέπει να είναι "home", "none" ή "out".');
    final meals = <Meal>[];
    for (final m in (x['meals'] is List ? x['meals'] as List : const [])) {
      final mm = mealOfName(m);
      if (mm == null) {
        errors.add('Άγνωστο γεύμα «$m» (breakfast, lunch, dinner, snack).');
      } else if (!meals.contains(mm)) {
        meals.add(mm);
      }
    }
    final o = x['order'];
    final plan = PlanInfo(
      key: errors.isEmpty ? key : null,
      meals: meals,
      tags: _tags(x['tags']),
      office: x['office'] == true,
      cook: cook ?? CookWay.home,
      order: o is String && o.trim().isNotEmpty ? _cut(o, maxOrderTextLength) : null,
    );
    if (plan.cook == CookWay.out && plan.order == null) errors.add('Φαγητό παραγγελίας χωρίς «order» (τι να ζητήσω).');
    final r = parseRecipeObject(x, needSteps: plan.cook == CookWay.home);
    errors.addAll(r.errors);
    out.add(LibraryEntry(key: key, name: name, plan: plan, recipe: errors.isEmpty ? r.recipe : null, errors: errors));
  }
  return LibraryParse(out, const []);
}

/// Ένα φαγητό που δεν περνά, με τα προβλήματά του.
typedef LibraryProblem = ({String key, String name, List<String> errors});

/// Τι θα γίνει με την επικόλληση: νέα φαγητά, αλλαγμένα, ίδια, και όσα έχουν πρόβλημα (αυτά δεν περνούν).
class LibraryImport {
  const LibraryImport({this.added = const [], this.updated = const [], this.unchanged = 0, this.problems = const []});
  final List<Dish> added;
  final List<Dish> updated;
  final int unchanged;
  final List<LibraryProblem> problems;

  List<Dish> get changes => [...added, ...updated];
}

/// Ταιριάζει το όνομα που έγραψε ο βοηθός με το τρόφιμο του id; Αρκεί μία λέξη (3+ γράμματα) του ονόματος να είναι, με ή
/// χωρίς κατάληξη, λέξη του τροφίμου. Χαλαρό σκόπιμα: πιάνει το λάθος id («Φακές» → «Ρύζι»), όχι τις διατυπώσεις.
bool itemNameMatches(String given, String foodName) {
  List<String> words(String s) => phonetic(s).split(RegExp(r'[^a-z0-9]+')).where((w) => w.length >= 3).toList();
  final g = words(given), f = words(foodName);
  if (g.isEmpty) return true;
  final fs = [for (final w in f) stem(w)];
  for (final w in g) {
    final sw = stem(w);
    if (fs.contains(sw) || f.any((x) => x.startsWith(sw)) || fs.any((x) => x.length >= 3 && sw.startsWith(x))) return true;
  }
  return false;
}

/// Ελέγχει την επικόλληση [p] με τη βάση και ετοιμάζει τα φαγητά. [existing]: τα φαγητά μου (ίδιο κλειδί = αλλαγή).
/// [food]: το τρόφιμο ενός id (βάση ή δικά μου), ή null. [now]: ms. [newId]: νέο id φαγητού.
LibraryImport planLibraryImport(
  LibraryParse p, {
  required List<Dish> existing,
  required Food? Function(String id) food,
  required FoodLikes likes,
  required int now,
  required String Function() newId,
}) {
  final byKey = <String, Dish>{
    for (final d in existing)
      if (planInfoOf(d)?.key case final k?) k: d,
  };
  final added = <Dish>[], updated = <Dish>[];
  final problems = <LibraryProblem>[];
  var unchanged = 0;
  for (final e in p.entries) {
    final r = e.recipe;
    if (r == null || e.errors.isNotEmpty) {
      problems.add((key: e.key, name: e.name, errors: e.errors));
      continue;
    }
    final errors = <String>[];
    final items = <DishItem>[];
    for (final i in r.items) {
      final id = i.id;
      final f = id == null ? null : food(id);
      if (id == null) {
        errors.add('«${i.name}»: λείπει το id.');
      } else if (f == null) {
        errors.add('«${i.name}»: δεν υπάρχει τρόφιμο με id $id.');
      } else if (!itemNameMatches(i.name, f.name)) {
        errors.add('Το id $id είναι «${f.name}», όχι «${i.name}».');
      } else if (likes.dislike.contains(f.id)) {
        errors.add('«${f.name}» είναι στα «Δε μου αρέσει».');
      } else if (f.isCooked && e.plan.cook != CookWay.out) {
        errors.add(f.rawId != null
            ? '«${f.name}» είναι μαγειρεμένη μορφή: γράψε την ωμή (${f.rawId}), ζυγισμένη ωμή.'
            : '«${f.name}» υπάρχει στη βάση μόνο μαγειρεμένο: διάλεξε ωμό υλικό, ζυγισμένο ωμό.');
      } else {
        items.add(DishItem(f.id, f.name, i.amount));
      }
    }
    if (errors.isNotEmpty) {
      problems.add((key: e.key, name: e.name, errors: errors));
      continue;
    }
    final recipeJson = r.recipe.isEmpty ? null : r.recipe.toJson();
    final old = byKey[e.key];
    if (old == null) {
      added.add(Dish(
        id: newId(),
        name: r.name,
        kind: r.kind,
        items: items,
        servings: r.kind == DishKind.portions ? r.servings : 1,
        created: now,
        extra: {'plan': e.plan.toJson(), if (recipeJson != null) 'recipe': recipeJson},
      ));
      continue;
    }
    final servings = r.kind == DishKind.portions ? r.servings : 1;
    final sameItems = old.items.length == items.length &&
        [for (var k = 0; k < items.length; k++) old.items[k].id == items[k].id && old.items[k].amount == items[k].amount]
            .every((x) => x);
    final same = sameItems &&
        old.name == r.name &&
        old.kind == r.kind &&
        old.servings == servings &&
        jsonEncode(old.extra['recipe']) == jsonEncode(recipeJson) &&
        planInfoOf(old) == e.plan;
    if (same) {
      unchanged++;
      continue;
    }
    final kindChanged = old.kind != r.kind;
    updated.add(Dish(
      id: old.id,
      name: r.name,
      kind: r.kind,
      items: items,
      servings: servings,
      // Όπως στην αλλαγή φαγητού: το τελευταίο μαγείρεμα μένει (είναι ό,τι έχεις στο ψυγείο), εκτός αν άλλαξε το είδος.
      batch: kindChanged ? null : old.batch,
      lastPlate: !kindChanged && sameItems ? old.lastPlate : null,
      lastQty: kindChanged || (old.kind == DishKind.portions && old.servings != servings) ? null : old.lastQty,
      created: old.created,
      used: old.used,
      uses: old.uses,
      extra: {
        for (final x in old.extra.entries)
          if (x.key != 'plan' && x.key != 'recipe') x.key: x.value,
        'plan': e.plan.toJson(),
        if (recipeJson != null) 'recipe': recipeJson,
      },
    ));
  }
  return LibraryImport(added: added, updated: updated, unchanged: unchanged, problems: problems);
}

/// Τα προβλήματα ως κείμενο για τον βοηθό, ώστε να στείλει διορθωμένα μόνο αυτά τα φαγητά.
String libraryProblemsText(List<LibraryProblem> problems) {
  final b = StringBuffer()
    ..writeln('Η εφαρμογή «Υγεία & Φόρμα» δεν πέρασε αυτά τα φαγητά της βιβλιοθήκης. Διόρθωσέ τα και στείλε ξανά ΜΟΝΟ αυτά, '
        'στην ίδια μορφή ("kind": "$libraryKind"), με τα ίδια "key":')
    ..writeln();
  for (final p in problems) {
    b.writeln('- ${p.name}${p.key.isEmpty ? '' : ' (key: ${p.key})'}:');
    for (final e in p.errors) {
      b.writeln('  · $e');
    }
  }
  return b.toString();
}

// ---------------------------------------------------------------------------
// Οδηγίες για τον βοηθό
// ---------------------------------------------------------------------------

/// Το κείμενο που αντιγράφεται για τον βοηθό AI. [existing]: τα φαγητά της βιβλιοθήκης που υπάρχουν ήδη (κλειδί και
/// όνομα), ώστε μια διόρθωση να κρατήσει το ίδιο κλειδί.
String libraryPrompt({
  required List<Food> foods,
  required FoodLikes likes,
  required Kitchen kitchen,
  RecipeTargets? targets,
  List<Dish> existing = const [],
}) {
  final byId = {for (final f in foods) f.id: f};
  String names(List<String> ids) => [for (final id in ids) if (byId[id] case final f?) '${f.id} ${f.name}'].join('; ');
  final devices = [
    for (final d in kitchenDevices)
      if (kitchen.has(d.$1)) d.$2,
  ];
  final b = StringBuffer()
    ..writeln(libraryPromptTitle)
    ..writeln()
    ..writeln('Γράψε φαγητά για τη βιβλιοθήκη της εφαρμογής μου, από την οποία φτιάχνεται το εβδομαδιαίο μου πρόγραμμα. '
        'Ποια φαγητά, θα σου τα πω στη συζήτησή μας.')
    ..writeln()
    ..writeln('Κανόνες:')
    ..writeln('1. Μόνο τρόφιμα από τις λίστες «ΤΡΟΦΙΜΑ» πιο κάτω, με το id ΚΑΙ το όνομά τους ακριβώς όπως είναι. Αν κάτι '
        'λείπει, διάλεξε το πιο κοντινό ή άφησέ το έξω. Νερό δεν γράφεται ως υλικό.')
    ..writeln('2. Ποσότητες σε γραμμάρια (ml για όσα η λίστα γράφει «ml»), ΩΜΑ, όπως ζυγίζονται πριν το μαγείρεμα. Λάδι, '
        'αλάτι και μπαχαρικά είναι υλικά σε γραμμάρια· στα βήματα γράψε και την ποσότητα με κουτάλι (π.χ. «½ κουταλάκι '
        'αλάτι, περίπου 3 g»).')
    ..writeln('3. Ποτέ τρόφιμα από τα «ΔΕ ΜΟΥ ΑΡΕΣΟΥΝ». ΜΗ γράψεις θερμίδες ή θρεπτικά: τα μετρά η εφαρμογή από τη βάση.')
    ..writeln('4. «cook»: "home" = μαγειρεύεται στο σπίτι (θέλει "steps": συσκευή, φωτιά, λεπτά, πότε μπαίνει κάθε υλικό)· '
        '"none" = χωρίς μαγείρεμα (π.χ. φρυγανιές με cottage και φρούτο· χωρίς βήματα)· "out" = παραγγελία (θέλει '
        '"order": τι να ζητήσω, π.χ. ψήσιμο, λάδι στο πλάι, συνοδευτικό· τα υλικά είναι εκτίμηση του πιάτου που έρχεται, και '
        'εδώ επιτρέπονται και οι μαγειρεμένες μορφές της λίστας «ΜΑΓΕΙΡΕΜΕΝΑ»).')
    ..writeln('5. «type»: "plate" = ένα πιάτο μόνο για μένα· "portions" = ίσες μερίδες (γράψε "servings")· "pot" = κατσαρόλα '
        'ή ταψί για όλους, από όπου τρώω όσο ζυγίσω (γράψε στο "servings" περίπου πόσες μερίδες βγάζει).')
    ..writeln('6. «meals»: σε ποια γεύματα ταιριάζει ("lunch" μεσημέρι, "dinner" βράδυ, "snack" σνακ, "breakfast" πρωινό). '
        '«office»: true αν ταιριάζει για μεσημεριανό στο γραφείο. «tags»: ετικέτες για τους κανόνες του προγράμματος· '
        'χρησιμοποίησε αυτές όπου ταιριάζουν: ${standardTags.join(', ')}.')
    ..writeln('7. «key»: σταθερό κλειδί κάθε φαγητού, μόνο λατινικά μικρά, αριθμοί, «-» (π.χ. "fakes-kokkinistes"). Για να '
        'αλλάξεις ένα φαγητό που υπάρχει, κράτα το ίδιο key.')
    ..writeln('8. Απάντησε με ΕΝΑ μπλοκ JSON σε αυτή ακριβώς τη μορφή (τα κείμενα στα ελληνικά). Στη θέση του «…» βάλε όλα τα '
        'φαγητά, τα υλικά και τα βήματα:')
    ..writeln('```json')
    ..writeln('{')
    ..writeln('  "kind": "$libraryKind",')
    ..writeln('  "dishes": [')
    ..writeln('    {')
    ..writeln('      "key": "fakes-kokkinistes",')
    ..writeln('      "name": "Φακές κοκκινιστές",')
    ..writeln('      "cook": "home", "type": "pot", "servings": 4, "minutes": 45,')
    ..writeln('      "meals": ["lunch", "dinner"], "office": true, "tags": ["όσπρια"],')
    ..writeln('      "items": [{"id": "C20359", "name": "Φακές (ξερές)", "g": 250}, …],')
    ..writeln('      "steps": [{"text": "…", "device": "Κατσαρόλα μεγάλη", "heat": "μέτρια", "min": 30}, …],')
    ..writeln('      "tips": ["…"], "keeps": "Στο ψυγείο ως 2 μέρες (με ρύζι: ως την επόμενη μέρα)", "why": "…"')
    ..writeln('    },')
    ..writeln('    {"key": "tsipoura-psitopoleio", "name": "Τσιπούρα από ψητοπωλείο", "cook": "out", "type": "plate", '
        '"meals": ["dinner"], "tags": ["ψάρι"], "order": "…", "items": […]},')
    ..writeln('    …')
    ..writeln('  ]')
    ..writeln('}')
    ..writeln('```')
    ..writeln();
  if (targets != null) {
    b.writeln('ΟΙ ΣΤΟΧΟΙ ΜΟΥ ΑΝΑ ΜΕΡΑ: ${thousands(targets.kcal)} kcal · πρωτεΐνη ${targets.protein} g · κορεσμένα έως '
        '${targets.satMax} g · ίνες τουλάχιστον ${targets.fiber} g · αλάτι κάτω από ${targets.salt.toStringAsFixed(0)} g.');
  }
  b
    ..writeln('ΚΟΥΖΙΝΑ: ${devices.isEmpty ? 'μάτια κουζίνας, φούρνος, κατσαρόλες, τηγάνια' : devices.join(', ')}'
        '${kitchen.cookware.isEmpty ? '' : '. Σκεύη: ${kitchen.cookware.map((c) => c.label).join(', ')}'}')
    ..writeln('ΜΟΥ ΑΡΕΣΟΥΝ: ${likes.like.isEmpty ? '—' : names(likes.like)}')
    ..writeln('ΔΕ ΜΟΥ ΑΡΕΣΟΥΝ: ${likes.dislike.isEmpty ? '—' : names(likes.dislike)}');
  if (likes.note.trim().isNotEmpty) b.writeln('ΣΗΜΕΙΩΣΕΙΣ: ${likes.note.trim()}');
  final lib = libraryDishes(existing);
  if (lib.isNotEmpty) {
    b
      ..writeln()
      ..writeln('ΥΠΑΡΧΟΥΝ ΗΔΗ ΣΤΗ ΒΙΒΛΙΟΘΗΚΗ (key: όνομα): '
          '${[for (final d in lib) '${planInfoOf(d)!.key}: ${d.name}'].join('; ')}');
  }
  b
    ..writeln()
    ..writeln('ΤΡΟΦΙΜΑ (id όνομα), ωμά, ανά κατηγορία:');
  for (final line in rawFoodLines(foods, likes)) {
    b.writeln(line);
  }
  b
    ..writeln()
    ..writeln('ΜΑΓΕΙΡΕΜΕΝΑ (id όνομα), ΜΟΝΟ για "cook": "out":');
  for (final line in rawFoodLines(foods, likes, cooked: true)) {
    b.writeln(line);
  }
  return b.toString();
}
