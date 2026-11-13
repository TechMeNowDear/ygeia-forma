import 'package:flutter/material.dart';

import '../sources.dart';
import '../theme.dart';

/// Η μικρή ετικέτα πηγής σε κάθε κάρτα: «Oura», «Ρολόι», «InBody». Κάθε κάρτα έχει μία μόνο πηγή.
class SourceTag extends StatelessWidget {
  const SourceTag(this.source, {super.key, this.onDark = false, this.label});
  final Source source;
  final bool onDark;

  /// Άλλο όνομα από το [sourceName] (π.χ. «Samsung Health» για τα βήματα, που ενώνουν ρολόι και κινητό).
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final fg = onDark ? Colors.white.withValues(alpha: 0.92) : c.textSecondary;
    final bg = onDark ? Colors.white.withValues(alpha: 0.14) : c.background;
    return Semantics(
      label: 'Πηγή: ${label ?? sourceDevice(source)}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: onDark ? null : Border.all(color: c.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon(source), size: 12, color: fg),
            const SizedBox(width: 4),
            Text(label ?? sourceName(source), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
          ],
        ),
      ),
    );
  }

  static IconData _icon(Source s) => switch (s) {
        Source.oura => Icons.radio_button_unchecked_rounded,
        Source.watch => Icons.watch_rounded,
        Source.scale => Icons.monitor_weight_outlined,
        Source.none => Icons.remove_rounded,
      };
}

/// Μικρή σημείωση «εκτίμηση της Oura» δίπλα σε βαθμολογίες και φάσεις.
class EstimateNote extends StatelessWidget {
  const EstimateNote(this.text, {super.key, this.onDark = false});
  final String text;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Text(
      text,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        color: onDark ? Colors.white.withValues(alpha: 0.8) : c.textSecondary,
      ),
    );
  }
}
