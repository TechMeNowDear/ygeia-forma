/// Υπολογισμοί για τις οθόνες του Oura (χωρίς Flutter, για να ελέγχονται).
///
/// Κανόνες εμφάνισης (απόφαση 2/11, έγγραφο › «Ακρίβεια Oura / Galaxy Watch»):
/// - Φάσεις ύπνου μόνο ως μέσοι όροι 7 νυχτών, ποτέ λεπτά μίας νύχτας ως γεγονός.
/// - Ο χρόνος ξύπνιος με «τουλάχιστον» (οι συσκευές τον υποεκτιμούν).
/// - HRV και αναπνοές ως μέσοι όροι όλης της νύχτας, σε σύγκριση ΜΟΝΟ με τις δικές σου 14 τελευταίες
///   νύχτες από το Oura (όχι με νύχτες του ρολογιού, όχι με «νόρμες»).
library;

import '../format.dart';
import '../history.dart';
import '../sources.dart';
import '../trends.dart' show usualMinNights, usualNights, usualOf;
import 'config.dart';
import 'oura_model.dart';

/// Ελάχιστες νύχτες για μέσο όρο ή «συνηθισμένο».
const minNightsForAverage = 4;
// Ίδιοι κανόνες «συνηθισμένου» με το ρολόι (trends.dart › usualOf: μεσαία τιμή έως 14 νυχτών, τουλάχιστον 7).
const minNightsForBaseline = usualMinNights;
const baselineNights = usualNights;

/// Round 8 (R8-U4-1): «από 5 νύχτες» κάτω από τον τίτλο «Φάσεις · μέσος όρος 7 νυχτών» (ρολόι και Oura), όταν ο μέσος όρος
/// δεν βγαίνει και από τις 7 νύχτες· null με 7.
String? stagesFromText(int nights) => nights >= 7 ? null : 'από ${countText(nights, 'νύχτα', 'νύχτες')}';

/// Η τιμή μιας νύχτας μπροστά στο συνηθισμένο σου (μεσαία τιμή των προηγούμενων 14 νυχτών Oura, [usualOf]).
class NightBaseline {
  const NightBaseline(this.value, this.usual, this.count);
  final double value;
  final double? usual;

  /// Πόσες νύχτες έχει το «συνηθισμένο».
  final int count;
  double? get diff => usual == null ? null : value - usual!;
}

/// Η τιμή της μέτρησης [metric] τη νύχτα [day] (μόνο Oura) και το συνηθισμένο από τις 14 προηγούμενες νύχτες
/// με πηγή Oura (μετά την τελευταία αλλαγή πηγής). Χωρίς αρκετές νύχτες: χωρίς «συνηθισμένο».
NightBaseline? ouraBaseline(Map<String, Map<String, double>> history, SourcePlan plan, String metric, DateTime day) {
  if (plan.sourceFor(metric, day) != Source.oura) return null;
  final v = plan.value(history, metric, day);
  if (v == null) return null;
  final seg = plan.segmentStart(metric, day);
  final prev = <double>[];
  for (var i = 1; prev.length < baselineNights && i <= 60; i++) {
    final d = DateTime(day.year, day.month, day.day - i);
    if (seg != null && d.isBefore(seg)) break;
    final x = plan.value(history, metric, d);
    if (x != null) prev.add(x);
  }
  if (prev.length < minNightsForBaseline) return NightBaseline(v, null, prev.length);
  return NightBaseline(v, usualOf(prev.reversed), prev.length);
}

/// Μέσοι όροι φάσεων (λεπτά) των τελευταίων 7 νυχτών Oura ως τη νύχτα [day].
class StageAverages {
  const StageAverages({required this.nights, this.deep, this.light, this.rem, this.awake});

  /// Οι νύχτες της εβδομάδας με όλες τις φάσεις (αυτές μπαίνουν στον μέσο όρο). Round 7 (R7-A5-2): οι τέσσερις τιμές
  /// είναι όλες null ή όλες με τιμή.
  final int nights;
  final int? deep;
  final int? light;
  final int? rem;

  /// «Τουλάχιστον» τόσα λεπτά ξύπνιος.
  final int? awake;
}

StageAverages ouraStageAverages(List<OuraNight> nights, DateTime day, SourcePlan plan) {
  // Έλεγχος 2, C12: μόνο νύχτες της ίδιας εποχής Oura (μετά από Oura → καμία → Oura, όχι μαζί με την παλιά).
  final seg = plan.segmentStart(K.deepPct, day);
  final recent = [
    for (final n in nights.reversed)
      if (!n.day.isAfter(day) &&
          (seg == null || !n.day.isBefore(seg)) &&
          n.day.isAfter(DateTime(day.year, day.month, day.day - 7)) &&
          plan.nightSource(n.day) == Source.oura &&
          n.main != null)
        n,
  ];
  // Round 1 (S5-5): η νύχτα σε κομμάτια μετρά ΟΛΑ τα κομμάτια της ([OuraNight.counted]), όπως η διάρκεια και τα
  // ποσοστά της ίδιας νύχτας ([ouraRow]). Πριν, μόνο η κύρια περίοδος: στην ίδια οθόνη η νύχτα ήταν 7 ώρες 55 λεπτά
  // και οι φάσεις της άθροιζαν 4 ώρες 40 λεπτά.
  // Round 7 (R7-A5-2): οι τέσσερις φάσεις από τις ΙΔΙΕΣ νύχτες: μετρά μόνο νύχτα όπου κάθε κομμάτι έχει βαθύ, ελαφρύ,
  // REM και ξύπνιο. Πριν, κάθε φάση είχε τις δικές της νύχτες (η μπάρα δεν ήταν «μια μέση νύχτα») και με μία νύχτα
  // χωρίς awake_time ο βαθύς έβγαινε ενώ ο ξύπνιος όχι, και η σελίδα έσπαγε στο `stages.awake!`.
  final complete = [
    for (final n in recent)
      if (n.counted.every((x) => x.deep != null && x.light != null && x.rem != null && x.awakeInSleep != null)) n.counted,
  ];
  int? avg(int? Function(OuraSleep) f) {
    if (complete.length < minNightsForAverage) return null;
    final sum = complete.fold<int>(0, (s, parts) => s + parts.fold<int>(0, (t, x) => t + f(x)!));
    return (sum / complete.length / 60).round();
  }

  return StageAverages(
    nights: complete.length,
    deep: avg((s) => s.deep),
    light: avg((s) => s.light),
    rem: avg((s) => s.rem),
    // E7: χωρίς τον χρόνο ως τον ύπνο (latency), ίδιος ορισμός με το ρολόι.
    awake: avg((s) => s.awakeInSleep),
  );
}

/// «Μόνο υπνάκος»: οι ώρες του (π.χ. «21:30–23:50 · 2 ώρες 15 λεπτά»), ώστε μια σύντομη νύχτα που τελείωσε πριν από
/// τα μεσάνυχτα να φαίνεται (δεν μετρά ως νύχτα: κανόνας επικάλυψης 00:00–06:00).
/// [nightOnly]: μόνο υπνάκοι της νύχτας (επικάλυψη με 18:00 της προηγούμενης ως 12:00 της μέρας), για τα κείμενα
/// «χθες βράδυ»· ποτέ ένας απογευματινός υπνάκος της ίδιας μέρας.
String napTimes(OuraNight? n, {bool nightOnly = false}) {
  if (n == null) return '';
  final d = n.day;
  final from = DateTime(d.year, d.month, d.day - 1, 18);
  final to = DateTime(d.year, d.month, d.day, 12);
  // Round 1 (S5-1): οι ώρες του τόπου όπου κοιμήθηκες ([OuraSleep.wallStart]).
  return [
    for (final x in n.naps)
      if (!nightOnly || (x.wallStart.isBefore(to) && x.wallEnd.isAfter(from)))
        '${hm(x.wallStart)}–${hm(x.wallEnd)}${x.totalMinutes == null ? '' : ' ·\u00A0${unitsGlued(hoursMinutes(x.totalMinutes!))}'}',
  ].join(', ');
}

/// Η νύχτα (όλα τα κομμάτια που μετρούν) είναι κάτω από 3 ώρες.
const shortNightLabel = 'Σύντομη νύχτα ·\u00A0κάτω από 3\u00A0ώρες';

/// Γιατί μια νύχτα δεν έχει ύπνο.
enum EmptyNight {
  /// Η νύχτα είναι του ρολογιού (πριν από τη σύνδεση): δεν αφορά το Oura.
  notOura,

  /// Δεν ήρθε ακόμα (πρωί, η εφαρμογή Oura δεν έχει συγχρονίσει).
  waiting,

  /// Δεν υπάρχει από το δαχτυλίδι (π.χ. δεν το φορούσες).
  noRing,

  /// Πρόβλημα σύνδεσης (χρειάζεται νέα σύνδεση).
  reconnect,

  /// Η συνδρομή δεν είναι ενεργή (403).
  subscription,

  /// Δεν έγινε ανάγνωση (δίκτυο κ.λπ.).
  notRead,

  /// Το Oura αποσυνδέθηκε και δεν διάλεξες άλλη πηγή.
  disconnected,

  /// Το δαχτυλίδι κατέγραψε μόνο υπνάκο (καμία περίοδος στο νυχτερινό παράθυρο).
  onlyNap,

  /// Δεν διαβάστηκε από πού έρχεται ο ύπνος (χαλασμένες ρυθμίσεις πηγών): κενό ώσπου να διαλέξεις.
  unknownPlan,

  /// Round 1 (S5-2 / U2a-05): πριν από τις 04:00, η νύχτα με τη σημερινή ημερομηνία δεν έχει τελειώσει ακόμα. Δεν
  /// λείπει τίποτα και δεν υπάρχει τίποτα να κάνεις.
  notYet,
}

String emptyNightText(EmptyNight r) => switch (r) {
      EmptyNight.notOura => '',
      EmptyNight.waiting => 'Περιμένει το Oura',
      EmptyNight.noRing => 'Δεν υπάρχουν δεδομένα από το δαχτυλίδι',
      EmptyNight.reconnect => 'Πρόβλημα σύνδεσης με το Oura',
      EmptyNight.subscription => 'Η συνδρομή Oura δεν είναι ενεργή',
      EmptyNight.notRead => 'Δεν διαβάστηκε ακόμα από την Oura',
      EmptyNight.disconnected => 'Το Oura δεν είναι συνδεδεμένο',
      EmptyNight.onlyNap => 'Μόνο υπνάκος από το δαχτυλίδι',
      EmptyNight.unknownPlan => 'Δεν διαβάστηκε από πού έρχεται ο ύπνος',
      EmptyNight.notYet => 'Η αποψινή νύχτα θα φανεί το πρωί',
    };

/// Ο λόγος που η νύχτα [day] είναι κενή (null = δεν είναι κενή).
/// [synced]: πότε διαβάστηκε τελευταία φορά το Oura με επιτυχία. [error]: το τελευταίο σφάλμα (όνομα).
EmptyNight? emptyNightReason({
  required SourcePlan plan,
  required DateTime day,
  required DateTime now,
  required OuraNight? night,
  required bool hasTokens,
  String? error,
  DateTime? synced,
  bool planUnknown = false,
}) {
  final src = plan.nightSource(day);
  if (src == Source.none) return planUnknown ? EmptyNight.unknownPlan : EmptyNight.disconnected;
  if (src != Source.oura) return null;
  if (night?.main != null) return null;
  final today = dayOf(now);
  final isToday = sameDay(day, today);
  // Round 1 (S5-2 / U2a-05): πριν από τις 04:00 η νύχτα με τη σημερινή ημερομηνία δεν έχει τελειώσει (κοιμάσαι ή δεν
  // έχεις κοιμηθεί ακόμα): ούτε «περιμένει το Oura» ούτε «μόνο υπνάκος» (ένας απογευματινός υπνάκος μετά τις 18:00
  // έχει ήδη τη σημερινή ημερομηνία). Ίδιο όριο με το `firstNightChoice`.
  if (isToday && now.hour < ouraNightDueHour) return EmptyNight.notYet;
  // Η Oura έδωσε μόνο υπνάκο για αυτή τη μέρα: το λέμε (όχι «δεν υπάρχουν δεδομένα»).
  // Round 8 (R8-A5-6): όχι το πρωί της ίδιας μέρας (ως τις 12:00): ένας βραδινός υπνάκος μπορεί να έχει ήδη διαβαστεί πριν
  // συγχρονίσει η εφαρμογή Oura τη νύχτα. Τότε ο ίδιος δρόμος με τη νύχτα που λείπει («Περιμένει το Oura»), όπως η
  // κατάσταση της Σήμερα (`ouraStatus`)· πριν, ο Ύπνος έλεγε οριστικά «κατέγραψε μόνο υπνάκο».
  if (night != null && night.onlyNap && !(isToday && now.hour < 12)) return EmptyNight.onlyNap;
  // Έλεγχος 2, C12: νύχτα που διαβάστηκε ΗΔΗ μετά το πρωί της και δεν είχε δεδομένα: «δεν υπάρχουν δεδομένα από το
  // δαχτυλίδι», όποια κι αν είναι η σύνδεση τώρα (μετά από αποσύνδεση ή χαμένα tokens δεν έγινε «πρόβλημα σύνδεσης»).
  final readAfter = synced != null && !synced.isBefore(DateTime(day.year, day.month, day.day, 4));
  if (readAfter && !(isToday && now.hour < 12)) {
    // Round 1 (S5-7): η ΤΕΛΕΥΤΑΙΑ προσπάθεια ανάγνωσης απέτυχε προσωρινά (δίκτυο, 429, διακομιστής, μεσάζων) και η
    // νύχτα είναι μέσα στις μέρες που ξαναδιαβάζονται κάθε φορά: δεν ξέρουμε αν ήρθε στο μεταξύ. «Δεν διαβάστηκε
    // ακόμα», όχι «δεν υπάρχουν δεδομένα από το δαχτυλίδι».
    final temporary =
        error != null && error != 'reconnect' && error != 'noRefresh' && error != 'scopeMissing' && error != 'subscription';
    final rereadDays = daysBetween(day, today);
    if (temporary && hasTokens && rereadDays >= 0 && rereadDays < ouraRecentDays) return EmptyNight.notRead;
    return EmptyNight.noRing;
  }
  // Αποσυνδέθηκε (από απόψε χωρίς πηγή, ή με ρητή επιλογή από το ρολόι): όχι «νέα σύνδεση».
  if (!hasTokens && plan.nightSource(DateTime(today.year, today.month, today.day + 1)) != Source.oura) {
    return EmptyNight.disconnected;
  }
  // Και «noRefresh» θέλει νέα σύνδεση.
  if (!hasTokens || error == 'reconnect' || error == 'noRefresh' || error == 'scopeMissing') return EmptyNight.reconnect;
  if (error == 'subscription') return EmptyNight.subscription;
  // Δεν διαβάστηκε μετά το πρωί αυτής της νύχτας: δεν ξέρουμε ακόμα.
  if (!readAfter) return isToday && now.hour < 12 ? EmptyNight.waiting : EmptyNight.notRead;
  // Διαβάστηκε: το πρωί περιμένουμε την εφαρμογή Oura, μετά τις 12:00 λέμε ότι δεν υπάρχει.
  if (isToday && now.hour < 12) return EmptyNight.waiting;
  return EmptyNight.noRing;
}

/// Μία νύχτα για τη «Σύγκριση πηγών»: Oura δίπλα στο ρολόι, μόνο για έλεγχο.
class CompareRow {
  const CompareRow({
    required this.day,
    this.ouraMinutes,
    this.ouraStart,
    this.ouraEnd,
    this.ouraHr,
    this.ouraAwake,
    this.watchMinutes,
    this.watchEstimated = 0,
    this.watchStart,
    this.watchEnd,
    this.watchParts = 0,
    this.ouraParts = 0,
    this.watchHr,
    this.watchAwake,
    this.ouraSpan,
    this.watchSpan,
  });

  /// Από τον ύπνο ως το ξύπνημα, ΜΕ τα ξυπνήματα (Oura: από την ώρα που κοιμήθηκες ως το τέλος· ρολόι: αρχή→τέλος των
  /// κομματιών). Συγκρίνεται μόνο με το ίδιο του άλλου.
  final int? ouraSpan;
  final int? watchSpan;

  final DateTime day;
  final int? ouraMinutes;
  final DateTime? ouraStart;
  final DateTime? ouraEnd;
  final double? ouraHr;

  /// Λεπτά ξύπνιος μέσα στη νύχτα, όπως τα μέτρησε κάθε συσκευή (και οι δύο μετρούν λιγότερα απ' όσα είναι).
  final int? ouraAwake;
  final int? watchAwake;

  /// Oura: μόνο ύπνος (total_sleep_duration, χωρίς τον χρόνο ξύπνιος).
  /// Ρολόι: πραγματικός ύπνος (από τις φάσεις, χωρίς τα ξυπνήματα): μόνο όταν όλα τα κομμάτια είχαν φάσεις,
  /// αλλιώς null — ποτέ «χρόνος με τα ξυπνήματα» δίπλα στον πραγματικό ύπνο του Oura.
  final int? watchMinutes;

  /// «Πιθανός ύπνος» στα κενά της Samsung (δεν μετρά στη διάρκεια).
  final int watchEstimated;
  final DateTime? watchStart;
  final DateTime? watchEnd;
  final int watchParts;

  /// Κομμάτια της νύχτας Oura που μετρούν (κοινός κανόνας με το ρολόι).
  final int ouraParts;
  final double? watchHr;

  bool get both => ouraMinutes != null && watchMinutes != null;
  int? get diff => both ? watchMinutes! - ouraMinutes! : null;
}

/// Μέσος όρος διαφοράς ρολογιού − Oura (λεπτά) στις νύχτες που έχουν και τα δύο.
({int nights, int? meanDiff, int splitNights}) compareSummary(List<CompareRow> rows) {
  final both = rows.where((r) => r.both).toList();
  if (both.isEmpty) return (nights: 0, meanDiff: null, splitNights: 0);
  final mean = both.fold<int>(0, (s, r) => s + r.diff!) / both.length;
  return (nights: both.length, meanDiff: mean.round(), splitNights: both.where((r) => r.watchParts > 1).length);
}

/// Round 1 (U2a-11): μια τιμή («Σάβ 14/11», «6 ώρες 27 λεπτά») δεν σπάει ποτέ σε δύο γραμμές: τα κενά της γίνονται
/// αδιάσπαστα.
String glued(String s) => s.replaceAll(' ', '\u00A0');

/// Ετικέτα με τιμή στο τέλος («Οξυγόνο τη νύχτα, χαμηλότερη τιμή 77%»): η τιμή μένει με τη λέξη πριν από αυτήν, άρα
/// δεν μένει ποτέ μόνη της σε γραμμή (U2a-11). Round 2 (R2-U1-6): ΜΟΝΟ το τελευταίο κενό· όταν όλο το κομμάτι μετά το
/// κόμμα γινόταν αδιάσπαστο, σε 360 dp με γράμματα 1,3× ήταν φαρδύτερο από τη στήλη και η Flutter το έκοβε μέσα στη
/// λέξη («… τιμή 77 | %»).
String gluedValue(String s) => s.replaceFirst(RegExp(r' (?=\S+$)'), '\u00A0');

/// Round 1 (U2a-06): γιατί λείπει η χθεσινή νύχτα, σε ολόκληρη πρόταση με ό,τι χρειάζεται να κάνεις (η σελίδα «Ύπνος»
/// τη δείχνει πάνω από την τελευταία νύχτα που ήρθε). [nap]: οι ώρες του υπνάκου, για το «μόνο υπνάκος».
/// [watchTonight]: μετά την αποσύνδεση διάλεξε ρητά «από απόψε το ρολόι».
String lastNightNote(EmptyNight r, {String nap = '', bool watchTonight = false}) => switch (r) {
      EmptyNight.waiting =>
        'Η χθεσινή νύχτα δεν έχει φτάσει ακόμα. Άνοιξε την εφαρμογή Oura για να συγχρονίσει, και μετά γύρνα εδώ.',
      EmptyNight.noRing =>
        'Χθες βράδυ δεν ήρθε ύπνος από το δαχτυλίδι. Αν το φορούσες, άνοιξε την εφαρμογή Oura για να συγχρονίσει.',
      EmptyNight.reconnect => 'Η χθεσινή νύχτα δεν διαβάστηκε: το Oura χρειάζεται νέα σύνδεση.',
      EmptyNight.subscription =>
        'Η χθεσινή νύχτα δεν διαβάστηκε: η Oura δεν δίνει δεδομένα (η συνδρομή δεν είναι ενεργή ή λείπει η άδεια).',
      EmptyNight.notRead => 'Η χθεσινή νύχτα δεν διαβάστηκε ακόμα από την Oura.',
      EmptyNight.disconnected => watchTonight
          ? 'Το Oura αποσυνδέθηκε. Από απόψε ο ύπνος έρχεται από το ρολόι, όπως διάλεξες.'
          : 'Το Oura αποσυνδέθηκε. Οι νύχτες μένουν κενές ώσπου να το συνδέσεις ξανά ή να διαλέξεις το ρολόι.',
      EmptyNight.onlyNap =>
        'Χθες βράδυ το δαχτυλίδι κατέγραψε μόνο υπνάκο${nap.isEmpty ? '' : ' ($nap)'}. Ο υπνάκος δεν μετρά ως νύχτα.',
      EmptyNight.unknownPlan => 'Δεν διαβάστηκε από πού έρχεται ο ύπνος. Διάλεξε πηγή για να συνεχίσουν οι νύχτες.',
      EmptyNight.notYet || EmptyNight.notOura => '',
    };

/// Λεπτά → «τουλάχιστον 28 λεπτά».
String atLeast(int minutes) => 'τουλάχιστον ${hoursMinutes(minutes)}';

/// Round 1 (S4-5): η μία νύχτα του δαχτυλιδιού απέναντι στη σύσταση «τουλάχιστον 7 ώρες» ([adviceMin], από το
/// reference.dart). Η σύσταση (AASM και Sleep Research Society· Watson κ.ά., Sleep 2015) στηρίζεται σχεδόν μόνο σε
/// ώρες ύπνου που ΔΗΛΩΝΑΝ οι ίδιοι οι άνθρωποι· σε μέτρηση με συσκευή οι ίδιοι άνθρωποι βγαίνουν κατά μέσο όρο 0,8 ώρες
/// κάτω (6,0 μετρημένες έναντι 6,8 δηλωμένων· Lauderdale κ.ά., Epidemiology 2008). Γι' αυτό:
/// - ύπνος (χωρίς τα ξυπνήματα) ≥ σύσταση: το λέμε·
/// - ύπνος κάτω από τη σύσταση αλλά χρόνος στο κρεβάτι ≥ σύσταση (ή άγνωστος): ΚΑΜΙΑ ετυμηγορία «κάτω από το εύρος»·
///   δείχνονται και τα δύο νούμερα και από πού βγήκε η σύσταση·
/// - και ο χρόνος στο κρεβάτι κάτω από τη σύσταση: «λιγότερο από τη σύσταση» (αληθές με κάθε τρόπο μέτρησης).
/// Πάντα «μία νύχτα» και «μετρά ο μέσος όρος πολλών νυχτών» (έλεγχος 9/11).
String sleepVsAdvice({required int asleepMin, required int? inBedMin, required int adviceMin}) {
  final asleep = hoursMinutes(asleepMin);
  final advice = hoursMinutes(adviceMin);
  const tail = ' Μετρά ο μέσος όρος πολλών νυχτών.';
  const basis = 'βασίζεται σε ώρες που δηλώνουν οι ίδιοι οι άνθρωποι· οι συσκευές μετρούν συνήθως λιγότερο.';
  if (asleepMin >= adviceMin) {
    return 'Μία νύχτα: ύπνος $asleep, όσο ζητά η σύσταση για ενήλικες (τουλάχιστον $advice).$tail';
  }
  if (inBedMin == null) {
    return 'Μία νύχτα: ύπνος $asleep. Η σύσταση για ενήλικες (τουλάχιστον $advice) $basis$tail';
  }
  final bed = hoursMinutes(inBedMin);
  if (inBedMin >= adviceMin) {
    return 'Μία νύχτα: ύπνος $asleep, στο κρεβάτι $bed. Η σύσταση για ενήλικες (τουλάχιστον $advice) $basis$tail';
  }
  return 'Μία νύχτα: ύπνος $asleep, στο κρεβάτι $bed: λιγότερο από τη σύσταση για ενήλικες (τουλάχιστον $advice).$tail';
}

/// Κλειδιά του ιστορικού που διαβάζει η σελίδα (για να φαίνεται ρητά ότι είναι μόνο του Oura).
const ouraScreenMetrics = [K.hrv, K.sleepHr, K.lowHr, K.breath, K.skinTemp, K.energy, K.sleepScore];
