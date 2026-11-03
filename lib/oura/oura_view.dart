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
import 'oura_model.dart';

/// Ελάχιστες νύχτες για μέσο όρο ή «συνηθισμένο».
const minNightsForAverage = 4;
const minNightsForBaseline = 7;
const baselineNights = 14;

/// Η τιμή μιας νύχτας μπροστά στο συνηθισμένο σου (μέση τιμή των προηγούμενων 14 νυχτών Oura).
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
  return NightBaseline(v, prev.reduce((a, b) => a + b) / prev.length, prev.length);
}

/// Μέσοι όροι φάσεων (λεπτά) των τελευταίων 7 νυχτών Oura ως τη νύχτα [day].
class StageAverages {
  const StageAverages({required this.nights, this.deep, this.light, this.rem, this.awake});
  final int nights;
  final int? deep;
  final int? light;
  final int? rem;

  /// «Τουλάχιστον» τόσα λεπτά ξύπνιος.
  final int? awake;
}

StageAverages ouraStageAverages(List<OuraNight> nights, DateTime day, SourcePlan plan) {
  final recent = [
    for (final n in nights.reversed)
      if (!n.day.isAfter(day) &&
          n.day.isAfter(DateTime(day.year, day.month, day.day - 7)) &&
          plan.nightSource(n.day) == Source.oura &&
          n.main != null)
        n.main!,
  ];
  int? avg(int? Function(OuraSleep) f) {
    final v = [for (final s in recent) if (f(s) != null) f(s)!];
    if (v.length < minNightsForAverage) return null;
    return (v.reduce((a, b) => a + b) / v.length / 60).round();
  }

  return StageAverages(
    nights: recent.length,
    deep: avg((s) => s.deep),
    light: avg((s) => s.light),
    rem: avg((s) => s.rem),
    awake: avg((s) => s.awake),
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
  return [
    for (final x in n.naps)
      if (!nightOnly || (x.start.isBefore(to) && x.end.isAfter(from)))
        '${hm(x.start)}–${hm(x.end)}${x.totalMinutes == null ? '' : ' · ${hoursMinutes(x.totalMinutes!)}'}',
  ].join(', ');
}

/// Η νύχτα είναι μόνο ένα σύντομο κομμάτι ύπνου (το Oura το λέει «sleep», όχι «long_sleep»).
const shortNightLabel = 'Σύντομη νύχτα · κάτω από 3 ώρες';

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
  // Η Oura έδωσε μόνο υπνάκο για αυτή τη μέρα: το λέμε (όχι «δεν υπάρχουν δεδομένα»).
  if (night != null && night.onlyNap) return EmptyNight.onlyNap;
  final today = dayOf(now);
  final isToday = sameDay(day, today);
  // Αποσυνδέθηκε (από απόψε χωρίς πηγή): όχι «νέα σύνδεση».
  if (!hasTokens && plan.nightSource(DateTime(today.year, today.month, today.day + 1)) == Source.none) {
    return EmptyNight.disconnected;
  }
  // Και «noRefresh» θέλει νέα σύνδεση.
  if (!hasTokens || error == 'reconnect' || error == 'noRefresh' || error == 'scopeMissing') return EmptyNight.reconnect;
  if (error == 'subscription') return EmptyNight.subscription;
  // Δεν διαβάστηκε μετά το πρωί αυτής της νύχτας: δεν ξέρουμε ακόμα.
  final readAfter = synced != null && !synced.isBefore(DateTime(day.year, day.month, day.day, 4));
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
    this.watchMinutes,
    this.watchEstimated = 0,
    this.watchStart,
    this.watchEnd,
    this.watchParts = 0,
    this.watchHr,
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

  /// Πραγματικός ύπνος του ρολογιού (από τις φάσεις, χωρίς τα ξυπνήματα): μόνο όταν όλα τα κομμάτια είχαν φάσεις,
  /// αλλιώς null — ποτέ «χρόνος με τα ξυπνήματα» δίπλα στον πραγματικό ύπνο του Oura.
  final int? watchMinutes;

  /// «Πιθανός ύπνος» στα κενά της Samsung (δεν μετρά στη διάρκεια).
  final int watchEstimated;
  final DateTime? watchStart;
  final DateTime? watchEnd;
  final int watchParts;
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

/// Λεπτά → «τουλάχιστον 28 λεπτά».
String atLeast(int minutes) => 'τουλάχιστον ${hoursMinutes(minutes)}';

/// Κλειδιά του ιστορικού που διαβάζει η σελίδα (για να φαίνεται ρητά ότι είναι μόνο του Oura).
const ouraScreenMetrics = [K.hrv, K.sleepHr, K.lowHr, K.breath, K.skinTemp, K.energy, K.sleepScore];
