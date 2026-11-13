import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../food/food_model.dart';
import '../food/food_sources.dart';
import '../data.dart';
import '../food/food_store.dart';
import '../format.dart';
import '../goals.dart';
import '../theme.dart';
import '../widgets.dart';
import 'food_add.dart';
import 'nutrition_goals.dart';

/// Χρώματα μακροθρεπτικών (ίδια παντού).
Color proteinColor(Aigaio c) => c.sleep;
Color carbsColor(Aigaio c) => c.move;
Color fatColor(Aigaio c) => c.heart;

IconData mealIcon(Meal m) => switch (m) {
      Meal.breakfast => Icons.free_breakfast_rounded,
      Meal.lunch => Icons.lunch_dining_rounded,
      Meal.dinner => Icons.dinner_dining_rounded,
      Meal.snack => Icons.cookie_rounded,
    };

/// Διατροφή: το ημερολόγιο της ημέρας.
class NutritionPage extends StatelessWidget {
  const NutritionPage({super.key, required this.food, this.health, this.now});
  final FoodStore food;

  /// Για τους στόχους (12/11). Χωρίς αυτό: η σελίδα όπως πριν, χωρίς στόχους.
  final HealthStore? health;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([food, if (health != null) health!]),
      builder: (context, _) {
        final c = Aigaio.of(context);
        final today = dayOf(now ?? DateTime.now());
        final day = food.day;
        final entries = food.entriesFor(day);
        final totals = Totals(entries);

        final dayLabel = sameDay(day, today)
            ? 'Σήμερα'
            : sameDay(day, DateTime(today.year, today.month, today.day - 1))
                ? 'Χθες'
                : shortDayDate(day);

        final switcher = Row(
          children: [
            _RoundButton(
              icon: Icons.chevron_left_rounded,
              tooltip: 'Προηγούμενη μέρα',
              onPressed: () => food.setDay(DateTime(day.year, day.month, day.day - 1)),
            ),
            Expanded(
              child: sameDay(day, today)
                  ? Text(
                      dayLabel,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text),
                    )
                  // Έλεγχος round1 (U3a-1, U3a-20): όταν το ημερολόγιο δείχνει άλλη μέρα, το λέει έντονα και με την
                  // ημερομηνία («Χθες · Πέμ 12/11»), και ένα πάτημα γυρίζει στο «Σήμερα» (πριν: ένα πάτημα «›» ανά μέρα).
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          entryDayLabel(day, today),
                          key: const ValueKey('diary-day'),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.warn),
                        ),
                        TextButton(
                          key: const ValueKey('diary-today'),
                          onPressed: () => food.setDay(today),
                          child: const Text('Πίσω στο Σήμερα'),
                        ),
                      ],
                    ),
            ),
            _RoundButton(
              icon: Icons.chevron_right_rounded,
              tooltip: 'Επόμενη μέρα',
              onPressed: day.isBefore(today) ? () => food.setDay(DateTime(day.year, day.month, day.day + 1)) : null,
            ),
          ],
        );

        if (!food.ready) {
          return PageFrame(
            eyebrow: dayLabel,
            title: 'Διατροφή',
            onRefresh: () async {},
            left: const [Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))],
          );
        }

        final goals = health?.goals;
        final summary = goals != null
            ? GoalsSummaryCard(totals: totals, goals: goals, today: sameDay(day, today), health: health!)
            : _SummaryCard(totals: totals);
        final cta = goals == null && health != null ? GoalsCtaCard(health: health!) : null;
        final chol = goals != null && goals.doctor ? CholCard(food: food, goals: goals, day: day, today: today) : null;
        final meals = [
          for (final m in Meal.values)
            _MealCard(food: food, meal: m, entries: entries.where((e) => e.meal == m).toList(), day: day),
        ];

        return PageFrame(
          eyebrow: dayLabel == 'Σήμερα' || dayLabel == 'Χθες' ? '$dayLabel · ${longDate(day)}' : longDate(day),
          title: 'Διατροφή',
          action: switcher,
          onRefresh: () async {},
          single: [
            if (food.error != null) _ErrorCard(food: food),
            if (food.saveError != null)
              EmptyCard(
                title: 'Δεν αποθηκεύτηκε',
                text: food.saveError!,
                icon: Icons.error_outline_rounded,
                buttonText: 'Εντάξει',
                onPressed: food.clearSaveError,
              ),
            summary,
            if (cta != null) cta,
            if (chol != null) chol,
            ...meals,
            _SourcesNote(color: c.textTertiary),
          ],
          left: [
            if (food.error != null) _ErrorCard(food: food),
            if (food.saveError != null)
              EmptyCard(
                title: 'Δεν αποθηκεύτηκε',
                text: food.saveError!,
                icon: Icons.error_outline_rounded,
                buttonText: 'Εντάξει',
                onPressed: food.clearSaveError,
              ),
            // UX U11: στο tablet/PC τα γεύματα αριστερά και η σύνοψη δεξιά. Το «+ Φαγητό» είναι κάτω δεξιά· η δεξιά στήλη
            // είναι κοντή, οπότε δεν κάθεται πάνω στις θερμίδες ενός φαγητού (πριν κάλυπτε το «375» του μεσημεριανού).
            ...meals,
          ],
          right: [
            summary,
            if (cta != null) cta,
            if (chol != null) chol,
            _SourcesNote(color: c.textTertiary),
          ],
        );
      },
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onPressed, required this.tooltip});
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: c.card,
        foregroundColor: c.text,
        disabledBackgroundColor: c.card.withValues(alpha: 0.5),
        disabledForegroundColor: c.textTertiary,
      ),
      icon: Icon(icon),
    );
  }
}

/// «τουλάχιστον 12 g» όταν κάποιο τρόφιμο δεν έχει τιμή γι' αυτό το θρεπτικό.
String _atLeast(Totals t, String key, String text) => (t.missing[key] ?? 0) > 0 ? 'τουλάχιστον $text' : text;

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.totals});
  final Totals totals;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final t = totals;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHeader(icon: Icons.restaurant_rounded, title: 'Σύνολο ημέρας', color: c.food),
          const SizedBox(height: 10),
          BigValue(thousands(t.shownKcal), unit: 'kcal', size: 44),
          const SizedBox(height: 14),
          MacroBreakdown(totals: t),
          const Hairline(vertical: 14),
          InfoRow('Φυτικές ίνες', _atLeast(t, Nk.fiber, '${gramsText(t.fiber)} g')),
          InfoRow('Σάκχαρα', _atLeast(t, Nk.sugars, '${gramsText(t.sugars)} g')),
          InfoRow('Κορεσμένα λιπαρά', _atLeast(t, Nk.satFat, '${gramsText(t.satFat)} g')),
          InfoRow('Αλάτι', _atLeast(t, Nk.salt, '${dec(t.salt, 1)} g')),
          // Έλεγχος 9/11 (Χ8): το αλκοόλ δίνει θερμίδες (7 kcal/g) που δεν είναι σε κανένα μακροθρεπτικό.
          if (t.alcohol >= 0.05) InfoRow('Αλκοόλ', '${gramsText(t.alcohol)} g'),
          if (t.missing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '«τουλάχιστον»: κάποια τρόφιμα δεν έχουν τιμή στην πηγή τους.',
                style: TextStyle(fontSize: 12.5, color: c.textTertiary),
              ),
            ),
        ],
      ),
    );
  }
}

/// Μπάρα ενέργειας ανά μακροθρεπτικό και τα γραμμάρια από κάτω.
class MacroBreakdown extends StatelessWidget {
  const MacroBreakdown({super.key, required this.totals, this.percent = true});
  final Totals totals;

  /// Και «24% θερμίδων» κάτω από κάθε τιμή.
  final bool percent;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final t = totals;
    // Ποσοστό των θερμίδων από κάθε μακροθρεπτικό (4/4/9 kcal ανά g). Παρονομαστής οι θερμίδες της πηγής
    // (μετρούν και ίνες, αλκοόλ), ποτέ λιγότερο από το άθροισμα των τριών, ώστε να μην ξεπερνά το 100%.
    final pk = t.protein * 4, ck = t.carbs * 4, fk = t.fat * 9;
    final sum = math.max(t.kcal, pk + ck + fk);
    // Έλεγχος 9/11 (Χ8): ό,τι λείπει ως το 100% είναι θερμίδες από ίνες (2 kcal/g) και αλκοόλ (7 kcal/g).
    final pp = sum > 0 ? (100 * pk / sum).round() : 0;
    final cp = sum > 0 ? (100 * ck / sum).round() : 0;
    final fp = sum > 0 ? (100 * fk / sum).round() : 0;
    final other = sum > 0 ? 100 - pp - cp - fp : 0;

    Widget macro(String label, double g, double kcalPart, Color color) => Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Round 1 (f9 · U1a-12): σταθερό ύψος γραμμής ετικέτας· όταν μία ετικέτα μικραίνει («Υδατάνθρ.» στα 750 dp),
              // οι τρεις τιμές από κάτω μένουν στην ίδια γραμμή.
              SizedBox(
                height: MediaQuery.textScalerOf(context).scale(17),
                child: Row(
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(label, maxLines: 1, style: TextStyle(fontSize: 13, color: c.textSecondary)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              // Ο αριθμός και το «g» πάντα μαζί· μικραίνουν αντί να σπάνε (σχέδια 9/11).
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: gramsText(g),
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: c.text),
                    ),
                    TextSpan(text: ' g', style: TextStyle(fontSize: 14, color: c.textSecondary)),
                  ]),
                  maxLines: 1,
                  style: const TextStyle(fontFeatures: tabular),
                ),
              ),
              if (percent)
                Text(
                  sum > 0 ? '${(100 * kcalPart / sum).round()}% θερμίδων' : '—',
                  style: TextStyle(fontSize: 12, color: c.textTertiary, fontFeatures: tabular),
                ),
            ],
          ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 10,
          child: sum <= 0
              ? DecoratedBox(
                  decoration: BoxDecoration(color: c.hairline, borderRadius: BorderRadius.circular(6)),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, part, color) in [(0, pk, proteinColor(c)), (1, ck, carbsColor(c)), (2, fk, fatColor(c))]) ...[
                      if (i > 0) const SizedBox(width: 3),
                      Expanded(
                        flex: (part * 100).round().clamp(1, 1 << 30),
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 14),
        // Πολύ μεγάλα γράμματα: μία γραμμή ανά μακροθρεπτικό («● Πρωτεΐνη …… 68 g»).
        // Έλεγχος round1 (U3a-7): το ίδιο και όταν η κάρτα είναι στενή (κάτω από 300 dp: δεξιά στήλη στο ανοιχτό Fold,
        // κινητό 360 dp). Εκεί οι τρεις στήλες δεν χωρούσαν: το «Υδατάνθρ.» μίκραινε μόνο του, η μεσαία στήλη καθόταν 2 px
        // πιο ψηλά και το «23% θερμίδων» έσπαγε σε δύο γραμμές.
        LayoutBuilder(builder: (context, box) {
          if (box.maxWidth < 300 || veryLargeText(context)) {
            return Column(key: const ValueKey('macro-rows'), children: [
              for (final (label, g, part, color) in [
                ('Πρωτεΐνη', t.protein, pk, proteinColor(c)),
                ('Υδατάνθρακες', t.carbs, ck, carbsColor(c)),
                ('Λιπαρά', t.fat, fk, fatColor(c)),
              ])
                InfoRow(label, '${gramsText(g)} g${percent && sum > 0 ? ' · ${(100 * part / sum).round()}%' : ''}', dot: color),
            ]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              macro('Πρωτεΐνη', t.protein, pk, proteinColor(c)),
              // UX U7: σύντομα, ίδιο μέγεθος με «Πρωτεΐνη»/«Λιπαρά» (όπως στο φύλλο ποσότητας).
              macro('Υδατάνθρ.', t.carbs, ck, carbsColor(c)),
              macro('Λιπαρά', t.fat, fk, fatColor(c)),
            ],
          );
        }),
        if (percent && other >= 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Άλλα $other% θερμίδων: ${t.alcohol >= 0.05 ? 'φυτικές ίνες και αλκοόλ' : 'φυτικές ίνες'}.',
              key: const ValueKey('macro-other'),
              style: TextStyle(fontSize: 12, color: c.textTertiary),
            ),
          ),
      ],
    );
  }
}

/// Η κάρτα της Διατροφής στο «Σήμερα»: τι έφαγα σήμερα και «+ Φαγητό».
class FoodTodayCard extends StatelessWidget {
  const FoodTodayCard({super.key, required this.food, required this.onOpen, this.now, this.goals});
  final FoodStore food;
  final VoidCallback onOpen;
  final DateTime? now;

  /// Με στόχους (12/11): «Μένουν X kcal» αντί για το σύνολο.
  final Goals? goals;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: food,
      builder: (context, _) {
        final c = Aigaio.of(context);
        final today = dayOf(now ?? DateTime.now());
        final entries = food.entriesFor(today);
        final t = Totals(entries);
        return AppCard(
          onTap: onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CardHeader(
                icon: Icons.restaurant_rounded,
                title: 'Διατροφή · σήμερα',
                color: c.food,
                trailing: Icon(Icons.chevron_right_rounded, color: c.textTertiary),
              ),
              const SizedBox(height: 12),
              if (goals != null) ...[
                () {
                  final left = kcalLeft(t.shownKcal, goals!.kcal, today: true);
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(left.label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: left.over ? c.warn : c.textSecondary)),
                    BigValue(left.value, unit: 'kcal', size: 40, color: left.over ? c.warn : null),
                    Text('έφαγες ${thousands(t.shownKcal)} · στόχος ${thousands(goals!.kcal)}',
                        style: TextStyle(fontSize: 13.5, color: c.textSecondary, fontFeatures: tabular)),
                  ]);
                }(),
                if (entries.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  MacroBreakdown(totals: t, percent: false),
                ],
              ] else if (entries.isEmpty)
                Text(
                  'Δεν έχεις γράψει τίποτα ακόμα σήμερα.',
                  style: TextStyle(fontSize: 15, color: c.textSecondary),
                )
              else ...[
                BigValue(thousands(t.shownKcal), unit: 'kcal', size: 40),
                const SizedBox(height: 14),
                MacroBreakdown(totals: t, percent: false),
              ],
              const SizedBox(height: 16),
              // Σχέδια 9/11: ένα γεμάτο κουμπί ανά οθόνη· το «+ Φαγητό» είναι απαλό, για να μην παλεύει με το «Ξεκίνα».
              FilledButton.icon(
                key: const ValueKey('today-add-food'),
                style: FilledButton.styleFrom(
                  backgroundColor: c.tint(c.food),
                  foregroundColor: c.food,
                  elevation: 0,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: food.loaded ? () => openAddFood(context, food, day: today) : null,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Φαγητό'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({required this.food, required this.meal, required this.entries, required this.day});
  final FoodStore food;
  final Meal meal;
  final List<LogEntry> entries;
  final DateTime day;

  DateTime get prevDay => DateTime(day.year, day.month, day.day - 1);

  Future<void> _copyFromPrevious(BuildContext context, DateTime from) async {
    final skipped = food.notCopyable(from, meal);
    final added = await food.copyMeal(from, meal, day);
    if (!context.mounted || added.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(
        '${mealLabel(meal)}: ${added.length == 1 ? '1 τρόφιμο' : '${added.length} τρόφιμα'} όπως χθες'
        // Έλεγχος 9/11 (Μ3): σβησμένα προϊόντα (π.χ. με λάθος τιμές) δεν ξαναγράφονται.
        '${skipped > 0 ? ' (χωρίς ${skipped == 1 ? '1 σβησμένο προϊόν' : '$skipped σβησμένα προϊόντα'})' : ''}',
      ),
      action: SnackBarAction(
        label: 'Αναίρεση',
        onPressed: () async {
          for (final e in added) {
            await food.remove(e);
          }
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final t = Totals(entries);
    final previous = entries.isEmpty ? food.copyable(prevDay, meal) : const <LogEntry>[];
    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: CardHeader(
              icon: mealIcon(meal),
              title: mealLabel(meal),
              color: c.food,
              trailing: entries.isEmpty
                  ? null
                  : Text(
                      '${thousands(t.shownKcal)} kcal',
                      style: TextStyle(fontWeight: FontWeight.w700, color: c.text, fontFeatures: tabular),
                    ),
            ),
          ),
          if (entries.isNotEmpty) const SizedBox(height: 4),
          for (final e in entries) _EntryRow(food: food, entry: e),
          // Αν δεν χωράνε δίπλα δίπλα, το «Όπως χθες» πάει στην από κάτω γραμμή.
          Wrap(
            children: [
              TextButton.icon(
                onPressed: food.loaded ? () => openAddFood(context, food, meal: meal, day: day) : null,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(entries.isEmpty ? 'Προσθήκη' : 'Κι άλλο'),
              ),
              if (entries.isEmpty && previous.isNotEmpty)
                TextButton.icon(
                  key: ValueKey('copy-${meal.name}'),
                  onPressed: food.loaded ? () => _copyFromPrevious(context, prevDay) : null,
                  icon: const Icon(Icons.content_copy_rounded, size: 18),
                  // Με τις τωρινές τιμές, όπως θα γραφτούν (όχι με τα παλιά αντίγραφα).
                  label: Text(
                      'Όπως χθες · ${thousands(Totals([for (final e in previous) e.copyWith(food: food.currentOf(e.food))]).shownKcal)} kcal'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.food, required this.entry});
  final FoodStore food;
  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final e = entry;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => openEditEntry(context, food, e),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 9, 8, 9),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Έλεγχος 9/11 (Χ9): 3 γραμμές, ώστε στη στενή στήλη να φαίνεται το κομμάτι που ξεχωρίζει
                  // το τρόφιμο (π.χ. «2%» στο τέλος του ονόματος του γιαουρτιού).
                  Text(
                    e.food.name,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${gramsText(e.grams)} ${e.food.unit} · πρωτεΐνη ${gramsText(e.total(Nk.protein))} g',
                    style: TextStyle(fontSize: 12.5, color: c.textSecondary, fontFeatures: tabular),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              thousands(e.total(Nk.kcal).round()),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text, fontFeatures: tabular),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourcesNote extends StatelessWidget {
  const _SourcesNote({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const ValueKey('food-sources'),
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.of(context).push(FoodSourcesScreen.route()),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Text(
          'Τιμές από CIQUAL 2025 (ANSES), USDA FoodData Central, Open Food Facts και ό,τι πέρασες από ετικέτες. '
          'Πηγές και άδειες ›',
          style: TextStyle(fontSize: 12, height: 1.4, color: color),
        ),
      ),
    );
  }
}

/// Κάρτα σφάλματος ανάγνωσης, με «Ξαναδοκίμασε» (έλεγχος 9/11, Χ6).
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.food});
  final FoodStore food;

  @override
  Widget build(BuildContext context) => EmptyCard(
        title: 'Πρόβλημα',
        text: food.loaded ? food.error! : '${food.error!} Μέχρι τότε η προσθήκη φαγητού είναι κλειδωμένη, για να μη γραφτεί κάτι διπλό.',
        icon: Icons.error_outline_rounded,
        buttonText: 'Ξαναδοκίμασε',
        onPressed: food.retry,
      );
}

/// «Πηγές και άδειες» της Διατροφής: έκδοση, ημερομηνία και άδεια κάθε πηγής (έλεγχος 9/11, Μ5· η Licence Ouverte
/// ζητά την ημερομηνία της τελευταίας ενημέρωσης, το Open Food Facts αναφορά της ODbL).
class FoodSourcesScreen extends StatelessWidget {
  const FoodSourcesScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'Πηγές διατροφής'),
        builder: (_) => const FoodSourcesScreen(),
      );

  @override
  Widget build(BuildContext context) => FoodTheme(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final c = Aigaio.of(context);
    Widget card(FoodSourceInfo s) => AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CardHeader(icon: Icons.verified_outlined, title: s.title, color: c.food),
              const SizedBox(height: 6),
              // Μεγάλα κείμενα: ετικέτα πάνω, τιμή από κάτω σε όλο το πλάτος (όχι InfoRow, που θέλει σύντομες τιμές).
              for (final (label, value) in [('Έκδοση', s.version), ('Άδεια', s.licence), if (s.link != null) ('Σελίδα', s.link!)])
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: TextStyle(fontSize: 12.5, color: c.textTertiary)),
                      Text(value, style: TextStyle(fontSize: 14.5, height: 1.35, color: c.text)),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Text(s.detail, style: TextStyle(fontSize: 13, height: 1.4, color: c.textSecondary)),
            ],
          ),
        );
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(backgroundColor: c.background, surfaceTintColor: Colors.transparent, title: const Text('Πηγές και άδειες')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 40),
            children: [
              Text(
                'Οι αριθμοί διατροφής έρχονται μόνο από αυτές τις βάσεις ή από την ετικέτα που περνάς εσύ. Ποτέ από AI.',
                style: TextStyle(fontSize: 14, height: 1.4, color: c.textSecondary),
              ),
              const SizedBox(height: 14),
              card(ciqualInfo),
              const SizedBox(height: 14),
              card(usdaInfo),
              const SizedBox(height: 14),
              card(offInfo),
            ],
          ),
        ),
      ),
    );
  }
}
