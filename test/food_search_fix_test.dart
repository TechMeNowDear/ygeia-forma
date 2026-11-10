// Διορθώσεις διατροφής μετά τον έλεγχο 9/11 (αναφορές 05 και V-C): αναζήτηση, νέα τρόφιμα, ετικέτα (αλάτι/νάτριο,
// ανά 100 ml), Open Food Facts, «Όπως χθες», μέρα μετά τα μεσάνυχτα, πηγές και άδειες.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_search.dart';
import 'package:ygeia_forma/food/food_sources.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/food/off.dart';
import 'package:ygeia_forma/food/replaced_foods.dart';
import 'package:ygeia_forma/food/weigh_hints.dart';
import 'package:ygeia_forma/format.dart' show dayOf;
import 'package:ygeia_forma/history.dart' show dateKey;
import 'package:ygeia_forma/pages/food_add.dart';
import 'package:ygeia_forma/pages/nutrition.dart';
import 'package:ygeia_forma/theme.dart';

import 'sample_food.dart';

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 2400), double textScale = 1.0}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(body: w),
  ));
  await t.pumpAndSettle();
}

Food _food(String id) => basicFoods().firstWhere((f) => f.id == id);

LogEntry _entry(String id, DateTime day, Meal meal, Food food, double grams) => LogEntry(
      id: id,
      day: dateKey(day),
      meal: meal,
      food: food,
      grams: grams,
      time: DateTime(day.year, day.month, day.day, 20),
    );

void main() {
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
  });

  final store = FoodStore.preloaded(foods: basicFoods(), now: DateTime(2026, 11, 9, 13));
  String? first(String q) {
    final r = store.find(q).foods;
    return r.isEmpty ? null : r.first.name;
  }

  group('Αναζήτηση: ίδια με τη μεταφορά σε Python (tools/food/search_port.py)', () {
    test('227 αναζητήσεις: ίδια 3 πρώτα, ίδιο πλήθος, ίδιες λέξεις που αγνοήθηκαν/διορθώθηκαν', () {
      final j = jsonDecode(File('test/fixtures/food_search_expected.json').readAsStringSync()) as Map<String, dynamic>;
      final qs = (j['queries'] as List).cast<Map<String, dynamic>>();
      expect(qs.length, greaterThanOrEqualTo(150));
      for (final e in qs) {
        final q = e['q'] as String;
        final r = store.find(q);
        expect([for (final f in r.foods.take(3)) f.id], (e['top'] as List).cast<String>(), reason: q);
        expect(r.foods.length, e['count'], reason: q);
        expect(r.ignored, (e['ignored'] as List).cast<String>(), reason: q);
        expect(r.corrected, Map<String, String>.from(e['corrected'] as Map), reason: q);
        expect(r.droppedFood, e['droppedFood'], reason: q);
      }
    });
  });

  group('Ν1: παστές/αλατισμένες παραλλαγές κάτω από το απλό τρόφιμο', () {
    test('«μπακαλιάρος βραστός» → φρέσκος μπακαλιάρος (αλάτι < 1 g/100 g), όχι ο παστός', () {
      for (final q in ['μπακαλιάρος βραστός', 'μπακαλιαρος βραστος', 'bakaliaros vrastos']) {
        final f = store.search(q).first;
        expect(f.name, 'Μπακαλιάρος (στον ατμό)', reason: q);
        expect(f.n.amount(Nk.salt), lessThan(1), reason: q);
      }
      expect(_food('C26024').aliases, isNot(contains('μπακαλιάρος βραστός')));
    });
    test('Ο παστός μόνο όταν τον ζητάς', () {
      expect(first('μπακαλιάρος'), 'Μπακαλιάρος (ωμός)');
      expect(store.search('μπακαλιάρος').take(3).any((f) => f.name.contains('παστός')), isFalse);
      expect(first('μπακαλιάρος παστός'), startsWith('Μπακαλιάρος παστός'));
      expect(first('παστός μπακαλιάρος'), startsWith('Μπακαλιάρος παστός'));
    });
    test('Ίδιος κανόνας: καπνιστό, αλατισμένο, μαρινάτο, αποξηραμένο φρούτο', () {
      expect(first('σολομός'), 'Σολομός υδατοκαλλιέργειας (ωμός)');
      expect(first('σολομός καπνιστός'), 'Σολομός καπνιστός');
      expect(first('φιστίκια'), 'Φιστίκια αράπικα (ανάλατα)');
      expect(first('φιστίκια αλατισμένα'), 'Φιστίκια αράπικα (καβουρδισμένα, αλατισμένα)');
      expect(first('γαύρος'), 'Γαύρος (ωμός)');
      expect(first('σύκο'), 'Σύκο (φρέσκο)');
      expect(first('σύκο ξερό'), 'Σύκο ξερό');
      expect(first('ξερά σύκα'), 'Σύκο ξερό');
    });
    test('«μερλούσα βραστή» βρίσκει τη μαγειρεμένη μερλούσα', () {
      expect(first('μερλούσα βραστή'), 'Μερλούσα (μαγειρεμένη στην κατσαρόλα)');
    });
  });

  group('Υ2: σωστό πρώτο αποτέλεσμα', () {
    test('«λάδι ελιάς» → ελαιόλαδο (πριν: μόνο οι ελιές)', () {
      for (final q in ['λάδι ελιάς', 'λαδι ελιας', 'ladi elias', 'λάδι']) {
        expect(first(q), 'Ελαιόλαδο εξαιρετικά παρθένο', reason: q);
      }
    });
    test('«σύκο» → φρέσκο (68 kcal), όχι ξερό (261)', () {
      for (final q in ['σύκο', 'siko', 'σύκα']) {
        expect(first(q), 'Σύκο (φρέσκο)', reason: q);
      }
    });
    test('«μπιζέλια» → αρακάς, όχι φάβα', () {
      expect(first('μπιζέλια'), startsWith('Αρακάς'));
    });
    test('«τσίπουρο» → το ποτό· ποτέ η τσιπούρα (ίδια ρίζα, άλλο νόημα)', () {
      for (final q in ['τσίπουρο', 'tsipouro']) {
        final r = store.search(q);
        expect(r.first.name, 'Απόσταγμα φρούτων (eau-de-vie)', reason: q);
        expect(r.any((f) => f.name.startsWith('Τσιπούρα')), isFalse, reason: q);
      }
      expect(first('τσιπούρα'), startsWith('Τσιπούρα'));
      expect(store.search('τσιπούρα').any((f) => f.id == 'C1001'), isFalse);
    });
    test('«κατσίκι» → κατσικάκι· «πουρές» → πουρές πατάτας', () {
      expect(first('κατσίκι'), 'Κατσικάκι (ωμό)');
      expect(first('πουρές'), startsWith('Πουρές πατάτας'));
      expect(first('πουρές ντομάτας'), startsWith('Πουρές ντομάτας'));
    });
    test('Σε ισοπαλία η σειρά της λίστας (ίδια σε κάθε κινητό): κιμάς 5% → 10% → 15% → 20%', () {
      final raw = [for (final f in store.search('κιμάς')) if (f.name.endsWith('(ωμός)')) f.name];
      expect(raw, [
        'Κιμάς μοσχαρίσιος 5% λιπαρά (ωμός)',
        'Κιμάς μοσχαρίσιος 10% λιπαρά (ωμός)',
        'Κιμάς μοσχαρίσιος 15% λιπαρά (ωμός)',
        'Κιμάς μοσχαρίσιος 20% λιπαρά (ωμός)',
      ]);
    });
    test('«γιαούρτι» → πρώτο το στραγγιστό 2%, μετά το 0%', () {
      final r = store.search('γιαούρτι');
      expect(r[0].name, 'Γιαούρτι στραγγιστό χαμηλά λιπαρά (περίπου 2%)');
      expect(r[1].name, 'Γιαούρτι στραγγιστό 0%');
      expect(first('γιαούρτι 0%'), 'Γιαούρτι στραγγιστό 0%');
    });
  });

  group('Υ3: πτώσεις, τρόπος μαγειρέματος, περιγραφικές λέξεις, κατηγορίες, λάθη', () {
    test('Γενική πτώση', () {
      expect(first('στήθος κοτόπουλου'), 'Κοτόπουλο στήθος χωρίς πέτσα (ωμό)');
      expect(first('μπούτι κοτόπουλου'), startsWith('Κοτόπουλο μπούτι'));
      expect(first('φιλέτο σολομού'), 'Σολομός υδατοκαλλιέργειας (ωμός)');
      expect(first('χυμός πορτοκαλιού'), 'Χυμός πορτοκάλι (φρέσκος)');
      expect(first('ψωμί ολικής αλέσεως'), 'Ψωμί ολικής άλεσης');
    });
    test('Τρόπος μαγειρέματος: βρίσκει τη μαγειρεμένη μορφή και λέει ποια λέξη αγνοήθηκε', () {
      for (final q in ['χταπόδι ψητό', 'χταπόδι βραστό', 'χταπόδι σχάρας']) {
        final r = store.find(q);
        expect(r.foods.first.name, 'Χταπόδι (μαγειρεμένο)', reason: q);
        expect(r.ignored, hasLength(1), reason: q);
      }
      expect(store.find('χταπόδι ψητό').ignored, ['ψητό']);
      expect(first('τσιπούρα σχάρας'), 'Τσιπούρα (ψητή στον φούρνο)');
      expect(first('πατάτες ψητές'), 'Πατάτα φούρνου (χωρίς λάδι, ξεφλουδισμένη)');
      expect(first('ρυζι ασπρο'), 'Ρύζι λευκό (ωμό)');
    });
    test('Περιγραφική λέξη δεν μηδενίζει την αναζήτηση', () {
      final r = store.find('μέλι θυμαρίσιο');
      expect(r.foods.first.name, 'Μέλι');
      expect(r.ignored, ['θυμαρίσιο']);
      expect(first('τυρί cottage'), startsWith('Cottage cheese'));
      expect(store.find('ελληνικός καφές').ignored, ['ελληνικός']);
      expect(first('τυρί τριμμένο'), anyOf('Πεκορίνο', 'Παρμεζάνα'));
    });
    test('Κατηγορίες: «ψάρι», «κρέας», «φρούτα», «λαχανικά»', () {
      final fish = store.search('ψάρι');
      expect(fish.length, greaterThanOrEqualTo(20));
      expect(fish.take(20).every((f) => f.cat == 'Ψάρια'), isTrue);
      expect(store.search('ψάρια').length, fish.length);
      expect(store.search('κρέας').take(20).every((f) => f.cat == 'Κρέας' || f.cat == 'Πουλερικά'), isTrue);
      expect(store.search('φρούτα').take(20).every((f) => f.cat == 'Φρούτα'), isTrue);
      expect(store.search('λαχανικά').take(20).every((f) => f.cat == 'Λαχανικά'), isTrue,
          reason: 'όχι η «πίτα… με λαχανικά» πρώτη');
      expect(store.search('ψάρι ψητό').every((f) => f.cat == 'Ψάρια'), isTrue);
    });
    test('Ένα λάθος γράμμα: «κοτόπολο», «γιαουτρι»', () {
      final r = store.find('κοτόπολο');
      expect(r.foods.first.name, startsWith('Κοτόπουλο'));
      expect(r.corrected, {'κοτόπολο': 'κοτόπουλο'});
      expect(store.find('γιαουτρι').foods.first.name, startsWith('Γιαούρτι'));
      // Όχι διόρθωση σε άσχετη λέξη: «κασέρι» δεν γίνεται «ξεροί».
      expect(store.find('κασέρι').foods, isEmpty);
    });
    test('Χ1: greeklish με au/eu/ay', () {
      expect(store.search('leuko').take(5).any((f) => plain(f.name).contains('λευκ')), isTrue);
      expect(store.search('leyko').take(5).any((f) => plain(f.name).contains('λευκ')), isTrue);
      expect(first('gayros'), startsWith('Γαύρος'));
      expect(first('zahari leuki'), 'Ζάχαρη λευκή');
    });
    test('Συστατικό μετά από «με» μετρά λίγο: «βούτυρο» → βούτυρο, όχι πουρές', () {
      expect(store.search('βούτυρο').take(2).map((f) => f.name), ['Βούτυρο ανάλατο', 'Φυστικοβούτυρο']);
    });
  });

  group('Νέα τρόφιμα (μόνο ακριβείς αντιστοιχίες CIQUAL 2025 / USDA FDC)', () {
    test('374 τρόφιμα· τα νέα υπάρχουν με την πηγή τους', () {
      expect(basicFoods().length, 374);
      const added = {
        'C26025': 'CIQUAL 2025', 'C26120': 'CIQUAL 2025', 'C26040': 'CIQUAL 2025', 'C6255': 'CIQUAL 2025',
        'C6257': 'CIQUAL 2025', 'C21800': 'CIQUAL 2025', 'C21801': 'CIQUAL 2025', 'C22505': 'CIQUAL 2025',
        'U169226': 'USDA SR Legacy', 'U169227': 'USDA SR Legacy', 'C20301': 'CIQUAL 2025', 'C4018': 'CIQUAL 2025',
        'C7200': 'CIQUAL 2025', 'C7603': 'CIQUAL 2025', 'C25621': 'CIQUAL 2025', 'C5215': 'CIQUAL 2025',
        'C1001': 'CIQUAL 2025', 'C25506': 'CIQUAL 2025', 'C25428': 'CIQUAL 2025', 'C25163': 'CIQUAL 2025',
        'C25547': 'CIQUAL 2025', 'U173180': 'USDA SR Legacy', 'C25586': 'CIQUAL 2025', 'C25585': 'CIQUAL 2025',
        'C15011': 'CIQUAL 2025',
      };
      for (final e in added.entries) {
        expect(_food(e.key).source, e.value, reason: e.key);
      }
      // Τιμές όπως στο επίσημο xlsx της CIQUAL 2025 (δείγμα).
      expect(_food('C26025').n.amount(Nk.kcal), 106);
      expect(_food('C26025').n.amount(Nk.sodium), 65);
      expect(_food('C5215').n.amount(Nk.kcal), 55.3);
    });
    test('Καθημερινά που έλειπαν', () {
      // Τα χόρτα τρώγονται βραστά: μόνο βραστά στο «χόρτα».
      expect(store.search('χόρτα').every((f) => f.name.contains('βραστ')), isTrue);
      expect(first('χόρτα βραστά'), contains('βραστ'));
      expect(first('αυγό τηγανητό'), 'Αυγό τηγανητό (μάτι, χωρίς λάδι)');
      expect(first('σαρδέλες κονσέρβα'), 'Σαρδέλα σε ελαιόλαδο (κονσέρβα, στραγγισμένη)');
      expect(first('κρασί λευκό'), 'Κρασί λευκό ξηρό');
      expect(first('whey'), startsWith('Πρωτεΐνη ορού γάλακτος'));
      expect(first('πρωτεΐνη'), startsWith('Πρωτεΐνη ορού γάλακτος'));
      expect(first('σουβλάκι'), 'Σουβλάκι με ανάμεικτα κρέατα');
      expect(first('γύρος πίτα'), 'Πίτα με γύρο/κεμπάπ και ωμά λαχανικά (χωρίς πατάτες)');
      expect(first('χούμους'), startsWith('Χούμους'));
      expect(first('κρουασάν'), startsWith('Κρουασάν'));
      expect(first('τοστ'), startsWith('Τοστ ζαμπόν'));
      expect(first('ψωμί τοστ'), startsWith('Ψωμί του τοστ'));
      expect(first('κεφτέδες'), startsWith('Κεφτέδες'));
    });
    test('Χωρίς ακριβή πηγή δεν «βαφτίζεται» τίποτα: κασέρι, παξιμάδι, χαλβάς', () {
      for (final q in ['κασέρι', 'παξιμάδι', 'χαλβάς']) {
        expect(store.search(q), isEmpty, reason: q);
      }
    });
    test('Χ2: πρωτεΐνη CIQUAL N × 6,25 (όπως οι ετικέτες της ΕΕ)', () {
      expect(_food('C9810').n.amount(Nk.protein), 13.1);
      expect(_food('C7000').n.amount(Nk.protein), 8.97);
    });
    test('Χ3: η φέτα χωρίς «ΠΟΠ» (η πηγή δεν το λέει)', () {
      expect(_food('C12066').name, 'Φέτα (πρόβειο και κατσικίσιο)');
    });
    test('Οδηγίες ζυγίσματος και επιλογής: όλα τα id υπάρχουν', () {
      final ids = {for (final f in basicFoods()) f.id};
      for (final id in [...weighHints.keys, ...pickHints.keys]) {
        expect(ids, contains(id), reason: id);
      }
      expect(weighHints['U172521'], contains('κόκαλα'));
      expect(weighHints['C26080'], contains('αν δεν την τρως'));
    });
  });

  group('Ετικέτα: αλάτι ή νάτριο (Μ1), ανά 100 ml (Μ2)', () {
    test('Νάτριο → αλάτι × 2,5', () {
      expect(saltFromInput(400, SaltInput.sodiumMg), closeTo(1.0, 1e-12));
      expect(saltFromInput(0.4, SaltInput.sodiumG), closeTo(1.0, 1e-12));
      expect(saltFromInput(1.2, SaltInput.salt), 1.2);
      expect(impossibleValues({Nk.salt: 400})[Nk.salt], contains('Νάτριο mg'));
    });

    Future<Food?> fill(WidgetTester t, {required String salt, String? mode, bool ml = false}) async {
      Food? saved;
      await _pump(
        t,
        Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              saved = await Navigator.of(ctx).push<Food>(
                MaterialPageRoute(builder: (_) => FoodFormScreen(draft: FoodDraft(name: 'Κράκερ'))),
              );
            },
            child: const Text('άνοιξε'),
          ),
        ),
      );
      await t.tap(find.text('άνοιξε'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('field-kcal')), '450');
      await t.enterText(find.byKey(const ValueKey('field-protein')), '8');
      await t.enterText(find.byKey(const ValueKey('field-carbs')), '60');
      await t.enterText(find.byKey(const ValueKey('field-fat')), '18');
      if (ml) await t.tap(find.text('ανά 100 ml'));
      if (mode != null) await t.tap(find.text(mode));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('field-salt')), salt);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Αποθήκευση'));
      await t.tap(find.text('Αποθήκευση'));
      await t.pumpAndSettle();
      return saved;
    }

    testWidgets('«Νάτριο mg» 400 → αλάτι 1 g, και κρατά το νάτριο', (t) async {
      final f = await fill(t, salt: '400', mode: 'Νάτριο mg');
      expect(f, isNotNull);
      expect(f!.n.amount(Nk.salt), closeTo(1.0, 1e-9));
      expect(f.n[Nk.sodium]!.value, 400);
      expect(f.perMl, isFalse);
    });
    testWidgets('«Αλάτι g» μένει όπως γράφτηκε, χωρίς νάτριο', (t) async {
      final f = await fill(t, salt: '1,2');
      expect(f!.n.amount(Nk.salt), 1.2);
      expect(f.n.has(Nk.sodium), isFalse);
    });
    testWidgets('«ανά 100 ml»: το προϊόν μένει ανά 100 ml', (t) async {
      final f = await fill(t, salt: '0,1', ml: true);
      expect(f!.perMl, isTrue);
      expect(f.unit, 'ml');
    });
    testWidgets('Αλάτι 400 g: δεν αποθηκεύεται και λέει «Νάτριο mg»', (t) async {
      final f = await fill(t, salt: '400');
      expect(f, isNull);
      expect(find.textContaining('Νάτριο mg».'), findsOneWidget);
    });
  });

  group('Open Food Facts', () {
    test('Μ2: «1 λίτρο», «1 λτ», «1 litre» είναι υγρά', () {
      for (final q in ['1 λίτρο', '1 Λίτρο', '1 λτ', '1 litre', '1 liter', '1lt', '0,5 l', '330 ml']) {
        expect(isLiquidQuantity(q), isTrue, reason: q);
      }
      for (final q in ['500 g', '2 lb', '1 kg', '6 τεμάχια']) {
        expect(isLiquidQuantity(q), isFalse, reason: q);
      }
    });
    test('Χ5: UPC-A 12 ψηφίων = EAN-13 με «0»', () async {
      expect(normalizeBarcode('012345678905'), '0012345678905');
      expect(normalizeBarcode('00012345678905'), '0012345678905');
      expect(normalizeBarcode('5201234567890'), '5201234567890');
      final s = FoodStore.preloaded(foods: basicFoods());
      final mine = foodFromDraft(FoodDraft(name: 'Δημητριακά', barcode: '0012345678905', values: {Nk.kcal: 380}), 'M1');
      await s.saveMyFood(mine);
      expect(s.byBarcode('012345678905')?.id, 'M1');
    });
    test('Χ5: «<» του Open Food Facts μένει «<»', () {
      final d = draftFromOff('1', {
        'nutriments': {'energy-kcal_100g': 40, 'salt_100g': 0.01, 'salt_modifier': '<', 'fat_100g': 0.5, 'fat_modifier': '<'},
      });
      expect(d.lessThan, {Nk.salt, Nk.fat});
      final f = foodFromDraft(d, 'M2');
      expect(f.n[Nk.salt]!.lessThan, isTrue);
      expect(nValueText(f.n[Nk.salt], digits: 2), '<0,01');
    });
    test('Χ5: η ερυθριτόλη μετρά 0 kcal/g (Κανονισμός 1169/2011)', () {
      final v = {Nk.kcal: 370.0, Nk.protein: 5.0, Nk.carbs: 60.0, Nk.fat: 30.0};
      expect(energyMismatch(v, polyols: 40, erythritol: 40), isNull);
      expect(energyMismatch(v, polyols: 40), isNotNull);
    });
    test('Χ5: η διόρθωση μπίρας κρατά το αλκοόλ (χωρίς ψεύτικο «οι θερμίδες δεν ταιριάζουν»)', () {
      final d = draftFromOff('1', {
        'quantity': '330 ml',
        'nutriments': {'energy-kcal_100g': 43, 'proteins_100g': 0.5, 'carbohydrates_100g': 3.6, 'fat_100g': 0, 'alcohol_100g': 5},
      });
      final beer = foodFromDraft(d, 'M3');
      final again = draftFromFood(beer);
      expect(again.alcohol, closeTo(5 * 0.789, 1e-9));
      expect(energyMismatch(again.values, alcohol: again.alcohol ?? 0), isNull);
      expect(again.perMl, isTrue);
    });
    test('Νάτριο από το Open Food Facts: κρατιέται σε mg', () {
      final d = draftFromOff('1', {'nutriments': {'energy-kcal_100g': 100, 'sodium_100g': 0.4}});
      expect(d.sodiumMg, 400);
      expect(foodFromDraft(d, 'M4').n[Nk.sodium]!.value, 400);
    });
  });

  group('Ποσότητα', () {
    testWidgets('Μ2: υγρό ανά 100 ml → ποσότητα σε ml', (t) async {
      final oil = foodFromDraft(
        FoodDraft(name: 'Ελαιόλαδο (μάρκα)', values: {Nk.kcal: 824, Nk.protein: 0, Nk.carbs: 0, Nk.fat: 91.6}, perMl: true),
        'M5',
      );
      await _pump(t, QuantitySheet(food: store, item: oil, initialGrams: 15, meal: Meal.lunch));
      expect(find.text('ml'), findsWidgets);
      expect(find.byKey(const ValueKey('ml-note')), findsOneWidget);
      expect(find.textContaining('10 g λάδι'), findsOneWidget);
      expect(find.text('330 ml'), findsOneWidget);
    });
    testWidgets('Μ4: υπενθύμιση λαδιού και χωρίς ωμή/μαγειρεμένη μορφή (μανιτάρια), όχι στα τηγανητά', (t) async {
      await _pump(t, QuantitySheet(key: const ValueKey('C20010'), food: store, item: _food('C20010'), initialGrams: 200, meal: Meal.lunch));
      expect(find.byKey(const ValueKey('oil-note')), findsOneWidget);
      await _pump(t, QuantitySheet(key: const ValueKey('C10084'), food: store, item: _food('C10084'), initialGrams: 200, meal: Meal.lunch));
      expect(find.byKey(const ValueKey('oil-note')), findsNothing);
      await _pump(t, QuantitySheet(key: const ValueKey('C4002'), food: store, item: _food('C4002'), initialGrams: 200, meal: Meal.lunch));
      expect(find.byKey(const ValueKey('oil-note')), findsOneWidget, reason: 'πατάτα φούρνου «χωρίς λάδι»');
    });
    testWidgets('V-C-13: ο κιμάς λέει να διαλέξεις το % λιπαρών', (t) async {
      await _pump(t, QuantitySheet(food: store, item: _food('C6254'), initialGrams: 200, meal: Meal.lunch));
      expect(find.textContaining('διάλεξε το %'), findsOneWidget);
    });
    testWidgets('V-D-23: μεγάλα γράμματα (2×) σε στενό κινητό χωρίς ξεχείλισμα', (t) async {
      await _pump(t, QuantitySheet(food: store, item: _food('C20360'), initialGrams: 1234, meal: Meal.lunch),
          size: const Size(360, 2400), textScale: 2.0);
      expect(t.takeException(), isNull);
      // Σχέδια 9/11 (9α): με μεγάλα γράμματα τα θρεπτικά πάνε σε 2×2 και η λέξη γράφεται ολόκληρη.
      expect(find.text('Υδατάνθρακες'), findsOneWidget);
    });
  });

  group('Μ3: «Όπως χθες» χωρίς σβησμένα προϊόντα', () {
    test('Το σβησμένο (λάθος) προϊόν δεν ξαναγράφεται και δεν μετρά στο κουμπί', () async {
      final today = DateTime(2026, 11, 9);
      final yesterday = DateTime(2026, 11, 8);
      final bad = foodFromDraft(FoodDraft(name: 'Μπάρα (λάθος)', values: {Nk.kcal: 900}), 'Mbad');
      final s = FoodStore.preloaded(
        foods: basicFoods(),
        mine: [bad],
        entries: [_entry('a', yesterday, Meal.dinner, bad, 50), _entry('b', yesterday, Meal.dinner, _food('C31008'), 15)],
        now: DateTime(2026, 11, 9, 20),
      );
      expect(s.copyable(yesterday, Meal.dinner).length, 2);
      await s.deleteMyFood(bad);
      expect(s.copyable(yesterday, Meal.dinner).map((e) => e.food.id), ['C31008']);
      expect(s.notCopyable(yesterday, Meal.dinner), 1);
      final added = await s.copyMeal(yesterday, Meal.dinner, today);
      expect(added.map((e) => e.food.id), ['C31008']);
    });
  });

  group('Σύνολα', () {
    test('Χ8: αλκοόλ στα σύνολα· Χ4: οι στρογγυλεμένες θερμίδες αθροίζουν', () {
      final day = DateTime(2026, 11, 9);
      final es = [
        _entry('w', day, Meal.dinner, _food('C5214'), 150),
        _entry('x', day, Meal.dinner, _food('C31008'), 7),
        _entry('y', day, Meal.dinner, _food('C20360'), 133),
      ];
      final t = Totals(es);
      expect(t.alcohol, closeTo(_food('C5214').n.amount(Nk.alcohol) * 1.5, 1e-9));
      expect(t.alcohol, greaterThan(10));
      expect(t.shownKcal, es.fold<int>(0, (a, e) => a + e.total(Nk.kcal).round()));
    });
    testWidgets('Χ8: «Άλλα x% θερμίδων» (ίνες, αλκοόλ), ώστε τα ποσοστά να φτάνουν το 100%', (t) async {
      final day = DateTime(2026, 11, 9);
      await _pump(t, MacroBreakdown(totals: Totals([_entry('w', day, Meal.dinner, _food('C5214'), 300)])));
      expect(find.byKey(const ValueKey('macro-other')), findsOneWidget);
      expect(find.textContaining('αλκοόλ'), findsOneWidget);
    });
  });

  group('Μέρα και γεύμα αργά το βράδυ (Χ11, RT-14)', () {
    test('Δείπνο ως τις 00:30', () {
      expect(mealForTime(DateTime(2026, 1, 1, 23, 30)), Meal.dinner);
      expect(mealForTime(DateTime(2026, 1, 2, 0, 20)), Meal.dinner);
      expect(mealForTime(DateTime(2026, 1, 2, 0, 40)), Meal.snack);
      expect(mealForTime(DateTime(2026, 1, 1, 21)), Meal.dinner);
      expect(mealForTime(DateTime(2026, 1, 1, 17, 30)), Meal.snack);
    });

    Future<FoodStore> addHoney(WidgetTester t, {required DateTime opened, required DateTime Function() clock, String? answer}) async {
      final s = FoodStore.preloaded(foods: basicFoods(), now: opened);
      await _pump(t, AddFoodScreen(food: s, meal: Meal.dinner, day: dayOf(opened), clock: clock));
      await t.enterText(find.byType(TextField), 'μέλι');
      await t.pumpAndSettle();
      await t.tap(find.text('Μέλι').first);
      await t.pumpAndSettle();
      await t.tap(find.textContaining('Προσθήκη στο'));
      await t.pumpAndSettle();
      if (answer != null) {
        expect(find.text('Σε ποια μέρα;'), findsOneWidget);
        await t.tap(find.textContaining(answer));
        await t.pumpAndSettle();
      } else {
        expect(find.text('Σε ποια μέρα;'), findsNothing);
      }
      return s;
    }

    testWidgets('00:20: ρωτά· «Χθες» → στη χθεσινή μέρα', (t) async {
      final now = DateTime(2026, 11, 10, 0, 20);
      final s = await addHoney(t, opened: now, clock: () => now, answer: 'Χθες');
      expect(s.entriesFor(DateTime(2026, 11, 9)).single.food.id, 'C31008');
      expect(s.entriesFor(DateTime(2026, 11, 10)), isEmpty);
    });
    testWidgets('Άνοιξε 23:50, πρόσθεσε 00:10: ρωτά· «Σήμερα» → στη νέα μέρα', (t) async {
      var now = DateTime(2026, 11, 9, 23, 50);
      final s = FoodStore.preloaded(foods: basicFoods(), now: now);
      await _pump(t, AddFoodScreen(food: s, meal: Meal.dinner, day: DateTime(2026, 11, 9), clock: () => now));
      now = DateTime(2026, 11, 10, 0, 10);
      await t.enterText(find.byType(TextField), 'μέλι');
      await t.pumpAndSettle();
      await t.tap(find.text('Μέλι').first);
      await t.pumpAndSettle();
      await t.tap(find.textContaining('Προσθήκη στο'));
      await t.pumpAndSettle();
      expect(find.text('Σε ποια μέρα;'), findsOneWidget);
      await t.tap(find.text('Σήμερα'));
      await t.pumpAndSettle();
      expect(s.entriesFor(DateTime(2026, 11, 10)).single.food.id, 'C31008');
    });
    testWidgets('Μεσημέρι: καμία ερώτηση', (t) async {
      final now = DateTime(2026, 11, 9, 14);
      final s = await addHoney(t, opened: now, clock: () => now);
      expect(s.entriesFor(DateTime(2026, 11, 9)).single.food.id, 'C31008');
    });
  });

  group('Αναζήτηση: η οθόνη λέει τι αγνοήθηκε', () {
    testWidgets('«μέλι θυμαρίσιο» → Μέλι, με σημείωση', (t) async {
      final s = FoodStore.preloaded(foods: basicFoods(), now: DateTime(2026, 11, 9, 13));
      await _pump(t, AddFoodScreen(food: s, meal: Meal.lunch, day: DateTime(2026, 11, 9)));
      await t.enterText(find.byType(TextField), 'μέλι θυμαρίσιο');
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-note')), findsOneWidget);
      expect(find.byKey(const ValueKey('search-warning')), findsNothing);
      expect(find.textContaining('Αποτελέσματα για «μέλι»'), findsOneWidget);
      expect(find.text('Μέλι'), findsOneWidget);
    });
  });

  group('Ανεξάρτητος έλεγχος του fix-food: η αναζήτηση δεν αλλάζει σιωπηλά τρόφιμο', () {
    test('3.1: ποτέ χωρίς την κύρια (πρώτη) λέξη', () {
      expect(first('σοκολάτα χωρίς ζάχαρη'), startsWith('Σοκολάτα'));
      expect(first('χυμός χωρίς ζάχαρη'), startsWith('Χυμός'));
      expect(first('μαρμελάδα χωρίς ζάχαρη'), startsWith('Μαρμελάδα'));
      expect(first('ψωμί χωρίς αλάτι'), startsWith('Ψωμί'));
      expect(first('γιαούρτι με μέλι'), startsWith('Γιαούρτι'));
      expect(first('κόλα light'), startsWith('Αναψυκτικό κόλα'));
      expect(first('σουβλάκι κοτόπουλο'), 'Σουβλάκι κοτόπουλο (ψημένο)');
      expect(first('καλαμάκι χοιρινό'), startsWith('Σουβλάκι'));
      for (final q in ['σοκολάτα χωρίς ζάχαρη', 'ψωμί χωρίς αλάτι', 'γιαούρτι με μέλι', 'κόλα light']) {
        expect(strongSearchWarning(store.find(q)), isTrue, reason: q);
      }
    });
    test('3.2: «σε λάδι»/«με ζάχαρη» δεν «ταιριάζουν» με το «χωρίς λάδι/ζάχαρη» του ονόματος', () {
      final egg = store.find('αυγό τηγανητό σε λάδι');
      expect(egg.ignored, ['λάδι'], reason: 'βρέθηκε μόνο χωρίς τη λέξη, και η οθόνη το λέει');
      final coffee = store.find('καφές με ζάχαρη');
      expect(coffee.ignored, ['ζάχαρη']);
      // Το «λάδι» δεν φέρνει πια τα «χωρίς λάδι» (πατάτα φούρνου, σαρδέλα ψητή).
      expect(store.search('λάδι').any((f) => f.name.contains('χωρίς λάδι')), isFalse);
      // Με «χωρίς» στην αναζήτηση ταιριάζουν κανονικά.
      expect(first('πατάτες χωρίς λάδι'), 'Πατάτα φούρνου (χωρίς λάδι, ξεφλουδισμένη)');
      expect(first('ρύζι χωρίς αλάτι'), startsWith('Ρύζι λευκό (βρασμένο'));
    });
    test('Ένα λάθος γράμμα μόνο για λέξη που δεν υπάρχει: «καλαμάκι» δεν γίνεται «καλαμάρι»', () {
      final r = store.find('καλαμάκι');
      expect(r.corrected, isEmpty);
      expect(r.foods.any((f) => f.name.startsWith('Καλαμάρι')), isFalse);
    });
    test('Σ-Β: σκέτο «καλαμάκι» → πρώτο το ανάμεικτο (το καλαμάκι είναι συνήθως χοιρινό), μετά κοτόπουλο/μοσχάρι', () {
      final r = store.search('καλαμάκι');
      expect(r.first.name, 'Σουβλάκι με ανάμεικτα κρέατα');
      expect(r.skip(1).take(2).map((f) => f.id).toSet(), {'C25586', 'C25585'});
      expect(first('καλαμάκι κοτόπουλο'), 'Σουβλάκι κοτόπουλο (ψημένο)');
      expect(first('καλαμάκι μοσχαρίσιο'), 'Σουβλάκι μοσχαρίσιο (ψημένο)');
      // «καλαμάκι χοιρινό»: δεν υπάρχει ψημένο χοιρινό σουβλάκι στην πηγή → το ανάμεικτο, ΜΕ προειδοποίηση.
      final pork = store.find('καλαμάκι χοιρινό');
      expect(pork.foods.first.name, 'Σουβλάκι με ανάμεικτα κρέατα');
      expect(strongSearchWarning(pork), isTrue);
    });
    test('Σ-Α: η κόκκινη κάρτα μόνο για τρόφιμο ή λέξη που αλλάζει τη διατροφή', () {
      for (final q in ['μήλο πράσινο', 'πατάτες τηγανητές σπιτικές', 'ελληνικός καφές', 'γάλα χωρίς λακτόζη',
          'γιαούρτι χωρίς λακτόζη', 'μέλι θυμαρίσιο', 'χταπόδι ψητό']) {
        final r = store.find(q);
        expect(r.foods, isNotEmpty, reason: q);
        expect(strongSearchWarning(r), isFalse, reason: q);
      }
      for (final q in ['γάλα σόγιας', 'κόλα light', 'γιαούρτι με μέλι', 'σοκολάτα χωρίς ζάχαρη', 'μπύρα χωρίς αλκοόλ',
          'κοτόπουλο πανέ', 'μπάρα πρωτεΐνης', 'αυγό τηγανητό σε λάδι', 'κοτόπουλο με ρύζι', 'γάλα με κακάο']) {
        final r = store.find(q);
        expect(r.foods, isNotEmpty, reason: q);
        expect(strongSearchWarning(r), isTrue, reason: q);
      }
      expect(store.find('μήλο πράσινο').droppedFood, isFalse);
      expect(store.find('κοτόπουλο με ρύζι').droppedFood, isTrue);
    });
    test('«τόνος σε λάδι» → ο τόνος σε ελαιόλαδο', () {
      expect(first('τόνος σε λάδι'), startsWith('Τόνος λευκός (albacore) σε ελαιόλαδο'));
    });
    test('Λέξεις που αλλάζουν τη διατροφή', () {
      for (final w in ['σόγιας', 'light', 'αλκοόλ', 'πανέ', 'μπάρα', 'αλατισμένα', 'λάδι', 'ζάχαρη', 'χωρίς']) {
        expect(changesNutrition(w), isTrue, reason: w);
      }
      for (final w in ['θυμαρίσιο', 'ψητό', 'σχάρας']) {
        expect(changesNutrition(w), isFalse, reason: w);
      }
      expect(isCookingWord('ψητό'), isTrue);
    });
    testWidgets('«γάλα σόγιας» → έντονη προειδοποίηση «άλλο τρόφιμο», όχι γκρι σημείωση', (t) async {
      final s = FoodStore.preloaded(foods: basicFoods(), now: DateTime(2026, 11, 9, 13));
      await _pump(t, AddFoodScreen(food: s, meal: Meal.lunch, day: DateTime(2026, 11, 9)));
      await t.enterText(find.byType(TextField), 'γάλα σόγιας');
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-warning')), findsOneWidget);
      expect(find.textContaining('άλλο τρόφιμο'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'χταπόδι ψητό');
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-warning')), findsNothing);
      expect(find.byKey(const ValueKey('search-note')), findsOneWidget);
    });
  });

  group('Ανεξάρτητος έλεγχος του fix-food: δεδομένα, αλάτι, ml, μέρα', () {
    test('1.1: ηλιόσποροι από CIQUAL (N × 6,25), ίδια βάση με τους αλατισμένους', () {
      expect(_food('C15011').n.amount(Nk.protein), 25.1);
      expect(_food('C15045').n.amount(Nk.protein), 25.0);
      expect(basicFoods().any((f) => f.id == 'U170562'), isFalse);
      expect(replacedFoods['U170562'], 'C15011');
      expect(weighHints['C15011'], isNotNull);
    });
    test('1.2: η οθόνη πηγών λέει τον συντελεστή πρωτεΐνης της USDA', () {
      expect(usdaInfo.detail, contains('Jones'));
      expect(ciqualInfo.detail, contains('6,25'));
    });
    test('2.x: ονόματα που λένε ακριβώς τι είναι', () {
      expect(_food('U169226').name, 'Ραδίκια πικραλίδας (ωμά)');
      expect(_food('U169226').aliases, isNot(contains('χόρτα')));
      expect(_food('C21800').aliases, isNot(contains('γίδα')));
      expect(_food('C25506').aliases, contains('καλαμάκι'));
      expect(_food('U173180').name, contains('προτίμησε το barcode'));
    });
    test('4.2: «30 g (+125 ml γάλα)» στη μερίδα δεν κάνει υγρό τα δημητριακά', () {
      expect(draftFromOff('1', {'serving_size': '30 g (+125 ml γάλα)', 'nutriments': {}}).perMl, isFalse);
      expect(draftFromOff('1', {'quantity': '500 g', 'serving_size': '1 cup (240 ml)', 'nutriments': {}}).perMl, isFalse);
      expect(draftFromOff('1', {'serving_size': '250 ml', 'nutriments': {}}).perMl, isTrue);
      expect(draftFromOff('1', {'quantity': '1 l', 'nutriments': {}}).perMl, isTrue);
    });
    testWidgets('4.1: αλλαγή μονάδας μετατρέπει την τιμή που ήρθε (ίδιο αλάτι), όχι αυτή που έγραψες', (t) async {
      Food? saved;
      final draft = draftFromOff('5201234567890', {
        'product_name': 'Κράκερ',
        'nutriments': {'energy-kcal_100g': 450, 'proteins_100g': 8, 'carbohydrates_100g': 60, 'fat_100g': 18, 'sodium_100g': 0.4},
      });
      await _pump(
        t,
        Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              saved = await Navigator.of(ctx).push<Food>(MaterialPageRoute(builder: (_) => FoodFormScreen(draft: draft)));
            },
            child: const Text('άνοιξε'),
          ),
        ),
      );
      await t.tap(find.text('άνοιξε'));
      await t.pumpAndSettle();
      await t.tap(find.text('Νάτριο mg'));
      await t.pumpAndSettle();
      final field = t.widget<TextField>(find.byKey(const ValueKey('field-salt')));
      expect(field.controller!.text, '400');
      await t.ensureVisible(find.text('Αποθήκευση'));
      await t.tap(find.text('Αποθήκευση'));
      await t.pumpAndSettle();
      expect(saved!.n.amount(Nk.salt), closeTo(1.0, 1e-9));
      expect(saved!.n[Nk.sodium]!.value, 400);
    });
    testWidgets('4.3: «Σε ποια μέρα;» δεν κλείνει με πάτημα έξω (η ποσότητα δεν χάνεται)', (t) async {
      final now = DateTime(2026, 11, 10, 0, 20);
      final s = FoodStore.preloaded(foods: basicFoods(), now: now);
      await _pump(t, AddFoodScreen(food: s, meal: Meal.dinner, day: dayOf(now), clock: () => now));
      await t.enterText(find.byType(TextField), 'μέλι');
      await t.pumpAndSettle();
      await t.tap(find.text('Μέλι').first);
      await t.pumpAndSettle();
      await t.tap(find.textContaining('Προσθήκη στο'));
      await t.pumpAndSettle();
      expect(find.text('Σε ποια μέρα;'), findsOneWidget);
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();
      expect(find.text('Σε ποια μέρα;'), findsOneWidget);
      await t.tap(find.text('Σήμερα'));
      await t.pumpAndSettle();
      expect(s.entriesFor(DateTime(2026, 11, 10)).single.food.id, 'C31008');
    });
  });

  group('Μ5: πηγές και άδειες', () {
    test('CIQUAL με ημερομηνία ενημέρωσης και DOI, OFF με ODbL, USDA CC0', () {
      expect(sourceSentence('CIQUAL 2025'), allOf(contains('19/11/2025'), contains('10.57745/RDMHWY'), contains('Etalab')));
      expect(sourceSentence('Open Food Facts'), contains('ODbL'));
      expect(sourceSentence('USDA SR Legacy'), contains('CC0'));
      expect(sourceSentence('USDA Foundation'), contains('CC0'));
      expect(sourceSentence('Ετικέτα'), contains('ετικέτα'));
    });
    testWidgets('Λεπτομέρειες τροφίμου: η πηγή με την έκδοση· «ανά 100 ml» για υγρά', (t) async {
      await _pump(t, FoodDetailScreen(food: _food('C26025')));
      expect(find.textContaining('19/11/2025'), findsOneWidget);
      expect(find.text('Ανά 100 g'), findsOneWidget);
      final juice = foodFromDraft(FoodDraft(name: 'Χυμός', values: {Nk.kcal: 45}, perMl: true), 'M6');
      await _pump(t, FoodDetailScreen(food: juice));
      expect(find.text('Ανά 100 ml'), findsOneWidget);
    });
    testWidgets('«Πηγές και άδειες»', (t) async {
      await _pump(t, const FoodSourcesScreen());
      expect(find.text(ciqualInfo.title), findsOneWidget);
      expect(find.text(usdaInfo.title), findsOneWidget);
      expect(find.text(offInfo.title), findsOneWidget);
      expect(find.text('Licence Ouverte / Etalab 2.0'), findsOneWidget);
    });
  });

  test('Χ6: χωρίς κανάλι (δοκιμές) το ημερολόγιο μετρά ως διαβασμένο', () {
    expect(store.loaded, isTrue);
    expect(store.followsClock, isFalse);
  });
}
