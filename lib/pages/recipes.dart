import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data.dart' show HealthStore;
import '../food/dishes.dart';
import '../food/food_model.dart';
import '../food/food_store.dart';
import '../food/kitchen.dart';
import '../food/recipe.dart';
import '../format.dart';
import '../goals.dart' show Goals;
import '../theme.dart';
import '../widgets.dart';
import 'dishes.dart';
import 'food_add.dart';
import 'privacy_page.dart' show copySensitive;

// ---------------------------------------------------------------------------
// Συνταγές με επικόλληση (15/11, βήμα 2). Ο βοηθός AI γράφει υλικά, βήματα και συμβουλές· τους αριθμούς τους μετρά πάντα
// η εφαρμογή από τη βάση (lib/food/recipe.dart).
// ---------------------------------------------------------------------------

/// Οι στόχοι της μέρας για τις οδηγίες, ή null.
RecipeTargets? targetsOf(Goals? g) =>
    g == null ? null : (kcal: g.kcal, protein: g.protein, satMax: g.satMax, fiber: g.fiber, salt: g.salt);

/// Το φύλλο «Συνταγή από AI»: τι θέλεις → «Αντιγραφή οδηγιών» → (στο AI) → «Επικόλληση συνταγής».
Future<void> openRecipeStart(BuildContext context, FoodStore food) async {
  final paste = await showModalBottomSheet<bool>(
    context: context,
    routeSettings: const RouteSettings(name: 'Συνταγή από AI'),
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => RecipeStartSheet(food: food),
  );
  if (paste == true && context.mounted) {
    await Navigator.of(context).push(RecipePreviewScreen.route(food));
  }
}

class RecipeStartSheet extends StatefulWidget {
  const RecipeStartSheet({super.key, required this.food, this.goals, this.now});
  final FoodStore food;

  /// Για δοκιμές· αλλιώς οι στόχοι της εφαρμογής.
  final Goals? goals;
  final DateTime? now;

  @override
  State<RecipeStartSheet> createState() => _RecipeStartSheetState();
}

class _RecipeStartSheetState extends State<RecipeStartSheet> {
  final _wish = TextEditingController();
  bool _today = false;
  bool _copied = false;

  Goals? get _goals => widget.goals ?? HealthStore.shared?.goals;

  @override
  void dispose() {
    _wish.dispose();
    super.dispose();
  }

  /// Τι μένει σήμερα (θερμίδες, πρωτεΐνη), από το ημερολόγιο και τους στόχους.
  ({int kcal, int protein})? _left() {
    final g = _goals;
    if (g == null) return null;
    final t = Totals(widget.food.entriesFor(dayOf(widget.now ?? DateTime.now())));
    return (kcal: g.kcal - t.shownKcal, protein: (g.protein - t.protein).round());
  }

  Future<void> _copy() async {
    final kitchen = Kitchen.fromJson(HealthStore.shared?.prefs.kitchen);
    final text = recipePrompt(
      wish: _wish.text,
      foods: [...widget.food.mine, ...widget.food.basicFoods],
      likes: widget.food.likes,
      kitchen: kitchen,
      targets: targetsOf(_goals),
      left: _today ? _left() : null,
    );
    await copySensitive(text);
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) => FoodTheme(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final c = Aigaio.of(context);
    final likes = widget.food.likes;
    final left = _left();
    Widget step(int n, String text, {bool done = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: done ? c.food : c.tint(c.food), shape: BoxShape.circle),
              child: done
                  ? Icon(Icons.check_rounded, size: 16, color: c.onSolid)
                  : Text('$n', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.food)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(fontSize: 14.5, height: 1.4, color: c.text))),
          ]),
        );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Text('Συνταγή από AI', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.text)),
              const SizedBox(height: 4),
              Text('Το AI γράφει τα υλικά και τα βήματα. Τις θερμίδες τις μετρά η εφαρμογή από τη βάση της.',
                  style: TextStyle(fontSize: 13.5, height: 1.35, color: c.textSecondary)),
              const SizedBox(height: 16),
              step(1, 'Γράψε τι θέλεις και πάτα «Αντιγραφή οδηγιών».', done: _copied),
              step(2, 'Επικόλλησέ τες σε μια συζήτηση με το AI σου (π.χ. Claude) και στείλ’ τες.'),
              step(3, 'Αντίγραψε όλη την απάντηση και πάτα «Επικόλληση συνταγής».'),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('recipe-wish'),
                controller: _wish,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Τι θέλεις;',
                  hintText: 'π.χ. κοτόπουλο με λαχανικά στον ατμό, για 2 μέρες, ως 30 λεπτά',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              if (left != null) ...[
                const SizedBox(height: 6),
                SwitchListTile(
                  key: const ValueKey('recipe-today'),
                  contentPadding: EdgeInsets.zero,
                  value: _today,
                  onChanged: (v) => setState(() => _today = v),
                  title: const Text('Για σήμερα: να χωράει σε ό,τι μένει'),
                  subtitle: Text('Μένουν ${thousands(left.kcal < 0 ? 0 : left.kcal)} kcal, πρωτεΐνη ${left.protein < 0 ? 0 : left.protein} g'),
                ),
              ],
              InkWell(
                key: const ValueKey('recipe-likes'),
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.of(context).push(FoodLikesScreen.route(widget.food)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(children: [
                    Icon(Icons.favorite_border_rounded, size: 20, color: c.food),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        likes.isEmpty
                            ? 'Τι μου αρέσει: δεν έχεις γράψει ακόμα'
                            : 'Τι μου αρέσει: ${countText(likes.like.length, 'τρόφιμο', 'τρόφιμα')}, '
                                'δε μου αρέσουν ${likes.dislike.length}',
                        style: TextStyle(fontSize: 14.5, color: c.text),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: c.textTertiary),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const ValueKey('recipe-copy'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: _copy,
                icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded),
                label: Text(_copied ? 'Αντιγράφηκαν: πήγαινε στο AI' : 'Αντιγραφή οδηγιών'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const ValueKey('recipe-paste'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.content_paste_rounded),
                label: const Text('Επικόλληση συνταγής'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Ένα υλικό της συνταγής, όπως αντιστοιχίστηκε στη βάση.
class _Item {
  _Item(this.pasted, this.food, this.match, this.amount);
  final PastedItem pasted;
  Food? food;
  ItemMatch match;
  double amount;
}

/// Η επικολλημένη συνταγή: έλεγχος υλικών, θρεπτικά ανά μερίδα με τους στόχους, βήματα, αποθήκευση ως φαγητό.
class RecipePreviewScreen extends StatefulWidget {
  const RecipePreviewScreen({super.key, required this.food, this.text, this.goals});
  final FoodStore food;

  /// Για δοκιμές: το κείμενο αντί για το πρόχειρο.
  final String? text;
  final Goals? goals;

  static Route<Dish> route(FoodStore food) => MaterialPageRoute<Dish>(
        settings: const RouteSettings(name: 'Επικόλληση συνταγής'),
        builder: (_) => RecipePreviewScreen(food: food),
      );

  @override
  State<RecipePreviewScreen> createState() => _RecipePreviewScreenState();
}

class _RecipePreviewScreenState extends State<RecipePreviewScreen> {
  RecipeParse? _parse;
  bool _empty = false;
  final List<_Item> _items = [];
  final _name = TextEditingController();
  late DishKind _kind;
  int _servings = 1;
  bool _saving = false;

  Goals? get _goals => widget.goals ?? HealthStore.shared?.goals;

  @override
  void initState() {
    super.initState();
    if (widget.text != null) {
      _read(widget.text!);
    } else {
      _fromClipboard();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _fromClipboard() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = d?.text ?? '';
    if (text.trim().isEmpty) {
      setState(() => _empty = true);
    } else {
      _read(text);
    }
  }

  void _read(String text) {
    final p = parseRecipe(text);
    _items.clear();
    final r = p.recipe;
    if (r != null) {
      _name.text = r.name;
      _kind = r.kind;
      _servings = r.servings;
      for (final i in r.items) {
        final byId = i.id == null ? null : widget.food.itemFood(DishItem(i.id!, i.name, i.amount));
        if (byId != null) {
          _items.add(_Item(i, byId, ItemMatch.exact, i.amount));
          continue;
        }
        // Το id δεν υπάρχει: το όνομα, μόνο αν ταιριάζουν όλες οι λέξεις του (αλλιώς «δεν βρέθηκε»).
        final hits = widget.food.search(i.name).take(5).where((f) => sameWords(i.name, f.name) || sameWords(f.name, i.name));
        final guess = hits.isEmpty ? null : hits.first;
        _items.add(_Item(i, guess, guess == null ? ItemMatch.missing : ItemMatch.byName, i.amount));
      }
    }
    setState(() {
      _empty = false;
      _parse = p;
    });
  }

  List<DishItem> get _dishItems => [
        for (final i in _items)
          if (i.food != null) DishItem(i.food!.id, i.food!.name, i.amount),
      ];

  bool _disliked(_Item i) => i.food != null && widget.food.likes.dislike.contains(i.food!.id);

  Future<void> _change(int k) async {
    final i = _items[k];
    final f = i.food;
    final r = f == null
        ? await pickIngredient(context, widget.food,
            dishName: _name.text.trim().isEmpty ? 'τη συνταγή' : _name.text.trim(), query: _searchWords(i.pasted.name))
        : await editIngredient(context, widget.food, f, i.amount);
    if (r == null || !mounted) return;
    setState(() {
      if (r.remove) {
        _items.removeAt(k);
      } else {
        i
          ..food = r.food
          ..amount = roundAmount(r.amount)
          ..match = ItemMatch.exact;
      }
    });
  }

  Future<void> _save() async {
    final r = _parse?.recipe;
    if (r == null || _saving) return;
    final name = _name.text.trim();
    final now = DateTime.now().millisecondsSinceEpoch;
    final dish = Dish(
      id: FoodStore.newDishId(),
      name: name.length > maxDishNameLength ? name.substring(0, maxDishNameLength) : name,
      kind: _kind,
      items: _dishItems,
      servings: _kind == DishKind.portions ? _servings : 1,
      created: now,
      extra: {'recipe': Recipe(
        steps: r.recipe.steps,
        tips: r.recipe.tips,
        minutes: r.recipe.minutes,
        keeps: r.recipe.keeps,
        why: r.recipe.why,
        servings: _kind == DishKind.pot ? _servings : null,
      ).toJson()},
    );
    setState(() => _saving = true);
    final ok = await widget.food.saveDish(dish);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Αποθηκεύτηκε: ${dish.name}. Θα το βρίσκεις πρώτο στο «+ Φαγητό».')));
    Navigator.of(context).pop(dish);
  }

  @override
  Widget build(BuildContext context) => FoodTheme(child: ListenableBuilder(listenable: widget.food, builder: (context, _) => _build(context)));

  Widget _build(BuildContext context) {
    final c = Aigaio.of(context);
    final p = _parse;
    final body = <Widget>[];
    if (_empty || p == null) {
      body.add(EmptyCard(
        icon: Icons.content_paste_rounded,
        color: c.food,
        title: _empty ? 'Το πρόχειρο είναι άδειο' : 'Διαβάζω το πρόχειρο…',
        text: 'Αντίγραψε όλη την απάντηση του AI και πάτα «Επικόλληση ξανά».',
        buttonText: 'Επικόλληση ξανά',
        onPressed: _fromClipboard,
      ));
    } else if (!p.ok) {
      body.add(AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Δεν μπορεί να αποθηκευτεί', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: c.bad)),
          const SizedBox(height: 6),
          for (final e in p.errors) Text('• $e', style: TextStyle(fontSize: 14.5, height: 1.4, color: c.text)),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: _fromClipboard, child: const Text('Επικόλληση ξανά')),
        ]),
      ));
    } else {
      body.addAll(_recipe(context, p.recipe!));
    }
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(backgroundColor: c.background, surfaceTintColor: Colors.transparent, title: const Text('Συνταγή')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: body),
        ),
      ),
    );
  }

  List<Widget> _recipe(BuildContext context, PastedRecipe r) {
    final c = Aigaio.of(context);
    final missing = _items.where((i) => i.food == null).length;
    final guessed = _items.where((i) => i.match == ItemMatch.byName).length;
    final disliked = _items.where(_disliked).length;
    final items = _dishItems;
    final all = dishTotals(widget.food, items);
    final per = _kind == DishKind.plate ? 1 : (_servings < 1 ? 1 : _servings);
    final serving = all == null ? null : dishTotals(widget.food, [for (final i in items) i.withAmount(i.amount / per)]);
    final canSave = missing == 0 && disliked == 0 && items.isNotEmpty && _name.text.trim().isNotEmpty;

    return [
      TextField(
        key: const ValueKey('recipe-name'),
        controller: _name,
        onChanged: (_) => setState(() {}),
        maxLength: maxDishNameLength,
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text),
        decoration: InputDecoration(labelText: 'Όνομα', counterText: '', border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 6, children: [
        for (final k in DishKind.values)
          ChoiceChip(
            key: ValueKey('recipe-kind-${k.name}'),
            avatar: Icon(dishIcon(k), size: 18),
            label: Text(dishKindLabel(k)),
            selected: _kind == k,
            onSelected: (_) => setState(() => _kind = k),
          ),
      ]),
      if (_kind != DishKind.plate)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            Expanded(
              child: Text(_kind == DishKind.portions ? 'Μερίδες που βγάζει' : 'Περίπου μερίδες (για το «μία μερίδα»)',
                  style: TextStyle(fontSize: 14.5, color: c.text)),
            ),
            IconButton(
              tooltip: 'Λιγότερες',
              onPressed: _servings > 1 ? () => setState(() => _servings--) : null,
              icon: const Icon(Icons.remove_circle_outline_rounded),
            ),
            Text('$_servings', key: const ValueKey('recipe-servings'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text)),
            IconButton(
              tooltip: 'Περισσότερες',
              onPressed: _servings < maxDishServings ? () => setState(() => _servings++) : null,
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
          ]),
        ),
      const SizedBox(height: 12),
      if (missing > 0 || guessed > 0 || disliked > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _Note(
            warn: missing > 0 || disliked > 0,
            text: [
              if (missing > 0) '${countText(missing, 'υλικό δεν βρέθηκε', 'υλικά δεν βρέθηκαν')} στη βάση: πάτα το και διάλεξε, ή αφαίρεσέ το.',
              if (disliked > 0) '${countText(disliked, 'υλικό είναι', 'υλικά είναι')} στα «Δε μου αρέσει»: άλλαξέ το ή αφαίρεσέ το.',
              if (guessed > 0) '${countText(guessed, 'υλικό βρέθηκε', 'υλικά βρέθηκαν')} από το όνομα: έλεγξε ότι είναι το σωστό.',
            ].join(' '),
          ),
        ),
      AppCard(
        key: const ValueKey('recipe-health'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            _kind == DishKind.plate
                ? 'Όλο το πιάτο'
                : _kind == DishKind.portions
                    ? 'Μία μερίδα (1 από $per)'
                    : 'Μία μερίδα, περίπου (1 από $per)',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.textSecondary),
          ),
          const SizedBox(height: 8),
          NutrientStrip(totals: serving),
          if (serving != null && _goals != null) ...[
            const SizedBox(height: 10),
            ..._goalRows(context, serving, _goals!),
          ],
          if (_kind == DishKind.pot && all != null) ...[
            const SizedBox(height: 8),
            Text('Όλη η κατσαρόλα: ${kcalText(all.kcal)} kcal. Τη μερίδα σου τη ζυγίζεις όταν τη φας.',
                style: TextStyle(fontSize: 13, height: 1.35, color: c.textSecondary)),
          ],
          const SizedBox(height: 6),
          Text('Οι τιμές από τη βάση τροφίμων· όσα υλικά δεν βρέθηκαν δεν μετρούν ακόμα.',
              style: TextStyle(fontSize: 12, color: c.textTertiary)),
        ]),
      ),
      const SizedBox(height: 16),
      SectionTitle(text: 'Υλικά', trailing: countText(_items.length, 'υλικό', 'υλικά')),
      const SizedBox(height: 6),
      AppCard(
        padding: const EdgeInsets.all(4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var k = 0; k < _items.length; k++) _itemRow(context, k),
        ]),
      ),
      if (r.recipe.steps.isNotEmpty) ...[
        const SizedBox(height: 16),
        SectionTitle(text: 'Βήματα', trailing: r.recipe.minutes == null ? null : 'περίπου ${hoursMinutes(r.recipe.minutes!)}'),
        const SizedBox(height: 6),
        RecipeSteps(recipe: r.recipe),
      ],
      const SizedBox(height: 20),
      FilledButton(
        key: const ValueKey('recipe-save'),
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20)),
        onPressed: canSave && !_saving ? _save : null,
        child: const Text('Αποθήκευση στα φαγητά μου'),
      ),
    ];
  }

  /// Μία μερίδα σε σχέση με τους στόχους της μέρας. Πορτοκαλί όταν μία μερίδα παίρνει πάνω από το μισό του ορίου της
  /// μέρας για κορεσμένα ή αλάτι (δική μας επιλογή: τρως 3 γεύματα, άρα ένα γεύμα «δικαιούται» περίπου το ένα τρίτο).
  List<Widget> _goalRows(BuildContext context, Totals t, Goals g) {
    final c = Aigaio.of(context);
    String pct(double v, num of) => of <= 0 ? '' : ' · ${(100 * v / of).round()}%';
    Widget row(String label, String value, {bool warn = false}) => InfoRow(label, value, valueColor: warn ? c.warn : null);
    return [
      row('Θερμίδες', '${kcalText(t.kcal)} από ${thousands(g.kcal)}${pct(t.kcal, g.kcal)}'),
      row('Πρωτεΐνη', '${gramsText(t.protein)} από ${g.protein} g${pct(t.protein, g.protein)}'),
      row('Κορεσμένα', '${dec(t.satFat, 1)} από ${g.satMax} g${pct(t.satFat, g.satMax)}', warn: t.satFat > g.satMax / 2),
      row('Φυτικές ίνες', '${gramsText(t.fiber)} από ${g.fiber} g${pct(t.fiber, g.fiber)}'),
      row('Αλάτι', '${dec(t.salt, 1)} από ${dec(g.salt, 0)} g${pct(t.salt, g.salt)}', warn: t.salt > g.salt / 2),
    ];
  }

  Widget _itemRow(BuildContext context, int k) {
    final c = Aigaio.of(context);
    final i = _items[k];
    final f = i.food;
    final bad = f == null || _disliked(i);
    final note = f == null
        ? 'Δεν βρέθηκε «${i.pasted.name}»: πάτα για να διαλέξεις'
        : _disliked(i)
            ? 'Στα «Δε μου αρέσει»: πάτα για αλλαγή'
            : i.match == ItemMatch.byName
                ? 'Βρέθηκε από το όνομα «${i.pasted.name}»: σωστό;'
                : null;
    return InkWell(
      key: ValueKey('recipe-item-$k'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => _change(k),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: k < _items.length - 1 ? BoxDecoration(border: Border(bottom: BorderSide(color: c.hairline))) : null,
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f?.name ?? i.pasted.name,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: bad ? c.warn : c.text)),
              const SizedBox(height: 2),
              Text('${amountText(i.amount)} ${f?.unit ?? 'g'}',
                  style: TextStyle(fontSize: 13, color: c.textSecondary, fontFeatures: tabular)),
              if (note != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(note, style: TextStyle(fontSize: 12.5, color: c.warn, fontWeight: FontWeight.w600)),
                ),
            ]),
          ),
          if (f != null) ...[
            const SizedBox(width: 8),
            Text('${kcalText(f.n.amount(Nk.kcal) * i.amount / 100)} kcal',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text, fontFeatures: tabular)),
          ],
          Icon(Icons.chevron_right_rounded, color: c.textTertiary),
        ]),
      ),
    );
  }
}

/// Το όνομα του βοηθού χωρίς παρενθέσεις («Φακές (ξερές)» → «Φακές»), για να βρει η αναζήτηση περισσότερα.
String _searchWords(String name) {
  final t = name.replaceAll(RegExp(r'\([^)]*\)'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.isEmpty ? name.trim() : t;
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.warn = false});
  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: warn ? c.warnBg : c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: warn ? c.warnLine : c.hairline),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(warn ? Icons.warning_amber_rounded : Icons.info_outline_rounded, size: 20, color: warn ? c.warn : c.textSecondary),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontSize: 14, height: 1.4, color: c.text))),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Βήματα και μαγείρεμα
// ---------------------------------------------------------------------------

/// «Κατσαρόλα μεγάλη · μέτρια φωτιά · 25 λεπτά»
String stepMeta(RecipeStep s) => [
      if (s.device != null) s.device!,
      if (s.heat != null) s.heat!,
      if (s.minutes != null) hoursMinutes(s.minutes!),
    ].join(dotJoin);

/// Τα βήματα, οι συμβουλές και πόσο κρατά (μόνο για ανάγνωση).
class RecipeSteps extends StatelessWidget {
  const RecipeSteps({super.key, required this.recipe});
  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var k = 0; k < recipe.steps.length; k++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.tint(c.food), shape: BoxShape.circle),
                child: Text('${k + 1}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.food)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(recipe.steps[k].text, style: TextStyle(fontSize: 15, height: 1.4, color: c.text)),
                  if (stepMeta(recipe.steps[k]).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(stepMeta(recipe.steps[k]), style: TextStyle(fontSize: 13, color: c.textSecondary)),
                    ),
                ]),
              ),
            ]),
          ),
        for (final t in recipe.tips)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.lightbulb_outline_rounded, size: 18, color: c.textSecondary),
              const SizedBox(width: 8),
              Expanded(child: Text(t, style: TextStyle(fontSize: 14, height: 1.4, color: c.text))),
            ]),
          ),
        if (recipe.keeps != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.kitchen_outlined, size: 18, color: c.textSecondary),
              const SizedBox(width: 8),
              Expanded(child: Text(recipe.keeps!, style: TextStyle(fontSize: 14, height: 1.4, color: c.text))),
            ]),
          ),
        if (recipe.why != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(recipe.why!, style: TextStyle(fontSize: 13.5, height: 1.4, color: c.textSecondary, fontStyle: FontStyle.italic)),
          ),
      ]),
    );
  }
}

/// Μαγείρεμα βήμα-βήμα: μεγάλα γράμματα, τικ σε ό,τι έγινε, χρονόμετρο ανά βήμα (μόνο όσο είναι ανοιχτή η οθόνη, που
/// μένει αναμμένη). Τίποτα στο παρασκήνιο.
class CookScreen extends StatefulWidget {
  const CookScreen({super.key, required this.dish, required this.recipe, required this.food});
  final Dish dish;
  final Recipe recipe;
  final FoodStore food;

  static Route<void> route(Dish d, Recipe r, FoodStore food) => MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'Μαγείρεμα'),
        builder: (_) => CookScreen(dish: d, recipe: r, food: food),
      );

  @override
  State<CookScreen> createState() => _CookScreenState();
}

class _CookScreenState extends State<CookScreen> {
  static const _training = MethodChannel('ygeia/training');
  final _done = <int>{};
  int? _timerStep;
  int _left = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _keepOn(true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _keepOn(false);
    super.dispose();
  }

  Future<void> _keepOn(bool on) async {
    try {
      await _training.invokeMethod<bool>('keepOn', {'on': on});
    } catch (_) {}
  }

  void _start(int k) {
    final m = widget.recipe.steps[k].minutes;
    if (m == null) return;
    _timer?.cancel();
    setState(() {
      _timerStep = k;
      _left = m * 60;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _left--);
      if (_left <= 0) {
        t.cancel();
        HapticFeedback.heavyImpact();
        SystemSound.play(SystemSoundType.alert);
        setState(() {
          _done.add(k);
          _timerStep = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Τέλος χρόνου: βήμα ${k + 1}')));
      }
    });
  }

  void _stop() {
    _timer?.cancel();
    setState(() => _timerStep = null);
  }

  @override
  Widget build(BuildContext context) => FoodTheme(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final c = Aigaio.of(context);
    final steps = widget.recipe.steps;
    final d = widget.dish;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        title: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        bottom: _timerStep == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Container(
                  key: const ValueKey('cook-timer'),
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                  decoration: BoxDecoration(color: c.foodSolid, borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    Icon(Icons.timer_outlined, color: c.onSolid),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Βήμα ${_timerStep! + 1}: ${clock(_left)}',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.onSolid, fontFeatures: tabular)),
                    ),
                    TextButton(onPressed: _stop, style: TextButton.styleFrom(foregroundColor: c.onSolid), child: const Text('Στοπ')),
                  ]),
                ),
              ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              SectionTitle(text: 'Υλικά', trailing: countText(d.items.length, 'υλικό', 'υλικά')),
              const SizedBox(height: 6),
              AppCard(
                child: Column(children: [
                  for (final i in d.items)
                    InfoRow(widget.food.itemFood(i)?.name ?? i.name, '${amountText(i.amount)} ${widget.food.itemFood(i)?.unit ?? 'g'}'),
                ]),
              ),
              const SizedBox(height: 16),
              const SectionTitle(text: 'Βήματα'),
              const SizedBox(height: 6),
              for (var k = 0; k < steps.length; k++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: _done.contains(k) ? c.tint(c.food) : c.card,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18), side: BorderSide(color: _done.contains(k) ? c.food : c.hairline)),
                    child: InkWell(
                      key: ValueKey('cook-step-$k'),
                      customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      onTap: () => setState(() => _done.contains(k) ? _done.remove(k) : _done.add(k)),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Icon(_done.contains(k) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                color: _done.contains(k) ? c.food : c.textTertiary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text('${k + 1}. ${steps[k].text}',
                                  style: TextStyle(fontSize: 18, height: 1.4, color: c.text, fontWeight: FontWeight.w500)),
                            ),
                          ]),
                          if (stepMeta(steps[k]).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 34, top: 4),
                              child: Text(stepMeta(steps[k]), style: TextStyle(fontSize: 14.5, color: c.textSecondary)),
                            ),
                          if (steps[k].minutes != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 26, top: 4),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  key: ValueKey('cook-start-$k'),
                                  onPressed: () => _start(k),
                                  icon: const Icon(Icons.timer_outlined),
                                  label: Text('Χρονόμετρο ${hoursMinutes(steps[k].minutes!)}'),
                                ),
                              ),
                            ),
                        ]),
                      ),
                    ),
                  ),
                ),
              if (widget.recipe.tips.isNotEmpty || widget.recipe.keeps != null) ...[
                const SizedBox(height: 6),
                RecipeSteps(recipe: Recipe(tips: widget.recipe.tips, keeps: widget.recipe.keeps)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// «Τι μου αρέσει»
// ---------------------------------------------------------------------------

class FoodLikesScreen extends StatefulWidget {
  const FoodLikesScreen({super.key, required this.food});
  final FoodStore food;

  static Route<void> route(FoodStore food) => MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'Τι μου αρέσει'),
        builder: (_) => FoodLikesScreen(food: food),
      );

  @override
  State<FoodLikesScreen> createState() => _FoodLikesScreenState();
}

class _FoodLikesScreenState extends State<FoodLikesScreen> {
  late final _note = TextEditingController(text: widget.food.likes.note);
  Timer? _noteSave;

  @override
  void dispose() {
    if (_noteSave?.isActive ?? false) {
      _noteSave!.cancel();
      _saveNote();
    }
    _note.dispose();
    super.dispose();
  }

  void _saveNote() {
    final l = widget.food.likes;
    if (l.note != _note.text.trim()) widget.food.saveLikes(l.copyWith(note: _note.text.trim()));
  }

  Future<void> _add(bool like) async {
    final f = await pickFood(context, widget.food, forWhat: like ? 'Μου αρέσουν' : 'Δε μου αρέσουν');
    if (f == null || !mounted) return;
    final l = widget.food.likes;
    final likeIds = [for (final x in l.like) if (x != f.id) x];
    final dislikeIds = [for (final x in l.dislike) if (x != f.id) x];
    await widget.food.saveLikes(like ? l.copyWith(like: [...likeIds, f.id], dislike: dislikeIds) : l.copyWith(like: likeIds, dislike: [...dislikeIds, f.id]));
  }

  Future<void> _remove(String id) async {
    final l = widget.food.likes;
    await widget.food.saveLikes(l.copyWith(like: [for (final x in l.like) if (x != id) x], dislike: [for (final x in l.dislike) if (x != id) x]));
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final r = parseLikes(d?.text ?? '', (id) => widget.food.itemFood(DishItem(id, id, 1)) != null);
    if (r == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Το πρόχειρο δεν έχει λίστα «Τι μου αρέσει».')));
      return;
    }
    final ok = await widget.food.saveLikes(r.likes);
    if (!mounted || !ok) return;
    _note.text = r.likes.note;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Μπήκαν ${countText(r.likes.like.length, 'τρόφιμο', 'τρόφιμα')} που σου αρέσουν και '
          '${r.likes.dislike.length} που δε σου αρέσουν'
          '${r.unknown.isEmpty ? '.' : '. ${countText(r.unknown.length, 'δεν βρέθηκε', 'δεν βρέθηκαν')} στη βάση.'}'),
    ));
  }

  @override
  Widget build(BuildContext context) => FoodTheme(child: ListenableBuilder(listenable: widget.food, builder: (context, _) => _build(context)));

  Widget _build(BuildContext context) {
    final c = Aigaio.of(context);
    final l = widget.food.likes;
    Widget chips(List<String> ids, bool like) {
      final foods = [
        for (final id in ids)
          if (widget.food.itemFood(DishItem(id, id, 1)) case final f?) f,
      ];
      return AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (foods.isEmpty)
            Text(like ? 'Τίποτα ακόμα.' : 'Τίποτα ακόμα.', style: TextStyle(fontSize: 14, color: c.textTertiary))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final f in foods)
                InputChip(
                  key: ValueKey('like-${f.id}'),
                  label: Text(f.name),
                  onDeleted: () => _remove(f.id),
                  deleteButtonTooltipMessage: 'Αφαίρεση',
                ),
            ]),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: ValueKey(like ? 'likes-add' : 'dislikes-add'),
              onPressed: widget.food.dishesRead ? () => _add(like) : null,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Πρόσθεσε τρόφιμο'),
            ),
          ),
        ]),
      );
    }

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        title: const Text('Τι μου αρέσει'),
        actions: [
          IconButton(
            key: const ValueKey('likes-paste'),
            tooltip: 'Επικόλληση λίστας',
            onPressed: widget.food.dishesRead ? _paste : null,
            icon: const Icon(Icons.content_paste_rounded),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              Text('Μπαίνουν στις οδηγίες για τις συνταγές από AI. Όσα δε σου αρέσουν δεν μπαίνουν ποτέ σε συνταγή.',
                  style: TextStyle(fontSize: 14.5, height: 1.4, color: c.textSecondary)),
              const SizedBox(height: 16),
              SectionTitle(text: 'Μου αρέσουν', trailing: l.like.isEmpty ? null : '${l.like.length}'),
              const SizedBox(height: 6),
              chips(l.like, true),
              const SizedBox(height: 16),
              SectionTitle(text: 'Δε μου αρέσουν', trailing: l.dislike.isEmpty ? null : '${l.dislike.length}'),
              const SizedBox(height: 6),
              chips(l.dislike, false),
              const SizedBox(height: 16),
              const SectionTitle(text: 'Σημειώσεις'),
              const SizedBox(height: 6),
              TextField(
                key: const ValueKey('likes-note'),
                controller: _note,
                minLines: 3,
                maxLines: 6,
                maxLength: 1000,
                enabled: widget.food.dishesRead,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) {
                  _noteSave?.cancel();
                  _noteSave = Timer(const Duration(milliseconds: 800), _saveNote);
                },
                decoration: InputDecoration(
                  hintText: 'π.χ. πόσο χρόνο έχεις για μαγείρεμα, τι τρόπο μαγειρέματος προτιμάς, τι αποφεύγεις.',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
