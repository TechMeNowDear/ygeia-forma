/// Οξυγόνο της νύχτας (ρολόι): κλιμακωτή σημείωση όταν η χαμηλότερη μέτρηση είναι πολύ χαμηλή ή χαμηλή
/// πολλές νύχτες. Χωρίς διάγνωση· μόνο προτροπή να το πεις στον γιατρό σου.
///
/// Απόφαση 4/11, μετά τον δεύτερο κλινικό έλεγχο (K2, K3, M1, M2· κείμενα όπως γράφτηκαν εκεί). ΕΝΑ μήνυμα, το
/// σημαντικότερο:
/// 1. Ελάχιστο < 80% σε τουλάχιστον 2 από τις 30 τελευταίες νύχτες → «…σπάνιο… πες το στον γιατρό σου».
/// 2. Ελάχιστο < 85% σε τουλάχιστον 3 από τις νύχτες με μέτρηση της τελευταίας εβδομάδας → «…αξίζει να το πεις…».
/// 3. Ελάχιστο < 80% την τελευταία νύχτα (μόνο αυτή) → ουδέτερο «από μία νύχτα δεν ξεχωρίζει· αν ξαναγίνει…».
/// Πάντα: σημάδια κινδύνου και 166/112 (στην οθόνη, όχι εδώ).
///
/// Γιατί: σε υγιείς, με οξύμετρο δαχτύλου, το ελάχιστο της νύχτας είναι 90,4% ± 3,1% (Gries & Brooks, Chest
/// 1996;110:1489). Το 80% απέχει πάνω από 3 τυπικές αποκλίσεις: μία τέτοια νύχτα μπορεί να είναι σφάλμα, δύο ή
/// περισσότερες σε έναν μήνα δύσκολα εξηγούνται έτσι. Το Galaxy Watch4 συμφώνησε καλά με την πολυυπνογραφία
/// (RMSE 2,3%) και πετάει μόνο του τα κακά σήματα (Jung et al., Sleep Health 2022;8:420)· δεν υπάρχει στοιχείο ότι
/// μια τιμή < 80% είναι «συνήθως» λάθος. Το 85% (όχι 88%): με 88% περίπου 1 στους 5 υγιείς θα έβλεπε σημείωση κάθε
/// εβδομάδα· με 85% περίπου 1 στους 500 (πρόχειρος υπολογισμός, κανονική κατανομή, ανεξάρτητες νύχτες). Η
/// επανάληψη έχει σημασία (Oldenburg et al., Eur Heart J 2016;37:1695).
/// Οι συγκρίσεις γίνονται στην τιμή όπως ήρθε, πριν από στρογγυλοποίηση (84,6 μετρά ως κάτω από 85).
/// Μετρούν ΜΟΝΟ νύχτες με μέτρηση: «3 από τις 4 νύχτες με μέτρηση», ποτέ «3 από 7» όταν οι 3 δεν είχαν τιμή.
library;

import 'format.dart';

/// Κάτω από αυτό: πολύ χαμηλή τιμή (μία νύχτα, ή επαναλαμβανόμενη στις [oxygenLongWindowNights]).
const oxygenVeryLow = 80.0;

/// Κάτω από αυτό, σε τουλάχιστον [oxygenRepeatNights] από τις νύχτες με μέτρηση των [oxygenWindowNights] τελευταίων.
const oxygenLow = 85.0;
const oxygenRepeatNights = 3;
const oxygenWindowNights = 7;

/// Πολύ χαμηλή τιμή σε τουλάχιστον [oxygenVeryLowRepeatNights] από τις [oxygenLongWindowNights] τελευταίες νύχτες.
const oxygenLongWindowNights = 30;
const oxygenVeryLowRepeatNights = 2;

/// Νέο (K2): ≥ 2 νύχτες < 80% στις 30 τελευταίες μέρες. Έλεγχος 3, E5 (κείμενο του κλινικού ελέγχου 4, C4): «σε N
/// νύχτες μέσα στις τελευταίες 30 μέρες» (μετρούν μόνο νύχτες με μέτρηση) και ΠΟΙΕΣ, με την τιμή τους, ώστε να τις
/// βρεις (η λίστα της Καρδιάς δείχνει μόνο 10). [nights]: (νύχτα, χαμηλότερη μέτρηση), με χρονολογική σειρά.
String oxygenVeryLowRepeatText(List<(DateTime, double)> nights) {
  final list = [for (final (d, v) in nights) '${d.day}/${d.month}: ${lowestText(v)}%'].join(', ');
  return 'Το οξυγόνο έπεσε κάτω από 80% σε ${nights.length} νύχτες μέσα στις τελευταίες 30 μέρες ($list). Με ιατρικό '
      'οξύμετρο, σε υγιείς ανθρώπους τέτοιες τιμές στον ύπνο είναι σπάνιες· μία τιμή του ρολογιού μπορεί να είναι '
      'λάθος, δύο σε έναν μήνα δύσκολα. Δεν είναι διάγνωση, και ένα αρνητικό τεστ άπνοιας του ρολογιού δεν το '
      'αποκλείει. Πες το στον γιατρό σου και δείξε του την αναφορά (Τάσεις › Για γιατρό).';
}

/// Μία νύχτα < 80%, χωρίς άλλο μήνυμα (K2): ουδέτερο, ούτε «συνήθως λάθος» ούτε συναγερμός.
const oxygenVeryLowText = 'Πολύ χαμηλή τιμή τη χθεσινή νύχτα. Μπορεί να είναι λάθος του αισθητήρα (κίνηση, πίεση '
    'στον καρπό), μπορεί και πραγματική πτώση· από μία νύχτα δεν ξεχωρίζει. Αν ξαναγίνει, πες το στον γιατρό σου.';

/// Το ίδιο για νύχτα που δεν είναι η χθεσινή (π.χ. το ρολόι δεν φορέθηκε από τότε): ποτέ «χθεσινή» για παλιά νύχτα.
String oxygenVeryLowTextFor(DateTime night, DateTime? today) => today == null || sameDay(night, today)
    ? oxygenVeryLowText
    : oxygenVeryLowText.replaceFirst('τη χθεσινή νύχτα', 'την τελευταία νύχτα με μέτρηση (${shortDayDate(night)})');

/// M2: «από τις N νύχτες με μέτρηση», όχι «από τις 7»· και η αναφορά δείχνει τη χαμηλότερη τιμή κάθε νύχτας (στο
/// γράφημα), όχι «όλες τις νύχτες» στη λίστα.
String oxygenRepeatText(int n, int measured) => 'Το οξυγόνο έπεσε κάτω από 85% σε $n από τις $measured νύχτες με '
    'μέτρηση της τελευταίας εβδομάδας. Δεν είναι διάγνωση, αξίζει όμως να το πεις στον γιατρό σου, ειδικά αν '
    'ροχαλίζεις, νυστάζεις τη μέρα, έχεις υψηλή πίεση ή αρρυθμία. Η αναφορά για γιατρό (Τάσεις › Για γιατρό) '
    'δείχνει τη χαμηλότερη τιμή κάθε νύχτας.';

const oxygenRedFlagText = 'Αν έχεις δύσπνοια, πόνο στο στήθος ή μπλε χείλη, μην περιμένεις: 166 ή 112.';

/// Μία γραμμή πάνω από τις τιμές· το πλήρες κείμενο ([oxygenAboutText]) ανοίγει με «Τι σημαίνει» (έλεγχος UX U9:
/// το ίδιο κείμενο σε 4 οθόνες έσπρωχνε τις τιμές κάτω από την οθόνη).
const oxygenAboutShort = 'Δεν είναι διάγνωση. Το ρολόι δεν είναι ιατρικό οξύμετρο.';

/// Κλινικός έλεγχος M3 (δεύτερος, 4/11): το τεστ άπνοιας του ρολογιού είναι μόνο διαλογή· ευαισθησία 82,7% (χάνει
/// περίπου 1 στους 6 με μέτρια–σοβαρή άπνοια) και δεν προορίζεται για κολπική μαρμαρυγή, καρδιακή ανεπάρκεια ή
/// χρόνια πνευμονοπάθεια (Samsung IFU Sleep Apnea EU v1.2, 2025· FDA DEN230041). Υψηλή πίεση και αρρυθμία είναι
/// λόγοι να ρωτήσεις για μελέτη ύπνου (AASM, Kapur et al., J Clin Sleep Med 2017;13:479).
const oxygenAboutText = 'Δεν είναι διάγνωση. Το ρολόι δεν είναι ιατρικό οξύμετρο: μεμονωμένες χαμηλές τιμές μπορεί να '
    'είναι λάθος μέτρησης (κίνηση, χαλαρό λουρί), αλλά μπορεί και όχι. Το κάπνισμα κάνει τις τιμές να φαίνονται '
    'ψηλότερες. Το τεστ άπνοιας του ρολογιού ψάχνει μόνο μέτρια ή σοβαρή άπνοια, χάνει περίπου 1 στους 6, και δεν '
    'προορίζεται για όσους έχουν κολπική μαρμαρυγή, καρδιακή ανεπάρκεια ή πάθηση των πνευμόνων· αρνητικό αποτέλεσμα '
    'δεν αποκλείει άπνοια. Ρώτα τον γιατρό σου για μελέτη ύπνου αν ροχαλίζεις δυνατά, σου έχουν πει ότι σταματάς να '
    'αναπνέεις, ξυπνάς με πονοκέφαλο, νυστάζεις τη μέρα, ή έχεις υψηλή πίεση ή αρρυθμία.';

class OxygenGuidance {
  const OxygenGuidance({
    required this.veryLowLastNight,
    required this.lowNights,
    this.measuredNights = 0,
    this.veryLowNights30 = 0,
    this.veryLowList = const [],
    this.lastNight,
    this.today,
  });

  /// Οι νύχτες των 30 τελευταίων ημερών με χαμηλότερη μέτρηση κάτω από 80%, με χρονολογική σειρά (E5).
  final List<(DateTime, double)> veryLowList;

  /// Η τελευταία νύχτα είχε χαμηλότερη μέτρηση κάτω από 80%.
  final bool veryLowLastNight;

  /// Σε πόσες από τις νύχτες με μέτρηση της τελευταίας εβδομάδας η χαμηλότερη μέτρηση ήταν κάτω από 85%.
  final int lowNights;

  /// Πόσες νύχτες της τελευταίας εβδομάδας είχαν μέτρηση (ο παρονομαστής του [lowNights]).
  final int measuredNights;

  /// Σε πόσες από τις 30 τελευταίες νύχτες η χαμηλότερη μέτρηση ήταν κάτω από 80%.
  final int veryLowNights30;

  /// Η νύχτα που η οθόνη δείχνει ως «τελευταία» και η σημερινή μέρα (για το «χθεσινή» ή την ημερομηνία).
  final DateTime? lastNight;
  final DateTime? today;

  bool get veryLowRepeated => veryLowNights30 >= oxygenVeryLowRepeatNights;
  bool get repeated => lowNights >= oxygenRepeatNights;

  /// Αν υπάρχει κάτι να πούμε πέρα από το σταθερό κείμενο.
  bool get any => veryLowRepeated || repeated || veryLowLastNight;

  /// ΕΝΑ μήνυμα, το σημαντικότερο (K3: δύο μαζί αντέφασκαν). Χωρίς το σταθερό των σημαδιών κινδύνου.
  List<String> get messages => [
        if (veryLowRepeated)
          oxygenVeryLowRepeatText(veryLowList)
        else if (repeated)
          oxygenRepeatText(lowNights, measuredNights)
        else if (veryLowLastNight)
          lastNight == null ? oxygenVeryLowText : oxygenVeryLowTextFor(lastNight!, today),
      ];

  /// Σύντομη γραμμή για τη μικρή κάρτα της Σήμερα (η πλήρης σημείωση είναι στην Καρδιά και στον Ύπνο).
  String? get short => veryLowRepeated
      ? 'Κάτω από 80% σε $veryLowNights30 νύχτες (30 μέρες) · δες την Καρδιά'
      : repeated
          ? 'Κάτω από 85% σε $lowNights από $measuredNights νύχτες · δες την Καρδιά'
          : veryLowLastNight
              ? 'Πολύ χαμηλή τιμή μία νύχτα · δες την Καρδιά'
              : null;
}

/// [minByNight]: η χαμηλότερη μέτρηση κάθε νύχτας (ημερομηνία του πρωινού), ΜΟΝΟ νύχτες με μέτρηση.
/// [lastNight]: η νύχτα που δείχνει η οθόνη ως «τελευταία». Η εβδομάδα: [lastNight − 6, lastNight]· ο μήνας:
/// [lastNight − 29, lastNight]. [today]: η σημερινή μέρα, για να μη λέγεται «χθεσινή» μια παλιά νύχτα.
OxygenGuidance oxygenGuidance(Map<DateTime, double> minByNight, DateTime lastNight, {DateTime? today}) {
  final last = DateTime(lastNight.year, lastNight.month, lastNight.day);
  final from7 = DateTime(last.year, last.month, last.day - (oxygenWindowNights - 1));
  final from30 = DateTime(last.year, last.month, last.day - (oxygenLongWindowNights - 1));
  var low = 0;
  var measured = 0;
  var veryLow30 = 0;
  final veryLowList = <(DateTime, double)>[];
  double? lastValue;
  for (final e in minByNight.entries) {
    final d = DateTime(e.key.year, e.key.month, e.key.day);
    if (d.isBefore(from30) || d.isAfter(last) || !e.value.isFinite) continue;
    if (e.value < oxygenVeryLow) {
      veryLow30++;
      veryLowList.add((d, e.value));
    }
    if (d.isBefore(from7)) continue;
    measured++;
    if (e.value < oxygenLow) low++;
    if (d == last) lastValue = e.value;
  }
  return OxygenGuidance(
    veryLowLastNight: lastValue != null && lastValue < oxygenVeryLow,
    lowNights: low,
    measuredNights: measured,
    veryLowNights30: veryLow30,
    veryLowList: veryLowList..sort((a, b) => a.$1.compareTo(b.$1)),
    lastNight: last,
    today: today == null ? null : dayOf(today),
  );
}

/// Κλινικός έλεγχος M6 και L3 (4/11): σταθερή γραμμή στο τέλος της Καρδιάς. «ΗΚΓ (ECG)» όπως στο PDF· όχι «ισχύουν
/// μόνο», που διαβαζόταν σαν «αυτά αρκούν».
const heartRhythmNote = 'Η εφαρμογή δεν ελέγχει τον ρυθμό της καρδιάς σου. Ακανόνιστο ρυθμό ελέγχουν μόνο το ΗΚΓ (ECG) '
    'και οι ειδοποιήσεις του Samsung Health Monitor, και χωρίς ειδοποίηση δεν αποκλείεται κολπική μαρμαρυγή. Αν έχεις '
    'πόνο στο στήθος, δύσπνοια, λιποθυμία ή έντονο φτερούγισμα, μην περιμένεις: 166 ή 112.';

/// Η χαμηλότερη μέτρηση, ποτέ στρογγυλεμένη προς τα πάνω: 89,6 → «89,6», 89,96 → «89,9», 88 → «88».
/// (Ποτέ «90%» για τιμή κάτω από 90· έλεγχος υπολογισμών F16.)
String lowestText(double v) {
  final f = (v * 10 + 1e-9).floorToDouble() / 10;
  if (f == f.roundToDouble()) return f.toStringAsFixed(0);
  return f.toStringAsFixed(1).replaceAll('.', ',');
}
