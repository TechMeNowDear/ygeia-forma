import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';

/// Άσκηση › Κίνηση: βήματα, ενεργός χρόνος, θερμίδες, απόσταση, όροφοι.
/// Οι προπονήσεις (Hevy) θα μπουν εδώ ως δεύτερη καρτέλα, όταν φτιαχτούν.
class ExercisePage extends StatelessWidget {
  const ExercisePage({super.key, required this.store});
  final HealthStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final c = Aigaio.of(context);
        final d = store.data;
        if (d == null) {
          return PageFrame(
            title: 'Άσκηση',
            onRefresh: () => store.refresh(),
            left: [
              EmptyCard(
                icon: Icons.directions_walk_rounded,
                color: c.exercise,
                title: 'Δεν υπάρχουν ακόμα δεδομένα',
                text: 'Τράβηξε προς τα κάτω για ανανέωση από το Samsung Health.',
              ),
            ],
          );
        }

        final a = d.activity;
        final steps = d.todaySteps;
        final distance = (a['distance'] as num?)?.toDouble();
        final activeMinutes = (a['activeMinutes'] as num?)?.toInt();
        final calories = (a['calories'] as num?)?.toDouble();
        final activeCalories = (a['activeCalories'] as num?)?.toDouble();
        final floorsToday = d.valueFor(d.floors, d.readAt)?.value;

        final last14 = d.steps.length <= 14 ? d.steps : d.steps.sublist(d.steps.length - 14);
        final floors14 = [for (var i = 13; i >= 0; i--) DateTime(d.readAt.year, d.readAt.month, d.readAt.day - i)];

        final stepsCard = AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CardHeader(icon: Icons.directions_walk_rounded, title: 'Βήματα σήμερα', color: c.exercise),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  BigValue(steps == null ? '—' : thousands(steps), size: 44),
                  if (d.stepsBaseline != null) ...[
                    const SizedBox(width: 10),
                    Text(
                      'συνήθως ${thousands(d.stepsBaseline!)}',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.textSecondary),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              BarChart(
                values: [for (final s in last14) s.value],
                labels: [for (final s in last14) weekdayShort(s.day)],
                average: d.stepsBaseline,
                valueLabel: (v) => thousands(v),
                color: c.exercise,
              ),
              if (d.stepsBaseline != null) ...[
                const SizedBox(height: 8),
                Text(
                  '14 ημέρες · η διακεκομμένη γραμμή είναι ο μέσος όρος των 7 προηγούμενων',
                  style: TextStyle(color: c.textSecondary, fontSize: 12.5),
                ),
              ],
            ],
          ),
        );

        final stats = pairUp([
          StatCard(
            icon: Icons.timer_rounded,
            color: c.exercise,
            title: 'Ενεργός χρόνος',
            value: activeMinutes == null ? null : (activeMinutes < 60 ? '$activeMinutes' : hoursMinutes(activeMinutes)),
            unit: (activeMinutes != null && activeMinutes < 60) ? (activeMinutes == 1 ? 'λεπτό' : 'λεπτά') : null,
          ),
          StatCard(
            icon: Icons.local_fire_department_rounded,
            color: c.heart,
            title: 'Θερμίδες που έκαψες',
            value: calories == null ? null : thousands(calories),
            unit: 'kcal',
            note: activeCalories == null ? 'Μαζί με τον βασικό μεταβολισμό' : 'Από κίνηση ${thousands(activeCalories)} kcal',
          ),
          StatCard(
            icon: Icons.straighten_rounded,
            color: c.energy,
            title: 'Απόσταση',
            value: distance == null ? null : dec(distance / 1000),
            unit: 'km',
          ),
          StatCard(
            icon: Icons.stairs_rounded,
            color: c.energy,
            title: 'Όροφοι',
            // Χωρίς καθόλου δεδομένα ορόφων: «—»· αλλιώς μέρα χωρίς ορόφους = 0.
            value: d.floors.isEmpty ? null : (floorsToday ?? 0).round().toString(),
          ),
        ]);

        final floorsCard = AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CardHeader(icon: Icons.stairs_rounded, title: 'Όροφοι, 14 ημέρες', color: c.energy),
              const SizedBox(height: 12),
              BarChart(
                height: 110,
                values: [for (final day in floors14) d.valueFor(d.floors, day)?.value ?? 0],
                labels: [for (final day in floors14) weekdayShort(day)],
                valueLabel: (v) => v.round().toString(),
                color: c.energy,
              ),
            ],
          ),
        );

        return PageFrame(
          title: 'Άσκηση',
          onRefresh: () => store.refresh(),
          single: [stepsCard, ...stats, floorsCard],
          left: [stepsCard, floorsCard],
          right: stats,
        );
      },
    );
  }
}
