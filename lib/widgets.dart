import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'data.dart';
import 'format.dart';
import 'theme.dart';

// ---------------------------------------------------------------------------
// Διάταξη σελίδας: μία στήλη στο κινητό, δύο σε ανοιχτό Fold / tablet,
// ποτέ τεντωμένη (μέγιστο πλάτος).
// ---------------------------------------------------------------------------

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.action,
    required this.onRefresh,
    required this.left,
    this.right = const [],
    this.single,
  });

  final String title;
  /// Σειρά για μία στήλη (κινητό), αν διαφέρει από αριστερά + δεξιά.
  final List<Widget>? single;
  final String? eyebrow;
  final String? subtitle;
  final Widget? action;
  final Future<void> Function() onRefresh;
  final List<Widget> left;
  final List<Widget> right;

  static const gap = 14.0;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.maxWidth >= 600 ? 28.0 : 18.0;
          final width = math.min(constraints.maxWidth - side * 2, 1080.0);
          final twoColumns = width >= 680 && right.isNotEmpty;

          Widget column(List<Widget> items) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) SizedBox(height: items[i] is SectionHeader ? 22 : gap),
                    items[i],
                  ],
                ],
              );

          final header = Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (eyebrow != null)
                        Text(
                          eyebrow!,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.textSecondary),
                        ),
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 32,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.8,
                          color: c.text,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
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
                    const SizedBox(width: gap + 4),
                    Expanded(child: column(right)),
                  ],
                )
              : column(single ?? [...left, ...right]);

          return RefreshIndicator(
            onRefresh: onRefresh,
            color: c.primary,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(side, 18, side, 120),
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

/// Μικρός τίτλος ενότητας μέσα στη σελίδα.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text, letterSpacing: -0.2),
      ),
    );
  }
}

/// Δύο κάρτες δίπλα δίπλα, ίδιο ύψος.
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

  static const radius = 24.0;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: c.dark ? Border.all(color: c.hairline) : null,
        boxShadow: c.dark
            ? null
            : const [
                BoxShadow(color: Color(0x0A0F172A), blurRadius: 2, offset: Offset(0, 1)),
                BoxShadow(color: Color(0x0D0F172A), blurRadius: 24, offset: Offset(0, 8)),
              ],
      ),
      child: Material(
        color: c.card,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Στρογγυλό εικονίδιο με απαλό φόντο στο χρώμα της ενότητας.
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, this.color, {super.key, this.size = 34});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.tint(color), borderRadius: BorderRadius.circular(size * 0.34)),
      child: Icon(icon, size: size * 0.56, color: color),
    );
  }
}

/// Κεφαλίδα κάρτας: εικονίδιο + τίτλος (+ κάτι δεξιά).
class CardHeader extends StatelessWidget {
  const CardHeader({super.key, required this.icon, required this.title, required this.color, this.trailing});
  final IconData icon;
  final String title;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Row(
      children: [
        IconBadge(icon, color, size: 30),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13.5, height: 1.25, fontWeight: FontWeight.w600, color: c.textSecondary),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

enum TrendKind { good, bad, neutral }

/// «Χάπι» τάσης: ↑/↓ με χρώμα καλό/κακό/ουδέτερο.
class TrendPill extends StatelessWidget {
  const TrendPill(this.text, {super.key, this.kind = TrendKind.neutral, this.up, this.onDark = false});
  final String text;
  final TrendKind kind;
  final bool? up;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final color = onDark
        ? Colors.white
        : switch (kind) {
            TrendKind.good => c.good,
            TrendKind.bad => c.bad,
            TrendKind.neutral => c.textSecondary,
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withValues(alpha: 0.14) : c.tint(color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (up != null) ...[
            Icon(up! ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 13, color: color),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Μεγάλος αριθμός με μικρή μονάδα δίπλα.
class BigValue extends StatelessWidget {
  const BigValue(this.value, {super.key, this.unit, this.size = 30, this.color, this.unitColor});
  final String value;
  final String? unit;
  final double size;
  final Color? color;
  final Color? unitColor;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: value,
            style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              color: color ?? c.text,
              fontFeatures: tabular,
            ),
          ),
          if (unit != null)
            TextSpan(
              text: ' $unit',
              style: TextStyle(
                fontSize: size * 0.48,
                fontWeight: FontWeight.w600,
                color: unitColor ?? c.textSecondary,
              ),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// «6 ώρες 12 λεπτά» με μεγάλους αριθμούς και μικρές λέξεις.
class DurationValue extends StatelessWidget {
  const DurationValue(this.minutes, {super.key, this.size = 32, this.color, this.unitColor});
  final int minutes;
  final double size;
  final Color? color;
  final Color? unitColor;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final parts = hoursMinutesParts(minutes);
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < parts.length; i++) ...[
            TextSpan(
              text: (i > 0 ? '  ' : '') + parts[i].$1,
              style: TextStyle(
                fontSize: size,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.8,
                color: color ?? c.text,
                fontFeatures: tabular,
              ),
            ),
            TextSpan(
              text: ' ${parts[i].$2}',
              style: TextStyle(fontSize: size * 0.5, fontWeight: FontWeight.w600, color: unitColor ?? c.textSecondary),
            ),
          ],
        ],
      ),
      maxLines: 1,
    );
  }
}

/// Μικρή κάρτα: εικονίδιο + τίτλος, μεγάλη τιμή, τάση, και προαιρετικά μικρό γράφημα.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    this.unit,
    this.trend,
    this.note,
    this.chart,
    this.empty,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? value;
  final String? unit;
  final Widget? trend;
  final String? note;
  final Widget? chart;
  final String? empty;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardHeader(icon: icon, title: title, color: color),
          const SizedBox(height: 14),
          if (value == null) ...[
            Text(
              empty ?? 'Δεν υπάρχουν δεδομένα ακόμα',
              style: TextStyle(color: c.textSecondary, fontSize: 14, height: 1.35),
            ),
          ] else ...[
            BigValue(value!, unit: unit, size: 28),
            if (trend != null) ...[const SizedBox(height: 8), trend!],
            if (note != null) ...[
              const SizedBox(height: 6),
              Text(note!, style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.3)),
            ],
            if (chart != null) ...[const Spacer(), const SizedBox(height: 12), chart!],
          ],
        ],
      ),
    );
  }
}

/// Γραμμή «όνομα ........ τιμή».
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.valueColor, this.dot});
  final String label;
  final String value;
  final Color? valueColor;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          if (dot != null) ...[
            Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(label, style: TextStyle(color: c.textSecondary, fontSize: 15))),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? c.text,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              fontFeatures: tabular,
            ),
          ),
        ],
      ),
    );
  }
}

class Hairline extends StatelessWidget {
  const Hairline({super.key, this.vertical = 10});
  final double vertical;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(vertical: vertical),
        child: Divider(height: 1, color: Aigaio.of(context).hairline),
      );
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
    this.caption,
  });

  final double? value;
  final double size;
  final double stroke;
  final Color color;
  final Color track;
  final Color? textColor;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final ring = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter((value ?? 0) / 100, stroke, color, track),
        child: Center(
          child: Text(
            value == null ? '—' : value!.round().toString(),
            style: TextStyle(
              fontSize: size * 0.34,
              height: 1.0,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: textColor ?? color,
              fontFeatures: tabular,
            ),
          ),
        ),
      ),
    );
    if (caption == null) return ring;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ring,
        const SizedBox(height: 6),
        Text(
          caption!,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: (textColor ?? color).withValues(alpha: 0.72)),
        ),
      ],
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
    final r = (Offset.zero & size).deflate(stroke / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(r, 0, math.pi * 2, false, p);
    final f = fraction.clamp(0.0, 1.0);
    if (f > 0) canvas.drawArc(r, -math.pi / 2, math.pi * 2 * f, false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction || old.color != color || old.track != track;
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

Color stageColorOf(String name) => switch (name) {
      'DEEP' => StageColors.deep,
      'LIGHT' => StageColors.light,
      'REM' => StageColors.rem,
      'AWAKE' => StageColors.awake,
      _ => const Color(0xFF94A0B4),
    };

/// Η νύχτα σαν «υπνόγραμμα»: κάθε φάση σε δική της γραμμή ύψους, στη σειρά που έγινε.
class Hypnogram extends StatelessWidget {
  const Hypnogram({super.key, required this.night, this.height = 64, this.onDark = false});

  final Night night;
  final double height;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final total = night.end.difference(night.start).inSeconds.toDouble();
    if (night.stages.isEmpty || total <= 0) return const SizedBox.shrink();
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _HypnoPainter(
          [
            for (final s in night.stages)
              (
                s.start.difference(night.start).inSeconds / total,
                s.end.difference(night.start).inSeconds / total,
                s.name,
              ),
          ],
          onDark ? Colors.white.withValues(alpha: 0.08) : Aigaio.of(context).background,
        ),
      ),
    );
  }
}

class _HypnoPainter extends CustomPainter {
  _HypnoPainter(this.parts, this.track);
  final List<(double, double, String)> parts;
  final Color track;

  // Από πάνω προς τα κάτω: ξύπνιος, REM, ελαφρύς, βαθύς.
  static const _rows = ['AWAKE', 'REM', 'LIGHT', 'DEEP'];

  @override
  void paint(Canvas canvas, Size size) {
    final rowH = size.height / _rows.length;
    final barH = rowH * 0.74;
    for (var i = 0; i < _rows.length; i++) {
      final y = rowH * i + (rowH - barH) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, y, size.width, barH), Radius.circular(barH / 2)),
        Paint()..color = track,
      );
    }
    for (final (a, b, name) in parts) {
      final row = _rows.indexOf(name);
      if (row < 0) continue;
      final left = a.clamp(0.0, 1.0) * size.width;
      final right = math.max(b.clamp(0.0, 1.0) * size.width, left + 2);
      final y = rowH * row + (rowH - barH) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(left, y, right, y + barH), const Radius.circular(3)),
        Paint()..color = stageColorOf(name),
      );
    }
  }

  @override
  bool shouldRepaint(_HypnoPainter old) => true;
}

/// Λεπτή μπάρα με τις φάσεις στη σειρά (για λίστες νυχτών).
class StageTimeline extends StatelessWidget {
  const StageTimeline({super.key, required this.night, this.height = 10, this.onBlue = false});

  final Night night;
  final double height;
  final bool onBlue;

  @override
  Widget build(BuildContext context) {
    final total = night.end.difference(night.start).inSeconds.toDouble();
    if (night.stages.isEmpty || total <= 0) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _TimelinePainter(
            [
              for (final s in night.stages)
                (
                  s.start.difference(night.start).inSeconds / total,
                  s.end.difference(night.start).inSeconds / total,
                  stageColorOf(s.name),
                ),
            ],
            onBlue ? Colors.white.withValues(alpha: 0.12) : Aigaio.of(context).background,
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

/// Υπόμνημα φάσεων σε πλέγμα 2×2: χρώμα, όνομα, διάρκεια, ποσοστό.
class StageLegend extends StatelessWidget {
  const StageLegend({super.key, required this.night, this.onBlue = false});
  final Night night;
  final bool onBlue;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final total = stageOrder.fold<int>(0, (s, n) => s + (night.stageMinutes[n] ?? 0));
    final main = onBlue ? Colors.white : c.text;
    final sub = onBlue ? Colors.white.withValues(alpha: 0.7) : c.textSecondary;

    Widget item(String name) {
      final m = night.stageMinutes[name] ?? 0;
      final pct = total == 0 ? 0 : (m * 100 / total).round();
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: stageColorOf(name), borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${stageLabel(name)} · $pct%',
                  style: TextStyle(color: sub, fontSize: 12.5, fontWeight: FontWeight.w500),
                ),
                Text(
                  hoursMinutes(m),
                  style: TextStyle(color: main, fontSize: 14.5, fontWeight: FontWeight.w600, fontFeatures: tabular),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Row(children: [Expanded(child: item('DEEP')), Expanded(child: item('LIGHT'))]),
        const SizedBox(height: 10),
        Row(children: [Expanded(child: item('REM')), Expanded(child: item('AWAKE'))]),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Μικρά γραφήματα για κάρτες
// ---------------------------------------------------------------------------

/// 7 μικρές ράβδοι, η τελευταία (σήμερα) έντονη.
class MiniBars extends StatelessWidget {
  const MiniBars({super.key, required this.values, required this.color, this.height = 34});
  final List<double> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _MiniBarsPainter(values, color, color.withValues(alpha: c.dark ? 0.32 : 0.26))),
    );
  }
}

class _MiniBarsPainter extends CustomPainter {
  _MiniBarsPainter(this.values, this.strong, this.soft);
  final List<double> values;
  final Color strong;
  final Color soft;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = values.fold<double>(0, math.max);
    if (maxV <= 0) return;
    const gap = 4.0;
    final w = (size.width - gap * (values.length - 1)) / values.length;
    for (var i = 0; i < values.length; i++) {
      final h = math.max(3.0, size.height * values[i] / maxV);
      final x = i * (w + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, size.height - h, w, h), const Radius.circular(3)),
        Paint()..color = i == values.length - 1 ? strong : soft,
      );
    }
  }

  @override
  bool shouldRepaint(_MiniBarsPainter old) => true;
}

/// Μικρή γραμμή τάσης.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, required this.color, this.height = 34});
  final List<double> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _SparkPainter(values, color)),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var lo = values.reduce(math.min);
    var hi = values.reduce(math.max);
    if (hi - lo < 1e-6) {
      lo -= 1;
      hi += 1;
    }
    Offset at(int i) => Offset(
          size.width * i / (values.length - 1),
          4 + (size.height - 8) * (1 - (values[i] - lo) / (hi - lo)),
        );
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(at(values.length - 1), 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => true;
}

// ---------------------------------------------------------------------------
// Μεγάλα γραφήματα (χωρίς βιβλιοθήκες)
// ---------------------------------------------------------------------------

/// Ράβδοι ανά μέρα, με γραμμή μέσου όρου.
class BarChart extends StatelessWidget {
  const BarChart({
    super.key,
    required this.values,
    required this.labels,
    this.height = 170,
    this.average,
    this.highlightLast = true,
    this.valueLabel,
    this.color,
  });

  final List<double?> values;
  final List<String> labels;
  final double height;
  final double? average;
  final bool highlightLast;
  final String Function(double)? valueLabel;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final col = color ?? c.primary;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _BarPainter(
          values: values,
          labels: labels,
          average: average,
          highlightLast: highlightLast,
          bar: col.withValues(alpha: c.dark ? 0.35 : 0.25),
          barStrong: col,
          text: c.textTertiary,
          strongText: c.text,
          line: c.textSecondary,
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
    required this.strongText,
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
  final Color strongText;
  final Color line;
  final String Function(double)? valueLabel;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const labelHeight = 20.0;
    const topPad = 22.0;
    final chartHeight = size.height - labelHeight - topPad;
    final maxV = [...values.whereType<double>(), if (average != null) average!].fold<double>(0, math.max);
    if (maxV <= 0) return;

    final slot = size.width / values.length;
    final barWidth = math.min(26.0, slot * 0.62);
    final showEvery = labels.length > 10 ? 2 : 1;

    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      final cx = slot * i + slot / 2;
      final strong = highlightLast && i == values.length - 1;
      if (v != null && v > 0) {
        final h = math.max(4.0, chartHeight * (v / maxV));
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - barWidth / 2, topPad + chartHeight - h, barWidth, h),
            Radius.circular(math.min(8.0, barWidth / 2)),
          ),
          Paint()..color = strong ? barStrong : bar,
        );
        if (strong && valueLabel != null) {
          final tp = _painter(valueLabel!(v), strongText, 12, bold: true);
          final x = (cx - tp.width / 2).clamp(0.0, math.max(0.0, size.width - tp.width));
          tp.paint(canvas, Offset(x, topPad + chartHeight - h - 18));
        }
      }
      final fromEnd = values.length - 1 - i;
      if (i < labels.length && fromEnd % showEvery == 0) {
        _text(canvas, labels[i], Offset(cx, size.height - labelHeight + 4), strong ? strongText : text, 11,
            bold: strong);
      }
    }

    if (average != null && average! > 0) {
      final y = topPad + chartHeight - chartHeight * (average! / maxV);
      final paint = Paint()
        ..color = line.withValues(alpha: 0.7)
        ..strokeWidth = 1.2;
      for (double x = 0; x < size.width; x += 7) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 3.5, size.width), y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) => true;
}

/// Γραμμή στον χρόνο (βάρος, λίπος, παλμοί), με απαλή σκίαση.
class LineChart extends StatelessWidget {
  const LineChart({
    super.key,
    required this.points,
    this.height = 170,
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
          text: c.textTertiary,
          strongText: c.text,
          grid: c.hairline,
          card: c.card,
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
    required this.strongText,
    required this.grid,
    required this.card,
    required this.format,
    required this.dateLabel,
  });

  final List<(DateTime, double)> points;
  final Color color;
  final Color text;
  final Color strongText;
  final Color grid;
  final Color card;
  final String Function(double) format;
  final String Function(DateTime) dateLabel;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const left = 4.0;
    const right = 44.0;
    const bottom = 22.0;
    const top = 26.0;
    final w = size.width - left - right;
    final h = size.height - bottom - top;

    var minV = points.map((p) => p.$2).reduce(math.min);
    var maxV = points.map((p) => p.$2).reduce(math.max);
    if (maxV - minV < 1e-6) {
      minV -= 1;
      maxV += 1;
    }
    final pad = (maxV - minV) * 0.2;
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
      canvas.drawLine(Offset(left, y), Offset(left + w, y), gridPaint);
      _textLeft(canvas, format(v), Offset(left + w + 8, y - 7), text, 11);
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
    if (points.length > 1) {
      final fill = Path.from(path)
        ..lineTo(at(points.last).dx, top + h)
        ..lineTo(at(points.first).dx, top + h)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.20), color.withValues(alpha: 0.0)],
          ).createShader(Rect.fromLTWH(0, top, size.width, h)),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    if (points.length <= 31) {
      final dot = Paint()..color = color;
      for (final p in points) {
        canvas.drawCircle(at(p), 2.5, dot);
      }
    }
    final last = at(points.last);
    canvas.drawCircle(last, 6, Paint()..color = card);
    canvas.drawCircle(last, 4.5, Paint()..color = color);
    _text(canvas, format(points.last.$2), Offset(math.min(last.dx, left + w - 16), last.dy - 24), strongText, 12,
        bold: true);

    _textLeft(canvas, dateLabel(points.first.$1), Offset(left, size.height - bottom + 6), text, 11);
    if (points.length > 1) {
      final label = dateLabel(points.last.$1);
      final tp = _painter(label, text, 11);
      tp.paint(canvas, Offset(left + w - tp.width, size.height - bottom + 6));
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => true;
}

TextPainter _painter(String s, Color color, double size, {bool bold = false}) => TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontFamily: fontFamily,
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          fontFeatures: tabular,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

void _text(Canvas canvas, String s, Offset center, Color color, double size, {bool bold = false}) {
  final tp = _painter(s, color, size, bold: bold);
  tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy));
}

void _textLeft(Canvas canvas, String s, Offset topLeft, Color color, double size) {
  _painter(s, color, size).paint(canvas, topLeft);
}

/// Κενή κατάσταση: ποτέ σκέτο «δεν υπάρχουν δεδομένα», πάντα τι να κάνω.
class EmptyCard extends StatelessWidget {
  const EmptyCard({
    super.key,
    required this.title,
    required this.text,
    this.icon,
    this.color,
    this.buttonText,
    this.onPressed,
  });

  final String title;
  final String text;
  final IconData? icon;
  final Color? color;
  final String? buttonText;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (icon != null)
            CardHeader(icon: icon!, title: title, color: color ?? c.primary)
          else
            Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
          const SizedBox(height: 10),
          Text(text, style: TextStyle(color: c.textSecondary, fontSize: 14.5, height: 1.4)),
          if (buttonText != null && onPressed != null) ...[
            const SizedBox(height: 14),
            OutlinedButton(onPressed: onPressed, child: Text(buttonText!)),
          ],
        ],
      ),
    );
  }
}

/// Τίτλος μέσα σε μεγάλη κάρτα.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Text(text, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text, letterSpacing: -0.2));
  }
}
