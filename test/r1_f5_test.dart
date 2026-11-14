// Round 1 · f5 («Oura, πηγές, συσκευές»): δοκιμές για τα ευρήματα S5-1 … S5-10, U2a, U2b, S4-5, S11-9.
// Οι αναμενόμενες τιμές βγήκαν από τον γραμμένο κανόνα (python, ώρες τοίχου / μέσοι όροι), όχι από τον κώδικα.
// Τρέχουν με TZ=Europe/Athens, όπως το CI· η δοκιμή της αλλαγής ώρας το ελέγχει ρητά. Σταθερό ρολόι: Σάββατο
// 14/11/2026 (εκτός αν μια δοκιμή ορίζει άλλη ώρα). Τίποτα από πραγματικά δεδομένα: όλα επινοημένα.
import 'dart:convert';

import 'package:flutter/material.dart';
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
import 'package:ygeia_forma/pages/devices_page.dart';
import 'package:ygeia_forma/pages/oura_pages.dart';
import 'package:ygeia_forma/pages/oura_sleep.dart';
import 'package:ygeia_forma/pages/oura_today.dart';
import 'package:ygeia_forma/pages/sources_page.dart';
import 'package:ygeia_forma/plan_file.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/widgets.dart';

import 'sample_data.dart';

// ---------------------------------------------------------------------------
// Βοηθοί
// ---------------------------------------------------------------------------

final _ouraStart = DateTime(2026, 11, 6);
final _at15 = DateTime(2026, 11, 14, 15);
final _p6 = SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 6));

DateTime _add(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

String _utc(DateTime t) => t.toUtc().toIso8601String();

/// Μία περίοδος ύπνου όπως τη δίνει η Oura.
Map<String, dynamic> _rec(String id, String day, String start, String end, int total,
        {int? latency, int? inBed, int? deep, int? light, int? rem, int? awake}) =>
    {
      'id': id,
      'day': day,
      'type': 'long_sleep',
      'bedtime_start': start,
      'bedtime_end': end,
      'total_sleep_duration': total,
      if (latency != null) 'latency': latency,
      if (inBed != null) 'time_in_bed': inBed,
      if (deep != null) 'deep_sleep_duration': deep,
      if (light != null) 'light_sleep_duration': light,
      if (rem != null) 'rem_sleep_duration': rem,
      if (awake != null) 'awake_time': awake,
    };

List<OuraNight> _nights(List<Map<String, dynamic>> sleep) =>
    parseOura(sleep: sleep, dailySleep: const [], readiness: const []).nights;

/// Store με Oura από 6/11 και νύχτες του δείγματος ως το [at] (εκτός από [missing]), όπως στα στιγμιότυπα.
HealthStore _ouraStore(DateTime at, {Set<DateTime> missing = const {}}) {
  final today = DateTime(at.year, at.month, at.day);
  final s = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(at));
  s.history = sampleHistory(at, s.data!);
  s.debugSetPlan(_p6);
  bool skip(DateTime d) => missing.any((m) => sameDay(m, d));
  final batch = parseOura(
    sleep: sampleOuraSleep(_ouraStart, at, missing: missing),
    dailySleep: [
      for (var d = _ouraStart; !d.isAfter(today); d = DateTime(d.year, d.month, d.day + 1))
        if (!skip(d)) {'id': 'ds${dateKey(d)}', 'day': dateKey(d), 'score': 70 + d.day % 15},
    ],
    readiness: [
      for (var d = _ouraStart; !d.isAfter(today); d = DateTime(d.year, d.month, d.day + 1))
        if (!skip(d)) {'id': 'dr${dateKey(d)}', 'day': dateKey(d), 'score': 64 + d.day % 12, 'temperature_deviation': (d.day % 5 - 2) / 10},
    ],
  );
  s.ouraNights = batch.nights;
  mergeOura(s.history, ouraRows(batch.nights), from: _ouraStart, to: today, plan: s.plan);
  s.ouraHasTokens = true;
  s.ouraLink = OuraLink(vault: MemoryVault(), clientId: 'TEST');
  s.ouraClock = () => at;
  s.ouraSyncedMs = at.subtract(const Duration(minutes: 12)).millisecondsSinceEpoch;
  return s;
}

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 2400)}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: w)));
  await t.pumpAndSettle();
}

Future<void> _pumpPage(WidgetTester t, Widget page, {Size size = const Size(400, 4000)}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: page));
  await t.pumpAndSettle();
}

/// U2a-02: καμία διάρκεια με «ω» / «λ» (π.χ. «22 λ», «1 ω 10 λ»).
void _noAbbreviatedDurations(WidgetTester t) {
  final abbr = RegExp(r'\d [ωλ](?![ά-ώ])');
  for (final w in t.widgetList<Text>(find.byType(Text))) {
    final s = w.data ?? w.textSpan?.toPlainText() ?? '';
    expect(abbr.hasMatch(s), isFalse, reason: s);
  }
}

/// Η πλευρά Android στα κανάλια (ίδια συμπεριφορά με το FakeAndroid του oura_store_test, μικρότερη).
class _Phone {
  _Phone(this.now);
  final DateTime now;
  Map<String, dynamic> prefs = {};
  final days = <String, Map<String, double>>{};

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
          final batch = jsonDecode(args['json'] as String) as List;
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

/// Ψεύτικη Oura: νύχτες του δείγματος από το [from]. [status] ≠ 200 για σφάλματα, [noData]: η νύχτα δεν ήρθε ακόμα.
class _Oura {
  _Oura(this.from, this.now);
  final DateTime from;
  final DateTime now;
  int status = 200;
  bool noData = false;
  int revokeStatus = 200;
  final calls = <(String, Uri)>[];

  Future<OuraResponse> send(String method, Uri url, {Map<String, String> headers = const {}, String? form}) async {
    calls.add((method, url));
    if (url.path.endsWith('/revoke')) return OuraResponse(revokeStatus, '{}');
    if (method == 'POST') {
      return OuraResponse(200, jsonEncode({'access_token': 'ACC', 'refresh_token': 'REF', 'expires_in': 86400}));
    }
    if (status != 200) return OuraResponse(status, '{}');
    final ep = url.pathSegments.last;
    final data = ep == 'sleep' && !noData ? sampleOuraSleep(from, now) : <Map<String, dynamic>>[];
    return OuraResponse(200, jsonEncode({'data': data, 'next_token': null}));
  }

  /// Αναγνώσεις δεδομένων (όχι η ανάκληση).
  int get gets => calls.where((c) => c.$1 == 'GET' && !c.$2.path.endsWith('/revoke')).length;
}

({HealthStore store, _Phone phone, _Oura oura, MemoryVault vault}) _app({
  required DateTime at,
  required DateTime Function() clock,
  SourcePlan? plan,
  DateTime? ouraFrom,
  bool withTokens = true,
}) {
  final p = plan ?? SourcePlan.samsungOnly.withEra(Source.oura, _add(DateTime(at.year, at.month, at.day), -3));
  final phone = _Phone(at)..install();
  final oura = _Oura(ouraFrom ?? p.ouraFrom ?? _ouraStart, at);
  final vault = MemoryVault();
  if (withTokens) {
    vault.data[vaultTokens] =
        OuraTokens(access: 'A0', refresh: 'R0', expiresAt: at.add(const Duration(days: 1)).millisecondsSinceEpoch).toJson();
  }
  final store = HealthStore()
    ..planFile = MemoryPlanFile(encodePlanFile(p, at, at: 1))
    ..ouraNightsFile = MemoryNightsFile()
    ..ouraClock = clock
    ..ouraLink = OuraLink(vault: vault, send: oura.send, clock: () => at, clientId: 'CID', tokenEndpoint: 'https://api.ouraring.com/oauth/token');
  return (store: store, phone: phone, oura: oura, vault: vault);
}

Future<void> _boot(HealthStore s) async {
  await s.loadPrefs();
  await s.start();
}

Future<void> _until(bool Function() done, {int tries = 300}) async {
  for (var i = 0; i < tries && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Περιμένει να τελειώσουν ανανέωση, ανάγνωση και συμπλήρωση που ξεκίνησαν (π.χ. από την επιστροφή στην εφαρμογή).
Future<void> _quiet(HealthStore s) async {
  await Future<void>.delayed(const Duration(milliseconds: 30));
  await _until(() => !s.loading && !s.ouraSyncing && !s.backfilling);
}

/// Τέλος δοκιμής: τίποτα δεν τρέχει πια, και το store φεύγει από τους παρατηρητές της εφαρμογής (οι δοκιμές οθονών
/// που ακολουθούν στο ίδιο αρχείο δεν πρέπει να το ξυπνήσουν).
Future<void> _done(HealthStore s) async {
  await _quiet(s);
  s.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Η γραμματοσειρά της εφαρμογής (όπως στα στιγμιότυπα και στο audit_d_test): με τη γραμματοσειρά δοκιμών κάθε
  // γράμμα είναι τετράγωνο και οι σελίδες θα «ξεχείλιζαν» χωρίς λόγο.
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
  });

  // -------------------------------------------------------------------------
  group('S5-1: «νύχτα ή υπνάκος» και ώρες στη ζώνη ώρας της ίδιας της εγγραφής', () {
    test('Νύχτα στο Λος Άντζελες (−08:00) διαβασμένη με κινητό στην Αθήνα: νύχτα 6 ωρών 30 λεπτών, ώρες τόπου', () {
      final n = _nights([
        _rec('la', '2026-11-26', '2026-11-26T02:30:00-08:00', '2026-11-26T09:30:00-08:00', 23400, latency: 600),
      ]).single;
      expect(n.main, isNotNull, reason: 'πριν: 12:30–19:30 ώρα Αθήνας → «μόνο υπνάκος»');
      expect(n.naps, isEmpty);
      expect(n.main!.offsetMin, -480);
      expect(hm(n.main!.wallStart), '02:30');
      expect(hm(n.main!.wallOnset!), '02:40');
      expect(hm(n.main!.wallEnd), '09:30');
      final row = ouraRow(n);
      expect(row[ouraKeys[K.sleepMin]!], 390);
      expect(row[ouraKeys[K.bedtime]!], 520, reason: '02:40 = 8 ώρες 40 λεπτά μετά τις 18:00');
      expect(row[ouraKeys[K.wake]!], 930, reason: '09:30 = 15 ώρες 30 λεπτά μετά τις 18:00');
      expect(row.containsKey(ouraKeys[K.napMin]!), isFalse);
    });

    test('Νύχτα στο Τόκιο (+09:00) 21:00–05:00: νύχτα 7 ωρών 30 λεπτών (πριν: 14:00–22:00 → υπνάκος)', () {
      final n = _nights([
        _rec('tk', '2026-11-25', '2026-11-24T21:00:00+09:00', '2026-11-25T05:00:00+09:00', 27000),
      ]).single;
      expect(n.main, isNotNull);
      expect(n.main!.offsetMin, 540);
      final row = ouraRow(n);
      expect(row[ouraKeys[K.sleepMin]!], 450);
      expect(row[ouraKeys[K.wake]!], 660, reason: '05:00 = 11 ώρες μετά τις 18:00');
    });

    test('Το αρχείο νυχτών κρατά τη ζώνη («tz»): ίδια νύχτα μετά την αποθήκευση', () {
      final nights = _nights([
        _rec('la', '2026-11-26', '2026-11-26T02:30:00-08:00', '2026-11-26T09:30:00-08:00', 23400, latency: 600),
      ]);
      expect(nights.single.main!.toJson()['tz'], -480);
      expect(nights.single.main!.toJson().containsKey('tz_end'), isFalse, reason: 'ίδια ζώνη αρχής και τέλους');
      final back = decodeOuraNights(encodeOuraNights(nights));
      expect(back.single.main!.offsetMin, -480);
      expect(back.single.main!.wallStart, DateTime(2026, 11, 26, 2, 30));
      expect(ouraRow(back.single), ouraRow(nights.single));
    });

    test('Χωρίς ζώνη («Z») ή στη ζώνη του κινητού: ακριβώς όπως πριν', () {
      final z = _nights([
        _rec('z', '2026-11-14', '2026-11-13T21:30:00.000Z', '2026-11-14T05:30:00.000Z', 25200),
      ]).single.main!;
      expect(z.offsetMin, isNull);
      expect(z.wallStart, z.start);
      expect(hm(z.wallStart), '23:30');
      final athens = _nights([
        _rec('a', '2026-11-14', '2026-11-13T23:30:00+02:00', '2026-11-14T07:30:00+02:00', 25200),
      ]).single.main!;
      expect(athens.offsetMin, 120);
      expect(athens.wallStart, athens.start);
      expect(athens.wallEnd, athens.end);
    });

    test('Νύχτα της αλλαγής ώρας 27→28/3/2027 στην Αθήνα (+02:00 → +03:00): ίδια με πριν, ξύπνημα 07:30', () {
      expect(DateTime(2027, 3, 29).timeZoneOffset - DateTime(2027, 3, 27).timeZoneOffset, const Duration(hours: 1),
          reason: 'οι δοκιμές τρέχουν με TZ=Europe/Athens');
      final n = _nights([
        _rec('dst', '2027-03-28', '2027-03-27T23:30:00+02:00', '2027-03-28T07:30:00+03:00', 24000, latency: 600),
      ]).single;
      expect(n.main!.offsetMin, 120);
      expect(n.main!.endOffsetMin, 180);
      expect(n.main!.toJson()['tz_end'], 180);
      expect(n.main!.wallEnd, n.main!.end);
      final row = ouraRow(n);
      expect(row[ouraKeys[K.sleepMin]!], 400);
      expect(row[ouraKeys[K.bedtime]!], 340, reason: '23:40');
      expect(row[ouraKeys[K.wake]!], 810, reason: '07:30');
    });
  });

  // -------------------------------------------------------------------------
  group('S5-2 / U2a-05: μετά τα μεσάνυχτα, πριν από τις 04:00, δεν «λείπει» η αποψινή νύχτα', () {
    final today = DateTime(2026, 11, 14);

    test('emptyNightReason: 00:20 και 03:59 → «θα φανεί το πρωί»· 04:00 → «περιμένει»· 13:00 → «δεν διαβάστηκε»', () {
      EmptyNight? at(DateTime now) =>
          emptyNightReason(plan: _p6, day: today, now: now, night: null, hasTokens: true, synced: DateTime(2026, 11, 13, 9));
      expect(at(DateTime(2026, 11, 14, 0, 20)), EmptyNight.notYet);
      expect(at(DateTime(2026, 11, 14, 3, 59)), EmptyNight.notYet);
      expect(at(DateTime(2026, 11, 14, 4)), EmptyNight.waiting);
      expect(at(DateTime(2026, 11, 14, 13)), EmptyNight.notRead);
      // Ένας υπνάκος του χθεσινού απογεύματος μετά τις 18:00 έχει τη σημερινή ημερομηνία: πριν από τις 04:00 όχι
      // «Μόνο υπνάκος».
      final nap = OuraNight(day: today, naps: [
        OuraSleep.fromJson(_rec('nap', '2026-11-14', _utc(DateTime(2026, 11, 13, 19)), _utc(DateTime(2026, 11, 13, 20)), 3000))!,
      ]);
      expect(emptyNightReason(plan: _p6, day: today, now: DateTime(2026, 11, 14, 0, 20), night: nap, hasTokens: true),
          EmptyNight.notYet);
      expect(emptyNightReason(plan: _p6, day: today, now: DateTime(2026, 11, 14, 13), night: nap, hasTokens: true),
          EmptyNight.onlyNap);
      expect(emptyNightText(EmptyNight.notYet), 'Η αποψινή νύχτα θα φανεί το πρωί');
    });

    test('ouraStatus: 00:20 → καμία κάρτα, «χθες βράδυ» = η νύχτα της 13/11· 05:00 → «Περιμένει το Oura»', () {
      final night = _ouraStore(DateTime(2026, 11, 14, 0, 20), missing: {today});
      expect(night.ouraStatus, OuraStatus.ok);
      expect(OuraStatusCard.shows(night), isFalse);
      expect(night.ouraNightDay(DateTime(2026, 11, 14, 0, 20)), DateTime(2026, 11, 13));
      final morning = _ouraStore(DateTime(2026, 11, 14, 5), missing: {today});
      morning.ouraSyncedMs = DateTime(2026, 11, 13, 9).millisecondsSinceEpoch;
      expect(morning.ouraStatus, OuraStatus.waiting);
      expect(OuraStatusCard.shows(morning), isTrue);
      expect(morning.ouraNightDay(DateTime(2026, 11, 14, 5)), today);
    });

    testWidgets('00:20: η κάρτα «Ύπνος» της Σήμερα δείχνει τη χθεσινή νύχτα, όχι «Περιμένει το Oura»', (t) async {
      final clock = DateTime(2026, 11, 14, 0, 20);
      final s = _ouraStore(clock, missing: {today});
      await _pump(t, SingleChildScrollView(child: OuraSleepTodayCard(store: s, now: clock, onTap: () {})));
      expect(find.text('Περιμένει το Oura'), findsNothing);
      expect(find.byKey(const ValueKey('oura-today-times')), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  test('S5-5: «Φάσεις · μέσος όρος 7 νυχτών» μετρά όλα τα κομμάτια μιας νύχτας σε κομμάτια', () {
    final nights = _nights([
      for (final d in [11, 12, 13])
        _rec('n$d', '2026-11-$d', _utc(DateTime(2026, 11, d - 1, 23)), _utc(DateTime(2026, 11, d, 7)), 23400,
            inBed: 28800, deep: 3600, light: 14400, rem: 5400, awake: 5400),
      _rec('a', '2026-11-14', _utc(DateTime(2026, 11, 13, 23, 30)), _utc(DateTime(2026, 11, 14, 3, 5)), 11700,
          inBed: 12900, deep: 3000, light: 6000, rem: 2700, awake: 1200),
      _rec('b', '2026-11-14', _utc(DateTime(2026, 11, 14, 5, 10)), _utc(DateTime(2026, 11, 14, 10, 20)), 16800,
          inBed: 18600, deep: 2400, light: 10200, rem: 4200, awake: 1800),
    ]);
    final split = nights.singleWhere((n) => sameDay(n.day, DateTime(2026, 11, 14)));
    expect(split.counted.length, 2);
    expect(split.nightMinutes, 475);
    final a = ouraStageAverages(nights, DateTime(2026, 11, 14), _p6);
    expect(a.nights, 4);
    // (3 × 3600 + 3000 + 2400) / 4 / 60 = 67,5 → 68 (πριν, μόνο η κύρια περίοδος: 55).
    expect(a.deep, 68);
    // (3 × 14400 + 6000 + 10200) / 4 / 60 = 247,5 → 248 (πριν: 223).
    expect(a.light, 248);
    // (3 × 5400 + 2700 + 4200) / 4 / 60 = 96,25 → 96 (πριν: 85).
    expect(a.rem, 96);
  });

  // -------------------------------------------------------------------------
  group('S5-6: 403 = άδεια ή συνδρομή· διέξοδος χωρίς «Αποσύνδεση»', () {
    test('Κείμενα σύνδεσης: λένε και τα δύο και τι να κάνεις· πουθενά «ο ύπνος μένει από το ρολόι» (U2b-13)', () {
      final sub = ouraLoginErrorText(OuraErrorKind.subscription);
      expect(sub, contains('άδεια'));
      expect(sub, contains('συνδρομή'));
      expect(ouraLoginErrorText(OuraErrorKind.scopeMissing), contains('«Daily»'));
      for (final k in OuraErrorKind.values) {
        expect(ouraLoginErrorText(k), isNot(contains('από το ρολόι')), reason: k.name);
        expect(ouraErrorText(k), isNot(contains('από το ρολόι')), reason: k.name);
      }
    });

    testWidgets('Σελίδα «Oura»: «Ενημέρωση τώρα» ΚΑΙ «Σύνδεση ξανά»· η κάρτα της Σήμερα έχει κουμπί', (t) async {
      final s = _ouraStore(_at15)..ouraError = OuraErrorKind.subscription;
      expect(s.ouraStatus, OuraStatus.subscription);
      await _pumpPage(t, OuraManagePage(store: s, now: _at15));
      expect(find.text('Ενημέρωση τώρα'), findsOneWidget);
      expect(find.byKey(const ValueKey('oura-reconnect')), findsOneWidget);
      await _pump(t, SingleChildScrollView(child: OuraStatusCard(store: s, now: _at15)));
      expect(find.text('Ρυθμίσεις Oura'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('S5-7: η ανάγνωση απέτυχε → «δεν διαβάστηκε ακόμα», όχι «δεν υπάρχουν δεδομένα»', () {
    final d = DateTime(2026, 11, 14);
    EmptyNight? r(DateTime day, {String? error, required DateTime synced}) => emptyNightReason(
        plan: _p6, day: day, now: DateTime(2026, 11, 14, 13), night: null, hasTokens: true, error: error, synced: synced);

    test('emptyNightReason', () {
      expect(r(d, error: 'network', synced: DateTime(2026, 11, 14, 7)), EmptyNight.notRead);
      expect(r(d, error: 'rateLimited', synced: DateTime(2026, 11, 14, 7)), EmptyNight.notRead);
      expect(r(d, error: 'proxyNotConfigured', synced: DateTime(2026, 11, 14, 7)), EmptyNight.notRead);
      expect(r(d, synced: DateTime(2026, 11, 14, 7)), EmptyNight.noRing, reason: 'χωρίς σφάλμα: όπως πριν');
      expect(r(DateTime(2026, 11, 7), error: 'network', synced: DateTime(2026, 11, 8, 9)), EmptyNight.noRing,
          reason: 'παλιά νύχτα, έξω από τις 3 μέρες που ξαναδιαβάζονται');
    });

    test('Κάρτα κατάστασης: μόνο όταν λείπει η νύχτα ή > 24 ώρες χωρίς επιτυχία', () {
      final missing = _ouraStore(_at15, missing: {d})..ouraError = OuraErrorKind.network;
      expect(missing.ouraStatus, OuraStatus.retry);
      expect(OuraStatusCard.shows(missing), isTrue);
      final fine = _ouraStore(_at15)..ouraError = OuraErrorKind.network;
      expect(OuraStatusCard.shows(fine), isFalse, reason: 'στιγμιαίο σφάλμα με όλα στη θέση τους');
      final stale = _ouraStore(_at15)
        ..ouraError = OuraErrorKind.proxyNotConfigured
        ..ouraSyncedMs = DateTime(2026, 11, 13, 9).millisecondsSinceEpoch;
      expect(OuraStatusCard.shows(stale), isTrue);
    });

    testWidgets('Η κάρτα λέει τον λόγο και έχει «Ενημέρωση τώρα»', (t) async {
      final s = _ouraStore(_at15, missing: {d})..ouraError = OuraErrorKind.network;
      await _pump(t, SingleChildScrollView(child: OuraStatusCard(store: s, now: _at15)));
      expect(find.text('Δεν διαβάστηκε ακόμα από την Oura'), findsOneWidget);
      expect(find.textContaining(ouraErrorText(OuraErrorKind.network)), findsOneWidget);
      expect(find.text('Ενημέρωση τώρα'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  test('S5-9: η εγγραφή των νέων tokens αποτυγχάνει → τα παλιά που δούλευαν ΔΕΝ σβήνονται', () async {
    final at = DateTime(2026, 11, 14, 15);
    final v = MemoryVault()
      ..data[vaultTokens] =
          OuraTokens(access: 'A0', refresh: 'R0', expiresAt: at.add(const Duration(days: 1)).millisecondsSinceEpoch).toJson();
    final o = _Oura(_ouraStart, at);
    final l = OuraLink(vault: v, send: o.send, clock: () => at, clientId: 'CID', tokenEndpoint: 'https://api.ouraring.com/oauth/token');
    expect((await l.tokens())!.refresh, 'R0');
    await l.begin(from: DateTime(2026, 11, 14));
    final state = OuraPending.fromJson(v.data[vaultPending])!.state;
    final ex = (await l.exchange('$ouraRedirectHttps?code=C&state=$state'))!;
    expect(ex.tokens.refresh, 'REF');
    v.failSaves = true;
    expect(await l.adopt(ex.tokens, ex.gen), isFalse);
    v.failSaves = false;
    expect(OuraTokens.fromJson(v.data[vaultTokens])!.refresh, 'R0', reason: 'πριν: το αρχείο σβηνόταν');
    expect((await l.tokens())!.refresh, 'R0');
    expect(await l.hasTokens, isTrue);
  });

  // -------------------------------------------------------------------------
  group('S5-10 / S5-3 / S5-8: εφαρμογή + Oura (ψεύτικα κανάλια και HTTP)', () {
    final today = DateTime(2026, 11, 14);

    test('S5-10: επιστροφή από την εφαρμογή Oura 3 λεπτά μετά: η νύχτα διαβάζεται (πριν: όχι για 30 λεπτά)', () async {
      var clock = DateTime(2026, 11, 14, 8, 20);
      final a = _app(at: clock, clock: () => clock);
      a.oura.noData = true;
      await _boot(a.store);
      expect(a.store.ouraStatus, OuraStatus.waiting);
      expect(a.phone.days[dateKey(today)]?[ouraKeys[K.sleepMin]!], isNull);
      final before = a.oura.gets;
      expect(before, greaterThan(0));
      a.oura.noData = false;
      clock = clock.add(const Duration(minutes: 3));
      a.store.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await _until(() => a.phone.days[dateKey(today)]?[ouraKeys[K.sleepMin]!] != null);
      await _quiet(a.store);
      expect(a.oura.gets, greaterThan(before));
      expect(a.phone.days[dateKey(today)]?[ouraKeys[K.sleepMin]!], isNotNull);
      expect(a.store.ouraStatus, OuraStatus.ok);
      await _done(a.store);
    });

    test('S5-10: τράβηγμα προς τα κάτω (refresh) = ρητή ενέργεια: διαβάζει το Oura αμέσως', () async {
      var clock = DateTime(2026, 11, 14, 8, 20);
      final a = _app(at: clock, clock: () => clock);
      a.oura.noData = true;
      await _boot(a.store);
      a.oura.noData = false;
      clock = clock.add(const Duration(minutes: 1));
      await a.store.refresh();
      await _quiet(a.store);
      expect(a.phone.days[dateKey(today)]?[ouraKeys[K.sleepMin]!], isNotNull);
      await _done(a.store);
    });

    test('S5-10: με τη νύχτα παρούσα η επιστροφή κρατά το όριο των 30 λεπτών· η ρητή ενέργεια όχι', () async {
      var clock = DateTime(2026, 11, 14, 9);
      final a = _app(at: clock, clock: () => clock);
      await _boot(a.store);
      expect(a.store.ouraStatus, OuraStatus.ok);
      final g = a.oura.gets;
      clock = clock.add(const Duration(minutes: 3));
      a.store.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await _quiet(a.store);
      expect(a.oura.gets, g, reason: 'τίποτα δεν περιμένουμε: καμία νέα ανάγνωση σε κάθε επιστροφή');
      await a.store.refresh();
      await _quiet(a.store);
      expect(a.oura.gets, greaterThan(g));
      await _done(a.store);
    });

    test('S5-10: φρένο 10″ για διπλό πάτημα· η αναμονή που ζήτησε η Oura (429) ισχύει και στη ρητή ενέργεια', () async {
      var clock = DateTime(2026, 11, 14, 9);
      final a = _app(at: clock, clock: () => clock);
      await _boot(a.store);
      final g = a.oura.gets;
      clock = clock.add(const Duration(seconds: 5));
      await a.store.refresh();
      await _quiet(a.store);
      expect(a.oura.gets, g, reason: 'μέσα σε ${ouraUserGap.inSeconds}″ από την προηγούμενη προσπάθεια');
      a.oura.status = 429;
      clock = clock.add(const Duration(seconds: 20));
      await a.store.refresh();
      await _quiet(a.store);
      expect(a.store.ouraError, OuraErrorKind.rateLimited);
      final g2 = a.oura.gets;
      a.oura.status = 200;
      clock = clock.add(const Duration(minutes: 1));
      await a.store.refresh();
      await _quiet(a.store);
      expect(a.oura.gets, g2, reason: 'χωρίς Retry-After η Oura ζητά 15 λεπτά');
      clock = clock.add(const Duration(minutes: 15));
      await a.store.refresh();
      await _quiet(a.store);
      expect(a.oura.gets, greaterThan(g2));
      expect(a.store.ouraError, isNull);
      await _done(a.store);
    });

    test('S5-3: «Σύνδεση ξανά» μέσα σε εποχή Oura που τρέχει: οι νύχτες διαβάζονται αμέσως, το σχέδιο δεν αλλάζει', () async {
      final clock = DateTime(2026, 11, 14, 15);
      final plan = SourcePlan.samsungOnly.withEra(Source.oura, _add(today, -5));
      final a = _app(at: clock, clock: () => clock, plan: plan, withTokens: false);
      await _boot(a.store);
      expect(a.store.ouraStatus, OuraStatus.reconnect);
      expect(a.oura.gets, 0);
      // Όπως ο παλιός δρόμος με «Όχι, από απόψε»: πρώτη νύχτα αύριο (η σελίδα πια δεν ρωτά σε εποχή Oura).
      expect(await a.store.beginOuraLogin(from: _add(today, 1)), isNull);
      final state = OuraPending.fromJson(a.vault.data[vaultPending])!.state;
      await a.store.completeOuraLogin('$ouraRedirectHttps?code=C&state=$state');
      await _until(() => a.phone.days[dateKey(today)]?[ouraKeys[K.sleepMin]!] != null);
      await _quiet(a.store);
      expect(a.phone.days[dateKey(today)]?[ouraKeys[K.sleepMin]!], isNotNull);
      expect(a.oura.gets, greaterThanOrEqualTo(4), reason: 'έλεγχος πρόσβασης + sleep, daily_sleep, daily_readiness');
      expect(a.store.plan, plan);
      expect(a.store.ouraStatus, OuraStatus.ok);
      await _done(a.store);
    });

    test('S5-8: αποσύνδεση χωρίς απάντηση της Oura στην ανάκληση → false (τα tokens σβήνονται)· με 200 → true', () async {
      final clock = DateTime(2026, 11, 14, 15);
      final a = _app(at: clock, clock: () => clock);
      a.oura.revokeStatus = 503;
      await _boot(a.store);
      expect(await a.store.disconnectOura(), isFalse);
      expect(a.vault.data.containsKey(vaultTokens), isFalse);
      expect(a.store.ouraHasTokens, isFalse);
      await _done(a.store);
      final b = _app(at: clock, clock: () => clock);
      await _boot(b.store);
      expect(await b.store.disconnectOura(), isTrue);
      await _done(b.store);
    });
  });

  // -------------------------------------------------------------------------
  group('U2a: σελίδες ύπνου του Oura', () {
    testWidgets('U2a-01: η μπάρα των φάσεων ζωγραφίζεται (κάθε κομμάτι έχει ύψος)', (t) async {
      await _pump(
        t,
        Center(child: SizedBox(width: 300, child: StackedBar(parts: [(70.0, Colors.red), (254.0, Colors.blue)]))),
      );
      final boxes = find.descendant(of: find.byType(StackedBar), matching: find.byType(ColoredBox));
      expect(boxes, findsNWidgets(2));
      expect(t.getSize(boxes.first).height, 12, reason: 'πριν: 0');
      expect(t.getSize(boxes.last).height, 12);
      expect(t.getSize(boxes.first).width, lessThan(t.getSize(boxes.last).width));
    });

    testWidgets('U2a-03/04/06 + S5-4/U2a-07: λείπει η χθεσινή νύχτα: πρόταση, γκρι, κουμπί, ημερομηνίες', (t) async {
      final s = _ouraStore(_at15, missing: {DateTime(2026, 11, 14), DateTime(2026, 11, 13)});
      expect(s.ouraNightReason(DateTime(2026, 11, 14), _at15), EmptyNight.noRing);
      await _pumpPage(t, OuraSleepPage(store: s, now: _at15));
      final note = find.byKey(const ValueKey('oura-last-night-note'));
      expect(note, findsOneWidget);
      final text = t.widget<Text>(note);
      expect(text.data, contains('Χθες βράδυ δεν ήρθε ύπνος από το δαχτυλίδι'));
      expect(text.data, isNot(contains('για χθες βράδυ')));
      expect(text.style!.color, Aigaio.of(t.element(note)).textSecondary, reason: 'κόκκινο μόνο όταν κάτι θέλει διόρθωση');
      expect(find.byKey(const ValueKey('oura-last-night-action')), findsOneWidget);
      // S5-4: η ετοιμότητα είναι της Πέμπτης 12/11, όχι «για σήμερα».
      expect(find.text('για σήμερα'), findsNothing);
      expect(find.text('για ${shortDayDate(DateTime(2026, 11, 12))}'), findsOneWidget);
      // U2a-07 / U2a-11: η ημερομηνία της νύχτας στις κάρτες της.
      final headers = t.widgetList<CardHeader>(find.byType(CardHeader)).toList();
      CardHeader h(String title) => headers.firstWhere((x) => x.title == title);
      expect(h('Τελευταία νύχτα').subtitle, 'Πέμ 12/11');
      expect(h('Καρδιά και θερμοκρασία στον ύπνο').subtitle, 'Πέμ 12/11');
      expect(h('Αναπνοή και οξυγόνο τη νύχτα').subtitle, 'Πέμ 12/11');
      // U2a-03: το οξυγόνο του ρολογιού ΔΕΝ «φαίνεται κανονικά» χωρίς νύχτα από το δαχτυλίδι.
      expect(find.textContaining('φαίνεται κανονικά'), findsNothing);
    });

    testWidgets('U2a-06: «χρειάζεται νέα σύνδεση» σε κόκκινο, με κουμπί «Σύνδεση ξανά»', (t) async {
      final s = _ouraStore(_at15, missing: {DateTime(2026, 11, 14)})
        ..ouraHasTokens = false
        ..ouraSyncedMs = DateTime(2026, 11, 13, 9).millisecondsSinceEpoch;
      expect(s.ouraNightReason(DateTime(2026, 11, 14), _at15), EmptyNight.reconnect);
      await _pumpPage(t, OuraSleepPage(store: s, now: _at15));
      final note = find.byKey(const ValueKey('oura-last-night-note'));
      expect(t.widget<Text>(note).style!.color, Aigaio.of(t.element(note)).bad);
      expect(find.widgetWithText(TextButton, 'Σύνδεση ξανά'), findsOneWidget);
    });

    testWidgets('U2a-03/04: κάρτα «Χθες βράδυ χωρίς ύπνο»: το οξυγόνο μένει κενό, οδηγία και κουμπί', (t) async {
      final s = _ouraStore(_at15, missing: {DateTime(2026, 11, 14)});
      expect(s.ouraStatus, OuraStatus.missing);
      await _pump(t, SingleChildScrollView(child: OuraStatusCard(store: s, now: _at15)));
      expect(find.textContaining('φαίνεται κανονικά'), findsNothing);
      expect(find.textContaining('το οξυγόνο της νύχτας μένει κενό'), findsOneWidget);
      expect(find.textContaining('Αν το φορούσες, άνοιξε την εφαρμογή Oura'), findsOneWidget);
      expect(find.text('Ενημέρωση τώρα'), findsOneWidget);
    });

    testWidgets('U2a-02/14/15/17: διάρκειες με λέξεις, υπόμνημα φάσεων, «βαθμολογία», στόχος αφής 48 dp', (t) async {
      final s = _ouraStore(_at15);
      await _pumpPage(t, OuraSleepPage(store: s, now: _at15));
      final legend = find.byKey(const ValueKey('oura-hypno-legend'));
      expect(legend, findsOneWidget);
      for (final n in const ['AWAKE', 'REM', 'LIGHT', 'DEEP']) {
        expect(find.descendant(of: legend, matching: find.text(stageLabel(n))), findsOneWidget, reason: n);
      }
      expect(t.getSize(find.byKey(const ValueKey('sleep-30-nights'))).height, greaterThanOrEqualTo(48));
      expect(find.textContaining('μαθαίνει το συνηθισμένο'), findsNothing);
      _noAbbreviatedDurations(t);
      await _pumpPage(t, OuraNightsPage(store: s, now: _at15));
      _noAbbreviatedDurations(t);
      expect(find.textContaining('τουλάχιστον '), findsWidgets, reason: 'ο χρόνος ξύπνιος «τουλάχιστον …», όχι «≥ … λ»');
      expect(find.textContaining('σκορ '), findsNothing);
    });

    testWidgets('U2a-09: ανοιχτό Fold (860 dp): «για σήμερα» σε μία γραμμή', (t) async {
      final s = _ouraStore(_at15);
      await _pumpPage(t, OuraSleepPage(store: s, now: _at15), size: const Size(860, 3000));
      expect(t.takeException(), isNull);
      expect(find.text('για σήμερα'), findsOneWidget);
      expect(t.getSize(find.text('για σήμερα')).height, lessThan(30));
    });

    test('U2a-11: τιμές που δεν σπάνε σε δύο γραμμές', () {
      expect(glued('Σάβ 14/11'), 'Σάβ 14/11');
      // Round 2 (R2-U1-6, h1): μόνο η τιμή με τη λέξη πριν από αυτήν (όλο το κομμάτι μετά το κόμμα σπούσε μέσα στη λέξη).
      expect(gluedValue('Οξυγόνο τη νύχτα, μέσος όρος 96%'), 'Οξυγόνο τη νύχτα, μέσος όρος\u00A096%');
      expect(gluedValue('χωρίς κόμμα 96%'), 'χωρίς κόμμα\u00A096%');
    });

    test('U2a-13 / S11-9: «από χθες», «από την Τρίτη», «από τη Δευτέρα», «από το Σάββατο», ≥ 7 μέρες με ημερομηνία', () {
      final sat = DateTime(2026, 11, 14, 15);
      expect(sinceDayText(DateTime(2026, 11, 13), sat), 'χθες');
      expect(sinceDayText(DateTime(2026, 11, 10), sat), 'την Τρίτη');
      expect(sinceDayText(DateTime(2026, 11, 9), sat), 'τη Δευτέρα');
      expect(sinceDayText(DateTime(2026, 11, 8), sat), 'την Κυριακή');
      expect(sinceDayText(DateTime(2026, 11, 14), DateTime(2026, 11, 19, 9)), 'το Σάββατο');
      // Τετάρτη 4/11 από Τετάρτη 11/11: η σκέτη «Τετάρτη» θα διαβαζόταν «από σήμερα».
      expect(sinceDayText(DateTime(2026, 11, 4), DateTime(2026, 11, 11, 9)), 'Τετ 4/11');
      expect(sinceDayText(DateTime(2026, 11, 7), sat), 'Σάβ 7/11');
    });

    test('S4-5: μία νύχτα απέναντι στη σύσταση «τουλάχιστον 7 ώρες» (μετρημένος ύπνος ≠ δηλωμένες ώρες)', () {
      // 6 ώρες 40 λεπτά ύπνος, 7 ώρες 45 λεπτά στο κρεβάτι: καμία ετυμηγορία «κάτω».
      final a = sleepVsAdvice(asleepMin: 400, inBedMin: 465, adviceMin: 420);
      expect(a, contains('ύπνος 6 ώρες 40 λεπτά'));
      expect(a, contains('στο κρεβάτι 7 ώρες 45 λεπτά'));
      expect(a, contains('δηλώνουν οι ίδιοι οι άνθρωποι'));
      expect(a, isNot(contains('κάτω από')));
      expect(a, isNot(contains('λιγότερο από τη σύσταση')));
      // Και ο χρόνος στο κρεβάτι κάτω από τη σύσταση: το λέμε (αληθές με κάθε τρόπο μέτρησης).
      final b = sleepVsAdvice(asleepMin: 340, inBedMin: 370, adviceMin: 420);
      expect(b, contains('λιγότερο από τη σύσταση για ενήλικες (τουλάχιστον 7 ώρες)'));
      // Ύπνος ≥ σύσταση.
      final c = sleepVsAdvice(asleepMin: 425, inBedMin: 450, adviceMin: 420);
      expect(c, contains('όσο ζητά η σύσταση'));
      // Χωρίς χρόνο στο κρεβάτι: καμία ετυμηγορία, μόνο η εξήγηση.
      final d = sleepVsAdvice(asleepMin: 400, inBedMin: null, adviceMin: 420);
      expect(d, isNot(contains('λιγότερο από')));
      expect(d, contains('δηλώνουν οι ίδιοι οι άνθρωποι'));
      for (final x in [a, b, c, d]) {
        expect(x, startsWith('Μία νύχτα'));
        expect(x, endsWith('Μετρά ο μέσος όρος πολλών νυχτών.'));
      }
    });
  });

  // -------------------------------------------------------------------------
  group('U2b: σελίδα «Oura», «Σύνδεση Oura», «Πηγές», «Τι μετράει κάθε συσκευή»', () {
    final noneFrom15 = _p6.withEra(Source.none, DateTime(2026, 11, 15));
    final noneFrom13 = _p6.withEra(Source.none, DateTime(2026, 11, 13));
    final watchFrom15 = noneFrom13.withEra(Source.watch, DateTime(2026, 11, 15));

    testWidgets('U2b-01: τη μέρα της αποσύνδεσης: «Ο ύπνος ξανά από το ρολόι», όχι ξανά «Αποσύνδεση»', (t) async {
      final s = _ouraStore(_at15)
        ..debugSetPlan(noneFrom15)
        ..ouraHasTokens = false;
      expect(s.ouraStatus, OuraStatus.disconnected);
      await _pumpPage(t, OuraManagePage(store: s, now: _at15));
      expect(find.byKey(const ValueKey('oura-watch-again')), findsOneWidget);
      expect(find.byKey(const ValueKey('oura-disconnect')), findsNothing);
      expect(find.textContaining('Η ενημέρωση γίνεται μόνη της'), findsNothing);
    });

    testWidgets('U2b-01: «Χρειάζεται νέα σύνδεση»: όχι «Η ενημέρωση γίνεται μόνη της»', (t) async {
      final s = _ouraStore(_at15)..ouraHasTokens = false;
      expect(s.ouraStatus, OuraStatus.reconnect);
      await _pumpPage(t, OuraManagePage(store: s, now: _at15));
      expect(find.textContaining('Η ενημέρωση γίνεται μόνη της'), findsNothing);
      expect(find.text('Σύνδεση ξανά'), findsOneWidget);
    });

    testWidgets('U2b-06/07/08: χωρίς πηγή ύπνου: η πραγματική πηγή, «Καμία», βήματα από Samsung Health', (t) async {
      final s = _ouraStore(_at15)
        ..debugSetPlan(noneFrom13)
        ..ouraHasTokens = false;
      await _pumpPage(t, OuraManagePage(store: s, now: _at15));
      expect(find.text('Oura · όχι τώρα'), findsNothing);
      expect(find.text('Samsung Health'), findsOneWidget);
      expect(find.text('Καμία'), findsNWidgets(sourceRows.where((r) => r.group == SourceGroup.night).length + 1));
    });

    testWidgets('U2b-09: μετά το «Ο ύπνος ξανά από το ρολόι»: η σελίδα και η κάρτα το λένε', (t) async {
      final s = _ouraStore(_at15)
        ..debugSetPlan(watchFrom15)
        ..ouraHasTokens = false;
      expect(s.watchSleepFromTonight, isTrue);
      expect(s.ouraStatus, OuraStatus.disconnected);
      await _pumpPage(t, OuraManagePage(store: s, now: _at15));
      expect(find.textContaining('Από απόψε ο ύπνος έρχεται από το ρολόι, όπως διάλεξες'), findsOneWidget);
      expect(find.byKey(const ValueKey('oura-watch-again')), findsNothing);
      await _pump(t, SingleChildScrollView(child: OuraStatusCard(store: s, now: _at15)));
      expect(find.text('Από απόψε ο ύπνος από το ρολόι'), findsOneWidget);
    });

    testWidgets('U2b-10: άγνωστο σχέδιο πηγών: όχι «Αποσυνδέθηκε», μόνο «Άνοιξε τις Πηγές»', (t) async {
      final s = _ouraStore(_at15)
        ..debugSetPlan(SourcePlan([SourceEra(Source.none, DateTime(2026, 11, 1))]), state: PlanState.unknown);
      expect(s.planUnknown, isTrue);
      await _pumpPage(t, OuraManagePage(store: s, now: _at15));
      expect(find.text('Αποσυνδέθηκε'), findsNothing);
      expect(find.byKey(const ValueKey('oura-watch-again')), findsNothing);
      expect(find.byKey(const ValueKey('oura-open-sources')), findsOneWidget);
    });

    testWidgets('U2b-11: αποσύνδεση πριν αρχίσει το Oura: σωστή συνέπεια, μετά κουμπί σύνδεσης, καμία άδεια κάρτα', (t) async {
      expect((_ouraStore(_at15)..debugSetPlan(SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 15))))
          .sleepSourceAfterDisconnect, Source.watch);
      expect(_ouraStore(_at15).sleepSourceAfterDisconnect, Source.none);
      final after = _ouraStore(_at15)
        ..debugSetPlan(SourcePlan.samsungOnly)
        ..ouraHasTokens = false;
      expect(after.ouraStatus, OuraStatus.off);
      await _pumpPage(t, OuraManagePage(store: after, now: _at15));
      expect(find.byKey(const ValueKey('oura-connect-open')), findsOneWidget);
      expect(find.byKey(const ValueKey('oura-disconnect')), findsNothing);
      expect(find.byKey(const ValueKey('oura-watch-again')), findsNothing);
    });

    testWidgets('U2b-12: λείπει η χθεσινή νύχτα το πρωί: η σελίδα «Oura» λέει τι να κάνεις', (t) async {
      final clock = DateTime(2026, 11, 14, 8, 5);
      final s = _ouraStore(clock, missing: {DateTime(2026, 11, 14)})
        ..ouraSyncedMs = DateTime(2026, 11, 14, 7, 50).millisecondsSinceEpoch;
      expect(s.ouraStatus, OuraStatus.waiting);
      await _pumpPage(t, OuraManagePage(store: s, now: clock));
      expect(find.textContaining('δεν χρειάζεται να κάνεις τίποτα'), findsNothing);
      expect(find.textContaining('Η χθεσινή νύχτα δεν έχει φτάσει ακόμα'), findsOneWidget);
    });

    for (final (name, plan, clock, expected) in [
      ('εποχή Oura σε εξέλιξη (S5-3)', _p6, DateTime(2026, 11, 14, 15), 'Οι νύχτες του δαχτυλιδιού που έλειψαν έρχονται μόλις συνδεθείς.'),
      ('πρώτη σύνδεση στις 10:00', SourcePlan.samsungOnly, DateTime(2026, 11, 14, 10),
          'Πριν ανοίξει η σελίδα της Oura θα σε ρωτήσουμε αν φορούσες το δαχτυλίδι την τελευταία νύχτα.'),
      ('πρώτη σύνδεση στις 02:00', SourcePlan.samsungOnly, DateTime(2026, 11, 14, 2), 'Η νύχτα που κοιμάσαι τώρα θα μετρά από το δαχτυλίδι.'),
    ]) {
      testWidgets('U2b-13/19: «Σύνδεση Oura» λέει αυτό που θα γίνει: $name', (t) async {
        final s = _ouraStore(clock)
          ..debugSetPlan(plan)
          ..ouraHasTokens = false;
        await _pumpPage(t, OuraConnectPage(store: s, now: clock));
        expect(find.textContaining(expected), findsOneWidget);
        expect(find.textContaining('Μετά τις 04:00 θα σε ρωτήσουμε'), findsNothing);
        expect(find.textContaining('Οι νύχτες πριν μένουν όπως είναι, από το ρολόι'), findsNothing);
      });
    }

    testWidgets('U2b-02/03/07/16/17: Πηγές χωρίς πηγή ύπνου', (t) async {
      final s = _ouraStore(_at15)
        ..debugSetPlan(noneFrom13)
        ..ouraHasTokens = false;
      await _pumpPage(t, SourcesPage(store: s, now: _at15));
      expect(find.text('Διαχείριση'), findsOneWidget, reason: 'η γραμμή Oura ανοίγει τη σελίδα «Oura»');
      expect(find.text('Ρυθμίσεις Oura'), findsOneWidget);
      expect(find.textContaining('το ρολόι μετρά το οξυγόνο της νύχτας μόνο μέσα στις ώρες ύπνου'), findsOneWidget);
      expect(find.textContaining('από το βράδυ της μέρας που την έκανες'), findsNothing);
      expect(find.textContaining('Μία πηγή για κάθε μέτρηση'), findsOneWidget);
      expect(find.textContaining('Μέσω Samsung Health ·\u00A0διαβάστηκε'), findsOneWidget);
    });

    testWidgets('U2b-14: μετά το «ξανά από το ρολόι» οι Πηγές δεν λένε «δεν διαβάζεται»· με Oura το λένε', (t) async {
      final clock = DateTime(2026, 11, 16, 15);
      final s = _ouraStore(clock)
        ..debugSetPlan(watchFrom15)
        ..ouraHasTokens = false;
      await _pumpPage(t, SourcesPage(store: s, now: clock));
      expect(find.textContaining('Ο ύπνος του ρολογιού δεν διαβάζεται'), findsNothing);
      expect(find.textContaining('Ύπνος του ρολογιού: δεν διαβάζεται'), findsNothing);
    });

    testWidgets('U2b-14: με το Oura πηγή του ύπνου η πρόταση μένει', (t) async {
      final s = _ouraStore(_at15);
      await _pumpPage(t, SourcesPage(store: s, now: _at15));
      expect(find.textContaining('Ο ύπνος του ρολογιού δεν διαβάζεται'), findsOneWidget);
    });

    test('U2b-04/05/07 (S4-8): τα κείμενα του πίνακα πηγών συμφωνούν με τον κώδικα', () {
      final avg = notUsedWithOura.singleWhere((s) => s.startsWith('Μέσος όρος οξυγόνου του ρολογιού'));
      expect(avg, contains('Τάσεις'));
      expect(avg, contains('αναφορά'));
      final oxMin = sourceRows.singleWhere((r) => r.needsNight);
      expect(oxMin.noteFor(Source.none), contains('μόνο μέσα στις ώρες ύπνου'));
      final steps = sourceRows.singleWhere((r) => r.metrics.contains(K.steps));
      expect(steps.noteFor(Source.watch), samsungTotalLabel);
      expect(steps.noteFor(Source.none, unknown: true), contains('δες την κάρτα πάνω'));
      expect(steps.noteFor(Source.none), contains('συνδέσεις ξανά'));
    });

    testWidgets('U2b-18: «Τι μετράει κάθε συσκευή» σε δύο στήλες στο ανοιχτό Fold', (t) async {
      await _pumpPage(t, const DevicesPage(), size: const Size(860, 2400));
      expect(t.takeException(), isNull);
      final ring = t.getRect(find.text('Oura Ring 5'));
      final watch = t.getRect(find.text('Galaxy Watch Ultra 2'));
      expect(watch.left, greaterThan(ring.left + 200));
    });

    testWidgets('U2b-18: στο κινητό μία στήλη, με την ίδια σειρά', (t) async {
      await _pumpPage(t, const DevicesPage(), size: const Size(400, 6000));
      final ring = t.getRect(find.text('Oura Ring 5'));
      final watch = t.getRect(find.text('Galaxy Watch Ultra 2'));
      expect(watch.left, ring.left);
      expect(watch.top, greaterThan(ring.top));
    });
  });
}
