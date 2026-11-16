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
    // Όλοι οι αλτήρες ενός βάρους μαζί, με τους ίδιους δίσκους σε κάθε άκρη (16/11, έλεγχος: πριν μοιράζονταν ένας-ένας
    // και η γραμμή έδειχνε μόνο τους δίσκους του τελευταίου). Ζευγάρι μισό δεν στήνεται.
    final p = handlesLeft >= n && perEnd >= -1e-6 ? take(perEnd, 2 * n) : null;
    final what = '$n ${n == 1 ? 'αλτήρας' : 'αλτήρες'} ${kgText(w)} kg';
    if (p != null) {
      handlesLeft -= n;
      lines.add(PrepLine(what, p.isEmpty ? 'μόνο η λαβή' : 'σε κάθε άκρη ${join(p)}', names));
    } else {
      short = true;
      lines.add(PrepLine(what, null, names, later: true));
    }
  }

  // Μπάρα και κέρατο: στο βάρος της πρώτης άσκησης που τα θέλει. Αν άλλες ασκήσεις τα θέλουν με άλλο βάρος, γράφεται
  // δίπλα στο όνομά τους (16/11, έλεγχος: πριν φαινόταν σαν να είναι όλες στο ίδιο βάρος).
  for (final kind in const [LoadKind.bar, LoadKind.horn]) {
    final first = items.where((i) => i.kind == kind && i.load != null).toList();
    if (first.isEmpty) continue;
    final w = first.first.load!;
    final names = [
      for (final i in first) _r(i.load!) == _r(w) ? i.name : '${i.name} (μετά ${kgText(i.load!)} kg)',
    ];
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
  final plateLater = <String, List<String>>{};
  for (final i in items) {
    if (!{LoadKind.kb, LoadKind.band, LoadKind.bandPair, LoadKind.bandAssist, LoadKind.plate}.contains(i.kind)) continue;
    if (i.load == null || (i.load! <= 0 && i.kind != LoadKind.bandAssist)) continue;
    // Δίσκος στο χέρι/στήθος: βγαίνει κι αυτός από τους δίσκους που περίσσεψαν (16/11, έλεγχος).
    if (i.kind == LoadKind.plate) {
      final need = platesPerSide(LoadKind.plate, i.load!) ?? const <double>[];
      final count = <double, int>{};
      for (final k in need) {
        count[k] = (count[k] ?? 0) + 1;
      }
      if (count.entries.every((c) => (stock[c.key] ?? 0) >= c.value)) {
        for (final c in count.entries) {
          stock[c.key] = stock[c.key]! - c.value;
        }
      } else {
        final t = setupText(i.kind, i.load);
        plateLater[t] = [...?plateLater[t], i.name];
        continue;
      }
    }
    final t = i.kind == LoadKind.bandPair ? 'λάστιχα: ${setupText(i.kind, i.load)}' : setupText(i.kind, i.load);
    other[t] = [...?other[t], i.name];
  }
  for (final MapEntry(key: t, value: names) in other.entries) {
    lines.add(PrepLine(t[0].toUpperCase() + t.substring(1), null, names));
  }
  for (final MapEntry(key: t, value: names) in plateLater.entries) {
    short = true;
    lines.add(PrepLine(t[0].toUpperCase() + t.substring(1), null, names, later: true));
  }
  return Prep(lines, handlesNeeded: handlesNeeded, short: short);
}
