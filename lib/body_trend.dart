/// Σώμα: η αλλαγή σε λίπος και μύες ως τάση από 3 ζυγίσεις (13/11, ιδέα Α5 του τελικού ελέγχου).
///
/// Η ζυγαριά εκτιμά λίπος και μύες από την αντίσταση του σώματος. Η εκτίμηση αλλάζει με το νερό, το φαγητό, την άσκηση
/// και την ώρα της μέρας (Kyle κ.ά. 2004, Clin Nutr 23:1430, οδηγίες ESPEN για τη μέτρηση), άρα η διαφορά ΜΙΑΣ ζύγισης
/// από την προηγούμενη είναι κυρίως θόρυβος. Γι' αυτό εδώ συγκρίνεται η μεσαία τιμή των 3 τελευταίων ζυγίσεων με τη
/// μεσαία των 3 πριν από αυτές. Η μεσαία (όχι ο μέσος όρος) δεν παρασύρεται από μία «περίεργη» ζύγιση.
///
/// - Μία ζύγιση ανά μέρα, η ΠΡΩΤΗ της μέρας (round 1, S4-4 = S3-6 = S11-13): ίδιος κανόνας με το ιστορικό, τις Τάσεις,
///   την αναφορά και τη διόρθωση θερμίδων (RT-15). Η πρωινή ζύγιση, νηστικός, είναι συγκρίσιμη από μέρα σε μέρα· μια
///   βραδινή μετά από φαγητό ή άσκηση αλλάζει βάρος και εκτίμηση λίπους (Kyle 2004). Πριν μετρούσε η τελευταία της μέρας.
/// - Ζύγιση που μοιάζει ξένη (round 1, S11-2· round 2, R2-E-2: [guardBody], ίδιος κανόνας με τη διόρθωση θερμίδων) δεν
///   μετρά· μένει στη λίστα των ζυγίσεων, σημειωμένη. Αν η πρώτη της μέρας μοιάζει ξένη, μετρά η επόμενη της ίδιας μέρας.
///   Ζύγιση «σε αναμονή» (διαφέρει πολύ, χωρίς ακόμα επόμενη) μετρά κανονικά εδώ.
/// - Με λιγότερες από 6 μέρες ζύγισης: καμία αλλαγή (ούτε «περίπου»).
/// - Το «3» είναι δική μας επιλογή (ο μικρότερος αριθμός που έχει μεσαία τιμή)· δεν βγαίνει από μελέτη.
/// - Round 1 (S4-3): η διαφορά γράφεται μόνο όταν ξεπερνά τον θόρυβο της ζυγαριάς ([bodyFloorFatPct], [bodyFloorKg]).
library;

import 'data.dart';
import 'format.dart' show dayOf, dec;
import 'history.dart' show dateKey;
import 'weight_guard.dart';

const bodyTrendGroup = 3;

/// Round 1 (S4-3): η μικρότερη διαφορά της τάσης (μεσαία 3 τελευταίων − μεσαία 3 πριν) που γράφεται. Πηγή: McLester κ.ά.,
/// J Clin Densitom 2020 (67 ενήλικες, InBody 230/720/770, δύο μετρήσεις με 24–72 ώρες διαφορά): τυπικό σφάλμα μέτρησης
/// 0,77–0,99 μονάδες στο % λίπους, 0,54–0,87 kg στη μάζα λίπους, 0,58–0,84 kg στην άλιπη μάζα. Σε προσομοίωση χωρίς
/// καμία αλλαγή, το 95% των διαφορών «3 με 3» είναι κάτω από ~1,86 × σφάλμα (διαφορά δύο μεσαίων τιμών από 3: τυπική
/// απόκλιση 0,947 × σφάλμα): 1,4–1,8 μονάδες λίπους και 1,0–1,6 kg.
/// Round 2 (g4 · R2-D-2): τα όρια μπήκαν στο ΠΑΝΩ άκρο αυτού του εύρους (2 μονάδες, 1,7 kg). Με το κάτω άκρο (1,5 / 1,0
/// του γύρου 1), χωρίς καμία αλλαγή, η παρένθεση έβγαινε στο 12% (λίπος %) και στο 23–25% (kg) των συγκρίσεων με το
/// μεγαλύτερο σφάλμα της μελέτης, ενώ η σημείωση λέει «μόνο αλλαγή μεγαλύτερη από τη διακύμανση». Τώρα ≤ 3,8% και ≤ 4,6%
/// (προσομοίωση με τη στρογγυλοποίηση της οθόνης: /home/claude/scratch/g4/floor_sim.py). Οι τιμές της μελέτης είναι από
/// εργαστήριο, σε ελεγχόμενες συνθήκες· στο σπίτι, με την H40, το σφάλμα είναι μάλλον μεγαλύτερο. Το τίμημα: αληθινή
/// αλλαγή 1–1,5 kg σε μια εβδομάδα συνήθως δεν φαίνεται (δεν ξεχωρίζει από τον θόρυβο της ζυγαριάς ούτως ή άλλως).
/// Για τους σκελετικούς μύες δεν υπάρχει δημοσιευμένο σφάλμα: ίδιο όριο με την άλιπη μάζα (είναι μέρος της), ώστε ο
/// θόρυβος να μη διαβάζεται «χάνω μύες». Για την H40 δεν υπάρχει καμία μελέτη.
const bodyFloorFatPct = 2.0;
const bodyFloorKg = 1.7;

/// true όταν η διαφορά [diff] (όπως φαίνεται) είναι τουλάχιστον [floor]: μόνο τότε γράφεται σε παρένθεση.
bool bodyDiffShown(double diff, double floor) => diff != 0 && diff.abs() >= floor - 1e-9;

/// Round 2 (g4 · R2-E-2): οι ζυγίσεις που μοιάζουν ξένες ([foreign]: δεν μετρούν πουθενά, φαίνονται σημειωμένες) και
/// όσες περιμένουν την επόμενη ζύγιση ([pending]: φαίνονται και μετρούν κανονικά εδώ· μένουν έξω μόνο από τη διόρθωση
/// θερμίδων). Ίδιος κανόνας με το `guardedWeights` της διόρθωσης θερμίδων ([guardDays], weight_guard.dart): κάθε μέρα
/// κρίνεται με τη ζύγιση της που μετρά. Οι άλλες ζυγίσεις της ίδιας μέρας: ξένες όταν δεν συμφωνούν μαζί της
/// ([weightsAgree]: δύο διαφορετικά βάρη την ίδια μέρα, π.χ. το παιδί μετά από σένα), αλλιώς ίδια κατάσταση με τη μέρα.
/// [body]: παλιότερη πρώτη. Ζυγίσεις χωρίς βάρος δεν κρίνονται.
({Set<BodyMeasurement> foreign, Set<BodyMeasurement> pending}) guardBody(List<BodyMeasurement> body) {
  final byDay = <DateTime, List<BodyMeasurement>>{};
  for (final b in body) {
    final w = b.weight;
    if (w == null || !w.isFinite) continue;
    byDay.putIfAbsent(dayOf(b.time), () => <BodyMeasurement>[]).add(b);
  }
  final days = byDay.keys.toList()..sort();
  final r = guardDays([
    for (final d in days) (d, [for (final b in byDay[d]!) b.weight!]),
  ]);
  final foreign = Set<BodyMeasurement>.identity();
  final pending = Set<BodyMeasurement>.identity();
  for (var i = 0; i < days.length; i++) {
    final list = byDay[days[i]]!;
    final status = r[i].status;
    final chosen = list[r[i].pick];
    for (final b in list) {
      if (status == WeighStatus.foreign || (!identical(b, chosen) && !weightsAgree(b.weight!, chosen.weight!))) {
        foreign.add(b);
      } else if (status == WeighStatus.pending) {
        pending.add(b);
      }
    }
  }
  return (foreign: foreign, pending: pending);
}

/// Οι ζυγίσεις που μοιάζουν ξένες ([guardBody]).
Set<BodyMeasurement> foreignBody(List<BodyMeasurement> body) => guardBody(body).foreign;

/// Η ζύγιση που μετρά για κάθε μέρα: η πρώτη της μέρας που δεν μοιάζει ξένη. Παλιότερη πρώτη.
List<BodyMeasurement> countedBody(List<BodyMeasurement> body, [Set<BodyMeasurement>? foreign]) {
  final skip = foreign ?? foreignBody(body);
  final out = <String, BodyMeasurement>{};
  for (final b in body) {
    if (skip.contains(b)) continue;
    out.putIfAbsent(dateKey(b.time), () => b);
  }
  return out.values.toList();
}

/// Οι τιμές ανά μέρα (η τιμή της ζύγισης που μετρά, [countedBody]), παλιότερη πρώτη. Μέρα όπου η ζύγιση που μετρά δεν
/// έχει την τιμή (π.χ. μόνο βάρος) δεν έχει τιμή, όπως στο ιστορικό. Το [body] είναι παλιότερη πρώτη.
List<(DateTime, double)> bodyDaily(List<BodyMeasurement> body, double? Function(BodyMeasurement) f) => [
      for (final b in countedBody(body))
        if (f(b) case final v? when v.isFinite) (b.time, v),
    ];

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

/// Round 1 (S11-2): η προηγούμενη ζύγιση με βάρος που μετρά (όχι ξένη), πριν από την [last]· για το «−1,1 kg από 13/8».
BodyMeasurement? previousCounted(List<BodyMeasurement> body, BodyMeasurement last, Set<BodyMeasurement> foreign) {
  for (final b in body.reversed) {
    if (identical(b, last) || foreign.contains(b) || b.weight == null || !b.time.isBefore(last.time)) continue;
    return b;
  }
  return null;
}

/// Η γραμμή κάτω από τον τίτλο «Σύσταση σώματος». [previous]: η προηγούμενη ζύγιση (για το βάρος), αν υπάρχει.
String bodyTrendNote({required DateTime? previous, required int days, required String Function(DateTime) date}) {
  final weight = previous == null ? '' : 'Στο βάρος, σε παρένθεση η αλλαγή από τις ${date(previous)}. ';
  if (days >= 2 * bodyTrendGroup) {
    // Round 2 (g4 · R2-D-2): τα όρια γραμμένα με τους αριθμούς τους ([bodyFloorFatPct], [bodyFloorKg]), ώστε να ξέρεις
    // γιατί συνήθως δεν φαίνεται παρένθεση από εβδομάδα σε εβδομάδα.
    return '${weight}Σε λίπος και μύες, οι 3 τελευταίες ζυγίσεις σε σύγκριση με τις 3 πριν. Σε παρένθεση μόνο αλλαγή από '
        '${dec(bodyFloorFatPct, 0)} μονάδες στο λίπος ή ${dec(bodyFloorKg)} kg και πάνω: μικρότερη χάνεται στη διακύμανση '
        'της ζυγαριάς.';
  }
  return '${weight}Η αλλαγή σε λίπος και μύες φαίνεται μετά από 6 μέρες ζύγισης (έχεις $days): μία ζύγιση μόνη της ανεβοκατεβαίνει με το νερό.';
}
