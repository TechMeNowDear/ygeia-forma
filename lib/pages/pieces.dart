// Κομμάτια (16/11): «2 μεσαίες μπανάνες» αντί για γραμμάρια, και «Ζύγισα ένα» για το δικό σου βάρος.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../food/food_model.dart';
import '../food/food_store.dart';
import '../food/units.dart';
import '../format.dart';
import 'food_add.dart' show gramsField, parseNumber;
import '../theme.dart';

/// Ένα μέγεθος για επιλογή: τυπικό (εκτίμηση) ή το δικό σου (ζυγισμένο).
typedef PieceChoice = ({String label, double grams, bool est});

/// Τα μεγέθη ενός τροφίμου: πρώτα το δικό σου (αν το ζύγισες), μετά τα τυπικά.
List<PieceChoice> pieceChoices(FoodStore food, Food item) => [
      if (food.myUnit(item.id) case final g?) (label: 'το δικό σου', grams: g, est: false),
      if (pieceUnits[item.id] case final u?)
        for (final s in u.sizes) (label: s.label.isEmpty ? 'ένα' : s.label, grams: s.grams, est: true),
    ];

/// «2 μεσαίες μπανάνες» / «2 κομμάτια (το δικό σου)».
String pieceChoiceText(Food item, PieceChoice c, int count) {
  final u = pieceUnits[item.id];
  if (!c.est) {
    final noun = u == null ? (count == 1 ? 'κομμάτι' : 'κομμάτια') : (count == 1 ? u.one : u.many);
    return '$count $noun (το δικό σου)';
  }
  final size = u!.sizes.firstWhere((s) => s.grams == c.grams && (s.label.isEmpty ? 'ένα' : s.label) == c.label);
  return pieceText(u, size, count);
}

/// Η σειρά «Κομμάτια» στο φύλλο ποσότητας. [onPick]: γραμμάρια και αν είναι εκτίμηση.
class PieceRow extends StatefulWidget {
  const PieceRow({super.key, required this.food, required this.item, required this.onPick});
  final FoodStore food;
  final Food item;
  final void Function(double grams, bool est) onPick;

  @override
  State<PieceRow> createState() => _PieceRowState();
}

class _PieceRowState extends State<PieceRow> {
  int? _pick;
  int _count = 1;

  void _apply(List<PieceChoice> list) {
    final i = _pick;
    if (i == null || i >= list.length) return;
    widget.onPick(list[i].grams * _count, list[i].est);
  }

  Future<void> _weighOne() async {
    final g = await showDialog<double>(
      context: context,
      routeSettings: const RouteSettings(name: 'Ζύγισα ένα'),
      builder: (_) => WeighOneDialog(initial: widget.food.myUnit(widget.item.id)),
    );
    if (g == null || !mounted) return;
    if (!await widget.food.setMyUnit(widget.item.id, g) || !mounted) return;
    setState(() => _pick = 0);
    _apply(pieceChoices(widget.food, widget.item));
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final list = pieceChoices(widget.food, widget.item);
    if (list.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('unit-weigh'),
          onPressed: _weighOne,
          icon: const Icon(Icons.scale_outlined, size: 18),
          label: const Text('Μετράς σε κομμάτια; Ζύγισε ένα'),
        ),
      );
    }
    final pick = _pick == null || _pick! >= list.length ? null : list[_pick!];
    return Column(key: const ValueKey('pieces'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Κομμάτια:', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.textSecondary)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 6, children: [
        for (var i = 0; i < list.length; i++)
          ChoiceChip(
            key: ValueKey('piece-$i'),
            label: Text('${list[i].label} · ${gramsText(list[i].grams)} g'),
            selected: _pick == i,
            onSelected: (_) {
              setState(() => _pick = i);
              _apply(list);
            },
          ),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        IconButton.filledTonal(
          key: const ValueKey('piece-less'),
          tooltip: 'Ένα λιγότερο',
          onPressed: _count > 1
              ? () {
                  setState(() => _count--);
                  _apply(list);
                }
              : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        Expanded(
          child: Text(
            pick == null ? '$_count' : pieceChoiceText(widget.item, pick, _count),
            key: const ValueKey('piece-text'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text),
          ),
        ),
        IconButton.filledTonal(
          key: const ValueKey('piece-more'),
          tooltip: 'Ένα ακόμα',
          onPressed: _count < 20
              ? () {
                  setState(() => _count++);
                  _apply(list);
                }
              : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ]),
      if (pick != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            pick.est
                ? 'Τυπικό βάρος (χωρίς φλούδα, κουκούτσι ή τσόφλι): γράφεται ως εκτίμηση.'
                : 'Με το δικό σου βάρος: δεν είναι εκτίμηση.',
            key: const ValueKey('piece-note'),
            style: TextStyle(fontSize: 12.5, color: c.textTertiary),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('unit-weigh'),
          onPressed: _weighOne,
          icon: const Icon(Icons.scale_outlined, size: 18),
          label: Text(widget.food.myUnit(widget.item.id) == null ? 'Ζύγισα ένα δικό μου' : 'Ζύγισα ξανά ένα'),
        ),
      ),
    ]);
  }
}

/// «Ζύγισα ένα»: πόσο ζυγίζει ένα κομμάτι. Το πεδίο ζει όσο ο διάλογος (και στο κλείσιμό του).
class WeighOneDialog extends StatefulWidget {
  const WeighOneDialog({super.key, this.initial});
  final double? initial;

  @override
  State<WeighOneDialog> createState() => _WeighOneDialogState();
}

class _WeighOneDialogState extends State<WeighOneDialog> {
  late final _ctl = TextEditingController(text: widget.initial == null ? '' : gramsField(widget.initial!));

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = validMyUnit(parseNumber(_ctl.text));
    return AlertDialog(
      title: const Text('Ζύγισα ένα'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Πόσο ζυγίζει ένα κομμάτι, όπως το τρως; Την επόμενη φορά διαλέγεις μόνο πόσα κομμάτια.',
            style: TextStyle(fontSize: 14, height: 1.35, color: Aigaio.of(context).textSecondary)),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('unit-weigh-field'),
          controller: _ctl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            suffixText: 'g',
            errorText: _ctl.text.isEmpty || v != null ? null : 'Από 1 έως 2.000 g',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Άκυρο')),
        FilledButton(
          key: const ValueKey('unit-weigh-save'),
          onPressed: v == null ? null : () => Navigator.pop(context, v),
          child: const Text('Αποθήκευση'),
        ),
      ],
    );
  }
}
