// Η εφαρμογή ολόκληρη (HealthStore + Oura), με ψεύτικη πλευρά Android (κανάλια), ψεύτικο HTTP και αποθήκευση:
// σύνδεση, αποσύνδεση και αναίρεση, «ξανά από το ρολόι», σειρά ανάγνωσης, όρια συχνότητας, και οι περιπτώσεις
// του ελέγχου: ρυθμίσεις που δεν διαβάστηκαν (B1), αποσύνδεση την ώρα ανάγνωσης (S5), πρώτη νύχτα (S3, S-D),
// σφάλμα μετά από επανεκκίνηση (S-A), αποσύνδεση μετά από «ρολόι» (S-B), επαναφορά σχεδίου (S-E, M-1/2/3).
// Σταθερό ρολόι: σήμερα στις 15:00 (εκτός αν μια δοκιμή ορίζει άλλη ώρα).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/oura/config.dart';
import 'package:ygeia_forma/oura/oura_api.dart';
import 'package:ygeia_forma/oura/oura_model.dart';
import 'package:ygeia_forma/oura/oura_store.dart';
import 'package:ygeia_forma/oura/oura_view.dart';
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
  bool noData = false;
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
    final data = ep == 'sleep' && !noData ? sampleOuraSleep(ouraStart, now) : <Map<String, dynamic>>[];
    return OuraResponse(200, jsonEncode({'data': data, 'next_token': null}));
  }

  int get gets => calls.where((c) => c.$1 == 'GET').length;
}

DateTime add(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final real = DateTime.now();
  final now = DateTime(real.year, real.month, real.day, 15);
  final today = dayOf(now);
  final ouraStart = add(today, -3);

  OuraTokens tokens() => OuraTokens(access: 'A0', refresh: 'R0', expiresAt: now.add(const Duration(days: 1)).millisecondsSinceEpoch);

  /// Μια εφαρμογή με ψεύτικα κανάλια. [plan]: το αρχείο σχεδίου πηγών (null = δεν υπάρχει).
  /// [at]: το «τώρα» της δοκιμής. Για επανεκκίνηση: ίδια [android], [vault], [planFile], [nights], [oura].
  ({HealthStore store, FakeAndroid android, FakeOura oura, MemoryVault vault, MemoryPlanFile planFile, MemoryNightsFile nights})
      app({
    SourcePlan? plan,
    String planState = 'ok',
    bool withTokens = false,
    DateTime Function()? clock,
    DateTime? at,
    FakeAndroid? android,
    FakeOura? oura,
    MemoryVault? vault,
    MemoryPlanFile? planFile,
    MemoryNightsFile? nights,
  }) {
    final t = at ?? now;
    final and = (android ?? FakeAndroid(now: t))..install();
    final o = oura ?? FakeOura(ouraStart: ouraStart, now: t);
    final v = vault ?? MemoryVault();
    if (withTokens) v.data[vaultTokens] = tokens().toJson();
    final pf = planFile ?? MemoryPlanFile(plan == null ? null : encodePlanFile(plan, t, at: 1), planState);
    final nf = nights ?? MemoryNightsFile();
    final store = HealthStore()
      ..planFile = pf
      ..ouraNightsFile = nf
      ..ouraClock = (clock ?? () => t)
      ..ouraLink = OuraLink(vault: v, send: o.send, clientId: 'CID', tokenEndpoint: 'https://api.ouraring.com/oauth/token');
    return (store: store, android: and, oura: o, vault: v, planFile: pf, nights: nf);
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
      a.android.prefs = {'sources': p.toJson(), 'sourcesAt': 5};
      await boot(a.store);
      expect(a.store.planState, PlanState.ok);
      expect(a.store.plan, p);
      expect(decodePlanFile(a.planFile.content), p);
    });

    test('M-2: προσωρινό σφάλμα ανάγνωσης του αρχείου: ξαναδιαβάζεται, δεν ξαναγράφεται', () async {
      final p = SourcePlan.samsungOnly.withEra(Source.oura, ouraStart);
      final a = app(plan: p, withTokens: true);
      a.planFile.transientErrors = 1;
      await boot(a.store);
      expect(a.store.planState, PlanState.ok);
      expect(a.store.plan, p);
      expect(a.planFile.writes, 0);
      expect(a.planFile.reads, greaterThanOrEqualTo(2));
    });

    test('M-2: χαμένο αρχείο, ημερολόγιο νεότερο από το αντίγραφο των ρυθμίσεων: κερδίζει το νεότερο', () async {
      final older = SourcePlan.samsungOnly.withEra(Source.oura, ouraStart);
      final newer = older.withEra(Source.watch, add(today, -1));
      final a = app(plan: null, withTokens: true);
      a.planFile.log = appendPlanLog(null, newer, 200);
      a.android.prefs = {'sources': older.toJson(), 'sourcesAt': 100};
      await boot(a.store);
      expect(a.store.planState, PlanState.ok);
      expect(a.store.plan, newer);
      expect(decodePlanFile(a.planFile.content), newer);
      expect(SourcePlan.fromJson(a.android.prefs['sources']), newer, reason: 'το αντίγραφο ακολουθεί');
    });

    test('M-3: χαμένο αρχείο, αντίγραφο Oura, αποτυχία εγγραφής: οι οθόνες ακολουθούν το Oura, τίποτα δεν γράφεται', () async {
      final p = SourcePlan.samsungOnly.withEra(Source.oura, ouraStart);
      final a = app(plan: null, withTokens: true);
      a.planFile.failWrites = true;
      a.android.prefs = {'sources': p.toJson(), 'sourcesAt': 100};
      await boot(a.store);
      expect(a.store.plan, p, reason: 'το σχέδιο ισχύει στη μνήμη');
      expect(a.store.planState, isNot(PlanState.ok));
      expect(a.store.data!.nights, isEmpty, reason: 'ποτέ νύχτες ρολογιού για νύχτες του Oura');
      expect(a.android.saveDaysCalls, 0);
      expect(a.oura.gets, 0);
    });

    test('S-E: χωρίς αρχείο και αντίγραφο αλλά με tokens (χωρίς τιμές «o.*»): «άγνωστο», ποτέ σιωπηλά ρολόι', () async {
      final a = app(plan: null, withTokens: true);
      await boot(a.store);
      expect(a.store.planState, PlanState.unknown);
      expect(a.store.plan.nightSource(today), Source.none);
      expect(a.android.saveDaysCalls, 0);
      final options = a.store.planRecovery!;
      expect(options.any((o) => o.plan.nightSource(add(today, 1)) == Source.oura), isTrue, reason: 'επιλογή Oura');
      // Αποτυχία εγγραφής: τίποτα δεν αλλάζει (η οθόνη δείχνει μήνυμα).
      a.planFile.failWrites = true;
      expect(await a.store.recoverPlan(options.first.plan), isFalse);
      expect(a.store.planState, PlanState.unknown);
      a.planFile.failWrites = false;
      expect(await a.store.recoverPlan(options.first.plan), isTrue);
      expect(a.store.planState, PlanState.ok);
      expect(lastLoggedPlan(a.planFile.log)!.plan, options.first.plan, reason: 'και στο ημερολόγιο');
    });

    test('S-E: αρχείο νυχτών Oura χωρίς tokens = ένδειξη· χωρίς ιστορικό ακόμα: καμία επιλογή («Δοκίμασε ξανά»)', () async {
      final a = app(plan: null);
      a.nights.content = encodeOuraNights(
          parseOura(sleep: sampleOuraSleep(ouraStart, now), dailySleep: const [], readiness: const []).nights);
      await boot(a.store);
      expect(a.store.planState, PlanState.unknown);
      expect(a.store.planRecovery, isNotNull);
      expect(recoveryOptions(history: null, evidence: true, today: today), isNull);
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
      await a.store.completeOuraLogin('$ouraRedirectHttps?code=C&state=${url.queryParameters['state']}');
      expect(a.store.ouraLoginError, isNull);
      expect(a.store.plan.ouraFrom, add(today, 1), reason: '15:00: από απόψε');
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

    test('S-D: σύνδεση στις 00:40 χωρίς τελειωμένη νύχτα ρολογιού: η νύχτα που έρχεται μετρά από το δαχτυλίδι', () async {
      final at = DateTime(today.year, today.month, today.day, 0, 40);
      final a = app(plan: null, at: at);
      a.oura.noData = true;
      await boot(a.store);
      final url = await a.store.ouraLink.begin();
      await a.store.completeOuraLogin('$ouraRedirectHttps?code=C&state=${url.queryParameters['state']}');
      for (var i = 0; i < 50 && (a.store.loading || a.store.ouraSyncing); i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(a.store.plan.ouraFrom, today);
      expect(a.store.ouraStatus, OuraStatus.startingNow);
      expect(a.store.ouraNightReason(today, at), EmptyNight.waiting);
    });

    test('S-B: αποσύνδεση μετά από «ρολόι από απόψε»: η επιλογή μένει, καμία «χωρίς πηγή»', () async {
      final p = SourcePlan([SourceEra(Source.oura, ouraStart), SourceEra(Source.watch, add(today, 1))]);
      final a = app(plan: p, withTokens: true);
      await boot(a.store);
      await a.store.disconnectOura();
      expect(a.store.plan, p);
      expect(a.store.plan.nightSource(add(today, 1)), Source.watch);
    });

    test('S-B: νέα σύνδεση (από αύριο) και αποσύνδεση: φεύγει μόνο η μελλοντική εποχή Oura', () async {
      final p = SourcePlan([SourceEra(Source.oura, ouraStart), SourceEra(Source.watch, add(today, -1)), SourceEra(Source.oura, add(today, 1))]);
      final a = app(plan: p, withTokens: true);
      await boot(a.store);
      await a.store.disconnectOura();
      expect(a.store.plan, SourcePlan([SourceEra(Source.oura, ouraStart), SourceEra(Source.watch, add(today, -1))]));
      expect(a.store.plan.nightSource(add(today, 1)), Source.watch);
    });

    test('S6: νύχτα «χωρίς πηγή» δεν δείχνει ποτέ νύχτα του Oura, ακόμα κι αν ήρθε', () async {
      final p = SourcePlan([SourceEra(Source.oura, ouraStart), SourceEra(Source.none, today)]);
      final a = app(plan: p, withTokens: true);
      await boot(a.store);
      expect(a.store.ouraNights.any((n) => sameDay(n.day, today)), isTrue, reason: 'η Oura την έδωσε');
      expect(a.store.ouraNightFor(today), isNull);
      expect(a.store.ouraNightFor(add(today, -1)), isNotNull);
      expect(a.store.ouraNightReason(today, now), EmptyNight.disconnected);
      expect(a.android.days[dateKey(today)]?.containsKey(ouraKeys[K.sleepMin]) ?? false, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  group('S-D: η πρώτη νύχτα του Oura (καθαρή συνάρτηση)', () {
    final d = DateTime(2026, 11, 3);
    test('00:40 χωρίς νύχτα ρολογιού: σήμερα', () {
      expect(firstOuraNight(connectedAt: DateTime(2026, 11, 3, 0, 40), watchNights: const []), d);
    });
    test('07:30 αφού τελείωσε νύχτα ρολογιού στις 07:10: αύριο (η νύχτα του ρολογιού μένει)', () {
      expect(
        firstOuraNight(connectedAt: DateTime(2026, 11, 3, 7, 30), watchNights: [(d, DateTime(2026, 11, 3, 7, 10))]),
        DateTime(2026, 11, 4),
      );
    });
    test('07:30 με νύχτα ρολογιού που δεν έχει τελειώσει ακόμα: σήμερα', () {
      expect(
        firstOuraNight(connectedAt: DateTime(2026, 11, 3, 7, 30), watchNights: [(d, DateTime(2026, 11, 3, 8, 10))]),
        d,
      );
    });
    test('15:00: αύριο', () {
      expect(firstOuraNight(connectedAt: DateTime(2026, 11, 3, 15), watchNights: const []), DateTime(2026, 11, 4));
    });
    test('Πριν από τις 12:00 χωρίς ανάγνωση της Samsung: αύριο (ποτέ δεν χάνεται νύχτα ρολογιού)', () {
      expect(firstOuraNight(connectedAt: DateTime(2026, 11, 3, 6), watchNights: null), DateTime(2026, 11, 4));
    });
  });

  // ---------------------------------------------------------------------------
  group('S-A: το σφάλμα και η αναμονή μένουν μετά από επανεκκίνηση', () {
    test('403 → νέα εκκίνηση: ίδια κατάσταση, καμία κλήση· μετά την αναμονή και επιτυχία καθαρίζει', () async {
      var clock = now;
      final p = SourcePlan.samsungOnly.withEra(Source.oura, ouraStart);
      final a = app(plan: p, withTokens: true, clock: () => clock);
      a.oura.status = 403;
      await boot(a.store);
      expect(a.store.ouraStatus, OuraStatus.subscription);
      expect(a.android.prefs['ouraErr'], 'subscription');
      final calls = a.oura.gets;
      // Νέα εκκίνηση της εφαρμογής (ίδια αποθήκευση).
      final b = app(clock: () => clock, android: a.android, oura: a.oura, vault: a.vault, planFile: a.planFile, nights: a.nights);
      await boot(b.store);
      expect(b.store.ouraError, OuraErrorKind.subscription);
      expect(b.store.ouraStatus, OuraStatus.subscription);
      expect(a.oura.gets, calls, reason: 'η αναμονή μένει');
      clock = clock.add(const Duration(hours: 1, minutes: 1));
      a.oura.status = 200;
      await b.store.syncOura();
      expect(b.store.ouraError, isNull);
      expect(a.android.prefs.containsKey('ouraErr'), isFalse);
    });

    test('Αποσύνδεση καθαρίζει σφάλμα, αναμονή και ώρα σύνδεσης', () async {
      final a = app(plan: SourcePlan.samsungOnly.withEra(Source.oura, ouraStart), withTokens: true);
      a.oura.status = 429;
      await boot(a.store);
      expect(a.store.ouraError, isNotNull);
      await a.store.disconnectOura();
      expect(a.store.ouraError, isNull);
      for (final k in ['ouraErr', 'ouraTried', 'ouraBackoff', 'ouraConnected']) {
        expect(a.android.prefs.containsKey(k), isFalse, reason: k);
      }
    });

    test('M-9: «δοκιμάστηκε» στο μέλλον ή αναμονή πάνω από 6 ώρες: θεωρούνται ληγμένα', () async {
      final a = app(plan: SourcePlan.samsungOnly.withEra(Source.oura, ouraStart), withTokens: true);
      a.android.prefs = {
        'sources': SourcePlan.samsungOnly.withEra(Source.oura, ouraStart).toJson(),
        'ouraTried': now.add(const Duration(days: 2)).millisecondsSinceEpoch,
        'ouraBackoff': now.add(const Duration(days: 3)).millisecondsSinceEpoch,
      };
      await boot(a.store);
      expect(a.oura.gets, greaterThan(0));
    });

    test('M-11: το Oura δεν είναι πηγή σήμερα και έχει διαβαστεί ως το τέλος του: καμία κλήση', () async {
      final p = SourcePlan([SourceEra(Source.oura, ouraStart), SourceEra(Source.watch, add(today, -1))]);
      final a = app(plan: p, withTokens: true);
      a.android.prefs = {'sources': p.toJson(), 'ouraSyncedTo': dateKey(add(today, -2))};
      await boot(a.store);
      expect(a.oura.gets, 0);
    });
  });

  // ---------------------------------------------------------------------------
  group('Επαναφορά σχεδίου: επιλογές και χρονογραμμή (S-E, M-1)', () {
    test('Χρονογραμμή από τα δεδομένα: «o.*» → Oura, μετά νύχτες ρολογιού → ρολόι', () {
      final h = {
        dateKey(add(today, -20)): {K.sleepMin: 400.0},
        dateKey(add(today, -10)): {'o.sleepMin': 420.0},
        dateKey(add(today, -9)): {'o.sleepMin': 410.0},
        dateKey(add(today, -4)): {K.sleepMin: 380.0},
        dateKey(add(today, -3)): {K.steps: 5000.0},
      };
      expect(rebuildTimeline(h), SourcePlan([SourceEra(Source.oura, add(today, -10)), SourceEra(Source.watch, add(today, -4))]));
      final o = recoveryOptions(history: h, evidence: false, today: today)!;
      expect(o.first.primary, isTrue);
      expect(o.first.plan, rebuildTimeline(h));
      expect(o.any((x) => x.plan.nightSource(add(today, 1)) == Source.oura), isTrue, reason: 'και «από το Oura»');
      expect(describePlan(o.first.plan).length, 3);
    });

    test('Το ημερολόγιο αλλαγών προτιμάται και δείχνεται ολόκληρο', () {
      final p = SourcePlan([SourceEra(Source.oura, add(today, -10))]);
      final log = appendPlanLog(appendPlanLog(null, SourcePlan.samsungOnly, 1), p, 2);
      expect(lastLoggedPlan(log), (plan: p, at: 2));
      final o = recoveryOptions(history: const {}, logged: lastLoggedPlan(log), evidence: true, today: today)!;
      expect(o.first.plan, p);
      expect(o.where((x) => x.plan.nightSource(add(today, 1)) == Source.oura).length, 1);
      expect(lastLoggedPlan('χαλασμένο'), isNull);
    });

    test('Χωρίς καμία ένδειξη Oura: μόνο «ρολόι, όπως πριν»', () {
      final o = recoveryOptions(history: const {}, evidence: false, today: today)!;
      expect(o.single.plan, SourcePlan.samsungOnly);
    });
  });

  // ---------------------------------------------------------------------------
  group('S1: παλμοί της μέρας χωρίς τον ύπνο του Oura', () {
    test('heartRange(exclude): οι μετρήσεις μέσα στις ώρες ύπνου δεν μετρούν', () {
      final d = Dashboard.fromJson(sampleDashboardJson(now));
      final day = add(today, -1);
      final all = d.heart.where((h) => sameDay(h.start, day)).toList();
      expect(all, isNotEmpty);
      final cut = (DateTime(day.year, day.month, day.day), DateTime(day.year, day.month, day.day, 12));
      final kept = all.where((h) => !(h.start.isBefore(cut.$2) && h.end.isAfter(cut.$1))).toList();
      final r = d.heartRange(day, exclude: [cut]);
      if (kept.isEmpty) {
        expect(r, isNull);
      } else {
        expect(r!.$1, kept.map((h) => h.min).reduce((a, b) => a < b ? a : b));
        expect(r.$2, kept.map((h) => h.max).reduce((a, b) => a > b ? a : b));
      }
      expect(d.heartRange(day, exclude: [(DateTime(day.year, day.month, day.day), add(day, 1))]), isNull);
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
      var clock = now;
      final a = app(plan: SourcePlan.samsungOnly.withEra(Source.oura, ouraStart), withTokens: true, clock: () => clock);
      // Η πρώτη ανάγνωση (στην εκκίνηση) αποτυγχάνει: τίποτα δεν έχει έρθει ακόμα.
      a.oura.status = 500;
      await boot(a.store);
      expect(a.store.ouraNights, isEmpty);
      // Δύο λεπτά μετά: «Ενημέρωση τώρα» με ανάγνωση που περιμένει.
      clock = clock.add(const Duration(minutes: 2));
      a.oura.status = 200;
      final before = a.oura.gets;
      a.oura.gate = Completer<void>();
      final saves = a.android.saveDaysCalls;
      final sync = a.store.syncOura(force: true);
      for (var i = 0; i < 20 && a.oura.gets == before; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(a.oura.gets, before + 1);
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
