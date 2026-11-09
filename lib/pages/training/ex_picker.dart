import 'package:flutter/material.dart';

import '../../exercise/ex_data.dart';
import '../../food/food_search.dart' show plain, phonetic;
import '../../format.dart' show upperGr;
import '../../theme.dart';

/// Διάλεξε άσκηση από τη βιβλιοθήκη («Ελεύθερη άσκηση», 9/11): αναζήτηση όπως στη σελίδα «Ασκήσεις»
/// (χωρίς τόνους, και με «φωνητική» γραφή), ανά ομάδα μυών. Όσες είναι ήδη στην προπόνηση έχουν ✓.
Future<String?> pickExercise(BuildContext context, {Set<String> already = const {}}) async {
  final lib = ExLibrary.loaded ?? await ExLibrary.load();
  if (!context.mounted) return null;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _Picker(lib: lib, already: already),
  );
}

/// Ταιριάζει η άσκηση με την αναζήτηση; (όνομα, αγγλικό όνομα, όργανο, ομάδα, μύες)
bool exMatches(Ex e, String q) {
  final t = q.trim();
  if (t.isEmpty) return true;
  final hay = [e.name, e.en, e.equip, e.groupName, for (final m in [...e.primary, ...e.secondary]) m.name].join(' ');
  if (plain(hay).contains(plain(t))) return true;
  return phonetic(hay).contains(phonetic(t));
}

class _Picker extends StatefulWidget {
  const _Picker({required this.lib, required this.already});
  final ExLibrary lib;
  final Set<String> already;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final shown = [for (final e in widget.lib.list) if (exMatches(e, _q.text)) e];
    final rows = <Widget>[];
    for (final g in exGroups.keys) {
      final list = [for (final e in shown) if (e.group == g) e];
      if (list.isEmpty) continue;
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 2),
        child: Text(upperGr(exGroups[g]!), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .6, color: c.textSecondary)),
      ));
      for (final e in list) {
        final inIt = widget.already.contains(e.id);
        rows.add(ListTile(
          key: ValueKey('pick-${e.id}'),
          contentPadding: EdgeInsets.zero,
          minVerticalPadding: 6,
          title: Text(e.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.text)),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.equip, style: TextStyle(fontSize: 13, color: c.textSecondary)),
            if (e.caution != null)
              Row(children: [
                Icon(Icons.warning_amber_rounded, size: 15, color: c.exercise),
                const SizedBox(width: 4),
                Flexible(child: Text('Σταδιακά, χωρίς πόνο', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.exercise))),
              ]),
          ]),
          trailing: inIt ? Icon(Icons.check_circle_rounded, color: c.good) : Icon(Icons.add_circle_outline_rounded, color: c.exercise),
          onTap: () => Navigator.of(context).pop(e.id),
        ));
      }
    }
    final h = MediaQuery.of(context).size.height;
    return SafeArea(
      child: Padding(
        // Το πληκτρολόγιο δεν κρύβει τα αποτελέσματα.
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: h * .85, maxWidth: 640),
          child: Column(key: const ValueKey('pick-sheet'), mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Πρόσθεσε άσκηση', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.text)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                key: const ValueKey('pick-search'),
                controller: _q,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Αναζήτηση: π.χ. στήθος, αλτήρες, κοιλιακοί',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _q.text.isEmpty
                      ? null
                      : IconButton(tooltip: 'Καθάρισμα', icon: const Icon(Icons.close_rounded), onPressed: () => setState(_q.clear)),
                ),
              ),
            ),
            Flexible(
              child: rows.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Καμία άσκηση με «${_q.text.trim()}».', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: c.textSecondary)),
                    )
                  : ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: rows),
            ),
          ]),
        ),
      ),
    );
  }
}
