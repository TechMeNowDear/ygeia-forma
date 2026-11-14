/// «Πρόοδος» (9/11): τι άλλαξε στο περπάτημα και στη δύναμη, τελευταίος μήνας (ή 3 μήνες) σε σχέση με τον προηγούμενο.
///
/// Κανόνες ακρίβειας:
/// - Περπάτημα: ο ίδιος έλεγχος με τις «Τάσεις» ([compareWindows]: μεσαία τιμή, «άλλαξε» μόνο όταν η διαφορά είναι
///   τουλάχιστον [MetricDef.minDiff] ΚΑΙ ξεκάθαρα μεγαλύτερη από τις συνηθισμένες διακυμάνσεις, έλεγχος Welch 1%).
///   Μία τιμή ανά μέρα (μέσος όρος, αν έγιναν δύο περπατήματα). Χρειάζονται [walkNeeded] μέρες με περπάτημα σε κάθε περίοδο.
/// - Μόνο περπατήματα από το ρολόι με GPS και τουλάχιστον [walkMinSec] ενεργό χρόνο, ώστε να συγκρίνονται ίδια πράγματα.
/// - Παλμοί ↓ = «καλύτερα» ΜΟΝΟ αν ο ρυθμός δεν έγινε πιο αργός (ως [paceTolerance]): πιο αργό βάδισμα ρίχνει από
///   μόνο του τους παλμούς. Παλμοί ↑ με πιο γρήγορο βάδισμα: ουδέτερο.
/// - Πτώση παλμών στο 1′: ουδέτερη, ποτέ «καλύτερα/χειρότερα» (έλεγχος 9/11, V-B-08): εξαρτάται κυρίως από την ένταση
///   (πιο γρήγορο βάδισμα = μεγαλύτερη πτώση), άρα δεν δείχνει από μόνη της φυσική κατάσταση. Δίπλα οι παλμοί στο τέλος.
/// - Δύναμη: μόνο γεγονότα (κιλά × επαναλήψεις τότε → τώρα), χωρίς υπολογισμένο «μέγιστο» (1RM).
library;

import '../format.dart' show dayOf;
import '../history.dart' show dateKey;
import '../trends.dart';
import 'equipment.dart';
import 'session.dart';

const walkMinSec = 15 * 60;
const walkNeeded = 4;

/// «Ίδιος ρυθμός» = έως 2% διαφορά στη μεσαία τιμή του ρυθμού.
const paceTolerance = 0.02;

const _kHr = 'pw.hr', _kPace = 'pw.pace', _kHrr = 'pw.hrr', _kHrrEnd = 'pw.hrrEnd';

const walkHrDef = MetricDef(key: _kHr, label: 'Παλμοί στο περπάτημα', section: TrendSection.move, minDiff: 3, unit: 'bpm');
const walkPaceDef = MetricDef(key: _kPace, label: 'Ρυθμός', section: TrendSection.move, minDiff: 15, better: -1);
/// Ουδέτερη (`better: 0`): μεγαλύτερη πτώση βγαίνει και μόνο από πιο γρήγορο βάδισμα (Buchheit 2014· Mann 2014).
const walkHrrDef = MetricDef(key: _kHrr, label: 'Πτώση παλμών στο 1ο λεπτό', section: TrendSection.move, minDiff: 3, unit: 'bpm');

/// Οι παλμοί τη στιγμή του «Τέλος» (από την ίδια μέτρηση): δείχνουν την ένταση, για να διαβάζεται η πτώση.
const walkHrrEndDef = MetricDef(key: _kHrrEnd, label: 'Παλμοί στο τέλος', section: TrendSection.move, minDiff: 3, unit: 'bpm');

/// Μετρά στην πρόοδο του περπατήματος;
bool countsAsWalk(Session s) =>
    s.isCardio &&
    s.finished &&
    !s.stopped &&
    (s.activity ?? 'walk') == 'walk' &&
    s.gps == true &&
    (s.cardioSec ?? 0) >= walkMinSec &&
    (s.meters ?? 0) >= 500;

/// Παλμοί του περπατήματος για σύγκριση: «σταθερό βάδισμα», από το 5′ ως το «Τέλος», χωρίς παύσεις ([Session.steadyHr]·
/// έλεγχος 9/11, V-B-11). Όχι ο μέσος όλου του περπατήματος (εξαρτάται από τη διάρκεια, λόγω των πρώτων λεπτών), και
/// ποτέ εφεδρικός μέσος με τις παύσεις μέσα (03-Χ3). Χωρίς αρκετές τιμές μετά το 5′: τίποτα.
int? walkHr(Session s) => s.steadyHr;

/// Μία τελεία ανά περπάτημα στο [from, end] (για το γράφημα της Προόδου, V-B-10).
List<(DateTime, double)> walkHrPoints(Iterable<Session> sessions, DateTime from, DateTime end) => [
      for (final s in sessions.where(countsAsWalk).toList()..sort((a, b) => a.start.compareTo(b.start)))
        if (!dayOf(s.start).isBefore(from) && !dayOf(s.start).isAfter(end))
          if (walkHr(s) case final v?) (s.start, v.toDouble()),
    ];

/// Μία τιμή ανά μέρα για κάθε δείκτη του περπατήματος (μέσος όρος των περπατημάτων της μέρας).
Map<String, Map<String, double>> walkHistory(Iterable<Session> sessions) {
  final sums = <String, Map<String, List<double>>>{};
  void add(DateTime d, String k, num? v) {
    if (v == null) return;
    ((sums[dateKey(d)] ??= {})[k] ??= []).add(v.toDouble());
  }

  for (final s in sessions) {
    if (!countsAsWalk(s)) continue;
    add(s.start, _kHr, walkHr(s));
    add(s.start, _kPace, s.cardioSec! / (s.meters! / 1000));
    if (s.hrrEnd != null && s.hrr1 != null) {
      add(s.start, _kHrr, s.hrrEnd! - s.hrr1!);
      add(s.start, _kHrrEnd, s.hrrEnd);
    }
  }
  return {
    for (final d in sums.entries) d.key: {for (final m in d.value.entries) m.key: m.value.reduce((a, b) => a + b) / m.value.length},
  };
}

/// Πώς σχετίζεται ο ρυθμός τώρα με πριν.
enum PaceRel { same, faster, slower, unknown }

class WalkProgress {
  WalkProgress(
      {required this.hr, required this.pace, required this.hrr, required this.hrrEnd, required this.countNow, required this.countBefore, required this.secNow});
  final TrendResult hr, pace, hrr;

  /// Παλμοί στο τέλος των ίδιων περπατημάτων (μόνο οι μεσαίες τιμές χρησιμεύουν: η ένταση δίπλα στην πτώση).
  final TrendResult hrrEnd;
  final int countNow, countBefore;

  /// Ενεργός χρόνος περπατήματος στην τρέχουσα περίοδο (″).
  final int secNow;

  PaceRel get paceRel {
    final a = pace.previous, b = pace.current;
    if (a == null || b == null) return PaceRel.unknown;
    if (b > a * (1 + paceTolerance)) return PaceRel.slower;
    if (b < a * (1 - paceTolerance)) return PaceRel.faster;
    return PaceRel.same;
  }

  /// +1 καλύτερα, −1 χειρότερα, 0 ουδέτερο/σταθερό. Παλμοί: μόνο με σύγκριση ρυθμού (δες πάνω).
  int get hrGoodness {
    if (!hr.changed) return 0;
    final rel = paceRel;
    if (hr.status == TrendStatus.down) return rel == PaceRel.same || rel == PaceRel.faster ? 1 : 0;
    return rel == PaceRel.same || rel == PaceRel.slower ? -1 : 0;
  }

  /// Λίγες μέρες με περπάτημα για σύγκριση (σε οποιαδήποτε από τις δύο περιόδους).
  bool get insufficient => hr.status == TrendStatus.insufficient;
}

/// Τα διαστήματα της σύγκρισης, όπως στις «Τάσεις» (μήνας = 30 μέρες, 3 μήνες = 90), με τη σημερινή μέρα.
({DateTime from, DateTime end, DateTime prevFrom, DateTime prevEnd}) progressWindows(DateTime today, TrendPeriod period) {
  final end = dayOf(today);
  final len = period == TrendPeriod.quarter ? 90 : 30;
  DateTime add(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
  final from = add(end, -(len - 1));
  final prevEnd = add(from, -1);
  return (from: from, end: end, prevFrom: add(prevEnd, -(len - 1)), prevEnd: prevEnd);
}

WalkProgress walkProgress(Iterable<Session> sessions, DateTime today, TrendPeriod period) {
  final h = walkHistory(sessions);
  final w = progressWindows(today, period);
  TrendResult cmp(MetricDef d) => compareWindows(d, h,
      currentFrom: w.from, end: w.end, previousFrom: w.prevFrom, previousEnd: w.prevEnd, needed: walkNeeded);
  bool inNow(Session s) => !dayOf(s.start).isBefore(w.from) && !dayOf(s.start).isAfter(w.end);
  bool inBefore(Session s) => !dayOf(s.start).isBefore(w.prevFrom) && !dayOf(s.start).isAfter(w.prevEnd);
  final walks = sessions.where(countsAsWalk).toList();
  return WalkProgress(
    hr: cmp(walkHrDef),
    pace: cmp(walkPaceDef),
    hrr: cmp(walkHrrDef),
    hrrEnd: cmp(walkHrrEndDef),
    countNow: walks.where(inNow).length,
    countBefore: walks.where(inBefore).length,
    secNow: walks.where(inNow).fold(0, (a, s) => a + s.cardioSec!),
  );
}

// ---------------------------------------------------------------- δύναμη

enum StrengthChange { up, down, mixed, same }

/// Μία επανάληψη πάνω-κάτω στο σύνολο των σετ δεν λέγεται αλλαγή.
const repsTolerance = 1;

class ExProgress {
  ExProgress({required this.ex, required this.kind, required this.beforeDay, required this.before, required this.nowDay, required this.now});
  final String ex;
  final LoadKind kind;
  final DateTime beforeDay, nowDay;
  final ExLog before, now;

  // R9-A6-2: τα σετ που κρίνονται ([ExLog.judged]), όπως η πρόοδος της εφαρμογής: όχι ένα σετ παραπάνω («+ Σετ»).
  List<int> get repsBefore => [for (final s in before.judged) s.reps];
  List<int> get repsNow => [for (final s in now.judged) s.reps];

  /// Διαφορά επαναλήψεων στα κοινά σετ (αν έγιναν 2 σετ τη μία φορά και 3 την άλλη, συγκρίνονται τα 2 πρώτα).
  int get repsDiff {
    final n = repsBefore.length < repsNow.length ? repsBefore.length : repsNow.length;
    var d = 0;
    for (var i = 0; i < n; i++) {
      d += repsNow[i] - repsBefore[i];
    }
    return d;
  }

  /// Διαφορά βάρους (θετική = πιο βαρύ· στο λάστιχο βοήθειας, λιγότερη βοήθεια = πιο δύσκολο).
  double get loadDiff {
    if (!hasLoad(kind)) return 0;
    // R7-A6-11: το φορτίο που ΚΑΤΕΛΗΞΕ κάθε φορά ([ExLog.endLoad], όπως η πρόοδος), όχι το μεγαλύτερο: αν μετά το 1ο σετ
    // το βάρος κατέβηκε, η άσκηση «έγινε» με το ελαφρύτερο.
    final a = before.endLoad, b = now.endLoad;
    if (a == null || b == null) return 0;
    // Στρογγυλεμένο στα εκατοστά (11,3 − 9,3 = 2,0000000000000018 στους δεκαδικούς του υπολογιστή).
    return ((kind == LoadKind.bandAssist ? a - b : b - a) * 100).round() / 100;
  }

  /// Τα κοινά σετ της πιο πρόσφατης φοράς έμειναν μέσα στο εύρος του στόχου (καθένα ≥ το κάτω όριο [ExLog.lo] της
  /// πιο πρόσφατης φοράς, όπως ήταν το πρόγραμμα εκείνη τη μέρα).
  bool get repsInRange {
    final n = repsBefore.length < repsNow.length ? repsBefore.length : repsNow.length;
    if (n == 0) return false;
    for (var i = 0; i < n; i++) {
      if (repsNow[i] < now.lo) return false;
    }
    return true;
  }

  /// ±[repsTolerance] επανάληψη στο σύνολο των σετ = ίδιο: τόσο αλλάζει από μέρα σε μέρα χωρίς πραγματική αλλαγή.
  /// Περισσότερο βάρος με τις επαναλήψεις ακόμα μέσα στο εύρος (π.χ. 12, 12, 12 → 9, 9, 8 με κάτω όριο 8) είναι
  /// πρόοδος: έτσι ακριβώς ανεβαίνει το βάρος στο πρόγραμμα (έλεγχος 9/11, V-B-12). «Μικτό» μόνο όταν κάποιο σετ
  /// έπεσε κάτω από το εύρος.
  StrengthChange get change {
    final l = loadDiff, r = repsDiff;
    const eps = 1e-6;
    if (l > eps) return r >= -repsTolerance || repsInRange ? StrengthChange.up : StrengthChange.mixed;
    if (l < -eps) return r > repsTolerance ? StrengthChange.mixed : StrengthChange.down;
    if (r > repsTolerance) return StrengthChange.up;
    if (r < -repsTolerance) return StrengthChange.down;
    return StrengthChange.same;
  }
}

/// Για κάθε άσκηση που έγινε στην τρέχουσα περίοδο: η τελευταία φορά της προηγούμενης περιόδου → η πιο πρόσφατη.
/// Αν ξεκίνησε μέσα στην τρέχουσα: η πρώτη φορά → η πιο πρόσφατη (χρειάζονται 2). Η πιο πρόσφατη πρώτη.
List<ExProgress> strengthProgress(Iterable<Session> sessions, DateTime today, TrendPeriod period) {
  final w = progressWindows(today, period);
  final logs = <String, List<(DateTime, ExLog)>>{};
  final ordered = sessions.where((s) => s.finished && !s.stopped && !s.isCardio).toList()..sort((a, b) => a.start.compareTo(b.start));
  for (final s in ordered) {
    final d = dayOf(s.start);
    if (d.isBefore(w.prevFrom) || d.isAfter(w.end)) continue;
    for (final e in s.items) {
      if (e.skipped || e.done.isEmpty) continue;
      (logs[e.ex] ??= []).add((d, e));
    }
  }
  final out = <ExProgress>[];
  for (final entry in logs.entries) {
    final list = entry.value;
    final now = [for (final x in list) if (!x.$1.isBefore(w.from)) x];
    if (now.isEmpty) continue;
    final prev = [for (final x in list) if (x.$1.isBefore(w.from)) x];
    final (DateTime, ExLog) before;
    if (prev.isNotEmpty) {
      before = prev.last;
    } else if (now.length >= 2) {
      before = now.first;
    } else {
      continue;
    }
    final last = now.last;
    out.add(ExProgress(ex: entry.key, kind: last.$2.kind, beforeDay: before.$1, before: before.$2, nowDay: last.$1, now: last.$2));
  }
  out.sort((a, b) => b.nowDay.compareTo(a.nowDay));
  return out;
}
