import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data.dart';
import '../food/kitchen.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';
import 'food_add.dart' show parseNumber;

/// «Η κουζίνα μου»: τι συσκευές και σκεύη έχω. Οι συνταγές θα χρησιμοποιούν μόνο αυτά.
class KitchenScreen extends StatefulWidget {
  const KitchenScreen({super.key, required this.store});
  final HealthStore store;

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> {
  late final Kitchen _k = Kitchen.fromJson(widget.store.prefs.kitchen);

  void _save() {
    widget.store.setKitchen(_k.toJson());
    setState(() {});
  }

  Future<void> _editCookware([Cookware? existing]) async {
    final r = await showModalBottomSheet<_CookwareResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _CookwareSheet(existing: existing),
    );
    if (r == null) return;
    if (r.delete && existing != null) {
      final i = _k.cookware.indexOf(existing);
      _k.cookware.remove(existing);
      _save();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Διαγράφηκε: ${existing.label}'),
        action: SnackBarAction(
          label: 'Αναίρεση',
          onPressed: () {
            _k.cookware.insert(i.clamp(0, _k.cookware.length), existing);
            _save();
          },
        ),
      ));
      return;
    }
    final c = r.cookware!;
    final i = _k.cookware.indexWhere((x) => x.id == c.id);
    if (i >= 0) {
      _k.cookware[i] = c;
    } else {
      _k.cookware.add(c);
    }
    _save();
  }

  @override
  Widget build(BuildContext context) => FoodTheme(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final c = Aigaio.of(context);

    Widget detail(Widget child) => Padding(padding: const EdgeInsets.fromLTRB(16, 0, 8, 12), child: child);

    Widget segmented<T>(List<(T, String)> options, T? value, ValueChanged<T> onChanged) => Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final o in options)
              ChoiceChip(label: Text(o.$2), selected: value == o.$1, onSelected: (_) => onChanged(o.$1)),
          ],
        );

    Widget numberField(String label, String suffix, double? value, ValueChanged<double?> onChanged) => SizedBox(
          width: 170,
          child: TextFormField(
            initialValue: value == null ? '' : gramsTextPlain(value),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(
              labelText: label,
              suffixText: suffix,
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onChanged: (t) => onChanged(parseNumber(t)),
            onEditingComplete: _save,
            onTapOutside: (_) {
              FocusScope.of(context).unfocus();
              _save();
            },
          ),
        );

    List<Widget> deviceDetails(String key) => switch (key) {
          'oven' => [
              detail(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Έχει αέρα;', style: TextStyle(fontSize: 13, color: c.textSecondary)),
                const SizedBox(height: 4),
                segmented<bool>([(true, 'Ναι'), (false, 'Όχι')], _k.ovenFan, (v) {
                  _k.ovenFan = v;
                  _save();
                }),
              ])),
            ],
          'hob' => [
              detail(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Τι μάτια;', style: TextStyle(fontSize: 13, color: c.textSecondary)),
                const SizedBox(height: 4),
                segmented<String>(
                  [('Κεραμικά', 'Κεραμικά'), ('Επαγωγικά', 'Επαγωγικά'), ('Γκάζι', 'Γκάζι'), ('Εμαγιέ', 'Εμαγιέ')],
                  _k.hob,
                  (v) {
                    _k.hob = v;
                    _save();
                  },
                ),
              ])),
            ],
          'steamer' => [
              detail(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Όροφοι για φαγητό', style: TextStyle(fontSize: 13, color: c.textSecondary)),
                const SizedBox(height: 4),
                segmented<int>([(1, '1'), (2, '2'), (3, '3')], _k.steamerTiers, (v) {
                  _k.steamerTiers = v;
                  _save();
                }),
              ])),
            ],
          'airFryer' => [
              detail(numberField('Χωρητικότητα', 'λίτρα', _k.airFryerLiters, (v) => _k.airFryerLiters = v)),
            ],
          'scale' => [
              detail(numberField('Μέγιστο βάρος', 'kg', _k.scaleMaxKg, (v) => _k.scaleMaxKg = v)),
            ],
          _ => const [],
        };

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(backgroundColor: c.background, surfaceTintColor: Colors.transparent, title: const Text('Η κουζίνα μου')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              Text(
                'Οι συνταγές θα χρησιμοποιούν μόνο ό,τι έχεις εδώ, με συσκευή, θερμοκρασία και χρόνο.',
                style: TextStyle(fontSize: 14.5, height: 1.4, color: c.textSecondary),
              ),
              const SizedBox(height: 14),
              AppCard(
                padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(padding: EdgeInsets.only(left: 10, bottom: 4), child: SectionLabel('Συσκευές')),
                    for (final d in kitchenDevices) ...[
                      CheckboxListTile(
                        value: _k.has(d.$1),
                        onChanged: (on) {
                          on == true ? _k.devices.add(d.$1) : _k.devices.remove(d.$1);
                          _save();
                        },
                        title: Text(d.$2),
                        subtitle: d.$3.isEmpty ? null : Text(d.$3),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      if (_k.has(d.$1)) ...deviceDetails(d.$1),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AppCard(
                padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(padding: EdgeInsets.only(left: 10), child: SectionLabel('Σκεύη')),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                      child: Text(
                        'Ζύγισε μία φορά κάθε σκεύος άδειο και γράψε το «απόβαρο». Έτσι θα μπορείς να ζυγίζεις '
                        'το μαγειρεμένο φαγητό μέσα στην κατσαρόλα ή στο ταψί.',
                        style: TextStyle(fontSize: 13, height: 1.4, color: c.textSecondary),
                      ),
                    ),
                    for (final w in _k.cookware)
                      ListTile(
                        onTap: () => _editCookware(w),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                        title: Text(w.label),
                        subtitle: Text(
                          w.tareGrams == null ? 'Απόβαρο: δεν το έχεις ζυγίσει' : 'Απόβαρο ${gramsTextPlain(w.tareGrams!)} g',
                          style: TextStyle(color: w.tareGrams == null ? c.textTertiary : c.textSecondary),
                        ),
                        trailing: Icon(Icons.chevron_right_rounded, color: c.textTertiary),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _editCookware(),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Προσθήκη σκεύους'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String gramsTextPlain(double v) => v == v.roundToDouble() ? v.round().toString() : dec(v, 1);

class _CookwareResult {
  _CookwareResult({this.cookware, this.delete = false});
  final Cookware? cookware;
  final bool delete;
}

class _CookwareSheet extends StatefulWidget {
  const _CookwareSheet({this.existing});
  final Cookware? existing;

  @override
  State<_CookwareSheet> createState() => _CookwareSheetState();
}

class _CookwareSheetState extends State<_CookwareSheet> {
  late String _kind = widget.existing?.kind ?? 'pot';
  late String? _size = widget.existing?.size;
  late final _brand = TextEditingController(text: widget.existing?.brand ?? '');
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late final _tare = TextEditingController(
      text: widget.existing?.tareGrams == null ? '' : gramsTextPlain(widget.existing!.tareGrams!));

  @override
  void dispose() {
    _brand.dispose();
    _note.dispose();
    _tare.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FoodTheme(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final c = Aigaio.of(context);
    InputDecoration deco(String l, {String? suffix}) => InputDecoration(
          labelText: l,
          suffixText: suffix,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.existing == null ? 'Νέο σκεύος' : 'Σκεύος',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.text)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final k in cookwareKinds)
                  ChoiceChip(label: Text(k.$2), selected: _kind == k.$1, onSelected: (_) => setState(() => _kind = k.$1)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final s in cookwareSizes)
                  ChoiceChip(
                    label: Text(cookwareSizeLabel(_kind, s)),
                    selected: _size == s,
                    onSelected: (on) => setState(() => _size = on ? s : null),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(controller: _brand, decoration: deco('Μάρκα (προαιρετικό)')),
            const SizedBox(height: 10),
            TextField(controller: _note, decoration: deco('Σημείωση (π.χ. «28 cm», «με καπάκι»)')),
            const SizedBox(height: 10),
            TextField(
              controller: _tare,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: deco('Απόβαρο (άδειο, χωρίς καπάκι)', suffix: 'g'),
            ),
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: () => Navigator.pop(
                context,
                _CookwareResult(
                  cookware: Cookware(
                    id: widget.existing?.id ?? 'c${DateTime.now().microsecondsSinceEpoch}',
                    kind: _kind,
                    size: _size,
                    brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
                    note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                    tareGrams: parseNumber(_tare.text),
                  ),
                ),
              ),
              child: const Text('Αποθήκευση'),
            ),
            if (widget.existing != null)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: c.bad),
                onPressed: () => Navigator.pop(context, _CookwareResult(delete: true)),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Διαγραφή'),
              ),
          ],
        ),
      ),
    );
  }
}
