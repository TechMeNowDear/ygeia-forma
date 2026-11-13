import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'data.dart';
import 'format.dart';
import 'theme.dart';

// ---------------------------------------------------------------------------
// Διάταξη σελίδας: μία στήλη στο κινητό, δύο σε ανοιχτό Fold / tablet,
// ποτέ τεντωμένη (μέγιστο πλάτος).
// ---------------------------------------------------------------------------

/// Σαν το IndexedStack, αλλά κάθε σελίδα χτίζεται μόνο την πρώτη φορά που την ανοίγεις
/// (και μετά κρατά την κατάστασή της). Λιγότερη μνήμη και δουλειά στο άνοιγμα της εφαρμογής.
class LazyIndexedStack extends StatefulWidget {
  const LazyIndexedStack({super.key, required this.index, required this.children});
  final int index;
  final List<Widget> children;

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  final _built = <int>{};

  @override
  Widget build(BuildContext context) {
    _built.add(widget.index);
    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          _built.contains(i) ? widget.children[i] : const SizedBox.shrink(),
      ],
    );
  }
}

/// Όταν μια σελίδα ζει μέσα σε κατηγορία (Υγεία, Διατροφή, Άσκηση), η κατηγορία δίνει
/// την κεφαλίδα (τίτλο και καρτέλες) και η σελίδα κρατά μόνο τη δική της γραμμή κάτω από αυτήν.
class PageHeaderScope extends InheritedWidget {
  const PageHeaderScope({super.key, required this.header, required super.child});
  final Widget header;

  static PageHeaderScope? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PageHeaderScope>();

  @override
  bool updateShouldNotify(PageHeaderScope oldWidget) => oldWidget.header != header;
}

/// Ο μεγάλος τίτλος σελίδας, ίδιος παντού.
class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key, this.eyebrow, this.eyebrowColor});
  final String title;
  final String? eyebrow;
  final Color? eyebrowColor;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null)
          Text(
            eyebrow!,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: eyebrowColor == null ? FontWeight.w500 : FontWeight.w600,
              color: eyebrowColor ?? c.textSecondary,
            ),
          ),
        // Σχέδια 9/11: με μεγάλα γράμματα ο τίτλος μικραίνει για να χωρά, ποτέ σπασμένη λέξη («Καλησπ/έρα»).
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            maxLines: 1,
            style: TextStyle(fontSize: 34, height: 1.18, fontWeight: FontWeight.w800, letterSpacing: -1.1, color: c.text),
          ),
        ),
      ],
    );
  }
}

/// Πολύ μεγάλα γράμματα (πάνω από 1,5×): οι κάρτες που κάθονται δίπλα δίπλα πάνε η μία κάτω από την άλλη.
bool veryLargeText(BuildContext context) => MediaQuery.textScalerOf(context).scale(10) > 15.01;

/// Χωράει κάθε λέξη των [texts] σε πλάτος [width]; (αλλιώς μια στενή στήλη θα έσπαγε λέξη στη μέση).
bool wordsFit(BuildContext context, Iterable<String> texts, TextStyle style, double width) {
  final scaler = MediaQuery.textScalerOf(context);
  // Με τη γραμματοσειρά της εφαρμογής (Inter), όπως θα ζωγραφιστεί.
  final base = DefaultTextStyle.of(context).style;
  for (final t in texts) {
    for (final w in t.split(' ')) {
      final tp = TextPainter(text: TextSpan(text: w, style: base.merge(style)), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)
        ..layout();
      final over = tp.width > width;
      tp.dispose();
      if (over) return false;
    }
  }
  return true;
}

/// Σκελετός κάθε σελίδας: τίτλος, ανανέωση με τράβηγμα, μία στήλη στο κινητό, δύο σε μεγάλη οθόνη.
/// Κάρτα που βάζει μόνη της το κενό από κάτω (και τίποτα όταν δεν φαίνεται), π.χ. μια θέση που μπορεί να είναι άδεια.
mixin SelfSpaced on Widget {}

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
    this.top = const [],
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

  /// Σε δύο στήλες: πάνω από τις στήλες, σε όλο το πλάτος (π.χ. ειδοποίηση).
  final List<Widget> top;

  static const gap = 14.0;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final scope = PageHeaderScope.of(context);
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.maxWidth >= 600 ? 28.0 : 16.0;
          final available = constraints.maxWidth - side * 2;
          // Δύο στήλες από ~580 dp περιεχομένου (στήλες ~283 dp, όσο ένα στενό κινητό): το ανοιχτό Fold με την πλαϊνή
          // μπάρα έμενε σε μία στήλη με το 680 (έλεγχος 8/11, UX-20).
          final twoColumns = available >= 580 && right.isNotEmpty;
          // Μία στήλη σε φαρδιά οθόνη: όχι τεντωμένη, έως 640 στο κέντρο.
          final width = math.min(available, twoColumns ? 1080.0 : 640.0);

          Widget column(List<Widget> items) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    // Έλεγχος 13/11 (U3b-13): μια θέση [SelfSpaced] βάζει το κενό της από ΚΑΤΩ· έτσι, πρώτη στη στήλη,
                    // ξεκινά στο ίδιο ύψος με κάθε άλλη πρώτη κάρτα, και άδεια δεν αφήνει κενό.
                    if (i > 0 && items[i - 1] is! SelfSpaced)
                      SizedBox(height: items[i] is SectionHeader ? 22 : gap)
                    // Round 1 (f9, U1a-1): τίτλος ενότητας μετά από θέση: η θέση έδωσε ήδη 14 (κάτω της ή πριν από αυτήν).
                    else if (i > 0 && items[i] is SectionHeader)
                      const SizedBox(height: 22.0 - gap),
                    items[i],
                  ],
                ],
              );

          final Widget header;
          if (scope != null) {
            // Μέσα σε κατηγορία: η κεφαλίδα της κατηγορίας, και από κάτω η γραμμή της σελίδας.
            final line = subtitle == null && action == null
                ? null
                : Row(
                    children: [
                      if (subtitle != null)
                        Expanded(
                          child: Text(subtitle!, style: TextStyle(fontSize: 14.5, color: c.textSecondary)),
                        ),
                      if (action != null) subtitle == null ? Expanded(child: action!) : action!,
                    ],
                  );
            header = Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  scope.header,
                  if (line != null) ...[const SizedBox(height: 14), line],
                ],
              ),
            );
          } else {
            header = Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PageTitle(title, eyebrow: eyebrow),
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
          }

          final body = twoColumns
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (top.isNotEmpty) ...[column(top), const SizedBox(height: gap)],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: column(left)),
                        const SizedBox(width: gap + 2),
                        Expanded(child: column(right)),
                      ],
                    ),
                  ],
                )
              : column(single ?? [...top, ...left, ...right]);

          return RefreshIndicator(
            onRefresh: onRefresh,
            color: c.primary,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(side, 14, side, 120),
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
    if (veryLargeText(context)) {
      // IntrinsicHeight: οι κάρτες με Spacer (γράφημα κάτω) παίρνουν το φυσικό τους ύψος.
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        IntrinsicHeight(child: first),
        if (second != null) ...[const SizedBox(height: PageFrame.gap), IntrinsicHeight(child: second!)],
      ]);
    }
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
      // Καθαρό περίγραμμα αντί για θολή σκιά: πιο «καθαρή» εικόνα.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: c.dark ? null : const [BoxShadow(color: Color(0x0A0F172A), blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: Material(
        color: c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: c.hairline),
        ),
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
  const CardHeader({super.key, required this.icon, required this.title, required this.color, this.trailing, this.subtitle});
  final IconData icon;
  final String title;
  final Color color;
  final Widget? trailing;

  /// Μικρή δεύτερη γραμμή κάτω από τον τίτλο (π.χ. η ημερομηνία «Σάβ 24/10»), ώστε ο τίτλος να μην κόβεται σε στενή
  /// κάρτα (UX U1: «Ενεργός χρόνος · Σ…» στα 860 dp).
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Row(
      children: [
        IconBadge(icon, color, size: 30),
        const SizedBox(width: 10),
        Expanded(
          child: subtitle == null
              ? Text(
                  title,
                                    style: TextStyle(fontSize: 15, height: 1.25, fontWeight: FontWeight.w600, color: c.textSecondary),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                                            style: TextStyle(fontSize: 15, height: 1.25, fontWeight: FontWeight.w600, color: c.textSecondary),
                    ),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      style: TextStyle(fontSize: 12, height: 1.25, color: c.textTertiary, fontFeatures: tabular),
                    ),
                  ],
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
  const TrendPill(this.text,
      {super.key, this.kind = TrendKind.neutral, this.up, this.onDark = false, this.maxLines = 1, this.keepLastWords = false});
  final String text;

  /// Οι δύο τελευταίες λέξεις μένουν στην ίδια γραμμή (round 1, U1a-14: όχι «… από ό,τι | συνήθως», «−1,1 kg από | 13/8»).
  /// Αλλάζει μόνο η ζωγραφική (αδιάσπαστο κενό)· το [text] μένει ίδιο.
  final bool keepLastWords;

  /// Γραμμές πριν κοπεί με «…» (2 όπου το κείμενο είναι πρόταση, π.χ. η σύγκριση με το συνηθισμένο).
  final int maxLines;
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
        // Round 1 (U4-14 j): ίδιο σχήμα με κάθε «χάπι» κατάστασης της εφαρμογής.
        borderRadius: BorderRadius.circular(999),
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
              keepLastWords ? text.replaceFirst(RegExp(r' (?=[^ ]*$)'), '\u00A0') : text,
              // Ποτέ κομμένο (σχέδια 9/11): αν δεν χωρά, πάει σε δεύτερη γραμμή.
              maxLines: maxLines < 3 ? 3 : maxLines,
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
    // Ποτέ κομμένος αριθμός ή μονάδα («1.200 k…»): με μεγάλα γράμματα μικραίνει για να χωρά (σχέδια 9/11).
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: value,
            style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w800,
              letterSpacing: -size * 0.035,
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
      ),
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
    // Σε στενή οθόνη ή με μεγάλα γράμματα: μικραίνει αντί να κόβεται.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < parts.length; i++) ...[
            TextSpan(
              text: (i > 0 ? '  ' : '') + parts[i].$1,
              style: TextStyle(
                fontSize: size,
                fontWeight: FontWeight.w800,
                letterSpacing: -size * 0.035,
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
      ),
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
    this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;

  /// Η ημερομηνία (ή άλλη μικρή πληροφορία) σε δική της γραμμή κάτω από τον τίτλο (UX U1).
  final String? subtitle;
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
          // Round 1 (U5-25 β): ίδιο ύψος κεφαλίδας σε κάθε κάρτα (τίτλος μίας ή δύο γραμμών, με ή χωρίς ημερομηνία), ώστε
          // στις κάρτες δίπλα δίπλα οι τιμές να είναι στην ίδια γραμμή.
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: MediaQuery.textScalerOf(context).scale(38)),
            child: Align(
              alignment: Alignment.centerLeft,
              child: CardHeader(icon: icon, title: title, color: color, subtitle: subtitle),
            ),
          ),
          const SizedBox(height: 14),
          if (value == null) ...[
            Text(
              empty ?? 'Δεν υπάρχουν δεδομένα ακόμα',
              style: TextStyle(color: c.textSecondary, fontSize: 14, height: 1.35),
            ),
          ] else ...[
            // Μεγάλη τιμή που δεν χωράει (π.χ. «2 ώρες 15 λεπτά» σε στενή κάρτα): μικραίνει, δεν κόβεται.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: BigValue(value!, unit: unit, size: 28),
            ),
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
    final valueText = Text(
      value,
      style: TextStyle(
        color: valueColor ?? c.text,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        fontFeatures: tabular,
      ),
    );
    final dotW = dot == null
        ? null
        : Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 10), decoration: BoxDecoration(color: dot, shape: BoxShape.circle));
    // Σχέδια 9/11 (9β): αν μια λέξη της ετικέτας δεν χωρά δίπλα στην τιμή, η τιμή πάει ολόκληρη στην από κάτω
    // γραμμή, δεξιά· ποτέ σπασμένη λέξη («Σκελετικο/ί») ή σπασμένος αριθμός.
    final labelStyle = TextStyle(color: c.textSecondary, fontSize: 15);
    return LayoutBuilder(builder: (context, box) {
      final scaler = MediaQuery.textScalerOf(context);
      final tp = TextPainter(
          text: TextSpan(text: value, style: DefaultTextStyle.of(context).style.merge(valueText.style)),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 1)
        ..layout();
      final valueW = tp.width;
      tp.dispose();
      final room = box.maxWidth - valueW - 12 - (dotW == null ? 0 : 18);
      if (box.maxWidth.isFinite && !wordsFit(context, [label], labelStyle, room)) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              if (dotW != null) dotW,
              Expanded(child: Text(label, style: labelStyle)),
            ]),
            Align(alignment: Alignment.centerRight, child: valueText),
          ]),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            if (dotW != null) dotW,
            Expanded(child: Text(label, style: labelStyle)),
            const SizedBox(width: 12),
            valueText,
          ],
        ),
      );
    });
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
        // Ο αριθμός μένει πάντα μέσα στον κύκλο (έλεγχος premium, M1): χωρά στο εσωτερικό του δαχτυλιδιού και μικραίνει
        // αν χρειαστεί, όποιο κι αν είναι το μέγεθος γραμμάτων του συστήματος (ο κύκλος δεν μεγαλώνει).
        child: Padding(
          padding: EdgeInsets.all(stroke + size * 0.08),
          child: Center(
          child: FittedBox(
            key: const ValueKey('score-ring-number'),
            fit: BoxFit.scaleDown,
            child: Text(
            value == null ? '—' : value!.round().toString(),
            maxLines: 1,
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

/// Χρώμα φάσης ύπνου στο τρέχον θέμα.
Color stageColorOf(BuildContext context, String name) => Aigaio.of(context).stage(name);

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
          onDark ? Colors.white.withValues(alpha: 0.10) : Aigaio.of(context).hairline,
          onDark ? Colors.white.withValues(alpha: 0.35) : Aigaio.of(context).textTertiary.withValues(alpha: 0.5),
          gaps: [
            for (final g in night.estimatedGaps)
              (g.$1.difference(night.start).inSeconds / total, g.$2.difference(night.start).inSeconds / total),
          ],
          gapColor: onDark ? Colors.white.withValues(alpha: 0.12) : Aigaio.of(context).sleep.withValues(alpha: 0.12),
          stageColor: Aigaio.of(context).stage,
        ),
      ),
    );
  }
}

/// Υπνόγραμμα: κάθε φάση στη γραμμή της, ενωμένες με λεπτές κάθετες, όπως στα εργαστήρια ύπνου.
class _HypnoPainter extends CustomPainter {
  _HypnoPainter(this.parts, this.guide, this.connector,
      {required this.stageColor, this.gaps = const [], this.gapColor = const Color(0x00000000)});
  final Color Function(String) stageColor;
  final List<(double, double, String)> parts;
  final Color guide;
  final Color connector;

  /// Κενά της Samsung που μετρήθηκαν ως ύπνος (εκτίμηση, χωρίς φάσεις): απαλή ζώνη σε όλο το ύψος.
  final List<(double, double)> gaps;
  final Color gapColor;

  // Από πάνω προς τα κάτω: ξύπνιος, REM, ελαφρύς, βαθύς.
  static const _rows = ['AWAKE', 'REM', 'LIGHT', 'DEEP'];

  @override
  void paint(Canvas canvas, Size size) {
    final rowH = size.height / _rows.length;
    final barH = math.min(rowH * 0.8, 12.0);
    double centerY(int row) => rowH * row + rowH / 2;

    for (final (a, b) in gaps) {
      final left = a.clamp(0.0, 1.0) * size.width;
      final right = b.clamp(0.0, 1.0) * size.width;
      if (right - left < 1) continue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(left, 0, right, size.height), const Radius.circular(6)),
        Paint()..color = gapColor,
      );
    }

    final guidePaint = Paint()
      ..color = guide
      ..strokeWidth = 1;
    for (var i = 0; i < _rows.length; i++) {
      final y = centerY(i);
      for (double x = 0; x < size.width; x += 6) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 2, size.width), y), guidePaint);
      }
    }

    final link = Paint()
      ..color = connector
      ..strokeWidth = 1.2;
    (double, int)? previous;
    for (final (a, b, name) in parts) {
      final row = _rows.indexOf(name);
      if (row < 0) continue;
      final left = a.clamp(0.0, 1.0) * size.width;
      final right = math.max(b.clamp(0.0, 1.0) * size.width, left + 2);
      if (previous != null && (left - previous.$1).abs() < 2 && previous.$2 != row) {
        canvas.drawLine(Offset(left, centerY(previous.$2)), Offset(left, centerY(row)), link);
      }
      final y = centerY(row) - barH / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(left, y, right, y + barH), Radius.circular(barH / 2.5)),
        Paint()..color = stageColor(name),
      );
      previous = (right, row);
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
                  stageColorOf(context, s.name),
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

/// Υπόμνημα φάσεων σε πλέγμα 2×2: χρώμα, όνομα, διάρκεια, ποσοστό του πραγματικού ύπνου (το «ξύπνιος» μόνο σε λεπτά).
class StageLegend extends StatelessWidget {
  const StageLegend({super.key, required this.night, this.onBlue = false});
  final Night night;
  final bool onBlue;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final main = onBlue ? Colors.white : c.text;
    final sub = onBlue ? Colors.white.withValues(alpha: 0.7) : c.textSecondary;

    Widget item(String name) {
      final m = night.stageMinutes[name] ?? 0;
      final pct = night.stagePct(name)?.round();
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: stageColorOf(context, name), borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pct == null ? stageLabel(name) : '${stageLabel(name)} · $pct%',
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
  const Sparkline({super.key, required this.values, required this.color, this.height = 34, this.minRange = 0});
  final List<double> values;
  final Color color;
  final double height;

  /// Ελάχιστο εύρος του κάθετου άξονα (στις μονάδες της τιμής), όπως στο [LineChart]: ο φυσιολογικός θόρυβος μιας μέρας
  /// (π.χ. 0,2 kg στο βάρος) να μη γεμίζει όλο το ύψος και να μοιάζει με μεγάλη αλλαγή (round 1, U1a-20).
  final double minRange;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _SparkPainter(values, color, minRange: minRange)),
    );
  }
}

/// Τα όρια του κάθετου άξονα ενός μικρού γραφήματος: ελάχιστο εύρος [minRange] γύρω από τη μέση των τιμών.
(double, double) sparkRange(List<double> values, double minRange) {
  var lo = values.reduce(math.min);
  var hi = values.reduce(math.max);
  if (hi - lo < minRange) {
    final mid = (hi + lo) / 2;
    lo = mid - minRange / 2;
    hi = mid + minRange / 2;
  }
  if (hi - lo < 1e-6) {
    lo -= 1;
    hi += 1;
  }
  return (lo, hi);
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color, {this.minRange = 0});
  final List<double> values;
  final Color color;
  final double minRange;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final (lo, hi) = sparkRange(values, minRange);
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

/// Μέγεθος γραμμάτων στα γραφήματα: ακολουθεί το μέγεθος γραμμάτων του συστήματος, από 1× ως 1,6× (round 1, U1a-18·
/// πριν έμενε 10–12 px και με γράμματα 2×). Η αναφορά για γιατρό ζωγραφίζεται χωρίς μεγέθυνση, άρα μένει ίδια.
double chartTextScale(BuildContext context) =>
    (MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling).clamp(minScaleFactor: 1, maxScaleFactor: 1.6).scale(10) / 10;

/// Βήματα άξονα για διάρκειες σε λεπτά (τέταρτα, μισάωρα, ώρες).
const minuteTickSteps = <double>[15, 30, 60, 120, 180, 240, 360];

/// «Στρογγυλό» βήμα άξονα: το μικρότερο 1, 2 ή 5 × 10ⁿ (ή, με [steps], το πρώτο από αυτά) που είναι ≥ [raw].
double niceStep(double raw, [List<double>? steps]) {
  if (!raw.isFinite || raw <= 0) return 1;
  if (steps != null && steps.isNotEmpty) {
    for (final s in steps) {
      if (s >= raw) return s;
    }
    return (raw / steps.last).ceilToDouble() * steps.last;
  }
  final p = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  for (final m in const [1.0, 2.0, 5.0]) {
    if (m * p >= raw * (1 - 1e-9)) return m * p;
  }
  return 10 * p;
}

/// Ο κάθετος άξονας ενός γραφήματος (round 1, U1b-09, U1a-19β): γραμμές σε ίσες αποστάσεις και σε «στρογγυλές» τιμές
/// ([niceStep], τουλάχιστον [minStep]) που περιέχουν το [lo]…[hi], με 2 ως [maxIntervals] διαστήματα (το πιο σφιχτό).
/// Πριν οι τρεις ετικέτες ήταν στρογγυλεμένες τυχαίες τιμές: «92 · 95 · 97» σε ίσες αποστάσεις, με το «95» στο 94,5.
/// Επιστρέφει (κάτω τιμή, βήμα, διαστήματα)· πάνω τιμή = κάτω + βήμα × διαστήματα.
(double, double, int) chartAxis(double lo, double hi, {int maxIntervals = 2, List<double>? steps, double minStep = 0}) {
  if (!(hi > lo)) hi = lo + math.max(minStep, 1.0);
  (double, double, int)? best;
  for (var n = 2; n <= math.max(2, maxIntervals); n++) {
    var step = math.max(niceStep((hi - lo) / n, steps), minStep);
    var a = (lo / step).floorToDouble() * step;
    for (var i = 0; i < 12 && a + n * step < hi - step * 1e-9; i++) {
      step = math.max(niceStep(step * 1.000001, steps), minStep);
      a = (lo / step).floorToDouble() * step;
    }
    if (best == null || n * step < best.$3 * best.$2 - 1e-9) best = (a, step, n);
  }
  return best!;
}

/// Κενά πολύ μεγαλύτερα από τη συνηθισμένη απόσταση των τιμών (round 1, U1b-10): πάνω από 3 μέρες ΚΑΙ πάνω από το
/// τριπλάσιο της μεσαίας απόστασης. Εκεί η γραμμή κόβεται· πριν ένα κενό τριών εβδομάδων ζωγραφιζόταν σαν μετρημένη
/// ευθεία. Δίνει τη μέρα της πρώτης τιμής μετά από κάθε τέτοιο κενό (τιμές παλιότερη πρώτη).
List<DateTime> longGaps(List<(DateTime, double)> points) {
  if (points.length < 3) return const [];
  final gaps = [for (var i = 1; i < points.length; i++) daysBetween(points[i - 1].$1, points[i].$1)];
  final positive = [for (final g in gaps) if (g > 0) g]..sort();
  if (positive.isEmpty) return const [];
  final limit = math.max(3, 3 * positive[positive.length ~/ 2]);
  return [for (var i = 1; i < points.length; i++) if (gaps[i - 1] > limit) points[i].$1];
}

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
          card: c.card,
          scale: chartTextScale(context),
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
    required this.card,
    this.scale = 1,
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
  final Color card;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final labelHeight = 20.0 * scale;
    final topPad = 22.0 * scale;
    final chartHeight = size.height - labelHeight - topPad;
    final maxV = [...values.whereType<double>(), if (average != null) average!].fold<double>(0, math.max);
    if (maxV <= 0 || chartHeight <= 0) return;

    final slot = size.width / values.length;
    final barWidth = math.min(26.0, slot * 0.62);
    final showEvery = labels.length > 10 ? 2 : 1;
    TextPainter? strongLabel;
    var strongAt = Offset.zero;

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
          final tp = _painter(valueLabel!(v), strongText, 12 * scale, bold: true);
          final x = (cx - tp.width / 2).clamp(0.0, math.max(0.0, size.width - tp.width)).toDouble();
          strongLabel = tp;
          strongAt = Offset(x, math.max(0.0, topPad + chartHeight - h - 4 - tp.height));
        }
      }
      final fromEnd = values.length - 1 - i;
      if (i < labels.length && fromEnd % showEvery == 0) {
        _text(canvas, labels[i], Offset(cx, size.height - labelHeight + 4 * scale), strong ? strongText : text, 11 * scale,
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
    // Round 1 (U1a-10): η τιμή της τελευταίας ράβδου τελευταία, πάνω σε πλάκα στο χρώμα της κάρτας· πριν έπεφτε πάνω
    // στις γειτονικές ράβδους (όταν η τελευταία νύχτα ήταν μικρότερη) και στη γραμμή του μέσου όρου.
    if (strongLabel != null) _plate(canvas, strongLabel, strongAt, card);
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
    this.minRange = 1,
    this.levels = const [],
    this.reference,
    this.from,
    this.to,
    this.breaks = const [],
    this.tickSteps,
  });

  /// Αλλαγές πηγής ή ορισμού (μέρα, σύντομη ετικέτα, π.χ. «Oura»): η γραμμή και το γέμισμα κόβονται εκεί, και μια
  /// λεπτή κάθετη γραμμή με την ετικέτα δείχνει την αλλαγή (έλεγχος 4, review M1: ποτέ μία γραμμή πάνω από δύο
  /// συσκευές). Η γραμμή κόβεται και σε κενό πολύ μεγαλύτερο από τη συνηθισμένη απόσταση των τιμών ([longGaps]).
  final List<(DateTime, String)> breaks;

  /// Το διάστημα του οριζόντιου άξονα (π.χ. οι 90 μέρες της αναφοράς), ίδιο για όλα τα γραφήματα μιας σελίδας, ώστε
  /// να συγκρίνονται τα σχήματα (τρίτος κλινικός έλεγχος C8/F6). Χωρίς αυτά: από την πρώτη ως την τελευταία τιμή.
  final DateTime? from;
  final DateTime? to;

  /// Οριζόντιες διακεκομμένες γραμμές ανά διάστημα (π.χ. η μεσαία τιμή κάθε περιόδου στις Τάσεις).
  final List<(DateTime, DateTime, double, Color)> levels;

  /// Γραμμή αναφοράς (τιμή, ετικέτα, χρώμα): ΔΙΑΣΤΙΚΤΗ σε όλο το πλάτος, με την ετικέτα στο δεξί περιθώριο (στη θέση
  /// των τιμών του άξονα), ώστε να ξεχωρίζει από τις διακεκομμένες [levels] (δεύτερος κλινικός έλεγχος M5) και να μην
  /// κάθεται πάνω στις τιμές (round 1, U1b-02).
  final (double, String, Color)? reference;

  /// Ελάχιστο εύρος του κάθετου άξονα, ώστε μικρές διαφορές να μη φαίνονται τεράστιες.
  final double minRange;

  /// Επιτρεπτά βήματα του κάθετου άξονα (π.χ. [minuteTickSteps] για διάρκειες σε λεπτά)· χωρίς αυτά 1, 2 ή 5 × 10ⁿ.
  final List<double>? tickSteps;
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
          minRange: minRange,
          levels: levels,
          reference: reference,
          from: from,
          to: to,
          breaks: breaks,
          tickSteps: tickSteps,
          scale: chartTextScale(context),
        ),
      ),
    );
  }
}

/// Τα κομμάτια της γραμμής: νέο κομμάτι από την πρώτη τιμή την ή μετά από κάθε [breaks] (τιμές παλιότερη πρώτη).
List<List<(DateTime, double)>> lineSegments(List<(DateTime, double)> points, List<DateTime> breaks) {
  final cuts = [...breaks]..sort();
  final out = <List<(DateTime, double)>>[];
  var seg = -1;
  for (final p in points) {
    final k = cuts.where((c) => !p.$1.isBefore(c)).length;
    if (out.isEmpty || k != seg) {
      out.add([]);
      seg = k;
    }
    out.last.add(p);
  }
  return out;
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.levels,
    required this.points,
    required this.color,
    required this.text,
    required this.strongText,
    required this.grid,
    required this.card,
    required this.format,
    required this.dateLabel,
    required this.minRange,
    this.reference,
    this.from,
    this.to,
    this.breaks = const [],
    this.tickSteps,
    this.scale = 1,
  });

  final List<(DateTime, String)> breaks;
  final DateTime? from;
  final DateTime? to;
  final double minRange;
  final List<(DateTime, DateTime, double, Color)> levels;
  final (double, String, Color)? reference;
  final List<(DateTime, double)> points;
  final Color color;
  final Color text;
  final Color strongText;
  final Color grid;
  final Color card;
  final String Function(double) format;
  final String Function(DateTime) dateLabel;
  final List<double>? tickSteps;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const left = 4.0;
    final right = 44.0 * scale;
    final bottom = 22.0 * scale;
    final top = 26.0 * scale;
    final w = size.width - left - right;
    final h = size.height - bottom - top;
    if (w <= 0 || h <= 0) return;

    final refs = [if (reference != null) reference!.$1];
    final all = [...points.map((p) => p.$2), ...levels.map((l) => l.$3), ...refs];
    var minV = all.reduce(math.min);
    var maxV = all.reduce(math.max);
    final nonNegative = minV >= 0;
    if (maxV - minV < minRange) {
      final mid = (maxV + minV) / 2;
      minV = mid - minRange / 2;
      maxV = mid + minRange / 2;
    }
    final pad = (maxV - minV) * 0.1;
    minV -= pad;
    maxV += pad;
    if (nonNegative && minV < 0) minV = 0;
    // Άξονας σε στρογγυλές τιμές (U1b-09)· με ετικέτες ακέραιων (π.χ. παλμοί) ποτέ βήμα κάτω από 1, αλλιώς δύο γραμμές θα
    // έγραφαν την ίδια τιμή.
    final integer = format(0.5) == format(1) || format(0.5) == format(0);
    final (axisLo, step, intervals) =
        chartAxis(minV, maxV, maxIntervals: h >= 72 ? 3 : 2, steps: tickSteps, minStep: integer ? 1 : 0);
    minV = axisLo;
    maxV = axisLo + step * intervals;

    final ranged = from != null && to != null;
    final t0 = (ranged ? from! : points.first.$1).millisecondsSinceEpoch.toDouble();
    final t1 = (ranged ? to! : points.last.$1).millisecondsSinceEpoch.toDouble();
    final span = math.max(t1 - t0, 1.0);

    double yOf(double v) => top + h * (1 - (v - minV) / (maxV - minV));
    Offset at((DateTime, double) p) {
      final x = points.length == 1 && !ranged ? left + w / 2 : left + w * ((p.$1.millisecondsSinceEpoch - t0) / span);
      return Offset(x, yOf(p.$2));
    }

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final refY = reference == null ? null : yOf(reference!.$1);
    for (var i = 0; i <= intervals; i++) {
      final y = top + h * (1 - i / intervals);
      canvas.drawLine(Offset(left, y), Offset(left + w, y), gridPaint);
      // Η ετικέτα της γραμμής αναφοράς παίρνει τη θέση μιας τιμής του άξονα που θα έπεφτε πάνω της.
      if (refY != null && (refY - y).abs() < 13 * scale) continue;
      _textLeft(canvas, format(minV + step * i), Offset(left + w + 8, y - 7 * scale), text, 11 * scale);
    }

    // Ένα κομμάτι για κάθε πηγή/ορισμό ([breaks]) και κάθε μεγάλο κενό ([longGaps]): ποτέ γραμμή ή γέμισμα από πάνω τους.
    final segments = lineSegments(points, [for (final b in breaks) b.$1, ...longGaps(points)]);
    final path = Path();
    for (final seg in segments) {
      final segPath = Path();
      for (var i = 0; i < seg.length; i++) {
        final o = at(seg[i]);
        if (i == 0) {
          segPath.moveTo(o.dx, o.dy);
        } else {
          segPath.lineTo(o.dx, o.dy);
        }
      }
      path.addPath(segPath, Offset.zero);
      if (seg.length > 1) {
        final fill = Path.from(segPath)
          ..lineTo(at(seg.last).dx, top + h)
          ..lineTo(at(seg.first).dx, top + h)
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
    }
    for (final (day, label) in breaks) {
      final x = at((day, minV)).dx;
      if (x < left || x > left + w) continue;
      final rule = Paint()
        ..color = text
        ..strokeWidth = 1;
      for (var y = top - 4; y < top + h; y += 6) {
        canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 3, top + h)), rule);
      }
      _textLeft(canvas, label, Offset(x + 3, top - 18 * scale), text, 10 * scale);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = levels.isEmpty ? color : color.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = points.length > 60 ? 1.5 : (levels.isEmpty ? 2.5 : 2)
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final dot = Paint()..color = color;
    if (points.length <= 31) {
      for (final p in points) {
        canvas.drawCircle(at(p), 2.5, dot);
      }
    } else {
      // Μια τιμή μόνη της ανάμεσα σε δύο μεγάλα κενά δεν έχει γραμμή: χωρίς κουκκίδα δεν θα φαινόταν (U1b-10).
      for (final seg in segments) {
        if (seg.length == 1) canvas.drawCircle(at(seg.first), 2.5, dot);
      }
    }
    for (final l in levels) {
      final a = at((l.$1, l.$3));
      final b = at((l.$2, l.$3));
      final x0 = a.dx.clamp(left, left + w).toDouble();
      final x1 = b.dx.clamp(left, left + w).toDouble();
      final dash = Paint()
        ..color = l.$4
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round;
      for (var x = x0; x < x1; x += 9) {
        canvas.drawLine(Offset(x, a.dy), Offset(math.min(x + 5, x1), a.dy), dash);
      }
    }
    if (reference != null && refY != null) {
      final (_, label, col) = reference!;
      final refDot = Paint()..color = col;
      for (var x = left; x <= left + w; x += 5) {
        canvas.drawCircle(Offset(x, refY), 1.1, refDot);
      }
      // Στο δεξί περιθώριο, όπως οι τιμές του άξονα (U1b-02): πριν καθόταν πάνω στις πιο πρόσφατες τιμές.
      final refTp = _painter(label, col, 10.5 * scale, bold: true);
      refTp.paint(canvas, Offset(left + w + 8, refY - refTp.height / 2));
    }
    final last = at(points.last);
    canvas.drawCircle(last, 6, Paint()..color = card);
    canvas.drawCircle(last, 4.5, Paint()..color = color);
    // Round 1 (U1a-10, U1b-02): η τελευταία τιμή πάνω σε πλάκα στο χρώμα της κάρτας· κάτω από το σημείο όταν η γραμμή
    // έρχεται από ψηλότερα (αλλιώς την έκοβε), αριστερά του όταν από κάτω δεν χωρά.
    final valueTp = _painter(format(points.last.$2), strongText, 12 * scale, bold: true);
    var lx = math.min(last.dx, left + w - 16) - valueTp.width / 2;
    var ly = last.dy - 9 - valueTp.height;
    if (points.length > 1 && at(points[points.length - 2]).dy < last.dy - 2) {
      ly = last.dy + 9;
      if (ly + valueTp.height > top + h) {
        lx = last.dx - 10 - valueTp.width;
        ly = last.dy - valueTp.height / 2;
      }
    }
    lx = lx.clamp(0.0, math.max(0.0, size.width - valueTp.width)).toDouble();
    ly = ly.clamp(0.0, math.max(0.0, top + h - valueTp.height)).toDouble();
    _plate(canvas, valueTp, Offset(lx, ly), card);

    _textLeft(canvas, dateLabel(ranged ? from! : points.first.$1), Offset(left, size.height - bottom + 6 * scale), text,
        11 * scale);
    if (points.length > 1 || ranged) {
      final label = dateLabel(ranged ? to! : points.last.$1);
      final dateTp = _painter(label, text, 11 * scale);
      dateTp.paint(canvas, Offset(left + w - dateTp.width, size.height - bottom + 6 * scale));
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => true;
}

/// Ετικέτα πάνω σε μικρή πλάκα στο χρώμα της κάρτας: διαβάζεται ακόμα κι όταν από κάτω της περνά γραμμή ή ράβδος.
void _plate(Canvas canvas, TextPainter tp, Offset at, Color card) {
  canvas.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(at.dx - 3, at.dy - 1, tp.width + 6, tp.height + 2), const Radius.circular(6)),
    Paint()..color = card,
  );
  tp.paint(canvas, at);
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
    this.primary = false,
  });

  final String title;
  final String text;
  final IconData? icon;
  final Color? color;
  final String? buttonText;
  final VoidCallback? onPressed;

  /// Το κουμπί είναι η ΜΙΑ ενέργεια της κάρτας (π.χ. «Σύνδεση ξανά» σε κάρτα σφάλματος): γεμάτο, όχι περίγραμμα
  /// (round 1, U2a-21: στο σκοτεινό θέμα το περίγραμμα είχε 1,23:1 και το κουμπί έμοιαζε δευτερεύον).
  final bool primary;

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
            // Round 1 (U4-14 γ): ίδιος τίτλος με κάθε τίτλο μέσα σε κάρτα ([SectionLabel]).
            SectionLabel(title),
          const SizedBox(height: 10),
          Text(text, style: TextStyle(color: c.textSecondary, fontSize: 14.5, height: 1.4)),
          if (buttonText != null && onPressed != null) ...[
            const SizedBox(height: 14),
            primary
                ? FilledButton(onPressed: onPressed, child: Text(buttonText!))
                : OutlinedButton(onPressed: onPressed, child: Text(buttonText!)),
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

/// Τίτλος ομάδας καρτών πάνω από την κάρτα (σχέδια 9/11): μικρά κεφαλαία χωρίς τόνους, γκρι, 24 dp πάνω.
class GroupLabel extends StatelessWidget {
  const GroupLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Row(children: [
        Expanded(
          child: Text(upperGr(text),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: .6, color: c.textSecondary)),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// Γραμμή που ανοίγει άλλη οθόνη, μέσα σε κάρτα: εικονίδιο, τίτλος, μία-δύο γραμμές εξήγηση, «›».
class NavRow extends StatelessWidget {
  const NavRow({super.key, required this.icon, required this.color, required this.title, this.text, required this.onTap, this.line = false});
  final IconData icon;
  final Color color;
  final String title;
  final String? text;
  final VoidCallback onTap;

  /// Λεπτή γραμμή από κάτω (όταν ακολουθεί κι άλλη γραμμή στην ίδια κάρτα).
  final bool line;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: line ? BoxDecoration(border: Border(bottom: BorderSide(color: c.hairline))) : null,
        // Round 1 (U4-14 β): ίδια μεγέθη με τη γραμμή των Ρυθμίσεων (SettingsRow), που κάνει την ίδια δουλειά.
        child: Row(children: [
          IconBadge(icon, color, size: 38),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
              if (text != null) ...[
                const SizedBox(height: 2),
                Text(text!, style: TextStyle(fontSize: 13.5, height: 1.35, color: c.textSecondary)),
              ],
            ]),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: c.textTertiary),
        ]),
      ),
    );
  }
}

/// Ετικέτα αξιοπιστίας δίπλα στον τίτλο (σχέδια 9/11): «εκτίμηση», «ενδεικτικό», «μέτρηση». Η εξήγηση είναι στο ⓘ.
class LabelTag extends StatelessWidget {
  const LabelTag(this.text, {super.key, this.warn = false, this.strong = false});
  final String text;

  /// «ενδεικτικό»: κεχριμπάρι.
  final bool warn;

  /// «μέτρηση»: σκούρο περίγραμμα.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final color = warn ? c.warn : (strong ? c.text : c.textSecondary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: warn ? c.warnBg : null,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: warn ? c.warnLine : (strong ? c.text : c.hairline), width: strong ? 1.5 : 1),
      ),
      child: Text(text, maxLines: 1, softWrap: false, style: TextStyle(fontSize: 13, height: 1.5, fontWeight: strong ? FontWeight.w700 : FontWeight.w500, color: color)),
    );
  }
}

/// Οριζόντια μπάρα με κομμάτια (φάσεις ύπνου, μακροθρεπτικά): μικρά κενά ανάμεσα, στρογγυλές άκρες.
class StackedBar extends StatelessWidget {
  const StackedBar({super.key, required this.parts, this.height = 12});
  final List<(double, Color)> parts;
  final double height;

  @override
  Widget build(BuildContext context) {
    final shown = [for (final p in parts) if (p.$1 > 0) p];
    if (shown.isEmpty) return SizedBox(height: height);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        // Round 1 (U2a-01): «stretch», αλλιώς τα κομμάτια (ColoredBox χωρίς παιδί) είχαν ύψος 0 και η μπάρα δεν φαινόταν.
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(flex: (shown[i].$1 * 100).round().clamp(1, 1 << 30), child: ColoredBox(color: shown[i].$2)),
          ],
        ]),
      ),
    );
  }
}

/// Κεφαλίδα κάρτας με ετικέτες/ⓘ δεξιά. Με πολύ μεγάλα γράμματα οι ετικέτες πάνε στην από κάτω γραμμή, για να
/// μη στριμώχνεται ο τίτλος σε σπασμένες λέξεις (σχέδια 9/11).
class TitleRow extends StatelessWidget {
  const TitleRow({super.key, required this.header, this.trailing = const []});
  final Widget header;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    if (trailing.isEmpty) return header;
    if (veryLargeText(context)) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        const SizedBox(height: 4),
        Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: trailing),
      ]);
    }
    return Row(children: [Expanded(child: header), ...trailing]);
  }
}

/// «7 μέρες», «30 μέρες», «3 μήνες», «1 χρόνος» (σχέδια 9/11: ένα λεξιλόγιο για κάθε επιλογέα περιόδου).
(String, String) periodWords(int days) => switch (days) {
      90 => ('3', 'μήνες'),
      365 => ('1', 'χρόνος'),
      _ => ('$days', 'μέρες'),
    };

/// Ο επιλογέας περιόδου της εφαρμογής (σχέδια 9/11, οδηγός): γκρι πλαίσιο, λευκή επιλογή με γράμματα στο χρώμα
/// της ενότητας (για να μη μοιάζει με τις καρτέλες). Από 1,3× γράμματα: αριθμός πάνω, λέξη κάτω· ποτέ κομμένο.
class PeriodPicker<T> extends StatelessWidget {
  const PeriodPicker({super.key, required this.values, required this.days, required this.selected, required this.onChanged, required this.color, this.keyOf});
  final List<T> values;
  final int Function(T) days;
  final T selected;
  final ValueChanged<T> onChanged;

  /// Χρώμα της ενότητας για την επιλογή.
  final Color color;
  final String Function(T)? keyOf;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final twoLines = MediaQuery.textScalerOf(context).scale(10) >= 12.5;
    return Container(
      padding: const EdgeInsets.all(4),
      // Round 1 (U4-14 θ): ίδιες γωνίες με τις καρτέλες (16 έξω, 12 μέσα).
      decoration: BoxDecoration(color: c.dark ? c.background : c.hairline, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        for (final v in values)
          Expanded(
            child: () {
              final on = v == selected;
              final (n, w) = periodWords(days(v));
              final st = TextStyle(fontFamily: fontFamily, fontSize: 15, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? color : c.textSecondary);
              return Semantics(
                selected: on,
                button: true,
                child: Material(
                  color: on ? c.card : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  elevation: on && !c.dark ? 1 : 0,
                  shadowColor: const Color(0x220F172A),
                  child: InkWell(
                    key: keyOf == null ? null : ValueKey(keyOf!(v)),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onChanged(v),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          child: twoLines
                              ? Column(mainAxisSize: MainAxisSize.min, children: [
                                  Text(n, style: st.copyWith(height: 1.1)),
                                  FittedBox(fit: BoxFit.scaleDown, child: Text(w, maxLines: 1, style: st.copyWith(height: 1.1))),
                                ])
                              : FittedBox(fit: BoxFit.scaleDown, child: Text('$n $w', maxLines: 1, style: st)),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }(),
          ),
      ]),
    );
  }
}
