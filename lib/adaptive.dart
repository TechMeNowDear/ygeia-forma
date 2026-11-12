/// Αυτόματη διόρθωση θερμίδων (συμφωνία 11/11, πριν από τις 7/12): από τα δικά σου δεδομένα, όχι από τύπο.
///
/// Ισοζύγιο ενέργειας: πραγματική κατανάλωση ≈ μέσες θερμίδες που έφαγες − (αλλαγή βάρους × 7.700 kcal/kg) / μέρες
/// (Hall 2008· η ίδια ιδέα με το MacroFactor). Κανένας αριθμός από AI: μόνο ό,τι έγραψες και ό,τι ζύγισε η ζυγαριά.
///
/// Κανόνες (όλοι εδώ, ένα μέρος). Τελευταία αλλαγή: τελικός έλεγχος, Συμβούλιο 2, αποφάσεις Α1–Α3 της 12/11.
/// - Η πρώτη εβδομάδα των στόχων δεν μετρά πουθενά ([adaptSkipDays], Α2): τότε φεύγουν κυρίως νερά και γλυκογόνο. Μετρημένα
///   σαν λίπος (7.700 kcal το κιλό) έβγαζαν την εκτίμηση περίπου 390 kcal πιο ψηλά για κάθε κιλό νερών (προσομοίωση).
///   Άρα η πρώτη εκτίμηση βγαίνει την 28η μέρα· την 21η η κάρτα λέει ότι μαζεύει ακόμα δεδομένα.
/// - Παράθυρο: οι τελευταίες ΤΕΛΕΙΩΜΕΝΕΣ μέρες (όχι σήμερα), από 21 ως 42 ([adaptWindows], Α1). Μετρά το μεγαλύτερο
///   παράθυρο που έχει αρκετά δεδομένα: με 42 μέρες το τυπικό σφάλμα της εκτίμησης πέφτει περίπου στο ένα τρίτο.
/// - Μέρα φαγητού που μετρά: τουλάχιστον 60% του στόχου θερμίδων. Λιγότερο σημαίνει σχεδόν πάντα ότι κάτι δεν γράφτηκε·
///   τέτοιες μέρες βγαίνουν από τον μέσο όρο (δεν θεωρούνται «λίγο φαγητό»).
/// - Αρκετά δεδομένα: φαγητό στα 2/3 των ημερών του παραθύρου (14 στις 21) και 2 ζυγίσεις την εβδομάδα (τουλάχιστον 6)
///   που απλώνονται στα 2/3 του παραθύρου (14 μέρες στις 21). Αλλιώς: «λίγα δεδομένα», καμία πρόταση.
/// - Τάση βάρους: ευθεία ελαχίστων τετραγώνων στις ζυγίσεις του παραθύρου. Από το πόσο απέχουν οι ζυγίσεις από την ευθεία
///   βγαίνει το τυπικό σφάλμα της κλίσης, δηλαδή πόσο σίγουρη είναι η εκτίμηση ([weightFit]).
/// - Αν η εκτίμηση βγει έξω από 70–140% του τύπου, κάτι λείπει (π.χ. μέρες χωρίς καταγραφή): καμία πρόταση.
/// - Νέος στόχος = εκτίμηση ± όσο χρειάζεται ο ρυθμός σου, στρογγυλεμένος στα 10, ποτέ κάτω από το όριο ασφαλείας,
///   και το πολύ ±150 kcal ανά εβδομαδιαίο έλεγχο. Αλλαγή κάτω από 30 kcal: «μένει ίδιος».
/// - Περιθώριο αβεβαιότητας (Α1): αλλαγή προτείνεται μόνο όταν η διαφορά είναι μεγαλύτερη από [adaptGuardSe] φορές το
///   τυπικό σφάλμα της εκτίμησης. Πριν, με 9 ζυγίσεις σε 21 μέρες, η κάρτα πρότεινε αλλαγή στο 84–93% των ελέγχων ενώ η
///   σωστή απάντηση ήταν «μένει ίδιος» (προσομοίωση με θόρυβο ζύγισης 0,3–0,6 kg)· με το περιθώριο πέφτει στο 7–9%.
/// - Γρήγορη απώλεια (Α3): στις [adaptFastWindowDays] τελευταίες μέρες ως και σήμερα, χωρίς την πρώτη εβδομάδα, η κλίση
///   περνά το 1% του βάρους την εβδομάδα ακόμα και με περιθώριο ενός τυπικού σφάλματος: πρόταση +150 kcal αμέσως (κρατά
///   τους μύες· Helms 2014, Garthe 2011). Για όποιον χάνει 0,75% την εβδομάδα, η πιθανότητα να δει ψεύτικη ειδοποίηση
///   κάποια μέρα ως την 28η πέφτει από 64% σε 10%· για 0,5% από 22% σε 1%. Όποιος χάνει 1,5% τη βλέπει στο 99,9%
///   (προσομοίωση με θόρυβο ζύγισης 0,4 kg, 4.000 επαναλήψεις).
/// - Μέρες: πάντα ημερολογιακές (DateTime(έτος, μήνας, μέρα − n)), ποτέ «μείον n × 24 ώρες»: στην αλλαγή ώρας μια μέρα
///   κρατά 23 ή 25 ώρες (Συμβούλιο 2, Σ2: ο απαντημένος έλεγχος ξαναέβγαινε την εβδομάδα μετά την αλλαγή του Οκτωβρίου).
library;

import 'dart:math' as math;

import 'format.dart' show daysBetween;
import 'goals.dart';

/// Το μικρότερο παράθυρο (και όσες μέρες μετά την αρχή βγαίνει η πρώτη κάρτα ελέγχου).
const adaptWindowDays = 21;

/// Τα παράθυρα που δοκιμάζονται, το μεγαλύτερο πρώτα (ολόκληρες εβδομάδες).
const adaptWindows = [42, 35, 28, 21];
const adaptMaxWindowDays = 42;

/// Οι πρώτες μέρες των στόχων που δεν μετρούν ούτε στην εκτίμηση ούτε στη «γρήγορη απώλεια»: νερά και γλυκογόνο.
const adaptSkipDays = 7;

/// Τα ελάχιστα για το παράθυρο των 21 ημερών· για μεγαλύτερο παράθυρο μεγαλώνουν αναλογικά ([adaptNeeds]).
const adaptMinIntakeDays = 14;
const adaptMinWeighIns = 6;
const adaptMinSpanDays = 14;
const adaptFullDayShare = fullDayShare;
const adaptMaxStep = 150;
const adaptMinStep = 30;

/// Πόσα τυπικά σφάλματα πρέπει να ξεπερνά η διαφορά για να προταθεί αλλαγή στόχου.
const adaptGuardSe = 2.0;
const adaptFastLossPct = 0.01;

/// Η «γρήγορη απώλεια» δεν κρίνεται πριν από αυτή τη μέρα των στόχων.
const adaptFastFromDay = 14;
const adaptFastWindowDays = 21;

/// Πόσα τυπικά σφάλματα περιθώριο αφήνει η «γρήγορη απώλεια» πριν ειδοποιήσει.
const adaptFastGuardSe = 1.0;

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Τι χρειάζεται ένα παράθυρο [windowDays] ημερών για να βγει εκτίμηση: μέρες φαγητού, ζυγίσεις, άπλωμα ζυγίσεων σε μέρες.
({int intakeDays, int weighIns, int spanDays}) adaptNeeds(int windowDays) => (
      intakeDays: (windowDays * adaptMinIntakeDays / adaptWindowDays).ceil(),
      weighIns: math.max(adaptMinWeighIns, (windowDays * 2 / 7).ceil()),
      spanDays: (windowDays * adaptMinSpanDays / adaptWindowDays).ceil(),
    );

/// Ευθεία ελαχίστων τετραγώνων στις ζυγίσεις: κλίση (kg ανά μέρα) και το τυπικό της σφάλμα, από το πόσο απέχουν οι
/// ζυγίσεις από την ευθεία. null με λιγότερα από 2 σημεία ή όλα την ίδια μέρα· [se] null με λιγότερα από 3 σημεία.
/// Οι μέρες μετριούνται ημερολογιακά (μία ζύγιση ανά μέρα), άρα η αλλαγή ώρας δεν τις πειράζει.
({double slope, double? se})? weightFit(List<(DateTime, double)> weights) {
  final n = weights.length;
  if (n < 2) return null;
  final t0 = weights.first.$1;
  final xs = [for (final w in weights) daysBetween(t0, w.$1).toDouble()];
  final ys = [for (final w in weights) w.$2];
  final mx = xs.reduce((a, b) => a + b) / n;
  final my = ys.reduce((a, b) => a + b) / n;
  var sxx = 0.0, sxy = 0.0;
  for (var i = 0; i < n; i++) {
    sxx += (xs[i] - mx) * (xs[i] - mx);
    sxy += (xs[i] - mx) * (ys[i] - my);
  }
  if (sxx < 1e-9) return null;
  final slope = sxy / sxx;
  if (n < 3) return (slope: slope, se: null);
  var rss = 0.0;
  for (var i = 0; i < n; i++) {
    final r = ys[i] - (my + slope * (xs[i] - mx));
    rss += r * r;
  }
  return (slope: slope, se: math.sqrt(rss / (n - 2) / sxx));
}

/// Κλίση (kg ανά μέρα) με ελάχιστα τετράγωνα· null με λιγότερα από 2 σημεία ή όλα την ίδια μέρα.
double? weightSlope(List<(DateTime, double)> weights) => weightFit(weights)?.slope;

/// Η εκτίμηση από τα δεδομένα.
class Expenditure {
  const Expenditure({
    required this.tdee,
    required this.meanIntake,
    required this.slopeKgWeek,
    required this.intakeDays,
    required this.weighIns,
    required this.from,
    required this.to,
    this.seKcal = 0,
    this.windowDays = adaptWindowDays,
  });

  /// Πραγματική κατανάλωση (kcal τη μέρα).
  final double tdee;
  final double meanIntake;

  /// Αλλαγή βάρους την εβδομάδα (αρνητικό = απώλεια).
  final double slopeKgWeek;
  final int intakeDays;
  final int weighIns;

  /// Το παράθυρο (από, ως και).
  final DateTime from, to;

  /// Τυπικό σφάλμα της εκτίμησης σε kcal τη μέρα: το τυπικό σφάλμα της κλίσης του βάρους × 7.700 (0: άγνωστο ή μηδενικό).
  final double seKcal;

  /// Πόσες μέρες έχει το παράθυρο που χρησιμοποιήθηκε (21 ως 42).
  final int windowDays;

  /// Το περιθώριο αβεβαιότητας (kcal): διαφορά ως εδώ δεν ξεχωρίζει από τον θόρυβο των ζυγίσεων.
  double get guardKcal => adaptGuardSe * seKcal;
}

enum AdaptStatus { ok, tooEarly, fewIntakeDays, fewWeighIns, implausible }

/// [intake]: θερμίδες ανά μέρα (όπως φαίνονται στη Διατροφή). [weights]: ζυγίσεις (μία ανά μέρα). [today]: σήμερα·
/// το παράθυρο τελειώνει χθες. [formulaTdee]: ο τύπος, για τον έλεγχο λογικής. [goalKcal]: για το «60% του στόχου».
/// [since]: η μέρα που ξεκίνησαν οι στόχοι· οι πρώτες [adaptSkipDays] μέρες δεν μετρούν (null: μετρούν όλες).
///
/// Δοκιμάζει τα παράθυρα του [adaptWindows] από το μεγαλύτερο: επιστρέφει το πρώτο που έχει αρκετά δεδομένα και λογική
/// εκτίμηση. Αν κανένα, την κατάσταση του μικρότερου (21 μέρες), ώστε η κάρτα να λέει τι λείπει «στις 3 τελευταίες
/// εβδομάδες». [AdaptStatus.tooEarly]: δεν έχουν περάσει ακόμα 21 μέρες που μετρούν.
({AdaptStatus status, Expenditure? est}) estimateExpenditure({
  required Map<DateTime, double> intake,
  required List<(DateTime, double)> weights,
  required DateTime today,
  required double formulaTdee,
  required int goalKcal,
  DateTime? since,
}) {
  // Χθες, ημερολογιακά (όχι «μείον 24 ώρες»: τη Δευτέρα μετά την αλλαγή ώρας του Μαρτίου έβγαινε Σάββατο 23:00).
  final t = _day(today);
  final to = DateTime(t.year, t.month, t.day - 1);
  final firstCounted = since == null ? null : DateTime(since.year, since.month, since.day + adaptSkipDays);
  final available = firstCounted == null ? adaptMaxWindowDays : daysBetween(firstCounted, to) + 1;
  if (available < adaptWindowDays) return (status: AdaptStatus.tooEarly, est: null);

  final full = adaptFullDayShare * goalKcal;
  ({AdaptStatus status, Expenditure? est}) result = (status: AdaptStatus.fewIntakeDays, est: null);
  for (final windowDays in adaptWindows) {
    if (windowDays > available) continue;
    final from = DateTime(to.year, to.month, to.day - (windowDays - 1));
    bool inWindow(DateTime d) => !_day(d).isBefore(from) && !_day(d).isAfter(to);
    final need = adaptNeeds(windowDays);
    final days = [
      for (final e in intake.entries)
        if (inWindow(e.key) && e.value >= full) e.value,
    ];
    final ws = [
      for (final w in weights)
        if (inWindow(w.$1) && w.$2 >= 30 && w.$2 <= 300) (_day(w.$1), w.$2),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    if (days.length < need.intakeDays) {
      result = (status: AdaptStatus.fewIntakeDays, est: null);
      continue;
    }
    if (ws.length < need.weighIns || daysBetween(ws.first.$1, ws.last.$1) < need.spanDays) {
      result = (status: AdaptStatus.fewWeighIns, est: null);
      continue;
    }
    final fit = weightFit(ws);
    if (fit == null) {
      result = (status: AdaptStatus.fewWeighIns, est: null);
      continue;
    }
    final mean = days.reduce((a, b) => a + b) / days.length;
    final tdee = mean - fit.slope * kcalPerKg;
    final est = Expenditure(
      tdee: tdee,
      meanIntake: mean,
      slopeKgWeek: fit.slope * 7,
      intakeDays: days.length,
      weighIns: ws.length,
      from: from,
      to: to,
      seKcal: (fit.se ?? 0.0) * kcalPerKg,
      windowDays: windowDays,
    );
    if (tdee < 0.7 * formulaTdee || tdee > 1.4 * formulaTdee) {
      // Ίσως φταίνε παλιές μέρες με ξεχασμένα γεύματα: δοκιμάζεται και το μικρότερο παράθυρο.
      result = (status: AdaptStatus.implausible, est: est);
      continue;
    }
    return (status: AdaptStatus.ok, est: est);
  }
  return result;
}

/// Πρόταση νέου στόχου.
class AdaptProposal {
  const AdaptProposal({
    required this.current,
    required this.target,
    required this.est,
    required this.fastLoss,
    required this.floored,
    this.withinNoise = false,
  });
  final int current;

  /// Ο νέος στόχος (ίδιος με τον τωρινό = «μένει ίδιος»).
  final int target;
  final Expenditure? est;

  /// Πρόταση λόγω γρήγορης απώλειας (> 1% την εβδομάδα).
  final bool fastLoss;
  final bool floored;

  /// Τα δεδομένα έδειχναν αλλαγή, αλλά μικρότερη από το περιθώριο αβεβαιότητας των ζυγίσεων: ο στόχος έμεινε ίδιος (Α1).
  final bool withinNoise;

  int get change => target - current;
  bool get same => change == 0;
}

int _round10(double v) => (v / 10).round() * 10;

/// Ο εβδομαδιαίος έλεγχος: [kgNow] = τρέχον βάρος (τάση ή τελευταία ζύγιση).
AdaptProposal proposeTarget({required Goals goals, required Expenditure est, required double kgNow}) {
  final current = goals.kcal;
  final delta = switch (goals.aim) {
    GoalAim.lose => -kgNow * goals.rate * kcalPerKg / 7,
    GoalAim.gain => kgNow * goals.rate * kcalPerKg / 7,
    GoalAim.keep => 0.0,
  };
  final floor = goals.male ? kcalFloorMale : kcalFloorFemale;
  var want = _round10(est.tdee + delta);
  var floored = false;
  if (want < floor) {
    want = floor;
    floored = true;
  }
  var change = (want - current).clamp(-adaptMaxStep, adaptMaxStep);
  if (change.abs() < adaptMinStep) change = 0;
  // Περιθώριο αβεβαιότητας (Συμβούλιο 2, Α1): διαφορά ως 2 τυπικά σφάλματα της εκτίμησης δεν ξεχωρίζει από τον θόρυβο των
  // ζυγίσεων (νερό, φαγητό). Τότε ο στόχος μένει ίδιος και η κάρτα το λέει.
  final withinNoise = change != 0 && (want - current).abs() <= est.guardKcal;
  if (withinNoise) change = 0;
  var target = current + change;
  if (target < floor) target = floor;
  // «Δεν κατεβαίνει κάτω από το όριο ασφαλείας» μόνο όταν ο νέος στόχος ΕΙΝΑΙ στο όριο (Συμβούλιο 2, μ1). Πριν το έλεγε και
  // όταν το βήμα των 150 τον άφηνε πολύ πιο πάνω (π.χ. 2.000 → 1.850 με όριο 1.500).
  return AdaptProposal(
    current: current,
    target: target,
    est: est,
    fastLoss: false,
    floored: floored && target == floor,
    withinNoise: withinNoise,
  );
}

/// Το παράθυρο της «γρήγορης απώλειας» σήμερα: από πότε ως και σήμερα. Οι [adaptFastWindowDays] τελευταίες μέρες, ΧΩΡΙΣ
/// τις πρώτες [adaptSkipDays] μέρες των στόχων (νερά και γλυκογόνο). null αν η αρχή των στόχων δεν διαβάζεται.
(DateTime, DateTime)? fastLossWindow({required Goals goals, required DateTime today}) {
  final since = DateTime.tryParse(goals.since);
  if (since == null) return null;
  final to = _day(today);
  var from = DateTime(to.year, to.month, to.day - adaptFastWindowDays);
  final firstCounted = DateTime(since.year, since.month, since.day + adaptSkipDays);
  if (from.isBefore(firstCounted)) from = firstCounted;
  return (from, to);
}

/// Οι ζυγίσεις που κρίνουν τη «γρήγορη απώλεια» σήμερα ([fastLossWindow]), παλιότερη πρώτη. Ένα μέρος, για να κρίνει
/// και να δείχνει η κάρτα ακριβώς τις ίδιες ζυγίσεις.
List<(DateTime, double)> fastLossWeights({required Goals goals, required List<(DateTime, double)> weights, required DateTime today}) {
  final window = fastLossWindow(goals: goals, today: today);
  if (window == null) return const [];
  final (from, to) = window;
  return [
    for (final w in weights)
      if (!_day(w.$1).isBefore(from) && !_day(w.$1).isAfter(to)) (_day(w.$1), w.$2),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
}

/// Γρήγορη απώλεια: η κλίση των ζυγίσεων του [fastLossWindow] περνά το −1% του βάρους την εβδομάδα ακόμα και αν της
/// προστεθεί ένα τυπικό σφάλμα (με ≥ 4 ζυγίσεις σε ≥ 10 μέρες). Μόνο σε «λιγότερο λίπος», από τη 14η μέρα των στόχων.
/// Στην πράξη η νωρίτερη ειδοποίηση βγαίνει τη 17η–18η μέρα (10 μέρες ζυγίσεων μετά την πρώτη εβδομάδα).
AdaptProposal? fastLossCheck({required Goals goals, required List<(DateTime, double)> weights, required DateTime today}) {
  if (goals.aim != GoalAim.lose) return null;
  final since = DateTime.tryParse(goals.since);
  if (since == null || daysBetween(since, today) < adaptFastFromDay) return null;
  final ws = fastLossWeights(goals: goals, weights: weights, today: today);
  if (ws.length < 4 || daysBetween(ws.first.$1, ws.last.$1) < 10) return null;
  final fit = weightFit(ws);
  if (fit == null) return null;
  final kg = ws.last.$2;
  // Περιθώριο (Συμβούλιο 2, Α3): η ειδοποίηση βγαίνει μόνο όταν η κλίση είναι πέρα από το όριο κατά ένα τυπικό σφάλμα.
  // Μια ρηχή ζύγιση (αφυδάτωση) δεν φτάνει πια για να τη βγάλει.
  final cautious = fit.slope + adaptFastGuardSe * (fit.se ?? 0.0);
  if (cautious * 7 >= -adaptFastLossPct * kg) return null;
  final current = goals.kcal;
  return AdaptProposal(current: current, target: current + adaptMaxStep, est: null, fastLoss: true, floored: false);
}

/// Μέρα εβδομαδιαίου ελέγχου: η μέρα της εβδομάδας που φτιάχτηκαν οι στόχοι, από την 21η μέρα και μετά. Αν χάθηκε
/// (δεν άνοιξες την εφαρμογή εκείνη τη μέρα), μένει ανοιχτός ως τον επόμενο. Μία φορά για κάθε μέρα ελέγχου.
bool checkInDue({required Goals goals, required DateTime today, String? lastCheckIn}) {
  final since = DateTime.tryParse(goals.since);
  if (since == null) return false;
  final t = _day(today);
  // Ημερολογιακά (Συμβούλιο 2, Σ2). Με «μείον n × 24 ώρες», την εβδομάδα μετά την αλλαγή ώρας του Οκτωβρίου η μέρα ελέγχου
  // έβγαινε 01:00 αντί για 00:00, και ένας έλεγχος που είχες ήδη απαντήσει ξαναέβγαινε· τον Μάρτιο έβγαινε η προηγούμενη
  // μέρα στις 23:00 και ο πρώτος έλεγχος χανόταν για μια εβδομάδα.
  final back = (t.weekday - since.weekday + 7) % 7;
  final dueDay = DateTime(t.year, t.month, t.day - back);
  if (daysBetween(since, dueDay) < adaptWindowDays) return false;
  final last = lastCheckIn == null ? null : DateTime.tryParse(lastCheckIn);
  return last == null || last.isBefore(dueDay);
}

/// Βοηθητικό για προβολή: «−0,4 kg την εβδομάδα».
double roundTo(double v, int digits) {
  final p = math.pow(10, digits);
  return (v * p).round() / p;
}
