/// Ένα αποτέλεσμα εξέτασης όπως το έδωσε το εργαστήριο, μαζί με ό,τι χρειάζεται για σωστή σύγκριση (12/11).
/// Κρατάμε ΠΑΝΤΑ την τιμή, τη μονάδα, τα όρια και το όνομα όπως γράφτηκαν· η βασική μονάδα υπολογίζεται από τον
/// κατάλογο. Νέα πεδία μόνο προστίθενται (παλιές εκδόσεις διαβάζουν τα δικά τους).
///
/// Τελικός έλεγχος (Συμβούλιο 1, Σ3):
/// - [LabResult.specimen]: το είδος δείγματος. Ο κατάλογος έχει μόνο εξετάσεις αίματος· ένα αποτέλεσμα ούρων με το ίδιο
///   όνομα («Γλυκόζη», «Κρεατινίνη») ΔΕΝ είναι η εξέταση του καταλόγου: μένει «άλλη εξέταση» και δεν συγκρίνεται.
/// - Τιμή «< 0,5» ή «> 1000» ([LabResult.below], [LabResult.above]) δεν είναι αριθμός για αφαίρεση: καμία διαφορά.
library;

import 'catalog.dart';

class LabResult {
  const LabResult({
    required this.day,
    required this.rawName,
    required this.value,
    required this.unit,
    this.testId,
    this.lab,
    this.refLo,
    this.refHi,
    this.refText,
    this.method,
    this.below = false,
    this.above = false,
    this.specimen,
  });

  /// Μέρα αιμοληψίας («2026-11-10»).
  final String day;

  /// Το όνομα όπως το γράφει το εργαστήριο.
  final String rawName;
  final double value;

  /// Η μονάδα όπως τη γράφει το εργαστήριο.
  final String unit;

  /// Η εξέταση του καταλόγου (null: «άλλη εξέταση», δεν χάνεται).
  final String? testId;

  /// Το εργαστήριο (όπως το έγραψες ή όπως φαίνεται στο PDF).
  final String? lab;

  /// Τα όρια του εργαστηρίου, στη μονάδα του εργαστηρίου.
  final double? refLo, refHi;

  /// Τα όρια όπως είναι γραμμένα, όταν δεν είναι απλό «από–ως» (π.χ. «< 200 επιθυμητό»).
  final String? refText;

  /// «calc» ή «direct» (LDL)· null άγνωστο.
  final String? method;

  /// Η τιμή γράφτηκε ως «< 0,5» ή «> 1000» (κάτω/πάνω από ό,τι μετρά το μηχάνημα).
  final bool below, above;

  /// Το είδος δείγματος όπως το γράφει το εργαστήριο («Ορός», «Ούρα»…)· null: δεν γράφτηκε (παλιές καταχωρίσεις).
  final String? specimen;

  /// Η τιμή δεν είναι ακριβής αριθμός («< 0,5», «> 1000»).
  bool get censored => below || above;

  /// Το δείγμα δεν είναι αίμα (ούρα ή άλλο): δεν είναι η εξέταση αίματος του καταλόγου, ό,τι όνομα κι αν έχει.
  bool get notBlood {
    final k = specimenKind(specimen);
    return k != null && k != 'blood';
  }

  /// Η εξέταση του καταλόγου. null: άγνωστη, ή δείγμα που δεν είναι αίμα ([notBlood]).
  LabTest? get test => testId == null || notBlood ? null : labById[testId];

  /// Στη βασική μονάδα (null: άγνωστη εξέταση ή μονάδα· τότε καμία σύγκριση).
  double? get base {
    final t = test;
    return t == null ? null : toBase(t, value, unit);
  }

  double? get baseLo {
    final t = test;
    return t == null || refLo == null ? null : toBase(t, refLo!, unit);
  }

  double? get baseHi {
    final t = test;
    return t == null || refHi == null ? null : toBase(t, refHi!, unit);
  }

  /// Έξω από τα όρια του ΙΔΙΟΥ εργαστηρίου (−1 κάτω, 1 πάνω, 0 μέσα, χωρίς όρια ή δεν ξέρουμε).
  /// Τιμή «< 3,0» (η αληθινή είναι μικρότερη): κάτω από το όριο όταν το κάτω όριο είναι 3,0 ή περισσότερο· ποτέ «πάνω».
  /// Τιμή «> 100» (η αληθινή είναι μεγαλύτερη): πάνω από το όριο όταν το πάνω όριο είναι 100 ή λιγότερο· ποτέ «κάτω».
  int get flag {
    final lo = refLo, hi = refHi;
    if (!above && lo != null && (below ? value <= lo : value < lo)) return -1;
    if (!below && hi != null && (above ? value >= hi : value > hi)) return 1;
    return 0;
  }

  Map<String, dynamic> toJson() => {
        'd': day,
        'n': rawName,
        'v': value,
        'u': unit,
        if (testId != null) 't': testId,
        if (lab != null) 'lab': lab,
        if (refLo != null) 'lo': refLo,
        if (refHi != null) 'hi': refHi,
        if (refText != null) 'ref': refText,
        if (method != null) 'm': method,
        if (below) 'lt': true,
        if (above) 'gt': true,
        if (specimen != null) 's': specimen,
      };

  static LabResult? fromJson(Object? j) {
    if (j is! Map) return null;
    final d = j['d'], n = j['n'], v = j['v'], u = j['u'];
    if (d is! String || n is! String || v is! num || u is! String || !isDay(d) || !v.isFinite) return null;
    double? num_(Object? x) => x is num && x.isFinite ? x.toDouble() : null;
    final t = j['t'];
    return LabResult(
      day: d,
      rawName: n,
      value: v.toDouble(),
      unit: u,
      // Άγνωστο id (π.χ. από νεότερη έκδοση): κρατιέται ως «άλλη εξέταση», όχι σβήσιμο.
      testId: t is String && labById.containsKey(t) ? t : null,
      lab: j['lab'] is String ? j['lab'] as String : null,
      refLo: num_(j['lo']),
      refHi: num_(j['hi']),
      refText: j['ref'] is String ? j['ref'] as String : null,
      method: j['m'] is String ? j['m'] as String : null,
      below: j['lt'] == true,
      above: j['gt'] == true,
      specimen: j['s'] is String && (j['s'] as String).trim().isNotEmpty ? j['s'] as String : null,
    );
  }
}

bool isDay(String s) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return false;
  final d = DateTime.tryParse(s);
  return d != null && d.toIso8601String().startsWith(s);
}

/// Σύγκριση δύο αποτελεσμάτων της ίδιας εξέτασης (παλιότερο [a], νεότερο [b]).
class LabChange {
  LabChange(this.a, this.b);
  final LabResult a, b;

  /// Συγκρίνονται ως αριθμοί: ίδια εξέταση του καταλόγου, και καμία από τις δύο τιμές «< …» ή «> …».
  bool get comparable => a.test != null && a.test == b.test && !a.censored && !b.censored;

  /// Διαφορά στη βασική μονάδα (null: δεν συγκρίνονται, π.χ. άγνωστη μονάδα, άλλη εξέταση, δείγμα ούρων, τιμή «< 0,5»).
  double? get diff {
    if (!comparable) return null;
    final x = a.base, y = b.base;
    return x == null || y == null ? null : y - x;
  }

  double? get pct {
    final x = a.base, d = diff;
    return x == null || d == null || x == 0 ? null : d / x * 100;
  }

  /// Άλλο εργαστήριο ή άλλη μέθοδος: η σύγκριση είναι λιγότερο σίγουρη (το λέει η οθόνη).
  bool get lessSure =>
      (a.lab != null && b.lab != null && a.lab!.trim().toLowerCase() != b.lab!.trim().toLowerCase()) ||
      (a.method != null && b.method != null && a.method != b.method);
}
