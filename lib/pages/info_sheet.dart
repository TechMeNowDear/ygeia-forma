import 'package:flutter/material.dart';

import '../history.dart' show K;
import '../reference.dart';
import '../theme.dart';
import 'devices_page.dart';

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
        radius: 24,
        onTap: () => showMetricInfo(context, info, range: range, device: deviceOf(metric)),
        // Round 1 (U1a-21): στόχος αφής 48 dp (πριν 44), ίδιο σημάδι 26 dp.
        child: SizedBox(
          width: 48,
          height: 48,
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
              // R7-U4-11: το «i» μόνο φαίνεται· το TalkBack λέει «Τι είναι: …» (πριν «Τι είναι: HRV, i»). Το πάτημα μένει.
              // Round 8 (R8-U4-6): το «i» είναι σήμα, όχι κείμενο: δεν μεγαλώνει με τα γράμματα του κινητού (στο 2× ήταν 28 px
              // μέσα σε κύκλο 26 και κοβόταν). Ο στόχος αφής μένει 48 dp.
              child: ExcludeSemantics(
                child: Text('i',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, fontStyle: FontStyle.italic, color: c.textSecondary)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ποια ενότητα του «Τι μετράει κάθε συσκευή» αφορά μια μέτρηση.
String deviceOf(String metric) => switch (metric) {
      K.weight || K.fatPct || K.smm => 'inbody',
      K.steps || K.dayHr => 'watch',
      K.ringSpo2 => 'oxygen',
      _ => 'oura',
    };

Future<void> showMetricInfo(BuildContext context, MetricInfo info, {RefRange? range, String? device}) {
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
              decoration: BoxDecoration(color: c.tint(color), borderRadius: BorderRadius.circular(16)),
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
              // Round 1 (S4-7): και τα δύο όταν υπάρχουν (πριν, με εύρος δεν φαινόταν ποτέ το «Με τι το συγκρίνεις», π.χ. η
              // σημείωση των αναπνοών ότι το εύρος μετρήθηκε στον βαθύ ύπνο και η σύγκριση είναι ενδεικτική).
              if (range != null) ...[
                const SizedBox(height: 14),
                block('Εύρος αναφοράς', '${_cap(range.text)}. Πηγή: ${range.cite}.'),
              ],
              if (info.compare != null) ...[
                const SizedBox(height: 14),
                block('Με τι το συγκρίνεις', info.compare!),
              ],
              const SizedBox(height: 14),
              block('Πόσο ακριβές είναι', info.accuracy),
              if (info.cite != null) ...[
                const SizedBox(height: 10),
                Text(info.cite!, style: TextStyle(fontSize: 12.5, color: c.textSecondary, height: 1.4)),
              ],
              if (device != null) ...[
                const SizedBox(height: 8),
                // Σχέδια 9/11 (4α): οι εξηγήσεις όλων των συσκευών σε μία σελίδα, στο σωστό σημείο.
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const ValueKey('info-devices'),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () {
                      final nav = Navigator.of(context);
                      nav.pop();
                      nav.push(DevicesPage.route(focus: device));
                    },
                    child: const Text('Τι μετράει κάθε συσκευή ›'),
                  ),
                ),
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
                // Round 1 (U1a-16 = U2a-18): η ζώνη ≥ 3:1 απέναντι στη γραμμή σε όλα τα θέματα (υπολογισμός f4/zone.py:
                // 3,16–5,70)· πριν η απαλή απόχρωση έδινε 1,16:1 και η ζώνη δεν φαινόταν.
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: c.dark ? 0.65 : 0.85),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
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
        Text('${oneNight ? 'Μία νύχτα: ${range.placeText(value)}' : _cap(range.placeText(value))} ·\u00A0${range.text}'
            '${oneNight ? '. Μετρά ο μέσος όρος πολλών νυχτών.' : ''}',
            style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.35)),
      ],
    );
  }
}

/// Το ίδιο «i», για εξηγήσεις που δεν είναι μέτρηση του [metricInfos] (ζώνη, στόχοι, χοληστερίνη, 12/11).
class InfoDot extends StatelessWidget {
  const InfoDot(this.info, {super.key});
  final MetricInfo info;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Semantics(
      button: true,
      label: 'Τι είναι: ${info.title}',
      child: InkResponse(
        radius: 24,
        onTap: () => showMetricInfo(context, info),
        // Round 1 (U1a-21): στόχος αφής 48 dp.
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.hairline), color: c.card),
              alignment: Alignment.center,
              // R7-U4-11: όπως στο [InfoButton], χωρίς «i» στην ετικέτα του TalkBack.
              // Round 8 (R8-U4-6): όπως στο [InfoButton], το «i» δεν μεγαλώνει με τα γράμματα (κοβόταν μέσα στον κύκλο).
              child: ExcludeSemantics(
                child: Text('i',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, fontStyle: FontStyle.italic, color: c.textSecondary)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
