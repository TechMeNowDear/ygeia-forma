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
  }) : values = values ?? {};

  String name;
  String? brand;
  String? barcode;
  double? servingGrams;
  String? servingLabel;

  /// Ανά 100 g, κλειδιά Nk.*
  final Map<String, double> values;
  final bool fromOff;

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
  if (values[Nk.kcal] == null) {
    final kj = _num(n['energy_100g']) ?? _num(n['energy-kj_100g']);
    if (kj != null) values[Nk.kcal] = double.parse((kj / 4.184).toStringAsFixed(1));
  }
  put(Nk.protein, 'proteins');
  put(Nk.carbs, 'carbohydrates');
  put(Nk.sugars, 'sugars');
  put(Nk.fat, 'fat');
  put(Nk.satFat, 'saturated-fat');
  put(Nk.fiber, 'fiber');
  put(Nk.salt, 'salt');

  final brand = pick(['brands'])?.split(',').first.trim();
  return FoodDraft(
    name: pick(['product_name_el', 'generic_name_el', 'product_name']) ?? '',
    brand: brand,
    barcode: barcode,
    servingGrams: _num(p['serving_quantity']),
    servingLabel: pick(['serving_size']),
    values: values,
    fromOff: true,
  );
}

/// Έλεγχος λογικής: θερμίδες ετικέτας vs υπολογισμένες από τα μακροθρεπτικά (συντελεστές ΕΕ).
/// Επιστρέφει τις υπολογισμένες αν η απόκλιση είναι >15% και >20 kcal.
double? energyMismatch(Map<String, double> v) {
  final k = v[Nk.kcal], p = v[Nk.protein], c = v[Nk.carbs], f = v[Nk.fat];
  if (k == null || p == null || c == null || f == null) return null;
  final calc = 4 * p + 4 * c + 9 * f + 2 * (v[Nk.fiber] ?? 0);
  final diff = (k - calc).abs();
  return (diff > 20 && diff / (k > 1 ? k : 1) > 0.15) ? calc : null;
}

/// Τιμές ανά 100 g που δεν γίνεται να είναι σωστές (λάθος πληκτρολόγηση ή τιμές ανά μερίδα/kJ).
/// Κλειδί → μήνυμα. Κενό αν όλα στέκουν.
Map<String, String> impossibleValues(Map<String, double> v) {
  final out = <String, String>{};
  final k = v[Nk.kcal];
  if (k != null && k > 900) out[Nk.kcal] = 'Πάνω από 900 kcal ανά 100 g δεν γίνεται (μήπως είναι kJ;)';
  for (final key in const [Nk.protein, Nk.carbs, Nk.sugars, Nk.fat, Nk.satFat, Nk.fiber, Nk.salt]) {
    final x = v[key];
    if (x != null && x > 100) out[key] = 'Πάνω από 100 g σε 100 g δεν γίνεται';
  }
  final c = v[Nk.carbs], s = v[Nk.sugars], f = v[Nk.fat], sf = v[Nk.satFat];
  if (c != null && s != null && s > c + 0.5) out[Nk.sugars] ??= 'Τα σάκχαρα είναι μέρος των υδατανθράκων: όχι περισσότερα';
  if (f != null && sf != null && sf > f + 0.5) out[Nk.satFat] ??= 'Τα κορεσμένα είναι μέρος των λιπαρών: όχι περισσότερα';
  final total = (v[Nk.protein] ?? 0) + (c ?? 0) + (f ?? 0) + (v[Nk.fiber] ?? 0) + (v[Nk.salt] ?? 0);
  if (total > 105) out[Nk.protein] ??= 'Μαζί όλα ξεπερνούν τα 100 g: έλεγξε τις τιμές';
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
      n: Nutrients({for (final e in d.values.entries) e.key: NValue(e.value)}),
    );
