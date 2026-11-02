import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../history.dart';
import '../oura/oura_model.dart';
import '../oura/oura_store.dart';
import '../oura/oura_view.dart';
import '../sources.dart';
import '../theme.dart';
import '../widgets.dart';
import 'compare_page.dart';
import 'source_widgets.dart';

/// Ο λόγος που η χθεσινή νύχτα είναι κενή (null = υπάρχει).
EmptyNight? lastNightReason(HealthStore s, DateTime now) => emptyNightReason(
      plan: s.plan,
      day: dayOf(now),
      now: now,
      night: s.ouraNightFor(dayOf(now)),
      hasTokens: s.ouraHasTokens,
      error: s.ouraError?.name,
      synced: s.ouraLastSync,
    );

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
        ? _EmptyNightCard(reason: reason ?? EmptyNight.noRing, day: today)
        : _OuraNightCard(night: last, now: now, reason: sameDay(last.day, today) ? null : reason);

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
    final breath = _BreathCard(store: store, day: last?.day ?? today);

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
                    'Έλεγχος με το ρολόι · ως ${shortDayDate(plan.compareUntil!)}',
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: c.text),
                  ),
                ),
                Text('Σύγκριση', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.primary)),
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
                : emptyNightReason(
                    plan: plan,
                    day: d,
                    now: now,
                    night: n,
                    hasTokens: store.ouraHasTokens,
                    error: store.ouraError?.name,
                    synced: store.ouraLastSync,
                  ),
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
  const _EmptyNightCard({required this.reason, required this.day});
  final EmptyNight reason;
  final DateTime day;

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
      EmptyNight.notOura => '',
    };
    return EmptyCard(icon: Icons.bedtime_rounded, color: c.sleep, title: emptyNightText(reason), text: text);
  }
}

class _OuraNightCard extends StatelessWidget {
  const _OuraNightCard({required this.night, required this.now, this.reason});
  final OuraNight night;
  final DateTime now;

  /// Αν αυτή δεν είναι η χθεσινή νύχτα: γιατί λείπει η χθεσινή.
  final EmptyNight? reason;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final m = night.main!;
    final n = night.toNight()!;
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
              '${emptyNightText(reason!)} για χθες βράδυ. Βλέπεις την τελευταία νύχτα που ήρθε.',
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
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: m.totalMinutes == null
                    ? Text('—', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: c.text))
                    : DurationValue(m.totalMinutes!, size: 30),
              ),
              ScoreRing(
                value: night.sleepScore?.toDouble(),
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
          Row(children: [clock('Ξάπλωσες', m.start), clock('Κοιμήθηκες', m.onset), clock('Ξύπνησες', m.end)]),
          if (n.stages.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Πώς κύλησε η νύχτα · εκτίμηση του Oura', style: TextStyle(color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Hypnogram(night: n, height: 64),
            const SizedBox(height: 4),
            Row(children: [
              Text(hm(m.start), style: TextStyle(color: c.textTertiary, fontSize: 11.5)),
              const Spacer(),
              Text(hm(m.end), style: TextStyle(color: c.textTertiary, fontSize: 11.5)),
            ]),
          ],
          if (night.naps.isNotEmpty || night.others.isNotEmpty) ...[
            const Hairline(vertical: 12),
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
            value('HRV νύχτας', hrv == null ? '—' : '${hrv.value.round()}', 'ms'),
          ]),
          if (hrv?.usual != null) ...[
            const SizedBox(height: 8),
            Text(
              'HRV: συνήθως ${hrv!.usual!.round()} ms (οι ${hrv.count} προηγούμενες νύχτες σου)',
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
            'Το HRV (μεταβλητότητα καρδιακού ρυθμού) ανεβαίνει όσο ξεκουράζεσαι. Κάθε σημείο είναι ο μέσος όρος μιας '
            'ολόκληρης νύχτας, γιατί αυτός μετριέται με ακρίβεια. Το συγκρίνουμε μόνο με τις δικές σου νύχτες.',
            style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// Αναπνοή (Oura) και οξυγόνο (ρολόι): δύο γραμμές, κάθε μία με την πηγή της. Ποτέ μαζί σε μία τιμή.
class _BreathCard extends StatelessWidget {
  const _BreathCard({required this.store, required this.day});
  final HealthStore store;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final plan = store.plan;
    final b = ouraBaseline(store.history, plan, K.breath, day);
    final ox = store.data?.watchSpo2(day);

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

    String breathNote() {
      if (b == null) return 'Δεν υπάρχει για αυτή τη νύχτα';
      if (b.usual == null) return 'Το συνηθισμένο σου βγαίνει μετά από $minNightsForBaseline νύχτες';
      final d = b.diff!;
      if (d.abs() < 1) return 'Συνηθισμένες για σένα (συνήθως ${dec(b.usual!)})';
      return '${dec(d.abs())} ${d > 0 ? 'πάνω' : 'κάτω'} από τις συνηθισμένες σου (${dec(b.usual!)})';
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
            ox == null ? 'Οξυγόνο —' : 'Οξυγόνο ${ox.avg.round()}%',
            ox == null
                ? 'Δεν υπάρχουν μετρήσεις του ρολογιού για αυτή τη νύχτα'
                : 'Χαμηλότερο ${ox.min.round()}% · ενδεικτικό'
                    '${ox.below90 == null ? '' : ' · κάτω από 90%: ${hoursMinutes(ox.below90!.round())} (ενδεικτικό)'}',
            Source.watch,
          ),
          const SizedBox(height: 6),
          Text(
            'Δεν είναι διάγνωση. Αν ροχαλίζεις ή είσαι κουρασμένος τη μέρα, το σωστό εργαλείο είναι το τεστ άπνοιας '
            'του Samsung Health Monitor και ο γιατρός σου.',
            style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.4),
          ),
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
                      m == null ? emptyNightText(reason ?? EmptyNight.noRing) : '${hm(m.onset ?? m.start)} – ${hm(m.end)}',
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
                      m.totalMinutes == null ? '—' : hoursMinutes(m.totalMinutes!),
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
      OuraStatus.waiting => 'Περιμένει το Oura',
      OuraStatus.missing => 'Χωρίς ύπνο από το δαχτυλίδι',
      OuraStatus.reconnect => 'Χρειάζεται νέα σύνδεση',
      OuraStatus.subscription => 'Η συνδρομή Oura δεν είναι ενεργή',
      OuraStatus.disconnected => 'Το Oura δεν είναι συνδεδεμένο',
      _ => '',
    };
