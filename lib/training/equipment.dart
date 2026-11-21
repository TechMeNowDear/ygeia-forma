/// Ο εξοπλισμός του μπαλκονιού (gymnastiriakos-exoplismos.md) και τα βάρη που βγαίνουν από αυτόν.
/// Όλα εδώ είναι καθαροί υπολογισμοί (χωρίς Flutter), για να ελέγχονται εύκολα.
library;

import 'dart:math' as math;

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

  /// Δύο λάστιχα, ένα σε κάθε χέρι (ανοίγματα): περίπου ίδια αντίσταση ανά πλευρά (ονομαστική· τα λάστιχα δεν
  /// τεντώνουν ακριβώς ίδια), με διαφορετικά χρώματα, αφού υπάρχει ένα από κάθε χρώμα. lb ανά πλευρά· ελάχιστο 30
  /// (έλεγχος #2, T2-06).
  bandPair,

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
  'band_fly': LoadKind.bandPair,
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

/// Τα βάρη των δίσκων (Φ28, X-FIT). Πόσοι από τον καθένα: [Equipment.plates].
const plateKinds = [5.0, 2.5, 1.25, 0.5];
const barKg = 10.0;
const kettlebells = [4.0, 6.0, 8.0, 10.0, 12.0, 16.0];

/// Ο εξοπλισμός που αλλάζει με τις αγορές (16/11): λαβές αλτήρα (πόσες, πόσο ζυγίζει η καθεμία με τα αστεράκια της)
/// και δίσκοι ανά βάρος. Αλλάζει από την εφαρμογή (Άσκηση › Ο εξοπλισμός μου), χωρίς νέα έκδοση. Γράφεται στο
/// training.json (κλειδί «equip»). Προεπιλογή: ό,τι υπήρχε ως τις 15/11 (2 λαβές 1,8 kg, 4 δίσκοι από κάθε βάρος).
class Equipment {
  const Equipment({this.handleKg = 1.8, this.handles = 2, this.counts = const [4, 4, 4, 4]});
  final double handleKg;
  final int handles;

  /// Πόσοι δίσκοι από κάθε βάρος, με τη σειρά του [plateKinds] (5, 2,5, 1,25, 0,5 kg).
  final List<int> counts;

  static const standard = Equipment();
  static const maxHandles = 20;
  static const maxPlates = 40;

  int count(double plate) {
    final i = plateKinds.indexOf(plate);
    return i < 0 || i >= counts.length ? 0 : counts[i];
  }

  bool get isStandard => toJson().toString() == standard.toJson().toString();

  Equipment copyWith({double? handleKg, int? handles}) =>
      Equipment(handleKg: handleKg ?? this.handleKg, handles: handles ?? this.handles, counts: counts);

  /// Ίδιος εξοπλισμός με [n] δίσκους των [plate] kg.
  Equipment withPlate(double plate, int n) => Equipment(
        handleKg: handleKg,
        handles: handles,
        counts: [for (final p in plateKinds) p == plate ? n : count(p)],
      );

  Map<String, Object> toJson() => {
        'handleKg': handleKg,
        'handles': handles,
        'plates': {for (final p in plateKinds) p.toString(): count(p)},
      };

  /// Με ανοχή: ό,τι λείπει ή δεν είναι λογικό παίρνει την προεπιλογή του.
  static Equipment fromJson(Object? j) {
    if (j is! Map) return standard;
    final h = j['handleKg'];
    final n = j['handles'];
    final pl = j['plates'];
    return Equipment(
      handleKg: h is num && h >= 0.5 && h <= 5 ? (h * 100).round() / 100 : standard.handleKg,
      handles: n is int && n >= 1 && n <= maxHandles ? n : standard.handles,
      counts: [
        for (final p in plateKinds)
          switch (pl is Map ? pl[p.toString()] : null) {
            final int c when c >= 0 && c <= maxPlates => c,
            _ => standard.count(p),
          },
      ],
    );
  }
}

/// Ο εξοπλισμός τώρα (το φορτώνει το TrainingStore από το αρχείο).
Equipment equip = Equipment.standard;

double get handleKg => equip.handleKg;

/// Λάστιχα: χρώμα → lb.
const bands = <String, int>{'yellow': 10, 'blue': 20, 'green': 30, 'black': 40, 'red': 50};
const bandNames = <String, String>{'yellow': 'κίτρινο', 'blue': 'μπλε', 'green': 'πράσινο', 'black': 'μαύρο', 'red': 'κόκκινο'};

bool usesKg(LoadKind k) => k != LoadKind.band && k != LoadKind.bandPair && k != LoadKind.bandAssist && k != LoadKind.bodyweight;
bool hasLoad(LoadKind k) => k != LoadKind.bodyweight;

double _r(double v) => (v * 100).round() / 100;

/// Όλα τα αθροίσματα δίσκων ανά πλευρά, με έως [limit] (p) από κάθε βάρος p.
List<double> _sideSums(int Function(double p) limit) {
  final out = <double>{0};
  for (final p in plateKinds) {
    final next = <double>{};
    for (final s in out) {
      for (var n = 1; n <= limit(p); n++) {
        next.add(_r(s + p * n));
      }
    }
    out.addAll(next);
  }
  return out.toList()..sort();
}

/// Πόσοι δίσκοι από κάθε βάρος χωρούν σε μία θέση: μπάρα 2 πλευρές, ζευγάρι αλτήρων 4 άκρες, ένας αλτήρας 2 άκρες,
/// κέρατο 1.
int _perSide(double p, int places) => equip.count(p) ~/ places;

/// Τα βάρη που βγαίνουν για κάθε είδος (kg, ή lb για λάστιχα), σε αύξουσα σειρά.
List<double> available(LoadKind k) {
  switch (k) {
    case LoadKind.bar:
      // Οι δίσκοι μοιράζονται στις 2 πλευρές (με 4 από κάθε βάρος: έως 2 ανά πλευρά).
      return {for (final s in _sideSums((p) => _perSide(p, 2))) _r(barKg + 2 * s)}.toList()..sort();
    case LoadKind.dbPair:
      // Δύο αλτήρες × δύο άκρες = 4 θέσεις (με 4 από κάθε βάρος: έως 1 ανά άκρη).
      return {for (final s in _sideSums((p) => _perSide(p, 4))) _r(handleKg + 2 * s)}.toList()..sort();
    case LoadKind.db:
      // Ένας αλτήρας: έως 2 από κάθε δίσκο ανά άκρη. Πόσοι χωράνε δεν έχει ελεγχθεί· όριο 25 kg ως τότε.
      return {for (final s in _sideSums((p) => _perSide(p, 2))) _r(handleKg + 2 * s)}.where((v) => v <= 25).toList()..sort();
    case LoadKind.kb:
      return kettlebells;
    case LoadKind.horn:
      return _sideSums((p) => _perSide(p, 1));
    case LoadKind.plate:
      // Ένας δίσκος ή δύο μαζί στο στήθος.
      final have = [for (final p in plateKinds) if (equip.count(p) > 0) p];
      final s = <double>{0, ...have};
      for (final a in have) {
        for (final b in have) {
          if (a != b || equip.count(a) >= 2) s.add(_r(a + b));
        }
      }
      return s.toList()..sort();
    case LoadKind.band:
    case LoadKind.bandAssist:
      return [for (final v in bandCombos().keys) v.toDouble()];
    case LoadKind.bandPair:
      return [for (final v in bandPairs().keys) v.toDouble()];
    case LoadKind.bodyweight:
      return const [0];
  }
}

/// Δύο χέρια με ίδια αντίσταση από ΔΙΑΦΟΡΕΤΙΚΑ λάστιχα: lb ανά πλευρά → (αριστερά, δεξιά), με τα λιγότερα λάστιχα.
/// Με κίτρινο 10, μπλε 20, πράσινο 30, μαύρο 40, κόκκινο 50 βγαίνουν 30–70 lb ανά πλευρά.
Map<int, (List<String>, List<String>)> bandPairs() {
  final names = bands.keys.toList();
  final out = <int, (List<String>, List<String>)>{};
  final n = names.length;
  for (var a = 1; a < (1 << n); a++) {
    for (var b = 1; b < (1 << n); b++) {
      if (a & b != 0) continue;
      List<String> pick(int m) => [for (var i = 0; i < n; i++) if (m & (1 << i) != 0) names[i]]..sort((x, y) => bands[y]!.compareTo(bands[x]!));
      final l = pick(a), r = pick(b);
      final la = l.fold(0, (s, x) => s + bands[x]!), lb = r.fold(0, (s, x) => s + bands[x]!);
      if (la != lb) continue;
      final cur = out[la];
      if (cur == null || l.length + r.length < cur.$1.length + cur.$2.length) out[la] = (l, r);
    }
  }
  return Map.fromEntries(out.entries.toList()..sort((x, y) => x.key.compareTo(y.key)));
}

/// Σύντομη ετικέτα («30 lb/πλευρά»): χωράει στο κουμπί και στο στρογγυλό ρολόι. Τα χρώματα: [setupText].
String bandPairText(double lb) => '${lb.round()} lb/πλευρά';

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
///
/// Έλεγχος 20/11 (K4C-05): στο λάστιχο βοήθειας «μικρότερο» σημαίνει πιο ΔΥΣΚΟΛΟ. Εκεί το ασφαλές είναι η ίση ή η αμέσως
/// ΠΕΡΙΣΣΟΤΕΡΗ βοήθεια (45 → 50, πριν 40), και το 0 («χωρίς λάστιχο») είναι κανονική τιμή (πριν γινόταν «κίτρινο, 10 lb»).
double snap(LoadKind k, double v) {
  final a = available(k);
  if (k == LoadKind.bandAssist) {
    if (v <= 1e-6) return 0;
    for (final x in a) {
      if (x >= v - 1e-6) return x;
    }
    return a.last;
  }
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

/// Έλεγχος 20/11 (K4C-02): «πιο ελαφριά» μετά από ενόχληση, ή όταν δεν βγήκαν οι επαναλήψεις ως την εξάντληση. Πριν ήταν
/// πάντα «το αμέσως μικρότερο που βγαίνει» ([stepDown]): με 4 δίσκους από κάθε βάρος η μπάρα έχει φορτία ανά 0,5 kg και
/// το κέρατο ανά 0,25 kg, άρα 30 → 29,5 kg (−1,7%) και 10 → 9,75 kg, ενώ στους αλτήρες το ίδιο «σκαλί» είναι −10% ως −16%.
/// Τώρα, στα κιλά: αν το ένα σκαλί είναι κάτω από −5% ([lighterMinDrop]), το μεγαλύτερο διαθέσιμο ως το [lighterRatio] του
/// βάρους (30 → 27 kg, 10 → 9 kg)· ποτέ κάτω από το [lighterFloor] (αραιά βάρη: τότε μένει το ένα σκαλί). Στην πράξη −10%
/// ως −15%· με τον τύπο του Epley, για να γίνουν οι 5 επαναλήψεις ως την εξάντληση 8 με ρεζέρβα 2 θέλει −12,5% (K4-R-12).
/// Όπου το ένα σκαλί είναι ήδη −5% ή περισσότερο (σχεδόν όλα τα ζευγάρια αλτήρων με τον αρχικό εξοπλισμό, kettlebell) και
/// στα λάστιχα: ίδιο αποτέλεσμα με πριν. Αλλάζουν, πάντα προς περισσότερη μείωση: μπάρα, κέρατο, δίσκος, ο μονός αλτήρας
/// σε 10 από τα 28 φορτία του (π.χ. 16,8 → 14,3 kg, πριν 16,3) και το ζευγάρι στα 20,3 kg (→ 17,8, πριν 19,3).
/// null = δεν υπάρχει ελαφρύτερο.
const lighterRatio = 0.9;
const lighterMinDrop = 0.05;
const lighterFloor = 0.8;

double? lighterStep(LoadKind k, double v, {bool allowZero = false}) {
  final one = stepDown(k, v, allowZero: allowZero);
  if (one == null || !usesKg(k) || v <= 0) return one;
  if (one <= v * (1 - lighterMinDrop) + 1e-6) return one;
  final s = snap(k, v * lighterRatio);
  return s < one - 1e-6 && s >= v * lighterFloor - 1e-6 ? s : one;
}

/// Περίπου [ratio] του βάρους (π.χ. 0,9 μετά από διάλειμμα), στο πλησιέστερο διαθέσιμο από κάτω.
/// Τα είδη που εξαρτώνται από τον εξοπλισμό μου (λαβές, δίσκοι): εδώ ένα φορτίο από παλιότερη καταγραφή μπορεί να μη
/// «βγαίνει» πια (π.χ. 11,8 kg με λαβή 1,8 kg, όταν η λαβή γίνει 2,2 kg).
bool onEquipment(LoadKind k) =>
    k == LoadKind.bar || k == LoadKind.dbPair || k == LoadKind.db || k == LoadKind.horn || k == LoadKind.plate;

/// Το φορτίο που βγαίνει με τον εξοπλισμό τώρα: το ίδιο αν βγαίνει, αλλιώς το αμέσως ελαφρύτερο (16/11, έλεγχος:
/// μετά από αλλαγή λαβής ή δίσκων). Ποτέ βαρύτερο από αυτό που καταγράφηκε.
double fitLoad(LoadKind k, double v) => onEquipment(k) ? snap(k, v) : v;

double scaled(LoadKind k, double v, double ratio) {
  if (k == LoadKind.bandAssist) {
    // Περισσότερη βοήθεια: το επόμενο βαρύτερο λάστιχο.
    return stepDown(k, v) ?? v;
  }
  if (!usesKg(k) && k != LoadKind.band && k != LoadKind.bandPair) return v;
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
    case LoadKind.bandPair:
      return bandPairText(v ?? 0);
    case LoadKind.bandAssist:
      return (v ?? 0) <= 0 ? 'χωρίς βοήθεια' : 'βοήθεια: ${bandText(v!)}';
    case LoadKind.plate:
      return (v ?? 0) <= 0 ? 'χωρίς δίσκο' : _plateText(v!);
    default:
      return '${kgText(v ?? 0)} kg';
  }
}

/// Δίσκος που κρατάς: «δίσκος 2,5 kg», ή «δίσκοι 1,25 + 0,5 kg» όταν το βάρος βγαίνει από δύο (R8-A6-4: πριν «δίσκος
/// 1,75 kg», ένας δίσκος που δεν υπάρχει).
String _plateText(double w) {
  final p = platesPerSide(LoadKind.plate, w);
  return p == null || p.length < 2 ? 'δίσκος ${kgText(w)} kg' : 'δίσκοι ${p.map(kgText).join(' + ')} kg';
}

/// Δίσκοι ανά πλευρά/άκρη για ένα βάρος (μεγαλύτεροι πρώτα). null αν δεν βγαίνει.
List<double>? platesPerSide(LoadKind k, double v) {
  final int places;
  final double base;
  switch (k) {
    case LoadKind.bar:
      places = 2;
      base = barKg;
    case LoadKind.dbPair:
      places = 4;
      base = handleKg;
    case LoadKind.db:
      places = 2;
      base = handleKg;
    case LoadKind.horn:
      return _platesFor(v, (p) => _perSide(p, 1), 99);
    case LoadKind.plate:
      // R8-A6-4: στο στήθος έως δύο δίσκοι, και δύο ίδιοι αν υπάρχουν δύο ([available]): 1 kg = 0,5 + 0,5.
      return _platesFor(v, (p) => math.min(2, equip.count(p)), 2);
    default:
      return null;
  }
  final side = _r((v - base) / 2);
  if (side < -1e-6) return null;
  return _platesFor(side, (p) => _perSide(p, places), 99);
}

/// Δίσκοι για μία άκρη με όριο ανά βάρος από ένα απόθεμα ([platesFromStock], για το «Ετοίμασε πριν ξεκινήσεις»).
List<double>? platesWithLimit(double target, int Function(double p) limit) => _platesFor(target, limit, 99);

List<double>? _platesFor(double target, int Function(double p) limit, int maxPieces) {
  // Από τα μεγάλα στα μικρά, με αναζήτηση (λίγοι συνδυασμοί).
  List<double>? best;
  void go(int i, double left, List<double> acc) {
    if (left.abs() < 1e-6) {
      if (best == null || acc.length < best!.length) best = List.of(acc);
      return;
    }
    if (i >= plateKinds.length || acc.length >= maxPieces) return;
    final p = plateKinds[i];
    for (var n = limit(p); n >= 0; n--) {
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
      return p.isEmpty ? 'μόνο η λαβή (${kgText(handleKg)} kg)$both' : 'λαβή + ανά άκρη ${p.map(kgText).join(' + ')}$both';
    case LoadKind.horn:
      final p = platesPerSide(k, w);
      if (w <= 0) return 'κέρατο χωρίς δίσκους';
      return p == null ? 'κέρατο ${kgText(w)} kg' : 'κέρατο: ${p.map(kgText).join(' + ')}';
    case LoadKind.kb:
      return 'kettlebell ${kgText(w)} kg';
    case LoadKind.band:
      return 'λάστιχο ${bandText(w)}';
    case LoadKind.bandPair:
      final p = bandPairs()[w.round()];
      if (p == null) return 'λάστιχα ${w.round()} lb ανά πλευρά';
      return 'αριστερό χέρι ${p.$1.map((x) => bandNames[x]).join(' + ')}, δεξί ${p.$2.map((x) => bandNames[x]).join(' + ')}';
    case LoadKind.bandAssist:
      return w <= 0 ? 'χωρίς λάστιχο βοήθειας' : 'λάστιχο βοήθειας ${bandText(w)}';
    case LoadKind.plate:
      if (w <= 0) return 'χωρίς βάρος';
      // R8-A6-4: 1,75 kg δεν είναι ένας δίσκος: «δύο δίσκοι μαζί: 1,25 + 0,5 kg» (πριν «δίσκος 1,75 kg»).
      final p = platesPerSide(k, w);
      return p == null || p.length < 2 ? 'δίσκος ${kgText(w)} kg' : 'δύο δίσκοι μαζί: ${p.map(kgText).join(' + ')} kg';
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
  // K4C-12: ο δίσκος που κρατάς στο στήθος δεν έχει «άκρες».
  final where = to == LoadKind.bar ? 'από κάθε πλευρά' : (to == LoadKind.horn || to == LoadKind.plate ? '' : 'σε κάθε άκρη');
  final parts = <String>[
    if (remove.isNotEmpty) 'βγάλε ${remove.map(kgText).join(' + ')}',
    if (add.isNotEmpty) 'βάλε ${add.map(kgText).join(' + ')}',
  ];
  return '${parts.join(', ')}${where.isEmpty ? '' : ' $where'}';
}
