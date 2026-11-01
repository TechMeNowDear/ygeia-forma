import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';

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
            _LatestCard(last: last, previous: d?.previousBody, now: d?.readAt ?? DateTime.now()),
          if (body.where((b) => b.weight != null).length >= 2)
            _chartCard(
              context,
              'Βάρος (kg)',
              [for (final b in body) if (b.weight != null) (b.time, b.weight!)],
              c.body,
            ),
          if (body.where((b) => b.fatPct != null).length >= 2)
            _chartCard(
              context,
              'Λίπος (%)',
              [for (final b in body) if (b.fatPct != null) (b.time, b.fatPct!)],
              c.heart,
            ),
        ];

        final bodyMore = <Widget>[
          if (body.where((b) => b.smm != null).length >= 2)
            _chartCard(
              context,
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
          if (skinNights.length >= 2)
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CardHeader(icon: Icons.thermostat_rounded, title: 'Θερμοκρασία καρπού στον ύπνο', color: c.move),
                  const SizedBox(height: 10),
                  Text(
                    skinBase == null
                        ? 'Χρειάζονται λίγες ακόμα νύχτες για τον μέσο όρο σου.'
                        : 'Ο μέσος όρος σου είναι ${dec(skinBase)} °C. Αλλάζει πολύ με τη θερμοκρασία του δωματίου, τα σκεπάσματα '
                            'και το λουράκι. Δείχνει μόνο τι άλλαξε σε σχέση με εσένα· δεν είναι θερμοκρασία σώματος ούτε πυρετός.',
                    style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  LineChart(
                    points: [
                      for (final n in skinNights.length <= 30 ? skinNights : skinNights.sublist(skinNights.length - 30))
                        (n.date, n.skinTemp!),
                    ],
                    format: (v) => dec(v),
                    color: c.move,
                  ),
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

  Widget _chartCard(BuildContext context, String title, List<(DateTime, double)> points, Color color) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHeader(icon: Icons.show_chart_rounded, title: title, color: color),
          const SizedBox(height: 12),
          LineChart(points: points, color: color, format: (v) => dec(v), dateLabel: dayMonth),
        ],
      ),
    );
  }
}

class _LatestCard extends StatelessWidget {
  const _LatestCard({required this.last, required this.previous, required this.now});
  final BodyMeasurement last;
  final BodyMeasurement? previous;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final p = previous;

    String withDiff(double? value, double? before, String unit, {int digits = 1, bool lowerIsBetter = true}) {
      if (value == null) return '—';
      final base = '${dec(value, digits)} $unit';
      if (before == null) return base;
      final diff = value - before;
      if (diff.abs() < 0.05) return base;
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
          ),
          const SizedBox(height: 14),
          BigValue(last.weight == null ? '—' : dec(last.weight!), unit: 'kg', size: 34),
          if (p != null) ...[
            const SizedBox(height: 4),
            Text(
              'Σε παρένθεση η αλλαγή από τις ${dayMonth(p.time)}. Η ζυγαριά (ρεύμα στο σώμα) αλλάζει από μέρα σε μέρα '
              'με το νερό και το φαγητό: αλλαγή κάτω από 1 kg ή 1% δεν σημαίνει κάτι.',
              style: TextStyle(color: c.textSecondary, fontSize: 13),
            ),
          ],
          const Hairline(vertical: 12),
          InfoRow('Βάρος', withDiff(last.weight, p?.weight, 'kg')),
          InfoRow('Λίπος', withDiff(last.fatPct, p?.fatPct, '%')),
          InfoRow('Μάζα λίπους', withDiff(last.fatKg, p?.fatKg, 'kg')),
          InfoRow('Σκελετικοί μύες', withDiff(last.smm, p?.smm, 'kg')),
          InfoRow('Άλιπη μάζα', withDiff(last.leanMass, p?.leanMass, 'kg')),
          if (last.bmr != null) InfoRow('Βασικός μεταβολισμός (εκτίμηση)', '${thousands(last.bmr!)} kcal'),
          if (last.bmi != null) InfoRow('Δείκτης μάζας σώματος', dec(last.bmi!)),
          if (last.water != null) InfoRow('Νερό σώματος', '${dec(last.water!)} L'),
          const SizedBox(height: 8),
          // Απόφαση 2/11: ό,τι δεν είναι ζύγισμα κιλών το λέμε εκτίμηση, και πώς γίνεται συγκρίσιμη.
          Text(
            'Λίπος, μύες, άλιπη μάζα και μεταβολισμός είναι εκτιμήσεις της ζυγαριάς, όχι μέτρηση εργαστηρίου: '
            'η τιμή μπορεί να απέχει μερικές μονάδες από την πραγματική. Η αλλαγή μέσα σε εβδομάδες λέει περισσότερα '
            'από την ίδια την τιμή, αν ζυγίζεσαι πάντα με τον ίδιο τρόπο: πρωί, πριν φας ή πιεις, μετά την τουαλέτα '
            'και πριν από την άσκηση.',
            style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.35),
          ),
        ],
      ),
    );
  }
}
