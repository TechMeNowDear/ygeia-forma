import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../food/dishes.dart';
import '../food/food_model.dart';
import '../food/food_sources.dart';
import '../data.dart';
import '../food/food_store.dart';
import '../format.dart';
import '../goals.dart';
import '../theme.dart';
import '../widgets.dart';
import 'dishes.dart';
import 'food_add.dart';
import 'nutrition_goals.dart';
import 'day_close.dart';
import 'transfer.dart' show transferGroup;
import 'week.dart' show PlanDayCard, planHasOpenSlot;

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
        // Round8 (R8-A1-5): μέρα που πέρασε με τον στόχο που ίσχυε τότε ([day])· μέρα πριν από τους στόχους, το απλό σύνολο.
        final summary = goals != null && !beforeGoals(goals, day)
            ? GoalsSummaryCard(
                totals: totals,
                goals: goals,
                today: sameDay(day, today),
                health: health!,
                day: day,
                part: food.dayMark(day) == DayMark.part)
            : _SummaryCard(totals: totals);
        final cta = goals == null && health != null ? GoalsCtaCard(health: health!) : null;
        // Round9 (R9-A3-4): ούτε η κάρτα «Χοληστερίνη» σε μέρα πριν από τους στόχους (το πλάνο δεν υπήρχε ακόμα), όπως το
        // «Σύνολο ημέρας» από πάνω.
        final chol = goals != null && goals.doctor && !beforeGoals(goals, day)
            ? CholCard(food: food, goals: goals, day: day, today: today)
            : null;
        // Πρωτεΐνη ανά γεύμα (16/11): ο στόχος της μέρας μοιρασμένος στα γεύματα (τουλάχιστον 3: τόσα τρως).
        final mealProtein = goals == null || beforeGoals(goals, day) ? null : proteinPerMeal(goals.protein, entries);
        final planFirst = sameDay(day, today) && planHasOpenSlot(food, day);
        // Α22 (21/11): Πρωινό, Μεσημέρι, Σνακ, Βράδυ ([mealsShown]).
        final meals = [
          for (final m in mealsShown)
            _MealCard(
                food: food,
                meal: m,
                entries: entries.where((e) => e.meal == m).toList(),
                day: day,
                today: today,
                proteinTarget: mealProtein),
        ];

        return PageFrame(
          eyebrow: dayLabel == 'Σήμερα' || dayLabel == 'Χθες' ? '$dayLabel ·\u00A0${longDate(day)}' : longDate(day),
          title: 'Διατροφή',
          action: switcher,
          onRefresh: () async {},
          single: [
            // Απόφαση χρήστη 21/11 (Α21): όσο μένει γεύμα του προγράμματος να σημειωθεί σήμερα, το «Πρόγραμμα» πρώτο (στο
            // κινητό και στο κλειστό Fold ήταν μία οθόνη πιο κάτω· πάνω φαινόταν μόνο το «+ Φαγητό», που σε βάζει να ψάχνεις).
            if (planFirst) PlanDayCard(food: food, day: day, clock: now == null ? null : () => now!),
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
            if (planFirst && sameDay(day, today)) YesterdayCard(food: food, today: today),
            if (!planFirst) ...[
              if (sameDay(day, today)) YesterdayCard(food: food, today: today),
              PlanDayCard(food: food, day: day, clock: now == null ? null : () => now!),
            ],
            ...meals,
            DayCard(food: food, day: day, entries: entries, today: sameDay(day, today)),
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
            if (sameDay(day, today)) YesterdayCard(food: food, today: today),
            PlanDayCard(food: food, day: day, clock: now == null ? null : () => now!),
            ...meals,
          ],
          right: [
            summary,
            if (cta != null) cta,
            if (chol != null) chol,
            DayCard(food: food, day: day, entries: entries, today: sameDay(day, today)),
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
    final otherText = sum > 0 ? otherEnergyText(t, sum, other) : '';

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
                InfoRow(label, '${gramsText(g)} g${percent && sum > 0 ? ' ·\u00A0${(100 * part / sum).round()}%' : ''}', dot: color),
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
              otherText,
              key: const ValueKey('macro-other'),
              style: TextStyle(fontSize: 12, color: c.textTertiary),
            ),
          ),
      ],
    );
  }
}

/// «Άλλα 3% θερμίδων: φυτικές ίνες.» — τι είναι οι θερμίδες της πηγής που δεν βγαίνουν από πρωτεΐνη, υδατάνθρακες και
/// λιπαρά ([other] %, από [sum] kcal). Round7 (R7-A2-2): λέει «φυτικές ίνες» (2 kcal/g) και «αλκοόλ» (7 kcal/g) μόνο όταν
/// υπάρχουν· ό,τι δεν εξηγούν αυτά (π.χ. τα οξέα των τροφίμων, 3 kcal/g στον Κανονισμό ΕΕ 1169/2011, ή οι ειδικοί
/// συντελεστές ενέργειας της USDA) λέγεται «ό,τι άλλο μετρά η πηγή». Πριν, κοτόπουλο με φέτα (0,1 g ίνες) έγραφε «Άλλα 2%
/// θερμίδων: φυτικές ίνες».
String otherEnergyText(Totals t, double sum, int other) {
  final fiberPct = (100 * 2 * t.fiber / sum).round();
  final alcoholPct = (100 * 7 * t.alcohol / sum).round();
  final parts = [
    if (fiberPct >= 1) 'φυτικές ίνες',
    if (t.alcohol >= 0.05) 'αλκοόλ',
  ];
  if (parts.isEmpty || other - fiberPct - alcoholPct >= 1) parts.add('ό,τι άλλο μετρά η πηγή');
  final list = parts.length == 1 ? parts.first : '${parts.sublist(0, parts.length - 1).join(', ')} και ${parts.last}';
  return 'Άλλα $other% θερμίδων: $list.';
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
                title: 'Διατροφή ·\u00A0σήμερα',
                color: c.food,
                trailing: Icon(Icons.chevron_right_rounded, color: c.textTertiary),
              ),
              const SizedBox(height: 12),
              // Round 8 (R8-A2-3, f5): το ημερολόγιο δεν διαβάστηκε (ή διαβάζεται ακόμα): ποτέ «Μένουν 2.090 kcal · έφαγες 0».
              if (!food.loaded)
                Text(
                  food.error != null ? diaryNotReadText : 'Διαβάζεται το ημερολόγιο φαγητού…',
                  key: const ValueKey('today-food-not-read'),
                  style: TextStyle(fontSize: 15, color: c.textSecondary),
                )
              else if (goals != null) ...[
                () {
                  final left = kcalLeft(t.shownKcal, goals!.kcal, today: true);
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(left.label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: left.over ? c.warn : c.textSecondary)),
                    BigValue(left.value, unit: 'kcal', size: 40, color: left.over ? c.warn : null),
                    Text('έφαγες ${thousands(t.shownKcal)} ·\u00A0στόχος ${thousands(goals!.kcal)}',
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
  const _MealCard(
      {required this.food, required this.meal, required this.entries, required this.day, required this.today, this.proteinTarget});
  final FoodStore food;

  /// Πρωτεΐνη ανά γεύμα (16/11), g. null: χωρίς στόχους.
  final double? proteinTarget;
  final Meal meal;
  final List<LogEntry> entries;
  final DateTime day;
  final DateTime today;

  DateTime get prevDay => DateTime(day.year, day.month, day.day - 1);

  /// Round7 (R7-U2-8): «χθες» μόνο όταν βλέπεις τη σημερινή μέρα· σε παλιότερη μέρα, η μέρα που αντιγράφεται («Τετ 11/11»).
  /// Πριν, βλέποντας την Πέμπτη, το κουμπί «Όπως χθες» αντέγραφε την Τετάρτη (προχθές) και έλεγε «χθες».
  String get _fromLabel => sameDay(day, today) ? 'χθες' : shortDayDate(prevDay);

  Future<void> _copyFromPrevious(BuildContext context, DateTime from) async {
    final skipped = food.notCopyable(from, meal);
    final added = await food.copyMeal(from, meal, day);
    if (!context.mounted || added.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(
        '${mealLabel(meal)}: ${added.length == 1 ? '1 τρόφιμο' : '${added.length} τρόφιμα'} όπως $_fromLabel'
        // Έλεγχος 9/11 (Μ3): σβησμένα προϊόντα (π.χ. με λάθος τιμές) δεν ξαναγράφονται.
        '${skipped > 0 ? ' (χωρίς ${skipped == 1 ? '1 σβησμένο προϊόν' : '$skipped σβησμένα προϊόντα'})' : ''}',
      ),
      // Round8 (R8-U2-1): με «Αναίρεση» το μήνυμα δεν θα έκλεινε ποτέ μόνο του (Flutter ≥ 3.38).
      persist: false,
      duration: undoSnackBarDuration,
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

  /// Τα τρόφιμα του γεύματος γίνονται τα υλικά ενός νέου φαγητού (πιάτο, με τις ποσότητες που έφαγες). Η οθόνη του φαγητού
  /// ανοίγει για όνομα και έλεγχο· στο ημερολόγιο δεν αλλάζει τίποτα.
  Future<void> _saveAsDish(BuildContext context) async {
    final items = [for (final e in entries) DishItem(e.food.id, e.food.name, roundAmount(e.grams))];
    final d = await openDishEditor(context, food, items: items);
    if (d == null || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Αποθηκεύτηκε: ${d.name}. Θα το βρίσκεις πρώτο στο «+ Φαγητό».')));
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final t = Totals(entries);
    final previous = entries.isEmpty ? food.copyable(prevDay, meal) : const <LogEntry>[];
    final copyButton = previous.isEmpty
        ? null
        : TextButton.icon(
            key: ValueKey('copy-${meal.name}'),
            onPressed: food.loaded ? () => _copyFromPrevious(context, prevDay) : null,
            icon: const Icon(Icons.content_copy_rounded, size: 18),
            // Με τις τωρινές τιμές, όπως θα γραφτούν (όχι με τα παλιά αντίγραφα).
            label: Text(
                'Όπως $_fromLabel ·\u00A0${thousands(Totals([for (final e in previous) e.copyWith(food: food.currentOf(e.food))]).shownKcal)} kcal'),
          );
    // Απόφαση χρήστη 21/11 (Α22): γεύμα χωρίς τίποτα σε μία γραμμή (όνομα και «Προσθήκη»)· το «Όπως χθες», αν υπάρχει,
    // από κάτω. Πριν: μια ολόκληρη κάρτα για κάθε άδειο γεύμα (π.χ. το «Πρωινό» που δεν τρως, πρώτο κάθε μέρα).
    if (entries.isEmpty) {
      return AppCard(
        key: ValueKey('meal-empty-${meal.name}'),
        padding: const EdgeInsets.fromLTRB(18, 6, 6, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CardHeader(
              icon: mealIcon(meal),
              title: mealLabel(meal),
              color: c.food,
              trailing: TextButton.icon(
                onPressed: food.loaded ? () => openAddFood(context, food, meal: meal, day: day) : null,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Προσθήκη'),
              ),
            ),
            if (copyButton != null) Align(alignment: Alignment.centerLeft, child: copyButton),
          ],
        ),
      );
    }
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
              subtitle: entries.isEmpty || proteinTarget == null
                  ? null
                  : 'πρωτεΐνη ${gramsText(t.protein)} / ${proteinTarget!.round()} g',
              color: c.food,
              trailing: entries.isEmpty
                  ? null
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      // Με μεγάλα γράμματα (2×, 360 dp) οι θερμίδες μικραίνουν αντί να σπρώχνουν το κουμπί έξω.
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 110),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${thousands(t.shownKcal)} kcal',
                            maxLines: 1,
                            style: TextStyle(fontWeight: FontWeight.w700, color: c.text, fontFeatures: tabular),
                          ),
                        ),
                      ),
                      // Αντιγραφή ή μετακίνηση όλου του γεύματος (16/11).
                      IconButton(
                        key: ValueKey('meal-transfer-${meal.name}'),
                        tooltip: 'Αντιγραφή ή μετακίνηση του γεύματος',
                        visualDensity: VisualDensity.compact,
                        onPressed: food.loaded ? () => transferGroup(context, food, entries) : null,
                        icon: Icon(Icons.drive_file_move_outline, size: 20, color: c.textSecondary),
                      ),
                    ]),
            ),
          ),
          if (entries.isNotEmpty) const SizedBox(height: 4),
          // «Τα φαγητά μου» (15/11): τα υλικά μιας καταγραφής φαγητού σε μία γραμμή, στη θέση του πρώτου τους.
          for (final row in mealRows(entries))
            if (row.length > 1 || row.first.dish != null) _DishRow(food: food, group: row) else _EntryRow(food: food, entry: row.first),
          // Αν δεν χωράνε δίπλα δίπλα, το «Όπως χθες» πάει στην από κάτω γραμμή.
          Wrap(
            children: [
              TextButton.icon(
                onPressed: food.loaded ? () => openAddFood(context, food, meal: meal, day: day) : null,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(entries.isEmpty ? 'Προσθήκη' : 'Κι άλλο'),
              ),
              // «Τα φαγητά μου» (15/11): ό,τι έφαγες σε αυτό το γεύμα γίνεται φαγητό, για να το γράφεις με ένα πάτημα.
              if (mealRows(entries).length > 1 && food.dishesRead)
                TextButton.icon(
                  key: ValueKey('save-dish-${meal.name}'),
                  onPressed: () => _saveAsDish(context),
                  icon: const Icon(Icons.bookmark_add_outlined, size: 19),
                  label: const Text('Κράτα το ως φαγητό'),
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
                    // «Εκτίμηση» (16/11): η ποσότητα δεν ζυγίστηκε.
                    '${e.est ? 'περίπου ' : ''}${gramsText(e.grams)} ${e.food.unit} ·\u00A0πρωτεΐνη ${gramsText(e.total(Nk.protein))} g',
                    style: TextStyle(fontSize: 12.5, color: c.textSecondary, fontFeatures: tabular),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${e.est ? '≈\u00A0' : ''}${thousands(e.total(Nk.kcal).round())}',
              key: e.est ? ValueKey('est-${e.id}') : null,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text, fontFeatures: tabular),
            ),
          ],
        ),
      ),
    );
  }
}

/// Οι γραμμές ενός γεύματος: κάθε απλό τρόφιμο μόνο του, και όλα τα υλικά μιας καταγραφής φαγητού (ίδιο «grp») μαζί,
/// στη θέση του πρώτου τους. Οι [entries] με τη σειρά της ώρας.
List<List<LogEntry>> mealRows(List<LogEntry> entries) {
  final out = <List<LogEntry>>[];
  final byGroup = <String, List<LogEntry>>{};
  for (final e in entries) {
    final g = e.dish?.grp;
    if (g == null) {
      out.add([e]);
    } else if (byGroup[g] case final list?) {
      list.add(e);
    } else {
      final list = [e];
      byGroup[g] = list;
      out.add(list);
    }
  }
  return out;
}

/// Ένα φαγητό στο ημερολόγιο: όνομα, πόσο έφαγες, θερμίδες. Πάτημα = αλλαγή μερίδας, γεύματος ή διαγραφή.
class _DishRow extends StatelessWidget {
  const _DishRow({required this.food, required this.group});
  final FoodStore food;
  final List<LogEntry> group;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final tag = group.first.dish!;
    final t = Totals(group);
    final est = group.any((e) => e.est);
    final qty = tag.kind == DishKind.plate ? countText(group.length, 'υλικό', 'υλικά') : dishQtyText(tag.kind, tag.qty);
    return InkWell(
      key: ValueKey('dish-row-${tag.grp}'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => openDishEntry(context, food, group),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 9, 8, 9),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(dishIcon(tag.kind), size: 16, color: c.food),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        tag.name,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    '${est ? 'περίπου ' : ''}$qty ·\u00A0πρωτεΐνη ${gramsText(t.protein)} g',
                    style: TextStyle(fontSize: 12.5, color: c.textSecondary, fontFeatures: tabular),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${est ? '≈\u00A0' : ''}${thousands(t.shownKcal)}',
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
          // Round9 (R9-U2 ΒΕΛΤΙΩΣΗ-Α): ο σύνδεσμος σε μία γραμμή (πριν έμενε «άδειες ›» μόνο του στα 400 dp).
          'Τιμές: CIQUAL, USDA, Open Food Facts και οι ετικέτες σου. Πηγές\u00A0και\u00A0άδειες\u00A0›',
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

/// Πρωτεΐνη ανά γεύμα (16/11): ο στόχος της μέρας μοιρασμένος στα γεύματα της μέρας, τουλάχιστον 3 (τρία γεύματα την
/// ημέρα). Με ένα γεύμα γραμμένο το πρωί δεν βγαίνει ολόκληρος ο στόχος της μέρας σε αυτό.
double proteinPerMeal(int dayProtein, List<LogEntry> entries) {
  // Μετρούν τα γεύματα με τουλάχιστον 15% των θερμίδων της μέρας (έλεγχος 16/11: ένας καφές με γάλα στο «Πρωινό» δεν
  // είναι 4ο γεύμα που κατεβάζει τον στόχο όλων από 43 σε 33 g).
  final all = Totals(entries).kcal;
  final byMeal = <Meal, double>{};
  for (final e in entries) {
    byMeal[e.meal] = (byMeal[e.meal] ?? 0) + e.total(Nk.kcal);
  }
  final used = all <= 0 ? 0 : byMeal.values.where((k) => k >= all * 0.15).length;
  return dayProtein / (used < 3 ? 3 : used);
}
