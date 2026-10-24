import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_search.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/food/off.dart';

import 'sample_food.dart';

void main() {
  group('Αναζήτηση', () {
    test('Τόνοι, κεφαλαία και greeklish δίνουν την ίδια φωνητική μορφή', () {
      expect(phonetic('Ντομάτα'), phonetic('ntomata'));
      expect(phonetic('κοτόπουλο'), phonetic('kotopoulo'));
      expect(phonetic('Γιαούρτι'), phonetic('giaourti'));
      expect(phonetic('χοιρινό'), phonetic('xoirino'));
      expect(phonetic('ρεβίθια'), phonetic('revithia'));
      expect(phonetic('ΦΑΚΈΣ'), phonetic('fakes'));
      expect(phonetic('μπέικον'), phonetic('mpeikon'));
    });

    final index = FoodIndex(basicFoods());
    List<String> names(String q) => [for (final f in index.search(q).take(5)) f.name];

    test('«fakes» βρίσκει φακές πρώτα', () {
      expect(names('fakes').first, startsWith('Φακές'));
    });
    test('«γιαουρτι 2» βρίσκει το στραγγιστό 2%', () {
      expect(names('γιαουρτι 2').first, contains('2%'));
    });
    test('«ρεβύθια» (με υ) βρίσκει ρεβίθια', () {
      expect(names('ρεβύθια').first, startsWith('Ρεβίθια'));
    });
    test('«φιλετο κοτοπουλο» βρίσκει στήθος κοτόπουλου από τα άλλα ονόματα', () {
      expect(names('φιλετο κοτοπουλο').first, startsWith('Κοτόπουλο στήθος'));
    });
    test('Τίποτα για ανύπαρκτη λέξη', () {
      expect(index.search('ξυλοκαρβουνο'), isEmpty);
    });
  });

  group('Αριθμοί', () {
    test('Σύνολα ανά ποσότητα από τη βάση', () {
      final lentils = foodNamed('Φακές (βρασμένες)');
      final e = LogEntry(id: 'x', day: '2026-10-24', meal: Meal.lunch, food: lentils, grams: 300, time: DateTime(2026));
      final t = Totals([e]);
      expect(t.kcal, closeTo(lentils.n.amount(Nk.kcal) * 3, 0.001));
      expect(t.protein, closeTo(lentils.n.amount(Nk.protein) * 3, 0.001));
    });

    test('«ίχνη» και «<x» μετράνε 0 αλλά δείχνονται όπως είναι', () {
      final n = Nutrients.fromJson({'fat': {'lt': 0.5}, 'carbs': {'tr': true}, 'protein': 3});
      expect(n.amount('fat'), 0);
      expect(n.amount('carbs'), 0);
      expect(nValueText(n['fat']), '<0,5');
      expect(nValueText(n['carbs']), 'ίχνη');
    });

    test('Κάθε τρόφιμο της βάσης έχει θερμίδες, πρωτεΐνη, υδατάνθρακες και λίπος', () {
      for (final f in basicFoods()) {
        for (final k in [Nk.kcal, Nk.protein, Nk.carbs, Nk.fat]) {
          expect(f.n.has(k), isTrue, reason: '${f.name}: λείπει $k');
        }
      }
    });

    test('Λογικά νούμερα: μακρο + ίνες + νερό δεν ξεπερνούν τα 100 g (με ανοχή 3 g για στρογγυλέματα της πηγής)', () {
      for (final f in basicFoods()) {
        final sum = [Nk.protein, Nk.carbs, Nk.fat, Nk.fiber, 'water'].fold<double>(0, (s, k) => s + f.n.amount(k));
        expect(sum, lessThanOrEqualTo(103), reason: '${f.name}: ${sum.toStringAsFixed(1)} g');
      }
    });

    test('USDA: οι υδατάνθρακες χωρίς τις φυτικές ίνες, όπως στις ετικέτες της ΕΕ', () {
      final lima = basicFoods().firstWhere((f) => f.id == 'U174252');
      expect(lima.n.amount(Nk.carbs), closeTo(63.38 - 19.0, 0.01));
    });

    test('Σταθερά id: το κριθαράκι κρατά το id του', () {
      expect(basicFoods().where((f) => f.id == 'C9810-1').single.name, startsWith('Κριθαράκι'));
    });

    test('Γεύμα από την ώρα', () {
      expect(mealForTime(DateTime(2026, 1, 1, 8)), Meal.breakfast);
      expect(mealForTime(DateTime(2026, 1, 1, 14)), Meal.lunch);
      expect(mealForTime(DateTime(2026, 1, 1, 21)), Meal.dinner);
      expect(mealForTime(DateTime(2026, 1, 1, 17, 30)), Meal.snack);
    });
  });

  group('Open Food Facts', () {
    test('Ανά 100 g, θερμίδες από kJ όταν λείπουν οι kcal', () {
      final d = draftFromOff('5201004021428', {
        'product_name': 'Yoghurt',
        'product_name_el': 'Γιαούρτι στραγγιστό 2%',
        'brands': 'Fage, Total',
        'serving_quantity': 170,
        'nutriments': {
          'energy_100g': 305,
          'proteins_100g': 10,
          'carbohydrates_100g': 3,
          'fat_100g': 2,
          'salt_100g': '0,1',
        },
      });
      expect(d.name, 'Γιαούρτι στραγγιστό 2%');
      expect(d.brand, 'Fage');
      expect(d.values[Nk.kcal], closeTo(72.9, 0.1));
      expect(d.values[Nk.salt], 0.1);
      expect(d.missing, isEmpty);
      expect(d.servingGrams, 170);
    });

    test('Λείπουν τιμές → ζητούνται από την ετικέτα', () {
      final d = draftFromOff('1', {'product_name': 'X', 'nutriments': {'energy-kcal_100g': 100}});
      expect(d.missing, containsAll([Nk.protein, Nk.carbs, Nk.fat]));
    });

    test('Θερμίδες που δεν ταιριάζουν με τα μακρο (π.χ. ανά μερίδα)', () {
      expect(energyMismatch({Nk.kcal: 72, Nk.protein: 10, Nk.carbs: 3, Nk.fat: 2}), isNull);
      expect(energyMismatch({Nk.kcal: 250, Nk.protein: 10, Nk.carbs: 3, Nk.fat: 2}), isNotNull);
    });
  });

  group('Ημερολόγιο', () {
    test('Προσθήκη, ποσότητα από την τελευταία φορά, συχνά, διαγραφή και αναίρεση', () async {
      final now = DateTime(2026, 10, 24, 13);
      final s = FoodStore.preloaded(foods: basicFoods(), now: now);
      final feta = foodNamed('Φέτα (ΠΟΠ, πρόβειο και κατσικίσιο)');
      await s.add(feta, 40, Meal.lunch);
      final e2 = await s.add(feta, 30, Meal.dinner);
      expect(s.entriesFor(now).length, 2);
      expect(s.lastGrams(feta.id), 30);
      expect(s.frequent().first.id, feta.id);
      await s.remove(e2);
      expect(s.entriesFor(now).length, 1);
      await s.restore(e2);
      expect(s.entriesFor(now, Meal.dinner).single.grams, 30);
    });

    test('Αντίγραφο τιμών στην καταχώριση (JSON πάει και έρχεται)', () {
      final f = foodNamed('Μέλι');
      final e = LogEntry(id: 'a', day: '2026-10-24', meal: Meal.breakfast, food: f, grams: 15, time: DateTime(2026, 10, 24, 9));
      final back = LogEntry.fromJson(e.toJson().map((k, v) => MapEntry(k, v)));
      expect(back.total(Nk.kcal), closeTo(e.total(Nk.kcal), 1e-9));
      expect(back.food.source, f.source);
    });
  });
}
