import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';

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
            left: const [
              EmptyCard(
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

        return PageFrame(
          title: 'Καρδιά',
          subtitle: 'Παλμοί, οξυγόνο και HRV',
          onRefresh: () => store.refresh(),
          left: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionLabel('Παλμοί ηρεμίας'),
                  const SizedBox(height: 4),
                  Text(
                    'Ο μέσος όρος των παλμών σου στον ύπνο. Όσο πιο χαμηλά, τόσο πιο ξεκούραστη η καρδιά.',
                    style: TextStyle(color: c.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  if (lastRhr != null)
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${lastRhr.round()}',
                            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: c.text),
                          ),
                          TextSpan(text: ' bpm', style: TextStyle(color: c.textSecondary)),
                          if (base != null)
                            TextSpan(
                              text: '   μέσος όρος ${base.round()}',
                              style: TextStyle(color: c.textSecondary),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (rhrPoints.length >= 2)
                    LineChart(
                      points: rhrPoints,
                      format: (v) => v.round().toString(),
                      color: c.terracotta,
                    ),
                ],
              ),
            ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionLabel('Σήμερα'),
                  const SizedBox(height: 6),
                  if (latest != null)
                    InfoRow('Τελευταία μέτρηση (${hm(latest.start)})', '${latest.avg.round()} bpm'),
                  if (today != null) ...[
                    InfoRow('Χαμηλότεροι', '${today.$1.round()} bpm'),
                    InfoRow('Υψηλότεροι', '${today.$2.round()} bpm'),
                  ],
                  if (latest == null && today == null)
                    Text('Δεν υπάρχουν μετρήσεις σήμερα.', style: TextStyle(color: c.textSecondary)),
                ],
              ),
            ),
          ],
          right: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionLabel('Οξυγόνο στον ύπνο'),
                  const SizedBox(height: 4),
                  Text(
                    'Μέσο και χαμηλότερο ανά νύχτα. Μεμονωμένες χαμηλές τιμές είναι συχνά λάθος μέτρησης '
                    '(κίνηση, χαλαρό λουρί). Αν επαναλαμβάνονται, συζήτησέ το με γιατρό.',
                    style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.35),
                  ),
                  const SizedBox(height: 8),
                  if (oxNights.isEmpty)
                    Text('Δεν υπάρχουν μετρήσεις οξυγόνου.', style: TextStyle(color: c.textSecondary)),
                  for (final n in oxNights)
                    InfoRow(
                      shortDayDate(n.date),
                      '${n.spo2Avg!.round()}% / ${n.spo2Min?.round() ?? '—'}%',
                      valueColor: (n.spo2Min ?? 100) < 88 ? c.terracotta : null,
                    ),
                ],
              ),
            ),
            const EmptyCard(
              title: 'HRV (μεταβλητότητα παλμών)',
              text: 'Η Samsung δεν το δίνει σε άλλες εφαρμογές. Θα το μετρά η δική μας εφαρμογή στο ρολόι (Βήμα 6).',
            ),
          ],
        );
      },
    );
  }
}
