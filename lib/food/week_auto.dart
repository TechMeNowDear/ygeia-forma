/// Αυτόματο πρόγραμμα εβδομάδας με κανόνες, χωρίς AI (16/11, απόφαση χρήστη: «σημαντικό, από τώρα»).
///
/// Κανόνες (έγγραφο προδιαγραφών › «Αποφάσεις χρήστη 16/11» και «Αυτόματο πρόγραμμα»):
/// 1. Μόνο φαγητά της βιβλιοθήκης, που ταιριάζουν στο γεύμα, χωρίς υλικό που λείπει ή που δεν σου αρέσει.
/// 2. Τρίτη–Πέμπτη το μεσημεριανό μόνο από τα «για γραφείο».
/// 3. Όσπρια και ψάρι όσες φορές την εβδομάδα λένε οι στόχοι.
/// 4. Κατσαρόλα: μαγειρεύεται μία φορά και τρώγεται μέσα σε 4 μέρες (ως 2 φορές), όχι δύο μέρες στη σειρά, εκτός αν η
///    δεύτερη είναι ταπεράκι για το γραφείο.
/// 5. Το ίδιο φαγητό (μεσημέρι, βράδυ, πρωινό) ως 2 φορές την εβδομάδα, ποτέ δύο φορές την ίδια μέρα ή δύο μέρες στη
///    σειρά (εκτός από τον 4). Τα σνακ επαναλαμβάνονται. Αν τα φαγητά δεν φτάνουν, ένα φαγητό ξαναμπαίνει και το λέει.
/// 6. Θερμίδες κάθε μέρας ±5% από τον στόχο, με μερίδες 0,6–1,6 φορές τη μερίδα της συνταγής (όχι «τριπλή σαλάτα»· στην
///    κατσαρόλα και στις ίσες μερίδες ως 2).
///    Οι θερμίδες και η πρωτεΐνη βγαίνουν πάντα από τη βάση. Ό,τι δεν βγαίνει λέγεται ([AutoWeek.notes]).
/// 7. Κλειδωμένες θέσεις του προγράμματος που υπάρχει μένουν όπως είναι.
library;

import 'dart:math' as math;

import '../history.dart' show dateKey;
import 'dishes.dart';
import 'food_model.dart';
import 'food_store.dart';
import 'library.dart';
import 'week.dart';
import 'week_calc.dart';

/// Πώς μοιράζονται οι θερμίδες της μέρας στα γεύματα (κανονικοποιείται στα γεύματα που επιλέχτηκαν).
const mealShare = {Meal.breakfast: 0.25, Meal.lunch: 0.40, Meal.dinner: 0.35, Meal.snack: 0.20};

/// Μέρες με γραφείο (απόφαση χρήστη 15/11: Τρίτη–Πέμπτη).
const officeWeekdays = {DateTime.tuesday, DateTime.wednesday, DateTime.thursday};

const autoMaxRepeat = 2;
const autoPotDays = 4;
const autoDayTolerance = 0.05;
const autoPortionMin = 0.6, autoPortionMax = 1.6;

class AutoWeek {
  const AutoWeek(this.plan, this.notes);
  final WeekPlan plan;

  /// Ό,τι δεν βγήκε όπως ζητούν οι κανόνες, σε απλά λόγια.
  final List<String> notes;
}

class _Cand {
  _Cand(this.dish, this.info, this.lo, this.hi, this.natural, this.proteinPerKcal);
  final Dish dish;
  final PlanInfo info;
  final double lo, hi;
  final double? natural;
  final double proteinPerKcal;
  bool get pot => dish.kind == DishKind.pot;
  bool get legumes => info.hasTag('όσπρια');
  bool get fish => info.hasTag('ψάρι') || info.hasTag('λιπαρό ψάρι');
}

/// Τα όρια της μερίδας ενός φαγητού σε θερμίδες (ίδια για τους κανόνες και το AI, 19/11): από 0,6 της μερίδας της
/// συνταγής ως 1,6 (πιάτο) ή 2 (κατσαρόλα, ίσες μερίδες). null αν δεν βγαίνουν θερμίδες από τη βάση.
({double lo, double hi, double? natural, double proteinPerKcal, double satPerKcal})? portionRange(FoodStore food, Dish d) {
  final all = itemsTotals(food, d.items);
  if (all == null || all.kcal <= 0) return null;
  final nat = naturalRaw(d);
  final n = nat == null ? null : itemsTotals(food, nat)?.kcal;
  final lo = n == null ? 150.0 : math.max(minSlotKcal, n * autoPortionMin);
  // Κατσαρόλα και ίσες μερίδες: ως 2 μερίδες (βάζεις λίγο παραπάνω, 2 μπιφτέκια)· πιάτο ως 1,6 φορές.
  final hi = n == null ? 1200.0 : math.min(maxSlotKcal, n * (d.kind == DishKind.plate ? autoPortionMax : 2.0));
  // Πολύ μικρό φαγητό (π.χ. καφές 14 kcal): πάντα lo ≤ hi (έλεγχος 16/11: αλλιώς το clamp έσκαγε).
  return (lo: lo, hi: math.max(lo, hi), natural: n, proteinPerKcal: all.protein / all.kcal, satPerKcal: all.satFat / all.kcal);
}

/// Φτιάχνει πρόγραμμα [days] ημερών από τη [from]. [seed]: άλλο seed → άλλη (εξίσου σωστή) εβδομάδα.
AutoWeek autoWeek(
  FoodStore food, {
  required DateTime from,
  required List<Meal> meals,
  required double kcalTarget,
  required double proteinTarget,
  int legumesWeek = 0,
  int fishWeek = 0,
  int days = 7,
  int seed = 1,
  WeekPlan? keep,
  int? now,
  List<Dish> extra = const [],
  Map<(int, Meal), String> forced = const {},
}) {
  final rnd = math.Random(seed);
  final notes = <String>[];
  final dislikes = food.likes.dislike.toSet();
  final cands = <_Cand>[];
  // 19/11 (AI): [extra] = φαγητά που δεν έχουν αποθηκευτεί ακόμα (μπαίνουν μόνο αν πεις «Ναι, το νέο»). [forced] = ποιο
  // φαγητό σε ποια θέση (μέρα, γεύμα) διάλεξε το AI: οι μερίδες βγαίνουν από εδώ, όπως σε κάθε άλλο πρόγραμμα.
  for (final d in libraryDishes([...food.dishes.where((x) => !extra.any((e) => e.id == x.id)), ...extra])) {
    final info = planInfoOf(d)!;
    if (food.missingItems(d.items).isNotEmpty) continue;
    if (d.items.any((i) => dislikes.contains(i.id))) continue;
    if (dishRating(d) < 0) continue; // «Δεν μου άρεσε»
    final r = portionRange(food, d);
    if (r == null) continue;
    cands.add(_Cand(d, info, r.lo, r.hi, r.natural, r.proteinPerKcal));
  }
  final ordered = [for (final m in Meal.values) if (meals.contains(m)) m];
  final shareSum = ordered.fold(0.0, (a, m) => a + mealShare[m]!);
  double target(Meal m) => kcalTarget * mealShare[m]! / shareSum;

  final start = DateTime(from.year, from.month, from.day);
  final used = <String, List<int>>{}; // dishId → μέρες
  var legumes = 0, fish = 0;
  final out = <List<PlanSlot>>[];
  final keepPlan = keep != null && keep.from == dateKey(start) ? keep : null;
  final noOffice = <String>{};
  final repeated = <String>[];

  for (var day = 0; day < days; day++) {
    final date = DateTime(start.year, start.month, start.day + day);
    final office = officeWeekdays.contains(date.weekday);
    // Μένουν όσα κλείδωσες και όσα έχουν ήδη γίνει («Το έφαγα», «Δεν το έφαγα»· έλεγχος 16/11: αλλιώς το «Ξαναφτιάξ’
    // το» στη μέση της εβδομάδας άλλαζε γεύματα που είχες ήδη φάει).
    final kept = keepPlan != null && day < keepPlan.days.length
        ? keepPlan.days[day].where((s) => s.locked || s.state != SlotState.open).toList()
        : const <PlanSlot>[];
    final chosen = <(Meal, _Cand?, PlanSlot?)>[];
    for (final m in ordered) {
      final k = kept.where((s) => s.meal == m).firstOrNull;
      if (k != null) {
        final c = cands.where((c) => c.dish.id == k.dishId).firstOrNull;
        chosen.add((m, c, k));
        (used[k.dishId] ??= []).add(day);
        // Και τα κρατημένα μετρούν στα όσπρια και στο ψάρι της εβδομάδας (έλεγχος 16/11).
        if (c != null && c.legumes) legumes++;
        if (c != null && c.fish) fish++;
        continue;
      }
      final officeLunch = office && m == Meal.lunch;
      final f = forced[(day, m)];
      if (f != null) {
        final c = cands.where((c) => c.dish.id == f).firstOrNull;
        if (c == null) {
          notes.add('${_dayName(date)}: το φαγητό για ${mealLabel(m).toLowerCase()} δεν μπορεί να μπει (λείπει υλικό ή '
              'δεν σου αρέσει).');
          continue;
        }
        chosen.add((m, c, null));
        (used[c.dish.id] ??= []).add(day);
        if (c.legumes) legumes++;
        if (c.fish) fish++;
        continue;
      }
      if (forced.isNotEmpty) continue; // Με επιλογές του AI: μόνο ό,τι διάλεξε (καμία θέση δεν γεμίζει «κρυφά»).
      final daysLeft = days - day;
      double score(_Cand c) {
        final t = target(m);
        var s = -((t.clamp(c.lo, c.hi) - t).abs() / t) * 3;
        final u = used[c.dish.id] ?? const [];
        if (c.pot && u.isNotEmpty) s += 1.5; // περισσεύματα πρώτα (όχι πέταμα)
        if (dishRating(c.dish) > 0) s += 0.8; // «Μου άρεσε»
        if (c.legumes && legumes < legumesWeek) s += 1.2 * (legumesWeek - legumes) / daysLeft + 0.6;
        if (c.fish && fish < fishWeek) s += 1.2 * (fishWeek - fish) / daysLeft + 0.6;
        s += c.proteinPerKcal * 8; // πρωτεΐνη ανά θερμίδα: προτίμηση στα πιο πρωτεϊνούχα
        if (u.isNotEmpty) s -= 0.4; // ποικιλία
        return s + rnd.nextDouble() * 0.5;
      }

      bool basic(_Cand c) =>
          c.info.fits(m) && !(officeLunch && !c.info.office) && !chosen.any((x) => x.$2?.dish.id == c.dish.id);

      bool allowed(_Cand c) {
        if (!basic(c)) return false;
        // Σνακ: επαναλαμβάνονται (το ίδιο γιαούρτι κάθε μέρα είναι εντάξει)· η ποικιλία μετρά μόνο στη βαθμολογία.
        if (m == Meal.snack) return true;
        final u = used[c.dish.id] ?? const [];
        if (u.length >= autoMaxRepeat) return false;
        if (u.isEmpty) return true;
        final last = u.last;
        if (c.pot) {
          if (day - u.first >= autoPotDays) return false;
          return day - last >= 2 || officeLunch;
        }
        return day - last >= 2;
      }

      var ok = [for (final c in cands) if (allowed(c)) c];
      if (ok.isEmpty) {
        // Λίγα φαγητά για τους κανόνες ποικιλίας: καλύτερα ένα φαγητό ξανά παρά άδειο γεύμα. Το λέει.
        ok = [for (final c in cands) if (basic(c)) c];
        if (ok.isNotEmpty) repeated.add('${_dayName(date)}, ${mealLabel(m).toLowerCase()}');
      }
      if (ok.isEmpty) {
        if (officeLunch) {
          noOffice.add(m.name);
        } else {
          notes.add('${_dayName(date)}: δεν βρέθηκε φαγητό για ${mealLabel(m).toLowerCase()}.');
        }
        continue;
      }
      // Μία βαθμολογία ανά φαγητό (έλεγχος 16/11: πριν ο τυχαίος αριθμός άλλαζε σε κάθε σύγκριση της ταξινόμησης).
      final scores = {for (final c in ok) c: score(c)};
      ok.sort((a, b) => scores[b]!.compareTo(scores[a]!));
      final pick = ok.first;
      chosen.add((m, pick, null));
      (used[pick.dish.id] ??= []).add(day);
      if (pick.legumes) legumes++;
      if (pick.fish) fish++;
    }

    // Θερμίδες: από το μερίδιο κάθε γεύματος, μέσα στα όρια της μερίδας· ό,τι λείπει ή περισσεύει μοιράζεται. Γεύμα που
    // έμεινε κενό (π.χ. χωρίς φαγητό για γραφείο) κρατά το μερίδιό του: δεν φορτώνεται στα άλλα (έλεγχος 16/11).
    final dayTarget = chosen.fold(0.0, (a, x) => a + target(x.$1));
    final kc = <double>[
      for (final (m, c, k) in chosen) k?.kcal ?? (c == null ? target(m) : target(m).clamp(c.lo, c.hi).toDouble()),
    ];
    for (var round = 0; round < 4; round++) {
      final diff = dayTarget - kc.fold(0.0, (a, b) => a + b);
      if (diff.abs() <= dayTarget * 0.01) break;
      final room = <int>[
        for (var i = 0; i < chosen.length; i++)
          if (chosen[i].$3 == null && chosen[i].$2 != null && (diff > 0 ? kc[i] < chosen[i].$2!.hi : kc[i] > chosen[i].$2!.lo)) i,
      ];
      if (room.isEmpty) break;
      for (final i in room) {
        final c = chosen[i].$2!;
        kc[i] = (kc[i] + diff / room.length).clamp(c.lo, c.hi).toDouble();
      }
    }
    // Ίσες μερίδες: μόνο ολόκληρες ή μισές μερίδες σερβίρονται (όπως στο «Το έφαγα»)· η διαφορά πάει στα άλλα γεύματα
    // (έλεγχος 16/11: πριν 750 kcal στο πρόγραμμα και 1,5 μερίδα = 900 kcal στο πιάτο).
    final snapped = <int>{};
    for (var i = 0; i < chosen.length; i++) {
      final c = chosen[i].$2;
      if (chosen[i].$3 != null || c == null || c.dish.kind != DishKind.portions || c.natural == null) continue;
      final half = c.natural! / 2;
      final halves = (kc[i] / half).round().clamp(1, (maxEatenServings * 2).round()).toInt();
      kc[i] = halves * half;
      snapped.add(i);
    }
    if (snapped.isNotEmpty) {
      final diff = dayTarget - kc.fold(0.0, (a, b) => a + b);
      final room = [
        for (var i = 0; i < chosen.length; i++)
          if (!snapped.contains(i) && chosen[i].$3 == null && chosen[i].$2 != null) i,
      ];
      for (final i in room) {
        final c = chosen[i].$2!;
        kc[i] = (kc[i] + diff / room.length).clamp(c.lo, c.hi).toDouble();
      }
    }
    final slots = <PlanSlot>[];
    var dayKcal = 0.0, dayProtein = 0.0;
    for (var i = 0; i < chosen.length; i++) {
      final (m, c, k) = chosen[i];
      if (k != null) {
        slots.add(k);
        dayKcal += k.kcal ?? kc[i];
        if (c != null) dayProtein += (k.kcal ?? kc[i]) * c.proteinPerKcal;
        continue;
      }
      final v = snapped.contains(i)
          ? kc[i].roundToDouble()
          : ((kc[i] / 10).round() * 10).toDouble().clamp(minSlotKcal, maxSlotKcal).toDouble();
      slots.add(PlanSlot(meal: m, dishId: c!.dish.id, kcal: v));
      dayKcal += v;
      dayProtein += v * c.proteinPerKcal;
    }
    out.add(slots);
    if (slots.isNotEmpty && (dayKcal - dayTarget).abs() > dayTarget * autoDayTolerance) {
      notes.add('${_dayName(date)}: ${dayKcal.round()} kcal (στόχος ${dayTarget.round()}): οι μερίδες των φαγητών δεν '
          'φτάνουν για ακριβώς τον στόχο.');
    }
    final dayProteinTarget = proteinTarget * dayTarget / kcalTarget;
    if (slots.isNotEmpty && dayProtein < dayProteinTarget * 0.9) {
      notes.add('${_dayName(date)}: πρωτεΐνη ${dayProtein.round()} g (στόχος ${dayProteinTarget.round()}).');
    }
  }
  if (noOffice.isNotEmpty) {
    notes.insert(0, 'Δεν υπάρχει (αρκετό) φαγητό «για γραφείο»: κάποια μεσημεριανά Τρίτη–Πέμπτη έμειναν κενά.');
  }
  if (repeated.isNotEmpty) {
    notes.add('Επαναλαμβάνεται φαγητό πιο συχνά απ’ όσο λένε οι κανόνες (λίγα φαγητά στη βιβλιοθήκη): ${repeated.join(' · ')}.');
  }
  if (legumesWeek > 0 && legumes < legumesWeek) notes.add('Όσπρια $legumes φορές (στόχος $legumesWeek): λίγα στη βιβλιοθήκη.');
  if (fishWeek > 0 && fish < fishWeek) notes.add('Ψάρι $fish φορές (στόχος $fishWeek): λίγο στη βιβλιοθήκη.');
  return AutoWeek(
    WeekPlan(from: dateKey(start), days: out, created: now ?? DateTime.now().millisecondsSinceEpoch, source: 'auto'),
    notes,
  );
}

const _wd = ['Δευτέρα', 'Τρίτη', 'Τετάρτη', 'Πέμπτη', 'Παρασκευή', 'Σάββατο', 'Κυριακή'];
String _dayName(DateTime d) => '${_wd[d.weekday - 1]} ${d.day}/${d.month}';

/// Πόσα φαγητά της βιβλιοθήκης μπορούν να μπουν (για το «θέλει τουλάχιστον 20»).
int usableLibrary(FoodStore food) {
  final dislikes = food.likes.dislike.toSet();
  return libraryDishes(food.dishes)
      .where((d) => food.missingItems(d.items).isEmpty && !d.items.any((i) => dislikes.contains(i.id)) && dishRating(d) >= 0)
      .length;
}
