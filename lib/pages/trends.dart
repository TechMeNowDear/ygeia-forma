import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../history.dart';
import '../shown.dart';
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

        // Round 1 (S10-10): η γραμμή που κινείται και το «Φέρνω…» μόνο όσο ΠΡΑΓΜΑΤΙΚΑ διαβάζεται κάτι· με μόνο τη
        // σημείωση για τους μήνες με τον παλιό ορισμό, κάρτα χωρίς κίνηση (πριν: γραμμή χωρίς τέλος σε κάθε άνοιγμα).
        final reading = store.backfillVisible || store.rereading;
        final progress = reading || store.prefs.staleMonths.isNotEmpty
            ? _BackfillCard(
                reached: store.backfillReached,
                rereadFrom: store.rereadBoundary,
                stale: store.prefs.staleMonths,
                reading: reading,
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
            : _ChangedCard(
                changed: changed,
                period: _period,
                // UX U2: όταν καμία γραμμή δεν έχει αρκετά δεδομένα, δεν λέμε «καμία διαφορά», λέμε ότι δεν συγκρίθηκε.
                // Έλεγχος 9/11 (V-B-01): και όσα δεν είχαν αρκετές ανεξάρτητες μέρες δεν συγκρίθηκαν πραγματικά.
                nothingCompared: results.every(
                    (r) => r.status == TrendStatus.insufficient || r.status == TrendStatus.sourceChange || r.inconclusive),
                // Round 1 (S4-1): με «Λίγες … για συμπέρασμα» σε κάποια γραμμή, δεν λέμε ότι «ό,τι αλλάζει είναι μέσα στις
                // διακυμάνσεις σου» (εκεί δεν φάνηκε αν άλλαξε). Round 2 (R2-D-7): ούτε με «Λίγα δεδομένα» / «Αλλαγή πηγής».
                notCompared: notComparedText(results),
                // Round 9 (R9-A5-1 = R9-U4-5): μόνο οι γραμμές που πέρασαν πράγματι από τον έλεγχο ([testedRows]).
                rows: testedRows(results),
              );

        Widget section(TrendSection s) => _SectionCard(
              section: s,
              results: [for (final r in results) if (r.def.section == s) r],
              open: _open,
              onToggle: _toggle,
            );

        // Round 1 (U1b-14): στο ανοιχτό Fold ο επιλογέας περιόδου (για όλη τη σελίδα) και η πρόοδος σε όλο το πλάτος, και
        // οι στήλες πιο ισορροπημένες· στο κινητό η ίδια σειρά με πριν.
        final top = <Widget>[selector, if (progress != null) progress];
        final left = <Widget>[summary, section(TrendSection.sleep)];
        final right = <Widget>[
          section(TrendSection.heart),
          section(TrendSection.body),
          section(TrendSection.move),
          section(TrendSection.other),
        ];
        final single = <Widget>[
          ...top,
          summary,
          section(TrendSection.heart),
          section(TrendSection.sleep),
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
          top: top,
          left: left,
          right: right,
          single: single,
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
    // Σχέδια 9/11: ο κοινός επιλογέας περιόδου («30 μέρες · 3 μήνες · 1 χρόνος»), επιλογή στο χρώμα της Υγείας.
    return PeriodPicker<TrendPeriod>(
      values: TrendPeriod.values,
      days: periodDays,
      selected: period,
      onChanged: onChanged,
      color: Aigaio.of(context).health,
      keyOf: (p) => 'period-${p.name}',
    );
  }
}

class _BackfillCard extends StatelessWidget {
  const _BackfillCard({required this.reached, this.rereadFrom, this.stale = const [], this.reading = true});

  /// Round 1 (S10-10): διαβάζεται τώρα ιστορικό (συμπλήρωση ή επανανάγνωση). false: μόνο η σημείωση για τους μήνες.
  final bool reading;

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
    if (!reading) {
      return AppCard(
        key: const ValueKey('trends-stale-months'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CardHeader(icon: Icons.history_rounded, title: 'Μήνες με παλιό υπολογισμό ύπνου', color: c.primary),
            const SizedBox(height: 10),
            Text(staleMonthsNote(stale), style: TextStyle(color: c.text, fontSize: 13, height: 1.4)),
          ],
        ),
      );
    }
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
  const _ChangedCard(
      {required this.changed, required this.period, this.nothingCompared = false, this.notCompared, this.rows = 0});
  final List<TrendResult> changed;
  final TrendPeriod period;

  /// Πόσες γραμμές (μετρήσεις) ελέγχθηκαν μαζί ([testedRows], [chanceNote]).
  final int rows;

  /// Καμία μέτρηση δεν είχε αρκετές μέρες για σύγκριση (όλες «Λίγα δεδομένα» ή αλλαγή πηγής).
  final bool nothingCompared;

  /// Round 1 (S4-1), round 2 (R2-D-7): κάποιες γραμμές δεν συγκρίθηκαν ([notComparedText])· null όταν συγκρίθηκαν όλες.
  final String? notCompared;

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
                nothingCompared
                    ? noComparisonText(period)
                    : notCompared ??
                        // Κλινικός έλεγχος M7 (4/11): όχι «ουσιαστικά», που διαβάζεται ως «κλινικά».
                        'Καμία διαφορά δεν πέρασε τα όρια ελέγχου. Ό,τι αλλάζει είναι μέσα στις συνηθισμένες μέρα-με-μέρα '
                            'διακυμάνσεις σου. Αυτό δεν είναι ιατρικός έλεγχος.',
                style: TextStyle(color: c.textSecondary, fontSize: 14.5, height: 1.4),
              ),
            )
          else ...[
            for (var i = 0; i < changed.length; i++) ...[
              if (i > 0) const Hairline(vertical: 4),
              _ChangeRow(r: changed[i]),
            ],
            // Round 7 (R7-A5-3): πολλές μετρήσεις μαζί → κάποιο «άλλαξε» βγαίνει και από τύχη. Το λέμε, αντί να το κρύβει
            // μια διόρθωση που θα έκρυβε και πραγματικές αλλαγές ([chanceNote]).
            const SizedBox(height: 6),
            Text(chanceNote(rows),
                key: const ValueKey('trends-chance-note'), style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.4)),
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
                  changeRowText(r),
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
    final relative = relativeTemp(r);
    final value = r.current == null || few
        ? '—'
        : relative
            ? relativeTempText(r)
            : r.def.formatAs(r.current!, r.source);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Round 8 (R8-U4-9): το TalkBack λέει αν η γραμμή είναι ανοιχτή ή κλειστή (WCAG 4.1.2)· το βελάκι είναι μόνο εικόνα.
        Semantics(
          container: true,
          button: true,
          expanded: expanded,
          child: InkWell(
            key: ValueKey('trend-${r.def.key}'),
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            // Round 1 (U1b-15): το όνομα σε δική του γραμμή, σε όλο το πλάτος (πριν μοιραζόταν τη γραμμή με το «χάπι» και
            // έσπαγε σε «… στον / ύπνο»)· από κάτω η τιμή αριστερά, το «χάπι» και το βελάκι δεξιά.
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(metricLabel(r.def, r.source), style: TextStyle(fontSize: 15, color: c.textSecondary)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              value,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: r.current == null || few || value == '—' ? c.textTertiary : c.text,
                                fontFeatures: tabular,
                              ),
                            ),
                            if (relative)
                              Text(
                                'σε σχέση με πριν · όχι θερμοκρασία σώματος',
                                style: TextStyle(fontSize: 12.5, color: c.textTertiary),
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
                ],
              ),
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
    // Round 7 (R7-U4-4): μετά από αλλαγή πηγής η τιμή «τώρα» είναι μόνο από τις μέρες της νέας πηγής: το διάστημα και
    // το πλήθος από την αλλαγή («9 από 9 μέρες»), όχι «9 από 30», σαν να έλειπαν 21 νύχτες που υπάρχουν.
    final from = r.shownFrom;
    final changedSpan = !sameDay(from, r.currentFrom);
    final len = daysBetween(from, r.end) + 1;

    String count(int n) => trendCountText(n, len, sparse: def.sparse);
    // Round 2 (R2-D-9): τα δύο διαστήματα σε διαφορετικές χρονιές → οι ημερομηνίες με το έτος.
    final years = r.previousFrom.year != r.end.year;
    // Θερμοκρασία καρπού (ρολόι): ΜΟΝΟ διαφορές, ποτέ απόλυτη τιμή (τρίτος έλεγχος F2/C5). Το γράφημα δείχνει κάθε
    // νύχτα σε σχέση με τη μεσαία τιμή του «πριν» (ή του «τώρα», αν δεν υπάρχει «πριν»).
    final relative = relativeTemp(r);
    final ref = relative ? (r.previous ?? r.current) : null;
    double rel(double v) => ref == null ? v : v - ref;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (r.points.length >= 2) ...[
            LineChart(
              height: 150,
              points: [for (final p in r.points) (p.$1, rel(p.$2))],
              color: color,
              format: relative ? (v) => signedDec(v, def.digits) : _axisFormat(def),
              minRange: _minRange(def),
              // Round 2 (R2-D-9): το «1 χρόνος» (15 μήνες) με το έτος στις άκρες.
              dateLabel: spanDateLabel(r.points.first.$1, r.points.last.$1),
              // Round 1 (U1b-09, αίτημα f9 → f4): διάρκειες σε λεπτά με βήματα τέταρτα/μισάωρα/ώρες («6:00 · 7:00»), όχι
              // 1/2/5 × 10ⁿ λεπτά («3:20 · 6:40»).
              tickSteps: def.kind == ValueKind.duration ? minuteTickSteps : null,
              // Round 9 (R9-U4-2): το TalkBack με λέξεις («6 ώρες 12 λεπτά»), όχι με τη μορφή του άξονα («6:12»)· η
              // θερμοκρασία καρπού ως διαφορά με τη μονάδα της («+0,4 °C»).
              semanticLabel: trendChartLabel(r, [for (final p in r.points) (p.$1, rel(p.$2))]),
              levels: [
                if (r.previous != null) (r.previousFrom, r.previousEnd, rel(r.previous!), c.textSecondary),
                if (r.current != null && r.status != TrendStatus.sourceChange) (r.currentFrom, r.end, rel(r.current!), c.text),
              ],
            ),
            if (def.kind != ValueKind.number) ...[
              const SizedBox(height: 4),
              // R7-U4-14 δ: η ώρα ύπνου είναι ώρα της μέρας (23:00 · 00:00), όχι διάρκεια.
              Text(def.kind == ValueKind.clock ? 'Άξονας: ώρα της μέρας' : 'Άξονας: ώρες:λεπτά',
                  style: TextStyle(color: c.textTertiary, fontSize: 12.5)),
            ],
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
                    : 'Αλλαγή πηγής ${dayMonth(r.changedOn!)}: από εκείνη τη μέρα η μέτρηση έρχεται από ${r.source == Source.none ? 'καμία συσκευή' : 'το ${sourceDevice(r.source)}'}. '
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
                // Round 2 (R2-D-9): «1 χρόνος» = οι ίδιοι μήνες πέρσι· χωρίς έτος τα δύο διαστήματα έμοιαζαν ίδια.
                InfoRow(
                  '${changedSpan ? 'Από την αλλαγή' : 'Τώρα'} · ${dateSpanText(from, r.end, withYear: years)}',
                  r.current == null ? '—' : (relative ? relativeTempText(r) : def.formatAs(r.current!, r.source)),
                  dot: c.text,
                ),
                // Round 7 (R7-U4-4): με αλλαγή πηγής δεν υπάρχει «πριν» που να συγκρίνεται (το λέει το πλαίσιο πιο πάνω)·
                // πριν: «Πριν —» και «0 από 30 μέρες», ενώ οι μέρες της παλιάς πηγής υπάρχουν.
                if (r.status != TrendStatus.sourceChange)
                  InfoRow(
                    'Πριν · ${dateSpanText(r.previousFrom, r.previousEnd, withYear: years)}',
                    r.previous == null ? '—' : (relative ? 'σημείο σύγκρισης' : def.formatAs(r.previous!, r.source)),
                    dot: c.textSecondary,
                  ),
                InfoRow(r.status == TrendStatus.sourceChange ? 'Με δεδομένα' : 'Με δεδομένα (τώρα)', count(r.nCurrent)),
                if (r.status != TrendStatus.sourceChange) InfoRow('Με δεδομένα (πριν)', count(r.nPrevious)),
                if (r.source != Source.watch) InfoRow('Πηγή', sourceDevice(r.source)),
                const Hairline(vertical: 8),
                // Με αλλαγή πηγής το γράφημα δεν έχει διακεκομμένες γραμμές (καμία σύγκριση).
                if (r.status != TrendStatus.sourceChange)
                  Text('Οι διακεκομμένες γραμμές στο γράφημα είναι η μεσαία τιμή κάθε περιόδου.', style: style),
                if (relative) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Θερμοκρασία του δέρματος στον καρπό, όχι του σώματος: αλλάζει με το δωμάτιο, τα σκεπάσματα και το '
                    'λουράκι. Γι\' αυτό φαίνεται μόνο η αλλαγή σε σχέση με πριν, ποτέ οι βαθμοί.',
                    style: style,
                  ),
                ],
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

/// Το «χάπι» δεξιά: ↓ 3 bpm / Σταθερό / Λίγες μέρες για συμπέρασμα / Λίγα δεδομένα.
class TrendStatusPill extends StatelessWidget {
  const TrendStatusPill({super.key, required this.r});
  final TrendResult r;

  @override
  Widget build(BuildContext context) {
    if (r.status == TrendStatus.insufficient) return const TrendPill('Λίγα δεδομένα');
    if (r.status == TrendStatus.sourceChange) {
      if (r.rereading) return const TrendPill('Ενημερώνεται το ιστορικό');
      return TrendPill(definitionMetrics.contains(r.def.key) ? 'Αλλαγή ορισμού' : 'Αλλαγή πηγής');
    }
    // Έλεγχος 9/11 (V-B-01): «Σταθερό» μόνο όταν ο έλεγχος μπορούσε να δει αλλαγή. Με πολύ λίγες ανεξάρτητες μέρες
    // (π.χ. αραιές ζυγίσεις) λέμε ότι δεν φτάνουν, όχι ότι «δεν άλλαξε». Σε δύο γραμμές, με όριο πλάτους, ώστε να
    // χωρά δίπλα στο όνομα σε κάθε γραμμή (και με μεγάλα γράμματα).
    if (r.inconclusive) {
      return ConstrainedBox(
        key: const ValueKey('trend-inconclusive'),
        constraints: const BoxConstraints(maxWidth: 150),
        child: TrendPill(inconclusiveText(r.def), maxLines: 2),
      );
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
  if (r.inconclusive) {
    b.write(' «${inconclusiveText(def)}»: οι τιμές μοιάζουν πολύ από μέρα σε μέρα, οπότε οι ανεξάρτητες μετρήσεις δεν '
        'φτάνουν για να φανεί αλλαγή. Δεν σημαίνει ότι έμεινε ίδιο.');
  }
  if (!def.includeToday) b.write(' Η σημερινή μέρα δεν μετράει, γιατί δεν έχει τελειώσει.');
  if (def.key == K.dayHr) {
    b.write(' Μέσος όρος των παλμών όσο είσαι ξύπνιος, χωρίς τον ύπνο και τις ασκήσεις.');
  }
  return b.toString();
}

String Function(double) _axisFormat(MetricDef def) => switch (def.kind) {
      ValueKind.clock => clockFromSix,
      // Round 1 (U1b-04): άξονας διάρκειας πάντα «ώρες:λεπτά» (με λεζάντα κάτω από το γράφημα), ποτέ «12′».
      ValueKind.duration => (v) {
          final m = v.round();
          return '${m ~/ 60}:${two(m % 60)}';
        },
      ValueKind.number => (v) => dec(v, def.digits),
    };

/// Round 9 (R9-U4-2): η περιγραφή του γραφήματος μιας γραμμής για το TalkBack ([lineChartSummary]) με τα [points] όπως
/// ζωγραφίζονται: διάρκειες με λέξεις («6 ώρες 12 λεπτά», ποτέ «6:12» σαν ώρα της μέρας), θερμοκρασία καρπού ως διαφορά
/// με τη μονάδα της. null για τα υπόλοιπα (η περιγραφή με τη μορφή του άξονα, π.χ. «23:15» για την ώρα ύπνου).
String? trendChartLabel(TrendResult r, List<(DateTime, double)> points) {
  if (relativeTemp(r)) return lineChartSummary(points, (v) => '${signedDec(v, r.def.digits)} ${r.def.unit}');
  if (r.def.kind == ValueKind.duration) return lineChartSummary(points, (v) => hoursMinutes(v.round()));
  return null;
}

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

/// R7-U4-14 γ: «Με δεδομένα» με ενικό στο 1: ζυγίσεις μόνο το πλήθος («1 ζύγιση», «3 ζυγίσεις»), αλλιώς από πόσες
/// μέρες του διαστήματος [len] («9 από 9 μέρες», «1 από 1 μέρα»). Πριν «1 ζυγίσεις».
String trendCountText(int n, int len, {required bool sparse}) =>
    sparse ? countText(n, 'ζύγιση', 'ζυγίσεις') : '$n από ${countText(len, 'μέρα', 'μέρες')}';

IconData _sectionIcon(TrendSection s) => switch (s) {
      TrendSection.heart => Icons.favorite_rounded,
      TrendSection.sleep => Icons.bedtime_rounded,
      TrendSection.body => Icons.monitor_weight_rounded,
      TrendSection.move => Icons.directions_walk_rounded,
      TrendSection.other => Icons.bolt_rounded,
    };

/// Τρίτος έλεγχος F2/C5: η θερμοκρασία καρπού του ρολογιού φαίνεται στις Τάσεις μόνο ως διαφορά (η απόλυτη τιμή,
/// π.χ. 33,6 °C, διαβαζόταν ως υποθερμία). Η θερμοκρασία του Oura είναι ήδη απόκλιση και φαίνεται όπως είναι.
bool relativeTemp(TrendResult r) => r.def.key == K.skinTemp && r.source != Source.oura;

/// «+1,6 °C»: η αλλαγή «τώρα» − «πριν» από τα νούμερα όπως θα φαίνονταν· «—» όταν δεν συγκρίνεται (χωρίς «πριν»,
/// λίγα δεδομένα ή αλλαγή πηγής: τότε ένα «0 °C» δίπλα στο «Λίγα δεδομένα» θα έμοιαζε με αποτέλεσμα).
String relativeTempText(TrendResult r) => r.current == null ||
        r.previous == null ||
        r.status == TrendStatus.insufficient ||
        r.status == TrendStatus.sourceChange
    ? '—'
    : '${signedDec(shownDiff(r.current!, r.previous!, r.def.digits), r.def.digits)} ${r.def.unit}';

/// Η γραμμή κάτω από το όνομα στο «Τι άλλαξε»: «από 6 ώρες 51 λεπτά σε 7 ώρες 32 λεπτά». Round 8 (R8-U4-3): ο αριθμός
/// μένει με τη μονάδα του ([unitsGlued]) όταν η γραμμή σπάει· πριν «… σε 7 | ώρες 32 λεπτά».
String changeRowText(TrendResult r) => relativeTemp(r)
    ? '${unitsGlued(relativeTempText(r))} σε σχέση με πριν · όχι θερμοκρασία σώματος'
    : 'από ${unitsGlued(r.def.formatAs(r.previous!, r.source))} σε ${unitsGlued(r.def.formatAs(r.current!, r.source))}';

/// Round 1 (S4-1): τίποτα δεν «άλλαξε», αλλά κάποια γραμμή δεν είχε αρκετές ανεξάρτητες μετρήσεις: όχι «ό,τι αλλάζει είναι
/// μέσα στις διακυμάνσεις σου» (για εκείνες τις γραμμές δεν φάνηκε).
const someInconclusiveText = 'Καμία διαφορά δεν πέρασε τα όρια ελέγχου. Όπου γράφει «Λίγες μέρες για συμπέρασμα» ή «Λίγες '
    'ζυγίσεις για συμπέρασμα», οι μετρήσεις δεν φτάνουν για να φανεί αν άλλαξε κάτι. Αυτό δεν είναι ιατρικός έλεγχος.';

/// Round 2 (R2-D-7): η ετικέτα («χάπι», [TrendStatusPill]) μιας γραμμής που ΔΕΝ συγκρίθηκε· null όταν συγκρίθηκε.
String? notComparedLabel(TrendResult r) {
  if (r.status == TrendStatus.insufficient) return 'Λίγα δεδομένα';
  if (r.status == TrendStatus.sourceChange) {
    if (r.rereading) return 'Ενημερώνεται το ιστορικό';
    return definitionMetrics.contains(r.def.key) ? 'Αλλαγή ορισμού' : 'Αλλαγή πηγής';
  }
  if (r.inconclusive) return inconclusiveText(r.def);
  return null;
}

/// Round 2 (R2-D-7): τίποτα δεν «άλλαξε», αλλά κάποιες γραμμές ΔΕΝ συγκρίθηκαν. Τότε η σύνοψη δεν λέει «ό,τι αλλάζει είναι
/// μέσα στις συνηθισμένες διακυμάνσεις σου» (για εκείνες δεν φάνηκε· π.χ. οι μετρήσεις του Oura τον πρώτο μήνα, «Λίγα
/// δεδομένα»), αλλά ονομάζει τις ετικέτες τους όπως φαίνονται. Μόνο «Λίγες … για συμπέρασμα»: το κείμενο του γύρου 1
/// ([someInconclusiveText]). null όταν συγκρίθηκαν όλες.
String? notComparedText(List<TrendResult> results) {
  final labels = <String>[];
  for (final r in results) {
    final l = notComparedLabel(r);
    if (l != null && !labels.contains(l)) labels.add(l);
  }
  if (labels.isEmpty) return null;
  if (results.every((r) => r.inconclusive || notComparedLabel(r) == null)) return someInconclusiveText;
  final quoted = [for (final l in labels) '«$l»'];
  final list = quoted.length == 1 ? quoted.single : '${quoted.sublist(0, quoted.length - 1).join(', ')} ή ${quoted.last}';
  return 'Καμία διαφορά δεν πέρασε τα όρια ελέγχου. Όπου γράφει $list, δεν φαίνεται αν άλλαξε κάτι. '
      'Αυτό δεν είναι ιατρικός έλεγχος.';
}

/// Round 7 (R7-A5-3): η μία πρόταση κάτω από το «Τι άλλαξε» όταν λέει κάτι. Κάθε γραμμή ελέγχεται στο 1% (trends.dart),
/// αλλά με 16–20 γραμμές μαζί «άλλαξε» χωρίς καμία πραγματική αλλαγή βγαίνει σε ~1 στις 10 περιόδους (προσομοίωση με
/// την port των Τάσεων, AR(1) με σαββατοκύριακα και κενά: 10% στις 30 μέρες, 10% στους 3 μήνες, 7,5% στον χρόνο·
/// /home/claude/scratch/f7/a53/holm_sim.py). Η διόρθωση Holm (οικογενειακό 1%) θα το έριχνε στο ~1%, αλλά θα έκρυβε
/// πραγματικές αλλαγές: +3 bpm παλμοί ύπνου για 30 μέρες φαίνονται 34% → 7,5%, σε 3 μήνες 90% → 70%· HRV −15% σε 3 μήνες
/// 88% → 56%· ύπνος −30 λεπτά σε 3 μήνες 60% → 25%. Γι' αυτό έμεινε ο έλεγχος ανά γραμμή, με αυτή την προειδοποίηση.
/// Round 9 (R9-A5-1 = R9-U4-5): [rows] = οι γραμμές που ΠΡΑΓΜΑΤΙΚΑ ελέγχθηκαν ([testedRows]) και η πιθανότητα ανάλογη με
/// αυτές ([chanceOneIn]). Πριν: «Με 20 μετρήσεις μαζί … μία φορά στις 10» όταν συγκρίθηκαν μόνο τα «Βήματα».
String chanceNote(int rows) => rows <= 1
    ? 'Ο έλεγχος λέει «άλλαξε» από τύχη περίπου μία φορά στις 100· αν η αλλαγή φαίνεται και τις επόμενες εβδομάδες, '
        'είναι πιο σίγουρη.'
    : 'Με $rows μετρήσεις μαζί, περίπου μία φορά στις ${chanceOneIn(rows)} κάποια γραμμή λέει «άλλαξε» από τύχη· αν η '
        'αλλαγή φαίνεται και τις επόμενες εβδομάδες, είναι πιο σίγουρη.';

/// Round 9 (R9-A5-1 = R9-U4-5): οι γραμμές που πέρασαν από τον έλεγχο του 1% (trends.dart): «άλλαξε», «Σταθερό» και
/// «Λίγες … για συμπέρασμα» (κι αυτές ελέγχθηκαν, με μεγάλη κρίσιμη τιμή, και θα μπορούσαν να πουν «άλλαξε»). Όχι
/// «Λίγα δεδομένα», «Αλλαγή πηγής/ορισμού», «Ενημερώνεται το ιστορικό»: εκεί δεν έγινε έλεγχος, άρα ούτε «άλλαξε» από τύχη.
int testedRows(List<TrendResult> results) => results
    .where((r) => r.status == TrendStatus.up || r.status == TrendStatus.down || r.status == TrendStatus.stable)
    .length;

/// Round 9 (R9-A5-1): «περίπου μία φορά στις N» για [tested] γραμμές μαζί, όταν τίποτα δεν άλλαξε πραγματικά: 1 − (1 − p)^k,
/// με p ανά γραμμή ανάμεσα στο ~0,55% της προσομοίωσης (19 γραμμές → 10%, holm_sim.py του R7-A5-3) και στο 1% του ελέγχου.
/// 1 γραμμή: 0,5–1% → 100· 2–3: 1,1–3% → 50· 4–9: 2,2–8,6% → 20· 10 και πάνω: 5,4–18% (προσομοίωση 16–20: ~10%) → 10.
int chanceOneIn(int tested) => tested <= 1
    ? 100
    : tested <= 3
        ? 50
        : tested <= 9
            ? 20
            : 10;

/// UX U2: κανένας δείκτης δεν είχε αρκετές μετρήσεις και στις δύο περιόδους.
String noComparisonText(TrendPeriod p) => switch (p) {
      TrendPeriod.month => 'Δεν υπάρχουν αρκετές μετρήσεις από τις προηγούμενες 30 μέρες για σύγκριση.',
      TrendPeriod.quarter => 'Δεν υπάρχουν αρκετές μετρήσεις από τους προηγούμενους 3 μήνες για σύγκριση.',
      TrendPeriod.year => 'Δεν υπάρχουν αρκετές μετρήσεις από πέρσι για σύγκριση.',
    };
