import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../history.dart';
import '../oura/oura_model.dart';
import '../oura/oura_store.dart';
import '../oura/oura_view.dart';
import '../oxygen_note.dart';
import '../shown.dart';
import '../sources.dart';
import '../theme.dart';
import '../widgets.dart';
import 'compare_page.dart';
import 'oxygen_widgets.dart';
import 'source_widgets.dart';

/// Ο λόγος που η χθεσινή νύχτα είναι κενή (null = υπάρχει).
EmptyNight? lastNightReason(HealthStore s, DateTime now) => s.ouraNightReason(dayOf(now), now);

/// Υγεία › Ύπνος όταν ο ύπνος έρχεται από το Oura (ή δεν έχει πηγή μετά την αποσύνδεση).
class OuraSleepPage extends StatelessWidget {
  const OuraSleepPage({super.key, required this.store, this.now});
  final HealthStore store;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final now = this.now ?? DateTime.now();
    final today = dayOf(now);
    final plan = store.plan;
    final nights = store.ouraNights.where((n) => plan.nightSource(n.day) == Source.oura).toList();
    final last = store.lastOuraNight != null && plan.nightSource(store.lastOuraNight!.day) == Source.oura
        ? store.lastOuraNight
        : null;
    final reason = lastNightReason(store, now);
    final stages = ouraStageAverages(nights, today, plan);

    final lastCard = last == null
        ? _EmptyNightCard(reason: reason ?? EmptyNight.noRing, day: today, night: store.ouraNightFor(today))
        : _OuraNightCard(
            night: last, now: now, reason: sameDay(last.day, today) ? null : reason, todayNight: store.ouraNightFor(today));

    final stagesCard = AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: CardHeader(icon: Icons.layers_rounded, title: 'Στάδια · μέσος όρος 7 νυχτών', color: c.sleep)),
            const SourceTag(Source.oura),
          ]),
          const SizedBox(height: 12),
          if (stages.deep == null)
            Text(
              'Χρειάζονται τουλάχιστον $minNightsForAverage νύχτες με το δαχτυλίδι μέσα σε μία εβδομάδα '
              '(τώρα ${countText(stages.nights, 'νύχτα', 'νύχτες')}).',
              style: TextStyle(color: c.textSecondary, fontSize: 14, height: 1.4),
            )
          else ...[
            InfoRow(stageLabel('DEEP'), hoursMinutes(stages.deep!), dot: c.stage('DEEP')),
            InfoRow(stageLabel('LIGHT'), hoursMinutes(stages.light!), dot: c.stage('LIGHT')),
            InfoRow(stageLabel('REM'), hoursMinutes(stages.rem!), dot: c.stage('REM')),
            InfoRow('Ξύπνιος τη νύχτα', atLeast(stages.awake!), dot: c.stage('AWAKE')),
          ],
          const SizedBox(height: 8),
          Text(
            'Τα στάδια μίας νύχτας έχουν μεγάλο λάθος σε κάθε συσκευή. Γι\' αυτό βλέπεις τον μέσο όρο της εβδομάδας. '
            'Τα ξυπνήματα συνήθως μετριούνται λιγότερα απ\' όσα είναι.',
            style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );

    final heart = _OuraHeartCard(store: store, day: last?.day ?? today);
    final breath = _BreathCard(store: store, day: last?.day ?? today, now: now);

    final compare = plan.compareActive(today)
        ? AppCard(
            key: const ValueKey('sleep-compare'),
            onTap: () => Navigator.of(context).push(ComparePage.route(store, now: this.now)),
            child: Row(
              children: [
                IconBadge(Icons.compare_arrows_rounded, c.sleep, size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Σύγκριση με το ρολόι (έως ${shortDayDate(plan.compareUntil!)})',
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: c.text),
                  ),
                ),
                Text('Άνοιγμα', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.primary)),
                Icon(Icons.chevron_right_rounded, color: c.primary),
              ],
            ),
          )
        : null;

    final list = [
      const SectionHeader('Νύχτα προς νύχτα'),
      for (var i = 0; i < 14; i++)
        () {
          final d = DateTime(today.year, today.month, today.day - i);
          if (plan.nightSource(d) == Source.watch) return null;
          final n = store.ouraNightFor(d);
          return _NightLine(
            day: d,
            now: now,
            night: n,
            reason: n?.main != null
                ? null
                : store.ouraNightReason(d, now),
          );
        }(),
    ].whereType<Widget>().toList();

    return PageFrame(
      title: 'Ύπνος',
      subtitle: plan.nightSource(today) == Source.none ? 'Το Oura δεν είναι συνδεδεμένο' : 'Από το Oura Ring 5',
      onRefresh: () => store.refresh(),
      left: [lastCard, if (compare != null) compare, stagesCard, heart, breath],
      right: list.length > 1 ? list : const [],
    );
  }
}

class _EmptyNightCard extends StatelessWidget {
  const _EmptyNightCard({required this.reason, required this.day, this.night});
  final EmptyNight reason;
  final DateTime day;

  /// Για «Μόνο υπνάκος»: οι ώρες του υπνάκου.
  final OuraNight? night;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final text = switch (reason) {
      EmptyNight.waiting => 'Η χθεσινή νύχτα δεν έχει φτάσει ακόμα. Άνοιξε την εφαρμογή Oura για να συγχρονίσει, και μετά γύρνα εδώ.',
      EmptyNight.noRing => 'Η νύχτα μένει κενή στον Ύπνο και στις Τάσεις. Οξυγόνο από το ρολόι φαίνεται κανονικά στην Καρδιά.',
      EmptyNight.reconnect => 'Η σύνδεση με το Oura χρειάζεται ανανέωση. Δεν χάνεται τίποτα· οι νύχτες έρχονται μετά.',
      EmptyNight.subscription => 'Χωρίς ενεργή συνδρομή Oura η εφαρμογή δεν μπορεί να διαβάσει τον ύπνο.',
      EmptyNight.notRead => 'Δεν έγινε ακόμα ανάγνωση από την Oura. Τράβηξε προς τα κάτω για να ξαναδοκιμάσεις.',
      EmptyNight.disconnected => 'Οι νύχτες μένουν κενές ώσπου να συνδέσεις ξανά το Oura ή να διαλέξεις το ρολόι (Ρυθμίσεις › Πηγές).',
      EmptyNight.onlyNap => 'Το δαχτυλίδι κατέγραψε μόνο υπνάκο, όχι νύχτα'
          '${napTimes(night).isEmpty ? '' : ': ${napTimes(night)}'}. Ο υπνάκος δεν μετρά ως νύχτα.',
      EmptyNight.unknownPlan => 'Οι ρυθμίσεις πηγών δεν διαβάστηκαν. Για να μη μπερδευτούν συσκευές, οι νύχτες μένουν κενές '
          'ώσπου να διαλέξεις στις Ρυθμίσεις › Πηγές.',
      EmptyNight.notOura => '',
    };
    return EmptyCard(icon: Icons.bedtime_rounded, color: c.sleep, title: emptyNightText(reason), text: text);
  }
}

class _OuraNightCard extends StatelessWidget {
  const _OuraNightCard({required this.night, required this.now, this.reason, this.todayNight});
  final OuraNight night;

  /// Η χθεσινή (π.χ. μόνο υπνάκος), για να φαίνονται οι ώρες της.
  final OuraNight? todayNight;
  final DateTime now;

  /// Αν αυτή δεν είναι η χθεσινή νύχτα: γιατί λείπει η χθεσινή.
  final EmptyNight? reason;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final n = night.toNight()!;
    // Νύχτα σε κομμάτια (ως 4 ώρες κενό): μετρούν όλα μαζί, το κενό όχι (δεύτερος γύρος ελέγχου, U12).
    final parts = night.counted;
    final minutes = night.nightMinutes;
    Widget clock(String label, DateTime? t) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: c.textSecondary, fontSize: 13)),
              Text(
                t == null ? '—' : hm(t),
                style: TextStyle(color: c.text, fontSize: 20, fontWeight: FontWeight.w700, fontFeatures: tabular),
              ),
            ],
          ),
        );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (reason != null) ...[
            Text(
              '${emptyNightText(reason!)} για χθες βράδυ'
              '${reason == EmptyNight.onlyNap && napTimes(todayNight, nightOnly: true).isNotEmpty ? ' (${napTimes(todayNight, nightOnly: true)})' : ''}. '
              'Βλέπεις την τελευταία νύχτα που ήρθε.',
              style: TextStyle(color: c.bad, fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.35),
            ),
            const SizedBox(height: 10),
          ],
          Row(children: [
            Expanded(
              child: CardHeader(icon: Icons.bedtime_rounded, title: 'Τελευταία νύχτα · ${shortDayDate(night.day)}', color: c.sleep),
            ),
            const SourceTag(Source.oura),
          ]),
          if (night.shortNight && (minutes ?? 0) < 180) ...[
            const SizedBox(height: 8),
            Text(shortNightLabel,
                key: const ValueKey('oura-short-night'),
                style: TextStyle(color: c.textSecondary, fontSize: 13.5, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: minutes == null
                    ? Text('—', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: c.text))
                    : DurationValue(minutes, size: 30),
              ),
              // Χωρίς βαθμολογία από την Oura: χωρίς άδειο δαχτυλίδι «—» (έλεγχος UX U8).
              if (night.sleepScore != null)
                ScoreRing(
                  value: night.sleepScore!.toDouble(),
                  size: 64,
                  stroke: 6,
                  color: c.sleep,
                  track: c.tint(c.sleep),
                  textColor: c.text,
                  caption: 'σκορ · εκτίμηση',
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(children: [clock('Ξάπλωσες', parts.first.start), clock('Κοιμήθηκες', parts.first.onset), clock('Ξύπνησες', parts.last.end)]),
          if (n.stages.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Πώς κύλησε η νύχτα · εκτίμηση του Oura', style: TextStyle(color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Hypnogram(night: n, height: 64),
            const SizedBox(height: 4),
            Row(children: [
              Text(hm(n.start), style: TextStyle(color: c.textTertiary, fontSize: 11.5)),
              const Spacer(),
              Text(hm(n.end), style: TextStyle(color: c.textTertiary, fontSize: 11.5)),
            ]),
          ],
          if (parts.length > 1) ...[
            const Hairline(vertical: 12),
            for (final x in parts)
              InfoRow('Κομμάτι ${hm(x.start)}–${hm(x.end)}', x.totalMinutes == null ? '—' : hoursMinutes(x.totalMinutes!)),
            InfoRow(
              'Κενό ανάμεσα (δεν μετρά)',
              hoursMinutes([for (var i = 1; i < parts.length; i++) parts[i].start.difference(parts[i - 1].end).inMinutes].fold(0, (a, b) => a + b)),
              dot: c.textTertiary,
            ),
          ],
          if (night.naps.isNotEmpty || night.others.isNotEmpty) ...[
            const Hairline(vertical: 12),
            // Υπνάκοι κατά τον κοινό κανόνα με το ρολόι, και περίοδοι που επικαλύπτονται: χωριστά, δεν προστίθενται.
            for (final x in night.naps)
              InfoRow('Υπνάκος ${hm(x.start)}–${hm(x.end)} (χωριστά)', x.totalMinutes == null ? '—' : hoursMinutes(x.totalMinutes!)),
            for (final x in night.others)
              InfoRow('Άλλος ύπνος ${hm(x.start)}–${hm(x.end)} (χωριστά)', x.totalMinutes == null ? '—' : hoursMinutes(x.totalMinutes!)),
          ],
        ],
      ),
    );
  }
}

/// Παλμοί και HRV ύπνου, μόνο από το Oura, σε σύγκριση με τις δικές σου 14 τελευταίες νύχτες.
class _OuraHeartCard extends StatelessWidget {
  const _OuraHeartCard({required this.store, required this.day});
  final HealthStore store;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final plan = store.plan;
    final low = plan.value(store.history, K.lowHr, day);
    final avg = plan.value(store.history, K.sleepHr, day);
    final hrv = ouraBaseline(store.history, plan, K.hrv, day);
    final series = planSeries(store.history, plan, K.hrv, DateTime(day.year, day.month, day.day - 29), day).points;

    Widget value(String label, String v, String unit) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: c.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              BigValue(v, unit: unit, size: 22),
            ],
          ),
        );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: CardHeader(icon: Icons.favorite_rounded, title: 'Καρδιά στον ύπνο', color: c.heart)),
            const SourceTag(Source.oura),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            value('Χαμηλότεροι παλμοί', low == null ? '—' : '${low.round()}', 'bpm'),
            value('Μέσοι παλμοί', avg == null ? '—' : '${avg.round()}', 'bpm'),
            value('HRV (RMSSD)', hrv == null ? '—' : '${hrv.value.round()}', 'ms'),
          ]),
          if (hrv?.usual != null) ...[
            const SizedBox(height: 8),
            Text(
              // Ίδιος κανόνας και ίδια μορφή με τη Σήμερα και την Καρδιά (τρίτος έλεγχος F1).
              'HRV: ${asUsual(hrv!.value, hrv.usual!) ? 'όπως συνήθως' : '${signedShown(shownDiff(hrv.value, hrv.usual!))} ms'} · '
              'συνήθως ${hrv.usual!.round()} ms (οι ${hrv.count} προηγούμενες νύχτες σου)',
              style: TextStyle(color: c.textSecondary, fontSize: 13.5),
            ),
          ] else if (hrv != null) ...[
            const SizedBox(height: 8),
            Text(
              'Το συνηθισμένο σου βγαίνει μετά από $minNightsForBaseline νύχτες με το δαχτυλίδι.',
              style: TextStyle(color: c.textSecondary, fontSize: 13.5),
            ),
          ],
          if (series.length >= 2) ...[
            const SizedBox(height: 12),
            LineChart(
              points: series,
              color: c.sleep,
              format: (v) => v.round().toString(),
              minRange: 10,
              dateLabel: dayMonth,
              levels: [
                if (hrv?.usual != null) (series.first.$1, series.last.$1, hrv!.usual!, c.textSecondary),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            // Κλινικός έλεγχος H5 (4/11): χωρίς «ανεβαίνει όσο ξεκουράζεσαι» και «με ακρίβεια».
            'HRV (RMSSD): πόσο αλλάζει το διάστημα από χτύπο σε χτύπο. Χαμηλώνει με την ηλικία, το αλκοόλ, την ασθένεια '
            'και την κούραση, και αλλάζει με φάρμακα. Κάθε σημείο είναι ο μέσος όρος μιας νύχτας, που είναι πιο αξιόπιστος '
            'από μεμονωμένες μετρήσεις. Έχει νόημα μόνο σε σύγκριση με τις δικές σου νύχτες. Ακανόνιστος ρυθμός ή έκτακτες '
            'συστολές μπορεί να ανεβάσουν ψεύτικα την τιμή.',
            style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// Αναπνοή (Oura) και οξυγόνο (ρολόι): δύο γραμμές, κάθε μία με την πηγή της. Ποτέ μαζί σε μία τιμή.
class _BreathCard extends StatelessWidget {
  const _BreathCard({required this.store, required this.day, required this.now});
  final HealthStore store;
  final DateTime day;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final plan = store.plan;
    final b = ouraBaseline(store.history, plan, K.breath, day);
    final windows = store.ouraWindows;
    final ox = store.data?.watchSpo2(day, windows);
    // Σημειώσεις για χαμηλό οξυγόνο (B7) με τις τιμές του ορισμού A4: ρολόι μέσα στις ώρες ύπνου του Oura, μόνο νύχτες
    // της ίδιας εποχής (όπως η λίστα της Καρδιάς).
    final oxSeg = plan.segmentStart(K.spo2Avg, day);
    final g = oxygenGuidance(
      store.data?.spo2MinByNight(day, ouraNights: true, windows: windows, since: oxSeg) ?? const {},
      day,
      today: now,
    );

    Widget row(String title, String sub, Source s) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: c.text)),
                    const SizedBox(height: 2),
                    Text(sub, style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.3)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SourceTag(s),
            ],
          ),
        );

    // Η ίδια λέξη «συνήθως» και η διαφορά των νούμερων όπως φαίνονται (έλεγχος υπολογισμών C6/C7).
    String breathNote() {
      if (b == null) return 'Δεν υπάρχει για αυτή τη νύχτα';
      if (b.usual == null) return 'Το συνηθισμένο σου βγαίνει μετά από $minNightsForBaseline νύχτες';
      // Τρίτος έλεγχος F1: «Όπως συνήθως» μόνο για διαφορά 0 (πριν: ως ±0,9, που φαινόταν ως διαφορά).
      final d = shownDiff(b.value, b.usual!, 1);
      if (d == 0) return '$asUsualText (${dec(b.usual!)})';
      return '${signedShown(d, 1)} · συνήθως ${dec(b.usual!)}';
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHeader(icon: Icons.air_rounded, title: 'Αναπνοή και οξυγόνο τη νύχτα', color: c.sleep),
          const SizedBox(height: 6),
          row(b == null ? 'Αναπνοές —' : 'Αναπνοές ${dec(b.value)} το λεπτό', breathNote(), Source.oura),
          const Hairline(vertical: 2),
          row(
            ox?.avg == null ? 'Οξυγόνο —' : 'Οξυγόνο ${spo2AvgText(ox!.avg!)}%',
            ox == null
                ? (windows.mains.containsKey(dateKey(day))
                    ? 'Δεν υπάρχουν μετρήσεις του ρολογιού μέσα στις ώρες ύπνου'
                    : 'Χωρίς νύχτα από το δαχτυλίδι δεν ξέρουμε πότε κοιμήθηκες· το οξυγόνο μένει κενό')
                // UX U4: ίδια λέξη με τις άλλες οθόνες· C13: χωρίς «T90» (εξηγείται στο PDF).
                : 'Χαμηλότερη μέτρηση ${lowestText(ox.min)}% · ενδεικτικό'
                    '${ox.below90 == null ? '' : ' · χρόνος κάτω από 90%: ${hoursMinutes(ox.below90!.round())} (από το ρολόι, ενδεικτικό)'}',
            Source.watch,
          ),
          const SizedBox(height: 6),
          // Κλινικός έλεγχος C1/M3 (4/11): το τεστ άπνοιας του ρολογιού είναι διαλογή· το πλήρες κείμενο με «Τι σημαίνει».
          const OxygenAbout(),
          const SizedBox(height: 4),
          OxygenNotes(guidance: g),
        ],
      ),
    );
  }
}

class _NightLine extends StatelessWidget {
  const _NightLine({required this.day, required this.now, required this.night, required this.reason});
  final DateTime day;
  final DateTime now;
  final OuraNight? night;
  final EmptyNight? reason;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final m = night?.main;
    final n = night?.toNight();
    final minutes = night?.nightMinutes;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sameDay(day, now) ? 'Χθες βράδυ' : shortDayDate(day),
                      style: TextStyle(color: c.text, fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      m == null
                          ? emptyNightText(reason ?? EmptyNight.noRing)
                          : '${hm(night!.counted.first.onset ?? night!.counted.first.start)} – ${hm(night!.counted.last.end)}'
                              '${night!.counted.length > 1 ? ' · ${night!.counted.length} κομμάτια' : ''}',
                      style: TextStyle(color: c.textSecondary, fontSize: 13.5, fontFeatures: tabular),
                    ),
                  ],
                ),
              ),
              if (m != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      minutes == null ? '—' : hoursMinutes(minutes),
                      style: TextStyle(color: c.text, fontWeight: FontWeight.w700, fontSize: 15, fontFeatures: tabular),
                    ),
                    if (night!.sleepScore != null)
                      Text('σκορ ${night!.sleepScore}', style: TextStyle(color: c.sleep, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
            ],
          ),
          if (n != null && n.stages.isNotEmpty) ...[
            const SizedBox(height: 10),
            StageTimeline(night: n, height: 8),
          ],
        ],
      ),
    );
  }
}

/// Για την κάρτα της Σήμερα: η κατάσταση του Oura σε μία γραμμή.
String ouraStatusLine(OuraStatus s) => switch (s) {
      OuraStatus.waiting || OuraStatus.startingNow => 'Περιμένει το Oura',
      OuraStatus.missing => 'Χωρίς ύπνο από το δαχτυλίδι',
      OuraStatus.reconnect => 'Χρειάζεται νέα σύνδεση',
      OuraStatus.subscription => 'Η συνδρομή Oura δεν είναι ενεργή',
      OuraStatus.disconnected => 'Το Oura δεν είναι συνδεδεμένο',
      _ => '',
    };
