// golden141 · ΥΓΕΙΑ (έλεγχος 20/11/2026): στιγμιότυπο των υπολογισμών του σημερινού κώδικα για πίεση/σάκχαρο/ΗΚΓ
// (vitals.dart), οξυγόνο (oxygen_note.dart), τάση HRV (hrv_trend.dart), εύρη αναφοράς (reference.dart), μορφοποιήσεις
// (format.dart), κενά ύπνου (sleep_gaps.dart), «τι συνδέεται με τον ύπνο» (sleep_links.dart), παλμούς ημέρας
// (heart_day.dart), εξετάσεις αίματος (labs/*) και Oura (oura_model.dart, oura_view.dart, από τα υπάρχοντα δείγματα του
// test/fixtures/oura/). Επινοημένα δεδομένα, σταθερές ημερομηνίες, καμία ώρα συστήματος, κανένα δίκτυο.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart' show Dashboard, Sample, SleepRecord;
import 'package:ygeia_forma/food/food_model.dart' show DayMark, Food, LogEntry, Meal, NValue, Nk, Nutrients;
import 'package:ygeia_forma/format.dart' as fmt;
import 'package:ygeia_forma/heart_day.dart';
import 'package:ygeia_forma/history.dart' show K, dateKey;
import 'package:ygeia_forma/hrv_trend.dart';
import 'package:ygeia_forma/labs/catalog.dart';
import 'package:ygeia_forma/labs/lab_number.dart';
import 'package:ygeia_forma/labs/lab_result.dart';
import 'package:ygeia_forma/oura/oura_model.dart';
import 'package:ygeia_forma/oura/oura_view.dart';
import 'package:ygeia_forma/oxygen_note.dart';
import 'package:ygeia_forma/pages/report_page.dart' show reportVitals;
import 'package:ygeia_forma/profile.dart' show Profile;
import 'package:ygeia_forma/reference.dart';
import 'package:ygeia_forma/sleep_gaps.dart';
import 'package:ygeia_forma/sleep_links.dart';
import 'package:ygeia_forma/sources.dart' show Source, SourceEra, SourcePlan;
import 'package:ygeia_forma/vitals.dart';

import 'golden141_common.dart';
import 'sample_data.dart' show sampleDashboardJson;

// ------------------------------------------------------------- πίεση, σάκχαρο, ΗΚΓ, οξυγόνο, HRV, εύρη, μορφοποίηση

Vital _bp(String id, DateTime at, int sys, int dia, [int? pulse]) => Vital(id: id, kind: VitalKind.bp, at: at, sys: sys, dia: dia, pulse: pulse);

Map<String, Object?>? _range(RefRange? r, List<double> probes) => r == null
    ? null
    : <String, Object?>{
        'low': r.low,
        'high': r.high,
        'nearBelow': r.nearBelow,
        'text': r.text,
        'cite': r.cite,
        'place': <String, Object?>{for (final v in probes) '$v': '${r.place(v)} · ${r.placeText(v)}'},
      };

Map<String, Object?> _guidance(OxygenGuidance g) => g141Compact(<String, Object?>{
      'veryLowLastNight': g.veryLowLastNight,
      'lowNights': g.lowNights,
      'measuredNights': g.measuredNights,
      'veryLowNights30': g.veryLowNights30,
      'veryLowList': [for (final e in g.veryLowList) '${g141Day(e.$1)}=${e.$2}'],
      'veryLowRepeated|repeated|any': '${g.veryLowRepeated}|${g.repeated}|${g.any}',
      'messages': g.messages,
      'short': g.short,
    });

Map<String, Object?> _vitalsGolden() {
  final out = <String, Object?>{};
  out['constants'] = <String, Object?>{
    'homeBp': [homeBpSys, homeBpDia, homeBpElevSys, homeBpElevDia],
    'bpMin': [bpMinDays, bpMinReadings],
    'oxygen': [oxygenVeryLow, oxygenLow, oxygenRepeatNights, oxygenWindowNights, oxygenLongWindowNights, oxygenVeryLowRepeatNights],
    'hrv': [hrvWeekMin, hrvBaseDays, hrvBaseMin, hrvBandSd],
    'reference': [sleepNearBelowMin, fatNearBelow],
  };
  out['texts'] = <String, Object?>{
    'glucoseWhen': <String, Object?>{for (final w in GlucoseWhen.values) w.name: glucoseWhenText(w)},
    'ecg': <String, Object?>{for (final r in EcgResult.values) r.name: '${ecgText(r)} · ${ecgNote(r)}'},
    'oxygen': <String, Object?>{
      'veryLow': oxygenVeryLowText,
      'redFlag': oxygenRedFlagText,
      'apneaShort': oxygenApneaShort,
      'noNote': oxygenNoNoteText,
      'aboutShort': oxygenAboutShort,
      'source': oxygenSourceText,
      'avgLabel': oxygenAvgLabel,
      'minLabel': oxygenMinLabel,
      'range': oxygenRangeText,
      'about': oxygenAboutText,
      'heartRhythm': heartRhythmNote,
      'lowContext': oxygenLowContext,
      'lowCite': oxygenLowCite,
      'veryLowTextFor same day': oxygenVeryLowTextFor(DateTime(2026, 11, 23, 7), DateTime(2026, 11, 23, 22)),
      'veryLowTextFor older night': oxygenVeryLowTextFor(DateTime(2026, 11, 21), DateTime(2026, 11, 23)),
      'veryLowTextFor no today': oxygenVeryLowTextFor(DateTime(2026, 11, 21), null),
      'repeat 3 of 5': oxygenRepeatText(3, 5),
      'veryLowRepeat 2': oxygenVeryLowRepeatText(2),
      'veryLowRepeat with nights': oxygenVeryLowRepeatText(2, [(DateTime(2026, 11, 3), 78.96), (DateTime(2026, 11, 20), 74.0)]),
    },
  };

  // Πίεση: τι γίνεται δεκτό, ο μέσος όρος 7 ημερών και το κείμενό του γύρω από κάθε όριο.
  out['bpProblem'] = <String, Object?>{
    for (final (s, d, p) in <(int, int, int?)>[
      (120, 80, null),
      (59, 40, null),
      (60, 40, null),
      (260, 100, null),
      (261, 100, null),
      (120, 29, null),
      (120, 30, null),
      (200, 160, null),
      (200, 161, null),
      (80, 80, null),
      (80, 81, null),
      (81, 80, null),
      (120, 80, 24),
      (120, 80, 25),
      (120, 80, 230),
      (120, 80, 231),
    ])
      '$s/$d/$p': bpProblem(s, d, p),
  };
  out['glucoseProblem'] = <String, Object?>{for (final g in [19.9, 20.0, 600.0, 600.1]) '$g': glucoseProblem(g)};
  final now = DateTime(2026, 11, 23, 20);
  out['bpNote'] = <String, Object?>{
    for (final (s, d) in [(179, 109), (180, 100), (170, 110), (180, 110), (220, 130)]) '$s/$d': bpNote(_bp('x', now, s, d)),
    'not bp': bpNote(Vital(id: 'g', kind: VitalKind.glucose, at: now, glucose: 300, when: GlucoseWhen.random)),
  };
  out['bpAverageText'] = <String, Object?>{
    for (final s in [119.5, 120.4, 120.5, 134.4, 134.5])
      for (final d in [69.5, 70.4, 70.5, 84.4, 84.5]) '$s/$d (12 μετρήσεις, 3 μέρες)': bpAverageText((sys: s, dia: d, n: 12, d: 3)),
    for (final (n, d) in [(1, 1), (11, 3), (12, 2), (12, 3), (28, 7)]) '140/90 ($n μετρήσεις, $d μέρες)': bpAverageText((sys: 140.0, dia: 90.0, n: n, d: d)),
  };
  final readings = [
    _bp('a', DateTime(2026, 11, 16, 23, 59), 200, 120),
    _bp('b', DateTime(2026, 11, 17, 0, 0), 130, 80),
    _bp('c', DateTime(2026, 11, 20, 8), 131, 85, 70),
    _bp('d', DateTime(2026, 11, 20, 20), 128, 82),
    _bp('e', now, 141, 91),
    _bp('f', now.add(const Duration(minutes: 1)), 100, 60),
    Vital(id: 'g', kind: VitalKind.glucose, at: DateTime(2026, 11, 21, 8), glucose: 99, when: GlucoseWhen.fasting),
    Vital(id: 'h', kind: VitalKind.ecg, at: DateTime(2026, 11, 22, 8), ecg: EcgResult.sinus),
  ];
  String? avg(Iterable<Vital> v, DateTime at, {int days = 7}) {
    final a = bpAverage(v, at, days: days);
    return a == null ? null : '${a.sys}/${a.dia} n=${a.n} d=${a.d} · ${bpAverageText(a)}';
  }

  out['bpAverage'] = <String, Object?>{
    '7 days': avg(readings, now),
    '8 days': avg(readings, now, days: 8),
    '1 day': avg(readings, now, days: 1),
    'next morning': avg(readings, DateTime(2026, 11, 24, 7)),
    'empty': avg(const [], now),
    'only other kinds': avg(readings.sublist(6), now),
    'around 25/10': avg([_bp('a', DateTime(2026, 10, 19, 0, 30), 120, 80), _bp('b', DateTime(2026, 10, 25, 3, 30), 130, 90)], DateTime(2026, 10, 25, 23)),
    'around 28/3': avg([_bp('a', DateTime(2027, 3, 22, 0, 30), 120, 80), _bp('b', DateTime(2027, 3, 28, 4, 30), 130, 90)], DateTime(2027, 3, 28, 23)),
    'twelve readings in three days': avg([
      for (var i = 0; i < 12; i++) _bp('r$i', DateTime(2026, 11, 21 + i ~/ 4, 8 + (i % 4) * 4), 118 + i % 5, 68 + i % 4),
    ], now),
  };
  out['reportVitals'] = [
    for (final v in reportVitals(readings, DateTime(2026, 11, 17, 15), DateTime(2026, 11, 22, 1))) v.id,
  ].join(' ');

  // Σάκχαρο: κάθε όριο, για κάθε «πότε».
  out['glucoseNote'] = <String, Object?>{
    for (final w in GlucoseWhen.values)
      for (final g in [20.0, 69.4, 69.5, 70.0, 99.4, 99.5, 100.0, 125.4, 125.5, 126.0, 199.4, 199.5, 200.0, 249.4, 249.5, 250.0, 600.0])
        '${w.name} $g': glucoseNote(Vital(id: 'g', kind: VitalKind.glucose, at: now, glucose: g, when: w)),
  };

  // Αποθηκευμένες μετρήσεις από/σε JSON.
  out['Vital.fromJson'] = <String, Object?>{
    for (final e in <String, Object?>{
      'bp': {'id': 'v1', 'k': 'bp', 'at': 1795000000000, 'sys': 128, 'dia': 82, 'pulse': 66, 'note': 'πρωί'},
      'bp no pulse, empty note': {'id': 'v1', 'k': 'bp', 'at': 1795000000000, 'sys': 128, 'dia': 82, 'note': ''},
      'bp sys as double': {'id': 'v1', 'k': 'bp', 'at': 1795000000000, 'sys': 128.0, 'dia': 82},
      'bp out of range': {'id': 'v1', 'k': 'bp', 'at': 1795000000000, 'sys': 300, 'dia': 82},
      'bp pulse out of range': {'id': 'v1', 'k': 'bp', 'at': 1795000000000, 'sys': 128, 'dia': 82, 'pulse': 300},
      'glucose': {'id': 'v2', 'k': 'glucose', 'at': 1795000000000, 'glu': 104, 'when': 'fasting'},
      'glucose no when': {'id': 'v2', 'k': 'glucose', 'at': 1795000000000, 'glu': 104},
      'glucose 19': {'id': 'v2', 'k': 'glucose', 'at': 1795000000000, 'glu': 19, 'when': 'random'},
      'ecg': {'id': 'v3', 'k': 'ecg', 'at': 1795000000000, 'ecg': 'afib'},
      'ecg unknown': {'id': 'v3', 'k': 'ecg', 'at': 1795000000000, 'ecg': 'flutter'},
      'unknown kind': {'id': 'v4', 'k': 'weight', 'at': 1795000000000},
      'empty id': {'id': '', 'k': 'ecg', 'at': 1795000000000, 'ecg': 'sinus'},
      'at as double': {'id': 'v5', 'k': 'ecg', 'at': 1795000000000.0, 'ecg': 'sinus'},
      'not a map': 'x',
    }.entries)
      e.key: Vital.fromJson(e.value)?.toJson(),
  };

  // Οξυγόνο τη νύχτα: πότε βγαίνει σημείωση.
  final last = DateTime(2026, 11, 23);
  Map<DateTime, double> nights(Map<int, double> byDaysAgo) => <DateTime, double>{
        for (final e in byDaysAgo.entries) DateTime(last.year, last.month, last.day - e.key, 6, 30): e.value,
      };
  out['oxygenGuidance'] = <String, Object?>{
    'empty': _guidance(oxygenGuidance(const {}, last)),
    'all fine': _guidance(oxygenGuidance(nights({0: 91, 1: 90, 2: 88, 3: 85, 4: 85.0}), last, today: last)),
    'last night 79.9': _guidance(oxygenGuidance(nights({0: 79.9, 1: 90}), last, today: last)),
    'last night 80.0': _guidance(oxygenGuidance(nights({0: 80.0, 1: 90}), last, today: last)),
    'last night 79.9, shown two days later': _guidance(oxygenGuidance(nights({0: 79.9, 1: 90}), last, today: DateTime(2026, 11, 25, 9))),
    'two very low: 0 and 29 days ago': _guidance(oxygenGuidance(nights({0: 79, 29: 78.5}), last, today: last)),
    'two very low: 0 and 30 days ago': _guidance(oxygenGuidance(nights({0: 79, 30: 78.5}), last, today: last)),
    'two very low, none last night': _guidance(oxygenGuidance(nights({3: 79, 12: 70, 0: 93}), last, today: last)),
    'three low in the week': _guidance(oxygenGuidance(nights({0: 84.9, 2: 84, 6: 83, 1: 95, 3: 96}), last, today: last)),
    'three low, one 7 days ago': _guidance(oxygenGuidance(nights({0: 84.9, 2: 84, 7: 83}), last, today: last)),
    'two low': _guidance(oxygenGuidance(nights({0: 84.9, 2: 84, 4: 85}), last, today: last)),
    'NaN and a future night': _guidance(oxygenGuidance(nights({0: double.nan, -1: 70, 1: 79}), last, today: last)),
    'across 25/10': _guidance(oxygenGuidance({
      for (var i = 0; i < 7; i++) DateTime(2026, 10, 20 + i, 3, 30): 84.0 + i * 0.2,
    }, DateTime(2026, 10, 26, 2), today: DateTime(2026, 10, 26))),
  };
  out['lowestText'] = <String, Object?>{for (final v in [69.0, 79.94, 79.95, 80.0, 84.99, 85.04, 85.05, 89.999, 90.0, 99.96, 100.0]) '$v': lowestText(v)};

  // Τάση HRV 7 νυχτών απέναντι στις 60 προηγούμενες.
  final today = DateTime(2026, 11, 20);
  DateTime back(int i) => DateTime(today.year, today.month, today.day - i);
  final plan = SourcePlan([SourceEra(Source.oura, back(200))]);
  Map<String, Map<String, double>> hist({required double week, double a = 36, double b = 44, int base = 60, Set<int> missing = const {}, Map<int, double> odd = const {}}) => {
        for (var i = 0; i < 7; i++)
          if (!missing.contains(i)) dateKey(back(i)): {'o.hrv': odd[i] ?? week},
        for (var i = 7; i < 7 + base; i++) dateKey(back(i)): {'o.hrv': odd[i] ?? (i.isEven ? a : b)},
      };
  Object? hrv(Map<String, Map<String, double>> h, {SourcePlan? p, DateTime? day}) {
    final t = hrvTrend(h, p ?? plan, day ?? today);
    return t == null ? null : '${t.weekMs}|${t.lowMs}|${t.highMs}|${t.band.name}|${t.weekNights}|${t.baseNights} · ${hrvTrendText(t)}';
  }

  out['hrvTrend'] = <String, Object?>{
    for (final w in [20.0, 33.0, 35.4, 35.5, 36.0, 40.0, 44.0, 44.4, 44.5, 47.0, 80.0]) 'week $w': hrv(hist(week: w)),
    '5 of 7 nights': hrv(hist(week: 40, missing: {1, 4})),
    '4 of 7 nights': hrv(hist(week: 40, missing: {1, 4, 6})),
    'base 21 nights': hrv(hist(week: 40, base: 21)),
    'base 20 nights': hrv(hist(week: 40, base: 20)),
    'outlier in base (200 ms)': hrv(hist(week: 40, odd: {10: 200, 11: 5})),
    'zero and negative values': hrv(hist(week: 40, odd: {0: 0, 1: -3, 8: 0})),
    'flat base': hrv(hist(week: 40, a: 40, b: 40)),
    'narrow base': hrv(hist(week: 41, a: 39.9, b: 40.1)),
    'Oura since 25 days ago': hrv(hist(week: 40), p: SourcePlan([SourceEra(Source.oura, back(25))])),
    'Oura since 30 days ago': hrv(hist(week: 40), p: SourcePlan([SourceEra(Source.oura, back(30))])),
    'watch only': hrv(hist(week: 40), p: SourcePlan.samsungOnly),
    'ten days later': hrv(hist(week: 40), day: DateTime(2026, 11, 30)),
  };

  // Εύρη αναφοράς: όλα τα όρια και τα κείμενα, για φύλο × ηλικία.
  Profile who(String? sex, int? age) => Profile(birthYear: age == null ? null : 2026 - age, birthMonth: 1, sex: sex, heightCm: 180);
  final refDay = DateTime(2026, 11, 23);
  out['sleepRange'] = <String, Object?>{
    for (final age in <int?>[null, 17, 18, 44, 60, 61]) 'age $age': _range(sleepRange(who('m', age), refDay), [389.9, 390, 419.9, 420, 480, 600]),
  };
  out['fatRange'] = <String, Object?>{
    for (final sex in <String?>['m', 'f', null])
      for (final age in <int?>[null, 19, 20, 39, 40, 59, 60, 79, 80])
        '$sex $age': _range(fatRange(who(sex, age), refDay), [7.0, 7.99, 8.0, 10.0, 10.99, 11.0, 18.99, 19.0, 19.99, 20.0, 21.0, 21.99, 22.0, 24.0, 24.99, 25.0, 32.99, 33.0, 36.0]),
  };
  out['stepsRange'] = <String, Object?>{
    for (final age in <int?>[null, 59, 60]) 'age $age': _range(stepsRange(who('m', age), refDay), [5999, 6000, 7999, 8000, 12000]),
  };
  out['breathRange'] = _range(breathRange, [11.79, 11.8, 15, 19.24, 19.25]);
  out['bmiRange'] = _range(bmiRange, [18.49, 18.5, 24.99, 25, 30]);
  out['bmi'] = <String, Object?>{
    'healthyWeight': <String, Object?>{
      for (final h in <double?>[null, 150, 163, 180, 180.5, 195])
        '$h': () {
          final w = healthyWeight(h);
          return w == null ? null : '${w.$1}|${w.$2} · ${healthyWeightText(w.$1, w.$2)}';
        }(),
    },
    'healthyWeightText edges': [healthyWeightText(59.9, 81.0), healthyWeightText(59.94, 80.96), healthyWeightText(59.96, 81.04)],
    'bmiOf': <String, Object?>{
      for (final (w, h) in <(double?, double?)>[(84.0, 180), (80.9, 180), (81.1, 180), (60.0, 180), (59.9, 180), (null, 180), (84.0, null)])
        '$w|$h': () {
          final b = bmiOf(w, h);
          return b == null ? null : '$b · ${bmiText(b)} · ${bmiShown(b)} · ${bmiRange.placeText(b)}';
        }(),
    },
    'bmiShown': <String, Object?>{for (final b in [18.49, 18.5, 24.94, 24.95, 24.99, 24.999999999, 25.0, 25.93, 29.96]) '$b': '${bmiShown(b)} · ${bmiText(b)}'},
    'inBodyHeight': [inBodyHeight(84.0, 25.9), inBodyHeight(84.0, 0), inBodyHeight(null, 25.9), inBodyHeight(84.0, null)],
  };
  final rows = <String, Map<String, double>>{
    for (var i = 0; i < 40; i++) dateKey(back(i)): {'o.hrv': 38.0 + (i * 7) % 9, K.sleepHr: 58.0 + (i * 5) % 6},
  };
  String? baseOf(String metric, int ago, {SourcePlan? p}) {
    final b = personalBaseline(rows, p ?? plan, metric, back(ago));
    final o = ouraBaseline(rows, p ?? plan, metric, back(ago));
    return '${b == null ? null : '${b.value}|${b.usual}|${b.count}|${b.diff}'} · oura ${o == null ? null : '${o.value}|${o.usual}|${o.count}'}';
  }

  out['baseline'] = <String, Object?>{
    'constants': [minNightsForAverage, minNightsForBaseline, baselineNights],
    for (final ago in [0, 20, 30, 36, 37, 38, 39, 40]) 'hrv −$ago': baseOf(K.hrv, ago),
    'sleepHr today (watch plan)': baseOf(K.sleepHr, 0, p: SourcePlan.samsungOnly),
    'hrv, Oura since 5 days ago': baseOf(K.hrv, 0, p: SourcePlan([SourceEra(Source.oura, back(5))])),
  };
  out['metricInfos'] = <String, Object?>{
    'stagesInfoKey': stagesInfoKey,
    'restHrException': restHrException,
    for (final e in metricInfos.entries)
      e.key: g141Compact(<String, Object?>{
        'title': e.value.title,
        'what': e.value.what,
        'shows': e.value.shows,
        'up': e.value.up,
        'down': e.value.down,
        'compare': e.value.compare,
        'accuracy': e.value.accuracy,
        'cite': e.value.cite,
      }),
  };

  // Μορφοποιήσεις (ό,τι βλέπει ο χρήστης ως αριθμό, διάρκεια, ημερομηνία).
  final dates = [DateTime(2026, 11, 23, 9, 5), DateTime(2026, 11, 29, 23, 59), DateTime(2027, 1, 1), DateTime(2027, 3, 28, 4), DateTime(2026, 10, 25, 3, 30), DateTime(2028, 2, 29, 12)];
  out['format dates'] = <String, Object?>{
    for (final d in dates)
      d.toIso8601String():
          '${fmt.longDate(d)} | ${fmt.shortDayDate(d)} | ${fmt.weekdayShort(d)} | ${fmt.dayMonth(d)} | ${fmt.dayMonthYear(d)} | ${fmt.dayMonthLong(d)} | ${fmt.hm(d)} | ${fmt.greeting(d)}',
    'relativeDay': <String, Object?>{
      for (final ago in [-1, 0, 1, 2, 6, 7, 30]) '$ago': fmt.relativeDay(DateTime(2026, 11, 23 - ago, 23, 50), DateTime(2026, 11, 23, 0, 10)),
      'across 28/3': fmt.relativeDay(DateTime(2027, 3, 27, 23, 50), DateTime(2027, 3, 29, 0, 10)),
    },
    'daysBetween': <String, Object?>{
      for (final (a, b) in [
        (DateTime(2026, 11, 23, 23, 59), DateTime(2026, 11, 24, 0, 1)),
        (DateTime(2026, 10, 24, 12), DateTime(2026, 10, 26, 12)),
        (DateTime(2027, 3, 27, 23), DateTime(2027, 3, 29, 1)),
        (DateTime(2026, 12, 31), DateTime(2027, 1, 1)),
        (DateTime(2028, 2, 28), DateTime(2028, 3, 1)),
        (DateTime(2026, 11, 24), DateTime(2026, 11, 23)),
      ])
        '${g141Day(a)}→${g141Day(b)}': fmt.daysBetween(a, b),
    },
    'sameDay': [fmt.sameDay(DateTime(2026, 11, 23, 0), DateTime(2026, 11, 23, 23, 59)), fmt.sameDay(DateTime(2026, 11, 23, 23, 59), DateTime(2026, 11, 24))],
    'datedTitle': [
      fmt.datedTitle('Ύπνος', null, DateTime(2026, 11, 23)),
      fmt.datedTitle('Ύπνος', DateTime(2026, 11, 23, 8), DateTime(2026, 11, 23)),
      fmt.datedTitle('Ύπνος', DateTime(2026, 11, 21), DateTime(2026, 11, 23)),
    ],
    'greeting hours': [for (var h = 0; h < 24; h++) fmt.greeting(DateTime(2026, 11, 23, h))[4]].join(),
    'dayOf': fmt.dayOf(DateTime(2026, 11, 23, 23, 59, 59)),
  };
  out['format durations'] = <String, Object?>{
    for (final m in [-125, -1, 0, 1, 2, 59, 60, 61, 119, 120, 125, 600, 1440])
      '$m': '${fmt.hoursMinutes(m)} | ${fmt.hoursMinutesShort(m)} | ${fmt.hmList(m)} | ${fmt.moreLessMinutes(m)} | ${fmt.signedMinutes(m)} | '
          '${m < 0 ? '-' : fmt.hoursMinutesParts(m).map((p) => '${p.$1} ${p.$2}').join(' ')}',
    'clock': <String, Object?>{for (final s in <num>[-75, -0.4, 0, 0.5, 59.4, 59.5, 60, 600, 3599, 3600, 3661, 36000]) '$s': '${fmt.clock(s)} | ${fmt.paceText(s)}'},
    'unitsGlued': fmt.unitsGlued('7 ώρες 5 λεπτά, 12 kg και 3x'),
    'dotJoin': fmt.dotJoin,
    'two': [fmt.two(0), fmt.two(7), fmt.two(12), fmt.two(123), fmt.two(-3)],
  };
  out['format numbers'] = <String, Object?>{
    for (final v in <num>[-1234.56, -0.05, -0.04, 0, 0.04, 0.05, 0.25, 0.35, 1, 2.5, 9.95, 82.25, 1234.5, 1e6])
      '$v': '${fmt.dec(v)} | ${fmt.dec(v, 0)} | ${fmt.dec(v, 2)} | ${fmt.signedDec(v)} | ${fmt.signedDec(v, 0)} | ${fmt.thousands(v)}',
    'thousands': [for (final v in <num>[999, 999.5, 1000, 12345, 1234567, -1000, -999.5, 0.4]) fmt.thousands(v)],
    'countText': [fmt.countText(0, 'νύχτα', 'νύχτες'), fmt.countText(1, 'νύχτα', 'νύχτες'), fmt.countText(2, 'νύχτα', 'νύχτες')],
    'upperGr': fmt.upperGr('Γάλα, αυγά, ΐ ΰ, ύπνος Άνω κάτω ς'),
  };
  return out;
}

// ----------------------------------------------------------------------- ύπνος: κενά, συνδέσεις· παλμοί της μέρας

Sample _hr(DateTime t, double bpm, {int minutes = 10}) => Sample(t, t.add(Duration(minutes: minutes)), bpm, bpm - 3, bpm + 4);

/// Δύο κομμάτια ύπνου με κενό [gapMin] λεπτών από τις 03:00, παλμοί ύπνου 58, παλμοί στο κενό [gapHr], [steps] βήματα στο κενό.
String _judge({required int gapMin, double? gapHr = 60, int steps = 0, bool stepData = true, bool heartEverySlot = true, DateTime? stepsFrom}) {
  final aStart = DateTime(2026, 11, 23, 0, 30), aEnd = DateTime(2026, 11, 23, 3, 0);
  final bStart = aEnd.add(Duration(minutes: gapMin)), bEnd = bStart.add(const Duration(hours: 3));
  final a = SleepRecord(aStart, aEnd, 150, 70, const []);
  final b = SleepRecord(bStart, bEnd, 180, 70, const []);
  final heart = <Sample>[
    for (var t = aStart; t.isBefore(aEnd); t = t.add(const Duration(minutes: 30))) _hr(t, 58),
    for (var t = bStart; t.isBefore(bEnd); t = t.add(const Duration(minutes: 30))) _hr(t, 58),
    if (gapHr != null)
      for (var t = aEnd; t.isBefore(bStart); t = t.add(Duration(minutes: heartEverySlot ? 10 : 70))) _hr(t, gapHr, minutes: 5),
  ];
  final stepsByMinute = <int, int>{if (steps > 0) aEnd.add(const Duration(minutes: 5)).millisecondsSinceEpoch ~/ 60000: steps};
  return judgeGap(a, b, heart: heart, stepsByMinute: stepsByMinute, stepsFrom: stepData ? (stepsFrom ?? DateTime(2026, 11, 17)) : null).name;
}

SleepSpan _span(DateTime start, int minutes) => (start: start, end: start.add(Duration(minutes: minutes)), minutes: minutes);

String _hmDay(DateTime t) => '${g141Day(t).substring(5)} ${fmt.hm(t)}';

Map<String, Object?> _grouped(List<SleepSpan> pieces, {int? Function(DateTime from, DateTime to)? stepsBetween}) {
  final sorted = [...pieces]..sort((a, b) => a.start.compareTo(b.start));
  final g = groupSleepPieces<SleepSpan>(sorted, (x) => x, stepsBetween: stepsBetween);
  return <String, Object?>{
    'nights': [
      for (final n in g.nights)
        '${g141Day(n.date)}: ${[for (final seg in n.segments) [for (final x in seg) '${_hmDay(x.start)}+${x.minutes}′'].join(' , ')].join(' | ')}'
            '${n.napLock == null ? '' : ' · napLock ${_hmDay(n.napLock!)}'} · ${n.parts.length} κομμάτια',
    ],
    'naps': <String, Object?>{
      for (final e in g.naps.entries) g141Day(e.key): [for (final x in e.value) '${_hmDay(x.start)}+${x.minutes}′'].join(' , '),
    },
  };
}

final _bread = Food(id: 'T-bread', name: 'Ψωμί (δοκιμή)', cat: 'Ψωμί', source: 'Ετικέτα', n: Nutrients({Nk.kcal: const NValue(250)}));

typedef _LinkData = ({Map<String, Map<String, double>> history, Map<String, List<LogEntry>> food, Set<String> done});

/// [nights] νύχτες ως [today]: ώρα ύπνου, παλμοί/διάρκεια ύπνου, βήματα, και βραδινό [gapH] ώρες πριν τον ύπνο.
/// Ίδια μορφή με το s3_sleep_links_test (εκεί με δικό του τυχαίο)· εδώ με G141Rng.
_LinkData _linkData(DateTime today, int nights,
    {required double Function(int i, G141Rng r) gapH, required double Function(int i, double gap, G141Rng r) hr, bool markDone = true, int seed = 7}) {
  final r = G141Rng(seed);
  final history = <String, Map<String, double>>{};
  final food = <String, List<LogEntry>>{};
  final done = <String>{};
  for (var i = 0; i < nights; i++) {
    final night = DateTime(today.year, today.month, today.day - (nights - 1 - i));
    final prev = DateTime(night.year, night.month, night.day - 1);
    final bed = 300 + (r.unit() * 60).round();
    final gap = gapH(i, r);
    final bedAt = DateTime(prev.year, prev.month, prev.day, 18, bed);
    final ate = bedAt.subtract(Duration(minutes: (gap * 60).round()));
    final minutes = 400 + r.unit() * 60;
    history[dateKey(night)] = {K.bedtime: bed.toDouble(), K.sleepHr: hr(i, gap, r), K.sleepMin: minutes};
    history[dateKey(prev)] = {...?history[dateKey(prev)], K.steps: 6000 + r.unit() * 4000};
    food[dateKey(prev)] = [
      LogEntry(id: 'l$i', day: dateKey(prev), meal: Meal.lunch, food: _bread, grams: 100, time: DateTime(prev.year, prev.month, prev.day, 14)),
      LogEntry(id: 'd$i', day: dateKey(prev), meal: Meal.dinner, food: _bread, grams: 100 + r.unit() * 200, time: ate),
    ];
    if (markDone) done.add(dateKey(prev));
  }
  return (history: history, food: food, done: done);
}

Map<String, Object?> _linksView(SleepLinksResult r) => <String, Object?>{
      'nights': r.nights,
      'ready': r.ready,
      'found': r.found.length,
      'links': [
        for (final l in r.links)
          '${l.cause.name}→${l.sleep.name} n=${l.n} rho=${l.rho.toStringAsFixed(6)} p=${l.p.toStringAsFixed(6)} split=${l.split.toStringAsFixed(4)} '
              '${l.lowMean.toStringAsFixed(4)}/${l.highMean.toStringAsFixed(4)} found=${l.found} · ${linkGroups(l).$1} / ${linkGroups(l).$2} · '
              '${linkValues(l).$1} / ${linkValues(l).$2}',
      ],
    };

Map<String, Object?> _sleepGolden() {
  final out = <String, Object?>{};
  out['constants'] = <String, Object?>{
    'maxGap': maxGap,
    'morningJoinGap': morningJoinGap,
    'maxGapSteps': maxGapSteps,
    'maxHrRise': maxHrRise,
    'fallbackMainMinutes': fallbackMainMinutes,
    'sleepLink': [sleepLinkMinNights, sleepLinkWindowDays, sleepLinkMinGroup, sleepLinkMinRho, sleepLinkAlpha],
    'heart': [minMinutesForValue, minMinutesForDayValue, restLeadMinutes],
  };

  // Κενό ανάμεσα σε δύο κομμάτια ύπνου: μετρά ως ύπνος;
  out['judgeGap'] = <String, Object?>{
    'no gap': _judge(gapMin: 0),
    'overlap': _judge(gapMin: -20),
    '20 min, calm': _judge(gapMin: 20),
    '240 min': _judge(gapMin: 240),
    '241 min': _judge(gapMin: 241),
    'no step data': _judge(gapMin: 20, stepData: false),
    'steps start after the gap': _judge(gapMin: 20, stepsFrom: DateTime(2026, 11, 23, 3, 1)),
    'steps start exactly at the gap': _judge(gapMin: 20, stepsFrom: DateTime(2026, 11, 23, 3, 0)),
    '30 steps': _judge(gapMin: 20, steps: 30),
    '31 steps': _judge(gapMin: 20, steps: 31),
    'no heart in the gap': _judge(gapMin: 20, gapHr: null),
    'heart missing in a half hour': _judge(gapMin: 100, heartEverySlot: false),
    'heart +5.0': _judge(gapMin: 20, gapHr: 63),
    'heart +5.1': _judge(gapMin: 20, gapHr: 63.1),
    'heart +12': _judge(gapMin: 20, gapHr: 70),
  };
  final minute = DateTime(2026, 11, 23, 3, 5).millisecondsSinceEpoch ~/ 60000;
  int? gs({DateTime? from, DateTime? to, int steps = 12, DateTime? end}) => gapSteps(DateTime(2026, 11, 23, 3), end ?? DateTime(2026, 11, 23, 3, 20),
      stepsByMinute: {minute: steps, minute + 30: 500}, stepsFrom: from, stepsTo: to);
  out['gapSteps'] = <String, Object?>{
    'no data': gs(),
    'data from before': gs(from: DateTime(2026, 11, 17)),
    'data from later': gs(from: DateTime(2026, 11, 23, 3, 1)),
    'longer gap': gs(from: DateTime(2026, 11, 17), end: DateTime(2026, 11, 23, 3, 40)),
    'cut, few steps': gs(from: DateTime(2026, 11, 17), to: DateTime(2026, 11, 23, 3, 10)),
    'cut, many steps': gs(from: DateTime(2026, 11, 17), to: DateTime(2026, 11, 23, 3, 10), steps: 31),
    'cut exactly at the end': gs(from: DateTime(2026, 11, 17), to: DateTime(2026, 11, 23, 3, 20)),
  };
  out['nightWindow'] = <String, Object?>{
    for (final d in [DateTime(2026, 11, 23, 15), DateTime(2026, 10, 25), DateTime(2027, 3, 28), DateTime(2027, 1, 1)])
      g141Day(d): () {
        final w = nightWindow(d);
        return '${w.from.toIso8601String()} → ${w.to.toIso8601String()}';
      }(),
  };
  out['napDateOf'] = <String, Object?>{
    for (final t in [DateTime(2026, 11, 23, 0, 30), DateTime(2026, 11, 23, 14), DateTime(2026, 11, 23, 17, 59), DateTime(2026, 11, 23, 18), DateTime(2026, 12, 31, 22), DateTime(2027, 3, 27, 19)])
      t.toIso8601String(): g141Day(napDateOf(t)),
  };
  out['groupSleepPieces'] = <String, Object?>{
    'empty': g141Safe(() => _grouped(const [])),
    'one night': g141Safe(() => _grouped([_span(DateTime(2026, 11, 22, 23, 40), 430)])),
    'night in two pieces, 20 min apart': g141Safe(() => _grouped([_span(DateTime(2026, 11, 23, 0, 30), 150), _span(DateTime(2026, 11, 23, 3, 20), 180)])),
    'two pieces, with steps in between': g141Safe(() => _grouped([_span(DateTime(2026, 11, 23, 0, 30), 150), _span(DateTime(2026, 11, 23, 3, 20), 180)], stepsBetween: (a, b) => 200)),
    'two pieces, no step data': g141Safe(() => _grouped([_span(DateTime(2026, 11, 23, 0, 30), 150), _span(DateTime(2026, 11, 23, 3, 20), 180)], stepsBetween: (a, b) => null)),
    'two pieces, 5 hours apart': g141Safe(() => _grouped([_span(DateTime(2026, 11, 22, 22), 120), _span(DateTime(2026, 11, 23, 5), 150)])),
    'night and morning piece 80 min later': g141Safe(() => _grouped([_span(DateTime(2026, 11, 23, 0, 30), 300), _span(DateTime(2026, 11, 23, 6, 50), 60)], stepsBetween: (a, b) => 500)),
    'night and morning piece 100 min later': g141Safe(() => _grouped([_span(DateTime(2026, 11, 23, 0, 30), 300), _span(DateTime(2026, 11, 23, 7, 10), 60)], stepsBetween: (a, b) => 500)),
    'afternoon nap': g141Safe(() => _grouped([_span(DateTime(2026, 11, 22, 23, 40), 430), _span(DateTime(2026, 11, 23, 15), 45)])),
    'evening nap then night': g141Safe(() => _grouped([_span(DateTime(2026, 11, 22, 19), 40), _span(DateTime(2026, 11, 23, 1), 380)])),
    'only a nap': g141Safe(() => _grouped([_span(DateTime(2026, 11, 23, 14), 50)])),
    'only a 50-minute piece at night': g141Safe(() => _grouped([_span(DateTime(2026, 11, 23, 2), 50)])),
    'only a 70-minute piece at night': g141Safe(() => _grouped([_span(DateTime(2026, 11, 23, 2), 70)])),
    'late night (after 03:00), short': g141Safe(() => _grouped([_span(DateTime(2026, 11, 23, 3, 30), 270)])),
    'three nights and naps': g141Safe(() => _grouped([
          _span(DateTime(2026, 11, 20, 23, 30), 420),
          _span(DateTime(2026, 11, 21, 16), 30),
          _span(DateTime(2026, 11, 22, 3, 10), 240),
          _span(DateTime(2026, 11, 22, 7, 40), 50),
          _span(DateTime(2026, 11, 22, 23, 50), 200),
          _span(DateTime(2026, 11, 23, 3, 40), 200),
        ])),
    'night of 25/10 (25 hours)': g141Safe(() => _grouped([_span(DateTime(2026, 10, 25, 0, 30), 480)])),
    'night of 28/3 (23 hours)': g141Safe(() => _grouped([_span(DateTime(2027, 3, 28, 0, 30), 400)])),
    'day sleeper (08:00–15:00)': g141Safe(() => _grouped([_span(DateTime(2026, 11, 23, 8), 420)])),
  };

  // «Τι συνδέεται με τον ύπνο σου».
  out['studentTwoSidedP'] = <String, Object?>{
    for (final (t, df) in [(0.0, 20.0), (1.0, 5.0), (2.0, 10.0), (2.228, 10.0), (-2.228, 10.0), (3.0, 30.0), (1.96, 1000.0), (10.0, 3.0), (2.048, 28.0), (1.701, 28.0)]) '$t|$df': studentTwoSidedP(t, df),
  };
  out['link labels'] = <String, Object?>{
    'sleep': <String, Object?>{for (final s in LinkSleep.values) s.name: linkSleepLabel(s)},
    'cause': <String, Object?>{for (final c in LinkCause.values) c.name: linkCauseLabel(c)},
    'groups and values': <String, Object?>{
      for (final c in LinkCause.values)
        for (final split in c == LinkCause.mealGap
            ? [0.9, 1.0, 1.24, 1.25, 2.5, 3.0]
            : c == LinkCause.dinnerKcal
                ? [24.9, 25.0, 624.9, 625.0, 1234.0]
                : c == LinkCause.steps
                    ? [249.0, 250.0, 6749.0, 6750.0, 12345.0]
                    : [292.0, 293.0, 352.0, 367.5, 360.0, 420.0])
          '${c.name} $split': g141Safe(() {
            final l = SleepLink(cause: c, sleep: LinkSleep.values[split.round() % 3], n: 40, rho: 0.3, p: 0.01, split: split, lowMean: 57.4, highMean: 61.5, found: true);
            return '${linkGroups(l).$1} / ${linkGroups(l).$2} · ${linkValues(l).$1} / ${linkValues(l).$2}';
          }),
    },
    'sleepMin values': () {
      const l = SleepLink(cause: LinkCause.steps, sleep: LinkSleep.sleepMin, n: 40, rho: -0.3, p: 0.01, split: 7000, lowMean: 389.5, highMean: 421.4, found: true);
      return '${linkValues(l).$1} / ${linkValues(l).$2}';
    }(),
  };
  final mealTime = DateTime(2026, 11, 22, 21, 10);
  LogEntry entry(String id) => LogEntry(id: id, day: '2026-11-22', meal: Meal.dinner, food: _bread, grams: 100, time: mealTime);
  out['writtenAt'] = <String, Object?>{
    for (final id in ['d5', '${DateTime(2026, 11, 23, 9, 10).microsecondsSinceEpoch}-abc', '123-abc', '-5', '${DateTime(2019, 12, 31).microsecondsSinceEpoch}-old', '99999999999999999999-x'])
      id: writtenAt(entry(id)),
  };
  final today = DateTime(2026, 12, 31);
  Map<String, Object?> links(_LinkData d, {DateTime? at, bool stable = false, SourcePlan? plan}) {
    List<LogEntry> entries(DateTime day) => d.food[dateKey(day)] ?? const [];
    DayMark? mark(DateTime day) => d.done.contains(dateKey(day)) ? DayMark.done : null;
    final r = stable
        ? sleepLinksStable(history: d.history, plan: plan ?? SourcePlan.samsungOnly, today: at ?? today, entries: entries, mark: mark)
        : sleepLinks(history: d.history, plan: plan ?? SourcePlan.samsungOnly, today: at ?? today, entries: entries, mark: mark);
    return _linksView(r);
  }

  final strong = _linkData(today, 84, gapH: (i, r) => 1 + r.unit() * 3, hr: (i, gap, r) => 64 - gap * 2 + r.noise(1.5));
  final none = _linkData(today, 84, gapH: (i, r) => 1 + r.unit() * 3, hr: (i, gap, r) => 60 + r.noise(3));
  out['sleepLinks'] = <String, Object?>{
    'late dinner → higher sleep HR (84 nights)': g141Safe(() => links(strong)),
    'same, stable over 4 weeks': g141Safe(() => links(strong, stable: true)),
    'no connection': g141Safe(() => links(none)),
    '27 nights': g141Safe(() => links(_linkData(today, 27, gapH: (i, r) => 1 + r.unit() * 3, hr: (i, gap, r) => 64 - gap * 2 + r.noise(1.5)))),
    '28 nights': g141Safe(() => links(_linkData(today, 28, gapH: (i, r) => 1 + r.unit() * 3, hr: (i, gap, r) => 64 - gap * 2 + r.noise(1.5)))),
    '40 nights': g141Safe(() => links(_linkData(today, 40, gapH: (i, r) => 1 + r.unit() * 3, hr: (i, gap, r) => 64 - gap * 2 + r.noise(1.5)))),
    'days not marked done': g141Safe(() => links(_linkData(today, 84, gapH: (i, r) => 1 + r.unit() * 3, hr: (i, gap, r) => 64 - gap * 2 + r.noise(1.5), markDone: false))),
    'weak connection': g141Safe(() => links(_linkData(today, 84, gapH: (i, r) => 1 + r.unit() * 3, hr: (i, gap, r) => 61 - gap * 0.5 + r.noise(3), seed: 11))),
    'two weeks earlier': g141Safe(() => links(strong, at: DateTime(2026, 12, 17))),
    'empty': g141Safe(() => links((history: <String, Map<String, double>>{}, food: <String, List<LogEntry>>{}, done: <String>{}))),
  };

  // Παλμοί της μέρας (ηρεμία, ζώνες κίνησης) από το δείγμα των δεδομένων του ρολογιού.
  out['heart bands'] = <String, Object?>{for (final b in HeartBand.values) b.name: '${bandLabel(b)} · ${bandHint(b)}'};
  String fig(HeartFigure f) => '${f.value?.toStringAsFixed(4)}@${f.minutes.toStringAsFixed(1)}′${f.enough ? '' : ' (λίγα)'}';
  final days = <String, Object?>{};
  for (final now in [DateTime(2026, 10, 24, 16, 30), DateTime(2026, 10, 25, 19, 10), DateTime(2027, 3, 29, 9)]) {
    days[now.toIso8601String()] = g141Safe(() {
      final d = Dashboard.fromJson(sampleDashboardJson(now));
      return <String, Object?>{
          'hasStepCoverage': [for (final ago in [0, 6, 7, 8]) d.hasStepCoverage(DateTime(now.year, now.month, now.day - ago))],
          'outside coverage': d.heartForDay(DateTime(now.year, now.month, now.day - 8)) == null,
          'days': [
            for (final h in d.recentHeartDays())
              '${g141Day(h.day)} δείγματα ${h.samples} κάθε ${h.typicalInterval}′ · εκτός: ύπνος ${h.excludedSleepMinutes.toStringAsFixed(1)}′ άσκηση '
                  '${h.excludedExerciseMinutes.toStringAsFixed(1)}′ · ξύπνιος ${fig(h.awake)} · ηρεμία ${fig(h.resting)} · '
                  '${[for (final b in HeartBand.values) '${b.name} ${fig(h.bands[b]!)}'].join(' · ')}',
          ],
          'no sleep ranges': () {
            final h = d.heartForDay(now, sleepRanges: const [], appRanges: const []);
            return h == null ? null : 'ξύπνιος ${fig(h.awake)} · ηρεμία ${fig(h.resting)} · ύπνος ${h.excludedSleepMinutes}';
          }(),
          'own exercise 10:00–11:00': () {
            final h = d.heartForDay(now, appRanges: [(DateTime(now.year, now.month, now.day, 10), DateTime(now.year, now.month, now.day, 11))]);
            return h == null ? null : 'άσκηση ${h.excludedExerciseMinutes} · ηρεμία ${fig(h.resting)}';
          }(),
        };
    });
  }
  out['heartForDay'] = days;
  return out;
}

// ----------------------------------------------------------------------------------------------- εξετάσεις αίματος

Map<String, Object?> _labsGolden() {
  final out = <String, Object?>{};
  out['catalog'] = <String, Object?>{
    'shortCodeLength': shortCodeLength,
    'cats': <String, Object?>{for (final e in labCatNames.entries) e.key.name: e.value},
    'tests': <String, Object?>{
      for (final t in labCatalog)
        t.id: <String, Object?>{
          'name': t.name,
          'cat': t.cat.name,
          'unit': t.unit,
          'decimals': t.decimals,
          'loinc': t.loinc,
          'units': <String, Object?>{for (final u in t.units.entries) u.key: '×${u.value.factor} +${u.value.offset} · 1→${u.value.toBase(1)} · 100←${u.value.fromBase(100)}'},
          'aliases': t.aliases,
          'toBase': <String, Object?>{
            for (final u in <String>{t.unit, t.unit.toUpperCase(), ...t.units.keys, 'κάτι'}) u: toBase(t, 10, u),
          },
        },
    },
    'labById': labById.length,
  };
  // Κάθε γνωστό όνομα εξέτασης πρέπει να αναγνωρίζεται ως η εξέτασή του· ό,τι όχι, γράφεται εδώ.
  out['aliases not matching their own test'] = g141Safe(() => [
        for (final t in labCatalog)
          for (final a in [t.name, ...t.aliases])
            if (matchTest(a) != t.id) '${t.id}: «$a» → ${matchTest(a)}',
      ]);
  const names = [
    'Χοληστερόλη ολική', 'ΧΟΛΗΣΤΕΡΙΝΗ', 'Cholesterol total', 'LDL', 'LDL-C', 'LDL χοληστερόλη (υπολογιζόμενη)', 'HDL', 'HDL-χοληστερίνη', 'Non-HDL', 'Τριγλυκερίδια',
    'TRIGLYCERIDES', 'Γλυκόζη', 'Σάκχαρο αίματος', 'Γλυκόζη ορού', 'Γλυκόζη ούρων', 'Glu', 'HbA1c', 'Γλυκοζυλιωμένη', 'Ινσουλίνη', 'Κρεατινίνη', 'Κρεατινίνη ορού',
    'Creatinine serum', 'eGFR', 'eGFR (CKD-EPI)', 'Ουρία', 'Ουρικό οξύ', 'SGOT', 'AST (SGOT)', 'SGPT', 'ALT', 'γ-GT', 'GGT', 'ALP', 'Χολερυθρίνη', 'Λευκωματίνη',
    'Αιμοσφαιρίνη', 'HGB', 'Αιματοκρίτης', 'Ht', 'Λευκά', 'WBC', 'RBC', 'PLT', 'Αιμοπετάλια', 'MCV', 'Φερριτίνη', 'Σίδηρος', 'Fe', 'TSH', 'FT4', 'Βιταμίνη D', '25-OH D3',
    'Vitamin D total', 'B12', 'Βιταμίνη Β12', 'Φυλλικό οξύ', 'Νάτριο', 'Na', 'Κάλιο', 'K', 'Ca', 'Ασβέστιο', 'CRP', 'hs-CRP', 'CRP υψηλής ευαισθησίας', 'PSA', 'Lp(a)',
    'ApoB', 'Άγνωστη εξέταση', 'Χ', '', '   ', 'LDL/HDL', 'Ολική/HDL', 'Σίδηρος ορού (Fe)', 'Τ3', 'Ομοκυστεΐνη',
  ];
  out['matchTest'] = <String, Object?>{
    for (final n in names) '«$n»': g141Safe(() => '${matchTest(n)} | ${matchTest(n, unit: 'mg/dL')} | ${matchTest(n, unit: 'mmol/L')} | ${matchTest(n, unit: '%')}'),
    'learned name': g141Safe(() => matchTest('Κακή χοληστερίνη', learned: {foldName('Κακή χοληστερίνη'): 'ldl'})),
    'learned unknown id': g141Safe(() => matchTest('Κακή χοληστερίνη', learned: {foldName('Κακή χοληστερίνη'): 'zzz'})),
  };
  out['foldName | unitKey'] = <String, Object?>{
    for (final s in ['Χοληστερόλη Ολική', 'ΓΛΥΚΟΖΗ (ορού)', 'γ-GT', 'Vitamin D3 25-OH', 'ΤSΗ', 'mg/dL', 'MG / DL', 'µmol/L', 'μmol/l', 'x10^3/µL', '×10³/μL', 'mL/min/1,73m²', '%', '']) '«$s»': g141Safe(() => '${foldName(s)} | ${unitKey(s)}'),
  };
  out['splitNameCode'] = <String, Object?>{
    for (final s in ['Γλυκόζη (GLU)', 'GLU - Γλυκόζη', 'Γλυκόζη', 'Χοληστερόλη ολική [CHOL]', '(HDL)', 'Κάλιο K', ''])
      '«$s»': g141Safe(() {
        final r = splitNameCode(s);
        return r == null ? null : '${r.name} | ${r.code}';
      }),
  };
  out['specimenKind'] = <String, Object?>{
    for (final s in <String?>[null, '', 'Ορός', 'serum', 'Πλάσμα', 'Ολικό αίμα', 'Ούρα', 'Urine', 'ούρα 24ώρου', 'Κόπρανα', 'Σίελος', 'κάτι άλλο']) '$s': specimenKind(s),
  };
  out['methodOf'] = <String, Object?>{
    for (final s in ['LDL (υπολογιζόμενη)', 'LDL άμεση μέτρηση', 'LDL direct', 'LDL calculated', 'eGFR (CKD-EPI)', 'eGFR MDRD', 'Γλυκόζη']) '«$s»': methodOf(s),
  };

  // Ανάγνωση αριθμών από εξετάσεις: υποδιαστολή με κόμμα ή τελεία.
  const raws = [
    '160', '5,5', '5.5', '1.234', '1,234', '12,345', '12.345', '1.234,5', '1,234.5', '0,123', '0.123', '12,34', '1234,5', '1.234.567', '1,234,567', '1,2,3', '01.234',
    '<0,5', '< 0.5', '≤ 5', '>= 1.000', '=< 3', '=>7', '≥1,5', '>1.234,5', '1 234', ' 5,5 ', '5,', ',5', 'abc', '', '5 mg', '1e5', '-5', '+5', '5-7', '１２',
  ];
  out['parseLabNumber (χωρίς ένδειξη | κόμμα | τελεία)'] = <String, Object?>{
    for (final r in raws)
      '«$r»': [
        for (final mark in <DecimalMark?>[null, DecimalMark.comma, DecimalMark.dot])
          () {
            final n = parseLabNumber(r, mark: mark);
            return n == null ? 'null' : '${n.below ? '<' : ''}${n.above ? '>' : ''}${n.value}';
          }(),
      ].join(' | '),
  };
  out['decimalMarkOf'] = <String, Object?>{
    for (final e in <String, List<String>>{
      'empty': [],
      'whole numbers': ['150', '40', '200'],
      'comma decimals': ['5,7', '150', '1,02'],
      'dot decimals': ['5.7', '150'],
      'mixed': ['5,7', '1.02'],
      'only ambiguous': ['1,234', '2.345'],
      'thousands with decimals (el)': ['1.234,5', '160'],
      'thousands with decimals (en)': ['1,234.5'],
      'grouped twice': ['1.234.567'],
      'with signs and junk': ['<0,5', 'abc', '≥ 1,5'],
      'leading zero': ['0,123'],
    }.entries)
      e.key: decimalMarkOf(e.value)?.name,
  };

  // Ένα αποτέλεσμα: σημαία εκτός ορίων, μετατροπή μονάδας, δείγμα, αλλαγή από την προηγούμενη φορά.
  LabResult res(String name, double v, String unit, {String? id, double? lo, double? hi, bool below = false, bool above = false, String? specimen, String? lab, String? method, String day = '2030-03-05'}) =>
      LabResult(day: day, rawName: name, value: v, unit: unit, testId: id, refLo: lo, refHi: hi, below: below, above: above, specimen: specimen, lab: lab, method: method);
  String view(LabResult r) => 'flag ${r.flag} · base ${r.base} [${r.baseLo}, ${r.baseHi}] · censored ${r.censored} · notBlood ${r.notBlood} · test ${r.test?.id}';
  out['LabResult'] = <String, Object?>{
    for (final v in [129.9, 130.0, 130.1, 99.9, 100.0, 100.1]) 'ldl $v [100, 130]': view(res('LDL', v, 'mg/dL', id: 'ldl', lo: 100, hi: 130)),
    'ldl 150, only upper limit': view(res('LDL', 150, 'mg/dL', id: 'ldl', hi: 130)),
    'hdl 35, only lower limit': view(res('HDL', 35, 'mg/dL', id: 'hdl', lo: 40)),
    'no limits': view(res('LDL', 150, 'mg/dL', id: 'ldl')),
    '<0.5 with lo 0.5': view(res('CRP', 0.5, 'mg/L', id: 'crp', lo: 0.5, hi: 5, below: true)),
    '<0.6 with lo 0.5': view(res('CRP', 0.6, 'mg/L', id: 'crp', lo: 0.5, hi: 5, below: true)),
    '>5 with hi 5': view(res('CRP', 5, 'mg/L', id: 'crp', lo: 0.5, hi: 5, above: true)),
    '>4.9 with hi 5': view(res('CRP', 4.9, 'mg/L', id: 'crp', lo: 0.5, hi: 5, above: true)),
    'ldl in mmol/L': view(res('LDL', 3.9, 'mmol/L', id: 'ldl', lo: 0, hi: 3.4)),
    'glucose in mmol/l': view(res('Γλυκόζη', 6.0, 'mmol/l', id: 'glu', lo: 3.9, hi: 5.5)),
    'hba1c in mmol/mol': view(res('HbA1c', 40, 'mmol/mol', id: 'hba1c')),
    'unknown unit': view(res('LDL', 150, 'mg', id: 'ldl')),
    'unknown test': view(res('Κάτι', 5, 'mg/dL')),
    'urine glucose': view(res('Γλυκόζη', 5, 'mg/dL', id: 'glu', specimen: 'Ούρα')),
    'serum glucose': view(res('Γλυκόζη', 95, 'mg/dL', id: 'glu', specimen: 'Ορός')),
    'fromJson': <String, Object?>{
      for (final e in <String, Object?>{
        'full': {'d': '2030-03-05', 'n': 'LDL', 'v': 150, 'u': 'mg/dL', 't': 'ldl', 'lab': 'Εργαστήριο Α', 'lo': 0, 'hi': 130, 'ref': '< 130', 'm': 'calc', 'lt': true, 'gt': true, 's': 'Ορός'},
        'minimal': {'d': '2030-03-05', 'n': 'Κάτι', 'v': 5.7, 'u': ''},
        'unknown test id': {'d': '2030-03-05', 'n': 'Κάτι', 'v': 5, 'u': 'x', 't': 'zzz', 's': '  '},
        'bad day': {'d': '2026-02-30', 'n': 'LDL', 'v': 150, 'u': 'mg/dL'},
        'value as text': {'d': '2030-03-05', 'n': 'LDL', 'v': '150', 'u': 'mg/dL'},
        'value NaN': {'d': '2030-03-05', 'n': 'LDL', 'v': double.nan, 'u': 'mg/dL'},
        'not a map': 5,
      }.entries)
        e.key: LabResult.fromJson(e.value)?.toJson(),
    },
    'isDay': <String, Object?>{for (final s in ['2030-03-05', '2026-02-29', '2028-02-29', '2026-13-01', '2026-1-1', '2030-03-05T08:00', '']) s: isDay(s)},
  };
  String change(LabResult a, LabResult b) {
    final c = LabChange(a, b);
    return 'comparable ${c.comparable} · diff ${c.diff} · pct ${c.pct} · lessSure ${c.lessSure}';
  }

  out['LabChange'] = <String, Object?>{
    'ldl 150 → 131': change(res('LDL', 150, 'mg/dL', id: 'ldl'), res('LDL', 131, 'mg/dL', id: 'ldl')),
    'ldl mg/dL → mmol/L': change(res('LDL', 150, 'mg/dL', id: 'ldl'), res('LDL', 3.4, 'mmol/L', id: 'ldl')),
    'different tests': change(res('LDL', 150, 'mg/dL', id: 'ldl'), res('HDL', 35, 'mg/dL', id: 'hdl')),
    'censored': change(res('CRP', 0.5, 'mg/L', id: 'crp', below: true), res('CRP', 1.2, 'mg/L', id: 'crp')),
    'from zero': change(res('CRP', 0, 'mg/L', id: 'crp'), res('CRP', 1.2, 'mg/L', id: 'crp')),
    'other lab': change(res('LDL', 150, 'mg/dL', id: 'ldl', lab: 'Α '), res('LDL', 140, 'mg/dL', id: 'ldl', lab: 'β')),
    'same lab, other case': change(res('LDL', 150, 'mg/dL', id: 'ldl', lab: ' ΑΒ'), res('LDL', 140, 'mg/dL', id: 'ldl', lab: 'αβ ')),
    'other method': change(res('LDL', 150, 'mg/dL', id: 'ldl', method: 'calc'), res('LDL', 140, 'mg/dL', id: 'ldl', method: 'direct')),
    'unknown unit on one side': change(res('LDL', 150, 'mg/dL', id: 'ldl'), res('LDL', 140, 'κάτι', id: 'ldl')),
    'urine vs blood': change(res('Γλυκόζη', 95, 'mg/dL', id: 'glu'), res('Γλυκόζη', 5, 'mg/dL', id: 'glu', specimen: 'Ούρα')),
  };
  return out;
}

// ---------------------------------------------------------------------------------------------------------- Oura

Map<String, dynamic> _fixture(String name) => jsonDecode(File('test/fixtures/oura/$name').readAsStringSync()) as Map<String, dynamic>;

List<Map<String, dynamic>> _data(String name) => [for (final x in _fixture(name)['data'] as List) Map<String, dynamic>.from(x as Map)];

Map<String, Object?> _nightView(OuraNight n) => g141Compact(<String, Object?>{
      'json': n.toJson(),
      'row': ouraRow(n),
      'counted': [for (final x in n.counted) x.id],
      'nightMinutes': n.nightMinutes,
      'shortNight|onlyNap|hasAny': '${n.shortNight}|${n.onlyNap}|${n.hasAny}',
      'napMinutes': n.napMinutes,
      'napTimes': napTimes(n),
      'napTimes nightOnly': napTimes(n, nightOnly: true),
      'score|readiness|temp|spo2': '${n.sleepScore}|${n.readiness}|${n.tempDeviation}|${n.spo2Avg}',
      'main': n.main == null
          ? null
          : () {
              final m = n.main!;
              return '${m.type} isMain ${m.isMain} isNap ${m.isNap} short ${m.isShortNight} · ${m.wallStart.toIso8601String()}→${m.wallEnd.toIso8601String()} · '
                  'onset ${m.onset?.toIso8601String()} · ${m.totalMinutes}′ · ξύπνιος μέσα ${m.awakeInSleep} · φάσεις ${m.stages.length}';
            }(),
    });

Map<String, Object?> _ouraGolden() {
  final out = <String, Object?>{};
  out['constants'] = <String, Object?>{
    'minNightsForAverage': minNightsForAverage,
    'minNightsForBaseline': minNightsForBaseline,
    'baselineNights': baselineNights,
    'ouraScreenMetrics': ouraScreenMetrics,
    'shortNightLabel': shortNightLabel,
  };
  // Τα μικρά δείγματα (όπως στο oura_test).
  final batch = parseOura(
    sleep: [..._data('sleep_page1.json'), ..._data('sleep_page2.json')],
    dailySleep: _data('daily_sleep.json'),
    readiness: _data('daily_readiness.json'),
  );
  out['fixtures'] = <String, Object?>{
    'skipped': batch.skipped,
    'nights': <String, Object?>{for (final n in batch.nights) dateKey(n.day): g141Safe(() => _nightView(n))},
    'rows': ouraRows(batch.nights),
    'encode/decode same': jsonEncode([for (final n in decodeOuraNights(encodeOuraNights(batch.nights))) n.toJson()]) == jsonEncode([for (final n in batch.nights) n.toJson()]),
    'decode junk': [decodeOuraNights(null).length, decodeOuraNights('').length, decodeOuraNights('{').length, decodeOuraNights('[1,2]').length],
  };
  // Τα δείγματα του sandbox της Oura (περισσότερες νύχτες).
  final sandbox = parseOura(
    sleep: _data('sandbox_sleep_2026-11-02.json'),
    dailySleep: _data('sandbox_daily_sleep_2026-11-02.json'),
    readiness: _data('sandbox_daily_readiness_2026-11-02.json'),
  );
  out['sandbox'] = <String, Object?>{
    'skipped': sandbox.skipped,
    'rows': ouraRows(sandbox.nights),
    'nights': <String, Object?>{
      for (final n in sandbox.nights)
        dateKey(n.day): g141Safe(() => '${n.main?.id} · υπνάκοι ${n.naps.length} · άλλα ${n.others.length} · κομμάτια ${n.pieces.length} · ${n.nightMinutes}′ · '
            'σύντομη ${n.shortNight} · βαθμός ${n.sleepScore} · ετοιμότητα ${n.readiness} · θερμ. ${n.tempDeviation}'),
    },
  };

  // Μία περίοδος ύπνου από JSON: τι διαβάζεται και τι απορρίπτεται.
  final one = _data('sleep_page1.json').first;
  String? sleepView(Map<String, dynamic> j) {
    final s = OuraSleep.fromJson(j);
    return s == null ? null : '${s.id} ${s.type} ${g141Day(s.day)} ${s.start.toIso8601String()}→${s.end.toIso8601String()} · ${s.totalMinutes}′ · hr ${s.lowestHr}/${s.avgHr} · hrv ${s.avgHrv}';
  }

  out['OuraSleep.fromJson'] = <String, Object?>{
    'as is': sleepView(one),
    'json round trip': g141Safe(() => jsonEncode(OuraSleep.fromJson(Map<String, dynamic>.from(OuraSleep.fromJson(one)!.toJson()))?.toJson()) == jsonEncode(OuraSleep.fromJson(one)!.toJson())),
    for (final k in ['id', 'day', 'type', 'bedtime_start', 'bedtime_end', 'total_sleep_duration', 'sleep_phase_5_min'])
      'without $k': g141Safe(() => sleepView(<String, dynamic>{...one}..remove(k))),
    'end before start': g141Safe(() => sleepView(<String, dynamic>{...one, 'bedtime_end': one['bedtime_start'], 'bedtime_start': one['bedtime_end']})),
    'bad day': g141Safe(() => sleepView(<String, dynamic>{...one, 'day': '2026-13-45'})),
    'numbers as text': g141Safe(() => sleepView(<String, dynamic>{...one, 'total_sleep_duration': '25000', 'lowest_heart_rate': '52'})),
  };
  final t0 = DateTime(2026, 11, 22, 23, 40);
  out['ouraStages'] = <String, Object?>{
    for (final p in <String?>[null, '', '4', '1122334', '4422211112223332222111', '9x1'])
      '$p': g141Safe(() => [for (final s in ouraStages(p, t0, t0.add(const Duration(hours: 2)))) '$s'].length),
  };
  out['parseOuraPage'] = <String, Object?>{
    'page 1': g141Safe(() {
      final p = parseOuraPage(_fixture('sleep_page1.json'));
      return '${p.data.length} · next ${p.next}';
    }),
    'page 2': g141Safe(() {
      final p = parseOuraPage(_fixture('sleep_page2.json'));
      return '${p.data.length} · next ${p.next}';
    }),
    'empty next token': g141Safe(() => parseOuraPage({'data': [1, {'id': 'x'}], 'next_token': ''}).next),
    'not a page': g141Safe(() => parseOuraPage({'detail': 'x'}).data.length),
    'list': g141Safe(() => parseOuraPage([1, 2]).data.length),
  };
  out['selectMainSleep'] = <String, Object?>{
    'empty': selectMainSleep(const [])?.id,
    'all fixture periods': selectMainSleep([for (final j in [..._data('sleep_page1.json'), ..._data('sleep_page2.json')]) if (OuraSleep.fromJson(j) case final s?) s])?.id,
  };

  // Κείμενα της οθόνης ύπνου.
  out['texts'] = <String, Object?>{
    'stagesFromText': <String, Object?>{for (final n in [0, 1, 4, 6, 7, 30]) '$n': stagesFromText(n)},
    'atLeast': [atLeast(420), atLeast(60), atLeast(61)],
    'sleepVsAdvice': <String, Object?>{
      for (final (asleep, bed) in <(int, int?)>[(420, 480), (419, 480), (419, 420), (419, 419), (300, null), (300, 330), (480, null)])
        '$asleep|$bed': sleepVsAdvice(asleepMin: asleep, inBedMin: bed, adviceMin: 420),
    },
    'glued': [glued('7 ώρες 5 λεπτά'), gluedValue('κάτω από 3 ώρες'), gluedValue('μόνο')],
    'emptyNightText': <String, Object?>{for (final r in EmptyNight.values) r.name: emptyNightText(r)},
    'lastNightNote': <String, Object?>{
      for (final r in EmptyNight.values) r.name: '${lastNightNote(r)} ## ${lastNightNote(r, nap: '14:10–14:50', watchTonight: true)}',
    },
    'napTimes null': napTimes(null),
  };
  return out;
}

void main() {
  test('golden141 · πίεση, σάκχαρο, ΗΚΓ, οξυγόνο, HRV, εύρη αναφοράς, μορφοποιήσεις', () => runGolden('health_vitals', _vitalsGolden));
  test('golden141 · κενά ύπνου, συνδέσεις με τον ύπνο, παλμοί της μέρας', () => runGolden('health_sleep', _sleepGolden));
  test('golden141 · εξετάσεις αίματος', () => runGolden('health_labs', _labsGolden));
  test('golden141 · Oura (ανάγνωση δειγμάτων, κείμενα)', () => runGolden('health_oura', _ouraGolden));
}
