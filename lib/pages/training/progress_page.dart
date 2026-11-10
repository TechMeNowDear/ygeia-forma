import 'package:flutter/material.dart';

import '../../data.dart';
import '../../format.dart';
import '../../history.dart' show K;
import '../../theme.dart';
import '../../training/equipment.dart';
import '../../training/progress.dart';
import '../../training/session.dart';
import '../../training/training_store.dart';
import '../../trends.dart';
import '../../widgets.dart';
import '../trends.dart' show TrendStatusPill;
import 'training_common.dart';

/// «Πρόοδος» (9/11): περπάτημα, δύναμη, και ό,τι δείχνουν ήδη οι «Τάσεις» για σώμα και ξεκούραση.
/// Λέει «άλλαξε» μόνο όταν η αλλαγή είναι πραγματική (κανόνες στο training/progress.dart). Δείχνει και τις πτώσεις.
class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key, required this.training, this.health, this.onOpenTrends, this.now});
  final TrainingStore training;
  final HealthStore? health;
  final VoidCallback? onOpenTrends;

  /// Μόνο για δοκιμές και στιγμιότυπα.
  final DateTime? now;

  static Route<void> route(TrainingStore t, {HealthStore? health, VoidCallback? onOpenTrends, DateTime? now}) => MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'Πρόοδος'),
      builder: (_) => ProgressPage(training: t, health: health, onOpenTrends: onOpenTrends, now: now));

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  // 3 μήνες από προεπιλογή (έλεγχος 9/11, V-B-10 / 03-M1): η βελτίωση με την προπόνηση είναι σταδιακή, και δύο
  // διαδοχικοί μήνες τη δείχνουν σπάνια (3–14%)· στο τρίμηνο 28–72%.
  TrendPeriod _period = TrendPeriod.quarter;

  @override
  Widget build(BuildContext context) {
    final t = widget.training;
    final health = widget.health;
    return ListenableBuilder(
      listenable: Listenable.merge([t, if (health != null) health]),
      builder: (context, _) {
        final today = widget.now ?? t.now;
        final walk = walkProgress(t.sessions, today, _period);
        final strength = strengthProgress(t.sessions, today, _period);
        final body = health == null
            ? const <TrendResult>[]
            : [
                for (final k in [K.sleepHr, K.smm, K.fatPct])
                  if (metricDef(k) case final d?) computeTrend(d, health.history, today, _period, plan: health.analysisPlan),
              ];
        final c = Aigaio.of(context);
        final period = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            PeriodPicker<TrendPeriod>(
              values: const [TrendPeriod.month, TrendPeriod.quarter],
              days: periodDays,
              selected: _period,
              onChanged: (p) => setState(() => _period = p),
              color: c.exercise,
              keyOf: (p) => p == TrendPeriod.month ? 'prog-month' : 'prog-quarter',
            ),
            const SizedBox(height: 8),
            Text(_period == TrendPeriod.month ? 'Τελευταίες 30 μέρες σε σχέση με τις 30 πριν.' : 'Τελευταίοι 3 μήνες σε σχέση με τους 3 πριν.',
                style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
          ]),
        );
        final summary = _SummaryCard(walk: walk, strength: strength, body: body);
        final w = progressWindows(today, _period);
        // RT-12: περπατήματα χωρίς GPS δεν μετράνε· λέγεται, ώστε να μη μοιάζει «χαλασμένη» η Πρόοδος.
        final noGps = t.sessions.where((s) => s.isCardio && s.finished && s.gps == false && !dayOf(s.start).isBefore(w.prevFrom)).length;
        final walkCard = _WalkCard(walk: walk, period: _period, points: walkHrPoints(t.sessions, w.prevFrom, w.end), window: w, noGps: noGps);
        final strengthCard = _StrengthCard(items: strength);
        final bodyCard = health == null ? null : _BodyCard(results: body, onOpenTrends: widget.onOpenTrends);
        final note = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text('«Άλλαξε» μόνο όταν η διαφορά είναι μεγαλύτερη από τις συνηθισμένες διακυμάνσεις σου· αλλιώς «Σταθερό», '
              'ή «Λίγες μέρες (ή ζυγίσεις) για συμπέρασμα» όταν δεν φτάνουν για σύγκριση. Είναι ένδειξη, όχι ιατρικός έλεγχος.',
              style: TextStyle(fontSize: 12.5, height: 1.45, color: c.textSecondary)),
        );
        return Scaffold(
          appBar: AppBar(title: const Text('Πρόοδος', style: TextStyle(fontWeight: FontWeight.w800))),
          body: SafeArea(
            child: LayoutBuilder(builder: (context, k) {
              if (k.maxWidth >= 720) {
                Widget col(List<Widget> w) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (var i = 0; i < w.length; i++) ...[if (i > 0) const SizedBox(height: 12), w[i]],
                    ]);
                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1080),
                    child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
                      period,
                      const SizedBox(height: 12),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: col([summary, walkCard])),
                        const SizedBox(width: 16),
                        Expanded(child: col([strengthCard, if (bodyCard != null) bodyCard, note])),
                      ]),
                    ]),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                children: [
                  for (final w in [period, summary, walkCard, strengthCard, if (bodyCard != null) bodyCard, note]) ...[w, const SizedBox(height: 12)],
                ],
              );
            }),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- κείμενα

/// Πτώση παλμών: πόσοι παλμοί (αρνητικό = ανέβηκαν, σπάνιο).
String _hrDrop(double v) => '${v.round()}';

/// Πτώση παλμών στο 1′ που άλλαξε: ουδέτερα, χωρίς βέλος (έλεγχος 9/11, V-B-08).
String hrrChangeText(TrendResult r) {
  final d = (r.current! - r.previous!).round();
  return d > 0 ? 'μεγαλύτερη κατά $d' : 'μικρότερη κατά ${-d}';
}

/// «παλμοί στο τέλος 112 → 118»: η ένταση των ίδιων περπατημάτων, για να διαβάζεται η πτώση.
String? hrrEndText(TrendResult end) {
  final a = end.previous, b = end.current;
  if (b == null) return null;
  return a == null ? 'παλμοί στο τέλος ${b.round()}' : 'παλμοί στο τέλος ${a.round()} → ${b.round()}';
}

String _paceRelText(PaceRel r) => switch (r) {
      PaceRel.same => 'ίδιος ρυθμός',
      PaceRel.faster => 'πιο γρήγορο βάδισμα',
      PaceRel.slower => 'πιο αργό βάδισμα',
      PaceRel.unknown => '',
    };

String _repsText(List<int> reps) => reps.join(', ');

/// «27″» κάτω από το λεπτό, αλλιώς «1′05″».
String _secs(int s) => s < 60 ? '$s″' : clock(s);

String _setText(LoadKind k, ExLog e) =>
    hasLoad(k) ? '${loadLabel(k, e.workLoad)} × ${_repsText([for (final s in e.done) s.reps])}' : '${_repsText([for (final s in e.done) s.reps])} επαν.';

String _loadDelta(LoadKind k, double d) => switch (k) {
      LoadKind.band || LoadKind.bandPair => '${d.abs().round()} lb',
      _ => '${kgText(d.abs())} kg',
    };

/// Το «χάπι» μιας άσκησης: κείμενο, είδος, βελάκι.
(String, TrendKind, bool?) strengthPill(ExProgress p) {
  final l = p.loadDiff, r = p.repsDiff;
  final assist = p.kind == LoadKind.bandAssist;
  switch (p.change) {
    case StrengthChange.up:
      if (l > 0) return assist ? ('λιγότερη βοήθεια', TrendKind.good, null) : (_loadDelta(p.kind, l), TrendKind.good, true);
      return ('$r επαν.', TrendKind.good, true);
    case StrengthChange.down:
      if (l < 0) return assist ? ('περισσότερη βοήθεια', TrendKind.bad, null) : (_loadDelta(p.kind, l), TrendKind.bad, false);
      return ('${-r} επαν.', TrendKind.bad, false);
    case StrengthChange.mixed:
      if (assist) return (l > 0 ? 'λιγότερη βοήθεια, λιγότερες επαν.' : 'περισσότερη βοήθεια, περισσότερες επαν.', TrendKind.neutral, null);
      return (l > 0 ? 'βάρος ↑, επαν. ↓' : 'βάρος ↓, επαν. ↑', TrendKind.neutral, null);
    case StrengthChange.same:
      return ('Ίδιο', TrendKind.neutral, null);
  }
}

// ---------------------------------------------------------------- κάρτες

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.detail, required this.pill, this.extra, this.line = true, super.key});
  final String label;
  final String detail;
  final String? extra;
  final Widget pill;
  final bool line;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    // Όνομα και «χάπι» στην πρώτη γραμμή, τα νούμερα από κάτω σε όλο το πλάτος (δεν σπάνε σε στενό κινητό).
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: line ? BoxDecoration(border: Border(bottom: BorderSide(color: c.hairline))) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: c.text))),
          const SizedBox(width: 8),
          Flexible(child: Align(alignment: Alignment.topRight, child: pill)),
        ]),
        const SizedBox(height: 3),
        Text(detail, style: TextStyle(fontSize: 14, height: 1.4, color: c.text, fontFeatures: const [FontFeature.tabularFigures()])),
        if (extra != null && extra!.isNotEmpty) Text(extra!, style: TextStyle(fontSize: 13, color: c.textSecondary)),
      ]),
    );
  }
}

Widget _title(BuildContext context, String t, {VoidCallback? info, Key? infoKey}) {
  final c = Aigaio.of(context);
  return Row(children: [
    Expanded(child: Text(t, style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: c.text))),
    if (info != null)
      IconButton(key: infoKey, tooltip: 'Πώς το βρίσκω', onPressed: info, icon: Icon(Icons.info_outline_rounded, color: c.textSecondary)),
  ]);
}

Widget _foot(BuildContext context, String t) =>
    Padding(padding: const EdgeInsets.only(top: 8), child: Text(t, style: TextStyle(fontSize: 12.5, height: 1.4, color: Aigaio.of(context).textSecondary)));

class _WalkCard extends StatelessWidget {
  const _WalkCard({required this.walk, required this.period, this.points = const [], this.window, this.noGps = 0});
  final WalkProgress walk;

  /// Περπατήματα των δύο περιόδων χωρίς GPS (δεν μετράνε).
  final int noGps;
  String get _noGpsText => noGps == 0
      ? ''
      : ' ${noGps == 1 ? '1 περπάτημα' : '$noGps περπατήματα'} χωρίς GPS δεν ${noGps == 1 ? 'μετράει' : 'μετράνε'}: '
          'στο ρολόι άνοιξε την τοποθεσία πριν από το «Ξεκίνα».';
  final TrendPeriod period;

  /// Μία τιμή ανά περπάτημα (παλμοί σταθερού βαδίσματος), και στις δύο περιόδους.
  final List<(DateTime, double)> points;
  final ({DateTime from, DateTime end, DateTime prevFrom, DateTime prevEnd})? window;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final w = walk;
    final info = _title(context, 'Περπάτημα', info: () => showWalkProgressInfo(context), infoKey: const ValueKey('prog-walk-info'));
    if (w.insufficient) {
      final now = w.hr.nCurrent, before = w.hr.nPrevious;
      return AppCard(
        key: const ValueKey('prog-walk'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          info,
          Text.rich(
            TextSpan(style: TextStyle(fontSize: 15, height: 1.45, color: c.text), children: [
              const TextSpan(text: 'Για σύγκριση χρειάζονται περπατήματα σε τουλάχιστον '),
              const TextSpan(text: '$walkNeeded διαφορετικές μέρες', style: TextStyle(fontWeight: FontWeight.w700)),
              const TextSpan(text: ' σε κάθε περίοδο. Ως τώρα: '),
              TextSpan(text: '$now', style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: period == TrendPeriod.month ? ' τις τελευταίες 30 μέρες, ' : ' τους τελευταίους 3 μήνες, '),
              TextSpan(text: '$before', style: const TextStyle(fontWeight: FontWeight.w700)),
              const TextSpan(text: ' πριν.'),
            ]),
            key: const ValueKey('prog-walk-few'),
          ),
          // Ίδια λογική με τον έλεγχο 03 (μήνας: 30 μέρες + ~9 για 4 μέρες στην προηγούμενη περίοδο → 5–6 εβδομάδες).
          _foot(context, '${period == TrendPeriod.month ? 'Με 3 περπατήματα την εβδομάδα, η πρώτη σύγκριση του μήνα βγαίνει περίπου 5–6 εβδομάδες μετά το πρώτο. ' : 'Με 3 περπατήματα την εβδομάδα, η πρώτη σύγκριση των 3 μηνών βγαίνει περίπου 14 εβδομάδες μετά το πρώτο· στον «Μήνα» 5–6 εβδομάδες. '}'
              'Μετράνε μόνο περπατήματα από το ρολόι, πάνω από 15′ και με GPS.$_noGpsText'),
        ]),
      );
    }
    Widget pillFor(TrendResult r, {int? goodness, String Function(double)? fmt}) {
      if (!r.changed) return TrendStatusPill(r: r);
      final d = r.current! - r.previous!;
      final g = goodness ?? r.goodness;
      final kind = g > 0 ? TrendKind.good : (g < 0 ? TrendKind.bad : TrendKind.neutral);
      return TrendPill(fmt != null ? fmt(d) : '${d.abs().round()} ${r.def.unit}'.trim(), kind: kind, up: d > 0);
    }

    String vals(TrendResult r, String Function(double) f) =>
        r.previous == null || r.current == null ? (r.current == null ? '—' : 'τώρα ${f(r.current!)}') : '${f(r.previous!)} → ${f(r.current!)}';

    // V-B-11: με άλλο ρυθμό οι παλμοί δεν συγκρίνονται (ουδέτερο)· η πύλη ρυθμού μένει (όχι ANCOVA).
    final hrExtra = w.hr.changed && w.hrGoodness == 0
        ? '${_paceRelText(w.paceRel)}: άλλος ρυθμός, δεν συγκρίνεται'
        : _paceRelText(w.paceRel);
    final win = window;
    final hours = w.secNow / 3600;
    return AppCard(
      key: const ValueKey('prog-walk'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        info,
        _Row(
          key: const ValueKey('prog-walk-hr'),
          label: 'Παλμοί στο περπάτημα',
          detail: vals(w.hr, (v) => '${v.round()}') + (w.hr.current == null ? '' : ' bpm'),
          extra: hrExtra.isEmpty ? 'από το 5ο λεπτό ως το «Τέλος»' : 'από το 5ο λεπτό · $hrExtra',
          pill: pillFor(w.hr, goodness: w.hrGoodness),
        ),
        // Μία τιμή ανά περπάτημα (V-B-10): φαίνεται η πορεία, όχι μόνο δύο μεσαίες τιμές.
        if (points.length >= 2 && win != null)
          Padding(
            key: const ValueKey('prog-walk-chart'),
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: LineChart(
              points: points,
              height: 120,
              minRange: 10,
              from: win.prevFrom,
              to: win.end,
              color: c.heart,
              format: (v) => '${v.round()}',
              levels: [
                if (w.hr.previous != null) (win.prevFrom, win.prevEnd, w.hr.previous!, c.textTertiary),
                if (w.hr.current != null) (win.from, win.end, w.hr.current!, c.heart),
              ],
            ),
          ),
        _Row(
          key: const ValueKey('prog-walk-pace'),
          label: 'Ρυθμός',
          // «11:30 → 11:15 /km»: η μονάδα μία φορά, στο τέλος (N2).
          detail: w.pace.previous != null && w.pace.current != null ? '${clock(w.pace.previous!)} → ${paceText(w.pace.current!)}' : vals(w.pace, (v) => paceText(v)),
          pill: w.pace.changed
              ? TrendPill(
                  '${w.pace.status == TrendStatus.down ? 'πιο γρήγορα' : 'πιο αργά'} ${_secs((w.pace.current! - w.pace.previous!).abs().round())}',
                  kind: w.pace.status == TrendStatus.down ? TrendKind.good : TrendKind.neutral)
              : TrendStatusPill(r: w.pace),
        ),
        // Ουδέτερη (έλεγχος 9/11, V-B-08): χωρίς χρώμα και βέλος, με τους παλμούς στο τέλος από κάτω.
        _Row(
          key: const ValueKey('prog-walk-hrr'),
          label: 'Πτώση παλμών στο 1′',
          detail: vals(w.hrr, _hrDrop) + (w.hrr.current == null ? '' : ' παλμοί'),
          extra: w.hrr.current == null ? null : hrrEndText(w.hrrEnd),
          pill: w.hrr.changed ? TrendPill(hrrChangeText(w.hrr)) : TrendStatusPill(r: w.hrr),
        ),
        _Row(
          key: const ValueKey('prog-walk-count'),
          label: 'Περπατήματα',
          detail: '${w.countBefore} → ${w.countNow} · ${dec(hours, 1)} ώρες',
          pill: TrendPill(w.countNow == w.countBefore ? 'Ίδιο' : '${w.countNow > w.countBefore ? '+' : '−'}${(w.countNow - w.countBefore).abs()}'),
          line: false,
        ),
        _foot(context, 'Μόνο περπατήματα από το ρολόι, πάνω από 15′ και με GPS. ${w.countNow} τώρα, ${w.countBefore} πριν.$_noGpsText'),
      ]),
    );
  }
}

class _StrengthCard extends StatelessWidget {
  const _StrengthCard({required this.items});
  final List<ExProgress> items;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return AppCard(
      key: const ValueKey('prog-strength'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title(context, 'Δύναμη', info: () => showStrengthProgressInfo(context), infoKey: const ValueKey('prog-strength-info')),
        if (items.isEmpty)
          Text('Κάθε άσκηση εμφανίζεται εδώ όταν γίνει τουλάχιστον 2 φορές.', style: TextStyle(fontSize: 15, height: 1.45, color: c.text))
        else
          for (var i = 0; i < items.length; i++)
            Builder(builder: (context) {
              final p = items[i];
              final (text, kind, up) = strengthPill(p);
              return _Row(
                key: ValueKey('prog-ex-${p.ex}'),
                label: exName(p.ex),
                detail: '${shortDayDate(p.beforeDay)}: ${_setText(p.kind, p.before)}\n${shortDayDate(p.nowDay)}: ${_setText(p.kind, p.now)}',
                pill: TrendPill(text, kind: kind, up: up, maxLines: 2),
                line: i < items.length - 1,
              );
            }),
        _foot(context, 'Η τελευταία φορά πριν από την περίοδο → η πιο πρόσφατη. Ασκήσεις που ξεκίνησαν μέσα στην περίοδο: '
            'η πρώτη φορά → η πιο πρόσφατη. Οι επαναλήψεις συγκρίνονται στα ίδια σετ (1ο με 1ο…).'),
      ]),
    );
  }
}

class _BodyCard extends StatelessWidget {
  const _BodyCard({required this.results, this.onOpenTrends});
  final List<TrendResult> results;
  final VoidCallback? onOpenTrends;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: const ValueKey('prog-body'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title(context, 'Σώμα και ξεκούραση'),
        for (var i = 0; i < results.length; i++)
          _Row(
            label: metricLabel(results[i].def, results[i].source),
            detail: results[i].previous == null || results[i].current == null
                ? (results[i].current == null ? '—' : 'τώρα ${results[i].def.formatAs(results[i].current!, results[i].source)}')
                : '${results[i].def.formatAs(results[i].previous!, results[i].source)} → ${results[i].def.formatAs(results[i].current!, results[i].source)}',
            pill: TrendStatusPill(r: results[i]),
            line: i < results.length - 1,
          ),
        if (onOpenTrends != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('prog-trends'),
              onPressed: () {
                Navigator.of(context).pop();
                onOpenTrends!();
              },
              child: const Text('Όλες οι τάσεις ›'),
            ),
          ),
        _foot(context, 'Από τις «Τάσεις»: ίδιοι αριθμοί και ίδιος έλεγχος.'),
      ]),
    );
  }
}

/// Οι ξεκάθαρες αλλαγές, η πιο σημαντική πρώτη. Για τη σελίδα και για την κάρτα στην «Προπόνηση».
List<(String, TrendKind, bool?)> progressHighlights(WalkProgress walk, List<ExProgress> strength, List<TrendResult> body) {
  final out = <(String, TrendKind, bool?)>[];
  TrendKind k(int g) => g > 0 ? TrendKind.good : (g < 0 ? TrendKind.bad : TrendKind.neutral);
  if (walk.hr.changed) {
    final d = (walk.hr.current! - walk.hr.previous!).round();
    out.add(('Παλμοί στο περπάτημα: ${d < 0 ? 'έπεσαν' : 'ανέβηκαν'} ${d.abs()} (${_paceRelText(walk.paceRel)})', k(walk.hrGoodness), d > 0));
  }
  if (walk.pace.changed) {
    final faster = walk.pace.status == TrendStatus.down;
    out.add(('Ρυθμός: ${clock(walk.pace.previous!)} → ${paceText(walk.pace.current!)}', faster ? TrendKind.good : TrendKind.neutral, !faster));
  }
  // Ουδέτερη, χωρίς βέλος (έλεγχος 9/11, V-B-08), με την ένταση δίπλα.
  if (walk.hrr.changed) {
    final end = hrrEndText(walk.hrrEnd);
    out.add(('Πτώση παλμών στο 1′: ${walk.hrr.previous!.round()} → ${walk.hrr.current!.round()}${end == null ? '' : ' ($end)'}', TrendKind.neutral, null));
  }
  for (final p in strength) {
    if (p.change != StrengthChange.up && p.change != StrengthChange.down) continue;
    final (_, kind, up) = strengthPill(p);
    final r = p.repsDiff;
    final String what;
    if (p.loadDiff.abs() > 1e-6) {
      what = p.kind == LoadKind.bandAssist
          ? (p.loadDiff > 0 ? 'λιγότερη βοήθεια' : 'περισσότερη βοήθεια')
          : '${loadLabel(p.kind, p.before.workLoad)} → ${loadLabel(p.kind, p.now.workLoad)}';
    } else {
      what = '${r > 0 ? '+' : '−'}${r.abs()} επαναλήψεις${hasLoad(p.kind) ? ' με το ίδιο βάρος' : ''}';
    }
    out.add(('${exName(p.ex)}: $what', kind, up));
  }
  for (final r in body) {
    if (!r.changed) continue;
    out.add(('${metricLabel(r.def, r.source)}: ${r.def.formatAs(r.previous!, r.source)} → ${r.def.formatAs(r.current!, r.source)}', k(r.goodness), r.status == TrendStatus.up));
  }
  return out;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.walk, required this.strength, required this.body});
  final WalkProgress walk;
  final List<ExProgress> strength;
  final List<TrendResult> body;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final items = progressHighlights(walk, strength, body);
    return AppCard(
      key: const ValueKey('prog-summary'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title(context, 'Τι άλλαξε'),
        const SizedBox(height: 4),
        if (items.isEmpty)
          Text('Καμία ξεκάθαρη αλλαγή ακόμα.', style: TextStyle(fontSize: 15, color: c.text))
        else
          for (final (text, kind, up) in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(
                  up == null ? Icons.remove_rounded : (up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
                  size: 18,
                  color: switch (kind) { TrendKind.good => c.good, TrendKind.bad => c.bad, TrendKind.neutral => c.textSecondary },
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(text, style: TextStyle(fontSize: 15, height: 1.4, color: c.text))),
              ]),
            ),
        _foot(context, 'Ό,τι δεν γράφεται εδώ έμεινε σταθερό ή δεν έχει αρκετά δεδομένα.'),
      ]),
    );
  }
}

// ---------------------------------------------------------------- οδηγίες (ⓘ)

Future<void> _sheet(BuildContext context, String key, String title, List<(String, String)> parts) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final c = Aigaio.of(ctx);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .85),
            child: SingleChildScrollView(
              key: ValueKey(key),
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.text)),
                for (final (h, p) in parts) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 14, bottom: 4),
                    child: Text(h, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: c.text)),
                  ),
                  Text(p, style: TextStyle(fontSize: 14.5, height: 1.45, color: c.text)),
                ],
              ]),
            ),
          ),
        );
      },
    );

Future<void> showWalkProgressInfo(BuildContext context) => _sheet(context, 'prog-walk-sheet', 'Πρόοδος στο περπάτημα', const [
      (
        'Τι δείχνει',
        'Παλμοί: ο μέσος όρος σε κάθε περπάτημα από το 5ο λεπτό ως το «Τέλος», χωρίς τις παύσεις (τα πρώτα λεπτά οι παλμοί '
            'ακόμα ανεβαίνουν, και θα έκαναν τα σύντομα περπατήματα να μοιάζουν αλλιώς). Το γράφημα έχει μία τελεία για κάθε '
            'περπάτημα. Όσο βελτιώνεται η φυσική κατάσταση, η ίδια ταχύτητα θέλει '
            'λιγότερους παλμούς. Ρυθμός: λεπτά ανά χιλιόμετρο, χωρίς τις παύσεις. Πτώση παλμών στο 1′: πόσο πέφτουν οι παλμοί '
            'στο πρώτο λεπτό μετά το «Τέλος». Εξαρτάται κυρίως από το πόσο γρήγορα περπάτησες (πιο γρήγορα = μεγαλύτερη πτώση), '
            'γι\' αυτό δεν τη λέω «καλύτερα» ή «χειρότερα»· από κάτω φαίνονται οι παλμοί στο τέλος, για να συγκρίνεις ίδια ένταση.'
      ),
      (
        'Πώς αποφασίζω',
        'Παίρνω μία τιμή για κάθε μέρα με περπάτημα και συγκρίνω τη μεσαία τιμή κάθε περιόδου. Λέω «άλλαξε» μόνο αν η διαφορά '
            'είναι τουλάχιστον 3 παλμοί (στον ρυθμό 15″ ανά km) και ξεκάθαρα μεγαλύτερη από τη διαφορά που έχουν συνήθως τα '
            'περπατήματά σου μεταξύ τους. Είναι ο ίδιος έλεγχος με τις «Τάσεις». Χρειάζονται τουλάχιστον 4 μέρες με περπάτημα σε κάθε περίοδο.'
      ),
      (
        'Παλμοί και ταχύτητα μαζί',
        'Αν περπατάς πιο αργά, οι παλμοί πέφτουν από μόνοι τους. Γι\' αυτό οι λιγότεροι παλμοί μετράνε ως βελτίωση μόνο αν ο ρυθμός '
            'έμεινε ίδιος (έως 2% διαφορά) ή έγινε πιο γρήγορος. Το ίδιο και ανάποδα: περισσότεροι παλμοί με πιο γρήγορο βάδισμα δεν είναι χειροτέρευση.'
      ),
      (
        'Τι το επηρεάζει',
        'Η ζέστη και οι ανηφόρες ανεβάζουν τους παλμούς στον ίδιο ρυθμό: καλοκαίρι με φθινόπωρο δεν συγκρίνονται καθαρά. '
            'Το ίδιο κούραση, λίγος ύπνος, καφές, αφυδάτωση και φάρμακα που αλλάζουν τους παλμούς. Για πιο καθαρή σύγκριση, '
            'περπάτα όσο γίνεται στην ίδια διαδρομή. Είναι ένδειξη, όχι ιατρικός έλεγχος.'
      ),
      ('Ποια περπατήματα μετράνε', 'Μόνο από το ρολόι, με GPS, με τουλάχιστον 15 λεπτά ενεργό χρόνο και 500 μέτρα.'),
    ]);

Future<void> showStrengthProgressInfo(BuildContext context) => _sheet(context, 'prog-strength-sheet', 'Πρόοδος στη δύναμη', const [
      (
        'Τι δείχνει',
        'Γεγονότα: τα κιλά και τις επαναλήψεις που έκανες την τελευταία φορά πριν από την περίοδο και την πιο πρόσφατη φορά. '
            'Δεν υπολογίζω «μέγιστο» (1RM): οι τύποι που το βγάζουν από σετ 8–15 επαναλήψεων έχουν μεγάλο λάθος, και όσο περισσότερες '
            'οι επαναλήψεις τόσο μεγαλύτερο (LeSuer 1997· Reynolds 2006).'
      ),
      (
        'Πώς διαβάζεται',
        'Περισσότερο βάρος με τις επαναλήψεις ακόμα μέσα στο εύρος του στόχου (π.χ. όλα τα σετ τουλάχιστον 8), ή ίδιο βάρος '
            'με περισσότερες επαναλήψεις: πρόοδος. Περισσότερο βάρος με κάποιο σετ κάτω από το εύρος: δεν λέω ούτε καλύτερα '
            'ούτε χειρότερα. Μία επανάληψη πάνω ή κάτω στο σύνολο των σετ μετρά ως «ίδιο»: '
            'τόσο αλλάζει από μέρα σε μέρα. Στις έλξεις με λάστιχο, λιγότερη βοήθεια σημαίνει πρόοδο.'
      ),
      (
        'Τι το επηρεάζει',
        'Ύπνος, κούραση, πόνος, η σειρά των ασκήσεων και το διάλειμμα. Μία κακή μέρα δεν σημαίνει πισωγύρισμα.'
      ),
    ]);
