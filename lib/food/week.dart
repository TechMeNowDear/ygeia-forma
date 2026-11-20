/// Πρόγραμμα εβδομάδας (15/11, υποδομή): ποιο φαγητό σε κάθε γεύμα κάθε μέρας, με στόχο θερμίδων ανά μερίδα.
///
/// Κανόνες (έγγραφο προδιαγραφών › «Διατροφή: εβδομαδιαίο πρόγραμμα από βιβλιοθήκη συνταγών»):
/// - Το πρόγραμμα ΔΕΝ είναι ημερολόγιο. Στο ημερολόγιο μπαίνει μόνο ό,τι πατήσεις «Το έφαγα» (ή γράψεις αλλιώς). Έτσι ο
///   εβδομαδιαίος έλεγχος θερμίδων μετρά μόνο ό,τι έφαγες.
/// - Κάθε θέση έχει ένα φαγητό από «Τα φαγητά μου» (συνήθως της βιβλιοθήκης) και, προαιρετικά, θερμίδες για τη μερίδα. Η
///   μερίδα σε γραμμάρια βγαίνει από τη βάση: πιάτο = όλα τα υλικά στην ίδια αναλογία, ίσες μερίδες = πόσες μερίδες,
///   κατσαρόλα = γραμμάρια από το έτοιμο φαγητό, όταν ζυγιστεί (lib/food/week_calc.dart).
/// - Αποθηκεύεται στο dishes.json (κλειδί «week»): μπαίνει και στο αντίγραφο Google μαζί με τα φαγητά.
library;

import '../history.dart' show dateKey;
import 'dishes.dart';
import 'food_model.dart';
import 'library.dart';
import 'recipe.dart' show jsonOfKind;

const weekKind = 'ygeia-week';

/// Χωρίς στόχους διατροφής δεν βγαίνουν μερίδες (έλεγχος 20/11: πριν έγραφε «Εγώ ›», μενού που δεν υπάρχει).
const noGoalsText = 'Πρώτα βάλε στόχους διατροφής (Ρυθμίσεις › Τα στοιχεία μου › Στόχοι διατροφής): από αυτούς βγαίνουν '
    'οι μερίδες.';
const weekPromptTitle = 'ΠΡΟΓΡΑΜΜΑ ΕΒΔΟΜΑΔΑΣ ΓΙΑ ΤΗΝ ΕΦΑΡΜΟΓΗ «ΥΓΕΙΑ & ΦΟΡΜΑ»';

/// Όρια (δική μας επιλογή): ως 14 μέρες, ως 6 γεύματα τη μέρα, μερίδα 30–2.500 kcal.
const maxPlanDays = 14;
const maxSlotsPerDay = 6;
const minSlotKcal = 30.0;
const maxSlotKcal = 2500.0;

/// Τι έγινε με ένα γεύμα του προγράμματος.
enum SlotState {
  /// Δεν έχει γραφτεί ακόμα.
  open,

  /// «Το έφαγα»: γράφτηκε στο ημερολόγιο (με [PlanSlot.grp]).
  ate,

  /// «Δεν το έφαγα».
  skip,

  /// «Έφαγα κάτι άλλο» (γράφτηκε στο ημερολόγιο κανονικά).
  other,
}

SlotState _stateOf(Object? v) {
  for (final s in SlotState.values) {
    if (s.name == v) return s;
  }
  return SlotState.open;
}

/// Ένα γεύμα του προγράμματος.
class PlanSlot {
  const PlanSlot({required this.meal, required this.dishId, this.kcal, this.locked = false, this.state = SlotState.open, this.grp});
  final Meal meal;

  /// Το φαγητό ([Dish.id]).
  final String dishId;

  /// Θερμίδες για τη μερίδα (null: η μερίδα της συνταγής: όλο το πιάτο, 1 μερίδα, ή 1 από τις μερίδες της κατσαρόλας).
  final double? kcal;

  /// Κλειδωμένο: μένει όταν ξαναφτιάχνεται η εβδομάδα.
  final bool locked;
  final SlotState state;

  /// «Το έφαγα»: η ομάδα των καταχωρίσεων στο ημερολόγιο ([DishTag.grp]).
  final String? grp;

  PlanSlot copyWith({String? dishId, double? kcal, bool clearKcal = false, bool? locked, SlotState? state, String? grp, bool clearGrp = false}) =>
      PlanSlot(
        meal: meal,
        dishId: dishId ?? this.dishId,
        kcal: clearKcal ? null : (kcal ?? this.kcal),
        locked: locked ?? this.locked,
        state: state ?? this.state,
        grp: clearGrp ? null : (grp ?? this.grp),
      );

  Map<String, Object> toJson() => {
        'meal': meal.name,
        'dish': dishId,
        if (kcal != null) 'kcal': kcal!,
        if (locked) 'lock': true,
        if (state != SlotState.open) 'st': state.name,
        if (grp != null) 'grp': grp!,
      };

  static PlanSlot? fromJson(Object? j) {
    if (j is! Map) return null;
    final m = mealOfName(j['meal']), d = j['dish'], k = j['kcal'], g = j['grp'];
    if (m == null || d is! String || d.isEmpty) return null;
    return PlanSlot(
      meal: m,
      dishId: d,
      kcal: k is num && k.isFinite && k >= minSlotKcal && k <= maxSlotKcal ? k.toDouble() : null,
      locked: j['lock'] == true,
      state: _stateOf(j['st']),
      grp: g is String && g.isNotEmpty ? g : null,
    );
  }
}

/// Το πρόγραμμα: από τη μέρα [from] ([dateKey]), μία λίστα γευμάτων για κάθε μέρα.
class WeekPlan {
  const WeekPlan({required this.from, required this.days, required this.created, this.source = 'paste', this.meals});
  final String from;

  /// Τα γεύματα κάθε μέρας, με τη σειρά των ημερών από το [from].
  final List<List<PlanSlot>> days;
  final int created;

  /// «paste» (επικόλληση), «auto» (το έφτιαξε η εφαρμογή) ή «ai» (AI για το φαγητό).
  final String source;

  /// Τα γεύματα που ζητήθηκαν (19/11, U-8): ώστε ένα γεύμα που έμεινε κενό να φαίνεται και να συμπληρώνεται, και το
  /// «Ξαναφτιάξ’ το» να ξέρει ποια γεύματα θέλεις. null στα παλιά/επικολλημένα προγράμματα.
  final List<Meal>? meals;

  DateTime get start => DateTime.parse(from);
  DateTime dayAt(int i) => DateTime(start.year, start.month, start.day + i);
  DateTime get end => dayAt(days.length - 1);

  /// Η θέση της μέρας [d] στο πρόγραμμα, ή -1.
  int indexOf(DateTime d) {
    for (var i = 0; i < days.length; i++) {
      final x = dayAt(i);
      if (x.year == d.year && x.month == d.month && x.day == d.day) return i;
    }
    return -1;
  }

  List<PlanSlot> slotsFor(DateTime d) {
    final i = indexOf(d);
    return i < 0 ? const [] : days[i];
  }

  WeekPlan withSlot(int day, int index, PlanSlot s) => WeekPlan(
        from: from,
        created: created,
        source: source,
        meals: meals,
        days: [
          for (var i = 0; i < days.length; i++)
            i == day ? [for (var k = 0; k < days[i].length; k++) k == index ? s : days[i][k]] : days[i],
        ],
      );

  Map<String, Object> toJson() => {
        'from': from,
        'created': created,
        'source': source,
        if (meals != null) 'meals': [for (final m in meals!) m.name],
        'days': [
          for (final d in days) [for (final s in d) s.toJson()],
        ],
      };

  static WeekPlan? fromJson(Object? j) {
    if (j is! Map) return null;
    final from = j['from'], days = j['days'], c = j['created'], src = j['source'], ms = j['meals'];
    if (from is! String || parseDayKey(from) == null || days is! List || days.isEmpty || days.length > maxPlanDays) return null;
    final out = <List<PlanSlot>>[];
    for (final d in days) {
      if (d is! List) return null;
      out.add([
        for (final s in d.take(maxSlotsPerDay))
          if (PlanSlot.fromJson(s) case final p?) p,
      ]);
    }
    return WeekPlan(
      from: from,
      days: out,
      created: c is num && c.isFinite ? c.toInt() : 0,
      source: src is String && src.isNotEmpty ? src : 'paste',
      meals: ms is List ? [for (final m in Meal.values) if (ms.contains(m.name)) m] : null,
    );
  }

  /// Με μία θέση ακόμα στη μέρα [day] (π.χ. γεύμα που είχε μείνει κενό).
  WeekPlan withAdded(int day, PlanSlot s) => WeekPlan(
        from: from,
        created: created,
        source: source,
        meals: meals,
        days: [
          for (var i = 0; i < days.length; i++) i == day ? [...days[i], s] : days[i],
        ],
      );
}

/// «2026-11-16» → η μέρα, ή null αν δεν είναι σωστή ημερομηνία.
DateTime? parseDayKey(String s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (m == null) return null;
  final d = DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  return dateKey(d) == s ? d : null;
}

// ---------------------------------------------------------------------------
// Επικόλληση προγράμματος (από τον βοηθό, με τα κλειδιά της βιβλιοθήκης)
// ---------------------------------------------------------------------------

class WeekParse {
  const WeekParse(this.plan, this.errors);
  final WeekPlan? plan;
  final List<String> errors;
}

/// Διαβάζει ένα πρόγραμμα από ό,τι επικόλλησες. [dishes]: τα φαγητά μου (τα γεύματα δείχνουν φαγητά της βιβλιοθήκης με
/// το «key» τους). Αυστηρό: ένα γεύμα με πρόβλημα, και δεν περνά το πρόγραμμα (ώστε να μη μείνουν κενά χωρίς να το δεις).
WeekParse parseWeek(String text, List<Dish> dishes, {required int now}) {
  if (!text.contains('{')) {
    return const WeekParse(null, ['Δεν βρέθηκε πρόγραμμα στο κείμενο. Αντίγραψε ολόκληρη την απάντηση του βοηθού.']);
  }
  final j = jsonOfKind(text, weekKind);
  if (j == null && text.contains(weekPromptTitle)) {
    return const WeekParse(null, [
      'Αυτές είναι οι οδηγίες που αντιγράφηκαν, όχι η απάντηση. Επικόλλησέ τες στο AI, και μετά αντίγραψε την απάντησή του.'
    ]);
  }
  if (j == null) {
    return const WeekParse(null, [
      'Το κείμενο δεν είναι πρόγραμμα της εφαρμογής, ή αντιγράφηκε μισό. Αντίγραψε ολόκληρη την απάντηση· αν ξαναβγεί, ζήτα '
          'από τον βοηθό να το γράψει ξανά στη μορφή των οδηγιών.'
    ]);
  }
  final errors = <String>[];
  final from = j['from'];
  if (from is! String || parseDayKey(from) == null) errors.add('Λείπει η πρώτη μέρα («from», π.χ. "2026-11-16").');
  final days = j['days'];
  if (days is! List || days.isEmpty) {
    errors.add('Το πρόγραμμα δεν έχει μέρες («days»).');
    return WeekParse(null, errors);
  }
  if (days.length > maxPlanDays) {
    errors.add('Πολλές μέρες (${days.length}): το πολύ $maxPlanDays.');
    return WeekParse(null, errors);
  }
  final byKey = <String, Dish>{
    for (final d in dishes)
      if (planInfoOf(d)?.key case final k?) k: d,
  };
  final out = <List<PlanSlot>>[];
  for (var i = 0; i < days.length; i++) {
    final d = days[i];
    final list = d is Map ? d['meals'] : d;
    final label = 'Μέρα ${i + 1}';
    if (list is! List) {
      errors.add('$label: δεν διαβάζεται.');
      out.add(const []);
      continue;
    }
    if (list.length > maxSlotsPerDay) errors.add('$label: πολλά γεύματα (${list.length}), το πολύ $maxSlotsPerDay.');
    final slots = <PlanSlot>[];
    for (final s in list.take(maxSlotsPerDay)) {
      if (s is! Map) {
        errors.add('$label: ένα γεύμα δεν διαβάζεται.');
        continue;
      }
      final meal = mealOfName(s['meal']);
      final key = s['key'];
      final k = s['kcal'];
      final dish = key is String ? byKey[key] : null;
      if (meal == null) errors.add('$label: άγνωστο γεύμα «${s['meal']}» (breakfast, lunch, dinner, snack).');
      if (dish == null) errors.add('$label: δεν υπάρχει στη βιβλιοθήκη φαγητό με key «$key».');
      // 19/11 (I-5): ό,τι σημείωσες «Δεν μου άρεσε» δεν μπαίνει ούτε με επικόλληση.
      if (dish != null && dishRating(dish) < 0) errors.add('$label: το «${dish.name}» δεν σου άρεσε· άλλαξέ το.');
      if (k != null && (k is! num || !k.isFinite || k < minSlotKcal || k > maxSlotKcal)) {
        errors.add('$label: οι θερμίδες («kcal») πρέπει να είναι από ${minSlotKcal.round()} ως ${maxSlotKcal.round()}.');
      }
      if (meal != null && dish != null) {
        slots.add(PlanSlot(meal: meal, dishId: dish.id, kcal: k is num && k.isFinite ? k.toDouble() : null));
      }
    }
    out.add(slots);
  }
  if (errors.isNotEmpty) return WeekParse(null, errors);
  return WeekParse(WeekPlan(from: from as String, days: out, created: now, source: 'paste'), const []);
}

/// Νέο πρόγραμμα που επικολλάται ενώ υπάρχει άλλο: τα γεύματα που έχεις ήδη σημειώσει («Το έφαγα», «Δεν το έφαγα»,
/// «Κάτι άλλο») σε μέρες που καλύπτουν και τα δύο μένουν όπως ήταν, αν είναι στο ίδιο γεύμα με το ίδιο φαγητό.
WeekPlan keepDone(WeekPlan next, WeekPlan? old) {
  if (old == null) return next;
  return WeekPlan(
    from: next.from,
    created: next.created,
    source: next.source,
    meals: next.meals,
    days: [
      for (var i = 0; i < next.days.length; i++)
        [
          for (final s in next.days[i])
            () {
              final prev = old.slotsFor(next.dayAt(i)).where((o) => o.meal == s.meal && o.dishId == s.dishId && o.state != SlotState.open);
              return prev.isEmpty ? s : s.copyWith(state: prev.first.state, grp: prev.first.grp);
            }(),
        ],
    ],
  );
}
