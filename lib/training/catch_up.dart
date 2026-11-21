// Χαμένη προπόνηση (αποφάσεις 20/11: «ό,τι κρίνεις πιο σωστό επιστημονικά»).
//
// Κανόνας: κάθε μυϊκή ομάδα καλό είναι να δουλεύει τουλάχιστον 2 φορές την εβδομάδα (με ίδιο όγκο, 2 φορές είναι καλύτερα
// από 1 για τους μύες: Schoenfeld κ.ά., Sports Med 2016;46:1689–97· ACSM 2026, Currier κ.ά., MSSE 58:851–872), άρα μια
// χαμένη προπόνηση αξίζει να αναπληρωθεί· και τα ίδια μέρη θέλουν περίπου 48 ώρες πριν ξαναδουλέψουν (ACSM 2011, Garber
// κ.ά., MSSE 43:1334–59). Έλεγχος 20/11 (K4-S-05): πριν το σχόλιο απέδιδε τις 48 ώρες στο ACSM 2009 (δεν υπάρχουν εκεί)
// και στο Schoenfeld 2016 κάτι που δεν λέει. Άρα μια χαμένη προπόνηση με βάρη προτείνεται ΜΙΑ φορά, σε μέρα που:
// - δεν έχει δική της προπόνηση με βάρη (ξεκούραση ή μόνο περπάτημα· ποτέ δύο προπονήσεις με βάρη την ίδια μέρα),
// - δεν έγινε χθες προπόνηση με βάρη για τους ΙΔΙΟΥΣ μύες και δεν είναι προγραμματισμένη αύριο (48 ώρες στους ίδιους
//   μύες· απόφαση χρήστη 21/11, Α14: πριν μετρούσε κάθε προπόνηση με βάρη, άρα σε πρόγραμμα «Πάνω/Κάτω» τέσσερις μέρες
//   στη σειρά δεν χωρούσε ποτέ· μια χαμένη «Πάνω» της Κυριακής χωρά πια την Τρίτη, μετά από «Κάτω» τη Δευτέρα),
// - απέχει ως 2 μέρες από τη χαμένη.
// «Ίδιοι μύες»: κοινή ομάδα της βιβλιοθήκης ασκήσεων (στήθος, χέρια, κοιλιακοί, πλάτη, ώμοι, πόδια). Όταν η βιβλιοθήκη
// δεν έχει φορτώσει, ή η προπόνηση δεν είναι του προγράμματος (ελεύθερη), μετρά ως ίδιοι μύες (όπως πριν).
// Αλλιώς προσπερνιέται και το πρόγραμμα συνεχίζει κανονικά. Τίποτα δεν αλλάζει μόνο του: η κάρτα ρωτά.
library;

import '../exercise/ex_data.dart' show ExLibrary;
import 'program.dart';
import 'session.dart';
import 'training_day.dart';

/// Ως πόσες μέρες πίσω ψάχνει χαμένη προπόνηση.
const catchUpDays = 2;

// Α13 (21/11): μέρες προπόνησης ([trainingDay]): η μέρα αλλάζει στις 04:00. Μια προπόνηση στις 00:30 του Σαββάτου είναι
// της Παρασκευής.
DateTime _day(DateTime t) => trainingDay(t);

/// Α14 (21/11): οι ομάδες μυών μιας προπόνησης ([ExLibrary]). null = άγνωστες (μετρούν ως ίδιοι μύες με όλα).
Set<String>? _groups(Workout? w) {
  final lib = ExLibrary.loaded;
  if (w == null || lib == null) return null;
  final out = <String>{};
  for (final i in w.items) {
    final g = lib.byId(i.ex)?.group;
    if (g == null) return null;
    out.add(g);
  }
  return out;
}

/// Α14 (21/11): οι δύο προπονήσεις δουλεύουν (ή μπορεί να δουλεύουν) κοινούς μύες.
bool _sameMuscles(Workout? a, Workout? b) {
  final x = _groups(a), y = _groups(b);
  return x == null || y == null || x.intersection(y).isNotEmpty;
}

/// Α14 (21/11): έγινε τη μέρα [day] προπόνηση με βάρη που δουλεύει κοινούς μύες με την [w].
bool _sameMusclesOn(Program p, Iterable<Session> sessions, DateTime day, Workout w) {
  final a = _day(day), b = DateTime(a.year, a.month, a.day + 1);
  return sessions.any((s) =>
      s.finished && !s.isCardio && !_day(s.start).isBefore(a) && _day(s.start).isBefore(b) && _sameMuscles(p.workout(s.workout), w));
}

bool _strengthOn(Iterable<Session> sessions, DateTime day) {
  // Έλεγχος 20/11 (K6C-05): η επόμενη ΗΜΕΡΟΛΟΓΙΑΚΗ μέρα, όχι «+24 ώρες»: στις αλλαγές ώρας η μέρα έχει 25 ή 23 ώρες, και
  // μια προπόνηση στις 23:30 της Κυριακής 31/10/2027 δεν μετρούσε ως Κυριακής («χαμένη προπόνηση» που είχε γίνει).
  final a = _day(day), b = DateTime(a.year, a.month, a.day + 1);
  return sessions.any((s) => s.finished && !s.isCardio && !_day(s.start).isBefore(a) && _day(s.start).isBefore(b));
}

bool _plannedStrength(Program p, DateTime day) {
  final w = p.forDay(day);
  return w != null && !w.isCardio;
}

/// Η χαμένη προπόνηση που χωρά σήμερα, και η μέρα που χάθηκε· null αν δεν χωρά (ή δεν χάθηκε καμία).
({Workout workout, DateTime missed})? missedToCatchUp(Program p, Iterable<Session> sessions, DateTime now) {
  final today = _day(now);
  if (p.notStarted(today)) return null;
  if (_plannedStrength(p, today) || _strengthOn(sessions, today)) return null;
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  for (var k = 1; k <= catchUpDays; k++) {
    final d = DateTime(today.year, today.month, today.day - k);
    if (p.notStarted(d)) break;
    final w = p.forDay(d);
    if (w == null || w.isCardio) continue;
    // Έγινε εκείνη τη μέρα ή μετά (π.χ. την έκανες ήδη την επόμενη): αυτή δεν χάθηκε. Α14 (21/11): ψάχνει και πιο πίσω
    // (πριν σταματούσε εδώ: η «Πάνω» της Κυριακής δεν προτεινόταν ποτέ αφού έγινε η «Κάτω» της Δευτέρας). Όταν η
    // βιβλιοθήκη ασκήσεων δεν έχει φορτώσει, η χθεσινή προπόνηση μετρά ως ίδιοι μύες και δεν προτείνεται τίποτα (όπως πριν).
    final done = sessions.any((s) => s.finished && !s.isCardio && s.workout == w.id && !_day(s.start).isBefore(d));
    if (done) continue;
    // Έγινε άλλη προπόνηση με βάρη στη θέση της (την ίδια μέρα): δεν χάθηκε.
    if (_strengthOn(sessions, d)) return null;
    // Α14 (21/11): 48 ώρες στους ίδιους μύες: όχι αν χθες έγινε, ή αύριο είναι προγραμματισμένη, προπόνηση για τους ίδιους.
    if (_sameMusclesOn(p, sessions, yesterday, w)) return null;
    final next = p.forDay(tomorrow);
    if (next != null && !next.isCardio && _sameMuscles(next, w)) return null;
    return (workout: w, missed: d);
  }
  return null;
}
