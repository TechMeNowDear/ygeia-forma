import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../history.dart';
import '../profile.dart';
import '../reference.dart';
import '../shown.dart';
import '../sources.dart';
import '../theme.dart';
import '../widgets.dart';
import 'info_sheet.dart';
import 'source_widgets.dart';

/// Πώς δείχνεται μια μέτρηση στη σελίδα της (7/11, σχέδιο «σελίδα μέτρησης»).
class MetricSpec {
  const MetricSpec({
    required this.metric,
    required this.title,
    required this.unit,
    required this.color,
    this.digits = 0,
    this.signed = false,
    this.thousandsSep = false,
    this.dayComplete = false,
    this.range,
    this.scale,
    this.periods = const [7, 30, 90],
  });

  final String metric;
  final String title;
  final String unit;
  final Color Function(Aigaio c) color;
  final int digits;

  /// Με πρόσημο (θερμοκρασία: απόκλιση από τα συνηθισμένα).
  final bool signed;
  final bool thousandsSep;

  /// Η σημερινή μέρα δεν έχει τελειώσει (βήματα, παλμοί ξύπνιος): μετρούν μόνο ως χθες.
  final bool dayComplete;

  /// Το εύρος αναφοράς για τον χρήστη (null = μόνο σε σχέση με τον εαυτό του).
  final RefRange? Function(Profile p, DateTime today)? range;

  /// Τα άκρα της μπάρας εύρους.
  final (double, double) Function(RefRange r)? scale;

  /// Οι περίοδοι του γραφήματος σε μέρες· η μεσαία ανοίγει πρώτη. Ζύγιση μία φορά την εβδομάδα → 30/90/365.
  final List<int> periods;

  String show(double v) {
    if (signed) return signedDec(v, digits);
    if (thousandsSep) return thousands(v.round());
    return digits == 0 ? '${v.round()}' : dec(v, digits);
  }
}

RefRange? _weightRange(Profile p, DateTime _) {
  final w = healthyWeight(p.heightCm);
  if (w == null) return null;
  return RefRange(low: w.$1, high: w.$2, text: 'υγιές βάρος για το ύψος σου ${dec(w.$1)}–${dec(w.$2)} kg', cite: bmiRange.cite);
}

const _bodyPeriods = [30, 90, 365];

final metricSpecs = <String, MetricSpec>{
  K.sleepHr: MetricSpec(metric: K.sleepHr, title: 'Παλμοί στον ύπνο', unit: 'bpm', color: (c) => c.heart),
  K.dayHr: MetricSpec(metric: K.dayHr, title: 'Παλμοί ξύπνιος', unit: 'bpm', color: (c) => c.heart, dayComplete: true),
  K.energy: MetricSpec(metric: K.energy, title: 'Ετοιμότητα', unit: '/100', color: (c) => c.energy),
  K.hrv: MetricSpec(metric: K.hrv, title: 'HRV', unit: 'ms', color: (c) => c.sleep),
  K.skinTemp: MetricSpec(metric: K.skinTemp, title: 'Θερμοκρασία στον ύπνο', unit: '°C', color: (c) => c.move, digits: 1, signed: true),
  K.breath: MetricSpec(
    metric: K.breath,
    title: 'Αναπνοές στον ύπνο',
    unit: '/λεπτό',
    color: (c) => c.sleep,
    digits: 1,
    range: (_, __) => breathRange,
    scale: (_) => (8, 24),
  ),
  K.weight: MetricSpec(
    metric: K.weight,
    title: 'Βάρος',
    unit: 'kg',
    color: (c) => c.body,
    digits: 1,
    range: _weightRange,
    scale: (r) => (r.low! - 15, r.high! + 25),
    periods: _bodyPeriods,
  ),
  K.fatPct: MetricSpec(
    metric: K.fatPct,
    title: 'Λίπος σώματος',
    unit: '%',
    color: (c) => c.body,
    digits: 1,
    range: fatRange,
    scale: (_) => (5, 40),
    periods: _bodyPeriods,
  ),
  K.smm: MetricSpec(metric: K.smm, title: 'Σκελετικοί μύες', unit: 'kg', color: (c) => c.body, digits: 1, periods: _bodyPeriods),
  K.steps: MetricSpec(
    metric: K.steps,
    title: 'Βήματα',
    unit: '',
    color: (c) => c.exercise,
    thousandsSep: true,
    dayComplete: true,
    range: stepsRange,
    scale: (_) => (0, 14000),
  ),
};

/// Η σελίδα μιας μέτρησης: τελευταία τιμή, εύρος (αν υπάρχει), γράφημα 7/30/90 ημερών, μικρά στατιστικά, οι τελευταίες
/// τιμές και η πηγή. Μία πηγή ανά γράφημα (planSeries κόβει στην αλλαγή πηγής).
class MetricPage extends StatefulWidget {
  const MetricPage({super.key, required this.store, required this.spec, this.now});
  final HealthStore store;
  final MetricSpec spec;
  final DateTime? now;

  static Route<void> route(HealthStore store, String metric, {DateTime? now}) => MaterialPageRoute<void>(
        settings: RouteSettings(name: 'Μέτρηση · ${metricSpecs[metric]!.title}'),
        builder: (_) => MetricPage(store: store, spec: metricSpecs[metric]!, now: now),
      );

  @override
  State<MetricPage> createState() => _MetricPageState();
}

class _MetricPageState extends State<MetricPage> {
  late int _days = widget.spec.periods[1];

  String _label(int d, bool first) {
    if (d == 365) return '1 χρόνος';
    return first ? '$d μέρες' : '$d';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.spec;
    final store = widget.store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final c = Aigaio.of(context);
        final color = s.color(c);
        final today = dayOf(widget.now ?? DateTime.now());
        final end = s.dayComplete ? DateTime(today.year, today.month, today.day - 1) : today;
        final from = DateTime(end.year, end.month, end.day - _days + 1);
        final series = planSeries(store.history, store.plan, s.metric, from, end);
        final pts = series.points;
        final last = pts.isEmpty ? null : pts.last;
        final base = last == null ? null : personalBaseline(store.history, store.plan, s.metric, last.$1);
        final range = s.range?.call(store.profile, today);
        final vals = [for (final p in pts) p.$2];
        final mean = vals.isEmpty ? null : vals.reduce((a, b) => a + b) / vals.length;
        double? lo, hi;
        for (final v in vals) {
          lo = lo == null || v < lo ? v : lo;
          hi = hi == null || v > hi ? v : hi;
        }
        String? usual;
        if (base?.usual != null) {
          final d = shownDiff(base!.value, base.usual!, s.digits);
          final unit = s.unit.isEmpty ? '' : ' ${s.unit}';
          usual = d == 0
              ? '$asUsualText · συνήθως ${s.show(base.usual!)}$unit'
              : '${signedShown(d, s.digits)}$unit · συνήθως ${s.show(base.usual!)}$unit';
        }

        final head = AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                  child: Text(last == null ? 'Καμία τιμή' : shortDayDate(last.$1),
                      style: TextStyle(color: c.textSecondary, fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
                SourceTag(series.source),
              ]),
              const SizedBox(height: 6),
              BigValue(last == null ? '—' : s.show(last.$2), unit: s.unit.isEmpty ? null : s.unit, size: 44),
              if (usual != null) ...[
                const SizedBox(height: 6),
                Text(usual, style: TextStyle(color: c.textSecondary, fontSize: 14)),
              ],
              if (range != null && last != null && s.scale != null) ...[
                const SizedBox(height: 14),
                RangeNote(value: last.$2, range: range, min: s.scale!(range).$1, max: s.scale!(range).$2, color: color),
              ],
            ],
          ),
        );

        final chart = AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<int>(
                key: const ValueKey('metric-period'),
                showSelectedIcon: false,
                segments: [
                  for (final d in s.periods)
                    ButtonSegment(
                      value: d,
                      label: Text(_label(d, d == s.periods.first), style: const TextStyle(fontFamily: 'Inter')),
                    ),
                ],
                selected: {_days},
                onSelectionChanged: (v) => setState(() => _days = v.first),
              ),
              const SizedBox(height: 14),
              if (pts.length >= 2)
                LineChart(points: pts, color: color, format: s.show, dateLabel: dayMonth)
              else
                Text('Λίγες τιμές για γράφημα σε αυτό το διάστημα.', style: TextStyle(color: c.textSecondary)),
              if (series.cut != null) ...[
                const SizedBox(height: 8),
                Text('Από ${dayMonth(series.cut!)}: άλλαξε η πηγή, τα παλιότερα δεν μπαίνουν στο ίδιο γράφημα.',
                    style: TextStyle(color: c.textTertiary, fontSize: 12.5)),
              ],
              if (mean != null) ...[
                const Hairline(vertical: 12),
                InfoRow('Μέσος όρος', s.show(mean)),
                InfoRow('Χαμηλότερη · υψηλότερη', '${s.show(lo!)} · ${s.show(hi!)}'),
                InfoRow('Μέρες με τιμή', '${pts.length} από $_days'),
              ],
            ],
          ),
        );

        final recent = AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Τελευταίες τιμές', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.textSecondary)),
              const SizedBox(height: 6),
              if (pts.isEmpty) Text('—', style: TextStyle(color: c.textSecondary)),
              for (final p in pts.reversed.take(10))
                InfoRow(shortDayDate(p.$1), '${s.show(p.$2)}${s.unit.isEmpty ? '' : ' ${s.unit}'}'),
            ],
          ),
        );

        return Scaffold(
          appBar: AppBar(
            title: Text(s.title),
            actions: [InfoButton(s.metric, range: range), const SizedBox(width: 4)],
          ),
          body: SafeArea(
            child: LayoutBuilder(builder: (context, k) {
              final wide = k.maxWidth >= 680;
              const pad = EdgeInsets.fromLTRB(16, 4, 16, 24);
              if (!wide) {
                return ListView(padding: pad, children: [head, const SizedBox(height: 12), chart, const SizedBox(height: 12), recent]);
              }
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: SingleChildScrollView(
                    padding: pad,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Column(children: [head, const SizedBox(height: 12), recent])),
                        const SizedBox(width: 16),
                        Expanded(child: chart),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
