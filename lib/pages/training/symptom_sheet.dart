// «Νιώθω κάτι» και «Πώς είσαι σήμερα;» (έλεγχος 8/11, δεύτερη ιατρική γνώμη 1.1).
import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../training/symptoms.dart';
import '../../training/training_device.dart';
import '../../training/training_store.dart';

/// Κουμπί «Νιώθω κάτι» (ίδιο παντού: προπόνηση, περπάτημα, καθημερινότητα).
class FeelButton extends StatelessWidget {
  const FeelButton({super.key, required this.training, this.where = 'day', this.compact = false});
  final TrainingStore training;
  final String where;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final style = OutlinedButton.styleFrom(
      foregroundColor: c.bad,
      side: BorderSide(color: c.bad.withValues(alpha: .6)),
      minimumSize: Size(compact ? 0 : double.infinity, compact ? 40 : 48),
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
    );
    return OutlinedButton.icon(
      key: const ValueKey('feel'),
      style: style,
      onPressed: () => feelSomething(context, training, where: where),
      icon: const Icon(Icons.monitor_heart_outlined, size: 20),
      label: const Text('Νιώθω κάτι'),
    );
  }
}

/// Λίστα συμπτωμάτων → καταγραφή → τι κάνεις τώρα.
Future<SymptomOutcome> feelSomething(BuildContext context, TrainingStore t, {String where = 'day'}) async {
  final picked = await showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _SymptomPicker(training: t),
  );
  if (picked == null || picked.isEmpty || !context.mounted) return SymptomOutcome.none;
  final callNow = picked.any((c) => symptomDef(c)?.callNow ?? false);
  final out = t.reportSymptoms(picked, where: where);
  if (out == SymptomOutcome.none || !context.mounted) return out;
  final red = picked.any((c) => symptomDef(c)?.red ?? false);
  await Navigator.of(context).push(SymptomResultPage.route(red: red, escalated: !red && out == SymptomOutcome.red, callNow: callNow));
  return out;
}

class _SymptomPicker extends StatefulWidget {
  const _SymptomPicker({required this.training});
  final TrainingStore training;

  @override
  State<_SymptomPicker> createState() => _SymptomPickerState();
}

class _SymptomPickerState extends State<_SymptomPicker> {
  final _on = <String>{};

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    Widget row(SymptomDef d) {
      final on = _on.contains(d.code);
      final col = d.red ? c.bad : c.exercise;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: on ? col.withValues(alpha: .12) : c.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: on ? col : c.hairline, width: on ? 2 : 1),
          ),
          child: InkWell(
            key: ValueKey('sym-${d.code}'),
            customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onTap: () => setState(() => on ? _on.remove(d.code) : _on.add(d.code)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Row(children: [
                Icon(on ? Icons.check_circle_rounded : Icons.circle_outlined, color: on ? col : c.textTertiary),
                const SizedBox(width: 10),
                Expanded(child: Text(d.text, style: TextStyle(fontSize: 15, height: 1.3, color: c.text))),
              ]),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .88),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          // Όλα χτισμένα (όχι ListView): το κουμπί στο τέλος υπάρχει πάντα.
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Τι νιώθεις;', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.text)),
          const SizedBox(height: 4),
          Text('Πρώτα σταμάτα και κάθισε. Διάλεξε ό,τι ισχύει.', style: TextStyle(fontSize: 14.5, color: c.textSecondary)),
          const SizedBox(height: 14),
          Text('Σοβαρά', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.bad)),
          const SizedBox(height: 6),
          for (final d in redSymptoms) row(d),
          const SizedBox(height: 8),
          Text('Άλλα', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.textSecondary)),
          const SizedBox(height: 6),
          for (final d in amberSymptoms) row(d),
          const SizedBox(height: 10),
          FilledButton(
            key: const ValueKey('sym-ok'),
            style: FilledButton.styleFrom(backgroundColor: c.bad, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(50)),
            onPressed: _on.isEmpty ? null : () => Navigator.of(context).pop(_on.toList()),
            child: const Text('Συνέχεια'),
          ),
          if (widget.training.pendingWatchSymptom != null)
            TextButton(
              key: const ValueKey('sym-nothing'),
              onPressed: () {
                widget.training.clearWatchSymptom();
                Navigator.of(context).pop();
              },
              child: const Text('Τελικά τίποτα, πατήθηκε κατά λάθος'),
            ),
        ])),
      ),
    );
  }
}

/// Τι κάνεις τώρα: κόκκινο (166) ή πορτοκαλί (σταματάς για σήμερα).
class SymptomResultPage extends StatelessWidget {
  const SymptomResultPage({super.key, required this.red, this.escalated = false, this.callNow = false});
  final bool red;

  /// Δεύτερο πορτοκαλί μέσα σε 14 μέρες: κλειδώνει όπως το κόκκινο, αλλά χωρίς «166 τώρα».
  final bool escalated;
  final bool callNow;

  static Route<void> route({required bool red, bool escalated = false, bool callNow = false}) => MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'Σύμπτωμα'),
        builder: (_) => SymptomResultPage(red: red, escalated: escalated, callNow: callNow),
      );

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final title = red ? 'Σταμάτα. Κάθισε. Μην οδηγήσεις.' : 'Σταμάτα για σήμερα';
    final body = red
        ? (callNow
            ? 'Πάρε τώρα το 166. Μην περιμένεις να περάσει.'
            : 'Αν δεν περάσει μέσα σε 5 λεπτά ξεκούρασης, αν είναι έντονο, ή αν έχεις κρύο ιδρώτα: πάρε τώρα το 166.')
        : escalated
            ? 'Γράφτηκε. Είναι η δεύτερη φορά μέσα σε 14 μέρες, γι’ αυτό τα βάρη κλείδωσαν μέχρι να σε δει γιατρός. '
                'Αν χειροτερέψει ή εμφανιστεί κάτι σοβαρό: 166.'
            : 'Γράφτηκε. Ξεκουράσου. Αν ξανασυμβεί μέσα σε 14 μέρες, τα βάρη κλειδώνουν μέχρι να σε δει γιατρός. '
                'Αν χειροτερέψει ή εμφανιστεί κάτι σοβαρό: 166.';
    return Scaffold(
      backgroundColor: red ? c.bad.withValues(alpha: .08) : null,
      appBar: AppBar(backgroundColor: Colors.transparent, automaticallyImplyLeading: false),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 24), children: [
              Icon(red ? Icons.emergency_rounded : Icons.pause_circle_outline_rounded, size: 56, color: red ? c.bad : c.exercise),
              const SizedBox(height: 14),
              Text(title, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.2, color: c.text)),
              const SizedBox(height: 10),
              Text(body, style: TextStyle(fontSize: 17, height: 1.45, color: c.text)),
              if (red || escalated) ...[
                const SizedBox(height: 10),
                Text('Τα βάρη κλείδωσαν. Ανοίγουν ξανά όταν σε δει γιατρός.', style: TextStyle(fontSize: 15, height: 1.4, color: c.textSecondary)),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const ValueKey('call-166'),
                style: FilledButton.styleFrom(
                  backgroundColor: red ? c.bad : c.card,
                  foregroundColor: red ? Colors.white : c.bad,
                  side: red ? null : BorderSide(color: c.bad),
                  minimumSize: Size.fromHeight(red ? 64 : 52),
                  textStyle: TextStyle(fontSize: red ? 20 : 16, fontWeight: FontWeight.w800),
                ),
                onPressed: () => TrainingDevice.dial('166'),
                icon: const Icon(Icons.call_rounded),
                label: const Text('Κλήση 166'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                key: const ValueKey('call-112'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => TrainingDevice.dial('112'),
                child: const Text('Κλήση 112'),
              ),
              const SizedBox(height: 18),
              TextButton(
                key: const ValueKey('sym-close'),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(red ? 'Κλείσιμο' : 'Εντάξει'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// «Πώς είσαι σήμερα;» πριν από την προπόνηση. Δύο ίσα κουμπιά, τίποτα προεπιλεγμένο. true = ξεκίνα.
Future<bool> readinessCheck(BuildContext context, TrainingStore t) async {
  final r = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => const _Readiness(),
  );
  if (!context.mounted || r == null) return false;
  switch (r) {
    case 'ok':
      return true;
    case 'fever':
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Με πυρετό ή ίωση, όχι προπόνηση σήμερα. Ξεκουράσου και ξαναδοκίμασε όταν περάσει.'),
        duration: Duration(seconds: 6),
      ));
      return false;
    case 'meds':
      t.relock('meds');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Νέο φάρμακο για καρδιά ή πίεση: τα βάρη κλείδωσαν μέχρι να το εγκρίνει ο γιατρός.'),
        duration: Duration(seconds: 6),
      ));
      return false;
    case 'symptom':
      await feelSomething(context, t, where: 'check');
      return false;
  }
  return false;
}

class _Readiness extends StatefulWidget {
  const _Readiness();

  @override
  State<_Readiness> createState() => _ReadinessState();
}

class _ReadinessState extends State<_Readiness> {
  bool _bad = false;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    Widget choice(String key, String text, IconData icon) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton.icon(
            key: ValueKey('ready-$key'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), alignment: Alignment.centerLeft),
            onPressed: () => Navigator.of(context).pop(key),
            icon: Icon(icon),
            label: Text(text, style: const TextStyle(fontSize: 15.5)),
          ),
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_bad ? 'Τι από αυτά;' : 'Πώς είσαι σήμερα;', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.text)),
          const SizedBox(height: 4),
          Text(
            _bad ? 'Διάλεξε ό,τι ισχύει.' : 'Πριν από τα βάρη, για τις πρώτες εβδομάδες και μετά από κάθε σύμπτωμα.',
            style: TextStyle(fontSize: 14.5, height: 1.35, color: c.textSecondary),
          ),
          const SizedBox(height: 16),
          if (!_bad)
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('ready-ok'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  onPressed: () => Navigator.of(context).pop('ok'),
                  child: const Text('Όλα καλά', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('ready-bad'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  onPressed: () => setState(() => _bad = true),
                  child: const Text('Κάτι δεν πάει καλά', textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
                ),
              ),
            ])
          else ...[
            choice('fever', 'Πυρετός ή ίωση', Icons.thermostat_rounded),
            choice('meds', 'Νέο φάρμακο για καρδιά ή πίεση', Icons.medication_outlined),
            choice('symptom', 'Κάποιο σύμπτωμα από την τελευταία φορά', Icons.monitor_heart_outlined),
          ],
        ]),
      ),
    );
  }
}
