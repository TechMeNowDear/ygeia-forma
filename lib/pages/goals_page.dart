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
  // Τελικός έλεγχος, Συμβούλιο 2 (Α1, Α2): η πρώτη εβδομάδα δεν μετρά· πρόταση μόνο πέρα από το εύρος των ζυγίσεων.
  shows: 'Πόσο να φας για τον στόχο σου. Ο στόχος θερμίδων είναι αρχική εκτίμηση. Η πρώτη εβδομάδα δεν μετρά, γιατί τότε '
      'φεύγουν κυρίως νερά. Μετά από άλλες 3 εβδομάδες με ζυγίσεις και καταγραφή φαγητού φαίνεται πόσες θερμίδες καις '
      'πραγματικά, και κάθε εβδομάδα η εφαρμογή ελέγχει τον στόχο. Προτείνει διόρθωση (το πολύ 150 kcal τη φορά) μόνο όταν '
      'η διαφορά ξεπερνά το φυσιολογικό εύρος των ζυγίσεων. Αλλάζει μόνο όταν πατήσεις «Εφάρμοσε».',
  // Έλεγχος 13/11 (S1-12): η EFSA δίνει εύρος 20–35% για τα λιπαρά· το κάτω όριο 25% είναι δική μας επιλογή μέσα σε αυτό.
  compare: 'Πρωτεΐνη 1,6 g ανά κιλό (Morton 2018) · λιπαρά 25–35% των θερμίδων (μέσα στο εύρος 20–35% της EFSA) · κορεσμένα '
      'λιπαρά έως 6% όταν ο γιατρός ζητά να πέσει η LDL (AHA/ACC), αλλιώς κάτω από 10% (Π.Ο.Υ.) · φυτικές ίνες 30 g '
      '(Reynolds 2019) · αλάτι κάτω από 5 g (Π.Ο.Υ.).',
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

/// Βάρος όπως γράφεται: ως 3 ψηφία και, αν θέλεις, κόμμα ή τελεία με 1–2 δεκαδικά.
final _kgPattern = RegExp(r'^\d{1,3}(?:[.,]\d{1,2})?$');

/// Μια εκτίμηση «πόσο καις» από τα δεδομένα θεωρείται πρόσφατη ως 6 εβδομάδες (όσο και το μεγαλύτερο παράθυρο).
const _freshEstimateDays = 42;

/// «τη Δευτέρα 14 Δεκεμβρίου», «το Σάββατο 12 Δεκεμβρίου».
String _onDay(DateTime d) => '${const ['τη', 'την', 'την', 'την', 'την', 'το', 'την'][d.weekday - 1]} ${longDate(d)}';

/// «180» ή «174,5» (ύψος σε cm).
String _cm(double h) => dec(h, h % 1 == 0 ? 0 : 1);

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
  late DoctorTargets _targets = _old?.docTargets ?? const DoctorTargets();
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

  /// Η τελευταία ζύγιση της ζυγαριάς που μετρά: η πρώτη της πιο πρόσφατης μέρας (η πρωινή), χωρίς ζυγίσεις που δεν
  /// μπορεί να είναι δικές σου (έλεγχος 13/11, S11-2: ζύγιση παιδιού 45 kg προσυμπλήρωνε τον οδηγό και έβγαζε στόχους για
  /// 45 κιλά).
  ({double kg, DateTime day})? _scale() {
    final d = widget.store.data;
    if (d == null) return null;
    // Μόνο βάρη που δέχονται οι στόχοι (30–300 kg, όπως και το πεδίο)· αλλιώς αποθηκεύονταν στόχοι που δεν ξαναδιαβάζονται.
    final used = [for (final w in dailyWeights(d.body)) if (w.$2 >= 30 && w.$2 <= 300) w];
    if (used.isEmpty) return null;
    return (kg: used.last.$2, day: used.last.$1);
  }

  /// Το βάρος που γράφτηκε με το χέρι: null αν το πεδίο είναι κενό ή δεν είναι βάρος από 30 ως 300 kg («82,5» ή «82.5»).
  double? get _typedKg {
    final text = _kg.text.trim();
    if (!_kgPattern.hasMatch(text)) return null;
    final v = double.tryParse(text.replaceAll(',', '.'));
    return v != null && v >= 30 && v <= 300 ? v : null;
  }

  /// Γράφτηκε κάτι στο πεδίο που δεν είναι βάρος (π.χ. «825» αντί για «82,5»). Έλεγχος 13/11 (S11-10 / U3b-25): πριν, ο
  /// οδηγός το αγνοούσε χωρίς λέξη και υπολόγιζε με τη ζύγιση της ζυγαριάς· τώρα το πεδίο το λέει και περιμένει.
  bool get _kgInvalid => _kg.text.trim().isNotEmpty && _typedKg == null;

  double? get _weight {
    if (_kgInvalid) return null;
    return _typedKg ?? _scale()?.kg;
  }

  /// Η τελευταία εκτίμηση «πόσο καις» από τα δεδομένα σου, αν είναι πρόσφατη (ως [_freshEstimateDays] μέρες).
  double? get _freshTdee {
    final o = _old;
    final te = o?.tdeeEst;
    if (o == null || te == null) return null;
    AdaptLog? last;
    for (final l in o.log) {
      if (!l.fast) last = l;
    }
    final day = last == null ? null : DateTime.tryParse(last.day);
    if (day == null) return null;
    final age = daysBetween(day, _now);
    return age >= 0 && age <= _freshEstimateDays ? te : null;
  }

  /// Οι στόχοι που θα αποθηκευτούν με όσα έχουν απαντηθεί ως τώρα (null όσο λείπει κάτι). Η σύνοψη δείχνει ακριβώς αυτούς.
  ///
  /// Έλεγχος 13/11 (S1-11). Πριν, το «Ξανά ο οδηγός» πετούσε σιωπηλά τον στόχο και την εκτίμηση από τα δεδομένα σου και
  /// γύριζε στον τύπο για 4 εβδομάδες (π.χ. από 1.800 σε 2.060 kcal για κάποιον που καίει 2.250). Τώρα, όταν υπάρχει
  /// πρόσφατη εκτίμηση, ο νέος στόχος βγαίνει από αυτήν (εκτίμηση ± ο ρυθμός που διάλεξες, ποτέ κάτω από το όριο
  /// ασφαλείας)· και αν ο σκοπός («λιγότερο λίπος» κ.λπ.) δεν άλλαξε, ο εβδομαδιαίος έλεγχος συνεχίζει στις ίδιες μέρες.
  /// Αν άλλαξε ο σκοπός, η αρχή είναι σήμερα: η πρώτη εβδομάδα (νερά) πάλι δεν μετρά.
  Goals? _draft() {
    final p = widget.store.profile;
    final calc = _calc;
    final age = p.ageOn(_now), h = p.heightCm, kg = _weight;
    if (calc == null || age == null || h == null || kg == null) return null;
    final o = _old;
    final te = _freshTdee;
    // Οι παλιοί στόχοι, μόνο όταν ο έλεγχος συνεχίζει στις ίδιες μέρες (πρόσφατη εκτίμηση και ίδιος σκοπός).
    final same = te != null && o != null && o.aim == _aim ? o : null;
    final floor = p.male ? kcalFloorMale : kcalFloorFemale;
    int? adapt;
    if (te != null) {
      final v = ((te + calc.delta) / 10).round() * 10;
      adapt = v < floor ? floor : v;
    }
    return Goals(
      aim: _aim,
      rate: _rateValue,
      activity: activityLevels[_activity],
      doctor: _doctor == true,
      since: same?.since ?? '${_now.year}-${two(_now.month)}-${two(_now.day)}',
      kg: kg,
      age: age,
      heightCm: h,
      male: p.male,
      // Ό,τι είχες αλλάξει στη χοληστερίνη μένει· οι θερμίδες/πρωτεΐνη ξαναϋπολογίζονται.
      nutsG: o?.nutsG ?? defaultNutsG,
      branG: o?.branG ?? defaultBranG,
      betaPer100: o?.betaPer100,
      legumesWeek: o?.legumesWeek ?? defaultLegumesWeek,
      fishWeek: o?.fishWeek ?? defaultFishWeek,
      kcalAdapt: adapt,
      tdeeEst: te,
      checkIn: same?.checkIn,
      fastAt: same?.fastAt,
      foreignSeen: o?.foreignSeen,
      // Οι στόχοι του γιατρού και το ιστορικό των ελέγχων θερμίδων μένουν.
      docTargets: _doctor == true ? _targets : const DoctorTargets(),
      log: o?.log ?? const [],
    );
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
    final g = _draft();
    if (g == null) return;
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
    // U3b-12: το χρώμα της διατροφής και στο «Αργότερα», όπως στις άλλες οθόνες φαγητού (πριν μπλε δίπλα σε πράσινα).
    return FoodTheme(
        child: ListenableBuilder(
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
    ));
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
        final w = _scale();
        final missingProfile = age == null || p.heightCm == null || (p.sex != 'm' && p.sex != 'f');
        // Βάρος που γράφτηκε λάθος δεν είναι «λείπει βάρος»: το λέει το ίδιο το πεδίο.
        final missing = missingForGoals(age: age, sex: p.sex, heightCm: p.heightCm, kg: _kgInvalid ? 1.0 : _weight);
        return [
          _q(context, 'Πρώτα, τα στοιχεία σου', 'Από «Τα στοιχεία μου» και τη ζυγαριά. Άλλαξε ό,τι δεν είναι σωστό.'),
          AppCard(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              InfoRow('Ηλικία', age == null ? '—' : '$age ετών'),
              InfoRow('Φύλο', p.male ? 'Άνδρας' : (p.female ? 'Γυναίκα' : '—')),
              InfoRow('Ύψος', p.heightCm == null ? '—' : '${_cm(p.heightCm!)} cm'),
              InfoRow('Βάρος', w == null ? '—' : '${dec(w.kg)} kg · ζυγαριά ${shortDayDate(w.day)}'),
            ]),
          ),
          const SizedBox(height: 12),
          // Πάντα εδώ (U3b-15): η οθόνη λέει «άλλαξε ό,τι δεν είναι σωστό», άρα δίνει και τον τρόπο.
          OutlinedButton(
            key: const ValueKey('wizard-me'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () async {
              await Navigator.of(context).push(MePage.route(widget.store));
              if (mounted) setState(() {});
            },
            child: Text(missingProfile ? 'Συμπλήρωσε τα στοιχεία μου' : 'Άλλαξε τα στοιχεία μου'),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('wizard-kg'),
            controller: _kg,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              labelText: w == null ? 'Βάρος' : 'Άλλο βάρος',
              suffixText: 'kg',
              helperText: w == null ? 'Δεν βρήκα ζύγιση· γράψε το βάρος σου ή ζυγίσου πρώτα.' : 'Μόνο αν η ζύγιση είναι παλιά.',
              errorText: _kgInvalid ? 'Γράψε το βάρος από 30 ως 300 kg, π.χ. 82,5' : null,
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
        // «Προτείνεται» στο «λιγότερο λίπος» μόνο με δείκτη μάζας σώματος 25 και πάνω (U3b-23): για κανέναν άλλον δεν το
        // στηρίζουν οι τύποι.
        final kgNow = _weight, cm = p.heightCm;
        final bmi = kgNow == null || cm == null || cm <= 0 ? null : kgNow / ((cm / 100) * (cm / 100));
        return [
          _q(context, 'Τι θέλεις πρώτα;', 'Αλλάζει μόνο τις θερμίδες. Η πρωτεΐνη μένει ίδια, τα κορεσμένα ίδιο ποσοστό.'),
          _Opt(
            k: 'aim-lose',
            on: _aim == GoalAim.lose,
            title: 'Λιγότερο λίπος, κρατώντας τους μύες',
            sub: 'Μικρό έλλειμμα θερμίδων, αρκετή πρωτεΐνη, βάρη. Κατάλληλο όταν το λίπος είναι κυρίως στην κοιλιά.',
            recommended: bmi != null && bmi >= 25,
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
                ? 'Ποτέ κάτω από ${p.female ? '1.200' : '1.500'} kcal. Αν χάνεις πάνω από 1% του βάρους την εβδομάδα, η '
                    'Σήμερα θα σου το πει.'
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
          if (_doctor == true) ...[
            const SizedBox(height: 4),
            AppCard(
              padding: EdgeInsets.zero,
              child: NavRow(
                key: const ValueKey('wizard-doc-targets'),
                icon: Icons.flag_rounded,
                color: c.food,
                title: _targets.isEmpty ? 'Σου έγραψε αριθμούς-στόχους;' : 'Στόχοι του γιατρού',
                text: _targets.isEmpty ? 'Π.χ. LDL < 115. Προαιρετικά.' : _targets.text,
                onTap: () async {
                  final t = await askDoctorTargets(context, _targets);
                  if (t != null) setState(() => _targets = t);
                },
              ),
            ),
          ],
        ];
      case _Step.summary:
        final g = _calc!;
        // Ό,τι δείχνει η σύνοψη είναι ακριβώς ό,τι θα αποθηκευτεί ([_draft]).
        final d = _draft()!;
        final per = g.delta.abs().round();
        final te = d.kcalAdapt == null ? null : d.tdeeEst;
        final fromData = te != null;
        final burn = te != null ? thousands((te / 10).round() * 10) : thousands(g.tdee);
        final floor = d.male ? kcalFloorMale : kcalFloorFemale;
        final floored = te != null ? ((te + g.delta) / 10).round() * 10 < floor : g.floored;
        final sinceDay = DateTime.parse(d.since);
        final weekday = weekdayNames[sinceDay.weekday - 1];
        final continues = !sameDay(sinceDay, _now);
        final small = TextStyle(fontSize: 13.5, color: c.textSecondary, fontFeatures: tabular);
        return [
          // U3b-14: μόνο όσα αλλάζουν πραγματικά από τη σελίδα «Στόχοι».
          _q(context, 'Οι στόχοι σου', 'Θερμίδες, πρωτεΐνη και τους στόχους της χοληστερίνης τους αλλάζεις αργότερα από τη σελίδα «Στόχοι».'),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Θερμίδες τη μέρα', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.textSecondary)),
              const SizedBox(height: 4),
              BigValue(thousands(d.kcal), unit: 'kcal', size: 44),
              const SizedBox(height: 6),
              Text(
                _aim == GoalAim.keep
                    ? 'όσες καις, περίπου $burn'
                    : 'καις περίπου $burn · ${_aim == GoalAim.lose ? '−' : '+'}$per για ${rateKgText(d.kg, _rateValue)}',
                style: small,
              ),
              // S1-11: ο στόχος βγαίνει από την πρόσφατη εκτίμηση με τα δεδομένα σου, και η οθόνη το λέει.
              if (fromData)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Από τα δεδομένα σου, όχι από τον τύπο (ο τύπος θα έδινε ${thousands(g.kcal)} kcal).',
                      key: const ValueKey('wizard-from-data'), style: small),
                ),
              if (floored)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Ανέβηκε στο κάτω όριο ασφαλείας (${thousands(d.kcal)} kcal).',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.warn)),
                ),
              const Hairline(vertical: 12),
              InfoRow('Πρωτεΐνη', '${d.protein} g'),
              InfoRow('Λιπαρά', '${d.fatLo}–${d.fatHi} g'),
              InfoRow('Κορεσμένα λιπαρά', 'έως ${d.satMax} g · ${d.satPct}%'),
              InfoRow('Φυτικές ίνες', '${d.fiber} g ή περισσότερες'),
              InfoRow('Αλάτι', 'κάτω από ${dec(d.salt, 0)} g'),
              InfoRow('Υδατάνθρακες', 'ό,τι μένει · ~${d.carbsEst} g'),
              const Hairline(vertical: 12),
              // U3b-23: με τι υπολογίστηκαν, για να φανεί ένα λάθος βάρος πριν από την αποθήκευση.
              InfoRow('Υπολογίστηκαν με', '${dec(d.kg)} kg · ${activityText(d.activity).toLowerCase()}'),
            ]),
          ),
          const SizedBox(height: 12),
          // S1-5 / S11-6 / U3b-2: η πρώτη εκτίμηση βγαίνει την 28η μέρα (η πρώτη εβδομάδα δεν μετρά), όχι την 21η που
          // έγραφε εδώ· και διόρθωση προτείνεται μόνο όταν χρειάζεται.
          _Note(continues
              ? 'Ο έλεγχος θερμίδων συνεχίζει όπως πριν: κάθε $weekday η Σήμερα ελέγχει τον στόχο με τις ζυγίσεις και το '
                  'φαγητό σου και προτείνει διόρθωση μόνο αν χρειάζεται.'
              : 'Με ζυγίσεις τις μέρες σου (${_weighDays(p)}) και φαγητό σχεδόν κάθε μέρα, ${_onDay(firstEstimateDay(d))} θα '
                  'φανεί πόσες θερμίδες καις πραγματικά (η πρώτη εβδομάδα δεν μετρά). Από τότε, κάθε $weekday, η Σήμερα ελέγχει '
                  'τον στόχο και προτείνει διόρθωση μόνο αν χρειάζεται.'),
          const SizedBox(height: 8),
          const _Note('Αρχική εκτίμηση από τύπους, όχι ιατρική οδηγία. Ό,τι πει ο γιατρός σου υπερισχύει.'),
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
                          // Γεμάτο χρώμα με τα γράμματα των γεμάτων κουμπιών (U3b-18): πριν 3,7:1 πάνω στην επιλεγμένη κάρτα.
                          decoration: BoxDecoration(color: c.foodSolid, borderRadius: BorderRadius.circular(999)),
                          child: Text('Προτείνεται', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.onSolid)),
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

/// «άνδρας, 45 ετών, 180 cm»
String _who(bool male, int age, double heightCm) => '${male ? 'άνδρας' : 'γυναίκα'}, $age ετών, ${_cm(heightCm)} cm';

/// Έλεγχος 13/11 (S11-12). Οι στόχοι κρατούν το φύλο, την ηλικία και το ύψος με τα οποία υπολογίστηκαν. Αν τα διόρθωσες
/// μετά στο «Τα στοιχεία μου», η σελίδα «Στόχοι» το λέει ήρεμα και προσφέρει «Υπολόγισε ξανά»· τίποτα δεν αλλάζει μόνο του.
/// Επιστρέφει τους στόχους με τα τωρινά στοιχεία όταν διαφέρουν, αλλιώς null. Η ηλικία αλλάζει και μόνη της με τα
/// γενέθλια: «διαφέρει» μόνο όταν δεν ταιριάζει με καμία μέρα από την αρχή των στόχων ως σήμερα.
Goals? goalsWithCurrentProfile(Goals g, Profile p, DateTime today) {
  final since = DateTime.tryParse(g.since);
  final h = p.heightCm;
  if (since == null || h == null || (!p.male && !p.female)) return null;
  final atStart = p.ageOn(since), now = p.ageOn(today);
  if (atStart == null || now == null) return null;
  final lo = atStart < now ? atStart : now;
  final hi = atStart < now ? now : atStart;
  final ageDiffers = g.age < lo || g.age > hi;
  if (p.male == g.male && (h - g.heightCm).abs() < 0.05 && !ageDiffers) return null;
  final age = ageDiffers ? atStart : g.age;
  if (age < 18 || age > 110) return null;
  return g.withProfile(male: p.male, age: age, heightCm: h);
}

/// Σελίδα «Στόχοι» (σχέδια 12/11, 2α).
class GoalsPage extends StatelessWidget {
  const GoalsPage({super.key, required this.store, this.now});
  final HealthStore store;
  final DateTime? now;

  static Route<void> route(HealthStore store, {DateTime? now}) =>
      MaterialPageRoute<void>(settings: const RouteSettings(name: 'Στόχοι'), builder: (_) => GoalsPage(store: store, now: now));

  @override
  Widget build(BuildContext context) {
    // U3b-12: το ίδιο χρώμα διατροφής σε κουμπιά, πεδία και παράθυρα, όπως στις άλλες οθόνες φαγητού (πριν: πράσινο και μπλε).
    return FoodTheme(
        child: ListenableBuilder(
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
        // «Έχει βγει εκτίμηση»: υπάρχει έλεγχος με εκτίμηση από την αρχή ΑΥΤΩΝ των στόχων και μετά. Ως τότε η σελίδα γράφει
        // τη μέρα που θα βγει η εκτίμηση (28η μέρα· Συμβούλιο 2, Α2), όχι την 21η, που η κάρτα της Σήμερα λέει μόνο ότι
        // μαζεύει δεδομένα. Έλεγχος 13/11: (α) «εκτίμηση», όχι «έλεγχος» (U3b-3: «Πρώτος έλεγχος» έμενε και αφού είχαν ήδη
        // βγει και απαντηθεί κάρτες «Έλεγχος θερμίδων…»)· (β) ισχύει και μετά το «Ξανά ο οδηγός», όπου το παλιό ιστορικό
        // μένει αλλά ο μετρητής ξαναρχίζει (S1-11)· (γ) ένα βήμα «γρήγορης απώλειας» στο ιστορικό δεν είναι εκτίμηση.
        final estimated = g.log.any((l) => !l.fast && l.day.compareTo(g.since) >= 0);
        final hadEstimate = g.log.any((l) => !l.fast);
        final due = nextCheckDay(g, today);
        final firstEstimate = firstEstimateDay(g);
        final next = !estimated && due.isBefore(firstEstimate) ? firstEstimate : due;
        final nextText = sameDay(next, today) ? 'σήμερα' : longDate(next);
        final nextLabel = estimated ? 'Επόμενος έλεγχος' : (hadEstimate ? 'Επόμενη εκτίμηση' : 'Πρώτη εκτίμηση');
        final lastApplied = g.log.where((l) => l.applied).lastOrNull;
        final adaptCards = _adaptCards(context, g, today, next, estimated: estimated, nextLabel: nextLabel);
        final small = TextStyle(fontSize: 13.5, color: c.textSecondary);
        // U3b-14: ό,τι αλλάζει έχει ύψος αφής 48 και ένα μικρό μολύβι· οι γραμμές που δεν αλλάζουν μένουν σκέτες.
        Widget editRow(String key, String label, String value, VoidCallback onTap) => InkWell(
              key: ValueKey(key),
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(children: [
                  Expanded(child: InfoRow(label, value)),
                  const SizedBox(width: 6),
                  Icon(Icons.edit_rounded, size: 16, color: c.textTertiary),
                ]),
              ),
            );
        // S11-12: τα στοιχεία άλλαξαν μετά τους στόχους; (null: όχι)
        final fixed = goalsWithCurrentProfile(g, p, today);
        // Πίτουρο: «για 3 g β-γλυκάνες» γράφεται μόνο όταν τα γραμμάρια βγαίνουν από την ετικέτα και φτάνουν (U3b-19, S1-12).
        final beta = g.betaPer100;
        final branNeed = beta == null ? null : branGramsFor(beta);
        final branCovers = branNeed != null && g.branG >= branNeed;

        final top = <Widget>[
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              CardHeader(icon: Icons.restaurant_rounded, title: 'Θερμίδες τη μέρα', color: c.food, trailing: const InfoDot(goalsInfo)),
              const SizedBox(height: 8),
              InkWell(
                key: const ValueKey('goals-kcal'),
                onTap: () => _editKcal(context, g),
                child: Row(children: [
                  Flexible(child: BigValue(thousands(g.kcal), unit: 'kcal', size: 44)),
                  const SizedBox(width: 8),
                  Icon(Icons.edit_rounded, size: 18, color: c.textTertiary),
                ]),
              ),
              const SizedBox(height: 6),
              Text(
                [
                  aimText(g.aim),
                  if (g.aim != GoalAim.keep) '${rateWord(g.aim, g.rate)} · ${rateKgText(g.kg, g.rate)}',
                ].join(' · '),
                style: small,
              ),
              if (g.kcalSet != null)
                Text('Τον άλλαξες εσύ (ο υπολογισμός λέει ${thousands(calc.kcal)}).', style: small)
              // S1-6: μετά από «Εφάρμοσε» στη «γρήγορη απώλεια» η σελίδα έγραφε «Από τον τύπο» για τύπο + 150.
              else if (g.kcalAdapt != null && lastApplied != null && lastApplied.fast && lastApplied.after == g.kcalAdapt)
                Text(
                    'Ανέβηκε από ${thousands(lastApplied.before)} σε ${thousands(lastApplied.after)} (${_dm(lastApplied.day)}), '
                    'γιατί έχανες βάρος πολύ γρήγορα',
                    style: small)
              else if (g.kcalAdapt != null)
                Text('Από τα δεδομένα σου${lastApplied == null ? '' : ', ${_dm(lastApplied.day)}'}', style: small)
              else if (estimated)
                Text('Από τον τύπο· τα δεδομένα σου δεν ζήτησαν αλλαγή', style: small)
              else
                Text('Από τον τύπο, ως την πρώτη εκτίμηση από τα δεδομένα σου', style: small),
              Text('$nextLabel: $nextText', key: const ValueKey('goals-next-check'), style: small),
              const SizedBox(height: 12),
              OutlinedButton(
                key: const ValueKey('goals-how'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), foregroundColor: c.food),
                onPressed: () => showHowCalculated(context, g),
                child: const Text('Πώς υπολογίστηκε'),
              ),
            ]),
          ),
          if (fixed != null) ...[
            const SizedBox(height: 12),
            AppCard(
              key: const ValueKey('goals-profile-changed'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Τα στοιχεία σου άλλαξαν μετά τους στόχους', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
                const SizedBox(height: 4),
                Text(
                    'Οι στόχοι υπολογίστηκαν με: ${_who(g.male, g.age, g.heightCm)}. Στα στοιχεία σου τώρα: '
                    '${_who(fixed.male, fixed.age, fixed.heightCm)}. Οι αριθμοί δεν αλλάζουν μόνοι τους.',
                    style: TextStyle(fontSize: 13.5, height: 1.4, color: c.textSecondary)),
                const SizedBox(height: 10),
                OutlinedButton(
                  key: const ValueKey('goals-recompute'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), foregroundColor: c.food),
                  onPressed: () => store.setGoals(fixed),
                  child: const Text('Υπολόγισε ξανά'),
                ),
              ]),
            ),
          ],
          for (final card in adaptCards) ...[const SizedBox(height: 12), card],
        ];
        final mid = <Widget>[
          AppCard(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              editRow('goals-protein', 'Πρωτεΐνη', '${g.protein} g${g.proteinSet != null ? ' · δική σου' : ''}', () => _editProtein(context, g)),
              // U3a-9: ένας όρος παντού, όπως στις οθόνες φαγητού και στη διατροφική δήλωση («Λιπαρά», «Κορεσμένα λιπαρά»).
              InfoRow('Λιπαρά', '${g.fatLo}–${g.fatHi} g'),
              InfoRow('Κορεσμένα λιπαρά', 'έως ${g.satMax} g · ${g.satPct}%'),
              InfoRow('Φυτικές ίνες', '${g.fiber} g ή περισσότερες'),
              InfoRow('Αλάτι', 'κάτω από ${dec(g.salt, 0)} g'),
              const InfoRow('Υδατάνθρακες', 'ό,τι μένει'),
            ]),
          ),
          if (g.doctor) ...[
            // U3b-28: οι αριθμοί εδώ είναι το πλάνο σου (προεπιλογές που αλλάζεις), όχι αριθμοί που έγραψε ο γιατρός.
            const GroupLabel('Χοληστερίνη · το πλάνο σου'),
            AppCard(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                editRow('goals-nuts', 'Ξηροί καρποί', '${g.nutsG} g τη μέρα',
                    () => _editInt(context, 'Ξηροί καρποί τη μέρα', g.nutsG, 0, 100, 'g', (v) => g.copyWith(nutsG: v))),
                editRow(
                    'goals-bran',
                    branCovers ? 'Πίτουρο βρώμης για 3 g β-γλυκάνες' : 'Πίτουρο βρώμης',
                    branCovers
                        ? '${g.branG} g · από την ετικέτα'
                        // Round 2 (R2-U1-14): ποιο είναι το πλάνο και ότι δεν φτάνει τα 3 g (πριν «40 g · για 3 g …: 45 g»).
                        : (branNeed == null
                            ? '${g.branG} g · γράψε την ετικέτα'
                            : '${g.branG}\u00A0g τη μέρα · για 3\u00A0g β-γλυκάνες χρειάζονται $branNeed\u00A0g'),
                    () => _editBran(context, g)),
                editRow('goals-legumes', 'Όσπρια', '${countText(g.legumesWeek, 'φορά', 'φορές')} την εβδομάδα',
                    () => _editInt(context, 'Όσπρια την εβδομάδα', g.legumesWeek, 0, 7, 'φορές', (v) => g.copyWith(legumesWeek: v))),
                editRow('goals-fish', 'Ψάρι', '${countText(g.fishWeek, 'φορά', 'φορές')} την εβδομάδα',
                    () => _editInt(context, 'Ψάρι την εβδομάδα', g.fishWeek, 0, 7, 'φορές', (v) => g.copyWith(fishWeek: v))),
                editRow('goals-doc-targets', 'Στόχοι του γιατρού', g.docTargets.isEmpty ? 'κανένας · γράψε' : g.docTargets.text, () async {
                  final t = await askDoctorTargets(context, g.docTargets);
                  if (t != null) store.setGoals(g.copyWith(docTargets: t));
                }),
              ]),
            ),
            const SizedBox(height: 8),
            // S1-12: το ψάρι δεν είναι τρόφιμο που ρίχνει την LDL (η διατροφή «portfolio» του Jenkins 2003 ήταν φυτική)· και
            // ποια ψάρια (EFSA 2015: ξιφίας και τόνος έχουν τον περισσότερο υδράργυρο).
            // Round 2 (R2-U1-14): τρεις περιπτώσεις· με ετικέτα που δεν φτάνει, όχι «γράψε τις β-γλυκάνες» (τις έγραψε ήδη).
            Text(
              'Από το πλάνο σου. '
              '${branCovers ? 'Τα γραμμάρια του πίτουρου βγήκαν από τις β-γλυκάνες που γράφει η συσκευασία σου (EFSA: 3 g τη μέρα).' : branNeed != null ? 'Με τη συσκευασία σου, για 3\u00A0g β-γλυκάνες τη μέρα (EFSA) χρειάζονται $branNeed\u00A0g πίτουρο· το πλάνο σου έχει ${g.branG}\u00A0g. Για να τα φτάνεις, πάτησε τη γραμμή «Πίτουρο βρώμης».' : 'Για το πίτουρο, γράψε τις β-γλυκάνες που έχει η συσκευασία σου: βγαίνουν τα γραμμάρια για 3 g τη μέρα (EFSA).'} '
              'Το ψάρι μπαίνει γιατί παίρνει τη θέση του κρέατος και για τα τριγλυκερίδια· το ίδιο δεν ρίχνει την LDL. Κυρίως μικρά '
              'λιπαρά ψάρια (σαρδέλα, γαύρος, σκουμπρί)· ξιφίας και τόνος όχι συχνά, γιατί έχουν περισσότερο υδράργυρο (EFSA 2015).',
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
        ];
        final bottom = <Widget>[
          OutlinedButton(
            key: const ValueKey('goals-wizard'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => Navigator.of(context).push(GoalsWizard.route(store, now: now, fromPage: true)),
            child: const Text('Ξανά ο οδηγός'),
          ),
          const SizedBox(height: 4),
          TextButton(
            key: const ValueKey('goals-delete'),
            // Κόκκινο, όπως κάθε άλλο σβήσιμο της εφαρμογής (U3b-29).
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(46), foregroundColor: c.bad),
            onPressed: () => _delete(context),
            child: const Text('Σβήσε τους στόχους'),
          ),
        ];
        return Scaffold(
          appBar: AppBar(title: const Text('Στόχοι')),
          body: SafeArea(
            // U3b-30: σε φαρδιά οθόνη (ανοιχτό Fold) δύο στήλες, όπως η Διατροφή και η Σήμερα· ποτέ μία τεντωμένη.
            child: LayoutBuilder(builder: (context, box) {
              final wide = box.maxWidth >= 700;
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: wide ? 1080 : 640),
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                    if (wide)
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [...top, const SizedBox(height: 16), ...bottom]),
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: mid)),
                      ])
                    else ...[
                      ...top,
                      const SizedBox(height: 12),
                      ...mid,
                      const SizedBox(height: 16),
                      ...bottom,
                    ],
                  ]),
                ),
              );
            }),
          ),
        );
      },
    ));
  }

  /// Σβήσιμο των στόχων (αίτημα 12/11: ό,τι γράφεται σβήνεται). Φαγητό και ζυγίσεις μένουν.
  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Σβήσιμο στόχων;'),
        content: const Text('Σβήνονται οι στόχοι, οι στόχοι του γιατρού και το ιστορικό των ελέγχων θερμίδων. Το φαγητό και οι '
            'ζυγίσεις μένουν.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Άκυρο')),
          FilledButton(key: const ValueKey('goals-delete-ok'), onPressed: () => Navigator.pop(context, true), child: const Text('Σβήσε')),
        ],
      ),
    );
    if (ok == true) store.setGoals(null);
  }

  /// A4: «Πριν από την πρώτη εκτίμηση» (πρόοδος, όσο δεν έχει βγει εκτίμηση για αυτούς τους στόχους) και το ιστορικό
  /// «Πόσες kcal καις τη μέρα, από τα δεδομένα σου» (όταν υπάρχει). Έλεγχος 13/11: U3b-3, U3b-31, S1-6, S1-11.
  List<Widget> _adaptCards(BuildContext context, Goals g, DateTime today, DateTime next,
      {required bool estimated, required String nextLabel}) {
    final c = Aigaio.of(context);
    final small = TextStyle(fontSize: 13.5, height: 1.4, color: c.textSecondary);
    final title = TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text);
    final days = daysBetween(today, next);
    final when = days <= 0 ? 'σήμερα' : (days == 1 ? 'αύριο' : 'σε $days μέρες');
    final cards = <Widget>[];
    final food = FoodStore.shared;
    final d = store.data;
    if (!estimated && food != null && food.loaded && d != null) {
      final r = readiness(goals: g, today: today, weights: dailyWeights(d.body), intake: (a, b) => dailyIntake(food, a, b));
      cards.add(AppCard(
        key: const ValueKey('goals-adapt-ready'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(nextLabel == 'Πρώτη εκτίμηση' ? 'Πριν από την πρώτη εκτίμηση' : 'Πριν από την επόμενη εκτίμηση', style: title),
          const SizedBox(height: 2),
          Text('Τι έχει μαζευτεί ως χθες (η πρώτη εβδομάδα δεν μετρά):', style: small),
          InfoRow('Μέρες με φαγητό', '${r.intakeDays} από $adaptMinIntakeDays'),
          InfoRow('Ζυγίσεις', '${r.weighIns} από $adaptMinWeighIns'),
          InfoRow(nextLabel, when),
          const SizedBox(height: 4),
          Text(
              'Η πρώτη εβδομάδα δεν μετρά: τότε φεύγουν κυρίως νερά. Μετράνε μέρες με τουλάχιστον το 60% του στόχου γραμμένο· '
              'οι ζυγίσεις έρχονται μόνες τους από την InBody.',
              style: small),
        ]),
      ));
    }
    if (g.log.isNotEmpty) {
      cards.add(AppCard(
        key: const ValueKey('goals-adapt-log'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Πόσες kcal καις τη μέρα, από τα δεδομένα σου', style: title),
          const SizedBox(height: 4),
          // U3b-27: ο τύπος με τον ίδιο αριθμό που γράφει το «Πώς υπολογίστηκε».
          InfoRow('Τύπος (αρχή, ${_dm(g.since)})', '${thousands(g.calc.tdee)} kcal'),
          for (final l in g.log.reversed.take(6).toList().reversed) ...[
            // Ένα βήμα «γρήγορης απώλειας» δεν έχει εκτίμηση: γράφεται μόνο η αλλαγή του στόχου (S1-3 / S1-6).
            if (l.fast)
              InfoRow('Γρήγορη απώλεια ${_dm(l.day)}', 'στόχος ${thousands(l.before)} → ${thousands(l.after)}')
            else ...[
              InfoRow('Έλεγχος ${_dm(l.day)}', '${thousands((l.tdee / 10).round() * 10)} kcal'),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                    l.applied ? 'στόχος ${thousands(l.before)} → ${thousands(l.after)}' : 'ο στόχος έμεινε ${thousands(l.before)}',
                    style: small),
              ),
            ],
          ],
          if (estimated) InfoRow('Επόμενος έλεγχος', when),
        ]),
      ));
    }
    return cards;
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
      setState(() => _err = 'Από ${thousands(widget.min)} ως ${thousands(widget.max)} ${widget.unit}.');
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
          decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), suffixText: widget.unit, errorText: _err),
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

/// Οι στόχοι του γιατρού για τα λιπίδια (σε mg/dL, όπως στο χαρτί του). Κενό = δεν έδωσε.
Future<DoctorTargets?> askDoctorTargets(BuildContext context, DoctorTargets current) =>
    showDialog<DoctorTargets>(context: context, builder: (_) => _DoctorTargetsDialog(current: current));

class _DoctorTargetsDialog extends StatefulWidget {
  const _DoctorTargetsDialog({required this.current});
  final DoctorTargets current;

  @override
  State<_DoctorTargetsDialog> createState() => _DoctorTargetsDialogState();
}

class _DoctorTargetsDialogState extends State<_DoctorTargetsDialog> {
  late final _ldl = TextEditingController(text: widget.current.ldlMax?.toString() ?? '');
  late final _hdl = TextEditingController(text: widget.current.hdlMin?.toString() ?? '');
  late final _tg = TextEditingController(text: widget.current.tgMax?.toString() ?? '');
  final _err = <String, String?>{};

  @override
  void dispose() {
    _ldl.dispose();
    _hdl.dispose();
    _tg.dispose();
    super.dispose();
  }

  void _ok() {
    _err.clear();
    int? read(String key, TextEditingController t, (int, int) r) {
      final s = t.text.trim();
      if (s.isEmpty) return null;
      final v = int.tryParse(s);
      if (v == null || v < r.$1 || v > r.$2) _err[key] = 'Από ${r.$1} ως ${r.$2} mg/dL.';
      return v;
    }

    final ldl = read('ldl', _ldl, DoctorTargets.ldlRange);
    final hdl = read('hdl', _hdl, DoctorTargets.hdlRange);
    final tg = read('tg', _tg, DoctorTargets.tgRange);
    if (_err.isNotEmpty) {
      setState(() {});
      return;
    }
    Navigator.pop(context, DoctorTargets(ldlMax: ldl, hdlMin: hdl, tgMax: tg));
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    Widget field(String key, String label, TextEditingController t) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: TextField(
            key: ValueKey('doc-$key'),
            controller: t,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                labelText: label,
                suffixText: 'mg/dL',
                errorText: _err[key]),
            onSubmitted: (_) => _ok(),
          ),
        );
    return AlertDialog(
      title: const Text('Στόχοι του γιατρού'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Όπως τους έγραψε ο γιατρός. Άφησε κενό ό,τι δεν σου έδωσε.',
              style: TextStyle(fontSize: 14, height: 1.4, color: c.textSecondary)),
          field('ldl', 'LDL κάτω από', _ldl),
          field('hdl', 'HDL πάνω από', _hdl),
          field('tg', 'Τριγλυκερίδια κάτω από', _tg),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Άκυρο')),
        FilledButton(key: const ValueKey('doc-ok'), onPressed: _ok, child: const Text('Εντάξει')),
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
          decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), labelText: 'β-γλυκάνες ανά 100 g', suffixText: 'g'),
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
          decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), labelText: 'Πίτουρο τη μέρα', suffixText: 'g'),
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
          // U3b-24: με λέξεις, για να φαίνεται τι είναι κάθε αριθμός.
          Text('Τύπος Mifflin-St Jeor: 10 × βάρος ${dec(g.kg)} + 6,25 × ύψος ${_cm(g.heightCm)} − 5 × ηλικία ${g.age} $sex', style: small),
          const SizedBox(height: 6),
          InfoRow('2 · Με την κίνησή σου (× ${dec(g.activity)})', '${n(calc.tdee)} kcal'),
          Text('«${activityText(g.activity)}». Είναι εκτίμηση: σε κάθε άνθρωπο πέφτει ως και 10–15% έξω.', style: small),
          if (g.aim != GoalAim.keep) ...[
            const SizedBox(height: 6),
            InfoRow('3 · Για ${rateKgText(g.kg, g.rate)}', '${calc.delta < 0 ? '−' : '+'}${n(calc.delta.abs())} kcal'),
            // S1-8: με το ποσοστό και το βάρος, ώστε ο αριθμός να ξαναβγαίνει ακριβώς (0,75% × 82,0 × 7.700 ÷ 7 = 677·
            // πριν «0,61 kg × 7.700 ÷ 7», που δίνει 671).
            Text('${ratePctText(g.rate)} του βάρους: ${ratePctText(g.rate)} × ${dec(g.kg)} kg × 7.700 kcal ÷ 7 μέρες', style: small),
          ],
          const Hairline(vertical: 12),
          // U3b-24: όταν ισχύει άλλος στόχος (δικός σου ή από τα δεδομένα), αυτή η γραμμή είναι «από τον τύπο».
          InfoRow(g.kcalSet != null || g.kcalAdapt != null ? 'Στόχος από τον τύπο' : 'Στόχος', '${thousands(calc.kcal)} kcal'),
          if (calc.floored) Text('Ανέβηκε στο κάτω όριο ασφαλείας.', style: small),
          if (g.kcalSet != null) Text('Ισχύει ο δικός σου: ${thousands(g.kcalSet!)} kcal.', style: small),
          if (g.kcalSet == null && g.kcalAdapt != null)
            Text('Ισχύει ο στόχος από τα δεδομένα σου: ${thousands(g.kcalAdapt!)} kcal.', style: small),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.tint(c.food), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Μετά από 4 εβδομάδες, από τα δικά σου δεδομένα', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
              const SizedBox(height: 4),
              Text(
                'Συγκρίνοντας τι έφαγες με το πώς άλλαξε το βάρος σου, φαίνεται πόσες θερμίδες καις πραγματικά. Η πρώτη '
                'εβδομάδα δεν μετρά, γιατί τότε φεύγουν κυρίως νερά. Κάθε εβδομάδα η Σήμερα ελέγχει τον στόχο και προτείνει '
                'διόρθωση μόνο όταν η διαφορά ξεπερνά το φυσιολογικό εύρος των ζυγίσεων, το πολύ 150 kcal τη φορά· αλλάζει '
                'μόνο αν πατήσεις «Εφάρμοσε».',
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
