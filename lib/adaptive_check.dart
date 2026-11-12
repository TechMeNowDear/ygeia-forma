/// Ο εβδομαδιαίος έλεγχος θερμίδων στην πράξη (σχέδια A1–A4, εγκρίθηκαν 12/11): από τα δεδομένα της εφαρμογής (φαγητό,
/// ζυγίσεις InBody) στην κάρτα της Σήμερα και πίσω στους στόχους. Οι κανόνες είναι στο [adaptive.dart]· εδώ μόνο τι
/// δείχνεται, πότε, και τι αλλάζει όταν απαντάς. Τίποτα δεν αλλάζει μόνο του: πάντα με το δικό σου «Εφάρμοσε».
library;

import 'adaptive.dart';
import 'data.dart' show BodyMeasurement;
import 'food/food_model.dart' show Totals;
import 'food/food_store.dart';
import 'history.dart' show dateKey;
import 'format.dart' show daysBetween;
import 'goals.dart';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Μία ζύγιση ανά μέρα: η πρώτη της μέρας (η πρωινή, όπως λέει η κάρτα «Σήμερα ζύγιση»). [body] είναι ήδη μόνο της
/// InBody (η σειρά της ζυγαριάς), παλιότερη πρώτη.
List<(DateTime, double)> dailyWeights(Iterable<BodyMeasurement> body) {
  final out = <DateTime, double>{};
  for (final b in body) {
    final w = b.weight;
    if (w == null || !w.isFinite) continue;
    out.putIfAbsent(_day(b.time), () => w);
  }
  final list = [for (final e in out.entries) (e.key, e.value)]..sort((a, b) => a.$1.compareTo(b.$1));
  return list;
}

/// Θερμίδες ανά μέρα όπως φαίνονται στη Διατροφή, από [from] ως [to] (και τα δύο μέσα). Μέρες χωρίς καταχώριση
/// δεν μπαίνουν καθόλου.
Map<DateTime, double> dailyIntake(FoodStore food, DateTime from, DateTime to) {
  final out = <DateTime, double>{};
  for (var d = _day(from); !d.isAfter(_day(to)); d = DateTime(d.year, d.month, d.day + 1)) {
    final entries = food.entriesFor(d);
    if (entries.isNotEmpty) out[d] = Totals(entries).kcal;
  }
  return out;
}

/// Τι δείχνει η κάρτα.
enum CheckKind {
  /// Νέος στόχος από τα δεδομένα (A1).
  proposal,

  /// Η εκτίμηση βγήκε, αλλά ο στόχος μένει ίδιος (αλλαγή κάτω από 30 kcal).
  same,

  /// Μέρα ελέγχου χωρίς αρκετά δεδομένα.
  fewData,

  /// Τα νούμερα δεν βγάζουν νόημα (συνήθως γεύματα που δεν γράφτηκαν).
  implausible,

  /// Χάνεις πιο γρήγορα από το ασφαλές (A3).
  fast,
}

class CheckIn {
  const CheckIn(
      {required this.kind, required this.goals, this.status, this.est, this.proposal, this.kgNow, this.fastSlope, this.days = 0, this.weighs = 0});
  final CheckKind kind;
  final Goals goals;
  final AdaptStatus? status;
  final Expenditure? est;
  final AdaptProposal? proposal;

  /// Το βάρος με το οποίο υπολογίστηκε ο ρυθμός (η τελευταία ζύγιση του παραθύρου).
  final double? kgNow;

  /// Για τη γρήγορη απώλεια: kg την εβδομάδα (αρνητικό) στις 14 τελευταίες μέρες.
  final double? fastSlope;

  /// Στο παράθυρο του ελέγχου: μέρες φαγητού που μετρούν (≥ 60% του στόχου) και ζυγίσεις.
  final int days, weighs;

  /// Ο στόχος από τον ρυθμό, πριν από το όριο των ±150 (για το «Πώς βγήκε»).
  int? get wanted {
    final e = est, k = kgNow;
    if (e == null || k == null) return null;
    final delta = switch (goals.aim) {
      GoalAim.lose => -k * goals.rate * kcalPerKg / 7,
      GoalAim.gain => k * goals.rate * kcalPerKg / 7,
      GoalAim.keep => 0.0,
    };
    return ((e.tdee + delta) / 10).round() * 10;
  }

  /// Τα δεδομένα θέλουν στόχο κάτω από το όριο ασφαλείας· ο στόχος δεν φτάνει ποτέ εκεί, όσοι έλεγχοι κι αν γίνουν.
  /// Το «Πώς βγήκε» γράφει τότε το όριο, όχι «τα δεδομένα λένε 1.210» (Συμβούλιο 2, μ1): ένας αριθμός κάτω από το όριο
  /// δεν πρέπει να διαβαστεί ως στόχος που έρχεται.
  bool get wantsBelowFloor {
    final w = wanted;
    return w != null && w < (goals.male ? kcalFloorMale : kcalFloorFemale);
  }
}

/// Η πρώτη μέρα ελέγχου: 21 μέρες μετά την αρχή (ίδια μέρα της εβδομάδας).
DateTime firstCheckDay(Goals g) {
  final s = DateTime.parse(g.since);
  return DateTime(s.year, s.month, s.day + adaptWindowDays);
}

/// Η επόμενη μέρα ελέγχου (σήμερα, αν εκκρεμεί).
DateTime nextCheckDay(Goals g, DateTime today) {
  final t = _day(today);
  if (checkInDue(goals: g, today: t, lastCheckIn: g.checkIn)) return t;
  final first = firstCheckDay(g);
  if (t.isBefore(first)) return first;
  var d = t;
  while (d.weekday != first.weekday || g.checkIn == dateKey(d)) {
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return d;
}

/// Τι εκκρεμεί σήμερα (null: τίποτα). Ο εβδομαδιαίος έλεγχος έχει προτεραιότητα· η γρήγορη απώλεια βγαίνει τις άλλες
/// μέρες, μία φορά την εβδομάδα, και όχι τη μέρα που απάντησες στον έλεγχο.
CheckIn? pendingCheckIn({
  required Goals? goals,
  required DateTime today,
  required List<(DateTime, double)> weights,
  required Map<DateTime, double> Function(DateTime from, DateTime to) intake,
}) {
  final g = goals;
  if (g == null) return null;
  final t = _day(today);
  if (checkInDue(goals: g, today: t, lastCheckIn: g.checkIn)) {
    final to = DateTime(t.year, t.month, t.day - 1);
    final from = DateTime(to.year, to.month, to.day - (adaptWindowDays - 1));
    final eaten = intake(from, to);
    final days = eaten.values.where((v) => v >= adaptFullDayShare * g.kcal).length;
    final weighs = weights.where((w) => !w.$1.isBefore(from) && !w.$1.isAfter(to)).length;
    final r = estimateExpenditure(
      intake: eaten,
      weights: weights,
      today: t,
      formulaTdee: g.calc.tdee,
      goalKcal: g.kcal,
    );
    switch (r.status) {
      case AdaptStatus.ok:
        final inWindow = [for (final w in weights) if (!w.$1.isBefore(from) && !w.$1.isAfter(to)) w];
        final kg = inWindow.last.$2;
        final p = proposeTarget(goals: g, est: r.est!, kgNow: kg);
        return CheckIn(
            kind: p.same ? CheckKind.same : CheckKind.proposal,
            goals: g,
            status: r.status,
            est: r.est,
            proposal: p,
            kgNow: kg,
            days: days,
            weighs: weighs);
      case AdaptStatus.implausible:
        return CheckIn(kind: CheckKind.implausible, goals: g, status: r.status, est: r.est, days: days, weighs: weighs);
      case AdaptStatus.tooEarly:
      case AdaptStatus.fewIntakeDays:
      case AdaptStatus.fewWeighIns:
        return CheckIn(kind: CheckKind.fewData, goals: g, status: r.status, days: days, weighs: weighs);
    }
  }
  if (g.checkIn == dateKey(t)) return null;
  final fa = g.fastAt == null ? null : DateTime.tryParse(g.fastAt!);
  if (fa != null && daysBetween(fa, t) < 7) return null;
  final f = fastLossCheck(goals: g, weights: weights, today: t);
  if (f == null) return null;
  // Οι ίδιες ζυγίσεις που έκριναν την ειδοποίηση (χωρίς την πρώτη εβδομάδα· Συμβούλιο 2, Σ1): ό,τι γράφει η κάρτα
  // («−1,2 kg την εβδομάδα») είναι ακριβώς ο αριθμός που συγκρίθηκε με το 1%.
  final ws = fastLossWeights(goals: g, weights: weights, today: t);
  final slope = weightSlope(ws);
  return CheckIn(kind: CheckKind.fast, goals: g, proposal: f, kgNow: ws.last.$2, fastSlope: slope == null ? null : slope * 7);
}

/// «Εφάρμοσε»: ο νέος στόχος ισχύει από τώρα. Αντικαθιστά και τον δικό σου αριθμό, αν είχες γράψει (το ζήτησες εσύ).
Goals applyCheckIn(CheckIn c, DateTime today) {
  final day = dateKey(today);
  final p = c.proposal!;
  if (c.kind == CheckKind.fast) {
    return c.goals.copyWith(kcalAdapt: p.target, fastAt: day, clearKcal: true);
  }
  return c.goals.copyWith(
    kcalAdapt: p.target,
    tdeeEst: c.est!.tdee,
    checkIn: day,
    clearKcal: true,
    addLog: AdaptLog(day: day, tdee: c.est!.tdee, before: p.current, after: p.target, applied: true),
  );
}

/// «Όχι τώρα» / «Εντάξει»: ο στόχος μένει ίδιος ως τον επόμενο έλεγχο· η εκτίμηση (αν βγήκε) κρατιέται για τη σελίδα «Στόχοι».
Goals dismissCheckIn(CheckIn c, DateTime today) {
  final day = dateKey(today);
  if (c.kind == CheckKind.fast) return c.goals.copyWith(fastAt: day);
  final p = c.proposal;
  final e = c.est;
  if (p == null || e == null) return c.goals.copyWith(checkIn: day);
  return c.goals.copyWith(
    tdeeEst: e.tdee,
    checkIn: day,
    addLog: AdaptLog(day: day, tdee: e.tdee, before: p.current, after: p.current, applied: false),
  );
}

/// Πριν από τον πρώτο έλεγχο (A4): πόσα δεδομένα μαζεύτηκαν ως χθες (από την αρχή, το πολύ 21 μέρες πίσω).
({int intakeDays, int weighIns, DateTime first}) readiness({
  required Goals goals,
  required DateTime today,
  required List<(DateTime, double)> weights,
  required Map<DateTime, double> Function(DateTime from, DateTime to) intake,
}) {
  final start = DateTime.parse(goals.since);
  final to = DateTime(today.year, today.month, today.day - 1);
  final windowFrom = DateTime(to.year, to.month, to.day - (adaptWindowDays - 1));
  final since = start.isAfter(windowFrom) ? start : windowFrom;
  final full = adaptFullDayShare * goals.kcal;
  final days = to.isBefore(since) ? 0 : intake(since, to).values.where((v) => v >= full).length;
  final ws = weights.where((w) => !w.$1.isBefore(since) && !w.$1.isAfter(to)).length;
  return (intakeDays: days, weighIns: ws, first: firstCheckDay(goals));
}
