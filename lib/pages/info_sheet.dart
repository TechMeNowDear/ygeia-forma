import 'package:flutter/material.dart';

import '../reference.dart';
import '../theme.dart';

/// Το «i» δίπλα σε μια μέτρηση (απόφαση 7/11): η εξήγηση δεν φαίνεται στη σελίδα· ανοίγει σε φύλλο από κάτω.
class InfoButton extends StatelessWidget {
  const InfoButton(this.metric, {super.key, this.range});

  /// Το κλειδί της μέτρησης (K.*) στο [metricInfos].
  final String metric;

  /// Το εύρος αναφοράς για αυτόν τον χρήστη, αν υπάρχει (δείχνεται μέσα στο φύλλο).
  final RefRange? range;

  @override
  Widget build(BuildContext context) {
    final info = metricInfos[metric];
    if (info == null) return const SizedBox.shrink();
    final c = Aigaio.of(context);
    return Semantics(
      button: true,
      label: 'Τι είναι: ${info.title}',
      child: InkResponse(
        key: ValueKey('info-$metric'),
        radius: 22,
        onTap: () => showMetricInfo(context, info, range: range),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: c.hairline),
                color: c.card,
              ),
              alignment: Alignment.center,
              child: Text('i',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, fontStyle: FontStyle.italic, color: c.textSecondary)),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showMetricInfo(BuildContext context, MetricInfo info, {RefRange? range}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    routeSettings: const RouteSettings(name: 'Εξήγηση'),
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) {
      final c = Aigaio.of(context);
      final body = TextStyle(fontSize: 15, height: 1.5, color: c.text);
      final head = TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text);
      Widget block(String title, String text) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(title, style: head), const SizedBox(height: 4), Text(text, style: body)],
          );
      Widget pill(String title, String text, Color color) => Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: c.tint(color), borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.text)),
                  const SizedBox(height: 3),
                  Text(text, style: TextStyle(fontSize: 13, height: 1.4, color: c.text)),
                ],
              ),
            ),
          );
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(info.title,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.2, color: c.text, letterSpacing: -0.2)),
              const SizedBox(height: 16),
              block('Τι είναι', info.what),
              const SizedBox(height: 14),
              block('Τι δείχνει', info.shows),
              if (info.up != null || info.down != null) ...[
                const SizedBox(height: 14),
                Text('Πώς το διαβάζεις', style: head),
                const SizedBox(height: 6),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (info.up != null) pill('Πάνω', info.up!, c.energy),
                      if (info.up != null && info.down != null) const SizedBox(width: 8),
                      if (info.down != null) pill('Κάτω', info.down!, c.move),
                    ],
                  ),
                ),
              ],
              if (range != null) ...[
                const SizedBox(height: 14),
                block('Εύρος αναφοράς', '${_cap(range.text)}. Πηγή: ${range.cite}.'),
              ] else if (info.compare != null) ...[
                const SizedBox(height: 14),
                block('Με τι το συγκρίνεις', info.compare!),
              ],
              const SizedBox(height: 14),
              block('Πόσο ακριβές είναι', info.accuracy),
              if (info.cite != null) ...[
                const SizedBox(height: 10),
                Text(info.cite!, style: TextStyle(fontSize: 12.5, color: c.textSecondary, height: 1.4)),
              ],
              const SizedBox(height: 18),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Κατάλαβα'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// Μπάρα εύρους: η ζώνη του εύρους αναφοράς και ένα σημάδι στην τιμή. Ουδέτερα χρώματα (όχι «κόκκινο»).
/// [min], [max]: τα άκρα της κλίμακας.
class RangeBar extends StatelessWidget {
  const RangeBar({super.key, required this.value, required this.range, required this.min, required this.max, required this.color});
  final double value;
  final RefRange range;
  final double min;
  final double max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    double pos(double v) => ((v - min) / (max - min)).clamp(0.0, 1.0);
    final a = pos(range.low ?? min);
    final b = pos(range.high ?? max);
    final v = pos(value);
    return Semantics(
      label: 'Εύρος ${range.text}· η τιμή σου είναι ${range.placeText(value)}',
      child: SizedBox(
        height: 18,
        child: LayoutBuilder(builder: (context, k) {
          final w = k.maxWidth;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 6,
                height: 6,
                child: DecoratedBox(decoration: BoxDecoration(color: c.hairline, borderRadius: BorderRadius.circular(3))),
              ),
              Positioned(
                left: a * w,
                width: (b - a) * w,
                top: 6,
                height: 6,
                child: DecoratedBox(decoration: BoxDecoration(color: c.tint(color), borderRadius: BorderRadius.circular(3))),
              ),
              Positioned(
                left: v * w - 7,
                top: 2,
                width: 14,
                height: 14,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: c.text, shape: BoxShape.circle, border: Border.all(color: c.card, width: 2)),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

/// Μία γραμμή κάτω από την τιμή: πού βρίσκεται σε σχέση με το εύρος, με την πηγή σε μικρά γράμματα.
class RangeNote extends StatelessWidget {
  const RangeNote({super.key, required this.value, required this.range, required this.min, required this.max, required this.color, this.oneNight = false});
  final double value;

  /// Τιμή μίας νύχτας (έλεγχος 9/11, 04-M5 / V-B-15): το εύρος αφορά τον μέσο όρο πολλών νυχτών· λέγεται ρητά.
  final bool oneNight;
  final RefRange range;
  final double min;
  final double max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RangeBar(value: value, range: range, min: min, max: max, color: color),
        const SizedBox(height: 6),
        Text('${oneNight ? 'Μία νύχτα: ${range.placeText(value)}' : _cap(range.placeText(value))} · ${range.text}'
            '${oneNight ? '. Μετρά ο μέσος όρος πολλών νυχτών.' : ''}',
            style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.35)),
      ],
    );
  }
}
