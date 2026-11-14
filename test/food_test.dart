import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_search.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/food/kitchen.dart';
import 'package:ygeia_forma/food/off.dart';
import 'package:ygeia_forma/food/replaced_foods.dart';
import 'package:ygeia_forma/pages/food_add.dart' show parseNumber, gramsField;

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
      expect(phonetic('κοτόπουλο'), phonetic('kotopoylo'));
      // αυ/ευ: f πριν από άηχο σύμφωνο, v αλλού (έλεγχος 8/11, FOOD-03)
      expect(phonetic('λευκό'), phonetic('lefko'));
      expect(phonetic('αυτό'), phonetic('afto'));
      expect(phonetic('αυγό'), phonetic('avgo'));
      expect(phonetic('Εύα'), phonetic('eva'));
    });

    test('Ελληνικά ψάρια και θαλασσινά από τη CIQUAL (έλεγχος 8/11, FOOD-02)', () {
      final i = FoodIndex(basicFoods());
      for (final (q, want) in [('σολομός', 'Σολομός'), ('τσιπούρα', 'Τσιπούρα'), ('λαβράκι', 'Λαβράκι'), ('γαρίδες', 'Γαρίδες'),
          ('μύδια', 'Μύδια'), ('γαύρος', 'Γαύρος'), ('κεφίρ', 'Κεφίρ'), ('tsipoura', 'Τσιπούρα')]) {
        expect(i.search(q).first.name, startsWith(want), reason: q);
      }
      final bream = basicFoods().firstWhere((f) => f.id == 'C27031');
      expect(bream.n.amount(Nk.kcal), 148);
    });

    test('«lefko», «levko», «zahari lefki»: βρίσκουν τα λευκά', () {
      final i = FoodIndex(basicFoods());
      for (final q in ['lefko', 'levko', 'zahari lefki']) {
        expect(i.search(q).take(5).any((f) => plain(f.name).contains('λευκ')), isTrue, reason: q);
      }
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

    test('Πληθυντικοί και πτώσεις βρίσκουν το τρόφιμο', () {
      expect(names('ντομάτες').first, startsWith('Ντομάτα'));
      expect(names('ntomates').first, startsWith('Ντομάτα'));
      expect(names('πιπεριές').first, startsWith('Πιπεριά'));
      expect(names('κρεμμύδια').first, startsWith('Κρεμμύδι'));
      expect(names('φακή').first, startsWith('Φακές'));
      expect(names('αμύγδαλο').first, startsWith('Αμύγδαλα'));
      expect(names('ελιά').first, startsWith('Ελιές'));
    });

    test('«λάδι» βρίσκει πρώτα το ελαιόλαδο, όχι κάτι «χωρίς λάδι»', () {
      expect(names('λάδι').first, startsWith('Ελαιόλαδο'));
      expect(names('λάδι').take(3).any((n) => n.contains('χωρίς λάδι')), isFalse);
    });

    test('Greeklish με x για ξ, h για η, ng για γγ', () {
      expect(names('xeres fakes').first, 'Φακές (ξερές)');
      expect(names('hliosporoi').first, startsWith('Ηλιόσποροι'));
      expect(names('angouri').first, startsWith('Αγγούρι'));
      expect(names('xoirino').first, startsWith('Χοιρ'), reason: 'το x ως χ δουλεύει όπως πριν');
      expect(names('mango').first, 'Μάνγκο');
      expect(names('μάνγκο').first, 'Μάνγκο');
    });

    test('Έλεγχος διατροφής 4/11: φραπέ, βραστά, giaurti, augo, xeres, κόλα, πίτα', () {
      // Ο φραπές δεν ανοίγει τη σκόνη (291 kcal/100 g) αλλά τον έτοιμο καφέ.
      expect(names('φραπέ'), ['Στιγμιαίος καφές έτοιμος (χωρίς ζάχαρη)']);
      expect(names('nescafe').contains('Στιγμιαίος καφές (σκόνη)'), isFalse);
      expect(names('μακαρόνια βραστά').first, startsWith('Μακαρόνια (βρασμένα'));
      expect(names('giaurti').first, startsWith('Γιαούρτι'));
      expect(names('augo').first, startsWith('Αυγό'));
      expect(names('xeres').first, 'Φακές (ξερές)', reason: 'όχι «Ντοματίνια» από ρίζα άλλου ονόματος');
      expect(names('κόλα').any((n) => n.startsWith('Σοκολάτα')), isFalse);
      expect(names('πίτα').any((n) => n.contains('χτυπητά')), isFalse);
    });

    test('Ονόματα φαγητών δεν ανοίγουν σκέτο υλικό (καλύτερα κανένα αποτέλεσμα)', () {
      for (final q in ['φασολάδα', 'γαλέτα', 'φλωρίνης']) {
        expect(names(q), isEmpty, reason: q);
      }
      expect(names('σαλάτα').any((n) => n.startsWith('Μαρούλι') || n.startsWith('Ρόκα') || n.startsWith('Μάτσε')), isFalse);
    });

    test('Αλάτι «<x»: από το νάτριο «<x», όχι «<2 g» (γκρέιπφρουτ, κρασί)', () {
      for (final id in ['C13040', 'C5214']) {
        final f = basicFoods().firstWhere((f) => f.id == id);
        expect(f.n['salt']!.lessThan, isTrue);
        expect(f.n['salt']!.value, lessThan(0.01), reason: f.name);
      }
      // Το όριο στρογγυλεύεται προς τα πάνω: <0,0125 → «<0,02», ποτέ «<0,01».
      expect(nValueText(const NValue(0.0125, lessThan: true), digits: 2), '<0,02');
      expect(nValueText(const NValue(0.13, lessThan: true), digits: 2), '<0,13');
    });

    test('Open Food Facts: υγρό → «ανά 100 ml»', () {
      expect(isLiquidQuantity('330 ml'), isTrue);
      expect(isLiquidQuantity('1,5 L'), isTrue);
      expect(isLiquidQuantity('75cl'), isTrue);
      expect(isLiquidQuantity('500 g'), isFalse);
      expect(isLiquidQuantity('2 lb'), isFalse);
      expect(draftFromOff('1', {'quantity': '1 l', 'nutriments': {'energy-kcal_100g': 42}}).perMl, isTrue);
      expect(draftFromOff('1', {'quantity': '400 g', 'nutriments': {'energy-kcal_100g': 42}}).perMl, isFalse);
    });

    test('Μικρές λέξεις (των, σε) και ρίζες στα άλλα ονόματα δεν φέρνουν άσχετα', () {
      expect(names('τόνος').every((n) => n.startsWith('Τόνος')), isTrue, reason: 'όχι «…όλων των ειδών»');
      expect(names('φέτα').take(2), ['Φέτα (πρόβειο και κατσικίσιο)', 'Τυρί τύπου φέτας από αγελαδινό γάλα']);
      // Όσο πληκτρολογώ: «τυ» (→ τυρί), «με» (→ μέλι) δεν δίνουν «Δεν βρέθηκε».
      expect(names('τυ'), isNotEmpty);
      expect(names('με'), isNotEmpty);
      expect(names('ψωμί με').first, startsWith('Ψωμί'));
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
    test('Αδύνατες τιμές ετικέτας δεν περνούν (kJ αντί για kcal, σάκχαρα > υδατάνθρακες)', () {
      expect(impossibleValues({Nk.kcal: 72, Nk.protein: 10, Nk.carbs: 3, Nk.sugars: 3, Nk.fat: 2}), isEmpty);
      expect(impossibleValues({Nk.kcal: 1500}).keys, [Nk.kcal]);
      expect(impossibleValues({Nk.salt: 100, Nk.fat: 100, Nk.kcal: 900}), isEmpty);
      // Μάλλον λάθος, αλλά αποθηκεύεται (προειδοποίηση).
      expect(impossibleValues({Nk.carbs: 10, Nk.sugars: 20}), isEmpty);
      expect(doubtfulValues({Nk.carbs: 10, Nk.sugars: 20}).keys, [Nk.sugars]);
      expect(doubtfulValues({Nk.fat: 5, Nk.satFat: 9}).keys, [Nk.satFat]);
      expect(doubtfulValues({Nk.protein: 50, Nk.carbs: 40, Nk.fat: 30}).keys, ['total']);
      // Σπόροι chia με αμερικάνικη ετικέτα (ίνες μέσα στους υδατάνθρακες): καμία προειδοποίηση.
      expect(doubtfulValues({Nk.protein: 17, Nk.carbs: 42, Nk.fat: 31, Nk.fiber: 34}), isEmpty);
    });
    test('Αριθμοί όπως στα ελληνικά', () {
      expect(parseNumber('12,5'), 12.5);
      expect(parseNumber('12.5'), 12.5);
      expect(parseNumber('1.000'), 1000);
      expect(parseNumber('1.250,5'), 1250.5);
      expect(parseNumber('0.500'), 0.5);
      expect(parseNumber(''), isNull);
      expect(gramsField(112.5), '112,5');
      expect(gramsField(120), '120');
    });
  });

  group('Ωμό και μαγειρεμένο', () {
    final s = FoodStore.preloaded(foods: basicFoods());
    test('Από το ωμό και από το βρασμένο βγαίνουν οι ίδιες καταστάσεις', () {
      final raw = foodNamed('Μακαρόνια (ξηρά, ωμά)');
      final cooked = foodNamed('Μακαρόνια (βρασμένα, χωρίς αλάτι)');
      final a = [for (final x in s.statesOf(raw)) x.$2];
      final b = [for (final x in s.statesOf(cooked)) x.$2];
      expect(a, ['Ωμά', 'Βρασμένα'], reason: 'round8 R8-A2-4: «ωμά» στο γένος του ονόματος «(ξηρά, ωμά)»');
      expect(b, a);
    });
    test('Πατάτα: ωμή, βραστή, φούρνου', () {
      final p = foodNamed('Πατάτα (ωμή, ξεφλουδισμένη)');
      expect([for (final x in s.statesOf(p)) x.$2], ['Ωμή', 'Βραστή', 'Φούρνου'], reason: 'round8 R8-A2-4: «(ωμή, …)»');
    });
    test('Όσπρια: «Ξερές» στο γένος του ονόματος· το «Κρεμμύδι ξερό» είναι ωμό', () {
      expect(s.statesOf(foodNamed('Φακές (ξερές)')).first.$2, 'Ξερές (πριν το βράσιμο)');
      final onion = basicFoods().where((f) => f.name.startsWith('Κρεμμύδι ξερό') && f.isRawWithCooked);
      for (final o in onion) {
        expect(s.statesOf(o).first.$2, 'Ωμό');
      }
    });
    test('Νέες βρασμένες μορφές: κριθαράκι, χυλοπίτες, parboiled', () {
      expect([for (final x in s.statesOf(foodNamed('Κριθαράκι (ξηρό, ωμό)'))) x.$2], ['Ωμό', 'Βρασμένο']);
      expect(s.statesOf(foodNamed('Χυλοπίτες/ζυμαρικά με αυγό (ξηρά, ωμά)')).length, 2);
      expect(s.statesOf(foodNamed('Ρύζι parboiled (ωμό)')).length, 2);
    });
    test('Καταχώριση που ξαναδιαβάστηκε από το κινητό: οι μορφές βγαίνουν από τη βάση', () {
      final raw = foodNamed('Ρύζι λευκό (ωμό)');
      final e = LogEntry(id: 'x', day: '2026-10-24', meal: Meal.lunch, food: raw, grams: 80, time: DateTime(2026, 10, 24, 13));
      final back = LogEntry.fromJson(e.toJson());
      final states = s.statesOf(back.food);
      expect(states.length, 2);
      expect(identical(states.first.$1, back.food), isTrue, reason: 'η ίδια μορφή μένει το αντίγραφο της καταχώρισης');
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
      final feta = foodNamed('Φέτα (πρόβειο και κατσικίσιο)');
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

    test('Η συχνότητα δεν βγάζει πρώτο άλλο τρόφιμο από αυτό που γράφω', () async {
      final now = DateTime(2026, 10, 24, 13);
      final s = FoodStore.preloaded(foods: basicFoods(), now: now);
      final eggplant = foodNamed('Μελιτζάνα (ωμή)');
      final pepper = foodNamed('Πιπεριά κόκκινη (ωμή)');
      final jam = foodNamed('Μαρμελάδα φράουλα');
      final noodles = foodNamed('Χυλοπίτες/ζυμαρικά με αυγό (ξηρά, ωμά)');
      for (var i = 0; i < 10; i++) {
        await s.add(eggplant, 200, Meal.lunch);
        await s.add(pepper, 100, Meal.lunch);
        await s.add(jam, 20, Meal.breakfast);
        await s.add(noodles, 80, Meal.dinner);
      }
      expect(s.search('αυγό').first.name, 'Αυγό (ωμό)');
      expect(s.search('μέλι').first.name, 'Μέλι');
      expect(s.search('πιπέρι').first.name, 'Πιπέρι μαύρο');
      expect(s.search('φράουλες').first.name, 'Φράουλες');
      // Ανάμεσα σε ίδια ταιριάσματα, το συχνό πρώτο.
      expect(s.search('μαρμελάδα').first.name, 'Μαρμελάδα φράουλα');
    });

    test('«γάλα» χωρίς ιστορικό: πρώτο το αγελαδινό 1,5%', () {
      final s = FoodStore.preloaded(foods: basicFoods(), now: DateTime(2026, 10, 24));
      expect(s.search('γάλα').first.name, 'Γάλα ημιαποβουτυρωμένο 1,5%');
      expect(s.search('λεμόνι').first.name, 'Λεμόνι');
    });

    test('Τρόφιμο που άλλαξε σε νεότερη λίστα: προτείνεται η σωστή, τωρινή μορφή', () async {
      final foods = basicFoods();
      final ids = {for (final f in foods) f.id};
      for (final e in replacedFoods.entries) {
        expect(ids.contains(e.key), isFalse, reason: '${e.key} υπάρχει ακόμα');
        expect(ids.contains(e.value), isTrue, reason: '${e.value} λείπει');
      }
      for (final r in removedFoods) {
        expect(ids.contains(r), isFalse);
      }
      final now = DateTime(2026, 10, 24, 13);
      final oldRice = Food.fromJson({
        'id': 'C9103', 'name': 'Ρύζι καστανό/ολικής (βρασμένο)', 'cat': 'Δημητριακά', 'source': 'CIQUAL 2025',
        'n': {'kcal': 187, 'protein': 4, 'carbs': 38, 'fat': 1.5},
      });
      final oldCream = Food.fromJson({
        'id': 'C19402', 'name': 'Κρέμα γάλακτος (μέσος όρος)', 'cat': 'Γαλακτοκομικά', 'source': 'CIQUAL 2025',
        'n': {'kcal': 248, 'protein': 2, 'carbs': 3, 'fat': 25},
      });
      final s = FoodStore.preloaded(foods: foods, now: now, entries: [
        LogEntry(id: 'r1', day: '2026-10-23', meal: Meal.lunch, food: oldRice, grams: 200, time: DateTime(2026, 10, 23, 13)),
        LogEntry(id: 'r2', day: '2026-10-22', meal: Meal.lunch, food: oldRice, grams: 200, time: DateTime(2026, 10, 22, 13)),
        LogEntry(id: 'c1', day: '2026-10-23', meal: Meal.dinner, food: oldCream, grams: 50, time: DateTime(2026, 10, 23, 20)),
      ]);
      expect(s.recent().map((f) => f.id), ['U169704'], reason: 'νέο id· η κρέμα που βγήκε δεν προτείνεται');
      expect(s.frequent().single.id, 'U169704');
      expect(s.timesEaten('U169704'), 2);
      // Οι παλιές μέρες κρατούν τις τιμές τους.
      expect(s.entriesFor(DateTime(2026, 10, 23), Meal.lunch).single.food.n.amount(Nk.kcal), 187);
      final copied = await s.copyMeal(DateTime(2026, 10, 23), Meal.lunch, DateTime(2026, 10, 24));
      expect(copied.single.food.id, 'U169704');
    });

    test('Δικό μου προϊόν που σβήστηκε: δεν ξαναπροτείνεται, οι παλιές μέρες κρατούν τις τιμές (έλεγχος 8/11)', () async {
      final now = DateTime(2026, 10, 24, 13);
      final bar = Food.fromJson({
        'id': 'L1', 'name': 'Μπάρα (λάθος τιμές)', 'cat': 'Τα δικά μου', 'source': 'Ετικέτα',
        'n': {'kcal': 900, 'protein': 10, 'carbs': 60, 'fat': 70},
      });
      final s = FoodStore.preloaded(foods: basicFoods(), now: now, mine: [bar], entries: [
        LogEntry(id: 'b1', day: '2026-10-23', meal: Meal.snack, food: bar, grams: 40, time: DateTime(2026, 10, 23, 11)),
        LogEntry(id: 'b2', day: '2026-10-22', meal: Meal.snack, food: bar, grams: 40, time: DateTime(2026, 10, 22, 11)),
      ]);
      expect(s.recent().map((f) => f.id), contains('L1'));
      expect(s.frequent().map((f) => f.id), contains('L1'));
      await s.deleteMyFood(bar);
      expect(s.recent().map((f) => f.id), isNot(contains('L1')));
      expect(s.frequent().map((f) => f.id), isNot(contains('L1')));
      expect(s.entriesFor(DateTime(2026, 10, 23), Meal.snack).single.food.n.amount(Nk.kcal), 900);
    });

    test('Διόρθωση προϊόντος: βρίσκει τις καταχωρίσεις με τις παλιές τιμές και τις διορθώνει', () async {
      final now = DateTime(2026, 10, 24, 13);
      final yog = Food.fromJson({
        'id': 'M1', 'name': 'Γιαούρτι Χ', 'cat': 'Τα προϊόντα μου', 'source': 'Ετικέτα',
        'n': {'kcal': 60, 'protein': 3.5, 'carbs': 4, 'fat': 2},
      });
      final s = FoodStore.preloaded(foods: basicFoods(), mine: [yog], now: now);
      await s.add(yog, 170, Meal.breakfast);
      final fixed = Food.fromJson({...yog.toJson(), 'n': {'kcal': 60, 'protein': 10, 'carbs': 4, 'fat': 2}});
      expect(s.entriesWithOldValues(yog), isEmpty);
      final old = s.entriesWithOldValues(fixed);
      expect(old.length, 1);
      expect(await s.applyFoodToEntries(fixed, old), 1);
      expect(s.entriesFor(now).single.total(Nk.protein), closeTo(17, 1e-9));
    });

    test('Αντίγραφο τιμών στην καταχώριση (JSON πάει και έρχεται)', () {
      final f = foodNamed('Μέλι');
      final e = LogEntry(id: 'a', day: '2026-10-24', meal: Meal.breakfast, food: f, grams: 15, time: DateTime(2026, 10, 24, 9));
      final json = e.toJson();
      final back = LogEntry.fromJson(json.map((k, v) => MapEntry(k, v)));
      expect(back.total(Nk.kcal), closeTo(e.total(Nk.kcal), 1e-9));
      expect(back.food.source, f.source);
      expect(back.food.name, f.name);
      // Το αντίγραφο δεν κουβαλά τα στοιχεία αναζήτησης (υπάρχουν στη βάση).
      expect((json['food'] as Map).containsKey('aliases'), isFalse);
      expect((json['food'] as Map).containsKey('sourceName'), isFalse);
    });
  });

  group('Η κουζίνα μου', () {
    test('Αρχική κατάσταση από το αρχείο του χρήστη και αποθήκευση', () {
      final k = Kitchen.fromJson(null);
      expect(k.has('steamer'), isTrue);
      expect(k.steamerTiers, 2);
      expect(k.has('airFryer'), isFalse);
      expect(k.cookware.where((c) => c.kind == 'panNonstick').length, 3);
      final back = Kitchen.fromJson(k.toJson());
      expect(back.cookware.first.label, k.cookware.first.label);
      expect(back.devices, k.devices);
      expect(back.cookware.where((c) => c.kind == 'pot').map((c) => c.size), ['Μικρό', 'Μεσαίο', 'Μεγάλο']);
      expect(back.hob, 'Κεραμικά');
      // Round 9 (R9-U2 ΒΕΛΤΙΩΣΗ-Α): αδιάσπαστο κενό πριν από το «·».
      expect(back.cookware.firstWhere((c) => c.kind == 'pot').label, 'Κατσαρόλα · μικρή');
      expect(back.cookware.first.label, 'Τηγάνι αντικολλητικό · μικρό · Tefal');
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
      expect(k.cookware.first.brand, 'Tefal');
      expect(k.cookware.first.toJson().containsKey('tare'), isFalse);
      expect(k.cookware.where((c) => c.kind == 'pot').length, 3);
      expect(k.cookware.where((c) => c.kind == 'glass').single.brand, 'Pyrex');
      // Δεύτερο άνοιγμα: τίποτα δεν διπλασιάζεται.
      final again = Kitchen.fromJson(k.toJson());
      expect(again.cookware.length, k.cookware.length);
    });
  });

  group('Ίδιο με χθες', () {
    test('Αντιγράφει το γεύμα με τις ίδιες ποσότητες και σειρά, σε άλλη μέρα', () async {
      final now = DateTime(2026, 10, 24, 20);
      final store = sampleFoodStore(now);
      final today = DateTime(2026, 10, 24);
      final yesterday = DateTime(2026, 10, 23);
      expect(store.entriesFor(today, Meal.dinner), isEmpty);
      final source = store.entriesFor(yesterday, Meal.dinner);
      expect(source, isNotEmpty);

      final added = await store.copyMeal(yesterday, Meal.dinner, today);
      final copied = store.entriesFor(today, Meal.dinner);
      expect(copied.length, source.length);
      expect([for (final e in copied) e.food.id], [for (final e in source) e.food.id]);
      expect([for (final e in copied) e.grams], [for (final e in source) e.grams]);
      expect(Totals(copied).kcal, closeTo(Totals(source).kcal, 0.001));
      // Τα χθεσινά μένουν όπως ήταν.
      expect(store.entriesFor(yesterday, Meal.dinner).length, source.length);

      for (final e in added) {
        await store.remove(e);
      }
      expect(store.entriesFor(today, Meal.dinner), isEmpty);
    });
  });
}
