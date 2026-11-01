import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../food/food_channel.dart';
import '../food/food_model.dart';
import '../food/food_store.dart';
import '../food/off.dart';
import '../food/weigh_hints.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';
import 'nutrition.dart';

// ---------------------------------------------------------------------------
// Είσοδοι
// ---------------------------------------------------------------------------

Future<void> openAddFood(BuildContext context, FoodStore food, {Meal? meal, DateTime? day}) {
  final shown = food.day;
  food.syncToday();
  // Κάρτα της μέρας που φαινόταν (π.χ. οθόνη ανοιχτή από χθες βράδυ): πάει στη νέα σημερινή μέρα.
  final target = day == null || sameDay(day, shown) ? food.day : day;
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'Προσθήκη φαγητού'),
      builder: (_) => AddFoodScreen(food: food, meal: meal ?? mealForTime(DateTime.now()), day: target),
    ),
  );
}

Future<void> openEditEntry(BuildContext context, FoodStore food, LogEntry e) async {
  final messenger = ScaffoldMessenger.of(context);
  final r = await showModalBottomSheet<_SheetResult>(
    context: context,
    routeSettings: const RouteSettings(name: 'Ποσότητα'),
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => QuantitySheet(food: food, item: e.food, initialGrams: e.grams, meal: e.meal, editing: true),
  );
  if (r == null) return;
  if (r.delete) {
    if (!await food.remove(e)) return;
    messenger.showSnackBar(SnackBar(
      content: Text('Διαγράφηκε: ${e.food.name}'),
      action: SnackBarAction(label: 'Αναίρεση', onPressed: () => food.restore(e)),
    ));
  } else {
    await food.update(e.copyWith(grams: r.grams, meal: r.meal, food: r.food.id == e.food.id ? null : r.food));
  }
}

/// Αριθμός όπως τον γράφουμε στα ελληνικά: «12,5» ή «12.5»· η τελεία ως διαχωριστικό χιλιάδων
/// («1.000», «1.250») διαβάζεται ως χιλιάδες, όχι ως «1».
double? parseNumber(String s) {
  var t = s.trim().replaceAll(' ', '');
  if (t.isEmpty) return null;
  if (t.contains(',')) {
    t = t.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^[1-9]\d{0,2}(\.\d{3})+$').hasMatch(t)) {
    t = t.replaceAll('.', '');
  }
  return double.tryParse(t);
}

/// Γραμμάρια στο πεδίο: χωρίς άσκοπα δεκαδικά, αλλά χωρίς να χάνεται το «,5».
String gramsField(double v) => v == v.roundToDouble() ? '${v.round()}' : dec(v, 1);

/// Επιλογή γεύματος: 4 ίσα κουμπιά που χωράνε πάντα σε μία γραμμή.
class MealPicker extends StatelessWidget {
  const MealPicker({super.key, required this.value, required this.onChanged});
  final Meal value;
  final ValueChanged<Meal> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.hairline)),
      child: Row(
        children: [
          for (final m in Meal.values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(m),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                  decoration: BoxDecoration(
                    color: m == value ? c.foodSolid : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      mealLabel(m),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: m == value ? c.onSolid : c.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Αναζήτηση και προσθήκη
// ---------------------------------------------------------------------------

class AddFoodScreen extends StatefulWidget {
  const AddFoodScreen({super.key, required this.food, required this.meal, required this.day});
  final FoodStore food;
  final Meal meal;
  final DateTime day;

  @override
  State<AddFoodScreen> createState() => _AddFoodScreenState();
}

class _AddFoodScreenState extends State<AddFoodScreen> {
  final _query = TextEditingController();
  late Meal _meal = widget.meal;
  bool _busy = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _pick(Food f) async {
    final r = await showModalBottomSheet<_SheetResult>(
      context: context,
      routeSettings: const RouteSettings(name: 'Ποσότητα'),
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => QuantitySheet(
        food: widget.food,
        item: f,
        initialGrams: widget.food.lastGrams(f.id) ?? f.servingGrams ?? 100,
        meal: _meal,
      ),
    );
    if (r == null || !mounted) return;
    final e = await widget.food.add(r.food, r.grams, r.meal, on: widget.day);
    if (!mounted) return;
    if (!widget.food.isSaved(e)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Δεν αποθηκεύτηκε: ${r.food.name}. Δοκίμασε ξανά.'),
      ));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Προστέθηκε: ${r.food.name}, ${gramsText(r.grams)} g'),
      action: SnackBarAction(label: 'Αναίρεση', onPressed: () => widget.food.remove(e)),
    ));
    setState(() => _meal = r.meal);
  }

  Future<void> _newFood({FoodDraft? draft}) async {
    final f = await createFood(context, widget.food, draft: draft);
    if (f != null && mounted) await _pick(f);
  }

  Future<void> _scan() async {
    final f = await scanToFood(context, widget.food, onBusy: (b) => setState(() => _busy = b));
    if (f != null && mounted) await _pick(f);
  }

  @override
  Widget build(BuildContext context) => FoodTheme(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final c = Aigaio.of(context);
    final q = _query.text;
    final results = q.trim().isEmpty ? const <Food>[] : widget.food.search(q);
    final recent = widget.food.recent(limit: 10);
    // «Συχνά»: όσα τρως συχνά αλλά δεν είναι ήδη στα «Πρόσφατα» (αλλιώς οι δύο λίστες βγαίνουν ίδιες).
    final recentIds = {for (final f in recent) f.id};
    final frequent = [for (final f in widget.food.frequent(limit: 25)) if (!recentIds.contains(f.id)) f].take(10).toList();

    Widget section(String title, List<Food> foods) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.textSecondary)),
            ),
            for (final f in foods) _FoodTile(food: f, store: widget.food, onTap: () => _pick(f)),
          ],
        );

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: TextField(
          controller: _query,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          style: TextStyle(fontSize: 17, color: c.text),
          decoration: InputDecoration(
            hintText: 'Αναζήτηση τροφίμου',
            border: InputBorder.none,
            suffixIcon: q.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Καθαρισμός',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(_query.clear),
                  ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Σκανάρισμα barcode',
            onPressed: _busy ? null : _scan,
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: MealPicker(value: _meal, onChanged: (m) => setState(() => _meal = m)),
            ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.only(bottom: 40),
                children: [
                  if (q.trim().isEmpty) ...[
                    if (frequent.isNotEmpty) section('Συχνά', frequent),
                    if (recent.isNotEmpty) section('Πρόσφατα', recent),
                    if (recent.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                        child: Text(
                          'Γράψε τι έφαγες, με ή χωρίς τόνους, ακόμα και σε greeklish («fakes», «kotopoulo»). '
                          'Για συσκευασμένα προϊόντα πάτα το εικονίδιο του barcode πάνω δεξιά.',
                          style: TextStyle(color: c.textSecondary, fontSize: 15, height: 1.45),
                        ),
                      ),
                  ] else if (results.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                      child: Text(
                        'Δεν βρέθηκε «$q» στη βάση. Αν είναι συσκευασμένο, σκάναρε το barcode ή γράψε τις τιμές της ετικέτας. '
                        'Αν δεν έχει ετικέτα (π.χ. σπιτικό φαγητό), πρόσθεσε ένα-ένα τα υλικά του.',
                        style: TextStyle(color: c.textSecondary, fontSize: 15, height: 1.45),
                      ),
                    )
                  else
                    for (final f in results) _FoodTile(food: f, store: widget.food, onTap: () => _pick(f)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _scan,
                            icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                            label: const Text('Barcode'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _newFood(draft: FoodDraft(name: q.trim())),
                            icon: const Icon(Icons.edit_note_rounded, size: 18),
                            label: const Text('Από ετικέτα'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_busy)
                const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 3)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FoodTile extends StatelessWidget {
  const _FoodTile({required this.food, required this.store, required this.onTap});
  final Food food;
  final FoodStore store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final n = food.n;
    final times = store.timesEaten(food.id);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    food.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: c.text),
                  ),
                  if (food.isMine)
                    Padding(
                      padding: const EdgeInsets.only(top: 3, bottom: 1),
                      child: MineBadge(text: food.brand ?? 'δικό μου'),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    '${kcalText(n.amount(Nk.kcal))} kcal · πρωτεΐνη ${nValueText(n[Nk.protein])} g ανά 100 g'
                    '${times > 0 ? ' · ${times == 1 ? '1 φορά' : '$times φορές'}' : ''}',
                    style: TextStyle(fontSize: 13, color: c.textSecondary, fontFeatures: tabular),
                  ),
                ],
              ),
            ),
            Icon(Icons.add_circle_outline_rounded, color: c.food),
          ],
        ),
      ),
    );
  }
}

/// Μικρή ετικέτα για τα προϊόντα μου (μάρκα), ώστε να ξεχωρίζουν από τα γενικά.
class MineBadge extends StatelessWidget {
  const MineBadge({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: c.tint(c.primary), borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sell_outlined, size: 12, color: c.primary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.primary),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ποσότητα
// ---------------------------------------------------------------------------

class _SheetResult {
  _SheetResult(this.grams, this.meal, this.food, {this.delete = false});
  final double grams;
  final Meal meal;

  /// Η μορφή που διάλεξε (ωμό/βρασμένο/ψητό…): μπορεί να διαφέρει από αυτή που άνοιξε.
  final Food food;
  final bool delete;
}

class QuantitySheet extends StatefulWidget {
  const QuantitySheet({
    super.key,
    required this.food,
    required this.item,
    required this.initialGrams,
    required this.meal,
    this.editing = false,
  });
  final FoodStore food;
  final Food item;
  final double initialGrams;
  final Meal meal;
  final bool editing;

  @override
  State<QuantitySheet> createState() => _QuantitySheetState();
}

class _QuantitySheetState extends State<QuantitySheet> {
  late final _grams = TextEditingController(text: gramsField(widget.initialGrams));
  late Meal _meal = widget.meal;
  late Food _item = widget.item;
  late final List<(Food, String)> _states = widget.food.statesOf(widget.item);

  @override
  void dispose() {
    _grams.dispose();
    super.dispose();
  }

  double? get _value {
    final v = parseNumber(_grams.text);
    return (v == null || v <= 0 || v > 5000) ? null : v;
  }

  void _set(double g) => setState(() => _grams.text = gramsField(g));

  @override
  Widget build(BuildContext context) => FoodTheme(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final c = Aigaio.of(context);
    final f = _item;
    final g = _value;
    double tot(String k) => g == null ? 0 : f.n.amount(k) * g / 100;

    final chips = <(String, double)>[
      if (f.servingGrams != null && f.servingGrams! > 0)
        ('1 μερίδα (${gramsText(f.servingGrams!)} g)', f.servingGrams!),
      for (final v in const [50.0, 100.0, 150.0, 200.0]) ('${v.round()} g', v),
    ];

    Widget stat(String label, String value, Color color) => Expanded(
          child: Column(
            children: [
              Text(value,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text, fontFeatures: tabular)),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text(label, style: TextStyle(fontSize: 12, color: c.textSecondary)),
                ],
              ),
            ],
          ),
        );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(f.name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.text)),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(settings: const RouteSettings(name: 'Τρόφιμο'), builder: (_) => FoodDetailScreen(food: f, sourceName: widget.food.byId(f.id)?.sourceName))),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '${f.brand != null ? '${f.brand} · ' : ''}${kcalText(f.n.amount(Nk.kcal))} kcal ανά 100 g · ${f.source} ›',
                      style: TextStyle(fontSize: 13.5, color: c.primary),
                    ),
                  ),
                ),
                if (_states.length > 1) ...[
                  const SizedBox(height: 12),
                  Text('Ζύγισα:', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.textSecondary)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final st in _states)
                        ChoiceChip(
                          label: Text(st.$2),
                          // Και για καταχώριση με παλιό id (τρόφιμο που άλλαξε σε νεότερη λίστα).
                          selected: st.$1.id == widget.food.currentOf(f).id,
                          onSelected: (_) {
                            if (st.$1.id != widget.food.currentOf(f).id) setState(() => _item = st.$1);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    f.rawId == null
                        ? 'Βάρος πριν το μαγείρεμα (το πιο ακριβές).'
                        : 'Βάρος μετά το μαγείρεμα· οι τιμές είναι για ${(f.cookedLabel ?? 'μαγειρεμένο').toLowerCase()}.',
                    style: TextStyle(fontSize: 12.5, color: c.textTertiary),
                  ),
                ],
                if (weighHints[f.id] case final hint?) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.scale_rounded, size: 18, color: c.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ζύγισε $hint: οι τιμές είναι για ό,τι τρώγεται.',
                          style: TextStyle(fontSize: 13.5, height: 1.35, color: c.text, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Λιγότερο',
                      onPressed: g == null ? null : () => _set((g - 10).clamp(1, 5000).toDouble()),
                      icon: const Icon(Icons.remove_rounded),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _grams,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                        textAlign: TextAlign.center,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: c.text, fontFeatures: tabular),
                        decoration: InputDecoration(
                          suffixText: 'g',
                          errorText: g == null ? 'Γράψε γραμμάρια' : null,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      tooltip: 'Περισσότερο',
                      onPressed: g == null ? null : () => _set((g + 10).clamp(1, 5000).toDouble()),
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [for (final ch in chips) ActionChip(label: Text(ch.$1), onPressed: () => _set(ch.$2))],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                  decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    children: [
                      stat('kcal', kcalText(tot(Nk.kcal)), c.primary),
                      stat('Πρωτεΐνη', '${gramsText(tot(Nk.protein))} g', proteinColor(c)),
                      stat('Υδατάνθρ.', '${gramsText(tot(Nk.carbs))} g', carbsColor(c)),
                      stat('Λίπος', '${gramsText(tot(Nk.fat))} g', fatColor(c)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                MealPicker(value: _meal, onChanged: (m) => setState(() => _meal = m)),
                const SizedBox(height: 18),
                FilledButton(
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: g == null ? null : () => Navigator.pop(context, _SheetResult(g, _meal, _item)),
                  child: Text(widget.editing ? 'Αποθήκευση' : 'Προσθήκη στο ${mealLabel(_meal)}'),
                ),
                if (widget.editing) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: c.bad),
                    onPressed: () => Navigator.pop(context, _SheetResult(g ?? 0, _meal, _item, delete: true)),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Διαγραφή'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Λεπτομέρειες τροφίμου (όλες οι τιμές ανά 100 g και η πηγή)
// ---------------------------------------------------------------------------

class FoodDetailScreen extends StatelessWidget {
  const FoodDetailScreen({super.key, required this.food, this.sourceName});
  final Food food;

  /// Η περιγραφή της πηγής, όταν το [food] είναι αντίγραφο καταχώρισης (που δεν την κρατά).
  final String? sourceName;

  static const _rows = <(String, String, String, int)>[
    ('kcal', 'Ενέργεια', 'kcal', 0),
    ('protein', 'Πρωτεΐνη', 'g', 1),
    ('carbs', 'Υδατάνθρακες', 'g', 1),
    ('sugars', '  από τα οποία σάκχαρα', 'g', 1),
    ('fiber', 'Φυτικές ίνες', 'g', 1),
    ('fat', 'Λίπος', 'g', 1),
    ('satFat', '  από το οποίο κορεσμένα', 'g', 1),
    ('monoFat', '  μονοακόρεστα', 'g', 1),
    ('polyFat', '  πολυακόρεστα', 'g', 1),
    ('salt', 'Αλάτι', 'g', 2),
    ('cholesterol', 'Χοληστερόλη', 'mg', 0),
    ('water', 'Νερό', 'g', 1),
    ('calcium', 'Ασβέστιο', 'mg', 0),
    ('iron', 'Σίδηρος', 'mg', 1),
    ('magnesium', 'Μαγνήσιο', 'mg', 0),
    ('potassium', 'Κάλιο', 'mg', 0),
    ('zinc', 'Ψευδάργυρος', 'mg', 1),
    ('vitC', 'Βιταμίνη C', 'mg', 1),
    ('vitD', 'Βιταμίνη D', 'µg', 1),
    ('vitB12', 'Βιταμίνη B12', 'µg', 1),
    ('folate', 'Φυλλικό οξύ', 'µg', 0),
  ];

  @override
  Widget build(BuildContext context) => FoodTheme(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final c = Aigaio.of(context);
    final f = food;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(backgroundColor: c.background, surfaceTintColor: Colors.transparent, title: Text(f.name)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 40),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CardHeader(icon: Icons.science_outlined, title: 'Ανά 100 g', color: c.food),
                    const SizedBox(height: 6),
                    for (final r in _rows)
                      if (f.n.has(r.$1)) InfoRow(r.$2, '${nValueText(f.n[r.$1], digits: r.$4)} ${r.$3}'),
                    if (f.energyCalc)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('Οι θερμίδες υπολογίστηκαν από τα μακροθρεπτικά (η πηγή δεν τις έδινε).',
                            style: TextStyle(fontSize: 12.5, color: c.textTertiary)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CardHeader(icon: Icons.verified_outlined, title: 'Πηγή', color: c.primary),
                    const SizedBox(height: 6),
                    InfoRow('Βάση', f.source),
                    if (f.sourceCode != null) InfoRow('Κωδικός', '${f.sourceCode}'),
                    if (f.barcode != null) InfoRow('Barcode', f.barcode!),
                    if ((f.sourceName ?? sourceName) != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('Όνομα στην πηγή: ${f.sourceName ?? sourceName}',
                            style: TextStyle(fontSize: 13, color: c.textSecondary)),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      switch (f.source) {
                        'CIQUAL 2025' => 'ANSES, Table de composition nutritionnelle des aliments Ciqual 2025 (Licence Ouverte).',
                        'Open Food Facts' => 'Open Food Facts, ανοιχτή βάση από εθελοντές (ODbL). Ελέγχθηκε με την ετικέτα.',
                        'Ετικέτα' => 'Από την ετικέτα του προϊόντος, όπως την πέρασες.',
                        _ => 'U.S. Department of Agriculture, FoodData Central (δημόσιο αγαθό).',
                      },
                      style: TextStyle(fontSize: 12.5, height: 1.4, color: c.textTertiary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Νέο τρόφιμο από την ετικέτα (ή έλεγχος προϊόντος του Open Food Facts)
// ---------------------------------------------------------------------------

class FoodFormScreen extends StatefulWidget {
  const FoodFormScreen({super.key, required this.draft, this.note, this.existingId});
  final FoodDraft draft;
  final String? note;

  /// Αν δίνεται, διορθώνουμε υπάρχον προϊόν (κρατά το ίδιο id).
  final String? existingId;

  @override
  State<FoodFormScreen> createState() => _FoodFormScreenState();
}

class _FoodFormScreenState extends State<FoodFormScreen> {
  late final _name = TextEditingController(text: widget.draft.name);
  late final _brand = TextEditingController(text: widget.draft.brand ?? '');
  late final _serving = TextEditingController(
      text: widget.draft.servingGrams == null ? '' : gramsField(widget.draft.servingGrams!));
  late final Map<String, TextEditingController> _v = {
    for (final k in _fields.map((e) => e.$1))
      // Μέχρι 4 δεκαδικά, ώστε μια διόρθωση μόνο του ονόματος να μη στρογγυλεύει τις τιμές (αλάτι 0,0125).
      k: TextEditingController(text: widget.draft.values[k] == null ? '' : dec(widget.draft.values[k]!, 4).replaceAll(RegExp(r',?0+$'), '')),
  };
  bool _tried = false;

  static const _fields = <(String, String, String, bool)>[
    (Nk.kcal, 'Ενέργεια', 'kcal', true),
    (Nk.protein, 'Πρωτεΐνη', 'g', true),
    (Nk.carbs, 'Υδατάνθρακες', 'g', true),
    (Nk.sugars, 'από τα οποία σάκχαρα', 'g', false),
    (Nk.fat, 'Λιπαρά', 'g', true),
    (Nk.satFat, 'από τα οποία κορεσμένα', 'g', false),
    (Nk.fiber, 'Φυτικές ίνες', 'g', false),
    (Nk.salt, 'Αλάτι', 'g', false),
  ];

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _serving.dispose();
    for (final c in _v.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, double> get _values => {
        for (final e in _v.entries)
          if (parseNumber(e.value.text) case final v?) e.key: v,
      };

  void _save() {
    setState(() => _tried = true);
    final values = _values;
    final missing = [for (final f in _fields) if (f.$4 && values[f.$1] == null) f.$1];
    if (_name.text.trim().isEmpty || missing.isNotEmpty || impossibleValues(values).isNotEmpty) return;
    final d = FoodDraft(
      name: _name.text.trim(),
      brand: _brand.text.trim(),
      barcode: widget.draft.barcode,
      servingGrams: parseNumber(_serving.text),
      servingLabel: widget.draft.servingLabel,
      values: values,
      fromOff: widget.draft.fromOff,
    );
    Navigator.pop(context, foodFromDraft(d, widget.existingId ?? FoodStore.newFoodId()));
  }

  @override
  Widget build(BuildContext context) => FoodTheme(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final c = Aigaio.of(context);
    final values = _values;
    final mismatch = energyMismatch(values);
    final impossible = impossibleValues(values);
    final doubtful = doubtfulValues(values);

    InputDecoration deco(String label, {String? suffix, String? error, String? warning}) => InputDecoration(
          labelText: label,
          suffixText: suffix,
          errorText: error,
          helperText: warning,
          helperMaxLines: 2,
          helperStyle: TextStyle(fontSize: 12.5, color: c.bad),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        );

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        title: Text(widget.existingId != null
            ? 'Διόρθωση προϊόντος'
            : widget.draft.fromOff
                ? 'Έλεγχος προϊόντος'
                : 'Νέο προϊόν'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 40),
            children: [
              if (widget.note != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: c.tint(c.primary), borderRadius: BorderRadius.circular(16)),
                  child: Text(widget.note!, style: TextStyle(fontSize: 14, height: 1.4, color: c.text)),
                ),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: deco('Όνομα', error: _tried && _name.text.trim().isEmpty ? 'Χρειάζεται όνομα' : null),
              ),
              const SizedBox(height: 12),
              TextField(controller: _brand, decoration: deco('Μάρκα (προαιρετικό)')),
              if (widget.draft.barcode != null) ...[
                const SizedBox(height: 8),
                Text('Barcode ${widget.draft.barcode}', style: TextStyle(color: c.textTertiary, fontSize: 13)),
              ],
              const SizedBox(height: 18),
              Text('Διατροφική ετικέτα, ανά 100 g',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
              const SizedBox(height: 10),
              for (final f in _fields) ...[
                TextField(
                  controller: _v[f.$1],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  onChanged: (_) => setState(() {}),
                  decoration: deco(
                    f.$4 ? f.$2 : '${f.$2} (προαιρετικό)',
                    suffix: f.$3,
                    error: impossible[f.$1] ?? (_tried && f.$4 && values[f.$1] == null ? 'Χρειάζεται' : null),
                    warning: doubtful[f.$1],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (doubtful['total'] != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: c.tint(c.bad), borderRadius: BorderRadius.circular(16)),
                  child: Text(doubtful['total']!, style: TextStyle(fontSize: 13.5, height: 1.4, color: c.text)),
                ),
                const SizedBox(height: 10),
              ],
              if (mismatch != null)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: c.tint(c.bad), borderRadius: BorderRadius.circular(16)),
                  child: Text(
                    'Οι θερμίδες δεν ταιριάζουν με τα υπόλοιπα: από πρωτεΐνη, υδατάνθρακες και λίπος βγαίνουν '
                    'περίπου ${kcalText(mismatch)} kcal. Έλεγξε ξανά την ετικέτα (μήπως είναι ανά μερίδα ή σε kJ;).',
                    style: TextStyle(fontSize: 13.5, height: 1.4, color: c.text),
                  ),
                ),
              const SizedBox(height: 14),
              TextField(
                controller: _serving,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: deco('Μία μερίδα (προαιρετικό)', suffix: 'g'),
              ),
              const SizedBox(height: 22),
              FilledButton(
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: _save,
                child: const Text('Αποθήκευση'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Κοινά: νέο προϊόν χειροκίνητα ή από barcode (χωρίς καταγραφή φαγητού)
// ---------------------------------------------------------------------------

/// Φόρμα νέου τροφίμου· το αποθηκεύει στα προϊόντα μου και το επιστρέφει.
Future<Food?> createFood(BuildContext context, FoodStore food, {FoodDraft? draft, String? note}) async {
  final f = await Navigator.of(context).push<Food>(
    MaterialPageRoute(settings: const RouteSettings(name: 'Νέο τρόφιμο'), builder: (_) => FoodFormScreen(draft: draft ?? FoodDraft(), note: note)),
  );
  if (f == null) return null;
  await food.saveMyFood(f);
  return f;
}

/// Σκανάρισμα → αν υπάρχει ήδη στα προϊόντα μου, αυτό· αλλιώς Open Food Facts → έλεγχος με την ετικέτα → αποθήκευση.
/// [existing]: τι να γίνει όταν το προϊόν υπάρχει ήδη (στην προσθήκη φαγητού απλώς επιστρέφεται).
Future<Food?> scanToFood(
  BuildContext context,
  FoodStore food, {
  required void Function(bool busy) onBusy,
  Future<Food?> Function(Food existing)? existing,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final s = await FoodChannel.scanBarcode();
  if (!context.mounted) return null;
  if (s['ok'] != true) {
    final kind = s['kind'];
    if (kind == 'cancelled') return null;
    final detail = (s['detail'] as String?) ?? '';
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: Text(kind == 'unavailable'
          ? 'Ο σαρωτής κατεβαίνει από το Google Play. Δοκίμασε ξανά σε λίγο, με σύνδεση στο ίντερνετ.'
          : 'Δεν άνοιξε ο σαρωτής. Μέχρι να το διορθώσω, πέρασε το προϊόν χειροκίνητα.'),
      action: detail.isEmpty
          ? null
          : SnackBarAction(
              label: 'Λεπτομέρειες',
              onPressed: () => showDialog<void>(
                context: context,
                routeSettings: const RouteSettings(name: 'Λεπτομέρειες σφάλματος'),
                builder: (ctx) => AlertDialog(
                  title: const Text('Για τον Claude'),
                  content: SingleChildScrollView(
                    child: SelectableText('${s['message'] ?? ''}\n\n$detail', style: const TextStyle(fontSize: 12)),
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Κλείσιμο'))],
                ),
              ),
            ),
    ));
    return null;
  }
  final code = (s['code'] as String?) ?? '';
  final mine = food.byBarcode(code);
  if (mine != null) return existing == null ? mine : existing(mine);

  onBusy(true);
  final r = await FoodChannel.offLookup(code);
  onBusy(false);
  if (!context.mounted) return null;
  if (r['ok'] != true) {
    return createFood(context, food,
        draft: FoodDraft(barcode: code),
        note: 'Δεν έγινε σύνδεση με το Open Food Facts. Πέρασε τα στοιχεία από την ετικέτα.');
  }
  if (r['found'] != true) {
    return createFood(context, food,
        draft: FoodDraft(barcode: code),
        note: 'Το προϊόν δεν υπάρχει στο Open Food Facts. Πέρασε τα στοιχεία από την ετικέτα (ανά 100 g).');
  }
  final d = draftFromOff(code, Map<String, dynamic>.from(r['product'] as Map));
  return createFood(context, food,
      draft: d,
      note: d.missing.isEmpty
          ? 'Βρέθηκε στο Open Food Facts. Έλεγξε ότι τα νούμερα ταιριάζουν με την ετικέτα και πάτα Αποθήκευση.'
          : 'Βρέθηκε στο Open Food Facts, αλλά λείπουν τιμές. Συμπλήρωσέ τες από την ετικέτα.');
}
