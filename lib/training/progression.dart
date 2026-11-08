/// Ο «εγκέφαλος» της προόδου: από την προηγούμενη φορά, τι κάνεις σήμερα.
///
/// Διπλή πρόοδος με ρεζέρβα (RIR): πρώτα ανεβαίνουν οι επαναλήψεις ως το πάνω όριο του εύρους, μετά το βάρος
/// (το μικρότερο σκαλί που βγαίνει με τον εξοπλισμό) και οι επαναλήψεις ξαναπάνε στο κάτω όριο.
/// Η πρόταση φαίνεται με τον λόγο της· η απόφαση μένει στον χρήστη.
library;

import 'dart:math' as math;

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

List<int> _same(int sets, int r) => List.filled(sets, r);

String _l(LoadKind k, double? v) => loadLabel(k, v);

/// [history]: οι προηγούμενες φορές της ίδιας άσκησης, νεότερη πρώτη, με την ημερομηνία τους.
/// [caution]: άσκηση με προσοχή στη βιβλιοθήκη (ώμοι, μέση): χωρίς απάντηση για ρεζέρβα δεν ανεβαίνει τίποτα.
Target nextTarget(PlanItem item, List<(DateTime, ExLog)> history, DateTime today, {bool caution = false}) {
  final k = item.kind;
  final sets = item.sets, lo = item.lo, hi = item.hi;
  final usable = [for (final h in history) if (!h.$2.skipped && h.$2.done.isNotEmpty) h];

  if (usable.isEmpty) {
    final start = hasLoad(k) ? (item.load != null ? snap(k, item.load!) : defaultStart(k)) : null;
    return Target(
      load: start,
      reps: _same(sets, lo),
      change: Change.first,
      reason: item.load != null || !hasLoad(k)
          ? 'Πρώτη φορά. Μετά το 1ο σετ θα σε ρωτήσει πώς πήγε, για να βρεθεί το σωστό βάρος.'
          : 'Πρώτη φορά: ελαφριά αρχή. Μετά το 1ο σετ θα σε ρωτήσει πώς πήγε και θα προτείνει βάρος.',
    );
  }

  final (lastDay, last) = usable.first;
  var lastLoad = last.workLoad ?? (hasLoad(k) ? (item.load ?? defaultStart(k)) : null);
  // Ανοίγματα με λάστιχο, από πριν το «ανά πλευρά» (π.χ. 20): στο πλησιέστερο που βγαίνει (ελάχιστο 30/πλευρά).
  if (k == LoadKind.bandPair && lastLoad != null) lastLoad = snap(k, lastLoad);
  final done = last.done;
  final gap = DateTime(today.year, today.month, today.day).difference(DateTime(lastDay.year, lastDay.month, lastDay.day)).inDays;

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

  List<int> plusOne(int cap) => [
        for (var i = 0; i < sets; i++) math.max(lo, math.min(cap, (i < done.length ? done[i].reps : lo) + 1)),
      ];
  List<int> asLast() => [for (var i = 0; i < sets; i++) math.max(lo, i < done.length ? math.min(done[i].reps, hi) : lo)];

  if (last.pain.isNotEmpty) {
    final where = last.pain.map((p) => painNames[p] ?? p).join(', ');
    return Target(
      load: lastLoad,
      reps: asLast(),
      change: Change.pain,
      reason: 'Την προηγούμενη φορά είχες ενόχληση ($where): τίποτα δεν ανεβαίνει. Αν ξανασυμβεί, δοκίμασε εναλλακτική.',
    );
  }

  final complete = done.length >= sets;
  // Χωρίς απάντηση δεν ξέρουμε πόσο κοντά στην αποτυχία ήταν: ποτέ περισσότερα κιλά (έλεγχος 8/11).
  final ra = last.rirAnswer;
  // Τουλάχιστον 2 ρεζέρβα σε όλες τις ασκήσεις, ως να πει άλλα ο καρδιολόγος: η πίεση ανεβαίνει απότομα
  // όσο πλησιάζεις την αποτυχία (MacDougall 1985· έλεγχος #2). Το πρόγραμμα μπορεί να ζητά περισσότερη.
  final rirGoal = math.max(item.rir, 2);
  final rirOk = ra != null && ra >= rirGoal;
  final strict = k == LoadKind.bar || caution;

  // Kettlebell: όταν το επόμενο είναι πάνω από 20% βαρύτερο, πρώτα 3 επαναλήψεις παραπάνω από το εύρος.
  var ceiling = hi;
  final up = lastLoad == null ? null : stepUp(k, lastLoad);
  if (k == LoadKind.kb && up != null && lastLoad != null && lastLoad > 0 && up / lastLoad > 1.2) ceiling = hi + 3;

  final top = complete && done.every((s) => s.reps >= ceiling);
  final inRange = complete && done.every((s) => s.reps >= lo);

  // Με λιγότερη από 2 ρεζέρβα, ποτέ αύξηση (μπάρα χωρίς βραχίονες ασφαλείας, και για την καρδιά σε όλες).
  if (ra != null && ra < 2 && inRange) {
    return Target(
      load: lastLoad,
      reps: asLast(),
      change: Change.hold,
      reason: k == LoadKind.bar
          ? 'Μπάρα χωρίς βραχίονες ασφαλείας: έμεινες με $ra ρεζέρβα. Ίδια κιλά, κράτα 2 ή περισσότερες.'
          : 'Έμεινες με $ra ρεζέρβα. ${usesKg(k) ? 'Ίδια κιλά' : 'Ίδιο φορτίο'}, και σταμάτα το σετ όταν σου μένουν 2: έτσι η πίεση '
              'δεν ανεβαίνει απότομα.',
    );
  }

  if (top && rirOk) {
    if (!hasLoad(k)) {
      if (item.next != null) {
        return Target(
          load: null,
          reps: _same(sets, lo),
          change: Change.variant,
          variant: item.next,
          reason: 'Έφτασες $sets × $hi με ρεζέρβα: ώρα για την πιο δύσκολη παραλλαγή.',
        );
      }
      return Target(
        load: null,
        reps: _same(sets, hi),
        change: Change.max,
        reason: 'Στο ανώτατο: κράτα $sets × $hi με πιο αργό κατέβασμα (3″). Πες μου να το κάνουμε πιο δύσκολο.',
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
    return Target(
      load: up,
      reps: _same(sets, lo),
      change: Change.up,
      reason: k == LoadKind.bandAssist
          ? 'Όλα τα σετ στις $ceiling με ρεζέρβα: λιγότερη βοήθεια, ${_l(k, up)}, ξανά από $lo.'
          : 'Όλα τα σετ στις $ceiling με ρεζέρβα: ανέβα σε ${_l(k, up)}, ξανά από $lo.',
    );
  }

  if (top) {
    return Target(
      load: lastLoad,
      reps: asLast(),
      change: Change.hold,
      reason: ra == null
          ? 'Έφτασες στις $ceiling, αλλά δεν ξέρουμε πόση ρεζέρβα είχες: ίδια, και πες μετά το τελευταίο σετ.'
          : 'Έφτασες στις $ceiling, αλλά με ${ra == 4 ? '4+' : ra} ρεζέρβα: ίδια μία φορά ακόμα, να γίνει πιο άνετα.',
    );
  }

  if (inRange && ra != null && ra < rirGoal) {
    return Target(
      load: lastLoad,
      reps: asLast(),
      change: Change.hold,
      reason: ra == 0
          ? 'Την προηγούμενη φορά έφτασες στο όριο (0 ρεζέρβα): ίδιες επαναλήψεις, να βγουν πιο άνετα.'
          : 'Την προηγούμενη φορά έμεινες με $ra ρεζέρβα, λιγότερη από $rirGoal: ίδιες επαναλήψεις.',
    );
  }

  if (inRange && ra == null && strict) {
    return Target(
      load: lastLoad,
      reps: asLast(),
      change: Change.hold,
      reason: 'Δεν ξέρουμε πόση ρεζέρβα είχες. Σε αυτή την άσκηση δεν ανεβαίνει τίποτα χωρίς απάντηση: ίδια.',
    );
  }

  if (inRange) {
    return Target(
      load: lastLoad,
      reps: plusOne(ceiling),
      change: Change.more,
      reason: hasLoad(k) ? 'Ίδιο βάρος, +1 επανάληψη σε κάθε σετ.' : '+1 επανάληψη σε κάθε σετ.',
    );
  }

  // Κάτω από το εύρος: δύο φορές στη σειρά με το ίδιο βάρος → ένα σκαλί κάτω. Μόνο από σετ που έγιναν:
  // όσα έμειναν (τελείωσες νωρίτερα) δεν μετράνε, όπως λέει και το «Τελείωσες νωρίτερα;» (έλεγχος #2, T2-03).
  var streak = 0;
  for (final (_, h) in usable) {
    final below = h.done.any((s) => s.reps < lo);
    if (!below || h.workLoad != lastLoad) break;
    streak++;
  }
  if (streak >= 2 && lastLoad != null && hasLoad(k)) {
    final down = stepDown(k, lastLoad, allowZero: k == LoadKind.plate);
    if (down != null) {
      return Target(
        load: down,
        reps: _same(sets, lo),
        change: Change.down,
        reason: 'Δύο φορές κάτω από $lo επαναλήψεις: ένα σκαλί πιο ελαφριά, ${_l(k, down)}.',
      );
    }
  }
  return Target(
    load: lastLoad,
    reps: _same(sets, lo),
    change: Change.hold,
    reason: complete ? 'Λίγο κάτω από τον στόχο: ίδιο βάρος, στόχος $lo επαναλήψεις.' : 'Την προηγούμενη φορά δεν έγιναν όλα τα σετ: ίδιο βάρος.',
  );
}

/// Πρώτη φορά, μετά το 1ο σετ: πρόταση για το επόμενο σετ. null = μένει ίδιο.
double? calibrate(PlanItem item, double? load, int reps, int rirAnswer) {
  final k = item.kind;
  if (load == null || !hasLoad(k)) return null;
  if (rirAnswer >= 4 && reps >= item.lo) return stepUp(k, load);
  if (rirAnswer == 0 && reps < item.lo) return stepDown(k, load, allowZero: k == LoadKind.plate);
  return null;
}
