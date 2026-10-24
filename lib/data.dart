import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'format.dart';
import 'samsung.dart';

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
  late DateTime start;
  late DateTime end;
  int minutes = 0;
  int? score;
  double? sleepingHr;
  double? spo2Avg;
  double? spo2Min;
  double? skinTemp;
  int napMinutes = 0;

  int get awakeMinutes => stageMinutes['AWAKE'] ?? 0;
}

class Sample {
  Sample(this.start, this.end, this.avg, this.min, this.max);
  final DateTime start;
  final DateTime end;
  final double avg;
  final double min;
  final double max;
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
  });

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

    final nights = _groupNights(records)
      ..forEach((n) => _fillNightMetrics(n, heart, spo2, skin));

    return Dashboard._(
      readAt: j['readAt'] is num ? t(j['readAt']) : DateTime.now(),
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
      stepsByMinute: {
        for (final e in list('stepsMin'))
          if (e is List && e.length >= 2) (e[0] as num).toInt() ~/ 60000: (e[1] as num).toInt(),
      },
      stepsMinuteFrom: j['stepsMin'] is List
          ? dayOf((j['readAt'] is num ? t(j['readAt']) : DateTime.now()).subtract(const Duration(days: 7)))
          : null,
      exercise: [
        for (final e in list('exercise'))
          if (e is List && e.length >= 2) (t(e[0]), t(e[1])),
      ],
    );
  }

  /// Ο ύπνος ομαδοποιείται σε νύχτες. Κομμάτι που αρχίζει 10:00–18:00 και κρατά λιγότερο από 3 ώρες
  /// είναι υπνάκος και μετρά χωριστά.
  static List<Night> _groupNights(List<SleepRecord> records) {
    final byDate = <DateTime, Night>{};
    final naps = <DateTime, int>{};
    for (final r in records) {
      final isNap = r.start.hour >= 10 && r.start.hour < 18 && r.minutes < 180;
      if (isNap) {
        final day = dayOf(r.start);
        naps[day] = (naps[day] ?? 0) + r.minutes;
        continue;
      }
      final date = r.end.hour >= 18 ? dayOf(r.end).add(const Duration(days: 1)) : dayOf(r.end);
      final night = byDate.putIfAbsent(date, () => Night(date));
      night.parts.add(r);
    }
    final nights = byDate.values.toList()..sort((a, b) => a.date.compareTo(b.date));
    for (final n in nights) {
      n.parts.sort((a, b) => a.start.compareTo(b.start));
      n.start = n.parts.first.start;
      n.end = n.parts.map((p) => p.end).reduce((a, b) => a.isAfter(b) ? a : b);
      n.minutes = n.parts.fold(0, (sum, p) => sum + p.minutes);
      final longest = n.parts.reduce((a, b) => a.minutes >= b.minutes ? a : b);
      n.score = longest.score ?? n.parts.map((p) => p.score).whereType<int>().fold<int?>(null, (a, b) => a == null ? b : math.max(a, b));
      for (final p in n.parts) {
        n.stages.addAll(p.stages);
      }
      n.stages.sort((a, b) => a.start.compareTo(b.start));
      for (final s in n.stages) {
        n.stageMinutes[s.name] = (n.stageMinutes[s.name] ?? 0) + s.minutes;
      }
      n.napMinutes = naps[n.date] ?? 0;
    }
    return nights;
  }

  static void _fillNightMetrics(Night n, List<Sample> heart, List<Sample> spo2, List<Sample> skin) {
    bool inside(Sample s) => n.parts.any((p) => s.start.isBefore(p.end) && s.end.isAfter(p.start));

    final hr = heart.where(inside).map((s) => s.avg).toList();
    n.sleepingHr = hr.isEmpty ? null : hr.reduce((a, b) => a + b) / hr.length;

    final ox = spo2.where(inside).toList();
    if (ox.isNotEmpty) {
      n.spo2Avg = ox.map((s) => s.avg).reduce((a, b) => a + b) / ox.length;
      n.spo2Min = ox.map((s) => s.min).reduce(math.min);
    }

    final st = skin.where(inside).map((s) => s.avg).toList();
    n.skinTemp = st.isEmpty ? null : st.reduce((a, b) => a + b) / st.length;
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

  /// Ελάχιστοι και μέγιστοι παλμοί μιας ημέρας.
  (double, double)? heartRange(DateTime day) {
    final s = heart.where((h) => sameDay(h.start, day)).toList();
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
  TodayCard('energy', 'Energy Score', true),
  TodayCard('rhr', 'Παλμοί στον ύπνο', true),
  TodayCard('steps', 'Βήματα', true),
  TodayCard('calories', 'Θερμίδες που έκαψα', true),
  TodayCard('weight', 'Βάρος και λίπος', true),
  TodayCard('spo2', 'Οξυγόνο στον ύπνο', false),
  TodayCard('skin', 'Θερμοκρασία δέρματος', false),
];

class Prefs {
  Prefs(this.cards);

  factory Prefs.fromJson(Map<String, dynamic> j) {
    final saved = j['cards'] is Map ? j['cards'] as Map : const {};
    return Prefs({
      for (final c in todayCards) c.key: saved[c.key] is bool ? saved[c.key] as bool : c.defaultOn,
    });
  }

  final Map<String, bool> cards;

  bool show(String key) => cards[key] ?? true;

  String toJson() => jsonEncode({'cards': cards});
}

// ---------------------------------------------------------------------------
// Η κατάσταση της εφαρμογής: διαβάζει όταν ανοίγει και όταν επιστρέφω σε αυτήν.
// Τίποτα στο παρασκήνιο.
// ---------------------------------------------------------------------------

class HealthStore extends ChangeNotifier with WidgetsBindingObserver {
  Dashboard? data;
  bool loading = false;
  Map<String, dynamic>? error;
  Prefs prefs = Prefs.fromJson(const {});
  DateTime? _lastRefresh;

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    prefs = Prefs.fromJson(await SamsungHealth.loadPrefs());
    final cached = await SamsungHealth.cachedDashboard();
    if (cached['ok'] == true) {
      try {
        data = Dashboard.fromJson(cached);
      } catch (_) {
        data = null;
      }
    }
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

    final r = await SamsungHealth.dashboard();
    if (r['ok'] == true) {
      try {
        data = Dashboard.fromJson(r);
        error = null;
      } catch (e) {
        error = {'ok': false, 'kind': 'other', 'message': e.toString()};
      }
      _lastRefresh = DateTime.now();
    } else {
      error = r;
    }
    loading = false;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _lastRefresh;
    if (last == null || DateTime.now().difference(last).inMinutes >= 5) {
      refresh();
    }
  }

  void setCard(String key, bool on) {
    prefs.cards[key] = on;
    notifyListeners();
    SamsungHealth.savePrefs(prefs.toJson());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
