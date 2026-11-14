import 'package:flutter/material.dart';

import '../format.dart';
import '../sources.dart';
import '../theme.dart';
import '../trends.dart';
import '../weekly.dart';
import '../widgets.dart';
import 'trends.dart';

/// «Η εβδομάδα σου»: φαίνεται στη Σήμερα την Κυριακή το βράδυ και τη Δευτέρα.
class WeekCard extends StatelessWidget {
  const WeekCard({super.key, required this.review});
  final WeekReview review;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final r = review;
    final range = r.monday.month == r.sunday.month
        ? '${r.monday.day}–${dayMonth(r.sunday)}'
        : '${dayMonth(r.monday)} – ${dayMonth(r.sunday)}';

    final highlights = <(IconData, Color, String, String)>[
      if (r.bestNight != null)
        (
          Icons.bedtime_rounded,
          c.sleep,
          'Καλύτερη βαθμολογία ύπνου (εκτίμηση)',
          // Η νύχτα έχει την ημερομηνία του πρωινού: «Τρί→Τετ» = η νύχτα από Τρίτη προς Τετάρτη.
          '${_weekday(DateTime(r.bestNight!.year, r.bestNight!.month, r.bestNight!.day - 1))}→${_weekday(r.bestNight!)} ·\u00A0${r.bestNightScore!.round()}',
        ),
      if (r.mostSteps != null)
        (Icons.directions_walk_rounded, c.move, 'Περισσότερα βήματα', '${_weekday(r.mostSteps!)} ·\u00A0${thousands(r.mostStepsValue!)}'),
      if (r.activeTotal != null)
        (
          Icons.timer_rounded,
          c.move,
          r.activeDays == 7 ? 'Ενεργός χρόνος, σύνολο' : 'Ενεργός χρόνος, ${countText(r.activeDays, 'μέρα', 'μέρες')}',
          hoursMinutes(r.activeTotal!.round()),
        ),
      if (r.weightLast != null)
        (
          Icons.monitor_weight_rounded,
          c.body,
          r.weightFirst != null && r.weightFirst!.$1 != r.weightLast!.$1 ? 'Βάρος μέσα στην εβδομάδα' : 'Ζύγιση',
          r.weightFirst != null && r.weightFirst!.$1 != r.weightLast!.$1
              ? '${dec(r.weightFirst!.$2)} → ${dec(r.weightLast!.$2)} kg'
              : '${dec(r.weightLast!.$2)} kg ·\u00A0${_weekday(r.weightLast!.$1)}',
        ),
    ];

    final shown = r.items.where((t) => t.current != null).toList();

    return AppCard(
      // Round 9 (R9-U1-2): στο ανοιχτό Fold η κάρτα είναι κάτω από τις δύο στήλες, σε όλο το πλάτος (today.dart): εκεί
      // (≥ 600 dp) οι πλακέτες σε μία σειρά και οι γραμμές σε δύο στήλες (~320 dp η καθεμία), ποτέ τεντωμένες.
      // Round 10 (R10-B8-1 = R10-B2-B1): οι γραμμές σε δύο στήλες ήδη από 520 dp. Στο ανοιχτό Fold όρθιο (750 dp, με την
      // πλαϊνή μπάρα) η κάρτα έχει 560 dp μέσα: με το 600 έμενε μία στήλη γραμμών 560 dp, με το «Σταθερό» ~450 dp μακριά από
      // το όνομα. Τώρα δύο στήλες των 268 dp (όσο σχεδόν η στήλη ενός κινητού 360 dp)· οι πλακέτες μένουν δύο-δύο ως τα 600.
      // Round 12 (R12-D2-1 (b)): δύο στήλες γραμμών μόνο όταν κάθε λέξη τους χωρά στη στενότερη στήλη τιμής: το μισό μιας
      // γραμμής δίπλα στο «Λίγες μέρες για συμπέρασμα», ((πλάτος − 24) ÷ 2 − 26) ÷ 2 (121 dp στο ανοιχτό Fold, 560 dp μέσα
      // στην κάρτα), με τα γράμματα όπως θα ζωγραφιστούν ([wordsFit]). Πριν, μόνο «από 520 dp»: στο ανοιχτό Fold από ~1,7×
      // το «13 λεπτά» (έντονα 16, ~147 dp στα 2×) και από ~1,3× το «προηγούμενες:» (12,5, ~121 dp στο 1,3×) κόβονταν μέσα
      // στη λέξη. Τώρα, όταν δεν χωρούν, μία στήλη, όπως στο κινητό (και πάνω από 1,3× τα «χάπια» κάτω από τις τιμές).
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 600;
        final stackPills = MediaQuery.textScalerOf(context).scale(10) > 10.05;
        final valueCol = ((box.maxWidth - 24) / 2 - 26) / 2 - 2;
        final wideRows = box.maxWidth >= 520 &&
            wordsFit(context, [for (final t in shown) metricLabel(t.def, t.source)], const TextStyle(fontSize: 14), valueCol) &&
            wordsFit(
              context,
              [for (final t in shown) unitsGlued(t.def.formatAs(t.current!, t.source))],
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFeatures: tabular),
              valueCol,
            ) &&
            wordsFit(
              context,
              ['4 προηγούμενες:', for (final t in shown) if (t.previous != null) unitsGlued(t.def.formatAs(t.previous!, t.source))],
              const TextStyle(fontSize: 12.5, fontFeatures: tabular),
              valueCol,
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconBadge(Icons.calendar_month_rounded, c.primary, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Η εβδομάδα σου',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text, letterSpacing: -0.2),
                      ),
                      Text(
                        '$range ·\u00A0σε σύγκριση με τις 4 προηγούμενες εβδομάδες',
                        style: TextStyle(fontSize: 13, color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Round 1 (U1b-05): δύο ανά σειρά με ΙΔΙΟ ύψος· μια μονή τελευταία σε όλο το πλάτος (πριν: κουτιά άλλου ύψους
            // και ένα μόνο του με κενό δίπλα).
            // Round 9 (R9-U1-2): σε φαρδιά κάρτα όλες σε μία σειρά, με θέσεις για 4 (ίδιο πλάτος, όσες κι αν είναι).
            if (highlights.isNotEmpty && wide) ...[
              const SizedBox(height: 14),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < 4; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(child: i < highlights.length ? _Highlight.of(highlights[i]) : const SizedBox()),
                    ],
                  ],
                ),
              ),
            ] else if (highlights.isNotEmpty) ...[
              const SizedBox(height: 14),
              for (var i = 0; i < highlights.length; i += 2) ...[
                if (i > 0) const SizedBox(height: 10),
                if (i + 1 < highlights.length)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _Highlight.of(highlights[i])),
                        const SizedBox(width: 10),
                        Expanded(child: _Highlight.of(highlights[i + 1])),
                      ],
                    ),
                  )
                else
                  _Highlight.of(highlights[i]),
              ],
            ],
            if (shown.isNotEmpty && wideRows) ...[
              const SizedBox(height: 10),
              for (var i = 0; i < shown.length; i += 2) ...[
                if (i > 0) const Hairline(vertical: 0),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Round 13 (R13-E1-2): ο έλεγχος [wideRows] υποθέτει ότι το «χάπι» παίρνει το πολύ τη μισή γραμμή· τα άλλα
                    // «χάπια» («45 λεπτά αργότερα», «Αλλαγή πηγής») δεν στενεύουν, οπότε από 1,1× η στήλη της τιμής έμενε
                    // στενότερη και το «προηγούμενες:» κοβόταν. Πάνω από 1× το «χάπι» πάει κάτω από την τιμή.
                    Expanded(child: _WeekRow(t: shown[i], forceStack: stackPills)),
                    const SizedBox(width: 24),
                    Expanded(child: i + 1 < shown.length ? _WeekRow(t: shown[i + 1], forceStack: stackPills) : const SizedBox()),
                  ],
                ),
              ],
            ] else if (shown.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0) const Hairline(vertical: 0),
                _WeekRow(t: shown[i]),
              ],
            ],
            const SizedBox(height: 8),
            Text(
              // Δεύτερος έλεγχος υπολογισμών C1: με 7 μέρες ο έλεγχος σπάνια βλέπει αλλαγή· «Σταθερό» δεν σημαίνει «χωράει».
              'Μεσαία τιμή της εβδομάδας. «Σταθερό»: δεν φαίνεται καθαρή αλλαγή· μία εβδομάδα σπάνια αρκεί για να φανεί.'
              '${r.items.any((t) => t.current != null && t.inconclusive) ? ' «Λίγες μέρες για συμπέρασμα»: οι μέρες μοιάζουν πολύ μεταξύ τους και δεν φτάνουν για σύγκριση.' : ''}'
              '${r.items.any((t) => t.end.isBefore(r.sunday)) ? ' Η σημερινή μέρα δεν μετράει στα βήματα και στον ενεργό χρόνο, γιατί δεν έχει τελειώσει.' : ''}'
              // Έλεγχος υπολογισμών F17: δύο ζυγίσεις μιας εβδομάδας απέχουν συχνά 0,5–1 kg μόνο από το νερό.
              '${r.weightFirst != null && r.weightLast != null && r.weightFirst!.$1 != r.weightLast!.$1 ? ' Το βάρος αλλάζει 0,5–1 kg από μέρα σε μέρα με το νερό και το φαγητό· μία εβδομάδα δεν δείχνει τάση.' : ''}',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: c.textTertiary),
            ),
          ],
        );
      }),
    );
  }
}

class _Highlight extends StatelessWidget {
  const _Highlight({required this.icon, required this.color, required this.label, required this.value});

  factory _Highlight.of((IconData, Color, String, String) h) => _Highlight(icon: h.$1, color: h.$2, label: h.$3, value: h.$4);
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.tint(color), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            // Round 2 (R2-U1-2): το εικονίδιο στην πρώτη γραμμή, όσες γραμμές κι αν πάρει η ετικέτα.
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  // Round 2 (R2-U1-2): ποτέ κομμένη («(εκτιμ…» στο ανοιχτό Fold, όπου η πλακέτα έχει ≈ 104 dp και θέλει
                  // 4 γραμμές)· η σειρά με τις δύο πλακέτες είναι IntrinsicHeight, άρα μένουν ίσες.
                  style: TextStyle(fontSize: 12.5, height: 1.2, fontWeight: FontWeight.w600, color: c.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: c.text, fontFeatures: tabular),
          ),
        ],
      ),
    );
  }
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({required this.t, this.forceStack = false});
  final TrendResult t;

  /// Round 13 (R13-E1-2): στις δύο στήλες του ανοιχτού Fold το «χάπι» κάτω από την τιμή ήδη πάνω από 1×.
  final bool forceStack;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    // Round 1 (U1b-17): με «Λίγα δεδομένα» και λίγες μέρες στην εβδομάδα, «—» αντί για μια μεσαία τιμή που δεν λέει κάτι
    // (ίδιος κανόνας με τις Τάσεις, F10), και χωρίς «πριν …».
    final insufficient = t.status == TrendStatus.insufficient;
    // Round 8 (R8-A5-3): και με «Αλλαγή πηγής» (π.χ. 1 νύχτα του Oura σε εβδομάδα του ρολογιού), όπως οι Τάσεις.
    final few = (insufficient || t.status == TrendStatus.sourceChange) && t.nCurrent < t.needed;
    // Round 12 (R12-D2-1): με γράμματα πάνω από 1,3× το «χάπι» πάει κάτω από την τιμή, όχι δίπλα. Δίπλα του η στήλη της τιμής
    // στένευε τόσο (κινητό 360 dp, 2×: ~143 dp· με «Λίγες μέρες για συμπέρασμα» το μισό της γραμμής) ώστε η λέξη
    // «προηγούμενες:» (Inter 12,5 στα 2×: ~181 dp) και το «13 λεπτά» (έντονα 16, ~147 dp) κόβονταν μέσα στη λέξη. Ως 1,3× η
    // στενότερη στήλη του κινητού (360 dp, «Λίγες μέρες…»: ~133 dp) χωρά το «προηγούμενες:» (~121 dp)· στο ανοιχτό Fold, όπου
    // δεν χωρά δίπλα στο «χάπι», οι γραμμές πάνε σε μία στήλη ([WeekCard]).
    final stacked = forceStack || MediaQuery.textScalerOf(context).scale(10) > 13.01;
    final Widget pill = t.inconclusive ? TrendPill(inconclusiveText(t.def), maxLines: 2) : TrendStatusPill(r: t);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: trendSectionColor(c, t.def.section), shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(metricLabel(t.def, t.source), style: TextStyle(fontSize: 14, color: c.textSecondary)),
                const SizedBox(height: 1),
                // Round 11 (R11-C2-1): ο αριθμός με τη μονάδα του ([unitsGlued], R2-U2-05)· στο ανοιχτό Fold (δύο στήλες γραμμών
                // από τα 520 dp, R10-B8-1) η στήλη με το «Λίγες μέρες για συμπέρασμα» έχει ~121 dp και η τιμή έσπαγε
                // «7 ώρες 13» / «λεπτά». Τώρα το πολύ «7 ώρες» / «13 λεπτά».
                Text(
                  few ? '—' : unitsGlued(t.def.formatAs(t.current!, t.source)),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: few ? c.textTertiary : c.text, fontFeatures: tabular),
                ),
                // «πριν», όχι «συνήθως»: εδώ είναι η μεσαία τιμή των 4 προηγούμενων εβδομάδων, όχι το «συνήθως» της
                // εφαρμογής (δεύτερος έλεγχος υπολογισμών C7).
                // Round 7 (U1-11): «4 προηγούμενες: 7 ώρες 26 λεπτά» (πριν «πριν 7 ώρες 26 λεπτά», που διαβάζεται «πριν από 7
                // ώρες», και «πριν 23:40» = «πριν από τις 23:40»)· ο υπότιτλος λέει «σε σύγκριση με τις 4 προηγούμενες
                // εβδομάδες».
                // Round 12 (R12-D2-1): ο κανόνας της τιμής από πάνω ([unitsGlued]: ο αριθμός με τη μονάδα του, όχι ΟΛΑ τα κενά
                // αδιάσπαστα). Πριν, το «7 ώρες 26 λεπτά» ήταν ένα κομμάτι 131 dp (1,3×) σε στήλη 121 dp και κοβόταν μέσα στη
                // λέξη («… λε» / «πτά»)· τώρα το πολύ «7 ώρες» / «26 λεπτά».
                if (t.previous != null && !insufficient)
                  Text(
                    '4 προηγούμενες: ${unitsGlued(t.def.formatAs(t.previous!, t.source))}',
                    style: TextStyle(fontSize: 12.5, color: c.textTertiary, fontFeatures: tabular),
                  ),
                if (stacked) Padding(padding: const EdgeInsets.only(top: 6), child: pill),
              ],
            ),
          ),
          if (!stacked) ...[
            const SizedBox(width: 8),
            if (t.inconclusive) Flexible(child: pill) else pill,
          ],
        ],
      ),
    );
  }
}

String _weekday(DateTime d) => weekdayShort(d);

/// Για να ξέρει η Σήμερα αν πρέπει να δείξει την κάρτα.
WeekReview? currentWeekReview(Map<String, Map<String, double>> history, DateTime now, {SourcePlan? plan}) {
  final sunday = reviewWeekSunday(now);
  if (sunday == null || history.isEmpty) return null;
  final r = buildWeekReview(history, sunday, now, plan: plan);
  final any = r.items.any((t) => t.current != null);
  return any ? r : null;
}
