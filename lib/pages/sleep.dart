import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';

class SleepPage extends StatelessWidget {
  const SleepPage({super.key, required this.store});
  final HealthStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final d = store.data;
        final nights = d?.nights ?? const <Night>[];
        if (d == null || nights.isEmpty) {
          return PageFrame(
            title: 'Ύπνος',
            onRefresh: () => store.refresh(),
            left: const [
              EmptyCard(
                title: 'Δεν υπάρχει ύπνος ακόμα',
                text: 'Φόρεσε το ρολόι στον ύπνο. Το πρωί θα δεις εδώ διάρκεια, βαθμολογία και φάσεις.',
              ),
            ],
          );
        }

        final last14 = nights.length <= 14 ? nights : nights.sublist(nights.length - 14);
        final avg7 = Dashboard.mean(
          (nights.length <= 7 ? nights : nights.sublist(nights.length - 7)).map((n) => n.minutes.toDouble()),
        );

        return PageFrame(
          title: 'Ύπνος',
          subtitle: '${nights.length} νύχτες τις τελευταίες 30 μέρες',
          onRefresh: () => store.refresh(),
          left: [
            _LastNightCard(night: nights.last, data: d),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionLabel('Διάρκεια ανά νύχτα'),
                  const SizedBox(height: 4),
                  Text(
                    avg7 == null ? '' : 'Μέσος όρος εβδομάδας ${hoursMinutes(avg7.round())} (διακεκομμένη γραμμή)',
                    style: TextStyle(color: Aigaio.of(context).textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  BarChart(
                    values: [for (final n in last14) n.minutes / 60],
                    labels: [for (final n in last14) weekdayShort(n.date)],
                    average: avg7 == null ? null : avg7 / 60,
                    valueLabel: (v) => '${dec(v)} ώ',
                  ),
                ],
              ),
            ),
            _ConsistencyCard(nights: nights.length <= 14 ? nights : nights.sublist(nights.length - 14)),
          ],
          right: [
            const SectionLabel('Νύχτες'),
            for (final n in nights.reversed.take(14)) _NightRow(night: n, now: d.readAt),
          ],
        );
      },
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
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Τελευταία νύχτα · ${relativeDay(n.date, data.readAt)}',
                      style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hoursMinutes(n.minutes),
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: c.text),
                    ),
                    Text('${hm(n.start)} – ${hm(n.end)}', style: TextStyle(color: c.textSecondary)),
                  ],
                ),
              ),
              ScoreRing(value: n.score?.toDouble(), size: 64, stroke: 7, color: c.primary, track: c.background),
            ],
          ),
          const SizedBox(height: 14),
          StageTimeline(night: n),
          const SizedBox(height: 10),
          StageLegend(night: n),
          const SizedBox(height: 8),
          if (n.sleepingHr != null) InfoRow('Παλμοί στον ύπνο', '${n.sleepingHr!.round()} bpm'),
          if (n.spo2Avg != null)
            InfoRow(
              'Οξυγόνο (μέσο / χαμηλότερο)',
              '${n.spo2Avg!.round()}% / ${n.spo2Min?.round() ?? '—'}%',
              valueColor: (n.spo2Min ?? 100) < 88 ? c.terracotta : null,
            ),
          if (n.parts.length > 1) InfoRow('Κομμάτια ύπνου', '${n.parts.length}'),
          if (n.napMinutes > 0) InfoRow('Υπνάκος', hoursMinutes(n.napMinutes)),
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
          const SectionLabel('Ωράριο'),
          const SizedBox(height: 6),
          InfoRow('Συνήθως πέφτεις', _clock(bedAvg)),
          InfoRow('Συνήθως ξυπνάς', _clock(wakeAvg)),
          InfoRow('Απόκλιση ώρας ύπνου', '± ${hoursMinutes(spread.round())}'),
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
            children: [
              Expanded(
                child: Text(
                  '${relativeDay(night.date, now)} · ${shortDayDate(night.date)}',
                  style: TextStyle(color: c.text, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                hoursMinutes(night.minutes),
                style: TextStyle(color: c.text, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 10),
              Text(
                night.score == null ? '' : '${night.score}',
                style: TextStyle(color: c.primary, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          StageTimeline(night: night, height: 8),
        ],
      ),
    );
  }
}
