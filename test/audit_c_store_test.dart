// Έλεγχος 2, κομμάτι C: η εφαρμογή ολόκληρη (HealthStore) με ψεύτικη πλευρά Android.
// C4 επανανάγνωση με αποθηκευμένη πρόοδο · C9 καινούργια βάση · C11 επαναφορά πηγών · C12 διακοπή αποσύνδεσης.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/oura/oura_api.dart';
import 'package:ygeia_forma/oura/oura_store.dart';
import 'package:ygeia_forma/plan_file.dart';
import 'package:ygeia_forma/sources.dart';

import 'sample_data.dart';

DateTime add(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// Η πλευρά Android στο κανάλι «ygeia/samsung»: ρυθμίσεις και μέρες κρατιούνται ανάμεσα σε «επανεκκινήσεις».
class Android {
  Android(this.now);
  final DateTime now;
  Map<String, dynamic> prefs = {};
  final days = <String, Map<String, double>>{};
  String range = '{"ok":false,"kind":"other"}';
  int? corrupt;
  final rangeCalls = <String>[];

  void install() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('ygeia/samsung'), (call) async {
      final args = call.arguments is Map ? call.arguments as Map : const {};
      switch (call.method) {
        case 'loadPrefs':
          return jsonEncode(prefs);
        case 'savePrefs':
          prefs = jsonDecode(args['json'] as String) as Map<String, dynamic>;
          return '{"ok":true}';
        case 'loadDays':
          return jsonEncode({
            'ok': true,
            'days': [for (final e in days.entries) {'date': e.key, 'data': e.value}],
          });
        case 'saveDays':
          for (final row in jsonDecode(args['json'] as String) as List) {
            final r = row as Map;
            days[r['date'] as String] = {
              for (final e in (r['data'] as Map).entries) e.key as String: (e.value as num).toDouble(),
            };
          }
          return '{"ok":true}';
        case 'dashboard':
          return jsonEncode(sampleDashboardJson(now));
        case 'cachedDashboard':
          return '{}';
        case 'readRange':
          rangeCalls.add('${args['from']}..${args['to']}');
          return range;
        case 'dbStatus':
          return jsonEncode({'ok': true, if (corrupt != null) 'corrupt': corrupt});
      }
      return '{"ok":true}';
    });
    m.setMockMethodCallHandler(const MethodChannel('ygeia/oura'), (call) async => null);
    m.setMockMethodCallHandler(const MethodChannel('ygeia/errors'), (call) async => null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final real = DateTime.now();
  final now = DateTime(real.year, real.month, real.day, 15);
  final today = dayOf(now);

  HealthStore app(Android a, {SourcePlan? plan, MemoryVault? vault}) {
    a.install();
    return HealthStore()
      ..planFile = MemoryPlanFile(plan == null ? null : encodePlanFile(plan, now, at: 1))
      ..ouraNightsFile = MemoryNightsFile()
      ..ouraClock = (() => now)
      ..ouraLink = OuraLink(
        vault: vault ?? MemoryVault(),
        send: (m, u, {headers = const {}, form}) async => const OuraResponse(500, '{}'),
        clientId: 'CID',
      );
  }

  Future<void> settle(HealthStore s) async {
    for (var i = 0; i < 400 && (s.backfilling || s.loading); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  Future<HealthStore> boot(Android a, {SourcePlan? plan, MemoryVault? vault}) async {
    final s = app(a, plan: plan, vault: vault);
    await s.loadPrefs();
    await s.start();
    await settle(s);
    return s;
  }

  group('C4: επανανάγνωση με νέους κανόνες', () {
    test('Η έκδοση αλλάζει μόνο στο τέλος· οι αποτυχίες ανά μήνα μένουν μετά από επανεκκίνηση· μετά από 3 σημειώνεται', () async {
      final a = Android(now)
        ..prefs = {'historyVersion': 2}
        ..days['2020-01-05'] = {K.sleepMin: 400}
        // Η Samsung απαντά, αλλά ο ύπνος δεν διαβάστηκε: αποτυχία του κομματιού (οι παλιές τιμές μένουν).
        ..range = jsonEncode({'ok': true, 'sleep': {'error': 'x'}, 'readAt': now.millisecondsSinceEpoch});
      var s = await boot(a);
      expect(a.prefs['historyVersion'], 2, reason: 'όχι 3 πριν ξαναδιαβαστεί όλο το ιστορικό');
      expect(a.prefs['rereadVersion'], historyRulesVersion);
      expect(s.rereading, isTrue);
      expect(s.analysisPlan.rulesFrom, isNotNull);
      expect(s.analysisPlan.changeDates(K.sleepMin), [s.analysisPlan.rulesFrom]);
      expect(s.analysisPlan.changeDates(K.steps), isEmpty);
      expect(s.plan.rulesFrom, isNull, reason: 'οι οθόνες ύπνου δεν κόβονται');
      final first = (a.prefs['monthFails'] as Map).keys.single;
      expect((a.prefs['monthFails'] as Map)[first], 1);
      // Επανεκκίνηση: η μέτρηση συνεχίζει (πριν: ξανά από 0, και ο μήνας δεν περνούσε ποτέ).
      s.dispose();
      s = await boot(a);
      expect((a.prefs['monthFails'] as Map)[first], 2);
      expect(a.prefs['backfillFrom'], isNull);
      s.dispose();
      s = await boot(a);
      expect(a.prefs['staleMonths'], [first], reason: 'ο μήνας κράτησε τον παλιό ορισμό: σημειώνεται, φαίνεται');
      expect(a.prefs['backfillFrom'], isNotNull, reason: 'μετά από 3 αποτυχίες προχωρά');
      expect(a.days['2020-01-05']![K.sleepMin], 400, reason: 'καμία τιμή δεν χάθηκε');
      expect(a.prefs['historyVersion'], 2);
      s.dispose();
    });

    test('Ολοκλήρωση: όταν φτάσει στην αρχή, η έκδοση γίνεται η νέα και το όριο φεύγει', () async {
      final a = Android(now)
        ..prefs = {
          'historyVersion': 2,
          'rereadVersion': historyRulesVersion,
          'backfillFrom': dateKey(add(today, -HealthStore.historyDays - 1)),
        }
        ..days['2020-01-05'] = {K.sleepMin: 400};
      final s = await boot(a);
      expect(a.prefs['historyVersion'], historyRulesVersion);
      expect(a.prefs.containsKey('rereadVersion'), isFalse);
      expect(s.rereading, isFalse);
      expect(s.analysisPlan.rulesFrom, isNull);
      s.dispose();
    });

    test('Νέα εγκατάσταση (χωρίς ιστορικό): καμία επανανάγνωση, κανένα όριο', () async {
      final a = Android(now);
      final s = app(a);
      await s.loadPrefs();
      await s.start();
      expect(a.prefs['historyVersion'], historyRulesVersion);
      expect(s.rereading, isFalse);
      await settle(s);
      s.dispose();
    });
  });

  group('C9: καινούργια βάση (η παλιά χάλασε)', () {
    test('Το Oura ξαναδιαβάζεται από την αρχή του (90 μέρες και πιο πίσω ανά 90)', () async {
      final plan = SourcePlan.samsungOnly.withEra(Source.oura, add(today, -200));
      final a = Android(now)
        ..prefs = {'historyVersion': historyRulesVersion, 'ouraSyncedTo': dateKey(add(today, -1))}
        ..corrupt = 1234;
      final s = await boot(a, plan: plan);
      expect(a.prefs.containsKey('ouraSyncedTo'), isFalse, reason: 'χωρίς «ως πότε»: ξαναδιαβάζονται 90 μέρες');
      expect(a.prefs['ouraRefetchTo'], dateKey(add(today, -91)));
      final r = s.ouraOlderRange()!;
      expect(r.to, add(today, -91));
      expect(r.from, add(today, -180));
      expect(r.next, add(today, -181));
      s.ouraRefetchTo = dateKey(add(today, -181));
      final r2 = s.ouraOlderRange()!;
      expect(r2.from, add(today, -200), reason: 'όχι πριν από την αρχή του Oura');
      expect(r2.next, isNull);
      s.dispose();
    });

    test('Βλάβη όσο η εφαρμογή είναι ανοιχτή: όλο το ιστορικό της μνήμης γράφεται στη νέα βάση', () async {
      final a = Android(now)..prefs = {'historyVersion': historyRulesVersion};
      for (var i = 40; i < 60; i++) {
        a.days[dateKey(add(today, -i))] = {K.sleepMin: 400.0 + i};
      }
      final s = await boot(a);
      final before = s.history.length;
      // Η Kotlin βρήκε χαλασμένη βάση και άνοιξε καινούργια (άδεια).
      a.days.clear();
      a.corrupt = 5678;
      await s.refresh();
      await settle(s);
      expect(a.days.length, greaterThanOrEqualTo(before));
      expect(a.days[dateKey(add(today, -45))]![K.sleepMin], 445);
      expect(a.prefs['dbReset'], 5678);
      s.dispose();
    });
  });

  group('C11: επαναφορά πηγών από αντίγραφο', () {
    test('Μέρες που η νύχτα άλλαξε πηγή: το οξυγόνο/παλμοί μέρας του άλλου ορισμού φεύγουν, το ιστορικό ξαναδιαβάζεται', () async {
      final x = add(today, -40);
      final a = Android(now)
        ..prefs = {'historyVersion': historyRulesVersion, 'backfillFrom': dateKey(add(today, -4000))};
      a.days[dateKey(add(x, -5))] = {K.spo2Avg: 95, K.dayHr: 70, K.steps: 1000};
      a.days[dateKey(add(x, 5))] = {K.spo2Avg: 94, K.dayHr: 71, K.steps: 2000};
      final s = await boot(a);
      final restored = SourcePlan.samsungOnly.withEra(Source.oura, x);
      expect(await s.restoreSources((plan: encodePlanFile(restored, now, at: 99), log: null)), isTrue);
      expect(a.days[dateKey(add(x, 5))], {K.steps: 2000}, reason: 'νύχτα του Oura: ο ορισμός του ρολογιού δεν μένει');
      expect(a.days[dateKey(add(x, -5))], {K.spo2Avg: 95, K.dayHr: 70, K.steps: 1000});
      expect(s.prefs.backfillFrom, isNull, reason: 'ξαναδιαβάζεται, ώστε να ξαναϋπολογιστούν με τον σωστό ορισμό');
      s.dispose();
    });
  });

  group('C12: αποσύνδεση που διακόπηκε', () {
    test('Σημάδι «αποσυνδέεται» χωρίς tokens στην εκκίνηση: η αποσύνδεση ολοκληρώνεται (από απόψε χωρίς πηγή)', () async {
      final plan = SourcePlan.samsungOnly.withEra(Source.oura, add(today, -3));
      final v = MemoryVault()..data[vaultConnecting] = jsonEncode({'disconnecting': true, 'at': 1});
      final a = Android(now)..prefs = {'historyVersion': historyRulesVersion};
      final s = await boot(a, plan: plan, vault: v);
      expect(s.plan.nightSource(add(today, 1)), Source.none);
      expect(s.plan.nightSource(today), Source.oura, reason: 'η χθεσινή νύχτα του Oura μένει');
      expect(v.data.containsKey(vaultConnecting), isFalse);
      s.dispose();
    });
  });

  test('C12: παλιές τιμές του Oura (ποσοστά φάσεων της #66) ξαναδιαβάζονται από την αρχή του Oura, μία φορά', () async {
    final plan = SourcePlan.samsungOnly.withEra(Source.oura, add(today, -120));
    final a = Android(now)..prefs = {'historyVersion': historyRulesVersion, 'ouraSyncedTo': dateKey(add(today, -1))};
    a.days[dateKey(add(today, -100))] = {'o.deepPct': 18.0, 'o.sleepMin': 420};
    var s = await boot(a, plan: plan);
    expect(a.prefs['ouraRules'], ouraRulesVersion);
    expect(a.prefs.containsKey('ouraSyncedTo'), isFalse);
    expect(a.prefs['ouraRefetchTo'], dateKey(add(today, -91)));
    s.dispose();
    // Δεύτερη εκκίνηση: δεν ξαναγίνεται.
    a.prefs['ouraSyncedTo'] = dateKey(today);
    a.prefs.remove('ouraRefetchTo');
    s = await boot(a, plan: plan);
    expect(a.prefs['ouraSyncedTo'], dateKey(today));
    expect(a.prefs.containsKey('ouraRefetchTo'), isFalse);
    s.dispose();
  });
}
