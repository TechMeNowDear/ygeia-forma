import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../history.dart';
import '../oura/oura_view.dart';
import '../shown.dart';
import '../sources.dart';
import '../theme.dart';
import '../widgets.dart';
import 'info_sheet.dart';
import 'source_widgets.dart';

/// Υγεία › Ανάκαμψη (7/11): πόσο ξεκουράστηκες. Ετοιμότητα, HRV, θερμοκρασία της νύχτας — όλα από το Oura, όλα
/// σε σύγκριση μόνο με τα δικά σου συνηθισμένα. Κάθε κάρτα: τιμή, «συνήθως», γράφημα 30 νυχτών και «i».
class RecoveryPage extends StatelessWidget {
  const RecoveryPage({super.key, required this.store, this.now});
  final HealthStore store;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final c = Aigaio.of(context);
        final today = dayOf(now ?? DateTime.now());
        final plan = store.plan;
        if (plan.nightSource(today) != Source.oura) {
          return PageFrame(
            title: 'Ανάκαμψη',
            subtitle: 'Από το Oura',
            onRefresh: () => store.refresh(),
            left: [
              EmptyCard(
                icon: Icons.self_improvement_rounded,
                color: c.energy,
                title: 'Η ανάκαμψη έρχεται από το δαχτυλίδι',
                text: 'Ετοιμότητα, HRV και θερμοκρασία της νύχτας φαίνονται όσο ο ύπνος έρχεται από το Oura.',
              ),
            ],
          );
        }
        final day = store.lastOuraNight?.day ?? today;
        final from = DateTime(day.year, day.month, day.day - 29);

        Widget card({
          required String metric,
          required IconData icon,
          required Color color,
          required String title,
          required String Function(double v) show,
          required String unit,
          required String Function(double diff) diffText,
          int digits = 0,
          double minRange = 10,
          String? note,
        }) {
          final b = ouraBaseline(store.history, plan, metric, day);
          final pts = planSeries(store.history, plan, metric, from, day).points;
          String? usual;
          if (b?.usual != null) {
            final d = shownDiff(b!.value, b.usual!, digits);
            usual = d == 0 ? '$asUsualText · συνήθως ${show(b.usual!)}' : '${diffText(d)} · συνήθως ${show(b.usual!)}';
          } else if (b != null) {
            usual = 'Το συνηθισμένο σου βγαίνει μετά από $minNightsForBaseline νύχτες';
          }
          return AppCard(
            key: ValueKey('recovery-$metric'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CardHeader(
                  icon: icon,
                  title: title,
                  subtitle: b == null ? null : shortDayDate(day),
                  color: color,
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [const SourceTag(Source.oura), InfoButton(metric)]),
                ),
                const SizedBox(height: 10),
                BigValue(b == null ? '—' : show(b.value), unit: unit, size: 34),
                if (usual != null) ...[
                  const SizedBox(height: 6),
                  Text(usual, style: TextStyle(color: c.textSecondary, fontSize: 13.5)),
                ],
                if (b == null) ...[
                  const SizedBox(height: 6),
                  Text('Δεν ήρθε για αυτή τη νύχτα.', style: TextStyle(color: c.textSecondary, fontSize: 13.5)),
                ],
                if (note != null) ...[
                  const SizedBox(height: 6),
                  Text(note, style: TextStyle(color: c.textTertiary, fontSize: 12.5, height: 1.35)),
                ],
                if (pts.length >= 2) ...[
                  const SizedBox(height: 14),
                  LineChart(points: pts, color: color, format: show, minRange: minRange, dateLabel: dayMonth),
                ],
              ],
            ),
          );
        }

        final readiness = card(
          metric: K.energy,
          icon: Icons.bolt_rounded,
          color: c.energy,
          title: 'Ετοιμότητα',
          show: (v) => '${v.round()}',
          unit: '/100',
          diffText: (d) => signedShown(d),
          note: 'Εκτίμηση του Oura, όχι μέτρηση.',
        );
        final hrv = card(
          metric: K.hrv,
          icon: Icons.timeline_rounded,
          color: c.sleep,
          title: 'HRV',
          show: (v) => '${v.round()}',
          unit: 'ms',
          diffText: (d) => '${signedShown(d)} ms',
        );
        final temp = card(
          metric: K.skinTemp,
          icon: Icons.thermostat_rounded,
          color: c.move,
          title: 'Θερμοκρασία στον ύπνο',
          show: (v) => signedDec(v),
          unit: '°C',
          diffText: (d) => '${signedDec(d)} °C',
          digits: 1,
          minRange: 1,
          note: 'Απόκλιση από τα συνηθισμένα σου, όχι θερμοκρασία σώματος.',
        );

        return PageFrame(
          title: 'Ανάκαμψη',
          subtitle: 'Πόσο ξεκουράστηκες · από το Oura',
          onRefresh: () => store.refresh(),
          left: [readiness, hrv],
          right: [temp],
        );
      },
    );
  }
}
