import 'package:flutter/material.dart';

import '../oxygen_note.dart';
import '../theme.dart';

/// Οι σημειώσεις κάτω από το οξυγόνο της νύχτας (Ύπνος, Καρδιά): τα μηνύματα όταν ισχύουν, και πάντα τα
/// σημάδια κινδύνου. Ήπιο, ζεστό χρώμα· όχι «κόκκινος συναγερμός» (ίδιο με την κάρτα «Εκτός συνηθισμένου»).
class OxygenNotes extends StatelessWidget {
  const OxygenNotes({super.key, required this.guidance});
  final OxygenGuidance guidance;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final style = TextStyle(color: c.text, fontSize: 13.5, height: 1.4);
    return Column(
      key: const ValueKey('oxygen-notes'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in guidance.messages) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.tint(c.move), borderRadius: BorderRadius.circular(14)),
            child: Text(m, style: style),
          ),
          const SizedBox(height: 8),
        ],
        Text(oxygenRedFlagText, style: style.copyWith(color: c.textSecondary, fontSize: 13)),
      ],
    );
  }
}
