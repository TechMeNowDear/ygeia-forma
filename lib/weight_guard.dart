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
/// - πιάνει ζύγιση που απέχει 10 kg ή περισσότερο (παιδί, σύντροφος με άλλο βάρος). Round 4 (m1 · R4-A-3): το «97% στα
///   5 kg» που έγραφε εδώ ίσχυε για ΜΙΑ ζύγιση άλλου· όταν ο ίδιος άνθρωπος, 5 kg ελαφρύτερος, ζυγίζεται κάθε
///   Σαββατοκύριακο στο προφίλ σου, με θόρυβο ζυγαριάς ±1 kg, μετρά ακόμα ένα μέρος των ζυγίσεών του (python του R4-A και
///   του m1: /home/claude/scratch/m1/leak.txt). Άνθρωπο με βάρος ως ~5 kg από το δικό σου δεν τον ξεχωρίζει κανένα όριο
///   από τα νερά μιας μέρας: η λύση είναι δικό του προφίλ στην εφαρμογή InBody.
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
///   ζυγίσεις στη σειρά στο νέο βάρος είναι η αλλαγή του ίδιου ανθρώπου. (Round 3, k1 · R3-A-1: δεν αρκεί πια· βλ. πιο
///   κάτω, [weightConfirmDays].)
/// - [WeighStatus.pending] όταν καμία ζύγιση δίπλα της δεν συμφωνεί και δεν είναι ανάμεσα σε ζυγίσεις που συμφωνούν (συνήθως
///   η τελευταία, που δεν έχει ακόμα επόμενη): φαίνεται κανονικά σε όλες τις οθόνες και στην αναφορά, και μένει έξω ΜΟΝΟ
///   από τη διόρθωση θερμίδων, ώσπου να τη βεβαιώσει η επόμενη ζύγιση. (Round 3, k1 · R3-A-1: έξω από κάθε υπολογισμό·
///   φαίνεται σημειωμένη.)
/// Προσομοίωση (/home/claude/scratch/g4/guard2.py, mc.py): με ζύγιση Δευτέρα, Τετάρτη, Παρασκευή (ή κάθε μέρα, ή με 40%
/// χαμένες ζυγίσεις) και απώλεια ως 2,5% την εβδομάδα, καμία δική σου ζύγιση «ξένη»· «σε αναμονή» ποτέ χωρίς κενά, και με
/// κενά 1 και 10 στις 7.143 (απώλεια 1,5% και 2,5%), πάντα «μετρά» με την επόμενη. Αρρώστια με −5 kg και 10 μέρες
/// χωρίς ζύγιση: η πρώτη ζύγιση «σε αναμονή», με τη δεύτερη μετρούν και οι δύο. Παιδί 45 kg ή επισκέπτης 95 kg ανάμεσα στις ζυγίσεις σου: «ξένη».
/// Με μία ζύγιση τη μέρα, ό,τι δεν μετρά εδώ δεν μετρούσε ούτε με τον κανόνα του γύρου 1: ο νέος κανόνας κρατά έξω
/// λιγότερες ζυγίσεις, ποτέ περισσότερες.
///
/// Round 3 (k1 · R3-A-1): ΔΥΟ ζυγίσεις στη σειρά που συμφωνούν δεν αρκούν πια. Ένας άνθρωπος 4,5–15 kg ελαφρύτερος που
/// ζυγίστηκε Σάββατο και Κυριακή στο προφίλ σου «μετρούσε» (η Κυριακή «βεβαίωνε» το Σάββατο) και η κάρτα γρήγορης
/// απώλειας πρότεινε +150 kcal (python του R3-A: 29–30 στις 30 φορές). Τώρα μια ζύγιση που διαφέρει μετρά μόνο όταν το νέο
/// βάρος φανεί σε ζυγίσεις [weightConfirmDays] διαφορετικών ημερών που απέχουν τουλάχιστον [weightConfirmSpan] μέρες
/// (πρώτη ως τελευταία), χωρίς ενδιάμεση ζύγιση στο παλιό βάρος· ως τότε «σε αναμονή». Με ζύγιση Δε/Τε/Πα κάθε 4 μέρες
/// περιέχουν μια δική σου ζύγιση, άρα ο επισκέπτης του Σαββατοκύριακου δεν φτάνει ποτέ να μετρήσει (python, k1: κάρτα
/// γρήγορης απώλειας 0 στις 30 για 5–15 kg· +150 τη Δευτέρα 1 στις 30, όσο και με τον κανόνα του γύρου 1, από τον θόρυβο
/// της ζυγαριάς)· μετά από αρρώστια οι δικές σου μετρούν με την 3η ζύγιση (Δε–Τε–Πα: την
/// Παρασκευή, πριν: την Τετάρτη). Με ζύγιση κάθε μέρα ή Δε/Τε/Πα και απώλεια ως 2,5% την εβδομάδα: καμία «σε αναμονή»,
/// καμία «ξένη» (python, k1: /home/claude/scratch/k1/mc_own.py). Το όριο: άνθρωπος με βάρος ως ~4 kg από το δικό σου δεν
/// ξεχωρίζει (ίδιο με πριν).
/// Round 3 (k1 · R3-A-2): την ίδια μέρα, αν δεν μετρά καμία ζύγιση, η ζύγιση της μέρας είναι η «σε αναμονή» (όχι η «ξένη»)
/// που είναι πιο κοντά στις γύρω ζυγίσεις, όχι απλώς η πρώτη: μετά από αρρώστια, με το παιδί πρώτο στη ζυγαριά (45 kg) και
/// εσένα μετά (73,4 kg), η ζύγιση της μέρας είναι η δική σου (πριν: του παιδιού, και η δική σου σημειωνόταν «ξένη»).
///
/// Round 4 (m1 · R4-A-1, R4-A-2): Η ΑΝΑΦΟΡΑ. Ως τον γύρο 3 κάθε ζύγιση συγκρινόταν με τη διάμεσο ΟΛΩΝ των ζυγίσεων ±14
/// ημερών. Ένα παιδί (ή σύντροφος 10+ kg μακριά) που ζυγίζεται κάθε Σαββατοκύριακο στο προφίλ σου είναι 2 από τις 5
/// ζυγίσεις της εβδομάδας: η διάμεσος έπεφτε ανάμεσα, οι ΔΙΚΕΣ σου ζυγίσεις έβγαιναν «ξένες» κάθε Κυριακή, και μετά από
/// μια εβδομάδα χωρίς δική σου ζύγιση μετρούσε το παιδί (κάρτα +150 kcal με 34,8 kg). Τώρα η αναφορά είναι η διάμεσος
/// της «κύριας ομάδας» ([_reference]): οι ζυγίσεις ±[weightGuardHorizon] ημερών χωρίζονται σε ομάδες βάρους (ταξινομημένες,
/// διπλανές που συμφωνούν ([weightsAgree]) στην ίδια ομάδα)· κύρια = αυτή που ζυγίζεται πιο συχνά τις εβδομάδες που
/// ζυγίζονται και οι δύο (ως [weightGuardSameWeek] μέρες η μία από την άλλη), μετά η πιο μεγάλη, μετά η βαρύτερη, μετά
/// η παλιότερη· μετρά και η ίδια η ζύγιση. Αναφορά = η διάμεσος των ζυγίσεων ±14 ημερών της κύριας ομάδας και όσων ομάδων
/// δεν ζυγίζονται στο ίδιο διάστημα με αυτήν (εσύ σε άλλο βάρος: πριν από μια γρήγορη απώλεια με κενά ή μια αρρώστια·
/// χωρίς αυτό, 5 στις 671.400 στιγμές της δοκιμής του γύρου 2 έβγαιναν «σε αναμονή»: rngcmp.py). Ένα πέρασμα, χωρίς
/// επαναλήψεις: η πρόταση του R4-A (επαναλαμβανόμενα περάσματα που βγάζουν από τη διάμεσο
/// όσες δεν μέτρησαν) δοκιμάστηκε και απορρίφθηκε: κύκλοι 2 και 4 περασμάτων σε καθημερινό ζύγισμα με αρρώστια, λάθος
/// ισορροπία στο σενάριο Β του R4-A συνεχισμένο ως 27/12 (το παιδί μετρούσε, οι δικές σου «ξένες»), μόνιμος αποκλεισμός
/// σου στην παραλλαγή «με τη σειρά των ημερών» (python: /home/claude/scratch/m1/guard4.py, battery.py).
/// Όριο της επιβεβαίωσης «3 μέρες σε 4 μέρες» (R4-A-1): μετρά αλλαγή ως [weightConfirmKg] kg ή [weightConfirmShare]· ως
/// [weightConfirmBigKg] kg ή [weightConfirmBigShare] μόνο όταν πριν από το νέο βάρος δεν υπάρχει καμία ζύγιση για πάνω από
/// [weightConfirmGap] μέρες (αρρώστια: 10 μέρες χωρίς ζύγιση). Ο επισκέπτης της εβδομάδας που λείπεις ζυγίζεται την
/// επομένη της δικής σου ζύγισης, άρα δεν περνά. Δική μας επιλογή (όχι από μελέτη): η αρρώστια −4,5…−6 kg των δοκιμών
/// (μαζί με 10 μέρες απώλειας και τον θόρυβο της ζυγαριάς) φτάνει ως 10,1 kg / 13,2% (capdist2.py) και μετρά πάντα με την
/// 3η ζύγιση· πάνω από 12 kg / 15% σε δύο εβδομάδες είναι πολύ πάνω από ό,τι χάνει ένας άνθρωπος ακόμα και σε αρρώστια.
/// Χωρίς αποκλεισμό: όσο δεν ζυγίζεται κανείς άλλος στο ίδιο διάστημα, το παλιό και το νέο βάρος σου ΔΕΝ «ζυγίζονται
/// μαζί» και η αναφορά είναι όλες οι ζυγίσεις ±14 ημερών (όπως πριν): μια μεγάλη αληθινή αλλαγή μετρά το αργότερο όταν η
/// τελευταία ζύγιση στο παλιό βάρος βγει από τις 14 μέρες (python lockout.py: −9…−20 kg μετά από κενό 7–21 ημερών, καμία
/// ζύγιση δεν περιμένει πάνω από 6 μέρες, καμία δεν μένει εκτός). Με άλλον άνθρωπο στη ζυγαριά στο ίδιο διάστημα: όταν το
/// νέο βάρος γίνει η κύρια ομάδα (το πολύ [weightGuardHorizon] μέρες).
/// Την ίδια μέρα ([guardDays], R4-A-2): δύο ζυγίσεις που δεν συμφωνούν (δύο άνθρωποι) → η πιο κοντινή στην αναφορά των
/// ΑΛΛΩΝ ημερών (πριν: η πρώτη που «μετρά», και στην αρχή, με λιγότερες από 3 γειτονικές μέρες, μετρούσε το παιδί που
/// ζυγίστηκε πρώτο)· χωρίς καμία άλλη ζύγιση ±[weightGuardHorizon] ημερών η μέρα είναι «σε αναμονή» ([guardDays] `unsure`).
/// Η κατάσταση μιας μέρας εξαρτάται μόνο από τις ζυγίσεις ±[weightGuardHorizon] ημερών γύρω της: το ιστορικό (trends.dart)
/// τη βγάζει ίδια από αυτό το κομμάτι (python: 0 διαφορές σε 19.487 μέρες, lightcone.py).
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

/// Round 3 (k1 · R3-A-1): ζύγιση που διαφέρει μετρά όταν το νέο βάρος φανεί σε ζυγίσεις τόσων διαφορετικών ημερών…
const weightConfirmDays = 3;

/// …που απέχουν τουλάχιστον τόσες μέρες, η πρώτη από την τελευταία. Δική μας επιλογή (όχι από μελέτη): ένα
/// Σαββατοκύριακο (2 μέρες, 1 μέρα απόσταση) δεν φτάνει ποτέ· η εβδομάδα μετά από μια αρρώστια φτάνει.
const weightConfirmSpan = 4;

/// Round 4 (m1 · R4-A-1): πόσες μέρες πριν και μετά κοιτά ο φύλακας για να βρει την «κύρια ομάδα» βάρους (το δικό σου
/// βάρος, [_reference]). Η κατάσταση μιας μέρας εξαρτάται μόνο από ζυγίσεις ως τόσες μέρες γύρω της (trends.dart).
const weightGuardHorizon = 42;

/// Round 4 (m1 · R4-A-1): δύο ζυγίσεις «την ίδια εβδομάδα» (ως τόσες μέρες η μία από την άλλη): για το ποιος ζυγίζεται
/// πιο συχνά τις εβδομάδες που ζυγίζονται και οι δύο.
const weightGuardSameWeek = 7;

/// Round 4 (m1 · R4-A-1): η επιβεβαίωση «[weightConfirmDays] μέρες σε [weightConfirmSpan] μέρες» μετρά αλλαγή ως τόσα kg…
const weightConfirmKg = 8.0;

/// …ή ως αυτό το μέρος της αναφοράς (10%).
const weightConfirmShare = 0.10;

/// Round 4 (m1 · R4-A-1): ως τόσα kg ή ως αυτό το μέρος της αναφοράς (15%) μόνο όταν πριν από το νέο βάρος δεν υπάρχει
/// καμία ζύγιση για πάνω από [weightConfirmGap] μέρες (π.χ. αρρώστια χωρίς ζύγιση)· και μια τέτοια αλλαγή που κρατά
/// πάνω από [weightGuardDays] μέρες μετρά (όπως πριν). Μεγαλύτερη αλλαγή δεν μετρά ποτέ με επιβεβαίωση ή διάρκεια· μετρά
/// μόνο όταν το νέο βάρος γίνει η ίδια η αναφορά ([_reference]).
const weightConfirmBigKg = 12.0;
const weightConfirmBigShare = 0.15;
const weightConfirmGap = 7;

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

  /// Διαφέρει πολύ, αλλά δεν τη βεβαίωσαν ή διέψευσαν ακόμα οι επόμενες ζυγίσεις: φαίνεται (σημειωμένη) ως η ζύγιση της
  /// μέρας· round 3 (k1 · R3-A-1): μένει έξω από ΚΑΘΕ υπολογισμό (θερμίδες, Τάσεις, εβδομάδα, γραφήματα, τάση σώματος).
  /// Πριν (γύρος 2) έμενε έξω μόνο από τη διόρθωση θερμίδων.
  pending,

  /// Οι ζυγίσεις πριν και μετά συμφωνούν μεταξύ τους και όχι μαζί της: δεν μετρά πουθενά (φαίνεται σημειωμένη).
  foreign,
}

/// Round 2 (R2-E-2): δύο ζυγίσεις μπορεί να είναι του ίδιου ανθρώπου: απέχουν ως [weightGuardKg] kg ή ως το
/// [weightGuardShare] της μεγαλύτερης (ίδια όρια με το [weightLooksForeign]).
bool weightsAgree(double a, double b) => (a - b).abs() <= math.max(weightGuardKg, weightGuardShare * math.max(a, b));

/// Round 2 (R2-E-2): η κατάσταση της ζύγισης [i] της [days] (μία ζύγιση ανά μέρα: η μέρα και τα kg, παλιότερη πρώτη,
/// διαφορετικές μέρες, πεπερασμένες τιμές). Round 4 (m1): κοιτά μόνο ζυγίσεις ως [weightGuardHorizon] μέρες πριν ή μετά,
/// άρα ένα κομμάτι του ιστορικού ±[weightGuardHorizon] ημερών γύρω από τη μέρα δίνει το ίδιο αποτέλεσμα με όλο
/// (trends.dart [weighInStatus]).
WeighStatus weighStatusAt(List<(DateTime, double)> days, int i) => _weighStatus(days, i, days[i].$2);

/// Οι θέσεις των ΑΛΛΩΝ ημερών της [s] ως [n] μέρες πριν ή μετά τη μέρα [i] (με τη σειρά των ημερών)· με [self] και η [i].
List<int> _within(List<(DateTime, double)> s, int i, int n, {bool self = false}) {
  final day = s[i].$1;
  var a = i;
  while (a > 0 && daysBetween(s[a - 1].$1, day) <= n) {
    a--;
  }
  var b = i;
  while (b < s.length - 1 && daysBetween(day, s[b + 1].$1) <= n) {
    b++;
  }
  return [
    for (var j = a; j <= b; j++)
      if (self || j != i) j,
  ];
}

/// Round 4 (m1 · R4-A-1): το βάρος με το οποίο συγκρίνεται η μέρα [i] (με τιμή [kg]), από την «κύρια ομάδα».
/// Οι ζυγίσεις ±[weightGuardHorizon] ημερών (με [vote] και η ίδια) χωρίζονται σε ομάδες: ταξινομημένες κατά βάρος, δύο
/// διπλανές που συμφωνούν ([weightsAgree]) είναι στην ίδια ομάδα. Δύο ομάδες «ζυγίζονται μαζί» όταν τα διαστήματά τους
/// (πρώτη ως τελευταία μέρα) μπαίνουν το ένα στο άλλο: δύο άνθρωποι. Ομάδες που η μία τελειώνει πριν αρχίσει η άλλη είναι
/// ο ίδιος άνθρωπος σε άλλο βάρος (γρήγορη απώλεια με κενά, αλλαγή μετά από αρρώστια). Κύρια: αυτή με τις περισσότερες
/// ζυγίσεις που έχουν ζύγιση άλλης ομάδας που ζυγίζεται μαζί της ως [weightGuardSameWeek] μέρες δίπλα (ποιος ζυγίζεται
/// πιο συχνά όταν ζυγίζονται και οι δύο: μια εβδομάδα που λείπεις δεν δίνει το προβάδισμα στο παιδί), μετά η μεγαλύτερη,
/// μετά η βαρύτερη, μετά η παλιότερη. Αναφορά: η διάμεσος των ζυγίσεων στις [near] (±[weightGuardDays] μέρες, όχι η ίδια)
/// που είναι της κύριας ομάδας ή ομάδας που ΔΕΝ ζυγίζεται μαζί της· αν καμία, όλων αυτών στις ±[weightGuardHorizon]
/// μέρες (όχι η ίδια)· αν καμία, το [kg]. [other]: με [vote], η ίδια είναι σε ΑΛΛΗ ομάδα που ζυγίζεται μαζί με την κύρια
/// (άλλος άνθρωπος, όχι εσύ σε άλλο βάρος).
({double ref, bool other}) _reference(List<(DateTime, double)> s, int i, double kg, List<int> near, {required bool vote}) {
  double v(int j) => j == i ? kg : s[j].$2;
  final hz = _within(s, i, weightGuardHorizon, self: vote);
  if (hz.isEmpty) return (ref: kg, other: false);
  final order = [...hz]..sort((a, b) {
      final c = v(a).compareTo(v(b));
      return c != 0 ? c : a.compareTo(b);
    });
  final group = <int, int>{};
  var last = 0;
  for (var k = 0; k < order.length; k++) {
    if (k > 0 && !weightsAgree(v(order[k - 1]), v(order[k]))) last++;
    group[order[k]] = last;
  }
  final groups = last + 1;
  // Πρώτη και τελευταία θέση (μέρα) κάθε ομάδας.
  final lo = List<int>.filled(groups, s.length);
  final hi = List<int>.filled(groups, -1);
  for (final j in hz) {
    final g = group[j]!;
    if (j < lo[g]) lo[g] = j;
    if (j > hi[g]) hi[g] = j;
  }
  bool together(int a, int b) => lo[a] < hi[b] && lo[b] < hi[a];
  var main = 0;
  if (groups > 1) {
    final size = List<int>.filled(groups, 0);
    final inter = List<int>.filled(groups, 0);
    final values = [for (var g = 0; g < groups; g++) <double>[]];
    for (var k = 0; k < hz.length; k++) {
      final j = hz[k];
      final g = group[j]!;
      size[g]++;
      values[g].add(v(j));
      var hit = false;
      for (var b = k - 1; !hit && b >= 0 && daysBetween(s[hz[b]].$1, s[j].$1) <= weightGuardSameWeek; b--) {
        final h = group[hz[b]]!;
        if (h != g && together(g, h)) hit = true;
      }
      for (var b = k + 1; !hit && b < hz.length && daysBetween(s[j].$1, s[hz[b]].$1) <= weightGuardSameWeek; b++) {
        final h = group[hz[b]]!;
        if (h != g && together(g, h)) hit = true;
      }
      if (hit) inter[g]++;
    }
    final med = [for (final x in values) _median(x)!];
    bool better(int a, int b) {
      if (inter[a] != inter[b]) return inter[a] > inter[b];
      if (size[a] != size[b]) return size[a] > size[b];
      if (med[a] != med[b]) return med[a] > med[b];
      return lo[a] < lo[b];
    }

    for (var g = 1; g < groups; g++) {
      if (better(g, main)) main = g;
    }
  }
  bool mine(int j) => group[j] == main || !together(group[j]!, main);
  final other = vote && !mine(i);
  final inner = [
    for (final j in near)
      if (mine(j)) s[j].$2,
  ];
  if (inner.isNotEmpty) return (ref: _median(inner)!, other: other);
  final rest = [
    for (final j in hz)
      if (j != i && mine(j)) s[j].$2,
  ];
  return (ref: rest.isEmpty ? kg : _median(rest)!, other: other);
}

/// Όπως το [weighStatusAt], με [kg] στη θέση της τιμής της μέρας [i] (για να δοκιμαστεί και άλλη ζύγιση της ίδιας μέρας).
WeighStatus _weighStatus(List<(DateTime, double)> s, int i, double kg) {
  final near = _within(s, i, weightGuardDays);
  // Λιγότερες από [weightGuardMinNeighbours] άλλες μέρες ±14: δεν κρίνεται (η αρχή· όπως πριν).
  if (near.length < weightGuardMinNeighbours) return WeighStatus.counted;
  final (:ref, :other) = _reference(s, i, kg, near, vote: true);
  final diff = (kg - ref).abs();
  if (diff <= math.max(weightGuardKg, weightGuardShare * ref)) return WeighStatus.counted;
  double at(int j) => j == i ? kg : s[j].$2;
  // Το «κομμάτι» της: οι διπλανές ζυγίσεις που συμφωνούν μαζί της, η καθεμία ως [weightGuardDays] μέρες από την επόμενη.
  bool linked(int a, int b) => daysBetween(s[a].$1, s[b].$1) <= weightGuardDays && weightsAgree(at(a), at(b));
  // Ξένη: κομμάτι ανάμεσα σε δύο ζυγίσεις (αμέσως πριν και αμέσως μετά, κοντά του) που συμφωνούν μεταξύ τους.
  bool bracketed(int first, int last) =>
      first > 0 &&
      last < s.length - 1 &&
      daysBetween(s[first - 1].$1, s[first].$1) <= weightGuardDays &&
      daysBetween(s[last].$1, s[last + 1].$1) <= weightGuardDays &&
      weightsAgree(at(first - 1), at(last + 1));
  final cap = math.max(weightConfirmKg, weightConfirmShare * ref);
  final big = math.max(weightConfirmBigKg, weightConfirmBigShare * ref);
  if (diff <= big) {
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
    // Νέο βάρος που κρατά πάνω από [weightGuardDays] μέρες: ο ίδιος άνθρωπος.
    if (longRun) return WeighStatus.counted;
    if (bracketed(first, last)) return WeighStatus.foreign;
    // Round 3 (k1 · R3-A-1): μετρά όταν το νέο βάρος φάνηκε σε [weightConfirmDays] μέρες σε [weightConfirmSpan] μέρες και
    // πάνω. Round 4 (m1 · R4-A-1): αλλαγή πάνω από [weightConfirmKg] kg / [weightConfirmShare] μόνο μετά από κενό
    // [weightConfirmGap] ημερών χωρίς ζύγιση (πριν: οποιοδήποτε μέγεθος, και −45 kg: το παιδί δύο Σαββατοκύριακα).
    final gapBefore = first == 0 || daysBetween(s[first - 1].$1, s[first].$1) > weightConfirmGap;
    return last - first + 1 >= weightConfirmDays &&
            daysBetween(s[first].$1, s[last].$1) >= weightConfirmSpan &&
            (diff <= cap || gapBefore)
        ? WeighStatus.counted
        : WeighStatus.pending;
  }
  // Round 4 (m1 · R4-A-1): πάνω από [weightConfirmBigKg] kg / [weightConfirmBigShare] από το δικό σου βάρος δεν μετρά
  // ποτέ με επιβεβαίωση ή διάρκεια (μόνο όταν το νέο βάρος γίνει η αναφορά, πιο πάνω). Το κομμάτι της ψάχνεται ως 2 ×
  // [weightGuardDays] μέρες γύρω της. Σύντομο: «ξένη» ανάμεσα σε ζυγίσεις που συμφωνούν, αλλιώς «σε αναμονή». Μεγάλο (πάνω
  // από [weightGuardDays] μέρες): «σε αναμονή» όσο είναι οι πιο πρόσφατες ζυγίσεις (καμία ως [weightGuardDays] μέρες
  // μετά), «ξένη» ανάμεσα σε ζυγίσεις που συμφωνούν (π.χ. το παιδί όσο έλειπες, μόλις ζυγιστείς ξανά), αλλιώς μετρά: το
  // παλιό σου βάρος πριν από μια μεγάλη αληθινή αλλαγή, όταν το νέο έγινε η κύρια ομάδα.
  const lim = 2 * weightGuardDays;
  var from = i;
  var to = i;
  var cutBefore = false;
  var cutAfter = false;
  while (from > 0 && linked(from - 1, from)) {
    if (daysBetween(s[from - 1].$1, s[i].$1) > lim) {
      cutBefore = true;
      break;
    }
    from--;
  }
  while (to < s.length - 1 && linked(to, to + 1)) {
    if (daysBetween(s[i].$1, s[to + 1].$1) > lim) {
      cutAfter = true;
      break;
    }
    to++;
  }
  final whole = !cutBefore && !cutAfter;
  final long = !whole || daysBetween(s[from].$1, s[to].$1) > weightGuardDays;
  // Άλλος άνθρωπος (ομάδα που ζυγίζεται μαζί με την κύρια, π.χ. το παιδί όσο έλειπες 4 εβδομάδες): ποτέ «μετρά» από εδώ.
  if (!long || other) return whole && bracketed(from, to) ? WeighStatus.foreign : WeighStatus.pending;
  final newest = !cutAfter && (to == s.length - 1 || daysBetween(s[to].$1, s[to + 1].$1) > weightGuardDays);
  if (newest) return WeighStatus.pending;
  return whole && bracketed(from, to) ? WeighStatus.foreign : WeighStatus.counted;
}

/// Η διάμεσος (null για άδεια λίστα).
double? _median(List<double> v) {
  if (v.isEmpty) return null;
  final o = [...v]..sort();
  final n = o.length;
  return n.isOdd ? o[n ~/ 2] : (o[n ~/ 2 - 1] + o[n ~/ 2]) / 2;
}

/// Δύο ζυγίσεις της ίδιας μέρας που δεν συμφωνούν μεταξύ τους ([weightsAgree]): δύο άνθρωποι.
bool _mixed(List<double> kgs) {
  for (var a = 0; a < kgs.length; a++) {
    for (var b = a + 1; b < kgs.length; b++) {
      if (!weightsAgree(kgs[a], kgs[b])) return true;
    }
  }
  return false;
}

/// Round 2 (R2-E-2): για κάθε μέρα ([days]: η μέρα και ΟΛΕΣ οι ζυγίσεις της σε kg, με τη σειρά που έγιναν, τουλάχιστον
/// μία· παλιότερη μέρα πρώτη), ποια ζύγιση μετρά ([pick]: θέση στη λίστα της μέρας) και η κατάσταση της μέρας.
/// Round 4 (m1 · R4-A-2): μέρα με ζυγίσεις που ΔΕΝ συμφωνούν μεταξύ τους (δύο άνθρωποι): η πιο κοντινή στην αναφορά
/// των άλλων ημερών ([_reference]· πριν: η πρώτη που μετρά, και στην αρχή, με λιγότερες από 3 γειτονικές μέρες, μετρούσε
/// όποιος ζυγιζόταν πρώτος). Χωρίς καμία άλλη μέρα ζύγισης ως [weightGuardHorizon] μέρες: [unsure], η μέρα «σε αναμονή»
/// (ζύγιση της μέρας η πρώτη· καμία δεν μετρά, καμία δεν είναι «ξένη») ως την επόμενη ζύγιση. Ζυγίσεις που συμφωνούν
/// (π.χ. πρωί και βράδυ): η πρώτη που μετρά· αν καμία, μια «σε αναμονή» πριν από μια «ξένη», η πιο κοντινή στην αναφορά
/// (round 3, R3-A-2). Η επιλογή ξανακρίνεται με τις επιλογές των άλλων ημερών (ως 3 φορές, ώσπου να μην αλλάζει)· η
/// κατάσταση κάθε μέρας βγαίνει στο τέλος από τη σειρά των ζυγίσεων της μέρας ([weighStatusAt]), όπως στο ιστορικό.
List<({int pick, WeighStatus status, bool unsure})> guardDays(List<(DateTime, List<double>)> days) {
  final n = days.length;
  bool alone(int i) =>
      (i == 0 || daysBetween(days[i - 1].$1, days[i].$1) > weightGuardHorizon) &&
      (i == n - 1 || daysBetween(days[i].$1, days[i + 1].$1) > weightGuardHorizon);
  final mixed = [for (final d in days) _mixed(d.$2)];
  final unsure = [for (var i = 0; i < n; i++) mixed[i] && alone(i)];
  var picks = List<int>.filled(n, 0);
  for (var round = 0; round < 3; round++) {
    final s = [for (var i = 0; i < n; i++) (days[i].$1, days[i].$2[picks[i]])];
    final next = [
      for (var i = 0; i < n; i++) days[i].$2.length < 2 || unsure[i] ? 0 : _pickDay(s, i, days[i].$2, mixed[i]),
    ];
    var same = true;
    for (var i = 0; i < n; i++) {
      if (next[i] != picks[i]) same = false;
    }
    if (same) break;
    picks = next;
  }
  final s = [for (var i = 0; i < n; i++) (days[i].$1, days[i].$2[picks[i]])];
  return [
    for (var i = 0; i < n; i++)
      (pick: picks[i], status: unsure[i] ? WeighStatus.pending : _weighStatus(s, i, s[i].$2), unsure: unsure[i]),
  ];
}

int _pickDay(List<(DateTime, double)> s, int i, List<double> kgs, bool mixed) {
  final ref = _reference(s, i, s[i].$2, _within(s, i, weightGuardDays), vote: false).ref;
  var best = 0;
  if (mixed) {
    for (var k = 1; k < kgs.length; k++) {
      if ((kgs[k] - ref).abs() < (kgs[best] - ref).abs()) best = k;
    }
    return best;
  }
  WeighStatus? bestStatus;
  var bestDistance = 0.0;
  for (var k = 0; k < kgs.length; k++) {
    final st = _weighStatus(s, i, kgs[k]);
    if (st == WeighStatus.counted) return k;
    final distance = (kgs[k] - ref).abs();
    final rank = st == WeighStatus.pending ? 0 : 1;
    final bestRank = bestStatus == WeighStatus.pending ? 0 : 1;
    if (bestStatus == null || rank < bestRank || (rank == bestRank && distance < bestDistance)) {
      best = k;
      bestStatus = st;
      bestDistance = distance;
    }
  }
  return best;
}
