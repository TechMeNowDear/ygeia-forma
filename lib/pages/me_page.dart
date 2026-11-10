import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data.dart';
import '../food/food_store.dart';
import '../food/kitchen.dart';
import '../format.dart';
import '../profile.dart';
import '../theme.dart';
import '../widgets.dart';
import 'kitchen.dart';
import 'my_foods.dart';

/// «Τα στοιχεία μου» (7/11): γέννηση, φύλο, ύψος για τα εύρη αναφοράς· η μέρα του εβδομαδιαίου ζυγίσματος.
/// Σχέδια 9/11 (10β): εδώ ζουν και «Τα προϊόντα μου» (όλη η λίστα) και «Η κουζίνα μου».
class MePage extends StatefulWidget {
  const MePage({super.key, required this.store, this.food});
  final HealthStore store;

  /// Χωρίς αυτό: η αποθήκη φαγητού της εφαρμογής ([FoodStore.shared]).
  final FoodStore? food;

  static Route<void> route(HealthStore store) =>
      MaterialPageRoute<void>(settings: const RouteSettings(name: 'Τα στοιχεία μου'), builder: (_) => MePage(store: store));

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  late final TextEditingController _height;

  @override
  void initState() {
    super.initState();
    final h = widget.store.profile.heightCm;
    _height = TextEditingController(text: h == null ? '' : dec(h));
  }

  @override
  void dispose() {
    _height.dispose();
    super.dispose();
  }

  /// Ύψος από την τελευταία ζύγιση (βάρος και δείκτης της InBody), ως πρόταση.
  double? _scaleHeight() {
    final b = widget.store.data?.latestBody;
    if (b?.weight == null || b?.bmi == null || b!.bmi! <= 0) return null;
    final cm = math.sqrt(b.weight! / b.bmi!) * 100;
    return (cm * 2).round() / 2;
  }

  void _save(Profile p) => widget.store.setProfile(p);

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final now = DateTime.now();
    final food = widget.food ?? FoodStore.shared;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.store, if (food != null) food]),
      builder: (context, _) {
        final p = widget.store.profile;
        final suggested = _scaleHeight();
        final label = TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text);
        final hint = TextStyle(fontSize: 13, color: c.textSecondary, height: 1.4);
        return Scaffold(
          appBar: AppBar(title: const Text('Τα στοιχεία μου')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    Text('Χρειάζονται για τα εύρη που δείχνει η εφαρμογή. Μένουν μόνο στο κινητό σου.', style: hint),
                    const SizedBox(height: 12),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Γέννηση', style: label),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  key: const ValueKey('me-month'),
                                  isExpanded: true,
                                  initialValue: p.birthMonth,
                                  decoration: const InputDecoration(labelText: 'Μήνας'),
                                  items: [
                                    for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text(monthNames[m - 1], overflow: TextOverflow.ellipsis)),
                                  ],
                                  onChanged: (v) => _save(p.copyWith(birthMonth: v)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  key: const ValueKey('me-year'),
                                  isExpanded: true,
                                  initialValue: p.birthYear,
                                  decoration: const InputDecoration(labelText: 'Έτος'),
                                  items: [
                                    for (var y = now.year - 18; y >= 1930; y--) DropdownMenuItem(value: y, child: Text('$y')),
                                  ],
                                  onChanged: (v) => _save(p.copyWith(birthYear: v)),
                                ),
                              ),
                            ],
                          ),
                          if (p.ageOn(now) != null) ...[
                            const SizedBox(height: 6),
                            Text('Ηλικία ${p.ageOn(now)}', style: hint),
                          ],
                          const Hairline(vertical: 14),
                          Text('Φύλο', style: label),
                          const SizedBox(height: 8),
                          SegmentedButton<String>(
                            key: const ValueKey('me-sex'),
                            emptySelectionAllowed: true,
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(value: 'm', label: Text('Άνδρας', style: TextStyle(fontFamily: 'Inter'))),
                              ButtonSegment(value: 'f', label: Text('Γυναίκα', style: TextStyle(fontFamily: 'Inter'))),
                            ],
                            selected: {if (p.sex != null) p.sex!},
                            onSelectionChanged: (s) {
                              if (s.isNotEmpty) _save(p.copyWith(sex: s.first));
                            },
                          ),
                          const SizedBox(height: 6),
                          Text('Οι επιστημονικές πηγές δίνουν τα εύρη χωριστά για άνδρες και γυναίκες.', style: hint),
                          const Hairline(vertical: 14),
                          TextField(
                            key: const ValueKey('me-height'),
                            controller: _height,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Ύψος', suffixText: 'cm'),
                            onChanged: (v) {
                              final h = double.tryParse(v.replaceAll(',', '.').trim());
                              if (h != null && h >= 100 && h <= 250) _save(p.copyWith(heightCm: h));
                            },
                          ),
                          if (suggested != null && p.heightCm == null) ...[
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: () {
                                  _height.text = dec(suggested);
                                  _save(p.copyWith(heightCm: suggested));
                                },
                                child: Text('Από τη ζυγαριά: ${dec(suggested)} cm'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Μέρα ζυγίσματος', style: label),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              for (var d = 1; d <= 7; d++) ...[
                                if (d > 1) const SizedBox(width: 6),
                                Expanded(
                                  child: _DayChip(
                                    label: weekdayChips[d - 1],
                                    semantics: weekdayNames[d - 1],
                                    selected: p.weighDay == d,
                                    onTap: () => _save(p.copyWith(weighDay: d)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Εκείνη τη μέρα η Σήμερα σου θυμίζει τη ζύγιση. Ίδια μέρα και ίδιες συνθήκες κάθε εβδομάδα: πρωί, μετά '
                            'την τουαλέτα, πριν φας ή πιεις.',
                            style: hint,
                          ),
                        ],
                      ),
                    ),
                    if (food != null) ...[
                      const GroupLabel('Διατροφή'),
                      _nutrition(context, food),
                    ],
                    const GroupLabel('Από πού έρχεται κάθε μέτρηση'),
                    AppCard(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _SourceRow('Ύπνος, HRV, παλμοί ύπνου, αναπνοές, μέσο οξυγόνο', 'Oura', line: true),
                          const _SourceRow('Βήματα, παλμοί ξύπνιος, χαμηλότερο οξυγόνο', 'Ρολόι', line: true),
                          const _SourceRow('Βάρος, λίπος, μύες', 'InBody'),
                          const SizedBox(height: 4),
                          Text('Κάθε μέτρηση έρχεται από μία συσκευή· ποτέ ανακατεμένα.', style: hint),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// «Τα προϊόντα μου» και «Η κουζίνα μου» (πριν: υπο-καρτέλα «Τα δικά μου» της Διατροφής).
  Widget _nutrition(BuildContext context, FoodStore food) {
    final c = Aigaio.of(context);
    final n = food.mine.length;
    final k = Kitchen.fromJson(widget.store.prefs.kitchen);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        NavRow(
          key: const ValueKey('mine-products'),
          icon: Icons.inventory_2_outlined,
          color: c.food,
          title: 'Τα προϊόντα μου',
          text: n == 0
              ? 'Πέρασε ό,τι αγοράζεις, με «Σάρωση» ή από την ετικέτα, χωρίς να το φας.'
              : '${n == 1 ? '1 προϊόν' : '$n προϊόντα'} · αλλαγή, αντιγραφή, διαγραφή',
          line: true,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              settings: const RouteSettings(name: 'Τα προϊόντα μου'), builder: (_) => MyFoodsScreen(food: food))),
        ),
        NavRow(
          key: const ValueKey('mine-kitchen'),
          icon: Icons.soup_kitchen_outlined,
          color: c.food,
          title: 'Η κουζίνα μου',
          text: '${k.devices.length} συσκευές · ${k.cookware.length} σκεύη · για τις συνταγές, όταν έρθουν',
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              settings: const RouteSettings(name: 'Η κουζίνα μου'), builder: (_) => KitchenScreen(store: widget.store))),
        ),
      ]),
    );
  }
}

/// «Ύπνος, HRV … · [Oura]»: η μέτρηση αριστερά, η συσκευή ως ετικέτα δεξιά.
class _SourceRow extends StatelessWidget {
  const _SourceRow(this.what, this.device, {this.line = false});
  final String what;
  final String device;
  final bool line;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: line ? BoxDecoration(border: Border(bottom: BorderSide(color: c.hairline))) : null,
      child: Row(children: [
        Expanded(child: Text(what, style: TextStyle(fontSize: 15, height: 1.35, color: c.text))),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(999), border: Border.all(color: c.hairline)),
          child: Text(device, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.text)),
        ),
      ]),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.label, required this.semantics, required this.selected, required this.onTap});
  final String label;
  final String semantics;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: semantics,
      child: Material(
        color: selected ? c.body : c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? c.body : c.hairline),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Center(
              // Μεγάλα γράμματα: η συντομογραφία μικραίνει για να χωρά, ποτέ κομμένη (σχέδια 9/11).
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label,
                    maxLines: 1,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: selected ? c.onSolid : c.text)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
