import 'package:flutter/material.dart';

import '../food/food_model.dart';
import '../food/food_store.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';
import 'food_add.dart';

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
  const NutritionPage({super.key, required this.food, this.now});
  final FoodStore food;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: food,
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
              child: Text(
                dayLabel,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text),
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

        final summary = _SummaryCard(totals: totals);
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
            if (food.error != null) EmptyCard(title: 'Πρόβλημα', text: food.error!),
            summary,
            ...meals,
            _SourcesNote(color: c.textTertiary),
          ],
          left: [
            if (food.error != null) EmptyCard(title: 'Πρόβλημα', text: food.error!),
            summary,
            _SourcesNote(color: c.textTertiary),
          ],
          right: meals,
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
          BigValue(kcalText(t.kcal), unit: 'kcal', size: 44),
          const SizedBox(height: 14),
          MacroBreakdown(totals: t),
          const Hairline(vertical: 14),
          InfoRow('Φυτικές ίνες', '${gramsText(t.fiber)} g'),
          InfoRow('Σάκχαρα', '${gramsText(t.sugars)} g'),
          InfoRow('Αλάτι', '${dec(t.salt, 1)} g'),
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
    // Ποσοστό ενέργειας από κάθε μακροθρεπτικό (4/4/9 kcal ανά g).
    final pk = t.protein * 4, ck = t.carbs * 4, fk = t.fat * 9;
    final sum = pk + ck + fk;

    Widget macro(String label, double g, double kcalPart, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: gramsText(g),
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: c.text),
                  ),
                  TextSpan(text: ' g', style: TextStyle(fontSize: 14, color: c.textSecondary)),
                ]),
                style: const TextStyle(fontFeatures: tabular),
              ),
              if (percent)
                Text(
                  sum > 0 ? '${(100 * kcalPart / sum).round()}% θερμίδων' : '—',
                  style: TextStyle(fontSize: 12, color: c.textTertiary, fontFeatures: tabular),
                ),
            ],
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            macro('Πρωτεΐνη', t.protein, pk, proteinColor(c)),
            macro('Υδατάνθρακες', t.carbs, ck, carbsColor(c)),
            macro('Λίπος', t.fat, fk, fatColor(c)),
          ],
        ),
      ],
    );
  }
}

/// Η κάρτα της Διατροφής στο «Σήμερα»: τι έφαγα σήμερα και «+ Φαγητό».
class FoodTodayCard extends StatelessWidget {
  const FoodTodayCard({super.key, required this.food, required this.onOpen, this.now});
  final FoodStore food;
  final VoidCallback onOpen;
  final DateTime? now;

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
              if (entries.isEmpty)
                Text(
                  'Δεν έχεις γράψει τίποτα ακόμα σήμερα.',
                  style: TextStyle(fontSize: 15, color: c.textSecondary),
                )
              else ...[
                BigValue(kcalText(t.kcal), unit: 'kcal', size: 40),
                const SizedBox(height: 14),
                MacroBreakdown(totals: t, percent: false),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Aigaio.foodSolid,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => openAddFood(context, food, day: today),
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

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final t = Totals(entries);
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
                      '${kcalText(t.kcal)} kcal',
                      style: TextStyle(fontWeight: FontWeight.w700, color: c.text, fontFeatures: tabular),
                    ),
            ),
          ),
          if (entries.isNotEmpty) const SizedBox(height: 4),
          for (final e in entries) _EntryRow(food: food, entry: e),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => openAddFood(context, food, meal: meal, day: day),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: Text(entries.isEmpty ? 'Προσθήκη' : 'Κι άλλο'),
            ),
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
                  Text(
                    e.food.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${gramsText(e.grams)} g · πρωτεΐνη ${gramsText(e.total(Nk.protein))} g',
                    style: TextStyle(fontSize: 12.5, color: c.textSecondary, fontFeatures: tabular),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              kcalText(e.total(Nk.kcal)),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        'Τιμές από CIQUAL 2025 (ANSES), USDA FoodData Central, Open Food Facts και ό,τι πέρασες από ετικέτες.',
        style: TextStyle(fontSize: 12, height: 1.4, color: color),
      ),
    );
  }
}
