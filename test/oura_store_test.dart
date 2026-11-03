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

  /// Καθυστερεί τις εγγραφές ιστορικού (για τη σειρά τους) και μετρά πόσες τρέχουν μαζί.
  Completer<void>? saveGate;
  var savesInFlight = 0;
  var maxSavesInFlight = 0;
  final savedBatches = <List<String>>[];

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
          savesInFlight++;
          if (savesInFlight > maxSavesInFlight) maxSavesInFlight = savesInFlight;
          final batch = jsonDecode(args['json'] as String) as List;
          savedBatches.add([for (final r in batch) (r as Map)['date'] as String]);
          if (saveGate != null) await saveGate!.future;
          savesInFlight--;
          for (final row in batch) {
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

  /// Αναγνώσεις δεδομένων (όχι η ανάκληση, που είναι κι αυτή GET).
  int get gets => calls.where((c) => c.$1 == 'GET' && !c.$2.path.endsWith('/revoke')).length;
}

DateTime add(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// Αποθήκευση που δεν απαντά μόνο για ορισμένα ονόματα, και καταγράφει τη σειρά των διαγραφών.
class PickyVault extends MemoryVault {
  final failNames = <String>{};
  final deletes = <String>[];

  @override
  Future<String?> load(String name) async {
    if (failNames.contains(name)) throw const VaultUnavailable();
    return super.load(name);
  }

  @override
  Future<void> delete(String name) async {
    deletes.add(name);
    await super.delete(name);
  }
}

/// Αρχείο σχεδίου που μπορεί να καθυστερήσει τις εγγραφές ([gate]) και να καταγράψει κάτι τη στιγμή της εγγραφής.
class GatedPlanFile extends MemoryPlanFile {
  GatedPlanFile(super.content);
  Completer<void>? gate;
  bool Function()? onWrite;
  final markerSeen = <bool>[];

  @override
  Future<bool> write(String json) async {
    if (onWrite != null) markerSeen.add(onWrite!());
    if (gate != null) await gate!.future;
    return super.write(json);
  }
}

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

  /// «Σύνδεση με Oura» στην ώρα του ρολογιού του store (με την απάντηση [wore] αν ρωτηθεί), και επιστροφή.
  Future<void> connect(HealthStore s, MemoryVault vault, {bool wore = false}) async {
    expect(await s.beginOuraLogin(from: firstOuraNight(s.ouraClock(), woreRing: wore)), isNull);
    final state = OuraPending.fromJson(vault.data[vaultPending])!.state;
    await s.completeOuraLogin('$ouraRedirectHttps?code=C&state=$state');
    await s.syncOura();
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

    test('S-E: χωρίς ένδειξη Oura, με επιλογές: αποτυχία εγγραφής δεν αλλάζει τίποτα, μετά γράφεται', () async {
      final a = app(plan: null);
      a.nights.content = encodeOuraNights(
          parseOura(sleep: sampleOuraSleep(ouraStart, now), dailySleep: const [], readiness: const []).nights);
      await boot(a.store);
      expect(a.store.planState, PlanState.unknown);
      expect(a.store.plan.nightSource(today), Source.none);
      expect(a.android.saveDaysCalls, 0);
      final options = a.store.planRecovery!;
      expect(options.any((o) => o.plan.nightSource(add(today, 1)) == Source.oura), isTrue, reason: 'επιλογή Oura');
      a.planFile.failWrites = true;
      expect(await a.store.recoverPlan(options.first.plan), isFalse);
      expect(a.store.planState, PlanState.unknown);
      expect(a.planFile.log, isNull, reason: 'ούτε στο ημερολόγιο');
      a.planFile.failWrites = false;
      expect(await a.store.recoverPlan(options.first.plan), isTrue);
      expect(a.store.planState, PlanState.ok);
      expect(lastLoggedPlan(a.planFile.log)!.plan, options.first.plan, reason: 'και στο ημερολόγιο');
    });

    test('N-2: tokens χωρίς εποχή Oura και χωρίς τίποτα από το Oura = μισή σύνδεση: σβήνονται, ποτέ «άγνωστο»', () async {
      final a = app(plan: null, withTokens: true);
      await boot(a.store);
      expect(a.store.planState, PlanState.ok);
      expect(a.store.plan.eras, isEmpty);
      expect(a.vault.data.containsKey(vaultTokens), isFalse);
      expect(a.store.ouraHasTokens, isFalse);
      expect(a.store.ouraStatus, OuraStatus.incomplete);
      expect(ouraErrorText(a.store.ouraLoginError!), 'Η σύνδεση δεν ολοκληρώθηκε· δοκίμασε ξανά.');
      expect(a.android.saveDaysCalls, greaterThan(0), reason: 'η εφαρμογή συνεχίζει κανονικά');
      expect(a.oura.gets, 0);
    });

    test('Tokens που χάθηκαν (π.χ. επαναφορά κινητού), χωρίς σημάδι: η εποχή μένει, «Χρειάζεται νέα σύνδεση»', () async {
      final p = SourcePlan.samsungOnly.withEra(Source.oura, today);
      final a = app(plan: p);
      await boot(a.store);
      expect(a.store.plan, p);
      expect(a.store.ouraStatus, OuraStatus.reconnect);
      expect(a.store.ouraIncomplete, isFalse);
    });

    test('Σημάδι «συνδέεται» χωρίς tokens (έκλεισε μετά το σχέδιο, πριν από τα tokens): το σχέδιο επιστρέφει', () async {
      final a = app(plan: SourcePlan.samsungOnly.withEra(Source.oura, today));
      a.vault.data[vaultConnecting] = jsonEncode({'from': dateKey(today), 'at': 1, 'before': <Object>[]});
      await boot(a.store);
      expect(a.store.plan.eras, isEmpty);
      expect(decodePlanFile(a.planFile.content)!.eras, isEmpty);
      expect(a.store.ouraStatus, OuraStatus.incomplete);
      expect(a.vault.data.containsKey(vaultConnecting), isFalse);
    });

    test('Σημάδι χωρίς tokens για όποιον είχε συνδεθεί παλιότερα (με δεδομένα Oura): επιστρέφει ακριβώς το προηγούμενο', () async {
      final before = SourcePlan([
        SourceEra(Source.oura, add(today, -20)),
        SourceEra(Source.none, add(today, -12)),
        SourceEra(Source.watch, add(today, -10)),
      ]);
      final after = before.withEra(Source.oura, add(today, 1));
      final a = app(plan: after);
      a.android.days[dateKey(add(today, -15))] = {'o.sleepMin': 420, K.steps: 3000};
      a.android.prefs = {'sources': after.toJson(), 'sourcesAt': 5, 'ouraSyncedTo': dateKey(add(today, -12))};
      a.vault.data[vaultConnecting] = jsonEncode({'from': dateKey(add(today, 1)), 'at': 1, 'before': before.toJson()});
      await boot(a.store);
      expect(a.store.plan, before);
      expect(a.store.ouraStatus, OuraStatus.incomplete);
      expect(a.vault.data.containsKey(vaultConnecting), isFalse);
    });

    test('Σημάδι ΜΕ tokens (έκλεισε μετά την ολοκλήρωση): μένει η σύνδεση, σβήνεται το σημάδι, η ώρα σύνδεσης επανέρχεται', () async {
      final p = SourcePlan.samsungOnly.withEra(Source.oura, today);
      final a = app(plan: p, withTokens: true);
      a.oura.noData = true;
      final at = DateTime(today.year, today.month, today.day, 9).millisecondsSinceEpoch;
      a.vault.data[vaultConnecting] = jsonEncode({'from': dateKey(today), 'at': at, 'before': <Object>[]});
      await boot(a.store);
      expect(a.store.plan, p);
      expect(a.store.ouraHasTokens, isTrue);
      expect(a.store.ouraConnectedMs, at);
      expect(a.vault.data.containsKey(vaultConnecting), isFalse);
      expect(a.store.ouraIncomplete, isFalse);
    });

    test('S-1: παλιό σημάδι χωρίς tokens, αλλά με ανάγνωση του Oura μετά από αυτό: η εποχή μένει, το σημάδι σβήνεται', () async {
      final before = SourcePlan.samsungOnly;
      final p = before.withEra(Source.oura, add(today, -3));
      final a = app(plan: p);
      a.android.prefs = {
        'sources': p.toJson(),
        'sourcesAt': 5,
        'ouraSynced': now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
        'ouraSyncedTo': dateKey(add(today, -1)),
      };
      a.vault.data[vaultConnecting] = jsonEncode({
        'from': dateKey(add(today, -3)),
        'at': now.subtract(const Duration(days: 3)).millisecondsSinceEpoch,
        'before': before.toJson(),
      });
      await boot(a.store);
      expect(a.store.plan, p, reason: 'μια σύνδεση που χρησιμοποιήθηκε δεν αναιρείται ποτέ');
      expect(a.vault.data.containsKey(vaultConnecting), isFalse);
      expect(a.store.ouraIncomplete, isFalse);
    });

    test('S-1: παλιό σημάδι χωρίς tokens, με τιμές «o.*» από την πρώτη νύχτα και μετά: η εποχή μένει', () async {
      final p = SourcePlan.samsungOnly.withEra(Source.oura, add(today, -3));
      final a = app(plan: p);
      a.android.days[dateKey(add(today, -2))] = {'o.sleepMin': 400, K.steps: 3000};
      a.vault.data[vaultConnecting] = jsonEncode({'from': dateKey(add(today, -3)), 'at': 1, 'before': <Object>[]});
      await boot(a.store);
      expect(a.store.plan, p);
      expect(a.vault.data.containsKey(vaultConnecting), isFalse);
    });

    test('S-1: η αποσύνδεση σβήνει ΠΡΩΤΑ το σημάδι', () async {
      final v = PickyVault()..data[vaultTokens] = tokens().toJson();
      v.data[vaultConnecting] = '{}';
      final a = app(plan: SourcePlan.samsungOnly.withEra(Source.oura, ouraStart), vault: v);
      await boot(a.store);
      v.deletes.clear();
      await a.store.disconnectOura();
      expect(v.deletes.first, vaultConnecting);
      expect(v.data, isEmpty);
    });

    test('M-1: σημάδι, αλλά τα tokens δεν διαβάζονται τώρα: τίποτα δεν κρίνεται, το σημάδι μένει για την επόμενη φορά', () async {
      final v = PickyVault()..failNames.add(vaultTokens);
      final p = SourcePlan.samsungOnly.withEra(Source.oura, today);
      final a = app(plan: p, vault: v);
      v.data[vaultConnecting] = jsonEncode({'from': dateKey(today), 'at': 1, 'before': <Object>[]});
      await boot(a.store);
      expect(a.store.plan, p);
      expect(v.data.containsKey(vaultConnecting), isTrue);
      expect(a.store.ouraIncomplete, isFalse);
      // Επόμενη εκκίνηση, η αποθήκευση απαντά και tokens δεν υπάρχουν: μισή σύνδεση, το σχέδιο επιστρέφει.
      v.failNames.clear();
      final b = app(android: a.android, oura: a.oura, vault: v, planFile: a.planFile, nights: a.nights);
      await boot(b.store);
      expect(b.store.plan.eras, isEmpty);
      expect(b.store.ouraStatus, OuraStatus.incomplete);
      expect(v.data.containsKey(vaultConnecting), isFalse);
    });

    test('M-2: «Αποσύνδεση» την ώρα της σύνδεσης: καμία εποχή Oura χωρίς tokens, κανένα σημάδι', () async {
      final pf = GatedPlanFile(null);
      final a = app(plan: null, planFile: pf);
      await boot(a.store);
      expect(await a.store.beginOuraLogin(from: add(today, 1)), isNull);
      final state = OuraPending.fromJson(a.vault.data[vaultPending])!.state;
      pf.gate = Completer<void>();
      pf.onWrite = () => true;
      final connecting = a.store.completeOuraLogin('$ouraRedirectHttps?code=C&state=$state');
      for (var i = 0; i < 50 && pf.markerSeen.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(pf.markerSeen, isNotEmpty, reason: 'το σχέδιο γράφεται τώρα');
      final disconnecting = a.store.disconnectOura();
      await Future<void>.delayed(Duration.zero);
      pf.gate!.complete();
      await connecting;
      await disconnecting;
      expect(a.store.plan.hasOura, isFalse);
      expect(decodePlanFile(pf.content)?.hasOura ?? false, isFalse);
      expect(a.vault.data.containsKey(vaultTokens), isFalse);
      expect(a.vault.data.containsKey(vaultConnecting), isFalse);
      expect(a.store.ouraHasTokens, isFalse);
    });

    test('T-1(α): Oura από σήμερα, tokens, χωρίς ανάγνωση ακόμα: ο καθαρισμός δεν πειράζει τίποτα', () async {
      final p = SourcePlan.samsungOnly.withEra(Source.oura, today);
      final a = app(plan: p, withTokens: true);
      a.oura.noData = true;
      await boot(a.store);
      expect(a.store.plan, p);
      expect(a.vault.data.containsKey(vaultTokens), isTrue);
      expect(a.store.ouraHasTokens, isTrue);
      expect(a.store.ouraStatus, isNot(OuraStatus.incomplete));
    });

    test('T-1(β): το ίδιο με αποθήκευση που δεν απαντά: τίποτα δεν σβήνεται', () async {
      final p = SourcePlan.samsungOnly.withEra(Source.oura, today);
      final a = app(plan: p, withTokens: true);
      a.vault.failLoads = true;
      await boot(a.store);
      expect(a.store.plan, p);
      expect(a.vault.data.containsKey(vaultTokens), isTrue);
      expect(a.store.ouraIncomplete, isFalse);
    });

    test('T-1(γ): αποσύνδεση την πρώτη μέρα: τίποτα δεν πειράζεται, «Αποσυνδέθηκε»', () async {
      final p = SourcePlan([SourceEra(Source.oura, today), SourceEra(Source.none, add(today, 1))]);
      final a = app(plan: p);
      await boot(a.store);
      expect(a.store.plan, p);
      expect(a.store.ouraStatus, OuraStatus.disconnected);
      expect(a.store.ouraNightReason(today, now), EmptyNight.disconnected);
      expect(a.store.ouraIncomplete, isFalse);
    });

    test('M-2: αλλαγή σχεδίου με ανανέωση στη μέση: το αρχείο μένει με το ΝΕΟ σχέδιο', () async {
      final pf = GatedPlanFile(encodePlanFile(SourcePlan.samsungOnly.withEra(Source.oura, ouraStart), now, at: 1));
      final a = app(withTokens: true, planFile: pf);
      await boot(a.store);
      final next = a.store.plan.withEra(Source.watch, add(today, 1));
      pf.gate = Completer<void>();
      final f1 = a.store.setPlan(next);
      final f2 = a.store.refresh();
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      pf.gate!.complete();
      expect(await f1, isTrue);
      await f2;
      expect(a.store.plan, next);
      expect(decodePlanFile(pf.content), next);
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
    test('15:00: από απόψε, χωρίς ερώτηση· η χθεσινή μένει του ρολογιού και δεν σβήνεται', () async {
      final a = app(plan: null);
      await boot(a.store);
      final watchSleep = a.android.days[dateKey(today)]?[K.sleepMin];
      expect(watchSleep, isNotNull, reason: 'η χθεσινή νύχτα του ρολογιού');
      expect(firstNightChoice(now), FirstNightChoice.tomorrow);
      await connect(a.store, a.vault);
      expect(a.store.ouraLoginError, isNull);
      expect(a.store.plan.ouraFrom, add(today, 1), reason: '15:00: από απόψε');
      expect(a.store.plan.nightSource(today), Source.watch);
      expect(a.store.ouraStatus, OuraStatus.starting);
      expect(a.store.ouraEraStarted, isFalse, reason: 'M-12: χωρίς «Αναίρεση»');
      expect(a.store.canWatchLastNight, isFalse);
      expect(a.android.days[dateKey(today)]?[K.sleepMin], watchSleep, reason: 'δεν σβήστηκε');
      expect(decodePlanFile(a.planFile.content)!.ouraFrom, add(today, 1), reason: 'πρώτα στο αρχείο');
      // Μία κλήση μόνο: ο έλεγχος πρόσβασης ΠΡΙΝ από το σχέδιο πηγών (A13). Ανάγνωση σήμερα: τίποτα να διαβαστεί
      // ακόμα (η πρώτη νύχτα είναι αύριο).
      expect(a.oura.calls.where((c) => c.$1 == 'GET' && !c.$2.path.endsWith('/revoke')).single.$2.pathSegments.last, 'daily_sleep');
      await a.store.syncOura(force: true);
      expect(a.oura.gets, 1);
      // Αποσύνδεση την ίδια μέρα: τίποτα δεν είχε έρθει από το Oura → όλα όπως πριν.
      await a.store.disconnectOura();
      expect(a.store.plan.eras, isEmpty);
      expect(a.vault.data, isEmpty);
    });

    test('02:00: η νύχτα που κοιμάσαι τώρα από το δαχτυλίδι, χωρίς ερώτηση', () async {
      final at = DateTime(today.year, today.month, today.day, 2);
      final pf = GatedPlanFile(null);
      final a = app(plan: null, at: at, planFile: pf);
      pf.onWrite = () => a.vault.data.containsKey(vaultConnecting);
      a.oura.noData = true;
      await boot(a.store);
      expect(firstNightChoice(at), FirstNightChoice.today);
      await connect(a.store, a.vault);
      expect(pf.markerSeen, [true], reason: 'το σημάδι γράφεται ΠΡΙΝ από το σχέδιο');
      expect(a.vault.data.containsKey(vaultConnecting), isFalse, reason: 'και σβήνεται μετά τα tokens');
      expect(a.store.canWatchLastNight, isTrue);
      expect(a.store.watchLastNightLabel, 'Η νύχτα που κοιμάσαι τώρα από το ρολόι');
      expect(a.store.plan.ouraFrom, today);
      expect(a.store.ouraStatus, OuraStatus.startingNow);
      expect(a.store.ouraFirstNightText, 'Η νύχτα που κοιμάσαι τώρα μετρά από το δαχτυλίδι');
      expect(a.store.ouraNightReason(today, at), EmptyNight.waiting);
      expect(a.store.ouraEraStarted, isTrue, reason: 'M-12: «Αναίρεση» μετά από αποσύνδεση');
    });

    test('09:00, «Όχι, από απόψε» (προεπιλογή): αύριο', () async {
      final at = DateTime(today.year, today.month, today.day, 9);
      final a = app(plan: null, at: at);
      await boot(a.store);
      expect(firstNightChoice(at), FirstNightChoice.ask);
      await connect(a.store, a.vault, wore: false);
      expect(a.store.plan.ouraFrom, add(today, 1));
      expect(a.store.plan.nightSource(today), Source.watch);
      expect(a.store.ouraStatus, OuraStatus.starting);
    });

    test('09:00, «Ναι»: σήμερα· η νύχτα του ρολογιού μένει στο ιστορικό (κρυφή)· «Η τελευταία νύχτα από το ρολόι»', () async {
      final at = DateTime(today.year, today.month, today.day, 9);
      final a = app(plan: null, at: at);
      await boot(a.store);
      final watchSleep = a.android.days[dateKey(today)]?[K.sleepMin];
      expect(watchSleep, isNotNull);
      await connect(a.store, a.vault, wore: true);
      expect(a.store.plan.ouraFrom, today);
      expect(a.store.plan.nightSource(today), Source.oura);
      expect(a.store.ouraFirstNightText, 'Η νύχτα που μόλις τελείωσε μετρά από το δαχτυλίδι');
      await a.store.refresh();
      final row = a.android.days[dateKey(today)]!;
      expect(row[ouraKeys[K.sleepMin]], isNotNull, reason: 'η νύχτα από το Oura');
      expect(row[K.sleepMin], watchSleep, reason: 'η νύχτα του ρολογιού δεν σβήνεται ποτέ');
      expect(a.store.plan.value(a.store.history, K.sleepMin, today), row[ouraKeys[K.sleepMin]], reason: 'οι οθόνες: Oura');
      expect(a.store.data!.nights.any((n) => sameDay(n.date, today)), isFalse, reason: 'μόνο στη Σύγκριση');
      // Αναίρεση της μέρας της σύνδεσης.
      expect(a.store.canWatchLastNight, isTrue);
      expect(await a.store.watchLastNight(), isTrue);
      expect(a.store.plan.nightSource(today), Source.watch);
      expect(a.store.plan.ouraFrom, add(today, 1));
      expect(decodePlanFile(a.planFile.content)!.ouraFrom, add(today, 1));
      final after = a.android.days[dateKey(today)]!;
      expect(after[K.sleepMin], watchSleep);
      expect(after.keys.any(ouraKeySet.contains), isFalse);
      expect(a.store.data!.nights.any((n) => sameDay(n.date, today)), isTrue, reason: 'ξαναφαίνεται');
      expect(a.store.canWatchLastNight, isFalse);
      expect(a.store.ouraHasTokens, isTrue, reason: 'η σύνδεση μένει');
    });

    test('Δεν γράφτηκε το σχέδιο πηγών: τα tokens δεν κρατιούνται (ανάκληση), τίποτα δεν αλλάζει', () async {
      final a = app(plan: null);
      await boot(a.store);
      a.planFile.failWrites = true;
      await connect(a.store, a.vault);
      expect(a.store.ouraLoginError, OuraErrorKind.cancelled);
      expect(a.vault.data.containsKey(vaultTokens), isFalse);
      expect(a.store.ouraHasTokens, isFalse);
      expect(a.oura.revoked, isNotEmpty);
      expect(a.store.plan.eras, isEmpty);
    });

    test('Δεν γράφτηκαν τα tokens: το σχέδιο πηγών επιστρέφει όπως ήταν', () async {
      final a = app(plan: null);
      await boot(a.store);
      expect(await a.store.beginOuraLogin(from: add(today, 1)), isNull);
      final state = OuraPending.fromJson(a.vault.data[vaultPending])!.state;
      a.vault.failSaves = true;
      await a.store.completeOuraLogin('$ouraRedirectHttps?code=C&state=$state');
      expect(a.store.ouraLoginError, OuraErrorKind.cancelled);
      expect(a.store.plan.eras, isEmpty);
      expect(decodePlanFile(a.planFile.content)?.eras ?? const [], isEmpty);
      expect(a.store.ouraHasTokens, isFalse);
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
      // Νύχτα «χωρίς πηγή»: δεν ζητείται καν από την Oura (A3: μόνο νύχτες με πηγή το Oura).
      expect(a.store.ouraNights.any((n) => sameDay(n.day, today)), isFalse);
      expect(a.store.ouraNightFor(today), isNull);
      expect(a.store.ouraNightFor(add(today, -1)), isNotNull);
      expect(a.store.ouraNightReason(today, now), EmptyNight.disconnected);
      expect(a.android.days[dateKey(today)]?.containsKey(ouraKeys[K.sleepMin]) ?? false, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  group('Η πρώτη νύχτα του Oura από την ώρα του «Σύνδεση με Oura» (καθαρή συνάρτηση)', () {
    final d = DateTime(2026, 11, 3);
    final next = DateTime(2026, 11, 4);
    DateTime t(int h, [int m = 0]) => DateTime(2026, 11, 3, h, m);
    test('00:00–03:59: σήμερα, χωρίς ερώτηση', () {
      for (final x in [t(0), t(2), t(3, 59)]) {
        expect(firstNightChoice(x), FirstNightChoice.today);
        expect(firstOuraNight(x), d);
      }
    });
    test('04:00–11:59: ερώτηση· «Ναι» σήμερα, «Όχι» (προεπιλογή) αύριο', () {
      for (final x in [t(4), t(9), t(11, 59)]) {
        expect(firstNightChoice(x), FirstNightChoice.ask);
        expect(firstOuraNight(x, woreRing: true), d);
        expect(firstOuraNight(x), next);
      }
    });
    test('12:00–23:59: αύριο, χωρίς ερώτηση', () {
      for (final x in [t(12), t(15), t(23, 59)]) {
        expect(firstNightChoice(x), FirstNightChoice.tomorrow);
        expect(firstOuraNight(x, woreRing: true), next);
      }
    });
    test('Η απόφαση ταξιδεύει κρυπτογραφημένη με το state (και ξαναδιαβάζεται)', () {
      final p = OuraPending(state: 's', verifier: 'v', created: t(9), from: d);
      expect(OuraPending.fromJson(p.toJson())!.from, d);
      expect(OuraPending.fromJson(OuraPending(state: 's', verifier: 'v', created: t(9)).toJson())!.from, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  group('Μικρά: όρια αναμονής (M-8), λόγοι κενής νύχτας (M-5, noRefresh)', () {
    test('M-8: 429 → max(Retry-After, 1 λεπτό), το πολύ 6 ώρες· χωρίς Retry-After 15 λεπτά', () {
      expect(ouraBackoffFor(OuraErrorKind.rateLimited, retryAfter: const Duration(seconds: 30)), const Duration(minutes: 1));
      expect(ouraBackoffFor(OuraErrorKind.rateLimited, retryAfter: const Duration(hours: 2)), const Duration(hours: 2));
      expect(ouraBackoffFor(OuraErrorKind.rateLimited, retryAfter: const Duration(hours: 10)), const Duration(hours: 6));
      expect(ouraBackoffFor(OuraErrorKind.rateLimited), const Duration(minutes: 15));
      expect(ouraBackoffFor(OuraErrorKind.network), ouraMinInterval);
    });
    test('M-5: άγνωστο σχέδιο → «Δεν διαβάστηκε από πού έρχεται ο ύπνος»· noRefresh → νέα σύνδεση', () {
      final none = SourcePlan([SourceEra(Source.none, add(today, -5))]);
      final r = emptyNightReason(plan: none, day: today, now: now, night: null, hasTokens: true, planUnknown: true);
      expect(r, EmptyNight.unknownPlan);
      expect(emptyNightText(r!), 'Δεν διαβάστηκε από πού έρχεται ο ύπνος');
      expect(emptyNightReason(plan: none, day: today, now: now, night: null, hasTokens: true), EmptyNight.disconnected);
      final oura = SourcePlan([SourceEra(Source.oura, add(today, -5))]);
      expect(emptyNightReason(plan: oura, day: today, now: now, night: null, hasTokens: true, error: 'noRefresh'),
          EmptyNight.reconnect);
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

    test('M-11: το Oura δεν είναι πηγή σήμερα, έχει διαβαστεί ως το τέλος του και δεν λείπει νύχτα: καμία κλήση', () async {
      final p = SourcePlan([SourceEra(Source.oura, ouraStart), SourceEra(Source.watch, add(today, -1))]);
      final a = app(plan: p, withTokens: true);
      a.android.prefs = {'sources': p.toJson(), 'ouraSyncedTo': dateKey(add(today, -2))};
      for (var d = ouraStart; d.isBefore(add(today, -1)); d = add(d, 1)) {
        a.android.days[dateKey(d)] = {'o.sleepMin': 420};
      }
      await boot(a.store);
      expect(a.oura.gets, 0);
    });

    test('A3: νύχτα της προηγούμενης εποχής Oura που λείπει (μέσα στις 30 μέρες) ξαναζητείται, και μετά το ρολόι', () async {
      final p = SourcePlan([SourceEra(Source.oura, ouraStart), SourceEra(Source.watch, add(today, -1))]);
      final a = app(plan: p, withTokens: true);
      a.android.prefs = {'sources': p.toJson(), 'ouraSyncedTo': dateKey(add(today, -2))};
      a.android.days[dateKey(ouraStart)] = {'o.sleepMin': 420};
      await boot(a.store);
      expect(a.oura.gets, 3);
      expect(a.android.days[dateKey(add(today, -2))]?['o.sleepMin'], isNotNull, reason: 'η νύχτα που έλειπε ήρθε');
      expect(a.android.days[dateKey(today)]?.containsKey('o.sleepMin') ?? false, isFalse, reason: 'νύχτα του ρολογιού');
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

    test('Ημερολόγιο αλλαγών: η τελευταία έγκυρη καταχώριση· με ένδειξη Oura υπάρχει επιλογή Oura', () {
      final p = SourcePlan([SourceEra(Source.oura, add(today, -10))]);
      final log = appendPlanLog(appendPlanLog(null, SourcePlan.samsungOnly, 1), p, 2);
      expect(lastLoggedPlan(log), (plan: p, at: 2));
      expect(lastLoggedPlan('χαλασμένο'), isNull);
      final o = recoveryOptions(history: const {}, evidence: true, today: today)!;
      expect(o.first.primary, isTrue);
      expect(o.first.plan.nightSource(add(today, 1)), Source.oura);
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
      // Η αποσύνδεση περιμένει την ανάγνωση που τρέχει μόνο για λίγο (A3)· εδώ δεν τελειώνει ποτέ πριν.
      a.store.ouraFinalSyncTimeout = const Duration(milliseconds: 50);
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
      expect(a.android.saveDaysCalls, saves, reason: 'καμία εγγραφή από ανάγνωση που δεν τελείωσε πριν από την αποσύνδεση');
      expect(a.store.ouraNights, isEmpty);
      expect(a.android.days.values.any((r) => r.keys.any(ouraKeySet.contains)), isFalse);
    });

    test('Πολλές νύχτες (πρώτη ανάγνωση): σε άλλο νήμα, ίδιο αποτέλεσμα', () async {
      final nights = parseOura(sleep: sampleOuraSleep(add(today, -40), now), dailySleep: const [], readiness: const []).nights;
      expect(nights.length, greaterThan(20));
      expect(await ouraRowsOffMain(nights), ouraRows(nights));
    });
  });

  // ---------------------------------------------------------------------------
  group('Έλεγχος 4/11, κομμάτι A', () {
    test('A1: ζύγιση σε παλιά μέρα του Oura (πάνω από 30 μέρες): το οξυγόνο της νύχτας ΔΕΝ σβήνεται', () async {
      final p = SourcePlan.samsungOnly.withEra(Source.oura, add(today, -100));
      final a = app(plan: p);
      // Ζύγιση του δείγματος (InBody), 72 μέρες πριν.
      final w = Dashboard.fromJson(sampleDashboardJson(now)).body[6];
      final k = dateKey(w.time);
      expect(w.weight, 83.3);
      a.android.days[k] = {K.spo2Avg: 95.1, K.spo2Min: 88, 'o.sleepMin': 420};
      await boot(a.store);
      expect(a.android.days[k]![K.spo2Avg], 95.1);
      expect(a.android.days[k]![K.spo2Min], 88);
      expect(a.android.days[k]!['o.sleepMin'], 420);
      expect(a.android.days[k]![K.weight], 83.3);
    });

    test('A8: οι εγγραφές του ιστορικού γίνονται μία-μία, με τη σειρά', () async {
      final a = app(plan: SourcePlan.samsungOnly);
      await boot(a.store);
      a.android.saveGate = Completer<void>();
      a.android.maxSavesInFlight = 0;
      a.store.history['2026-01-01'] = {K.steps: 1};
      a.store.history['2026-01-02'] = {K.steps: 2};
      final first = a.store.saveDaysNow({'2026-01-01'});
      final second = a.store.saveDaysNow({'2026-01-02'});
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(a.android.savesInFlight, 1, reason: 'η δεύτερη περιμένει την πρώτη');
      a.store.history['2026-01-02'] = {K.steps: 3}; // αλλάζει πριν γραφτεί: γράφεται η νεότερη τιμή
      a.android.saveGate!.complete();
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(a.android.maxSavesInFlight, 1);
      expect(a.android.savedBatches.sublist(a.android.savedBatches.length - 2), [
        ['2026-01-01'],
        ['2026-01-02'],
      ]);
      expect(a.android.days['2026-01-02'], {K.steps: 3});
    });

    test('A3: νύχτες που άργησαν να φτάσουν στην Oura (ως 30 μέρες) έρχονται· start_date μία μέρα νωρίτερα', () async {
      var clock = now;
      final start = add(today, -10);
      final o = FakeOura(ouraStart: start, now: now)..noData = true;
      final a = app(plan: SourcePlan.samsungOnly.withEra(Source.oura, start), withTokens: true, clock: () => clock, oura: o);
      await boot(a.store);
      expect(a.store.ouraSyncedTo, dateKey(today), reason: 'διαβάστηκε (κενό)');
      final first = o.calls.firstWhere((c) => c.$1 == 'GET' && c.$2.pathSegments.last == 'sleep').$2;
      expect(first.queryParameters['start_date'], dateKey(add(start, -1)));
      // Το δαχτυλίδι συγχρονίζει αργότερα: όλες οι νύχτες είναι τώρα στην Oura.
      o.noData = false;
      clock = clock.add(const Duration(minutes: 31));
      await a.store.syncOura();
      for (var d = start; !d.isAfter(today); d = add(d, 1)) {
        expect(a.android.days[dateKey(d)]?['o.sleepMin'], isNotNull, reason: dateKey(d));
      }
    });

    test('A3: αποσύνδεση: μία τελευταία ανάγνωση ΠΡΙΝ από την ανάκληση· η χθεσινή νύχτα δεν χάνεται', () async {
      final start = add(today, -3);
      final o = FakeOura(ouraStart: start, now: now)..noData = true;
      final a = app(plan: SourcePlan.samsungOnly.withEra(Source.oura, start), withTokens: true, oura: o);
      await boot(a.store);
      expect(a.android.days[dateKey(today)]?['o.sleepMin'], isNull);
      o.noData = false; // η νύχτα έφτασε στην Oura λίγο μετά (μέσα στα 30 λεπτά)
      await a.store.disconnectOura();
      expect(a.android.days[dateKey(today)]?['o.sleepMin'], isNotNull);
      final revoke = o.calls.indexWhere((c) => c.$2.path.endsWith('/revoke'));
      final lastGet = o.calls.lastIndexWhere((c) => c.$1 == 'GET' && !c.$2.path.endsWith('/revoke'));
      expect(revoke, greaterThan(lastGet), reason: 'πρώτα η ανάγνωση, μετά η ανάκληση');
      expect(a.vault.data, isEmpty);
    });

    test('A13: έλεγχος πρόσβασης πριν από το σχέδιο· 401 → tokens ανακαλούνται, το σχέδιο μένει, σωστό μήνυμα', () async {
      final a = app(plan: null);
      await boot(a.store);
      a.oura.status = 401;
      expect(await a.store.beginOuraLogin(from: firstOuraNight(now)), isNull);
      final state = OuraPending.fromJson(a.vault.data[vaultPending])!.state;
      await a.store.completeOuraLogin('$ouraRedirectHttps?code=C&state=$state');
      expect(a.store.ouraLoginError, OuraErrorKind.scopeMissing);
      expect(a.store.plan.eras, isEmpty, reason: 'το σχέδιο πηγών δεν άλλαξε');
      expect(a.vault.data.containsKey(vaultTokens), isFalse);
      expect(a.vault.data.containsKey(vaultConnecting), isFalse);
      expect(a.oura.revoked, ['ACC'], reason: 'τα νέα tokens ανακλήθηκαν');
      expect(ouraLoginErrorText(a.store.ouraLoginError!), contains('Δεν άλλαξε τίποτα'));
      // 403: συνδρομή.
      a.oura.status = 403;
      await a.store.beginOuraLogin(from: firstOuraNight(now));
      final s2 = OuraPending.fromJson(a.vault.data[vaultPending])!.state;
      await a.store.completeOuraLogin('$ouraRedirectHttps?code=C&state=$s2');
      expect(a.store.ouraLoginError, OuraErrorKind.subscription);
      expect(a.store.plan.eras, isEmpty);
    });

    test('A13: σφάλμα της σελίδας της Oura: «δεν δόθηκε άδεια» μόνο για access_denied· ο κωδικός κρατιέται', () async {
      final a = app(plan: null);
      await boot(a.store);
      Future<void> back(String error) async {
        await a.store.beginOuraLogin(from: firstOuraNight(now));
        final state = OuraPending.fromJson(a.vault.data[vaultPending])!.state;
        await a.store.completeOuraLogin('$ouraRedirectHttps?error=$error&state=$state');
      }

      await back('access_denied');
      expect(a.store.ouraLoginError, OuraErrorKind.denied);
      await back('invalid_scope');
      expect(a.store.ouraLoginError, OuraErrorKind.authError);
      expect(a.store.ouraLoginCode, 'invalid_scope');
      expect(ouraLoginErrorText(a.store.ouraLoginError!, code: a.store.ouraLoginCode), contains('invalid_scope'));
      expect(a.store.plan.eras, isEmpty);
    });

    test('A13: επιστροφή χωρίς εκκρεμή σύνδεση (παλιά καρτέλα): «η σύνδεση έληξε», τίποτα δεν αλλάζει', () async {
      final a = app(plan: null);
      await boot(a.store);
      await a.store.completeOuraLogin('$ouraRedirectHttps?code=C&state=παλιό');
      expect(a.store.ouraLoginError, OuraErrorKind.stale);
      expect(a.store.plan.eras, isEmpty);
      expect(a.oura.calls.where((c) => c.$1 == 'POST'), isEmpty, reason: 'ο κωδικός δεν χρησιμοποιήθηκε');
      // Η ίδια επιστροφή δύο φορές αμέσως μετά από επιτυχημένη σύνδεση: χωρίς μήνυμα.
      await connect(a.store, a.vault);
      expect(a.store.ouraLoginError, isNull);
      await a.store.completeOuraLogin('$ouraRedirectHttps?code=C&state=ξανά');
      expect(a.store.ouraLoginError, isNull);
    });
  
    test('A10: επαναφορά πηγών από αντίγραφο: σε κινητό χωρίς σχέδιο μπαίνει· νεότερο σχέδιο του κινητού ΜΕΝΕΙ', () async {
      final backupPlan = SourcePlan.samsungOnly.withEra(Source.oura, add(today, -20));
      final file = encodePlanFile(backupPlan, add(today, -19), at: 1000);
      // Νέο κινητό: κανένα σχέδιο.
      final a = app(plan: null);
      a.android.days[dateKey(add(today, -40))] = {K.steps: 4000, K.sleepMin: 400}; // έξω από τις 30 μέρες
      await boot(a.store);
      expect(await a.store.restoreSources((plan: file, log: appendPlanLog(null, backupPlan, 1000))), isTrue);
      expect(a.store.plan, backupPlan);
      expect(decodePlanFile(a.planFile.content), backupPlan);
      expect(lastLoggedPlan(a.planFile.log)!.plan, backupPlan);
      expect(a.android.days[dateKey(add(today, -40))], {K.steps: 4000, K.sleepMin: 400}, reason: 'τίποτα δεν σβήνεται από την επαναφορά');
      // Κινητό με νεότερο σχέδιο (ορίστηκε μετά το αντίγραφο): δεν αλλάζει.
      final newer = SourcePlan.samsungOnly.withEra(Source.oura, add(today, -5));
      final b = app(plan: null, planFile: MemoryPlanFile(encodePlanFile(newer, today, at: 5000)));
      await boot(b.store);
      expect(await b.store.restoreSources((plan: file, log: null)), isFalse);
      expect(b.store.plan, newer);
    });
});
}
