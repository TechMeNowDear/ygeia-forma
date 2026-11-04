import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../history.dart';
import '../oura/oura_view.dart';
import '../oxygen_note.dart';
import '../shown.dart';
import '../sources.dart';
import '../theme.dart';
import '../unusual.dart';
import '../widgets.dart';
import 'oxygen_widgets.dart';
import 'source_widgets.dart';

class HeartPage extends StatelessWidget {
  const HeartPage({super.key, required this.store, this.now, this.onOpenSleep});
  final HealthStore store;

  /// Άνοιγμα της καρτέλας «Ύπνος» (για το HRV του Oura· κουμπί, όχι διαδρομή γραμμένη ως κείμενο, έλεγχος UX U11).
  final VoidCallback? onOpenSleep;

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
        // Η νύχτα της τιμής που δείχνουμε: αν δεν είναι η τελευταία (π.χ. η χθεσινή χωρίς παλμούς), γράφεται η
        // ημερομηνία της (τρίτος έλεγχος F4), όπως στη Σήμερα.
        DateTime? rhrNight;
        if (ouraHr) {
          rhrPoints = planSeries(store.history, store.plan, K.sleepHr, DateTime(day.year, day.month, day.day - 29), day).points;
          final b = rhrPoints.isEmpty ? null : ouraBaseline(store.history, store.plan, K.sleepHr, rhrPoints.last.$1);
          lastRhr = rhrPoints.isEmpty ? null : rhrPoints.last.$2;
          rhrNight = rhrPoints.isEmpty ? null : rhrPoints.last.$1;
          base = b?.usual;
        } else {
          final rhrNights = d.nights.where((n) => n.sleepingHr != null).toList();
          rhrPoints = [
            for (final n in rhrNights.length <= 30 ? rhrNights : rhrNights.sublist(rhrNights.length - 30))
              (n.date, n.sleepingHr!),
          ];
          lastRhr = rhrNights.isEmpty ? null : rhrNights.last.sleepingHr;
          rhrNight = rhrNights.isEmpty ? null : rhrNights.last.date;
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
          // Και με το ρολόι εξαιρείται ο ύπνος του ρολογιού (έλεγχος υπολογισμών C14, 4/11): «Χαμηλότεροι σήμερα»
          // σημαίνει παντού «ξύπνιος», όχι «μαζί με τον ύπνο» πριν από το Oura και «ξύπνιος» μετά.
          today = d.heartRange(d.readAt, exclude: [for (final r in d.sleepRecords) (r.start, r.end)]);
        } else if (store.plan.nightSource(readDay) == Source.oura && windows.mains.containsKey(dateKey(readDay))) {
          today = d.heartRange(d.readAt, exclude: windows.ranges);
        } else {
          today = null;
        }
        final latest = d.latestHeart;
        // Οξυγόνο: πάντα του ρολογιού. Μετά τη σύνδεση του Oura ανά νύχτα μέσα στις ώρες ύπνου του Oura, και ΜΟΝΟ
        // νύχτες της ίδιας εποχής (ποτέ νύχτες πριν από την αλλαγή με άλλον ορισμό στην ίδια λίστα, A4).
        final oxSeg = store.plan.segmentStart(K.spo2Avg, day);
        final oxNights = ouraHr
            ? [
                for (var i = 0; i < 14; i++)
                  if (oxSeg == null || !DateTime(day.year, day.month, day.day - i).isBefore(oxSeg))
                    if (d.watchSpo2(DateTime(day.year, day.month, day.day - i), windows) case final o? when o.avg != null)
                      (DateTime(day.year, day.month, day.day - i), o.avg!, o.min),
              ].take(10).toList()
            : [
                for (final n in d.nights.where((n) => n.spo2Avg != null && (oxSeg == null || !n.date.isBefore(oxSeg))).toList().reversed.take(10))
                  (n.date, n.spo2Avg!, n.spo2Min),
              ];
        // Σημειώσεις για χαμηλό οξυγόνο (B7) με τις τιμές του ορισμού A4 (παράθυρο Oura / νύχτα ρολογιού, ίδια εποχή).
        final oxLast = ouraHr ? day : (d.lastNight?.date ?? day);
        final oxGuidance = oxygenGuidance(
          d.spo2MinByNight(oxLast, ouraNights: ouraHr, windows: windows, history: store.history),
          oxLast,
          today: day,
        );

        Widget? trend;
        if (lastRhr != null && base != null) {
          // Η διαφορά των δύο νούμερων όπως φαίνονται (έλεγχος υπολογισμών C6): «61 · +2 από το συνηθισμένο (59)»,
          // ποτέ «61 … 3 πάνω (59)». Ίδια λέξη «συνήθως» σε όλη την εφαρμογή (C7/U7), με μονάδα.
          // Ένας κανόνας σε όλες τις οθόνες (τρίτος έλεγχος F1): «Όπως συνήθως» μόνο για διαφορά 0.
          final diff = shownDiff(lastRhr, base);
          trend = diff == 0
              ? const TrendPill(asUsualText)
              : TrendPill(
                  '${signedShown(diff)} bpm · συνήθως ${base.round()}',
                  up: diff > 0,
                  // Η πτώση είναι ουδέτερη, όχι «καλή» (κλινικός έλεγχος M4): μπορεί να είναι φάρμακο ή κρύο δωμάτιο.
                  // Κόκκινο μόνο με τον κανόνα του «Εκτός συνηθισμένου» (κλινικός έλεγχος 4, C1)· αλλιώς γκρι.
                  kind: diff > 0 && rhrNight != null && sleepHrOff(store.history, rhrNight, plan: store.analysisPlan)
                      ? TrendKind.bad
                      : TrendKind.neutral,
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
                    title: datedTitle('Παλμοί στον ύπνο', rhrNight, day),
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
            // Στο tablet/PC κάτω από τους παλμούς ύπνου, για να μη μένει η αριστερή στήλη με μία κάρτα (UX U10).
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
                  const OxygenAbout(lead: 'Μέσο ανά νύχτα και η χαμηλότερη μεμονωμένη μέτρηση του ρολογιού (ενδεικτική).'),
                  const Hairline(vertical: 12),
                  if (oxNights.isEmpty)
                    Text('Δεν υπάρχουν μετρήσεις οξυγόνου.', style: TextStyle(color: c.textSecondary)),
                  // UX U4: «χαμηλότερη μέτρηση» όπως σε κάθε οθόνη, μία φορά ως επικεφαλίδα της στήλης· στις γραμμές μόνο
                  // οι τιμές, για να μη σπάει η ημερομηνία σε 2 γραμμές στα 360–400 dp.
                  if (oxNights.isNotEmpty)
                    Text(
                      'μέσο · χαμηλότερη μέτρηση',
                      key: const ValueKey('heart-oxygen-columns'),
                      textAlign: TextAlign.right,
                      style: TextStyle(color: c.textTertiary, fontSize: 12.5),
                    ),
                  for (final n in oxNights)
                    InfoRow(
                      shortDayDate(n.$1),
                      // Χωρίς «(ενδεικτικό)» σε κάθε γραμμή (το λέει το κείμενο πάνω): στα 400 dp η ημερομηνία έσπαγε σε 2 γραμμές.
                      '${spo2AvgText(n.$2)}% · ${n.$3 == null ? '—' : '${lowestText(n.$3!)}%'}',
                    ),
                  const SizedBox(height: 10),
                  OxygenNotes(guidance: oxGuidance),
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
                text: 'Έρχεται από το Oura και φαίνεται στον Ύπνο, στην κάρτα «Καρδιά στον ύπνο».',
                buttonText: onOpenSleep == null ? null : 'Άνοιγμα Ύπνου',
                onPressed: onOpenSleep,
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
