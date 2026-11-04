import 'package:flutter/material.dart';

import '../oxygen_note.dart';
import '../theme.dart';

/// Οι σημειώσεις κάτω από το οξυγόνο της νύχτας (Ύπνος, Καρδιά): το ΕΝΑ μήνυμα όταν ισχύει, και πάντα τα
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

/// Τι σημαίνει το οξυγόνο του ρολογιού: μία γραμμή και «Τι σημαίνει», που ανοίγει το πλήρες κείμενο
/// ([oxygenAboutText]: όχι ιατρικό οξύμετρο, τεστ άπνοιας, πότε μελέτη ύπνου). Έλεγχος UX U9 (4/11): το ίδιο
/// κείμενο 11 γραμμών σε 4 οθόνες έσπρωχνε τις τιμές κάτω από την οθόνη. Η σημείωση που ισχύει και τα σημάδια
/// κινδύνου μένουν πάντα ανοιχτά ([OxygenNotes]).
class OxygenAbout extends StatefulWidget {
  const OxygenAbout({super.key, this.lead = ''});

  /// Τι δείχνει η κάρτα, πριν από τη σταθερή γραμμή (π.χ. «Μέσο ανά νύχτα και η χαμηλότερη μέτρηση.»).
  final String lead;

  @override
  State<OxygenAbout> createState() => _OxygenAboutState();
}

class _OxygenAboutState extends State<OxygenAbout> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final style = TextStyle(color: c.textSecondary, fontSize: 13.5, height: 1.4);
    return Column(
      key: const ValueKey('oxygen-about'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _open
              ? '${widget.lead.isEmpty ? '' : '${widget.lead} '}$oxygenAboutText'
              : '${widget.lead.isEmpty ? '' : '${widget.lead} '}$oxygenAboutShort',
          style: style,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('oxygen-about-toggle'),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), visualDensity: VisualDensity.compact),
            onPressed: () => setState(() => _open = !_open),
            icon: Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20),
            label: Text(_open ? 'Λιγότερα' : 'Τι σημαίνει'),
          ),
        ),
      ],
    );
  }
}
