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
import 'format.dart' show dayOf, sameDay;

/// Μέγιστο κενό που εξετάζουμε. Πιο μεγάλο δεν το «γεμίζουμε» ποτέ.
const maxGap = Duration(hours: 4);

/// Πρωινό κομμάτι μετά το ξύπνημα με κενό ως τόσο (και χωρίς βήματα): η ίδια νύχτα, όχι υπνάκος (έλεγχος 2, C1).
const morningJoinGap = Duration(minutes: 90);

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

  final steps = gapSteps(gapStart, gapEnd, stepsByMinute: stepsByMinute, stepsFrom: stepsFrom);
  if (steps == null) return GapVerdict.noStepData;
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

/// Βήματα στο διάστημα [start, end), ή null αν δεν ξέρουμε ότι μετρήθηκαν (λεπτά χωρίς βήματα δεν υπάρχουν
/// στον πίνακα, οπότε χωρίς [stepsFrom] πριν από την αρχή δεν ξεχωρίζει το «0 βήματα» από το «δεν μετρήθηκε»).
int? gapSteps(DateTime start, DateTime end, {required Map<int, int> stepsByMinute, required DateTime? stepsFrom}) {
  if (stepsFrom == null || start.isBefore(stepsFrom)) return null;
  var steps = 0;
  final from = start.millisecondsSinceEpoch ~/ 60000;
  final to = end.millisecondsSinceEpoch ~/ 60000;
  for (var m = from; m < to; m++) {
    steps += stepsByMinute[m] ?? 0;
  }
  return steps;
}

// ---------------------------------------------------------------------------
// Ο ΕΝΑΣ κανόνας της νύχτας, για το ρολόι ΚΑΙ για το Oura (έλεγχος 2, C1 + U12, συγχώνευση 4/11)
// ---------------------------------------------------------------------------

/// Ένα κομμάτι ύπνου για τον κοινό κανόνα: αρχή, τέλος και λεπτά ύπνου (χωρίς ξυπνήματα όπου είναι γνωστά).
typedef SleepSpan = ({DateTime start, DateTime end, int minutes});

/// Μία νύχτα από τον κοινό κανόνα: η ημερομηνία της (το πρωί) και τα κομμάτια της σε ομάδες. Κάθε ομάδα έχει
/// κομμάτια με κενό ως [maxGap]· δύο ομάδες στην ίδια νύχτα = ίδια ημερομηνία, χωρίς να είναι υπνάκος η μία.
class NightPieces<T> {
  NightPieces(this.date, this.segments);
  final DateTime date;
  final List<List<T>> segments;
  List<T> get parts => [for (final s in segments) ...s];
}

class _PieceGroup<T> {
  _PieceGroup(T first, SleepSpan s, {required this.isNight})
      : parts = [first],
        start = s.start,
        end = s.end,
        minutes = s.minutes;
  final List<T> parts;
  final bool isNight;
  final DateTime start;
  DateTime end;
  int minutes;

  void add(T p, SleepSpan s) {
    parts.add(p);
    if (s.end.isAfter(end)) end = s.end;
    minutes += s.minutes;
  }
}

/// Ο κανόνας της νύχτας, ΙΔΙΟΣ για το ρολόι και το Oura (ο τύπος περιόδου της Oura δεν αποφασίζει):
/// - Κομμάτι συνεχίζει τη νύχτα αν το κενό από το προηγούμενο είναι ως [maxGap] (4 ώρες), ανεξάρτητα από βήματα ή
///   παλμούς. Το κενό δεν μετρά ποτέ ως ύπνος.
/// - Υπνάκος είναι μόνο: (α) βραδινό λαγοκοίμισμα που αρχίζει μετά το μεσημέρι και τελειώνει ως τις 22:00 της ίδιας
///   μέρας· (β) κομμάτι που αρχίζει 06:00–20:00 μετά το τέλος της νύχτας, εκτός αν το κενό είναι ως [morningJoinGap]
///   (90 λεπτά) ΚΑΙ τα βήματα του κενού είναι ως [maxGapSteps] ή άγνωστα ([stepsBetween] null ή επιστρέφει null· το
///   Oura δεν έχει βήματα, άρα «άγνωστα»)· (γ) απογευματινός: αρχίζει 10:00–18:00 και κρατά λιγότερο από 3 ώρες.
/// - Δύο ομάδες με την ίδια ημερομηνία (κενό πάνω από 4 ώρες): η μεγαλύτερη που δεν είναι λαγοκοίμισμα είναι η νύχτα·
///   η άλλη είναι υπνάκος μόνο κατά τα (α)/(β), αλλιώς μέρος της νύχτας (το κενό δεν μετρά). Μόνο λαγοκοίμισμα, χωρίς
///   νύχτα: υπνάκος.
/// - Ημερομηνία ([dateOf]): εξ ορισμού το πρωί του τέλους (τέλος μετά τις 18:00 → η επόμενη μέρα)· ο απογευματινός
///   υπνάκος στη μέρα που άρχισε. Το Oura δίνει τη δική του μέρα ανά περίοδο (ίδια λογική) και τη χρησιμοποιεί.
/// [sorted]: τα κομμάτια ταξινομημένα κατά αρχή. Οι υπνάκοι επιστρέφονται ανά ημερομηνία νύχτας.
({List<NightPieces<T>> nights, Map<DateTime, List<T>> naps}) groupSleepPieces<T>(
  List<T> sorted,
  SleepSpan Function(T) span, {
  int? Function(DateTime from, DateTime to)? stepsBetween,
  DateTime Function(List<T> parts)? dateOf,
}) {
  final groups = <_PieceGroup<T>>[];
  _PieceGroup<T>? previous;
  for (final r in sorted) {
    final s = span(r);
    final g = previous;
    if (g != null && g.isNight && _joinsNight(g, s, stepsBetween)) {
      g.add(r, s);
      continue;
    }
    final isNap = s.start.hour >= 10 && s.start.hour < 18 && s.minutes < 180;
    final ng = _PieceGroup<T>(r, s, isNight: !isNap);
    groups.add(ng);
    previous = ng;
  }

  final naps = <DateTime, List<T>>{};
  final byDate = <DateTime, List<_PieceGroup<T>>>{};
  for (final g in groups) {
    if (!g.isNight) {
      // Απογευματινός υπνάκος: της νύχτας με την ίδια ημερομηνία (το πρωί της ίδιας μέρας).
      naps.putIfAbsent(dateOf?.call(g.parts) ?? dayOf(g.start), () => []).addAll(g.parts);
      continue;
    }
    final e = g.end;
    final date = dateOf?.call(g.parts) ?? (e.hour >= 18 ? DateTime(e.year, e.month, e.day + 1) : dayOf(e));
    byDate.putIfAbsent(date, () => []).add(g);
  }

  final nights = <NightPieces<T>>[];
  for (final entry in byDate.entries) {
    final list = entry.value..sort((a, b) => a.start.compareTo(b.start));
    final candidates = [for (final g in list) if (!_eveningDoze(g.start, g.end)) g];
    if (candidates.isEmpty) {
      // Μόνο βραδινό λαγοκοίμισμα (π.χ. ανάγνωση στις 22:30, πριν από τον ύπνο): υπνάκος, ποτέ «η νύχτα».
      for (final g in list) {
        naps.putIfAbsent(entry.key, () => []).addAll(g.parts);
      }
      continue;
    }
    final main = candidates.reduce((a, b) => a.minutes >= b.minutes ? a : b);
    final segments = <List<T>>[];
    for (final g in list) {
      if (!identical(g, main) &&
          (_eveningDoze(g.start, g.end) || _startsMorningNap(g.start, main.end, stepsBetween))) {
        naps.putIfAbsent(entry.key, () => []).addAll(g.parts);
        continue;
      }
      segments.add(g.parts);
    }
    nights.add(NightPieces(entry.key, segments));
  }
  nights.sort((a, b) => a.date.compareTo(b.date));
  return (nights: nights, naps: naps);
}

/// Αν το κομμάτι [s] συνεχίζει την ομάδα [g] (ίδια νύχτα): κενό ως 4 ώρες, εκτός αν η ομάδα είναι βραδινό
/// λαγοκοίμισμα ή το [s] πρωινός υπνάκος. Συνεχόμενα ή επικαλυπτόμενα κομμάτια: πάντα μαζί.
bool _joinsNight<T>(_PieceGroup<T> g, SleepSpan s, int? Function(DateTime, DateTime)? stepsBetween) {
  final gap = s.start.difference(g.end);
  if (gap <= Duration.zero) return true;
  if (gap > maxGap) return false;
  if (_eveningDoze(g.start, g.end)) return false;
  return !_startsMorningNap(s.start, g.end, stepsBetween);
}

/// Βραδινό λαγοκοίμισμα: αρχίζει μετά το μεσημέρι και τελειώνει την ίδια μέρα ως τις 22:00.
bool _eveningDoze(DateTime s, DateTime e) =>
    s.hour >= 12 && sameDay(s, e) && !e.isAfter(DateTime(e.year, e.month, e.day, 22));

/// Πρωινός υπνάκος: κομμάτι που αρχίζει 06:00–20:00, μετά το τέλος της νύχτας ([nightEnd]). Είναι η ίδια νύχτα
/// (όχι υπνάκος) αν το κενό είναι ως [morningJoinGap] ΚΑΙ τα βήματα του κενού είναι άγνωστα ή ως [maxGapSteps].
/// Κομμάτια που αρχίζουν 20:00–06:00 δεν κρίνονται εδώ (πάντα νύχτα).
bool _startsMorningNap(DateTime start, DateTime nightEnd, int? Function(DateTime, DateTime)? stepsBetween) {
  if (start.hour < 6 || start.hour >= 20 || !start.isAfter(nightEnd)) return false;
  if (start.difference(nightEnd) > morningJoinGap) return true;
  final steps = stepsBetween?.call(nightEnd, start);
  return steps != null && steps > maxGapSteps;
}
