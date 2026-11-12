import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../adaptive.dart';
import '../adaptive_check.dart';
import '../data.dart';
import '../food/food_store.dart';
import '../format.dart';
import '../goals.dart';
import '../profile.dart';
import '../reference.dart' show MetricInfo;
import '../theme.dart';
import '../widgets.dart';
import 'info_sheet.dart';
import 'me_page.dart';

/// «Στόχοι διατροφής»: ο οδηγός αν δεν υπάρχουν, αλλιώς η σελίδα «Στόχοι».
Future<void> openGoals(BuildContext context, HealthStore store, {DateTime? now}) {
  final nav = Navigator.of(context);
  if (store.goals == null) return nav.push(GoalsWizard.route(store, now: now));
  return nav.push(GoalsPage.route(store, now: now));
}

const goalsInfo = MetricInfo(
  title: 'Στόχοι διατροφής',
  what: 'Θερμίδες και θρεπτικά της ημέρας, από τύπους με επιστημονική πηγή. Κανένας αριθμός δεν βγαίνει από AI.',
  // 12/11: η αυτόματη διόρθωση μπήκε (σχέδια A1–A4)· πάντα με το δικό σου «Εφάρμοσε».
  shows: 'Πόσο να φας για τον στόχο σου. Ο στόχος θερμίδων είναι αρχική εκτίμηση. Μετά από 3 εβδομάδες με ζυγίσεις και '
      'καταγραφή φαγητού φαίνεται πόσες θερμίδες καις πραγματικά, και κάθε εβδομάδα η εφαρμογή προτείνει διόρθωση του '
      'στόχου (το πολύ 150 kcal τη φορά). Αλλάζει μόνο όταν πατήσεις «Εφάρμοσε».',
  compare: 'Πρωτεΐνη 1,6 g ανά κιλό (Morton 2018) · λίπος 25–35% των θερμίδων (EFSA) · κορεσμένα έως 6% όταν ο γιατρός ζητά να '
      'πέσει η LDL (AHA/ACC), αλλιώς κάτω από 10% (Π.Ο.Υ.) · φυτικές ίνες 30 g (Reynolds 2019) · αλάτι κάτω από 5 g (Π.Ο.Υ.).',
  accuracy: 'Οι τύποι για τις θερμίδες πέφτουν συχνά 10–15% έξω σε έναν άνθρωπο. Γι’ αυτό η εφαρμογή τους διορθώνει με τα '
      'δικά σου δεδομένα. Ό,τι πει ο γιατρός σου υπερισχύει.',
  cite: 'Mifflin 1990 · FAO/WHO/UNU 2004 · Hall 2008 · Helms 2014 · Jensen 2013 (AHA/ACC/TOS) · Morton 2018 · EFSA 2010 · '
      'Eckel 2013 · Reynolds 2019 · Π.Ο.Υ. 2012',
);

// ---------------------------------------------------------------------------------------------------- οδηγός

/// Οδηγός με κάρτες (σχέδια 12/11, 1α–1στ): μία ερώτηση ανά οθόνη, προσυμπληρωμένος, «Αργότερα» πάντα.
class GoalsWizard extends StatefulWidget {
  const GoalsWizard({super.key, required this.store, this.now, this.fromPage = false});
  final HealthStore store;
  final DateTime? now;

  /// Άνοιξε από τη σελίδα «Στόχοι» («Ξανά ο οδηγός»): στο τέλος γυρίζει πίσω σε αυτήν, όχι δεύτερη σελίδα από πάνω.
  final bool fromPage;

  static Route<void> route(HealthStore store, {DateTime? now, bool fromPage = false}) => MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'Στόχοι διατροφής · οδηγός'),
      builder: (_) => GoalsWizard(store: store, now: now, fromPage: fromPage));

  @override
  State<GoalsWizard> createState() => _GoalsWizardState();
}

enum _Step { data, aim, rate, activity, doctor, summary }

class _GoalsWizardState extends State<GoalsWizard> {
  late final Goals? _old = widget.store.goals;
  late GoalAim _aim = _old?.aim ?? GoalAim.lose;
  late int _rate = () {
    final o = _old;
    if (o == null || o.aim == GoalAim.keep) return 1;
    final i = (o.aim == GoalAim.lose ? loseRates : gainRates).indexOf(o.rate);
    return i < 0 ? (o.aim == GoalAim.lose ? 1 : 0) : i;
  }();
  late int _activity = () {
    final i = activityLevels.indexOf(_old?.activity ?? 1.5);
    return i < 0 ? 1 : i;
  }();
  late bool? _doctor = _old?.doctor;
  final _kg = TextEditingController();
  int _i = 0;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void dispose() {
    _kg.dispose();
    super.dispose();
  }

  List<_Step> get _steps => [
        _Step.data,
        _Step.aim,
        if (_aim != GoalAim.keep) _Step.rate,
        _Step.activity,
        _Step.doctor,
        _Step.summary,
      ];

  double get _rateValue => switch (_aim) {
        GoalAim.lose => loseRates[_rate.clamp(0, loseRates.length - 1)],
        GoalAim.gain => gainRates[_rate.clamp(0, gainRates.length - 1)],
        GoalAim.keep => 0,
      };

  double? get _weight {
    final typed = double.tryParse(_kg.text.replaceAll(',', '.').trim());
    if (typed != null && typed >= 30 && typed <= 300) return typed;
    return widget.store.latestWeight()?.kg;
  }

  GoalCalc? get _calc {
    final p = widget.store.profile;
    final age = p.ageOn(_now), h = p.heightCm, kg = _weight;
    if (age == null || age < 18 || h == null || kg == null || (p.sex != 'm' && p.sex != 'f')) return null;
    return computeGoals(
        male: p.male, age: age, heightCm: h, kg: kg, aim: _aim, rate: _rateValue, activity: activityLevels[_activity], doctor: _doctor == true);
  }

  bool _canGo(_Step s) => switch (s) {
        _Step.data => _calc != null,
        _Step.doctor => _doctor != null,
        _ => true,
      };

  void _next() {
    final steps = _steps;
    if (_i < steps.length - 1) {
      setState(() => _i++);
      return;
    }
    _save();
  }

  void _save() {
    final p = widget.store.profile;
    final age = p.ageOn(_now)!;
    final o = _old;
    final g = Goals(
      aim: _aim,
      rate: _rateValue,
      activity: activityLevels[_activity],
      doctor: _doctor == true,
      since: '${_now.year}-${two(_now.month)}-${two(_now.day)}',
      kg: _weight!,
      age: age,
      heightCm: p.heightCm!,
      male: p.male,
      // Ό,τι είχες αλλάξει στη χοληστερίνη μένει· οι θερμίδες/πρωτεΐνη ξαναϋπολογίζονται.
      nutsG: o?.nutsG ?? defaultNutsG,
      branG: o?.branG ?? defaultBranG,
      betaPer100: o?.betaPer100,
      legumesWeek: o?.legumesWeek ?? defaultLegumesWeek,
      fishWeek: o?.fishWeek ?? defaultFishWeek,
    );
    widget.store.setGoals(g);
    if (widget.fromPage) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(GoalsPage.route(widget.store, now: widget.now));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final steps = _steps;
        if (_i >= steps.length) _i = steps.length - 1;
        final step = steps[_i];
        final last = step == _Step.summary;
        return PopScope(
          canPop: _i == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _i > 0) setState(() => _i--);
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text('Στόχοι διατροφής · ${_i + 1} από ${steps.length}', style: TextStyle(fontSize: 15, color: c.textSecondary)),
              actions: [
                TextButton(
                  key: const ValueKey('wizard-later'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Αργότερα'),
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Row(children: [
                    for (var k = 0; k < steps.length; k++) ...[
                      if (k > 0) const SizedBox(width: 4),
                      Expanded(
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(color: k <= _i ? c.food : c.hairline, borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ListView(
                    key: ValueKey('wizard-${step.name}'),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: _page(context, step),
                  ),
                ),
              ),
            ),
            bottomNavigationBar: SafeArea(
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: FilledButton(
                      key: const ValueKey('wizard-next'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: c.foodSolid, foregroundColor: c.onSolid),
                      onPressed: _canGo(step) ? _next : null,
                      child: Text(last ? 'Αποθήκευση στόχων' : 'Συνέχεια'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _q(BuildContext context, String q, String sub) {
    final c = Aigaio.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(q, style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -0.6, color: c.text)),
      const SizedBox(height: 8),
      Text(sub, style: TextStyle(fontSize: 15, height: 1.45, color: c.textSecondary)),
      const SizedBox(height: 18),
    ]);
  }

  List<Widget> _page(BuildContext context, _Step step) {
    final c = Aigaio.of(context);
    final p = widget.store.profile;
    switch (step) {
      case _Step.data:
        final age = p.ageOn(_now);
        final w = widget.store.latestWeight();
        final missing = missingForGoals(age: age, sex: p.sex, heightCm: p.heightCm, kg: _weight);
        return [
          _q(context, 'Πρώτα, τα στοιχεία σου', 'Από «Τα στοιχεία μου» και τη ζυγαριά. Άλλαξε ό,τι δεν είναι σωστό.'),
          AppCard(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              InfoRow('Ηλικία', age == null ? '—' : '$age ετών'),
              InfoRow('Φύλο', p.male ? 'Άνδρας' : (p.female ? 'Γυναίκα' : '—')),
              InfoRow('Ύψος', p.heightCm == null ? '—' : '${dec(p.heightCm!, p.heightCm! % 1 == 0 ? 0 : 1)} cm'),
              InfoRow('Βάρος', w == null ? '—' : '${dec(w.kg)} kg · ζυγαριά ${shortDayDate(w.day)}'),
            ]),
          ),
          const SizedBox(height: 12),
          if (age == null || p.heightCm == null || (p.sex != 'm' && p.sex != 'f'))
            OutlinedButton(
              key: const ValueKey('wizard-me'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () async {
                await Navigator.of(context).push(MePage.route(widget.store));
                if (mounted) setState(() {});
              },
              child: const Text('Συμπλήρωσε τα στοιχεία μου'),
            ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('wizard-kg'),
            controller: _kg,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(
              labelText: w == null ? 'Βάρος (kg)' : 'Άλλο βάρος (kg), αν η ζύγιση είναι παλιά',
              helperText: w == null ? 'Δεν βρήκα ζύγιση· γράψε το βάρος σου ή ζυγίσου πρώτα.' : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Λείπει: ${missing.join(', ')}.', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.warn)),
          ],
          if (age != null && age < 18) ...[
            const SizedBox(height: 12),
            Text('Οι τύποι είναι για ενήλικες.', style: TextStyle(fontSize: 14, color: c.warn)),
          ],
        ];
      case _Step.aim:
        return [
          _q(context, 'Τι θέλεις πρώτα;', 'Αλλάζει μόνο τις θερμίδες. Η πρωτεΐνη μένει ίδια, τα κορεσμένα ίδιο ποσοστό.'),
          _Opt(
            k: 'aim-lose',
            on: _aim == GoalAim.lose,
            title: 'Λιγότερο λίπος, κρατώντας τους μύες',
            sub: 'Μικρό έλλειμμα θερμίδων, αρκετή πρωτεΐνη, βάρη. Κατάλληλο όταν το λίπος είναι κυρίως στην κοιλιά.',
            recommended: true,
            onTap: () => setState(() {
              _aim = GoalAim.lose;
              _rate = 1;
            }),
          ),
          _Opt(
            k: 'aim-keep',
            on: _aim == GoalAim.keep,
            title: 'Ίδιο βάρος, καλύτερη υγεία',
            sub: 'Θερμίδες όσες καις. Αλλάζει μόνο η ποιότητα του φαγητού.',
            onTap: () => setState(() => _aim = GoalAim.keep),
          ),
          _Opt(
            k: 'aim-gain',
            on: _aim == GoalAim.gain,
            title: 'Περισσότεροι μύες',
            sub: 'Μικρό πλεόνασμα θερμίδων. Το λίπος μπορεί να ανέβει λίγο.',
            onTap: () => setState(() {
              _aim = GoalAim.gain;
              _rate = 0;
            }),
          ),
        ];
      case _Step.rate:
        final kg = _weight ?? 0;
        final list = _aim == GoalAim.lose ? loseRates : gainRates;
        final words = _aim == GoalAim.lose ? const ['Ήπια', 'Μέτρια', 'Γρήγορα'] : const ['Αργά', 'Πιο γρήγορα'];
        final rec = _aim == GoalAim.lose ? 1 : 0;
        return [
          _q(context, 'Πόσο γρήγορα;', 'Σε ποσοστό του βάρους σου την εβδομάδα. Πιο αργά κρατάς πιο εύκολα τους μύες.'),
          for (var k = 0; k < list.length; k++)
            _Opt(
              k: 'rate-$k',
              on: _rate == k,
              title: '${words[k]} · ${rateKgText(kg, list[k])}',
              sub: '${ratePctText(list[k])} του βάρους · περίπου ${(kg * list[k] * kcalPerKg / 7 / 10).round() * 10} kcal '
                  '${_aim == GoalAim.lose ? 'λιγότερες' : 'περισσότερες'} τη μέρα',
              recommended: k == rec,
              onTap: () => setState(() => _rate = k),
            ),
          const SizedBox(height: 4),
          _Note(
            _aim == GoalAim.lose
                ? 'Ποτέ κάτω από ${p.female ? '1.200' : '1.500'} kcal. Αν χάνεις πάνω από 1% την εβδομάδα για 2 εβδομάδες, '
                    'ανέβασε τις θερμίδες από τη σελίδα «Στόχοι».'
                : 'Αύξηση 0,25–0,5% την εβδομάδα για όσους ξεκινούν βάρη (Iraki 2019).',
          ),
        ];
      case _Step.activity:
        return [
          _q(context, 'Πόσο κινείσαι;', 'Μια πρώτη εκτίμηση. Οι ζυγίσεις σου θα δείξουν αν πέτυχε.'),
          _Opt(k: 'act-0', on: _activity == 0, title: 'Λίγο', sub: 'Γραφείο, λίγο περπάτημα, χωρίς προπόνηση', onTap: () => setState(() => _activity = 0)),
          _Opt(
            k: 'act-1',
            on: _activity == 1,
            title: 'Μέτρια',
            sub: 'Γραφείο, και 3–4 προπονήσεις ή περπατήματα την εβδομάδα',
            recommended: true,
            onTap: () => setState(() => _activity = 1),
          ),
          _Opt(k: 'act-2', on: _activity == 2, title: 'Πολύ', sub: 'Δουλειά στο πόδι, ή άσκηση σχεδόν κάθε μέρα', onTap: () => setState(() => _activity = 2)),
        ];
      case _Step.doctor:
        return [
          _q(context, 'Σου ζήτησε ο γιατρός να πέσει η χοληστερίνη (LDL);', 'Ό,τι πει ο γιατρός έχει πάντα προτεραιότητα.'),
          _Opt(
            k: 'doc-yes',
            on: _doctor == true,
            title: 'Ναι',
            sub: 'Κορεσμένα έως 6% των θερμίδων, φυτικές ίνες 30 g, αλάτι κάτω από 5 g. Ανοίγει η κάρτα «Χοληστερίνη», με τους '
                'ξηρούς καρπούς, το πίτουρο βρώμης, τα όσπρια και το ψάρι.',
            onTap: () => setState(() => _doctor = true),
          ),
          _Opt(
            k: 'doc-no',
            on: _doctor == false,
            title: 'Όχι',
            sub: 'Οι γενικές οδηγίες: κορεσμένα κάτω από 10% των θερμίδων.',
            onTap: () => setState(() => _doctor = false),
          ),
          const SizedBox(height: 4),
          const _Note('Οι τιμές των εξετάσεων (LDL, HDL, τριγλυκερίδια) θα μπαίνουν στις «Εξετάσεις», που έρχονται σύντομα.'),
        ];
      case _Step.summary:
        final g = _calc!;
        final per = g.delta.abs().round();
        return [
          _q(context, 'Οι στόχοι σου', 'Κάθε αριθμός αλλάζει αργότερα από τη σελίδα «Στόχοι».'),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Θερμίδες τη μέρα', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.textSecondary)),
              const SizedBox(height: 4),
              BigValue(thousands(g.kcal), unit: 'kcal', size: 44),
              const SizedBox(height: 6),
              Text(
                _aim == GoalAim.keep
                    ? 'όσες καις, περίπου ${thousands(g.tdee)}'
                    : 'καις περίπου ${thousands(g.tdee)} · ${_aim == GoalAim.lose ? '−' : '+'}$per για ${rateKgText(_weight!, _rateValue)}',
                style: TextStyle(fontSize: 13.5, color: c.textSecondary, fontFeatures: tabular),
              ),
              if (g.floored)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Ανέβηκε στο κάτω όριο ασφαλείας (${thousands(g.kcal)} kcal).',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.warn)),
                ),
              const Hairline(vertical: 12),
              InfoRow('Πρωτεΐνη', '${g.protein} g'),
              InfoRow('Λίπος', '${g.fatLo}–${g.fatHi} g'),
              InfoRow('Κορεσμένα', 'έως ${g.satMax} g · ${g.satPct}%'),
              InfoRow('Φυτικές ίνες', '${g.fiber} g ή περισσότερες'),
              InfoRow('Αλάτι', 'κάτω από ${dec(g.salt, 0)} g'),
              InfoRow('Υδατάνθρακες', 'ό,τι μένει · ~${g.carbsEst} g'),
            ]),
          ),
          const SizedBox(height: 12),
          _Note(
              'Με ζυγίσεις τις μέρες σου (${_weighDays(p)}) και φαγητό σχεδόν κάθε μέρα, από '
              '${longDate(DateTime(_now.year, _now.month, _now.day + 21))} θα φαίνεται πόσες θερμίδες καις πραγματικά. Τότε, και '
              'μετά κάθε ${weekdayNames[_now.weekday - 1]}, η Σήμερα θα σου προτείνει διόρθωση του στόχου.'),
        ];
    }
  }
}

/// «7/12» από «2026-12-07».
String _dm(String day) {
  final d = DateTime.parse(day);
  return '${d.day}/${d.month}';
}

String _weighDays(Profile p) => (p.weighDays.toList()..sort()).map((d) => weekdayChips[d - 1]).join(' · ');

class _Opt extends StatelessWidget {
  const _Opt({required this.k, required this.on, required this.title, required this.sub, required this.onTap, this.recommended = false});
  final String k;
  final bool on;
  final String title;
  final String sub;
  final bool recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        selected: on,
        child: Material(
          color: on ? c.tint(c.food) : c.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: on ? c.food : c.hairline, width: on ? 2 : 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('opt-$k'),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded, color: on ? c.food : c.textTertiary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 4, children: [
                      Text(title, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: c.text)),
                      if (recommended)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: c.tint(c.food), borderRadius: BorderRadius.circular(999)),
                          child: Text('Προτείνεται', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.food)),
                        ),
                    ]),
                    const SizedBox(height: 4),
                    Text(sub, style: TextStyle(fontSize: 13.5, height: 1.4, color: c.textSecondary)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Text(text, style: TextStyle(fontSize: 13.5, height: 1.45, color: c.textSecondary));
  }
}

// ---------------------------------------------------------------------------------------------------- σελίδα

/// Σελίδα «Στόχοι» (σχέδια 12/11, 2α).
class GoalsPage extends StatelessWidget {
  const GoalsPage({super.key, required this.store, this.now});
  final HealthStore store;
  final DateTime? now;

  static Route<void> route(HealthStore store, {DateTime? now}) =>
      MaterialPageRoute<void>(settings: const RouteSettings(name: 'Στόχοι'), builder: (_) => GoalsPage(store: store, now: now));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final c = Aigaio.of(context);
        final g = store.goals;
        final p = store.profile;
        if (g == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Στόχοι')),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              EmptyCard(
                title: 'Δεν υπάρχουν στόχοι',
                text: 'Ο οδηγός θέλει 2 λεπτά.',
                buttonText: 'Ο οδηγός',
                onPressed: () => Navigator.of(context).pushReplacement(GoalsWizard.route(store, now: now)),
              ),
            ]),
          );
        }
        final calc = g.calc;
        final today = now ?? DateTime.now();
        final next = nextCheckDay(g, today);
        final nextText = sameDay(next, today) ? 'σήμερα' : longDate(next);
        final lastApplied = g.log.where((l) => l.applied).lastOrNull;
        final adaptCards = _adaptCards(context, g, today, next);
        Widget editRow(String key, String label, String value, VoidCallback onTap) => InkWell(
              key: ValueKey(key),
              onTap: onTap,
              child: InfoRow(label, value),
            );
        return Scaffold(
          appBar: AppBar(title: const Text('Στόχοι')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                  AppCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      CardHeader(icon: Icons.restaurant_rounded, title: 'Θερμίδες τη μέρα', color: c.food, trailing: const InfoDot(goalsInfo)),
                      const SizedBox(height: 8),
                      InkWell(
                        key: const ValueKey('goals-kcal'),
                        onTap: () => _editKcal(context, g),
                        child: BigValue(thousands(g.kcal), unit: 'kcal', size: 44),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        [
                          aimText(g.aim),
                          if (g.aim != GoalAim.keep) '${rateWord(g.aim, g.rate)} · ${rateKgText(g.kg, g.rate)}',
                        ].join(' · '),
                        style: TextStyle(fontSize: 13.5, color: c.textSecondary),
                      ),
                      if (g.kcalSet != null)
                        Text('Τον άλλαξες εσύ (ο υπολογισμός λέει ${thousands(calc.kcal)}).', style: TextStyle(fontSize: 13.5, color: c.textSecondary))
                      else if (g.kcalAdapt != null && lastApplied != null)
                        Text('Από τα δεδομένα σου, ${_dm(lastApplied.day)}', style: TextStyle(fontSize: 13.5, color: c.textSecondary))
                      else
                        Text('Από τον τύπο, ως τον πρώτο έλεγχο με τα δεδομένα σου', style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
                      Text('${g.log.isEmpty ? 'Πρώτος' : 'Επόμενος'} έλεγχος: $nextText',
                          key: const ValueKey('goals-next-check'), style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        key: const ValueKey('goals-how'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), foregroundColor: c.food),
                        onPressed: () => showHowCalculated(context, g),
                        child: const Text('Πώς υπολογίστηκε'),
                      ),
                    ]),
                  ),
                  for (final card in adaptCards) ...[const SizedBox(height: 12), card],
                  const SizedBox(height: 12),
                  AppCard(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      editRow('goals-protein', 'Πρωτεΐνη', '${g.protein} g${g.proteinSet != null ? ' · δική σου' : ''}', () => _editProtein(context, g)),
                      InfoRow('Λίπος', '${g.fatLo}–${g.fatHi} g'),
                      InfoRow('Κορεσμένα', 'έως ${g.satMax} g · ${g.satPct}%'),
                      InfoRow('Φυτικές ίνες', '${g.fiber} g+'),
                      InfoRow('Αλάτι', 'κάτω από ${dec(g.salt, 0)} g'),
                      const InfoRow('Υδατάνθρακες', 'ό,τι μένει'),
                    ]),
                  ),
                  if (g.doctor) ...[
                    const GroupLabel('Χοληστερίνη · από τον γιατρό'),
                    AppCard(
                      padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        editRow('goals-nuts', 'Ξηροί καρποί', '${g.nutsG} g τη μέρα',
                            () => _editInt(context, 'Ξηροί καρποί τη μέρα', g.nutsG, 0, 100, 'g', (v) => g.copyWith(nutsG: v))),
                        editRow('goals-bran', 'Πίτουρο βρώμης για 3 g β-γλυκάνες',
                            '${g.branG} g${g.betaPer100 == null ? '' : ' · από την ετικέτα'}', () => _editBran(context, g)),
                        editRow('goals-legumes', 'Όσπρια', '${g.legumesWeek} φορές την εβδομάδα',
                            () => _editInt(context, 'Όσπρια την εβδομάδα', g.legumesWeek, 0, 7, 'φορές', (v) => g.copyWith(legumesWeek: v))),
                        editRow('goals-fish', 'Ψάρι', '${g.fishWeek} φορές την εβδομάδα',
                            () => _editInt(context, 'Ψάρι την εβδομάδα', g.fishWeek, 0, 7, 'φορές', (v) => g.copyWith(fishWeek: v))),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Από το πλάνο σου. Τα γραμμάρια του πίτουρου βγαίνουν από τις β-γλυκάνες που γράφει η συσκευασία του δικού σου '
                      'προϊόντος (EFSA: 3 g τη μέρα). Το ψάρι μπαίνει γιατί παίρνει τη θέση του κρέατος και για τα τριγλυκερίδια.',
                      style: TextStyle(fontSize: 13, height: 1.45, color: c.textSecondary),
                    ),
                  ],
                  const GroupLabel('Ζύγισμα'),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: NavRow(
                      key: const ValueKey('goals-weigh'),
                      icon: Icons.monitor_weight_rounded,
                      color: c.body,
                      title: 'Μέρες: ${_weighDays(p)}, πρωί',
                      text: 'Μέση με μεζούρα: ${weekdayNames[p.waistDay - 1]}',
                      onTap: () => Navigator.of(context).push(MePage.route(store)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    key: const ValueKey('goals-wizard'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () => Navigator.of(context).push(GoalsWizard.route(store, now: now, fromPage: true)),
                    child: const Text('Ξανά ο οδηγός'),
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  /// A4: «Πόσο καις, από τα δεδομένα σου» (μετά τον πρώτο έλεγχο) ή «Πριν από τον πρώτο έλεγχο» (πρόοδος).
  List<Widget> _adaptCards(BuildContext context, Goals g, DateTime today, DateTime next) {
    final c = Aigaio.of(context);
    final small = TextStyle(fontSize: 13.5, height: 1.4, color: c.textSecondary);
    final title = TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text);
    final days = DateTime(next.year, next.month, next.day).difference(DateTime(today.year, today.month, today.day)).inDays;
    final when = days <= 0 ? 'σήμερα' : (days == 1 ? 'αύριο' : 'σε $days μέρες');
    if (g.log.isNotEmpty) {
      return [
        AppCard(
          key: const ValueKey('goals-adapt-log'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Πόσο καις, από τα δεδομένα σου', style: title),
            const SizedBox(height: 4),
            InfoRow('Τύπος (αρχή, ${_dm(g.since)})', thousands((g.calc.tdee / 10).round() * 10)),
            for (final l in g.log.reversed.take(6).toList().reversed)
              InfoRow(
                'Έλεγχος ${_dm(l.day)}',
                '${thousands((l.tdee / 10).round() * 10)} · '
                    '${l.applied ? 'στόχος ${thousands(l.before)} → ${thousands(l.after)}' : 'στόχος έμεινε ${thousands(l.before)}'}',
              ),
            InfoRow('Επόμενος έλεγχος', when),
          ]),
        ),
      ];
    }
    final food = FoodStore.shared;
    final d = store.data;
    if (food == null || !food.loaded || d == null) return const [];
    final r = readiness(goals: g, today: today, weights: dailyWeights(d.body), intake: (a, b) => dailyIntake(food, a, b));
    return [
      AppCard(
        key: const ValueKey('goals-adapt-ready'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Πριν από τον πρώτο έλεγχο', style: title),
          const SizedBox(height: 2),
          Text('Στις 3 τελευταίες εβδομάδες, ως χθες:', style: small),
          InfoRow('Μέρες με φαγητό', '${r.intakeDays} από $adaptMinIntakeDays'),
          InfoRow('Ζυγίσεις', '${r.weighIns} από $adaptMinWeighIns'),
          InfoRow('Έλεγχος', when),
          const SizedBox(height: 4),
          Text('Μετράνε μέρες με τουλάχιστον το 60% του στόχου γραμμένο· οι ζυγίσεις έρχονται μόνες τους από την InBody.', style: small),
        ]),
      ),
    ];
  }

  Future<void> _editInt(BuildContext context, String title, int current, int min, int max, String unit, Goals Function(int) apply) async {
    final v = await askNumber(context, title: title, current: current, min: min, max: max, unit: unit);
    if (v != null) store.setGoals(apply(v));
  }

  Future<void> _editKcal(BuildContext context, Goals g) async {
    final v = await askNumber(context,
        title: 'Θερμίδες τη μέρα', current: g.kcal, min: g.male ? 1500 : 1200, max: 5000, unit: 'kcal', resetText: g.kcalAdapt != null
            ? 'Από τα δεδομένα σου (${thousands(g.kcalAdapt!)})'
            : 'Από τον υπολογισμό (${thousands(g.calc.kcal)})');
    if (v == null) return;
    store.setGoals(v < 0 ? g.copyWith(clearKcal: true) : g.copyWith(kcalSet: v));
  }

  Future<void> _editProtein(BuildContext context, Goals g) async {
    final v = await askNumber(context,
        title: 'Πρωτεΐνη τη μέρα', current: g.protein, min: 40, max: 300, unit: 'g', resetText: 'Από τον υπολογισμό (${g.calc.protein} g)');
    if (v == null) return;
    store.setGoals(v < 0 ? g.copyWith(clearProtein: true) : g.copyWith(proteinSet: v));
  }

  Future<void> _editBran(BuildContext context, Goals g) async {
    final r = await showDialog<(int, double?)>(context: context, builder: (_) => _BranDialog(goals: g));
    if (r != null) store.setGoals(g.copyWith(branG: r.$1, betaPer100: r.$2, clearBeta: r.$2 == null));
  }
}

/// Αριθμός με όρια. Επιστρέφει −1 για «από τον υπολογισμό» (όταν δίνεται [resetText]).
Future<int?> askNumber(BuildContext context,
    {required String title, required int current, required int min, required int max, required String unit, String? resetText}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _NumberDialog(title: title, current: current, min: min, max: max, unit: unit, resetText: resetText),
  );
}

class _NumberDialog extends StatefulWidget {
  const _NumberDialog({required this.title, required this.current, required this.min, required this.max, required this.unit, this.resetText});
  final String title;
  final int current, min, max;
  final String unit;
  final String? resetText;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final _t = TextEditingController(text: '${widget.current}');
  String? _err;

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  void _ok() {
    final v = int.tryParse(_t.text.trim());
    if (v == null || v < widget.min || v > widget.max) {
      setState(() => _err = 'Από ${widget.min} ως ${widget.max}.');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          key: const ValueKey('number-field'),
          controller: _t,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(suffixText: widget.unit, errorText: _err),
          onSubmitted: (_) => _ok(),
        ),
        if (widget.resetText != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () => Navigator.pop(context, -1), child: Text(widget.resetText!)),
          ),
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Άκυρο')),
        FilledButton(key: const ValueKey('number-ok'), onPressed: _ok, child: const Text('Εντάξει')),
      ],
    );
  }
}

class _BranDialog extends StatefulWidget {
  const _BranDialog({required this.goals});
  final Goals goals;

  @override
  State<_BranDialog> createState() => _BranDialogState();
}

class _BranDialogState extends State<_BranDialog> {
  late final _beta = TextEditingController(text: widget.goals.betaPer100 == null ? '' : dec(widget.goals.betaPer100!));
  late final _grams = TextEditingController(text: '${widget.goals.branG}');

  @override
  void dispose() {
    _beta.dispose();
    _grams.dispose();
    super.dispose();
  }

  double? get _b => double.tryParse(_beta.text.replaceAll(',', '.').trim());

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final b = _b;
    final fromLabel = b == null ? null : branGramsFor(b);
    return AlertDialog(
      title: const Text('Πίτουρο βρώμης'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Γράψε τις β-γλυκάνες ανά 100 g από τη συσκευασία σου. Βγαίνουν τα γραμμάρια για 3 g τη μέρα (EFSA).',
            style: TextStyle(fontSize: 14, height: 1.4, color: c.textSecondary)),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('bran-beta'),
          controller: _beta,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: const InputDecoration(labelText: 'β-γλυκάνες ανά 100 g', suffixText: 'g'),
          onChanged: (_) => setState(() {
            final g = _b == null ? null : branGramsFor(_b!);
            if (g != null) _grams.text = '$g';
          }),
        ),
        if (b != null && fromLabel == null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Δεν μοιάζει σωστό (από 0 ως 40 g).', style: TextStyle(fontSize: 13, color: c.bad)),
          ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('bran-grams'),
          controller: _grams,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Πίτουρο τη μέρα', suffixText: 'g'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Άκυρο')),
        FilledButton(
          key: const ValueKey('bran-ok'),
          onPressed: () {
            final g = int.tryParse(_grams.text.trim());
            if (g == null || g < 0 || g > 150) return;
            Navigator.pop(context, (g, fromLabel == null ? null : b));
          },
          child: const Text('Εντάξει'),
        ),
      ],
    );
  }
}

/// «Πώς υπολογίστηκαν οι θερμίδες» (σχέδια 12/11, 2β).
Future<void> showHowCalculated(BuildContext context, Goals g) {
  final calc = g.calc;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    routeSettings: const RouteSettings(name: 'Πώς υπολογίστηκε'),
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) {
      final c = Aigaio.of(context);
      final small = TextStyle(fontSize: 13, height: 1.4, color: c.textSecondary);
      final sex = g.male ? '+ 5' : '− 161';
      String n(double v) => thousands(v.round());
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Πώς υπολογίστηκαν οι θερμίδες', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.text)),
          const SizedBox(height: 10),
          InfoRow('1 · Σε πλήρη ξεκούραση', '${n(calc.bmr)} kcal'),
          Text('Mifflin-St Jeor: 10 × ${dec(g.kg)} + 6,25 × ${dec(g.heightCm, g.heightCm % 1 == 0 ? 0 : 1)} − 5 × ${g.age} $sex', style: small),
          const SizedBox(height: 6),
          InfoRow('2 · Με την κίνησή σου (× ${dec(g.activity)})', '${n(calc.tdee)} kcal'),
          Text('«${activityText(g.activity)}». Είναι εκτίμηση: σε κάθε άνθρωπο πέφτει ως και 10–15% έξω.', style: small),
          if (g.aim != GoalAim.keep) ...[
            const SizedBox(height: 6),
            InfoRow('3 · Για ${rateKgText(g.kg, g.rate)}', '${calc.delta < 0 ? '−' : '+'}${n(calc.delta.abs())} kcal'),
            Text('${dec(g.kg * g.rate, 2)} kg × 7.700 kcal ÷ 7 μέρες', style: small),
          ],
          const Hairline(vertical: 12),
          InfoRow('Στόχος', '${thousands(calc.kcal)} kcal'),
          if (calc.floored) Text('Ανέβηκε στο κάτω όριο ασφαλείας.', style: small),
          if (g.kcalSet != null) Text('Ισχύει ο δικός σου: ${thousands(g.kcalSet!)} kcal.', style: small),
          if (g.kcalSet == null && g.kcalAdapt != null)
            Text('Ισχύει ο στόχος από τα δεδομένα σου: ${thousands(g.kcalAdapt!)} kcal.', style: small),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.tint(c.food), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Μετά από 3 εβδομάδες, από τα δικά σου δεδομένα', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
              const SizedBox(height: 4),
              Text(
                'Συγκρίνοντας τι έφαγες με το πώς άλλαξε το βάρος σου, φαίνεται πόσες θερμίδες καις πραγματικά. Κάθε εβδομάδα '
                'η Σήμερα σού προτείνει διόρθωση του στόχου, το πολύ 150 kcal τη φορά· αλλάζει μόνο αν πατήσεις «Εφάρμοσε».',
                style: TextStyle(fontSize: 14, height: 1.45, color: c.text),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Text('Πηγές: Mifflin 1990 · FAO/WHO/UNU 2004 · Hall 2008 · Jensen 2013 (AHA/ACC/TOS)', style: small),
        ]),
      );
    },
  );
}
