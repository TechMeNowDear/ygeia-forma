import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../heart_day.dart';
import '../theme.dart';
import '../widgets.dart';

/// «Παλμοί μέσα στη μέρα» (δοκιμαστικό): ηρεμία ξύπνιος, μέσος όρος ημέρας, ανά κατάσταση.
class DayHeartCard extends StatefulWidget {
  const DayHeartCard({super.key, required this.data});
  final Dashboard data;

  @override
  State<DayHeartCard> createState() => _DayHeartCardState();
}

class _DayHeartCardState extends State<DayHeartCard> {
  int _dayOffset = 0; // 0 = σήμερα, 1 = χθες
  bool _showMethod = false;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final d = widget.data;
    final day = dayOf(d.readAt).subtract(Duration(days: _dayOffset));
    final h = d.heartForDay(day);

    final header = Row(
      children: [
        Expanded(child: CardHeader(icon: Icons.monitor_heart_rounded, title: 'Παλμοί μέσα στη μέρα', color: c.heart)),
        const TrendPill('Δοκιμαστικό'),
      ],
    );

    final toggle = SegmentedButton<int>(
      segments: const [
        ButtonSegment(value: 0, label: Text('Σήμερα')),
        ButtonSegment(value: 1, label: Text('Χθες')),
      ],
      selected: {_dayOffset},
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: c.tint(c.heart),
        selectedForegroundColor: c.heart,
        side: BorderSide(color: c.hairline),
        textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w600),
      ),
      onSelectionChanged: (s) => setState(() => _dayOffset = s.first),
    );

    if (!d.hasStepCoverage(day) || d.stepsByMinute.isEmpty) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 12),
            Text(
              'Χρειάζονται βήματα ανά λεπτό από το Samsung Health για να ξέρω πότε ήσουν ακίνητος και πότε περπατούσες. '
              'Έλεγξε ότι έχεις δώσει άδεια για τα βήματα (Ρυθμίσεις › Άδειες Samsung Health).',
              style: TextStyle(color: c.textSecondary, fontSize: 14, height: 1.4),
            ),
          ],
        ),
      );
    }

    if (h == null) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 12),
            toggle,
            const SizedBox(height: 12),
            Text('Δεν υπάρχουν μετρήσεις παλμών για αυτή τη μέρα.', style: TextStyle(color: c.textSecondary)),
          ],
        ),
      );
    }

    String valueOf(HeartFigure f) => f.value == null ? 'λίγα δεδομένα' : '${f.value!.round()} bpm';
    String timeOf(HeartFigure f) => f.minutes < 1 ? 'καθόλου χρόνος' : 'από ${hoursMinutes(f.minutes.round())}';

    Widget bigFigure(String label, HeartFigure f) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: c.textSecondary, fontSize: 13)),
              const SizedBox(height: 4),
              if (f.value != null)
                BigValue('${f.value!.round()}', unit: 'bpm', size: 30)
              else
                Text('λίγα δεδομένα', style: TextStyle(color: c.textTertiary, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(timeOf(f), style: TextStyle(color: c.textTertiary, fontSize: 12.5)),
            ],
          ),
        );

    Widget bandRow(HeartBand b) {
      final f = h.bands[b]!;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bandLabel(b), style: TextStyle(color: c.text, fontSize: 15, fontWeight: FontWeight.w600)),
                  Text(
                    '${bandHint(b)} · ${timeOf(f)}',
                    style: TextStyle(color: c.textTertiary, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              valueOf(f),
              style: TextStyle(
                color: f.value == null ? c.textTertiary : c.text,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                fontFeatures: tabular,
              ),
            ),
          ],
        ),
      );
    }

    final recent = d.recentHeartDays(7).where((x) => x.resting.value != null).toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 14),
          toggle,
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              bigFigure('Ηρεμία, ξύπνιος', h.resting),
              bigFigure('Μέσος όρος ημέρας', h.awake),
            ],
          ),
          const Hairline(vertical: 14),
          for (final b in HeartBand.values) bandRow(b),
          if (recent.length >= 2) ...[
            const Hairline(vertical: 14),
            Text('Ηρεμία ξύπνιος, τελευταίες μέρες', style: TextStyle(color: c.textSecondary, fontSize: 13)),
            const SizedBox(height: 8),
            LineChart(
              height: 130,
              points: [for (final x in recent) (x.day, x.resting.value!)],
              format: (v) => v.round().toString(),
              color: c.heart,
              dateLabel: (dt) => weekdayShort(dt),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _showMethod = !_showMethod),
              icon: Icon(_showMethod ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20),
              label: const Text('Πώς υπολογίστηκε'),
            ),
          ),
          if (_showMethod) _Method(h: h),
        ],
      ),
    );
  }
}

class _Method extends StatelessWidget {
  const _Method({required this.h});
  final DayHeart h;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final style = TextStyle(color: c.textSecondary, fontSize: 13.5, height: 1.45);
    final interval = h.typicalInterval;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoRow('Μετρήσεις παλμών', '${h.samples}'),
          if (interval != null)
            InfoRow(
              'Διάρκεια κάθε μέτρησης',
              interval < 1.5 ? '1 λεπτό' : '${dec(interval, interval < 10 ? 1 : 0)} λεπτά',
            ),
          InfoRow('Εξαιρέθηκε ύπνος', hoursMinutes(h.excludedSleepMinutes.round())),
          InfoRow('Εξαιρέθηκε άσκηση', hoursMinutes(h.excludedExerciseMinutes.round())),
          const SizedBox(height: 8),
          Text(
            'Η κατάσταση βγαίνει από τα βήματα στο ίδιο διάστημα με κάθε μέτρηση. '
            'Ηρεμία είναι η μεσαία τιμή όταν δεν έκανες ούτε βήμα, ούτε τα 20 λεπτά πριν. '
            'Κάτω από 30 λεπτά δεδομένων δεν δείχνω τιμή. '
            '«Ακινησία» σημαίνει χωρίς βήματα: από τα βήματα δεν ξεχωρίζει το κάθισμα από την ορθοστασία, '
            'ούτε τα βάρη αν δεν τα ξεκινήσεις ως άσκηση στο ρολόι.',
            style: style,
          ),
          const SizedBox(height: 8),
          Text(
            'Για έλεγχο: σύγκρινε την «Ηρεμία, ξύπνιος» με τους παλμούς ηρεμίας του Samsung Health και πες στο Claude τη διαφορά.',
            style: style.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
