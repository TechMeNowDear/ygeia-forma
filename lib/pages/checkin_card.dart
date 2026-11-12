import 'package:flutter/material.dart';

import '../adaptive.dart';
import '../adaptive_check.dart';
import '../data.dart';
import '../food/food_store.dart';
import '../format.dart';
import '../goals.dart';
import '../profile.dart' show weekdayNames;
import '../theme.dart';
import '../widgets.dart';

/// Η θέση της κάρτας ελέγχου θερμίδων στη Σήμερα (σχέδια A1/A3, 12/11: κάτω από τη ζύγιση). Χωρίς εκκρεμότητα: τίποτα,
/// ούτε κενό. Υπολογίζει μόνο όταν υπάρχουν στόχοι και έχει φορτωθεί το ημερολόγιο φαγητού (αλλιώς θα έβγαινε
/// ψεύτικο «λίγα δεδομένα»).
class CheckInSlot extends StatelessWidget with SelfSpaced {
  const CheckInSlot({super.key, required this.store, required this.food, required this.now});
  final HealthStore store;
  final FoodStore food;
  final DateTime now;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: food,
        builder: (context, _) {
          final c = pendingFor(store, food, now);
          if (c == null) return const SizedBox.shrink(key: ValueKey('today-checkin-none'));
          return Padding(
            padding: const EdgeInsets.only(top: PageFrame.gap),
            child: CheckInCard(check: c, store: store, now: now),
          );
        },
      );

  static CheckIn? pendingFor(HealthStore store, FoodStore food, DateTime now) {
    final g = store.goals;
    final d = store.data;
    if (g == null || d == null || !food.loaded) return null;
    return pendingCheckIn(
      goals: g,
      today: now,
      weights: dailyWeights(d.body),
      intake: (from, to) => dailyIntake(food, from, to),
    );
  }
}

String _kcal(num v) => thousands((v / 10).round() * 10);
String _signed(int v) => v == 0 ? '0' : '${v > 0 ? '+' : '−'}${thousands(v.abs())}';

/// A1 (εβδομαδιαίος έλεγχος) και A3 (γρήγορη απώλεια).
class CheckInCard extends StatelessWidget {
  const CheckInCard({super.key, required this.check, required this.store, required this.now});
  final CheckIn check;
  final HealthStore store;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final k = check;
    final g = k.goals;
    final p = k.proposal;
    final warn = k.kind == CheckKind.fast;
    final accent = warn ? c.warn : c.food;
    final weekday = weekdayNames[DateTime.parse(g.since).weekday - 1];
    final body = TextStyle(fontSize: 15, height: 1.45, color: c.text);
    final bold = TextStyle(fontWeight: FontWeight.w700, color: c.text);
    final small = TextStyle(fontSize: 13.5, height: 1.4, color: c.textSecondary);

    final title = switch (k.kind) {
      CheckKind.fast => 'Χάνεις πιο γρήγορα από το ασφαλές',
      CheckKind.fewData => 'Έλεγχος θερμίδων: λίγα δεδομένα',
      CheckKind.implausible => 'Έλεγχος θερμίδων: κάτι λείπει',
      _ => 'Έλεγχος θερμίδων · κάθε $weekday',
    };

    final Widget text = switch (k.kind) {
      CheckKind.proposal || CheckKind.same => Text.rich(TextSpan(style: body, children: [
          TextSpan(text: 'Από ${k.est!.intakeDays} μέρες φαγητό και ${k.est!.weighIns} ζυγίσεις, '),
          TextSpan(text: 'καις περίπου ${_kcal(k.est!.tdee)} kcal', style: bold),
          TextSpan(
              text: (k.est!.tdee - g.calc.tdee).abs() < 30
                  ? ' τη μέρα, όσο υπολόγισε και ο τύπος.'
                  : ' τη μέρα, όχι ${_kcal(g.calc.tdee)} που υπολόγισε ο τύπος.'),
          if (k.kind == CheckKind.same) const TextSpan(text: ' Ο στόχος σου ταιριάζει: μένει ίδιος.'),
        ])),
      CheckKind.fewData => Text(
          [
            k.status == AdaptStatus.fewWeighIns
                ? 'Στις 3 τελευταίες εβδομάδες έγιναν ${k.weighs} ζυγίσεις· χρειάζονται τουλάχιστον $adaptMinWeighIns, σε 2 εβδομάδες.'
                : 'Στις 3 τελευταίες εβδομάδες μετράνε ${k.days} μέρες φαγητό· χρειάζονται τουλάχιστον $adaptMinIntakeDays. '
                    'Μέρες με λιγότερο από το 60% του στόχου δεν μετράνε: συνήθως κάτι δεν γράφτηκε.',
            'Ο στόχος μένει ίδιος. Ξανά ${weekday == 'Σάββατο' ? 'το επόμενο' : 'την επόμενη'} $weekday.',
          ].join(' '),
          style: body),
      CheckKind.implausible => Text(
          'Με όσα γράφτηκαν βγαίνει ότι καις ${_kcal(k.est!.tdee)} kcal, πολύ μακριά από τον τύπο (${_kcal(g.calc.tdee)}). '
          'Συνήθως φταίνε γεύματα ή σνακ που δεν γράφτηκαν. Ο στόχος μένει ίδιος.',
          style: body),
      CheckKind.fast => Text.rich(TextSpan(style: body, children: [
          const TextSpan(text: 'Τις 2 τελευταίες εβδομάδες: '),
          TextSpan(
              text: '−${dec((k.fastSlope ?? 0).abs())} kg την εβδομάδα'
                  '${k.kgNow == null || k.fastSlope == null ? '' : ' (${dec((k.fastSlope!.abs() / k.kgNow! * 100))}% του βάρους)'}',
              style: bold),
          const TextSpan(text: '. Πάνω από 1% την εβδομάδα χάνονται και μύες.'),
        ])),
    };

    final hasProposal = (k.kind == CheckKind.proposal || k.kind == CheckKind.fast) && p != null;
    final apply = FilledButton(
      key: const ValueKey('checkin-apply'),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: c.foodSolid, foregroundColor: c.onSolid),
      onPressed: () {
        store.setGoals(applyCheckIn(k, now));
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Νέος στόχος: ${thousands(p!.target)} kcal τη μέρα')));
      },
      child: const Text('Εφάρμοσε', softWrap: false),
    );
    final later = OutlinedButton(
      key: const ValueKey('checkin-later'),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: c.textSecondary),
      onPressed: () => store.setGoals(dismissCheckIn(k, now)),
      child: const Text('Όχι τώρα', softWrap: false),
    );
    // Με μεγάλα γράμματα σε στενή οθόνη τα κουμπιά πάνε το ένα κάτω από το άλλο (ποτέ «Εφάρμοσ/ε»).
    final buttons = hasProposal
        ? LayoutBuilder(
            builder: (context, box) => box.maxWidth / MediaQuery.textScalerOf(context).scale(1) < 250
                ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [apply, const SizedBox(height: 8), later])
                : Row(children: [Expanded(child: apply), const SizedBox(width: 10), Expanded(child: later)]),
          )
        : OutlinedButton(
            key: const ValueKey('checkin-ok'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: c.text),
            onPressed: () => store.setGoals(dismissCheckIn(k, now)),
            child: const Text('Εντάξει'),
          );

    return Container(
      key: const ValueKey('today-checkin'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: warn ? c.warnBg : c.card,
        borderRadius: BorderRadius.circular(AppCard.radius),
        border: Border.all(color: warn ? c.warnLine : c.food, width: warn ? 1 : 2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          IconBadge(warn ? Icons.warning_amber_rounded : Icons.restaurant_rounded, accent, size: 40),
          const SizedBox(width: 14),
          Expanded(child: Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: warn ? c.warn : c.text))),
        ]),
        const SizedBox(height: 10),
        text,
        if (hasProposal) ...[
          const SizedBox(height: 12),
          Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 10, runSpacing: 4, children: [
            Text(k.kind == CheckKind.fast ? 'Πρόταση' : 'Νέος στόχος', style: small),
            BigValue(thousands(p.target), key: const ValueKey('checkin-target'), size: 34),
            Text('kcal · ${_signed(p.change)} από ${thousands(p.current)}', style: small),
          ]),
          if (g.kcalSet != null) Text('Αντικαθιστά τον δικό σου στόχο (${thousands(g.kcalSet!)}).', style: small),
          if (p.floored) Text('Δεν κατεβαίνει κάτω από το όριο ασφαλείας.', style: small),
        ],
        const SizedBox(height: 14),
        buttons,
        if (k.kind == CheckKind.proposal || k.kind == CheckKind.same)
          TextButton(
            key: const ValueKey('checkin-how'),
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(44), foregroundColor: c.food),
            onPressed: () => showHowAdapted(context, k),
            child: const Text('Πώς βγήκε'),
          ),
      ]),
    );
  }
}

/// A2: «Πώς βγήκε ο νέος στόχος», βήμα βήμα, με τα δικά σου νούμερα.
Future<void> showHowAdapted(BuildContext context, CheckIn k) {
  final g = k.goals;
  final e = k.est!;
  final p = k.proposal!;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    routeSettings: const RouteSettings(name: 'Πώς βγήκε'),
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) {
      final c = Aigaio.of(context);
      final small = TextStyle(fontSize: 13, height: 1.4, color: c.textSecondary);
      final slope = e.slopeKgWeek;
      final missed = adaptWindowDays - e.intakeDays;
      final kg = k.kgNow ?? g.kg;
      final delta = (kg * g.rate * kcalPerKg / 7).round();
      final wanted = k.wanted;
      final formula = g.calc.tdee;
      final off = (e.tdee - formula).round();
      Widget step(String label, String value, String note) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [InfoRow(label, value), Text(note, style: small)]),
          );
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(p.same ? 'Πώς βγήκε' : 'Πώς βγήκε ο νέος στόχος',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.text)),
          const SizedBox(height: 4),
          Text('${dayMonth(e.from)} – ${dayMonth(e.to)} · $adaptWindowDays μέρες', style: small),
          const SizedBox(height: 10),
          step('1 · Έφαγες κατά μέσο όρο', '${_kcal(e.meanIntake)} kcal',
              'από ${e.intakeDays} μέρες${missed > 0 ? '· $missed μέρες με λίγη ή καθόλου καταγραφή δεν μέτρησαν' : ''}'),
          step('2 · Το βάρος σου άλλαξε', '${slope < 0 ? '−' : (slope > 0 ? '+' : '')}${dec(slope.abs(), 2)} kg / εβδ.',
              'ευθεία από ${e.weighIns} ζυγίσεις (τα νερά μιας μέρας τη μετακινούν λίγο)'),
          step('3 · Άρα καις', '≈ ${_kcal(e.tdee)} kcal',
              '${_kcal(e.meanIntake)} ${slope <= 0 ? '+' : '−'} ${dec(slope.abs(), 2)} × 7.700 ÷ 7'),
          if (g.aim != GoalAim.keep)
            step('4 · Για ${dec(kg * g.rate, 2)} kg την εβδομάδα', '${g.aim == GoalAim.lose ? '−' : '+'} ${thousands(delta)} kcal',
                '${ratePctText(g.rate)} του βάρους σου × 7.700 ÷ 7'),
          const Hairline(vertical: 12),
          InfoRow(p.same ? 'Ο στόχος μένει' : 'Νέος στόχος', '${thousands(p.target)} kcal'),
          if (p.floored)
            Text('Δεν κατεβαίνει κάτω από ${thousands(g.male ? kcalFloorMale : kcalFloorFemale)} kcal (όριο ασφαλείας).', style: small)
          else if (wanted != null && (wanted - p.current).abs() > adaptMaxStep)
            Text(
                'Τα δεδομένα λένε ${thousands(wanted)}. Ο στόχος αλλάζει το πολύ $adaptMaxStep kcal τη φορά, ώστε μια εβδομάδα με '
                'νερά να μη σε ταρακουνά· ο επόμενος έλεγχος συνεχίζει.',
                style: small)
          else if (p.same && wanted != null && wanted != p.current)
            Text('Η διαφορά (${_signed(wanted - p.current)} kcal) είναι κάτω από $adaptMinStep: δεν αξίζει αλλαγή.', style: small),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.tint(c.food), borderRadius: BorderRadius.circular(16)),
            child: Text(
              off.abs() < 100
                  ? 'Ο τύπος ήταν κοντά (${_kcal(formula)}). Η διαφορά είναι μέσα στο λάθος μιας εκτίμησης.'
                  : 'Ο τύπος έλεγε ${_kcal(formula)}: έπεφτε ${thousands(((off.abs()) / 10).round() * 10)} kcal '
                      '${off > 0 ? 'χαμηλά' : 'ψηλά'}. Γι’ αυτό μετράνε τα δικά σου δεδομένα.',
              style: TextStyle(fontSize: 14, height: 1.45, color: c.text),
            ),
          ),
          const SizedBox(height: 12),
          Text(
              'Όσο πιο πλήρης η καταγραφή φαγητού, τόσο πιο σωστή η εκτίμηση. Ισοζύγιο ενέργειας (Hall 2008). Καμία τιμή από AI: '
              'μόνο ό,τι έγραψες και ό,τι ζύγισε η ζυγαριά.',
              style: small),
        ]),
      );
    },
  );
}
