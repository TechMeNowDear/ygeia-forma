import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_search.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/food/kitchen.dart';
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
      expect(names('fakes').take(2).every((n) => n.startsWith('Φακές')), isTrue);
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
    test('Η ωμή μορφή βγαίνει πριν από τη μαγειρεμένη', () {
      expect(names('μακαρονια').first, 'Μακαρόνια (ξηρά, ωμά)');
      expect(names('ρυζι λευκο').first, 'Ρύζι λευκό (ωμό)');
      expect(names('fakes').first, 'Φακές (ξερές)');
      expect(names('κοτοπουλο στηθος').first, 'Κοτόπουλο στήθος χωρίς πέτσα (ωμό)');
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

  group('Ωμό και μαγειρεμένο', () {
    final s = FoodStore.preloaded(foods: basicFoods());
    test('Από το ωμό και από το βρασμένο βγαίνουν οι ίδιες καταστάσεις', () {
      final raw = foodNamed('Μακαρόνια (ξηρά, ωμά)');
      final cooked = foodNamed('Μακαρόνια (βρασμένα, χωρίς αλάτι)');
      final a = [for (final x in s.statesOf(raw)) x.$2];
      final b = [for (final x in s.statesOf(cooked)) x.$2];
      expect(a, ['Ωμό', 'Βρασμένα']);
      expect(b, a);
    });
    test('Πατάτα: ωμή, βραστή, φούρνου', () {
      final p = foodNamed('Πατάτα (ωμή, ξεφλουδισμένη)');
      expect([for (final x in s.statesOf(p)) x.$2], ['Ωμό', 'Βραστή', 'Φούρνου']);
    });
    test('Τρόφιμο χωρίς άλλες μορφές', () {
      expect(s.statesOf(foodNamed('Μέλι')), isEmpty);
    });
    test('180 g ωμά μακαρόνια ≠ 180 g βρασμένα', () {
      final raw = foodNamed('Μακαρόνια (ξηρά, ωμά)');
      final cooked = foodNamed('Μακαρόνια (βρασμένα, χωρίς αλάτι)');
      expect(raw.n.amount(Nk.kcal) * 1.8, greaterThan(cooked.n.amount(Nk.kcal) * 1.8 * 2));
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

  group('Η κουζίνα μου', () {
    test('Αρχική κατάσταση από το αρχείο του χρήστη και αποθήκευση', () {
      final k = Kitchen.fromJson(null);
      expect(k.has('steamer'), isTrue);
      expect(k.steamerTiers, 2);
      expect(k.has('airFryer'), isFalse);
      expect(k.cookware.where((c) => c.kind == 'panNonstick').length, 3);
      k.cookware.first.tareGrams = 640;
      final back = Kitchen.fromJson(k.toJson());
      expect(back.cookware.first.tareGrams, 640);
      expect(back.devices, k.devices);
      expect(back.cookware.where((c) => c.kind == 'pot').map((c) => c.size), ['Μικρό', 'Μεσαίο', 'Μεγάλο']);
      expect(back.hob, 'Κεραμικά');
      expect(back.cookware.firstWhere((c) => c.kind == 'pot').label, 'Κατσαρόλα · μικρή');
      expect(back.cookware.first.label, 'Τηγάνι αντικολλητικό · μικρό · Tefal');
    });

    test('Αναβάθμιση από την πρώτη έκδοση: προσθέτει, δεν σβήνει', () {
      // Όπως αποθηκεύτηκε στο #32, με αλλαγές του χρήστη.
      final old = {
        'devices': ['oven', 'hob', 'steamer', 'scale'],
        'ovenFan': false,
        'cookware': [
          {'id': 'c1', 'kind': 'panNonstick', 'size': 'Μικρό', 'brand': 'Tefal', 'tare': 410},
          {'id': 'c6', 'kind': 'pot'},
          {'id': 'c7', 'kind': 'tray'},
        ],
      };
      final k = Kitchen.fromJson(old);
      expect(k.has('toaster') && k.has('blender') && k.has('steamer'), isTrue);
      expect(k.ovenFan, isFalse, reason: 'ό,τι έγραψε ο χρήστης μένει');
      expect(k.hob, 'Κεραμικά');
      expect(k.cookware.first.tareGrams, 410);
      expect(k.cookware.where((c) => c.kind == 'pot').length, 3);
      expect(k.cookware.where((c) => c.kind == 'glass').single.brand, 'Pyrex');
      // Δεύτερο άνοιγμα: τίποτα δεν διπλασιάζεται.
      final again = Kitchen.fromJson(k.toJson());
      expect(again.cookware.length, k.cookware.length);
    });
  });
}
