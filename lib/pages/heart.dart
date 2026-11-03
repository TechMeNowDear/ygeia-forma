import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../history.dart';
import '../oura/oura_view.dart';
import '../oxygen_note.dart';
import '../sources.dart';
import '../theme.dart';
import '../widgets.dart';
import 'oxygen_widgets.dart';
import 'source_widgets.dart';

class HeartPage extends StatelessWidget {
  const HeartPage({super.key, required this.store, this.now});
  final HealthStore store;

  /// Για τα στιγμιότυπα δοκιμών.
  final DateTime? now;

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
              if (d != null && d.failed.contains('heart'))
                EmptyCard(
                  icon: Icons.favorite_rounded,
                  color: c.heart,
                  title: 'Οι παλμοί δεν διαβάστηκαν τώρα',
                  text: 'Η Samsung δεν τους έδωσε αυτή τη φορά. Τράβηξε την οθόνη προς τα κάτω για να ξαναδοκιμάσεις.',
                )
              else
                EmptyCard(
                  icon: Icons.favorite_rounded,
                  color: c.heart,
                  title: 'Δεν υπάρχουν παλμοί ακόμα',
                  text: 'Φόρεσε το ρολόι. Οι παλμοί εμφανίζονται εδώ μόλις συγχρονιστεί το Samsung Health.',
                ),
            ],
          );
        }

        // Παλμοί ύπνου: ΜΙΑ πηγή. Μετά τη σύνδεση του Oura μόνο οι νύχτες του Oura (από το ιστορικό, με τα
        // κλειδιά του), με σύγκριση μόνο με νύχτες του Oura· πριν, όπως πάντα από το ρολόι.
        final day = dayOf(now ?? d.readAt);
        final ouraHr = store.plan.nightSource(day) != Source.watch;
        final List<(DateTime, double)> rhrPoints;
        final double? lastRhr;
        final double? base;
        if (ouraHr) {
          rhrPoints = planSeries(store.history, store.plan, K.sleepHr, DateTime(day.year, day.month, day.day - 29), day).points;
          final b = rhrPoints.isEmpty ? null : ouraBaseline(store.history, store.plan, K.sleepHr, rhrPoints.last.$1);
          lastRhr = rhrPoints.isEmpty ? null : rhrPoints.last.$2;
          base = b?.usual;
        } else {
          final rhrNights = d.nights.where((n) => n.sleepingHr != null).toList();
          rhrPoints = [
            for (final n in rhrNights.length <= 30 ? rhrNights : rhrNights.sublist(rhrNights.length - 30))
              (n.date, n.sleepingHr!),
          ];
          lastRhr = rhrNights.isEmpty ? null : rhrNights.last.sleepingHr;
          // Το «συνηθισμένο» από τις νύχτες ΠΡΙΝ από αυτή που δείχνουμε (έλεγχος υπολογισμών F8).
          base = rhrNights.isEmpty ? null : d.restingHrBaselineFor(rhrNights.last.date);
        }
        // Χαμηλότεροι/υψηλότεροι της μέρας από το ρολόι. Όσο ο ύπνος δεν είναι του ρολογιού, ο ύπνος της νύχτας
        // εξαιρείται με τις ώρες του Oura (ίδιος κανόνας με τους παλμούς της μέρας)· χωρίς νύχτα του Oura δεν
        // ξεχωρίζει η μέρα από τον ύπνο, οπότε δεν δείχνουμε τίποτα (ποτέ «χαμηλότεροι» που είναι παλμοί του ύπνου).
        final readDay = dayOf(d.readAt);
        final dayOnly = store.plan.nightSource(readDay) != Source.watch;
        final windows = store.ouraWindows;
        final (double, double)? today;
        if (!dayOnly) {
          today = d.heartRange(d.readAt);
        } else if (store.plan.nightSource(readDay) == Source.oura && windows.mains.containsKey(dateKey(readDay))) {
          today = d.heartRange(d.readAt, exclude: windows.ranges);
        } else {
          today = null;
        }
        final latest = d.latestHeart;
        // Οξυγόνο: πάντα του ρολογιού. Μετά τη σύνδεση του Oura ανά νύχτα χωρίς τον ύπνο του ρολογιού.
        final oxNights = ouraHr
            ? [
                for (var i = 0; i < 14; i++)
                  if (d.watchSpo2(DateTime(day.year, day.month, day.day - i)) case final o?)
                    (DateTime(day.year, day.month, day.day - i), o.avg, o.min),
              ].take(10).toList()
            : [for (final n in d.nights.where((n) => n.spo2Avg != null).toList().reversed.take(10)) (n.date, n.spo2Avg!, n.spo2Min)];
        final oxGuidance = oxygenGuidance(
          {for (final n in oxNights) if (n.$3 != null) n.$1: n.$3!},
          ouraHr ? day : (d.lastNight?.date ?? day),
        );

        Widget? trend;
        if (lastRhr != null && base != null) {
          final diff = (lastRhr - base).round();
          trend = diff == 0
              ? const TrendPill('Όπως ο μέσος όρος σου')
              : TrendPill(
                  '${diff.abs()} ${diff > 0 ? 'πάνω' : 'κάτω'} από τον μέσο όρο (${base.round()})',
                  up: diff > 0,
                  // Η πτώση είναι ουδέτερη, όχι «καλή» (κλινικός έλεγχος M4): μπορεί να είναι φάρμακο ή κρύο δωμάτιο.
                  kind: diff >= 3 ? TrendKind.bad : TrendKind.neutral,
                );
        }

        return PageFrame(
          title: 'Καρδιά',
          subtitle: 'Παλμοί και οξυγόνο',
          onRefresh: () => store.refresh(),
          left: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CardHeader(
                    icon: Icons.bedtime_rounded,
                    title: 'Παλμοί στον ύπνο',
                    color: c.sleep,
                    trailing: store.plan.nightSource(day) == Source.oura ? const SourceTag(Source.oura) : null,
                  ),
                  const SizedBox(height: 14),
                  if (lastRhr != null) BigValue('${lastRhr.round()}', unit: 'bpm', size: 34),
                  if (trend != null) ...[const SizedBox(height: 8), trend],
                  const SizedBox(height: 8),
                  Text(
                    ouraHr
                        ? 'Ο μέσος όρος των παλμών σου όσο κοιμάσαι, κάθε νύχτα, από το δαχτυλίδι. Συγκρίνεται μόνο με '
                            'τις νύχτες σου από το Oura.'
                        : 'Ο μέσος όρος των παλμών σου όσο κοιμάσαι, κάθε νύχτα. Είναι συνήθως λίγο πιο χαμηλά από την ηρεμία όταν είσαι ξύπνιος.',
                    style: TextStyle(color: c.textSecondary, fontSize: 13.5, height: 1.4),
                  ),
                  if (rhrPoints.length >= 2) ...[
                    const SizedBox(height: 14),
                    LineChart(points: rhrPoints, format: (v) => v.round().toString(), color: c.sleep, minRange: 8),
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
                  CardHeader(icon: Icons.monitor_heart_rounded, title: 'Τελευταίες μετρήσεις', color: c.heart),
                  const SizedBox(height: 8),
                  if (latest != null)
                    InfoRow(
                      'Τελευταία μέτρηση, ${sameDay(latest.start, DateTime.now()) ? '' : '${relativeDay(latest.start, DateTime.now()).replaceFirst('Χθες', 'χθες')} '}${hm(latest.start)}',
                      '${latest.avg.round()} bpm',
                    ),
                  if (today != null && !dayOnly) ...[
                    InfoRow('Χαμηλότεροι σήμερα', '${today.$1.round()} bpm'),
                    InfoRow('Υψηλότεροι σήμερα', '${today.$2.round()} bpm'),
                  ],
                  if (today != null && dayOnly) ...[
                    InfoRow('Χαμηλότεροι μέρας · ρολόι', '${today.$1.round()} bpm'),
                    InfoRow('Υψηλότεροι μέρας · ρολόι', '${today.$2.round()} bpm'),
                  ],
                  if (today == null && dayOnly)
                    Text(
                      'Οι χαμηλότεροι και υψηλότεροι της μέρας φαίνονται όταν έρθει η νύχτα από το δαχτυλίδι, για να μη '
                      'μετρήσουν παλμοί του ύπνου.',
                      style: TextStyle(color: c.textSecondary, fontSize: 13.5, height: 1.4),
                    ),
                  if (latest == null && today == null && !dayOnly)
                    Text('Δεν υπάρχουν μετρήσεις σήμερα.', style: TextStyle(color: c.textSecondary)),
                ],
              ),
            ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CardHeader(
                    icon: Icons.air_rounded,
                    title: 'Οξυγόνο στον ύπνο',
                    color: c.sleep,
                    trailing: ouraHr ? const SourceTag(Source.watch) : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Μέσο ανά νύχτα και η χαμηλότερη μεμονωμένη μέτρηση του ρολογιού. $oxygenAboutText',
                    style: TextStyle(color: c.textSecondary, fontSize: 13.5, height: 1.4),
                  ),
                  const Hairline(vertical: 12),
                  if (oxNights.isEmpty)
                    Text('Δεν υπάρχουν μετρήσεις οξυγόνου.', style: TextStyle(color: c.textSecondary)),
                  for (final n in oxNights)
                    InfoRow(
                      shortDayDate(n.$1),
                      '${n.$2.round()}% · χαμηλότερη ${n.$3 == null ? '—' : lowestText(n.$3!)}% (ενδεικτικό)',
                    ),
                  const SizedBox(height: 10),
                  OxygenNotes(guidance: oxGuidance),
                ],
              ),
            ),
            if (!ouraHr)
              EmptyCard(
                icon: Icons.timeline_rounded,
                color: c.sleep,
                title: 'HRV (μεταβλητότητα παλμών)',
                text: 'Η Samsung δεν το δίνει σε άλλες εφαρμογές, γι\' αυτό δεν φαίνεται εδώ.',
              )
            else
              EmptyCard(
                icon: Icons.timeline_rounded,
                color: c.sleep,
                title: 'HRV (μεταβλητότητα παλμών)',
                text: 'Έρχεται από το Oura: Υγεία › Ύπνος › «Καρδιά στον ύπνο».',
              ),
            // Κλινικός έλεγχος M6 (4/11): όποιος έχει συμπτώματα ανοίγει πρώτα την Καρδιά.
            Padding(
              key: const ValueKey('heart-red-flags'),
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Text(heartRhythmNote, style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.4)),
            ),
          ],
        );
      },
    );
  }
}
