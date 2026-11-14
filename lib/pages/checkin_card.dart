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
            padding: const EdgeInsets.only(bottom: PageFrame.gap),
            child: CheckInCard(check: c, store: store, now: now),
          );
        },
      );

  static CheckIn? pendingFor(HealthStore store, FoodStore food, DateTime now) {
    final g = store.goals;
    final d = store.data;
    if (g == null || d == null || !food.loaded) return null;
    // Round 1 (f3 · S1-10): όσο φαίνεται το αντίγραφο του παρασκηνίου ([Dashboard.background]: όχι πλήρης ανάγνωση·
    // από παλιότερη έκδοση, ζυγίσεις μόνο 30 ημερών) η κάρτα περιμένει την πλήρη ανάγνωση της εφαρμογής. Πριν, στο
    // άνοιγμα έβγαινε από μέρος των ζυγίσεων και μπορούσε να δείξει άλλη πρόταση από αυτήν λίγα δευτερόλεπτα μετά.
    if (d.background) return null;
    // Round 1 (f1 · S11-2): ζύγιση που δεν μπορεί να είναι δική σου δεν μπαίνει στον έλεγχο· η κάρτα τη γράφει.
    // Round 1 (f1 · S11-8): αν οι ζυγίσεις δεν διαβάστηκαν τώρα, η κάρτα δεν γράφει «έγιναν 0 ζυγίσεις» και το
    // «Εντάξει» δεν ξοδεύει τον έλεγχο της εβδομάδας: τη μέρα ελέγχου λέει ότι δεν διαβάστηκαν, χωρίς κουμπί.
    // Χωρίς ζυγίσεις στην ανάγνωση και χωρίς σφάλμα (δεν δόθηκε άδεια): καμία κάρτα· ο έλεγχος μένει ανοιχτός ως να
    // διαβαστούν (πριν: «έγιναν 0 ζυγίσεις» και το «Εντάξει» ξόδευε τον έλεγχο).
    final bodyFailed = d.failed.contains('body');
    if (!d.bodyOk && !bodyFailed) return null;
    final w = guardedWeights(d.body);
    return pendingCheckIn(
      goals: g,
      today: now,
      weights: w.used,
      foreign: w.foreign,
      weightsRead: d.bodyOk && !bodyFailed,
      intake: (from, to) => dailyIntake(food, from, to),
    );
  }
}

String _kcal(num v) => thousands((v / 10).round() * 10);
String _signed(int v) => v == 0 ? '0' : '${v > 0 ? '+' : '−'}${thousands(v.abs())}';

/// «1,3%» για την απώλεια την εβδομάδα. Κοντά στο όριο γράφει δύο δεκαδικά («1,02%»), ώστε να μη διαβάζεται «1,0% …
/// πάνω από 1%» (έλεγχος 13/11, S1-14).
String lossPctText(double pct) {
  final one = dec(pct);
  if (one != '1,0') return '$one%';
  final two = dec(pct, 2);
  return two == '1,00' ? 'λίγο πάνω από 1%' : '$two%';
}

/// «Η ζύγιση Τετ 9/12 (45,0 kg) διαφέρει πολύ από τις άλλες σου ζυγίσεις και δεν μέτρησε.» (S11-2)
String foreignWeighText(List<(DateTime, double)> foreign) {
  final items = [for (final (d, kg) in foreign) '${shortDayDate(d)} (${dec(kg)} kg)'].join(' · ');
  return foreign.length == 1
      ? 'Η ζύγιση $items διαφέρει πολύ από τις άλλες σου ζυγίσεις και δεν μέτρησε.'
      : 'Οι ζυγίσεις $items διαφέρουν πολύ από τις άλλες σου ζυγίσεις και δεν μέτρησαν.';
}

/// «Η μέρα Τετ 2/12 (19.710 kcal) έχει πάρα πολλές θερμίδες για μία μέρα και δεν μέτρησε. …» (S11-3)
String absurdDaysText(List<(DateTime, double)> days) {
  final items = [for (final (d, kcal) in days) '${shortDayDate(d)} (${thousands(kcal)}\u00A0kcal)'].join(' · ');
  return days.length == 1
      ? 'Η μέρα $items έχει πάρα πολλές θερμίδες για μία μέρα και δεν μέτρησε. Αν είναι λάθος ποσότητα, διόρθωσέ τη στη Διατροφή.'
      : 'Οι μέρες $items έχουν πάρα πολλές θερμίδες για μία μέρα και δεν μέτρησαν. Αν είναι λάθος ποσότητες, διόρθωσέ τες '
          'στη Διατροφή.';
}

/// Το κείμενο της κάρτας «λίγα δεδομένα» (έλεγχος 13/11: S1-14, S11-9, U3b-4, U3b-16). Ενικός και πληθυντικός σωστά·
/// όταν οι ζυγίσεις φτάνουν σε αριθμό αλλά είναι μαζεμένες σε λίγες μέρες, το λέει (πριν: «έγιναν 9· χρειάζονται 6»).
String fewDataText(AdaptStatus? status, {required int days, required int weighs}) {
  if (status == AdaptStatus.fewWeighIns) {
    if (weighs >= adaptMinWeighIns) {
      return 'Οι $weighs ζυγίσεις των 3 τελευταίων εβδομάδων είναι μαζεμένες σε λίγες μέρες· η πρώτη και η τελευταία πρέπει '
          'να απέχουν τουλάχιστον 2 εβδομάδες.';
    }
    final had = weighs == 0
        ? 'δεν έγινε καμία ζύγιση'
        : (weighs == 1 ? 'έγινε 1 ζύγιση' : 'έγιναν $weighs ζυγίσεις');
    return 'Στις 3 τελευταίες εβδομάδες $had· χρειάζονται τουλάχιστον $adaptMinWeighIns, απλωμένες σε τουλάχιστον 2 εβδομάδες.';
  }
  final had = days == 0
      ? 'δεν μετρά καμία μέρα με φαγητό'
      : (days == 1 ? 'μετρά 1 μέρα με φαγητό' : 'μετράνε $days μέρες με φαγητό');
  return 'Στις 3 τελευταίες εβδομάδες $had· χρειάζονται τουλάχιστον $adaptMinIntakeDays. '
      'Μέρες με λιγότερο από το 60% του στόχου δεν μετράνε: συνήθως κάτι δεν γράφτηκε.';
}

/// Round 7 (R7-A1-1): το κείμενο της πρότασης από τη ζυγαριά ([CheckIn.lowLog]). Τι έκανε το βάρος, τι ζητά ο ρυθμός
/// σου, και με απλά λόγια, χωρίς κατηγορία, ότι μάλλον λείπει φαγητό από το ημερολόγιο. Κανένα «καις …»: η εκτίμηση από
/// το ημερολόγιο δεν μέτρησε. «Τις 3 τελευταίες εβδομάδες το βάρος σου ανέβαινε 0,30 kg την εβδομάδα, ενώ ο στόχος σου
/// είναι να πέφτει 0,48 kg την εβδομάδα. …»
String lowLogText(CheckIn k) {
  final e = k.est!;
  final g = k.goals;
  final kg = k.kgNow ?? g.kg;
  final s = e.slopeKgWeek;
  final moved = s >= 0.005
      ? 'ανέβαινε ${dec(s, 2)}\u00A0kg την εβδομάδα'
      : (s <= -0.005 ? 'έπεφτε μόνο ${dec(-s, 2)}\u00A0kg την εβδομάδα' : 'έμενε σχεδόν ίδιο');
  final plan = switch (g.aim) {
    GoalAim.lose => 'να πέφτει ${dec(kg * g.rate, 2)}\u00A0kg την εβδομάδα',
    GoalAim.keep => 'να μένει ίδιο',
    GoalAim.gain => 'να ανεβαίνει ${dec(kg * g.rate, 2)}\u00A0kg την εβδομάδα',
  };
  return 'Τις ${e.windowDays ~/ 7} τελευταίες εβδομάδες το βάρος σου $moved, ενώ ο στόχος σου είναι $plan. Με όσα '
      'γράφτηκαν στο ημερολόγιο, η ζυγαριά θα έπρεπε να δείχνει λιγότερα: μάλλον λείπουν κάποια γεύματα, σνακ ή ποτά, '
      'κάτι που συμβαίνει σχεδόν σε όλους. Ο στόχος κατεβαίνει με βάση τη ζυγαριά.';
}

/// «τη Δευτέρα 28 Δεκεμβρίου», «το Σάββατο 26 Δεκεμβρίου».
String _onDay(DateTime d) => '${const ['τη', 'την', 'την', 'την', 'την', 'το', 'την'][d.weekday - 1]} ${longDate(d)}';

/// Round 8 (R8-A1-4): το κείμενο της κάρτας «μαζεύω δεδομένα» ([CheckKind.gathering]). Χωρίς κενό στο φαγητό η πρώτη
/// εκτίμηση βγαίνει την επόμενη μέρα ελέγχου ([firstEstimateDay])· με κενό, 3 εβδομάδες αφού ξαναρχίσει η καταγραφή
/// ([estimateDayAfterGap]), όπως τη βγάζει ο έλεγχος και τη γράφει η σελίδα «Στόχοι». Πριν, η κάρτα έγραφε «την επόμενη
/// Δευτέρα» ενώ η πρώτη εκτίμηση έβγαινε δύο εβδομάδες αργότερα.
String gatheringText(CheckIn k) {
  final g = k.goals;
  final weekday = weekdayNames[DateTime.parse(g.since).weekday - 1];
  const skip = 'Η πρώτη εβδομάδα δεν μετρά: τότε φεύγουν κυρίως νερά, και η εκτίμηση θα έβγαινε πιο ψηλή από την αληθινή.';
  final gap = k.gap;
  if (gap == null) {
    return '$skip Η πρώτη εκτίμηση βγαίνει ${weekday == 'Σάββατο' ? 'το επόμενο' : 'την επόμενη'} $weekday, με 3 εβδομάδες '
        'δεδομένα. Ο στόχος μένει ίδιος.';
  }
  final restart = gap.restart;
  final day = estimateDayAfterGap(g, firstEstimateDay(g), gap);
  if (restart == null || day == null) {
    return '$skip Από ${dayMonth(gap.from)} δεν έχει γραφτεί φαγητό που να μετρά: η πρώτη εκτίμηση βγαίνει 3 εβδομάδες αφού '
        'ξαναρχίσει η καταγραφή. Ο στόχος μένει ίδιος.';
  }
  return '$skip Από ${dayMonth(gap.from)} ως ${dayMonth(gap.to)} δεν γράφτηκε φαγητό που να μετρά, άρα η εκτίμηση θέλει 3 '
      'εβδομάδες από ${dayMonth(restart)}: η πρώτη βγαίνει ${_onDay(day)}. Ο στόχος μένει ίδιος.';
}

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

    final next = 'Ξανά ${weekday == 'Σάββατο' ? 'το επόμενο' : 'την επόμενη'} $weekday.';
    // Round 8 (R8-A1-3): εκτίμηση πολύ ΨΗΛΑ (πάνω από το [adaptHighShare] του τύπου). Γεύματα που δεν γράφτηκαν τη ρίχνουν
    // (μέσος όρος φαγητού − αλλαγή βάρους), δεν την ανεβάζουν· άρα εδώ φταίνε άλλα και η κάρτα τα λέει.
    final high = k.kind == CheckKind.implausible && k.est != null && k.est!.tdee > adaptHighShare * g.calc.tdee;
    // Έλεγχος 13/11 (S1-12): όχι «πιο γρήγορα από το ασφαλές». Το Helms 2014 λέει 0,5–1% την εβδομάδα «για να κρατιούνται
    // οι μύες», όχι ότι πιο γρήγορα είναι επικίνδυνο· ο τίτλος λέει μόνο αυτό που μετρήθηκε.
    final title = switch (k.kind) {
      CheckKind.fast => 'Χάνεις πάνω από 1% του βάρους την εβδομάδα',
      CheckKind.fewData => 'Έλεγχος θερμίδων: λίγα δεδομένα',
      CheckKind.gathering => 'Έλεγχος θερμίδων: μαζεύω δεδομένα',
      CheckKind.implausible => high ? 'Έλεγχος θερμίδων: κάτι δεν ταιριάζει' : 'Έλεγχος θερμίδων: κάτι λείπει',
      CheckKind.gap => 'Έλεγχος θερμίδων: κενό στο φαγητό',
      CheckKind.foreign => k.foreign.length == 1 ? 'Μια ζύγιση δεν μέτρησε' : 'Κάποιες ζυγίσεις δεν μέτρησαν',
      CheckKind.unread => 'Έλεγχος θερμίδων: οι ζυγίσεις δεν διαβάστηκαν',
      _ => 'Έλεγχος θερμίδων · κάθε\u00A0$weekday',
    };

    final Widget text = switch (k.kind) {
      // Round 7 (R7-A1-1): η πρόταση βγήκε από τη ζυγαριά, γιατί με όσα γράφτηκαν η εκτίμηση ήταν πολύ χαμηλή. Δεν
      // γράφεται «καις …»: εκείνος ο αριθμός δεν είναι αξιόπιστος.
      CheckKind.proposal when k.lowLog => Text(lowLogText(k), style: body),
      CheckKind.proposal || CheckKind.same => Text.rich(TextSpan(style: body, children: [
          TextSpan(text: 'Από ${k.est!.intakeDays} μέρες με φαγητό και ${k.est!.weighIns} ζυγίσεις, '),
          TextSpan(text: 'καις περίπου ${_kcal(k.est!.tdee)}\u00A0kcal', style: bold),
          // Συμβούλιο 2, Α1: «όχι Χ που υπολόγισε ο τύπος» μόνο όταν η διαφορά ξεπερνά το περιθώριο των ζυγίσεων.
          // U3b-27: ο τύπος με τον ίδιο αριθμό που γράφουν ο οδηγός και το «Πώς υπολογίστηκε» (2.745, όχι 2.750).
          TextSpan(
              text: (k.est!.tdee - g.calc.tdee).abs() < 30
                  ? ' τη μέρα, όσο υπολόγισε και ο τύπος.'
                  : (k.est!.tdee - g.calc.tdee).abs() <= k.est!.guardKcal
                      ? ' τη μέρα, κοντά στον τύπο (${thousands(g.calc.tdee)}).'
                      : ' τη μέρα, όχι ${thousands(g.calc.tdee)} που υπολόγισε ο τύπος.'),
          if (k.kind == CheckKind.same) TextSpan(text: _sameText(k)),
        ])),
      // Συμβούλιο 2, Α2: την 21η μέρα δεν βγαίνει ακόμα εκτίμηση, γιατί η πρώτη εβδομάδα δεν μετρά.
      CheckKind.gathering => Text(gatheringText(k), style: body),
      CheckKind.fewData =>
        Text('${fewDataText(k.status, days: k.days, weighs: k.weighs)} Ο στόχος μένει ίδιος. $next', style: body),
      // Έλεγχος 13/11 (S1-1): κενό καταγραφής. Ο μέσος όρος φαγητού βγαίνει μόνο από τις γραμμένες μέρες και η αλλαγή
      // βάρους από όλες· με μέρες στη σειρά χωρίς φαγητό η εκτίμηση δεν είναι σωστή, άρα δεν βγαίνει.
      CheckKind.gap => Text(_gapText(k, next), style: body),
      // Round 2 (g4 · R2-E-2): «ξένη» είναι πια μόνο ζύγιση ανάμεσα σε ζυγίσεις που συμφωνούν μεταξύ τους (weight_guard.dart)·
      // η υπόσχεση «θα μετρήσει μόλις συμφωνήσουν…» δεν ισχύει γι' αυτήν και βγήκε. Ζύγιση χωρίς ακόμα επόμενη δεν
      // λέγεται ξένη· περιμένει την επόμενη (μία αρκεί).
      CheckKind.foreign => Text(
          k.foreign.length == 1
              ? '${foreignWeighText(k.foreign)} Δεν μπήκε στον έλεγχο θερμίδων: οι ζυγίσεις σου πριν και μετά από αυτήν '
                  'συμφωνούν μεταξύ τους, όχι μαζί της. Αν δεν είναι δική σου, δεν χρειάζεται να κάνεις τίποτα.'
              : '${foreignWeighText(k.foreign)} Δεν μπήκαν στον έλεγχο θερμίδων: οι ζυγίσεις σου πριν και μετά από αυτές '
                  'συμφωνούν μεταξύ τους, όχι μαζί τους. Αν δεν είναι δικές σου, δεν χρειάζεται να κάνεις τίποτα.',
          style: body),
      CheckKind.unread => Text(
          'Η Samsung Health δεν έδωσε τώρα τις ζυγίσεις σου, άρα ο έλεγχος δεν μπορεί να γίνει. Τράβηξε τη Σήμερα προς τα '
          'κάτω για νέα ανάγνωση: η κάρτα θα βγει μόλις διαβαστούν. Ο στόχος μένει ίδιος.',
          style: body),
      CheckKind.implausible => Text(
          high
              ? 'Με όσα γράφτηκαν βγαίνει ότι καις ${_kcal(k.est!.tdee)}\u00A0kcal, πολύ πιο ψηλά από τον τύπο '
                  '(${thousands(g.calc.tdee)}). Συνήθως φταίνε ποσότητες γραμμένες μεγαλύτερες από όσο έφαγες (π.χ. '
                  'μαγειρεμένο φαγητό γραμμένο σαν ωμό, ή κάτι γραμμένο δύο φορές) ή νερά που έφυγαν γρήγορα (π.χ. σε '
                  'αρρώστια). Ο στόχος μένει ίδιος.'
              : 'Με όσα γράφτηκαν βγαίνει ότι καις ${_kcal(k.est!.tdee)}\u00A0kcal, πολύ μακριά από τον τύπο (${thousands(g.calc.tdee)}). '
                  'Συνήθως φταίνε γεύματα ή σνακ που δεν γράφτηκαν. Ο στόχος μένει ίδιος.',
          style: body),
      CheckKind.fast => Text.rich(TextSpan(style: body, children: [
          TextSpan(text: '${fastPeriodText(k.fastDays)}: '),
          // Δύο δεκαδικά στα kg, ώστε το ποσοστό δίπλα να βγαίνει από τον αριθμό που φαίνεται (U3b-6).
          TextSpan(
              text: '−${dec((k.fastSlope ?? 0).abs(), 2)}\u00A0kg την εβδομάδα'
                  '${k.kgNow == null || k.fastSlope == null ? '' : ' (${lossPctText(k.fastSlope!.abs() / k.kgNow! * 100)} του βάρους)'}',
              style: bold),
          const TextSpan(text: '. Πάνω από 1% την εβδομάδα γίνεται πιο δύσκολο να κρατήσεις τους μύες.'),
          // Έλεγχος 13/11 (S1-2): χωρίς πρόταση, γιατί το ημερολόγιο δείχνει ότι τρως πολύ κάτω από τον στόχο (ή δεν
          // δείχνει πόσο τρως). Τότε δεν φταίει ο στόχος: ανεβάζοντάς τον δεν αλλάζει τίποτα.
          if (p == null) TextSpan(text: _fastNoProposalText(k)),
        ])),
    };
    // Ό,τι δεν μέτρησε γράφεται κάτω από το κείμενο της κάρτας, με απλά λόγια (S11-2, S11-3).
    final notes = [
      if (k.kind != CheckKind.foreign && k.foreign.isNotEmpty) foreignWeighText(k.foreign),
      if (k.absurd.isNotEmpty) absurdDaysText(k.absurd),
    ];

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
    final Widget? buttons = k.kind == CheckKind.unread
        ? null
        : hasProposal
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
        for (final note in notes)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(note, style: small)),
        if (hasProposal) ...[
          const SizedBox(height: 12),
          // Η μονάδα μένει δίπλα στον αριθμό και όταν η γραμμή σπάει (U3b-7): «Νέος στόχος 2.100 kcal» / «−150 από 2.250».
          Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 10, runSpacing: 4, children: [
            Text(k.kind == CheckKind.fast ? 'Πρόταση' : 'Νέος στόχος', style: small),
            BigValue(thousands(p.target), unit: 'kcal', key: const ValueKey('checkin-target'), size: 34),
            Text('${_signed(p.change)} από ${thousands(p.current)}', style: small),
          ]),
          if (g.kcalSet != null) Text('Αντικαθιστά τον δικό σου στόχο (${thousands(g.kcalSet!)}).', style: small),
          // R7-A1-4: με τα λόγια της οδηγίας (AHA/ACC/TOS 2013).
          if (p.floored)
            Text('Δεν κατεβαίνει κάτω από ${thousands(g.male ? kcalFloorMale : kcalFloorFemale)}\u00A0kcal, ${floorWhy(g.male)}.',
                style: small),
        ],
        if (buttons != null) ...[const SizedBox(height: 14), buttons],
        // R7-A1-1: η πρόταση από τη ζυγαριά εξηγείται ολόκληρη στην κάρτα· το «Πώς βγήκε» θα έδειχνε την εκτίμηση που δεν μέτρησε.
        if ((k.kind == CheckKind.proposal || k.kind == CheckKind.same) && !k.lowLog)
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

/// Το τέλος του κειμένου όταν ο στόχος μένει ίδιος: γιατί μένει.
String _sameText(CheckIn k) {
  final p = k.proposal, e = k.est;
  if (k.tooFast) {
    // S1-3: ο στόχος δεν κατεβαίνει όσο χάνεις πάνω από 1% την εβδομάδα. Αν το ημερολόγιο δείχνει και γιατί, το λέει.
    const fast = ' Χάνεις όμως πάνω από 1% του βάρους την εβδομάδα: ο στόχος δεν κατεβαίνει όσο χάνεις τόσο γρήγορα.';
    if (p == null || e == null) return fast;
    final eaten = (e.meanIntake / 10).round() * 10;
    // Γύρος 2 (R2-A-1): σύγκριση με τους στόχους που ίσχυαν τις ίδιες μέρες, όχι με τον τωρινό. Πριν, όποιος έτρωγε ακριβώς
    // τους στόχους του, μετά από δύο αυξήσεις μέσα στο παράθυρο, άκουγε «τρως 340 λιγότερες».
    final targetMean = k.estTarget;
    final target = targetMean == null ? p.current : (targetMean / 10).round() * 10;
    final under = target - eaten;
    if (under <= adaptMaxStep) return fast;
    if (target == p.current) {
      return '$fast Τρως κατά μέσο όρο ${thousands(eaten)}\u00A0kcal, ${thousands(under)} λιγότερες από τον στόχο σου: φάε πιο '
          'κοντά στον στόχο.';
    }
    return '$fast Τρως κατά μέσο όρο ${thousands(eaten)}\u00A0kcal, ${thousands(under)} λιγότερες από τους στόχους σου αυτές τις '
        'εβδομάδες (κατά μέσο όρο ${thousands(target)}): φάε πιο κοντά στον στόχο.';
  }
  final held = k.heldDays;
  if (held != null) {
    // S1-4: όχι δεύτερη αλλαγή μέσα σε λίγες μέρες.
    final ago = held <= 0 ? 'σήμερα' : (held == 1 ? 'χθες' : 'πριν από $held μέρες');
    return ' Ο στόχος άλλαξε $ago: δεν αλλάζει ξανά τόσο σύντομα. Ο επόμενος έλεγχος συνεχίζει.';
  }
  if (p != null && p.withinNoise) {
    return ' Η διαφορά από τον στόχο σου είναι μέσα στο φυσιολογικό εύρος των ζυγίσεων: μένει ίδιος.';
  }
  return ' Ο στόχος σου ταιριάζει: μένει ίδιος.';
}

/// Γρήγορη απώλεια χωρίς πρόταση (S1-2): τι δείχνει το ημερολόγιο φαγητού.
/// Γύρος 2: «τις τελευταίες μέρες», γιατί τώρα μετρούν κυρίως αυτές (R2-A-3)· και όταν ο στόχος άλλαξε μέσα στις μέρες
/// που κρίθηκαν, η διαφορά είναι από τους στόχους που ίσχυαν τότε, με τον μέσο όρο τους γραμμένο (R2-A-1).
String _fastNoProposalText(CheckIn k) {
  final g = k.goals;
  final mean = k.fastIntake;
  if (mean == null) {
    return ' Τις τελευταίες μέρες δεν έχει γραφτεί αρκετό φαγητό για να φανεί πόσο τρως. Αν τρως λιγότερο από τον στόχο σου '
        '(${thousands(g.kcal)}\u00A0kcal), φάε πιο κοντά σε αυτόν. Ο στόχος μένει ίδιος.';
  }
  final eaten = (mean / 10).round() * 10;
  final targetMean = k.fastTarget;
  final target = targetMean == null ? g.kcal : (targetMean / 10).round() * 10;
  if (target == g.kcal) {
    return ' Στο ημερολόγιο φαγητού γράφτηκαν κατά μέσο όρο ${thousands(eaten)}\u00A0kcal τη μέρα, ${thousands(g.kcal - eaten)} '
        'λιγότερες από τον στόχο σου (${thousands(g.kcal)}). Αν τα έγραψες όλα, τρως πολύ λίγο: φάε πιο κοντά στον στόχο. '
        'Ο στόχος μένει ίδιος.';
  }
  return ' Στο ημερολόγιο φαγητού γράφτηκαν κατά μέσο όρο ${thousands(eaten)}\u00A0kcal τη μέρα, ${thousands(target - eaten)} '
      'λιγότερες από τους στόχους σου αυτές τις μέρες (κατά μέσο όρο ${thousands(target)}). Αν τα έγραψες όλα, τρως πολύ '
      'λίγο: φάε πιο κοντά στον στόχο (${thousands(g.kcal)}). Ο στόχος μένει ίδιος.';
}

/// Κενό καταγραφής (S1-1): ανοιχτό ακόμα, ή κλειστό με την εκτίμηση να ξαναρχίζει.
String _gapText(CheckIn k, String next) {
  final gap = k.gap;
  if (gap == null) return 'Λείπουν μέρες φαγητού στη σειρά, άρα η εκτίμηση δεν θα ήταν σωστή. Ο στόχος μένει ίδιος. $next';
  final restart = gap.restart;
  if (restart == null) {
    final n = daysBetween(gap.from, gap.to) + 1;
    return 'Από ${dayMonth(gap.from)} δεν έχει γραφτεί φαγητό που να μετρά (${countText(n, 'μέρα', 'μέρες')} στη σειρά). Με '
        'τέτοιο κενό η εκτίμηση δεν θα ήταν σωστή, άρα δεν βγαίνει. Ο στόχος μένει ίδιος. $next';
  }
  return 'Από ${dayMonth(gap.from)} ως ${dayMonth(gap.to)} δεν γράφτηκε φαγητό που να μετρά. Με τέτοιο κενό η εκτίμηση δεν θα '
      'ήταν σωστή: ξαναρχίζει με τις μέρες από ${dayMonth(restart)} και μετά, και θέλει 3 εβδομάδες δεδομένα. Ο στόχος '
      'μένει ίδιος. $next';
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
      // Μέρες με πάρα πολλές θερμίδες (S11-3) γράφονται χωριστά από τις μέρες με λίγη ή καθόλου καταγραφή.
      final tooMuch = k.absurd.length;
      final missed = e.windowDays - e.intakeDays - tooMuch;
      // Το περιθώριο των ζυγίσεων (Συμβούλιο 2, Α1), στρογγυλεμένο στα 10· κάτω από 10 kcal δεν γράφεται.
      final guard = (e.guardKcal / 10).round() * 10;
      final kg = k.kgNow ?? g.kg;
      final delta = (kg * g.rate * kcalPerKg / 7).round();
      final wanted = k.wanted;
      final formula = g.calc.tdee;
      final rawOff = e.tdee - formula;
      // Η διαφορά που γράφεται είναι η διαφορά των δύο αριθμών όπως φαίνονται (εκτίμηση στα 10, τύπος όπως στο «Πώς
      // υπολογίστηκε»): πριν «2.750» και «2.580» στην οθόνη και «έπεφτε 160 ψηλά» από κάτω (έλεγχος 13/11, U3b-5, U3b-27).
      final off = (e.tdee / 10).round() * 10 - formula.round();
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
          Text('${dayMonth(e.from)} – ${dayMonth(e.to)} · ${e.windowDays} μέρες', style: small),
          const SizedBox(height: 10),
          step(
              '1 · Έφαγες κατά μέσο όρο',
              '${_kcal(e.meanIntake)} kcal',
              'από ${e.intakeDays} μέρες'
                  '${missed > 0 ? '· ${countText(missed, 'μέρα', 'μέρες')} με λίγη ή καθόλου καταγραφή δεν ${missed == 1 ? 'μέτρησε' : 'μέτρησαν'}' : ''}'
                  '${tooMuch > 0 ? '· ${countText(tooMuch, 'μέρα', 'μέρες')} με πάρα πολλές θερμίδες δεν ${tooMuch == 1 ? 'μέτρησε' : 'μέτρησαν'}' : ''}'),
          step('2 · Αλλαγή βάρους την εβδομάδα', '${slope < 0 ? '−' : (slope > 0 ? '+' : '')}${dec(slope.abs(), 2)} kg',
              'ευθεία από ${e.weighIns} ζυγίσεις (τα νερά μιας μέρας τη μετακινούν λίγο)'),
          step('3 · Άρα καις', '≈ ${_kcal(e.tdee)} kcal',
              '${_kcal(e.meanIntake)} ${slope <= 0 ? '+' : '−'} ${dec(slope.abs(), 2)} × 7.700 ÷ 7'
                  '${guard >= 10 ? '. Οι ζυγίσεις αφήνουν περιθώριο ±${thousands(guard)}\u00A0kcal' : ''}'),
          if (g.aim != GoalAim.keep)
            // Με το βάρος γραμμένο, ώστε ο αριθμός να ξαναβγαίνει από όσα φαίνονται (U3b-20): 0,5% × 89,2 × 7.700 ÷ 7 = 491.
            step('4 · Για ${dec(kg * g.rate, 2)} kg την εβδομάδα', '${g.aim == GoalAim.lose ? '−' : '+'}${thousands(delta)} kcal',
                '${ratePctText(g.rate)} × ${dec(kg)} kg × 7.700 ÷ 7'),
          const Hairline(vertical: 12),
          InfoRow(p.same ? 'Ο στόχος μένει' : 'Νέος στόχος', '${thousands(p.target)} kcal'),
          // Πρώτα το περιθώριο των ζυγίσεων (Συμβούλιο 2, Α1): αν ο στόχος έμεινε γι' αυτό, αυτός είναι ο λόγος που γράφεται.
          // Χωρίς αριθμό διαφοράς, ώστε να μη φανεί ποτέ στόχος κάτω από το κάτω όριο (μ1).
          if (k.tooFast)
            Text('Χάνεις πάνω από 1% του βάρους την εβδομάδα: ο στόχος δεν κατεβαίνει όσο χάνεις τόσο γρήγορα.', style: small)
          else if (k.heldDays != null)
            Text('Ο στόχος άλλαξε πριν από λίγες μέρες: δεν αλλάζει ξανά τόσο σύντομα.', style: small)
          else if (p.withinNoise)
            Text(
                'Η διαφορά από τον στόχο σου είναι μέσα στο φυσιολογικό εύρος των ζυγίσεων'
                '${guard >= 10 ? ' (±${thousands(guard)}\u00A0kcal)' : ''}: δεν αξίζει αλλαγή. Με περισσότερες ζυγίσεις το εύρος μικραίνει.',
                style: small)
          // Και όταν ο νέος στόχος δεν είναι ακόμα στο όριο αλλά τα δεδομένα θέλουν κάτω από αυτό (Συμβούλιο 2, μ1): εδώ
          // γράφεται το όριο, ποτέ «τα δεδομένα λένε» έναν αριθμό κάτω από το κάτω όριο. R7-A1-4: με τα λόγια της οδηγίας.
          else if (p.floored || k.wantsBelowFloor)
            Text('Δεν κατεβαίνει κάτω από ${thousands(g.male ? kcalFloorMale : kcalFloorFemale)}\u00A0kcal: ${floorWhy(g.male)}.',
                style: small)
          else if (wanted != null && (wanted - p.current).abs() > adaptMaxStep)
            Text(
                'Τα δεδομένα λένε ${thousands(wanted)}. Ο στόχος αλλάζει το πολύ $adaptMaxStep\u00A0kcal τη φορά, ώστε μια εβδομάδα με '
                'νερά να μη σε ταρακουνά· ο επόμενος έλεγχος συνεχίζει.',
                style: small)
          else if (p.same && wanted != null && wanted != p.current)
            Text('Η διαφορά (${_signed(wanted - p.current)}\u00A0kcal) είναι κάτω από $adaptMinStep: δεν αξίζει αλλαγή.', style: small),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.tint(c.food), borderRadius: BorderRadius.circular(16)),
            child: Text(
              // «Έπεφτε Χ χαμηλά» μόνο όταν η διαφορά από τον τύπο ξεπερνά και το περιθώριο των ζυγίσεων (Α1).
              rawOff.abs() < 100 || rawOff.abs() <= e.guardKcal
                  ? 'Ο τύπος ήταν κοντά (${thousands(formula)}). Η διαφορά είναι μέσα στο λάθος μιας εκτίμησης.'
                  : 'Ο τύπος έλεγε ${thousands(formula)}: έπεφτε ${thousands(off.abs())}\u00A0kcal '
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
