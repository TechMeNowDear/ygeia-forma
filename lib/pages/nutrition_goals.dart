import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../adaptive_check.dart' show targetOn;
import '../data.dart';
import '../food/chol.dart';
import '../food/food_model.dart';
import '../food/food_store.dart';
import '../format.dart';
import '../goals.dart';
import '../reference.dart' show MetricInfo;
import '../theme.dart';
import '../widgets.dart';
import 'goals_page.dart';
import 'info_sheet.dart';
import 'nutrition.dart' show proteinColor;

/// Η Διατροφή με στόχους (σχέδια 12/11, 3α–3γ). Οι αριθμοί έρχονται μόνο από τη βάση τροφίμων και τους τύπους του
/// goals.dart· τίποτα από AI.

/// «Μένουν 1.009 kcal» / «150 kcal πάνω από τον στόχο». [today]: για άλλες μέρες λέει «κάτω/πάνω από τον στόχο».
({String label, String value, bool over}) kcalLeft(int eaten, int goal, {required bool today}) {
  final diff = goal - eaten;
  if (diff >= 0) return (label: today ? 'Μένουν' : 'Κάτω από τον στόχο', value: thousands(diff), over: false);
  return (label: 'Πάνω από τον στόχο', value: thousands(-diff), over: true);
}

/// Η τιμή με ένα δεκαδικό, όπως τη γράφει η οθόνη (round7, R7-A3-3/4: η απόφαση «πάνω από το όριο» με τον αριθμό που
/// φαίνεται).
double oneDecimal(double v) => double.parse(v.toStringAsFixed(1));

/// Η μέρα [day] είναι πριν από τους στόχους (πριν από το «since» τους): τότε η Διατροφή δείχνει το απλό «Σύνολο ημέρας»,
/// όχι «πάνω/κάτω από τον στόχο» με έναν στόχο που δεν υπήρχε (round8, R8-A1-5).
bool beforeGoals(Goals g, DateTime day) {
  final since = DateTime.tryParse(g.since);
  return since != null && dayOf(day).isBefore(dayOf(since));
}

/// Σύνολο ημέρας με τους στόχους (αντικαθιστά τη «Σύνολο ημέρας» όταν υπάρχουν στόχοι).
class GoalsSummaryCard extends StatelessWidget {
  const GoalsSummaryCard(
      {super.key, required this.totals, required this.goals, required this.today, required this.health, this.day});
  final Totals totals;
  final Goals goals;
  final bool today;
  final HealthStore health;

  /// Η μέρα που φαίνεται (για μέρα που πέρασε: ο στόχος που ίσχυε εκείνη τη μέρα).
  final DateTime? day;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final t = totals, g = goals;
    // Round8 (R8-A1-5): μέρα που πέρασε κρίνεται με τον στόχο θερμίδων που ίσχυε ΕΚΕΙΝΗ τη μέρα ([targetOn], ο ίδιος κανόνας
    // με τον εβδομαδιαίο έλεγχο), και τα όρια λιπαρών/κορεσμένων από αυτόν. Πριν, μετά από ένα «Εφάρμοσε» 2.160 → 2.010,
    // η Κυριακή με 2.100 kcal (κάτω από τον στόχο της) γραφόταν «Πάνω από τον στόχο 90».
    final day = this.day;
    final kcalGoal = today || day == null ? g.kcal : targetOn(g, day);
    // Round9 (R9-A3-2): το όριο σε γραμμάρια ακριβές, με ένα δεκαδικό ([satLimitShown]: 2.160 kcal × 6% = «έως 14,4 g»)· πριν
    // στρογγυλευόταν στο γραμμάριο («έως 14 g») και 14,3 g σήμερα έβγαιναν «0,3 g πάνω από το όριο», ενώ είναι 5,96%.
    // Η απόφαση με τους αριθμούς όπως φαίνονται (ένα δεκαδικό, R7-A3-3).
    final satLimit = satLimitShown(kcalGoal, g.satPct);
    final fatLo = (kcalGoal * 0.25 / 9).round(), fatHi = (kcalGoal * 0.35 / 9).round(); // όπως τα Goals.fatLo/fatHi
    final left = kcalLeft(t.shownKcal, kcalGoal, today: today);
    String atLeast(String key, String text) => (t.missing[key] ?? 0) > 0 ? '≥ $text' : text;
    final protLeft = g.protein - t.protein;
    final fiberLeft = g.fiber - t.fiber;
    final satOver = oneDecimal(oneDecimal(t.satFat) - satLimit);
    // Round7 (R7-A3-4): μέρα που τελείωσε, με πλήρη καταγραφή: τα κορεσμένα ως % των θερμίδων που έφαγες, ο κανόνας της
    // σελίδας «Χοληστερίνη» και των οδηγιών (AHA/ACC 2013, ESC/EAS 2019: % της ενέργειας). Πριν η ίδια μέρα έβγαινε εδώ
    // «πάνω από το όριο» (γραμμάρια του στόχου) και εκεί κάτω από το 6%, ή ανάποδα. Για τη σημερινή μέρα, που δεν
    // τελείωσε, μένουν τα γραμμάρια του στόχου (πόσα «χωράνε» ακόμα).
    // Round9 (R9-U2-1): «πλήρης μέρα» με τον στόχο που ισχύει ΤΩΡΑ (60% του [Goals.kcal]), ο ίδιος κανόνας με τη σελίδα
    // «Χοληστερίνη» ([CholWeek]) και τη διόρθωση θερμίδων (adaptive_check.dart: adaptFullDayShare × g.kcal), όπως λέει και
    // το κείμενο «το 60% του στόχου σου». Πριν, μετά από ένα «Εφάρμοσε», η ίδια μέρα ήταν «πλήρης» στη μία οθόνη και όχι
    // στην άλλη (εντάξει εδώ, πάνω από το 6% εκεί). Οι θερμίδες και τα όρια της μέρας μένουν με τον στόχο εκείνης της
    // μέρας ([targetOn], R8-A1-5).
    final satPctDay = !today && t.kcal > 0 && t.kcal >= fullDayKcalFor(g.kcal) ? t.satFat * 9 / t.kcal * 100 : null;
    // Round8 (R8-A3-3): χωρίς οδηγία γιατρού ο κανόνας είναι του ΠΟΥ, «λιγότερο από 10%» (WHO, Healthy diet fact sheet,
    // 2020): το 10,0% δεν είναι εντάξει, και ο στόχος γράφεται «κάτω από 10%» όπως στον οδηγό. Με οδηγία γιατρού μένει
    // «έως 6%» (AHA/ACC 2013: 5–6%). Round9 (R9-A1-4 / R9-U2-5): ο ίδιος κανόνας και στη σημερινή μπάρα γραμμαρίων.
    final satStrict = satStrictPct(g.satPct);
    final satPctShown = satPctDay == null ? null : oneDecimal(satPctDay);
    final satPctOver = satPctShown != null && (satStrict ? satPctShown >= g.satPct : satPctShown > g.satPct);
    final satGramsOver = t.count > 0 && (satStrict ? satOver >= 0 : satOver > 0);
    // Round7 (R7-A3-3): κοντά στο όριο (ως 1 g) με ένα δεκαδικό, ώστε ο αριθμός να συμφωνεί με το «πάνω από το όριο»:
    // 14,3 g γράφονταν «14 g / έως 14 g» μαζί με «0,3 g πάνω από το όριο».
    final satText = t.satFat >= 10 && satOver.abs() < 1 ? dec(t.satFat, 1) : gramsText(t.satFat);
    return AppCard(
      key: const ValueKey('nutrition-goals'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Έλεγχος 13/11 (U3b-10): ο μεγάλος αριθμός παίρνει όσο πλάτος χρειάζεται και το «έφαγες / στόχος» πάει στη δεξιά
        // άκρη· με μεγάλα γράμματα κατεβαίνει από κάτω, δεν μικραίνει τον αριθμό (πριν μοιράζονταν την κάρτα μισή-μισή).
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 8,
          runSpacing: 4,
          children: [
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(left.label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: left.over ? c.warn : c.textSecondary)),
              BigValue(left.value, unit: 'kcal', size: 44, color: left.over ? c.warn : null),
            ]),
            InkWell(
              key: const ValueKey('nutrition-goals-open'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => openGoals(context, health),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('έφαγες ${thousands(t.shownKcal)}',
                      textAlign: TextAlign.right, style: TextStyle(fontSize: 13.5, color: c.textSecondary, fontFeatures: tabular)),
                  Text('στόχος ${thousands(kcalGoal)}',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.food, fontFeatures: tabular)),
                ]),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GoalBar(
          label: 'Πρωτεΐνη',
          value: '${gramsText(t.protein)} g',
          target: '${g.protein} g',
          fraction: t.protein / g.protein,
          color: proteinColor(c),
          note: t.count == 0
              ? null
              : protLeft <= 0.5
                  ? 'Έπιασες τον στόχο'
                  : (today ? 'Μένουν ${gramsText(protLeft)} g' : null),
          done: t.count > 0 && protLeft <= 0.5,
        ),
        if (satPctDay != null)
          GoalBar(
            key: const ValueKey('goals-sat-pct'),
            label: 'Κορεσμένα λιπαρά',
            value: atLeast(Nk.satFat, '${dec(satPctDay, 1)}%'),
            target: '${satStrict ? 'κάτω από' : 'έως'} ${g.satPct}% των θερμίδων',
            fraction: satPctDay / g.satPct,
            color: satPctOver ? c.warn : c.heart,
            note: !satPctOver
                ? null
                : satPctShown > g.satPct
                    ? 'Πάνω από το ${g.satPct}% των θερμίδων που έφαγες'
                    : 'Στο ${g.satPct}% των θερμίδων που έφαγες· ο στόχος είναι κάτω από ${g.satPct}%',
            warn: satPctOver,
          )
        else
          GoalBar(
            // U3a-9: ένας όρος παντού, όπως στις οθόνες φαγητού («Λιπαρά», «Κορεσμένα λιπαρά»).
            label: 'Κορεσμένα λιπαρά',
            value: atLeast(Nk.satFat, '$satText g'),
            target: satLimitText(kcalGoal, g.satPct),
            fraction: t.satFat / satLimit,
            color: satGramsOver ? c.warn : c.heart,
            note: !satGramsOver
                ? null
                : satOver > 0
                    ? '${gramsText(satOver)} g πάνω από το όριο'
                    : 'Στο όριο· ο στόχος είναι ${satLimitText(kcalGoal, g.satPct)}',
            warn: satGramsOver,
          ),
        GoalBar(
          label: 'Φυτικές ίνες',
          value: atLeast(Nk.fiber, '${gramsText(t.fiber)} g'),
          target: '${g.fiber} g',
          fraction: t.fiber / g.fiber,
          color: c.good,
          // U3b-21: ίδιο όριο με την πρωτεΐνη (0,5 g): με 29,6 g η μπάρα έγραφε «30 g / 30 g» χωρίς «Έπιασες τον στόχο».
          note: fiberLeft <= 0.5 && t.count > 0 ? 'Έπιασες τον στόχο' : null,
          done: fiberLeft <= 0.5 && t.count > 0,
        ),
        const Hairline(vertical: 12),
        // U3b-27: η μονάδα και στον στόχο, όπως στις μπάρες από πάνω.
        InfoRow('Λιπαρά', '${gramsText(t.fat)} g / $fatLo–$fatHi g'),
        // Round7 (R7-A3-3): με το αλάτι όπως φαίνεται ([saltShown]): «5,0 g» δεν είναι «κάτω από 5 g».
        InfoRow('Αλάτι', '${atLeast(Nk.salt, dec(t.salt, 1))} g / κάτω από ${dec(g.salt, 0)} g',
            valueColor: saltShown(t.salt) >= g.salt ? c.warn : null),
        InfoRow('Υδατάνθρακες', '${gramsText(t.carbs)} g'),
        InfoRow('Σάκχαρα', '${atLeast(Nk.sugars, gramsText(t.sugars))} g'),
        if (t.alcohol >= 0.05) InfoRow('Αλκοόλ', '${gramsText(t.alcohol)} g'),
        if (t.missing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('«≥»: κάποια τρόφιμα δεν έχουν τιμή στην πηγή τους.', style: TextStyle(fontSize: 12.5, color: c.textTertiary)),
          ),
      ]),
    );
  }
}

/// Μπάρα «τιμή / στόχος» με σημείωση από κάτω.
class GoalBar extends StatelessWidget {
  const GoalBar({
    super.key,
    required this.label,
    required this.value,
    required this.target,
    required this.fraction,
    required this.color,
    this.note,
    this.warn = false,
    this.done = false,
  });
  final String label, value, target;
  final double fraction;
  final Color color;
  final String? note;
  final bool warn;

  /// Ο στόχος πιάστηκε: μπροστά από τη σημείωση μπαίνει το εικονίδιο «έγινε» (έλεγχος 13/11, U3b-32: το «✓» δεν υπάρχει
  /// στη γραμματοσειρά της εφαρμογής και στην οθόνη έβγαινε από άλλη ή καθόλου).
  final bool done;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final f = fraction.isFinite ? fraction.clamp(0.0, 1.0) : 0.0;
    final labelStyle = TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: c.text);
    const valueStyle = TextStyle(fontSize: 14.5, fontFeatures: tabular);
    final valueSpan = TextSpan(children: [
      TextSpan(text: value, style: TextStyle(fontWeight: FontWeight.w700, color: warn ? c.warn : c.text)),
      TextSpan(text: ' / $target', style: TextStyle(color: c.textSecondary)),
    ]);
    // Round9 (R9-U2-6): «στόχος …» για το TalkBack· πριν διάβαζε «13 g από έως 14 g».
    return Semantics(
      label: '$label: $value, στόχος $target${note == null ? '' : '. $note'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Round8 (R8-U2-4): η τιμή πάντα στη δεξιά άκρη. Αν ετικέτα και τιμή δεν χωρούν σε μία γραμμή, η τιμή πάει από
          // κάτω, δεξιά· πριν (Wrap με spaceBetween) έπεφτε αριστερά, κάτω από την ετικέτα (π.χ. «7,2% / έως 6% των
          // θερμίδων» μιας μέρας που τελείωσε, ή «13 g / έως 14 g» στα 360 dp με μεγάλα γράμματα).
          LayoutBuilder(builder: (context, box) {
            final scaler = MediaQuery.textScalerOf(context);
            final base = DefaultTextStyle.of(context).style;
            double width(InlineSpan span) {
              final tp = TextPainter(text: span, textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)..layout();
              final w = tp.width;
              tp.dispose();
              return w;
            }

            final labelText = Text(label, style: labelStyle);
            final valueText = Text.rich(valueSpan, style: valueStyle, textAlign: TextAlign.right);
            final oneLine = width(TextSpan(text: label, style: base.merge(labelStyle))) +
                    8 +
                    width(TextSpan(style: base.merge(valueStyle), children: [valueSpan])) <=
                box.maxWidth;
            if (oneLine) {
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: labelText),
                const SizedBox(width: 8),
                valueText,
              ]);
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              labelText,
              Align(alignment: Alignment.centerRight, child: valueText),
            ]);
          }),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 8,
              child: Stack(fit: StackFit.expand, children: [
                ColoredBox(color: c.hairline),
                FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: f, child: ColoredBox(color: color)),
              ]),
            ),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                if (done) ...[Icon(Icons.check_circle_rounded, size: 16, color: c.good), const SizedBox(width: 4)],
                Expanded(
                  child: Text(note!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: warn ? c.warn : c.textSecondary)),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Χωρίς στόχους: πρόσκληση στον οδηγό.
class GoalsCtaCard extends StatelessWidget {
  const GoalsCtaCard({super.key, required this.health});
  final HealthStore health;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return EmptyCard(
      key: const ValueKey('nutrition-goals-cta'),
      icon: Icons.flag_rounded,
      color: c.food,
      title: 'Βάλε στόχους διατροφής',
      text: 'Θερμίδες, πρωτεΐνη, κορεσμένα και ίνες για σένα, σε 2 λεπτά.',
      buttonText: 'Ο οδηγός',
      onPressed: () => openGoals(context, health),
    );
  }
}

// ---------------------------------------------------------------------------------------------------- χοληστερίνη

const cholInfo = MetricInfo(
  title: 'Χοληστερίνη · τι τη ρίχνει',
  // Έλεγχος 13/11 (S1-12): το ψάρι δεν είναι τρόφιμο που ρίχνει την LDL (η διατροφή «portfolio» του Jenkins 2003 ήταν
  // φυτική)· μετριέται γιατί είναι στο πλάνο, στη θέση του κρέατος και για τα τριγλυκερίδια.
  // Round 1 (αίτημα f2 → f1, S2-1 / S2-3): οι δύο αλλαγές του κανόνα (chol.dart) λέγονται κι εδώ: οι σπόροι δεν μετρούν
  // ως ξηροί καρποί (το κουκουνάρι μετρά), και τα δικά σου προϊόντα μετρούν όταν πεις τι είναι.
  // Round7 (R7-A3-8): «βοηθά τα τριγλυκερίδια» έφυγε: κατά τις οδηγίες ESC/EAS 2019 (§7) το ψάρι στη διατροφή δεν αλλάζει
  // ουσιαστικά τα λιπίδια· τα τριγλυκερίδια τα ρίχνουν κυρίως λιγότερο αλκοόλ και ζάχαρη και το χάσιμο βάρους.
  // Round7 (R7-A3-7): η διατροφή «portfolio» έχει και φυτικές στερόλες και σόγια (Jenkins 2003)· το λέμε, αφού δεν τις μετράμε.
  // Round8 (R8-A3-4): τα τριγλυκερίδια με τη σειρά του πίνακα 7 των ESC/EAS 2019 (Mach 2020, Eur Heart J 41:111): λιγότερο
  // αλκοόλ +++ (>10%)· τακτική άσκηση, λιγότεροι υδατάνθρακες, λιγότερα σάκχαρα ++ (5–10%)· χάσιμο βάρους + (<5%). Πριν
  // το χάσιμο βάρους ήταν στα «κυρίως» και η άσκηση έλειπε.
  what: 'Μετρά τα τρόφιμα που έφαγες και ρίχνουν την LDL («κακή» χοληστερίνη): ξηρούς καρπούς, πίτουρο βρώμης, όσπρια. '
      'Η διατροφή «portfolio» έχει και φυτικές στερόλες και σόγια· η εφαρμογή δεν τις μετρά. '
      'Μετρά και το ψάρι: μπαίνει στη θέση του κρέατος (λιγότερα κορεσμένα) και το προτείνουν οι οδηγίες για την καρδιά· '
      'το ίδιο δεν ρίχνει την LDL. Τα τριγλυκερίδια τα ρίχνουν κυρίως λιγότερο αλκοόλ, η τακτική άσκηση και λιγότεροι '
      'υδατάνθρακες (ιδίως ζάχαρη)· βοηθά και το χάσιμο βάρους (ESC/EAS 2019). '
      'Ως ξηροί καρποί μετρούν οι καρποί, π.χ. καρύδια, αμύγδαλα, φιστίκια και κουκουνάρι· οι σπόροι (ηλιόσποροι, '
      'κολοκυθόσποροι) δεν μετρούν. Τα δικά σου προϊόντα μετρούν όταν στη φόρμα τους διαλέξεις τι είναι («Στην κάρτα '
      '«Χοληστερίνη» μετρά ως»).',
  shows: 'Αν κάνεις όσα συμφώνησες: λιγότερα κορεσμένα λιπαρά, περισσότερες φυτικές ίνες, ξηροί καρποί και πίτουρο βρώμης '
      'κάθε μέρα, όσπρια και ψάρι μέσα στην εβδομάδα. Η εφαρμογή δεν προβλέπει τη νέα σου LDL· αυτό το λένε μόνο οι '
      'εξετάσεις.',
  compare: 'Κορεσμένα λιπαρά έως 6% των θερμίδων (AHA/ACC) · φυτικές ίνες 30 g (Reynolds 2019) · 3 g β\u2011γλυκάνες βρώμης τη μέρα '
      '(EFSA) · ξηροί καρποί περίπου 30 g (Del Gobbo 2015) · όσπρια ως φυτική πρωτεΐνη (διατροφή «portfolio», '
      'Chiavaroli 2018).',
  // Τελικός έλεγχος, Συμβούλιο 2 (Α4): ίδιος κανόνας «πλήρους μέρας» με τη διόρθωση θερμίδων, και το αλάτι που λείπει.
  accuracy: 'Οι μέρες με λίγη καταγραφή (κάτω από το 60% του στόχου θερμίδων) δεν μπαίνουν στους μέσους όρους. Αν ένα '
      'τρόφιμο δεν έχει τιμή για κορεσμένα λιπαρά ή ίνες στην πηγή του, το σύνολο είναι «τουλάχιστον» και γράφεται με «≥». '
      'Μέρα με τρόφιμο χωρίς τιμή αλατιού δεν μετρά ως «αλάτι εντάξει». Το αλάτι μετρά μόνο ό,τι γράφεις: γράψε και το '
      'αλάτι που βάζεις στο μαγείρεμα και στο πιάτο (τρόφιμο «Αλάτι»).',
  cite: 'Eckel 2013 (AHA/ACC) · EFSA 2010/2011 · Reynolds 2019 (Lancet) · Del Gobbo 2015 (AJCN) · Jenkins 2003 και 2011 '
      '(JAMA) · Chiavaroli 2018 (Prog Cardiovasc Dis) · ESC/EAS 2019',
);

List<(DateTime, CholDay)> _daysOf(FoodStore food, DateTime from, DateTime toExclusive) => [
      for (var d = from; d.isBefore(toExclusive); d = DateTime(d.year, d.month, d.day + 1)) (d, CholDay(food.entriesFor(d))),
    ];

/// Κάρτα «Χοληστερίνη» στη Διατροφή (μόνο όταν ο γιατρός ζήτησε να πέσει η LDL): η μέρα που βλέπεις και η εβδομάδα της.
class CholCard extends StatelessWidget {
  const CholCard({super.key, required this.food, required this.goals, required this.day, required this.today});
  final FoodStore food;
  final Goals goals;
  final DateTime day;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final g = goals;
    final d = CholDay(food.entriesFor(day));
    final ws = weekStart(day);
    final week = _daysOf(food, ws, DateTime(day.year, day.month, day.day + 1));
    final legumes = week.where((x) => x.$2.legumes).length;
    final fish = week.where((x) => x.$2.fish).length;
    // Round7 (R7-A3-6): σε άλλη μέρα από τη σημερινή λέει ποιες μέρες μετρά (από τη Δευτέρα ως εκείνη τη μέρα), όχι «αυτή την
    // εβδομάδα» (πριν, στην Τετ 18/11 βλέποντας από την Πέμ 26/11, μετρούσε 16–18/11 και έγραφε «αυτή την εβδομάδα»).
    final weekText = sameDay(day, today)
        ? 'αυτή την εβδομάδα'
        : sameDay(ws, day)
            ? 'Δευτέρα ${dayMonth(day)}'
            : 'από ${dayMonth(ws)} ως ${dayMonth(day)}';
    // Round9 (R9-U2-6): για το TalkBack ολόκληρος ο μήνας («16 Νοεμβρίου»· το «Νοε» διαβάζεται ως συντομογραφία, R7-U4-8).
    final weekSpoken = sameDay(day, today)
        ? null
        : sameDay(ws, day)
            ? 'Δευτέρα ${dayMonthLong(day)}'
            : 'από ${dayMonthLong(ws)} ως ${dayMonthLong(day)}';
    return AppCard(
      key: const ValueKey('nutrition-chol'),
      onTap: () => Navigator.of(context).push(CholesterolPage.route(food, g, today)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardHeader(
          icon: Icons.favorite_rounded,
          // Round7 (R7-U2-15): το «τι τη ρίχνει» πάει ολόκληρο στην επόμενη γραμμή (πριν έσπαγε «τι | τη ρίχνει»).
          title: 'Χοληστερίνη · τι\u00A0τη\u00A0ρίχνει',
          color: c.heart,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            const InfoDot(cholInfo),
            Icon(Icons.chevron_right_rounded, color: c.textTertiary),
          ]),
        ),
        const SizedBox(height: 6),
        // «Έγινε» με τον αριθμό όπως φαίνεται (U3b-21): 29,6 g γράφονται «30 g / 30 g», άρα και με το σημάδι. Ο ίδιος κανόνας
        // και στη σελίδα «Χοληστερίνη» ([reachedGrams], R7-A3-2).
        if (g.nutsG > 0)
          CholRow(label: 'Ξηροί καρποί', value: '${d.nutsG.round()} g', target: '${g.nutsG} g', done: reachedGrams(d.nutsG, g.nutsG)),
        if (g.branG > 0)
          CholRow(label: 'Πίτουρο βρώμης', value: '${d.branG.round()} g', target: '${g.branG} g', done: reachedGrams(d.branG, g.branG)),
        if (g.legumesWeek > 0)
          CholRow(
              label: 'Όσπρια',
              sub: weekText,
              subSemantics: weekSpoken,
              value: '$legumes',
              target: '${g.legumesWeek}',
              done: legumes >= g.legumesWeek),
        if (g.fishWeek > 0)
          CholRow(
              label: 'Ψάρι', sub: weekText, subSemantics: weekSpoken, value: '$fish', target: '${g.fishWeek}', done: fish >= g.fishWeek),
      ]),
    );
  }
}

class CholRow extends StatelessWidget {
  const CholRow(
      {super.key, required this.label, required this.value, required this.target, required this.done, this.sub, this.subSemantics});
  final String label, value, target;
  final String? sub;

  /// Το [sub] όπως το διαβάζει το TalkBack, όταν διαφέρει από το γραμμένο (ολόκληρος ο μήνας· round9, R9-U2-6).
  final String? subSemantics;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final spoken = subSemantics ?? sub;
    return Semantics(
      label: '$label${spoken == null ? '' : ', $spoken'}: $value${target.isEmpty ? '' : ' από $target'}${done ? ', έγινε' : ''}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        // Έλεγχος 13/11 (U3b-9): η τιμή σε δικό της χώρο ως τη δεξιά άκρη της κάρτας (πριν ξεκινούσε από τη μέση και
        // άφηνε κενό δεξιά, ενώ η ετικέτα έσπαγε σε δύο γραμμές)· η ετικέτα παίρνει τα 3/5.
        child: Row(children: [
          Expanded(
            flex: 3,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
              if (sub != null) Text(sub!, style: TextStyle(fontSize: 12.5, color: c.textTertiary)),
            ]),
          ),
          Expanded(
            flex: 2,
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (done) Padding(padding: const EdgeInsets.only(right: 6), child: Icon(Icons.check_circle_rounded, size: 20, color: c.good)),
              Flexible(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: value, style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
                    if (target.isNotEmpty) TextSpan(text: ' / $target', style: TextStyle(color: c.textSecondary)),
                  ]),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 14.5, fontFeatures: tabular),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Σελίδα «Χοληστερίνη» (σχέδια 12/11, 3β): οι μέρες της εβδομάδας που ΕΧΟΥΝ τελειώσει, ή 4 εβδομάδες.
class CholesterolPage extends StatefulWidget {
  const CholesterolPage({super.key, required this.food, required this.goals, required this.today});
  final FoodStore food;
  final Goals goals;
  final DateTime today;

  static Route<void> route(FoodStore food, Goals goals, DateTime today) => MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'Χοληστερίνη'), builder: (_) => CholesterolPage(food: food, goals: goals, today: today));

  @override
  State<CholesterolPage> createState() => _CholesterolPageState();
}

class _CholesterolPageState extends State<CholesterolPage> {
  bool _four = false;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final g = widget.goals;
    final today = dayOf(widget.today);
    final ws = weekStart(today);
    // Μόνο οι μέρες που έχουν τελειώσει (σήμερα όχι).
    final thisWeek = CholWeek(_daysOf(widget.food, ws, today), goalKcal: g.kcal);
    final weeks = [
      for (var k = 3; k >= 0; k--)
        () {
          final from = DateTime(ws.year, ws.month, ws.day - 7 * k);
          final to = k == 0 ? today : DateTime(from.year, from.month, from.day + 7);
          return (from, CholWeek(_daysOf(widget.food, from, to), goalKcal: g.kcal));
        }(),
    ];
    // Round7 (R7-A3-5): ο μέσος όρος των 4 εβδομάδων από ΟΛΕΣ τις μέρες με πλήρη καταγραφή, όχι μέσος όρος των εβδομαδιαίων
    // μέσων (η τρέχουσα εβδομάδα με μία μέρα μετρούσε όσο μια γεμάτη: 1 μέρα στο 12% + 21 στο 5% έβγαιναν «6,8%», ενώ οι
    // 22 μέρες έχουν 5,3%). Οι μπάρες μένουν μία ανά εβδομάδα.
    final four = CholWeek([for (final x in weeks) ...x.$2.days], goalKcal: g.kcal);
    const dayLabels = ['Δε', 'Τρ', 'Τε', 'Πε', 'Πα', 'Σα', 'Κυ'];
    // Round9 (R9-U2-6): για το TalkBack ολόκληρες λέξεις («Δευτέρα 16 Νοεμβρίου», «εβδομάδα από 2 Νοεμβρίου»).
    final daySpoken = [for (var k = 0; k < 7; k++) longDate(DateTime(ws.year, ws.month, ws.day + k))];
    final weekSpoken = [for (final x in weeks) 'εβδομάδα από ${dayMonthLong(x.$1)}'];
    List<double?> perDay(double? Function(CholDay) f) => [
          for (var k = 0; k < 7; k++)
            () {
              final hit = thisWeek.days.where((x) => x.$1.weekday == k + 1 && x.$2.fullFor(g.kcal));
              return hit.isEmpty ? null : f(hit.first.$2);
            }(),
        ];
    final w = thisWeek;
    final small = TextStyle(fontSize: 13, height: 1.45, color: c.textSecondary);
    // Έλεγχος 13/11 (U3b-8): όσπρια και ψάρι μετρούν ΜΑΖΙ με σήμερα, όπως στην κάρτα της Διατροφής (ένα γεύμα που έγινε
    // έχει γίνει)· πριν η κάρτα έγραφε «3 / 4» και αυτή η σελίδα «2 / 4» την ίδια στιγμή. Οι μέσοι όροι μένουν χωρίς σήμερα.
    final weekNow = _daysOf(widget.food, ws, DateTime(today.year, today.month, today.day + 1));
    final legumesNow = weekNow.where((x) => x.$2.legumes).length;
    final fishNow = weekNow.where((x) => x.$2.fish).length;
    // Έλεγχος 13/11 (S2-2): τρόφιμο χωρίς τιμή κορεσμένων λιπαρών (ή ινών) στην πηγή του μετρά 0 g· τότε ο αριθμός είναι
    // «τουλάχιστον» και γράφεται με «≥», όπως υπόσχεται το ⓘ και όπως κάνει ήδη η κάρτα της μέρας.
    // Οι μετρητές είναι του chol.dart ([CholWeek.daysSatUnknown], [CholWeek.daysFiberUnknown]: μέρες με πλήρη καταγραφή).
    final satUnknown = _four ? four.daysSatUnknown : w.daysSatUnknown;
    final fiberUnknown = _four ? four.daysFiberUnknown : w.daysFiberUnknown;
    List<bool> dayFlags(bool Function(CholDay) missing) => [
          for (var k = 0; k < 7; k++) thisWeek.days.any((x) => x.$1.weekday == k + 1 && x.$2.fullFor(g.kcal) && missing(x.$2)),
        ];
    String daysOf(int n) => w.fullDays == 0 ? '—' : '$n από ${countText(w.fullDays, 'μέρα', 'μέρες')}';
    // U3b-12: το χρώμα της διατροφής και στον διακόπτη «Αυτή η εβδομάδα / 4 εβδομάδες» (πριν το χρώμα του βάρους).
    return FoodTheme(
        child: Scaffold(
      appBar: AppBar(title: const Text('Χοληστερίνη')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
              Text(longDate(today), style: small),
              const SizedBox(height: 6),
              Text('Η εφαρμογή δεν προβλέπει τη νέα σου LDL· δείχνει μόνο αν κάνεις όσα τη ρίχνουν. Τις τιμές τις λένε οι '
                  'εξετάσεις και ο γιατρός σου.', style: small),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                key: const ValueKey('chol-range'),
                segments: const [
                  ButtonSegment(value: false, label: Text('Αυτή η εβδομάδα')),
                  ButtonSegment(value: true, label: Text('4 εβδομάδες')),
                ],
                selected: {_four},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _four = s.first),
              ),
              const SizedBox(height: 12),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  CardHeader(
                      icon: Icons.bar_chart_rounded, title: 'Κορεσμένα λιπαρά, % των θερμίδων', color: c.heart, trailing: const InfoDot(cholInfo)),
                  const SizedBox(height: 4),
                  Text(
                      _meanText(_four ? four.satPctMean : w.satPctMean, '%', 'έως ${g.satPct}%',
                          atLeast: satUnknown > 0),
                      style: small),
                  if (satUnknown > 0)
                    Text(
                        '${countText(satUnknown, 'μέρα', 'μέρες')} με τρόφιμο χωρίς τιμή κορεσμένων λιπαρών: το πραγματικό ποσοστό '
                        'είναι ίσο ή μεγαλύτερο («≥»).',
                        key: const ValueKey('chol-sat-unknown'),
                        style: small.copyWith(color: c.warn)),
                  const SizedBox(height: 10),
                  _four
                      ? MiniBars(
                          values: [for (final x in weeks) x.$2.satPctMean],
                          labels: [for (final x in weeks) dayMonth(x.$1)],
                          semanticLabels: weekSpoken,
                          semanticUnit: ' τοις εκατό',
                          target: g.satPct.toDouble(),
                          color: c.heart,
                          over: c.warn,
                          higherIsWorse: true,
                          format: (v) => dec(v),
                          shownValue: oneDecimal,
                          atLeast: [for (final x in weeks) x.$2.daysSatUnknown > 0],
                        )
                      : MiniBars(
                          values: perDay((d) => d.satPct),
                          labels: dayLabels,
                          semanticLabels: daySpoken,
                          semanticUnit: ' τοις εκατό',
                          target: g.satPct.toDouble(),
                          color: c.heart,
                          over: c.warn,
                          higherIsWorse: true,
                          format: (v) => dec(v),
                          shownValue: oneDecimal,
                          atLeast: dayFlags((d) => d.satMissing),
                        ),
                ]),
              ),
              const SizedBox(height: 12),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  CardHeader(icon: Icons.grass_rounded, title: 'Φυτικές ίνες, g', color: c.good),
                  const SizedBox(height: 4),
                  Text(
                      _meanText(_four ? four.fiberMean : w.fiberMean, ' g', '${g.fiber} g',
                          digits: 0, atLeast: fiberUnknown > 0),
                      style: small),
                  if (fiberUnknown > 0)
                    Text(
                        '${countText(fiberUnknown, 'μέρα', 'μέρες')} με τρόφιμο χωρίς τιμή φυτικών ινών: οι πραγματικές είναι ίσες ή '
                        'περισσότερες («≥»).',
                        key: const ValueKey('chol-fiber-unknown'),
                        style: small),
                  const SizedBox(height: 10),
                  _four
                      ? MiniBars(
                          values: [for (final x in weeks) x.$2.fiberMean],
                          labels: [for (final x in weeks) dayMonth(x.$1)],
                          semanticLabels: weekSpoken,
                          semanticUnit: ' γραμμάρια',
                          target: g.fiber.toDouble(),
                          color: c.good,
                          format: (v) => v.round().toString(),
                          atLeast: [for (final x in weeks) x.$2.daysFiberUnknown > 0],
                        )
                      : MiniBars(
                          values: perDay((d) => d.fiber),
                          labels: dayLabels,
                          semanticLabels: daySpoken,
                          semanticUnit: ' γραμμάρια',
                          target: g.fiber.toDouble(),
                          color: c.good,
                          format: (v) => v.round().toString(),
                          atLeast: dayFlags((d) => d.fiberMissing),
                        ),
                ]),
              ),
              const SizedBox(height: 12),
              if (!_four)
                AppCard(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (g.nutsG > 0)
                      CholRow(
                          label: 'Ξηροί καρποί',
                          sub: 'μέρες με ${g.nutsG} g',
                          value: daysOf(w.daysWithNuts(g.nutsG)),
                          target: '',
                          done: w.fullDays > 0 && w.daysWithNuts(g.nutsG) == w.fullDays),
                    if (g.branG > 0)
                      CholRow(
                          label: 'Πίτουρο βρώμης',
                          sub: 'μέρες με ${g.branG} g',
                          value: daysOf(w.daysWithBran(g.branG)),
                          target: '',
                          done: w.fullDays > 0 && w.daysWithBran(g.branG) == w.fullDays),
                    if (g.legumesWeek > 0)
                      CholRow(
                          label: 'Όσπρια',
                          sub: 'μαζί με σήμερα',
                          value: '$legumesNow',
                          target: countText(g.legumesWeek, 'φορά', 'φορές'),
                          done: legumesNow >= g.legumesWeek),
                    if (g.fishWeek > 0)
                      CholRow(
                          label: 'Ψάρι',
                          sub: 'μαζί με σήμερα',
                          value: '$fishNow',
                          target: countText(g.fishWeek, 'φορά', 'φορές'),
                          done: fishNow >= g.fishWeek),
                    CholRow(
                        label: 'Αλάτι κάτω από ${dec(g.salt, 0)} g',
                        // Συμβούλιο 2, Α4: μέρα με τρόφιμο χωρίς τιμή αλατιού δεν μετρά ως «εντάξει»· η γραμμή το λέει.
                        sub: w.daysSaltUnknown == 0
                            ? null
                            : w.daysSaltUnknown == 1
                                ? '1 μέρα με τρόφιμο χωρίς τιμή αλατιού'
                                : '${w.daysSaltUnknown} μέρες με τρόφιμο χωρίς τιμή αλατιού',
                        value: daysOf(w.daysSaltOk(g.salt)),
                        target: '',
                        done: w.fullDays > 0 && w.daysSaltOk(g.salt) == w.fullDays),
                  ]),
                ),
              const SizedBox(height: 10),
              Text(
                'Μέρες με λίγη καταγραφή (κάτω από ${thousands(fullDayKcalFor(g.kcal).round())} kcal, το 60% του στόχου σου) δεν '
                'μετρούν στους μέσους όρους. Στους μέσους όρους και στις μέρες, σήμερα δεν μετρά μέχρι να τελειώσει η μέρα· τα '
                // Round7 (R7-A3-9): μία φορά ΤΗ ΜΕΡΑ, όσα κι αν φας (chol.dart, CholDay.legumes / fish).
                'όσπρια και το ψάρι μετρούν και σήμερα. Όσπρια: μετρά μία φορά κάθε μέρα με τουλάχιστον 40 g ξερά ή 100 g '
                'βρασμένα· ψάρι: μία φορά κάθε μέρα με τουλάχιστον 100 g.',
                style: small,
              ),
            ]),
          ),
        ),
      ),
    ));
  }

  static String _meanText(double? v, String unit, String target, {int digits = 1, bool atLeast = false}) => v == null
      ? 'Δεν υπάρχει ακόμα ολοκληρωμένη μέρα · στόχος $target'
      : 'μέσος όρος ${atLeast ? '≥ ' : ''}${dec(v, digits)}$unit · στόχος $target';
}

/// Μικρές μπάρες με γραμμή στόχου. null: μέρα χωρίς αρκετή καταγραφή (κενή).
class MiniBars extends StatelessWidget {
  const MiniBars({
    super.key,
    required this.values,
    required this.labels,
    required this.target,
    required this.color,
    required this.format,
    this.over,
    this.higherIsWorse = false,
    this.atLeast,
    this.shownValue,
    this.semanticLabels,
    this.semanticUnit = '',
  });
  final List<double?> values;
  final List<String> labels;

  /// Round9 (R9-U2-6): οι [labels] όπως τις διαβάζει το TalkBack («Δευτέρα 16 Νοεμβρίου» αντί για «Δε»), και η μονάδα
  /// μετά από κάθε τιμή («τοις εκατό», «γραμμάρια»). Πριν διάβαζε «Δε: 10,2, Τρ: 7,1…», και το «πάνω από τον στόχο»
  /// φαινόταν μόνο με το χρώμα.
  final List<String>? semanticLabels;
  final String semanticUnit;

  /// Η τιμή όπως τη γράφει η ετικέτα της μπάρας ([format]), για το χρώμα «πάνω από τον στόχο» (round7, R7-A3-3): 6,03%
  /// γράφεται «6,0» και δεν είναι πάνω από το 6%. null = η ακριβής τιμή.
  final double Function(double)? shownValue;

  /// Ποιες μπάρες είναι «τουλάχιστον» (κάποιο τρόφιμο χωρίς τιμή στην πηγή του): η ετικέτα τους γράφεται με «≥» (S2-2).
  final List<bool>? atLeast;
  final double target;
  final Color color;
  final Color? over;
  final bool higherIsWorse;
  final String Function(double) format;

  static const _h = 96.0;

  bool _beyond(double v) => higherIsWorse ? v > target + 1e-9 : v < target - 1e-9;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final top = math.max(target * 1.35, values.whereType<double>().fold<double>(0, math.max));
    double y(double v) => top <= 0 ? 0 : (v / top * _h).clamp(0, _h);
    String spoken(int k) {
      final v = values[k];
      final name = semanticLabels != null && k < semanticLabels!.length ? semanticLabels![k] : labels[k];
      if (v == null) return '$name: χωρίς';
      final least = atLeast != null && k < atLeast!.length && atLeast![k] ? 'τουλάχιστον ' : '';
      final beyond = over != null && _beyond(shownValue?.call(v) ?? v)
          ? (higherIsWorse ? ', πάνω από τον στόχο' : ', κάτω από τον στόχο')
          : '';
      return '$name: $least${format(v)}$semanticUnit$beyond';
    }

    return Semantics(
      label: [for (var k = 0; k < values.length; k++) spoken(k)].join('; '),
      excludeSemantics: true,
      child: Column(children: [
        SizedBox(
          height: _h + 26,
          child: Stack(children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: y(target),
              child: Container(height: 1.5, color: c.textTertiary.withValues(alpha: 0.6)),
            ),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final (k, v) in values.indexed)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      if (v != null)
                        // Με φόντο στο χρώμα της κάρτας (U3b-11): η γραμμή του στόχου περνούσε μέσα από τα ψηφία, ακριβώς
                        // στις μέρες «σχεδόν στον στόχο».
                        DecoratedBox(
                          decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(3)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Text('${atLeast != null && k < atLeast!.length && atLeast![k] ? '≥' : ''}${format(v)}',
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.textSecondary, fontFeatures: tabular)),
                          ),
                        ),
                      const SizedBox(height: 2),
                      // Με μεγάλα γράμματα η ετικέτα ψηλώνει: η μπάρα μικραίνει, δεν ξεχειλίζει.
                      Flexible(
                        child: Container(
                          height: v == null ? 0 : math.max(2, y(v)),
                          decoration: BoxDecoration(
                            color: v != null && over != null && _beyond(shownValue?.call(v) ?? v) ? over : color,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
            ]),
          ]),
        ),
        const SizedBox(height: 4),
        Row(children: [
          for (final l in labels)
            Expanded(child: Text(l, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.textTertiary))),
        ]),
      ]),
    );
  }
}
