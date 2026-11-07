/// Ο εξοπλισμός του μπαλκονιού (gymnastiriakos-exoplismos.md) και τα βάρη που βγαίνουν από αυτόν.
/// Όλα εδώ είναι καθαροί υπολογισμοί (χωρίς Flutter), για να ελέγχονται εύκολα.
library;

/// Πώς «ανεβαίνει» μια άσκηση.
enum LoadKind {
  /// Μπάρα 10 kg + δίσκοι ανά πλευρά.
  bar,

  /// Ζευγάρι αλτήρων (το βάρος είναι του ενός αλτήρα).
  dbPair,

  /// Ένας αλτήρας (κωπηλασία, έκταση με έναν αλτήρα, hip thrust).
  db,

  /// Kettlebell (ένα από τα 6).
  kb,

  /// Δίσκοι στο κόκκινο κέρατο της μονάδας ποδιών.
  horn,

  /// Λάστιχο: αντίσταση σε lb (συνδυασμοί λάστιχων).
  band,

  /// Λάστιχο που βοηθά (έλξεις): πρόοδος = λιγότερη βοήθεια.
  bandAssist,

  /// Δίσκος που κρατάς (π.χ. στο στήθος στο crunch). 0 = χωρίς.
  plate,

  /// Μόνο το σώμα: πρόοδος με επαναλήψεις.
  bodyweight,
}

/// Το είδος φορτίου κάθε άσκησης της βιβλιοθήκης.
const exerciseLoad = <String, LoadKind>{
  'db_press': LoadKind.dbPair,
  'incline_press': LoadKind.dbPair,
  'pushup_handles': LoadKind.bodyweight,
  'pushup_bench': LoadKind.bodyweight,
  'band_fly': LoadKind.band,
  'dips': LoadKind.bodyweight,
  'db_curl': LoadKind.dbPair,
  'incline_curl': LoadKind.dbPair,
  'hammer_curl': LoadKind.dbPair,
  'lying_ext': LoadKind.dbPair,
  'overhead_ext': LoadKind.db,
  'band_pushdown': LoadKind.band,
  'crunch': LoadKind.plate,
  'reverse_crunch': LoadKind.bodyweight,
  'ab_wheel': LoadKind.bodyweight,
  'pallof': LoadKind.band,
  'db_row': LoadKind.db,
  'band_pulldown': LoadKind.band,
  'assisted_pullup': LoadKind.bandAssist,
  'face_pull': LoadKind.band,
  'band_er': LoadKind.band,
  'shoulder_press': LoadKind.dbPair,
  'lateral_raise': LoadKind.dbPair,
  'goblet': LoadKind.kb,
  'rdl': LoadKind.bar,
  'split_squat': LoadKind.dbPair,
  'leg_curl': LoadKind.horn,
  'leg_ext': LoadKind.horn,
  'hip_thrust': LoadKind.db,
};

LoadKind loadKindOf(String exercise) => exerciseLoad[exercise] ?? LoadKind.bodyweight;

/// Δίσκοι: 4 από κάθε βάρος, κοινοί για όλα.
const plateKinds = [5.0, 2.5, 1.25, 0.5];
const platesEach = 4;
const barKg = 10.0;
const handleKg = 1.8;
const kettlebells = [4.0, 6.0, 8.0, 10.0, 12.0, 16.0];

/// Λάστιχα: χρώμα → lb.
const bands = <String, int>{'yellow': 10, 'blue': 20, 'green': 30, 'black': 40, 'red': 50};
const bandNames = <String, String>{'yellow': 'κίτρινο', 'blue': 'μπλε', 'green': 'πράσινο', 'black': 'μαύρο', 'red': 'κόκκινο'};

bool usesKg(LoadKind k) => k != LoadKind.band && k != LoadKind.bandAssist && k != LoadKind.bodyweight;
bool hasLoad(LoadKind k) => k != LoadKind.bodyweight;

double _r(double v) => (v * 100).round() / 100;

/// Όλα τα αθροίσματα δίσκων ανά πλευρά, με έως [perType] από κάθε βάρος.
List<double> _sideSums(int perType) {
  final out = <double>{0};
  for (final p in plateKinds) {
    final next = <double>{};
    for (final s in out) {
      for (var n = 1; n <= perType; n++) {
        next.add(_r(s + p * n));
      }
    }
    out.addAll(next);
  }
  return out.toList()..sort();
}

/// Τα βάρη που βγαίνουν για κάθε είδος (kg, ή lb για λάστιχα), σε αύξουσα σειρά.
List<double> available(LoadKind k) {
  switch (k) {
    case LoadKind.bar:
      // 4 από κάθε δίσκο → έως 2 ανά πλευρά.
      return {for (final s in _sideSums(platesEach ~/ 2)) _r(barKg + 2 * s)}.toList()..sort();
    case LoadKind.dbPair:
      // Δύο αλτήρες × δύο άκρες = 4 θέσεις → έως 1 από κάθε δίσκο ανά άκρη.
      return {for (final s in _sideSums(platesEach ~/ 4)) _r(handleKg + 2 * s)}.toList()..sort();
    case LoadKind.db:
      // Ένας αλτήρας: έως 2 από κάθε δίσκο ανά άκρη. Πόσοι χωράνε δεν έχει ελεγχθεί· όριο 25 kg ως τότε.
      return {for (final s in _sideSums(platesEach ~/ 2)) _r(handleKg + 2 * s)}.where((v) => v <= 25).toList()..sort();
    case LoadKind.kb:
      return kettlebells;
    case LoadKind.horn:
      return _sideSums(platesEach);
    case LoadKind.plate:
      // Ένας δίσκος ή δύο μαζί στο στήθος.
      final s = <double>{0, ...plateKinds};
      for (final a in plateKinds) {
        for (final b in plateKinds) {
          s.add(_r(a + b));
        }
      }
      return s.toList()..sort();
    case LoadKind.band:
    case LoadKind.bandAssist:
      return [for (final v in bandCombos().keys) v.toDouble()];
    case LoadKind.bodyweight:
      return const [0];
  }
}

/// Συνδυασμοί λάστιχων: lb → χρώματα (με τα λιγότερα λάστιχα).
Map<int, List<String>> bandCombos() {
  final out = <int, List<String>>{};
  final names = bands.keys.toList();
  for (var mask = 1; mask < (1 << names.length); mask++) {
    final pick = [for (var i = 0; i < names.length; i++) if (mask & (1 << i) != 0) names[i]];
    final lb = pick.fold(0, (s, n) => s + bands[n]!);
    final cur = out[lb];
    if (cur == null || pick.length < cur.length) out[lb] = pick..sort((a, b) => bands[b]!.compareTo(bands[a]!));
  }
  return Map.fromEntries(out.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
}

/// Το πλησιέστερο διαθέσιμο βάρος (ίσο ή μικρότερο), για να μη ζητηθεί κάτι που δεν βγαίνει.
double snap(LoadKind k, double v) {
  final a = available(k);
  var best = a.first;
  for (final x in a) {
    if (x <= v + 1e-6) best = x;
  }
  return best;
}

/// Ένα σκαλί πάνω. null = δεν υπάρχει βαρύτερο.
double? stepUp(LoadKind k, double v) {
  final a = available(k);
  switch (k) {
    case LoadKind.bar:
      // +1 kg (0,5 ανά πλευρά), όπως ορίζει το πρόγραμμα.
      for (final x in a) {
        if (x >= v + 1 - 1e-6) return x;
      }
      return null;
    case LoadKind.horn:
    case LoadKind.plate:
      // Τουλάχιστον +0,5 kg και περίπου +5%.
      final want = v + (v * 0.05 < 0.5 ? 0.5 : v * 0.05);
      for (final x in a) {
        if (x >= want - 1e-6) return x;
      }
      return null;
    case LoadKind.bandAssist:
      // Λιγότερη βοήθεια: ελαφρύτερο λάστιχο, και στο τέλος καθόλου.
      if (v <= 0) return null;
      double? lighter;
      for (final x in available(LoadKind.band)) {
        if (x < v - 1e-6) lighter = x;
      }
      return lighter ?? 0;
    case LoadKind.bodyweight:
      return null;
    default:
      for (final x in a) {
        if (x > v + 1e-6) return x;
      }
      return null;
  }
}

/// Ένα σκαλί κάτω. null = δεν υπάρχει ελαφρύτερο.
double? stepDown(LoadKind k, double v, {bool allowZero = false}) {
  if (k == LoadKind.bandAssist) {
    // Περισσότερη βοήθεια = βαρύτερο λάστιχο.
    for (final x in available(LoadKind.band)) {
      if (x > v + 1e-6) return x;
    }
    return null;
  }
  final a = available(k);
  double? best;
  for (final x in a) {
    if (x < v - 1e-6) best = x;
  }
  if (best == 0 && !allowZero && k != LoadKind.plate && k != LoadKind.horn) return null;
  return best;
}

/// Περίπου [ratio] του βάρους (π.χ. 0,9 μετά από διάλειμμα), στο πλησιέστερο διαθέσιμο από κάτω.
double scaled(LoadKind k, double v, double ratio) {
  if (k == LoadKind.bandAssist) {
    // Περισσότερη βοήθεια: το επόμενο βαρύτερο λάστιχο.
    return stepDown(k, v) ?? v;
  }
  if (!usesKg(k) && k != LoadKind.band) return v;
  final s = snap(k, v * ratio);
  return s >= v ? (stepDown(k, v) ?? v) : s;
}

String kgText(double v) {
  final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : (v * 10 == (v * 10).roundToDouble() ? v.toStringAsFixed(1) : v.toStringAsFixed(2));
  return s.replaceAll('.', ',');
}

/// Τα χρώματα ενός συνδυασμού λάστιχων.
String bandText(double lb) {
  if (lb <= 0) return 'χωρίς λάστιχο';
  final c = bandCombos()[lb.round()];
  if (c == null) return '${lb.round()} lb';
  return '${c.map((n) => bandNames[n]).join(' + ')} (${lb.round()} lb)';
}

/// Σύντομη ετικέτα φορτίου: «11,8 kg», «πράσινο (30 lb)», «σώμα».
String loadLabel(LoadKind k, double? v) {
  switch (k) {
    case LoadKind.bodyweight:
      return 'σώμα';
    case LoadKind.band:
      return bandText(v ?? 0);
    case LoadKind.bandAssist:
      return (v ?? 0) <= 0 ? 'χωρίς βοήθεια' : 'βοήθεια: ${bandText(v!)}';
    case LoadKind.plate:
      return (v ?? 0) <= 0 ? 'χωρίς δίσκο' : 'δίσκος ${kgText(v!)} kg';
    default:
      return '${kgText(v ?? 0)} kg';
  }
}

/// Δίσκοι ανά πλευρά/άκρη για ένα βάρος (μεγαλύτεροι πρώτα). null αν δεν βγαίνει.
List<double>? platesPerSide(LoadKind k, double v) {
  final int perType;
  final double base;
  switch (k) {
    case LoadKind.bar:
      perType = 2;
      base = barKg;
    case LoadKind.dbPair:
      perType = 1;
      base = handleKg;
    case LoadKind.db:
      perType = 2;
      base = handleKg;
    case LoadKind.horn:
    case LoadKind.plate:
      return _platesFor(v, k == LoadKind.horn ? platesEach : 1, k == LoadKind.plate ? 2 : 99);
    default:
      return null;
  }
  final side = _r((v - base) / 2);
  if (side < -1e-6) return null;
  return _platesFor(side, perType, 99);
}

List<double>? _platesFor(double target, int perType, int maxPieces) {
  // Από τα μεγάλα στα μικρά, με αναζήτηση (λίγοι συνδυασμοί).
  List<double>? best;
  void go(int i, double left, List<double> acc) {
    if (left.abs() < 1e-6) {
      if (best == null || acc.length < best!.length) best = List.of(acc);
      return;
    }
    if (i >= plateKinds.length || acc.length >= maxPieces) return;
    final p = plateKinds[i];
    for (var n = perType; n >= 0; n--) {
      if (p * n <= left + 1e-6) {
        go(i + 1, _r(left - p * n), [...acc, for (var j = 0; j < n; j++) p]);
      }
    }
  }

  go(0, _r(target), []);
  return best;
}

/// Στήσιμο σε απλά λόγια: «μπάρα 10 + ανά πλευρά 5 + 0,5».
String setupText(LoadKind k, double? v) {
  final w = v ?? 0;
  switch (k) {
    case LoadKind.bar:
      final p = platesPerSide(k, w);
      if (p == null) return 'μπάρα ${kgText(w)} kg';
      return p.isEmpty ? 'μόνο η μπάρα (10 kg)' : 'μπάρα 10 + ανά πλευρά ${p.map(kgText).join(' + ')}';
    case LoadKind.dbPair:
    case LoadKind.db:
      final p = platesPerSide(k, w);
      final both = k == LoadKind.dbPair ? ', και στους δύο αλτήρες' : '';
      if (p == null) return 'αλτήρας ${kgText(w)} kg$both';
      return p.isEmpty ? 'μόνο η λαβή (1,8 kg)$both' : 'λαβή + ανά άκρη ${p.map(kgText).join(' + ')}$both';
    case LoadKind.horn:
      final p = platesPerSide(k, w);
      if (w <= 0) return 'κέρατο χωρίς δίσκους';
      return p == null ? 'κέρατο ${kgText(w)} kg' : 'κέρατο: ${p.map(kgText).join(' + ')}';
    case LoadKind.kb:
      return 'kettlebell ${kgText(w)} kg';
    case LoadKind.band:
      return 'λάστιχο ${bandText(w)}';
    case LoadKind.bandAssist:
      return w <= 0 ? 'χωρίς λάστιχο βοήθειας' : 'λάστιχο βοήθειας ${bandText(w)}';
    case LoadKind.plate:
      return w <= 0 ? 'χωρίς βάρος' : 'δίσκος ${kgText(w)} kg';
    case LoadKind.bodyweight:
      return 'με το βάρος του σώματος';
  }
}

/// Τι αλλάζει στους δίσκους από την προηγούμενη άσκηση (ίδιο όργανο), ή null.
String? plateChange(LoadKind from, double? fromKg, LoadKind to, double? toKg) {
  final sameTool = (from == to) || ({from, to}.difference({LoadKind.db, LoadKind.dbPair}).isEmpty);
  if (!sameTool || fromKg == null || toKg == null) return null;
  if ((fromKg - toKg).abs() < 1e-6) return 'ίδιοι δίσκοι';
  final a = platesPerSide(from, fromKg), b = platesPerSide(to, toKg);
  if (a == null || b == null) return null;
  final add = List.of(b), remove = <double>[];
  for (final p in a) {
    if (!add.remove(p)) remove.add(p);
  }
  final where = to == LoadKind.bar ? 'από κάθε πλευρά' : (to == LoadKind.horn ? '' : 'σε κάθε άκρη');
  final parts = <String>[
    if (remove.isNotEmpty) 'βγάλε ${remove.map(kgText).join(' + ')}',
    if (add.isNotEmpty) 'βάλε ${add.map(kgText).join(' + ')}',
  ];
  return '${parts.join(', ')}${where.isEmpty ? '' : ' $where'}';
}
