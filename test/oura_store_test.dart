// Η εφαρμογή ολόκληρη (HealthStore + Oura), με ψεύτικη πλευρά Android (κανάλια), ψεύτικο HTTP και αποθήκευση:
// σύνδεση, αποσύνδεση και αναίρεση, «ξανά από το ρολόι», σειρά ανάγνωσης, όρια συχνότητας, και οι περιπτώσεις
// του ελέγχου: ρυθμίσεις που δεν διαβάστηκαν (B1), αποσύνδεση την ώρα ανάγνωσης (S5), πρώτη νύχτα (S3).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/oura/oura_api.dart';
import 'package:ygeia_forma/oura/oura_model.dart';
import 'package:ygeia_forma/oura/oura_store.dart';
import 'package:ygeia_forma/plan_file.dart';
import 'package:ygeia_forma/sources.dart';

import 'sample_data.dart';

/// Η πλευρά Android στα κανάλια «ygeia/samsung» και «ygeia/oura».
class FakeAndroid {
  FakeAndroid({required this.now});
  final DateTime now;

  /// «ok», «corrupt» (χαλασμένο αρχείο) ή «read» (δεν διαβάστηκε τώρα).
  String prefsMode = 'ok';
  Map<String, dynamic> prefs = {};
  final days = <String, Map<String, double>>{};
  final savedPrefs = <Map<String, dynamic>>[];
  var saveDaysCalls = 0;

  void install() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('ygeia/samsung'), (call) async {
      final args = call.arguments is Map ? call.arguments as Map : const {};
      switch (call.method) {
        case 'loadPrefs':
          return switch (prefsMode) {
            'corrupt' => '{"ok":false,"kind":"other","message":"χαλασμένο"}',
            'read' => '{"ok":false,"kind":"read"}',
            _ => jsonEncode(prefs),
          };
        case 'savePrefs':
          final j = jsonDecode(args['json'] as String) as Map<String, dynamic>;
          savedPrefs.add(j);
          if (prefsMode == 'ok' || prefsMode == 'corrupt') {
            prefs = j;
          }
          return '{"ok":true}';
        case 'loadDays':
          return jsonEncode({
            'ok': true,
            'days': [for (final e in days.entries) {'date': e.key, 'data': e.value}],
          });
        case 'saveDays':
          saveDaysCalls++;
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
          return '{"ok":false,"kind":"other"}';
      }
      return '{"ok":false}';
    });
    m.setMockMethodCallHandler(const MethodChannel('ygeia/oura'), (call) async {
      if (call.method == 'open') return true;
      return null;
    });
    m.setMockMethodCallHandler(const MethodChannel('ygeia/errors'), (call) async => null);
  }
}

/// Ψεύτικη Oura: νύχτες από το [ouraStart] ως σήμερα. [status] ≠ 200 για σφάλματα. [gate]: καθυστερεί τα GET.
class FakeOura {
  FakeOura({required this.ouraStart, required this.now});
  final DateTime ouraStart;
  final DateTime now;
  int status = 200;
  Completer<void>? gate;
  final calls = <(String, Uri)>[];
  final revoked = <String>[];

  Future<OuraResponse> send(String method, Uri url, {Map<String, String> headers = const {}, String? form}) async {
    calls.add((method, url));
    if (url.path.endsWith('/revoke')) {
      revoked.add(url.queryParameters['access_token'] ?? '');
      return const OuraResponse(200, '{}');
    }
    if (method == 'POST') {
      return OuraResponse(200, jsonEncode({'access_token': 'ACC', 'refresh_token': 'REF', 'expires_in': 86400}));
    }
    if (gate != null) await gate!.future;
    if (status != 200) return OuraResponse(status, '{}');
    final ep = url.pathSegments.last;
    final data = ep == 'sleep' ? sampleOuraSleep(ouraStart, now) : <Map<String, dynamic>>[];
    return OuraResponse(200, jsonEncode({'data': data, 'next_token': null}));
  }

  int get gets => calls.where((c) => c.$1 == 'GET').length;
}

DateTime add(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();
  final today = dayOf(now);
  final ouraStart = add(today, -3);

  OuraTokens tokens() => OuraTokens(access: 'A0', refresh: 'R0', expiresAt: now.add(const Duration(days: 1)).millisecondsSinceEpoch);

  /// Μια εφαρμογή με ψεύτικα κανάλια. [plan]: το αρχείο σχεδίου πηγών (null = δεν υπάρχει).
  ({HealthStore store, FakeAndroid android, FakeOura oura, MemoryVault vault, MemoryPlanFile planFile}) app({
    SourcePlan? plan,
    String planState = 'ok',
    bool withTokens = false,
  }) {
    final android = FakeAndroid(now: now)..install();
    final oura = FakeOura(ouraStart: ouraStart, now: now);
    final vault = MemoryVault();
    if (withTokens) vault.data[vaultTokens] = tokens().toJson();
    final planFile = MemoryPlanFile(plan == null ? null : encodePlanFile(plan, now), planState);
    final store = HealthStore()
      ..planFile = planFile
      ..ouraNightsFile = MemoryNightsFile()
      ..ouraLink = OuraLink(vault: vault, send: oura.send, clientId: 'CID', tokenEndpoint: 'https://api.ouraring.com/oauth/token');
    return (store: store, android: android, oura: oura, vault: vault, planFile: planFile);
  }

  Future<void> boot(HealthStore s) async {
    await s.loadPrefs();
    await s.start();
  }

  // ---------------------------------------------------------------------------
  group('B1: χωρίς ρυθμίσεις ή σχέδιο πηγών δεν γράφεται τίποτα', () {
    test('Ιστορικό διαβασμένο, ρυθμίσεις ΟΧΙ: καμία εγγραφή, καμία κλήση στην Oura', () async {
      final a = app(plan: SourcePlan.samsungOnly.withEra(Source.oura, ouraStart), withTokens: true);
      a.android.prefsMode = 'read';
      a.android.days['2026-01-01'] = {K.steps: 5000};
      await boot(a.store);
      expect(a.store.prefsLoaded, isFalse);
      expect(a.android.saveDaysCalls, 0, reason: 'το ιστορικό δεν γράφεται χωρίς ρυθμίσεις');
      expect(a.android.savedPrefs, isEmpty);
      expect(a.oura.gets, 0);
      // Οι οθόνες δείχνουν το σωστό σχέδιο (από το δικό του αρχείο): καμία νύχτα ρολογιού για τις μέρες του Oura.
      expect(a.store.plan.nightSource(today), Source.oura);
      expect(a.store.data!.nights, isEmpty);
    });

    test('Χαλασμένες ρυθμίσεις, αρχείο σχεδίου εντάξει: το σχέδιο Oura μένει, το αντίγραφό του ξαναγράφεται', () async {
      final a = app(plan: SourcePlan.samsungOnly.withEra(Source.oura, ouraStart), withTokens: true);
      a.android.prefsMode = 'corrupt';
      await boot(a.store);
      expect(a.store.planState, PlanState.ok);
      expect(a.store.plan.ouraFrom, ouraStart);
      expect(a.android.savedPrefs, isNotEmpty);
      expect(SourcePlan.fromJson(a.android.savedPrefs.last['sources']).ouraFrom, ouraStart,
          reason: 'οι προεπιλογές γράφτηκαν ΜΑΖΙ με το σχέδιο');
      // Καμία τιμή νύχτας του ρολογιού για νύχτα του Oura στο ιστορικό.
      for (var d = ouraStart; !d.isAfter(today); d = add(d, 1)) {
        final row = a.android.days[dateKey(d)] ?? const {};
        for (final k in watchNightKeys) {
          expect(row.containsKey(k), isFalse, reason: '$k ${dateKey(d)}');
        }
      }
      expect(a.android.days[dateKey(today)]?[ouraKeys[K.sleepMin]], isNotNull, reason: 'ο ύπνος ήρθε από το Oura');
    });

    test('Χαλασμένες ρυθμίσεις ΚΑΙ χαμένο σχέδιο με δεδομένα Oura: «άγνωστο», κενές νύχτες, τίποτα δεν γράφεται', () async {
      final a = app(plan: null, withTokens: true);
      a.android.prefsMode = 'corrupt';
      a.android.days[dateKey(ouraStart)] = {'o.sleepMin': 420, K.steps: 4000};
      await boot(a.store);
      expect(a.store.planState, PlanState.unknown);
      expect(a.store.plan.nightSource(today), Source.none, reason: 'ποτέ σιωπηλά πίσω στο ρολόι');
      expect(a.store.plan.nightSource(add(ouraStart, -1)), Source.watch);
      expect(a.android.saveDaysCalls, 0);
      expect(a.android.savedPrefs, isEmpty, reason: 'οι προεπιλογές δεν γράφονται πάνω στις ρυθμίσεις');
      expect(a.oura.gets, 0);
      expect(a.store.data!.nights, isEmpty);
      // Ρητή επιλογή του χρήστη: γράφεται το αρχείο και ξαναρχίζουν οι εγγραφές.
      expect(await a.store.recoverPlan(SourcePlan([SourceEra(Source.oura, ouraStart)])), isTrue);
      expect(a.store.planState, PlanState.ok);
      expect(decodePlanFile(a.planFile.content)!.ouraFrom, ouraStart);
    });

    test('Αρχείο σχεδίου χαλασμένο, ρυθμίσεις εντάξει με αντίγραφο: το σχέδιο επανέρχεται και ξαναγράφεται', () async {
      final p = SourcePlan.samsungOnly.withEra(Source.oura, ouraStart);
      final a = app(plan: null, planState: 'error');
      a.android.prefs = {'sources': p.toJson()};
      await boot(a.store);
      expect(a.store.planState, PlanState.ok);
      expect(a.store.plan, p);
      expect(decodePlanFile(a.planFile.content), p);
    });

    test('Χωρίς αρχείο, χωρίς δεδομένα Oura: όπως πάντα (κανένα αρχείο δεν γράφεται)', () async {
      final a = app(plan: null);
      await boot(a.store);
      expect(a.store.planState, PlanState.ok);
      expect(a.store.plan.eras, isEmpty);
      expect(a.planFile.writes, 0);
      expect(a.android.saveDaysCalls, greaterThan(0));
    });
  });

  // ---------------------------------------------------------------------------
  group('Σύνδεση, αποσύνδεση, αναίρεση, «ξανά από το ρολόι»', () {
    test('S3: η πρώτη νύχτα του Oura είναι η επόμενη· η χθεσινή μένει του ρολογιού και δεν σβήνεται', () async {
      final a = app(plan: null);
      await boot(a.store);
      final watchSleep = a.android.days[dateKey(today)]?[K.sleepMin];
      expect(watchSleep, isNotNull, reason: 'η χθεσινή νύχτα του ρολογιού');
      final url = await a.store.ouraLink.begin();
      await a.store.completeOuraLogin('ygeiaforma://oura-callback?code=C&state=${url.queryParameters['state']}');
      expect(a.store.ouraLoginError, isNull);
      expect(a.store.plan.ouraFrom, add(today, 1));
      expect(a.store.plan.nightSource(today), Source.watch);
      expect(a.store.ouraStatus, OuraStatus.starting);
      expect(a.android.days[dateKey(today)]?[K.sleepMin], watchSleep, reason: 'δεν σβήστηκε');
      expect(decodePlanFile(a.planFile.content)!.ouraFrom, add(today, 1), reason: 'πρώτα στο αρχείο');
      // Ανάγνωση σήμερα: τίποτα να διαβαστεί ακόμα (η πρώτη νύχτα είναι αύριο).
      await a.store.syncOura(force: true);
      expect(a.oura.gets, 0);
      // Αποσύνδεση την ίδια μέρα: τίποτα δεν είχε έρθει από το Oura → όλα όπως πριν.
      await a.store.disconnectOura();
      expect(a.store.plan.eras, isEmpty);
      expect(a.vault.data, isEmpty);
    });

    test('Χωρίς γνωστό σχέδιο δεν συνδέεται (ο κωδικός δεν χρησιμοποιείται)', () async {
      final a = app(plan: null, withTokens: false);
      a.android.prefsMode = 'read';
      await boot(a.store);
      await a.store.completeOuraLogin('ygeiaforma://oura-callback?code=C&state=S');
      expect(a.store.ouraLoginError, OuraErrorKind.cancelled);
      expect(a.oura.calls, isEmpty);
    });

    test('Αποσύνδεση με ενεργό Oura: από απόψε χωρίς πηγή· η χθεσινή νύχτα του Oura μένει· αναίρεση· ρολόι ρητά', () async {
      final a = app(plan: SourcePlan.samsungOnly.withEra(Source.oura, ouraStart), withTokens: true);
      await boot(a.store);
      expect(a.android.days[dateKey(today)]?[ouraKeys[K.sleepMin]], isNotNull);
      final before = a.store.plan;
      await a.store.disconnectOura();
      expect(a.vault.data, isEmpty);
      expect(a.oura.revoked, isNotEmpty);
      expect(a.store.plan.nightSource(today), Source.oura, reason: 'η χθεσινή νύχτα μένει του Oura');
      expect(a.store.plan.nightSource(add(today, 1)), Source.none);
      expect(a.store.ouraNightFor(today)?.main, isNotNull);
      // Αναίρεση: το σχέδιο επιστρέφει (για ανάγνωση χρειάζεται νέα σύνδεση).
      await a.store.restorePlan(before);
      expect(a.store.plan, before);
      // Ξανά αποσύνδεση και ρητά ρολόι από απόψε.
      await a.store.disconnectOura();
      await a.store.sleepFromWatchAgain();
      expect(a.store.plan.nightSource(add(today, 1)), Source.watch);
      expect(a.store.plan.changeDates(K.sleepMin), [ouraStart, add(today, 1)]);
    });
  });

  // ---------------------------------------------------------------------------
  group('Ανάγνωση: σειρά, όρια συχνότητας, αποσύνδεση την ώρα ανάγνωσης', () {
    test('Πρώτα το Oura, μετά το ιστορικό της Samsung· μόνο κλειδιά «o.*» για τις νύχτες του Oura', () async {
      final a = app(plan: SourcePlan.samsungOnly.withEra(Source.oura, ouraStart), withTokens: true);
      await boot(a.store);
      expect(a.oura.gets, 3, reason: 'sleep, daily_sleep, daily_readiness μία φορά');
      for (var d = ouraStart; !d.isAfter(today); d = add(d, 1)) {
        final row = a.android.days[dateKey(d)]!;
        expect(row[ouraKeys[K.sleepMin]], isNotNull, reason: dateKey(d));
        for (final k in watchNightKeys) {
          expect(row.containsKey(k), isFalse, reason: '$k ${dateKey(d)}');
        }
      }
      // Οι παλμοί της μέρας του ρολογιού υπολογίστηκαν με τις ώρες ύπνου του Oura (ήρθε πρώτο).
      expect(a.android.days[dateKey(add(today, -1))]?.containsKey(K.dayHr), isTrue);
    });

    test('S7: όριο συχνότητας σε κάθε αποτέλεσμα (και σφάλματα)· «Ενημέρωση τώρα» το πολύ μία φορά το λεπτό', () async {
      final a = app(plan: SourcePlan.samsungOnly.withEra(Source.oura, ouraStart), withTokens: true);
      var clock = now;
      a.store.ouraClock = () => clock;
      a.oura.status = 403;
      await boot(a.store);
      expect(a.store.ouraError, OuraErrorKind.subscription);
      final first = a.oura.gets;
      expect(first, greaterThan(0));
      await a.store.syncOura();
      await a.store.refresh();
      expect(a.oura.gets, first, reason: 'όχι ξανά μετά από σφάλμα, σε κάθε επιστροφή');
      await a.store.syncOuraNow();
      expect(a.oura.gets, first, reason: 'όχι δύο φορές μέσα στο ίδιο λεπτό');
      clock = clock.add(const Duration(minutes: 2));
      a.oura.status = 200;
      await a.store.syncOuraNow();
      expect(a.oura.gets, greaterThan(first));
      expect(a.store.ouraError, isNull);
      final after = a.oura.gets;
      await a.store.syncOura();
      expect(a.oura.gets, after, reason: 'μετά την επιτυχία: όχι πριν από 30 λεπτά');
      clock = clock.add(const Duration(minutes: 31));
      await a.store.syncOura();
      expect(a.oura.gets, greaterThan(after));
    });

    test('S5: αποσύνδεση την ώρα ανάγνωσης: τίποτα από την ανάγνωση δεν κρατιέται, κανένα token δεν μένει', () async {
      final a = app(plan: SourcePlan.samsungOnly.withEra(Source.oura, ouraStart));
      await boot(a.store);
      // Τώρα τα tokens (μετά την εκκίνηση) και ανάγνωση που περιμένει.
      a.vault.data[vaultTokens] = tokens().toJson();
      a.store.ouraLink.reload();
      a.store.ouraHasTokens = true;
      a.oura.gate = Completer<void>();
      final saves = a.android.saveDaysCalls;
      final sync = a.store.syncOura(force: true);
      for (var i = 0; i < 20 && a.oura.gets == 0; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(a.oura.gets, 1);
      await a.store.disconnectOura();
      a.oura.gate!.complete();
      await sync;
      expect(a.vault.data, isEmpty);
      expect(a.store.ouraHasTokens, isFalse);
      expect(a.android.saveDaysCalls, saves, reason: 'καμία εγγραφή από ανάγνωση πριν από την αποσύνδεση');
      expect(a.store.ouraNights, isEmpty);
      expect(a.android.days.values.any((r) => r.keys.any(ouraKeySet.contains)), isFalse);
    });

    test('Πολλές νύχτες (πρώτη ανάγνωση): σε άλλο νήμα, ίδιο αποτέλεσμα', () async {
      final nights = parseOura(sleep: sampleOuraSleep(add(today, -40), now), dailySleep: const [], readiness: const []).nights;
      expect(nights.length, greaterThan(20));
      expect(await ouraRowsOffMain(nights), ouraRows(nights));
    });
  });
}
