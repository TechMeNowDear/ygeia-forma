import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';

class BodyPage extends StatelessWidget {
  const BodyPage({super.key, required this.store});
  final HealthStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final c = Aigaio.of(context);
        final d = store.data;
        final body = d?.body ?? const <BodyMeasurement>[];
        final last = d?.latestBody;

        final skinNights = (d?.nights ?? const <Night>[]).where((n) => n.skinTemp != null).toList();
        final skinBase = d?.skinTempBaseline;

        final left = <Widget>[
          if (last == null)
            const EmptyCard(
              title: 'Δεν υπάρχει ζύγιση',
              text: 'Ζυγίσου στην InBody. Η μέτρηση φτάνει εδώ μέσω Samsung Health σε λίγα λεπτά.',
            )
          else
            _LatestCard(last: last, previous: d?.previousBody, now: d?.readAt ?? DateTime.now()),
          if (body.where((b) => b.weight != null).length >= 2)
            _chartCard(
              context,
              'Βάρος (kg)',
              [for (final b in body) if (b.weight != null) (b.time, b.weight!)],
              c.primary,
            ),
          if (body.where((b) => b.fatPct != null).length >= 2)
            _chartCard(
              context,
              'Λίπος (%)',
              [for (final b in body) if (b.fatPct != null) (b.time, b.fatPct!)],
              c.terracotta,
            ),
        ];

        final right = <Widget>[
          if (body.where((b) => b.smm != null).length >= 2)
            _chartCard(
              context,
              'Σκελετικοί μύες (kg)',
              [for (final b in body) if (b.smm != null) (b.time, b.smm!)],
              c.olive,
            ),
          if (body.isNotEmpty)
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionLabel('Ζυγίσεις'),
                  const SizedBox(height: 6),
                  for (final b in body.reversed.take(12))
                    InfoRow(
                      dayMonthYear(b.time),
                      [
                        if (b.weight != null) '${dec(b.weight!)} kg',
                        if (b.fatPct != null) '${dec(b.fatPct!)}%',
                        if (b.smm != null) 'μύες ${dec(b.smm!)}',
                      ].join(' · '),
                    ),
                ],
              ),
            ),
          if (skinNights.length >= 2)
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionLabel('Θερμοκρασία δέρματος στον ύπνο'),
                  const SizedBox(height: 4),
                  Text(
                    skinBase == null
                        ? 'Χρειάζονται λίγες ακόμα νύχτες για τον μέσο όρο σου.'
                        : 'Μέσος όρος σου ${dec(skinBase)} °C. Μια απότομη άνοδος συχνά προηγείται κρυώματος ή κούρασης.',
                    style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  LineChart(
                    points: [
                      for (final n in skinNights.length <= 30 ? skinNights : skinNights.sublist(skinNights.length - 30))
                        (n.date, n.skinTemp!),
                    ],
                    format: (v) => dec(v),
                    color: c.wheat,
                  ),
                ],
              ),
            ),
          const EmptyCard(
            title: 'Περισσότερα από την InBody',
            text: 'Σπλαχνικό λίπος, νερό σώματος και μετρήσεις ανά χέρι και πόδι έρχονται με τη σύνδεση με την InBody (Βήμα 5).',
          ),
        ];

        return PageFrame(
          title: 'Σώμα',
          subtitle: body.isEmpty ? null : '${body.length} ζυγίσεις στην InBody',
          onRefresh: () => store.refresh(),
          left: left,
          right: right,
        );
      },
    );
  }

  Widget _chartCard(BuildContext context, String title, List<(DateTime, double)> points, Color color) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(title),
          const SizedBox(height: 12),
          LineChart(points: points, color: color, format: (v) => dec(v), dateLabel: dayMonth),
        ],
      ),
    );
  }
}

class _LatestCard extends StatelessWidget {
  const _LatestCard({required this.last, required this.previous, required this.now});
  final BodyMeasurement last;
  final BodyMeasurement? previous;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final p = previous;

    String withDiff(double? value, double? before, String unit, {int digits = 1, bool lowerIsBetter = true}) {
      if (value == null) return '—';
      final base = '${dec(value, digits)} $unit';
      if (before == null) return base;
      final diff = value - before;
      if (diff.abs() < 0.05) return base;
      return '$base  (${signedDec(diff, digits)})';
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Τελευταία ζύγιση · ${relativeDay(last.time, now)} ${hm(last.time)}',
            style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: last.weight == null ? '—' : dec(last.weight!),
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: c.text),
                ),
                TextSpan(text: ' kg', style: TextStyle(color: c.textSecondary, fontSize: 16)),
              ],
            ),
          ),
          if (p != null)
            Text(
              'Σύγκριση με ${dayMonth(p.time)}',
              style: TextStyle(color: c.textSecondary, fontSize: 13),
            ),
          const SizedBox(height: 8),
          InfoRow('Βάρος', withDiff(last.weight, p?.weight, 'kg')),
          InfoRow('Λίπος', withDiff(last.fatPct, p?.fatPct, '%')),
          InfoRow('Μάζα λίπους', withDiff(last.fatKg, p?.fatKg, 'kg')),
          InfoRow('Σκελετικοί μύες', withDiff(last.smm, p?.smm, 'kg')),
          InfoRow('Άλιπη μάζα', withDiff(last.leanMass, p?.leanMass, 'kg')),
          if (last.bmr != null) InfoRow('Βασικός μεταβολισμός', '${thousands(last.bmr!)} kcal'),
          if (last.bmi != null) InfoRow('Δείκτης μάζας σώματος', dec(last.bmi!)),
          if (last.water != null) InfoRow('Νερό σώματος', '${dec(last.water!)} L'),
        ],
      ),
    );
  }
}
