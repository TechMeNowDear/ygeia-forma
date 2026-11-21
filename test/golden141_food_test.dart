// golden141 · ΔΙΑΤΡΟΦΗ (έλεγχος 20/11/2026): στιγμιότυπο των υπολογισμών του σημερινού κώδικα για τρόφιμα και σύνολα
// ημέρας (food_model, food_store), μονάδες (units), φαγητά και πρόγραμμα εβδομάδας (dishes, week_calc, week, week_auto,
// library), χοληστερόλη (chol), συνταγές (recipe), κουζίνα (kitchen), υποδείξεις ζυγίσματος (weigh_hints), Open Food
// Facts (off), αναζήτηση (food_search) και τα ντετερμινιστικά του AI φαγητού (ai_food). Καμία κλήση δικτύου, καμία ώρα
// συστήματος. Βιβλιοθήκη φαγητών και καταγραφές επινοημένες· οι αριθμοί των τροφίμων έρχονται από τη βάση της εφαρμογής
// (assets/foods/basic_foods.json): αν αλλάξει η βάση, αλλάζουν και αυτά τα στιγμιότυπα (και πρέπει να φαίνεται).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/food/ai_food.dart';
import 'package:ygeia_forma/food/chol.dart';
import 'package:ygeia_forma/food/dishes.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_search.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/food/kitchen.dart';
import 'package:ygeia_forma/food/library.dart';
import 'package:ygeia_forma/food/off.dart';
import 'package:ygeia_forma/food/recipe.dart';
import 'package:ygeia_forma/food/units.dart';
import 'package:ygeia_forma/food/week.dart';
import 'package:ygeia_forma/food/week_auto.dart';
import 'package:ygeia_forma/food/week_calc.dart';
import 'package:ygeia_forma/food/weigh_hints.dart';

import 'golden141_common.dart';
import 'sample_food.dart';

final _monday = DateTime(2026, 11, 23);

// Τρόφιμα της βάσης που χρησιμοποιούν και οι υπάρχουσες δοκιμές (week_auto_test, ai_food_test).
const _lentils = 'C20359', _chickpeas = 'C20516', _beans = 'C20501', _oil = 'C17270', _onion = 'C20034', _tomato = 'C20385';
const _chicken = 'C36017', _rice = 'C9100', _yogurt = 'U170894', _feta = 'C12066', _salmon = 'C26036', _bream = 'C26088';
const _beef = 'C6206', _apple = 'C13039', _rusks = 'C7340', _salt = 'C11017', _egg = 'C22000', _tunaCan = 'C26039';

String _nameOf(String id) => basicFoods().firstWhere((f) => f.id == id).name;
Food _dbFood(String id) => basicFoods().firstWhere((f) => f.id == id);

String _n2(double? v) => v == null ? '-' : v.toStringAsFixed(2);
String _n1(double? v) => v == null ? '-' : v.toStringAsFixed(1);

// --------------------------------------------------------------------------------------------- βοηθητικά τροφίμων

/// Επινοημένο τρόφιμο (όχι από τη βάση): οι κανόνες δοκιμάζονται με γνωστούς αριθμούς.
Food _mk(String id, String name, String cat, Map<String, double> n,
        {String source = 'Δοκιμή',
        bool spoon = false,
        bool spoonNo = false,
        bool fruitVeg = false,
        String? cholKind,
        String? rawId,
        String? cookedLabel,
        List<(String, String)> cooked = const [],
        bool perMl = false,
        Set<String> lessThan = const {}}) =>
    Food(
      id: id,
      name: name,
      cat: cat,
      source: source,
      spoon: spoon,
      spoonNo: spoonNo,
      fruitVeg: fruitVeg,
      cholKind: cholKind,
      rawId: rawId,
      cookedLabel: cookedLabel,
      cooked: cooked,
      perMl: perMl,
      n: Nutrients({for (final e in n.entries) e.key: NValue(e.value, lessThan: lessThan.contains(e.key))}),
    );

LogEntry _le(Food f, double g, {Meal meal = Meal.lunch, bool est = false, int hour = 14, String day = '2026-11-23'}) => LogEntry(
    id: 'e-${f.id}-$g-$hour', day: day, meal: meal, food: f, grams: g, time: DateTime(2026, 11, 23, hour), est: est);

Map<String, Object?> _totals(Totals t) => <String, Object?>{
      'kcal': t.kcal,
      'protein': t.protein,
      'carbs': t.carbs,
      'fat': t.fat,
      'fiber': t.fiber,
      'sugars': t.sugars,
      'salt': t.salt,
      'satFat': t.satFat,
      'alcohol': t.alcohol,
      'count': t.count,
      'estKcal': t.estKcal,
      'shownKcal': t.shownKcal,
      'missing': t.missing,
    };

String _tShort(Totals? t) => t == null
    ? 'null'
    : '${_n1(t.kcal)} kcal · πρωτ ${_n1(t.protein)} · υδατ ${_n1(t.carbs)} · λιπ ${_n1(t.fat)} · κορ ${_n2(t.satFat)} · ίνες ${_n1(t.fiber)} · '
        'σάκχ ${_n1(t.sugars)} · αλάτι ${_n2(t.salt)} · λείπουν ${t.missing}';

String _items(List<DishItem>? items) => items == null ? 'null' : [for (final i in items) '${i.id}=${_n2(i.amount)}'].join(' ');

Map<String, Object?> _cholDay(CholDay d, {int goal = 2150}) => <String, Object?>{
      'count': d.count,
      'kcal': d.kcal,
      'satFat': d.satFat,
      'fiber': d.fiber,
      'salt': d.salt,
      'missing': '${d.satMissing}|${d.fiberMissing}|${d.saltMissing}',
      'nutsG': d.nutsG,
      'branG': d.branG,
      'legumesDryG': d.legumesDryG,
      'fishG': d.fishG,
      'legumes': d.legumes,
      'fish': d.fish,
      'part': d.part,
      'fullFor': d.fullFor(goal),
      'satPct': d.satPct,
    };

Map<String, Object?> _cholWeek(CholWeek w) => <String, Object?>{
      'fullDays': w.fullDays,
      'satPctMean': w.satPctMean,
      'fiberMean': w.fiberMean,
      'daysSatUnknown': w.daysSatUnknown,
      'daysFiberUnknown': w.daysFiberUnknown,
      'daysWithNuts30': w.daysWithNuts(30),
      'daysWithBran40': w.daysWithBran(40),
      'daysSaltOk5': w.daysSaltOk(5),
      'daysSaltUnknown': w.daysSaltUnknown,
      'legumes': w.legumes,
      'fish': w.fish,
    };

Map<String, Object?> _draft(FoodDraft d) => g141Compact(<String, Object?>{
      'name': d.name,
      'brand': d.brand,
      'barcode': d.barcode,
      'servingGrams': d.servingGrams,
      'servingLabel': d.servingLabel,
      'values': d.values,
      'fromOff': d.fromOff,
      'perMl': d.perMl,
      'alcohol': d.alcohol,
      'polyols': d.polyols,
      'erythritol': d.erythritol,
      'saltFromSodium': d.saltFromSodium,
      'sodiumMg': d.sodiumMg,
      'lessThan': (d.lessThan.toList()..sort()),
      'cholKind': d.cholKind,
      'spoon': d.spoon,
      'fruitVeg': d.fruitVeg,
      'missing': d.missing,
    });

// ------------------------------------------------------------------- τρόφιμα, σύνολα, μονάδες, OFF, χοληστερόλη

Map<String, Object?> _modelGolden() {
  final out = <String, Object?>{};
  out['constants'] = <String, Object?>{
    'maxEntryGrams': maxEntryGrams,
    'typoEntryKcal': typoEntryKcal,
    'typoEntryBigGrams': typoEntryBigGrams,
    'typoEntryBigKcal': typoEntryBigKcal,
    'typoFatPer100': typoFatPer100,
    'typoFatGrams': typoFatGrams,
    'typoDensePer100': typoDensePer100,
    'typoDenseGrams': typoDenseGrams,
    'typoTimesLast': typoTimesLast,
    'typoTimesLastKcal': typoTimesLastKcal,
    'typoSaltPer100': typoSaltPer100,
    'typoSaltGrams': typoSaltGrams,
    'spoonSpreadKcal': spoonSpreadKcal,
    'rawCheckKcal': rawCheckKcal,
    'rawCheckGrams': rawCheckGrams,
    'dayMarksKeepDays': dayMarksKeepDays,
    'fruitVegTargetG': fruitVegTargetG,
    'fruitVegCats': (fruitVegCats.toList()..sort()),
    'fruitVegExclude': (fruitVegExclude.toList()..sort()),
    'fruitVegFormMaxKcal': fruitVegFormMaxKcal,
    'cholKinds': CholKind.all,
    'branFoodId': branFoodId,
    'legumesDryMinG': legumesDryMinG,
    'legumesCookedFactor': legumesCookedFactor,
    'fishMinG': fishMinG,
    'legumesDryMinKcal': legumesDryMinKcal,
    'myUnitMinG': myUnitMinG,
    'myUnitMaxG': myUnitMaxG,
    'myFoodsCategory': myFoodsCategory,
    'draftRequired': FoodDraft.required,
  };

  // Τιμές θρεπτικών.
  out['NValue'] = <String, Object?>{
    for (final e in <String, Object?>{
      'number': 12.5,
      'int': 3,
      'traces': {'tr': true},
      'lessThan': {'lt': 0.5},
      'lt text': {'lt': 'x'},
      'text': 'x',
      'null': null,
    }.entries)
      e.key: () {
        final v = NValue.fromJson(e.value);
        return v == null ? null : <String, Object?>{'json': v.toJson(), 'amount': v.amount, 'text': nValueText(v), 'text2': nValueText(v, digits: 2)};
      }(),
    'nValueText null': nValueText(null),
    'nValueText <': <String, Object?>{
      for (final x in [0.0125, 0.04, 0.05, 0.1, 0.11, 0.5, 5.0]) '$x': '${nValueText(NValue(x, lessThan: true))} | ${nValueText(NValue(x, lessThan: true), digits: 2)}',
    },
  };
  out['validServing'] = <String, Object?>{
    for (final v in <Object?>[null, 'x', 0, -1, 0.1, 170, 5000, 5000.1, double.nan, double.infinity]) '$v': validServing(v),
  };
  out['validMyUnit'] = <String, Object?>{
    for (final v in <Object?>[null, 'x', 0.99, 1, 150.5, 2000, 2000.1, double.nan]) '$v': validMyUnit(v),
  };
  out['CholKind.parse'] = <String, Object?>{for (final v in <Object?>['nuts', 'legumes', 'fish', 'bran', 'none', 'meat', 5, null]) '$v': CholKind.parse(v)};
  out['dayMarkOf'] = <String, Object?>{for (final v in <Object?>['done', 'part', 'x', null]) '$v': dayMarkOf(v)?.name};

  // Τρόφιμο από/σε JSON.
  final fj = <String, dynamic>{
    'id': 'X1',
    'name': 'Δοκιμαστικό',
    'cat': 'Όσπρια',
    'aliases': ['α', 5],
    'source': 'Open Food Facts',
    'sourceCode': 12,
    'sourceName': 'Test',
    'brand': 'Μάρκα',
    'barcode': '5200000000017',
    'energyCalc': true,
    'servingGrams': 170,
    'servingLabel': '1 κεσές',
    'rawId': 'X0',
    'cookedLabel': 'Βρασμένο',
    'perMl': true,
    'ck': 'legumes',
    'sp': false,
    'fv': true,
    'cooked': [
      {'id': 'X2', 'label': 'Ψητό'},
      'x',
    ],
    'n': {
      'kcal': 120,
      'protein': {'lt': 0.5},
      'fat': {'tr': true},
      'junk': 'x',
    },
  };
  Map<String, Object?> foodView(Food f) => <String, Object?>{
        'json': f.toJson(),
        'snapshotKeys': (f.toSnapshotJson().keys.toList()..sort()),
        'isRawWithCooked': f.isRawWithCooked,
        'isCooked': f.isCooked,
        'isMine': f.isMine,
        'unit': f.unit,
      };
  out['Food.fromJson'] = <String, Object?>{
    'full': foodView(Food.fromJson(fj)),
    'minimal': foodView(Food.fromJson(<String, dynamic>{'id': 'X3', 'name': 'Ελάχιστο', 'n': <String, dynamic>{}})),
    'serving 0': Food.fromJson(<String, dynamic>{...fj, 'servingGrams': 0}).servingGrams,
    'serving 5000.1': Food.fromJson(<String, dynamic>{...fj, 'servingGrams': 5000.1}).servingGrams,
    'sp true': Food.fromJson(<String, dynamic>{...fj, 'sp': true}).toJson()['sp'],
    'ck unknown': Food.fromJson(<String, dynamic>{...fj, 'ck': 'meat'}).cholKind,
    'source Ετικέτα': Food.fromJson(<String, dynamic>{...fj, 'source': 'Ετικέτα'}).isMine,
    'source CIQUAL': Food.fromJson(<String, dynamic>{...fj, 'source': 'CIQUAL 2025'}).isMine,
  };

  // Γεύματα.
  out['mealLabel'] = <String, Object?>{for (final m in Meal.values) m.name: mealLabel(m)};
  out['mealForTime (λεπτά 0, 29, 30, 59)'] = <String, Object?>{
    for (var h = 0; h < 24; h++)
      h.toString().padLeft(2, '0'): [for (final m in [0, 29, 30, 59]) mealForTime(DateTime(2026, 11, 23, h, m)).name[0]].join(),
  };

  // Επινοημένα τρόφιμα με γνωστούς αριθμούς.
  final chicken = _mk('T1', 'Κοτόπουλο δοκιμής', 'Πουλερικά', {Nk.kcal: 110, Nk.protein: 23.4, Nk.carbs: 0, Nk.fat: 1.5, Nk.satFat: 0.44, Nk.salt: 0.107, Nk.fiber: 0, Nk.sugars: 0});
  final oil = _mk('T2', 'Λάδι δοκιμής', 'Λιπαρά', {Nk.kcal: 899, Nk.protein: 0, Nk.carbs: 0, Nk.fat: 99.9, Nk.satFat: 15.2});
  final olives = _mk('T3', 'Ελιές δοκιμής', 'Λιπαρά', {Nk.kcal: 300, Nk.fat: 30, Nk.salt: 3});
  final spread500 = _mk('T4', 'Άλειμμα 500', 'Αλείμματα', {Nk.kcal: 500, Nk.fat: 40});
  final spread499 = _mk('T5', 'Άλειμμα 499', 'Αλείμματα', {Nk.kcal: 499, Nk.fat: 40});
  final flagged = _mk('T6', 'Ταχίνι δικό μου', 'Τα προϊόντα μου', {Nk.kcal: 240, Nk.fat: 20}, source: 'Ετικέτα', spoon: true);
  final fat80 = _mk('T7', 'Λίπος 80', 'Άλλα', {Nk.kcal: 240, Nk.fat: 80});
  final fat799 = _mk('T8', 'Λίπος 79,9', 'Άλλα', {Nk.kcal: 240, Nk.fat: 79.9});
  final dense250 = _mk('T9', 'Πυκνό 250', 'Άλλα', {Nk.kcal: 250, Nk.fat: 5});
  final dense249 = _mk('T10', 'Πυκνό 249', 'Άλλα', {Nk.kcal: 249, Nk.fat: 5});
  final salty50 = _mk('T11', 'Αλμυρό 50', 'Καρυκεύματα', {Nk.kcal: 0, Nk.salt: 50});
  final salty499 = _mk('T12', 'Αλμυρό 49,9', 'Καρυκεύματα', {Nk.kcal: 0, Nk.salt: 49.9});
  final water = _mk('T13', 'Νερό δοκιμής', 'Ροφήματα', {Nk.kcal: 0}, perMl: true);
  final wine = _mk('T14', 'Κρασί δοκιμής', 'Ροφήματα', {Nk.kcal: 83, Nk.alcohol: 10.5, Nk.carbs: 2.6}, perMl: true);
  final typoFoods = [chicken, oil, olives, spread500, spread499, flagged, fat80, fat799, dense250, dense249, salty50, salty499, water];
  const grams = [9.0, 10.0, 19.9, 20.0, 99.0, 100.0, 222.0, 223.0, 299.0, 300.0, 454.0, 455.0, 999.0, 1000.0, 1818.0, 1819.0];
  out['typo grams'] = grams;
  out['entryLooksLikeTypo'] = <String, Object?>{
    for (final f in typoFoods)
      f.name: <String, Object?>{
        'spoon': isSpoonFood(f),
        'olives': isOlives(f),
        for (final last in <double?>[null, 10, 60])
          'last=$last': [for (final g in grams) entryLooksLikeTypo(f, g, lastGrams: last) ? '1' : '0'].join(),
      },
  };
  final rawWithCooked = _mk('T15', 'Ρύζι δοκιμής (ωμό)', 'Δημητριακά', {Nk.kcal: 350}, cooked: const [('T16', 'Βρασμένο')]);
  final raw299 = _mk('T17', 'Όσπριο δοκιμής (ξερό)', 'Όσπρια', {Nk.kcal: 299}, cooked: const [('T18', 'Βρασμένο')]);
  out['askRawOrCooked'] = <String, Object?>{
    for (final (name, f) in [('ωμό 350 kcal', rawWithCooked), ('ωμό 299 kcal', raw299), ('χωρίς μαγειρεμένη μορφή', dense250)])
      for (final g in [149.0, 150.0])
        for (final times in [0, 1])
          for (final dry in [false, true]) '$name|$g g|φορές $times|ξερό δικό μου $dry': askRawOrCooked(f, g, timesEaten: times, dryMine: dry),
  };
  out['gramsText'] = <String, Object?>{
    for (final v in [0.0, 0.04, 0.05, 0.5, 1.0, 2.25, 9.94, 9.95, 10.0, 10.4, 10.5, 99.4, 99.5, 100.0, 1234.5]) '$v': gramsText(v),
  };
  out['kcalText'] = <String, Object?>{for (final v in [0.0, 0.5, 999.4, 999.5, 1000.0, 12345.6]) '$v': kcalText(v)};

  // Σύνολα: κάθε πεδίο του Totals, με εκτίμηση, ίχνη/«<», θρεπτικά που λείπουν.
  final traces = Food.fromJson(<String, dynamic>{
    'id': 'T20',
    'name': 'Με ίχνη',
    'cat': 'Άλλα',
    'n': {
      'kcal': 87.6,
      'protein': 1.06,
      'carbs': 19.7,
      'fat': {'lt': 0.5},
      'satFat': {'lt': 0.01},
      'sugars': {'tr': true},
      'salt': {'lt': 0.0125},
      'fiber': 2.7,
    },
  });
  final day = [
    _le(chicken, 180),
    _le(oil, 10.5),
    _le(olives, 33.3, est: true),
    _le(traces, 120, meal: Meal.snack, hour: 16),
    _le(wine, 150, meal: Meal.dinner, hour: 21, est: true),
    _le(dense250, 47.4, meal: Meal.dinner, hour: 21),
  ];
  out['Totals'] = <String, Object?>{
    'empty': _totals(Totals(const [])),
    'day': _totals(Totals(day)),
    'entry totals': [for (final e in day) '${e.food.name} ${e.grams} g → ${_n2(e.total(Nk.kcal))} kcal, ${_n2(e.total(Nk.protein))} πρωτ'],
    'copyWith': _le(chicken, 180).copyWith(grams: 200, meal: Meal.dinner, est: true, day: '2026-11-24', id: 'z').toJson(),
    'json round trip': LogEntry.fromJson(Map<String, dynamic>.from(_le(traces, 120, est: true).toJson())).toJson(),
    'unknown meal → snack': LogEntry.fromJson(<String, dynamic>{..._le(chicken, 50).toJson(), 'meal': 'brunch'}).meal.name,
  };

  // Φρούτα και λαχανικά.
  final fv = [
    _mk('F1', 'Φρούτο δοκιμής', 'Φρούτα', {Nk.kcal: 50}),
    _mk('F2', 'Λαχανικό δοκιμής', 'Λαχανικά', {Nk.kcal: 20}),
    _mk('C2007', 'Εκτός (χυμός)', 'Φρούτα', {Nk.kcal: 45}),
    _mk('C20068', 'Εκτός (πελτές)', 'Λαχανικά', {Nk.kcal: 99}),
    _mk('C20170', 'Εκτός (τρίτο)', 'Λαχανικά', {Nk.kcal: 30}),
    _mk('F3', 'Προϊόν με σήμανση', 'Τα προϊόντα μου', {Nk.kcal: 60}, source: 'Ετικέτα', fruitVeg: true),
    _mk('F4', 'Γλυκό', 'Γλυκά', {Nk.kcal: 400}),
    _mk('F5', 'Αποξηραμένο', 'Αποξηραμένα φρούτα', {Nk.kcal: 280}),
  ];
  out['isFruitVeg'] = <String, Object?>{for (final f in fv) '${f.id} ${f.cat}': isFruitVeg(f)};
  out['fruitVegGrams'] = fruitVegGrams([for (var i = 0; i < fv.length; i++) _le(fv[i], 100.0 + i * 10.5)]);

  // Μονάδες («1 μπανάνα μεσαία»).
  out['pieceUnits'] = <String, Object?>{
    for (final e in pieceUnits.entries)
      e.key: <String, Object?>{
        'unit': '${e.value.one}/${e.value.many} sizeAfter=${e.value.sizeAfter} middle=${e.value.middle.label}:${e.value.middle.grams}',
        'texts': [
          for (final size in e.value.sizes)
            for (final c in [1, 2, 5]) '${size.grams} g × $c → ${pieceText(e.value, size, c)}',
        ],
      },
  };

  // Χοληστερόλη: ποιο τρόφιμο μετρά ως τι.
  final cholFoods = [
    _mk('N1', 'Καρύδια δοκιμής', 'Ξηροί καρποί', {Nk.kcal: 700, Nk.satFat: 6, Nk.fiber: 6, Nk.salt: 0}),
    _mk('C15011', 'Σπόρος στους ξηρούς καρπούς', 'Ξηροί καρποί', {Nk.kcal: 600}),
    _mk('C15025', 'Κουκουνάρι αλλού', 'Σπόροι', {Nk.kcal: 712}),
    _mk('L1', 'Φακές δοκιμής (ξερές)', 'Όσπρια', {Nk.kcal: 327, Nk.satFat: 0.24, Nk.fiber: 16.3, Nk.salt: 0.01}),
    _mk('L2', 'Φακές δοκιμής (βρασμένες)', 'Όσπρια', {Nk.kcal: 116, Nk.satFat: 0.1, Nk.fiber: 7.9, Nk.salt: 0.01}, rawId: 'L1'),
    _mk('L3', 'Ρεβίθια κονσέρβα', 'Όσπρια', {Nk.kcal: 120}),
    _mk('L4', 'Φακές ψιλές μάρκας', 'Τα προϊόντα μου', {Nk.kcal: 330}, source: 'Ετικέτα'),
    _mk('L5', 'Σαλάτα με σήμανση όσπρια', 'Τα προϊόντα μου', {Nk.kcal: 249.9}, source: 'Ετικέτα', cholKind: CholKind.legumes),
    _mk('L6', 'Ξερό με σήμανση όσπρια', 'Τα προϊόντα μου', {Nk.kcal: 250}, source: 'Ετικέτα', cholKind: CholKind.legumes),
    _mk('P1', 'Σολομός δοκιμής', 'Ψάρια', {Nk.kcal: 193, Nk.satFat: 2.15, Nk.fiber: 0, Nk.salt: 0.11}),
    _mk('P2', 'Γαρίδες δοκιμής', 'Θαλασσινά', {Nk.kcal: 90}),
    _mk('P3', 'Ψάρι με σήμανση «όχι»', 'Ψάρια', {Nk.kcal: 200}, cholKind: CholKind.none),
    _mk(branFoodId, 'Πίτουρο βρώμης', 'Δημητριακά', {Nk.kcal: 361, Nk.satFat: 1.16, Nk.fiber: 16.7, Nk.salt: 0.016}),
    _mk('B2', 'Πίτουρο Βρώμης Μάρκα', 'Τα προϊόντα μου', {Nk.kcal: 360}, source: 'Open Food Facts'),
    _mk('B3', 'Ψωμί με πίτουρο βρώμης', 'Ψωμί', {Nk.kcal: 250}),
    _mk('B4', 'Κάτι με σήμανση πίτουρο', 'Άλλα', {Nk.kcal: 100}, cholKind: CholKind.bran),
  ];
  out['chol kinds (bran|nuts|legumes|fish)'] = <String, Object?>{
    for (final f in cholFoods) '${f.id} ${f.name}': '${isBran(f)}|${isNuts(f)}|${isLegumes(f)}|${isFish(f)}',
  };
  Food cf(String id) => cholFoods.firstWhere((f) => f.id == id);
  out['CholDay'] = <String, Object?>{
    'empty': _cholDay(CholDay(const [])),
    'mixed': _cholDay(CholDay([_le(cf('N1'), 30), _le(cf('L1'), 39.9), _le(cf('P1'), 99.9), _le(cf(branFoodId), 39.4), _le(chicken, 500), _le(oil, 60)])),
    'legumes dry 40': _cholDay(CholDay([_le(cf('L1'), 40)])),
    'legumes cooked 99': _cholDay(CholDay([_le(cf('L2'), 99)])),
    'legumes cooked 100': _cholDay(CholDay([_le(cf('L2'), 100)])),
    'legumes canned 100': _cholDay(CholDay([_le(cf('L3'), 100)])),
    'legumes by name 40': _cholDay(CholDay([_le(cf('L4'), 40)])),
    'legumes tagged 249.9 kcal ×100': _cholDay(CholDay([_le(cf('L5'), 100)])),
    'legumes tagged 250 kcal ×40': _cholDay(CholDay([_le(cf('L6'), 40)])),
    'fish 100': _cholDay(CholDay([_le(cf('P1'), 60), _le(cf('P2'), 40)])),
    'part': _cholDay(CholDay([_le(chicken, 2000)], part: true)),
    'full at 1290 kcal': _cholDay(CholDay([_le(dense250, 516)])),
    'not full at 1289 kcal': _cholDay(CholDay([_le(dense250, 515.6)])),
    'fullDayKcalFor': [fullDayKcalFor(2150), fullDayKcalFor(1500)],
  };
  out['reachedGrams'] = <String, Object?>{
    for (final (g, t) in [(29.4, 30), (29.5, 30), (30.0, 30), (39.5, 40), (5.0, 0), (0.0, 0)]) '$g|$t': reachedGrams(g, t),
  };
  out['saltShown'] = <String, Object?>{for (final v in [4.94, 4.95, 4.96, 5.04, 5.05, 0.049]) '$v': saltShown(v)};
  out['satLimit'] = <String, Object?>{
    for (final (kcal, pct) in [(2150, 6), (2150, 10), (2090, 6), (1800, 10), (2250, 6), (1500, 6), (2700, 10)])
      '$kcal|$pct': '${satLimitShown(kcal, pct)} · ${satLimitText(kcal, pct)} · strict=${satStrictPct(pct)}',
    'strict 9/10/11': [satStrictPct(9), satStrictPct(10), satStrictPct(11)],
  };
  out['weekStart'] = <String, Object?>{
    for (final d in [
      for (var i = 0; i < 7; i++) DateTime(2026, 11, 23 + i, 13),
      DateTime(2026, 10, 25, 3, 30),
      DateTime(2026, 10, 26),
      DateTime(2027, 3, 28, 4),
      DateTime(2027, 3, 29),
      DateTime(2027, 1, 1),
      DateTime(2028, 2, 29),
    ])
      g141Day(d): g141Day(weekStart(d)),
  };
  final weekDays = <(DateTime, CholDay)>[
    (DateTime(2026, 11, 23), CholDay([_le(cf('N1'), 30), _le(cf('L1'), 80), _le(chicken, 800), _le(oil, 40)])),
    (DateTime(2026, 11, 24), CholDay([_le(cf('N1'), 29.4), _le(cf('P1'), 150), _le(chicken, 900), _le(cf(branFoodId), 40)])),
    (DateTime(2026, 11, 25), CholDay([_le(cf('P1'), 100)])),
    (DateTime(2026, 11, 26), CholDay([_le(chicken, 1500), _le(salty50, 9)], part: true)),
    (DateTime(2026, 11, 27), CholDay([_le(chicken, 1300), _le(salty50, 9.6), _le(cf('N1'), 31)])),
    (DateTime(2026, 11, 28), CholDay([_le(dense250, 600), _le(cf('L2'), 100)])),
    (DateTime(2026, 11, 29), CholDay(const [])),
  ];
  out['CholWeek'] = <String, Object?>{
    'goal 2150': _cholWeek(CholWeek(weekDays, goalKcal: 2150)),
    'goal 1500': _cholWeek(CholWeek(weekDays, goalKcal: 1500)),
    'empty': _cholWeek(CholWeek(const [], goalKcal: 2150)),
  };

  // Το ημερολόγιο του δείγματος (6 μέρες φαγητού από τη βάση): σύνολα μέρας, γεύματα, συνήθειες.
  final now = DateTime(2026, 11, 23, 16, 30);
  final s = sampleFoodStore(now);
  final days = <String, Object?>{};
  final chol = <(DateTime, CholDay)>[];
  for (var ago = 6; ago >= 0; ago--) {
    final d = DateTime(now.year, now.month, now.day - ago);
    final entries = s.entriesFor(d);
    final c = CholDay(entries);
    chol.add((d, c));
    days[g141Day(d)] = <String, Object?>{
      'totals': _totals(Totals(entries)),
      'perMeal': <String, Object?>{for (final m in Meal.values) m.name: _n1(Totals(s.entriesFor(d, m)).kcal)},
      'fruitVegGrams': fruitVegGrams(entries),
      'chol': _cholDay(c),
      'hasEntries': s.hasEntries(d),
      'dayMark': s.dayMark(d)?.name,
      'copyable lunch': '${s.copyable(d, Meal.lunch).length}/${s.notCopyable(d, Meal.lunch)}',
    };
  }
  final banana = foodNamed('Μπανάνα');
  final lentilsCooked = foodNamed('Φακές (βρασμένες)');
  final changed = Food.fromJson(<String, dynamic>{
    ...banana.toJson(),
    'n': <String, dynamic>{...banana.n.toJson(), 'kcal': 95},
  });
  out['store'] = <String, Object?>{
    'days': days,
    'CholWeek 2150': _cholWeek(CholWeek(chol, goalKcal: 2150)),
    'CholWeek 1200': _cholWeek(CholWeek(chol, goalKcal: 1200)),
    'recent': [for (final f in s.recent(limit: 8)) '${f.id} ${f.name}'],
    'frequent': [for (final f in s.frequent(limit: 8)) '${f.id} ${f.name}'],
    'timesEaten': <String, Object?>{'banana': s.timesEaten(banana.id), 'lentils': s.timesEaten(lentilsCooked.id), 'unknown': s.timesEaten('ZZ')},
    'lastGrams': <String, Object?>{'banana': s.lastGrams(banana.id), 'lentils': s.lastGrams(lentilsCooked.id), 'unknown': s.lastGrams('ZZ')},
    'statesOf': <String, Object?>{
      for (final id in [_lentils, lentilsCooked.id, _salmon, _apple, _egg, 'Mdemo1'])
        id: [for (final st in s.statesOf(s.byId(id) ?? banana)) '${st.$1.id}:${st.$2}'],
    },
    'byBarcode': [s.byBarcode('5200000000017')?.id, s.byBarcode('520 0000 000017')?.id, s.byBarcode('05200000000017')?.id, s.byBarcode('')?.id, s.byBarcode('123')?.id],
    'pickable unknown': s.pickable(_mk('ZZ', 'Άγνωστο', 'Άλλα', {Nk.kcal: 1}))?.id,
    'pickable known': s.pickable(banana)?.id,
    'currentOf unknown': s.currentOf(_mk('ZZ', 'Άγνωστο', 'Άλλα', {Nk.kcal: 1})).id,
    'entriesWithOldValues': s.entriesWithOldValues(changed).length,
    'entriesWithOldValues same': s.entriesWithOldValues(banana).length,
    'groupOf': s.groupOf(s.entriesFor(now).first).length,
    'otherDayShown': [_dayOrDash(s.otherDayShown(now)), _dayOrDash(s.otherDayShown(DateTime(2026, 11, 24)))],
    'entryTime': <String, Object?>{
      for (final (name, d, at) in [
        ('today 14:05', DateTime(2026, 11, 23), DateTime(2026, 11, 23, 14, 5, 6, 7)),
        ('yesterday at 03:59', DateTime(2026, 11, 22), DateTime(2026, 11, 23, 3, 59)),
        ('yesterday at 04:00', DateTime(2026, 11, 22), DateTime(2026, 11, 23, 4, 0)),
        ('two days ago at 02:00', DateTime(2026, 11, 21), DateTime(2026, 11, 23, 2, 0)),
        ('25/10 at 03:30', DateTime(2026, 10, 24), DateTime(2026, 10, 25, 3, 30)),
        ('28/3 at 02:30 target', DateTime(2027, 3, 28), DateTime(2027, 3, 27, 2, 30)),
      ])
        name: FoodStore.entryTime(d, at),
    },
  };

  // Open Food Facts → πρόχειρο προϊόν.
  final products = <String, Map<String, dynamic>>{
    'kcal': {
      'product_name_el': ' Γιαούρτι στραγγιστό 2% ',
      'product_name': 'Greek yogurt',
      'brands': 'Μάρκα Α, Άλλη',
      'serving_size': '170 g',
      'serving_quantity': '170',
      'quantity': '170 g',
      'nutriments': {'energy-kcal_100g': 73, 'energy_100g': 305, 'proteins_100g': '9,6', 'carbohydrates_100g': 3.4, 'sugars_100g': 3.4, 'fat_100g': 2, 'saturated-fat_100g': 1.3, 'fiber_100g': 0, 'salt_100g': 0.1, 'sodium_100g': 0.04},
    },
    'kJ only': {
      'product_name': 'Crackers',
      'nutriments': {'energy_100g': 1900, 'proteins_100g': 10, 'carbohydrates_100g': 60, 'fat_100g': 18},
    },
    'kJ field energy-kj': {
      'nutriments': {'energy-kj_100g': 418.4},
    },
    'kcal 0 with kJ': {
      'generic_name_el': 'Μπάρα',
      'nutriments': {'energy-kcal_100g': 0, 'energy_100g': 1674},
    },
    'kcal 0, kJ 0': {
      'nutriments': {'energy-kcal_100g': 0, 'energy_100g': 0, 'proteins_100g': 0, 'carbohydrates_100g': 0, 'fat_100g': 0},
    },
    'sodium only': {
      'nutriments': {'sodium_100g': 0.4, 'sodium_modifier': '<'},
    },
    'salt 0, sodium 0.5': {
      'nutriments': {'salt_100g': 0, 'salt_modifier': '<', 'sodium_100g': 0.5},
    },
    'salt and sodium': {
      'nutriments': {'salt_100g': 1.2, 'sodium_100g': 0.4},
    },
    'modifiers': {
      'nutriments': {'fat_100g': 0.5, 'fat_modifier': '<', 'saturated-fat_100g': 0.1, 'saturated-fat_modifier': '≤', 'sugars_100g': 0.5, 'sugars_modifier': '<=', 'fiber_100g': 1, 'fiber_modifier': '~'},
    },
    'negative and junk': {
      'nutriments': {'proteins_100g': -1, 'fat_100g': 'πολύ', 'carbohydrates_100g': double.nan, 'energy-kcal_100g': '250.5'},
    },
    'per 100 ml': {
      'product_name': 'Χυμός',
      'nutrition_data_per': '100ml',
      'nutriments': {'energy-kcal_100g': 45},
    },
    'quantity 1 l': {
      'quantity': '1 l',
      'nutrition_data_per': '100g',
      'nutriments': {'energy-kcal_100g': 824},
    },
    'quantity 500 g': {
      'quantity': '500 g',
      'nutriments': <String, dynamic>{},
    },
    'serving 330 ml, no quantity': {
      'serving_size': '330 ml',
      'serving_quantity': 330,
      'nutriments': <String, dynamic>{},
    },
    'serving 30 g (2 ml)': {
      'serving_size': '30 g (2 ml)',
      'nutriments': <String, dynamic>{},
    },
    'serving too big': {
      'serving_quantity': 5000.1,
      'nutriments': <String, dynamic>{},
    },
    'alcohol, polyols': {
      'product_name': 'Μπίρα',
      'quantity': '33 cl',
      'nutriments': {'energy-kcal_100g': 43, 'alcohol_100g': 5, 'polyols_100g': 0, 'erythritol_100g': 101},
    },
    'alcohol field, polyols 12': {
      'nutriments': {'alcohol': '12,5', 'polyols_100g': 12, 'erythritol_100g': 8},
    },
    'nuts': {
      'product_name': 'Αμύγδαλα',
      'categories_tags': ['en:plant-based-foods', 'en:nuts', 'en:almonds'],
      'nutriments': {'energy-kcal_100g': 600},
    },
    'nut butter 600 kcal': {
      'product_name': 'Φυστικοβούτυρο',
      'categories_tags': ['en:spreads', 'en:nut-butters', 'en:peanuts'],
      'nutriments': {'energy-kcal_100g': 600},
    },
    'spread 499 kcal': {
      'categories_tags': ['en:spreads'],
      'nutriments': {'energy-kcal_100g': 499},
    },
    'margarine': {
      'categories_tags': ['EN:Margarines '],
      'nutriments': {'energy-kcal_100g': 350},
    },
    'canned tuna': {
      'categories_tags': ['en:canned-fishes', 'en:tunas'],
      'nutriments': <String, dynamic>{},
    },
    'fish fingers': {
      'categories_tags': ['en:fishes', 'en:fish-fingers'],
      'nutriments': <String, dynamic>{},
    },
    'canned lentils': {
      'categories_tags': ['en:pulses', 'en:canned-lentils'],
      'nutriments': <String, dynamic>{},
    },
    'green beans': {
      'categories_tags': ['en:pulses', 'en:green-beans'],
      'nutriments': <String, dynamic>{},
    },
    'oat bran in cereals': {
      'categories_tags': ['en:breakfast-cereals', 'en:oat-bran'],
      'nutriments': <String, dynamic>{},
    },
    'oat bran by name in flours': {
      'product_name_el': 'Πίτουρο βρώμης',
      'categories_tags': ['en:flours'],
      'nutriments': <String, dynamic>{},
    },
    'oat bran bar': {
      'categories_tags': ['en:oat-bran', 'en:bars'],
      'nutriments': <String, dynamic>{},
    },
    'no tags': {
      'product_name': 'Κάτι',
      'nutriments': <String, dynamic>{},
    },
    'nutriments not a map': {'nutriments': 'x', 'brands': '  '},
  };
  final off = <String, Object?>{};
  for (final e in products.entries) {
    final d = draftFromOff('5200000000017', e.value);
    off[e.key] = <String, Object?>{
      'draft': _draft(d),
      'food': foodFromDraft(d, 'M-${e.key}').toJson(),
    };
  }
  out['draftFromOff'] = off;
  final back = draftFromFood(foodFromDraft(draftFromOff('1', products['kcal']!), 'M1'));
  out['draftFromFood'] = <String, Object?>{
    'round trip': _draft(back),
    'from label, sodium, spoonNo': _draft(draftFromFood(Food.fromJson(<String, dynamic>{
      'id': 'M2',
      'name': 'Ετικέτα',
      'source': 'Ετικέτα',
      'sp': false,
      'fv': true,
      'ck': 'nuts',
      'perMl': true,
      'n': {'kcal': 100, 'protein': {'lt': 0.5}, 'salt': 1.0, 'sodium': 400, 'alcohol': 4, 'polyols': 2, 'erythritol': 1, 'vitC': 5},
    }))),
  };

  out['energyMismatch'] = <String, Object?>{
    'no kcal': energyMismatch({Nk.protein: 10, Nk.carbs: 10, Nk.fat: 10}),
    for (final k in [100.0, 149.0, 150.0, 151.0, 170.0, 189.0, 190.0, 191.0, 211.0, 212.0, 230.0, 300.0])
      'kcal $k (calc 170)': energyMismatch({Nk.kcal: k, Nk.protein: 10, Nk.carbs: 10, Nk.fat: 10}),
    for (final k in [0.0, 20.0, 21.0]) 'kcal $k (calc 0)': energyMismatch({Nk.kcal: k, Nk.protein: 0, Nk.carbs: 0, Nk.fat: 0}),
    'fiber': energyMismatch({Nk.kcal: 100, Nk.protein: 10, Nk.carbs: 10, Nk.fat: 10, Nk.fiber: 20}),
    'alcohol': energyMismatch({Nk.kcal: 43, Nk.protein: 0.5, Nk.carbs: 3, Nk.fat: 0}, alcohol: 3.9),
    'alcohol missing': energyMismatch({Nk.kcal: 43, Nk.protein: 0.5, Nk.carbs: 3, Nk.fat: 0}),
    'polyols': energyMismatch({Nk.kcal: 250, Nk.protein: 5, Nk.carbs: 60, Nk.fat: 10}, polyols: 40),
    'polyols > carbs, erythritol > polyols': energyMismatch({Nk.kcal: 400, Nk.protein: 5, Nk.carbs: 30, Nk.fat: 10}, polyols: 50, erythritol: 80),
    'erythritol': energyMismatch({Nk.kcal: 20, Nk.protein: 0, Nk.carbs: 100, Nk.fat: 0}, polyols: 100, erythritol: 100),
  };
  out['impossibleValues'] = <String, Object?>{
    'ok': impossibleValues({Nk.kcal: 900, Nk.protein: 100, Nk.carbs: 100, Nk.sugars: 100, Nk.fat: 100, Nk.satFat: 100, Nk.fiber: 100, Nk.salt: 100}),
    'all over': impossibleValues({Nk.kcal: 900.1, Nk.protein: 100.1, Nk.carbs: 101, Nk.sugars: 101, Nk.fat: 101, Nk.satFat: 101, Nk.fiber: 101, Nk.salt: 400}),
  };
  out['doubtfulValues'] = <String, Object?>{
    'ok': doubtfulValues({Nk.protein: 30, Nk.carbs: 40, Nk.sugars: 40.5, Nk.fat: 30, Nk.satFat: 30.5, Nk.salt: 5}),
    'sugars > carbs': doubtfulValues({Nk.carbs: 40, Nk.sugars: 40.6}),
    'sat > fat': doubtfulValues({Nk.fat: 30, Nk.satFat: 30.6}),
    'total 105.1': doubtfulValues({Nk.protein: 30, Nk.carbs: 40, Nk.fat: 30, Nk.salt: 5.1}),
    'empty': doubtfulValues(const {}),
  };
  Food mine(String name, {double kcal = 350, String source = 'Ετικέτα', bool perMl = false, String? cholKind}) =>
      _mk('M-$name', name, myFoodsCategory, {Nk.kcal: kcal}, source: source, perMl: perMl, cholKind: cholKind);
  out['dryStapleRawId | legumesByName'] = <String, Object?>{
    for (final name in [
      'Φακές ψιλές',
      'Φακή κόκκινη',
      'Ρεβίθια χονδρά',
      'Ρεβύθια',
      'Φάβα Σαντορίνης',
      'Φασόλια μαυρομάτικα',
      'Γίγαντες ελέφαντες',
      'Φασόλια μέτρια',
      'Ρύζι μπασμάτι',
      'Ρύζι καστανό parboiled',
      'Ρύζι parboiled',
      'Ρύζι νυχάκι',
      'Ρύζι ολικής',
      'Κινόα τρίχρωμη',
      'Πλιγούρι χοντρό',
      'Κους κους',
      'Κουσκούς',
      'Κριθαράκι μέτριο',
      'Χυλοπίτες με αυγά',
      'Μακαρόνια Νο 6',
      'Μακαρόνια ολικής άλεσης',
      'Ταλιατέλες με αυγά',
      'Ζυμαρικά από φακές',
      'Αλεύρι ρεβιθιού',
      'Κράκερ ρυζιού',
      'Νιφάδες βρώμης',
      'Spaghetti integrale',
      'Lentil pasta',
      'Red lentils',
      'Κουκιά ξερά',
      'Κουκί',
      'Γάλα ρυζιού',
      'Σούπα φακές',
      'Μπάρα δημητριακών',
      'Κάτι άλλο',
    ])
      name: '${dryStapleRawId(mine(name))}|${legumesByName(mine(name))}',
    'Φακές ψιλές, 299 kcal': '${dryStapleRawId(mine('Φακές ψιλές', kcal: 299))}|${legumesByName(mine('Φακές ψιλές', kcal: 299))}',
    'Φακές ψιλές, 300 kcal': '${dryStapleRawId(mine('Φακές ψιλές', kcal: 300))}|${legumesByName(mine('Φακές ψιλές', kcal: 300))}',
    'Φακές ψιλές, ml': '${dryStapleRawId(mine('Φακές ψιλές', perMl: true))}|${legumesByName(mine('Φακές ψιλές', perMl: true))}',
    'Φακές ψιλές, βάση': '${dryStapleRawId(mine('Φακές ψιλές', source: 'CIQUAL 2025'))}|${legumesByName(mine('Φακές ψιλές', source: 'CIQUAL 2025'))}',
    'Ζυμαρικά από φακές, σήμανση όσπρια':
        '${dryStapleRawId(mine('Ζυμαρικά από φακές', cholKind: CholKind.legumes))}|${legumesByName(mine('Ζυμαρικά από φακές', cholKind: CholKind.legumes))}',
  };
  out['spoonByName'] = <String, Object?>{
    for (final n in ['Ταχίνι ολικής', 'ΦΥΣΤΙΚΟΒΟΥΤΥΡΟ', 'Πραλίνα φουντουκιού', 'Μαργαρίνη soft', 'Μαγιονέζα light', 'Βούτυρο αγελαδινό', 'Tahini', 'Margarine', 'Mayonnaise', 'Ψωμί με βούτυρο', 'Μέλι', '', '  — '])
      n: spoonByName(n),
  };
  out['spoonFromOffTags'] = <String, Object?>{
    'not a list': spoonFromOffTags('en:fats'),
    'fats': spoonFromOffTags(['en:fats']),
    'butters upper': spoonFromOffTags([' EN:BUTTERS ', 5]),
    'spread 500': spoonFromOffTags(['en:sweet-spreads'], kcal: 500),
    'spread 499.9': spoonFromOffTags(['en:sweet-spreads'], kcal: 499.9),
    'spread no kcal': spoonFromOffTags(['en:nut-butters']),
    'other': spoonFromOffTags(['en:cheeses'], kcal: 900),
  };
  out['cholKindFromOffTags'] = <String, Object?>{
    for (final e in <String, List<Object?>>{
      'empty': [],
      'nuts': ['en:nuts'],
      'peanut butter': ['en:peanuts', 'en:peanut-butters'],
      'fish': ['en:sardines'],
      'breaded fish': ['en:fishes', 'en:breaded-fish'],
      'pulses': ['en:chickpeas'],
      'hummus': ['en:chickpeas', 'en:hummus'],
      'edamame': ['en:pulses', 'en:edamame'],
      'bran': ['en:oat-brans'],
      'bran + nuts': ['en:oat-bran', 'en:nuts'],
      'bran in flours and cereals': ['en:oat-bran', 'en:flours', 'en:breakfast-cereals'],
      'bran in biscuits': ['en:oat-bran', 'en:biscuits-and-cakes'],
      'nuts + fish': ['en:nuts', 'en:fishes'],
      'chestnuts': ['en:nuts', 'en:chestnuts'],
      'unknown': ['en:cheeses', 7],
    }.entries)
      e.key: cholKindFromOffTags(e.value),
    'not a list': cholKindFromOffTags('en:nuts'),
    'name bran, no tags list': cholKindFromOffTags(null, name: 'Πίτουρο βρώμης'),
    'name bran, flours': cholKindFromOffTags(['en:flours'], name: 'Πίτυρο βρώμης ψιλό'),
    'name bran, breads': cholKindFromOffTags(['en:breads'], name: 'Πίτουρο βρώμης'),
    'name bran, other tag': cholKindFromOffTags(['en:cereals'], name: 'Πίτουρο βρώμης'),
  };
  out['isLiquidQuantity'] = <String, Object?>{
    for (final q in <String?>[null, '', '500 g', '1 l', '1L', '330ml', '33 cl', '2 dl', '1,5 λίτρα', '1 λίτρο', '500 μλ', '1 λτ', '1 lt', '2 litres', '100 gr', '3 λεμόνια', '1 lb', '6 x 330 ml', 'ml'])
      '$q': isLiquidQuantity(q),
  };
  out['normalizeBarcode | scannedBarcode'] = <String, Object?>{
    for (final c in ['5200000000017', '520000000001', '05200000000017', '15200000000017', '12345678', '1234567', '52 0000-0000017', 'ABC', '', ' 5200000000017 ', '5200000000017x'])
      c: '${normalizeBarcode(c)}|${scannedBarcode(c)}',
    'not text': scannedBarcode(5200000000017),
  };

  // Κουζίνα.
  final upgraded = Kitchen.fromJson(<String, dynamic>{
    'devices': ['oven'],
    'cookware': [
      {'id': 'p1', 'kind': 'pot'},
    ],
  });
  final own = Kitchen.fromJson(<String, dynamic>{
    'seed': 2,
    'devices': ['hob', 'scale', 7],
    'hob': 'Γκαζιού',
    'ovenFan': false,
    'steamerTiers': 3.0,
    'airFryerLiters': 5.5,
    'scaleMaxKg': 5,
    'cookware': [
      {'id': 'c1', 'kind': 'tray', 'size': 'Μεγάλο', 'brand': 'Χ', 'note': 'βαθύ'},
      {'id': 'c2', 'kind': 'pot', 'size': 'Μεσαίο', 'brand': ''},
      {'id': 'c3', 'kind': 'wok'},
      {'id': 5},
      'x',
    ],
  });
  out['kitchen'] = <String, Object?>{
    'seedVersion': Kitchen.seedVersion,
    'devices': [for (final d in kitchenDevices) '${d.$1}|${d.$2}|${d.$3}'],
    'cookwareKinds': [for (final c in cookwareKinds) '${c.$1}|${c.$2}'],
    'cookwareSizes': cookwareSizes,
    'initial': Kitchen.initial().toJson(),
    'initial labels': [for (final c in Kitchen.initial().cookware) c.label],
    'fromJson null': Kitchen.fromJson(null).toJson(),
    'upgraded from seed 1': upgraded.toJson(),
    'own': own.toJson(),
    'own labels': [for (final c in own.cookware) c.label],
    'has': [own.has('hob'), own.has('oven')],
    'cookwareSizeLabel': <String, Object?>{
      for (final k in ['pot', 'tray'])
        for (final sz in [...cookwareSizes, 'Τεράστιο']) '$k|$sz': cookwareSizeLabel(k, sz),
    },
    'cookwareKindLabel': [cookwareKindLabel('pot'), cookwareKindLabel('wok')],
  };

  out['weighHints'] = weighHints;
  return out;
}

String _dayOrDash(DateTime? d) => d == null ? '-' : g141Day(d);

// -------------------------------------------------------------------------- βιβλιοθήκη φαγητών (επινοημένη)

Map<String, Object?> _dish(String key, String type, List<(String, double)> items,
        {List<String> meals = const [], bool office = false, int? servings, String cook = 'home', int? minutes, List<String> tags = const []}) =>
    <String, Object?>{
      'key': key,
      'name': 'Φαγητό $key',
      'type': type,
      if (servings != null) 'servings': servings,
      if (minutes != null) 'minutes': minutes,
      'meals': meals,
      'tags': tags,
      'office': office,
      'cook': cook,
      if (cook == 'out') 'order': 'Ψητό, λάδι στο πλάι.',
      'items': [
        for (final (id, g) in items) {'id': id, 'name': _nameOf(id), 'g': g},
      ],
      if (cook == 'home')
        'steps': [
          {'text': 'Μαγείρεψέ το.', 'min': 20},
        ],
    };

List<Map<String, Object?>> _library() => [
      _dish('fakes', 'pot', [(_lentils, 500), (_onion, 150), (_oil, 40)], meals: ['lunch', 'dinner'], office: true, servings: 6, tags: ['όσπρια']),
      _dish('revithia', 'pot', [(_chickpeas, 500), (_onion, 150), (_oil, 40)], meals: ['lunch', 'dinner'], office: true, servings: 6, tags: ['όσπρια']),
      _dish('fasolada', 'pot', [(_beans, 500), (_tomato, 300), (_oil, 40)], meals: ['lunch', 'dinner'], office: true, servings: 6, tags: ['όσπρια']),
      _dish('kotopoulo-ryzi', 'plate', [(_chicken, 200), (_rice, 90), (_oil, 10)], meals: ['lunch', 'dinner'], minutes: 25),
      _dish('kotopoulo-salata', 'plate', [(_chicken, 200), (_tomato, 250), (_oil, 20), (_feta, 40)], meals: ['lunch', 'dinner'], office: true, minutes: 10),
      _dish('solomos', 'plate', [(_salmon, 200), (_rice, 80)], meals: ['dinner'], tags: ['λιπαρό ψάρι']),
      _dish('tsipoura', 'plate', [(_bream, 350), (_tomato, 150), (_oil, 15)], meals: ['dinner'], tags: ['ψάρι']),
      _dish('tsipoura-exo', 'plate', [(_bream, 350), (_rice, 80)], meals: ['lunch', 'dinner'], tags: ['ψάρι'], cook: 'out'),
      _dish('mosxari', 'plate', [(_beef, 200), (_rice, 80)], meals: ['dinner'], tags: ['κόκκινο κρέας']),
      _dish('biftekia', 'portions', [(_beef, 500), (_onion, 100), (_egg, 50), (_oil, 20)], meals: ['lunch', 'dinner'], servings: 4, tags: ['κόκκινο κρέας']),
      _dish('giaourti', 'plate', [(_yogurt, 250), (_apple, 150), (_rusks, 30)], meals: ['snack'], cook: 'none'),
      _dish('frygania', 'plate', [(_rusks, 40), (_feta, 40), (_tomato, 100)], meals: ['snack'], cook: 'none'),
      _dish('milo-giaourti', 'plate', [(_yogurt, 250), (_rusks, 40)], meals: ['snack'], cook: 'none'),
      _dish('tonosalata', 'plate', [(_tunaCan, 150), (_tomato, 200), (_oil, 10), (_rusks, 40)], meals: ['lunch'], office: true, cook: 'none'),
    ];

/// Μου αρέσουν όλα εκτός από μοσχάρι· ελαιόλαδο, κρεμμύδι και αλάτι είναι «βασικά κουζίνας».
const _likes = FoodLikes(
  like: [_lentils, _chickpeas, _beans, _tomato, _chicken, _rice, _yogurt, _feta, _salmon, _bream, _apple, _rusks, _egg, _tunaCan],
  staple: [_oil, _onion, _salt],
  dislike: [_beef],
);

LibraryImport _import() {
  var n = 0;
  final s0 = FoodStore.preloaded(foods: basicFoods(), now: _monday);
  return planLibraryImport(
    parseLibrary(jsonEncode({'kind': libraryKind, 'dishes': _library()})),
    existing: const [],
    food: (id) => s0.itemFood(DishItem(id, id, 1)),
    likes: const FoodLikes(),
    now: 1,
    newId: () => 'L${n++}',
  );
}

FoodStore _store({FoodLikes likes = const FoodLikes(), List<Dish> Function(List<Dish> all)? edit, List<LogEntry> entries = const []}) {
  final added = _import().added;
  return FoodStore.preloaded(foods: basicFoods(), dishes: edit == null ? added : edit(added), likes: likes, entries: entries, now: _monday);
}

Dish _k(FoodStore s, String key) => s.dishes.firstWhere((d) => planInfoOf(d)?.key == key);
String _keyOf(FoodStore s, String dishId) {
  final d = s.dishById(dishId);
  return d == null ? '?$dishId' : (planInfoOf(d)?.key ?? '?$dishId');
}

List<Object?> _planView(FoodStore s, WeekPlan w) => [
      for (final d in w.days)
        [
          for (final x in d)
            '${x.meal.name}:${_keyOf(s, x.dishId)}@${_n1(x.kcal)}${x.locked ? ' lock' : ''}${x.state != SlotState.open ? ' ${x.state.name}' : ''}'
                '${x.grp == null ? '' : ' grp=${x.grp}'}',
        ].join(' | '),
    ];

Map<String, Object?> _autoView(FoodStore s, AutoWeek r) => <String, Object?>{
      'from': r.plan.from,
      'source': r.plan.source,
      'meals': [for (final m in r.plan.meals ?? const <Meal>[]) m.name],
      'days': _planView(s, r.plan),
      'planned': [
        for (var i = 0; i < r.plan.days.length; i++)
          () {
            final p = plannedDay(s, r.plan, i);
            return '${_n1(p.totals.kcal)} kcal · πρωτ ${_n1(p.totals.protein)} · κορ ${_n2(p.totals.satFat)} · ίνες ${_n1(p.totals.fiber)} · άγνωστα ${p.unknown}';
          }(),
      ],
      'notes': r.notes,
    };

/// Αλλάζει μια θέση αν υπάρχει (αλλιώς το πρόγραμμα μένει ίδιο): το στιγμιότυπο δεν σπάει αν μια μέρα βγει πιο κοντή.
WeekPlan _mark(WeekPlan w, int day, int index, PlanSlot Function(PlanSlot s) f) =>
    day >= 0 && day < w.days.length && index >= 0 && index < w.days[day].length ? w.withSlot(day, index, f(w.days[day][index])) : w;

/// Η πρώτη θέση της εβδομάδας (ή μια κενή θέση-σημάδι αν η εβδομάδα είναι άδεια).
PlanSlot _firstSlot(WeekPlan w) {
  for (final d in w.days) {
    if (d.isNotEmpty) return d.first;
  }
  return const PlanSlot(meal: Meal.lunch, dishId: 'none');
}

const _text = 'Ορίστε:\n```json\n';
String _fence(Object j) => '$_text${jsonEncode(j)}\n```';

// -------------------------------------------------------------------------------- φαγητά, εβδομάδα, συνταγές

Map<String, Object?> _dishesGolden() {
  final out = <String, Object?>{};
  final s = _store();
  out['constants'] = <String, Object?>{
    'maxDishItems': maxDishItems,
    'maxDishServings': maxDishServings,
    'maxDishNameLength': maxDishNameLength,
    'maxCookedGrams': maxCookedGrams,
    'maxEatenServings': maxEatenServings,
    'cookedTooLightShare': cookedTooLightShare,
    'potQuickDays': potQuickDays,
    'maxPlanDays': maxPlanDays,
    'maxSlotsPerDay': maxSlotsPerDay,
    'minSlotKcal': minSlotKcal,
    'maxSlotKcal': maxSlotKcal,
    'mealShare': <String, Object?>{for (final e in mealShare.entries) e.key.name: e.value},
    'officeWeekdays': (officeWeekdays.toList()..sort()),
    'autoMaxRepeat': autoMaxRepeat,
    'autoPotDays': autoPotDays,
    'autoRiceDays': autoRiceDays,
    'autoDayTolerance': autoDayTolerance,
    'autoPortionMin': autoPortionMin,
    'autoPortionMax': autoPortionMax,
    'freshShopCats': (freshShopCats.toList()..sort()),
    'maxLibraryDishes': maxLibraryDishes,
    'maxPlanTags': maxPlanTags,
    'maxTagLength': maxTagLength,
    'maxOrderTextLength': maxOrderTextLength,
    'maxLibraryKeyLength': maxLibraryKeyLength,
    'standardTags': standardTags,
    'maxRecipeSteps': maxRecipeSteps,
    'maxRecipeTextLength': maxRecipeTextLength,
    'maxRecipeMinutes': maxRecipeMinutes,
    'kinds': [weekKind, libraryKind, recipeKind, likesKind],
    'noGoalsText': noGoalsText,
  };
  out['labels'] = <String, Object?>{
    'dishKind': <String, Object?>{for (final k in DishKind.values) k.name: dishKindLabel(k)},
    'dishKindOf': [for (final v in <Object?>['plate', 'portions', 'pot', 'x', null]) dishKindOf(v)?.name],
    'cookWay': <String, Object?>{for (final c in CookWay.values) c.name: cookWayLabel(c)},
    'cookWayOf': [for (final v in <Object?>['home', 'none', 'out', 'x', null]) cookWayOf(v)?.name],
    'mealOfName': [for (final v in <Object?>['breakfast', 'lunch', 'dinner', 'snack', 'brunch', 5]) mealOfName(v)?.name],
  };

  // Στρογγυλοποιήσεις.
  out['roundAmount'] = <String, Object?>{for (final v in [0.004, 0.005, 0.0051, 0.015, 1.005, 2.675, 83.333333, 4999.999]) '$v': roundAmount(v)};
  out['weighRound'] = <String, Object?>{
    for (final v in [0.0, 0.1, 0.24, 0.25, 0.74, 0.75, 3.2, 3.25, 9.74, 9.75, 9.99, 10.0, 10.49, 10.5, 11.5, 123.5]) '$v': weighRound(v),
  };
  out['portionRound'] = <String, Object?>{for (final v in [0.0, 2.4, 2.5, 7.4, 7.5, 12.4, 12.5, 247.4, 247.5, 250.0]) '$v': portionRound(v)};
  out['shopRound'] = <String, Object?>{for (final v in [0.0, 0.2, 1.0, 9.01, 9.99, 10.0, 10.01, 95.0, 100.0, 100.01]) '$v': shopRound(v)};
  out['dishLooksLikeTypo'] = [dishLooksLikeTypo(1999.99), dishLooksLikeTypo(2000)];
  out['cookedLooksWrong'] = <String, Object?>{
    for (final (rawG, cookedG) in [(1000.0, 399.9), (1000.0, 400.0), (1000.0, 400.1), (0.0, 0.0), (0.0, 10.0), (500.0, 3000.0)]) '$rawG|$cookedG': cookedLooksWrong(rawG, cookedG),
  };
  out['cookedAgo'] = <String, Object?>{
    for (final o in [-1, 0, 1, 2, 4, 30]) '$o': cookedAgo(DateTime(2026, 11, 22, 19), DateTime(2026, 11, 22 + o, 8)),
    'across 28/3': cookedAgo(DateTime(2027, 3, 27, 23, 30), DateTime(2027, 3, 29, 0, 30)),
    'across 25/10': cookedAgo(DateTime(2026, 10, 24, 23, 30), DateTime(2026, 10, 26, 0, 30)),
  };

  // Ανάγνωση αποθηκευμένων φαγητών.
  out['DishItem.fromJson'] = <String, Object?>{
    for (final e in <String, Object?>{
      'ok': {'id': 'C1', 'n': 'Όνομα', 'g': 120.5},
      'no name': {'id': 'C1', 'g': 1},
      'g 0': {'id': 'C1', 'g': 0},
      'g 5000': {'id': 'C1', 'g': 5000},
      'g 5000.1': {'id': 'C1', 'g': 5000.1},
      'g text': {'id': 'C1', 'g': '5'},
      'empty id': {'id': '', 'g': 5},
      'not a map': 5,
    }.entries)
      e.key: DishItem.fromJson(e.value)?.toJson(),
  };
  final itemsJson = [
    {'id': 'C1', 'n': 'Α', 'g': 100},
    {'id': 'C2', 'n': 'Β', 'g': 50},
  ];
  out['PotBatch.fromJson'] = <String, Object?>{
    for (final e in <String, Object?>{
      'ok': {'at': 1000, 'c': 2400, 'items': itemsJson},
      'c 0': {'at': 1000, 'c': 0, 'items': itemsJson},
      'c 20000': {'at': 1000, 'c': 20000, 'items': itemsJson},
      'c 20000.1': {'at': 1000, 'c': 20000.1, 'items': itemsJson},
      'no items': {'at': 1000, 'c': 100, 'items': <Object?>[]},
      'bad item': {'at': 1000, 'c': 100, 'items': [...itemsJson, 5]},
      '41 items': {'at': 1000, 'c': 100, 'items': [for (var i = 0; i < 41; i++) itemsJson.first]},
      'at text': {'at': 'x', 'c': 100, 'items': itemsJson},
    }.entries)
      e.key: PotBatch.fromJson(e.value)?.toJson(),
  };
  final dishJson = <String, Object?>{'id': 'D1', 'name': ' Φακές ', 'kind': 'pot', 'items': itemsJson, 'created': 10};
  out['Dish.fromJson'] = <String, Object?>{
    for (final e in <String, Map<String, Object?>>{
      'pot': dishJson,
      'pot with batch, lastQty, extras': {
        ...dishJson,
        'batch': {'at': 1000, 'c': 2400, 'items': itemsJson},
        'lastQty': 350,
        'lastPlate': [1, 2],
        'used': 20,
        'uses': 3,
        'rate': 1,
        'plan': {'key': 'fakes'},
      },
      'plate with lastPlate': {...dishJson, 'kind': 'plate', 'lastPlate': [120, 0], 'lastQty': 300, 'batch': {'at': 1, 'c': 2, 'items': itemsJson}},
      'plate lastPlate wrong length': {...dishJson, 'kind': 'plate', 'lastPlate': [120]},
      'plate lastPlate 5000.1': {...dishJson, 'kind': 'plate', 'lastPlate': [120, 5000.1]},
      'portions 4': {...dishJson, 'kind': 'portions', 'serv': 4, 'lastQty': 1.5},
      'portions 50': {...dishJson, 'kind': 'portions', 'serv': 50},
      'portions 51': {...dishJson, 'kind': 'portions', 'serv': 51},
      'portions 0': {...dishJson, 'kind': 'portions', 'serv': 0},
      'portions missing': {...dishJson, 'kind': 'portions'},
      'lastQty 20000.1': {...dishJson, 'lastQty': 20000.1},
      'uses -2': {...dishJson, 'uses': -2},
      'blank name': {...dishJson, 'name': '  '},
      'bad kind': {...dishJson, 'kind': 'soup'},
      'bad item': {...dishJson, 'items': [5]},
      'no items': {...dishJson, 'items': <Object?>[]},
      'empty id': {...dishJson, 'id': ''},
    }.entries)
      e.key: Dish.fromJson(e.value)?.toJson(),
    'not a map': Dish.fromJson('x')?.toJson(),
  };
  out['DishTag.fromJson'] = <String, Object?>{
    for (final e in <String, Object?>{
      'ok': {'id': 'D1', 'n': 'Φακές', 'grp': 'g1', 'k': 'pot', 'q': 350, 'b': 1000},
      'blank name': {'id': 'D1', 'n': ' ', 'grp': 'g1', 'k': 'plate', 'q': 1},
      'q 0': {'id': 'D1', 'grp': 'g1', 'k': 'plate', 'q': 0},
      'no grp': {'id': 'D1', 'grp': '', 'k': 'plate', 'q': 1},
      'bad kind': {'id': 'D1', 'grp': 'g', 'k': 'x', 'q': 1},
      'not a map': null,
    }.entries)
      e.key: DishTag.fromJson(e.value)?.toJson(),
    'withQty/withGrp': const DishTag(id: 'D1', name: 'Φ', grp: 'g1', kind: DishKind.pot, qty: 100).withQty(250).withGrp('g2').toJson(),
  };

  // Ποσότητες ενός φαγητού (πιάτο / ίσες μερίδες / κατσαρόλα), με χειροποίητα φαγητά.
  const plate = Dish(id: 'P', name: 'Πιάτο', kind: DishKind.plate, items: [DishItem(_chicken, 'Κοτόπουλο', 200), DishItem(_rice, 'Ρύζι', 90), DishItem(_oil, 'Λάδι', 10)], created: 1);
  const portions = Dish(
      id: 'S', name: 'Μπιφτέκια', kind: DishKind.portions, servings: 4, items: [DishItem(_beef, 'Μοσχάρι', 500), DishItem(_onion, 'Κρεμμύδι', 100), DishItem(_egg, 'Αυγό', 50)], created: 2, used: 9, uses: 4);
  const batch = PotBatch(at: 1000, cooked: 2400, items: [DishItem(_lentils, 'Φακές', 500), DishItem(_onion, 'Κρεμμύδι', 150), DishItem(_oil, 'Λάδι', 40)]);
  const pot = Dish(id: 'K', name: 'Φακές', kind: DishKind.pot, items: [DishItem(_lentils, 'Φακές', 400), DishItem(_onion, 'Κρεμμύδι', 100), DishItem(_oil, 'Λάδι', 30)], created: 3, batch: batch, uses: 1);
  out['dishAmounts'] = <String, Object?>{
    'plate default': _items(dishAmounts(plate)),
    'plate given': _items(dishAmounts(plate, plate: [180.004, 0, 12.345])),
    'plate short list': _items(dishAmounts(plate, plate: [150])),
    'plate long list': _items(dishAmounts(plate, plate: [1, 2, 3, 4])),
    'portions default': _items(dishAmounts(portions)),
    'portions 1.5': _items(dishAmounts(portions, servings: 1.5)),
    'portions 0': _items(dishAmounts(portions, servings: 0)),
    'portions 0.001': _items(dishAmounts(portions, servings: 0.001)),
    'pot 350 g': _items(dishAmounts(pot, portion: 350)),
    'pot 0 g': _items(dishAmounts(pot, portion: 0)),
    'pot no portion': _items(dishAmounts(pot)),
    'pot other batch': _items(dishAmounts(pot, portion: 300, batch: const PotBatch(at: 2, cooked: 1200, items: [DishItem(_lentils, 'Φακές', 250)]))),
    'pot without batch': _items(dishAmounts(pot.copyWith(clearBatch: true), portion: 300)),
    'itemsSum': itemsSum(plate.items),
  };
  out['copyWith'] = <String, Object?>{
    'plate': plate.copyWith(name: 'Νέο', lastPlate: [1, 2, 3], used: 5, uses: 2).toJson(),
    'clear': pot.copyWith(clearBatch: true, lastQty: 300).copyWith(clearLastQty: true).toJson(),
    'withExtra add/remove': withExtra(withExtra(plate, 'rate', 1), 'rate', null).toJson(),
    'withRating': [for (final r in [1, -1, 0, 5]) dishRating(withRating(plate, r))],
    'dishRating junk': dishRating(withExtra(plate, 'rate', 'x')),
  };
  out['dishesInOrder'] = [
    for (final d in dishesInOrder([plate, portions, pot, plate.copyWith(name: 'Άλφα', used: 3), pot.copyWith(name: 'Βήτα', used: 3)])) '${d.id} ${d.name}',
  ];
  out['searchDishes'] = <String, Object?>{
    for (final q in ['κοτο', 'kotopoulo', 'fakes', 'φακες', 'σολ', 'Φαγητό', 'φαγητο ρυζι', '', '  ', 'ξξξ', 'ryzi', 'giaourti milo'])
      q: [for (final d in s.findDishes(q)) planInfoOf(d)?.key],
    'by uses': [for (final d in searchDishes([plate, portions, pot], 'φακες μπιφτεκια')) d.id],
    'uses order': [for (final d in searchDishes([plate.copyWith(name: 'Φακές Α'), pot, portions.copyWith(name: 'Φακές Β')], 'φακ')) '${d.id}:${d.uses}'],
  };

  // Βιβλιοθήκη: τι πέρασε και με ποιους αριθμούς.
  final imp = _import();
  out['library import'] = <String, Object?>{
    'added': imp.added.length,
    'updated': imp.updated.length,
    'unchanged': imp.unchanged,
    'problems': [for (final p in imp.problems) '${p.key}: ${p.errors.join(' | ')}'],
    'usableLibrary': usableLibrary(s),
    'libraryDishes': libraryDishes(s.dishes).length,
  };
  final batchAt = DateTime(2026, 11, 22, 19);
  final perDish = <String, Object?>{};
  for (final d in s.dishes) {
    final key = planInfoOf(d)?.key ?? d.id;
    final r = portionRange(s, d);
    final fresh = d.kind == DishKind.pot ? d.copyWith(batch: PotBatch(at: batchAt.millisecondsSinceEpoch, cooked: 2400, items: d.items)) : d;
    final b = fresh.batch;
    perDish[key] = <String, Object?>{
      'json': d.toJson(),
      'plan': planInfoOf(d)?.toJson(),
      'recipe': recipeOf(d)?.toJson(),
      'all items': _tShort(itemsTotals(s, d.items)),
      'naturalRaw': _items(naturalRaw(d)),
      'natural totals': _tShort(naturalRaw(d) == null ? null : itemsTotals(s, naturalRaw(d)!)),
      'portionRange': r == null ? null : '${_n2(r.lo)}..${_n2(r.hi)} natural ${_n2(r.natural)} · πρωτ/kcal ${r.proteinPerKcal.toStringAsFixed(5)} · κορ/kcal ${r.satPerKcal.toStringAsFixed(5)}',
      for (final kcal in <double?>[null, 100, 400, 650, 3000]) ...{
        'plannedRaw $kcal': _items(plannedRaw(s, d, kcal)),
        'plannedTotals $kcal': _tShort(plannedTotals(s, d, PlanSlot(meal: Meal.lunch, dishId: d.id, kcal: kcal))),
        'slotLog $kcal': () {
          final l = slotLog(s, fresh, PlanSlot(meal: Meal.lunch, dishId: d.id, kcal: kcal), DateTime(2026, 11, 23, 13));
          return l == null ? null : 'qty ${_n2(l.qty)} · ${_items(l.amounts)}${l.plate == null ? '' : ' · plate ${[for (final p in l.plate!) _n1(p)].join('/')}'}';
        }(),
        if (b != null) 'potPortion $kcal': potPortion(s, fresh, b, kcal),
      },
      'dishGroup': dishGroup(s, d),
    };
  }
  out['dishes'] = perDish;

  final fakes = _k(s, 'fakes');
  final cooked = fakes.copyWith(batch: PotBatch(at: batchAt.millisecondsSinceEpoch, cooked: 2400, items: fakes.items));
  out['freshBatch'] = <String, Object?>{
    for (final o in [0, 1, 3, 4, 5]) '+$o': freshBatch(cooked, DateTime(2026, 11, 22 + o, 9)) != null,
    'no batch': freshBatch(fakes, _monday) != null,
    'plate': freshBatch(_k(s, 'solomos'), _monday) != null,
    'old batch → no slotLog': slotLog(s, cooked, PlanSlot(meal: Meal.lunch, dishId: fakes.id), DateTime(2026, 11, 26, 13)) == null,
    'potPortion bigger than pot': potPortion(s, cooked, PotBatch(at: 1, cooked: 300, items: fakes.items), 3000),
  };
  out['nextMonday'] = <String, Object?>{
    for (final d in [for (var i = 0; i < 8; i++) DateTime(2026, 11, 22 + i, 23, 30), DateTime(2027, 3, 28, 12), DateTime(2026, 10, 25, 12), DateTime(2026, 12, 31)])
      g141Day(d): g141Day(nextMonday(d)),
  };
  out['isFreshBuy'] = <String, Object?>{
    for (final id in [_chicken, _salmon, _beef, _tunaCan, _lentils, _tomato, _egg, 'C6207']) '$id ${_nameOf(id)}': isFreshBuy(_dbFood(id)),
  };

  // Αυτόματο πρόγραμμα (σταθερό seed) και ό,τι βγαίνει από αυτό.
  const lsd = [Meal.lunch, Meal.snack, Meal.dinner];
  AutoWeek make(FoodStore st, {int seed = 1, List<Meal> meals = lsd, double kcal = 2150, double protein = 140, int legumes = 4, int fish = 2, int days = 7, DateTime? from, WeekPlan? keep, Map<(int, Meal), String> forced = const {}, bool aiOnly = false}) =>
      autoWeek(st,
          from: from ?? _monday,
          meals: meals,
          kcalTarget: kcal,
          proteinTarget: protein,
          legumesWeek: legumes,
          fishWeek: fish,
          days: days,
          seed: seed,
          keep: keep,
          now: 1,
          forced: forced,
          aiOnly: aiOnly);
  final a1 = make(s);
  var kept = _mark(a1.plan, 0, 0, (x) => x.copyWith(locked: true));
  kept = _mark(kept, 1, 1, (x) => x.copyWith(state: SlotState.ate, grp: 'g1'));
  kept = _mark(kept, 2, 0, (x) => x.copyWith(state: SlotState.skip));
  final noChicken = _store(likes: const FoodLikes(dislike: [_chicken, _feta]));
  out['autoWeek'] = <String, Object?>{
    'seed 1': _autoView(s, a1),
    'seed 2': _autoView(s, make(s, seed: 2)),
    'seed 3': _autoView(s, make(s, seed: 3)),
    'four meals 2800': _autoView(s, make(s, meals: Meal.values, kcal: 2800, protein: 140)),
    'two meals 1500, fish 6': _autoView(s, make(s, meals: const [Meal.lunch, Meal.dinner], kcal: 1500, protein: 110, fish: 6)),
    'keep locked/ate/skip, seed 2': _autoView(s, make(s, seed: 2, keep: kept)),
    'keep from another week': _autoView(s, make(s, seed: 2, keep: kept, from: DateTime(2026, 11, 30))),
    '14 days from 22/3/2027': _autoView(s, make(s, days: 14, from: DateTime(2027, 3, 22, 15))),
    'from Thursday 22/10/2026, 5 days': _autoView(s, make(s, days: 5, from: DateTime(2026, 10, 22))),
    'dislikes chicken and feta': _autoView(noChicken, make(noChicken)),
    'forced': _autoView(
        s,
        make(s, forced: {
          (0, Meal.lunch): _k(s, 'fakes').id,
          (0, Meal.dinner): _k(s, 'solomos').id,
          (1, Meal.lunch): _k(s, 'solomos').id,
          (1, Meal.snack): 'missing-id',
          (2, Meal.lunch): _k(s, 'kotopoulo-ryzi').id,
        })),
    'aiOnly, nothing forced': _autoView(s, make(s, aiOnly: true)),
    'no legumes or fish asked': _autoView(s, make(s, legumes: 0, fish: 0)),
    'snack only 400': _autoView(s, make(s, meals: const [Meal.snack], kcal: 400, protein: 30, legumes: 0, fish: 0)),
  };

  // Εβδομάδα: κατάσταση θέσης, λίστα για ψώνια, οδηγίες.
  final w = a1.plan;
  final first = _firstSlot(w);
  final tag = DishTag(id: first.dishId, name: 'Φ', grp: 'g1', kind: DishKind.plate, qty: 1);
  final withEntry = _store(entries: [
    LogEntry(id: 'x1', day: '2026-11-23', meal: Meal.lunch, food: _dbFood(_chicken), grams: 200, time: DateTime(2026, 11, 23, 14), dish: tag),
  ]);
  out['slotStateNow'] = <String, Object?>{
    'open': slotStateNow(withEntry, w, 0, first).name,
    'ate, entry exists': slotStateNow(withEntry, w, 0, first.copyWith(state: SlotState.ate, grp: 'g1')).name,
    'ate, entry deleted': slotStateNow(withEntry, w, 0, first.copyWith(state: SlotState.ate, grp: 'g2')).name,
    'ate, entry on another day': slotStateNow(withEntry, w, 1, first.copyWith(state: SlotState.ate, grp: 'g1')).name,
    'ate, no grp': slotStateNow(withEntry, w, 0, first.copyWith(state: SlotState.ate)).name,
    'skip': slotStateNow(withEntry, w, 0, first.copyWith(state: SlotState.skip)).name,
    'other': slotStateNow(withEntry, w, 0, first.copyWith(state: SlotState.other)).name,
  };
  final withBatch = _store(
      edit: (all) => [
            for (final d in all)
              planInfoOf(d)?.key == 'fakes' ? d.copyWith(batch: PotBatch(at: batchAt.millisecondsSinceEpoch, cooked: 2400, items: d.items)) : d,
          ]);
  Map<String, Object?> shop(FoodStore st, WeekPlan plan, {int fromDay = 0, DateTime? now}) {
    final l = shoppingList(st, plan, fromDay: fromDay, now: now);
    return <String, Object?>{
      'main': [for (final x in l.main) '${x.food.cat} · ${x.food.name}: ${_n2(x.amount)}'],
      'fresh': <String, Object?>{
        for (final e in l.fresh.entries) '${e.key}': [for (final x in e.value) '${x.food.name}: ${_n2(x.amount)}'],
      },
      'ordered': l.ordered,
      'unknown': l.unknown,
      'isEmpty': l.isEmpty,
      'text': g141Lines(shoppingText(l, plan)),
    };
  }

  final outPlan = WeekPlan(from: '2026-11-23', created: 1, days: [
    [PlanSlot(meal: Meal.lunch, dishId: _k(s, 'tsipoura-exo').id, kcal: 600), PlanSlot(meal: Meal.dinner, dishId: _k(s, 'fakes').id)],
    [PlanSlot(meal: Meal.lunch, dishId: _k(s, 'fakes').id), const PlanSlot(meal: Meal.dinner, dishId: 'gone')],
    [PlanSlot(meal: Meal.lunch, dishId: _k(s, 'fakes').id, state: SlotState.ate), PlanSlot(meal: Meal.dinner, dishId: _k(s, 'biftekia').id, kcal: 500)],
    const [],
    [PlanSlot(meal: Meal.lunch, dishId: _k(s, 'fakes').id), PlanSlot(meal: Meal.dinner, dishId: _k(s, 'solomos').id)],
  ]);
  out['shoppingList'] = <String, Object?>{
    'auto week seed 1': shop(s, w),
    'auto week from day 3': shop(s, w, fromDay: 3),
    'pot, order, missing, ate': shop(s, outPlan),
    'pot cooked yesterday': shop(withBatch, outPlan, now: DateTime(2026, 11, 23, 9)),
    'empty': shop(s, const WeekPlan(from: '2026-11-23', days: [[]], created: 1)),
  };
  out['weekPrompt'] = <String, Object?>{
    'with targets': g141Lines(weekPrompt(food: s, from: _monday, targets: (kcal: 2150, protein: 140, satMax: 14, fiber: 30, salt: 5.0), legumesWeek: 4, fishWeek: 2)),
    'bare': g141Text(weekPrompt(food: s, from: DateTime(2027, 3, 29))),
    'disliked and missing': g141Lines(weekPrompt(
        food: _store(
            edit: (all) => [
                  for (final d in all)
                    planInfoOf(d)?.key == 'solomos'
                        ? withRating(d, -1)
                        : planInfoOf(d)?.key == 'mosxari'
                            ? withRating(d, 1)
                            : planInfoOf(d)?.key == 'frygania'
                                ? d.copyWith(items: [...d.items, const DishItem('ZZ9', 'Άγνωστο', 10)])
                                : d,
                ]),
        from: _monday,
        fishWeek: 2)),
  };

  // Αποθηκευμένο πρόγραμμα από/σε JSON.
  out['PlanSlot.fromJson'] = <String, Object?>{
    for (final e in <String, Object?>{
      'ok': {'meal': 'lunch', 'dish': 'D1', 'kcal': 650, 'lock': true, 'st': 'ate', 'grp': 'g1'},
      'kcal 29.9': {'meal': 'lunch', 'dish': 'D1', 'kcal': 29.9},
      'kcal 30': {'meal': 'lunch', 'dish': 'D1', 'kcal': 30},
      'kcal 2500': {'meal': 'lunch', 'dish': 'D1', 'kcal': 2500},
      'kcal 2500.1': {'meal': 'lunch', 'dish': 'D1', 'kcal': 2500.1},
      'unknown state': {'meal': 'snack', 'dish': 'D1', 'st': 'later', 'grp': ''},
      'bad meal': {'meal': 'brunch', 'dish': 'D1'},
      'no dish': {'meal': 'lunch', 'dish': ''},
      'not a map': 5,
    }.entries)
      e.key: PlanSlot.fromJson(e.value)?.toJson(),
    'copyWith clear': const PlanSlot(meal: Meal.lunch, dishId: 'D1', kcal: 600, grp: 'g1').copyWith(clearKcal: true, clearGrp: true, locked: true, dishId: 'D2').toJson(),
  };
  final slotJson = {'meal': 'lunch', 'dish': 'D1'};
  out['WeekPlan.fromJson'] = <String, Object?>{
    for (final e in <String, Object?>{
      'ok': {
        'from': '2026-11-23',
        'created': 5,
        'source': 'auto',
        'meals': ['dinner', 'lunch', 'x'],
        'days': [
          [slotJson, 5, {'meal': 'x', 'dish': 'D'}],
          <Object?>[],
        ],
      },
      'defaults': {'from': '2026-11-23', 'days': [<Object?>[]]},
      '7 slots a day': {'from': '2026-11-23', 'days': [[for (var i = 0; i < 7; i++) slotJson]]},
      '14 days': {'from': '2026-11-23', 'days': [for (var i = 0; i < 14; i++) <Object?>[]]},
      '15 days': {'from': '2026-11-23', 'days': [for (var i = 0; i < 15; i++) <Object?>[]]},
      'no days': {'from': '2026-11-23', 'days': <Object?>[]},
      'day not a list': {'from': '2026-11-23', 'days': [5]},
      'bad from': {'from': '2026-11-31', 'days': [<Object?>[]]},
      'not a map': 'x',
    }.entries)
      e.key: WeekPlan.fromJson(e.value)?.toJson(),
  };
  out['parseDayKey'] = <String, Object?>{
    for (final k in ['2026-11-23', '2026-02-29', '2028-02-29', '2026-13-01', '2026-11-31', '2026-1-01', '2026-11-23 ', '2027-03-28', '2026-10-25']) k: _dayOrDash(parseDayKey(k)),
  };
  final dst = WeekPlan(from: '2027-03-22', created: 1, days: [for (var i = 0; i < 14; i++) const <PlanSlot>[]]);
  final autumn = WeekPlan(from: '2026-10-19', created: 1, days: [for (var i = 0; i < 14; i++) const <PlanSlot>[]]);
  out['WeekPlan days'] = <String, Object?>{
    'spring': [for (var i = 0; i < 14; i++) g141Day(dst.dayAt(i)).substring(5)].join(' '),
    'spring end': g141Day(dst.end),
    'spring indexOf 28/3 23:59': dst.indexOf(DateTime(2027, 3, 28, 23, 59)),
    'spring indexOf 5/4': dst.indexOf(DateTime(2027, 4, 5)),
    'autumn': [for (var i = 0; i < 14; i++) g141Day(autumn.dayAt(i)).substring(5)].join(' '),
    'autumn indexOf 25/10 01:30': autumn.indexOf(DateTime(2026, 10, 25, 1, 30)),
    'autumn indexOf 26/10': autumn.indexOf(DateTime(2026, 10, 26)),
    'slotsFor outside': w.slotsFor(DateTime(2026, 12, 1)).length,
    'slotsFor inside': w.slotsFor(DateTime(2026, 11, 25, 18)).length,
    'withAdded': _planView(s, w.withAdded(6, PlanSlot(meal: Meal.breakfast, dishId: _k(s, 'giaourti').id, kcal: 300)))[6],
  };

  // Επικόλληση προγράμματος εβδομάδας: σωστό και λάθη.
  Map<String, Object?> pw(Object text) {
    final r = parseWeek(text is String ? text : _fence(text), s.dishes, now: 7);
    return g141Compact(<String, Object?>{'errors': r.errors, 'plan': r.plan == null ? null : _planView(s, r.plan!), 'created': r.plan?.created, 'source': r.plan?.source});
  }

  Map<String, Object?> week(Object days, {Object? from = '2026-11-23'}) => <String, Object?>{'kind': weekKind, 'from': from, 'days': days};
  final bad = _store(edit: (all) => [for (final d in all) planInfoOf(d)?.key == 'solomos' ? withRating(d, -1) : d]);
  out['parseWeek'] = <String, Object?>{
    'ok': pw(week([
      [
        {'meal': 'lunch', 'key': 'fakes', 'kcal': 650},
        {'meal': 'snack', 'key': 'giaourti'},
        {'meal': 'dinner', 'key': 'solomos', 'kcal': 700.5},
      ],
      {
        'meals': [
          {'meal': 'lunch', 'key': 'fakes'},
        ],
      },
      <Object?>[],
    ])),
    'no json': pw('Δεν έχω πρόγραμμα.'),
    'the instructions themselves': pw('$weekPromptTitle\n{ "x": 1 }'),
    'other json': pw('{"kind": "x"}'),
    'half': pw('```json\n{"kind": "ygeia-week", "from": "2026-11-23", "days": [[{"meal": "lunch"'),
    'no from': pw(week([<Object?>[]], from: null)),
    'bad from, no days': pw(week(<Object?>[], from: '23/11/2026')),
    'days not a list': pw(week(5)),
    '15 days': pw(week([for (var i = 0; i < 15; i++) <Object?>[]])),
    'errors in slots': pw(week([
      5,
      [
        7,
        {'meal': 'brunch', 'key': 'fakes'},
        {'meal': 'lunch', 'key': 'unknown'},
        {'meal': 'lunch', 'key': 5},
        {'meal': 'dinner', 'key': 'solomos', 'kcal': 29},
        {'meal': 'dinner', 'key': 'solomos', 'kcal': 2501},
        {'meal': 'dinner', 'key': 'solomos', 'kcal': 'πολλές'},
      ],
      [for (var i = 0; i < 7; i++) {'meal': 'snack', 'key': 'giaourti'}],
    ])),
    'disliked dish': () {
      final r = parseWeek(
          _fence(week([
            [
              {'meal': 'dinner', 'key': 'solomos'},
            ],
          ])),
          bad.dishes,
          now: 7);
      return r.errors;
    }(),
    'kcal 30 and 2500': pw(week([
      [
        {'meal': 'lunch', 'key': 'fakes', 'kcal': 30},
        {'meal': 'dinner', 'key': 'solomos', 'kcal': 2500},
      ],
    ])),
  };
  final next = make(s, seed: 2).plan;
  out['keepDone'] = <String, Object?>{
    'no old': _planView(s, keepDone(next, null)),
    'same plan with states': _planView(s, keepDone(a1.plan, kept)),
    'other plan': _planView(s, keepDone(next, kept)),
  };

  // Επικόλληση βιβλιοθήκης: λάθη.
  Map<String, Object?> pl(Object text) {
    final p = parseLibrary(text is String ? text : _fence(text));
    return g141Compact(<String, Object?>{
      'errors': p.errors,
      'entries': [for (final e in p.entries) '${e.key} · ${e.name} · ${e.plan.toJson()} · συνταγή ${e.recipe != null} · ${e.errors.join(' | ')}'],
    });
  }

  Map<String, Object?> lib(List<Object?> dishes) => <String, Object?>{'kind': libraryKind, 'dishes': dishes};
  final good = _dish('nea-fakes', 'pot', [(_lentils, 300), (_oil, 20)], meals: ['lunch'], servings: 4, tags: [' Όσπρια ', 'οσπρια', 'x' * 31, 5.toString()]);
  out['parseLibrary'] = <String, Object?>{
    'no json': pl('τίποτα'),
    'instructions': pl('$libraryPromptTitle {'),
    'other json': pl('{"kind": "ygeia-week"}'),
    'no dishes': pl(lib(const [])),
    '301 dishes': pl(lib([for (var i = 0; i < 301; i++) 5])),
    'mixed': pl(lib([
      good,
      5,
      {...good, 'key': 'nea-fakes'},
      {...good, 'key': ''},
      {...good, 'key': 'Κεφαλαία'},
      {...good, 'key': 'a' * 61},
      {...good, 'key': 'k2', 'cook': 'boil'},
      {...good, 'key': 'k3', 'meals': ['lunch', 'brunch', 'lunch']},
      {...good, 'key': 'k4', 'cook': 'out'},
      {...good, 'key': 'k5', 'cook': 'out', 'order': '  Ψητό '},
      {...good, 'key': 'k6', 'cook': 'none', 'steps': <Object?>[]},
      {...good, 'key': 'k7', 'steps': <Object?>[]},
      {...good, 'key': 'k8', 'name': '  '},
      {...good, 'key': 'k9', 'type': 'portions', 'servings': null},
      {...good, 'key': 'k10', 'items': <Object?>[]},
    ])),
  };
  LibraryImport imp2(List<Object?> dishes, {List<Dish> existing = const [], FoodLikes likes = const FoodLikes()}) {
    var n = 0;
    return planLibraryImport(parseLibrary(_fence(lib(dishes))),
        existing: existing, food: (id) => s.itemFood(DishItem(id, id, 1)), likes: likes, now: 9, newId: () => 'N${n++}');
  }

  String impView(LibraryImport r) =>
      'added ${[for (final d in r.added) d.id].join(',')} · updated ${[for (final d in r.updated) d.id].join(',')} · unchanged ${r.unchanged} · '
      '${[for (final p in r.problems) '${p.key}: ${p.errors.join(' | ')}'].join(' ## ')}';
  final problems = imp2([
    {
      ...good,
      'key': 'p1',
      'items': [
        {'name': 'Χωρίς id', 'g': 10},
        {'id': 'ZZ1', 'name': 'Άγνωστο', 'g': 10},
        {'id': _lentils, 'name': 'Κοτόπουλο', 'g': 10},
        {'id': 'C6207', 'name': _nameOf('C6207'), 'g': 10},
        {'id': _feta, 'name': 'Φέτα', 'g': 10},
      ],
    },
  ], likes: const FoodLikes(dislike: [_feta]));
  out['planLibraryImport'] = <String, Object?>{
    'problems': impView(problems),
    'problems text': g141Lines(libraryProblemsText(problems.problems)),
    'same again': impView(imp2(_library(), existing: s.dishes)),
    'changed amounts': impView(imp2([
      _dish('fakes', 'pot', [(_lentils, 450), (_onion, 150), (_oil, 40)], meals: ['lunch', 'dinner'], office: true, servings: 6, tags: ['όσπρια']),
      _dish('solomos', 'portions', [(_salmon, 400), (_rice, 160)], meals: ['dinner'], servings: 2),
      good,
    ], existing: s.dishes)),
    'cooked form allowed for order': impView(imp2([
      {...good, 'key': 'p2', 'cook': 'out', 'order': 'Ψητό', 'type': 'plate', 'items': [{'id': 'C6207', 'name': _nameOf('C6207'), 'g': 150}]},
    ])),
  };
  out['itemNameMatches'] = <String, Object?>{
    for (final (given, name) in [
      ('Φακές', 'Φακές (ξερές)'),
      ('φακη', 'Φακές (ξερές)'),
      ('lentils', 'Φακές (ξερές)'),
      ('Κοτόπουλο', 'Φακές (ξερές)'),
      ('', 'Φακές (ξερές)'),
      ('το', 'Φακές (ξερές)'),
      ('Ελαιόλαδο', 'Ελαιόλαδο εξαιρετικά παρθένο'),
      ('λάδι', 'Ελαιόλαδο εξαιρετικά παρθένο'),
      ('στήθος κοτόπουλου', 'Κοτόπουλο στήθος χωρίς πέτσα (ωμό)'),
      ('ρύζι άσπρο', 'Ρύζι λευκό (ωμό)'),
    ])
      '$given|$name': itemNameMatches(given, name),
  };
  out['tags'] = <String, Object?>{
    'normTag': [normTag('  Λιπαρό   ΨΆΡΙ '), normTag('')],
    'sameTag': [sameTag('όσπρια', 'ΟΣΠΡΙΑ'), sameTag('ψάρι', 'psari'), sameTag('ψάρι', 'λιπαρό ψάρι')],
    'PlanInfo.fromJson': <String, Object?>{
      for (final e in <String, Object?>{
        'full': {'key': 'fakes', 'meals': ['dinner', 'lunch', 'lunch', 'x'], 'tags': ['Όσπρια', 'όσπρια', 5, '', 'x' * 31], 'office': true, 'cook': 'none', 'order': ' ζήτα ψητό '},
        'bad key': {'key': 'Φακές'},
        'long key': {'key': 'a' * 61},
        '13 tags': {'tags': [for (var i = 0; i < 13; i++) 'ετικέτα $i']},
        'long order': {'order': 'ω' * 801, 'cook': 'out'},
        'not a map': 5,
      }.entries)
        e.key: () {
          final p = PlanInfo.fromJson(e.value);
          if (p == null) return null;
          final j = p.toJson();
          final o = j['order'];
          return <String, Object?>{...j, if (o is String && o.length > 60) 'order': 'μήκος ${o.length}'};
        }(),
    },
    'hasTag/fits': () {
      final p = planInfoOf(_k(s, 'solomos'))!;
      return [p.hasTag('Λιπαρό ψάρι'), p.hasTag('ψάρι'), p.fits(Meal.dinner), p.fits(Meal.lunch), const PlanInfo().fits(Meal.breakfast)];
    }(),
  };
  final small = [_dbFood(_lentils), _dbFood(_chicken), _dbFood('C6207'), _dbFood(_oil), _dbFood(_feta), _dbFood(_apple)];
  out['libraryPrompt'] = <String, Object?>{
    'small list': g141Lines(libraryPrompt(
        foods: small,
        likes: const FoodLikes(like: [_lentils, 'ZZ'], dislike: [_feta], note: ' Όχι πικάντικα. '),
        kitchen: Kitchen.initial(),
        targets: (kcal: 2150, protein: 140, satMax: 14, fiber: 30, salt: 5.0),
        existing: s.dishes.take(3).toList())),
    'whole database': g141Text(libraryPrompt(foods: basicFoods(), likes: const FoodLikes(), kitchen: Kitchen())),
  };

  // Συνταγές.
  Map<String, Object?> pr(Object text) {
    final r = parseRecipe(text is String ? text : _fence(text));
    final x = r.recipe;
    return g141Compact(<String, Object?>{
      'ok': r.ok,
      'errors': r.errors,
      'recipe': x == null
          ? null
          : <String, Object?>{
              'name': x.name,
              'kind': x.kind.name,
              'servings': x.servings,
              'items': [for (final i in x.items) '${i.id}|${i.name}|${_n2(i.amount)}'],
              'recipe': x.recipe.toJson(),
            },
    });
  }

  final recipe = <String, Object?>{
    'kind': recipeKind,
    'name': '  Φακές με καρότο ',
    'type': 'pot',
    'servings': 4,
    'minutes': 45,
    'items': [
      {'id': _lentils, 'name': 'Φακές (ξερές)', 'g': 250},
      {'id': ' $_oil ', 'grams': 20.004},
      {'name': 'Καρότο', 'g': 100},
    ],
    'steps': [
      {'text': ' Ξέπλυνε. ', 'device': '', 'heat': ' ', 'min': 2},
      {'text': 'Βράσε.', 'device': 'Κατσαρόλα μεγάλη', 'heat': 'δυνατή', 'min': 30.4},
      'Σέρβιρε.',
      {'text': '  '},
      5,
    ],
    'tips': ['Με λεμόνι.', '', 5],
    'keeps': 'Στο ψυγείο ως 3 μέρες',
    'why': 'Πολλές ίνες.',
  };
  out['parseRecipe'] = <String, Object?>{
    'ok': pr(recipe),
    'no json': pr('συνταγή χωρίς τίποτα'),
    'instructions': pr('$recipePromptTitle\n{'),
    'other json': pr('{"kind": "ygeia-library"}'),
    'plain braces, no fence': pr('Πριν {"x": {"kind": "no"}} μετά ${jsonEncode(recipe)} τέλος'),
    'no name': pr({...recipe, 'name': 5}),
    'unknown type → pot': pr({...recipe, 'type': 'soup', 'servings': 0}),
    'plate ignores servings': pr({...recipe, 'type': 'plate', 'servings': 4}),
    'portions without servings': pr({...recipe, 'type': 'portions', 'servings': 51}),
    'no items': pr({...recipe, 'items': <Object?>[]}),
    'bad items': pr({
      ...recipe,
      'items': [
        5,
        {'id': 'C1', 'g': 0},
        {'id': 'C1', 'g': 5000.1},
        {'name': 'Χωρίς ποσό'},
        {'g': 10},
        {'id': 'C1', 'name': 'Εντάξει', 'g': 5000},
      ],
    }),
    '41 items': pr({...recipe, 'items': [for (var i = 0; i < 41; i++) {'id': 'C$i', 'g': 1}]}),
    'no steps': pr({...recipe, 'steps': <Object?>[]}),
    'min instead of minutes, 1441': pr({...recipe, 'minutes': null, 'min': 1441}),
    'long texts': g141Safe(() {
      final r = parseRecipe(_fence({...recipe, 'name': 'Ν' * 81, 'why': 'Γ' * 601, 'steps': [for (var i = 0; i < 31; i++) 'Βήμα $i ${'β' * 600}']}));
      final x = r.recipe!;
      return [x.name.length, x.recipe.why?.length, x.recipe.steps.length, x.recipe.steps.first.text.length];
    }),
  };
  out['Recipe.fromJson'] = <String, Object?>{
    for (final e in <String, Object?>{
      'empty map': <String, Object?>{},
      'only minutes': {'min': 30},
      'only tips': {'tips': ['α']},
      'serv bounds': {'keeps': 'ψυγείο', 'serv': 0, 'min': 0},
      'serv 50': {'keeps': 'ψυγείο', 'servings': 50.4, 'minutes': 1440},
      'not a map': 'x',
    }.entries)
      e.key: Recipe.fromJson(e.value)?.toJson(),
    'recipeOf/withRecipe': recipeOf(withRecipe(plate, const Recipe(tips: ['α'], servings: 3)))?.toJson(),
    'withRecipe null': withRecipe(withRecipe(plate, const Recipe(tips: ['α'])), null).toJson().containsKey('recipe'),
  };
  out['FoodLikes'] = <String, Object?>{
    'fromJson': FoodLikes.fromJson({
      'like': ['A', 'B', 'A', '', 5, 'C'],
      'dislike': ['C', 'D'],
      'staple': ['D', 'E'],
      'note': ' σημείωση ',
    }).toJson(),
    'fromJson junk': FoodLikes.fromJson(5).toJson(),
    'isEmpty': [const FoodLikes().isEmpty, const FoodLikes(note: '  ').isEmpty, const FoodLikes(staple: ['A']).isEmpty],
    'mapIds': const FoodLikes(like: ['A', 'B'], dislike: ['C'], staple: ['D', 'A2']).mapIds((id) => id == 'B' ? 'C' : (id == 'A2' ? 'A' : id)).toJson(),
    'copyWith': const FoodLikes(like: ['A']).copyWith(dislike: ['B'], note: 'ν').toJson(),
    'parseLikes': () {
      final r = parseLikes(_fence({'kind': likesKind, 'like': ['A', 'ZZ'], 'dislike': ['B', 'YY'], 'staple': ['S']}), (id) => id.length == 1);
      return r == null ? null : <String, Object?>{'likes': r.likes.toJson(), 'unknown': r.unknown};
    }(),
    'parseLikes other': parseLikes('{"kind": "x"}', (id) => true) == null,
  };
  out['sameWords'] = <String, Object?>{
    for (final (a, b) in [('φακές', 'Φακές (ξερές)'), ('φακες ξερες', 'Φακές (ξερές)'), ('ξερές φακές κόκκινες', 'Φακές (ξερές)'), ('', 'Φακές'), ('α', 'α β'), ('fakes', 'Φακές')])
      '$a|$b': sameWords(a, b),
  };
  out['rawFoodLines'] = <String, Object?>{
    'raw': rawFoodLines(small, const FoodLikes(dislike: [_feta])),
    'cooked': rawFoodLines(small, const FoodLikes(), cooked: true),
    'with tail': rawFoodLines([..._modelFoods()], const FoodLikes(), tail: (f) => ' <${f.unit}>'),
  };
  out['recipePrompt'] = <String, Object?>{
    'full': g141Lines(recipePrompt(
        wish: '  κάτι με φακές ',
        foods: small,
        likes: const FoodLikes(like: [_lentils], dislike: [_feta], note: 'Όχι πικάντικα.'),
        kitchen: Kitchen(devices: {'hob', 'oven'}, cookware: [Cookware(id: 'c1', kind: 'pot', size: 'Μεγάλο')]),
        targets: (kcal: 2150, protein: 140, satMax: 14, fiber: 30, salt: 5.0),
        left: (kcal: 1234, protein: 56))),
    'bare': g141Lines(recipePrompt(wish: ' ', foods: const [], likes: const FoodLikes(), kitchen: Kitchen(), left: (kcal: 0, protein: 10))),
  };
  out['jsonOfKind'] = <String, Object?>{
    'fenced': jsonOfKind('α\n```json\n{"kind":"k","a":1}\n```\nβ', 'k'),
    'fence without json word': jsonOfKind('```\n{"kind":"k","a":2}\n```', 'k'),
    'second fence': jsonOfKind('```json\n{"kind":"x"}\n```\n```json\n{"kind":"k","a":3}\n```', 'k'),
    'bare with braces in strings': jsonOfKind('πριν {"kind":"k","t":"} \\" {"} μετά', 'k'),
    'nested first': jsonOfKind('{"a":{"kind":"k"}} {"kind":"k","a":4}', 'k'),
    'list': jsonOfKind('[{"kind":"k"}]', 'k'),
    'broken': jsonOfKind('{"kind":"k", "a": ', 'k'),
  };
  return out;
}

List<Food> _modelFoods() => [
      _mk('R1', 'Χυμός δοκιμής', 'Ροφήματα', {Nk.kcal: 45}, perMl: true),
      _mk('R2', 'Ρύζι δοκιμής (ωμό)', 'Δημητριακά', {Nk.kcal: 350}, cooked: const [('R3', 'Βρασμένο')]),
      _mk('R3', 'Ρύζι δοκιμής (βρασμένο)', 'Δημητριακά', {Nk.kcal: 130}, rawId: 'R2'),
      _mk('R4', 'Χωρίς κατηγορία', '', {Nk.kcal: 10}),
    ];

// --------------------------------------------------------------------------------------------------- αναζήτηση

Map<String, Object?> _searchGolden() {
  final out = <String, Object?>{};
  const words = [
    'Κοτόπουλο', 'κοτόπουλα', 'στήθος', 'Γιαούρτι', 'giaourti', 'yiaourti', 'γιαουρτιού', 'ΦΈΤΑ', 'φέτες', 'ρύζι', 'ρυζιού', 'rizi', 'ryzi',
    'φακές', 'φακή', 'fakes', 'αυγό', 'αυγά', 'avgo', 'αβγό', 'μπανάνα', 'banana', 'ντομάτα', 'τομάτες', 'domata', 'ψωμί', 'psomi',
    'βρασμένο', 'βραστό', 'ψητό', 'φούρνου', 'σχάρας', 'άσπρο', 'λευκό', 'γάλα', 'γαλακτοκομικά', 'κρέας', 'κρέατα', 'χωρίς', 'τσίπουρο',
    'τσιπούρα', 'ευχαριστώ', 'αυτοκίνητο', 'ξύδι', 'ψάρια', 'θαλασσινών', 'ς', '', '1,5%', 'ω-3', 'Ελαιόλαδο', 'elaiolado', 'ΐ',
  ];
  out['plain | phonetic | stem | stem(no synonyms)'] = <String, Object?>{
    for (final w in words) '«$w»': g141Safe(() => '${plain(w)} | ${phonetic(w)} | ${stem(phonetic(w))} | ${stem(phonetic(w), synonyms: false)}'),
  };
  out['rawFirstBonus'] = rawFirstBonus;

  const queries = [
    'κοτόπουλο', 'κοτοπουλο στηθος', 'kotopoulo', 'κοτόπολο', 'στήθος κοτόπουλου ψητό', 'γιαούρτι', 'giaourti', 'γιαουτρι', 'γιαούρτι 2%', 'φέτα',
    'ρύζι', 'ρυζι βρασμενο', 'ρύζι καστανό', 'φακές', 'φακές βρασμένες', 'μήλο', 'μπανάνα', 'αυγό', 'αυγα βραστα', 'ψωμί ολικής',
    'ελαιόλαδο', 'λάδι', 'τόνος', 'σολομός', 'μοσχάρι', 'μοσχάρι ψητό', 'γάλα', 'γαλα χωρις λακτοζη', 'τυρί', 'ντομάτα',
    'πατάτες φούρνου', 'καρύδια', 'μέλι θυμαρίσιο', 'ψάρι', 'κρέας', 'χωρίς ζάχαρη', 'βρώμη', 'πίτουρο', 'τσίπουρο', 'τσιπούρα',
    'ανθότυρο', 'μάρκα α', 'ξξξξ', 'α', '', '   ', 'κοτόπουλο ρύζι', 'espresso', 'καφές', 'φρούτα', 'όσπρια', 'ξηροί καρποί',
  ];
  final all = [...basicFoods(), ...sampleMine()];
  final index = FoodIndex(all);
  final store = sampleFoodStore(DateTime(2026, 11, 23, 16, 30));
  final byQuery = <String, Object?>{};
  for (final q in queries) {
    byQuery['«$q»'] = g141Safe(() {
      final r = index.find(q);
      final withHabits = store.find(q);
      return g141Compact(<String, Object?>{
        'n': r.foods.length,
        'top': [for (final f in r.foods.take(10)) '${f.id} ${f.name}'],
        'ignored': r.ignored,
        'corrected': r.corrected,
        'kept': r.kept,
        'droppedFood': r.droppedFood,
        'with habits': [for (final f in withHabits.foods.take(6)) f.id].join(' '),
        'limit 3': [for (final f in index.search(q, limit: 3)) f.id].join(' '),
      });
    });
  }
  out['find'] = byQuery;
  out['boost'] = <String, Object?>{
    for (final q in ['ρύζι', 'κοτόπουλο', 'γιαούρτι'])
      q: [for (final f in index.search(q, boost: {_rice: 1.5, _chicken: 0.5, 'Mdemo1': 2.0}, limit: 5)) f.id].join(' '),
  };
  out['empty'] = <String, Object?>{
    'foods': FoodSearchResult.empty.foods.length,
    'index of nothing': FoodIndex(const []).find('ρύζι').foods.length,
  };
  return out;
}

// ---------------------------------------------------------------------------------- AI φαγητού (χωρίς δίκτυο)

Map<String, Object?> _aiGolden() {
  final out = <String, Object?>{};
  final s = _store(likes: _likes);
  final allowed = aiAllowedIds(s);
  final aiLib = aiLibrary(s, allowed);
  const meals = [Meal.lunch, Meal.snack, Meal.dinner];
  const AiTargets targets = (kcal: 2150, protein: 140, satMax: 14.3, fiber: 30, salt: 5.0);
  out['constants'] = <String, Object?>{
    'kinds': [aiWeekKind, aiSwapKind, aiKeyPrefix],
    'aiMaxNewDishes': aiMaxNewDishes,
    'aiMaxRetries': aiMaxRetries,
    'aiParallel': aiParallel,
    'aiSwapKcalTol': aiSwapKcalTol,
    'aiSwapProteinMin': aiSwapProteinMin,
    'aiSwapSatExtra': aiSwapSatExtra,
    'aiQuickMinutes': aiQuickMinutes,
    'aiDayKcalTol': aiDayKcalTol,
    'aiDayProteinMin': aiDayProteinMin,
    'aiDayFiberMin': aiDayFiberMin,
    'aiFruitVegDayG': aiFruitVegDayG,
    'aiFreeSugarPct': aiFreeSugarPct,
    'aiWeekKcalTol': aiWeekKcalTol,
    'aiMaxAddedSaltG': aiMaxAddedSaltG,
    'aiMaxSaltG': aiMaxSaltG,
    'aiMaxFatsG': aiMaxFatsG,
    'aiMaxSweetG': aiMaxSweetG,
    'aiMaxProcessedG': aiMaxProcessedG,
    'aiMaxSpiceG': aiMaxSpiceG,
    'aiMaxAlcoholG': aiMaxAlcoholG,
    'aiPotMaxGap': aiPotMaxGap,
    'aiPotRiceGap': aiPotRiceGap,
    'aiPotUserShare': aiPotUserShare,
    'aiMercuryTwiPerKg': aiMercuryTwiPerKg,
    'aiMercuryPpm': aiMercuryPpm,
    'aiTailSat': aiTailSat,
    'aiTailSalt': aiTailSalt,
    'stapleSuggestions': [for (final x in stapleSuggestions) '${x.$1} ${x.$2}'],
  };
  out['aiAllowedIds'] = <String, Object?>{
    'likes': (allowed.toList()..sort()),
    'cooked form liked → raw': (aiAllowedIds(_store(likes: const FoodLikes(like: ['C6207'], staple: [_oil]))).toList()..sort()),
    'cooked form disliked → raw too': (aiAllowedIds(_store(likes: const FoodLikes(like: [_chicken, _beef], dislike: ['C6207']))).toList()..sort()),
    'never id and unknown': (aiAllowedIds(_store(likes: const FoodLikes(like: ['C26098', 'ZZ', _rice]))).toList()..sort()),
    'empty': aiAllowedIds(_store()).length,
  };
  out['aiLibrary'] = [for (final d in aiLib) planInfoOf(d)?.key];
  out['aiDishAllowed'] = <String, Object?>{for (final d in s.dishes) '${planInfoOf(d)?.key}': aiDishAllowed(s, d, allowed)};
  out['aiFoodLines'] = aiFoodLines(s, allowed);
  out['aiNutTail | aiNeedsCooking'] = <String, Object?>{
    for (final f in basicFoods()) '${f.id} ${f.name}': '${aiNutTail(f)}|${aiNeedsCooking(f) ? 'θέλει μαγείρεμα' : '-'}',
  };
  out['aiMealKcal'] = <String, Object?>{
    for (final kcal in [1500, 2090, 2150, 2175, 2800])
      for (final ms in const [
        [Meal.lunch, Meal.snack, Meal.dinner],
        [Meal.breakfast, Meal.lunch, Meal.dinner, Meal.snack],
        [Meal.lunch, Meal.dinner],
        [Meal.snack],
      ])
        '$kcal|${ms.map((m) => m.name).join('+')}': <String, Object?>{for (final e in aiMealKcal(kcal, ms).entries) e.key.name: e.value},
  };
  out['aiKeepsText'] = [aiKeepsText(false), aiKeepsText(true)];

  // Έλεγχοι ενός φαγητού (όρια αλατιού, λαδιού, ωμά σε «χωρίς μαγείρεμα» κ.λπ.).
  Dish hand(String key, DishKind kind, List<(String, double)> items, {String cook = 'home', List<String> mealNames = const ['lunch'], int? serv}) {
    var d = Dish(id: 'H-$key', name: 'Δοκιμή $key', kind: kind, servings: kind == DishKind.portions ? (serv ?? 2) : 1, created: 1, items: [
      for (final (id, g) in items) DishItem(id, _nameOf(id), g),
    ]);
    d = withPlanInfo(d, PlanInfo.fromJson(<String, Object?>{'key': key, 'meals': mealNames, 'cook': cook}));
    if (kind == DishKind.pot && serv != null) d = withRecipe(d, Recipe(tips: const ['α'], servings: serv));
    return d;
  }

  final handDishes = [
    hand('ok', DishKind.plate, [(_chicken, 200), (_rice, 90), (_oil, 10)]),
    hand('salt-1.2', DishKind.plate, [(_chicken, 200), (_rice, 90), (_salt, 1.2)]),
    hand('salt-1.3', DishKind.plate, [(_chicken, 200), (_rice, 90), (_salt, 1.3)]),
    hand('salty-feta', DishKind.plate, [(_feta, 120), (_rusks, 60)]),
    hand('oil-20', DishKind.plate, [(_chicken, 200), (_rice, 90), (_oil, 20)]),
    hand('oil-21', DishKind.plate, [(_chicken, 200), (_rice, 90), (_oil, 21)]),
    hand('raw-none', DishKind.plate, [(_chicken, 250), (_tomato, 200), (_egg, 60)], cook: 'none'),
    hand('tuna-none', DishKind.plate, [(_tunaCan, 150), (_tomato, 200), (_rusks, 40)], cook: 'none'),
    hand('tiny', DishKind.plate, [(_tomato, 300)]),
    hand('huge', DishKind.plate, [(_rice, 450)]),
    hand('snack-49', DishKind.plate, [(_apple, 90)], mealNames: const ['snack']),
    hand('snack-701', DishKind.plate, [(_rusks, 181)], mealNames: const ['snack']),
    hand('pot-2', DishKind.pot, [(_lentils, 500), (_onion, 150), (_oil, 40)], serv: 2),
    hand('pot-3', DishKind.pot, [(_lentils, 500), (_onion, 150), (_oil, 40)], serv: 3),
    hand('pot-none', DishKind.pot, [(_lentils, 500), (_onion, 150), (_oil, 40)]),
    hand('portions-2', DishKind.portions, [(_beef, 500), (_egg, 50)], serv: 2),
    hand('pepper-6', DishKind.plate, [(_chicken, 200), (_rice, 90), ('C11015', 6)]),
    hand('salted-cod', DishKind.plate, [('C26098', 150), (_rice, 90)]),
    hand('unknown-item', DishKind.plate, [(_chicken, 200)]).copyWith(items: const [DishItem('ZZ', 'Άγνωστο', 100)]),
  ];
  out['aiDishProblems'] = <String, Object?>{
    for (final d in [...s.dishes, ...handDishes]) '${planInfoOf(d)?.key}': aiDishProblems(s, d),
  };
  out['aiDishLine'] = [for (final d in s.dishes) aiDishLine(s, d)];

  // Οι οδηγίες προς το AI (κείμενο): κάθε αλλαγή στους κανόνες φαίνεται ως γραμμή που άλλαξε.
  AiWeekAsk ask([Map<(int, Meal), String> kept = const {}, int days = 7]) => (from: _monday, days: days, meals: meals, kept: kept);
  out['aiSystem'] = <String, Object?>{
    'no limits': g141Lines(aiSystem(s, allowed, Kitchen.initial())),
    'with limits': g141Lines(aiSystem(s, allowed, Kitchen(devices: {'hob'}), limits: targets)),
  };
  out['aiPlanPrompt'] = <String, Object?>{
    'default': g141Lines(aiPlanPrompt(food: s, ask: ask(), library: aiLib, dayKcal: 2150)),
    'kept, legumes 3, fish 1': g141Lines(aiPlanPrompt(
        food: s, ask: ask({(0, Meal.lunch): _k(s, 'fakes').id, (2, Meal.dinner): _k(s, 'solomos').id}, 5), library: aiLib, dayKcal: 1800, legumesWeek: 3, fishWeek: 1)),
    'empty library': g141Lines(aiPlanPrompt(food: s, ask: ask(), library: const [], dayKcal: 2150)),
  };
  const newKey = 'ai-kotopoulo-fournou';
  Map<String, Object> newJson({String key = newKey}) => {
        'key': key,
        'name': 'Κοτόπουλο φούρνου με ντομάτα',
        'type': 'pot',
        'cook': 'home',
        'minutes': 50,
        'meals': ['lunch', 'dinner'],
        'office': true,
        'idea': 'κοτόπουλο, ντομάτα, κρεμμύδι, ελαιόλαδο',
      };
  AiNewDish want({String key = newKey}) => AiNewDish(key: key, name: 'Κοτόπουλο φούρνου με ντομάτα', idea: 'κοτόπουλο, ντομάτα', json: newJson(key: key));
  out['aiRecipePrompt'] = g141Lines(aiRecipePrompt(want()));
  out['AiNewDish'] = <String, Object?>{
    'full': '${want().kind.name}|${want().cook.name}|${want().office}|${want().meals.map((m) => m.name).join('+')}|${want().minutes}',
    'empty': () {
      const n = AiNewDish(key: 'ai-x', name: 'Χ', idea: '', json: <String, dynamic>{});
      return '${n.kind.name}|${n.cook.name}|${n.office}|${n.meals.length}|${n.minutes}';
    }(),
  };

  // Το σχέδιο εβδομάδας του AI: σωστό και λάθη.
  final planDays = [
    ['kotopoulo-ryzi', 'giaourti', 'fakes'],
    ['fakes', 'frygania', newKey],
    [newKey, 'giaourti', 'tsipoura'],
    ['kotopoulo-salata', 'milo-giaourti', 'kotopoulo-ryzi'],
    ['fasolada', 'frygania', 'solomos'],
    ['revithia', 'giaourti', 'fasolada'],
    ['kotopoulo-salata', 'milo-giaourti', 'revithia'],
  ];
  Map<String, Object> planJson({List<List<String>>? days, List<Map<String, Object>>? news}) => {
        'kind': aiWeekKind,
        'new': news ?? [newJson()],
        'days': [
          for (final d in days ?? planDays)
            [
              {'meal': 'lunch', 'key': d[0]},
              {'meal': 'snack', 'key': d[1]},
              {'meal': 'dinner', 'key': d[2]},
            ],
        ],
      };
  final libMap = {for (final d in aiLib) planInfoOf(d)!.key!: d};
  final allKeys = {for (final d in libraryDishes(s.dishes)) planInfoOf(d)!.key!};
  Map<String, Object?> planView(AiPlanParse p) => g141Compact(<String, Object?>{
        'errors': p.errors,
        'new': [for (final n in p.plan?.newDishes ?? const <AiNewDish>[]) n.key],
        'days': [
          for (final d in p.plan?.days ?? const <List<(Meal, String)>>[]) [for (final x in d) '${x.$1.name}:${x.$2}'].join(' | '),
        ],
      });
  List<List<String>> edit(void Function(List<List<String>> d) f) {
    final d = [for (final x in planDays) List.of(x)];
    f(d);
    return d;
  }

  Object? plan(List<List<String>> d, {List<Map<String, Object>>? news}) =>
      g141Safe(() => planView(parseAiPlan(_fence(planJson(days: d, news: news)), ask(), libMap, allKeys)));
  out['parseAiPlan'] = <String, Object?>{
    'ok': plan(planDays),
    'not the kind': g141Safe(() => planView(parseAiPlan('{"kind": "x"}', ask(), libMap, allKeys))),
    'disliked dish': plan(edit((d) => d[0][2] = 'mosxari')),
    'unknown key': plan(edit((d) => d[0][2] = 'pastitsio')),
    'office lunch not for office': plan(edit((d) => d[1][0] = 'kotopoulo-ryzi')),
    'dinner dish at lunch': plan(edit((d) => d[5][0] = 'solomos')),
    'same dish three days': plan(edit((d) {
      d[0][0] = 'kotopoulo-salata';
      d[1][0] = 'kotopoulo-salata';
      d[2][0] = 'kotopoulo-salata';
    })),
    'pot four days apart': plan(edit((d) => d[4][2] = 'fakes')),
    'new dish not used': plan(edit((d) {
      d[1][2] = 'tsipoura';
      d[2][0] = 'kotopoulo-salata';
    })),
    'new key without prefix': plan(planDays, news: [newJson(key: 'kotopoulo-fournou')]),
    'new key already in library': plan(planDays, news: [newJson(key: 'fakes')]),
    'nine new dishes': plan(planDays, news: [for (var i = 0; i < 9; i++) newJson(key: 'ai-neo-$i')]),
    'six days': plan(planDays.sublist(0, 6)),
    'missing snack': g141Safe(() => planView(parseAiPlan(
        _fence({
          'kind': aiWeekKind,
          'new': [newJson()],
          'days': [
            for (final d in planDays)
              [
                {'meal': 'lunch', 'key': d[0]},
                {'meal': 'dinner', 'key': d[2]},
              ],
          ],
        }),
        ask(),
        libMap,
        allKeys))),
    'kept slots': g141Safe(() => planView(parseAiPlan(_fence(planJson()), ask({(0, Meal.lunch): _k(s, 'kotopoulo-ryzi').id}), libMap, allKeys,
        keptKeys: {(0, Meal.lunch): 'kotopoulo-ryzi'}))),
    'kept slot changed by AI': g141Safe(() => planView(
        parseAiPlan(_fence(planJson()), ask({(0, Meal.lunch): _k(s, 'fakes').id}), libMap, allKeys, keptKeys: {(0, Meal.lunch): 'fakes'}))),
    'new key in allKeys': g141Safe(() => planView(parseAiPlan(_fence(planJson()), ask(), libMap, {...allKeys, newKey}))),
  };

  // Μία συνταγή του AI: σωστή και λάθη.
  Map<String, Object> recipeJson(List<(String, double)> items, {String key = newKey, String type = 'pot', String cook = 'home', bool office = true}) => {
        'kind': libraryKind,
        'dishes': [
          {
            ..._dish(key, type, items, meals: ['lunch', 'dinner'], office: office, servings: type == 'plate' ? null : 4, minutes: 50, cook: cook),
            'name': 'Κοτόπουλο φούρνου με ντομάτα',
            'kcal': 99999,
          },
        ],
      };
  var counter = 0;
  Object? read(Map<String, Object> j, {AiNewDish? w, Set<Meal> needMeals = const {}, bool office = false}) => g141Safe(() {
        final r = aiReadDish(_fence(j), food: s, allowed: allowed, now: 1, newId: () => 'N${counter++}', want: w, needMeals: needMeals, needOffice: office);
        return g141Compact(<String, Object?>{'errors': r.errors, 'dish': r.dish?.toJson()});
      });

  out['aiReadDish'] = <String, Object?>{
    'ok': read(recipeJson([(_chicken, 900), (_tomato, 400), (_onion, 150), (_oil, 30)]), w: want(), needMeals: {Meal.lunch, Meal.dinner}, office: true),
    'ok with rice': read(recipeJson([(_chicken, 900), (_rice, 300), (_oil, 30)]), w: want()),
    'not allowed item': read(recipeJson([(_chicken, 800), (_beef, 200), (_oil, 30)]), w: want()),
    'raw in no-cook': read(recipeJson([(_chicken, 250), (_tomato, 200), (_oil, 10)], key: 'ai-kotosalata', type: 'plate', cook: 'none')),
    'canned tuna no-cook': read(recipeJson([(_tunaCan, 150), (_tomato, 200), (_oil, 10), (_rusks, 40)], key: 'ai-tonosalata', type: 'plate', cook: 'none')),
    'salt 60 g': read(recipeJson([(_chicken, 200), (_rice, 90), (_oil, 10), (_salt, 60)], key: 'ai-a', type: 'plate')),
    'oil 120 g': read(recipeJson([(_chicken, 200), (_rice, 90), (_oil, 120)], key: 'ai-b', type: 'plate')),
    'type and office differ from plan': read(recipeJson([(_chicken, 900), (_tomato, 400), (_onion, 150), (_oil, 30)], type: 'plate', office: false),
        w: want(), needMeals: {Meal.lunch}, office: true),
    'key without ai-': read(recipeJson([(_chicken, 900), (_tomato, 400)], key: 'kotopoulo')),
    'other key than asked': read(recipeJson([(_chicken, 900), (_tomato, 400)], key: 'ai-allo'), w: want()),
    'not a library': read({'kind': 'x'}),
    'two dishes': read({
      'kind': libraryKind,
      'dishes': [
        _dish('ai-1', 'plate', [(_chicken, 200), (_rice, 90)], meals: ['lunch']),
        _dish('ai-2', 'plate', [(_chicken, 200), (_rice, 90)], meals: ['lunch']),
      ],
    }),
  };

  // Έλεγχος εβδομάδας (όρια μέρας, όσπρια/ψάρι, κατσαρόλα, λεπτά) πάνω σε προγράμματα με σταθερό seed.
  WeekPlan auto({int seed = 1, double kcal = 2150, double protein = 140}) =>
      autoWeek(s, from: _monday, meals: meals, kcalTarget: kcal, proteinTarget: protein, legumesWeek: 4, fishWeek: 2, seed: seed, now: 1).plan;
  Object? problems(WeekPlan w, {AiTargets t = targets, Set<int>? checkDays, int legumes = 4, int fish = 2, double? bodyKg, List<Meal> ms = meals}) => g141Safe(() {
        final ps =
            aiCheckWeek(s, w, const [], t: t, meals: ms, checkDays: checkDays ?? {for (var i = 0; i < w.days.length; i++) i}, legumesWeek: legumes, fishWeek: fish, bodyKg: bodyKg);
        return [
          'score ${aiScore(ps).toStringAsFixed(3)}',
          for (final p in ps) '[${p.day ?? '-'}] ×${p.weight} ΧΡΗΣΤΗΣ: ${p.user} ## AI: ${p.ai}',
        ];
      });

  final w1 = auto();
  Dish k(String key) => _k(s, key);
  WeekPlan weekOf(List<List<PlanSlot>> days) => WeekPlan(from: '2026-11-23', days: days, created: 1, meals: meals);
  PlanSlot slot(Meal m, String key, [double? kcal]) => PlanSlot(meal: m, dishId: k(key).id, kcal: kcal);
  final heavy = weekOf([
    [slot(Meal.lunch, 'kotopoulo-salata', 900), slot(Meal.snack, 'frygania', 400), slot(Meal.dinner, 'mosxari', 800)],
    [slot(Meal.lunch, 'fakes'), slot(Meal.snack, 'giaourti', 250), slot(Meal.dinner, 'fakes')],
    [slot(Meal.snack, 'giaourti', 440), slot(Meal.dinner, 'tsipoura', 770)],
    [slot(Meal.lunch, 'fakes'), slot(Meal.snack, 'milo-giaourti'), slot(Meal.dinner, 'kotopoulo-ryzi', 700)],
    [slot(Meal.lunch, 'tonosalata', 700), slot(Meal.snack, 'frygania', 300), slot(Meal.dinner, 'solomos', 900)],
    [slot(Meal.lunch, 'kotopoulo-ryzi', 800), slot(Meal.snack, 'giaourti', 300), slot(Meal.dinner, 'kotopoulo-ryzi', 800)],
    [slot(Meal.lunch, 'revithia'), slot(Meal.snack, 'giaourti', 300), const PlanSlot(meal: Meal.dinner, dishId: 'gone', kcal: 700)],
  ]);
  out['aiCheckWeek'] = <String, Object?>{
    'auto seed 1': problems(w1),
    'auto seed 2': problems(auto(seed: 2)),
    'auto seed 1, only days 0-2': problems(w1, checkDays: {0, 1, 2}),
    'auto seed 1, strict targets': problems(w1, t: (kcal: 2150, protein: 190, satMax: 8.0, fiber: 45, salt: 2.0)),
    'auto seed 1 for 1500 kcal checked at 2150': problems(auto(kcal: 1500, protein: 110)),
    'hand-made heavy week': problems(heavy, bodyKg: 82.0),
    'hand-made heavy week, 60 kg, no weekly rules': problems(heavy, bodyKg: 60, legumes: 0, fish: 0),
    'empty week': problems(weekOf([for (var i = 0; i < 7; i++) const <PlanSlot>[]])),
  };

  // Αλλαγή γεύματος και «έφαγα κάτι άλλο».
  out['portionFor'] = <String, Object?>{
    for (final d in s.dishes)
      '${planInfoOf(d)?.key}': [
        for (final kcal in [50.0, 300.0, 643.0, 1200.0, 4000.0])
          () {
            final p = portionFor(s, d, kcal);
            return p == null ? 'null' : '$kcal→${_n1(p.kcal)} (${_n1(p.n.kcal)} kcal, πρωτ ${_n1(p.n.protein)}, κορ ${_n2(p.n.sat)}, αλάτι ${_n2(p.n.salt)}, ίνες ${_n1(p.n.fiber)})';
          }(),
      ],
  };
  const old = (kcal: 600.0, protein: 45.0, sat: 5.0, salt: 1.0, fiber: 5.0);
  out['analogProblems'] = <String, Object?>{
    for (final (name, cand) in <(String, SlotNumbers)>[
      ('same', old),
      ('kcal 660', (kcal: 660.0, protein: 45.0, sat: 5.0, salt: 1.0, fiber: 5.0)),
      ('kcal 660.1', (kcal: 660.1, protein: 45.0, sat: 5.0, salt: 1.0, fiber: 5.0)),
      ('kcal 539.9', (kcal: 539.9, protein: 45.0, sat: 5.0, salt: 1.0, fiber: 5.0)),
      ('protein 40.5', (kcal: 600.0, protein: 40.5, sat: 5.0, salt: 1.0, fiber: 5.0)),
      ('protein 40.4', (kcal: 600.0, protein: 40.4, sat: 5.0, salt: 1.0, fiber: 5.0)),
      ('sat 6.0', (kcal: 600.0, protein: 45.0, sat: 6.0, salt: 1.0, fiber: 5.0)),
      ('sat 6.01', (kcal: 600.0, protein: 45.0, sat: 6.01, salt: 1.0, fiber: 5.0)),
      ('all', (kcal: 900.0, protein: 10.0, sat: 12.0, salt: 9.0, fiber: 0.0)),
    ])
      name: analogProblems(old, cand),
  };
  out['swapChecks'] = <String, Object?>{
    for (final d in s.dishes)
      for (final why in SwapReason.values)
        '${planInfoOf(d)?.key}|${why.name}': swapChecks(s, d,
                meal: Meal.lunch, office: why == SwapReason.missing, reason: why, missingId: why == SwapReason.missing ? _feta : null, old: old, allowed: allowed, currentId: k('kotopoulo-ryzi').id)
            .join(' · '),
  };
  out['swapWarnings'] = <String, Object?>{
    for (final (from, to) in [('fakes', 'kotopoulo-ryzi'), ('solomos', 'mosxari'), ('kotopoulo-ryzi', 'fakes'), ('tsipoura', 'solomos'), ('giaourti', 'frygania'), ('kotopoulo-salata', 'tonosalata')])
      '$from → $to': g141Safe(() => swapWarnings(s, k(from), slot(Meal.dinner, from, 650), k(to), 650)),
  };
  out['applySwap'] = g141Safe(
      () => _planView(s, applySwap(_mark(w1, 0, 0, (x) => x.copyWith(locked: true, state: SlotState.skip, grp: 'g')), 0, 0, k('tonosalata'), 555))[0]);
  Object? rebalance(WeekPlan w, {required double eaten, required double eatenProtein, double target = 2150, Meal after = Meal.lunch}) => g141Safe(() {
    final r = rebalanceDay(s, w, 0, eaten: eaten, eatenProtein: eatenProtein, target: target, after: after, now: DateTime(2026, 11, 23, 15));
    if (r == null) return null;
    return <String, Object?>{
      'day': _planView(s, r.plan)[0],
      'changes': [for (final c in r.changes) '${c.$1.name} ${c.$2}: ${_n1(c.$3)} → ${_n1(c.$4)}'],
      'dayKcal': r.dayKcal,
      'proteinBefore': r.proteinBefore,
      'proteinAfter': r.proteinAfter,
    };
  });

  final lunch = w1.days[0].indexWhere((x) => x.meal == Meal.lunch);
  final ate = _mark(w1, 0, lunch, (x) => x.copyWith(state: SlotState.other));
  var lockedAll = ate;
  for (var i = 0; i < lockedAll.days[0].length; i++) {
    lockedAll = _mark(lockedAll, 0, i, (x) => x.copyWith(locked: true));
  }
  out['rebalanceDay'] = <String, Object?>{
    'ate 1100 at lunch': rebalance(ate, eaten: 1100, eatenProtein: 40),
    'ate 300 at lunch': rebalance(ate, eaten: 300, eatenProtein: 30),
    'ate 860 at lunch (as planned)': rebalance(ate, eaten: 860, eatenProtein: 60),
    'ate 2500': rebalance(ate, eaten: 2500, eatenProtein: 80),
    'after dinner': rebalance(ate, eaten: 1100, eatenProtein: 40, after: Meal.dinner),
    'after snack': rebalance(ate, eaten: 1100, eatenProtein: 40, after: Meal.snack),
    'all locked': rebalance(lockedAll, eaten: 1100, eatenProtein: 40),
    'target 1500': rebalance(ate, eaten: 1100, eatenProtein: 40, target: 1500),
  };
  return out;
}

void main() {
  test('golden141 · τρόφιμα, σύνολα ημέρας, μονάδες, Open Food Facts, χοληστερόλη, κουζίνα', () => runGolden('food_model', _modelGolden));
  test('golden141 · φαγητά, πρόγραμμα εβδομάδας, βιβλιοθήκη, συνταγές', () => runGolden('food_dishes', _dishesGolden));
  test('golden141 · αναζήτηση τροφίμων', () => runGolden('food_search', _searchGolden));
  test('golden141 · AI φαγητού (οδηγίες, έλεγχοι, αλλαγές) χωρίς δίκτυο', () => runGolden('food_ai', _aiGolden));
}
