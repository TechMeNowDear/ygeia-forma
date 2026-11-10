/// Παλμοί ανά σετ και ανά διάλειμμα, από τις ώρες των ✓ και τους παλμούς του ρολογιού (9/11).
///
/// Ορισμοί (ίδιοι στην οθόνη, στο ⓘ και στις δοκιμές):
/// - «♥ σετ»: ο μέσος όρος των παλμών στα [setWindow] δευτερόλεπτα ως το ✓ του σετ. Ένα σετ 8–12 επαναλήψεων
///   κρατά περίπου τόσο· με σταθερό παράθυρο τα σετ συγκρίνονται μεταξύ τους χωρίς να ξέρουμε πότε ξεκίνησε το καθένα.
/// - «♥ διάλειμμα»: ο μέσος όρος των τελευταίων [restWindow] δευτερολέπτων πριν από την αρχή του επόμενου σετ (οι
///   παλμοί λίγο πριν ξαναρχίσεις). Μόνο αν το διάλειμμα κράτησε τουλάχιστον [minRest] δευτερόλεπτα. Έλεγχος 9/11
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
List<ExHr> sessionSetHr(Session s) {
  if (s.hr.isEmpty) return const [];
  final hr = [...s.hr]..sort((a, b) => a[0].compareTo(b[0]));
  final t0 = s.start.millisecondsSinceEpoch;

  // Όλα τα ✓ με τη σειρά που έγιναν, από όλες τις ασκήσεις: το διάλειμμα είναι ως το επόμενο σετ, όποιο κι αν είναι.
  final ends = <double>[
    for (final e in s.items)
      for (final x in e.log)
        if (x.done && x.at != null) (x.at! - t0) / 1000,
  ]..sort();

  double? nextAfter(double t) {
    for (final x in ends) {
      if (x > t) return x;
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
                final n = nextAfter(end);
                return SetHr(
                  set: meanIn(hr, end - setWindow, end),
                  rest: n == null ? null : restIn(hr, end, n - setWindow),
                );
              }(),
        ];
        final vals = [for (final v in sets) if (v?.set != null) v!.set!];
        return ExHr(sets, vals.isEmpty ? null : (vals.reduce((a, b) => a + b) / vals.length).round());
      }(),
  ];
}
