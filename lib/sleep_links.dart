/// «Τι συνδέεται με τον ύπνο σου» (συμφωνία 30/10, υλοποίηση 18/11).
///
/// Κάθε νύχτα (με ημερομηνία το πρωί, όπως παντού) μπαίνει δίπλα στην προηγούμενη μέρα:
/// - **ώρες από το τελευταίο φαγητό ως τον ύπνο**, **θερμίδες βραδινού**, **βήματα της μέρας**, **ώρα ύπνου**·
/// - απέναντι σε **παλμούς ύπνου**, **HRV** και **διάρκεια ύπνου** της νύχτας.
///
/// Στατιστική (δική μας, συντηρητική):
/// - Μόνο οι τελευταίες [sleepLinkWindowDays] νύχτες, και μόνο της ίδιας πηγής (δεν περνά πάνω από αλλαγή πηγής).
/// - Συσχέτιση Spearman (με τάξεις: δεν την παρασύρει μία ακραία νύχτα).
/// - Οι διαδοχικές νύχτες μοιάζουν μεταξύ τους: το πλήθος των «ανεξάρτητων» νυχτών μικραίνει με τον τύπο του Bartlett για
///   δύο σειρές AR(1), n·(1 − φx·φy)/(1 + φx·φy) (Bartlett 1935· Dawdy & Matalas 1964).
/// - 4 × 3 = 12 έλεγχοι μαζί: διόρθωση Holm (1979) στο 5%, ώστε η πιθανότητα να φανεί έστω μία ψεύτικη σύνδεση να μένει
///   κάτω από 5%. Και |ρ| ≥ [sleepLinkMinRho], ώστε να μη λέγεται «συνδέεται» μια ασήμαντη διαφορά.
///   Προσομοίωση (sim 18/11, χωρίς καμία πραγματική σύνδεση, φ 0,3–0,6): ψεύτικη σύνδεση στο 2–4,5% των φορών. Με
///   πραγματική σύνδεση ρ = 0,45 τη βρίσκει στο ~20% με 28 νύχτες, ~57% με 56, ~83% με 84.
/// - Ό,τι φαίνεται είναι «συνδέεται», ποτέ «προκαλεί»: π.χ. τα βήματα και ο ύπνος μπορεί να αλλάζουν μαζί επειδή
///   αλλάζει η εβδομάδα (δουλειά, Σαββατοκύριακο).
///
/// Η ώρα του φαγητού είναι η ώρα που **γράφτηκε**: μετρά μόνο μέρα με «Τελείωσα για σήμερα» ([DayMark.done]) και όλες
/// τις καταχωρίσεις γραμμένες από τα μεσάνυχτα της μέρας ως την ώρα του ύπνου. Οι θερμίδες βραδινού μόνο σε μέρα με
/// «Τελείωσα για σήμερα» (αλλιώς ένα βραδινό που δεν γράφτηκε θα μετρούσε 0).
library;

import 'dart:math' as math;

import 'food/food_model.dart';
import 'format.dart';
import 'history.dart';
import 'sources.dart';
import 'trends.dart' show dailyCorrelation;

/// Πόσες νύχτες (με τιμή και στα δύο) χρειάζεται ένα ζευγάρι για να κριθεί.
const sleepLinkMinNights = 28;

/// Το παράθυρο: 12 εβδομάδες (το ημερολόγιο φαγητού κρατά στη μνήμη 90 μέρες).
const sleepLinkWindowDays = 84;

/// Τουλάχιστον τόσες νύχτες σε κάθε μισό (πάνω/κάτω από τη διάμεσο).
const sleepLinkMinGroup = 10;

/// Η μικρότερη συσχέτιση που λέγεται «συνδέεται».
const sleepLinkMinRho = 0.25;

/// Επίπεδο σημαντικότητας για όλους τους ελέγχους μαζί (Holm).
const sleepLinkAlpha = 0.05;

enum LinkCause { mealGap, dinnerKcal, steps, bedtime }

enum LinkSleep { sleepHr, hrv, sleepMin }

String _sleepKey(LinkSleep s) => switch (s) {
      LinkSleep.sleepHr => K.sleepHr,
      LinkSleep.hrv => K.hrv,
      LinkSleep.sleepMin => K.sleepMin,
    };

/// Μία σύγκριση: [cause] απέναντι σε [sleep].
class SleepLink {
  const SleepLink({
    required this.cause,
    required this.sleep,
    required this.n,
    required this.rho,
    required this.p,
    required this.split,
    required this.lowMean,
    required this.highMean,
    required this.found,
  });
  final LinkCause cause;
  final LinkSleep sleep;

  /// Νύχτες με τιμή και στα δύο.
  final int n;

  /// Spearman.
  final double rho;

  /// p δύο πλευρών (πριν από τη διόρθωση Holm).
  final double p;

  /// Η διάμεσος της αιτίας: «κάτω» = ως και αυτήν, «πάνω» = πάνω από αυτήν.
  final double split;

  /// Μέσος όρος του ύπνου στις νύχτες «κάτω» και «πάνω».
  final double lowMean, highMean;

  /// Πέρασε όλους τους ελέγχους.
  final bool found;
}

class SleepLinksResult {
  const SleepLinksResult({required this.nights, required this.links});

  /// Οι νύχτες του ζευγαριού με τις περισσότερες (για το «Μαζεύω: X από 28»).
  final int nights;

  /// Όσα ζευγάρια είχαν αρκετές νύχτες για να κριθούν.
  final List<SleepLink> links;

  bool get ready => links.isNotEmpty;
  List<SleepLink> get found => [for (final l in links) if (l.found) l];
}

/// Μία νύχτα: οι «αιτίες» της προηγούμενης μέρας και ο ύπνος.
typedef _Night = ({DateTime night, Map<LinkCause, double> cause, Map<LinkSleep, double> sleep});

/// [entries]: οι καταχωρίσεις φαγητού μιας μέρας· [mark]: το «Τελείωσα για σήμερα» μιας μέρας.
SleepLinksResult sleepLinks({
  required Map<String, Map<String, double>> history,
  required SourcePlan plan,
  required DateTime today,
  required List<LogEntry> Function(DateTime day) entries,
  required DayMark? Function(DateTime day) mark,
}) {
  final t = dayOf(today);
  final from = DateTime(t.year, t.month, t.day - sleepLinkWindowDays + 1);
  // Η πηγή κάθε τιμής νύχτας: μόνο από την τελευταία αλλαγή πηγής και μετά.
  DateTime startFor(String key) {
    final s = plan.segmentStart(key, t);
    return s != null && s.isAfter(from) ? s : from;
  }

  final rows = <_Night>[];
  for (var d = from; !d.isAfter(t); d = DateTime(d.year, d.month, d.day + 1)) {
    final prev = DateTime(d.year, d.month, d.day - 1);
    final cause = <LinkCause, double>{};
    final sleep = <LinkSleep, double>{};
    for (final s in LinkSleep.values) {
      final k = _sleepKey(s);
      if (d.isBefore(startFor(k))) continue;
      final v = plan.value(history, k, d);
      if (v != null && v.isFinite && v > 0) sleep[s] = v;
    }
    if (sleep.isEmpty) continue;
    final bed = d.isBefore(startFor(K.bedtime)) ? null : plan.value(history, K.bedtime, d);
    if (bed != null) cause[LinkCause.bedtime] = bed;
    final steps = plan.value(history, K.steps, prev);
    if (steps != null && steps > 0) cause[LinkCause.steps] = steps;
    if (mark(prev) == DayMark.done) {
      final es = entries(prev);
      if (es.isNotEmpty) {
        cause[LinkCause.dinnerKcal] = Totals(es.where((e) => e.meal == Meal.dinner)).kcal;
        if (bed != null) {
          final bedAt = DateTime(prev.year, prev.month, prev.day, 18).add(Duration(minutes: bed.round()));
          final dayStart = DateTime(prev.year, prev.month, prev.day);
          // Όλες γραμμένες από τα μεσάνυχτα της μέρας ως τον ύπνο· αλλιώς η ώρα δεν λέει πότε έφαγες.
          if (es.every((e) => !e.time.isBefore(dayStart) && e.time.isBefore(bedAt))) {
            final last = es.map((e) => e.time).reduce((a, b) => a.isAfter(b) ? a : b);
            cause[LinkCause.mealGap] = bedAt.difference(last).inMinutes / 60;
          }
        }
      }
    }
    rows.add((night: d, cause: cause, sleep: sleep));
  }

  var most = 0;
  final tested = <SleepLink>[];
  for (final c in LinkCause.values) {
    for (final s in LinkSleep.values) {
      final pts = [
        for (final r in rows)
          if (r.cause[c] != null && r.sleep[s] != null) (r.night, r.cause[c]!, r.sleep[s]!),
      ];
      most = math.max(most, pts.length);
      if (pts.length < sleepLinkMinNights) continue;
      final l = _test(c, s, pts);
      if (l != null) tested.add(l);
    }
  }
  // Holm: με τη σειρά από το μικρότερο p· σταματά στο πρώτο που δεν περνά.
  final order = [for (var i = 0; i < tested.length; i++) i]..sort((a, b) => tested[a].p.compareTo(tested[b].p));
  final pass = List<bool>.filled(tested.length, false);
  for (var k = 0; k < order.length; k++) {
    if (tested[order[k]].p <= sleepLinkAlpha / (order.length - k)) {
      pass[order[k]] = true;
    } else {
      break;
    }
  }
  final out = <SleepLink>[
    for (var i = 0; i < tested.length; i++)
      SleepLink(
        cause: tested[i].cause,
        sleep: tested[i].sleep,
        n: tested[i].n,
        rho: tested[i].rho,
        p: tested[i].p,
        split: tested[i].split,
        lowMean: tested[i].lowMean,
        highMean: tested[i].highMean,
        // Και η διαφορά των δύο μισών προς την ίδια μεριά με τη συσχέτιση.
        found: pass[i] &&
            tested[i].rho.abs() >= sleepLinkMinRho &&
            (tested[i].highMean - tested[i].lowMean).sign == tested[i].rho.sign,
      ),
  ];
  return SleepLinksResult(nights: most, links: out);
}

SleepLink? _test(LinkCause c, LinkSleep s, List<(DateTime, double, double)> pts) {
  final xs = [for (final p in pts) p.$2];
  final ys = [for (final p in pts) p.$3];
  final split = _median(xs);
  final low = [for (final p in pts) if (p.$2 <= split) p.$3];
  final high = [for (final p in pts) if (p.$2 > split) p.$3];
  if (low.length < sleepLinkMinGroup || high.length < sleepLinkMinGroup) return null;
  final rho = _pearson(_ranks(xs), _ranks(ys));
  final n = pts.length;
  // Αυτοσυσχέτιση κάθε σειράς, σε κομμάτια 28 ημερών (μια αλλαγή επιπέδου δεν μετρά ως «νύχτες που μοιάζουν»).
  double phiOf(List<(DateTime, double)> v) {
    final blocks = <List<(DateTime, double)>>[];
    for (final e in v) {
      final b = daysBetween(v.first.$1, e.$1) ~/ 28;
      while (blocks.length <= b) {
        blocks.add([]);
      }
      blocks[b].add(e);
    }
    // Χωρίς εκτίμηση: συντηρητικά 0,5.
    return dailyCorrelation(blocks) ?? 0.5;
  }

  final fx = phiOf([for (final p in pts) (p.$1, p.$2)]);
  final fy = phiOf([for (final p in pts) (p.$1, p.$3)]);
  final nEff = n * (1 - fx * fy) / (1 + fx * fy);
  final df = nEff - 2;
  double p;
  if (rho.abs() >= 0.999999) {
    p = 0;
  } else if (df < 3) {
    p = 1;
  } else {
    final tv = rho.abs() * math.sqrt(df / (1 - rho * rho));
    p = studentTwoSidedP(tv, df);
  }
  return SleepLink(
    cause: c,
    sleep: s,
    n: n,
    rho: rho,
    p: p,
    split: split,
    lowMean: low.reduce((a, b) => a + b) / low.length,
    highMean: high.reduce((a, b) => a + b) / high.length,
    found: false,
  );
}

double _median(List<double> v) {
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

/// Τάξεις με μέσο όρο στις ισοπαλίες (1 = η μικρότερη).
List<double> _ranks(List<double> v) {
  final idx = [for (var i = 0; i < v.length; i++) i]..sort((a, b) => v[a].compareTo(v[b]));
  final r = List<double>.filled(v.length, 0);
  var i = 0;
  while (i < idx.length) {
    var j = i;
    while (j + 1 < idx.length && v[idx[j + 1]] == v[idx[i]]) {
      j++;
    }
    for (var k = i; k <= j; k++) {
      r[idx[k]] = (i + j) / 2 + 1;
    }
    i = j + 1;
  }
  return r;
}

double _pearson(List<double> x, List<double> y) {
  final n = x.length;
  final mx = x.reduce((a, b) => a + b) / n;
  final my = y.reduce((a, b) => a + b) / n;
  var sxy = 0.0, sxx = 0.0, syy = 0.0;
  for (var i = 0; i < n; i++) {
    sxy += (x[i] - mx) * (y[i] - my);
    sxx += (x[i] - mx) * (x[i] - mx);
    syy += (y[i] - my) * (y[i] - my);
  }
  return sxx > 0 && syy > 0 ? sxy / math.sqrt(sxx * syy) : 0;
}

/// p δύο πλευρών της κατανομής t του Student: I_{df/(df+t²)}(df/2, 1/2) (κανονικοποιημένη ελλιπής βήτα).
/// Επαλήθευση (sim 18/11): t 2,228/df 10 → 0,0500· 2,0/10 → 0,0734· 3,0/30 → 0,0054.
double studentTwoSidedP(double t, double df) => _incBeta(df / 2, 0.5, df / (df + t * t));

double _lgamma(double x) {
  // Lanczos (g = 7, 9 όροι).
  const c = [
    0.99999999999980993, 676.5203681218851, -1259.1392167224028, 771.32342877765313, -176.61502916214059,
    12.507343278686905, -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7,
  ];
  if (x < 0.5) return math.log(math.pi / math.sin(math.pi * x).abs()) - _lgamma(1 - x);
  final y = x - 1;
  var a = c[0];
  final t = y + 7.5;
  for (var i = 1; i < 9; i++) {
    a += c[i] / (y + i);
  }
  return 0.5 * math.log(2 * math.pi) + (y + 0.5) * math.log(t) - t + math.log(a);
}

double _betacf(double a, double b, double x) {
  const tiny = 1e-300;
  final qab = a + b, qap = a + 1, qam = a - 1;
  var c = 1.0;
  var d = 1 - qab * x / qap;
  if (d.abs() < tiny) d = tiny;
  d = 1 / d;
  var h = d;
  for (var m = 1; m <= 200; m++) {
    final m2 = 2 * m;
    var aa = m * (b - m) * x / ((qam + m2) * (a + m2));
    d = 1 + aa * d;
    if (d.abs() < tiny) d = tiny;
    c = 1 + aa / c;
    if (c.abs() < tiny) c = tiny;
    d = 1 / d;
    h *= d * c;
    aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2));
    d = 1 + aa * d;
    if (d.abs() < tiny) d = tiny;
    c = 1 + aa / c;
    if (c.abs() < tiny) c = tiny;
    d = 1 / d;
    final del = d * c;
    h *= del;
    if ((del - 1).abs() < 3e-14) break;
  }
  return h;
}

double _incBeta(double a, double b, double x) {
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  final bt = math.exp(_lgamma(a + b) - _lgamma(a) - _lgamma(b) + a * math.log(x) + b * math.log(1 - x));
  return x < (a + 1) / (a + b + 2) ? bt * _betacf(a, b, x) / a : 1 - bt * _betacf(b, a, 1 - x) / b;
}

// ---------- Κείμενα ----------

String linkSleepLabel(LinkSleep s) => switch (s) {
      LinkSleep.sleepHr => 'παλμοί ύπνου',
      LinkSleep.hrv => 'HRV',
      LinkSleep.sleepMin => 'διάρκεια ύπνου',
    };

String linkCauseLabel(LinkCause c) => switch (c) {
      LinkCause.mealGap => 'ώρες από το τελευταίο φαγητό',
      LinkCause.dinnerKcal => 'θερμίδες βραδινού',
      LinkCause.steps => 'βήματα της μέρας',
      LinkCause.bedtime => 'ώρα ύπνου',
    };

/// Το όριο των δύο μισών, στρογγυλεμένο όπως φαίνεται.
String _splitText(LinkCause c, double v) => switch (c) {
      LinkCause.mealGap => () {
          final h = (v * 2).round() / 2;
          return h == 1 ? '1 ώρα' : '${dec(h, (v * 2).round().isEven ? 0 : 1)} ώρες';
        }(),
      LinkCause.dinnerKcal => '${thousands(((v / 50).round() * 50).toDouble())} kcal',
      LinkCause.steps => '${thousands(((v / 500).round() * 500).toDouble())} βήματα',
      LinkCause.bedtime => clockFromSix(((v / 15).round() * 15).toDouble()),
    };

String _sleepValue(LinkSleep s, double v) => switch (s) {
      LinkSleep.sleepHr => '${dec(v, 0)} bpm',
      LinkSleep.hrv => '${dec(v, 0)} ms',
      LinkSleep.sleepMin => hoursMinutes(v.round()),
    };

/// Οι δύο ομάδες νυχτών, π.χ. «Τελευταίο φαγητό λιγότερο από 3 ώρες πριν τον ύπνο» / «3 ώρες και πάνω».
(String low, String high) linkGroups(SleepLink l) {
  final s = _splitText(l.cause, l.split);
  return switch (l.cause) {
    LinkCause.mealGap => ('Τελευταίο φαγητό ως $s πριν τον ύπνο', 'Πάνω από $s πριν τον ύπνο'),
    LinkCause.dinnerKcal => ('Βραδινό ως $s', 'Βραδινό πάνω από $s'),
    LinkCause.steps => ('Μέρες ως $s', 'Μέρες πάνω από $s'),
    LinkCause.bedtime => ('Ύπνος ως τις $s', 'Ύπνος μετά τις $s'),
  };
}

/// «παλμοί ύπνου 58 bpm · 61 bpm»
(String low, String high) linkValues(SleepLink l) => (_sleepValue(l.sleep, l.lowMean), _sleepValue(l.sleep, l.highMean));
