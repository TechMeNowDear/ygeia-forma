import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data.dart' show HealthStore;
import '../../format.dart' show daysBetween;
import '../../reference.dart' show MetricInfo;
import '../../theme.dart';
import '../../training/session.dart';
import '../../training/training_store.dart';
import '../../training/zone.dart';
import '../../widgets.dart';
import '../info_sheet.dart';
import '../me_page.dart';

/// Εξήγηση της ζώνης (σχέδια 12/11, «i»).
const zoneInfo = MetricInfo(
  title: 'Ζώνη περπατήματος',
  what: 'Οι παλμοί της μέτριας έντασης: 40–59% του «αποθέματος παλμών», δηλαδή της διαφοράς ανάμεσα στους μέγιστους παλμούς '
      'και στους παλμούς ηρεμίας (τύπος Karvonen). Στο πάνω όριο μιλάς με προτάσεις αλλά δεν μπορείς να τραγουδήσεις.',
  shows: 'Πόσο κουράζεται η καρδιά σου στο περπάτημα. Η μέτρια ένταση είναι αυτή που προτείνουν οι οδηγίες για 150–300 λεπτά την '
      'εβδομάδα (Π.Ο.Υ. 2020), μαζί με βάρη 2 ή περισσότερες μέρες.',
  up: 'Πάνω από τη ζώνη: πιο έντονη άσκηση. Δεν είναι κακό, απλώς κουράζει περισσότερο. Το ρολόι δονείται για να το ξέρεις.',
  down: 'Κάτω από τη ζώνη: ελαφριά κίνηση. Μετρά κι αυτή, αλλά όχι στα λεπτά μέτριας άσκησης.',
  compare: 'Η «ζώνη καύσης λίπους» υπάρχει (εκεί καις περισσότερο λίπος ανά λεπτό), αλλά δεν αλλάζει πόσο λίπος χάνεις: μετρά '
      'πόση άσκηση κάνεις συνολικά και τι τρως. Για τη χοληστερίνη και την HDL μετρά επίσης η συνολική ποσότητα άσκησης.',
  // round1, S6-4: το ±10 είναι μία τυπική απόκλιση (Tanaka 2001: SD ~10 παλμοί), δηλαδή περίπου 1 στους 3 ανθρώπους
  // απέχει περισσότερο και περίπου 1 στους 20 πάνω από 20. Ο τύπος βγήκε από υγιείς, χωρίς κάπνισμα και φάρμακα· το
  // κάπνισμα αλλάζει τους παλμούς ηρεμίας και τους μέγιστους (Papathanasiou 2013). Γενικό κείμενο, για κάθε χρήστη.
  accuracy: 'Οι μέγιστοι παλμοί βγαίνουν από την ηλικία (208 − 0,7 × ηλικία). Είναι εκτίμηση: σε 1 στους 3 ανθρώπους οι '
      'πραγματικοί διαφέρουν πάνω από 10 παλμούς, και σε περίπου 1 στους 20 πάνω από 20. Ο τύπος βγήκε από υγιείς ανθρώπους '
      'που δεν κάπνιζαν και δεν έπαιρναν φάρμακα· το κάπνισμα και φάρμακα που αλλάζουν τους παλμούς (π.χ. β-αναστολείς) '
      'μετακινούν τη ζώνη. Γι’ αυτό, τα πρώτα περπατήματα έλεγξε τη ζώνη με το «τεστ ομιλίας»: στο πάνω όριο μιλάς με '
      'προτάσεις αλλά δεν τραγουδάς. Οι παλμοί ηρεμίας είναι η μεσαία τιμή των παλμών ύπνου των 14 τελευταίων νυχτών. '
      'Οι παλμοί καρπού στο περπάτημα είναι αρκετά ακριβείς.',
  cite: 'ACSM Guidelines (μέτρια ένταση 40–59%) · Tanaka 2001 · Papathanasiou 2013 (κάπνισμα) · Π.Ο.Υ. 2020 · '
      'Achten & Jeukendrup 2002 · Venables 2005 · Kraus 2002 (NEJM) · Kodama 2007 · Persinger 2004 (τεστ ομιλίας)',
);

/// Με όριο γιατρού το ρολόι δονείται μόνο σε εκείνο (round1, U5-28· ExerciseService.zoneMaySpeak).
String zoneLimitText(int limit) => 'Έχεις όριο γιατρού ($limit): το ρολόι δονείται μόνο σε εκείνο. Οι δονήσεις της ζώνης είναι κλειστές.';

/// Οι δονήσεις της ζώνης σε λέξεις (round1, U5-06), από τις ίδιες σταθερές με το ρολόι.
const zoneHighText = 'Δύο σύντομες δονήσεις όταν μείνεις πάνω $zoneHoldSec δευτερόλεπτα. Ξανά μετά από ${zoneRepeatSec ~/ 60} λεπτά, '
    'αν δεν κατέβεις. Όχι τα πρώτα ${zoneWarmupSec ~/ 60} λεπτά.';
const zoneLowText = 'Μία δόνηση όταν μείνεις κάτω 1 λεπτό. Ξανά μετά από 5 λεπτά.';

/// «Τεστ ομιλίας» (round1, S6-3): η απάντηση λέει κάτι για το πάνω όριο μόνο αν οι παλμοί πέρασαν αρκετή ώρα κοντά του
/// (Persinger 2004: το τεστ κρίνει την ένταση στην οποία δίνεται η απάντηση). «Κοντά» = από [talkNearBelow] κάτω ως
/// [talkNearAbove] πάνω από το όριο, για τουλάχιστον [talkNearMinSec] (οι παλμοί σταθεροποιούνται σε 2–3 λεπτά σταθερής
/// έντασης). Και η ζώνη απομακρύνεται το πολύ [talkMaxDrift] από τον υπολογισμό, όσες απαντήσεις κι αν δοθούν: περίπου
/// όσο μετακινεί τη ζώνη (59% του αποθέματος) ένα λάθος δύο τυπικών αποκλίσεων στους μέγιστους (Tanaka 2001, SD ~10).
const talkNearBelow = 7, talkNearAbove = 5, talkNearMinSec = 180, talkMaxDrift = 10;

/// Δευτερόλεπτα ενεργού χρόνου κοντά στο πάνω όριο [hi] και πάνω από αυτό το «κοντά». Χωρίς παλμούς: 0 και 0.
({int near, int above}) talkSeconds(Session s, int hi) {
  if (s.hr.isEmpty) return (near: 0, above: 0);
  final t = zoneTimes(s.hr, s.pauses, hi - talkNearBelow, hi + talkNearAbove, endSec: s.end?.difference(s.start).inSeconds);
  return (near: t.inZone, above: t.above);
}

/// Η ζώνη που προτείνεται μετά την απάντηση [answer] για ένα περπάτημα με ζώνη [walkLo]–[walkHi], ή null (καμία πρόταση).
/// [baseLo]/[baseHi]: η ζώνη του υπολογισμού (χωρίς αλλαγές του χρήστη)· χωρίς αυτήν, η ζώνη του περπατήματος.
(int, int)? talkProposal(
    {required String answer, required int walkLo, required int walkHi, int? baseLo, int? baseHi, required int nearSec, required int aboveSec}) {
  final shift = talkShift(answer);
  if (shift == 0 || nearSec < talkNearMinSec) return null;
  // «Λαχάνιαζα» σε περπάτημα που ήταν κυρίως πάνω από τη ζώνη: αυτό ακριβώς περιμένει μια σωστή ζώνη.
  if (shift < 0 && aboveSec > nearSec) return null;
  final bLo = baseLo ?? walkLo, bHi = baseHi ?? walkHi;
  final up = math.min(bLo + talkMaxDrift - walkLo, bHi + talkMaxDrift - walkHi);
  final down = math.max(bLo - talkMaxDrift - walkLo, bHi - talkMaxDrift - walkHi);
  if (up < down) return null;
  final d = math.max(down, math.min(up, shift));
  if (d == 0) return null;
  return (walkLo + d, walkHi + d);
}

/// Η κάρτα της ζώνης στην Προπόνηση (σχέδια 12/11, 4α).
class ZoneCard extends StatelessWidget {
  const ZoneCard({super.key, required this.health, required this.training, required this.now});
  final HealthStore health;
  final TrainingStore training;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([health, training]),
      builder: (context, _) {
        final z = health.zoneOn(now);
        final s = health.zoneSettings;
        if (z == null) {
          return EmptyCard(
            key: const ValueKey('zone-need-age'),
            icon: Icons.directions_walk_rounded,
            color: c.exercise,
            title: 'Ζώνη περπατήματος',
            text: 'Για να βρω τη ζώνη σου χρειάζομαι την ηλικία σου.',
            buttonText: 'Τα στοιχεία μου',
            onPressed: () => Navigator.of(context).push(MePage.route(health)),
          );
        }
        final span = z.max - (z.rest ?? 0);
        double at(int v) => span <= 0 ? 0 : ((v - (z.rest ?? 0)) / span).clamp(0.0, 1.0);
        return AppCard(
          key: const ValueKey('zone-card'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CardHeader(
              icon: Icons.directions_walk_rounded,
              title: 'Ζώνη περπατήματος',
              color: c.exercise,
              trailing: const InfoDot(zoneInfo),
            ),
            const SizedBox(height: 6),
            BigValue('${z.lo}–${z.hi}', unit: 'παλμοί', size: 34),
            const SizedBox(height: 4),
            Text('Μέτρια ένταση: μιλάς με προτάσεις, δεν τραγουδάς.', style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
            if (z.rest != null && z.max > 0) ...[
              const SizedBox(height: 14),
              _ZoneBar(lo: at(z.lo), hi: at(z.hi), color: c.exercise),
              const SizedBox(height: 6),
              Row(children: [
                Text('${z.rest} ηρεμία', style: TextStyle(fontSize: 12.5, color: c.textSecondary, fontFeatures: tabular)),
                const Spacer(),
                Text('${z.max} μέγιστοι', style: TextStyle(fontSize: 12.5, color: c.textSecondary, fontFeatures: tabular)),
              ]),
            ] else if (!z.manual) ...[
              const SizedBox(height: 8),
              Text('Προσωρινά από την ηλικία (64–76% των μέγιστων)· με 7 νύχτες παλμών ύπνου γίνεται πιο προσωπική.',
                  style: TextStyle(fontSize: 13, height: 1.4, color: c.textSecondary)),
            ],
            if (z.manual) ...[
              const SizedBox(height: 8),
              Text('Τη ζώνη την όρισες εσύ.', style: TextStyle(fontSize: 13, color: c.textSecondary)),
            ],
            // round1, U5-28: με όριο γιατρού το ρολόι δεν δονείται για τη ζώνη (ExerciseService: zoneMaySpeak)· ο διακόπτης
            // δεν δείχνει «ανοιχτό» κάτι που δεν γίνεται.
            if (training.hrLimit != null) ...[
              const SizedBox(height: 8),
              Text(zoneLimitText(training.hrLimit!),
                  key: const ValueKey('zone-doctor-limit'), style: TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w600, color: c.warn)),
            ],
            const Hairline(vertical: 12),
            Row(children: [
              Expanded(child: Text('Δόνηση όταν την ξεπερνάς', style: TextStyle(fontSize: 15, color: training.hrLimit == null ? c.text : c.textSecondary))),
              Switch(
                key: const ValueKey('zone-alert-high'),
                value: s.alertHigh && training.hrLimit == null,
                onChanged: training.hrLimit != null ? null : (v) => health.setZoneSettings(s.copyWith(alertHigh: v)),
              ),
            ]),
            const SizedBox(height: 4),
            OutlinedButton(
              key: const ValueKey('zone-edit'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), foregroundColor: c.exercise),
              onPressed: () => openZoneSheet(context, health, now, limit: training.hrLimit),
              child: const Text('Αλλαγή'),
            ),
          ]),
        );
      },
    );
  }
}

class _ZoneBar extends StatelessWidget {
  const _ZoneBar({required this.lo, required this.hi, required this.color});
  final double lo, hi;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return LayoutBuilder(builder: (context, k) {
      final w = k.maxWidth;
      return SizedBox(
        height: 14,
        child: Stack(children: [
          Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(color: c.hairline, borderRadius: BorderRadius.circular(7)))),
          Positioned(
            left: w * lo,
            width: (w * (hi - lo)).clamp(4.0, w),
            top: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(7),
              ),
            ),
          ),
        ]),
      );
    });
  }
}

Future<void> openZoneSheet(BuildContext context, HealthStore health, DateTime now, {int? limit}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      routeSettings: const RouteSettings(name: 'Ζώνη περπατήματος'),
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => ZoneSheet(health: health, now: now, limit: limit),
    );

/// Φύλλο «Ζώνη περπατήματος» (σχέδια 12/11, 4β): πώς υπολογίστηκε, αλλαγή, δονήσεις.
class ZoneSheet extends StatefulWidget {
  const ZoneSheet({super.key, required this.health, required this.now, this.limit});
  final HealthStore health;
  final DateTime now;

  /// Το όριο γιατρού, αν υπάρχει: τότε οι δονήσεις της ζώνης είναι κλειστές στο ρολόι (U5-28).
  final int? limit;

  @override
  State<ZoneSheet> createState() => _ZoneSheetState();
}

class _ZoneSheetState extends State<ZoneSheet> {
  late ZoneSettings _s = widget.health.zoneSettings;
  late final Zone? _z0 = widget.health.zoneOn(widget.now);
  late final _lo = TextEditingController(text: '${_z0?.lo ?? ''}');
  late final _hi = TextEditingController(text: '${_z0?.hi ?? ''}');
  late final _max = TextEditingController(text: _s.maxHr == null ? '' : '${_s.maxHr}');
  late final _rest = TextEditingController(text: _s.restHr == null ? '' : '${_s.restHr}');
  String? _error;

  @override
  void dispose() {
    _lo.dispose();
    _hi.dispose();
    _max.dispose();
    _rest.dispose();
    super.dispose();
  }

  int? _int(TextEditingController c) => int.tryParse(c.text.trim());

  void _save() {
    final lo = _int(_lo), hi = _int(_hi), max = _max.text.trim().isEmpty ? null : _int(_max);
    if (_max.text.trim().isNotEmpty && (max == null || max < 120 || max > 230)) {
      setState(() => _error = 'Οι μέγιστοι παλμοί θέλουν αριθμό από 120 ως 230.');
      return;
    }
    final rest = _rest.text.trim().isEmpty ? null : _int(_rest);
    if (_rest.text.trim().isNotEmpty && (rest == null || rest < zoneRestMin || rest > zoneRestMax)) {
      setState(() => _error = 'Οι παλμοί ηρεμίας θέλουν αριθμό από $zoneRestMin ως $zoneRestMax.');
      return;
    }
    if (lo == null || hi == null || lo < 60 || hi > 220 || lo >= hi) {
      setState(() => _error = 'Η ζώνη θέλει δύο αριθμούς, από 60 ως 220, με το κάτω μικρότερο από το πάνω.');
      return;
    }
    var s = _s.copyWith(maxHr: max, clearMax: max == null, restHr: rest, clearRest: rest == null);
    // Αν η ζώνη είναι όπως θα την υπολόγιζε η εφαρμογή με αυτούς τους μέγιστους, μένει «υπολογισμένη» (ακολουθεί τους
    // παλμούς ύπνου)· αλλιώς την όρισες εσύ.
    final calc = computeZone(age: widget.health.profile.ageOn(widget.now), restHr: widget.health.restHrForZone(widget.now), s: s.copyWith(clearManual: true));
    // Ανασκόπηση 11/11 (S1): κάτω/πάνω όπως ήταν (π.χ. άλλαξες μόνο τους μέγιστους) σε υπολογισμένη ζώνη = μένει
    // υπολογισμένη, με τους νέους μέγιστους· όχι «την όρισες εσύ» με τα παλιά νούμερα.
    final z0 = _z0;
    final untouched = z0 != null && lo == z0.lo && hi == z0.hi && !_s.manual;
    s = untouched || (calc != null && calc.lo == lo && calc.hi == hi) ? s.copyWith(clearManual: true) : s.copyWith(lo: lo, hi: hi);
    widget.health.setZoneSettings(s);
    Navigator.of(context).pop();
  }

  void _reset() {
    widget.health.setZoneSettings(_s.copyWith(clearManual: true, clearMax: true, clearRest: true));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final z = _z0;
    final hint = TextStyle(fontSize: 13, height: 1.4, color: c.textSecondary);
    final head = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: .6, color: c.textSecondary);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Ζώνη περπατήματος', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.text)),
          const SizedBox(height: 8),
          if (z != null) ...[
            InfoRow(
                'Παλμοί ηρεμίας',
                z.rest == null
                    ? '— · λίγες νύχτες ακόμα'
                    : z.restMeasured
                        ? '${z.rest} · δική σου μέτρηση, ξύπνιος'
                        : '${z.rest} · παλμοί ύπνου, 14 νύχτες'),
            InfoRow('Μέγιστοι παλμοί', z.max <= 0 ? '—' : '${z.max} · ${z.maxMeasured ? 'από τεστ' : 'εκτίμηση από την ηλικία'}'),
            InfoRow('Μέτρια ένταση', z.rest == null ? '64–76% των μέγιστων' : '40–59%'),
            InfoRow('Ζώνη', '${z.lo}–${z.hi}${z.manual ? ' · δική σου' : ''}'),
            const SizedBox(height: 4),
            Text(
                z.rest == null
                    ? 'Χωρίς αρκετές νύχτες παλμών ύπνου η ζώνη βγαίνει από τους μέγιστους παλμούς.'
                    : 'Ηρεμία + 40% και + 59% της διαφοράς «μέγιστοι − ηρεμία» (τύπος Karvonen).',
                style: hint),
          ],
          const SizedBox(height: 18),
          Text('ΑΛΛΑΓΗ', style: head),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                key: const ValueKey('zone-lo'),
                controller: _lo,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Κάτω', suffixText: 'παλμοί', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const ValueKey('zone-hi'),
                controller: _hi,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Πάνω', suffixText: 'παλμοί', border: OutlineInputBorder()),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('zone-max'),
            controller: _max,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Μέγιστοι παλμοί, αν τους ξέρεις', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 6),
          Text('Μόνο από τεστ ως την εξάντληση. Αν σταμάτησες νωρίτερα (π.χ. από κούραση), δεν είναι οι μέγιστοι.', style: hint),
          const SizedBox(height: 12),
          // 13/11: προαιρετικά, οι παλμοί ηρεμίας ξύπνιος, όπως τους ορίζει ο τύπος του Karvonen.
          TextField(
            key: const ValueKey('zone-rest'),
            controller: _rest,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Παλμοί ηρεμίας ξύπνιος, αν τους μέτρησες', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 6),
          Text('Καθιστός, μετά από 5 λεπτά ηρεμίας, το πρωί. Χωρίς τιμή μετρούν οι παλμοί ύπνου, που είναι λίγο χαμηλότεροι.', style: hint),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.bad)),
          ],
          const SizedBox(height: 18),
          Text('ΔΟΝΗΣΗ ΣΤΟ ΡΟΛΟΪ', style: head),
          if (widget.limit != null) ...[
            const SizedBox(height: 6),
            Text(zoneLimitText(widget.limit!), style: TextStyle(fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w600, color: c.warn)),
          ],
          // round1, U5-06: διάρκειες σε λέξεις· οι χρόνοι από τις σταθερές του zone.dart (ίδιοι με το ρολόι, S12-16).
          SwitchListTile(
            key: const ValueKey('zone-sheet-high'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Πάνω από τη ζώνη'),
            subtitle: Text(zoneHighText),
            value: _s.alertHigh && widget.limit == null,
            onChanged: widget.limit != null ? null : (v) => setState(() => _s = _s.copyWith(alertHigh: v)),
          ),
          SwitchListTile(
            key: const ValueKey('zone-sheet-low'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Κάτω από τη ζώνη'),
            subtitle: const Text(zoneLowText),
            value: _s.alertLow && widget.limit == null,
            onChanged: widget.limit != null ? null : (v) => setState(() => _s = _s.copyWith(alertLow: v)),
          ),
          // Ό,τι δείχνει και το ρολόι (f7, S8-02): σε Σίγαση ή Εξοικονόμηση ενέργειας η δόνηση της ζώνης δεν φτάνει.
          Text('Σε Σίγαση ή Εξοικονόμηση ενέργειας το ρολόι δεν δονείται για τη ζώνη· η οθόνη του γράφει «χωρίς δόνηση».',
              style: hint),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('zone-save'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: c.exerciseSolid, foregroundColor: c.onSolid),
            onPressed: _save,
            child: const Text('Αποθήκευση'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const ValueKey('zone-reset'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _reset,
            child: const Text('Επαναφορά στον υπολογισμό'),
          ),
        ]),
      ),
    );
  }
}

/// «Αυτή η εβδομάδα»: λεπτά μέτριας άσκησης (περπάτημα στη ζώνη ή πιο πάνω) και μέρες με βάρη (σχέδια 12/11, 4α).
class WeekMovementCard extends StatelessWidget {
  const WeekMovementCard({super.key, required this.training, required this.now});
  final TrainingStore training;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final w = weekMovement(training.sessions, now);
    final pct = (w.moderateMin / 150).clamp(0.0, 1.0);
    return AppCard(
      key: const ValueKey('week-movement'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Αυτή η εβδομάδα', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.textSecondary)),
        const SizedBox(height: 8),
        BigValue('${w.moderateMin}', unit: 'από 150 λεπτά', size: 34),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: pct, minHeight: 8, color: c.exercise, backgroundColor: c.hairline),
        ),
        const SizedBox(height: 8),
        Text(
          'Μέτρια άσκηση: περπάτημα στη ζώνη ή πιο πάνω. Π.Ο.Υ.: 150–300 λεπτά την εβδομάδα, συν βάρη 2 ή περισσότερες μέρες.',
          style: TextStyle(fontSize: 13, height: 1.4, color: c.textSecondary),
        ),
        const SizedBox(height: 4),
        // round1, U5-18: το «✓» ως γράμμα δεν υπάρχει στη γραμματοσειρά της εφαρμογής· εικονίδιο.
        Row(key: const ValueKey('week-strength'), children: [
          Text('Βάρη: ${w.strengthDays == 1 ? '1 μέρα' : '${w.strengthDays} μέρες'}',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.text)),
          if (w.strengthDays >= 2) ...[const SizedBox(width: 4), Icon(Icons.check_rounded, size: 16, color: c.good)],
        ]),
        if (w.unmeasuredWalks > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                w.unmeasuredWalks == 1
                    ? '1 περπάτημα χωρίς παλμούς ή ζώνη δεν μετρά εδώ.'
                    : '${w.unmeasuredWalks} περπατήματα χωρίς παλμούς ή ζώνη δεν μετρούν εδώ.',
                style: TextStyle(fontSize: 12.5, color: c.textTertiary)),
          ),
      ]),
    );
  }
}

/// «Χρόνος στη ζώνη» στη σύνοψη ενός περπατήματος (σχέδια 12/11, 4ε).
class ZoneTimeCard extends StatelessWidget {
  const ZoneTimeCard({super.key, required this.session});
  final Session session;

  static bool shows(Session s) => s.isCardio && s.zoneLo != null && s.zoneHi != null && (s.zoneTimes != null || s.hr.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final s = session;
    final t = s.zoneTimes ??
        () {
          final z = zoneTimes(s.hr, s.pauses, s.zoneLo!, s.zoneHi!, endSec: s.end?.difference(s.start).inSeconds);
          return [z.below, z.inZone, z.above];
        }();
    final total = t[0] + t[1] + t[2];
    int min(int sec) => (sec / 60).round();
    String mins(int sec) => min(sec) == 1 ? '1 λεπτό' : '${min(sec)} λεπτά';
    Widget col(String label, int sec) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
            Text(mins(sec), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text, fontFeatures: tabular)),
          ]),
        );
    return AppCard(
      key: const ValueKey('zone-time'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardHeader(icon: Icons.favorite_rounded, title: 'Χρόνος στη ζώνη ${s.zoneLo}–${s.zoneHi}', color: c.exercise),
        const SizedBox(height: 8),
        BigValue('${min(t[1])}', unit: 'από ${min(total)} λεπτά', size: 34),
        const SizedBox(height: 12),
        if (total > 0)
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(children: [
                if (t[0] > 0) Expanded(flex: t[0], child: ColoredBox(color: c.hairline)),
                if (t[1] > 0) Expanded(flex: t[1], child: ColoredBox(color: c.exercise)),
                if (t[2] > 0) Expanded(flex: t[2], child: ColoredBox(color: c.warn)),
              ]),
            ),
          ),
        const SizedBox(height: 10),
        Row(children: [col('Κάτω', t[0]), col('Στη ζώνη', t[1]), col('Πάνω', t[2])]),
        const SizedBox(height: 8),
        Text('Μετρά ο χρόνος με παλμούς από το ρολόι, χωρίς τις παύσεις. Τα πρώτα 5 λεπτά (ζέσταμα) φαίνονται, αλλά δεν δονούν.',
            style: TextStyle(fontSize: 12.5, height: 1.4, color: c.textSecondary)),
      ]),
    );
  }
}

/// «Τεστ ομιλίας» στα πρώτα περπατήματα (σχέδια 12/11, 4ε): η απάντηση φέρνει πρόταση, ποτέ αλλαγή χωρίς «Ναι».
class TalkTestCard extends StatefulWidget {
  const TalkTestCard({super.key, required this.session, required this.health});
  final Session session;
  final HealthStore health;

  static bool shows(Session s, HealthStore? h) {
    if (h == null || !s.isCardio || s.zoneLo == null || s.zoneHi == null) return false;
    if (s.activity != null && s.activity != 'walk') return false;
    final talk = h.zoneSettings.talk;
    if (talk.any((t) => t[0] == s.id)) return true; // έχει απαντηθεί: φαίνεται η απάντηση
    // Μόνο για πρόσφατα περπατήματα (ανασκόπηση 11/11, N5): όχι για ένα παλιό που άνοιξες τυχαία.
    if (daysBetween(s.start, DateTime.now()) > 14) return false;
    // round1, S6-3: χρειάζονται οι παλμοί του περπατήματος (φορτώνονται για τη σύνοψη) για να ξέρουμε αν έφτασε κοντά στο
    // πάνω όριο. Χωρίς παλμούς καμία ερώτηση.
    if (!s.hrLoaded || s.hr.isEmpty) return false;
    return talk.length < talkAskWalks;
  }

  @override
  State<TalkTestCard> createState() => _TalkTestCardState();
}

class _TalkTestCardState extends State<TalkTestCard> {
  Future<void> _answer(String a) async {
    final h = widget.health;
    final s = h.zoneSettings;
    String? before;
    for (final t in s.talk) {
      if (t[0] == widget.session.id) before = t[1];
    }
    final talk = [for (final t in s.talk) if (t[0] != widget.session.id) t, [widget.session.id, a]];
    h.setZoneSettings(s.copyWith(talk: talk));
    final shift = talkShift(a);
    final now = DateTime.now();
    final z = h.zoneOn(now);
    // Ανασκόπηση 11/11 (S2): η πρόταση βγαίνει από τη ζώνη ΑΥΤΟΥ του περπατήματος, όχι από την τωρινή, ώστε δεύτερο
    // πάτημα να μη μετακινεί τη ζώνη ξανά. Ίδια απάντηση ή ζώνη ήδη εκεί: καμία ερώτηση.
    final wLo = widget.session.zoneLo, wHi = widget.session.zoneHi;
    if (shift == 0 || before == a || z == null || wLo == null || wHi == null || !mounted) return;
    // round1, S6-3: μόνο αν οι παλμοί έμειναν κοντά στο πάνω όριο, και το πολύ ±10 από τη ζώνη του υπολογισμού.
    final secs = talkSeconds(widget.session, wHi);
    final base = computeZone(age: h.profile.ageOn(now), restHr: h.restHrForZone(now), s: s.copyWith(clearManual: true));
    final next = talkProposal(
        answer: a, walkLo: wLo, walkHi: wHi, baseLo: base?.lo, baseHi: base?.hi, nearSec: secs.near, aboveSec: secs.above);
    if (next == null) return;
    final (lo, hi) = next;
    if (z.lo == lo && z.hi == hi) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Να γίνει η ζώνη $lo–$hi;'),
        content: Text(shift > 0
            ? 'Αφού κοντά στους $wHi παλμούς μπορούσες και να τραγουδήσεις, η ζώνη σου μάλλον είναι λίγο πιο πάνω.'
            : 'Αφού κοντά στους $wHi παλμούς λαχάνιαζες, η ζώνη σου μάλλον είναι λίγο πιο κάτω.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Όχι')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ναι')),
        ],
      ),
    );
    if (ok == true) h.setZoneSettings(h.zoneSettings.copyWith(lo: lo, hi: hi));
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final s = widget.health.zoneSettings;
    String? answered;
    for (final t in s.talk) {
      if (t[0] == widget.session.id) answered = t[1];
    }
    const options = [
      ('sing', 'Ναι, και θα μπορούσα να τραγουδήσω'),
      ('talk', 'Ναι, με προτάσεις'),
      ('no', 'Όχι, λαχάνιαζα'),
    ];
    final hi = widget.session.zoneHi!;
    // round1, S6-3: χωρίς αρκετή ώρα κοντά στο πάνω όριο η ερώτηση δεν έχει νόημα· μόνο μία ήρεμη γραμμή.
    if (answered == null && talkSeconds(widget.session, hi).near < talkNearMinSec) {
      return AppCard(
        key: const ValueKey('talk-test-not-near'),
        child: Text('Τεστ ομιλίας: σε αυτό το περπάτημα οι παλμοί δεν έμειναν κοντά στο πάνω όριο ($hi) για ${talkNearMinSec ~/ 60} λεπτά. '
            'Η ερώτηση έρχεται σε περπάτημα που φτάνει εκεί.',
            style: TextStyle(fontSize: 13.5, height: 1.4, color: c.textSecondary)),
      );
    }
    return AppCard(
      key: const ValueKey('talk-test'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Όταν οι παλμοί ήταν κοντά στους $hi, μπορούσες να μιλάς με προτάσεις;',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
        const SizedBox(height: 4),
        Text('Ερώτηση μόνο στα $talkAskWalks πρώτα περπατήματα.', style: TextStyle(fontSize: 13, color: c.textSecondary)),
        const SizedBox(height: 12),
        for (final (k, label) in options) ...[
          OutlinedButton(
            key: ValueKey('talk-$k'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              alignment: Alignment.centerLeft,
              foregroundColor: c.text,
              backgroundColor: answered == k ? c.tint(c.exercise) : null,
              side: BorderSide(color: answered == k ? c.exercise : c.hairline, width: answered == k ? 2 : 1),
            ),
            onPressed: () => _answer(k),
            child: Text(label),
          ),
          const SizedBox(height: 8),
        ],
        Text('Πρώτο → πρόταση να ανέβει η ζώνη κατά 5. Τρίτο → να κατέβει κατά 5. Μεσαίο → μένει. Όχι πάνω από 10 μακριά '
            'από τον υπολογισμό. Αποφασίζεις εσύ.',
            style: TextStyle(fontSize: 12.5, height: 1.4, color: c.textSecondary)),
      ]),
    );
  }
}
