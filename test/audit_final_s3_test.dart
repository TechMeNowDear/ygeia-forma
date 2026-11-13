// Τελικός έλεγχος, Συμβούλιο 3 (ανάγνωση εξωτερικών δεδομένων): αριθμοί που πληκτρολογούνται, προϊόντα από το Open Food
// Facts, barcode, αντίγραφα ασφαλείας, ρυθμίσεις από αντίγραφο. Οι εξετάσεις είναι στο test/labs_test.dart.
// Όλα τα δεδομένα εδώ είναι φανταστικά (δημόσιο repo).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/backup.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/food/kitchen.dart';
import 'package:ygeia_forma/food/off.dart';
import 'package:ygeia_forma/pages/food_add.dart'
    show FoodFormScreen, barcodeUnreadText, parseNumber, servingErrorText, servingRejected;
import 'package:ygeia_forma/profile.dart';
import 'package:ygeia_forma/theme.dart';

const _food = <String, Object>{
  'id': 'M1',
  'name': 'Γιαούρτι 2%',
  'cat': 'Τα προϊόντα μου',
  'source': 'Ετικέτα',
  'n': {'kcal': 70, 'protein': 10, 'salt': {'lt': 0.1}},
};

final _entry = <String, Object>{
  'id': 'E1',
  'day': '2026-11-01',
  'meal': 'lunch',
  'food': _food,
  'grams': 170,
  'time': DateTime(2026, 11, 1, 14).millisecondsSinceEpoch,
};

/// Το κείμενο ενός αντιγράφου, με τις λίστες ήδη σε JSON (ώστε να χωρά και «1e999», που το jsonEncode δεν γράφει).
String _backup(String log, String mine, {String version = '1'}) =>
    '{"app":"$backupApp","version":$version,"foodLog":$log,"myFoods":$mine}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Τ1: αριθμός που πληκτρολογείται (parseNumber)', () {
    test('ό,τι διαβαζόταν σωστά διαβάζεται ίδια', () {
      for (final (text, value) in <(String, double)>[
        ('12,5', 12.5), ('12.5', 12.5), ('1.000', 1000), ('1.250', 1250), ('12.500', 12500), ('1.250,75', 1250.75),
        ('0,5', 0.5), ('0.5', 0.5), ('0.500', 0.5), ('1.5', 1.5), ('1.50', 1.5), ('1.5000', 1.5), ('100', 100),
        (' 250 ', 250), ('1 250', 1250), (',5', 0.5), ('5,', 5), ('.5', 0.5), ('5.', 5), ('1.000.000', 1000000), ('1,250', 1.25),
      ]) {
        expect(parseNumber(text), value, reason: text);
      }
      for (final text in ['', ' ', ',', '.', '1,2,3', '1.5.5', 'abc', '12a']) {
        expect(parseNumber(text), isNull, reason: text);
      }
    });

    test('αμερικάνικη γραφή και κακές ομάδες χιλιάδων δεν μαντεύονται', () {
      // Πριν: «1,250.75» → 1,25075 (χίλιες φορές κάτω)· «3.76,» → 376 (εκατό φορές πάνω)· «1.2,5» → 12,5.
      for (final text in ['1,250.75', '3.76,', '1.2,5', '12.5,5', '1.00,5']) {
        expect(parseNumber(text), isNull, reason: text);
      }
    });

    test('μόνο ψηφία, τελεία, κόμμα· πάντα πεπερασμένος αριθμός', () {
      // Πριν περνούσαν από το double.tryParse: αρνητικό, εκθέτης, «NaN», «Infinity».
      for (final text in ['-5', '+5', '1e3', 'NaN', 'Infinity', '-Infinity', '0x10', '5 g', '9' * 400]) {
        expect(parseNumber(text), isNull, reason: text.length > 20 ? '400 ψηφία' : text);
      }
      // Κενά που βάζουν μερικά πληκτρολόγια και η επικόλληση ανάμεσα στις χιλιάδες.
      expect(parseNumber('1\u{A0}250'), 1250);
      expect(parseNumber('1\u{202F}250,5'), 1250.5);
    });
  });

  group('Τ2/Τ5: μία μερίδα', () {
    test('μόνο πάνω από 0 και ως 5.000· αλλιώς «χωρίς μερίδα»', () {
      expect(maxEntryGrams, 5000);
      expect(validServing(30), 30);
      expect(validServing(5000), 5000);
      for (final Object? bad in [0, -5, 5000.1, double.infinity, double.nan, '30', null, true]) {
        expect(validServing(bad), isNull, reason: '$bad');
      }
    });

    test('προϊόν με μερίδα 0, αρνητική ή τεράστια: διαβάζεται, χωρίς μερίδα', () {
      Food read(Object? serving) => Food.fromJson({..._food, 'servingGrams': serving});
      expect(read(30).servingGrams, 30);
      for (final Object? bad in [0, -20, 60000, 'τριάντα']) {
        final f = read(bad);
        expect((f.id, f.servingGrams), ('M1', null), reason: '$bad');
        expect(f.n.amount(Nk.kcal), 70, reason: 'οι τιμές μένουν');
      }
    });
  });

  group('Β3: μήνυμα για τη μερίδα και για barcode που δεν διαβάστηκε (κείμενα εγκρίθηκαν 12/11)', () {
    test('το πεδίο «Μία μερίδα»: κενό δεκτό, ό,τι άλλο πρέπει να είναι πάνω από 0 και ως 5.000', () {
      for (final ok in ['', '   ', '30', '0,5', '5000', '5.000', '1.250,5']) {
        expect(servingRejected(ok), isFalse, reason: '«$ok»');
      }
      for (final bad in ['0', '0,0', '5000,1', '5.001', '60000', '3.76,', '1,2,3', ',', '.']) {
        expect(servingRejected(bad), isTrue, reason: '«$bad»');
      }
      expect(servingErrorText(perMl: false), 'Γράψε μερίδα ως 5.000 g, ή άφησέ το κενό.');
      expect(servingErrorText(perMl: true), 'Γράψε μερίδα ως 5.000 ml, ή άφησέ το κενό.');
      expect(barcodeUnreadText, 'Δεν διαβάστηκε το barcode. Δοκίμασε ξανά.');
    });

    testWidgets('μερίδα «0»: η αποθήκευση περιμένει και το πεδίο λέει τι θέλει· με «30» αποθηκεύεται', (t) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(400, 2400);
      addTearDown(t.view.reset);
      Food? saved;
      var popped = false;
      final draft = FoodDraft(name: 'Κράκερ', values: {Nk.kcal: 450, Nk.protein: 8, Nk.carbs: 60, Nk.fat: 18});
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                saved = await Navigator.of(ctx).push<Food>(MaterialPageRoute(builder: (_) => FoodFormScreen(draft: draft)));
                popped = true;
              },
              child: const Text('άνοιξε'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('άνοιξε'));
      await t.pumpAndSettle();
      final serving = find.byKey(const ValueKey('field-serving'));
      await t.ensureVisible(serving);
      await t.enterText(serving, '0');
      await t.pumpAndSettle();
      expect(find.text(servingErrorText(perMl: false)), findsNothing, reason: 'πριν πατηθεί «Αποθήκευση» δεν ενοχλεί');
      await t.ensureVisible(find.text('Αποθήκευση'));
      await t.tap(find.text('Αποθήκευση'));
      await t.pumpAndSettle();
      expect(popped, isFalse, reason: 'η φόρμα μένει ανοιχτή');
      expect(find.text(servingErrorText(perMl: false)), findsOneWidget);

      await t.enterText(serving, '30');
      await t.pumpAndSettle();
      expect(find.text(servingErrorText(perMl: false)), findsNothing, reason: 'το μήνυμα φεύγει μόλις διορθωθεί');
      await t.ensureVisible(find.text('Αποθήκευση'));
      await t.tap(find.text('Αποθήκευση'));
      await t.pumpAndSettle();
      expect(popped, isTrue);
      expect(saved!.servingGrams, 30);
    });

    testWidgets('κενή μερίδα: αποθηκεύεται χωρίς μερίδα, όπως πριν', (t) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(400, 2400);
      addTearDown(t.view.reset);
      Food? saved;
      final draft = FoodDraft(name: 'Κράκερ', values: {Nk.kcal: 450, Nk.protein: 8, Nk.carbs: 60, Nk.fat: 18});
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                saved = await Navigator.of(ctx).push<Food>(MaterialPageRoute(builder: (_) => FoodFormScreen(draft: draft)));
              },
              child: const Text('άνοιξε'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('άνοιξε'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Αποθήκευση'));
      await t.tap(find.text('Αποθήκευση'));
      await t.pumpAndSettle();
      expect(saved, isNotNull);
      expect(saved!.servingGrams, isNull);
    });
  });

  group('Τ3: Open Food Facts', () {
    const base = {'energy-kcal_100g': 100, 'proteins_100g': 5, 'carbohydrates_100g': 10, 'fat_100g': 3};
    FoodDraft draft({Map<String, Object?> n = const {}, Object? serving}) =>
        draftFromOff('1', {'nutriments': {...base, ...n}, if (serving != null) 'serving_quantity': serving});

    test('μερίδα: μόνο όταν γίνεται να γραφτεί ως ποσότητα', () {
      expect(draft(serving: 30).servingGrams, 30);
      expect(draft(serving: '33,5').servingGrams, 33.5);
      for (final Object bad in [0, -30, 120000, 'NaN', 'Infinity', '1e999', double.infinity, 'δύο']) {
        expect(draft(serving: bad).servingGrams, isNull, reason: '$bad');
      }
    });

    test('αλκοόλ, πολυόλες, ερυθριτόλη: πάνω από 0 και ως 100, αλλιώς δεν μετρούν', () {
      expect(draft(n: {'alcohol_100g': 5}).alcohol, closeTo(3.945, 1e-9));
      expect(draft(n: {'alcohol': '12,5'}).alcohol, closeTo(12.5 * 0.789, 1e-9));
      expect(draft(n: {'alcohol_100g': 400}).alcohol, isNull, reason: '400% vol δεν γίνεται');
      expect(draft(n: {'alcohol_100g': -1}).alcohol, isNull);
      expect(draft(n: {'polyols_100g': 40}).polyols, 40);
      expect(draft(n: {'polyols_100g': 250}).polyols, isNull);
      expect(draft(n: {'erythritol_100g': 100}).erythritol, 100);
      expect(draft(n: {'erythritol_100g': '1e999'}).erythritol, isNull);
    });

    test('τιμή που δεν είναι πεπερασμένος αριθμός μετρά ως «λείπει», και το προϊόν γράφεται σε JSON', () {
      expect(draft(n: {'energy-kcal_100g': 'NaN'}).values[Nk.kcal], isNull);
      expect(draft(n: {'energy-kcal_100g': double.infinity}).missing, [Nk.kcal]);
      expect(draft(n: {'energy-kcal_100g': 'Infinity', 'energy_100g': 418.4}).values[Nk.kcal], 100, reason: 'τότε από τα kJ');
      expect(draft(n: {'proteins_100g': double.infinity}).values[Nk.protein], isNull);
      expect(draft(n: {'fat_100g': '-3'}).values[Nk.fat], isNull);
      // Πριν: αλκοόλ «άπειρο» έφτανε ως το προϊόν, και το jsonEncode πετούσε σφάλμα στην αποθήκευση.
      final d = draft(n: {'alcohol_100g': double.infinity, 'polyols_100g': double.infinity}, serving: double.infinity);
      expect(() => jsonEncode(foodFromDraft(d..name = 'Δοκιμή', 'M9').toJson()), returnsNormally);
    });

    test('αλάτι 0 μαζί με νάτριο > 0: μετρά το νάτριο', () {
      final fixed = draft(n: {'salt_100g': 0, 'sodium_100g': 0.4});
      expect((fixed.values[Nk.salt], fixed.saltFromSodium, fixed.sodiumMg), (1.0, true, 400.0));
      final zero = draft(n: {'salt_100g': 0, 'sodium_100g': 0});
      expect((zero.values[Nk.salt], zero.saltFromSodium), (0.0, false));
      final has = draft(n: {'salt_100g': 1.2, 'sodium_100g': 0.4});
      expect((has.values[Nk.salt], has.saltFromSodium), (1.2, false), reason: 'όταν υπάρχει αλάτι, μένει');
      final only = draft(n: {'sodium_100g': 0.4});
      expect((only.values[Nk.salt], only.saltFromSodium), (1.0, true), reason: 'όπως πριν');
      // Το «<» ακολουθεί την τιμή που κρατήθηκε.
      expect(draft(n: {'salt_100g': 0, 'salt_modifier': '<', 'sodium_100g': 0.4}).lessThan, isEmpty);
      final lt = draft(n: {'salt_100g': 0, 'sodium_100g': 0.002, 'sodium_modifier': '<'});
      expect(lt.values[Nk.salt], 0.005);
      expect(lt.lessThan, {Nk.salt});
      final inf = draft(n: {'salt_100g': 0, 'sodium_100g': double.infinity});
      expect((inf.values[Nk.salt], inf.saltFromSodium), (0.0, false), reason: 'άπειρο νάτριο αγνοείται');
    });
  });

  group('Τ4: barcode από τον σαρωτή', () {
    test('μόνο ψηφία, 8 ή 13 μετά την ενιαία μορφή', () {
      for (final (Object? raw, String? code) in <(Object?, String?)>[
        ('5201234567890', '5201234567890'),
        (' 5201234567890 ', '5201234567890'),
        ('012345678905', '0012345678905'),
        ('00012345678905', '0012345678905'),
        ('12345670', '12345670'),
        ('', null),
        ('   ', null),
        ('abc', null),
        ('1234567', null),
        ('123456789', null),
        ('520123456789a', null),
        ('520-1234567890', null),
        ('12345678901234', null),
        (null, null),
        (5201234567890, null),
      ]) {
        expect(scannedBarcode(raw), code, reason: '$raw');
      }
    });

    test('κενός κωδικός δεν «βρίσκει» προϊόν που αποθηκεύτηκε με κενό barcode', () {
      Food mine(String id, String barcode) =>
          Food(id: id, name: 'Προϊόν $id', cat: myFoodsCategory, n: Nutrients({Nk.kcal: const NValue(100)}), source: 'Ετικέτα', barcode: barcode);
      final s = FoodStore.preloaded(foods: const [], mine: [mine('M1', ''), mine('M2', '0012345678905')]);
      expect(s.byBarcode(''), isNull);
      expect(s.byBarcode('abc'), isNull);
      expect(s.byBarcode('012345678905')?.id, 'M2', reason: 'τα κανονικά βρίσκονται όπως πριν');
    });
  });

  group('Α2/Α3: αντίγραφο ασφαλείας', () {
    String e(Map<String, Object?> change) => jsonEncode({..._entry, ...change});
    Map<String, Object> foodWith(Map<String, Object> n) => {..._food, 'n': n};

    test('παραλείπεται ό,τι η εφαρμογή δεν γράφει ποτέ· τα υπόλοιπα μένουν', () {
      final log = '[${[
        e({}),
        e({'id': 'E2', 'day': '2026-13-45'}),
        e({'id': 'E3', 'day': 'χθες'}),
        e({'id': 'E4', 'day': '2026-02-30'}),
        e({'id': 'E5'}).replaceFirst('"grams":170', '"grams":1e999'),
        e({'id': 'E6', 'grams': 250000}),
        e({'id': 'E7', 'grams': 6000}),
        e({'id': 'E8', 'grams': -5}),
        e({'id': 'E9', 'food': foodWith({'kcal': -70})}),
        e({'id': 'E10', 'food': foodWith({'kcal': 70, 'salt': {'lt': -1}})}),
        e({'id': 'E11'}).replaceFirst('"kcal":70', '"kcal":1e999'),
        e({'id': 'E1', 'grams': 999}),
        e({'id': 'E12', 'food': foodWith({'kcal': 5000})}),
        e({'id': 'E13', 'day': '2026-11-02', 'grams': 100000}),
      ].join(',')}]';
      final mine = '[${[
        jsonEncode(_food),
        jsonEncode({..._food, 'id': 'M2', 'name': '   '}),
        jsonEncode({..._food, 'id': 'M3', 'n': {'kcal': 70, 'fat': -1}}),
        jsonEncode({..._food, 'name': 'δεύτερο με το ίδιο id'}),
        jsonEncode({..._food, 'id': 'M4', 'servingGrams': 0}),
        jsonEncode({..._food, 'id': 'M5', 'servingGrams': 30}),
        jsonEncode({..._food, 'id': 'M6', 'n': {'kcal': 70}}).replaceFirst('"kcal":70', '"kcal":1e999'),
      ].join(',')}]';
      final b = parseBackup(_backup(log, mine));
      // E7 (6 κιλά) και E12 (5.000 kcal ανά 100 g) είναι παράλογα αλλά γίνεται να τα έχει γράψει παλιά έκδοση: μένουν,
      // και τα δείχνει η «Αναφορά για έλεγχο» (food-grams, food-values). Τίποτα δικό σου δεν χάνεται στην επαναφορά.
      expect(b.entries.map((x) => x.id), ['E1', 'E7', 'E12', 'E13']);
      expect(b.entries.first.grams, 170, reason: 'από δύο εγγραφές με το ίδιο id μένει η πρώτη');
      expect(b.myFoods.map((x) => x.id), ['M1', 'M4', 'M5']);
      expect(b.myFoods.map((x) => x.servingGrams), [null, null, 30.0], reason: 'μερίδα 0 = χωρίς μερίδα, το προϊόν μένει');
      expect(b.skipped, 14, reason: '10 καταχωρίσεις και 4 προϊόντα');
      expect(backupMaxGrams, 100000);
    });

    test('έκδοση που δεν είναι πεπερασμένος αριθμός: καθαρό μήνυμα, όχι άλλο σφάλμα', () {
      for (final (version, part) in [('1e999', 'δεν είναι αντίγραφο'), ('"1"', 'δεν είναι αντίγραφο'), ('null', 'δεν είναι αντίγραφο'), ('2', 'νεότερη έκδοση')]) {
        expect(
          () => parseBackup(_backup('[]', '[]', version: version)),
          throwsA(isA<BackupError>().having((x) => x.message, 'message', contains(part))),
          reason: version,
        );
      }
      expect(parseBackup(_backup('[]', '[]', version: '0')).skipped, 0);
      expect(parseBackup(_backup('[]', '[]', version: '1.0')).skipped, 0);
      expect(parseBackup(_backup('"x"', '{"a":1}')).entries, isEmpty, reason: 'λίστα με λάθος τύπο = κενή');
    });

    test('το αντίγραφο που φτιάχνει η εφαρμογή περνά ολόκληρο', () {
      final b = parseBackup(buildBackup(foodLog: [_entry], myFoods: [_food], prefs: const {}, now: DateTime(2026, 11, 12)));
      expect((b.entries.length, b.myFoods.length, b.skipped), (1, 1, 0));
    });
  });

  group('Α1: ρυθμίσεις από αντίγραφο', () {
    final mine = <String, dynamic>{
      'cards': {'sleep': true},
      'kitchen': {'hob': 'Γκάζι'},
      'themeMode': 'light',
      'backfillFrom': '2025-11-01',
      'goals': {'k': 2100, 'since': '2026-11-16'},
      'zone': {'up': true, 'down': false},
      'me': {'h': 180, 'wds': [1, 3, 5], 'wad': 5, 'wd': 5},
      'waist': [
        {'d': '2026-11-10', 'v': [95.0, 95.5]},
      ],
    };
    final backup = <String, dynamic>{
      'cards': {'sleep': false},
      'kitchen': {'hob': 'Κεραμικά'},
      'themeMode': 'dark',
      'goals': {'k': 2250, 'since': '2026-10-01'},
      'zone': {'lo': 100, 'hi': 125, 'up': true, 'down': true},
      'me': {'by': 1985, 'bm': 12, 'sex': 'm', 'h': 174, 'wds': [2], 'wad': 2, 'wd': 2},
      'waist': [
        {'d': '2026-11-03', 'v': [96.0, 96.5]},
        {'d': '2026-11-10', 'v': [90.0, 90.0]},
      ],
    };

    test('στόχοι, ζώνη και στοιχεία του κινητού μένουν· κουζίνα, κάρτες και εμφάνιση από το αντίγραφο', () {
      final m = mergePrefsForRestore(mine, backup);
      expect(m['cards'], backup['cards']);
      expect(m['kitchen'], backup['kitchen']);
      expect(m['themeMode'], 'dark');
      // Πριν, τα τρία παρακάτω γίνονταν του αντιγράφου: παλιός στόχος θερμίδων, παλιά ζώνη, παλιά στοιχεία.
      expect(m['goals'], mine['goals']);
      expect(m['zone'], mine['zone']);
      expect(m['me'], {'by': 1985, 'bm': 12, 'sex': 'm', 'h': 180, 'wds': [1, 3, 5], 'wad': 5, 'wd': 5},
          reason: 'του κινητού· ό,τι λείπει (γέννηση, φύλο) από το αντίγραφο');
      expect((m['backfillFrom'], m['layout']), ('2025-11-01', todayLayout));
      expect((m['waist'] as List).map((x) => ((x as Map)['d'], (x['v'] as List).first)), [('2026-11-03', 96.0), ('2026-11-10', 95.0)],
          reason: 'μέση: του κινητού, συν τις μέρες που λείπουν');
    });

    test('κινητό χωρίς στόχους, ζώνη και στοιχεία: μπαίνουν από το αντίγραφο', () {
      final m = mergePrefsForRestore({'cards': <String, bool>{}, 'kitchen': null, 'themeMode': 'auto'}, backup);
      expect(m['goals'], backup['goals']);
      expect(m['zone'], backup['zone']);
      expect(m['me'], backup['me']);
    });

    test('αντίγραφο χωρίς στοιχεία, ή με χαλασμένα: τα δικά σου όπως είναι', () {
      expect(mergePrefsForRestore(mine, {'themeMode': 'dark'})['me'], mine['me']);
      expect(mergePrefsForRestore(mine, {'me': 'χαλασμένο'})['me'], mine['me']);
      final p = Prefs.fromJson(mergePrefsForRestore(mine, {'me': 'χαλασμένο', 'goals': 7, 'zone': <Object>[]}));
      expect(p.goals, mine['goals']);
      expect(p.zone, mine['zone']);
      expect(p.me, mine['me']);
    });
  });

  group('Α6/Α7: ανεκτική ανάγνωση ρυθμίσεων από αντίγραφο', () {
    test('κουζίνα με λάθος τύπους: αγνοείται ό,τι δεν διαβάζεται, χωρίς σφάλμα', () {
      // Πριν: σφάλμα τύπου κάθε φορά που άνοιγαν «Τα στοιχεία μου» (εκεί διαβάζεται η κουζίνα).
      final k = Kitchen.fromJson({
        'seed': 2,
        'devices': 'oven',
        'hob': 5,
        'ovenFan': 'ναι',
        'steamerTiers': double.infinity,
        'airFryerLiters': '4',
        'scaleMaxKg': double.nan,
        'cookware': [
          {'id': 'c1', 'kind': 'pot'},
          {'kind': 'tray'},
          {'id': 7, 'kind': 'pot'},
          'τηγάνι',
          {'id': 'c2', 'kind': 'tray', 'size': 3, 'brand': false},
        ],
      });
      expect(k.devices, isEmpty);
      expect((k.hob, k.ovenFan, k.steamerTiers, k.airFryerLiters, k.scaleMaxKg), (null, null, null, null, null));
      expect(k.cookware.map((c) => (c.id, c.size, c.brand)), [('c1', null, null), ('c2', null, null)]);
      expect(Kitchen.fromJson({'seed': 2, 'devices': 7, 'cookware': 'όχι λίστα'}).cookware, isEmpty);
      // Η σωστή κουζίνα διαβάζεται όπως πριν.
      final ok = Kitchen.fromJson({'seed': 2, 'devices': ['oven', 'hob'], 'hob': 'Γκάζι', 'ovenFan': false, 'steamerTiers': 2, 'airFryerLiters': 4.2, 'cookware': <Object>[]});
      expect(ok.devices, {'oven', 'hob'});
      expect((ok.hob, ok.ovenFan, ok.steamerTiers, ok.airFryerLiters), ('Γκάζι', false, 2, 4.2));
    });

    test('«Τα στοιχεία μου» με 1e999: κενά πεδία, όχι σφάλμα σε κάθε οθόνη', () {
      final p = Profile.fromJson(jsonDecode('{"by":1e999,"bm":1e999,"h":1e999,"wd":1e999,"wad":1e999,"wds":[1e999,3],"sex":"m"}'));
      expect((p.birthYear, p.birthMonth, p.heightCm, p.sex), (null, null, null, 'm'));
      expect(p.weighDays, {3});
      expect(p.waistDay, DateTime.friday);
      final ok = Profile.fromJson({'by': 1985, 'bm': 12, 'sex': 'm', 'h': 180, 'wds': [1, 3, 5], 'wad': 5});
      expect((ok.birthYear, ok.heightCm, ok.waistDay), (1985, 180.0, 5));
      expect(ok.weighDays, {1, 3, 5});
    });
  });

  group('γραμμές της βάσης που δεν διαβάζονται', () {
    const channel = MethodChannel('ygeia/food');
    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    test('παραλείπονται, μετριούνται, και οι υπόλοιπες φαίνονται κανονικά', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => switch (call.method) {
            'myFoods' => jsonEncode({
                'ok': true,
                'foods': [_food, 'σκουπίδι', {'name': 'χωρίς id'}],
              }),
            'logRange' => jsonEncode({
                'ok': true,
                'entries': [{..._entry, 'day': '2026-11-01'}, {'id': 'E2'}, 42],
              }),
            _ => jsonEncode({'ok': true}),
          });
      final s = FoodStore();
      addTearDown(s.dispose);
      await s.start();
      expect(s.loaded, isTrue);
      expect(s.mine.map((f) => f.id), ['M1']);
      expect(s.entriesFor(DateTime(2026, 11, 1)).map((x) => x.id), ['E1']);
      expect(s.skippedRows, 4, reason: '2 προϊόντα και 2 καταχωρίσεις: φαίνονται στην «Αναφορά για έλεγχο» (food-rows)');
    });
  });
}
