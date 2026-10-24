import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';
import 'day_heart_card.dart';

class HeartPage extends StatelessWidget {
  const HeartPage({super.key, required this.store});
  final HealthStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final c = Aigaio.of(context);
        final d = store.data;
        if (d == null || (d.heart.isEmpty && d.nights.isEmpty)) {
          return PageFrame(
            title: 'Καρδιά',
            onRefresh: () => store.refresh(),
            left: [
              EmptyCard(
                icon: Icons.favorite_rounded,
                color: c.heart,
                title: 'Δεν υπάρχουν παλμοί ακόμα',
                text: 'Φόρεσε το ρολόι. Οι παλμοί εμφανίζονται εδώ μόλις συγχρονιστεί το Samsung Health.',
              ),
            ],
          );
        }

        final rhrNights = d.nights.where((n) => n.sleepingHr != null).toList();
        final rhrPoints = [
          for (final n in rhrNights.length <= 30 ? rhrNights : rhrNights.sublist(rhrNights.length - 30))
            (n.date, n.sleepingHr!),
        ];
        final lastRhr = rhrNights.isEmpty ? null : rhrNights.last.sleepingHr;
        final base = d.restingHrBaseline;
        final today = d.heartRange(d.readAt);
        final latest = d.latestHeart;
        final oxNights = d.nights.where((n) => n.spo2Avg != null).toList().reversed.take(10).toList();

        Widget? trend;
        if (lastRhr != null && base != null) {
          final diff = (lastRhr - base).round();
          trend = diff == 0
              ? const TrendPill('Όπως ο μέσος όρος σου')
              : TrendPill(
                  '${diff.abs()} ${diff > 0 ? 'πάνω' : 'κάτω'} από τον μέσο όρο (${base.round()})',
                  up: diff > 0,
                  kind: diff >= 3 ? TrendKind.bad : (diff < 0 ? TrendKind.good : TrendKind.neutral),
                );
        }

        return PageFrame(
          title: 'Καρδιά',
          subtitle: 'Παλμοί, οξυγόνο και HRV',
          onRefresh: () => store.refresh(),
          left: [
            DayHeartCard(data: d),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CardHeader(icon: Icons.bedtime_rounded, title: 'Παλμοί στον ύπνο', color: c.sleep),
                  const SizedBox(height: 14),
                  if (lastRhr != null) BigValue('${lastRhr.round()}', unit: 'bpm', size: 34),
                  if (trend != null) ...[const SizedBox(height: 8), trend],
                  const SizedBox(height: 8),
                  Text(
                    'Ο μέσος όρος των παλμών σου όσο κοιμάσαι, κάθε νύχτα. Είναι συνήθως λίγο πιο χαμηλά από την ηρεμία όταν είσαι ξύπνιος.',
                    style: TextStyle(color: c.textSecondary, fontSize: 13.5, height: 1.4),
                  ),
                  if (rhrPoints.length >= 2) ...[
                    const SizedBox(height: 14),
                    LineChart(points: rhrPoints, format: (v) => v.round().toString(), color: c.sleep),
                  ],
                ],
              ),
            ),
          ],
          right: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CardHeader(icon: Icons.monitor_heart_rounded, title: 'Τελευταίες μετρήσεις σήμερα', color: c.heart),
                  const SizedBox(height: 8),
                  if (latest != null)
                    InfoRow('Τελευταία μέτρηση, ${hm(latest.start)}', '${latest.avg.round()} bpm'),
                  if (today != null) ...[
                    InfoRow('Χαμηλότεροι', '${today.$1.round()} bpm'),
                    InfoRow('Υψηλότεροι', '${today.$2.round()} bpm'),
                  ],
                  if (latest == null && today == null)
                    Text('Δεν υπάρχουν μετρήσεις σήμερα.', style: TextStyle(color: c.textSecondary)),
                ],
              ),
            ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CardHeader(icon: Icons.air_rounded, title: 'Οξυγόνο στον ύπνο', color: c.sleep),
                  const SizedBox(height: 8),
                  Text(
                    'Μέσο και χαμηλότερο ανά νύχτα. Μεμονωμένες χαμηλές τιμές είναι συχνά λάθος μέτρησης '
                    '(κίνηση, χαλαρό λουρί). Αν επαναλαμβάνονται, συζήτησέ το με γιατρό.',
                    style: TextStyle(color: c.textSecondary, fontSize: 13.5, height: 1.4),
                  ),
                  const Hairline(vertical: 12),
                  if (oxNights.isEmpty)
                    Text('Δεν υπάρχουν μετρήσεις οξυγόνου.', style: TextStyle(color: c.textSecondary)),
                  for (final n in oxNights)
                    InfoRow(
                      shortDayDate(n.date),
                      '${n.spo2Avg!.round()}% · χαμηλότερο ${n.spo2Min?.round() ?? '—'}%',
                      valueColor: (n.spo2Min ?? 100) < 88 ? c.bad : null,
                    ),
                ],
              ),
            ),
            EmptyCard(
              icon: Icons.timeline_rounded,
              color: c.sleep,
              title: 'HRV (μεταβλητότητα παλμών)',
              text: 'Η Samsung δεν το δίνει σε άλλες εφαρμογές. Θα το μετρά η δική μας εφαρμογή στο ρολόι (Βήμα 6).',
            ),
          ],
        );
      },
    );
  }
}
