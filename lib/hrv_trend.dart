/// Τάση HRV 7 νυχτών (13/11). Μία νύχτα HRV ανεβοκατεβαίνει πολύ από μόνη της· ο μέσος όρος 7 νυχτών είναι πιο σταθερός
/// και συγκρίνεται με το ΔΙΚΟ σου εύρος των προηγούμενων περίπου 2 μηνών (Plews κ.ά. 2013· Buchheit 2014).
///
/// - Οι υπολογισμοί γίνονται στον φυσικό λογάριθμο του RMSSD, όπως στις μελέτες (οι τιμές σε ms δεν είναι συμμετρικές).
/// - «7 νύχτες»: η νύχτα [day] και οι 6 πριν από αυτή. Θέλει τουλάχιστον [hrvWeekMin] από τις 7 (δική μας, συντηρητική
///   επιλογή, ώστε δύο νύχτες να μη λέγονται «εβδομάδα»).
/// - «Το συνηθισμένο σου εύρος»: οι [hrvBaseDays] νύχτες πριν από αυτές τις 7· θέλει τουλάχιστον [hrvBaseMin]. Εύρος =
///   μέσος ± ΜΙΑ τυπική απόκλιση των νυχτών ([hrvBandSd]): εκεί είναι περίπου 2 στις 3 νύχτες σου (κανονική κατανομή).
///   Round 1 (S4-2): πριν ήταν ± μισή τυπική απόκλιση (η «μικρότερη αλλαγή που αξίζει» της αθλητικής βιβλιογραφίας,
///   Plews κ.ά. 2013· Buchheit 2014): είναι όριο αλλαγής, όχι «εύρος». Χωρείς εκεί μόνο το ~38% των δικών σου νυχτών, και
///   ένας άνθρωπος που δεν άλλαξε σε τίποτα έβλεπε «κάτω/πάνω» στο 24–54% των εβδομάδων (αυτοσυσχέτιση φ 0–0,7). Με ± 1
///   τυπική απόκλιση: ~2–19%, και μέσα είναι ~68% των νυχτών σου (προσομοίωση, round 1, f4: sim_hrv.py).
/// - Η θέση (μέσα/κάτω/πάνω) κρίνεται από τα νούμερα όπως φαίνονται (ακέραια ms), ώστε να μη γράφεται «42 ms, πάνω από
///   το εύρος (36–42)».
/// - Μόνο νύχτες της ίδιας πηγής (δεν περνά πάνω από αλλαγή πηγής), όπως το «συνήθως».
/// - Η τεκμηρίωση είναι σε αθλητές αντοχής. Γι' αυτό η εφαρμογή ΜΟΝΟ περιγράφει («μέσα», «κάτω», «πάνω»)· ποτέ δεν δίνει
///   οδηγία προπόνησης ή ερμηνεία υγείας από αυτό.
library;

import 'dart:math' as math;

import 'history.dart';
import 'sources.dart';

const hrvWeekMin = 5;
const hrvBaseDays = 60;
const hrvBaseMin = 21;

/// Το εύρος: μέσος όρος ± τόσες τυπικές αποκλίσεις των νυχτών (σε λογάριθμο).
const hrvBandSd = 1.0;

enum HrvBand { below, within, above }

class HrvTrend {
  const HrvTrend({required this.weekMs, required this.lowMs, required this.highMs, required this.band, required this.weekNights, required this.baseNights});

  /// Ο μέσος όρος των 7 νυχτών (γεωμετρικός, σε ms) και το δικό σου εύρος.
  final double weekMs, lowMs, highMs;
  final HrvBand band;
  final int weekNights, baseNights;
}

/// null όταν δεν υπάρχουν αρκετές νύχτες (ούτε εκτίμηση ούτε «περίπου»).
HrvTrend? hrvTrend(Map<String, Map<String, double>> history, SourcePlan plan, DateTime day) {
  final seg = plan.segmentStart(K.hrv, day);
  double? ln(int back) {
    final d = DateTime(day.year, day.month, day.day - back);
    if (seg != null && d.isBefore(seg)) return null;
    final v = plan.value(history, K.hrv, d);
    return v == null || !v.isFinite || v <= 0 ? null : math.log(v);
  }

  final week = [for (var i = 0; i < 7; i++) ln(i)].whereType<double>().toList();
  if (week.length < hrvWeekMin) return null;
  final base = [for (var i = 7; i < 7 + hrvBaseDays; i++) ln(i)].whereType<double>().toList();
  if (base.length < hrvBaseMin) return null;
  double mean(List<double> v) => v.fold<double>(0, (a, b) => a + b) / v.length;
  // Έλεγχος 17/11 (Κ4-4): μία νύχτα με λάθος (π.χ. 180 ms από έκτακτες συστολές) δεν απλώνει το εύρος για 60 νύχτες:
  // οι τιμές πέρα από διάμεσο ± 3 × MAD × 1,4826 κόβονται σε αυτό το όριο πριν από τον υπολογισμό (winsorize). Χωρίς
  // τέτοιες νύχτες ο υπολογισμός είναι ίδιος με πριν.
  final sorted = [...base]..sort();
  double med(List<double> v) => v.length.isOdd ? v[v.length ~/ 2] : (v[v.length ~/ 2 - 1] + v[v.length ~/ 2]) / 2;
  final md = med(sorted);
  final mad = med([for (final x in sorted) (x - md).abs()]..sort()) * 1.4826;
  final clipped = mad <= 0 ? base : [for (final x in base) x.clamp(md - 3 * mad, md + 3 * mad).toDouble()];
  final mc = mean(clipped);
  final sd = math.sqrt(clipped.fold<double>(0, (a, b) => a + (b - mc) * (b - mc)) / (clipped.length - 1));
  final w = mean(week);
  final lo = mc - hrvBandSd * sd, hi = mc + hrvBandSd * sd;
  final weekMs = math.exp(w), lowMs = math.exp(lo), highMs = math.exp(hi);
  // Από τα νούμερα όπως φαίνονται ([hrvTrendText]: ακέραια ms).
  final shownWeek = weekMs.round(), shownLow = lowMs.round(), shownHigh = highMs.round();
  return HrvTrend(
    weekMs: weekMs,
    lowMs: lowMs,
    highMs: highMs,
    band: shownWeek < shownLow ? HrvBand.below : (shownWeek > shownHigh ? HrvBand.above : HrvBand.within),
    weekNights: week.length,
    baseNights: base.length,
  );
}

/// «7 νύχτες: 42 ms, μέσα στο συνηθισμένο σου εύρος (36–47)» (ή «5 από 7 νύχτες: …»). Μόνο περιγραφή.
String hrvTrendText(HrvTrend t) {
  final where = switch (t.band) {
    HrvBand.below => 'κάτω από το συνηθισμένο σου εύρος',
    HrvBand.within => 'μέσα στο συνηθισμένο σου εύρος',
    HrvBand.above => 'πάνω από το συνηθισμένο σου εύρος',
  };
  // Έλεγχος 20/11 (K3C-07): ο μέσος όρος βγαίνει και από 5 ή 6 νύχτες ([hrvWeekMin])· τότε το λέει («5 από 7 νύχτες»).
  final nights = t.weekNights >= 7 ? '7 νύχτες' : '${t.weekNights} από 7 νύχτες';
  return '$nights: ${t.weekMs.round()} ms, $where (${t.lowMs.round()}–${t.highMs.round()})';
}
