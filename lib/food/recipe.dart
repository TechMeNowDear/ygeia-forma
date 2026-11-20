/// Συνταγές με επικόλληση (15/11, βήμα 2): η εφαρμογή αντιγράφει οδηγίες για έναν βοηθό AI (μορφή, τρόφιμα της βάσης με
/// το id τους, κουζίνα, προτιμήσεις, στόχοι), ο βοηθός γράφει τη συνταγή, και η επικόλληση γίνεται φαγητό.
///
/// Κανόνες (έγγραφο προδιαγραφών › «Διατροφή: Τα φαγητά μου και συνταγές»):
/// - Ο βοηθός δίνει ΜΟΝΟ υλικά (id της βάσης) με ωμά γραμμάρια, βήματα και συμβουλές. Θερμίδες και θρεπτικά τα μετρά
///   πάντα η εφαρμογή από τη βάση· ό,τι αριθμό θρεπτικού γράψει ο βοηθός, αγνοείται.
/// - Υλικό με id που δεν υπάρχει στη βάση: η εφαρμογή ψάχνει το όνομά του και το δείχνει ως «βρέθηκε ως …» για έλεγχο·
///   αν δεν βρεθεί, η συνταγή δεν αποθηκεύεται ώσπου να διαλέξεις υλικό ή να το βγάλεις.
/// - Υλικό από τα «Δε μου αρέσει»: φαίνεται έντονα· η συνταγή αποθηκεύεται μόνο αν το αλλάξεις ή το βγάλεις.
library;

import 'dart:convert';

import '../format.dart' show thousands;
import 'dishes.dart';
import 'food_model.dart';
import 'food_search.dart' show phonetic;
import 'kitchen.dart';

const recipeKind = 'ygeia-recipe';

/// Η πρώτη γραμμή των οδηγιών: αν επικολληθούν οι ίδιες οι οδηγίες (αντί για την απάντηση), το λέμε.
const recipePromptTitle = 'ΣΥΝΤΑΓΗ ΓΙΑ ΤΗΝ ΕΦΑΡΜΟΓΗ «ΥΓΕΙΑ & ΦΟΡΜΑ»';
const likesKind = 'ygeia-likes';

/// Όρια μιας συνταγής που επικολλάται (ώστε ένα λάθος κείμενο να μη φτιάχνει παράλογα φαγητά).
const maxRecipeSteps = 30;
const maxRecipeTextLength = 600;
const maxRecipeMinutes = 24 * 60;

/// Ένα βήμα: τι κάνεις, με ποια συσκευή, σε πόση φωτιά/θερμοκρασία, για πόσα λεπτά.
class RecipeStep {
  const RecipeStep({required this.text, this.device, this.heat, this.minutes});
  final String text;
  final String? device;
  final String? heat;
  final int? minutes;

  Map<String, Object> toJson() =>
      {'text': text, if (device != null) 'device': device!, if (heat != null) 'heat': heat!, if (minutes != null) 'min': minutes!};

  static RecipeStep? fromJson(Object? j) {
    if (j is String) return j.trim().isEmpty ? null : RecipeStep(text: _cut(j));
    if (j is! Map) return null;
    final t = j['text'];
    if (t is! String || t.trim().isEmpty) return null;
    String? s(Object? v) => v is String && v.trim().isNotEmpty ? _cut(v, 80) : null;
    final m = j['min'];
    return RecipeStep(
      text: _cut(t),
      device: s(j['device']),
      heat: s(j['heat']),
      minutes: m is num && m.isFinite && m > 0 && m <= maxRecipeMinutes ? m.round() : null,
    );
  }
}

String _cut(String s, [int max = maxRecipeTextLength]) {
  final t = s.trim();
  return t.length <= max ? t : t.substring(0, max);
}

/// Η συνταγή ενός φαγητού (βήματα, συμβουλές, χρόνος, πόσο κρατά). Αποθηκεύεται μέσα στο φαγητό (κλειδί «recipe»).
class Recipe {
  const Recipe({this.steps = const [], this.tips = const [], this.minutes, this.keeps, this.why, this.servings});
  final List<RecipeStep> steps;
  final List<String> tips;
  final int? minutes;
  final String? keeps;

  /// Περίπου πόσες μερίδες βγάζει (κατσαρόλα: εκτίμηση του βοηθού, μόνο για να φανεί «μία μερίδα περίπου»).
  final int? servings;

  /// Λίγες γραμμές του βοηθού για το γιατί ταιριάζει στους στόχους (κείμενο, όχι αριθμοί).
  final String? why;

  bool get isEmpty => steps.isEmpty && tips.isEmpty && keeps == null && why == null;

  Map<String, Object> toJson() => {
        'steps': [for (final s in steps) s.toJson()],
        if (tips.isNotEmpty) 'tips': tips,
        if (minutes != null) 'min': minutes!,
        if (keeps != null) 'keeps': keeps!,
        if (why != null) 'why': why!,
        if (servings != null) 'serv': servings!,
      };

  static Recipe? fromJson(Object? j) {
    if (j is! Map) return null;
    final steps = <RecipeStep>[
      for (final s in (j['steps'] is List ? j['steps'] as List : const []).take(maxRecipeSteps))
        if (RecipeStep.fromJson(s) case final st?) st,
    ];
    final tips = <String>[
      for (final t in (j['tips'] is List ? j['tips'] as List : const []).take(10))
        if (t is String && t.trim().isNotEmpty) _cut(t),
    ];
    final m = j['min'] ?? j['minutes'];
    final sv = j['serv'] ?? j['servings'];
    String? s(Object? v) => v is String && v.trim().isNotEmpty ? _cut(v) : null;
    final r = Recipe(
      steps: steps,
      tips: tips,
      minutes: m is num && m.isFinite && m > 0 && m <= maxRecipeMinutes ? m.round() : null,
      keeps: s(j['keeps']),
      why: s(j['why']),
      servings: sv is num && sv.isFinite && sv >= 1 && sv <= maxDishServings ? sv.round() : null,
    );
    return r.isEmpty ? null : r;
  }
}

/// Η συνταγή του φαγητού [d], αν έχει.
Recipe? recipeOf(Dish d) => Recipe.fromJson(d.extra['recipe']);

/// Το φαγητό [d] με τη συνταγή [r] (ή χωρίς, αν null).
Dish withRecipe(Dish d, Recipe? r) => withExtra(d, 'recipe', r?.toJson());

// ---------------------------------------------------------------------------
// Η επικόλληση
// ---------------------------------------------------------------------------

/// Ένα υλικό όπως ήρθε από τον βοηθό.
class PastedItem {
  const PastedItem({required this.id, required this.name, required this.amount});
  final String? id;
  final String name;
  final double amount;
}

/// Η συνταγή όπως διαβάστηκε (πριν αντιστοιχιστούν τα υλικά στη βάση).
class PastedRecipe {
  const PastedRecipe({
    required this.name,
    required this.kind,
    required this.servings,
    required this.items,
    required this.recipe,
  });
  final String name;
  final DishKind kind;

  /// Πόσες μερίδες βγάζει (ίσες μερίδες· και ως εκτίμηση για την κατσαρόλα). 1 στο πιάτο.
  final int servings;
  final List<PastedItem> items;
  final Recipe recipe;
}

/// Αποτέλεσμα της επικόλλησης: η συνταγή, ή τα προβλήματα (για τον χρήστη).
class RecipeParse {
  const RecipeParse(this.recipe, this.errors);
  final PastedRecipe? recipe;
  final List<String> errors;
  bool get ok => recipe != null && errors.isEmpty;
}

/// Το πρώτο αντικείμενο JSON μέσα στο κείμενο με «kind» = [kind]: πρώτα μέσα σε ```…```, μετά κάθε «{» ως το «}» που το
/// κλείνει (με τα εισαγωγικά). Ίδιος κανόνας με την επικόλληση προγράμματος.
Map<String, dynamic>? jsonOfKind(String text, String kind) {
  Map<String, dynamic>? tryDecode(String t) {
    try {
      final j = jsonDecode(t);
      return j is Map<String, dynamic> && j['kind'] == kind ? j : null;
    } on FormatException {
      return null;
    }
  }

  for (final m in RegExp(r'```(?:json)?\s*\n([\s\S]*?)```').allMatches(text)) {
    final j = tryDecode(m.group(1)!.trim());
    if (j != null) return j;
  }
  for (var a = text.indexOf('{'); a >= 0; a = text.indexOf('{', a + 1)) {
    var depth = 0;
    var inStr = false, esc = false;
    for (var i = a; i < text.length; i++) {
      final ch = text[i];
      if (inStr) {
        if (esc) {
          esc = false;
        } else if (ch == r'\') {
          esc = true;
        } else if (ch == '"') {
          inStr = false;
        }
        continue;
      }
      if (ch == '"') {
        inStr = true;
      } else if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) {
          final j = tryDecode(text.substring(a, i + 1));
          if (j != null) return j;
          break;
        }
      }
    }
  }
  return null;
}

/// Διαβάζει μια συνταγή από ό,τι επικόλλησες (όλο το μήνυμα του βοηθού).
RecipeParse parseRecipe(String text) {
  if (!text.contains('{')) {
    return const RecipeParse(null, ['Δεν βρέθηκε συνταγή στο κείμενο. Αντίγραψε ολόκληρη την απάντηση του βοηθού.']);
  }
  final j = jsonOfKind(text, recipeKind);
  if (j == null && text.contains(recipePromptTitle)) {
    return const RecipeParse(null, [
      'Αυτές είναι οι οδηγίες που αντιγράφηκαν, όχι η απάντηση. Επικόλλησέ τες στο AI, και μετά αντίγραψε την απάντησή του.'
    ]);
  }
  if (j == null) {
    return const RecipeParse(null, [
      'Το κείμενο δεν είναι συνταγή της εφαρμογής, ή αντιγράφηκε μισό. Αντίγραψε ολόκληρη την απάντηση· αν ξαναβγεί, ζήτα '
          'από τον βοηθό να τη γράψει ξανά στη μορφή των οδηγιών.'
    ]);
  }
  return parseRecipeObject(j);
}

/// Μία συνταγή από ένα αντικείμενο JSON (της επικόλλησης μίας συνταγής ή ενός φαγητού της βιβλιοθήκης). [needSteps]:
/// χωρίς βήματα δεν γίνεται δεκτή (φαγητό χωρίς μαγείρεμα, π.χ. φρούτο με φρυγανιά, δεν χρειάζεται βήματα).
RecipeParse parseRecipeObject(Map<String, dynamic> j, {bool needSteps = true}) {
  final errors = <String>[];
  final name = j['name'] is String ? _cut(j['name'] as String, maxDishNameLength) : '';
  if (name.isEmpty) errors.add('Η συνταγή δεν έχει όνομα.');
  final kind = dishKindOf(j['type']) ?? DishKind.pot;
  final sv = j['servings'];
  final servings = sv is num && sv.isFinite && sv >= 1 && sv <= maxDishServings ? sv.round() : (kind == DishKind.plate ? 1 : 0);
  if (kind == DishKind.portions && servings < 1) errors.add('Λείπει πόσες μερίδες βγάζει («servings», 1–$maxDishServings).');
  final items = parsePastedItems(j['items'] is List ? j['items'] as List : const [], errors);
  if (items.isEmpty && errors.isEmpty) errors.add('Η συνταγή δεν έχει υλικά.');
  if (items.length > maxDishItems) errors.add('Πολλά υλικά (${items.length}): το πολύ $maxDishItems.');
  final recipe = Recipe.fromJson({...j, 'min': j['minutes'] ?? j['min']}) ?? const Recipe();
  if (needSteps && recipe.steps.isEmpty) errors.add('Η συνταγή δεν έχει βήματα.');
  return RecipeParse(
    errors.isEmpty
        ? PastedRecipe(
            name: name,
            kind: kind,
            servings: kind == DishKind.plate ? 1 : (servings < 1 ? 1 : servings),
            items: items,
            recipe: recipe,
          )
        : null,
    errors,
  );
}

/// Τα υλικά όπως ήρθαν (id, όνομα, γραμμάρια). Ό,τι δεν στέκει γράφεται στο [errors] και δεν μπαίνει.
List<PastedItem> parsePastedItems(List rawItems, List<String> errors) {
  final items = <PastedItem>[];
  for (var k = 0; k < rawItems.length; k++) {
    final x = rawItems[k];
    if (x is! Map) {
      errors.add('Το υλικό ${k + 1} δεν διαβάζεται.');
      continue;
    }
    final g = x['g'] ?? x['grams'];
    final n = x['name'] is String ? (x['name'] as String).trim() : '';
    final id = x['id'] is String && (x['id'] as String).trim().isNotEmpty ? (x['id'] as String).trim() : null;
    if (g is! num || !g.isFinite || g <= 0 || g > maxEntryGrams) {
      errors.add('«${n.isEmpty ? (id ?? 'υλικό ${k + 1}') : n}»: η ποσότητα πρέπει να είναι γραμμάρια από 0 ως ${thousands(maxEntryGrams)}.');
      continue;
    }
    if (id == null && n.isEmpty) {
      errors.add('Το υλικό ${k + 1} δεν έχει όνομα.');
      continue;
    }
    items.add(PastedItem(id: id, name: n.isEmpty ? id! : n, amount: roundAmount(g.toDouble())));
  }
  return items;
}

/// Πώς αντιστοιχίστηκε ένα υλικό στη βάση.
enum ItemMatch {
  /// Με το id του (όπως έπρεπε).
  exact,

  /// Το id δεν υπάρχει· βρέθηκε από το όνομα: θέλει έλεγχο.
  byName,

  /// Δεν βρέθηκε: θέλει επιλογή ή αφαίρεση.
  missing,
}

// ---------------------------------------------------------------------------
// «Τι μου αρέσει»
// ---------------------------------------------------------------------------

/// Τα τρόφιμα που μου αρέσουν και δε μου αρέσουν (id της βάσης ή δικών μου), και ελεύθερες σημειώσεις (π.χ. «γρήγορα φαγητά
/// τις καθημερινές»). Μπαίνουν στις οδηγίες για τον βοηθό· τα «δε μου αρέσει» ελέγχονται και στην επικόλληση.
class FoodLikes {
  const FoodLikes({this.like = const [], this.dislike = const [], this.note = '', this.staple = const []});
  final List<String> like;
  final List<String> dislike;
  final String note;

  /// 19/11 (AI φαγητού): «Βασικά κουζίνας» που εγκρίνεις μία φορά (λάδι, αλάτι, μπαχαρικά, κρεμμύδι…). Μαζί με τα
  /// [like] είναι τα ΜΟΝΑ υλικά που επιτρέπονται στις συνταγές του AI ([aiAllowedIds]). Ποτέ ταυτόχρονα και στα [dislike].
  final List<String> staple;

  bool get isEmpty => like.isEmpty && dislike.isEmpty && note.trim().isEmpty && staple.isEmpty;

  Map<String, Object> toJson() => {
        'like': like,
        'dislike': dislike,
        if (note.trim().isNotEmpty) 'note': note.trim(),
        if (staple.isNotEmpty) 'staple': staple,
      };

  static FoodLikes fromJson(Object? j) {
    if (j is! Map) return const FoodLikes();
    List<String> ids(Object? v) => [
          for (final x in (v is List ? v : const []))
            if (x is String && x.isNotEmpty) x,
        ].toSet().toList();
    final dislike = ids(j['dislike']);
    return FoodLikes(
      like: [for (final x in ids(j['like'])) if (!dislike.contains(x)) x],
      dislike: dislike,
      note: j['note'] is String ? _cut(j['note'] as String, 1000) : '',
      staple: [for (final x in ids(j['staple'])) if (!dislike.contains(x)) x],
    );
  }

  FoodLikes copyWith({List<String>? like, List<String>? dislike, String? note, List<String>? staple}) => FoodLikes(
      like: like ?? this.like, dislike: dislike ?? this.dislike, note: note ?? this.note, staple: staple ?? this.staple);

  /// Με τα id όπως είναι σήμερα στη βάση (αντικατεστημένα τρόφιμα, έλεγχος 19/11, I-2), χωρίς διπλά· ό,τι είναι στα «Δε
  /// μου αρέσει» φεύγει από τα άλλα δύο.
  FoodLikes mapIds(String Function(String id) now) {
    List<String> m(List<String> xs) => [...{for (final x in xs) now(x)}];
    final dis = m(dislike);
    return FoodLikes(
      like: [for (final x in m(like)) if (!dis.contains(x)) x],
      dislike: dis,
      note: note,
      staple: [for (final x in m(staple)) if (!dis.contains(x)) x],
    );
  }
}

/// Επικόλληση προτιμήσεων («kind»: «ygeia-likes»): για να μπουν όλα μαζί την πρώτη φορά. Τα id που δεν υπάρχουν στη
/// βάση αγνοούνται (επιστρέφονται χωριστά, για να τα πει η οθόνη).
({FoodLikes likes, List<String> unknown})? parseLikes(String text, bool Function(String id) exists) {
  final j = jsonOfKind(text, likesKind);
  if (j == null) return null;
  final l = FoodLikes.fromJson(j);
  final unknown = [for (final id in [...l.like, ...l.dislike, ...l.staple]) if (!exists(id)) id];
  return (
    likes: l.copyWith(
      like: [for (final x in l.like) if (exists(x)) x],
      dislike: [for (final x in l.dislike) if (exists(x)) x],
      staple: [for (final x in l.staple) if (exists(x)) x],
    ),
    unknown: unknown,
  );
}

// ---------------------------------------------------------------------------
// Οδηγίες για τον βοηθό
// ---------------------------------------------------------------------------

/// Οι στόχοι της μέρας για τις οδηγίες (null = δεν έχουν οριστεί).
typedef RecipeTargets = ({int kcal, int protein, int satMax, int fiber, double salt});

/// Το κείμενο που αντιγράφεται για τον βοηθό AI. [wish]: τι θέλεις (ελεύθερο κείμενο). [foods]: τα τρόφιμα που επιτρέπονται
/// (βάση και δικά μου). [left]: τι μένει σήμερα, αν θες η συνταγή να χωράει.
String recipePrompt({
  required String wish,
  required List<Food> foods,
  required FoodLikes likes,
  required Kitchen kitchen,
  RecipeTargets? targets,
  ({int kcal, int protein})? left,
}) {
  final byId = {for (final f in foods) f.id: f};
  String names(List<String> ids) => [for (final id in ids) if (byId[id] case final f?) '${f.id} ${f.name}'].join('; ');
  final devices = [
    for (final d in kitchenDevices)
      if (kitchen.has(d.$1)) d.$2,
  ];
  final b = StringBuffer()
    ..writeln(recipePromptTitle)
    ..writeln()
    ..writeln('Τι θέλω: ${wish.trim().isEmpty ? 'μια υγιεινή, απλή συνταγή για μεσημεριανό ή βραδινό' : wish.trim()}')
    ..writeln()
    ..writeln('Κανόνες:')
    ..writeln('1. Μόνο τρόφιμα από τη λίστα «ΤΡΟΦΙΜΑ» πιο κάτω, με το id τους ακριβώς όπως είναι. Αν κάτι λείπει, διάλεξε το πιο '
        'κοντινό της λίστας ή άφησέ το έξω. Νερό και ζωμός από νερό δεν γράφονται ως υλικά.')
    ..writeln('2. Ποσότητες σε γραμμάρια (ml για όσα η λίστα γράφει «ml»), όπως ζυγίζονται ΩΜΑ, πριν το μαγείρεμα: ξερά όσπρια, '
        'ωμό ρύζι και ζυμαρικά, ωμό κρέας. Το λάδι μαγειρέματος είναι υλικό, μετρημένο σε γραμμάρια.')
    ..writeln('3. Ποτέ τρόφιμα από τα «ΔΕ ΜΟΥ ΑΡΕΣΟΥΝ». Προτίμησε όσα «ΜΟΥ ΑΡΕΣΟΥΝ».')
    ..writeln('4. Μόνο με τις συσκευές της «ΚΟΥΖΙΝΑΣ». Σε κάθε βήμα: συσκευή, φωτιά ή θερμοκρασία, και λεπτά. Ακριβείς οδηγίες, '
        'σαν για κάποιον που μαθαίνει να μαγειρεύει.')
    ..writeln('5. Υγιεινή συνταγή για τους στόχους μου: λίγα κορεσμένα, λίγο αλάτι, πολλές ίνες, αρκετή πρωτεΐνη, πολλά λαχανικά. '
        'ΜΗ γράψεις θερμίδες ή θρεπτικά: τα υπολογίζει η εφαρμογή από τη βάση της.')
    ..writeln('6. «type»: "plate" = ένα πιάτο για μένα· "portions" = ίσες μερίδες (π.χ. μπιφτέκια· γράψε "servings")· '
        '"pot" = κατσαρόλα ή ταψί από όπου τρώω όσο ζυγίσω (γράψε στο "servings" περίπου πόσες μερίδες βγάζει).')
    ..writeln('7. Απάντησε με ΕΝΑ μπλοκ JSON σε αυτή ακριβώς τη μορφή (τα ελληνικά κείμενα στα ελληνικά). Στη θέση του «…» '
        'βάλε όλα τα υλικά και όλα τα βήματα:')
    ..writeln('```json')
    ..writeln('{')
    ..writeln('  "kind": "$recipeKind",')
    ..writeln('  "name": "Φακές με καρότο και σέλινο",')
    ..writeln('  "type": "pot",')
    ..writeln('  "servings": 4,')
    ..writeln('  "minutes": 45,')
    ..writeln('  "items": [')
    ..writeln('    {"id": "C20359", "name": "Φακές (ξερές)", "g": 250},')
    ..writeln('    {"id": "C17270", "name": "Ελαιόλαδο εξαιρετικά παρθένο", "g": 20},')
    ..writeln('    …')
    ..writeln('  ],')
    ..writeln('  "steps": [')
    ..writeln('    {"text": "Ξέπλυνε τις φακές σε σουρωτήρι.", "device": "", "heat": "", "min": 2},')
    ..writeln('    {"text": "Βράσε τις φακές με 1,5 λίτρο νερό.", "device": "Κατσαρόλα μεγάλη", "heat": "δυνατή, μετά χαμηλή", "min": 30},')
    ..writeln('    …')
    ..writeln('  ],')
    ..writeln('  "tips": ["…"],')
    ..writeln('  "keeps": "Στο ψυγείο ως 3 μέρες",')
    ..writeln('  "why": "Μία-δύο προτάσεις: γιατί ταιριάζει στους στόχους μου."')
    ..writeln('}')
    ..writeln('```')
    ..writeln();
  if (targets != null) {
    b.writeln('ΟΙ ΣΤΟΧΟΙ ΜΟΥ ΑΝΑ ΜΕΡΑ: ${thousands(targets.kcal)} kcal · πρωτεΐνη ${targets.protein} g · κορεσμένα έως '
        '${targets.satMax} g · ίνες τουλάχιστον ${targets.fiber} g · αλάτι κάτω από ${targets.salt.toStringAsFixed(0)} g. '
        'Μία μερίδα για ένα γεύμα: περίπου το ένα τρίτο αυτών, εκτός αν γράφω αλλιώς στο «Τι θέλω».');
  }
  if (left != null && left.kcal > 0) {
    b.writeln('ΣΗΜΕΡΑ ΜΟΥ ΜΕΝΟΥΝ: ${thousands(left.kcal)} kcal και ${left.protein} g πρωτεΐνη. Αν η συνταγή είναι για σήμερα, η '
        'μερίδα μου να χωράει εδώ.');
  }
  b
    ..writeln()
    ..writeln('ΚΟΥΖΙΝΑ: ${devices.isEmpty ? 'μάτια κουζίνας, φούρνος, κατσαρόλες, τηγάνια' : devices.join(', ')}'
        '${kitchen.cookware.isEmpty ? '' : '. Σκεύη: ${kitchen.cookware.map((c) => c.label).join(', ')}'}')
    ..writeln()
    ..writeln('ΜΟΥ ΑΡΕΣΟΥΝ: ${likes.like.isEmpty ? '—' : names(likes.like)}')
    ..writeln('ΔΕ ΜΟΥ ΑΡΕΣΟΥΝ: ${likes.dislike.isEmpty ? '—' : names(likes.dislike)}');
  if (likes.note.trim().isNotEmpty) b.writeln('ΣΗΜΕΙΩΣΕΙΣ: ${likes.note.trim()}');
  b
    ..writeln()
    ..writeln('ΤΡΟΦΙΜΑ (id όνομα), ανά κατηγορία:');
  for (final line in rawFoodLines(foods, likes)) {
    b.writeln(line);
  }
  return b.toString();
}

/// Τα τρόφιμα για τις οδηγίες, μία γραμμή ανά κατηγορία («Κατηγορία: id όνομα; …»). Μόνο ωμές μορφές: οι συνταγές
/// ζυγίζονται ωμές. Έξω οι μαγειρεμένες μορφές ωμών τροφίμων (π.χ. «Φακές (βρασμένες)», που η βάση τις συνδέει με τις
/// ξερές) και όσα δε μου αρέσουν. [cooked]: αντί για τις ωμές, ΜΟΝΟ οι μαγειρεμένες μορφές (για φαγητά από παραγγελία).
/// [tail]: κάτι μετά το όνομα (π.χ. για το AI τα κορεσμένα και το αλάτι ανά 100 g, έλεγχος 20/11).
List<String> rawFoodLines(List<Food> foods, FoodLikes likes, {bool cooked = false, String Function(Food f)? tail}) {
  final byCat = <String, List<Food>>{};
  final cookedIds = {for (final f in foods) for (final c in f.cooked) c.$1};
  for (final f in foods) {
    if (likes.dislike.contains(f.id)) continue;
    final isCooked = f.isCooked || cookedIds.contains(f.id);
    if (isCooked != cooked) continue;
    byCat.putIfAbsent(f.cat.isEmpty ? 'Άλλα' : f.cat, () => []).add(f);
  }
  return [
    for (final e in byCat.entries)
      '${e.key}: ${[for (final f in e.value) '${f.id} ${f.name}${f.perMl ? ' (ml)' : ''}${tail?.call(f) ?? ''}'].join('; ')}',
  ];
}

/// Αναζήτηση υλικού από το όνομα, όταν το id του βοηθού δεν υπάρχει: ταιριάζει αν όλες οι λέξεις του ονόματος είναι στο
/// όνομα του τροφίμου (χωρίς τόνους, πτώσεις). Ο έλεγχος με το μάτι (στην οθόνη) είναι υποχρεωτικός.
bool sameWords(String a, String b) {
  List<String> w(String s) => phonetic(s).split(RegExp(r'[^a-z0-9]+')).where((x) => x.length > 1).toList();
  final wa = w(a), wb = w(b);
  return wa.isNotEmpty && wa.every(wb.contains);
}
