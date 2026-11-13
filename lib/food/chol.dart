/// Κάρτα «Χοληστερίνη» (σχέδια 12/11): μετρά τα ΤΡΟΦΙΜΑ που έφαγες και ρίχνουν την LDL (διατροφή «portfolio»: Jenkins
/// 2003 και 2011, JAMA· Chiavaroli 2018, μετα-ανάλυση), από τις κατηγορίες της βάσης. Δεν προβλέπει τιμή LDL και δεν εκτιμά β-γλυκάνες (οι βάσεις δεν τις
/// δίνουν): ο στόχος σε γραμμάρια πίτουρου βγαίνει από την ετικέτα του προϊόντος σου.
///
/// Κανόνες (όλοι εδώ, ένα μέρος):
/// - Ξηροί καρποί: γραμμάρια της κατηγορίας «Ξηροί καρποί» της βάσης (καρποί δέντρων και αράπικα φιστίκια, όπως στη
///   διατροφή «portfolio»), ΟΧΙ οι σπόροι: οι ηλιόσποροι και οι κολοκυθόσποροι δεν μετρούν, το κουκουνάρι μετρά
///   ([_seedIds], [_treeNutIds]· έλεγχος round1, S2-3).
/// - Πίτουρο βρώμης: το τρόφιμο της βάσης (CIQUAL 9640) ή προϊόν σου που το όνομά του ΑΡΧΙΖΕΙ με «πίτουρο βρώμης»
///   ([branByName]· round7, R7-A3-1: πριν αρκούσε να το περιέχει, και ένα «Ψωμί τοστ με πίτουρο βρώμης» μετρούσε όλο του
///   το βάρος ως πίτουρο).
/// - Όσπρια: μία «φορά» = μέρα με τουλάχιστον 40 g ξερά, ή το ίσο σε μαγειρεμένα (100 g βρασμένα ή κονσέρβα· τα
///   όσπρια φουσκώνουν περίπου 2,5 φορές).
/// - Ψάρι: μία «φορά» = μέρα με τουλάχιστον 100 g ψάρι ή θαλασσινά.
/// - Τα ΔΙΚΑ ΣΟΥ προϊόντα (barcode, ετικέτα) μετρούν με ό,τι λέει το προϊόν ([Food.cholKind]: ξηροί καρποί, όσπρια, ψάρι,
///   πίτουρο βρώμης· έλεγχος round1, S2-1 / S1-9). Πριν δεν μετρούσαν ποτέ: 30 g δικά σου καρύδια έβγαιναν «0 g / 30 g».
///   Όταν το προϊόν λέει τι είναι, ισχύει ΜΟΝΟ αυτό (ούτε η κατηγορία ούτε το όνομα)· και το «Τίποτα» ([CholKind.none]).
/// - «Έπιασες τον στόχο» (γραμμάρια): με τον αριθμό όπως φαίνεται, ίδιος κανόνας στην κάρτα και στη σελίδα ([reachedGrams]).
/// - Αλάτι «κάτω από 5 g»: με το αλάτι όπως φαίνεται, με ένα δεκαδικό ([saltShown]· round7, R7-A3-3).
library;

import '../goals.dart' show fullDayShare;
import 'food_model.dart';

const branFoodId = 'C9640';
const legumesDryMinG = 40.0;
const legumesCookedFactor = 2.5;
const fishMinG = 100.0;

/// Δικό σου προϊόν οσπρίων: κάτω από τόσες kcal ανά 100 g είναι μαγειρεμένο (βρασμένο, κονσέρβα, βάζο) και μετρά
/// διά 2,5· από εκεί και πάνω είναι ξερό. Στη βάση τα ξερά όσπρια έχουν 301–350 kcal και τα βρασμένα ή της κονσέρβας
/// 112–148: το όριο είναι στη μέση, μακριά και από τα δύο.
const legumesDryMinKcal = 250.0;

/// Σπόροι που είναι (ή ήταν ως το #100) στην κατηγορία «Ξηροί καρποί» της βάσης: ηλιόσποροι (και το παλιό τους id),
/// κολοκυθόσποροι. Δεν μετρούν ως ξηροί καρποί: η μείωση της LDL έχει δειχθεί για καρπούς δέντρων και αράπικα φιστίκια
/// (Del Gobbo 2015, Am J Clin Nutr· Jenkins 2011, JAMA: «tree nuts and peanuts»), όχι για σπόρους. Με το id, ώστε να ισχύει και για παλιές
/// καταχωρίσεις που κρατούν την παλιά κατηγορία.
const _seedIds = {'C15011', 'C15045', 'U170557', 'U169415', 'U170562'};

/// Καρπός δέντρου που η βάση είχε ως το #100 στους «Σπόρους»: κουκουνάρι.
const _treeNutIds = {'C15025'};

/// Από πόσες θερμίδες και πάνω μια μέρα έχει «πλήρη καταγραφή» και μπαίνει στους μέσους όρους: το 60% του στόχου
/// θερμίδων, ο ίδιος κανόνας με τη διόρθωση θερμίδων (τελικός έλεγχος, Συμβούλιο 2, Α4). Πριν ήταν σταθερές 1.200 kcal.
double fullDayKcalFor(int goalKcal) => fullDayShare * goalKcal;

/// Πεζά, χωρίς τόνους, και το τελικό «ς» ως «σ». Έλεγχος round1 (S12-12): το `toLowerCase` της Dart δεν ξέρει το τελικό
/// σίγμα, οπότε ένα προϊόν γραμμένο με κεφαλαία («ΠΙΤΟΥΡΟ ΒΡΩΜΗΣ», συχνό στο Open Food Facts) έβγαινε «…βρωμησ» και δεν
/// αναγνωριζόταν ως πίτουρο βρώμης.
String _plain(String s) {
  const from = 'άέήίόύώϊϋΐΰς';
  const to = 'αεηιουωιυιυσ';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final k = from.indexOf(ch);
    b.write(k < 0 ? ch : to[k]);
  }
  return b.toString();
}

/// Προϊόν χωρίς «μετρά ως» που μετρά ως πίτουρο βρώμης από το όνομά του: μόνο όταν το όνομα ΑΡΧΙΖΕΙ με «πίτουρο βρώμης»
/// (κεφαλαία, τόνοι και τελικό «ς» δεν μετράνε). Για τα παλιά προϊόντα, από πριν υπάρξει το «μετρά ως», και για τη φόρμα,
/// που δείχνει τι θα μετρήσει.
bool branByName(String name) => _plain(name.trimLeft()).startsWith('πιτουρο βρωμησ'); // = _plain('πίτουρο βρώμης')

// Αν το προϊόν λέει τι είναι ([Food.cholKind]), ισχύει μόνο αυτό· αλλιώς η κατηγορία της βάσης (και το όνομα, για το πίτουρο).
bool isBran(Food f) => f.cholKind != null ? f.cholKind == CholKind.bran : f.id == branFoodId || branByName(f.name);
bool isNuts(Food f) => f.cholKind != null
    ? f.cholKind == CholKind.nuts
    : !_seedIds.contains(f.id) && (f.cat == 'Ξηροί καρποί' || _treeNutIds.contains(f.id));
bool isLegumes(Food f) => f.cholKind != null ? f.cholKind == CholKind.legumes : f.cat == 'Όσπρια';
bool isFish(Food f) => f.cholKind != null ? f.cholKind == CholKind.fish : f.cat == 'Ψάρια' || f.cat == 'Θαλασσινά';

/// Μαγειρεμένα όσπρια (βρασμένα, κονσέρβα): ζυγίζουν περίπου 2,5 φορές τα ξερά. Δικό σου προϊόν οσπρίων: και όταν οι
/// θερμίδες του δείχνουν μαγειρεμένο ([legumesDryMinKcal]), ό,τι όνομα κι αν του έδωσες.
bool _cookedLegumes(Food f) =>
    f.rawId != null ||
    _plain(f.name).contains('κονσερβα') ||
    _plain(f.name).contains('βρασμεν') ||
    (f.cholKind == CholKind.legumes && f.n.has(Nk.kcal) && f.n.amount(Nk.kcal) < legumesDryMinKcal);

class CholDay {
  CholDay(Iterable<LogEntry> entries) {
    for (final e in entries) {
      kcal += e.total(Nk.kcal);
      satFat += e.total(Nk.satFat);
      fiber += e.total(Nk.fiber);
      salt += e.total(Nk.salt);
      if (!e.food.n.has(Nk.satFat)) satMissing = true;
      if (!e.food.n.has(Nk.fiber)) fiberMissing = true;
      // Τρόφιμο χωρίς τιμή αλατιού μετρούσε ως 0 g και η μέρα έβγαινε «αλάτι εντάξει» (Συμβούλιο 2, μ4 / Α4).
      if (!e.food.n.has(Nk.salt)) saltMissing = true;
      final f = e.food;
      if (isBran(f)) {
        branG += e.grams;
      } else if (isNuts(f)) {
        nutsG += e.grams;
      } else if (isLegumes(f)) {
        legumesDryG += _cookedLegumes(f) ? e.grams / legumesCookedFactor : e.grams;
      } else if (isFish(f)) {
        fishG += e.grams;
      }
      count++;
    }
  }

  int count = 0;
  double kcal = 0, satFat = 0, fiber = 0, salt = 0;
  bool satMissing = false, fiberMissing = false, saltMissing = false;
  double nutsG = 0, branG = 0, legumesDryG = 0, fishG = 0;

  bool get legumes => legumesDryG >= legumesDryMinG - 1e-9;
  bool get fish => fishG >= fishMinG - 1e-9;

  /// Αρκετή καταγραφή για μέσους όρους, με στόχο [goalKcal] θερμίδες τη μέρα.
  bool fullFor(int goalKcal) => kcal >= fullDayKcalFor(goalKcal);

  /// Κορεσμένα ως % των θερμίδων (null χωρίς θερμίδες).
  double? get satPct => kcal <= 0 ? null : satFat * 9 / kcal * 100;
}

/// Έπιασες τον στόχο [target] γραμμαρίων με [g]; Με τον αριθμό όπως φαίνεται (στρογγυλεμένο στο γραμμάριο): 29,6 g
/// γράφονται «30 g / 30 g», άρα πιάνουν τα 30 (U3b-21). Round7 (R7-A3-2): ίδιος κανόνας στην κάρτα της Διατροφής και
/// στη σελίδα «Χοληστερίνη»· πριν η κάρτα έδειχνε «έγινε» και η σελίδα δεν μετρούσε τη μέρα.
bool reachedGrams(double g, int target) => target > 0 && g.round() >= target;

/// Το αλάτι όπως φαίνεται, με ένα δεκαδικό (round7, R7-A3-3): 4,96 g γράφονται «5,0 g», άρα ΔΕΝ είναι «κάτω από 5 g».
/// Πριν η οθόνη έγραφε «5,0 g / κάτω από 5 g» χωρίς προειδοποίηση και η εβδομάδα το μετρούσε «εντάξει».
double saltShown(double salt) => double.parse(salt.toStringAsFixed(1));

/// Η εβδομάδα Δευτέρα–Κυριακή της [day].
DateTime weekStart(DateTime day) => DateTime(day.year, day.month, day.day - (day.weekday - 1));

/// Σύνοψη για τις μέρες μιας εβδομάδας που ΕΧΟΥΝ τελειώσει ([days]: η κάθε μέρα με τις καταχωρίσεις της).
class CholWeek {
  CholWeek(this.days, {required this.goalKcal});

  /// Παλιότερη πρώτη. Μπαίνουν μόνο μέρες που έχουν τελειώσει.
  final List<(DateTime, CholDay)> days;

  /// Ο στόχος θερμίδων που ισχύει: κρίνει ποιες μέρες έχουν «πλήρη καταγραφή» ([CholDay.fullFor]).
  final int goalKcal;

  Iterable<CholDay> get _full => days.map((d) => d.$2).where((d) => d.fullFor(goalKcal));
  int get fullDays => _full.length;

  double? _mean(Iterable<double?> v) {
    final x = v.whereType<double>().toList();
    return x.isEmpty ? null : x.reduce((a, b) => a + b) / x.length;
  }

  double? get satPctMean => _mean(_full.map((d) => d.satPct));
  double? get fiberMean => _mean(_full.map((d) => d.fiber));

  /// Μέρες με πλήρη καταγραφή όπου κάποιο τρόφιμο δεν έχει τιμή κορεσμένων στην πηγή του. Εκείνο το τρόφιμο μετρά 0 g,
  /// άρα αν είναι πάνω από 0 ο [satPctMean] είναι «τουλάχιστον»: το πραγματικό ποσοστό είναι ίσο ή μεγαλύτερο (έλεγχος
  /// round1, S2-2· πριν ο μέσος όρος φαινόταν σαν ακριβής, και μπορούσε να δείχνει «κάτω από το όριο» ενώ δεν ήταν).
  int get daysSatUnknown => _full.where((d) => d.satMissing).length;

  /// Το ίδιο για τις φυτικές ίνες: ο [fiberMean] είναι τότε «τουλάχιστον».
  int get daysFiberUnknown => _full.where((d) => d.fiberMissing).length;

  int daysWithNuts(int target) => _full.where((d) => reachedGrams(d.nutsG, target)).length;
  int daysWithBran(int target) => _full.where((d) => reachedGrams(d.branG, target)).length;
  /// Μέρες με αλάτι κάτω από [max]. Μέρα με τρόφιμο χωρίς τιμή αλατιού δεν μετρά ως «εντάξει»: το πραγματικό αλάτι
  /// της είναι άγνωστο ([daysSaltUnknown]).
  int daysSaltOk(double max) => _full.where((d) => !d.saltMissing && saltShown(d.salt) < max).length;

  /// Μέρες με πλήρη καταγραφή όπου κάποιο τρόφιμο δεν έχει τιμή αλατιού στην πηγή του.
  int get daysSaltUnknown => _full.where((d) => d.saltMissing).length;

  /// Όσπρια και ψάρι: κάθε μέρα που έγιναν, και με λίγη καταγραφή (το φαγητό έγινε).
  int get legumes => days.where((d) => d.$2.legumes).length;
  int get fish => days.where((d) => d.$2.fish).length;
}
