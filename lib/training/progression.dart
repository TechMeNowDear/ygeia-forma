/// Ο «εγκέφαλος» της προόδου: από την προηγούμενη φορά, τι κάνεις σήμερα.
///
/// Διπλή πρόοδος με ρεζέρβα (RIR): πρώτα ανεβαίνουν οι επαναλήψεις ως το πάνω όριο του εύρους, μετά το βάρος
/// (το μικρότερο σκαλί που βγαίνει με τον εξοπλισμό) και οι επαναλήψεις ξαναπάνε στο κάτω όριο.
/// Η πρόταση φαίνεται με τον λόγο της· η απόφαση μένει στον χρήστη.
///
/// Κανόνες του ελέγχου 13/11 (round1), με την πηγή τους:
/// - Η προηγούμενη φορά κρίνεται με τα σετ και το κάτω όριο ΕΚΕΙΝΗΣ της μέρας ([ExLog.sets], [ExLog.lo])· ο σημερινός
///   στόχος ταιριάζει μετά στα σημερινά σετ και εύρος (S6-1: η ίδια άσκηση σε δύο προπονήσεις με άλλα σετ).
/// - Βάρος ανεβαίνει μόνο όταν οι επαναλήψεις δείχνουν ότι το επόμενο σκαλί βγαίνει στο κάτω όριο με την ίδια ρεζέρβα
///   ([repsBeforeStep], S6-12). Οδηγία: αύξηση φορτίου 2–10% όταν βγαίνουν 1–2 επαναλήψεις πάνω από τον στόχο (ACSM,
///   Progression models in resistance training, Med Sci Sports Exerc 2009;41:687–708). Όπου το σκαλί του εξοπλισμού είναι
///   μεγαλύτερο από ~10%, πρώτα περισσότερες επαναλήψεις με το ίδιο (διπλή πρόοδος).
/// - Ο στόχος ρυθμίζεται από τη ρεζέρβα που λες (Zourdos κ.ά., J Strength Cond Res 2016;30:267–75· Helms κ.ά.,
///   Strength Cond J 2016;38(4):42–9): λίγο κάτω από τον στόχο ΜΕ τη ρεζέρβα που ζητά το πρόγραμμα δεν είναι αποτυχία.
library;

import 'dart:math' as math;

import '../exercise/ex_names.dart' show exNamesById;
import '../format.dart' show daysBetween;
import 'equipment.dart';
import 'program.dart';
import 'session.dart';

enum Change {
  /// Πρώτη φορά: από το πρόγραμμα (ή ελαφριά αρχή).
  first,

  /// Περισσότερο βάρος.
  up,

  /// Ίδιο βάρος, +1 επανάληψη.
  more,

  /// Ίδια, χωρίς αλλαγή.
  hold,

  /// Ένα σκαλί κάτω.
  down,

  /// Μετά από διάλειμμα: λίγο πιο ελαφριά.
  back,

  /// Πιο δύσκολη παραλλαγή.
  variant,

  /// Ενόχληση: τίποτα δεν ανεβαίνει.
  pain,

  /// Το μέγιστο του εξοπλισμού.
  max,
}

class Target {
  const Target({required this.load, required this.reps, required this.change, required this.reason, this.variant});

  /// kg/lb, ή null για ασκήσεις σώματος.
  final double? load;

  /// Στόχος επαναλήψεων ανά σετ.
  final List<int> reps;
  final Change change;
  final String reason;

  /// Αν προτείνεται αλλαγή σε πιο δύσκολη παραλλαγή (id άσκησης).
  final String? variant;

  bool get isUp => change == Change.up || change == Change.more || change == Change.variant;
}

/// Αρχικό βάρος όταν το πρόγραμμα δεν δίνει: ελαφριά, για να βρεθεί το σωστό από τις απαντήσεις.
double? defaultStart(LoadKind k) => switch (k) {
      LoadKind.bar => 10,
      LoadKind.dbPair => 4.3,
      LoadKind.db => 6.8,
      LoadKind.kb => 8,
      LoadKind.horn => 2.5,
      LoadKind.band => 20,
      LoadKind.bandPair => 30,
      LoadKind.bandAssist => 50,
      LoadKind.plate => 0,
      LoadKind.bodyweight => null,
    };

/// Αρχικό λάστιχο ανά άσκηση, όπου το γενικό «μπλε (20 lb)» δεν ταιριάζει (S7-02). Η ίδια η βιβλιοθήκη γράφει «ελαφρύ
/// λάστιχο (κίτρινο)» στην εξωτερική στροφή και «κίτρινο ή μπλε» στο face pull: μικροί μύες του ώμου, ελαφριά αντίσταση
/// και πολλές επαναλήψεις (Reinold κ.ά., J Orthop Sports Phys Ther 2004;34:385–94, όπως το παραθέτει ο έλεγχος S7).
const startOverride = <String, double>{'band_er': 10, 'face_pull': 10};

/// Ασκήσεις που μένουν πάντα σε ελαφρύ λάστιχο (στροφικό πέταλο): ποτέ αυτόματα βαρύτερο, μόνο επαναλήψεις (S7-02).
const lightOnly = <String>{'band_er'};

/// Ασκήσεις όπου μαζί με το όργανο σηκώνεις και μεγάλο μέρος του σώματος (πόδια, γοφοί): ένα σκαλί στο όργανο είναι
/// λίγα τοις εκατό του συνόλου, άρα ο τύπος του [repsBeforeStep] (που μετρά μόνο το όργανο) δεν τους ταιριάζει.
const bodyLoaded = <String>{'goblet', 'split_squat', 'hip_thrust', 'rdl'};

/// Πάνω από τόσο (περίπου +10%, ACSM 2009) ένα σκαλί είναι «μεγάλο»: πρώτα περισσότερες επαναλήψεις.
const bigStepRatio = 1.11;

/// Ως τόσες επαναλήψεις πάνω από το πάνω όριο πριν από ένα μεγάλο σκαλί. Αν δεν φτάνουν ούτε αυτές (π.χ. λάστιχο
/// 20 → 30 lb, +50%), το σκαλί δεν γίνεται ποτέ αυτόματα: μένεις [plateauExtraReps] πάνω από το πάνω όριο.
const maxExtraReps = 10;
const plateauExtraReps = 5;

/// Ως τόσες επαναλήψεις κάτω από το κάτω όριο, με τη ρεζέρβα που ζητά το πρόγραμμα, δεν είναι αποτυχία: τόσο πέφτει
/// έξω η εκτίμηση της ρεζέρβας (Halperin κ.ά. 2021, όπως στον έλεγχο S7-15: περίπου 1 επανάληψη κατά μέσο όρο).
const closeReps = 2;

double? startLoad(String ex, LoadKind k) => startOverride[ex] ?? defaultStart(k);

/// Το νούμερο του οργάνου είναι όλο το φορτίο (αλτήρες και λάστιχα σε ασκήσεις του πάνω μέρους). Όχι: μπάρα και
/// kettlebell (δικοί τους κανόνες, όπως πριν), κέρατο και δίσκος (μαζί τους ο μοχλός ή το σώμα), [bodyLoaded].
bool labelIsLoad(String ex, LoadKind k) =>
    (k == LoadKind.dbPair || k == LoadKind.db || k == LoadKind.band || k == LoadKind.bandPair) && !bodyLoaded.contains(ex);

/// Πόσες επαναλήψεις χρειάζονται με το τωρινό φορτίο ώστε με [ratio] φορές βαρύτερο να βγαίνουν [lo] με την ίδια
/// ρεζέρβα [rirGoal]. Από τη σχέση του Epley (μέγιστο ≈ φορτίο × (1 + επαναλήψεις ως την εξάντληση ÷ 30)):
/// ratio × (30 + lo + ρεζέρβα) − 30 − ρεζέρβα. Παράδειγμα: 8–12, ρεζέρβα 3, αλτήρες 4,3 → 5,3 kg (+23%) → 18.
int repsBeforeStep(double ratio, int lo, int rirGoal) => (ratio * (30 + lo + rirGoal) - 30 - rirGoal - 1e-6).ceil();

/// Σε πόσες επαναλήψεις ([reps]) ανεβαίνει το βάρος από [load] σε [up], και αν ανεβαίνει αυτόματα ([step]).
({int reps, bool step}) stepCeiling(String ex, LoadKind k, double? load, double? up, int lo, int hi, int rirGoal) {
  if (up == null || load == null || load <= 0) return (reps: hi, step: true);
  final q = up / load;
  // Kettlebell: όταν το επόμενο είναι πάνω από 20% βαρύτερο, πρώτα 3 επαναλήψεις παραπάνω από το εύρος (όπως πριν).
  if (k == LoadKind.kb && q > 1.2) return (reps: hi + 3, step: true);
  if (labelIsLoad(ex, k) && q > bigStepRatio) {
    final need = repsBeforeStep(q, lo, rirGoal);
    if (need <= hi + maxExtraReps) return (reps: math.max(hi, need), step: true);
    return (reps: hi + plateauExtraReps, step: false);
  }
  return (reps: hi, step: true);
}

List<int> _same(int sets, int r) => List.filled(sets, r);

String _l(LoadKind k, double? v) => loadLabel(k, v);

/// Το φορτίο με το οποίο ΤΕΛΕΙΩΣΕ η άσκηση: του τελευταίου σετ που έγινε. Όχι το μεγαλύτερο ([ExLog.workLoad]): αν μετά
/// το 1ο σετ το βάρος κατέβηκε (βαθμονόμηση, S6-7) ή ανέβηκε, η επόμενη φορά ξεκινά από εκεί που κατέληξες.
double? _endLoad(ExLog e) {
  final d = e.done;
  for (var i = d.length - 1; i >= 0; i--) {
    if (d[i].load != null) return d[i].load;
  }
  return null;
}

/// Οι λιγότερες επαναλήψεις στα σετ που έγιναν με το φορτίο [load] (τα σετ με άλλο φορτίο δεν κρίνονται).
int _lowAt(ExLog e, double? load) {
  int? low;
  for (final s in e.done) {
    if (s.load == load && (low == null || s.reps < low)) low = s.reps;
  }
  return low ?? 0;
}

/// [a] είναι ευκολότερο φορτίο από το [b] (στο λάστιχο βοήθειας: περισσότερη βοήθεια).
bool _easier(LoadKind k, double a, double b) => k == LoadKind.bandAssist ? a > b : a < b;

const _hint = ' Αν είναι πολύ ελαφρύ (θα έβγαζες άνετα τις τριπλάσιες), ανέβασε ένα σκαλί με το «+».';

/// Η συμβουλή «ανέβασέ το εσύ» (S7-22) ταιριάζει: αλτήρες με μεγάλο σκαλί (ως +34%), και όταν «τριπλάσιες» επαναλήψεις
/// φτάνουν πράγματι για το σκαλί ([repsBeforeStep] χωρίς τη ρεζέρβα: ratio × (30 + lo + ρεζέρβα) − 30).
bool _hintFits(PlanItem item, LoadKind k, double? load, double? up, int rirGoal) {
  if (load == null || up == null || load <= 0) return false;
  if ((k != LoadKind.dbPair && k != LoadKind.db) || !labelIsLoad(item.ex, k) || lightOnly.contains(item.ex)) return false;
  final q = up / load;
  return q > bigStepRatio && q <= 1.34 && 3 * item.lo >= q * (30 + item.lo + rirGoal) - 30;
}

String _firstReason(PlanItem item, LoadKind k, double? start, int rirGoal) {
  if (!hasLoad(k)) return 'Πρώτη φορά: σταμάτα κάθε σετ όταν σου μένουν $rirGoal, όσες επαναλήψεις κι αν βγουν.';
  if (item.load != null) return 'Πρώτη φορά. Μετά το 1ο σετ θα σε ρωτήσει πώς πήγε, για να βρεθεί το σωστό βάρος.';
  if (!labelIsLoad(item.ex, k)) return 'Πρώτη φορά: ελαφριά αρχή. Μετά το 1ο σετ θα σε ρωτήσει πώς πήγε και θα προτείνει βάρος.';
  final up = start == null ? null : stepUp(k, start);
  return 'Πρώτη φορά: ελαφριά αρχή. Μετά το 1ο σετ θα σε ρωτήσει πώς πήγε.${_hintFits(item, k, start, up, rirGoal) ? _hint : ''}';
}

/// [history]: οι προηγούμενες φορές της ίδιας άσκησης, νεότερη πρώτη, με την ημερομηνία τους.
/// [caution]: άσκηση με προσοχή στη βιβλιοθήκη (ώμοι, μέση): χωρίς απάντηση για ρεζέρβα δεν ανεβαίνει τίποτα.
Target nextTarget(PlanItem item, List<(DateTime, ExLog)> history, DateTime today, {bool caution = false}) {
  final k = item.kind;
  final sets = item.sets, lo = item.lo, hi = item.hi;
  // Τουλάχιστον 2 ρεζέρβα σε όλες τις ασκήσεις, ως να πει άλλα ο καρδιολόγος: η πίεση ανεβαίνει απότομα
  // όσο πλησιάζεις την αποτυχία (MacDougall 1985· έλεγχος #2). Το πρόγραμμα μπορεί να ζητά περισσότερη.
  final rirGoal = math.max(item.rir, 2);
  final usable = [for (final h in history) if (!h.$2.skipped && h.$2.done.isNotEmpty) h];

  if (usable.isEmpty) {
    final start = hasLoad(k) ? (item.load != null ? snap(k, item.load!) : startLoad(item.ex, k)) : null;
    return Target(load: start, reps: _same(sets, lo), change: Change.first, reason: _firstReason(item, k, start, rirGoal));
  }

  final (lastDay, last) = usable.first;
  final done = last.done;
  final endLoad = _endLoad(last);
  var lastLoad = endLoad ?? (hasLoad(k) ? (item.load ?? startLoad(item.ex, k)) : null);
  // Ανοίγματα με λάστιχο, από πριν το «ανά πλευρά» (π.χ. 20): στο πλησιέστερο που βγαίνει (ελάχιστο 30/πλευρά).
  if (k == LoadKind.bandPair && lastLoad != null) lastLoad = snap(k, lastLoad);
  // Ημερολογιακές μέρες σε UTC (έλεγχος 9/11, RT-17 / V-B-17): πάνω από την αλλαγή ώρας του Μαρτίου, 15 μέρες δεν
  // μετριούνται πια 14 (14 μέρες + 23 ώρες).
  final gap = daysBetween(lastDay, today);

  // Μετά από πάνω από 2 εβδομάδες: περίπου 10% πιο ελαφριά.
  if (gap > 14 && lastLoad != null && hasLoad(k)) {
    final v = scaled(k, lastLoad, 0.9);
    return Target(
      load: v,
      reps: _same(sets, lo),
      change: Change.back,
      reason: 'Πέρασαν $gap μέρες από την τελευταία φορά: λίγο πιο ελαφριά για αρχή.',
    );
  }

  // Χωρίς απάντηση δεν ξέρουμε πόσο κοντά στην αποτυχία ήταν: ποτέ περισσότερα κιλά (έλεγχος 8/11).
  final ra = last.rirAnswer;
  final rirOk = ra != null && ra >= rirGoal;
  final strict = k == LoadKind.bar || caution;
  final up = lastLoad == null ? null : stepUp(k, lastLoad);

  // Σε πόσες επαναλήψεις ανεβαίνει το βάρος (S6-12), και αν ανεβαίνει αυτόματα.
  final sc = stepCeiling(item.ex, k, lastLoad, up, lo, hi, rirGoal);
  var ceiling = sc.reps;
  var auto = sc.step;
  if (lightOnly.contains(item.ex)) {
    ceiling = hi + plateauExtraReps;
    auto = false;
  }
  // Σώμα με πιο δύσκολη παραλλαγή (S7-03): η παραλλαγή είναι μεγάλο σκαλί, πρώτα λίγες επαναλήψεις παραπάνω.
  if (!hasLoad(k) && item.next != null) ceiling = hi + plateauExtraReps;

  // Κρίνονται μόνο τα σετ που έγιναν με το τελικό φορτίο· όσα έγιναν με άλλο (πριν αλλάξει το βάρος) παίρνουν τις
  // λιγότερες επαναλήψεις των υπολοίπων. Σετ που προστίθενται σήμερα: όσες το τελευταίο σετ της προηγούμενης φοράς.
  final low = _lowAt(last, endLoad);
  final r = [for (final s in done) s.load == endLoad ? s.reps : low];
  List<int> asLast() => [for (var i = 0; i < sets; i++) math.max(1, math.min(i < r.length ? r[i] : r.last, ceiling))];
  List<int> plusOne() => [for (var i = 0; i < sets; i++) math.max(1, math.min(ceiling, i < r.length ? r[i] + 1 : r.last))];

  if (last.pain.isNotEmpty) {
    final where = last.pain.map((p) => painNames[p] ?? p).join(', ');
    return Target(
      load: lastLoad,
      reps: asLast(),
      change: Change.pain,
      reason: 'Την προηγούμενη φορά είχες ενόχληση ($where): τίποτα δεν ανεβαίνει. Αν ξανασυμβεί, δοκίμασε εναλλακτική.',
    );
  }

  // S6-1: με τα σετ και το κάτω όριο που είχε η άσκηση ΕΚΕΙΝΗ τη μέρα (η ίδια άσκηση μπορεί να είναι σε δύο
  // προπονήσεις με άλλα σετ ή εύρος). Το πάνω όριο (πότε ανεβαίνει το βάρος) είναι το σημερινό.
  final complete = done.length >= last.sets;
  final top = complete && low >= ceiling;
  final inRange = complete && low >= last.lo;

  // Με λιγότερη από 2 ρεζέρβα, ποτέ αύξηση (μπάρα χωρίς βραχίονες ασφαλείας, και για την καρδιά σε όλες).
  if (ra != null && ra < 2 && inRange) {
    return Target(
      load: lastLoad,
      reps: asLast(),
      change: Change.hold,
      reason: k == LoadKind.bar
          ? 'Μπάρα χωρίς βραχίονες ασφαλείας: άφησες $ra. Ίδια κιλά, και άφηνε 2 ή περισσότερες.'
          // Έλεγχος 9/11 (V-B-07, AHA 2023): με ρεζέρβα 2 η πίεση ανεβαίνει λιγότερο, όχι «δεν ανεβαίνει».
          : 'Άφησες $ra. ${usesKg(k) ? 'Ίδια κιλά' : 'Ίδιο φορτίο'}, και σταμάτα το σετ όταν σου μένουν 2: η πίεση '
              'ανεβαίνει λιγότερο απ’ ό,τι όταν φτάνεις στην εξάντληση· πόση ένταση σου επιτρέπεται, το λέει ο γιατρός.',
    );
  }

  if (top && rirOk) {
    if (!hasLoad(k)) {
      final next = item.next;
      if (next != null) {
        // S7-03: πρόταση, όχι σιωπηλή αλλαγή. Οι επαναλήψεις μένουν· η παραλλαγή μπαίνει όταν τη διαλέξεις εσύ.
        return Target(
          load: null,
          reps: asLast(),
          change: Change.variant,
          variant: next,
          reason: 'Έφτασες $sets × $ceiling και άφησες όσες ζητά το πρόγραμμα. Η πιο δύσκολη παραλλαγή είναι «${exNamesById[next] ?? next}»: όταν θες να τη '
              'δοκιμάσεις, στην προπόνηση πάτα ⋮ › «Αλλαγή άσκησης». Από εκεί και πέρα μπαίνει αυτή.',
        );
      }
      return Target(
        load: null,
        reps: _same(sets, hi),
        change: Change.max,
        reason: 'Στο ανώτατο: κράτα $sets × $hi με πιο αργό κατέβασμα (3 δευτερόλεπτα). Πες μου να το κάνουμε πιο δύσκολο.',
      );
    }
    if (up == null) {
      return Target(
        load: lastLoad,
        reps: _same(sets, hi),
        change: Change.max,
        reason: 'Είσαι στο μεγαλύτερο ${_l(k, lastLoad)} που βγαίνει με τον εξοπλισμό. Πες μου να το αλλάξουμε.',
      );
    }
    if (!auto) {
      // S6-12 / S7-02: το επόμενο σκαλί δεν βγαίνει με αυτή τη ρεζέρβα όσες επαναλήψεις κι αν κάνεις πρώτα.
      return Target(
        load: lastLoad,
        reps: asLast(),
        change: Change.max,
        reason: lightOnly.contains(item.ex)
            ? 'Έφτασες στις $ceiling και άφησες όσες ζητά το πρόγραμμα. Σε αυτή την άσκηση μένουμε σε ελαφρύ λάστιχο: κράτα τις $ceiling με πιο αργή κίνηση '
                '(3 δευτερόλεπτα στην επιστροφή).'
            : 'Έφτασες στις $ceiling και άφησες όσες ζητά το πρόγραμμα. Το επόμενο σκαλί, ${_l(k, up)}, είναι πολύ μεγάλο για να ανέβεις μονομιάς: κράτα τις '
                '$ceiling με πιο αργή κίνηση (3 δευτερόλεπτα στην επιστροφή) και πες μου να το κάνουμε πιο δύσκολο.',
      );
    }
    return Target(
      load: up,
      reps: _same(sets, lo),
      change: Change.up,
      reason: k == LoadKind.bandAssist
          ? 'Όλα τα σετ στις $ceiling και άφησες όσες ζητά το πρόγραμμα: λιγότερη βοήθεια, ${_l(k, up)}, ξανά από $lo.'
          : 'Όλα τα σετ στις $ceiling και άφησες όσες ζητά το πρόγραμμα: ανέβα σε ${_l(k, up)}, ξανά από $lo.',
    );
  }

  if (top) {
    return Target(
      load: lastLoad,
      reps: asLast(),
      change: Change.hold,
      reason: ra == null
          ? 'Έφτασες στις $ceiling, αλλά δεν ξέρουμε πόσες άφησες: ίδια, και πες μετά το τελευταίο σετ.'
          : 'Έφτασες στις $ceiling, αλλά άφησες ${ra == 4 ? '4+' : ra}, λιγότερες από $rirGoal: ίδια μία φορά ακόμα, να γίνει πιο άνετα.',
    );
  }

  if (inRange && ra != null && ra < rirGoal) {
    return Target(
      load: lastLoad,
      reps: asLast(),
      change: Change.hold,
      reason: ra == 0
          ? 'Την προηγούμενη φορά δεν άφησες καμία (έφτασες στο όριο): ίδιες επαναλήψεις, να βγουν πιο άνετα.'
          : 'Την προηγούμενη φορά άφησες $ra, λιγότερες από $rirGoal: ίδιες επαναλήψεις.',
    );
  }

  if (inRange && ra == null && strict) {
    return Target(
      load: lastLoad,
      reps: asLast(),
      change: Change.hold,
      reason: 'Δεν ξέρουμε πόσες άφησες. Σε αυτή την άσκηση δεν ανεβαίνει τίποτα χωρίς απάντηση: ίδια.',
    );
  }

  if (inRange) {
    final reps = plusOne();
    final b = StringBuffer(hasLoad(k) ? 'Ίδιο βάρος, +1 επανάληψη σε κάθε σετ.' : '+1 επανάληψη σε κάθε σετ.');
    // S6-12: γιατί οι επαναλήψεις περνούν το πάνω όριο του προγράμματος.
    if (reps.any((x) => x > hi)) {
      if (!hasLoad(k)) {
        b.write(' Πριν από την πιο δύσκολη παραλλαγή: ως τις $ceiling επαναλήψεις.');
      } else if (auto && up != null) {
        b.write(' Το επόμενο σκαλί (${_l(k, up)}) είναι μεγάλο: πρώτα ως τις $ceiling επαναλήψεις.');
      } else {
        b.write(' Το επόμενο σκαλί είναι πολύ μεγάλο: εδώ ως τις $ceiling επαναλήψεις.');
      }
    }
    // S7-22: «4+» σημαίνει «τουλάχιστον 4»· αν ήταν πολύ περισσότερες, το ξέρεις μόνο εσύ. Όχι αν το βαρύτερο
    // δοκιμάστηκε ήδη και γύρισες πίσω.
    if (ra == 4 && rirGoal < 4 && !strict && _hintFits(item, k, lastLoad, up, rirGoal) && !usable.any((h) => _endLoad(h.$2) == up)) {
      b.write(_hint);
    }
    return Target(load: lastLoad, reps: reps, change: Change.more, reason: b.toString());
  }

  // Τελείωσες νωρίτερα: όσα σετ έμειναν δεν μετράνε, όπως λέει και το «Τελείωσες νωρίτερα;» (έλεγχος #2, T2-03). Όσα
  // έγιναν μέσα στο εύρος: ίδια. Όσα έμειναν κάτω από το εύρος μετράνε παρακάτω, όπως πριν (δύο φορές → ένα σκαλί κάτω).
  if (!complete && low >= last.lo) {
    return Target(
      load: lastLoad,
      reps: asLast(),
      change: Change.hold,
      reason: 'Την προηγούμενη φορά δεν έγιναν όλα τα σετ: ίδιο βάρος.',
    );
  }

  // Όλα τα σετ έγιναν, αλλά κάποιο έμεινε κάτω από το κάτω όριο εκείνης της μέρας.
  // Λίγο κάτω ΜΕ τη ρεζέρβα που ζητά το πρόγραμμα: σταμάτησες όπως πρέπει (Helms 2016), δεν είναι αποτυχία.
  if (complete && rirOk && low >= last.lo - closeReps) {
    return Target(
      load: lastLoad,
      reps: plusOne(),
      change: Change.more,
      reason: 'Σταμάτησες λίγο πριν από τον στόχο και άφησες όσες ζητά το πρόγραμμα, όπως πρέπει: ${hasLoad(k) ? 'ίδιο βάρος, ' : ''}+1 επανάληψη σε κάθε σετ.',
    );
  }

  // Το βάρος ανέβηκε μέσα στην ίδια προπόνηση (βαθμονόμηση ή «+») και δεν βγήκε: πίσω στο ελαφρύτερο που είχε βγει.
  if (endLoad != null && lastLoad != null && hasLoad(k)) {
    SetLog? ref;
    for (final s in done) {
      final l = s.load;
      if (l != null && l != endLoad && _easier(k, l, endLoad) && s.reps >= last.lo) ref = s;
    }
    final back = ref?.load;
    if (ref != null && back != null) {
      return Target(
        load: k == LoadKind.bandPair ? snap(k, back) : back,
        reps: _same(sets, math.max(math.min(lo, last.lo), math.min(ref.reps, hi))),
        change: Change.down,
        reason: 'Με ${_l(k, endLoad)} δεν βγήκαν οι ${last.lo}: πίσω σε ${_l(k, back)}.',
      );
    }
  }

  // Κάτω από το εύρος δύο φορές στη σειρά με το ίδιο βάρος → ένα σκαλί κάτω. Μόνο από σετ που έγιναν.
  var streak = 0;
  for (final (_, h) in usable) {
    final hl = _endLoad(h);
    final hlow = _lowAt(h, hl);
    final hr = h.rirAnswer;
    final fine = hlow >= h.lo || (hr != null && hr >= rirGoal && hlow >= h.lo - closeReps);
    if (fine || hl != endLoad) break;
    streak++;
  }
  if (streak >= 2 && lastLoad != null && hasLoad(k)) {
    final down = stepDown(k, lastLoad, allowZero: k == LoadKind.plate);
    if (down != null) {
      return Target(
        load: down,
        reps: _same(sets, lo),
        change: Change.down,
        reason: 'Δύο φορές κάτω από ${last.lo} επαναλήψεις: ένα σκαλί πιο ελαφριά, ${_l(k, down)}.',
      );
    }
  }
  final aim = math.min(lo, last.lo);
  return Target(
    load: lastLoad,
    reps: _same(sets, aim),
    change: Change.hold,
    reason: complete
        ? 'Λίγο κάτω από τον στόχο: ίδιο βάρος, στόχος $aim επαναλήψεις.'
        : 'Την προηγούμενη φορά δεν έγιναν όλα τα σετ: ίδιο βάρος, στόχος $aim επαναλήψεις.',
  );
}

/// Πρώτη φορά, μετά το 1ο σετ: πρόταση για το επόμενο σετ. null = μένει ίδιο.
///
/// - Λιγότερη από 2 ρεζέρβα, όσες επαναλήψεις κι αν βγήκαν: ένα σκαλί πιο ελαφριά για τα επόμενα σετ (S6-7). Αλλιώς τα
///   επόμενα σετ θα πήγαιναν ως την εξάντληση, εκεί που η πίεση ανεβαίνει πιο πολύ (MacDougall 1985).
/// - «4+» με τις επαναλήψεις του στόχου: ένα σκαλί πάνω, όπως πριν — εκτός από αλτήρες και λάστιχα σε ασκήσεις του πάνω
///   μέρους ([labelIsLoad]): εκεί ισχύει ο ίδιος κανόνας με την πρόοδο ([stepCeiling]· το 1ο σετ πρέπει ήδη να δείχνει
///   ότι το επόμενο σκαλί βγαίνει, μετρώντας και τη ρεζέρβα που περίσσεψε), γιατί τα σκαλιά τους είναι +15% ως +50%
///   (S6-12, S7-02). Το «4+» λέει μόνο «τουλάχιστον 4»· για το πολύ ελαφρύ υπάρχει το «+» και η συμβουλή στον στόχο (S7-22).
double? calibrate(PlanItem item, double? load, int reps, int rirAnswer) {
  final k = item.kind;
  if (load == null || !hasLoad(k)) return null;
  if (rirAnswer < 2) return stepDown(k, load, allowZero: k == LoadKind.plate);
  if (rirAnswer < 4 || reps < item.lo || lightOnly.contains(item.ex)) return null;
  final up = stepUp(k, load);
  if (up == null) return null;
  if (labelIsLoad(item.ex, k)) {
    final g = math.max(item.rir, 2);
    final c = stepCeiling(item.ex, k, load, up, item.lo, item.hi, g);
    if (!c.step || reps + (rirAnswer - g) < c.reps) return null;
  }
  return up;
}
