import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../food/food_model.dart';
import '../food/food_store.dart';
import '../food/reminder.dart' show remindDefaultMinutes;
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
          // Με μεγάλα γράμματα ο αριθμός μικραίνει αντί να βγαίνει έξω από την κάρτα.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '${thousands(fv.round())} / ${thousands(fruitVegTargetG.round())} g',
                key: const ValueKey('day-fruitveg'),
                maxLines: 1,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: enough ? c.food : c.text, fontFeatures: tabular),
              ),
            ),
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
              // Χωρίς εικονίδιο: με μεγάλα γράμματα το κείμενο σπάει σε δύο γραμμές αντί να βγαίνει έξω.
              FilledButton.tonal(
                key: const ValueKey('day-done'),
                onPressed: food.dishesRead ? () => food.setDayMark(day, DayMark.done) : null,
                child: Text(today ? 'Τελείωσα για σήμερα' : 'Ναι, όλα', textAlign: TextAlign.center),
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

// ---------------------------------------------------------------------------
// Βραδινή υπενθύμιση (16/11): ναι/όχι και ώρα. Η λογική είναι στο food/reminder.dart.
// ---------------------------------------------------------------------------

String hhmm(int minutes) => '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';

/// Τι γράφει η γραμμή στο «Εγώ».
String reminderRowText(int? at) => at == null
    ? 'Κλειστή · μία το βράδυ, μόνο αν η μέρα έχει λίγο φαγητό'
    : 'Στις ${hhmm(at)}, μόνο αν η μέρα έχει λίγο φαγητό';

Future<void> openReminderSheet(BuildContext context, FoodStore food) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      routeSettings: const RouteSettings(name: 'Βραδινή υπενθύμιση'),
      builder: (_) => ReminderSheet(food: food),
    );

class ReminderSheet extends StatelessWidget {
  const ReminderSheet({super.key, required this.food});
  final FoodStore food;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return ListenableBuilder(
      listenable: food,
      builder: (context, _) {
        final at = food.remindAt;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Text('Βραδινή υπενθύμιση', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.text)),
                const SizedBox(height: 6),
                Text(
                  'Μία ειδοποίηση, μόνο αν ως εκείνη την ώρα η μέρα έχει λιγότερο από το 60% του στόχου γραμμένο και δεν έχεις '
                  'πατήσει «Τελείωσα για σήμερα». Τίποτα δεν τρέχει στο παρασκήνιο.',
                  style: TextStyle(fontSize: 14, height: 1.4, color: c.textSecondary),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  key: const ValueKey('remind-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Υπενθύμιση'),
                  value: at != null,
                  onChanged: !food.dishesRead
                      ? null
                      : (on) async {
                          if (on) await askNotifyPermission();
                          await food.setRemindAt(on ? remindDefaultMinutes : null);
                        },
                ),
                if (at != null)
                  ListTile(
                    key: const ValueKey('remind-time'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ώρα'),
                    trailing: Text(hhmm(at), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.primary)),
                    onTap: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(hour: at ~/ 60, minute: at % 60),
                        builder: (ctx, child) => MediaQuery(
                            data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
                      );
                      if (t != null) await food.setRemindAt(t.hour * 60 + t.minute);
                    },
                  ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// Η άδεια «Ειδοποιήσεις» (Android 13+), όπως στο διάλειμμα της προπόνησης.
Future<void> askNotifyPermission() async {
  try {
    await const MethodChannel('ygeia/training').invokeMethod<Object?>('askNotify');
  } on PlatformException {
    // Χωρίς άδεια η υπενθύμιση απλώς δεν φαίνεται.
  } on MissingPluginException {
    // Δοκιμές / όχι Android.
  }
}
