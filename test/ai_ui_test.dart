// AI για το φαγητό (19/11): οι οθόνες. Ψεύτικη γέφυρα, χωρίς δίκτυο.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/ai/ai_bridge.dart';
import 'package:ygeia_forma/food/dishes.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/food/recipe.dart';
import 'package:ygeia_forma/food/week.dart';
import 'package:ygeia_forma/oura/oura_api.dart' show MemoryVault;
import 'package:ygeia_forma/pages/ai_settings.dart';
import 'package:ygeia_forma/pages/ai_week.dart';
import 'package:ygeia_forma/pages/recipes.dart' show FoodLikesScreen;
import 'package:ygeia_forma/theme.dart';

import 'sample_food.dart';

Future<void> pump(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(420, 2000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: w));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('Ρυθμίσεις AI: κλειδί, Project ID, δοκιμή', (t) async {
    final sent = <String>[];
    final b = AiBridge(MemoryVault(), send: (u, token, body) async {
      sent.add(u.toString());
      return (200, '{"ok":true,"text":"ΟΚ","stop":"end_turn"}');
    });
    await pump(t, AiSettingsPage(bridge: b));
    // Χωρίς κλειδί και διεύθυνση: η δοκιμή δεν πατιέται.
    expect(t.widget<FilledButton>(find.byKey(const ValueKey('ai-test'))).onPressed, isNull);

    await t.tap(find.byKey(const ValueKey('ai-make-token')));
    await t.pumpAndSettle();
    expect(b.token, hasLength(43));
    // Κρυμμένο μέχρι να το ζητήσεις (X-9): φαίνονται μόνο οι 4 πρώτοι και οι 4 τελευταίοι χαρακτήρες.
    expect(find.text(b.token!), findsNothing);
    await t.tap(find.byKey(const ValueKey('ai-show-token')));
    await t.pumpAndSettle();
    expect(find.text(b.token!), findsOneWidget);

    await t.enterText(find.byKey(const ValueKey('ai-project-id')), 'λάθος');
    await t.tap(find.byKey(const ValueKey('ai-save-id')));
    await t.pumpAndSettle();
    expect(b.url, isNull);
    // Το μήνυμα λάθους (κάτω) καλύπτει το κουμπί: κλείνει πριν το επόμενο πάτημα.
    ScaffoldMessenger.of(t.element(find.byType(Scaffold).first)).removeCurrentSnackBar();
    await t.pumpAndSettle();

    await t.enterText(find.byKey(const ValueKey('ai-project-id')), 'abcdefghij0123456789');
    await t.tap(find.byKey(const ValueKey('ai-save-id')));
    await t.pumpAndSettle();
    expect(b.ready, isTrue);

    await t.tap(find.byKey(const ValueKey('ai-test')));
    await t.pumpAndSettle();
    expect(find.text('Η σύνδεση δουλεύει.'), findsOneWidget);
    expect(b.okDay, isNotNull);
    expect(find.textContaining('Συνδεδεμένο ✓'), findsOneWidget);
    expect(sent.single, 'https://abcdefghij0123456789.supabase.co/functions/v1/ai-food');
    expect(find.textContaining('Ποτέ ζυγίσεις'), findsOneWidget);

    await t.ensureVisible(find.byKey(const ValueKey('ai-disconnect')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('ai-disconnect')));
    await t.pumpAndSettle();
    await t.tap(find.text('Αποσύνδεση').last);
    await t.pumpAndSettle();
    expect(b.ready, isFalse);
  });

  testWidgets('Ρυθμίσεις AI: σφάλμα της γέφυρας σε απλά λόγια', (t) async {
    final v = MemoryVault();
    final b = AiBridge(v, send: (u, token, body) async => (401, '{"ok":false,"kind":"token"}'));
    await b.setUrl('abcdefghij0123456789');
    await b.ensureToken();
    await pump(t, AiSettingsPage(bridge: b));
    await t.tap(find.byKey(const ValueKey('ai-test')));
    await t.pumpAndSettle();
    expect(find.text(aiErrorText(AiFail.token)), findsOneWidget);
    expect(b.okDay, isNull);
    expect(find.textContaining('Συνδεδεμένο ✓'), findsNothing);
  });

  testWidgets('Τι μου αρέσει: τα βασικά κουζίνας τσεκάρονται, το «δε μου αρέσει» τα κλειδώνει', (t) async {
    const oil = 'C17270', salt = 'C11017';
    final food = FoodStore.preloaded(
        foods: basicFoods(), likes: const FoodLikes(like: ['C36017'], dislike: [salt]), now: DateTime(2026, 11, 23));
    await pump(t, FoodLikesScreen(food: food));
    expect(find.byKey(const ValueKey('likes-staples')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('staple-$oil')));
    await t.pumpAndSettle();
    expect(food.likes.staple, [oil]);
    await t.tap(find.byKey(const ValueKey('staple-$oil')));
    await t.pumpAndSettle();
    expect(food.likes.staple, isEmpty);
    // «Μου αρέσει» και «βασικό» είναι ανεξάρτητα: τα «Μου αρέσει» δεν άλλαξαν.
    expect(food.likes.like, ['C36017']);
    // Το αλάτι είναι στα «δε μου αρέσει»: δεν τσεκάρεται.
    expect(t.widget<FilterChip>(find.byKey(const ValueKey('staple-$salt'))).onSelected, isNull);
  });

  testWidgets('Προεπισκόπηση: τα νέα φαγητά φαίνονται «ΝΕΟ», τίποτα δεν γράφεται πριν το «Ναι»', (t) async {
    final food = FoodStore.preloaded(foods: basicFoods(), now: DateTime(2026, 11, 23));
    const d = Dish(id: 'N1', name: 'Κοτόπουλο φούρνου', kind: DishKind.plate, items: [DishItem('C36017', 'Κοτόπουλο', 200)], created: 1);
    final plan = WeekPlan(from: '2026-11-23', created: 1, source: 'ai', days: [
      [const PlanSlot(meal: Meal.lunch, dishId: 'N1', kcal: 400)],
    ]);
    bool? got;
    await pump(
        t,
        Builder(
            builder: (context) => TextButton(
                onPressed: () async => got = await Navigator.of(context).push<bool>(MaterialPageRoute(
                    builder: (_) => AiWeekPreview(food: food, plan: plan, newDishes: const [d], notes: const ['Μία σημείωση.']))),
                child: const Text('άνοιξε'))));
    await t.tap(find.text('άνοιξε'));
    await t.pumpAndSettle();
    expect(find.textContaining('ΝΕΟ'), findsWidgets);
    expect(find.text('• Μία σημείωση.'), findsOneWidget);
    expect(food.dishes, isEmpty);
    await t.tap(find.byKey(const ValueKey('ai-preview-yes')));
    await t.pumpAndSettle();
    expect(got, isTrue);
  });
}
