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
          if (body.isNotEmpty)
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CardHeader(icon: Icons.list_alt_rounded, title: 'Ζυγίσεις', color: c.body),
                  const SizedBox(height: 8),
                  for (final b in body.reversed.take(12))
                    InfoRow(
                      dayMonthYear(b.time),
                      [
                        if (b.weight != null) '${dec(b.weight!)} kg',
                        if (b.fatPct != null) '${dec(b.fatPct!)}%',
                        if (b.smm != null) 'μύες ${dec(b.smm!)}',
                      ].join(' · '),
                    ),
                ],
              ),
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
            title: 'Τελευταία ζύγιση · ${relativeDay(last.time, now)} ${hm(last.time)}',
            color: c.body,
            trailing: const InfoButton(K.weight),
          ),
          const SizedBox(height: 14),
          BigValue(last.weight == null ? '—' : dec(last.weight!), unit: 'kg', size: 34),
          if (p != null) ...[
            const SizedBox(height: 4),
            Text(
              'Σε παρένθεση η αλλαγή από τις ${dayMonth(p.time)}.',
              style: TextStyle(color: c.textSecondary, fontSize: 13),
            ),
          ],
          const Hairline(vertical: 12),
          InfoRow('Βάρος', withDiff(last.weight, p?.weight, 'kg')),
          InfoRow('Λίπος', withDiff(last.fatPct, p?.fatPct, '%')),
          InfoRow('Μάζα λίπους', withDiff(last.fatKg, p?.fatKg, 'kg')),
          InfoRow('Σκελετικοί μύες', withDiff(last.smm, p?.smm, 'kg')),
          InfoRow('Άλιπη μάζα', withDiff(last.leanMass, p?.leanMass, 'kg')),
          if (last.bmr != null) InfoRow('Βασικός μεταβολισμός (εκτίμηση, ±10%)', '${thousands(last.bmr!)} kcal'),
          if (last.bmi != null) InfoRow('Δείκτης μάζας σώματος', dec(last.bmi!)),
          if (last.bmi == null && bmiOf(last.weight, profile.heightCm) != null)
            InfoRow('Δείκτης μάζας σώματος', dec(bmiOf(last.weight, profile.heightCm)!)),
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
        text: 'υγιές βάρος για το ύψος σου ${dec(lo)}–${dec(hi)} kg',
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
