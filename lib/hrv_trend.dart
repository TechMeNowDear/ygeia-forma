/// Τάση HRV 7 νυχτών (13/11). Μία νύχτα HRV ανεβοκατεβαίνει πολύ από μόνη της· ο μέσος όρος 7 νυχτών είναι πιο σταθερός
/// και συγκρίνεται με το ΔΙΚΟ σου εύρος των προηγούμενων περίπου 2 μηνών (Plews κ.ά. 2013· Buchheit 2014).
///
/// - Οι υπολογισμοί γίνονται στον φυσικό λογάριθμο του RMSSD, όπως στις μελέτες (οι τιμές σε ms δεν είναι συμμετρικές).
/// - «7 νύχτες»: η νύχτα [day] και οι 6 πριν από αυτή. Θέλει τουλάχιστον [hrvWeekMin] από τις 7 (δική μας, συντηρητική
///   επιλογή, ώστε δύο νύχτες να μη λέγονται «εβδομάδα»).
/// - «Το δικό σου εύρος»: οι [hrvBaseDays] νύχτες πριν από αυτές τις 7· θέλει τουλάχιστον [hrvBaseMin]. Εύρος = μέσος ±
///   μισή τυπική απόκλιση («η μικρότερη αλλαγή που αξίζει», Buchheit 2014).
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
  final m = mean(base);
  final sd = math.sqrt(base.fold<double>(0, (a, b) => a + (b - m) * (b - m)) / (base.length - 1));
  final w = mean(week);
  final lo = m - 0.5 * sd, hi = m + 0.5 * sd;
  return HrvTrend(
    weekMs: math.exp(w),
    lowMs: math.exp(lo),
    highMs: math.exp(hi),
    band: w < lo ? HrvBand.below : (w > hi ? HrvBand.above : HrvBand.within),
    weekNights: week.length,
    baseNights: base.length,
  );
}

/// «7 νύχτες: 42 ms, μέσα στο δικό σου εύρος (38–47)». Μόνο περιγραφή.
String hrvTrendText(HrvTrend t) {
  final where = switch (t.band) {
    HrvBand.below => 'κάτω από το δικό σου εύρος',
    HrvBand.within => 'μέσα στο δικό σου εύρος',
    HrvBand.above => 'πάνω από το δικό σου εύρος',
  };
  return '7 νύχτες: ${t.weekMs.round()} ms, $where (${t.lowMs.round()}–${t.highMs.round()})';
}
