/// «Εκτός συνηθισμένου»: ήπια ένδειξη όταν δύο ή τρεις δείκτες του πρωινού ξεφεύγουν μαζί
/// από τα συνηθισμένα σου. Χωρίς ιατρικούς ισχυρισμούς.
///
/// Κανόνες (εγκρίθηκαν 24/10, έγγραφο › «Τάσεις και επόμενα»):
/// - Ιστορικό = οι 28 προηγούμενες μέρες (χωρίς τη σημερινή), τουλάχιστον 14 τιμές.
/// - «Τυπική διακύμανση» από αυτές με ανθεκτικό τρόπο (διάμεσος απόλυτων αποκλίσεων × 1,4826), ώστε μια παλιά
///   περίεργη μέρα να μη χαλάει το μέτρο.
/// - «Συνήθως» (το κέντρο, που φαίνεται και στην κάρτα) = το ΕΝΑ «συνήθως» της εφαρμογής ([usualOf]: μεσαία τιμή των
///   14 πιο πρόσφατων από αυτές). Από 4/11 (δεύτερος έλεγχος υπολογισμών C7): πριν, η κάρτα έλεγε «συνήθως 58»
///   (μεσαία 28 ημερών) ενώ η κάρτα παλμών στην ίδια οθόνη έλεγε «59» (μέσος όρος 14 νυχτών).
/// - Ένας δείκτης ξεφεύγει όταν η απόκλιση είναι ΚΑΙ τουλάχιστον το ελάχιστο ΚΑΙ τουλάχιστον
///   2 τυπικές διακυμάνσεις: παλμοί στον ύπνο +3 bpm, θερμοκρασία δέρματος +0,4 °C, Energy Score −10.
///   (Έλεγχος 9/11, 03-Χ2: με MAD από 28 τιμές και στρογγυλοποίηση είναι στην πράξη ~1,7σ· ένας δείκτης ξεφεύγει τυχαία
///   ~4% των πρωινών. Η κάρτα θέλει δύο μαζί, οπότε ~0,2%. Το κείμενο της κάρτας λέει «1 στις 20», όχι «2σ».)
/// - Από 4/11 (κλινικός έλεγχος M1): το Energy Score / η ετοιμότητα του Oura βγαίνει εν μέρει από τους ίδιους παλμούς
///   και τη θερμοκρασία, άρα δεν είναι ανεξάρτητος δείκτης. Κάρτα μόνο όταν ξεφεύγουν ΚΑΙ οι παλμοί ΚΑΙ η θερμοκρασία·
///   η ετοιμότητα φαίνεται ως τρίτη γραμμή, χωρίς να μετρά μόνη της.
/// - Τρίτος έλεγχος (F2): η θερμοκρασία του Oura είναι ΗΔΗ απόκλιση από το συνηθισμένο του (temperature_deviation).
///   Το «συνήθως» της είναι 0 και η κάρτα δείχνει το ίδιο νούμερο με την κάρτα «Καρδιά και θερμοκρασία» (πριν
///   αφαιρούσε ξανά τη μεσαία τιμή των προηγούμενων αποκλίσεων: +0,3 εκεί, +0,5 εδώ, την ίδια νύχτα).
/// - Τρίτος έλεγχος (F4): η απόκλιση μετριέται από τα νούμερα όπως φαίνονται, όπως το κόκκινο χρώμα της Καρδιάς
///   (61,9 με συνήθως 59,2 φαίνεται «62 · συνήθως 59 · +3» και μετρά +3, όχι 2,6).
library;

import 'history.dart';
import 'shown.dart';
import 'sources.dart';
import 'trends.dart';

class UnusualRule {
  const UnusualRule(this.key, this.direction, this.minDiff);
  final String key;

  /// +1 = μας απασχολεί όταν ανεβαίνει, −1 = όταν πέφτει.
  final int direction;
  final double minDiff;

  MetricDef get def => trendMetrics.firstWhere((m) => m.key == key);
}

const unusualRules = [
  UnusualRule(K.sleepHr, 1, 3),
  UnusualRule(K.skinTemp, 1, 0.4),
  UnusualRule(K.energy, -1, 10),
];

const unusualBaselineDays = 28;
const unusualMinBaseline = 14;

class UnusualSignal {
  UnusualSignal({
    required this.rule,
    required this.value,
    required this.usual,
    required this.spread,
    required this.threshold,
    required this.baselineCount,
    this.source = Source.watch,
  });

  /// Από ποια συσκευή είναι η τιμή και το «συνηθισμένο» (πάντα η ίδια).
  final Source source;

  final UnusualRule rule;
  final double value;
  final double usual;

  /// Τυπική διακύμανση (ανθεκτική).
  final double spread;

  /// Πόσο πρέπει να ξεφύγει για να μετρήσει: το μεγαλύτερο από το ελάχιστο και τις 2 διακυμάνσεις.
  final double threshold;
  final int baselineCount;

  /// Απόκλιση προς την κατεύθυνση που μας απασχολεί (θετική = προς το «χειρότερο»), από τα νούμερα όπως φαίνονται
  /// (τρίτος έλεγχος F4: ίδιος κανόνας με την Καρδιά και το νούμερο της κάρτας).
  double get deviation => shownDiff(value, usual, rule.def.digits) * rule.direction;
  bool get off => deviation >= threshold;
}

class UnusualResult {
  UnusualResult({required this.day, required this.signals, required this.previousDayOff});
  final DateTime day;

  /// Οι δείκτες που είχαν σήμερα τιμή και αρκετό ιστορικό.
  final List<UnusualSignal> signals;

  /// Αν και χθες ξέφευγαν τουλάχιστον 2.
  final bool previousDayOff;

  int get offCount => signals.where((s) => s.off).length;

  bool _off(String key) => signals.any((s) => s.rule.key == key && s.off);

  /// Παλμοί ύπνου και θερμοκρασία μαζί (οι δύο ανεξάρτητοι δείκτες)· η ετοιμότητα δεν μετρά μόνη της.
  bool get show => _off(K.sleepHr) && _off(K.skinTemp);
}

double? _median(List<double> v) => median(v);

/// [plan]: κάθε δείκτης μόνο από την πηγή του. Το «συνηθισμένο» μετρά μόνο μέρες με την ίδια πηγή με σήμερα:
/// μετά από αλλαγή πηγής ξαναμαθαίνεται από την αρχή (θέλει πάλι τουλάχιστον [unusualMinBaseline] μέρες).
UnusualResult checkUnusual(Map<String, Map<String, double>> history, DateTime day,
    {bool checkPrevious = true, SourcePlan? plan}) {
  final p = plan ?? SourcePlan.samsungOnly;
  DateTime add(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
  final signals = <UnusualSignal>[];
  for (final rule in unusualRules) {
    final x = p.value(history, rule.key, day);
    if (x == null) continue;
    final seg = p.segmentStart(rule.key, day);
    final base = <double>[
      for (var i = 1; i <= unusualBaselineDays; i++)
        if (seg == null || !add(day, -i).isBefore(seg))
          if (p.value(history, rule.key, add(day, -i)) case final v?) v,
    ];
    if (base.length < unusualMinBaseline) continue;
    final med = _median(base)!;
    final mad = _median([for (final v in base) (v - med).abs()])!;
    final spread = mad * 1.4826;
    final threshold = rule.minDiff > 2 * spread ? rule.minDiff : 2 * spread;
    final source = p.sourceFor(rule.key, day);
    // Το «base» έχει πρώτη τη χθεσινή· το usualOf θέλει παλιότερη πρώτη. Oura θερμοκρασία: ήδη απόκλιση (F2), «συνήθως» 0.
    final usual = rule.key == K.skinTemp && source == Source.oura ? 0.0 : usualOf(base.reversed)!;
    signals.add(UnusualSignal(
      rule: rule,
      value: x,
      usual: usual,
      spread: spread,
      threshold: threshold,
      baselineCount: base.length,
      source: source,
    ));
  }
  final prev = checkPrevious ? checkUnusual(history, add(day, -1), checkPrevious: false, plan: p).show : false;
  return UnusualResult(day: day, signals: signals, previousDayOff: prev);
}

/// Κλινικός έλεγχος 4 (C1): το χρώμα του «+N» στους παλμούς ύπνου (Καρδιά, Σήμερα) το αποφασίζει ο ίδιος κανόνας με
/// το «Εκτός συνηθισμένου». Κόκκινο μόνο όταν οι παλμοί της νύχτας [night] ξεφεύγουν (τουλάχιστον 3 bpm ΚΑΙ 2 τυπικές
/// διακυμάνσεις σου)· αλλιώς ουδέτερο γκρι. Ένα +3 μόνο του είναι συχνά τυχαίο (αλκοόλ, ζέστη, αργό φαγητό).
bool sleepHrOff(Map<String, Map<String, double>> history, DateTime night, {SourcePlan? plan}) =>
    checkUnusual(history, DateTime(night.year, night.month, night.day), checkPrevious: false, plan: plan)
        .signals
        .any((s) => s.rule.key == K.sleepHr && s.off);
