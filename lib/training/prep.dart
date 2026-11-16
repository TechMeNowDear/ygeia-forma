/// «Ετοίμασε πριν ξεκινήσεις» (16/11): όλοι οι αλτήρες της μέρας στημένοι από πριν, ώστε να μη χάνεται χρόνος ανάμεσα
/// στις ασκήσεις. Καθαροί υπολογισμοί (χωρίς Flutter).
///
/// - Αλτήρες: κάθε διαφορετικό βάρος στήνεται μία φορά, όσοι χρειάζονται (ζευγάρι = 2, μονός = 1). Ασκήσεις με το ίδιο
///   βάρος μοιράζονται τους ίδιους αλτήρες.
/// - Οι δίσκοι μοιράζονται από το απόθεμα ([Equipment.plates]) με τη σειρά των ασκήσεων: πρώτα οι αλτήρες, μετά η
///   μπάρα και το κέρατο (στο βάρος της πρώτης άσκησης που τα θέλει). Ό,τι δεν χωράει λέγεται: στήνεται όταν φτάσεις εκεί.
/// - Λαβές: αν δεν φτάνουν, το ίδιο.
library;

import 'equipment.dart';

/// Μία άσκηση της μέρας: όνομα, είδος φορτίου, βάρος (kg, ή lb για λάστιχα· null για σώμα).
typedef PrepIn = ({String name, LoadKind kind, double? load});

class PrepLine {
  const PrepLine(this.what, this.how, this.forWhat, {this.later = false});

  /// «2 αλτήρες 11,8 kg», «Μπάρα 30 kg», «Kettlebell 16 kg».
  final String what;

  /// «σε κάθε άκρη 5», «ανά πλευρά 5 + 5».
  final String? how;

  /// Οι ασκήσεις που το χρειάζονται.
  final List<String> forWhat;

  /// Δεν φτάνουν οι λαβές ή οι δίσκοι για να στηθεί από πριν: στήνεται όταν φτάσεις εκεί.
  final bool later;
}

class Prep {
  const Prep(this.lines, {this.handlesNeeded = 0, this.short = false});
  final List<PrepLine> lines;
  final int handlesNeeded;

  /// Κάτι δεν στήνεται από πριν (λαβές ή δίσκοι).
  final bool short;
}

double _r(double v) => (v * 100).round() / 100;

/// Ο υπολογισμός. [e]: ο εξοπλισμός (λαβές, βάρος λαβής, δίσκοι).
Prep prepFor(List<PrepIn> items, Equipment e) {
  final stock = {for (final p in plateKinds) p: e.count(p)};
  final lines = <PrepLine>[];
  var short = false;

  // Αλτήρες: βάρος → (πόσοι, ασκήσεις), με τη σειρά που εμφανίζονται.
  final dbs = <double, (int, List<String>)>{};
  for (final i in items) {
    if ((i.kind != LoadKind.dbPair && i.kind != LoadKind.db) || i.load == null) continue;
    final need = i.kind == LoadKind.dbPair ? 2 : 1;
    final w = _r(i.load!);
    final cur = dbs[w];
    dbs[w] = (cur == null ? need : (cur.$1 > need ? cur.$1 : need), [...?cur?.$2, i.name]);
  }
  final handlesNeeded = dbs.values.fold(0, (a, b) => a + b.$1);
  var handlesLeft = e.handles;

  // Δίσκοι για μία θέση, από ό,τι έχει μείνει: [ends] θέσεις με τους ίδιους δίσκους (ένας αλτήρας = 2 άκρες).
  List<double>? take(double perEnd, int ends) {
    final p = platesWithLimit(perEnd, (k) => (stock[k] ?? 0) ~/ ends);
    if (p == null) return null;
    for (final k in p) {
      stock[k] = stock[k]! - ends;
    }
    return p;
  }

  String join(List<double> p) => p.map(kgText).join(' + ');

  for (final MapEntry(key: w, value: (n, names)) in dbs.entries) {
    final perEnd = _r((w - e.handleKg) / 2);
    var built = 0;
    List<double>? plates;
    for (var k = 0; k < n; k++) {
      if (handlesLeft == 0 || perEnd < -1e-6) break;
      final p = take(perEnd, 2);
      if (p == null) break;
      plates = p;
      handlesLeft--;
      built++;
    }
    if (built > 0) {
      lines.add(PrepLine('$built ${built == 1 ? 'αλτήρας' : 'αλτήρες'} ${kgText(w)} kg',
          plates!.isEmpty ? 'μόνο η λαβή' : 'σε κάθε άκρη ${join(plates)}', names));
    }
    if (built < n) {
      short = true;
      lines.add(PrepLine('${n - built} ${n - built == 1 ? 'αλτήρας' : 'αλτήρες'} ${kgText(w)} kg', null, names, later: true));
    }
  }

  // Μπάρα και κέρατο: στο βάρος της πρώτης άσκησης που τα θέλει.
  for (final kind in const [LoadKind.bar, LoadKind.horn]) {
    final first = items.where((i) => i.kind == kind && i.load != null).toList();
    if (first.isEmpty) continue;
    final w = first.first.load!;
    final names = [for (final i in first) i.name];
    final perSide = kind == LoadKind.bar ? _r((w - barKg) / 2) : w;
    final p = perSide < -1e-6 ? null : take(perSide, kind == LoadKind.bar ? 2 : 1);
    final what = kind == LoadKind.bar ? 'Μπάρα ${kgText(w)} kg' : 'Κέρατο ${kgText(w)} kg';
    if (p == null) {
      short = true;
      lines.add(PrepLine(what, null, names, later: true));
    } else {
      lines.add(PrepLine(
          what,
          p.isEmpty ? (kind == LoadKind.bar ? 'μόνο η μπάρα' : 'χωρίς δίσκους') : '${kind == LoadKind.bar ? 'ανά πλευρά' : 'δίσκοι'} ${join(p)}',
          names));
    }
  }

  // Ό,τι άλλο: kettlebell, λάστιχα, δίσκος στο στήθος (ένα ανά διαφορετικό στήσιμο).
  final other = <String, List<String>>{};
  for (final i in items) {
    if (!{LoadKind.kb, LoadKind.band, LoadKind.bandPair, LoadKind.bandAssist, LoadKind.plate}.contains(i.kind)) continue;
    if (i.load == null || (i.load! <= 0 && i.kind != LoadKind.bandAssist)) continue;
    final t = i.kind == LoadKind.bandPair ? 'λάστιχα: ${setupText(i.kind, i.load)}' : setupText(i.kind, i.load);
    other[t] = [...?other[t], i.name];
  }
  for (final MapEntry(key: t, value: names) in other.entries) {
    lines.add(PrepLine(t[0].toUpperCase() + t.substring(1), null, names));
  }
  return Prep(lines, handlesNeeded: handlesNeeded, short: short);
}
