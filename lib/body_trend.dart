/// Σώμα: η αλλαγή σε λίπος και μύες ως τάση από 3 ζυγίσεις (13/11, ιδέα Α5 του τελικού ελέγχου).
///
/// Η ζυγαριά εκτιμά λίπος και μύες από την αντίσταση του σώματος. Η εκτίμηση αλλάζει με το νερό, το φαγητό, την άσκηση
/// και την ώρα της μέρας (Kyle κ.ά. 2004, Clin Nutr 23:1430, οδηγίες ESPEN για τη μέτρηση), άρα η διαφορά ΜΙΑΣ ζύγισης
/// από την προηγούμενη είναι κυρίως θόρυβος. Γι' αυτό εδώ συγκρίνεται η μεσαία τιμή των 3 τελευταίων ζυγίσεων με τη
/// μεσαία των 3 πριν από αυτές. Η μεσαία (όχι ο μέσος όρος) δεν παρασύρεται από μία «περίεργη» ζύγιση.
///
/// - Μία ζύγιση ανά μέρα (η τελευταία της μέρας): τρεις ζυγίσεις το ίδιο πρωί δεν είναι «τάση».
/// - Με λιγότερες από 6 μέρες ζύγισης: καμία αλλαγή (ούτε «περίπου»).
/// - Το «3» είναι δική μας επιλογή (ο μικρότερος αριθμός που έχει μεσαία τιμή)· δεν βγαίνει από μελέτη.
library;

import 'data.dart';
import 'history.dart' show dateKey;

const bodyTrendGroup = 3;

/// Οι τιμές ανά μέρα (η τελευταία ζύγιση κάθε μέρας που έχει τιμή), παλιότερη πρώτη. Το [body] είναι παλιότερη πρώτη.
List<(DateTime, double)> bodyDaily(List<BodyMeasurement> body, double? Function(BodyMeasurement) f) {
  final out = <String, (DateTime, double)>{};
  for (final b in body) {
    final v = f(b);
    if (v == null || !v.isFinite) continue;
    final k = dateKey(b.time);
    out.remove(k); // η νεότερη της ίδιας μέρας παίρνει τη θέση της
    out[k] = (b.time, v);
  }
  return out.values.toList();
}

class BodyTrend {
  const BodyTrend({required this.now, required this.before, required this.from, required this.to});

  /// Η μεσαία τιμή των 3 τελευταίων ζυγίσεων και των 3 πριν από αυτές.
  final double now, before;

  /// Η πρώτη και η τελευταία μέρα των 3 παλιότερων ζυγίσεων (για το κείμενο «με τις 3 πριν»).
  final DateTime from, to;
}

/// null με λιγότερες από 6 μέρες ζύγισης που έχουν την τιμή.
BodyTrend? bodyTrend(List<BodyMeasurement> body, double? Function(BodyMeasurement) f) {
  final d = bodyDaily(body, f);
  const g = bodyTrendGroup;
  if (d.length < 2 * g) return null;
  double median(List<(DateTime, double)> v) => ([for (final e in v) e.$2]..sort())[g ~/ 2];
  final last = d.sublist(d.length - g);
  final prev = d.sublist(d.length - 2 * g, d.length - g);
  return BodyTrend(now: median(last), before: median(prev), from: prev.first.$1, to: prev.last.$1);
}

/// Πόσες μέρες ζύγισης έχουν σύσταση σώματος (λίπος).
int bodyCompositionDays(List<BodyMeasurement> body) => bodyDaily(body, (b) => b.fatPct).length;

/// Η γραμμή κάτω από τον τίτλο «Σύσταση σώματος». [previous]: η προηγούμενη ζύγιση (για το βάρος), αν υπάρχει.
String bodyTrendNote({required DateTime? previous, required int days, required String Function(DateTime) date}) {
  final weight = previous == null ? '' : 'Στο βάρος, σε παρένθεση η αλλαγή από τις ${date(previous)}. ';
  if (days >= 2 * bodyTrendGroup) {
    return '${weight}Σε λίπος και μύες, οι 3 τελευταίες ζυγίσεις σε σύγκριση με τις 3 πριν.';
  }
  return '${weight}Η αλλαγή σε λίπος και μύες φαίνεται μετά από 6 μέρες ζύγισης (έχεις $days): μία ζύγιση μόνη της ανεβοκατεβαίνει με το νερό.';
}
