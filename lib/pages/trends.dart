import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../history.dart';
import '../theme.dart';
import '../trends.dart';
import '../widgets.dart';

/// Τάσεις: τι άλλαξε τον τελευταίο μήνα, τους 3 μήνες ή μέσα στον χρόνο.
/// Λέμε «άλλαξε» μόνο όταν η αλλαγή είναι πραγματική (κανόνες στο trends.dart).
class TrendsPage extends StatefulWidget {
  const TrendsPage({super.key, required this.store, this.now});
  final HealthStore store;

  /// Μόνο για τα στιγμιότυπα δοκιμών.
  final DateTime? now;

  @override
  State<TrendsPage> createState() => _TrendsPageState();
}

class _TrendsPageState extends State<TrendsPage> {
  TrendPeriod _period = TrendPeriod.month;
  final _open = <String>{};

  void _toggle(String key) => setState(() => _open.contains(key) ? _open.remove(key) : _open.add(key));

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final c = Aigaio.of(context);
        final today = dayOf(widget.now ?? store.data?.readAt ?? DateTime.now());
        final results = computeAllTrends(store.history, today, _period);
        final changed = results.where((r) => r.changed).toList()..sort((a, b) => b.z.compareTo(a.z));

        final selector = _PeriodSelector(
          period: _period,
          onChanged: (p) => setState(() => _period = p),
        );

        final progress = store.backfilling
            ? _BackfillCard(progress: store.backfillProgress)
            : null;

        final Widget summary = store.history.isEmpty
            ? EmptyCard(
                icon: Icons.insights_rounded,
                color: c.primary,
                title: 'Δεν υπάρχει ακόμα ιστορικό',
                text: 'Άνοιξε τη Σήμερα και τράβηξε προς τα κάτω για ανανέωση. '
                    'Οι μέρες αποθηκεύονται στο κινητό σου και οι τάσεις γεμίζουν μόνες τους.',
              )
            : _ChangedCard(changed: changed, period: _period);

        Widget section(TrendSection s) => _SectionCard(
              section: s,
              results: [for (final r in results) if (r.def.section == s) r],
              open: _open,
              onToggle: _toggle,
            );

        final left = <Widget>[
          selector,
          if (progress != null) progress,
          summary,
          section(TrendSection.heart),
          section(TrendSection.sleep),
        ];
        final right = <Widget>[
          section(TrendSection.body),
          section(TrendSection.move),
          section(TrendSection.other),
        ];

        return PageFrame(
          title: 'Τάσεις',
          subtitle: 'Συγκρίνω ${periodExplanation(_period)}',
          onRefresh: () => store.refresh(),
          left: left,
          right: right,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.period, required this.onChanged});
  final TrendPeriod period;
  final ValueChanged<TrendPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<TrendPeriod>(
      showSelectedIcon: false,
      style: ButtonStyle(
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontFamily: fontFamily, fontSize: 14.5, fontWeight: FontWeight.w600),
        ),
        visualDensity: VisualDensity.standard,
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 12)),
      ),
      segments: [
        for (final p in TrendPeriod.values) ButtonSegment(value: p, label: Text(periodLabel(p), key: ValueKey('period-${p.name}'))),
      ],
      selected: {period},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

class _BackfillCard extends StatelessWidget {
  const _BackfillCard({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final pct = (progress.clamp(0, 1) * 100).round();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHeader(
            icon: Icons.history_rounded,
            title: 'Φέρνω το ιστορικό σου από το Samsung Health',
            color: c.primary,
            trailing: Text(
              '$pct%',
              style: TextStyle(fontWeight: FontWeight.w700, color: c.text, fontFeatures: tabular),
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress.clamp(0, 1).toDouble(),
              minHeight: 8,
              color: c.primary,
              backgroundColor: c.tint(c.primary),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Μία φορά, για τους τελευταίους 12 μήνες. Προχωρά μόνο όσο είναι ανοιχτή η εφαρμογή· '
            'αν την κλείσεις, συνεχίζει από εκεί που έμεινε. Μέχρι τότε, οι συγκρίσεις 3 μηνών και χρόνου μπορεί να λένε «λίγα δεδομένα».',
            style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// Η περίληψη: μόνο ό,τι άλλαξε πραγματικά, το πιο ξεκάθαρο πρώτο.
class _ChangedCard extends StatelessWidget {
  const _ChangedCard({required this.changed, required this.period});
  final List<TrendResult> changed;
  final TrendPeriod period;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHeader(icon: Icons.insights_rounded, title: 'Τι άλλαξε', color: c.primary),
          const SizedBox(height: 6),
          if (changed.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Τίποτα δεν άλλαξε ουσιαστικά. Ό,τι διαφορές υπάρχουν είναι μέσα στις συνηθισμένες μέρα-με-μέρα διακυμάνσεις σου.',
                style: TextStyle(color: c.textSecondary, fontSize: 14.5, height: 1.4),
              ),
            )
          else
            for (var i = 0; i < changed.length; i++) ...[
              if (i > 0) const Hairline(vertical: 4),
              _ChangeRow(r: changed[i]),
            ],
        ],
      ),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.r});
  final TrendResult r;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final color = _sectionColor(c, r.def.section);
    final up = r.status == TrendStatus.up;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          IconBadge(up ? Icons.trending_up_rounded : Icons.trending_down_rounded, color, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.def.label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                const SizedBox(height: 2),
                Text(
                  'από ${r.def.format(r.previous!)} σε ${r.def.format(r.current!)}',
                  style: TextStyle(fontSize: 13.5, color: c.textSecondary, fontFeatures: tabular),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _StatusPill(r: r),
        ],
      ),
    );
  }
}

/// Μία κάρτα ανά ενότητα, με μία γραμμή ανά μέτρηση· πάτημα → γράφημα και εξήγηση.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section, required this.results, required this.open, required this.onToggle});
  final TrendSection section;
  final List<TrendResult> results;
  final Set<String> open;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final color = _sectionColor(c, section);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHeader(icon: _sectionIcon(section), title: sectionLabel(section), color: color),
          const SizedBox(height: 4),
          for (var i = 0; i < results.length; i++) ...[
            if (i > 0) const Hairline(vertical: 0),
            _MetricRow(
              r: results[i],
              color: color,
              expanded: open.contains(results[i].def.key),
              onTap: () => onToggle(results[i].def.key),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.r, required this.color, required this.expanded, required this.onTap});
  final TrendResult r;
  final Color color;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final value = r.current == null ? '—' : r.def.format(r.current!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: ValueKey('trend-${r.def.key}'),
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.def.label, style: TextStyle(fontSize: 15, color: c.textSecondary)),
                      const SizedBox(height: 2),
                      Text(
                        value,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: r.current == null ? c.textTertiary : c.text,
                          fontFeatures: tabular,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatusPill(r: r),
                const SizedBox(width: 4),
                Icon(
                  expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 20,
                  color: c.textTertiary,
                ),
              ],
            ),
          ),
        ),
        if (expanded) _MetricDetail(r: r, color: color),
      ],
    );
  }
}

class _MetricDetail extends StatelessWidget {
  const _MetricDetail({required this.r, required this.color});
  final TrendResult r;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final def = r.def;
    final style = TextStyle(color: c.textSecondary, fontSize: 13.5, height: 1.45);
    final unitWord = def.sparse ? 'ζυγίσεις' : 'μέρες';
    final len = r.end.difference(r.currentFrom).inDays + 1;

    String count(int n) => def.sparse ? '$n $unitWord' : '$n από $len $unitWord';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (r.points.length >= 2) ...[
            LineChart(
              height: 150,
              points: r.points,
              color: color,
              format: _axisFormat(def),
              minRange: _minRange(def),
              dateLabel: dayMonth,
            ),
            const SizedBox(height: 10),
          ],
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InfoRow(
                  '${dayMonth(r.currentFrom)} – ${dayMonth(r.end)}',
                  r.current == null ? '—' : def.format(r.current!),
                  dot: color,
                ),
                InfoRow(
                  '${dayMonth(r.previousFrom)} – ${dayMonth(_previousEnd(r))}',
                  r.previous == null ? '—' : def.format(r.previous!),
                  dot: c.textTertiary,
                ),
                InfoRow('Με δεδομένα (τώρα)', count(r.nCurrent)),
                InfoRow('Με δεδομένα (πριν)', count(r.nPrevious)),
                const Hairline(vertical: 8),
                Text(_explain(r), style: style),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Το «χάπι» δεξιά: ↓ 3 bpm / Σταθερό / Λίγα δεδομένα.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.r});
  final TrendResult r;

  @override
  Widget build(BuildContext context) {
    if (r.status == TrendStatus.insufficient) return const TrendPill('Λίγα δεδομένα');
    if (r.status == TrendStatus.stable) return const TrendPill('Σταθερό');
    final up = r.status == TrendStatus.up;
    final kind = switch (r.goodness) {
      1 => TrendKind.good,
      -1 => TrendKind.bad,
      _ => TrendKind.neutral,
    };
    if (r.def.kind == ValueKind.clock) {
      return TrendPill('${r.def.formatDiff(r.diff!)} ${up ? 'αργότερα' : 'νωρίτερα'}', kind: kind);
    }
    return TrendPill(r.def.formatDiff(r.diff!), kind: kind, up: up);
  }
}

// ---------------------------------------------------------------------------

DateTime _previousEnd(TrendResult r) {
  final len = r.end.difference(r.currentFrom).inDays + 1;
  return DateTime(r.previousFrom.year, r.previousFrom.month, r.previousFrom.day + len - 1);
}

String _explain(TrendResult r) {
  final def = r.def;
  final len = r.end.difference(r.currentFrom).inDays + 1;
  final minDiff = switch (def.kind) {
    ValueKind.number => '${dec(def.minDiff, def.digits)}${def.unit.isEmpty ? '' : ' ${def.unit}'}',
    _ => hoursMinutes(def.minDiff.round()),
  };
  final b = StringBuffer()
    ..write('Συγκρίνω τη μεσαία τιμή κάθε περιόδου (μισές μέρες πάνω, μισές κάτω), ώστε μια περίεργη μέρα να μη χαλάει το αποτέλεσμα. ')
    ..write('Λέω «άλλαξε» μόνο αν η διαφορά είναι τουλάχιστον $minDiff και ξεκάθαρα μεγαλύτερη από τις συνηθισμένες διακυμάνσεις σου. ');
  if (def.sparse) {
    b.write('Χρειάζονται τουλάχιστον ${r.needed} ζυγίσεις σε κάθε περίοδο.');
  } else {
    b.write('Χρειάζονται δεδομένα τουλάχιστον ${r.needed} από τις $len μέρες κάθε περιόδου.');
  }
  if (!def.includeToday) b.write(' Η σημερινή μέρα δεν μετράει, γιατί δεν έχει τελειώσει.');
  if (def.key == K.restHr || def.key == K.walkHr || def.key == K.dayHr) {
    b.write(' Υπολογίζεται με τον ίδιο τρόπο όπως στην Καρδιά (παλμοί μαζί με βήματα ανά λεπτό).');
  }
  return b.toString();
}

String Function(double) _axisFormat(MetricDef def) => switch (def.kind) {
      ValueKind.clock => clockFromSix,
      ValueKind.duration => (v) {
          final m = v.round();
          return m >= 60 ? '${m ~/ 60}:${two(m % 60)}' : '$m′';
        },
      ValueKind.number => (v) => dec(v, def.digits),
    };

double _minRange(MetricDef def) => switch (def.key) {
      K.sleepMin => 120,
      K.bedtime => 120,
      K.awakeMin => 30,
      K.steps => 4000,
      K.activeMin => 60,
      _ => def.minDiff * 4,
    };

Color _sectionColor(Aigaio c, TrendSection s) => switch (s) {
      TrendSection.heart => c.heart,
      TrendSection.sleep => c.sleep,
      TrendSection.body => c.body,
      TrendSection.move => c.move,
      TrendSection.other => c.energy,
    };

IconData _sectionIcon(TrendSection s) => switch (s) {
      TrendSection.heart => Icons.favorite_rounded,
      TrendSection.sleep => Icons.bedtime_rounded,
      TrendSection.body => Icons.monitor_weight_rounded,
      TrendSection.move => Icons.directions_walk_rounded,
      TrendSection.other => Icons.bolt_rounded,
    };
