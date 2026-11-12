/// Διατροφή: τρόφιμα, καταχωρίσεις, γεύματα.
///
/// Κανόνες ακρίβειας (έγγραφο › «Βάση τροφίμων»):
/// - Οι αριθμοί έρχονται ΜΟΝΟ από βάση (CIQUAL, USDA, Open Food Facts, ετικέτα που πέρασα εγώ). Ποτέ από AI.
/// - Τιμές ανά 100 g. «Ίχνη» και «<x» μετράνε 0 στα αθροίσματα και δείχνονται όπως είναι.
/// - Κάθε καταχώριση κρατά αντίγραφο των τιμών ανά 100 g τη στιγμή που μπήκε.
library;

import 'dart:math' as math;

import '../format.dart';

/// Κλειδιά θρεπτικών (ίδια με τα αρχεία της βάσης).
abstract final class Nk {
  static const kcal = 'kcal';
  static const protein = 'protein';
  static const carbs = 'carbs';
  static const sugars = 'sugars';
  static const fiber = 'fiber';
  static const fat = 'fat';
  static const satFat = 'satFat';
  static const salt = 'salt';

  /// Νάτριο σε mg (της πηγής· ή από την ετικέτα, όταν γράφει νάτριο αντί για αλάτι).
  static const sodium = 'sodium';

  /// Αλκοόλ, πολυόλες και ερυθριτόλη σε g ανά 100 (δίνουν θερμίδες που δεν φαίνονται στα μακροθρεπτικά).
  static const alcohol = 'alcohol';
  static const polyols = 'polyols';
  static const erythritol = 'erythritol';
}

/// Η μεγαλύτερη ποσότητα μιας καταχώρισης (g ή ml). Το ίδιο όριο ισχύει για τη «μία μερίδα» ενός προϊόντος: μερίδα που
/// δεν γίνεται να γραφτεί δεν προτείνεται (τελικός έλεγχος, Συμβούλιο 3).
const maxEntryGrams = 5000.0;

/// Η «μία μερίδα» όπως διαβάστηκε (αρχείο, αντίγραφο, Open Food Facts, φόρμα): μόνο αριθμός πάνω από 0 και ως
/// [maxEntryGrams]. Οτιδήποτε άλλο (0, αρνητικό, τεράστιο, όχι αριθμός) = «χωρίς μερίδα».
double? validServing(Object? v) => v is num && v.isFinite && v > 0 && v <= maxEntryGrams ? v.toDouble() : null;

/// Τιμή θρεπτικού όπως έρχεται από την πηγή.
class NValue {
  const NValue(this.value, {this.lessThan = false, this.traces = false});
  final double value;

  /// «<x»: η πηγή λέει μόνο ότι είναι μικρότερο από value.
  final bool lessThan;
  final bool traces;

  /// Για αθροίσματα: «ίχνη» και «<x» μετράνε 0.
  double get amount => (lessThan || traces) ? 0 : value;

  static NValue? fromJson(Object? j) {
    if (j is num) return NValue(j.toDouble());
    if (j is Map) {
      if (j['tr'] == true) return const NValue(0, traces: true);
      if (j['lt'] is num) return NValue((j['lt'] as num).toDouble(), lessThan: true);
    }
    return null;
  }

  Object toJson() => traces ? {'tr': true} : (lessThan ? {'lt': value} : value);
}

class Nutrients {
  Nutrients(this.values);
  final Map<String, NValue> values;

  factory Nutrients.fromJson(Map<String, dynamic> j) => Nutrients({
        for (final e in j.entries)
          if (NValue.fromJson(e.value) case final v?) e.key: v,
      });

  Map<String, Object> toJson() => {for (final e in values.entries) e.key: e.value.toJson()};

  NValue? operator [](String k) => values[k];
  double amount(String k) => values[k]?.amount ?? 0;
  bool has(String k) => values.containsKey(k);
}

class Food {
  Food({
    required this.id,
    required this.name,
    required this.cat,
    required this.n,
    this.aliases = const [],
    required this.source,
    this.sourceCode,
    this.sourceName,
    this.brand,
    this.barcode,
    this.energyCalc = false,
    this.servingGrams,
    this.servingLabel,
    this.rawId,
    this.cookedLabel,
    this.cooked = const [],
    this.perMl = false,
  });

  /// Οι τιμές είναι ανά 100 ml (υγρό από το Open Food Facts). Αποθηκεύεται, ώστε η διόρθωση αργότερα να λέει ξανά
  /// «ανά 100 ml» και όχι «ανά 100 g» (δεύτερος έλεγχος διατροφής N9).
  final bool perMl;

  final String id;
  final String name;
  final String cat;
  final List<String> aliases;

  /// «CIQUAL 2025», «USDA SR Legacy», «Open Food Facts», «Ετικέτα».
  final String source;
  final Object? sourceCode;
  final String? sourceName;
  final String? brand;
  final String? barcode;
  final bool energyCalc;

  /// Μερίδα της συσκευασίας (αν τη δίνει η πηγή).
  final double? servingGrams;
  final String? servingLabel;

  final Nutrients n;

  /// Αν αυτό είναι μαγειρεμένη μορφή: το id της ωμής και ο τρόπος («Βρασμένο», «Ψητό»…).
  final String? rawId;
  final String? cookedLabel;

  /// Αν αυτό είναι ωμό: οι μαγειρεμένες μορφές του (id, τρόπος).
  final List<(String, String)> cooked;

  bool get isRawWithCooked => cooked.isNotEmpty;

  bool get isMine => source == 'Open Food Facts' || source == 'Ετικέτα';

  /// «ml» για υγρά με τιμές ανά 100 ml (η ποσότητα γράφεται τότε σε ml), αλλιώς «g».
  String get unit => perMl ? 'ml' : 'g';

  factory Food.fromJson(Map<String, dynamic> j) => Food(
        id: j['id'] as String,
        name: j['name'] as String,
        cat: (j['cat'] as String?) ?? '',
        aliases: [for (final a in (j['aliases'] as List?) ?? const []) a.toString()],
        source: (j['source'] as String?) ?? '',
        sourceCode: j['sourceCode'],
        sourceName: j['sourceName'] as String?,
        brand: j['brand'] as String?,
        barcode: j['barcode'] as String?,
        energyCalc: j['energyCalc'] == true,
        // Τελικός έλεγχος (Συμβούλιο 3): μερίδα 0, αρνητική ή τεράστια (παλιά καταχώριση, πειραγμένο αντίγραφο) δεν
        // προτείνεται ως ποσότητα· το προϊόν και οι τιμές του μένουν όπως είναι.
        servingGrams: validServing(j['servingGrams']),
        servingLabel: j['servingLabel'] as String?,
        rawId: j['rawId'] as String?,
        cookedLabel: j['cookedLabel'] as String?,
        perMl: j['perMl'] == true,
        cooked: [
          for (final c in (j['cooked'] as List?) ?? const [])
            if (c is Map) ((c['id'] as String), (c['label'] as String)),
        ],
        n: Nutrients.fromJson(Map<String, dynamic>.from(j['n'] as Map)),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'cat': cat,
        'aliases': aliases,
        'source': source,
        if (sourceCode != null) 'sourceCode': sourceCode,
        if (sourceName != null) 'sourceName': sourceName,
        if (brand != null) 'brand': brand,
        if (barcode != null) 'barcode': barcode,
        if (energyCalc) 'energyCalc': true,
        if (servingGrams != null) 'servingGrams': servingGrams,
        if (servingLabel != null) 'servingLabel': servingLabel,
        if (rawId != null) 'rawId': rawId,
        if (cookedLabel != null) 'cookedLabel': cookedLabel,
        if (cooked.isNotEmpty) 'cooked': [for (final c in cooked) {'id': c.$1, 'label': c.$2}],
        if (perMl) 'perMl': true,
        'n': n.toJson(),
      };

  /// Το αντίγραφο που κρατά κάθε καταχώριση: ό,τι χρειάζεται για να δείχνει και να μετρά
  /// (όνομα, πηγή, τιμές), χωρίς τα στοιχεία αναζήτησης (άλλα ονόματα, περιγραφή πηγής, μορφές),
  /// που υπάρχουν ήδη στη βάση. Μικρότερο ημερολόγιο και αντίγραφο ασφαλείας.
  Map<String, Object?> toSnapshotJson() => {
        for (final e in toJson().entries)
          if (e.key != 'aliases' && e.key != 'sourceName' && e.key != 'cooked') e.key: e.value,
      };
}

enum Meal { breakfast, lunch, dinner, snack }

/// Σύντομα ονόματα, ίδιου μεγέθους στο κουμπί επιλογής (UX U7: το «Μεσημεριανό» μίκραινε για να χωρέσει στα 400 dp).
String mealLabel(Meal m) => switch (m) {
      Meal.breakfast => 'Πρωινό',
      Meal.lunch => 'Μεσημέρι',
      Meal.dinner => 'Βράδυ',
      Meal.snack => 'Σνακ',
    };

/// Έξυπνη προεπιλογή γεύματος από την ώρα (έγγραφο › Καταχώριση). Δείπνο ως τις 00:30: στην Ελλάδα τρώμε αργά
/// (έλεγχος 9/11, RT-14· πριν, ό,τι γραφόταν μετά τις 23:00 έμπαινε «Σνακ»).
Meal mealForTime(DateTime t) {
  final h = t.hour;
  if (h >= 5 && h < 11) return Meal.breakfast;
  if (h >= 12 && h < 17) return Meal.lunch;
  if (h >= 19 || (h == 0 && t.minute < 30)) return Meal.dinner;
  return Meal.snack;
}

class LogEntry {
  LogEntry({
    required this.id,
    required this.day,
    required this.meal,
    required this.food,
    required this.grams,
    required this.time,
  });

  final String id;

  /// «2026-10-24»
  final String day;
  final Meal meal;

  /// Αντίγραφο του τροφίμου τη στιγμή της καταχώρισης.
  final Food food;
  final double grams;
  final DateTime time;

  double total(String k) => food.n.amount(k) * grams / 100;

  LogEntry copyWith({Meal? meal, double? grams, Food? food}) => LogEntry(
      id: id, day: day, meal: meal ?? this.meal, food: food ?? this.food, grams: grams ?? this.grams, time: time);

  factory LogEntry.fromJson(Map<String, dynamic> j) => LogEntry(
        id: j['id'] as String,
        day: j['day'] as String,
        meal: Meal.values.firstWhere((m) => m.name == j['meal'], orElse: () => Meal.snack),
        food: Food.fromJson(Map<String, dynamic>.from(j['food'] as Map)),
        grams: (j['grams'] as num).toDouble(),
        time: DateTime.fromMillisecondsSinceEpoch((j['time'] as num).toInt()),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'day': day,
        'meal': meal.name,
        'food': food.toSnapshotJson(),
        'grams': grams,
        'time': time.millisecondsSinceEpoch,
      };
}

/// Σύνολα για ένα σύνολο καταχωρίσεων.
class Totals {
  Totals(Iterable<LogEntry> entries) {
    for (final e in entries) {
      kcal += e.total(Nk.kcal);
      protein += e.total(Nk.protein);
      carbs += e.total(Nk.carbs);
      fat += e.total(Nk.fat);
      fiber += e.total(Nk.fiber);
      sugars += e.total(Nk.sugars);
      salt += e.total(Nk.salt);
      satFat += e.total(Nk.satFat);
      alcohol += e.total(Nk.alcohol);
      shownKcal += e.total(Nk.kcal).round();
      for (final k in const [Nk.fiber, Nk.sugars, Nk.salt, Nk.satFat]) {
        if (!e.food.n.has(k)) missing[k] = (missing[k] ?? 0) + 1;
      }
      count++;
    }
  }
  double kcal = 0, protein = 0, carbs = 0, fat = 0, fiber = 0, sugars = 0, salt = 0, satFat = 0, alcohol = 0;
  int count = 0;

  /// Θερμίδες όπως φαίνονται: το άθροισμα των στρογγυλεμένων θερμίδων κάθε καταχώρισης, ώστε τα κομμάτια να
  /// αθροίζουν ακριβώς στο σύνολο που γράφει η οθόνη (έλεγχος 9/11, Χ4). Διαφέρει από το [kcal] το πολύ λίγες kcal.
  int shownKcal = 0;

  /// Πόσα τρόφιμα δεν έχουν τιμή για κάθε θρεπτικό (τότε το σύνολο είναι «τουλάχιστον»).
  final Map<String, int> missing = {};
}

/// «1.250» για θερμίδες, «12,5» για γραμμάρια.
String kcalText(double v) => thousands(v.round());
String gramsText(double v) => v >= 100 ? v.round().toString() : dec(v, v < 10 ? 1 : 0);

/// Κείμενο τιμής ανά 100 g όπως στην πηγή: «<0,5», «ίχνη», «12,3».
String nValueText(NValue? v, {int digits = 1}) {
  if (v == null) return '—';
  if (v.traces) return 'ίχνη';
  // Το όριο «<x» στρογγυλεύεται προς τα πάνω: «<0,0125 g» γράφεται «<0,02», ποτέ «<0,01» (που θα ήταν λιγότερο από το όριο).
  if (v.lessThan) {
    final f = math.pow(10, digits);
    return '<${dec(((v.value * f) - 1e-9).ceil() / f, digits)}';
  }
  return dec(v.value, digits);
}
