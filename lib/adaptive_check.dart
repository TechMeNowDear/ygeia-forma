/// Ο εβδομαδιαίος έλεγχος θερμίδων στην πράξη (σχέδια A1–A4, εγκρίθηκαν 12/11): από τα δεδομένα της εφαρμογής (φαγητό,
/// ζυγίσεις InBody) στην κάρτα της Σήμερα και πίσω στους στόχους. Οι κανόνες είναι στο [adaptive.dart]· εδώ μόνο τι
/// δείχνεται, πότε, και τι αλλάζει όταν απαντάς. Τίποτα δεν αλλάζει μόνο του: πάντα με το δικό σου «Εφάρμοσε».
library;

import 'adaptive.dart';
import 'body_trend.dart' show weighInDays;
import 'data.dart' show BodyMeasurement;
import 'food/food_model.dart' show DayMark, Totals;
import 'food/food_store.dart';
import 'history.dart' show dateKey;
import 'format.dart' show daysBetween;
import 'goals.dart';
import 'weight_guard.dart';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Μία ζύγιση ανά μέρα, χωρισμένες σε όσες μετρούν ([used]) και όσες δεν μπορεί να είναι δικές σου ([foreign]: έλεγχος
/// 13/11, S11-2, κανόνας στο weight_guard.dart). Και οι δύο παλιότερη πρώτη. [body] είναι ήδη μόνο της InBody.
/// - Μετρά η πρώτη ζύγιση της μέρας (η πρωινή, όπως λέει η κάρτα «Σήμερα ζύγιση»).
/// - Κάθε μέρα κρίνεται με τις πρώτες ζυγίσεις των άλλων ημερών ως [weightGuardDays] μέρες πριν ή μετά. Αν η πρώτη της
///   μοιάζει ξένη (π.χ. ζυγίστηκε πρώτα το παιδί) και υπάρχει επόμενη της ίδιας μέρας που μετρά, μετρά εκείνη.
///   Αν δεν μετρά καμία, η μέρα πάει στο [foreign] με τη ζύγιση της μέρας ([weighInDays]). Τίποτα δεν σβήνεται: απλώς δεν μετρά.
/// - Round 2 (g4 · R2-E-2, κανόνας [guardDays]): «ξένη» μόνο όταν οι ζυγίσεις πριν ΚΑΙ μετά συμφωνούν μεταξύ τους και όχι
///   μαζί της. Μια ζύγιση που διαφέρει πολύ αλλά δεν έχει ακόμα επόμενη (π.χ. η πρώτη μετά από αρρώστια με −5 kg) είναι «σε
///   αναμονή»: δεν μπαίνει ΟΥΤΕ στο [used] (ο έλεγχος θερμίδων την περιμένει) ΟΥΤΕ στο [foreign] (η κάρτα δεν τη λέει
///   ξένη)· μετρά μόλις συμφωνήσει μαζί της η επόμενη ζύγιση.
/// - Round 3 (k1 · R3-C-1): η ζύγιση κάθε μέρας από τον ΙΔΙΟ υπολογισμό με το ιστορικό, το Σώμα, τη Σήμερα και το widget
///   ([weighInDays], body_trend.dart). Round 3 (k1 · R3-A-1): «μετρά» θέλει πια ζυγίσεις 3 ημερών σε ≥ 4 μέρες όταν το βάρος
///   άλλαξε απότομα (επισκέπτης Σάββατο και Κυριακή: «σε αναμονή», όχι στο [used]).
({List<(DateTime, double)> used, List<(DateTime, double)> foreign}) guardedWeights(Iterable<BodyMeasurement> body) {
  final used = <(DateTime, double)>[];
  final foreign = <(DateTime, double)>[];
  for (final g in weighInDays(body.toList())) {
    final w = g.pick.weight;
    // Μέρα μόνο με ζυγίσεις χωρίς βάρος: δεν κρίνεται, δεν μπαίνει.
    if (w == null || !w.isFinite) continue;
    if (g.status == WeighStatus.counted) {
      used.add((g.day, w));
    } else if (g.status == WeighStatus.foreign) {
      foreign.add((g.day, w));
    }
  }
  return (used: used, foreign: foreign);
}

/// Μία ζύγιση ανά μέρα, μόνο όσες μετρούν ([guardedWeights]), παλιότερη πρώτη.
List<(DateTime, double)> dailyWeights(Iterable<BodyMeasurement> body) => guardedWeights(body).used;

/// Θερμίδες ανά μέρα όπως φαίνονται στη Διατροφή, από [from] ως [to] (και τα δύο μέσα). Μέρες χωρίς καταχώριση
/// δεν μπαίνουν καθόλου.
Map<DateTime, double> dailyIntake(FoodStore food, DateTime from, DateTime to) {
  final out = <DateTime, double>{};
  for (var d = _day(from); !d.isAfter(_day(to)); d = DateTime(d.year, d.month, d.day + 1)) {
    // «Τελείωσα για σήμερα» (16/11): μέρα που είπες ότι λείπουν γεύματα δεν μετρά (όπως μια μέρα χωρίς καταγραφή).
    if (food.dayMark(d) == DayMark.part) continue;
    final entries = food.entriesFor(d);
    if (entries.isNotEmpty) out[d] = Totals(entries).kcal;
  }
  return out;
}

/// «Εκτίμηση» (16/11): τι μέρος των θερμίδων των ημερών που μετρούν ([dailyIntake]) γράφτηκε χωρίς ζύγιση (0–1).
/// null χωρίς θερμίδες. [minKcal]/[maxKcal]: οι ίδιες μέρες με την εκτίμηση της κατανάλωσης (από το 60% του στόχου
/// ως το [absurdDayKcal]· έλεγχος 16/11: πριν μετρούσαν και μέρες που η εκτίμηση δεν χρησιμοποιεί).
double? estimatedShare(FoodStore food, DateTime from, DateTime to, {double? minKcal, double? maxKcal}) {
  var all = 0.0, est = 0.0;
  for (var d = _day(from); !d.isAfter(_day(to)); d = DateTime(d.year, d.month, d.day + 1)) {
    if (food.dayMark(d) == DayMark.part) continue;
    final t = Totals(food.entriesFor(d));
    if (minKcal != null && t.kcal < minKcal) continue;
    if (maxKcal != null && t.kcal > maxKcal) continue;
    all += t.kcal;
    est += t.estKcal;
  }
  return all > 0 ? est / all : null;
}

/// Από πόσο και πάνω το λέει η κάρτα ελέγχου (λίγες εκτιμήσεις δεν αλλάζουν τίποτα).
const estimatedShareNote = 0.15;

/// «Το 32% των θερμίδων … ήταν εκτίμηση …» ή null κάτω από [estimatedShareNote].
String? estimatedShareText(double? share) {
  if (share == null || share < estimatedShareNote) return null;
  return 'Το ${(share * 100).round()}% των θερμίδων αυτών των ημερών γράφτηκε χωρίς ζύγιση (εκτίμηση): ο έλεγχος είναι '
      'λιγότερο ακριβής. Όσο πιο πολλά ζυγίζεις, τόσο πιο σωστός βγαίνει.';
}

/// Τι δείχνει η κάρτα.
enum CheckKind {
  /// Νέος στόχος από τα δεδομένα (A1).
  proposal,

  /// Η εκτίμηση βγήκε, αλλά ο στόχος μένει ίδιος (αλλαγή κάτω από 30 kcal).
  same,

  /// Μέρα ελέγχου χωρίς αρκετά δεδομένα.
  fewData,

  /// Μέρα ελέγχου πριν μαζευτούν 3 εβδομάδες μετά την πρώτη (Συμβούλιο 2, Α2): η πρώτη εβδομάδα δεν μετρά, γιατί τότε
  /// φεύγουν κυρίως νερά. Η κάρτα το εξηγεί· η πρώτη εκτίμηση βγαίνει την επόμενη μέρα ελέγχου.
  gathering,

  /// Τα νούμερα δεν βγάζουν νόημα (συνήθως γεύματα που δεν γράφτηκαν).
  implausible,

  /// Χάνεις πάνω από 1% του βάρους την εβδομάδα (A3). Με [CheckIn.proposal]: πρόταση +150. Χωρίς: το ημερολόγιο δείχνει
  /// ότι τρως πολύ κάτω από τον στόχο (ή δεν δείχνει τίποτα), άρα δεν φταίει ο στόχος (έλεγχος 13/11, S1-2).
  fast,

  /// Μέρα ελέγχου με κενό καταγραφής φαγητού (έλεγχος 13/11, S1-1): καμία εκτίμηση, ο στόχος μένει.
  gap,

  /// Μια ζύγιση που δεν μπορεί να είναι δική σου δεν μέτρησε (S11-2). Μόνο ενημέρωση, «Εντάξει».
  foreign,

  /// Μέρα ελέγχου, αλλά οι ζυγίσεις δεν διαβάστηκαν τώρα (S11-8). Χωρίς κουμπί: ο έλεγχος δεν «ξοδεύεται».
  unread,
}

class CheckIn {
  const CheckIn(
      {required this.kind,
      required this.goals,
      this.status,
      this.est,
      this.proposal,
      this.kgNow,
      this.fastSlope,
      this.fastDays,
      this.days = 0,
      this.weighs = 0,
      this.tooFast = false,
      this.heldDays,
      this.quitDays,
      this.gap,
      this.absurd = const [],
      this.foreign = const [],
      this.fastIntake,
      this.fastIntakeDays = 0,
      this.fastTarget,
      this.estTarget,
      this.lowLog = false,
      this.formula,
      this.formulaKg});
  final CheckKind kind;
  final Goals goals;

  /// Κ1-L6 (17/11): ο τύπος με τον οποίο κρίθηκε η εκτίμηση ([formulaNow]) και το βάρος του, όταν διαφέρει από του
  /// οδηγού (null: ο τύπος του οδηγού). Η κάρτα γράφει αυτόν τον αριθμό.
  final double? formula;
  final double? formulaKg;
  double get formulaTdee => formula ?? goals.calc.tdee;
  final AdaptStatus? status;
  final Expenditure? est;
  final AdaptProposal? proposal;

  /// Το βάρος με το οποίο υπολογίστηκε ο ρυθμός (η τελευταία ζύγιση του παραθύρου).
  final double? kgNow;

  /// Για τη γρήγορη απώλεια: kg την εβδομάδα (αρνητικό) στις μέρες που κρίθηκαν ([fastDays]).
  final double? fastSlope;

  /// Για τη γρήγορη απώλεια: πόσες μέρες πίσω φτάνει το παράθυρο που κρίθηκε (το πολύ 21· λιγότερες όσο η πρώτη
  /// εβδομάδα των στόχων το κόβει). Η κάρτα γράφει ακριβώς αυτό ([fastPeriodText]).
  final int? fastDays;

  /// Στις 3 τελευταίες εβδομάδες (χωρίς την πρώτη εβδομάδα των στόχων): μέρες φαγητού που μετρούν (≥ 60% του στόχου)
  /// και ζυγίσεις. Για την κάρτα «λίγα δεδομένα».
  final int days, weighs;

  /// Εβδομαδιαίος έλεγχος (S1-3): χάνεις πάνω από 1% την εβδομάδα και τα δεδομένα δεν ζητούν αύξηση. Ο στόχος ΔΕΝ
  /// κατεβαίνει· η κάρτα λέει γιατί.
  final bool tooFast;

  /// Εβδομαδιαίος έλεγχος (S1-4): ο στόχος άλλαξε πριν από τόσες μέρες (λιγότερες από [adaptMinChangeDays]), γι' αυτό
  /// δεν προτείνεται νέα αλλαγή τώρα. null: δεν ισχύει.
  final int? heldDays;

  /// Απόφαση χρήστη 17/11: πριν από πόσες μέρες έκοψες το κάπνισμα, όταν γι' αυτό ο στόχος δεν κατέβηκε
  /// ([smokeQuitHoldDays]).
  final int? quitDays;

  /// Το κενό καταγραφής φαγητού ([CheckKind.gap]· και στο [CheckKind.gathering], για τη μέρα της πρώτης εκτίμησης:
  /// R8-A1-4).
  final FoodGap? gap;

  /// Μέρες του παραθύρου με αδύνατα πολλές θερμίδες, που δεν μπήκαν στον μέσο όρο (S11-3), με τις θερμίδες τους.
  final List<(DateTime, double)> absurd;

  /// Ζυγίσεις των 3 τελευταίων εβδομάδων που δεν μέτρησαν γιατί δεν μπορεί να είναι δικές σου (S11-2) και που δεν τις
  /// έχεις δει ακόμα σε κάρτα.
  final List<(DateTime, double)> foreign;

  /// Γρήγορη απώλεια: ο μέσος όρος όσων γράφτηκαν στο ημερολόγιο τις μέρες που κρίθηκαν (kcal τη μέρα), όταν υπάρχουν
  /// τουλάχιστον [adaptFastMinIntakeDays] γραμμένες μέρες και [adaptFastRecentMinDays] από τις [adaptFastRecentDays]
  /// τελευταίες (γύρος 2, R2-A-3)· αλλιώς null. [fastIntakeDays]: πόσες μέρες γράφτηκαν.
  final double? fastIntake;
  final int fastIntakeDays;

  /// Γύρος 2 (R2-A-1): ο μέσος όρος των στόχων που ίσχυαν τις ίδιες μέρες ([targetOn]), για να συγκρίνεται το φαγητό κάθε
  /// μέρας με τον στόχο της. [fastTarget]: για το [fastIntake] (null όταν και αυτό είναι null). [estTarget]: για το
  /// [Expenditure.meanIntake] του εβδομαδιαίου ελέγχου (μόνο με εκτίμηση).
  final double? fastTarget;
  final double? estTarget;

  /// Round 7 (R7-A1-1): πρόταση ([CheckKind.proposal]) από τη ζυγαριά, ενώ η εκτίμηση βγήκε πολύ χαμηλή (το ημερολόγιο
  /// γράφει λιγότερο από όσο τρως): [status] είναι [AdaptStatus.implausible] και το [est] δεν δείχνεται ως «πόσο καις».
  final bool lowLog;

  /// Ο στόχος από τον ρυθμό, πριν από το όριο των ±150 (για το «Πώς βγήκε»).
  int? get wanted {
    final e = est, k = kgNow;
    if (e == null || k == null) return null;
    final delta = switch (goals.aim) {
      GoalAim.lose => -k * goals.rate * kcalPerKg / 7,
      GoalAim.gain => k * goals.rate * kcalPerKg / 7,
      GoalAim.keep => 0.0,
    };
    return ((e.tdee + delta) / 10).round() * 10;
  }

  /// Τα δεδομένα θέλουν στόχο κάτω από το κάτω όριο (1.500 / 1.200)· ο στόχος δεν φτάνει ποτέ εκεί, όσοι έλεγχοι κι αν
  /// γίνουν. Το «Πώς βγήκε» γράφει τότε το όριο, όχι «τα δεδομένα λένε 1.210» (Συμβούλιο 2, μ1): ένας αριθμός κάτω από το
  /// όριο δεν πρέπει να διαβαστεί ως στόχος που έρχεται.
  bool get wantsBelowFloor {
    final w = wanted;
    return w != null && w < (goals.male ? kcalFloorMale : kcalFloorFemale);
  }
}

/// Η πρώτη μέρα που βγαίνει κάρτα ελέγχου: 21 μέρες μετά την αρχή (ίδια μέρα της εβδομάδας). Εκείνη τη μέρα η κάρτα
/// λέει ότι μαζεύει ακόμα δεδομένα ([CheckKind.gathering])· η πρώτη εκτίμηση βγαίνει στο [firstEstimateDay].
/// Απόφαση χρήστη 17/11: για 10 εβδομάδες αφού κόψεις το κάπνισμα ο στόχος θερμίδων δεν κατεβαίνει. Τους πρώτους μήνες
/// το βάρος ανεβαίνει συνήθως 2–3 kg (Aubin 2012, BMJ: +2,9 kg στους 3 μήνες, +4,7 στον χρόνο), κυρίως γιατί η νικοτίνη
/// ανεβάζει την κατανάλωση και κόβει την όρεξη. Η εφαρμογή δεν το «πολεμά» με λιγότερο φαγητό: προτεραιότητα να μην
/// ξαναρχίσεις. Επιλογή προσοχής (έλεγχος 19/11, S-9): Hartmann-Boyce 2021 (Cochrane): γενικές οδηγίες για το βάρος χωρίς
/// εξατομικευμένη υποστήριξη μπορεί να μειώνουν τις διακοπές (χαμηλή βεβαιότητα).
const smokeQuitHoldDays = 70;

/// Πόσες μέρες πέρασαν από τη διακοπή, όταν είναι μέσα στις [smokeQuitHoldDays]· αλλιώς null.
int? quitHoldDays(DateTime? quitDay, DateTime today) {
  if (quitDay == null) return null;
  final d = daysBetween(_day(quitDay), _day(today));
  return d >= 0 && d < smokeQuitHoldDays ? d : null;
}

DateTime firstCheckDay(Goals g) {
  final s = DateTime.parse(g.since);
  return DateTime(s.year, s.month, s.day + adaptWindowDays);
}

/// Η πρώτη μέρα ελέγχου με εκτίμηση: 28 μέρες μετά την αρχή, δηλαδή 21 μέρες που μετρούν μετά την πρώτη εβδομάδα
/// (Συμβούλιο 2, Α2). Ίδια μέρα της εβδομάδας με την αρχή. Αυτή δείχνει η σελίδα «Στόχοι» ως «Πρώτος έλεγχος».
DateTime firstEstimateDay(Goals g) {
  final s = DateTime.parse(g.since);
  return DateTime(s.year, s.month, s.day + adaptSkipDays + adaptWindowDays);
}

/// Πώς γράφει η κάρτα της γρήγορης απώλειας την περίοδο που κρίθηκε (εγκρίθηκε 12/11): «Τις τελευταίες 11 μέρες» όσο η
/// πρώτη εβδομάδα κόβει το παράθυρο, «Τις 2 / 3 τελευταίες εβδομάδες» όταν είναι ακριβώς 14 ή 21 μέρες.
String fastPeriodText(int? days) => switch (days) {
      null => 'Τις τελευταίες μέρες',
      14 => 'Τις 2 τελευταίες εβδομάδες',
      21 => 'Τις 3 τελευταίες εβδομάδες',
      _ => 'Τις τελευταίες $days μέρες',
    };

/// Η επόμενη μέρα ελέγχου (σήμερα, αν εκκρεμεί). Ίδιος κανόνας με το [checkInDue] (έλεγχος 13/11, S1-4): μια μέρα ελέγχου
/// λιγότερο από [adaptMinChangeDays] μέρες μετά από απάντηση που άλλαξε τον στόχο δεν μετρά· μετά από απάντηση που δεν
/// άλλαξε τίποτα, μετρά η επόμενη μέρα ελέγχου (γύρος 2, R2-A-5: πριν, ένα «Εντάξει» την Παρασκευή στο «μαζεύω δεδομένα»
/// μετέθετε την πρώτη εκτίμηση από τις 14 στις 21 Δεκεμβρίου, ενώ ο οδηγός είχε πει 14).
DateTime nextCheckDay(Goals g, DateTime today) {
  final t = _day(today);
  if (checkInDue(goals: g, today: t, lastCheckIn: g.checkIn)) return t;
  final first = firstCheckDay(g);
  if (t.isBefore(first)) return first;
  final ci = g.checkIn;
  final last = ci == null ? null : DateTime.tryParse(ci);
  var d = t;
  if (last != null) {
    // Η νωρίτερη μέρα που μπορεί να ξαναβγεί έλεγχος· από εκεί, η πρώτη ίδια μέρα της εβδομάδας με την αρχή.
    final gap = answerChangedTarget(g, last) ? adaptMinChangeDays : 1;
    final earliest = DateTime(last.year, last.month, last.day + gap);
    if (earliest.isAfter(d)) d = earliest;
  }
  while (d.weekday != first.weekday) {
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return d;
}

/// Τόσες γραμμένες μέρες φαγητού (τουλάχιστον) χρειάζεται η «γρήγορη απώλεια» για να πει πόσο τρως (S1-2).
const adaptFastMinIntakeDays = 4;

/// Γύρος 2 (R2-A-3): και από τις [adaptFastRecentDays] τελευταίες τελειωμένες μέρες, τουλάχιστον [adaptFastRecentMinDays]
/// γραμμένες. Αυτές οι μέρες κινούν περισσότερο τη ζυγαριά· αν λείπουν (π.χ. αρρώστια χωρίς καταγραφή), το ημερολόγιο
/// δεν λέει πόσο τρως τώρα, και το +150 δεν προτείνεται από τις παλιότερες μέρες. Προσομοίωση (300 επαναλήψεις): με
/// αρρώστια 10 ημερών χωρίς καταγραφή τα λάθος +150 πέφτουν από 1,93 σε 0,27 ανά επανάληψη· η αληθινά γρήγορη απώλεια
/// (1,2% την εβδομάδα, 10% μέρες χωρίς καταγραφή) πιάνεται όπως πριν (κάρτα τη 22η μέρα, +150 στο 99% των επαναλήψεων).
const adaptFastRecentDays = 7;
const adaptFastRecentMinDays = 5;

/// Η τελευταία μέρα που άλλαξε ο στόχος από κάρτα (εβδομαδιαίος έλεγχος ή γρήγορη απώλεια με «Εφάρμοσε»). null: ποτέ.
DateTime? lastChangeDay(Goals g) {
  String? last;
  for (final l in g.log) {
    if (l.applied && (last == null || l.day.compareTo(last) > 0)) last = l.day;
  }
  return last == null ? null : DateTime.tryParse(last);
}

/// Ο στόχος θερμίδων που ίσχυε τη μέρα [d] (γύρος 2, R2-A-1): το «πριν» της πρώτης αλλαγής από κάρτα («Εφάρμοσε») που
/// έγινε εκείνη τη μέρα ή αργότερα· αν από τότε δεν άλλαξε, ο τωρινός. Η μέρα της αλλαγής μετρά με τον παλιό στόχο (το
/// «Εφάρμοσε» πατιέται κάποια ώρα μέσα στη μέρα). Πριν, κάθε μέρα συγκρινόταν με τον ΤΩΡΙΝΟ στόχο: όποιος έτρωγε ακριβώς
/// τους στόχους του, μετά από δύο «+150» άκουγε «τρως πολύ λίγο» και το επόμενο +150 δεν προτεινόταν.
/// Round 9 (R9-A1-2 / R9-A12-4): από το [Goals.hist], όπου γράφεται ΚΑΘΕ αλλαγή του στόχου (κάρτα, δικός σου στόχος,
/// «από τον υπολογισμό», «Ξανά ο οδηγός», «Υπολόγισε ξανά»), όχι μόνο από το «Εφάρμοσε»: πριν, μετά από έναν δικό σου
/// στόχο 2.000 οι προηγούμενες μέρες κρίνονταν με το 2.000 αντί για τον στόχο τους, και το [log] κρατά μόνο τους
/// [adaptLogMax] τελευταίους ελέγχους. Όσο το [Goals.hist] είναι άδειο (στόχοι από παλιότερη έκδοση), οι αλλαγές από
/// κάρτα του [Goals.log], όπως πριν. Μέρες πριν από την αρχή των στόχων δεν ξεχωρίζουν εδώ (η Διατροφή: [beforeGoals]).
int targetOn(Goals g, DateTime d) {
  final key = dateKey(d);
  final changes = g.hist.isNotEmpty
      ? g.hist
      : [
          for (final l in g.log)
            if (l.applied) TargetChange(day: l.day, before: l.before, after: l.after),
        ];
  TargetChange? next;
  for (final c in changes) {
    if (c.day.compareTo(key) >= 0 && (next == null || c.day.compareTo(next.day) < 0)) next = c;
  }
  return next?.before ?? g.kcal;
}

/// Ο μέσος όρος του [targetOn] στις [days] (ο τωρινός στόχος, αν δεν υπάρχει καμία μέρα).
double meanTargetOn(Goals g, Iterable<DateTime> days) {
  var sum = 0.0;
  var n = 0;
  for (final d in days) {
    sum += targetOn(g, d);
    n++;
  }
  return n == 0 ? g.kcal.toDouble() : sum / n;
}

/// Τι εκκρεμεί σήμερα (null: τίποτα). Ο εβδομαδιαίος έλεγχος έχει προτεραιότητα· η γρήγορη απώλεια βγαίνει τις άλλες
/// μέρες, μία φορά την εβδομάδα, και όχι τη μέρα που απάντησες στον έλεγχο.
///
/// Έλεγχος 13/11. [weights]: οι ζυγίσεις που μετρούν ([guardedWeights] → used). [foreign]: όσες εξαιρέθηκαν ως ξένες, για
/// να τις γράψει η κάρτα (S11-2)· όσες δεν έχεις δει βγαίνουν μέσα στην κάρτα της μέρας, αλλιώς σε δική τους
/// ([CheckKind.foreign]). [weightsRead]: false όταν οι ζυγίσεις δεν διαβάστηκαν τώρα (S11-8): τη μέρα ελέγχου η κάρτα το
/// λέει χωρίς κουμπί, τις άλλες μέρες δεν βγαίνει τίποτα.
CheckIn? pendingCheckIn({
  required Goals? goals,
  required DateTime today,
  required List<(DateTime, double)> weights,
  required Map<DateTime, double> Function(DateTime from, DateTime to) intake,
  List<(DateTime, double)> foreign = const [],
  bool weightsRead = true,
  DateTime? quitDay,
}) {
  final g = goals;
  if (g == null) return null;
  final t = _day(today);
  // Ξένες ζυγίσεις των 3 τελευταίων εβδομάδων που δεν έχουν φανεί ακόμα σε κάρτα.
  final seen = g.foreignSeen;
  final recentFrom = DateTime(t.year, t.month, t.day - adaptFastWindowDays);
  final news = [
    for (final x in foreign)
      if (!x.$1.isBefore(recentFrom) && !x.$1.isAfter(t) && (seen == null || dateKey(x.$1).compareTo(seen) > 0)) x,
  ];
  // Κ1-L6 (17/11): ο τύπος με το τωρινό βάρος, για όλους τους ελέγχους λογικής εδώ ([formulaNow]).
  final fNow = formulaNow(g, weights);
  final formula = fNow.tdee;
  // Μέρα με αδύνατα πολλές θερμίδες δεν μετρά πουθενά (S11-3).
  final over = absurdDayKcal(formula);
  if (checkInDue(goals: g, today: t, lastCheckIn: g.checkIn)) {
    if (!weightsRead) return CheckIn(kind: CheckKind.unread, goals: g);
    final to = DateTime(t.year, t.month, t.day - 1);
    final since = DateTime.parse(g.since);
    // Η πρώτη εβδομάδα των στόχων δεν μετρά (Συμβούλιο 2, Α2).
    final firstCounted = DateTime(since.year, since.month, since.day + adaptSkipDays);
    DateTime notBeforeFirst(DateTime d) => d.isBefore(firstCounted) ? firstCounted : d;
    // Το φαγητό διαβάζεται για το μεγαλύτερο παράθυρο (ως 42 μέρες, Α1) και 4 μέρες πριν από αυτό, για το κενό καταγραφής
    // ([adaptScanDays], γύρος 2, R2-A-2)· οι μετρητές της κάρτας «λίγα δεδομένα» αφορούν τις 3 τελευταίες εβδομάδες, όπως
    // γράφει το κείμενό της.
    final wideFrom = notBeforeFirst(DateTime(to.year, to.month, to.day - (adaptScanDays - 1)));
    final from = notBeforeFirst(DateTime(to.year, to.month, to.day - (adaptWindowDays - 1)));
    final eaten = intake(wideFrom, to);
    final days =
        eaten.entries.where((e) => !e.key.isBefore(from) && e.value >= adaptFullDayShare * g.kcal && e.value <= over).length;
    final weighs = weights.where((w) => !w.$1.isBefore(from) && !w.$1.isAfter(to)).length;
    final r = estimateExpenditure(
      intake: eaten,
      weights: weights,
      today: t,
      formulaTdee: formula,
      goalKcal: g.kcal,
      since: since,
    );
    // Οι μέρες με αδύνατα πολλές θερμίδες του παραθύρου που κρίθηκε (αλλιώς των 3 τελευταίων εβδομάδων), για την κάρτα.
    final absurdFrom = r.est?.from ?? from;
    final absurd = [
      for (final e in eaten.entries)
        if (!e.key.isBefore(absurdFrom) && e.value > over) (e.key, e.value),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    switch (r.status) {
      case AdaptStatus.ok:
        final e = r.est!;
        // Το βάρος για τον ρυθμό: η τελευταία ζύγιση του παραθύρου που έδωσε την εκτίμηση.
        final inWindow = [for (final w in weights) if (!w.$1.isBefore(e.from) && !w.$1.isAfter(e.to)) w];
        final kg = inWindow.last.$2;
        var p = proposeTarget(goals: g, est: e, kgNow: kg);
        // Έλεγχος 20/11 (K1-C-02): πρόταση από παράθυρο μεγαλύτερο των 21 ημερών μόνο όταν και οι 21 τελευταίες μέρες
        // δείχνουν προς την ίδια κατεύθυνση ([recentAgrees]). Η εκτίμηση των 21 ημερών βγαίνει από τον ίδιο υπολογισμό, με
        // «αρχή» τέτοια που να χωρά ακριβώς το μικρότερο παράθυρο.
        if (p.change != 0 && e.windowDays > adaptWindowDays) {
          final recentSince = DateTime(to.year, to.month, to.day - (adaptWindowDays - 1) - adaptSkipDays);
          final recent = estimateExpenditure(
              intake: eaten, weights: weights, today: t, formulaTdee: formula, goalKcal: g.kcal, since: recentSince).est;
          p = recentAgrees(
              p: p, goals: g, recent: recent != null && recent.windowDays == adaptWindowDays ? recent : null, kgNow: kg);
        }
        // S1-3: όσο χάνεις πάνω από 1% την εβδομάδα (στο παράθυρο της εκτίμησης ή στις τελευταίες μέρες), ο στόχος δεν
        // κατεβαίνει. Πριν, η κάρτα της Δευτέρας τον κατέβαζε 150 και η «γρήγορη απώλεια» της Παρασκευής τον ανέβαζε 150.
        // Έλεγχος 20/11 (K1-C-02): οι τελευταίες μέρες χωρίς την πρώτη εβδομάδα μετά από κενό καταγραφής ([fastNotBefore]).
        final fastFrom =
            fastNotBefore(foodGap(intake: eaten, today: t, formulaTdee: formula, goalKcal: g.kcal, since: since));
        final losingFast = g.aim == GoalAim.lose &&
            (e.slopeKgWeek < -adaptFastLossPct * kg ||
                fastLossSlope(goals: g, weights: weights, today: t, notBefore: fastFrom) != null);
        final tooFast = losingFast && p.change <= 0;
        // S1-4: όχι δεύτερη αλλαγή λιγότερο από 4 μέρες μετά την προηγούμενη (π.χ. «γρήγορη απώλεια» την Παρασκευή).
        final changed = lastChangeDay(g);
        final sinceChange = changed == null ? null : daysBetween(changed, t);
        final held = sinceChange != null && sinceChange < adaptMinChangeDays && p.change != 0;
        final quit = quitHoldDays(quitDay, t);
        final quitHeld = quit != null && p.change < 0 && !tooFast && !held;
        if ((tooFast && p.change < 0) || held || quitHeld) {
          p = AdaptProposal(current: p.current, target: p.current, est: e, fastLoss: false, floored: false);
        }
        // R2-A-1: οι στόχοι που ίσχυαν τις μέρες που μπήκαν στον μέσο όρο φαγητού (ίδιο φίλτρο με το estimateExpenditure).
        final full = adaptFullDayShare * g.kcal;
        final estTarget = meanTargetOn(g, [
          for (final x in eaten.entries)
            if (!x.key.isBefore(e.from) && !x.key.isAfter(e.to) && x.value >= full && x.value <= over) x.key,
        ]);
        return CheckIn(
            kind: p.same ? CheckKind.same : CheckKind.proposal,
            goals: g,
            status: r.status,
            est: e,
            proposal: p,
            kgNow: kg,
            days: days,
            weighs: weighs,
            tooFast: tooFast,
            heldDays: held ? sinceChange : null,
            quitDays: quitHeld ? quit : null,
            absurd: absurd,
            foreign: news,
            estTarget: estTarget,
            formula: formula,
            formulaKg: fNow.kg);
      case AdaptStatus.implausible:
        // Round 7 (R7-A1-1): εκτίμηση πολύ χαμηλή (λείπει φαγητό από το ημερολόγιο) και βάρος καθαρά πιο ψηλά από τον
        // ρυθμό σου: ο στόχος κατεβαίνει από τη ζυγαριά ([lowLogProposal]). Όχι λιγότερο από 4 μέρες μετά από αλλαγή (S1-4).
        final lowEst = r.est;
        final lowWeights = lowEst == null
            ? const <(DateTime, double)>[]
            : [for (final w in weights) if (!w.$1.isBefore(lowEst.from) && !w.$1.isAfter(lowEst.to)) w];
        final lowKg = lowWeights.isEmpty ? null : lowWeights.last.$2;
        final lowP = lowEst == null || lowKg == null ? null : lowLogProposal(goals: g, est: lowEst, kgNow: lowKg, formulaTdee: formula);
        final lowChanged = lastChangeDay(g);
        final lowHeld = lowChanged != null && daysBetween(lowChanged, t) < adaptMinChangeDays;
        // 17/11: και όχι στις 10 εβδομάδες μετά τη διακοπή του καπνίσματος (πάντα προς τα κάτω).
        if (lowP != null && !lowHeld && quitHoldDays(quitDay, t) == null) {
          return CheckIn(
              kind: CheckKind.proposal,
              goals: g,
              status: r.status,
              est: lowEst,
              proposal: lowP,
              kgNow: lowKg,
              days: days,
              weighs: weighs,
              absurd: absurd,
              foreign: news,
              lowLog: true,
              formula: formula,
              formulaKg: fNow.kg);
        }
        // Έλεγχος 19/11 (L-2): στις 10 εβδομάδες μετά τη διακοπή, εκτίμηση χαμηλή = συνήθως το βάρος που ανεβαίνει μετά
        // τη διακοπή (μέση άνοδος ~0,25 kg την εβδομάδα τους πρώτους μήνες), όχι γεύματα που δεν γράφτηκαν: η κάρτα το λέει.
        final quitLow = quitHoldDays(quitDay, t);
        return CheckIn(
            kind: CheckKind.implausible,
            goals: g,
            status: r.status,
            est: r.est,
            days: days,
            weighs: weighs,
            absurd: absurd,
            foreign: news,
            // V-4: μόνο όταν το βάρος ανεβαίνει· αλλιώς η χαμηλή εκτίμηση είναι συνήθως φαγητό που δεν γράφτηκε.
            quitDays: quitLow != null && r.est != null && r.est!.tdee < formula && r.est!.slopeKgWeek > 0 ? quitLow : null,
            formula: formula,
            formulaKg: fNow.kg);
      case AdaptStatus.tooEarly:
        // Round 8 (R8-A1-4): και το κενό καταγραφής ως χθες. Μετά από κενό η πρώτη εκτίμηση δεν βγαίνει την επόμενη μέρα
        // ελέγχου αλλά 3 εβδομάδες αφού ξαναρχίσει η καταγραφή ([estimateDayAfterGap]): η κάρτα το γράφει.
        return CheckIn(
            kind: CheckKind.gathering,
            goals: g,
            status: r.status,
            days: days,
            weighs: weighs,
            gap: foodGap(intake: eaten, today: t, formulaTdee: formula, goalKcal: g.kcal, since: since),
            foreign: news);
      case AdaptStatus.gapOpen:
      case AdaptStatus.afterGap:
        return CheckIn(
            kind: CheckKind.gap,
            goals: g,
            status: r.status,
            days: days,
            weighs: weighs,
            gap: foodGap(intake: eaten, today: t, formulaTdee: formula, goalKcal: g.kcal, since: since),
            absurd: absurd,
            foreign: news);
      case AdaptStatus.fewIntakeDays:
      case AdaptStatus.fewWeighIns:
        return CheckIn(
            kind: CheckKind.fewData, goals: g, status: r.status, days: days, weighs: weighs, absurd: absurd, foreign: news);
    }
  }
  if (g.checkIn == dateKey(t)) return null;
  if (!weightsRead) return null;
  // Χωρίς γρήγορη απώλεια: μόνο η ενημέρωση για ξένη ζύγιση, αν υπάρχει καινούργια.
  final CheckIn? onlyForeign = news.isEmpty ? null : CheckIn(kind: CheckKind.foreign, goals: g, foreign: news);
  final fa = g.fastAt == null ? null : DateTime.tryParse(g.fastAt!);
  if (fa != null && daysBetween(fa, t) < 7) return onlyForeign;
  // S1-4: όχι πρόταση λιγότερο από 4 μέρες μετά από αλλαγή του στόχου.
  final lastChange = lastChangeDay(g);
  if (lastChange != null && daysBetween(lastChange, t) < adaptMinChangeDays) return onlyForeign;
  // Οι ίδιες ζυγίσεις που κρίνουν την ειδοποίηση (χωρίς την πρώτη εβδομάδα· Συμβούλιο 2, Σ1): ό,τι γράφει η κάρτα
  // («−1,16 kg την εβδομάδα») είναι ακριβώς ο αριθμός που συγκρίθηκε με το 1%.
  // Πρώτα μόνο με τις ζυγίσεις (φθηνό)· το φαγητό διαβάζεται μόνο αν υπάρχει λόγος.
  if (fastLossSlope(goals: g, weights: weights, today: t) == null) return onlyForeign;
  final yesterday = DateTime(t.year, t.month, t.day - 1);
  // Έλεγχος 20/11 (K1-C-02): μετά από κενό καταγραφής οι πρώτες μέρες της επιστροφής δεν κρίνονται ([fastNotBefore]): τα
  // νερά των διακοπών φεύγουν σε λίγες μέρες και έμοιαζαν με «γρήγορη απώλεια» (ψεύτικο «+150» στο 32–46% των πορειών).
  final scanFrom = DateTime(yesterday.year, yesterday.month, yesterday.day - (adaptScanDays - 1));
  final fastFrom = fastNotBefore(foodGap(
      intake: intake(scanFrom, yesterday),
      today: t,
      formulaTdee: formula,
      goalKcal: g.kcal,
      since: DateTime.tryParse(g.since)));
  final f = fastLossSlope(goals: g, weights: weights, today: t, notBefore: fastFrom);
  final window = fastLossWindow(goals: g, today: t, notBefore: fastFrom);
  if (f == null || window == null) return onlyForeign;
  // S1-2: πόσο γράφτηκε στο ημερολόγιο τις ίδιες μέρες (ως χθες· η σημερινή μέρα δεν έχει τελειώσει). Όλες οι μέρες με
  // καταχώριση, όχι μόνο όσες περνούν το 60%: εδώ ψάχνουμε ακριβώς το «τρως πολύ λίγο».
  final diary = yesterday.isBefore(window.$1) ? const <DateTime, double>{} : intake(window.$1, yesterday);
  final loggedDays = [
    for (final e in diary.entries)
      if (e.value <= over) e.key,
  ];
  final logged = [for (final d in loggedDays) diary[d]!];
  // R2-A-3: γραμμένες και οι περισσότερες από τις τελευταίες μέρες (αλλιώς το ημερολόγιο δεν λέει πόσο τρως τώρα).
  final recentFrom7 = DateTime(yesterday.year, yesterday.month, yesterday.day - (adaptFastRecentDays - 1));
  final recent = loggedDays.where((d) => !d.isBefore(recentFrom7)).length;
  final known = logged.length >= adaptFastMinIntakeDays && recent >= adaptFastRecentMinDays;
  final mean = logged.isEmpty ? null : logged.reduce((a, b) => a + b) / logged.length;
  // R2-A-1: κάθε μέρα με τον στόχο που ίσχυε εκείνη τη μέρα, όχι με τον τωρινό.
  final target = meanTargetOn(g, loggedDays);
  AdaptProposal? proposal;
  if (known && mean != null && mean >= target - adaptMaxStep) {
    // Τρως περίπου όσο ο στόχος και χάνεις γρήγορα: πρόταση +150, ως όσα καις. Αν ο στόχος είναι ήδη εκεί, καμία κάρτα·
    // ο εβδομαδιαίος έλεγχος τον διορθώνει από τα δεδομένα.
    proposal = fastLossCheck(goals: g, weights: weights, today: t, notBefore: fastFrom);
    if (proposal == null) return onlyForeign;
  }
  return CheckIn(
      kind: CheckKind.fast,
      goals: g,
      proposal: proposal,
      kgNow: f.kg,
      fastSlope: f.slopeKgWeek,
      fastDays: daysBetween(window.$1, window.$2),
      fastIntake: known ? mean : null,
      fastIntakeDays: logged.length,
      fastTarget: known ? target : null,
      foreign: news);
}

/// Έλεγχος 20/11 (K1-S-02): πόσο πιο γρήγορα από τον ρυθμό σου πρέπει να χάνεις για να το πει η κάρτα.
const farBelowRate = 1.5;

/// Έλεγχος 20/11 (K1-S-02): εβδομαδιαίος έλεγχος με εκτίμηση, «λιγότερο λίπος», και το ημερολόγιο δείχνει ότι τρως πάνω
/// από [adaptMaxStep] kcal κάτω από τους στόχους που ίσχυαν ([CheckIn.estTarget]) ΕΝΩ χάνεις πάνω από [farBelowRate] φορές
/// τον ρυθμό που διάλεξες. Πριν, η κάρτα το έλεγε μόνο πάνω από 1% την εβδομάδα (S1-3)· ανάμεσα στο 0,5% και στο 1% έγραφε
/// σκέτο «ο στόχος σου ταιριάζει» σε όποιον έτρωγε 300–450 kcal λιγότερες και έχανε σχεδόν διπλάσια. Ο ρυθμός είναι επιλογή
/// του χρήστη για να κρατιούνται οι μύες (Helms 2014· Garthe 2011). null όταν δεν ισχύει.
/// [eaten], [target], [under]: στρογγυλεμένα στα 10, όπως γράφονται· [slopeKgWeek], [plannedKgWeek]: αρνητικά.
({int eaten, int target, int under, double slopeKgWeek, double plannedKgWeek})? eatingFarBelow(CheckIn k) {
  final e = k.est, kg = k.kgNow, targetMean = k.estTarget;
  final g = k.goals;
  if (e == null || kg == null || targetMean == null || k.lowLog || g.aim != GoalAim.lose) return null;
  final eaten = (e.meanIntake / 10).round() * 10;
  final target = (targetMean / 10).round() * 10;
  final under = target - eaten;
  if (under <= adaptMaxStep) return null;
  final planned = plannedKgWeek(g, kg);
  if (planned >= 0 || e.slopeKgWeek >= farBelowRate * planned) return null;
  return (eaten: eaten, target: target, under: under, slopeKgWeek: e.slopeKgWeek, plannedKgWeek: planned);
}

/// Οι ξένες ζυγίσεις που έγραψε η κάρτα θεωρούνται «ειδωμένες» μόλις απαντηθεί (δεν ξαναγράφονται).
Goals _markForeignSeen(CheckIn c, Goals g) {
  if (c.foreign.isEmpty) return g;
  var last = dateKey(c.foreign.first.$1);
  for (final f in c.foreign) {
    final k = dateKey(f.$1);
    if (k.compareTo(last) > 0) last = k;
  }
  return g.copyWith(foreignSeen: last);
}

/// «Εφάρμοσε»: ο νέος στόχος ισχύει από τώρα. Αντικαθιστά και τον δικό σου αριθμό, αν είχες γράψει (το ζήτησες εσύ).
/// Και το βήμα της «γρήγορης απώλειας» γράφεται πια στο ιστορικό ([AdaptLog.fast]· έλεγχος 13/11, S1-3 / S1-6).
/// Round 9 (R9-A1-2): και στο ιστορικό του στόχου ([Goals.recordChangeFrom]), όπως κάθε άλλη αλλαγή.
Goals applyCheckIn(CheckIn c, DateTime today) => _applied(c, today).recordChangeFrom(c.goals, today);

Goals _applied(CheckIn c, DateTime today) {
  final day = dateKey(today);
  final p = c.proposal!;
  if (c.kind == CheckKind.fast) {
    return _markForeignSeen(
        c,
        c.goals.copyWith(
          kcalAdapt: p.target,
          fastAt: day,
          clearKcal: true,
          addLog: AdaptLog(
              day: day, tdee: fastLossCap(c.goals).toDouble(), before: p.current, after: p.target, applied: true, fast: true),
        ));
  }
  // Round 7 (R7-A1-1): πρόταση από τη ζυγαριά με πολύ χαμηλή εκτίμηση. Η εκτίμηση ΔΕΝ κρατιέται (ούτε για το όριο της
  // «γρήγορης απώλειας» ούτε για τον οδηγό)· η γραμμή του ιστορικού γράφει, όπως στη «γρήγορη απώλεια», το όριο που ίσχυε.
  if (c.lowLog) {
    return _markForeignSeen(
        c,
        c.goals.copyWith(
          kcalAdapt: p.target,
          checkIn: day,
          clearKcal: true,
          addLog: AdaptLog(
              day: day, tdee: fastLossCap(c.goals).toDouble(), before: p.current, after: p.target, applied: true, lowLog: true),
        ));
  }
  return _markForeignSeen(
      c,
      c.goals.copyWith(
        kcalAdapt: p.target,
        tdeeEst: c.est!.tdee,
        checkIn: day,
        clearKcal: true,
        addLog: AdaptLog(day: day, tdee: c.est!.tdee, before: p.current, after: p.target, applied: true),
      ));
}

/// «Όχι τώρα» / «Εντάξει»: ο στόχος μένει ίδιος ως τον επόμενο έλεγχο· η εκτίμηση (αν βγήκε) κρατιέται για τη σελίδα «Στόχοι».
/// [CheckKind.unread] (οι ζυγίσεις δεν διαβάστηκαν) δεν αλλάζει τίποτα: ο έλεγχος της εβδομάδας μένει ανοιχτός (S11-8).
Goals dismissCheckIn(CheckIn c, DateTime today) {
  final day = dateKey(today);
  if (c.kind == CheckKind.unread) return c.goals;
  if (c.kind == CheckKind.foreign) return _markForeignSeen(c, c.goals);
  if (c.kind == CheckKind.fast) return _markForeignSeen(c, c.goals.copyWith(fastAt: day));
  final p = c.proposal;
  final e = c.est;
  // Round 7 (R7-A1-1): «Όχι τώρα» σε πρόταση από τη ζυγαριά: γραμμή στο ιστορικό (ο έλεγχος έγινε), χωρίς εκτίμηση.
  if (c.lowLog && p != null) {
    return _markForeignSeen(
        c,
        c.goals.copyWith(
          checkIn: day,
          addLog: AdaptLog(
              day: day, tdee: fastLossCap(c.goals).toDouble(), before: p.current, after: p.current, applied: false, lowLog: true),
        ));
  }
  if (p == null || e == null) return _markForeignSeen(c, c.goals.copyWith(checkIn: day));
  return _markForeignSeen(
      c,
      c.goals.copyWith(
        tdeeEst: e.tdee,
        checkIn: day,
        addLog: AdaptLog(day: day, tdee: e.tdee, before: p.current, after: p.current, applied: false),
      ));
}

/// Πριν από τον πρώτο έλεγχο (A4): πόσα δεδομένα μαζεύτηκαν ως χθες, μετά την πρώτη εβδομάδα των στόχων (που δεν μετρά:
/// Συμβούλιο 2, Α2), το πολύ 21 μέρες πίσω. [first]: η πρώτη μέρα ελέγχου με εκτίμηση ([firstEstimateDay]).
/// Round 7 (R7-A1-2): με τους ίδιους κανόνες με τον έλεγχο. [gap]: το κενό καταγραφής ([foodGap]) ως χθες· οι μέρες
/// μετρούν από τη μέρα που ξαναρχίζει η καταγραφή (με κενό που κρατά ακόμα: καμία). Μέρες πάνω από το [absurdDayKcal]
/// δεν μετρούν. Πριν, μετά από 5 μέρες χωρίς φαγητό η κάρτα έγραφε «16 από 14» ενώ ο έλεγχος δεν μπορούσε να βγάλει
/// εκτίμηση για άλλες 3 εβδομάδες.
/// Round 8 (R8-A1-6): [weighSpan] = πόσες μέρες απέχουν η πρώτη και η τελευταία από αυτές τις ζυγίσεις (0 με λιγότερες
/// από 2). Ο έλεγχος θέλει και τουλάχιστον [adaptMinSpanDays] ([estimateExpenditure]): πριν, η κάρτα έγραφε «Ζυγίσεις 8
/// από 6» για 8 ζυγίσεις μιας εβδομάδας, και ο έλεγχος έλεγε μετά «μαζεμένες σε λίγες μέρες».
({int intakeDays, int weighIns, int weighSpan, DateTime first, FoodGap? gap}) readiness({
  required Goals goals,
  required DateTime today,
  required List<(DateTime, double)> weights,
  required Map<DateTime, double> Function(DateTime from, DateTime to) intake,
}) {
  final start = DateTime.parse(goals.since);
  final firstCounted = DateTime(start.year, start.month, start.day + adaptSkipDays);
  final t = _day(today);
  final to = DateTime(t.year, t.month, t.day - 1);
  final windowFrom = DateTime(to.year, to.month, to.day - (adaptWindowDays - 1));
  var since = firstCounted.isAfter(windowFrom) ? firstCounted : windowFrom;
  final formula = formulaNow(goals, weights).tdee;
  // Το κενό ψάχνεται όσο πίσω και στον έλεγχο ([adaptScanDays]), χωρίς την πρώτη εβδομάδα.
  final scanFrom = DateTime(to.year, to.month, to.day - (adaptScanDays - 1));
  final wideFrom = scanFrom.isBefore(firstCounted) ? firstCounted : scanFrom;
  final gap = to.isBefore(wideFrom)
      ? null
      : foodGap(intake: intake(wideFrom, to), today: t, formulaTdee: formula, goalKcal: goals.kcal, since: start);
  if (gap != null) {
    final restart = gap.restart;
    // Κενό που κρατά ως χθες: τίποτα δεν μετρά ακόμα για την επόμενη εκτίμηση. Έλεγχος 20/11 (K1-C-02): μετά το κενό οι
    // μέρες μετρούν από [afterGapStart] (η πρώτη εβδομάδα της επιστροφής δεν μετρά), όπως στον έλεγχο.
    final from = restart == null ? DateTime(t.year, t.month, t.day) : afterGapStart(restart);
    if (from.isAfter(since)) since = from;
  }
  final full = adaptFullDayShare * goals.kcal;
  final over = absurdDayKcal(formula);
  final days = to.isBefore(since) ? 0 : intake(since, to).values.where((v) => v >= full && v <= over).length;
  final wDays = [for (final w in weights) if (!w.$1.isBefore(since) && !w.$1.isAfter(to)) w.$1];
  var span = 0;
  if (wDays.length >= 2) {
    var lo = wDays.first, hi = wDays.first;
    for (final d in wDays) {
      if (d.isBefore(lo)) lo = d;
      if (d.isAfter(hi)) hi = d;
    }
    span = daysBetween(lo, hi);
  }
  return (intakeDays: days, weighIns: wDays.length, weighSpan: span, first: firstEstimateDay(goals), gap: gap);
}

/// Round 7 (R7-A1-2): η μέρα ελέγχου που μπορεί να βγάλει εκτίμηση, μετά από κενό καταγραφής φαγητού. Ο έλεγχος θέλει
/// [adaptWindowDays] μέρες που μετρούν ως χθες ([estimateExpenditure]: «afterGap»), και από 20/11 (K1-C-02) οι πρώτες
/// [adaptSkipDays] μέρες της επιστροφής δεν μετρούν: άρα η πρώτη μέρα ελέγχου (ίδια μέρα της εβδομάδας με την αρχή) από
/// [FoodGap.restart] + 7 + 21 μέρες. Χωρίς κενό, ή αν η [next]
/// είναι ήδη αργότερα: η [next]. null: το κενό κρατά ως χθες (η εκτίμηση περιμένει να ξαναρχίσει η καταγραφή).
/// Πριν, η σελίδα «Στόχοι» έγραφε «Πρώτη εκτίμηση: Δευτέρα 21 Δεκεμβρίου» ενώ η Σήμερα έλεγε σωστά 4 Ιανουαρίου.
DateTime? estimateDayAfterGap(Goals g, DateTime next, FoodGap? gap) {
  if (gap == null) return next;
  final restart = gap.restart;
  if (restart == null) return null;
  // Έλεγχος 20/11 (K1-C-02): και η πρώτη εβδομάδα της επιστροφής δεν μετρά ([afterGapStart]).
  final counted = afterGapStart(restart);
  var d = DateTime(counted.year, counted.month, counted.day + adaptWindowDays);
  if (!d.isAfter(next)) return next;
  final weekday = DateTime.parse(g.since).weekday;
  while (d.weekday != weekday) {
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return d;
}
