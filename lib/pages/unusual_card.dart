import 'package:flutter/material.dart';

import '../format.dart';
import '../history.dart';
import '../shown.dart';
import '../sources.dart';
import '../theme.dart';
import '../trends.dart';
import '../unusual.dart';
import '../widgets.dart';

/// «Εκτός συνηθισμένου»: φαίνεται στη Σήμερα μόνο όταν ξεφεύγουν μαζί οι παλμοί ύπνου και η θερμοκρασία.
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
                      r.previousDayOff ? 'Σήμερα το πρωί ·\u00A0και χθες' : 'Σήμερα το πρωί',
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
              'Συμβαίνει συχνά μετά από λίγο ύπνο, αλκοόλ, βαρύ φαγητό ή φαγητό αργά το βράδυ, έντονη άσκηση, ζεστό δωμάτιο, '
              'αλλαγή στο κάπνισμα ή στα φάρμακα, ή όταν αρχίζει κάποιο κρυολόγημα. Δεν είναι διάγνωση. '
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
                'Συνήθως = η μεσαία τιμή των $usualNights πιο πρόσφατων μετρήσεων, ίδια με όλη την εφαρμογή· οι '
                'συνηθισμένες διακυμάνσεις σου από τις $unusualBaselineDays προηγούμενες μέρες (τουλάχιστον '
                '$unusualMinBaseline με μέτρηση). Ένας δείκτης μετράει μόνο αν ξεφύγει '
                'και πάνω από ένα ελάχιστο ('
                '${r.signals.any((s) => s.source == Source.oura) ? 'παλμοί ύπνου +3 bpm, απόκλιση θερμοκρασίας +0,4 °C, ετοιμότητα του Oura −10' : 'παλμοί +3 bpm, δέρμα +0,4 °C, Energy Score −10'}) '
                'και πάνω από τις συνηθισμένες μέρα-με-μέρα διακυμάνσεις σου. '
                // Έλεγχος 9/11 (03-Χ2): στην πράξη ένας δείκτης ξεφεύγει τυχαία ~4% των πρωινών (προσομοίωση), όχι 2,3%.
                'Η κάρτα βγαίνει μόνο όταν ξεφεύγουν και οι παλμοί και η θερμοκρασία το ίδιο πρωί, γιατί ένας δείκτης μόνος '
                'του ξεφεύγει τυχαία περίπου 1 στις 20 νύχτες. ${r.signals.any((s) => s.source == Source.oura) ? 'Η ετοιμότητα' : 'Το Energy Score'} βγαίνει '
                'εν μέρει από τους ίδιους παλμούς και τη θερμοκρασία, γι\' αυτό δεν μετρά ως ξεχωριστός δείκτης.'
                '${r.signals.any((s) => s.source == Source.oura && s.rule.key == K.skinTemp) ? ' Η θερμοκρασία του Oura '
                    'είναι ήδη απόκλιση από το συνηθισμένο σου, όπως τη δίνει το Oura· φαίνεται όπως είναι.' : ''}',
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
    final oura = s.source == Source.oura;
    // Θερμοκρασία: ΠΑΝΤΑ ως απόκλιση από το συνηθισμένο, ποτέ απόλυτη θερμοκρασία καρπού (π.χ. «35,9 °C» διαβαζόταν
    // ως θερμοκρασία σώματος· δεύτερος κλινικός έλεγχος M7, ίδιος κανόνας με τη Σήμερα, L5).
    final deviation = def.key == K.skinTemp;
    // Η διαφορά των νούμερων όπως φαίνονται (έλεγχος υπολογισμών C6): «62 · συνήθως 58 · +4», ποτέ «+3».
    // Oura θερμοκρασία: το «συνήθως» είναι 0 (F2), άρα το νούμερο είναι η απόκλιση του ίδιου του Oura.
    final diff = shownDiff(s.value, s.usual, def.digits);
    final diffText = signedShown(diff, def.digits);
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
                Text(metricLabel(def, s.source), style: TextStyle(fontSize: 14, color: c.textSecondary)),
                Text(
                  deviation ? '${signedDec(diff, def.digits)} °C' : def.format(s.value),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text, fontFeatures: tabular),
                ),
                Text(
                  deviation
                      ? '${oura ? ouraTempDeviationLabel : 'απόκλιση από το συνηθισμένο σου'} ·\u00A0όχι θερμοκρασία σώματος'
                      : 'συνήθως ${def.format(s.usual)}${oura ? ' ·\u00A0Oura' : ''}',
                  style: TextStyle(fontSize: 12.5, color: c.textTertiary, fontFeatures: tabular),
                ),
              ],
            ),
          ),
          // Θερμοκρασία: χωρίς «χάπι», γιατί το νούμερο είναι ήδη η διαφορά (UX U6: «+0,8 °C» δύο φορές). Αλλιώς ένας
          // κανόνας παντού (F1): «Όπως συνήθως» μόνο για διαφορά 0, ακόμα κι αν ο δείκτης δεν «ξεφεύγει».
          if (!deviation)
            TrendPill(
              diff == 0 ? asUsualText : '$diffText${def.unit.isEmpty ? '' : def.unit == '%' ? '%' : ' ${def.unit}'}',
              kind: TrendKind.neutral,
            ),
        ],
      ),
    );
  }
}
