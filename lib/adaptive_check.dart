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
import 'weight_guard.dart';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Μία ζύγιση ανά μέρα, χωρισμένες σε όσες μετρούν ([used]) και όσες δεν μπορεί να είναι δικές σου ([foreign]: έλεγχος
/// 13/11, S11-2, κανόνας στο weight_guard.dart). Και οι δύο παλιότερη πρώτη. [body] είναι ήδη μόνο της InBody.
/// - Μετρά η πρώτη ζύγιση της μέρας (η πρωινή, όπως λέει η κάρτα «Σήμερα ζύγιση»).
/// - Κάθε μέρα κρίνεται με τις πρώτες ζυγίσεις των άλλων ημερών ως [weightGuardDays] μέρες πριν ή μετά. Αν η πρώτη της
///   μοιάζει ξένη (π.χ. ζυγίστηκε πρώτα το παιδί) και υπάρχει επόμενη της ίδιας μέρας που δεν μοιάζει, μετρά εκείνη.
///   Αν όλες μοιάζουν ξένες, η μέρα πάει στο [foreign] με την πρώτη της ζύγιση. Τίποτα δεν σβήνεται: απλώς δεν μετρά.
({List<(DateTime, double)> used, List<(DateTime, double)> foreign}) guardedWeights(Iterable<BodyMeasurement> body) {
  final byDay = <DateTime, List<double>>{};
  for (final b in body) {
    final w = b.weight;
    if (w == null || !w.isFinite) continue;
    byDay.putIfAbsent(_day(b.time), () => <double>[]).add(w);
  }
  final days = byDay.keys.toList()..sort();
  final used = <(DateTime, double)>[];
  final foreign = <(DateTime, double)>[];
  for (var i = 0; i < days.length; i++) {
    final d = days[i];
    final others = <double>[];
    for (var j = i - 1; j >= 0 && daysBetween(days[j], d) <= weightGuardDays; j--) {
      others.add(byDay[days[j]]!.first);
    }
    for (var j = i + 1; j < days.length && daysBetween(d, days[j]) <= weightGuardDays; j++) {
      others.add(byDay[days[j]]!.first);
    }
    final candidates = byDay[d]!;
    double? pick;
    for (final w in candidates) {
      if (!weightLooksForeign(w, others)) {
        pick = w;
        break;
      }
    }
    if (pick == null) {
      foreign.add((d, candidates.first));
    } else {
      used.add((d, pick));
    }
  }
  return (used: used, foreign: foreign);
}

/// Μία ζύγιση ανά μέρα, μόνο όσες μετρούν ([guardedWeights]), παλιότερη πρώτη.
List<(DateTime, double)> dailyWeights(Iterable<BodyMeasurement> body) => guardedWeights(body).used;

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

  /// Μέρα ελέγχου πριν μαζευτούν 3 εβδομάδες μετά την πρώτη (Συμβούλιο 2, Α2): η πρώτη εβδομάδα δεν μετρά, γιατί τότε
  /// φεύγουν κυρίως νερά. Η κάρτα το εξηγεί· η πρώτη εκτίμηση βγαίνει την επόμενη μέρα ελέγχου.
  gathering,

  /// Τα νούμερα δεν βγάζουν νόημα (συνήθως γεύματα που δεν γράφτηκαν).
  implausible,

  /// Χάνεις πάνω από 1% του βάρους την εβδομάδα (A3). Με [CheckIn.proposal]: πρόταση +150. Χωρίς: το ημερολόγιο δείχνει
  /// ότι τρως πολύ κάτω από τον στόχο (ή δεν δείχνει τίποτα), άρα δεν φταίει ο στόχος (έλεγχος 13/11, S1-2).
  fast,

  /// Μέρα ελέγχου με κενό καταγραφής φαγητού (έλεγχος 13/11, S1-1): καμία εκτίμηση, ο στόχος μένει.
  gap,

  /// Μια ζύγιση που δεν μπορεί να είναι δική σου δεν μέτρησε (S11-2). Μόνο ενημέρωση, «Εντάξει».
  foreign,

  /// Μέρα ελέγχου, αλλά οι ζυγίσεις δεν διαβάστηκαν τώρα (S11-8). Χωρίς κουμπί: ο έλεγχος δεν «ξοδεύεται».
  unread,
}

class CheckIn {
  const CheckIn(
      {required this.kind,
      required this.goals,
      this.status,
      this.est,
      this.proposal,
      this.kgNow,
      this.fastSlope,
      this.fastDays,
      this.days = 0,
      this.weighs = 0,
      this.tooFast = false,
      this.heldDays,
      this.gap,
      this.absurd = const [],
      this.foreign = const [],
      this.fastIntake,
      this.fastIntakeDays = 0});
  final CheckKind kind;
  final Goals goals;
  final AdaptStatus? status;
  final Expenditure? est;
  final AdaptProposal? proposal;

  /// Το βάρος με το οποίο υπολογίστηκε ο ρυθμός (η τελευταία ζύγιση του παραθύρου).
  final double? kgNow;

  /// Για τη γρήγορη απώλεια: kg την εβδομάδα (αρνητικό) στις μέρες που κρίθηκαν ([fastDays]).
  final double? fastSlope;

  /// Για τη γρήγορη απώλεια: πόσες μέρες πίσω φτάνει το παράθυρο που κρίθηκε (το πολύ 21· λιγότερες όσο η πρώτη
  /// εβδομάδα των στόχων το κόβει). Η κάρτα γράφει ακριβώς αυτό ([fastPeriodText]).
  final int? fastDays;

  /// Στις 3 τελευταίες εβδομάδες (χωρίς την πρώτη εβδομάδα των στόχων): μέρες φαγητού που μετρούν (≥ 60% του στόχου)
  /// και ζυγίσεις. Για την κάρτα «λίγα δεδομένα».
  final int days, weighs;

  /// Εβδομαδιαίος έλεγχος (S1-3): χάνεις πάνω από 1% την εβδομάδα και τα δεδομένα δεν ζητούν αύξηση. Ο στόχος ΔΕΝ
  /// κατεβαίνει· η κάρτα λέει γιατί.
  final bool tooFast;

  /// Εβδομαδιαίος έλεγχος (S1-4): ο στόχος άλλαξε πριν από τόσες μέρες (λιγότερες από [adaptMinChangeDays]), γι' αυτό
  /// δεν προτείνεται νέα αλλαγή τώρα. null: δεν ισχύει.
  final int? heldDays;

  /// Το κενό καταγραφής φαγητού ([CheckKind.gap]).
  final FoodGap? gap;

  /// Μέρες του παραθύρου με αδύνατα πολλές θερμίδες, που δεν μπήκαν στον μέσο όρο (S11-3), με τις θερμίδες τους.
  final List<(DateTime, double)> absurd;

  /// Ζυγίσεις των 3 τελευταίων εβδομάδων που δεν μέτρησαν γιατί δεν μπορεί να είναι δικές σου (S11-2) και που δεν τις
  /// έχεις δει ακόμα σε κάρτα.
  final List<(DateTime, double)> foreign;

  /// Γρήγορη απώλεια: ο μέσος όρος όσων γράφτηκαν στο ημερολόγιο τις μέρες που κρίθηκαν (kcal τη μέρα), όταν υπάρχουν
  /// τουλάχιστον [adaptFastMinIntakeDays] γραμμένες μέρες· αλλιώς null. [fastIntakeDays]: πόσες μέρες γράφτηκαν.
  final double? fastIntake;
  final int fastIntakeDays;

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

/// Η πρώτη μέρα που βγαίνει κάρτα ελέγχου: 21 μέρες μετά την αρχή (ίδια μέρα της εβδομάδας). Εκείνη τη μέρα η κάρτα
/// λέει ότι μαζεύει ακόμα δεδομένα ([CheckKind.gathering])· η πρώτη εκτίμηση βγαίνει στο [firstEstimateDay].
DateTime firstCheckDay(Goals g) {
  final s = DateTime.parse(g.since);
  return DateTime(s.year, s.month, s.day + adaptWindowDays);
}

/// Η πρώτη μέρα ελέγχου με εκτίμηση: 28 μέρες μετά την αρχή, δηλαδή 21 μέρες που μετρούν μετά την πρώτη εβδομάδα
/// (Συμβούλιο 2, Α2). Ίδια μέρα της εβδομάδας με την αρχή. Αυτή δείχνει η σελίδα «Στόχοι» ως «Πρώτος έλεγχος».
DateTime firstEstimateDay(Goals g) {
  final s = DateTime.parse(g.since);
  return DateTime(s.year, s.month, s.day + adaptSkipDays + adaptWindowDays);
}

/// Πώς γράφει η κάρτα της γρήγορης απώλειας την περίοδο που κρίθηκε (εγκρίθηκε 12/11): «Τις τελευταίες 11 μέρες» όσο η
/// πρώτη εβδομάδα κόβει το παράθυρο, «Τις 2 / 3 τελευταίες εβδομάδες» όταν είναι ακριβώς 14 ή 21 μέρες.
String fastPeriodText(int? days) => switch (days) {
      null => 'Τις τελευταίες μέρες',
      14 => 'Τις 2 τελευταίες εβδομάδες',
      21 => 'Τις 3 τελευταίες εβδομάδες',
      _ => 'Τις τελευταίες $days μέρες',
    };

/// Η επόμενη μέρα ελέγχου (σήμερα, αν εκκρεμεί). Ίδιος κανόνας με το [checkInDue] (έλεγχος 13/11, S1-4): μια μέρα ελέγχου
/// λιγότερο από [adaptMinChangeDays] μέρες μετά την τελευταία απάντηση δεν μετρά.
DateTime nextCheckDay(Goals g, DateTime today) {
  final t = _day(today);
  if (checkInDue(goals: g, today: t, lastCheckIn: g.checkIn)) return t;
  final first = firstCheckDay(g);
  if (t.isBefore(first)) return first;
  final ci = g.checkIn;
  final last = ci == null ? null : DateTime.tryParse(ci);
  var d = t;
  while (d.weekday != first.weekday || (last != null && daysBetween(last, d) < adaptMinChangeDays)) {
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return d;
}

/// Τόσες γραμμένες μέρες φαγητού (τουλάχιστον) χρειάζεται η «γρήγορη απώλεια» για να πει πόσο τρως (S1-2).
const adaptFastMinIntakeDays = 4;

/// Η τελευταία μέρα που άλλαξε ο στόχος από κάρτα (εβδομαδιαίος έλεγχος ή γρήγορη απώλεια με «Εφάρμοσε»). null: ποτέ.
DateTime? lastChangeDay(Goals g) {
  String? last;
  for (final l in g.log) {
    if (l.applied && (last == null || l.day.compareTo(last) > 0)) last = l.day;
  }
  return last == null ? null : DateTime.tryParse(last);
}

/// Τι εκκρεμεί σήμερα (null: τίποτα). Ο εβδομαδιαίος έλεγχος έχει προτεραιότητα· η γρήγορη απώλεια βγαίνει τις άλλες
/// μέρες, μία φορά την εβδομάδα, και όχι τη μέρα που απάντησες στον έλεγχο.
///
/// Έλεγχος 13/11. [weights]: οι ζυγίσεις που μετρούν ([guardedWeights] → used). [foreign]: όσες εξαιρέθηκαν ως ξένες, για
/// να τις γράψει η κάρτα (S11-2)· όσες δεν έχεις δει βγαίνουν μέσα στην κάρτα της μέρας, αλλιώς σε δική τους
/// ([CheckKind.foreign]). [weightsRead]: false όταν οι ζυγίσεις δεν διαβάστηκαν τώρα (S11-8): τη μέρα ελέγχου η κάρτα το
/// λέει χωρίς κουμπί, τις άλλες μέρες δεν βγαίνει τίποτα.
CheckIn? pendingCheckIn({
  required Goals? goals,
  required DateTime today,
  required List<(DateTime, double)> weights,
  required Map<DateTime, double> Function(DateTime from, DateTime to) intake,
  List<(DateTime, double)> foreign = const [],
  bool weightsRead = true,
}) {
  final g = goals;
  if (g == null) return null;
  final t = _day(today);
  // Ξένες ζυγίσεις των 3 τελευταίων εβδομάδων που δεν έχουν φανεί ακόμα σε κάρτα.
  final seen = g.foreignSeen;
  final recentFrom = DateTime(t.year, t.month, t.day - adaptFastWindowDays);
  final news = [
    for (final x in foreign)
      if (!x.$1.isBefore(recentFrom) && !x.$1.isAfter(t) && (seen == null || dateKey(x.$1).compareTo(seen) > 0)) x,
  ];
  // Μέρα με αδύνατα πολλές θερμίδες δεν μετρά πουθενά (S11-3).
  final over = absurdDayKcal(g.calc.tdee);
  if (checkInDue(goals: g, today: t, lastCheckIn: g.checkIn)) {
    if (!weightsRead) return CheckIn(kind: CheckKind.unread, goals: g);
    final to = DateTime(t.year, t.month, t.day - 1);
    final since = DateTime.parse(g.since);
    // Η πρώτη εβδομάδα των στόχων δεν μετρά (Συμβούλιο 2, Α2).
    final firstCounted = DateTime(since.year, since.month, since.day + adaptSkipDays);
    DateTime notBeforeFirst(DateTime d) => d.isBefore(firstCounted) ? firstCounted : d;
    // Το φαγητό διαβάζεται για το μεγαλύτερο παράθυρο (ως 42 μέρες, Α1)· οι μετρητές της κάρτας «λίγα δεδομένα» αφορούν
    // τις 3 τελευταίες εβδομάδες, όπως γράφει το κείμενό της.
    final wideFrom = notBeforeFirst(DateTime(to.year, to.month, to.day - (adaptMaxWindowDays - 1)));
    final from = notBeforeFirst(DateTime(to.year, to.month, to.day - (adaptWindowDays - 1)));
    final eaten = intake(wideFrom, to);
    final days =
        eaten.entries.where((e) => !e.key.isBefore(from) && e.value >= adaptFullDayShare * g.kcal && e.value <= over).length;
    final weighs = weights.where((w) => !w.$1.isBefore(from) && !w.$1.isAfter(to)).length;
    final r = estimateExpenditure(
      intake: eaten,
      weights: weights,
      today: t,
      formulaTdee: g.calc.tdee,
      goalKcal: g.kcal,
      since: since,
    );
    // Οι μέρες με αδύνατα πολλές θερμίδες του παραθύρου που κρίθηκε (αλλιώς των 3 τελευταίων εβδομάδων), για την κάρτα.
    final absurdFrom = r.est?.from ?? from;
    final absurd = [
      for (final e in eaten.entries)
        if (!e.key.isBefore(absurdFrom) && e.value > over) (e.key, e.value),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    switch (r.status) {
      case AdaptStatus.ok:
        final e = r.est!;
        // Το βάρος για τον ρυθμό: η τελευταία ζύγιση του παραθύρου που έδωσε την εκτίμηση.
        final inWindow = [for (final w in weights) if (!w.$1.isBefore(e.from) && !w.$1.isAfter(e.to)) w];
        final kg = inWindow.last.$2;
        var p = proposeTarget(goals: g, est: e, kgNow: kg);
        // S1-3: όσο χάνεις πάνω από 1% την εβδομάδα (στο παράθυρο της εκτίμησης ή στις τελευταίες μέρες), ο στόχος δεν
        // κατεβαίνει. Πριν, η κάρτα της Δευτέρας τον κατέβαζε 150 και η «γρήγορη απώλεια» της Παρασκευής τον ανέβαζε 150.
        final losingFast = g.aim == GoalAim.lose &&
            (e.slopeKgWeek < -adaptFastLossPct * kg || fastLossSlope(goals: g, weights: weights, today: t) != null);
        final tooFast = losingFast && p.change <= 0;
        // S1-4: όχι δεύτερη αλλαγή λιγότερο από 4 μέρες μετά την προηγούμενη (π.χ. «γρήγορη απώλεια» την Παρασκευή).
        final changed = lastChangeDay(g);
        final sinceChange = changed == null ? null : daysBetween(changed, t);
        final held = sinceChange != null && sinceChange < adaptMinChangeDays && p.change != 0;
        if ((tooFast && p.change < 0) || held) {
          p = AdaptProposal(current: p.current, target: p.current, est: e, fastLoss: false, floored: false);
        }
        return CheckIn(
            kind: p.same ? CheckKind.same : CheckKind.proposal,
            goals: g,
            status: r.status,
            est: e,
            proposal: p,
            kgNow: kg,
            days: days,
            weighs: weighs,
            tooFast: tooFast,
            heldDays: held ? sinceChange : null,
            absurd: absurd,
            foreign: news);
      case AdaptStatus.implausible:
        return CheckIn(
            kind: CheckKind.implausible,
            goals: g,
            status: r.status,
            est: r.est,
            days: days,
            weighs: weighs,
            absurd: absurd,
            foreign: news);
      case AdaptStatus.tooEarly:
        return CheckIn(kind: CheckKind.gathering, goals: g, status: r.status, days: days, weighs: weighs, foreign: news);
      case AdaptStatus.gapOpen:
      case AdaptStatus.afterGap:
        return CheckIn(
            kind: CheckKind.gap,
            goals: g,
            status: r.status,
            days: days,
            weighs: weighs,
            gap: foodGap(intake: eaten, today: t, formulaTdee: g.calc.tdee, goalKcal: g.kcal, since: since),
            absurd: absurd,
            foreign: news);
      case AdaptStatus.fewIntakeDays:
      case AdaptStatus.fewWeighIns:
        return CheckIn(
            kind: CheckKind.fewData, goals: g, status: r.status, days: days, weighs: weighs, absurd: absurd, foreign: news);
    }
  }
  if (g.checkIn == dateKey(t)) return null;
  if (!weightsRead) return null;
  // Χωρίς γρήγορη απώλεια: μόνο η ενημέρωση για ξένη ζύγιση, αν υπάρχει καινούργια.
  final CheckIn? onlyForeign = news.isEmpty ? null : CheckIn(kind: CheckKind.foreign, goals: g, foreign: news);
  final fa = g.fastAt == null ? null : DateTime.tryParse(g.fastAt!);
  if (fa != null && daysBetween(fa, t) < 7) return onlyForeign;
  // S1-4: όχι πρόταση λιγότερο από 4 μέρες μετά από αλλαγή του στόχου.
  final lastChange = lastChangeDay(g);
  if (lastChange != null && daysBetween(lastChange, t) < adaptMinChangeDays) return onlyForeign;
  // Οι ίδιες ζυγίσεις που κρίνουν την ειδοποίηση (χωρίς την πρώτη εβδομάδα· Συμβούλιο 2, Σ1): ό,τι γράφει η κάρτα
  // («−1,16 kg την εβδομάδα») είναι ακριβώς ο αριθμός που συγκρίθηκε με το 1%.
  final f = fastLossSlope(goals: g, weights: weights, today: t);
  final window = fastLossWindow(goals: g, today: t);
  if (f == null || window == null) return onlyForeign;
  // S1-2: πόσο γράφτηκε στο ημερολόγιο τις ίδιες μέρες (ως χθες· η σημερινή μέρα δεν έχει τελειώσει). Όλες οι μέρες με
  // καταχώριση, όχι μόνο όσες περνούν το 60%: εδώ ψάχνουμε ακριβώς το «τρως πολύ λίγο».
  final yesterday = DateTime(t.year, t.month, t.day - 1);
  final diary = yesterday.isBefore(window.$1) ? const <DateTime, double>{} : intake(window.$1, yesterday);
  final logged = [
    for (final v in diary.values)
      if (v <= over) v,
  ];
  final known = logged.length >= adaptFastMinIntakeDays;
  final mean = logged.isEmpty ? null : logged.reduce((a, b) => a + b) / logged.length;
  AdaptProposal? proposal;
  if (known && mean != null && mean >= g.kcal - adaptMaxStep) {
    // Τρως περίπου όσο ο στόχος και χάνεις γρήγορα: πρόταση +150, ως όσα καις. Αν ο στόχος είναι ήδη εκεί, καμία κάρτα·
    // ο εβδομαδιαίος έλεγχος τον διορθώνει από τα δεδομένα.
    proposal = fastLossCheck(goals: g, weights: weights, today: t);
    if (proposal == null) return onlyForeign;
  }
  return CheckIn(
      kind: CheckKind.fast,
      goals: g,
      proposal: proposal,
      kgNow: f.kg,
      fastSlope: f.slopeKgWeek,
      fastDays: daysBetween(window.$1, window.$2),
      fastIntake: known ? mean : null,
      fastIntakeDays: logged.length,
      foreign: news);
}

/// Οι ξένες ζυγίσεις που έγραψε η κάρτα θεωρούνται «ειδωμένες» μόλις απαντηθεί (δεν ξαναγράφονται).
Goals _markForeignSeen(CheckIn c, Goals g) {
  if (c.foreign.isEmpty) return g;
  var last = dateKey(c.foreign.first.$1);
  for (final f in c.foreign) {
    final k = dateKey(f.$1);
    if (k.compareTo(last) > 0) last = k;
  }
  return g.copyWith(foreignSeen: last);
}

/// «Εφάρμοσε»: ο νέος στόχος ισχύει από τώρα. Αντικαθιστά και τον δικό σου αριθμό, αν είχες γράψει (το ζήτησες εσύ).
/// Και το βήμα της «γρήγορης απώλειας» γράφεται πια στο ιστορικό ([AdaptLog.fast]· έλεγχος 13/11, S1-3 / S1-6).
Goals applyCheckIn(CheckIn c, DateTime today) {
  final day = dateKey(today);
  final p = c.proposal!;
  if (c.kind == CheckKind.fast) {
    return _markForeignSeen(
        c,
        c.goals.copyWith(
          kcalAdapt: p.target,
          fastAt: day,
          clearKcal: true,
          addLog: AdaptLog(
              day: day, tdee: fastLossCap(c.goals).toDouble(), before: p.current, after: p.target, applied: true, fast: true),
        ));
  }
  return _markForeignSeen(
      c,
      c.goals.copyWith(
        kcalAdapt: p.target,
        tdeeEst: c.est!.tdee,
        checkIn: day,
        clearKcal: true,
        addLog: AdaptLog(day: day, tdee: c.est!.tdee, before: p.current, after: p.target, applied: true),
      ));
}

/// «Όχι τώρα» / «Εντάξει»: ο στόχος μένει ίδιος ως τον επόμενο έλεγχο· η εκτίμηση (αν βγήκε) κρατιέται για τη σελίδα «Στόχοι».
/// [CheckKind.unread] (οι ζυγίσεις δεν διαβάστηκαν) δεν αλλάζει τίποτα: ο έλεγχος της εβδομάδας μένει ανοιχτός (S11-8).
Goals dismissCheckIn(CheckIn c, DateTime today) {
  final day = dateKey(today);
  if (c.kind == CheckKind.unread) return c.goals;
  if (c.kind == CheckKind.foreign) return _markForeignSeen(c, c.goals);
  if (c.kind == CheckKind.fast) return _markForeignSeen(c, c.goals.copyWith(fastAt: day));
  final p = c.proposal;
  final e = c.est;
  if (p == null || e == null) return _markForeignSeen(c, c.goals.copyWith(checkIn: day));
  return _markForeignSeen(
      c,
      c.goals.copyWith(
        tdeeEst: e.tdee,
        checkIn: day,
        addLog: AdaptLog(day: day, tdee: e.tdee, before: p.current, after: p.current, applied: false),
      ));
}

/// Πριν από τον πρώτο έλεγχο (A4): πόσα δεδομένα μαζεύτηκαν ως χθες, μετά την πρώτη εβδομάδα των στόχων (που δεν μετρά:
/// Συμβούλιο 2, Α2), το πολύ 21 μέρες πίσω. [first]: η πρώτη μέρα ελέγχου με εκτίμηση ([firstEstimateDay]).
({int intakeDays, int weighIns, DateTime first}) readiness({
  required Goals goals,
  required DateTime today,
  required List<(DateTime, double)> weights,
  required Map<DateTime, double> Function(DateTime from, DateTime to) intake,
}) {
  final start = DateTime.parse(goals.since);
  final firstCounted = DateTime(start.year, start.month, start.day + adaptSkipDays);
  final to = DateTime(today.year, today.month, today.day - 1);
  final windowFrom = DateTime(to.year, to.month, to.day - (adaptWindowDays - 1));
  final since = firstCounted.isAfter(windowFrom) ? firstCounted : windowFrom;
  final full = adaptFullDayShare * goals.kcal;
  final days = to.isBefore(since) ? 0 : intake(since, to).values.where((v) => v >= full).length;
  final ws = weights.where((w) => !w.$1.isBefore(since) && !w.$1.isAfter(to)).length;
  return (intakeDays: days, weighIns: ws, first: firstEstimateDay(goals));
}
