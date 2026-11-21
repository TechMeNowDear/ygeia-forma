// Βαθύς έλεγχος 21/11/2026, κατηγορία 8 («Αναφορά για έλεγχο»): τι γράφει το αρχείο, αν ταιριάζει με τις οθόνες, και η
// «Σύνοψη για τον Claude» (χωρίς καμία τιμή του Oura). Κάθε δοκιμή γράφει τι έβγαινε ΠΡΙΝ.
// Επινοημένα δεδομένα (δημόσιο repo): φανταστικός χρήστης, άνδρας 44 ετών (6/1982), 180 cm, 84,0 kg· πίεση 120/80 και 128/82.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/adaptive.dart';
import 'package:ygeia_forma/adaptive_check.dart';
import 'package:ygeia_forma/body_trend.dart' show guardBody;
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/diagnostics.dart';
import 'package:ygeia_forma/error_report.dart';
import 'package:ygeia_forma/food/food_model.dart' show LogEntry, Meal;
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/goals.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/home_widgets/widget_snapshot.dart' show buildWidgetSnapshot;
import 'package:ygeia_forma/pages/checkin_card.dart' show CheckInSlot;
import 'package:ygeia_forma/pages/diagnostics_sheet.dart';
import 'package:ygeia_forma/profile.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/vitals.dart';

import 'sample_checkin.dart';
import 'sample_data.dart';
import 'sample_food.dart';

const _samsung = MethodChannel('ygeia/samsung');

TestDefaultBinaryMessenger get _messenger => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

// Δευτέρα 14/12/2026, 28η μέρα των στόχων (από Δευτέρα 16/11): μέρα ελέγχου θερμίδων.
final _at = DateTime(2026, 12, 14, 8, 20);
const _me = Profile(birthYear: 1982, birthMonth: 6, sex: 'm', heightCm: 180);

/// Άνδρας 44, 180 cm, 84 kg, «λιγότερο λίπος» 0,5% την εβδομάδα, μέτρια κίνηση: τύπος 1.750 × 1,5 = 2.625, στόχος 2.160.
Goals _goals() => Goals(
    aim: GoalAim.lose, rate: 0.005, activity: 1.5, doctor: true, since: '2026-11-16', kg: 84, age: 44, heightCm: 180, male: true);

List<(DateTime, double)> _weights(DateTime at) => simWeights(at, eat: 2160, tdee: 2500, kg0: 84);

FoodStore _food(DateTime at) => checkinFood(at, eat: 2160);

HealthStore _store({DateTime? at, List<(DateTime, double)>? weights, Map<String, dynamic>? dashboard, Goals? goals}) {
  final now = at ?? _at;
  final s = HealthStore()
    ..data = Dashboard.fromJson(dashboard ?? {...sampleDashboardJson(now), 'body': bodyJson(weights ?? _weights(now))});
  s
    ..history = sampleHistory(now, s.data!)
    ..setProfile(_me)
    ..setGoals(goals ?? _goals());
  return s;
}

Map _adaptive(Map<String, dynamic> r) => (r['calc'] as Map)['adaptive'] as Map;
Map<Object?, Map> _checks(Map<String, dynamic> r) => {for (final c in r['checks'] as List) (c as Map)['id']: c};

/// Μια κάρτα ελέγχου με πρόταση, φτιαγμένη στο χέρι (επινοημένα νούμερα).
CheckIn _proposal(Goals g, {bool tooFast = false}) {
  final est = Expenditure(
      tdee: 2500,
      meanIntake: 2160.4,
      slopeKgWeek: -0.3004,
      intakeDays: 20,
      weighIns: 9,
      from: DateTime(2026, 11, 22),
      to: DateTime(2026, 12, 13),
      seKcal: 61.6);
  return CheckIn(
      kind: CheckKind.proposal,
      goals: g,
      status: AdaptStatus.ok,
      est: est,
      proposal: AdaptProposal(current: g.kcal, target: g.kcal - 100, est: est, fastLoss: false, floored: false),
      kgNow: 83.1,
      days: 20,
      weighs: 9,
      tooFast: tooFast);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // --------------------------------------------------------------------------------------------------------- K8-01
  group('K8-01: η κάρτα ελέγχου της αναφοράς είναι η κάρτα της οθόνης', () {
    test('μέρα ελέγχου με σφάλμα στις ζυγίσεις: «unread», όπως η κάρτα (πριν: «fewData», 0 ζυγίσεις)', () {
      final s = _store(dashboard: {
        ...sampleDashboardJson(_at),
        'body': {'error': 'x'}
      });
      final food = _food(_at);
      expect(CheckInSlot.pendingFor(s, food, _at)!.kind, CheckKind.unread, reason: 'η οθόνη');
      final a = _adaptive(diagnosticsFrom(store: s, food: food, now: _at));
      expect((a['pending'] as Map)['kind'], 'unread');
      expect((a['cardShown'], a['cardWhyNot']), (true, 'none'));
    });

    test('ξένη ζύγιση 45 kg, εκτός μέρας ελέγχου: «foreign» με τη ζύγιση (πριν: pending null)', () {
      final day = DateTime(2026, 12, 9, 9); // Τετάρτη· ο έλεγχος της Δευτέρας 7/12 έχει απαντηθεί
      final child = [for (final (d, kg) in _weights(day)) (d, d.day == 7 && d.month == 12 ? 45.0 : kg)];
      final s = _store(at: day, weights: child, goals: _goals().copyWith(checkIn: '2026-12-07'));
      final food = _food(day);
      final shown = CheckInSlot.pendingFor(s, food, day)!;
      expect(shown.kind, CheckKind.foreign, reason: 'η οθόνη');
      final a = _adaptive(diagnosticsFrom(store: s, food: food, now: day));
      final pending = a['pending'] as Map;
      expect(pending['kind'], 'foreign');
      expect(pending['foreign'], [
        ['2026-12-07', 45.0]
      ]);
      expect(jsonEncode(pending), jsonEncode(checkInJson(shown, estShare: checkInEstShare(shown, food))),
          reason: 'ακριβώς ό,τι δίνει η συνάρτηση της οθόνης');
    });

    test('γιατί δεν βγήκε κάρτα: αντίγραφο παρασκηνίου, ζυγίσεις χωρίς άδεια', () {
      final food = _food(_at);
      final bg = _store(dashboard: {
        ...sampleDashboardJson(_at),
        'body': bodyJson(_weights(_at)),
        'background': true,
      });
      final a = _adaptive(diagnosticsFrom(store: bg, food: food, now: _at));
      expect((a['pending'], a['cardShown'], a['cardWhyNot']), (null, false, 'background'));
      final none = _store(dashboard: {...sampleDashboardJson(_at)}..remove('body'));
      final b = _adaptive(diagnosticsFrom(store: none, food: food, now: _at));
      expect((b['pending'], b['cardWhyNot']), (null, 'bodyNoPermission'));
    });

    test('κάθε πεδίο του CheckIn έχει κλειδί στο «pending» (σπάει όταν προστεθεί πεδίο χωρίς κλειδί)', () {
      // Πεδίο της κάρτας → κλειδί της αναφοράς.
      const keys = {
        'kind': 'kind',
        'goals': 'goalKcal',
        'status': 'status',
        'est': 'est',
        'proposal': 'proposal',
        'kgNow': 'kgNow',
        'fastSlope': 'fastSlopeKgWeek',
        'fastDays': 'fastDays',
        'days': 'days',
        'weighs': 'weighs',
        'tooFast': 'tooFast',
        'heldDays': 'heldDays',
        'quitDays': 'quitHoldDays',
        'gap': 'gap',
        'absurd': 'absurd',
        'foreign': 'foreign',
        'fastIntake': 'fastIntake',
        'fastIntakeDays': 'fastIntakeDays',
        'fastTarget': 'fastTarget',
        'estTarget': 'estTarget',
        'lowLog': 'lowLog',
        'formula': 'formulaTdee',
        'formulaKg': 'formulaKg',
      };
      final src = File('lib/adaptive_check.dart').readAsStringSync();
      final from = src.indexOf('const CheckIn(');
      final ctor = src.substring(from, src.indexOf('});', from));
      final fields = [for (final m in RegExp(r'this\.(\w+)').allMatches(ctor)) m.group(1)!];
      expect(fields.length, greaterThanOrEqualTo(23));
      final g = _goals();
      final base = _proposal(g);
      final full = CheckIn(
          kind: CheckKind.proposal,
          goals: g,
          status: AdaptStatus.ok,
          est: base.est,
          proposal: base.proposal,
          kgNow: 83.1,
          fastSlope: -0.9,
          fastDays: 21,
          days: 20,
          weighs: 9,
          tooFast: true,
          heldDays: 2,
          quitDays: 30,
          gap: (from: DateTime(2026, 11, 24), to: DateTime(2026, 11, 29), restart: DateTime(2026, 11, 30)),
          absurd: [(DateTime(2026, 12, 2), 19710.0)],
          foreign: [(DateTime(2026, 12, 7), 45.0)],
          fastIntake: 1500,
          fastIntakeDays: 10,
          fastTarget: 2100,
          estTarget: 2140,
          lowLog: true,
          formula: 2600,
          formulaKg: 83.5);
      final j = checkInJson(full, estShare: 0.3217);
      for (final f in fields) {
        expect(keys.containsKey(f), isTrue, reason: 'νέο πεδίο «$f» του CheckIn: βάλ\' το στο checkInJson και εδώ');
        expect(j.containsKey(keys[f]), isTrue, reason: 'το πεδίο «$f» δεν γράφεται στην αναφορά');
      }
      expect(j['gap'], ['2026-11-24', '2026-11-29', '2026-11-30']);
      expect(j['absurd'], [
        ['2026-12-02', 19710.0]
      ]);
      expect((j['withinNoise'], j['estShare'], j['quitHoldDays'], j['heldDays']), (false, 0.3217, 30, 2));
      expect((j['est'] as Map)['from'], '2026-11-22');
      jsonEncode(j); // γράφεται σε JSON
    });
  });

  // --------------------------------------------------------------------------------------------------------- K8-02
  group('K8-02: ο έλεγχος που απαντήθηκε κρατά με τι κρίθηκε', () {
    test('«Εφάρμοσε» και «Όχι τώρα»: η γραμμή του ιστορικού έχει παράθυρο, μέσο όρο, κλίση, σφάλμα, πλήθη, βάρος, είδος', () {
      final g = _goals();
      final applied = applyCheckIn(_proposal(g), _at);
      final line = applied.log.last.toJson();
      // Τα παλιά πεδία όπως πριν.
      expect((line['d'], line['te'], line['k0'], line['k1'], line['ap']), ('2026-12-14', 2500.0, g.kcal, g.kcal - 100, true));
      // Πριν: τίποτα από αυτά (μετά την απάντηση ο έλεγχος δεν ξαναελεγχόταν).
      expect((line['wf'], line['wt'], line['mi'], line['sl'], line['se']), ('2026-11-22', '2026-12-13', 2160, -0.3, 62));
      expect((line['nd'], line['nw'], line['kg'], line['kd']), (20, 9, 83.1, 'proposal'));
      expect(line.containsKey('wh'), isFalse, reason: 'κανένας λόγος κρατήματος: το κλειδί δεν γράφεται');
      // Ξαναδιαβάζεται ίδια (ρυθμίσεις, αντίγραφο).
      expect(jsonEncode(Goals.fromJson(applied.toJson())!.log.last.toJson()), jsonEncode(line));
      final no = dismissCheckIn(_proposal(g, tooFast: true), _at).log.last.toJson();
      expect((no.containsKey('ap'), no['kd'], no['wh'], no['wf']), (false, 'proposal', 'tooFast', '2026-11-22'));
    });

    test('παλιό αρχείο: γραμμή χωρίς τα νέα κλειδιά διαβάζεται και γράφεται ίδια· άκυρες τιμές αγνοούνται', () {
      const old = {'d': '2026-12-07', 'te': 2500.0, 'k0': 2160, 'k1': 2160};
      expect(AdaptLog.fromJson(old)!.toJson(), old);
      final odd = AdaptLog.fromJson({...old, 'wf': 'χθες', 'mi': 'x', 'kd': 7, 'sl': '−0,3'})!.toJson();
      expect(odd, old, reason: 'η γραμμή μένει· τα άκυρα προαιρετικά δεν γράφονται');
      const plain = AdaptLog(day: '2026-12-07', tdee: 2500, before: 2160, after: 2160, applied: false);
      expect(plain.toJson().keys.toList(), ['d', 'te', 'k0', 'k1'], reason: 'κανένα κλειδί με null');
    });
  });

  // --------------------------------------------------------------------------------------------------------- K8-03
  group('K8-03: πίεση, σάκχαρο, καρδιογραφήματα στην αναφορά', () {
    test('14 μετρήσεις σε 4 μέρες: όλες στο «data.vitals», ο μέσος όρος 7 ημερών στο «calc.bp»', () async {
      final v = VitalsStore(io: MemoryVitalsIO());
      await v.load();
      var n = 0;
      // 11, 12, 13/12: 4 μετρήσεις τη μέρα· 14/12: 2 (πριν από τις 08:20). Εναλλάξ 120/80 και 128/82.
      for (final (day, count) in [(11, 4), (12, 4), (13, 4), (14, 2)]) {
        for (var i = 0; i < count; i++) {
          final high = n.isOdd;
          expect(
              await v.add(Vital(
                  id: 'b${n++}',
                  kind: VitalKind.bp,
                  at: DateTime(2026, 12, day, 7, i),
                  sys: high ? 128 : 120,
                  dia: high ? 82 : 80)),
              isTrue);
        }
      }
      final r = diagnosticsFrom(store: _store(), food: _food(_at), now: _at, vitals: v);
      expect(((r['data'] as Map)['vitals'] as List).length, 14, reason: 'πριν: το κλειδί δεν υπήρχε');
      expect((r['calc'] as Map)['bp'], {'sys': 124.0, 'dia': 81.0, 'n': 14, 'd': 4});
      final avg = bpAverage(v.all, _at)!;
      expect((avg.n, avg.d), (14, 4), reason: 'η ίδια συνάρτηση με τη σελίδα');
      expect(_checks(r)['vitals-read']!['ok'], isTrue);
      expect(((r['calc'] as Map)['rules'] as Map)['bp'], {'days': 7, 'minDays': bpMinDays, 'minReadings': bpMinReadings});
    });

    test('χωρίς διαβασμένες μετρήσεις: «vitals» null και ο έλεγχος «vitals-read» το λέει', () {
      final r = diagnosticsFrom(store: _store(), food: _food(_at), now: _at);
      expect((r['data'] as Map)['vitals'], isNull);
      expect((r['calc'] as Map)['bp'], isNull);
      expect(_checks(r)['vitals-read']!['ok'], isFalse);
    });
  });

  // --------------------------------------------------------------------------------------------------------- K8-05
  test('K8-05: «shown» = το στιγμιότυπο των widgets την ίδια στιγμή· «calc.body» η ζύγιση της μέρας του Σώματος', () {
    final s = _store();
    final food = _food(_at);
    final r = diagnosticsFrom(store: s, food: food, now: _at);
    final snap = buildWidgetSnapshot(s, food, _at);
    final shown = r['shown'] as Map;
    for (final kind in ['sleep', 'move', 'food', 'body']) {
      expect(jsonEncode((shown['kinds'] as Map)[kind]), jsonEncode((snap['kinds'] as Map)[kind]), reason: kind);
    }
    final body = (r['calc'] as Map)['body'] as Map;
    final last = guardBody(s.data!.body).shown.last;
    expect((body['last'] as Map)['kg'], last.weight);
    expect((body['last'] as Map)['ms'], last.time.millisecondsSinceEpoch);
    expect((body['last'] as Map)['status'], 'counted');
    final week = (r['calc'] as Map)['week'] as Map;
    // Δευτέρα 14/12: η κάρτα «Η εβδομάδα σου» δείχνει την εβδομάδα 7–13/12.
    expect((week['monday'], week['sunday'], week['shownNow']), ('2026-12-07', '2026-12-13', true));
    jsonEncode(r); // όλη η αναφορά γράφεται σε JSON (κανένα NaN)
  });

  // --------------------------------------------------------------------------------------------------------- K8-06
  group('K8-06: ό,τι πήγε στραβά επιζεί από το κλείσιμο της εφαρμογής', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('errq-k8'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('σφάλμα → νέα εκτέλεση με τον ίδιο φάκελο: στην αναφορά με «run: previous» (πριν: errors [])', () async {
      final first = ErrorReporter(dir: dir, post: (_) async => 200)..sending.value = false;
      await first.report(StateError('δοκιμή αποθήκευσης'), StackTrace.current);
      expect(File('${dir.path}/${ErrorReporter.recentFile}').existsSync(), isTrue);
      expect(await first.pending(), 0, reason: 'το αρχείο των τελευταίων σφαλμάτων δεν είναι γεγονός της ουράς');

      final sent = <String>[];
      final next = ErrorReporter(post: (b) async {
        sent.add(b);
        return 200;
      });
      await next.configure(dir: dir, release: 'ygeia-forma@0.1.0', device: const {});
      await next.flush();
      expect(sent, isEmpty, reason: 'δεν στέλνεται ποτέ');
      expect(next.recentErrors.single['run'], 'previous');
      await next.report(StateError('τωρινό'), StackTrace.current);
      expect([for (final e in next.recentErrors) e['run']], ['previous', null], reason: 'τα παλιά πρώτα');

      final r = diagnosticsFrom(store: _store(), food: _food(_at), now: _at, reporter: next);
      final errors = r['errors'] as List;
      expect((errors.first as Map)['run'], 'previous');
      expect((errors.first as Map)['message'], contains('δοκιμή αποθήκευσης'));
      expect((errors.last as Map)['atMs'], isA<int>());
    });

    test('οι αποτυχημένες αναγνώσεις της Samsung στις ρυθμίσεις: προαιρετικό κλειδί, ως 20, μόνο ώρα και είδη', () {
      expect(failedLogMax, 20);
      expect(failedLogFromJson(null), isEmpty);
      final p = Prefs.fromJson({
        'failedLog': [
          [1796000000000, 'body,heart'],
          ['x', 1],
          [1, 2, 3],
          'όχι γραμμή',
        ],
      });
      expect(p.failedLog, [
        [1796000000000, 'body,heart']
      ]);
      expect((jsonDecode(p.toJson()) as Map)['failedLog'], [
        [1796000000000, 'body,heart']
      ]);
      expect((jsonDecode(Prefs.fromJson(const {}).toJson()) as Map).containsKey('failedLog'), isFalse,
          reason: 'παλιό αρχείο: άδειο, και δεν γράφεται');
      final s = _store()..prefs.failedLog.add(<Object>[1796000000000, 'sleep']);
      final r = diagnosticsFrom(store: s, food: _food(_at), now: _at);
      expect((r['env'] as Map)['samsungFailedLog'], [
        [1796000000000, 'sleep']
      ]);
    });
  });

  // --------------------------------------------------------------------------------------------------------- K8-07
  test('K8-07: αποθήκευση ιστορικού που απέτυχε → «history-saved» false με τη μέρα (πριν: όλοι οι έλεγχοι ok)', () async {
    _messenger.setMockMethodCallHandler(
        _samsung, (call) async => call.method == 'saveDays' ? '{"ok":false,"kind":"io"}' : '{"ok":true}');
    addTearDown(() => _messenger.setMockMethodCallHandler(_samsung, null));
    final s = _store();
    final food = _food(_at);
    final before = _checks(diagnosticsFrom(store: s, food: food, now: _at));
    expect((before['history-saved']!['ok'], before['prefs-saved']!['ok']), (true, true));
    expect(await s.saveDaysNow({'2026-12-13'}), isFalse);
    expect(s.unsavedDays, {'2026-12-13'});
    final after = _checks(diagnosticsFrom(store: s, food: food, now: _at))['history-saved']!;
    expect((after['ok'], after['detail'], after['n']), (false, '2026-12-13', 1));
  });

  // --------------------------------------------------------------------------------------------------------- K8-08
  group('K8-08: σειρά κλειδιών και «Σύνοψη για τον Claude»', () {
    test('πλήρες αρχείο: «checks» και «calc» πριν από το ημερολόγιο φαγητού (πριν: το «data» πρώτο)', () {
      final text = jsonEncode(diagnosticsFrom(store: _store(), food: _food(_at), now: _at));
      final checks = text.indexOf('"checks"'), calc = text.indexOf('"calc"'), shown = text.indexOf('"shown"');
      final data = text.indexOf('"data"'), log = text.indexOf('"foodLog"');
      expect(checks, greaterThan(0));
      expect([checks, calc, shown, data, log], [checks, calc, shown, data, log]..sort(), reason: 'με αυτή τη σειρά');
      expect(diagnosticsVersion, 2);
      expect(diagnosticsFileName(_at), 'ygeia-elegxos-2026-12-14-0820.json.gz');
      expect(diagnosticsSummaryFileName(_at), 'ygeia-elegxos-2026-12-14-0820-synopsi.json');
    });

    test('σύνοψη: ίδια σειρά, χωρίς foodLog/myFoods/παλμούς, φαγητό 60 ημερών σε λεπτή μορφή που δίνει τα ίδια σύνολα', () {
      final food = _food(_at);
      final full = diagnosticsFrom(store: _store(), food: food, now: _at, training: {
        'v': 1,
        'sessions': [
          {'id': 's-old', 'start': DateTime(2026, 9, 1, 18).millisecondsSinceEpoch, 'items': <Object>[]},
          {
            'id': 's-new',
            'start': DateTime(2026, 12, 12, 18).millisecondsSinceEpoch,
            'items': <Object>[],
            'hr': [
              [0, 97]
            ]
          },
        ],
        'hrz': {'s-new': 'AAAA'},
      });
      final before = jsonEncode(full);
      final sum = diagnosticsSummary(full);
      expect(jsonEncode(full), before, reason: 'η σύνοψη δεν αλλάζει την πλήρη αναφορά');
      expect((sum['kind'], sum['oura'], sum['v']), ('diagnostics-summary', 'omitted', diagnosticsVersion));
      final keys = sum.keys.toList();
      expect(keys.sublist(0, 4), ['app', 'kind', 'oura', 'omitted']);
      expect([keys.indexOf('checks'), keys.indexOf('errors'), keys.indexOf('calc'), keys.indexOf('shown'), keys.indexOf('data')],
          [for (var i = keys.length - 5; i < keys.length; i++) i],
          reason: 'checks → errors → calc → shown → data, στο τέλος');
      final data = sum['data'] as Map;
      expect((data.containsKey('foodLog'), data.containsKey('myFoods')), (false, false));
      expect(data.keys.last, 'food', reason: 'τα βαριά τελευταία');
      final training = data['training'] as Map;
      expect(training.containsKey('hrz'), isFalse);
      expect([for (final x in training['sessions'] as List) (x as Map)['id']], ['s-new'], reason: 'μόνο των 60 ημερών');
      expect(((training['sessions'] as List).single as Map).containsKey('hr'), isFalse);
      expect(training['trainingOlder'], 1, reason: 'γράφει πόσες έμειναν έξω');
      // Λεπτή μορφή: κάθε τρόφιμο μία φορά, και τα σύνολα της μέρας βγαίνουν ίδια με το «calc.days».
      final thin = data['food'] as Map;
      final foods = thin['foods'] as Map;
      final entries = (thin['entries'] as List).cast<Map>();
      expect(entries.length, ((full['data'] as Map)['foodLog'] as List).length);
      expect(foods.length, 2, reason: 'ψωμί και γιαούρτι, μία φορά το καθένα');
      final day = (((full['calc'] as Map)['days'] as List).cast<Map>()).firstWhere((d) => d['d'] == '2026-12-13');
      var kcal = 0.0;
      for (final e in entries.where((e) => e['day'] == '2026-12-13')) {
        final n = (foods[e['f']] as Map)['n'] as Map;
        kcal += (e['grams'] as num) * (n['kcal'] as num) / 100;
      }
      expect(kcal, closeTo((day['kcal'] as num).toDouble(), 0.06));
      expect(sum['omitted'], containsAll(['data.foodLog', 'data.myFoods', 'data.training.hrz']));
    });

    test('ημερολόγιο 365 ημερών: η σύνοψη κάτω από 300.000 χαρακτήρες και λέει πόσες καταχωρίσεις έμειναν έξω', () {
      // Το ημερολόγιο όπως έρχεται από τον δίσκο: 365 μέρες × 3 καταχωρίσεις (επινοημένες).
      final bread = foodNamed('Ψωμί ολικής άλεσης');
      final log = [
        for (var k = 365; k >= 1; k--)
          for (final h in const [9, 14, 20])
            Map<String, dynamic>.from(LogEntry(
                    id: 'y$k-$h',
                    day: dateKey(DateTime(_at.year, _at.month, _at.day - k)),
                    meal: Meal.lunch,
                    food: bread,
                    grams: 250,
                    time: DateTime(_at.year, _at.month, _at.day - k, h))
                .toJson()),
      ];
      expect(log.length, 1095);
      final full = diagnosticsFrom(store: _store(), food: _food(_at), now: _at, foodLog: log, myFoods: const []);
      final text = jsonEncode(full);
      expect(text.indexOf('"calc"'), lessThan(text.indexOf('"foodLog"')));
      final sum = diagnosticsSummary(full);
      expect(jsonEncode(sum).length, lessThan(300000));
      final kept = (((sum['data'] as Map)['food'] as Map)['entries'] as List).length;
      expect(kept, 180, reason: '60 μέρες × 3 καταχωρίσεις (από 15/10)');
      expect((sum['omitted'] as List).any((x) => '$x'.startsWith('data.food: ${log.length - kept} ')), isTrue);
    });

    test('η σύνοψη ΔΕΝ έχει καμία τιμή του Oura (χαρακτηριστική τιμή 61.3777 σε κάθε πεδίο του δαχτυλιδιού)', () {
      final s = _store()..debugSetPlan(SourcePlan([SourceEra(Source.oura, DateTime(2026, 9, 1))]));
      // Κάθε τιμή του Oura = 61.3777, για 75 νύχτες· η κάλυψη οξυγόνου (πάνω στις ώρες ύπνου του Oura) = 0.613777.
      final history = {for (final e in s.history.entries) e.key: {...e.value}};
      for (var i = 0; i < 75; i++) {
        final row = history.putIfAbsent(dateKey(DateTime(_at.year, _at.month, _at.day - i)), () => <String, double>{});
        for (final k in ouraKeySet) {
          row[k] = 61.3777;
        }
        row[K.spo2Cov] = 0.613777;
      }
      s.history = history;
      // Και μια προπόνηση με όρια ζώνης (βγαίνουν από τους παλμούς ηρεμίας, που εδώ είναι του δαχτυλιδιού).
      final full = diagnosticsFrom(store: s, food: _food(_at), now: _at, training: {
        'v': 1,
        'zone': {'lo': 106, 'hi': 124},
        'sessions': [
          {'id': 'w1', 'start': DateTime(2026, 12, 12, 18).millisecondsSinceEpoch, 'items': <Object>[], 'zlo': 106, 'zhi': 124},
        ],
      });
      final fullText = jsonEncode(full);
      // Η πλήρης αναφορά τα έχει (απόφαση χρήστη· η οθόνη το λέει)…
      expect(fullText, contains('61.3777'));
      expect(full['ouraIn'], containsAll(['data.history: o.*', 'calc.hrv', 'shown.kinds.sleep']));
      expect(((full['calc'] as Map)['zone'] as Map)['restSrc'], 'oura');
      // …η σύνοψη όχι.
      final sum = diagnosticsSummary(full);
      final text = jsonEncode(sum);
      expect(text, isNot(contains('61.3777')));
      expect(text, isNot(contains('613777')));
      expect(RegExp(r'"o\.[A-Za-z0-9]+"\s*:').hasMatch(text), isFalse, reason: 'κανένα κλειδί «o.*»');
      expect(sum['oura'], 'omitted');
      final calc = sum['calc'] as Map;
      expect(calc.containsKey('hrv'), isFalse);
      expect((calc['zone'] as Map).containsKey('restHrUsed'), isFalse);
      expect((calc['zone'] as Map).containsKey('zone'), isFalse);
      expect(((sum['shown'] as Map)['kinds'] as Map).containsKey('sleep'), isFalse);
      final training = (sum['data'] as Map)['training'] as Map;
      final walk = (training['sessions'] as List).single as Map;
      expect((training.containsKey('zone'), walk.containsKey('zlo'), walk.containsKey('zhi'), walk['id']), (false, false, false, 'w1'));
      expect([for (final it in (calc['week'] as Map)['items'] as List) (it as Map)['src']], everyElement(isNot('oura')));
      // Ό,τι δεν είναι του δαχτυλιδιού μένει: βήματα του ιστορικού, κίνηση, φαγητό, σώμα.
      final rows = ((sum['data'] as Map)['history'] as Map).values.cast<Map>().toList();
      expect(rows.any((row) => row.keys.any((k) => '$k'.startsWith('o.'))), isFalse);
      expect(rows.any((row) => row.containsKey(K.steps)), isTrue, reason: 'τα βήματα (Samsung) μένουν');
      expect(((sum['shown'] as Map)['kinds'] as Map).keys, containsAll(['move', 'food', 'body']));
      // Και λέει ΤΙ έμεινε έξω (ονόματα πεδίων, όχι τιμές).
      final omitted = (sum['omitted'] as List).join(' | ');
      for (final what in ['data.history: ', 'o.hrv', 'calc.hrv', 'calc.zone: restHrUsed, zone', 'shown.kinds.sleep']) {
        expect(omitted, contains(what));
      }
    });

    testWidgets('οθόνη: δεύτερο κουμπί «Σύνοψη για τον Claude» → αρχείο «…-synopsi.json», απλό JSON, χωρίς Oura', (t) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(400, 1600);
      addTearDown(t.view.reset);
      String? saved;
      String? name;
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: DiagnosticsSheet(
            store: _store(),
            food: _food(_at),
            vitals: VitalsStore(io: MemoryVitalsIO()),
            save: (json, n) async {
              saved = json;
              name = n;
              return {'ok': true, 'uri': 'content://x', 'name': n};
            },
          ),
        ),
      ));
      // Το παλιό κουμπί μένει όπως ήταν, και από κάτω το νέο με τη μία γραμμή του.
      expect(find.text('Φτιάξε και στείλε'), findsOneWidget);
      expect(find.text('Σύνοψη για τον Claude'), findsOneWidget);
      expect(find.text(diagnosticsSummaryText), findsOneWidget);
      expect(diagnosticsSummaryText, 'Μικρό αρχείο, χωρίς τα δεδομένα του Oura. Αυτό δίνεις στον Claude.');
      expect(t.getTopLeft(find.byKey(const ValueKey('diag-summary'))).dy,
          greaterThan(t.getBottomLeft(find.byKey(const ValueKey('diag-make'))).dy));
      await t.tap(find.byKey(const ValueKey('diag-summary')));
      // Οι κλήσεις προς το Android (που εδώ δεν υπάρχει) τελειώνουν σε πραγματικό χρόνο, όχι στο ψεύτικο ρολόι της δοκιμής.
      for (var i = 0; i < 50 && name == null; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await t.pump();
      }
      await t.pumpAndSettle();
      expect(name, startsWith('ygeia-elegxos-'));
      expect(name, endsWith('-synopsi.json'), reason: 'όχι «.gz»: το Android το γράφει ως application/json');
      final j = jsonDecode(saved!) as Map;
      expect((j['kind'], j['oura']), ('diagnostics-summary', 'omitted'));
      expect((j['data'] as Map).containsKey('foodLog'), isFalse);
      expect(find.byKey(const ValueKey('diag-result')), findsOneWidget);
      expect(find.textContaining('Δεν έχει τα δεδομένα του Oura.'), findsOneWidget);
    });

    test('Android: όνομα χωρίς «.gz» γράφεται ασυμπίεστο ως application/json (BackupFiles.kt)', () {
      final kt = File('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/BackupFiles.kt').readAsStringSync();
      expect(kt, contains('val gz = fileName.endsWith(".gz")'));
      expect(kt, contains('if (gz) "application/gzip" else "application/json"'));
    });
  });

  // ------------------------------------------------------------------------------------------- K8-13, K8-14, K8-15
  group('μικρά: ώρες σε ms, πλήθη στις περικοπές, σταθερές κανόνων', () {
    test('K8-13: ώρα αναφοράς, ανάγνωσης και κάθε ζύγισης και σε ms', () {
      final s = _store();
      final r = diagnosticsFrom(store: s, food: _food(_at), now: _at);
      expect(r['createdMs'], _at.millisecondsSinceEpoch);
      final samsung = (r['data'] as Map)['samsung'] as Map;
      expect(samsung['readAtMs'], s.data!.readAt.millisecondsSinceEpoch);
      final body = (samsung['body'] as List).cast<Map>();
      expect(body, isNotEmpty);
      for (final b in body) {
        expect(b['ms'], DateTime.parse(b['t'] as String).millisecondsSinceEpoch);
      }
      expect(r['window'], {'days': diagnosticsDays, 'from': '2026-10-15', 'to': '2026-12-14'});
    });

    test('K8-14: 25 διπλές καταχωρίσεις → «n» 25 και 20 στη λεπτομέρεια (πριν: μόνο οι 20, χωρίς το σύνολο)', () {
      final day = DateTime(2026, 12, 13, 13);
      final bread = foodNamed('Ψωμί ολικής άλεσης');
      final food = FoodStore.preloaded(foods: basicFoods(), now: _at, entries: [
        for (var i = 0; i < 26; i++)
          LogEntry(id: 'd$i', day: dateKey(day), meal: Meal.lunch, food: bread, grams: 60, time: day),
      ]);
      final dup = _checks(diagnosticsFrom(store: _store(), food: food, now: _at))['food-duplicates']!;
      expect((dup['ok'], dup['n']), (false, 25));
      expect((dup['detail'] as String).split('; ').length, 20);
      final fine = _checks(diagnosticsFrom(store: _store(), food: _food(_at), now: _at))['food-duplicates']!;
      expect(fine.containsKey('n'), isFalse);
    });

    test('K8-14: ρύθμιση που δεν μπαίνει στην αναφορά: το ΟΝΟΜΑ της στο «prefsDropped», ποτέ η τιμή', () async {
      _messenger.setMockMethodCallHandler(_samsung, (call) async {
        if (call.method == 'loadPrefs') return jsonEncode({'reportName': 'Δοκιμή Όνομα', 'themeMode': 'dark'});
        return '{"ok":true}';
      });
      addTearDown(() => _messenger.setMockMethodCallHandler(_samsung, null));
      final s = HealthStore()..data = Dashboard.fromJson({...sampleDashboardJson(_at), 'body': bodyJson(_weights(_at))});
      s.history = sampleHistory(_at, s.data!);
      await s.loadPrefs();
      s
        ..setProfile(_me)
        ..setGoals(_goals());
      final r = diagnosticsFrom(store: s, food: _food(_at), now: _at);
      final data = r['data'] as Map;
      expect(data['prefsDropped'], ['reportName']);
      expect((data['prefs'] as Map).containsKey('reportName'), isFalse);
      expect(jsonEncode(r).contains('Δοκιμή Όνομα'), isFalse);
    });

    test('K8-15: οι σταθερές των κανόνων είναι στο αρχείο και ίδιες με του κώδικα', () {
      final rules = diagnosticsRules();
      final adapt = rules['adapt'] as Map;
      expect(adapt['fullDayShare'], adaptFullDayShare);
      expect((adapt['skipDays'], adapt['windows'], adapt['maxStep']), (adaptSkipDays, adaptWindows, adaptMaxStep));
      expect((adapt['minIntakeDays'], adapt['minWeighIns'], adapt['guardSe']), (adaptMinIntakeDays, adaptMinWeighIns, adaptGuardSe));
      expect((adapt['lowShare'], adapt['highShare'], adapt['quitHoldDays']), (adaptLowShare, adaptHighShare, smokeQuitHoldDays));
      final r = diagnosticsFrom(store: _store(), food: _food(_at), now: _at);
      expect(jsonEncode((r['calc'] as Map)['rules']), jsonEncode(rules));
      expect(r['v'], 2);
    });
  });
}
