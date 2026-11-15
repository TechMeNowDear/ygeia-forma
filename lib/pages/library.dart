import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data.dart' show HealthStore;
import '../food/dishes.dart';
import '../food/food_store.dart';
import '../food/kitchen.dart';
import '../food/library.dart';
import '../format.dart';
import '../theme.dart';
import 'privacy_page.dart' show copySensitive;
import 'recipes.dart' show targetsOf;

// ---------------------------------------------------------------------------
// Βιβλιοθήκη φαγητών (15/11): πολλά φαγητά μαζί με μία επικόλληση, για το εβδομαδιαίο πρόγραμμα (lib/food/library.dart).
// ---------------------------------------------------------------------------

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.food, this.clock});
  final FoodStore food;
  final DateTime Function()? clock;

  static Route<void> route(FoodStore food) => MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'Βιβλιοθήκη φαγητών'),
        builder: (_) => LibraryScreen(food: food),
      );

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _copied = false;
  bool _saving = false;
  List<String>? _errors;
  LibraryImport? _plan;

  Future<void> _copy() async {
    final text = libraryPrompt(
      foods: [...widget.food.mine, ...widget.food.basicFoods],
      likes: widget.food.likes,
      kitchen: Kitchen.fromJson(HealthStore.shared?.prefs.kitchen),
      targets: targetsOf(HealthStore.shared?.goals),
      existing: widget.food.dishes,
    );
    await copySensitive(text);
    if (mounted) setState(() => _copied = true);
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    read(d?.text ?? '');
  }

  /// Διαβάζει το κείμενο και ετοιμάζει τι θα περάσει (χωρίς να γράψει τίποτα).
  void read(String text) {
    if (text.trim().isEmpty) {
      setState(() {
        _errors = const ['Το πρόχειρο είναι άδειο. Αντίγραψε ολόκληρη την απάντηση του βοηθού.'];
        _plan = null;
      });
      return;
    }
    final p = parseLibrary(text);
    final food = widget.food;
    setState(() {
      _errors = p.errors.isEmpty ? null : p.errors;
      _plan = p.errors.isNotEmpty
          ? null
          : planLibraryImport(
              p,
              existing: food.dishes,
              food: (id) => food.itemFood(DishItem(id, id, 1)),
              likes: food.likes,
              now: (widget.clock ?? DateTime.now)().millisecondsSinceEpoch,
              newId: FoodStore.newDishId,
            );
    });
  }

  Future<void> _apply() async {
    final plan = _plan;
    if (plan == null || plan.changes.isEmpty || _saving) return;
    setState(() => _saving = true);
    final ok = await widget.food.saveDishes(plan.changes);
    if (!mounted) return;
    setState(() => _saving = false);
    final messenger = ScaffoldMessenger.of(context);
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(widget.food.saveError ?? 'Δεν αποθηκεύτηκαν. Δοκίμασε ξανά.')));
      return;
    }
    messenger.showSnackBar(SnackBar(
      content: Text('Πέρασαν ${countText(plan.changes.length, 'φαγητό', 'φαγητά')} στη βιβλιοθήκη.'),
    ));
    setState(() => _plan = LibraryImport(problems: plan.problems));
  }

  @override
  Widget build(BuildContext context) => FoodTheme(child: ListenableBuilder(listenable: widget.food, builder: (c, _) => _build(c)));

  Widget _build(BuildContext context) {
    final c = Aigaio.of(context);
    final lib = libraryDishes(widget.food.dishes);
    final plan = _plan;
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
    final body = <Widget>[
      Text('Πολλά φαγητά μαζί, γραμμένα από το AI σε άλλη συζήτηση. Τις θερμίδες τις μετρά η εφαρμογή από τη βάση της.',
          style: TextStyle(fontSize: 14.5, height: 1.4, color: c.textSecondary)),
      const SizedBox(height: 6),
      Text(
        lib.isEmpty ? 'Η βιβλιοθήκη είναι άδεια.' : 'Στη βιβλιοθήκη: ${countText(lib.length, 'φαγητό', 'φαγητά')}.',
        key: const ValueKey('library-count'),
        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: c.text),
      ),
      const SizedBox(height: 16),
      step(1, 'Πάτα «Αντιγραφή οδηγιών».', done: _copied),
      step(2, 'Επικόλλησέ τες σε μια συζήτηση με το AI (π.χ. Claude) και πες του ποια φαγητά θέλεις.'),
      step(3, 'Αντίγραψε όλη την απάντηση και πάτα «Επικόλληση».'),
      const SizedBox(height: 8),
      FilledButton.icon(
        key: const ValueKey('library-copy'),
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
        onPressed: _copy,
        icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded),
        label: Text(_copied ? 'Αντιγράφηκαν: πήγαινε στο AI' : 'Αντιγραφή οδηγιών'),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        key: const ValueKey('library-paste'),
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
        onPressed: widget.food.dishesRead ? _paste : null,
        icon: const Icon(Icons.content_paste_rounded),
        label: const Text('Επικόλληση'),
      ),
      if (widget.food.dishesNote != null) ...[
        const SizedBox(height: 12),
        Text(widget.food.dishesNote!, style: TextStyle(fontSize: 13.5, height: 1.35, color: c.warn)),
      ],
      if (_errors case final errs?) ...[
        const SizedBox(height: 16),
        for (final e in errs)
          Text(e, key: const ValueKey('library-error'), style: TextStyle(fontSize: 14.5, height: 1.4, color: c.warn)),
      ],
      if (plan != null) ...[
        const SizedBox(height: 18),
        _Summary(plan: plan),
        if (plan.changes.isNotEmpty) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('library-apply'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _saving ? null : _apply,
            icon: const Icon(Icons.library_add_check_rounded),
            label: Text('Πέρασε ${countText(plan.changes.length, 'φαγητό', 'φαγητά')}'),
          ),
        ],
        if (plan.problems.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text('Δεν περνούν (${plan.problems.length})',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.warn)),
          const SizedBox(height: 4),
          Text('Δώσε τα προβλήματα στο AI να τα διορθώσει, και επικόλλησε ξανά. Τα υπόλοιπα περνούν κανονικά.',
              style: TextStyle(fontSize: 13.5, height: 1.35, color: c.textSecondary)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('library-copy-problems'),
            onPressed: () async {
              await copySensitive(libraryProblemsText(plan.problems));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Αντιγράφηκαν τα προβλήματα.')));
              }
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Αντιγραφή προβλημάτων για το AI'),
          ),
          const SizedBox(height: 8),
          for (final p in plan.problems)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                for (final e in p.errors)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 8),
                    child: Text('· $e', style: TextStyle(fontSize: 14, height: 1.35, color: c.textSecondary)),
                  ),
              ]),
            ),
        ],
      ],
    ];
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(backgroundColor: c.background, surfaceTintColor: Colors.transparent, title: const Text('Βιβλιοθήκη φαγητών')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 40), children: body),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.plan});
  final LibraryImport plan;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    Widget row(String label, int n) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 15, color: c.text))),
            Text('$n', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
          ]),
        );
    return Container(
      key: const ValueKey('library-summary'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.tint(c.food), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        row('Νέα', plan.added.length),
        row('Αλλαγμένα', plan.updated.length),
        row('Ίδια με πριν', plan.unchanged),
        row('Με πρόβλημα', plan.problems.length),
        if (plan.changes.isEmpty && plan.problems.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Τίποτα καινούργιο: η βιβλιοθήκη έχει ήδη αυτά τα φαγητά.',
                style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
          ),
      ]),
    );
  }
}
