import 'package:flutter/material.dart';

import '../body_trend.dart';
import '../data.dart';
import '../format.dart';
import '../history.dart';
import '../profile.dart';
import '../reference.dart';
import '../shown.dart';
import '../theme.dart';
import '../widgets.dart';
import 'info_sheet.dart';
import 'me_page.dart';
import 'metric_page.dart';
import 'waist_sheet.dart';
import '../waist.dart';

class BodyPage extends StatelessWidget {
  const BodyPage({super.key, required this.store, this.now});
  final HealthStore store;

  /// Για τα στιγμιότυπα δοκιμών (αλλιώς η ώρα του κινητού).
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final c = Aigaio.of(context);
        final d = store.data;
        final body = d?.body ?? const <BodyMeasurement>[];
        // Round 1 (S3-3): «Σήμερα/Χθες» σε σχέση με ΤΩΡΑ, όχι με την ώρα της τελευταίας ανάγνωσης (με παλιά ανάγνωση
        // η χθεσινή ζύγιση έγραφε «Σήμερα 07:10»).
        final clock = now ?? DateTime.now();
        // Round 1 (S11-2): ζυγίσεις που μοιάζουν ξένες: δεν μετρούν σε γραφήματα και τάσεις· φαίνονται σημειωμένες.
        // Round 2 (g4 · R2-E-2): ζύγιση «σε αναμονή» (διαφέρει πολύ, χωρίς ακόμα επόμενη) φαίνεται και μετρά κανονικά εδώ.
        final guard = guardBody(body);
        final foreign = guard.foreign;
        // Round 7 (A4-1): η ΖΥΓΙΣΗ ΤΗΣ ΜΕΡΑΣ ([guardBody] `shown`: η πρώτη της μέρας που μετρά, ή «σε αναμονή»), ίδια με τη
        // Σήμερα, το widget, τις Τάσεις, την αναφορά και τη διόρθωση θερμίδων. Πριν: η χρονικά τελευταία ζύγιση, και μια
        // βραδινή ζύγιση μετά από φαγητό/άσκηση (82,1 μετά την πρωινή 80,7) έδειχνε εδώ «+1,2 kg», δείκτη 25,3 και «Πάνω από
        // το εύρος», ενώ η Σήμερα και το widget 80,7, «−0,2 kg» και «μέσα στο εύρος», και «Λίπος 27,6%  (+2,0)» με τάση από
        // τις πρωινές που δεν την περιέχει (κανόνας R6-1). Μόνο αν δεν φαίνεται καμία (όλες ξένες): η τελευταία, σημειωμένη.
        final last = guard.shown.isEmpty ? d?.latestBody : guard.shown.last;
        final lastPending = last != null && guard.pending.contains(last);
        // Η επόμενη ζύγιση της ίδιας μέρας, αν υπάρχει (π.χ. η βραδινή): φαίνεται σε μια γκρι γραμμή, χωρίς διαφορά, δείκτη,
        // εύρος ή τάση. Όχι όταν η ζύγιση της μέρας δεν μετρά (εκεί λέει ήδη γιατί).
        final later = last == null || foreign.contains(last) || lastPending
            ? null
            : [
                for (final b in body)
                  if (b.weight != null && dayOf(b.time) == dayOf(last.time) && b.time.isAfter(last.time)) b,
              ].lastOrNull;
        // Round 2 (g4 · R2-D-8): τα γραφήματα με μία ζύγιση ανά μέρα, την πρώτη που μετρά ([countedBody]), όπως η τάση, το
        // ιστορικό, οι Τάσεις και η σελίδα της μέτρησης (πριν: κάθε ζύγιση, και η βραδινή μετά την προπόνηση ζιγκ-ζαγκ).
        // Round 3 (k1 · R3-C-1): η ζύγιση της μέρας του φύλακα, ίδια με το ιστορικό ([weighInDays]).
        final daily = guard.counted;

        // Οι 12 πιο πρόσφατες ζυγίσεις του πίνακα «Ζυγίσεις», νεότερη πρώτη.
        final tableRows = body.reversed.take(12).toList();

        final skinNights = (d?.nights ?? const <Night>[]).where((n) => n.skinTemp != null).toList();
        final skinBase = d?.skinTempBaseline;

        final left = <Widget>[
          if (last == null && d != null && d.failed.contains('body'))
            EmptyCard(
              icon: Icons.monitor_weight_rounded,
              color: c.body,
              title: 'Οι ζυγίσεις δεν διαβάστηκαν τώρα',
              text: 'Η Samsung δεν τις έδωσε αυτή τη φορά. Τράβηξε την οθόνη προς τα κάτω για να ξαναδοκιμάσεις.',
            )
          // Round 8 (R8-A4-3): η άδεια «Σύσταση σώματος» της Samsung Health είναι κλειστή (κανένα «body» στην ανάγνωση,
          // κανένα σφάλμα): πριν «Δεν υπάρχει ζύγιση · Ζυγίσου στην InBody», ενώ η ζύγιση δεν μπορούσε να φτάσει.
          else if (last == null && bodyNotPermitted(d))
            EmptyCard(
              icon: Icons.monitor_weight_rounded,
              color: c.body,
              title: bodyNoPermissionTitle,
              text: bodyNoPermissionText,
              buttonText: 'Άδειες Samsung Health',
              onPressed: () => store.refresh(askPermissions: true),
              primary: true,
            )
          else if (last == null)
            EmptyCard(
              icon: Icons.monitor_weight_rounded,
              color: c.body,
              title: 'Δεν υπάρχει ζύγιση',
              text: 'Ζυγίσου στην InBody. Η μέτρηση φτάνει εδώ μέσω Samsung Health σε λίγα λεπτά.',
            )
          else
            _LatestCard(
              last: last,
              // Round 5 (n1 · R5-B-1): η προηγούμενη που ΜΕΤΡΑ, από προηγούμενη μέρα (όπως η Σήμερα και το widget).
              previous: previousCounted(guard.counted, last),
              foreign: foreign.contains(last),
              pending: lastPending,
              mixed: mixedDayPending(guard.pending, last),
              later: later,
              body: body,
              now: clock,
              profile: store.profile,
              onProfile: () => Navigator.of(context).push(MePage.route(store)),
            ),
          // Round 1 (U1a-20): ελάχιστο εύρος άξονα 3 (kg ή μονάδες λίπους): η συνηθισμένη διακύμανση μιας μέρας (0,5–1 kg,
          // reference.dart) να μη γεμίζει το γράφημα και να μοιάζει με μεγάλη αλλαγή (πριν 1).
          if (daily.where((b) => b.weight != null).length >= 2)
            _chartCard(
              context,
              K.weight,
              'Βάρος (kg)',
              [for (final b in daily) if (b.weight != null) (b.time, b.weight!)],
              c.body,
              clock,
            ),
          _WaistCard(store: store),
          if (daily.where((b) => b.fatPct != null).length >= 2)
            _chartCard(
              context,
              K.fatPct,
              'Λίπος (%)',
              [for (final b in daily) if (b.fatPct != null) (b.time, b.fatPct!)],
              c.heart,
              clock,
            ),
        ];

        final bodyMore = <Widget>[
          if (daily.where((b) => b.smm != null).length >= 2)
            _chartCard(
              context,
              K.smm,
              'Σκελετικοί μύες (kg)',
              [for (final b in daily) if (b.smm != null) (b.time, b.smm!)],
              c.energy,
              clock,
            ),
          if (body.isNotEmpty)
            _WeighTable(
              body: tableRows,
              now: clock,
              foreign: foreign,
              // Round 9 (R9-U4-7): η δεύτερη ζύγιση μιας μέρας (π.χ. η βραδινή), που δεν μετρά, σε γκρι με την ώρα της.
              other: otherWeighIns(tableRows, shown: guard.shown, foreign: foreign, pending: guard.pending),
            ),
          // Θερμοκρασία καρπού: μόνο ως απόκλιση από το «συνήθως» (τρίτος έλεγχος F2/C5), ποτέ βαθμοί (33,6 °C διαβαζόταν ως
          // υποθερμία). Το «συνήθως» είναι η μεσαία τιμή των 14 προηγούμενων νυχτών (όχι «μέσος όρος»).
          if (skinNights.length >= 2)
            AppCard(
              key: const ValueKey('body-skin'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CardHeader(icon: Icons.thermostat_rounded, title: 'Θερμοκρασία καρπού στον ύπνο', color: c.move),
                  const SizedBox(height: 10),
                  Text(
                    skinBase == null
                        ? 'Χρειάζονται λίγες ακόμα νύχτες για το «συνήθως» σου (7 νύχτες).'
                        : 'Κάθε νύχτα σε σχέση με το «συνήθως» σου (η μεσαία τιμή των 14 προηγούμενων νυχτών, 0 στο '
                            'γράφημα). Αλλάζει πολύ με τη θερμοκρασία του δωματίου, τα σκεπάσματα και το λουράκι. Δείχνει '
                            'μόνο τι άλλαξε σε σχέση με εσένα· δεν είναι θερμοκρασία σώματος ούτε πυρετός.',
                    style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.35),
                  ),
                  if (skinBase != null) ...[
                    const SizedBox(height: 12),
                    LineChart(
                      points: [
                        for (final n in skinNights.length <= 30 ? skinNights : skinNights.sublist(skinNights.length - 30))
                          (n.date, shownDiff(n.skinTemp!, skinBase, 1)),
                      ],
                      format: (v) => signedDec(v),
                      color: c.move,
                      dateLabel: dayMonth,
                    ),
                  ],
                ],
              ),
            ),
        ];

        return PageFrame(
          title: 'Σώμα',
          subtitle: body.isEmpty ? null : countText(body.length, 'ζύγιση', 'ζυγίσεις'),
          onRefresh: () => store.refresh(),
          left: left,
          right: bodyMore,
        );
      },
    );
  }

  Widget _chartCard(BuildContext context, String metric, String title, List<(DateTime, double)> points, Color color, DateTime clock) {
    return AppCard(
      key: ValueKey('body-$metric'),
      // Round 1 (U1b-21): η σελίδα της μέτρησης με το ίδιο ρολόι (πριν: πάντα η ώρα του κινητού, και το στιγμιότυπο έδειχνε
      // «Λίγες τιμές για γράφημα»).
      onTap: () => Navigator.of(context).push(MetricPage.route(store, metric, now: clock)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHeader(
            icon: Icons.show_chart_rounded,
            title: title,
            color: color,
            trailing: Icon(Icons.chevron_right_rounded, color: Aigaio.of(context).textTertiary),
          ),
          const SizedBox(height: 12),
          LineChart(points: points, color: color, format: (v) => dec(v), minRange: 3, dateLabel: yearAwareLabel(points)),
        ],
      ),
    );
  }
}

/// Round 1 (U1a-19α): όταν το γράφημα περνά σε άλλη χρονιά, οι ημερομηνίες της παλιάς χρονιάς γράφουν και το έτος
/// («28 Δεκ 2025 … 24 Οκτ»), ώστε να μη μοιάζει ότι ο χρόνος πάει πίσω.
String Function(DateTime) yearAwareLabel(List<(DateTime, double)> points) {
  final year = points.isEmpty ? null : points.last.$1.year;
  return (d) => year == null || d.year == year ? dayMonth(d) : dayMonthYear(d);
}

class _LatestCard extends StatelessWidget {
  const _LatestCard({
    required this.last,
    required this.previous,
    required this.body,
    required this.now,
    required this.profile,
    required this.onProfile,
    this.foreign = false,
    this.pending = false,
    this.mixed = false,
    this.later,
  });
  final BodyMeasurement last;

  /// Round 7 (A4-1): μια επόμενη ζύγιση της ίδιας μέρας (η τελευταία), που δεν μετρά: μετρά η ζύγιση της μέρας ([last]).
  final BodyMeasurement? later;

  /// Round 1 (S11-2): η τελευταία ζύγιση μοιάζει ξένη ([foreignBody]): φαίνεται, αλλά δεν μετρά.
  final bool foreign;

  /// Round 2 (R2-E-2): η τελευταία ζύγιση διαφέρει πολύ από τις προηγούμενες και δεν έχει ακόμα επόμενη ([guardBody]):
  /// φαίνεται κανονικά, με μια γραμμή που λέει πότε θα μετρήσει και στη διόρθωση θερμίδων.
  final bool pending;

  /// Round 4 (m1 · R4-A-2): «σε αναμονή» επειδή την ίδια μέρα υπάρχει κι άλλη πολύ διαφορετική ζύγιση και καμία άλλη
  /// κοντά ([mixedDayPending]): άλλη εξήγηση ([mixedLatestText]).
  final bool mixed;

  /// Όλες οι ζυγίσεις (παλιότερη πρώτη), για την τάση σε λίπος και μύες (body_trend.dart).
  final List<BodyMeasurement> body;
  final BodyMeasurement? previous;
  final DateTime now;
  final Profile profile;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    // Round 5 (n1 · R5-B-2): για ζύγιση που δεν μετρά καμία «προηγούμενη»: ούτε διαφορά, ούτε η σημείωση «σε παρένθεση η
    // αλλαγή από τις …» (πριν έμενε, χωρίς παρένθεση από κάτω).
    final p = foreign || pending ? null : previous;
    // Round 5 (n1 · R5-B-2): ούτε δείκτης μάζας σώματος από ζύγιση που δεν μετρά (π.χ. 45,0 kg με το δικό σου ύψος: 13,9),
    // όπως το widget και η Σήμερα. Ένα ύψος για όλα (έλεγχος 8/11, DATA-08): από τα στοιχεία σου· της InBody μόνο αν δεν
    // έχεις δώσει ύψος.
    final bmi = foreign || pending ? null : bmiOf(last.weight, profile.heightCm) ?? last.bmi;

    // Round 1 (U1a-7): «25,4%» χωρίς κενό, όπως παντού στην εφαρμογή· «82,2 kg» με κενό.
    String withUnit(double value, String unit, [int digits = 1]) => unit == '%' ? '${dec(value, digits)}%' : '${dec(value, digits)} $unit';

    String withDiff(double? value, double? before, String unit, {int digits = 1, bool lowerIsBetter = true}) {
      if (value == null) return '—';
      final base = withUnit(value, unit, digits);
      // Round 4 (m1 · R4-A-4): ούτε από ζύγιση «σε αναμονή» (πριν: «(−42,6)» για το παιδί του Σαββάτου).
      if (before == null || foreign || pending) return base;
      // Η διαφορά των νούμερων όπως φαίνονται (τρίτος έλεγχος F3): 82,2 και 83,4 → «−1,2».
      // Round 9 (R9-A4-3): και το 0 («82,2 kg  (0)»), όπως η Σήμερα («0 kg από 18/11») και το widget: η σημείωση από πάνω
      // λέει «σε παρένθεση η αλλαγή από τις …», και πριν, με ίδιο βάρος, δεν φαινόταν καμία.
      final diff = shownDiff(value, before, digits);
      return '$base  (${signedDec(diff, digits)})';
    }

    // Η τιμή της τελευταίας ζύγισης· σε παρένθεση η διαφορά των δύο μεσαίων τιμών (3 τελευταίες, 3 πριν), όπως φαίνονται,
    // ΜΟΝΟ όταν ξεπερνά τη διακύμανση της ζυγαριάς [floor] (round 1, S4-3: πριν γραφόταν κάθε διαφορά, π.χ. «(+0,2)» μύες).
    String trendDiff(double? value, double? Function(BodyMeasurement) f, String unit, double floor) {
      if (value == null) return '—';
      final base = withUnit(value, unit);
      // Round 6 (R6-1): ούτε τάση δίπλα σε ζύγιση που δεν μετρά· η τάση (3 τελευταίες που μετρούν) δεν την περιέχει και θα
      // διαβαζόταν σαν αλλαγή της τιμής που φαίνεται (π.χ. «Λίπος 25,0%  (+2,0)» μετά από αρρώστια).
      if (foreign || pending) return base;
      final t = bodyTrend(body, f);
      if (t == null) return base;
      final diff = shownDiff(t.now, t.before, 1);
      return bodyDiffShown(diff, floor) ? '$base  (${signedDec(diff)})' : base;
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHeader(
            icon: Icons.monitor_weight_rounded,
            // Round 8 (R8-U4-10): με δεύτερη ζύγιση της ίδιας μέρας ([later], η βραδινή) η κάρτα δείχνει τη ζύγιση ΤΗΣ ΜΕΡΑΣ
            // (την πρώτη), όχι την τελευταία: πριν «Τελευταία ζύγιση · 07:15» πάνω από το «Και 20:30: 82,1 kg».
            title: later != null ? 'Ζύγιση της μέρας' : 'Τελευταία ζύγιση',
            subtitle: '${relativeDay(last.time, now)} ${hm(last.time)}',
            color: c.body,
            trailing: const InfoButton(K.weight),
          ),
          const SizedBox(height: 14),
          BigValue(last.weight == null ? '—' : dec(last.weight!), unit: 'kg', size: 44),
          if (later != null) ...[
            const SizedBox(height: 6),
            Text(
              laterWeighInText(later!),
              key: const ValueKey('body-later-weighin'),
              style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.35),
            ),
          ],
          if (foreign) ...[
            const SizedBox(height: 6),
            Text(
              foreignLatestText,
              key: const ValueKey('body-foreign-latest'),
              style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.35),
            ),
          ],
          if (pending && !foreign) ...[
            const SizedBox(height: 6),
            Text(
              mixed ? mixedLatestText : pendingLatestText,
              key: const ValueKey('body-pending-latest'),
              style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.35),
            ),
          ],
          // Round 9 (R9-A4-3): και με διαφορά 0 («0 kg από 18/11»), όπως η Σήμερα.
          if (!foreign && !pending && p != null && last.weight != null && p.weight != null) ...[
            const SizedBox(height: 6),
            // Σχέδια 9/11 (Spec): αλλαγή χωρίς κρίση, σε γκρι.
            Align(
              alignment: Alignment.centerLeft,
              child: TrendPill('${signedDec(shownDiff(last.weight!, p.weight!, 1))} kg από ${_dayNum(p.time)}'),
            ),
          ],
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: Text(upperGr('Σύσταση σώματος'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: .6, color: c.textSecondary)),
            ),
            const LabelTag('εκτίμηση'),
          ]),
          // 13/11 (Α5): στο βάρος η αλλαγή από την προηγούμενη ζύγιση· σε λίπος και μύες η τάση από 3 ζυγίσεις, γιατί
          // μία εκτίμηση της ζυγαριάς μόνη της ανεβοκατεβαίνει με το νερό (body_trend.dart).
          if (last.fatPct != null || p != null)
            Text(
              // Round 8 (A4 Β2 / U4 Β4): η ίδια μέρα με την ίδια μορφή στο χάπι και στη σημείωση («από 13/8», όπως η Σήμερα και
              // το widget)· πριν «από 13/8» στο χάπι και «από τις 13 Αυγ.» από κάτω.
              bodyTrendNote(previous: p?.weight == null ? null : p!.time, days: bodyCompositionDays(body), date: _dayNum),
              key: const ValueKey('body-trend-note'),
              style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.35),
            ),
          const SizedBox(height: 4),
          InfoRow('Βάρος', withDiff(last.weight, p?.weight, 'kg')),
          InfoRow('Λίπος', trendDiff(last.fatPct, (b) => b.fatPct, '%', bodyFloorFatPct)),
          InfoRow('Μάζα λίπους', trendDiff(last.fatKg, (b) => b.fatKg, 'kg', bodyFloorKg)),
          InfoRow('Σκελετικοί μύες', trendDiff(last.smm, (b) => b.smm, 'kg', bodyFloorKg)),
          InfoRow('Άλιπη μάζα', trendDiff(last.leanMass, (b) => b.leanMass, 'kg', bodyFloorKg)),
          // Round 8 (R8-A4-2): χωρίς το «±10%», που δεν είχε πηγή και δεν ισχύει για κάθε άνθρωπο (Frankenfield κ.ά., J Am
          // Diet Assoc 2005: ακόμα και η καλύτερη εξίσωση βγαίνει μέσα στο ±10% μόνο στους περισσότερους, όχι σε όλους).
          if (last.bmr != null) InfoRow('Βασικός μεταβολισμός (εκτίμηση)', '${thousands(last.bmr!)} kcal'),
          // Round 7 (A4-2): κομμένος στο 0,1 ([bmiText]): ποτέ «25,0» δίπλα σε «μέσα στο εύρος».
          if (bmi != null) InfoRow('Δείκτης μάζας σώματος', bmiText(bmi)),
          if (inBodyHeight(last.weight, last.bmi) case final h? when profile.heightCm != null && (h - profile.heightCm!).abs() >= 1)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              child: Text(
                'Η εφαρμογή InBody έχει ύψος ${h.round()} cm, τα στοιχεία σου ${profile.heightCm!.round()} cm. Εδώ μετρά το δικό σου· '
                'διόρθωσέ το και στην InBody, για να βγάζει σωστά λίπος και μύες.',
                style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.35),
              ),
            ),
          if (last.water != null) InfoRow('Νερό σώματος', '${dec(last.water!)} L'),
          // 7/11: εύρη αναφοράς με πηγή (λίπος ανά ηλικία και φύλο, υγιές βάρος για το ύψος). Η εξήγηση στο «i».
          const Hairline(vertical: 12),
          // Round 1 (S11-2): καμία θέση «μέσα/πάνω από το εύρος» για ζύγιση που μοιάζει ξένη· round 4 (m1 · R4-A-4): ούτε
          // για ζύγιση «σε αναμονή» (μπορεί να είναι του παιδιού: «κάτω από το εύρος»).
          if (!foreign && !pending) ..._ranges(context),
          const SizedBox(height: 8),
          Text(
            // Round 8 (R8-A4-2): ο μεταβολισμός της ζυγαριάς είναι άλλη εκτίμηση από αυτήν των Στόχων (Mifflin-St Jeor,
            // goals_page.dart «Πώς υπολογίστηκαν οι θερμίδες»): το λέει, για να μη μοιάζει λάθος η διαφορά.
            last.bmr != null ? bodyEstimatesBmrText : 'Λίπος και μύες είναι εκτιμήσεις της ζυγαριάς· σύγκρινε ζυγίσεις με τις ίδιες συνθήκες.',
            key: const ValueKey('body-estimates-note'),
            style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.35),
          ),
        ],
      ),
    );
  }

  List<Widget> _ranges(BuildContext context) {
    final c = Aigaio.of(context);
    final fat = fatRange(profile, now);
    final weightRange = healthyWeight(profile.heightCm);
    final label = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.text);
    final out = <Widget>[];
    if (last.fatPct != null && fat != null) {
      out.addAll([
        // Round 1 (S4-6): το «i» δίπλα στην κρίση δείχνει και το εύρος με την πηγή του (Gallagher 2000).
        Row(children: [Expanded(child: Text('Λίπος', style: label)), InfoButton(K.fatPct, range: fat)]),
        RangeNote(value: last.fatPct!, range: fat, min: 5, max: 40, color: c.body),
        const SizedBox(height: 12),
      ]);
    }
    if (last.weight != null && weightRange != null) {
      final (lo, hi) = weightRange;
      final r = RefRange(
        low: lo,
        high: hi,
        // Round 7 (A4-2): τα άκρα που κρίνονται «μέσα» («60,0–80,9 kg» για 180 cm· πριν «59,9–81,0», και τα 81,0 kg «Πάνω
        // από το εύρος»).
        text: 'φυσιολογικός δείκτης για το ύψος σου: ${healthyWeightText(lo, hi)} kg',
        cite: bmiRange.cite,
      );
      out.addAll([
        Text('Βάρος', style: label),
        const SizedBox(height: 6),
        RangeNote(value: last.weight!, range: r, min: lo - 15, max: hi + 25, color: c.body),
      ]);
    }
    if (fat == null || weightRange == null) {
      out.add(Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: onProfile,
          child: const Text('Πρόσθεσε ηλικία, φύλο και ύψος για να δεις τα εύρη'),
        ),
      ));
    }
    return out;
  }
}

/// Round 9 (R9-A4-2): η μέρα της πρώτης μέτρησης μέσης στη γραμμή «−4,0 cm από …»: με έτος όταν είναι άλλης χρονιάς από
/// την τελευταία ([last]), όπως το [yearAwareLabel] των γραφημάτων.
String waistFromLabel(DateTime first, DateTime last) => first.year == last.year ? dayMonth(first) : dayMonthYear(first);

/// Round 8 (A4 Β2 / U4 Β4): «13/8», η μορφή της μέρας σε όλη την κάρτα (χάπι, σημείωση), όπως Σήμερα και widget.
String _dayNum(DateTime d) => '${d.day}/${d.month}';

/// Round 8 (R8-A4-2): η σημείωση κάτω από τη σύσταση σώματος όταν η ζυγαριά δίνει και βασικό μεταβολισμό.
const bodyEstimatesBmrText = 'Λίπος, μύες και βασικός μεταβολισμός είναι εκτιμήσεις της ζυγαριάς· σύγκρινε ζυγίσεις με τις '
    'ίδιες συνθήκες. Οι Στόχοι υπολογίζουν τον μεταβολισμό με άλλο τύπο (Mifflin-St Jeor), γι\' αυτό ο αριθμός τους μπορεί να διαφέρει.';

/// Round 7 (A4-1): κάτω από τη ζύγιση της μέρας, όταν την ίδια μέρα έγινε και άλλη, αργότερα (π.χ. το βράδυ).
String laterWeighInText(BodyMeasurement b) => 'Και ${hm(b.time)}: ${dec(b.weight!)} kg· μετρά μία ζύγιση τη μέρα, η πρώτη.';

/// Round 1 (S11-2): κάτω από μια τελευταία ζύγιση που μοιάζει ξένη (ίδια λογική με την κάρτα ελέγχου θερμίδων).
/// Round 2 (g4 · R2-E-2): τελευταία ξένη ζύγιση γίνεται μόνο όταν την ίδια μέρα υπάρχει άλλη ζύγιση με πολύ διαφορετικό
/// βάρος που μετρά (π.χ. το παιδί ζυγίστηκε μετά από σένα). Η υπόσχεση «θα μετρήσει μόλις συμφωνήσουν…» βγήκε: για ξένη
/// ζύγιση δεν ισχύει (οι γύρω ζυγίσεις ήδη δεν συμφωνούν μαζί της).
const foreignLatestText = 'Αυτή η ζύγιση διαφέρει πολύ από τις άλλες σου ζυγίσεις και δεν μετρά σε γραφήματα, τάσεις και '
    'θερμίδες. Αν δεν είναι δική σου, δεν χρειάζεται να κάνεις τίποτα.';

/// Round 2 (g4 · R2-E-2): κάτω από μια τελευταία ζύγιση «σε αναμονή» (weight_guard.dart, `WeighStatus.pending`). Μία
/// ζύγιση που συμφωνεί μαζί της αρκεί για να μετρήσει· αν η επόμενη συμφωνεί με τις παλιότερες, γίνεται «ξένη».
/// Round 3 (k1 · R3-A-1): δύο ζυγίσεις δεν αρκούν πια ([weightConfirmDays], [weightConfirmSpan] του weight_guard.dart),
/// και η «σε αναμονή» μένει έξω από κάθε υπολογισμό (πριν μόνο από τον έλεγχο θερμίδων).
const pendingLatestText = 'Διαφέρει πολύ από τις προηγούμενες ζυγίσεις σου, γι\' αυτό δεν μπαίνει ακόμα σε υπολογισμούς '
    '(θερμίδες, Τάσεις, γραφήματα). Αν είναι δική σου, θα μετρήσει μόλις το νέο βάρος φανεί σε 3 μέρες ζύγισης, με '
    'τουλάχιστον 4 μέρες από την πρώτη ως την τελευταία (π.χ. Δευτέρα, Τετάρτη, Παρασκευή). Αν δεν είναι, δεν '
    'χρειάζεται να κάνεις τίποτα: με την επόμενη ζύγισή σου θα σημειωθεί και δεν θα μετρά.';

/// Round 4 (m1 · R4-A-2): κάτω από μια τελευταία ζύγιση «σε αναμονή» επειδή την ίδια μέρα υπάρχει κι άλλη πολύ
/// διαφορετική ζύγιση και καμία άλλη ζύγιση ως 6 εβδομάδες κοντά (weight_guard.dart `guardDays`).
const mixedLatestText = 'Την ίδια μέρα υπάρχουν δύο ζυγίσεις με πολύ διαφορετικό βάρος και καμία άλλη για σύγκριση, γι\' '
    'αυτό δεν μετρά καμία ακόμα. Με την επόμενη ζύγισή σου θα μετρήσει αυτή που ταιριάζει μαζί της.';

/// Ζυγίσεις ως πίνακας (σχέδια 9/11, 9β): οι μονάδες μία φορά επάνω, η χρονιά ως διαχωριστικό («2025»), αριθμοί
/// με σταθερό πλάτος που μικραίνουν αντί να σπάνε.
class _WeighTable extends StatelessWidget {
  const _WeighTable({
    required this.body,
    required this.now,
    this.foreign = const <BodyMeasurement>{},
    this.other = const <BodyMeasurement>{},
  });
  final List<BodyMeasurement> body;
  final DateTime now;

  /// Round 1 (S11-2): ζυγίσεις που μοιάζουν ξένες: στη λίστα, σε γκρι, με σημείωση από κάτω.
  final Set<BodyMeasurement> foreign;

  /// Round 9 (R9-U4-7): άλλη ζύγιση μιας μέρας όπου μετρά ήδη μία ([otherWeighIns]): σε γκρι, με την ώρα της, και σημείωση.
  /// Πριν φαινόταν σαν κανονική («4/12 · 82,1» πάνω από «4/12 · 80,7»), ενώ η κάρτα από πάνω, τα γραφήματα και οι Τάσεις
  /// μετρούν την πρώτη (80,7).
  final Set<BodyMeasurement> other;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final head = TextStyle(fontSize: 13, height: 1.25, color: c.textSecondary);
    final numStyle = TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text, fontFeatures: tabular);
    final greyStyle = numStyle.copyWith(color: c.textTertiary);
    // Round 1 (U1a-9): κενό 8 dp αριστερά κάθε στήλης, ώστε οι επικεφαλίδες να μην κολλούν («ΒάροςΛίπος») σε μεγάλα γράμματα.
    Widget cell(String s, TextStyle st, {TextAlign align = TextAlign.right}) => Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Align(
              alignment: align == TextAlign.right ? Alignment.centerRight : Alignment.centerLeft,
              child: FittedBox(fit: BoxFit.scaleDown, child: Text(s, maxLines: 2, textAlign: align, style: st)),
            ),
          ),
        );
    final rows = <Widget>[];
    int? year = now.year;
    for (var i = 0; i < body.length; i++) {
      final b = body[i];
      if (b.time.year != year) {
        year = b.time.year;
        rows.add(Container(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.hairline))),
          child: Text('${b.time.year}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.textSecondary)),
        ));
      }
      // Round 1 (U1a-9): ίδια μορφή σε όλες τις γραμμές («24/10»)· με την ημέρα της εβδομάδας η πρώτη μίκραινε στο
      // 60–70% σε μεγάλα γράμματα (η κάρτα πάνω λέει ήδη «Σήμερα 16:13»).
      final date = '${b.time.day}/${b.time.month}';
      final isOther = !foreign.contains(b) && other.contains(b);
      final st = foreign.contains(b) || isOther ? greyStyle : numStyle;
      rows.add(Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: i < body.length - 1 ? BoxDecoration(border: Border(bottom: BorderSide(color: c.hairline))) : null,
        child: Row(children: [
          Expanded(
            flex: 4,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(foreign.contains(b) ? '$date *' : (isOther ? '$date ${hm(b.time)}' : date), maxLines: 1, style: st),
            ),
          ),
          cell(b.weight == null ? '—' : dec(b.weight!), st),
          cell(b.fatPct == null ? '—' : dec(b.fatPct!), st),
          cell(b.smm == null ? '—' : dec(b.smm!), st),
        ]),
      ));
    }
    final marked = body.any(foreign.contains);
    final markedOther = body.any((b) => !foreign.contains(b) && other.contains(b));
    return AppCard(
      key: const ValueKey('body-weighings'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHeader(icon: Icons.list_alt_rounded, title: 'Ζυγίσεις', color: c.body),
          const SizedBox(height: 8),
          Row(children: [
            const Expanded(flex: 4, child: SizedBox()),
            cell('Βάρος\nkg', head),
            cell('Λίπος\n%', head),
            cell('Μύες\nkg', head),
          ]),
          const SizedBox(height: 4),
          Divider(height: 1, color: c.hairline),
          ...rows,
          if (marked) ...[
            const SizedBox(height: 8),
            Text(
              '* Διαφέρει πολύ από τις άλλες σου ζυγίσεις: δεν μετρά σε γραφήματα, τάσεις και θερμίδες.',
              key: const ValueKey('body-weighings-foreign'),
              style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.35),
            ),
          ],
          if (markedOther) ...[
            const SizedBox(height: 8),
            Text(
              weighTableOtherText,
              key: const ValueKey('body-weighings-other'),
              style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

/// Round 9 (R9-U4-7): κάτω από τον πίνακα «Ζυγίσεις» όταν φαίνεται άλλη ζύγιση μιας μέρας που δεν μετρά ([otherWeighIns]).
const weighTableOtherText = 'Με ώρα, σε γκρι: άλλη ζύγιση της ίδιας μέρας, που δεν μετρά (μετρά μία ζύγιση τη μέρα).';

/// Round 9 (R9-U4-7): από τις [rows] του πίνακα, όσες ΔΕΝ μετρούν επειδή την ίδια μέρα μετρά άλλη ζύγιση (η ζύγιση της
/// μέρας, [shown] του [guardBody]): π.χ. η βραδινή μετά την πρωινή. Όχι οι ξένες ([foreign], έχουν δικό τους σημάδι) ούτε
/// οι «σε αναμονή» ([pending]: όλη η μέρα περιμένει, το λέει η κάρτα από πάνω), ούτε ζυγίσεις χωρίς βάρος.
Set<BodyMeasurement> otherWeighIns(
  Iterable<BodyMeasurement> rows, {
  required List<BodyMeasurement> shown,
  required Set<BodyMeasurement> foreign,
  required Set<BodyMeasurement> pending,
}) {
  final pick = <DateTime, BodyMeasurement>{for (final s in shown) dayOf(s.time): s};
  final out = Set<BodyMeasurement>.identity();
  for (final b in rows) {
    if (b.weight == null || foreign.contains(b) || pending.contains(b)) continue;
    final p = pick[dayOf(b.time)];
    if (p != null && !identical(p, b)) out.add(b);
  }
  return out;
}

/// Μέση με μεζούρα (σχέδια 12/11): η τελευταία τιμή, η αλλαγή από την πρώτη, το εύρος αναφοράς (ESC 2021) και η πορεία.
/// Πιο χρήσιμη από τη ζυγαριά για το λίπος της κοιλιάς· αλλάζει αργά, γι’ αυτό μία φορά την εβδομάδα.
class _WaistCard extends StatelessWidget {
  const _WaistCard({required this.store});
  final HealthStore store;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final list = store.waist;
    final p = store.profile;
    final ref = waistRef(!p.female);
    final last = list.isEmpty ? null : list.last;
    final first = list.length >= 2 ? list.first : null;
    DateTime day(String s) => DateTime.parse(s);
    final small = TextStyle(fontSize: 13.5, height: 1.4, color: c.textSecondary);
    return AppCard(
      key: const ValueKey('body-waist'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardHeader(icon: Icons.straighten_rounded, title: 'Μέση με μεζούρα', color: c.body),
        const SizedBox(height: 10),
        if (last == null)
          Text('Μέτρησε τη μέση σου μία φορά την εβδομάδα (${weekdayNames[p.waistDay - 1]}). Δείχνει το λίπος της κοιλιάς '
              'καλύτερα από τη ζυγαριά.', style: small)
        else ...[
          BigValue(dec(last.cm), unit: 'cm', size: 36),
          const SizedBox(height: 4),
          Text(
            [
              dayMonthYear(day(last.day)),
              // Round 9 (R9-A4-2): η πρώτη μέτρηση με το έτος της όταν είναι άλλης χρονιάς («−4,0 cm από 16 Νοε 2026» δίπλα
              // σε «20 Νοε 2027»)· πριν «από 16 Νοε», που διαβαζόταν σαν πριν από 4 μέρες.
              if (first != null) '${signedDec(shownDiff(last.cm, first.cm, 1))} cm από ${waistFromLabel(day(first.day), day(last.day))}',
            ].join(' · '),
            style: small,
          ),
          if (p.male || p.female)
            Text('Εύρος αναφοράς: κάτω από ${dec(ref.ok, 0)} cm (ESC 2021)', style: small),
          if (list.length >= 2) ...[
            const SizedBox(height: 12),
            LineChart(
              points: [for (final e in list) (day(e.day), e.cm)],
              color: c.body,
              format: (v) => dec(v),
              // Round 7 (A4 · B2): ελάχιστο εύρος άξονα 3 cm, όπως βάρος και λίπος: αλλαγή 1 cm (όσο διαφέρουν δύο μετρήσεις
              // της ίδιας μέρας, [waistSpreadCm]) γέμιζε όλο το γράφημα.
              minRange: 3,
              dateLabel: yearAwareLabel([for (final e in list) (day(e.day), e.cm)]),
            ),
          ],
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('body-waist-add'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), foregroundColor: c.body),
          onPressed: () => openWaistSheet(context, store),
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('Γράψε τη μέση'),
        ),
      ]),
    );
  }
}
