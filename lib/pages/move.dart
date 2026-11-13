import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';
import 'info_sheet.dart';
import 'metric_page.dart';
import '../reference.dart';
import '../history.dart';

/// Άσκηση › Κίνηση: βήματα, ενεργός χρόνος, θερμίδες, απόσταση, όροφοι.
/// Οι προπονήσεις (Hevy) θα μπουν εδώ ως δεύτερη καρτέλα, όταν φτιαχτούν.
class ExercisePage extends StatelessWidget {
  const ExercisePage({super.key, required this.store, this.now});
  final HealthStore store;

  /// Round 1 (S12-09 γ, αίτημα f8): το «τώρα» της σελίδας (στιγμιότυπα, δοκιμές)· χωρίς αυτό το ρολόι της συσκευής.
  final DateTime? now;

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
        // Οι τιμές της μέρας είναι της μέρας της ανάγνωσης: από αποθηκευμένη ανάγνωση άλλης μέρας, με ημερομηνία (A11).
        final today = now ?? DateTime.now();
        // UX U1/U8: η ημερομηνία σε δική της γραμμή («Σάβ 24/10»), ίδια μορφή παντού· ο τίτλος δεν κόβεται.
        String? dated(Object? value) => value == null || sameDay(d.readAt, today) ? null : shortDayDate(d.readAt);

        final last14 = d.steps.length <= 14 ? d.steps : d.steps.sublist(d.steps.length - 14);
        final floors14 = [for (var i = 13; i >= 0; i--) DateTime(d.readAt.year, d.readAt.month, d.readAt.day - i)];

        final stepsRef = stepsRange(store.profile, today);
        // Η τελευταία ΟΛΟΚΛΗΡΩΜΕΝΗ μέρα (όχι η σημερινή, που δεν έχει τελειώσει).
        DayValue? fullDay;
        for (final s in last14) {
          if (dayOf(s.day).isBefore(dayOf(today))) fullDay = s;
        }
        final stepsCard = AppCard(
          onTap: () => Navigator.of(context).push(MetricPage.route(store, K.steps)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Από αποθηκευμένη ανάγνωση άλλης μέρας: το λέει, να μη μοιάζει με τα σημερινά.
              CardHeader(
                icon: Icons.directions_walk_rounded,
                title: sameDay(d.readAt, today) ? 'Βήματα σήμερα' : 'Βήματα · ${shortDayDate(d.readAt)}',
                color: c.exercise,
                trailing: InfoButton(K.steps, range: stepsRef),
              ),
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
              // 7/11: εύρος με πηγή (Paluch 2022) για τη χθεσινή ολοκληρωμένη μέρα, όχι για τη μισή σημερινή.
              if (stepsRef != null && fullDay != null) ...[
                const SizedBox(height: 12),
                RangeNote(
                  value: fullDay.value,
                  range: stepsRef,
                  min: 0,
                  max: 14000,
                  color: c.exercise,
                ),
                const SizedBox(height: 2),
                Text(shortDayDate(fullDay.day),
                    style: TextStyle(color: c.textTertiary, fontSize: 12.5)),
              ],
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
                  // UX U8: η γραμμή είναι το «συνήθως» (μεσαία τιμή), όχι μέσος όρος.
                  '14 ημέρες · η διακεκομμένη γραμμή είναι το «συνήθως» σου (η μεσαία τιμή των 14 προηγούμενων ημερών)',
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
            subtitle: dated(activeMinutes),
            value: activeMinutes == null ? null : (activeMinutes < 60 ? '$activeMinutes' : hoursMinutes(activeMinutes)),
            unit: (activeMinutes != null && activeMinutes < 60) ? (activeMinutes == 1 ? 'λεπτό' : 'λεπτά') : null,
          ),
          StatCard(
            icon: Icons.local_fire_department_rounded,
            color: c.heart,
            // Κλινικός έλεγχος M9 (4/11): μεγάλο λάθος σε όλα τα ρολόγια, ειδικά στα βάρη (σημείωση κάτω από τις κάρτες).
            // Σύντομος τίτλος για τη μισή κάρτα· με ημερομηνία όταν η τιμή δεν είναι σημερινή (A11).
            title: 'Θερμίδες',
            subtitle: dated(calories),
            value: calories == null ? null : thousands(calories),
            unit: 'kcal',
            note: 'Εκτίμηση ρολογιού · ${activeCalories == null ? 'μαζί με τον βασικό μεταβολισμό' : 'από κίνηση ${thousands(activeCalories)} kcal'}',
          ),
          StatCard(
            icon: Icons.straighten_rounded,
            color: c.energy,
            title: 'Απόσταση',
            subtitle: dated(distance),
            value: distance == null ? null : dec(distance / 1000),
            unit: 'km',
          ),
          StatCard(
            icon: Icons.stairs_rounded,
            color: c.energy,
            title: 'Όροφοι',
            subtitle: dated(d.floors.isEmpty ? null : 0),
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

        final caloriesNote = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Θερμίδες: τα ρολόγια κάνουν μεγάλα λάθη, ειδικά στα βάρη. Δες τις μόνο ως τάση, όχι για να ισοφαρίσεις φαγητό.',
            style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.4),
          ),
        );

        return PageFrame(
          title: 'Άσκηση',
          onRefresh: () => store.refresh(),
          single: [stepsCard, ...stats, caloriesNote, floorsCard],
          // round1, U5-25: οι όροφοι δεξιά, κάτω από τα στοιχεία, ώστε οι δύο στήλες να έχουν περίπου ίδιο ύψος (πριν η
          // δεξιά τελείωνε ~350 dp νωρίτερα).
          left: [stepsCard],
          right: [...stats, caloriesNote, floorsCard],
        );
      },
    );
  }
}
