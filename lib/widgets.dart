import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'data.dart';
import 'theme.dart';

// ---------------------------------------------------------------------------
// Διάταξη σελίδας: μία στήλη στο κινητό, δύο σε ανοιχτό Fold / tablet,
// ποτέ τεντωμένη (μέγιστο πλάτος).
// ---------------------------------------------------------------------------

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    required this.onRefresh,
    required this.left,
    this.right = const [],
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final Future<void> Function() onRefresh;
  final List<Widget> left;
  final List<Widget> right;

  static const gap = 12.0;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const side = 16.0;
          final width = math.min(constraints.maxWidth - side * 2, 1100.0);
          final twoColumns = width >= 700 && right.isNotEmpty;

          Widget column(List<Widget> items) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const SizedBox(height: gap),
                    items[i],
                  ],
                ],
              );

          final header = Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: c.text),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(subtitle!, style: TextStyle(fontSize: 15, color: c.textSecondary)),
                        ),
                    ],
                  ),
                ),
                if (action != null) action!,
              ],
            ),
          );

          final body = twoColumns
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: column(left)),
                    const SizedBox(width: gap),
                    Expanded(child: column(right)),
                  ],
                )
              : column([...left, ...right]);

          return RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(side, 20, side, 120),
              children: [
                Center(
                  child: SizedBox(
                    width: width,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [header, body],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Δύο κάρτες δίπλα δίπλα (π.χ. μικρές κάρτες στο «Σήμερα»).
class CardPair extends StatelessWidget {
  const CardPair({super.key, required this.first, this.second});

  final Widget first;
  final Widget? second;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: first),
          const SizedBox(width: PageFrame.gap),
          Expanded(child: second ?? const SizedBox()),
        ],
      ),
    );
  }
}

/// Βάζει τις μικρές κάρτες ανά δύο.
List<Widget> pairUp(List<Widget> cards) => [
      for (var i = 0; i < cards.length; i += 2)
        CardPair(first: cards[i], second: i + 1 < cards.length ? cards[i + 1] : null),
    ];

// ---------------------------------------------------------------------------
// Κάρτες
// ---------------------------------------------------------------------------

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.onTap});

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Material(
      color: c.card,
      elevation: 0,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: Theme.of(context).brightness == Brightness.light
                ? const [BoxShadow(color: Color(0x0F0F172A), blurRadius: 16, offset: Offset(0, 4))]
                : null,
          ),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// Μικρή κάρτα με τίτλο, μεγάλη τιμή και μια γραμμή σύγκρισης.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.title,
    required this.value,
    this.unit,
    this.note,
    this.noteColor,
    this.leading,
    this.empty,
    this.onTap,
  });

  final String title;
  final String? value;
  final String? unit;
  final String? note;
  final Color? noteColor;
  final Widget? leading;
  final String? empty;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          if (value == null)
            Text(empty ?? 'Δεν υπάρχουν δεδομένα ακόμα', style: TextStyle(color: c.textSecondary))
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 10)],
                Flexible(
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: value,
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: c.text),
                        ),
                        if (unit != null)
                          TextSpan(
                            text: ' $unit',
                            style: TextStyle(fontSize: 14, color: c.textSecondary, fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          if (note != null && value != null) ...[
            const SizedBox(height: 6),
            Text(note!, style: TextStyle(color: noteColor ?? c.textSecondary, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Text(text, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text));
  }
}

/// Γραμμή «όνομα ........ τιμή».
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: c.textSecondary, fontSize: 15))),
          Text(
            value,
            style: TextStyle(color: valueColor ?? c.text, fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Κύκλος προόδου (βαθμολογία 0–100)
// ---------------------------------------------------------------------------

class ScoreRing extends StatelessWidget {
  const ScoreRing({
    super.key,
    required this.value,
    this.size = 56,
    this.stroke = 6,
    required this.color,
    required this.track,
    this.textColor,
  });

  final double? value;
  final double size;
  final double stroke;
  final Color color;
  final Color track;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter((value ?? 0) / 100, stroke, color, track),
        child: Center(
          child: Text(
            value == null ? '—' : value!.round().toString(),
            style: TextStyle(
              fontSize: size * 0.32,
              fontWeight: FontWeight.w700,
              color: textColor ?? color,
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.fraction, this.stroke, this.color, this.track);
  final double fraction;
  final double stroke;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(r, 0, math.pi * 2, false, base);
    final f = fraction.clamp(0.0, 1.0);
    if (f > 0) {
      canvas.drawArc(r, -math.pi / 2, math.pi * 2 * f, false, base..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.color != color || old.track != track;
}

// ---------------------------------------------------------------------------
// Φάσεις ύπνου
// ---------------------------------------------------------------------------

const stageOrder = ['DEEP', 'LIGHT', 'REM', 'AWAKE'];

String stageLabel(String name) => switch (name) {
      'DEEP' => 'Βαθύς',
      'LIGHT' => 'Ελαφρύς',
      'REM' => 'REM',
      'AWAKE' => 'Ξύπνιος',
      _ => 'Άλλο',
    };

Color stageColor(BuildContext context, String name, {bool onBlue = false}) {
  final c = Aigaio.of(context);
  if (onBlue) {
    return switch (name) {
      'DEEP' => const Color(0xFF0B2E6E),
      'LIGHT' => const Color(0xFF9CC0FF),
      'REM' => c.wheat,
      'AWAKE' => c.terracotta,
      _ => Colors.white24,
    };
  }
  return switch (name) {
    'DEEP' => c.primary,
    'LIGHT' => c.primary.withValues(alpha: 0.4),
    'REM' => c.wheat,
    'AWAKE' => c.terracotta,
    _ => c.textSecondary,
  };
}

/// Οριζόντια μπάρα με τις φάσεις στη σειρά που έγιναν μέσα στη νύχτα.
class StageTimeline extends StatelessWidget {
  const StageTimeline({super.key, required this.night, this.height = 14, this.onBlue = false});

  final Night night;
  final double height;
  final bool onBlue;

  @override
  Widget build(BuildContext context) {
    final total = night.end.difference(night.start).inSeconds.toDouble();
    if (night.stages.isEmpty || total <= 0) {
      return const SizedBox.shrink();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: CustomPaint(
          size: Size.infinite,
          painter: _TimelinePainter(
            [
              for (final s in night.stages)
                (
                  s.start.difference(night.start).inSeconds / total,
                  s.end.difference(night.start).inSeconds / total,
                  stageColor(context, s.name, onBlue: onBlue),
                ),
            ],
            onBlue ? Colors.white24 : Aigaio.of(context).background,
          ),
        ),
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter(this.parts, this.background);
  final List<(double, double, Color)> parts;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    for (final (a, b, color) in parts) {
      final left = a.clamp(0.0, 1.0) * size.width;
      final right = b.clamp(0.0, 1.0) * size.width;
      if (right <= left) continue;
      canvas.drawRect(Rect.fromLTRB(left, 0, right, size.height), Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) => true;
}

class StageLegend extends StatelessWidget {
  const StageLegend({super.key, required this.night, this.onBlue = false});
  final Night night;
  final bool onBlue;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final textColor = onBlue ? c.onPrimary : c.textSecondary;
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final name in stageOrder)
          if ((night.stageMinutes[name] ?? 0) > 0)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: stageColor(context, name, onBlue: onBlue),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${stageLabel(name)} ${_hm(night.stageMinutes[name] ?? 0)}',
                  style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
      ],
    );
  }

  String _hm(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return h == 0 ? '$m λ' : '$h ώ $m λ';
  }
}

// ---------------------------------------------------------------------------
// Γραφήματα (χωρίς βιβλιοθήκες)
// ---------------------------------------------------------------------------

/// Ράβδοι ανά μέρα, με προαιρετική γραμμή μέσου όρου.
class BarChart extends StatelessWidget {
  const BarChart({
    super.key,
    required this.values,
    required this.labels,
    this.height = 150,
    this.average,
    this.highlightLast = true,
    this.valueLabel,
  });

  final List<double?> values;
  final List<String> labels;
  final double height;
  final double? average;
  final bool highlightLast;
  final String Function(double)? valueLabel;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _BarPainter(
          values: values,
          labels: labels,
          average: average,
          highlightLast: highlightLast,
          bar: c.primary.withValues(alpha: 0.35),
          barStrong: c.primary,
          text: c.textSecondary,
          line: c.terracotta,
          valueLabel: valueLabel,
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.values,
    required this.labels,
    required this.average,
    required this.highlightLast,
    required this.bar,
    required this.barStrong,
    required this.text,
    required this.line,
    required this.valueLabel,
  });

  final List<double?> values;
  final List<String> labels;
  final double? average;
  final bool highlightLast;
  final Color bar;
  final Color barStrong;
  final Color text;
  final Color line;
  final String Function(double)? valueLabel;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const labelHeight = 18.0;
    const topPad = 16.0;
    final chartHeight = size.height - labelHeight - topPad;
    final maxV = [
      ...values.whereType<double>(),
      if (average != null) average!,
    ].fold<double>(0, math.max);
    if (maxV <= 0) return;

    final slot = size.width / values.length;
    final barWidth = math.min(28.0, slot * 0.6);
    final showEvery = labels.length > 10 ? (labels.length / 7).ceil() : 1;

    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      final cx = slot * i + slot / 2;
      if (v != null && v > 0) {
        final h = chartHeight * (v / maxV);
        final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - barWidth / 2, topPad + chartHeight - h, barWidth, h),
          const Radius.circular(6),
        );
        final strong = highlightLast && i == values.length - 1;
        canvas.drawRRect(r, Paint()..color = strong ? barStrong : bar);
        if (strong && valueLabel != null) {
          _text(canvas, valueLabel!(v), Offset(cx, topPad + chartHeight - h - 14), text, 11, bold: true);
        }
      }
      final fromEnd = values.length - 1 - i;
      if (i < labels.length && fromEnd % showEvery == 0) {
        _text(canvas, labels[i], Offset(cx, size.height - labelHeight + 2), text, 11);
      }
    }

    if (average != null && average! > 0) {
      final y = topPad + chartHeight - chartHeight * (average! / maxV);
      final paint = Paint()
        ..color = line
        ..strokeWidth = 1.5;
      for (double x = 0; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, size.width), y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) => true;
}

/// Γραμμή στον χρόνο, για βάρος, λίπος, παλμούς.
class LineChart extends StatelessWidget {
  const LineChart({
    super.key,
    required this.points,
    this.height = 160,
    this.format,
    this.color,
    this.dateLabel,
  });

  final List<(DateTime, double)> points;
  final double height;
  final String Function(double)? format;
  final Color? color;
  final String Function(DateTime)? dateLabel;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _LinePainter(
          points: points,
          color: color ?? c.primary,
          text: c.textSecondary,
          grid: c.textSecondary.withValues(alpha: 0.15),
          format: format ?? (v) => v.toStringAsFixed(1),
          dateLabel: dateLabel ?? (d) => '${d.day}/${d.month}',
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.points,
    required this.color,
    required this.text,
    required this.grid,
    required this.format,
    required this.dateLabel,
  });

  final List<(DateTime, double)> points;
  final Color color;
  final Color text;
  final Color grid;
  final String Function(double) format;
  final String Function(DateTime) dateLabel;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const left = 40.0;
    const bottom = 20.0;
    const top = 10.0;
    final w = size.width - left - 8;
    final h = size.height - bottom - top;

    var minV = points.map((p) => p.$2).reduce(math.min);
    var maxV = points.map((p) => p.$2).reduce(math.max);
    if (maxV - minV < 1e-6) {
      minV -= 1;
      maxV += 1;
    }
    final pad = (maxV - minV) * 0.15;
    minV -= pad;
    maxV += pad;

    final t0 = points.first.$1.millisecondsSinceEpoch.toDouble();
    final t1 = points.last.$1.millisecondsSinceEpoch.toDouble();
    final span = math.max(t1 - t0, 1.0);

    Offset at((DateTime, double) p) {
      final x = points.length == 1 ? left + w / 2 : left + w * ((p.$1.millisecondsSinceEpoch - t0) / span);
      final y = top + h * (1 - (p.$2 - minV) / (maxV - minV));
      return Offset(x, y);
    }

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final v = minV + (maxV - minV) * i / 2;
      final y = top + h * (1 - i / 2);
      canvas.drawLine(Offset(left, y), Offset(size.width, y), gridPaint);
      _text(canvas, format(v), Offset(left / 2, y - 7), text, 10);
    }

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final o = at(points[i]);
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    final dot = Paint()..color = color;
    for (final p in points) {
      canvas.drawCircle(at(p), points.length > 40 ? 1.5 : 3.5, dot);
    }

    _text(canvas, dateLabel(points.first.$1), Offset(left + 16, size.height - bottom + 4), text, 10);
    if (points.length > 1) {
      _text(canvas, dateLabel(points.last.$1), Offset(size.width - 24, size.height - bottom + 4), text, 10);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => true;
}

void _text(Canvas canvas, String s, Offset center, Color color, double size, {bool bold = false}) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(color: color, fontSize: size, fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy));
}

/// Κενή κατάσταση: ποτέ σκέτο «δεν υπάρχουν δεδομένα», πάντα τι να κάνω.
class EmptyCard extends StatelessWidget {
  const EmptyCard({super.key, required this.title, required this.text, this.buttonText, this.onPressed});

  final String title;
  final String text;
  final String? buttonText;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text)),
          const SizedBox(height: 6),
          Text(text, style: TextStyle(color: c.textSecondary, height: 1.35)),
          if (buttonText != null && onPressed != null) ...[
            const SizedBox(height: 14),
            OutlinedButton(onPressed: onPressed, child: Text(buttonText!)),
          ],
        ],
      ),
    );
  }
}
