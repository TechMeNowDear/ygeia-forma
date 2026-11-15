import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../food/dishes.dart';
import '../food/food_model.dart';
import '../food/food_store.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';
import '../food/recipe.dart';
import 'food_add.dart';
import 'nutrition.dart' show carbsColor, fatColor, proteinColor;
import 'recipes.dart';

// ---------------------------------------------------------------------------
// «Τα φαγητά μου» (αίτημα χρήστη 15/11): φτιάχνεις ένα φαγητό από υλικά και το γράφεις με ένα πάτημα.
// Οι αριθμοί βγαίνουν πάντα από τη βάση (lib/food/dishes.dart).
// ---------------------------------------------------------------------------

/// «350 g», «1 μερίδα», «1,5 μερίδες».
String dishQtyText(DishKind k, double q) => switch (k) {
      DishKind.portions => q == 1 ? '1 μερίδα' : '${dec(q, q % 1 == 0 ? 0 : 1)} μερίδες',
      _ => '${gramsText(q)} g',
    };

/// «1.000» από 1.000 και πάνω (όπως οι θερμίδες), αλλιώς όπως παντού («250», «9,3»).
String amountText(double v) => v >= 1000 && v == v.roundToDouble() ? thousands(v.round()) : gramsText(v);

/// Τα σύνολα μιας λίστας υλικών (με τις τιμές της βάσης όπως είναι τώρα), ή null αν λείπει υλικό.
Totals? dishTotals(FoodStore food, List<DishItem> amounts) {
  final p = food.previewDish(amounts);
  return p == null ? null : Totals(p);
}

/// Η δεύτερη γραμμή ενός φαγητού στις λίστες: τι είναι και πόσες θερμίδες έχει «μία φορά».
String dishSubtitle(FoodStore food, Dish d) {
  final missing = food.missingItems(d.items);
  if (missing.isNotEmpty) return 'Λείπει: ${missing.join(', ')}';
  String kp(Totals t) => '${kcalText(t.kcal)} kcal${dotJoin}πρωτεΐνη ${gramsText(t.protein)} g';
  switch (d.kind) {
    case DishKind.plate:
      final t = dishTotals(food, dishAmounts(d, plate: d.lastPlate));
      return t == null ? 'Πιάτο' : 'Πιάτο$dotJoin${kp(t)}';
    case DishKind.portions:
      final t = dishTotals(food, dishAmounts(d, servings: 1));
      return t == null ? 'Ίσες μερίδες' : '1 από ${d.servings} μερίδες$dotJoin${kp(t)}';
    case DishKind.pot:
      final b = d.batch;
      if (b == null) return 'Κατσαρόλα${dotJoin}ζυγίζεις τη μερίδα σου';
      final t = dishTotals(food, dishAmounts(d, portion: 100));
      return t == null ? 'Κατσαρόλα' : 'Κατσαρόλα$dotJoin${kcalText(t.kcal)} kcal ανά 100 g';
  }
}

IconData dishIcon(DishKind k) => switch (k) {
      DishKind.plate => Icons.dinner_dining_rounded,
      DishKind.portions => Icons.grid_view_rounded,
      DishKind.pot => Icons.soup_kitchen_rounded,
    };

/// Ένα φαγητό στις λίστες. Πάτημα = ανοίγει η καταγραφή ([onTap])· το «+» δεξιά = γράφεται αμέσως, όπως την τελευταία
/// φορά ([onQuick]).
class DishTile extends StatelessWidget {
  const DishTile({super.key, required this.food, required this.dish, required this.onTap, this.onQuick, this.onMore, this.line = false});
  final FoodStore food;
  final Dish dish;
  final VoidCallback onTap;
  final VoidCallback? onQuick;
  final VoidCallback? onMore;
  final bool line;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final missing = food.missingItems(dish.items).isNotEmpty;
    return InkWell(
      key: ValueKey('dish-${dish.id}'),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.fromLTRB(4, 10, 0, 10),
        decoration: line ? BoxDecoration(border: Border(bottom: BorderSide(color: c.hairline))) : null,
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: c.tint(c.food), borderRadius: BorderRadius.circular(10)),
              child: Icon(dishIcon(dish.kind), size: 20, color: c.food),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dish.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: c.text)),
                  const SizedBox(height: 2),
                  Text(
                    dishSubtitle(food, dish),
                    style: TextStyle(fontSize: 13, color: missing ? c.warn : c.textSecondary, fontFeatures: tabular),
                  ),
                ],
              ),
            ),
            if (onMore != null)
              IconButton(
                key: ValueKey('dish-more-${dish.id}'),
                tooltip: 'Αλλαγή',
                onPressed: onMore,
                icon: Icon(Icons.more_vert_rounded, color: c.textSecondary),
              ),
            if (onQuick != null && !missing)
              IconButton(
                key: ValueKey('dish-quick-${dish.id}'),
                tooltip: 'Γράψ’ το τώρα, όπως την τελευταία φορά',
                onPressed: onQuick,
                icon: Icon(Icons.add_circle_rounded, color: c.food, size: 32),
              )
            else
              Icon(Icons.chevron_right_rounded, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// Θερμίδες, πρωτεΐνη, υδατάνθρακες, λιπαρά: σε μία σειρά, ή μία γραμμή το καθένα με μεγάλα γράμματα.
class NutrientStrip extends StatelessWidget {
  const NutrientStrip({super.key, required this.totals});
  final Totals? totals;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final t = totals;
    String g(double v) => t == null ? '—' : '${gramsText(v)} g';
    final kcal = t == null ? '—' : kcalText(t.kcal);
    // Στενό πλαίσιο (π.χ. κάρτα σε κινητό 360 dp) ή μεγάλα γράμματα: μία γραμμή το καθένα, ποτέ ετικέτες που ακουμπούν.
    return LayoutBuilder(builder: (context, box) {
    if (box.maxWidth < 320 || veryLargeText(context) || MediaQuery.textScalerOf(context).scale(10) >= 12.5) {
      return Container(
        key: const ValueKey('dish-nutrients-rows'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          InfoRow('kcal', kcal, dot: c.primary),
          InfoRow('Πρωτεΐνη', g(t?.protein ?? 0), dot: proteinColor(c)),
          InfoRow('Υδατάνθρακες', g(t?.carbs ?? 0), dot: carbsColor(c)),
          InfoRow('Λιπαρά', g(t?.fat ?? 0), dot: fatColor(c)),
        ]),
      );
    }
    Widget stat(String label, String value, Color color) => Expanded(
          child: Column(children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  maxLines: 1, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text, fontFeatures: tabular)),
            ),
            const SizedBox(height: 2),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label, maxLines: 1, style: TextStyle(fontSize: 12, color: c.textSecondary)),
                ),
              ),
            ]),
          ]),
        );
    return Container(
      key: const ValueKey('dish-nutrients'),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        stat('kcal', kcal, c.primary),
        stat('Πρωτεΐνη', g(t?.protein ?? 0), proteinColor(c)),
        stat('Υδατάνθρ.', g(t?.carbs ?? 0), carbsColor(c)),
        stat('Λιπαρά', g(t?.fat ?? 0), fatColor(c)),
      ]),
    );
    });
  }
}

/// Πεδίο ποσότητας: αριθμός με «g»/«ml», το πρώτο άγγιγμα διαλέγει όλο τον αριθμό (όπως στο φύλλο ποσότητας).
class AmountField extends StatefulWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.unit = 'g',
    this.error,
    this.big = false,
    this.hint,
  });
  final TextEditingController controller;
  final VoidCallback onChanged;
  final String unit;
  final String? error;
  final bool big;
  final String? hint;

  @override
  State<AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<AmountField> {
  final _focus = FocusNode();
  bool _selectAll = true;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _selectAll = true;
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return TextField(
      controller: widget.controller,
      focusNode: _focus,
      onTap: () {
        if (!_selectAll) return;
        _selectAll = false;
        widget.controller.selection = TextSelection(baseOffset: 0, extentOffset: widget.controller.text.length);
      },
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      textAlign: TextAlign.center,
      onChanged: (_) => widget.onChanged(),
      style: TextStyle(
          fontSize: widget.big ? 26 : 17, fontWeight: widget.big ? FontWeight.w700 : FontWeight.w600, color: c.text, fontFeatures: tabular),
      decoration: InputDecoration(
        isDense: !widget.big,
        hintText: widget.hint,
        suffixText: widget.unit,
        suffixStyle: TextStyle(fontSize: widget.big ? 16 : 14, fontWeight: FontWeight.w600, color: c.textSecondary),
        errorText: widget.error,
        errorMaxLines: 3,
        contentPadding: widget.big ? null : const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(widget.big ? 14 : 12)),
      ),
    );
  }
}

/// Αριθμός πεδίου πάνω από 0 και ως [max], ή null.
double? fieldValue(TextEditingController t, {double max = maxEntryGrams, bool zero = false}) {
  final v = parseNumber(t.text);
  if (v == null || v > max) return null;
  if (zero ? v < 0 : v <= 0) return null;
  return v;
}

/// «−» αριθμός «+»: η μερίδα σου (g) ή οι μερίδες.
class StepperRow extends StatelessWidget {
  const StepperRow({super.key, required this.field, required this.onMinus, required this.onPlus});
  final Widget field;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: IconButton.filledTonal(tooltip: 'Λιγότερο', onPressed: onMinus, icon: const Icon(Icons.remove_rounded)),
          ),
          const SizedBox(width: 10),
          Expanded(child: field),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: IconButton.filledTonal(tooltip: 'Περισσότερο', onPressed: onPlus, icon: const Icon(Icons.add_rounded)),
          ),
        ],
      );
}

/// Ίσα κουμπιά ποσότητας σε μία σειρά (2 × 2 με μεγάλα γράμματα).
class QuickAmounts extends StatelessWidget {
  const QuickAmounts({super.key, required this.values, required this.label, required this.onPick});
  final List<double> values;
  final String Function(double) label;
  final ValueChanged<double> onPick;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    Widget chip(double v) => Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44), padding: const EdgeInsets.symmetric(horizontal: 4), foregroundColor: c.text),
            onPressed: () => onPick(v),
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(label(v), maxLines: 1)),
          ),
        );
    final large = MediaQuery.textScalerOf(context).scale(10) >= 12.5;
    if (large && values.length == 4) {
      return Column(children: [
        Row(children: [chip(values[0]), const SizedBox(width: 8), chip(values[1])]),
        const SizedBox(height: 8),
        Row(children: [chip(values[2]), const SizedBox(width: 8), chip(values[3])]),
      ]);
    }
    return Row(children: [
      for (var k = 0; k < values.length; k++) ...[if (k > 0) const SizedBox(width: 8), chip(values[k])],
    ]);
  }
}

// ---------------------------------------------------------------------------
// Καταγραφή φαγητού
// ---------------------------------------------------------------------------

/// Τι διάλεξες στο φύλλο καταγραφής. [edit]: «Αλλαγή φαγητού» (π.χ. λείπει υλικό).
class DishLogResult {
  const DishLogResult({required this.amounts, required this.qty, required this.meal, this.plate, this.batch, this.edit = false});
  final List<DishItem> amounts;
  final double qty;
  final Meal meal;
  final List<double>? plate;
  final PotBatch? batch;
  final bool edit;
}

/// Το «ένα πάτημα»: η καταγραφή όπως την τελευταία φορά, ή null όταν χρειάζεται η οθόνη (λείπει υλικό, κατσαρόλα που
/// δεν έχει ζυγιστεί ή μαγειρεύτηκε πριν από [potQuickDays] μέρες και πάνω, καταγραφή που μοιάζει με λάθος).
DishLogResult? quickDishResult(FoodStore food, Dish d, Meal meal, DateTime now) {
  if (food.missingItems(d.items).isNotEmpty) return null;
  List<DishItem> amounts;
  double qty;
  List<double>? plate;
  switch (d.kind) {
    case DishKind.plate:
      plate = d.lastPlate ?? [for (final i in d.items) i.amount];
      amounts = dishAmounts(d, plate: plate);
      qty = itemsSum(amounts);
    case DishKind.portions:
      qty = d.lastQty ?? 1;
      amounts = dishAmounts(d, servings: qty);
    case DishKind.pot:
      final b = d.batch, g = d.lastQty;
      if (b == null || g == null || g > b.cooked) return null;
      if (daysBetween(DateTime.fromMillisecondsSinceEpoch(b.at), now) >= potQuickDays) return null;
      qty = g;
      amounts = dishAmounts(d, portion: g);
  }
  if (amounts.isEmpty) return null;
  final t = dishTotals(food, amounts);
  if (t == null || dishLooksLikeTypo(t.kcal)) return null;
  return DishLogResult(amounts: amounts, qty: qty, meal: meal, plate: plate);
}

Future<DishLogResult?> openDishLogSheet(BuildContext context, FoodStore food, Dish dish, {required Meal meal, DateTime Function()? now}) =>
    showModalBottomSheet<DishLogResult>(
      context: context,
      routeSettings: const RouteSettings(name: 'Καταγραφή φαγητού'),
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => DishLogSheet(food: food, dish: dish, meal: meal, now: now),
    );

class DishLogSheet extends StatefulWidget {
  const DishLogSheet({super.key, required this.food, required this.dish, required this.meal, this.now});
  final FoodStore food;
  final Dish dish;
  final Meal meal;
  final DateTime Function()? now;

  @override
  State<DishLogSheet> createState() => _DishLogSheetState();
}

class _DishLogSheetState extends State<DishLogSheet> {
  Dish get d => widget.dish;
  late Meal _meal = widget.meal;

  // Πιάτο: μία ποσότητα για κάθε υλικό (ξεκινά από την τελευταία φορά).
  late final List<TextEditingController> _plate = [
    for (var k = 0; k < d.items.length; k++)
      TextEditingController(text: gramsField(d.lastPlate?[k] ?? d.items[k].amount)),
  ];

  // Ίσες μερίδες / κατσαρόλα: πόσο έφαγες.
  late final TextEditingController _qty = TextEditingController(
    text: switch (d.kind) {
      DishKind.portions => gramsField(d.lastQty ?? 1),
      DishKind.pot => d.lastQty == null ? '' : gramsField(d.lastQty!),
      DishKind.plate => '',
    },
  );

  // Κατσαρόλα: νέο μαγείρεμα (όταν δεν υπάρχει, ή το ζητάς): βάρος του έτοιμου και οι ποσότητες αυτής της φοράς.
  late bool _cooking = d.kind == DishKind.pot && d.batch == null;
  final _cooked = TextEditingController();
  bool _changeItems = false;
  late final List<TextEditingController> _batchItems = [
    for (final i in d.items) TextEditingController(text: gramsField(i.amount)),
  ];

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void dispose() {
    for (final t in [..._plate, ..._batchItems, _qty, _cooked]) {
      t.dispose();
    }
    super.dispose();
  }

  void _changed() => setState(() {});

  /// Το μαγείρεμα που μετρά τώρα: το νέο (αν τα πεδία του είναι σωστά) ή το αποθηκευμένο.
  PotBatch? get _batch {
    if (!_cooking) return d.batch;
    final cooked = fieldValue(_cooked, max: maxCookedGrams);
    if (cooked == null) return null;
    final items = <DishItem>[];
    for (var k = 0; k < d.items.length; k++) {
      final v = _changeItems ? fieldValue(_batchItems[k], zero: true) : d.items[k].amount;
      if (v == null) return null;
      if (v > 0) items.add(d.items[k].withAmount(v));
    }
    if (items.isEmpty) return null;
    return PotBatch(at: _now().millisecondsSinceEpoch, cooked: cooked, items: items);
  }

  List<double>? get _plateValues {
    final out = <double>[];
    for (final t in _plate) {
      final v = fieldValue(t, zero: true);
      if (v == null) return null;
      out.add(v);
    }
    return out.any((v) => v > 0) ? out : null;
  }

  /// Οι ποσότητες που θα γραφτούν και «πόσο έφαγες», ή null αν κάτι δεν είναι σωστό ακόμα.
  (List<DishItem>, double)? get _choice {
    switch (d.kind) {
      case DishKind.plate:
        final p = _plateValues;
        if (p == null) return null;
        final a = dishAmounts(d, plate: p);
        return a.isEmpty ? null : (a, itemsSum(a));
      case DishKind.portions:
        final s = fieldValue(_qty, max: maxEatenServings);
        if (s == null) return null;
        final a = dishAmounts(d, servings: s);
        return a.isEmpty ? null : (a, s);
      case DishKind.pot:
        final b = _batch;
        final g = fieldValue(_qty, max: maxCookedGrams);
        if (b == null || g == null || g > b.cooked) return null;
        final a = dishAmounts(d, portion: g, batch: b);
        return a.isEmpty ? null : (a, g);
    }
  }

  Future<void> _submit() async {
    final ch = _choice;
    if (ch == null) return;
    final (amounts, qty) = ch;
    final batch = _cooking ? _batch : null;
    // Νέο μαγείρεμα που ζυγίζει πολύ λιγότερο από τα ωμά υλικά: ρωτά μία φορά.
    if (batch != null && cookedLooksWrong(itemsSum(batch.items), batch.cooked)) {
      final ok = await _ask(
        'Σωστό βάρος;',
        'Τα ωμά υλικά ζυγίζουν ${thousands(itemsSum(batch.items).round())} g και όλο το έτοιμο φαγητό '
            '${thousands(batch.cooked.round())} g. Συνήθως το έτοιμο ζυγίζει περισσότερο (το νερό) ή λίγο λιγότερο '
            '(τα ψητά). Ζύγισες όλο το φαγητό, χωρίς την κατσαρόλα;',
      );
      if (ok != true || !mounted) return;
    }
    final t = dishTotals(widget.food, amounts);
    if (t != null && dishLooksLikeTypo(t.kcal)) {
      final ok = await _ask(
        'Σωστή ποσότητα;',
        '${dishQtyText(d.kind, qty)} «${d.name}» = ${kcalText(t.kcal)} kcal σε μία καταγραφή. Είναι σωστό;',
      );
      if (ok != true || !mounted) return;
    }
    if (!mounted) return;
    Navigator.pop(
      context,
      DishLogResult(amounts: amounts, qty: qty, meal: _meal, plate: d.kind == DishKind.plate ? _plateValues : null, batch: batch),
    );
  }

  Future<bool?> _ask(String title, String text) => showDialog<bool>(
        context: context,
        routeSettings: const RouteSettings(name: 'Έλεγχος φαγητού'),
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Όχι, θα το διορθώσω')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ναι, σωστό')),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => FoodTheme(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final c = Aigaio.of(context);
    final missing = widget.food.missingItems(d.items);
    final ch = missing.isEmpty ? _choice : null;
    final totals = ch == null ? null : dishTotals(widget.food, ch.$1);
    final large = MediaQuery.textScalerOf(context).scale(10) >= 12.5;

    final body = <Widget>[
      Text(d.name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.text)),
      const SizedBox(height: 2),
      if (recipeOf(d) case final r?)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('dish-log-recipe'),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
            onPressed: () => Navigator.of(context).push(CookScreen.route(d, r, widget.food)),
            icon: const Icon(Icons.menu_book_rounded, size: 18),
            label: Text('Η συνταγή: ${countText(r.steps.length, 'βήμα', 'βήματα')} ›'),
          ),
        ),
      InkWell(
        key: const ValueKey('dish-log-edit'),
        onTap: () => Navigator.pop(context, DishLogResult(amounts: const [], qty: 0, meal: _meal, edit: true)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            '${dishKindLabel(d.kind)}$dotJoin${countText(d.items.length, 'υλικό', 'υλικά')}${dotJoin}Αλλαγή φαγητού ›',
            style: TextStyle(fontSize: 13.5, color: c.primary),
          ),
        ),
      ),
      const SizedBox(height: 12),
    ];

    if (missing.isNotEmpty) {
      body.add(_WarnBox(
        text: 'Λείπει ${missing.map((m) => '«$m»').join(', ')}: σβήστηκε από τα προϊόντα σου. Άλλαξε το φαγητό για να το '
            'γράψεις, ώστε οι θερμίδες του να είναι σωστές.',
      ));
    } else {
      switch (d.kind) {
        case DishKind.plate:
          body.addAll(_plateFields(context));
        case DishKind.portions:
          body.addAll(_portionFields(context));
        case DishKind.pot:
          body.addAll(_potFields(context));
      }
    }

    body.addAll([
      const SizedBox(height: 16),
      NutrientStrip(totals: totals),
      const SizedBox(height: 16),
      MealPicker(value: _meal, grid: large, onChanged: (m) => setState(() => _meal = m)),
      const SizedBox(height: 18),
      if (missing.isNotEmpty)
        FilledButton(
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20)),
          onPressed: () => Navigator.pop(context, DishLogResult(amounts: const [], qty: 0, meal: _meal, edit: true)),
          child: const Text('Αλλαγή φαγητού'),
        )
      else
        FilledButton(
          key: const ValueKey('dish-log-add'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20)),
          onPressed: ch == null ? null : _submit,
          child: Text('Προσθήκη στο ${mealLabel(_meal)}', textAlign: TextAlign.center),
        ),
    ]);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: body),
          ),
        ),
      ),
    );
  }

  List<Widget> _plateFields(BuildContext context) {
    final c = Aigaio.of(context);
    return [
      Text('Άλλαξε ό,τι ζύγισες διαφορετικά. Ό,τι δεν έφαγες: 0.',
          style: TextStyle(fontSize: 13, height: 1.35, color: c.textSecondary)),
      const SizedBox(height: 8),
      for (var k = 0; k < d.items.length; k++)
        _ItemAmountRow(
          key: ValueKey('dish-plate-$k'),
          name: widget.food.itemFood(d.items[k])?.name ?? d.items[k].name,
          controller: _plate[k],
          unit: widget.food.itemFood(d.items[k])?.unit ?? 'g',
          zero: true,
          onChanged: _changed,
        ),
    ];
  }

  List<Widget> _portionFields(BuildContext context) {
    final c = Aigaio.of(context);
    final s = fieldValue(_qty, max: maxEatenServings);
    void set(double v) => setState(() => _qty.text = gramsField(v.clamp(0.5, maxEatenServings).toDouble()));
    return [
      Text('Η συνταγή βγάζει ${countText(d.servings, 'μερίδα', 'μερίδες')}. Πόσες έφαγες;',
          style: TextStyle(fontSize: 14, height: 1.35, color: c.text)),
      const SizedBox(height: 10),
      StepperRow(
        field: AmountField(
          key: const ValueKey('dish-servings'),
          controller: _qty,
          onChanged: _changed,
          unit: s == 1 ? 'μερίδα' : 'μερίδες',
          big: true,
          error: s == null ? 'Γράψε από 0,5 ως ${dec(maxEatenServings, 0)} μερίδες.' : null,
        ),
        onMinus: s == null ? null : () => set(s - 0.5),
        onPlus: s == null ? null : () => set(s + 0.5),
      ),
      const SizedBox(height: 10),
      QuickAmounts(values: const [0.5, 1, 1.5, 2], label: (v) => dec(v, v % 1 == 0 ? 0 : 1), onPick: set),
    ];
  }

  List<Widget> _potFields(BuildContext context) {
    final c = Aigaio.of(context);
    final b = d.batch;
    final now = _now();
    final out = <Widget>[];
    if (!_cooking && b != null) {
      final at = DateTime.fromMillisecondsSinceEpoch(b.at);
      final old = daysBetween(at, now) >= potQuickDays;
      out.add(Container(
        key: const ValueKey('dish-batch'),
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        decoration: BoxDecoration(color: old ? c.warnBg : c.background, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Expanded(
            child: Text(
              'Μαγειρεύτηκε ${cookedAgo(at, now)}${dotJoin}όλο το φαγητό ${thousands(b.cooked.round())} g',
              style: TextStyle(fontSize: 14, height: 1.35, color: old ? c.warn : c.text, fontWeight: old ? FontWeight.w600 : null),
            ),
          ),
          TextButton(
            key: const ValueKey('dish-new-cooking'),
            onPressed: () => setState(() => _cooking = true),
            child: const Text('Νέο μαγείρεμα'),
          ),
        ]),
      ));
    } else {
      final cooked = fieldValue(_cooked, max: maxCookedGrams);
      out.addAll([
        Text('Πόσο ζυγίζει όλο το έτοιμο φαγητό;', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
        const SizedBox(height: 4),
        Text(
          'Μόλις μαγειρευτεί, πριν σερβίρει κανείς, χωρίς το βάρος της κατσαρόλας: ζύγισε την άδεια κατσαρόλα πριν '
          'μαγειρέψεις και αφαίρεσέ το.',
          style: TextStyle(fontSize: 13, height: 1.35, color: c.textSecondary),
        ),
        const SizedBox(height: 10),
        AmountField(
          key: const ValueKey('dish-cooked'),
          controller: _cooked,
          onChanged: _changed,
          big: true,
          hint: 'π.χ. 2.250',
          error: _cooked.text.trim().isNotEmpty && cooked == null ? 'Γράψε βάρος ως ${thousands(maxCookedGrams.round())} g.' : null,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('dish-change-items'),
            onPressed: () => setState(() => _changeItems = !_changeItems),
            icon: Icon(_changeItems ? Icons.expand_less_rounded : Icons.expand_more_rounded),
            label: const Text('Άλλαξαν οι ποσότητες αυτή τη φορά;'),
          ),
        ),
        if (_changeItems)
          for (var k = 0; k < d.items.length; k++)
            _ItemAmountRow(
              key: ValueKey('dish-batch-item-$k'),
              name: widget.food.itemFood(d.items[k])?.name ?? d.items[k].name,
              controller: _batchItems[k],
              unit: widget.food.itemFood(d.items[k])?.unit ?? 'g',
              zero: true,
              onChanged: _changed,
            ),
        if (b != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _cooking = false),
              child: Text('Άκυρο: κράτα το μαγείρεμα της ${shortDayDate(DateTime.fromMillisecondsSinceEpoch(b.at))}'),
            ),
          ),
      ]);
    }
    final batch = _batch;
    final g = fieldValue(_qty, max: maxCookedGrams);
    final tooMuch = g != null && batch != null && g > batch.cooked;
    void set(double v) => setState(() => _qty.text = gramsField(v.clamp(1, maxCookedGrams).toDouble()));
    out.addAll([
      const SizedBox(height: 14),
      Text('Η μερίδα μου', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
      const SizedBox(height: 8),
      StepperRow(
        field: AmountField(
          key: const ValueKey('dish-portion'),
          controller: _qty,
          onChanged: _changed,
          big: true,
          hint: 'ζύγισε το πιάτο σου',
          error: tooMuch
              ? 'Η μερίδα είναι μεγαλύτερη από όλο το φαγητό (${thousands(batch!.cooked.round())} g).'
              : (_qty.text.trim().isNotEmpty && g == null ? 'Γράψε τα γραμμάρια της μερίδας σου.' : null),
        ),
        onMinus: g == null ? null : () => set(g - 10),
        onPlus: g == null ? null : () => set(g + 10),
      ),
      const SizedBox(height: 10),
      QuickAmounts(values: const [200, 250, 300, 350], label: (v) => '${v.round()} g', onPick: set),
      if (batch != null && g != null && !tooMuch)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Το ${dec(100 * g / batch.cooked, 0)}% της κατσαρόλας.',
            key: const ValueKey('dish-share'),
            style: TextStyle(fontSize: 12.5, color: c.textTertiary),
          ),
        ),
    ]);
    return out;
  }
}

/// Μία γραμμή «όνομα υλικού · [ποσότητα]».
class _ItemAmountRow extends StatelessWidget {
  const _ItemAmountRow({
    super.key,
    required this.name,
    required this.controller,
    required this.unit,
    required this.onChanged,
    this.zero = false,
  });
  final String name;
  final TextEditingController controller;
  final String unit;
  final VoidCallback onChanged;
  final bool zero;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final ok = fieldValue(controller, zero: zero) != null;
    final field = SizedBox(
      width: 112,
      child: AmountField(controller: controller, onChanged: onChanged, unit: unit, error: ok ? null : 'Άκυρο'),
    );
    final text = Text(name, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, color: c.text));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: veryLargeText(context)
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [text, const SizedBox(height: 6), field])
          : Row(children: [Expanded(child: text), const SizedBox(width: 10), field]),
    );
  }
}

class _WarnBox extends StatelessWidget {
  const _WarnBox({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.warnBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.warnLine)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.warning_amber_rounded, size: 20, color: c.warn),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontSize: 14, height: 1.4, color: c.text))),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Αλλαγή ενός φαγητού που έχει ήδη γραφτεί (από το ημερολόγιο)
// ---------------------------------------------------------------------------

/// Το φαγητό [group] (όλα τα υλικά μιας καταγραφής) από το ημερολόγιο: αλλαγή μερίδας, γεύματος ή διαγραφή.
Future<void> openDishEntry(BuildContext context, FoodStore food, List<LogEntry> group) async {
  final messenger = ScaffoldMessenger.of(context);
  final r = await showModalBottomSheet<({List<LogEntry> entries, bool delete})>(
    context: context,
    routeSettings: const RouteSettings(name: 'Φαγητό στο ημερολόγιο'),
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => DishEntrySheet(food: food, group: group),
  );
  if (r == null) return;
  final name = group.first.dish?.name ?? group.first.food.name;
  if (r.delete) {
    if (!await food.removeGroup(group)) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Διαγράφηκε: $name'),
        persist: false,
        duration: undoSnackBarDuration,
        action: SnackBarAction(label: 'Αναίρεση', onPressed: () => food.restoreGroup(group)),
      ));
  } else {
    await food.updateGroup(r.entries);
  }
}

class DishEntrySheet extends StatefulWidget {
  const DishEntrySheet({super.key, required this.food, required this.group});
  final FoodStore food;
  final List<LogEntry> group;

  @override
  State<DishEntrySheet> createState() => _DishEntrySheetState();
}

class _DishEntrySheetState extends State<DishEntrySheet> {
  List<LogEntry> get g => widget.group;
  DishTag get tag => g.first.dish!;
  late Meal _meal = g.first.meal;
  late final _qty = TextEditingController(text: gramsField(tag.qty));
  late final List<TextEditingController> _items = [for (final e in g) TextEditingController(text: gramsField(e.grams))];
  bool _showItems = false;

  @override
  void dispose() {
    _qty.dispose();
    for (final t in _items) {
      t.dispose();
    }
    super.dispose();
  }

  void _changed() => setState(() {});

  /// Οι καταχωρίσεις όπως θα γραφτούν, ή null αν κάτι δεν είναι σωστό.
  List<LogEntry>? get _result {
    if (tag.kind == DishKind.plate) {
      final out = <LogEntry>[];
      for (var k = 0; k < g.length; k++) {
        final v = fieldValue(_items[k]);
        if (v == null) return null;
        out.add(g[k].copyWith(grams: roundAmount(v), meal: _meal));
      }
      final sum = out.fold(0.0, (a, e) => a + e.grams);
      return [for (final e in out) e.copyWith(dish: tag.withQty(roundAmount(sum)))];
    }
    final q = fieldValue(_qty, max: tag.kind == DishKind.portions ? maxEatenServings : maxCookedGrams);
    if (q == null) return null;
    final f = q / tag.qty;
    return [
      for (final e in g)
        e.copyWith(grams: roundAmount(e.grams * f) > 0 ? roundAmount(e.grams * f) : 0.01, meal: _meal, dish: tag.withQty(q)),
    ];
  }

  Future<void> _save() async {
    final r = _result;
    if (r == null) return;
    final kcal = Totals(r).kcal;
    final unchanged = Totals(g).kcal.round() == kcal.round();
    if (!unchanged && dishLooksLikeTypo(kcal)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Σωστή ποσότητα;'),
          content: Text('«${tag.name}» = ${kcalText(kcal)} kcal σε μία καταγραφή. Είναι σωστό;'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Όχι, θα το διορθώσω')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ναι, σωστό')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    if (!mounted) return;
    Navigator.pop(context, (entries: r, delete: false));
  }

  @override
  Widget build(BuildContext context) => FoodTheme(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final c = Aigaio.of(context);
    final r = _result;
    final large = MediaQuery.textScalerOf(context).scale(10) >= 12.5;
    final portions = tag.kind == DishKind.portions;
    final q = fieldValue(_qty, max: portions ? maxEatenServings : maxCookedGrams);
    void set(double v) => setState(
        () => _qty.text = gramsField(v.clamp(portions ? 0.5 : 1, portions ? maxEatenServings : maxCookedGrams).toDouble()));

    final body = <Widget>[
      Text(tag.name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.text)),
      const SizedBox(height: 4),
      Text('${dishKindLabel(tag.kind)}$dotJoin${countText(g.length, 'υλικό', 'υλικά')}',
          style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
      const SizedBox(height: 14),
    ];
    if (tag.kind == DishKind.plate) {
      for (var k = 0; k < g.length; k++) {
        body.add(_ItemAmountRow(
          key: ValueKey('dish-entry-item-$k'),
          name: g[k].food.name,
          controller: _items[k],
          unit: g[k].food.unit,
          onChanged: _changed,
        ));
      }
    } else {
      body.addAll([
        Text(portions ? 'Μερίδες' : 'Η μερίδα μου', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
        const SizedBox(height: 8),
        StepperRow(
          field: AmountField(
            key: const ValueKey('dish-entry-qty'),
            controller: _qty,
            onChanged: _changed,
            unit: portions ? (q == 1 ? 'μερίδα' : 'μερίδες') : 'g',
            big: true,
            error: q == null ? (portions ? 'Γράψε από 0,5 μερίδα και πάνω.' : 'Γράψε τα γραμμάρια της μερίδας σου.') : null,
          ),
          onMinus: q == null ? null : () => set(q - (portions ? 0.5 : 10)),
          onPlus: q == null ? null : () => set(q + (portions ? 0.5 : 10)),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('dish-entry-items'),
            onPressed: () => setState(() => _showItems = !_showItems),
            icon: Icon(_showItems ? Icons.expand_less_rounded : Icons.expand_more_rounded),
            label: Text('Υλικά (${g.length})'),
          ),
        ),
        if (_showItems)
          for (final e in r ?? g)
            InfoRow(e.food.name, '${amountText(e.grams)} ${e.food.unit}'),
      ]);
    }
    body.addAll([
      const SizedBox(height: 16),
      NutrientStrip(totals: r == null ? null : Totals(r)),
      const SizedBox(height: 16),
      MealPicker(value: _meal, grid: large, onChanged: (m) => setState(() => _meal = m)),
      const SizedBox(height: 18),
      FilledButton(
        key: const ValueKey('dish-entry-save'),
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20)),
        onPressed: r == null ? null : _save,
        child: const Text('Αποθήκευση'),
      ),
      const SizedBox(height: 8),
      TextButton.icon(
        key: const ValueKey('dish-entry-delete'),
        style: TextButton.styleFrom(foregroundColor: c.bad),
        onPressed: () => Navigator.pop(context, (entries: g, delete: true)),
        icon: const Icon(Icons.delete_outline_rounded),
        label: const Text('Διαγραφή'),
      ),
    ]);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: body),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Νέο φαγητό / αλλαγή φαγητού
// ---------------------------------------------------------------------------

/// Ανοίγει την οθόνη του φαγητού ([dish] για αλλαγή· αλλιώς νέο, με αρχικά υλικά [items] και όνομα [name]). Επιστρέφει
/// το φαγητό όπως αποθηκεύτηκε, ή null.
Future<Dish?> openDishEditor(BuildContext context, FoodStore food, {Dish? dish, List<DishItem>? items, String? name}) =>
    Navigator.of(context).push<Dish>(MaterialPageRoute<Dish>(
      settings: RouteSettings(name: dish == null ? 'Νέο φαγητό' : 'Αλλαγή φαγητού'),
      builder: (_) => DishEditScreen(food: food, dish: dish, items: items, name: name),
    ));

class DishEditScreen extends StatefulWidget {
  const DishEditScreen({super.key, required this.food, this.dish, this.items, this.name, this.clock});
  final FoodStore food;
  final Dish? dish;
  final List<DishItem>? items;
  final String? name;
  final DateTime Function()? clock;

  @override
  State<DishEditScreen> createState() => _DishEditScreenState();
}

class _DishEditScreenState extends State<DishEditScreen> {
  late final _name = TextEditingController(text: widget.dish?.name ?? widget.name ?? '');
  late List<DishItem> _items = [...?(widget.dish?.items ?? widget.items)];
  late DishKind _kind = widget.dish?.kind ?? DishKind.plate;
  late final _servings = TextEditingController(text: '${widget.dish?.kind == DishKind.portions ? widget.dish!.servings : 4}');
  bool _tried = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _servings.dispose();
    super.dispose();
  }

  int? get _serv {
    final v = parseNumber(_servings.text);
    return v != null && v == v.roundToDouble() && v >= 1 && v <= maxDishServings ? v.toInt() : null;
  }

  Future<void> _addItem() async {
    final name = _name.text.trim().isEmpty ? 'το φαγητό' : _name.text.trim();
    final r = await pickIngredient(context, widget.food, dishName: name);
    if (r == null || !mounted) return;
    if (_items.length >= maxDishItems) return;
    setState(() => _items = [..._items, DishItem(r.food.id, r.food.name, roundAmount(r.amount))]);
  }

  Future<void> _editItem(int k) async {
    final i = _items[k];
    final f = widget.food.itemFood(i);
    if (f == null) {
      // Το τρόφιμο δεν υπάρχει πια: μόνο αφαίρεση (και νέο υλικό στη θέση του).
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('«${i.name}»'),
          content: const Text('Αυτό το υλικό σβήστηκε από τα προϊόντα σου. Αφαίρεσέ το και βάλε άλλο στη θέση του.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Άκυρο')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Αφαίρεση')),
          ],
        ),
      );
      if (yes == true && mounted) setState(() => _items = [..._items]..removeAt(k));
      return;
    }
    final r = await editIngredient(context, widget.food, f, i.amount);
    if (r == null || !mounted) return;
    setState(() {
      final next = [..._items];
      if (r.remove) {
        next.removeAt(k);
      } else {
        next[k] = DishItem(r.food.id, r.food.name, roundAmount(r.amount));
      }
      _items = next;
    });
  }

  Future<void> _save() async {
    setState(() => _tried = true);
    final name = _name.text.trim();
    final serv = _kind == DishKind.portions ? _serv : 1;
    if (name.isEmpty || _items.isEmpty || serv == null || _saving) return;
    final now = (widget.clock ?? DateTime.now)().millisecondsSinceEpoch;
    final old = widget.dish;
    final sameItems = old != null &&
        old.items.length == _items.length &&
        [for (var k = 0; k < _items.length; k++) old.items[k].id == _items[k].id && old.items[k].amount == _items[k].amount]
            .every((x) => x);
    final Dish d;
    if (old == null) {
      d = Dish(
        id: FoodStore.newDishId(),
        name: name.length > maxDishNameLength ? name.substring(0, maxDishNameLength) : name,
        kind: _kind,
        items: _items,
        servings: serv,
        created: now,
      );
    } else {
      final kindChanged = old.kind != _kind;
      d = Dish(
        id: old.id,
        name: name.length > maxDishNameLength ? name.substring(0, maxDishNameLength) : name,
        kind: _kind,
        items: _items,
        servings: serv,
        // Το τελευταίο μαγείρεμα μένει (είναι ό,τι έχεις στο ψυγείο), εκτός αν άλλαξε το είδος.
        batch: kindChanged ? null : old.batch,
        lastPlate: !kindChanged && sameItems ? old.lastPlate : null,
        lastQty: kindChanged || (old.kind == DishKind.portions && old.servings != serv) ? null : old.lastQty,
        created: old.created,
        used: old.used,
        uses: old.uses,
        extra: old.extra,
      );
    }
    setState(() => _saving = true);
    final ok = await widget.food.saveDish(d);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop(d);
  }

  Future<void> _delete() async {
    final d = widget.dish;
    if (d == null) return;
    final messenger = ScaffoldMessenger.of(context);
    if (!await widget.food.deleteDish(d) || !mounted) return;
    Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Διαγράφηκε: ${d.name}'),
        persist: false,
        duration: undoSnackBarDuration,
        action: SnackBarAction(label: 'Αναίρεση', onPressed: () => widget.food.saveDish(d)),
      ));
  }

  @override
  Widget build(BuildContext context) => FoodTheme(child: ListenableBuilder(listenable: widget.food, builder: (context, _) => _build(context)));

  Widget _build(BuildContext context) {
    final c = Aigaio.of(context);
    final serv = _kind == DishKind.portions ? _serv : 1;
    final all = dishTotals(widget.food, _items);
    final per = serv == null || _kind != DishKind.portions ? null : dishTotals(widget.food, [for (final i in _items) i.withAmount(i.amount / serv)]);
    final missing = widget.food.missingItems(_items);
    final hasOil = _items.any((i) {
      final f = widget.food.itemFood(i);
      return f != null && (f.cat == 'Λιπαρά' || isSpoonFood(f));
    });
    final nameError = _tried && _name.text.trim().isEmpty ? 'Γράψε ένα όνομα, π.χ. «Φακές με σάλτσα».' : null;

    Widget kindCard(DishKind k, String title, String text) {
      final on = _kind == k;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: on ? c.tint(c.food) : c.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: on ? c.food : c.hairline, width: on ? 1.6 : 1),
          ),
          child: InkWell(
            key: ValueKey('dish-kind-${k.name}'),
            customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onTap: () => setState(() => _kind = k),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: on ? c.food : c.textTertiary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: c.text)),
                    const SizedBox(height: 2),
                    Text(text, style: TextStyle(fontSize: 13, height: 1.35, color: c.textSecondary)),
                  ]),
                ),
                Icon(dishIcon(k), color: on ? c.food : c.textTertiary),
              ]),
            ),
          ),
        ),
      );
    }

    String kp(Totals t) => '${kcalText(t.kcal)} kcal${dotJoin}πρωτεΐνη ${gramsText(t.protein)} g';

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        title: Text(widget.dish == null ? 'Νέο φαγητό' : 'Αλλαγή φαγητού'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              TextField(
                key: const ValueKey('dish-name'),
                controller: _name,
                autofocus: widget.dish == null && (widget.name ?? '').isEmpty,
                textCapitalization: TextCapitalization.sentences,
                maxLength: maxDishNameLength,
                onChanged: (_) => setState(() {}),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.text),
                decoration: InputDecoration(
                  labelText: 'Όνομα',
                  hintText: 'π.χ. Φακές με σάλτσα',
                  errorText: nameError,
                  counterText: '',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              if (widget.dish != null && recipeOf(widget.dish!) != null) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const ValueKey('dish-cook'),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () => Navigator.of(context).push(CookScreen.route(widget.dish!, recipeOf(widget.dish!)!, widget.food)),
                  icon: const Icon(Icons.menu_book_rounded),
                  label: const Text('Μαγείρεψέ το: η συνταγή βήμα-βήμα'),
                ),
              ],
              const SizedBox(height: 18),
              SectionTitle(text: 'Υλικά', trailing: _items.isEmpty ? null : countText(_items.length, 'υλικό', 'υλικά')),
              const SizedBox(height: 6),
              if (_items.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                  child: Text(
                    'Πρόσθεσε τα υλικά ένα-ένα, με τα γραμμάρια όπως τα ζυγίζεις, ωμά. Μην ξεχάσεις το λάδι.',
                    style: TextStyle(fontSize: 14, height: 1.4, color: _tried ? c.warn : c.textSecondary),
                  ),
                ),
              AppCard(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (var k = 0; k < _items.length; k++)
                    _IngredientRow(
                      key: ValueKey('dish-item-$k'),
                      item: _items[k],
                      food: widget.food.itemFood(_items[k]),
                      line: true,
                      onTap: () => _editItem(k),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('dish-add-item'),
                      onPressed: _items.length >= maxDishItems ? null : _addItem,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Πρόσθεσε υλικό'),
                    ),
                  ),
                ]),
              ),
              if (_items.isNotEmpty && !hasOil)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: Text('Μαγειρεύτηκε με λάδι ή βούτυρο; Βάλ’ το κι αυτό ως υλικό: μία κουταλιά είναι περίπου 120 kcal.',
                      key: const ValueKey('dish-oil-note'), style: TextStyle(fontSize: 13, height: 1.35, color: c.textSecondary)),
                ),
              if (missing.isNotEmpty) ...[
                const SizedBox(height: 10),
                _WarnBox(text: 'Λείπει ${missing.map((m) => '«$m»').join(', ')}: σβήστηκε από τα προϊόντα σου. Πάτα το και βάλε άλλο.'),
              ],
              const SizedBox(height: 20),
              const SectionTitle(text: 'Πώς το τρως;'),
              const SizedBox(height: 8),
              kindCard(DishKind.plate, 'Ένα πιάτο', 'Το τρως όλο, π.χ. φιλέτο με ρύζι και μπρόκολο. Κάθε φορά αλλάζεις ό,τι ζύγισες διαφορετικά.'),
              kindCard(DishKind.portions, 'Ίσες μερίδες', 'Π.χ. 8 μπιφτέκια ή ταψί σε 4 κομμάτια. Γράφεις πόσες μερίδες έφαγες.'),
              if (_kind == DishKind.portions)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                  child: Row(children: [
                    Expanded(child: Text('Πόσες μερίδες βγάζει;', style: TextStyle(fontSize: 15, color: c.text))),
                    SizedBox(
                      width: 112,
                      child: AmountField(
                        key: const ValueKey('dish-serv'),
                        controller: _servings,
                        onChanged: () => setState(() {}),
                        unit: 'μερ.',
                        error: _serv == null ? '1–$maxDishServings' : null,
                      ),
                    ),
                  ]),
                ),
              kindCard(DishKind.pot, 'Κατσαρόλα',
                  'Για όλους ή για μέρες: φακές, σάλτσα, φαγητό φούρνου. Ζυγίζεις όλο το έτοιμο φαγητό και μετά τη μερίδα σου.'),
              const SizedBox(height: 14),
              if (all != null && _items.isNotEmpty)
                AppCard(
                  key: const ValueKey('dish-totals'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (_kind == DishKind.portions && per != null) ...[
                      Text('Μία μερίδα (1 από $serv)', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.textSecondary)),
                      const SizedBox(height: 8),
                      NutrientStrip(totals: per),
                      const SizedBox(height: 10),
                      Text('Όλο το φαγητό: ${kp(all)}', style: TextStyle(fontSize: 13, color: c.textSecondary, fontFeatures: tabular)),
                    ] else ...[
                      Text(_kind == DishKind.pot ? 'Όλη η κατσαρόλα' : 'Όλο το πιάτο',
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.textSecondary)),
                      const SizedBox(height: 8),
                      NutrientStrip(totals: all),
                      if (_kind == DishKind.pot) ...[
                        const SizedBox(height: 10),
                        Text('Τα ωμά υλικά ζυγίζουν ${thousands(itemsSum(_items).round())} g. Τη μερίδα σου τη βρίσκεις όταν '
                            'ζυγίσεις το έτοιμο φαγητό.',
                            style: TextStyle(fontSize: 13, height: 1.35, color: c.textSecondary)),
                      ],
                    ],
                    const SizedBox(height: 8),
                    Text('Οι τιμές από τη βάση τροφίμων, όπως κάθε τρόφιμο.', style: TextStyle(fontSize: 12, color: c.textTertiary)),
                  ]),
                ),
              const SizedBox(height: 18),
              FilledButton(
                key: const ValueKey('dish-save'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20)),
                onPressed: _saving ? null : _save,
                child: Text(widget.dish == null ? 'Αποθήκευση φαγητού' : 'Αποθήκευση'),
              ),
              if (_tried && _items.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Πρόσθεσε τουλάχιστον ένα υλικό.', style: TextStyle(fontSize: 13.5, color: c.warn)),
                ),
              if (widget.dish != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const ValueKey('dish-delete'),
                  style: TextButton.styleFrom(foregroundColor: c.bad),
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Διαγραφή φαγητού'),
                ),
                Text('Ό,τι έχεις ήδη γράψει από αυτό μένει στο ημερολόγιο όπως είναι.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: c.textTertiary)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Τίτλος ενότητας με κεφαλαία (όπως στο «+ Φαγητό») και προαιρετικό σύντομο κείμενο δεξιά.
class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.text, this.trailing});
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: [
        Expanded(
          child: Text(upperGr(text),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: .6, color: c.textSecondary)),
        ),
        if (trailing != null) Text(trailing!, style: TextStyle(fontSize: 13, color: c.textTertiary)),
      ]),
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({super.key, required this.item, required this.food, required this.onTap, this.line = false});
  final DishItem item;
  final Food? food;
  final VoidCallback onTap;
  final bool line;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final f = food;
    final kcal = f == null ? null : f.n.amount(Nk.kcal) * item.amount / 100;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: line ? BoxDecoration(border: Border(bottom: BorderSide(color: c.hairline))) : null,
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f?.name ?? item.name,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: f == null ? c.warn : c.text)),
              const SizedBox(height: 2),
              Text(
                f == null ? 'Δεν υπάρχει πια: πάτα για αφαίρεση' : '${amountText(item.amount)} ${f.unit}',
                style: TextStyle(fontSize: 13, color: f == null ? c.warn : c.textSecondary, fontFeatures: tabular),
              ),
            ]),
          ),
          if (kcal != null) ...[
            const SizedBox(width: 10),
            Text('${kcalText(kcal)} kcal',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: c.text, fontFeatures: tabular)),
          ],
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: c.textTertiary),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Όλα τα φαγητά
// ---------------------------------------------------------------------------

/// ⋮ ενός φαγητού: αλλαγή, διαγραφή.
Future<void> dishActions(BuildContext context, FoodStore food, Dish d) async {
  final c = Aigaio.of(context);
  final choice = await showModalBottomSheet<String>(
    context: context,
    routeSettings: const RouteSettings(name: 'Επιλογές φαγητού'),
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: const Text('Αλλαγή'),
          subtitle: const Text('Όνομα, υλικά, ποσότητες, μερίδες'),
          onTap: () => Navigator.pop(ctx, 'edit'),
        ),
        ListTile(
          leading: Icon(Icons.delete_outline_rounded, color: c.bad),
          title: Text('Διαγραφή', style: TextStyle(color: c.bad)),
          subtitle: const Text('Ό,τι έχεις ήδη γράψει μένει όπως είναι.'),
          onTap: () => Navigator.pop(ctx, 'delete'),
        ),
      ]),
    ),
  );
  if (!context.mounted) return;
  if (choice == 'edit') {
    await openDishEditor(context, food, dish: d);
  } else if (choice == 'delete') {
    if (!await food.deleteDish(d) || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Διαγράφηκε: ${d.name}'),
        persist: false,
        duration: undoSnackBarDuration,
        action: SnackBarAction(label: 'Αναίρεση', onPressed: () => food.saveDish(d)),
      ));
  }
}

/// Όλα τα φαγητά μου. [pick]: ανοιχτό από το «+ Φαγητό»: πάτημα = κλείνει και επιστρέφει το φαγητό, για να γραφτεί.
class DishesScreen extends StatefulWidget {
  const DishesScreen({super.key, required this.food, this.pick = false});
  final FoodStore food;
  final bool pick;

  static Route<Dish> route(FoodStore food, {bool pick = false}) => MaterialPageRoute<Dish>(
        settings: const RouteSettings(name: 'Τα φαγητά μου'),
        builder: (_) => DishesScreen(food: food, pick: pick),
      );

  @override
  State<DishesScreen> createState() => _DishesScreenState();
}

class _DishesScreenState extends State<DishesScreen> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _new() async {
    final d = await openDishEditor(context, widget.food);
    if (d != null && mounted && widget.pick) Navigator.of(context).pop(d);
  }

  @override
  Widget build(BuildContext context) => FoodTheme(child: ListenableBuilder(listenable: widget.food, builder: (context, _) => _build(context)));

  Widget _build(BuildContext context) {
    final c = Aigaio.of(context);
    final all = widget.food.dishes;
    final q = _query.text.trim();
    final shown = q.isEmpty ? all : widget.food.findDishes(q);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(backgroundColor: c.background, surfaceTintColor: Colors.transparent, title: const Text('Τα φαγητά μου')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 120),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  widget.pick
                      ? 'Πάτα ένα φαγητό για να το γράψεις, ή το «+» για να γραφτεί αμέσως όπως την τελευταία φορά.'
                      : 'Φαγητά από τα δικά σου υλικά. Τα γράφεις από το «+ Φαγητό» με ένα πάτημα.',
                  style: TextStyle(fontSize: 14.5, height: 1.4, color: c.textSecondary),
                ),
              ),
              if (widget.food.dishesNote != null)
                Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: _WarnBox(text: widget.food.dishesNote!)),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: FilledButton.icon(
                  key: const ValueKey('dishes-new'),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: widget.food.dishesRead ? _new : null,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Νέο φαγητό'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                child: OutlinedButton.icon(
                  key: const ValueKey('dishes-recipe'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: widget.food.dishesRead ? () => openRecipeStart(context, widget.food) : null,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('Συνταγή από AI'),
                ),
              ),
              if (all.length > 6)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: TextField(
                    controller: _query,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Αναζήτηση στα φαγητά μου',
                      prefixIcon: const Icon(Icons.search_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              if (all.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
                  child: Text('Δεν έχεις φτιάξει ακόμα φαγητά.',
                      textAlign: TextAlign.center, style: TextStyle(color: c.textTertiary, fontSize: 15)),
                ),
              for (var k = 0; k < shown.length; k++)
                DishTile(
                  food: widget.food,
                  dish: shown[k],
                  line: k < shown.length - 1,
                  onTap: () {
                    if (widget.pick) {
                      Navigator.of(context).pop(shown[k]);
                    } else {
                      openDishEditor(context, widget.food, dish: shown[k]);
                    }
                  },
                  onMore: () => dishActions(context, widget.food, shown[k]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
