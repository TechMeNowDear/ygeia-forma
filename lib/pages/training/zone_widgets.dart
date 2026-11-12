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
  accuracy: 'Οι μέγιστοι παλμοί βγαίνουν από την ηλικία (208 − 0,7 × ηλικία) και σε έναν άνθρωπο μπορεί να διαφέρουν ±10. Γι’ αυτό, '
      'τα πρώτα περπατήματα έλεγξε τη ζώνη με το «τεστ ομιλίας». Οι παλμοί ηρεμίας είναι η μεσαία τιμή των παλμών ύπνου των '
      '14 τελευταίων νυχτών. Οι παλμοί καρπού στο περπάτημα είναι αρκετά ακριβείς.',
  cite: 'ACSM Guidelines (μέτρια ένταση 40–59%) · Tanaka 2001 · Π.Ο.Υ. 2020 · Achten & Jeukendrup 2002 · Venables 2005 · '
      'Kraus 2002 (NEJM) · Kodama 2007 · Persinger 2004 (τεστ ομιλίας)',
);

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
            if (training.hrLimit != null) ...[
              const SizedBox(height: 8),
              Text('Υπάρχει όριο γιατρού ${training.hrLimit}: στο ρολόι νικά εκείνο.',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.warn)),
            ],
            const Hairline(vertical: 12),
            Row(children: [
              Expanded(child: Text('Δόνηση όταν την ξεπερνάς', style: TextStyle(fontSize: 15, color: c.text))),
              Switch(
                key: const ValueKey('zone-alert-high'),
                value: s.alertHigh,
                onChanged: (v) => health.setZoneSettings(s.copyWith(alertHigh: v)),
              ),
            ]),
            const SizedBox(height: 4),
            OutlinedButton(
              key: const ValueKey('zone-edit'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), foregroundColor: c.exercise),
              onPressed: () => openZoneSheet(context, health, now),
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

Future<void> openZoneSheet(BuildContext context, HealthStore health, DateTime now) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      routeSettings: const RouteSettings(name: 'Ζώνη περπατήματος'),
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => ZoneSheet(health: health, now: now),
    );

/// Φύλλο «Ζώνη περπατήματος» (σχέδια 12/11, 4β): πώς υπολογίστηκε, αλλαγή, δονήσεις.
class ZoneSheet extends StatefulWidget {
  const ZoneSheet({super.key, required this.health, required this.now});
  final HealthStore health;
  final DateTime now;

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
    final head = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: .3, color: c.textSecondary);
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
                    : 'ηρεμία + 40% και + 59% της διαφοράς «μέγιστοι − ηρεμία» (Karvonen).',
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
                decoration: const InputDecoration(labelText: 'Κάτω'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const ValueKey('zone-hi'),
                controller: _hi,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Πάνω'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('zone-max'),
            controller: _max,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Μέγιστοι παλμοί, αν τους ξέρεις'),
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
            decoration: const InputDecoration(labelText: 'Παλμοί ηρεμίας ξύπνιος, αν τους μέτρησες'),
          ),
          const SizedBox(height: 6),
          Text('Καθιστός, μετά από 5 λεπτά ηρεμίας, το πρωί. Χωρίς τιμή μετρούν οι παλμοί ύπνου, που είναι λίγο χαμηλότεροι.', style: hint),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.bad)),
          ],
          const SizedBox(height: 18),
          Text('ΔΟΝΗΣΗ ΣΤΟ ΡΟΛΟΪ', style: head),
          SwitchListTile(
            key: const ValueKey('zone-sheet-high'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Πάνω από τη ζώνη'),
            subtitle: const Text('Δύο σύντομες δονήσεις όταν μείνεις πάνω ${zoneHoldSec}″. Ξανά μετά από 2′, αν δεν κατέβεις. '
                'Όχι τα πρώτα 5 λεπτά.'),
            value: _s.alertHigh,
            onChanged: (v) => setState(() => _s = _s.copyWith(alertHigh: v)),
          ),
          SwitchListTile(
            key: const ValueKey('zone-sheet-low'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Κάτω από τη ζώνη'),
            subtitle: const Text('Μία δόνηση όταν μείνεις κάτω 1′. Ξανά μετά από 5′.'),
            value: _s.alertLow,
            onChanged: (v) => setState(() => _s = _s.copyWith(alertLow: v)),
          ),
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
        Text('Βάρη: ${w.strengthDays == 1 ? '1 μέρα' : '${w.strengthDays} μέρες'}${w.strengthDays >= 2 ? ' ✓' : ''}',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.text)),
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
    final z = h.zoneOn(DateTime.now());
    // Ανασκόπηση 11/11 (S2): η πρόταση βγαίνει από τη ζώνη ΑΥΤΟΥ του περπατήματος, όχι από την τωρινή, ώστε δεύτερο
    // πάτημα να μη μετακινεί τη ζώνη ξανά. Ίδια απάντηση ή ζώνη ήδη εκεί: καμία ερώτηση.
    final wLo = widget.session.zoneLo, wHi = widget.session.zoneHi;
    if (shift == 0 || before == a || z == null || wLo == null || wHi == null || !mounted) return;
    final lo = wLo + shift, hi = wHi + shift;
    if (z.lo == lo && z.hi == hi) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Να γίνει η ζώνη $lo–$hi;'),
        content: Text(shift > 0
            ? 'Αφού μπορούσες και να τραγουδήσεις, η ζώνη σου μάλλον είναι λίγο πιο πάνω.'
            : 'Αφού λαχάνιαζες, η ζώνη σου μάλλον είναι λίγο πιο κάτω.'),
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
    return AppCard(
      key: const ValueKey('talk-test'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Στο πάνω όριο, μπορούσες να μιλάς με προτάσεις;',
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
        Text('Πρώτο → πρόταση να ανέβει η ζώνη κατά 5. Τρίτο → να κατέβει κατά 5. Μεσαίο → μένει. Αποφασίζεις εσύ.',
            style: TextStyle(fontSize: 12.5, height: 1.4, color: c.textSecondary)),
      ]),
    );
  }
}
