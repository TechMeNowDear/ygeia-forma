import 'package:flutter/material.dart';

import '../food/food_model.dart';
import '../food/food_store.dart';
import '../format.dart';
import '../theme.dart';
import '../history.dart' show dateKey;
import 'food_add.dart' show MealPicker, entryDayLabel, undoSnackBarDuration;

// ---------------------------------------------------------------------------
// Αντιγραφή ή μετακίνηση (16/11): μία καταχώριση, ένα φαγητό ή όλο το γεύμα σε άλλη μέρα και γεύμα. Μέρες ως και σήμερα
// (το ημερολόγιο δεν γράφει μέλλον), ως 60 μέρες πίσω.
// ---------------------------------------------------------------------------

/// Πόσες μέρες πίσω δέχεται η επιλογή «Άλλη μέρα».
const transferDaysBack = 60;

typedef TransferChoice = ({DateTime day, Meal meal, bool move});

/// Ανοίγει την επιλογή και κάνει την αντιγραφή ή μετακίνηση της ομάδας [group] (με «Αναίρεση»).
Future<void> transferGroup(BuildContext context, FoodStore food, List<LogEntry> group, {DateTime Function()? clock}) async {
  if (group.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  final now = (clock ?? DateTime.now)();
  final from = DateTime.parse(group.first.day);
  final choice = await showModalBottomSheet<TransferChoice>(
    context: context,
    routeSettings: const RouteSettings(name: 'Αντιγραφή ή μετακίνηση'),
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => TransferSheet(from: from, meal: group.first.meal, today: dayOf(now), count: group.length),
  );
  if (choice == null) return;
  final before = [...group];
  final out = await food.transferEntries(group, choice.day, choice.meal, move: choice.move, now: now);
  if (out == null || out.isEmpty) {
    // 16/11 (έλεγχος): καθαρό μήνυμα όταν δεν βγήκε τίποτα (π.χ. τρόφιμο που δεν υπάρχει πια), όχι ένα παλιό σφάλμα.
    messenger.showSnackBar(SnackBar(
        content: Text(out == null
            ? (food.saveError ?? 'Δεν έγινε. Δοκίμασε ξανά.')
            : 'Δεν αντιγράφηκε τίποτα: τα τρόφιμα αυτά δεν υπάρχουν πια στη βάση.')));
    return;
  }
  final skipped = choice.move ? 0 : group.length - out.length;
  final where = '${entryDayLabel(choice.day, dayOf(now))}$dotJoin${mealLabel(choice.meal)}'
      '${skipped > 0 ? ' ($skipped δεν αντιγράφηκαν: τρόφιμα που δεν υπάρχουν πια)' : ''}';
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(choice.move ? 'Μετακινήθηκε: $where' : 'Αντιγράφηκε: $where'),
      persist: false,
      duration: undoSnackBarDuration,
      action: SnackBarAction(
        label: 'Αναίρεση',
        onPressed: () {
          if (!choice.move) {
            food.removeGroup(out);
            return;
          }
          // 16/11 (έλεγχος): γυρίζουν πίσω μόνο όσα δεν άλλαξαν στο μεταξύ (αλλιώς χανόταν μια διόρθωση ή ξαναερχόταν
          // κάτι που έσβησες μετά τη μετακίνηση).
          final now2 = {for (final e in food.entriesFor(choice.day)) e.id: e};
          final unchanged = {for (final e in out) if (identical(now2[e.id], e)) e.id};
          final back = [for (final e in before) if (unchanged.contains(e.id)) e];
          if (back.isNotEmpty) food.restoreGroup(back);
        },
      ),
    ));
}

/// Η επιλογή: αντιγραφή ή μετακίνηση, μέρα, γεύμα.
class TransferSheet extends StatefulWidget {
  const TransferSheet({super.key, required this.from, required this.meal, required this.today, this.count = 1});
  final DateTime from;
  final Meal meal;
  final DateTime today;
  final int count;

  @override
  State<TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<TransferSheet> {
  bool _move = false;
  late DateTime _day = widget.today;
  late Meal _meal = widget.meal;

  bool get _same => sameDay(_day, widget.from) && _meal == widget.meal;

  Future<void> _pickDay() async {
    final t = widget.today;
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(t.year, t.month, t.day - transferDaysBack),
      lastDate: t,
    );
    if (d != null) setState(() => _day = dayOf(d));
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final t = widget.today;
    final days = [t, DateTime(t.year, t.month, t.day - 1), DateTime(t.year, t.month, t.day - 2)];
    final custom = !days.any((d) => sameDay(d, _day));
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(widget.count == 1 ? 'Αντιγραφή ή μετακίνηση' : 'Αντιγραφή ή μετακίνηση (${widget.count} τρόφιμα)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text)),
            const SizedBox(height: 14),
            SegmentedButton<bool>(
              key: const ValueKey('transfer-mode'),
              segments: const [
                ButtonSegment(value: false, label: Text('Αντιγραφή'), icon: Icon(Icons.content_copy_rounded, size: 18)),
                ButtonSegment(value: true, label: Text('Μετακίνηση'), icon: Icon(Icons.drive_file_move_outline, size: 18)),
              ],
              selected: {_move},
              onSelectionChanged: (s) => setState(() => _move = s.first),
            ),
            const SizedBox(height: 16),
            Text('Μέρα', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.textSecondary)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final d in days)
                ChoiceChip(
                  key: ValueKey('transfer-day-${dateKey(d)}'),
                  label: Text(entryDayLabel(d, t)),
                  selected: sameDay(d, _day),
                  onSelected: (_) => setState(() => _day = d),
                ),
              ChoiceChip(
                key: const ValueKey('transfer-day-other'),
                label: Text(custom ? shortDayDate(_day) : 'Άλλη μέρα…'),
                selected: custom,
                onSelected: (_) => _pickDay(),
              ),
            ]),
            const SizedBox(height: 16),
            Text('Γεύμα', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.textSecondary)),
            const SizedBox(height: 6),
            MealPicker(value: _meal, onChanged: (m) => setState(() => _meal = m)),
            const SizedBox(height: 18),
            FilledButton(
              key: const ValueKey('transfer-go'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: _move && _same ? null : () => Navigator.pop(context, (day: _day, meal: _meal, move: _move)),
              child: Text(_move ? 'Μετακίνηση' : 'Αντιγραφή'),
            ),
          ]),
        ),
      ),
    );
  }
}
