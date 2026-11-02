/// Πηγές δεδομένων: από ποια συσκευή έρχεται κάθε μέτρηση, σε ΕΝΑΝ πίνακα (απόφαση χρήστη 2/11).
///
/// Κανόνες (δεσμευτικοί):
/// - Μία πηγή για κάθε μέτρηση κάθε μέρα. Ποτέ «όποια υπάρχει», ποτέ εναλλακτική από άλλη συσκευή,
///   ποτέ μέσος όρος δύο συσκευών.
/// - Η «νύχτα» (ύπνος, παλμοί και HRV ύπνου, θερμοκρασία, βαθμολογίες) αλλάζει πηγή σε συγκεκριμένες
///   ημερομηνίες (εποχές): ρολόι ως τη σύνδεση του Oura, Oura από εκεί και πέρα. Οι υπόλοιπες έχουν πάντα μία.
/// - Κάθε τιμή αποθηκεύεται με κλειδί της πηγής της: του ρολογιού με το παλιό κλειδί (π.χ. «sleepMin»),
///   του Oura με πρόθεμα «o.» (π.χ. «o.sleepMin»). Οι υπολογισμοί διαβάζουν ΜΟΝΟ μέσω του [SourcePlan],
///   που για κάθε μέρα δίνει ένα μόνο κλειδί: η ανάμειξη δεν γίνεται ούτε κατά λάθος.
/// - Η οθόνη «Πηγές» φτιάχνεται από τον [sourceRows], ώστε να μη διαφωνεί ποτέ με τον κώδικα.
library;

import 'format.dart';
import 'history.dart';

/// Από πού έρχεται μια τιμή.
enum Source {
  /// Galaxy Watch Ultra 2, μέσω Samsung Health.
  watch,

  /// Ζυγαριά InBody H40, μέσω Samsung Health.
  scale,

  /// Oura Ring 5, κατευθείαν από την Oura.
  oura,

  /// Καμία: π.χ. μετά την αποσύνδεση του Oura, ώσπου να διαλέξεις ξανά. Οι νύχτες μένουν κενές.
  none,
}

/// Σύντομο όνομα για τις ετικέτες στις κάρτες.
String sourceName(Source s) => switch (s) {
      Source.watch => 'Ρολόι',
      Source.scale => 'InBody',
      Source.oura => 'Oura',
      Source.none => 'Καμία',
    };

/// Το όνομα της συσκευής.
String sourceDevice(Source s) => switch (s) {
      Source.watch => 'Galaxy Watch Ultra 2',
      Source.scale => 'InBody H40',
      Source.oura => 'Oura Ring 5',
      Source.none => 'Καμία συσκευή',
    };

String _sourceId(Source s) => switch (s) {
      Source.watch => 'watch',
      Source.scale => 'scale',
      Source.oura => 'oura',
      Source.none => 'none',
    };

Source? _sourceFromId(Object? id) => switch (id) {
      'watch' => Source.watch,
      'oura' => Source.oura,
      'none' => Source.none,
      _ => null,
    };

/// Ομάδες μετρήσεων με την ίδια πηγή.
enum SourceGroup {
  /// Αλλάζει πηγή στις εποχές (ρολόι → Oura).
  night,

  /// Πάντα από το ρολόι.
  watch,

  /// Πάντα από τη ζυγαριά.
  scale,
}

/// Μία γραμμή του πίνακα «Από πού παίρνουμε τι».
class SourceRow {
  const SourceRow({
    required this.title,
    required this.group,
    required this.metrics,
    required this.watchNote,
    this.ouraNote,
  });

  final String title;
  final SourceGroup group;

  /// Οι μετρήσεις (κλειδιά K.*) που καλύπτει. Κάθε μέτρηση βρίσκεται σε μία μόνο γραμμή.
  final List<String> metrics;

  /// Τι σημαίνει όταν η πηγή είναι το ρολόι (ή η ζυγαριά).
  final String watchNote;

  /// Τι σημαίνει όταν η πηγή είναι το Oura (μόνο για τη «νύχτα»).
  final String? ouraNote;

  /// Η εξήγηση για την πηγή [s].
  String noteFor(Source s) => switch (s) {
        Source.oura => ouraNote ?? watchNote,
        Source.none => 'Κενό, ώσπου να συνδέσεις ξανά το Oura ή να διαλέξεις το ρολόι',
        _ => watchNote,
      };
}

/// Ο ΕΝΑΣ πίνακας πηγών. Από αυτόν βγαίνουν οι υπολογισμοί και η οθόνη «Πηγές».
const sourceRows = <SourceRow>[
  SourceRow(
    title: 'Ύπνος, ώρες και φάσεις',
    group: SourceGroup.night,
    metrics: [K.sleepMin, K.bedtime, K.wake, K.deepPct, K.remPct, K.awakeMin, K.napMin],
    watchNote: 'Όπως τον μετρά η Samsung',
    ouraNote: 'Μόνο Oura· νύχτα χωρίς δαχτυλίδι μένει κενή',
  ),
  SourceRow(
    title: 'Παλμοί ύπνου, HRV, αναπνοές',
    group: SourceGroup.night,
    metrics: [K.sleepHr, K.lowHr, K.hrv, K.breath],
    watchNote: 'Μόνο παλμοί· η Samsung δεν δίνει HRV',
    ouraNote: 'Μόνο Oura· μέσοι όροι όλης της νύχτας',
  ),
  SourceRow(
    title: 'Θερμοκρασία στον ύπνο',
    group: SourceGroup.night,
    metrics: [K.skinTemp],
    watchNote: 'Θερμοκρασία καρπού',
    ouraNote: 'Μόνο Oura· απόκλιση από το συνηθισμένο σου',
  ),
  SourceRow(
    title: 'Βαθμολογία ύπνου, ετοιμότητα',
    group: SourceGroup.night,
    metrics: [K.sleepScore, K.energy],
    watchNote: 'Βαθμολογία και Energy Score της Samsung',
    ouraNote: 'Μόνο Oura· εκτίμηση, όχι μέτρηση',
  ),
  SourceRow(
    title: 'Οξυγόνο τη νύχτα',
    group: SourceGroup.watch,
    metrics: [K.spo2Avg, K.spo2Min, K.spo2Low],
    watchNote: 'Μόνο ρολόι· μέσο, χαμηλότερο, χρόνος κάτω από 90% (ενδεικτικό). Του δαχτυλιδιού δεν διαβάζεται',
  ),
  SourceRow(
    title: 'Βήματα, όροφοι, θερμίδες',
    group: SourceGroup.watch,
    metrics: [K.steps, K.floors, K.calories, K.activeMin],
    watchNote: 'Μόνο ρολόι· τα βήματα του δαχτυλιδιού δεν διαβάζονται',
  ),
  SourceRow(
    title: 'Παλμοί μέρας',
    group: SourceGroup.watch,
    metrics: [K.dayHr, K.restHr, K.walkHr],
    watchNote: 'Μόνο ρολόι',
  ),
  SourceRow(
    title: 'Βάρος, λίπος, μύες',
    group: SourceGroup.scale,
    metrics: [K.weight, K.fatPct, K.smm],
    watchNote: 'Μόνο InBody, μέσω Samsung Health',
  ),
];

/// Τι ΔΕΝ διαβάζεται ή δεν φαίνεται, ώστε να μην ανακατευτεί ποτέ (δείχνεται στην οθόνη «Πηγές» μετά τη σύνδεση).
const notUsedWithOura = <String>[
  'Βήματα του δαχτυλιδιού: δεν διαβάζονται',
  'Οξυγόνο του δαχτυλιδιού: δεν διαβάζεται',
  'Δείκτης διαταραχών αναπνοής του Oura: δεν φαίνεται (δεν είναι τεστ άπνοιας)',
  'Βαθμολογία ύπνου και Energy Score της Samsung: δεν φαίνονται',
  'Ύπνος του ρολογιού: μόνο στη «Σύγκριση πηγών», τις πρώτες $compareDays μέρες',
];

/// Σε ποια ομάδα ανήκει κάθε μέτρηση (από τον [sourceRows]).
final Map<String, SourceGroup> metricGroups = {
  for (final r in sourceRows)
    for (final m in r.metrics) m: r.group,
};

/// Κλειδιά αποθήκευσης των τιμών του Oura (ποτέ ίδια με του ρολογιού).
const ouraKeys = <String, String>{
  K.sleepMin: 'o.sleepMin',
  K.bedtime: 'o.bedtime',
  K.wake: 'o.wake',
  K.deepPct: 'o.deepPct',
  K.remPct: 'o.remPct',
  K.awakeMin: 'o.awakeMin',
  K.napMin: 'o.napMin',
  K.sleepHr: 'o.sleepHr',
  K.lowHr: 'o.lowHr',
  K.hrv: 'o.hrv',
  K.breath: 'o.breath',
  K.skinTemp: 'o.skinTemp',
  K.sleepScore: 'o.sleepScore',
  K.energy: 'o.readiness',
};

/// Όλα τα κλειδιά αποθήκευσης του Oura.
final Set<String> ouraKeySet = ouraKeys.values.toSet();

/// Μετρήσεις που δίνει μόνο το Oura: με το ρολόι ως πηγή δεν έχουν τιμή (όχι «0», απλώς κενό).
const ouraOnlyMetrics = {K.lowHr, K.hrv, K.breath, K.napMin};

/// Τιμές της «νύχτας» από το ρολόι, όπως αποθηκεύονται (χωρίς το οξυγόνο, που είναι πάντα του ρολογιού).
const watchNightKeys = {
  K.sleepMin, K.sleepScore, K.deepPct, K.remPct, K.awakeMin, K.bedtime, K.wake, K.sleepHr, K.skinTemp, K.energy,
};

/// Πόσες μέρες μετά τη σύνδεση φαίνεται η «Σύγκριση πηγών» (και διαβάζεται ο ύπνος του ρολογιού γι' αυτήν).
const compareDays = 14;

/// Από μια μέρα και μετά, η «νύχτα» έρχεται από την [source].
class SourceEra {
  const SourceEra(this.source, this.from);
  final Source source;

  /// Η πρώτη νύχτα (με ημερομηνία το πρωί) που ανήκει σε αυτή την πηγή.
  final DateTime from;

  Map<String, String> toJson() => {'src': _sourceId(source), 'from': dateKey(from)};

  @override
  bool operator ==(Object other) => other is SourceEra && other.source == source && sameDay(other.from, from);

  @override
  int get hashCode => Object.hash(source, dateKey(from));
}

/// Το σχέδιο πηγών: για κάθε μέτρηση και μέρα, ΜΙΑ πηγή και ΕΝΑ κλειδί αποθήκευσης.
class SourcePlan {
  SourcePlan(List<SourceEra> eras) : eras = List.unmodifiable([...eras]..sort((a, b) => a.from.compareTo(b.from)));

  /// Πριν από οποιαδήποτε σύνδεση: όλα όπως πάντα (ρολόι και ζυγαριά).
  static final samsungOnly = SourcePlan(const []);

  /// Αλλαγές πηγής της «νύχτας», παλιότερη πρώτη. Πριν από την πρώτη: ρολόι.
  final List<SourceEra> eras;

  factory SourcePlan.fromJson(Object? j) {
    if (j is! List) return samsungOnly;
    final out = <SourceEra>[];
    for (final e in j) {
      if (e is! Map) continue;
      final s = _sourceFromId(e['src']);
      final f = e['from'];
      if (s == null || f is! String) continue;
      try {
        out.add(SourceEra(s, parseDateKey(f)));
      } catch (_) {}
    }
    return out.isEmpty ? samsungOnly : SourcePlan(out);
  }

  List<Map<String, String>> toJson() => [for (final e in eras) e.toJson()];

  /// Η πηγή της «νύχτας» με ημερομηνία (πρωινό) [day].
  Source nightSource(DateTime day) {
    final d = dayOf(day);
    var s = Source.watch;
    for (final e in eras) {
      if (!e.from.isAfter(d)) s = e.source;
    }
    return s;
  }

  /// Έχει συνδεθεί ποτέ το Oura.
  bool get hasOura => eras.any((e) => e.source == Source.oura);

  /// Η αρχή της τελευταίας εποχής Oura (η τελευταία σύνδεση).
  DateTime? get ouraFrom {
    DateTime? f;
    for (final e in eras) {
      if (e.source == Source.oura) f = e.from;
    }
    return f;
  }

  /// Η πηγή της μέτρησης [metric] τη μέρα [day].
  Source sourceFor(String metric, DateTime day) => switch (metricGroups[metric]) {
        SourceGroup.night => nightSource(day),
        SourceGroup.scale => Source.scale,
        _ => Source.watch,
      };

  /// Το κλειδί αποθήκευσης για τη μέτρηση [metric] από την πηγή [s] (null = η πηγή δεν τη δίνει).
  static String? storageKey(String metric, Source s) {
    final g = metricGroups[metric];
    return switch (s) {
      Source.oura => g == SourceGroup.night ? ouraKeys[metric] : null,
      Source.watch =>
        g == null || g == SourceGroup.watch || (g == SourceGroup.night && !ouraOnlyMetrics.contains(metric)) ? metric : null,
      Source.scale => g == SourceGroup.scale ? metric : null,
      Source.none => null,
    };
  }

  /// Το ΕΝΑ κλειδί που διαβάζεται για τη μέτρηση [metric] τη μέρα [day].
  String? keyFor(String metric, DateTime day) => storageKey(metric, sourceFor(metric, day));

  /// Η τιμή της μέτρησης [metric] τη μέρα [day], μόνο από την πηγή της.
  double? value(Map<String, Map<String, double>> history, String metric, DateTime day) {
    final k = keyFor(metric, day);
    return k == null ? null : history[dateKey(day)]?[k];
  }

  /// Οι μέρες που η μέτρηση [metric] αλλάζει πηγή (η πρώτη μέρα της νέας πηγής), παλιότερη πρώτη.
  /// Μετρούν μόνο οι πηγές που ΔΙΝΟΥΝ τη μέτρηση: μια εποχή χωρίς τιμή (π.χ. «καμία», ή το ρολόι για το HRV)
  /// δεν είναι αλλαγή η ίδια, αλλά ρολόι → [κενό] → Oura είναι αλλαγή στην αρχή του Oura. Έτσι:
  /// - HRV/αναπνοές/χαμηλότεροι παλμοί (μόνο Oura) δεν έχουν ποτέ «αλλαγή πηγής»· απλώς λίγα δεδομένα στην αρχή.
  /// - Ύπνος: ρολόι → Oura → καμία → ρολόι έχει αλλαγές στην αρχή του Oura και στην αρχή του ρολογιού.
  List<DateTime> changeDates(String metric) {
    if (metricGroups[metric] != SourceGroup.night) return const [];
    final out = <DateTime>[];
    Source? prev = storageKey(metric, Source.watch) != null ? Source.watch : null;
    for (final e in eras) {
      if (storageKey(metric, e.source) == null) continue;
      if (prev != null && e.source != prev) out.add(e.from);
      prev = e.source;
    }
    return out;
  }

  /// Η πρώτη μέρα του κομματιού με την ίδια πηγή που περιέχει το [day] (null = από πάντα).
  DateTime? segmentStart(String metric, DateTime day) {
    final d = dayOf(day);
    DateTime? start;
    for (final c in changeDates(metric)) {
      if (!c.isAfter(d)) start = c;
    }
    return start;
  }

  /// Η πρώτη αλλαγή πηγής μέσα στο (after, until]: αν υπάρχει, ένα διάστημα από after ως until
  /// έχει τιμές από δύο πηγές και δεν συγκρίνεται.
  DateTime? changeWithin(String metric, DateTime after, DateTime until) {
    final a = dayOf(after);
    final b = dayOf(until);
    for (final c in changeDates(metric)) {
      if (c.isAfter(a) && !c.isAfter(b)) return c;
    }
    return null;
  }

  /// Η τελευταία νύχτα της «Σύγκρισης πηγών»: ακριβώς [compareDays] νύχτες από την αρχή του (τελευταίου) Oura.
  DateTime? get compareUntil {
    final f = ouraFrom;
    return f == null ? null : DateTime(f.year, f.month, f.day + compareDays - 1);
  }

  /// Αν φαίνεται σήμερα η «Σύγκριση πηγών»: μόνο όσο ο ύπνος είναι του Oura (όχι μετά από αποσύνδεση
  /// ή «ξανά από το ρολόι»), και μόνο τις [compareDays] πρώτες νύχτες.
  bool compareActive(DateTime today) {
    final f = ouraFrom;
    final u = compareUntil;
    if (f == null || u == null) return false;
    final d = dayOf(today);
    return nightSource(d) == Source.oura && !d.isBefore(f) && !d.isAfter(u);
  }

  /// Αν επιτρέπεται σήμερα ([today]) να διαβαστεί ο ύπνος του ρολογιού για τη νύχτα [day]: όταν το ρολόι
  /// είναι η πηγή της, ή για τη «Σύγκριση πηγών» όσο αυτή είναι ανοιχτή.
  bool watchSleepAllowed(DateTime day, DateTime today) {
    final d = dayOf(day);
    if (nightSource(d) == Source.watch) return true;
    if (!compareActive(today)) return false;
    final f = ouraFrom!;
    return !d.isBefore(f) && !d.isAfter(compareUntil!) && nightSource(d) == Source.oura;
  }

  /// Ως ποια νύχτα (μαζί) διαβάζεται σήμερα ([today]) ο ύπνος του ρολογιού από τη Samsung. null = χωρίς όριο.
  /// - Τελευταία εποχή ρολόι: χωρίς όριο.
  /// - Αλλιώς η τελευταία νύχτα του ρολογιού, ή όσο η σύγκριση είναι ανοιχτή η τελευταία νύχτα της.
  ///   Μόλις κλείσει η σύγκριση, το όριο πέφτει πάλι στην τελευταία νύχτα του ρολογιού: δεν ξαναδιαβάζεται
  ///   ύπνος ρολογιού για νύχτες του Oura (ούτε στην ανάγνωση των 30 ημερών).
  DateTime? watchSleepCutoff(DateTime today) {
    if (eras.isEmpty || eras.last.source == Source.watch) return null;
    DateTime? best;
    for (var i = -1; i < eras.length - 1; i++) {
      final source = i < 0 ? Source.watch : eras[i].source;
      if (source != Source.watch) continue;
      final next = eras[i + 1].from;
      final lastOfEra = DateTime(next.year, next.month, next.day - 1);
      if (best == null || lastOfEra.isAfter(best)) best = lastOfEra;
    }
    if (compareActive(today)) {
      final u = compareUntil!;
      if (best == null || u.isAfter(best)) best = u;
    }
    return best;
  }

  /// Νέο σχέδιο όπου από τη μέρα [from] και μετά η «νύχτα» έρχεται από την [source].
  /// Ό,τι είχε προγραμματιστεί από [from] και μετά φεύγει· αν η πηγή είναι ήδη αυτή, δεν μπαίνει νέα εποχή.
  SourcePlan withEra(Source source, DateTime from) {
    final f = dayOf(from);
    final kept = [for (final e in eras) if (e.from.isBefore(f)) e];
    final before = SourcePlan(kept).nightSource(DateTime(f.year, f.month, f.day - 1));
    if (before == source) return SourcePlan(kept);
    return SourcePlan([...kept, SourceEra(source, f)]);
  }

  @override
  bool operator ==(Object other) {
    if (other is! SourcePlan || other.eras.length != eras.length) return false;
    for (var i = 0; i < eras.length; i++) {
      if (other.eras[i] != eras[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(eras);
}

/// Ώρες ύπνου από την πηγή του ύπνου (Oura), ΜΟΝΟ ως χρονικά παράθυρα: για να μη μετρούν ως «μέρα»
/// οι παλμοί του ρολογιού όσο κοιμάσαι. Δεν δίνουν καμία τιμή σε καμία μέτρηση.
class SleepWindows {
  const SleepWindows(this.ranges, this.mains);

  /// Όλες οι περίοδοι ύπνου (νύχτες και υπνάκοι).
  final List<(DateTime, DateTime)> ranges;

  /// Η κύρια νύχτα κάθε μέρας (πρωινό, «2026-11-06») → από πότε ως πότε.
  final Map<String, (DateTime, DateTime)> mains;

  /// Οι μέρες που έχουν κύρια νύχτα.
  Iterable<String> get nights => mains.keys;

  static const empty = SleepWindows([], {});
}

/// Οι τιμές της μέτρησης [metric] στο [from, to], ΜΟΝΟ από την πηγή της τελευταίας μέρας: αν η πηγή άλλαξε
/// μέσα στο διάστημα, κρατιούνται μόνο οι μέρες μετά την αλλαγή (ποτέ δύο πηγές στο ίδιο γράφημα).
/// Επιστρέφει και την αλλαγή, αν έκοψε το διάστημα.
({List<(DateTime, double)> points, Source source, DateTime? cut}) planSeries(
  Map<String, Map<String, double>> history,
  SourcePlan plan,
  String metric,
  DateTime from,
  DateTime to,
) {
  final end = dayOf(to);
  final seg = plan.segmentStart(metric, end);
  final cut = seg != null && seg.isAfter(dayOf(from)) ? seg : null;
  final start = cut ?? dayOf(from);
  final out = <(DateTime, double)>[];
  for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
    final v = plan.value(history, metric, d);
    if (v != null) out.add((d, v));
  }
  return (points: out, source: plan.sourceFor(metric, end), cut: cut);
}
