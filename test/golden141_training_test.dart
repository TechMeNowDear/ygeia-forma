// golden141 · ΠΡΟΠΟΝΗΣΗ (έλεγχος 20/11/2026): στιγμιότυπο των υπολογισμών του σημερινού κώδικα για τον επόμενο στόχο κάθε
// άσκησης (progression.dart), τον εξοπλισμό και τα φορτία που βγαίνουν (equipment.dart), την προετοιμασία (prep.dart), το
// πρόγραμμα και την επικόλλησή του (program.dart), την «χαμένη» προπόνηση (catch_up.dart), την καταγραφή (session.dart),
// τη ζώνη παλμών (zone.dart), τους παλμούς ανά σετ (set_hr.dart), την ποιότητα μέτρησης (hr_quality.dart), το περπάτημα
// (walk_stats.dart) και την πρόοδο (progress.dart). Επινοημένα δεδομένα, σταθερές ημερομηνίες, καμία ώρα συστήματος.
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/training/catch_up.dart';
import 'package:ygeia_forma/training/equipment.dart';
import 'package:ygeia_forma/training/hr_quality.dart';
import 'package:ygeia_forma/training/prep.dart';
import 'package:ygeia_forma/training/program.dart';
import 'package:ygeia_forma/training/progress.dart';
import 'package:ygeia_forma/training/progression.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/set_hr.dart';
import 'package:ygeia_forma/training/walk_stats.dart';
import 'package:ygeia_forma/training/zone.dart';
import 'package:ygeia_forma/trends.dart' show TrendPeriod, TrendResult;

import 'golden141_common.dart';
import 'training_sample.dart';

String _kg(double? v) => v == null ? '-' : v.toStringAsFixed(2);
String _list(List<double>? v) => v == null ? 'null' : '[${v.map(_kg).join(' ')}]';

// ------------------------------------------------------------------------------------------------- επόμενος στόχος

final _today = DateTime(2026, 12, 14, 18);

PlanItem _item(String ex, {int sets = 3, int lo = 8, int hi = 12, int rir = 2, double? load, String? next}) =>
    PlanItem(ex: ex, sets: sets, lo: lo, hi: hi, rir: rir, load: load, next: next);

/// Μία καταγραφή της άσκησης: σετ (φορτίο, επαναλήψεις), όλα «έγιναν».
ExLog _log(PlanItem item, List<(double?, int)> sets,
        {int? rir, List<String> pain = const [], bool skipped = false, int? plannedSets, int? firstAnswer, int? setsOverride}) =>
    ExLog(
      ex: item.ex,
      sets: setsOverride ?? item.sets,
      lo: item.lo,
      hi: item.hi,
      rir: item.rir,
      rest: item.rest,
      rirAnswer: rir,
      pain: [...pain],
      skipped: skipped,
      plannedSets: plannedSets,
      firstAnswer: firstAnswer,
      log: [for (final (l, r) in sets) SetLog(load: l, reps: r, done: true)],
    );

DateTime _ago(int days) => DateTime(_today.year, _today.month, _today.day - days, 18);

String _target(Target t) =>
    '${t.change.name} | ${_kg(t.load)} | ${t.reps.join(',')} | ${t.variant ?? '-'} | isUp ${t.isUp} | ${t.reason}';

/// Ένα «μεσαίο» φορτίο από όσα βγαίνουν με τον εξοπλισμό (για ασκήσεις με βάρος σώματος: κανένα).
double? _midLoad(LoadKind k) {
  if (!hasLoad(k)) return null;
  final a = [for (final v in available(k)) if (v > 0) v];
  return a.isEmpty ? null : a[a.length ~/ 3];
}

/// Όλες οι περιπτώσεις ιστορικού για μια άσκηση: «πρώτη φορά», «πέτυχε», «απέτυχε», διακοπές, ενόχληση κ.λπ.
Map<String, Object?> _targetsFor(PlanItem item, {bool caution = false}) {
  final k = item.kind;
  final load = _midLoad(k);
  final lo = item.lo, hi = item.hi, n = item.sets;
  final up = load == null ? null : stepUp(k, load);
  final down = load == null ? null : stepDown(k, load, allowZero: k == LoadKind.plate);
  List<(double?, int)> all(int reps, [double? l]) => [for (var i = 0; i < n; i++) (l ?? load, reps)];
  final cases = <String, List<(DateTime, ExLog)>>{
    'πρώτη φορά': const [],
    for (final ra in <int?>[null, 0, 1, 2, 3, 4]) 'στην κορυφή, άφησε $ra': [(_ago(2), _log(item, all(hi), rir: ra))],
    for (final ra in <int?>[null, 1, 2, 4]) 'μέσα στο εύρος (${lo + 1}), άφησε $ra': [(_ago(2), _log(item, all(lo + 1), rir: ra))],
    'ακριβώς στο κάτω όριο, άφησε 2': [(_ago(2), _log(item, all(lo), rir: 2))],
    'πάνω από την κορυφή (${hi + 3}), άφησε 3': [(_ago(2), _log(item, all(hi + 3), rir: 3))],
    'λίγο κάτω (${lo - 1},${lo - 2},${lo - 2}), άφησε 2': [
      (_ago(2), _log(item, [(load, lo - 1), (load, lo - 2), (load, lo - 2)], rir: 2)),
    ],
    'κάτω (${lo - 3}), άφησε 2': [(_ago(2), _log(item, all(lo - 3), rir: 2))],
    'κάτω (${lo - 2}), άφησε 0': [(_ago(2), _log(item, all(lo - 2), rir: 0))],
    'κάτω (${lo - 2}), χωρίς απάντηση': [(_ago(2), _log(item, all(lo - 2)))],
    'δύο φορές κάτω': [
      (_ago(2), _log(item, all(lo - 3), rir: 2)),
      (_ago(5), _log(item, all(lo - 3), rir: 2)),
    ],
    'δύο από τρία σετ': [(_ago(2), _log(item, [(load, lo + 2), (load, lo + 1)], rir: 2))],
    'ένα σετ παραπάνω (ίδιο φορτίο)': [(_ago(2), _log(item, [...all(hi), (load, hi - 2)], rir: 3))],
    'ένα σετ παραπάνω πιο ελαφρύ': [(_ago(2), _log(item, [...all(hi), (down, hi)], rir: 3))],
    'πρώτο σετ πιο βαρύ που δεν βγήκε': [
      (_ago(2), _log(item, [(load, lo + 2), (up ?? load, lo - 3), (up ?? load, lo - 4)], rir: 2)),
    ],
    'ενόχληση': [(_ago(2), _log(item, all(lo + 1), rir: 2, pain: const ['elbow']))],
    'ενόχληση δύο φορές': [
      (_ago(2), _log(item, all(lo + 1), rir: 2, pain: const ['shoulderR', 'άλλο'])),
      (_ago(5), _log(item, all(lo + 1), rir: 2, pain: const ['back'])),
    ],
    'ενόχληση χωρίς σετ': [(_ago(2), _log(item, const [], pain: const ['knee']))],
    'παράλειψη, πριν μέσα στο εύρος': [
      (_ago(2), _log(item, const [], skipped: true)),
      (_ago(5), _log(item, all(lo + 2), rir: 3)),
    ],
    for (final gap in [14, 15, 28, 29, 30, 100]) 'διακοπή $gap ημερών': [(_ago(gap), _log(item, all(hi), rir: 3))],
    'άνετα (4+) δύο φορές': [
      (_ago(2), _log(item, all(lo + 2), rir: 4)),
      (_ago(5), _log(item, all(lo + 1), rir: 4)),
    ],
    'στην κορυφή, έχει ήδη σηκώσει το επόμενο σκαλί': [
      (_ago(2), _log(item, all(hi), rir: 2)),
      (_ago(9), _log(item, all(lo + 1, up ?? load), rir: 2)),
    ],
    'προγραμματισμένα 4 σετ, έγιναν 3': [(_ago(2), _log(item, all(hi), rir: 3, plannedSets: 4))],
    'πρώτη απάντηση 1, μετά στην κορυφή': [(_ago(2), _log(item, all(hi), rir: 3, firstAnswer: 1))],
    'μηδέν επαναλήψεις': [(_ago(2), _log(item, all(0), rir: 0))],
  };
  return <String, Object?>{
    'load': _kg(load),
    for (final e in cases.entries) e.key: g141Safe(() => _target(nextTarget(item, e.value, _today, caution: caution))),
  };
}

Map<String, Object?> _progressionGolden() {
  final out = <String, Object?>{};
  out['constants'] = <String, Object?>{
    'startOverride': startOverride,
    'lightOnly': (lightOnly.toList()..sort()),
    'bodyLoaded': (bodyLoaded.toList()..sort()),
    'bigStepRatio': bigStepRatio,
    'maxExtraReps': maxExtraReps,
    'plateauExtraReps': plateauExtraReps,
    'closeReps': closeReps,
    'calibrateMaxJump': calibrateMaxJump,
    'calibrateBarKg': calibrateBarKg,
    'recalibrateGapDays': recalibrateGapDays,
    'defaultStart': <String, Object?>{for (final k in LoadKind.values) k.name: defaultStart(k)},
    'painNames': painNames,
  };
  out['per exercise'] = <String, Object?>{
    for (final e in exerciseLoad.entries)
      e.key: '${e.value.name} · αρχή ${_kg(startLoad(e.key, e.value))} · ετικέτα=φορτίο ${labelIsLoad(e.key, e.value)}',
  };
  out['repsBeforeStep'] = <String, Object?>{
    for (final q in [1.0, 1.05, 1.11, 1.12, 1.2, 1.25, 1.34, 1.5, 2.0])
      '$q': [
        for (final lo in [6, 8, 10, 12, 15])
          for (final g in [2, 3]) repsBeforeStep(q, lo, g),
      ].join(' '),
  };
  // Πότε μπαίνει το επόμενο σκαλί: για κάθε άσκηση και κάθε φορτίο που βγαίνει (εύρος 8–12, άφησε 2). «*» = δεν ανεβαίνει μόνο του.
  out['stepCeiling 8-12'] = <String, Object?>{
    for (final e in exerciseLoad.entries)
      if (hasLoad(e.value))
        e.key: [
          for (final v in available(e.value).take(40))
            () {
              final sc = stepCeiling(e.key, e.value, v, stepUp(e.value, v), 8, 12, 2);
              return '${_kg(v)}→${sc.reps}${sc.step ? '' : '*'}';
            }(),
        ].join(' '),
  };
  out['stepCeiling edges'] = <String, Object?>{
    for (final (name, ex, k, load, up, lo, hi, g) in <(String, String, LoadKind, double?, double?, int, int, int)>[
      ('no up', 'db_press', LoadKind.dbPair, 9.3, null, 8, 12, 2),
      ('no load', 'db_press', LoadKind.dbPair, null, 9.3, 8, 12, 2),
      ('load 0', 'crunch', LoadKind.plate, 0, 0.5, 8, 12, 2),
      ('kb 8→10 (1.25)', 'goblet', LoadKind.kb, 8, 10, 8, 12, 2),
      ('kb 10→12 (1.2)', 'goblet', LoadKind.kb, 10, 12, 8, 12, 2),
      ('pair 1.11', 'db_press', LoadKind.dbPair, 10, 11.1, 8, 12, 2),
      ('pair 1.111', 'db_press', LoadKind.dbPair, 10, 11.11, 8, 12, 2),
      ('pair 1.5', 'db_press', LoadKind.dbPair, 10, 15, 8, 12, 2),
      ('pair 1.6', 'db_press', LoadKind.dbPair, 10, 16, 8, 12, 2),
      ('pair 1.3, 12-15, g3', 'db_press', LoadKind.dbPair, 10, 13, 12, 15, 3),
      ('body-loaded pair', 'split_squat', LoadKind.dbPair, 10, 15, 8, 12, 2),
      ('bar', 'rdl', LoadKind.bar, 20, 30, 8, 12, 2),
    ])
      name: () {
        final sc = stepCeiling(ex, k, load, up, lo, hi, g);
        return '${sc.reps} step=${sc.step}';
      }(),
  };

  // Ο επόμενος στόχος: ένα είδος εξοπλισμού το καθένα, εύρος 8–12, «άφησε 2».
  const representative = [
    'rdl', 'db_press', 'db_row', 'goblet', 'leg_curl', 'band_pushdown', 'band_fly', 'assisted_pullup', 'crunch', 'reverse_crunch', 'band_er', 'face_pull', 'split_squat',
  ];
  out['nextTarget 3×8-12 rir2'] = <String, Object?>{for (final ex in representative) ex: _targetsFor(_item(ex))};
  // Άλλα εύρη και «άφησε 3», για τέσσερις ασκήσεις.
  final ranges = <String, Object?>{};
  for (final ex in ['db_press', 'rdl', 'band_pushdown', 'reverse_crunch']) {
    for (final (lo, hi) in [(6, 10), (10, 15), (12, 15)]) {
      for (final rir in [2, 3]) {
        ranges['$ex $lo-$hi rir$rir'] = _targetsFor(_item(ex, lo: lo, hi: hi, rir: rir));
      }
    }
  }
  out['nextTarget other ranges'] = ranges;
  out['nextTarget variations'] = <String, Object?>{
    'db_press με προσοχή (caution)': _targetsFor(_item('db_press'), caution: true),
    'goblet με προσοχή (caution)': _targetsFor(_item('goblet'), caution: true),
    'pushup_bench με επόμενη παραλλαγή': _targetsFor(_item('pushup_bench', lo: 10, hi: 15, next: 'pushup_handles')),
    'db_press 4 σετ': _targetsFor(_item('db_press', sets: 4)),
    'db_press 1 σετ 5-5': _targetsFor(_item('db_press', sets: 1, lo: 5, hi: 5)),
    'db_press rir 0 στο πρόγραμμα': _targetsFor(_item('db_press', rir: 0)),
    'db_press rir 4': _targetsFor(_item('db_press', rir: 4)),
    'άγνωστη άσκηση (βάρος σώματος)': _targetsFor(_item('kati_allo')),
  };
  // Πρώτη φορά, για ΚΑΘΕ άσκηση: χωρίς φορτίο στο πρόγραμμα, με φορτίο που βγαίνει, με φορτίο που δεν βγαίνει.
  out['nextTarget first time'] = <String, Object?>{
    for (final e in exerciseLoad.entries)
      e.key: <String, Object?>{
        'χωρίς φορτίο': _target(nextTarget(_item(e.key), const [], _today)),
        if (hasLoad(e.value)) 'φορτίο 9,3': _target(nextTarget(_item(e.key, load: 9.3), const [], _today)),
        if (hasLoad(e.value)) 'φορτίο 33,3': _target(nextTarget(_item(e.key, load: 33.3), const [], _today)),
      },
  };
  // Για κάθε άλλη άσκηση: «στην κορυφή, άφησε 2» και «μέσα στο εύρος» σε κάθε φορτίο που βγαίνει (ως 12 φορτία).
  final ladder = <String, Object?>{};
  for (final e in exerciseLoad.entries) {
    if (!hasLoad(e.value)) continue;
    final item = _item(e.key);
    final loads = [for (final v in available(e.value)) if (v > 0) v];
    final step = loads.length <= 12 ? 1 : loads.length ~/ 12;
    ladder[e.key] = <String, Object?>{
      for (var i = 0; i < loads.length; i += step)
        _kg(loads[i]): () {
          final top = nextTarget(item, [(_ago(2), _log(item, [for (var s = 0; s < 3; s++) (loads[i], 12)], rir: 2))], _today);
          final mid = nextTarget(item, [(_ago(2), _log(item, [for (var s = 0; s < 3; s++) (loads[i], 10)], rir: 2))], _today);
          final back = nextTarget(item, [(_ago(30), _log(item, [for (var s = 0; s < 3; s++) (loads[i], 10)], rir: 2))], _today);
          return 'κορυφή: ${top.change.name} ${_kg(top.load)} ${top.reps.join(',')} · εύρος: ${mid.change.name} ${_kg(mid.load)} ${mid.reps.join(',')} · '
              '30 μέρες: ${back.change.name} ${_kg(back.load)}';
        }(),
    };
  }
  out['nextTarget ladder'] = ladder;
  out['nextTarget across 28/3'] = <String, Object?>{
    for (final gap in [14, 15])
      '$gap': _target(nextTarget(_item('db_press'), [(DateTime(2027, 4, 5 - gap, 23, 30), _log(_item('db_press'), [(9.3, 12), (9.3, 12), (9.3, 12)], rir: 2))],
          DateTime(2027, 4, 5, 0, 30))),
  };

  // Ρύθμιση μετά το 1ο σετ (calibrate): φορτίο × επαναλήψεις × «πόσες άφησες» (0–4, 5 = «πολύ ελαφρύ», 8).
  final cal = <String, Object?>{};
  for (final ex in representative) {
    final item = _item(ex);
    final k = item.kind;
    final a = [for (final v in available(k)) if (v > 0) v];
    final loads = a.isEmpty ? <double?>[null] : <double?>[a.first, a[a.length ~/ 3], a[(a.length * 2) ~/ 3], a.last, null];
    for (final l in loads) {
      for (final reps in [7, 8, 12, 17, 30]) {
        cal['$ex ${_kg(l)} × $reps'] = [
          for (final ra in [0, 1, 2, 3, 4, 5, 8]) '$ra:${_kg(calibrate(item, l, reps, ra))}',
        ].join(' ');
      }
    }
  }
  out['calibrate'] = cal;
  final notes = <String, Object?>{};
  for (final ex in representative) {
    final item = _item(ex);
    final a = [for (final v in available(item.kind)) if (v > 0) v];
    for (final l in a.isEmpty ? const <double>[] : <double>{a.first, a[a.length ~/ 3], a.last}) {
      for (final reps in [7, 12, 20]) {
        for (final ra in [3, 4, 5]) {
          final note = calibrateNote(item, l, reps, ra);
          if (note != null) notes['$ex ${_kg(l)} × $reps άφησε $ra'] = note;
        }
      }
    }
  }
  out['calibrateNote'] = notes;
  out['calibrate other items'] = <String, Object?>{
    'rdl 12-15 rir3, 20 kg × 15': [for (final ra in [0, 2, 4, 5, 9]) _kg(calibrate(_item('rdl', lo: 12, hi: 15, rir: 3), 20, 15, ra))].join(' '),
    'db_press 6-10, 9.3 × 10': [for (final ra in [0, 2, 4, 5, 9]) _kg(calibrate(_item('db_press', lo: 6, hi: 10), 9.3, 10, ra))].join(' '),
    'bodyweight': calibrate(_item('reverse_crunch'), null, 12, 5),
  };
  return out;
}

// ---------------------------------------------------------------------------------------------------- εξοπλισμός

Map<String, Object?> _kindView(LoadKind k) => <String, Object?>{
      'usesKg|hasLoad|onEquipment': '${usesKg(k)}|${hasLoad(k)}|${onEquipment(k)}',
      'available': available(k).length,
      'steps': [
        for (final v in available(k))
          '${_kg(v)} ↑${_kg(stepUp(k, v))} ↓${_kg(stepDown(k, v))} ↓0:${_kg(stepDown(k, v, allowZero: true))} · ${loadLabel(k, v)} · ${setupText(k, v)} · '
              '${_list(platesPerSide(k, v))}',
      ],
      'snap|fitLoad|scaled 0.9|scaled 0.8': <String, Object?>{
        for (final v in [0.0, 1.0, 4.3, 7.77, 9.3, 10.0, 12.5, 20.0, 33.3, 55.0, 200.0])
          '$v': g141Safe(() => '${_kg(snap(k, v))}|${_kg(fitLoad(k, v))}|${_kg(scaled(k, v, 0.9))}|${_kg(scaled(k, v, 0.8))}'),
      },
      'null': '${loadLabel(k, null)} · ${setupText(k, null)}',
    };

Map<String, Object?> _equipmentGolden() {
  final out = <String, Object?>{};
  equip = Equipment.standard;
  out['constants'] = <String, Object?>{
    'plateKinds': plateKinds,
    'barKg': barKg,
    'kettlebells': kettlebells,
    'bands': bands,
    'bandNames': bandNames,
    'standard': Equipment.standard.toJson(),
    'maxHandles': Equipment.maxHandles,
    'maxPlates': Equipment.maxPlates,
    'handleKg': handleKg,
    'loadKindOf unknown': loadKindOf('kati_allo').name,
  };
  out['standard'] = <String, Object?>{for (final k in LoadKind.values) k.name: _kindView(k)};
  out['bandCombos'] = <String, Object?>{for (final e in bandCombos().entries) '${e.key}': e.value.join('+')};
  out['bandPairs'] = <String, Object?>{for (final e in bandPairs().entries) '${e.key}': '${e.value.$1.join('+')} | ${e.value.$2.join('+')}'};
  out['kgText'] = <String, Object?>{for (final v in [0.0, 5.0, 9.3, 10.25, 1.005, 12.345, 100.0, 7.75]) '$v': kgText(v)};
  out['bandText'] = <String, Object?>{for (final v in [-10.0, 0.0, 10.0, 15.0, 60.0, 150.0, 160.0]) '$v': '${bandText(v)} · ${bandPairText(v)}'};
  out['platesWithLimit'] = <String, Object?>{
    for (final t in [0.0, 0.5, 1.75, 3.75, 9.25, 18.5, 18.6, 40.0]) '$t': _list(platesWithLimit(t, (p) => 2)),
    '7.5 with only 2.5s': _list(platesWithLimit(7.5, (p) => p == 2.5 ? 4 : 0)),
  };
  out['plateChange'] = <String, Object?>{
    for (final (from, a, to, b) in <(LoadKind, double?, LoadKind, double?)>[
      (LoadKind.dbPair, 9.3, LoadKind.dbPair, 9.3),
      (LoadKind.dbPair, 9.3, LoadKind.dbPair, 11.8),
      (LoadKind.dbPair, 11.8, LoadKind.db, 14.3),
      (LoadKind.db, 14.3, LoadKind.dbPair, 6.8),
      (LoadKind.bar, 20, LoadKind.bar, 27.5),
      (LoadKind.bar, 27.5, LoadKind.bar, 10),
      (LoadKind.horn, 2.5, LoadKind.horn, 6.25),
      (LoadKind.bar, 20, LoadKind.dbPair, 9.3),
      (LoadKind.kb, 8, LoadKind.kb, 10),
      (LoadKind.dbPair, null, LoadKind.dbPair, 9.3),
      (LoadKind.dbPair, 9.3, LoadKind.dbPair, 9.4),
      (LoadKind.plate, 5, LoadKind.plate, 7.5),
    ])
      '${from.name} ${_kg(a)} → ${to.name} ${_kg(b)}': plateChange(from, a, to, b),
  };
  out['Equipment.fromJson'] = <String, Object?>{
    for (final e in <String, Object?>{
      'not a map': 5,
      'empty': <String, Object?>{},
      'own': {'handleKg': 2.004, 'handles': 4, 'plates': {'5.0': 2, '2.5': 0, '1.25': 40, '0.5': 41}},
      'bounds low': {'handleKg': 0.49, 'handles': 0, 'plates': {'5.0': -1}},
      'bounds ok': {'handleKg': 0.5, 'handles': 1, 'plates': {'5.0': 0}},
      'bounds high ok': {'handleKg': 5, 'handles': 20},
      'bounds high': {'handleKg': 5.01, 'handles': 21, 'plates': 'x'},
      'handles as double': {'handles': 4.0, 'plates': {'5.0': 2.0}},
    }.entries)
      e.key: () {
        final q = Equipment.fromJson(e.value);
        return <String, Object?>{'json': q.toJson(), 'isStandard': q.isStandard};
      }(),
    'copyWith': Equipment.standard.copyWith(handleKg: 2.2, handles: 6).toJson(),
    'withPlate': Equipment.standard.withPlate(1.25, 0).withPlate(7.5, 3).toJson(),
    'count': [Equipment.standard.count(5), Equipment.standard.count(7.5), const Equipment(counts: [1, 2]).count(1.25)],
  };

  // Άλλος εξοπλισμός (περισσότερες λαβές, χωρίς δίσκους του μισού κιλού): όλα τα φορτία ξανά.
  try {
    equip = const Equipment(handleKg: 2.2, handles: 4, counts: [2, 6, 2, 0]);
    out['other equipment'] = <String, Object?>{
      'json': equip.toJson(),
      for (final k in [LoadKind.bar, LoadKind.dbPair, LoadKind.db, LoadKind.horn, LoadKind.plate]) k.name: _kindView(k),
      'nextTarget db_press στην κορυφή': _target(nextTarget(_item('db_press'), [(_ago(2), _log(_item('db_press'), [(7.2, 12), (7.2, 12), (7.2, 12)], rir: 2))], _today)),
      'nextTarget φορτίο του παλιού εξοπλισμού': _target(nextTarget(_item('db_press'), [(_ago(2), _log(_item('db_press'), [(9.3, 10), (9.3, 10), (9.3, 10)], rir: 2))], _today)),
    };
    equip = const Equipment(handleKg: 1.8, handles: 2, counts: [0, 0, 0, 0]);
    out['no plates'] = <String, Object?>{
      for (final k in [LoadKind.bar, LoadKind.dbPair, LoadKind.db, LoadKind.horn, LoadKind.plate]) k.name: _kindView(k),
    };
  } finally {
    equip = Equipment.standard;
  }

  // Προετοιμασία πριν από την προπόνηση: ποιοι δίσκοι πού.
  Map<String, Object?> prep(List<PrepIn> items, Equipment e) {
    final p = prepFor(items, e);
    return <String, Object?>{
      'lines': [for (final l in p.lines) '${l.what} · ${l.how ?? '-'} · ${l.forWhat.join(', ')}${l.later ? ' · ΜΕΤΑ' : ''}'],
      'handlesNeeded': p.handlesNeeded,
      'short': p.short,
    };
  }

  const dayA = <PrepIn>[
    (name: 'Πιέσεις', kind: LoadKind.dbPair, load: 9.3),
    (name: 'Κωπηλατική', kind: LoadKind.db, load: 14.3),
    (name: 'Goblet', kind: LoadKind.kb, load: 12),
    (name: 'Κάμψεις', kind: LoadKind.dbPair, load: 5.3),
    (name: 'Λάστιχο', kind: LoadKind.band, load: 30),
    (name: 'Κοιλιακοί', kind: LoadKind.bodyweight, load: null),
  ];
  const dayB = <PrepIn>[
    (name: 'RDL', kind: LoadKind.bar, load: 20),
    (name: 'RDL βαρύ', kind: LoadKind.bar, load: 30),
    (name: 'Πόδια', kind: LoadKind.horn, load: 6.25),
    (name: 'Crunch', kind: LoadKind.plate, load: 7.5),
    (name: 'Crunch 2', kind: LoadKind.plate, load: 10),
    (name: 'Fly', kind: LoadKind.bandPair, load: 30),
    (name: 'Έλξεις', kind: LoadKind.bandAssist, load: 0),
    (name: 'Σφυριά', kind: LoadKind.dbPair, load: 6.8),
    (name: 'Ίδιο βάρος', kind: LoadKind.db, load: 6.8),
    (name: 'Χωρίς φορτίο', kind: LoadKind.dbPair, load: null),
    (name: 'Μηδέν λάστιχο', kind: LoadKind.band, load: 0),
  ];
  out['prepFor'] = <String, Object?>{
    'day A standard': prep(dayA, Equipment.standard),
    'day B standard': prep(dayB, Equipment.standard),
    'day A, 1 handle': prep(dayA, const Equipment(handles: 1)),
    'day A, 8 handles 40 plates': prep(dayA, const Equipment(handles: 8, counts: [10, 10, 10, 10])),
    'day B, no plates': prep(dayB, const Equipment(counts: [0, 0, 0, 0])),
    'impossible': prep(const [(name: 'Λάθος', kind: LoadKind.dbPair, load: 1.0), (name: 'Μπάρα 5', kind: LoadKind.bar, load: 5), (name: 'Πολύ', kind: LoadKind.db, load: 99.9)], Equipment.standard),
    'empty': prep(const [], Equipment.standard),
  };
  return out;
}

// --------------------------------------------------------------------------- πρόγραμμα, χαμένη προπόνηση, καταγραφή

String _program({
  String id = '"id":"p1",',
  String days = '"days":{"fri":"A","sat":"B","sun":"A","mon":"B","tue":"walk","wed":"walk","thu":"walk"},',
  String a = '{"ex":"db_press","sets":3,"reps":[8,12],"rir":2,"rest":120,"load":9.3}',
  String b = '{"ex":"rdl","sets":3,"reps":[8,12],"rir":2,"rest":120,"load":20}',
  String walk = '{"id":"walk","name":"Περπάτημα","cardio":{"activity":"walk","minutes":30}}',
  String from = '"from":"2026-11-23",',
  String kind = 'ygeia-program',
}) =>
    '{"kind":"$kind","v":1,$id"name":"Πρόγραμμα","author":"claude",$from$days'
    '"workouts":[{"id":"A","name":"Προπόνηση Α","items":[$a]},{"id":"B","name":"Προπόνηση Β","items":[$b]},$walk]}';

Map<String, Object?> _paste(String text, {bool withProgram = false}) {
  final known = exerciseLoad.keys.toSet();
  final r = parseProgram(text, known);
  return g141Compact(<String, Object?>{
    'ok': r.ok,
    'errors': r.errors,
    'warnings': r.warnings,
    'program': withProgram ? r.program?.toJson() : null,
  });
}

Session _strength(String id, DateTime start, String workout, {bool finished = true, bool stopped = false, List<ExLog>? items}) => Session(
      id: id,
      workout: workout,
      name: 'Προπόνηση $workout',
      programId: 'p1',
      start: start,
      end: finished ? start.add(const Duration(minutes: 50)) : null,
      stopped: stopped,
      items: items ??
          [
            ExLog(ex: 'db_press', sets: 3, lo: 8, hi: 12, rir: 2, rest: 120, rirAnswer: 2, log: [
              for (final r in [10, 10, 9]) SetLog(load: 9.3, reps: r, done: true),
            ]),
          ],
    );

Session _walk(String id, DateTime start,
        {int sec = 1800, double? meters = 2300, double? metersEst, bool? gps = true, int? steps = 3100, int hr = 110, int? hrrEnd, int? hrr1,
        String? activity, bool finished = true, bool stopped = false, List<int>? zone, List<List<int>>? pauses, List<List<int>>? splits, bool samples = true}) {
  final s = Session(
    id: id,
    workout: 'walk',
    name: 'Περπάτημα',
    programId: 'p1',
    start: start,
    end: finished ? start.add(Duration(seconds: sec + 60)) : null,
    cardioMinutes: (sec / 60).round(),
    cardioSec: sec,
    meters: meters,
    metersEst: metersEst,
    gps: gps,
    steps: steps,
    hrAvg: hr,
    hrMax: hr + 14,
    hrrEnd: hrrEnd,
    hrr1: hrr1,
    activity: activity,
    stopped: stopped,
    pauses: pauses,
    splits: splits,
    source: 'watch',
    // Ένα δείγμα κάθε 10″: ζέσταμα 5′ από −15, μετά γύρω από τον μέσο όρο (σταθερό μοτίβο, χωρίς τυχαίο).
    hr: samples ? [for (var t = 0; t < sec; t += 10) [t, t < 300 ? hr - 15 + t ~/ 20 : hr + const [0, 2, -1, 3, -2, 1][(t ~/ 10) % 6]]] : null,
  );
  s.zoneTimes = zone;
  return s;
}

Map<String, Object?> _exView(ExLog e) => <String, Object?>{
      'kind': e.kind.name,
      'done': e.done.length,
      'complete|rowsDone|canRemoveRow|mixedLoads': '${e.complete}|${e.rowsDone}|${e.canRemoveRow}|${e.mixedLoads}',
      'workLoad': e.workLoad,
      'endLoad': e.endLoad,
      'judged': [for (final s in e.judged) '${_kg(s.load)}×${s.reps}'].join(' '),
      'doneText': e.doneText(),
      'volume': e.volume,
    };

Map<String, Object?> _programGolden() {
  final out = <String, Object?>{};
  equip = Equipment.standard;
  out['constants'] = <String, Object?>{
    'routineMaxSteps': routineMaxSteps,
    'routineMaxChars': routineMaxChars,
    'planMaxWeeks': planMaxWeeks,
    'cardioMinMinutes': cardioMinMinutes,
    'cardioMaxMinutes': cardioMaxMinutes,
    'dayShort': <String, Object?>{for (final e in dayShort.entries) '${e.key}': e.value},
    'weekdayLong': <String, Object?>{for (final e in weekdayLong.entries) '${e.key}': e.value},
    'cardioNames': Cardio.names,
    'catchUpDays': catchUpDays,
    'freeWorkoutId': freeWorkoutId,
    'steadyFromSec': Session.steadyFromSec,
    'steadyMinSamples': Session.steadyMinSamples,
  };

  // Επικόλληση προγράμματος: το σωστό και τα λάθη (τα μηνύματα που βλέπει ο χρήστης).
  final many = [for (var i = 0; i < 11; i++) '"βήμα $i"'].join(',');
  out['parseProgram'] = <String, Object?>{
    'sample (σωστό)': _paste(sampleProgramText, withProgram: true),
    'minimal (σωστό)': _paste(_program(), withProgram: true),
    'κείμενο χωρίς πρόγραμμα': _paste('Γεια, δεν έχω πρόγραμμα.'),
    'μισό': _paste(_program().substring(0, 120)),
    'μισό με αγκύλη στο τέλος': _paste('${_program().substring(0, 120)}}'),
    'άλλο είδος': _paste(_program(kind: 'ygeia-week')),
    'λίστα αντί για αντικείμενο': _paste('[{"kind":"ygeia-program"}]'),
    'λάθος μορφή (workouts όχι λίστα)': _paste('{"kind":"ygeia-program","id":"p","workouts":{"A":1}}'),
    'λάθος μορφή (άσκηση χωρίς ex)': _paste(_program(a: '{"sets":3}')),
    'χωρίς προπονήσεις': _paste('{"kind":"ygeia-program","id":"p","name":"Άδειο","days":{}}'),
    'άγνωστη άσκηση και παραλλαγή': _paste(_program(a: '{"ex":"bench_press","sets":3,"reps":[8,12],"next":"kati"}')),
    'σετ 0 και 11': _paste(_program(a: '{"ex":"db_press","sets":0}', b: '{"ex":"rdl","sets":11}')),
    'εύρος ανάποδα, πάνω από 50, μηδέν': _paste(_program(a: '{"ex":"db_press","reps":[12,8]}', b: '{"ex":"rdl","reps":[0,51]}')),
    'επαναλήψεις ως κείμενο': _paste(_program(a: '{"ex":"db_press","reps":"8-12"}', b: '{"ex":"rdl","reps":[8,12,15]}')),
    'επαναλήψεις ως ένας αριθμός': _paste(_program(a: '{"ex":"db_press","reps":10}'), withProgram: true),
    'διάλειμμα −1 και 601': _paste(_program(a: '{"ex":"db_press","rest":-1}', b: '{"ex":"rdl","rest":601}')),
    'άφησε 5, 1 και 0 (μπάρα)': _paste(_program(a: '{"ex":"db_press","rir":5},{"ex":"db_curl","rir":1}', b: '{"ex":"rdl","rir":0}'), withProgram: true),
    'αρνητικό βάρος': _paste(_program(a: '{"ex":"db_press","load":-5}')),
    'βάρη που δεν βγαίνουν': _paste(
        _program(
            a: '{"ex":"db_press","load":10},{"ex":"goblet","load":9},{"ex":"band_pushdown","load":35},{"ex":"band_fly","load":35},'
                '{"ex":"assisted_pullup","load":45},{"ex":"crunch","load":3},{"ex":"leg_curl","load":0.3},{"ex":"reverse_crunch","load":10}',
            b: '{"ex":"rdl","load":21.3}'),
        withProgram: true),
    'μέρα σε προπόνηση που δεν υπάρχει': _paste(_program(days: '"days":{"mon":"A","tue":"Γ"},')),
    'μέρες που δεν διαβάζονται': _paste(_program(days: '"days":{"Δευτέρα":"A","Τρ.":"B","8":"A","someday":"B","0":"A","sat":""},'), withProgram: true),
    'μέρες με αριθμούς και ελληνικά': _paste(_program(days: '"days":{"1":"A","τετ":"B","Παρασκευή":"A","SUN":"walk","thurs":"walk"},'), withProgram: true),
    'δύο προπονήσεις ίδιο id': _paste(_program(walk: '{"id":"A","name":"Άλλη","items":[{"ex":"db_row"}]}')),
    'προπόνηση χωρίς ασκήσεις': _paste(_program(walk: '{"id":"C","name":"Άδεια","items":[]}')),
    'αερόβια 0 και 601 λεπτά': _paste(_program(walk: '{"id":"walk","name":"Περπάτημα","cardio":{"minutes":0}},{"id":"w2","name":"Πολύ","cardio":{"minutes":601}}')),
    'πλάνο 13 εβδομάδων': _paste(_program(walk: '{"id":"walk","name":"Περπάτημα","cardio":{"minutes":30,"plan":[20,20,20,20,20,20,20,20,20,20,20,20,20]}}')),
    'πλάνο με 0 λεπτά': _paste(_program(walk: '{"id":"walk","name":"Περπάτημα","cardio":{"minutes":30,"plan":[20,0,30]}}')),
    'πλάνο χωρίς ημερομηνία έναρξης': _paste(_program(from: '', walk: '{"id":"walk","name":"Περπάτημα","cardio":{"minutes":30,"plan":[20,25,"x",null,30]}}'), withProgram: true),
    'ζέσταμα 11 βήματα': _paste(_program(walk: '{"id":"walk","name":"Περπάτημα","warmup":[$many],"cardio":{"minutes":30}}')),
    'αποθεραπεία με πολύ μεγάλο βήμα': _paste(_program(walk: '{"id":"walk","name":"Περπάτημα","cooldown":["${'α' * 161}"],"cardio":{"minutes":30}}')),
    'κείμενο γύρω και δύο μπλοκ': _paste('Πρώτα αυτό: {"x":1}\n```json\n{"kind":"άλλο"}\n```\nκαι μετά\n```\n${_program()}\n```\nτέλος }'),
    'χωρίς id (μόνο λάθη/προειδοποιήσεις)': _paste(_program(id: '')),
  };
  out['programJsonIn'] = <String, Object?>{
    'fence': programJsonIn('```json\n${_program()}\n```')?['id'],
    'bare with braces in strings': programJsonIn('πριν {"kind":"ygeia-program","id":"}{","note":"\\"}"} μετά')?['id'],
    'none': programJsonIn('{"kind":"x"}'),
  };

  // Το πρόγραμμα του δείγματος: ποια προπόνηση κάθε μέρα, εβδομάδα πλάνου, διάρκειες.
  final p = sampleProgram();
  final planned = parseProgram(
          _program(walk: '{"id":"walk","name":"Περπάτημα","cardio":{"activity":"brisk","minutes":30,"note":"χαλαρά","plan":[20,25,30,35]}}'), exerciseLoad.keys.toSet())
      .program!;
  out['program'] = <String, Object?>{
    'from': p.from,
    'forDay': <String, Object?>{
      for (var i = -2; i < 12; i++) g141Day(DateTime(2026, 11, 13 + i)): p.forDay(DateTime(2026, 11, 13 + i, 22))?.id,
    },
    'notStarted': [p.notStarted(DateTime(2026, 11, 12, 23, 59)), p.notStarted(DateTime(2026, 11, 13)), Program(id: 'x', name: 'χ').notStarted(DateTime(2020))],
    'minutes': <String, Object?>{for (final w in p.workouts) w.id: w.minutes},
    'weekOf': <String, Object?>{
      for (final d in [DateTime(2026, 11, 22), DateTime(2026, 11, 23), DateTime(2026, 11, 29, 23), DateTime(2026, 11, 30), DateTime(2027, 3, 28, 12), DateTime(2027, 3, 29), DateTime(2027, 11, 22)])
        g141Day(d): planned.weekOf(d),
    },
    'plan minutes by date': <String, Object?>{
      for (final d in [DateTime(2026, 11, 22), DateTime(2026, 11, 24), DateTime(2026, 12, 1), DateTime(2026, 12, 8), DateTime(2026, 12, 15), DateTime(2026, 12, 22), DateTime(2027, 6, 1)])
        g141Day(d): '${planned.forDay(d)?.cardio?.minutes} · ${planned.planWeekText(planned.workout('walk')!.cardio!, d)}',
    },
    'cardio': () {
      final c = planned.workout('walk')!.cardio!;
      return <String, Object?>{
        'name': c.name,
        'unknown name': Cardio(activity: 'swim').name,
        'minutesInWeek': [for (final w in [-1, 0, 1, 3, 4, 99]) c.minutesInWeek(w)],
        'planWeekText': [for (final w in [-1, 0, 3, 4]) c.planWeekText(w)],
        'no plan': [Cardio(minutes: 40).minutesInWeek(5), Cardio(minutes: 40).planWeekText(0)],
        'json': c.toJson(),
      };
    }(),
    'copy equals': planned.copy().toJson().toString() == planned.toJson().toString(),
    'workout(null)': planned.workout(null)?.id,
    'cardioMinutesPlus/Minus': <String, Object?>{for (final m in [1, 5, 6, 30, 594, 595, 596, 599, 600, 601]) '$m': '${cardioMinutesPlus(m)}|${cardioMinutesMinus(m)}'},
    'PlanItem.fromJson': <String, Object?>{
      'defaults': PlanItem.fromJson(<String, dynamic>{'ex': 'db_press'}).toJson(),
      'reps number': PlanItem.fromJson(<String, dynamic>{'ex': 'db_press', 'reps': 10.9, 'sets': 4.9, 'load': 9, 'note': ''}).toJson(),
      'reps list of 3': PlanItem.fromJson(<String, dynamic>{'ex': 'db_press', 'reps': [1, 2, 3]}).toJson(),
      'copy': _item('goblet', load: 12, next: 'x').copy().toJson(),
      'kind': [_item('goblet').kind.name, _item('kati').kind.name],
    },
    'Workout.minutes per-side': Workout(id: 'w', name: 'w', items: [_item('db_row'), _item('db_press', sets: 4)]).minutes,
  };

  // «Έχασες την προπόνηση;»: κάθε μέρα δύο εβδομάδων, με διάφορα ιστορικά.
  final sessionsSets = <String, List<Session>>{
    'καμία προπόνηση': const [],
    'έγινε η Α την Παρασκευή 13/11': [_strength('s1', DateTime(2026, 11, 13, 19), 'A')],
    'έγινε η Β την Κυριακή αντί για την Α': [_strength('s1', DateTime(2026, 11, 15, 19), 'B')],
    'μισή (όχι τελειωμένη) το Σάββατο': [_strength('s1', DateTime(2026, 11, 14, 19), 'B', finished: false)],
    'περπάτημα κάθε μέρα': [for (var i = 0; i < 14; i++) _walk('w$i', DateTime(2026, 11, 13 + i, 8))],
    'η Β της Δευτέρας έγινε την Τρίτη': [_strength('s1', DateTime(2026, 11, 17, 19), 'B')],
  };
  out['missedToCatchUp'] = <String, Object?>{
    for (final e in sessionsSets.entries)
      e.key: [
        for (var i = -1; i < 13; i++)
          () {
            final now = DateTime(2026, 11, 13 + i, 21, 30);
            final m = missedToCatchUp(p, e.value, now);
            return '${g141Day(now).substring(5)}:${m == null ? '-' : '${m.workout.id}@${g141Day(m.missed).substring(5)}'}';
          }(),
      ].join(' '),
  };

  // Καταγραφή μιας άσκησης: τι μετρά.
  SetLog st(double? l, int r, {bool done = true, int? at}) => SetLog(load: l, reps: r, done: done, at: at);
  ExLog ex(String id, List<SetLog> log, {int sets = 3, int? planned, int? ra}) =>
      ExLog(ex: id, sets: sets, lo: 8, hi: 12, rir: 2, rest: 90, log: log, plannedSets: planned, rirAnswer: ra);
  final logs = <String, ExLog>{
    'άδεια': ex('db_press', []),
    'τρία σετ': ex('db_press', [st(9.3, 12), st(9.3, 11), st(9.3, 10)]),
    'δύο έγιναν, ένα όχι': ex('db_press', [st(9.3, 12), st(9.3, 11), st(9.3, 10, done: false)]),
    'ένα παραπάνω που δεν έγινε': ex('db_press', [st(9.3, 12), st(9.3, 11), st(9.3, 10), st(9.3, 10, done: false)]),
    'ένα παραπάνω που έγινε': ex('db_press', [st(9.3, 12), st(9.3, 11), st(9.3, 10), st(6.8, 12)]),
    'ανέβηκε στη μέση': ex('db_press', [st(9.3, 12), st(11.8, 9), st(11.8, 8)]),
    'σετ με 0 επαναλήψεις': ex('db_press', [st(9.3, 12), st(9.3, 0), st(9.3, 10)]),
    'προγραμματισμένα 4': ex('db_press', [st(9.3, 12), st(9.3, 11), st(9.3, 10), st(9.3, 9), st(9.3, 8)], planned: 4),
    'κωπηλατική ανά πλευρά': ex('db_row', [st(14.3, 10), st(14.3, 10)]),
    'μπάρα': ex('rdl', [st(20, 10), st(22.5, 8), st(null, 8)]),
    'λάστιχο': ex('band_pushdown', [st(30, 14), st(40, 12)]),
    'βοήθεια (λιγότερη = πιο βαρύ)': ex('assisted_pullup', [st(50, 6), st(30, 5), st(40, 5)]),
    'σώμα': ex('reverse_crunch', [st(null, 12), st(null, 11)]),
    'δίσκος': ex('crunch', [st(0, 15), st(5, 12), st(7.5, 10)]),
    'ένα σετ από ένα': ex('db_press', [st(9.3, 12)], sets: 1),
  };
  out['ExLog'] = <String, Object?>{
    for (final e in logs.entries) e.key: _exView(e.value),
    'json round trip': ExLog.fromJson(<String, dynamic>{
      ...ex('db_press', [st(9.3, 12, at: 1000), st(9.3, 11, done: false)], planned: 4, ra: 3).toJson(),
      'pain': ['elbow', 5],
      'skip': 1,
      'from': 'db_fly',
      'why': 'δεν είχα',
      'fa': 2,
      'μελλοντικό': {'x': 1},
    }).toJson(),
    'fromJson minimal': ExLog.fromJson(<String, dynamic>{'ex': 'db_press', 'sets': 3.0, 'lo': 8, 'hi': 12, 'log': [{'r': '5', 'l': 'x', 'd': true, 'q': 7}]}).toJson(),
    'unknownKeys': unknownKeys(<String, dynamic>{'a': 1, 'b': 2, 'c': 3}, const {'a', 'c'}),
  };

  // Προπόνηση: παλμοί, σταθερό μέρος, τελευταία κίνηση, αποθήκευση.
  final start = DateTime(2026, 11, 23, 19);
  final full = _strength('s9', start, 'A', items: [
    ExLog(ex: 'db_press', sets: 3, lo: 8, hi: 12, rir: 2, rest: 120, rirAnswer: 2, log: [
      for (final (i, r) in [(0, 12), (1, 11), (2, 10)]) SetLog(load: 9.3, reps: r, done: true, at: start.millisecondsSinceEpoch + (120 + i * 180) * 1000),
    ]),
    ExLog(ex: 'db_row', sets: 2, lo: 8, hi: 12, rir: 2, rest: 90, log: [
      SetLog(load: 14.3, reps: 10, done: true, at: start.millisecondsSinceEpoch + 780 * 1000),
      SetLog(load: 14.3, reps: 10),
    ]),
    ExLog(ex: 'reverse_crunch', sets: 2, lo: 10, hi: 15, rir: 2, rest: 60, log: [SetLog(reps: 12, done: true)]),
  ])
    ..hr.addAll([for (var t = 0; t < 1500; t += 5) [t, 95 + (t % 180 < 40 ? 25 : 0) + (t ~/ 300)]])
    ..hrAvg = 104
    ..hrMax = 126
    ..feel = 4
    ..limit = 140;
  final walk = _walk('w9', DateTime(2026, 11, 24, 8), hrrEnd: 118, hrr1: 96, zone: [300, 1200, 250], pauses: [[600, 660], [1200, 1205]], splits: [[780, 790], [1560, 1640]]);
  out['Session'] = <String, Object?>{
    'strength': <String, Object?>{
      'isCardio|isFree|finished': '${full.isCardio}|${full.isFree}|${full.finished}',
      'setsDone': full.setsDone,
      'volume': full.volume,
      'duration': full.duration,
      'lastTick': full.lastTick,
      'lastActivity': full.lastActivity,
      'lastActivity resumed': (() {
        final s = _strength('r', start, 'A')..resumedAt = start.millisecondsSinceEpoch + 4000000;
        return s.lastActivity;
      })(),
      'limitUsed': [full.limitUsed, _strength('l0', start, 'A').limitUsed, (_strength('l1', start, 'A')..limit = 0).limitUsed],
      'steadyHr': full.steadyHr,
      'hasHr': full.hasHr,
      'hrUpTo 10′': () {
        final h = full.hrUpTo(start.add(const Duration(minutes: 10)));
        return '${h.hr.length}|${h.avg}|${h.max}';
      }(),
      'hrUpTo end': () {
        final h = full.hrUpTo(start.add(const Duration(minutes: 50)));
        return '${h.hr.length}|${h.avg}|${h.max}';
      }(),
      'hrUpTo before start': () {
        final h = full.hrUpTo(start.subtract(const Duration(minutes: 5)));
        return '${h.hr.length}|${h.avg}|${h.max}';
      }(),
      'json keys': (full.toJson(hrInline: false).keys.toList()..sort()),
      'json round trip': () {
        final j = Session.fromJson(Map<String, dynamic>.from(full.toJson())).toJson();
        return <String, Object?>{...j, 'hr': '${(j['hr'] as List?)?.length} δείγματα'};
      }(),
      'free': _strength('f', start, freeWorkoutId).isFree,
    },
    'walk': <String, Object?>{
      'isCardio': walk.isCardio,
      'moderateMinutes': walk.moderateMinutes,
      'steadyHr': walk.steadyHr,
      'json round trip': () {
        final j = Session.fromJson(Map<String, dynamic>.from(walk.toJson())).toJson();
        return <String, Object?>{...j, 'hr': '${(j['hr'] as List?)?.length} δείγματα'};
      }(),
    },
    'steadyFrom': <String, Object?>{
      'empty': Session.steadyFrom(const [], const []),
      '29 samples after 5′': Session.steadyFrom([for (var i = 0; i < 29; i++) [300 + i * 10, 110]], const []),
      '30 samples after 5′': Session.steadyFrom([for (var i = 0; i < 30; i++) [300 + i * 10, 110 + i % 2]], const []),
      'sample at 299 not counted': Session.steadyFrom([[299, 200], for (var i = 0; i < 30; i++) [300 + i * 10, 100]], const []),
      'with a pause in the warm-up': Session.steadyFrom([for (var i = 0; i < 100; i++) [i * 10, 90 + i ~/ 10]], const [[100, 200]]),
      'samples inside a pause': Session.steadyFrom([for (var i = 0; i < 100; i++) [i * 10, i >= 50 && i < 60 ? 60 : 110]], const [[500, 600]]),
    },
    'inPause': [for (final t in [599, 600, 659, 660]) Session.inPause(const [[600, 660]], t)],
    'pairs': Session.pairs([[1, 2], [3], 'x', [4.9, 5.1], [6, 'y']]),
    'watchLimit': [for (final v in <Object?>[null, -1, 0, 140, 140.9, '140']) Session.watchLimit(v)],
    'fromJson minimal': () {
      final s = Session.fromJson(<String, dynamic>{'id': 'm', 'start': 1795000000000, 'note': 'Σταμάτησε: πόνος', 'km': 'x', 'zt': [1, 2, 3, 4], 'lim': -5, 'κάτι': 1});
      return <String, Object?>{'stopped': s.stopped, 'zoneTimes': s.zoneTimes, 'limit': s.limit, 'extra': s.extra, 'workout': s.workout};
    }(),
  };
  return out;
}

// ----------------------------------------------------------------- ζώνη παλμών, παλμοί ανά σετ, περπάτημα, πρόοδος

Map<String, Object?> _trend(TrendResult r) => <String, Object?>{
      'key': r.def.key,
      'status': r.status.name,
      'current': r.current,
      'previous': r.previous,
      'nCurrent': r.nCurrent,
      'nPrevious': r.nPrevious,
      'changed': r.changed,
    };

String? _zone(Zone? z) => z == null ? null : '${z.lo}–${z.hi} · ηρεμίας ${z.rest} · μέγιστοι ${z.max} · maxMeasured ${z.maxMeasured} · restMeasured ${z.restMeasured} · manual ${z.manual}';

Map<String, Object?> _cardioGolden() {
  final out = <String, Object?>{};
  out['constants'] = <String, Object?>{
    'zoneLoPct': zoneLoPct,
    'zoneHiPct': zoneHiPct,
    'zoneLoMaxPct': zoneLoMaxPct,
    'zoneHiMaxPct': zoneHiMaxPct,
    'zoneWarmupSec': zoneWarmupSec,
    'zoneHoldSec': zoneHoldSec,
    'zoneRepeatSec': zoneRepeatSec,
    'zoneGapSec': zoneGapSec,
    'zoneBackSec': zoneBackSec,
    'talkAskWalks': talkAskWalks,
    'zoneRestMin': zoneRestMin,
    'zoneRestMax': zoneRestMax,
    'setWindow': setWindow,
    'restWindow': restWindow,
    'minRest': minRest,
    'minSamples': minSamples,
    'defaultRepSec': defaultRepSec,
    'minSetSec': minSetSec,
    'maxSetSec': maxSetSec,
    'perSideExercises': (perSideExercises.toList()..sort()),
    'sideSwitchSec': sideSwitchSec,
    'walkMinSec': walkMinSec,
    'walkNeeded': walkNeeded,
    'paceTolerance': paceTolerance,
    'repsTolerance': repsTolerance,
  };

  // Ζώνη παλμών.
  out['tanakaMax'] = [for (var age = 18; age <= 90; age++) tanakaMax(age)].join(' ');
  final zones = <String, Object?>{};
  for (final age in <int?>[null, 25, 47, 70]) {
    for (final rest in <double?>[null, 29.9, 30, 54.6, 70, 120]) {
      zones['ηλικία $age · ηρεμίας $rest'] = _zone(computeZone(age: age, restHr: rest, s: const ZoneSettings()));
    }
  }
  // 47 ετών: μέγιστοι 175 → παλμοί ηρεμίας 154 και 155 (όριο «μέγιστοι − 20»).
  for (final rest in [154.0, 154.4, 154.5, 155.0, 156.0]) {
    zones['ηλικία 47 · ηρεμίας $rest (όριο)'] = _zone(computeZone(age: 47, restHr: rest, s: const ZoneSettings()));
  }
  zones['μετρημένοι μέγιστοι 158'] = _zone(computeZone(age: 47, restHr: 60, s: const ZoneSettings(maxHr: 158)));
  zones['μετρημένοι μέγιστοι, χωρίς ηλικία'] = _zone(computeZone(restHr: 60, s: const ZoneSettings(maxHr: 180)));
  zones['δικοί του παλμοί ηρεμίας 58'] = _zone(computeZone(age: 47, restHr: 70, s: const ZoneSettings(restHr: 58)));
  zones['χειροκίνητη 100–125'] = _zone(computeZone(age: 47, restHr: 60.4, s: const ZoneSettings(lo: 100, hi: 125)));
  zones['χειροκίνητη, χωρίς ηλικία'] = _zone(computeZone(s: const ZoneSettings(lo: 100, hi: 125)));
  zones['μόνο κάτω όριο (όχι χειροκίνητη)'] = _zone(computeZone(age: 47, s: const ZoneSettings(lo: 100)));
  out['computeZone'] = zones;
  out['ZoneSettings.fromJson'] = <String, Object?>{
    for (final e in <String, Object?>{
      'not a map': 5,
      'empty': <String, Object?>{},
      'full': {'lo': 100, 'hi': 125, 'max': 172, 'rest': 58, 'up': false, 'down': true, 'talk': [['2026-11-24', 'ok'], ['x'], [1, 2], 'y']},
      'lo >= hi': {'lo': 125, 'hi': 125},
      'bounds low': {'lo': 49, 'hi': 221, 'max': 99, 'rest': 29},
      'bounds ok low': {'lo': 50, 'hi': 51, 'max': 100, 'rest': 30},
      'bounds ok high': {'lo': 219, 'hi': 220, 'max': 230, 'rest': 120},
      'bounds high': {'lo': 100, 'hi': 221, 'max': 231, 'rest': 121},
    }.entries)
      e.key: () {
        final z = ZoneSettings.fromJson(e.value);
        return <String, Object?>{'json': z.toJson(), 'manual': z.manual};
      }(),
    'copyWith clear': const ZoneSettings(lo: 100, hi: 125, maxHr: 172, restHr: 58).copyWith(clearManual: true, clearMax: true, clearRest: true, alertLow: true).toJson(),
    'copyWith set': const ZoneSettings().copyWith(lo: 95, hi: 120, maxHr: 170, restHr: 60, alertHigh: false, talk: const [['a', 'b']]).toJson(),
  };
  out['WalkZone.fromJson'] = <String, Object?>{
    for (final e in <String, Object?>{
      'ok': {'lo': 100, 'hi': 125, 'up': false, 'down': true},
      'defaults': {'lo': 100.9, 'hi': 125.2},
      'lo 49': {'lo': 49, 'hi': 125},
      'hi 221': {'lo': 100, 'hi': 221},
      'lo = hi': {'lo': 100, 'hi': 100},
      'text': {'lo': '100', 'hi': 125},
      'not a map': null,
    }.entries)
      e.key: WalkZone.fromJson(e.value)?.toJson(),
    'equality': [const WalkZone(100, 125) == const WalkZone(100, 125, up: true), const WalkZone(100, 125) == const WalkZone(100, 125, down: true)],
  };
  out['talkShift'] = <String, Object?>{for (final a in ['sing', 'no', 'ok', '']) a: talkShift(a)};
  String zt(List<List<int>> samples, List<List<int>> pauses, {int maxGap = 15, int? endSec}) {
    final z = zoneTimes(samples, pauses, 100, 125, maxGap: maxGap, endSec: endSec);
    return '${z.below}|${z.inZone}|${z.above}|${z.measured}';
  }

  final ramp = [for (var t = 0; t < 600; t += 10) [t, 90 + t ~/ 12]];
  out['zoneTimes (below|in|above|measured)'] = <String, Object?>{
    'empty': zt(const [], const []),
    'ramp 90→139': zt(ramp, const []),
    'ramp, end at 300': zt(ramp, const [], endSec: 300),
    'ramp, end at 305': zt(ramp, const [], endSec: 305),
    'ramp, pause 100–200': zt(ramp, const [[100, 200]]),
    'edges 99/100/125/126': zt(const [[0, 99], [1, 100], [2, 125], [3, 126]], const []),
    'gap of 60 s counts 15': zt(const [[0, 110], [60, 110]], const []),
    'gap of 60 s, maxGap 30': zt(const [[0, 110], [60, 110]], const [], maxGap: 30),
    'last sample with endSec': zt(const [[0, 110], [10, 130]], const [], endSec: 40),
    'zero bpm ignored': zt(const [[0, 0], [10, 110], [20, -5]], const []),
  };
  out['weekMovement'] = <String, Object?>{
    for (final (name, now) in [('Δευτέρα 23/11', DateTime(2026, 11, 23, 9)), ('Κυριακή 29/11', DateTime(2026, 11, 29, 23)), ('Δευτέρα 30/11', DateTime(2026, 11, 30)), ('Κυριακή 28/3/2027', DateTime(2027, 3, 28, 12))])
      name: () {
        final m = weekMovement([
          _walk('a', DateTime(2026, 11, 23, 8), zone: [100, 1200, 300]),
          _walk('b', DateTime(2026, 11, 25, 8), zone: [0, 29, 0]),
          _walk('c', DateTime(2026, 11, 26, 8)),
          _walk('d', DateTime(2026, 11, 27, 8), activity: 'bike', zone: [0, 3000, 0]),
          _walk('e', DateTime(2026, 11, 29, 23, 59), zone: [0, 600, 0], finished: false),
          _walk('f', DateTime(2026, 11, 30, 0, 0), zone: [0, 900, 0]),
          _walk('g', DateTime(2027, 3, 22, 0, 0), zone: [0, 1500, 0]),
          _walk('h', DateTime(2027, 3, 28, 23, 0), zone: [0, 0, 600]),
          _strength('s1', DateTime(2026, 11, 23, 19), 'A'),
          _strength('s2', DateTime(2026, 11, 23, 21), 'B'),
          _strength('s3', DateTime(2026, 11, 27, 19), 'A', stopped: true),
          _strength('s4', DateTime(2026, 11, 28, 19), 'B', items: const []),
          _strength('s5', DateTime(2026, 11, 29, 19), 'A'),
        ], now);
        return '${m.moderateMin}|${m.strengthDays}|${m.unmeasuredWalks}';
      }(),
  };

  // Παλμοί ανά σετ.
  out['setSeconds'] = <String, Object?>{
    for (final reps in [0, 1, 4, 5, 8, 12, 26, 27, 50]) '$reps': '${setSeconds(reps)}|${setSeconds(reps, 2.5)}|${setSeconds(reps, 0)}|${setSecondsOf('db_row', reps)}|${setSecondsOf('db_press', reps, 3)}',
  };
  final hr = [for (var t = 0; t < 600; t += 1) [t, 90 + (t % 120 < 40 ? 30 : 0) + t ~/ 100]];
  out['meanIn/restIn'] = <String, Object?>{
    'meanIn 0–30': meanIn(hr, 0, 30),
    'meanIn 30–60': meanIn(hr, 30, 60),
    'meanIn 599–700 (1 δείγμα)': meanIn(hr, 599, 700),
    'meanIn 597–700 (3 δείγματα)': meanIn(hr, 597, 700),
    'meanIn half seconds': meanIn(hr, 10.5, 13.5),
    'restIn 14 s': restIn(hr, 100, 114),
    'restIn 15 s': restIn(hr, 100, 115),
    'restIn 90 s': restIn(hr, 40, 130),
    'empty': meanIn(const [], 0, 100),
  };
  final t0 = DateTime(2026, 11, 23, 19);
  final strength = Session(id: 'h', workout: 'A', name: 'Α', programId: 'p1', start: t0, end: t0.add(const Duration(minutes: 20)), hr: hr, items: [
    ExLog(ex: 'db_press', sets: 3, lo: 8, hi: 12, rir: 2, rest: 90, log: [
      for (final t in [60, 180, 300]) SetLog(load: 9.3, reps: 8, done: true, at: t0.millisecondsSinceEpoch + t * 1000),
    ]),
    ExLog(ex: 'db_row', sets: 2, lo: 8, hi: 12, rir: 2, rest: 90, log: [
      SetLog(load: 14.3, reps: 10, done: true, at: t0.millisecondsSinceEpoch + 420 * 1000),
      SetLog(load: 14.3, reps: 10, done: true, at: t0.millisecondsSinceEpoch + 425 * 1000),
      SetLog(load: 14.3, reps: 10),
      SetLog(load: 14.3, reps: 10, done: true),
    ]),
  ]);
  String setHr(List<ExHr> r) => [for (final e in r) '${e.avg}: ${[for (final x in e.sets) x == null ? '-' : '${x.set}/${x.rest}'].join(' ')}'].join(' ## ');
  out['sessionSetHr'] = <String, Object?>{
    'default': setHr(sessionSetHr(strength)),
    'slow reps (8 s)': setHr(sessionSetHr(strength, repSeconds: (ex) => 8.0)),
    'own seconds only for db_row': setHr(sessionSetHr(strength, repSeconds: (ex) => ex == 'db_row' ? 2.0 : 0.0)),
    'no hr': sessionSetHr(Session(id: 'n', workout: 'A', name: 'Α', programId: 'p1', start: t0)).length,
  };
  out['hrQuality'] = <String, Object?>{
    for (final d in <String?>[null, '', 'q=100/0/0', 'q=1234/56/7', 'v=3 q=10/2/1 x', 'q=0/0/0', 'q=0/0/5', 'xq=1/2/3', 'q=1/2', 'q=1/2/3/4', 'q=1234567890/1/1', 'q=1/2/3 ${'x' * 40}'])
      '$d': () {
        final q = hrQualityFromDiag(d);
        return q == null ? null : '${q.ok}|${q.low}|${q.bad}|${q.total} · ${hrQualityText(q)}';
      }(),
    'only low': hrQualityText(const HrQualityCounts(1500, 20, 0)),
    'only bad': hrQualityText(const HrQualityCounts(999, 0, 1)),
  };

  // Περπάτημα: απόσταση, ρυθμός, βήματα.
  out['pickMeters'] = <String, Object?>{
    for (final gps in <bool?>[true, false, null])
      for (final (m, est) in [(0.0, 0.0), (9.9, 0.0), (10.0, 0.0), (0.0, 9.9), (0.0, 10.0), (2300.0, 2400.0), (1919.0, 2400.0), (1920.0, 2400.0), (1921.0, 2400.0), (9.0, 2400.0), (2300.0, 9.0)])
        '$gps|$m|$est': () {
          final p = pickMeters(m, est, gps);
          return p == null ? null : '${p.meters}${p.approx ? ' ≈' : ''}';
        }(),
  };
  final walks = <String, Session>{
    'gps 2,3 km σε 30′': _walk('a', DateTime(2026, 11, 24, 8), splits: [[780, 790], [1560, 1640]], pauses: [[600, 660]]),
    'gps 2,04 km (υπόλοιπο 40 m)': _walk('b', DateTime(2026, 11, 24, 8), meters: 2040, splits: [[880, 880], [1760, 1760]]),
    'gps 2,05 km (υπόλοιπο 50 m)': _walk('c', DateTime(2026, 11, 24, 8), meters: 2050, splits: [[880, 880], [1760, 1760]]),
    'χωρίς gps, από βήματα': _walk('d', DateTime(2026, 11, 24, 8), gps: false, meters: 0, metersEst: 2250),
    'gps αλλά η εκτίμηση νικά': _walk('e', DateTime(2026, 11, 24, 8), meters: 1500, metersEst: 2400, splits: [[900, 900]]),
    'σύντομο 59″': _walk('f', DateTime(2026, 11, 24, 8), sec: 59, meters: 80, steps: 100),
    'χωρίς απόσταση': _walk('g', DateTime(2026, 11, 24, 8), meters: null, steps: null, gps: null),
    'ποδήλατο': _walk('h', DateTime(2026, 11, 24, 8), activity: 'bike', meters: 9000, steps: 0),
    'μισό (όχι τελειωμένο)': _walk('i', DateTime(2026, 11, 24, 8), finished: false, splits: [[780, 790]]),
    '14′59″': _walk('j', DateTime(2026, 11, 24, 8), sec: 899, meters: 1100),
    '15′ 499 m': _walk('k', DateTime(2026, 11, 24, 8), sec: 900, meters: 499),
    '15′ 500 m': _walk('l', DateTime(2026, 11, 24, 8), sec: 900, meters: 500),
    'σταμάτησε': _walk('m', DateTime(2026, 11, 24, 8), stopped: true),
    'χωρίς δείγματα παλμών': _walk('n', DateTime(2026, 11, 24, 8), samples: false),
  };
  out['walks'] = <String, Object?>{
    for (final e in walks.entries)
      e.key: g141Compact(<String, Object?>{
        'shown': () {
          final p = shownMeters(e.value);
          return p == null ? null : '${p.meters}${p.approx ? ' ≈' : ''}';
        }(),
        'kmValue': kmValue(e.value),
        'pace': paceSecPerKm(e.value),
        'cadence': cadence(e.value),
        'fromSteps': distanceFromSteps(e.value),
        'pausedSec': pausedSec(e.value),
        'activeHr': activeHr(e.value).length,
        'splits': [for (final k in walkSplits(e.value)) '${k.label}: ${k.sec}″ ♥${k.hr}${k.partial ? ' (μέρος)' : ''}'],
        'countsAsWalk': countsAsWalk(e.value),
        'walkHr': walkHr(e.value),
      }),
  };
  out['kmText'] = <String, Object?>{for (final m in [0.0, 4.9, 5.0, 999.0, 1004.9, 1005.0, 12345.6]) '$m': kmText(m)};
  out['liveMeters'] = <String, Object?>{
    for (final e in <String, Map<String, dynamic>>{
      'empty': {},
      'gps': {'m': 1200, 'mest': 1250.5, 'gps': true},
      'no gps': {'m': 0, 'mest': 800, 'gps': false},
      'gps as text': {'m': 1200, 'mest': 2000, 'gps': 'true'},
    }.entries)
      e.key: () {
        final p = liveMeters(e.value);
        return p == null ? null : '${p.meters}${p.approx ? ' ≈' : ''}';
      }(),
  };
  final strideSessions = [
    _walk('s1', DateTime(2026, 11, 10, 8), meters: 2000, steps: 2700),
    _walk('s2', DateTime(2026, 11, 11, 8), meters: 400, steps: 2700),
    _walk('s3', DateTime(2026, 11, 12, 8), meters: 3000, steps: 2000),
    _walk('s4', DateTime(2026, 11, 13, 8), meters: 2400, steps: 3100, gps: false),
    _walk('s5', DateTime(2026, 11, 14, 8), meters: 2200, steps: 3000, activity: 'bike'),
    for (var i = 0; i < 6; i++) _walk('t$i', DateTime(2026, 11, 15 + i, 8), meters: 2300.0 + i * 50, steps: 3100 + i * 30),
  ];
  out['strideFor'] = <String, Object?>{
    'from walks': strideFor(strideSessions),
    'only the first five': strideFor(strideSessions.sublist(0, 5)),
    for (final h in <double?>[null, 119, 120, 180, 230, 231])
      for (final sex in <String?>['m', 'f', null]) 'no walks · $h · $sex': strideFor(const [], heightCm: h, sex: sex),
  };

  // Πρόοδος στο περπάτημα: 30 και 90 μέρες.
  final today = DateTime(2026, 12, 20, 11);
  Session w(int daysAgo, int bpm, {int sec = 1800, double meters = 2300, int? end, int? drop, int hour = 8}) => _walk('p$daysAgo-$hour', DateTime(today.year, today.month, today.day - daysAgo, hour),
      sec: sec, meters: meters, hr: bpm, hrrEnd: end, hrr1: end == null || drop == null ? null : end - drop);
  const noise = [2, -2, 1, -1, 0, 2];
  final sets = <String, List<Session>>{
    'καθόλου': const [],
    'τρία περπατήματα τώρα': [for (var i = 0; i < 3; i++) w(2 + i * 4, 112)],
    'τέσσερα τώρα, κανένα πριν': [for (var i = 0; i < 4; i++) w(2 + i * 4, 112 + noise[i])],
    'παλμοί κάτω, ίδιος ρυθμός': [
      for (var i = 0; i < 6; i++) w(32 + i * 5, 120 + noise[i], end: 124, drop: 16 + noise[i]),
      for (var i = 0; i < 6; i++) w(1 + i * 5, 112 + noise[(i + 3) % 6], end: 116, drop: 24 + noise[(i + 3) % 6]),
    ],
    'παλμοί κάτω, πιο αργά': [
      for (var i = 0; i < 6; i++) w(32 + i * 5, 120 + noise[i], meters: 2500),
      for (var i = 0; i < 6; i++) w(1 + i * 5, 112 + noise[(i + 3) % 6], meters: 2200),
    ],
    'παλμοί πάνω, πιο γρήγορα': [
      for (var i = 0; i < 6; i++) w(32 + i * 5, 110 + noise[i], meters: 2200),
      for (var i = 0; i < 6; i++) w(1 + i * 5, 119 + noise[(i + 3) % 6], meters: 2500),
    ],
    'ίδια': [
      for (var i = 0; i < 6; i++) w(32 + i * 5, 112 + noise[i]),
      for (var i = 0; i < 6; i++) w(1 + i * 5, 112 + noise[(i + 3) % 6]),
    ],
    'δύο την ίδια μέρα και ένα που δεν μετρά': [
      for (var i = 0; i < 5; i++) w(33 + i * 5, 118),
      for (var i = 0; i < 4; i++) w(2 + i * 6, 113),
      w(2, 121, hour: 19),
      w(3, 150, sec: 600),
    ],
    'τρίμηνο': [
      for (var i = 0; i < 12; i++) w(95 + i * 7, 121 + noise[i % 6]),
      for (var i = 0; i < 12; i++) w(3 + i * 7, 113 + noise[i % 6]),
    ],
  };
  out['progressWindows'] = <String, Object?>{
    for (final p in TrendPeriod.values)
      for (final d in [today, DateTime(2027, 3, 30), DateTime(2026, 10, 26), DateTime(2028, 3, 1)])
        '${p.name} ${g141Day(d)}': () {
          final x = progressWindows(d, p);
          return '${g141Day(x.prevFrom)}..${g141Day(x.prevEnd)} | ${g141Day(x.from)}..${g141Day(x.end)}';
        }(),
  };
  out['walkProgress'] = <String, Object?>{
    for (final e in sets.entries)
      for (final p in [TrendPeriod.month, TrendPeriod.quarter])
        '${e.key} · ${p.name}': g141Safe(() {
          final r = walkProgress(e.value, today, p);
          return <String, Object?>{
            'hr': _trend(r.hr),
            'pace': _trend(r.pace),
            'hrr': _trend(r.hrr),
            'hrrEnd': _trend(r.hrrEnd),
            'count': '${r.countNow}|${r.countBefore}|${r.secNow}',
            'paceRel': r.paceRel.name,
            'hrGoodness': r.hrGoodness,
            'insufficient': r.insufficient,
          };
        }),
  };
  out['walkHistory'] = walkHistory(sets['δύο την ίδια μέρα και ένα που δεν μετρά']!);
  out['walkHrPoints'] = [
    for (final p in walkHrPoints(sets['δύο την ίδια μέρα και ένα που δεν μετρά']!, DateTime(2026, 11, 21), DateTime(2026, 12, 18))) '${g141Day(p.$1)}=${p.$2}',
  ];

  // Πρόοδος στα βάρη: τελευταία φορά της περιόδου απέναντι στην προηγούμενη.
  Session lift(int daysAgo, Map<String, (double?, List<int>)> items, {bool stopped = false, bool skip = false}) => _strength(
        'l$daysAgo',
        DateTime(today.year, today.month, today.day - daysAgo, 19),
        'A',
        stopped: stopped,
        items: [
          for (final e in items.entries)
            ExLog(ex: e.key, sets: 3, lo: 8, hi: 12, rir: 2, rest: 90, skipped: skip, log: [for (final r in e.value.$2) SetLog(load: e.value.$1, reps: r, done: true)]),
        ],
      );
  final lifts = [
    lift(40, {'db_press': (9.3, [10, 10, 9]), 'db_row': (14.3, [10, 10, 10]), 'goblet': (12, [12, 12, 12]), 'reverse_crunch': (null, [10, 10, 9]), 'assisted_pullup': (50, [6, 6, 5]), 'rdl': (20, [12, 12, 12]), 'band_pushdown': (30, [12, 12, 12]), 'lateral_raise': (4.3, [12, 12, 12])}),
    lift(20, {'db_press': (9.3, [12, 12, 11]), 'db_row': (16.8, [8, 8, 7]), 'goblet': (10, [12, 12, 12]), 'reverse_crunch': (null, [12, 12, 12]), 'assisted_pullup': (40, [6, 5, 5]), 'rdl': (22.5, [9, 8, 8]), 'band_pushdown': (30, [12, 11, 12]), 'incline_curl': (5.3, [10, 10, 10])}),
    lift(6, {'db_press': (11.8, [8, 8, 8]), 'db_row': (16.8, [10, 9, 9]), 'goblet': (10, [15, 15, 14]), 'reverse_crunch': (null, [9, 9, 8]), 'assisted_pullup': (30, [5, 5, 4]), 'rdl': (25, [6, 5, 5]), 'band_pushdown': (30, [12, 12, 13]), 'hammer_curl': (6.8, [10, 10, 10])}),
    lift(4, {'db_press': (11.8, [9, 9, 8])}, stopped: true),
    lift(3, {'lateral_raise': (4.3, [15, 15, 15])}, skip: true),
    lift(2, {'hammer_curl': (6.8, [12, 11, 11])}),
  ];
  String exp(List<ExProgress> list) => [
        for (final x in list)
          '${x.ex}(${x.kind.name}) ${g141Day(x.beforeDay).substring(5)}→${g141Day(x.nowDay).substring(5)} ${x.repsBefore.join(',')}→${x.repsNow.join(',')} '
              'Δεπαν ${x.repsDiff} Δφορτίο ${x.loadDiff} στοΕύρος ${x.repsInRange} ${x.change.name}',
      ].join(' ## ');
  out['strengthProgress'] = <String, Object?>{
    for (final p in TrendPeriod.values) p.name: g141Safe(() => exp(strengthProgress(lifts, today, p))),
    'δέκα μέρες αργότερα': exp(strengthProgress(lifts, DateTime(2026, 12, 30), TrendPeriod.month)),
    'κενό': exp(strengthProgress(const [], today, TrendPeriod.month)),
  };
  return out;
}

void main() {
  tearDown(() => equip = Equipment.standard);
  test('golden141 · επόμενος στόχος και ρύθμιση βάρους', () => runGolden('training_progression', _progressionGolden));
  test('golden141 · εξοπλισμός, φορτία, προετοιμασία', () => runGolden('training_equipment', _equipmentGolden));
  test('golden141 · πρόγραμμα, χαμένη προπόνηση, καταγραφή', () => runGolden('training_program', _programGolden));
  test('golden141 · ζώνη παλμών, παλμοί ανά σετ, περπάτημα, πρόοδος', () => runGolden('training_cardio', _cardioGolden));
}
