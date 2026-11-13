/// Παλμοί ανά σετ και ανά διάλειμμα, από τις ώρες των ✓ και τους παλμούς του ρολογιού (9/11).
///
/// Ορισμοί (ίδιοι στην οθόνη, στο ⓘ και στις δοκιμές):
/// - «♥ σετ»: ο μέσος όρος των παλμών στα [setWindow] δευτερόλεπτα ως το ✓ του σετ. Ένα σετ 8–12 επαναλήψεων
///   κρατά περίπου τόσο· με σταθερό παράθυρο τα σετ συγκρίνονται μεταξύ τους χωρίς να ξέρουμε πότε ξεκίνησε το καθένα.
/// - «♥ διάλειμμα»: ο μέσος όρος των τελευταίων [restWindow] δευτερολέπτων πριν από την αρχή του επόμενου σετ (οι
///   παλμοί λίγο πριν ξαναρχίσεις). Μόνο αν το διάλειμμα κράτησε τουλάχιστον [minRest] δευτερόλεπτα. Η αρχή του επόμενου
///   σετ δεν καταγράφεται· υπολογίζεται από το ✓ του και από το πόσο κρατά το σετ ([setSeconds]: επαναλήψεις × ρυθμός
///   της άσκησης). round1, S6-8: πριν θεωρούσαμε ότι κάθε σετ κρατά 30″, ενώ με τον ρυθμό της βιβλιοθήκης (4–5″ ανά
///   επανάληψη) τα σετ του προγράμματος κρατούν 34–78″: το «διάλειμμα» διαβαζόταν ΜΕΣΑ στο επόμενο σετ. Έλεγχος 9/11
///   (03-Χ1): πριν ήταν ο ΧΑΜΗΛΟΤΕΡΟΣ μέσος 10″ όλου του διαλείμματος· το ελάχιστο πολλών θορυβωδών μέσων πέφτει κάτω
///   από την αληθινή τιμή (−0,5 ως −3,9 bpm, περισσότερο στα μεγάλα διαλείμματα), άρα «καλύτερη πτώση» από τεχνούργημα.
/// - Παράθυρα [από, έως): «30″» = 30 τιμές, «10″» = 10 (έλεγχος 9/11, 03-Χ4· πριν ήταν κλειστά και στις δύο άκρες).
/// - Κάθε μέσος όρος θέλει τουλάχιστον [minSamples] τιμές μέσα στο παράθυρο, αλλιώς «—» (καλύτερα κενό παρά
///   αριθμός από μία-δύο τιμές).
/// - Ο καρπός στα βάρη μετρά κατά προσέγγιση (Boudreaux et al., Med Sci Sports Exerc 2018): γι' αυτό μόνο μέσοι όροι,
///   ποτέ μέγιστο ανά σετ.
library;

import 'session.dart';

const setWindow = 30;
const restWindow = 10;
const minRest = 15;
const minSamples = 3;

/// Δευτερόλεπτα ανά επανάληψη όταν δεν ξέρουμε τον ρυθμό της άσκησης (οι ασκήσεις της βιβλιοθήκης έχουν 4,0–5,2″).
const defaultRepSec = 4.5;

/// Ένα σετ κρατά από [minSetSec] ως [maxSetSec] δευτερόλεπτα, όσες επαναλήψεις κι αν γράφει.
const minSetSec = 20.0, maxSetSec = 120.0;

/// Πόσο κράτησε περίπου ένα σετ [reps] επαναλήψεων με [perRep] δευτερόλεπτα την καθεμία (round1, S6-8). Αν ο χρήστης
/// κινείται πιο γρήγορα από τον ρυθμό της βιβλιοθήκης, το παράθυρο πέφτει λίγο νωρίτερα μέσα στο διάλειμμα (μικρό σφάλμα
/// προς τα πάνω)· αν το θεωρούσαμε πιο σύντομο απ' ό,τι ήταν, θα έπεφτε μέσα στο σετ (μεγάλο σφάλμα).
double setSeconds(int reps, [double? perRep]) {
  final d = reps * (perRep != null && perRep > 0 ? perRep : defaultRepSec);
  return d < minSetSec ? minSetSec : (d > maxSetSec ? maxSetSec : d);
}

class SetHr {
  const SetHr({this.set, this.rest});

  /// Μέσος όρος στο σετ (bpm), ή null.
  final int? set;

  /// Ως πόσο έπεσαν στο διάλειμμα που ακολούθησε (bpm), ή null (τελευταίο σετ, μικρό διάλειμμα, λίγες τιμές).
  final int? rest;
}

class ExHr {
  const ExHr(this.sets, this.avg);

  /// Ένα ανά γραμμή του [ExLog.log] (ίδια σειρά)· null για σετ που δεν έγινε.
  final List<SetHr?> sets;

  /// Μέσος όρος των σετ της άσκησης που έχουν τιμή, ή null.
  final int? avg;
}

/// Η πρώτη θέση με χρόνο ≥ [t] (οι τιμές είναι ταξινομημένες).
int _first(List<List<int>> hr, num t) {
  var lo = 0, hi = hr.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (hr[mid][0] < t) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// Μέσος όρος των τιμών με χρόνο στο [from, to) (δευτερόλεπτα από την αρχή, ταξινομημένες), ή null με λιγότερες
/// από [minSamples].
int? meanIn(List<List<int>> hr, num from, num to) {
  var sum = 0, n = 0;
  for (var i = _first(hr, from); i < hr.length && hr[i][0] < to; i++) {
    sum += hr[i][1];
    n++;
  }
  return n < minSamples ? null : (sum / n).round();
}

/// Ο μέσος όρος των τελευταίων [restWindow]″ του διαλείμματος [from, to), ή null (μικρό διάλειμμα, λίγες τιμές).
int? restIn(List<List<int>> hr, num from, num to) {
  if (to - from < minRest) return null;
  return meanIn(hr, to - restWindow, to);
}

/// Παλμοί ανά σετ για κάθε άσκηση της [s] (ίδια σειρά με [Session.items]). Χωρίς παλμούς: κενή λίστα.
/// [repSeconds]: δευτερόλεπτα ανά επανάληψη κάθε άσκησης (ο ρυθμός της βιβλιοθήκης)· χωρίς αυτό, [defaultRepSec].
List<ExHr> sessionSetHr(Session s, {double Function(String ex)? repSeconds}) {
  if (s.hr.isEmpty) return const [];
  final hr = [...s.hr]..sort((a, b) => a[0].compareTo(b[0]));
  final t0 = s.start.millisecondsSinceEpoch;

  // Όλα τα ✓ με τη σειρά που έγιναν, από όλες τις ασκήσεις: το διάλειμμα είναι ως το επόμενο σετ, όποιο κι αν είναι.
  // Για καθένα: (η ώρα του ✓, η αρχή του σετ όπως υπολογίζεται από τις επαναλήψεις του).
  final ends = <(double, double)>[
    for (final e in s.items)
      for (final x in e.log)
        if (x.done && x.at != null)
          ((x.at! - t0) / 1000, (x.at! - t0) / 1000 - setSeconds(x.reps, repSeconds?.call(e.ex))),
  ]..sort((a, b) => a.$1.compareTo(b.$1));

  /// Η αρχή του επόμενου σετ μετά το ✓ στο [t], ή null αν δεν έγινε άλλο.
  double? nextStart(double t) {
    for (final x in ends) {
      if (x.$1 > t) return x.$2;
    }
    return null;
  }

  return [
    for (final e in s.items)
      () {
        final sets = <SetHr?>[
          for (final x in e.log)
            if (!x.done || x.at == null)
              null
            else
              () {
                final end = (x.at! - t0) / 1000;
                final n = nextStart(end);
                return SetHr(
                  set: meanIn(hr, end - setWindow, end),
                  rest: n == null ? null : restIn(hr, end, n),
                );
              }(),
        ];
        final vals = [for (final v in sets) if (v?.set != null) v!.set!];
        return ExHr(sets, vals.isEmpty ? null : (vals.reduce((a, b) => a + b) / vals.length).round());
      }(),
  ];
}
