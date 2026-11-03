import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../sources.dart';
import '../theme.dart';
import '../widgets.dart';
import 'oura_sleep.dart';

class SleepPage extends StatelessWidget {
  const SleepPage({super.key, required this.store, this.now});
  final HealthStore store;

  /// Για τα στιγμιότυπα δοκιμών.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final c = Aigaio.of(context);
        // Μετά τη σύνδεση του Oura (ή την αποσύνδεσή του χωρίς άλλη πηγή): μόνο ύπνος από το Oura.
        if (store.plan.nightSource(now ?? DateTime.now()) != Source.watch) {
          return OuraSleepPage(store: store, now: now);
        }
        final d = store.data;
        final nights = d?.nights ?? const <Night>[];
        if (d == null || nights.isEmpty) {
          return PageFrame(
            title: 'Ύπνος',
            onRefresh: () => store.refresh(),
            left: [
              if (d != null && d.failed.contains('sleep'))
                EmptyCard(
                  icon: Icons.bedtime_rounded,
                  color: c.sleep,
                  title: 'Ο ύπνος δεν διαβάστηκε τώρα',
                  text: 'Η Samsung δεν τον έδωσε αυτή τη φορά. Τράβηξε την οθόνη προς τα κάτω για να ξαναδοκιμάσεις.',
                )
              else
                EmptyCard(
                  icon: Icons.bedtime_rounded,
                  color: c.sleep,
                  title: 'Δεν υπάρχει ύπνος ακόμα',
                  text: 'Φόρεσε το ρολόι στον ύπνο. Το πρωί θα δεις εδώ πότε κοιμήθηκες, πόσο και πόσο καλά.',
                ),
            ],
          );
        }

        final last14 = nights.length <= 14 ? nights : nights.sublist(nights.length - 14);
        final week = nights.length <= 7 ? nights : nights.sublist(nights.length - 7);
        final avg7 = Dashboard.mean(week.map((n) => n.minutes.toDouble()));
        final scoreAvg = Dashboard.mean(week.map((n) => n.score?.toDouble()));
        // Οι χωρισμένες νύχτες δεν έχουν βαθμολογία: λέμε από πόσες βγαίνει ο μέσος όρος.
        final scored = week.where((n) => n.score != null).length;

        return PageFrame(
          title: 'Ύπνος',
          subtitle: 'Οι τελευταίες ${nights.length} νύχτες',
          onRefresh: () => store.refresh(),
          left: [
            _LastNightCard(night: nights.last, data: d),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CardHeader(icon: Icons.bar_chart_rounded, title: 'Διάρκεια, 14 νύχτες', color: c.sleep),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _Summary(
                          label: 'Μέσος όρος εβδομάδας',
                          value: avg7 == null ? '—' : hoursMinutes(avg7.round()),
                        ),
                      ),
                      Expanded(
                        child: _Summary(
                          label: scored == week.length ? 'Μέση βαθμολογία' : 'Μέση βαθμολογία (${countText(scored, 'νύχτα', 'νύχτες')})',
                          value: scoreAvg == null ? '—' : '${scoreAvg.round()} από 100',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  BarChart(
                    values: [for (final n in last14) n.minutes / 60],
                    labels: [for (final n in last14) weekdayShort(n.date)],
                    average: avg7 == null ? null : avg7 / 60,
                    valueLabel: (v) => hoursMinutes((v * 60).round()),
                    color: c.sleep,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Η διακεκομμένη γραμμή είναι ο μέσος όρος της εβδομάδας.',
                    style: TextStyle(color: c.textTertiary, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            _ConsistencyCard(nights: last14),
          ],
          right: [
            const SectionHeader('Νύχτα προς νύχτα'),
            for (final n in nights.reversed.take(14)) _NightRow(night: n, now: d.readAt),
          ],
        );
      },
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: c.textSecondary, fontSize: 12.5)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: c.text, fontSize: 16, fontWeight: FontWeight.w700, fontFeatures: tabular)),
      ],
    );
  }
}

class _LastNightCard extends StatelessWidget {
  const _LastNightCard({required this.night, required this.data});
  final Night night;
  final Dashboard data;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final n = night;

    Widget clock(String label, DateTime t) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: c.textSecondary, fontSize: 13)),
              Text(
                hm(t),
                style: TextStyle(color: c.text, fontSize: 22, fontWeight: FontWeight.w700, fontFeatures: tabular),
              ),
            ],
          ),
        );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHeader(
            icon: Icons.bedtime_rounded,
            title: 'Τελευταία νύχτα · ${shortDayDate(n.date)}',
            color: c.sleep,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: DurationValue(n.minutes, size: 30)),
              ScoreRing(
                value: n.score?.toDouble(),
                size: 64,
                stroke: 6,
                color: c.sleep,
                track: c.tint(c.sleep),
                textColor: c.text,
                caption: 'βαθμολογία',
              ),
            ],
          ),
          if (n.estimatedMinutes > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Επιπλέον ${hoursMinutes(n.estimatedMinutes)} κενό της Samsung χωρίς βήματα, με παλμούς σαν του ύπνου: '
              'ίσως κοιμόσουν, ίσως ήσουν ξαπλωμένος ξύπνιος. Δεν μετρά στη διάρκεια.',
              style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.35),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              clock('Κοιμήθηκες', n.start),
              clock('Ξύπνησες', n.end),
              if (n.awakeMinutes > 0)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ξύπνιος', style: TextStyle(color: c.textSecondary, fontSize: 13)),
                      Text(
                        hoursMinutes(n.awakeMinutes),
                        style: TextStyle(color: c.text, fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Hypnogram(night: n, height: 64),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(hm(n.start), style: TextStyle(color: c.textTertiary, fontSize: 11.5)),
              const Spacer(),
              Text(hm(n.end), style: TextStyle(color: c.textTertiary, fontSize: 11.5)),
            ],
          ),
          const SizedBox(height: 14),
          StageLegend(night: n),
          const Hairline(vertical: 14),
          if (n.sleepingHr != null) InfoRow('Παλμοί στον ύπνο', '${n.sleepingHr!.round()} bpm', dot: c.heart),
          if (n.spo2Avg != null) InfoRow('Οξυγόνο, μέσος όρος', '${n.spo2Avg!.round()}%', dot: c.sleep),
          if (n.spo2Min != null) InfoRow('Οξυγόνο, χαμηλότερη μέτρηση', '${n.spo2Min!.round()}% · ενδεικτικό', dot: c.sleep),
          if (n.parts.length > 1) InfoRow('Η Samsung τη χώρισε σε', '${n.parts.length} κομμάτια', dot: c.textTertiary),
          if (n.parts.length > 1 && n.parts.any((p) => p.score != null))
            InfoRow(
              'Βαθμολογία Samsung ανά κομμάτι',
              [for (final p in n.parts) p.score?.toString() ?? '—'].join(' · '),
              dot: c.textTertiary,
            ),
          if (n.estimatedMinutes > 0)
            InfoRow('Πιθανός ύπνος στα κενά (δεν μετρά)', hoursMinutes(n.estimatedMinutes), dot: c.tint(c.sleep)),
          if (n.spanMinutes > n.minutes)
            InfoRow('Από τον ύπνο ως το ξύπνημα (με τα ξυπνήματα)', hoursMinutes(n.spanMinutes), dot: c.textTertiary),
          if (!n.staged)
            InfoRow('Χωρίς φάσεις από τη Samsung', 'διάρκεια όπως τη δίνει η Samsung', dot: c.textTertiary),
          if (n.napMinutes > 0) InfoRow('Υπνάκος ή χωριστός ύπνος (δεν μετρά)', hoursMinutes(n.napMinutes), dot: c.textTertiary),
        ],
      ),
    );
  }
}

class _ConsistencyCard extends StatelessWidget {
  const _ConsistencyCard({required this.nights});
  final List<Night> nights;

  /// Λεπτά μετά τις 18:00, ώστε τα μεσάνυχτα να μη «σπάνε» τον μέσο όρο.
  int _fromSix(DateTime t) => (t.hour * 60 + t.minute - 18 * 60 + 1440) % 1440;

  String _clock(double minutesFromSix) {
    final m = (minutesFromSix.round() + 18 * 60) % 1440;
    return '${two(m ~/ 60)}:${two(m % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    if (nights.length < 3) return const SizedBox.shrink();
    final bed = nights.map((n) => _fromSix(n.start).toDouble()).toList();
    final wake = nights.map((n) => _fromSix(n.end).toDouble()).toList();
    final bedAvg = Dashboard.mean(bed)!;
    final wakeAvg = Dashboard.mean(wake)!;
    final spread = bed.map((b) => (b - bedAvg).abs()).reduce((a, b) => a + b) / bed.length;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHeader(icon: Icons.schedule_rounded, title: 'Ωράριο, 14 νύχτες', color: c.sleep),
          const SizedBox(height: 8),
          InfoRow('Συνήθως κοιμάσαι', _clock(bedAvg)),
          InfoRow('Συνήθως ξυπνάς', _clock(wakeAvg)),
          InfoRow('Η ώρα ύπνου αλλάζει συνήθως', '± ${hoursMinutes(spread.round())}'),
        ],
      ),
    );
  }
}

class _NightRow extends StatelessWidget {
  const _NightRow({required this.night, required this.now});
  final Night night;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
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
                      relativeDay(night.date, now) == 'Σήμερα' ? 'Χθες βράδυ' : shortDayDate(night.date),
                      style: TextStyle(color: c.text, fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${hm(night.start)} – ${hm(night.end)}',
                      style: TextStyle(color: c.textSecondary, fontSize: 13.5, fontFeatures: tabular),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    hoursMinutes(night.minutes),
                    style: TextStyle(color: c.text, fontWeight: FontWeight.w700, fontSize: 15, fontFeatures: tabular),
                  ),
                  if (night.score != null)
                    Text(
                      'βαθμολογία ${night.score}',
                      style: TextStyle(color: c.sleep, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          StageTimeline(night: night, height: 8),
        ],
      ),
    );
  }
}
