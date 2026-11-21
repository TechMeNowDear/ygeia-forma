// Χαμένη προπόνηση (αποφάσεις 20/11: «ό,τι κρίνεις πιο σωστό επιστημονικά»).
//
// Κανόνας: κάθε μυϊκή ομάδα καλό είναι να δουλεύει τουλάχιστον 2 φορές την εβδομάδα (με ίδιο όγκο, 2 φορές είναι καλύτερα
// από 1 για τους μύες: Schoenfeld κ.ά., Sports Med 2016;46:1689–97· ACSM 2026, Currier κ.ά., MSSE 58:851–872), άρα μια
// χαμένη προπόνηση αξίζει να αναπληρωθεί· και τα ίδια μέρη θέλουν περίπου 48 ώρες πριν ξαναδουλέψουν (ACSM 2011, Garber
// κ.ά., MSSE 43:1334–59). Έλεγχος 20/11 (K4-S-05): πριν το σχόλιο απέδιδε τις 48 ώρες στο ACSM 2009 (δεν υπάρχουν εκεί)
// και στο Schoenfeld 2016 κάτι που δεν λέει. Άρα μια χαμένη προπόνηση με βάρη προτείνεται ΜΙΑ φορά, σε μέρα που:
// - δεν έχει δική της προπόνηση με βάρη (ξεκούραση ή μόνο περπάτημα· ποτέ δύο προπονήσεις με βάρη την ίδια μέρα),
// - δεν έγινε προπόνηση με βάρη χθες και δεν είναι προγραμματισμένη αύριο (ποτέ δύο βαριές μέρες στη σειρά),
// - απέχει ως 2 μέρες από τη χαμένη.
// Αλλιώς προσπερνιέται και το πρόγραμμα συνεχίζει κανονικά. Τίποτα δεν αλλάζει μόνο του: η κάρτα ρωτά.
library;

import 'program.dart';
import 'session.dart';
import 'training_day.dart';

/// Ως πόσες μέρες πίσω ψάχνει χαμένη προπόνηση.
const catchUpDays = 2;

// Α13 (21/11): μέρες προπόνησης ([trainingDay]): η μέρα αλλάζει στις 04:00. Μια προπόνηση στις 00:30 του Σαββάτου είναι
// της Παρασκευής.
DateTime _day(DateTime t) => trainingDay(t);

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
  if (_strengthOn(sessions, yesterday) || _plannedStrength(p, tomorrow)) return null;
  for (var k = 1; k <= catchUpDays; k++) {
    final d = DateTime(today.year, today.month, today.day - k);
    if (p.notStarted(d)) break;
    final w = p.forDay(d);
    if (w == null || w.isCardio) continue;
    // Έγινε εκείνη τη μέρα ή μετά (π.χ. την έκανες ήδη την επόμενη): τίποτα χαμένο.
    final done = sessions.any((s) => s.finished && !s.isCardio && s.workout == w.id && !_day(s.start).isBefore(d));
    if (done) return null;
    // Έγινε άλλη προπόνηση με βάρη στη θέση της (την ίδια μέρα): δεν χάθηκε.
    if (_strengthOn(sessions, d)) return null;
    return (workout: w, missed: d);
  }
  return null;
}
