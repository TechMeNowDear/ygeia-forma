/// «Αναφορά για έλεγχο» (αίτημα χρήστη 12/11): ένα αρχείο με ό,τι έχει γράψει η εφαρμογή ΚΑΙ ό,τι υπολόγισε από αυτό,
/// ώστε να ελέγχεται από έξω αν οι υπολογισμοί είναι σωστοί και αν κάτι δεν γράφτηκε. Ο χρήστης το στέλνει ο ίδιος
/// (κοινοποίηση)· η εφαρμογή δεν το ανεβάζει πουθενά.
///
/// Περιέχει δεδομένα υγείας: ΠΟΤΕ σε δημόσιο repo ή σε δοκιμές. Δεν περιέχει κλειδιά ή tokens (αυτά δεν είναι στις
/// ρυθμίσεις· φιλτράρονται κι όμως, για σιγουριά).
///
/// Τρία μέρη:
/// - «data»: τα αποθηκευμένα (όπως το αντίγραφο ασφαλείας) + ό,τι διαβάστηκε από τη Samsung (ζυγίσεις, βήματα, νύχτες)
///   και το ημερήσιο ιστορικό.
/// - «calc»: οι υπολογισμοί όπως τους βλέπει ο χρήστης στις οθόνες (στόχοι, θερμίδες ανά μέρα, χοληστερίνη, ζώνη,
///   διόρθωση θερμίδων) με τα ενδιάμεσα νούμερα.
/// - «checks»: αυτόματοι έλεγχοι συνέπειας (π.χ. καταχώριση με 0 g, ζύγιση που πηδά 3 kg σε μία μέρα).
library;

import 'dart:convert';

import 'adaptive.dart';
import 'adaptive_check.dart';
import 'data.dart';
import 'error_report.dart';
import 'food/chol.dart';
import 'food/food_model.dart';
import 'food/food_store.dart';
import 'format.dart' show daysBetween;
import 'goals.dart';
import 'history.dart' show dateKey;
import 'training/training_store.dart';

const diagnosticsVersion = 1;

/// Πόσες μέρες πίσω μπαίνουν τα ανά μέρα (φαγητό, ιστορικό, βήματα).
const diagnosticsDays = 60;

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
double _r(double v, [int digits = 2]) => double.parse(v.toStringAsFixed(digits));
String _iso(DateTime d) => d.toIso8601String();

/// «ygeia-elegxos-2026-11-12-1710.json.gz»
String diagnosticsFileName(DateTime now) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'ygeia-elegxos-${now.year}-${two(now.month)}-${two(now.day)}-${two(now.hour)}${two(now.minute)}.json.gz';
}

Map<String, dynamic> _withoutSecrets(Map<String, dynamic> m) => {
      for (final e in m.entries)
        if (!RegExp('token|secret|password|key', caseSensitive: false).hasMatch(e.key)) e.key: e.value,
    };

/// Η αναφορά. [screen]: μέγεθος οθόνης, γράμματα, θέμα (από τη σελίδα που τη ζητά). [note]: ό,τι έγραψε ο χρήστης.
Future<Map<String, dynamic>> buildDiagnostics({
  required HealthStore store,
  required FoodStore food,
  required TrainingStore training,
  required DateTime now,
  Map<String, Object?> screen = const {},
  String note = '',
  ErrorReporter? reporter,
}) async {
  final raw = await food.exportRaw();
  Map<String, dynamic>? trainingJson;
  try {
    await training.load();
    if (training.ready && !training.readError) trainingJson = await training.backupJson();
  } catch (_) {}
  final sources = await store.sourcesForBackup();
  return diagnosticsFrom(
    store: store,
    food: food,
    now: now,
    foodLog: raw?.$1,
    myFoods: raw?.$2,
    training: trainingJson,
    trainingReadError: training.readError,
    sources: sources,
    screen: screen,
    note: note,
    reporter: reporter,
  );
}

/// Το ίδιο, με ό,τι διαβάζεται ασύγχρονα ήδη έτοιμο (για τις δοκιμές).
Map<String, dynamic> diagnosticsFrom({
  required HealthStore store,
  required FoodStore food,
  required DateTime now,
  List<Map<String, dynamic>>? foodLog,
  List<Map<String, dynamic>>? myFoods,
  Map<String, dynamic>? training,
  bool trainingReadError = false,
  ({String plan, String? log})? sources,
  Map<String, Object?> screen = const {},
  String note = '',
  ErrorReporter? reporter,
}) {
  final today = _day(now);
  final from = DateTime(today.year, today.month, today.day - diagnosticsDays);
  final d = store.data;
  final g = store.goals;
  final weights = d == null ? <(DateTime, double)>[] : dailyWeights(d.body);
  Map<DateTime, double> intake(DateTime a, DateTime b) => dailyIntake(food, a, b);

  // ---------------------------------------------------------------- data
  final samsung = d == null
      ? null
      : {
          'readAt': _iso(d.readAt),
          'granted': d.granted,
          'total': d.total,
          'failed': d.failed.toList(),
          'bodyOk': d.bodyOk,
          'body': [
            for (final b in d.body)
              if (!b.time.isBefore(DateTime(today.year - 1, today.month, today.day)))
                {
                  't': _iso(b.time),
                  if (b.weight != null) 'kg': b.weight,
                  if (b.fatPct != null) 'fatPct': b.fatPct,
                  if (b.smm != null) 'smm': b.smm,
                  if (b.ffm != null) 'ffm': b.ffm,
                  if (b.water != null) 'water': b.water,
                  if (b.bmr != null) 'bmr': b.bmr,
                  'app': b.app,
                },
          ],
          'steps': [
            for (final s in d.steps)
              if (!s.day.isBefore(from)) [dateKey(s.day), s.value],
          ],
          'nights': [
            for (final n in d.nights)
              if (!n.date.isBefore(from))
                {'d': dateKey(n.date), 'start': _iso(n.start), 'end': _iso(n.end), 'min': n.minutes, 'stages': n.stageMinutes},
          ],
          'activityDaily': [
            for (final a in d.activityDaily)
              if (!a.$1.isBefore(from)) [dateKey(a.$1), a.$2, a.$3],
          ],
        };

  final history = {
    for (final e in store.history.entries)
      if (e.key.compareTo(dateKey(from)) >= 0) e.key: e.value,
  };

  // ---------------------------------------------------------------- calc
  Map<String, dynamic>? goalsCalc;
  if (g != null) {
    final c = g.calc;
    goalsCalc = {
      'stored': g.toJson(),
      'formula': {
        'bmr': _r(c.bmr, 1),
        'tdee': _r(c.tdee, 1),
        'delta': _r(c.delta, 1),
        'kcal': c.kcal,
        'floored': c.floored,
        'protein': c.protein,
        'fat': [c.fatLo, c.fatHi],
        'satMax': c.satMax,
        'satPct': c.satPct,
        'fiber': c.fiber,
        'salt': c.salt,
        'carbsEst': c.carbsEst,
      },
      'inForce': {
        'kcal': g.kcal,
        'source': g.kcalSet != null ? 'user' : (g.kcalAdapt != null ? 'adaptive' : 'formula'),
        'protein': g.protein,
        'fat': [g.fatLo, g.fatHi],
        'satMax': g.satMax,
      },
    };
  }

  final days = <Map<String, dynamic>>[];
  final cholDays = <(DateTime, CholDay)>[];
  for (var day = from; !day.isAfter(today); day = DateTime(day.year, day.month, day.day + 1)) {
    final entries = food.entriesFor(day);
    if (entries.isEmpty) continue;
    final t = Totals(entries);
    final ch = CholDay(entries);
    cholDays.add((day, ch));
    days.add({
      'd': dateKey(day),
      'entries': entries.length,
      'kcal': _r(t.kcal, 1),
      'shownKcal': t.shownKcal,
      'protein': _r(t.protein, 1),
      'carbs': _r(t.carbs, 1),
      'fat': _r(t.fat, 1),
      'satFat': _r(t.satFat, 1),
      'fiber': _r(t.fiber, 1),
      'sugars': _r(t.sugars, 1),
      'salt': _r(t.salt, 2),
      'alcohol': _r(t.alcohol, 1),
      if (t.missing.isNotEmpty) 'missing': t.missing,
      if (ch.satPct != null) 'satPct': _r(ch.satPct!, 1),
      'chol': {'nutsG': _r(ch.nutsG, 0), 'branG': _r(ch.branG, 0), 'legumesDryG': _r(ch.legumesDryG, 0), 'fishG': _r(ch.fishG, 0)},
      if (g != null) 'goalKcal': g.kcal,
      if (g != null) 'countsForAdaptive': t.kcal >= adaptFullDayShare * g.kcal,
    });
  }

  Map<String, dynamic>? adaptive;
  if (g != null) {
    final pending = pendingCheckIn(goals: g, today: today, weights: weights, intake: intake);
    final ready = readiness(goals: g, today: today, weights: weights, intake: intake);
    final to = DateTime(today.year, today.month, today.day - 1);
    final windowFrom = DateTime(to.year, to.month, to.day - (adaptWindowDays - 1));
    // Η εκτίμηση ΤΩΡΑ (όποια μέρα κι αν είναι), για έλεγχο· στην εφαρμογή φαίνεται μόνο τη μέρα ελέγχου.
    final probe = estimateExpenditure(
        intake: intake(windowFrom, to), weights: weights, today: today, formulaTdee: g.calc.tdee, goalKcal: g.kcal);
    final w14 = [for (final w in weights) if (!w.$1.isBefore(DateTime(today.year, today.month, today.day - 14))) w];
    final w21 = [for (final w in weights) if (!w.$1.isBefore(windowFrom) && !w.$1.isAfter(to)) w];
    adaptive = {
      'since': g.since,
      'firstCheck': dateKey(firstCheckDay(g)),
      'nextCheck': dateKey(nextCheckDay(g, today)),
      'due': checkInDue(goals: g, today: today, lastCheckIn: g.checkIn),
      'pending': pending == null
          ? null
          : {
              'kind': pending.kind.name,
              'status': pending.status?.name,
              'days': pending.days,
              'weighs': pending.weighs,
              if (pending.proposal != null)
                'proposal': {
                  'current': pending.proposal!.current,
                  'target': pending.proposal!.target,
                  'change': pending.proposal!.change,
                  'floored': pending.proposal!.floored,
                  'fastLoss': pending.proposal!.fastLoss,
                },
              'wanted': pending.wanted,
              'kgNow': pending.kgNow,
              'fastSlopeKgWeek': pending.fastSlope == null ? null : _r(pending.fastSlope!, 3),
            },
      'readiness': {'intakeDays': ready.intakeDays, 'weighIns': ready.weighIns, 'first': dateKey(ready.first)},
      'probe': {
        'window': [dateKey(windowFrom), dateKey(to)],
        'status': probe.status.name,
        if (probe.est != null)
          'est': {
            'tdee': _r(probe.est!.tdee, 1),
            'meanIntake': _r(probe.est!.meanIntake, 1),
            'slopeKgWeek': _r(probe.est!.slopeKgWeek, 3),
            'intakeDays': probe.est!.intakeDays,
            'weighIns': probe.est!.weighIns,
          },
        'formulaTdee': _r(g.calc.tdee, 1),
        'plausibleBand': [_r(0.7 * g.calc.tdee, 0), _r(1.4 * g.calc.tdee, 0)],
      },
      'slopeKgWeek14': w14.length < 2 ? null : _r((weightSlope(w14) ?? 0) * 7, 3),
      'slopeKgWeek21': w21.length < 2 ? null : _r((weightSlope(w21) ?? 0) * 7, 3),
      'weightsUsed': [for (final w in weights) if (!w.$1.isBefore(from)) [dateKey(w.$1), w.$2]],
    };
  }

  Map<String, dynamic>? chol;
  if (g != null && g.doctor) {
    final ws = weekStart(today);
    final week = CholWeek([for (final c in cholDays) if (!c.$1.isBefore(ws) && c.$1.isBefore(today)) c]);
    chol = {
      'weekStart': dateKey(ws),
      'fullDays': week.fullDays,
      'satPctMean': week.satPctMean == null ? null : _r(week.satPctMean!, 1),
      'fiberMean': week.fiberMean == null ? null : _r(week.fiberMean!, 1),
      'daysWithNuts': week.daysWithNuts(g.nutsG),
      'daysWithBran': week.daysWithBran(g.branG),
      'daysSaltOk': week.daysSaltOk(g.salt),
      'legumes': week.legumes,
      'fish': week.fish,
      'targets': {'nutsG': g.nutsG, 'branG': g.branG, 'legumesWeek': g.legumesWeek, 'fishWeek': g.fishWeek, 'doctor': g.docTargets.toJson()},
    };
  }

  final z = store.zoneOn(now);
  final zone = {
    'settings': store.zoneSettings.toJson(),
    'restHrUsed': store.restHrForZone(now),
    'age': store.profile.ageOn(now),
    if (z != null) 'zone': {'lo': z.lo, 'hi': z.hi, 'rest': z.rest, 'max': z.max, 'maxMeasured': z.maxMeasured, 'manual': z.manual},
  };

  // ---------------------------------------------------------------- checks
  final checks = <Map<String, Object?>>[];
  void check(String id, bool ok, [String? detail]) => checks.add({'id': id, 'ok': ok, if (detail != null) 'detail': detail});

  check('prefs-read', store.prefsReady);
  check('history-read', store.historyReady);
  check('food-read', food.loaded && food.error == null, food.error);
  check('food-save', food.saveError == null, food.saveError);
  check('training-read', !trainingReadError);
  check('samsung-read', d != null && d.failed.isEmpty, d == null ? 'καμία ανάγνωση' : (d.failed.isEmpty ? null : d.failed.join(',')));

  final badGrams = <String>[];
  final noKcal = <String>[];
  final atwater = <String>{};
  final dup = <String>[];
  final seen = <String>{};
  for (var day = from; !day.isAfter(today); day = DateTime(day.year, day.month, day.day + 1)) {
    for (final e in food.entriesFor(day)) {
      if (!e.grams.isFinite || e.grams <= 0 || e.grams > 3000) badGrams.add('${e.day} ${e.food.name} ${e.grams}');
      if (!e.food.n.has(Nk.kcal)) noKcal.add('${e.day} ${e.food.name}');
      // Atwater (4/4/9 + ίνες 2 + αλκοόλ 7) ±20% και ±20 kcal: ετικέτα ή βάση με λάθος ενέργεια.
      final n = e.food.n;
      final calc = 4 * n.amount(Nk.protein) + 4 * n.amount(Nk.carbs) + 9 * n.amount(Nk.fat) + 2 * n.amount(Nk.fiber) + 7 * n.amount(Nk.alcohol);
      final kcal = n.amount(Nk.kcal);
      if (n.has(Nk.kcal) && n.has(Nk.protein) && n.has(Nk.carbs) && n.has(Nk.fat) && (kcal - calc).abs() > 20 && (kcal - calc).abs() > 0.2 * kcal) {
        atwater.add('${e.food.id} ${e.food.name}: ${_r(kcal, 0)} kcal, από τα μακροθρεπτικά ${_r(calc, 0)}');
      }
      final sig = '${e.day}|${e.food.id}|${e.grams}|${e.meal.name}|${e.time.hour}:${e.time.minute}';
      if (!seen.add(sig)) dup.add(sig);
    }
  }
  check('food-grams', badGrams.isEmpty, badGrams.isEmpty ? null : badGrams.take(20).join('; '));
  check('food-has-kcal', noKcal.isEmpty, noKcal.isEmpty ? null : noKcal.take(20).join('; '));
  check('food-atwater', atwater.isEmpty, atwater.isEmpty ? null : atwater.take(20).join('; '));
  check('food-duplicates', dup.isEmpty, dup.isEmpty ? null : dup.take(20).join('; '));

  final jumps = <String>[];
  for (var i = 1; i < weights.length; i++) {
    final a = weights[i - 1], b = weights[i];
    final gap = daysBetween(a.$1, b.$1);
    if (gap > 0 && gap <= 7 && (b.$2 - a.$2).abs() > 1.5 * gap.clamp(1, 2)) jumps.add('${dateKey(a.$1)}→${dateKey(b.$1)}: ${a.$2}→${b.$2}');
  }
  check('weight-jumps', jumps.isEmpty, jumps.isEmpty ? null : jumps.take(10).join('; '));
  if (g != null) {
    check('goals-floor', g.kcal >= (g.male ? kcalFloorMale : kcalFloorFemale), '${g.kcal}');
    final latest = weights.isEmpty ? null : weights.last.$2;
    check('goals-weight-fresh', latest == null || (latest - g.kg).abs() < 3,
        latest == null ? 'καμία ζύγιση' : 'στόχοι με ${g.kg} kg, τελευταία ζύγιση $latest kg');
  }

  return {
    'app': 'ygeia-forma',
    'kind': 'diagnostics',
    'v': diagnosticsVersion,
    'created': _iso(now),
    'tz': now.timeZoneName,
    'tzOffsetMin': now.timeZoneOffset.inMinutes,
    'release': reporter?.release,
    'device': reporter?.device,
    'screen': screen,
    'note': note,
    'data': {
      'foodLogSource': foodLog == null ? 'memory-${diagnosticsDays}d' : 'file',
      'prefs': store.prefsReady ? _withoutSecrets(store.prefsJson()) : null,
      'profile': {
        'birthYear': store.profile.birthYear,
        'birthMonth': store.profile.birthMonth,
        'sex': store.profile.sex,
        'heightCm': store.profile.heightCm,
        'weighDays': store.profile.weighDays.toList()..sort(),
        'waistDay': store.profile.waistDay,
      },
      // Αν δεν διαβάστηκε το αρχείο του ημερολογίου, ό,τι υπάρχει στη μνήμη (τις τελευταίες μέρες).
      'foodLog': foodLog ??
          [
            for (var day = from; !day.isAfter(today); day = DateTime(day.year, day.month, day.day + 1))
              for (final e in food.entriesFor(day)) e.toJson(),
          ],
      'myFoods': myFoods,
      'training': training,
      'sources': sources == null ? null : {'plan': _tryJson(sources.plan), 'log': sources.log == null ? null : _tryJson(sources.log!)},
      'waist': [for (final w in store.waist) w.toJson()],
      'samsung': samsung,
      'history': history,
    },
    'calc': {
      'goals': goalsCalc,
      'days': days,
      'adaptive': adaptive,
      'chol': chol,
      'zone': zone,
    },
    'checks': checks,
    'errors': reporter == null ? const [] : List.of(reporter.recentErrors),
    'screens': reporter?.screen,
  };
}

Object? _tryJson(String s) {
  try {
    return jsonDecode(s);
  } catch (_) {
    return s;
  }
}
