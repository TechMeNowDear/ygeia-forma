import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data.dart' show HealthStore;
import '../food/dishes.dart';
import '../food/food_model.dart';
import '../food/food_store.dart';
import '../food/library.dart';
import '../food/recipe.dart' show recipeOf;
import '../food/week.dart';
import '../food/week_auto.dart';
import '../food/week_calc.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';
import '../ai/ai_bridge.dart' show AiBridge;
import 'ai_settings.dart' show mainAiBridge;
import 'ai_week.dart';
import 'dishes.dart';
import 'food_add.dart';
import 'nutrition.dart' show mealIcon;
import 'privacy_page.dart' show copySensitive;
import 'recipes.dart' show CookScreen, targetsOf;

// ---------------------------------------------------------------------------
// Πρόγραμμα εβδομάδας (15/11, lib/food/week.dart). Στο ημερολόγιο μπαίνει μόνο ό,τι πατήσεις «Το έφαγα».
// ---------------------------------------------------------------------------

/// Οι ενέργειες σε ένα γεύμα του προγράμματος. Διαβάζουν πάντα το τρέχον πρόγραμμα ([FoodStore.week]): αν άλλαξε στο
/// μεταξύ (π.χ. νέα επικόλληση), δεν γράφουν τίποτα.
class SlotActions {
  SlotActions(this.context, this.food, this.day, this.index, {this.clock});
  final BuildContext context;
  final FoodStore food;
  final int day;
  final int index;
  final DateTime Function()? clock;

  DateTime get _now => (clock ?? DateTime.now)();

  PlanSlot? get _slot {
    final w = food.week;
    return w == null || day >= w.days.length || index >= w.days[day].length ? null : w.days[day][index];
  }

  Future<bool> _set(PlanSlot s) async {
    final w = food.week;
    if (w == null) return false;
    return food.saveWeek(w.withSlot(day, index, s));
  }

  /// «Το έφαγα»: με ένα πάτημα όταν η μερίδα βγαίνει (πιάτο, μερίδες, κατσαρόλα ζυγισμένη)· αλλιώς ανοίγει το φαγητό με
  /// τη μερίδα του προγράμματος.
  Future<void> ate() async {
    final s = _slot, w = food.week;
    if (s == null || w == null) return;
    final d = food.dishById(s.dishId);
    if (d == null) return change();
    final messenger = ScaffoldMessenger.of(context);
    final on = w.dayAt(day);
    final quick = slotLog(food, d, s, _now);
    List<LogEntry>? out;
    if (quick != null) {
      out = await food.logDish(d, quick.amounts, meal: s.meal, qty: quick.qty, plate: quick.plate, on: on, now: _now);
    } else {
      final r = await openDishLogSheet(context, food, d, meal: s.meal, now: () => _now, targetKcal: s.kcal);
      if (r == null || !context.mounted) return;
      if (r.edit) {
        await openDishEditor(context, food, dish: d);
        return;
      }
      out = await food.logDish(d, r.amounts, meal: r.meal, qty: r.qty, plate: r.plate, batch: r.batch, on: on, now: _now, est: r.est);
    }
    if (out == null || out.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(food.saveError ?? 'Δεν γράφτηκε: ${d.name}. Δοκίμασε ξανά.')));
      return;
    }
    final grp = out.first.dish?.grp;
    await _set(s.copyWith(state: SlotState.ate, grp: grp));
    final kcal = Totals(out).shownKcal;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Γράφτηκε: ${d.name}$dotJoin${thousands(kcal)} kcal'),
        persist: false,
        duration: undoSnackBarDuration,
        action: SnackBarAction(
          label: 'Αναίρεση',
          onPressed: () async {
            if (await food.removeGroup(out!)) {
              // Το φαγητό όπως ήταν, αλλά με τη βαθμολογία που ίσως δόθηκε στο μεταξύ (I-12).
              final cur = food.dishById(d.id);
              if (cur != null) await food.saveDish(withRating(d, dishRating(cur)));
              final now = _slot;
              if (now != null && now.grp == grp) await _set(now.copyWith(state: SlotState.open, clearGrp: true));
            }
          },
        ),
      ));
  }

  /// «Αναίρεση: δεν το έφαγα τελικά»: σβήνει την καταγραφή του από το ημερολόγιο και ξανανοίγει τη θέση.
  Future<void> undoAte() async {
    final s = _slot, w = food.week;
    if (s == null || w == null) return;
    final g = s.grp;
    final group = g == null ? const <LogEntry>[] : [for (final e in food.entriesFor(w.dayAt(day))) if (e.dish?.grp == g) e];
    if (group.isNotEmpty && !await food.removeGroup(group)) return;
    await _set(s.copyWith(state: SlotState.open, clearGrp: true));
  }

  Future<void> skip() async {
    final s = _slot;
    if (s != null) await _set(s.copyWith(state: SlotState.skip, clearGrp: true));
  }

  Future<void> reopen() async {
    final s = _slot;
    if (s != null) await _set(s.copyWith(state: SlotState.open, clearGrp: true));
  }

  /// «Έφαγα κάτι άλλο»: σημειώνεται, και ανοίγει η κανονική καταχώριση για εκείνο το γεύμα και τη μέρα.
  Future<void> other() async {
    final s = _slot, w = food.week;
    if (s == null || w == null) return;
    await _set(s.copyWith(state: SlotState.other, clearGrp: true));
    final on = w.dayAt(day);
    final before = {for (final e in food.entriesFor(on)) e.id};
    if (context.mounted) await openAddFood(context, food, meal: s.meal, day: on);
    // 19/11: τα επόμενα γεύματα της μέρας (κανόνες, χωρίς AI· μόνο για σήμερα, μόνο αν έγραψες κάτι, μόνο με «Ναι»).
    final wrote = food.entriesFor(on).any((e) => !before.contains(e.id));
    if (wrote && context.mounted) await offerRebalance(context, food, day, after: s.meal, clock: clock);
  }

  /// «Άλλαξέ το με AI» (19/11): ανάλογο φαγητό, μόνο με «Ναι».
  Future<void> aiChange() => aiSwapFlow(context, food, day, index, clock: clock);

  /// «Άλλαξέ το»: άλλο φαγητό στην ίδια θέση, με τις ίδιες θερμίδες.
  Future<void> change() async {
    final s = _slot;
    if (s == null) return;
    final d = await Navigator.of(context).push<Dish>(DishesScreen.route(food, pick: true));
    if (d == null) return;
    final now = _slot;
    if (now != null) await _set(now.copyWith(dishId: d.id, state: SlotState.open, clearGrp: true));
  }

  Future<void> toggleLock() async {
    final s = _slot;
    if (s != null) await _set(s.copyWith(locked: !s.locked));
  }
}

/// Ένα γεύμα του προγράμματος: τι είναι, πόσο, και «Το έφαγα».
class SlotRow extends StatelessWidget {
  const SlotRow({super.key, required this.food, required this.plan, required this.day, required this.index, this.lock = false, this.clock});
  final FoodStore food;
  final WeekPlan plan;
  final int day;
  final int index;

  /// Δείχνει και το κλείδωμα (στην οθόνη της εβδομάδας).
  final bool lock;
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final s = plan.days[day][index];
    final d = food.dishById(s.dishId);
    final now = (clock ?? DateTime.now)();
    final state = slotStateNow(food, plan, day, s);
    final t = plannedTotals(food, d, s);
    final a = SlotActions(context, food, day, index, clock: clock);
    final parts = <String>[
      mealLabel(s.meal),
      if (t != null) '${thousands(t.shownKcal)} kcal',
      if (t != null) 'πρωτεΐνη ${t.protein.round()} g',
    ];
    String? hint;
    if (d != null && state == SlotState.open) {
      if (food.missingItems(d.items).isNotEmpty) {
        hint = 'Λείπει υλικό: άλλαξε το φαγητό';
      } else if (d.kind == DishKind.pot) {
        final b = freshBatch(d, now);
        final g = b == null ? null : potPortion(food, d, b, s.kcal);
        hint = g != null
            ? 'Η μερίδα σου: ${thousands(g.round())} g'
            : 'Μαγείρεψε και ζύγισε όλο το έτοιμο φαγητό· μετά βγαίνει η μερίδα σου';
      } else if (d.kind == DishKind.plate && s.kcal != null) {
        final l = slotLog(food, d, s, now);
        if (l?.plate case final p?) {
          hint = [
            for (var k = 0; k < d.items.length && k < p.length; k++)
              if (p[k] > 0) '${food.itemFood(d.items[k])?.name ?? d.items[k].name} ${gramsText(p[k])} g',
          ].join(dotJoin);
        }
      } else if (d.kind == DishKind.portions) {
        final l = slotLog(food, d, s, now);
        if (l != null) hint = dishQtyText(DishKind.portions, l.qty);
      }
    }
    final info = d == null ? null : planInfoOf(d);
    final recipe = d == null ? null : recipeOf(d);
    final (icon, color) = switch (state) {
      SlotState.ate => (Icons.check_circle_rounded, c.food),
      SlotState.skip => (Icons.remove_circle_outline_rounded, c.textTertiary),
      SlotState.other => (Icons.swap_horiz_rounded, c.textTertiary),
      SlotState.open => (mealIcon(s.meal), c.food),
    };
    final done = state != SlotState.open;
    // Μέρα που δεν ήρθε ακόμα: μόνο αλλαγή φαγητού (τίποτα δεν γράφεται στο ημερολόγιο του μέλλοντος).
    final future = dayOf(plan.dayAt(day)).isAfter(dayOf(now));
    return Padding(
      key: ValueKey('slot-$day-$index'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 24, color: color)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              d?.name ?? 'Το φαγητό δεν υπάρχει πια',
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: d == null ? c.warn : (done ? c.textSecondary : c.text),
                decoration: state == SlotState.skip || state == SlotState.other ? TextDecoration.lineThrough : null,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              state == SlotState.skip
                  ? '${mealLabel(s.meal)}${dotJoin}Δεν το έφαγες'
                  : state == SlotState.other
                      ? '${mealLabel(s.meal)}${dotJoin}Έφαγες κάτι άλλο'
                      : parts.join(dotJoin),
              style: TextStyle(fontSize: 13.5, height: 1.35, color: c.textSecondary),
            ),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(hint, key: ValueKey('slot-hint-$day-$index'),
                    style: TextStyle(fontSize: 14, height: 1.35, fontWeight: FontWeight.w600, color: c.text)),
              ),
            if (state == SlotState.open && d != null && !future)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: FilledButton.tonalIcon(
                  key: ValueKey('slot-ate-$day-$index'),
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: food.loaded && food.dishesRead ? a.ate : null,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Το έφαγα'),
                ),
              ),
          ]),
        ),
        if (lock)
          IconButton(
            key: ValueKey('slot-lock-$day-$index'),
            tooltip: s.locked ? 'Ξεκλείδωμα' : 'Κλείδωμα: μένει όταν ξαναφτιάχνεται η εβδομάδα',
            onPressed: a.toggleLock,
            icon: Icon(s.locked ? Icons.lock_rounded : Icons.lock_open_rounded, size: 20, color: s.locked ? c.food : c.textTertiary),
          ),
        PopupMenuButton<String>(
          key: ValueKey('slot-menu-$day-$index'),
          tooltip: 'Περισσότερα',
          icon: Icon(Icons.more_vert_rounded, color: c.textSecondary),
          onSelected: (v) => switch (v) {
            'change' => a.change(),
            'aiswap' => a.aiChange(),
            'like' => rateDish(context, food, d!, 1),
            'dislike' => rateDish(context, food, d!, -1),
            'other' => a.other(),
            'skip' => a.skip(),
            'reopen' => a.reopen(),
            'undo' => a.undoAte(),
            'recipe' => Navigator.of(context).push(CookScreen.route(d!, recipe!, food)),
            'order' => showOrderText(context, d!.name, info!.order!),
            _ => null,
          },
          itemBuilder: (_) => [
            if (recipe != null) const PopupMenuItem(value: 'recipe', child: Text('Η συνταγή')),
            if (info?.order != null) const PopupMenuItem(value: 'order', child: Text('Τι να ζητήσεις όταν το παραγγέλνεις')),
            if (state == SlotState.open) ...[
              const PopupMenuItem(value: 'change', child: Text('Άλλαξέ το')),
              if (d != null) const PopupMenuItem(value: 'aiswap', child: Text('Άλλαξέ το με AI')),
              if (!future) const PopupMenuItem(value: 'other', child: Text('Έφαγα κάτι άλλο')),
              if (!future) const PopupMenuItem(value: 'skip', child: Text('Δεν το έφαγα')),
            ],
            if (state == SlotState.ate) const PopupMenuItem(value: 'undo', child: Text('Αναίρεση: σβήνεται από το ημερολόγιο')),
            if (state == SlotState.ate && d != null) ...[
              CheckedPopupMenuItem(value: 'like', checked: dishRating(d) == 1, child: const Text('Μου άρεσε')),
              CheckedPopupMenuItem(value: 'dislike', checked: dishRating(d) == -1, child: const Text('Δεν μου άρεσε')),
            ],
            if (state == SlotState.skip || state == SlotState.other) const PopupMenuItem(value: 'reopen', child: Text('Ξανά στο πρόγραμμα')),
          ],
        ),
      ]),
    );
  }
}

/// Η κάρτα «Πρόγραμμα» στο ημερολόγιο, για τη μέρα που φαίνεται (μόνο αν το πρόγραμμα την έχει).
class PlanDayCard extends StatelessWidget {
  const PlanDayCard({super.key, required this.food, required this.day, this.clock});
  final FoodStore food;
  final DateTime day;
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final w = food.week;
    final i = w?.indexOf(day) ?? -1;
    if (w == null || i < 0 || w.days[i].isEmpty) return const SizedBox.shrink();
    final open = [for (var k = 0; k < w.days[i].length; k++) if (slotStateNow(food, w, i, w.days[i][k]) == SlotState.open) k];
    return AppCard(
      key: const ValueKey('plan-day-card'),
      padding: const EdgeInsets.fromLTRB(16, 14, 4, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.event_note_rounded, color: c.food, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(open.isEmpty ? 'Πρόγραμμα: όλα σημειωμένα' : 'Πρόγραμμα',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
          ),
          TextButton(
            key: const ValueKey('plan-open-week'),
            onPressed: () => Navigator.of(context).push(WeekPlanScreen.route(food)),
            child: const Text('Η εβδομάδα ›'),
          ),
        ]),
        for (var k = 0; k < w.days[i].length; k++) SlotRow(food: food, plan: w, day: i, index: k, clock: clock),
      ]),
    );
  }
}

/// Η εβδομάδα: όλες οι μέρες, κλείδωμα, επικόλληση νέου προγράμματος και οδηγίες για τον βοηθό.
class WeekPlanScreen extends StatefulWidget {
  const WeekPlanScreen({super.key, required this.food, this.clock});
  final FoodStore food;
  final DateTime Function()? clock;

  static Route<void> route(FoodStore food) => MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'Πρόγραμμα εβδομάδας'),
        builder: (_) => WeekPlanScreen(food: food),
      );

  @override
  State<WeekPlanScreen> createState() => _WeekPlanScreenState();
}

class _WeekPlanScreenState extends State<WeekPlanScreen> {
  bool _copied = false;

  /// Τρέχει ήδη το AI (U-2: ένα πάτημα τη φορά).
  bool _aiBusy = false;

  /// Συνδεδεμένο το AI (για το ποιο κουμπί είναι το κύριο, U-24).
  bool _aiReady = false;

  AiBridge get _bridge => mainAiBridge;

  @override
  void initState() {
    super.initState();
    final b = _bridge;
    (b.loaded ? Future.value(true) : b.load()).then((_) {
      if (mounted) setState(() => _aiReady = b.ready && b.okDay != null);
    });
  }
  List<String>? _errors;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  Future<void> _copy() async {
    final g = HealthStore.shared?.goals;
    await copySensitive(weekPrompt(
      food: widget.food,
      from: nextMonday(_now),
      targets: targetsOf(g),
      legumesWeek: g?.legumesWeek,
      fishWeek: g?.fishWeek,
    ));
    if (mounted) setState(() => _copied = true);
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    await read(d?.text ?? '');
  }

  /// Διαβάζει ένα πρόγραμμα· αν είναι σωστό, ρωτά πριν αντικαταστήσει το υπάρχον και το αποθηκεύει.
  Future<void> read(String text) async {
    final food = widget.food;
    final p = parseWeek(text, food.dishes, now: _now.millisecondsSinceEpoch);
    if (p.plan == null) {
      setState(() => _errors = p.errors);
      return;
    }
    setState(() => _errors = null);
    final old = food.week;
    if (old != null) {
      final yes = await showDialog<bool>(
        context: context,
        routeSettings: const RouteSettings(name: 'Νέο πρόγραμμα'),
        builder: (ctx) => AlertDialog(
          title: const Text('Νέο πρόγραμμα;'),
          content: Text('Το πρόγραμμα από ${shortDayDate(old.start)} γίνεται αυτό από ${shortDayDate(p.plan!.start)}. '
              'Ό,τι έχεις ήδη γράψει στο ημερολόγιο μένει όπως είναι.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Άκυρο')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ναι, το νέο')),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    final ok = await food.saveWeek(keepDone(p.plan!, old));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Το πρόγραμμα αποθηκεύτηκε.' : (food.saveError ?? 'Δεν αποθηκεύτηκε. Δοκίμασε ξανά.')),
    ));
  }

  /// Οι σημειώσεις του τελευταίου αυτόματου προγράμματος (ό,τι δεν βγήκε όπως ζητούν οι κανόνες).
  List<String>? _autoNotes;
  // Κάθε «Φτιάξε»/«Ξαναφτιάξ’ το» δίνει άλλη εβδομάδα, και μετά από νέο άνοιγμα της οθόνης (έλεγχος 16/11).
  int _seed = DateTime.now().millisecondsSinceEpoch % 100000;

  /// «Φτιάξε πρόγραμμα» (16/11): με κανόνες, χωρίς AI. Ρωτά από πότε και ποια γεύματα.
  Future<void> _auto() async {
    final g = HealthStore.shared?.goals;
    if (g == null) {
      setState(() => _errors = [noGoalsText]);
      return;
    }
    final choice = await showModalBottomSheet<({DateTime from, List<Meal> meals})>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      routeSettings: const RouteSettings(name: 'Φτιάξε πρόγραμμα'),
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => AutoWeekSheet(now: _now),
    );
    if (choice == null || !mounted) return;
    await _generate(choice.from, choice.meals, keep: null);
  }

  /// «Φτιάξ’ το με AI» (19/11): μόνο από ό,τι σου αρέσει· προεπισκόπηση και «Ναι» πριν αποθηκευτεί.
  Future<void> _ai({WeekPlan? again}) async {
    if (_aiBusy) return;
    setState(() => _aiBusy = true);
    try {
      await _aiRun(again: again);
    } finally {
      if (mounted) {
        setState(() {
          _aiBusy = false;
          _aiReady = _bridge.ready && _bridge.okDay != null;
        });
      }
    }
  }

  Future<void> _aiRun({WeekPlan? again}) async {
    DateTime from;
    List<Meal> meals;
    if (again != null) {
      from = again.start;
      meals = again.meals ?? [for (final m in Meal.values) if (again.days.any((d) => d.any((s) => s.meal == m))) m];
    } else {
      if (HealthStore.shared?.goals == null) {
        setState(() => _errors = [noGoalsText]);
        return;
      }
      final choice = await showModalBottomSheet<({DateTime from, List<Meal> meals})>(
        context: context,
        showDragHandle: true,
        useSafeArea: true,
        isScrollControlled: true,
        routeSettings: const RouteSettings(name: 'Φτιάξ’ το με AI'),
        constraints: const BoxConstraints(maxWidth: 560),
        builder: (_) => AutoWeekSheet(now: _now, ai: true, food: widget.food),
      );
      if (choice == null || !mounted) return;
      from = choice.from;
      meals = choice.meals;
    }
    final r = await aiMakeWeek(context, widget.food, from: from, meals: meals, keep: again ?? widget.food.week, clock: widget.clock);
    if (r == null || !mounted) return;
    setState(() {
      _errors = r.errors.isEmpty ? null : r.errors;
      _autoNotes = r.errors.isEmpty ? r.notes : null;
    });
  }

  /// «Ξαναφτιάξ' το»: ίδια αρχή και γεύματα, άλλη επιλογή φαγητών· οι κλειδωμένες θέσεις μένουν.
  Future<void> _again(WeekPlan w) async {
    final meals = w.meals ?? {for (final d in w.days) for (final s in d) s.meal}.toList();
    _seed++;
    await _generate(w.start, meals, keep: w, ask: false);
  }

  /// Οι μέρες πριν από σήμερα μένουν όπως είναι στο «Ξαναφτιάξ’ το» (U-23): κλειδώνουν προσωρινά για το autoWeek και
  /// ξεκλειδώνουν μετά.
  static WeekPlan lockPast(WeekPlan w, DateTime today) => WeekPlan(
        from: w.from,
        created: w.created,
        source: w.source,
        meals: w.meals,
        days: [
          for (var i = 0; i < w.days.length; i++)
            [for (final s in w.days[i]) w.dayAt(i).isBefore(dayOf(today)) && !s.locked ? s.copyWith(locked: true) : s],
        ],
      );

  static WeekPlan unlockLike(WeekPlan next, WeekPlan old, DateTime today) => WeekPlan(
        from: next.from,
        created: next.created,
        source: next.source,
        meals: next.meals,
        days: [
          for (var i = 0; i < next.days.length; i++)
            [
              for (final s in next.days[i])
                next.dayAt(i).isBefore(dayOf(today)) &&
                        s.locked &&
                        !old.slotsFor(next.dayAt(i)).any((o) => o.meal == s.meal && o.dishId == s.dishId && o.locked)
                    ? s.copyWith(locked: false)
                    : s,
            ],
        ],
      );

  Future<void> _generate(DateTime from, List<Meal> meals, {required WeekPlan? keep, bool ask = true}) async {
    final food = widget.food;
    final g = HealthStore.shared?.goals;
    if (g == null) return;
    final r = autoWeek(
      food,
      from: from,
      meals: meals,
      kcalTarget: g.kcal.toDouble(),
      proteinTarget: g.protein.toDouble(),
      legumesWeek: g.legumesWeek,
      fishWeek: g.fishWeek,
      seed: _seed,
      keep: keep == null ? null : lockPast(keep, _now),
      now: _now.millisecondsSinceEpoch,
    );
    final plan = keep == null ? r.plan : unlockLike(r.plan, keep, _now);
    final old = food.week;
    if (ask && old != null) {
      final yes = await showDialog<bool>(
        context: context,
        routeSettings: const RouteSettings(name: 'Νέο πρόγραμμα'),
        builder: (ctx) => AlertDialog(
          title: const Text('Νέο πρόγραμμα;'),
          content: Text('Το πρόγραμμα από ${shortDayDate(old.start)} γίνεται νέο, από ${shortDayDate(r.plan.start)}. '
              'Ό,τι έχεις ήδη γράψει στο ημερολόγιο μένει όπως είναι.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Άκυρο')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ναι, το νέο')),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    final ok = await food.saveWeek(keepDone(plan, old));
    if (!mounted) return;
    setState(() {
      _errors = ok ? null : [food.saveError ?? 'Δεν αποθηκεύτηκε. Δοκίμασε ξανά.'];
      _autoNotes = ok ? r.notes : null;
    });
  }

  /// Γεύμα που έμεινε κενό (U-8): διαλέγεις φαγητό, με τη μερίδα του γεύματος από τους στόχους.
  Future<void> _fillEmpty(int day, Meal m) async {
    final food = widget.food;
    final d = await Navigator.of(context).push<Dish>(DishesScreen.route(food, pick: true));
    final w = food.week;
    if (d == null || w == null || day >= w.days.length || w.days[day].any((s) => s.meal == m)) return;
    final g = HealthStore.shared?.goals;
    final meals = w.meals ?? [m];
    final share = [for (final x in Meal.values) if (meals.contains(x)) x].fold(0.0, (a, x) => a + mealShare[x]!);
    final kcal = g == null || share <= 0 ? null : ((g.kcal * mealShare[m]! / share) / 10).round() * 10.0;
    final r = portionRange(food, d);
    await food.saveWeek(w.withAdded(day, PlanSlot(meal: m, dishId: d.id, kcal: kcal == null || r == null ? kcal : kcal.clamp(r.lo, r.hi).roundToDouble())));
  }

  Future<void> _delete() async {
    final yes = await showDialog<bool>(
      context: context,
      routeSettings: const RouteSettings(name: 'Σβήσιμο προγράμματος'),
      builder: (ctx) => AlertDialog(
        title: const Text('Σβήσιμο του προγράμματος;'),
        content: const Text('Σβήνεται μόνο το πρόγραμμα. Ό,τι έχεις γράψει στο ημερολόγιο και τα φαγητά σου μένουν.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Άκυρο')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Σβήσιμο')),
        ],
      ),
    );
    if (yes == true) await widget.food.saveWeek(null);
  }

  @override
  Widget build(BuildContext context) => FoodTheme(child: ListenableBuilder(listenable: widget.food, builder: (c, _) => _build(c)));

  Widget _build(BuildContext context) {
    final c = Aigaio.of(context);
    final food = widget.food;
    final w = food.week;
    final lib = libraryDishes(food.dishes);
    final goals = HealthStore.shared?.goals;
    final today = dayOf(_now);
    final body = <Widget>[
      Text(
        'Τι θα φας κάθε μέρα. Στο ημερολόγιο μπαίνει μόνο ό,τι πατήσεις «Το έφαγα».',
        style: TextStyle(fontSize: 14.5, height: 1.4, color: c.textSecondary),
      ),
      const SizedBox(height: 14),
      // 19/11: AI μόνο από ό,τι σου αρέσει (φτιάχνει και νέα φαγητά, άρα και με άδεια βιβλιοθήκη). Κύριο κουμπί μόνο όταν
      // είναι συνδεδεμένο (U-24).
      if (_aiReady)
        FilledButton.icon(
          key: const ValueKey('week-ai'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: food.dishesRead && food.loaded && !_aiBusy ? () => _ai() : null,
          icon: const Icon(Icons.auto_awesome_rounded),
          label: const Text('Φτιάξ’ το με AI'),
        )
      else
        OutlinedButton.icon(
          key: const ValueKey('week-ai'),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: food.dishesRead && food.loaded && !_aiBusy ? () => _ai() : null,
          icon: const Icon(Icons.auto_awesome_rounded),
          label: const Text('Φτιάξ’ το με AI (θέλει σύνδεση)'),
        ),
      const SizedBox(height: 10),
      if (lib.isEmpty)
        Text('Για πρόγραμμα χωρίς AI, βάλε φαγητά στη βιβλιοθήκη: «Τα φαγητά μου › Βιβλιοθήκη».',
            key: const ValueKey('week-no-library'), style: TextStyle(fontSize: 14.5, height: 1.4, color: c.warn))
      else ...[
        // Αυτόματο πρόγραμμα (16/11), χωρίς AI. Οι οδηγίες για επικόλληση μένουν ως τρίτος τρόπος.
        FilledButton.tonalIcon(
          key: const ValueKey('week-auto'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: food.dishesRead ? _auto : null,
          icon: const Icon(Icons.auto_awesome_motion_rounded),
          label: const Text('Φτιάξε πρόγραμμα'),
        ),
        if (usableLibrary(food) < 20)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Η βιβλιοθήκη έχει ${usableLibrary(food)} φαγητά. Με λιγότερα από 20 το πρόγραμμα θα επαναλαμβάνεται και '
              'κάποιοι κανόνες μπορεί να μη βγαίνουν.',
              key: const ValueKey('week-auto-few'),
              style: TextStyle(fontSize: 13.5, height: 1.4, color: c.textSecondary),
            ),
          ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const ValueKey('week-copy'),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: _copy,
          icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded),
          label: Text(_copied ? 'Αντιγράφηκαν: πήγαινε στο AI' : 'Αντιγραφή οδηγιών για νέο πρόγραμμα'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const ValueKey('week-paste'),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: food.dishesRead ? _paste : null,
          icon: const Icon(Icons.content_paste_rounded),
          label: const Text('Επικόλληση προγράμματος'),
        ),
      ],
      if (_errors case final errs? when errs.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text(errs.first, key: const ValueKey('week-error'), style: TextStyle(fontSize: 14.5, height: 1.4, color: c.warn)),
        // Οι λεπτομέρειες (π.χ. τι απάντησε λάθος το AI) κρυμμένες (U-9).
        if (errs.length > 1)
          ExpansionTile(
            key: const ValueKey('week-error-details'),
            tilePadding: EdgeInsets.zero,
            title: Text('Λεπτομέρειες', style: TextStyle(fontSize: 14, color: c.textSecondary)),
            children: [
              for (final e in errs.skip(1))
                Align(alignment: Alignment.centerLeft, child: Text('•\u00A0$e', style: TextStyle(fontSize: 13.5, height: 1.4, color: c.text))),
            ],
          ),
      ],
      if (_autoNotes case final notes? when notes.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text('Τι δεν βγήκε όπως ζητούν οι κανόνες:',
            key: const ValueKey('week-auto-notes'), style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: c.warn)),
        for (final n in notes) Text('•\u00A0$n', style: TextStyle(fontSize: 14, height: 1.4, color: c.text)),
      ],
      if (w != null) ...[
        const SizedBox(height: 22),
        Row(children: [
          Expanded(
            child: Text('${shortDayDate(w.start)} – ${shortDayDate(w.end)}',
                key: const ValueKey('week-range'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text)),
          ),
          TextButton(key: const ValueKey('week-delete'), onPressed: _delete, child: const Text('Σβήσιμο')),
        ]),
        if (w.source == 'ai')
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('week-ai-again'),
              onPressed: _aiBusy ? null : () => _ai(again: w),
              icon: const Icon(Icons.auto_awesome_rounded, size: 20),
              label: const Text('Ξαναφτιάξ’ το με AI (μένουν όσα κλείδωσες)'),
            ),
          ),
        if (w.source == 'auto')
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('week-auto-again'),
              onPressed: () => _again(w),
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Ξαναφτιάξ’ το (μένουν όσα κλείδωσες)'),
            ),
          ),
        const SizedBox(height: 6),
        FilledButton.tonalIcon(
          key: const ValueKey('week-shopping'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
          onPressed: () => Navigator.of(context).push(ShoppingScreen.route(food)),
          icon: const Icon(Icons.shopping_cart_outlined),
          label: const Text('Λίστα ψωνιών'),
        ),
        for (var i = 0; i < w.days.length; i++) ...[
          const SizedBox(height: 10),
          AppCard(
            key: ValueKey('week-day-$i'),
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Builder(builder: (context) {
                final p = plannedDay(food, w, i);
                final isToday = sameDay(w.dayAt(i), today);
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                    Expanded(
                      child: Text(isToday ? 'Σήμερα$dotJoin${shortDayDate(w.dayAt(i))}' : shortDayDate(w.dayAt(i)),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isToday ? c.food : c.text)),
                    ),
                    Text(
                      '${thousands(p.totals.shownKcal)}${p.unknown > 0 ? '+' : ''}'
                      '${goals == null ? '' : ' / ${thousands(goals.kcal)}'} kcal',
                      key: ValueKey('week-day-kcal-$i'),
                      style: TextStyle(fontSize: 13.5, color: c.textSecondary),
                    ),
                  ]),
                );
              }),
              if (w.days[i].isEmpty && (w.meals?.isEmpty ?? true))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('Χωρίς γεύματα.', style: TextStyle(fontSize: 14, color: c.textTertiary)),
                ),
              for (var k = 0; k < w.days[i].length; k++)
                SlotRow(food: food, plan: w, day: i, index: k, lock: true, clock: widget.clock),
              // Γεύμα που έμεινε κενό (π.χ. συνταγή του AI που δεν πέρασε): διαλέγεις φαγητό (U-8).
              for (final m in w.meals ?? const <Meal>[])
                if (!w.days[i].any((s) => s.meal == m))
                  Padding(
                    padding: const EdgeInsets.only(right: 12, top: 4, bottom: 4),
                    child: Row(children: [
                      Icon(mealIcon(m), size: 24, color: c.textTertiary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('${mealLabel(m)}${dotJoin}χωρίς φαγητό',
                            style: TextStyle(fontSize: 15, height: 1.3, color: c.textSecondary)),
                      ),
                      TextButton(
                        key: ValueKey('week-fill-$i-${m.name}'),
                        onPressed: food.dishesRead ? () => _fillEmpty(i, m) : null,
                        child: const Text('Διάλεξε φαγητό'),
                      ),
                    ]),
                  ),
            ]),
          ),
        ],
      ],
    ];
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(backgroundColor: c.background, surfaceTintColor: Colors.transparent, title: const Text('Πρόγραμμα εβδομάδας')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: body),
        ),
      ),
    );
  }
}

/// Η λίστα ψωνιών του προγράμματος: από σήμερα (ή την αρχή του προγράμματος) ως το τέλος, για ό,τι δεν έχει σημειωθεί.
class ShoppingScreen extends StatefulWidget {
  const ShoppingScreen({super.key, required this.food, this.clock});
  final FoodStore food;
  final DateTime Function()? clock;

  static Route<void> route(FoodStore food) => MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'Λίστα ψωνιών'),
        builder: (_) => ShoppingScreen(food: food),
      );

  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen> {
  /// Τι έχεις ήδη πάρει (μόνο όσο είναι ανοιχτή η οθόνη).
  final _got = <String>{};

  @override
  Widget build(BuildContext context) => FoodTheme(child: ListenableBuilder(listenable: widget.food, builder: (c, _) => _build(c)));

  Widget _build(BuildContext context) {
    final c = Aigaio.of(context);
    final w = widget.food.week;
    final now = (widget.clock ?? DateTime.now)();
    final body = <Widget>[];
    if (w == null) {
      body.add(Text('Δεν υπάρχει πρόγραμμα.', style: TextStyle(fontSize: 15, color: c.textSecondary)));
    } else {
      final ti = w.indexOf(now);
      final from = ti >= 0 ? ti : (dayOf(now).isAfter(w.end) ? w.days.length : 0);
      final l = shoppingList(widget.food, w, fromDay: from, now: now);
      Widget row(String key, ShopLine s) {
        final got = _got.contains(key);
        return CheckboxListTile(
          key: ValueKey('shop-$key'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: got,
          onChanged: (v) => setState(() => v == true ? _got.add(key) : _got.remove(key)),
          title: Text(s.food.name,
              style: TextStyle(fontSize: 15, color: got ? c.textTertiary : c.text, decoration: got ? TextDecoration.lineThrough : null)),
          secondary: Text('${thousands(shopRound(s.amount).round())} ${s.food.unit}',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: got ? c.textTertiary : c.text)),
        );
      }

      body.addAll([
        Text(
          'Από ${shortDayDate(w.dayAt(from.clamp(0, w.days.length - 1)))} ως ${shortDayDate(w.end)}, για τα γεύματα που δεν έχεις σημειώσει. '
          'Ωμά, όπως τα ζυγίζεις. Η κατσαρόλα μετρά μία φορά για κάθε μαγείρεμα, για όλους.',
          style: TextStyle(fontSize: 14, height: 1.4, color: c.textSecondary),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const ValueKey('shop-copy'),
          onPressed: l.isEmpty
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: shoppingText(l, w)));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Η λίστα αντιγράφηκε.')));
                  }
                },
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Αντιγραφή της λίστας'),
        ),
        if (l.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text('Δεν χρειάζεται να αγοράσεις κάτι για τα υπόλοιπα γεύματα.', style: TextStyle(fontSize: 15, color: c.textSecondary)),
          ),
      ]);
      String? cat;
      for (final s in l.main) {
        if (s.food.cat != cat) {
          cat = s.food.cat;
          body.add(Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 2),
            child: Text(cat.isEmpty ? 'Άλλα' : cat, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.food)),
          ));
        }
        body.add(row('m-${s.food.id}', s));
      }
      for (final i in l.fresh.keys.toList()..sort()) {
        body.add(Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 2),
          child: Text('Φρέσκα, ${shortDayDate(w.dayAt(i))}: τη μέρα που μαγειρεύεις',
              key: ValueKey('shop-fresh-$i'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.food)),
        ));
        for (final s in l.fresh[i]!) {
          body.add(row('f$i-${s.food.id}', s));
        }
      }
      if (l.ordered > 0) {
        body.add(Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text('${countText(l.ordered, 'γεύμα είναι', 'γεύματα είναι')} από παραγγελία: δεν αγοράζονται.',
              style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
        ));
      }
      if (l.unknown.isNotEmpty) {
        body.add(Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text('Δεν μπήκαν στη λίστα: ${l.unknown.join(', ')}.', style: TextStyle(fontSize: 13.5, height: 1.35, color: c.warn)),
        ));
      }
    }
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(backgroundColor: c.background, surfaceTintColor: Colors.transparent, title: const Text('Λίστα ψωνιών')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: body),
        ),
      ),
    );
  }
}

/// «Φτιάξε πρόγραμμα»: από πότε και ποια γεύματα. Προεπιλογή: η επόμενη Δευτέρα (ή σήμερα, αν είναι Δευτέρα) και
/// μεσημέρι, σνακ, βράδυ (απόφαση χρήστη 15/11: τρία γεύματα, χωρίς πρωινό).
class AutoWeekSheet extends StatefulWidget {
  const AutoWeekSheet({super.key, required this.now, this.ai = false, this.food});
  final DateTime now;

  /// Για το «Φτιάξ’ το με AI»: η κάρτα «τι θα χρησιμοποιήσει» (U-10).
  final FoodStore? food;

  /// Για το «Φτιάξ’ το με AI» (άλλος τίτλος και εξήγηση).
  final bool ai;

  @override
  State<AutoWeekSheet> createState() => _AutoWeekSheetState();
}

class _AutoWeekSheetState extends State<AutoWeekSheet> {
  late final DateTime _today = DateTime(widget.now.year, widget.now.month, widget.now.day);
  late DateTime _from = nextMonday(widget.now);
  final _meals = <Meal>{Meal.lunch, Meal.snack, Meal.dinner};

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final tomorrow = DateTime(_today.year, _today.month, _today.day + 1);
    final monday = nextMonday(widget.now);
    final starts = <(String, DateTime)>[
      ('Σήμερα', _today),
      ('Αύριο', tomorrow),
      if (!sameDay(monday, _today) && !sameDay(monday, tomorrow)) ('Δευτέρα ${monday.day}/${monday.month}', monday),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(widget.ai ? 'Φτιάξ’ το με AI' : 'Φτιάξε πρόγραμμα', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.text)),
        const SizedBox(height: 4),
        Text(
            widget.ai
                ? '7 μέρες μόνο από ό,τι σου αρέσει: φαγητά της βιβλιοθήκης σου και νέα, αν χρειάζονται. Θέλει 1–3 λεπτά. '
                    'Πριν αποθηκευτεί, το βλέπεις.'
                : '7 μέρες από τη βιβλιοθήκη σου, με τους στόχους σου. Μετά αλλάζεις ό,τι θέλεις με «Άλλαξέ το».',
            style: TextStyle(fontSize: 13.5, height: 1.4, color: c.textSecondary)),
        const SizedBox(height: 14),
        if (widget.ai && widget.food != null) ...[
          AiReadyCard(food: widget.food!),
          const SizedBox(height: 14),
        ],
        Text('Από', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.textSecondary)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final (label, d) in starts)
            ChoiceChip(
              key: ValueKey('auto-from-${d.day}'),
              label: Text(label),
              selected: sameDay(_from, d),
              onSelected: (_) => setState(() => _from = d),
            ),
        ]),
        const SizedBox(height: 14),
        Text('Γεύματα', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.textSecondary)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final m in Meal.values)
            FilterChip(
              key: ValueKey('auto-meal-${m.name}'),
              label: Text(mealLabel(m)),
              selected: _meals.contains(m),
              onSelected: (on) => setState(() => on ? _meals.add(m) : _meals.remove(m)),
            ),
        ]),
        const SizedBox(height: 18),
        FilledButton(
          key: const ValueKey('auto-go'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20)),
          onPressed: _meals.isEmpty || (widget.ai && (widget.food?.likes.like.isEmpty ?? false))
              ? null
              : () => Navigator.pop(context, (from: _from, meals: [for (final m in Meal.values) if (_meals.contains(m)) m])),
          child: const Text('Φτιάξ’ το'),
        ),
      ]),
    );
  }
}
