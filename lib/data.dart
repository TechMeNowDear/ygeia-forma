import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart';

import 'error_report.dart';
import 'format.dart';
import 'history.dart';
import 'oura/config.dart' show ouraMaxBackDays;
import 'oura/oura_model.dart';
import 'oura/oura_store.dart';
import 'oxygen_note.dart' show oxygenLongWindowNights;
import 'plan_file.dart';
import 'samsung.dart';
import 'sleep_gaps.dart';
import 'sources.dart';
import 'trends.dart' show usualMean;

// ---------------------------------------------------------------------------
// Μοντέλα
// ---------------------------------------------------------------------------

class Stage {
  Stage(this.name, this.start, this.end);
  final String name;
  final DateTime start;
  final DateTime end;
  int get minutes => end.difference(start).inMinutes;
}

class SleepRecord {
  SleepRecord(this.start, this.end, this.minutes, this.score, this.stages);
  final DateTime start;
  final DateTime end;

  /// Η διάρκεια όπως τη δίνει η Samsung (DURATION). Δεν ξέρουμε με σιγουριά αν περιέχει τα ξυπνήματα: η Samsung
  /// δείχνει «Χρόνος ύπνου» (από τον ύπνο ως το ξύπνημα, ΜΕ τα ξυπνήματα) και «Πραγματικός ύπνος» (έλεγχος 4/11).
  final int minutes;
  final int? score;
  final List<Stage> stages;

  static const _asleep = {'LIGHT', 'DEEP', 'REM'};
  static const _known = {'LIGHT', 'DEEP', 'REM', 'AWAKE'};

  /// Πόσο από το κομμάτι μπορεί να είναι φάση «άγνωστη» (UNDEFINED) χωρίς να χαθεί ο πραγματικός ύπνος (C3).
  static const undefinedShare = 0.05;

  /// Πραγματικός ύπνος σε δευτερόλεπτα: ελαφρύς + βαθύς + REM, χωρίς τα ξυπνήματα. Μόνο αν το κομμάτι έχει φάσεις
  /// (αλλιώς null: δεν ξέρουμε). Άγνωστες φάσεις ως το [undefinedShare] του κομματιού δεν μετρούν ούτε ως ύπνος ούτε
  /// ως ξύπνιος (C3: μία άγνωστη φάση δεν «σβήνει» όλη τη νύχτα)· περισσότερες: null.
  int? get asleepSeconds {
    if (stages.isEmpty) return null;
    var unknown = 0;
    var asleep = 0;
    var total = 0;
    for (final s in stages) {
      final secs = s.end.difference(s.start).inSeconds;
      total += secs;
      if (_asleep.contains(s.name)) {
        asleep += secs;
      } else if (!_known.contains(s.name)) {
        unknown += secs;
      }
    }
    final span = math.max(total, end.difference(start).inSeconds);
    if (unknown > 0 && (unknown == total || unknown > undefinedShare * span)) return null;
    return asleep;
  }

  /// Ύπνος του κομματιού σε λεπτά: ο πραγματικός (από τις φάσεις) όταν υπάρχει, αλλιώς η διάρκεια της Samsung.
  int get sleepMinutes {
    final a = asleepSeconds;
    return a == null ? minutes : (a / 60).round();
  }
}

/// Μία νύχτα ύπνου (μπορεί να έχει πολλά κομμάτια), με ημερομηνία το πρωί που ξύπνησα.
class Night {
  Night(this.date);
  final DateTime date;
  final List<SleepRecord> parts = [];
  final List<Stage> stages = [];
  final Map<String, int> stageMinutes = {};

  /// Δευτερόλεπτα ανά φάση (τα λεπτά στρογγυλεύονται μία φορά, στο τέλος).
  final Map<String, int> stageSeconds = {};
  late DateTime start;
  late DateTime end;

  /// Πραγματικός ύπνος (έλεγχος 4/11): ελαφρύς + βαθύς + REM από τις φάσεις, ΧΩΡΙΣ τα ξυπνήματα και χωρίς τα κενά
  /// ανάμεσα στα κομμάτια· ίδιος ορισμός με το «Πραγματικός ύπνος» της Samsung και το total_sleep_duration του Oura.
  /// Κομμάτι χωρίς φάσεις: η διάρκεια της Samsung ([staged] = false).
  int minutes = 0;

  /// Αν η νύχτα έχει φάσεις (τουλάχιστον ένα κομμάτι): τότε τα [minutes] είναι πραγματικός ύπνος, χωρίς τα ξυπνήματα.
  bool staged = false;

  /// Κάποιο κομμάτι της νύχτας ήρθε χωρίς φάσεις (C2/C3): τα [minutes] μετρούν μόνο τα κομμάτια με φάσεις («μερικώς
  /// χωρίς φάσεις»), ποτέ με τα ξυπνήματα του άλλου κομματιού.
  bool partial = false;

  /// Από τον ύπνο ως το ξύπνημα, ΜΕ τα ξυπνήματα («Χρόνος ύπνου» της Samsung): άθροισμα αρχή→τέλος των κομματιών.
  int spanMinutes = 0;

  /// Κενά ανάμεσα στα κομμάτια της νύχτας (εκτός από τον «πιθανό ύπνο»): δεν μετρούν ποτέ ως ύπνος.
  int betweenMinutes = 0;
  int? score;
  double? sleepingHr;
  double? spo2Avg;
  double? spo2Min;
  double? spo2Below90;
  double? skinTemp;
  int napMinutes = 0;

  /// Έλεγχος 3, E1.6: η απόφαση «πρωινός υπνάκος» που πάρθηκε με βήματα (αρχή του κομματιού που έγινε υπνάκος),
  /// ώστε να αποθηκευτεί ([K.napLock]) και να μην αλλάξει όταν τα βήματα ανά λεπτό δεν υπάρχουν πια.
  DateTime? napLock;

  /// Κενά της Samsung ανάμεσα στα κομμάτια, με παλμούς σαν του ύπνου (δες sleep_gaps.dart).
  /// «Πιθανός ύπνος»: φαίνονται χωριστά και **δεν** μετρούν στα [minutes].
  final List<(DateTime, DateTime)> estimatedGaps = [];
  int get estimatedMinutes => estimatedGaps.fold(0, (s, g) => s + g.$2.difference(g.$1).inMinutes);

  int get awakeMinutes => stageMinutes['AWAKE'] ?? 0;

  /// Πραγματικός ύπνος από τα στάδια: βαθύς + ελαφρύς + REM, χωρίς τον χρόνο ξύπνιος.
  int get asleepStageMinutes => ['DEEP', 'LIGHT', 'REM'].fold(0, (s, k) => s + (stageMinutes[k] ?? 0));

  /// Ποσοστό ενός σταδίου ύπνου επί του πραγματικού ύπνου (όχι επί του χρόνου με τα ξυπνήματα), ίδιος ορισμός
  /// για ρολόι και Oura (έλεγχος 4/11, F6/B4). Το «ξύπνιος» δεν είναι ποσοστό του ύπνου: null (φαίνεται σε λεπτά).
  double? stagePct(String stage) {
    final asleep = asleepStageMinutes;
    if (asleep <= 0 || stage == 'AWAKE') return null;
    return 100 * (stageMinutes[stage] ?? 0) / asleep;
  }
}

/// Διπλές ή επικαλυπτόμενες εγγραφές ύπνου δεν αθροίζονται (π.χ. η ίδια νύχτα από δύο πηγές).
/// - Αν η επικάλυψη είναι τουλάχιστον το μισό της μικρότερης εγγραφής: η ίδια νύχτα δύο φορές,
///   κρατάμε τη μεγαλύτερη.
/// - Αν είναι μικρότερη: η δεύτερη ξεκινά εκεί που τελειώνει η πρώτη και χάνει τα κοινά λεπτά.
List<SleepRecord> dedupeSleep(List<SleepRecord> records) {
  final sorted = [...records]..sort((a, b) => a.start.compareTo(b.start));
  final out = <SleepRecord>[];
  for (final r in sorted) {
    if (out.isEmpty || !r.start.isBefore(out.last.end)) {
      out.add(r);
      continue;
    }
    final k = out.last;
    final overlap = (r.end.isBefore(k.end) ? r.end : k.end).difference(r.start);
    final rLen = r.end.difference(r.start);
    final kLen = k.end.difference(k.start);
    final shorter = rLen < kLen ? rLen : kLen;
    if (shorter.inSeconds <= 0 || overlap.inSeconds * 2 >= shorter.inSeconds) {
      if (rLen > kLen) out[out.length - 1] = r;
      continue;
    }
    out.add(SleepRecord(
      k.end,
      r.end,
      math.max(0, r.minutes - overlap.inMinutes),
      r.score,
      [for (final s in r.stages) if (!s.start.isBefore(k.end)) s],
    ));
  }
  return out;
}

class Sample {
  Sample(this.start, this.end, this.avg, this.min, this.max, [this.belowSec]);
  final DateTime start;
  final DateTime end;
  final double avg;
  final double min;
  final double max;

  /// Οξυγόνο: δευτερόλεπτα κάτω από 90%, μόνο όταν βγαίνει με σιγουριά από τις αναλυτικές μετρήσεις.
  final double? belowSec;
}

/// Οξυγόνο μιας νύχτας από το ρολόι: μέσο (null αν υπάρχουν μόνο σύντομες μετρήσεις), χαμηλότερη μέτρηση
/// (ενδεικτική), λεπτά κάτω από 90% (αν βγαίνουν).
typedef NightOxygen = ({double? avg, double min, double? below90});

/// Λεπτά κάτω από 90%: μόνο αν ΚΑΘΕ μέτρηση της νύχτας το δίνει (αλλιώς δεν ξέρουμε, άρα κενό).
double? _below90Minutes(List<Sample> ox) {
  if (ox.isEmpty || ox.any((s) => s.belowSec == null)) return null;
  return ox.fold<double>(0, (t, s) => t + s.belowSec!) / 60;
}

class DayValue {
  DayValue(this.day, this.value);
  final DateTime day;
  final double value;
}

class BodyMeasurement {
  BodyMeasurement({
    required this.time,
    this.weight,
    this.fatPct,
    this.fatKg,
    this.smm,
    this.ffm,
    this.bmi,
    this.water,
    this.bmr,
    this.app = '',
  });

  final DateTime time;

  /// Η εφαρμογή που έγραψε τη μέτρηση στη Samsung Health (π.χ. της InBody).
  final String app;
  final double? weight;
  final double? fatPct;
  final double? fatKg;
  final double? smm;
  final double? ffm;
  final double? bmi;
  final double? water;
  final int? bmr;

  /// Άλιπη μάζα: από την InBody, αλλιώς βάρος μείον λίπος.
  double? get leanMass => ffm ?? ((weight != null && fatKg != null) ? weight! - fatKg! : null);
}

/// Ζυγίσεις μόνο από την εφαρμογή της InBody (έλεγχος 4/11, A2): η Samsung Health κρατά και χειροκίνητα βάρη,
/// μετρήσεις σύστασης του ρολογιού (BIA) ή ό,τι έρχεται από το Health Connect. Αυτά δεν μπαίνουν ποτέ στη σειρά
/// της ζυγαριάς. Ο ίδιος κανόνας με την ετικέτα «InBody» στο «Τι φτάνει» (labels.dart) και στο Kotlin (SourceRules).
bool isScaleApp(String appId) => appId.toLowerCase().contains('inbody');

/// Όρια λογικών τιμών: έξω από αυτά η τιμή είναι σφάλμα αισθητήρα (π.χ. ρολόι εκτός καρπού), όχι μέτρηση.
const hrRange = (25.0, 250.0);
const spo2Range = (50.0, 100.0);
const skinRange = (20.0, 42.0);

/// Χρόνος που δεν μπορεί να είναι μέτρηση (πριν από το 2000, π.χ. «0» = 1970): η εγγραφή αγνοείται.
const _oldestMs = 946684800000;

/// Οξυγόνο: εγγραφές μικρότερες από αυτό (π.χ. μια χειροκίνητη μέτρηση στο ρολόι) δεν μετρούν στον μέσο όρο
/// της νύχτας. Μετρούν μόνο στη «χαμηλότερη μέτρηση», που είναι ενδεικτική.
const spo2MinRecord = Duration(seconds: 60);

/// Οξυγόνο από εγγραφές (A4): μέσος όρος σταθμισμένος με τη διάρκεια κάθε εγγραφής, μόνο από εγγραφές τουλάχιστον
/// [spo2MinRecord]· χαμηλότερη μέτρηση από όλες (ενδεικτική)· λεπτά κάτω από 90% μόνο από τις μεγάλες εγγραφές.
/// null αν δεν υπάρχει καμία εγγραφή.
NightOxygen? oxygenOf(List<Sample> ox) {
  if (ox.isEmpty) return null;
  final long = [for (final s in ox) if (s.end.difference(s.start) >= spo2MinRecord) s];
  double? avg;
  if (long.isNotEmpty) {
    var sum = 0.0;
    var secs = 0.0;
    for (final s in long) {
      final w = s.end.difference(s.start).inMilliseconds / 1000;
      sum += s.avg * w;
      secs += w;
    }
    avg = sum / secs;
  }
  return (avg: avg, min: ox.map((s) => s.min).reduce(math.min), below90: _below90Minutes(long));
}

// ---------------------------------------------------------------------------
// Όλα τα δεδομένα μιας ανάγνωσης, με τους υπολογισμούς τους
// ---------------------------------------------------------------------------

class Dashboard {
  Dashboard._({
    required this.readAt,
    required this.granted,
    required this.total,
    required this.nights,
    required this.heart,
    required this.spo2,
    required this.skin,
    required this.energy,
    required this.steps,
    required this.floors,
    required this.body,
    required this.activity,
    required this.sleepRecords,
    required this.stepsByMinute,
    required this.stepsMinuteFrom,
    required this.exercise,
    required this.activityDaily,
    required this.sleepOk,
    this.bodyOk = false,
    this.failed = const {},
    this.compareNights = const [],
    this.bodyOther = 0,
    this.naps = const {},
    this.napTimes = const {},
    this.otherBodyDays = const {},
  });

  /// Οι ώρες των υπνάκων ανά ημερομηνία (αρχή, τέλος, λεπτά ύπνου), ενωμένα τα κομμάτια που αγγίζονται. Για τη μέρα
  /// χωρίς νύχτα στη λίστα του Ύπνου («Μόνο υπνάκος», τελικός έλεγχος)· δεν μετρούν πουθενά ως νύχτα.
  final Map<DateTime, List<(DateTime, DateTime, int)>> napTimes;

  /// Μέρες («2026-11-10») με ζύγιση από ΑΛΛΗ εφαρμογή (όχι InBody) στη Samsung Health: οι παλιές εκδόσεις τις
  /// έγραφαν στο ιστορικό. Έλεγχος 3, E2: δεν σβήνονται ποτέ· μετρούν ως «υπάρχουν ακόμα» στη Samsung.
  final Set<String> otherBodyDays;

  /// Υπνάκοι του ρολογιού (λεπτά) ανά ημερομηνία νύχτας (C1): αποθηκεύονται στο ιστορικό (napMin), ακόμα και μέρα
  /// χωρίς νύχτα, ώστε μετρημένος ύπνος να μη χάνεται.
  final Map<DateTime, int> naps;

  /// Ζυγίσεις από άλλες εφαρμογές (όχι InBody) που δεν μπήκαν ([isScaleApp]).
  final int bodyOther;

  /// Νύχτες του ρολογιού που ΔΕΝ είναι η πηγή του ύπνου (μετά τη σύνδεση του Oura), μόνο για τη
  /// «Σύγκριση πηγών» τις πρώτες 14 μέρες. Καμία άλλη οθόνη ή υπολογισμός δεν τις διαβάζει.
  final List<Night> compareNights;

  /// Για τις ΟΘΟΝΕΣ (όχι για το ιστορικό, που υπολογίζεται από τα πλήρη δεδομένα με το σχέδιο πηγών):
  /// - στις [nights] μένουν μόνο νύχτες του ρολογιού της τρέχουσας εποχής ρολογιού (μετά από «ξανά από το
  ///   ρολόι» δεν φαίνονται νύχτες από πριν από το Oura· όσο ο ύπνος είναι του Oura ή χωρίς πηγή, καμία),
  /// - στις [compareNights] οι νύχτες του ρολογιού για τη «Σύγκριση πηγών», μόνο όσο είναι ανοιχτή,
  /// - το Energy Score της Samsung μόνο όσο η «νύχτα» είναι του ρολογιού, από την τρέχουσα εποχή.
  /// Έτσι καμία οθόνη δεν δείχνει ύπνο του ρολογιού για νύχτα του Oura, ούτε συγκρίνει πάνω από αλλαγή πηγής.
  Dashboard restrict(SourcePlan plan) {
    if (plan.eras.isEmpty) return this;
    final today = dayOf(readAt);
    final all = [...nights, ...compareNights]..sort((a, b) => a.date.compareTo(b.date));
    final watchNow = plan.nightSource(today) == Source.watch;
    final seg = plan.segmentStart(K.sleepMin, today);
    bool current(DateTime d) => watchNow && plan.nightSource(d) == Source.watch && (seg == null || !d.isBefore(seg));
    return Dashboard._(
      readAt: readAt,
      granted: granted,
      total: total,
      nights: [for (final n in all) if (current(n.date)) n],
      compareNights: [
        for (final n in all)
          if (plan.nightSource(n.date) != Source.watch && plan.watchSleepAllowed(n.date, today)) n,
      ],
      heart: heart,
      spo2: spo2,
      skin: skin,
      energy: [for (final e in energy) if (current(e.day)) e],
      steps: steps,
      floors: floors,
      body: body,
      activity: activity,
      sleepRecords: sleepRecords,
      stepsByMinute: stepsByMinute,
      stepsMinuteFrom: stepsMinuteFrom,
      exercise: exercise,
      activityDaily: activityDaily,
      sleepOk: sleepOk,
      bodyOk: bodyOk,
      failed: failed,
      bodyOther: bodyOther,
      naps: naps,
      napTimes: napTimes,
      otherBodyDays: otherBodyDays,
    );
  }

  /// Ο ύπνος διαβάστηκε κανονικά (όχι σφάλμα ανάγνωσης). Χωρίς αυτό δεν σβήνουμε τιμές ύπνου από το ιστορικό.
  final bool sleepOk;

  /// Οι ζυγίσεις (10 χρόνια) διαβάστηκαν όλες: μόνο τότε σβήνεται από το ιστορικό ζύγιση που δεν υπάρχει πια.
  final bool bodyOk;

  /// Είδη δεδομένων που η Samsung δεν έδωσε τώρα (σφάλμα), π.χ. {'heart'}: οι οθόνες λένε «δεν διαβάστηκε»,
  /// όχι «δεν υπάρχει».
  final Set<String> failed;

  final DateTime readAt;
  final int granted;
  final int total;
  final List<Night> nights; // παλιότερη πρώτη
  final List<Sample> heart;
  final List<Sample> spo2;
  final List<Sample> skin;
  final List<DayValue> energy;
  final List<DayValue> steps;
  final List<DayValue> floors;
  final List<BodyMeasurement> body; // παλιότερη πρώτη
  final Map<String, dynamic> activity;

  /// Όλα τα κομμάτια ύπνου (και οι υπνάκοι), για να εξαιρούνται από τους παλμούς ημέρας.
  final List<SleepRecord> sleepRecords;

  /// Βήματα ανά λεπτό: κλειδί = λεπτά από την εποχή Unix.
  final Map<int, int> stepsByMinute;

  /// Από πότε υπάρχουν βήματα ανά λεπτό (null = καθόλου).
  final DateTime? stepsMinuteFrom;

  /// Ασκήσεις (αρχή, τέλος).
  final List<(DateTime, DateTime)> exercise;

  /// Ανά μέρα: (μέρα, ενεργά λεπτά, θερμίδες).
  final List<(DateTime, int?, double?)> activityDaily;

  bool get hasAnyPermission => granted > 0;

  /// [napLocks]: οι αποθηκευμένες αποφάσεις «πρωινός υπνάκος» ανά νύχτα («2026-11-03» → λεπτά από την εποχή Unix,
  /// [K.napLock] του ιστορικού), για τις νύχτες που δεν έχουν πια βήματα ανά λεπτό (E1.6).
  factory Dashboard.fromJson(Map<String, dynamic> j, {Map<String, int> napLocks = const {}}) {
    DateTime t(dynamic ms) => DateTime.fromMillisecondsSinceEpoch((ms as num).toInt());
    // Χρόνος «0» ή πριν από το 2000: η εγγραφή αγνοείται (αλλιώς μια νύχτα του 1970 θα «κατάπινε» όλες τις άλλες).
    bool okTime(dynamic ms) => ms is num && ms >= _oldestMs;
    List<dynamic> list(String key) => j[key] is List ? j[key] as List<dynamic> : const [];
    double? d(dynamic v) => v is num ? v.toDouble() : null;

    // Τιμή έξω από τα λογικά όρια = σφάλμα αισθητήρα: η εγγραφή αγνοείται· ελάχιστο/μέγιστο έξω από τα όρια
    // παίρνουν τη μέση τιμή της εγγραφής (π.χ. «ελάχιστο 0%» δεν είναι μέτρηση).
    List<Sample> samples(String key, (double, double) range) {
      bool inRange(num v) => v >= range.$1 && v <= range.$2;
      return [
        for (final e in list(key))
          if (e is List && e.length >= 3 && okTime(e[0]) && e[2] is num && inRange(e[2] as num))
            Sample(
              t(e[0]),
              e[1] is num && (e[1] as num) >= (e[0] as num) ? t(e[1]) : t(e[0]),
              (e[2] as num).toDouble(),
              e.length > 3 && e[3] is num && inRange(e[3] as num) ? (e[3] as num).toDouble() : (e[2] as num).toDouble(),
              e.length > 4 && e[4] is num && inRange(e[4] as num) ? (e[4] as num).toDouble() : (e[2] as num).toDouble(),
              e.length > 5 && e[5] is num ? (e[5] as num).toDouble() : null,
            ),
      ];
    }

    final records = <SleepRecord>[
      for (final e in list('sleep'))
        if (e is Map<String, dynamic> && okTime(e['start']) && okTime(e['end']) && (e['end'] as num) > (e['start'] as num))
          () {
            final start = t(e['start']);
            final end = t(e['end']);
            final stages = <Stage>[
              for (final s in (e['stages'] as List<dynamic>? ?? const []))
                if (s is List && s.length >= 3 && okTime(s[1]) && okTime(s[2])) Stage(s[0].toString(), t(s[1]), t(s[2])),
            ]..sort((a, b) => a.start.compareTo(b.start));
            final minutes = (e['minutes'] as num?)?.toInt() ?? end.difference(start).inMinutes;
            return SleepRecord(start, end, minutes, (e['score'] as num?)?.toInt(), stages);
          }(),
    ]..sort((a, b) => a.start.compareTo(b.start));

    final heart = samples('heart', hrRange)..sort((a, b) => a.start.compareTo(b.start));
    final spo2 = samples('spo2', spo2Range);
    final skin = samples('skinTemp', skinRange);

    final floorsByDay = <DateTime, double>{};
    for (final e in list('floors')) {
      if (e is List && e.length >= 2 && okTime(e[0])) {
        final day = dayOf(t(e[0]));
        floorsByDay[day] = (floorsByDay[day] ?? 0) + (e[1] as num).toDouble();
      }
    }

    final allBody = <BodyMeasurement>[
      for (final e in list('body'))
        if (e is Map<String, dynamic> && okTime(e['time']))
          BodyMeasurement(
            time: t(e['time']),
            weight: d(e['weight']),
            fatPct: d(e['fatPct']),
            fatKg: d(e['fatKg']),
            smm: d(e['smm']),
            ffm: d(e['ffm']),
            bmi: d(e['bmi']),
            water: d(e['water']),
            bmr: (e['bmr'] as num?)?.toInt(),
            app: e['app'] is String ? e['app'] as String : '',
          ),
    ]..sort((a, b) => a.time.compareTo(b.time));
    // Μόνο InBody ([isScaleApp]): ποτέ βάρος από άλλη εφαρμογή ή συσκευή στη σειρά της ζυγαριάς.
    final body = [for (final b in allBody) if (isScaleApp(b.app)) b];

    final stepsByMinute = <int, int>{
      for (final e in list('stepsMin'))
        if (e is List && e.length >= 2 && okTime(e[0])) (e[0] as num).toInt() ~/ 60000: (e[1] as num).toInt(),
    };
    final stepsFrom = j['stepsMin'] is List
        ? (j['stepsFrom'] is num
            ? t(j['stepsFrom'])
            : () {
                final r = j['readAt'] is num ? t(j['readAt']) : DateTime.now();
                return DateTime(r.year, r.month, r.day - 7);
              }())
        : null;

    final grouped =
        _groupNights(records, heart: heart, stepsByMinute: stepsByMinute, stepsFrom: stepsFrom, napLocks: napLocks);
    final nights = grouped.nights..forEach((n) => _fillNightMetrics(n, heart, spo2, skin));

    return Dashboard._(
      readAt: j['readAt'] is num ? t(j['readAt']) : DateTime.now(),
      sleepOk: j['sleep'] is List,
      bodyOk: j['body'] is List,
      failed: {
        for (final e in j.entries)
          if (e.value is Map && (e.value as Map).containsKey('error')) e.key,
      },
      granted: (j['granted'] as num?)?.toInt() ?? 0,
      total: (j['total'] as num?)?.toInt() ?? 0,
      nights: nights,
      naps: grouped.naps,
      napTimes: grouped.napTimes,
      heart: heart,
      spo2: spo2,
      skin: skin,
      energy: [
        for (final e in list('energy'))
          if (e is List && e.length >= 2 && okTime(e[0])) DayValue(dayOf(t(e[0])), (e[1] as num).toDouble()),
      ],
      steps: [
        for (final e in list('steps'))
          if (e is List && e.length >= 2 && okTime(e[0])) DayValue(dayOf(t(e[0])), (e[1] as num).toDouble()),
      ],
      floors: [
        for (final entry in floorsByDay.entries) DayValue(entry.key, entry.value),
      ]..sort((a, b) => a.day.compareTo(b.day)),
      body: body,
      bodyOther: allBody.length - body.length,
      otherBodyDays: {for (final b in allBody) if (!isScaleApp(b.app)) dateKey(b.time)},
      activity: j['activity'] is Map<String, dynamic> ? j['activity'] as Map<String, dynamic> : const {},
      sleepRecords: records,
      stepsByMinute: stepsByMinute,
      stepsMinuteFrom: stepsFrom,
      activityDaily: [
        for (final e in list('activityDaily'))
          if (e is List && e.length >= 3 && okTime(e[0])) (dayOf(t(e[0])), (e[1] as num?)?.toInt(), (e[2] as num?)?.toDouble()),
      ],
      exercise: [
        for (final e in list('exercise'))
          if (e is List && e.length >= 2 && okTime(e[0]) && okTime(e[1])) (t(e[0]), t(e[1])),
      ],
    );
  }

  /// Ο ύπνος ομαδοποιείται σε νύχτες με τον ΕΝΑΝ κανόνα, κοινό με το Oura ([groupSleepPieces], έλεγχος 3, E1):
  /// - Η διάρκεια είναι **μόνο** ό,τι μέτρησε η Samsung (πραγματικός ύπνος από τις φάσεις). Τα κενά ανάμεσα στα
  ///   κομμάτια **δεν** μετρούν ποτέ ως ύπνος.
  /// - Κύρια ομάδα = τα περισσότερα λεπτά ύπνου μέσα στο 22:00–08:00· πριν από αυτήν μπαίνει ό,τι αρχίζει από τις 20:00
  ///   με κενό ως 4 ώρες, μετά από αυτήν ό,τι αρχίζει πριν από τις 06:00 με κενό ως 4 ώρες, ή από τις 06:00 με κενό ως
  ///   90 λεπτά και ως 30 βήματα (ή άγνωστα βήματα)· όλα τα άλλα είναι υπνάκοι ([Night.napMinutes], αποθηκεύονται
  ///   χωριστά ως napMin).
  /// - Η απόφαση «υπνάκος λόγω βημάτων» κλειδώνει ([Night.napLock] → [K.napLock], [napLocks] στην επόμενη ανάγνωση).
  /// - Βήματα και παλμοί κρίνουν επίσης την ετικέτα του κενού («πιθανός ύπνος» ή «κενό»), που δεν μετρά.
  static ({List<Night> nights, Map<DateTime, int> naps, Map<DateTime, List<(DateTime, DateTime, int)>> napTimes}) _groupNights(
    List<SleepRecord> records, {
    List<Sample> heart = const [],
    Map<int, int> stepsByMinute = const {},
    DateTime? stepsFrom,
    Map<String, int> napLocks = const {},
  }) {
    final recs = dedupeSleep(records);
    // Ο ΕΝΑΣ κανόνας της νύχτας (sleep_gaps.dart, [groupSleepPieces]), ίδιος με του Oura. Τα βήματα κρίνουν μόνο το
    // πρωινό κομμάτι (κενό ως 90′) και την ετικέτα του κενού, ποτέ τα κομμάτια 20:00–06:00.
    final grouped = groupSleepPieces<SleepRecord>(
      recs,
      (r) => (start: r.start, end: r.end, minutes: r.sleepMinutes),
      stepsBetween: (a, b) => gapSteps(a, b, stepsByMinute: stepsByMinute, stepsFrom: stepsFrom),
      napLockOf: (date) {
        final m = napLocks[dateKey(date)];
        return m == null ? null : DateTime.fromMillisecondsSinceEpoch(m * 60000);
      },
    );
    final naps = <DateTime, int>{
      for (final e in grouped.naps.entries) e.key: e.value.fold(0, (sum, r) => sum + r.sleepMinutes),
    };
    final napTimes = <DateTime, List<(DateTime, DateTime, int)>>{};
    for (final e in grouped.naps.entries) {
      final out = <(DateTime, DateTime, int)>[];
      for (final r in [...e.value]..sort((a, b) => a.start.compareTo(b.start))) {
        if (out.isNotEmpty && !r.start.isAfter(out.last.$2)) {
          final l = out.removeLast();
          out.add((l.$1, r.end.isAfter(l.$2) ? r.end : l.$2, l.$3 + r.sleepMinutes));
        } else {
          out.add((r.start, r.end, r.sleepMinutes));
        }
      }
      napTimes[e.key] = out;
    }

    final nights = <Night>[];
    for (final g in grouped.nights) {
      final n = Night(g.date)..napLock = g.napLock;
      for (final seg in g.segments) {
        // Μόνο η ετικέτα του κενού κρίνεται με βήματα και παλμούς («πιθανός ύπνος»)· δεν μετρά ποτέ στη διάρκεια.
        var reach = seg.first.end;
        for (var i = 1; i < seg.length; i++) {
          final r = seg[i];
          if (r.start.isAfter(reach) &&
              judgeGap(seg[i - 1], r, heart: heart, stepsByMinute: stepsByMinute, stepsFrom: stepsFrom) == GapVerdict.asleep) {
            n.estimatedGaps.add((reach, r.start));
          }
          if (r.end.isAfter(reach)) reach = r.end;
        }
        n.parts.addAll(seg);
      }
      nights.add(n);
    }
    nights.sort((a, b) => a.date.compareTo(b.date));

    for (final n in nights) {
      n.parts.sort((a, b) => a.start.compareTo(b.start));
      n.estimatedGaps.sort((a, b) => a.$1.compareTo(b.$1));
      n.start = n.parts.first.start;
      n.end = n.parts.map((p) => p.end).reduce((a, b) => a.isAfter(b) ? a : b);
      // Πραγματικός ύπνος: δευτερόλεπτα από τις φάσεις (στρογγυλεύονται μία φορά). Κομμάτι χωρίς φάσεις μέσα σε νύχτα
      // με φάσεις (C2/C3): δεν μηδενίζει τη νύχτα· μετρά ό,τι έχει φάσεις και η νύχτα σημειώνεται «μερικώς χωρίς
      // φάσεις» ([Night.partial]). Νύχτα χωρίς καθόλου φάσεις: η διάρκεια της Samsung (με τα ξυπνήματα, [Night.staged]
      // false). Τα κενά ανάμεσα στα κομμάτια δεν μετρούν ποτέ.
      var asleep = 0;
      var other = 0;
      var unstagedParts = 0;
      for (final p in n.parts) {
        final a = p.asleepSeconds;
        if (a == null) {
          other += p.minutes;
          unstagedParts++;
        } else {
          asleep += a;
        }
      }
      n.staged = unstagedParts < n.parts.length;
      n.partial = n.staged && unstagedParts > 0;
      n.minutes = n.staged ? (asleep / 60).round() : other;
      n.spanMinutes = n.parts.fold(0, (sum, p) => sum + p.end.difference(p.start).inMinutes);
      var between = 0;
      var reach = n.parts.first.end;
      for (final p in n.parts.skip(1)) {
        if (p.start.isAfter(reach)) between += p.start.difference(reach).inMinutes;
        if (p.end.isAfter(reach)) reach = p.end;
      }
      n.betweenMinutes = math.max(0, between - n.estimatedMinutes);
      // Βαθμολογία: της Samsung μόνο όταν η νύχτα είναι ένα κομμάτι. Σε σπασμένη νύχτα η Samsung
      // βαθμολογεί κάθε κομμάτι χωριστά· κανένα από αυτά δεν είναι η βαθμολογία της νύχτας.
      n.score = n.parts.length == 1 ? n.parts.single.score : null;
      for (final p in n.parts) {
        n.stages.addAll(p.stages);
      }
      n.stages.sort((a, b) => a.start.compareTo(b.start));
      for (final s in n.stages) {
        n.stageSeconds[s.name] = (n.stageSeconds[s.name] ?? 0) + s.end.difference(s.start).inSeconds;
      }
      for (final e in n.stageSeconds.entries) {
        n.stageMinutes[e.key] = (e.value / 60).round();
      }
      n.napMinutes = naps[n.date] ?? 0;
    }
    return (nights: nights, naps: naps, napTimes: napTimes);
  }

  static void _fillNightMetrics(Night n, List<Sample> heart, List<Sample> spo2, List<Sample> skin) {
    bool inside(Sample s) => n.parts.any((p) => s.start.isBefore(p.end) && s.end.isAfter(p.start));

    final hr = heart.where(inside).map((s) => s.avg).toList();
    n.sleepingHr = hr.isEmpty ? null : hr.reduce((a, b) => a + b) / hr.length;

    final ox = oxygenOf(spo2.where(inside).toList());
    if (ox != null) {
      n.spo2Avg = ox.avg;
      n.spo2Min = ox.min;
      n.spo2Below90 = ox.below90;
    }

    final st = skin.where(inside).map((s) => s.avg).toList();
    n.skinTemp = st.isEmpty ? null : st.reduce((a, b) => a + b) / st.length;
  }

  /// Οξυγόνο της νύχτας με ημερομηνία (πρωινό) [day] όσο ο ύπνος έρχεται από άλλη πηγή (Oura): οι τιμές μένουν
  /// ΜΟΝΟ του ρολογιού, αλλά «νύχτα» = οι μετρήσεις του ρολογιού μέσα στις ώρες της κύριας νύχτας του Oura
  /// ([windows], μόνο ώρες· ποτέ τιμές του Oura). Χωρίς νύχτα του Oura δεν ξέρουμε πότε κοιμήθηκες: κενό
  /// (όχι «18:00–12:00», που θα έπιανε και μετρήσεις της μέρας). Δες [oxygenOf] για μέσο όρο και ελάχιστο.
  /// Έλεγχος 3, S5: νύχτα του Oura σε κομμάτια → οι μετρήσεις μέσα σε ΟΠΟΙΟΔΗΠΟΤΕ κομμάτι που μετρά
  /// ([SleepWindows.nightPieces], η ένωσή τους), ποτέ μέσα στο κενό ανάμεσα. Ίδιος κανόνας με τη νύχτα του ρολογιού.
  NightOxygen? watchSpo2(DateTime day, SleepWindows windows) {
    final parts = windows.nightPieces(dateKey(day));
    if (parts.isEmpty) return null;
    // Μέσα σε ένα κομμάτι: με διάρκεια που το τέμνει, ή στιγμιαία μέσα του.
    bool inside(Sample s) => parts.any((w) {
          final (from, to) = w;
          return s.start.isBefore(to) && (s.end.isAfter(from) || (s.end == s.start && !s.start.isBefore(from)));
        });
    return oxygenOf([for (final s in spo2) if (inside(s)) s]);
  }

  /// Η χαμηλότερη μέτρηση οξυγόνου του ρολογιού ανά νύχτα, για τις σημειώσεις χαμηλού οξυγόνου (B7), με τον ίδιο
  /// ορισμό που δείχνουν οι κάρτες (A4): οι [oxygenLongWindowNights] νύχτες ως και την [last] (30: ο κανόνας «κάτω
  /// από 80% σε 2 από τις 30», δεύτερος κλινικός έλεγχος K2)· νύχτες του ρολογιού, ή
  /// — με [ouraNights] — οι μετρήσεις του ρολογιού μέσα στις ώρες ύπνου του Oura ([windows]).
  /// Έλεγχος 3, E5: ΟΛΕΣ οι 30 νύχτες, πάνω από τη σύνδεση του Oura και το όριο της επανανάγνωσης (ίδιος αισθητήρας,
  /// όπως η αναφορά γιατρού): νύχτα που δεν υπάρχει στην ανάγνωση (π.χ. πριν από το Oura) παίρνει την τιμή του
  /// ρολογιού από το [history] (K.spo2Min, πάντα του ρολογιού). Το ελάχιστο μετρά και σε νύχτα με μόνο σύντομες
  /// μετρήσεις (χωρίς μέσο όρο).
  Map<DateTime, double> spo2MinByNight(
    DateTime last, {
    bool ouraNights = false,
    SleepWindows windows = SleepWindows.empty,
    Map<String, Map<String, double>> history = const {},
  }) {
    final out = <DateTime, double>{};
    final end = dayOf(last);
    for (var i = 0; i < oxygenLongWindowNights; i++) {
      final day = DateTime(end.year, end.month, end.day - i);
      double? min;
      if (ouraNights) {
        min = watchSpo2(day, windows)?.min;
      } else {
        for (final n in nights) {
          if (sameDay(n.date, day)) min = n.spo2Min;
        }
      }
      min ??= history[dateKey(day)]?[K.spo2Min];
      if (min != null && min.isFinite) out[day] = min;
    }
    return out;
  }

  // ---------- Υπολογισμοί για τις οθόνες ----------

  /// Η πιο πρόσφατη νύχτα (συνήθως η χθεσινή).
  Night? get lastNight => nights.isEmpty ? null : nights.last;

  /// Οι νύχτες πριν από την τελευταία (για σύγκριση), έως [count].
  List<Night> previousNights([int count = 7]) {
    if (nights.length < 2) return const [];
    final prev = nights.sublist(0, nights.length - 1);
    return prev.length <= count ? prev : prev.sublist(prev.length - count);
  }

  static double? mean(Iterable<double?> values) {
    final v = values.whereType<double>().toList();
    if (v.isEmpty) return null;
    return v.reduce((a, b) => a + b) / v.length;
  }

  /// Οι νύχτες πριν από τη νύχτα [date] (ποτέ η ίδια μέσα στο «συνηθισμένο» της).
  Iterable<Night> nightsBefore(DateTime date) => nights.where((n) => n.date.isBefore(dayOf(date)));

  /// «Συνήθως» για τη διάρκεια της τελευταίας νύχτας ([usualMean]: τουλάχιστον 7 προηγούμενες νύχτες).
  /// Μόνο νύχτες με φάσεις (πραγματικός ύπνος): μια νύχτα χωρίς φάσεις έχει διάρκεια με τα ξυπνήματα.
  double? get sleepBaseline => lastNight == null
      ? null
      : usualMean(nightsBefore(lastNight!.date).where((n) => n.staged).map((n) => n.minutes.toDouble()));

  double? get restingHrBaseline => lastNight == null ? null : restingHrBaselineFor(lastNight!.date);

  /// Ο μέσος όρος παλμών ύπνου πριν από τη νύχτα [date] (η νύχτα που δείχνουμε, όχι απαραίτητα η τελευταία).
  double? restingHrBaselineFor(DateTime date) => usualMean(nightsBefore(date).map((n) => n.sleepingHr));

  double? get skinTempBaseline =>
      lastNight == null ? null : usualMean(nightsBefore(lastNight!.date).map((n) => n.skinTemp));

  DayValue? valueFor(List<DayValue> list, DateTime day) {
    for (final v in list.reversed) {
      if (sameDay(v.day, day)) return v;
    }
    return null;
  }

  DayValue? get latestEnergy => energy.isEmpty ? null : energy.last;

  double? get todaySteps => valueFor(steps, readAt)?.value;

  double? get stepsBaseline => usualMean(steps.where((s) => s.day.isBefore(dayOf(readAt))).map((s) => s.value));

  /// Ελάχιστοι και μέγιστοι παλμοί μιας ημέρας. [exclude]: χρονικά διαστήματα (π.χ. ο ύπνος από το Oura)
  /// που δεν μετρούν, ώστε το «χαμηλότερο της μέρας» να μην είναι παλμός του ύπνου.
  (double, double)? heartRange(DateTime day, {List<(DateTime, DateTime)> exclude = const []}) {
    final s = heart
        .where((h) => sameDay(h.start, day) && !exclude.any((r) => h.start.isBefore(r.$2) && h.end.isAfter(r.$1)))
        .toList();
    if (s.isEmpty) return null;
    return (s.map((h) => h.min).reduce(math.min), s.map((h) => h.max).reduce(math.max));
  }

  Sample? get latestHeart => heart.isEmpty ? null : heart.last;

  BodyMeasurement? get latestBody => body.isEmpty ? null : body.last;

  BodyMeasurement? get previousBody => body.length < 2 ? null : body[body.length - 2];
}

// ---------------------------------------------------------------------------
// Ρυθμίσεις «Τι βλέπω»
// ---------------------------------------------------------------------------

class TodayCard {
  const TodayCard(this.key, this.label, this.defaultOn);
  final String key;
  final String label;
  final bool defaultOn;
}

const todayCards = <TodayCard>[
  TodayCard('sleep', 'Ύπνος της νύχτας', true),
  TodayCard('unusual', 'Εκτός συνηθισμένου (όταν ξεφεύγουν μαζί παλμοί ύπνου και θερμοκρασία)', true),
  TodayCard('week', 'Απολογισμός εβδομάδας (Κυριακή βράδυ και Δευτέρα)', true),
  TodayCard('food', 'Διατροφή της ημέρας', true),
  TodayCard('steps', 'Βήματα', true),
  TodayCard('weight', 'Βάρος', true),
  TodayCard('energy', 'Energy Score', false),
  TodayCard('rhr', 'Παλμοί στον ύπνο', false),
  TodayCard('calories', 'Θερμίδες που έκαψα', false),
  TodayCard('spo2', 'Οξυγόνο στον ύπνο (εμφανίζεται μόνο του όταν επαναλαμβάνεται χαμηλό)', false),
  TodayCard('skin', 'Θερμοκρασία καρπού στον ύπνο', false),
];

/// Έκδοση της διάταξης του «Σήμερα». Στη 2 (νέα δομή, 24/10) το Energy Score, οι παλμοί
/// και οι θερμίδες φεύγουν από την αρχική (υπάρχουν στην Υγεία και στην Άσκηση)· μπαίνουν ξανά από τις Ρυθμίσεις.
const todayLayout = 2;

class Prefs {
  Prefs(this.cards,
      {this.backfillFrom,
      this.kitchen,
      this.reportName,
      this.reportNameKnown = false,
      this.themeMode = 'auto',
      this.dayTheme = 'aigaio',
      this.nightTheme = 'aigaio',
      this.historyVersion = 1,
      this.recentTo,
      this.gapFrom,
      this.gapTo,
      this.emptyFrom,
      this.emptyChecked,
      SourcePlan? plan,
      this.ouraSynced,
      this.ouraSyncedTo,
      this.ouraTried,
      this.ouraBackoff,
      this.planAt,
      this.ouraErr,
      this.ouraConnected,
      this.dbReset,
      this.rereadVersion,
      this.ouraRefetchTo,
      this.ouraRules = 0,
      Map<String, int>? monthFails,
      List<String>? staleMonths})
      : plan = plan ?? SourcePlan.samsungOnly,
        monthFails = monthFails ?? {},
        staleMonths = staleMonths ?? [];

  factory Prefs.fromJson(Map<String, dynamic> j) {
    final saved = j['cards'] is Map ? j['cards'] as Map : const {};
    final layout = (j['layout'] as num?)?.toInt() ?? 1;
    // Κάρτες που η νέα διάταξη βγάζει από την αρχική: μία φορά στην προεπιλογή τους.
    const movedOut = {'energy', 'rhr', 'calories'};
    return Prefs(
      {
        for (final c in todayCards)
          c.key: (layout < todayLayout && movedOut.contains(c.key)) || saved[c.key] is! bool
              ? c.defaultOn
              : saved[c.key] as bool,
      },
      backfillFrom: j['backfillFrom'] is String ? j['backfillFrom'] as String : null,
      kitchen: j['kitchen'] is Map ? Map<String, dynamic>.from(j['kitchen'] as Map) : null,
      reportName: j['reportName'] is String ? j['reportName'] as String : null,
      reportNameKnown: true,
      themeMode: const ['auto', 'light', 'dark'].contains(j['themeMode']) ? j['themeMode'] as String : 'auto',
      dayTheme: j['dayTheme'] is String ? j['dayTheme'] as String : 'aigaio',
      nightTheme: j['nightTheme'] is String ? j['nightTheme'] as String : 'aigaio',
      historyVersion: (j['historyVersion'] as num?)?.toInt() ?? 1,
      recentTo: j['recentTo'] is String ? j['recentTo'] as String : null,
      gapFrom: j['gapFrom'] is String ? j['gapFrom'] as String : null,
      gapTo: j['gapTo'] is String ? j['gapTo'] as String : null,
      emptyFrom: j['emptyFrom'] is String ? j['emptyFrom'] as String : null,
      emptyChecked: j['emptyChecked'] is String ? j['emptyChecked'] as String : null,
      plan: SourcePlan.fromJson(j['sources']),
      ouraSynced: (j['ouraSynced'] as num?)?.toInt(),
      ouraSyncedTo: j['ouraSyncedTo'] is String ? j['ouraSyncedTo'] as String : null,
      ouraTried: (j['ouraTried'] as num?)?.toInt(),
      ouraBackoff: (j['ouraBackoff'] as num?)?.toInt(),
      planAt: (j['sourcesAt'] as num?)?.toInt(),
      ouraErr: j['ouraErr'] is String ? j['ouraErr'] as String : null,
      ouraConnected: (j['ouraConnected'] as num?)?.toInt(),
      dbReset: (j['dbReset'] as num?)?.toInt(),
      rereadVersion: (j['rereadVersion'] as num?)?.toInt(),
      ouraRefetchTo: j['ouraRefetchTo'] is String ? j['ouraRefetchTo'] as String : null,
      ouraRules: (j['ouraRules'] as num?)?.toInt() ?? 0,
      monthFails: {
        if (j['monthFails'] is Map)
          for (final e in (j['monthFails'] as Map).entries)
            if (e.key is String && e.value is num) e.key as String: (e.value as num).toInt(),
      },
      staleMonths: [
        if (j['staleMonths'] is List)
          for (final m in j['staleMonths'] as List) if (m is String) m,
      ],
    );
  }

  /// Έλεγχος 2, C12: με ποιους κανόνες γράφτηκαν οι τιμές «o.*» (δες [ouraRulesVersion]).
  int ouraRules;

  /// Έλεγχος 2, C9: ως πού μένει να ξαναδιαβαστεί το Oura πιο πίσω από τις 90 μέρες (μετά από καινούργια βάση).
  String? ouraRefetchTo;

  /// Έλεγχος 2, C4: η έκδοση κανόνων που ξαναϋπολογίζεται τώρα (null = καμία). Η [historyVersion] αλλάζει ΜΟΝΟ όταν
  /// ξαναδιαβαστεί ΟΛΟ το ιστορικό· ως τότε οι μέρες πριν από το [backfillFrom] έχουν τον παλιό ορισμό.
  int? rereadVersion;

  /// Αποτυχίες ανά κομμάτι της επανανάγνωσης (κλειδί: η μέρα-δείκτης «2026-10-01»), αποθηκευμένες: μια επανεκκίνηση
  /// της εφαρμογής δεν τις μηδενίζει (πριν: μόνο στη μνήμη, και ο ίδιος μήνας ξαναδοκιμαζόταν για πάντα).
  final Map<String, int> monthFails;

  /// Κομμάτια («2026-10-01» = οι 30 μέρες ως εκείνη τη μέρα) που απέτυχαν 3 φορές και κράτησαν τις παλιές τιμές
  /// ύπνου: φαίνονται στις Τάσεις («δεν ξαναϋπολογίστηκαν»), ποτέ σιωπηλά.
  final List<String> staleMonths;

  /// Για ποια χαλασμένη βάση (ώρα, ms) ξεκίνησε ήδη η ξαναδιάβαση του ιστορικού (A7): μία φορά για κάθε βλάβη.
  int? dbReset;

  /// ΑΝΤΙΓΡΑΦΟ του σχεδίου πηγών. Το κύριο είναι στο δικό του αρχείο (plan_file.dart)· αυτό χρησιμεύει μόνο
  /// αν εκείνο χαθεί και οι ρυθμίσεις διαβάστηκαν κανονικά.
  SourcePlan plan;

  /// Πότε ορίστηκε το [plan] (ms): για να διαλέγεται το νεότερο αντίγραφο αν χαθεί το αρχείο.
  int? planAt;

  /// Το είδος του τελευταίου σφάλματος του Oura (π.χ. «auth», «rate»), δίπλα στην αναμονή: μετά από
  /// επανεκκίνηση η κάρτα λέει το ίδιο. Ποτέ κείμενο ή τιμές.
  String? ouraErr;

  /// Πότε ολοκληρώθηκε η σύνδεση του Oura (ms): για το «η νύχτα που κοιμάσαι τώρα».
  int? ouraConnected;

  /// Πότε δοκιμάστηκε τελευταία φορά ανάγνωση του Oura (ms, με ή χωρίς επιτυχία) και ως πότε περιμένουμε (ms).
  int? ouraTried;
  int? ouraBackoff;

  /// Πότε διαβάστηκε τελευταία φορά το Oura με επιτυχία (ms) και ως ποια μέρα («2026-11-07»).
  int? ouraSynced;
  String? ouraSyncedTo;

  /// Κενό στο ιστορικό από όσο έμεινε κλειστή η εφαρμογή: από [gapFrom] ως τη μέρα −30.
  /// [gapTo]: ως πού (από πάνω) έχει ήδη διαβαστεί.
  String? gapFrom;
  String? gapTo;

  /// Από πού και πίσω δεν βρέθηκε τίποτα (2 χρόνια άδεια), και πότε κοιτάχτηκε (ξανά σε έναν μήνα).
  String? emptyFrom;
  String? emptyChecked;

  /// Η τελευταία μέρα που γράφτηκε από την κανονική ανάγνωση («2026-11-01»). Αν η εφαρμογή μείνει
  /// κλειστή πάνω από 29 μέρες, το ιστορικό ξαναδιαβάζεται, ώστε να μη μείνουν κενές μέρες.
  String? recentTo;

  /// Με ποιους κανόνες υπολογίστηκε το αποθηκευμένο ιστορικό (δες historyRulesVersion).
  int historyVersion;

  /// Εμφάνιση: «auto» (όπως το κινητό), «light» ή «dark»· και ποιο θέμα τη μέρα και τη νύχτα.
  String themeMode;
  String dayTheme;
  String nightTheme;

  /// «Η κουζίνα μου» (δες food/kitchen.dart), όπως αποθηκεύεται.
  Map<String, dynamic>? kitchen;

  /// Όνομα για την αναφορά γιατρού (προαιρετικό). Μένει μόνο στο κινητό: ΔΕΝ μπαίνει στο αρχείο αντιγράφου
  /// ασφαλείας (backupPrefKeys), ούτε σε αναφορά σφάλματος, ούτε στο αντίγραφο Google/μεταφορά του Android (η Kotlin
  /// το γράφει χωριστά στο noBackupFilesDir, DataRules.splitDeviceOnlyPrefs· συγχώνευση 4/11).
  String? reportName;

  /// Έλεγχος 3, E6: το [reportName] είναι γνωστό (ήρθε από τις αποθηκευμένες ρυθμίσεις ή το άλλαξε ο χρήστης). Μόνο
  /// τότε γράφεται (και το null σημαίνει «σβήσ' το»)· με ρυθμίσεις από προεπιλογές (χαλασμένο prefs.json) το κλειδί
  /// λείπει και η Kotlin αφήνει το όνομα στο κινητό όπως είναι (πριν το έσβηνε).
  bool reportNameKnown;

  final Map<String, bool> cards;

  /// Ως πού έχει φτάσει το ιστορικό προς τα πίσω («2025-11-01»).
  String? backfillFrom;

  bool show(String key) => cards[key] ?? true;

  String toJson() =>
      jsonEncode({
        'layout': todayLayout,
        'cards': cards,
        'backfillFrom': backfillFrom,
        'kitchen': kitchen,
        if (reportNameKnown) 'reportName': reportName,
        'themeMode': themeMode,
        'dayTheme': dayTheme,
        'nightTheme': nightTheme,
        'historyVersion': historyVersion,
        'recentTo': recentTo,
        'gapFrom': gapFrom,
        'gapTo': gapTo,
        'emptyFrom': emptyFrom,
        'emptyChecked': emptyChecked,
        if (plan.eras.isNotEmpty || planAt != null) 'sources': plan.toJson(),
        if (planAt != null) 'sourcesAt': planAt,
        if (ouraErr != null) 'ouraErr': ouraErr,
        if (ouraConnected != null) 'ouraConnected': ouraConnected,
        if (ouraSynced != null) 'ouraSynced': ouraSynced,
        if (ouraSyncedTo != null) 'ouraSyncedTo': ouraSyncedTo,
        if (ouraTried != null) 'ouraTried': ouraTried,
        if (ouraBackoff != null) 'ouraBackoff': ouraBackoff,
        if (dbReset != null) 'dbReset': dbReset,
        if (rereadVersion != null) 'rereadVersion': rereadVersion,
        if (ouraRefetchTo != null) 'ouraRefetchTo': ouraRefetchTo,
        if (ouraRules != 0) 'ouraRules': ouraRules,
        if (monthFails.isNotEmpty) 'monthFails': monthFails,
        if (staleMonths.isNotEmpty) 'staleMonths': staleMonths,
      });
}

/// Έλεγχος 2, C12: έκδοση των κανόνων για τις τιμές του Oura στο ιστορικό. 1: ποσοστά φάσεων επί του πραγματικού
/// ύπνου (η #66 τα έγραφε επί του χρόνου με τα ξυπνήματα) και ο κοινός κανόνας νύχτας με το ρολόι (συγχώνευση 4/11:
/// κομμάτια ως 4 ώρες μαζί, υπνάκοι μόνο λαγοκοίμισμα ως τις 22:00 / πρωί / απόγευμα). Όταν αλλάζει, το Oura
/// ξαναδιαβάζεται από την αρχή του.
const ouraRulesVersion = 1;

/// Μια απάντηση της Samsung, διαβασμένη: [status] (ok ή το σφάλμα), [data] αν ήταν εντάξει,
/// [sleepFailed] αν κάποιο είδος του ύπνου δεν διαβάστηκε (δες sleepReadFailed), [heartFailed] αν οι παλμοί
/// δεν διαβάστηκαν (δες heartReadFailed).
/// [rows]: οι συνόψεις των 30 ημερών, υπολογισμένες στο ίδιο νήμα με το διάβασμα (A9), αν ζητήθηκαν.
typedef ParsedDashboard = ({
  Map<String, dynamic> status,
  Dashboard? data,
  bool sleepFailed,
  bool heartFailed,
  Map<String, Map<String, double>>? rows,
  bool sleepFilterEmpty,
});

/// Έλεγχος 3, E3: ο ύπνος της κανονικής ανάγνωσης γύρισε «φίλτρο ρολογιού άδειο» (C6): το φίλτρο ίσως δεν βρίσκει το
/// ρολόι σου. Όσο ισχύει, η συμπλήρωση/επανανάγνωση ΔΕΝ τρέχει (εκεί ένα άδειο αποτέλεσμα θα γινόταν δεκτό ως «χωρίς
/// ρολόι» για όλο το ιστορικό).
bool sleepFilterEmpty(Map<String, dynamic> r) {
  final v = r['sleep'];
  return v is Map && '${v['error']}'.contains('watch_filter_empty');
}

/// Σε ξεχωριστό νήμα (isolate), ώστε το άνοιγμα να μην «παγώνει». Αν το νήμα δεν ξεκινήσει,
/// γίνεται εδώ (πιο αργά, αλλά ποτέ «κολλημένο»).
/// Με [plan] υπολογίζονται εκεί και οι συνόψεις των 30 ημερών (A9: όχι στο νήμα της οθόνης). Το αποτέλεσμα
/// επιστρέφει χωρίς αντιγραφή (Isolate.run).
Future<ParsedDashboard> parseDashboard(String raw,
    {SourcePlan? plan, SleepWindows windows = SleepWindows.empty, Map<String, int> napLocks = const {}}) async {
  try {
    return await Isolate.run(() => parseDashboardSync(raw, plan: plan, windows: windows, napLocks: napLocks));
  } catch (e, st) {
    _isolateFailed(e, st);
    return parseDashboardSync(raw, plan: plan, windows: windows, napLocks: napLocks);
  }
}

/// Έλεγχος 3, E1.6: οι αποθηκευμένες αποφάσεις «πρωινός υπνάκος» του ρολογιού ([K.napLock]) ανά νύχτα, για την
/// ομαδοποίηση ([Dashboard.fromJson]). [key]: «napLock» (ρολόι) ή «o.napLock» (Oura).
Map<String, int> napLocksOf(Map<String, Map<String, double>> history, {String key = K.napLock}) => {
      for (final e in history.entries)
        if (e.value[key] case final v? when v.isFinite) e.key: v.round(),
    };

/// Αν το νήμα δεν ξεκινά, η εφαρμογή δουλεύει (πιο αργά)· το λέμε στο Sentry μία φορά, για να το δούμε.
bool _isolateReported = false;
void _isolateFailed(Object e, StackTrace st) {
  if (_isolateReported) return;
  _isolateReported = true;
  errors.report(e, st, extra: {'where': 'isolate'});
}

/// Ένα κομμάτι ιστορικού από τη Samsung, διαβασμένο: συνόψεις ανά μέρα και αν διαβάστηκαν όλα.
typedef ParsedRange = ({
  bool ok,
  Map<String, Map<String, double>> rows,
  bool sleepOk,
  bool sleepFailed,
  bool heartFailed,
  bool anyError,
  Set<String> nonWatch,

  /// Έλεγχος 4 (red team M1): ο ύπνος «από άλλη συσκευή» γίνεται δεκτός μόνο αν το κομμάτι τελειώνει πριν από την
  /// πρώτη εγγραφή ύπνου ρολογιού όλου του ιστορικού («firstWatchSleep» της Kotlin, αριθμός).
  bool otherDeviceOk,

  /// Η Kotlin απάντησε ρητά null («καμία εγγραφή ρολογιού»). Review M2: δεν εμπιστευόμαστε μόνο αυτό (το ίδιο φίλτρο
  /// που μπορεί να έχει χαλάσει)· δεκτό μόνο αν το κομμάτι δεν έχει αποθηκευμένες νύχτες ρολογιού.
  bool noWatchSleep,
});

Future<ParsedRange> parseRange(String raw, DateTime from, DateTime to,
    {SourcePlan? plan, SleepWindows windows = SleepWindows.empty, Map<String, int> napLocks = const {}}) async {
  try {
    return await Isolate.run(() => parseRangeSync(raw, from, to, plan: plan, windows: windows, napLocks: napLocks));
  } catch (e, st) {
    _isolateFailed(e, st);
    return parseRangeSync(raw, from, to, plan: plan, windows: windows, napLocks: napLocks);
  }
}

ParsedRange parseRangeSync(String raw, DateTime from, DateTime to,
    {SourcePlan? plan, SleepWindows windows = SleepWindows.empty, Map<String, int> napLocks = const {}}) {
  const fail = (
    ok: false,
    rows: <String, Map<String, double>>{},
    sleepOk: false,
    sleepFailed: false,
    heartFailed: false,
    anyError: true,
    nonWatch: <String>{},
    otherDeviceOk: false,
    noWatchSleep: false,
  );
  try {
    final j = jsonDecode(raw);
    if (j is! Map<String, dynamic> || j['ok'] != true) return fail;
    final d = Dashboard.fromJson(j, napLocks: napLocks);
    return (
      ok: true,
      rows: summarizeRange(d, from, to, plan: plan, windows: windows),
      sleepOk: d.sleepOk,
      sleepFailed: sleepReadFailed(j),
      heartFailed: heartReadFailed(j),
      anyError: d.failed.isNotEmpty,
      // E3: είδη με δεδομένα μόνο από άλλη συσκευή σε αυτό το κομμάτι (δεκτό: «χωρίς δεδομένα ρολογιού εδώ»).
      nonWatch: {for (final x in (j['nonWatch'] is List ? j['nonWatch'] as List : const [])) if (x is String) x},
      // Μόνο με γνωστή απάντηση: αριθμός (η πρώτη εγγραφή ρολογιού) ή ρητό null (καμία). Σφάλμα ή απουσία = άγνωστο.
      otherDeviceOk: j['firstWatchSleep'] is num &&
          dayOf(to).isBefore(dayOf(DateTime.fromMillisecondsSinceEpoch((j['firstWatchSleep'] as num).toInt()))),
      noWatchSleep: j.containsKey('firstWatchSleep') && j['firstWatchSleep'] == null,
    );
  } catch (_) {
    return fail;
  }
}

/// Πόσες μέρες (ως σήμερα) ξαναγράφονται από την κανονική ανάγνωση.
const recentSummaryDays = 30;

/// [plan]/[windows]: αν δοθούν, υπολογίζονται και οι συνόψεις των 30 ημερών ([ParsedDashboard.rows]).
ParsedDashboard parseDashboardSync(String raw,
    {SourcePlan? plan, SleepWindows windows = SleepWindows.empty, Map<String, int> napLocks = const {}}) {
  Object? j;
  try {
    j = jsonDecode(raw);
  } catch (e) {
    return (status: {'ok': false, 'kind': 'other', 'message': 'Χαλασμένη απάντηση'}, data: null, sleepFailed: false, heartFailed: false, rows: null, sleepFilterEmpty: false);
  }
  if (j is! Map<String, dynamic>) {
    return (status: {'ok': false, 'kind': 'other', 'message': 'Κενή απάντηση'}, data: null, sleepFailed: false, heartFailed: false, rows: null, sleepFilterEmpty: false);
  }
  if (j['ok'] != true) {
    return (
      status: {for (final k in const ['ok', 'kind', 'message', 'code', 'resolvable']) if (j.containsKey(k)) k: j[k]},
      data: null,
      sleepFailed: false,
      heartFailed: false,
      rows: null,
      sleepFilterEmpty: false,
    );
  }
  try {
    final d = Dashboard.fromJson(j, napLocks: napLocks);
    final today = dayOf(d.readAt);
    return (
      status: const {'ok': true},
      data: d,
      sleepFailed: sleepReadFailed(j),
      heartFailed: heartReadFailed(j),
      rows: plan == null
          ? null
          : summarizeRange(d, DateTime(today.year, today.month, today.day - recentSummaryDays + 1), today,
              plan: plan, windows: windows),
      sleepFilterEmpty: sleepFilterEmpty(j),
    );
  } catch (e) {
    return (status: {'ok': false, 'kind': 'other', 'message': e.toString()}, data: null, sleepFailed: false, heartFailed: false, rows: null, sleepFilterEmpty: false);
  }
}

/// Μια κανονική ανάγνωση (30 μέρες + όλες οι ζυγίσεις) στο ιστορικό. Επιστρέφει τις μέρες που άλλαξαν.
/// - Οι 30 μέρες περνούν από το [mergeHistory] (ύπνος με κλειδωμένες αποφάσεις πρωινού υπνάκου, E1.6· πηγή κάθε νύχτας).
/// - Οι ζυγίσεις μπαίνουν ΧΩΡΙΣΤΑ ([mergeBody]): μία ολόκληρη ζύγιση InBody ανά μέρα, χωρίς να αγγίζεται τίποτα
///   άλλο της μέρας (A1: πριν, μια ζύγιση σε παλιά μέρα του Oura έσβηνε το οξυγόνο της νύχτας).
/// - Νύχτες με άλλη πηγή που είχαν ακόμα τιμές του ρολογιού: φεύγουν· ζύγιση που σβήστηκε στη Samsung: φεύγει
///   (με προφύλαξη, ως 3 μέρες μαζί).
Set<String> applyRecentRead(
  Map<String, Map<String, double>> history,
  Dashboard d, {
  required SourcePlan plan,
  SleepWindows windows = SleepWindows.empty,
  bool sleepFailed = false,
  bool heartFailed = false,
  Map<String, Map<String, double>>? rows,
  bool windowsComplete = true,
}) {
  final today = dayOf(d.readAt);
  // Από τη μέρα −29: η νύχτα της μέρας −30 μπορεί να ξεκίνησε πριν από την αρχή της ανάγνωσης. [rows]: ήδη
  // υπολογισμένες σε άλλο νήμα με το ΙΔΙΟ σχέδιο και τις ίδιες ώρες ύπνου (A9).
  rows ??= summarizeRange(d, DateTime(today.year, today.month, today.day - recentSummaryDays + 1), today,
      plan: plan, windows: windows);
  for (final r in rows.values) {
    r.removeWhere((k, _) => bodyKeys.contains(k));
  }
  // Όλες οι μέρες της ανάγνωσης ξαναγράφονται (όχι μόνο οι 7 με βήματα ανά λεπτό), όταν ο ύπνος διαβάστηκε κανονικά.
  // Τα βήματα κρίνουν μόνο το πρωινό κενό· η απόφαση που πάρθηκε με βήματα είναι κλειδωμένη στο ιστορικό ([K.napLock],
  // έλεγχος 3, E1.6), άρα η μέρα 8–29 χωρίς βήματα βγαίνει ίδια με τη μέρα 0–7.
  final windowFrom = DateTime(today.year, today.month, today.day - recentSummaryDays + 1);
  // Review M4: ίδιος κανόνας «πολύ λίγες νύχτες» με την επανανάγνωση. Αν το ιστορικό έχει ≥ 4 νύχτες ρολογιού στις 30
  // μέρες και η ανάγνωση δίνει έγκυρες λιγότερες από τις μισές (π.χ. Samsung Health μόλις επανεγκαταστάθηκε, νέο
  // κινητό που συγχρονίζει ακόμα), σαν σφάλμα ανάγνωσης του ύπνου: τίποτα δεν κρύβεται, οι τιμές μένουν.
  var hadNights = 0, gotNights = 0;
  for (var day = windowFrom; !day.isAfter(today); day = DateTime(day.year, day.month, day.day + 1)) {
    if (plan.nightSource(day) != Source.watch) continue;
    if (history[dateKey(day)]?.containsKey(K.sleepMin) ?? false) hadNights++;
    if (rows[dateKey(day)]?.containsKey(K.sleepMin) ?? false) gotNights++;
  }
  final tooFewNights = hadNights >= 4 && gotNights < hadNights / 2;
  final sleepFrom = !sleepFailed && d.sleepOk && !tooFewNights ? windowFrom : null;
  // Έλεγχος 4 (1_data M2): νύχτα του ρολογιού που τώρα ήρθε χωρίς έγκυρη διάρκεια (χωρίς φάσεις, άγνωστες φάσεις, ή
  // καθόλου): οι αποθηκευμένες τιμές ύπνου της μέρας κρατιούνται κρυφές («nw.*»), όπως στην επανανάγνωση· πριν
  // σβηνόταν η διάρκεια εδώ, ενώ η επανανάγνωση την κρατούσε ως ύπνο.
  final archived =
      sleepFrom == null ? <String>{} : archiveSleep(history, rows, from: sleepFrom, to: today, plan: plan);
  final changed = archived..addAll(mergeHistory(
    history,
    rows,
    sleepFrom: sleepFrom,
    plan: plan,
    keepKeys: heartFailed ? heartKeys : const {},
    ouraNights: windows.mains.keys.toSet(),
  ));
  // Έλεγχος 2, C12: παλμοί μέρας που είχαν γραφτεί από μισή μέρα (π.χ. το απόγευμα), ενώ τώρα δεν βγαίνουν επειδή
  // λείπει η νύχτα του Oura που χρειάζονται: φεύγουν (ο κανόνας λέει «χωρίς τιμή», όχι η παλιά μισή).
  // Μόνο με γνωστές ώρες ύπνου του Oura (το αρχείο νυχτών διαβάστηκε): αλλιώς δεν ξέρουμε ότι λείπει η νύχτα.
  // Έλεγχος 3, E4: ποτέ μετά από σφάλμα ανάγνωσης του αρχείου ([windowsComplete] false), και ποτέ για μέρα πριν από την
  // πρώτη νύχτα που ξέρουμε (ένα αρχείο με λίγες νύχτες δεν λέει τίποτα για τις παλιότερες).
  final known = windows.mains.keys.toList()..sort();
  if (!heartFailed && windowsComplete && known.isNotEmpty) {
    for (var day = DateTime(today.year, today.month, today.day - recentSummaryDays + 1);
        day.isBefore(today);
        day = DateTime(day.year, day.month, day.day + 1)) {
      final k = dateKey(day);
      if (k.compareTo(known.first) < 0) continue;
      final old = history[k];
      if (old == null || !old.keys.any(dayHeartKeys.contains) || (rows[k]?.containsKey(K.dayHr) ?? false)) continue;
      if (!dayHeartNeedsMissingWindow(plan, windows, day, today)) continue;
      history[k] = {for (final e in old.entries) if (!dayHeartKeys.contains(e.key)) e.key: e.value};
      changed.add(k);
    }
  }
  changed.addAll(mergeBody(history, bodyRows(d.body)));
  // Μέρες με άλλη πηγή ύπνου που είχαν ακόμα τιμές νύχτας του ρολογιού (π.χ. η μέρα της σύνδεσης): φεύγουν.
  final f = plan.eras.isEmpty ? null : plan.eras.first.from;
  if (f != null) changed.addAll(stripForeignWatchNight(history, plan, from: f));
  // Ζύγιση που σβήστηκε στη Samsung / InBody: φεύγει και από το ιστορικό (Τάσεις, αναφορά γιατρού).
  // Με προφύλαξη: αν η Samsung δεν δίνει καμία ζύγιση (π.χ. μόλις επανεγκαταστάθηκε) ή θα έφευγαν
  // πολλές μαζί, δεν σβήνεται τίποτα· μια λάθος ζύγιση που σβήνεις είναι μία-δύο μέρες.
  // Έλεγχος 3, E2: ζυγίσεις άλλων εφαρμογών (χειροκίνητο βάρος, BIA του ρολογιού) που είχαν γράψει παλιές εκδόσεις
  // ΔΕΝ σβήνονται ποτέ (πριν, το C5 τις έσβηνε από όλο το ιστορικό, και όλες αν δεν βρισκόταν καμία ζύγιση InBody).
  // Μετρούν ως «υπάρχουν ακόμα» ([Dashboard.otherBodyDays]) και απλώς δεν φαίνονται από την πρώτη ζύγιση InBody και
  // μετά ([SourcePlan.scaleFrom], σημάδι [K.inbody]).
  if (d.bodyOk && d.body.isNotEmpty) {
    final days = {for (final b in d.body) dateKey(b.time), ...d.otherBodyDays};
    final from = DateTime(today.year - 10, today.month, today.day + 1);
    final copy = {for (final e in history.entries) e.key: e.value};
    final gone = removeMissingBody(copy, days, from: from);
    if (gone.isNotEmpty && gone.length <= 3) changed.addAll(removeMissingBody(history, days, from: from));
  }
  return changed;
}

// ---------------------------------------------------------------------------
// Η κατάσταση της εφαρμογής: διαβάζει όταν ανοίγει και όταν επιστρέφω σε αυτήν. Στο παρασκήνιο μόνο
// ο RefreshWorker (Android) ανανεώνει κάθε 3 ώρες το βοηθητικό αρχείο· το ιστορικό γράφεται εδώ.
// ---------------------------------------------------------------------------

class HealthStore extends ChangeNotifier with WidgetsBindingObserver, OuraStore {
  /// Τα δεδομένα της Samsung για τις οθόνες, χωρισμένα πάντα κατά το σχέδιο πηγών ([Dashboard.restrict]).
  /// Το ιστορικό υπολογίζεται από τα πλήρη ([_raw]) με το σχέδιο πηγών.
  Dashboard? get data => _data;
  set data(Dashboard? d) {
    _raw = d;
    _data = d?.restrict(_plan);
  }

  Dashboard? _data;
  Dashboard? _raw;
  bool loading = false;
  Map<String, dynamic>? error;
  Prefs prefs = Prefs.fromJson(const {});
  DateTime? _lastRefresh;

  /// Ημερήσιες συνόψεις: «2026-10-24» → τιμές (δες history.dart).
  @override
  Map<String, Map<String, double>> history = {};

  /// Το σχέδιο πηγών: από το δικό του αρχείο (plan_file.dart). Ως να διαβαστεί, τίποτα δεν γράφεται.
  @override
  /// Το σχέδιο πηγών, με το όριο της ζυγαριάς από το ιστορικό (έλεγχος 3, E2: [SourcePlan.scaleFrom]).
  SourcePlan get plan {
    final s = _scaleFrom;
    if (s == null) return _plan;
    final c = _planView;
    if (c != null && identical(_planViewBase, _plan) && c.scaleFrom == s) return c;
    _planViewBase = _plan;
    return _planView = _plan.withScaleFrom(s);
  }

  SourcePlan _plan = SourcePlan.samsungOnly;
  SourcePlan? _planView;
  SourcePlan? _planViewBase;

  /// E2: η πρώτη ζύγιση InBody όταν υπάρχουν και παλιές ζυγίσεις χωρίς σημάδι ([scaleFromOf]). Ξαναϋπολογίζεται μόνο
  /// όταν αλλάζει το ιστορικό (νέος χάρτης ή αποθήκευση).
  DateTime? get _scaleFrom {
    if (_scaleDirty || !identical(_scaleFor, history)) {
      _scaleFor = history;
      _scaleDirty = false;
      _scaleValue = scaleFromOf(history);
    }
    return _scaleValue;
  }

  Map<String, Map<String, double>>? _scaleFor;
  bool _scaleDirty = true;
  DateTime? _scaleValue;
  PlanState planState = PlanState.loading;

  /// Πού κρατιέται το σχέδιο (αντικαθίσταται στις δοκιμές).
  PlanFile planFile = const ChannelPlanFile();
  String? _planFileWritten;

  @override
  bool get planReady => planState == PlanState.ok;

  /// Ιστορικό γράφεται μόνο με διαβασμένες ρυθμίσεις, διαβασμένο ιστορικό και γνωστό σχέδιο πηγών.
  bool get _canWrite => _historyLoaded && _prefsLoaded && planState == PlanState.ok;

  @override
  int? get ouraTriedMs => prefs.ouraTried;
  @override
  set ouraTriedMs(int? v) => prefs.ouraTried = v;
  @override
  int? get ouraBackoffMs => prefs.ouraBackoff;
  @override
  set ouraBackoffMs(int? v) => prefs.ouraBackoff = v;

  /// Για τα στιγμιότυπα της «άγνωστης» κατάστασης: αν διαβάστηκε το ιστορικό, ημερολόγιο, ένδειξη Oura.
  @visibleForTesting
  void debugSetRecovery({bool historyLoaded = true, bool evidence = false}) {
    _historyLoaded = historyLoaded;
    ouraEvidence = evidence;
  }

  /// Για τους ελέγχους και τα στιγμιότυπα: ορίζει το σχέδιο χωρίς αρχείο.
  @visibleForTesting
  void debugSetPlan(SourcePlan p, {PlanState state = PlanState.ok}) {
    _plan = p;
    prefs.plan = p;
    planState = state;
    _data = _raw?.restrict(p);
  }

  @override
  bool get planUnknown => planState == PlanState.unknown;

  /// Ένδειξη ότι το Oura διαβάστηκε κάποτε (αρχείο νυχτών, «ouraSyncedTo»· και οι τιμές «o.*» στο ιστορικό): ένα
  /// χαμένο σχέδιο τότε δεν θεωρείται ποτέ «δεν συνδέθηκε». Tokens μόνα τους (χωρίς τίποτα από το Oura) = μισή
  /// σύνδεση, που καθαρίζεται στην εκκίνηση (OuraStore) — ποτέ «άγνωστο σχέδιο» γι' αυτό.
  bool ouraEvidence = false;
  DatedPlan? _logged;

  /// Πότε ορίστηκε το τρέχον σχέδιο (ms), όπως γράφτηκε στο αρχείο.
  int? _planAt;

  /// Οι επιλογές στην «άγνωστη» κατάσταση (null = δεν είναι άγνωστη, ή το ιστορικό δεν διαβάστηκε ακόμα).
  List<RecoveryOption>? get planRecovery => planState != PlanState.unknown
      ? null
      : recoveryOptions(
          history: _historyLoaded ? history : null,
          evidence: ouraEvidence,
          today: dayOf(ouraClock()),
        );

  Future<bool> _findOuraEvidence() async {
    if (_prefsLoaded && !_prefsDefaulted && prefs.ouraSyncedTo != null) return true;
    try {
      if (decodeOuraNights((await ouraNightsFile.read()).json).isNotEmpty) return true;
    } catch (_) {}
    return false;
  }

  static int? _atOf(String? raw) {
    try {
      final j = raw == null ? null : jsonDecode(raw);
      return j is Map && j['at'] is num ? (j['at'] as num).toInt() : null;
    } catch (_) {
      return null;
    }
  }

  /// Οι εγγραφές του σχεδίου πηγών (αρχείο, ημερολόγιο) μία-μία: μια παλιότερη δεν γράφει πάνω σε νεότερη.
  Future<void> _planWrites = Future.value();
  Future<T> _planQueue<T>(Future<T> Function() f) {
    final run = _planWrites.catchError((_) {}).then((_) => f());
    _planWrites = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// Νέα καταχώριση στο ημερολόγιο αλλαγών. Αν το ημερολόγιο δεν διαβάζεται, δεν γράφεται από πάνω του.
  Future<void> _appendLog(SourcePlan p, int at) async {
    final log = await planFile.readLog();
    if (log.state == 'error') return;
    final raw = appendPlanLog(log.json, p, at);
    if (!await planFile.writeLog(raw)) await planFile.writeLog(raw);
    _logged = (plan: p, at: at);
  }

  /// Διαβάζει (ή ξανακρίνει) το σχέδιο πηγών. Δες [resolvePlan].
  Future<void> _loadPlan() async {
    if (planState == PlanState.ok) return;
    var file = await planFile.read();
    // Προσωρινό σφάλμα ανάγνωσης: μία ακόμα προσπάθεια πριν το θεωρήσουμε χαλασμένο.
    if (file.state == 'error') file = await planFile.read();
    final fileOk = file.state == 'ok' && decodePlanFile(file.json) != null;
    if (!fileOk) {
      final log = await planFile.readLog();
      _logged = lastLoggedPlan(log.json);
      ouraEvidence = await _findOuraEvidence();
    }
    final now = ouraClock();
    // Το αντίγραφο στις ρυθμίσεις (παλιό αντίγραφο χωρίς ώρα = το παλιότερο δυνατό).
    final prefsCopy = _prefsLoaded && !_prefsDefaulted && (prefs.planAt != null || prefs.plan.eras.isNotEmpty)
        ? (plan: prefs.plan, at: prefs.planAt ?? 0)
        : null;
    final r = resolvePlan(
      file: file,
      logged: _logged,
      prefsCopy: prefsCopy,
      history: _historyLoaded ? history : null,
      evidence: ouraEvidence,
      today: now,
    );
    // Το σχέδιο που βρέθηκε ισχύει αμέσως για τις οθόνες, ακόμα κι αν το αρχείο δεν ξαναγραφτεί τώρα: ποτέ
    // οι νύχτες του ρολογιού στη θέση νυχτών του Oura. Αποθήκευση στο ιστορικό μόνο όταν γραφτεί το αρχείο.
    _plan = r.plan;
    _data = _raw?.restrict(_plan);
    if (r.rewrite) {
      final copy = _logged != null && (prefsCopy == null || _logged!.at >= prefsCopy.at) ? _logged! : prefsCopy!;
      final json = encodePlanFile(r.plan, now, at: copy.at);
      if (!await _planQueue(() => planFile.write(json))) {
        planState = PlanState.loading;
        notifyListeners();
        return;
      }
      _planFileWritten = json;
      _planAt = copy.at;
    } else if (fileOk) {
      _planAt = _atOf(file.json);
      // Ό,τι διαβάστηκε είναι ήδη γραμμένο: δεν ξαναγράφεται αν δεν άλλαξε.
      _planFileWritten = file.json;
    }
    planState = r.state;
    if (planState == PlanState.ok) {
      // Το αντίγραφο στις ρυθμίσεις ακολουθεί το αρχείο (π.χ. αν μια παλιότερη αποθήκευσή του απέτυχε).
      final stale = prefs.plan != _plan || prefs.planAt != _planAt;
      prefs.plan = _plan;
      prefs.planAt = _plan.eras.isEmpty && _planAt == null ? null : _planAt ?? 0;
      if (_prefsLoaded && (_prefsDefaulted || stale)) await _savePrefs();
    }
    notifyListeners();
  }

  /// Το όριο του ύπνου του ρολογιού αλλάζει με τις μέρες (π.χ. όταν κλείνει η «Σύγκριση πηγών»): το αρχείο
  /// ξαναγράφεται πριν από κάθε ανάγνωση της Samsung, μόνο αν άλλαξε.
  Future<void> _syncPlanFile() => _planQueue(() async {
        if (planState != PlanState.ok || _plan.eras.isEmpty) return;
        final json = encodePlanFile(_plan, ouraClock(), at: _planAt);
        if (json == _planFileWritten) return;
        if (await planFile.write(json)) _planFileWritten = json;
      });

  /// Μετά από «άγνωστο» σχέδιο: ο χρήστης διαλέγει ρητά (Ρυθμίσεις › Πηγές). `false` αν δεν γράφτηκε.
  Future<bool> recoverPlan(SourcePlan p) async {
    if (planState != PlanState.unknown || !_prefsLoaded || !_historyLoaded) return false;
    final now = ouraClock();
    final at = now.millisecondsSinceEpoch;
    final ok = await _planQueue(() async {
      final json = encodePlanFile(p, now, at: at);
      if (!await planFile.write(json)) return false;
      _planFileWritten = json;
      // Αμέσως μετά την εγγραφή (μέσα στην ουρά): μια ανανέωση που περιμένει πίσω της βλέπει ήδη το νέο σχέδιο
      // και δεν ξαναγράφει ποτέ το παλιό.
      _plan = p;
      _planAt = at;
      await _appendLog(p, at);
      return true;
    });
    if (!ok) return false;
    _plan = p;
    _planAt = at;
    prefs.plan = p;
    prefs.planAt = at;
    planState = PlanState.ok;
    _data = _raw?.restrict(p);
    notifyListeners();
    if (!await _savePrefs()) await _savePrefs();
    return true;
  }

  /// «Δοκίμασε ξανά» στην άγνωστη κατάσταση: ξαναδιαβάζει ρυθμίσεις, ιστορικό και σχέδιο.
  Future<void> retryPlan() async {
    if (!_prefsLoaded) await loadPrefs(timeout: const Duration(seconds: 5));
    if (!_historyLoaded) await _loadHistory();
    await _loadPlan();
    notifyListeners();
  }

  @override
  String? get ouraErrorStored => prefs.ouraErr;
  @override
  set ouraErrorStored(String? v) => prefs.ouraErr = v;
  @override
  int? get ouraConnectedMs => prefs.ouraConnected;
  @override
  set ouraConnectedMs(int? v) => prefs.ouraConnected = v;

  @override
  int? get ouraSyncedMs => prefs.ouraSynced;
  @override
  set ouraSyncedMs(int? v) => prefs.ouraSynced = v;
  @override
  String? get ouraSyncedTo => prefs.ouraSyncedTo;
  @override
  set ouraSyncedTo(String? v) => prefs.ouraSyncedTo = v;
  @override
  String? get ouraRefetchTo => prefs.ouraRefetchTo;
  @override
  set ouraRefetchTo(String? v) => prefs.ouraRefetchTo = v;

  /// Φέρνω το ιστορικό (μία φορά, ανά μήνα).
  bool backfilling = false;

  /// Ως 10 χρόνια πίσω: όλο το ιστορικό που έχει η Samsung (απόφαση 2/11). Διαβάζεται μία φορά·
  /// ο «Χρόνος» στις Τάσεις χρειάζεται 455 μέρες, τα υπόλοιπα μένουν για τον γιατρό και για αργότερα.
  static const historyDays = 3653;

  /// Τόσοι συνεχόμενοι μήνες χωρίς κανένα δεδομένο (πιο πίσω από τους 15 μήνες των Τάσεων) = εκεί
  /// αρχίζει το ιστορικό σου· η συμπλήρωση σταματά και ξανακοιτά σε έναν μήνα.
  static const _emptyMonthsToStop = 24;
  static const _recentDays = 7; // όσες μέρες έχουν βήματα ανά λεπτό στην κανονική ανάγνωση

  bool _prefsLoaded = false;

  /// Οι ρυθμίσεις ΔΕΝ διαβάστηκαν (χαλασμένο αρχείο) και ξεκινήσαμε από τις προεπιλογές: δεν γράφονται πάνω
  /// στο αρχείο ως να είναι γνωστό το σχέδιο πηγών (ώστε το αντίγραφό του να μη χαθεί).
  bool _prefsDefaulted = false;
  int _prefsErrors = 0;
  Future<void>? _prefsLoad;

  /// Αν διαβάστηκαν οι ρυθμίσεις (ως τότε δεν αλλάζει η «Η κουζίνα μου»).
  bool get prefsLoaded => _prefsLoaded;

  /// Οι ρυθμίσεις πριν από την πρώτη οθόνη, ώστε να ανοίγει κατευθείαν με το σωστό θέμα.
  /// Αν αργήσουν, η εφαρμογή ανοίγει κανονικά και το θέμα αλλάζει μόλις έρθουν.
  ///
  /// Μέχρι να διαβαστούν, **τίποτα δεν αποθηκεύεται** στις ρυθμίσεις: αλλιώς οι προεπιλογές θα
  /// έγραφαν πάνω σε «Η κουζίνα μου», τις κάρτες και το θέμα.
  Future<void> loadPrefs({Duration timeout = const Duration(milliseconds: 800)}) async {
    if (_prefsLoaded) return;
    // Μία ανάγνωση τη φορά: αν τρέχει ήδη (π.χ. από το άνοιγμα), περιμένουμε την ίδια, ώστε μια
    // παλιότερη απάντηση να μη γράψει πάνω σε νεότερη και ένα σφάλμα να μετρά μία φορά.
    final load = _prefsLoad ??= _loadPrefsOnce().whenComplete(() => _prefsLoad = null);
    try {
      await load.timeout(timeout);
    } catch (_) {}
  }

  Future<void> _loadPrefsOnce() async {
    final r = await SamsungHealth.loadPrefs();
    if (_prefsLoaded) return;
    if (r['ok'] == false) {
      // Το αρχείο υπάρχει αλλά δεν διαβάστηκε τώρα (kind «read»): ξανά αργότερα, ποτέ προεπιλογές
      // από πάνω του. Άλλο σφάλμα (π.χ. χαλασμένο αρχείο) δύο φορές: ξεκινάμε από τις προεπιλογές.
      if (r['kind'] == 'read' || ++_prefsErrors < 2) return;
      _prefsDefaulted = true;
    } else {
      try {
        prefs = Prefs.fromJson(r);
      } catch (_) {
        if (++_prefsErrors < 2) return;
        _prefsDefaulted = true;
      }
    }
    // Το σχέδιο πηγών δεν έρχεται από τις ρυθμίσεις (έχει δικό του αρχείο)· κρατάμε όποιο ξέρουμε ήδη.
    if (planState == PlanState.ok) {
      prefs.plan = _plan;
      prefs.planAt = _plan.eras.isEmpty && _planAt == null ? null : _planAt ?? 0;
    }
    // Ό,τι άλλαξε ο χρήστης όσο περιμέναμε (π.χ. θέμα) μπαίνει πάνω στις ρυθμίσεις που ήρθαν.
    final pending = [..._pendingPrefChanges];
    _pendingPrefChanges.clear();
    for (final f in pending) {
      f(prefs);
    }
    _prefsLoaded = true;
    notifyListeners();
    if (pending.isNotEmpty) await _savePrefs();
  }

  /// Αλλαγές ρυθμίσεων πριν διαβαστεί το αρχείο: εφαρμόζονται αμέσως στην οθόνη και ξανά πάνω
  /// στις ρυθμίσεις που θα διαβαστούν, ώστε να μη χαθούν.
  final List<void Function(Prefs)> _pendingPrefChanges = [];

  void _changePrefs(void Function(Prefs) f) {
    f(prefs);
    if (!_prefsLoaded) _pendingPrefChanges.add(f);
    notifyListeners();
    _savePrefs();
  }

  /// Οι αποθηκεύσεις γίνονται με τη σειρά (η μία μετά την άλλη), ώστε μια παλιότερη να μη γράψει
  /// πάνω σε νεότερη. `true` αν γράφτηκε.
  Future<bool> _prefsSaves = Future.value(true);

  Future<bool> _savePrefs() {
    if (!_prefsLoaded) return Future.value(false);
    if (_prefsDefaulted && planState != PlanState.ok) return Future.value(false);
    final json = prefs.toJson();
    return _prefsSaves = _prefsSaves.catchError((_) => false).then((_) async {
      final r = await SamsungHealth.savePrefs(json);
      return r['ok'] == true;
    });
  }

  bool _historyLoaded = false;

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    // Αν δεν ήρθαν ακόμα, μία ακόμα προσπάθεια εδώ· μετά ξαναδοκιμάζει κάθε ανανέωση.
    if (!_prefsLoaded) await loadPrefs(timeout: const Duration(seconds: 5));
    await _loadHistory();
    // Το σχέδιο πριν από τον έλεγχο της βάσης (C9): μετά από βλάβη ξαναδιαβάζεται και το Oura, αν είναι στο σχέδιο.
    await _loadPlan();
    await _checkDatabase();
    await _upgradeHistory();
    await _upgradeOura();
    await startOura();
    final cached = await parseDashboard(await SamsungHealth.cachedDashboardRaw(), napLocks: napLocksOf(history));
    if (cached.data != null) data = cached.data;
    notifyListeners();
    await refresh();
  }

  Future<void> refresh({bool askPermissions = false}) async {
    if (loading) return;
    loading = true;
    notifyListeners();

    if (askPermissions) {
      final r = await SamsungHealth.requestPermissions();
      if (r['ok'] != true) {
        error = r;
        loading = false;
        notifyListeners();
        return;
      }
    }

    // C9: χαλασμένη βάση που βρέθηκε όσο η εφαρμογή ήταν ανοιχτή (η Kotlin άνοιξε καινούργια).
    if (_historyLoaded && _prefsLoaded) await _checkDatabase(midSession: true);

    // Το σχέδιο πηγών πριν από την ανάγνωση: η Samsung διαβάζει ύπνο του ρολογιού μόνο ως το όριό του.
    if (planState != PlanState.ok) await _loadPlan();
    await _syncPlanFile();

    // Πρώτα το Oura (όταν είναι η πηγή του ύπνου): οι ώρες ύπνου του χρειάζονται για τους παλμούς της μέρας και το
    // οξυγόνο, που υπολογίζονται μαζί με το διάβασμα της Samsung (A9).
    // Χωρίς απάντηση σε 90″ (π.χ. κόλλησε η Samsung) δεν μένει «φορτώνει» για πάντα. Η Samsung και το Oura μαζί.
    // Έλεγχος 2, C12: το σχέδιο ΠΡΙΝ από την ανάγνωση (η Samsung διαβάζει τον ύπνο του ρολογιού ως το όριο αυτού του
    // σχεδίου). Αν αλλάξει ως να έρθει η απάντηση (π.χ. «η τελευταία νύχτα από το ρολόι»), το ιστορικό δεν γράφεται
    // από αυτή την ανάγνωση (θα έσβηνε μια νύχτα που δεν διαβάστηκε)· γράφεται στην επόμενη.
    final readPlan = plan;
    final rawRead = SamsungHealth.dashboardRaw().timeout(const Duration(seconds: 90),
        onTimeout: () => jsonEncode({'ok': false, 'kind': 'other', 'message': 'Η Samsung δεν απάντησε. Δοκίμασε ξανά.'}));
    if (_canWrite) await syncOura();
    final raw = await rawRead;
    // Οι υπολογισμοί (νύχτες, παλμοί, συνόψεις 30 ημερών, μερικά MB δεδομένων) σε άλλο νήμα: η οθόνη δεν «κολλάει».
    final parsePlan = _canWrite && readPlan == plan ? readPlan : null;
    final parseNights = ouraNights;
    final p = await parseDashboard(raw,
        plan: parsePlan, windows: parsePlan == null ? SleepWindows.empty : ouraWindows, napLocks: napLocksOf(history));
    final ok = p.data != null;
    if (ok) {
      data = p.data;
      error = null;
      _lastRefresh = DateTime.now();
      _recentFilterEmpty = p.sleepFilterEmpty;
    } else {
      error = p.status;
    }
    loading = false;
    notifyListeners();

    if (!_prefsLoaded) await loadPrefs(timeout: const Duration(seconds: 10));

    final d = _raw;
    if (ok && d != null && d.hasAnyPermission) {
      if (!_historyLoaded) await _loadHistory();
      if (planState != PlanState.ok) await _loadPlan();
      // Χωρίς το αποθηκευμένο ιστορικό, τις ρυθμίσεις ή το σχέδιο πηγών δεν γράφουμε τίποτα: θα έσβηνε τιμές
      // που δεν ξαναδιαβάζονται, ή θα έγραφε ύπνο του ρολογιού για νύχτες του Oura.
      if (_canWrite) {
        await _upgradeHistory();
        // Πρώτα το Oura (όταν είναι η πηγή του ύπνου): οι ώρες ύπνου του χρειάζονται για τους παλμούς της μέρας.
        // [regroup] (έλεγχος 4, 1_data M1): η ανάγνωση πριν από τη Samsung είχε παλιά βήματα για ένα πρωινό κενό·
        // ξανά τώρα, με τα φρέσκα, ώστε ένας «υπνάκος» μετά από περπάτημα να μη μείνει μέσα στη νύχτα.
        await syncOura(regroup: true);
        // Οι συνόψεις από το άλλο νήμα μόνο αν το σχέδιο και οι νύχτες του Oura δεν άλλαξαν στο μεταξύ.
        final same = parsePlan != null && parsePlan == plan && identical(parseNights, ouraNights);
        if (readPlan == plan) {
          await _updateRecentHistory(d, sleepFailed: p.sleepFailed, heartFailed: p.heartFailed, rows: same ? p.rows : null);
        }
        _backfill();
      }
    } else if (_canWrite) {
      // Η Samsung δεν απάντησε: το Oura διαβάζεται κανονικά (ανεξάρτητη πηγή).
      await syncOura();
    }
  }

  /// Η βάση βρέθηκε χαλασμένη (ώρα, ms) και κρατήθηκε αντίγραφο (A7): κάρτα στη Σήμερα ώσπου να την κλείσει ο χρήστης.
  int? dbCorruptAt;

  /// Χαλασμένη βάση: ξεκίνησε καινούργια (το παλιό αρχείο κρατήθηκε). Το ιστορικό ξαναδιαβάζεται από τη Samsung από
  /// την αρχή (μία φορά για κάθε βλάβη)· το ημερολόγιο φαγητού επανέρχεται από το αντίγραφο ασφαλείας.
  ///
  /// Έλεγχος 2, C9: και το Oura ξαναδιαβάζεται από την αρχή της πρώτης εποχής του (90 μέρες με την κανονική ανάγνωση,
  /// και πιο πίσω ανά 90 μέρες, [OuraStore.ouraOlderRange]). [midSession]: η βλάβη βρέθηκε ενώ η εφαρμογή ήταν ανοιχτή·
  /// τότε το ιστορικό στη μνήμη (πλήρες, από πριν) ξαναγράφεται όλο στη νέα βάση.
  Future<void> _checkDatabase({bool midSession = false}) async {
    final r = await SamsungHealth.dbStatus();
    final at = r['ok'] == true && r['corrupt'] is num ? (r['corrupt'] as num).toInt() : null;
    if (at == null && midSession) return;
    dbCorruptAt = at;
    if (at == null || !_prefsLoaded || prefs.dbReset == at) return;
    final today = dayOf(ouraClock());
    prefs
      ..backfillFrom = null
      ..emptyFrom = null
      ..emptyChecked = null
      ..gapFrom = null
      ..gapTo = null
      ..recentTo = null
      ..dbReset = at;
    if (_plan.hasOura || prefs.plan.hasOura) {
      prefs
        ..ouraSyncedTo = null
        ..ouraRefetchTo = dateKey(addDays(today, -(ouraMaxBackDays + 1)));
    }
    await _savePrefs();
    // Το ιστορικό στη μνήμη είναι από ΠΡΙΝ τη βλάβη: γράφεται όλο στη νέα βάση (αλλιώς θα έμεναν μόνο όσες μέρες
    // αλλάξουν από εδώ και πέρα).
    if (midSession && _historyLoaded && history.isNotEmpty) {
      await _saveDays(history.keys.toSet());
      notifyListeners();
    }
  }

  /// «Εντάξει» στην κάρτα της χαλασμένης βάσης.
  Future<void> dismissDatabaseNotice() async {
    dbCorruptAt = null;
    notifyListeners();
    await SamsungHealth.dbStatusSeen();
  }

  // ---------- Ιστορικό ----------

  static DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

  Future<void> _loadHistory() async {
    final r = await SamsungHealth.loadDays();
    if (r['ok'] != true || r['days'] is! List) return;
    _historyLoaded = true;
    final h = <String, Map<String, double>>{};
    for (final row in r['days'] as List) {
      if (row is! Map || row['date'] is! String || row['data'] is! Map) continue;
      h[row['date'] as String] = {
        for (final e in (row['data'] as Map).entries)
          if (e.value is num) e.key.toString(): (e.value as num).toDouble(),
      };
    }
    history = h;
  }

  /// Μέρες που άλλαξαν στη μνήμη αλλά δεν γράφτηκαν ακόμα στο κινητό (απέτυχε η αποθήκευση):
  /// μπαίνουν σε κάθε επόμενη αποθήκευση μέχρι να γραφτούν, ώστε να μη μείνουν κενά.
  final Set<String> _unsavedDays = {};

  @override
  bool get historyReady => _historyLoaded;

  @override
  bool get prefsReady => _prefsLoaded;

  @override
  Future<bool> saveDaysNow(Set<String> keys) => _saveDays(keys);

  @override
  int? watchStepsBetween(DateTime from, DateTime to) {
    final d = _raw;
    // Έλεγχος 4 (1_data M1): τα λεπτά μετά την ανάγνωση των βημάτων είναι άγνωστα, όχι 0.
    return d == null
        ? null
        : gapSteps(from, to, stepsByMinute: d.stepsByMinute, stepsFrom: d.stepsMinuteFrom, stepsTo: d.readAt);
  }

  @override
  DateTime? get watchStepsReadAt => _raw?.readAt;

  @override
  Future<bool> savePrefsNow() => _savePrefs();

  /// Οι εγγραφές του ιστορικού γίνονται μία-μία, με τη σειρά που ζητήθηκαν (έλεγχος 4/11, A8): η ανάγνωση των
  /// 30 ημερών, η συμπλήρωση και το Oura γράφουν τις ίδιες μέρες, και μια παλιότερη εικόνα μιας μέρας δεν πρέπει
  /// να φτάσει στη βάση μετά από νεότερη. Κάθε εγγραφή παίρνει τις τιμές της μέρας τη στιγμή που ΓΡΑΦΕΤΑΙ.
  Future<bool> _daysWrites = Future.value(true);

  /// `true` αν γράφτηκαν (ή δεν υπήρχε κάτι να γραφτεί).
  Future<bool> _saveDays(Set<String> keys) {
    if (keys.isNotEmpty) _scaleDirty = true;
    final run = _daysWrites.catchError((_) => false).then((_) async {
      final all = {...keys, ..._unsavedDays};
      if (all.isEmpty) return true;
      final r = await SamsungHealth.saveDays(jsonEncode([
        for (final k in all)
          if (history[k] != null) {'date': k, 'data': history[k]},
      ]));
      final ok = r['ok'] == true;
      if (ok) {
        _unsavedDays.removeAll(all);
      } else {
        _unsavedDays.addAll(all);
      }
      return ok;
    });
    _daysWrites = run.catchError((_) => false);
    return run;
  }

  /// Νέοι κανόνες ύπνου (historyRulesVersion): το ιστορικό ξαναδιαβάζεται από την αρχή και κάθε
  /// μήνας αντικαθιστά τις τιμές ύπνου του με τους νέους κανόνες, ώστε όλες οι μέρες να έχουν τον
  /// ίδιο ορισμό. Οι παλιές τιμές **δεν σβήνονται από πριν**: μένουν ώσπου να έρθουν οι νέες,
  /// ώστε μια ανάγνωση που αποτυγχάνει να μην αφήνει κενά.
  /// Έλεγχος 2, C4: η [Prefs.historyVersion] γίνεται η νέα ΜΟΝΟ όταν ξαναδιαβαστεί όλο το ιστορικό ([_finishReread])·
  /// ως τότε [Prefs.rereadVersion] και η πρόοδος ([Prefs.backfillFrom]) είναι αποθηκευμένα, και οι Τάσεις/αναφορά δεν
  /// συγκρίνουν πάνω από το όριο ([analysisPlan]).
  Future<void> _upgradeHistory() async {
    if (!_prefsLoaded || !_historyLoaded || prefs.historyVersion >= historyRulesVersion) return;
    if (prefs.rereadVersion == historyRulesVersion) return; // ήδη σε εξέλιξη (συνεχίζει από το backfillFrom)
    if (history.isEmpty) {
      // Νέα εγκατάσταση: δεν υπάρχει παλιός ορισμός να ξαναϋπολογιστεί (η πρώτη συμπλήρωση γίνεται κανονικά).
      prefs.historyVersion = historyRulesVersion;
      await _savePrefs();
      return;
    }
    prefs.backfillFrom = null;
    prefs.emptyFrom = null;
    prefs.emptyChecked = null;
    prefs.rereadVersion = historyRulesVersion;
    prefs.monthFails.clear();
    prefs.staleMonths.clear();
    await _savePrefs();
  }

  /// Έλεγχος 2, C12: παλιές τιμές του Oura με άλλον ορισμό (π.χ. o.deepPct της #66): το Oura ξαναδιαβάζεται από την αρχή
  /// του (90 μέρες με την κανονική ανάγνωση, πιο πίσω ανά 90 μέρες), μία φορά για κάθε αλλαγή κανόνων.
  Future<void> _upgradeOura() async {
    if (!_prefsLoaded || planState != PlanState.ok || prefs.ouraRules >= ouraRulesVersion) return;
    // Μόνο αν υπάρχουν αποθηκευμένα ποσοστά φάσεων του Oura (αλλιώς δεν υπάρχει τίποτα με τον παλιό ορισμό). Η Oura
    // δίνει φάσεις σε κάθε νύχτα, οπότε έτσι ξαναδιαβάζονται και οι νύχτες σε κομμάτια (κοινός κανόνας, 4/11).
    final old = ouraKeys[K.deepPct]!;
    if (_plan.hasOura && _historyLoaded && history.values.any((r) => r.containsKey(old))) {
      prefs
        ..ouraSyncedTo = null
        ..ouraRefetchTo = dateKey(addDays(dayOf(ouraClock()), -(ouraMaxBackDays + 1)));
    }
    prefs.ouraRules = ouraRulesVersion;
    await _savePrefs();
  }

  /// Η επανανάγνωση έφτασε στην αρχή του ιστορικού: από εδώ και πέρα όλο το ιστορικό έχει τους νέους κανόνες.
  Future<void> _finishReread() async {
    final v = prefs.rereadVersion;
    if (v == null) return;
    prefs.historyVersion = v;
    prefs.rereadVersion = null;
    prefs.monthFails.clear();
    await _savePrefs();
  }

  /// Αν το ιστορικό ξαναϋπολογίζεται τώρα με νέους κανόνες (C4).
  bool get rereading => prefs.rereadVersion != null;

  /// Ως πού (προς τα πίσω) έχει ξαναϋπολογιστεί: οι μέρες πριν από αυτήν έχουν ακόμα τον παλιό ορισμό. null = όλο.
  DateTime? get rereadBoundary {
    if (!rereading) return null;
    final f = prefs.backfillFrom;
    // Πριν από το πρώτο κομμάτι: μόνο οι μέρες της κανονικής ανάγνωσης (30 μέρες) έχουν τους νέους κανόνες.
    if (f == null) return addDays(dayOf(DateTime.now()), -(recentSummaryDays - 1));
    return parseDateKey(f);
  }

  /// Το σχέδιο πηγών για Τάσεις, αναφορά, «εκτός συνηθισμένου» και εβδομάδα: όσο το ιστορικό ξαναϋπολογίζεται, το
  /// όριο είναι αλλαγή ορισμού (καμία σύγκριση παλιού με νέο ορισμό). Οι οθόνες ύπνου χρησιμοποιούν το [plan].
  SourcePlan get analysisPlan => rereading ? plan.withRulesFrom(rereadBoundary) : plan;

  /// Οι τελευταίες 30 μέρες από την κανονική ανάγνωση + όλες οι ζυγίσεις.
  /// Ο ύπνος ξαναγράφεται μόνο για τις μέρες με βήματα ανά λεπτό (δες mergeHistory).
  /// [sleepFailed]: κάποιο είδος από το οποίο βγαίνει ο ύπνος δεν διαβάστηκε (δες sleepReadFailed)·
  /// τότε οι τιμές ύπνου που υπάρχουν ήδη δεν αντικαθίστανται.
  /// [heartFailed]: οι παλμοί δεν διαβάστηκαν· οι τιμές από τους παλμούς μένουν ως είχαν (A12).
  Future<void> _updateRecentHistory(Dashboard d,
      {bool sleepFailed = false, bool heartFailed = false, Map<String, Map<String, double>>? rows}) async {
    if (!_canWrite) return;
    final changed = applyRecentRead(
      history,
      d,
      plan: plan,
      windows: ouraWindows,
      sleepFailed: sleepFailed,
      heartFailed: heartFailed,
      rows: rows,
      windowsComplete: ouraWindowsComplete,
    );
    // Μέρες με άλλη πηγή ύπνου που είχαν ακόμα τιμές νύχτας του ρολογιού (π.χ. η μέρα της σύνδεσης): φεύγουν.
    final today = dayOf(d.readAt);
    final saved = await _saveDays(changed);
    // Η εφαρμογή έμεινε κλειστή πάνω από 6 μέρες: οι μέρες στη μέση (και η τελευταία, που είχε
    // γραφτεί μισή) ξαναδιαβάζονται, με βήματα ανά λεπτό, ώστε ο ύπνος τους να έχει τον ίδιο ορισμό
    // με τις υπόλοιπες (η κανονική ανάγνωση έχει βήματα ανά λεπτό μόνο για 7 μέρες).
    final last = prefs.recentTo != null ? parseDateKey(prefs.recentTo!) : null;
    if (saved && _prefsLoaded) {
      // Διαβάζεται μόνο το κενό (όχι όλο το ιστορικό): από την τελευταία μέρα που είχε γραφτεί (μισή) ως
      // τη μέρα −7. Αν υπήρχε ήδη ανολοκλήρωτο κενό, κρατάμε την παλιότερη αρχή και ξεκινάμε από πάνω.
      if (last != null && last.isBefore(addDays(today, -(_recentDays - 1)))) {
        final prev = prefs.gapFrom != null ? parseDateKey(prefs.gapFrom!) : null;
        prefs.gapFrom = dateKey(prev != null && prev.isBefore(last) ? prev : last);
        prefs.gapTo = null;
      }
      if (prefs.recentTo != dateKey(today)) {
        prefs.recentTo = dateKey(today);
        await _savePrefs();
      }
    }
    notifyListeners();
  }

  /// Αποτυχίες της συμπλήρωσης σε αυτή τη χρήση της εφαρμογής (η ανάγνωση δεν έγινε καθόλου). Μετά από 3, δεν
  /// ξαναδιαβάζουμε σε κάθε ανανέωση (μπαταρία). Οι αποτυχίες ανά μήνα είναι αποθηκευμένες ([Prefs.monthFails]).
  int _backfillFails = 0;

  /// Κομμάτια με «άλλη συσκευή» μετά τον πρώτο ύπνο ρολογιού που απέτυχαν ήδη μία φορά σε αυτό το άνοιγμα (έλεγχος 4).
  final Set<String> _nonWatchRetried = {};

  /// Ένα κομμάτι [from, cursor) από τη Samsung: διαβάζεται σε άλλο νήμα και γράφεται στο ιστορικό.
  /// Επιστρέφει null αν σταματάμε για τώρα (θα ξαναδοκιμαστεί), αλλιώς αν ήταν εντελώς άδειο.
  Future<bool?> _readChunk(DateTime from, DateTime cursor) async {
    final to = addDays(cursor, -1);
    final readPlan = plan;
    final raw = await SamsungHealth.readRangeRaw(dateKey(from), dateKey(cursor))
        .timeout(const Duration(seconds: 120), onTimeout: () => '{"ok":false,"kind":"timeout"}');
    final p = await parseRange(raw, from, to, plan: readPlan, windows: ouraWindows, napLocks: napLocksOf(history));
    // Έλεγχος 2, C11: το σχέδιο πηγών άλλαξε όσο διαβαζόταν (π.χ. επαναφορά αντιγράφου): οι τιμές υπολογίστηκαν με
    // το παλιό· δεν γράφονται, το κομμάτι ξαναδιαβάζεται στην επόμενη ανανέωση (χωρίς να μετρά ως αποτυχία).
    if (readPlan != plan) return null;
    if (!p.ok) {
      // Δεν διαβάστηκε τίποτα: ξανά στην επόμενη ανανέωση (ως 3 φορές), χωρίς να προχωρήσουμε.
      _backfillFails++;
      return null;
    }
    _backfillFails = 0;
    // Η Samsung έδωσε πολύ λιγότερες νύχτες από όσες έχει ήδη το ιστορικό για αυτόν τον μήνα
    // (π.χ. νέο κινητό που δεν έχει συγχρονίσει ακόμα): σαν αποτυχία ανάγνωσης, ώστε να μη σβηστούν.
    final had = sleepDaysIn(history, from, to);
    final got = p.rows.values.where((v) => v.containsKey(K.sleepMin)).length;
    // E3: ύπνος μόνο από άλλη συσκευή. Έλεγχος 4 (red team M1): δεκτό («χωρίς ρολόι», χωρίς ξαναδοκιμές) ΜΟΝΟ για
    // κομμάτι που τελειώνει πριν από τον πρώτο ύπνο ρολογιού όλου του ιστορικού (π.χ. πριν από το ρολόι). Μετά από αυτόν
    // (ρολόι που δεν αναγνωρίστηκε, μήνας χωρίς ρολόι με ύπνο από κινητό): σφάλμα ανάγνωσης, οι τιμές μένουν.
    final nonWatch = p.sleepOk && p.nonWatch.contains('sleep');
    // Review M2: «καμία εγγραφή ρολογιού ποτέ» μόνο για κομμάτι χωρίς αποθηκευμένες νύχτες ρολογιού· αλλιώς σφάλμα.
    final otherDevice = nonWatch && (p.otherDeviceOk || (p.noWatchSleep && had == 0));
    final nonWatchError = nonWatch && !otherDevice;
    final tooFew = !p.nonWatch.contains('sleep') && had >= 4 && got < had / 2;
    // Σφάλμα σε είδος από το οποίο βγαίνει ο ύπνος: ξανά στην επόμενη ανανέωση. Μετά από 3 φορές
    // προχωράμε, κρατώντας τις τιμές ύπνου που υπάρχουν ήδη.
    final failed = p.sleepFailed || tooFew || nonWatchError;
    final k = dateKey(cursor);
    if (failed) {
      // C4: αποθηκευμένο (όχι στη μνήμη): μετά από 3 αποτυχίες, και με επανεκκινήσεις στο μεταξύ, προχωράμε.
      final n = prefs.monthFails[k] = (prefs.monthFails[k] ?? 0) + 1;
      await _savePrefs();
      if (n < 3) {
        // Έλεγχος 4: «άλλη συσκευή» μετά τον πρώτο ύπνο ρολογιού ξαναδοκιμάζεται το πολύ μία φορά σε κάθε άνοιγμα της
        // εφαρμογής (όχι σε κάθε επιστροφή): η δεύτερη αποτυχία σταματά τη συμπλήρωση ως το επόμενο άνοιγμα.
        if (nonWatchError && !_nonWatchRetried.add(k)) _backfillFails = 3;
        return null;
      }
    }
    // Έλεγχος 4 (1_data M2/M3/L1): νύχτες του ρολογιού χωρίς έγκυρη νέα διάρκεια: ΟΛΕΣ οι τιμές ύπνου της μέρας
    // κρυφές («nw.*»), ποτέ σβησμένες· στο κομμάτι «από άλλη συσκευή» και με σημάδι (μετριέται στο «Τι φτάνει»).
    final archived = !failed && p.sleepOk
        ? archiveSleep(history, p.rows, from: from, to: to, plan: plan, otherDevice: otherDevice)
        : <String>{};
    final saved = await _saveDays({
      ...archived,
      ...mergeHistory(
      history,
      p.rows,
      replaceSleep: !failed && p.sleepOk,
      rangeFrom: from,
      rangeTo: to,
      plan: plan,
      keepKeys: p.heartFailed ? heartKeys : const {},
      ouraNights: ouraWindows.mains.keys.toSet(),
    ),
    });
    // Δεν γράφτηκε στο κινητό: δεν προχωράμε, ώστε ο μήνας να ξαναδιαβαστεί.
    if (!saved) {
      _backfillFails++;
      return null;
    }
    // C4: κομμάτι που κράτησε τις παλιές τιμές ύπνου (3 αποτυχίες) σημειώνεται και φαίνεται· ποτέ σιωπηλά.
    if (prefs.monthFails.remove(k) != null || failed) {
      if (failed && rereading && !prefs.staleMonths.contains(k)) prefs.staleMonths.add(k);
      await _savePrefs();
    }
    // «Άδειο» μόνο αν δεν υπήρχε τίποτα και δεν απέτυχε κανένα είδος δεδομένων.
    return p.rows.isEmpty && !p.anyError;
  }

  /// Ως πού έχει φτάσει η συμπλήρωση (για την κάρτα στις Τάσεις).
  DateTime? backfillReached;
  bool _fillingGap = false;

  /// Η κάρτα στις Τάσεις φαίνεται μόνο όσο έρχονται μέρες που αλλάζουν τις Τάσεις (κενό ή τελευταίοι
  /// 15 μήνες). Τα παλιότερα χρόνια και ο μηνιαίος έλεγχος γίνονται αθόρυβα.
  bool get backfillVisible {
    if (!backfilling) return false;
    final r = backfillReached;
    return _fillingGap || r == null || r.isAfter(addDays(dayOf(DateTime.now()), -455));
  }

  /// Συμπληρώνει το ιστορικό, μόνο όσο η εφαρμογή είναι ανοιχτή· αν κλείσει, συνεχίζει την επόμενη φορά.
  /// 1. Πρώτα το κενό από όσο έμεινε κλειστή η εφαρμογή (πάνω από 6 μέρες).
  /// 2. Μετά προς τα πίσω ανά 30 μέρες, ως 10 χρόνια ή ως εκεί που αρχίζουν τα δεδομένα σου.
  /// E3: η τελευταία κανονική ανάγνωση έδωσε «φίλτρο ρολογιού άδειο» για τον ύπνο ([sleepFilterEmpty]).
  bool _recentFilterEmpty = false;

  Future<void> _backfill() async {
    if (backfilling || !_canWrite || _backfillFails >= 3) return;
    // E3: όσο το φίλτρο ρολογιού δεν βρίσκει τίποτα στις 30 μέρες (όπου περιμένουμε ρολόι), κανένα κομμάτι ιστορικού:
    // εκεί ένα άδειο αποτέλεσμα γίνεται δεκτό ως «χωρίς ρολόι» και θα έκρυβε όλο τον παλιό ύπνο.
    if (_recentFilterEmpty) return;
    final today = dayOf(DateTime.now());
    // Το πρώτο κομμάτι φτάνει ως τη μέρα −7 (η −6 και μετά ξαναγράφονται σε κάθε ανανέωση).
    final start = addDays(today, -(_recentDays - 1));
    final oldest = addDays(today, -historyDays);
    // Μία φορά τον μήνα ξανακοιτάμε πιο πίσω από εκεί που «άρχιζαν» τα δεδομένα: π.χ. σε νέο κινητό
    // που τότε δεν είχε συγχρονίσει ακόμα όλο το ιστορικό της Samsung.
    // Μόνο όταν η συμπλήρωση έχει τελειώσει: αλλιώς ο δείκτης θα πηδούσε μήνες που δεν έχουν διαβαστεί.
    final checked = prefs.emptyChecked != null ? parseDateKey(prefs.emptyChecked!) : null;
    final done = prefs.backfillFrom != null && !parseDateKey(prefs.backfillFrom!).isAfter(oldest);
    if (done && prefs.emptyFrom != null && checked != null && checked.isBefore(addDays(today, -30))) {
      prefs.backfillFrom = prefs.emptyFrom;
      prefs.emptyFrom = null;
      prefs.emptyChecked = null;
    }
    final gapFrom = prefs.gapFrom != null ? parseDateKey(prefs.gapFrom!) : null;
    var cursor = prefs.backfillFrom != null ? parseDateKey(prefs.backfillFrom!) : start;
    if (gapFrom == null && !cursor.isAfter(oldest)) {
      await _finishReread();
      return;
    }

    backfilling = true;
    _fillingGap = gapFrom != null;
    backfillReached = gapFrom != null ? (prefs.gapTo != null ? parseDateKey(prefs.gapTo!) : start) : cursor;
    notifyListeners();
    try {
      if (gapFrom != null) {
        var g = prefs.gapTo != null ? parseDateKey(prefs.gapTo!) : start;
        while (g.isAfter(gapFrom)) {
          var from = addDays(g, -30);
          if (from.isBefore(gapFrom)) from = gapFrom;
          if (await _readChunk(from, g) == null) return;
          g = from;
          prefs.gapTo = dateKey(g);
          await _savePrefs();
          backfillReached = g;
          notifyListeners();
        }
        prefs.gapFrom = null;
        prefs.gapTo = null;
        await _savePrefs();
        _fillingGap = false;
        backfillReached = cursor;
        notifyListeners();
      }

      final tooOldForTrends = addDays(today, -455);
      var emptyMonths = 0;
      DateTime? emptyStart;
      while (cursor.isAfter(oldest)) {
        var from = addDays(cursor, -30);
        if (from.isBefore(oldest)) from = oldest;
        final empty = await _readChunk(from, cursor);
        if (empty == null) break;
        if (empty) {
          emptyStart ??= cursor;
          emptyMonths++;
        } else {
          emptyMonths = 0;
          emptyStart = null;
        }
        cursor = from;
        // 2 χρόνια χωρίς κανένα δεδομένο, πιο πίσω από τους 15 μήνες των Τάσεων: εκεί αρχίζουν τα
        // δεδομένα σου. Σταματάμε (και ξανακοιτάμε σε έναν μήνα, δες πάνω).
        if (emptyMonths >= _emptyMonthsToStop && !from.isAfter(tooOldForTrends)) {
          prefs.emptyFrom = dateKey(emptyStart!);
          prefs.emptyChecked = dateKey(today);
          cursor = oldest;
        }
        prefs.backfillFrom = dateKey(cursor);
        await _savePrefs();
        backfillReached = cursor;
        notifyListeners();
      }
      if (!cursor.isAfter(oldest)) await _finishReread();
    } catch (_) {
      // Ξανά στην επόμενη ανανέωση (ως 3 φορές σε αυτή τη χρήση της εφαρμογής).
      _backfillFails++;
    } finally {
      backfilling = false;
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _lastRefresh;
    if (last == null || DateTime.now().difference(last).inMinutes >= 5) {
      refresh();
    } else if (_historyLoaded && _prefsLoaded) {
      syncOura(); // έχει δικό της όριο (το πολύ κάθε 30 λεπτά)
    }
  }

  /// Οι ρυθμίσεις όπως αποθηκεύονται (για το αντίγραφο ασφαλείας).
  Map<String, dynamic> prefsJson() => jsonDecode(prefs.toJson()) as Map<String, dynamic>;

  /// Αλλαγή του σχεδίου πηγών (σύνδεση/αποσύνδεση Oura): ΠΡΩΤΑ στο δικό του αρχείο (ατομικά), μετά στη μνήμη
  /// και στο αντίγραφο των ρυθμίσεων. Μόνο με διαβασμένες ρυθμίσεις και γνωστό σχέδιο.
  @override
  Future<bool> setPlan(SourcePlan p) async {
    if (!_prefsLoaded || planState != PlanState.ok) return false;
    final now = ouraClock();
    final at = now.millisecondsSinceEpoch;
    // Σειρά: αρχείο (ατομικά) → ημερολόγιο αλλαγών → αντίγραφο στις ρυθμίσεις (με μία επανάληψη). Αν το αρχείο
    // δεν γραφτεί, τίποτα άλλο δεν αλλάζει (ούτε το ημερολόγιο).
    final ok = await _planQueue(() async {
      final json = encodePlanFile(p, now, at: at);
      if (!await planFile.write(json)) return false;
      _planFileWritten = json;
      // Αμέσως μετά την εγγραφή (μέσα στην ουρά): μια ανανέωση που περιμένει πίσω της βλέπει ήδη το νέο σχέδιο
      // και δεν ξαναγράφει ποτέ το παλιό.
      _plan = p;
      _planAt = at;
      await _appendLog(p, at);
      return true;
    });
    if (!ok) return false;
    _plan = p;
    _planAt = at;
    prefs.plan = p;
    prefs.planAt = at;
    _data = _raw?.restrict(p);
    notifyListeners();
    if (!await _savePrefs()) await _savePrefs();
    return true;
  }

  /// Αν επιτρέπεται τώρα αλλαγή πηγών (για τη σύνδεση: να μη συνδεθεί χωρίς να μπορεί να αλλάξει η πηγή).
  @override
  bool get canChangePlan => _prefsLoaded && planState == PlanState.ok;

  /// Το σχέδιο πηγών και το ημερολόγιό του για το αντίγραφο ασφαλείας (A10), μόνο αν το αρχείο διαβάζεται.
  Future<({String plan, String? log})?> sourcesForBackup() async {
    if (planState != PlanState.ok) return null;
    final f = await planFile.read();
    if (f.state != 'ok' || decodePlanFile(f.json) == null) return null;
    final log = await planFile.readLog();
    return (plan: f.json!, log: log.state == 'ok' ? log.json : null);
  }

  /// Επαναφορά του σχεδίου πηγών από αντίγραφο (A10). Μπαίνει ΜΟΝΟ αν το κινητό δεν έχει νεότερο: σε κινητό που δεν
  /// είχε ποτέ σχέδιο (π.χ. νέο κινητό), ή αν το σχέδιο του αντιγράφου ορίστηκε αργότερα. Δεν σβήνει τίποτα από το
  /// ιστορικό ή τα δεδομένα· αλλάζει μόνο το ποια πηγή μετρά κάθε νύχτα. `true` αν μπήκε.
  Future<bool> restoreSources(({String plan, String? log}) s) async {
    if (!_prefsLoaded || planState != PlanState.ok) return false;
    final p = decodePlanFile(s.plan);
    if (p == null) return false;
    final at = _atOf(s.plan) ?? 0;
    final neverSet = _plan.eras.isEmpty && _planAt == null;
    if (!neverSet && (at <= (_planAt ?? 0) || p == _plan)) return false;
    final now = ouraClock();
    final ok = await _planQueue(() async {
      final json = encodePlanFile(p, now, at: at);
      if (!await planFile.write(json)) return false;
      _planFileWritten = json;
      _plan = p;
      _planAt = at;
      // Το ημερολόγιο του αντιγράφου, αν το κινητό δεν έχει δικό του· και η καταχώριση της επαναφοράς.
      final log = await planFile.readLog();
      if (log.state == 'missing' && s.log != null && lastLoggedPlan(s.log) != null) await planFile.writeLog(s.log!);
      await _appendLog(p, at);
      return true;
    });
    if (!ok) return false;
    final before = prefs.plan;
    prefs.plan = p;
    prefs.planAt = at;
    _data = _raw?.restrict(p);
    // Έλεγχος 2, C11: οι μέρες που η νύχτα άλλαξε πηγή (ρολόι ↔ άλλη) με την επαναφορά: οξυγόνο νύχτας και παλμοί μέρας
    // είχαν υπολογιστεί με τον άλλο ορισμό (ώρες ύπνου του ρολογιού αντί του Oura ή το αντίστροφο). Φεύγουν, και το
    // ιστορικό ξαναδιαβάζεται, ώστε να ξαναϋπολογιστούν με τον σωστό ορισμό όπου υπάρχουν οι ώρες ύπνου.
    final changed = stripChangedDefinitions(history, before, p);
    if (changed.isNotEmpty) {
      await _saveDays(changed);
      prefs
        ..backfillFrom = null
        ..emptyFrom = null
        ..emptyChecked = null;
    }
    notifyListeners();
    if (!await _savePrefs()) await _savePrefs();
    return true;
  }

  /// Επαναφορά ρυθμίσεων από αντίγραφο: κουζίνα, κάρτες, εμφάνιση. Η πρόοδος του ιστορικού μένει.
  Future<bool> restorePrefs(Map<String, dynamic> p) async {
    if (!_prefsLoaded) return false;
    final merged = {...prefsJson(), ...p, 'layout': todayLayout};
    final restored = Prefs.fromJson(merged)
      ..backfillFrom = prefs.backfillFrom
      ..historyVersion = prefs.historyVersion
      ..recentTo = prefs.recentTo
      ..gapFrom = prefs.gapFrom
      ..gapTo = prefs.gapTo
      ..emptyFrom = prefs.emptyFrom
      ..emptyChecked = prefs.emptyChecked
      ..rereadVersion = prefs.rereadVersion
      ..ouraRules = prefs.ouraRules
      ..ouraRefetchTo = prefs.ouraRefetchTo
      ..monthFails.clear()
      ..monthFails.addAll(prefs.monthFails)
      ..staleMonths.clear()
      ..staleMonths.addAll(prefs.staleMonths)
      // Οι πηγές και η σύνδεση Oura ανήκουν σε αυτό το κινητό, όχι στο αντίγραφο.
      ..plan = _plan
      ..ouraSynced = prefs.ouraSynced
      ..ouraSyncedTo = prefs.ouraSyncedTo
      ..ouraTried = prefs.ouraTried
      ..ouraBackoff = prefs.ouraBackoff
      ..planAt = prefs.planAt
      ..ouraErr = prefs.ouraErr
      ..ouraConnected = prefs.ouraConnected;
    prefs = restored;
    notifyListeners();
    return _savePrefs();
  }

  /// `false` αν οι ρυθμίσεις δεν έχουν διαβαστεί ακόμα: τότε η κουζίνα που φαίνεται μπορεί να μην
  /// είναι η αποθηκευμένη, και δεν τη γράφουμε πάνω της.
  bool setKitchen(Map<String, dynamic> k) {
    if (!_prefsLoaded) return false;
    _changePrefs((p) => p.kitchen = k);
    return true;
  }

  /// Εμφάνιση: αλλάζει αμέσως και αποθηκεύεται.
  void setAppearance({String? mode, String? day, String? night}) => _changePrefs((p) {
        if (mode != null) p.themeMode = mode;
        if (day != null) p.dayTheme = day;
        if (night != null) p.nightTheme = night;
      });

  void setCard(String key, bool on) => _changePrefs((p) => p.cards[key] = on);

  /// Έλεγχος 3, E6: το όνομα της αναφοράς. Αν οι ρυθμίσεις δεν έχουν διαβαστεί ακόμα, μπαίνει πάνω τους όταν έρθουν
  /// (πριν χανόταν: γραφόταν στις προεπιλογές, που αντικαθίσταντο).
  void setReportName(String? name) => _changePrefs((p) {
        p.reportName = name;
        p.reportNameKnown = true;
      });

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    disposeOura();
    super.dispose();
  }
}
