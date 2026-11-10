import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart' show countText;
import '../food/food_model.dart';
import '../food/food_search.dart';
import '../food/food_store.dart';
import '../food/off.dart';
import '../theme.dart';
import 'food_add.dart';

/// «Τα προϊόντα μου»: περνάω προϊόντα στη βάση μου χωρίς να τα καταγράψω ως φαγητό
/// (π.χ. μετά το σούπερ μάρκετ), τα διορθώνω ή τα σβήνω.
class MyFoodsScreen extends StatefulWidget {
  const MyFoodsScreen({super.key, required this.food});
  final FoodStore food;

  @override
  State<MyFoodsScreen> createState() => _MyFoodsScreenState();
}

class _MyFoodsScreenState extends State<MyFoodsScreen> {
  final _query = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _saved(Food f, {bool fromScan = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Αποθηκεύτηκε: ${f.name}'),
      action: fromScan ? SnackBarAction(label: 'Σκάναρε άλλο', onPressed: _scan) : null,
    ));
  }

  Future<void> _scan() async {
    final f = await scanToFood(
      context,
      widget.food,
      onBusy: (b) {
        if (mounted) setState(() => _busy = b);
      },
      existing: (e) async {
        if (!mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Το έχεις ήδη: ${e.name}. Αν θες, διόρθωσέ το.')),
        );
        return _edit(e, note: 'Αυτό το προϊόν το έχεις ήδη περάσει.');
      },
    );
    if (f != null && mounted) _saved(f, fromScan: true);
  }

  /// Όλα τα προϊόντα σε απλό κείμενο, για έλεγχο (π.χ. επικόλληση σε ένα μήνυμα ή σημείωση).
  Future<void> _copyForCheck() async {
    final all = widget.food.mine;
    String v(Food f, String k) => f.n.has(k) ? nValueText(f.n[k], digits: 2) : '—';
    final b = StringBuffer('Τα προϊόντα μου (${all.length})\n');
    for (final f in all) {
      b
        ..writeln()
        ..writeln(f.name)
        ..writeln('Μάρκα: ${f.brand ?? '—'} · Barcode: ${f.barcode ?? '—'} · Πηγή: ${f.source}')
        // Κάθε προϊόν με τη δική του βάση: τα υγρά είναι ανά 100 ml (έλεγχος 9/11, Μ2).
        ..writeln('Ανά 100 ${f.unit}: Ενέργεια ${v(f, Nk.kcal)} kcal · Λιπαρά ${v(f, Nk.fat)} g (κορεσμένα ${v(f, Nk.satFat)}) · '
            'Υδατάνθρακες ${v(f, Nk.carbs)} g (σάκχαρα ${v(f, Nk.sugars)}) · Ίνες ${v(f, Nk.fiber)} g · '
            'Πρωτεΐνες ${v(f, Nk.protein)} g · Αλάτι ${v(f, Nk.salt)} g')
        ..writeln('Μερίδα: ${f.servingGrams == null ? '—' : '${gramsText(f.servingGrams!)} ${f.unit}'}');
    }
    // Έλεγχος 9/11 (Μ5): χωρίς «Claude» στα κείμενα της εφαρμογής (έτοιμη για δημόσια κυκλοφορία).
    await Clipboard.setData(ClipboardData(text: b.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(all.length == 1
          ? 'Αντιγράφηκε 1 προϊόν. Επικόλλησέ το όπου θέλεις να το ελέγξεις.'
          : 'Αντιγράφηκαν ${all.length} προϊόντα. Επικόλλησέ τα όπου θέλεις να τα ελέγξεις.'),
    ));
  }

  Future<void> _manual() async {
    final f = await createFood(context, widget.food);
    if (f != null && mounted) _saved(f);
  }

  Future<Food?> _edit(Food f, {String? note}) => editMyFood(context, widget.food, f, note: note);

  Future<void> _actions(Food f) => myFoodActions(context, widget.food, f);

  @override
  Widget build(BuildContext context) => FoodTheme(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final c = Aigaio.of(context);
    return ListenableBuilder(
      listenable: widget.food,
      builder: (context, _) {
        final all = widget.food.mine;
        final q = _query.text.trim();
        final shown = q.isEmpty ? all : FoodIndex(all).search(q, limit: 500);

        return Scaffold(
          backgroundColor: c.background,
          appBar: AppBar(
            backgroundColor: c.background,
            surfaceTintColor: Colors.transparent,
            title: const Text('Τα προϊόντα μου'),

            bottom: _busy
                ? const PreferredSize(preferredSize: Size.fromHeight(3), child: LinearProgressIndicator(minHeight: 3))
                : null,
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                children: [
                  Text(
                    'Πέρασε εδώ ό,τι αγοράζεις, χωρίς να το καταγράψεις ως φαγητό. '
                    'Όταν το φας, θα το βρεις πρώτο στην αναζήτηση.',
                    style: TextStyle(fontSize: 14.5, height: 1.4, color: c.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                          onPressed: _busy ? null : _scan,
                          icon: const Icon(Icons.qr_code_scanner_rounded),
                          label: const Text('Σάρωση'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                          onPressed: _manual,
                          icon: const Icon(Icons.edit_note_rounded),
                          // UX U5: ίδιο όνομα με το κουμπί της αναζήτησης για την ίδια ενέργεια.
                          label: const Text('Από ετικέτα'),
                        ),
                      ),
                    ],
                  ),
                  if (all.length > 6) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: _query,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Αναζήτηση στα προϊόντα μου',
                        prefixIcon: const Icon(Icons.search_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (all.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Text(
                        'Δεν έχεις περάσει ακόμα προϊόντα.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.textTertiary, fontSize: 15),
                      ),
                    )
                  else ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 0, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              all.length == 1 ? '1 προϊόν' : '${all.length} προϊόντα',
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.textSecondary),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _copyForCheck,
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: const Text('Αντιγραφή λίστας'),
                          ),
                        ],
                      ),
                    ),
                    for (final f in shown)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _actions(f),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(f.name,
                                          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: c.text)),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          if (f.brand != null) ...[
                                            Flexible(child: MineBadge(text: f.brand!)),
                                            const SizedBox(width: 8),
                                          ],
                                          Text(
                                            '${kcalText(f.n.amount(Nk.kcal))} kcal/100 ${f.unit}'
                                            '${f.barcode != null ? ' · barcode' : ''}',
                                            style: TextStyle(fontSize: 12.5, color: c.textSecondary, fontFeatures: tabular),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.more_vert_rounded, color: c.textTertiary),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Διόρθωση ενός δικού μου προϊόντος (και, αν θέλει ο χρήστης, των μερών που το έχει ήδη γράψει).
/// Κοινό για «Τα προϊόντα μου» και το «Δικά μου» του «+ Φαγητό» (σχέδια 9/11).
Future<Food?> editMyFood(BuildContext context, FoodStore food, Food f, {String? note}) async {
  final edited = await Navigator.of(context).push<Food>(
    MaterialPageRoute(settings: const RouteSettings(name: 'Διόρθωση προϊόντος'), builder: (_) => FoodFormScreen(draft: draftFromFood(f), existingId: f.id, note: note)),
  );
  if (edited == null) return null;
  if (!await food.saveMyFood(edited)) return edited;
  // Διόρθωση τιμών: προσφέρεται να διορθωθούν και οι μέρες που το έχω ήδη γράψει.
  final old = food.entriesWithOldValues(edited);
  if (old.isNotEmpty && context.mounted) {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Και στις μέρες που το έγραψες;'),
        content: Text(
          'Το «${edited.name}» υπάρχει σε ${countText(old.length, 'καταχώριση', 'καταχωρίσεις')} των τελευταίων '
          '${FoodStore.historyDays} ημερών με τις παλιές τιμές. Να πάρουν τις νέες; Τα γραμμάρια μένουν ίδια.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Όχι, μόνο από εδώ και πέρα')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ναι, διόρθωσέ τες')),
        ],
      ),
    );
    if (yes == true) {
      final n = await food.applyFoodToEntries(edited, old);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Διορθώθηκαν ${countText(n, 'καταχώριση', 'καταχωρίσεις')}.')));
      }
    }
  }
  return edited;
}

Future<void> _deleteMyFood(BuildContext context, FoodStore food, Food f) async {
  if (!await food.deleteMyFood(f) || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('Διαγράφηκε: ${f.name}'),
    action: SnackBarAction(label: 'Αναίρεση', onPressed: () => food.saveMyFood(f)),
  ));
}

/// ⋮ ενός δικού μου προϊόντος: διόρθωση, όλες οι τιμές, διαγραφή.
Future<void> myFoodActions(BuildContext context, FoodStore food, Food f) async {
  final c = Aigaio.of(context);
  final choice = await showModalBottomSheet<String>(
    context: context,
    routeSettings: const RouteSettings(name: 'Επιλογές προϊόντος'),
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Διόρθωση'),
            onTap: () => Navigator.pop(ctx, 'edit'),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('Όλες οι τιμές και η πηγή'),
            onTap: () => Navigator.pop(ctx, 'detail'),
          ),
          ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: c.bad),
            title: Text('Διαγραφή', style: TextStyle(color: c.bad)),
            subtitle: const Text('Ό,τι έχεις ήδη καταγράψει μένει όπως είναι.'),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  if (choice == 'edit') {
    final e = await editMyFood(context, food, f);
    if (e != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Αποθηκεύτηκε: ${e.name}')));
    }
  } else if (choice == 'detail') {
    await Navigator.of(context).push(MaterialPageRoute<void>(settings: const RouteSettings(name: 'Τρόφιμο'), builder: (_) => FoodDetailScreen(food: f)));
  } else if (choice == 'delete') {
    await _deleteMyFood(context, food, f);
  }
}
