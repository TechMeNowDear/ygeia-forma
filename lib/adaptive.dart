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
///
/// Έλεγχος 13/11 (γύρος 1). Όλοι οι κανόνες αποδείχθηκαν πρώτα με αριθμούς (αντίγραφο σε Python) και μετά γράφτηκαν εδώ:
/// - Κενό καταγραφής (S1-1, [foodGap]): κανένα παράθυρο δεν περιέχει [adaptGapDays] ή περισσότερες συνεχόμενες μέρες που
///   δεν μετρούν. Ο μέσος όρος φαγητού βγαίνει μόνο από τις γραμμένες μέρες, η κλίση του βάρους από όλες: με δύο εβδομάδες
///   διακοπών χωρίς καταγραφή η εκτίμηση έβγαινε 280–510 kcal χαμηλά και ο στόχος κατέβαινε 150–450 kcal για 3–4
///   εβδομάδες. Τώρα το παράθυρο ξεκινά μετά το κενό· ως τότε η κάρτα το λέει και ο στόχος μένει ίδιος.
/// - Μέρα με αδύνατα πολλές θερμίδες (S11-3, [absurdDayKcal]): δεν μπαίνει στον μέσο όρο (π.χ. 2000 g αντί για 20 g).
/// - Γρήγορη απώλεια (S1-2): η πρόταση δεν περνά ποτέ όσα καις ([fastLossCap])· και δεν γίνεται καθόλου όταν το
///   ημερολόγιο δείχνει ότι τρως πολύ κάτω από τον στόχο (τότε δεν φταίει ο στόχος): αυτό το κρίνει το adaptive_check.dart.
/// - Απόσταση αλλαγών (S1-4, [adaptMinChangeDays]): έλεγχος που απαντήθηκε λιγότερο από 4 μέρες πριν από μια μέρα
///   ελέγχου καλύπτει και αυτήν (πριν: δύο βήματα των 150 kcal μέσα σε 24 ώρες, με τα ίδια δεδομένα).
///
/// Έλεγχος 13/11 (γύρος 2, g1). Πάλι πρώτα με αριθμούς σε Python, μετά εδώ:
/// - Το κενό ψάχνεται [adaptScanDays] μέρες πίσω (R2-A-2): και ένα κενό που άρχισε πριν από τις 42 μέρες κόβει το
///   παράθυρο. Πριν, έξι εβδομάδες μετά από μια αρρώστια χωρίς καταγραφή το παράθυρο άρχιζε ΜΕΣΑ στο κενό (με τις
///   ζυγίσεις της αρρώστιας) και η κάρτα πρότεινε −130 kcal χωρίς λόγο.
/// - Η απόσταση των 4 ημερών μετρά μόνο μετά από απάντηση που ΑΛΛΑΞΕ τον στόχο (R2-A-5, [answerChangedTarget]). Ένα
///   «Εντάξει» αργά (π.χ. την Παρασκευή, στο «μαζεύω δεδομένα») δεν μεταθέτει πια την πρώτη εκτίμηση κατά μία εβδομάδα.
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

/// Τόσες συνεχόμενες μέρες που δεν μετρούν (καθόλου ή λίγη καταγραφή) είναι «κενό καταγραφής»: κανένα παράθυρο δεν το
/// περιέχει (έλεγχος 13/11, S1-1). Ένα Σαββατοκύριακο ή ένα τριήμερο δεν φτάνει· μια εβδομάδα διακοπών ναι.
const adaptGapDays = 5;

/// Πόσες μέρες πίσω (ως χθες) ψάχνεται το κενό καταγραφής, άρα και πόσες μέρες ημερολογίου χρειάζεται ο έλεγχος (γύρος 2,
/// R2-A-2): το μεγαλύτερο παράθυρο και [adaptGapDays] − 1 μέρες πριν από αυτό. Έτσι πιάνεται και κενό που άρχισε πριν από
/// το παράθυρο και φτάνει μέσα του. Όποιος καλεί το [estimateExpenditure] διαβάζει το φαγητό τόσες μέρες πίσω· αλλιώς οι
/// μέρες που δεν διαβάστηκαν μοιάζουν με μέρες χωρίς φαγητό.
const adaptScanDays = adaptMaxWindowDays + adaptGapDays - 1;

/// Ελάχιστες μέρες ανάμεσα σε δύο αλλαγές του στόχου, και από ένα «Εφάρμοσε» ως την επόμενη μέρα ελέγχου (S1-4, R2-A-5).
const adaptMinChangeDays = 4;

/// Μέρα με περισσότερες θερμίδες από αυτό δεν μπαίνει στον μέσο όρο: σχεδόν σίγουρα λάθος ποσότητα (S11-3).
/// Το μεγαλύτερο από 6.000 kcal και 2,5 φορές όσα καις κατά τον τύπο. Για σύγκριση: η πρόσληψη που αντέχει το πεπτικό
/// για πολλές μέρες είναι περίπου 2,5 φορές ο ΒΑΣΙΚΟΣ μεταβολισμός (Thurber 2019, Science Advances)· το όριο εδώ είναι
/// 2,5 φορές η ΣΥΝΟΛΙΚΗ κατανάλωση, δηλαδή πάνω και από αυτό. Μία μέρα μπορεί θεωρητικά να το περάσει (διαγωνισμός
/// φαγητού)· είναι δική μας επιλογή για λάθη πληκτρολόγησης, όχι ιατρικό όριο. Η μέρα μένει στο ημερολόγιο όπως είναι.
const adaptAbsurdKcal = 6000.0;
const adaptAbsurdTimes = 2.5;

double absurdDayKcal(double formulaTdee) => math.max(adaptAbsurdKcal, adaptAbsurdTimes * formulaTdee);

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

enum AdaptStatus {
  ok,
  tooEarly,
  fewIntakeDays,
  fewWeighIns,
  implausible,

  /// Κενό καταγραφής που κρατά ως και χθες ([foodGap] χωρίς «restart»): καμία εκτίμηση.
  gapOpen,

  /// Μετά από κενό καταγραφής δεν έχουν μαζευτεί ακόμα [adaptWindowDays] μέρες: καμία εκτίμηση.
  afterGap,
}

/// Κενό καταγραφής: από [from] ως και [to] καμία μέρα δεν μετρά. [restart]: η πρώτη μέρα που μετρά μετά το κενό (από
/// εκεί και πέρα ξαναρχίζει η εκτίμηση)· null όταν το κενό κρατά ως και χθες.
typedef FoodGap = ({DateTime from, DateTime to, DateTime? restart});

/// Το τελευταίο κενό καταγραφής ως χθες: [adaptGapDays] ή περισσότερες συνεχόμενες μέρες χωρίς φαγητό που μετρά (κάτω
/// από το 60% του στόχου, καθόλου καταγραφή, ή πάνω από το [absurdDayKcal]). Ψάχνει [adaptScanDays] μέρες πίσω, χωρίς την
/// πρώτη εβδομάδα των στόχων. null: κανένα κενό, ή καμία μέρα που να μετρά (τότε η κάρτα λέει «λίγα δεδομένα», όπως πριν).
/// Χωρίς [since] το ημερολόγιο θεωρείται ότι αρχίζει στην πρώτη μέρα που μετρά: οι μέρες πριν από αυτήν δεν είναι κενό.
/// Γύρος 2 (R2-A-2): πριν έψαχνε μόνο τις 42 μέρες του μεγαλύτερου παραθύρου, και ένα κενό που είχε αρχίσει νωρίτερα
/// μετρούσε μόνο με το κομμάτι του μέσα σε αυτές· κάτω από 5 μέρες «δεν ήταν κενό» και το παράθυρο άρχιζε μέσα του.
/// Τώρα κάθε κενό που φτάνει μέσα στις 42 μέρες φαίνεται ολόκληρο (ως 4 μέρες πριν από αυτές, που φτάνουν για τις 5).
FoodGap? foodGap({
  required Map<DateTime, double> intake,
  required DateTime today,
  required double formulaTdee,
  required int goalKcal,
  DateTime? since,
}) {
  final t = _day(today);
  final to = DateTime(t.year, t.month, t.day - 1);
  var lo = DateTime(to.year, to.month, to.day - (adaptScanDays - 1));
  if (since != null) {
    final firstCounted = DateTime(since.year, since.month, since.day + adaptSkipDays);
    if (lo.isBefore(firstCounted)) lo = firstCounted;
  }
  final full = adaptFullDayShare * goalKcal;
  final over = absurdDayKcal(formulaTdee);
  final counted = <DateTime>{};
  for (final e in intake.entries) {
    final d = _day(e.key);
    if (e.value >= full && e.value <= over && !d.isBefore(lo) && !d.isAfter(to)) counted.add(d);
  }
  if (counted.isEmpty) return null;
  FoodGap? gap;
  var run = 0;
  var seen = since != null;
  var runStart = lo;
  for (var d = lo; !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
    if (counted.contains(d)) {
      if (seen && run >= adaptGapDays) gap = (from: runStart, to: DateTime(d.year, d.month, d.day - 1), restart: d);
      run = 0;
      seen = true;
    } else {
      if (run == 0) runStart = d;
      run++;
    }
  }
  if (run >= adaptGapDays) return (from: runStart, to: to, restart: null);
  return gap;
}

/// [intake]: θερμίδες ανά μέρα (όπως φαίνονται στη Διατροφή), τουλάχιστον [adaptScanDays] μέρες πίσω από χθες (για το
/// κενό καταγραφής). [weights]: ζυγίσεις (μία ανά μέρα). [today]: σήμερα·
/// το παράθυρο τελειώνει χθες. [formulaTdee]: ο τύπος, για τον έλεγχο λογικής. [goalKcal]: για το «60% του στόχου».
/// [since]: η μέρα που ξεκίνησαν οι στόχοι· οι πρώτες [adaptSkipDays] μέρες δεν μετρούν (null: μετρούν όλες).
///
/// Δοκιμάζει τα παράθυρα του [adaptWindows] από το μεγαλύτερο: επιστρέφει το πρώτο που έχει αρκετά δεδομένα και λογική
/// εκτίμηση. Αν κανένα, την κατάσταση του μικρότερου (21 μέρες), ώστε η κάρτα να λέει τι λείπει «στις 3 τελευταίες
/// εβδομάδες». [AdaptStatus.tooEarly]: δεν έχουν περάσει ακόμα 21 μέρες που μετρούν.
/// Έλεγχος 13/11: κανένα παράθυρο δεν αρχίζει πριν από το τέλος του τελευταίου κενού καταγραφής ([foodGap])·
/// [AdaptStatus.gapOpen] / [AdaptStatus.afterGap] όταν γι' αυτό δεν χωρά ακόμα παράθυρο 21 ημερών. Μέρες πάνω από το
/// [absurdDayKcal] δεν μετρούν.
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
  var available = firstCounted == null ? adaptMaxWindowDays : daysBetween(firstCounted, to) + 1;
  if (available < adaptWindowDays) return (status: AdaptStatus.tooEarly, est: null);

  final full = adaptFullDayShare * goalKcal;
  final over = absurdDayKcal(formulaTdee);
  // Κενό καταγραφής (S1-1): το παράθυρο δεν αρχίζει πριν από την πρώτη μέρα που μετρά μετά το κενό.
  final gap = foodGap(intake: intake, today: t, formulaTdee: formulaTdee, goalKcal: goalKcal, since: since);
  if (gap != null) {
    final restart = gap.restart;
    if (restart == null) return (status: AdaptStatus.gapOpen, est: null);
    final after = daysBetween(restart, to) + 1;
    if (after < adaptWindowDays) return (status: AdaptStatus.afterGap, est: null);
    if (after < available) available = after;
  }
  ({AdaptStatus status, Expenditure? est}) result = (status: AdaptStatus.fewIntakeDays, est: null);
  for (final windowDays in adaptWindows) {
    if (windowDays > available) continue;
    final from = DateTime(to.year, to.month, to.day - (windowDays - 1));
    bool inWindow(DateTime d) => !_day(d).isBefore(from) && !_day(d).isAfter(to);
    final need = adaptNeeds(windowDays);
    final days = [
      for (final e in intake.entries)
        if (inWindow(e.key) && e.value >= full && e.value <= over) e.value,
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

/// Γρήγορη απώλεια, η μέτρηση: η κλίση των ζυγίσεων του [fastLossWindow] περνά το −1% του βάρους την εβδομάδα ακόμα και
/// αν της προστεθεί ένα τυπικό σφάλμα (με ≥ 4 ζυγίσεις σε ≥ 10 μέρες). Μόνο σε «λιγότερο λίπος», από τη 14η μέρα των
/// στόχων. Στην πράξη η νωρίτερη ειδοποίηση βγαίνει τη 17η–18η μέρα (10 μέρες ζυγίσεων μετά την πρώτη εβδομάδα).
/// Επιστρέφει την κλίση (kg την εβδομάδα, αρνητική) και το βάρος της τελευταίας ζύγισης· null όταν δεν ισχύει.
({double slopeKgWeek, double kg})? fastLossSlope({required Goals goals, required List<(DateTime, double)> weights, required DateTime today}) {
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
  return (slopeKgWeek: fit.slope * 7, kg: kg);
}

/// Πάνω από εδώ η «γρήγορη απώλεια» δεν ανεβάζει τον στόχο (έλεγχος 13/11, S1-2): όσα καις, από την τελευταία εκτίμηση
/// με τα δεδομένα σου, αλλιώς από τον τύπο, στα 10. Πριν, το +150 επαναλαμβανόταν κάθε εβδομάδα χωρίς τέλος και ο στόχος
/// «λιγότερο λίπος» έφτανε πάνω από την κατανάλωση.
int fastLossCap(Goals goals) => _round10(goals.tdeeEst ?? goals.calc.tdee);

/// Γρήγορη απώλεια, η πρόταση: +[adaptMaxStep] kcal, ποτέ πάνω από το [fastLossCap]. null όταν η [fastLossSlope] δεν
/// ισχύει ή όταν ο στόχος είναι ήδη εκεί (μένουν λιγότερες από [adaptMinStep] kcal ως το όριο).
AdaptProposal? fastLossCheck({required Goals goals, required List<(DateTime, double)> weights, required DateTime today}) {
  if (fastLossSlope(goals: goals, weights: weights, today: today) == null) return null;
  final current = goals.kcal;
  final target = math.min(current + adaptMaxStep, fastLossCap(goals));
  if (target - current < adaptMinStep) return null;
  return AdaptProposal(current: current, target: target, est: null, fastLoss: true, floored: false);
}

/// Μέρα εβδομαδιαίου ελέγχου: η μέρα της εβδομάδας που φτιάχτηκαν οι στόχοι, από την 21η μέρα και μετά. Αν χάθηκε
/// (δεν άνοιξες την εφαρμογή εκείνη τη μέρα), μένει ανοιχτός ως τον επόμενο. Μία φορά για κάθε μέρα ελέγχου.
/// Έλεγχος 13/11 (S1-4): έλεγχος που απαντήθηκε με «Εφάρμοσε» λιγότερο από [adaptMinChangeDays] μέρες πριν από μια μέρα
/// ελέγχου καλύπτει και αυτήν. Πριν, απάντηση την Κυριακή και νέα κάρτα τη Δευτέρα έδιναν δύο βήματα (−290 kcal) σε 24 ώρες.
/// Γύρος 2 (R2-A-5): μόνο όταν η απάντηση ΑΛΛΑΞΕ τον στόχο ([answerChangedTarget]). Μια απάντηση που δεν άλλαξε τίποτα
/// («Εντάξει», «Όχι τώρα») καλύπτει μόνο τις μέρες ελέγχου ως και τη μέρα της, όπως πριν από το S1-4.
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
  if (last == null) return true;
  if (answerChangedTarget(goals, last)) return daysBetween(last, dueDay) >= adaptMinChangeDays;
  return daysBetween(last, dueDay) > 0;
}

/// Την [day] άλλαξε ο στόχος από κάρτα («Εφάρμοσε»: εβδομαδιαίος έλεγχος ή γρήγορη απώλεια)· από το ιστορικό [Goals.log].
bool answerChangedTarget(Goals goals, DateTime day) {
  for (final l in goals.log) {
    if (!l.applied) continue;
    final d = DateTime.tryParse(l.day);
    if (d != null && daysBetween(d, day) == 0) return true;
  }
  return false;
}

/// Βοηθητικό για προβολή: «−0,4 kg την εβδομάδα».
double roundTo(double v, int digits) {
  final p = math.pow(10, digits);
  return (v * p).round() / p;
}
