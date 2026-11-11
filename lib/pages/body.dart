import 'package:flutter/material.dart';

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
  const BodyPage({super.key, required this.store});
  final HealthStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final c = Aigaio.of(context);
        final d = store.data;
        final body = d?.body ?? const <BodyMeasurement>[];
        final last = d?.latestBody;

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
              previous: d?.previousBody,
              now: d?.readAt ?? DateTime.now(),
              profile: store.profile,
              onProfile: () => Navigator.of(context).push(MePage.route(store)),
            ),
          if (body.where((b) => b.weight != null).length >= 2)
            _chartCard(
              context,
              K.weight,
              'Βάρος (kg)',
              [for (final b in body) if (b.weight != null) (b.time, b.weight!)],
              c.body,
            ),
          _WaistCard(store: store),
          if (body.where((b) => b.fatPct != null).length >= 2)
            _chartCard(
              context,
              K.fatPct,
              'Λίπος (%)',
              [for (final b in body) if (b.fatPct != null) (b.time, b.fatPct!)],
              c.heart,
            ),
        ];

        final bodyMore = <Widget>[
          if (body.where((b) => b.smm != null).length >= 2)
            _chartCard(
              context,
              K.smm,
              'Σκελετικοί μύες (kg)',
              [for (final b in body) if (b.smm != null) (b.time, b.smm!)],
              c.energy,
            ),
          if (body.isNotEmpty) _WeighTable(body: body.reversed.take(12).toList(), now: d?.readAt ?? DateTime.now()),
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

  Widget _chartCard(BuildContext context, String metric, String title, List<(DateTime, double)> points, Color color) {
    return AppCard(
      key: ValueKey('body-$metric'),
      onTap: () => Navigator.of(context).push(MetricPage.route(store, metric)),
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
          LineChart(points: points, color: color, format: (v) => dec(v), dateLabel: dayMonth),
        ],
      ),
    );
  }
}

class _LatestCard extends StatelessWidget {
  const _LatestCard({required this.last, required this.previous, required this.now, required this.profile, required this.onProfile});
  final BodyMeasurement last;
  final BodyMeasurement? previous;
  final DateTime now;
  final Profile profile;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final p = previous;

    String withDiff(double? value, double? before, String unit, {int digits = 1, bool lowerIsBetter = true}) {
      if (value == null) return '—';
      final base = '${dec(value, digits)} $unit';
      if (before == null) return base;
      // Η διαφορά των νούμερων όπως φαίνονται (τρίτος έλεγχος F3): 82,2 και 83,4 → «−1,2».
      final diff = shownDiff(value, before, digits);
      if (diff == 0) return base;
      return '$base  (${signedDec(diff, digits)})';
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHeader(
            icon: Icons.monitor_weight_rounded,
            title: 'Τελευταία ζύγιση',
            subtitle: '${relativeDay(last.time, now)} ${hm(last.time)}',
            color: c.body,
            trailing: const InfoButton(K.weight),
          ),
          const SizedBox(height: 14),
          BigValue(last.weight == null ? '—' : dec(last.weight!), unit: 'kg', size: 44),
          if (p != null && last.weight != null && p.weight != null && shownDiff(last.weight!, p.weight!, 1) != 0) ...[
            const SizedBox(height: 6),
            // Σχέδια 9/11 (Spec): αλλαγή χωρίς κρίση, σε γκρι.
            Align(
              alignment: Alignment.centerLeft,
              child: TrendPill('${signedDec(shownDiff(last.weight!, p.weight!, 1))} kg από ${p.time.day}/${p.time.month}'),
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
          if (p != null)
            Text('Σε παρένθεση η αλλαγή από τις ${dayMonth(p.time)}.', style: TextStyle(color: c.textSecondary, fontSize: 13)),
          const SizedBox(height: 4),
          InfoRow('Βάρος', withDiff(last.weight, p?.weight, 'kg')),
          InfoRow('Λίπος', withDiff(last.fatPct, p?.fatPct, '%')),
          InfoRow('Μάζα λίπους', withDiff(last.fatKg, p?.fatKg, 'kg')),
          InfoRow('Σκελετικοί μύες', withDiff(last.smm, p?.smm, 'kg')),
          InfoRow('Άλιπη μάζα', withDiff(last.leanMass, p?.leanMass, 'kg')),
          if (last.bmr != null) InfoRow('Βασικός μεταβολισμός (εκτίμηση, ±10%)', '${thousands(last.bmr!)} kcal'),
          // Ένα ύψος για όλα (έλεγχος 8/11, DATA-08): από τα στοιχεία σου· της InBody μόνο αν δεν έχεις δώσει ύψος.
          if (bmiOf(last.weight, profile.heightCm) ?? last.bmi case final bmi?) InfoRow('Δείκτης μάζας σώματος', dec(bmi)),
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
          ..._ranges(context),
          const SizedBox(height: 8),
          Text(
            'Λίπος και μύες είναι εκτιμήσεις της ζυγαριάς· σύγκρινε ζυγίσεις με τις ίδιες συνθήκες.',
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
        Row(children: [Expanded(child: Text('Λίπος', style: label)), const InfoButton(K.fatPct)]),
        RangeNote(value: last.fatPct!, range: fat, min: 5, max: 40, color: c.body),
        const SizedBox(height: 12),
      ]);
    }
    if (last.weight != null && weightRange != null) {
      final (lo, hi) = weightRange;
      final r = RefRange(
        low: lo,
        high: hi,
        text: 'φυσιολογικός δείκτης για το ύψος σου: ${dec(lo)}–${dec(hi)} kg',
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

/// Ζυγίσεις ως πίνακας (σχέδια 9/11, 9β): οι μονάδες μία φορά επάνω, η χρονιά ως διαχωριστικό («2025»), αριθμοί
/// με σταθερό πλάτος που μικραίνουν αντί να σπάνε.
class _WeighTable extends StatelessWidget {
  const _WeighTable({required this.body, required this.now});
  final List<BodyMeasurement> body;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final head = TextStyle(fontSize: 13, height: 1.25, color: c.textSecondary);
    final numStyle = TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text, fontFeatures: tabular);
    Widget cell(String s, TextStyle st, {TextAlign align = TextAlign.right}) => Expanded(
          flex: 3,
          child: Align(
            alignment: align == TextAlign.right ? Alignment.centerRight : Alignment.centerLeft,
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(s, maxLines: 2, textAlign: align, style: st)),
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
      final date = i == 0 && b.time.year == now.year ? shortDayDate(b.time) : '${b.time.day}/${b.time.month}';
      rows.add(Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: i < body.length - 1 ? BoxDecoration(border: Border(bottom: BorderSide(color: c.hairline))) : null,
        child: Row(children: [
          Expanded(
            flex: 4,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(date, maxLines: 1, style: numStyle),
            ),
          ),
          cell(b.weight == null ? '—' : dec(b.weight!), numStyle),
          cell(b.fatPct == null ? '—' : dec(b.fatPct!), numStyle),
          cell(b.smm == null ? '—' : dec(b.smm!), numStyle),
        ]),
      ));
    }
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
        ],
      ),
    );
  }
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
              if (first != null) '${signedDec(shownDiff(last.cm, first.cm, 1))} cm από ${dayMonth(day(first.day))}',
            ].join(' · '),
            style: small,
          ),
          if (p.male || p.female)
            Text('Εύρος αναφοράς: κάτω από ${dec(ref.ok, 0)} cm (ESC 2021)', style: small),
          if (list.length >= 2) ...[
            const SizedBox(height: 12),
            LineChart(points: [for (final e in list) (day(e.day), e.cm)], color: c.body, format: (v) => dec(v), dateLabel: dayMonth),
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
