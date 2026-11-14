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

import 'oxygen_note.dart' show oxygenAvgLabel, oxygenMinLabel;
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
    this.needsNight = false,
  });

  /// Round 1 (U2b-07, f5): μέτρηση του ρολογιού που βγαίνει ΜΟΝΟ μέσα στις ώρες ύπνου (οξυγόνο της νύχτας). Όταν ο ύπνος
  /// δεν έχει πηγή («Καμία», π.χ. μετά την αποσύνδεση του Oura) δεν βγαίνει καθόλου, όσο κι αν φοράς το ρολόι: η οθόνη
  /// «Πηγές» το δείχνει ως «Καμία», όχι «Ρολόι».
  final bool needsNight;

  final String title;
  final SourceGroup group;

  /// Οι μετρήσεις (κλειδιά K.*) που καλύπτει. Κάθε μέτρηση βρίσκεται σε μία μόνο γραμμή.
  final List<String> metrics;

  /// Τι σημαίνει όταν η πηγή είναι το ρολόι (ή η ζυγαριά).
  final String watchNote;

  /// Τι σημαίνει όταν η πηγή είναι το Oura (μόνο για τη «νύχτα»).
  final String? ouraNote;

  /// Η εξήγηση για την πηγή [s]. [unknown] (round 1, U2b-05, f5): το σχέδιο πηγών δεν διαβάστηκε· τότε το ζητούμενο
  /// είναι η κάρτα στην κορυφή των Πηγών, όχι «σύνδεσε ξανά το Oura» (που μπορεί να γράφει «Συνδεδεμένο»).
  String noteFor(Source s, {bool unknown = false}) => switch (s) {
        Source.oura => ouraNote ?? watchNote,
        Source.none => needsNight
            ? 'Κενό όσο ο ύπνος δεν έχει πηγή: το ρολόι μετρά το οξυγόνο της νύχτας μόνο μέσα στις ώρες ύπνου'
            : unknown
                ? 'Κενό, ώσπου να οριστεί η πηγή του ύπνου (δες την κάρτα πάνω)'
                : 'Κενό, ώσπου να συνδέσεις ξανά το Oura ή να διαλέξεις το ρολόι',
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
    title: 'Θερμοκρασία δέρματος',
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
    title: oxygenAvgLabel,
    group: SourceGroup.night,
    metrics: [K.ringSpo2],
    watchNote: 'Με το ρολόι ως πηγή ύπνου: ο μέσος όρος του ρολογιού (από κάτω)',
    ouraNote: 'Μόνο Oura· όλης της νύχτας',
  ),
  SourceRow(
    title: oxygenMinLabel,
    group: SourceGroup.watch,
    metrics: [K.spo2Avg, K.spo2Min, K.spo2Low, K.spo2Cov],
    watchNote: 'Μόνο ρολόι· με το Oura, όταν το ρολόι μέτρησε τουλάχιστον τον μισό ύπνο',
    needsNight: true,
  ),
  SourceRow(
    title: 'Βήματα, όροφοι, θερμίδες',
    group: SourceGroup.watch,
    metrics: [K.steps, K.floors, K.calories, K.activeMin],
    // Το σύνολο της Samsung, όπως στον κώδικα (DashboardReader: StepsType.TOTAL κ.λπ.): ρολόι ΚΑΙ κινητό (A2).
    // Round 1 (U2b-15, f5): χωρίς «τα βήματα του δαχτυλιδιού δεν διαβάζονται» (το λέει ήδη το «Τι δεν χρησιμοποιούμε»,
    // και πριν από το Oura δεν έχει νόημα)· η γραμμή στρίμωχνε τον πίνακα.
    watchNote: samsungTotalLabel,
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

/// Βήματα, όροφοι, θερμίδες, ενεργός χρόνος: το σύνολο της Samsung Health, που ενώνει ρολόι και κινητό χωρίς να μετρά
/// δύο φορές (έλεγχος 4/11, A2). ΔΕΝ είναι «μόνο ρολόι»: η ετικέτα το λέει παντού (Πηγές, κάρτες, αναφορά).
const samsungTotalMetrics = {K.steps, K.floors, K.calories, K.activeMin};
const samsungTotalLabel = 'Samsung Health (ρολόι και κινητό, χωρίς διπλομέτρηση)';

/// Το σύντομο όνομα της πηγής μιας μέτρησης για ετικέτες: «Samsung Health» για τα σύνολα της Samsung.
String metricSourceName(String metric, Source s) => samsungTotalMetrics.contains(metric) ? 'Samsung Health' : sourceName(s);

/// Τι ΔΕΝ διαβάζεται ή δεν φαίνεται, ώστε να μην ανακατευτεί ποτέ (δείχνεται στην οθόνη «Πηγές» μετά τη σύνδεση).
const notUsedWithOura = <String>[
  'Βήματα του δαχτυλιδιού: δεν διαβάζονται',
  // Round 1 (U2b-04 / S4-8, f5): ο μέσος όρος του ρολογιού ΦΑΙΝΕΤΑΙ στις Τάσεις («… μέσος όρος (ρολόι)») και στην αναφορά
  // για γιατρό («από το ρολόι»)· πριν το κείμενο έλεγε «δεν φαίνεται». Αν κάποτε βγει από εκεί, αλλάζει και αυτή η γραμμή.
  'Μέσος όρος οξυγόνου του ρολογιού: στις κάρτες δεν φαίνεται (εκεί ο μέσος όρος είναι του Oura και η χαμηλότερη τιμή του '
      'ρολογιού)· φαίνεται μόνο στις Τάσεις και στην αναφορά για γιατρό, με ετικέτα «ρολόι»',
  'Δείκτης διαταραχών αναπνοής του Oura: δεν φαίνεται (δεν είναι τεστ άπνοιας)',
  'Βαθμολογία ύπνου και Energy Score της Samsung: δεν φαίνονται',
  'Ύπνος του ρολογιού: δεν διαβάζεται',
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
  K.napLock: 'o.napLock',
  K.sleepHr: 'o.sleepHr',
  K.lowHr: 'o.lowHr',
  K.hrv: 'o.hrv',
  K.breath: 'o.breath',
  K.skinTemp: 'o.skinTemp',
  K.sleepScore: 'o.sleepScore',
  K.energy: 'o.readiness',
  K.ringSpo2: 'o.spo2',
};

/// Το κλειδί του μέσου οξυγόνου του Oura (έρχεται χωριστά, με την άδεια spo2).
const ouraSpo2Key = 'o.spo2';

/// Όλα τα κλειδιά αποθήκευσης του Oura.
final Set<String> ouraKeySet = ouraKeys.values.toSet();

/// Μετρήσεις που δίνει μόνο το Oura: με το ρολόι ως πηγή δεν έχουν τιμή (όχι «0», απλώς κενό).
const ouraOnlyMetrics = {K.lowHr, K.hrv, K.breath, K.ringSpo2};

/// Μετρήσεις του ρολογιού που αλλάζουν ΟΡΙΣΜΟ όταν η νύχτα έρχεται από το Oura (έλεγχος 4/11, A4):
/// - οξυγόνο: πριν, οι μετρήσεις μέσα στον ύπνο του ρολογιού· μετά, μέσα στις ώρες ύπνου του Oura,
/// - παλμοί μέρας: εξαιρείται ο ύπνος του ρολογιού ή οι ώρες ύπνου του Oura.
/// Η τιμή μένει πάντα του ρολογιού, αλλά δεν συγκρίνεται πάνω από την αλλαγή ([SourcePlan.changeDates]).
const definitionMetrics = {K.spo2Avg, K.spo2Min, K.spo2Low, K.dayHr, K.restHr, K.walkHr};

/// Τιμές που αλλάζουν όταν αλλάζουν οι κανόνες του ιστορικού (historyRulesVersion): ό,τι βγαίνει από την ομαδοποίηση
/// του ύπνου και το οξυγόνο της νύχτας. Όσο ξαναϋπολογίζονται, δεν συγκρίνονται πάνω από το όριο ([SourcePlan.rulesFrom]).
const rulesMetrics = {
  K.sleepMin, K.deepPct, K.remPct, K.awakeMin, K.bedtime, K.wake, K.napMin, K.sleepHr, K.skinTemp, K.sleepScore,
  K.spo2Avg, K.spo2Min, K.spo2Low,
};

/// Τιμές της «νύχτας» από το ρολόι, όπως αποθηκεύονται (χωρίς το οξυγόνο, που είναι πάντα του ρολογιού).
const watchNightKeys = {
  K.sleepMin, K.sleepScore, K.deepPct, K.remPct, K.awakeMin, K.bedtime, K.wake, K.sleepHr, K.skinTemp, K.energy, K.napMin,
  K.napLock,
};

/// Πόσες μέρες μετά τη σύνδεση θα φαινόταν η «Σύγκριση πηγών».
const compareDays = 14;

/// Απόφαση χρήστη 7/11: το ρολόι βγαίνει εντελώς από τον ύπνο. Η «Σύγκριση πηγών» δεν ανοίγει ποτέ και ο ύπνος του
/// ρολογιού δεν διαβάζεται για νύχτες του Oura. (Ο κώδικας της σύγκρισης μένει, κλειστός.)
const compareOpen = false;

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
  SourcePlan(List<SourceEra> eras, {this.rulesFrom, this.scaleFrom})
      : eras = List.unmodifiable([...eras]..sort((a, b) => a.from.compareTo(b.from)));

  /// Έλεγχος 3, E2: η πρώτη μέρα με ζύγιση InBody, όταν το ιστορικό έχει και ζυγίσεις χωρίς σημάδι InBody (παλιές
  /// εκδόσεις, ίσως άλλη εφαρμογή· [scaleFromOf]). Από αυτήν και μετά φαίνονται μόνο ζυγίσεις της InBody ([value])·
  /// πριν από αυτήν οι παλιές μένουν και φαίνονται (με την πηγή τους). Είναι αλλαγή πηγής για βάρος/λίπος/μύες
  /// ([changeDates]). ΔΕΝ αποθηκεύεται και δεν μετρά στην ισότητα (βγαίνει από το ιστορικό). null = κανένα φίλτρο.
  final DateTime? scaleFrom;

  /// Το ίδιο σχέδιο με όριο ζυγαριάς [from] (E2).
  SourcePlan withScaleFrom(DateTime? from) =>
      SourcePlan(eras, rulesFrom: rulesFrom, scaleFrom: from == null ? null : dayOf(from));

  /// Αν η τιμή ζύγισης της μέρας [day] είναι παλιά, χωρίς σημάδι InBody (E2: πριν από το [scaleFrom] φαίνεται με την
  /// πηγή της· μετά δεν φαίνεται).
  static bool isOtherWeighIn(Map<String, Map<String, double>> history, DateTime day) {
    final r = history[dateKey(day)];
    return r != null && r[K.inbody] == null && r.keys.any(bodyKeys.contains);
  }

  /// Έλεγχος 2, C4: όσο το ιστορικό ξαναϋπολογίζεται με νέους κανόνες, οι μέρες πριν από αυτή την ημερομηνία έχουν
  /// ακόμα τον παλιό ορισμό των τιμών ύπνου ([rulesMetrics]). Για τις Τάσεις, την αναφορά και το «εκτός συνηθισμένου»
  /// είναι αλλαγή ορισμού ([changeDates]): καμία σύγκριση πάνω από αυτήν. ΔΕΝ αποθηκεύεται και δεν μετρά στην
  /// ισότητα (είναι πρόοδος της επανανάγνωσης, όχι μέρος του σχεδίου πηγών).
  final DateTime? rulesFrom;

  /// Το ίδιο σχέδιο με όριο επανανάγνωσης [from] (null = χωρίς).
  SourcePlan withRulesFrom(DateTime? from) =>
      SourcePlan(eras, rulesFrom: from == null ? null : dayOf(from), scaleFrom: scaleFrom);

  /// Αν η αλλαγή της μέρας [d] είναι το όριο της επανανάγνωσης («Ενημερώνεται το ιστορικό»), όχι αλλαγή πηγής.
  bool isRulesChange(DateTime? d) => d != null && rulesFrom != null && sameDay(d, rulesFrom!);

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
    if (k == null) return null;
    final row = history[dateKey(day)];
    // E2: από την πρώτη ζύγιση InBody και μετά, μόνο ζυγίσεις της InBody (οι άλλες μένουν αποθηκευμένες, κρυφές).
    final s = scaleFrom;
    if (s != null && row != null && row[K.inbody] == null && metricGroups[metric] == SourceGroup.scale && !dayOf(day).isBefore(s)) {
      return null;
    }
    return row?[k];
  }

  /// Οι μέρες που η μέτρηση [metric] αλλάζει πηγή ή ορισμό (η πρώτη μέρα της νέας εποχής), παλιότερη πρώτη.
  /// Καμία σύγκριση, γράφημα ή «συνηθισμένο» δεν περνά πάνω από αυτές (έλεγχος 4/11, A5).
  /// - Κάθε εποχή που ΔΙΝΕΙ τιμή, μετά από οποιαδήποτε προηγούμενη περίοδο με τιμές, είναι αλλαγή: και
  ///   Oura → καμία → Oura (ίσως άλλο δαχτυλίδι ή λογαριασμός, νέα «βάση»). Μια εποχή χωρίς τιμή (π.χ. «καμία»,
  ///   ή το ρολόι για το HRV) δεν είναι αλλαγή η ίδια.
  /// - HRV/αναπνοές/χαμηλότεροι παλμοί (μόνο Oura): η πρώτη σύνδεση δεν είναι αλλαγή (απλώς αρχίζουν τιμές)·
  ///   κάθε επόμενη εποχή Oura είναι.
  /// - Οξυγόνο νύχτας και παλμοί μέρας ([definitionMetrics]): μένουν του ρολογιού, αλλά ο ορισμός τους αλλάζει
  ///   όταν η νύχτα περνά από το ρολόι στο Oura και πίσω (A4)· «καμία» δεν δίνει τιμή.
  List<DateTime> changeDates(String metric) {
    // E2: η πρώτη ζύγιση InBody, όταν πριν υπάρχουν ζυγίσεις άλλης πηγής: καμία σύγκριση πάνω από αυτήν.
    final s = scaleFrom;
    if (metricGroups[metric] == SourceGroup.scale) return s == null ? const [] : [s];
    final eraChanges = _eraChangeDates(metric);
    final r = rulesFrom;
    if (r == null || !rulesMetrics.contains(metric) || eraChanges.any((d) => sameDay(d, r))) return eraChanges;
    return [...eraChanges, r]..sort();
  }

  List<DateTime> _eraChangeDates(String metric) {
    final night = metricGroups[metric] == SourceGroup.night;
    final definition = definitionMetrics.contains(metric);
    if (!night && !definition) return const [];
    bool gives(Source s) => night ? storageKey(metric, s) != null : (s == Source.watch || s == Source.oura);
    final out = <DateTime>[];
    // Πριν από την πρώτη εποχή η νύχτα είναι του ρολογιού.
    var hadValues = gives(Source.watch);
    Source prev = Source.watch;
    for (final e in eras) {
      if (!gives(e.source)) {
        prev = e.source;
        continue;
      }
      // Ορισμός: αλλάζει μόνο όταν αλλάζει το «ρολόι ή Oura» της νύχτας (ή μετά από κενό «καμία»).
      final same = definition && e.source == prev;
      if (hadValues && !same) out.add(e.from);
      hadValues = true;
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

  /// Η πρώτη νύχτα μιας εποχής Oura: αν το ρολόι είχε ήδη γράψει νύχτα εκείνη τη μέρα (σύνδεση το πρωί με
  /// «μετρά από το δαχτυλίδι»), οι τιμές του μένουν στο ιστορικό — κρυφές, μόνο για τη «Σύγκριση πηγών» και
  /// για την αναίρεση «Η τελευταία νύχτα από το ρολόι». Ποτέ δεν σβήνονται.
  bool keepsWatchNight(DateTime day) =>
      eras.any((e) => e.source == Source.oura && e.from.year == day.year && e.from.month == day.month && e.from.day == day.day);

  /// Η τελευταία νύχτα της «Σύγκρισης πηγών»: ακριβώς [compareDays] νύχτες από την αρχή του (τελευταίου) Oura.
  DateTime? get compareUntil {
    final f = ouraFrom;
    return f == null ? null : DateTime(f.year, f.month, f.day + compareDays - 1);
  }

  /// Αν φαίνεται σήμερα η «Σύγκριση πηγών»: μόνο όσο ο ύπνος είναι του Oura (όχι μετά από αποσύνδεση
  /// ή «ξανά από το ρολόι»), και μόνο τις [compareDays] πρώτες νύχτες.
  bool compareActive(DateTime today) {
    if (!compareOpen) return false;
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
    if (before == source) return SourcePlan(kept, rulesFrom: rulesFrom, scaleFrom: scaleFrom);
    return SourcePlan([...kept, SourceEra(source, f)], rulesFrom: rulesFrom, scaleFrom: scaleFrom);
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

/// Round 1 (S9-7): επαναφορά αντιγράφου σε κινητό που έχει ήδη ΝΕΟΤΕΡΟ σχέδιο πηγών (π.χ. νέο κινητό: πρώτα «Σύνδεση με
/// Oura», μετά «Επαναφορά από αντίγραφο»). Αν ΟΛΕΣ οι εποχές του κινητού ([phone]) αρχίζουν μετά την τελευταία εποχή του
/// αντιγράφου ([backup]), το κινητό δεν λέει τίποτα για το παρελθόν: το παρελθόν έρχεται από το αντίγραφο και το παρόν
/// μένει του κινητού. Πριν, το σχέδιο του αντιγράφου απορριπτόταν ολόκληρο και μήνες νυχτών του Oura γίνονταν νύχτες
/// του ρολογιού. Εποχή του κινητού με την ίδια πηγή που ισχύει ήδη από το αντίγραφο δεν γίνεται νέα εποχή (δεν είναι
/// αλλαγή πηγής: το ίδιο δαχτυλίδι συνεχίζει). null = δεν ενώνονται (το κινητό έχει εποχή μέσα στο παρελθόν του
/// αντιγράφου, ή κάποιο από τα δύο δεν έχει εποχές): τότε μένει το σχέδιο του κινητού, όπως πριν.
SourcePlan? planWithPast(SourcePlan phone, SourcePlan backup) {
  if (phone.eras.isEmpty || backup.eras.isEmpty) return null;
  if (!phone.eras.first.from.isAfter(backup.eras.last.from)) return null;
  var out = SourcePlan(backup.eras);
  for (final e in phone.eras) {
    out = out.withEra(e.source, e.from);
  }
  return out;
}

/// Ώρες ύπνου από την πηγή του ύπνου (Oura), ΜΟΝΟ ως χρονικά παράθυρα: για να μη μετρούν ως «μέρα»
/// οι παλμοί του ρολογιού όσο κοιμάσαι. Δεν δίνουν καμία τιμή σε καμία μέτρηση.
class SleepWindows {
  const SleepWindows(this.ranges, this.mains, [this.pieces = const {}]);

  /// Όλες οι περίοδοι ύπνου (νύχτες και υπνάκοι).
  final List<(DateTime, DateTime)> ranges;

  /// Η κύρια νύχτα κάθε μέρας (πρωινό, «2026-11-06») → από πότε ως πότε.
  final Map<String, (DateTime, DateTime)> mains;

  /// Έλεγχος 3, S5: νύχτα σε κομμάτια → ΟΛΑ τα κομμάτια που μετρούν ως η νύχτα (κύριο + κομμάτια, όχι τα κενά),
  /// ενωμένα και με χρονολογική σειρά. Χωρίς εγγραφή εδώ: μόνο η [mains].
  final Map<String, List<(DateTime, DateTime)>> pieces;

  /// Οι μέρες που έχουν κύρια νύχτα.
  Iterable<String> get nights => mains.keys;

  /// Οι ώρες της νύχτας [day] («2026-11-06») που μετρούν: η ένωση των κομματιών της, χωρίς τα κενά ανάμεσα·
  /// χωρίς κομμάτια, η κύρια περίοδος· κενό αν η μέρα δεν έχει νύχτα.
  List<(DateTime, DateTime)> nightPieces(String day) {
    final main = mains[day];
    if (main == null) return const [];
    final p = pieces[day];
    return p == null || p.isEmpty ? [main] : p;
  }

  static const empty = SleepWindows([], {});
}

/// Η ένωση χρονικών διαστημάτων: όσα επικαλύπτονται ή αγγίζονται γίνονται ένα, με χρονολογική σειρά. Τα κενά ανάμεσα
/// μένουν έξω.
List<(DateTime, DateTime)> unionOfRanges(Iterable<(DateTime, DateTime)> ranges) {
  final sorted = [for (final r in ranges) if (!r.$2.isBefore(r.$1)) r]..sort((a, b) => a.$1.compareTo(b.$1));
  final out = <(DateTime, DateTime)>[];
  for (final r in sorted) {
    if (out.isNotEmpty && !r.$1.isAfter(out.last.$2)) {
      if (r.$2.isAfter(out.last.$2)) out[out.length - 1] = (out.last.$1, r.$2);
    } else {
      out.add(r);
    }
  }
  return out;
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
