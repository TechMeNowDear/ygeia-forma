// Βιβλιοθήκη φαγητών (15/11): πολλά φαγητά μαζί με μία επικόλληση. Τα φαγητά και οι προτιμήσεις είναι επινοημένα.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/food/dishes.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/food/kitchen.dart';
import 'package:ygeia_forma/food/library.dart';
import 'package:ygeia_forma/food/recipe.dart';
import 'package:ygeia_forma/pages/dishes.dart';
import 'package:ygeia_forma/pages/library.dart';
import 'package:ygeia_forma/theme.dart';

import 'sample_food.dart';

const lentils = 'C20359';
const lentilsCooked = 'C20360';
const onion = 'C20034';
const oil = 'C17270';
const salt = 'C11017';
const pepper = 'C11015';
const rusks = 'C7340';
const apple = 'C13039';
const celery = 'C20023'; // επινοημένο «δε μου αρέσει»

Map<String, Object?> lentilDish({String key = 'fakes', double grams = 250, List<Map<String, Object?>>? items, Object? steps}) => {
      'key': key,
      'name': 'Φακές κοκκινιστές',
      'cook': 'home',
      'type': 'pot',
      'servings': 3,
      'minutes': 45,
      'meals': ['lunch', 'dinner'],
      'office': true,
      'tags': ['Όσπρια', 'όσπρια', '  Λαχανικά  '],
      'items': items ??
          [
            {'id': lentils, 'name': 'Φακές (ξερές)', 'g': grams},
            {'id': onion, 'name': 'Κρεμμύδι', 'g': 100},
            {'id': oil, 'name': 'Ελαιόλαδο', 'g': 20},
            {'id': salt, 'name': 'Αλάτι', 'g': 3},
            {'id': pepper, 'name': 'Πιπέρι μαύρο', 'g': 2},
          ],
      'steps': steps ??
          [
            {'text': 'Βράσε τις φακές 30 λεπτά.', 'device': 'Κατσαρόλα', 'heat': 'μέτρια', 'min': 30},
            {'text': 'Πρόσθεσε το λάδι, ½ κουταλάκι αλάτι και πολύ πιπέρι στο τέλος.', 'min': 5},
          ],
      'keeps': 'Στο ψυγείο ως 3 μέρες',
      'kcal': 9999,
    };

final officeSnack = <String, Object?>{
  'key': 'frygania-milo',
  'name': 'Φρυγανιές με μήλο',
  'cook': 'none',
  'type': 'plate',
  'meals': ['snack'],
  'office': true,
  'items': [
    {'id': rusks, 'name': 'Φρυγανιές ολικής', 'g': 30},
    {'id': apple, 'name': 'Μήλο', 'g': 150},
  ],
};

String pack(List<Map<String, Object?>> dishes) => 'Ορίστε:\n\n```json\n${jsonEncode({'kind': libraryKind, 'dishes': dishes})}\n```\nΚαλή όρεξη!';

FoodStore store({List<Dish> dishes = const [], DishIO? io}) => FoodStore.preloaded(
      foods: basicFoods(),
      dishes: dishes,
      dishIO: io,
      likes: const FoodLikes(dislike: [celery]),
      now: DateTime(2026, 11, 16, 13),
    );

var _n = 0;
LibraryImport plan(FoodStore s, String text) => planLibraryImport(
      parseLibrary(text),
      existing: s.dishes,
      food: (id) => s.itemFood(DishItem(id, id, 1)),
      likes: s.likes,
      now: 1000,
      newId: () => 'L${_n++}',
    );

void main() {
  group('Επικόλληση βιβλιοθήκης', () {
    test('Πολλά φαγητά μαζί· τα ονόματα των υλικών από τη βάση, κανένας αριθμός θρεπτικού του βοηθού', () {
      final s = store();
      final r = plan(s, pack([lentilDish(), officeSnack]));
      expect(r.problems, isEmpty, reason: r.problems.map((p) => p.errors).join());
      expect(r.added, hasLength(2));
      final f = r.added.first;
      expect(f.name, 'Φακές κοκκινιστές');
      expect(f.kind, DishKind.pot);
      expect(f.items.map((i) => i.id), [lentils, onion, oil, salt, pepper]);
      expect(f.items.first.name, 'Φακές (ξερές)');
      expect(f.items[1].name, isNot('Κρεμμύδι'), reason: 'όνομα της βάσης, όχι του βοηθού');
      final p = planInfoOf(f)!;
      expect(p.key, 'fakes');
      expect(p.meals, [Meal.lunch, Meal.dinner]);
      expect(p.office, isTrue);
      expect(p.cook, CookWay.home);
      expect(p.tags, ['όσπρια', 'λαχανικά'], reason: 'ίδια ετικέτα μία φορά, μικρά γράμματα');
      expect(p.hasTag('ΟΣΠΡΙΑ'), isTrue);
      expect(p.hasTag('ospria'), isTrue);
      expect(recipeOf(f)!.steps, hasLength(2));
      expect(recipeOf(f)!.servings, 3);
      expect(jsonEncode(f.toJson()).contains('9999'), isFalse);
      // Χωρίς μαγείρεμα: χωρίς βήματα και χωρίς συνταγή.
      final snack = r.added[1];
      expect(planInfoOf(snack)!.cook, CookWay.none);
      expect(recipeOf(snack), isNull);
    });

    test('Κάθε πρόβλημα λέγεται· το φαγητό με πρόβλημα δεν περνά, τα υπόλοιπα περνούν', () {
      final s = store();
      final r = plan(s, pack([
        officeSnack,
        lentilDish(key: 'a', items: [
          {'id': 'X999', 'name': 'Κάτι', 'g': 10}
        ]),
        lentilDish(key: 'b', items: [
          {'id': lentils, 'name': 'Ρύζι καστανό', 'g': 80}
        ]),
        lentilDish(key: 'c', items: [
          {'id': celery, 'name': 'Σέλινο', 'g': 50}
        ]),
        lentilDish(key: 'd', items: [
          {'id': lentilsCooked, 'name': 'Φακές βρασμένες', 'g': 300}
        ]),
        lentilDish(key: 'e', steps: <Object>[]),
        {...officeSnack, 'key': 'f', 'cook': 'out'},
        {...officeSnack, 'key': 'frygania-milo'},
        {...officeSnack, 'key': 'Κεφαλαία'},
        {...officeSnack, 'key': 'g', 'meals': ['brunch']},
        {...officeSnack, 'key': 'h', 'cook': 'grill'},
      ]));
      expect(r.added.map((d) => d.name), ['Φρυγανιές με μήλο']);
      final byKey = {for (final p in r.problems) p.key: p.errors.join(' | ')};
      expect(byKey['a'], contains('δεν υπάρχει τρόφιμο με id X999'));
      expect(byKey['b'], contains('είναι «Φακές (ξερές)», όχι «Ρύζι καστανό»'));
      expect(byKey['c'], contains('«Δε μου αρέσει»'));
      expect(byKey['d'], contains('μαγειρεμένη μορφή'));
      expect(byKey['d'], contains(lentils), reason: 'λέει ποιο είναι το ωμό');
      expect(byKey['e'], contains('βήματα'));
      expect(byKey['f'], contains('«order»'));
      expect(byKey['frygania-milo'], contains('δύο φορές'));
      expect(byKey['Κεφαλαία'], contains('λατινικά'));
      expect(byKey['g'], contains('brunch'));
      expect(byKey['h'], contains('"home"'));
      final text = libraryProblemsText(r.problems);
      expect(text, contains('key: a'));
      expect(text, contains(libraryKind));
    });

    test('Φαγητό παραγγελίας: δέχεται μαγειρεμένη μορφή και κρατά το «Τι να ζητήσεις»', () {
      final r = plan(store(), pack([
        {
          'key': 'fakes-taverna',
          'name': 'Φακές από ταβέρνα',
          'cook': 'out',
          'type': 'plate',
          'order': 'Χωρίς επιπλέον λάδι, με ξίδι στο πλάι.',
          'items': [
            {'id': lentilsCooked, 'name': 'Φακές (βρασμένες)', 'g': 350},
            {'id': oil, 'name': 'Ελαιόλαδο', 'g': 15},
          ],
        }
      ]));
      expect(r.problems, isEmpty, reason: r.problems.map((p) => p.errors).join());
      expect(planInfoOf(r.added.single)!.order, 'Χωρίς επιπλέον λάδι, με ξίδι στο πλάι.');
    });

    test('Οι ίδιες οδηγίες, μισό κείμενο, άλλο είδος: το λέει, και δεν περνά τίποτα', () {
      final prompt = libraryPrompt(foods: basicFoods(), likes: const FoodLikes(), kitchen: Kitchen());
      expect(parseLibrary(prompt).errors.single, contains('οδηγίες'));
      final t = pack([lentilDish()]);
      expect(parseLibrary(t.substring(0, t.length ~/ 2)).errors, isNotEmpty);
      expect(parseLibrary('{"kind": "ygeia-recipe"}').errors.single, contains('δεν είναι βιβλιοθήκη'));
      expect(parseLibrary(jsonEncode({'kind': libraryKind, 'dishes': []})).errors.single, contains('δεν έχει φαγητά'));
    });

    test('Ξανά η ίδια επικόλληση: τίποτα νέο· αλλαγμένη: το ίδιο φαγητό, με το ιστορικό και το μαγείρεμά του', () async {
      final io = MemoryDishIO();
      final s = store(io: io);
      await s.loadDishes();
      expect(await s.saveDishes(plan(s, pack([lentilDish(), officeSnack])).changes), isTrue);
      expect(io.writes, 1, reason: 'όλα σε μία εγγραφή');
      expect(s.dishes, hasLength(2));
      final f = s.dishes.firstWhere((d) => d.name.startsWith('Φακές'));
      // Μαγειρεύτηκε και γράφτηκε μία φορά.
      const batch = PotBatch(at: 5, cooked: 1200, items: [DishItem(lentils, 'Φακές (ξερές)', 250)]);
      await s.saveDish(f.copyWith(batch: batch, lastQty: 380, used: 7, uses: 1));
      // Ο χρήστης έσβησε το σνακ από τη βιβλιοθήκη· η νέα επικόλληση δεν το σβήνει ούτε το ξαναφτιάχνει διπλό.
      final same = plan(s, pack([lentilDish(), officeSnack]));
      expect(same.changes, isEmpty);
      expect(same.unchanged, 2);
      final changed = plan(s, pack([lentilDish(grams: 300), officeSnack]));
      expect(changed.added, isEmpty);
      expect(changed.updated, hasLength(1));
      final u = changed.updated.single;
      expect(u.id, f.id);
      expect(u.items.first.amount, 300);
      expect(u.uses, 1);
      expect(u.lastQty, 380);
      expect(u.batch!.cooked, 1200, reason: 'το μαγείρεμα στο ψυγείο μένει');
      expect(u.created, f.created);
      expect(await s.saveDishes(changed.changes), isTrue);
      expect(s.dishes, hasLength(2));
      // Το αρχείο ξαναδιαβάζεται με όλα τα στοιχεία.
      final s2 = store(io: MemoryDishIO(io.json));
      await s2.loadDishes();
      final back = s2.dishById(f.id)!;
      expect(planInfoOf(back)!.tags, ['όσπρια', 'λαχανικά']);
      expect(recipeOf(back)!.steps, hasLength(2));
      expect(back.items.first.amount, 300);
    });

    test('Η αλλαγή φαγητού στην εφαρμογή κρατά τα στοιχεία της βιβλιοθήκης', () {
      final f = plan(store(), pack([lentilDish()])).added.single;
      final edited = f.copyWith(name: 'Φακές του Σαββάτου');
      expect(planInfoOf(edited)!.key, 'fakes');
      expect(planInfoOf(withRecipe(edited, null))!.key, 'fakes');
      expect(planInfoOf(withPlanInfo(edited, null)), isNull);
      expect(recipeOf(withPlanInfo(edited, null)), isNotNull);
    });
  });

  group('Οδηγίες για τον βοηθό', () {
    test('Μορφή, κανόνες, στόχοι, ωμά και μαγειρεμένα χωριστά, τα κλειδιά που υπάρχουν· χωρίς τα «δε μου αρέσει»', () {
      final existing = plan(store(), pack([lentilDish()])).added;
      final text = libraryPrompt(
        foods: basicFoods(),
        likes: const FoodLikes(like: [lentils], dislike: [celery], note: 'Πολύ πιπέρι'),
        kitchen: Kitchen(devices: {'hob'}),
        targets: (kcal: 2150, protein: 130, satMax: 14, fiber: 30, salt: 5.0),
        existing: existing,
      );
      expect(text, startsWith(libraryPromptTitle));
      expect(text, contains('"kind": "$libraryKind"'));
      expect(text, contains('2.150 kcal'));
      expect(text, contains('Πολύ πιπέρι'));
      expect(text, contains('ΥΠΑΡΧΟΥΝ ΗΔΗ ΣΤΗ ΒΙΒΛΙΟΘΗΚΗ (key: όνομα): fakes: Φακές κοκκινιστές'));
      for (final t in standardTags) {
        expect(text, contains(t));
      }
      final raw = text.substring(text.indexOf('ΤΡΟΦΙΜΑ (id όνομα), ωμά'), text.indexOf('ΜΑΓΕΙΡΕΜΕΝΑ (id όνομα)'));
      final cooked = text.substring(text.indexOf('ΜΑΓΕΙΡΕΜΕΝΑ (id όνομα)'));
      expect(raw, contains('$lentils Φακές (ξερές)'));
      expect(raw, isNot(contains('$lentilsCooked ')));
      expect(cooked, contains('$lentilsCooked Φακές (βρασμένες)'));
      expect(cooked, isNot(contains('$lentils ')));
      expect(text, isNot(contains('$celery Σέλινο')));
    });
  });

  group('Οθόνη', () {
    Future<void> pump(WidgetTester t, Widget w) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(420, 2600);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: w));
      await t.pumpAndSettle();
    }

    testWidgets('Επικόλληση → σύνοψη και προβλήματα → «Πέρασε» → στα φαγητά μου', (t) async {
      final s = store();
      await pump(t, LibraryScreen(food: s, clock: () => DateTime(2026, 11, 16, 13)));
      expect(find.text('Η βιβλιοθήκη είναι άδεια.'), findsOneWidget);
      final st = t.state(find.byType(LibraryScreen)) as dynamic;
      st.read(pack([
        lentilDish(),
        officeSnack,
        lentilDish(key: 'x', items: [
          {'id': celery, 'name': 'Σέλινο', 'g': 50}
        ]),
      ]));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('library-summary')), findsOneWidget);
      expect(find.text('Δεν περνούν (1)'), findsOneWidget);
      expect(find.textContaining('«Δε μου αρέσει»'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('library-apply')));
      await t.pumpAndSettle();
      expect(s.dishes, hasLength(2));
      expect(find.text('Στη βιβλιοθήκη: 2 φαγητά.'), findsOneWidget);
      expect(find.byKey(const ValueKey('library-apply')), findsNothing, reason: 'δεν ξαναγράφεται το ίδιο');
    });

    testWidgets('Το φαγητό της βιβλιοθήκης δείχνει πότε ταιριάζει, και «Τι να ζητήσεις»', (t) async {
      final d = plan(store(), pack([
        {
          ...officeSnack,
          'key': 'tsipoura',
          'name': 'Τσιπούρα από ψητοπωλείο',
          'cook': 'out',
          'meals': ['dinner'],
          'office': false,
          'tags': ['ψάρι'],
          'order': 'Ψητή στα κάρβουνα, λάδι και λεμόνι στο πλάι.'
        }
      ])).added.single;
      final s = store(dishes: [d]);
      await pump(t, DishEditScreen(food: s, dish: d));
      expect(find.byKey(const ValueKey('dish-plan-info')), findsOneWidget);
      expect(find.text('Από παραγγελία · Βράδυ'), findsOneWidget);
      expect(find.text('ψάρι'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('dish-plan-order')));
      await t.pumpAndSettle();
      expect(find.text('Ψητή στα κάρβουνα, λάδι και λεμόνι στο πλάι.'), findsOneWidget);
    });
  });
}
