// «Ετοίμασε πριν ξεκινήσεις» και «Ο εξοπλισμός μου» (16/11).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import '../../training/equipment.dart';
import '../../training/prep.dart';
import '../../training/program.dart';
import '../../training/training_store.dart';
import 'training_common.dart' show exName;

/// Οι ασκήσεις της μέρας όπως θα γίνουν σήμερα (παραλλαγή και βάρος του στόχου).
List<PrepIn> prepItems(TrainingStore t, Workout w) => [
      for (final plan in w.items)
        () {
          final item = t.itemToday(plan);
          return (name: exName(item.ex), kind: item.kind, load: t.targetFor(item).load);
        }(),
    ];

/// Το κουμπί κάτω από το όνομα της προπόνησης (μόνο σε μέρα βαρών, και μόνο αν κάτι στήνεται).
class PrepButton extends StatelessWidget {
  const PrepButton(this.training, this.workout, {super.key});
  final TrainingStore training;
  final Workout workout;

  @override
  Widget build(BuildContext context) {
    if (workout.isCardio) return const SizedBox.shrink();
    final c = Aigaio.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const ValueKey('prep-open'),
        style: TextButton.styleFrom(
            foregroundColor: c.exercise, minimumSize: const Size(48, 48), padding: const EdgeInsets.symmetric(horizontal: 4)),
        onPressed: () => openPrepSheet(context, training, workout),
        icon: const Icon(Icons.checklist_rounded, size: 20),
        label: const Text('Ετοίμασε πριν ξεκινήσεις', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

Future<void> openPrepSheet(BuildContext context, TrainingStore t, Workout w) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      routeSettings: const RouteSettings(name: 'Ετοίμασε πριν ξεκινήσεις'),
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => ListenableBuilder(
        listenable: t,
        builder: (context, _) => PrepSheet(prep: prepFor(prepItems(t, w), t.equipment), training: t),
      ),
    );

class PrepSheet extends StatelessWidget {
  const PrepSheet({super.key, required this.prep, required this.training});
  final Prep prep;
  final TrainingStore training;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final small = TextStyle(fontSize: 13.5, height: 1.4, color: c.textSecondary);
    final now = [for (final l in prep.lines) if (!l.later) l];
    final later = [for (final l in prep.lines) if (l.later) l];
    Widget line(PrepLine l) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(l.later ? Icons.schedule_rounded : Icons.check_box_outline_blank_rounded, size: 20, color: c.exercise),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.what, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
                if (l.how != null) Text(l.how!, style: TextStyle(fontSize: 15, color: c.text)),
                Text('για: ${l.forWhat.join(', ')}', style: small),
              ]),
            ),
          ]),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Ετοίμασε πριν ξεκινήσεις', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.text)),
        const SizedBox(height: 4),
        Text(
          prep.lines.isEmpty
              ? 'Σήμερα δεν χρειάζεται να στήσεις τίποτα: όλες οι ασκήσεις είναι με το βάρος του σώματος.'
              : 'Στήσε τα από πριν, με τα βάρη του σημερινού στόχου.',
          style: small,
        ),
        const SizedBox(height: 6),
        for (final l in now) line(l),
        if (later.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Δεν φτάνουν ${prep.handlesNeeded > training.equipment.handles ? 'οι λαβές' : 'οι δίσκοι'} για να στηθούν όλα μαζί. '
            'Αυτά στήσ’ τα όταν φτάσεις εκεί:',
            key: const ValueKey('prep-short'),
            style: TextStyle(fontSize: 14.5, height: 1.4, fontWeight: FontWeight.w600, color: c.warn),
          ),
          for (final l in later) line(l),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('equip-open'),
            onPressed: () => openEquipmentSheet(context, training),
            icon: const Icon(Icons.tune_rounded, size: 20),
            label: const Text('Ο εξοπλισμός μου'),
          ),
        ),
      ]),
    );
  }
}

Future<void> openEquipmentSheet(BuildContext context, TrainingStore t) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      routeSettings: const RouteSettings(name: 'Ο εξοπλισμός μου'),
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => EquipmentSheet(training: t),
    );

/// Λαβές και δίσκοι (μετά από αγορά). Τα βάρη που προτείνονται αλλάζουν αμέσως.
class EquipmentSheet extends StatefulWidget {
  const EquipmentSheet({super.key, required this.training});
  final TrainingStore training;

  @override
  State<EquipmentSheet> createState() => _EquipmentSheetState();
}

class _EquipmentSheetState extends State<EquipmentSheet> {
  late Equipment _e = widget.training.equipment;
  late final _handleKg = TextEditingController(text: kgText(_e.handleKg));

  @override
  void dispose() {
    _handleKg.dispose();
    super.dispose();
  }

  double? get _kg {
    final v = double.tryParse(_handleKg.text.trim().replaceAll(',', '.'));
    return v != null && v >= 0.5 && v <= 5 ? (v * 100).round() / 100 : null;
  }

  Widget _stepper(String label, int value, int max, ValueChanged<int> set, String key) {
    final c = Aigaio.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(fontSize: 15.5, color: c.text))),
        IconButton.filledTonal(
          key: ValueKey('$key-less'),
          tooltip: 'Λιγότερα',
          onPressed: value > 0 ? () => set(value - 1) : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        SizedBox(
          width: 44,
          child: Text('$value',
              key: ValueKey('$key-value'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text, fontFeatures: tabular)),
        ),
        IconButton.filledTonal(
          key: ValueKey('$key-more'),
          tooltip: 'Περισσότερα',
          onPressed: value < max ? () => set(value + 1) : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final kg = _kg;
    final total = plateKinds.fold(0.0, (a, p) => a + p * _e.count(p));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Ο εξοπλισμός μου', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.text)),
          const SizedBox(height: 4),
          Text('Από αυτά βγαίνουν τα βάρη που προτείνονται και το «Ετοίμασε πριν ξεκινήσεις».',
              style: TextStyle(fontSize: 13.5, height: 1.4, color: c.textSecondary)),
          const SizedBox(height: 12),
          Text('ΛΑΒΕΣ ΑΛΤΗΡΑ', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.textSecondary)),
          _stepper('Πόσες λαβές', _e.handles, Equipment.maxHandles, (v) => setState(() => _e = _e.copyWith(handles: v < 1 ? 1 : v)),
              'equip-handles'),
          const SizedBox(height: 6),
          TextField(
            key: const ValueKey('equip-handle-kg'),
            controller: _handleKg,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Βάρος μίας λαβής, με τα 2 αστεράκια της',
              suffixText: 'kg',
              // 16/11 (έλεγχος): ένα βάρος για όλες. Με παλιές 1,8 και νέες 2,2 kg, ο αλτήρας στις παλιές βγαίνει 0,4 kg
              // ελαφρύτερος από όσο γράφει: μικρή διαφορά, αλλά καλύτερα οι λαβές του ίδιου ζευγαριού να είναι ίδιες.
              helperText: 'Αν δεν ζυγίζουν όλες το ίδιο: το βάρος των περισσότερων, και τα ζευγάρια από ίδιες λαβές.',
              helperMaxLines: 3,
              errorText: kg == null ? 'Από 0,5 έως 5 kg' : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),
          Text('ΔΙΣΚΟΙ (ΟΛΟΙ ΜΑΖΙ ${kgText(total)} kg)',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.textSecondary)),
          for (final p in plateKinds)
            _stepper('${kgText(p)} kg', _e.count(p), Equipment.maxPlates,
                (v) => setState(() => _e = _e.withPlate(p, v)), 'equip-plate-${kgText(p)}'),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('equip-save'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20)),
            onPressed: kg == null
                ? null
                : () {
                    widget.training.setEquipment(_e.copyWith(handleKg: kg));
                    Navigator.pop(context);
                  },
            child: const Text('Αποθήκευση'),
          ),
        ]),
      ),
    );
  }
}
