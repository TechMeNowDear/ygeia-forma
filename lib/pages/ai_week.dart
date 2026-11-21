// AI στο «Πρόγραμμα εβδομάδας» (19/11, βαθύς έλεγχος 19/11): «Φτιάξ’ το με AI», προεπισκόπηση πριν το «Ναι», «Άλλαξέ το
// με AI», «Έφαγα κάτι άλλο» → οι υπόλοιπες μερίδες της μέρας. Τίποτα δεν αποθηκεύεται χωρίς «Ναι».
import 'dart:async';

import 'package:flutter/material.dart';

import '../ai/ai_bridge.dart';
import '../data.dart' show HealthStore;
import '../error_report.dart' show errors;
import '../food/ai_food.dart';
import '../food/chol.dart' show satLimitShown;
import '../food/dishes.dart';
import '../food/food_model.dart';
import '../food/food_store.dart';
import '../food/kitchen.dart';
import '../food/library.dart';
import '../food/recipe.dart';
import '../food/week.dart';
import '../food/week_auto.dart';
import '../food/week_calc.dart';
import '../format.dart';
import '../goals.dart' show Goals;
import '../theme.dart';
import '../widgets.dart';
import 'ai_settings.dart';
import 'recipes.dart' show FoodLikesScreen, RecipeSteps;

/// Ως τόσο περιμένουμε ένα ολόκληρο «Φτιάξ’ το με AI» (μετά σταματά μόνο του).
const aiTotalCap = Duration(minutes: 10);

/// Οι στόχοι για τους ελέγχους του AI (μένουν στο κινητό). Τα κορεσμένα όπως τα γράφει η σελίδα «Στόχοι» (13,9, όχι 13).
AiTargets aiTargetsOf(Goals g) =>
    (kcal: g.kcal, protein: g.protein, satMax: satLimitShown(g.kcal, g.satPct), fiber: g.fiber, salt: g.salt);

/// Τρέχει [work] με ένα παράθυρο προόδου (στάδιο, ρολόι). «Ακύρωση» ή όριο χρόνου: καμία νέα κλήση στο AI και
/// επιστρέφει `value: null` ([capped] αν έληξε ο χρόνος). Κλείνει πάντα μόνο το ΔΙΚΟ του παράθυρο (U-2). Σφάλμα του
/// [work] → αναφορά σφάλματος και `value: null` με [crashed].
Future<({T? value, bool capped, bool crashed})> runWithProgress<T>(
  BuildContext context,
  ValueNotifier<String> text,
  Future<T> Function(AiCancel cancel) work, {
  Duration cap = aiTotalCap,
}) async {
  final nav = Navigator.of(context, rootNavigator: true);
  final cancel = AiCancel();
  final done = Completer<({T? value, bool capped, bool crashed})>();
  final route = DialogRoute<void>(
    context: context,
    themes: InheritedTheme.capture(from: context, to: nav.context),
    barrierDismissible: false,
    settings: const RouteSettings(name: 'AI σε εξέλιξη'),
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: _ProgressBody(text: text),
        actions: [
          TextButton(
            key: const ValueKey('ai-cancel'),
            onPressed: () {
              cancel.cancel();
              if (!done.isCompleted) done.complete((value: null, capped: false, crashed: false));
            },
            child: const Text('Ακύρωση'),
          ),
        ],
      ),
    ),
  );
  unawaited(nav.push(route));
  final timer = Timer(cap, () {
    cancel.cancel();
    if (!done.isCompleted) done.complete((value: null, capped: true, crashed: false));
  });
  work(cancel).then((v) {
    if (!done.isCompleted) done.complete((value: v, capped: false, crashed: false));
  }, onError: (Object e, StackTrace s) {
    unawaited(errors.report(e, s));
    if (!done.isCompleted) done.complete((value: null, capped: false, crashed: true));
  });
  try {
    return await done.future;
  } finally {
    timer.cancel();
    cancel.cancel();
    if (route.isActive) {
      if (route.isCurrent) {
        nav.pop();
      } else {
        nav.removeRoute(route);
      }
    }
  }
}

class _ProgressBody extends StatefulWidget {
  const _ProgressBody({required this.text});
  final ValueNotifier<String> text;

  @override
  State<_ProgressBody> createState() => _ProgressBodyState();
}

class _ProgressBodyState extends State<_ProgressBody> {
  final _start = DateTime.now();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Το ρολόι τρέχει μόνο όσο είναι ανοιχτό το παράθυρο.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final s = DateTime.now().difference(_start).inSeconds;
    final clock = '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, semanticsLabel: 'Περιμένουμε το AI')),
        const SizedBox(width: 18),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: ValueListenableBuilder(
              valueListenable: widget.text,
              builder: (_, t, __) => Text(t, key: const ValueKey('ai-progress'), style: TextStyle(fontSize: 15, height: 1.35, color: c.text)),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      Text('$clock · συνήθως 1–3 λεπτά. Μείνε στην εφαρμογή· η οθόνη μπορεί να σβήσει.',
          style: TextStyle(fontSize: 13, height: 1.35, color: c.textSecondary)),
    ]);
  }
}

String aiStageText(AiStage s, int done, int total, int attempt) {
  final base = switch (s) {
    AiStage.plan => 'Το AI διαλέγει τα φαγητά της εβδομάδας…',
    AiStage.recipes => 'Γράφει ${total == 1 ? 'τη νέα συνταγή' : 'τις νέες συνταγές'} ($done από $total)…',
    AiStage.check => 'Μετρά θερμίδες, πρωτεΐνη, αλάτι και ίνες από τη βάση…',
    AiStage.fix => 'Διορθώνει τις μέρες που δεν βγαίνουν…',
  };
  return attempt > 1 ? '$base\nΤο AI διορθώνει την απάντησή του (προσπάθεια $attempt από ${aiMaxRetries + 1}).' : base;
}

/// Αν δεν έχει συνδεθεί το AI: εξηγεί και ανοίγει τις ρυθμίσεις. Αν δεν έχει γίνει «Δοκιμή σύνδεσης», το λέει. `true` αν
/// μπορεί να ξεκινήσει.
Future<bool> ensureAiReady(BuildContext context, AiBridge b) async {
  if (!b.loaded && !await b.load()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(aiErrorText(AiFail.vault))));
    }
    return false;
  }
  if (!context.mounted) return false;
  if (b.ready && b.okDay != null) return true;
  final go = await showDialog<bool>(
    context: context,
    routeSettings: const RouteSettings(name: 'AI χωρίς σύνδεση'),
    builder: (ctx) => AlertDialog(
      scrollable: true,
      title: Text(b.ready ? 'Κάνε πρώτα «Δοκιμή σύνδεσης»' : 'Το AI δεν έχει συνδεθεί'),
      content: Text(b.ready
          ? 'Η διεύθυνση και το κλειδί είναι στο κινητό, αλλά η σύνδεση δεν έχει δοκιμαστεί. Δοκίμασέ την στις Ρυθμίσεις › AI '
              'για το φαγητό.'
          : 'Η σύνδεση γίνεται μία φορά, σε λίγα βήματα, στις Ρυθμίσεις › AI για το φαγητό.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Άκυρο')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(b.ready ? 'Δοκιμή' : 'Σύνδεση')),
      ],
    ),
  );
  if (go == true && context.mounted) {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'AI για το φαγητό'),
      builder: (_) => AiSettingsPage(bridge: b),
    ));
  }
  return b.ready && b.okDay != null;
}

/// Αποτέλεσμα για την οθόνη: [errors] πρώτη γραμμή για τον χρήστη, μετά λεπτομέρειες (για «Λεπτομέρειες»).
typedef AiOutcome = ({List<String> notes, List<String> errors});

final _disposed = Expando<bool>();
bool _isDisposed(ValueNotifier<String> n) => _disposed[n] == true;
void _dispose(ValueNotifier<String> n) {
  _disposed[n] = true;
  n.dispose();
}

/// «Φτιάξ’ το με AI». `null` αν ακυρώθηκε ή δεν ξεκίνησε· αλλιώς οι σημειώσεις ή τα σφάλματα για την οθόνη.
Future<AiOutcome?> aiMakeWeek(
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
  if (g == null) return (notes: const <String>[], errors: [noGoalsText]);
  final now = (clock ?? DateTime.now)();
  final text = ValueNotifier(aiStageText(AiStage.plan, 0, 1, 1));
  ({AiWeekResult? value, bool capped, bool crashed}) run;
  try {
    run = await runWithProgress<AiWeekResult>(
      context,
      text,
      (cancel) => aiBuildWeek(
        call: cancel.wrap(b.call),
        food: food,
        kitchen: Kitchen.fromJson(HealthStore.shared?.prefs.kitchen),
        targets: aiTargetsOf(g),
        from: from,
        meals: meals,
        legumesWeek: g.legumesWeek,
        fishWeek: g.fishWeek,
        bodyKg: g.kg,
        keep: keep,
        now: now.millisecondsSinceEpoch,
        today: now,
        newId: FoodStore.newDishId,
        progress: (s, d, t, a) {
          if (!_isDisposed(text) && !cancelledText(text)) text.value = aiStageText(s, d, t, a);
        },
      ),
    );
  } finally {
    _dispose(text);
  }
  if (!context.mounted) return null;
  if (run.capped) return (notes: const <String>[], errors: const ['Πήρε πολύ ώρα (πάνω από 10 λεπτά). Δοκίμασε ξανά σε λίγο.']);
  if (run.crashed) return (notes: const <String>[], errors: const ['Κάτι πήγε στραβά. Δοκίμασε ξανά.']);
  final r = run.value;
  if (r == null || r.fail == AiFail.cancelled) return null;
  if (r.fail != null) return (notes: const <String>[], errors: [aiErrorText(r.fail!)]);
  final plan = r.plan;
  if (plan == null) return (notes: const <String>[], errors: r.errors);
  final yes = await Navigator.of(context).push<bool>(MaterialPageRoute(
    settings: const RouteSettings(name: 'AI προεπισκόπηση εβδομάδας'),
    builder: (_) => AiWeekPreview(food: food, plan: plan, newDishes: r.newDishes, notes: r.notes, replaces: food.week),
  ));
  if (yes != true || !context.mounted) return null;
  // Μία εγγραφή για νέα φαγητά και πρόγραμμα (ίδιο αρχείο): ή όλα ή τίποτα (I-13/U-5). Αν αποτύχει, ξανά μόνο η εγγραφή.
  while (!await food.saveDishesAndWeek(r.newDishes, keepDone(plan, food.week))) {
    if (!context.mounted) return null;
    final again = await showDialog<bool>(
      context: context,
      routeSettings: const RouteSettings(name: 'AI δεν αποθηκεύτηκε'),
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Δεν αποθηκεύτηκε'),
        content: Text(food.saveError ?? 'Το πρόγραμμα δεν αποθηκεύτηκε. Δοκίμασε ξανά.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Άκυρο')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ξανά')),
        ],
      ),
    );
    if (again != true) return (notes: const <String>[], errors: const ['Το πρόγραμμα δεν αποθηκεύτηκε.']);
  }
  return (notes: r.notes, errors: const <String>[]);
}

/// Για τα tests: η πρόοδος μετά το κλείσιμο δεν γράφει πια (ο notifier έχει σβηστεί).
bool cancelledText(ValueNotifier<String> n) => _isDisposed(n);

/// Η εβδομάδα του AI πριν το «Ναι»: κάθε μέρα με θερμίδες και πρωτεΐνη από τη βάση, τα νέα φαγητά σημειωμένα (πάτημα:
/// υλικά και συνταγή). Σε μεγάλη οθόνη δύο στήλες.
class AiWeekPreview extends StatelessWidget {
  const AiWeekPreview({super.key, required this.food, required this.plan, required this.newDishes, required this.notes, this.replaces});
  final FoodStore food;
  final WeekPlan plan;
  final List<Dish> newDishes;
  final List<String> notes;

  /// Το τωρινό πρόγραμμα, αν αντικαθίσταται (U-4).
  final WeekPlan? replaces;

  Future<bool> _confirmDiscard(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        routeSettings: const RouteSettings(name: 'AI πέταμα προγράμματος'),
        builder: (ctx) => AlertDialog(
          title: const Text('Να πεταχτεί το νέο πρόγραμμα;'),
          content: const Text('Για να το ξαναδείς θα χρειαστεί να το φτιάξει ξανά το AI.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Πίσω')),
            FilledButton(key: const ValueKey('ai-preview-discard'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Πέτα το')),
          ],
        ),
      ) ==
      true;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final byId = {for (final d in [...food.dishes, ...newDishes]) d.id: d};
    final newIds = {for (final d in newDishes) d.id};
    final g = HealthStore.shared?.goals;
    final order = [for (final m in Meal.values) if (plan.meals?.contains(m) ?? true) m];
    final share = order.fold(0.0, (a, m) => a + mealShare[m]!);

    Widget day(int i) {
      var kcal = 0, protein = 0.0;
      final present = <Meal>{};
      for (final s in plan.days[i]) {
        final t = plannedTotals(food, byId[s.dishId], s);
        present.add(s.meal);
        if (t == null) continue;
        kcal += t.shownKcal;
        protein += t.protein;
      }
      final target = g == null ? null : g.kcal * present.fold(0.0, (a, m) => a + (mealShare[m] ?? 0)) / (share <= 0 ? 1 : share);
      final missing = [for (final m in plan.meals ?? const <Meal>[]) if (!present.contains(m)) m];
      return AppCard(
        key: ValueKey('ai-preview-day-$i'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 12, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.end, children: [
            Text(shortDayDate(plan.dayAt(i)), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
            Text(
              '${thousands(kcal)}${target == null ? '' : ' / ${thousands(target)}'} kcal${dotJoin}πρωτεΐνη ${protein.round()} g',
              style: TextStyle(fontSize: 13.5, color: c.textSecondary),
            ),
          ]),
          for (final s in plan.days[i])
            Builder(builder: (context) {
              final d = byId[s.dishId];
              final t = plannedTotals(food, d, s);
              final isNew = newIds.contains(s.dishId);
              return Semantics(
                button: d != null,
                hint: d == null ? null : 'Δες τα υλικά',
                child: InkWell(
                  key: ValueKey('ai-preview-slot-$i-${s.meal.name}'),
                  onTap: d == null ? null : () => showDishSheet(context, food, d, s.kcal),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(text: d?.name ?? '—'),
                            if (isNew) TextSpan(text: '  ΝΕΟ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c.food)),
                            if (s.locked) const TextSpan(text: '  🔒'),
                          ]),
                          style: TextStyle(fontSize: 15, height: 1.3, color: c.text),
                        ),
                        Text(
                          [
                            mealLabel(s.meal),
                            if (t != null) '${thousands(t.shownKcal)} kcal',
                            if (t != null) 'πρωτεΐνη ${t.protein.round()} g',
                          ].join(dotJoin),
                          style: TextStyle(fontSize: 13.5, height: 1.35, color: c.textSecondary),
                        ),
                      ]),
                    ),
                  ),
                ),
              );
            }),
          for (final m in missing)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('${mealLabel(m)}${dotJoin}χωρίς φαγητό (το συμπληρώνεις μετά στην εβδομάδα)',
                  style: TextStyle(fontSize: 14, height: 1.35, color: c.warn)),
            ),
        ]),
      );
    }

    final header = <Widget>[
      if (replaces != null && replaces!.from != plan.from)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Το τωρινό πρόγραμμα (${shortDayDate(replaces!.start)} – ${shortDayDate(replaces!.end)}) αντικαθίσταται. Ό,τι '
            'έχεις γράψει στο ημερολόγιο μένει.',
            key: const ValueKey('ai-preview-replaces'),
            style: TextStyle(fontSize: 14.5, height: 1.4, fontWeight: FontWeight.w600, color: c.warn),
          ),
        ),
      Text(
        newDishes.isEmpty
            ? 'Όλα από τη βιβλιοθήκη σου. Οι αριθμοί είναι από τη βάση της εφαρμογής.'
            : '${countText(newDishes.length, 'νέο φαγητό', 'νέα φαγητά')} (σημειωμένα «ΝΕΟ»): μπαίνουν στη βιβλιοθήκη σου μόνο '
                'αν πεις «Ναι». Πάτα ένα φαγητό για υλικά και συνταγή. Οι αριθμοί είναι από τη βάση της εφαρμογής.',
        style: TextStyle(fontSize: 14.5, height: 1.4, color: c.textSecondary),
      ),
      if (notes.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Να ξέρεις:', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: c.warn)),
        for (final n in notes) Text('• $n', style: TextStyle(fontSize: 14, height: 1.4, color: c.text)),
      ],
    ];

    return FoodTheme(
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final nav = Navigator.of(context);
          if (await _confirmDiscard(context)) nav.pop(false);
        },
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
                        onPressed: () async {
                          final nav = Navigator.of(context);
                          if (await _confirmDiscard(context)) nav.pop(false);
                        },
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
          body: LayoutBuilder(builder: (context, box) {
            final two = box.maxWidth >= 900;
            final days = [for (var i = 0; i < plan.days.length; i++) day(i)];
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: two ? 1200 : 720),
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                  ...header,
                  const SizedBox(height: 10),
                  if (two)
                    for (var i = 0; i < days.length; i += 2)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: IntrinsicHeight(
                          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Expanded(child: days[i]),
                            const SizedBox(width: 12),
                            Expanded(child: i + 1 < days.length ? days[i + 1] : const SizedBox.shrink()),
                          ]),
                        ),
                      )
                  else
                    for (final d in days) Padding(padding: const EdgeInsets.only(bottom: 10), child: d),
                ]),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// Τα υλικά (ωμά) και η συνταγή ενός φαγητού, μόνο για ανάγνωση (U-14). Κατσαρόλα: όλη η κατσαρόλα· αλλιώς η μερίδα σου.
Future<void> showDishSheet(BuildContext context, FoodStore food, Dish d, double? kcal) {
  final r = recipeOf(d);
  final items = d.kind == DishKind.pot ? d.items : (plannedRaw(food, d, kcal) ?? d.items);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    routeSettings: const RouteSettings(name: 'AI υλικά φαγητού'),
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (ctx) {
      final c = Aigaio.of(ctx);
      return FoodTheme(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          builder: (ctx, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
            Text(d.name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.text)),
            const SizedBox(height: 4),
            Text(
              [
                planInfoOf(d)?.cook == CookWay.none ? 'Χωρίς μαγείρεμα' : 'Μαγείρεμα',
                if (r?.minutes != null) '${r!.minutes} λεπτά',
                if (d.kind == DishKind.pot) 'κατσαρόλα για όλο το σπίτι',
              ].join(dotJoin),
              style: TextStyle(fontSize: 13.5, color: c.textSecondary),
            ),
            const SizedBox(height: 12),
            Text(d.kind == DishKind.pot ? 'Υλικά (όλη η κατσαρόλα, ωμά)' : 'Υλικά της μερίδας σου (ωμά)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
            for (final i in items)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${food.itemFood(i)?.name ?? i.name}$dotJoin${gramsText(i.amount)} ${food.itemFood(i)?.unit ?? 'g'}',
                    style: TextStyle(fontSize: 14.5, height: 1.35, color: c.text)),
              ),
            if (r != null && !r.isEmpty) ...[
              const SizedBox(height: 14),
              RecipeSteps(recipe: r),
            ],
          ]),
        ),
      );
    },
  );
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
    isScrollControlled: true,
    routeSettings: const RouteSettings(name: 'Άλλαξέ το με AI'),
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (ctx) => _SwapReasonSheet(food: food, dish: cur),
  );
  if (why == null || !context.mounted) return;
  if (!await ensureAiReady(context, b) || !context.mounted) return;
  final text = ValueNotifier('Το AI ψάχνει ανάλογο φαγητό…');
  ({AiSwapResult? value, bool capped, bool crashed}) run;
  try {
    run = await runWithProgress<AiSwapResult>(
      context,
      text,
      (cancel) => aiSwapSlot(
        call: cancel.wrap(b.call),
        food: food,
        kitchen: Kitchen.fromJson(HealthStore.shared?.prefs.kitchen),
        w: w0,
        day: day,
        index: index,
        reason: why.$1,
        missingId: why.$2,
        now: (clock ?? DateTime.now)().millisecondsSinceEpoch,
        newId: FoodStore.newDishId,
        limits: HealthStore.shared?.goals == null ? null : aiTargetsOf(HealthStore.shared!.goals!),
        onAttempt: (a) {
          if (a > 1 && !_isDisposed(text)) {
            text.value = 'Το AI ψάχνει ανάλογο φαγητό…\nΔιορθώνει την απάντησή του (προσπάθεια $a από ${aiMaxRetries + 1}).';
          }
        },
      ),
      cap: const Duration(minutes: 6),
    );
  } finally {
    _dispose(text);
  }
  if (!context.mounted) return;
  final r = run.value;
  if (r?.fail == AiFail.cancelled || (r == null && !run.capped && !run.crashed)) return;
  if (r == null || r.fail != null || r.dish == null) {
    final msg = run.capped
        ? 'Πήρε πολύ ώρα. Δοκίμασε ξανά σε λίγο.'
        : run.crashed || r == null
            ? 'Κάτι πήγε στραβά. Δοκίμασε ξανά.'
            : r.fail != null
                ? aiErrorText(r.fail!)
                : (r.errors.isEmpty ? 'Δεν βρέθηκε ανάλογο φαγητό.' : r.errors.first);
    final details = r == null || r.fail != null ? const <String>[] : r.errors.skip(1).toList();
    await showDialog<void>(
      context: context,
      routeSettings: const RouteSettings(name: 'AI δεν βρέθηκε αλλαγή'),
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: const Text('Δεν βρέθηκε αλλαγή'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(msg),
          if (details.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Λεπτομέρειες'),
              children: [for (final e in details) Align(alignment: Alignment.centerLeft, child: Text('• $e'))],
            ),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Εντάξει'))],
      ),
    );
    return;
  }
  final d = r.dish!;
  final k = r.kcal!;
  final oldT = plannedTotals(food, cur, s0)!;
  final newT = plannedTotals(food, d, PlanSlot(meal: s0.meal, dishId: d.id, kcal: k))!;
  final warnings = swapWarnings(food, cur, s0, d, k);
  // Η μέρα μετά την αλλαγή (θερμίδες, πρωτεΐνη, κορεσμένα), από τη βάση.
  final g = HealthStore.shared?.goals;
  final after = applySwap(w0, day, index, d, k);
  var dayKcal = 0, dayProtein = 0.0, daySat = 0.0;
  for (final s in after.days[day]) {
    if (s.state == SlotState.skip) continue;
    final t = plannedTotals(food, s.dishId == d.id ? d : food.dishById(s.dishId), s);
    if (t == null) continue;
    dayKcal += t.shownKcal;
    dayProtein += t.protein;
    daySat += t.satFat;
  }
  final elsewhere = [
    for (var i = 0; i < w0.days.length; i++)
      for (var j = 0; j < w0.days[i].length; j++)
        if ((i != day || j != index) && w0.days[i][j].dishId == cur.id && slotStateNow(food, w0, i, w0.days[i][j]) == SlotState.open)
          shortDayDate(w0.dayAt(i)),
  ];
  if (!context.mounted) return;
  final yes = await showDialog<bool>(
    context: context,
    routeSettings: const RouteSettings(name: 'Αλλαγή γεύματος'),
    builder: (ctx) => AlertDialog(
      scrollable: true,
      title: Text(d.name),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          '${r.isNew ? 'Νέο φαγητό· μπαίνει και στη βιβλιοθήκη σου.\n\n' : ''}'
          // Έλεγχος 21/11 (K7B-03): δεκαδικά με κόμμα, όπως παντού (πριν «4.2 g»).
          'Αντί για «${cur.name}».\n'
          'Θερμίδες: ${thousands(oldT.shownKcal)} → ${thousands(newT.shownKcal)} kcal\n'
          'Πρωτεΐνη: ${oldT.protein.round()} → ${newT.protein.round()} g\n'
          'Κορεσμένα: ${dec(oldT.satFat)} → ${dec(newT.satFat)} g\n'
          'Αλάτι: ${dec(oldT.salt)} → ${dec(newT.salt)} g'
          '${g == null ? '' : '\n\nΗ μέρα μετά: ${thousands(dayKcal)} / ${thousands(g.kcal)} kcal, πρωτεΐνη ${dayProtein.round()} / '
              '${g.protein} g, κορεσμένα ${dec(daySat)} / ${dec(satLimitShown(g.kcal, g.satPct))} g.'}'
          '\n\nΑπό τη βάση της εφαρμογής.',
          key: const ValueKey('ai-swap-summary'),
        ),
        if (warnings.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final w in warnings) Text('• $w', style: TextStyle(color: Aigaio.of(ctx).warn, height: 1.35)),
        ],
        if (elsewhere.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Το «${cur.name}» είναι και ${elsewhere.join(', ')}: εκεί μένει (άλλαξέ το κι εκεί αν θέλεις).'),
        ],
        if (r.isNew)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () => showDishSheet(ctx, food, d, k), child: const Text('Δες τη συνταγή')),
          ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Όχι')),
        FilledButton(key: const ValueKey('ai-swap-yes'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Ναι, άλλαξέ το')),
      ],
    ),
  );
  if (yes != true) return;
  // Το πρόγραμμα ή η θέση άλλαξε στο μεταξύ; Τότε τίποτα (U-19).
  final w1 = food.week;
  final s1 = w1 == null || w1.from != w0.from || day >= w1.days.length || index >= w1.days[day].length ? null : w1.days[day][index];
  if (w1 == null || s1 == null || s1.dishId != s0.dishId || s1.kcal != s0.kcal || slotStateNow(food, w1, day, s1) != SlotState.open) {
    messenger.showSnackBar(const SnackBar(content: Text('Το πρόγραμμα άλλαξε στο μεταξύ· δεν έγινε αλλαγή.')));
    return;
  }
  final ok = await food.saveDishesAndWeek(r.isNew ? [d] : const [], applySwap(w1, day, index, d, k));
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
        Text('Το AI βρίσκει ανάλογο: ίδιες περίπου θερμίδες, όση πρωτεΐνη, όχι περισσότερα κορεσμένα, μόνο με όσα σου αρέσουν.',
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
            enabled: items.isNotEmpty,
            onTap: () => setState(() => _pickMissing = true),
          ),
          ListTile(
            key: const ValueKey('swap-appetite'),
            leading: const Icon(Icons.sentiment_neutral_rounded),
            title: const Text('Δεν μου κάνει όρεξη'),
            onTap: () => Navigator.pop(context, (SwapReason.appetite, null)),
          ),
        ] else ...[
          for (final f in items)
            ListTile(
              key: ValueKey('swap-missing-${f.id}'),
              title: Text(f.name),
              onTap: () => Navigator.pop(context, (SwapReason.missing, f.id)),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('swap-missing-back'),
              onPressed: () => setState(() => _pickMissing = false),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Πίσω'),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Μετά το «Έφαγα κάτι άλλο» (μόνο για σήμερα, μόνο αν γράφτηκε κάτι): προτείνει τις νέες μερίδες των γευμάτων που
/// έρχονται μετά το [after] στη μέρα (κανόνες, χωρίς AI).
Future<void> offerRebalance(BuildContext context, FoodStore food, int day, {required Meal after, DateTime Function()? clock}) async {
  final w = food.week;
  final g = HealthStore.shared?.goals;
  if (w == null || g == null || day >= w.days.length) return;
  final now = (clock ?? DateTime.now)();
  if (!sameDay(w.dayAt(day), now)) return;
  final t = Totals(food.entriesFor(now));
  final r = rebalanceDay(food, w, day, eaten: t.kcal, eatenProtein: t.protein, target: g.kcal.toDouble(), after: after, now: now);
  if (r == null || !context.mounted) return;
  final over = r.dayKcal > g.kcal * 1.05;
  final yes = await showDialog<bool>(
    context: context,
    routeSettings: const RouteSettings(name: 'Υπόλοιπα γεύματα'),
    builder: (ctx) => AlertDialog(
      scrollable: true,
      title: const Text('Να προσαρμοστούν τα επόμενα γεύματα;'),
      content: Text(
        'Ως τώρα σήμερα: ${thousands(t.shownKcal)} από ${thousands(g.kcal)} kcal.\n\n'
        '${[for (final (m, n, a, b) in r.changes) '${mealLabel(m)}$dotJoin$n: ${thousands(a)} → ${thousands(b)} kcal'].join('\n')}\n\n'
        'Η μέρα θα κλείσει στις ${thousands(r.dayKcal)} kcal (στόχος ${thousands(g.kcal)}), πρωτεΐνη '
        '${r.proteinBefore.round()} → ${r.proteinAfter.round()} g (στόχος ${g.protein}).'
        '${over ? '\n\nΟι μερίδες είναι ήδη στο ελάχιστο· η μέρα θα κλείσει πάνω από τον στόχο.' : ''}',
        key: const ValueKey('rebalance-text'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Όχι')),
        FilledButton(key: const ValueKey('rebalance-yes'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Ναι')),
      ],
    ),
  );
  if (yes != true || !context.mounted) return;
  // Μόνο αν το πρόγραμμα δεν άλλαξε στο μεταξύ.
  if (!identical(food.week, w)) return;
  final messenger = ScaffoldMessenger.of(context);
  final ok = await food.saveWeek(r.plan);
  messenger.showSnackBar(SnackBar(
    persist: false,
    content: Text(ok ? 'Οι μερίδες άλλαξαν.' : (food.saveError ?? 'Δεν αποθηκεύτηκε. Δοκίμασε ξανά.')),
  ));
}

/// «Μου άρεσε» / «Δεν μου άρεσε» για ένα φαγητό (η βαθμολογία πάει στο AI και στο «Φτιάξε πρόγραμμα»). Ξανά το ίδιο:
/// σβήνει.
Future<void> rateDish(BuildContext context, FoodStore food, Dish d, int r) async {
  final messenger = ScaffoldMessenger.of(context);
  final now = food.dishById(d.id) ?? d;
  final next = dishRating(now) == r ? 0 : r;
  final ok = await food.saveDish(withRating(now, next));
  messenger.showSnackBar(SnackBar(
    persist: false,
    content: Text(!ok
        ? (food.saveError ?? 'Δεν αποθηκεύτηκε.')
        : next == 1
            ? 'Σημειώθηκε: σου άρεσε. Θα μπαίνει πιο συχνά.'
            : next == -1
                ? 'Δεν σου άρεσε: δεν θα ξαναμπεί σε πρόγραμμα. Αλλάζει από τη βιβλιοθήκη.'
                : 'Η βαθμολογία σβήστηκε.'),
  ));
}

/// Τι θα χρησιμοποιήσει το AI (U-10): μου αρέσουν, βασικά κουζίνας, φαγητά της βιβλιοθήκης που μπαίνουν.
class AiReadyCard extends StatelessWidget {
  const AiReadyCard({super.key, required this.food});
  final FoodStore food;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return ListenableBuilder(
      listenable: food,
      builder: (context, _) {
        final l = food.likes;
        final allowed = aiAllowedIds(food);
        final lib = libraryDishes(food.dishes).where((d) => planInfoOf(d)!.cook != CookWay.out).length;
        final usable = aiLibrary(food, allowed).length;
        final warn = l.like.isEmpty || l.staple.isEmpty;
        return AppCard(
          key: const ValueKey('ai-ready-card'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              'Μου αρέσουν: ${l.like.length}${dotJoin}Βασικά κουζίνας: ${l.staple.length}${dotJoin}'
              'Από τη βιβλιοθήκη μπαίνουν $usable από $lib φαγητά.',
              style: TextStyle(fontSize: 14, height: 1.4, color: c.text),
            ),
            if (warn) ...[
              const SizedBox(height: 6),
              Text(
                l.like.isEmpty
                    ? 'Πρώτα διάλεξε τι σου αρέσει: μόνο από αυτά φτιάχνει το AI.'
                    : 'Τσέκαρε τουλάχιστον λάδι και αλάτι στα βασικά κουζίνας, αλλιώς οι συνταγές βγαίνουν χωρίς αυτά.',
                key: const ValueKey('ai-ready-warn'),
                style: TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w600, color: c.warn),
              ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('ai-ready-likes'),
                onPressed: () => Navigator.of(context).push(FoodLikesScreen.route(food)),
                icon: const Icon(Icons.favorite_border_rounded, size: 20),
                label: const Text('Τι μου αρέσει'),
              ),
            ),
          ]),
        );
      },
    );
  }
}
