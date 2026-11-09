import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../training/session.dart';
import '../../training/walk_stats.dart';
import '../../widgets.dart';

/// Περπάτημα στη σύνοψη (9/11): ρυθμός, βήματα ανά λεπτό, παύσεις.
class WalkExtraCard extends StatelessWidget {
  const WalkExtraCard({super.key, required this.session});
  final Session session;

  static bool shows(Session s) => paceSecPerKm(s) != null || cadence(s) != null || s.pauses.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final pace = paceSecPerKm(session), cad = cadence(session);
    final paused = pausedSec(session);
    Widget stat(String v, String l) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.text)),
            Text(l, style: TextStyle(fontSize: 13, color: c.textSecondary)),
          ]),
        );
    return AppCard(
      key: const ValueKey('walk-extra'),
      child: Row(children: [
        stat(pace == null ? '—' : paceText(pace), 'ανά km'),
        stat(cad == null ? '—' : '$cad', 'βήματα / λεπτό'),
        stat(session.pauses.isEmpty ? '0' : '${session.pauses.length} · ${(paused / 60).ceil()}′', 'παύσεις'),
      ]),
    );
  }
}

/// Ανά χιλιόμετρο (μόνο με GPS).
class KmCard extends StatelessWidget {
  const KmCard({super.key, required this.splits});
  final List<KmSplit> splits;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final head = TextStyle(fontSize: 12.5, color: c.textSecondary);
    final cell = TextStyle(fontSize: 15, color: c.text, fontFeatures: const [FontFeature.tabularFigures()]);
    Widget row(List<Widget> cells, {bool line = true}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: line ? BoxDecoration(border: Border(bottom: BorderSide(color: c.hairline))) : null,
          child: Row(children: [
            SizedBox(width: 56, child: cells[0]),
            Expanded(child: cells[1]),
            SizedBox(width: 92, child: cells[2]),
          ]),
        );
    return AppCard(
      key: const ValueKey('walk-km'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Ανά χιλιόμετρο', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
        const SizedBox(height: 6),
        row([
          Text('km', style: head),
          Text('χρόνος', style: head),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.favorite_rounded, size: 12, color: c.textSecondary),
            const SizedBox(width: 3),
            Text('μέσος', style: head),
          ]),
        ]),
        for (var i = 0; i < splits.length; i++)
          row([
            Text(splits[i].label, style: cell.copyWith(fontWeight: FontWeight.w700)),
            Text(paceText(splits[i].sec), style: cell),
            Text(splits[i].hr == null ? '—' : '${splits[i].hr}',
                key: ValueKey('km-hr-$i'), style: splits[i].hr == null ? cell.copyWith(color: c.textSecondary) : cell.copyWith(fontWeight: FontWeight.w700)),
          ], line: i < splits.length - 1),
        const SizedBox(height: 6),
        Text('Χρόνος χωρίς τις παύσεις. Το τελευταίο κομμάτι, αν είναι μικρότερο από 1 km, δείχνει τον χρόνο του κομματιού.',
            style: TextStyle(fontSize: 12.5, height: 1.35, color: c.textSecondary)),
      ]),
    );
  }
}

/// Πτώση παλμών στο 1ο λεπτό μετά το «Τέλος».
class RecoveryCard extends StatelessWidget {
  const RecoveryCard({super.key, required this.session});
  final Session session;

  /// Με ρολόι #89+ (υπάρχει ενεργός χρόνος) δείχνεται και όταν δεν μετρήθηκε, με τον λόγο.
  static bool shows(Session s) => s.isCardio && (s.hrrEnd != null || s.cardioSec != null);

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final e = session.hrrEnd, m = session.hrr1;
    return AppCard(
      key: const ValueKey('walk-hrr'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Πτώση παλμών στο 1′', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text))),
          IconButton(
            key: const ValueKey('hrr-info'),
            tooltip: 'Τι σημαίνει και πώς μετριέται',
            onPressed: () => showRecoveryInfo(context),
            icon: Icon(Icons.info_outline_rounded, color: c.textSecondary),
          ),
        ]),
        if (e != null && m != null)
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(e - m >= 0 ? '−${e - m}' : '+${m - e}',
                key: const ValueKey('hrr-drop'), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: e - m > 0 ? c.good : c.text)),
            const SizedBox(width: 8),
            Flexible(child: Text('παλμοί ($e → $m)', style: TextStyle(fontSize: 15, color: c.text))),
          ])
        else
          Text('Δεν μετρήθηκε: πάτησες «Παράλειψη», ήσουν σε παύση, ή δεν υπήρχαν αρκετοί παλμοί.',
              style: TextStyle(fontSize: 14, height: 1.4, color: c.textSecondary)),
        const SizedBox(height: 4),
        Text('Συγκρίνεται μόνο με τις δικές σου προηγούμενες φορές.', style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
      ]),
    );
  }
}

/// Οδηγίες και σημασία της πτώσης παλμών στο 1′.
Future<void> showRecoveryInfo(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final c = Aigaio.of(ctx);
      Widget h(String t) => Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 4),
            child: Text(t, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: c.text)),
          );
      Widget p(String t) => Text(t, style: TextStyle(fontSize: 14.5, height: 1.45, color: c.text));
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .85),
          child: SingleChildScrollView(
            key: const ValueKey('hrr-info-sheet'),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Πτώση παλμών στο 1ο λεπτό', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.text)),
              h('Τι κάνεις'),
              p('1. Πατάς «Τέλος» στο ρολόι (δύο φορές).\n'
                  '2. Μέσα σε 10 δευτερόλεπτα κάθεσαι σε καρέκλα ή πάγκο.\n'
                  '3. Χέρια ακίνητα πάνω στα πόδια, ρολόι σφιχτό στον καρπό.\n'
                  '4. Δεν μιλάς· αναπνέεις κανονικά (όχι βαθιές ανάσες για να ηρεμήσεις).\n'
                  '5. Μένεις έτσι ώσπου να δονηθεί το ρολόι (λίγο πάνω από 1 λεπτό).'),
              h('Τι μετριέται'),
              p('Οι μέσοι παλμοί στα τελευταία 10 δευτερόλεπτα πριν το «Τέλος», μείον οι μέσοι παλμοί από 55 ως 65 δευτερόλεπτα μετά. '
                  'Όσο μεγαλύτερη η πτώση, τόσο καλύτερα «ηρεμεί» η καρδιά μετά την προσπάθεια· με την άσκηση συνήθως βελτιώνεται.'),
              h('Πώς το διαβάζεις'),
              p('Μόνο σε σύγκριση με τον εαυτό σου, με τον ίδιο τρόπο κάθε φορά (καθιστός). Τα όρια που διαβάζεις σε άρθρα '
                  '(π.χ. «κάτω από 12») προέρχονται από νοσοκομειακά τεστ με άλλο πρωτόκολλο και δεν ισχύουν εδώ. '
                  'Επηρεάζεται από το πόσο γρήγορα περπάτησες, τη ζέστη, την κούραση, τον καφέ και φάρμακα που επηρεάζουν τους παλμούς.'),
              h('Πότε δεν μετριέται'),
              p('Αν πατήσεις «Παράλειψη», αν ήσουν σε παύση όταν πάτησες «Τέλος», ή αν δεν υπήρχαν αρκετές μετρήσεις παλμών '
                  '(λιγότερες από 5 σε κάποιο από τα δύο διαστήματα). Τότε δεν γράφεται αριθμός.'),
              h('Πηγή'),
              p('Cole CR et al. Heart-rate recovery immediately after exercise as a predictor of mortality. N Engl J Med 1999;341:1351–7.'),
            ]),
          ),
        ),
      );
    },
  );
}
