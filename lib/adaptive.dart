/// Αυτόματη διόρθωση θερμίδων (συμφωνία 11/11, πριν από τις 7/12): από τα δικά σου δεδομένα, όχι από τύπο.
///
/// Ισοζύγιο ενέργειας: πραγματική κατανάλωση ≈ μέσες θερμίδες που έφαγες − (αλλαγή βάρους × 7.700 kcal/kg) / μέρες
/// (Hall 2008· η ίδια ιδέα με το MacroFactor). Κανένας αριθμός από AI: μόνο ό,τι έγραψες και ό,τι ζύγισε η ζυγαριά.
///
/// Κανόνες (όλοι εδώ, ένα μέρος). Τελευταία αλλαγή: τελικός έλεγχος, Συμβούλιο 2, αποφάσεις Α1–Α3 της 12/11.
/// - Η πρώτη εβδομάδα των στόχων δεν μετρά πουθενά ([adaptSkipDays], Α2): τότε φεύγουν κυρίως νερά και γλυκογόνο. Μετρημένα
///   σαν λίπος (7.700 kcal το κιλό) έβγαζαν την εκτίμηση περίπου 390 kcal πιο ψηλά για κάθε κιλό νερών (προσομοίωση).
///   Άρα η πρώτη εκτίμηση βγαίνει την 28η μέρα· την 21η η κάρτα λέει ότι μαζεύει ακόμα δεδομένα.
/// - Παράθυρο: οι τελευταίες ΤΕΛΕΙΩΜΕΝΕΣ μέρες (όχι σήμερα), από 21 ως 42 ([adaptWindows], Α1). Μετρά το μεγαλύτερο
///   παράθυρο που έχει αρκετά δεδομένα: με 42 μέρες το τυπικό σφάλμα της εκτίμησης πέφτει περίπου στο ένα τρίτο.
/// - Μέρα φαγητού που μετρά: τουλάχιστον 60% του στόχου θερμίδων. Λιγότερο σημαίνει σχεδόν πάντα ότι κάτι δεν γράφτηκε·
///   τέτοιες μέρες βγαίνουν από τον μέσο όρο (δεν θεωρούνται «λίγο φαγητό»).
///   Έλεγχος 17/11 (Κ1-L1, απόφαση): ισχύει και για μέρα με «Τελείωσα για σήμερα». Το κουμπί είναι ένα πάτημα, όχι απόδειξη
///   ότι γράφτηκαν όλα, και η υποκαταγραφή είναι το συχνότερο λάθος· μια αληθινά μικρή μέρα (αρρώστια) που βγαίνει έξω
///   ανεβάζει λίγο το «καις», ενώ μια ελλιπής που θα έμπαινε θα κατέβαζε τον στόχο. Ο ρυθμός απώλειας δεν αλλάζει
///   (προσομοίωση: 0,28 έναντι 0,26 kg την εβδομάδα).
/// - Αρκετά δεδομένα: φαγητό στα 2/3 των ημερών του παραθύρου (14 στις 21) και 2 ζυγίσεις την εβδομάδα (τουλάχιστον 6)
///   που απλώνονται στα 2/3 του παραθύρου (14 μέρες στις 21). Αλλιώς: «λίγα δεδομένα», καμία πρόταση.
/// - Τάση βάρους: ευθεία ελαχίστων τετραγώνων στις ζυγίσεις του παραθύρου. Από το πόσο απέχουν οι ζυγίσεις από την ευθεία
///   βγαίνει το τυπικό σφάλμα της κλίσης, δηλαδή πόσο σίγουρη είναι η εκτίμηση ([weightFit]).
/// - Αν η εκτίμηση βγει έξω από 70–140% του τύπου, κάτι λείπει (π.χ. μέρες χωρίς καταγραφή): καμία πρόταση από την
///   εκτίμηση. Round 7 (R7-A1-1): κάτω από το 70%, όταν το βάρος πάει καθαρά πιο ψηλά από τον ρυθμό σου, ο στόχος
///   κατεβαίνει από τη ζυγαριά ([lowLogProposal]).
/// - Νέος στόχος = εκτίμηση ± όσο χρειάζεται ο ρυθμός σου, στρογγυλεμένος στα 10, ποτέ κάτω από το κάτω όριο (το
///   λιγότερο που προτείνουν οι οδηγίες AHA/ACC/TOS 2013: 1.500 άνδρες, 1.200 γυναίκες), και το πολύ ±150 kcal ανά
///   εβδομαδιαίο έλεγχο. Αλλαγή κάτω από 30 kcal: «μένει ίδιος».
/// - Περιθώριο αβεβαιότητας (Α1): αλλαγή προτείνεται μόνο όταν η διαφορά είναι μεγαλύτερη από [adaptGuardSe] φορές το
///   τυπικό σφάλμα της εκτίμησης. Πριν, με 9 ζυγίσεις σε 21 μέρες, η κάρτα πρότεινε αλλαγή στο 84–93% των ελέγχων ενώ η
///   σωστή απάντηση ήταν «μένει ίδιος» (προσομοίωση με θόρυβο ζύγισης 0,3–0,6 kg)· με το περιθώριο πέφτει στο 7–9% όταν οι
///   ζυγίσεις είναι ανεξάρτητες. Με αληθινά νερά που κρατούν μέρες ανέβαινε στο 24–59%: γι' αυτό το σφάλμα διορθώνεται για
///   ζυγίσεις που μοιάζουν μεταξύ τους (έλεγχος 17/11, [weightFit]) και πέφτει περίπου στο 17%.
/// - Γρήγορη απώλεια (Α3): από [adaptFastWindowDays] μέρες πριν ως και σήμερα, χωρίς την πρώτη εβδομάδα, η κλίση
///   περνά το 1% του βάρους την εβδομάδα ακόμα και με περιθώριο [adaptFastGuardSe] τυπικών σφαλμάτων: πρόταση +150 kcal
///   αμέσως (κρατά τους μύες· Helms 2014, Garthe 2011).
///   Έλεγχος 20/11 (K1-C-01): το περιθώριο έγινε 2 τυπικά σφάλματα (πριν 1). Ο κανόνας κρίνεται ΚΑΘΕ μέρα, περίπου 70
///   φορές σε 26 εβδομάδες· με 1 σφάλμα, όποιος έχανε σταθερά 0,5% έβλεπε ψεύτικη ειδοποίηση (και «+150») στο 4–42% των
///   πορειών (ανάλογα με το πόσο κρατούν τα νερά), και όποιος έχανε 0,75% στο 79–92%· με 2 σφάλματα 1–16% και 21–34%.
///   Η αληθινά γρήγορη απώλεια πιάνεται λίγες μέρες αργότερα (1,3% την εβδομάδα: ως τη μέρα 42 στο 86% αντί για 98%·
///   1,6%: 99,5%, διάμεσος μέρα 22 αντί για 18)· ο εβδομαδιαίος έλεγχος τη βλέπει ούτως ή άλλως από τη μέρα 28
///   (προσομοίωση σε Python, k1-calc: fast_standalone.py, fast_fix.py).
/// - Μέρες: πάντα ημερολογιακές (DateTime(έτος, μήνας, μέρα − n)), ποτέ «μείον n × 24 ώρες»: στην αλλαγή ώρας μια μέρα
///   κρατά 23 ή 25 ώρες (Συμβούλιο 2, Σ2: ο απαντημένος έλεγχος ξαναέβγαινε την εβδομάδα μετά την αλλαγή του Οκτωβρίου).
///
/// Έλεγχος 13/11 (γύρος 1). Όλοι οι κανόνες αποδείχθηκαν πρώτα με αριθμούς (αντίγραφο σε Python) και μετά γράφτηκαν εδώ:
/// - Κενό καταγραφής (S1-1, [foodGap]): κανένα παράθυρο δεν περιέχει [adaptGapDays] ή περισσότερες συνεχόμενες μέρες που
///   δεν μετρούν. Ο μέσος όρος φαγητού βγαίνει μόνο από τις γραμμένες μέρες, η κλίση του βάρους από όλες: με δύο εβδομάδες
///   διακοπών χωρίς καταγραφή η εκτίμηση έβγαινε 280–510 kcal χαμηλά και ο στόχος κατέβαινε 150–450 kcal για 3–4
///   εβδομάδες. Τώρα το παράθυρο ξεκινά μετά το κενό· ως τότε η κάρτα το λέει και ο στόχος μένει ίδιος.
/// - Μέρα με αδύνατα πολλές θερμίδες (S11-3, [absurdDayKcal]): δεν μπαίνει στον μέσο όρο (π.χ. 2000 g αντί για 20 g).
/// - Γρήγορη απώλεια (S1-2): η πρόταση δεν περνά ποτέ όσα καις ([fastLossCap])· και δεν γίνεται καθόλου όταν το
///   ημερολόγιο δείχνει ότι τρως πολύ κάτω από τον στόχο (τότε δεν φταίει ο στόχος): αυτό το κρίνει το adaptive_check.dart.
/// - Απόσταση αλλαγών (S1-4, [adaptMinChangeDays]): έλεγχος που απαντήθηκε λιγότερο από 4 μέρες πριν από μια μέρα
///   ελέγχου καλύπτει και αυτήν (πριν: δύο βήματα των 150 kcal μέσα σε 24 ώρες, με τα ίδια δεδομένα).
///
/// Έλεγχος 13/11 (γύρος 2, g1). Πάλι πρώτα με αριθμούς σε Python, μετά εδώ:
/// - Το κενό ψάχνεται [adaptScanDays] μέρες πίσω (R2-A-2): και ένα κενό που άρχισε πριν από τις 42 μέρες κόβει το
///   παράθυρο. Πριν, έξι εβδομάδες μετά από μια αρρώστια χωρίς καταγραφή το παράθυρο άρχιζε ΜΕΣΑ στο κενό (με τις
///   ζυγίσεις της αρρώστιας) και η κάρτα πρότεινε −130 kcal χωρίς λόγο.
/// - Η απόσταση των 4 ημερών μετρά μόνο μετά από απάντηση που ΑΛΛΑΞΕ τον στόχο (R2-A-5, [answerChangedTarget]). Ένα
///   «Εντάξει» αργά (π.χ. την Παρασκευή, στο «μαζεύω δεδομένα») δεν μεταθέτει πια την πρώτη εκτίμηση κατά μία εβδομάδα.
///
/// Βαθύς έλεγχος 20/11 (κατηγορία 1). Πρώτα με αριθμούς σε Python (k1-calc, k1-science), μετά εδώ:
/// - Μετά από κενό καταγραφής, οι πρώτες [adaptSkipDays] μέρες της επιστροφής δεν μετρούν ([afterGapStart], K1-C-02): ίδια
///   φυσιολογία με την πρώτη εβδομάδα των στόχων (νερά και γλυκογόνο των διακοπών φεύγουν σε λίγες μέρες). Πριν, η πρώτη
///   εκτίμηση μετά από 10 μέρες γιορτών χωρίς καταγραφή έβγαινε 264–387 kcal ψηλά (με +1 ως +1,5 kg νερά) και πρότεινε
///   «+150»· με τον κανόνα −3 kcal. Κόστος: η εκτίμηση βγαίνει μία εβδομάδα αργότερα. Το ίδιο όριο ισχύει για το παράθυρο
///   της «γρήγορης απώλειας» ([fastNotBefore]).
/// - Πρόταση από παράθυρο μεγαλύτερο των 21 ημερών μόνο όταν και οι 21 τελευταίες μέρες δείχνουν προς την ίδια
///   κατεύθυνση ([recentAgrees], K1-C-02): ένα «φούσκωμα» νερών στην άκρη του μεγάλου παραθύρου (π.χ. γιορτές) μετακινεί
///   την κλίση πολύ ενώ το περιθώριο των ζυγίσεων μένει μικρό. Ψεύτικο «+150» έξι εβδομάδες μετά τις γιορτές: από 51% σε
///   27% των πορειών· όπου η αλλαγή χρειάζεται, ο τελικός στόχος και ο ρυθμός μένουν ίδιοι (διαφορά ≤ 6 kcal).
/// - Με «λιγότερο λίπος» και δείκτη μάζας σώματος κάτω από [adaptMinBmi], ο στόχος δεν κατεβαίνει ([belowHealthyWeight],
///   K1-S-05 / K1-C-04): κάτω από 18,5 καμία οδηγία δεν συστήνει απώλεια βάρους (Π.Ο.Υ.· NICE NG246).
library;

import 'dart:math' as math;

import 'format.dart' show daysBetween;
import 'goals.dart';

/// Το μικρότερο παράθυρο (και όσες μέρες μετά την αρχή βγαίνει η πρώτη κάρτα ελέγχου).
const adaptWindowDays = 21;

/// Τα παράθυρα που δοκιμάζονται, το μεγαλύτερο πρώτα (ολόκληρες εβδομάδες).
const adaptWindows = [42, 35, 28, 21];
const adaptMaxWindowDays = 42;

/// Οι πρώτες μέρες των στόχων που δεν μετρούν ούτε στην εκτίμηση ούτε στη «γρήγορη απώλεια»: νερά και γλυκογόνο.
const adaptSkipDays = 7;

/// Τα ελάχιστα για το παράθυρο των 21 ημερών· για μεγαλύτερο παράθυρο μεγαλώνουν αναλογικά ([adaptNeeds]).
const adaptMinIntakeDays = 14;
const adaptMinWeighIns = 6;
const adaptMinSpanDays = 14;
const adaptFullDayShare = fullDayShare;
const adaptMaxStep = 150;
const adaptMinStep = 30;

/// Τόσες συνεχόμενες μέρες που δεν μετρούν (καθόλου ή λίγη καταγραφή) είναι «κενό καταγραφής»: κανένα παράθυρο δεν το
/// περιέχει (έλεγχος 13/11, S1-1). Ένα Σαββατοκύριακο ή ένα τριήμερο δεν φτάνει· μια εβδομάδα διακοπών ναι.
const adaptGapDays = 5;

/// Πόσες μέρες πίσω (ως χθες) ψάχνεται το κενό καταγραφής, άρα και πόσες μέρες ημερολογίου χρειάζεται ο έλεγχος (γύρος 2,
/// R2-A-2): το μεγαλύτερο παράθυρο και [adaptGapDays] − 1 μέρες πριν από αυτό. Έτσι πιάνεται και κενό που άρχισε πριν από
/// το παράθυρο και φτάνει μέσα του. Όποιος καλεί το [estimateExpenditure] διαβάζει το φαγητό τόσες μέρες πίσω· αλλιώς οι
/// μέρες που δεν διαβάστηκαν μοιάζουν με μέρες χωρίς φαγητό.
/// Έλεγχος 20/11 (ανεξάρτητος έλεγχος K1, K1R-01): και [adaptSkipDays] μέρες ακόμα (53 αντί για 46). Με 46, ένα κενό που είχε
/// τελειώσει 42–48 μέρες πριν από το «χθες» δεν φαινόταν πια, και το παράθυρο των 42 ημερών άρχιζε ΜΕΣΑ στην εβδομάδα της
/// επιστροφής, που κατά το K1-C-02 δεν μετρά: έξι εβδομάδες μετά από γιορτές 24/12–2/1, ο έλεγχος της 15/2 έβγαζε την
/// εκτίμηση +60 ως +180 kcal ψηλά (ψεύτικο «+150» στο 3–10% των πορειών· με 53 μέρες: 1–2%).
const adaptScanDays = adaptMaxWindowDays + adaptGapDays - 1 + adaptSkipDays;

/// Ελάχιστες μέρες ανάμεσα σε δύο αλλαγές του στόχου, και από ένα «Εφάρμοσε» ως την επόμενη μέρα ελέγχου (S1-4, R2-A-5).
const adaptMinChangeDays = 4;

/// Μέρα με περισσότερες θερμίδες από αυτό δεν μπαίνει στον μέσο όρο: σχεδόν σίγουρα λάθος ποσότητα (S11-3).
/// Το μεγαλύτερο από 6.000 kcal και 2,5 φορές όσα καις κατά τον τύπο. Για σύγκριση: η πρόσληψη που αντέχει το πεπτικό
/// για πολλές μέρες είναι περίπου 2,5 φορές ο ΒΑΣΙΚΟΣ μεταβολισμός (Thurber 2019, Science Advances)· το όριο εδώ είναι
/// 2,5 φορές η ΣΥΝΟΛΙΚΗ κατανάλωση, δηλαδή πάνω και από αυτό. Μία μέρα μπορεί θεωρητικά να το περάσει (διαγωνισμός
/// φαγητού)· είναι δική μας επιλογή για λάθη πληκτρολόγησης, όχι ιατρικό όριο. Η μέρα μένει στο ημερολόγιο όπως είναι.
const adaptAbsurdKcal = 6000.0;
const adaptAbsurdTimes = 2.5;

double absurdDayKcal(double formulaTdee) => math.max(adaptAbsurdKcal, adaptAbsurdTimes * formulaTdee);

/// Η εκτίμηση γίνεται δεκτή μόνο από [adaptLowShare] ως [adaptHighShare] φορές τον τύπο· έξω από αυτό «κάτι λείπει».
const adaptLowShare = 0.7;
const adaptHighShare = 1.4;

/// Πόσα τυπικά σφάλματα πρέπει να ξεπερνά η διαφορά για να προταθεί αλλαγή στόχου.
const adaptGuardSe = 2.0;
const adaptFastLossPct = 0.01;

/// Η «γρήγορη απώλεια» δεν κρίνεται πριν από αυτή τη μέρα των στόχων.
const adaptFastFromDay = 14;
const adaptFastWindowDays = 21;

/// Πόσα τυπικά σφάλματα περιθώριο αφήνει η «γρήγορη απώλεια» πριν ειδοποιήσει. Έλεγχος 20/11 (K1-C-01): 2 (πριν 1),
/// όσο και ο εβδομαδιαίος έλεγχος ([adaptGuardSe]): ο κανόνας κρίνεται κάθε μέρα, και με 1 σφάλμα μία ρηχή ζύγιση αρκούσε.
const adaptFastGuardSe = 2.0;

/// Έλεγχος 20/11 (K1-S-05 / K1-C-04): κάτω από αυτόν τον δείκτη μάζας σώματος (όριο «λιποβαρούς», Π.Ο.Υ.· NICE NG246) ο
/// στόχος του «λιγότερο λίπος» δεν κατεβαίνει άλλο.
const adaptMinBmi = 18.5;

/// Το βάρος [kg] είναι κάτω από το φυσιολογικό για το ύψος των στόχων, και ο σκοπός είναι «λιγότερο λίπος».
bool belowHealthyWeight(Goals g, double kg) {
  if (g.aim != GoalAim.lose) return false;
  final m = g.heightCm / 100;
  return kg / (m * m) < adaptMinBmi;
}

/// Έλεγχος 20/11 (K1-S-01): εκτίμηση κάτω από αυτό το μέρος του τύπου (πάνω από ένα τυπικό σφάλμα των εξισώσεων συνολικής
/// κατανάλωσης: 339 kcal τη μέρα για άνδρες, περίπου 13%· NASEM 2023, Dietary Reference Intakes for Energy, Table S-1)
/// σημαίνει συχνότερα φαγητό που δεν γράφτηκε παρά χαμηλό μεταβολισμό: η υποκαταγραφή 12–25% είναι ο κανόνας σε μελέτες
/// με διπλά σημασμένο νερό (Subar 2003, Am J Epidemiol 158:1· Burrows 2019, Front Endocrinol 10:850). Η κάρτα το λέει.
const adaptLikelyUnderlogShare = 0.87;

/// Η πρώτη μέρα που μετρά μετά από κενό καταγραφής που τελείωσε τη μέρα [restart] (K1-C-02): [adaptSkipDays] μέρες μετά.
DateTime afterGapStart(DateTime restart) => DateTime(restart.year, restart.month, restart.day + adaptSkipDays);

/// Από πότε μετρούν οι ζυγίσεις της «γρήγορης απώλειας» μετά από κενό καταγραφής ([afterGapStart])· null χωρίς κενό, ή
/// όσο το κενό κρατά ακόμα (τότε η κάρτα δεν προτείνει τίποτα: δεν ξέρει πόσο τρως).
///
/// Το κόστος του κανόνα, γραμμένο (ανεξάρτητος έλεγχος K1, K1R-07): «κενό» είναι και οι μέρες από την αρχή των ημερών που
/// μετρούν ως την πρώτη γραμμένη μέρα ([foodGap] με «since»). Όποιος ζυγίζεται από την αρχή αλλά αρχίζει να γράφει φαγητό
/// δύο εβδομάδες αργότερα, και χάνει πράγματι 1,5% την εβδομάδα, βλέπει την κάρτα «χάνεις γρήγορα» τη μέρα 32 αντί για
/// τη 18. Το δεχόμαστε: αλλιώς τα νερά μιας δίαιτας που αρχίζει μαζί με την καταγραφή θα έδιναν ψεύτικο «+150». Και με
/// κενό 5 ημερών κάθε 4 εβδομάδες δεν βγαίνει ποτέ εκτίμηση (η κάρτα «κενό στο φαγητό» το λέει κάθε εβδομάδα).
DateTime? fastNotBefore(FoodGap? gap) {
  final restart = gap?.restart;
  return restart == null ? null : afterGapStart(restart);
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Τι χρειάζεται ένα παράθυρο [windowDays] ημερών για να βγει εκτίμηση: μέρες φαγητού, ζυγίσεις, άπλωμα ζυγίσεων σε μέρες.
({int intakeDays, int weighIns, int spanDays}) adaptNeeds(int windowDays) => (
      intakeDays: (windowDays * adaptMinIntakeDays / adaptWindowDays).ceil(),
      weighIns: math.max(adaptMinWeighIns, (windowDays * 2 / 7).ceil()),
      spanDays: (windowDays * adaptMinSpanDays / adaptWindowDays).ceil(),
    );

/// Ευθεία ελαχίστων τετραγώνων στις ζυγίσεις: κλίση (kg ανά μέρα) και το τυπικό της σφάλμα, από το πόσο απέχουν οι
/// ζυγίσεις από την ευθεία. null με λιγότερα από 2 σημεία ή όλα την ίδια μέρα· [se] null με λιγότερα από 3 σημεία.
/// Οι μέρες μετριούνται ημερολογιακά (μία ζύγιση ανά μέρα), άρα η αλλαγή ώρας δεν τις πειράζει.
({double slope, double? se})? weightFit(List<(DateTime, double)> weights) {
  final n = weights.length;
  if (n < 2) return null;
  final t0 = weights.first.$1;
  final xs = [for (final w in weights) daysBetween(t0, w.$1).toDouble()];
  final ys = [for (final w in weights) w.$2];
  final mx = xs.reduce((a, b) => a + b) / n;
  final my = ys.reduce((a, b) => a + b) / n;
  var sxx = 0.0, sxy = 0.0;
  for (var i = 0; i < n; i++) {
    sxx += (xs[i] - mx) * (xs[i] - mx);
    sxy += (xs[i] - mx) * (ys[i] - my);
  }
  if (sxx < 1e-9) return null;
  final slope = sxy / sxx;
  if (n < 3) return (slope: slope, se: null);
  var rss = 0.0, lag = 0.0;
  double? prev;
  for (var i = 0; i < n; i++) {
    final r = ys[i] - (my + slope * (xs[i] - mx));
    rss += r * r;
    if (prev != null) lag += r * prev;
    prev = r;
  }
  // Έλεγχος 17/11 (Κ1-H1): τα νερά, το γλυκογόνο και το έντερο κρατούν μέρες, άρα το λάθος μιας ζύγισης μοιάζει με της
  // προηγούμενης. Ο σκέτος τύπος τις μετρά σαν ανεξάρτητες και βγάζει το εύρος πιο στενό, και πιο στενό όσο πιο συχνά
  // ζυγίζεσαι: σε προσομοίωση η κάρτα άλλαζε τον στόχο στο 24–59% των ελέγχων ενώ ο στόχος ήταν ήδη σωστός. Διόρθωση: πόσο
  // μοιάζει κάθε απόκλιση με την προηγούμενη (ρ, από 0 ως 0,9) και το σφάλμα × √((1+ρ)/(1−ρ)). Με αυτό ~17% και για
  // Δευτέρα/Τετάρτη/Παρασκευή και για κάθε μέρα· η σύγκλιση του στόχου δεν αλλάζει.
  final rho = rss > 1e-12 ? (lag / rss).clamp(0.0, 0.9) : 0.0;
  final inflate = math.sqrt((1 + rho) / (1 - rho));
  return (slope: slope, se: math.sqrt(rss / (n - 2) / sxx) * inflate);
}

/// Έλεγχος 17/11 (Κ1-L6): ο τύπος για τους ελέγχους λογικής (70–140%, «αδύνατα πολλές θερμίδες», «όχι Χ που υπολόγισε ο
/// τύπος») με το ΤΕΛΕΥΤΑΙΟ βάρος. Πριν έμενε με το βάρος του οδηγού: μετά από 7 kg απώλεια ο τύπος έλεγε ~115 kcal
/// περισσότερα από όσα καις και μια κανονική υποκαταγραφή έβγαινε «κάτι λείπει» νωρίτερα. Μόνο όταν το βάρος απέχει
/// [formulaKgDrift] kg ή περισσότερο από του οδηγού ([kg] τότε ≠ null)· αλλιώς ίδιος αριθμός με το «Πώς υπολογίστηκε».
/// [weights]: παλιότερη πρώτη.
({double tdee, double? kg}) formulaNow(Goals g, List<(DateTime, double)> weights) {
  final kg = weights.isEmpty ? null : weights.last.$2;
  if (kg == null || !kg.isFinite || kg < 30 || kg > 300 || (kg - g.kg).abs() < formulaKgDrift) {
    return (tdee: g.calc.tdee, kg: null);
  }
  return (tdee: g.tdeeAt(kg), kg: kg);
}

/// Από πόση διαφορά βάρους (kg) από τον οδηγό οι έλεγχοι λογικής κρατούν τον τύπο με το τωρινό βάρος ([formulaNow]).
const formulaKgDrift = 2.0;

/// Κλίση (kg ανά μέρα) με ελάχιστα τετράγωνα· null με λιγότερα από 2 σημεία ή όλα την ίδια μέρα.
double? weightSlope(List<(DateTime, double)> weights) => weightFit(weights)?.slope;

/// Η εκτίμηση από τα δεδομένα.
class Expenditure {
  const Expenditure({
    required this.tdee,
    required this.meanIntake,
    required this.slopeKgWeek,
    required this.intakeDays,
    required this.weighIns,
    required this.from,
    required this.to,
    this.seKcal = 0,
    this.windowDays = adaptWindowDays,
  });

  /// Πραγματική κατανάλωση (kcal τη μέρα).
  final double tdee;
  final double meanIntake;

  /// Αλλαγή βάρους την εβδομάδα (αρνητικό = απώλεια).
  final double slopeKgWeek;
  final int intakeDays;
  final int weighIns;

  /// Το παράθυρο (από, ως και).
  final DateTime from, to;

  /// Τυπικό σφάλμα της εκτίμησης σε kcal τη μέρα: το τυπικό σφάλμα της κλίσης του βάρους × 7.700 (0: άγνωστο ή μηδενικό).
  final double seKcal;

  /// Πόσες μέρες έχει το παράθυρο που χρησιμοποιήθηκε (21 ως 42).
  final int windowDays;

  /// Το περιθώριο αβεβαιότητας (kcal): διαφορά ως εδώ δεν ξεχωρίζει από τον θόρυβο των ζυγίσεων.
  double get guardKcal => adaptGuardSe * seKcal;
}

enum AdaptStatus {
  ok,
  tooEarly,
  fewIntakeDays,
  fewWeighIns,
  implausible,

  /// Κενό καταγραφής που κρατά ως και χθες ([foodGap] χωρίς «restart»): καμία εκτίμηση.
  gapOpen,

  /// Μετά από κενό καταγραφής δεν έχουν μαζευτεί ακόμα [adaptWindowDays] μέρες που μετρούν (από το [afterGapStart]: η
  /// πρώτη εβδομάδα της επιστροφής δεν μετρά): καμία εκτίμηση.
  afterGap,
}

/// Κενό καταγραφής: από [from] ως και [to] καμία μέρα δεν μετρά. [restart]: η πρώτη γραμμένη μέρα μετά το κενό (η
/// εκτίμηση ξαναρχίζει [adaptSkipDays] μέρες αργότερα: [afterGapStart])· null όταν το κενό κρατά ως και χθες.
typedef FoodGap = ({DateTime from, DateTime to, DateTime? restart});

/// Το τελευταίο κενό καταγραφής ως χθες: [adaptGapDays] ή περισσότερες συνεχόμενες μέρες χωρίς φαγητό που μετρά (κάτω
/// από το 60% του στόχου, καθόλου καταγραφή, ή πάνω από το [absurdDayKcal]). Ψάχνει [adaptScanDays] μέρες πίσω, χωρίς την
/// πρώτη εβδομάδα των στόχων. null: κανένα κενό, ή καμία μέρα που να μετρά (τότε η κάρτα λέει «λίγα δεδομένα», όπως πριν).
/// Χωρίς [since] το ημερολόγιο θεωρείται ότι αρχίζει στην πρώτη μέρα που μετρά: οι μέρες πριν από αυτήν δεν είναι κενό.
/// Γύρος 2 (R2-A-2): πριν έψαχνε μόνο τις 42 μέρες του μεγαλύτερου παραθύρου, και ένα κενό που είχε αρχίσει νωρίτερα
/// μετρούσε μόνο με το κομμάτι του μέσα σε αυτές· κάτω από 5 μέρες «δεν ήταν κενό» και το παράθυρο άρχιζε μέσα του.
/// Τώρα κάθε κενό που φτάνει μέσα στις 42 μέρες φαίνεται ολόκληρο (ως 4 μέρες πριν από αυτές, που φτάνουν για τις 5).
FoodGap? foodGap({
  required Map<DateTime, double> intake,
  required DateTime today,
  required double formulaTdee,
  required int goalKcal,
  DateTime? since,
}) {
  final t = _day(today);
  final to = DateTime(t.year, t.month, t.day - 1);
  var lo = DateTime(to.year, to.month, to.day - (adaptScanDays - 1));
  if (since != null) {
    final firstCounted = DateTime(since.year, since.month, since.day + adaptSkipDays);
    if (lo.isBefore(firstCounted)) lo = firstCounted;
  }
  final full = adaptFullDayShare * goalKcal;
  final over = absurdDayKcal(formulaTdee);
  final counted = <DateTime>{};
  for (final e in intake.entries) {
    final d = _day(e.key);
    if (e.value >= full && e.value <= over && !d.isBefore(lo) && !d.isAfter(to)) counted.add(d);
  }
  if (counted.isEmpty) return null;
  FoodGap? gap;
  var run = 0;
  var seen = since != null;
  var runStart = lo;
  for (var d = lo; !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
    if (counted.contains(d)) {
      if (seen && run >= adaptGapDays) gap = (from: runStart, to: DateTime(d.year, d.month, d.day - 1), restart: d);
      run = 0;
      seen = true;
    } else {
      if (run == 0) runStart = d;
      run++;
    }
  }
  if (run >= adaptGapDays) return (from: runStart, to: to, restart: null);
  return gap;
}

/// [intake]: θερμίδες ανά μέρα (όπως φαίνονται στη Διατροφή), τουλάχιστον [adaptScanDays] μέρες πίσω από χθες (για το
/// κενό καταγραφής). [weights]: ζυγίσεις (μία ανά μέρα). [today]: σήμερα·
/// το παράθυρο τελειώνει χθες. [formulaTdee]: ο τύπος, για τον έλεγχο λογικής. [goalKcal]: για το «60% του στόχου».
/// [since]: η μέρα που ξεκίνησαν οι στόχοι· οι πρώτες [adaptSkipDays] μέρες δεν μετρούν (null: μετρούν όλες).
///
/// Δοκιμάζει τα παράθυρα του [adaptWindows] από το μεγαλύτερο: επιστρέφει το πρώτο που έχει αρκετά δεδομένα και λογική
/// εκτίμηση. Αν κανένα, την κατάσταση του μικρότερου (21 μέρες), ώστε η κάρτα να λέει τι λείπει «στις 3 τελευταίες
/// εβδομάδες». [AdaptStatus.tooEarly]: δεν έχουν περάσει ακόμα 21 μέρες που μετρούν.
/// Έλεγχος 13/11: κανένα παράθυρο δεν αρχίζει πριν από το τέλος του τελευταίου κενού καταγραφής ([foodGap])· από 20/11
/// (K1-C-02) ούτε στις πρώτες [adaptSkipDays] μέρες μετά από αυτό ([afterGapStart]).
/// [AdaptStatus.gapOpen] / [AdaptStatus.afterGap] όταν γι' αυτό δεν χωρά ακόμα παράθυρο 21 ημερών. Μέρες πάνω από το
/// [absurdDayKcal] δεν μετρούν.
({AdaptStatus status, Expenditure? est}) estimateExpenditure({
  required Map<DateTime, double> intake,
  required List<(DateTime, double)> weights,
  required DateTime today,
  required double formulaTdee,
  required int goalKcal,
  DateTime? since,
}) {
  // Χθες, ημερολογιακά (όχι «μείον 24 ώρες»: τη Δευτέρα μετά την αλλαγή ώρας του Μαρτίου έβγαινε Σάββατο 23:00).
  final t = _day(today);
  final to = DateTime(t.year, t.month, t.day - 1);
  final firstCounted = since == null ? null : DateTime(since.year, since.month, since.day + adaptSkipDays);
  var available = firstCounted == null ? adaptMaxWindowDays : daysBetween(firstCounted, to) + 1;
  if (available < adaptWindowDays) return (status: AdaptStatus.tooEarly, est: null);

  final full = adaptFullDayShare * goalKcal;
  final over = absurdDayKcal(formulaTdee);
  // Κενό καταγραφής (S1-1): το παράθυρο δεν αρχίζει πριν από την πρώτη μέρα που μετρά μετά το κενό.
  final gap = foodGap(intake: intake, today: t, formulaTdee: formulaTdee, goalKcal: goalKcal, since: since);
  if (gap != null) {
    final restart = gap.restart;
    if (restart == null) return (status: AdaptStatus.gapOpen, est: null);
    // Έλεγχος 20/11 (K1-C-02): οι πρώτες μέρες της επιστροφής δεν μετρούν (νερά, όπως στην πρώτη εβδομάδα των στόχων).
    final after = daysBetween(afterGapStart(restart), to) + 1;
    if (after < adaptWindowDays) return (status: AdaptStatus.afterGap, est: null);
    if (after < available) available = after;
  }
  ({AdaptStatus status, Expenditure? est}) result = (status: AdaptStatus.fewIntakeDays, est: null);
  for (final windowDays in adaptWindows) {
    if (windowDays > available) continue;
    final from = DateTime(to.year, to.month, to.day - (windowDays - 1));
    bool inWindow(DateTime d) => !_day(d).isBefore(from) && !_day(d).isAfter(to);
    final need = adaptNeeds(windowDays);
    final days = [
      for (final e in intake.entries)
        if (inWindow(e.key) && e.value >= full && e.value <= over) e.value,
    ];
    final ws = [
      for (final w in weights)
        if (inWindow(w.$1) && w.$2 >= 30 && w.$2 <= 300) (_day(w.$1), w.$2),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    if (days.length < need.intakeDays) {
      result = (status: AdaptStatus.fewIntakeDays, est: null);
      continue;
    }
    if (ws.length < need.weighIns || daysBetween(ws.first.$1, ws.last.$1) < need.spanDays) {
      result = (status: AdaptStatus.fewWeighIns, est: null);
      continue;
    }
    final fit = weightFit(ws);
    if (fit == null) {
      result = (status: AdaptStatus.fewWeighIns, est: null);
      continue;
    }
    final mean = days.reduce((a, b) => a + b) / days.length;
    final tdee = mean - fit.slope * kcalPerKg;
    final est = Expenditure(
      tdee: tdee,
      meanIntake: mean,
      slopeKgWeek: fit.slope * 7,
      intakeDays: days.length,
      weighIns: ws.length,
      from: from,
      to: to,
      seKcal: (fit.se ?? 0.0) * kcalPerKg,
      windowDays: windowDays,
    );
    if (tdee < adaptLowShare * formulaTdee || tdee > adaptHighShare * formulaTdee) {
      // Ίσως φταίνε παλιές μέρες με ξεχασμένα γεύματα: δοκιμάζεται και το μικρότερο παράθυρο.
      result = (status: AdaptStatus.implausible, est: est);
      continue;
    }
    return (status: AdaptStatus.ok, est: est);
  }
  return result;
}

/// Πρόταση νέου στόχου.
class AdaptProposal {
  const AdaptProposal({
    required this.current,
    required this.target,
    required this.est,
    required this.fastLoss,
    required this.floored,
    this.withinNoise = false,
    this.recentDiffers = false,
    this.underweight = false,
  });
  final int current;

  /// Ο νέος στόχος (ίδιος με τον τωρινό = «μένει ίδιος»).
  final int target;
  final Expenditure? est;

  /// Πρόταση λόγω γρήγορης απώλειας (> 1% την εβδομάδα).
  final bool fastLoss;
  final bool floored;

  /// Τα δεδομένα έδειχναν αλλαγή, αλλά μικρότερη από το περιθώριο αβεβαιότητας των ζυγίσεων: ο στόχος έμεινε ίδιος (Α1).
  final bool withinNoise;

  /// Έλεγχος 20/11 (K1-C-02): το μεγάλο παράθυρο ζητούσε αλλαγή, οι 21 τελευταίες μέρες όχι (ή προς την άλλη μεριά): ο
  /// στόχος έμεινε ίδιος ([recentAgrees]).
  final bool recentDiffers;

  /// Έλεγχος 20/11 (K1-S-05 / K1-C-04): τα δεδομένα ζητούσαν μείωση, αλλά το βάρος είναι κάτω από το φυσιολογικό
  /// ([belowHealthyWeight]): ο στόχος έμεινε ίδιος.
  final bool underweight;

  int get change => target - current;
  bool get same => change == 0;
}

int _round10(double v) => (v / 10).round() * 10;

/// Ο εβδομαδιαίος έλεγχος: [kgNow] = τρέχον βάρος (τάση ή τελευταία ζύγιση).
AdaptProposal proposeTarget({required Goals goals, required Expenditure est, required double kgNow}) {
  final current = goals.kcal;
  final delta = switch (goals.aim) {
    GoalAim.lose => -kgNow * goals.rate * kcalPerKg / 7,
    GoalAim.gain => kgNow * goals.rate * kcalPerKg / 7,
    GoalAim.keep => 0.0,
  };
  final floor = goals.male ? kcalFloorMale : kcalFloorFemale;
  var want = _round10(est.tdee + delta);
  var floored = false;
  if (want < floor) {
    want = floor;
    floored = true;
  }
  var change = (want - current).clamp(-adaptMaxStep, adaptMaxStep);
  if (change.abs() < adaptMinStep) change = 0;
  // Περιθώριο αβεβαιότητας (Συμβούλιο 2, Α1): διαφορά ως 2 τυπικά σφάλματα της εκτίμησης δεν ξεχωρίζει από τον θόρυβο των
  // ζυγίσεων (νερό, φαγητό). Τότε ο στόχος μένει ίδιος και η κάρτα το λέει.
  final withinNoise = change != 0 && (want - current).abs() <= est.guardKcal;
  if (withinNoise) change = 0;
  // Έλεγχος 20/11 (K1-S-05 / K1-C-04): κάτω από το φυσιολογικό βάρος ο στόχος του «λιγότερο λίπος» δεν κατεβαίνει.
  final underweight = change < 0 && belowHealthyWeight(goals, kgNow);
  if (underweight) change = 0;
  var target = current + change;
  if (target < floor) target = floor;
  // «Δεν κατεβαίνει κάτω από το κάτω όριο» μόνο όταν ο νέος στόχος ΕΙΝΑΙ στο όριο (Συμβούλιο 2, μ1). Πριν το έλεγε και
  // όταν το βήμα των 150 τον άφηνε πολύ πιο πάνω (π.χ. 2.000 → 1.850 με όριο 1.500).
  return AdaptProposal(
    current: current,
    target: target,
    est: est,
    fastLoss: false,
    floored: floored && target == floor,
    withinNoise: withinNoise,
    underweight: underweight,
  );
}

/// Έλεγχος 20/11 (K1-C-02): η πρόταση [p] από παράθυρο μεγαλύτερο των [adaptWindowDays] ημερών στέκει μόνο όταν και η
/// εκτίμηση των 21 τελευταίων ημερών ([recent]) ζητά αλλαγή προς την ίδια κατεύθυνση (τουλάχιστον [adaptMinStep] kcal,
/// χωρίς το περιθώριο των ζυγίσεων: εδώ μετρά μόνο η κατεύθυνση). Αλλιώς ο στόχος μένει ίδιος ([AdaptProposal.recentDiffers])
/// και ο επόμενος έλεγχος ξανακοιτά. [recent] null (λίγα δεδομένα στις 21 τελευταίες μέρες): η πρόταση μένει όπως είναι.
AdaptProposal recentAgrees({required AdaptProposal p, required Goals goals, required Expenditure? recent, required double kgNow}) {
  if (p.change == 0 || recent == null) return p;
  final direction = proposeTarget(
      goals: goals,
      est: Expenditure(
          tdee: recent.tdee,
          meanIntake: recent.meanIntake,
          slopeKgWeek: recent.slopeKgWeek,
          intakeDays: recent.intakeDays,
          weighIns: recent.weighIns,
          from: recent.from,
          to: recent.to,
          windowDays: recent.windowDays),
      kgNow: kgNow);
  if (direction.change != 0 && (direction.change > 0) == (p.change > 0)) return p;
  return AdaptProposal(current: p.current, target: p.current, est: p.est, fastLoss: false, floored: false, recentDiffers: true);
}

/// Ο ρυθμός που διάλεξες, σε kg την εβδομάδα για βάρος [kg]: αρνητικός για «λιγότερο λίπος», 0 για «ίδιο βάρος».
double plannedKgWeek(Goals goals, double kg) => switch (goals.aim) {
      GoalAim.lose => -kg * goals.rate,
      GoalAim.keep => 0.0,
      GoalAim.gain => kg * goals.rate,
    };

/// Round 7 (R7-A1-1): λίγη καταγραφή, και το βάρος πάει πιο ψηλά από τον ρυθμό σου.
///
/// Όταν η εκτίμηση βγαίνει κάτω από το [adaptLowShare] του τύπου, το ημερολόγιο γράφει λιγότερο από όσο τρως (σχεδόν
/// πάντα). Ως τώρα τότε δεν άλλαζε τίποτα («κάτι λείπει»), όσο κι αν ανέβαινε το βάρος: σε προσομοίωση με 20% ξεχασμένο
/// φαγητό και κατανάλωση 10% κάτω από τον τύπο, το βάρος ανέβηκε 5 kg σε 16 εβδομάδες με στόχο «λιγότερο λίπος».
/// Η εκτίμηση εδώ δεν μετρά (δεν είναι αξιόπιστη)· μετρά μόνο η ζυγαριά:
/// - Η κλίση του βάρους στο παράθυρο, μείον τον ρυθμό σου ([plannedKgWeek]), × 7.700 ÷ 7 = πόσες kcal τη μέρα τρως πάνω
///   από όσο θέλει ο ρυθμός σου. Πρέπει να ξεπερνά το περιθώριο των ζυγίσεων ([Expenditure.guardKcal], 2 τυπικά
///   σφάλματα, ίδιο με τον εβδομαδιαίο έλεγχο)· αλλιώς null (μένει το «κάτι λείπει»).
/// - Ο στόχος κατεβαίνει τόσο, στρογγυλεμένο στα 10, το πολύ [adaptMaxStep]· ποτέ κάτω από το κάτω όριο· κάτω από
///   [adaptMinStep] καμία αλλαγή. Μόνο προς τα κάτω: με πολύ λίγη καταγραφή, ένας ψηλότερος στόχος δεν θα έφτανε στο πιάτο.
/// Απόδειξη πρώτα σε Python (αντίγραφο του #104, 120 επαναλήψεις ανά περίπτωση, γιορτές, αρρώστια, διακοπές): με
/// 10–40% ξεχασμένο φαγητό ο στόχος πάει προς τον σωστό ρυθμό (ως το κάτω όριο)· με σωστή καταγραφή οι προτάσεις είναι
/// ίδιες με πριν σε κάθε επανάληψη όπου ο παλιός κανόνας δεν έλεγε «κάτι λείπει»· οι άσκοπες αλλαγές όταν δεν χρειάζεται
/// καμία μένουν 8–12% των ελέγχων (το πολύ +0,1 μονάδα)· η αρχή (16/11, πρώτη εκτίμηση 14/12) ίδια.
AdaptProposal? lowLogProposal({required Goals goals, required Expenditure est, required double kgNow, double? formulaTdee}) {
  if (est.tdee >= adaptLowShare * (formulaTdee ?? goals.calc.tdee)) return null;
  // Έλεγχος 20/11 (K1-S-05 / K1-C-04): κάτω από το φυσιολογικό βάρος καμία μείωση.
  if (belowHealthyWeight(goals, kgNow)) return null;
  final excess = (est.slopeKgWeek - plannedKgWeek(goals, kgNow)) * kcalPerKg / 7;
  if (excess <= est.guardKcal) return null;
  final current = goals.kcal;
  final floor = goals.male ? kcalFloorMale : kcalFloorFemale;
  var target = current - math.min<int>(adaptMaxStep, _round10(excess));
  var floored = false;
  if (target < floor) {
    target = floor;
    floored = true;
  }
  if (current - target < adaptMinStep) return null;
  return AdaptProposal(current: current, target: target, est: est, fastLoss: false, floored: floored);
}

/// Το παράθυρο της «γρήγορης απώλειας» σήμερα: από πότε ως και σήμερα. Οι [adaptFastWindowDays] τελευταίες μέρες, ΧΩΡΙΣ
/// τις πρώτες [adaptSkipDays] μέρες των στόχων (νερά και γλυκογόνο). null αν η αρχή των στόχων δεν διαβάζεται.
///
/// Έλεγχος 20/11 (K1-C-02): [notBefore] = η πρώτη μέρα που μετρά μετά από κενό καταγραφής ([fastNotBefore])· οι μέρες πριν
/// από αυτήν (τα νερά της επιστροφής) δεν κρίνονται.
(DateTime, DateTime)? fastLossWindow({required Goals goals, required DateTime today, DateTime? notBefore}) {
  final since = DateTime.tryParse(goals.since);
  if (since == null) return null;
  final to = _day(today);
  // Έλεγχος 17/11 (Κ1-L2, απόφαση): από την αρχή ως σήμερα απέχουν [adaptFastWindowDays] μέρες (3 εβδομάδες, όσο γράφει η
  // κάρτα· 22 ημερολογιακές μέρες μαζί με τις δύο άκρες). Μένει έτσι: οι κανόνες και οι πιθανότητες του Α3 βγήκαν με αυτό.
  var from = DateTime(to.year, to.month, to.day - adaptFastWindowDays);
  final firstCounted = DateTime(since.year, since.month, since.day + adaptSkipDays);
  if (from.isBefore(firstCounted)) from = firstCounted;
  if (notBefore != null && from.isBefore(_day(notBefore))) from = _day(notBefore);
  return (from, to);
}

/// Οι ζυγίσεις που κρίνουν τη «γρήγορη απώλεια» σήμερα ([fastLossWindow]), παλιότερη πρώτη. Ένα μέρος, για να κρίνει
/// και να δείχνει η κάρτα ακριβώς τις ίδιες ζυγίσεις.
List<(DateTime, double)> fastLossWeights(
    {required Goals goals, required List<(DateTime, double)> weights, required DateTime today, DateTime? notBefore}) {
  final window = fastLossWindow(goals: goals, today: today, notBefore: notBefore);
  if (window == null) return const [];
  final (from, to) = window;
  return [
    for (final w in weights)
      if (!_day(w.$1).isBefore(from) && !_day(w.$1).isAfter(to)) (_day(w.$1), w.$2),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
}

/// Γρήγορη απώλεια, η μέτρηση: η κλίση των ζυγίσεων του [fastLossWindow] περνά το −1% του βάρους την εβδομάδα ακόμα και
/// αν της προστεθούν [adaptFastGuardSe] τυπικά σφάλματα (με ≥ 4 ζυγίσεις σε ≥ 10 μέρες). Μόνο σε «λιγότερο λίπος», από τη
/// 14η μέρα των στόχων. Στην πράξη η νωρίτερη ειδοποίηση βγαίνει τη 17η–18η μέρα (10 μέρες ζυγίσεων μετά την πρώτη εβδομάδα).
/// Επιστρέφει την κλίση (kg την εβδομάδα, αρνητική) και το βάρος της τελευταίας ζύγισης· null όταν δεν ισχύει.
({double slopeKgWeek, double kg})? fastLossSlope(
    {required Goals goals, required List<(DateTime, double)> weights, required DateTime today, DateTime? notBefore}) {
  if (goals.aim != GoalAim.lose) return null;
  final since = DateTime.tryParse(goals.since);
  if (since == null || daysBetween(since, today) < adaptFastFromDay) return null;
  final ws = fastLossWeights(goals: goals, weights: weights, today: today, notBefore: notBefore);
  if (ws.length < 4 || daysBetween(ws.first.$1, ws.last.$1) < 10) return null;
  final fit = weightFit(ws);
  if (fit == null) return null;
  final kg = ws.last.$2;
  // Περιθώριο (Συμβούλιο 2, Α3· έλεγχος 20/11, K1-C-01: δύο τυπικά σφάλματα): η ειδοποίηση βγαίνει μόνο όταν η κλίση
  // είναι πέρα από το όριο κατά [adaptFastGuardSe] τυπικά σφάλματα. Μια ρηχή ζύγιση (αφυδάτωση) δεν φτάνει για να τη βγάλει.
  final cautious = fit.slope + adaptFastGuardSe * (fit.se ?? 0.0);
  if (cautious * 7 >= -adaptFastLossPct * kg) return null;
  return (slopeKgWeek: fit.slope * 7, kg: kg);
}

/// Έλεγχος 20/11 (ανεξάρτητος έλεγχος K1): μπορεί να βγει «γρήγορη απώλεια» σήμερα, με ΟΠΟΙΟΔΗΠΟΤΕ όριο [fastNotBefore];
/// Φθηνός ΑΝΑΓΚΑΙΟΣ όρος, μόνο από τις ζυγίσεις (χωρίς το ημερολόγιο): σκοπός «λιγότερο λίπος», μέρα των στόχων, και ≥ 4
/// ζυγίσεις σε ≥ 10 μέρες στο πλήρες παράθυρο. Κάθε στενότερο παράθυρο (μετά από κενό) έχει λιγότερες ή ίσες ζυγίσεις και
/// μέρες, άρα όταν εδώ βγαίνει «όχι» δεν βγαίνει ειδοποίηση με κανένα όριο. ΔΕΝ κοιτά την κλίση: η κλίση του πλήρους
/// παραθύρου μπορεί να είναι ήπια (ζυγίσεις των διακοπών) ενώ του στενού είναι γρήγορη.
bool fastLossPossible({required Goals goals, required List<(DateTime, double)> weights, required DateTime today}) {
  if (goals.aim != GoalAim.lose) return false;
  final since = DateTime.tryParse(goals.since);
  if (since == null || daysBetween(since, today) < adaptFastFromDay) return false;
  final ws = fastLossWeights(goals: goals, weights: weights, today: today);
  return ws.length >= 4 && daysBetween(ws.first.$1, ws.last.$1) >= 10;
}

/// Πάνω από εδώ η «γρήγορη απώλεια» δεν ανεβάζει τον στόχο (έλεγχος 13/11, S1-2): όσα καις, από την τελευταία εκτίμηση
/// με τα δεδομένα σου, αλλιώς από τον τύπο, στα 10. Πριν, το +150 επαναλαμβανόταν κάθε εβδομάδα χωρίς τέλος και ο στόχος
/// «λιγότερο λίπος» έφτανε πάνω από την κατανάλωση.
int fastLossCap(Goals goals) => _round10(goals.tdeeEst ?? goals.calc.tdee);

/// Γρήγορη απώλεια, η πρόταση: +[adaptMaxStep] kcal, ποτέ πάνω από το [fastLossCap]. null όταν η [fastLossSlope] δεν
/// ισχύει ή όταν ο στόχος είναι ήδη εκεί (μένουν λιγότερες από [adaptMinStep] kcal ως το όριο).
AdaptProposal? fastLossCheck(
    {required Goals goals, required List<(DateTime, double)> weights, required DateTime today, DateTime? notBefore}) {
  if (fastLossSlope(goals: goals, weights: weights, today: today, notBefore: notBefore) == null) return null;
  final current = goals.kcal;
  final target = math.min(current + adaptMaxStep, fastLossCap(goals));
  if (target - current < adaptMinStep) return null;
  return AdaptProposal(current: current, target: target, est: null, fastLoss: true, floored: false);
}

/// Μέρα εβδομαδιαίου ελέγχου: η μέρα της εβδομάδας που φτιάχτηκαν οι στόχοι, από την 21η μέρα και μετά. Αν χάθηκε
/// (δεν άνοιξες την εφαρμογή εκείνη τη μέρα), μένει ανοιχτός ως τον επόμενο. Μία φορά για κάθε μέρα ελέγχου.
/// Έλεγχος 13/11 (S1-4): έλεγχος που απαντήθηκε με «Εφάρμοσε» λιγότερο από [adaptMinChangeDays] μέρες πριν από μια μέρα
/// ελέγχου καλύπτει και αυτήν. Πριν, απάντηση την Κυριακή και νέα κάρτα τη Δευτέρα έδιναν δύο βήματα (−290 kcal) σε 24 ώρες.
/// Γύρος 2 (R2-A-5): μόνο όταν η απάντηση ΑΛΛΑΞΕ τον στόχο ([answerChangedTarget]). Μια απάντηση που δεν άλλαξε τίποτα
/// («Εντάξει», «Όχι τώρα») καλύπτει μόνο τις μέρες ελέγχου ως και τη μέρα της, όπως πριν από το S1-4.
bool checkInDue({required Goals goals, required DateTime today, String? lastCheckIn}) {
  final since = DateTime.tryParse(goals.since);
  if (since == null) return false;
  final t = _day(today);
  // Ημερολογιακά (Συμβούλιο 2, Σ2). Με «μείον n × 24 ώρες», την εβδομάδα μετά την αλλαγή ώρας του Οκτωβρίου η μέρα ελέγχου
  // έβγαινε 01:00 αντί για 00:00, και ένας έλεγχος που είχες ήδη απαντήσει ξαναέβγαινε· τον Μάρτιο έβγαινε η προηγούμενη
  // μέρα στις 23:00 και ο πρώτος έλεγχος χανόταν για μια εβδομάδα.
  final back = (t.weekday - since.weekday + 7) % 7;
  final dueDay = DateTime(t.year, t.month, t.day - back);
  if (daysBetween(since, dueDay) < adaptWindowDays) return false;
  final last = lastCheckIn == null ? null : DateTime.tryParse(lastCheckIn);
  if (last == null) return true;
  if (answerChangedTarget(goals, last)) return daysBetween(last, dueDay) >= adaptMinChangeDays;
  return daysBetween(last, dueDay) > 0;
}

/// Την [day] άλλαξε ο στόχος από κάρτα («Εφάρμοσε»: εβδομαδιαίος έλεγχος ή γρήγορη απώλεια)· από το ιστορικό [Goals.log].
bool answerChangedTarget(Goals goals, DateTime day) {
  for (final l in goals.log) {
    if (!l.applied) continue;
    final d = DateTime.tryParse(l.day);
    if (d != null && daysBetween(d, day) == 0) return true;
  }
  return false;
}

/// Βοηθητικό για προβολή: «−0,4 kg την εβδομάδα».
double roundTo(double v, int digits) {
  final p = math.pow(10, digits);
  return (v * p).round() / p;
}
