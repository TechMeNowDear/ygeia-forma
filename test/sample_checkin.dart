// Φανταστικά δεδομένα για τον εβδομαδιαίο έλεγχο θερμίδων (δημόσιο repo: κανένα πραγματικό νούμερο του χρήστη).
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/goals.dart';
import 'package:ygeia_forma/history.dart';

import 'sample_data.dart' show inbodyApp;
import 'sample_food.dart';

/// Στόχοι από Δευτέρα 16/11: άνδρας 40, 180 cm, 90 kg, −0,5%/εβδ., μέτρια κίνηση (τύπος 2.745 → στόχος 2.250).
Goals checkinGoals({String since = '2026-11-16', int? kcalSet, int? kcalAdapt}) => Goals(
      aim: GoalAim.lose,
      rate: 0.005,
      activity: 1.5,
      doctor: true,
      since: since,
      kg: 90,
      age: 40,
      heightCm: 180,
      male: true,
      kcalSet: kcalSet,
      kcalAdapt: kcalAdapt,
    );

/// [days] μέρες πριν από [today]: τρως [eat], καις [tdee]· ζυγίσεις Δευτέρα, Τετάρτη, Παρασκευή στις 7:30.
List<(DateTime, double)> simWeights(DateTime today, {int days = 21, double eat = 2250, double tdee = 2600, double kg0 = 90}) {
  final out = <(DateTime, double)>[];
  var kg = kg0;
  for (var k = days; k >= 0; k--) {
    final d = DateTime(today.year, today.month, today.day - k);
    if (d.weekday == 1 || d.weekday == 3 || d.weekday == 5) out.add((DateTime(d.year, d.month, d.day, 7, 30), (kg * 10).round() / 10));
    kg += (eat - tdee) / kcalPerKg;
  }
  return out;
}

/// Η σειρά «body» του Dashboard (InBody) για τις ζυγίσεις.
List<Map<String, Object>> bodyJson(List<(DateTime, double)> w) => [
      for (final (t, kg) in w) {'time': t.millisecondsSinceEpoch, 'weight': kg, 'app': inbodyApp},
    ];

/// Ημερολόγιο: [days] μέρες πριν από [today] με [eat] kcal (σε τρία γεύματα), και ένα πρωινό σήμερα.
FoodStore checkinFood(DateTime today, {int days = 21, double eat = 2250, Set<int> skip = const {}}) {
  final bread = foodNamed('Ψωμί ολικής άλεσης');
  final yog = foodNamed('Γιαούρτι στραγγιστό χαμηλά λιπαρά (περίπου 2%)');
  final perG = bread.n.amount(Nk.kcal) / 100;
  final entries = <LogEntry>[];
  var n = 0;
  void add(DateTime d, Meal m, Food f, double g, int hour) => entries.add(LogEntry(
      id: 'c${n++}', day: dateKey(d), meal: m, food: f, grams: g, time: DateTime(d.year, d.month, d.day, hour)));
  for (var k = days; k >= 1; k--) {
    if (skip.contains(k)) continue;
    final d = DateTime(today.year, today.month, today.day - k);
    for (final (m, h) in [(Meal.breakfast, 9), (Meal.lunch, 14), (Meal.dinner, 20)]) {
      add(d, m, bread, eat / 3 / perG, h);
    }
  }
  add(today, Meal.breakfast, yog, 200, 9);
  return FoodStore.preloaded(foods: basicFoods(), entries: entries, now: today);
}
