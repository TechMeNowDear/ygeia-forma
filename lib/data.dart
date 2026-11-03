import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart';

import 'error_report.dart';
import 'format.dart';
import 'history.dart';
import 'oura/oura_model.dart';
import 'oura/oura_store.dart';
import 'plan_file.dart';
import 'samsung.dart';
import 'sleep_gaps.dart';
import 'sources.dart';

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
  final int minutes;
  final int? score;
  final List<Stage> stages;
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
  int minutes = 0;
  int? score;
  double? sleepingHr;
  double? spo2Avg;
  double? spo2Min;
  double? spo2Below90;
  double? skinTemp;
  int napMinutes = 0;

  /// Κενά της Samsung ανάμεσα στα κομμάτια, με παλμούς σαν του ύπνου (δες sleep_gaps.dart).
  /// «Πιθανός ύπνος»: φαίνονται χωριστά και **δεν** μετρούν στα [minutes].
  final List<(DateTime, DateTime)> estimatedGaps = [];
  int get estimatedMinutes => estimatedGaps.fold(0, (s, g) => s + g.$2.difference(g.$1).inMinutes);

  int get awakeMinutes => stageMinutes['AWAKE'] ?? 0;
}

/// Κομμάτια ύπνου που ανήκουν μαζί (πριν μοιραστούν σε νύχτες και υπνάκους).
class _SleepGroup {
  _SleepGroup(SleepRecord first, {required this.isNight}) : parts = [first];
  final List<SleepRecord> parts;
  final bool isNight;
  final List<(DateTime, DateTime)> gaps = [];
  int get minutes => parts.fold(0, (s, p) => s + p.minutes);
  DateTime get end => parts.map((p) => p.end).reduce((a, b) => a.isAfter(b) ? a : b);
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

/// Οξυγόνο μιας νύχτας από το ρολόι: μέσο, χαμηλότερη μέτρηση, λεπτά κάτω από 90% (αν βγαίνουν).
typedef NightOxygen = ({double avg, double min, double? below90});

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
  });

  final DateTime time;
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
  });

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

  factory Dashboard.fromJson(Map<String, dynamic> j) {
    DateTime t(dynamic ms) => DateTime.fromMillisecondsSinceEpoch((ms as num).toInt());
    List<dynamic> list(String key) => j[key] is List ? j[key] as List<dynamic> : const [];
    double? d(dynamic v) => v is num ? v.toDouble() : null;

    List<Sample> samples(String key) => [
          for (final e in list(key))
            if (e is List && e.length >= 3)
              Sample(
                t(e[0]),
                t(e[1]),
                (e[2] as num).toDouble(),
                e.length > 3 ? (e[3] as num).toDouble() : (e[2] as num).toDouble(),
                e.length > 4 ? (e[4] as num).toDouble() : (e[2] as num).toDouble(),
                e.length > 5 && e[5] is num ? (e[5] as num).toDouble() : null,
              ),
        ];

    final records = <SleepRecord>[
      for (final e in list('sleep'))
        if (e is Map<String, dynamic>)
          () {
            final start = t(e['start']);
            final end = t(e['end']);
            final stages = <Stage>[
              for (final s in (e['stages'] as List<dynamic>? ?? const []))
                if (s is List && s.length >= 3) Stage(s[0].toString(), t(s[1]), t(s[2])),
            ]..sort((a, b) => a.start.compareTo(b.start));
            final minutes = (e['minutes'] as num?)?.toInt() ?? end.difference(start).inMinutes;
            return SleepRecord(start, end, minutes, (e['score'] as num?)?.toInt(), stages);
          }(),
    ]..sort((a, b) => a.start.compareTo(b.start));

    final heart = samples('heart')..sort((a, b) => a.start.compareTo(b.start));
    final spo2 = samples('spo2');
    final skin = samples('skinTemp');

    final floorsByDay = <DateTime, double>{};
    for (final e in list('floors')) {
      if (e is List && e.length >= 2) {
        final day = dayOf(t(e[0]));
        floorsByDay[day] = (floorsByDay[day] ?? 0) + (e[1] as num).toDouble();
      }
    }

    final body = <BodyMeasurement>[
      for (final e in list('body'))
        if (e is Map<String, dynamic>)
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
          ),
    ]..sort((a, b) => a.time.compareTo(b.time));

    final stepsByMinute = <int, int>{
      for (final e in list('stepsMin'))
        if (e is List && e.length >= 2) (e[0] as num).toInt() ~/ 60000: (e[1] as num).toInt(),
    };
    final stepsFrom = j['stepsMin'] is List
        ? (j['stepsFrom'] is num
            ? t(j['stepsFrom'])
            : () {
                final r = j['readAt'] is num ? t(j['readAt']) : DateTime.now();
                return DateTime(r.year, r.month, r.day - 7);
              }())
        : null;

    final nights = _groupNights(records, heart: heart, stepsByMinute: stepsByMinute, stepsFrom: stepsFrom)
      ..forEach((n) => _fillNightMetrics(n, heart, spo2, skin));

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
      heart: heart,
      spo2: spo2,
      skin: skin,
      energy: [
        for (final e in list('energy'))
          if (e is List && e.length >= 2) DayValue(dayOf(t(e[0])), (e[1] as num).toDouble()),
      ],
      steps: [
        for (final e in list('steps'))
          if (e is List && e.length >= 2) DayValue(dayOf(t(e[0])), (e[1] as num).toDouble()),
      ],
      floors: [
        for (final entry in floorsByDay.entries) DayValue(entry.key, entry.value),
      ]..sort((a, b) => a.day.compareTo(b.day)),
      body: body,
      activity: j['activity'] is Map<String, dynamic> ? j['activity'] as Map<String, dynamic> : const {},
      sleepRecords: records,
      stepsByMinute: stepsByMinute,
      stepsMinuteFrom: stepsFrom,
      activityDaily: [
        for (final e in list('activityDaily'))
          if (e is List && e.length >= 3) (dayOf(t(e[0])), (e[1] as num?)?.toInt(), (e[2] as num?)?.toDouble()),
      ],
      exercise: [
        for (final e in list('exercise'))
          if (e is List && e.length >= 2) (t(e[0]), t(e[1])),
      ],
    );
  }

  /// Ο ύπνος ομαδοποιείται σε νύχτες (απόφαση 1/11, μετά τον έλεγχο):
  /// - Η διάρκεια είναι **μόνο** ό,τι μέτρησε η Samsung (άθροισμα των κομματιών).
  /// - Κομμάτι που ακολουθεί άλλο με κενό που μοιάζει με ύπνο (sleep_gaps.dart) ανήκει στην ίδια
  ///   νύχτα. Το κενό φαίνεται χωριστά ως «πιθανός ύπνος» και **δεν** μετρά στη διάρκεια, γιατί
  ///   δεν ξεχωρίζει ύπνο από ξάπλωμα ξύπνιος.
  /// - Αλλιώς: κομμάτι που αρχίζει 10:00–18:00 και κρατά λιγότερο από 3 ώρες είναι υπνάκος.
  /// - Δύο ομάδες κομματιών με την ίδια ημερομηνία και κενό πάνω από 4 ώρες (π.χ. λαγοκοίμισμα στον
  ///   καναπέ το βράδυ): η μεγαλύτερη είναι η νύχτα· η άλλη, αν κρατά λιγότερο από 3 ώρες, υπνάκος.
  static List<Night> _groupNights(
    List<SleepRecord> records, {
    List<Sample> heart = const [],
    Map<int, int> stepsByMinute = const {},
    DateTime? stepsFrom,
  }) {
    final recs = dedupeSleep(records);
    // Ομάδες: κομμάτια ενωμένα με κενό που κρίθηκε ύπνος.
    final groups = <_SleepGroup>[];
    _SleepGroup? previous;
    for (final r in recs) {
      final last = previous?.parts.last;
      final linked = last != null &&
          previous!.isNight &&
          judgeGap(last, r, heart: heart, stepsByMinute: stepsByMinute, stepsFrom: stepsFrom) == GapVerdict.asleep;
      if (linked) {
        if (r.start.isAfter(last.end)) previous.gaps.add((last.end, r.start));
        previous.parts.add(r);
        continue;
      }
      final isNap = r.start.hour >= 10 && r.start.hour < 18 && r.minutes < 180;
      final g = _SleepGroup(r, isNight: !isNap);
      groups.add(g);
      previous = g;
    }

    final naps = <DateTime, int>{};
    void addNap(_SleepGroup g) {
      final day = dayOf(g.parts.first.start);
      naps[day] = (naps[day] ?? 0) + g.minutes;
    }

    final byDate = <DateTime, List<_SleepGroup>>{};
    for (final g in groups) {
      if (!g.isNight) {
        addNap(g);
        continue;
      }
      final end = g.end;
      final date = end.hour >= 18 ? DateTime(end.year, end.month, end.day + 1) : dayOf(end);
      byDate.putIfAbsent(date, () => []).add(g);
    }

    final nights = <Night>[];
    for (final entry in byDate.entries) {
      final list = entry.value..sort((a, b) => a.parts.first.start.compareTo(b.parts.first.start));
      final main = list.reduce((a, b) => a.minutes >= b.minutes ? a : b);
      final n = Night(entry.key);
      for (final g in list) {
        final separate = !identical(g, main) && _gapBetween(g, main) > maxGap;
        if (separate && g.minutes < 180) {
          addNap(g);
          continue;
        }
        n.parts.addAll(g.parts);
        n.estimatedGaps.addAll(g.gaps);
      }
      nights.add(n);
    }
    nights.sort((a, b) => a.date.compareTo(b.date));

    for (final n in nights) {
      n.parts.sort((a, b) => a.start.compareTo(b.start));
      n.estimatedGaps.sort((a, b) => a.$1.compareTo(b.$1));
      n.start = n.parts.first.start;
      n.end = n.parts.map((p) => p.end).reduce((a, b) => a.isAfter(b) ? a : b);
      n.minutes = n.parts.fold(0, (sum, p) => sum + p.minutes);
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
    return nights;
  }

  static Duration _gapBetween(_SleepGroup a, _SleepGroup b) {
    final first = a.parts.first.start.isBefore(b.parts.first.start) ? a : b;
    final second = identical(first, a) ? b : a;
    return second.parts.first.start.difference(first.end);
  }

  static void _fillNightMetrics(Night n, List<Sample> heart, List<Sample> spo2, List<Sample> skin) {
    bool inside(Sample s) => n.parts.any((p) => s.start.isBefore(p.end) && s.end.isAfter(p.start));

    final hr = heart.where(inside).map((s) => s.avg).toList();
    n.sleepingHr = hr.isEmpty ? null : hr.reduce((a, b) => a + b) / hr.length;

    final ox = spo2.where(inside).toList();
    if (ox.isNotEmpty) {
      n.spo2Avg = ox.map((s) => s.avg).reduce((a, b) => a + b) / ox.length;
      n.spo2Min = ox.map((s) => s.min).reduce(math.min);
      n.spo2Below90 = _below90Minutes(ox);
    }

    final st = skin.where(inside).map((s) => s.avg).toList();
    n.skinTemp = st.isEmpty ? null : st.reduce((a, b) => a + b) / st.length;
  }

  /// Οξυγόνο της νύχτας με ημερομηνία (πρωινό) [day], ΧΩΡΙΣ τον ύπνο του ρολογιού: όσο ο ύπνος έρχεται από
  /// άλλη πηγή (Oura), το οξυγόνο μένει του ρολογιού. Οι μετρήσεις οξυγόνου του ρολογιού γίνονται μόνο στον ύπνο,
  /// άρα «νύχτα» = οι μετρήσεις από τις 18:00 της προηγούμενης μέρας ως τις 12:00 του πρωινού.
  NightOxygen? watchSpo2(DateTime day) {
    final d = dayOf(day);
    final from = DateTime(d.year, d.month, d.day - 1, 18);
    final to = DateTime(d.year, d.month, d.day, 12);
    final ox = spo2.where((s) => s.start.isBefore(to) && s.end.isAfter(from) && !s.start.isBefore(from)).toList();
    if (ox.isEmpty) return null;
    return (
      avg: ox.map((s) => s.avg).reduce((a, b) => a + b) / ox.length,
      min: ox.map((s) => s.min).reduce(math.min),
      below90: _below90Minutes(ox),
    );
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

  double? get sleepBaseline => mean(previousNights().map((n) => n.minutes.toDouble()));

  double? get restingHrBaseline => mean(previousNights(14).map((n) => n.sleepingHr));

  double? get skinTempBaseline {
    final prev = previousNights(14).map((n) => n.skinTemp).whereType<double>().toList();
    return prev.length >= 3 ? mean(prev) : null;
  }

  DayValue? valueFor(List<DayValue> list, DateTime day) {
    for (final v in list.reversed) {
      if (sameDay(v.day, day)) return v;
    }
    return null;
  }

  DayValue? get latestEnergy => energy.isEmpty ? null : energy.last;

  double? get todaySteps => valueFor(steps, readAt)?.value;

  double? get stepsBaseline {
    final prev = steps.where((s) => !sameDay(s.day, readAt)).toList();
    final last7 = prev.length <= 7 ? prev : prev.sublist(prev.length - 7);
    return mean(last7.map((s) => s.value));
  }

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
  TodayCard('unusual', 'Εκτός συνηθισμένου (όταν ξεφεύγουν 2 δείκτες)', true),
  TodayCard('week', 'Απολογισμός εβδομάδας (Κυριακή βράδυ και Δευτέρα)', true),
  TodayCard('food', 'Διατροφή της ημέρας', true),
  TodayCard('steps', 'Βήματα', true),
  TodayCard('weight', 'Βάρος', true),
  TodayCard('energy', 'Energy Score', false),
  TodayCard('rhr', 'Παλμοί στον ύπνο', false),
  TodayCard('calories', 'Θερμίδες που έκαψα', false),
  TodayCard('spo2', 'Οξυγόνο στον ύπνο', false),
  TodayCard('skin', 'Θερμοκρασία καρπού στον ύπνο', false),
];

/// Έκδοση της διάταξης του «Σήμερα». Στη 2 (νέα δομή, 24/10) το Energy Score, οι παλμοί
/// και οι θερμίδες φεύγουν από την αρχική (υπάρχουν στην Υγεία και στην Άσκηση)· μπαίνουν ξανά από τις Ρυθμίσεις.
const todayLayout = 2;

class Prefs {
  Prefs(this.cards,
      {this.backfillFrom,
      this.kitchen,
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
      this.ouraConnected})
      : plan = plan ?? SourcePlan.samsungOnly;

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
    );
  }

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
      });
}

/// Μια απάντηση της Samsung, διαβασμένη: [status] (ok ή το σφάλμα), [data] αν ήταν εντάξει,
/// [sleepFailed] αν κάποιο είδος του ύπνου δεν διαβάστηκε (δες sleepReadFailed).
typedef ParsedDashboard = ({Map<String, dynamic> status, Dashboard? data, bool sleepFailed});

/// Σε ξεχωριστό νήμα (isolate), ώστε το άνοιγμα να μην «παγώνει». Αν το νήμα δεν ξεκινήσει,
/// γίνεται εδώ (πιο αργά, αλλά ποτέ «κολλημένο»).
Future<ParsedDashboard> parseDashboard(String raw) async {
  try {
    return await Isolate.run(() => parseDashboardSync(raw));
  } catch (e, st) {
    _isolateFailed(e, st);
    return parseDashboardSync(raw);
  }
}

/// Αν το νήμα δεν ξεκινά, η εφαρμογή δουλεύει (πιο αργά)· το λέμε στο Sentry μία φορά, για να το δούμε.
bool _isolateReported = false;
void _isolateFailed(Object e, StackTrace st) {
  if (_isolateReported) return;
  _isolateReported = true;
  errors.report(e, st, extra: {'where': 'isolate'});
}

/// Ένα κομμάτι ιστορικού από τη Samsung, διαβασμένο: συνόψεις ανά μέρα και αν διαβάστηκαν όλα.
typedef ParsedRange = ({bool ok, Map<String, Map<String, double>> rows, bool sleepOk, bool sleepFailed, bool anyError});

Future<ParsedRange> parseRange(String raw, DateTime from, DateTime to,
    {SourcePlan? plan, SleepWindows windows = SleepWindows.empty}) async {
  try {
    return await Isolate.run(() => parseRangeSync(raw, from, to, plan: plan, windows: windows));
  } catch (e, st) {
    _isolateFailed(e, st);
    return parseRangeSync(raw, from, to, plan: plan, windows: windows);
  }
}

ParsedRange parseRangeSync(String raw, DateTime from, DateTime to,
    {SourcePlan? plan, SleepWindows windows = SleepWindows.empty}) {
  const fail = (ok: false, rows: <String, Map<String, double>>{}, sleepOk: false, sleepFailed: false, anyError: true);
  try {
    final j = jsonDecode(raw);
    if (j is! Map<String, dynamic> || j['ok'] != true) return fail;
    final d = Dashboard.fromJson(j);
    return (
      ok: true,
      rows: summarizeRange(d, from, to, plan: plan, windows: windows),
      sleepOk: d.sleepOk,
      sleepFailed: sleepReadFailed(j),
      anyError: d.failed.isNotEmpty,
    );
  } catch (_) {
    return fail;
  }
}

ParsedDashboard parseDashboardSync(String raw) {
  Object? j;
  try {
    j = jsonDecode(raw);
  } catch (e) {
    return (status: {'ok': false, 'kind': 'other', 'message': 'Χαλασμένη απάντηση'}, data: null, sleepFailed: false);
  }
  if (j is! Map<String, dynamic>) {
    return (status: {'ok': false, 'kind': 'other', 'message': 'Κενή απάντηση'}, data: null, sleepFailed: false);
  }
  if (j['ok'] != true) {
    return (
      status: {for (final k in const ['ok', 'kind', 'message', 'code', 'resolvable']) if (j.containsKey(k)) k: j[k]},
      data: null,
      sleepFailed: false,
    );
  }
  try {
    return (status: const {'ok': true}, data: Dashboard.fromJson(j), sleepFailed: sleepReadFailed(j));
  } catch (e) {
    return (status: {'ok': false, 'kind': 'other', 'message': e.toString()}, data: null, sleepFailed: false);
  }
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
  SourcePlan get plan => _plan;
  SourcePlan _plan = SourcePlan.samsungOnly;
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
      if (decodeOuraNights(await ouraNightsFile.read()).isNotEmpty) return true;
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
    await _loadPlan();
    await _upgradeHistory();
    await startOura();
    final cached = await parseDashboard(await SamsungHealth.cachedDashboardRaw());
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

    // Το σχέδιο πηγών πριν από την ανάγνωση: η Samsung διαβάζει ύπνο του ρολογιού μόνο ως το όριό του.
    if (planState != PlanState.ok) await _loadPlan();
    await _syncPlanFile();

    // Χωρίς απάντηση σε 90″ (π.χ. κόλλησε η Samsung) δεν μένει «φορτώνει» για πάντα.
    final raw = await SamsungHealth.dashboardRaw().timeout(const Duration(seconds: 90),
        onTimeout: () => jsonEncode({'ok': false, 'kind': 'other', 'message': 'Η Samsung δεν απάντησε. Δοκίμασε ξανά.'}));
    // Οι υπολογισμοί (νύχτες, παλμοί, μερικά MB δεδομένων) σε άλλο νήμα: η οθόνη δεν «κολλάει».
    final p = await parseDashboard(raw);
    final ok = p.data != null;
    if (ok) {
      data = p.data;
      error = null;
      _lastRefresh = DateTime.now();
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
        await syncOura();
        await _updateRecentHistory(d, sleepFailed: p.sleepFailed);
        _backfill();
      }
    } else if (_canWrite) {
      // Η Samsung δεν απάντησε: το Oura διαβάζεται κανονικά (ανεξάρτητη πηγή).
      await syncOura();
    }
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
  Future<bool> savePrefsNow() => _savePrefs();

  /// `true` αν γράφτηκαν (ή δεν υπήρχε κάτι να γραφτεί).
  Future<bool> _saveDays(Set<String> keys) async {
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
  }

  /// Νέοι κανόνες ύπνου (historyRulesVersion): το ιστορικό ξαναδιαβάζεται από την αρχή και κάθε
  /// μήνας αντικαθιστά τις τιμές ύπνου του με τους νέους κανόνες, ώστε όλες οι μέρες να έχουν τον
  /// ίδιο ορισμό. Οι παλιές τιμές **δεν σβήνονται από πριν**: μένουν ώσπου να έρθουν οι νέες,
  /// ώστε μια ανάγνωση που αποτυγχάνει να μην αφήνει κενά.
  Future<void> _upgradeHistory() async {
    if (!_prefsLoaded || !_historyLoaded || prefs.historyVersion >= historyRulesVersion) return;
    prefs.backfillFrom = null;
    prefs.emptyFrom = null;
    prefs.emptyChecked = null;
    prefs.historyVersion = historyRulesVersion;
    await _savePrefs();
  }

  /// Οι τελευταίες 30 μέρες από την κανονική ανάγνωση + όλες οι ζυγίσεις.
  /// Ο ύπνος ξαναγράφεται μόνο για τις μέρες με βήματα ανά λεπτό (δες mergeHistory).
  /// [sleepFailed]: κάποιο είδος από το οποίο βγαίνει ο ύπνος δεν διαβάστηκε (δες sleepReadFailed)·
  /// τότε οι τιμές ύπνου που υπάρχουν ήδη δεν αντικαθίστανται.
  Future<void> _updateRecentHistory(Dashboard d, {bool sleepFailed = false}) async {
    final today = dayOf(d.readAt);
    // Από τη μέρα −29: η νύχτα της μέρας −30 μπορεί να ξεκίνησε πριν από την αρχή της ανάγνωσης.
    final rows = summarizeRange(d, addDays(today, -29), today, plan: plan, windows: ouraWindows);
    for (final b in d.body) {
      final k = dateKey(b.time);
      rows[k] = {
        ...?rows[k],
        if (b.weight != null) K.weight: b.weight!,
        if (b.fatPct != null) K.fatPct: b.fatPct!,
        if (b.smm != null) K.smm: b.smm!,
      };
    }
    final stepsFrom = d.stepsMinuteFrom;
    final sleepFrom = !sleepFailed && d.sleepOk && stepsFrom != null ? addDays(dayOf(stepsFrom), 1) : null;
    if (!_canWrite) return;
    final changed = mergeHistory(history, rows, sleepFrom: sleepFrom, plan: plan);
    // Μέρες με άλλη πηγή ύπνου που είχαν ακόμα τιμές νύχτας του ρολογιού (π.χ. η μέρα της σύνδεσης): φεύγουν.
    final f = plan.eras.isEmpty ? null : plan.eras.first.from;
    if (f != null) changed.addAll(stripForeignWatchNight(history, plan, from: f));
    // Ζύγιση που σβήστηκε στη Samsung / InBody: φεύγει και από το ιστορικό (Τάσεις, αναφορά γιατρού).
    // Με προφύλαξη: αν η Samsung δεν δίνει καμία ζύγιση (π.χ. μόλις επανεγκαταστάθηκε) ή θα έφευγαν
    // πολλές μαζί, δεν σβήνεται τίποτα· μια λάθος ζύγιση που σβήνεις είναι μία-δύο μέρες.
    if (d.bodyOk && d.body.isNotEmpty) {
      final copy = {for (final e in history.entries) e.key: e.value};
      final gone = removeMissingBody(copy, {for (final b in d.body) dateKey(b.time)},
          from: DateTime(today.year - 10, today.month, today.day + 1));
      if (gone.isNotEmpty && gone.length <= 3) {
        changed.addAll(removeMissingBody(history, {for (final b in d.body) dateKey(b.time)},
            from: DateTime(today.year - 10, today.month, today.day + 1)));
      }
    }
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

  /// Αποτυχίες της συμπλήρωσης σε αυτή τη χρήση της εφαρμογής: ανά μήνα (σφάλμα σε είδος ύπνου)
  /// και συνολικά (η ανάγνωση δεν έγινε καθόλου). Μετά από 3, δεν ξαναδιαβάζουμε τα ίδια
  /// σε κάθε ανανέωση (μπαταρία).
  final Map<String, int> _backfillMonthFails = {};
  int _backfillFails = 0;

  /// Ένα κομμάτι [from, cursor) από τη Samsung: διαβάζεται σε άλλο νήμα και γράφεται στο ιστορικό.
  /// Επιστρέφει null αν σταματάμε για τώρα (θα ξαναδοκιμαστεί), αλλιώς αν ήταν εντελώς άδειο.
  Future<bool?> _readChunk(DateTime from, DateTime cursor) async {
    final to = addDays(cursor, -1);
    final raw = await SamsungHealth.readRangeRaw(dateKey(from), dateKey(cursor))
        .timeout(const Duration(seconds: 120), onTimeout: () => '{"ok":false,"kind":"timeout"}');
    final p = await parseRange(raw, from, to, plan: plan, windows: ouraWindows);
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
    final tooFew = had >= 4 && got < had / 2;
    // Σφάλμα σε είδος από το οποίο βγαίνει ο ύπνος: ξανά στην επόμενη ανανέωση. Μετά από 3 φορές
    // προχωράμε, κρατώντας τις τιμές ύπνου που υπάρχουν ήδη.
    final failed = p.sleepFailed || tooFew;
    if (failed) {
      final k = dateKey(cursor);
      final n = _backfillMonthFails[k] = (_backfillMonthFails[k] ?? 0) + 1;
      if (n < 3) return null;
    }
    final saved = await _saveDays(mergeHistory(
      history,
      p.rows,
      replaceSleep: !failed && p.sleepOk,
      rangeFrom: from,
      rangeTo: to,
      plan: plan,
    ));
    // Δεν γράφτηκε στο κινητό: δεν προχωράμε, ώστε ο μήνας να ξαναδιαβαστεί.
    if (!saved) {
      _backfillFails++;
      return null;
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
  Future<void> _backfill() async {
    if (backfilling || !_canWrite || _backfillFails >= 3) return;
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
    if (gapFrom == null && !cursor.isAfter(oldest)) return;

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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    disposeOura();
    super.dispose();
  }
}
