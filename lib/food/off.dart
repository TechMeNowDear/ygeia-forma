/// Open Food Facts → πρόχειρο τρόφιμο για έλεγχο από τον χρήστη.
/// Τα δεδομένα είναι από εθελοντές (άδεια ODbL), οπότε ΠΑΝΤΑ τα βλέπει και τα επιβεβαιώνει
/// ο χρήστης με την ετικέτα πριν αποθηκευτούν.
library;

import 'chol.dart' show branByName;
import 'food_model.dart';
import 'food_search.dart' show plain;

class FoodDraft {
  FoodDraft({
    this.name = '',
    this.brand,
    this.barcode,
    this.servingGrams,
    this.servingLabel,
    Map<String, double>? values,
    this.fromOff = false,
    this.perMl = false,
    this.alcohol,
    this.polyols,
    this.erythritol,
    this.saltFromSodium = false,
    this.sodiumMg,
    Set<String>? lessThan,
    this.cholKind,
    this.spoon,
  })  : values = values ?? {},
        lessThan = lessThan ?? {};

  /// Round9 (R9-A2-2): μετριέται με το κουτάλι ([Food.spoon]). Από τις κατηγορίες του Open Food Facts όταν σαρώνεται
  /// ([spoonFromOffTags]), από το ίδιο το προϊόν όταν διορθώνεται· null = δεν ξέρουμε (η φόρμα προτείνει από το όνομα).
  /// Round10 (R10-B1-1): false = διάλεξες «Όχι» ([Food.spoonNo]), και μένει «Όχι» σε κάθε «Διόρθωση».
  final bool? spoon;

  /// Τι μετρά το προϊόν στην κάρτα «Χοληστερίνη» ([CholKind]) ή null. Από τις κατηγορίες του Open Food Facts όταν
  /// σαρώνεται ([cholKindFromOffTags]), από το ίδιο το προϊόν όταν διορθώνεται· το αλλάζεις στη φόρμα.
  final String? cholKind;

  /// Πεδία που η πηγή δίνει ως «<x» (π.χ. «αλάτι <0,01»): μένουν «<x» αν δεν τα αλλάξεις (έλεγχος 9/11, Χ5).
  final Set<String> lessThan;

  /// Νάτριο σε mg ανά 100, όταν το αλάτι βγήκε από νάτριο (για να φαίνεται και στη διόρθωση).
  final double? sodiumMg;

  /// Το Open Food Facts έδωσε μόνο νάτριο: το αλάτι υπολογίστηκε × 2,5 (Κανονισμός ΕΕ 1169/2011· τρίτος έλεγχος
  /// διατροφής N7). Η φόρμα το λέει, για να το συγκρίνει ο χρήστης με την ετικέτα.
  final bool saltFromSodium;

  String name;
  String? brand;
  String? barcode;
  double? servingGrams;
  String? servingLabel;

  /// Ανά 100 g, κλειδιά Nk.*
  final Map<String, double> values;
  final bool fromOff;

  /// Υγρό στο Open Food Facts: τα πεδία «_100g» είναι τότε ανά 100 ml (έλεγχος διατροφής M4, 4/11).
  /// Η εφαρμογή μετρά σε γραμμάρια· το λέμε στη φόρμα, χωρίς να μαντεύουμε πυκνότητα.
  final bool perMl;

  /// Αλκοόλ και πολυόλες σε g ανά 100 (από το Open Food Facts), ΜΟΝΟ για τον έλεγχο θερμίδων: δίνουν θερμίδες που
  /// δεν φαίνονται στα μακροθρεπτικά (αλκοόλ 7 kcal/g, πολυόλες 2,4 kcal/g, Κανονισμός ΕΕ 1169/2011). Δεν
  /// αποθηκεύονται ως θρεπτικά (δεύτερος έλεγχος διατροφής N9: μπίρα και κρασί έβγαζαν «οι θερμίδες δεν ταιριάζουν»).
  final double? alcohol;
  final double? polyols;

  /// Ερυθριτόλη (g ανά 100), μέρος των πολυολών: 0 kcal/g στον Κανονισμό ΕΕ 1169/2011, όχι 2,4 (έλεγχος 9/11, Χ5).
  final double? erythritol;

  static const required = [Nk.kcal, Nk.protein, Nk.carbs, Nk.fat];

  List<String> get missing => [for (final k in required) if (values[k] == null) k];
}

/// Αριθμός του Open Food Facts (αριθμός ή κείμενο). Τελικός έλεγχος (Συμβούλιο 3): μόνο πεπερασμένος· «NaN»,
/// «Infinity» ή 1e999 μετρούν ως «λείπει» (πριν περνούσαν, και μια τέτοια τιμή δεν γράφεται σε JSON: η αποθήκευση έσκαγε).
double? _num(Object? v) {
  final d = v is num ? v.toDouble() : (v is String ? double.tryParse(v.trim().replaceAll(',', '.')) : null);
  return d == null || !d.isFinite ? null : d;
}

/// Ποσοστό ή γραμμάρια ανά 100: πάνω από 0 και ως 100. Αλλιώς «δεν υπάρχει» (π.χ. αλκοόλ 400% vol από λάθος εθελοντή).
double? _per100(double? v) => v == null || v <= 0 || v > 100 ? null : v;

FoodDraft draftFromOff(String barcode, Map<String, dynamic> p) {
  final n = (p['nutriments'] is Map) ? Map<String, dynamic>.from(p['nutriments'] as Map) : <String, dynamic>{};
  String? pick(List<String> keys) {
    for (final k in keys) {
      final v = p[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  final values = <String, double>{};
  final lessThan = <String>{};
  void put(String key, String offKey) {
    final v = _num(n['${offKey}_100g']);
    if (v != null && v >= 0) {
      values[key] = v;
      // «<0,5 g» στην ετικέτα: το Open Food Facts κρατά τον αριθμό και το «<» χωριστά.
      final mod = n['${offKey}_modifier'];
      if (mod == '<' || mod == '≤' || mod == '<=') lessThan.add(key);
    }
  }

  put(Nk.kcal, 'energy-kcal');
  final kj = _num(n['energy_100g']) ?? _num(n['energy-kj_100g']);
  // kcal 0 μαζί με kJ > 0 είναι λάθος δεδομένων του Open Food Facts (N7): μετρά ως «λείπει».
  if (values[Nk.kcal] == null || (values[Nk.kcal] == 0 && kj != null && kj > 0)) {
    values.remove(Nk.kcal);
    if (kj != null && kj >= 0) values[Nk.kcal] = double.parse((kj / 4.184).toStringAsFixed(1));
  }
  put(Nk.protein, 'proteins');
  put(Nk.carbs, 'carbohydrates');
  put(Nk.sugars, 'sugars');
  put(Nk.fat, 'fat');
  put(Nk.satFat, 'saturated-fat');
  put(Nk.fiber, 'fiber');
  put(Nk.salt, 'salt');
  // Μόνο νάτριο (συχνό σε εισαγόμενα): αλάτι = νάτριο × 2,5 (το νάτριο του Open Food Facts είναι σε g).
  // Αλάτι 0 μαζί με νάτριο > 0 είναι λάθος δεδομένων, όπως το «kcal 0 με kJ > 0» πιο πάνω (τελικός έλεγχος, Συμβούλιο 3):
  // μετρά το νάτριο, αλλιώς το προϊόν έμπαινε σιωπηλά «χωρίς αλάτι».
  var saltFromSodium = false;
  double? sodiumMg;
  final na = _num(n['sodium_100g']);
  if (na != null && na >= 0 && (values[Nk.salt] == null || (values[Nk.salt] == 0 && na > 0))) {
    values[Nk.salt] = double.parse((na * 2.5).toStringAsFixed(3));
    saltFromSodium = true;
    sodiumMg = double.parse((na * 1000).toStringAsFixed(1));
    lessThan.remove(Nk.salt);
    final mod = n['sodium_modifier'];
    if (mod == '<' || mod == '≤' || mod == '<=') lessThan.add(Nk.salt);
  }

  final brand = pick(['brands'])?.split(',').first.trim();
  // «Ανά 100 ml»: στο Open Food Facts το nutrition_data_per είναι μόνο «100g» ή «serving», και τα «_100g» των υγρών
  // σημαίνουν ανά 100 ml (τεκμηρίωση OFF, Product-Nutrition schema). Άρα το υγρό φαίνεται από τη συσκευασία
  // (έλεγχος 8/11, FOOD-01· ο κανόνας N7 βασιζόταν σε τιμή «100ml» που το OFF δεν στέλνει).
  final per = (p['nutrition_data_per'] is String ? p['nutrition_data_per'] as String : '').trim().toLowerCase();
  // Η μερίδα μετρά μόνο όταν δεν υπάρχει συσκευασία και δεν έχει γραμμάρια: «30 g (+125 ml γάλα)» ή «1 cup (240 ml)» σε
  // δημητριακά δεν είναι υγρό (ανεξάρτητος έλεγχος του fix-food, 4.2).
  final quantity = pick(['quantity']);
  final serving = pick(['serving_size']);
  final perMl = per.contains('ml') ||
      isLiquidQuantity(quantity) ||
      (quantity == null && serving != null && !RegExp(r'\d\s*g\b').hasMatch(serving) && isLiquidQuantity(serving));
  // Στο Open Food Facts το «alcohol» είναι % vol: g ανά 100 ml = % vol × 0,789 (πυκνότητα αιθανόλης).
  // Ό,τι δεν είναι πάνω από 0 και ως 100 δεν μετρά (τελικός έλεγχος, Συμβούλιο 3): αυτές οι τρεις τιμές δεν φαίνονται
  // στη φόρμα, άρα ο χρήστης δεν θα έβλεπε ποτέ μια παράλογη.
  final alcoholVol = _per100(_num(n['alcohol_100g']) ?? _num(n['alcohol']));
  final polyols = _per100(_num(n['polyols_100g']));
  final erythritol = _per100(_num(n['erythritol_100g']));
  final name = pick(['product_name_el', 'generic_name_el', 'product_name']) ?? '';
  return FoodDraft(
    name: name,
    brand: brand,
    barcode: barcode,
    // Μερίδα μόνο αν γίνεται να γραφτεί ως ποσότητα (πάνω από 0, ως 5.000): αλλιώς «χωρίς μερίδα».
    servingGrams: validServing(_num(p['serving_quantity'])),
    servingLabel: pick(['serving_size']),
    values: values,
    fromOff: true,
    perMl: perMl,
    alcohol: alcoholVol == null ? null : alcoholVol * 0.789,
    polyols: polyols,
    erythritol: erythritol,
    saltFromSodium: saltFromSodium,
    sodiumMg: sodiumMg,
    lessThan: lessThan,
    cholKind: cholKindFromOffTags(p['categories_tags'], name: name),
    spoon: spoonFromOffTags(p['categories_tags'], kcal: values[Nk.kcal]),
  );
}

// Round9 (R9-A2-2): κατηγορίες του Open Food Facts για ό,τι μετριέται με το κουτάλι, με τον κανόνα της βάσης ([isSpoonFood]):
// λίπη και λάδια, βούτυρο, μαργαρίνη, μαγιονέζα πάντα (όπως η κατηγορία «Λιπαρά»)· αλείμματα από [spoonSpreadKcal] kcal
// στα 100 g (ταχίνι, φυστικοβούτυρο, πραλίνα, όπως τα «Αλείμματα»· όχι μαρμελάδα, μέλι, χούμους).
const _offSpoonFatTags = {'en:fats', 'en:spreadable-fats', 'en:margarines', 'en:butters', 'en:mayonnaises'};
const _offSpreadTags = {'en:spreads', 'en:sweet-spreads', 'en:plant-based-spreads', 'en:oilseed-purees', 'en:nut-butters'};

/// Μετριέται με το κουτάλι, από τις κατηγορίες του Open Food Facts ([tags]) και τις θερμίδες ανά 100 g ([kcal]): true, ή
/// null όταν οι κατηγορίες δεν το λένε (τότε η φόρμα προτείνει από το όνομα, [spoonByName]). Πριν, ένα σαρωμένο ταχίνι
/// («Τα προϊόντα μου», λιπαρά 60 g) άνοιγε με τη μερίδα του Open Food Facts (100 g = 673 kcal) χωρίς καμία ερώτηση, ενώ
/// το ταχίνι της βάσης ανοίγει με 15 g (R8-A2-1).
bool? spoonFromOffTags(Object? tags, {double? kcal}) {
  if (tags is! List) return null;
  final t = {
    for (final x in tags)
      if (x is String) x.trim().toLowerCase(),
  };
  if (t.any(_offSpoonFatTags.contains)) return true;
  if (t.any(_offSpreadTags.contains) && (kcal ?? 0) >= spoonSpreadKcal) return true;
  return null;
}

/// Η πρώτη λέξη του ονόματος λέει τρόφιμο του κουταλιού: «Ταχίνι …», «Φυστικοβούτυρο …», «Μαργαρίνη …», «Μαγιονέζα …»,
/// «Πραλίνα …», «Βούτυρο …» (πεζά/κεφαλαία και τόνοι δεν μετράνε). Μόνο η ΠΡΩΤΗ λέξη: «Μπισκότα με ταχίνι» δεν είναι.
/// Round10 (R10-B1-1): οι ελληνικές λέξεις ΟΛΟΚΛΗΡΕΣ· πριν αρκούσε να αρχίζει έτσι η λέξη, και το «Βουτυρόγαλα» ή τα
/// «Βουτυρομπισκότα» έβγαιναν «Ναι» (ανοίγαν με 15 g, και κάθε ποσότητα από 100 g ρωτούσε «Σωστή ποσότητα;»).
bool spoonByName(String name) {
  final first = plain(name).split(RegExp(r'[^a-z0-9α-ω]+')).firstWhere((w) => w.isNotEmpty, orElse: () => '');
  return first.isNotEmpty && (_spoonWords.contains(first) || _spoonLatin.any(first.startsWith));
}

/// Ολόκληρες λέξεις (όχι «ταχινόπιτα», «πραλινέ» σοκολάτα, «βουτυράκια» μπισκότα, «βουτυρόγαλα», «βουτυρομπισκότα»).
const _spoonWords = {'ταχινι', 'φυστικοβουτυρο', 'πραλινα', 'μαργαρινη', 'μαγιονεζα', 'βουτυρο'};

/// Λατινικά: η αρχή της λέξης (tahini, margarine/margarina, mayonnaise/mayonesa).
const _spoonLatin = ['tahini', 'margarin', 'mayonn'];

// ---------------------------------------------------------------------------
// Ξερό ή μαγειρεμένο, για τα δικά μου προϊόντα (round9, R9-A2-3)
// ---------------------------------------------------------------------------

/// Λέξεις που λένε ότι το προϊόν δεν βράζεται σαν ζυμαρικό, ρύζι ή όσπριο (αλεύρι, γκοφρέτες, μπάρες, γάλα, σούπα…).
const _dryNot = [
  'αλευρ', 'γκοφρετ', 'κρακερ', 'μπαρα', 'μπαρεσ', 'νιφαδ', 'φουσκωτ', 'γαλα', 'ροφημ', 'σουπ', 'σαλατ', 'μπισκοτ',
  'σνακ', 'πατατακ', 'κριτσιν', 'τραχαν', 'πουρε', 'κεικ', 'flour', 'farin', 'cracker', 'cake', 'wafer', 'flake',
  'puff', 'chip', 'snack', 'milk', 'drink', 'soup', 'salad', 'cereal', 'noodle',
];

const _pastaNames = [
  'μακαρον', 'σπαγγετ', 'σπαγετ', 'πεννε', 'πενεσ', 'φουζιλ', 'βιδεσ', 'ταλιατελ', 'λινγκουιν', 'λιγκουιν', 'ριγκατον',
  'φαρφαλ', 'φιογκακ', 'ζυμαρικ', 'κοφτο', 'φιδε', 'λαζαν', 'spaghett', 'penne', 'fusill', 'linguin', 'tagliatell',
  'farfall', 'rigaton', 'macaroni', 'lasagn', 'fettuccin', 'pappardell', 'tortiglion', 'conchigli', 'orecchiett',
  'bucatin', 'vermicell',
];

/// Δικό μου προϊόν (barcode ή ετικέτα) που είναι ξερό ζυμαρικό, ρύζι, όσπριο, κινόα, πλιγούρι ή κουσκούς: το id της
/// ξερής μορφής της βάσης που του αντιστοιχεί (ολικής → «Μακαρόνια ολικής άλεσης», καστανό parboiled → «Ρύζι καστανό
/// parboiled», φακές → «Φακές (ξερές)»…), αλλιώς null. Από το όνομα (ελληνικά ή λατινικά, χωρίς τόνους), και μόνο για ξερό
/// προϊόν: από [rawCheckKcal] kcal στα 100 g (οι κονσέρβες και τα έτοιμα έχουν 70–180).
///
/// Round9 (R9-A2-3): η ερώτηση «Ζύγισες πριν ή μετά το μαγείρεμα;» (R7-U2-2) και τα «Ζύγισα:» ίσχυαν μόνο για τη βάση· ένα
/// σαρωμένο σπαγγέτι ολικής (336 kcal) με 250 g ΒΡΑΣΜΕΝΑ έγραφε 840 kcal αντί για ~448, χωρίς ερώτηση. Τώρα η δεύτερη
/// επιλογή είναι η βρασμένη μορφή της ΒΑΣΗΣ (οι αριθμοί πάντα από βάση, ποτέ υπολογισμένοι από εμάς).
String? dryStapleRawId(Food f) {
  if (!f.isMine || f.perMl || f.n.amount(Nk.kcal) < rawCheckKcal) return null;
  final words = [
    for (final w in plain(f.name).split(RegExp(r'[^a-z0-9α-ω]+')))
      if (w.isNotEmpty) w,
  ];
  bool has(List<String> stems) => words.any((w) => stems.any(w.startsWith));
  if (has(_dryNot)) return null;
  final whole = has(const ['ολικ', 'κασταν', 'whole', 'integral', 'brown', 'complet']);
  // Round10 (R10-B1-3): ζυμαρικό ΑΠΟ όσπρια («Fusilli κόκκινες φακές», «Πένες από ρεβίθι», «Lentil pasta») είναι ζυμαρικό:
  // ξερή και βρασμένη μορφή τα μακαρόνια της βάσης. Πριν η λέξη «φακές» έδινε «Φακές (ξερές)» και η «Βρασμένες» ήταν οι
  // φακές της βάσης: ζυγισμένο βρασμένο μετρούσε «Όσπρια» (και 125 αντί για 167 kcal στα 100 g), ζυγισμένο ξερό όχι (στο
  // Open Food Facts είναι «Pastas»: «Τίποτα»). Το ζυμαρικό φουσκώνει όπως τα μακαρόνια (×2,2 στη βάση, οι φακές ×2,6), άρα
  // οι θερμίδες των βρασμένων μακαρονιών είναι πιο κοντά (και όχι λιγότερες). Μόνο όταν το ίδιο το προϊόν λέει «Όσπρια»
  // (το διάλεξες στη φόρμα) μένουν οι μορφές των οσπρίων, ώστε ξερό και βρασμένο να μετρούν το ίδιο στην κάρτα.
  final pasta = (has(_pastaNames) || has(const ['pasta'])) && f.cholKind != CholKind.legumes;
  String legume(String id) => pasta ? (whole ? 'C9870' : 'C9810') : id;
  if (has(const ['φακεσ', 'φακη', 'lentil', 'lenticch', 'lentej'])) return legume('C20359');
  if (has(const ['ρεβυθ', 'ρεβιθ', 'chickpea', 'garbanzo'])) return legume('C20516');
  if (has(const ['φαβα', 'σπαστ'])) return legume('C20515');
  if (has(const ['μαυρομ'])) return legume('U173758');
  if (has(const ['γιγαντ', 'ελεφαντ'])) return legume('U174252');
  if (has(const ['φασολ'])) return legume('C20501');
  if (has(const ['ρυζι', 'rice', 'riso', 'riz', 'arroz'])) {
    if (has(const ['μπασματι', 'basmati'])) return 'C9119';
    final parboiled = has(const ['parboil']);
    if (whole) return parboiled ? 'U168876' : 'C9102';
    return parboiled ? 'C9101' : 'C9100';
  }
  if (has(const ['κινοα', 'quinoa'])) return 'C9340';
  if (has(const ['πλιγουρ', 'bulgur', 'boulgour'])) return 'C9690';
  if (has(const ['κουσκουσ', 'couscous'])) return 'C9681';
  if (has(const ['κριθαρακ', 'orzo'])) return 'C9810-1';
  if (has(const ['χυλοπιτ'])) return 'C9821';
  if (has(_pastaNames)) {
    if (has(const ['αυγ', 'egg', 'uova', 'uovo'])) return 'C9821';
    return whole ? 'C9870' : 'C9810';
  }
  return null;
}

/// Οι ξερές μορφές οσπρίων της βάσης που δίνει το [dryStapleRawId] (κατηγορία «Όσπρια»: φακές, ρεβίθια, φάβα,
/// μαυρομάτικα, γίγαντες, φασόλια).
const _dryLegumeIds = {'C20359', 'C20516', 'C20515', 'U173758', 'U174252', 'C20501'};

/// Round11 (R11-C1-3): δικό μου ΞΕΡΟ όσπριο από το όνομα («Φακές ψιλές Χ», 334 kcal): η ξερή του μορφή είναι όσπριο της
/// βάσης ([dryStapleRawId]· όχι ζυμαρικό από όσπρια, R10-B1-3). Για προϊόν χωρίς «μετρά ως» ([Food.cholKind] null): η
/// κάρτα «Χοληστερίνη» το μετρά «Όσπρια» ([isLegumes]) και η φόρμα το δείχνει. Πριν, ζυγισμένο ξερό ΔΕΝ μετρούσε, ενώ το
/// ίδιο ζυγισμένο «Βρασμένες» (η βρασμένη μορφή της βάσης, κατηγορία «Όσπρια») μετρούσε: ίδιο προϊόν, ίδια ποσότητα, άλλη
/// απάντηση. Μόνο ξερό (από [rawCheckKcal] kcal): μια κονσέρβα χωρίς «μετρά ως» μένει όπως πριν, γιατί από το όνομα δεν
/// ξέρουμε πάντα ότι είναι μαγειρεμένη (θα μετρούσε σαν ξερή, 2,5 φορές περισσότερο).
///
/// Round12 (R12-D1-1): και τα ξερά κουκιά («Κουκιά ξερά Χ», 301 kcal), που η βάση έχει μόνο ξερά («Κουκιά (ξερά)», C20518,
/// κατηγορία «Όσπρια», χωρίς βρασμένη μορφή, άρα όχι στο [dryStapleRawId]): πριν, 80 g από τη βάση μετρούσαν «Όσπρια» και
/// τα ίδια 80 g από δικό σου προϊόν όχι. Ίδιοι φραγμοί: δικό σου, όχι υγρό, από [rawCheckKcal] kcal (τα φρέσκα ή
/// κατεψυγμένα κουκιά, 60–90 kcal, μένουν έξω, R9-A3-1), όχι «αλεύρι/σνακ…» ([_dryNot]), όχι ζυμαρικό από όσπρια (R10-B1-3).
bool legumesByName(Food f) {
  final raw = dryStapleRawId(f);
  if (_dryLegumeIds.contains(raw)) return true;
  if (raw != null || !f.isMine || f.perMl || f.n.amount(Nk.kcal) < rawCheckKcal) return false;
  final words = [
    for (final w in plain(f.name).split(RegExp(r'[^a-z0-9α-ω]+')))
      if (w.isNotEmpty) w,
  ];
  bool has(List<String> stems) => words.any((w) => stems.any(w.startsWith));
  if (has(_dryNot) || has(_pastaNames) || has(const ['pasta'])) return false;
  return has(const ['κουκι']);
}

// Κατηγορίες του Open Food Facts (πεδίο «categories_tags», αγγλικά ονόματα της ταξινομίας του) για το ΙΔΙΟ το τρόφιμο.
const _offNutTags = {
  'en:nuts', 'en:mixed-nuts', 'en:almonds', 'en:walnuts', 'en:walnut-kernels', 'en:hazelnuts', 'en:pistachios',
  'en:cashew-nuts', 'en:pecan-nuts', 'en:brazil-nuts', 'en:macadamia-nuts', 'en:pine-nuts', 'en:peanuts',
};
const _offFishTags = {
  'en:fishes', 'en:canned-fishes', 'en:frozen-fishes', 'en:smoked-fishes', 'en:fatty-fishes', 'en:fish-fillets',
  'en:tunas', 'en:canned-tunas', 'en:sardines', 'en:canned-sardines', 'en:salmons', 'en:smoked-salmons',
  'en:mackerels', 'en:canned-mackerels', 'en:anchovies', 'en:herrings', 'en:cods', 'en:crustaceans', 'en:shrimps',
  'en:prawns', 'en:mollusks', 'en:molluscs', 'en:cephalopods', 'en:mussels', 'en:squids', 'en:octopuses',
};
/// Round9 (R9-A3-1): χωρίς τα «en:canned-legumes», «en:legume-seeds» και «en:broad-beans»: στην ταξινομία του Open Food
/// Facts περιέχουν και πράσινα λαχανικά (φασολάκια και αρακά κονσέρβα, φρέσκα/κατεψυγμένα κουκιά, φύτρες), και μια
/// κονσέρβα φασολάκια μετρούσε «Όσπρια». Όσπρια είναι μόνο οι καρποί που συγκομίζονται ξεροί (FAO 2016, «Definitions of
/// legumes and pulses»), όπως στη βάση, όπου φασολάκια και αρακάς είναι «Λαχανικά». Τα ξερά/κονσέρβα όσπρια που
/// βρίσκονταν μόνο κάτω από εκείνες τις κατηγορίες μπαίνουν με το όνομά τους.
const _offLegumeTags = {
  'en:pulses', 'en:canned-pulses', 'en:lentils', 'en:green-lentils', 'en:red-lentils', 'en:canned-lentils',
  'en:canned-seasoned-lentils', 'en:chickpeas', 'en:canned-chickpeas', 'en:common-beans', 'en:canned-common-beans',
  'en:white-beans', 'en:red-beans', 'en:kidney-beans', 'en:black-beans', 'en:split-peas', 'en:dried-broad-beans',
  'en:canned-butter-beans', 'en:canned-scarlet-runner-beans', 'en:dried-soy-beans',
};

/// Round9 (R9-A3-1): πράσινα λαχανικά, φύτρες και ό,τι άλλο δεν είναι όσπριο, ακόμα κι όταν το Open Food Facts τα βάζει
/// κάτω από τα «όσπρια» (π.χ. τα χιονομπίζελα και οι φύτρες μουνγκ είναι στα «en:pulses», οι φύτρες φακής στα «en:lentils»):
/// «Τίποτα».
const _offGreenVeg = {
  'en:green-beans', 'en:green-peas', 'en:fresh-legumes', 'en:snow-peas', 'en:cooked-snow-peas',
  'en:snow-peas-boiled-in-water', 'en:sprouts', 'en:lentil-sprouts', 'en:sprouted-mung-beans', 'en:alfalfa-seeds',
  'en:tonka-beans', 'en:edamame', 'en:fresh-broad-beans', 'en:frozen-broad-beans', 'en:canned-broad-beans',
  'en:cooked-broad-beans',
};
const _offBranTags = {'en:oat-bran', 'en:oat-brans'};

/// Κατηγορίες του [_offNotTheFood] όπου μπαίνει και το σκέτο πίτουρο βρώμης (round8, R8-A3-1).
const _offBranHomes = {'en:breakfast-cereals', 'en:flours'};

/// Προϊόντα που απλώς ΠΕΡΙΕΧΟΥΝ ξηρούς καρπούς, όσπρια ή ψάρι (άλειμμα, ρόφημα, σοκολάτα, μπάρα, έτοιμο φαγητό, σαλάτα,
/// σούπα, πανέ, σουρίμι, λάδι, αλεύρι…) ή δεν είναι από αυτά που ρίχνουν την LDL (κάστανα): δεν μετρούν μόνα τους.
const _offNotTheFood = {
  'en:spreads', 'en:sweet-spreads', 'en:nut-butters', 'en:peanut-butters', 'en:oilseed-purees', 'en:hummus',
  'en:beverages', 'en:plant-based-beverages', 'en:plant-based-milk-alternatives', 'en:milk-substitutes',
  'en:chocolates', 'en:confectioneries', 'en:sweet-snacks', 'en:bars', 'en:cereal-bars', 'en:biscuits-and-cakes',
  'en:desserts', 'en:ice-creams', 'en:breakfast-cereals', 'en:mueslis', 'en:breads', 'en:crackers', 'en:pastas',
  'en:flours', 'en:vegetable-oils', 'en:nut-oils', 'en:fish-oils', 'en:dietary-supplements', 'en:meals',
  'en:prepared-meals', 'en:soups', 'en:sauces', 'en:salads', 'en:prepared-salads', 'en:sandwiches', 'en:pizzas',
  'en:breaded-products', 'en:breaded-fish', 'en:fish-fingers', 'en:surimi', 'en:fish-eggs', 'en:taramasalata',
  'en:meat-analogues', 'en:tofu', 'en:chestnuts',
  // Round9 (R9-A3-1): πανέ ψάρια/θαλασσινά που στο Open Food Facts δεν έχουν γονέα το «en:breaded-fish».
  'en:breaded-fried-european-plaice', 'en:breaded-lemon-sole', 'en:breaded-scampi',
};

/// Τι μετρά ένα προϊόν του Open Food Facts στην κάρτα «Χοληστερίνη», από τις κατηγορίες του («categories_tags»): μία
/// τιμή του [CholKind] ή null (έλεγχος round1, S2-1 / S1-9). Προσεκτικά, για να μη μετρήσει κάτι που δεν είναι:
/// - μόνο όταν το προϊόν είναι το ΙΔΙΟ το τρόφιμο (σκέτοι ξηροί καρποί, όσπρια ξερά ή σε κονσέρβα, ψάρι ή θαλασσινά,
///   πίτουρο βρώμης)· ό,τι απλώς τα περιέχει ([_offNotTheFood]) δεν μετρά·
/// - κατηγορία που δεν ξέρουμε = null: το προϊόν μετρά όπως πριν (καθόλου), ώσπου να το ορίσεις στη φόρμα.
/// Τα αράπικα φιστίκια είναι στο Open Food Facts και «όσπρια»· εδώ μετρούν ως ξηροί καρποί, όπως στη βάση.
/// Ό,τι βγει εδώ φαίνεται στη φόρμα ελέγχου του προϊόντος και αλλάζει με ένα πάτημα.
/// Round7 (R7-A3-1): ό,τι απλώς τα περιέχει δίνει «Τίποτα» ([CholKind.none]), όχι null· αλλιώς ένα «Πίτουρο βρώμης
/// κράκερ» (κατηγορία κράκερ) μετρούσε από το όνομα ως πίτουρο.
/// Round8 (R8-A3-1): το σκέτο πίτουρο βρώμης μπαίνει συχνά ΚΑΙ στα «δημητριακά πρωινού» ή στα «αλεύρια» ([_offBranHomes]),
/// και ελληνικό πίτουρο (π.χ. «Πίτυρο Βρώμης …», μόνο με «Breakfast cereals») έβγαινε «Τίποτα»: 0 g στην κάρτα κάθε μέρα.
/// Τώρα: αν οι μόνες «όχι το ίδιο το τρόφιμο» κατηγορίες είναι αυτές οι δύο, και το προϊόν έχει κατηγορία πίτουρου βρώμης
/// ή το όνομά του ([name]) αρχίζει «πίτουρο/πίτυρο βρώμης» ([branByName]), μετρά ως πίτουρο. Μπάρες, μπισκότα, κράκερ,
/// ψωμιά και μούσλι μένουν «Τίποτα», και με κατηγορία πίτουρου.
String? cholKindFromOffTags(Object? tags, {String? name}) {
  if (tags is! List) return null;
  final t = {
    for (final x in tags)
      if (x is String) x.trim().toLowerCase(),
  };
  final bran = t.any(_offBranTags.contains) || (name != null && branByName(name));
  final notTheFood = t.where(_offNotTheFood.contains).toSet();
  if (notTheFood.isNotEmpty) return bran && notTheFood.every(_offBranHomes.contains) ? CholKind.bran : CholKind.none;
  if (t.any(_offBranTags.contains)) return CholKind.bran;
  if (t.any(_offNutTags.contains)) return CholKind.nuts;
  if (t.any(_offFishTags.contains)) return CholKind.fish;
  if (t.any(_offGreenVeg.contains)) return CholKind.none;
  if (t.any(_offLegumeTags.contains)) return CholKind.legumes;
  return null;
}

/// «330 ml», «1 L», «75cl», «1,5 l», «1 λίτρο», «1 λτ», «1 litre» → υγρό (έλεγχος 9/11, Μ2: πριν δεν έπιανε τα
/// ελληνικά και τα «litre/liter»).
bool isLiquidQuantity(String? q) =>
    q != null &&
    RegExp(r'\d\s*(ml|cl|dl|l|lt|ltr|litres?|liters?|λιτρο|λιτρα|λτ|μλ)(?![a-zα-ω])').hasMatch(plain(q));

/// Το ίδιο barcode σε μία μορφή: μόνο ψηφία, UPC-A 12 ψηφίων → EAN-13 με «0» μπροστά, GTIN-14 με «0» → EAN-13.
String normalizeBarcode(String code) {
  var c = code.replaceAll(RegExp(r'[^0-9]'), '');
  if (c.length == 12) c = '0$c';
  if (c.length == 14 && c.startsWith('0')) c = c.substring(1);
  return c;
}

/// Αυτό που έδωσε ο σαρωτής είναι barcode προϊόντος; Μόνο ψηφία, και μετά το [normalizeBarcode] 8 (EAN-8, UPC-E) ή 13
/// (EAN-13, UPC-A). Επιστρέφει την ενιαία μορφή, ή null. Τελικός έλεγχος (Συμβούλιο 3): πριν, κενή ή άκυρη απάντηση του
/// σαρωτή συνέχιζε ως «barcode», κατέληγε σε «Δεν έγινε σύνδεση…» και το προϊόν αποθηκευόταν με barcode «» (κενό)· ο
/// επόμενος κενός κωδικός θα «έβρισκε» εκείνο το προϊόν.
String? scannedBarcode(Object? raw) {
  if (raw is! String) return null;
  final t = raw.trim();
  if (!RegExp(r'^[0-9]+$').hasMatch(t)) return null;
  final c = normalizeBarcode(t);
  return c.length == 8 || c.length == 13 ? c : null;
}

/// Έλεγχος λογικής: θερμίδες ετικέτας vs υπολογισμένες από τα μακροθρεπτικά (συντελεστές ΕΕ: πρωτεΐνη 4,
/// υδατάνθρακες 4, λίπος 9, ίνες 2, αλκοόλ 7, πολυόλες 2,4· στην ετικέτα ΕΕ οι υδατάνθρακες περιέχουν τις πολυόλες).
/// [alcohol], [polyols]: g ανά 100. Επιστρέφει τις υπολογισμένες αν η απόκλιση είναι >15% και >20 kcal.
/// [erythritol]: μέρος των πολυολών με 0 kcal/g (Παράρτημα XIV του ίδιου Κανονισμού).
double? energyMismatch(Map<String, double> v, {double alcohol = 0, double polyols = 0, double erythritol = 0}) {
  final k = v[Nk.kcal], p = v[Nk.protein], c = v[Nk.carbs], f = v[Nk.fat];
  if (k == null || p == null || c == null || f == null) return null;
  final sugarAlcohols = polyols.clamp(0.0, c);
  final ery = erythritol.clamp(0.0, sugarAlcohols);
  final calc = 4 * p + 4 * (c - sugarAlcohols) + 9 * f + 2 * (v[Nk.fiber] ?? 0) + 7 * alcohol + 2.4 * (sugarAlcohols - ery);
  final diff = (k - calc).abs();
  return (diff > 20 && diff / (k > 1 ? k : 1) > 0.15) ? calc : null;
}

/// Τιμές που **δεν γίνεται** να είναι σωστές (ανά 100 g): το προϊόν δεν αποθηκεύεται μέχρι να διορθωθούν.
Map<String, String> impossibleValues(Map<String, double> v) {
  final out = <String, String>{};
  final k = v[Nk.kcal];
  if (k != null && k > 900) out[Nk.kcal] = 'Πάνω από 900 kcal ανά 100 g δεν γίνεται (μήπως είναι kJ;)';
  for (final key in const [Nk.protein, Nk.carbs, Nk.sugars, Nk.fat, Nk.satFat, Nk.fiber, Nk.salt]) {
    final x = v[key];
    if (x != null && x > 100) {
      // Έλεγχος 9/11 (V-C-14): στο αλάτι ο πιο πιθανός λόγος είναι νάτριο σε mg από ξένη ετικέτα.
      out[key] = key == Nk.salt
          ? 'Πάνω από 100 g δεν γίνεται. Αν η ετικέτα γράφει νάτριο (sodium) σε mg, διάλεξε «Νάτριο mg».'
          : 'Πάνω από 100 g σε 100 g δεν γίνεται';
    }
  }
  return out;
}

/// Τιμές που **μάλλον** είναι λάθος: προειδοποίηση, αλλά το προϊόν αποθηκεύεται (κάποιες ετικέτες,
/// π.χ. αμερικάνικες, γράφουν αλλιώς). Το κλειδί `total` είναι για το σύνολο, όχι για ένα πεδίο.
Map<String, String> doubtfulValues(Map<String, double> v) {
  final out = <String, String>{};
  final c = v[Nk.carbs], s = v[Nk.sugars], f = v[Nk.fat], sf = v[Nk.satFat];
  if (c != null && s != null && s > c + 0.5) out[Nk.sugars] = 'Τα σάκχαρα είναι μέρος των υδατανθράκων: έλεγξέ τα';
  if (f != null && sf != null && sf > f + 0.5) out[Nk.satFat] = 'Τα κορεσμένα είναι μέρος των λιπαρών: έλεγξέ τα';
  // Χωρίς τις φυτικές ίνες: σε αμερικάνικες ετικέτες είναι ήδη μέσα στους υδατάνθρακες.
  final total = (v[Nk.protein] ?? 0) + (c ?? 0) + (f ?? 0) + (v[Nk.salt] ?? 0);
  if (total > 105) {
    out['total'] = 'Πρωτεΐνη, υδατάνθρακες, λιπαρά και αλάτι μαζί ξεπερνούν τα 100 g. Έλεγξε ξανά την ετικέτα.';
  }
  return out;
}

/// Για διόρθωση προϊόντος που υπάρχει ήδη. Κρατά αλκοόλ και πολυόλες για τον έλεγχο θερμίδων (έλεγχος 9/11, Χ5:
/// πριν, η διόρθωση μιας μπίρας έλεγε ψέματα «οι θερμίδες δεν ταιριάζουν»), και τα «<x».
FoodDraft draftFromFood(Food f) => FoodDraft(
      name: f.name,
      brand: f.brand,
      barcode: f.barcode,
      servingGrams: f.servingGrams,
      servingLabel: f.servingLabel,
      values: {
        for (final e in f.n.values.entries)
          if (_formKeys.contains(e.key)) e.key: e.value.value,
      },
      fromOff: f.source == 'Open Food Facts',
      perMl: f.perMl,
      alcohol: f.n[Nk.alcohol]?.value,
      polyols: f.n[Nk.polyols]?.value,
      erythritol: f.n[Nk.erythritol]?.value,
      saltFromSodium: f.n.has(Nk.sodium),
      sodiumMg: f.n[Nk.sodium]?.value,
      lessThan: {for (final e in f.n.values.entries) if (e.value.lessThan) e.key},
      cholKind: f.cholKind,
      // Προϊόν χωρίς «sp» (και όσα αποθηκεύτηκαν πριν υπάρξει): η φόρμα προτείνει από το όνομα ([spoonByName]).
      // Round10 (R10-B1-1): το «Όχι» που διάλεξες μένει «Όχι» ([Food.spoonNo]· πριν η «Διόρθωση» ξαναπρότεινε «Ναι» από το
      // όνομα, και η αποθήκευση το έγραφε σιωπηλά).
      spoon: f.spoon ? true : (f.spoonNo ? false : null),
    );

const _formKeys = {Nk.kcal, Nk.protein, Nk.carbs, Nk.sugars, Nk.fat, Nk.satFat, Nk.fiber, Nk.salt};

const myFoodsCategory = 'Τα προϊόντα μου';

/// Αλκοόλ, πολυόλες, ερυθριτόλη και νάτριο αποθηκεύονται κι αυτά (νέα κλειδιά· οι παλιές εκδόσεις τα αγνοούν).
Food foodFromDraft(FoodDraft d, String id) => Food(
      id: id,
      name: d.name.trim(),
      cat: myFoodsCategory,
      brand: (d.brand?.trim().isEmpty ?? true) ? null : d.brand!.trim(),
      barcode: d.barcode,
      source: d.fromOff ? 'Open Food Facts' : 'Ετικέτα',
      servingGrams: d.servingGrams,
      servingLabel: d.servingLabel,
      perMl: d.perMl,
      cholKind: d.cholKind,
      spoon: d.spoon ?? false,
      spoonNo: d.spoon == false,
      n: Nutrients({
        for (final e in d.values.entries) e.key: NValue(e.value, lessThan: d.lessThan.contains(e.key)),
        if (d.alcohol != null) Nk.alcohol: NValue(d.alcohol!),
        if (d.polyols != null) Nk.polyols: NValue(d.polyols!),
        if (d.erythritol != null) Nk.erythritol: NValue(d.erythritol!),
        if (d.sodiumMg != null && d.values[Nk.salt] != null) Nk.sodium: NValue(d.sodiumMg!),
      }),
    );
