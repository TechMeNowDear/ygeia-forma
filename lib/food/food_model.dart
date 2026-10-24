/// Διατροφή: τρόφιμα, καταχωρίσεις, γεύματα.
///
/// Κανόνες ακρίβειας (έγγραφο › «Βάση τροφίμων»):
/// - Οι αριθμοί έρχονται ΜΟΝΟ από βάση (CIQUAL, USDA, Open Food Facts, ετικέτα που πέρασα εγώ). Ποτέ από AI.
/// - Τιμές ανά 100 g. «Ίχνη» και «<x» μετράνε 0 στα αθροίσματα και δείχνονται όπως είναι.
/// - Κάθε καταχώριση κρατά αντίγραφο των τιμών ανά 100 g τη στιγμή που μπήκε.
library;

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
}

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
  });

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

  bool get isMine => source == 'Open Food Facts' || source == 'Ετικέτα';

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
        servingGrams: (j['servingGrams'] as num?)?.toDouble(),
        servingLabel: j['servingLabel'] as String?,
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
        'n': n.toJson(),
      };
}

enum Meal { breakfast, lunch, dinner, snack }

String mealLabel(Meal m) => switch (m) {
      Meal.breakfast => 'Πρωινό',
      Meal.lunch => 'Μεσημεριανό',
      Meal.dinner => 'Βραδινό',
      Meal.snack => 'Σνακ',
    };

/// Έξυπνη προεπιλογή γεύματος από την ώρα (έγγραφο › Καταχώριση).
Meal mealForTime(DateTime t) {
  final h = t.hour;
  if (h >= 5 && h < 11) return Meal.breakfast;
  if (h >= 12 && h < 17) return Meal.lunch;
  if (h >= 19 && h < 23) return Meal.dinner;
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

  LogEntry copyWith({Meal? meal, double? grams}) =>
      LogEntry(id: id, day: day, meal: meal ?? this.meal, food: food, grams: grams ?? this.grams, time: time);

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
        'food': food.toJson(),
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
      count++;
    }
  }
  double kcal = 0, protein = 0, carbs = 0, fat = 0, fiber = 0, sugars = 0, salt = 0;
  int count = 0;
}

/// «1.250» για θερμίδες, «12,5» για γραμμάρια.
String kcalText(double v) => thousands(v.round());
String gramsText(double v) => v >= 100 ? v.round().toString() : dec(v, v < 10 ? 1 : 0);

/// Κείμενο τιμής ανά 100 g όπως στην πηγή: «<0,5», «ίχνη», «12,3».
String nValueText(NValue? v, {int digits = 1}) {
  if (v == null) return '—';
  if (v.traces) return 'ίχνη';
  if (v.lessThan) return '<${dec(v.value, digits)}';
  return dec(v.value, digits);
}
