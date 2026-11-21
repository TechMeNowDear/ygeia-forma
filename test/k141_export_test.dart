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
        'fastFrom': 'fastFrom',
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
      expect(fields.length, greaterThanOrEqualTo(24));
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

    test('K8-R-06: και η «γρήγορη απώλεια» (χωρίς εκτίμηση) κρατά το παράθυρο που κρίθηκε', () {
      // Πριν: wf/wt null· αυτός ο έλεγχος δεν μπορούσε να ξαναελεγχθεί.
      final g = _goals();
      final fast = CheckIn(
          kind: CheckKind.fast,
          goals: g,
          proposal: AdaptProposal(current: g.kcal, target: g.kcal + 150, est: null, fastLoss: true, floored: false),
          kgNow: 82.4,
          fastSlope: -1.104,
          fastDays: 21,
          fastFrom: DateTime(2026, 11, 24),
          fastIntake: 2140.6,
          fastIntakeDays: 18,
          fastTarget: 2160);
      final line = applyCheckIn(fast, DateTime(2026, 12, 15, 8)).log.last.toJson();
      expect((line['d'], line['f'], line['k0'], line['k1'], line['ap']), ('2026-12-15', true, g.kcal, g.kcal + 150, true));
      expect((line['wf'], line['wt'], line['mi'], line['sl'], line['nd'], line['kg'], line['kd']),
          ('2026-11-24', '2026-12-15', 2141, -1.104, 18, 82.4, 'fast'));
      expect((line.containsKey('se'), line.containsKey('nw')), (false, false), reason: 'δεν υπάρχει εκτίμηση');
      expect(checkInJson(fast)['fastFrom'], '2026-11-24');
    });

    test('K8-R-07: έλεγχος παλιότερος από τις 60 μέρες της αναφοράς: η γραμμή του μένει, το βάρος της όχι', () {
      // Πριν: «kg» ως 26 ελέγχους πίσω (περίπου 6 μήνες), ενώ η αναφορά λέει «τις τελευταίες 60 μέρες».
      AdaptLog line(String day, double kg) =>
          AdaptLog(day: day, tdee: 2500, before: 2160, after: 2160, applied: true, kg: kg, kind: 'same', meanIntake: 2160);
      final g = _goals().copyWith(addLog: line('2026-09-07', 86.537)).copyWith(addLog: line('2026-12-07', 83.4));
      final r = diagnosticsFrom(store: _store(goals: g), food: _food(_at), now: _at);
      final stored = (((r['calc'] as Map)['goals'] as Map)['stored'] as Map)['log'] as List;
      expect([for (final x in stored) (x as Map)['d']], ['2026-09-07', '2026-12-07']);
      expect([for (final x in stored) (x as Map)['kg']], [null, 83.4]);
      expect((stored.first as Map)['mi'], 2160, reason: 'μόνο το βάρος βγαίνει');
      final inPrefs = jsonEncode((r['data'] as Map)['prefs']);
      expect(inPrefs, isNot(contains('86.537')));
      expect(jsonEncode(r), isNot(contains('86.537')));
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
      final first = ErrorReporter(dir: dir, post: (_) async => 200);
      await first.report(StateError('δοκιμή αποθήκευσης'), StackTrace.current);
      expect(File('${dir.path}/${ErrorReporter.recentFile}').existsSync(), isTrue);
      await first.flush();
      expect(await first.pending(), 0, reason: 'το αρχείο των τελευταίων σφαλμάτων δεν είναι γεγονός της ουράς');
      expect(File('${dir.path}/${ErrorReporter.recentFile}').existsSync(), isTrue, reason: 'η αποστολή δεν το σβήνει');

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

    test('K8-R-09: σφάλμα την ώρα που διαβάζεται το αρχείο της προηγούμενης εκτέλεσης: τίποτα δεν χάνεται', () async {
      // Πριν: το σφάλμα έγραφε το αρχείο μόνο με τον εαυτό του και τα σφάλματα της προηγούμενης εκτέλεσης χάνονταν.
      final first = ErrorReporter(dir: dir, post: (_) async => 200);
      await first.report(StateError('χθες'), StackTrace.current);
      final next = ErrorReporter(post: (_) async => 200);
      final a = next.configure(dir: dir, release: 'ygeia-forma@0.1.0', device: const {});
      final b = next.report(StateError('σήμερα'), StackTrace.current);
      await Future.wait([a, b]);
      expect([for (final e in next.recentErrors) e['run']], ['previous', null]);
      final saved = jsonDecode(File('${dir.path}/${ErrorReporter.recentFile}').readAsStringSync()) as List;
      expect([for (final e in saved) '${(e as Map)['message']}'.contains('χθες')], [true, false]);
    });

    test('K8-R-10: με κλειστές τις «Αναφορές σφαλμάτων» δεν μένει αρχείο σφαλμάτων στο κινητό', () async {
      // Η πολιτική απορρήτου: «Κλειστές, δεν στέλνεται τίποτα και όσες περίμεναν στο κινητό σβήνονται».
      final r = ErrorReporter(dir: dir, post: (_) async => 200);
      await r.report(StateError('ένα'), StackTrace.current);
      final f = File('${dir.path}/${ErrorReporter.recentFile}');
      expect(f.existsSync(), isTrue);
      expect(await r.setEnabled(false), isTrue);
      expect(f.existsSync(), isFalse, reason: 'το κλείσιμο το σβήνει');
      await r.report(StateError('δύο'), StackTrace.current);
      expect(f.existsSync(), isFalse, reason: 'κλειστές: δεν γράφεται');
      expect(r.recentErrors.length, 2, reason: 'στη μνήμη μένουν, για την αναφορά αυτής της εκτέλεσης');
      final next = ErrorReporter(post: (_) async => 200);
      await next.configure(dir: dir, release: 'ygeia-forma@0.1.0', device: const {}, enabled: false);
      expect(next.recentErrors, isEmpty);
    });

    test('K8-R-08: μία γραμμή για κάθε διαφορετική αποτυχία, με πλήθος· η μόνιμη αποτυχία δεν σβήνει τη σπάνια', () {
      // Πριν: νέα γραμμή κάθε ώρα· 20 ανοίγματα με κλειστή άδεια «Ύπνος» έσβηναν τη σπάνια αποτυχία της προηγούμενης εβδομάδας.
      const h = failedLogRepeatMs;
      final log = <List<Object>>[];
      expect(noteFailedRead(log, 'heart', 1000), isTrue);
      expect(noteFailedRead(log, 'sleep', 2000), isTrue);
      expect(noteFailedRead(log, 'sleep', 2000 + h - 1), isFalse, reason: 'μέσα στην ώρα: καμία εγγραφή');
      for (var i = 1; i <= 30; i++) {
        expect(noteFailedRead(log, 'sleep', 2000 + i * h), isTrue);
      }
      expect(log, [
        [1000, 'heart'],
        [2000, 'sleep', 31, 2000 + 30 * h],
      ]);
      // Δύο αποτυχίες που εναλλάσσονται μέσα στην ώρα: καμία εγγραφή (πριν: εγγραφή σε κάθε ανανέωση).
      expect(noteFailedRead(log, 'heart', 1010), isFalse);
      expect(noteFailedRead(log, 'sleep', 2000 + 30 * h + 10), isFalse);
      expect(failedLogFromJson(jsonDecode(jsonEncode(log))), log, reason: 'ξαναδιαβάζεται ίδιο από τις ρυθμίσεις');
      final many = <List<Object>>[];
      for (var i = 0; i < 25; i++) {
        noteFailedRead(many, 'k$i', i);
      }
      expect((many.length, many.first[1], many.last[1]), (failedLogMax, 'k5', 'k24'));
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
      // Και οι τιμές του ρολογιού που μετριούνται πάνω στις ώρες ύπνου του Oura (εδώ κάθε μέρα έχει τιμές του δαχτυλιδιού).
      final fullRows = ((full['data'] as Map)['history'] as Map).values.cast<Map>().toList();
      expect(fullRows.any((row) => row.keys.any(definitionMetrics.contains)), isTrue, reason: 'το πλήρες αρχείο τις έχει');
      expect(rows.any((row) => row.keys.any(definitionMetrics.contains)), isFalse);
      final moveShown = (((sum['shown'] as Map)['kinds'] as Map)['move'] as Map)['m'] as Map;
      expect(moveShown.containsKey('dayHr'), isFalse);
      expect(((sum['shown'] as Map)['kinds'] as Map).keys, containsAll(['move', 'food', 'body']));
      // Και λέει ΤΙ έμεινε έξω (ονόματα πεδίων, όχι τιμές).
      final omitted = (sum['omitted'] as List).join(' | ');
      for (final what in ['data.history: ', 'o.hrv', 'calc.hrv', 'calc.zone: restHrUsed, zone', 'shown.kinds.sleep']) {
        expect(omitted, contains(what));
      }
    });

    test('σύνοψη: και οι τιμές του ρολογιού που μετριούνται πάνω στις ώρες ύπνου του Oura μένουν έξω, μόνο τις μέρες με δαχτυλίδι',
        () {
      // Πριν (πρώτη μορφή της σύνοψης): οξυγόνο νύχτας και παλμοί μέρας/ηρεμίας/περπατήματος έμεναν μέσα· η τιμή είναι του
      // ρολογιού, αλλά το ποιες ώρες μετρούν το ορίζει ο ύπνος του Oura.
      final full = <String, dynamic>{
        'app': 'ygeia-forma',
        'kind': 'diagnostics',
        'window': {'days': 60, 'from': '2026-10-16', 'to': '2026-12-14'},
        'ouraIn': ['data.history: o.*', 'shown.kinds.move.m.dayHr'],
        'checks': <Object>[],
        'errors': <Object>[],
        'calc': {
          'zone': {
            'restHrUsed': 58.0,
            'restSrc': 'watch',
            'age': 44,
            'zone': {'lo': 106, 'hi': 124},
          },
        },
        'shown': {
          'kinds': {
            'move': {
              'src': 'Samsung · 08:20',
              'm': {
                'steps': {'v': '5.120'},
                'dayHr': {'v': '75'},
              },
            },
          },
        },
        'data': {
          'history': {
            '2026-12-10': {
              K.steps: 8000.0,
              K.restHr: 60.0,
              K.dayHr: 75.0,
              K.walkHr: 98.0,
              K.spo2Avg: 95.0,
              K.spo2Min: 90.0,
              K.spo2Low: 2.0,
              K.spo2Cov: 0.9,
            },
            '2026-12-13': {K.steps: 9000.0, K.restHr: 61.0, K.dayHr: 76.0, K.spo2Avg: 96.0, K.spo2Cov: 0.8, 'o.sleepMin': 400.0},
          },
        },
      };
      final sum = diagnosticsSummary(full);
      final rows = (sum['data'] as Map)['history'] as Map;
      // Μέρα χωρίς δαχτυλίδι, και όχι παραμονή νύχτας του: όλα του ρολογιού μένουν (τις ώρες τις ορίζει ο ύπνος του ρολογιού).
      expect((rows['2026-12-10'] as Map).keys.toSet(),
          {K.steps, K.restHr, K.dayHr, K.walkHr, K.spo2Avg, K.spo2Min, K.spo2Low, K.spo2Cov});
      // Μέρα με δαχτυλίδι: μένει μόνο ό,τι δεν εξαρτάται από τις ώρες ύπνου του.
      expect((rows['2026-12-13'] as Map).keys.toSet(), {K.steps});
      final zone = (sum['calc'] as Map)['zone'] as Map;
      expect((zone.containsKey('restHrUsed'), zone.containsKey('zone'), zone['age']), (false, false, 44));
      final m = (((sum['shown'] as Map)['kinds'] as Map)['move'] as Map)['m'] as Map;
      expect(m.keys.toSet(), {'steps'});
      final omitted = (sum['omitted'] as List).join(' | ');
      for (final what in ['restHr', 'dayHr', 'spo2Avg', 'spo2Cov', 'o.sleepMin', 'calc.zone: restHrUsed, zone', 'shown.kinds.move.m.dayHr']) {
        expect(omitted, contains(what));
      }
      // Το πλήρες αρχείο δεν αλλάζει.
      expect(((full['data'] as Map)['history'] as Map)['2026-12-13'], containsPair(K.restHr, 61.0));
    });

    test('σύνοψη, ανεξάρτητος έλεγχος (K8-R-01…05): γράφημα 7 νυχτών, παραμονή νύχτας Oura, προπόνηση σε εξέλιξη, ζώνη που όρισες, ψηφία σφαλμάτων',
        () {
      // Πριν: (1) ο «Ύπνος» έμενε όταν η ΤΕΛΕΥΤΑΙΑ νύχτα ήταν του ρολογιού, με γράφημα 7 νυχτών που είχε νύχτες του Oura·
      // (2) οι παλμοί της παραμονής μιας νύχτας Oura έμεναν· (3) «current», «bad», «drop», «zt» των προπονήσεων έμεναν·
      // (4) η ζώνη «που όρισες» (ζώνη του υπολογισμού ± 5) έμενε· (5) τα μηνύματα σφαλμάτων έμεναν με τους αριθμούς τους.
      final inWindow = DateTime(2026, 12, 12, 18).millisecondsSinceEpoch;
      final full = <String, dynamic>{
        'app': 'ygeia-forma',
        'kind': 'diagnostics',
        'window': {'days': 60, 'from': '2026-10-16', 'to': '2026-12-14'},
        // Κανένα σημάδι για τον «Ύπνο»: η δεύτερη ασφάλεια της σύνοψης πρέπει να φτάνει μόνη της.
        'ouraIn': ['data.history: o.*'],
        'checks': <Object>[],
        'errors': [
          {'type': 'StateError', 'message': 'Bad state: τιμή 61 στη θέση 3', 'screen': 'sleep'},
        ],
        'calc': {
          'zone': {
            'settings': {'lo': 117, 'hi': 136, 'max': 170, 'up': true, 'down': false},
            'restHrUsed': 58.0,
            'restSrc': 'watch',
            'age': 44,
          },
        },
        'shown': {
          'kinds': {
            'sleep': {
              'src': 'ρολόι · 07:10',
              'm': {
                'sleepMin': {
                  'v': '7:05',
                  's': [401.0, 402.0, 403.0, 404.0, 405.0, 420.0, 425.0],
                },
              },
            },
            'move': {
              'm': {
                'steps': {'v': '5.120'},
                'dayHr': {'v': '75'},
              },
            },
          },
        },
        'data': {
          'prefs': {
            'layout': 1,
            'zone': {'lo': 117, 'hi': 136, 'up': true, 'down': false},
          },
          'history': {
            // Παραμονή της νύχτας του Oura: κανένα «o.*», αλλά οι παλμοί της εξαιρούν τον ύπνο που άρχισε το βράδυ της.
            '2026-12-07': {K.steps: 7000.0, K.restHr: 60.0, K.dayHr: 75.0, K.walkHr: 98.0, K.spo2Avg: 95.0},
            '2026-12-08': {K.steps: 8000.0, 'o.sleepMin': 401.0},
            '2026-12-10': {K.steps: 9000.0, K.restHr: 61.0, K.dayHr: 76.0},
          },
          'training': {
            'v': 1,
            'current': {
              'id': 'c',
              'start': inWindow,
              'hr': [
                [0, 101],
                [5, 104],
              ],
              'zlo': 106,
              'zhi': 124,
              'zt': [10, 200, 30],
              'hrAvg': 103,
            },
            'bad': [
              {'in': 'sessions', 'j': {'zlo': 106}},
              {'in': 'sessions', 'j': {'zhi': 124}},
            ],
            'drop': [
              {'id': 'd', 'zlo': 106, 'hr': <Object>[]},
            ],
            'sessions': [
              {'id': 'w', 'start': inWindow, 'zlo': 106, 'zhi': 124, 'zt': [10, 200, 30], 'hrAvg': 101, 'hr': <Object>[]},
            ],
          },
        },
      };
      final sum = diagnosticsSummary(full);
      final omitted = (sum['omitted'] as List).join(' | ');
      // (1) Ο «Ύπνος» βγαίνει ολόκληρος: τιμή του Oura μέσα στις 8 τελευταίες μέρες (8/12, αναφορά 14/12).
      final kinds = (sum['shown'] as Map)['kinds'] as Map;
      expect(kinds.containsKey('sleep'), isFalse);
      expect(omitted, contains('shown.kinds.sleep'));
      // Οι «Παλμοί χθες» μένουν: ούτε χθες ούτε σήμερα έχει νύχτα του Oura.
      expect(((kinds['move'] as Map)['m'] as Map).keys.toSet(), {'steps', 'dayHr'});
      // (2) Παραμονή: οι τρεις παλμοί έξω, το οξυγόνο (της νύχτας που τελείωσε το πρωί της) και τα βήματα μένουν.
      final rows = (sum['data'] as Map)['history'] as Map;
      expect((rows['2026-12-07'] as Map).keys.toSet(), {K.steps, K.spo2Avg});
      expect((rows['2026-12-08'] as Map).keys.toSet(), {K.steps});
      expect((rows['2026-12-10'] as Map).keys.toSet(), {K.steps, K.restHr, K.dayHr}, reason: 'μέρα μακριά από νύχτα Oura');
      // (3) Προπονήσεις.
      final training = (sum['data'] as Map)['training'] as Map;
      expect((training['current'] as Map).keys.toSet(), {'id', 'start', 'hrAvg'});
      expect((training['bad'], training['drop']), (2, 1));
      expect(((training['sessions'] as List).single as Map).keys.toSet(), {'id', 'start', 'hrAvg'});
      // (4) Ζώνη που όρισες: τα όρια έξω, οι υπόλοιπες ρυθμίσεις μένουν.
      final zone = (sum['calc'] as Map)['zone'] as Map;
      expect((zone['settings'] as Map).keys.toSet(), {'max', 'up', 'down'});
      final prefs = (sum['data'] as Map)['prefs'] as Map;
      expect((prefs['zone'] as Map).keys.toSet(), {'up', 'down'});
      expect(prefs['layout'], 1);
      // (5) Σφάλματα: το μήνυμα μένει, χωρίς ψηφία.
      expect(((sum['errors'] as List).single as Map)['message'], 'Bad state: τιμή # στη θέση #');
      final text = jsonEncode(sum);
      for (final leak in ['401', '117', '136', '106', '124', '"zt"', '"zlo"', '"zhi"', '"hr"']) {
        expect(text, isNot(contains(leak)), reason: leak);
      }
      // Το πλήρες αρχείο δεν αλλάζει.
      expect((((full['data'] as Map)['training'] as Map)['current'] as Map).containsKey('hr'), isTrue);
      expect(((full['data'] as Map)['prefs'] as Map)['zone'], containsPair('lo', 117));
    });

    // K8-R-17 (ανεξάρτητος έλεγχος): η δοκιμή «χαρακτηριστική τιμή 61.3777» έπιανε μόνο ωμές τιμές σε ΕΝΑ σχέδιο πηγών (Oura
    // κάθε μέρα): ούτε στρογγυλεμένα παράγωγα, ούτε νύχτα ρολογιού μετά από Oura, ούτε παραμονή σύνδεσης, ούτε αποσύνδεση.
    // Διαφορική δοκιμή: δύο χρήστες ίδιοι σε όλα, που διαφέρουν ΜΟΝΟ σε ό,τι έρχεται από το δαχτυλίδι («o.*») ή ορίζεται από
    // τις ώρες ύπνου του (οξυγόνο νύχτας του ρολογιού· παλμοί μέρας, ηρεμίας, περπατήματος της ίδιας μέρας και της
    // παραμονής· ζώνη περπατήματος των προπονήσεων). Η σύνοψη πρέπει να βγαίνει ΙΔΙΑ, χαρακτήρα προς χαρακτήρα.
    group('K8-R-17: διαφορική δοκιμή: ό,τι αλλάζει μόνο από το Oura δεν αλλάζει τη σύνοψη', () {
      final today = DateTime(_at.year, _at.month, _at.day);
      Map<String, dynamic> training(int lo) => {
            'v': 1,
            'zone': {'lo': lo, 'hi': lo + 18},
            'current': {
              'id': 'c',
              'start': DateTime(2026, 12, 14, 7, 30).millisecondsSinceEpoch,
              'items': <Object>[],
              'zlo': lo,
              'zhi': lo + 18,
              'zt': [lo, 300, 20],
              'hr': [
                [0, lo + 3],
              ],
            },
            'sessions': [
              {
                'id': 'w1',
                'start': DateTime(2026, 12, 12, 18).millisecondsSinceEpoch,
                'items': <Object>[],
                'zlo': lo,
                'zhi': lo + 18,
                'zt': [lo, 900, 60],
                'hrAvg': 104,
              },
            ],
          };

      /// Η πλήρης αναφορά και η σύνοψη ενός χρήστη με σχέδιο πηγών [eras]: κάθε τιμή του δαχτυλιδιού = [oura], και οι τιμές
      /// του ρολογιού που ορίζονται από τις ώρες ύπνου του μετακινημένες κατά [shift].
      (String, String) reports(List<SourceEra> eras, double oura, double shift, {int? zoneLo}) {
        final plan = SourcePlan(eras);
        final s = _store()..debugSetPlan(plan);
        final history = {for (final e in s.history.entries) e.key: {...e.value}};
        for (var i = 0; i < 75; i++) {
          final day = DateTime(today.year, today.month, today.day - i);
          final next = DateTime(day.year, day.month, day.day + 1);
          final row = history.putIfAbsent(dateKey(day), () => <String, double>{});
          final ring = plan.nightSource(day) == Source.oura;
          if (ring) {
            for (final k in ouraKeySet) {
              row[k] = oura;
            }
            for (final k in [K.spo2Avg, K.spo2Min, K.spo2Low, K.spo2Cov]) {
              row[k] = (row[k] ?? 90.0) + shift;
            }
          }
          // Οι παλμοί της μέρας εξαιρούν τον ύπνο που τελείωσε το πρωί της ΚΑΙ αυτόν που άρχισε το βράδυ της.
          if (ring || (!next.isAfter(today) && plan.nightSource(next) == Source.oura)) {
            for (final k in [K.dayHr, K.restHr, K.walkHr]) {
              row[k] = (row[k] ?? 70.0) + shift;
            }
          }
        }
        s.history = history;
        final full = diagnosticsFrom(
            store: s, food: _food(_at), now: _at, training: zoneLo == null ? null : training(zoneLo));
        return (jsonEncode(full), jsonEncode(diagnosticsSummary(full)));
      }

      /// Πού διαφέρουν δύο κείμενα (για το μήνυμα της αποτυχίας).
      String firstDiff(String a, String b) {
        var i = 0;
        while (i < a.length && i < b.length && a.codeUnitAt(i) == b.codeUnitAt(i)) {
          i++;
        }
        if (i == a.length && i == b.length) return 'ίδια';
        final from = i < 200 ? 0 : i - 200;
        String cut(String x) => x.substring(from, i + 80 > x.length ? x.length : i + 80);
        return 'θέση $i:\nΑ: ${cut(a)}\nΒ: ${cut(b)}';
      }

      final plans = <String, List<SourceEra>>{
        'μόνο Oura': [SourceEra(Source.oura, DateTime(2026, 9, 1))],
        'Oura, και πριν από 2 μέρες ξανά ρολόι': [
          SourceEra(Source.oura, DateTime(2026, 9, 1)),
          SourceEra(Source.watch, DateTime(2026, 12, 13)),
        ],
        'Oura, και πριν από 10 μέρες ξανά ρολόι': [
          SourceEra(Source.oura, DateTime(2026, 9, 1)),
          SourceEra(Source.watch, DateTime(2026, 12, 4)),
        ],
        'ρολόι, και από σήμερα Oura (η χθεσινή μέρα είναι παραμονή)': [SourceEra(Source.oura, DateTime(2026, 12, 14))],
        'Oura, και πριν από 5 μέρες αποσύνδεση': [
          SourceEra(Source.oura, DateTime(2026, 9, 1)),
          SourceEra(Source.none, DateTime(2026, 12, 10)),
        ],
      };
      for (final e in plans.entries) {
        test(e.key, () {
          final a = reports(e.value, 61.3777, 0);
          final b = reports(e.value, 47.9191, 3.25);
          expect(a.$1 == b.$1, isFalse, reason: 'οι δύο χρήστες διαφέρουν στο πλήρες αρχείο (αλλιώς η δοκιμή δεν λέει τίποτα)');
          expect(a.$1, contains('61.3777'));
          expect(a.$2 == b.$2, isTrue, reason: firstDiff(a.$2, b.$2));
        });
      }

      test('μόνο Oura, με προπόνηση σε εξέλιξη και άλλη ζώνη περπατήματος (βγαίνει από τους παλμούς ύπνου)', () {
        final a = reports(plans['μόνο Oura']!, 61.3777, 0, zoneLo: 106);
        final b = reports(plans['μόνο Oura']!, 47.9191, 3.25, zoneLo: 101);
        expect(a.$1 == b.$1, isFalse);
        expect(a.$2 == b.$2, isTrue, reason: firstDiff(a.$2, b.$2));
        expect(a.$2, contains('"hrAvg":104'), reason: 'ό,τι μέτρησε το ρολόι στην προπόνηση μένει');
      });
    });

    test('δείγμα αρχείων για τον ελεγκτή Python: build/golden141/export_full.json και export_summary.json', () async {
      // Το CI βγάζει τον φάκελο build/golden141 στο log· ο ελεγκτής (εκτός repo) ξαναϋπολογίζει ΑΝΕΞΑΡΤΗΤΑ ό,τι γράφει το
      // «calc» από τα ακατέργαστα «data» αυτών των δύο αρχείων, όπως θα κάνει με το αρχείο του κινητού. Επινοημένα δεδομένα.
      final v = VitalsStore(io: MemoryVitalsIO());
      await v.load();
      for (var i = 0; i < 6; i++) {
        await v.add(Vital(id: 'x$i', kind: VitalKind.bp, at: DateTime(2026, 12, 11 + i ~/ 2, 7, i), sys: 120 + 4 * (i % 2), dia: 80 + i % 2));
      }
      final full = diagnosticsFrom(store: _store(), food: _food(_at), now: _at, vitals: v, note: 'δείγμα', training: {
        'v': 1,
        'sessions': [
          {'id': 'w1', 'start': DateTime(2026, 12, 12, 18).millisecondsSinceEpoch, 'items': <Object>[], 'hrAvg': 104},
        ],
      });
      final dir = Directory('build/golden141')..createSync(recursive: true);
      File('${dir.path}/export_full.json').writeAsStringSync(diagnosticsEncode(full));
      File('${dir.path}/export_summary.json').writeAsStringSync(diagnosticsEncode(diagnosticsSummary(full)));
      expect((full['kind'], full['v']), ('diagnostics', 2));
    });

    test('K8-R-13 / K8-R-24: το αρχείο βγαίνει και με μη πεπερασμένο αριθμό, και γράφει ό,τι έγραφε το σκέτο jsonEncode', () {
      // Πριν: ένα NaN οπουδήποτε = «Δεν φτιάχτηκε η αναφορά».
      expect(diagnosticsEncode({'x': double.nan, 'y': double.infinity, 'z': 1.5}), '{"x":null,"y":null,"z":1.5}');
      // Αντικείμενο με toJson() γράφεται με το toJson() του, όπως στο σκέτο jsonEncode (όχι «Instance of …»).
      final g = _goals();
      expect(diagnosticsEncode({'g': g}), jsonEncode({'g': g.toJson()}));
      final r = diagnosticsFrom(store: _store(), food: _food(_at), now: _at);
      expect(jsonDecode(diagnosticsEncode(r)), jsonDecode(jsonEncode(r)));
      expect(jsonDecode(diagnosticsEncode(diagnosticsSummary(r))), jsonDecode(jsonEncode(diagnosticsSummary(r))));
    });

    test('K8-R-18 / K8-R-12: ζυγίσεις μόνο πριν από τις 60 μέρες της αναφοράς: «outsideWindow», καμία τιμή τους', () {
      // Πριν: η αντικατάσταση δεν δοκιμαζόταν πουθενά.
      final old = [(DateTime(2026, 9, 1, 8), 86.211), (DateTime(2026, 9, 3, 8), 85.837)];
      final r = diagnosticsFrom(store: _store(weights: old), food: _food(_at), now: _at);
      expect(((r['calc'] as Map)['body'] as Map)['last'], {'outsideWindow': true});
      expect(((r['shown'] as Map)['kinds'] as Map)['body'], {'outsideWindow': true});
      final text = jsonEncode(r);
      expect(text, isNot(contains('86.211')));
      expect(text, isNot(contains('85.837')));
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
