import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';

class MovePage extends StatelessWidget {
  const MovePage({super.key, required this.store});
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
            title: 'Κίνηση',
            onRefresh: () => store.refresh(),
            left: [
              EmptyCard(
                icon: Icons.directions_walk_rounded,
                color: c.move,
                title: 'Δεν υπάρχουν δεδομένα ακόμα',
                text: 'Σύνδεσε το Samsung Health από το «Σήμερα».',
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
        final floors14 = [
          for (var i = 13; i >= 0; i--) d.readAt.subtract(Duration(days: i)),
        ];

        return PageFrame(
          title: 'Κίνηση',
          subtitle: 'Βήματα, δραστηριότητα και θερμίδες',
          onRefresh: () => store.refresh(),
          left: [
            ...pairUp([
              StatCard(
                icon: Icons.directions_walk_rounded,
                color: c.move,
                title: 'Βήματα σήμερα',
                value: steps == null ? null : thousands(steps),
                note: d.stepsBaseline == null ? null : 'Μέσος όρος ${thousands(d.stepsBaseline!)}',
              ),
              StatCard(
                icon: Icons.timer_rounded,
                color: c.move,
                title: 'Ενεργός χρόνος',
                value: activeMinutes == null ? null : hoursMinutes(activeMinutes),
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
                value: floorsToday == null ? '0' : floorsToday.round().toString(),
              ),
              StatCard(
                icon: Icons.local_fire_department_rounded,
                color: c.heart,
                title: 'Θερμίδες που έκαψες',
                value: calories == null ? null : thousands(calories),
                unit: 'kcal',
                note: 'Μαζί με τον βασικό μεταβολισμό',
              ),
              StatCard(
                icon: Icons.bolt_rounded,
                color: c.heart,
                title: 'Από κίνηση',
                value: activeCalories == null ? null : thousands(activeCalories),
                unit: 'kcal',
              ),
            ]),
          ],
          right: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CardHeader(icon: Icons.bar_chart_rounded, title: 'Βήματα, 14 ημέρες', color: c.move),
                  const SizedBox(height: 8),
                  Text(
                    d.stepsBaseline == null
                        ? ''
                        : 'Μέσος όρος εβδομάδας ${thousands(d.stepsBaseline!)} (διακεκομμένη γραμμή)',
                    style: TextStyle(color: c.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  BarChart(
                    values: [for (final s in last14) s.value],
                    labels: [for (final s in last14) weekdayShort(s.day)],
                    average: d.stepsBaseline,
                    valueLabel: (v) => thousands(v),
                    color: c.move,
                  ),
                ],
              ),
            ),
            AppCard(
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
            ),
          ],
        );
      },
    );
  }
}
