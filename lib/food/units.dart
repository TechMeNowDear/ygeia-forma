/// Μονάδες «ανά τεμάχιο» (16/11): «1 μεσαία μπανάνα» αντί για γραμμάρια, όταν δεν ζυγίζεις.
///
/// Τα βάρη είναι **βρώσιμο μέρος** (χωρίς φλούδα, κουκούτσι, τσόφλι), όπως οι τιμές της βάσης ανά 100 g, από τα
/// τυπικά μεγέθη της USDA (SR Legacy, «Food Weights»). Είναι μέσοι όροι: ένα συγκεκριμένο φρούτο μπορεί να είναι
/// ±25%. Γι' αυτό μια καταχώριση με αυτά γράφεται ως **εκτίμηση** ([LogEntry.est]). Αν ζυγίσεις ένα δικό σου
/// («Ζύγισα ένα»), το βάρος σου μένει στο κινητό και οι επόμενες με αυτό δεν είναι εκτίμηση.
///
/// Αυγά: τα ελληνικά αυγά πωλούνται με τις κλάσεις της ΕΕ (Καν. 589/2008: M 53–63 g, L 63–73 g με το τσόφλι). Το
/// βρώσιμο μέρος είναι το 88% (USDA: τσόφλι 12%): M ≈ 58 × 0,88 = 51 g, L ≈ 68 × 0,88 = 60 g.
library;

class PieceSize {
  const PieceSize(this.label, this.grams);

  /// «μικρή», «μεσαία», «μεγάλη» (συμφωνεί με το [PieceUnit.one]).
  final String label;
  final double grams;
}

class PieceUnit {
  const PieceUnit(this.one, this.many, this.sizes, {this.sizeAfter = false});

  /// Το μέγεθος μετά το όνομα: «1 αυγό M» (όχι «1 M αυγό»).
  final bool sizeAfter;

  /// «μπανάνα» / «μπανάνες».
  final String one;
  final String many;
  final List<PieceSize> sizes;

  /// Το μεσαίο μέγεθος (ή το μόνο).
  PieceSize get middle => sizes[sizes.length ~/ 2];
}

const _fruitF = ['μικρή', 'μεσαία', 'μεγάλη'];
const _fruitN = ['μικρό', 'μεσαίο', 'μεγάλο'];

PieceUnit _f(String one, String many, List<double> g) => PieceUnit(one, many, [for (var i = 0; i < g.length; i++) PieceSize(_fruitF[i], g[i])]);
PieceUnit _n(String one, String many, List<double> g) => PieceUnit(one, many, [for (var i = 0; i < g.length; i++) PieceSize(_fruitN[i], g[i])]);

const _egg = PieceUnit('αυγό', 'αυγά', [PieceSize('M', 51), PieceSize('L', 60)], sizeAfter: true);

/// Τα τρόφιμα της βάσης με τεμάχια. Μόνο όσα έχουν επαληθευμένο τυπικό βάρος· τα υπόλοιπα ζυγίζονται.
final Map<String, PieceUnit> pieceUnits = {
  // Αυγά (όλοι οι τρόποι: το βάρος του αυγού δεν αλλάζει πολύ στο βράσιμο).
  'C22000': _egg,
  'C22010': _egg,
  'C22014': _egg,
  'C22011': _egg,
  // Φρούτα
  'C13005': _f('μπανάνα', 'μπανάνες', [101, 118, 136]),
  'C13039': _n('μήλο', 'μήλα', [149, 182, 223]),
  'C13037': _n('αχλάδι', 'αχλάδια', [148, 178, 230]),
  'C13043': _n('ροδάκινο', 'ροδάκινα', [130, 150, 175]),
  'C13034': _n('πορτοκάλι', 'πορτοκάλια', [96, 131, 184]),
  'C13024': _n('μανταρίνι', 'μανταρίνια', [76, 88, 120]),
  'C13021': const PieceUnit('ακτινίδιο', 'ακτινίδια', [PieceSize('μεσαίο', 69)]),
  'C13000': const PieceUnit('βερίκοκο', 'βερίκοκα', [PieceSize('μεσαίο', 35)]),
  // Λαχανικά
  'C20385': _f('ντομάτα', 'ντομάτες', [91, 123, 182]),
  'C20009': const PieceUnit('καρότο', 'καρότα', [PieceSize('μεσαίο', 61)]),
  'C20034': _n('κρεμμύδι', 'κρεμμύδια', [70, 110, 150]),
  'C11000': const PieceUnit('σκελίδα', 'σκελίδες', [PieceSize('', 3)]),
};

/// «1 μεσαία μπανάνα», «2 μεσαίες μπανάνες», «3 αυγά L», «2 ακτινίδια» (ένα μέγεθος: χωρίς επίθετο). Στον πληθυντικό
/// το επίθετο: -α → -ες, -ο → -α.
String pieceText(PieceUnit u, PieceSize s, int count) {
  final noun = count == 1 ? u.one : u.many;
  if (u.sizes.length == 1 || s.label.isEmpty) return '$count $noun';
  if (u.sizeAfter) return '$count $noun ${s.label}';
  var adj = s.label;
  if (count != 1 && adj.endsWith('α')) adj = '${adj.substring(0, adj.length - 1)}ες';
  if (count != 1 && adj.endsWith('ο')) adj = '${adj.substring(0, adj.length - 1)}α';
  return '$count $adj $noun';
}

/// Το δικό σου βάρος ανά τεμάχιο: όρια (g). Κάτω από 1 g ή πάνω από 2 κιλά δεν είναι τεμάχιο φαγητού.
const myUnitMinG = 1.0;
const myUnitMaxG = 2000.0;

double? validMyUnit(Object? v) {
  if (v is! num) return null;
  final d = v.toDouble();
  return d.isFinite && d >= myUnitMinG && d <= myUnitMaxG ? d : null;
}
