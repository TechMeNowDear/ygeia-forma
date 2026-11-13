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
///   Ζύγιση «σε αναμονή» (διαφέρει πολύ, χωρίς ακόμα βεβαίωση): round 3 (k1 · R3-A-1) δεν μπαίνει στην τάση (πριν μέσα).
/// - Με λιγότερες από 6 μέρες ζύγισης: καμία αλλαγή (ούτε «περίπου»).
/// - Το «3» είναι δική μας επιλογή (ο μικρότερος αριθμός που έχει μεσαία τιμή)· δεν βγαίνει από μελέτη.
/// - Round 1 (S4-3): η διαφορά γράφεται μόνο όταν ξεπερνά τον θόρυβο της ζυγαριάς ([bodyFloorFatPct], [bodyFloorKg]).
library;

import 'data.dart';
import 'format.dart' show dayOf, dec;
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

bool _weighed(BodyMeasurement b) => b.weight != null && b.weight!.isFinite;

/// Round 3 (k1 · R3-C-1): Η ΖΥΓΙΣΗ ΤΗΣ ΜΕΡΑΣ, με έναν κανόνα για όλη την εφαρμογή. Για κάθε μέρα με ζύγιση (παλιότερη
/// πρώτη): όλες οι ζυγίσεις της με τη σειρά που έγιναν ([all]), η ζύγιση της μέρας ([pick]) και η κατάστασή της
/// ([status]). [pick] = αυτή που διαλέγει ο φύλακας ([guardDays], ίδιος με το `guardedWeights` της διόρθωσης θερμίδων):
/// η πρώτη της μέρας που μετρά (αν ζυγίστηκε πρώτα το παιδί και μετά εσύ, η δική σου)· αν δεν μετρά καμία, μια «σε
/// αναμονή» πριν από μια «ξένη», η πιο κοντινή στις γύρω ζυγίσεις (R3-A-2). Μέρα μόνο με ζυγίσεις χωρίς βάρος: η πρώτη
/// της, «μετρά» (δεν κρίνεται).
/// Από αυτό βγαίνουν ΟΛΑ: το ιστορικό ([bodyRows] → Τάσεις, «Η εβδομάδα σου», αναφορά, σελίδα μέτρησης), το Σώμα, η
/// Σήμερα και το widget ([guardBody], [countedBody]). Πριν (γύρος 2) το ιστορικό κρατούσε την ΠΡΩΤΗ ζύγιση της μέρας
/// χωρίς φύλακα: με το παιδί πρώτο (38,0 kg) και εσένα μετά (80,8 kg), η Σήμερα έλεγε 80,8 και η «Η εβδομάδα σου»
/// «81,2 → 38,0 kg». Και το Σώμα (πρώτη μη ξένη) μπορούσε να διαλέξει άλλη ζύγιση από τη διόρθωση θερμίδων όταν δύο
/// ζυγίσεις της ίδιας μέρας συμφωνούν μεταξύ τους αλλά μόνο η δεύτερη μετρά (86 και 90 kg με τις γύρω στα 91).
/// [body]: με οποιαδήποτε σειρά (μέσα σε κάθε μέρα ταξινομείται με την ώρα).
/// Round 4 (m1 · R4-A-2): [unsure] = δύο ζυγίσεις της μέρας με πολύ διαφορετικό βάρος και καμία άλλη ζύγιση ως
/// [weightGuardHorizon] μέρες: δεν ξέρουμε ποια είναι δική σου, η μέρα «σε αναμονή» ([guardDays]).
List<({DateTime day, List<BodyMeasurement> all, BodyMeasurement pick, WeighStatus status, bool unsure})> weighInDays(
    List<BodyMeasurement> body) {
  final byDay = <DateTime, List<BodyMeasurement>>{};
  for (final b in body) {
    byDay.putIfAbsent(dayOf(b.time), () => <BodyMeasurement>[]).add(b);
  }
  final days = byDay.keys.toList()..sort();
  for (final d in days) {
    byDay[d]!.sort((a, b) => a.time.compareTo(b.time));
  }
  // Μόνο ζυγίσεις με βάρος κρίνονται (όπως πριν).
  final judged = [
    for (final d in days)
      if (byDay[d]!.any(_weighed)) d,
  ];
  final r = guardDays([
    for (final d in judged) (d, [for (final b in byDay[d]!) if (_weighed(b)) b.weight!]),
  ]);
  final picked = <DateTime, ({BodyMeasurement pick, WeighStatus status, bool unsure})>{};
  for (var i = 0; i < judged.length; i++) {
    final weighed = [for (final b in byDay[judged[i]]!) if (_weighed(b)) b];
    picked[judged[i]] = (pick: weighed[r[i].pick], status: r[i].status, unsure: r[i].unsure);
  }
  return [
    for (final d in days)
      (
        day: d,
        all: byDay[d]!,
        pick: picked[d]?.pick ?? byDay[d]!.first,
        status: picked[d]?.status ?? WeighStatus.counted,
        unsure: picked[d]?.unsure ?? false,
      ),
  ];
}

/// Round 3 (k1 · R3-C-1): η ζύγιση της μέρας [day] ([weighInDays]), ή null χωρίς ζύγιση εκείνη τη μέρα. Με μία ζύγιση
/// τη μέρα (το σύνηθες) είναι αυτή, χωρίς να τρέξει ο φύλακας σε όλο το ιστορικό.
BodyMeasurement? dayWeighIn(List<BodyMeasurement> body, DateTime day) {
  final k = dayOf(day);
  final same = [
    for (final b in body)
      if (dayOf(b.time) == k) b,
  ];
  if (same.length <= 1) return same.isEmpty ? null : same.first;
  for (final g in weighInDays(body)) {
    if (g.day == k) return g.pick;
  }
  return null;
}

/// Round 2 (g4 · R2-E-2): οι ζυγίσεις που μοιάζουν ξένες ([foreign]: δεν μετρούν πουθενά, φαίνονται σημειωμένες) και
/// όσες περιμένουν βεβαίωση ([pending]: φαίνονται ως η ζύγιση της μέρας· round 3, k1 · R3-A-1: έξω από κάθε υπολογισμό,
/// πριν μόνο από τη διόρθωση θερμίδων). Ίδιος κανόνας με το `guardedWeights` της διόρθωσης θερμίδων ([guardDays], weight_guard.dart): κάθε μέρα
/// κρίνεται με τη ζύγιση της που μετρά. Οι άλλες ζυγίσεις της ίδιας μέρας: ξένες όταν δεν συμφωνούν μαζί της
/// ([weightsAgree]: δύο διαφορετικά βάρη την ίδια μέρα, π.χ. το παιδί μετά από σένα), αλλιώς ίδια κατάσταση με τη μέρα.
/// [body]: παλιότερη πρώτη. Ζυγίσεις χωρίς βάρος δεν κρίνονται.
/// Round 3 (k1 · R3-C-1): και, από τον ίδιο υπολογισμό ([weighInDays]), οι ζυγίσεις των ημερών: [counted] = [countedBody]
/// (μόνο όσες μετρούν: γραφήματα, τάσεις, υπολογισμοί) και [shown] = [shownBody] (και οι «σε αναμονή»: η τελευταία ζύγιση
/// στη Σήμερα και στο widget).
({
  Set<BodyMeasurement> foreign,
  Set<BodyMeasurement> pending,
  List<BodyMeasurement> counted,
  List<BodyMeasurement> shown,
}) guardBody(List<BodyMeasurement> body) {
  final foreign = Set<BodyMeasurement>.identity();
  final pending = Set<BodyMeasurement>.identity();
  final counted = <BodyMeasurement>[];
  final shown = <BodyMeasurement>[];
  for (final g in weighInDays(body)) {
    if (g.status == WeighStatus.counted) counted.add(g.pick);
    if (g.status != WeighStatus.foreign) shown.add(g.pick);
    for (final b in g.all) {
      if (!_weighed(b)) continue;
      // Round 4 (m1 · R4-A-2): μέρα [unsure] (δύο πολύ διαφορετικά βάρη, καμία άλλη ζύγιση κοντά): όλες «σε αναμονή».
      if (!g.unsure &&
          (g.status == WeighStatus.foreign || (!identical(b, g.pick) && !weightsAgree(b.weight!, g.pick.weight!)))) {
        foreign.add(b);
      } else if (g.status == WeighStatus.pending) {
        pending.add(b);
      }
    }
  }
  return (foreign: foreign, pending: pending, counted: counted, shown: shown);
}

/// Round 4 (m1 · R4-A-2): η [b] είναι «σε αναμονή» επειδή την ίδια μέρα υπάρχει κι άλλη ζύγιση με πολύ διαφορετικό
/// βάρος και καμία άλλη ζύγιση κοντά ([weighInDays] `unsure`): δεν ξέρουμε ποια είναι δική σου. ([pending]: το
/// [guardBody] `pending`· μόνο σε τέτοια μέρα υπάρχουν δύο ζυγίσεις της ίδιας μέρας «σε αναμονή» που δεν συμφωνούν.)
bool mixedDayPending(Set<BodyMeasurement> pending, BodyMeasurement b) =>
    pending.contains(b) &&
    b.weight != null &&
    pending.any((o) => !identical(o, b) && o.weight != null && dayOf(o.time) == dayOf(b.time) && !weightsAgree(o.weight!, b.weight!));

/// Οι ζυγίσεις που μοιάζουν ξένες ([guardBody]).
Set<BodyMeasurement> foreignBody(List<BodyMeasurement> body) => guardBody(body).foreign;

/// Η ζύγιση που μετρά για κάθε μέρα, παλιότερη πρώτη: η ζύγιση της μέρας ([weighInDays]: η πρώτη της μέρας που μετρά),
/// μόνο τις μέρες που μετρά. Για γραφήματα, τάσεις και κάθε υπολογισμό.
/// Round 3 (k1 · R3-C-1): πριν «η πρώτη της μέρας που δεν είναι ξένη», που δεν ήταν πάντα η ίδια με του φύλακα.
/// Round 3 (k1 · R3-A-1): χωρίς τις «σε αναμονή» (πριν μέσα): ζύγιση που δεν βεβαιώθηκε δεν μπαίνει σε υπολογισμό.
List<BodyMeasurement> countedBody(List<BodyMeasurement> body) => guardBody(body).counted;

/// Round 3 (k1): όπως το [countedBody], με τις «σε αναμονή» (φαίνονται ως η ζύγιση της μέρας, σημειωμένες): για την
/// τελευταία ζύγιση στη Σήμερα, στην κάρτα ζύγισης και στο widget.
List<BodyMeasurement> shownBody(List<BodyMeasurement> body) => guardBody(body).shown;

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
