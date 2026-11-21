// golden141 · ΕΝΕΡΓΕΙΑ (έλεγχος 20/11/2026): στιγμιότυπο των υπολογισμών του σημερινού κώδικα για στόχους (goals.dart),
// εκτίμηση και εβδομαδιαίο έλεγχο θερμίδων (adaptive.dart, adaptive_check.dart), φύλακα ζυγίσεων (weight_guard.dart),
// τάση σώματος (body_trend.dart), μέση (waist.dart) και προφίλ (profile.dart). Μόνο επινοημένα δεδομένα, σταθερές
// ημερομηνίες, καμία ώρα συστήματος. Δες golden141_common.dart για το πώς διαβάζεται μια διαφορά.
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/adaptive.dart';
import 'package:ygeia_forma/adaptive_check.dart';
import 'package:ygeia_forma/body_trend.dart';
import 'package:ygeia_forma/data.dart' show BodyMeasurement;
import 'package:ygeia_forma/goals.dart';
import 'package:ygeia_forma/profile.dart';
import 'package:ygeia_forma/waist.dart';
import 'package:ygeia_forma/weight_guard.dart';

import 'golden141_common.dart';
import 'sample_checkin.dart' show checkinFood;

const _inbody = 'com.inbody2014.inbody';

String _f2(double? v) => v == null ? '-' : v.toStringAsFixed(2);
String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
String? _dayOrNull(DateTime? d) => d == null ? null : g141Day(d);

// ------------------------------------------------------------------------------------------------------------ στόχοι

Map<String, Object?> _calcJson(GoalCalc c) => <String, Object?>{
      'kg': c.kg,
      'bmr': c.bmr,
      'tdee': c.tdee,
      'delta': c.delta,
      'kcal': c.kcal,
      'floored': c.floored,
      'protein': c.protein,
      'fatLo': c.fatLo,
      'fatHi': c.fatHi,
      'satMax': c.satMax,
      'satPct': c.satPct,
      'fiber': c.fiber,
      'salt': c.salt,
      'carbsEst': c.carbsEst,
    };

/// Επινοημένοι στόχοι: άνδρας 40 ετών, 180 cm, 90 kg, −0,5% την εβδομάδα, από Δευτέρα 23/11/2026.
Goals _base({
  GoalAim aim = GoalAim.lose,
  double rate = 0.005,
  double activity = 1.53,
  bool doctor = true,
  String since = '2026-11-23',
  double kg = 90,
  int age = 40,
  double heightCm = 180,
  bool male = true,
  int? kcalSet,
  int? proteinSet,
  int? kcalAdapt,
  double? tdeeEst,
  String? checkIn,
  String? fastAt,
  String? foreignSeen,
  List<AdaptLog> log = const [],
  DoctorTargets docTargets = const DoctorTargets(),
  List<TargetChange> hist = const [],
}) =>
    Goals(
      aim: aim,
      rate: rate,
      activity: activity,
      doctor: doctor,
      since: since,
      kg: kg,
      age: age,
      heightCm: heightCm,
      male: male,
      kcalSet: kcalSet,
      proteinSet: proteinSet,
      kcalAdapt: kcalAdapt,
      tdeeEst: tdeeEst,
      checkIn: checkIn,
      fastAt: fastAt,
      foreignSeen: foreignSeen,
      log: log,
      docTargets: docTargets,
      hist: hist,
    );

List<(GoalAim, double)> _aims() => [
      for (final r in loseRates) (GoalAim.lose, r),
      (GoalAim.keep, 0.0),
      for (final r in gainRates) (GoalAim.gain, r),
    ];

Map<String, Object?> _goalsView(Goals g) => <String, Object?>{
      'kcal': g.kcal,
      'protein': g.protein,
      'fatLo': g.fatLo,
      'fatHi': g.fatHi,
      'satMax': g.satMax,
      'satPct': g.satPct,
      'fiber': g.fiber,
      'salt': g.salt,
      'carbsEst': g.carbsEst,
      'json': g.toJson(),
    };

/// Ο οδηγός στόχων σε πλέγμα: φύλο × ηλικία × ύψος × βάρος × κίνηση × στόχος/ρυθμός × γιατρός.
Map<String, Object?> _goalsGrid() {
  final out = <String, Object?>{};
  for (final male in [true, false]) {
    for (final age in [25, 44, 70]) {
      for (final h in [160.0, 180.0, 195.0]) {
        for (final kg in [55.0, 84.0, 110.0, 140.0]) {
          for (final pal in activityLevels) {
            for (final (aim, rate) in _aims()) {
              final a = _calcJson(computeGoals(
                  male: male, age: age, heightCm: h, kg: kg, aim: aim, rate: rate, activity: pal, doctor: false));
              final b = _calcJson(computeGoals(
                  male: male, age: age, heightCm: h, kg: kg, aim: aim, rate: rate, activity: pal, doctor: true));
              // Ο γιατρός αλλάζει μόνο τα κορεσμένα: γράφονται τα δύο πεδία του «με γιατρό» και ένας έλεγχος ότι όλα
              // τα άλλα είναι ίδια (αν πάψουν να είναι, γράφεται ολόκληρο το «με γιατρό»).
              var same = true;
              for (final k in a.keys) {
                if (k != 'satMax' && k != 'satPct' && a[k] != b[k]) same = false;
              }
              out['${male ? 'm' : 'f'}|$age|${h.round()}|$kg|$pal|${aim.name}|$rate'] = <String, Object?>{
                ...a,
                'satMaxDoc': b['satMax'],
                'satPctDoc': b['satPct'],
                'docSame': same,
                if (!same) 'doc': b,
              };
            }
          }
        }
      }
    }
  }
  return out;
}

Map<String, Object?> _goalsGolden() {
  final out = <String, Object?>{};
  out['constants'] = <String, Object?>{
    'loseRates': loseRates,
    'gainRates': gainRates,
    'activityLevels': activityLevels,
    'legacyActivityLevels': legacyActivityLevels,
    'kcalPerKg': kcalPerKg,
    'kcalFloorMale': kcalFloorMale,
    'kcalFloorFemale': kcalFloorFemale,
    'proteinPerKg': proteinPerKg,
    'proteinPerKgLose': proteinPerKgLose,
    'fullDayShare': fullDayShare,
    'defaultNutsG': defaultNutsG,
    'defaultBranG': defaultBranG,
    'defaultLegumesWeek': defaultLegumesWeek,
    'defaultFishWeek': defaultFishWeek,
    'betaGlucanTarget': betaGlucanTarget,
    'adaptLogMax': adaptLogMax,
    'targetHistMax': targetHistMax,
    'ldlRange': [DoctorTargets.ldlRange.$1, DoctorTargets.ldlRange.$2],
    'hdlRange': [DoctorTargets.hdlRange.$1, DoctorTargets.hdlRange.$2],
    'tgRange': [DoctorTargets.tgRange.$1, DoctorTargets.tgRange.$2],
  };
  out['grid'] = _goalsGrid();

  // Παλιά επίπεδα κίνησης και ακραίες τιμές (ό,τι μπορεί να υπάρχει σε αποθηκευμένους στόχους).
  final legacy = <String, Object?>{};
  for (final male in [true, false]) {
    for (final pal in [1.2, ...legacyActivityLevels, 2.5]) {
      for (final (aim, rate) in _aims()) {
        legacy['${male ? 'm' : 'f'}|$pal|${aim.name}|$rate'] = _calcJson(
            computeGoals(male: male, age: 44, heightCm: 180, kg: 84.0, aim: aim, rate: rate, activity: pal, doctor: true));
      }
    }
  }
  out['legacyPal'] = legacy;

  // Γύρω από το κατώτατο (1.500 / 1.200): 70 ετών, 160 cm, γρήγορη απώλεια, βάρος 50–90 kg ανά 0,5.
  final floor = <String, Object?>{};
  for (final male in [true, false]) {
    for (var i = 0; i <= 80; i++) {
      final kg = 50 + i * 0.5;
      final c = computeGoals(
          male: male, age: 70, heightCm: 160, kg: kg, aim: GoalAim.lose, rate: 0.0075, activity: 1.53, doctor: true);
      floor['${male ? 'm' : 'f'}|$kg'] = '${c.kcal}|${c.floored}|${c.protein}|${c.satMax}|${c.carbsEst}';
    }
  }
  out['floorScan'] = floor;

  // Πρωτεΐνη γύρω από ΔΜΣ 30 (180 cm → 97,2 kg): στην απώλεια μετρά το βάρος του ΔΜΣ 30, αλλού το πραγματικό.
  final prot = <String, Object?>{};
  for (var i = 0; i <= 32; i++) {
    final kg = 93 + i * 0.25;
    final lose =
        computeGoals(male: true, age: 44, heightCm: 180, kg: kg, aim: GoalAim.lose, rate: 0.005, activity: 1.53, doctor: true);
    final keep =
        computeGoals(male: true, age: 44, heightCm: 180, kg: kg, aim: GoalAim.keep, rate: 0, activity: 1.53, doctor: true);
    prot['$kg'] = '${lose.protein}|${keep.protein}';
  }
  out['proteinScan'] = prot;

  // Το αντικείμενο Goals: δικές του θερμίδες/πρωτεΐνη, θερμίδες του ελέγχου, και ό,τι βγαίνει από αυτές.
  out['goals'] = <String, Object?>{
    'base': _goalsView(_base()),
    'kcalSet': _goalsView(_base(kcalSet: 1800)),
    'kcalAdapt': _goalsView(_base(kcalAdapt: 2150)),
    'kcalSet+Adapt': _goalsView(_base(kcalSet: 1800, kcalAdapt: 2150)),
    'proteinSet': _goalsView(_base(proteinSet: 120)),
    'noDoctor': _goalsView(_base(doctor: false, kcalSet: 2000)),
    'female': _goalsView(_base(male: false, kg: 62, heightCm: 163, age: 44, rate: 0.0075)),
    'gain': _goalsView(_base(aim: GoalAim.gain, rate: 0.0025, kg: 70)),
    'keep': _goalsView(_base(aim: GoalAim.keep, rate: 0)),
    'tinyKcal': _goalsView(_base(kcalSet: 1500, proteinSet: 300)),
    'tdeeAt': <String, Object?>{
      for (final kg in [60.0, 84.0, 88.0, 90.0, 92.0, 120.0]) '$kg': _base().tdeeAt(kg),
    },
  };

  out['withProfile'] = <String, Object?>{
    'toFemale': _base(kcalSet: 1600, kcalAdapt: 1700).withProfile(male: false, age: 41, heightCm: 165).toJson(),
    'toMaleDropsLow':
        _base(male: false, kg: 60, heightCm: 160, kcalSet: 1300, kcalAdapt: 1250).withProfile(male: true, age: 40, heightCm: 160).toJson(),
    'floorExact':
        _base(male: false, kg: 60, heightCm: 160, kcalSet: 1500, kcalAdapt: 1499).withProfile(male: true, age: 40, heightCm: 160).toJson(),
  };

  // Ιστορικό αλλαγών του στόχου (recordChangeFrom, addTargetChange).
  final old = _base();
  final neu = _base(kcalSet: 2100);
  const oneLog = [
    AdaptLog(day: '2026-12-14', tdee: 2600, before: 2300, after: 2200, applied: true),
    AdaptLog(day: '2026-12-21', tdee: 2600, before: 2200, after: 2200, applied: false),
  ];
  Object? th(Goals g) => g.toJson()['th'];
  out['recordChange'] = <String, Object?>{
    'oldNull': th(neu.recordChangeFrom(null, DateTime(2026, 12, 14))),
    'sameKcal': th(old.recordChangeFrom(old, DateTime(2026, 12, 14))),
    'changed': th(neu.recordChangeFrom(old, DateTime(2026, 12, 14, 23, 59))),
    'oldSinceToday': th(neu.recordChangeFrom(_base(since: '2026-12-14'), DateTime(2026, 12, 14))),
    'oldSinceTomorrow': th(neu.recordChangeFrom(_base(since: '2026-12-15'), DateTime(2026, 12, 14))),
    'newSinceToday': th(_base(since: '2026-12-14', kcalSet: 2100).recordChangeFrom(old, DateTime(2026, 12, 14))),
    'newSinceTodaySameKcal': th(_base(since: '2026-12-14').recordChangeFrom(old, DateTime(2026, 12, 14))),
    'newYearDay': th(_base(since: '2027-01-01', kcalSet: 2100).recordChangeFrom(old, DateTime(2027, 1, 1))),
    'fromLogNoHist': th(neu.recordChangeFrom(_base(log: oneLog, kcalAdapt: 2200), DateTime(2026, 12, 28))),
    'sameDayAsLast': th(neu.recordChangeFrom(
        _base(kcalAdapt: 2200, hist: const [TargetChange(day: '2026-12-28', before: 2300, after: 2200)]), DateTime(2026, 12, 28))),
  };
  final many = [
    for (var i = 0; i < targetHistMax; i++)
      TargetChange(day: g141Day(DateTime(2025, 1, 1 + i)), before: 2000 + i, after: 2001 + i),
  ];
  final capped = addTargetChange(many, const [], const TargetChange(day: '2026-12-28', before: 2400, after: 2300));
  out['addTargetChange'] = <String, Object?>{
    'fromLog': [
      for (final t in addTargetChange(const [], oneLog, const TargetChange(day: '2026-12-28', before: 2200, after: 2100))) t.toJson(),
    ],
    'sameDay': [
      for (final t in addTargetChange(const [TargetChange(day: '2026-12-28', before: 2300, after: 2200)], const [],
          const TargetChange(day: '2026-12-28', before: 2200, after: 2100)))
        t.toJson(),
    ],
    'cap': <String, Object?>{'n': capped.length, 'first': capped.first.toJson(), 'last': capped.last.toJson()},
  };

  // copyWith: «καθάρισε» και ημερολόγιο ελέγχων με ανώτατο πλήθος.
  final full = _base(kcalSet: 2000, proteinSet: 140, kcalAdapt: 2100, tdeeEst: 2650.5);
  var logged = _base();
  for (var i = 0; i < 30; i++) {
    logged = logged.copyWith(
        addLog: AdaptLog(
            day: g141Day(DateTime(2026, 11, 23 + i * 7)), tdee: 2600.0 + i, before: 2300, after: 2300 - i, applied: i.isEven));
  }
  final twice = logged.copyWith(addLog: AdaptLog(day: logged.log.last.day, tdee: 2500, before: 2300, after: 2000, applied: true));
  out['copyWith'] = <String, Object?>{
    'clearKcal': full.copyWith(clearKcal: true).toJson(),
    'clearProtein': full.copyWith(clearProtein: true).toJson(),
    'clearAdapt': full.copyWith(clearAdapt: true).toJson(),
    'clearBeta': _base().copyWith(betaPer100: 5.5).copyWith(clearBeta: true, nutsG: 20, branG: 55, legumesWeek: 3, fishWeek: 2).toJson(),
    'logCap': <String, Object?>{
      'n': logged.log.length,
      'first': logged.log.first.toJson(),
      'last': logged.log.last.toJson(),
      'sameDayTwice': <String, Object?>{'n': twice.log.length, 'last': twice.log.last.toJson()},
    },
  };

  // Ανάγνωση αποθηκευμένων στόχων: τι γίνεται δεκτό, τι πέφτει στην προεπιλογή, τι απορρίπτει ολόκληρους τους στόχους.
  final ok = _base(
    kcalSet: 2000,
    proteinSet: 140,
    kcalAdapt: 2100,
    tdeeEst: 2650.5,
    checkIn: '2026-12-14',
    fastAt: '2026-12-10',
    foreignSeen: '2026-12-01',
    log: oneLog,
    docTargets: const DoctorTargets(ldlMax: 100, hdlMin: 40, tgMax: 150),
    hist: const [TargetChange(day: '2026-12-14', before: 2300, after: 2200)],
  ).copyWith(betaPer100: 5.5).toJson();
  Object? view(Map<String, dynamic> patch) {
    final g = Goals.fromJson(<String, dynamic>{...ok, ...patch});
    if (g == null) return 'ΑΠΟΡΡΙΨΗ';
    final j = g.toJson();
    return <String, Object?>{for (final k in patch.keys) k: j[k]};
  }

  final patches = <String, Map<String, dynamic>>{
    'rate=-0.001': {'rate': -0.001},
    'rate=0': {'rate': 0},
    'rate=0.01': {'rate': 0.01},
    'rate=0.0101': {'rate': 0.0101},
    'pal=1.19': {'pal': 1.19},
    'pal=1.2': {'pal': 1.2},
    'pal=2.5': {'pal': 2.5},
    'pal=2.51': {'pal': 2.51},
    'kg=29.9': {'kg': 29.9},
    'kg=30': {'kg': 30},
    'kg=300': {'kg': 300},
    'kg=300.1': {'kg': 300.1},
    'age=17': {'age': 17},
    'age=18': {'age': 18},
    'age=110': {'age': 110},
    'age=111': {'age': 111},
    'h=99.9': {'h': 99.9},
    'h=100': {'h': 100},
    'h=250': {'h': 250},
    'h=250.1': {'h': 250.1},
    'since=2026-13-01': {'since': '2026-13-01'},
    'since=2026-02-29': {'since': '2026-02-29'},
    'since=number': {'since': 20261123},
    'aim=bulk': {'aim': 'bulk'},
    'm=null': {'m': null},
    'm=text': {'m': 'true'},
    'female kcal=1300 ka=1250': {'m': false, 'kcal': 1300, 'ka': 1250},
    'female kcal=1199 ka=1200': {'m': false, 'kcal': 1199, 'ka': 1200},
    'kcal=1499': {'kcal': 1499},
    'kcal=1500': {'kcal': 1500},
    'kcal=6000': {'kcal': 6000},
    'kcal=6001': {'kcal': 6001},
    'prot=29': {'prot': 29},
    'prot=30': {'prot': 30},
    'prot=300': {'prot': 300},
    'prot=301': {'prot': 301},
    'ka=1499': {'ka': 1499},
    'ka=6001': {'ka': 6001},
    'te=799': {'te': 799},
    'te=800': {'te': 800},
    'te=8000': {'te': 8000},
    'te=8001': {'te': 8001},
    'beta=0': {'beta': 0},
    'beta=0.1': {'beta': 0.1},
    'beta=40': {'beta': 40},
    'beta=40.1': {'beta': 40.1},
    'nuts=-1': {'nuts': -1},
    'nuts=0': {'nuts': 0},
    'nuts=100': {'nuts': 100},
    'nuts=101': {'nuts': 101},
    'bran=150': {'bran': 150},
    'bran=151': {'bran': 151},
    'leg=7': {'leg': 7},
    'leg=8': {'leg': 8},
    'fish=7': {'fish': 7},
    'fish=8': {'fish': 8},
    'ci=2026-02-30': {'ci': '2026-02-30'},
    'fa=text': {'fa': 'χθες'},
    'fw=number': {'fw': 5},
    'doc=1': {'doc': 1},
    'ldl=29': {'ldl': 29},
    'ldl=30': {'ldl': 30},
    'ldl=250': {'ldl': 250},
    'ldl=251': {'ldl': 251},
    'hdl=19': {'hdl': 19},
    'hdl=20': {'hdl': 20},
    'hdl=120': {'hdl': 120},
    'hdl=121': {'hdl': 121},
    'tg=49': {'tg': 49},
    'tg=50': {'tg': 50},
    'tg=500': {'tg': 500},
    'tg=501': {'tg': 501},
    'log=junk': {
      'log': [
        1,
        {'d': 'x'},
        {'d': '2026-12-01', 'te': 2500, 'k0': 2000, 'k1': 2100},
        {'d': '2026-12-08', 'te': 799, 'k0': 2000, 'k1': 2100},
        {'d': '2026-12-08', 'te': 800, 'k0': 999, 'k1': 2100},
        {'d': '2026-12-08', 'te': 8000, 'k0': 1000, 'k1': 6000, 'ap': true, 'f': true, 'lo': true},
        {'d': '2026-12-15', 'te': 8001, 'k0': 1000, 'k1': 6000},
        {'d': '2026-12-15', 'te': 3000, 'k0': 1000, 'k1': 6001},
      ],
    },
    'th=junk': {
      'th': [
        'x',
        {'d': '2026-12-01', 'k0': 499, 'k1': 2000},
        {'d': '2026-12-01', 'k0': 500, 'k1': 20000},
        {'d': '2026-12-02', 'k0': 500, 'k1': 20001},
        {'d': '2026-2-3', 'k0': 2000, 'k1': 2100},
      ],
    },
  };
  out['fromJson'] = <String, Object?>{
    'asIs': Goals.fromJson(ok)?.toJson(),
    'notMap': Goals.fromJson('x') == null,
    'empty': Goals.fromJson(<String, dynamic>{}) == null,
    for (final e in patches.entries) e.key: view(e.value),
  };

  out['doctorTargets'] = <String, Object?>{
    'empty': <String, Object?>{'isEmpty': const DoctorTargets().isEmpty, 'text': const DoctorTargets().text},
    'all': const DoctorTargets(ldlMax: 100, hdlMin: 40, tgMax: 150).text,
    'ldl': const DoctorTargets(ldlMax: 100).text,
    'hdl+tg': const DoctorTargets(hdlMin: 45, tgMax: 150).text,
    'notEmpty': const DoctorTargets(tgMax: 150).isEmpty,
  };

  final pals = [1.2, 1.4, 1.5, 1.53, 1.589, 1.59, 1.6, 1.65, 1.7, 1.704, 1.705, 1.71, 1.76, 2.0];
  out['texts'] = <String, Object?>{
    'rateKgText': <String, Object?>{
      for (final kg in [55.0, 84.0, 110.0])
        for (final r in [...loseRates, ...gainRates]) '$kg|$r': rateKgText(kg, r),
    },
    'ratePctText': <String, Object?>{
      for (final r in [0.0, 0.0025, 0.005, 0.0075, 0.01, 0.0033, 0.00333]) '$r': ratePctText(r),
    },
    'aimText': <String, Object?>{for (final a in GoalAim.values) a.name: aimText(a)},
    'activityText': <String, Object?>{for (final p in pals) '$p': activityText(p)},
    'activityAnswer': <String, Object?>{for (final p in pals) '$p': activityAnswer(p)},
    'currentActivityLevel': <String, Object?>{for (final p in pals) '$p': currentActivityLevel(p)},
    'palText': <String, Object?>{for (final p in pals) '$p': palText(p)},
    'rateWord': <String, Object?>{
      for (final a in GoalAim.values)
        for (final r in [0.0, 0.0025, 0.004, 0.005, 0.0075]) '${a.name}|$r': rateWord(a, r),
    },
    'floorWhy': <String, Object?>{'m': floorWhy(true), 'f': floorWhy(false)},
    'missingForGoals': <String, Object?>{
      'none': missingForGoals(),
      'all': missingForGoals(age: 40, sex: 'm', heightCm: 180, kg: 90),
      'sexX': missingForGoals(age: 40, sex: 'x', heightCm: 180),
    },
    'branGramsFor': <String, Object?>{
      for (final b in [-1.0, 0.0, 0.1, 3.0, 4.0, 5.5, 8.0, 40.0, 40.1]) '$b': branGramsFor(b),
    },
  };
  return out;
}

// --------------------------------------------------------------------------------- εκτίμηση και εβδομαδιαίος έλεγχος

Map<String, Object?>? _estJson(Expenditure? e) => e == null
    ? null
    : <String, Object?>{
        'tdee': e.tdee,
        'meanIntake': e.meanIntake,
        'slopeKgWeek': e.slopeKgWeek,
        'intakeDays': e.intakeDays,
        'weighIns': e.weighIns,
        'from': g141Day(e.from),
        'to': g141Day(e.to),
        'seKcal': e.seKcal,
        'windowDays': e.windowDays,
        'guardKcal': e.guardKcal,
      };

Map<String, Object?>? _propJson(AdaptProposal? p) => p == null
    ? null
    : <String, Object?>{
        'current': p.current,
        'target': p.target,
        'fastLoss': p.fastLoss,
        'floored': p.floored,
        'withinNoise': p.withinNoise,
        'change': p.change,
        'same': p.same,
        // Έλεγχος 20/11 (K1-C-02, K1-S-05): γράφονται μόνο όταν ισχύουν, ώστε τα παλιά στιγμιότυπα να μην αλλάζουν.
        if (p.recentDiffers) 'recentDiffers': true,
        if (p.underweight) 'underweight': true,
      };

String? _gapText(FoodGap? g) => g == null ? null : '${g141Day(g.from)}..${g141Day(g.to)} restart=${_dayOrNull(g.restart) ?? '-'}';

Map<String, Object?>? _checkJson(CheckIn? c) {
  if (c == null) return null;
  return g141Compact(<String, Object?>{
    'kind': c.kind.name,
    'status': c.status?.name,
    'est': _estJson(c.est),
    'proposal': _propJson(c.proposal),
    'kgNow': c.kgNow,
    'fastSlope': c.fastSlope,
    'fastDays': c.fastDays,
    'days': c.days,
    'weighs': c.weighs,
    'tooFast': c.tooFast,
    'heldDays': c.heldDays,
    'quitDays': c.quitDays,
    'gap': _gapText(c.gap),
    'absurd': [for (final a in c.absurd) '${g141Day(a.$1)}=${a.$2.round()}'],
    'foreign': [for (final a in c.foreign) '${g141Day(a.$1)}=${_f2(a.$2)}'],
    'fastIntake': c.fastIntake,
    'fastIntakeDays': c.fastIntakeDays,
    'fastTarget': c.fastTarget,
    'estTarget': c.estTarget,
    'lowLog': c.lowLog,
    'formula': c.formula,
    'formulaKg': c.formulaKg,
    'formulaTdee': c.formulaTdee,
    'wanted': c.wanted,
    'wantsBelowFloor': c.wantsBelowFloor,
    // Έλεγχος 20/11 (K1-S-02): «τρως πολύ κάτω από τον στόχο» (null όταν δεν ισχύει).
    'farBelow': _farBelow(c),
  });
}

String? _farBelow(CheckIn c) {
  final b = eatingFarBelow(c);
  return b == null ? null : '${b.eaten}/${b.target} under=${b.under} slope=${_f2(b.slopeKgWeek)} planned=${_f2(b.plannedKgWeek)}';
}

/// Ό,τι αλλάζει στους στόχους μετά από «εφάρμοσε» / «όχι τώρα».
Map<String, Object?> _goalsBrief(Goals g) {
  final j = g.toJson();
  return g141Compact(<String, Object?>{
    'kcal': g.kcal,
    'kcalSet': j['kcal'],
    'ka': j['ka'],
    'te': j['te'],
    'ci': j['ci'],
    'fa': j['fa'],
    'fw': j['fw'],
    'log': j['log'],
    'th': j['th'],
  });
}

typedef _World = ({Map<DateTime, double> intake, List<(DateTime, double)> weights});

/// Συνθετικός κόσμος, μέρα-μέρα: [eat] το πραγματικό φαγητό, [tdee] όσα καίει, [written] τι γράφτηκε στο ημερολόγιο,
/// [logs]/[weighs] ποιες μέρες γράφτηκε φαγητό / έγινε ζύγιση (προεπιλογή: κάθε μέρα / Δευτέρα-Τετάρτη-Παρασκευή).
/// Θόρυβος με σταθερό seed (G141Rng): ίδιος σε κάθε τρέξιμο.
_World _world({
  required int seed,
  required DateTime from,
  int days = 130,
  double kg0 = 90,
  double tdee = 2800,
  double Function(int i, DateTime d)? eat,
  bool Function(int i, DateTime d)? logs,
  bool Function(int i, DateTime d)? weighs,
  double Function(int i, double eaten)? written,
  double eatNoise = 80,
  double scaleNoise = 0.3,
}) {
  final rnd = G141Rng(seed);
  final intake = <DateTime, double>{};
  final weights = <(DateTime, double)>[];
  var kg = kg0;
  for (var i = 0; i < days; i++) {
    final d = DateTime(from.year, from.month, from.day + i);
    final eaten = (eat == null ? 2300.0 : eat(i, d)) + rnd.noise(eatNoise);
    final wobble = rnd.noise(scaleNoise);
    final onScale = weighs == null ? (d.weekday == 1 || d.weekday == 3 || d.weekday == 5) : weighs(i, d);
    if (onScale) weights.add((d, ((kg + wobble) * 10).round() / 10));
    final wrote = logs == null ? true : logs(i, d);
    if (wrote) intake[d] = (written == null ? eaten : written(i, eaten)).roundToDouble();
    kg += (eaten - tdee) / kcalPerKg;
  }
  return (intake: intake, weights: weights);
}

class _Scn {
  _Scn(this.name, this.goals, _World w, {this.foreign = const [], this.read = true, this.quitDay})
      : intake = w.intake,
        weights = w.weights;
  final String name;
  final Goals goals;
  final Map<DateTime, double> intake;
  final List<(DateTime, double)> weights;
  final List<(DateTime, double)> foreign;
  final bool read;
  final DateTime? quitDay;
}

Map<DateTime, double> Function(DateTime, DateTime) _intakeOf(Map<DateTime, double> m) => (a, b) => <DateTime, double>{
      for (final e in m.entries)
        if (!e.key.isBefore(a) && !e.key.isAfter(b)) e.key: e.value,
    };

List<(DateTime, double)> _upTo(List<(DateTime, double)> w, DateTime today) => [
      for (final x in w)
        if (!x.$1.isAfter(today)) x,
    ];

List<_Scn> _scenarios() {
  final start = DateTime(2026, 11, 23); // Δευτέρα
  final g = _base(); // 2.300 kcal· ο τύπος δίνει 2.800 kcal την ημέρα
  final steady = _world(seed: 11, from: start);
  return [
    _Scn('01 τέλεια δεδομένα', g, steady),
    _Scn('02 κενό 7 ημερών στο ημερολόγιο', g, _world(seed: 12, from: start, logs: (i, d) => i < 30 || i > 36)),
    _Scn('03 ζύγιση μόνο Δευτέρα', g, _world(seed: 13, from: start, weighs: (i, d) => d.weekday == 1)),
    _Scn('04 γρήγορη απώλεια', g, _world(seed: 14, from: start, eat: (i, d) => 1700.0, tdee: 3100)),
    _Scn('05 στασιμότητα', g, _world(seed: 15, from: start, tdee: 2300)),
    _Scn(
        '06 αλλαγή στόχου στη μέση',
        _base(
          since: '2026-12-21',
          kcalAdapt: 2200,
          log: const [AdaptLog(day: '2026-12-21', tdee: 2700, before: 2300, after: 2200, applied: true)],
          hist: const [TargetChange(day: '2026-12-21', before: 2300, after: 2200)],
        ),
        _world(seed: 16, from: start, eat: (i, d) => i < 28 ? 2300.0 : 2200.0)),
    _Scn('07 το έκοψα (κάπνισμα)', g, _world(seed: 17, from: start, tdee: 2300), quitDay: DateTime(2026, 12, 20)),
    _Scn('08 γράφει τα μισά', g, _world(seed: 18, from: start, eat: (i, d) => 2900.0, written: (i, eaten) => eaten * 0.55)),
    _Scn('09 αύξηση μυών', _base(aim: GoalAim.gain, rate: 0.0025, kg: 75), _world(seed: 19, from: start, kg0: 75, eat: (i, d) => 3000.0)),
    _Scn('10 ξένες ζυγίσεις', g, steady, foreign: [(DateTime(2026, 12, 28), 62.0), (DateTime(2027, 1, 4), 61.5)]),
    _Scn('11 αδύνατες μέρες', g,
        _world(seed: 21, from: start, written: (i, eaten) => i == 25 ? 9500.0 : (i == 26 ? 400.0 : eaten))),
    _Scn('12 ζυγίσεις αδιάβαστες', g, steady, read: false),
    _Scn('13 αλλαγή ώρας 28/3', _base(since: '2027-03-01'), _world(seed: 23, from: DateTime(2027, 3, 1))),
    _Scn('14 ίδιο βάρος', _base(aim: GoalAim.keep, rate: 0), _world(seed: 24, from: start, eat: (i, d) => 2800.0, tdee: 2650)),
    _Scn('15 γυναίκα στο κατώτατο', _base(male: false, kg: 62, heightCm: 160, age: 44, rate: 0.0075),
        _world(seed: 25, from: start, kg0: 62, eat: (i, d) => 1250.0, tdee: 1650)),
    _Scn('16 ζυγαριά με θόρυβο', g, _world(seed: 26, from: start, scaleNoise: 1.5)),
    _Scn('17 ζύγιση κάθε μέρα', g, _world(seed: 27, from: start, weighs: (i, d) => true)),
    _Scn('18 σταμάτησε να γράφει', g, _world(seed: 28, from: start, logs: (i, d) => i < 30)),
    _Scn('19 αλλαγή ώρας 25/10', _base(since: '2026-10-05'), _world(seed: 29, from: DateTime(2026, 10, 5))),
    _Scn('20 τρώει λίγο πιο πολύ', g, _world(seed: 30, from: start, eat: (i, d) => 2450.0)),
  ];
}

Map<String, Object?> _at(_Scn s, Goals g, DateTime today) {
  final w = _upTo(s.weights, today);
  final intake = _intakeOf(s.intake);
  final c = pendingCheckIn(
      goals: g, today: today, weights: w, intake: intake, foreign: s.foreign, weightsRead: s.read, quitDay: s.quitDay);
  final r = readiness(goals: g, today: today, weights: w, intake: intake);
  final next = nextCheckDay(g, today);
  final fast = fastLossSlope(goals: g, weights: w, today: today);
  Object? applied;
  Object? dismissed;
  if (c != null) {
    final check = c;
    if (check.proposal != null) applied = g141Safe(() => _goalsBrief(applyCheckIn(check, today)));
    dismissed = g141Safe(() => _goalsBrief(dismissCheckIn(check, today)));
  }
  return g141Compact(<String, Object?>{
    'check': _checkJson(c),
    'due': checkInDue(goals: g, today: today, lastCheckIn: g.checkIn),
    'next': g141Day(next),
    'ready': '${r.intakeDays}|${r.weighIns}|${r.weighSpan}|${g141Day(r.first)}',
    'readyGap': _gapText(r.gap),
    'afterGap': _dayOrNull(estimateDayAfterGap(g, next, r.gap)),
    'fast': fast == null ? null : [fast.slopeKgWeek, fast.kg],
    'apply': applied,
    'dismiss': dismissed,
  });
}

/// Η ίδια σειρά μέρα-μέρα, με τις απαντήσεις να αλλάζουν τους στόχους («εφάρμοσε» όταν προτείνει αλλαγή, αλλιώς
/// «όχι τώρα»): πιάνει το ιστορικό του στόχου, το «κράτα 4 μέρες» και τον έλεγχο γρήγορης απώλειας ανάμεσα στους ελέγχους.
List<Object?> _journey(_Scn s, int days) {
  final out = <Object?>[];
  var g = s.goals;
  final since = DateTime.parse(s.goals.since);
  for (var i = 0; i <= days; i++) {
    final today = DateTime(since.year, since.month, since.day + i, 8, 20);
    final c = pendingCheckIn(
        goals: g,
        today: today,
        weights: _upTo(s.weights, today),
        intake: _intakeOf(s.intake),
        foreign: s.foreign,
        weightsRead: s.read,
        quitDay: s.quitDay);
    if (c == null) continue;
    // Αδιάβαστες ζυγίσεις: η κάρτα μένει ίδια κάθε μέρα· γράφεται μόνο η πρώτη φορά.
    if (c.kind == CheckKind.unread) {
      if (out.isEmpty) out.add('${g141Day(today)} unread (και κάθε επόμενη μέρα)');
      continue;
    }
    final p = c.proposal;
    final apply = p != null && !p.same && (c.kind == CheckKind.proposal || c.kind == CheckKind.fast);
    g = apply ? applyCheckIn(c, today) : dismissCheckIn(c, today);
    out.add('${g141Day(today)} ${c.kind.name} ${c.status?.name ?? '-'} '
        '${p == null ? '-' : '${p.current}→${p.target}'} ${apply ? 'εφάρμοσε' : 'όχι τώρα'} → ${g.kcal} kcal');
  }
  out.add(_goalsBrief(g));
  return out;
}

Map<String, Object?> _checkinGolden() {
  final out = <String, Object?>{};
  const offsets = [7, 13, 14, 17, 20, 21, 23, 26, 28, 30, 33, 35, 42, 45, 49, 56, 63, 70, 84];
  for (final s in _scenarios()) {
    final since = DateTime.parse(s.goals.since);
    final days = <String, Object?>{};
    for (final o in offsets) {
      final today = DateTime(since.year, since.month, since.day + o, 8, 20);
      days['+${o.toString().padLeft(2, '0')} ${g141Day(today)}'] = g141Safe(() => _at(s, s.goals, today));
    }
    // Ανάμεσα στους ελέγχους (ο τελευταίος έλεγχος απαντήθηκε τη Δευτέρα της ίδιας εβδομάδας): ο δρόμος της γρήγορης απώλειας.
    for (final o in [23, 26, 30, 33, 45, 59]) {
      final today = DateTime(since.year, since.month, since.day + o, 8, 20);
      final answered = DateTime(since.year, since.month, since.day + o - o % 7);
      days['+${o.toString().padLeft(2, '0')} ${g141Day(today)} μετά τον έλεγχο'] =
          g141Safe(() => _at(s, s.goals.copyWith(checkIn: g141Day(answered)), today));
    }
    out[s.name] = <String, Object?>{
      'days': days,
      'journey': g141Safe(() => _journey(s, 91)),
    };
  }
  return out;
}

Expenditure _est(double tdee, {double slope = -0.45, double se = 0, double mean = 2300}) => Expenditure(
    tdee: tdee,
    meanIntake: mean,
    slopeKgWeek: slope,
    intakeDays: 21,
    weighIns: 9,
    from: DateTime(2026, 12, 21),
    to: DateTime(2027, 1, 10),
    seKcal: se);

Map<DateTime, double> _days(DateTime from, int n, {Set<int> skip = const {}, double kcal = 2300, Map<int, double> other = const {}}) =>
    <DateTime, double>{
      for (var i = 0; i < n; i++)
        if (!skip.contains(i)) DateTime(from.year, from.month, from.day + i): other[i] ?? kcal,
    };

List<(DateTime, double)> _line(DateTime from, List<int> offsets, double kg0, {double perDay = 0, List<double> wobble = const [0]}) => [
      for (var k = 0; k < offsets.length; k++)
        (DateTime(from.year, from.month, from.day + offsets[k]), kg0 + perDay * offsets[k] + wobble[k % wobble.length]),
    ];

Map<String, Object?> _fitJson(List<(DateTime, double)> w) {
  final f = weightFit(w);
  return <String, Object?>{'slope': f?.slope, 'se': f?.se, 'weightSlope': weightSlope(w)};
}

Map<String, Object?> _adaptiveGolden() {
  final out = <String, Object?>{};
  final start = DateTime(2026, 11, 23);
  final g = _base();
  out['constants'] = <String, Object?>{
    'adaptWindowDays': adaptWindowDays,
    'adaptWindows': adaptWindows,
    'adaptMaxWindowDays': adaptMaxWindowDays,
    'adaptSkipDays': adaptSkipDays,
    'adaptMinIntakeDays': adaptMinIntakeDays,
    'adaptMinWeighIns': adaptMinWeighIns,
    'adaptMinSpanDays': adaptMinSpanDays,
    'adaptFullDayShare': adaptFullDayShare,
    'adaptMaxStep': adaptMaxStep,
    'adaptMinStep': adaptMinStep,
    'adaptGapDays': adaptGapDays,
    'adaptScanDays': adaptScanDays,
    'adaptMinChangeDays': adaptMinChangeDays,
    'adaptAbsurdKcal': adaptAbsurdKcal,
    'adaptAbsurdTimes': adaptAbsurdTimes,
    'adaptLowShare': adaptLowShare,
    'adaptHighShare': adaptHighShare,
    'adaptGuardSe': adaptGuardSe,
    'adaptFastLossPct': adaptFastLossPct,
    'adaptFastFromDay': adaptFastFromDay,
    'adaptFastWindowDays': adaptFastWindowDays,
    'adaptFastGuardSe': adaptFastGuardSe,
    'formulaKgDrift': formulaKgDrift,
    'estimatedShareNote': estimatedShareNote,
    'smokeQuitHoldDays': smokeQuitHoldDays,
    'adaptFastMinIntakeDays': adaptFastMinIntakeDays,
    'adaptFastRecentDays': adaptFastRecentDays,
    'adaptFastRecentMinDays': adaptFastRecentMinDays,
  };
  out['adaptNeeds'] = <String, Object?>{
    for (final w in [14, 21, 22, 28, 30, 35, 42, 56])
      '$w': () {
        final n = adaptNeeds(w);
        return '${n.intakeDays}|${n.weighIns}|${n.spanDays}';
      }(),
  };
  out['absurdDayKcal'] = <String, Object?>{
    for (final f in [1500.0, 2399.0, 2400.0, 2401.0, 2800.0, 3500.0]) '$f': absurdDayKcal(f),
  };
  out['roundTo'] = <String, Object?>{
    for (final (v, d) in [(2.345, 2), (2.355, 2), (-2.345, 2), (82.25, 1), (82.35, 1), (0.5, 0), (1.5, 0), (-0.5, 0)])
      '$v|$d': roundTo(v, d),
  };

  // Κλίση βάρους (ελάχιστα τετράγωνα) και αβεβαιότητα.
  out['weightFit'] = <String, Object?>{
    'empty': _fitJson(const []),
    'one': _fitJson(_line(start, [0], 90)),
    'two same day': _fitJson([(start, 90.0), (start, 89.0)]),
    'two': _fitJson(_line(start, [0, 7], 90, perDay: -0.07)),
    'three on a line': _fitJson(_line(start, [0, 7, 14], 90, perDay: -0.07)),
    'nine M/W/F wobble': _fitJson(_line(start, [0, 2, 4, 7, 9, 11, 14, 16, 18], 90, perDay: -0.064, wobble: const [0.2, -0.3, 0.1, 0.4, -0.2])),
    'drift then flat': _fitJson([
      ..._line(start, [0, 2, 4, 7, 9], 90, perDay: -0.15),
      ..._line(start, [11, 14, 16, 18, 21], 88.6),
    ]),
    'flat': _fitJson(_line(start, [0, 2, 4, 7, 9, 11], 90)),
    'across 28/3 (hours)': _fitJson([
      for (var k = 0; k < 8; k++) (DateTime(2027, 3, 22 + k * 2, k.isEven ? 7 : 23, 30), 88.0 - k * 0.11),
    ]),
  };

  out['formulaNow'] = <String, Object?>{
    for (final kg in [29.9, 30.0, 87.99, 88.0, 88.01, 89.0, 90.0, 91.99, 92.0, 92.01, 300.0, 300.1])
      '$kg': () {
        final f = formulaNow(g, [(start, 90.0), (DateTime(2026, 12, 14), kg)]);
        return <String, Object?>{'tdee': f.tdee, 'kg': f.kg};
      }(),
    'empty': () {
      final f = formulaNow(g, const []);
      return <String, Object?>{'tdee': f.tdee, 'kg': f.kg};
    }(),
  };

  // Πρόταση νέου στόχου: σήμερα 2.300· «θέλει» = εκτίμηση − 495 (90 kg, −0,5%)· βήμα 30–150· θόρυβος 2 × SE.
  final propose = <String, Object?>{};
  for (var t = 2560; t <= 3020; t += 10) {
    final cells = <String>[];
    for (final se in [0.0, 12.0, 40.0, 80.0]) {
      final p = proposeTarget(goals: g, est: _est(t.toDouble(), se: se), kgNow: 90);
      cells.add('${p.target}${p.withinNoise ? 'n' : ''}${p.floored ? 'f' : ''}');
    }
    propose['$t'] = cells.join(' ');
  }
  out['proposeTarget se=0|12|40|80'] = propose;
  final fem = _base(male: false, kg: 62, heightCm: 160, age: 44, rate: 0.0075, kcalSet: 1300);
  out['proposeTarget floor'] = <String, Object?>{
    for (final t in [1500.0, 1600.0, 1680.0, 1690.0, 1700.0, 1711.0, 1720.0, 1800.0])
      '$t': _propJson(proposeTarget(goals: fem, est: _est(t), kgNow: 62)),
    'kgNow 80 vs 100': [
      _propJson(proposeTarget(goals: g, est: _est(2900), kgNow: 80)),
      _propJson(proposeTarget(goals: g, est: _est(2900), kgNow: 100)),
    ],
    'gain': _propJson(proposeTarget(goals: _base(aim: GoalAim.gain, rate: 0.0025, kg: 75), est: _est(2900), kgNow: 75)),
    'keep': _propJson(proposeTarget(goals: _base(aim: GoalAim.keep, rate: 0), est: _est(2900), kgNow: 90)),
  };
  out['plannedKgWeek'] = <String, Object?>{
    'lose': plannedKgWeek(g, 90),
    'gain': plannedKgWeek(_base(aim: GoalAim.gain, rate: 0.0025), 75),
    'keep': plannedKgWeek(_base(aim: GoalAim.keep, rate: 0), 90),
  };

  // Πρόταση όταν το ημερολόγιο γράφει πολύ λίγα (εκτίμηση κάτω από 70% του τύπου = 1.960).
  final low = <String, Object?>{};
  for (final t in [1900.0, 1959.0, 1960.0, 1961.0]) {
    for (final slope in [-0.6, -0.45, -0.42, -0.3, 0.0, 0.3]) {
      for (final se in [0.0, 50.0, 200.0]) {
        final p = lowLogProposal(goals: g, est: _est(t, slope: slope, se: se), kgNow: 90);
        low['$t|$slope|$se'] = p == null ? null : '${p.current}→${p.target}${p.floored ? ' f' : ''}';
      }
    }
  }
  low['formula 3000, est 2050'] = _propJson(lowLogProposal(goals: g, est: _est(2050, slope: 0.1), kgNow: 90, formulaTdee: 3000));
  low['female floor'] = _propJson(lowLogProposal(goals: fem, est: _est(900, slope: 0.2), kgNow: 62));
  out['lowLogProposal'] = low;

  // Γρήγορη απώλεια: όριο 1% του βάρους την εβδομάδα, από τη 14η μέρα, ζυγίσεις μετά την πρώτη εβδομάδα.
  final fast = <String, Object?>{};
  for (final perWeek in [0.6, 0.85, 0.9, 0.95, 1.0, 1.1, 1.4]) {
    final w = _line(start, [0, 2, 4, 7, 9, 11, 14, 16, 18, 21, 23, 25, 28, 30, 32, 35], 90, perDay: -perWeek / 7, wobble: const [0.05, -0.05, 0]);
    for (final o in [13, 14, 17, 18, 21, 28, 35]) {
      final today = DateTime(2026, 11, 23 + o, 9);
      final seen = _upTo(w, today);
      final f = fastLossSlope(goals: g, weights: seen, today: today);
      final win = fastLossWindow(goals: g, today: today);
      final c = fastLossCheck(goals: g, weights: seen, today: today);
      fast['$perWeek kg/εβδ. +$o'] = g141Compact(<String, Object?>{
        'window': win == null ? null : '${g141Day(win.$1)}..${g141Day(win.$2)}',
        'n': fastLossWeights(goals: g, weights: seen, today: today).length,
        'slope': f?.slopeKgWeek,
        'kg': f?.kg,
        'check': _propJson(c),
      });
    }
  }
  final steep = _line(start, [7, 9, 11, 14, 16, 18, 21], 90, perDay: -0.25);
  fast['aim keep'] = fastLossSlope(goals: _base(aim: GoalAim.keep, rate: 0), weights: steep, today: DateTime(2026, 12, 14)) == null;
  fast['cap tdeeEst 2390'] = _propJson(fastLossCheck(goals: _base(tdeeEst: 2390), weights: steep, today: DateTime(2026, 12, 14)));
  fast['cap tdeeEst 2320'] = _propJson(fastLossCheck(goals: _base(tdeeEst: 2320), weights: steep, today: DateTime(2026, 12, 14)));
  fast['cap tdeeEst 2334'] = _propJson(fastLossCheck(goals: _base(tdeeEst: 2334), weights: steep, today: DateTime(2026, 12, 14)));
  fast['fastLossCap'] = [fastLossCap(g), fastLossCap(_base(tdeeEst: 2654.9)), fastLossCap(_base(tdeeEst: 2655))];
  fast['3 ζυγίσεις'] = fastLossSlope(goals: g, weights: steep.sublist(0, 3), today: DateTime(2026, 12, 14)) == null;
  fast['εύρος 9 ημερών'] = fastLossSlope(goals: g, weights: _line(start, [7, 9, 11, 16], 90, perDay: -0.25), today: DateTime(2026, 12, 14)) == null;
  fast['εύρος 10 ημερών'] = fastLossSlope(goals: g, weights: _line(start, [7, 9, 11, 17], 90, perDay: -0.25), today: DateTime(2026, 12, 14)) == null;
  out['fastLoss'] = fast;

  // Πότε ανοίγει ο έλεγχος: κάθε μέρα των πρώτων 6 εβδομάδων, με/χωρίς προηγούμενη απάντηση, με/χωρίς αλλαγή στόχου.
  final changed = _base(checkIn: '2026-12-14', log: const [AdaptLog(day: '2026-12-14', tdee: 2700, before: 2300, after: 2200, applied: true)]);
  String dueRow(Goals x, String? last) => [
        for (var o = 0; o <= 44; o++) checkInDue(goals: x, today: DateTime(2026, 11, 23 + o, 22, 30), lastCheckIn: last) ? '1' : '0',
      ].join();
  String nextRow(Goals x) => [
        for (final o in [0, 10, 20, 21, 22, 24, 25, 27, 28, 29, 34, 35, 36, 43]) g141Day(nextCheckDay(x, DateTime(2026, 11, 23 + o, 22, 30))).substring(5),
      ].join(' ');
  out['checkInDue'] = <String, Object?>{
    'no answer yet': dueRow(g, null),
    'answered 14/12': dueRow(g, '2026-12-14'),
    'answered 16/12': dueRow(g, '2026-12-16'),
    'answered 14/12, target changed': dueRow(changed, '2026-12-14'),
    'answered 18/12, target changed that day':
        dueRow(_base(log: const [AdaptLog(day: '2026-12-18', tdee: 2700, before: 2300, after: 2200, applied: true)]), '2026-12-18'),
    'bad lastCheckIn': dueRow(g, 'x'),
    'bad since': checkInDue(goals: _base(since: 'x'), today: DateTime(2026, 12, 14)),
    'since Thursday': [
      for (var o = 0; o <= 30; o++)
        checkInDue(goals: _base(since: '2026-11-26'), today: DateTime(2026, 11, 26 + o), lastCheckIn: null) ? '1' : '0',
    ].join(),
    'answerChangedTarget': [
      answerChangedTarget(changed, DateTime(2026, 12, 14, 23)),
      answerChangedTarget(changed, DateTime(2026, 12, 15)),
      answerChangedTarget(g, DateTime(2026, 12, 14)),
    ],
    'nextCheckDay': <String, Object?>{
      'no answer yet': nextRow(g),
      'answered 14/12': nextRow(_base(checkIn: '2026-12-14')),
      'answered 14/12, target changed': nextRow(changed),
      'answered 18/12, target changed': nextRow(_base(
          checkIn: '2026-12-18', log: const [AdaptLog(day: '2026-12-18', tdee: 2700, before: 2300, after: 2200, applied: true)])),
    },
    'firstCheckDay/firstEstimateDay': <String, Object?>{
      for (final s in ['2026-11-23', '2026-10-05', '2026-10-19', '2027-03-08', '2026-12-10', '2028-02-08'])
        s: '${g141Day(firstCheckDay(_base(since: s)))} ${g141Day(firstEstimateDay(_base(since: s)))}',
    },
    'lastChangeDay': [
      _dayOrNull(lastChangeDay(g)),
      _dayOrNull(lastChangeDay(changed)),
      _dayOrNull(lastChangeDay(_base(log: const [
        AdaptLog(day: '2026-12-21', tdee: 2700, before: 2300, after: 2200, applied: true),
        AdaptLog(day: '2026-12-14', tdee: 2700, before: 2300, after: 2200, applied: true),
        AdaptLog(day: '2026-12-28', tdee: 2700, before: 2200, after: 2200, applied: false),
      ]))),
    ],
  };

  out['quitHoldDays'] = <String, Object?>{
    for (final o in [-1, 0, 1, 69, 70, 71]) '$o': quitHoldDays(DateTime(2026, 12, 20, 15), DateTime(2026, 12, 20 + o, 8)),
    'null': quitHoldDays(null, DateTime(2026, 12, 20)),
    'across 28/3': quitHoldDays(DateTime(2027, 1, 18), DateTime(2027, 3, 29)),
  };
  out['fastPeriodText'] = <String, Object?>{for (final d in <int?>[null, 7, 14, 20, 21]) '$d': fastPeriodText(d)};
  out['estimatedShareText'] = <String, Object?>{
    for (final s in <double?>[null, 0.0, 0.149, 0.15, 0.151, 0.305, 0.315, 1.0]) '$s': estimatedShareText(s),
  };

  // Ο στόχος που ίσχυε κάθε μέρα (για τη σύγκριση «έφαγες όσο ο στόχος»).
  final hist = _base(kcalAdapt: 2100, hist: const [
    TargetChange(day: '2026-12-14', before: 2300, after: 2200),
    TargetChange(day: '2026-12-28', before: 2200, after: 2100),
  ]);
  final fromLog = _base(kcalAdapt: 2100, log: const [
    AdaptLog(day: '2026-12-14', tdee: 2700, before: 2300, after: 2200, applied: true),
    AdaptLog(day: '2026-12-21', tdee: 2700, before: 2200, after: 2200, applied: false),
    AdaptLog(day: '2026-12-28', tdee: 2700, before: 2200, after: 2100, applied: true),
  ]);
  final probe = [DateTime(2026, 12, 13), DateTime(2026, 12, 14, 12), DateTime(2026, 12, 15), DateTime(2026, 12, 28), DateTime(2026, 12, 29)];
  out['targetOn'] = <String, Object?>{
    'hist': [for (final d in probe) targetOn(hist, d)],
    'log': [for (final d in probe) targetOn(fromLog, d)],
    'none': [for (final d in probe) targetOn(g, d)],
    'mean hist': meanTargetOn(hist, probe),
    'mean empty': meanTargetOn(hist, const []),
  };

  // Κενό στο ημερολόγιο φαγητού: 5 συνεχόμενες μέρες χωρίς πλήρη καταγραφή.
  final gapDay = DateTime(2027, 1, 12, 8); // 50 μέρες μετά τις 23/11
  String? gap(Map<DateTime, double> intake, {DateTime? since, DateTime? at}) =>
      _gapText(foodGap(intake: intake, today: at ?? gapDay, formulaTdee: 2800, goalKcal: 2300, since: since));
  out['foodGap'] = <String, Object?>{
    'full': gap(_days(start, 50), since: start),
    'empty': gap(const {}, since: start),
    '4 missing': gap(_days(start, 50, skip: {20, 21, 22, 23}), since: start),
    '5 missing': gap(_days(start, 50, skip: {20, 21, 22, 23, 24}), since: start),
    'two gaps': gap(_days(start, 50, skip: {12, 13, 14, 15, 16, 30, 31, 32, 33, 34, 35}), since: start),
    'last 4 missing': gap(_days(start, 46), since: start),
    'last 5 missing': gap(_days(start, 45), since: start),
    'first week ignored': gap(_days(start, 50, skip: {0, 1, 2, 3, 4, 5, 6}), since: start),
    'leading 5 after first week': gap(_days(start, 50, skip: {7, 8, 9, 10, 11}), since: start),
    'leading 5, no since': gap(_days(start, 50, skip: {3, 4, 5, 6, 7}), at: DateTime(2027, 1, 12)),
    '1379 kcal days': gap(_days(start, 50, other: {20: 1379, 21: 1379, 22: 1379, 23: 1379, 24: 1379}), since: start),
    '1380 kcal days': gap(_days(start, 50, other: {20: 1380, 21: 1380, 22: 1380, 23: 1380, 24: 1380}), since: start),
    '7000 kcal days': gap(_days(start, 50, other: {20: 7000, 21: 7000, 22: 7000, 23: 7000, 24: 7000}), since: start),
    '7001 kcal days': gap(_days(start, 50, other: {20: 7001, 21: 7001, 22: 7001, 23: 7001, 24: 7001}), since: start),
    'across 28/3': gap(_days(DateTime(2027, 3, 1), 50, skip: {25, 26, 27, 28, 29}), since: DateTime(2027, 3, 1), at: DateTime(2027, 4, 20)),
    'across 25/10': gap(_days(DateTime(2026, 10, 5), 50, skip: {18, 19, 20, 21, 22}), since: DateTime(2026, 10, 5), at: DateTime(2026, 11, 24)),
  };

  // Εκτίμηση: τα ελάχιστα (μέρες φαγητού, ζυγίσεις, εύρος) και τα όρια «δεν βγάζει νόημα» (70% / 140% του τύπου).
  Map<String, Object?> est({required Map<DateTime, double> intake, required List<(DateTime, double)> weights, DateTime? at, DateTime? since}) {
    final r = estimateExpenditure(
        intake: intake, weights: weights, today: at ?? DateTime(2026, 12, 21, 8), formulaTdee: 2800, goalKcal: 2300, since: since);
    return g141Compact(<String, Object?>{'status': r.status.name, 'est': _estJson(r.est)});
  }

  final w9 = _line(start, [7, 9, 11, 14, 16, 18, 21, 23, 25], 90, perDay: -0.064);
  final flat9 = _line(start, [7, 9, 11, 14, 16, 18, 21, 23, 25], 90);
  final e = <String, Object?>{
    'since 23/11, 20/12 (20 μέρες)': est(intake: _days(start, 28), weights: w9, at: DateTime(2026, 12, 20, 8), since: start),
    'since 23/11, 21/12 (21 μέρες)': est(intake: _days(start, 28), weights: w9, since: start),
    'no since': est(intake: _days(start, 28), weights: w9),
    '13 intake days': est(intake: _days(start, 28, skip: {7, 8, 9, 10, 11, 12, 13, 14}), weights: w9, since: start),
    '14 intake days': est(intake: _days(start, 28, skip: {7, 9, 11, 13, 15, 17, 19}), weights: w9, since: start),
    '5 weigh-ins': est(intake: _days(start, 28), weights: _line(start, [7, 11, 16, 21, 25], 90, perDay: -0.064), since: start),
    '6 weigh-ins, span 13': est(intake: _days(start, 28), weights: _line(start, [7, 9, 11, 14, 18, 20], 90, perDay: -0.064), since: start),
    '6 weigh-ins, span 14': est(intake: _days(start, 28), weights: _line(start, [7, 9, 11, 14, 18, 21], 90, perDay: -0.064), since: start),
    'same weight every day': est(intake: _days(start, 28), weights: flat9, since: start),
    'weights 29.9 / 300.1 ignored': est(
        intake: _days(start, 28), weights: [...w9, (DateTime(2026, 12, 19), 29.9), (DateTime(2026, 12, 20), 300.1)], since: start),
  };
  for (final kcal in [1959.0, 1960.0, 1961.0, 3919.0, 3920.0, 3921.0]) {
    e['flat weight, eats $kcal'] = est(intake: _days(start, 28, kcal: kcal), weights: flat9, since: start);
  }
  for (final o in [28, 35, 42, 49, 56]) {
    e['long history +$o'] = est(
        intake: _days(start, 70),
        weights: _line(start, [for (var k = 0; k < 30; k++) (k ~/ 3) * 7 + const [0, 2, 4][k % 3]], 90, perDay: -0.064, wobble: const [0.1, -0.2, 0.15, -0.05]),
        at: DateTime(2026, 11, 23 + o, 8),
        since: start);
  }
  out['estimateExpenditure'] = e;

  out['estimateDayAfterGap'] = <String, Object?>{
    'no gap': _dayOrNull(estimateDayAfterGap(g, DateTime(2027, 1, 4), null)),
    'open gap': _dayOrNull(estimateDayAfterGap(g, DateTime(2027, 1, 4), (from: DateTime(2026, 12, 20), to: DateTime(2027, 1, 3), restart: null))),
    'restart 12/12': _dayOrNull(
        estimateDayAfterGap(g, DateTime(2027, 1, 4), (from: DateTime(2026, 12, 5), to: DateTime(2026, 12, 11), restart: DateTime(2026, 12, 12)))),
    'restart 14/12': _dayOrNull(
        estimateDayAfterGap(g, DateTime(2027, 1, 4), (from: DateTime(2026, 12, 5), to: DateTime(2026, 12, 13), restart: DateTime(2026, 12, 14)))),
    'restart 16/12': _dayOrNull(
        estimateDayAfterGap(g, DateTime(2027, 1, 4), (from: DateTime(2026, 12, 5), to: DateTime(2026, 12, 15), restart: DateTime(2026, 12, 16)))),
  };

  // Ζυγίσεις και θερμίδες όπως τις παίρνει ο έλεγχος από τα δεδομένα (φύλακας ζυγίσεων, ημερολόγιο φαγητού).
  final body = <BodyMeasurement>[
    for (var k = 0; k < 12; k++)
      BodyMeasurement(time: DateTime(2026, 11, 23 + (k ~/ 3) * 7 + const [0, 2, 4][k % 3], 7, 30), weight: 90 - k * 0.2, app: _inbody),
    BodyMeasurement(time: DateTime(2026, 12, 8, 19), weight: 41.5, app: _inbody), // άλλος στη ζυγαριά
    BodyMeasurement(time: DateTime(2026, 12, 9, 7, 20), weight: double.nan, app: _inbody),
    BodyMeasurement(time: DateTime(2026, 12, 9, 21, 10), weight: 89.9, app: _inbody), // βράδυ της ίδιας μέρας
    BodyMeasurement(time: DateTime(2026, 12, 12, 8), fatPct: 27.1, app: _inbody), // χωρίς βάρος
  ];
  final split = guardedWeights(body);
  out['guardedWeights'] = <String, Object?>{
    'used': [for (final x in split.used) '${g141Day(x.$1)}=${_f2(x.$2)}'],
    'foreign': [for (final x in split.foreign) '${g141Day(x.$1)}=${_f2(x.$2)}'],
    'dailyWeights': dailyWeights(body).length,
  };
  final food = checkinFood(DateTime(2026, 12, 14), skip: const {2, 5});
  final eaten = dailyIntake(food, DateTime(2026, 12, 7), DateTime(2026, 12, 14));
  out['dailyIntake'] = <String, Object?>{for (final x in eaten.entries) g141Day(x.key): x.value};
  out['estimatedShare'] = <String, Object?>{
    'all': estimatedShare(food, DateTime(2026, 12, 7), DateTime(2026, 12, 14)),
    'min 1380': estimatedShare(food, DateTime(2026, 12, 7), DateTime(2026, 12, 14), minKcal: 1380),
    'max 1000': estimatedShare(food, DateTime(2026, 12, 7), DateTime(2026, 12, 14), maxKcal: 1000),
    'no food': estimatedShare(food, DateTime(2026, 10, 1), DateTime(2026, 10, 7)),
  };
  return out;
}

// ---------------------------------------------------------------------------- φύλακας ζυγίσεων, τάση σώματος, μέση

DateTime _mwf(int i) => DateTime(2026, 11, 23 + (i ~/ 3) * 7 + const [0, 2, 4][i % 3]);

/// 18 ζυγίσεις Δευτέρα-Τετάρτη-Παρασκευή γύρω από [kg] (μικρή, σταθερή διακύμανση).
List<(DateTime, double)> _series(int n, {double kg = 82.0}) => [
      for (var i = 0; i < n; i++) (_mwf(i), kg + const [0.0, 0.3, -0.2][i % 3]),
    ];

List<(DateTime, double)> _swap(List<(DateTime, double)> s, Map<int, double> at) => [
      for (var i = 0; i < s.length; i++) (s[i].$1, at[i] ?? s[i].$2),
    ];

String _statuses(List<(DateTime, double)> s) => [for (var i = 0; i < s.length; i++) weighStatusAt(s, i).name[0]].join();

String _guard(List<(DateTime, List<double>)> days) => [
      for (final r in guardDays(days)) '${r.pick}${r.status.name[0]}${r.unsure ? '?' : ''}',
    ].join(' ');

String _bm(BodyMeasurement? b) =>
    b == null ? '-' : '${g141Day(b.time)} ${_hm(b.time)} ${_f2(b.weight)} kg, λίπος ${_f2(b.fatPct)}, μύες ${_f2(b.smm)}';

Map<String, Object?> _bodyView(List<BodyMeasurement> body) {
  final g = guardBody(body);
  final counted = countedBody(body);
  Object? trend(double? Function(BodyMeasurement) f) {
    final t = bodyTrend(body, f);
    return t == null ? null : <String, Object?>{'now': t.now, 'before': t.before, 'from': t.from, 'to': t.to};
  }

  return g141Compact(<String, Object?>{
    'days': [
      for (final d in weighInDays(body))
        '${g141Day(d.day)} n=${d.all.length} → ${_hm(d.pick.time)} ${_f2(d.pick.weight)} λίπος ${_f2(d.pick.fatPct)} '
            '${d.status.name}${d.unsure ? ' ?' : ''}',
    ],
    'foreign': [for (final b in body) if (g.foreign.contains(b)) _bm(b)],
    'pending': [for (final b in body) if (g.pending.contains(b)) _bm(b)],
    'mixedDayPending': [for (final b in body) if (mixedDayPending(g.pending, b)) _bm(b)],
    'counted': counted.length,
    'shown': shownBody(body).length,
    'foreignBody': foreignBody(body).length,
    'weight daily': bodyDaily(body, (b) => b.weight).length,
    'compositionDays': bodyCompositionDays(body),
    'trend weight': trend((b) => b.weight),
    'trend fat': trend((b) => b.fatPct),
    'trend smm': trend((b) => b.smm),
    'previousCounted': counted.isEmpty ? null : _bm(previousCounted(counted, counted.last)),
    'dayWeighIn first': body.isEmpty ? null : _bm(dayWeighIn(body, body.first.time)),
    'dayWeighIn last': body.isEmpty ? null : _bm(dayWeighIn(body, body.last.time)),
    'average7': [
      for (final p in average7Days(bodyDaily(body, (b) => b.weight))) '${g141Day(p.$1)}=${p.$2.toStringAsFixed(4)}',
    ],
  });
}

Map<String, Object?> _bodyGolden() {
  final out = <String, Object?>{};
  out['constants'] = <String, Object?>{
    'weightGuardDays': weightGuardDays,
    'weightGuardMinNeighbours': weightGuardMinNeighbours,
    'weightGuardKg': weightGuardKg,
    'weightGuardShare': weightGuardShare,
    'weightConfirmDays': weightConfirmDays,
    'weightConfirmSpan': weightConfirmSpan,
    'weightGuardHorizon': weightGuardHorizon,
    'weightGuardSameWeek': weightGuardSameWeek,
    'weightConfirmKg': weightConfirmKg,
    'weightConfirmShare': weightConfirmShare,
    'weightConfirmBigKg': weightConfirmBigKg,
    'weightConfirmBigShare': weightConfirmBigShare,
    'weightConfirmGap': weightConfirmGap,
    'weightReachKgPerDay': weightReachKgPerDay,
    'bodyTrendGroup': bodyTrendGroup,
    'bodyTrendGapDays': bodyTrendGapDays,
    'bodySameSessionMin': bodySameSessionMin,
    'bodyFloorFatPct': bodyFloorFatPct,
    'bodyFloorKg': bodyFloorKg,
    'waistMinCm': waistMinCm,
    'waistMaxCm': waistMaxCm,
    'waistSpreadCm': waistSpreadCm,
  };

  out['weightsAgree'] = <String, Object?>{
    for (final (a, b) in [
      (80.0, 80.0),
      (80.0, 83.99),
      (80.0, 84.0),
      (80.0, 84.01),
      (84.0, 80.0),
      (84.01, 80.0),
      (95.0, 100.0),
      (94.99, 100.0),
      (100.0, 105.0),
      (100.0, 105.3),
      (114.0, 120.0),
      (113.9, 120.0),
      (60.0, 64.0),
      (60.0, 64.1),
      (35.0, 82.0),
    ])
      '$a|$b': weightsAgree(a, b),
  };

  // Μία ή περισσότερες ζυγίσεις έξω από τα συνηθισμένα (γύρω από 82 kg τα όρια είναι 4,1 / 8,2 / 12,3 kg).
  final base = _series(18);
  const diffs = [-20.0, -12.5, -12.31, -12.3, -12.2, -8.3, -8.21, -8.2, -8.1, -4.2, -4.11, -4.1, -4.0, 4.0, 4.1, 4.11, 4.2, 8.1, 8.2, 8.21, 8.3, 12.2, 12.3, 12.31, 12.5, 20.0];
  final shapes = <String, List<int>>{
    'first': [0],
    'middle': [9],
    'middle x3': [8, 9, 10],
    'last': [17],
    'last x2': [16, 17],
    'last x3': [15, 16, 17],
    'last x4': [14, 15, 16, 17],
    'from the middle on': [9, 10, 11, 12, 13, 14, 15, 16, 17],
  };
  final status = <String, Object?>{'clean': _statuses(base)};
  for (final sh in shapes.entries) {
    for (final d in diffs) {
      status['${sh.key} $d'] = _statuses(_swap(base, {for (final i in sh.value) i: 82.0 + d}));
    }
  }
  // Κενά και λίγα δεδομένα.
  final afterGap = [
    for (var n = 0; n < 9; n++) (DateTime(2026, 11, 23 + n * 2), 82.0),
    for (var n = 0; n < 7; n++) (DateTime(2027, 1, 4 + n * 2), 76.0),
  ];
  status['76 after 3 weeks away'] = _statuses(afterGap);
  for (final gapDays in [5, 7, 8, 14, 15, 42, 43]) {
    status['74 after $gapDays days'] = _statuses([
      for (var n = 0; n < 9; n++) (DateTime(2026, 11, 23 + n * 2), 82.0),
      for (var n = 0; n < 5; n++) (DateTime(2026, 12, 9 + gapDays + n * 2), 74.0),
    ]);
  }
  status['two weigh-ins'] = _statuses([(DateTime(2026, 11, 23), 82.0), (DateTime(2026, 11, 25), 60.0)]);
  status['three neighbours'] = _statuses([
    (DateTime(2026, 11, 23), 82.0),
    (DateTime(2026, 11, 25), 82.3),
    (DateTime(2026, 11, 27), 81.9),
    (DateTime(2026, 11, 30), 60.0),
  ]);
  status['weekly'] = _statuses([for (var n = 0; n < 10; n++) (DateTime(2026, 11, 23 + n * 7), n == 6 ? 70.0 : 82.0 - n * 0.4)]);
  status['every 15 days'] = _statuses([for (var n = 0; n < 8; n++) (DateTime(2026, 11, 23 + n * 15), n == 5 ? 70.0 : 82.0)]);
  status['steady loss 1 kg/week'] = _statuses([for (var i = 0; i < 30; i++) (_mwf(i), 95.0 - _mwf(i).difference(_mwf(0)).inDays / 7)]);
  status['two people alternating'] = _statuses([for (var n = 0; n < 20; n++) (DateTime(2026, 11, 23 + n), n.isEven ? 82.0 : 61.0)]);
  out['weighStatusAt'] = status;

  // Πολλές ζυγίσεις την ίδια μέρα (ποια μετρά, και αν μετρά).
  out['guardDays'] = <String, Object?>{
    'child first every day from day 42': _guard([
      for (var n = 0; n < 42; n++) (DateTime(2026, 9, 1 + n), [80.0]),
      for (var n = 42; n < 60; n++) (DateTime(2026, 9, 1 + n), [65.0, 80.0]),
    ]),
    'mixed day in the middle': _guard([
      for (var i = 0; i < 9; i++) (_mwf(i), i == 4 ? [35.0, 82.1] : [82.0]),
    ]),
    'mixed day, own weight first': _guard([
      for (var i = 0; i < 9; i++) (_mwf(i), i == 4 ? [82.1, 35.0] : [82.0]),
    ]),
    'mixed day alone': _guard([
      (DateTime(2026, 11, 23), [82.0, 35.0]),
    ]),
    'mixed day 43 days from the rest': _guard([
      (DateTime(2026, 10, 1), [82.0, 35.0]),
      for (var i = 0; i < 6; i++) (DateTime(2026, 11, 13 + i * 2), [82.0]),
    ]),
    'mixed day 42 days from the rest': _guard([
      (DateTime(2026, 10, 2), [82.0, 35.0]),
      for (var i = 0; i < 6; i++) (DateTime(2026, 11, 13 + i * 2), [82.0]),
    ]),
    'morning and evening agree': _guard([
      for (var i = 0; i < 9; i++) (_mwf(i), i.isOdd ? [82.0, 83.4] : [82.0]),
    ]),
    'three on a day': _guard([
      for (var i = 0; i < 9; i++) (_mwf(i), i == 8 ? [70.0, 82.3, 95.0] : [82.0]),
    ]),
    'first days all mixed': _guard([
      for (var i = 0; i < 6; i++) (_mwf(i), [61.0 + i * 0.1, 82.0 - i * 0.1]),
    ]),
    'empty': _guard(const []),
  };

  // Σειρές ζυγίσεων όπως φτάνουν από τη ζυγαριά (με λίπος και μύες).
  BodyMeasurement m(int i, double kg, {double? fat, double? smm, int hour = 7, int minute = 30}) => BodyMeasurement(
      time: DateTime(_mwf(i).year, _mwf(i).month, _mwf(i).day, hour, minute), weight: kg, fatPct: fat, smm: smm, app: _inbody);
  final clean = [for (var i = 0; i < 18; i++) m(i, 84.0 - i * 0.15 + (i % 3) * 0.1, fat: 27.0 - i * 0.08, smm: 34.0 + (i % 4) * 0.05)];
  out['body'] = <String, Object?>{
    'clean 18': _bodyView(clean),
    'five days': _bodyView(clean.sublist(0, 5)),
    'six days in two weeks': _bodyView(clean.sublist(0, 6)),
    'nine days': _bodyView(clean.sublist(0, 9)),
    'empty': _bodyView(const []),
    'one': _bodyView(clean.sublist(0, 1)),
    'child on day 9': _bodyView([...clean.sublist(0, 9), m(9, 36.0, fat: 18.0), ...clean.sublist(10)]),
    'child and own weight on day 9': _bodyView([...clean.sublist(0, 10), m(9, 36.0, fat: 18.0, minute: 35), ...clean.sublist(10)]),
    'weight first, composition 5 min later': _bodyView([
      for (var i = 0; i < 12; i++) ...[
        m(i, 84.0 - i * 0.15),
        m(i, 84.1 - i * 0.15, fat: 27.0 - i * 0.1, smm: 34.2, minute: 35),
      ],
    ]),
    'composition 31 min later': _bodyView([
      for (var i = 0; i < 8; i++) ...[
        m(i, 84.0 - i * 0.15),
        m(i, 84.1 - i * 0.15, fat: 27.0 - i * 0.1, smm: 34.2, hour: 8, minute: 1),
      ],
    ]),
    'evening heavier': _bodyView([
      for (var i = 0; i < 8; i++) ...[
        m(i, 84.0 - i * 0.15, fat: 27.0),
        if (i.isEven) m(i, 85.3 - i * 0.15, fat: 26.0, hour: 21),
      ],
    ]),
    'last three 13 kg lower (pending)': _bodyView([...clean.sublist(0, 15), for (var i = 15; i < 18; i++) m(i, 70.0, fat: 20.0)]),
    'fat only on some days': _bodyView([for (var i = 0; i < 12; i++) m(i, 84.0 - i * 0.15, fat: i % 2 == 0 ? 27.0 - i * 0.1 : null)]),
    'without weight': _bodyView([
      BodyMeasurement(time: DateTime(2026, 11, 23, 8), fatPct: 27.0, app: _inbody),
      BodyMeasurement(time: DateTime(2026, 11, 25, 8), weight: double.nan, fatPct: 27.0, app: _inbody),
      BodyMeasurement(time: DateTime(2026, 11, 27, 8), weight: 84.0, fatPct: 26.5, app: _inbody),
    ]),
    'around 25/10 (25-hour day)': _bodyView([
      for (var n = 0; n < 9; n++)
        BodyMeasurement(time: DateTime(2026, 10, 19 + n, n == 6 ? 3 : 7, 30), weight: 84.0 - n * 0.1, fatPct: 27.0 - n * 0.05, app: _inbody),
    ]),
    'bodyNotPermitted(null)': bodyNotPermitted(null),
  };

  // Η τάση σε λίπος/μύες: 3 τελευταίες με 3 τουλάχιστον 14 μέρες παλιότερες.
  BodyMeasurement f(int day, double fat) => BodyMeasurement(time: DateTime(2026, 11, day, 8), weight: 90, fatPct: fat, app: _inbody);
  Object? fatTrend(List<BodyMeasurement> b) {
    final t = bodyTrend(b, (x) => x.fatPct);
    return t == null ? null : '${t.now}|${t.before}|${g141Day(t.from)}|${g141Day(t.to)}';
  }

  out['bodyTrend'] = <String, Object?>{
    'gap 14': fatTrend([f(2, 27.9), f(4, 27.5), f(6, 27.0), f(20, 26.6), f(22, 31.0), f(24, 26.3)]),
    'gap 13': fatTrend([f(2, 27.9), f(4, 27.5), f(6, 27.0), f(19, 26.6), f(22, 31.0), f(24, 26.3)]),
    'older picks the latest three': fatTrend([f(1, 29.0), f(2, 27.9), f(4, 27.5), f(6, 27.0), f(20, 26.6), f(22, 26.4), f(24, 26.3)]),
    'five': fatTrend([f(2, 27.9), f(4, 27.5), f(6, 27.0), f(20, 26.6), f(22, 26.4)]),
  };
  String shortDate(DateTime t) => '${t.day} Νοε';
  out['bodyTrendNote'] = <String, Object?>{
    for (final days in [0, 1, 5, 6, 7])
      for (final ready in <bool?>[null, false, true])
        'days=$days ready=$ready': bodyTrendNote(previous: days.isEven ? DateTime(2026, 11, 11) : null, days: days, date: shortDate, ready: ready),
    'noPermission': [bodyNoPermissionTitle, bodyNoPermissionText, bodyNoPermissionShort],
  };
  out['bodyDiffShown'] = <String, Object?>{
    for (final (d, fl) in [(0.0, 0.0), (0.0, 2.0), (1.99, 2.0), (2.0, 2.0), (-2.0, 2.0), (-1.99, 2.0), (1.69, 1.7), (1.7, 1.7), (-1.7, 1.7), (0.1, 0.0)])
      '$d|$fl': bodyDiffShown(d, fl),
  };
  String avg(List<(DateTime, double)> pts) => [for (final p in average7Days(pts)) '${g141Day(p.$1)}=${p.$2.toStringAsFixed(4)}'].join(' ');
  DateTime d0(int n) => DateTime(2026, 11, 30 + n, 7, 30);
  out['average7Days'] = <String, Object?>{
    'ten days in a row': avg([for (var n = 0; n < 10; n++) (d0(n), 90.0 + n)]),
    'gap': avg([(d0(0), 90.0), (d0(1), 90.0), (d0(2), 90.0), (d0(10), 80.0), (d0(11), 80.0)]),
    'M/W/F, one Wednesday missing': avg([for (final n in [0, 2, 4, 7, 11, 14, 16, 18]) (d0(n), 82.0 - n / 10)]),
    'two, 2 days apart': avg([(d0(0), 90.0), (d0(2), 89.0)]),
    'two, 3 days apart': avg([(d0(0), 90.0), (d0(3), 89.0)]),
    'two, 6 days apart': avg([(d0(0), 90.0), (d0(6), 89.0)]),
    'two, 7 days apart': avg([(d0(0), 90.0), (d0(7), 89.0)]),
    'empty': avg(const []),
    'across 28/3': avg([for (var n = 0; n < 9; n++) (DateTime(2027, 3, 24 + n, n.isEven ? 2 : 23, 30), 85.0 - n * 0.2)]),
    'across 25/10': avg([for (var n = 0; n < 9; n++) (DateTime(2026, 10, 21 + n, n.isEven ? 3 : 23, 30), 85.0 - n * 0.2)]),
  };

  // Μέση.
  final heights = <double?>[null, 99.0, 100.0, 180.0, 250.0, 251.0];
  out['waist'] = <String, Object?>{
    'cm': <String, Object?>{
      for (final v in const [
        [88.0],
        [88.0, 89.0],
        [88.0, 90.5],
        [88.0, 89.0, 90.0],
        [88.0, 88.4, 90.0],
        [88.0, 89.6, 90.0],
        [90.0, 88.0, 88.4],
        [88.0, 88.0, 88.0],
        [87.9, 88.0, 88.1],
      ])
        v.join('/'): WaistEntry('2026-11-27', v).cm,
    },
    'needsThird': <String, Object?>{
      for (final (a, b) in [(88.0, 88.0), (88.0, 89.0), (89.0, 88.0), (88.0, 89.0001), (88.0, 89.1), (88.5, 87.4)]) '$a|$b': needsThird(a, b),
    },
    'fromJson': <String, Object?>{
      for (final e in <String, Object?>{
        'ok': {'d': '2026-11-27', 'v': [88, 89.5]},
        'bounds': {'d': '2026-11-27', 'v': [49.9, 50, 200, 200.1]},
        'four values': {'d': '2026-11-27', 'v': [88, 89, 90, 91]},
        'none in range': {'d': '2026-11-27', 'v': [10, 300]},
        'bad day': {'d': '2026-11-31', 'v': [88]},
        'short day': {'d': '2026-1-5', 'v': [88]},
        'text values': {'d': '2026-11-27', 'v': ['88', 89]},
        'not a map': 'x',
      }.entries)
        e.key: WaistEntry.fromJson(e.value)?.toJson(),
    },
    'isDayKey': <String, Object?>{
      for (final s in ['2026-11-23', '2026-02-29', '2028-02-29', '2026-13-01', '2026-11-31', '2026-1-01', '20261123', '2026-11-23T10:00', ''])
        s: isDayKey(s),
    },
    'waistFromJson': [
      for (final e in waistFromJson([
        {'d': '2026-12-04', 'v': [88]},
        {'d': '2026-11-27', 'v': [89, 90]},
        {'d': '2026-12-04', 'v': [87.5]},
        'x',
      ]))
        e.toJson(),
    ],
    'mergeWaist': mergeWaist([
      {'d': '2026-12-04', 'v': [87.5]},
      {'d': '2026-12-11', 'v': [87]},
    ], [
      {'d': '2026-11-27', 'v': [89, 90]},
      {'d': '2026-12-04', 'v': [88]},
    ]),
    'mergeWaist junk': mergeWaist(null, 5),
    'waistRef': <String, Object?>{
      'm': [waistRef(true).ok, waistRef(true).high],
      'f': [waistRef(false).ok, waistRef(false).high],
    },
    'waistHeightText': <String, Object?>{
      for (final h in heights)
        for (final w in [71.9, 72.0, 89.9, 90.0, 90.1, 107.9, 108.0, 108.1, 50.0, 200.0])
          if (h == 180.0 || w == 90.0) '$w|$h': waistHeightText(w, h),
      for (final w in [63.9, 64.0, 79.9, 80.0, 95.9, 96.0]) '$w|160.0': waistHeightText(w, 160),
    },
  };

  // Προφίλ.
  const me = Profile(birthYear: 1985, birthMonth: 12, sex: 'm', heightCm: 180);
  Map<String, Object?> pv(Profile p) => <String, Object?>{
        'json': p.toJson(),
        'male': p.male,
        'female': p.female,
        'smokes': p.smokes,
        'quitDate': _dayOrNull(p.quitDate),
      };
  final today = DateTime(2026, 11, 23);
  out['profile'] = <String, Object?>{
    'ageOn': <String, Object?>{
      for (final d in [DateTime(2026, 11, 30), DateTime(2026, 12, 1), DateTime(2027, 1, 1), DateTime(1985, 11, 30), DateTime(1985, 12, 1), DateTime(1984, 6, 1)])
        g141Day(d): me.ageOn(d),
      'no month': const Profile(birthYear: 1985).ageOn(DateTime(2026, 1, 1)),
      'no year': const Profile(birthMonth: 5).ageOn(DateTime(2026, 1, 1)),
    },
    'packYears': <String, Object?>{
      'now 20/day from 18': me.withSmoking(smoke: 'now', cigs: 20, smokeFrom: 18).packYears(today),
      'now 35/day from 16': me.withSmoking(smoke: 'now', cigs: 35, smokeFrom: 16).packYears(today),
      'now, started after today\'s age': me.withSmoking(smoke: 'now', cigs: 20, smokeFrom: 41).packYears(today),
      'now, started at today\'s age': me.withSmoking(smoke: 'now', cigs: 20, smokeFrom: 40).packYears(today),
      'now, no start age': me.withSmoking(smoke: 'now', cigs: 20).packYears(today),
      'now, no cigs': me.withSmoking(smoke: 'now', smokeFrom: 18).packYears(today),
      'ex 10/day 20→quit 2020-06-01': me.withSmoking(smoke: 'ex', cigs: 10, smokeFrom: 20, quit: '2020-06-01').packYears(today),
      'ex, quit in December 2020': me.withSmoking(smoke: 'ex', cigs: 10, smokeFrom: 20, quit: '2020-12-01').packYears(today),
      'ex, quit in the future': me.withSmoking(smoke: 'ex', cigs: 10, smokeFrom: 20, quit: '2027-06-01').packYears(today),
      'ex, no quit day': me.withSmoking(smoke: 'ex', cigs: 10, smokeFrom: 20).packYears(today),
      'no': me.withSmoking(smoke: 'no', cigs: 20, smokeFrom: 18).packYears(today),
      'unanswered': me.packYears(today),
      'no birth year': const Profile().withSmoking(smoke: 'now', cigs: 20, smokeFrom: 18).packYears(today),
    },
    'withSmoking': <String, Object?>{
      'now': pv(me.withSmoking(smoke: 'now', cigs: 20, smokeFrom: 18, quit: '2026-11-23')),
      'ex': pv(me.withSmoking(smoke: 'ex', cigs: 15, smokeFrom: 19, quit: '2026-11-23')),
      'no': pv(me.withSmoking(smoke: 'no', cigs: 20, smokeFrom: 18, quit: '2026-11-23')),
      'cleared': pv(me.withSmoking()),
    },
    'copyWith': pv(me
        .withSmoking(smoke: 'ex', cigs: 15, smokeFrom: 19, quit: '2026-11-23')
        .copyWith(birthYear: 1982, birthMonth: 6, sex: 'f', heightCm: 165, weighDays: {2, 6}, waistDay: 7)),
    'copyWith empty weighDays': pv(me.copyWith(weighDays: <int>{})),
    'fromJson': <String, Object?>{
      for (final e in <String, Object?>{
        'not a map': 5,
        'empty': <String, dynamic>{},
        'full': {'by': 1985, 'bm': 12, 'sex': 'm', 'h': 180, 'wds': [1, 3, 5], 'wad': 5, 'smk': 'ex', 'cig': 30, 'smf': 17, 'quit': '2026-11-23'},
        'bounds low': {'by': 1899, 'bm': 0, 'sex': 'x', 'h': 99.9, 'wds': [0, 8], 'wad': 0, 'smk': 'now', 'cig': 0, 'smf': 7},
        'bounds ok low': {'by': 1900, 'bm': 1, 'sex': 'f', 'h': 100, 'wds': [7, 1], 'wad': 1, 'smk': 'now', 'cig': 1, 'smf': 8},
        'bounds ok high': {'by': 2100, 'bm': 12, 'h': 250, 'wad': 7, 'smk': 'now', 'cig': 80, 'smf': 80},
        'bounds high': {'by': 2101, 'bm': 13, 'h': 250.1, 'wad': 8, 'smk': 'now', 'cig': 81, 'smf': 81},
        'old wd=3': {'wd': 3},
        'old wd=5': {'wd': 5},
        'smk no keeps nothing': {'smk': 'no', 'cig': 20, 'smf': 18, 'quit': '2026-11-23'},
        'now with quit': {'smk': 'now', 'cig': 20, 'smf': 18, 'quit': '2026-11-23'},
        'ex bad quit': {'smk': 'ex', 'cig': 20, 'smf': 18, 'quit': '2026-02-30'},
        'smk unknown': {'smk': 'maybe', 'cig': 20},
        'text numbers': {'by': '1985', 'h': '180'},
      }.entries)
        e.key: pv(Profile.fromJson(e.value)),
    },
    'names': <String, Object?>{'weekdayNames': weekdayNames, 'weekdayChips': weekdayChips, 'monthNames': monthNames},
  };
  return out;
}

void main() {
  test('golden141 · στόχοι (οδηγός σε πλέγμα, αποθήκευση, κείμενα)', () => runGolden('energy_goals', _goalsGolden));
  test('golden141 · εκτίμηση ενέργειας (συναρτήσεις και όρια)', () => runGolden('energy_adaptive', _adaptiveGolden));
  test('golden141 · εβδομαδιαίος έλεγχος (20 συνθετικές σειρές)', () => runGolden('energy_checkin', _checkinGolden));
  test('golden141 · ζυγίσεις, τάση σώματος, μέση, προφίλ', () => runGolden('energy_body', _bodyGolden));
}
