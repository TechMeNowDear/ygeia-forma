import 'package:flutter/material.dart';

import '../food/food_model.dart';
import '../food/food_store.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';

// ---------------------------------------------------------------------------
// «Τελείωσα για σήμερα» και φρούτα/λαχανικά (16/11). Μια μέρα που λες ότι λείπουν γεύματα δεν μετρά στον εβδομαδιαίο
// έλεγχο θερμίδων (adaptive_check.dart, dailyIntake): αλλιώς θα φαινόταν «έφαγα λίγο» και ο στόχος θα κατέβαινε άδικα.
// ---------------------------------------------------------------------------

/// Η κάρτα στο τέλος της μέρας στο ημερολόγιο: φρούτα και λαχανικά, και «Τελείωσα για σήμερα».
class DayCard extends StatelessWidget {
  const DayCard({super.key, required this.food, required this.day, required this.entries, required this.today});
  final FoodStore food;
  final DateTime day;
  final List<LogEntry> entries;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final fv = fruitVegGrams(entries);
    final mark = food.dayMark(day);
    final enough = fv >= fruitVegTargetG;
    final share = (fv / fruitVegTargetG).clamp(0.0, 1.0);
    return AppCard(
      key: const ValueKey('day-card'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('Φρούτα και λαχανικά', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
          ),
          Text(
            '${thousands(fv.round())} / ${thousands(fruitVegTargetG.round())} g',
            key: const ValueKey('day-fruitveg'),
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: enough ? c.food : c.text, fontFeatures: tabular),
          ),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: share, minHeight: 8, color: c.food, backgroundColor: c.tint(c.food)),
        ),
        const SizedBox(height: 6),
        Text(
          enough ? 'Έφτασες τα 400 g της ημέρας.' : 'Τουλάχιστον 400 g τη μέρα, χωρίς πατάτες (ΠΟΥ).',
          style: TextStyle(fontSize: 13, color: c.textSecondary),
        ),
        if (entries.isNotEmpty) ...[
          const Hairline(vertical: 14),
          if (mark == null) ...[
            Text(
              today ? 'Έγραψες όλα όσα έφαγες σήμερα;' : 'Έγραψες όλα όσα έφαγες αυτή τη μέρα;',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.tonalIcon(
                key: const ValueKey('day-done'),
                onPressed: food.dishesRead ? () => food.setDayMark(day, DayMark.done) : null,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(today ? 'Τελείωσα για σήμερα' : 'Ναι, όλα'),
              ),
              OutlinedButton(
                key: const ValueKey('day-part'),
                onPressed: food.dishesRead ? () => food.setDayMark(day, DayMark.part) : null,
                child: const Text('Όχι, λείπουν γεύματα'),
              ),
            ]),
          ] else
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(mark == DayMark.done ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                  size: 22, color: mark == DayMark.done ? c.food : c.warn),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  mark == DayMark.done
                      ? 'Η μέρα γράφτηκε ολόκληρη.'
                      : 'Λείπουν γεύματα: η μέρα δεν μετρά στον εβδομαδιαίο έλεγχο θερμίδων.',
                  key: const ValueKey('day-mark-text'),
                  style: TextStyle(fontSize: 14.5, height: 1.35, color: c.text),
                ),
              ),
              TextButton(
                key: const ValueKey('day-mark-change'),
                onPressed: food.dishesRead ? () => food.setDayMark(day, null) : null,
                child: const Text('Αλλαγή'),
              ),
            ]),
        ],
      ]),
    );
  }
}

/// Στο σημερινό ημερολόγιο, μία φορά: «Η χθεσινή μέρα γράφτηκε ολόκληρη;» (μόνο αν χθες έχει καταχωρίσεις και δεν
/// απαντήθηκε). Η απάντηση μένει στη χθεσινή μέρα.
class YesterdayCard extends StatelessWidget {
  const YesterdayCard({super.key, required this.food, required this.today});
  final FoodStore food;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final y = DateTime(today.year, today.month, today.day - 1);
    if (!food.dishesRead || food.dayMark(y) != null || food.entriesFor(y).isEmpty) return const SizedBox.shrink();
    final c = Aigaio.of(context);
    return AppCard(
      key: const ValueKey('yesterday-card'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Χθες έγραψες όλα όσα έφαγες;', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: c.text)),
        const SizedBox(height: 4),
        Text(
          'Αν λείπουν γεύματα, η χθεσινή μέρα δεν μετρά στον εβδομαδιαίο έλεγχο θερμίδων. Έτσι ο στόχος δεν αλλάζει χωρίς λόγο.',
          style: TextStyle(fontSize: 13.5, height: 1.35, color: c.textSecondary),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.tonal(
            key: const ValueKey('yesterday-done'),
            onPressed: () => food.setDayMark(y, DayMark.done),
            child: const Text('Ναι, όλα'),
          ),
          OutlinedButton(
            key: const ValueKey('yesterday-part'),
            onPressed: () => food.setDayMark(y, DayMark.part),
            child: const Text('Όχι, λείπουν'),
          ),
          TextButton(
            key: const ValueKey('yesterday-open'),
            onPressed: () => food.setDay(y),
            child: const Text('Δες τη χθεσινή'),
          ),
        ]),
      ]),
    );
  }
}
