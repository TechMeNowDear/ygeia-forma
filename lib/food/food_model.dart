/// Διατροφή: τρόφιμα, καταχωρίσεις, γεύματα.
///
/// Κανόνες ακρίβειας (έγγραφο › «Βάση τροφίμων»):
/// - Οι αριθμοί έρχονται ΜΟΝΟ από βάση (CIQUAL, USDA, Open Food Facts, ετικέτα που πέρασα εγώ). Ποτέ από AI.
/// - Τιμές ανά 100 g. «Ίχνη» και «<x» μετράνε 0 στα αθροίσματα και δείχνονται όπως είναι.
/// - Κάθε καταχώριση κρατά αντίγραφο των τιμών ανά 100 g τη στιγμή που μπήκε.
library;

import 'dart:math' as math;

import '../format.dart';

/// Κλειδιά θρεπτικών (ίδια με τα αρχεία της βάσης).
abstract final class Nk {
  static const kcal = 'kcal';
  static const protein = 'protein';
  static const carbs = 'carbs';
  static const sugars = 'sugars';
  static const fiber = 'fiber';
  static const fat = 'fat';
  static const satFat = 'satFat';
  static const salt = 'salt';

  /// Νάτριο σε mg (της πηγής· ή από την ετικέτα, όταν γράφει νάτριο αντί για αλάτι).
  static const sodium = 'sodium';

  /// Αλκοόλ, πολυόλες και ερυθριτόλη σε g ανά 100 (δίνουν θερμίδες που δεν φαίνονται στα μακροθρεπτικά).
  static const alcohol = 'alcohol';
  static const polyols = 'polyols';
  static const erythritol = 'erythritol';
}

/// Η μεγαλύτερη ποσότητα μιας καταχώρισης (g ή ml). Το ίδιο όριο ισχύει για τη «μία μερίδα» ενός προϊόντος: μερίδα που
/// δεν γίνεται να γραφτεί δεν προτείνεται (τελικός έλεγχος, Συμβούλιο 3).
const maxEntryGrams = 5000.0;

/// Η «μία μερίδα» όπως διαβάστηκε (αρχείο, αντίγραφο, Open Food Facts, φόρμα): μόνο αριθμός πάνω από 0 και ως
/// [maxEntryGrams]. Οτιδήποτε άλλο (0, αρνητικό, τεράστιο, όχι αριθμός) = «χωρίς μερίδα».
double? validServing(Object? v) => v is num && v.isFinite && v > 0 && v <= maxEntryGrams ? v.toDouble() : null;

/// Τι μετρά ένα ΔΙΚΟ ΜΟΥ προϊόν στην κάρτα «Χοληστερίνη» (έλεγχος round1, S2-1 / S1-9). Αποθηκεύεται στο προϊόν και
/// στο αντίγραφο κάθε καταχώρισης με το κλειδί «ck»· προαιρετικό: οι παλιές εκδόσεις το αγνοούν, και προϊόν χωρίς
/// αυτό μετρά όπως πριν. Τα τρόφιμα της βάσης δεν το έχουν: εκείνα μετρούν από την κατηγορία τους (lib/food/chol.dart).
abstract final class CholKind {
  static const nuts = 'nuts';
  static const legumes = 'legumes';
  static const fish = 'fish';
  static const bran = 'bran';

  /// «Τίποτα»: το προϊόν δεν μετρά (round7, R7-A3-1). Πριν το «Τίποτα» αποθηκευόταν ως «δεν ορίστηκε» (null), οπότε ένα
  /// «Ψωμί με πίτουρο βρώμης» μετρούσε από το όνομα ως πίτουρο και δεν διορθωνόταν. Νέα τιμή: οι παλιές εκδόσεις την
  /// διαβάζουν ως null (όπως πριν).
  static const none = 'none';
  static const all = [nuts, legumes, fish, bran, none];

  /// Μόνο οι γνωστές τιμές· οτιδήποτε άλλο (πειραγμένο αντίγραφο, άγνωστη τιμή) = «δεν ορίστηκε».
  static String? parse(Object? v) => v is String && all.contains(v) ? v : null;
}

/// Τιμή θρεπτικού όπως έρχεται από την πηγή.
class NValue {
  const NValue(this.value, {this.lessThan = false, this.traces = false});
  final double value;

  /// «<x»: η πηγή λέει μόνο ότι είναι μικρότερο από value.
  final bool lessThan;
  final bool traces;

  /// Για αθροίσματα: «ίχνη» και «<x» μετράνε 0.
  double get amount => (lessThan || traces) ? 0 : value;

  static NValue? fromJson(Object? j) {
    if (j is num) return NValue(j.toDouble());
    if (j is Map) {
      if (j['tr'] == true) return const NValue(0, traces: true);
      if (j['lt'] is num) return NValue((j['lt'] as num).toDouble(), lessThan: true);
    }
    return null;
  }

  Object toJson() => traces ? {'tr': true} : (lessThan ? {'lt': value} : value);
}

class Nutrients {
  Nutrients(this.values);
  final Map<String, NValue> values;

  factory Nutrients.fromJson(Map<String, dynamic> j) => Nutrients({
        for (final e in j.entries)
          if (NValue.fromJson(e.value) case final v?) e.key: v,
      });

  Map<String, Object> toJson() => {for (final e in values.entries) e.key: e.value.toJson()};

  NValue? operator [](String k) => values[k];
  double amount(String k) => values[k]?.amount ?? 0;
  bool has(String k) => values.containsKey(k);
}

class Food {
  Food({
    required this.id,
    required this.name,
    required this.cat,
    required this.n,
    this.aliases = const [],
    required this.source,
    this.sourceCode,
    this.sourceName,
    this.brand,
    this.barcode,
    this.energyCalc = false,
    this.servingGrams,
    this.servingLabel,
    this.rawId,
    this.cookedLabel,
    this.cooked = const [],
    this.perMl = false,
    this.cholKind,
    this.spoon = false,
  });

  /// Δικό μου προϊόν: τι μετρά στην κάρτα «Χοληστερίνη» ([CholKind]) ή null (δεν ορίστηκε).
  final String? cholKind;

  /// Round9 (R9-A2-2): δικό μου προϊόν που μετριέται με το κουτάλι (ταχίνι, φυστικοβούτυρο, μαργαρίνη, μαγιονέζα), από τις
  /// κατηγορίες του Open Food Facts ή από τη φόρμα ([isSpoonFood]). Κλειδί «sp» (νέο, προαιρετικό: οι παλιές εκδόσεις το
  /// αγνοούν, και χωρίς αυτό το προϊόν μένει όπως πριν). Τα τρόφιμα της βάσης δεν το έχουν: εκείνα από την κατηγορία τους.
  final bool spoon;

  /// Οι τιμές είναι ανά 100 ml (υγρό από το Open Food Facts). Αποθηκεύεται, ώστε η διόρθωση αργότερα να λέει ξανά
  /// «ανά 100 ml» και όχι «ανά 100 g» (δεύτερος έλεγχος διατροφής N9).
  final bool perMl;

  final String id;
  final String name;
  final String cat;
  final List<String> aliases;

  /// «CIQUAL 2025», «USDA SR Legacy», «Open Food Facts», «Ετικέτα».
  final String source;
  final Object? sourceCode;
  final String? sourceName;
  final String? brand;
  final String? barcode;
  final bool energyCalc;

  /// Μερίδα της συσκευασίας (αν τη δίνει η πηγή).
  final double? servingGrams;
  final String? servingLabel;

  final Nutrients n;

  /// Αν αυτό είναι μαγειρεμένη μορφή: το id της ωμής και ο τρόπος («Βρασμένο», «Ψητό»…).
  final String? rawId;
  final String? cookedLabel;

  /// Αν αυτό είναι ωμό: οι μαγειρεμένες μορφές του (id, τρόπος).
  final List<(String, String)> cooked;

  bool get isRawWithCooked => cooked.isNotEmpty;

  bool get isMine => source == 'Open Food Facts' || source == 'Ετικέτα';

  /// «ml» για υγρά με τιμές ανά 100 ml (η ποσότητα γράφεται τότε σε ml), αλλιώς «g».
  String get unit => perMl ? 'ml' : 'g';

  factory Food.fromJson(Map<String, dynamic> j) => Food(
        id: j['id'] as String,
        name: j['name'] as String,
        cat: (j['cat'] as String?) ?? '',
        aliases: [for (final a in (j['aliases'] as List?) ?? const []) a.toString()],
        source: (j['source'] as String?) ?? '',
        sourceCode: j['sourceCode'],
        sourceName: j['sourceName'] as String?,
        brand: j['brand'] as String?,
        barcode: j['barcode'] as String?,
        energyCalc: j['energyCalc'] == true,
        // Τελικός έλεγχος (Συμβούλιο 3): μερίδα 0, αρνητική ή τεράστια (παλιά καταχώριση, πειραγμένο αντίγραφο) δεν
        // προτείνεται ως ποσότητα· το προϊόν και οι τιμές του μένουν όπως είναι.
        servingGrams: validServing(j['servingGrams']),
        servingLabel: j['servingLabel'] as String?,
        rawId: j['rawId'] as String?,
        cookedLabel: j['cookedLabel'] as String?,
        perMl: j['perMl'] == true,
        cholKind: CholKind.parse(j['ck']),
        spoon: j['sp'] == true,
        cooked: [
          for (final c in (j['cooked'] as List?) ?? const [])
            if (c is Map) ((c['id'] as String), (c['label'] as String)),
        ],
        n: Nutrients.fromJson(Map<String, dynamic>.from(j['n'] as Map)),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'cat': cat,
        'aliases': aliases,
        'source': source,
        if (sourceCode != null) 'sourceCode': sourceCode,
        if (sourceName != null) 'sourceName': sourceName,
        if (brand != null) 'brand': brand,
        if (barcode != null) 'barcode': barcode,
        if (energyCalc) 'energyCalc': true,
        if (servingGrams != null) 'servingGrams': servingGrams,
        if (servingLabel != null) 'servingLabel': servingLabel,
        if (rawId != null) 'rawId': rawId,
        if (cookedLabel != null) 'cookedLabel': cookedLabel,
        if (cooked.isNotEmpty) 'cooked': [for (final c in cooked) {'id': c.$1, 'label': c.$2}],
        if (perMl) 'perMl': true,
        if (cholKind != null) 'ck': cholKind,
        if (spoon) 'sp': true,
        'n': n.toJson(),
      };

  /// Το αντίγραφο που κρατά κάθε καταχώριση: ό,τι χρειάζεται για να δείχνει και να μετρά
  /// (όνομα, πηγή, τιμές), χωρίς τα στοιχεία αναζήτησης (άλλα ονόματα, περιγραφή πηγής, μορφές),
  /// που υπάρχουν ήδη στη βάση. Μικρότερο ημερολόγιο και αντίγραφο ασφαλείας.
  Map<String, Object?> toSnapshotJson() => {
        for (final e in toJson().entries)
          if (e.key != 'aliases' && e.key != 'sourceName' && e.key != 'cooked') e.key: e.value,
      };
}

enum Meal { breakfast, lunch, dinner, snack }

/// Σύντομα ονόματα, ίδιου μεγέθους στο κουμπί επιλογής (UX U7: το «Μεσημεριανό» μίκραινε για να χωρέσει στα 400 dp).
String mealLabel(Meal m) => switch (m) {
      Meal.breakfast => 'Πρωινό',
      Meal.lunch => 'Μεσημέρι',
      Meal.dinner => 'Βράδυ',
      Meal.snack => 'Σνακ',
    };

/// Έξυπνη προεπιλογή γεύματος από την ώρα (έγγραφο › Καταχώριση). Δείπνο ως τις 00:30: στην Ελλάδα τρώμε αργά
/// (έλεγχος 9/11, RT-14· πριν, ό,τι γραφόταν μετά τις 23:00 έμπαινε «Σνακ»).
Meal mealForTime(DateTime t) {
  final h = t.hour;
  if (h >= 5 && h < 11) return Meal.breakfast;
  if (h >= 12 && h < 17) return Meal.lunch;
  if (h >= 19 || (h == 0 && t.minute < 30)) return Meal.dinner;
  return Meal.snack;
}

class LogEntry {
  LogEntry({
    required this.id,
    required this.day,
    required this.meal,
    required this.food,
    required this.grams,
    required this.time,
  });

  final String id;

  /// «2026-10-24»
  final String day;
  final Meal meal;

  /// Αντίγραφο του τροφίμου τη στιγμή της καταχώρισης.
  final Food food;
  final double grams;
  final DateTime time;

  double total(String k) => food.n.amount(k) * grams / 100;

  LogEntry copyWith({Meal? meal, double? grams, Food? food}) => LogEntry(
      id: id, day: day, meal: meal ?? this.meal, food: food ?? this.food, grams: grams ?? this.grams, time: time);

  factory LogEntry.fromJson(Map<String, dynamic> j) => LogEntry(
        id: j['id'] as String,
        day: j['day'] as String,
        meal: Meal.values.firstWhere((m) => m.name == j['meal'], orElse: () => Meal.snack),
        food: Food.fromJson(Map<String, dynamic>.from(j['food'] as Map)),
        grams: (j['grams'] as num).toDouble(),
        time: DateTime.fromMillisecondsSinceEpoch((j['time'] as num).toInt()),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'day': day,
        'meal': meal.name,
        'food': food.toSnapshotJson(),
        'grams': grams,
        'time': time.millisecondsSinceEpoch,
      };
}

/// Σύνολα για ένα σύνολο καταχωρίσεων.
class Totals {
  Totals(Iterable<LogEntry> entries) {
    for (final e in entries) {
      kcal += e.total(Nk.kcal);
      protein += e.total(Nk.protein);
      carbs += e.total(Nk.carbs);
      fat += e.total(Nk.fat);
      fiber += e.total(Nk.fiber);
      sugars += e.total(Nk.sugars);
      salt += e.total(Nk.salt);
      satFat += e.total(Nk.satFat);
      alcohol += e.total(Nk.alcohol);
      shownKcal += e.total(Nk.kcal).round();
      for (final k in const [Nk.fiber, Nk.sugars, Nk.salt, Nk.satFat]) {
        if (!e.food.n.has(k)) missing[k] = (missing[k] ?? 0) + 1;
      }
      count++;
    }
  }
  double kcal = 0, protein = 0, carbs = 0, fat = 0, fiber = 0, sugars = 0, salt = 0, satFat = 0, alcohol = 0;
  int count = 0;

  /// Θερμίδες όπως φαίνονται: το άθροισμα των στρογγυλεμένων θερμίδων κάθε καταχώρισης, ώστε τα κομμάτια να
  /// αθροίζουν ακριβώς στο σύνολο που γράφει η οθόνη (έλεγχος 9/11, Χ4). Διαφέρει από το [kcal] το πολύ λίγες kcal.
  int shownKcal = 0;

  /// Πόσα τρόφιμα δεν έχουν τιμή για κάθε θρεπτικό (τότε το σύνολο είναι «τουλάχιστον»).
  final Map<String, int> missing = {};
}

// ---------------------------------------------------------------------------
// Καταχώριση που μοιάζει με λάθος πληκτρολόγησης (έλεγχος round1, S11-3)
// ---------------------------------------------------------------------------
//
// Ένα «2000» αντί για «20» σε λάδι βάζει 17.000 kcal σε μία μέρα, και η εβδομαδιαία διόρθωση θερμίδων το πιστεύει για
// εβδομάδες. Γι' αυτό μια καταχώριση που σχεδόν σίγουρα είναι λάθος ζητά ΜΙΑ επιβεβαίωση πριν γραφτεί. Δεν μπλοκάρει
// τίποτα: με «Ναι, σωστό» γράφεται όπως είναι. Τα όρια είναι δική μας επιλογή (όχι από μελέτη), βαλμένα ώστε μια
// κανονική μεγάλη μερίδα να μην ρωτιέται ποτέ:

/// 1. Μία καταχώριση με τόσες θερμίδες ή περισσότερες: όσες η «πρόσληψη αναφοράς» ΟΛΗΣ της μέρας για έναν ενήλικα
///    (2.000 kcal, Κανονισμός ΕΕ 1169/2011, Παράρτημα XIII).
const typoEntryKcal = 2000.0;

/// 2. Ένα κιλό (ή λίτρο) και πάνω σε μία καταχώριση, όταν δίνει πάνω από [typoEntryBigKcal] θερμίδες: είναι ό,τι βγάζει
///    ένα μηδενικό παραπάνω στη συνηθισμένη μερίδα των 100–300 g. Το όριο θερμίδων αφήνει έξω νερό, τσάι, καρπούζι,
///    σαλάτα, που τρώγονται και με το κιλό.
const typoEntryBigGrams = 1000.0;
const typoEntryBigKcal = 500.0;

/// 3. Λάδι, βούτυρο και άλλα σχεδόν καθαρά λίπη (από [typoFatPer100] g λιπαρά στα 100): από 100 g και πάνω σε μία
///    καταχώριση (περίπου 7 κουταλιές της σούπας, 750–900 kcal). Η συνηθισμένη καταχώριση είναι 5–30 g, και ένα
///    μηδενικό παραπάνω τη φέρνει ακριβώς εδώ (10 → 100). Round8 (R8-A2-1): και για κάθε τρόφιμο του κουταλιού
///    ([isSpoonFood]: μαγιονέζα, μαργαρίνη, ταχίνι, φυστικοβούτυρο).
const typoFatPer100 = 80.0;
const typoFatGrams = 100.0;

/// 4. Πυκνό τρόφιμο (από [typoDensePer100] kcal στα 100 g: βρώμη, πίτουρο, ξηροί καρποί, τυρί, ζυμαρικά ή ρύζι ωμά) από
///    [typoDenseGrams] g και πάνω (round7, R7-A2-3): ένα μηδενικό παραπάνω στη μερίδα των 30–50 g (50 → 500 g βρώμη =
///    1.845 kcal) περνούσε χωρίς ερώτηση. Η συνηθισμένη μερίδα αυτών είναι 30–100 g.
const typoDensePer100 = 250.0;
const typoDenseGrams = 300.0;

/// 5. Πέντε φορές (ή περισσότερο) η ποσότητα της τελευταίας φοράς, όταν δίνει από [typoTimesLastKcal] kcal (round7,
///    R7-A2-3): 60 → 600 g ψωμί (1.404 kcal), 80 → 800 g τόνος (1.144 kcal). Το όριο θερμίδων αφήνει έξω τα μικρά
///    (γάλα 30 → 250 ml στον καφέ, 119 kcal).
const typoTimesLast = 5.0;
const typoTimesLastKcal = 400.0;

/// 6. Αλάτι (round8, R8-U2-7): τρόφιμο με τουλάχιστον [typoSaltPer100] g αλάτι στα 100 (το ίδιο το αλάτι, κύβοι ζωμού)
///    με [typoSaltGrams] g αλάτι και πάνω σε μία καταχώριση: το διπλάσιο του ορίου όλης της μέρας (λιγότερο από 5 g, ΠΟΥ
///    2012). Το αλάτι έχει 0 kcal, οπότε κανένας κανόνας θερμίδων δεν έπιανε τα 100 g αντί για 1. Μόνο για τέτοια
///    τρόφιμα: παστά ψάρια και αντζούγιες (12–14 g στα 100) τρώγονται και με 100 g.
const typoSaltPer100 = 50.0;
const typoSaltGrams = 10.0;

/// Round8 (R8-A2-1 / R8-U2-3): τρόφιμα που μετριούνται με το κουτάλι. Σχεδόν καθαρά λίπη (από [typoFatPer100] g
/// λιπαρά στα 100), ό,τι είναι στην κατηγορία «Λιπαρά» της βάσης εκτός από τις ελιές (μαγιονέζα, μαργαρίνη), και τα
/// πυκνά αλείμματα (ταχίνι, φυστικοβούτυρο, πραλίνα: από [spoonSpreadKcal] kcal στα 100 g· όχι το χούμους). Ένας
/// κανόνας για την πρώτη ποσότητα, τα κουμπιά ποσότητας (5, 10, 15, 30 g) και τον κανόνα 3 του ελέγχου λάθους: πριν η
/// μαγιονέζα άνοιγε με 10 g αλλά με κουμπιά 50–200 g (ένα πάτημα «100 g» = 692 kcal, χωρίς ερώτηση), και το ταχίνι
/// άνοιγε με 100 g (631 kcal). Round9 (R9-A2-2): και τα δικά μου προϊόντα που το λένε ([Food.spoon]: σαρωμένο ταχίνι,
/// φυστικοβούτυρο, μαργαρίνη, μαγιονέζα), που πριν έμεναν έξω όταν είχαν λιγότερα από 80 g λιπαρά.
bool isSpoonFood(Food f) =>
    f.spoon ||
    f.n.amount(Nk.fat) >= typoFatPer100 ||
    (f.cat == 'Λιπαρά' && !isOlives(f)) ||
    (f.cat == 'Αλείμματα' && f.n.amount(Nk.kcal) >= spoonSpreadKcal);

const spoonSpreadKcal = 500.0;

/// Ελιές της βάσης (κατηγορία «Λιπαρά»): μετριούνται με το κομμάτι, όχι με το κουτάλι, και 100 g ελιές είναι κανονική
/// ποσότητα (164–349 kcal).
bool isOlives(Food f) => f.cat == 'Λιπαρά' && f.name.toLowerCase().startsWith('ελιές');

/// Μοιάζει η καταχώριση ([grams] g ή ml του [f]) με λάθος πληκτρολόγησης; Τότε η οθόνη ρωτά μία φορά πριν τη γράψει.
/// [lastGrams]: η ποσότητα της τελευταίας φοράς που γράφτηκε αυτό το τρόφιμο (αν υπάρχει).
bool entryLooksLikeTypo(Food f, double grams, {double? lastGrams}) {
  final kcal = f.n.amount(Nk.kcal) * grams / 100;
  if (kcal >= typoEntryKcal) return true;
  if (grams >= typoEntryBigGrams && kcal > typoEntryBigKcal) return true;
  // Κανόνας 3 και για ό,τι άλλο μετριέται με το κουτάλι (round8, R8-A2-1): 10 → 100 g μαγιονέζα, 15 → 150 g ταχίνι.
  if (isSpoonFood(f) && grams >= typoFatGrams) return true;
  if (f.n.amount(Nk.kcal) >= typoDensePer100 && grams >= typoDenseGrams) return true;
  if (f.n.amount(Nk.salt) >= typoSaltPer100 && f.n.amount(Nk.salt) * grams / 100 >= typoSaltGrams) return true;
  return lastGrams != null && lastGrams > 0 && grams >= typoTimesLast * lastGrams && kcal >= typoTimesLastKcal;
}

// ---------------------------------------------------------------------------
// Ξερό ή μαγειρεμένο; (round7, R7-U2-2)
// ---------------------------------------------------------------------------
//
// Την πρώτη φορά που γράφεις «φακές», «ρύζι» ή «μακαρόνια» βγαίνει πρώτη η ξερή/ωμή μορφή (ζυγίζουμε ωμά). Αν ζύγισες το
// πιάτο σου μαγειρεμένο, 300 g «Φακές (ξερές)» = 981 kcal αντί για 375 (×2,3–2,9). Γι' αυτό ρωτάμε ΜΙΑ φορά ανά τρόφιμο.

/// Ξερά όσπρια, ζυμαρικά, ρύζι και δημητριακά της βάσης έχουν 307–381 kcal στα 100 g· οι μαγειρεμένες μορφές τους
/// 112–179. Κανένα άλλο τρόφιμο με μαγειρεμένη μορφή δεν φτάνει τις 300.
const rawCheckKcal = 300.0;

/// Από τόσα γραμμάρια: η συνηθισμένη ξερή μερίδα είναι 50–100 g, το μαγειρεμένο πιάτο 200–400 g.
const rawCheckGrams = 150.0;

/// Να ρωτήσει η οθόνη «πριν ή μετά το μαγείρεμα;»; Μόνο για ξερή/ωμή μορφή με μαγειρεμένη μορφή στη βάση, από
/// [rawCheckGrams] g, και μόνο όσο δεν την έχεις γράψει ποτέ ([timesEaten] = 0). Round9 (R9-A2-3): [dryMine] = δικό μου
/// ξερό προϊόν (ζυμαρικό, ρύζι, όσπριο) που έχει βρασμένη μορφή στη βάση (off.dart, `dryStapleRawId`).
bool askRawOrCooked(Food f, double grams, {required int timesEaten, bool dryMine = false}) =>
    (f.isRawWithCooked || dryMine) && f.n.amount(Nk.kcal) >= rawCheckKcal && grams >= rawCheckGrams && timesEaten == 0;

/// «1.250» για θερμίδες, «12,5» για γραμμάρια.
String kcalText(double v) => thousands(v.round());
String gramsText(double v) {
  if (v >= 100) return v.round().toString();
  if (v >= 10) return dec(v, 0);
  // Έλεγχος round1 (U3a-14): ακέραια ποσότητα κάτω από 10 χωρίς «,0» («5 g», «0 g»· πριν «5,0 g», «0,0 g»). Το «1,3» μένει.
  final t = dec(v, 1);
  return t.endsWith(',0') ? t.substring(0, t.length - 2) : t;
}

/// Κείμενο τιμής ανά 100 g όπως στην πηγή: «<0,5», «ίχνη», «12,3».
String nValueText(NValue? v, {int digits = 1}) {
  if (v == null) return '—';
  if (v.traces) return 'ίχνη';
  // Το όριο «<x» στρογγυλεύεται προς τα πάνω: «<0,0125 g» γράφεται «<0,02», ποτέ «<0,01» (που θα ήταν λιγότερο από το όριο).
  if (v.lessThan) {
    final f = math.pow(10, digits);
    return '<${dec(((v.value * f) - 1e-9).ceil() / f, digits)}';
  }
  return dec(v.value, digits);
}
