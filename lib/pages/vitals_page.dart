// Πίεση, σάκχαρο, καρδιογραφήματα (16/11): καταχώριση με το χέρι και λίστα.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../theme.dart';
import '../vitals.dart';
import '../widgets.dart';

class VitalsPage extends StatefulWidget {
  const VitalsPage({super.key, required this.store, this.now});
  final VitalsStore store;
  final DateTime Function()? now;

  static Route<void> route(VitalsStore s) => MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'Πίεση, σάκχαρο, καρδιογράφημα'), builder: (_) => VitalsPage(store: s));

  @override
  State<VitalsPage> createState() => _VitalsPageState();
}

class _VitalsPageState extends State<VitalsPage> {
  VitalKind _kind = VitalKind.bp;

  DateTime _now() => (widget.now ?? DateTime.now)();

  String _title(VitalKind k) => switch (k) {
        VitalKind.bp => 'Πίεση',
        VitalKind.glucose => 'Σάκχαρο',
        VitalKind.ecg => 'Καρδιογράφημα',
      };

  Future<void> _add() async {
    final v = await showModalBottomSheet<Vital>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      routeSettings: const RouteSettings(name: 'Νέα μέτρηση'),
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => VitalSheet(kind: _kind, now: _now()),
    );
    if (v != null) await widget.store.add(v);
  }

  Future<void> _open(Vital v) async {
    final del = await showDialog<bool>(
      context: context,
      routeSettings: const RouteSettings(name: 'Διαγραφή μέτρησης'),
      builder: (ctx) => AlertDialog(
        title: const Text('Διαγραφή μέτρησης;'),
        content: Text('${longDate(v.at)}, ${hm(v.at)} · ${vitalValueText(v)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Άκυρο')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Διαγραφή')),
        ],
      ),
    );
    if (del == true) await widget.store.remove(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Πίεση, σάκχαρο, καρδιογράφημα'), backgroundColor: c.background, surfaceTintColor: Colors.transparent),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('vital-add'),
        onPressed: widget.store.read ? _add : null,
        icon: const Icon(Icons.add_rounded),
        label: Text('Νέα: ${_title(_kind).toLowerCase()}'),
      ),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final list = widget.store.of(_kind);
          final avg = _kind == VitalKind.bp ? bpAverage(list, _now()) : null;
          final small = TextStyle(fontSize: 13.5, height: 1.4, color: c.textSecondary);
          return ListView(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 96 + MediaQuery.paddingOf(context).bottom),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SegmentedButton<VitalKind>(
                      key: const ValueKey('vital-kind'),
                      showSelectedIcon: false,
                      segments: [
                        for (final k in VitalKind.values) ButtonSegment(value: k, label: Text(_title(k), maxLines: 1)),
                      ],
                      selected: {_kind},
                      onSelectionChanged: (s) => setState(() => _kind = s.first),
                    ),
                    const SizedBox(height: 12),
                    if (widget.store.error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(widget.store.error!, style: TextStyle(color: c.warn, fontWeight: FontWeight.w600)),
                      ),
                    if (avg != null)
                      AppCard(
                        child: Text(bpAverageText(avg),
                            key: const ValueKey('bp-average'), style: TextStyle(fontSize: 15, height: 1.4, color: c.text)),
                      ),
                    if (_kind == VitalKind.ecg)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Γράψε το αποτέλεσμα όπως το έδειξε η εφαρμογή ECG του ρολογιού. Το καρδιογράφημα του ρολογιού δεν '
                          'βλέπει έμφραγμα: με πόνο στο στήθος ή δύσπνοια, 166 ή 112.',
                          style: small,
                        ),
                      ),
                    if (list.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text('Δεν έχεις γράψει ακόμα μέτρηση.', textAlign: TextAlign.center, style: small),
                      )
                    else
                      AppCard(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Column(children: [
                          for (var i = 0; i < list.length; i++)
                            InkWell(
                              key: ValueKey('vital-${list[i].id}'),
                              onTap: () => _open(list[i]),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                decoration: i < list.length - 1
                                    ? BoxDecoration(border: Border(bottom: BorderSide(color: c.hairline)))
                                    : null,
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(vitalValueText(list[i]),
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text, fontFeatures: tabular)),
                                  Text(
                                      [
                                        '${shortDayDate(list[i].at)}, ${hm(list[i].at)}',
                                        if (list[i].when != null) glucoseWhenText(list[i].when!),
                                        if (list[i].note != null) list[i].note!,
                                      ].join(' · '),
                                      style: small),
                                  if (list[i].kind == VitalKind.glucose && glucoseNote(list[i]) != null)
                                    Text(glucoseNote(list[i])!, style: small.copyWith(color: list[i].glucose! < 70 ? c.warn : c.textSecondary)),
                                ]),
                              ),
                            ),
                        ]),
                      ),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// «128/82 mmHg · σφυγμοί 64», «96 mg/dL», «Φλεβοκομβικός ρυθμός».
String vitalValueText(Vital v) => switch (v.kind) {
      VitalKind.bp => '${v.sys}/${v.dia} mmHg${v.pulse == null ? '' : ' · σφυγμοί ${v.pulse}'}',
      VitalKind.glucose => '${v.glucose!.round()} mg/dL',
      VitalKind.ecg => ecgText(v.ecg!),
    };

/// Νέα μέτρηση: τα πεδία του είδους, ώρα (τώρα, αλλάζει), σημείωση.
class VitalSheet extends StatefulWidget {
  const VitalSheet({super.key, required this.kind, required this.now});
  final VitalKind kind;
  final DateTime now;

  @override
  State<VitalSheet> createState() => _VitalSheetState();
}

class _VitalSheetState extends State<VitalSheet> {
  final _a = TextEditingController(), _b = TextEditingController(), _p = TextEditingController(), _note = TextEditingController();
  late DateTime _at = widget.now;
  GlucoseWhen _when = GlucoseWhen.fasting;
  EcgResult? _ecg;

  @override
  void dispose() {
    for (final c in [_a, _b, _p, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _int(TextEditingController c) => int.tryParse(c.text.trim());

  /// Η μέτρηση, ή το πρόβλημα που λέγεται.
  (Vital?, String?) _build() {
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    final id = VitalsStore.newId();
    switch (widget.kind) {
      case VitalKind.bp:
        final s = _int(_a), d = _int(_b), p = _p.text.trim().isEmpty ? null : _int(_p);
        if (s == null || d == null) return (null, null);
        final err = bpProblem(s, d, p);
        if (err != null || (_p.text.trim().isNotEmpty && p == null)) return (null, err ?? 'Οι σφυγμοί θέλουν ακέραιο αριθμό.');
        return (Vital(id: id, kind: VitalKind.bp, at: _at, sys: s, dia: d, pulse: p, note: note), null);
      case VitalKind.glucose:
        final g = double.tryParse(_a.text.trim().replaceAll(',', '.'));
        if (g == null) return (null, null);
        final err = glucoseProblem(g);
        if (err != null) return (null, err);
        return (Vital(id: id, kind: VitalKind.glucose, at: _at, glucose: g, when: _when, note: note), null);
      case VitalKind.ecg:
        if (_ecg == null) return (null, null);
        return (Vital(id: id, kind: VitalKind.ecg, at: _at, ecg: _ecg, note: note), null);
    }
  }

  Widget _field(TextEditingController c, String label, String key, {String? suffix}) => TextField(
        key: ValueKey(key),
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

  Future<void> _pickTime() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(widget.now.year - 1),
      lastDate: widget.now,
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t == null) return;
    setState(() => _at = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final (v, err) = _build();
    final title = switch (widget.kind) {
      VitalKind.bp => 'Νέα μέτρηση πίεσης',
      VitalKind.glucose => 'Νέα μέτρηση σακχάρου',
      VitalKind.ecg => 'Νέο καρδιογράφημα',
    };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.text)),
          const SizedBox(height: 12),
          if (widget.kind == VitalKind.bp) ...[
            Row(children: [
              Expanded(child: _field(_a, 'Μεγάλη', 'bp-sys')),
              const SizedBox(width: 8),
              Expanded(child: _field(_b, 'Μικρή', 'bp-dia')),
            ]),
            const SizedBox(height: 8),
            _field(_p, 'Σφυγμοί (αν τους δείχνει)', 'bp-pulse'),
            const SizedBox(height: 6),
            Text('Καθιστός, μετά από 5 λεπτά ηρεμίας, το χέρι στο ύψος της καρδιάς. Καλύτερα 2 μετρήσεις και γράψε τη δεύτερη.',
                style: TextStyle(fontSize: 13, height: 1.35, color: c.textSecondary)),
          ],
          if (widget.kind == VitalKind.glucose) ...[
            _field(_a, 'Σάκχαρο', 'glu-value', suffix: 'mg/dL'),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final w in GlucoseWhen.values)
                ChoiceChip(
                  key: ValueKey('glu-${w.name}'),
                  label: Text(glucoseWhenText(w)),
                  selected: _when == w,
                  onSelected: (_) => setState(() => _when = w),
                ),
            ]),
          ],
          if (widget.kind == VitalKind.ecg)
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final r in EcgResult.values)
                ChoiceChip(
                  key: ValueKey('ecg-${r.name}'),
                  label: Text(ecgText(r)),
                  selected: _ecg == r,
                  onSelected: (_) => setState(() => _ecg = r),
                ),
            ]),
          const SizedBox(height: 12),
          ListTile(
            key: const ValueKey('vital-time'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Πότε'),
            trailing: Text('${shortDayDate(_at)}, ${hm(_at)}',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.primary)),
            onTap: _pickTime,
          ),
          TextField(
            key: const ValueKey('vital-note'),
            controller: _note,
            maxLength: 120,
            decoration: InputDecoration(
              labelText: 'Σημείωση (προαιρετικά)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          if (err != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(err, key: const ValueKey('vital-error'), style: TextStyle(color: c.warn, fontWeight: FontWeight.w600)),
            ),
          FilledButton(
            key: const ValueKey('vital-save'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20)),
            onPressed: v == null ? null : () => Navigator.pop(context, v),
            child: const Text('Αποθήκευση'),
          ),
        ]),
      ),
    );
  }
}
