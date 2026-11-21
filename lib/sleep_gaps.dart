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
import 'format.dart' show dayOf;

/// Μέγιστο κενό που εξετάζουμε. Πιο μεγάλο δεν το «γεμίζουμε» ποτέ.
const maxGap = Duration(hours: 4);

/// Πρωινό κομμάτι μετά το ξύπνημα με κενό ως τόσο (και χωρίς βήματα): η ίδια νύχτα, όχι υπνάκος (έλεγχος 2, C1).
/// Απόφαση χρήστη 21/11 (Α9α): πια ως [maxGap] (4 ώρες), όταν το κομμάτι αρχίζει πριν από τις 12:00 και δεν περπάτησες
/// στο μεταξύ. Πριν: ως 90 λεπτά, άρα 03:30–07:00 και 08:40–10:00 έβγαινε «νύχτα + υπνάκος».
const morningJoinGap = maxGap;

/// Απόφαση χρήστη 21/11 (Α10): ύπνος ΠΡΙΝ από τη νύχτα (λαγοκοίμισμα στον καναπέ) ενώνεται με αυτήν μόνο όταν απέχει ως
/// τόσο. Πριν: ως 4 ώρες, άρα καναπές 22:15–23:45 και ύπνος από τις 03:30 έβγαιναν ΜΙΑ νύχτα με «ώρα ύπνου 22:25».
const eveningJoinGap = Duration(hours: 2);

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
/// [stepsTo]: πότε διαβάστηκαν τα βήματα (έλεγχος 4, 1_data M1). Τα λεπτά μετά από αυτό είναι ΑΓΝΩΣΤΑ, όχι 0: αν το
/// κενό περνά πέρα από αυτό, null, εκτός αν τα γνωστά βήματα ήδη ξεπερνούν το [maxGapSteps] (σηκώθηκε, σίγουρα).
int? gapSteps(DateTime start, DateTime end,
    {required Map<int, int> stepsByMinute, required DateTime? stepsFrom, DateTime? stepsTo}) {
  if (stepsFrom == null || start.isBefore(stepsFrom)) return null;
  final cut = stepsTo != null && end.isAfter(stepsTo);
  var steps = 0;
  final from = start.millisecondsSinceEpoch ~/ 60000;
  final to = (cut ? stepsTo : end).millisecondsSinceEpoch ~/ 60000;
  for (var m = from; m < to; m++) {
    steps += stepsByMinute[m] ?? 0;
  }
  if (cut && steps <= maxGapSteps) return null;
  return steps;
}

// ---------------------------------------------------------------------------
// Ο ΕΝΑΣ κανόνας της νύχτας, για το ρολόι ΚΑΙ για το Oura (έλεγχος 3, E1: νέος κανόνας με «κύρια» ομάδα στη νύχτα)
// ---------------------------------------------------------------------------

/// Ένα κομμάτι ύπνου για τον κοινό κανόνα: αρχή, τέλος και λεπτά ύπνου (χωρίς ξυπνήματα όπου είναι γνωστά).
typedef SleepSpan = ({DateTime start, DateTime end, int minutes});

/// Μία νύχτα από τον κοινό κανόνα: η ημερομηνία της (το πρωί) και τα κομμάτια της. Όλα τα κενά μιας νύχτας είναι ως
/// [maxGap] (4 ώρες), άρα ένα ενιαίο «κομμάτι» ([segments] έχει ένα στοιχείο, με τα κομμάτια κατά αρχή).
/// [napLock]: η απόφαση «πρωινός υπνάκος» που πάρθηκε με βήματα (η αρχή του πρώτου κομματιού που έγινε υπνάκος
/// λόγω βημάτων), για να αποθηκευτεί και να μην αλλάξει όταν τα βήματα ανά λεπτό δεν υπάρχουν πια (E1.6).
class NightPieces<T> {
  NightPieces(this.date, this.segments, {this.napLock});
  final DateTime date;
  final List<List<T>> segments;
  final DateTime? napLock;
  List<T> get parts => [for (final s in segments) ...s];
}

class _PieceGroup<T> {
  _PieceGroup(T first, SleepSpan s, SleepSpan w)
      : parts = [first],
        spans = [s],
        walls = [w],
        start = s.start,
        end = s.end,
        wallStart = w.start,
        wallEnd = w.end;
  final List<T> parts;
  final List<SleepSpan> spans;

  /// Round 1 (S5-1): τα ίδια κομμάτια στην ώρα «τοίχου» του τόπου όπου κοιμήθηκες (ίδια με τα [spans] όταν δεν δίνεται
  /// ζώνη). Μόνο για τους κανόνες με ώρα της μέρας· η σειρά και τα κενά μετριούνται πάντα στα [spans].
  final List<SleepSpan> walls;
  final DateTime start;
  DateTime end;
  final DateTime wallStart;
  DateTime wallEnd;

  void add(T p, SleepSpan s, SleepSpan w) {
    parts.add(p);
    spans.add(s);
    walls.add(w);
    if (s.end.isAfter(end)) {
      end = s.end;
      wallEnd = w.end;
    }
  }

  /// Όλα τα λεπτά πραγματικού ύπνου της ομάδας.
  double get totalMinutes => spans.fold<double>(0, (s, x) => s + x.minutes);

  /// Λεπτά ύπνου μέσα στο [from, to) (ώρα «τοίχου»): κάθε κομμάτι κατ' αναλογία του χρόνου του που πέφτει μέσα.
  double minutesWithin(DateTime from, DateTime to) {
    var sum = 0.0;
    for (final s in walls) {
      final len = s.end.difference(s.start).inMilliseconds;
      if (len <= 0) {
        // Κομμάτι χωρίς διάρκεια (π.χ. δεδομένα δοκιμής της Oura): μετρά όλο αν η στιγμή του είναι μέσα.
        if (!s.start.isBefore(from) && s.start.isBefore(to)) sum += s.minutes;
        continue;
      }
      final a = s.start.isAfter(from) ? s.start : from;
      final b = s.end.isBefore(to) ? s.end : to;
      final inside = b.difference(a).inMilliseconds;
      if (inside > 0) sum += s.minutes * inside / len;
    }
    return sum;
  }
}

/// Έλεγχος 4: ελάχιστος πραγματικός ύπνος για να γίνει νύχτα μια ομάδα χωρίς κανένα λεπτό στο [nightWindow] (1β).
const fallbackMainMinutes = 60;

/// Κανόνας 1γ (έλεγχος 20/11, K3C-01): μια επόμενη ομάδα ΧΩΡΙΣ κανένα λεπτό στο 22:00–08:00 (αρχή ως τις 12:00) γίνεται
/// η κύρια όταν έχει περισσότερο πραγματικό ύπνο από ΟΛΗ τη νύχτα όπως βγαίνει ως τώρα, και τουλάχιστον
/// [fallbackMainMinutes] λεπτά. Απόφαση χρήστη 21/11 (Α9β): «πάντα ο μεγαλύτερος». Ως την #150 ήθελε και 2 φορές τη νύχτα
/// και 3 ώρες (mainTakeoverRatio, mainTakeoverMinMinutes).

/// Κανόνας 1γ: πόσες φορές το πολύ ξαναχτίζεται η νύχτα μιας ανάγνωσης (κάθε φορά η κύρια πάει σε μεταγενέστερη ομάδα).
const _takeoverRounds = 6;

/// Το «παράθυρο νύχτας» της ημερομηνίας [date] (το πρωί): 22:00 της προηγούμενης μέρας ως 08:00 (τοπική ώρα).
({DateTime from, DateTime to}) nightWindow(DateTime date) =>
    (from: DateTime(date.year, date.month, date.day - 1, 22), to: DateTime(date.year, date.month, date.day, 8));

/// Η ημερομηνία ενός υπνάκου (ίδια σύμβαση για ρολόι και Oura, όπως το «day» της Oura): αρχή από τις 18:00 και μετά →
/// η επόμενη μέρα (ανήκει στη νύχτα που ακολουθεί), αλλιώς η μέρα που άρχισε.
DateTime napDateOf(DateTime start) => start.hour >= 18 ? DateTime(start.year, start.month, start.day + 1) : dayOf(start);

/// Ο κανόνας της νύχτας, ΙΔΙΟΣ για το ρολόι και το Oura (έλεγχος 3, E1· ο τύπος περιόδου της Oura δεν αποφασίζει):
/// 0. Ομάδα = κομμάτια που αγγίζονται ή επικαλύπτονται (χωρίς κενό).
/// 1. Κύρια ομάδα μιας ημερομηνίας = η ομάδα με τα περισσότερα λεπτά ύπνου μέσα στο 22:00–08:00 ([nightWindow])·
///    ισοπαλία → η νωρίτερη. Ημερομηνία χωρίς καμία τέτοια ομάδα (1β, έλεγχος 4): κύρια η ομάδα με τον περισσότερο
///    πραγματικό ύπνο από όσες αρχίζουν ως τις 12:00 της μέρας, αν έχει ≥ [fallbackMainMinutes] λεπτά (μια ομάδα του
///    βραδιού χωρίς λεπτά στο παράθυρο τελειώνει πριν από τις 22:00: λαγοκοίμισμα, μένει υπνάκος).
///    1γ (έλεγχος 20/11, K3C-01: ύπνος μετά τις 03:00): μια ΕΠΟΜΕΝΗ ομάδα της ίδιας ημερομηνίας, που δεν είναι ήδη
///    μέρος της νύχτας, παίρνει τη θέση της κύριας όταν έχει περισσότερο πραγματικό ύπνο από ΟΛΗ τη νύχτα ως τώρα (κύρια
///    + ό,τι ενώθηκε με τους κανόνες 2–4). Ομάδα με λεπτά στο παράθυρο της ίδιας ημερομηνίας (αρχίζει πριν από τις
///    08:00): αρκεί περισσότερος ύπνος. Ομάδα χωρίς κανένα λεπτό στο παράθυρο, που αρχίζει τη μέρα αυτή πριν από τις
///    12:00: αρκεί κι εδώ περισσότερος ύπνος, με τουλάχιστον [fallbackMainMinutes] λεπτά (απόφαση χρήστη 21/11, Α9β:
///    «πάντα ο μεγαλύτερος»· ως την #150 ήθελε 2 φορές τη νύχτα και 3 ώρες). Έτσι ένα λαγοκοίμισμα 22:15–23:45 δεν
///    γίνεται «νύχτα» αντί για τον ύπνο 06:30–12:30, και στο 03:30–05:15 + 06:50–09:30 κύρια είναι το μεγάλο κομμάτι.
///    Ποτέ προς τα πίσω: ένας μεγάλος βραδινός ύπνος 18:00–22:30 δεν παίρνει τη θέση της νύχτας που ακολουθεί.
/// 2. Ομάδες ΠΡΙΝ από την κύρια: μέρος της νύχτας αν αρχίζουν από τις 20:00 του προηγούμενου βραδιού και μετά ΚΑΙ το
///    κενό ως την (ήδη ενωμένη) νύχτα είναι ως [eveningJoinGap] (2 ώρες· απόφαση χρήστη 21/11, Α10· πριν 4 ώρες)·
///    αλλιώς υπνάκος.
/// 3. Ομάδες ΜΕΤΑ από την κύρια που αρχίζουν πριν από τις 06:00: μέρος της νύχτας αν το κενό είναι ως 4 ώρες· αλλιώς
///    υπνάκος.
/// 4. Ομάδες ΜΕΤΑ από την κύρια που αρχίζουν από τις 06:00 και πριν από τις 12:00: μέρος της νύχτας αν το κενό είναι
///    ως [morningJoinGap] (4 ώρες· απόφαση χρήστη 21/11, Α9α· πριν 90 λεπτά) ΚΑΙ τα βήματα στο κενό είναι ως
///    [maxGapSteps] ή άγνωστα· αλλιώς υπνάκος. Από τις 12:00 και μετά: πάντα υπνάκος.
/// 5. Βήματα ([stepsBetween]): από τα βήματα ανά λεπτό του ΡΟΛΟΓΙΟΥ, και για τις νύχτες του Oura (μόνο ώρες· κρίνουν
///    μόνο το κενό, δεν φαίνονται πουθενά). null = άγνωστα.
/// 6. Η απόφαση «υπνάκος λόγω βημάτων» ΚΛΕΙΔΩΝΕΙ ([NightPieces.napLock] → αποθηκεύεται)· όταν τα βήματα δεν υπάρχουν
///    πια, [napLockOf] τη δίνει πίσω για την ίδια ημερομηνία και δεν αλλάζει ποτέ σε «μέρος της νύχτας» (ανάγνωση 30
///    ημερών, συμπλήρωση, επανανάγνωση). Χωρίς βήματα και χωρίς αποθηκευμένη απόφαση: μέρος της νύχτας. Μόνη εξαίρεση
///    (1β, 1γ): όταν η κύρια δεν βγήκε από το παράθυρο, ένα κλείδωμα ως την αρχή της είχε παρθεί με άλλη κύρια και
///    αγνοείται.
/// 7. Τα κενά δεν μετρούν ποτέ ως ύπνος· οι υπνάκοι επιστρέφονται χωριστά ανά ημερομηνία ([napDateOf]).
/// Ημερομηνία νύχτας: η ημερομηνία του παραθύρου της κύριας ομάδας, ή [dateOf] (Oura: το «day» της Oura) αν δοθεί.
/// [sorted]: τα κομμάτια ταξινομημένα κατά αρχή.
/// [wall] (round 1, S5-1): το ίδιο κομμάτι στην ώρα «τοίχου» του τόπου όπου κοιμήθηκες (Oura: η ζώνη ώρας της ίδιας
/// της εγγραφής). Οι κανόνες με ώρα της μέρας (22:00–08:00, 20:00, 06:00, 12:00, 18:00) κρίνονται εκεί, ώστε μια
/// νύχτα 7 ωρών να μένει νύχτα όπου κι αν βρίσκεται το κινητό όταν τη διαβάζει. Η σειρά, η επικάλυψη, τα κενά (4 ώρες,
/// 90 λεπτά), τα βήματα και οι αποθηκευμένες αποφάσεις μετριούνται πάντα στον πραγματικό χρόνο ([span]). Χωρίς [wall]
/// (ρολόι, ή εγγραφή χωρίς ζώνη): η ώρα του κινητού, όπως πάντα.
({List<NightPieces<T>> nights, Map<DateTime, List<T>> naps}) groupSleepPieces<T>(
  List<T> sorted,
  SleepSpan Function(T) span, {
  int? Function(DateTime from, DateTime to)? stepsBetween,
  DateTime Function(List<T> parts)? dateOf,
  DateTime? Function(DateTime date)? napLockOf,
  SleepSpan Function(T)? wall,
}) {
  // 0. Ομάδες χωρίς κενό.
  final groups = <_PieceGroup<T>>[];
  for (final r in sorted) {
    final s = span(r);
    final w = wall == null ? s : wall(r);
    final last = groups.isEmpty ? null : groups.last;
    if (last != null && !s.start.isAfter(last.end)) {
      last.add(r, s, w);
    } else {
      groups.add(_PieceGroup<T>(r, s, w));
    }
  }

  // 1. Κύρια ομάδα ανά ημερομηνία: κάθε ομάδα «διεκδικεί» την ημερομηνία όπου έχει τα περισσότερα λεπτά στο παράθυρο.
  final windowMain = <DateTime, int>{};
  final mainMinutes = <DateTime, double>{};
  // Η ημερομηνία που διεκδικεί κάθε ομάδα με τα λεπτά της στο παράθυρο (null: κανένα λεπτό σε κανένα παράθυρο).
  final claim = List<DateTime?>.filled(groups.length, null);
  for (var i = 0; i < groups.length; i++) {
    final g = groups[i];
    DateTime? best;
    var bestMin = 0.0;
    final last = DateTime(g.wallEnd.year, g.wallEnd.month, g.wallEnd.day + 1);
    for (var d = dayOf(g.wallStart); !d.isAfter(last); d = DateTime(d.year, d.month, d.day + 1)) {
      final w = nightWindow(d);
      final m = g.minutesWithin(w.from, w.to);
      if (m > bestMin) {
        bestMin = m;
        best = d;
      }
    }
    if (best == null) continue;
    claim[i] = best;
    final prev = mainMinutes[best];
    if (prev == null || bestMin > prev) {
      windowMain[best] = i;
      mainMinutes[best] = bestMin;
    }
  }

  // Οι κανόνες 1β και 2–4 για δοσμένες κύριες ([forced]: οι κύριες που διάλεξε το 1γ, ανά ημερομηνία).
  ({List<MapEntry<DateTime, int>> mains, List<int?> owner, Map<DateTime, DateTime> locks}) assign(Map<DateTime, int> forced) {
    final mainOf = <DateTime, int>{...windowMain, ...forced};
    // Κύριες που ΔΕΝ βγήκαν από το παράθυρο (1β και 1γ): μια αποθηκευμένη απόφαση «υπνάκος» ως την αρχή τους είχε παρθεί
    // χωρίς κύρια ομάδα ή με άλλη κύρια, και δεν μετρά.
    final fallback = <int>{...forced.values};
    // 1β. Έλεγχος 4 (νύχτα με όλο τον ύπνο το πρωί, π.χ. 08:30–13:00: κανένα λεπτό στο 22:00–08:00 → η νύχτα χανόταν).
    // Ημερομηνία χωρίς κύρια ομάδα: κύρια γίνεται η ομάδα με τον περισσότερο πραγματικό ύπνο ανάμεσα σε όσες αρχίζουν ως
    // τις 12:00 της μέρας (ισοπαλία → η νωρίτερη), μόνο αν έχει τουλάχιστον [fallbackMainMinutes] λεπτά. Μετά οι ίδιοι
    // κανόνες ένωσης. Η νύχτα ανήκει στη μέρα που ξυπνάς.
    final mainSet = mainOf.values.toSet();
    final fallbackOf = <DateTime, int>{};
    for (var i = 0; i < groups.length; i++) {
      if (mainSet.contains(i)) continue;
      final st = groups[i].wallStart;
      // Ομάδα του βραδιού (20:00 και μετά) χωρίς κανένα λεπτό στο 22:00–08:00 τελειώνει πριν από τις 22:00: είναι
      // λαγοκοίμισμα και μένει υπνάκος (όπως πριν). Άρα υποψήφιες μόνο όσες αρχίζουν τη μέρα που ξυπνάς, ως τις 12:00.
      if (st.hour >= 12) continue;
      final d = dayOf(st);
      if (mainOf.containsKey(d)) continue;
      final total = groups[i].totalMinutes;
      if (total < fallbackMainMinutes) continue;
      final prev = fallbackOf[d];
      if (prev == null || total > groups[prev].totalMinutes) fallbackOf[d] = i;
    }
    for (final e in fallbackOf.entries) {
      mainOf[e.key] = e.value;
      fallback.add(e.value);
    }
    final mains = mainOf.entries.toList()..sort((a, b) => a.value.compareTo(b.value));

    // Ποια νύχτα (δείκτης κύριας ομάδας) κρατά κάθε ομάδα· null = υπνάκος.
    final owner = List<int?>.filled(groups.length, null);
    for (final m in mains) {
      owner[m.value] = m.value;
    }
    // 2. Πριν από την κύρια (πρώτα αυτά: ένα βραδινό κομμάτι πριν από τη νύχτα ανήκει σε αυτήν).
    for (final m in mains) {
      final date = m.key;
      final evening = DateTime(date.year, date.month, date.day - 1, 20);
      var nightStart = groups[m.value].start;
      for (var j = m.value - 1; j >= 0 && owner[j] == null; j--) {
        final g = groups[j];
        if (g.wallStart.isBefore(evening) || nightStart.difference(g.end) > eveningJoinGap) break;
        owner[j] = m.value;
        nightStart = g.start;
      }
    }
    // 3–4. Μετά από την κύρια.
    final locks = <DateTime, DateTime>{};
    for (final m in mains) {
      final date = m.key;
      // Το κλειδί της αποθηκευμένης απόφασης: η ημερομηνία της νύχτας (Oura: το «day» της κύριας ομάδας).
      final lockKey = dateOf?.call(groups[m.value].parts) ?? date;
      final six = DateTime(date.year, date.month, date.day, 6);
      final noon = DateTime(date.year, date.month, date.day, 12);
      var nightEnd = groups[m.value].end;
      for (var j = m.value + 1; j < groups.length && owner[j] == null; j++) {
        final g = groups[j];
        final gap = g.start.difference(nightEnd);
        final bool joins;
        if (g.wallStart.isBefore(six)) {
          joins = gap <= maxGap;
        } else if (gap > morningJoinGap || !g.wallStart.isBefore(noon)) {
          // Α9α (21/11): ως 4 ώρες, μόνο το πρωί· ύπνος από τις 12:00 και μετά είναι υπνάκος.
          joins = false;
        } else {
          final steps = stepsBetween?.call(nightEnd, g.start);
          if (steps != null) {
            joins = steps <= maxGapSteps;
            if (!joins) locks[m.key] ??= g.start;
          } else {
            var lock = napLockOf?.call(lockKey);
            // Κύρια από το 1β ή το 1γ: μια αποθηκευμένη απόφαση ως την αρχή της είχε παρθεί χωρίς κύρια ομάδα (κανόνες
            // ως v3) ή με άλλη κύρια (πριν από το 1γ)· δεν μετρά (σαν να μην υπάρχει).
            if (lock != null && fallback.contains(m.value) && !lock.isAfter(groups[m.value].start)) lock = null;
            joins = lock == null || g.start.isBefore(lock);
            if (!joins) locks[m.key] ??= lock;
          }
        }
        if (!joins) break;
        owner[j] = m.value;
        if (g.end.isAfter(nightEnd)) nightEnd = g.end;
      }
    }
    return (mains: mains, owner: owner, locks: locks);
  }

  // 1γ. Έλεγχος 20/11 (K3C-01, και K3-review R1/R2): μια ΕΠΟΜΕΝΗ ομάδα της ίδιας ημερομηνίας, που ΔΕΝ είναι ήδη μέρος
  // κάποιας νύχτας, γίνεται κύρια όταν έχει περισσότερο πραγματικό ύπνο από ΟΛΗ τη νύχτα όπως βγαίνει ως τώρα (κύρια + ό,τι
  // ενώθηκε μαζί της με τους κανόνες 2–4), όχι από ένα κομμάτι της. Η νωρίτερη που περνά γίνεται κύρια, η νύχτα ξαναχτίζεται
  // και ο έλεγχος επαναλαμβάνεται (το πολύ [_takeoverRounds] φορές· η κύρια πάει πάντα προς τα μετά, άρα τελειώνει).
  final forced = <DateTime, int>{};
  var a = assign(forced);
  for (var round = 0; round < _takeoverRounds; round++) {
    var changed = false;
    for (final m in a.mains) {
      final date = m.key, w = m.value;
      // Κύρια από το 1β (καμία ομάδα με λεπτά στο παράθυρο): δεν αλλάζει.
      if (claim[w] != date && !forced.containsKey(date)) continue;
      var night = 0.0;
      for (var i = 0; i < groups.length; i++) {
        if (a.owner[i] == w) night += groups[i].totalMinutes;
      }
      final limit = DateTime(date.year, date.month, date.day + 2);
      for (var i = w + 1; i < groups.length; i++) {
        final g = groups[i];
        if (g.wallStart.isAfter(limit)) break;
        if (a.owner[i] != null) continue; // ήδη μέρος κάποιας νύχτας
        final total = g.totalMinutes;
        final c = claim[i];
        final bool takes;
        if (c != null) {
          // (α) Με λεπτά στο παράθυρο της ίδιας ημερομηνίας (αρχίζει πριν από τις 08:00): αρκεί περισσότερος ύπνος.
          takes = c == date && total > night;
        } else {
          // (β) Χωρίς κανένα λεπτό στο παράθυρο, αρχή τη μέρα αυτή πριν από τις 12:00: 2 φορές τη νύχτα, και 3 ώρες, εκτός
          // αν η «νύχτα» ως τώρα είναι λαγοκοίμισμα κάτω από [fallbackMainMinutes] λεπτά (τότε αρκεί το όριο του 1β).
          // Απόφαση χρήστη 21/11 (Α9β): πάντα ο μεγαλύτερος ύπνος (με τουλάχιστον [fallbackMainMinutes] λεπτά). Πριν: 2 φορές
          // τη νύχτα και 3 ώρες, άρα 80 λεπτά στις 04:30 και 165 από τις 08:05 έβγαινε «νύχτα 80 λεπτά, υπνάκος 165».
          final st = g.wallStart;
          takes = st.hour < 12 && dayOf(st) == date && total >= fallbackMainMinutes && total > night;
        }
        if (takes) {
          forced[date] = i;
          changed = true;
          break;
        }
      }
    }
    if (!changed) break;
    a = assign(forced);
  }
  final mains = a.mains, owner = a.owner, locks = a.locks;

  // 7. Νύχτες και υπνάκοι.
  final naps = <DateTime, List<T>>{};
  final byMain = <int, List<T>>{};
  for (var i = 0; i < groups.length; i++) {
    final o = owner[i];
    if (o == null) {
      final g = groups[i];
      naps.putIfAbsent(dateOf?.call(g.parts) ?? napDateOf(g.wallStart), () => []).addAll(g.parts);
    } else {
      byMain.putIfAbsent(o, () => []).addAll(groups[i].parts);
    }
  }
  final byDate = <DateTime, ({List<T> parts, DateTime? lock})>{};
  for (final m in mains) {
    final parts = byMain[m.value]!;
    final date = dateOf?.call(parts) ?? m.key;
    final old = byDate[date];
    // Δύο κύριες ομάδες με την ίδια ημερομηνία του Oura (σχεδόν ποτέ): μία νύχτα, χωρίς να μετρά το κενό.
    byDate[date] = old == null
        ? (parts: parts, lock: locks[m.key])
        : (parts: [...old.parts, ...parts], lock: old.lock ?? locks[m.key]);
  }
  final nights = <NightPieces<T>>[
    for (final e in byDate.entries) NightPieces<T>(e.key, [e.value.parts], napLock: e.value.lock),
  ]..sort((a, b) => a.date.compareTo(b.date));
  return (nights: nights, naps: naps);
}
