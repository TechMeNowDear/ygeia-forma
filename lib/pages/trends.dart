import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../history.dart';
import '../sources.dart';
import '../theme.dart';
import '../trends.dart';
import '../widgets.dart';
import 'report_page.dart';

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
        final results = computeAllTrends(store.history, today, _period, plan: store.analysisPlan);
        final changed = results.where((r) => r.changed).toList()..sort((a, b) => b.z.compareTo(a.z));

        final selector = _PeriodSelector(
          period: _period,
          onChanged: (p) => setState(() => _period = p),
        );

        final progress = store.backfillVisible || store.rereading || store.prefs.staleMonths.isNotEmpty
            ? _BackfillCard(
                reached: store.backfillReached,
                rereadFrom: store.rereadBoundary,
                stale: store.prefs.staleMonths,
              )
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

        final reportButton = TextButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(settings: const RouteSettings(name: 'Για γιατρό'), builder: (_) => ReportPage(store: store, now: widget.now, end: today)),
          ),
          style: TextButton.styleFrom(
            backgroundColor: c.card,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: const StadiumBorder(),
          ),
          icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
          label: const Text('Για γιατρό'),
        );

        return PageFrame(
          action: store.history.isEmpty ? null : reportButton,
          title: 'Τάσεις',
          subtitle: 'Συγκρίνω ${periodExplanation(_period)}. Κάθε τιμή είναι η μεσαία της περιόδου.',
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
    final c = Aigaio.of(context);
    return SegmentedButton<TrendPeriod>(
      showSelectedIcon: false,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.primary : c.card,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onPrimary : c.text,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: c.hairline)),
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
  const _BackfillCard({required this.reached, this.rereadFrom, this.stale = const []});

  /// Ως πού έχει φτάσει (null = μόλις ξεκίνησε).
  final DateTime? reached;

  /// C4: το ιστορικό ξαναϋπολογίζεται με νέους κανόνες· πριν από αυτή τη μέρα, ακόμα ο παλιός ορισμός.
  final DateTime? rereadFrom;

  /// C4: κομμάτια (30 μέρες ως τη μέρα-κλειδί) που δεν ξαναϋπολογίστηκαν μετά από 3 προσπάθειες.
  final List<String> stale;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final r = reached;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHeader(
            icon: Icons.history_rounded,
            title: rereadFrom != null ? 'Ενημερώνεται το ιστορικό' : 'Φέρνω το ιστορικό σου από το Samsung Health',
            color: c.primary,
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            // Χωρίς ποσοστό: δεν ξέρουμε από πριν πόσα χρόνια έχει η Samsung.
            child: LinearProgressIndicator(minHeight: 8, color: c.primary, backgroundColor: c.tint(c.primary)),
          ),
          const SizedBox(height: 10),
          Text(
            '${r == null ? '' : 'Έφτασα στις ${dayMonth(r)} ${r.year}. '}'
            'Πρώτα οι μήνες που χρειάζονται οι Τάσεις· τα παλιότερα χρόνια (ως 10) έρχονται μετά, χωρίς αυτή την κάρτα. '
            'Προχωρά μόνο όσο είναι ανοιχτή η εφαρμογή· αν την κλείσεις, συνεχίζει από εκεί που έμεινε. '
            'Μέχρι τότε, οι συγκρίσεις 3 μηνών και χρόνου μπορεί να λένε «λίγα δεδομένα».',
            style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.4),
          ),
          if (rereadFrom != null) ...[
            const SizedBox(height: 8),
            Text(
              rereadNote(rereadFrom!),
              style: TextStyle(color: c.text, fontSize: 13, height: 1.4),
            ),
          ],
          if (stale.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(staleMonthsNote(stale), style: TextStyle(color: c.text, fontSize: 13, height: 1.4)),
          ],
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
                // Κλινικός έλεγχος M7 (4/11): όχι «ουσιαστικά», που διαβάζεται ως «κλινικά».
                'Καμία διαφορά δεν πέρασε τα όρια ελέγχου. Ό,τι αλλάζει είναι μέσα στις συνηθισμένες μέρα-με-μέρα '
                'διακυμάνσεις σου. Αυτό δεν είναι ιατρικός έλεγχος.',
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
    final color = trendSectionColor(c, r.def.section);
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
                Text(metricLabel(r.def, r.source), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                const SizedBox(height: 2),
                Text(
                  'από ${r.def.formatAs(r.previous!, r.source)} σε ${r.def.formatAs(r.current!, r.source)}',
                  style: TextStyle(fontSize: 13.5, color: c.textSecondary, fontFeatures: tabular),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TrendStatusPill(r: r),
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
    final color = trendSectionColor(c, section);
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
    // Με λίγες μέρες (π.χ. μία νύχτα μετά από αλλαγή πηγής) η «μεσαία της περιόδου» δεν λέει κάτι: «—»
    // (έλεγχος υπολογισμών F10). Η τιμή και το πλήθος φαίνονται στις λεπτομέρειες.
    final few = r.nCurrent < r.needed && (r.status == TrendStatus.insufficient || r.status == TrendStatus.sourceChange);
    final value = r.current == null || few ? '—' : r.def.formatAs(r.current!, r.source);
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
                      Text(metricLabel(r.def, r.source), style: TextStyle(fontSize: 15, color: c.textSecondary)),
                      const SizedBox(height: 2),
                      Text(
                        value,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: r.current == null || few ? c.textTertiary : c.text,
                          fontFeatures: tabular,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TrendStatusPill(r: r),
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
    final len = daysBetween(r.currentFrom, r.end) + 1;

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
              levels: [
                if (r.previous != null) (r.previousFrom, r.previousEnd, r.previous!, c.textSecondary),
                if (r.current != null && r.status != TrendStatus.sourceChange) (r.currentFrom, r.end, r.current!, c.text),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (r.status == TrendStatus.sourceChange) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: c.tint(c.sleep), borderRadius: BorderRadius.circular(16)),
              child: Text(
                r.rereading
                    ? rereadNote(r.changedOn!)
                    : definitionMetrics.contains(def.key)
                    // Ίδια συσκευή (ρολόι), άλλος ορισμός: μετά τη σύνδεση του Oura μετρά μέσα στις ώρες ύπνου του.
                    ? 'Αλλαγή ${dayMonth(r.changedOn!)}: από εκείνη τη μέρα ο ύπνος έρχεται από άλλη πηγή, οπότε η τιμή '
                        'του ρολογιού υπολογίζεται μέσα σε άλλες ώρες ύπνου. Δεν συγκρίνω τιμές από πριν και μετά. Το '
                        'γράφημα δείχνει μόνο τις μέρες από την αλλαγή.'
                    : 'Αλλαγή πηγής ${dayMonth(r.changedOn!)}: από εκείνη τη μέρα η μέτρηση έρχεται από ${sourceDevice(r.source)}. '
                        'Δύο συσκευές δεν μετρούν το ίδιο, οπότε δεν συγκρίνω τιμές από πριν και μετά. Το γράφημα δείχνει μόνο '
                        'τις μέρες από την αλλαγή· η σύγκριση ξαναρχίζει όταν μαζευτούν αρκετές μέρες από τη νέα πηγή.',
                style: style.copyWith(color: c.text),
              ),
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
                  'Τώρα · ${dayMonth(r.currentFrom)} – ${dayMonth(r.end)}',
                  r.current == null ? '—' : def.formatAs(r.current!, r.source),
                  dot: c.text,
                ),
                InfoRow(
                  'Πριν · ${dayMonth(r.previousFrom)} – ${dayMonth(r.previousEnd)}',
                  r.previous == null ? '—' : def.formatAs(r.previous!, r.source),
                  dot: c.textSecondary,
                ),
                InfoRow('Με δεδομένα (τώρα)', count(r.nCurrent)),
                InfoRow('Με δεδομένα (πριν)', count(r.nPrevious)),
                if (r.source != Source.watch) InfoRow('Πηγή', sourceDevice(r.source)),
                const Hairline(vertical: 8),
                Text('Οι διακεκομμένες γραμμές στο γράφημα είναι η μεσαία τιμή κάθε περιόδου.', style: style),
                const SizedBox(height: 6),
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
class TrendStatusPill extends StatelessWidget {
  const TrendStatusPill({required this.r});
  final TrendResult r;

  @override
  Widget build(BuildContext context) {
    if (r.status == TrendStatus.insufficient) return const TrendPill('Λίγα δεδομένα');
    if (r.status == TrendStatus.sourceChange) {
      if (r.rereading) return const TrendPill('Ενημερώνεται το ιστορικό');
      return TrendPill(definitionMetrics.contains(r.def.key) ? 'Αλλαγή ορισμού' : 'Αλλαγή πηγής');
    }
    if (r.status == TrendStatus.stable) return const TrendPill('Σταθερό');
    final up = r.status == TrendStatus.up;
    final kind = switch (r.goodness) {
      1 => TrendKind.good,
      -1 => TrendKind.bad,
      _ => TrendKind.neutral,
    };
    if (r.def.kind == ValueKind.clock) {
      return TrendPill('${r.def.formatDiff(r.displayDiff!)} ${up ? 'αργότερα' : 'νωρίτερα'}', kind: kind);
    }
    return TrendPill(r.def.formatDiff(r.displayDiff!), kind: kind, up: up);
  }
}

// ---------------------------------------------------------------------------

String _explain(TrendResult r) {
  final def = r.def;
  final len = daysBetween(r.currentFrom, r.end) + 1;
  final minDiff = switch (def.kind) {
    ValueKind.number => '${dec(def.minDiff, def.digits)}${def.unit.isEmpty ? '' : ' ${def.unit}'}',
    _ => hoursMinutes(def.minDiff.round()),
  };
  final b = StringBuffer()
    ..write('Συγκρίνω τη μεσαία τιμή κάθε περιόδου (μισές μέρες πάνω, μισές κάτω), ώστε μια περίεργη μέρα να μη χαλάει το αποτέλεσμα. ')
    ..write('Λέω «άλλαξε» μόνο αν η διαφορά είναι τουλάχιστον $minDiff, ξεκάθαρα μεγαλύτερη από τις συνηθισμένες διακυμάνσεις σου, '
        'και ο μέσος όρος αλλάζει προς την ίδια κατεύθυνση. Είναι ένδειξη, όχι ιατρικός έλεγχος. ');
  if (def.sparse) {
    b.write('Χρειάζονται τουλάχιστον ${r.needed} ζυγίσεις σε κάθε περίοδο.');
  } else {
    b.write('Χρειάζονται δεδομένα τουλάχιστον ${r.needed} από τις $len μέρες κάθε περιόδου.');
  }
  if (def.partial && r.source == Source.watch) {
    b.write(' Μετρούν μόνο οι νύχτες που η Samsung δεν χώρισε σε κομμάτια, γιατί μόνο αυτές έχουν μία βαθμολογία.');
  }
  if (!def.includeToday) b.write(' Η σημερινή μέρα δεν μετράει, γιατί δεν έχει τελειώσει.');
  if (def.key == K.dayHr) {
    b.write(' Μέσος όρος των παλμών όσο είσαι ξύπνιος, χωρίς τον ύπνο και τις ασκήσεις.');
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

Color trendSectionColor(Aigaio c, TrendSection s) => switch (s) {
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
