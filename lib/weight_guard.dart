/// Φύλακας ζυγίσεων (έλεγχος 13/11, S11-2): μια ζύγιση που δεν μπορεί να είναι του ίδιου ανθρώπου (παιδί ή σύντροφος
/// στην ίδια ζυγαριά, ζύγιση με βαλίτσα στο χέρι) δεν μπαίνει στους υπολογισμούς. Η ζύγιση ΔΕΝ σβήνεται και δεν
/// κρύβεται: μένει στη Samsung Health και στο ιστορικό· απλώς δεν μετρά, και η οθόνη το λέει.
///
/// Κανόνας (ένα μέρος, για τη διόρθωση θερμίδων και για τις τάσεις σώματος): η ζύγιση συγκρίνεται με τη ΔΙΑΜΕΣΟ των
/// άλλων ζυγίσεων των γύρω ημερών (ως [weightGuardDays] μέρες πριν ή μετά, μία ανά μέρα). «Ξένη» είναι όταν απέχει πάνω
/// από [weightGuardKg] kg ΚΑΙ πάνω από το [weightGuardShare] της διαμέσου. Με λιγότερες από [weightGuardMinNeighbours]
/// άλλες ζυγίσεις δεν κρίνεται (μένει).
///
/// Γιατί αυτά τα όρια. Το βάρος του ίδιου ανθρώπου αλλάζει λίγο από μέρα σε μέρα: σε ενήλικες με έξυπνη ζυγαριά ο
/// κύκλος της εβδομάδας είναι περίπου 0,35% του βάρους και η άνοδος των γιορτών περίπου 1,35% (Turicchi 2020, PLoS ONE·
/// ο ίδιος εβδομαδιαίος ρυθμός στο Orsama 2014, Obes Facts), και η αλλαγή δύο εβδομάδων σε ελεύθερη ζωή είναι της τάξης
/// του 1 kg (Bhutani 2017, Physiol Rep). Το όριο (5%, και ποτέ κάτω από 4 kg) είναι πολλαπλάσιο όλων αυτών, επίτηδες:
/// - δεν πρέπει ΠΟΤΕ να κρύψει μια αληθινά γρήγορη απώλεια. Σε προσομοίωση (ζυγίσεις Δευτέρα, Τετάρτη, Παρασκευή, θόρυβος
///   0,6 kg) η σημερινή, δική σου ζύγιση εξαιρείται στο 0,00% των φορών με απώλεια ως 1,5% την εβδομάδα και στο 0,4% με
///   2,5% την εβδομάδα· με όριο 3 kg / 4% θα ήταν 0,5% και 9%.
/// - πιάνει στο 100% ζύγιση που απέχει 10 kg ή περισσότερο (παιδί, σύντροφος με άλλο βάρος) και στο 97% τα 5 kg (για 82 kg).
///   Άνθρωπο με σχεδόν ίδιο βάρος (ως 3–4 kg διαφορά) δεν τον ξεχωρίζει κανένα όριο από τα νερά μιας μέρας.
/// Το όριο είναι δική μας επιλογή για λάθη και ξένες ζυγίσεις, όχι ιατρικό όριο.
///
/// Round 2 (g4 · R2-E-2): η διαφορά από τη διάμεσο ΜΟΝΗ της δεν κάνει πια μια ζύγιση «ξένη». Μετά από κενό στις ζυγίσεις
/// με αληθινή αλλαγή (αρρώστια, −5 kg σε 10 μέρες χωρίς ζύγιση) οι ΔΙΚΕΣ σου ζυγίσεις έβγαιναν «ξένες» για μια εβδομάδα
/// και η αναφορά για τον γιατρό έλεγε «πιθανόν άλλου ατόμου». Τώρα ([weighStatusAt]) μια ζύγιση που διαφέρει (κανόνας
/// πάνω, [weightLooksForeign]) είναι:
/// - [WeighStatus.foreign] μόνο όταν οι ζυγίσεις ΠΡΙΝ και ΜΕΤΑ από αυτήν (ως [weightGuardDays] μέρες) συμφωνούν μεταξύ
///   τους και όχι μαζί της ([weightsAgree]): το παιδί ή ο επισκέπτης ανάμεσα στις δικές σου ζυγίσεις, μία ή λίγες στη σειρά
///   (ως [weightGuardDays] μέρες συνολικά, π.χ. ένα Σαββατοκύριακο). Δεν μετρά πουθενά.
/// - [WeighStatus.counted] μόλις η αμέσως επόμενη (ή η αμέσως προηγούμενη) ζύγιση συμφωνεί μαζί της: μία αρκεί, γιατί δύο
///   ζυγίσεις στη σειρά στο νέο βάρος είναι η αλλαγή του ίδιου ανθρώπου.
/// - [WeighStatus.pending] όταν καμία ζύγιση δίπλα της δεν συμφωνεί και δεν είναι ανάμεσα σε ζυγίσεις που συμφωνούν (συνήθως
///   η τελευταία, που δεν έχει ακόμα επόμενη): φαίνεται κανονικά σε όλες τις οθόνες και στην αναφορά, και μένει έξω ΜΟΝΟ
///   από τη διόρθωση θερμίδων, ώσπου να τη βεβαιώσει η επόμενη ζύγιση.
/// Προσομοίωση (/home/claude/scratch/g4/guard2.py, mc.py): με ζύγιση Δευτέρα, Τετάρτη, Παρασκευή (ή κάθε μέρα, ή με 40%
/// χαμένες ζυγίσεις) και απώλεια ως 2,5% την εβδομάδα, καμία δική σου ζύγιση «ξένη»· «σε αναμονή» ποτέ χωρίς κενά, και με
/// κενά 1 και 10 στις 7.143 (απώλεια 1,5% και 2,5%), πάντα «μετρά» με την επόμενη. Αρρώστια με −5 kg και 10 μέρες
/// χωρίς ζύγιση: η πρώτη ζύγιση «σε αναμονή», με τη δεύτερη μετρούν και οι δύο. Παιδί 45 kg ή επισκέπτης 95 kg ανάμεσα στις ζυγίσεις σου: «ξένη».
/// Με μία ζύγιση τη μέρα, ό,τι δεν μετρά εδώ δεν μετρούσε ούτε με τον κανόνα του γύρου 1: ο νέος κανόνας κρατά έξω
/// λιγότερες ζυγίσεις, ποτέ περισσότερες.
library;

import 'dart:math' as math;

import 'format.dart' show daysBetween;

/// Πόσες ημερολογιακές μέρες πριν και μετά μια ζύγιση είναι «γύρω μέρες».
const weightGuardDays = 14;

/// Κάτω από τόσες άλλες ζυγίσεις στις γύρω μέρες, η ζύγιση δεν κρίνεται.
const weightGuardMinNeighbours = 3;

/// Η ζύγιση είναι «ξένη» όταν απέχει από τη διάμεσο των άλλων πάνω από τόσα kg…
const weightGuardKg = 4.0;

/// …και πάνω από αυτό το μέρος της διαμέσου (5%).
const weightGuardShare = 0.05;

/// true: η ζύγιση [kg] δεν μπορεί λογικά να είναι του ίδιου ανθρώπου με τις [neighbours] (οι ΑΛΛΕΣ ζυγίσεις του των
/// γύρω ημερών, σε kg· όχι η ίδια). false και όταν δεν φτάνουν οι άλλες ζυγίσεις για να κριθεί.
bool weightLooksForeign(double kg, Iterable<double> neighbours) {
  if (!kg.isFinite) return false;
  final others = [
    for (final w in neighbours)
      if (w.isFinite) w,
  ]..sort();
  final n = others.length;
  if (n < weightGuardMinNeighbours) return false;
  final median = n.isOdd ? others[n ~/ 2] : (others[n ~/ 2 - 1] + others[n ~/ 2]) / 2;
  return (kg - median).abs() > math.max(weightGuardKg, weightGuardShare * median);
}

/// Round 2 (R2-E-2): τι γίνεται με μια ζύγιση (κανόνας στην αρχή του αρχείου).
enum WeighStatus {
  /// Μετρά παντού.
  counted,

  /// Διαφέρει πολύ, αλλά δεν έχει ακόμα επόμενη ζύγιση που να τη βεβαιώνει ή να τη διαψεύδει: φαίνεται κανονικά· μένει
  /// έξω μόνο από τη διόρθωση θερμίδων.
  pending,

  /// Οι ζυγίσεις πριν και μετά συμφωνούν μεταξύ τους και όχι μαζί της: δεν μετρά πουθενά (φαίνεται σημειωμένη).
  foreign,
}

/// Round 2 (R2-E-2): δύο ζυγίσεις μπορεί να είναι του ίδιου ανθρώπου: απέχουν ως [weightGuardKg] kg ή ως το
/// [weightGuardShare] της μεγαλύτερης (ίδια όρια με το [weightLooksForeign]).
bool weightsAgree(double a, double b) => (a - b).abs() <= math.max(weightGuardKg, weightGuardShare * math.max(a, b));

/// Round 2 (R2-E-2): η κατάσταση της ζύγισης [i] της [days] (μία ζύγιση ανά μέρα: η μέρα και τα kg, παλιότερη πρώτη,
/// διαφορετικές μέρες, πεπερασμένες τιμές). Κοιτά μόνο ζυγίσεις ως 2 × [weightGuardDays] μέρες πριν ή μετά, άρα ένα
/// κομμάτι του ιστορικού γύρω από τη μέρα δίνει το ίδιο αποτέλεσμα με όλο (trends.dart [foreignWeighIn]).
WeighStatus weighStatusAt(List<(DateTime, double)> days, int i) => _weighStatus(days, i, days[i].$2);

/// Όπως το [weighStatusAt], με [kg] στη θέση της τιμής της μέρας [i] (για να δοκιμαστεί και άλλη ζύγιση της ίδιας μέρας).
WeighStatus _weighStatus(List<(DateTime, double)> s, int i, double kg) {
  double at(int j) => j == i ? kg : s[j].$2;
  final day = s[i].$1;
  final others = <double>[
    for (var j = i - 1; j >= 0 && daysBetween(s[j].$1, day) <= weightGuardDays; j--) s[j].$2,
    for (var j = i + 1; j < s.length && daysBetween(day, s[j].$1) <= weightGuardDays; j++) s[j].$2,
  ];
  if (!weightLooksForeign(kg, others)) return WeighStatus.counted;
  // Το «κομμάτι» της: οι διπλανές ζυγίσεις που συμφωνούν μαζί της, η καθεμία ως [weightGuardDays] μέρες από την επόμενη.
  bool linked(int a, int b) => daysBetween(s[a].$1, s[b].$1) <= weightGuardDays && weightsAgree(at(a), at(b));
  var first = i;
  var last = i;
  var longRun = false;
  while (first > 0 && linked(first - 1, first)) {
    first--;
    if (daysBetween(s[first].$1, s[last].$1) > weightGuardDays) {
      longRun = true;
      break;
    }
  }
  while (!longRun && last < s.length - 1 && linked(last, last + 1)) {
    last++;
    if (daysBetween(s[first].$1, s[last].$1) > weightGuardDays) longRun = true;
  }
  // Ξένη: σύντομο κομμάτι ανάμεσα σε δύο ζυγίσεις (αμέσως πριν και αμέσως μετά, κοντά του) που συμφωνούν μεταξύ τους.
  if (!longRun &&
      first > 0 &&
      last < s.length - 1 &&
      daysBetween(s[first - 1].$1, s[first].$1) <= weightGuardDays &&
      daysBetween(s[last].$1, s[last + 1].$1) <= weightGuardDays &&
      weightsAgree(at(first - 1), at(last + 1))) {
    return WeighStatus.foreign;
  }
  return first == last ? WeighStatus.pending : WeighStatus.counted;
}

/// Round 2 (R2-E-2): για κάθε μέρα ([days]: η μέρα και ΟΛΕΣ οι ζυγίσεις της σε kg, με τη σειρά που έγιναν, τουλάχιστον
/// μία· παλιότερη μέρα πρώτη), ποια ζύγιση μετρά ([pick]: θέση στη λίστα της μέρας) και η κατάσταση της μέρας. Μετρά η
/// πρώτη της μέρας· αν εκείνη δεν μετρά (π.χ. ζυγίστηκε πρώτα το παιδί) και μετρά μια επόμενη της ίδιας μέρας, εκείνη.
/// Αλλιώς η πρώτη, με την κατάστασή της. Δύο περάσματα: στο δεύτερο οι γύρω μέρες κρίνονται με τη ζύγιση που διάλεξε το
/// πρώτο (όχι με του παιδιού, αν ζυγίστηκε πρώτο).
List<({int pick, WeighStatus status})> guardDays(List<(DateTime, List<double>)> days) {
  var picks = List<int>.filled(days.length, 0);
  var out = <({int pick, WeighStatus status})>[];
  for (var pass = 0; pass < 2; pass++) {
    final s = [for (var i = 0; i < days.length; i++) (days[i].$1, days[i].$2[picks[i]])];
    out = [for (var i = 0; i < days.length; i++) _pickDay(s, i, days[i].$2)];
    picks = [for (final r in out) r.pick];
  }
  return out;
}

({int pick, WeighStatus status}) _pickDay(List<(DateTime, double)> s, int i, List<double> kgs) {
  WeighStatus? first;
  for (var k = 0; k < kgs.length; k++) {
    final st = _weighStatus(s, i, kgs[k]);
    if (st == WeighStatus.counted) return (pick: k, status: st);
    first ??= st;
  }
  return (pick: 0, status: first ?? WeighStatus.counted);
}
