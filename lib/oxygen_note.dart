/// Οξυγόνο της νύχτας (ρολόι): κλιμακωτή σημείωση όταν η χαμηλότερη μέτρηση είναι πολύ χαμηλή ή χαμηλή
/// πολλές νύχτες. Χωρίς διάγνωση· μόνο προτροπή να το πεις στον γιατρό σου.
///
/// Απόφαση 4/11 (κλινικός έλεγχος C2, κείμενα όπως γράφτηκαν εκεί):
/// - Ελάχιστο < 80% την τελευταία νύχτα → «Πολύ χαμηλή μεμονωμένη τιμή…».
/// - Ελάχιστο < 88% σε τουλάχιστον 3 από τις 7 τελευταίες νύχτες → «…αξίζει να το πεις στον γιατρό σου…».
/// - Πάντα: σημάδια κινδύνου και 166/112.
/// Τα όρια 80/88% είναι συντηρητικά όρια για προτροπή να μιλήσεις με γιατρό, όχι διαγνωστικά. Σε υγιείς το
/// ελάχιστο της νύχτας είναι κατά μέσο όρο 90,4% ± 3,1% (Gries & Brooks, Chest 1996;110:1489)· το ελάχιστο του
/// Galaxy Watch4 συμφώνησε με την πολυυπνογραφία (ICC 0,909, J Rhinol 2022), οπότε δεν είναι κάθε χαμηλή τιμή
/// λάθος· η επανάληψη έχει σημασία (Oldenburg et al., Eur Heart J 2016;37:1695).
/// Οι συγκρίσεις γίνονται στην τιμή όπως ήρθε, πριν από στρογγυλοποίηση (87,6 μετρά ως κάτω από 88).
library;

/// Κάτω από αυτό, μία νύχτα: πολύ χαμηλή μεμονωμένη τιμή.
const oxygenVeryLow = 80.0;

/// Κάτω από αυτό, σε τουλάχιστον [oxygenRepeatNights] από τις [oxygenWindowNights] τελευταίες νύχτες.
const oxygenLow = 88.0;
const oxygenRepeatNights = 3;
const oxygenWindowNights = 7;

const oxygenVeryLowText = 'Πολύ χαμηλή μεμονωμένη τιμή. Συνήθως είναι λάθος του αισθητήρα (κίνηση, πίεση στον καρπό), '
    'αλλά δες αν επαναλαμβάνεται τις επόμενες νύχτες.';

String oxygenRepeatText(int n) => 'Το οξυγόνο έπεσε κάτω από 88% σε $n από τις 7 τελευταίες νύχτες. Δεν είναι διάγνωση, '
    'αξίζει όμως να το πεις στον γιατρό σου, ειδικά αν ροχαλίζεις ή νυστάζεις τη μέρα. Η αναφορά «Για γιατρό» έχει '
    'όλες τις νύχτες.';

const oxygenRedFlagText = 'Αν έχεις δύσπνοια, πόνο στο στήθος ή μπλε χείλη, μην περιμένεις: 166 ή 112.';

/// Κλινικός έλεγχος C1 (4/11): το τεστ άπνοιας του ρολογιού είναι μόνο διαλογή· αρνητικό δεν αποκλείει άπνοια.
const oxygenAboutText = 'Δεν είναι διάγνωση. Το ρολόι δεν είναι ιατρικό οξύμετρο, και μεμονωμένες χαμηλές τιμές είναι '
    'συχνά λάθος μέτρησης (κίνηση, χαλαρό λουρί). Το κάπνισμα κάνει τις τιμές να φαίνονται ψηλότερες. Το τεστ άπνοιας '
    'του ρολογιού ψάχνει μόνο μέτρια ή σοβαρή άπνοια, και αρνητικό αποτέλεσμα δεν την αποκλείει. Αν ροχαλίζεις δυνατά, '
    'σου έχουν πει ότι σταματάς να αναπνέεις, ξυπνάς με πονοκέφαλο ή νυστάζεις τη μέρα, ζήτα από τον γιατρό σου μελέτη ύπνου.';

class OxygenGuidance {
  const OxygenGuidance({required this.veryLowLastNight, required this.lowNights});

  /// Η τελευταία νύχτα είχε χαμηλότερη μέτρηση κάτω από 80%.
  final bool veryLowLastNight;

  /// Σε πόσες από τις 7 τελευταίες νύχτες η χαμηλότερη μέτρηση ήταν κάτω από 88%.
  final int lowNights;

  bool get repeated => lowNights >= oxygenRepeatNights;

  /// Αν υπάρχει κάτι να πούμε πέρα από το σταθερό κείμενο.
  bool get any => veryLowLastNight || repeated;

  /// Τα μηνύματα, το σημαντικότερο πρώτο (χωρίς το σταθερό των σημαδιών κινδύνου).
  List<String> get messages => [
        if (repeated) oxygenRepeatText(lowNights),
        if (veryLowLastNight) oxygenVeryLowText,
      ];

  /// Σύντομη γραμμή για τη μικρή κάρτα της Σήμερα (η πλήρης σημείωση είναι στην Καρδιά και στον Ύπνο).
  String? get short => repeated
      ? 'Κάτω από 88% σε $lowNights από 7 νύχτες · δες την Καρδιά'
      : veryLowLastNight
          ? 'Πολύ χαμηλή μεμονωμένη τιμή · δες την Καρδιά'
          : null;
}

/// [minByNight]: η χαμηλότερη μέτρηση κάθε νύχτας (ημερομηνία του πρωινού), όποιες νύχτες υπάρχουν.
/// [lastNight]: η νύχτα που δείχνει η οθόνη ως «τελευταία». Μετρούν οι νύχτες [lastNight − 6, lastNight].
OxygenGuidance oxygenGuidance(Map<DateTime, double> minByNight, DateTime lastNight) {
  final last = DateTime(lastNight.year, lastNight.month, lastNight.day);
  final from = DateTime(last.year, last.month, last.day - (oxygenWindowNights - 1));
  var low = 0;
  double? lastValue;
  for (final e in minByNight.entries) {
    final d = DateTime(e.key.year, e.key.month, e.key.day);
    if (d.isBefore(from) || d.isAfter(last) || !e.value.isFinite) continue;
    if (e.value < oxygenLow) low++;
    if (d == last) lastValue = e.value;
  }
  return OxygenGuidance(veryLowLastNight: lastValue != null && lastValue < oxygenVeryLow, lowNights: low);
}

/// Κλινικός έλεγχος M6 (4/11): σταθερή γραμμή στο τέλος της Καρδιάς.
const heartRhythmNote = 'Η εφαρμογή δεν ελέγχει τον ρυθμό της καρδιάς σου. Για ακανόνιστο ρυθμό ισχύουν μόνο το ECG και οι '
    'ειδοποιήσεις του Samsung Health Monitor, και χωρίς ειδοποίηση δεν αποκλείεται κολπική μαρμαρυγή. Αν έχεις πόνο '
    'στο στήθος, δύσπνοια, λιποθυμία ή έντονο φτερούγισμα, μην περιμένεις: 166 ή 112.';

/// Η χαμηλότερη μέτρηση, ποτέ στρογγυλεμένη προς τα πάνω: 89,6 → «89,6», 89,96 → «89,9», 88 → «88».
/// (Ποτέ «90%» για τιμή κάτω από 90· έλεγχος υπολογισμών F16.)
String lowestText(double v) {
  final f = (v * 10 + 1e-9).floorToDouble() / 10;
  if (f == f.roundToDouble()) return f.toStringAsFixed(0);
  return f.toStringAsFixed(1).replaceAll('.', ',');
}
