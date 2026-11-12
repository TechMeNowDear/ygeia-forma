import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data.dart';
import '../format.dart';
import '../theme.dart';
import '../waist.dart';
import '../widgets.dart';

/// Φύλλο «Μέση» (σχέδια 12/11, 5β): δύο μετρήσεις, τρίτη αν διαφέρουν πάνω από 1 cm, ο μέσος όρος, ο τρόπος μέτρησης και
/// το εύρος αναφοράς (ESC 2021). Μία τιμή τη μέρα· αν υπάρχει ήδη της ημέρας, ανοίγει με αυτήν.
Future<void> openWaistSheet(BuildContext context, HealthStore store, {DateTime? now}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    routeSettings: const RouteSettings(name: 'Μέση'),
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => WaistSheet(store: store, now: now ?? DateTime.now()),
  );
}

String waistDayKey(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

class WaistSheet extends StatefulWidget {
  const WaistSheet({super.key, required this.store, required this.now});
  final HealthStore store;
  final DateTime now;

  @override
  State<WaistSheet> createState() => _WaistSheetState();
}

class _WaistSheetState extends State<WaistSheet> {
  late final String _day = waistDayKey(widget.now);
  late final WaistEntry? _old = () {
    for (final e in widget.store.waist) {
      if (e.day == _day) return e;
    }
    return null;
  }();
  late final List<TextEditingController> _t = () {
    final v = _old?.values ?? const <double>[];
    return [for (var k = 0; k < 3; k++) TextEditingController(text: k < v.length ? dec(v[k]) : '')];
  }();

  @override
  void dispose() {
    for (final t in _t) {
      t.dispose();
    }
    super.dispose();
  }

  double? _v(int k) {
    final v = double.tryParse(_t[k].text.replaceAll(',', '.').trim());
    return v != null && v >= waistMinCm && v <= waistMaxCm ? v : null;
  }

  bool get _third {
    final a = _v(0), b = _v(1);
    return a != null && b != null && needsThird(a, b);
  }

  /// Οι μετρήσεις που μετράνε (null αν λείπει κάποια).
  List<double>? get _values {
    final a = _v(0), b = _v(1);
    if (a == null || b == null) return null;
    if (!needsThird(a, b)) return [a, b];
    final c = _v(2);
    return c == null ? null : [a, b, c];
  }

  Widget _field(int k, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          key: ValueKey('waist-$k'),
          controller: _t[k],
          autofocus: k == 0 && _old == null,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: label, suffixText: 'cm'),
          onChanged: (_) => setState(() {}),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final values = _values;
    final p = widget.store.profile;
    final ref = waistRef(!p.female);
    final small = TextStyle(fontSize: 13.5, height: 1.45, color: c.textSecondary);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Μέση', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.text)),
          const SizedBox(height: 12),
          _field(0, '1η μέτρηση'),
          _field(1, '2η μέτρηση'),
          if (_third) ...[
            Text('Διαφέρουν πάνω από 1 cm. Μέτρησε μία ακόμα φορά.', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.warn)),
            const SizedBox(height: 8),
            _field(2, '3η μέτρηση'),
          ],
          if (values != null)
            InfoRow('Μέση (μέσος όρος)', '${dec(WaistEntry(_day, values).cm)} cm')
          else
            Text('Αν διαφέρουν πάνω από 1 cm, ζητά και 3η.', style: small),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.tint(c.body), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Πώς μετράς', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
              const SizedBox(height: 4),
              Text(
                'Όρθιος, κοιλιά χαλαρή, στο τέλος της εκπνοής. Στη μέση ανάμεσα στο κάτω πλευρό και τη λεκάνη. Μεζούρα '
                'οριζόντια, χωρίς να βουλιάζει το δέρμα. Ίδια ώρα κάθε φορά, πριν το φαγητό.',
                style: TextStyle(fontSize: 14, height: 1.45, color: c.text),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Text(
            p.female || p.male
                ? 'Εύρος αναφοράς ${p.female ? 'γυναικών' : 'ανδρών'}: κάτω από ${dec(ref.ok, 0)} cm· από ${dec(ref.high, 0)} cm '
                    'οι οδηγίες συστήνουν μείωση βάρους (ESC 2021).'
                : 'Εύρος αναφοράς: ανδρών κάτω από 94 cm, γυναικών κάτω από 80 cm (ESC 2021).',
            style: small,
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('waist-save'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: c.body, foregroundColor: c.dark ? const Color(0xFF14200A) : Colors.white),
            onPressed: values == null
                ? null
                : () {
                    widget.store.saveWaist(WaistEntry(_day, values));
                    Navigator.of(context).pop();
                  },
            child: const Text('Αποθήκευση'),
          ),
          if (_old != null)
            TextButton(
              key: const ValueKey('waist-delete'),
              onPressed: () {
                widget.store.deleteWaist(_day);
                Navigator.of(context).pop();
              },
              child: Text('Διαγραφή της σημερινής', style: TextStyle(color: c.bad)),
            ),
        ]),
      ),
    );
  }
}
