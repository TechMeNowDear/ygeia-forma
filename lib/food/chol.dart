/// Κάρτα «Χοληστερίνη» (σχέδια 12/11): μετρά τα ΤΡΟΦΙΜΑ που έφαγες και ρίχνουν την LDL (διατροφή «portfolio», Jenkins
/// 2003, JAMA), από τις κατηγορίες της βάσης. Δεν προβλέπει τιμή LDL και δεν εκτιμά β-γλυκάνες (οι βάσεις δεν τις
/// δίνουν): ο στόχος σε γραμμάρια πίτουρου βγαίνει από την ετικέτα του προϊόντος σου.
///
/// Κανόνες (όλοι εδώ, ένα μέρος):
/// - Ξηροί καρποί: γραμμάρια της κατηγορίας «Ξηροί καρποί» (όχι οι σπόροι).
/// - Πίτουρο βρώμης: το τρόφιμο της βάσης (CIQUAL 9640) ή προϊόν σου που λέγεται «πίτουρο βρώμης».
/// - Όσπρια: μία «φορά» = μέρα με τουλάχιστον 40 g ξερά, ή το ίσο σε μαγειρεμένα (100 g βρασμένα ή κονσέρβα· τα
///   όσπρια φουσκώνουν περίπου 2,5 φορές).
/// - Ψάρι: μία «φορά» = μέρα με τουλάχιστον 100 g ψάρι ή θαλασσινά.
library;

import '../goals.dart' show fullDayShare;
import 'food_model.dart';

const branFoodId = 'C9640';
const legumesDryMinG = 40.0;
const legumesCookedFactor = 2.5;
const fishMinG = 100.0;

/// Από πόσες θερμίδες και πάνω μια μέρα έχει «πλήρη καταγραφή» και μπαίνει στους μέσους όρους: το 60% του στόχου
/// θερμίδων, ο ίδιος κανόνας με τη διόρθωση θερμίδων (τελικός έλεγχος, Συμβούλιο 2, Α4). Πριν ήταν σταθερές 1.200 kcal.
double fullDayKcalFor(int goalKcal) => fullDayShare * goalKcal;

String _plain(String s) {
  const from = 'άέήίόύώϊϋΐΰ';
  const to = 'αεηιουωιυιυ';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final k = from.indexOf(ch);
    b.write(k < 0 ? ch : to[k]);
  }
  return b.toString();
}

bool isBran(Food f) => f.id == branFoodId || _plain(f.name).contains('πιτουρο βρωμης');
bool isNuts(Food f) => f.cat == 'Ξηροί καρποί';
bool isLegumes(Food f) => f.cat == 'Όσπρια';
bool isFish(Food f) => f.cat == 'Ψάρια' || f.cat == 'Θαλασσινά';

/// Μαγειρεμένα όσπρια (βρασμένα, κονσέρβα): ζυγίζουν περίπου 2,5 φορές τα ξερά.
bool _cookedLegumes(Food f) => f.rawId != null || _plain(f.name).contains('κονσερβα') || _plain(f.name).contains('βρασμεν');

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

  int daysWithNuts(int target) => _full.where((d) => target > 0 && d.nutsG >= target - 1e-9).length;
  int daysWithBran(int target) => _full.where((d) => target > 0 && d.branG >= target - 1e-9).length;
  /// Μέρες με αλάτι κάτω από [max]. Μέρα με τρόφιμο χωρίς τιμή αλατιού δεν μετρά ως «εντάξει»: το πραγματικό αλάτι
  /// της είναι άγνωστο ([daysSaltUnknown]).
  int daysSaltOk(double max) => _full.where((d) => !d.saltMissing && d.salt < max).length;

  /// Μέρες με πλήρη καταγραφή όπου κάποιο τρόφιμο δεν έχει τιμή αλατιού στην πηγή του.
  int get daysSaltUnknown => _full.where((d) => d.saltMissing).length;

  /// Όσπρια και ψάρι: κάθε μέρα που έγιναν, και με λίγη καταγραφή (το φαγητό έγινε).
  int get legumes => days.where((d) => d.$2.legumes).length;
  int get fish => days.where((d) => d.$2.fish).length;
}
