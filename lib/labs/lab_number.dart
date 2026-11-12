/// Ένας αριθμός όπως τον γράφει ένα εργαστήριο, σε αριθμό για την εφαρμογή (τελικός έλεγχος, Συμβούλιο 3, Λ5).
///
/// Το πρόβλημα: «4.500» είναι 4,5 σε έγγραφο με τελεία για υποδιαστολή (έτσι γράφει η Βιοϊατρική: «4.00 - 10.50») και
/// 4.500 σε έγγραφο με ελληνική γραφή (τελεία στις χιλιάδες, κόμμα στα δεκαδικά). Λάθος ανάγνωση = τιμή 1.000 φορές
/// μεγαλύτερη ή μικρότερη. Γι' αυτό:
/// - Η υποδιαστολή κρίνεται από ΟΛΟ το έγγραφο ([decimalMarkOf]), όχι από έναν αριθμό.
/// - Όταν ένας αριθμός διαβάζεται με δύο τρόπους και το έγγραφο δεν ξεκαθαρίζει ποιος ισχύει, η απάντηση είναι null:
///   η εφαρμογή ρωτά, δεν μαντεύει.
/// - Το κελί της τιμής πρέπει να έχει ΕΝΑΝ αριθμό (με «<» ή «>» μπροστά, αν υπάρχει). Δύο αριθμοί («4.5 5.1»: σημερινή
///   και προηγούμενη τιμή) ή εύρος («4.00 - 10.50»: όρια αναφοράς) δεν είναι τιμή: null.
///
/// Μόνο συναρτήσεις, χωρίς οθόνη και χωρίς κλήση από αλλού ακόμα: η ανάγνωση PDF δεν έχει φτιαχτεί (απόφαση 12/11: οι
/// Εξετάσεις στο τέλος). Είναι το θεμέλιο που θα χρησιμοποιήσει, με τους κανόνες του ήδη δοκιμασμένους.
library;

/// Η υποδιαστολή ενός εγγράφου.
enum DecimalMark { comma, dot }

/// Ένας αριθμός εργαστηρίου: η τιμή, και αν γράφτηκε με «<» / «≤» ([below]) ή «>» / «≥» ([above]) μπροστά.
class LabNumber {
  const LabNumber(this.value, {this.below = false, this.above = false});
  final double value;
  final bool below, above;
}

/// Προαιρετικό σύμβολο σύγκρισης και ΕΝΑΣ αριθμός: ψηφία, με τελείες ή κόμματα ανάμεσα. Τίποτα άλλο.
final _valueShape = RegExp(r'^(<=|>=|=<|=>|≤|≥|<|>)?\s*(\d+(?:[.,]\d+)*)$');

int _count(String s, String ch) => ch.allMatches(s).length;

/// Ομάδες χιλιάδων με το [sep]: 1–3 ψηφία (όχι «0» μπροστά), και μετά ομάδες των 3: «1.234», «12.345.678».
bool _grouped(String digits, String sep) {
  final groups = digits.split(sep);
  if (groups.length < 2) return false;
  final head = groups.first;
  if (head.isEmpty || head.length > 3 || head.startsWith('0')) return false;
  return groups.skip(1).every((g) => g.length == 3);
}

/// Τι δείχνει ΕΝΑΣ αριθμός για την υποδιαστολή του εγγράφου του. null: τίποτα (ακέραιος, ή διφορούμενος όπως «4.500»).
DecimalMark? _evidence(String digits) {
  final commas = _count(digits, ','), dots = _count(digits, '.');
  if (commas == 0 && dots == 0) return null;
  if (commas > 0 && dots > 0) {
    // «1.234,5»: υποδιαστολή το τελευταίο σημείο, αν το άλλο χωρίζει σωστά χιλιάδες.
    final commaLast = digits.lastIndexOf(',') > digits.lastIndexOf('.');
    final decimal = commaLast ? ',' : '.', thousands = commaLast ? '.' : ',';
    if (_count(digits, decimal) != 1) return null;
    final whole = digits.substring(0, digits.lastIndexOf(decimal));
    if (!_grouped(whole, thousands)) return null;
    return commaLast ? DecimalMark.comma : DecimalMark.dot;
  }
  final sep = commas > 0 ? ',' : '.';
  final self = commas > 0 ? DecimalMark.comma : DecimalMark.dot;
  final other = commas > 0 ? DecimalMark.dot : DecimalMark.comma;
  if (commas + dots > 1) {
    // «1.234.567»: το σημείο χωρίζει χιλιάδες, άρα υποδιαστολή του εγγράφου είναι το άλλο.
    return _grouped(digits, sep) ? other : null;
  }
  final i = digits.indexOf(sep);
  final head = digits.substring(0, i), tail = digits.substring(i + 1);
  // «4,5», «13.25», «0.0125», «0.125», «1234.567»: δεν γίνεται να είναι χιλιάδες.
  if (tail.length != 3 || head.length > 3 || head.startsWith('0')) return self;
  return null;
}

/// Τα ψηφία ενός κελιού (χωρίς «<», «>» και κενά), ή null αν το κελί δεν είναι ένας αριθμός.
String? _digitsOf(String raw) => _valueShape.firstMatch(raw.replaceAll('\u{A0}', ' ').trim())?.group(2);

/// Η υποδιαστολή ενός εγγράφου, από όλους τους αριθμούς του (τιμές και όρια αναφοράς, ό,τι διαβάστηκε). null: κανένας
/// αριθμός δεν τη δείχνει, ή κάποιοι δείχνουν κόμμα και άλλοι τελεία. Τότε οι διφορούμενοι αριθμοί δεν διαβάζονται.
DecimalMark? decimalMarkOf(Iterable<String> numbers) {
  var comma = false, dot = false;
  for (final raw in numbers) {
    final digits = _digitsOf(raw);
    if (digits == null) continue;
    final e = _evidence(digits);
    if (e == DecimalMark.comma) comma = true;
    if (e == DecimalMark.dot) dot = true;
  }
  if (comma == dot) return null;
  return comma ? DecimalMark.comma : DecimalMark.dot;
}

/// Η τιμή ενός κελιού. [mark]: η υποδιαστολή του εγγράφου ([decimalMarkOf])· null = άγνωστη.
///
/// - «13.2», «0,63», «105»: ο αριθμός.
/// - «< 0,5», «>1000», «≤ 5.7»: ο αριθμός, με [LabNumber.below] ή [LabNumber.above].
/// - «1.234,5» (ή «1,234.5»): χιλιάδες και δεκαδικά· διαβάζεται από το ίδιο το σχήμα του.
/// - «4.500», «12,345» (ένα σημείο και ακριβώς τρία ψηφία μετά): με [mark] το ίδιο σημείο = δεκαδικά (4,5)· με [mark] το
///   άλλο = χιλιάδες (4.500)· χωρίς [mark] null.
/// - Αριθμός που αντιφάσκει με το [mark] («4.5» σε έγγραφο με κόμμα), δύο αριθμοί, εύρος, γράμματα, κενό: null.
LabNumber? parseLabNumber(String raw, {DecimalMark? mark}) {
  final m = _valueShape.firstMatch(raw.replaceAll('\u{A0}', ' ').trim());
  if (m == null) return null;
  final cmp = m.group(1) ?? '';
  final v = _numberOf(m.group(2)!, mark);
  if (v == null || !v.isFinite) return null;
  return LabNumber(v, below: cmp.contains('<') || cmp == '≤', above: cmp.contains('>') || cmp == '≥');
}

double? _numberOf(String digits, DecimalMark? mark) {
  final commas = _count(digits, ','), dots = _count(digits, '.');
  if (commas == 0 && dots == 0) return double.tryParse(digits);
  if (commas > 0 && dots > 0) {
    final e = _evidence(digits);
    if (e == null || (mark != null && mark != e)) return null;
    final decimal = e == DecimalMark.comma ? ',' : '.', thousands = e == DecimalMark.comma ? '.' : ',';
    final cut = digits.lastIndexOf(decimal);
    return double.tryParse('${digits.substring(0, cut).replaceAll(thousands, '')}.${digits.substring(cut + 1)}');
  }
  final sep = commas > 0 ? ',' : '.';
  final self = commas > 0 ? DecimalMark.comma : DecimalMark.dot;
  if (commas + dots > 1) {
    // Μόνο χιλιάδες («1.234.567»). Αν το έγγραφο έχει αυτό το σημείο για υποδιαστολή, ο αριθμός δεν στέκει.
    if (!_grouped(digits, sep) || mark == self) return null;
    return double.tryParse(digits.replaceAll(sep, ''));
  }
  final asDecimal = double.tryParse(digits.replaceAll(sep, '.'));
  if (_evidence(digits) == self) {
    // Σίγουρα δεκαδικός. Σε έγγραφο με την άλλη υποδιαστολή είναι ύποπτος: η εφαρμογή ρωτά.
    return mark == null || mark == self ? asDecimal : null;
  }
  // Διφορούμενος («4.500»): αποφασίζει μόνο το έγγραφο.
  if (mark == null) return null;
  return mark == self ? asDecimal : double.tryParse(digits.replaceAll(sep, ''));
}
