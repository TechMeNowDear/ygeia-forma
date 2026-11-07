import 'package:flutter/material.dart';

import '../data.dart';
import '../history.dart';
import '../oura/oura_api.dart';
import '../oxygen_note.dart';
import '../format.dart';
import '../sources.dart';
import '../theme.dart';
import '../widgets.dart';

/// Οξυγόνο μιας νύχτας όσο ο ύπνος είναι του Oura (απόφαση 7/11): ο ΜΕΣΟΣ ΟΡΟΣ από το Oura, η ΧΑΜΗΛΟΤΕΡΗ τιμή από το
/// ρολόι — δύο χωριστές μετρήσεις με δική τους ετικέτα, ποτέ ανακατεμένες. Η χαμηλότερη φαίνεται μόνο όταν το ρολόι
/// μέτρησε τουλάχιστον το μισό του ύπνου ([spo2MinShown]).
class RingOxygen {
  const RingOxygen(this.avg, this.watch);

  /// Μέσος όρος της νύχτας από το Oura (%).
  final double? avg;

  /// Οι μετρήσεις του ρολογιού μέσα στις ώρες ύπνου του Oura.
  final NightOxygen? watch;

  bool get minShown => watch != null && spo2MinShown(watch!.cov);
  double? get min => minShown ? watch!.min : null;
  bool get isEmpty => avg == null && watch == null;
}

RingOxygen ringOxygen(HealthStore store, Dashboard? d, DateTime day, SleepWindows windows) => RingOxygen(
      store.plan.value(store.history, K.ringSpo2, day) ?? store.ouraNightFor(day)?.spo2Avg,
      d?.watchSpo2(day, windows),
    );

/// Όταν λείπει ο μέσος όρος του Oura.
String ringAvgMissing(HealthStore store) => store.ouraSpo2 == false
    ? 'Ο μέσος όρος θέλει μία νέα σύνδεση με το Oura (Ρυθμίσεις › Πηγές)'
    : 'Ο μέσος όρος του Oura δεν ήρθε για αυτή τη νύχτα';

/// Η γραμμή του ρολογιού: χαμηλότερη τιμή και κάλυψη, ή γιατί δεν φαίνεται.
String watchLowText(NightOxygen? ox) {
  if (ox == null) return 'Χωρίς μετρήσεις του ρολογιού μέσα στον ύπνο';
  final pct = ox.cov == null ? null : (ox.cov! * 100).round();
  if (!spo2MinShown(ox.cov)) return 'Λίγη κάλυψη: το ρολόι μέτρησε το $pct% του ύπνου';
  final below = ox.below90 == null ? '' : ' · κάτω από 90%: ${hoursMinutes(ox.below90!.round())} (ενδεικτικό)';
  return '${pct == null ? '' : 'Μέτρησε το $pct% του ύπνου'}$below';
}

/// Κάρτα για να δοθεί η άδεια οξυγόνου στο Oura (μόνο όταν η τωρινή σύνδεση δεν την έχει).
class OuraOxygenAccessCard extends StatefulWidget {
  const OuraOxygenAccessCard({super.key, required this.store});
  final HealthStore store;

  static Widget? orNull(HealthStore store) =>
      store.ouraActive && store.ouraSpo2 == false ? OuraOxygenAccessCard(store: store) : null;

  @override
  State<OuraOxygenAccessCard> createState() => _OuraOxygenAccessCardState();
}

class _OuraOxygenAccessCardState extends State<OuraOxygenAccessCard> {
  bool _busy = false;

  /// Τι έγινε στην τελευταία προσπάθεια (μόνο αφού πατήθηκε το κουμπί): λάθος της Oura, ή σύνδεση χωρίς οξυγόνο.
  static String? _result(HealthStore s) {
    if (!s.ouraOxygenAsked || s.ouraConnecting) return null;
    if (s.ouraLoginError case final e?) return ouraLoginErrorText(e, code: s.ouraLoginCode);
    // Μόνο αν η νέα σύνδεση ολοκληρώθηκε ΜΕΤΑ το πάτημα (όχι όσο ο χρήστης είναι ακόμα στη σελίδα της Oura).
    final asked = s.ouraOxygenAskedMs, done = s.ouraConnectedMs;
    if (s.ouraSpo2 != false || asked == null || done == null || done < asked) return null;
    final given = s.ouraLastScope == null ? '' : ' (έδωσε μόνο: ${s.ouraLastScope})';
    return 'Η Oura συνδέθηκε ξανά, αλλά χωρίς την άδεια για το οξυγόνο$given. Στη σελίδα της Oura πρέπει να '
        'φαίνεται και διακόπτης για το οξυγόνο· αν δεν φαίνεται, η άδεια SpO2 δεν είναι ενεργή στις ρυθμίσεις της '
        'εφαρμογής στο developer.ouraring.com. Η εφαρμογή δοκιμάζει πάντως μία φορά τη μέρα να το διαβάσει.';
  }

  Future<void> _go() async {
    setState(() => _busy = true);
    final e = await widget.store.addOuraOxygen();
    if (!mounted) return;
    setState(() => _busy = false);
    if (e != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ouraErrorText(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return AppCard(
      key: const ValueKey('oura-oxygen-access'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBadge(Icons.air_rounded, c.sleep, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Οξυγόνο από το Oura',
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: c.text)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Για τον μέσο όρο οξυγόνου της νύχτας χρειάζεται μία νέα σύνδεση, ώστε να δώσεις και αυτή την άδεια. '
            'Ο ύπνος και τα υπόλοιπα συνεχίζουν κανονικά.',
            style: TextStyle(fontSize: 13.5, color: c.textSecondary, height: 1.4),
          ),
          if (_result(widget.store) case final r?) ...[
            const SizedBox(height: 10),
            Container(
              key: const ValueKey('oura-oxygen-result'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: c.tint(c.move), borderRadius: BorderRadius.circular(14)),
              child: Text(r, style: TextStyle(fontSize: 13.5, color: c.text, height: 1.4)),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _busy ? null : _go,
              child: Text(_busy ? 'Ανοίγει η Oura…' : 'Σύνδεση για το οξυγόνο'),
            ),
          ),
        ],
      ),
    );
  }
}

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
