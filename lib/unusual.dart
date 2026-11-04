/// «Εκτός συνηθισμένου»: ήπια ένδειξη όταν δύο ή τρεις δείκτες του πρωινού ξεφεύγουν μαζί
/// από τα συνηθισμένα σου. Χωρίς ιατρικούς ισχυρισμούς.
///
/// Κανόνες (εγκρίθηκαν 24/10, έγγραφο › «Τάσεις και επόμενα»):
/// - Συνηθισμένο = οι 28 προηγούμενες μέρες (χωρίς τη σημερινή), τουλάχιστον 14 τιμές.
/// - Μεσαία τιμή και «τυπική διακύμανση» με ανθεκτικό τρόπο (διάμεσος απόλυτων αποκλίσεων × 1,4826),
///   ώστε μια παλιά περίεργη μέρα να μη χαλάει το μέτρο.
/// - Ένας δείκτης ξεφεύγει όταν η απόκλιση είναι ΚΑΙ τουλάχιστον το ελάχιστο ΚΑΙ τουλάχιστον
///   2 τυπικές διακυμάνσεις: παλμοί στον ύπνο +3 bpm, θερμοκρασία δέρματος +0,4 °C, Energy Score −10.
/// - Κάρτα μόνο όταν ξεφεύγουν τουλάχιστον 2 το ίδιο πρωί.
/// - Από 4/11 (κλινικός έλεγχος M1): το Energy Score / η ετοιμότητα του Oura βγαίνει εν μέρει από τους ίδιους παλμούς
///   και τη θερμοκρασία, άρα δεν είναι ανεξάρτητος δείκτης. Κάρτα μόνο όταν ξεφεύγουν ΚΑΙ οι παλμοί ΚΑΙ η θερμοκρασία·
///   η ετοιμότητα φαίνεται ως τρίτη γραμμή, χωρίς να μετρά μόνη της.
library;

import 'history.dart';
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

  /// Απόκλιση προς την κατεύθυνση που μας απασχολεί (θετική = προς το «χειρότερο»).
  double get deviation => (value - usual) * rule.direction;
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
    signals.add(UnusualSignal(
      rule: rule,
      value: x,
      usual: med,
      spread: spread,
      threshold: threshold,
      baselineCount: base.length,
      source: p.sourceFor(rule.key, day),
    ));
  }
  final prev = checkPrevious ? checkUnusual(history, add(day, -1), checkPrevious: false, plan: p).show : false;
  return UnusualResult(day: day, signals: signals, previousDayOff: prev);
}
