/// Κενά ανάμεσα σε κομμάτια ύπνου που η Samsung «έκοψε» ενώ ο χρήστης κοιμόταν.
///
/// Η Samsung συχνά σπάει μία νύχτα σε 2–3 κομμάτια (έλεγχος 26/10 στα δεδομένα του χρήστη:
/// 9 από 16 νύχτες). Το ρολόι όμως συνεχίζει να μετρά παλμούς και βήματα μέσα στο κενό.
/// Αν στο κενό **δεν υπάρχουν βήματα** και **οι παλμοί μένουν στο επίπεδο του ύπνου**,
/// τα δύο κομμάτια ανήκουν στην ίδια νύχτα και το κενό φαίνεται ως «πιθανός ύπνος».
/// Από 1/11 το κενό **δεν** προστίθεται στη διάρκεια: δεν ξεχωρίζει ύπνο από ξάπλωμα ξύπνιος.
///
/// Δικός μας κανόνας, όχι ελεγμένος σε εργαστήριο ύπνου (απόφαση χρήστη 26/10, αλλαγή 1/11).
library;

import 'data.dart' show Sample, SleepRecord;

/// Μέγιστο κενό που εξετάζουμε. Πιο μεγάλο δεν το «γεμίζουμε» ποτέ.
const maxGap = Duration(hours: 4);

/// Μέχρι τόσα βήματα σε όλο το κενό (π.χ. μια κίνηση του χεριού που μετρήθηκε ως βήμα).
const maxGapSteps = 30;

/// Οι παλμοί στο κενό επιτρέπεται να είναι έως τόσο πάνω από τους παλμούς του ύπνου.
const maxHrRise = 5.0;

/// Αποτέλεσμα του ελέγχου, με τον λόγο (για «Πώς υπολογίστηκε» και για τους ελέγχους).
enum GapVerdict { asleep, tooLong, noStepData, steps, noHeartData, heartHigh }

GapVerdict judgeGap(
  SleepRecord a,
  SleepRecord b, {
  required List<Sample> heart,
  required Map<int, int> stepsByMinute,
  required DateTime? stepsFrom,
}) {
  final gapStart = a.end;
  final gapEnd = b.start;
  final gap = gapEnd.difference(gapStart);
  if (gap <= Duration.zero) return GapVerdict.asleep; // συνεχόμενα ή επικαλυπτόμενα κομμάτια
  if (gap > maxGap) return GapVerdict.tooLong;

  // Βήματα: πρέπει να ξέρουμε ότι μετρήθηκαν (λεπτά χωρίς βήματα δεν υπάρχουν στον πίνακα).
  if (stepsFrom == null || gapStart.isBefore(stepsFrom)) return GapVerdict.noStepData;
  var steps = 0;
  final from = gapStart.millisecondsSinceEpoch ~/ 60000;
  final to = gapEnd.millisecondsSinceEpoch ~/ 60000;
  for (var m = from; m < to; m++) {
    steps += stepsByMinute[m] ?? 0;
  }
  if (steps > maxGapSteps) return GapVerdict.steps;

  // Παλμοί: στο κενό αρκετές μετρήσεις (μία ανά 30 λεπτά τουλάχιστον) και κοντά σε αυτούς του ύπνου.
  // Μέτρηση μέσα στο διάστημα [start, end): με διάρκεια που το τέμνει, ή στιγμιαία μέσα του.
  bool overlaps(Sample s, DateTime start, DateTime end) =>
      s.start.isBefore(end) && (s.end.isAfter(start) || (s.end == s.start && !s.start.isBefore(start)));
  final gapSamples = [for (final s in heart) if (overlaps(s, gapStart, gapEnd)) s];
  final inGap = [for (final s in gapSamples) s.avg];
  final inSleep = [
    for (final s in heart)
      if (overlaps(s, a.start, a.end) || overlaps(s, b.start, b.end)) s.avg,
  ];
  // Κάλυψη: τουλάχιστον μία μέτρηση σε **κάθε** μισάωρο του κενού (όχι απλώς αρκετές μετρήσεις
  // συνολικά, που μπορεί να είναι όλες στην αρχή, π.χ. πριν μπει το ρολόι στον φορτιστή).
  for (var slot = gapStart; slot.isBefore(gapEnd); slot = slot.add(const Duration(minutes: 30))) {
    final slotEnd = slot.add(const Duration(minutes: 30)).isBefore(gapEnd) ? slot.add(const Duration(minutes: 30)) : gapEnd;
    if (!gapSamples.any((s) => overlaps(s, slot, slotEnd))) return GapVerdict.noHeartData;
  }
  if (inGap.isEmpty || inSleep.length < 3) return GapVerdict.noHeartData;
  double mean(List<double> v) => v.reduce((x, y) => x + y) / v.length;
  if (mean(inGap) > mean(inSleep) + maxHrRise) return GapVerdict.heartHigh;

  return GapVerdict.asleep;
}
