// Χαμένη προπόνηση (αποφάσεις 20/11: «ό,τι κρίνεις πιο σωστό επιστημονικά»).
//
// Κανόνας: για τη δύναμη μετρά η συνολική δουλειά της εβδομάδας περισσότερο από την ακριβή μέρα (Schoenfeld 2016,
// συχνότητα με ίδιο όγκο), και τα ίδια μέρη θέλουν περίπου 48 ώρες πριν ξαναδουλέψουν βαριά (ACSM 2009, θέση για την
// προπόνηση με αντιστάσεις). Άρα μια χαμένη προπόνηση με βάρη προτείνεται ΜΙΑ φορά, σε μέρα που:
// - δεν έχει δική της προπόνηση με βάρη (ξεκούραση ή μόνο περπάτημα· ποτέ δύο προπονήσεις με βάρη την ίδια μέρα),
// - δεν έγινε προπόνηση με βάρη χθες και δεν είναι προγραμματισμένη αύριο (ποτέ δύο βαριές μέρες στη σειρά),
// - απέχει ως 2 μέρες από τη χαμένη.
// Αλλιώς προσπερνιέται και το πρόγραμμα συνεχίζει κανονικά. Τίποτα δεν αλλάζει μόνο του: η κάρτα ρωτά.
library;

import 'program.dart';
import 'session.dart';

/// Ως πόσες μέρες πίσω ψάχνει χαμένη προπόνηση.
const catchUpDays = 2;

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

bool _strengthOn(Iterable<Session> sessions, DateTime day) {
  final a = _day(day), b = a.add(const Duration(days: 1));
  return sessions.any((s) => s.finished && !s.isCardio && !s.start.isBefore(a) && s.start.isBefore(b));
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
    final done = sessions.any((s) => s.finished && !s.isCardio && s.workout == w.id && !s.start.isBefore(d));
    if (done) return null;
    // Έγινε άλλη προπόνηση με βάρη στη θέση της (την ίδια μέρα): δεν χάθηκε.
    if (_strengthOn(sessions, d)) return null;
    return (workout: w, missed: d);
  }
  return null;
}
