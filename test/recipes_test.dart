// Συνταγές με επικόλληση και «Τι μου αρέσει» (15/11, βήμα 2). Οι συνταγές και οι προτιμήσεις είναι επινοημένες.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/backup.dart';
import 'package:ygeia_forma/food/dishes.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/food/kitchen.dart';
import 'package:ygeia_forma/food/recipe.dart';
import 'package:ygeia_forma/goals.dart';
import 'package:ygeia_forma/pages/recipes.dart';
import 'package:ygeia_forma/theme.dart';

import 'sample_food.dart';

const lentils = 'C20359';
const onion = 'C20034';
const carrot = 'C20009';
const oil = 'C17270';
const celery = 'C20023'; // Σέλινο κοτσάνι (ωμό): επινοημένο «δε μου αρέσει»

String recipeText({String type = 'pot', Object? servings = 4, List<Map<String, Object?>>? items, List<Object>? steps}) => '''
Ορίστε μια συνταγή:

```json
${jsonEncode({
      'kind': recipeKind,
      'name': 'Φακές με καρότο',
      'type': type,
      if (servings != null) 'servings': servings,
      'minutes': 45,
      'items': items ??
          [
            {'id': lentils, 'name': 'Φακές (ξερές)', 'g': 250},
            {'id': onion, 'name': 'Κρεμμύδι ξερό (ωμό)', 'g': 100},
            {'id': carrot, 'name': 'Καρότο (ωμό)', 'g': 150},
            {'id': oil, 'name': 'Ελαιόλαδο εξαιρετικά παρθένο', 'g': 20},
          ],
      'steps': steps ??
          [
            {'text': 'Ξέπλυνε τις φακές.', 'min': 2},
            {'text': 'Βράσε τις φακές με 1,5 λίτρο νερό.', 'device': 'Κατσαρόλα μεγάλη', 'heat': 'μέτρια', 'min': 30},
          ],
      'tips': ['Λίγο ξίδι στο πιάτο.'],
      'keeps': 'Στο ψυγείο ως 3 μέρες',
      'why': 'Πολλές ίνες, λίγα κορεσμένα.',
      'kcal': 9999,
    })}
```

Καλή όρεξη! {όχι json}
''';

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(420, 2600)}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: w));
  await t.pumpAndSettle();
}

FoodStore store({FoodLikes likes = const FoodLikes(), DishIO? io}) =>
    FoodStore.preloaded(foods: basicFoods(), likes: likes, dishIO: io, now: DateTime(2026, 11, 16, 13));

void main() {
  group('Επικόλληση', () {
    test('Η συνταγή μέσα σε όλο το μήνυμα· ό,τι αριθμό θρεπτικού γράψει ο βοηθός αγνοείται', () {
      final p = parseRecipe(recipeText());
      expect(p.ok, isTrue, reason: p.errors.join());
      final r = p.recipe!;
      expect(r.name, 'Φακές με καρότο');
      expect(r.kind, DishKind.pot);
      expect(r.servings, 4);
      expect(r.items.map((i) => i.id), [lentils, onion, carrot, oil]);
      expect(r.items.map((i) => i.amount), [250, 100, 150, 20]);
      expect(r.recipe.steps, hasLength(2));
      expect(r.recipe.steps[1].device, 'Κατσαρόλα μεγάλη');
      expect(r.recipe.steps[1].minutes, 30);
      expect(r.recipe.minutes, 45);
      expect(r.recipe.keeps, 'Στο ψυγείο ως 3 μέρες');
      expect(jsonEncode(r.recipe.toJson()).contains('9999'), isFalse);
    });

    test('Ό,τι δεν στέκει λέγεται, και δεν αποθηκεύεται', () {
      expect(parseRecipe('καμία συνταγή').ok, isFalse);
      expect(parseRecipe('{"kind": "ygeia-program"}').errors.single, contains('δεν είναι συνταγή'));
      expect(parseRecipe(recipeText(items: [])).errors, contains('Η συνταγή δεν έχει υλικά.'));
      final zero = parseRecipe(recipeText(items: [
        {'id': lentils, 'name': 'Φακές', 'g': 0}
      ]));
      expect(zero.errors.first, contains('η ποσότητα'));
      expect(parseRecipe(recipeText(type: 'portions', servings: null)).errors.first, contains('μερίδες'));
      expect(parseRecipe(recipeText(steps: [])).errors, contains('Η συνταγή δεν έχει βήματα.'));
    });

    test('Αντιγράφηκε μισό: δεν διαβάζεται', () {
      final t = recipeText();
      expect(parseRecipe(t.substring(0, t.length ~/ 2)).ok, isFalse);
    });
  });

  group('Η συνταγή μέσα στο φαγητό', () {
    test('Μένει με το φαγητό (και στο αρχείο) και διαβάζεται ξανά', () {
      final r = parseRecipe(recipeText()).recipe!;
      final d = withRecipe(
          Dish(id: 'D1', name: r.name, kind: r.kind, items: const [DishItem(lentils, 'Φακές', 250)], created: 0), r.recipe);
      final back = Dish.fromJson(jsonDecode(jsonEncode(d.toJson())))!;
      final rr = recipeOf(back)!;
      expect(rr.steps.map((s) => s.text), ['Ξέπλυνε τις φακές.', 'Βράσε τις φακές με 1,5 λίτρο νερό.']);
      expect(rr.tips, ['Λίγο ξίδι στο πιάτο.']);
      expect(recipeOf(withRecipe(back, null)), isNull);
    });
  });

  group('Οδηγίες για τον βοηθό', () {
    test('Κανόνες, μορφή, στόχοι, κουζίνα, τι μου αρέσει· τα «δε μου αρέσει» και οι μαγειρεμένες μορφές έξω από τη λίστα', () {
      final text = recipePrompt(
        wish: 'κάτι με φακές',
        foods: basicFoods(),
        likes: const FoodLikes(like: [lentils], dislike: [celery], note: 'Γρήγορα φαγητά τις καθημερινές'),
        kitchen: Kitchen(devices: {'hob', 'steamer'}),
        targets: (kcal: 2150, protein: 130, satMax: 14, fiber: 30, salt: 5.0),
        left: (kcal: 900, protein: 60),
      );
      expect(text, contains('Τι θέλω: κάτι με φακές'));
      expect(text, contains('"kind": "$recipeKind"'));
      expect(text, contains('ΩΜΑ'));
      expect(text, contains('2.150 kcal'));
      expect(text, contains('ΣΗΜΕΡΑ ΜΟΥ ΜΕΝΟΥΝ: 900 kcal'));
      expect(text, contains('ΚΟΥΖΙΝΑ: Μάτια κουζίνας, Ατμομάγειρας'));
      expect(text, contains('ΜΟΥ ΑΡΕΣΟΥΝ: $lentils Φακές (ξερές)'));
      expect(text, contains('ΔΕ ΜΟΥ ΑΡΕΣΟΥΝ: $celery'));
      expect(text, contains('Γρήγορα φαγητά'));
      final list = text.substring(text.indexOf('ΤΡΟΦΙΜΑ (id όνομα)'));
      expect(list, contains('$lentils Φακές (ξερές)'));
      expect(list, isNot(contains('C20360 ')), reason: 'οι βρασμένες φακές είναι μαγειρεμένη μορφή');
      expect(list, isNot(contains('$celery ')), reason: 'δε μου αρέσει');
      // Το παράδειγμα μέσα στις οδηγίες δεν διαβάζεται ως συνταγή: αν επικολληθούν οι οδηγίες, το λέμε.
      final back = parseRecipe(text);
      expect(back.ok, isFalse);
      expect(back.errors.single, contains('οδηγίες'));
    });
  });

  group('«Τι μου αρέσει»', () {
    test('Ένα τρόφιμο δεν είναι και στα δύο· επικόλληση: όσα id δεν υπάρχουν λέγονται χωριστά', () {
      final l = FoodLikes.fromJson({
        'like': [lentils, celery, lentils],
        'dislike': [celery],
      });
      expect(l.like, [lentils]);
      expect(l.dislike, [celery]);
      final r = parseLikes(
        jsonEncode({'kind': likesKind, 'like': [lentils, 'X-λάθος'], 'dislike': [celery], 'note': 'σημείωση'}),
        (id) => basicFoods().any((f) => f.id == id),
      )!;
      expect(r.likes.like, [lentils]);
      expect(r.unknown, ['X-λάθος']);
      expect(r.likes.note, 'σημείωση');
    });

    test('Γράφεται στο αρχείο των φαγητών και ξαναδιαβάζεται· μπαίνει στο αντίγραφο', () async {
      final io = MemoryDishIO();
      final s = store(io: io);
      await s.loadDishes();
      expect(await s.saveLikes(const FoodLikes(like: [lentils], dislike: [celery], note: 'x')), isTrue);
      final s2 = store(io: io);
      await s2.loadDishes();
      expect(s2.likes.like, [lentils]);
      expect(s2.likes.dislike, [celery]);
      final b = parseBackup(buildBackup(
          foodLog: const [], myFoods: const [], prefs: const {}, now: DateTime(2026, 11, 16), foodLikes: s2.likesForBackup()));
      expect(b.likes.like, [lentils]);
      // Επαναφορά: μόνο αν το κινητό δεν έχει.
      final s3 = store(io: MemoryDishIO());
      await s3.loadDishes();
      expect(await s3.importLikes(b.likes), isTrue);
      expect(await s3.importLikes(const FoodLikes(like: [onion])), isFalse);
      expect(s3.likes.like, [lentils]);
    });
  });

  group('Οθόνες', () {
    testWidgets('Επικόλληση: οι αριθμοί από τη βάση, αποθήκευση ως φαγητό με τη συνταγή', (t) async {
      final s = store();
      await _pump(t, RecipePreviewScreen(food: s, text: recipeText(), goals: null));
      expect(find.text('Φακές (ξερές)'), findsOneWidget);
      // Όλη η κατσαρόλα: 327×2,5 + 39×1 + 30,2×1,5 + 899×0,2 = 1.081,6 kcal.
      expect(find.textContaining('Όλη η κατσαρόλα: 1.082 kcal'), findsOneWidget);
      // Μία μερίδα περίπου (1 από 4): 270 kcal.
      expect(find.text('270'), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('recipe-save')));
      await t.tap(find.byKey(const ValueKey('recipe-save')));
      await t.pumpAndSettle();
      final d = s.dishes.single;
      expect(d.name, 'Φακές με καρότο');
      expect(d.kind, DishKind.pot);
      expect(d.items.map((i) => i.amount), [250, 100, 150, 20]);
      expect(recipeOf(d)!.steps, hasLength(2));
      expect(recipeOf(d)!.servings, 4);
    });

    testWidgets('Υλικό με id που δεν υπάρχει: από το όνομα, με σημείωση· αν δεν βρεθεί, η αποθήκευση περιμένει', (t) async {
      final s = store();
      await _pump(
        t,
        RecipePreviewScreen(
          food: s,
          text: recipeText(items: [
            {'id': 'ΛΑΘΟΣ', 'name': 'Φακές (ξερές)', 'g': 250},
            {'id': 'ΛΑΘΟΣ2', 'name': 'Σαφράν της Κοζάνης', 'g': 1},
          ]),
        ),
      );
      expect(find.textContaining('Βρέθηκε από το όνομα'), findsOneWidget);
      expect(find.textContaining('Δεν βρέθηκε «Σαφράν της Κοζάνης»'), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('recipe-save')));
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('recipe-save'))).onPressed, isNull);
    });

    testWidgets('Υλικό από τα «Δε μου αρέσει»: φαίνεται και η αποθήκευση περιμένει', (t) async {
      final s = store(likes: const FoodLikes(dislike: [onion]));
      await _pump(t, RecipePreviewScreen(food: s, text: recipeText()));
      expect(find.textContaining('Στα «Δε μου αρέσει»'), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('recipe-save')));
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('recipe-save'))).onPressed, isNull);
    });

    testWidgets('Με στόχους: μία μερίδα σε σχέση με τη μέρα', (t) async {
      final s = store();
      final g = Goals(
        aim: GoalAim.lose,
        rate: 0.005,
        activity: 1.5,
        doctor: false,
        since: '2026-11-16',
        kg: 90,
        age: 40,
        heightCm: 180,
        male: true,
        nutsG: 30,
        branG: 40,
        legumesWeek: 4,
        fishWeek: 2,
      );
      await _pump(t, RecipePreviewScreen(food: s, text: recipeText(), goals: g));
      expect(find.text('Κορεσμένα'), findsOneWidget);
      expect(find.text('Αλάτι'), findsOneWidget);
      expect(find.textContaining('από ${g.protein} g'), findsOneWidget);
    });

    testWidgets('Μαγείρεμα: βήματα, τικ, χρονόμετρο', (t) async {
      final s = store();
      final r = parseRecipe(recipeText()).recipe!;
      final d = withRecipe(Dish(id: 'D1', name: r.name, kind: r.kind, items: const [DishItem(lentils, 'Φακές', 250)], created: 0), r.recipe);
      await _pump(t, CookScreen(dish: d, recipe: recipeOf(d)!, food: s));
      expect(find.textContaining('2. Βράσε τις φακές'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('cook-start-1')));
      await t.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('cook-timer')), findsOneWidget);
      expect(find.textContaining('Βήμα 2: 29:5'), findsOneWidget);
      await t.tap(find.text('Στοπ'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('cook-timer')), findsNothing);
    });
  });
}
