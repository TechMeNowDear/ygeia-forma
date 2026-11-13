/// Αναφορά για γιατρό: τι μπαίνει και πώς υπολογίζεται. Μόνο από τις ημερήσιες συνόψεις
/// (ίδια νούμερα με την εφαρμογή). Οι πειραματικοί δείκτες (ηρεμία ξύπνιος) ΔΕΝ μπαίνουν.
library;

import 'dart:math' as math;

import 'format.dart';
import 'history.dart';
import 'sources.dart';
import 'trends.dart';

const reportDays = 90;

/// Στατιστικά ενός δείκτη στο διάστημα της αναφοράς.
class ReportStat {
  ReportStat({required this.values, this.trend, this.source = Source.watch, this.since, this.periods = const []});

  /// Οξυγόνο (ίδιος αισθητήρας, άλλος ορισμός νύχτας μετά το Oura): οι τιμές ΟΛΩΝ των 90 ημερών στο [values], και
  /// εδώ ένα κομμάτι για κάθε ορισμό της νύχτας, παλιότερο πρώτο (κενό αν ο ορισμός δεν άλλαξε μέσα στο διάστημα).
  final List<ReportPeriod> periods;

  /// Από ποια συσκευή είναι όλες οι τιμές (μία, πάντα).
  final Source source;

  /// Αν η πηγή άλλαξε μέσα στο διάστημα της αναφοράς: από πότε μετρούν οι τιμές (μόνο της νέας πηγής).
  final DateTime? since;

  /// (μέρα, τιμή), παλιότερη πρώτη.
  final List<(DateTime, double)> values;

  /// Σύγκριση με τους 3 προηγούμενους μήνες (αν υπάρχουν αρκετά δεδομένα).
  final TrendResult? trend;

  int get n => values.length;
  double? get median => n == 0 ? null : _quantile(0.5);
  double? get low => n == 0 ? null : values.map((e) => e.$2).reduce(math.min);
  double? get high => n == 0 ? null : values.map((e) => e.$2).reduce(math.max);

  /// Τυπικό εύρος: από το 10ο ως το 90ό εκατοστημόριο (οι 8 στις 10 μέρες).
  double? get p10 => n < 5 ? null : _quantile(0.1);
  double? get p90 => n < 5 ? null : _quantile(0.9);

  double _quantile(double q) {
    final s = values.map((e) => e.$2).toList()..sort();
    final pos = (s.length - 1) * q;
    final i = pos.floor();
    final f = pos - i;
    return i + 1 < s.length ? s[i] + (s[i + 1] - s[i]) * f : s[i];
  }
}

/// Ένα κομμάτι του διαστήματος με τον ίδιο ορισμό της νύχτας (οξυγόνο), ή με την ίδια συσκευή ([reportDeviceKeys]).
class ReportPeriod {
  ReportPeriod({required this.from, required this.to, required this.night, required this.stat, this.oldRules = false});
  final DateTime from;
  final DateTime to;

  /// Από πού ορίζεται η νύχτα: ρολόι (ο ύπνος του ρολογιού) ή Oura (οι ώρες ύπνου του Oura).
  final Source night;
  final ReportStat stat;

  /// Μέρες πριν από το όριο της επανανάγνωσης (έλεγχος 2, C4): ακόμα με τον παλιό κανόνα της νύχτας («Ενημερώνεται
  /// το ιστορικό»). Άλλος ορισμός: χωριστή γραμμή, ποτέ σύγκριση πάνω από το όριο.
  final bool oldRules;
}

/// Μετρήσεις του ίδιου αισθητήρα (ρολόι, καρπός) με ορισμό νύχτας που αλλάζει με την πηγή του ύπνου. Στην αναφορά
/// μπαίνουν ΟΛΕΣ οι 90 μέρες, με ετικέτα για κάθε ορισμό· ποτέ κομμένες στη σύνδεση του Oura (δεύτερος κλινικός
/// έλεγχος K1: οι νύχτες με 72% και 74% πριν από το Oura είναι ο λόγος της επίσκεψης). Η «Διαφορά» μένει «Αλλαγή
/// ορισμού»: δεν συγκρίνεται πάνω από την αλλαγή.
const reportSensorKeys = {K.spo2Avg, K.spo2Min};

/// Ύπνος και παλμοί ύπνου: άλλη συσκευή μετά τη σύνδεση του Oura. Έλεγχος 4 (2_calcs M2 = κλινικός C3): όταν η
/// συσκευή άλλαξε μέσα στις 90 μέρες, μία γραμμή για κάθε περίοδο συσκευής («ως 5/11: ρολόι», «↳ από 6/11: Oura»),
/// η καθεμία με τη δική της μεσαία τιμή και εύρος, «Διαφορά» = «Αλλαγή συσκευής». Ποτέ μαζί οι δύο πηγές (πριν: μόνο
/// οι νύχτες του Oura, και ο γιατρός έχανε τις ~80 νύχτες του ρολογιού).
const reportDeviceKeys = {K.sleepHr, K.sleepMin, K.bedtime, K.wake};

class ReportData {
  ReportData({
    required this.from,
    required this.to,
    required this.created,
    required this.stats,
    required this.lowOxygenNights,
    required this.weighIns,
    this.plan,
    this.otherWeighIns = const {},
    this.weighInsInPeriod = 0,
    this.weighInsSpread = false,
    this.foreignWeighIns = 0,
    this.pendingWeighIns = const {},
  });

  /// Round 3 (k1 · R3-A-3): οι ζυγίσεις του [weighIns] «σε αναμονή» (διαφέρουν πολύ από τις προηγούμενες και δεν τις
  /// βεβαίωσαν ακόμα επόμενες: weight_guard.dart). Φαίνονται στον πίνακα με σημάδι· δεν μπαίνουν σε υπολογισμούς.
  final Set<DateTime> pendingWeighIns;

  /// Round 1 (U1b-13): πόσες ζυγίσεις (που μετρούν) έγιναν μέσα στο διάστημα της αναφοράς.
  final int weighInsInPeriod;

  /// Round 1 (U1b-13): true = οι γραμμές του [weighIns] είναι απλωμένες από την πρώτη ως την τελευταία ζύγιση του
  /// διαστήματος (περισσότερες από 6 μέσα σε αυτό)· false = οι τελευταίες (έως 6).
  final bool weighInsSpread;

  /// Round 1 (S11-2): ζυγίσεις που μοιάζουν ξένες και δεν μπήκαν στον πίνακα· round 4 (m1 · R4-A-5): μόνο του
  /// διαστήματος της αναφοράς ([from]–[to]).
  final int foreignWeighIns;

  /// Έλεγχος 3, E2: οι ζυγίσεις του [weighIns] που ΔΕΝ είναι της InBody (παλιές εκδόσεις, πριν από την πρώτη ζύγιση
  /// InBody): φαίνονται με την πηγή τους («όχι InBody»), ποτέ ως ζυγίσεις της InBody.
  final Set<DateTime> otherWeighIns;

  /// Οι πηγές (για τη σημείωση «Πώς μετρήθηκαν»).
  final SourcePlan? plan;

  /// Έως 6 ζυγίσεις, η νεότερη πρώτη: (μέρα, βάρος, λίπος %, μύες). Με περισσότερες από 6 μέσα στο διάστημα, απλωμένες
  /// από την πρώτη ως την τελευταία ([weighInsSpread])· αλλιώς οι τελευταίες, όποτε κι αν έγιναν.
  final List<(DateTime, double?, double?, double?)> weighIns;

  final DateTime from;
  final DateTime to;
  final DateTime created;

  /// Κλειδί (K.*) → στατιστικά.
  final Map<String, ReportStat> stats;

  /// Νύχτες με ελάχιστο οξυγόνο κάτω από 90%, (μέρα, ελάχιστο), με χρονολογική σειρά (δεύτερος κλινικός έλεγχος M4).
  final List<(DateTime, double)> lowOxygenNights;

  ReportStat stat(String key) => stats[key] ?? ReportStat(values: const []);

  /// Οι νύχτες με χαμηλότερη μέτρηση οξυγόνου κάτω από [limit]%, με χρονολογική σειρά (σύγκριση πριν από
  /// στρογγυλοποίηση: 84,6 μετρά ως κάτω από 85).
  List<(DateTime, double)> oxygenBelow(double limit) => [
        for (final v in stat(K.spo2Min).values)
          if (v.$2 < limit) v,
      ];

  /// Νύχτες χωρίς φάσεις: έχουν ώρα ύπνου αλλά όχι διάρκεια (η διάρκεια μετρά μόνο τον πραγματικό ύπνο από τις
  /// φάσεις). Γράφεται στην αναφορά (δεύτερος έλεγχος υπολογισμών C10). Τρίτος έλεγχος F4: μετριούνται ΜΕΡΑ-ΜΕΡΑ (ώρα
  /// ύπνου χωρίς διάρκεια), όχι ως διαφορά δύο πληθών: μια μέρα με διάρκεια αλλά χωρίς ώρα ύπνου (κρατημένη διάρκεια
  /// μετά από ανάγνωση χωρίς ύπνο) «έτρωγε» μια νύχτα χωρίς φάσεις από το μέτρημα.
  int get nightsWithoutStages {
    final timed = {for (final v in stat(K.sleepMin).values) dateKey(v.$1)};
    return stat(K.bedtime).values.where((v) => !timed.contains(dateKey(v.$1))).length;
  }
}

const reportKeys = [
  K.sleepHr,
  K.spo2Avg,
  K.spo2Min,
  K.sleepMin,
  K.bedtime,
  K.wake,
  K.steps,
  K.weight,
  K.fatPct,
  K.smm,
];

/// Μετά τη σύνδεση του Oura η αναφορά δείχνει και ό,τι δίνει μόνο αυτό.
List<String> reportKeysFor(SourcePlan plan) => plan.hasOura ? [...reportKeys, K.lowHr, K.hrv, K.breath, K.ringSpo2] : reportKeys;

/// [end]: η τελευταία μέρα του διαστήματος, ίδια με τις Τάσεις από όπου ανοίγει η αναφορά (δεύτερος έλεγχος
/// υπολογισμών C12: μετά τα μεσάνυχτα, πριν από ανανέωση, οι Τάσεις τελείωναν χθες και η αναφορά σήμερα). Χωρίς
/// [end]: η μέρα του [now]. Το [now] είναι πάντα η ώρα δημιουργίας.
ReportData buildReport(Map<String, Map<String, double>> history, DateTime now, {SourcePlan? plan, DateTime? end}) {
  final p = plan ?? SourcePlan.samsungOnly;
  DateTime add(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
  final to = dayOf(end ?? now);
  final from = add(to, -(reportDays - 1));
  final stats = <String, ReportStat>{};

  for (final key in reportKeysFor(p)) {
    // Βήματα: η σημερινή μέρα δεν έχει τελειώσει.
    final last = key == K.steps ? add(to, -1) : to;
    // Πάντα 90 μέρες ως το [last], ίδιο διάστημα με τη «Διαφορά» της ίδιας γραμμής (έλεγχος υπολογισμών F11:
    // πριν, τα βήματα είχαν 89 μέρες στον πίνακα και 90 στη σύγκριση).
    final start = add(last, -(reportDays - 1));
    final def = metricDef(key);
    final trend = def == null ? null : computeTrend(def, history, to, TrendPeriod.quarter, plan: p);
    if (reportSensorKeys.contains(key)) {
      stats[key] = _sensorStat(history, p, key, start, last, trend);
      continue;
    }
    if (reportDeviceKeys.contains(key)) {
      final devices = _deviceStat(history, p, key, start, last, trend);
      if (devices != null) {
        stats[key] = devices;
        continue;
      }
    }
    // Μόνο μία πηγή ανά δείκτη: αν άλλαξε μέσα στους 3 μήνες, μετρούν μόνο οι μέρες της νέας.
    final series = planSeries(history, p, key, start, last);
    // Round 3 (k1 · R3-C-1/2, R3-A-1): βάρος, λίπος, μύες μόνο από ζυγίσεις που μετρούν ([uncountedWeighIn]), όπως οι
    // Τάσεις (και η «Διαφορά» της ίδιας γραμμής).
    final values = def != null && def.sparse
        ? [
            for (final v in series.points)
              if (!uncountedWeighIn(history, p, v.$1)) v,
          ]
        : series.points;
    stats[key] = ReportStat(values: values, trend: trend, source: series.source, since: series.cut);
  }

  // Χρονολογική σειρά (M4): ο γιατρός διαβάζει το μοτίβο και τη σχέση με φάρμακα και συμπτώματα.
  final low = [
    for (final v in stats[K.spo2Min]!.values)
      if (v.$2 < 90) v,
  ];

  // Round 1 (S11-2): ζυγίσεις που μοιάζουν ξένες δεν μπαίνουν (μετριούνται, για τη σημείωση).
  final allWeighDays = history.keys.where((k) => p.value(history, K.weight, parseDateKey(k)) != null).toList()..sort();
  final foreignKeys = {for (final k in allWeighDays) if (foreignWeighIn(history, p, parseDateKey(k))) k};
  final weighDays = [for (final k in allWeighDays) if (!foreignKeys.contains(k)) k];
  // Round 1 (U1b-13): με ζύγιση κάθε 2–3 μέρες οι 6 τελευταίες ήταν μόνο οι 2 τελευταίες εβδομάδες, και η αλλαγή των 3
  // μηνών δεν φαινόταν πουθενά. Με περισσότερες από 6 μέσα στο διάστημα: η πρώτη, η τελευταία και 4 ανάμεσα.
  final inPeriod = [
    for (final k in weighDays)
      if (!parseDateKey(k).isBefore(from) && !parseDateKey(k).isAfter(to)) k,
  ];
  final spread = inPeriod.length > 6;
  final picked = spread ? spreadPick(inPeriod, 6) : weighDays.reversed.take(6).toList().reversed.toList();
  final weighIns = [
    for (final k in picked.reversed)
      (
        parseDateKey(k),
        p.value(history, K.weight, parseDateKey(k)),
        p.value(history, K.fatPct, parseDateKey(k)),
        p.value(history, K.smm, parseDateKey(k)),
      ),
  ];

  return ReportData(
    from: from,
    to: to,
    created: now,
    stats: stats,
    lowOxygenNights: low,
    weighIns: weighIns,
    otherWeighIns: {
      for (final w in weighIns)
        if (SourcePlan.isOtherWeighIn(history, w.$1)) w.$1,
    },
    plan: p,
    weighInsInPeriod: inPeriod.length,
    weighInsSpread: spread,
    // Round 4 (m1 · R4-A-5): μόνο όσες είναι μέσα στο διάστημα της αναφοράς (η σημείωση είναι κάτω από τον πίνακά του·
    // πριν: όλου του ιστορικού, π.χ. «24 ζυγίσεις» αντί για 6 με ένα παιδί στη ζυγαριά δύο φορές τον μήνα).
    foreignWeighIns: foreignKeys.where((k) => !parseDateKey(k).isBefore(from) && !parseDateKey(k).isAfter(to)).length,
    // Round 3 (k1 · R3-A-3): ζυγίσεις του πίνακα «σε αναμονή»: φαίνονται, με σημάδι και σημείωση.
    pendingWeighIns: {
      for (final w in weighIns)
        if (pendingWeighIn(history, p, w.$1)) w.$1,
    },
  );
}

/// Round 1 (U1b-13): [n] στοιχεία της [v] (ταξινομημένης), η πρώτη, η τελευταία και ανάμεσα σε ίσες αποστάσεις.
/// Με λιγότερα από [n], όλα.
List<T> spreadPick<T>(List<T> v, int n) {
  if (v.length <= n || n < 2) return v.length <= n ? List<T>.of(v) : [v.last];
  return [for (var i = 0; i < n; i++) v[(i * (v.length - 1) / (n - 1)).round()]];
}

/// Οξυγόνο: όλες οι 90 μέρες του ρολογιού (ίδιος αισθητήρας), και ένα κομμάτι για κάθε ορισμό της νύχτας (αλλαγή
/// πηγής της νύχτας, ή όριο επανανάγνωσης με νέους κανόνες, C4: [ReportPeriod.oldRules]).
ReportStat _sensorStat(
  Map<String, Map<String, double>> history,
  SourcePlan p,
  String key,
  DateTime start,
  DateTime last,
  TrendResult? trend,
) {
  DateTime add(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
  // Έλεγχος #2 (D2-01): ίδιος κανόνας με την εφαρμογή για τη χαμηλότερη: σε νύχτα του Oura μόνο όταν το ρολόι
  // μέτρησε τουλάχιστον το μισό ύπνο ([spo2MinCoverage]). Παλιές μέρες χωρίς κάλυψη γραμμένη: όπως ήταν. Ο μέσος όρος
  // του ρολογιού μένει όλες τις 90 μέρες (K1), με ετικέτα «ρολόι»· του δαχτυλιδιού έχει δική του γραμμή.
  // Round 1 (S4-8 (4)): ο ίδιος κανόνας κάλυψης και για τον μέσο όρο του ρολογιού σε νύχτα του Oura ([watchOxygenCovered]):
  // ένας «μέσος όρος» από το 10% του ύπνου δεν είναι μέσος όρος της νύχτας.
  bool keep(DateTime d) => watchOxygenCovered(history, p, d);

  final values = <(DateTime, double)>[];
  for (var d = start; !d.isAfter(last); d = add(d, 1)) {
    final v = p.value(history, key, d);
    if (v != null && keep(d)) values.add((d, v));
  }
  final cuts = [for (final c in p.changeDates(key)) if (c.isAfter(start) && !c.isAfter(last)) c];
  final periods = <ReportPeriod>[];
  if (cuts.isNotEmpty) {
    final bounds = [start, ...cuts, add(last, 1)];
    for (var i = 0; i + 1 < bounds.length; i++) {
      final from = bounds[i];
      final to = add(bounds[i + 1], -1);
      periods.add(ReportPeriod(
        from: from,
        to: to,
        night: p.nightSource(from) == Source.oura ? Source.oura : Source.watch,
        stat: ReportStat(values: [for (final v in values) if (!v.$1.isBefore(from) && !v.$1.isAfter(to)) v]),
        oldRules: p.rulesFrom != null && to.isBefore(p.rulesFrom!),
      ));
    }
  }
  return ReportStat(values: values, trend: trend, source: p.sourceFor(key, last), periods: periods);
}

/// [reportDeviceKeys] με αλλαγή συσκευής μέσα στις 90 μέρες: ένα κομμάτι για κάθε περίοδο (και για το όριο της
/// επανανάγνωσης, αν είναι μέσα), κάθε τιμή ΜΟΝΟ από την πηγή της μέρας της. null = καμία αλλαγή συσκευής μέσα στο
/// διάστημα (τότε όπως πριν: [planSeries]).
ReportStat? _deviceStat(
  Map<String, Map<String, double>> history,
  SourcePlan p,
  String key,
  DateTime start,
  DateTime last,
  TrendResult? trend,
) {
  DateTime add(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
  final cuts = [for (final c in p.changeDates(key)) if (c.isAfter(start) && !c.isAfter(last)) c];
  if (!cuts.any((c) => p.nightSource(add(c, -1)) != p.nightSource(c))) return null;
  final values = <(DateTime, double)>[];
  for (var d = start; !d.isAfter(last); d = add(d, 1)) {
    final v = p.value(history, key, d);
    if (v != null) values.add((d, v));
  }
  final bounds = [start, ...cuts, add(last, 1)];
  final periods = <ReportPeriod>[
    for (var i = 0; i + 1 < bounds.length; i++)
      () {
        final from = bounds[i];
        final to = add(bounds[i + 1], -1);
        return ReportPeriod(
          from: from,
          to: to,
          night: p.nightSource(from),
          stat: ReportStat(
            values: [for (final v in values) if (!v.$1.isBefore(from) && !v.$1.isAfter(to)) v],
            source: p.nightSource(from),
          ),
          oldRules: p.rulesFrom != null && to.isBefore(p.rulesFrom!),
        );
      }(),
  ];
  return ReportStat(values: values, trend: trend, source: p.sourceFor(key, last), periods: periods);
}
