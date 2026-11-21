/// AI για το φαγητό (19/11, έγγραφο προδιαγραφών › «AI για το φαγητό»· βαθύς έλεγχος 19/11).
///
/// Κανόνες που δεν αλλάζουν:
/// - Το AI ΔΙΑΛΕΓΕΙ (φαγητά, υλικά, ωμά γραμμάρια, βήματα). Οι θερμίδες και τα θρεπτικά βγαίνουν ΠΑΝΤΑ από τη βάση· ό,τι
///   αριθμό γράψει το AI αγνοείται. Οι μερίδες του προγράμματος βγαίνουν από τους ίδιους κανόνες με το «Φτιάξε πρόγραμμα».
/// - Υλικά: ΜΟΝΟ «Μου αρέσει» + «Βασικά κουζίνας», ποτέ «Δε μου αρέσει» ([aiAllowedIds]). Ελέγχεται εδώ, όχι με
///   εμπιστοσύνη στο AI. Φαγητό της βιβλιοθήκης με έστω ένα άλλο υλικό δεν προτείνεται.
/// - Κάθε νέα συνταγή ελέγχεται και για ασφάλεια και λογική ([aiDishProblems]): τίποτα ωμό που θέλει μαγείρεμα σε φαγητό
///   «χωρίς μαγείρεμα», αλάτι, λάδι, ζάχαρη, αλλαντικά, αλκοόλ, μέγεθος μερίδας.
/// - Ό,τι δεν περνά τους ελέγχους πάει πίσω στο AI με τα προβλήματα (ως 2 φορές)· αν ξανά δεν περνά, το λέμε. Ποτέ κάτι
///   «περίπου σωστό» στη θέση του, και ποτέ φαγητά που δεν διάλεξε το AI από τη λίστα του.
/// - Το πρόγραμμα ελέγχεται ξανά από τη βάση ([aiCheckWeek]): κάθε μέρα (θερμίδες, πρωτεΐνη, κορεσμένα, αλάτι, ίνες, φρούτα
///   και λαχανικά, ζάχαρη) και η εβδομάδα (όσπρια, ψάρι, κόκκινο κρέας, αλλαντικά, υδράργυρος, κατσαρόλες, χρόνος).
/// - Τίποτα δεν γράφεται πριν πεις «Ναι»: οι συναρτήσεις εδώ ΜΟΝΟ ετοιμάζουν (πρόγραμμα, νέα φαγητά, αλλαγή γεύματος).
/// - (Ως 19/11· από τις αποφάσεις 20/11 πηγαίνουν και τα όρια της μέρας: κορεσμένα, αλάτι, ίνες, πρωτεΐνη· δες [aiSystem].)
///   Στο AI δεν πήγαιναν αριθμοί στόχων που προδίδουν υγεία ή βάρος (κορεσμένα, πρωτεΐνη σε γραμμάρια): μόνο θερμίδες
///   ανά γεύμα σε στρογγυλά νούμερα και λόγια («πολλή πρωτεΐνη»)· τα προβλήματα πάνε ως ποσοστά (έλεγχος 19/11, X-3).
/// - Σε κάθε κλήση: λίγη δουλειά (σχέδιο ή ΜΙΑ συνταγή), ώστε να χωράει στα 150″ του Supabase.
library;

import 'dart:convert';
import 'dart:math' as math;

import '../ai/ai_bridge.dart';
import '../history.dart' show dateKey;
import 'chol.dart' show isLegumes, isFish, cookedLegumes, legumesDryMinG, legumesCookedFactor, fishMinG;
import 'dishes.dart';
import 'food_model.dart';
import 'food_store.dart';
import 'kitchen.dart';
import 'library.dart';
import 'recipe.dart';
import 'week.dart';
import 'week_auto.dart';
import 'week_calc.dart';

const aiWeekKind = 'ygeia-ai-week';
const aiSwapKind = 'ygeia-ai-swap';

/// Τα κλειδιά των φαγητών που φτιάχνει το AI ξεκινούν έτσι, ώστε να μη συγκρούονται με τη βιβλιοθήκη από το άλλο project
/// (ίδιο κλειδί = αντικατάσταση· έλεγχος 19/11, I-7).
const aiKeyPrefix = 'ai-';

/// Το πολύ τόσα νέα φαγητά σε ένα πρόγραμμα (το καθένα είναι μία κλήση).
const aiMaxNewDishes = 8;

/// Ως τόσες φορές ξαναρωτάμε το AI με τα προβλήματα μίας απάντησης.
const aiMaxRetries = 2;

/// Ως τόσες συνταγές ταυτόχρονα (η πρώτη πάντα μόνη της, για να μπει το σταθερό κομμάτι στην cache).
const aiParallel = 3;

/// «Ανάλογο» γεύμα (απόφαση χρήστη 19/11): θερμίδες ±10%, πρωτεΐνη τουλάχιστον 90%, κορεσμένα το πολύ +1 g.
const aiSwapKcalTol = 0.10;
const aiSwapProteinMin = 0.90;
const aiSwapSatExtra = 1.0;

/// «Δεν έχω χρόνο»: ως τόσα λεπτά (ή χωρίς μαγείρεμα).
const aiQuickMinutes = 15;

/// Έλεγχος κάθε μέρας του προγράμματος.
const aiDayKcalTol = 0.10;
const aiDayProteinMin = 0.90;
const aiDayFiberMin = 0.80;

/// Φρούτα και λαχανικά τη μέρα (ΠΟΥ: τουλάχιστον 400 g· η μέρα θέλει τουλάχιστον 300 g, αναλογικά με τα γεύματα).
const aiFruitVegDayG = 300.0;

/// Ελεύθερα σάκχαρα (κατηγορία «Γλυκά»): κάτω από το 10% των θερμίδων (ΠΟΥ).
const aiFreeSugarPct = 0.10;

/// Μέσος όρος θερμίδων της εβδομάδας: ±5% του στόχου.
const aiWeekKcalTol = 0.05;

/// Όρια ανά μερίδα για τις συνταγές του AI (δική μας επιλογή για υγιεινή συνταγή, έλεγχος 19/11, L-1/S-2/S-12/S-13):
/// πρόσθετο αλάτι, αλάτι συνολικά (μαζί με τυρί, ψωμί…), λάδια/βούτυρο, ζάχαρη/μέλι, αλλαντικά, ξερά μπαχαρικά, αλκοόλ.
const aiMaxAddedSaltG = 1.2;
const aiMaxSaltG = 2.5;
const aiMaxFatsG = 20.0;
const aiMaxSweetG = 15.0;
const aiMaxProcessedG = 40.0;
const aiMaxSpiceG = 5.0;
const aiMaxAlcoholG = 60.0;

/// Κατσαρόλα: η 2η φορά το πολύ τόσες μέρες μετά (FSA: περισσεύματα ως 48 ώρες)· με ρύζι μόνο την επόμενη (Bacillus
/// cereus, FSS). Τα 2–3 άτομα του σπιτιού τρώνε κι αυτά: ο χρήστης το πολύ το μισό της κατσαρόλας.
const aiPotMaxGap = 2;
const aiPotRiceGap = 1;
const aiPotUserShare = 0.5;

/// Υδράργυρος (EFSA 2012: ανεκτή εβδομαδιαία πρόσληψη μεθυλυδραργύρου 1,3 µg/kg βάρους)· μέσες τιμές FDA «Mercury Levels in
/// Commercial Fish and Shellfish (1990–2012)» σε mg/kg (= µg/g).
///
/// Έλεγχος 20/11 (K2-S-01): τιμή για ΚΑΘΕ ψάρι και θαλασσινό της βάσης. Πριν μετρούσαν μόνο ξιφίας και τόνος, και κάθε άλλο
/// ψάρι έμπαινε με 0: μια εβδομάδα με μπακαλιάρο (0,111, όσο σχεδόν ο τόνος σε νερό), μερλούσα ή λαβράκι έφτανε το
/// 96–150% του ορίου και ο έλεγχος έγραφε 0 µg. Λαβράκι: «Bass, saltwater» της FDA (το λαβράκι ιχθυοτροφείου έχει συνήθως
/// λιγότερο: συντηρητικό). Σκουμπρί: η μεγαλύτερη από τις δύο τιμές (chub 0,088· Atlantic 0,05). Μύδια: δεν υπάρχουν στον
/// πίνακα· η μεγαλύτερη τιμή διθύρων (στρείδι 0,012· αχιβάδα 0,009· χτένι 0,003). Ό,τι δεν έχει τιμή στον πίνακα (τσιπούρα,
/// σαυρίδι, χταπόδι, δικό σου προϊόν ψαριού) παίρνει το [aiMercuryDefaultPpm].
const aiMercuryTwiPerKg = 1.3;
const aiMercuryPpm = {
  'C26082': 0.995, // ξιφίας
  'C26179': 0.35, // τόνος λευκός (albacore), κονσέρβα
  'C26039': 0.126, // τόνος σε νερό (κονσέρβα, «light»)
  'C26205': 0.167, 'C26206': 0.167, 'C27030': 0.167, // λαβράκι
  'C26043': 0.111, 'C26023': 0.111, 'C26025': 0.111, 'C26024': 0.111, 'C26098': 0.111, // μπακαλιάρος (cod)
  'C26051': 0.088, 'C26019': 0.088, // σκουμπρί
  'C26044': 0.079, 'C26120': 0.079, // μερλούσα (hake)
  'C26011': 0.078, 'C26014': 0.078, 'C25998': 0.078, // ρέγγα
  'C10001': 0.024, 'C10084': 0.024, // καλαμάρι
  'C26036': 0.022, 'C26230': 0.022, 'C26229': 0.022, 'C26037': 0.022, // σολομός
  'C26079': 0.016, 'C26700': 0.016, 'C26694': 0.016, // γαύρος, αντζούγιες
  'C26065': 0.013, 'C26136': 0.013, 'C26040': 0.013, // σαρδέλα
  'C10026': 0.012, 'C10013': 0.012, // μύδια
  'C10021': 0.009, 'C10007': 0.009, // γαρίδες
};

/// Τελικός έλεγχος 21/11 (K2-R-03): παστές, καπνιστές και μορφές κονσέρβας που η βάση δεν τις δένει με ωμή μορφή
/// ([Food.rawId]): το είδος τους, για το [fishRawFactor]. Ο τόνος κονσέρβας ΔΕΝ είναι εδώ: η τιμή της FDA είναι ήδη για
/// την κονσέρβα.
const aiFishRawOf = {
  'C26024': 'C26043', 'C26098': 'C26043', // μπακαλιάρος παστός (βρασμένος, ξερός) → ωμός
  'C26037': 'C26036', // σολομός καπνιστός
  'C25998': 'C26011', // ρέγγα καπνιστή
  'C26700': 'C26079', 'C26694': 'C26079', // γαύρος μαρινάτος, αντζούγιες
  'C26040': 'C26065', // σαρδέλα κονσέρβα
};

/// Τελικός έλεγχος 21/11 (K2-R-03): πόσα γραμμάρια ΩΜΟΥ ψαριού αντιστοιχούν σε 1 g της μαγειρεμένης ή παστής μορφής [f].
/// Οι τιμές υδραργύρου της FDA είναι ανά g ψαριού όπως πουλιέται, και το όριο του λιπαρού ψαριού είναι σε g ωμού· το
/// μαγείρεμα και το πάστωμα βγάζουν νερό, όχι υδράργυρο ούτε πρωτεΐνη, άρα 1 g ψητού είναι περισσότερο από 1 g ωμού. Ο
/// λόγος είναι η πρωτεΐνη της μορφής προς την πρωτεΐνη της ωμής (τιμές της βάσης, ανά 100 g): μπακαλιάρος φούρνου 1,23,
/// σολομός σχάρας 1,24, χταπόδι μαγειρεμένο 2,31, παστός ξερός μπακαλιάρος 2,63. Πριν μετρούσαν σαν ωμά: ο υδράργυρος
/// έβγαινε 4% ως 57% χαμηλότερα σε φαγητά παραγγελίας και σε δικά σου φαγητά με ψημένο ψάρι (τα φαγητά του AI μπαίνουν με
/// ωμές μορφές: εκεί ήταν σωστό). Ωμό, ό,τι δεν είναι ψάρι, ή μορφή χωρίς γνωστή ωμή (π.χ. δικό σου προϊόν): 1. Ποτέ
/// κάτω από 1, και ως [aiFishRawFactorMax] (λάθος τιμή πρωτεΐνης δεν δίνει παράλογο αριθμό).
double fishRawFactor(Food f, Food? Function(String id) byId) {
  if (!isFish(f)) return 1;
  final rawId = f.rawId ?? aiFishRawOf[f.id];
  if (rawId == null) return 1;
  final raw = byId(rawId);
  if (raw == null || !f.n.has(Nk.protein) || !raw.n.has(Nk.protein)) return 1;
  final cooked = f.n.amount(Nk.protein), fresh = raw.n.amount(Nk.protein);
  if (!(cooked > 0) || !(fresh > 0)) return 1;
  final k = cooked / fresh;
  return k < 1 ? 1 : (k > aiFishRawFactorMax ? aiFishRawFactorMax : k);
}

const aiFishRawFactorMax = 3.0;

/// Έλεγχος 20/11 (K2-S-01): ψάρι ή θαλασσινό χωρίς τιμή στον πίνακα της FDA. Συντηρητική προεπιλογή, περίπου όσο ο
/// μπακαλιάρος: η τσιπούρα έχει μετρηθεί 0,05 (ιχθυοτροφείου) ως 0,09 mg/kg (άγρια) (Environ Sci Pollut Res 2021,
/// doi:10.1007/s11356-021-13366-y).
const aiMercuryDefaultPpm = 0.10;

/// Υδράργυρος του τροφίμου σε µg ανά g: ο πίνακας, αλλιώς η προεπιλογή για ψάρια και θαλασσινά ([isFish]), αλλιώς 0.
/// Δικό σου προϊόν με «ξιφία» ή «τόνο» στο όνομα: ξιφίας, ή τόνος λευκός (το είδος της κονσέρβας δεν είναι γνωστό· στα
/// ελληνικά ράφια είναι συχνά κιτρινόπτερος, που η FDA μετρά φρέσκο 0,354: μένει η συντηρητική τιμή του λευκού).
/// K2-R-02: και χωρίς τόνο στο γράμμα («ΞΙΦΙΑΣ» από barcode) ή στα αγγλικά/γαλλικά/ιταλικά.
double mercuryPpm(Food f) {
  final known = aiMercuryPpm[f.id];
  if (known != null) return known;
  if (!isFish(f)) return 0;
  final n = f.name.toLowerCase();
  if (n.contains('ξιφί') || n.contains('ξιφι') || n.contains('swordfish') || n.contains('espadon') || n.contains('pesce spada')) {
    return aiMercuryPpm['C26082']!;
  }
  if (n.contains('τόνο') || n.contains('τονο') || n.contains('tuna') || n.contains('thon') || n.contains('tonno')) {
    return aiMercuryPpm['C26179']!;
  }
  return aiMercuryDefaultPpm;
}

/// Έλεγχος 20/11 (K2-S-03): λιπαρά ψάρια (σολομός, σαρδέλα, σκουμπρί, ρέγγα, γαύρος, σαυρίδι) και το όριό τους. Το NHS
/// (σελίδα «Fish and shellfish», αναθ. 26/6/2026) δίνει για άνδρες ως 4 μερίδες λιπαρού ψαριού την εβδομάδα (μερίδα
/// περίπου 140 g μαγειρεμένο), λόγω ρύπων που μαζεύονται στο λίπος του ψαριού. 4 × 140 g μαγειρεμένο ÷ 0,78 ≈ 720 g ωμό.
/// Ο στόχος «ψάρι Χ φορές» μένει όπως είναι· αλλάζει μόνο πόσα από αυτά μπορούν να είναι λιπαρά.
/// K2-R-09: κάτω από τόσα g λιπαρό ψάρι την εβδομάδα = «κανένα» (μία μερίδα είναι τουλάχιστον 100 g ωμό).
const aiOilyFishMinG = 100.0;

const aiOilyFishIds = {
  'C26036', 'C26230', 'C26229', 'C26037', // σολομός
  'C26065', 'C26136', 'C26040', // σαρδέλα
  'C26051', 'C26019', // σκουμπρί
  'C26011', 'C26014', 'C25998', // ρέγγα
  'C26079', 'C26700', 'C26694', // γαύρος, αντζούγιες
  'C26113', // σαυρίδι
};
const aiOilyFishWeekG = 720.0;

/// Βασικά κουζίνας που προτείνονται (id της βάσης, σύντομο όνομα). Μπαίνουν ΜΟΝΟ αν τα εγκρίνεις.
const stapleSuggestions = [
  ('C17270', 'Ελαιόλαδο'),
  ('C11017', 'Αλάτι'),
  ('C11015', 'Πιπέρι'),
  ('C11035', 'Ρίγανη'),
  ('C11049', 'Πάπρικα'),
  ('C11025', 'Κανέλα'),
  ('C20034', 'Κρεμμύδι'),
  ('C11000', 'Σκόρδο'),
  ('C13009', 'Λεμόνι'),
  ('C11014', 'Μαϊντανός'),
  ('C11093', 'Άνηθος'),
  ('C11027', 'Δυόσμος'),
  ('C11033', 'Βασιλικός'),
  ('C20068', 'Πελτές ντομάτας'),
];

const _saltId = 'C11017';

/// Ο ξερός παστός μπακαλιάρος ζυγίζεται πριν το ξαλμύρισμα και μετρά όλο το αλάτι: δεν μπαίνει σε συνταγή του AI.
const _neverIds = {'C26098'};

String? _nowId(FoodStore food, String id) => food.itemFood(DishItem(id, id, 1))?.id;

/// Τα επιτρεπόμενα υλικά: «Μου αρέσει» + «Βασικά κουζίνας», χωρίς τα «Δε μου αρέσει». Όλα με το ΤΩΡΙΝΟ id της βάσης
/// (αντικατεστημένα τρόφιμα, I-2) και με την ωμή μορφή όταν διάλεξες μαγειρεμένη (I-17).
Set<String> aiAllowedIds(FoodStore food) {
  final l = food.likes;
  final bad = <String>{...l.dislike};
  for (final x in l.dislike) {
    final f = food.itemFood(DishItem(x, x, 1));
    if (f != null) {
      bad.add(f.id);
      if (f.rawId != null) bad.add(f.rawId!);
    }
  }
  final out = <String>{};
  for (final x in [...l.like, ...l.staple]) {
    final f = food.itemFood(DishItem(x, x, 1));
    if (f == null) continue;
    final id = f.rawId ?? f.id;
    if (!bad.contains(id) && !bad.contains(f.id) && !_neverIds.contains(id)) out.add(id);
  }
  return out;
}

/// Όλα τα υλικά του φαγητού επιτρέπονται και υπάρχουν.
bool aiDishAllowed(FoodStore food, Dish d, Set<String> allowed) =>
    d.items.isNotEmpty && d.items.every((i) => allowed.contains(_nowId(food, i.id)));

/// Τα φαγητά της βιβλιοθήκης που μπορεί να διαλέξει το AI: όλα τα υλικά επιτρέπονται, όχι «Δεν μου άρεσε», μαγείρεμα στο
/// σπίτι ή χωρίς μαγείρεμα (η παραγγελία θέλει μαγειρεμένες μορφές, που δεν είναι στη λίστα σου).
List<Dish> aiLibrary(FoodStore food, Set<String> allowed) => [
      for (final d in libraryDishes(food.dishes))
        if (dishRating(d) >= 0 && planInfoOf(d)!.cook != CookWay.out && aiDishAllowed(food, d, allowed) && portionRange(food, d) != null) d,
    ];

/// Τα επιτρεπόμενα τρόφιμα (ωμές μορφές), μία γραμμή ανά κατηγορία, με id και όνομα.
List<String> aiFoodLines(FoodStore food, Set<String> allowed) {
  final foods = [
    for (final f in [...food.mine, ...food.basicFoods])
      if (allowed.contains(f.id)) f,
  ];
  return rawFoodLines(foods, food.likes, tail: aiNutTail);
}

/// Αποφάσεις 20/11 (ο χρήστης: «θέλω να έχει πρόσβαση και να μαθαίνει ό,τι θέλει»): δίπλα σε κάθε υλικό τα κορεσμένα
/// και το αλάτι ανά 100 g (ή 100 ml) από τη βάση, όταν μετράνε (κορεσμένα από [aiTailSat] g, αλάτι από [aiTailSalt] g),
/// ώστε το AI να διαλέγει υλικά που χωράνε στα όρια. Οι αριθμοί του προγράμματος μετριούνται πάντα από την εφαρμογή.
String aiNutTail(Food f) {
  final sat = f.n.has(Nk.satFat) ? f.n.amount(Nk.satFat) : null;
  final salt = f.n.has(Nk.salt) ? f.n.amount(Nk.salt) : null;
  final parts = [
    if (sat != null && sat >= aiTailSat) 'κορ. ${_g1(sat)}',
    if (salt != null && salt >= aiTailSalt) 'αλάτι ${_g1(salt)}',
  ];
  return parts.isEmpty ? '' : ' [${parts.join(' · ')}]';
}

const aiTailSat = 1.0;
const aiTailSalt = 0.25;

// ---------------------------------------------------------------------------
// Ασφάλεια και λογική μιας συνταγής
// ---------------------------------------------------------------------------

final _rawMark = RegExp(r'[(\s,]ωμ[όήάέοηίςύ]*[),\s]');

/// Θέλει μαγείρεμα για να φαγωθεί με ασφάλεια (έλεγχος 19/11, S-1): ωμό κρέας, πουλερικό, ψάρι, θαλασσινό, αυγό, αλλαντικό
/// (μπέικον), ξερά όσπρια, ωμά δημητριακά/ζυμαρικά/πατάτες, αλεύρι, ωμά φασολάκια. Κονσέρβες, καπνιστά, μαρινάτα, βρασμένα
/// δεν πιάνονται (δεν έχουν «ωμ» ούτε μαγειρεμένες μορφές).
/// Έλεγχος 20/11 (K2-S-07): και τα ωμά κατεψυγμένα λαχανικά (αρακάς· EFSA 2020, Listeria: «cooked properly after
/// defrosting»), η ωμή ζύμη (φύλλο κρούστας) και το λουκάνικο (χωρίς «ωμό» στο όνομα της πηγής).
const _alwaysCookIds = {'C30780'};

bool aiNeedsCooking(Food f) {
  if (f.isCooked) return false;
  if (_alwaysCookIds.contains(f.id)) return true;
  final n = ' ${f.name.toLowerCase()} ';
  final raw = f.isRawWithCooked || _rawMark.hasMatch(n);
  return switch (f.cat) {
    'Κρέας' || 'Πουλερικά' || 'Ψάρια' || 'Θαλασσινά' || 'Αυγά' || 'Αλλαντικά' => raw,
    'Όσπρια' => raw || n.contains('ξερ'),
    'Δημητριακά' || 'Ζυμαρικά' || 'Πατάτες' => raw || n.contains('ξηρ') || n.contains('αλεύρι'),
    'Λαχανικά' => raw && (n.contains('φασολάκια') || n.contains('κατεψυγμ')),
    'Ψωμί' => raw,
    _ => false,
  };
}

/// Τα προβλήματα μιας συνταγής του AI (κείμενο για το AI· κενό = εντάξει). Μετρά στη μερίδα της συνταγής: όλο το πιάτο,
/// 1 μερίδα ή 1 από τις μερίδες της κατσαρόλας.
List<String> aiDishProblems(FoodStore food, Dish d) {
  final p = planInfoOf(d);
  final out = <String>[];
  if (d.kind == DishKind.pot && (recipeOf(d)?.servings ?? 0) < 3) {
    out.add('Κατσαρόλα: γράψε στο "servings" πόσες μερίδες βγάζει για όλο το σπίτι (2–3 άτομα) μαζί με ένα ταπεράκι, '
        'τουλάχιστον 3.');
  }
  final nat = naturalRaw(d);
  final parts = nat == null ? null : food.previewDish(nat);
  if (parts == null || parts.isEmpty) return [...out, 'Δεν βγαίνουν θερμίδες από τα υλικά.'];
  final t = Totals(parts);
  final snackOnly = p != null && p.meals.isNotEmpty && p.meals.every((m) => m == Meal.snack);
  final (lo, hi) = snackOnly ? (50.0, 700.0) : (150.0, 1500.0);
  if (t.kcal < lo || t.kcal > hi) {
    out.add('Η μερίδα της συνταγής έχει ${t.kcal.round()} kcal· για ${snackOnly ? 'σνακ' : 'γεύμα'} θέλει '
        '${lo.round()}–${hi.round()} (έλεγξε τα γραμμάρια και το "servings").');
  }
  if (p?.cook == CookWay.none) {
    final raw = {for (final e in parts) if (aiNeedsCooking(e.food)) e.food.name};
    if (raw.isNotEmpty) {
      out.add('Χωρίς μαγείρεμα ("cook": "none") αλλά έχει ${raw.join(', ')}, που θέλουν μαγείρεμα για να φαγωθούν με '
          'ασφάλεια. Χωρίς μαγείρεμα μόνο έτοιμα για φάγωμα (γιαούρτι, τυρί, κονσέρβα, ψωμί, ωμά λαχανικά, φρούτα, ξηροί '
          'καρποί)· αλλιώς "cook": "home" με βήματα.');
    }
  }
  double grams(bool Function(Food f) w) => parts.where((e) => w(e.food)).fold(0.0, (a, e) => a + e.grams);
  final added = grams((f) => f.id == _saltId);
  if (added > aiMaxAddedSaltG + 1e-9) {
    out.add('Πρόσθετο αλάτι ${_g1(added)} g τη μερίδα: το πολύ 1 g (μόνο όσο μένει στο φαγητό, όχι στο νερό που βράζει).');
  }
  if (t.salt > aiMaxSaltG + 1e-9) {
    out.add('Αλάτι ${_g1(t.salt)} g στη μερίδα μαζί με τα υλικά (${_topSources(parts, Nk.salt)}): το πολύ '
        '${_g1(aiMaxSaltG)} g. Λιγότερο αλάτι ή αλμυρά (τυρί, αλλαντικά, ελιές).');
  }
  final fats = grams((f) => f.cat == 'Λιπαρά' && !f.name.startsWith('Ελιές'));
  if (fats > aiMaxFatsG + 1e-9) {
    out.add('Λάδι/λιπαρά ${fats.round()} g τη μερίδα: το πολύ ${aiMaxFatsG.round()} g. Γράψε μόνο το λάδι που τρώγεται '
        '(όχι το λάδι του τηγανιού), χωρίς βαθύ τηγάνισμα.');
  }
  final sweet = grams((f) => f.cat == 'Γλυκά');
  if (sweet > aiMaxSweetG + 1e-9) out.add('Ζάχαρη/μέλι/γλυκά ${sweet.round()} g τη μερίδα: το πολύ ${aiMaxSweetG.round()} g.');
  final processed = grams((f) => f.cat == 'Αλλαντικά');
  if (processed > aiMaxProcessedG + 1e-9) {
    out.add('Αλλαντικά ${processed.round()} g τη μερίδα: το πολύ ${aiMaxProcessedG.round()} g.');
  }
  for (final e in parts) {
    if (e.food.cat == 'Καρυκεύματα' && e.food.id != _saltId && e.grams > aiMaxSpiceG + 1e-9) {
      out.add('«${e.food.name}» ${e.grams.round()} g τη μερίδα: τα ξερά μπαχαρικά το πολύ ${aiMaxSpiceG.round()} g.');
    }
    if (_neverIds.contains(e.food.id)) out.add('Το «${e.food.name}» δεν μπαίνει (μετρά όλο το αλάτι πριν το ξαλμύρισμα).');
  }
  final alcohol = grams((f) => f.n.amount(Nk.alcohol) > 0);
  if (alcohol > 0 && (p?.cook != CookWay.home || alcohol > aiMaxAlcoholG + 1e-9)) {
    out.add('Κρασί/ποτό μόνο για μαγείρεμα ("cook": "home") και το πολύ ${aiMaxAlcoholG.round()} ml τη μερίδα· όχι ως '
        'ρόφημα.');
  }
  return out;
}

String _g1(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
String _n(double v) => v.round().toString();

/// Οι 3 μεγαλύτερες πηγές ενός θρεπτικού (π.χ. «φέτα 2,3 g, αλάτι 1,0 g»).
String _topSources(List<LogEntry> parts, String k, {int n = 3}) {
  final by = <String, double>{};
  for (final e in parts) {
    by[e.food.name] = (by[e.food.name] ?? 0) + e.total(k);
  }
  final top = by.entries.where((e) => e.value > 0.05).toList()..sort((a, b) => b.value.compareTo(a.value));
  return [for (final e in top.take(n)) '${_shortName(e.key)} ${_g1(e.value)} g'].join(', ');
}

String _shortName(String name) {
  final i = name.indexOf(' (');
  return (i > 0 ? name.substring(0, i) : name).toLowerCase();
}

/// Μία γραμμή για ένα φαγητό της βιβλιοθήκης: η μερίδα της συνταγής από τη βάση.
String aiDishLine(FoodStore food, Dish d) {
  final p = planInfoOf(d)!;
  final raw = naturalRaw(d);
  final t = raw == null ? null : itemsTotals(food, raw);
  final r = recipeOf(d);
  final kind = switch (d.kind) {
    DishKind.plate => 'πιάτο',
    DishKind.portions => '${d.servings} μερίδες',
    DishKind.pot => 'κατσαρόλα${r?.servings == null ? '' : ' ~${r!.servings} μερίδες'}',
  };
  return [
    p.key,
    d.name,
    kind,
    p.cook == CookWay.none ? 'χωρίς μαγείρεμα' : (r?.minutes == null ? 'μαγείρεμα' : 'μαγείρεμα ${r!.minutes}′'),
    p.meals.isEmpty ? 'όλα τα γεύματα' : p.meals.map((m) => m.name).join('/'),
    if (p.office) 'γραφείο',
    if (_hasRice(food, d)) 'με ρύζι',
    if (p.tags.isNotEmpty) p.tags.join(', '),
    if (dishRating(d) > 0) 'ΜΟΥ ΑΡΕΣΕ',
    if (t != null)
      'μερίδα ${_n(t.kcal)} kcal, πρωτεΐνη ${_n(t.protein)} g, κορεσμένα ${_g1(t.satFat)} g, αλάτι ${_g1(t.salt)} g, '
          'ίνες ${_n(t.fiber)} g',
  ].join(' · ');
}

bool _hasRice(FoodStore food, Dish d) => itemsHaveRice(food, d.items);

/// Οι μερίδες ανά γεύμα σε στρογγυλά νούμερα (μόνο αυτό το νούμερο των στόχων πάει στο AI).
Map<Meal, int> aiMealKcal(int dayKcal, List<Meal> meals) {
  final ordered = [for (final m in Meal.values) if (meals.contains(m)) m];
  final sum = ordered.fold(0.0, (a, m) => a + mealShare[m]!);
  return {for (final m in ordered) m: ((dayKcal * mealShare[m]! / sum) / 50).round() * 50};
}

/// Το σταθερό κομμάτι κάθε ερώτησης (κρατιέται στην cache του API, ώστε οι συνταγές να έρχονται γρηγορότερα).
///
/// [limits] (αποφάσεις 20/11): τα όρια της μέρας του χρήστη (κορεσμένα, αλάτι, ίνες, πρωτεΐνη), ώστε το AI να τα σέβεται
/// από την αρχή. Ποτέ δεδομένα υγείας (ύπνος, παλμοί, πίεση, σάκχαρο, Oura): μόνο οι στόχοι διατροφής.
String aiSystem(FoodStore food, Set<String> allowed, Kitchen kitchen, {AiTargets? limits}) {
  final devices = [
    for (final d in kitchenDevices)
      if (kitchen.has(d.$1)) '${d.$2} (${d.$3})',
  ];
  final b = StringBuffer()
    ..writeln('Είσαι ο μάγειρας και διατροφολόγος της προσωπικής εφαρμογής «Υγεία & Φόρμα». Γράφεις στα ελληνικά.')
    ..writeln()
    ..writeln('ΑΠΑΡΑΒΑΤΟΙ ΚΑΝΟΝΕΣ:')
    ..writeln('1. Υλικά ΜΟΝΟ από τη λίστα «ΕΠΙΤΡΕΠΟΜΕΝΑ ΥΛΙΚΑ», με το id ΚΑΙ το όνομα ακριβώς όπως είναι. Τίποτα άλλο, ούτε '
        '«λίγο». Αν ένα φαγητό θέλει κάτι που λείπει, διάλεξε άλλο φαγητό. Το νερό δεν γράφεται ως υλικό.')
    ..writeln('2. Ποσότητες σε γραμμάρια (ml όπου η λίστα γράφει «ml»), ΩΜΑ, όπως ζυγίζονται πριν το μαγείρεμα. Λάδι, αλάτι '
        'και μπαχαρικά είναι υλικά σε γραμμάρια· στα βήματα γράψε και το κουτάλι (½ κουταλάκι αλάτι ≈ 3 g).')
    ..writeln('3. ΜΗ γράψεις θερμίδες ή θρεπτικά: τα μετρά η εφαρμογή από τη βάση της. Η εφαρμογή βάζει και τις μερίδες.')
    ..writeln('4. Απαντάς ΜΟΝΟ με ένα μπλοκ JSON στη μορφή που ζητείται, χωρίς άλλο κείμενο.')
    ..writeln()
    ..writeln('ΑΣΦΑΛΕΙΑ ΤΡΟΦΙΜΩΝ:')
    ..writeln('- ΠΟΤΕ ωμό ή μισοψημένο κρέας, πουλερικό, ψάρι, θαλασσινό ή αυγό. Φαγητό «χωρίς μαγείρεμα» μόνο με έτοιμα '
        'για φάγωμα (γιαούρτι, τυρί, κονσέρβα, ψωμί, ωμά λαχανικά, φρούτα, ξηροί καρποί).')
    // K2-R-12: το «χωρίς ροζ» ισχύει για κρέας και πουλερικά (FSS)· ο ψημένος σολομός ΕΙΝΑΙ ροζ. Ψάρι (FDA: 63 °C, ή
    // ώσπου η σάρκα να γίνει αδιαφανής και να χωρίζει εύκολα με το πιρούνι).
    ..writeln('- Κοτόπουλο, κιμάς, χοιρινό: ψημένα ως το κέντρο (75 °C, ή χωρίς ροζ και με διάφανα ζουμιά). Ψάρι: ώσπου '
        'να γίνει αδιαφανές και να χωρίζει εύκολα με το πιρούνι.')
    ..writeln('- Ξερά φασόλια, γίγαντες, ρεβίθια: μούλιασμα, πέταμα του νερού, και σε φρέσκο νερό δυνατό βράσιμο τουλάχιστον '
        '10 λεπτά πριν το σιγανό· ποτέ μισοβρασμένα. Φακές και φάβα δεν θέλουν μούλιασμα.')
    ..writeln('- Περισσεύματα: κρύωμα μέσα σε 1–2 ώρες, ψυγείο, φαγητό ως 2 μέρες (με ρύζι: ως την επόμενη μέρα), ένα '
        'ξαναζέσταμα ως να αχνίζει παντού.')
    ..writeln()
    ..writeln('ΥΓΙΕΙΝΗ ΣΥΝΤΑΓΗ (ανά μερίδα):')
    ..writeln('- Κύριο γεύμα με λαχανικά τουλάχιστον 150 g και καλή πηγή πρωτεΐνης.')
    ..writeln('- Λάδι 10–15 g (λαδερά ως 20 g), μόνο όσο τρώγεται· όχι βαθύ τηγάνισμα.')
    ..writeln('- Πρόσθετο αλάτι ως 1 g (νοστιμιά με λεμόνι, ξύδι, σκόρδο, μυρωδικά, μπαχαρικά)· τυρί ως '
        '${limits == null ? '30 g' : '20 g και πάντα μέσα στο όριο κορεσμένων του γεύματος (με λάδι στο ίδιο πιάτο: λιγότερο ή άπαχο τυρί)'}· '
        'όχι αλλαντικά.')
    ..writeln('- Ψωμί, ζυμαρικά και ρύζι ολικής όπου υπάρχουν στη λίστα· ζάχαρη ή μέλι ως 10 g· κρασί μόνο στο μαγείρεμα.')
    ..writeln('- Ψάρι: κυρίως σαρδέλα, γαύρος, σκουμπρί, σολομός, τσιπούρα, λαβράκι, μπακαλιάρος, γαρίδες, καλαμάρι, με '
        'εναλλαγή ειδών. Λιπαρό ψάρι (σολομός, σαρδέλα, σκουμπρί, ρέγγα, γαύρος) ως 4 φορές την εβδομάδα. Ξιφίας το πολύ μία '
        'φορά τον μήνα· τόνος λευκός (albacore) το πολύ μία φορά την εβδομάδα.')
    ..writeln();
  if (limits != null) {
    b
      ..writeln('ΤΑ ΟΡΙΑ ΤΗΣ ΜΕΡΑΣ ΜΟΥ (τα μετρά η εφαρμογή από τη βάση· διάλεξε υλικά και ποσότητες ώστε να χωράνε):')
      ..writeln('- Κορεσμένα λιπαρά έως ${_g1(limits.satMax)} g τη μέρα, όλα τα γεύματα μαζί (ένα κύριο γεύμα περίπου έως '
          '${_g1(limits.satMax / 3)} g). Μετρούν και τα κορεσμένα του ελαιόλαδου, του λιπαρού ψαριού, του τυριού και του '
          'γιαουρτιού: προτίμησε άπαχα γαλακτοκομικά και λίγο λάδι.')
      ..writeln('- Αλάτι κάτω από ${_g1(limits.salt)} g τη μέρα, ΜΑΖΙ με το αλάτι που έχουν ήδη τα τρόφιμα (τυρί, cottage, '
          'ψωμί, κονσέρβες, παστά, καπνιστά, μαρινάτα).')
      ..writeln('- Φυτικές ίνες τουλάχιστον ${limits.fiber} g τη μέρα (όσπρια, λαχανικά, φρούτα, ολικής άλεσης, πίτουρο).')
      ..writeln('- Πρωτεΐνη περίπου ${limits.protein} g τη μέρα, μοιρασμένη στα κύρια γεύματα.')
      ..writeln('- Στη λίστα υλικών, «[κορ. … · αλάτι …]» = γραμμάρια κορεσμένων και αλατιού ανά 100 g (ή 100 ml), από τη '
          'βάση. Όπου δεν γράφει, είναι λίγα.')
      ..writeln();
  }
  b
    ..writeln('ΚΟΥΖΙΝΑ: ${devices.isEmpty ? 'μάτια κουζίνας, φούρνος, κατσαρόλες, τηγάνια' : devices.join(', ')}'
        '${kitchen.cookware.isEmpty ? '' : '. Σκεύη: ${kitchen.cookware.map((c) => c.size == null ? c.kind : '${c.kind} ${c.size}').join(', ')}'}');
  if (food.likes.note.trim().isNotEmpty) b.writeln('ΣΗΜΕΙΩΣΕΙΣ ΤΟΥ ΧΡΗΣΤΗ: ${food.likes.note.trim()}');
  b
    ..writeln()
    ..writeln('ΕΠΙΤΡΕΠΟΜΕΝΑ ΥΛΙΚΑ (id όνομα), ωμά, ανά κατηγορία:');
  for (final l in aiFoodLines(food, allowed)) {
    b.writeln(l);
  }
  return b.toString();
}

// ---------------------------------------------------------------------------
// Το σχέδιο της εβδομάδας (βήμα 1)
// ---------------------------------------------------------------------------

/// Ένα νέο φαγητό που ζήτησε το AI στο σχέδιο (η συνταγή γράφεται μετά, χωριστά).
class AiNewDish {
  const AiNewDish({required this.key, required this.name, required this.idea, required this.json});
  final String key;
  final String name;
  final String idea;

  /// Ό,τι έγραψε για το φαγητό (είδος, γεύματα, γραφείο, ετικέτες, λεπτά), για να το ξαναδώσουμε στη συνταγή.
  final Map<String, dynamic> json;

  DishKind get kind => dishKindOf(json['type']) ?? DishKind.pot;
  CookWay get cook => cookWayOf(json['cook'] ?? 'home') ?? CookWay.home;
  bool get office => json['office'] == true;
  List<Meal> get meals => [for (final m in (json['meals'] is List ? json['meals'] as List : const [])) if (mealOfName(m) case final mm?) mm];
  // Έλεγχος 20/11 (K2-C-08): «minutes»: 1e999 γίνεται Infinity και το round() πετούσε εξαίρεση (χανόταν όλη η προσπάθεια).
  int? get minutes {
    final m = json['minutes'];
    return m is num && m.isFinite && m > 0 && m <= maxRecipeMinutes ? m.round() : null;
  }
}

class AiPlan {
  const AiPlan(this.newDishes, this.days);
  final List<AiNewDish> newDishes;

  /// Για κάθε μέρα: (γεύμα, key).
  final List<List<(Meal, String)>> days;
}

class AiPlanParse {
  const AiPlanParse(this.plan, this.errors);
  final AiPlan? plan;
  final List<String> errors;
}

final _keyRe = RegExp(r'^[a-z0-9][a-z0-9_-]*$');

/// Τι ζητήθηκε: [days] μέρες από τη [from], γεύματα [meals]. [kept]: θέσεις που μένουν (κλειδωμένες, ήδη γραμμένες ή
/// μέρες πριν από σήμερα): (μέρα, γεύμα) → id φαγητού.
typedef AiWeekAsk = ({DateTime from, int days, List<Meal> meals, Map<(int, Meal), String> kept});

/// Τα στοιχεία ενός φαγητού για τους κανόνες του σχεδίου (βιβλιοθήκη ή δηλωμένο νέο).
typedef _Info = ({String name, DishKind kind, CookWay cook, bool office, List<Meal> meals, bool snack, int? minutes});

_Info _infoOf(Dish d) {
  final p = planInfoOf(d);
  return (
    name: d.name,
    kind: d.kind,
    cook: p?.cook ?? CookWay.home,
    office: p?.office ?? false,
    meals: p?.meals ?? const [],
    snack: p != null && p.meals.isNotEmpty && p.meals.every((m) => m == Meal.snack),
    minutes: recipeOf(d)?.minutes,
  );
}

_Info _infoNew(AiNewDish n) => (
      name: n.name,
      kind: n.kind,
      cook: n.cook,
      office: n.office,
      meals: n.meals,
      snack: n.meals.isNotEmpty && n.meals.every((m) => m == Meal.snack),
      minutes: n.minutes,
    );

/// Διαβάζει το σχέδιο. [library]: τα φαγητά που επιτρέπεται να διαλέξει (key → φαγητό). [allKeys]: όλα τα κλειδιά της
/// βιβλιοθήκης (νέο φαγητό δεν παίρνει κλειδί που υπάρχει). [extra]: νέα φαγητά προηγούμενου σχεδίου (στη διόρθωση): αν
/// ξαναγραφτούν στο "new", αγνοούνται (είναι τα ίδια). [keptKeys]: το key των κρατημένων θέσεων (για τους κανόνες).
AiPlanParse parseAiPlan(
  String text,
  AiWeekAsk ask,
  Map<String, Dish> library,
  Set<String> allKeys, {
  Map<String, Dish> extra = const {},
  Map<(int, Meal), String> keptKeys = const {},
}) {
  final j = jsonOfKind(text, aiWeekKind);
  if (j == null) return const AiPlanParse(null, ['Η απάντηση δεν είναι στη μορφή "kind": "$aiWeekKind".']);
  final errors = <String>[];
  final news = <AiNewDish>[];
  final newKeys = <String, AiNewDish>{};
  final rawNew = j['new'];
  for (final x in (rawNew is List ? rawNew : const [])) {
    if (x is! Map<String, dynamic>) {
      errors.add('Ένα νέο φαγητό δεν διαβάζεται.');
      continue;
    }
    final key = x['key'] is String ? (x['key'] as String).trim() : '';
    final name = x['name'] is String ? (x['name'] as String).trim() : '';
    final idea = x['idea'] is String ? (x['idea'] as String).trim() : '';
    if (extra.containsKey(key)) continue; // το ίδιο νέο φαγητό του πρώτου σχεδίου (διόρθωση, L-8)
    if (key.isEmpty || key.length > maxLibraryKeyLength || !_keyRe.hasMatch(key) || !key.startsWith(aiKeyPrefix)) {
      errors.add('Νέο φαγητό «$name»: το "key" ξεκινά με «$aiKeyPrefix» και έχει μόνο λατινικά μικρά, αριθμούς και «-».');
      continue;
    }
    if (allKeys.contains(key) || newKeys.containsKey(key)) {
      errors.add(allKeys.contains(key)
          ? 'Νέο φαγητό «$name»: το key «$key» είναι ήδη φαγητό της ΒΙΒΛΙΟΘΗΚΗΣ. Αν εννοείς αυτό, βγάλ’ το από το "new" '
              'και βάλ’ το μόνο στις μέρες· αλλιώς δώσε άλλο key.'
          : 'Νέο φαγητό «$name»: το key «$key» γράφτηκε δύο φορές στο "new".');
      continue;
    }
    if (name.isEmpty) errors.add('Νέο φαγητό «$key»: λείπει το "name".');
    final cook = cookWayOf(x['cook'] ?? 'home');
    if (cook == null || cook == CookWay.out) errors.add('Νέο φαγητό «$name»: "cook" μόνο "home" ή "none".');
    if (dishKindOf(x['type']) == null) errors.add('Νέο φαγητό «$name»: "type" μόνο "plate", "portions" ή "pot".');
    final n = AiNewDish(key: key, name: name, idea: idea, json: x);
    if (n.meals.isEmpty) errors.add('Νέο φαγητό «$name»: γράψε "meals".');
    newKeys[key] = n;
    news.add(n);
  }
  final days = j['days'];
  if (days is! List || days.length != ask.days) {
    errors.add('Θέλω ακριβώς ${ask.days} μέρες στο "days".');
    return AiPlanParse(null, errors);
  }
  final out = <List<(Meal, String)>>[];
  final start = DateTime(ask.from.year, ask.from.month, ask.from.day);
  _Info? infoOfKey(String k) =>
      library[k] != null ? _infoOf(library[k]!) : extra[k] != null ? _infoOf(extra[k]!) : newKeys[k] != null ? _infoNew(newKeys[k]!) : null;
  for (var i = 0; i < days.length; i++) {
    final date = DateTime(start.year, start.month, start.day + i);
    final label = _day(date);
    final d = days[i];
    final list = d is Map ? d['meals'] : d;
    final slots = <(Meal, String)>[];
    if (list is! List) {
      errors.add('$label: δεν διαβάζεται.');
      out.add(slots);
      continue;
    }
    final seen = <Meal>{};
    for (final s in list) {
      final meal = s is Map ? mealOfName(s['meal']) : null;
      final key = s is Map && s['key'] is String ? (s['key'] as String).trim() : '';
      if (meal == null || !ask.meals.contains(meal)) {
        errors.add('$label: γεύμα που δεν ζητήθηκε (${s is Map ? s['meal'] : '?'}).');
        continue;
      }
      if (!seen.add(meal)) {
        errors.add('$label: το ${mealLabel(meal).toLowerCase()} υπάρχει δύο φορές.');
        continue;
      }
      if (ask.kept.containsKey((i, meal))) continue; // μένει όπως ήταν
      final info = infoOfKey(key);
      if (info == null) {
        errors.add('$label, ${mealLabel(meal).toLowerCase()}: δεν υπάρχει φαγητό με key «$key» (ούτε στη βιβλιοθήκη ούτε στα νέα).');
        continue;
      }
      if (info.meals.isNotEmpty && !info.meals.contains(meal)) {
        errors.add('$label: το «${info.name}» δεν είναι για ${mealLabel(meal).toLowerCase()}.');
      }
      if (meal == Meal.lunch && officeWeekdays.contains(date.weekday) && !info.office) {
        errors.add('$label: μεσημέρι στο γραφείο, θέλει φαγητό με "office": true (όχι «${info.name}»).');
      }
      slots.add((meal, key));
    }
    for (final m in ask.meals) {
      if (!seen.contains(m) && !ask.kept.containsKey((i, m))) errors.add('$label: λείπει το ${mealLabel(m).toLowerCase()}.');
    }
    out.add(slots);
  }
  // Κανόνες επανάληψης και κατσαρόλας (μαζί με τις κρατημένες θέσεις).
  final placements = <String, List<(int, Meal)>>{};
  for (final e in keptKeys.entries) {
    (placements[e.value] ??= []).add(e.key);
  }
  for (var i = 0; i < out.length; i++) {
    for (final (m, k) in out[i]) {
      (placements[k] ??= []).add((i, m));
    }
  }
  for (final MapEntry(key: k, value: ps) in placements.entries) {
    final info = infoOfKey(k);
    if (info == null || info.snack) continue; // τα σνακ επαναλαμβάνονται
    ps.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : _mealOrder(a.$2).compareTo(_mealOrder(b.$2)));
    if (ps.length > 2) {
      errors.add('«${info.name}» μπαίνει ${ps.length} φορές: το πολύ 2 την εβδομάδα.');
      continue;
    }
    if (ps.length == 2) {
      final gap = ps[1].$1 - ps[0].$1;
      if (info.kind == DishKind.pot) {
        if (gap > aiPotMaxGap) {
          errors.add('«${info.name}» (κατσαρόλα): η 2η φορά το πολύ $aiPotMaxGap μέρες μετά το μαγείρεμα (περισσεύματα ως 48 ώρες).');
        }
      } else if (gap < 2) {
        errors.add('«${info.name}»: όχι ίδια ή συνεχόμενη μέρα (ξανά το νωρίτερο 2 μέρες μετά).');
      }
    }
    // Κατσαρόλα που μαγειρεύεται ώστε να φαγωθεί πρώτη φορά σε μεσημέρι γραφείου: πρέπει να υπάρχει ήδη (βράδυ πριν).
    final first = ps.first;
    final firstDate = DateTime(start.year, start.month, start.day + first.$1);
    if (info.kind == DishKind.pot && info.cook == CookWay.home && first.$2 == Meal.lunch &&
        officeWeekdays.contains(firstDate.weekday) && !keptKeys.containsKey(first)) {
      errors.add('«${info.name}» (κατσαρόλα) μπαίνει πρώτη φορά στο γραφείο (${_day(firstDate)}): βάλ’ τη πρώτα στο βράδυ '
          'της προηγούμενης μέρας, ώστε το ταπεράκι να είναι περίσσευμα.');
    }
  }
  if (news.length > aiMaxNewDishes) errors.add('Πολλά νέα φαγητά (${news.length}): το πολύ $aiMaxNewDishes.');
  // Νέο φαγητό που δεν μπήκε πουθενά: δεν το φτιάχνουμε.
  final used = {for (final d in out) for (final s in d) s.$2};
  news.removeWhere((n) => !used.contains(n.key));
  return AiPlanParse(errors.isEmpty ? AiPlan(news, out) : null, errors);
}

int _mealOrder(Meal m) => switch (m) {
      Meal.breakfast => 0,
      Meal.lunch => 1,
      Meal.snack => 2,
      Meal.dinner => 3,
    };

const _wd = ['Δευτέρα', 'Τρίτη', 'Τετάρτη', 'Πέμπτη', 'Παρασκευή', 'Σάββατο', 'Κυριακή'];
String _day(DateTime d) => '${_wd[d.weekday - 1]} ${d.day}/${d.month}';

/// Η ερώτηση του σχεδίου. Στόχοι μόνο ως θερμίδες ανά γεύμα σε στρογγυλά νούμερα (X-3).
String aiPlanPrompt({
  required FoodStore food,
  required AiWeekAsk ask,
  required List<Dish> library,
  required int dayKcal,
  int? legumesWeek,
  int? fishWeek,
}) {
  final start = DateTime(ask.from.year, ask.from.month, ask.from.day);
  final byId = {for (final d in food.dishes) d.id: d};
  final mk = aiMealKcal(dayKcal, ask.meals);
  final legumes = legumesWeek ?? 4, fish = fishWeek ?? 2;
  final b = StringBuffer()
    ..writeln('Φτιάξε το πρόγραμμα φαγητού μου για ${ask.days} μέρες από τη ${dateKey(start)}, με γεύματα: '
        '${ask.meals.map((m) => '${m.name} (${mealLabel(m).toLowerCase()})').join(', ')}.')
    ..writeln()
    ..writeln('ΣΤΟΧΟΣ: απώλεια λίπους. Μερίδα ανά γεύμα περίπου: '
        '${[for (final e in mk.entries) '${mealLabel(e.key).toLowerCase()} ~${e.value} kcal'].join(', ')} (τις μερίδες τις '
        'βάζει η εφαρμογή από 0,6 ως 1,6 φορές τη μερίδα της συνταγής· διάλεξε φαγητά που ταιριάζουν). Κάθε κύριο γεύμα '
        'με πολλή πρωτεΐνη· λίγα κορεσμένα· πολλές ίνες και λαχανικά (τουλάχιστον 400 g φρούτα και λαχανικά τη μέρα)· λίγο '
        'αλάτι και ζάχαρη.')
    ..writeln()
    ..writeln('ΚΑΝΟΝΕΣ ΠΡΟΓΡΑΜΜΑΤΟΣ:')
    ..writeln('- Τρίτη, Τετάρτη, Πέμπτη μεσημέρι είμαι στο γραφείο (ψυγείο και μικροκύματα): μόνο φαγητό με "office": true. '
        'Κατσαρόλα στο γραφείο μόνο ως περίσσευμα (μαγειρεμένη το βράδυ της προηγούμενης μέρας)· αλλιώς κάτι χωρίς μαγείρεμα.')
    ..writeln('- Καθημερινές ως 30 λεπτά μαγείρεμα, Σαββατοκύριακο ως 60.')
    ..writeln('- Κατσαρόλα ("pot") για όλο το σπίτι: 2–3 άτομα σε ένα γεύμα, ΣΥΝ τις δύο δικές μου μερίδες (είναι '
        'μεγάλες) και ένα ταπεράκι· στο "idea" γράψε για πόσες μερίδες ενήλικα, τουλάχιστον 6. Μαγειρεύεται μία φορά '
        'και ξαναμπαίνει το πολύ μία φορά, ως 2 μέρες μετά (με ρύζι: μόνο την επόμενη μέρα), με το ίδιο key. Τα άλλα φαγητά (όχι σνακ) το πολύ 2 '
        'φορές την εβδομάδα και όχι σε ίδια ή συνεχόμενη μέρα. Τα σνακ μπορούν να επαναλαμβάνονται.')
    ..writeln('- Ψώνια τη Δευτέρα: το φρέσκο ψάρι νωρίς στην εβδομάδα, τα υπόλοιπα κατεψυγμένα ή κονσέρβα.')
    ..writeln('- Την εβδομάδα: ${[
      if (legumes > 0) 'όσπρια τουλάχιστον $legumes μέρες (τουλάχιστον 40 g ξερά ή 100 g βρασμένα στη μερίδα)',
      if (fish > 0)
        'ψάρι τουλάχιστον $fish μέρες (τουλάχιστον 100 g ωμό στη μερίδα${fish >= 2 ? ', από αυτά ${fish >= 4 ? 2 : 1} ως ${math.min(4, fish)} λιπαρά, το πολύ ${_n(aiOilyFishWeekG)} g ωμό λιπαρό ψάρι την εβδομάδα' : ', κατά προτίμηση λιπαρό'})',
      'κόκκινο κρέας το πολύ 1',
      'αλλαντικά το πολύ 1',
      'κοτόπουλο ως 5',
    ].join(' · ')}.')
    ..writeln('- Προτίμησε φαγητά της ΒΙΒΛΙΟΘΗΚΗΣ (ειδικά όσα γράφουν «ΜΟΥ ΑΡΕΣΕ»). Νέα φαγητά μόνο όσα χρειάζονται για ποικιλία '
        'ή για τους κανόνες, το πολύ $aiMaxNewDishes, και ΜΟΝΟ με επιτρεπόμενα υλικά.');
  if (ask.kept.isNotEmpty) {
    b.writeln('- ΜΕΝΟΥΝ ΙΔΙΑ (μην τα γράψεις): ${[
      for (final e in ask.kept.entries)
        '${_day(DateTime(start.year, start.month, start.day + e.key.$1))} ${mealLabel(e.key.$2).toLowerCase()}: '
            '${byId[e.value]?.name ?? '—'}',
    ].join('; ')}.');
  }
  final disliked = [for (final d in food.dishes) if (dishRating(d) < 0) d.name];
  if (disliked.isNotEmpty) b.writeln('- ΔΕΝ ΜΟΥ ΑΡΕΣΑΝ (ποτέ ξανά, ούτε κάτι παρόμοιο με άλλο όνομα): ${disliked.join('; ')}.');
  b
    ..writeln()
    ..writeln('ΒΙΒΛΙΟΘΗΚΗ (key · όνομα · είδος · μαγείρεμα · γεύματα · γραφείο · ετικέτες · μερίδα της συνταγής):');
  if (library.isEmpty) b.writeln('(άδεια: όλα τα φαγητά θα είναι νέα)');
  for (final d in library) {
    b.writeln(aiDishLine(food, d));
  }
  b
    ..writeln()
    ..writeln('Απάντησε με ΕΝΑ μπλοκ JSON σε αυτή ακριβώς τη μορφή («days»: ${ask.days} λίστες, μία για κάθε μέρα με τη σειρά):')
    ..writeln('```json')
    ..writeln('{')
    ..writeln('  "kind": "$aiWeekKind",')
    ..writeln('  "new": [')
    ..writeln('    {"key": "${aiKeyPrefix}kotopoulo-lemonato", "name": "Κοτόπουλο λεμονάτο με πατάτες και κολοκυθάκια", '
        '"type": "pot", "cook": "home", "minutes": 50, "meals": ["lunch", "dinner"], "office": true, "tags": ["κοτόπουλο"], '
        '"idea": "μπούτι χωρίς πέτσα, πατάτες, κολοκυθάκια, λεμόνι, ελαιόλαδο, ρίγανη· για 6 μερίδες"}')
    ..writeln('  ],')
    ..writeln('  "days": [')
    ..writeln('    [{"meal": "lunch", "key": "…"}, {"meal": "dinner", "key": "${aiKeyPrefix}kotopoulo-lemonato"}],')
    ..writeln('    …')
    ..writeln('  ]')
    ..writeln('}')
    ..writeln('```')
    ..writeln('Το "key" ενός ΝΕΟΥ φαγητού ξεκινά με «$aiKeyPrefix», έχει μόνο λατινικά μικρά, αριθμούς και «-», και είναι '
        'ΔΙΑΦΟΡΕΤΙΚΟ από όσα υπάρχουν στη βιβλιοθήκη. Στο "new" μόνο ΚΑΙΝΟΥΡΓΙΑ φαγητά. Ετικέτες όπου ταιριάζουν: '
        '${standardTags.join(', ')}.');
  return b.toString();
}

// ---------------------------------------------------------------------------
// Μία συνταγή (βήμα 2, και για «Άλλαξε αυτό το γεύμα»)
// ---------------------------------------------------------------------------

/// Η ερώτηση για τη συνταγή ενός νέου φαγητού του σχεδίου.
String aiRecipePrompt(AiNewDish n) {
  final j = n.json;
  return [
    'Γράψε τη συνταγή αυτού του φαγητού του προγράμματός μου, ΜΟΝΟ με τα ΕΠΙΤΡΕΠΟΜΕΝΑ ΥΛΙΚΑ (id και όνομα):',
    jsonEncode({
      'key': n.key,
      'name': n.name,
      for (final k in const ['type', 'cook', 'minutes', 'meals', 'office', 'tags', 'servings'])
        if (j[k] != null) k: j[k],
      'idea': n.idea,
    }),
    '',
    _recipeFormat(n.key, n.name),
  ].join('\n');
}

String _recipeFormat(String key, String name) => [
      'Κράτα ΙΔΙΑ τα "key", "name", "type", "cook", "meals", "office", "tags". "type": "plate" = ένα πιάτο για μένα· '
          '"portions" = ίσες μερίδες (γράψε "servings")· "pot" = κατσαρόλα για όλο το σπίτι: 2–3 άτομα σε ένα γεύμα, ΣΥΝ τις '
          'δύο δικές μου μερίδες (είναι μεγάλες) και ένα ταπεράκι. Γράψε στο "servings" πόσες μερίδες ενήλικα βγάζει, '
          'τουλάχιστον 6, και ποσότητες για όλες (μία μερίδα ενήλικα ≈ ένα κανονικό πιάτο). Με "cook": "home" θέλει "steps" (συσκευή, '
          'φωτιά, λεπτά, πότε μπαίνει κάθε υλικό, αλάτι με κουτάλι). Μην γράψεις "keeps": τη διατήρηση τη γράφει η εφαρμογή.',
      'Απάντησε με ΕΝΑ μπλοκ JSON σε αυτή ακριβώς τη μορφή:',
      '```json',
      '{"kind": "$libraryKind", "dishes": [{"key": "$key", "name": "$name", "type": "pot", "cook": "home", "servings": 6, '
          '"minutes": 40, "meals": ["lunch"], "office": true, "tags": ["…"], '
          '"items": [{"id": "C…", "name": "…", "g": 250}, …], '
          '"steps": [{"text": "…", "device": "…", "heat": "μέτρια", "min": 10}, …], '
          '"tips": ["…"], "why": "…"}]}',
      '```',
    ].join('\n');

/// Η διατήρηση που γράφει η εφαρμογή (όχι το AI) στα φαγητά του AI που ξαναμπαίνουν (έλεγχος 19/11, S-7).
String aiKeepsText(bool rice) => 'Κρύωσέ το μέσα σε 1–2 ώρες και βάλ’ το στο ψυγείο. Φάε το ως '
    '${rice ? 'την επόμενη μέρα (έχει ρύζι)' : '2 μέρες'}. Ζέστανέ το μία φορά, ως να αχνίζει παντού· ανακάτεψε στη μέση '
    'του μικροκυμάτων.';

/// Έλεγχος 20/11 (K2-S-10): αριθμός διατροφής («420 kcal», «30 g πρωτεΐνη», «4 g κορεσμένα») μέσα στο ελεύθερο κείμενο
/// του AI («why», «tips»). Το κείμενο αυτό φαίνεται όπως ήρθε, δίπλα στους αριθμούς της βάσης, και μπορεί να διαφωνεί μαζί
/// τους: ο κανόνας «οι αριθμοί διατροφής ποτέ από το AI» ισχύει και εκεί. Τα βήματα δεν ελέγχονται (έχουν γραμμάρια υλικών).
/// K2-R-04 (ανεξάρτητος έλεγχος): και με το θρεπτικό ΠΡΩΤΟ («Πρωτεΐνη 35 g», «Κορεσμένα μόνο 3,5 g», «Θερμίδες: 450»,
/// «το 30% της πρωτεΐνης»), που είναι το ύφος του ίδιου του prompt· όχι ποσότητες υλικών μέσα σε συμβουλή («πρόσθεσε 1 g
/// αλάτι», «150 g φυτικό επιδόρπιο», «10 g λιπαρό τυρί», «5 g ζάχαρη»), που έκαιγαν μία από τις 2 ξαναδοκιμές.
/// Δοκιμασμένο σε 46 προτάσεις (test/k141_food_test.dart).
const _gl = 'α-ωάέήίόύώϊϋΐΰ';
const _nut = '(?:πρωτε[ΐϊι]ν|κορεσμ|υδατ|[ίι]νες|ινών|σάκχαρ|λιπαρ(?:ά|ών)(?![$_gl])|protein|carb|fat\\b|fiber|fibre)';
const _about = '(?:(?:μόνο|μόλις|περίπου|σχεδόν|γύρω στα|γύρω στις|γύρω|ως|έως|κάτω από|πάνω από)\\s+)?';
final _nutritionNumber = RegExp([
  r'\d[\d.,]*\s*(?:kcal|θερμίδ|χιλιοθερμ|calor)',
  '(?:θερμίδ|calor)[${_gl}a-z]*[\\s:(=~≈]*$_about\\d',
  '\\d[\\d.,]*\\s*(?:g|γρ|γραμμάρι\\S*)\\.?\\s+(?:of\\s+)?$_nut',
  // Στην αρχή λέξης («ίνες 12 g», όχι «κλημεντίνες 150 g»).
  '(?:^|[^$_gl])$_nut[$_gl]*[\\s:(=~≈]*$_about\\d[\\d.,]*\\s*(?:g\\b|γρ|γραμμάρι|%)',
  '\\d[\\d.,]*\\s*%\\s+(?:\\S+\\s+){0,2}$_nut',
  r'(?:αλάτι|αλατιού|νάτριο)\s+(?:κάτω από|πάνω από|μόνο|περίπου|ως)\s+\d[\d.,]*\s*(?:g\b|γρ|mg)',
].join('|'));

/// Για τις δοκιμές (K2-R-04): αν ένα κείμενο του AI έχει αριθμό διατροφής.
bool aiSentenceHasNutritionNumber(String text) => _nutritionNumber.hasMatch(text.toLowerCase());

bool aiTextHasNutritionNumbers(Recipe? r) {
  if (r == null) return false;
  return [if (r.why != null) r.why!, ...r.tips].any((t) => _nutritionNumber.hasMatch(t.toLowerCase()));
}

/// Ένα φαγητό από την απάντηση (μορφή βιβλιοθήκης, ΕΝΑ φαγητό), ελεγμένο με τη βάση, τα επιτρεπόμενα υλικά, την ασφάλεια
/// ([aiDishProblems]) και, για φαγητό του σχεδίου, με ό,τι δηλώθηκε στο σχέδιο ([want]: είδος, μαγείρεμα, γραφείο,
/// γεύματα). Επιστρέφει το φαγητό ή τα προβλήματα (για το AI).
({Dish? dish, List<String> errors}) aiReadDish(
  String text, {
  required FoodStore food,
  required Set<String> allowed,
  required int now,
  required String Function() newId,
  AiNewDish? want,
  Set<Meal> needMeals = const {},
  bool needOffice = false,
}) {
  final p = parseLibrary(text);
  if (p.errors.isNotEmpty) return (dish: null, errors: p.errors);
  if (p.entries.length != 1) return (dish: null, errors: const ['Θέλω ΕΝΑ φαγητό στο "dishes".']);
  final e = p.entries.first;
  if (want != null && e.key != want.key) return (dish: null, errors: ['Το "key" πρέπει να μείνει «${want.key}».']);
  if (want == null && !e.key.startsWith(aiKeyPrefix)) {
    return (dish: null, errors: ['Το "key" νέου φαγητού ξεκινά με «$aiKeyPrefix».']);
  }
  if (e.plan.cook == CookWay.out) return (dish: null, errors: const ['"cook" μόνο "home" ή "none".']);
  if (libraryDishes(food.dishes).any((d) => planInfoOf(d)!.key == e.key)) {
    return (dish: null, errors: ['Το key «${e.key}» υπάρχει ήδη στη βιβλιοθήκη· διάλεξε άλλο.']);
  }
  final imp = planLibraryImport(
    p,
    existing: food.dishes,
    food: (id) => food.itemFood(DishItem(id, id, 1)),
    likes: food.likes,
    now: now,
    newId: newId,
  );
  if (imp.problems.isNotEmpty) return (dish: null, errors: imp.problems.first.errors);
  if (imp.added.length != 1) return (dish: null, errors: const ['Το φαγητό δεν διαβάστηκε.']);
  var d = imp.added.first;
  final info = planInfoOf(d)!;
  final errors = <String>[];
  // Ίδιο με το σχέδιο (έλεγχος 19/11, L-3/I-3): αλλιώς μπαίνει σε θέση που δεν του ταιριάζει.
  if (want != null) {
    if (d.kind != want.kind) errors.add('"type" πρέπει να μείνει "${want.json['type']}" όπως στο σχέδιο.');
    if (info.cook != want.cook) errors.add('"cook" πρέπει να μείνει "${want.cook.name}" όπως στο σχέδιο.');
  }
  if (needOffice && !info.office) errors.add('Μπαίνει μεσημέρι στο γραφείο: θέλει "office": true.');
  for (final m in needMeals) {
    if (!info.fits(m)) errors.add('Μπαίνει στο ${mealLabel(m).toLowerCase()}: το "meals" πρέπει να το έχει ("${m.name}").');
  }
  final bad = [
    for (final i in d.items)
      if (!allowed.contains(_nowId(food, i.id))) i.name,
  ];
  if (bad.isNotEmpty) errors.add('Υλικά εκτός λίστας «ΕΠΙΤΡΕΠΟΜΕΝΑ ΥΛΙΚΑ»: ${bad.join(', ')}. Βγάλ’ τα ή άλλαξε φαγητό.');
  if (errors.isEmpty) errors.addAll(aiDishProblems(food, d));
  if (errors.isEmpty && portionRange(food, d) == null) errors.add('Δεν βγαίνουν θερμίδες από τα υλικά.');
  if (errors.isEmpty && aiTextHasNutritionNumbers(recipeOf(d))) {
    errors.add('Στα "why" και "tips" μη γράφεις θερμίδες ή γραμμάρια θρεπτικών: τα μετρά η εφαρμογή από τη βάση της. Βγάλε '
        'τους αριθμούς.');
  }
  if (errors.isNotEmpty) return (dish: null, errors: errors);
  // Η διατήρηση από την εφαρμογή, όχι από το AI· και σημάδι «από AI».
  final r = recipeOf(d);
  if (r != null && d.kind != DishKind.plate) {
    d = withRecipe(d, Recipe(steps: r.steps, tips: r.tips, minutes: r.minutes, keeps: aiKeepsText(_hasRice(food, d)), why: r.why, servings: r.servings));
  }
  return (dish: withExtra(d, 'by', 'ai'), errors: const []);
}

/// Ρωτά το AI μέχρι να πάρει σωστή απάντηση ([read] → τιμή), ως [aiMaxRetries] ξανά. Κάθε ξανά στέλνει πίσω την απάντησή
/// του και τα προβλήματα (κενή απάντηση: ξανά η ίδια ερώτηση με σημείωση, X-2· άρνηση: μία ακόμα προσπάθεια). Επιστρέφει
/// το αποτέλεσμα ή (null, τελευταία προβλήματα / αποτυχία σύνδεσης). [onAttempt]: η προσπάθεια (1, 2, 3) για την οθόνη.
Future<(T?, List<String>, AiFail?)> aiAskUntilValid<T>(
  AiCall call, {
  required String model,
  required String system,
  required String prompt,
  required (T?, List<String>) Function(String text) read,
  int maxTokens = aiMaxTokensRecipe,
  void Function(int attempt)? onAttempt,
}) async {
  var messages = <(String, String)>[('user', prompt)];
  var last = const <String>[];
  for (var attempt = 0; attempt <= aiMaxRetries; attempt++) {
    onAttempt?.call(attempt + 1);
    final r = await call(AiAsk(model: model, system: system, messages: List.of(messages), maxTokens: maxTokens));
    if (r.fail == AiFail.refused) {
      last = const ['Το AI δεν απάντησε (άρνηση).'];
      messages = [('user', prompt)];
      continue;
    }
    if (r.fail != null) return (null, last, r.fail);
    final text = r.text!;
    if (text.trim().isEmpty) {
      // Κενή απάντηση: δεν ξαναστέλνεται ως μήνυμα (το API δεν το δέχεται)· ξανά η αρχική ερώτηση.
      last = const ['Η απάντηση ήταν κενή.'];
      messages = [('user', '$prompt\n\n(Η προηγούμενη απάντηση ήταν κενή. Απάντησε μόνο με το JSON.)')];
      continue;
    }
    if (r.cut) {
      last = const ['Η απάντηση κόπηκε (πολύ μεγάλη).'];
    } else {
      final (v, errs) = read(text);
      if (v != null) return (v, const <String>[], null);
      last = errs;
    }
    messages = [
      ...messages,
      ('assistant', text),
      ('user', 'Η εφαρμογή δεν δέχτηκε την απάντηση:\n${[for (final e in last) '- $e'].join('\n')}\n'
          'Διόρθωσέ τα και στείλε ξανά ΟΛΟ το JSON, στην ίδια μορφή${r.cut ? ', πιο σύντομα (λιγότερα βήματα και συμβουλές)' : ''}.'),
    ];
  }
  return (null, last, null);
}

/// Τρέχει τις εργασίες με τη σειρά τους στο αποτέλεσμα: η πρώτη μόνη της (για να μπει το σταθερό κομμάτι στην cache του
/// API, X-15), οι υπόλοιπες έως [aiParallel] ταυτόχρονα.
Future<List<R>> aiPool<A, R>(List<A> items, Future<R> Function(A) task, {void Function(int done)? progress}) async {
  if (items.isEmpty) return <R>[];
  final out = List<R?>.filled(items.length, null);
  var done = 0;
  out[0] = await task(items[0]);
  progress?.call(++done);
  var next = 1;
  Future<void> worker() async {
    while (next < items.length) {
      final i = next++;
      out[i] = await task(items[i]);
      progress?.call(++done);
    }
  }

  await Future.wait([for (var w = 0; w < math.min(aiParallel, items.length - 1); w++) worker()]);
  return [for (final r in out) r as R];
}

// ---------------------------------------------------------------------------
// Έλεγχος του προγράμματος από τη βάση
// ---------------------------------------------------------------------------

/// Οι στόχοι για τους ελέγχους (μένουν στο κινητό· δεν πάνε στο AI).
typedef AiTargets = ({int kcal, int protein, double satMax, int fiber, double salt});

/// Ένα πρόβλημα του προγράμματος: [user] για την οθόνη (με αριθμούς), [ai] για τη διόρθωση (χωρίς αριθμούς στόχων).
class AiProblem {
  const AiProblem({this.day, required this.user, required this.ai, this.weight = 1, this.tag});

  /// Έλεγχος 20/11 (K2-C-10): τι είδους πρόβλημα υγείας είναι («sat», «salt», «mercury», «oily»)· null για τα υπόλοιπα.
  /// Με αυτό το [weekHealthNotes] δείχνει τα ίδια και στο πρόγραμμα που φτιάχνεται με κανόνες ή επικολλάται.
  final String? tag;

  /// Η μέρα (θέση στο πρόγραμμα) ή null για όλη την εβδομάδα.
  final int? day;
  final String user;
  final String ai;
  final double weight;
}

double _pct(double a, double b) => b <= 0 ? 0 : ((a - b).abs() / b * 100);

/// Έλεγχος 20/11 (K2-C-10): οι σημειώσεις υγείας για πρόγραμμα που ΔΕΝ πέρασε από το AI («Φτιάξε πρόγραμμα» με κανόνες,
/// επικόλληση): κορεσμένα και αλάτι κάθε μέρας απέναντι στα όριά σου, υδράργυρος και λιπαρό ψάρι της εβδομάδας. Ο ίδιος
/// έλεγχος με του AI ([aiCheckWeek]), από τη βάση. Πριν, αυτά τα προγράμματα έλεγχαν μόνο θερμίδες, πρωτεΐνη, όσπρια και
/// ψάρι, και το όριο κορεσμένων του γιατρού δεν φαινόταν πουθενά πριν φας.
List<String> weekHealthNotes(FoodStore food, WeekPlan w, {required AiTargets t, double? bodyKg}) {
  final meals = w.meals ?? [for (final m in Meal.values) if (w.days.any((d) => d.any((s) => s.meal == m))) m];
  if (meals.isEmpty) return const [];
  final ps = aiCheckWeek(food, w, const [], t: t, meals: meals, checkDays: {for (var i = 0; i < w.days.length; i++) i}, bodyKg: bodyKg);
  return [for (final p in ps) if (p.tag != null) p.user];
}

/// Ελέγχει το πρόγραμμα από τη βάση. [extra]: τα νέα φαγητά (δεν έχουν αποθηκευτεί). [checkDays]: ποιες μέρες ελέγχονται
/// (όσες μπορεί να αλλάξει το AI: από σήμερα, με θέσεις που δεν κρατήθηκαν). [bodyKg]: για τον υδράργυρο (μένει στο κινητό).
List<AiProblem> aiCheckWeek(
  FoodStore food,
  WeekPlan w,
  List<Dish> extra, {
  required AiTargets t,
  required List<Meal> meals,
  required Set<int> checkDays,
  int legumesWeek = 0,
  int fishWeek = 0,
  double? bodyKg,
}) {
  final byId = {for (final d in [...food.dishes, ...extra]) d.id: d};
  final ordered = [for (final m in Meal.values) if (meals.contains(m)) m];
  final shareAll = ordered.fold(0.0, (a, m) => a + mealShare[m]!);
  final out = <AiProblem>[];
  var legumeDays = 0, fishDays = 0, redMeat = 0, processed = 0;
  var mercury = 0.0, oilyFish = 0.0;
  final mercuryBy = <String, double>{};
  var fruitVegShort = 0;
  final weekKcal = <double>[];
  for (var i = 0; i < w.days.length; i++) {
    final label = _day(w.dayAt(i));
    final parts = <LogEntry>[];
    var share = 0.0;
    // K2-R-01: το μερίδιο κάθε γεύματος μετρά ΜΙΑ φορά τη μέρα. Σε επικολλημένο πρόγραμμα με δύο φαγητά στο ίδιο γεύμα
    // το «όριο» κορεσμένων της μέρας γινόταν 20,3 g αντί για 14,3 (αλατιού 7,1 αντί για 5).
    final seenMeals = <Meal>{};
    var unknown = false;
    var legumeG = 0.0, fishG = 0.0;
    for (final s in w.days[i]) {
      if (s.state == SlotState.skip) continue;
      final d = byId[s.dishId];
      final raw = d == null ? null : plannedRaw(food, d, s.kcal);
      final p = raw == null ? null : food.previewDish(raw);
      if (p == null) {
        unknown = true;
        continue;
      }
      parts.addAll(p);
      if (seenMeals.add(s.meal)) share += mealShare[s.meal] ?? 0;
      var meat = 0.0, proc = 0.0;
      for (final e in p) {
        final f = e.food;
        if (isLegumes(f)) legumeG += cookedLegumes(f) ? e.grams / legumesCookedFactor : e.grams; // K2-C-05
        if (isFish(f)) fishG += e.grams;
        if (f.cat == 'Κρέας') meat += e.grams;
        if (f.cat == 'Αλλαντικά') proc += e.grams;
        // K2-R-03: μαγειρεμένη ή παστή μορφή ψαριού σε γραμμάρια ωμού ([fishRawFactor]).
        final rawG = e.grams * fishRawFactor(f, food.byId);
        final hg = rawG * mercuryPpm(f); // K2-S-01: κάθε ψάρι και θαλασσινό, όχι μόνο ξιφίας και τόνος
        if (hg > 0) {
          mercury += hg;
          // K2-R-11: ένα όνομα ανά είδος («μπακαλιάρος», όχι «μπακαλιάρος, μπακαλιάρος» για ωμό και ψητό)· είδος χωρίς
          // τιμή στον πίνακα (η προεπιλογή) γράφεται «(εκτίμηση)».
          final name = '${_shortName(f.name)}${aiMercuryPpm.containsKey(f.id) ? '' : ' (εκτίμηση)'}';
          mercuryBy[name] = (mercuryBy[name] ?? 0) + hg;
        }
        if (aiOilyFishIds.contains(f.id)) oilyFish += rawG;
      }
      if (meat >= 80) redMeat++;
      if (proc >= 20) processed++;
    }
    if (legumeG >= legumesDryMinG - 1e-9) legumeDays++;
    if (fishG >= fishMinG - 1e-9) fishDays++;
    final missingMeals = [for (final m in ordered) if (!w.days[i].any((s) => s.meal == m)) m];
    if (!checkDays.contains(i)) continue;
    for (final m in missingMeals) {
      out.add(AiProblem(
        day: i,
        user: '$label: το ${mealLabel(m).toLowerCase()} έμεινε χωρίς φαγητό.',
        ai: '$label: λείπει το ${mealLabel(m).toLowerCase()} (${m.name}).',
        weight: 3,
      ));
    }
    if (unknown) {
      out.add(AiProblem(day: i, user: '$label: δεν ελέγχθηκε όλη (ένα φαγητό δεν έχει θερμίδες στη βάση).', ai: '', weight: 0));
    }
    if (parts.isEmpty || share <= 0) continue;
    final tot = Totals(parts);
    final f = share / shareAll;
    final kt = t.kcal * f, pt = t.protein * f;
    if (missingMeals.isEmpty && !unknown) weekKcal.add(tot.kcal);
    if ((tot.kcal - kt).abs() > kt * aiDayKcalTol) {
      final low = tot.kcal < kt;
      out.add(AiProblem(
        day: i,
        user: '$label: ${_n(tot.kcal)} kcal (στόχος ${_n(kt)}).',
        ai: '$label: θερμίδες ${_n(_pct(tot.kcal, kt))}% ${low ? 'κάτω' : 'πάνω'} από τον στόχο της μέρας, ακόμα και με τη '
            '${low ? 'μεγαλύτερη' : 'μικρότερη'} μερίδα: θέλει ${low ? 'πιο χορταστικά' : 'πιο ελαφριά'} φαγητά.',
        weight: 1 + _pct(tot.kcal, kt) / 10,
      ));
    }
    if (tot.protein < pt * aiDayProteinMin) {
      out.add(AiProblem(
        day: i,
        user: '$label: πρωτεΐνη ${_n(tot.protein)} g (στόχος ${_n(pt)}).',
        ai: '$label: πρωτεΐνη ${_n(_pct(tot.protein, pt))}% κάτω από τον στόχο: θέλει πιο πρωτεϊνούχα φαγητά.',
      ));
    }
    if (tot.satFat > t.satMax * f + 1e-9) {
      final src = _topSources(parts, Nk.satFat);
      out.add(AiProblem(
        day: i,
        user: '$label: κορεσμένα ${_g1(tot.satFat)} g (όριο ${_g1(t.satMax * f)}): κυρίως $src.',
        ai: '$label: κορεσμένα ${_n(_pct(tot.satFat, t.satMax * f))}% πάνω από το όριο· κυρίως $src.',
        tag: 'sat',
      ));
    } else if ((tot.missing[Nk.satFat] ?? 0) > 0) {
      // K2-R-10: με tag, για να φαίνεται και στα προγράμματα με κανόνες / επικολλημένα ([weekHealthNotes]).
      out.add(AiProblem(
          day: i,
          user: '$label: κάποια τρόφιμα δεν έχουν κορεσμένα στη βάση (το σύνολο είναι «τουλάχιστον»).',
          ai: '',
          weight: 0,
          tag: 'sat'));
    }
    final saltMax = t.salt * f;
    if (tot.salt > saltMax + 1e-9) {
      final src = _topSources(parts, Nk.salt);
      out.add(AiProblem(
        day: i,
        user: '$label: αλάτι ${(tot.missing[Nk.salt] ?? 0) > 0 ? '≥ ' : ''}${_g1(tot.salt)} g (όριο ${_g1(saltMax)}): κυρίως $src.',
        ai: '$label: αλάτι ${_n(_pct(tot.salt, saltMax))}% πάνω από το όριο· κυρίως $src.',
        weight: 0.7,
        tag: 'salt',
      ));
    }
    if (tot.fiber < t.fiber * f * aiDayFiberMin) {
      out.add(AiProblem(
        day: i,
        user: '$label: ίνες ${(tot.missing[Nk.fiber] ?? 0) > 0 ? '≥ ' : ''}${_n(tot.fiber)} g (στόχος ${_n(t.fiber * f)}).',
        ai: '$label: ίνες ${_n(_pct(tot.fiber, t.fiber * f))}% κάτω από τον στόχο: περισσότερα λαχανικά, όσπρια, ολικής.',
        weight: 0.5,
      ));
    }
    final fv = parts.where((e) => isFruitVeg(e.food) && e.grams >= 10).fold(0.0, (a, e) => a + e.grams);
    if (fv < aiFruitVegDayG * f) {
      out.add(AiProblem(
        day: i,
        user: '$label: φρούτα και λαχανικά ${_n(fv)} g (τουλάχιστον ${_n(aiFruitVegDayG * f)}).',
        ai: '$label: λίγα φρούτα και λαχανικά (${_n(fv)} g)· θέλει τουλάχιστον ${_n(aiFruitVegDayG * f)} g.',
        weight: 0.5,
      ));
    } else if (fv < fruitVegTargetG * f) {
      fruitVegShort++; // K2-S-08: περνά τον έλεγχο (από 300 g), αλλά κάτω από τον στόχο της μέρας (400 g, ΠΟΥ)
    }
    final sugar = parts.where((e) => e.food.cat == 'Γλυκά').fold(0.0, (a, e) => a + e.total(Nk.sugars));
    if (sugar > kt * aiFreeSugarPct / 4) {
      out.add(AiProblem(
        day: i,
        user: '$label: ζάχαρη/γλυκά ${_n(sugar)} g (όριο ${_n(kt * aiFreeSugarPct / 4)}).',
        ai: '$label: πολλά γλυκά/ζάχαρη· λιγότερα.',
        weight: 0.5,
      ));
    }
  }
  if (checkDays.isEmpty) return out;
  if (legumesWeek > 0 && legumeDays < legumesWeek) {
    out.add(AiProblem(
      user: 'Όσπρια $legumeDays μέρες (στόχος $legumesWeek).',
      ai: 'Όσπρια μόνο $legumeDays μέρες (θέλω $legumesWeek, με τουλάχιστον 40 g ξερά στη μερίδα).',
      weight: 0.7,
    ));
  }
  if (fishWeek > 0 && fishDays < fishWeek) {
    out.add(AiProblem(
      user: 'Ψάρι $fishDays μέρες (στόχος $fishWeek).',
      ai: 'Ψάρι μόνο $fishDays μέρες (θέλω $fishWeek, με τουλάχιστον 100 g στη μερίδα).',
      weight: 0.7,
    ));
  }
  if (redMeat > 1) {
    out.add(AiProblem(user: 'Κόκκινο κρέας $redMeat φορές (το πολύ 1).', ai: 'Κόκκινο κρέας $redMeat φορές: το πολύ 1.'));
  }
  if (processed > 1) {
    out.add(AiProblem(user: 'Αλλαντικά $processed φορές (το πολύ 1).', ai: 'Αλλαντικά $processed φορές: το πολύ 1.', weight: 0.7));
  }
  // K2-R-10: πρόγραμμα πάνω από 7 μέρες (επικόλληση ως 14): τα εβδομαδιαία όρια μετριούνται ανά εβδομάδα (μέσος όρος).
  final weeks = w.days.length > 7 ? w.days.length / 7 : 1.0;
  mercury /= weeks;
  oilyFish /= weeks;
  if (bodyKg != null && bodyKg > 0 && mercury > aiMercuryTwiPerKg * bodyKg) {
    // K2-S-01: οι μεγαλύτερες πηγές με το όνομά τους (πριν: πάντα «ξιφίας ή τόνος λευκός»).
    final top = mercuryBy.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final names = [for (final e in top.take(2)) e.key].join(', ');
    // K2-R-11: η τιμή προς τα πάνω και το όριο προς τα κάτω, ώστε να μη γράφεται «107 µg (όριο 107)».
    out.add(AiProblem(
      user: 'Υδράργυρος από ψάρια ${mercury.ceil()} µg την εβδομάδα (όριο EFSA ${(aiMercuryTwiPerKg * bodyKg).floor()}): '
          'κυρίως $names.',
      ai: 'Πολύς υδράργυρος από ψάρια την εβδομάδα, κυρίως από: $names. Λιγότερες φορές ή μικρότερη μερίδα από αυτά· στη '
          'θέση τους σαρδέλα, γαύρος, σολομός, γαρίδες ή καλαμάρι. Ξιφίας το πολύ μία φορά τον μήνα, τόνος λευκός το '
          'πολύ μία φορά την εβδομάδα.',
      weight: 1.5,
      tag: 'mercury',
    ));
  }
  if (fruitVegShort > 0) {
    // K2-S-08: μόνο ενημέρωση (βάρος 0): η κάρτα της μέρας ζητά 400 g, ο έλεγχος του προγράμματος περνά από τα 300.
    out.add(AiProblem(
      user: 'Φρούτα και λαχανικά: ${fruitVegShort == 1 ? '1 μέρα' : '$fruitVegShort μέρες'} με ${_n(aiFruitVegDayG)}–'
          '${_n(fruitVegTargetG)} g, κάτω από τον στόχο της μέρας (${_n(fruitVegTargetG)} g). Ένα φρούτο ή μια σαλάτα ακόμα '
          'τον καλύπτει.',
      ai: '',
      weight: 0,
    ));
  }
  // K2-R-09 (NHS: «τουλάχιστον 2 μερίδες ψάρι την εβδομάδα, η 1 λιπαρό»): μόνο ενημέρωση (βάρος 0, δεν ξεκινά διόρθωση),
  // όταν ζητάς ψάρι 2+ φορές και η εβδομάδα δεν έχει καθόλου λιπαρό.
  if (fishWeek >= 2 && oilyFish < aiOilyFishMinG) {
    out.add(const AiProblem(
      user: 'Κανένα λιπαρό ψάρι αυτή την εβδομάδα (καλό είναι τουλάχιστον 1 φορά: σολομός, σαρδέλα, σκουμπρί, γαύρος· NHS).',
      ai: '',
      weight: 0,
    ));
  }
  if (oilyFish > aiOilyFishWeekG + 1e-9) {
    // K2-S-03: άνω όριο για το λιπαρό ψάρι (NHS: άνδρες ως 4 μερίδες την εβδομάδα).
    out.add(AiProblem(
      user: 'Λιπαρό ψάρι ${_n(oilyFish)} g την εβδομάδα (ως ${_n(aiOilyFishWeekG)} g ωμό, περίπου 4 μερίδες· NHS).',
      ai: 'Λιπαρό ψάρι (σολομός, σαρδέλα, σκουμπρί, ρέγγα, γαύρος) ${_n(oilyFish)} g την εβδομάδα: το πολύ '
          '${_n(aiOilyFishWeekG)} g ωμό (4 μερίδες). Βάλε άπαχο ψάρι ή θαλασσινά (τσιπούρα, γαρίδες, καλαμάρι) στη θέση '
          'μερικών, ή μικρότερη μερίδα.',
      weight: 0.7,
      tag: 'oily',
    ));
  }
  if (weekKcal.length >= 3) {
    final avg = weekKcal.fold(0.0, (a, b) => a + b) / weekKcal.length;
    if ((avg - t.kcal).abs() > t.kcal * aiWeekKcalTol) {
      out.add(AiProblem(
        user: 'Μέσος όρος εβδομάδας ${_n(avg)} kcal (στόχος ${t.kcal}).',
        ai: 'Ο μέσος όρος της εβδομάδας είναι ${_n(_pct(avg, t.kcal.toDouble()))}% ${avg < t.kcal ? 'κάτω' : 'πάνω'} από τον στόχο.',
        weight: 0.5,
      ));
    }
  }
  out.addAll(_potProblems(food, w, byId));
  out.addAll(_minuteProblems(w, byId, checkDays));
  return out;
}

/// Κατσαρόλες: ρύζι μόνο ως την επόμενη μέρα, και ο χρήστης το πολύ το μισό ενός μαγειρέματος (L-5, S-7).
List<AiProblem> _potProblems(FoodStore food, WeekPlan w, Map<String, Dish> byId) {
  final out = <AiProblem>[];
  final placed = <String, List<(int, PlanSlot)>>{};
  for (var i = 0; i < w.days.length; i++) {
    for (final s in w.days[i]) {
      final d = byId[s.dishId];
      if (d != null && d.kind == DishKind.pot) (placed[d.id] ??= []).add((i, s));
    }
  }
  for (final MapEntry(key: id, value: ps) in placed.entries) {
    final d = byId[id]!;
    final all = itemsTotals(food, d.items);
    if (all == null || all.kcal <= 0) continue;
    final rice = _hasRice(food, d);
    final natural = itemsTotals(food, naturalRaw(d) ?? const [])?.kcal ?? 0;
    // Μαγειρέματα: η πρώτη θέση και όσες ακολουθούν μέσα στο παράθυρο.
    var i = 0;
    while (i < ps.length) {
      final first = ps[i].$1;
      var j = i;
      var sum = 0.0;
      while (j < ps.length && ps[j].$1 - first <= aiPotMaxGap) {
        sum += ps[j].$2.kcal ?? natural;
        if (rice && ps[j].$1 - first > aiPotRiceGap) {
          out.add(AiProblem(
            user: '«${d.name}» έχει ρύζι: το περίσσευμα μόνο ως την επόμενη μέρα (όχι ${_day(w.dayAt(ps[j].$1))}).',
            ai: '«${d.name}» έχει ρύζι: η 2η φορά μόνο την επόμενη μέρα.',
            weight: 1.5,
          ));
        }
        j++;
      }
      if (sum > all.kcal * aiPotUserShare + 1) {
        out.add(AiProblem(
          user: '«${d.name}»: τρως το ${_n(sum / all.kcal * 100)}% της κατσαρόλας· δεν φτάνει για όλο το σπίτι.',
          ai: '«${d.name}» (κατσαρόλα): δεν φτάνει για όλο το σπίτι· θέλει περισσότερες μερίδες στο "servings" ή μία φορά λιγότερη.',
        ));
      }
      i = j;
    }
  }
  return out;
}

/// Χρόνος μαγειρέματος: καθημερινές ως 30′, Σαββατοκύριακο ως 60′ (όχι για τα περισσεύματα της κατσαρόλας).
List<AiProblem> _minuteProblems(WeekPlan w, Map<String, Dish> byId, Set<int> checkDays) {
  final out = <AiProblem>[];
  final seenPot = <String, int>{};
  for (var i = 0; i < w.days.length; i++) {
    for (final s in w.days[i]) {
      final d = byId[s.dishId];
      if (d == null || planInfoOf(d)?.cook != CookWay.home) continue;
      if (d.kind == DishKind.pot) {
        final f = seenPot[d.id];
        if (f != null && i - f <= aiPotMaxGap) continue; // περίσσευμα
        seenPot[d.id] = i;
      }
      final min = recipeOf(d)?.minutes;
      final weekend = w.dayAt(i).weekday >= DateTime.saturday;
      final limit = weekend ? 60 : 30;
      if (checkDays.contains(i) && min != null && min > limit) {
        out.add(AiProblem(
          day: i,
          user: '${_day(w.dayAt(i))}: «${d.name}» θέλει $min′ (${weekend ? 'Σαββατοκύριακο' : 'καθημερινή'} ως $limit′).',
          ai: '${_day(w.dayAt(i))}: «${d.name}» θέλει $min′, ${weekend ? 'Σαββατοκύριακο' : 'καθημερινή'} ως $limit′.',
          weight: 0.5,
        ));
      }
    }
  }
  return out;
}

double aiScore(List<AiProblem> ps) => ps.fold(0.0, (a, p) => a + p.weight);

// ---------------------------------------------------------------------------
// Όλο το «Φτιάξε την εβδομάδα με AI»
// ---------------------------------------------------------------------------

class AiWeekResult {
  const AiWeekResult({this.plan, this.newDishes = const [], this.notes = const [], this.fail, this.errors = const []});

  /// Το πρόγραμμα (δεν έχει αποθηκευτεί) ή null αν δεν βγήκε.
  final WeekPlan? plan;

  /// Τα νέα φαγητά του προγράμματος (δεν έχουν αποθηκευτεί).
  final List<Dish> newDishes;

  /// Ό,τι δεν βγήκε όπως ζητούν οι κανόνες, σε απλά λόγια.
  final List<String> notes;
  final AiFail? fail;

  /// Γιατί δεν βγήκε (όταν [plan] είναι null και δεν φταίει η σύνδεση): πρώτη γραμμή για τον χρήστη, μετά λεπτομέρειες.
  final List<String> errors;
}

/// Τι γίνεται τώρα (για την οθόνη).
enum AiStage { plan, recipes, check, fix }

/// «Φτιάξε την εβδομάδα με AI». [keep]: το τωρινό πρόγραμμα (μένουν κλειδωμένα, γραμμένα και οι μέρες πριν από [today],
/// αν είναι ίδια αρχή).
Future<AiWeekResult> aiBuildWeek({
  required AiCall call,
  required FoodStore food,
  required Kitchen kitchen,
  required AiTargets targets,
  required DateTime from,
  required List<Meal> meals,
  int? legumesWeek,
  int? fishWeek,
  double? bodyKg,
  WeekPlan? keep,
  required int now,
  DateTime? today,
  required String Function() newId,
  void Function(AiStage stage, int done, int total, int attempt)? progress,
}) async {
  final allowed = aiAllowedIds(food);
  if (allowed.isEmpty || food.likes.like.isEmpty) {
    return const AiWeekResult(errors: ['Πρώτα διάλεξε τι σου αρέσει: μόνο από αυτά φτιάχνει το AI.']);
  }
  final start = DateTime(from.year, from.month, from.day);
  final day0 = today ?? DateTime.fromMillisecondsSinceEpoch(now);
  final todayD = DateTime(day0.year, day0.month, day0.day);
  final keepPlan = keep != null && keep.from == dateKey(start) ? keep : null;
  final kept = <(int, Meal), String>{};
  if (keepPlan != null) {
    for (var i = 0; i < keepPlan.days.length && i < 7; i++) {
      final past = keepPlan.dayAt(i).isBefore(todayD);
      for (final s in keepPlan.days[i]) {
        // Μέρες πριν από σήμερα μένουν όπως είναι (U-23)· και κλειδωμένα/σημειωμένα.
        if (past || s.locked || s.state != SlotState.open) kept.putIfAbsent((i, s.meal), () => s.dishId);
      }
    }
  }
  final ask = (from: start, days: 7, meals: meals, kept: kept);
  final lib = aiLibrary(food, allowed);
  final libByKey = {for (final d in lib) planInfoOf(d)!.key!: d};
  final allKeys = {for (final d in libraryDishes(food.dishes)) planInfoOf(d)!.key!};
  final keptKeys = <(int, Meal), String>{
    for (final e in kept.entries)
      if (food.dishById(e.value) case final d?)
        if (planInfoOf(d)?.key case final k?) e.key: k,
  };
  final system = aiSystem(food, allowed, kitchen, limits: targets);
  final checkDays = <int>{
    for (var i = 0; i < 7; i++)
      if (!DateTime(start.year, start.month, start.day + i).isBefore(todayD) && meals.any((m) => !kept.containsKey((i, m)))) i,
  };

  progress?.call(AiStage.plan, 0, 1, 1);
  final basePrompt = aiPlanPrompt(food: food, ask: ask, library: lib, dayKcal: targets.kcal, legumesWeek: legumesWeek, fishWeek: fishWeek);
  final (plan0, errs0, fail0) = await aiAskUntilValid<AiPlan>(
    call,
    model: aiModelPlan,
    system: system,
    prompt: basePrompt,
    maxTokens: aiMaxTokensPlan,
    onAttempt: (a) => progress?.call(AiStage.plan, 0, 1, a),
    read: (t) {
      final p = parseAiPlan(t, ask, libByKey, allKeys, keptKeys: keptKeys);
      return (p.plan, p.errors);
    },
  );
  if (fail0 != null) return AiWeekResult(fail: fail0);
  if (plan0 == null) {
    return AiWeekResult(errors: ['Το AI δεν έφτιαξε πρόγραμμα που να περνά τους ελέγχους, ούτε στην 3η προσπάθεια.', ...errs0]);
  }

  final extra = <Dish>[];
  final failedNew = <String, String>{}; // key → σημείωση για τον χρήστη

  /// Οι συνταγές των νέων φαγητών του [p] που δεν έχουν γραφτεί ήδη. null: εντάξει· αλλιώς αποτυχία σύνδεσης.
  Future<AiFail?> recipes(AiPlan p) async {
    final want = [
      for (final n in p.newDishes)
        if (!extra.any((d) => planInfoOf(d)!.key == n.key) && !failedNew.containsKey(n.key)) n,
    ];
    if (want.isEmpty) return null;
    progress?.call(AiStage.recipes, 0, want.length, 1);
    final res = await aiPool<AiNewDish, (Dish?, List<String>, AiFail?)>(
      want,
      (n) {
        final needMeals = <Meal>{};
        var office = false;
        for (var i = 0; i < p.days.length; i++) {
          for (final (m, k) in p.days[i]) {
            if (k != n.key) continue;
            needMeals.add(m);
            if (m == Meal.lunch && officeWeekdays.contains(DateTime(start.year, start.month, start.day + i).weekday)) office = true;
          }
        }
        return aiAskUntilValid<Dish>(
          call,
          model: aiModelRecipe,
          system: system,
          prompt: aiRecipePrompt(n),
          read: (t) {
            final r = aiReadDish(t,
                food: food, allowed: allowed, now: now, newId: newId, want: n, needMeals: needMeals, needOffice: office);
            return (r.dish, r.errors);
          },
        );
      },
      progress: (done) => progress?.call(AiStage.recipes, done, want.length, 1),
    );
    for (var k = 0; k < want.length; k++) {
      final (d, _, fail) = res[k];
      if (fail != null) return fail;
      if (d == null) {
        failedNew[want[k].key] = 'Η συνταγή «${want[k].name}» δεν μπήκε: το AI δεν την έγραψε μόνο με όσα σου αρέσουν και '
            'μέσα στα όρια της εφαρμογής (αλάτι, λάδι, ασφάλεια). Η θέση της έμεινε χωρίς φαγητό.';
      } else {
        extra.add(d);
      }
    }
    return null;
  }

  final f0 = await recipes(plan0);
  if (f0 != null) return AiWeekResult(fail: f0);

  AutoWeek assemble(AiPlan p) {
    final byKey = {...libByKey, for (final d in extra) planInfoOf(d)!.key!: d};
    final forced = <(int, Meal), String>{
      for (var i = 0; i < p.days.length; i++)
        for (final (m, k) in p.days[i])
          if (byKey[k] case final d?) (i, m): d.id,
    };
    return autoWeek(
      food,
      from: start,
      meals: meals,
      kcalTarget: targets.kcal.toDouble(),
      proteinTarget: targets.protein.toDouble(),
      legumesWeek: legumesWeek ?? 0,
      fishWeek: fishWeek ?? 0,
      keep: keepPlan == null ? null : _keepOnly(keepPlan, kept),
      now: now,
      extra: extra,
      forced: forced,
      aiOnly: true,
    );
  }

  List<String> notesFor(AiPlan p, AutoWeek built) {
    final keys = {for (final d in p.days) for (final s in d) s.$2};
    return [
      for (final e in failedNew.entries)
        if (keys.contains(e.key)) e.value,
      ...built.notes,
    ];
  }

  List<AiProblem> check(WeekPlan w) => aiCheckWeek(food, w, extra,
      t: targets, meals: meals, checkDays: checkDays, legumesWeek: legumesWeek ?? 0, fishWeek: fishWeek ?? 0, bodyKg: bodyKg);

  bool anyAiSlot(WeekPlan w) {
    for (var i = 0; i < w.days.length; i++) {
      for (final s in w.days[i]) {
        if (kept[(i, s.meal)] != s.dishId) return true;
      }
    }
    return false;
  }

  progress?.call(AiStage.check, 0, 1, 1);
  var plan = plan0;
  var built = assemble(plan);
  if (!anyAiSlot(built.plan) && checkDays.isNotEmpty) {
    // Κανένα φαγητό του AI δεν μπήκε (L-2): ποτέ πρόγραμμα από φαγητά που δεν διάλεξε.
    return AiWeekResult(errors: ['Δεν μπήκε κανένα φαγητό του AI στο πρόγραμμα.', ...failedNew.values]);
  }
  var problems = check(built.plan);
  final fixable = problems.where((p) => p.ai.isNotEmpty && p.weight > 0).toList();
  if (fixable.isNotEmpty) {
    // Μία διόρθωση: πίσω στο AI το πρόγραμμα με τα προβλήματα (σε ποσοστά, από τη βάση).
    progress?.call(AiStage.fix, 0, 1, 1);
    final byId = {for (final d in [...food.dishes, ...extra]) d.id: d};
    final current = {
      'kind': aiWeekKind,
      'new': const [],
      'days': [
        for (var i = 0; i < built.plan.days.length; i++)
          [
            for (final s in built.plan.days[i])
              if (kept[(i, s.meal)] != s.dishId)
                if (byId[s.dishId] case final d?)
                  if (planInfoOf(d)?.key case final k?) {'meal': s.meal.name, 'key': k},
          ],
      ],
    };
    final fixLib = [...lib, ...extra];
    final fixByKey = {for (final d in fixLib) planInfoOf(d)!.key!: d};
    final extraByKey = {for (final d in extra) planInfoOf(d)!.key!: d};
    final prompt = '${aiPlanPrompt(food: food, ask: ask, library: fixLib, dayKcal: targets.kcal, legumesWeek: legumesWeek, fishWeek: fishWeek)}\n'
        'ΤΩΡΙΝΟ ΠΡΟΓΡΑΜΜΑ:\n```json\n${jsonEncode(current)}\n```\n'
        'Με τις μερίδες της εφαρμογής βγαίνουν αυτά τα προβλήματα:\n${[for (final p in fixable) '- ${p.ai}'].join('\n')}\n'
        'Άλλαξε ΜΟΝΟ όσα γεύματα χρειάζεται για να διορθωθούν, και στείλε ΟΛΟ το πρόγραμμα στην ίδια μορφή (στο "new" μόνο '
        'καινούργια φαγητά· τα φαγητά του τωρινού προγράμματος είναι ήδη στη βιβλιοθήκη).';
    final (plan1, _, fail1) = await aiAskUntilValid<AiPlan>(
      call,
      model: aiModelPlan,
      system: system,
      prompt: prompt,
      maxTokens: aiMaxTokensPlan,
      onAttempt: (a) => progress?.call(AiStage.fix, 0, 1, a),
      read: (t) {
        final p = parseAiPlan(t, ask, fixByKey, {...allKeys, ...extraByKey.keys}, extra: extraByKey, keptKeys: keptKeys);
        return (p.plan, p.errors);
      },
    );
    if (fail1 == AiFail.cancelled) return const AiWeekResult(fail: AiFail.cancelled);
    if (fail1 == null && plan1 != null) {
      final f1 = await recipes(plan1);
      if (f1 == AiFail.cancelled) return const AiWeekResult(fail: AiFail.cancelled);
      if (f1 == null) {
        final b1 = assemble(plan1);
        final p1 = check(b1.plan);
        // Κρατά το νέο μόνο αν είναι συνολικά καλύτερο (κενές θέσεις και κανόνες μετρούν βαριά, L-7).
        if (aiScore(p1) < aiScore(problems)) {
          plan = plan1;
          built = b1;
          problems = p1;
        }
      }
    }
  }
  // Μόνο τα νέα φαγητά που μπήκαν τελικά στο πρόγραμμα.
  final usedIds = {for (final d in built.plan.days) for (final s in d) s.dishId};
  final keptNew = [for (final d in extra) if (usedIds.contains(d.id)) d];
  final allNotes = <String>{...notesFor(plan, built), for (final p in problems) p.user}.toList();
  return AiWeekResult(
    plan: WeekPlan(
      from: built.plan.from,
      created: built.plan.created,
      source: 'ai',
      meals: meals,
      // Οι παλιές μέρες κλείδωσαν μόνο για να μείνουν· ξεκλειδώνουν ξανά όπως ήταν.
      days: [
        for (var i = 0; i < built.plan.days.length; i++)
          [
            for (final s in built.plan.days[i])
              if (s.locked && kept[(i, s.meal)] == s.dishId &&
                  !(keepPlan?.days.elementAtOrNull(i)?.any((o) => o.meal == s.meal && o.dishId == s.dishId && o.locked) ?? false))
                s.copyWith(locked: false)
              else
                s,
          ],
      ],
    ),
    newDishes: keptNew,
    notes: allNotes,
  );
}

/// Το τωρινό πρόγραμμα μόνο με τις θέσεις που μένουν (κλειδωμένες, σημειωμένες, μέρες πριν από σήμερα). Όσες μένουν
/// επειδή είναι παλιές μέρες κλειδώνουν, ώστε να τις κρατήσει και το autoWeek.
WeekPlan _keepOnly(WeekPlan w, Map<(int, Meal), String> kept) => WeekPlan(
      from: w.from,
      created: w.created,
      source: w.source,
      meals: w.meals,
      days: [
        for (var i = 0; i < w.days.length; i++)
          [
            for (final s in w.days[i])
              if (kept[(i, s.meal)] == s.dishId) (s.locked || s.state != SlotState.open ? s : s.copyWith(locked: true)),
          ],
      ],
    );

// ---------------------------------------------------------------------------
// «Άλλαξε αυτό το γεύμα»
// ---------------------------------------------------------------------------

/// Γιατί αλλάζει.
enum SwapReason { time, missing, appetite }

/// Τα νούμερα της θέσης από τη βάση.
typedef SlotNumbers = ({double kcal, double protein, double sat, double salt, double fiber});

/// Η μερίδα του [d] όσο πιο κοντά στις [kcal] θερμίδες: μέσα στα όρια της μερίδας του, στρογγυλή όπως θα αποθηκευτεί
/// (ανά 10 kcal· ίσες μερίδες ανά μισή μερίδα, όπως στο «Το έφαγα», L-9/L-10), και τα νούμερά της από τη βάση.
({double kcal, SlotNumbers n})? portionFor(FoodStore food, Dish d, double kcal) {
  final r = portionRange(food, d);
  if (r == null) return null;
  var k = kcal.clamp(r.lo, r.hi).toDouble();
  if (d.kind == DishKind.portions && r.natural != null && r.natural! > 0) {
    final half = r.natural! / 2;
    k = ((k / half).round().clamp(1, (maxEatenServings * 2).round()) * half).roundToDouble();
  } else {
    final lo = math.max(minSlotKcal, r.lo), hi = math.max(lo, math.min(maxSlotKcal, r.hi));
    k = ((k / 10).round() * 10).toDouble();
    if (k < lo) k = (lo / 10).ceil() * 10.0;
    if (k > hi) k = (hi / 10).floor() * 10.0;
    if (k < lo) k = lo.roundToDouble();
  }
  final raw = plannedRaw(food, d, k);
  final t = raw == null ? null : itemsTotals(food, raw);
  if (t == null) return null;
  return (kcal: k, n: (kcal: t.kcal, protein: t.protein, sat: t.satFat, salt: t.salt, fiber: t.fiber));
}

/// Είναι «ανάλογο»; Επιστρέφει τα προβλήματα (κενό = ναι).
List<String> analogProblems(SlotNumbers old, SlotNumbers cand) => [
      if ((cand.kcal - old.kcal).abs() > old.kcal * aiSwapKcalTol)
        'θερμίδες ${_n(cand.kcal)} αντί για περίπου ${_n(old.kcal)} (η μερίδα του δεν φτάνει εκεί)',
      if (cand.protein < old.protein * aiSwapProteinMin)
        'πρωτεΐνη ${_n(cand.protein)} g, χρειάζεται τουλάχιστον ${_n(old.protein * aiSwapProteinMin)} g',
      if (cand.sat > old.sat + aiSwapSatExtra)
        'κορεσμένα ${_g1(cand.sat)} g, το πολύ ${_g1(old.sat + aiSwapSatExtra)} g',
    ];

class AiSwapResult {
  const AiSwapResult({this.dish, this.kcal, this.isNew = false, this.fail, this.errors = const []});
  final Dish? dish;

  /// Η μερίδα όπως θα αποθηκευτεί (ήδη στρογγυλή).
  final double? kcal;

  /// Νέο φαγητό (μπαίνει και στη βιβλιοθήκη με το «Ναι»).
  final bool isNew;
  final AiFail? fail;

  /// Γιατί δεν βρέθηκε: πρώτη γραμμή για τον χρήστη, μετά λεπτομέρειες.
  final List<String> errors;
}

/// Η «ομάδα» ενός φαγητού (για να προτιμηθεί ίδια ομάδα στην αλλαγή, S-6): η κύρια πηγή πρωτεΐνης στη μερίδα.
String? dishGroup(FoodStore food, Dish d) {
  final parts = food.previewDish(naturalRaw(d) ?? d.items);
  if (parts == null) return null;
  final by = <String, double>{};
  for (final e in parts) {
    final f = e.food;
    final g = isLegumes(f)
        ? 'όσπρια'
        : isFish(f)
            ? 'ψάρι'
            : switch (f.cat) {
                'Κρέας' || 'Αλλαντικά' => 'κρέας',
                'Πουλερικά' => 'πουλερικά',
                'Αυγά' => 'αυγά',
                'Τυριά' || 'Γαλακτοκομικά' => 'γαλακτοκομικά',
                _ => null,
              };
    if (g != null) by[g] = (by[g] ?? 0) + e.total(Nk.protein);
  }
  if (by.isEmpty) return null;
  return (by.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
}

/// Ελέγχει ένα υποψήφιο φαγητό για τη θέση.
List<String> swapChecks(FoodStore food, Dish d, {required Meal meal, required bool office, required SwapReason reason,
    String? missingId, required SlotNumbers old, required Set<String> allowed, required String currentId}) {
  final p = planInfoOf(d);
  final out = <String>[];
  if (d.id == currentId) out.add('είναι το ίδιο φαγητό');
  if (p != null && !p.fits(meal)) out.add('δεν είναι για ${mealLabel(meal).toLowerCase()}');
  if (office && !(p?.office ?? false)) out.add('θέλει φαγητό για γραφείο ("office": true)');
  if (!aiDishAllowed(food, d, allowed)) out.add('έχει υλικό εκτός λίστας');
  if (dishRating(d) < 0) out.add('είναι στα «Δεν μου άρεσε»');
  if (missingId != null && d.items.any((i) => _nowId(food, i.id) == missingId)) out.add('έχει το υλικό που λείπει');
  if (reason == SwapReason.time && p?.cook != CookWay.none) {
    final m = recipeOf(d)?.minutes;
    if (m == null || m > aiQuickMinutes) out.add('θέλει ως $aiQuickMinutes λεπτά μαγείρεμα (ή χωρίς μαγείρεμα)');
  }
  final pf = portionFor(food, d, old.kcal);
  if (pf == null) {
    out.add('δεν βγαίνουν θερμίδες');
  } else {
    out.addAll(analogProblems(old, pf.n));
  }
  return out;
}

/// Τι αλλάζει για την υγεία με την αλλαγή (για τον διάλογο επιβεβαίωσης, S-6): ίνες, αλάτι, όσπρια/ψάρι της εβδομάδας,
/// κόκκινο κρέας, υδράργυρος.
List<String> swapWarnings(FoodStore food, Dish oldDish, PlanSlot oldSlot, Dish newDish, double newKcal) {
  final oldRaw = plannedRaw(food, oldDish, oldSlot.kcal), newRaw = plannedRaw(food, newDish, newKcal);
  final a = oldRaw == null ? null : food.previewDish(oldRaw);
  final b = newRaw == null ? null : food.previewDish(newRaw);
  if (a == null || b == null) return const [];
  final ta = Totals(a), tb = Totals(b);
  double g(List<LogEntry> p, bool Function(Food f) w, {bool legumes = false}) => p
      .where((e) => w(e.food))
      .fold(0.0, (s, e) => s + (legumes && cookedLegumes(e.food) ? e.grams / legumesCookedFactor : e.grams));
  final out = <String>[];
  if (ta.fiber - tb.fiber > 3 && tb.fiber < ta.fiber * 0.6) out.add('Ίνες ${_n(ta.fiber)} → ${_n(tb.fiber)} g.');
  if (tb.salt - ta.salt >= 1) out.add('Αλάτι ${_g1(ta.salt)} → ${_g1(tb.salt)} g.');
  if (g(a, isLegumes, legumes: true) >= legumesDryMinG && g(b, isLegumes, legumes: true) < legumesDryMinG) {
    out.add('Χάνεται μία μέρα οσπρίων της εβδομάδας.');
  }
  if (g(a, isFish) >= fishMinG && g(b, isFish) < fishMinG) out.add('Χάνεται ένα ψάρι της εβδομάδας.');
  if (g(a, (f) => f.cat == 'Κρέας') < 80 && g(b, (f) => f.cat == 'Κρέας') >= 80) out.add('Μπαίνει κόκκινο κρέας.');
  if (b.any((e) => mercuryPpm(e.food) >= 0.3) && !a.any((e) => mercuryPpm(e.food) >= 0.3)) {
    out.add('Ψάρι με περισσότερο υδράργυρο (ξιφίας/τόνος λευκός): όχι συχνά.');
  }
  return out;
}

/// «Άλλαξε αυτό το γεύμα» με AI: ένα ανάλογο φαγητό (της βιβλιοθήκης ή νέο) για τη θέση [day]/[index] του [w].
Future<AiSwapResult> aiSwapSlot({
  required AiCall call,
  required FoodStore food,
  required Kitchen kitchen,
  required WeekPlan w,
  required int day,
  required int index,
  required SwapReason reason,
  String? missingId,
  required int now,
  required String Function() newId,
  void Function(int attempt)? onAttempt,
  AiTargets? limits,
}) async {
  final s = w.days[day][index];
  final cur = food.dishById(s.dishId);
  final allowed = aiAllowedIds(food);
  if (cur == null) return const AiSwapResult(errors: ['Το φαγητό αυτής της θέσης δεν υπάρχει πια.']);
  final curTotals = plannedTotals(food, cur, s);
  if (curTotals == null) return const AiSwapResult(errors: ['Δεν βγαίνουν θερμίδες για το τωρινό φαγητό.']);
  final old = (kcal: curTotals.kcal, protein: curTotals.protein, sat: curTotals.satFat, salt: curTotals.salt, fiber: curTotals.fiber);
  final date = w.dayAt(day);
  final office = s.meal == Meal.lunch && officeWeekdays.contains(date.weekday);
  List<String> check(Dish d) => swapChecks(food, d,
      meal: s.meal, office: office, reason: reason, missingId: missingId, old: old, allowed: allowed, currentId: cur.id);

  // Φαγητά της βιβλιοθήκης που περνούν ήδη όλους τους ελέγχους: πρώτα ίδια ομάδα (όσπρια→όσπρια, ψάρι→ψάρι), μετά «ΜΟΥ ΑΡΕΣΕ».
  final sameDay = {for (final x in w.days[day]) x.dishId};
  final group = dishGroup(food, cur);
  final ready = [
    for (final d in aiLibrary(food, allowed))
      if (!sameDay.contains(d.id) && check(d).isEmpty) d,
  ]..sort((a, b) {
      final ga = dishGroup(food, a) == group ? 0 : 1, gb = dishGroup(food, b) == group ? 0 : 1;
      if (ga != gb) return ga.compareTo(gb);
      return dishRating(b).compareTo(dishRating(a));
    });
  final missingName = missingId == null ? null : food.itemFood(DishItem(missingId, missingId, 1))?.name;
  final why = switch (reason) {
    SwapReason.time => 'Δεν έχω χρόνο: θέλω κάτι ως $aiQuickMinutes λεπτά ή χωρίς μαγείρεμα.',
    SwapReason.missing => 'Μου λείπει υλικό${missingName == null ? '' : ': $missingName (να μην το έχει)'}.',
    SwapReason.appetite => 'Δεν μου κάνει όρεξη: κάτι διαφορετικό.',
  };
  final prompt = StringBuffer()
    ..writeln('Άλλαξε ένα γεύμα του προγράμματός μου με ΑΝΑΛΟΓΟ φαγητό.')
    ..writeln('Γεύμα: ${_day(date)}, ${mealLabel(s.meal).toLowerCase()}${office ? ' (στο γραφείο: θέλει "office": true)' : ''}.')
    ..writeln('Τώρα: «${cur.name}»${group == null ? '' : ' (κύρια πρωτεΐνη: $group)'}, μερίδα ${_n(old.kcal)} kcal, πρωτεΐνη '
        '${_n(old.protein)} g, κορεσμένα ${_g1(old.sat)} g, αλάτι ${_g1(old.salt)} g, ίνες ${_n(old.fiber)} g.')
    ..writeln('Αιτία: $why')
    ..writeln('Ανάλογο σημαίνει: ίδιο γεύμα, με μερίδα κοντά στις ίδιες θερμίδες, πρωτεΐνη τουλάχιστον '
        '${_n(old.protein * aiSwapProteinMin)} g και κορεσμένα το πολύ ${_g1(old.sat + aiSwapSatExtra)} g σε αυτή τη '
        'μερίδα, και όπου γίνεται ίδια ομάδα (όσπρια με όσπρια, ψάρι με ψάρι), όχι περισσότερο αλάτι, όσες ίνες. Η '
        'εφαρμογή βάζει τη μερίδα.')
    ..writeln();
  if (ready.isNotEmpty) {
    prompt
      ..writeln('ΦΑΓΗΤΑ ΤΗΣ ΒΙΒΛΙΟΘΗΚΗΣ ΠΟΥ ΤΑΙΡΙΑΖΟΥΝ ΗΔΗ (key · όνομα · …):')
      ..writeln([for (final d in ready.take(40)) aiDishLine(food, d)].join('\n'))
      ..writeln()
      ..writeln('Αν ένα από αυτά είναι καλή επιλογή, απάντησε: ```json\n{"kind": "$aiSwapKind", "key": "…"}\n```')
      ..writeln('Αλλιώς γράψε ΝΕΟ φαγητό (key που ξεκινά με «$aiKeyPrefix»):');
  } else {
    prompt.writeln('Γράψε ΝΕΟ φαγητό (στη βιβλιοθήκη δεν υπάρχει κάτι που ταιριάζει· key που ξεκινά με «$aiKeyPrefix»):');
  }
  prompt.writeln(_recipeFormat('${aiKeyPrefix}neo-fagito', 'Όνομα'));
  // Έλεγχος 20/11 (K2-S-09): και εδώ τα όρια της μέρας (όπως στο πρόγραμμα της εβδομάδας)· πριν το AI δεν τα μάθαινε.
  final system = aiSystem(food, allowed, kitchen, limits: limits);
  final readyByKey = {for (final d in ready) planInfoOf(d)!.key!: d};
  final (res, errs, fail) = await aiAskUntilValid<AiSwapResult>(
    call,
    model: aiModelRecipe,
    system: system,
    prompt: prompt.toString(),
    onAttempt: onAttempt,
    read: (t) {
      final sw = jsonOfKind(t, aiSwapKind);
      if (sw != null) {
        final d = readyByKey[sw['key']];
        if (d == null) return (null, ['Το key «${sw['key']}» δεν είναι στη λίστα «ΦΑΓΗΤΑ ΤΗΣ ΒΙΒΛΙΟΘΗΚΗΣ».']);
        final pf = portionFor(food, d, old.kcal)!;
        return (AiSwapResult(dish: d, kcal: pf.kcal), const <String>[]);
      }
      final r = aiReadDish(t, food: food, allowed: allowed, now: now, newId: newId, needMeals: {s.meal}, needOffice: office);
      if (r.dish == null) return (null, r.errors);
      final c = check(r.dish!);
      if (c.isNotEmpty) return (null, ['Το «${r.dish!.name}» δεν είναι ανάλογο: ${c.join('· ')}.']);
      final pf = portionFor(food, r.dish!, old.kcal)!;
      return (AiSwapResult(dish: r.dish, kcal: pf.kcal, isNew: true), const <String>[]);
    },
  );
  if (fail != null) return AiSwapResult(fail: fail);
  if (res == null) {
    return AiSwapResult(errors: [
      'Δεν βρέθηκε ανάλογο φαγητό που να ταιριάζει σε θερμίδες, πρωτεΐνη και κορεσμένα, μόνο με όσα σου αρέσουν.',
      if (ready.isEmpty) 'Μπορείς να διαλέξεις μόνος σου με «Άλλαξέ το».',
      ...errs,
    ]);
  }
  return res;
}

/// Το πρόγραμμα με το νέο φαγητό στη θέση (μερίδα [kcal], ήδη στρογγυλή από το [portionFor])· το κλείδωμα μένει όπως ήταν.
WeekPlan applySwap(WeekPlan w, int day, int index, Dish d, double kcal) {
  final s = w.days[day][index];
  return w.withSlot(day, index, PlanSlot(meal: s.meal, dishId: d.id, kcal: kcal, locked: s.locked));
}

// ---------------------------------------------------------------------------
// «Έφαγα κάτι άλλο»: οι υπόλοιπες μερίδες της μέρας (κανόνες, χωρίς AI)
// ---------------------------------------------------------------------------

/// Αποτέλεσμα: το νέο πρόγραμμα, οι αλλαγές (γεύμα, φαγητό, πριν, μετά), και πώς κλείνει η μέρα (θερμίδες, πρωτεΐνη).
///
/// Έλεγχος 21/11 (K7B-02, K2-R-08): [assumed] = οι ανοιχτές θέσεις γευμάτων ως και το γεύμα που μόλις άλλαξε, που μπήκαν
/// στο σύνολο της μέρας ως «θα φαγωθούν ακόμα» (γεύμα, φαγητό, θερμίδες). Ο διάλογος το λέει: αν ένα τέτοιο γεύμα
/// έχει ήδη φαγωθεί και γραφτεί αλλιώς, το «η μέρα θα κλείσει στις …» το μετρά δύο φορές και τα επόμενα μικραίνουν λάθος.
typedef Rebalance = ({
  WeekPlan plan,
  List<(Meal, String, double, double)> changes,
  double dayKcal,
  double proteinBefore,
  double proteinAfter,
  List<(Meal, String, double)> assumed,
});

/// Έλεγχος 20/11 (K2-C-01): πόσο από τις θερμίδες των ανοιχτών θέσεων ενός προηγούμενου γεύματος πρέπει να υπάρχει στο
/// ημερολόγιο (εκτός προγράμματος) για να θεωρηθεί ότι το γεύμα φαγώθηκε ήδη.
const rebalanceEatenShare = 0.5;

/// Έλεγχος 20/11 (K2-C-01): τα γεύματα της μέρας [day], εκτός από το [changed], που γράφτηκαν στο ημερολόγιο χωρίς το
/// πρόγραμμα («+ Φαγητό», «Κι άλλο», «Όπως χθες»): όλες οι θέσεις τους είναι ακόμα ανοιχτές, και το ημερολόγιο έχει σε
/// αυτό το γεύμα τουλάχιστον το [rebalanceEatenShare] των θερμίδων τους. Οι θέσεις αυτές ΔΕΝ είναι «θα φαγωθεί ακόμα»:
/// οι θερμίδες τους είναι ήδη στο «έφαγες ως τώρα». Πριν μετριόνταν δύο φορές και το «Έφαγα κάτι άλλο» έκοβε το βραδινό
/// στο ελάχιστο χωρίς λόγο (840 → 440 kcal· η μέρα έκλεινε 600 kcal κάτω από τον στόχο). Γεύμα με θέση που σημειώθηκε από
/// το πρόγραμμα («Το έφαγα», «Έφαγα κάτι άλλο», «Δεν το έφαγα») μένει όπως πριν: εκεί οι καταχωρίσεις ανήκουν στη θέση.
///
/// Απόφαση χρήστη 21/11 (Α31· K7-R-15): ΟΛΑ τα άλλα γεύματα της μέρας, όχι μόνο τα προηγούμενα. Πριν: σνακ που φαγώθηκε το
/// πρωί και γράφτηκε με «+ Φαγητό», και μετά «Έφαγα κάτι άλλο» στο μεσημεριανό: η θέση του σνακ ήταν «επόμενο γεύμα», οι
/// θερμίδες του μετρούσαν δεύτερη φορά και η εφαρμογή άλλαζε τη μερίδα ενός σνακ που είχε ήδη φαγωθεί.
Set<Meal> mealsEatenOutsidePlan(FoodStore food, WeekPlan w, int day, {required Meal changed}) {
  final open = <Meal, double>{};
  final touched = <Meal>{};
  for (final s in w.days[day]) {
    if (slotStateNow(food, w, day, s) != SlotState.open) {
      touched.add(s.meal);
      continue;
    }
    final t = plannedTotals(food, food.dishById(s.dishId), s);
    if (t != null) open[s.meal] = (open[s.meal] ?? 0) + t.kcal;
  }
  final logged = <Meal, double>{};
  for (final e in food.entriesFor(w.dayAt(day))) {
    logged[e.meal] = (logged[e.meal] ?? 0) + Totals([e]).kcal;
  }
  return {
    for (final m in open.keys)
      if (m != changed && !touched.contains(m) && open[m]! > 0 && (logged[m] ?? 0) >= rebalanceEatenShare * open[m]!) m,
  };
}

/// Ξαναμοιράζει τις θερμίδες των ανοιχτών γευμάτων της μέρας [day] που έρχονται ΜΕΤΑ το [after] (όχι κλειδωμένα), ώστε
/// [eaten] (ό,τι γράφτηκε ήδη στο ημερολόγιο τη μέρα) + τα υπόλοιπα ≈ [target]. Κάθε μερίδα μέσα στα όριά της (0,6–1,6).
/// Όταν μικραίνουν, πρώτα το φαγητό με τη λιγότερη πρωτεΐνη ανά θερμίδα· όταν μεγαλώνουν, πρώτα το πιο πρωτεϊνούχο
/// (S-11). null αν δεν αλλάζει τίποτα.
Rebalance? rebalanceDay(
  FoodStore food,
  WeekPlan w,
  int day, {
  required double eaten,
  required double eatenProtein,
  required double target,
  required Meal after,
  required DateTime now,
}) {
  final byId = {for (final d in food.dishes) d.id: d};
  final adjust = <int>[];
  final assumed = <(Meal, String, double)>[];
  var fixedKcal = 0.0, fixedProtein = 0.0;
  final eatenOutside = mealsEatenOutsidePlan(food, w, day, changed: after);
  for (var k = 0; k < w.days[day].length; k++) {
    final s = w.days[day][k];
    if (slotStateNow(food, w, day, s) != SlotState.open) continue;
    final d = byId[s.dishId];
    final t = d == null ? null : plannedTotals(food, d, s);
    if (d == null || t == null) continue;
    if (eatenOutside.contains(s.meal)) {
      // K2-C-01, Α31: γράφτηκε με «+ Φαγητό»· είναι ήδη μέσα στο [eaten]. Ούτε «θα φαγωθεί ακόμα», ούτε αλλάζει η μερίδα του
      // (και όταν είναι επόμενο γεύμα: έχει ήδη φαγωθεί).
      continue;
    } else if (!s.locked && _mealOrder(s.meal) > _mealOrder(after) && portionRange(food, d) != null) {
      adjust.add(k);
    } else {
      fixedKcal += t.kcal;
      fixedProtein += t.protein;
      if (_mealOrder(s.meal) <= _mealOrder(after)) assumed.add((s.meal, d.name, t.kcal));
    }
  }
  if (adjust.isEmpty) return null;
  final info = <int, ({double lo, double hi, double ppk, double cur, Dish d})>{};
  for (final k in adjust) {
    final s = w.days[day][k];
    final d = byId[s.dishId]!;
    final r = portionRange(food, d)!;
    info[k] = (lo: r.lo, hi: r.hi, ppk: r.proteinPerKcal, cur: plannedTotals(food, d, s)!.kcal, d: d);
  }
  final curSum = adjust.fold(0.0, (a, k) => a + info[k]!.cur);
  final want = math.max(0.0, target - eaten - fixedKcal);
  final next = {for (final k in adjust) k: info[k]!.cur};
  var diff = want - curSum;
  final down = diff < 0;
  final order = [...adjust]..sort((a, b) => down ? info[a]!.ppk.compareTo(info[b]!.ppk) : info[b]!.ppk.compareTo(info[a]!.ppk));
  for (final k in order) {
    if (diff.abs() < 1) break;
    final i = info[k]!;
    final v = (next[k]! + diff).clamp(i.lo, i.hi).toDouble();
    diff -= v - next[k]!;
    next[k] = v;
  }
  final changes = <(Meal, String, double, double)>[];
  var out = w;
  var newSum = 0.0, newProtein = 0.0, oldProtein = 0.0;
  for (final k in adjust) {
    final i = info[k]!;
    final pf = portionFor(food, i.d, next[k]!);
    final v = pf?.kcal ?? next[k]!;
    final s = w.days[day][k];
    oldProtein += i.cur * i.ppk;
    if ((v - i.cur).abs() < 20) {
      newSum += i.cur;
      newProtein += i.cur * i.ppk;
      continue; // μικρότερο από μία κουταλιά: δεν αλλάζει
    }
    newSum += v;
    newProtein += v * i.ppk;
    out = out.withSlot(day, k, s.copyWith(kcal: v));
    changes.add((s.meal, i.d.name, i.cur, v));
  }
  if (changes.isEmpty) return null;
  return (
    plan: out,
    changes: changes,
    dayKcal: eaten + fixedKcal + newSum,
    proteinBefore: eatenProtein + fixedProtein + oldProtein,
    proteinAfter: eatenProtein + fixedProtein + newProtein,
    assumed: assumed,
  );
}
