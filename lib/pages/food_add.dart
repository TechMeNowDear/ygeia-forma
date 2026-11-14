import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data.dart' show HealthStore;
import '../food/chol.dart' show branByName, isBran;
import '../food/food_channel.dart';
import '../food/food_model.dart';
import '../food/food_search.dart' show FoodSearchResult, plain;
import '../food/food_sources.dart';
import '../food/food_store.dart';
import '../food/off.dart';
import '../food/weigh_hints.dart';
import '../format.dart';
import '../goals.dart' show defaultBranG;
import '../theme.dart';
import '../widgets.dart';
import 'my_foods.dart';
import 'nutrition.dart';

// ---------------------------------------------------------------------------
// Είσοδοι
// ---------------------------------------------------------------------------

/// Το ημερολόγιο διαβάζεται ακόμα (π.χ. πολύ αργό άνοιγμα): δεν υπάρχει «Ξαναδοκίμασε» να πατηθεί, μόνο αναμονή.
const diaryStillLoadingText = 'Το ημερολόγιο φαγητού διαβάζεται ακόμα. Δοκίμασε ξανά σε λίγο.';

/// Η ανάγνωση του ημερολογίου απέτυχε: η Διατροφή δείχνει την κάρτα «Πρόβλημα» με το «Ξαναδοκίμασε».
const diaryNotReadText = 'Δεν διαβάστηκε ακόμα το ημερολόγιο φαγητού. Πάτα «Ξαναδοκίμασε» στη Διατροφή.';

Future<void> openAddFood(BuildContext context, FoodStore food, {Meal? meal, DateTime? day, bool scan = false}) async {
  final messenger = ScaffoldMessenger.of(context);
  // Έλεγχος 9/11 (Χ6): αν δεν διαβάστηκε το ημερολόγιο, ό,τι γραφτεί μπορεί να βγει διπλό.
  // Έλεγχος round1 (S2-11): στο άνοιγμα από το widget της αρχικής οθόνης το ημερολόγιο μπορεί να διαβάζεται ακόμα·
  // περιμένουμε να τελειώσει η ανάγνωση και μετά ανοίγουμε (πριν: μήνυμα και τίποτα άλλο).
  if (!await food.waitLoaded()) {
    messenger.showSnackBar(SnackBar(content: Text(food.error != null ? diaryNotReadText : diaryStillLoadingText)));
    return;
  }
  if (!context.mounted) return;
  final shown = food.day;
  food.syncToday();
  // Κάρτα της μέρας που φαινόταν (π.χ. οθόνη ανοιχτή από χθες βράδυ): πάει στη νέα σημερινή μέρα.
  final target = day == null || sameDay(day, shown) ? food.day : day;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'Προσθήκη φαγητού'),
      builder: (_) => AddFoodScreen(food: food, meal: meal ?? mealForTime(DateTime.now()), day: target, scanOnOpen: scan),
    ),
  );
}

Future<void> openEditEntry(BuildContext context, FoodStore food, LogEntry e) async {
  final messenger = ScaffoldMessenger.of(context);
  final r = await showModalBottomSheet<_SheetResult>(
    context: context,
    routeSettings: const RouteSettings(name: 'Ποσότητα'),
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => QuantitySheet(food: food, item: e.food, initialGrams: e.grams, meal: e.meal, editing: true),
  );
  if (r == null) return;
  if (r.delete) {
    if (!await food.remove(e)) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Διαγράφηκε: ${e.food.name}'),
        persist: false,
        duration: undoSnackBarDuration,
        action: SnackBarAction(label: 'Αναίρεση', onPressed: () => food.restore(e)),
      ));
  } else {
    await food.update(e.copyWith(grams: r.grams, meal: r.meal, food: r.food.id == e.food.id ? null : r.food));
  }
}

/// Πόσο μένει ένα μήνυμα με «Αναίρεση» (round8, R8-U2-1). Από το Flutter 3.38 ένα SnackBar με κουμπί δεν κλείνει ποτέ
/// μόνο του, εκτός αν έχει `persist: false` (docs.flutter.dev, «SnackBar with action no longer auto-dismisses»)· και ο
/// ScaffoldMessenger δείχνει ένα μήνυμα τη φορά, τα άλλα περιμένουν. Έτσι το «Αναίρεση» μετά από δεύτερο φαγητό
/// έσβηνε το ΠΡΩΤΟ (το μήνυμα του δεύτερου περίμενε πίσω από το πρώτο). Τώρα κάθε τέτοιο μήνυμα κλείνει το προηγούμενο
/// (`hideCurrentSnackBar`) και κλείνει μόνο του μετά από αυτό το διάστημα.
const undoSnackBarDuration = Duration(seconds: 6);

/// Ο σαρωτής άνοιξε αλλά αυτό που έδωσε δεν είναι barcode προϊόντος (κείμενο εγκρίθηκε 12/11).
const barcodeUnreadText = 'Δεν διαβάστηκε το barcode. Δοκίμασε ξανά.';

final _numberSpaces = RegExp('[ \u{A0}\u{202F}]');
final _numberChars = RegExp(r'^[0-9.,]+$');
final _dotThousands = RegExp(r'^[1-9]\d{0,2}(\.\d{3})+$');

/// Αριθμός όπως τον γράφουμε στα ελληνικά: «12,5» ή «12.5»· η τελεία ως διαχωριστικό χιλιάδων
/// («1.000», «1.250») διαβάζεται ως χιλιάδες, όχι ως «1».
///
/// Τελικός έλεγχος (Συμβούλιο 3, Τ1): ό,τι δεν είναι καθαρά αριθμός δεν μαντεύεται, γίνεται null (το πεδίο μένει άκυρο):
/// - Μόνο ψηφία, τελείες και κόμμα. «-5», «1e3», «NaN», «Infinity» περνούσαν από το double.tryParse.
/// - Ένα κόμμα το πολύ, και μετά από αυτό καμία τελεία: «1,250.75» (αμερικάνικη γραφή) διαβαζόταν 1,25075.
/// - Τελείες πριν από το κόμμα μόνο ως σωστές χιλιάδες: «3.76,» διαβαζόταν 376 και «1.2,5» 12,5.
/// - Πάντα πεπερασμένος αριθμός.
double? parseNumber(String s) {
  var t = s.trim().replaceAll(_numberSpaces, '');
  if (t.isEmpty || !_numberChars.hasMatch(t)) return null;
  final comma = t.indexOf(',');
  if (comma >= 0) {
    if (comma != t.lastIndexOf(',') || t.indexOf('.', comma) >= 0) return null;
    final whole = t.substring(0, comma);
    if (whole.contains('.') && !_dotThousands.hasMatch(whole)) return null;
    t = '${whole.replaceAll('.', '')}.${t.substring(comma + 1)}';
  } else if (_dotThousands.hasMatch(t)) {
    t = t.replaceAll('.', '');
  }
  final v = double.tryParse(t);
  return v == null || !v.isFinite ? null : v;
}

/// Το πεδίο «Μία μερίδα» δεν γίνεται δεκτό: γράφτηκε κάτι, αλλά δεν είναι ποσότητα πάνω από 0 και ως [maxEntryGrams].
/// Κενό πεδίο = «χωρίς μερίδα», δεκτό. Τελικός έλεγχος (Συμβούλιο 3, Β3): πριν, μια άκυρη μερίδα απλώς δεν αποθηκευόταν,
/// χωρίς να το μάθεις· τώρα η αποθήκευση περιμένει και το πεδίο γράφει τι θέλει.
bool servingRejected(String text) => text.trim().isNotEmpty && validServing(parseNumber(text)) == null;

/// Το μήνυμα κάτω από το πεδίο «Μία μερίδα» (κείμενο εγκρίθηκε 12/11). Στα υγρά η μονάδα του πεδίου είναι ml.
String servingErrorText({required bool perMl}) => 'Γράψε μερίδα ως 5.000 ${perMl ? 'ml' : 'g'}, ή άφησέ το κενό.';

/// Γραμμάρια στο πεδίο: χωρίς άσκοπα δεκαδικά, αλλά χωρίς να χάνεται το «,5».
String gramsField(double v) => v == v.roundToDouble() ? '${v.round()}' : dec(v, 1);

/// Το μήνυμα κάτω από την ποσότητα όταν δεν γίνεται δεκτή. Έλεγχος round1 (U3a-12): πάνω από το όριο των 5.000 λέει το
/// όριο (πριν έλεγε «Γράψε γραμμάρια», ενώ γραμμάρια είχαν γραφτεί).
String quantityErrorText(String text, {required bool perMl}) {
  final v = parseNumber(text);
  if (v != null && v > maxEntryGrams) return 'Ως 5.000 ${perMl ? 'ml' : 'g'} τη φορά';
  return perMl ? 'Γράψε ml' : 'Γράψε γραμμάρια';
}

/// Η ερώτηση για ποσότητα που μοιάζει με λάθος πληκτρολόγησης (έλεγχος round1, S11-3): «2.000 g «Ελαιόλαδο εξαιρετικά
/// παρθένο» = 17.980 kcal σε μία καταχώριση. Είναι σωστό;».
String typoQuestion(Food f, double grams) {
  final qty = grams >= 1000 && grams == grams.roundToDouble() ? thousands(grams) : gramsField(grams);
  // Round8 (R8-U2-7): το αλάτι έχει 0 kcal· η ερώτηση λέει πόσο αλάτι θα γραφτεί («100 g «Αλάτι» = 97,8 g αλάτι …»).
  if (f.n.amount(Nk.salt) >= typoSaltPer100) {
    return '$qty ${f.unit} «${f.name}» = ${dec(f.n.amount(Nk.salt) * grams / 100, 1)} g αλάτι σε μία καταχώριση. Είναι σωστό;';
  }
  return '$qty ${f.unit} «${f.name}» = ${kcalText(f.n.amount(Nk.kcal) * grams / 100)} kcal σε μία καταχώριση. Είναι σωστό;';
}

/// Η ερώτηση «Ζύγισες πριν ή μετά το μαγείρεμα;» (round7, R7-U2-2): μία γραμμή για κάθε μορφή, με τις θερμίδες που θα
/// γράφονταν, π.χ. «300 g ξερές = 981 kcal» και «300 g βρασμένες = 375 kcal».
String rawOrCookedQuestion(double grams, List<(Food, String)> forms) {
  final qty = grams >= 1000 && grams == grams.roundToDouble() ? thousands(grams) : gramsField(grams);
  return [
    for (final (f, label) in forms) '$qty ${f.unit} ${label.toLowerCase()} = ${kcalText(f.n.amount(Nk.kcal) * grams / 100)} kcal',
  ].join('\n');
}

/// Ξηροί καρποί και σπόροι: μετριούνται με τη χούφτα (round7, R7-U2-4).
bool _nutsPortion(Food f) => f.cat == 'Ξηροί καρποί' || f.cat == 'Σπόροι' || f.cholKind == CholKind.nuts;

/// Αλάτι (από [typoSaltPer100] g στα 100) και μπαχαρικά: μετριούνται με την πρέζα και το κουταλάκι (round8, R8-U2-7).
bool _pinchPortion(Food f) => f.n.amount(Nk.salt) >= typoSaltPer100 || f.cat == 'Καρυκεύματα';

/// Οι νιφάδες βρώμης της βάσης (CIQUAL 32140).
const oatFlakesId = 'C32140';

/// Πίτουρο βρώμης και νιφάδες βρώμης: η μερίδα του πλάνου, 40 g (round8, R8-U2 Β1).
bool _oatPortion(Food f) => isBran(f) || f.id == oatFlakesId;

/// Η πρώτη ποσότητα για τρόφιμο που δεν έχεις γράψει ποτέ και δεν έχει μερίδα (round7, R7-U2-4). Πριν ήταν πάντα 100 g:
/// 100 g καρύδια = 709 kcal (το πλάνο λέει 30 g), και 100 g λάδι ενεργοποιούσαν τον δικό τους έλεγχο λάθους.
/// Λάδι, βούτυρο, μαγιονέζα, μαργαρίνη, ελιές: 10 g (περίπου μία κουταλιά)· ξηροί καρποί και σπόροι: 30 g· τα άλλα 100 g.
/// Round8: ταχίνι, φυστικοβούτυρο, πραλίνα 15 g (μία κουταλιά· [isSpoonFood], R8-A2-1)· αλάτι και μπαχαρικά 2 g
/// (R8-U2-7· πριν 100 g αλάτι)· πίτουρο βρώμης η ποσότητα του πλάνου σου ([branG], αλλιώς 40 g) και νιφάδες βρώμης 40 g
/// (R8-U2 Β1).
double firstGrams(Food f, {int? branG}) {
  if (_pinchPortion(f)) return 2;
  if (isSpoonFood(f)) return f.cat == 'Αλείμματα' ? 15 : 10;
  if (isOlives(f)) return 10;
  if (_nutsPortion(f)) return 30;
  if (isBran(f)) return (branG != null && branG > 0 ? branG : defaultBranG).toDouble();
  if (f.id == oatFlakesId) return 40;
  return 100;
}

/// Η μέρα στην οποία γράφεται ένα φαγητό, όπως τη λέει η οθόνη προσθήκης: «Σήμερα · Παρ 13/11», «Χθες · Πέμ 12/11»,
/// ή για παλιότερη μέρα «Τρί 10/11» (έλεγχος round1, S2-8 / S11-1 / U3a-1: πριν η οθόνη δεν έλεγε πουθενά τη μέρα).
/// Round 2 (R2-U1-11): η ημερομηνία «Σάβ 24/10» δεν σπάει ποτέ σε δύο γραμμές (με γράμματα 2× έμενε «Σάβ | 24/10»).
String entryDayLabel(DateTime day, DateTime today) {
  final d = dayOf(day), t = dayOf(today);
  final date = shortDayDate(d).replaceAll(' ', '\u00A0');
  if (sameDay(d, t)) return 'Σήμερα · $date';
  if (sameDay(d, DateTime(t.year, t.month, t.day - 1))) return 'Χθες · $date';
  return date;
}

/// Επιλογή γεύματος: 4 ίσα κουμπιά που χωράνε πάντα σε μία γραμμή.
class MealPicker extends StatelessWidget {
  const MealPicker({super.key, required this.value, required this.onChanged, this.grid = false});
  final Meal value;
  final ValueChanged<Meal> onChanged;

  /// Σχέδια 9/11 (9α): με μεγάλα γράμματα τα γεύματα σε 2×2, ποτέ μικρυμένα ή κομμένα.
  final bool grid;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    if (grid) {
      Widget b(Meal m) => Expanded(
            child: Material(
              color: m == value ? c.foodSolid : c.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: m == value ? c.foodSolid : c.hairline, width: 1.5),
              ),
              child: InkWell(
                key: ValueKey('meal-${m.name}'),
                customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onTap: () => onChanged(m),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                      child: Text(mealLabel(m),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: m == value ? c.onSolid : c.text)),
                    ),
                  ),
                ),
              ),
            ),
          );
      const v = Meal.values;
      return LayoutBuilder(builder: (context, box) {
        // Αν ένα όνομα γεύματος δεν χωρά ολόκληρο σε μισό πλάτος: ένα κουμπί ανά γραμμή (ποτέ «Μεσημέρ/ι»).
        final half = (box.maxWidth - 8) / 2 - 12;
        if (!wordsFit(context, [for (final m in v) mealLabel(m)], const TextStyle(fontSize: 15, fontWeight: FontWeight.w600), half)) {
          return Column(key: const ValueKey('meal-list'), children: [
            for (var k = 0; k < v.length; k++) ...[if (k > 0) const SizedBox(height: 8), Row(children: [b(v[k])])],
          ]);
        }
        return Column(children: [
          Row(children: [b(v[0]), const SizedBox(width: 8), b(v[1])]),
          const SizedBox(height: 8),
          Row(children: [b(v[2]), const SizedBox(width: 8), b(v[3])]),
        ]);
      });
    }
    // Έλεγχος round1 (U3a-8): ΕΝΑ μέγεθος γραμμάτων και για τα τέσσερα γεύματα. Αν το πιο φαρδύ όνομα («Μεσημέρι») δεν
    // χωρά στο κουμπί του, μικραίνουν όλα μαζί· πριν μίκραινε μόνο εκείνο και φαινόταν πιο μικρό από τα διπλανά του.
    return LayoutBuilder(builder: (context, box) {
      const style = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
      final scaler = MediaQuery.textScalerOf(context);
      final base = DefaultTextStyle.of(context).style;
      var widest = 0.0;
      for (final m in Meal.values) {
        final tp = TextPainter(
            text: TextSpan(text: mealLabel(m), style: base.merge(style)), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)
          ..layout();
        if (tp.width > widest) widest = tp.width;
        tp.dispose();
      }
      // Χώρος κάθε ονόματος: το ένα τέταρτο του πλαισίου, χωρίς τα περιθώρια (4 + 4 του πλαισίου, 4 + 4 του κουμπιού).
      final room = (box.maxWidth - 8) / 4 - 8;
      final double fontSize = widest > room && room > 0 ? 14 * (room / widest).clamp(0.5, 1.0).toDouble() : 14.0;
      // Round8 (R8-U2-6): κάθε γεύμα πατιέται σε ύψος τουλάχιστον 48 dp (4 + 40 + 4: το πάνω και κάτω περιθώριο του
      // πλαισίου ανήκει πια στο κουμπί) και το TalkBack λέει ποιο είναι επιλεγμένο. Πριν η περιοχή αφής ήταν 38 dp και
      // ένα πάτημα στο περιθώριο των 4 dp χανόταν.
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.hairline)),
        child: Row(
          children: [
            for (final m in Meal.values)
              Expanded(
                child: MergeSemantics(
                  child: Semantics(
                    button: true,
                    selected: m == value,
                    child: GestureDetector(
                      key: ValueKey('meal-bar-${m.name}'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(m),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          constraints: const BoxConstraints(minHeight: 40),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                          decoration: BoxDecoration(
                            color: m == value ? c.foodSolid : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          // Το FittedBox μένει μόνο ως δίχτυ ασφαλείας (διαφορά ενός pixel)· το μέγεθος το ορίζει το [fontSize].
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              mealLabel(m),
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: fontSize,
                                fontWeight: FontWeight.w600,
                                color: m == value ? c.onSolid : c.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Αναζήτηση και προσθήκη
// ---------------------------------------------------------------------------

class AddFoodScreen extends StatefulWidget {
  const AddFoodScreen({super.key, required this.food, required this.meal, required this.day, this.clock, this.scanOnOpen = false});
  final FoodStore food;

  /// Ανοίγει αμέσως τον σαρωτή barcode (από το widget «Γρήγορο φαγητό», 13/11). Αν ο σαρωτής κλείσει χωρίς αποτέλεσμα,
  /// μένει η κανονική οθόνη αναζήτησης.
  final bool scanOnOpen;
  final Meal meal;
  final DateTime day;

  /// Για δοκιμές: η ώρα «τώρα». Χωρίς αυτό, η ερώτηση «σε ποια μέρα;» γίνεται μόνο στο κινητό (όχι στα στιγμιότυπα).
  final DateTime Function()? clock;

  @override
  State<AddFoodScreen> createState() => _AddFoodScreenState();
}

class _AddFoodScreenState extends State<AddFoodScreen> {
  final _query = TextEditingController();
  late Meal _meal = widget.meal;
  bool _busy = false;
  bool _moreRecent = false;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  /// Πότε άνοιξε η οθόνη (για να φανεί αν πέρασαν τα μεσάνυχτα όσο ήταν ανοιχτή).
  late final DateTime _openedAt;

  @override
  void initState() {
    super.initState();
    _openedAt = _now();
    if (widget.scanOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_busy) _scan();
      });
    }
  }

  /// Η μέρα που διάλεξε ο χρήστης στην ερώτηση «σε ποια μέρα;» (μία φορά για όσο είναι ανοιχτή η οθόνη).
  DateTime? _dayChoice;

  /// «Σήμερα» για αυτή την οθόνη: το ρολόι του κινητού. Στις δοκιμές και στα στιγμιότυπα χωρίς ρολόι (όπου δεν γίνεται
  /// ούτε η ερώτηση «σε ποια μέρα;») είναι η μέρα με την οποία άνοιξε η οθόνη.
  DateTime _today() => widget.clock == null && !widget.food.followsClock ? dayOf(widget.day) : dayOf(_now());

  /// Η μέρα στην οποία θα γραφτεί ό,τι προστεθεί τώρα (όπως τη δείχνει η γραμμή «Μέρα: …»).
  DateTime get _writeDay => _dayChoice ?? dayOf(widget.day);

  /// Σε ποια μέρα γράφεται το φαγητό (έλεγχος 9/11, Χ11 και RT-14):
  /// - η οθόνη άνοιξε «σήμερα» και στο μεταξύ πέρασαν τα μεσάνυχτα → ρωτά «χθες ή σήμερα;» (πριν πήγαινε σιωπηλά χθες)·
  /// - 00:00–03:59 και η μέρα είναι η σημερινή → ρωτά, γιατί το βραδινό συχνά γράφεται μετά τα μεσάνυχτα.
  /// null αν έκλεισε την ερώτηση χωρίς απάντηση.
  Future<DateTime?> _targetDay() async {
    final chosen = _dayChoice;
    if (chosen != null) return chosen;
    final opened = dayOf(widget.day);
    if (widget.clock == null && !widget.food.followsClock) return opened;
    final now = _now();
    final today = dayOf(now);
    DateTime? other;
    if (sameDay(opened, dayOf(_openedAt)) && !sameDay(opened, today)) {
      other = today;
    } else if (sameDay(opened, today) && now.hour < 4) {
      other = DateTime(today.year, today.month, today.day - 1);
    }
    if (other == null) return opened;
    final yesterday = other.isBefore(opened) ? other : opened;
    // Χωρίς κλείσιμο με πάτημα έξω ή «πίσω»: αλλιώς η ποσότητα που γράφτηκε χανόταν χωρίς μήνυμα (έλεγχος fix-food, 4.3).
    final pick = await showDialog<DateTime>(
      context: context,
      barrierDismissible: false,
      routeSettings: const RouteSettings(name: 'Σε ποια μέρα'),
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
        title: const Text('Σε ποια μέρα;'),
        content: const Text('Πέρασαν τα μεσάνυχτα. Είναι το χθεσινό βραδινό ή φαγητό της νέας μέρας;'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, yesterday),
            child: Text('Χθες (${shortDayDate(yesterday)})'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx, today), child: const Text('Σήμερα')),
        ],
      ),
      ),
    );
    if (pick != null) _dayChoice = pick;
    return pick;
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _pick(Food f) async {
    final r = await showModalBottomSheet<_SheetResult>(
      context: context,
      routeSettings: const RouteSettings(name: 'Ποσότητα'),
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => QuantitySheet(
        food: widget.food,
        item: f,
        initialGrams:
            widget.food.lastGrams(f.id) ?? f.servingGrams ?? firstGrams(f, branG: HealthStore.shared?.goals?.branG),
        meal: _meal,
      ),
    );
    if (r == null || !mounted) return;
    final day = await _targetDay();
    if (day == null || !mounted) return;
    final e = await widget.food.add(r.food, r.grams, r.meal, on: day, now: _now());
    if (!mounted) return;
    if (!widget.food.isSaved(e)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Δεν αποθηκεύτηκε: ${r.food.name}. Δοκίμασε ξανά.'),
      ));
      return;
    }
    // Έλεγχος round1 (S2-8 / S11-1): αν δεν γράφτηκε στη σημερινή μέρα, το μήνυμα λέει σε ποια.
    final today = _today();
    final where = sameDay(day, today) ? 'Προστέθηκε' : 'Προστέθηκε (${entryDayLabel(day, today)})';
    // Round8 (R8-U2-1): το μήνυμα του προηγούμενου φαγητού κλείνει, ώστε το «Αναίρεση» να είναι ΠΑΝΤΑ του τελευταίου.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('$where: ${r.food.name}, ${gramsText(r.grams)} ${r.food.unit}'),
        persist: false,
        duration: undoSnackBarDuration,
        action: SnackBarAction(label: 'Αναίρεση', onPressed: () => widget.food.remove(e)),
      ));
    setState(() => _meal = r.meal);
  }

  Future<void> _newFood({FoodDraft? draft}) async {
    final f = await createFood(context, widget.food, draft: draft);
    if (f != null && mounted) await _pick(f);
  }

  Future<void> _scan() async {
    // Έλεγχος round1 (S2-5): αν η οθόνη έκλεισε όσο έψαχνε στο Open Food Facts, δεν γίνεται setState σε κλειστή οθόνη
    // (πριν: σφάλμα στην αναφορά σφαλμάτων κάθε φορά).
    final f = await scanToFood(context, widget.food, onBusy: (b) {
      if (mounted) setState(() => _busy = b);
    });
    if (f != null && mounted) await _pick(f);
  }

  @override
  Widget build(BuildContext context) => FoodTheme(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final c = Aigaio.of(context);
    final q = _query.text;
    final found = q.trim().isEmpty ? null : widget.food.find(q);
    final results = found?.foods ?? const <Food>[];
    // Έλεγχος 9/11 (Υ3): αν βρέθηκε μόνο χωρίς μια λέξη ή με διόρθωση, το λέμε (να μη μοιάζει ακριβής απάντηση).
    // Ανεξάρτητος έλεγχος του fix-food (3.3): αν αγνοήθηκε λέξη που αλλάζει τη διατροφή («γάλα σόγιας», «μπύρα χωρίς
    // αλκοόλ», «σοκολάτα χωρίς ζάχαρη») ή ένα άλλο τρόφιμο («γιαούρτι με μέλι»), τα αποτελέσματα είναι ΑΛΛΟ τρόφιμο:
    // έντονη προειδοποίηση, όχι γκρι σημείωση. Ο τρόπος μαγειρέματος («χταπόδι ψητό») μένει απλή σημείωση.
    final kept = found?.kept.join(' ') ?? '';
    final strong = found != null && results.isNotEmpty && strongSearchWarning(found);
    final note = found == null || results.isEmpty
        ? null
        : found.corrected.isNotEmpty
            ? 'Δεν βρέθηκε ${found.corrected.keys.map((w) => '«$w»').join(', ')}. '
                'Αποτελέσματα για ${found.corrected.values.map((w) => '«$w»').join(', ')}.'
            : found.ignored.isEmpty
                ? null
                : strong
                    ? 'Δεν έχουμε «${q.trim()}». Τα παρακάτω είναι για «$kept»: άλλο τρόφιμο, με άλλες θερμίδες. Αν είναι '
                        'συσκευασμένο, πάτα «Σάρωση» ή «Από ετικέτα» (πιο πάνω)· αν είναι σπιτικό, γράψε '
                        'χωριστά και τα υπόλοιπα υλικά.'
                    : kept.isEmpty
                        ? 'Δεν βρέθηκε με όλες τις λέξεις. Αποτελέσματα χωρίς ${found.ignored.map((w) => '«$w»').join(', ')}.'
                        : 'Δεν βρέθηκε «${q.trim()}». Αποτελέσματα για «$kept».';
    // Έλεγχος premium (S3): λίγα από το καθένα (όπως ο πίνακας 10α), ώστε τα «Δικά μου» να φαίνονται χωρίς κύλιση
    // πολλών οθονών· «Περισσότερα πρόσφατα» ανοίγει ως 10.
    final allRecent = widget.food.recent(limit: 10);
    final recent = _moreRecent ? allRecent : allRecent.take(3).toList();
    // «Συχνά»: όσα τρως συχνά αλλά δεν είναι ήδη στα «Πρόσφατα» (αλλιώς οι δύο λίστες βγαίνουν ίδιες).
    final recentIds = {for (final f in recent) f.id};
    final frequent = [for (final f in widget.food.frequent(limit: 25)) if (!recentIds.contains(f.id)) f].take(4).toList();

    // Σχέδια 9/11 (10α): Συχνά → Πρόσφατα → Δικά μου. Τα δικά μου που φαίνονται ήδη πιο πάνω δεν ξαναμπαίνουν.
    final shownIds = {...recentIds, for (final f in frequent) f.id};
    final allMine = widget.food.mine;
    final mine = [for (final f in allMine) if (!shownIds.contains(f.id)) f].take(3).toList();

    Widget head(String title, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 8, 2),
          child: Row(children: [
            Expanded(
              child: Text(upperGr(title),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: .6, color: c.textSecondary)),
            ),
            if (trailing != null) trailing,
          ]),
        );
    Widget section(String title, List<Food> foods, {Widget? trailing, bool more = false}) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            head(title, trailing: trailing),
            for (var k = 0; k < foods.length; k++)
              _FoodTile(
                food: foods[k],
                store: widget.food,
                onTap: () => _pick(foods[k]),
                onMore: more ? () => myFoodActions(context, widget.food, foods[k]) : null,
                badge: !more,
                line: k < foods.length - 1,
              ),
          ],
        );
    // Έλεγχος round1 (U3a-5): αν οι δύο ετικέτες δεν χωρούν ολόκληρες δίπλα δίπλα (μεγάλα γράμματα σε στενή οθόνη), τα
    // κουμπιά πάνε το ένα κάτω από το άλλο· πριν κόβονταν σε «Σάρω…» και «Από ε…». (U3a-18: ίδιο εικονίδιο για το
    // «Από ετικέτα» με «Τα προϊόντα μου».)
    Widget tool(String keyName, String text, IconData icon, VoidCallback? onPressed, {required bool oneLine}) =>
        OutlinedButton.icon(
          key: ValueKey(keyName),
          onPressed: onPressed,
          icon: Icon(icon, size: 20),
          label: oneLine ? Text(text, maxLines: 1, overflow: TextOverflow.ellipsis) : Text(text),
        );
    final tools = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: LayoutBuilder(builder: (context, box) {
        // Ο χώρος της ετικέτας σε κάθε μισό κουμπί: χωρίς το εικονίδιο (20), το κενό του (8) και τα περιθώρια του κουμπιού
        // (16 + 24 στο 1,0×· με μεγαλύτερα γράμματα το Material τα μικραίνει, άρα εδώ μένει πάντα λίγος χώρος παραπάνω).
        // «Από ετικέτα» με αδιάσπαστο κενό: μετριέται ΟΛΗ η ετικέτα, γιατί στο κουμπί πρέπει να χωρά σε μία γραμμή.
        final room = (box.maxWidth - 10) / 2 - 68;
        final sideBySide = wordsFit(
            context, const ['Σάρωση', 'Από\u00A0ετικέτα'], const TextStyle(fontSize: 15, fontWeight: FontWeight.w600), room);
        final scan = tool('add-scan', 'Σάρωση', Icons.qr_code_scanner_rounded, _busy ? null : _scan, oneLine: sideBySide);
        final label = tool('add-label', 'Από ετικέτα', Icons.edit_note_rounded,
            () => _newFood(draft: FoodDraft(name: q.trim())), oneLine: sideBySide);
        if (sideBySide) {
          return Row(children: [Expanded(child: scan), const SizedBox(width: 10), Expanded(child: label)]);
        }
        return Column(
          key: const ValueKey('add-tools-stacked'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [scan, const SizedBox(height: 8), label],
        );
      }),
    );

    // Έλεγχος round1 (S2-8 / S11-1 / U3a-1): η οθόνη λέει ΠΑΝΤΑ σε ποια μέρα γράφει, και έντονα όταν δεν είναι η
    // σημερινή (πριν, φαγητό μπορούσε να πάει σε άλλη μέρα χωρίς να φαίνεται πουθενά).
    final writeDay = _writeDay;
    final otherDay = !sameDay(writeDay, _today());
    final dayLine = Padding(
      key: const ValueKey('add-day'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.event_rounded, size: 16, color: otherDay ? c.warn : c.textSecondary),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Μέρα: ${entryDayLabel(writeDay, _today())}',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: otherDay ? FontWeight.w700 : FontWeight.w500,
                color: otherDay ? c.warn : c.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );

    // Έλεγχος round1 (U3a-4): με μεγάλα γράμματα το κουτί αναζήτησης και τα γεύματα ψηλώνουν· τα ύψη της μπάρας
    // μεγαλώνουν μαζί τους. Πριν έμεναν 64 + 60 dp και από 1,3× το κουτί έχανε την πάνω και την κάτω γραμμή του.
    final bigger = math.max(0.0, MediaQuery.textScalerOf(context).scale(17) / 17 - 1);
    // Round7 (R7-U2-9): από 1,3× γράμματα τα γεύματα σε 2 × 2 (όπως στο φύλλο ποσότητας), στην αρχή της λίστας. Στη μία
    // σειρά της μπάρας μίκραιναν στο μισό για να χωρέσουν, και με γράμματα 2× έμεναν σχεδόν όσο στο 1×.
    final large = MediaQuery.textScalerOf(context).scale(10) >= 12.5;
    final mealPicker = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: MealPicker(value: _meal, grid: large, onChanged: (m) => setState(() => _meal = m)),
    );

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        toolbarHeight: 64 + bigger * 26,
        // Σχέδια 9/11 (10α): η αναζήτηση σε κουτί, «Σάρωση» και «Από ετικέτα» ως κουμπιά πιο κάτω (όχι εικονίδιο).
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Container(
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.hairline),
            ),
            child: TextField(
              controller: _query,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              style: TextStyle(fontSize: 17, color: c.text),
              decoration: InputDecoration(
                hintText: 'Ψάξε φαγητό ή μάρκα',
                hintStyle: TextStyle(color: c.textTertiary, fontSize: 17),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
                prefixIcon: Icon(Icons.search_rounded, color: c.textSecondary),
                suffixIcon: q.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Καθάρισμα',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(_query.clear),
                      ),
              ),
            ),
          ),
        ),
        bottom: large
            ? null
            : PreferredSize(
                // Round8 (R8-U2-6): 64 (πριν 60): τα γεύματα πατιούνται σε 48 dp, μέσα σε πλαίσιο 50 dp.
                preferredSize: Size.fromHeight(64 + bigger * 30),
                child: Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 10), child: mealPicker),
              ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          // Η γραμμή «Μέρα: …» μένει πάντα στη θέση της, πάνω από τη λίστα που κυλά.
          child: Column(children: [
            dayLine,
            Expanded(
              child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.only(bottom: 40),
                children: [
                  if (large) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: Center(child: mealPicker)),
                  tools,
                  if (q.trim().isEmpty) ...[
                    if (frequent.isNotEmpty) section('Συχνά', frequent),
                    if (recent.isNotEmpty) section('Πρόσφατα', recent),
                    if (!_moreRecent && allRecent.length > recent.length)
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            key: const ValueKey('add-more-recent'),
                            onPressed: () => setState(() => _moreRecent = true),
                            child: const Text('Περισσότερα πρόσφατα'),
                          ),
                        ),
                      ),
                    if (recent.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                        child: Text(
                          'Γράψε τι έφαγες, με ή χωρίς τόνους, ακόμα και σε greeklish («fakes», «kotopoulo»). '
                          'Για συσκευασμένα προϊόντα πάτα «Σάρωση».',
                          style: TextStyle(color: c.textSecondary, fontSize: 15, height: 1.45),
                        ),
                      ),
                    if (allMine.isNotEmpty)
                      KeyedSubtree(
                        key: const ValueKey('add-mine'),
                        child: section(
                          'Δικά μου',
                          mine,
                          more: true,
                          trailing: TextButton(
                            key: const ValueKey('add-mine-all'),
                            // Round7 (R7-U2-7): από εδώ ένα πάτημα στο προϊόν το γράφει (ανοίγει την ποσότητα), όπως στη
                            // λίστα «Δικά μου»· πριν άνοιγε μόνο διόρθωση/διαγραφή και έπρεπε να γυρίσεις πίσω να το ψάξεις.
                            onPressed: () async {
                              final f = await Navigator.of(context).push<Food>(MaterialPageRoute<Food>(
                                  settings: const RouteSettings(name: 'Τα προϊόντα μου'),
                                  builder: (_) => MyFoodsScreen(food: widget.food, pick: true)));
                              if (f != null && mounted) await _pick(f);
                            },
                            child: Text('Όλα (${allMine.length}) ›'),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                      child: Text(
                        'Νέο δικό σου προϊόν: «Σάρωση» ή «Από ετικέτα». Τα δικά σου βγαίνουν και όταν ψάχνεις.',
                        style: TextStyle(color: c.textSecondary, fontSize: 13.5, height: 1.4),
                      ),
                    ),
                  ] else if (results.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                      child: Text(
                        // Έλεγχος round1 (U3a-18): με τα ονόματα των δύο κουμπιών, όπως και η κάρτα «άλλο τρόφιμο».
                        // Round7 (R7-U2-14): χωρίς το κενό που αφήνει το πληκτρολόγιο μετά από πρόταση λέξης («σαλάτα »).
                        'Δεν βρέθηκε «${q.trim()}» στη βάση. Αν είναι συσκευασμένο, πάτα «Σάρωση» ή «Από ετικέτα». '
                        'Αν δεν έχει ετικέτα (π.χ. σπιτικό φαγητό), πρόσθεσε ένα-ένα τα υλικά του.',
                        style: TextStyle(color: c.textSecondary, fontSize: 15, height: 1.45),
                      ),
                    )
                  else ...[
                    if (note != null && strong)
                      Container(
                        key: const ValueKey('search-warning'),
                        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: c.warnBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.warnLine)),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 20, color: c.warn),
                            const SizedBox(width: 10),
                            Expanded(child: Text(note, style: TextStyle(fontSize: 14, height: 1.4, color: c.text))),
                          ],
                        ),
                      )
                    else if (note != null)
                      Padding(
                        key: const ValueKey('search-note'),
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded, size: 18, color: c.textSecondary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(note, style: TextStyle(fontSize: 13.5, height: 1.35, color: c.textSecondary)),
                            ),
                          ],
                        ),
                      ),
                    for (var k = 0; k < results.length; k++)
                      _FoodTile(
                        food: results[k],
                        store: widget.food,
                        onTap: () => _pick(results[k]),
                        line: k < results.length - 1,
                      ),
                  ],
                ],
              ),
              if (_busy)
                const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 3)),
            ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _FoodTile extends StatelessWidget {
  const _FoodTile({required this.food, required this.store, required this.onTap, this.onMore, this.line = false, this.badge = true});

  /// Ετικέτα «δικό μου»/μάρκα· όχι μέσα στην ενότητα «Δικά μου», όπου περισσεύει (N8).
  final bool badge;
  final Food food;
  final FoodStore store;
  final VoidCallback onTap;

  /// ⋮ για αλλαγή (μόνο στα δικά μου).
  final VoidCallback? onMore;

  /// Λεπτή γραμμή από κάτω (ανάμεσα σε γραμμές της ίδιας ενότητας).
  final bool line;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final times = store.timesEaten(food.id);
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.fromLTRB(4, 11, 0, 11),
        decoration: line ? BoxDecoration(border: Border(bottom: BorderSide(color: c.hairline))) : null,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    food.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: c.text),
                  ),
                  if (food.isMine && badge)
                    Padding(
                      padding: const EdgeInsets.only(top: 3, bottom: 1),
                      child: MineBadge(text: food.brand ?? 'δικό μου'),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    foodTileSubtitle(food, times),
                    style: TextStyle(fontSize: 13, color: c.textSecondary, fontFeatures: tabular),
                  ),
                ],
              ),
            ),
            if (onMore != null)
              IconButton(
                key: ValueKey('mine-more-${food.id}'),
                tooltip: 'Αλλαγή',
                onPressed: onMore,
                icon: Icon(Icons.more_vert_rounded, color: c.textSecondary),
              ),
            Icon(Icons.add_circle_outline_rounded, color: c.food, size: 28),
          ],
        ),
      ),
    );
  }
}

/// Η δεύτερη γραμμή ενός τροφίμου στις λίστες: «125 kcal · πρωτεΐνη 10,1 g ανά 100 g · 6 φορές». Έλεγχος round1
/// (U3a-6): ανάμεσα σε κάθε αριθμό και στη λέξη του το κενό δεν σπάει (U+00A0)· πριν, στο τέλος της γραμμής έμενε ο
/// αριθμός μόνος του («… · 6» / «φορές», «ανά 100» / «g»).
String foodTileSubtitle(Food food, int times) {
  const nb = '\u00A0';
  final n = food.n;
  final base = '${kcalText(n.amount(Nk.kcal))}${nb}kcal · πρωτεΐνη ${nValueText(n[Nk.protein])}${nb}g ανά 100$nb${food.unit}';
  return times > 0 ? '$base · ${times == 1 ? '1${nb}φορά' : '$times${nb}φορές'}' : base;
}

/// Μικρή ετικέτα για τα προϊόντα μου (μάρκα), ώστε να ξεχωρίζουν από τα γενικά.
class MineBadge extends StatelessWidget {
  const MineBadge({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: c.tint(c.primary), borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sell_outlined, size: 12, color: c.primary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.primary),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ποσότητα
// ---------------------------------------------------------------------------

class _SheetResult {
  _SheetResult(this.grams, this.meal, this.food, {this.delete = false});
  final double grams;
  final Meal meal;

  /// Η μορφή που διάλεξε (ωμό/βρασμένο/ψητό…): μπορεί να διαφέρει από αυτή που άνοιξε.
  final Food food;
  final bool delete;
}

class QuantitySheet extends StatefulWidget {
  const QuantitySheet({
    super.key,
    required this.food,
    required this.item,
    required this.initialGrams,
    required this.meal,
    this.editing = false,
  });
  final FoodStore food;
  final Food item;
  final double initialGrams;
  final Meal meal;
  final bool editing;

  @override
  State<QuantitySheet> createState() => _QuantitySheetState();
}

class _QuantitySheetState extends State<QuantitySheet> {
  late final _grams = TextEditingController(text: gramsField(widget.initialGrams));
  late Meal _meal = widget.meal;
  late Food _item = widget.item;
  late final List<(Food, String)> _states = widget.food.statesOf(widget.item);

  // Έλεγχος round1 (U3a-12): το πρώτο άγγιγμα στο πεδίο διαλέγει όλο τον αριθμό, ώστε ό,τι γράψεις να τον αντικαθιστά
  // (πριν: σβήσιμο ψηφίο-ψηφίο). Το επόμενο άγγιγμα βάζει κανονικά τον δρομέα. Ξανά από την αρχή όταν το πεδίο χάσει
  // την εστίαση.
  final _gramsFocus = FocusNode();
  bool _selectAllOnTap = true;

  void _onGramsFocus() {
    if (!_gramsFocus.hasFocus) _selectAllOnTap = true;
  }

  void _onGramsTap() {
    if (!_selectAllOnTap) return;
    _selectAllOnTap = false;
    _grams.selection = TextSelection(baseOffset: 0, extentOffset: _grams.text.length);
  }

  @override
  void initState() {
    super.initState();
    _gramsFocus.addListener(_onGramsFocus);
  }

  @override
  void dispose() {
    _gramsFocus.dispose();
    _grams.dispose();
    super.dispose();
  }

  double? get _value {
    final v = parseNumber(_grams.text);
    return (v == null || !(v > 0 && v <= maxEntryGrams)) ? null : v;
  }

  void _set(double g) => setState(() => _grams.text = gramsField(g));

  /// «Προσθήκη» / «Αποθήκευση». Έλεγχος round1 (S11-3): ποσότητα που μοιάζει με λάθος πληκτρολόγησης
  /// ([entryLooksLikeTypo], π.χ. 2.000 g λάδι αντί για 20) ζητά πρώτα ΜΙΑ επιβεβαίωση, με τις θερμίδες που θα γραφτούν.
  /// Δεν μπλοκάρει τίποτα: με «Ναι, σωστό» γράφεται όπως είναι. Καταχώριση που ανοίγει για αλλαγή και μένει με την ίδια
  /// ποσότητα και το ίδιο τρόφιμο (π.χ. αλλάζει μόνο το γεύμα) δεν ξαναρωτιέται.
  ///
  /// Round7 (R7-U2-2): ξερά όσπρια, ρύζι, ζυμαρικά από 150 g, που δεν έχεις γράψει ποτέ ([askRawOrCooked]), ρωτούν πρώτα
  /// «πριν ή μετά το μαγείρεμα;» με τις θερμίδες της κάθε μορφής· η απάντηση αλλάζει τη μορφή που γράφεται. Αν κράτησες
  /// την ξερή, δεν ξαναρωτά «Σωστή ποσότητα;» (είδες ήδη τις θερμίδες). Round7 (R7-A2-3): ο έλεγχος λάθους ξέρει και την
  /// ποσότητα της τελευταίας φοράς.
  Future<void> _submit(double g) async {
    final unchanged = widget.editing && g == widget.initialGrams && _item.id == widget.item.id;
    var item = _item;
    var keptRaw = false;
    if (!unchanged && _states.length > 1 && askRawOrCooked(item, g, timesEaten: widget.food.timesEaten(item.id))) {
      final raw = _states.first;
      final rawWord = raw.$2.split(' (').first;
      final cooked = _states.skip(1).toList();
      final pick = await showDialog<Food>(
        context: context,
        routeSettings: const RouteSettings(name: 'Ξερό ή μαγειρεμένο'),
        builder: (ctx) => AlertDialog(
          title: const Text('Ζύγισες πριν ή μετά το μαγείρεμα;'),
          content: Text(rawOrCookedQuestion(g, [(raw.$1, rawWord), ...cooked])),
          actions: [
            for (final st in cooked) TextButton(onPressed: () => Navigator.pop(ctx, st.$1), child: Text(st.$2)),
            FilledButton(onPressed: () => Navigator.pop(ctx, raw.$1), child: Text(rawWord)),
          ],
        ),
      );
      if (pick == null || !mounted) return;
      keptRaw = pick.id == item.id;
      if (!keptRaw) {
        item = pick;
        setState(() => _item = pick);
      }
    }
    if (!unchanged && !keptRaw && entryLooksLikeTypo(item, g, lastGrams: widget.food.lastGrams(item.id))) {
      final ok = await showDialog<bool>(
        context: context,
        routeSettings: const RouteSettings(name: 'Έλεγχος ποσότητας'),
        builder: (ctx) => AlertDialog(
          title: const Text('Σωστή ποσότητα;'),
          content: Text(typoQuestion(item, g)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Όχι, θα τη διορθώσω')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ναι, σωστό')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    Navigator.pop(context, _SheetResult(g, _meal, item));
  }

  @override
  Widget build(BuildContext context) => FoodTheme(child: Builder(builder: _build));

  /// Χωρούν ολόκληρες οι λέξεις των θρεπτικών σε πλακίδια 2×2; (πλάτος φύλλου ως 560, μείον περιθώρια)
  bool _tilesFit(BuildContext context) {
    final w = math.min(MediaQuery.sizeOf(context).width - 44, 560.0);
    return wordsFit(context, const ['Υδατάνθρακες', 'Πρωτεΐνη', 'Λιπαρά'], const TextStyle(fontSize: 13), (w - 8) / 2 - 24 - 12);
  }

  Widget _build(BuildContext context) {
    final c = Aigaio.of(context);
    final f = _item;
    final g = _value;
    final unit = f.unit;
    double tot(String k) => g == null ? 0 : f.n.amount(k) * g / 100;
    // Round8 (R8-U2-7): στο αλάτι (0 kcal, 0 g πρωτεΐνη, υδατάνθρακες, λιπαρά) το τέταρτο πλακίδιο λέει πόσο αλάτι γράφεται.
    final saltTile = f.n.amount(Nk.salt) >= typoSaltPer100;
    final lastLabel = saltTile ? 'Αλάτι' : 'Λιπαρά';
    final lastValue = saltTile ? '${dec(tot(Nk.salt), 1)} g' : '${gramsText(tot(Nk.fat))} g';
    final lastColor = saltTile ? c.textTertiary : fatColor(c);

    final chips = <(String, double)>[
      if (f.servingGrams != null && f.servingGrams! > 0)
        ('1 μερίδα (${gramsText(f.servingGrams!)} $unit)', f.servingGrams!),
      // Υγρά ανά 100 ml (έλεγχος 9/11, Μ2): ποτήρι, κουτάκι.
      // Έλεγχος round1 (U3a-13): λάδι, βούτυρο και άλλα σχεδόν καθαρά λίπη μετριούνται με το κουταλάκι και την κουταλιά
      // (5, 10, 15, 30)· πριν το λάδι σε ml είχε «100, 200, 250, 330 ml» (ένα πάτημα = 824 kcal).
      // Round7 (R7-U2-4): ξηροί καρποί και σπόροι με τη χούφτα (15, 30, 45, 60 g· το πλάνο λέει 30 g)· πριν 50–200 g.
      // Round8: ο ίδιος κανόνας με την πρώτη ποσότητα ([firstGrams]): ό,τι μετριέται με το κουτάλι ([isSpoonFood]:
      // και μαγιονέζα, μαργαρίνη, ταχίνι, φυστικοβούτυρο) 5–30 g (R8-A2-1)· ελιές 10–50 g· αλάτι και μπαχαρικά 1–5 g
      // (R8-U2-7)· πίτουρο και νιφάδες βρώμης 20–50 g (R8-U2 Β1).
      for (final v in _pinchPortion(f)
          ? const [1.0, 2.0, 3.0, 5.0]
          : isSpoonFood(f)
              ? const [5.0, 10.0, 15.0, 30.0]
              : isOlives(f)
                  ? const [10.0, 20.0, 30.0, 50.0]
                  : _nutsPortion(f)
                      ? const [15.0, 30.0, 45.0, 60.0]
                      : _oatPortion(f)
                          ? const [20.0, 30.0, 40.0, 50.0]
                          : f.perMl
                              ? const [100.0, 200.0, 250.0, 330.0]
                              : const [50.0, 100.0, 150.0, 200.0])
        ('${v.round()} $unit', v),
    ];

    // Σχέδια 9/11 (9α): από 1,3× γράμματα θρεπτικά 2×2, γεύματα 2×2, «Ζύγισα» σε γραμμές· στο 1,0× μένουν οι 4 στήλες.
    final large = MediaQuery.textScalerOf(context).scale(10) >= 12.5;
    Widget tile(String label, String value, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, maxLines: 1, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.text, fontFeatures: tabular)),
              ),
              Row(children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: c.textSecondary))),
              ]),
            ]),
          ),
        );

    // Έλεγχος 9/11 (V-D-23): με μεγάλα γράμματα (1,3×–2×) η ετικέτα και η τιμή μικραίνουν αντί να κόβονται.
    Widget stat(String label, String value, Color color) => Expanded(
          child: Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value,
                    maxLines: 1,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text, fontFeatures: tabular)),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(label, maxLines: 1, style: TextStyle(fontSize: 12, color: c.textSecondary)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

    // Έλεγχος 9/11 (Μ4): το λάδι του μαγειρέματος είναι συχνά οι μισές θερμίδες του πιάτου· η υπενθύμιση φαίνεται σε
    // κάθε κρέας, ψάρι, λαχανικό, πατάτα και αυγό (όχι μόνο όταν υπάρχουν ωμή/μαγειρεμένη μορφή) και στα «χωρίς λάδι»,
    // εκτός από ό,τι έχει ήδη μέσα το λάδι (τηγανητά, σε λάδι, με λιπαρή ουσία).
    final pn = plain(f.name);
    final hasFat = (pn.contains('τηγαν') && !pn.contains('χωρισ')) ||
        pn.contains('σε λαδι') ||
        pn.contains('σε ελαιολαδο') ||
        pn.contains('με λιπαρη');
    final oilNote = !hasFat && (_oilCats.contains(f.cat) || pn.contains('χωρισ λαδι') || pn.contains('χωρισ λιπαρη'));
    final pickHint = pickHints[f.id] ?? pickHints[widget.food.currentOf(f).id];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(f.name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.text)),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(settings: const RouteSettings(name: 'Τρόφιμο'), builder: (_) => FoodDetailScreen(food: f, sourceName: widget.food.byId(f.id)?.sourceName))),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '${f.brand != null ? '${f.brand} · ' : ''}${kcalText(f.n.amount(Nk.kcal))} kcal ανά 100 $unit · ${f.source} ›',
                      style: TextStyle(fontSize: 13.5, color: c.primary),
                    ),
                  ),
                ),
                if (_states.length > 1) ...[
                  const SizedBox(height: 12),
                  Text('Ζύγισα:', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.textSecondary)),
                  const SizedBox(height: 6),
                  if (large)
                    Column(children: [
                      for (final st in _states) ...[
                        () {
                          final on = st.$1.id == widget.food.currentOf(f).id;
                          // Round8 (R8-U2-5): κάθετο περιθώριο 10 dp. Με μεγάλα γράμματα το Material μηδενίζει το δικό
                          // του, και όταν το κείμενο έσπαγε σε δύο γραμμές («Ξερές (πριν το βράσιμο)») ακουμπούσε το περίγραμμα.
                          const pad = EdgeInsets.symmetric(horizontal: 16, vertical: 10);
                          return SizedBox(
                            width: double.infinity,
                            child: on
                                ? FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                        minimumSize: const Size.fromHeight(48), alignment: Alignment.centerLeft, padding: pad),
                                    onPressed: () {},
                                    icon: const Icon(Icons.check_rounded),
                                    label: Text(st.$2),
                                  )
                                : OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                        minimumSize: const Size.fromHeight(48),
                                        alignment: Alignment.centerLeft,
                                        foregroundColor: c.text,
                                        padding: pad),
                                    onPressed: () => setState(() => _item = st.$1),
                                    child: Text(st.$2),
                                  ),
                          );
                        }(),
                        const SizedBox(height: 8),
                      ],
                    ])
                  else
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final st in _states)
                        ChoiceChip(
                          label: Text(st.$2),
                          // Και για καταχώριση με παλιό id (τρόφιμο που άλλαξε σε νεότερη λίστα).
                          selected: st.$1.id == widget.food.currentOf(f).id,
                          onSelected: (_) {
                            if (st.$1.id != widget.food.currentOf(f).id) setState(() => _item = st.$1);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    f.rawId == null
                        ? 'Βάρος πριν το μαγείρεμα (το πιο ακριβές).'
                        : 'Βάρος μετά το μαγείρεμα· οι τιμές είναι για ${(f.cookedLabel ?? 'μαγειρεμένο').toLowerCase()}'
                            '${(f.cookedLabel ?? '').toLowerCase().contains('τηγαν') && !(f.cookedLabel ?? '').toLowerCase().contains('χωρίς') ? ', μαζί με το λάδι που ρούφηξε' : ''}.',
                    style: TextStyle(fontSize: 12.5, color: c.textTertiary),
                  ),
                ],
                if (oilNote) ...[
                  SizedBox(height: _states.length > 1 ? 2 : 10),
                  Text(
                    'Λάδι ή βούτυρο για το μαγείρεμα: γράψ’ το χωριστά.',
                    key: const ValueKey('oil-note'),
                    style: TextStyle(fontSize: 12.5, color: c.textTertiary),
                  ),
                ],
                if (pickHint != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 18, color: c.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(pickHint, style: TextStyle(fontSize: 13.5, height: 1.35, color: c.text)),
                      ),
                    ],
                  ),
                ],
                if (f.perMl) ...[
                  const SizedBox(height: 10),
                  Text(
                    // Έλεγχος 9/11 (Μ2): οι τιμές μένουν όπως στην ετικέτα (ανά 100 ml) και η ποσότητα γράφεται σε ml.
                    (f.n[Nk.fat]?.value ?? 0) >= 90
                        ? 'Οι τιμές είναι ανά 100 ml, όπως στην ετικέτα: γράψε ml. Αν το ζυγίζεις, 10 g λάδι είναι περίπου 11 ml.'
                        : 'Οι τιμές είναι ανά 100 ml, όπως στην ετικέτα: γράψε ml.',
                    key: const ValueKey('ml-note'),
                    style: TextStyle(fontSize: 12.5, height: 1.35, color: c.textTertiary),
                  ),
                ],
                if (weighHints[f.id] case final hint?) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.scale_rounded, size: 18, color: c.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ζύγισε $hint: οι τιμές είναι για ό,τι τρώγεται.',
                          style: TextStyle(fontSize: 13.5, height: 1.35, color: c.text, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Λιγότερο',
                      onPressed: g == null ? null : () => _set((g - 10).clamp(1, 5000).toDouble()),
                      icon: const Icon(Icons.remove_rounded),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _grams,
                        focusNode: _gramsFocus,
                        onTap: _onGramsTap,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                        textAlign: TextAlign.center,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: c.text, fontFeatures: tabular),
                        decoration: InputDecoration(
                          suffixText: unit,
                          // Έλεγχος round1 (U3a-12): η μονάδα πιο μικρή και γκρι, δίπλα στον αριθμό (πριν 26 px έντονη).
                          suffixStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.textSecondary),
                          errorText: g == null ? quantityErrorText(_grams.text, perMl: f.perMl) : null,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      tooltip: 'Περισσότερο',
                      onPressed: g == null ? null : () => _set((g + 10).clamp(1, 5000).toDouble()),
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Σχέδια 9/11 (9α): οι ποσότητες ως ίσα κουμπιά σε μία σειρά (η μερίδα, αν υπάρχει, από πάνω ολόκληρη).
                for (final ch in chips.where((x) => x.$1.startsWith('1 μερίδα')))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44), foregroundColor: c.text),
                      onPressed: () => _set(ch.$2),
                      child: Text(ch.$1),
                    ),
                  ),
                () {
                  final quick = [
                    for (final x in chips)
                      if (!x.$1.startsWith('1 μερίδα')) x
                  ];
                  Widget chip((String, double) ch) => Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44), padding: const EdgeInsets.symmetric(horizontal: 4), foregroundColor: c.text),
                          onPressed: () => _set(ch.$2),
                          child: FittedBox(fit: BoxFit.scaleDown, child: Text(ch.$1, maxLines: 1)),
                        ),
                      );
                  // Έλεγχος round1 (U3a-8): με μεγάλα γράμματα οι ποσότητες σε 2 × 2 (όπως τα θρεπτικά και τα γεύματα),
                  // ώστε να έχουν όλες το ίδιο μέγεθος γραμμάτων· σε μία σειρά το «50 g» έβγαινε μεγαλύτερο από το «100 g».
                  if (large && quick.length == 4) {
                    return Column(key: const ValueKey('qty-chips-grid'), children: [
                      Row(children: [chip(quick[0]), const SizedBox(width: 8), chip(quick[1])]),
                      const SizedBox(height: 8),
                      Row(children: [chip(quick[2]), const SizedBox(width: 8), chip(quick[3])]),
                    ]);
                  }
                  return Row(children: [
                    for (var k = 0; k < quick.length; k++) ...[
                      if (k > 0) const SizedBox(width: 8),
                      chip(quick[k]),
                    ],
                  ]);
                }(),
                const SizedBox(height: 16),
                if (large && !_tilesFit(context))
                  // Πολύ μεγάλα γράμματα (έλεγχος premium, M3): μία γραμμή ανά θρεπτικό, ποτέ σπασμένη λέξη.
                  Container(
                    key: const ValueKey('qty-nutrients-rows'),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(14)),
                    child: Column(children: [
                      InfoRow('kcal', kcalText(tot(Nk.kcal)), dot: c.primary),
                      InfoRow('Πρωτεΐνη', '${gramsText(tot(Nk.protein))} g', dot: proteinColor(c)),
                      InfoRow('Υδατάνθρακες', '${gramsText(tot(Nk.carbs))} g', dot: carbsColor(c)),
                      InfoRow(lastLabel, lastValue, dot: lastColor),
                    ]),
                  )
                else if (large)
                  Column(key: const ValueKey('qty-nutrients-grid'), children: [
                    Row(children: [
                      tile('kcal', kcalText(tot(Nk.kcal)), c.primary),
                      const SizedBox(width: 8),
                      tile('Πρωτεΐνη', '${gramsText(tot(Nk.protein))} g', proteinColor(c)),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      tile('Υδατάνθρακες', '${gramsText(tot(Nk.carbs))} g', carbsColor(c)),
                      const SizedBox(width: 8),
                      tile(lastLabel, lastValue, lastColor),
                    ]),
                  ])
                else
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                  decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    children: [
                      stat('kcal', kcalText(tot(Nk.kcal)), c.primary),
                      stat('Πρωτεΐνη', '${gramsText(tot(Nk.protein))} g', proteinColor(c)),
                      stat('Υδατάνθρ.', '${gramsText(tot(Nk.carbs))} g', carbsColor(c)),
                      stat(lastLabel, lastValue, lastColor),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                MealPicker(value: _meal, grid: large, onChanged: (m) => setState(() => _meal = m)),
                const SizedBox(height: 18),
                FilledButton(
                  // Round 2 (R2-U1-12): και 20 dp δεξιά-αριστερά (πριν 0: με γράμματα 2× το κείμενο ακουμπούσε τις άκρες).
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20)),
                  onPressed: g == null ? null : () => _submit(g),
                  // Έλεγχος round1 (U3a-18): αν σπάσει σε δύο γραμμές (μεγάλα γράμματα), μένει στο κέντρο του κουμπιού.
                  child: Text(widget.editing ? 'Αποθήκευση' : 'Προσθήκη στο ${mealLabel(_meal)}', textAlign: TextAlign.center),
                ),
                if (widget.editing) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: c.bad),
                    onPressed: () => Navigator.pop(context, _SheetResult(g ?? 0, _meal, _item, delete: true)),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Διαγραφή'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Κατηγορίες που συνήθως μαγειρεύονται με λάδι ή βούτυρο (υπενθύμιση στην ποσότητα). Round7 (R7-U2-1): και τα όσπρια
/// (φακές, φασολάδα, ρεβίθια μαγειρεύονται με ελαιόλαδο· μία κουταλιά = 120–135 kcal που αλλιώς χάνονται).
const _oilCats = {'Κρέας', 'Πουλερικά', 'Ψάρια', 'Θαλασσινά', 'Λαχανικά', 'Πατάτες', 'Αυγά', 'Όσπρια'};

/// Συμβουλή επιλογής στην ποσότητα, όταν το ίδιο τρόφιμο έχει είδη με μεγάλη διαφορά θερμίδων (έλεγχος 9/11, V-C-13).
final pickHints = <String, String>{
  for (final id in const ['C6250', 'C6251', 'C6252', 'C6253', 'C6254', 'C6255', 'C6256', 'C6257'])
    id: 'Τα λιπαρά αλλάζουν πολύ τις θερμίδες του κιμά: διάλεξε το % που γράφει η συσκευασία ή ρώτα τον κρεοπώλη.',
};

/// Λέξεις που, αν αγνοηθούν στην αναζήτηση, κάνουν το αποτέλεσμα άλλο τρόφιμο με άλλες θερμίδες (αρχές λέξεων, χωρίς
/// τόνους): «γάλα σόγιας», «μπύρα χωρίς αλκοόλ», «κοτόπουλο πανέ», «σοκολάτα χωρίς ζάχαρη», «αμύγδαλα αλατισμένα».
const _nutritionWords = [
  'σογι', 'σοι', 'soy', 'αμυγδαλ', 'βρωμ', 'καρυδ', 'light', 'λαιτ', 'zero', 'ζιρο', 'διαιτ', 'αλκοολ', 'γλουτεν',
  'πανε', 'μπαρ', 'αλατισμ', 'αναλατ', 'λαδι', 'ελαιολαδ', 'βουτυρ', 'τηγαν', 'ζαχαρ', 'μελι', 'σοκολατ', 'κρεμ',
  'τυρι', 'γαλα', 'σιροπ', 'πρωτειν', 'κακαο', 'σοκολατουχ',
  // Round7 (R7-U2-6): ροφήματα με γάλα: «φρέντο καπουτσίνο» έβρισκε σκέτο εσπρέσο με απλή γκρι σημείωση.
  'καπουτσ', 'cappucc', 'kaputs', 'λατε', 'latte',
  // Αγνοημένο «χωρίς» αλλάζει το νόημα («μαρμελάδα χωρίς ζάχαρη» → «με λιγότερη ζάχαρη»).
  'χωρισ', 'without',
];

bool changesNutrition(String word) {
  final w = plain(word);
  return _nutritionWords.any(w.startsWith);
}

/// Έντονη προειδοποίηση «άλλο τρόφιμο» (δεύτερος ανεξάρτητος έλεγχος του fix-food, Σ-Α): μόνο όταν αγνοήθηκε λέξη που
/// αλλάζει τη διατροφή ή λέξη που είναι τρόφιμο της βάσης — όχι για επίθετα («μήλο πράσινο»), «σπιτικές», «ελληνικός
/// καφές», ούτε για «χωρίς λακτόζη» (ίδια θρεπτική αξία).
bool strongSearchWarning(FoodSearchResult r) {
  if (r.corrected.isNotEmpty || r.ignored.isEmpty) return false;
  final lactoseFree = r.ignored.any((w) => plain(w).startsWith('λακτοζ') || plain(w).startsWith('lactose'));
  return r.droppedFood ||
      r.ignored.any((w) => changesNutrition(w) && !(lactoseFree && (plain(w).startsWith('χωρισ') || w == 'without')));
}

/// Τρόπος μαγειρέματος χωρίς λάδι: αν αγνοηθεί, οι μαγειρεμένες μορφές μπαίνουν ήδη πρώτες.
bool isCookingWord(String word) {
  final w = plain(word);
  return const ['ψητ', 'βραστ', 'βρασμεν', 'σχαρ', 'φουρν', 'μαγειρ', 'ατμ', 'στιφαδ', 'κοκκινιστ'].any(w.startsWith);
}

// ---------------------------------------------------------------------------
// Λεπτομέρειες τροφίμου (όλες οι τιμές ανά 100 g και η πηγή)
// ---------------------------------------------------------------------------

class FoodDetailScreen extends StatelessWidget {
  const FoodDetailScreen({super.key, required this.food, this.sourceName});
  final Food food;

  /// Η περιγραφή της πηγής, όταν το [food] είναι αντίγραφο καταχώρισης (που δεν την κρατά).
  final String? sourceName;

  static const _rows = <(String, String, String, int)>[
    ('kcal', 'Ενέργεια', 'kcal', 0),
    ('protein', 'Πρωτεΐνη', 'g', 1),
    ('carbs', 'Υδατάνθρακες', 'g', 1),
    // Round8 (R8-U2-9): «εκ των οποίων», όπως η φόρμα της ετικέτας και η διατροφική δήλωση της ΕΕ.
    ('sugars', '  εκ των οποίων σάκχαρα', 'g', 1),
    ('fiber', 'Φυτικές ίνες', 'g', 1),
    // «Λιπαρά», όπως στη διατροφική δήλωση της ΕΕ (έλεγχος 9/11, Χ10).
    ('fat', 'Λιπαρά', 'g', 1),
    ('satFat', '  εκ των οποίων κορεσμένα', 'g', 1),
    ('monoFat', '  μονοακόρεστα', 'g', 1),
    ('polyFat', '  πολυακόρεστα', 'g', 1),
    ('salt', 'Αλάτι', 'g', 2),
    ('sodium', 'Νάτριο', 'mg', 0),
    ('alcohol', 'Αλκοόλ', 'g', 1),
    ('polyols', 'Πολυόλες (γλυκαντικά)', 'g', 1),
    // Round8 (R8-U2-9): «Χοληστερίνη», η λέξη της υπόλοιπης εφαρμογής.
    ('cholesterol', 'Χοληστερίνη', 'mg', 0),
    ('water', 'Νερό', 'g', 1),
    ('calcium', 'Ασβέστιο', 'mg', 0),
    ('iron', 'Σίδηρος', 'mg', 1),
    ('magnesium', 'Μαγνήσιο', 'mg', 0),
    ('potassium', 'Κάλιο', 'mg', 0),
    ('zinc', 'Ψευδάργυρος', 'mg', 1),
    ('vitC', 'Βιταμίνη C', 'mg', 1),
    ('vitD', 'Βιταμίνη D', 'µg', 1),
    ('vitB12', 'Βιταμίνη B12', 'µg', 1),
    // Ολικό φυλλικό της πηγής, όχι μόνο «φυλλικό οξύ» (το συνθετικό)· έλεγχος διατροφής L4, 4/11.
    // (Η βιταμίνη A δεν φαίνεται: CIQUAL = ισοδύναμα ρετινόλης RE, USDA = RAE· διαφέρουν ~2× στα φυτικά.)
    ('folate', 'Φυλλικό (φολικό)', 'µg', 0),
  ];

  @override
  Widget build(BuildContext context) => FoodTheme(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final c = Aigaio.of(context);
    final f = food;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(backgroundColor: c.background, surfaceTintColor: Colors.transparent, title: Text(f.name)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 40),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CardHeader(icon: Icons.science_outlined, title: 'Ανά 100 ${f.unit}', color: c.food),
                    const SizedBox(height: 6),
                    // Τρίτος έλεγχος διατροφής N6: το αλάτι της βάσης είναι νάτριο × 2,5 (κανόνας ΕΕ), όχι η στήλη αλατιού της
                    // CIQUAL· το λέει η ετικέτα, και φαίνεται και το νάτριο.
                    for (final r in _rows)
                      if (f.n.has(r.$1))
                        InfoRow(
                          r.$1 == 'salt' && f.n.has('sodium') ? saltFromSodiumLabel : r.$2,
                          '${nValueText(f.n[r.$1], digits: r.$4)} ${r.$3}',
                        ),
                    if (f.energyCalc)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('Οι θερμίδες υπολογίστηκαν από τα μακροθρεπτικά (η πηγή δεν τις έδινε).',
                            style: TextStyle(fontSize: 12.5, color: c.textTertiary)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CardHeader(icon: Icons.verified_outlined, title: 'Πηγή', color: c.primary),
                    const SizedBox(height: 6),
                    InfoRow('Βάση', f.source),
                    if (f.sourceCode != null) InfoRow('Κωδικός', '${f.sourceCode}'),
                    if (f.barcode != null) InfoRow('Barcode', f.barcode!),
                    if ((f.sourceName ?? sourceName) != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('Όνομα στην πηγή: ${f.sourceName ?? sourceName}',
                            style: TextStyle(fontSize: 13, color: c.textSecondary)),
                      ),
                    const SizedBox(height: 8),
                    // Έλεγχος 9/11 (Μ5): έκδοση και ημερομηνία της πηγής, όπως ζητά η άδεια.
                    Text(
                      sourceSentence(f.source),
                      style: TextStyle(fontSize: 12.5, height: 1.4, color: c.textTertiary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Νέο τρόφιμο από την ετικέτα (ή έλεγχος προϊόντος του Open Food Facts)
// ---------------------------------------------------------------------------

class FoodFormScreen extends StatefulWidget {
  const FoodFormScreen({super.key, required this.draft, this.note, this.existingId, this.cholChoice});
  final FoodDraft draft;
  final String? note;

  /// Αν δίνεται, διορθώνουμε υπάρχον προϊόν (κρατά το ίδιο id).
  final String? existingId;

  /// Αν φαίνεται η επιλογή «Στην κάρτα «Χοληστερίνη» μετρά ως» (έλεγχος round1, S2-1 / S1-9). null = μόνο όταν η κάρτα
  /// υπάρχει (στόχοι με οδηγία γιατρού για τη χοληστερίνη). Ό,τι έχει ήδη το προϊόν κρατιέται και όταν δεν φαίνεται.
  final bool? cholChoice;

  @override
  State<FoodFormScreen> createState() => _FoodFormScreenState();
}

/// Τι γράφει η ετικέτα στη θέση του αλατιού (έλεγχος 9/11, Μ1): οι ευρωπαϊκές «Αλάτι» σε g, οι αμερικάνικες και
/// πολλές εισαγόμενες «Sodium» σε mg (ή σε g). Η εφαρμογή κρατά πάντα αλάτι = νάτριο × 2,5 (Κανονισμός ΕΕ 1169/2011,
/// Παράρτημα I).
enum SaltInput { salt, sodiumG, sodiumMg }

/// Αλάτι σε g από ό,τι γράφει η ετικέτα.
double saltFromInput(double v, SaltInput mode) => switch (mode) {
      SaltInput.salt => v,
      SaltInput.sodiumG => v * 2.5,
      SaltInput.sodiumMg => v * 2.5 / 1000,
    };

class _FoodFormScreenState extends State<FoodFormScreen> {
  late final _name = TextEditingController(text: widget.draft.name);
  late final _brand = TextEditingController(text: widget.draft.brand ?? '');
  late final _serving = TextEditingController(
      text: widget.draft.servingGrams == null ? '' : gramsField(widget.draft.servingGrams!));
  late final Map<String, TextEditingController> _v = {
    for (final k in _fields.map((e) => e.$1))
      // Μέχρι 4 δεκαδικά, ώστε μια διόρθωση μόνο του ονόματος να μη στρογγυλεύει τις τιμές (αλάτι 0,0125).
      k: TextEditingController(text: widget.draft.values[k] == null ? '' : _field(widget.draft.values[k]!)),
  };
  bool _tried = false;
  SaltInput _saltMode = SaltInput.salt;

  /// Round7 (R7-U2-3): όταν η «Αποθήκευση» δεν γίνεται, η φόρμα πάει στο πρώτο πεδίο που θέλει διόρθωση και το λέει·
  /// πριν, με το «Όνομα» έξω από την οθόνη (σάρωση προϊόντος που δεν υπάρχει στο Open Food Facts), δεν φαινόταν τίποτα.
  final _scroll = ScrollController();
  final _nameKey = GlobalKey();
  final _servingKey = GlobalKey();
  late final Map<String, GlobalKey> _fieldKeys = {for (final f in _fields) f.$1: GlobalKey()};

  /// Οι τιμές είναι ανά 100 ml (υγρό) αντί για ανά 100 g (έλεγχος 9/11, Μ2): και για χειροκίνητη ετικέτα.
  late bool _perMl = widget.draft.perMl;

  /// Τι μετρά το προϊόν στην κάρτα «Χοληστερίνη» ([CholKind]) ή null.
  late String? _cholKind = widget.draft.cholKind;

  static String _field(double v) => dec(v, 4).replaceAll(RegExp(r',?0+$'), '');

  // Round7 (R7-U2 Β-1): με τη σειρά της διατροφικής δήλωσης της ΕΕ (Κανονισμός 1169/2011, Παράρτημα XV), όπως είναι
  // τυπωμένη στη συσκευασία: αντιγράφεται γραμμή-γραμμή, χωρίς πήγαινε-έλα στην ετικέτα.
  static const _fields = <(String, String, String, bool)>[
    (Nk.kcal, 'Ενέργεια', 'kcal', true),
    (Nk.fat, 'Λιπαρά', 'g', true),
    (Nk.satFat, 'εκ των οποίων κορεσμένα', 'g', false),
    (Nk.carbs, 'Υδατάνθρακες', 'g', true),
    (Nk.sugars, 'εκ των οποίων σάκχαρα', 'g', false),
    (Nk.fiber, 'Φυτικές (εδώδιμες) ίνες', 'g', false),
    (Nk.protein, 'Πρωτεΐνες', 'g', true),
    (Nk.salt, 'Αλάτι', 'g', false),
  ];

  @override
  void dispose() {
    _scroll.dispose();
    _name.dispose();
    _brand.dispose();
    _serving.dispose();
    for (final c in _v.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Οι τιμές όπως γράφτηκαν, με το αλάτι πάντα σε g αλατιού (και αν η ετικέτα έδινε νάτριο).
  Map<String, double> get _values => {
        for (final e in _v.entries)
          if (parseNumber(e.value.text) case final v?) e.key: e.key == Nk.salt ? saltFromInput(v, _saltMode) : v,
      };

  void _save() {
    setState(() => _tried = true);
    final values = _values;
    final missing = [for (final f in _fields) if (f.$4 && values[f.$1] == null) f.$1];
    final noName = _name.text.trim().isEmpty;
    final wrong = impossibleValues(values);
    if (noName || missing.isNotEmpty || wrong.isNotEmpty) {
      final firstWrong = [for (final f in _fields) if (wrong.containsKey(f.$1)) f.$1];
      _showProblem(noName: noName, missing: missing, firstWrong: firstWrong.isEmpty ? null : firstWrong.first);
      return;
    }
    if (servingRejected(_serving.text)) {
      _showProblem(noName: false, missing: const [], serving: true);
      return;
    }
    final typedSalt = parseNumber(_v[Nk.salt]!.text);
    // Νάτριο σε mg: αν γράφτηκε νάτριο, αυτό· αν το αλάτι έμεινε όπως ήρθε (από νάτριο), το νάτριο της πηγής.
    final sodiumMg = typedSalt == null
        ? null
        : switch (_saltMode) {
            SaltInput.sodiumMg => typedSalt,
            SaltInput.sodiumG => typedSalt * 1000,
            SaltInput.salt => typedSalt == widget.draft.values[Nk.salt] ? widget.draft.sodiumMg : null,
          };
    final d = FoodDraft(
      name: _name.text.trim(),
      brand: _brand.text.trim(),
      barcode: widget.draft.barcode,
      // Μερίδα μόνο αν γίνεται να γραφτεί ως ποσότητα (πάνω από 0, ως 5.000· τελικός έλεγχος, Συμβούλιο 3). Πριν, «0»,
      // αρνητικό ή τεράστιο αποθηκευόταν όπως ήταν και έβγαινε ως προτεινόμενη ποσότητα.
      servingGrams: validServing(parseNumber(_serving.text)),
      servingLabel: widget.draft.servingLabel,
      values: values,
      fromOff: widget.draft.fromOff,
      // Το «ανά 100 ml» μένει στο προϊόν (πριν χανόταν στην αποθήκευση· δεύτερος έλεγχος διατροφής N9).
      perMl: _perMl,
      alcohol: widget.draft.alcohol,
      polyols: widget.draft.polyols,
      erythritol: widget.draft.erythritol,
      sodiumMg: sodiumMg,
      // «<x» της πηγής: μόνο όσα έμειναν όπως ήρθαν.
      lessThan: {
        for (final k in widget.draft.lessThan)
          if (values[k] != null && values[k] == widget.draft.values[k]) k,
      },
      cholKind: _cholKind,
    );
    Navigator.pop(context, foodFromDraft(d, widget.existingId ?? FoodStore.newFoodId()));
  }

  /// Η «Αποθήκευση» δεν έγινε: μήνυμα με ό,τι λείπει και κύλιση στο πρώτο πεδίο που θέλει διόρθωση (round7, R7-U2-3).
  void _showProblem({required bool noName, required List<String> missing, String? firstWrong, bool serving = false}) {
    final labels = {for (final f in _fields) f.$1: f.$2.toLowerCase()};
    final parts = [if (noName) 'όνομα', for (final k in missing) labels[k]!];
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(parts.isNotEmpty ? 'Συμπλήρωσε: ${parts.join(', ')}.' : 'Διόρθωσε το πεδίο με το κόκκινο μήνυμα.'),
      ));
    final key = noName
        ? _nameKey
        : missing.isNotEmpty
            ? _fieldKeys[missing.first]
            : firstWrong != null
                ? _fieldKeys[firstWrong]
                : serving
                    ? _servingKey
                    : null;
    final target = key?.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(target, alignment: 0.2, duration: const Duration(milliseconds: 250));
    } else if (_scroll.hasClients) {
      // Το πεδίο είναι τόσο μακριά που η λίστα δεν το έχει φτιάξει ακόμα: όλα τα πεδία που ελέγχονται είναι από πάνω.
      _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  /// Αλλαγή μονάδας αλατιού (ανεξάρτητος έλεγχος του fix-food, 4.1): αν το πεδίο έχει ακόμα την τιμή που ήρθε (π.χ.
  /// από το Open Food Facts), μετατρέπεται στη νέα μονάδα ώστε να μένει το ίδιο αλάτι. Αν ο χρήστης έγραψε δικό του
  /// αριθμό (π.χ. 400 από ξένη ετικέτα), μένει όπως είναι: απλώς λέει τι μονάδα είναι.
  void _setSaltMode(SaltInput mode) {
    final field = _v[Nk.salt]!;
    final typed = parseNumber(field.text);
    final original = widget.draft.values[Nk.salt];
    // Με ανοχή: μετά από μετατροπή και στρογγύλεμα σε 4 δεκαδικά η ακριβής ισότητα μπορεί να αποτύχει (έλεγχος fix-food, Χ-Δ).
    if (typed != null && original != null && mode != _saltMode && (saltFromInput(typed, _saltMode) - original).abs() < 1e-6) {
      final v = switch (mode) {
        SaltInput.salt => original,
        SaltInput.sodiumG => original / 2.5,
        SaltInput.sodiumMg => original / 2.5 * 1000,
      };
      field.text = _field(double.parse(v.toStringAsFixed(4)));
    }
    setState(() => _saltMode = mode);
  }

  @override
  Widget build(BuildContext context) => FoodTheme(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final c = Aigaio.of(context);
    final values = _values;
    final mismatch = energyMismatch(values,
        alcohol: widget.draft.alcohol ?? 0, polyols: widget.draft.polyols ?? 0, erythritol: widget.draft.erythritol ?? 0);
    final impossible = impossibleValues(values);
    final doubtful = doubtfulValues(values);
    final per = _perMl ? '100 ml' : '100 g';
    final showChol = widget.cholChoice ?? (HealthStore.shared?.goals?.doctor ?? false);

    InputDecoration deco(String label, {String? suffix, String? error, String? warning, bool info = false}) => InputDecoration(
          labelText: label,
          suffixText: suffix,
          errorText: error,
          errorMaxLines: 3,
          helperText: warning,
          helperMaxLines: 3,
          // Προειδοποίηση σε κόκκινο· απλή πληροφορία (π.χ. «αποθηκεύεται ως αλάτι…») σε γκρι.
          helperStyle: TextStyle(fontSize: 12.5, color: info ? c.textSecondary : c.bad),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        );

    Widget choices<T>(String label, List<(T, String)> items, T value, ValueChanged<T> onChanged, {Key? key}) => Padding(
          key: key,
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(label, style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
              for (final it in items)
                ChoiceChip(label: Text(it.$2), selected: it.$1 == value, onSelected: (_) => onChanged(it.$1)),
            ],
          ),
        );

    String? saltWarning() {
      final typed = parseNumber(_v[Nk.salt]!.text);
      if (typed == null) return null;
      if (_saltMode != SaltInput.salt) return 'Αποθηκεύεται ως αλάτι ${dec(saltFromInput(typed, _saltMode), 2)} g (νάτριο × 2,5).';
      if (widget.draft.saltFromSodium && typed == widget.draft.values[Nk.salt]) {
        return widget.draft.fromOff
            ? 'Από νάτριο × 2,5 (το Open Food Facts έδωσε μόνο νάτριο). Έλεγξέ το με την ετικέτα.'
            : 'Από νάτριο × 2,5. Έλεγξέ το με την ετικέτα.';
      }
      return null;
    }

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        title: Text(widget.existingId != null
            ? 'Διόρθωση προϊόντος'
            : widget.draft.fromOff
                ? 'Έλεγχος προϊόντος'
                : 'Νέο προϊόν'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 40),
            children: [
              if (widget.note != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: c.tint(c.primary), borderRadius: BorderRadius.circular(16)),
                  child: Text(widget.note!, style: TextStyle(fontSize: 14, height: 1.4, color: c.text)),
                ),
              KeyedSubtree(
                key: _nameKey,
                child: TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  // Η επιλογή «μετρά ως» δείχνει τι θα μετρήσει το όνομα (πίτουρο βρώμης· R7-A3-1).
                  onChanged: (_) => setState(() {}),
                  decoration: deco('Όνομα', error: _tried && _name.text.trim().isEmpty ? 'Χρειάζεται όνομα' : null),
                ),
              ),
              const SizedBox(height: 12),
              TextField(controller: _brand, textInputAction: TextInputAction.next, decoration: deco('Μάρκα (προαιρετικό)')),
              if (widget.draft.barcode != null) ...[
                const SizedBox(height: 8),
                Text('Barcode ${widget.draft.barcode}', style: TextStyle(color: c.textTertiary, fontSize: 13)),
              ],
              const SizedBox(height: 18),
              Text('Διατροφική ετικέτα, ανά $per',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
              const SizedBox(height: 8),
              choices<bool>('Οι τιμές είναι:', const [(false, 'ανά 100 g'), (true, 'ανά 100 ml')], _perMl,
                  (v) => setState(() => _perMl = v),
                  key: const ValueKey('per-unit')),
              if (_perMl)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    widget.draft.fromOff && widget.draft.perMl
                        ? 'Το Open Food Facts δίνει τα υγρά ανά 100 ml. Θα γράφεις την ποσότητα σε ml.'
                        : 'Θα γράφεις την ποσότητα σε ml.',
                    style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.4),
                  ),
                ),
              const SizedBox(height: 4),
              for (final f in _fields) ...[
                if (f.$1 == Nk.salt)
                  choices<SaltInput>(
                    'Η ετικέτα γράφει:',
                    const [(SaltInput.salt, 'Αλάτι g'), (SaltInput.sodiumG, 'Νάτριο g'), (SaltInput.sodiumMg, 'Νάτριο mg')],
                    _saltMode,
                    _setSaltMode,
                    key: const ValueKey('salt-mode'),
                  ),
                KeyedSubtree(
                  key: _fieldKeys[f.$1],
                  child: TextField(
                    key: ValueKey('field-${f.$1}'),
                    controller: _v[f.$1],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    // Round7 (R7-U2 Β-1): «Επόμενο» στο πληκτρολόγιο, στο επόμενο πεδίο της ετικέτας.
                    textInputAction: TextInputAction.next,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    onChanged: (_) => setState(() {}),
                    decoration: deco(
                      f.$1 == Nk.salt && _saltMode != SaltInput.salt
                          ? 'Νάτριο (προαιρετικό)'
                          : f.$4
                              ? f.$2
                              : '${f.$2} (προαιρετικό)',
                      suffix: f.$1 == Nk.salt && _saltMode == SaltInput.sodiumMg ? 'mg' : f.$3,
                      error: (f.$1 == Nk.salt && _saltMode != SaltInput.salt && impossible[Nk.salt] != null
                              ? 'Τόσο νάτριο δεν γίνεται: έλεγξε τον αριθμό και τη μονάδα.'
                              : impossible[f.$1]) ??
                          (_tried && f.$4 && values[f.$1] == null ? 'Χρειάζεται' : null),
                      warning: doubtful[f.$1] ?? (f.$1 == Nk.salt ? saltWarning() : null),
                      info: doubtful[f.$1] == null && f.$1 == Nk.salt && _saltMode != SaltInput.salt,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (doubtful['total'] != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: c.warnBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.warnLine)),
                  child: Text(doubtful['total']!, style: TextStyle(fontSize: 13.5, height: 1.4, color: c.text)),
                ),
                const SizedBox(height: 10),
              ],
              if (mismatch != null)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: c.warnBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.warnLine)),
                  child: Text(
                    'Οι θερμίδες δεν ταιριάζουν με τα υπόλοιπα: από πρωτεΐνες, υδατάνθρακες και λιπαρά βγαίνουν '
                    'περίπου ${kcalText(mismatch)} kcal. Έλεγξε ξανά την ετικέτα (μήπως είναι ανά μερίδα ή σε kJ;). '
                    'Αλκοόλ και γλυκαντικές πολυόλες δίνουν θερμίδες που δεν φαίνονται εδώ.',
                    style: TextStyle(fontSize: 13.5, height: 1.4, color: c.text),
                  ),
                ),
              if (showChol) ...[
                const SizedBox(height: 14),
                // Έλεγχος round1 (S2-1 / S1-9): τα δικά σου προϊόντα μετρούν στην κάρτα «Χοληστερίνη» μόνο αν λένε τι είναι.
                // Round7 (R7-A3-1): το «Τίποτα» αποθηκεύεται ([CholKind.none]) και κανένα όνομα δεν το αλλάζει. Όσο δεν
                // διάλεξες, η επιλογή δείχνει τι θα μετρήσει: «Πίτουρο βρώμης» όταν το όνομα αρχίζει έτσι, αλλιώς «Τίποτα».
                choices<String>(
                  'Στην κάρτα «Χοληστερίνη» μετρά ως:',
                  const [
                    (CholKind.none, 'Τίποτα'),
                    (CholKind.nuts, 'Ξηροί καρποί'),
                    (CholKind.legumes, 'Όσπρια'),
                    (CholKind.fish, 'Ψάρι ή θαλασσινά'),
                    (CholKind.bran, 'Πίτουρο βρώμης'),
                  ],
                  _cholKind ?? (branByName(_name.text) ? CholKind.bran : CholKind.none),
                  (v) => setState(() => _cholKind = v),
                  key: const ValueKey('chol-kind'),
                ),
              ],
              const SizedBox(height: 14),
              KeyedSubtree(
                key: _servingKey,
                child: TextField(
                  key: const ValueKey('field-serving'),
                  controller: _serving,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  // Όπως τα υπόλοιπα πεδία αριθμών της φόρμας (πριν, το μόνο χωρίς φίλτρο: δεχόταν «-», γράμματα από επικόλληση).
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  onChanged: (_) => setState(() {}),
                  decoration: deco(
                    'Μία μερίδα (προαιρετικό)',
                    suffix: _perMl ? 'ml' : 'g',
                    error: _tried && servingRejected(_serving.text) ? servingErrorText(perMl: _perMl) : null,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              FilledButton(
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: _save,
                child: const Text('Αποθήκευση'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Κοινά: νέο προϊόν χειροκίνητα ή από barcode (χωρίς καταγραφή φαγητού)
// ---------------------------------------------------------------------------

/// Φόρμα νέου τροφίμου· το αποθηκεύει στα προϊόντα μου και το επιστρέφει.
Future<Food?> createFood(BuildContext context, FoodStore food, {FoodDraft? draft, String? note}) async {
  final messenger = ScaffoldMessenger.of(context);
  final f = await Navigator.of(context).push<Food>(
    MaterialPageRoute(settings: const RouteSettings(name: 'Νέο τρόφιμο'), builder: (_) => FoodFormScreen(draft: draft ?? FoodDraft(), note: note)),
  );
  if (f == null) return null;
  // Έλεγχος round1 (S2-4): αν το προϊόν δεν γράφτηκε στο κινητό (π.χ. γεμάτος χώρος), το λέμε και επιστρέφουμε null.
  // Πριν το αποτέλεσμα αγνοούνταν: έβγαινε «Αποθηκεύτηκε» (ή συνέχιζε στην ποσότητα) για προϊόν που δεν υπήρχε.
  if (!await food.saveMyFood(f)) {
    messenger.showSnackBar(SnackBar(content: Text(productNotSavedText(f.name))));
    return null;
  }
  return f;
}

/// Το μήνυμα όταν ένα προϊόν ή μια καταχώριση δεν γράφτηκε στο κινητό (ίδιο κείμενο με τη Διατροφή).
String productNotSavedText(String name) => 'Δεν αποθηκεύτηκε: $name. Δοκίμασε ξανά.';

/// Σκανάρισμα → αν υπάρχει ήδη στα προϊόντα μου, αυτό· αλλιώς Open Food Facts → έλεγχος με την ετικέτα → αποθήκευση.
/// [existing]: τι να γίνει όταν το προϊόν υπάρχει ήδη (στην προσθήκη φαγητού απλώς επιστρέφεται).
Future<Food?> scanToFood(
  BuildContext context,
  FoodStore food, {
  required void Function(bool busy) onBusy,
  Future<Food?> Function(Food existing)? existing,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final s = await FoodChannel.scanBarcode();
  if (!context.mounted) return null;
  if (s['ok'] != true) {
    final kind = s['kind'];
    if (kind == 'cancelled') return null;
    final detail = (s['detail'] as String?) ?? '';
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      // Round8 (R8-U2-1): με κουμπί («Λεπτομέρειες») το μήνυμα δεν θα έκλεινε ποτέ μόνο του (Flutter ≥ 3.38).
      persist: false,
      content: Text(kind == 'unavailable'
          ? 'Ο σαρωτής κατεβαίνει από το Google Play. Δοκίμασε ξανά σε λίγο, με σύνδεση στο ίντερνετ.'
          : 'Δεν άνοιξε ο σαρωτής. Μέχρι να το διορθώσω, πέρασε το προϊόν χειροκίνητα.'),
      action: detail.isEmpty
          ? null
          : SnackBarAction(
              label: 'Λεπτομέρειες',
              onPressed: () => showDialog<void>(
                context: context,
                routeSettings: const RouteSettings(name: 'Λεπτομέρειες σφάλματος'),
                builder: (ctx) => AlertDialog(
                  title: const Text('Για τον Claude'),
                  content: SingleChildScrollView(
                    child: SelectableText('${s['message'] ?? ''}\n\n$detail', style: const TextStyle(fontSize: 12)),
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Κλείσιμο'))],
                ),
              ),
            ),
    ));
    return null;
  }
  final code = (s['code'] is String ? s['code'] as String : '').trim();
  // Ό,τι δεν είναι barcode προϊόντος (κενό, γράμματα, λάθος μήκος) δεν συνεχίζει (τελικός έλεγχος, Συμβούλιο 3), και
  // τίποτα δεν αποθηκεύεται με άκυρο barcode. Δικό του μήνυμα (εγκρίθηκε 12/11): ο σαρωτής άνοιξε, απλώς δεν διάβασε.
  if (scannedBarcode(code) == null) {
    messenger.showSnackBar(const SnackBar(
      duration: Duration(seconds: 8),
      content: Text(barcodeUnreadText),
    ));
    return null;
  }
  final mine = food.byBarcode(code);
  if (mine != null) return existing == null ? mine : existing(mine);

  onBusy(true);
  final r = await FoodChannel.offLookup(code);
  onBusy(false);
  if (!context.mounted) return null;
  if (r['ok'] != true) {
    return createFood(context, food,
        draft: FoodDraft(barcode: code),
        note: 'Δεν έγινε σύνδεση με το Open Food Facts. Πέρασε τα στοιχεία από την ετικέτα.');
  }
  if (r['found'] != true) {
    return createFood(context, food,
        draft: FoodDraft(barcode: code),
        note: 'Το προϊόν δεν υπάρχει στο Open Food Facts. Πέρασε τα στοιχεία από την ετικέτα.');
  }
  final d = draftFromOff(code, Map<String, dynamic>.from(r['product'] as Map));
  return createFood(context, food,
      draft: d,
      note: d.missing.isEmpty
          ? 'Βρέθηκε στο Open Food Facts. Έλεγξε ότι τα νούμερα ταιριάζουν με την ετικέτα και πάτα Αποθήκευση.'
          : 'Βρέθηκε στο Open Food Facts, αλλά λείπουν τιμές. Συμπλήρωσέ τες από την ετικέτα.');
}

/// Η ετικέτα του αλατιού για τρόφιμα της βάσης (τρίτος έλεγχος διατροφής N6).
const saltFromSodiumLabel = 'Αλάτι (από νάτριο × 2,5)';
