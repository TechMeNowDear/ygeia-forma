/// Αυτόματη διόρθωση θερμίδων (συμφωνία 11/11, πριν από τις 7/12): από τα δικά σου δεδομένα, όχι από τύπο.
///
/// Ισοζύγιο ενέργειας: πραγματική κατανάλωση ≈ μέσες θερμίδες που έφαγες − (αλλαγή βάρους × 7.700 kcal/kg) / μέρες
/// (Hall 2008· η ίδια ιδέα με το MacroFactor). Κανένας αριθμός από AI: μόνο ό,τι έγραψες και ό,τι ζύγισε η ζυγαριά.
///
/// Κανόνες (όλοι εδώ, ένα μέρος):
/// - Παράθυρο: οι 21 τελευταίες ΤΕΛΕΙΩΜΕΝΕΣ μέρες (όχι σήμερα).
/// - Μέρα φαγητού που μετρά: τουλάχιστον 60% του στόχου θερμίδων. Λιγότερο σημαίνει σχεδόν πάντα ότι κάτι δεν γράφτηκε·
///   τέτοιες μέρες βγαίνουν από τον μέσο όρο (δεν θεωρούνται «λίγο φαγητό»).
/// - Χρειάζονται ≥ 14 τέτοιες μέρες και ≥ 6 ζυγίσεις που απλώνονται σε ≥ 14 μέρες. Αλλιώς: «λίγα δεδομένα», καμία πρόταση.
/// - Τάση βάρους: ευθεία ελαχίστων τετραγώνων στις ζυγίσεις του παραθύρου (τα νερά μιας μέρας δεν την κουνάνε πολύ).
/// - Αν η εκτίμηση βγει έξω από 70–140% του τύπου, κάτι λείπει (π.χ. μέρες χωρίς καταγραφή): καμία πρόταση.
/// - Νέος στόχος = εκτίμηση ± όσο χρειάζεται ο ρυθμός σου, στρογγυλεμένος στα 10, ποτέ κάτω από το όριο ασφαλείας,
///   και το πολύ ±150 kcal ανά εβδομαδιαίο έλεγχο. Αλλαγή κάτω από 30 kcal: «μένει ίδιος».
/// - Γρήγορη απώλεια: αν στις 14 τελευταίες μέρες χάνεις πάνω από 1% του βάρους την εβδομάδα, πρόταση +150 kcal αμέσως
///   (κρατά τους μύες· Helms 2014, Garthe 2011), από τη 14η μέρα και μετά (η πρώτη εβδομάδα έχει νερά και γλυκογόνο).
library;

import 'dart:math' as math;

import 'format.dart' show daysBetween;
import 'goals.dart';

const adaptWindowDays = 21;
const adaptMinIntakeDays = 14;
const adaptMinWeighIns = 6;
const adaptMinSpanDays = 14;
const adaptFullDayShare = 0.6;
const adaptMaxStep = 150;
const adaptMinStep = 30;
const adaptFastLossPct = 0.01;
const adaptFastWindowDays = 14;

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Κλίση (kg ανά μέρα) με ελάχιστα τετράγωνα· null με λιγότερα από 2 σημεία ή όλα την ίδια μέρα.
double? weightSlope(List<(DateTime, double)> weights) {
  if (weights.length < 2) return null;
  final t0 = weights.first.$1;
  final xs = [for (final w in weights) w.$1.difference(t0).inHours / 24.0];
  final ys = [for (final w in weights) w.$2];
  final mx = xs.reduce((a, b) => a + b) / xs.length;
  final my = ys.reduce((a, b) => a + b) / ys.length;
  var sxx = 0.0, sxy = 0.0;
  for (var i = 0; i < xs.length; i++) {
    sxx += (xs[i] - mx) * (xs[i] - mx);
    sxy += (xs[i] - mx) * (ys[i] - my);
  }
  if (sxx < 1e-9) return null;
  return sxy / sxx;
}

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
}

enum AdaptStatus { ok, tooEarly, fewIntakeDays, fewWeighIns, implausible }

/// [intake]: θερμίδες ανά μέρα (όπως φαίνονται στη Διατροφή). [weights]: ζυγίσεις (μία ανά μέρα). [today]: σήμερα·
/// το παράθυρο τελειώνει χθες. [formulaTdee]: ο τύπος, για τον έλεγχο λογικής. [goalKcal]: για το «60% του στόχου».
({AdaptStatus status, Expenditure? est}) estimateExpenditure({
  required Map<DateTime, double> intake,
  required List<(DateTime, double)> weights,
  required DateTime today,
  required double formulaTdee,
  required int goalKcal,
}) {
  final to = _day(today).subtract(const Duration(days: 1));
  final from = DateTime(to.year, to.month, to.day - (adaptWindowDays - 1));
  bool inWindow(DateTime d) => !_day(d).isBefore(from) && !_day(d).isAfter(to);

  final full = adaptFullDayShare * goalKcal;
  final days = [
    for (final e in intake.entries)
      if (inWindow(e.key) && e.value >= full) e.value,
  ];
  final ws = [
    for (final w in weights)
      if (inWindow(w.$1) && w.$2 >= 30 && w.$2 <= 300) (_day(w.$1), w.$2),
  ]..sort((a, b) => a.$1.compareTo(b.$1));

  if (days.length < adaptMinIntakeDays) return (status: AdaptStatus.fewIntakeDays, est: null);
  if (ws.length < adaptMinWeighIns || daysBetween(ws.first.$1, ws.last.$1) < adaptMinSpanDays) {
    return (status: AdaptStatus.fewWeighIns, est: null);
  }
  final slope = weightSlope(ws);
  if (slope == null) return (status: AdaptStatus.fewWeighIns, est: null);
  final mean = days.reduce((a, b) => a + b) / days.length;
  final tdee = mean - slope * kcalPerKg;
  final est = Expenditure(
    tdee: tdee,
    meanIntake: mean,
    slopeKgWeek: slope * 7,
    intakeDays: days.length,
    weighIns: ws.length,
    from: from,
    to: to,
  );
  if (tdee < 0.7 * formulaTdee || tdee > 1.4 * formulaTdee) return (status: AdaptStatus.implausible, est: est);
  return (status: AdaptStatus.ok, est: est);
}

/// Πρόταση νέου στόχου.
class AdaptProposal {
  const AdaptProposal({required this.current, required this.target, required this.est, required this.fastLoss, required this.floored});
  final int current;

  /// Ο νέος στόχος (ίδιος με τον τωρινό = «μένει ίδιος»).
  final int target;
  final Expenditure? est;

  /// Πρόταση λόγω γρήγορης απώλειας (> 1% την εβδομάδα).
  final bool fastLoss;
  final bool floored;

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
  var target = current + change;
  if (target < floor) target = floor;
  return AdaptProposal(current: current, target: target, est: est, fastLoss: false, floored: floored);
}

/// Γρήγορη απώλεια: κλίση των 14 τελευταίων ημερών < −1% του βάρους την εβδομάδα (με ≥ 4 ζυγίσεις σε ≥ 10 μέρες).
/// Μόνο σε «λιγότερο λίπος» και από τη 14η μέρα των στόχων.
AdaptProposal? fastLossCheck({required Goals goals, required List<(DateTime, double)> weights, required DateTime today}) {
  if (goals.aim != GoalAim.lose) return null;
  final since = DateTime.tryParse(goals.since);
  if (since == null || daysBetween(since, today) < adaptFastWindowDays) return null;
  final to = _day(today);
  final from = to.subtract(const Duration(days: adaptFastWindowDays));
  final ws = [
    for (final w in weights)
      if (!_day(w.$1).isBefore(from) && !_day(w.$1).isAfter(to)) (_day(w.$1), w.$2),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  if (ws.length < 4 || daysBetween(ws.first.$1, ws.last.$1) < 10) return null;
  final slope = weightSlope(ws);
  if (slope == null) return null;
  final kg = ws.last.$2;
  if (slope * 7 >= -adaptFastLossPct * kg) return null;
  final current = goals.kcal;
  return AdaptProposal(current: current, target: current + adaptMaxStep, est: null, fastLoss: true, floored: false);
}

/// Μέρα εβδομαδιαίου ελέγχου: η μέρα της εβδομάδας που φτιάχτηκαν οι στόχοι, από την 21η μέρα και μετά. Αν χάθηκε
/// (δεν άνοιξες την εφαρμογή εκείνη τη μέρα), μένει ανοιχτός ως τον επόμενο. Μία φορά για κάθε μέρα ελέγχου.
bool checkInDue({required Goals goals, required DateTime today, String? lastCheckIn}) {
  final since = DateTime.tryParse(goals.since);
  if (since == null) return false;
  final t = _day(today);
  final dueDay = t.subtract(Duration(days: (t.weekday - since.weekday + 7) % 7));
  if (daysBetween(since, dueDay) < adaptWindowDays) return false;
  final last = lastCheckIn == null ? null : DateTime.tryParse(lastCheckIn);
  return last == null || last.isBefore(dueDay);
}

/// Βοηθητικό για προβολή: «−0,4 kg την εβδομάδα».
double roundTo(double v, int digits) {
  final p = math.pow(10, digits);
  return (v * p).round() / p;
}
