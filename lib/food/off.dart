/// Open Food Facts → πρόχειρο τρόφιμο για έλεγχο από τον χρήστη.
/// Τα δεδομένα είναι από εθελοντές (άδεια ODbL), οπότε ΠΑΝΤΑ τα βλέπει και τα επιβεβαιώνει
/// ο χρήστης με την ετικέτα πριν αποθηκευτούν.
library;

import 'food_model.dart';

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
    this.saltFromSodium = false,
  }) : values = values ?? {};

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
  void put(String key, String offKey) {
    final v = _num(n['${offKey}_100g']);
    if (v != null && v >= 0) values[key] = v;
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
  if (values[Nk.salt] == null) {
    final na = _num(n['sodium_100g']);
    if (na != null && na >= 0) {
      values[Nk.salt] = double.parse((na * 2.5).toStringAsFixed(3));
      saltFromSodium = true;
    }
  }

  final brand = pick(['brands'])?.split(',').first.trim();
  // «Ανά 100 ml»: στο Open Food Facts το nutrition_data_per είναι μόνο «100g» ή «serving», και τα «_100g» των υγρών
  // σημαίνουν ανά 100 ml (τεκμηρίωση OFF, Product-Nutrition schema). Άρα το υγρό φαίνεται από τη συσκευασία
  // (έλεγχος 8/11, FOOD-01· ο κανόνας N7 βασιζόταν σε τιμή «100ml» που το OFF δεν στέλνει).
  final per = (p['nutrition_data_per'] is String ? p['nutrition_data_per'] as String : '').trim().toLowerCase();
  final perMl = per.contains('ml') || isLiquidQuantity(pick(['quantity'])) || isLiquidQuantity(pick(['serving_size']));
  // Στο Open Food Facts το «alcohol» είναι % vol: g ανά 100 ml = % vol × 0,789 (πυκνότητα αιθανόλης).
  final alcoholVol = _num(n['alcohol_100g']) ?? _num(n['alcohol']);
  final polyols = _num(n['polyols_100g']);
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
    saltFromSodium: saltFromSodium,
  );
}

/// «330 ml», «1 L», «75cl», «1,5 l» → υγρό.
bool isLiquidQuantity(String? q) =>
    q != null && RegExp(r'\d\s*(ml|cl|dl|l|lt)\b', caseSensitive: false).hasMatch(q);

/// Έλεγχος λογικής: θερμίδες ετικέτας vs υπολογισμένες από τα μακροθρεπτικά (συντελεστές ΕΕ: πρωτεΐνη 4,
/// υδατάνθρακες 4, λίπος 9, ίνες 2, αλκοόλ 7, πολυόλες 2,4· στην ετικέτα ΕΕ οι υδατάνθρακες περιέχουν τις πολυόλες).
/// [alcohol], [polyols]: g ανά 100. Επιστρέφει τις υπολογισμένες αν η απόκλιση είναι >15% και >20 kcal.
double? energyMismatch(Map<String, double> v, {double alcohol = 0, double polyols = 0}) {
  final k = v[Nk.kcal], p = v[Nk.protein], c = v[Nk.carbs], f = v[Nk.fat];
  if (k == null || p == null || c == null || f == null) return null;
  final sugarAlcohols = polyols.clamp(0.0, c);
  final calc = 4 * p + 4 * (c - sugarAlcohols) + 9 * f + 2 * (v[Nk.fiber] ?? 0) + 7 * alcohol + 2.4 * sugarAlcohols;
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
    if (x != null && x > 100) out[key] = 'Πάνω από 100 g σε 100 g δεν γίνεται';
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

/// Για διόρθωση προϊόντος που υπάρχει ήδη.
FoodDraft draftFromFood(Food f) => FoodDraft(
      name: f.name,
      brand: f.brand,
      barcode: f.barcode,
      servingGrams: f.servingGrams,
      servingLabel: f.servingLabel,
      values: {for (final e in f.n.values.entries) e.key: e.value.value},
      fromOff: f.source == 'Open Food Facts',
      perMl: f.perMl,
    );

const myFoodsCategory = 'Τα προϊόντα μου';

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
      n: Nutrients({for (final e in d.values.entries) e.key: NValue(e.value)}),
    );
