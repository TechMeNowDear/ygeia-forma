import 'dart:convert';
import 'dart:io';

import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/history.dart';

List<Food>? _cache;

/// Η πραγματική βάση τροφίμων της εφαρμογής (assets/foods/basic_foods.json).
List<Food> basicFoods() => _cache ??= [
      for (final f in (jsonDecode(File('assets/foods/basic_foods.json').readAsStringSync()) as Map)['foods'] as List)
        Food.fromJson(Map<String, dynamic>.from(f as Map)),
    ];

Food foodNamed(String name) => basicFoods().firstWhere((f) => f.name == name);

/// Ένα ρεαλιστικό ημερολόγιο: σήμερα μέχρι το απόγευμα, και μερικές προηγούμενες μέρες.
FoodStore sampleFoodStore(DateTime now) {
  final entries = <LogEntry>[];
  var n = 0;
  void add(int daysAgo, Meal meal, String name, double grams, int hour) {
    final d = DateTime(now.year, now.month, now.day - daysAgo);
    entries.add(LogEntry(
      id: 'e${n++}',
      day: dateKey(d),
      meal: meal,
      food: foodNamed(name),
      grams: grams,
      time: DateTime(d.year, d.month, d.day, hour, n % 60),
    ));
  }

  for (var ago = 0; ago < 6; ago++) {
    add(ago, Meal.breakfast, 'Εσπρέσο (χωρίς ζάχαρη)', 60, 9);
    add(ago, Meal.breakfast, 'Γάλα ημιαποβουτυρωμένο 1,5%', 30, 9);
    add(ago, Meal.breakfast, 'Ζάχαρη λευκή', 5, 9);
    add(ago, Meal.breakfast, 'Γιαούρτι στραγγιστό χαμηλά λιπαρά (περίπου 2%)', 200, 9);
    add(ago, Meal.breakfast, 'Μέλι', 15, 9);
    add(ago, Meal.breakfast, 'Καρύδια', 20, 9);
    if (ago.isEven) {
      add(ago, Meal.lunch, 'Φακές (βρασμένες)', 300, 14);
      add(ago, Meal.lunch, 'Φέτα (ΠΟΠ, πρόβειο και κατσικίσιο)', 40, 14);
    } else {
      add(ago, Meal.lunch, 'Κοτόπουλο στήθος χωρίς πέτσα (ψητό στο τηγάνι/σχάρα)', 180, 14);
      add(ago, Meal.lunch, 'Ρύζι καστανό/ολικής (βρασμένο)', 150, 14);
    }
    add(ago, Meal.lunch, 'Ψωμί ολικής άλεσης', 60, 14);
    add(ago, Meal.lunch, 'Ελαιόλαδο εξαιρετικά παρθένο', 10, 14);
    add(ago, Meal.snack, 'Μπανάνα', 120, 16);
    if (ago > 0) {
      add(ago, Meal.dinner, 'Μπρόκολο (στον ατμό)', 200, 20);
      add(ago, Meal.dinner, 'Μοσχαρίσιο φιλέτο (ωμό)', 150, 20);
    }
  }
  return FoodStore.preloaded(foods: basicFoods(), entries: entries, now: now);
}
