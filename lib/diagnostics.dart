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
import 'ai/ai_bridge.dart' show AiBridge;
import 'adaptive_check.dart';
import 'body_trend.dart'
    show bodyFloorFatPct, bodyFloorKg, bodyTrend, bodyTrendGapDays, bodyTrendGroup, guardBody, previousCounted;
import 'data.dart';
import 'error_report.dart';
import 'food/chol.dart';
import 'food/food_model.dart';
import 'food/food_store.dart';
import 'food/off.dart' show impossibleValues;
import 'format.dart' show daysBetween;
import 'goals.dart';
import 'history.dart' show K, dateKey;
import 'home_widgets/widget_snapshot.dart' show buildWidgetSnapshot;
import 'home_widgets/widget_style.dart' show WKind;
import 'hrv_trend.dart';
import 'pages/nutrition_goals.dart' show beforeGoals, satVerdict;
import 'sources.dart' show Source, definitionMetrics;
import 'training/training_store.dart';
import 'vitals.dart' show VitalsStore, bpAverage, bpMinDays, bpMinReadings;
import 'weekly.dart' show buildWeekReview, reviewWeekSunday;

/// Έλεγχος 21/11 (K8-15): 2 = νέα σειρά κλειδιών (στοιχεία αρχείου → checks → errors → calc → shown → data), κάρτα ελέγχου
/// όπως στην οθόνη, πίεση/σάκχαρο, «shown», σταθερές κανόνων, ώρες και σε ms. Ανεβαίνει σε ΚΑΘΕ αλλαγή μορφής (πριν έμενε 1
/// ενώ η μορφή άλλαξε πολλές φορές).
const diagnosticsVersion = 2;

/// Πόσες μέρες πίσω μπαίνουν τα ανά μέρα (φαγητό, ιστορικό, βήματα).
const diagnosticsDays = 60;

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
double _r(double v, [int digits = 2]) => double.parse(v.toStringAsFixed(digits));
String _iso(DateTime d) => d.toIso8601String();

/// Έλεγχος 21/11: στρογγύλεμα για τα νέα πεδία που δεν σπάει το JSON: τιμή που λείπει ή δεν είναι αριθμός (NaN, άπειρο)
/// γράφεται null (το `jsonEncode` πετά σφάλμα σε NaN).
double? _n(double? v, [int digits = 2]) => v == null || !v.isFinite ? null : _r(v, digits);

String _stamp(DateTime now) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}-${two(now.hour)}${two(now.minute)}';
}

/// «ygeia-elegxos-2026-11-12-1710.json.gz»
String diagnosticsFileName(DateTime now) => 'ygeia-elegxos-${_stamp(now)}.json.gz';

/// Έλεγχος 21/11 (K8-08): «ygeia-elegxos-2026-11-12-1710-synopsi.json»: η σύνοψη, ΑΣΥΜΠΙΕΣΤΗ (απλό κείμενο JSON, για να
/// διαβάζεται από μοντέλο σε συζήτηση· το Android τη γράφει ως application/json επειδή το όνομα δεν τελειώνει σε «.gz»).
String diagnosticsSummaryFileName(DateTime now) => 'ygeia-elegxos-${_stamp(now)}-synopsi.json';

/// Ρυθμίσεις που μένουν ΜΟΝΟ στο κινητό και δεν μπαίνουν σε κανένα αρχείο που φεύγει από αυτό. Έλεγχος 13/11 (S9-6): το
/// όνομα για την αναφορά γιατρού ([Prefs.reportName]) έμπαινε στην «Αναφορά για έλεγχο», δίπλα σε όλα τα δεδομένα
/// υγείας, ενώ δεν μπαίνει ούτε στο αντίγραφο ασφαλείας ούτε στο αντίγραφο Google. Το αρχείο μένει χωρίς όνομα.
const diagnosticsDeviceOnlyPrefs = {'reportName'};

bool _secretKey(String k) =>
    diagnosticsDeviceOnlyPrefs.contains(k) || RegExp('token|secret|password|key', caseSensitive: false).hasMatch(k);

Map<String, dynamic> _withoutSecrets(Map<String, dynamic> m) => {
      for (final e in m.entries)
        if (!_secretKey(e.key)) e.key: e.value,
    };

/// K8-R-07 (ανεξάρτητος έλεγχος): το ιστορικό ελέγχων κρατά πια και το βάρος κάθε ελέγχου («kg») για ως [adaptLogMax]
/// ελέγχους (περίπου 6 μήνες). Η αναφορά λέει «από Samsung και Oura τις τελευταίες 60 μέρες» (R8-A11-3: οι ζυγίσεις
/// κόπηκαν εκεί ακριβώς γι' αυτό): σε γραμμές πριν από την πρώτη μέρα της αναφοράς [fromKey] το βάρος δεν γράφεται.
Map<String, dynamic> _goalsForReport(Map<String, dynamic> goals, String fromKey) {
  final log = goals['log'];
  if (log is! List) return goals;
  return {
    ...goals,
    'log': [
      for (final x in log)
        if (x is Map && x['d'] is String && (x['d'] as String).compareTo(fromKey) < 0)
          {
            for (final e in x.entries)
              if (e.key != 'kg') '${e.key}': e.value,
          }
        else
          x,
    ],
  };
}

Map<String, dynamic> _prefsForReport(Map<String, dynamic> prefs, String fromKey) {
  final goals = prefs['goals'];
  if (goals is! Map) return prefs;
  return {...prefs, 'goals': _goalsForReport(Map<String, dynamic>.from(goals), fromKey)};
}

/// K8-R-13 (ανεξάρτητος έλεγχος): το `jsonEncode` πετά σφάλμα σε NaN/άπειρο, και τότε δεν βγαίνει ΚΑΘΟΛΟΥ αναφορά, ακριβώς
/// όταν χρειάζεται (μια καταχώριση με άπειρα γραμμάρια είναι αυτό που ψάχνουν οι έλεγχοι «food-grams»/«food-values»). Με
/// αυτό ως `toEncodable` ο μη πεπερασμένος αριθμός γράφεται null και ό,τι άλλο δεν γράφεται σε JSON γίνεται κείμενο.
///
/// K8-R-24: με δικό μας `toEncodable` το `jsonEncode` δεν καλεί πια μόνο του το `toJson()` ενός αντικειμένου· το καλούμε
/// εδώ πρώτα, αλλιώς ένα αντικείμενο με `toJson()` θα γραφόταν σιωπηλά «Instance of …».
Object? diagnosticsEncodable(Object? o) {
  if (o is num) return null;
  try {
    return (o as dynamic).toJson();
  } catch (_) {
    return '$o';
  }
}

/// Η αναφορά (ή η σύνοψη) ως κείμενο JSON, χωρίς να σπάει σε μη πεπερασμένο αριθμό.
String diagnosticsEncode(Object? report) => jsonEncode(report, toEncodable: diagnosticsEncodable);

/// Έλεγχος 21/11 (K8-14): ΤΑ ΟΝΟΜΑΤΑ (ποτέ οι τιμές) των ρυθμίσεων που δεν μπήκαν στην αναφορά. Πριν το φίλτρο τις
/// πετούσε αθόρυβα: ένα μελλοντικό κλειδί με «key» στο όνομα θα χανόταν χωρίς ίχνος.
List<String> _droppedKeys(Map<String, dynamic> m) => [
      for (final k in m.keys)
        if (_secretKey(k)) k,
    ];

/// Έλεγχος 21/11 (K8-01): η εκτίμηση κατανάλωσης όπως γράφεται στο «probe.est», και με το παράθυρό της.
Map<String, dynamic> _estJson(Expenditure e) => {
      'tdee': _r(e.tdee, 1),
      'meanIntake': _r(e.meanIntake, 1),
      'slopeKgWeek': _r(e.slopeKgWeek, 3),
      'intakeDays': e.intakeDays,
      'weighIns': e.weighIns,
      'windowDays': e.windowDays,
      'seKcal': _r(e.seKcal, 1),
      'guardKcal': _r(e.guardKcal, 1),
    };

/// Έλεγχος 21/11 (K8-01): ΟΛΑ τα πεδία της κάρτας ελέγχου ([CheckIn]) όπως τα είδε ο χρήστης. Πριν γράφονταν 8 από τα 23:
/// δεν φαινόταν ποιον από τους πέντε λόγους «ο στόχος μένει ίδιος» έγραψε η κάρτα (περιθώριο θορύβου, γρήγορη απώλεια,
/// αλλαγή πριν από λίγες μέρες, κάπνισμα, οι 3 τελευταίες εβδομάδες), ούτε το κενό καταγραφής, οι μέρες με αδύνατα πολλές
/// θερμίδες, οι ξένες ζυγίσεις και το «Χ% εκτίμηση». [estShare]: [checkInEstShare]. Κάθε κλειδί γράφεται πάντα (null όταν
/// δεν ισχύει), εκτός από τα παλιά «proposal», «quitHoldDays» και «formulaKg» που γράφονται μόνο όταν υπάρχουν, όπως πριν.
///
/// [oldWeights] (K8-R-12): η τελευταία ζύγιση είναι παλιότερη από τις μέρες της αναφοράς· τότε το βάρος της κάρτας και
/// το βάρος του τύπου δεν γράφονται (η αναφορά έχει από τη Samsung μόνο τις τελευταίες [diagnosticsDays] μέρες).
Map<String, dynamic> checkInJson(CheckIn c, {double? estShare, bool oldWeights = false}) {
  final p = c.proposal;
  final e = c.est;
  final gap = c.gap;
  final restart = gap?.restart;
  return {
    'kind': c.kind.name,
    'status': c.status?.name,
    'days': c.days,
    'weighs': c.weighs,
    if (p != null)
      'proposal': {
        'current': p.current,
        'target': p.target,
        'change': p.change,
        'floored': p.floored,
        'fastLoss': p.fastLoss,
        // Έλεγχος 20/11 (K1-C-02, K1-S-05): γράφονται μόνο όταν ισχύουν.
        if (p.recentDiffers) 'recentDiffers': true,
        if (p.underweight) 'underweight': true,
      },
    'wanted': c.wanted,
    if (c.quitDays != null) 'quitHoldDays': c.quitDays,
    'kgNow': oldWeights ? null : c.kgNow,
    'fastSlopeKgWeek': _n(c.fastSlope, 3),
    // ---- Έλεγχος 21/11 (K8-01): τα υπόλοιπα πεδία της κάρτας.
    'goalKcal': c.goals.kcal,
    'formulaTdee': _n(c.formulaTdee, 1),
    if (c.formulaKg != null && !oldWeights) 'formulaKg': c.formulaKg,
    'tooFast': c.tooFast,
    'heldDays': c.heldDays,
    'lowLog': c.lowLog,
    'withinNoise': p?.withinNoise ?? false,
    'gap': gap == null ? null : [dateKey(gap.from), dateKey(gap.to), restart == null ? null : dateKey(restart)],
    'absurd': [
      for (final (day, kcal) in c.absurd) [dateKey(day), _n(kcal, 1)],
    ],
    'foreign': [
      for (final (day, kg) in c.foreign) [dateKey(day), kg],
    ],
    'fastDays': c.fastDays,
    'fastFrom': c.fastFrom == null ? null : dateKey(c.fastFrom!),
    'fastIntake': _n(c.fastIntake, 1),
    'fastIntakeDays': c.fastIntakeDays,
    'fastTarget': _n(c.fastTarget, 1),
    'estTarget': _n(c.estTarget, 1),
    'est': e == null ? null : {..._estJson(e), 'from': dateKey(e.from), 'to': dateKey(e.to)},
    'estShare': _n(estShare, 4),
  };
}

/// Η αναφορά. [screen]: μέγεθος οθόνης, γράμματα, θέμα (από τη σελίδα που τη ζητά). [note]: ό,τι έγραψε ο χρήστης.
Future<Map<String, dynamic>> buildDiagnostics({
  required HealthStore store,
  required FoodStore food,
  required TrainingStore training,
  required DateTime now,
  Map<String, Object?> screen = const {},
  Map<String, Object?> rest = const {},
  String note = '',
  ErrorReporter? reporter,
  VitalsStore? vitals,
}) async {
  final raw = await food.exportRaw();
  Map<String, dynamic>? trainingJson;
  try {
    await training.load();
    if (training.ready && !training.readError) trainingJson = await training.backupJson();
  } catch (_) {}
  final sources = await store.sourcesForBackup();
  // Έλεγχος 21/11 (K8-03): πίεση, σάκχαρο, καρδιογραφήματα· περιμένει να διαβαστεί το αρχείο τους, όπως η εξαγωγή
  // αντιγράφου. [vitals]: άλλο από του κινητού δίνουν μόνο οι δοκιμές (το [VitalsStore.main] εκεί δεν τελειώνει ποτέ).
  final vitalsStore = vitals ?? VitalsStore.main;
  try {
    await vitalsStore.ensureLoaded();
  } catch (_) {}
  // Έλεγχος 21/11 (K8-12): πόσα σφάλματα περιμένουν να σταλούν (μόνο ο αριθμός).
  int? errorsPending;
  try {
    errorsPending = await reporter?.pending();
  } catch (_) {}
  return diagnosticsFrom(
    store: store,
    food: food,
    now: now,
    foodLog: raw?.$1,
    myFoods: raw?.$2,
    training: trainingJson,
    trainingReadError: training.readError,
    trainingStore: training,
    vitals: vitalsStore,
    errorsPending: errorsPending,
    sources: sources,
    screen: screen,
    rest: rest,
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
  TrainingStore? trainingStore,
  VitalsStore? vitals,
  int? errorsPending,
  ({String plan, String? log})? sources,
  Map<String, Object?> screen = const {},
  Map<String, Object?> rest = const {},
  String note = '',
  ErrorReporter? reporter,
}) {
  final today = _day(now);
  final from = DateTime(today.year, today.month, today.day - diagnosticsDays);
  final d = store.data;
  final g = store.goals;
  final weights = d == null ? <(DateTime, double)>[] : dailyWeights(d.body);
  // K8-R-12: η τελευταία ζύγιση είναι πριν από τις μέρες της αναφοράς· τότε η τιμή της δεν γράφεται πουθενά.
  final weightsOld = weights.isNotEmpty && weights.last.$1.isBefore(from);
  Map<DateTime, double> intake(DateTime a, DateTime b) => dailyIntake(food, a, b);
  // Κ1-L6 (17/11): ο τύπος με το τωρινό βάρος, όπως ο έλεγχος θερμίδων ([formulaNow]).
  final fNow = g == null ? null : formulaNow(g, weights);

  // ---------------------------------------------------------------- data
  final samsung = d == null
      ? null
      : {
          'readAt': _iso(d.readAt),
          // Έλεγχος 21/11 (K8-13): κάθε ώρα και σε ms από την εποχή Unix. Οι ώρες χωρίς ζώνη δεν ξεχωρίζουν την
          // ώρα που επαναλαμβάνεται όταν γυρίζουν πίσω τα ρολόγια, και το «tzOffsetMin» είναι μόνο της στιγμής της αναφοράς.
          'readAtMs': d.readAt.millisecondsSinceEpoch,
          'granted': d.granted,
          'total': d.total,
          'failed': d.failed.toList(),
          'bodyOk': d.bodyOk,
          // Round 8 (R8-A11-3): οι ζυγίσεις των τελευταίων [diagnosticsDays] ημερών, όπως όλα τα άλλα της Samsung και της
          // Oura (και όπως λέει η πολιτική απορρήτου)· πριν έμπαινε ένας ολόκληρος χρόνος. Κάθε υπολογισμός της αναφοράς
          // κοιτά ως 53 μέρες πίσω ([adaptScanDays]), μέσα στις [diagnosticsDays].
          'body': [
            for (final b in d.body)
              if (!b.time.isBefore(from))
                {
                  't': _iso(b.time),
                  'ms': b.time.millisecondsSinceEpoch,
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
                {
                  'd': dateKey(n.date),
                  'start': _iso(n.start),
                  'end': _iso(n.end),
                  'startMs': n.start.millisecondsSinceEpoch,
                  'endMs': n.end.millisecondsSinceEpoch,
                  'min': n.minutes,
                  'stages': n.stageMinutes,
                },
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
      'stored': _goalsForReport(g.toJson(), dateKey(from)),
      'formula': {
        'bmr': _r(c.bmr, 1),
        'tdee': _r(c.tdee, 1),
        'delta': _r(c.delta, 1),
        'kcal': c.kcal,
        'floored': c.floored,
        'protein': c.protein,
        'fat': [c.fatLo, c.fatHi],
        // Round10 (R10-B1-2 / R10-B7-3): το όριο κορεσμένων όπως το γράφουν οι οθόνες ([satLimitShown], ένα δεκαδικό:
        // 2.340 kcal × 6% = 15,6 g)· πριν στρογγυλεμένο στο γραμμάριο (16), άλλο από αυτό που έβλεπε ο χρήστης.
        'satMax': satLimitShown(c.kcal, c.satPct),
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
        'satMax': satLimitShown(g.kcal, g.satPct),
      },
    };
  }

  final days = <Map<String, dynamic>>[];
  final cholDays = <(DateTime, CholDay)>[];
  // Round11 (R11-C1-1): η πρώτη μέρα που μετρά στη διόρθωση θερμίδων (η πρώτη εβδομάδα των στόχων δεν μετρά,
  // [adaptSkipDays]· όπως estimateExpenditure / pendingCheckIn). null χωρίς στόχους ή με άκυρο «since»: καμία κάτω άκρη.
  final adaptSince = g == null ? null : DateTime.tryParse(g.since);
  final adaptFirst = adaptSince == null ? null : DateTime(adaptSince.year, adaptSince.month, adaptSince.day + adaptSkipDays);
  for (var day = from; !day.isAfter(today); day = DateTime(day.year, day.month, day.day + 1)) {
    final entries = food.entriesFor(day);
    if (entries.isEmpty) continue;
    final t = Totals(entries);
    // «Λείπουν γεύματα» (16/11, έλεγχος): όπως στον έλεγχο θερμίδων, η μέρα δεν μετρά.
    final part = food.dayMark(day) == DayMark.part;
    final ch = CholDay(entries, part: part);
    cholDays.add((day, ch));
    // Round10 (R10-B1-2 / R10-B7-3): ο στόχος και το όριο κορεσμένων της μέρας όπως τα γράφει η Διατροφή
    // (GoalsSummaryCard): σήμερα ο τωρινός στόχος, μέρα που πέρασε ο στόχος που ίσχυε τότε ([targetOn], R9-A1-2), μέρα πριν
    // από τους στόχους κανένας ([beforeGoals]: εκεί η Διατροφή γράφει μόνο «Σύνολο ημέρας»). Πριν, κάθε μέρα είχε τον
    // ΤΩΡΙΝΟ στόχο.
    final goalKcal = g == null || beforeGoals(g, day) ? null : (day == today ? g.kcal : targetOn(g, day));
    // Round11 (R11-C1-2): η μπάρα «Κορεσμένα λιπαρά» της Διατροφής κρίνει μέρα που τελείωσε με πλήρη καταγραφή με το % των
    // θερμίδων που έφαγες, όχι με τα γραμμάρια του στόχου: το «sat» λέει ποιον κανόνα εφάρμοσε η οθόνη και τι έκρινε
    // ([satVerdict], η ίδια συνάρτηση με την κάρτα). Πριν η αναφορά έδινε για ΚΑΘΕ μέρα το «satLimit» (γραμμάρια) σαν όριο
    // της οθόνης, και σε τέτοιες μέρες (2.000 kcal, 14,0 g: οθόνη 6,3% «πάνω από το 6%») έβγαινε η ανάποδη ετυμηγορία.
    // Το «satLimit» μένει μόνο για τις μέρες που η οθόνη κρίνει με γραμμάρια.
    final sat = goalKcal == null || g == null ? null : satVerdict(t, g, today: day == today, day: day, part: part);
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
      if (goalKcal != null) 'goalKcal': goalKcal,
      if (sat != null && sat.pctDay == null) 'satLimit': sat.limitG,
      if (sat != null && g != null)
        'sat': sat.pctDay != null
            ? {'rule': 'pct', 'shown': _r(sat.pctDay!, 1), 'limitPct': g.satPct, 'over': sat.over}
            : {'rule': 'g', 'shown': _r(t.satFat, 1), 'limit': sat.limitG, 'over': sat.over},
      // Round11 (R11-C1-1): ο κανόνας της διόρθωσης θερμίδων για ΜΙΑ μέρα (adaptive.dart: estimateExpenditure, foodGap·
      // adaptive_check.dart: pendingCheckIn): από την 8η μέρα των στόχων ως χθες (η σημερινή δεν έχει τελειώσει), με
      // θερμίδες από το 60% του τωρινού στόχου ως το [absurdDayKcal]. Πριν έλεγχε μόνο το 60%, και η αναφορά έγραφε «μετρά»
      // για μέρες πριν από τους στόχους, για την πρώτη εβδομάδα, για σήμερα και για μέρες με αδύνατα πολλές θερμίδες, ενώ
      // το «adaptive.readiness» (σωστά) δεν τις μετρούσε. Αν η μέρα πέφτει στο παράθυρο που κρίθηκε ή μετά από κενό
      // καταγραφής φαίνεται στο «adaptive».
      if (part) 'dayMark': 'part',
      if (g != null)
        'countsForAdaptive': !part &&
            day.isBefore(today) &&
            (adaptFirst == null || !day.isBefore(adaptFirst)) &&
            t.kcal >= adaptFullDayShare * g.kcal &&
            t.kcal <= absurdDayKcal(fNow!.tdee),
    });
  }

  Map<String, dynamic>? adaptive;
  if (g != null) {
    // Έλεγχος 19/11 (L-6): με τη μέρα διακοπής του καπνίσματος, όπως η κάρτα της Σήμερα (τη δίνει το [checkInShown]).
    // Έλεγχος 21/11 (K8-01): η κάρτα από την ΙΔΙΑ συνάρτηση με τη «Σήμερα» ([checkInShown]), με τους όρους της οθόνης
    // (ημερολόγιο φορτωμένο, όχι αντίγραφο παρασκηνίου, ζυγίσεις διαβασμένες ή με σφάλμα) και όλα τα ορίσματά της (ξένες
    // ζυγίσεις, «οι ζυγίσεις δεν διαβάστηκαν»). Πριν: δική της κλήση με λιγότερα ορίσματα· με σφάλμα στις ζυγίσεις τη
    // μέρα ελέγχου έγραφε «fewData, 0 ζυγίσεις» ενώ η οθόνη έδειχνε «οι ζυγίσεις δεν διαβάστηκαν» (unread).
    final shownCard = checkInShown(store, food, now);
    final pending = shownCard.check;
    final ready = readiness(goals: g, today: today, weights: weights, intake: intake);
    final to = DateTime(today.year, today.month, today.day - 1);
    final windowFrom = DateTime(to.year, to.month, to.day - (adaptWindowDays - 1));
    // Γύρος 2 (g1 · R2-A-2): όσο πίσω ψάχνει το κενό καταγραφής, όπως ο έλεγχος της Σήμερα.
    final wideFrom = DateTime(to.year, to.month, to.day - (adaptScanDays - 1));
    final since = DateTime.tryParse(g.since);
    // Η εκτίμηση ΤΩΡΑ (όποια μέρα κι αν είναι), για έλεγχο· στην εφαρμογή φαίνεται μόνο τη μέρα ελέγχου. Με τους ίδιους
    // κανόνες (Συμβούλιο 2, Α1–Α2): χωρίς την πρώτη εβδομάδα των στόχων, στο μεγαλύτερο παράθυρο που έχει αρκετά δεδομένα.
    final probe = estimateExpenditure(
        intake: intake(wideFrom, to), weights: weights, today: today, formulaTdee: fNow!.tdee, goalKcal: g.kcal, since: since);
    // Έλεγχος 20/11 (K1-C-02, ανεξάρτητος έλεγχος): το ίδιο όριο μετά από κενό καταγραφής που κρίνει και η κάρτα
    // ([fastNotBefore])· πριν η αναφορά έδειχνε το παράθυρο χωρίς αυτό.
    final fastFrom = fastNotBefore(
        foodGap(intake: intake(wideFrom, to), today: today, formulaTdee: fNow!.tdee, goalKcal: g.kcal, since: since));
    final fastWindow = fastLossWindow(goals: g, today: today, notBefore: fastFrom);
    final fastWs = fastLossWeights(goals: g, weights: weights, today: today, notBefore: fastFrom);
    final fastFit = weightFit(fastWs);
    final w14 = [for (final w in weights) if (!w.$1.isBefore(DateTime(today.year, today.month, today.day - 14))) w];
    final w21 = [for (final w in weights) if (!w.$1.isBefore(windowFrom) && !w.$1.isAfter(to)) w];
    adaptive = {
      'since': g.since,
      'firstCheck': dateKey(firstCheckDay(g)),
      'nextCheck': dateKey(nextCheckDay(g, today)),
      'due': checkInDue(goals: g, today: today, lastCheckIn: g.checkIn),
      'cardShown': pending != null,
      'cardWhyNot': shownCard.why,
      'pending': pending == null ? null : checkInJson(pending, estShare: checkInEstShare(pending, food), oldWeights: weightsOld),
      'readiness': {'intakeDays': ready.intakeDays, 'weighIns': ready.weighIns, 'first': dateKey(ready.first)},
      'firstEstimate': dateKey(firstEstimateDay(g)),
      'probe': {
        'window': probe.est == null ? [dateKey(windowFrom), dateKey(to)] : [dateKey(probe.est!.from), dateKey(probe.est!.to)],
        'status': probe.status.name,
        if (probe.est != null) 'est': _estJson(probe.est!),
        'formulaTdee': _r(fNow!.tdee, 1),
        if (fNow!.kg != null && !weightsOld) 'formulaKg': fNow!.kg,
        'wizardTdee': _r(g.calc.tdee, 1),
        'plausibleBand': [_r(adaptLowShare * fNow!.tdee, 0), _r(adaptHighShare * fNow!.tdee, 0)],
      },
      // Η «γρήγορη απώλεια» όπως θα κρινόταν σήμερα (Συμβούλιο 2, Α3): παράθυρο, ζυγίσεις, κλίση και τυπικό σφάλμα.
      'fast': {
        'window': fastWindow == null ? null : [dateKey(fastWindow.$1), dateKey(fastWindow.$2)],
        'weighIns': fastWs.length,
        'slopeKgWeek': fastFit == null ? null : _r(fastFit.slope * 7, 3),
        'seKgWeek': fastFit?.se == null ? null : _r(fastFit!.se! * 7, 3),
      },
      'slopeKgWeek14': w14.length < 2 ? null : _r((weightSlope(w14) ?? 0) * 7, 3),
      'slopeKgWeek21': w21.length < 2 ? null : _r((weightSlope(w21) ?? 0) * 7, 3),
      'weightsUsed': [for (final w in weights) if (!w.$1.isBefore(from)) [dateKey(w.$1), w.$2]],
    };
  }

  Map<String, dynamic>? chol;
  if (g != null && g.doctor) {
    final ws = weekStart(today);
    final week = CholWeek([for (final c in cholDays) if (!c.$1.isBefore(ws) && c.$1.isBefore(today)) c], goalKcal: g.kcal);
    // Round 8 (R8-A3-2): όσπρια και ψάρι ΜΑΖΙ με σήμερα, όπως η κάρτα και η σελίδα «Χοληστερίνη» (U3b-8: ένα γεύμα που
    // έγινε έχει γίνει)· οι μέσοι όροι μένουν χωρίς σήμερα. Πριν η αναφορά έγραφε «2» εκεί που η οθόνη έδειχνε «3 / 4».
    final weekNow = [for (final c in cholDays) if (!c.$1.isBefore(ws) && !c.$1.isAfter(today)) c];
    chol = {
      'weekStart': dateKey(ws),
      'fullDays': week.fullDays,
      'satPctMean': week.satPctMean == null ? null : _r(week.satPctMean!, 1),
      'fiberMean': week.fiberMean == null ? null : _r(week.fiberMean!, 1),
      'daysWithNuts': week.daysWithNuts(g.nutsG),
      'daysWithBran': week.daysWithBran(g.branG),
      'daysSaltOk': week.daysSaltOk(g.salt),
      'daysSaltUnknown': week.daysSaltUnknown,
      'fullDayKcal': fullDayKcalFor(g.kcal).round(),
      'legumes': weekNow.where((c) => c.$2.legumes).length,
      'fish': weekNow.where((c) => c.$2.fish).length,
      'targets': {'nutsG': g.nutsG, 'branG': g.branG, 'legumesWeek': g.legumesWeek, 'fishWeek': g.fishWeek, 'doctor': g.docTargets.toJson()},
    };
  }

  final z = store.zoneOn(now);
  // Έλεγχος 21/11 (K8-08): από ποια πηγή είναι οι παλμοί ύπνου που δίνουν τους «παλμούς ηρεμίας» της ζώνης (μόνο το όνομα
  // της πηγής: «watch», «oura», «none»)· η σύνοψη αφήνει έξω τη ζώνη όταν βγαίνει από το δαχτυλίδι.
  // K8-R-11 (ανεξάρτητος έλεγχος): η πηγή της τελευταίας νύχτας που ΜΠΗΚΕ στον υπολογισμό (οι 28 τελευταίες μέρες, όχι
  // πάνω από αλλαγή πηγής, όπως το `restHrForZone`). Πριν: η πηγή της σημερινής μέρας· μετά από αποσύνδεση έγραφε «none»
  // ενώ οι παλμοί ηρεμίας έβγαιναν ακόμα από τις νύχτες του Oura.
  String restSource() {
    final p = store.analysisPlan;
    final changes = p.changeDates(K.sleepHr);
    final first = changes.isEmpty ? null : changes.last;
    for (var i = 0; i < 28; i++) {
      final x = DateTime(today.year, today.month, today.day - i);
      if (first != null && x.isBefore(first)) break;
      if (p.value(store.history, K.sleepHr, x) != null) return p.sourceFor(K.sleepHr, x).name;
    }
    return p.sourceFor(K.sleepHr, today).name;
  }

  final restSrc = restSource();
  final zone = {
    'settings': store.zoneSettings.toJson(),
    'restHrUsed': store.restHrForZone(now),
    'restSrc': restSrc,
    'age': store.profile.ageOn(now),
    if (z != null) 'zone': {'lo': z.lo, 'hi': z.hi, 'rest': z.rest, 'max': z.max, 'maxMeasured': z.maxMeasured, 'manual': z.manual, 'restMeasured': z.restMeasured},
  };

  // ---------------------------------------------------------------- «όπως φάνηκε» έξω από τη Διατροφή (K8-05)
  // Έλεγχος 21/11 (K8-05): πριν η αναφορά είχε τιμή «όπως φάνηκε» μόνο για τη Διατροφή. Τώρα και Ύπνος, Κίνηση, Σώμα,
  // προπόνηση σήμερα ([buildWidgetSnapshot]: τα έτοιμα κείμενα των widgets, με τους ίδιους κανόνες με τις οθόνες), και
  // τρεις υπολογισμοί με τις ΙΔΙΕΣ συναρτήσεις των οθονών (μόνο αριθμοί): τάση σώματος «3 με 3» ([bodyTrend]), ζώνη HRV
  // ([hrvTrend]) και «Η εβδομάδα σου» ([buildWeekReview]). Κανένας νέος υπολογισμός.
  final shown = buildWidgetSnapshot(store, food, now, training: trainingStore);
  // R8-A11-3: το widget «Σώμα» δείχνει την τελευταία ζύγιση όσο παλιά κι αν είναι· αν είναι παλιότερη από τις μέρες της
  // αναφοράς, οι τιμές της δεν γράφονται (μόνο ότι υπάρχει).
  final shownWeigh = d == null || d.body.isEmpty ? null : (guardBody(d.body).shown.lastOrNull ?? d.body.last);
  if (shownWeigh != null && shownWeigh.time.isBefore(from)) {
    (shown['kinds'] as Map)['body'] = <String, dynamic>{'outsideWindow': true};
  } else if (d != null && shownWeigh != null) {
    // K8-R-12 (ανεξάρτητος έλεγχος): το γράφημα του widget είναι οι 7 τελευταίες ζυγίσεις που μετρούν, ΟΣΟ παλιές κι αν
    // είναι, και η διαφορά («−0,4 kg») είναι από την προηγούμενη. Με αραιές ζυγίσεις έμπαιναν τιμές μηνών, ενώ η αναφορά
    // λέει «τις τελευταίες 60 μέρες»: οι θέσεις του γραφήματος πριν από την πρώτη μέρα της αναφοράς γράφονται null, και αν
    // η προηγούμενη ζύγιση (αυτή με την οποία συγκρίνει το widget) είναι έξω από αυτές τις μέρες, το «Βάρος» γράφεται
    // χωρίς τη διαφορά του (η λεζάντα, η σύντομη λεζάντα και το πρόσημο).
    final guard = guardBody(d.body);
    final counted = guard.counted;
    final recent = counted.length > 7 ? counted.sublist(counted.length - 7) : counted;
    final waiting = guard.shown.isEmpty || guard.pending.contains(shownWeigh);
    final at = counted.indexWhere((x) => identical(x, shownWeigh));
    final prevOld = !waiting && at >= 1 && counted[at - 1].time.isBefore(from);
    final body = (shown['kinds'] as Map)['body'];
    final m = body is Map ? body['m'] : null;
    if (body is Map && m is Map && (prevOld || recent.any((x) => x.time.isBefore(from)))) {
      final old = [for (final x in recent) x.time.isBefore(from)];
      final pad = 7 - recent.length;
      Object? masked(Object? key, Object? box) {
        if (box is! Map) return box;
        final series = box['s'];
        final noDiff = prevOld && key == 'weight';
        return <String, dynamic>{
          for (final e in box.entries)
            if (!(noDiff && (e.key == 'cap' || e.key == 'capShort' || e.key == 'd')))
              '${e.key}': e.key == 's' && series is List
                  ? [
                      for (var i = 0; i < series.length; i++)
                        i - pad >= 0 && i - pad < old.length && old[i - pad] ? null : series[i],
                    ]
                  : e.value,
        };
      }

      (shown['kinds'] as Map)['body'] = <String, dynamic>{
        for (final e in body.entries)
          '${e.key}': e.key == 'm' ? <String, dynamic>{for (final x in m.entries) '${x.key}': masked(x.key, x.value)} : e.value,
      };
    }
  }

  Map<String, dynamic>? bodyCalc;
  if (d != null) {
    // Όπως η σελίδα «Σώμα»: η ζύγιση της μέρας του φύλακα ([guardBody] `shown`) και η προηγούμενη που μετρά.
    final guard = guardBody(d.body);
    final last = guard.shown.isEmpty ? d.latestBody : guard.shown.last;
    final prev = last == null ? null : previousCounted(guard.counted, last);
    // R8-A11-3: και εδώ μόνο ζυγίσεις των τελευταίων [diagnosticsDays] ημερών (όπως λέει η πολιτική απορρήτου): τιμή από
    // παλιότερη ζύγιση δεν γράφεται, μόνο ότι υπάρχει («outsideWindow»).
    const outside = <String, dynamic>{'outsideWindow': true};
    Map<String, dynamic>? trend(double? Function(BodyMeasurement) f) {
      final t = bodyTrend(d.body, f);
      if (t == null) return null;
      if (t.from.isBefore(from)) return outside;
      return {'now': _n(t.now), 'before': _n(t.before), 'from': dateKey(t.from), 'to': dateKey(t.to)};
    }

    bodyCalc = {
      'last': last == null
          ? null
          : last.time.isBefore(from)
              ? outside
              : {
                  't': _iso(last.time),
                  'ms': last.time.millisecondsSinceEpoch,
                  'kg': _n(last.weight),
                  'status': guard.foreign.contains(last) ? 'foreign' : (guard.pending.contains(last) ? 'pending' : 'counted'),
                },
      'previous': prev == null
          ? null
          : prev.time.isBefore(from)
              ? outside
              : {'t': _iso(prev.time), 'ms': prev.time.millisecondsSinceEpoch, 'kg': _n(prev.weight)},
      // Οι τέσσερις γραμμές της «Σύστασης σώματος» που δείχνουν τάση: μεσαία τιμή 3 τελευταίων, 3 παλιότερων, από–ως.
      'fatPct': trend((b) => b.fatPct),
      'fatKg': trend((b) => b.fatKg),
      'smm': trend((b) => b.smm),
      'leanMass': trend((b) => b.leanMass),
    };
  }

  // Ζώνη HRV: για την τελευταία νύχτα με HRV (σήμερα ή χθες), όπως η σελίδα της νύχτας. Η HRV έρχεται μόνο από το Oura.
  Map<String, dynamic>? hrvCalc;
  final nightPlan = store.plan;
  DateTime? hrvDay;
  for (var i = 0; i < 2 && hrvDay == null; i++) {
    final x = DateTime(today.year, today.month, today.day - i);
    if (nightPlan.value(store.history, K.hrv, x) != null) hrvDay = x;
  }
  if (hrvDay != null) {
    final t = hrvTrend(store.history, nightPlan, hrvDay);
    if (t != null) {
      hrvCalc = {
        'day': dateKey(hrvDay),
        'weekMs': _n(t.weekMs, 1),
        'lowMs': _n(t.lowMs, 1),
        'highMs': _n(t.highMs, 1),
        'band': t.band.name,
        'weekNights': t.weekNights,
        'baseNights': t.baseNights,
        // K8-R-12: το εύρος βγαίνει από τις [hrvBaseDays] νύχτες ΠΡΙΝ από τις 7 τελευταίες, δηλαδή ως 67 μέρες πίσω, ενώ το
        // «data.history» έχει 60: όποιος το ξαναϋπολογίσει από το αρχείο πρέπει να ξέρει ότι οι πρώτες μέρες του λείπουν.
        'baseFrom': dateKey(DateTime(hrvDay.year, hrvDay.month, hrvDay.day - (7 + hrvBaseDays - 1))),
        'baseTo': dateKey(DateTime(hrvDay.year, hrvDay.month, hrvDay.day - 7)),
      };
    }
  }

  // «Η εβδομάδα σου»: η εβδομάδα που δείχνει (ή έδειξε τελευταία) η κάρτα: Κυριακή από τις 18:00 και όλη τη Δευτέρα
  // ([reviewWeekSunday]· «shownNow»)· τις άλλες μέρες η τελευταία Κυριακή που πέρασε. Με το ίδιο σχέδιο πηγών με τη Σήμερα.
  Map<String, dynamic>? weekCalc;
  if (store.history.isNotEmpty) {
    final weekPlan = store.analysisPlan;
    final shownSunday = reviewWeekSunday(now);
    final sunday = shownSunday ?? DateTime(today.year, today.month, today.day - today.weekday);
    final w = buildWeekReview(store.history, sunday, now, plan: weekPlan);
    // Αν η μέτρηση ήρθε από το δαχτυλίδι κάποια μέρα των δύο περιόδων (μόνο σημάδι· η σύνοψη αφήνει έξω τη γραμμή).
    // Και οι τιμές του ρολογιού που μετριούνται πάνω στις ώρες ύπνου του Oura ([definitionMetrics]) τις μέρες με νύχτα Oura.
    bool ouraIn(String metric, DateTime a, DateTime b) {
      final byDefinition = definitionMetrics.contains(metric);
      for (var x = _day(a); !x.isAfter(b); x = DateTime(x.year, x.month, x.day + 1)) {
        if (weekPlan.sourceFor(metric, x) == Source.oura) return true;
        if (byDefinition && (weekPlan.nightSource(x) == Source.oura || _hasOura(store.history[dateKey(x)]))) return true;
      }
      // K8-R-02: οι παλμοί μέρας της τελευταίας μέρας εξαιρούν και τον ύπνο που αρχίζει το βράδυ της (η νύχτα της επομένης).
      final next = DateTime(b.year, b.month, b.day + 1);
      if (byDefinition && (weekPlan.nightSource(next) == Source.oura || _hasOura(store.history[dateKey(next)]))) return true;
      return false;
    }

    weekCalc = {
      'monday': dateKey(w.monday),
      'sunday': dateKey(w.sunday),
      // K8-R-14: η Σήμερα δείχνει την κάρτα μόνο αν είναι ανοιχτή στις ρυθμίσεις ΚΑΙ υπάρχει τουλάχιστον μία τιμή.
      'shownNow': shownSunday != null && store.prefs.show('week') && w.items.any((t) => t.current != null),
      'items': [
        for (final t in w.items)
          {
            'key': t.def.key,
            'status': t.status.name,
            'current': _n(t.current),
            'previous': _n(t.previous),
            'n': t.nCurrent,
            'nPrev': t.nPrevious,
            'needed': t.needed,
            'src': t.source.name,
            if (ouraIn(t.def.key, t.previousFrom, t.end)) 'oura': true,
          },
      ],
      if (w.bestNight case final b?) 'bestNight': dateKey(b),
      if (w.bestNightScore case final v?) 'bestNightScore': _n(v, 1),
      if (ouraIn(K.sleepScore, w.monday, w.sunday)) 'bestNightOura': true,
      if (w.mostSteps case final b?) 'mostSteps': dateKey(b),
      if (w.mostStepsValue case final v?) 'mostStepsValue': _n(v, 0),
      'activeTotal': _n(w.activeTotal, 1),
      'activeDays': w.activeDays,
      if (w.weightFirst case final f?) 'weightFirst': [dateKey(f.$1), _n(f.$2)],
      if (w.weightLast case final l?) 'weightLast': [dateKey(l.$1), _n(l.$2)],
    };
  }

  // ---------------------------------------------------------------- πίεση, σάκχαρο, καρδιογραφήματα (K8-03)
  // Έλεγχος 21/11 (K8-03): πριν έλειπαν εντελώς (το αντίγραφο ασφαλείας τα είχε, η αναφορά όχι). Ο μέσος όρος 7 ημερών με
  // την ίδια [bpAverage] που δείχνει η σελίδα, με ένα δεκαδικό (η οθόνη τον γράφει στρογγυλεμένο στη μονάδα).
  final vitalsOk = vitals != null && vitals.read ? vitals : null;
  final bp = vitalsOk == null ? null : bpAverage(vitalsOk.all, now);
  final bpCalc = bp == null ? null : {'sys': _n(bp.sys, 1), 'dia': _n(bp.dia, 1), 'n': bp.n, 'd': bp.d};

  // Έλεγχος 21/11 (K8-08): ΠΟΙΑ μέρη της αναφοράς βγαίνουν από τιμές του δαχτυλιδιού (μόνο ονόματα πεδίων, καμία τιμή):
  // η σύνοψη που δίνεται σε AI τα αφήνει έξω ([diagnosticsSummary]).
  // Η νύχτα που δείχνει το widget «Ύπνος» (σήμερα ή χθες) και η πηγή της, όπως τη διαλέγει το [buildWidgetSnapshot].
  DateTime? sleepDay;
  for (var i = 0; i < 2 && sleepDay == null; i++) {
    final x = DateTime(today.year, today.month, today.day - i);
    if (nightPlan.value(store.history, K.sleepMin, x) != null) sleepDay = x;
  }
  // K8-R-01 (ανεξάρτητος έλεγχος): το widget γράφει για κάθε κουτάκι και γράφημα 7 νυχτών (και «Ν νύχτες μέσα στο εύρος»),
  // με κάθε νύχτα από τη ΔΙΚΗ της πηγή. Μετά από επιστροφή στο ρολόι, οι προηγούμενες νύχτες του γραφήματος είναι ακόμα του
  // Oura: ο «Ύπνος» σημαδεύεται όταν ΟΠΟΙΑΔΗΠΟΤΕ από τις 7 νύχτες είναι του δαχτυλιδιού, όχι μόνο η τελευταία.
  final sleepFromOura = sleepDay != null &&
      [for (var i = 0; i < 7; i++) DateTime(sleepDay.year, sleepDay.month, sleepDay.day - i)]
          .any((x) => nightPlan.nightSource(x) == Source.oura || _hasOura(store.history[dateKey(x)]));
  // Οι «Παλμοί χθες» του widget «Κίνηση» είναι του ρολογιού, αλλά μετριούνται έξω από τις ώρες ύπνου του Oura όταν η
  // χθεσινή νύχτα είναι του δαχτυλιδιού.
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  final moveShown = (shown['kinds'] as Map)[WKind.move];
  final dayHrByOura = moveShown is Map &&
      moveShown['m'] is Map &&
      (moveShown['m'] as Map).containsKey('dayHr') &&
      // K8-R-02: οι παλμοί της χθεσινής μέρας εξαιρούν τον ύπνο δύο νυχτών: της χθεσινής και αυτής που άρχισε χθες βράδυ
      // (η σημερινή νύχτα).
      (nightPlan.nightSource(yesterday) == Source.oura ||
          _hasOura(store.history[dateKey(yesterday)]) ||
          nightPlan.nightSource(today) == Source.oura ||
          _hasOura(store.history[dateKey(today)]));
  final ouraParts = <String>[
    if (store.history.values.any((row) => row.keys.any((k) => k.startsWith(_ouraPrefix)))) 'data.history: o.*',
    if (hrvCalc != null) 'calc.hrv',
    if (restSrc == Source.oura.name) 'calc.zone: restHrUsed, zone',
    if (weekCalc != null && (weekCalc['items'] as List).any((x) => (x as Map)['oura'] == true)) 'calc.week.items',
    if (weekCalc != null && weekCalc['bestNightOura'] == true) 'calc.week: bestNight, bestNightScore',
    if (sleepFromOura) 'shown.kinds.sleep',
    if (dayHrByOura) 'shown.kinds.move.m.dayHr',
  ];

  // ---------------------------------------------------------------- checks
  final checks = <Map<String, Object?>>[];
  // Έλεγχος 21/11 (K8-14): [n] = πόσα βρέθηκαν ΣΥΝΟΛΙΚΑ όταν η λεπτομέρεια κόβεται (στα 20 ή στα 10)· πριν δεν φαινόταν.
  void check(String id, bool ok, [String? detail, int? n]) =>
      checks.add({'id': id, 'ok': ok, if (detail != null) 'detail': detail, if (n != null && n > 0) 'n': n});

  check('prefs-read', store.prefsReady);
  check('history-read', store.historyReady);
  check('food-read', food.loaded && food.error == null, food.error);
  // Τελικός έλεγχος (Συμβούλιο 3): γραμμές της βάσης που δεν διαβάστηκαν και παραλείφθηκαν στο άνοιγμα.
  check('food-rows', food.skippedRows == 0, food.skippedRows == 0 ? null : '${food.skippedRows} γραμμές δεν διαβάστηκαν');
  check('food-save', food.saveError == null, food.saveError);
  // «Τα φαγητά μου» (15/11): το αρχείο τους διαβάστηκε, και κάθε φαγητό έχει μόνο υλικά που υπάρχουν.
  check('dishes-read', food.dishesRead && food.dishesNote == null, food.dishesNote);
  final brokenDishes = [
    for (final d in food.dishes)
      if (food.missingItems(d.items).isNotEmpty) '${d.name}: ${food.missingItems(d.items).join(', ')}',
  ];
  check('dishes-items', brokenDishes.isEmpty, brokenDishes.isEmpty ? null : brokenDishes.take(20).join('; '), brokenDishes.length);
  // Πρόγραμμα εβδομάδας (15/11): κάθε γεύμα δείχνει φαγητό που υπάρχει.
  final plan = food.week;
  final lostSlots = plan == null
      ? const <String>[]
      : [
          for (var i = 0; i < plan.days.length; i++)
            for (final s in plan.days[i])
              if (food.dishById(s.dishId) == null) 'μέρα ${i + 1} ${s.meal.name}',
        ];
  check('week-dishes', lostSlots.isEmpty, lostSlots.isEmpty ? null : lostSlots.take(20).join('; '), lostSlots.length);
  check('training-read', !trainingReadError);
  // Έλεγχος 21/11 (K8-07): ιστορικό, ρυθμίσεις και προπονήσεις γράφονται στην αναφορά από τη ΜΝΗΜΗ. Πριν οι έλεγχοι
  // έλεγαν μόνο αν ΔΙΑΒΑΣΤΗΚΑΝ: με αποθήκευση που απέτυχε η αναφορά τα έδειχνε «σωστά» και όλους τους ελέγχους «ok», ενώ
  // μετά το κλείσιμο της εφαρμογής οι τιμές έλειπαν. Τώρα και αν ΓΡΑΦΤΗΚΑΝ.
  final unsaved = store.unsavedDays.toList()..sort();
  check('history-saved', unsaved.isEmpty, unsaved.isEmpty ? null : unsaved.take(20).join(','), unsaved.length);
  check('prefs-saved', !store.prefsWriteFailed && !store.prefsSaveError);
  if (trainingStore != null) {
    check('training-saved', trainingStore.saveError == null, trainingStore.saveError);
    // Προπονήσεις που λένε ότι έχουν παλμούς αλλά το αρχείο των παλμών τους δεν διαβάστηκε για την αναφορά.
    check('training-hr', trainingStore.backupHrMissing == 0,
        trainingStore.backupHrMissing == 0 ? null : '${trainingStore.backupHrMissing} προπονήσεις χωρίς τους παλμούς τους');
  }
  // Έλεγχος 21/11 (K8-03): το αρχείο με πίεση, σάκχαρο, καρδιογραφήματα διαβάστηκε.
  check('vitals-read', vitalsOk != null, vitals == null ? 'δεν ζητήθηκαν' : vitals.error);
  check('samsung-read', d != null && d.failed.isEmpty, d == null ? 'καμία ανάγνωση' : (d.failed.isEmpty ? null : d.failed.join(',')));

  final badGrams = <String>[];
  final badValues = <String>{};
  final noKcal = <String>[];
  final atwater = <String>{};
  final dup = <String>[];
  final seen = <String>{};
  for (var day = from; !day.isAfter(today); day = DateTime(day.year, day.month, day.day + 1)) {
    for (final e in food.entriesFor(day)) {
      if (!e.grams.isFinite || e.grams <= 0 || e.grams > 3000) badGrams.add('${e.day} ${e.food.name} ${e.grams}');
      if (!e.food.n.has(Nk.kcal)) noKcal.add('${e.day} ${e.food.name}');
      // Τελικός έλεγχος (Συμβούλιο 3): τιμές ανά 100 g που δεν γίνεται να ισχύουν (αρνητικές, άπειρες, πάνω από 900 kcal
      // ή πάνω από 100 g): η φόρμα δεν τις δέχεται, άρα ήρθαν από αντίγραφο ή παλιά έκδοση.
      final per100 = {
        for (final k in const [Nk.kcal, Nk.protein, Nk.carbs, Nk.sugars, Nk.fat, Nk.satFat, Nk.fiber, Nk.salt])
          if (e.food.n[k] case final x?) k: x.value,
      };
      if (per100.values.any((x) => !x.isFinite || x < 0) || impossibleValues(per100).isNotEmpty) {
        badValues.add('${e.food.id} ${e.food.name}');
      }
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
  check('food-grams', badGrams.isEmpty, badGrams.isEmpty ? null : badGrams.take(20).join('; '), badGrams.length);
  check('food-values', badValues.isEmpty, badValues.isEmpty ? null : badValues.take(20).join('; '), badValues.length);
  check('food-has-kcal', noKcal.isEmpty, noKcal.isEmpty ? null : noKcal.take(20).join('; '), noKcal.length);
  check('food-atwater', atwater.isEmpty, atwater.isEmpty ? null : atwater.take(20).join('; '), atwater.length);
  check('food-duplicates', dup.isEmpty, dup.isEmpty ? null : dup.take(20).join('; '), dup.length);

  final jumps = <String>[];
  for (var i = 1; i < weights.length; i++) {
    final a = weights[i - 1], b = weights[i];
    // R8-A11-3: μόνο μέσα στις μέρες της αναφοράς (το κείμενο του ελέγχου γράφει τις δύο ζυγίσεις).
    if (a.$1.isBefore(from)) continue;
    final gap = daysBetween(a.$1, b.$1);
    if (gap > 0 && gap <= 7 && (b.$2 - a.$2).abs() > 1.5 * gap.clamp(1, 2)) jumps.add('${dateKey(a.$1)}→${dateKey(b.$1)}: ${a.$2}→${b.$2}');
  }
  check('weight-jumps', jumps.isEmpty, jumps.isEmpty ? null : jumps.take(10).join('; '), jumps.length);
  if (g != null) {
    check('goals-floor', g.kcal >= (g.male ? kcalFloorMale : kcalFloorFemale), '${g.kcal}');
    final latest = weights.isEmpty ? null : weights.last.$2;
    // K8-R-12: ζύγιση παλιότερη από τις μέρες της αναφοράς δεν γράφεται με την τιμή της (ο έλεγχος γίνεται όπως πριν).
    final latestOld = weightsOld;
    check(
        'goals-weight-fresh',
        latest == null || (latest - g.kg).abs() < 3,
        latest == null
            ? 'καμία ζύγιση'
            : latestOld
                ? 'στόχοι με ${g.kg} kg, η τελευταία ζύγιση είναι πριν από τις μέρες της αναφοράς'
                : 'στόχοι με ${g.kg} kg, τελευταία ζύγιση $latest kg');
  }

  // Έλεγχος 21/11 (K8-08): η σειρά των κλειδιών: στοιχεία αρχείου → «checks» → «errors» → «calc» → «shown» → «data», και
  // μέσα στο «data» τα βαριά τελευταία (προπονήσεις, «τα προϊόντα μου», ημερολόγιο φαγητού). Πριν το «data» (με όλο το
  // ημερολόγιο, το 95% του κειμένου) γραφόταν ΠΡΙΝ από το «calc»: όποιος διάβαζε το αρχείο από την αρχή έβλεπε πρώτα
  // εκατοντάδες χιλιάδες χαρακτήρες καταχωρίσεων.
  return {
    'app': 'ygeia-forma',
    'kind': 'diagnostics',
    'v': diagnosticsVersion,
    'created': _iso(now),
    'createdMs': now.millisecondsSinceEpoch,
    'tz': now.timeZoneName,
    'tzOffsetMin': now.timeZoneOffset.inMinutes,
    // Οι μέρες που καλύπτουν τα ανά μέρα στοιχεία (Samsung, ιστορικό, «calc.days»).
    'window': {'days': diagnosticsDays, 'from': dateKey(from), 'to': dateKey(today)},
    'release': reporter?.release,
    'device': reporter?.device,
    'screen': screen,
    'screens': reporter?.screen,
    // Τέλος διαλείμματος στο κινητό: πόσες φορές χτύπησε και πόσο άργησε (ms), όπως το μέτρησε το ίδιο το κινητό (13/11).
    'rest': rest,
    'note': note,
    // Έλεγχος 21/11 (K8-12): κατάσταση που έλειπε. «background»: φαίνεται το αντίγραφο του παρασκηνίου (παλμοί 7 ημερών,
    // ο έλεγχος θερμίδων περιμένει). «errorReports»: αν είναι ανοιχτές οι «Αναφορές σφαλμάτων», και πόσα περιμένουν.
    // «samsungFailedLog» (K8-06): οι τελευταίες αναγνώσεις της Samsung με αποτυχία, [ώρα ms, είδη].
    'env': {
      'background': d?.background,
      'sleepOk': d?.sleepOk,
      'bodyOk': d?.bodyOk,
      'bodyOther': d?.bodyOther,
      'planState': store.planState.name,
      'sourcesRead': sources != null,
      'prefsSaveError': store.prefsSaveError,
      'errorReports': reporter?.enabled,
      'errorsPending': errorsPending,
      'samsungFailedLog': store.prefs.failedLog,
    },
    'ouraIn': ouraParts,
    'checks': checks,
    'errors': reporter == null ? const [] : List.of(reporter.recentErrors),
    'calc': {
      'goals': goalsCalc,
      'adaptive': adaptive,
      'chol': chol,
      'zone': zone,
      'body': bodyCalc,
      'hrv': hrvCalc,
      'week': weekCalc,
      'bp': bpCalc,
      'rules': diagnosticsRules(),
      'days': days,
    },
    'shown': shown,
    'data': {
      'foodLogSource': foodLog == null ? 'memory-${diagnosticsDays}d' : 'file',
      'prefs': store.prefsReady ? _prefsForReport(_withoutSecrets(store.prefsJson()), dateKey(from)) : null,
      'prefsDropped': store.prefsReady ? _droppedKeys(store.prefsJson()) : const <String>[],
      'profile': {
        'birthYear': store.profile.birthYear,
        'birthMonth': store.profile.birthMonth,
        'sex': store.profile.sex,
        'heightCm': store.profile.heightCm,
        'weighDays': store.profile.weighDays.toList()..sort(),
        'waistDay': store.profile.waistDay,
      },
      'dishes': food.dishesForBackup(),
      // Πρόγραμμα εβδομάδας (15/11): οι θέσεις με το φαγητό, τις θερμίδες και τι σημειώθηκε.
      'week': food.week?.toJson(),
      // 19/11 (I-15): «Τι μου αρέσει» (από αυτά φτιάχνει το AI) και αν είναι συνδεδεμένο το AI. Ποτέ διεύθυνση ή κλειδί.
      'foodLikes': food.likesForBackup(),
      'ai': {'connected': AiBridge.shared?.ready ?? false, 'tested': AiBridge.shared?.okDay},
      'sources': sources == null ? null : {'plan': _tryJson(sources.plan), 'log': sources.log == null ? null : _tryJson(sources.log!)},
      'waist': [for (final w in store.waist) w.toJson()],
      // Έλεγχος 21/11 (K8-03): πίεση, σάκχαρο, καρδιογραφήματα, όπως στο αντίγραφο ασφαλείας· null αν δεν διαβάστηκαν.
      'vitals': vitalsOk?.forBackup(),
      'samsung': samsung,
      'history': history,
      'training': training,
      'myFoods': myFoods,
      // Αν δεν διαβάστηκε το αρχείο του ημερολογίου, ό,τι υπάρχει στη μνήμη (τις τελευταίες μέρες).
      'foodLog': foodLog ??
          [
            for (var day = from; !day.isAfter(today); day = DateTime(day.year, day.month, day.day + 1))
              for (final e in food.entriesFor(day)) e.toJson(),
          ],
    },
  };
}

/// Έλεγχος 21/11 (K8-15): οι σταθερές των κανόνων που χρησιμοποιεί το «calc», γραμμένες στο αρχείο. Πριν υπήρχαν μόνο στον
/// κώδικα: ο ελεγκτής τις είχε αντιγραμμένες και θα έβγαζε ψεύτικες «διαφορές» μόλις άλλαζε μία.
Map<String, dynamic> diagnosticsRules() => {
      'days': diagnosticsDays,
      'adapt': {
        'fullDayShare': adaptFullDayShare,
        'skipDays': adaptSkipDays,
        'windowDays': adaptWindowDays,
        'windows': adaptWindows,
        'minIntakeDays': adaptMinIntakeDays,
        'minWeighIns': adaptMinWeighIns,
        'minSpanDays': adaptMinSpanDays,
        'maxStep': adaptMaxStep,
        'minStep': adaptMinStep,
        'gapDays': adaptGapDays,
        'scanDays': adaptScanDays,
        'minChangeDays': adaptMinChangeDays,
        'absurdKcal': adaptAbsurdKcal,
        'absurdTimes': adaptAbsurdTimes,
        'lowShare': adaptLowShare,
        'highShare': adaptHighShare,
        'guardSe': adaptGuardSe,
        'fastLossPct': adaptFastLossPct,
        'fastFromDay': adaptFastFromDay,
        'fastWindowDays': adaptFastWindowDays,
        'fastGuardSe': adaptFastGuardSe,
        'fastMinIntakeDays': adaptFastMinIntakeDays,
        'fastRecentDays': adaptFastRecentDays,
        'fastRecentMinDays': adaptFastRecentMinDays,
        'minBmi': adaptMinBmi,
        'likelyUnderlogShare': adaptLikelyUnderlogShare,
        'farBelowRate': farBelowRate,
        'quitHoldDays': smokeQuitHoldDays,
        'estShareNote': estimatedShareNote,
        'kcalPerKg': kcalPerKg,
        'floorMale': kcalFloorMale,
        'floorFemale': kcalFloorFemale,
        'logMax': adaptLogMax,
      },
      'body': {
        'trendGroup': bodyTrendGroup,
        'trendGapDays': bodyTrendGapDays,
        'floorFatPct': bodyFloorFatPct,
        'floorKg': bodyFloorKg,
      },
      'bp': {'days': 7, 'minDays': bpMinDays, 'minReadings': bpMinReadings},
      'hrv': {'weekMin': hrvWeekMin, 'baseDays': hrvBaseDays, 'baseMin': hrvBaseMin, 'bandSd': hrvBandSd},
    };

// ---------------------------------------------------------------------------------------------------------------------
// Σύνοψη για τον Claude (K8-08)
// ---------------------------------------------------------------------------------------------------------------------

/// Το πρόθεμα των τιμών του Oura στο ιστορικό («o.sleepMin», «o.hrv» …· sources.dart `ouraKeys`).
const _ouraPrefix = 'o.';

/// Η μέρα του ιστορικού έχει τιμή του Oura.
bool _hasOura(Map<String, double>? row) => row != null && row.keys.any((k) => k.startsWith(_ouraPrefix));

/// Το ίδιο για γραμμή που διαβάστηκε από την αναφορά (άγνωστος τύπος).
bool _rowHasOura(Object? row) => row is Map && row.keys.any((k) => '$k'.startsWith(_ouraPrefix));

/// Το κλειδί της επόμενης μέρας («2026-12-13» → «2026-12-14»)· κενό αν το κλειδί δεν είναι μέρα.
String _nextDayKey(String key) {
  final d = DateTime.tryParse(key);
  return d == null ? '' : dateKey(DateTime(d.year, d.month, d.day + 1));
}

/// Οι τιμές του ρολογιού που εξαιρούν και τον ύπνο που ΑΡΧΙΖΕΙ το βράδυ της μέρας (history.dart `_heartWithPlan`).
const _dayHeartByOuraNight = {K.dayHr, K.restHr, K.walkHr};

/// Το ιστορικό της αναφοράς [full] έχει τιμή του Oura σε κάποια από τις [back] + 1 τελευταίες μέρες της («window.to» και
/// [back] μέρες πίσω). Χωρίς «window»: αν έχει οπουδήποτε.
bool _recentOura(Map<String, dynamic> full, int back) {
  final data = full['data'];
  final history = data is Map ? data['history'] : null;
  if (history is! Map) return false;
  final window = full['window'];
  final to = window is Map && window['to'] is String ? DateTime.tryParse(window['to'] as String) : null;
  if (to == null) return history.values.any(_rowHasOura);
  final first = dateKey(DateTime(to.year, to.month, to.day - back));
  return history.entries.any((e) => '${e.key}'.compareTo(first) >= 0 && _rowHasOura(e.value));
}

/// Ψηφία σε κείμενο σφάλματος → «#»: το μήνυμα μένει χρήσιμο, χωρίς καμία τιμή.
String _maskDigits(String s) => s.replaceAll(RegExp(r'[0-9]+'), '#');

/// Τα θρεπτικά που μετρά η εφαρμογή· μόνο αυτά κρατά το λεπτό αντίγραφο τροφίμου της σύνοψης.
const diagnosticsThinNutrients = [
  Nk.kcal, Nk.protein, Nk.carbs, Nk.sugars, Nk.fiber, Nk.fat, Nk.satFat, Nk.salt, Nk.sodium, Nk.alcohol, Nk.polyols,
  Nk.erythritol,
];

/// Έλεγχος 21/11 (K8-08): η «Σύνοψη για τον Claude», από την πλήρη αναφορά ([full], το αποτέλεσμα του [diagnosticsFrom]).
/// Καθαρή συνάρτηση: δεν διαβάζει τίποτα άλλο και δεν αλλάζει το [full].
///
/// Γιατί: η πλήρης αναφορά είναι «.json.gz» (συμπιεσμένη) και ήδη τον πρώτο μήνα περίπου 365.000 χαρακτήρες, με το 95% να
/// είναι το ημερολόγιο φαγητού (κάθε καταχώριση κουβαλά αντίγραφο του τροφίμου με ~42 θρεπτικά) και οι παλμοί των
/// προπονήσεων: ένα μοντέλο σε συζήτηση δεν τη διαβάζει «μόνο του». Η σύνοψη είναι απλό κείμενο JSON με την ίδια σειρά
/// (στοιχεία αρχείου → «checks» → «errors» → «calc» → «shown» → «data») και:
/// - ΧΩΡΙΣ καμία τιμή του Oura (η σύμβαση της Oura δεν επιτρέπει να δοθούν δεδομένα του δαχτυλιδιού σε AI): έξω μένουν
///   οι τιμές «o.*» του ιστορικού και, στις μέρες που έχουν τέτοιες, οι τιμές του ρολογιού που μετριούνται πάνω στις ώρες
///   ύπνου του Oura (οξυγόνο της νύχτας και η κάλυψή του, παλμοί μέρας, ηρεμίας, περπατήματος), η ζώνη HRV, η ζώνη
///   περπατήματος όταν οι παλμοί ηρεμίας της βγαίνουν με τη βοήθεια του δαχτυλιδιού, οι γραμμές της «Η εβδομάδα σου» που
///   βγήκαν από αυτό, και ο «Ύπνος» του «shown» όταν η νύχτα είναι του Oura. Στην αρχή γράφει «oura: omitted» και στο
///   «omitted» ΤΙ έμεινε έξω (ονόματα πεδίων, ποτέ τιμές).
/// - χωρίς «data.foodLog», «data.myFoods» και τους παλμούς των προπονήσεων («training.hrz», «hr» μέσα στην προπόνηση)·
/// - οι καταχωρίσεις φαγητού μόνο των ημερών της αναφοράς («window», 60 μέρες) σε λεπτή μορφή («data.food»): κάθε τρόφιμο
///   μία φορά («foods»: όνομα και τα [diagnosticsThinNutrients] ανά 100 g), και κάθε καταχώριση με μέρα, γεύμα, γραμμάρια,
///   ώρα και το κλειδί του τροφίμου της·
/// - οι προπονήσεις μόνο των ίδιων ημερών (πόσες παλιότερες έμειναν έξω: «trainingOlder»).
Map<String, dynamic> diagnosticsSummary(Map<String, dynamic> full) {
  final omitted = <String>['data.foodLog', 'data.myFoods', 'data.training.hrz', 'data.training.sessions[].hr'];
  final data = full['data'] is Map ? Map<String, dynamic>.from(full['data'] as Map) : <String, dynamic>{};
  final calc = full['calc'] is Map ? Map<String, dynamic>.from(full['calc'] as Map) : <String, dynamic>{};
  final window = full['window'];
  final fromKey = window is Map && window['from'] is String ? window['from'] as String : '';

  // ---- Oura: ιστορικό ημερών χωρίς τα «o.*».
  final ouraKeys = <String>{};
  final history = data['history'];
  if (history is Map) {
    final out = <String, dynamic>{};
    for (final e in history.entries) {
      final row = e.value;
      if (row is! Map) {
        out['${e.key}'] = row;
        continue;
      }
      final hadOura = _rowHasOura(row);
      // K8-R-02 (ανεξάρτητος έλεγχος): οι παλμοί μέρας, ηρεμίας και περπατήματος της μέρας εξαιρούν τον ύπνο ΔΥΟ νυχτών:
      // αυτής που τελείωσε το πρωί της και αυτής που άρχισε το βράδυ της (γράφεται στην επόμενη μέρα). Η παραμονή της
      // πρώτης νύχτας του Oura δεν έχει κανένα «o.*», αλλά οι παλμοί της ορίζονται από τις ώρες ύπνου του.
      final byNext = _rowHasOura(history[_nextDayKey('${e.key}')]);
      final kept = <String, dynamic>{};
      for (final v in row.entries) {
        final k = '${v.key}';
        // Και οι τιμές του ρολογιού που μετριούνται πάνω στις ώρες ύπνου του Oura ([definitionMetrics]: οξυγόνο της νύχτας,
        // παλμοί μέρας, ηρεμίας, περπατήματος): η τιμή είναι του ρολογιού, αλλά το ποιες ώρες μετρούν το ορίζει το δαχτυλίδι.
        if (k.startsWith(_ouraPrefix) ||
            (hadOura && (k == K.spo2Cov || definitionMetrics.contains(k))) ||
            (byNext && _dayHeartByOuraNight.contains(k))) {
          ouraKeys.add(k);
        } else {
          kept[k] = v.value;
        }
      }
      out['${e.key}'] = kept;
    }
    data['history'] = out;
  }
  if (ouraKeys.isNotEmpty) omitted.add('data.history: ${(ouraKeys.toList()..sort()).join(', ')}');

  // ---- Oura: ό,τι στο «calc» βγαίνει από το δαχτυλίδι.
  // Η ζώνη HRV βγαίνει ΜΟΝΟ από τιμές του δαχτυλιδιού: έξω πάντα.
  if (calc['hrv'] != null) omitted.add('calc.hrv');
  calc.remove('hrv');
  final zone = calc['zone'];
  // Η αναφορά έχει οτιδήποτε του δαχτυλιδιού: τότε μένει έξω και ό,τι βγαίνει από τους παλμούς ηρεμίας (ζώνη περπατήματος).
  final ouraUsed = ouraKeys.isNotEmpty ||
      (full['ouraIn'] is List && (full['ouraIn'] as List).isNotEmpty) ||
      (zone is Map && zone['restSrc'] == Source.oura.name);
  // Και όταν οι παλμοί ηρεμίας είναι του ρολογιού αλλά μετρήθηκαν έξω από ώρες ύπνου του Oura (ιστορικό με τιμές Oura).
  if (zone is Map && ouraUsed) {
    // K8-R-04 (ανεξάρτητος έλεγχος): και η ζώνη «που όρισες εσύ» («settings.lo/hi»): το τεστ ομιλίας την προτείνει ως τη
    // ζώνη του υπολογισμού ± 5, δηλαδή βγαίνει κι αυτή από τους παλμούς ύπνου.
    final settings = zone['settings'];
    calc['zone'] = {
      for (final e in zone.entries)
        if (e.key != 'restHrUsed' && e.key != 'zone')
          '${e.key}': e.key == 'settings' && settings is Map
              ? {
                  for (final x in settings.entries)
                    if (x.key != 'lo' && x.key != 'hi') '${x.key}': x.value,
                }
              : e.value,
    };
    omitted.add('calc.zone: restHrUsed, zone, settings.lo, settings.hi');
    final prefs = data['prefs'];
    final prefsZone = prefs is Map ? prefs['zone'] : null;
    if (prefs is Map && prefsZone is Map) {
      data['prefs'] = {
        for (final e in prefs.entries)
          '${e.key}': e.key == 'zone'
              ? {
                  for (final x in prefsZone.entries)
                    if (x.key != 'lo' && x.key != 'hi') '${x.key}': x.value,
                }
              : e.value,
      };
      omitted.add('data.prefs.zone: lo, hi');
    }
  }
  final week = calc['week'];
  if (week is Map) {
    final w = <String, dynamic>{for (final e in week.entries) '${e.key}': e.value};
    final items = w['items'];
    if (items is List) {
      final kept = <Object?>[];
      final dropped = <String>[];
      for (final it in items) {
        if (it is Map && (it['oura'] == true || it['src'] == Source.oura.name)) {
          dropped.add('${it['key']}');
        } else {
          kept.add(it);
        }
      }
      w['items'] = kept;
      if (dropped.isNotEmpty) omitted.add('calc.week.items: ${dropped.join(', ')}');
    }
    if (w['bestNightOura'] == true) {
      w
        ..remove('bestNight')
        ..remove('bestNightScore');
      omitted.add('calc.week: bestNight, bestNightScore');
    }
    calc['week'] = w;
  }

  // ---- Oura: ο «Ύπνος» όπως φάνηκε, όταν η νύχτα είναι του δαχτυλιδιού (σημάδι της αναφοράς, ή η πηγή που γράφει).
  Object? shown = full['shown'];
  if (shown is Map) {
    final kinds = shown['kinds'];
    final sleep = kinds is Map ? kinds['sleep'] : null;
    final marked = full['ouraIn'] is List && (full['ouraIn'] as List).contains('shown.kinds.sleep');
    final src = sleep is Map ? sleep['src'] : null;
    // K8-R-01: δεύτερη ασφάλεια, ανεξάρτητη από το σημάδι: τιμή του Oura σε οποιαδήποτε από τις 8 τελευταίες μέρες της
    // αναφοράς (το γράφημα 7 νυχτών του widget) βγάζει όλο τον «Ύπνο».
    if (kinds is Map && sleep != null && (marked || (src is String && src.startsWith('Oura')) || _recentOura(full, 7))) {
      shown = {
        for (final e in shown.entries)
          '${e.key}': e.key == 'kinds'
              ? {
                  for (final k in kinds.entries)
                    if (k.key != 'sleep') '${k.key}': k.value,
                }
              : e.value,
      };
      omitted.add('shown.kinds.sleep');
    }
  }

  // ---- Oura: οι «Παλμοί χθες» της «Κίνησης» όταν η χθεσινή νύχτα είναι του δαχτυλιδιού (σημάδι της αναφοράς).
  if (shown is Map &&
      ((full['ouraIn'] is List && (full['ouraIn'] as List).contains('shown.kinds.move.m.dayHr')) || _recentOura(full, 1))) {
    final kinds = shown['kinds'];
    final move = kinds is Map ? kinds[WKind.move] : null;
    final m = move is Map ? move['m'] : null;
    if (kinds is Map && move is Map && m is Map && m.containsKey('dayHr')) {
      shown = {
        for (final e in shown.entries)
          '${e.key}': e.key == 'kinds'
              ? {
                  for (final k in kinds.entries)
                    '${k.key}': k.key == WKind.move
                        ? {
                            for (final x in move.entries)
                              '${x.key}': x.key == 'm'
                                  ? {
                                      for (final y in m.entries)
                                        if (y.key != 'dayHr') '${y.key}': y.value,
                                    }
                                  : x.value,
                          }
                        : k.value,
                }
              : e.value,
      };
      omitted.add('shown.kinds.move.m.dayHr');
    }
  }

  // ---- Φαγητό: οι καταχωρίσεις των ημερών της αναφοράς, λεπτές· κάθε τρόφιμο μία φορά.
  final foods = <String, Object?>{};
  final foodKeys = <String, String>{};
  final perId = <String, int>{};
  final entries = <Map<String, Object?>>[];
  var older = 0;
  final log = data['foodLog'];
  if (log is List) {
    for (final e in log) {
      if (e is! Map) continue;
      final day = e['day'];
      if (day is! String || day.compareTo(fromKey) < 0) {
        older++;
        continue;
      }
      final f = e['food'];
      String? key;
      if (f is Map) {
        final n = f['n'];
        final thin = <String, Object?>{
          'name': f['name'],
          for (final k in const ['perMl', 'ck', 'fv', 'energyCalc'])
            if (f[k] != null) k: f[k],
          'n': {
            if (n is Map)
              for (final k in diagnosticsThinNutrients)
                if (n[k] != null) k: n[k],
          },
        };
        final id = '${f['id']}';
        final sig = '$id|${diagnosticsEncode(thin)}';
        key = foodKeys[sig];
        if (key == null) {
          // Το ίδιο τρόφιμο με άλλες τιμές (π.χ. διορθώθηκε το προϊόν): δεύτερο κλειδί, «id#2».
          final c = perId[id] = (perId[id] ?? 0) + 1;
          key = c == 1 ? id : '$id#$c';
          foodKeys[sig] = key;
          foods[key] = thin;
        }
      }
      entries.add({
        'day': day,
        'meal': e['meal'],
        'f': key,
        'grams': e['grams'],
        'time': e['time'],
        if (e['est'] == true) 'est': true,
        if (e['dish'] != null) 'dish': e['dish'],
      });
    }
  }
  data
    ..remove('foodLog')
    ..remove('myFoods');
  if (older > 0) omitted.add('data.food: $older καταχωρίσεις πριν από $fromKey');

  // ---- Προπονήσεις: χωρίς παλμούς, μόνο των ημερών της αναφοράς.
  // Oura: τα όρια της ζώνης περπατήματος (της εφαρμογής και κάθε προπόνησης) βγαίνουν από τους παλμούς ηρεμίας· όταν η
  // αναφορά έχει οτιδήποτε του δαχτυλιδιού, μένουν κι αυτά έξω (δεν ξέρουμε από ποια πηγή ήταν τη μέρα της προπόνησης).
  final training = data['training'];
  if (training is Map) {
    final t = <String, dynamic>{
      for (final e in training.entries)
        if (e.key != 'hrz' && !(ouraUsed && e.key == 'zone')) '${e.key}': e.value,
    };
    if (ouraUsed) omitted.add('data.training: zone, sessions[].zlo, sessions[].zhi, sessions[].zt');
    // K8-R-03 (ανεξάρτητος έλεγχος): μια προπόνηση χωρίς τους παλμούς της και, όταν η αναφορά έχει οτιδήποτε του
    // δαχτυλιδιού, χωρίς τα όρια της ζώνης και τον χρόνο κάτω/μέσα/πάνω από αυτήν («zt»: κρίνεται με τα ίδια όρια).
    Map<String, dynamic> thin(Map s) => {
          for (final e in s.entries)
            if (e.key != 'hr' && !(ouraUsed && (e.key == 'zlo' || e.key == 'zhi' || e.key == 'zt'))) '${e.key}': e.value,
        };
    // Η προπόνηση σε εξέλιξη («current») κρατά όρια ζώνης και ΟΛΟΥΣ τους παλμούς: το ίδιο φίλτρο. Οι προπονήσεις που δεν
    // διαβάστηκαν («bad») και όσες σβήστηκαν πρόσφατα («drop») είναι ωμά αντικείμενα με ό,τι είχαν μέσα: μόνο το πλήθος.
    final current = t['current'];
    if (current is Map) {
      t['current'] = thin(current);
      omitted.add('data.training.current: hr${ouraUsed ? ', zlo, zhi, zt' : ''}');
    }
    for (final k in const ['bad', 'drop']) {
      final raw = t[k];
      if (raw is List) {
        t[k] = raw.length;
        omitted.add('data.training.$k: ${raw.length} (μόνο το πλήθος)');
      }
    }
    final fromMs = DateTime.tryParse(fromKey)?.millisecondsSinceEpoch;
    final sessions = t['sessions'];
    if (sessions is List) {
      final kept = <Object?>[];
      var old = 0;
      for (final s in sessions) {
        if (s is! Map) {
          kept.add(s);
          continue;
        }
        final start = s['start'];
        if (fromMs != null && start is num && start < fromMs) {
          old++;
          continue;
        }
        kept.add(thin(s));
      }
      t['sessions'] = kept;
      if (old > 0) {
        t['trainingOlder'] = old;
        omitted.add('data.training.sessions: $old προπονήσεις πριν από $fromKey');
      }
    }
    data['training'] = t;
  }

  // Τα βαριά τελευταία: προπονήσεις και φαγητό στο τέλος του «data».
  final trainingOut = data.remove('training');
  data['training'] = trainingOut;
  data['food'] = {'from': fromKey, 'foods': foods, 'entries': entries};

  // ---- Oura: μήνυμα σφάλματος από τον κώδικα του Oura μπορεί να κουβαλά κομμάτι από αυτό που διάβαζε (π.χ. FormatException):
  // μένει ο τύπος και η στοίβα, όχι το μήνυμα.
  Object? errorsOut = full['errors'];
  if (errorsOut is List) {
    var cut = 0;
    errorsOut = [
      for (final x in errorsOut)
        if (x is Map && diagnosticsEncode(x).toLowerCase().contains('oura'))
          {
            for (final e in x.entries)
              if (e.key != 'message') '${e.key}': e.value,
            'messageOmitted': ++cut > 0,
          }
        else if (x is Map)
          // K8-R-05 (ανεξάρτητος έλεγχος): σφάλμα σε οθόνη που ζωγραφίζει τιμές του Oura μπορεί να κουβαλά αριθμό στο μήνυμα
          // χωρίς τη λέξη «oura» πουθενά: στη σύνοψη κάθε μήνυμα γράφεται με «#» στη θέση των ψηφίων.
          {
            for (final e in x.entries) '${e.key}': e.key == 'message' && e.value is String ? _maskDigits(e.value as String) : e.value,
          }
        else
          x,
    ];
    if (cut > 0) omitted.add('errors[].message: $cut');
    omitted.add('errors[].message: τα ψηφία ως #');
  }

  const heavy = {'calc', 'shown', 'data', 'ouraIn', 'errors'};
  return {
    for (final e in full.entries)
      if (!heavy.contains(e.key)) ...{
        e.key: e.key == 'kind' ? 'diagnostics-summary' : e.value,
        if (e.key == 'checks') 'errors': errorsOut,
        // Αμέσως μετά το είδος: τι είναι αυτό το αρχείο και τι ΔΕΝ έχει.
        if (e.key == 'kind') ...{
          'oura': 'omitted',
          'omitted': omitted,
          'about': 'Σύνοψη της «Αναφοράς για έλεγχο»: χωρίς τα δεδομένα του Oura και χωρίς ό,τι μετρά το ρολόι πάνω στις ώρες '
              'ύπνου του (οξυγόνο νύχτας, παλμοί μέρας, ηρεμίας και περπατήματος, ζώνη περπατήματος), χωρίς το πλήρες '
              'ημερολόγιο φαγητού και χωρίς τους παλμούς των προπονήσεων. Το «omitted» λέει τι έμεινε έξω· το πλήρες αρχείο '
              '(.json.gz) τα έχει.',
        },
      },
    'calc': calc,
    'shown': shown,
    'data': data,
  };
}

Object? _tryJson(String s) {
  try {
    return jsonDecode(s);
  } catch (_) {
    return s;
  }
}
