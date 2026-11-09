/// Open Food Facts → πρόχειρο τρόφιμο για έλεγχο από τον χρήστη.
/// Τα δεδομένα είναι από εθελοντές (άδεια ODbL), οπότε ΠΑΝΤΑ τα βλέπει και τα επιβεβαιώνει
/// ο χρήστης με την ετικέτα πριν αποθηκευτούν.
library;

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
  })  : values = values ?? {},
        lessThan = lessThan ?? {};

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

double? _num(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.'));
  return null;
}

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
  var saltFromSodium = false;
  double? sodiumMg;
  if (values[Nk.salt] == null) {
    final na = _num(n['sodium_100g']);
    if (na != null && na >= 0) {
      values[Nk.salt] = double.parse((na * 2.5).toStringAsFixed(3));
      saltFromSodium = true;
      sodiumMg = double.parse((na * 1000).toStringAsFixed(1));
      final mod = n['sodium_modifier'];
      if (mod == '<' || mod == '≤' || mod == '<=') lessThan.add(Nk.salt);
    }
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
  final alcoholVol = _num(n['alcohol_100g']) ?? _num(n['alcohol']);
  final polyols = _num(n['polyols_100g']);
  final erythritol = _num(n['erythritol_100g']);
  return FoodDraft(
    name: pick(['product_name_el', 'generic_name_el', 'product_name']) ?? '',
    brand: brand,
    barcode: barcode,
    servingGrams: _num(p['serving_quantity']),
    servingLabel: pick(['serving_size']),
    values: values,
    fromOff: true,
    perMl: perMl,
    alcohol: alcoholVol == null || alcoholVol <= 0 ? null : alcoholVol * 0.789,
    polyols: polyols == null || polyols <= 0 ? null : polyols,
    erythritol: erythritol == null || erythritol <= 0 ? null : erythritol,
    saltFromSodium: saltFromSodium,
    sodiumMg: sodiumMg,
    lessThan: lessThan,
  );
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
      n: Nutrients({
        for (final e in d.values.entries) e.key: NValue(e.value, lessThan: d.lessThan.contains(e.key)),
        if (d.alcohol != null) Nk.alcohol: NValue(d.alcohol!),
        if (d.polyols != null) Nk.polyols: NValue(d.polyols!),
        if (d.erythritol != null) Nk.erythritol: NValue(d.erythritol!),
        if (d.sodiumMg != null && d.values[Nk.salt] != null) Nk.sodium: NValue(d.sodiumMg!),
      }),
    );
