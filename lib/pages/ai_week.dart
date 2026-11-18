// AI στο «Πρόγραμμα εβδομάδας» (19/11): «Φτιάξ’ το με AI», προεπισκόπηση πριν το «Ναι», «Άλλαξέ το με AI»,
// «Έφαγα κάτι άλλο» → οι υπόλοιπες μερίδες της μέρας. Τίποτα δεν αποθηκεύεται χωρίς «Ναι».
import 'dart:async';

import 'package:flutter/material.dart';

import '../ai/ai_bridge.dart';
import '../data.dart' show HealthStore;
import '../food/ai_food.dart';
import '../food/dishes.dart';
import '../food/food_model.dart';
import '../food/food_store.dart';
import '../food/kitchen.dart';
import '../food/library.dart';
import '../food/week.dart';
import '../food/week_calc.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';
import 'ai_settings.dart';
import 'recipes.dart' show targetsOf;

/// Τρέχει [work] με ένα παράθυρο προόδου. Με «Ακύρωση» επιστρέφει null (ό,τι έρθει μετά αγνοείται).
Future<T?> runWithProgress<T>(BuildContext context, ValueNotifier<String> text, Future<T> Function() work) async {
  final done = Completer<T?>();
  var open = true;
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    routeSettings: const RouteSettings(name: 'AI: σε εξέλιξη'),
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(width: 18),
          Expanded(child: ValueListenableBuilder(valueListenable: text, builder: (_, t, __) => Text(t, key: const ValueKey('ai-progress')))),
        ]),
        actions: [
          TextButton(
            key: const ValueKey('ai-cancel'),
            onPressed: () {
              open = false;
              Navigator.pop(ctx);
              if (!done.isCompleted) done.complete(null);
            },
            child: const Text('Ακύρωση'),
          ),
        ],
      ),
    ),
  ).whenComplete(() => open = false));
  work().then((v) {
    if (!done.isCompleted) done.complete(v);
  }, onError: (Object e, StackTrace s) {
    if (!done.isCompleted) done.completeError(e, s);
  });
  try {
    return await done.future;
  } finally {
    if (open && context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

String aiStageText(AiStage s, int done, int total) => switch (s) {
      AiStage.plan => 'Το AI διαλέγει τα φαγητά της εβδομάδας…',
      AiStage.recipes => 'Γράφει ${total == 1 ? 'τη νέα συνταγή' : 'τις νέες συνταγές'} ($done από $total)…',
      AiStage.check => 'Μετρά θερμίδες και πρωτεΐνη από τη βάση…',
      AiStage.fix => 'Διορθώνει τις μέρες που δεν βγαίνουν…',
    };

/// Αν δεν έχει συνδεθεί το AI: εξηγεί και ανοίγει τις ρυθμίσεις. `true` αν είναι έτοιμο.
Future<bool> ensureAiReady(BuildContext context, AiBridge b) async {
  await b.load();
  if (b.ready || !context.mounted) return b.ready;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Το AI δεν έχει συνδεθεί'),
      content: const Text('Η σύνδεση γίνεται μία φορά, σε 3 βήματα, στις Ρυθμίσεις › AI για το φαγητό.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Άκυρο')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Σύνδεση')),
      ],
    ),
  );
  if (go == true && context.mounted) {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'AI για το φαγητό'),
      builder: (_) => AiSettingsPage(bridge: b),
    ));
  }
  return b.ready;
}

/// «Φτιάξ’ το με AI». `null` αν ακυρώθηκε· αλλιώς οι σημειώσεις ή τα σφάλματα για την οθόνη.
Future<({List<String> notes, List<String> errors})?> aiMakeWeek(
  BuildContext context,
  FoodStore food, {
  required DateTime from,
  required List<Meal> meals,
  WeekPlan? keep,
  AiBridge? bridge,
  DateTime Function()? clock,
}) async {
  final b = bridge ?? mainAiBridge;
  if (!await ensureAiReady(context, b) || !context.mounted) return null;
  final g = HealthStore.shared?.goals;
  final targets = targetsOf(g);
  if (g == null || targets == null) {
    return (notes: const <String>[], errors: ['Πρώτα βάλε στόχους διατροφής (Εγώ › Στόχοι διατροφής).']);
  }
  final now = (clock ?? DateTime.now)();
  final text = ValueNotifier(aiStageText(AiStage.plan, 0, 1));
  final r = await runWithProgress(
    context,
    text,
    () => aiBuildWeek(
      call: b.call,
      food: food,
      kitchen: Kitchen.fromJson(HealthStore.shared?.prefs.kitchen),
      targets: targets,
      from: from,
      meals: meals,
      legumesWeek: g.legumesWeek,
      fishWeek: g.fishWeek,
      keep: keep,
      now: now.millisecondsSinceEpoch,
      newId: FoodStore.newDishId,
      progress: (s, d, t) => text.value = aiStageText(s, d, t),
    ),
  );
  text.dispose();
  if (r == null || !context.mounted) return null;
  if (r.fail != null) return (notes: const <String>[], errors: [aiErrorText(r.fail!)]);
  final plan = r.plan;
  if (plan == null) return (notes: const <String>[], errors: r.errors);
  final yes = await Navigator.of(context).push<bool>(MaterialPageRoute(
    settings: const RouteSettings(name: 'AI: προεπισκόπηση εβδομάδας'),
    builder: (_) => AiWeekPreview(food: food, plan: plan, newDishes: r.newDishes, notes: r.notes),
  ));
  if (yes != true || !context.mounted) return null;
  // Πρώτα τα νέα φαγητά (όλα μαζί), μετά το πρόγραμμα. Αν δεν γραφτούν τα φαγητά, δεν γράφεται ούτε το πρόγραμμα.
  if (r.newDishes.isNotEmpty && !await food.saveDishes(r.newDishes)) {
    return (notes: const <String>[], errors: [food.saveError ?? 'Δεν αποθηκεύτηκαν τα νέα φαγητά. Δοκίμασε ξανά.']);
  }
  if (!await food.saveWeek(keepDone(plan, food.week))) {
    return (notes: const <String>[], errors: [food.saveError ?? 'Δεν αποθηκεύτηκε το πρόγραμμα. Δοκίμασε ξανά.']);
  }
  return (notes: r.notes, errors: const <String>[]);
}

/// Η εβδομάδα του AI πριν το «Ναι»: κάθε μέρα με θερμίδες και πρωτεΐνη από τη βάση, τα νέα φαγητά σημειωμένα.
class AiWeekPreview extends StatelessWidget {
  const AiWeekPreview({super.key, required this.food, required this.plan, required this.newDishes, required this.notes});
  final FoodStore food;
  final WeekPlan plan;
  final List<Dish> newDishes;
  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final byId = {for (final d in [...food.dishes, ...newDishes]) d.id: d};
    final newIds = {for (final d in newDishes) d.id};
    final g = HealthStore.shared?.goals;
    return FoodTheme(
      child: Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(backgroundColor: c.background, surfaceTintColor: Colors.transparent, title: const Text('Το νέο πρόγραμμα')),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('ai-preview-no'),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Όχι'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      key: const ValueKey('ai-preview-yes'),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Ναι, το νέο'),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
              Text(
                newDishes.isEmpty
                    ? 'Όλα από τη βιβλιοθήκη σου. Οι αριθμοί είναι από τη βάση της εφαρμογής.'
                    : '${countText(newDishes.length, 'νέο φαγητό', 'νέα φαγητά')} (σημειωμένα «ΝΕΟ»): μπαίνουν στη '
                        'βιβλιοθήκη σου μόνο αν πεις «Ναι». Οι αριθμοί είναι από τη βάση της εφαρμογής.',
                style: TextStyle(fontSize: 14.5, height: 1.4, color: c.textSecondary),
              ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Να ξέρεις:', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: c.warn)),
                for (final n in notes) Text('• $n', style: TextStyle(fontSize: 14, height: 1.4, color: c.text)),
              ],
              for (var i = 0; i < plan.days.length; i++) ...[
                const SizedBox(height: 10),
                Builder(builder: (context) {
                  var kcal = 0.0, protein = 0.0;
                  for (final s in plan.days[i]) {
                    final t = plannedTotals(food, byId[s.dishId], s);
                    if (t == null) continue;
                    kcal += t.kcal;
                    protein += t.protein;
                  }
                  return AppCard(
                    key: ValueKey('ai-preview-day-$i'),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Expanded(
                          child: Text(shortDayDate(plan.dayAt(i)), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
                        ),
                        Text(
                          '${thousands(kcal)}${g == null ? '' : ' / ${thousands(g.kcal)}'} kcal${dotJoin}πρωτ. ${protein.round()} g',
                          style: TextStyle(fontSize: 13.5, color: c.textSecondary),
                        ),
                      ]),
                      for (final s in plan.days[i])
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            SizedBox(
                              width: 78,
                              child: Text(mealLabel(s.meal), style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
                            ),
                            Expanded(
                              child: Text.rich(TextSpan(children: [
                                TextSpan(text: byId[s.dishId]?.name ?? '—'),
                                if (newIds.contains(s.dishId))
                                  TextSpan(text: '  ΝΕΟ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c.food)),
                                if (s.locked) const TextSpan(text: '  🔒'),
                              ]), style: TextStyle(fontSize: 15, height: 1.3, color: c.text)),
                            ),
                            if (plannedTotals(food, byId[s.dishId], s) case final t?)
                              Text(' ${thousands(t.kcal)} kcal', style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
                          ]),
                        ),
                    ]),
                  );
                }),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// «Άλλαξέ το με AI»: ρωτά γιατί, βρίσκει ανάλογο, δείχνει τι αλλάζει και αποθηκεύει μόνο με «Ναι».
Future<void> aiSwapFlow(BuildContext context, FoodStore food, int day, int index, {AiBridge? bridge, DateTime Function()? clock}) async {
  final b = bridge ?? mainAiBridge;
  final w0 = food.week;
  if (w0 == null || day >= w0.days.length || index >= w0.days[day].length) return;
  final s0 = w0.days[day][index];
  final cur = food.dishById(s0.dishId);
  if (cur == null) return;
  final messenger = ScaffoldMessenger.of(context);
  final why = await showModalBottomSheet<(SwapReason, String?)>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    routeSettings: const RouteSettings(name: 'Άλλαξέ το με AI'),
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (ctx) => _SwapReasonSheet(food: food, dish: cur),
  );
  if (why == null || !context.mounted) return;
  if (!await ensureAiReady(context, b) || !context.mounted) return;
  final text = ValueNotifier('Το AI ψάχνει ανάλογο φαγητό…');
  final r = await runWithProgress(
    context,
    text,
    () => aiSwapSlot(
      call: b.call,
      food: food,
      kitchen: Kitchen.fromJson(HealthStore.shared?.prefs.kitchen),
      w: w0,
      day: day,
      index: index,
      reason: why.$1,
      missingId: why.$2,
      now: (clock ?? DateTime.now)().millisecondsSinceEpoch,
      newId: FoodStore.newDishId,
    ),
  );
  text.dispose();
  if (r == null || !context.mounted) return;
  if (r.fail != null || r.dish == null) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Δεν βρέθηκε αλλαγή'),
        content: Text(r.fail != null ? aiErrorText(r.fail!) : r.errors.join('\n')),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Εντάξει'))],
      ),
    );
    return;
  }
  final d = r.dish!;
  final oldT = plannedTotals(food, cur, s0)!;
  final newT = plannedTotals(food, d, PlanSlot(meal: s0.meal, dishId: d.id, kcal: r.kcal))!;
  if (!context.mounted) return;
  final yes = await showDialog<bool>(
    context: context,
    routeSettings: const RouteSettings(name: 'Αλλαγή γεύματος'),
    builder: (ctx) => AlertDialog(
      title: Text(d.name),
      content: Text(
        '${r.isNew ? 'Νέο φαγητό· μπαίνει και στη βιβλιοθήκη σου.\n\n' : ''}'
        'Αντί για «${cur.name}».\n'
        'Θερμίδες: ${thousands(oldT.kcal)} → ${thousands(newT.kcal)} kcal\n'
        'Πρωτεΐνη: ${oldT.protein.round()} → ${newT.protein.round()} g\n'
        'Κορεσμένα: ${oldT.satFat.toStringAsFixed(1)} → ${newT.satFat.toStringAsFixed(1)} g\n\n'
        'Από τη βάση της εφαρμογής.',
        key: const ValueKey('ai-swap-summary'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Όχι')),
        FilledButton(key: const ValueKey('ai-swap-yes'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Ναι, άλλαξέ το')),
      ],
    ),
  );
  if (yes != true) return;
  // Το πρόγραμμα άλλαξε στο μεταξύ; Τότε τίποτα.
  final w1 = food.week;
  if (w1 == null || w1.from != w0.from || day >= w1.days.length || index >= w1.days[day].length || w1.days[day][index].dishId != s0.dishId) {
    messenger.showSnackBar(const SnackBar(content: Text('Το πρόγραμμα άλλαξε στο μεταξύ· δεν έγινε αλλαγή.')));
    return;
  }
  if (r.isNew && !await food.saveDish(d)) {
    messenger.showSnackBar(SnackBar(content: Text(food.saveError ?? 'Δεν αποθηκεύτηκε το νέο φαγητό.')));
    return;
  }
  final ok = await food.saveWeek(applySwap(w1, day, index, d, r.kcal!));
  messenger.showSnackBar(SnackBar(content: Text(ok ? 'Άλλαξε: ${d.name}' : (food.saveError ?? 'Δεν αποθηκεύτηκε. Δοκίμασε ξανά.'))));
}

class _SwapReasonSheet extends StatefulWidget {
  const _SwapReasonSheet({required this.food, required this.dish});
  final FoodStore food;
  final Dish dish;

  @override
  State<_SwapReasonSheet> createState() => _SwapReasonSheetState();
}

class _SwapReasonSheetState extends State<_SwapReasonSheet> {
  bool _pickMissing = false;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final items = [
      for (final i in widget.dish.items)
        if (widget.food.itemFood(i) case final f?) f,
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(_pickMissing ? 'Τι σου λείπει;' : 'Γιατί να αλλάξει;', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.text)),
        const SizedBox(height: 4),
        Text('Το AI βρίσκει ανάλογο: ίδιες περίπου θερμίδες, όση πρωτεΐνη, όχι περισσότερα κορεσμένα.',
            style: TextStyle(fontSize: 13.5, height: 1.4, color: c.textSecondary)),
        const SizedBox(height: 12),
        if (!_pickMissing) ...[
          ListTile(
            key: const ValueKey('swap-time'),
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Δεν έχω χρόνο'),
            subtitle: Text('Ως $aiQuickMinutes λεπτά ή χωρίς μαγείρεμα'),
            onTap: () => Navigator.pop(context, (SwapReason.time, null)),
          ),
          ListTile(
            key: const ValueKey('swap-missing'),
            leading: const Icon(Icons.remove_shopping_cart_outlined),
            title: const Text('Μου λείπει υλικό'),
            onTap: () => setState(() => _pickMissing = true),
          ),
          ListTile(
            key: const ValueKey('swap-appetite'),
            leading: const Icon(Icons.sentiment_neutral_rounded),
            title: const Text('Δεν μου κάνει όρεξη'),
            onTap: () => Navigator.pop(context, (SwapReason.appetite, null)),
          ),
        ] else
          for (final f in items)
            ListTile(
              key: ValueKey('swap-missing-${f.id}'),
              title: Text(f.name),
              onTap: () => Navigator.pop(context, (SwapReason.missing, f.id)),
            ),
      ]),
    );
  }
}

/// Μετά το «Έφαγα κάτι άλλο» (μόνο για σήμερα): προτείνει τις νέες μερίδες των υπόλοιπων γευμάτων της μέρας.
Future<void> offerRebalance(BuildContext context, FoodStore food, int day, {DateTime Function()? clock}) async {
  final w = food.week;
  final g = HealthStore.shared?.goals;
  if (w == null || g == null || day >= w.days.length) return;
  final now = (clock ?? DateTime.now)();
  if (!sameDay(w.dayAt(day), now)) return;
  final eaten = Totals(food.entriesFor(now)).kcal;
  final r = rebalanceDay(food, w, day, eaten, g.kcal.toDouble());
  if (r == null || !context.mounted) return;
  final (w2, changes) = r;
  final yes = await showDialog<bool>(
    context: context,
    routeSettings: const RouteSettings(name: 'Υπόλοιπα γεύματα'),
    builder: (ctx) => AlertDialog(
      title: const Text('Να προσαρμοστούν τα υπόλοιπα γεύματα;'),
      content: Text(
        'Ως τώρα σήμερα: ${thousands(eaten)} από ${thousands(g.kcal)} kcal.\n\n'
        '${[for (final (n, a, b) in changes) '$n: ${thousands(a)} → ${thousands(b)} kcal'].join('\n')}',
        key: const ValueKey('rebalance-text'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Όχι')),
        FilledButton(key: const ValueKey('rebalance-yes'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Ναι')),
      ],
    ),
  );
  if (yes != true) return;
  // Μόνο αν το πρόγραμμα δεν άλλαξε στο μεταξύ.
  if (identical(food.week, w)) await food.saveWeek(w2);
}

/// «Μου άρεσε» / «Δεν μου άρεσε» για ένα φαγητό (η βαθμολογία πάει στο AI και στο «Φτιάξε πρόγραμμα»).
Future<void> rateDish(BuildContext context, FoodStore food, Dish d, int r) async {
  final messenger = ScaffoldMessenger.of(context);
  final cur = dishRating(d);
  final next = cur == r ? 0 : r;
  final ok = await food.saveDish(withRating(d, next));
  messenger.showSnackBar(SnackBar(
    persist: false,
    content: Text(!ok
        ? (food.saveError ?? 'Δεν αποθηκεύτηκε.')
        : next == 1
            ? 'Σημειώθηκε: σου άρεσε. Θα μπαίνει πιο συχνά.'
            : next == -1
                ? 'Σημειώθηκε: δεν σου άρεσε. Δεν θα προτείνεται.'
                : 'Η βαθμολογία σβήστηκε.'),
  ));
}
