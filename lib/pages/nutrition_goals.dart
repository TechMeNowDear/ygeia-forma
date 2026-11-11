import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data.dart';
import '../food/chol.dart';
import '../food/food_model.dart';
import '../food/food_store.dart';
import '../format.dart';
import '../goals.dart';
import '../reference.dart' show MetricInfo;
import '../theme.dart';
import '../widgets.dart';
import 'goals_page.dart';
import 'info_sheet.dart';
import 'nutrition.dart' show proteinColor;

/// Η Διατροφή με στόχους (σχέδια 12/11, 3α–3γ). Οι αριθμοί έρχονται μόνο από τη βάση τροφίμων και τους τύπους του
/// goals.dart· τίποτα από AI.

/// «Μένουν 1.009 kcal» / «150 kcal πάνω από τον στόχο». [today]: για άλλες μέρες λέει «κάτω/πάνω από τον στόχο».
({String label, String value, bool over}) kcalLeft(int eaten, int goal, {required bool today}) {
  final diff = goal - eaten;
  if (diff >= 0) return (label: today ? 'Μένουν' : 'Κάτω από τον στόχο', value: thousands(diff), over: false);
  return (label: 'Πάνω από τον στόχο', value: thousands(-diff), over: true);
}

/// Σύνολο ημέρας με τους στόχους (αντικαθιστά τη «Σύνολο ημέρας» όταν υπάρχουν στόχοι).
class GoalsSummaryCard extends StatelessWidget {
  const GoalsSummaryCard({super.key, required this.totals, required this.goals, required this.today, required this.health});
  final Totals totals;
  final Goals goals;
  final bool today;
  final HealthStore health;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final t = totals, g = goals;
    final left = kcalLeft(t.shownKcal, g.kcal, today: today);
    String atLeast(String key, String text) => (t.missing[key] ?? 0) > 0 ? '≥ $text' : text;
    final protLeft = g.protein - t.protein;
    final fiberLeft = g.fiber - t.fiber;
    final satOver = t.satFat - g.satMax;
    return AppCard(
      key: const ValueKey('nutrition-goals'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(left.label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: left.over ? c.warn : c.textSecondary)),
              BigValue(left.value, unit: 'kcal', size: 44, color: left.over ? c.warn : null),
            ]),
          ),
          // Με μεγάλα γράμματα: το «έφαγες / στόχος» σπάει σε γραμμές, δεν βγαίνει έξω από την κάρτα.
          Flexible(
            child: InkWell(
            key: const ValueKey('nutrition-goals-open'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => openGoals(context, health),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('έφαγες ${thousands(t.shownKcal)}', textAlign: TextAlign.right, style: TextStyle(fontSize: 13.5, color: c.textSecondary, fontFeatures: tabular)),
                Text('στόχος ${thousands(g.kcal)}',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.food, fontFeatures: tabular)),
              ]),
            ),
          ),
          ),
        ]),
        const SizedBox(height: 10),
        GoalBar(
          label: 'Πρωτεΐνη',
          value: '${gramsText(t.protein)} g',
          target: '${g.protein} g',
          fraction: t.protein / g.protein,
          color: proteinColor(c),
          note: t.count == 0
              ? null
              : protLeft <= 0.5
                  ? 'Έπιασες τον στόχο ✓'
                  : (today ? 'Μένουν ${gramsText(protLeft)} g' : null),
        ),
        GoalBar(
          label: 'Κορεσμένα',
          value: atLeast(Nk.satFat, '${gramsText(t.satFat)} g'),
          target: 'έως ${g.satMax} g',
          fraction: t.satFat / g.satMax,
          color: satOver > 0.05 ? c.warn : c.heart,
          note: satOver > 0.05 ? '${gramsText(satOver)} g πάνω από το όριο' : null,
          warn: satOver > 0.05,
        ),
        GoalBar(
          label: 'Φυτικές ίνες',
          value: atLeast(Nk.fiber, '${gramsText(t.fiber)} g'),
          target: '${g.fiber} g',
          fraction: t.fiber / g.fiber,
          color: c.good,
          note: fiberLeft <= 0.05 && t.count > 0 ? 'Έπιασες τον στόχο ✓' : null,
        ),
        const Hairline(vertical: 12),
        InfoRow('Λίπος', '${gramsText(t.fat)} g / ${g.fatLo}–${g.fatHi}'),
        InfoRow('Αλάτι', '${atLeast(Nk.salt, dec(t.salt, 1))} g / < ${dec(g.salt, 0)}',
            valueColor: t.salt >= g.salt ? c.warn : null),
        InfoRow('Υδατάνθρακες', '${gramsText(t.carbs)} g'),
        InfoRow('Σάκχαρα', '${atLeast(Nk.sugars, gramsText(t.sugars))} g'),
        if (t.alcohol >= 0.05) InfoRow('Αλκοόλ', '${gramsText(t.alcohol)} g'),
        if (t.missing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('«≥»: κάποια τρόφιμα δεν έχουν τιμή στην πηγή τους.', style: TextStyle(fontSize: 12.5, color: c.textTertiary)),
          ),
      ]),
    );
  }
}

/// Μπάρα «τιμή / στόχος» με σημείωση από κάτω.
class GoalBar extends StatelessWidget {
  const GoalBar({
    super.key,
    required this.label,
    required this.value,
    required this.target,
    required this.fraction,
    required this.color,
    this.note,
    this.warn = false,
  });
  final String label, value, target;
  final double fraction;
  final Color color;
  final String? note;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final f = fraction.isFinite ? fraction.clamp(0.0, 1.0) : 0.0;
    return Semantics(
      label: '$label: $value από $target${note == null ? '' : '. $note'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(alignment: WrapAlignment.spaceBetween, spacing: 8, children: [
            Text(label, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: c.text)),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: value, style: TextStyle(fontWeight: FontWeight.w700, color: warn ? c.warn : c.text)),
                TextSpan(text: ' / $target', style: TextStyle(color: c.textSecondary)),
              ]),
              style: const TextStyle(fontSize: 14.5, fontFeatures: tabular),
            ),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 8,
              child: Stack(fit: StackFit.expand, children: [
                ColoredBox(color: c.hairline),
                FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: f, child: ColoredBox(color: color)),
              ]),
            ),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(note!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: warn ? c.warn : c.textSecondary)),
            ),
        ]),
      ),
    );
  }
}

/// Χωρίς στόχους: πρόσκληση στον οδηγό.
class GoalsCtaCard extends StatelessWidget {
  const GoalsCtaCard({super.key, required this.health});
  final HealthStore health;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return EmptyCard(
      key: const ValueKey('nutrition-goals-cta'),
      icon: Icons.flag_rounded,
      color: c.food,
      title: 'Βάλε στόχους διατροφής',
      text: 'Θερμίδες, πρωτεΐνη, κορεσμένα και ίνες για σένα, σε 2 λεπτά.',
      buttonText: 'Ο οδηγός',
      onPressed: () => openGoals(context, health),
    );
  }
}

// ---------------------------------------------------------------------------------------------------- χοληστερίνη

const cholInfo = MetricInfo(
  title: 'Χοληστερίνη · τι τη ρίχνει',
  what: 'Μετρά τα τρόφιμα που έφαγες και ρίχνουν την LDL («κακή» χοληστερίνη), από τις κατηγορίες της βάσης τροφίμων.',
  shows: 'Αν κάνεις όσα συμφώνησες: λιγότερα κορεσμένα, περισσότερες φυτικές ίνες, ξηροί καρποί και πίτουρο βρώμης κάθε '
      'μέρα, όσπρια και ψάρι μέσα στην εβδομάδα. Η εφαρμογή δεν προβλέπει τη νέα σου LDL· αυτό το λένε μόνο οι εξετάσεις.',
  compare: 'Κορεσμένα έως 6% των θερμίδων (AHA/ACC) · φυτικές ίνες 30 g (Reynolds 2019) · 3 g β-γλυκάνες βρώμης τη μέρα '
      '(EFSA) · ξηροί καρποί περίπου 30 g (Del Gobbo 2015) · όσπρια και φυτικά τρόφιμα μαζί (Jenkins 2003).',
  accuracy: 'Οι μέρες με λίγη καταγραφή (κάτω από 1.200 kcal) δεν μπαίνουν στους μέσους όρους. Αν ένα τρόφιμο δεν έχει τιμή '
      'για κορεσμένα ή ίνες στην πηγή του, το σύνολο είναι «τουλάχιστον».',
  cite: 'Eckel 2013 (AHA/ACC) · EFSA 2010/2011 · Reynolds 2019 (Lancet) · Del Gobbo 2015 (AJCN) · Jenkins 2003 (JAMA)',
);

List<(DateTime, CholDay)> _daysOf(FoodStore food, DateTime from, DateTime toExclusive) => [
      for (var d = from; d.isBefore(toExclusive); d = DateTime(d.year, d.month, d.day + 1)) (d, CholDay(food.entriesFor(d))),
    ];

/// Κάρτα «Χοληστερίνη» στη Διατροφή (μόνο όταν ο γιατρός ζήτησε να πέσει η LDL): η μέρα που βλέπεις και η εβδομάδα της.
class CholCard extends StatelessWidget {
  const CholCard({super.key, required this.food, required this.goals, required this.day, required this.today});
  final FoodStore food;
  final Goals goals;
  final DateTime day;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final g = goals;
    final d = CholDay(food.entriesFor(day));
    final week = _daysOf(food, weekStart(day), DateTime(day.year, day.month, day.day + 1));
    final legumes = week.where((x) => x.$2.legumes).length;
    final fish = week.where((x) => x.$2.fish).length;
    return AppCard(
      key: const ValueKey('nutrition-chol'),
      onTap: () => Navigator.of(context).push(CholesterolPage.route(food, g, today)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardHeader(
          icon: Icons.favorite_rounded,
          title: 'Χοληστερίνη · τι τη ρίχνει',
          color: c.heart,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            const InfoDot(cholInfo),
            Icon(Icons.chevron_right_rounded, color: c.textTertiary),
          ]),
        ),
        const SizedBox(height: 6),
        if (g.nutsG > 0) CholRow(label: 'Ξηροί καρποί', value: '${d.nutsG.round()} g', target: '${g.nutsG} g', done: d.nutsG >= g.nutsG - 1e-9),
        if (g.branG > 0)
          CholRow(label: 'Πίτουρο βρώμης', value: '${d.branG.round()} g', target: '${g.branG} g', done: d.branG >= g.branG - 1e-9),
        if (g.legumesWeek > 0)
          CholRow(label: 'Όσπρια', sub: 'αυτή την εβδομάδα', value: '$legumes', target: '${g.legumesWeek}', done: legumes >= g.legumesWeek),
        if (g.fishWeek > 0) CholRow(label: 'Ψάρι', sub: 'αυτή την εβδομάδα', value: '$fish', target: '${g.fishWeek}', done: fish >= g.fishWeek),
      ]),
    );
  }
}

class CholRow extends StatelessWidget {
  const CholRow({super.key, required this.label, required this.value, required this.target, required this.done, this.sub});
  final String label, value, target;
  final String? sub;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Semantics(
      label: '$label${sub == null ? '' : ', $sub'}: $value${target.isEmpty ? '' : ' από $target'}${done ? ', έγινε' : ''}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
              if (sub != null) Text(sub!, style: TextStyle(fontSize: 12.5, color: c.textTertiary)),
            ]),
          ),
          if (done) Padding(padding: const EdgeInsets.only(right: 6), child: Icon(Icons.check_circle_rounded, size: 20, color: c.good)),
          Flexible(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: value, style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
                if (target.isNotEmpty) TextSpan(text: ' / $target', style: TextStyle(color: c.textSecondary)),
              ]),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14.5, fontFeatures: tabular),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Σελίδα «Χοληστερίνη» (σχέδια 12/11, 3β): οι μέρες της εβδομάδας που ΕΧΟΥΝ τελειώσει, ή 4 εβδομάδες.
class CholesterolPage extends StatefulWidget {
  const CholesterolPage({super.key, required this.food, required this.goals, required this.today});
  final FoodStore food;
  final Goals goals;
  final DateTime today;

  static Route<void> route(FoodStore food, Goals goals, DateTime today) => MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'Χοληστερίνη'), builder: (_) => CholesterolPage(food: food, goals: goals, today: today));

  @override
  State<CholesterolPage> createState() => _CholesterolPageState();
}

class _CholesterolPageState extends State<CholesterolPage> {
  bool _four = false;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final g = widget.goals;
    final today = dayOf(widget.today);
    final ws = weekStart(today);
    // Μόνο οι μέρες που έχουν τελειώσει (σήμερα όχι).
    final thisWeek = CholWeek(_daysOf(widget.food, ws, today));
    final weeks = [
      for (var k = 3; k >= 0; k--)
        () {
          final from = DateTime(ws.year, ws.month, ws.day - 7 * k);
          final to = k == 0 ? today : DateTime(from.year, from.month, from.day + 7);
          return (from, CholWeek(_daysOf(widget.food, from, to)));
        }(),
    ];
    const dayLabels = ['Δε', 'Τρ', 'Τε', 'Πε', 'Πα', 'Σα', 'Κυ'];
    List<double?> perDay(double? Function(CholDay) f) => [
          for (var k = 0; k < 7; k++)
            () {
              final hit = thisWeek.days.where((x) => x.$1.weekday == k + 1 && x.$2.full);
              return hit.isEmpty ? null : f(hit.first.$2);
            }(),
        ];
    final w = thisWeek;
    final small = TextStyle(fontSize: 13, height: 1.45, color: c.textSecondary);
    return Scaffold(
      appBar: AppBar(title: const Text('Χοληστερίνη')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
              Text(longDate(today), style: small),
              const SizedBox(height: 6),
              Text('Η εφαρμογή δεν προβλέπει τη νέα σου LDL· δείχνει μόνο αν κάνεις όσα τη ρίχνουν. Τις τιμές τις λένε οι '
                  'εξετάσεις και ο γιατρός σου.', style: small),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                key: const ValueKey('chol-range'),
                segments: const [
                  ButtonSegment(value: false, label: Text('Αυτή η εβδομάδα')),
                  ButtonSegment(value: true, label: Text('4 εβδομάδες')),
                ],
                selected: {_four},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _four = s.first),
              ),
              const SizedBox(height: 12),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  CardHeader(icon: Icons.bar_chart_rounded, title: 'Κορεσμένα, % των θερμίδων', color: c.heart, trailing: const InfoDot(cholInfo)),
                  const SizedBox(height: 4),
                  Text(_meanText(_four ? _mean(weeks.map((x) => x.$2.satPctMean)) : w.satPctMean, '%', 'έως ${g.satPct}%'), style: small),
                  const SizedBox(height: 10),
                  _four
                      ? MiniBars(
                          values: [for (final x in weeks) x.$2.satPctMean],
                          labels: [for (final x in weeks) dayMonth(x.$1)],
                          target: g.satPct.toDouble(),
                          color: c.heart,
                          over: c.warn,
                          higherIsWorse: true,
                          format: (v) => dec(v),
                        )
                      : MiniBars(
                          values: perDay((d) => d.satPct),
                          labels: dayLabels,
                          target: g.satPct.toDouble(),
                          color: c.heart,
                          over: c.warn,
                          higherIsWorse: true,
                          format: (v) => dec(v),
                        ),
                ]),
              ),
              const SizedBox(height: 12),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  CardHeader(icon: Icons.grass_rounded, title: 'Φυτικές ίνες, g', color: c.good),
                  const SizedBox(height: 4),
                  Text(_meanText(_four ? _mean(weeks.map((x) => x.$2.fiberMean)) : w.fiberMean, ' g', '${g.fiber} g', digits: 0), style: small),
                  const SizedBox(height: 10),
                  _four
                      ? MiniBars(
                          values: [for (final x in weeks) x.$2.fiberMean],
                          labels: [for (final x in weeks) dayMonth(x.$1)],
                          target: g.fiber.toDouble(),
                          color: c.good,
                          format: (v) => v.round().toString(),
                        )
                      : MiniBars(
                          values: perDay((d) => d.fiber),
                          labels: dayLabels,
                          target: g.fiber.toDouble(),
                          color: c.good,
                          format: (v) => v.round().toString(),
                        ),
                ]),
              ),
              const SizedBox(height: 12),
              if (!_four)
                AppCard(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (g.nutsG > 0)
                      CholRow(
                          label: 'Ξηροί καρποί',
                          sub: 'μέρες με ${g.nutsG} g',
                          value: '${w.daysWithNuts(g.nutsG)} από ${w.fullDays} μέρες',
                          target: '',
                          done: w.fullDays > 0 && w.daysWithNuts(g.nutsG) == w.fullDays),
                    if (g.branG > 0)
                      CholRow(
                          label: 'Πίτουρο βρώμης',
                          sub: 'μέρες με ${g.branG} g',
                          value: '${w.daysWithBran(g.branG)} από ${w.fullDays} μέρες',
                          target: '',
                          done: w.fullDays > 0 && w.daysWithBran(g.branG) == w.fullDays),
                    if (g.legumesWeek > 0)
                      CholRow(label: 'Όσπρια', value: '${w.legumes}', target: '${g.legumesWeek} φορές', done: w.legumes >= g.legumesWeek),
                    if (g.fishWeek > 0) CholRow(label: 'Ψάρι', value: '${w.fish}', target: '${g.fishWeek} φορές', done: w.fish >= g.fishWeek),
                    CholRow(
                        label: 'Αλάτι κάτω από ${dec(g.salt, 0)} g',
                        value: '${w.daysSaltOk(g.salt)} από ${w.fullDays} μέρες',
                        target: '',
                        done: w.fullDays > 0 && w.daysSaltOk(g.salt) == w.fullDays),
                  ]),
                ),
              const SizedBox(height: 10),
              Text(
                'Μέρες με λίγη καταγραφή (κάτω από ${thousands(fullDayKcal.round())} kcal) δεν μετρούν στους μέσους όρους. Σήμερα δεν '
                'μετρά μέχρι να τελειώσει η μέρα. Όσπρια: μία φορά = 40 g ξερά ή 100 g βρασμένα· ψάρι: 100 g.',
                style: small,
              ),
            ]),
          ),
        ),
      ),
    );
  }

  static double? _mean(Iterable<double?> v) {
    final x = v.whereType<double>().toList();
    return x.isEmpty ? null : x.reduce((a, b) => a + b) / x.length;
  }

  static String _meanText(double? v, String unit, String target, {int digits = 1}) =>
      v == null ? 'Δεν υπάρχει ακόμα ολοκληρωμένη μέρα · στόχος $target' : 'μέσος όρος ${dec(v, digits)}$unit · στόχος $target';
}

/// Μικρές μπάρες με γραμμή στόχου. null: μέρα χωρίς αρκετή καταγραφή (κενή).
class MiniBars extends StatelessWidget {
  const MiniBars({
    super.key,
    required this.values,
    required this.labels,
    required this.target,
    required this.color,
    required this.format,
    this.over,
    this.higherIsWorse = false,
  });
  final List<double?> values;
  final List<String> labels;
  final double target;
  final Color color;
  final Color? over;
  final bool higherIsWorse;
  final String Function(double) format;

  static const _h = 96.0;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final top = math.max(target * 1.35, values.whereType<double>().fold<double>(0, math.max));
    double y(double v) => top <= 0 ? 0 : (v / top * _h).clamp(0, _h);
    return Semantics(
      label: [for (var k = 0; k < values.length; k++) '${labels[k]}: ${values[k] == null ? 'χωρίς' : format(values[k]!)}'].join(', '),
      excludeSemantics: true,
      child: Column(children: [
        SizedBox(
          height: _h + 18,
          child: Stack(children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: y(target),
              child: Container(height: 1.5, color: c.textTertiary.withValues(alpha: 0.6)),
            ),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final v in values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      if (v != null)
                        Text(format(v), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.textSecondary, fontFeatures: tabular)),
                      const SizedBox(height: 2),
                      Container(
                        height: v == null ? 0 : math.max(2, y(v)),
                        decoration: BoxDecoration(
                          color: v != null && over != null && (higherIsWorse ? v > target + 1e-9 : v < target - 1e-9) ? over : color,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ]),
                  ),
                ),
            ]),
          ]),
        ),
        const SizedBox(height: 4),
        Row(children: [
          for (final l in labels)
            Expanded(child: Text(l, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.textTertiary))),
        ]),
      ]),
    );
  }
}
