import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../history.dart';
import '../oura/oura_view.dart';
import '../oxygen_note.dart';
import '../reference.dart';
import '../shown.dart';
import '../sources.dart';
import '../theme.dart';
import '../unusual.dart';
import '../widgets.dart';
import 'info_sheet.dart';
import 'metric_page.dart';
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
        // 7/11: με το Oura, μέσος όρος από το Oura και χαμηλότερη από το ρολόι (μόνο με κάλυψη ≥ 50%).
        final List<(DateTime, double?, double?)> oxNights = ouraHr
            ? [
                for (var i = 0; i < 14; i++)
                  if (oxSeg == null || !DateTime(day.year, day.month, day.day - i).isBefore(oxSeg))
                    if (ringOxygen(store, d, DateTime(day.year, day.month, day.day - i), windows) case final o
                        when o.avg != null || o.min != null)
                      (DateTime(day.year, day.month, day.day - i), o.avg, o.min),
              ].take(10).toList()
            : [
                for (final n in d.nights.where((n) => n.spo2Avg != null && (oxSeg == null || !n.date.isBefore(oxSeg))).toList().reversed.take(10))
                  (n.date, n.spo2Avg, n.spo2Min),
              ];
        // Σημειώσεις για χαμηλό οξυγόνο (B7) με τις τιμές του ορισμού A4 (παράθυρο Oura / νύχτα ρολογιού, ίδια εποχή).
        // Round 1 (S4-10): με το Oura, «τελευταία νύχτα» = η πιο πρόσφατη με χαμηλότερη τιμή του ρολογιού ως 2 μέρες πίσω
        // ([oxygenLastNight]), όπως στον Ύπνο· πριν ήταν πάντα «σήμερα», και μια πολύ χαμηλή τιμή της χθεσινής νύχτας δεν
        // έβγαινε σημείωση όταν η σημερινή δεν είχε ακόμα τιμή.
        final oxLast = ouraHr ? oxygenLastNight(store, d, day) : (d.lastNight?.date ?? day);
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
                  '${signedShown(diff)} bpm ·\u00A0συνήθως ${base.round()}',
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
              onTap: () => Navigator.of(context).push(MetricPage.route(store, K.sleepHr, now: now)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CardHeader(
                    icon: Icons.bedtime_rounded,
                    title: datedTitle('Παλμοί στον ύπνο', rhrNight, day),
                    color: c.sleep,
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (store.plan.nightSource(day) == Source.oura) const SourceTag(Source.oura),
                      const InfoButton(K.sleepHr),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  if (lastRhr != null) BigValue('${lastRhr.round()}', unit: 'bpm', size: 34),
                  // Round 1 (U1a-5 = U2a-08): το «χάπι» στο πλάτος του κειμένου (πριν τεντωνόταν σε όλη την κάρτα).
                  if (trend != null) ...[const SizedBox(height: 8), Align(alignment: Alignment.centerLeft, child: trend)],
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
                    // Round 1 (U1a-5 = U2a-16): ίδια μορφή ημερομηνίας με το γράφημα από κάτω («8 Νοε»).
                    LineChart(points: rhrPoints, format: (v) => v.round().toString(), color: c.sleep, minRange: 8, dateLabel: dayMonth),
                  ],
                ],
              ),
            ),
            _AwakeHeartCard(store: store, day: day),
            // Στο tablet/PC κάτω από τους παλμούς ύπνου, για να μη μένει η αριστερή στήλη με μία κάρτα (UX U10).
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CardHeader(
                    icon: Icons.air_rounded,
                    title: 'Οξυγόνο στον ύπνο',
                    color: c.sleep,
                    trailing: ouraHr ? const InfoButton(K.ringSpo2) : null,
                  ),
                  const SizedBox(height: 8),
                  OxygenAbout(
                      lead: ouraHr
                          ? 'Μέσος όρος της νύχτας από το Oura· χαμηλότερη μέτρηση από το ρολόι, μόνο όταν μέτρησε '
                              'τουλάχιστον το μισό του ύπνου (ενδεικτική).'
                          // Round 1 (U1a-6): «μέσος όρος», όχι «μέσο»· ένα όνομα για τη χαμηλότερη («τιμή»).
                          : 'Μέσος όρος κάθε νύχτας και η χαμηλότερη μεμονωμένη τιμή του ρολογιού (ενδεικτική).'),
                  if (ouraHr && store.ouraSpo2 == false) ...[
                    const SizedBox(height: 8),
                    Text(ringAvgMissing(store), style: TextStyle(color: c.textSecondary, fontSize: 13.5)),
                  ],
                  const Hairline(vertical: 12),
                  if (oxNights.isEmpty)
                    Text('Δεν υπάρχουν μετρήσεις οξυγόνου.', style: TextStyle(color: c.textSecondary)),
                  // UX U4: «χαμηλότερη μέτρηση» όπως σε κάθε οθόνη, μία φορά ως επικεφαλίδα της στήλης· στις γραμμές μόνο
                  // οι τιμές, για να μη σπάει η ημερομηνία σε 2 γραμμές στα 360–400 dp.
                  if (oxNights.isNotEmpty)
                    Text(
                      ouraHr ? 'μέσος όρος (Oura) ·\u00A0χαμηλότερη τιμή (ρολόι)' : 'μέσος όρος ·\u00A0χαμηλότερη τιμή',
                      key: const ValueKey('heart-oxygen-columns'),
                      textAlign: TextAlign.right,
                      style: TextStyle(color: c.textTertiary, fontSize: 12.5),
                    ),
                  for (final n in oxNights)
                    InfoRow(
                      shortDayDate(n.$1),
                      // Χωρίς «(ενδεικτικό)» σε κάθε γραμμή (το λέει το κείμενο πάνω): στα 400 dp η ημερομηνία έσπαγε σε 2 γραμμές.
                      '${n.$2 == null ? '—' : '${spo2AvgText(n.$2!)}%'} ·\u00A0${n.$3 == null ? '—' : '${lowestText(n.$3!)}%'}',
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
                      // Round 1 (S12-09 γ): το «τώρα» της σελίδας, όχι το ρολόι της συσκευής (στιγμιότυπα).
                      'Τελευταία μέτρηση, ${sameDay(latest.start, now ?? DateTime.now()) ? '' : '${relativeDay(latest.start, now ?? DateTime.now()).replaceFirst('Χθες', 'χθες')} '}${hm(latest.start)}',
                      '${latest.avg.round()} bpm',
                    ),
                  if (today != null && !dayOnly) ...[
                    InfoRow('Χαμηλότεροι σήμερα', '${today.$1.round()} bpm'),
                    InfoRow('Υψηλότεροι σήμερα', '${today.$2.round()} bpm'),
                  ],
                  if (today != null && dayOnly) ...[
                    // Round 1 (U1a-7): «της μέρας», όπως η πρόταση από κάτω.
                    InfoRow('Χαμηλότεροι της μέρας ·\u00A0ρολόι', '${today.$1.round()} bpm'),
                    InfoRow('Υψηλότεροι της μέρας ·\u00A0ρολόι', '${today.$2.round()} bpm'),
                  ],
                  if (today == null && dayOnly)
                    Text(
                      // Round 9 (R9-A5-4): χωρίς πηγή ύπνου (αποσύνδεση του Oura) καμία νύχτα δαχτυλιδιού δεν θα έρθει·
                      // πριν η σελίδα υποσχόταν τιμές «όταν έρθει η νύχτα από το δαχτυλίδι».
                      store.plan.nightSource(readDay) == Source.none
                          ? heartNoSleepSourceRangeText
                          : 'Οι χαμηλότεροι και υψηλότεροι της μέρας φαίνονται όταν έρθει η νύχτα από το δαχτυλίδι, για να μη '
                              'μετρήσουν παλμοί του ύπνου.',
                      key: const ValueKey('heart-day-range-note'),
                      style: TextStyle(color: c.textSecondary, fontSize: 13.5, height: 1.4),
                    ),
                  if (latest == null && today == null && !dayOnly)
                    Text('Δεν υπάρχουν μετρήσεις σήμερα.', style: TextStyle(color: c.textSecondary)),
                ],
              ),
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


/// Παλμοί ξύπνιος (7/11): ο μέσος όρος των παλμών του ρολογιού όλη τη μέρα έξω από τον ύπνο (ώρες ύπνου από το Oura),
/// με βάρος τον χρόνο, μαζί με την κίνηση. Μόνο ολοκληρωμένες μέρες (η σημερινή δεν μετρά). Χωρίς εύρος: δεν υπάρχει
/// δημοσιευμένο για αυτόν τον μέσο όρο· μόνο το «συνήθως» του χρήστη.
class _AwakeHeartCard extends StatelessWidget {
  const _AwakeHeartCard({required this.store, required this.day});
  final HealthStore store;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final plan = store.plan;
    DateTime? last;
    for (var i = 1; i <= 3 && last == null; i++) {
      final d = DateTime(day.year, day.month, day.day - i);
      if (plan.value(store.history, K.dayHr, d) != null) last = d;
    }
    final b = last == null ? null : personalBaseline(store.history, plan, K.dayHr, last);
    final pts = planSeries(store.history, plan, K.dayHr, DateTime(day.year, day.month, day.day - 30), DateTime(day.year, day.month, day.day - 1)).points;
    // Round 1 (U1a-5): η σύγκριση με το «συνήθως» ως «χάπι», όπως στους παλμούς ύπνου (πριν: γκρι πρόταση).
    Widget? pill;
    String? usual;
    if (b?.usual != null) {
      final d = shownDiff(b!.value, b.usual!);
      // Round 2 (R2-U1-10): ίδια γραφή με το χάπι των παλμών ύπνου στην ίδια σελίδα («+2 bpm · συνήθως 59», «Όπως
      // συνήθως»)· πριν «−2 bpm · συνήθως 74 bpm» και «Όπως συνήθως · συνήθως 74 bpm».
      pill = TrendPill(
        d == 0 ? asUsualText : '${signedShown(d)} bpm ·\u00A0συνήθως ${b.usual!.round()}',
        up: d == 0 ? null : d > 0,
      );
    } else if (b != null) {
      usual = 'Το συνηθισμένο σου βγαίνει μετά από 7 μέρες';
    }
    return AppCard(
      key: const ValueKey('heart-awake'),
      onTap: () => Navigator.of(context).push(MetricPage.route(store, K.dayHr, now: day)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHeader(
            icon: Icons.directions_walk_rounded,
            title: 'Παλμοί ξύπνιος',
            subtitle: last == null ? null : shortDayDate(last),
            color: c.heart,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: const [SourceTag(Source.watch), InfoButton(K.dayHr)]),
          ),
          const SizedBox(height: 10),
          BigValue(b == null ? '—' : '${b.value.round()}', unit: 'bpm', size: 34),
          const SizedBox(height: 6),
          if (pill != null)
            Align(alignment: Alignment.centerLeft, child: pill)
          else
            Text(
              usual ?? awakeHeartNote(plan, day),
              key: const ValueKey('heart-awake-note'),
              style: TextStyle(color: c.textSecondary, fontSize: 13.5),
            ),
          if (pts.length >= 2) ...[
            const SizedBox(height: 14),
            LineChart(points: pts, color: c.heart, format: (v) => v.round().toString(), minRange: 8, dateLabel: dayMonth),
          ],
        ],
      ),
    );
  }
}

/// Round 9 (R9-A5-4): «Τελευταίες μετρήσεις» όταν ο ύπνος δεν έχει πηγή (το Oura αποσυνδέθηκε χωρίς να διαλεχτεί το
/// ρολόι): χωρίς ώρες ύπνου δεν ξεχωρίζει ο ύπνος από τη μέρα ([_heartWithPlan] στο history.dart: τίποτα για Source.none).
const heartNoSleepSourceRangeText = 'Χωρίς πηγή ύπνου δεν ξεχωρίζει ο ύπνος από τη μέρα, οπότε οι χαμηλότεροι και '
    'υψηλότεροι της μέρας δεν φαίνονται. Η πηγή του ύπνου αλλάζει στις «Ρυθμίσεις Oura».';

/// Round 9 (R9-A5-4): το ίδιο για τους «Παλμούς ξύπνιος».
const heartNoSleepSourceAwakeText =
    'Χωρίς πηγή ύπνου δεν ξεχωρίζει ο ύπνος από τη μέρα, οπότε δεν βγαίνει. Η πηγή του ύπνου αλλάζει στις «Ρυθμίσεις Oura».';

/// Η σημείωση των «Παλμών ξύπνιος» χωρίς τιμή. Round 7 (R7-A5-5): με τον ύπνο από το ρολόι οι παλμοί ξύπνιος βγαίνουν από
/// τον ύπνο του ρολογιού (history.dart › summarizeDay), όχι από το δαχτυλίδι· 6 ώρες = [minMinutesForDayValue]
/// (heart_day.dart). Round 9 (R9-A5-4): με τον ύπνο σήμερα χωρίς πηγή, καμία υπόσχεση «από το δαχτυλίδι»· και τη
/// μέρα που ο ύπνος ξαναγυρίζει στο ρολόι (χθες χωρίς πηγή ή Oura), το ρολόι.
String awakeHeartNote(SourcePlan plan, DateTime day) {
  final now = plan.nightSource(day);
  if (now == Source.none) return heartNoSleepSourceAwakeText;
  return now == Source.watch || plan.nightSource(DateTime(day.year, day.month, day.day - 1)) == Source.watch
      ? 'Βγαίνει για μέρες με αρκετές μετρήσεις του ρολογιού (τουλάχιστον 6 ώρες).'
      : 'Βγαίνει για μέρες με νύχτα από το δαχτυλίδι και αρκετές μετρήσεις του ρολογιού.';
}
