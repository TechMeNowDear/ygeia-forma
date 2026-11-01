import 'package:flutter/material.dart';

import '../format.dart';
import '../theme.dart';
import '../unusual.dart';
import '../widgets.dart';

/// «Εκτός συνηθισμένου»: φαίνεται στη Σήμερα μόνο όταν ξεφεύγουν τουλάχιστον 2 δείκτες.
class UnusualCard extends StatefulWidget {
  const UnusualCard({super.key, required this.result});
  final UnusualResult result;

  @override
  State<UnusualCard> createState() => _UnusualCardState();
}

class _UnusualCardState extends State<UnusualCard> {
  bool _method = false;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final r = widget.result;
    final accent = c.move; // ζεστό, ήπιο χρώμα· όχι «κόκκινος συναγερμός»
    final title = r.offCount == 3 ? 'Τρεις δείκτες εκτός συνηθισμένου' : 'Δύο δείκτες εκτός συνηθισμένου';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBadge(Icons.info_outline_rounded, accent, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text, letterSpacing: -0.2),
                    ),
                    Text(
                      r.previousDayOff ? 'Σήμερα το πρωί · και χθες' : 'Σήμερα το πρωί',
                      style: TextStyle(fontSize: 13, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < r.signals.length; i++) ...[
            if (i > 0) const Hairline(vertical: 0),
            _SignalRow(s: r.signals[i], accent: accent),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.tint(accent), borderRadius: BorderRadius.circular(16)),
            child: Text(
              'Συμβαίνει συχνά μετά από λίγο ύπνο, αλκοόλ, βαρύ ή αργό φαγητό, έντονη άσκηση, ζεστό δωμάτιο, '
              'αλλαγή στο κάπνισμα ή στα φάρμακα, ή στην αρχή μιας ίωσης. Δεν είναι διάγνωση. '
              'Αν νιώθεις άρρωστος ή κρατήσει μέρες, ρώτα γιατρό. '
              'Αν έχεις πόνο στο στήθος, δύσπνοια, λιποθυμία ή έντονο φτερούγισμα, μην περιμένεις: 166 ή 112.',
              style: TextStyle(fontSize: 13.5, height: 1.45, color: c.text),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _method = !_method),
              icon: Icon(_method ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20),
              label: const Text('Πώς υπολογίστηκε'),
            ),
          ),
          if (_method)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(16)),
              child: Text(
                'Συνηθισμένο σου = η μεσαία τιμή των $unusualBaselineDays προηγούμενων ημερών '
                '(τουλάχιστον $unusualMinBaseline με μέτρηση). Ένας δείκτης μετράει μόνο αν ξεφύγει '
                'και πάνω από ένα ελάχιστο (παλμοί +3 bpm, δέρμα +0,4 °C, Energy Score −10) '
                'και πάνω από τις συνηθισμένες μέρα-με-μέρα διακυμάνσεις σου. '
                'Η κάρτα βγαίνει μόνο όταν ξεφεύγουν τουλάχιστον δύο το ίδιο πρωί, γιατί ένας μόνος συχνά είναι τυχαίος.',
                style: TextStyle(color: c.textSecondary, fontSize: 13.5, height: 1.45),
              ),
            ),
        ],
      ),
    );
  }
}

class _SignalRow extends StatelessWidget {
  const _SignalRow({required this.s, required this.accent});
  final UnusualSignal s;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final def = s.rule.def;
    final diff = s.value - s.usual;
    final sign = diff >= 0 ? '+' : '−';
    final diffText = def.digits == 0 ? '$sign${diff.abs().round()}' : '$sign${dec(diff.abs(), def.digits)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(
            s.off ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            size: 20,
            color: s.off ? accent : c.textTertiary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(def.label, style: TextStyle(fontSize: 14, color: c.textSecondary)),
                Text(
                  def.format(s.value),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text, fontFeatures: tabular),
                ),
                Text(
                  'συνήθως ${def.format(s.usual)}',
                  style: TextStyle(fontSize: 12.5, color: c.textTertiary, fontFeatures: tabular),
                ),
              ],
            ),
          ),
          TrendPill(
            s.off ? '$diffText${def.unit.isEmpty ? '' : def.unit == '%' ? '%' : ' ${def.unit}'}' : 'Όπως συνήθως',
            kind: TrendKind.neutral,
          ),
        ],
      ),
    );
  }
}
