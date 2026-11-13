// Round 1 · f3 · «Samsung Health → ιστορικό, ρυθμίσεις, πηγές». Μία ομάδα ανά εύρημα των συμβουλίων S3, S9, S11, S1 και
// οι δοκιμές του S12 για ανάγνωση δεδομένων και κανόνες του ιστορικού. Όλα τα νούμερα είναι φανταστικά (δημόσιο repo)·
// οι αναμενόμενες τιμές βγήκαν με το χέρι από τον γραμμένο κανόνα, όχι από τον κώδικα.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/adaptive_check.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/oura/oura_api.dart';
import 'package:ygeia_forma/oura/oura_store.dart';
import 'package:ygeia_forma/pages/checkin_card.dart';
import 'package:ygeia_forma/pages/prefs_notice.dart';
import 'package:ygeia_forma/plan_file.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/waist.dart';

import 'sample_checkin.dart';
import 'sample_data.dart';

int _ms(DateTime t) => t.millisecondsSinceEpoch;
DateTime _add(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
Map<String, Map<String, double>> _copy(Map<String, Map<String, double>> h) => {for (final e in h.entries) e.key: {...e.value}};

/// Μία νύχτα ρολογιού 9→10/11/2026, 23:30–07:00, με φάσεις: ελαφρύς 120′ + βαθύς 90′ + REM 90′ + ελαφρύς 140′ +
/// ξύπνιος 10′ → πραγματικός ύπνος 440′, βαθύς και REM 90 ÷ 440 = 20,45%. Ανάγνωση στις 10/11 12:00.
/// [heart]: μέσοι παλμοί τριών μετρήσεων μέσα στον ύπνο (00:00, 02:00, 04:00)· [spo2]: (μέσο, ελάχιστο)· [skin]: °C.
/// null = το κλειδί ΛΕΙΠΕΙ από την απάντηση (η άδειά του στη Samsung Health είναι κλειστή).
Map<String, dynamic> _oneNight({List<int>? heart = const [50, 54, 58], List<int>? spo2 = const [95, 91], double? skin = 34.5}) {
  DateTime at(int d, int h, int m) => DateTime(2026, 11, d, h, m);
  return {
    'ok': true,
    'readAt': _ms(at(10, 12, 0)),
    'granted': 10,
    'total': 10,
    'sleep': [
      {
        'start': _ms(at(9, 23, 30)),
        'end': _ms(at(10, 7, 0)),
        'minutes': 450,
        'score': 80,
        'stages': [
          ['LIGHT', _ms(at(9, 23, 30)), _ms(at(10, 1, 30))],
          ['DEEP', _ms(at(10, 1, 30)), _ms(at(10, 3, 0))],
          ['REM', _ms(at(10, 3, 0)), _ms(at(10, 4, 30))],
          ['LIGHT', _ms(at(10, 4, 30)), _ms(at(10, 6, 50))],
          ['AWAKE', _ms(at(10, 6, 50)), _ms(at(10, 7, 0))],
        ],
      },
    ],
    if (heart != null)
      'heart': [
        for (var i = 0; i < heart.length; i++)
          [_ms(at(10, i * 2, 0)), _ms(at(10, i * 2, 30)), heart[i], heart[i] - 3, heart[i] + 4],
      ],
    if (spo2 != null)
      'spo2': [
        [_ms(at(9, 23, 30)), _ms(at(10, 7, 0)), spo2[0], spo2[1], 98],
      ],
    if (skin != null)
      'skinTemp': [
        [_ms(at(9, 23, 30)), _ms(at(10, 7, 0)), skin],
      ],
    'steps': [
      [_ms(at(10, 0, 0)), 4321],
    ],
    'exercise': <Object>[],
  };
}

/// Μια κανονική ανάγνωση στο ιστορικό, όπως τη γράφει η εφαρμογή (HealthStore._updateRecentHistory). [keep] false: όπως
/// ΠΡΙΝ από τη διόρθωση (χωρίς το «τι δεν διαβάστηκε»), για να φαίνεται ότι η δοκιμή βλέπει τη διαφορά.
Set<String> _apply(Map<String, Map<String, double>> h, Map<String, dynamic> j, {bool keep = true}) {
  final p = parseDashboardSync(jsonEncode(j), plan: SourcePlan.samsungOnly);
  return applyRecentRead(h, p.data!,
      plan: SourcePlan.samsungOnly,
      sleepFailed: p.sleepFailed,
      heartFailed: p.heartFailed,
      rows: p.rows,
      keepKeys: keep ? p.keep : const <String>{});
}

/// Η πλευρά Android στο κανάλι «ygeia/samsung» για τις ρυθμίσεις: το «αρχείο» ([load], όπως το απαντά η Kotlin) και οι
/// εγγραφές του.
class _Phone {
  _Phone(this.now);
  final DateTime now;

  /// Η απάντηση του «loadPrefs» (κείμενο).
  String load = '{}';

  /// Τι βρίσκει το «loadPrefs» αφού το χαλασμένο αρχείο μπει στην άκρη (π.χ. μόνο το όνομα της αναφοράς).
  String afterSetAside = '{}';
  bool saveOk = true;
  final calls = <String>[];
  final saved = <Map<String, dynamic>>[];
  final days = <String, Map<String, double>>{};
  var saveDaysCalls = 0;

  int count(String method) => calls.where((c) => c == method).length;

  void install() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('ygeia/samsung'), (call) async {
      final args = call.arguments is Map ? call.arguments as Map : const {};
      switch (call.method) {
        case 'loadPrefs':
          calls.add('loadPrefs');
          return load;
        case 'savePrefs':
          calls.add('savePrefs');
          if (!saveOk) return '{"ok":false,"kind":"write"}';
          final j = jsonDecode(args['json'] as String) as Map<String, dynamic>;
          saved.add(j);
          load = jsonEncode(j);
          return '{"ok":true}';
        case 'prefsSetAside':
          calls.add('prefsSetAside');
          load = afterSetAside;
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
      return '{"ok":true}';
    });
    m.setMockMethodCallHandler(const MethodChannel('ygeia/oura'), (call) async => null);
    m.setMockMethodCallHandler(const MethodChannel('ygeia/errors'), (call) async => null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // -------------------------------------------------------------------------------------------------------------
  group('S3-1 (ΚΡΙΣΙΜΟ): άδεια της Samsung Health κλειστή = «δεν διαβάστηκε», ποτέ «δεν υπάρχουν δεδομένα»', () {
    test('notReadKeys: κλειδί που λείπει ή σφάλμα → οι τιμές του μένουν· άδεια λίστα = διαβάστηκε', () {
      final when = DateTime(2026, 10, 24, 20);
      expect(notReadKeys(sampleDashboardJson(when)), isEmpty);
      expect(notReadKeys(sampleDashboardJson(when)..remove('heart')), {K.sleepHr, K.restHr, K.dayHr, K.walkHr});
      expect(notReadKeys(sampleDashboardJson(when)..['heart'] = {'error': 'x'}), {K.sleepHr, K.restHr, K.dayHr, K.walkHr});
      // Μόνο οι ασκήσεις: οι παλμοί ύπνου διαβάστηκαν, οι παλμοί της μέρας όχι (DATA-06).
      expect(notReadKeys(sampleDashboardJson(when)..remove('exercise')), {K.restHr, K.dayHr, K.walkHr});
      expect(notReadKeys(sampleDashboardJson(when)..remove('spo2')), {K.spo2Avg, K.spo2Min, K.spo2Low, K.spo2Cov});
      expect(notReadKeys(sampleDashboardJson(when)..remove('skinTemp')), {K.skinTemp});
      expect(
        notReadKeys(sampleDashboardJson(when)
          ..['heart'] = <Object>[]
          ..['spo2'] = <Object>[]
          ..['skinTemp'] = <Object>[]),
        isEmpty,
        reason: 'η άδεια λίστα είναι «διαβάστηκε, δεν υπάρχει τίποτα»',
      );
      // Και οι δύο αναγνώσεις το μεταφέρουν.
      final j = sampleDashboardJson(when)..remove('spo2');
      expect(parseDashboardSync(jsonEncode(j)).keep, {K.spo2Avg, K.spo2Min, K.spo2Low, K.spo2Cov});
      expect(parseRangeSync(jsonEncode(j), DateTime(2026, 10, 1), DateTime(2026, 10, 20)).keep,
          {K.spo2Avg, K.spo2Min, K.spo2Low, K.spo2Cov});
      expect(parseDashboardSync(jsonEncode(sampleDashboardJson(when))).keep, isEmpty);
    });

    test('30 νύχτες: ανανέωση με ΜΙΑ άδεια κλειστή δεν αλλάζει καμία αποθηκευμένη τιμή', () {
      final when = DateTime(2026, 10, 24, 20);
      final h = <String, Map<String, double>>{};
      _apply(h, sampleDashboardJson(when));
      final before = _copy(h);
      int nights(Map<String, Map<String, double>> x, String k) => x.values.where((r) => r.containsKey(k)).length;
      // Η δοκιμή έχει νόημα μόνο αν υπάρχουν τιμές να χαθούν.
      for (final k in [K.sleepMin, K.sleepHr, K.spo2Avg, K.spo2Min, K.skinTemp]) {
        expect(nights(before, k), greaterThanOrEqualTo(28), reason: k);
      }
      const lost = {
        'heart': [K.sleepHr],
        'spo2': [K.spo2Avg, K.spo2Min],
        'skinTemp': [K.skinTemp],
      };
      for (final gone in lost.keys) {
        final j = sampleDashboardJson(when)
          ..remove(gone)
          ..['granted'] = 9;
        // Όπως πριν από τη διόρθωση: οι τιμές του είδους σβήνονταν από όλες τις νύχτες της ανάγνωσης.
        final old = _copy(before);
        _apply(old, j, keep: false);
        for (final k in lost[gone]!) {
          expect(nights(old, k), 0, reason: 'χωρίς τη διόρθωση: $gone κλειστό → $k χάνεται');
        }
        // Με τη διόρθωση: το ιστορικό μένει ίδιο, τιμή προς τιμή, και τίποτα δεν ξαναγράφεται.
        final now = _copy(before);
        final changed = _apply(now, j);
        expect(now, before, reason: 'άδεια «$gone» κλειστή');
        expect(changed, isEmpty, reason: 'άδεια «$gone» κλειστή: καμία μέρα δεν αλλάζει');
      }
    });

    test('ακριβείς τιμές: κλειστή άδεια → μένουν· ανοιχτή ξανά → ενημερώνονται· άδεια λίστα → σβήνονται', () {
      const day = '2026-11-10';
      final h = <String, Map<String, double>>{};
      _apply(h, _oneNight());
      expect(h[day]![K.sleepMin], 440);
      expect(h[day]![K.sleepScore], 80);
      expect(h[day]![K.deepPct], closeTo(20.4545, 0.001));
      expect(h[day]![K.remPct], closeTo(20.4545, 0.001));
      expect(h[day]![K.awakeMin], 10);
      expect((h[day]![K.bedtime], h[day]![K.wake]), (330, 780), reason: '23:30 και 07:00, σε λεπτά μετά τις 18:00');
      expect(h[day]![K.sleepHr], 54, reason: '(50 + 54 + 58) ÷ 3');
      expect((h[day]![K.spo2Avg], h[day]![K.spo2Min]), (95, 91));
      expect(h[day]![K.skinTemp], 34.5);
      expect(h[day]![K.steps], 4321);

      // Η άδεια «Παλμοί» κλειστή (το κλειδί λείπει)· το οξυγόνο διαβάστηκε με νέες τιμές.
      _apply(h, _oneNight(heart: null, spo2: const [96, 92]));
      expect(h[day]![K.sleepHr], 54, reason: 'δεν διαβάστηκε: η αποθηκευμένη τιμή μένει');
      expect((h[day]![K.spo2Avg], h[day]![K.spo2Min]), (96, 92), reason: 'ό,τι διαβάστηκε ενημερώνεται κανονικά');
      expect((h[day]![K.sleepMin], h[day]![K.skinTemp]), (440, 34.5));

      // Όλες οι άδειες κλειστές εκτός από τον ύπνο και τα βήματα: καμία τιμή νύχτας δεν φεύγει.
      final allOff = _copy(h);
      _apply(allOff, _oneNight(heart: null, spo2: null, skin: null));
      expect(allOff[day], h[day]);

      // Η άδεια ξανά ανοιχτή, με νέες μετρήσεις: (60 + 62 + 64) ÷ 3 = 62.
      _apply(h, _oneNight(heart: const [60, 62, 64], spo2: const [96, 92]));
      expect(h[day]![K.sleepHr], 62);

      // Άδεια ανοιχτή και κανένας παλμός (το ρολόι δεν μέτρησε): τότε, και μόνο τότε, η τιμή φεύγει.
      _apply(h, _oneNight(heart: const [], spo2: const [96, 92]));
      expect(h[day]!.containsKey(K.sleepHr), isFalse);
      expect(h[day]![K.sleepMin], 440);
    });

    test('επανανάγνωση ιστορικού (κομμάτι): κλειστή άδεια δεν σβήνει τις τιμές της από το κομμάτι', () {
      const day = '2026-11-10';
      final from = DateTime(2026, 11, 1), to = DateTime(2026, 11, 10);
      final base = <String, Map<String, double>>{};
      _apply(base, _oneNight());
      final r = parseRangeSync(jsonEncode(_oneNight(heart: null, skin: null)), from, to);
      expect((r.ok, r.sleepOk, r.sleepFailed, r.heartFailed), (true, true, false, false));
      expect(r.keep, {K.sleepHr, K.restHr, K.dayHr, K.walkHr, K.skinTemp});
      // Πριν: «replaceSleep» σε κάθε κομμάτι έσβηνε παλμούς ύπνου και θερμοκρασία από ΟΛΟ το ιστορικό.
      final old = _copy(base);
      mergeHistory(old, _copy(r.rows), replaceSleep: true, rangeFrom: from, rangeTo: to, plan: SourcePlan.samsungOnly);
      expect((old[day]!.containsKey(K.sleepHr), old[day]!.containsKey(K.skinTemp)), (false, false));
      final h = _copy(base);
      mergeHistory(h, _copy(r.rows),
          replaceSleep: true, rangeFrom: from, rangeTo: to, plan: SourcePlan.samsungOnly, keepKeys: r.keep);
      expect(h, base, reason: 'κάθε αποθηκευμένη τιμή της νύχτας μένει ίδια');
    });

    test('νύχτα του Oura: το οξυγόνο του ρολογιού μένει όταν η άδεια «Οξυγόνο» είναι κλειστή', () {
      final plan = SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 1));
      Map<String, Map<String, double>> stored() => {
            '2026-11-10': {'o.sleepMin': 410, K.spo2Min: 87, K.spo2Cov: 0.8, K.steps: 4000},
          };
      final rows = {
        '2026-11-10': {K.steps: 5000.0},
      };
      final keep = notReadKeys({'sleep': <Object>[], 'heart': <Object>[], 'exercise': <Object>[], 'skinTemp': <Object>[]});
      expect(keep, {K.spo2Avg, K.spo2Min, K.spo2Low, K.spo2Cov});
      final old = stored();
      mergeHistory(old, _copy(rows), sleepFrom: DateTime(2026, 10, 12), plan: plan, ouraNights: {'2026-11-10'});
      expect(old['2026-11-10'], {'o.sleepMin': 410.0, K.steps: 5000.0}, reason: 'πριν: το οξυγόνο της νύχτας χανόταν');
      final h = stored();
      mergeHistory(h, _copy(rows), sleepFrom: DateTime(2026, 10, 12), plan: plan, keepKeys: keep, ouraNights: {'2026-11-10'});
      expect(h['2026-11-10'], {'o.sleepMin': 410.0, K.spo2Min: 87.0, K.spo2Cov: 0.8, K.steps: 5000.0});
    });
  });

  // -------------------------------------------------------------------------------------------------------------
  group('S3-7: ύπνος του ρολογιού που δεν διαβάστηκε δεν αλλάζει τους παλμούς της μέρας', () {
    final now = DateTime(2026, 11, 8, 16, 30);
    final day = DateTime(2026, 11, 6);
    final k = dateKey(day);

    test('χωρίς διαβασμένο ύπνο (σφάλμα ή κλειστή άδεια) η σύνοψη δεν έχει παλμούς μέρας', () {
      expect(summarizeDay(Dashboard.fromJson(sampleDashboardJson(now)), day).containsKey(K.dayHr), isTrue,
          reason: 'με διαβασμένο ύπνο: όπως πάντα');
      final withError = sampleDashboardJson(now)..['sleep'] = {'error': 'x'};
      final withoutKey = sampleDashboardJson(now)..remove('sleep');
      for (final j in [withError, withoutKey]) {
        final row = summarizeDay(Dashboard.fromJson(j), day);
        for (final key in dayHeartKeys) {
          expect(row.containsKey(key), isFalse, reason: key);
        }
        expect(row.containsKey(K.steps), isTrue, reason: 'τα υπόλοιπα της μέρας γράφονται κανονικά');
      }
    });

    test('οι αποθηκευμένοι παλμοί μέρας μένουν, ακόμα κι αν η ανάγνωση φέρει άλλους', () {
      final err = Dashboard.fromJson(sampleDashboardJson(now)..['sleep'] = {'error': 'x'});
      final h = <String, Map<String, double>>{
        k: {K.dayHr: 74, K.restHr: 61, K.walkHr: 95, K.steps: 1},
      };
      applyRecentRead(h, err, plan: SourcePlan.samsungOnly, sleepFailed: true, rows: {
        k: {K.dayHr: 60.0, K.restHr: 50.0, K.walkHr: 80.0, K.steps: 2.0},
      });
      expect(h[k], {K.dayHr: 74.0, K.restHr: 61.0, K.walkHr: 95.0, K.steps: 2.0});
      // Με διαβασμένο ύπνο οι ίδιες γραμμές γράφονται κανονικά.
      final ok = Dashboard.fromJson(sampleDashboardJson(now));
      applyRecentRead(h, ok, plan: SourcePlan.samsungOnly, rows: {
        k: {K.dayHr: 60.0, K.restHr: 50.0, K.walkHr: 80.0, K.steps: 3.0},
      });
      expect(h[k], {K.dayHr: 60.0, K.restHr: 50.0, K.walkHr: 80.0, K.steps: 3.0});
    });

    test('«πολύ λίγες νύχτες» (6 αποθηκευμένες, 1 στην ανάγνωση): ούτε ο ύπνος ούτε οι παλμοί μέρας αλλάζουν', () {
      final today = dayOf(now);
      final d = Dashboard.fromJson(sampleDashboardJson(now));
      final h = <String, Map<String, double>>{
        for (var i = 3; i < 9; i++) dateKey(_add(today, -i)): {K.sleepMin: 400.0 + i, K.bedtime: 330, K.dayHr: 70.0 + i},
      };
      final x = dateKey(_add(today, -3));
      applyRecentRead(h, d, plan: SourcePlan.samsungOnly, rows: {
        x: {K.sleepMin: 380.0, K.bedtime: 300.0, K.dayHr: 55.0, K.steps: 9.0},
      });
      expect(h[x], {K.sleepMin: 403.0, K.bedtime: 330.0, K.dayHr: 73.0, K.steps: 9.0});
    });
  });

  // -------------------------------------------------------------------------------------------------------------
  group('S3-8: η ώρα της εγγραφής στη δική της ζώνη («off»)', () {
    // 04:50 UTC της 21/11/2026 = 06:50 στην Αθήνα (+120′) = 23:50 της 20/11 στη Νέα Υόρκη (−300′).
    final instant = DateTime.utc(2026, 11, 21, 4, 50).millisecondsSinceEpoch;
    (int, int, int, int, int) f(DateTime t) => (t.year, t.month, t.day, t.hour, t.minute);

    test('wallClock: τα ψηφία της ώρας στη ζώνη της εγγραφής, όποια κι αν είναι η ζώνη του κινητού', () {
      expect(f(wallClock(instant, 120)), (2026, 11, 21, 6, 50));
      expect(f(wallClock(instant, -300)), (2026, 11, 20, 23, 50));
      expect(f(wallClock(instant, 0)), (2026, 11, 21, 4, 50));
      expect(f(wallClock(instant, 330)), (2026, 11, 21, 10, 20), reason: 'ζώνη με μισή ώρα (+5:30)');
      // Χωρίς «off», ή με άκυρο: ακριβώς η τοπική ώρα του κινητού, όπως πριν.
      final local = DateTime.fromMillisecondsSinceEpoch(instant);
      for (final bad in <Object?>[null, 'x', double.nan, double.infinity, 18 * 60 + 1, -(18 * 60 + 1)]) {
        expect(wallClock(instant, bad), local, reason: '$bad');
      }
      // Ίδια ζώνη με το κινητό: το ίδιο αντικείμενο ώρας (καμία αλλαγή στο σπίτι).
      expect(wallClock(instant, local.timeZoneOffset.inMinutes), local);
    });

    test('ζύγιση: η μέρα και η ώρα της μένουν όπως ζυγίστηκες', () {
      Dashboard d(Object? off) => Dashboard.fromJson({
            'readAt': instant,
            'body': [
              {'time': instant, 'weight': 82.4, 'fatPct': 21.3, 'app': inbodyApp, if (off != null) 'off': off},
            ],
          });
      expect(f(d(120).body.single.time), (2026, 11, 21, 6, 50));
      expect(bodyRows(d(120).body).keys.single, '2026-11-21');
      expect(bodyRows(d(120).body).values.single, {K.weight: 82.4, K.fatPct: 21.3, K.inbody: 1.0});
      // Ζύγιση που έγινε 23:50 σε ζώνη −5 ώρες: ανήκει στις 20/11 εκείνου του τόπου.
      expect(f(d(-300).body.single.time), (2026, 11, 20, 23, 50));
      expect(bodyRows(d(-300).body).keys.single, '2026-11-20');
      // Χωρίς «off» (παλιό αποθηκευμένο αντίγραφο): η ζώνη του κινητού, όπως πριν.
      expect(d(null).body.single.time, DateTime.fromMillisecondsSinceEpoch(instant));
    });

    test('νύχτα του ρολογιού: ώρα ύπνου και ξυπνήματος στη ζώνη της εγγραφής', () {
      // Ύπνος 23:30–07:00 σε ζώνη UTC+0 (π.χ. ταξίδι), όπως τον γράφει η Samsung με «off»: 0.
      final start = DateTime.utc(2026, 11, 9, 23, 30).millisecondsSinceEpoch;
      final end = DateTime.utc(2026, 11, 10, 7, 0).millisecondsSinceEpoch;
      Map<String, double> night(Object? off) {
        final d = Dashboard.fromJson({
          'readAt': DateTime.utc(2026, 11, 10, 12).millisecondsSinceEpoch,
          'sleep': [
            {'start': start, 'end': end, 'minutes': 440, if (off != null) 'off': off},
          ],
        });
        final rows = summarizeRange(d, DateTime(2026, 11, 8), DateTime(2026, 11, 12));
        return rows.values.where((r) => r.containsKey(K.bedtime)).single;
      }

      final n = night(0);
      expect((n[K.bedtime], n[K.wake]), (330, 780), reason: '23:30 και 07:00 εκεί που κοιμήθηκες');
      expect(clockFromSix(n[K.bedtime]!), '23:30');
      expect(clockFromSix(n[K.wake]!), '07:00');
      // Χωρίς «off»: η ζώνη του κινητού, όπως πριν.
      final plain = night(null);
      expect(plain[K.bedtime], minutesFromSix(DateTime.fromMillisecondsSinceEpoch(start)).toDouble());
      expect(plain[K.wake], minutesFromSix(DateTime.fromMillisecondsSinceEpoch(end)).toDouble());
    });

    test('η γέφυρα στέλνει το «off» για ύπνο και ζυγίσεις (πηγαίος κώδικας Kotlin)', () {
      final reader = File('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/DashboardReader.kt').readAsStringSync();
      expect('DataRules.offsetMinutes(p.zoneOffset?.totalSeconds)'.allMatches(reader).length, 2);
      expect(reader, contains('o.put("off", off)'));
    });
  });

  // -------------------------------------------------------------------------------------------------------------
  group('S3-5 / S1-10: το αντίγραφο του παρασκηνίου', () {
    final at = DateTime(2026, 12, 14, 8, 20); // Δευτέρα, 28 μέρες μετά τις 16/11: μέρα ελέγχου με εκτίμηση

    test('Dashboard.background: μόνο το αρχείο του RefreshWorker· μένει και μετά το «restrict»', () {
      final j = sampleDashboardJson(at);
      expect(Dashboard.fromJson(j).background, isFalse);
      expect(parseDashboardSync(jsonEncode({...j, 'background': true})).data!.background, isTrue);
      expect(parseDashboardSync(jsonEncode({...j, 'background': 'ναι'})).data!.background, isFalse);
      final plan = SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 12, 1));
      expect(Dashboard.fromJson({...j, 'background': true}).restrict(plan).background, isTrue);
    });

    test('ο έλεγχος θερμίδων περιμένει την πλήρη ανάγνωση: καμία κάρτα από το αντίγραφο του παρασκηνίου', () {
      final food = checkinFood(at);
      final body = bodyJson(simWeights(at));
      HealthStore store({required bool background}) => HealthStore()
        ..data = Dashboard.fromJson({...sampleDashboardJson(at), 'body': body, if (background) 'background': true})
        ..setGoals(checkinGoals());
      expect(CheckInSlot.pendingFor(store(background: false), food, at)?.kind, CheckKind.proposal);
      expect(CheckInSlot.pendingFor(store(background: true), food, at), isNull);
    });

    test('ο RefreshWorker διαβάζει όλες τις ζυγίσεις (πηγαίος κώδικας Kotlin)', () {
      final worker = File('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/RefreshWorker.kt').readAsStringSync();
      expect(worker, contains('SleepPolicy.reader(applicationContext, store, heartDays = 7).read(names)'));
      expect(worker, isNot(contains('bodyDays = 30')));
      expect(worker, contains('.put("background", true)'));
    });
  });

  test('S3-4: «Τι φτάνει»: το Energy Score της σημερινής μέρας μέσα στο φίλτρο ημερομηνίας (τέλος εκτός)', () {
    final bridge = File('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/SamsungHealthBridge.kt').readAsStringSync();
    expect(bridge, contains('LocalDateFilter.of(from.toLocalDate(), to.toLocalDate().plusDays(1))'));
    expect(bridge, isNot(contains('LocalDateFilter.of(from.toLocalDate(), to.toLocalDate())')));
  });

  // -------------------------------------------------------------------------------------------------------------
  group('Ρυθμίσεις στο κινητό (S3-2 = S9-1, S3-9 = S9-5 = S11-5)', () {
    final real = DateTime.now();
    final now = DateTime(real.year, real.month, real.day, 15);
    const waist = WaistEntry('2026-11-20', [101.5, 101.0]);
    const waistJson = {
      'd': '2026-11-20',
      'v': [101.5, 101.0],
    };

    HealthStore app(_Phone a, {String? planFile}) {
      a.install();
      return HealthStore()
        ..planFile = MemoryPlanFile(planFile)
        ..ouraNightsFile = MemoryNightsFile()
        ..ouraClock = (() => now)
        ..prefsRetryDelay = const Duration(milliseconds: 10)
        ..ouraLink = OuraLink(
          vault: MemoryVault(),
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

    Future<HealthStore> boot(_Phone a, {String? planFile}) async {
      final s = app(a, planFile: planFile);
      await s.loadPrefs();
      await s.start();
      await settle(s);
      return s;
    }

    Future<void> tick([int ms = 40]) => Future<void>.delayed(Duration(milliseconds: ms));

    test('χαλασμένο prefs.json: καμία προεπιλογή από πάνω του, τίποτα δεν γράφεται ως τη ρητή επιλογή', () async {
      final a = _Phone(now)
        ..load = '{"ok":false,"kind":"corrupt"}'
        ..afterSetAside = '{"reportName":"Δοκιμή Όνομα"}';
      final s = await boot(a);
      expect((s.prefsCorrupt, s.prefsLoaded), (true, false));
      expect(a.count('loadPrefs'), greaterThanOrEqualTo(2), reason: 'ξαναδοκιμάζεται (άνοιγμα, εκκίνηση, ανανέωση)');
      expect(a.count('savePrefs'), 0, reason: 'πριν: στη δεύτερη αποτυχία οι προεπιλογές έγραφαν πάνω στο αρχείο');
      expect(a.count('prefsSetAside'), 0, reason: 'το αρχείο δεν μετακινείται χωρίς τον χρήστη');
      expect(a.saveDaysCalls, 0, reason: 'χωρίς ρυθμίσεις δεν γράφεται ούτε ιστορικό');
      expect(s.data, isNotNull, reason: 'τα δεδομένα της Samsung φαίνονται κανονικά');
      // Μια αλλαγή όσο οι ρυθμίσεις δεν διαβάζονται: φαίνεται ότι δεν γράφτηκε, και περιμένει.
      s.saveWaist(waist);
      await tick();
      expect(s.prefsSaveError, isTrue);
      expect(a.count('savePrefs'), 0);
      // «Ξεκίνα με νέες ρυθμίσεις»: πρώτα το χαλασμένο αρχείο στην άκρη, μετά οι εγγραφές.
      expect(await s.startFreshPrefs(), isTrue);
      expect(a.count('prefsSetAside'), 1);
      expect(a.calls.indexOf('prefsSetAside'), lessThan(a.calls.indexOf('savePrefs')));
      expect((s.prefsCorrupt, s.prefsLoaded, s.prefsSaveError), (false, true, false));
      expect(s.prefs.reportName, 'Δοκιμή Όνομα', reason: 'το όνομα της αναφοράς είναι σε άλλο αρχείο: μένει');
      expect(a.saved.last['reportName'], 'Δοκιμή Όνομα', reason: 'ποτέ «reportName: null» από προεπιλογές');
      expect(a.saved.last['waist'], [waistJson], reason: 'η αλλαγή που περίμενε γράφτηκε');
      await s.refresh();
      await settle(s);
      expect(a.saveDaysCalls, greaterThan(0), reason: 'με διαβασμένες ρυθμίσεις το ιστορικό γράφεται ξανά');
      s.dispose();
    });

    test('κείμενο που δεν διαβάζεται, «[]» ή «null»: χαλασμένο, όχι «καμία ρύθμιση»', () async {
      for (final text in ['{"goals":{"v":1,', '', '[]', 'null']) {
        final a = _Phone(now)..load = text;
        final s = await boot(a);
        expect((s.prefsCorrupt, s.prefsLoaded), (true, false), reason: '«$text»');
        expect(a.count('savePrefs'), 0, reason: '«$text»');
        expect(a.load, text, reason: 'το αρχείο μένει όπως ήταν');
        s.dispose();
      }
    });

    test('αντικείμενο JSON με πεδία λάθος είδους: διαβάζεται· μόνο εκείνα παίρνουν την προεπιλογή τους', () async {
      // Πριν: σφάλμα για όλο το αρχείο → «χαλασμένο», ενώ η Kotlin το διαβάζει κανονικά και δεν το βάζει στην άκρη: το
      // κουμπί «Ξεκίνα με νέες ρυθμίσεις» δεν θα πετύχαινε ποτέ. Τώρα στόχοι και μέση μένουν.
      final j = <String, dynamic>{
        'goals': checkinGoals().toJson(),
        'waist': [waistJson],
        'layout': 'x',
        'cards': 7,
        'historyVersion': '4',
        'ouraSynced': true,
        'sourcesAt': 'χθες',
        'ouraRules': <Object>[],
      };
      final p = Prefs.fromJson(j);
      expect(p.goals, checkinGoals().toJson());
      expect((p.historyVersion, p.ouraSynced, p.planAt, p.ouraRules), (1, null, null, 0));
      final a = _Phone(now)..load = jsonEncode(j);
      final s = await boot(a);
      expect((s.prefsCorrupt, s.prefsLoaded), (false, true));
      expect(s.goals!.since, '2026-11-16');
      expect(s.waist.single.day, '2026-11-20');
      expect(a.count('prefsSetAside'), 0);
      s.dispose();
    });

    test('το αρχείο διαβάζεται αργότερα (το σφάλμα ήταν προσωρινό): οι ρυθμίσεις έρχονται, χωρίς άλλη ενέργεια', () async {
      final a = _Phone(now)..load = '{"ok":false,"kind":"corrupt"}';
      final s = await boot(a);
      expect(s.prefsCorrupt, isTrue);
      a.load = jsonEncode({'goals': checkinGoals().toJson(), 'historyVersion': historyRulesVersion});
      await s.refresh();
      await settle(s);
      expect((s.prefsCorrupt, s.prefsLoaded), (false, true));
      expect(s.goals!.since, '2026-11-16');
      expect(a.count('prefsSetAside'), 0);
      expect(a.saved.last['goals'], checkinGoals().toJson(), reason: 'οι στόχοι του αρχείου μένουν στο αρχείο');
      s.dispose();
    });

    test('χωρίς πλευρά Android (δοκιμές, στιγμιότυπα): όπως πάντα, προεπιλογές στη δεύτερη φορά, κανένα μήνυμα', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('ygeia/samsung'), null);
      final s = HealthStore();
      await s.loadPrefs();
      expect(s.prefsLoaded, isFalse);
      await s.loadPrefs();
      expect((s.prefsLoaded, s.prefsCorrupt), (true, false));
      s.saveWaist(waist);
      await tick();
      expect(s.prefsSaveError, isFalse);
      expect(s.waist.single.day, '2026-11-20');
    });

    test('αποτυχία εγγραφής: μία επανάληψη, μετά φαίνεται· η επόμενη επιτυχημένη εγγραφή τα γράφει όλα', () async {
      final a = _Phone(now)..load = jsonEncode({'historyVersion': historyRulesVersion});
      final s = await boot(a);
      var notified = 0;
      s.addListener(() => notified++);
      final before = a.count('savePrefs');
      a.saveOk = false;
      s.saveWaist(waist);
      await tick(150);
      expect(a.count('savePrefs') - before, 2, reason: 'η εγγραφή και μία επανάληψη');
      expect(s.prefsSaveError, isTrue);
      expect(notified, greaterThanOrEqualTo(2), reason: 'η οθόνη μαθαίνει και την αλλαγή και την αποτυχία');
      expect(s.waist.single.day, '2026-11-20', reason: 'στη μνήμη υπάρχει');
      expect(a.load.contains('2026-11-20'), isFalse, reason: 'στο κινητό όχι');
      // «Δοκίμασε ξανά» με τον χώρο ακόμα γεμάτο.
      expect(await s.retrySavePrefs(), isFalse);
      expect(s.prefsSaveError, isTrue);
      // Ο χώρος ελευθερώθηκε: οποιαδήποτε επόμενη αλλαγή γράφει όλες τις ρυθμίσεις της μνήμης.
      a.saveOk = true;
      s.setCard('steps', true);
      await tick();
      expect(s.prefsSaveError, isFalse);
      expect(a.saved.last['waist'], [waistJson]);
      s.dispose();
    });

    test('«Δοκίμασε ξανά» γράφει την αλλαγή που απέτυχε', () async {
      final a = _Phone(now)..load = jsonEncode({'historyVersion': historyRulesVersion});
      final s = await boot(a);
      a.saveOk = false;
      s.setGoals(checkinGoals());
      await tick(150);
      expect(s.prefsSaveError, isTrue);
      a.saveOk = true;
      expect(await s.retrySavePrefs(), isTrue);
      expect(s.prefsSaveError, isFalse);
      expect(a.saved.last['goals'], checkinGoals().toJson());
      s.dispose();
    });

    test('ρυθμίσεις που δεν διαβάστηκαν τώρα («read»): η αλλαγή περιμένει, φαίνεται, και γράφεται πάνω στις αποθηκευμένες', () async {
      final a = _Phone(now)..load = '{"ok":false,"kind":"read"}';
      final s = await boot(a);
      expect((s.prefsLoaded, s.prefsCorrupt, s.prefsSaveError), (false, false, false));
      s.saveWaist(waist);
      await tick();
      expect(s.prefsSaveError, isTrue);
      expect(await s.startFreshPrefs(), isFalse, reason: 'μόνο για χαλασμένο αρχείο· ένα σφάλμα ανάγνωσης δεν το μετακινεί');
      expect(a.count('prefsSetAside'), 0);
      expect(await s.retrySavePrefs(), isFalse, reason: 'ακόμα δεν διαβάζονται');
      expect(a.count('savePrefs'), 0);
      a.load = jsonEncode({'goals': checkinGoals().toJson(), 'historyVersion': historyRulesVersion});
      expect(await s.retrySavePrefs(), isTrue);
      expect(s.prefsSaveError, isFalse);
      expect(a.saved.last['goals'], checkinGoals().toJson(), reason: 'οι αποθηκευμένοι στόχοι δεν χάθηκαν');
      expect(a.saved.last['waist'], [waistJson], reason: 'και η αλλαγή που περίμενε μπήκε πάνω τους');
      s.dispose();
    });

    testWidgets('η κάρτα της Σήμερα: μόνο όταν χρειάζεται, με το σωστό κείμενο', (t) async {
      final s = HealthStore();
      expect(PrefsNoticeCard.shows(s), isFalse);
      Future<void> pump() => t.pumpWidget(MaterialApp(
            theme: buildTheme(Brightness.light),
            home: Scaffold(body: SingleChildScrollView(child: PrefsNoticeCard(store: s))),
          ));
      s.prefsCorrupt = true;
      expect(PrefsNoticeCard.shows(s), isTrue);
      await pump();
      expect(find.byKey(const ValueKey('today-prefs-corrupt')), findsOneWidget);
      expect(find.text('Οι ρυθμίσεις δεν διαβάζονται'), findsOneWidget);
      expect(find.text('Ξεκίνα με νέες ρυθμίσεις'), findsOneWidget);
      expect(find.textContaining('Δεν γράφτηκε τίποτα από πάνω του'), findsOneWidget);
      expect(t.takeException(), isNull);
      s
        ..prefsCorrupt = false
        ..prefsSaveError = true;
      await pump();
      expect(find.byKey(const ValueKey('today-prefs-unsaved')), findsOneWidget);
      expect(find.text('Η τελευταία αλλαγή δεν αποθηκεύτηκε'), findsOneWidget);
      expect(find.text('Δοκίμασε ξανά'), findsOneWidget);
      expect(find.textContaining('Οι ρυθμίσεις δεν διαβάστηκαν ακόμα'), findsOneWidget, reason: 'οι ρυθμίσεις εδώ δεν έχουν διαβαστεί');
      expect(t.takeException(), isNull);
    });

    // -----------------------------------------------------------------------------------------------------------
    group('Επαναφορά πηγών ύπνου από αντίγραφο (S9-2, S9-7)', () {
      final today = dayOf(now);
      String file(SourcePlan p, int at) => encodePlanFile(p, now, at: at);
      // [synced]: το Oura είχε διαβαστεί ως χθες (μόνο σε κινητό που έχει ήδη αρχείο σχεδίου πηγών).
      String okPrefs({bool synced = false}) => jsonEncode({
            'historyVersion': historyRulesVersion,
            if (synced) 'ouraSyncedTo': dateKey(_add(today, -1)),
          });

      test('S9-7: νέα σύνδεση Oura στο κινητό, μετά επαναφορά: το παρελθόν από το αντίγραφο, χωρίς νέα αλλαγή πηγής', () async {
        final a = _Phone(now)..load = okPrefs(synced: true);
        final s = await boot(a, planFile: file(SourcePlan([SourceEra(Source.oura, _add(today, 1))]), 2000));
        expect(s.plan.nightSource(_add(today, -60)), Source.watch, reason: 'πριν από την επαναφορά το παρελθόν είναι «ρολόι»');
        final backup = SourcePlan([SourceEra(Source.oura, _add(today, -105))]);
        expect(await s.restoreSources((plan: file(backup, 1000), log: null)), isTrue,
            reason: 'πριν: «οι πηγές του κινητού είναι νεότερες» και το αντίγραφο απορριπτόταν');
        expect(s.plan.nightSource(_add(today, -106)), Source.watch);
        expect(s.plan.nightSource(_add(today, -105)), Source.oura);
        expect(s.plan.nightSource(_add(today, -60)), Source.oura);
        expect(s.plan.nightSource(_add(today, 1)), Source.oura);
        expect(s.plan.changeDates(K.sleepMin), [_add(today, -105)], reason: 'το ίδιο δαχτυλίδι συνεχίζει: μία μόνο αλλαγή πηγής');
        final written = jsonDecode((s.planFile as MemoryPlanFile).content!) as Map;
        expect(written['at'], 2000, reason: 'η ώρα του σχεδίου του κινητού, που είναι το νεότερο');
        expect(decodePlanFile((s.planFile as MemoryPlanFile).content), backup);
        // S9-2: το Oura ξαναδιαβάζεται από την αρχή του, και πριν από τις 90 μέρες.
        expect(a.saved.last.containsKey('ouraSyncedTo'), isFalse);
        expect(a.saved.last['ouraRefetchTo'], dateKey(_add(today, -91)));
        final older = s.ouraOlderRange()!;
        expect((older.from, older.to, older.next), (_add(today, -105), _add(today, -91), null));
        s.dispose();
      });

      test('S9-7: το αντίγραφο είχε γυρίσει στο ρολόι· το κινητό έχει εποχή μέσα στο παρελθόν του αντιγράφου', () async {
        final backup = SourcePlan([SourceEra(Source.oura, _add(today, -105)), SourceEra(Source.watch, _add(today, -50))]);
        final a = _Phone(now)..load = okPrefs();
        final s = await boot(a, planFile: file(SourcePlan([SourceEra(Source.oura, _add(today, 1))]), 2000));
        expect(await s.restoreSources((plan: file(backup, 1000), log: null)), isTrue);
        expect(s.plan.nightSource(_add(today, -60)), Source.oura);
        expect(s.plan.nightSource(_add(today, -30)), Source.watch);
        expect(s.plan.nightSource(_add(today, 1)), Source.oura);
        expect(s.plan.eras.length, 3);
        s.dispose();
        // Κινητό με εποχή ΜΕΣΑ στο παρελθόν του αντιγράφου: ξέρει καλύτερα, μένει όπως είναι.
        final phone = SourcePlan([SourceEra(Source.oura, _add(today, -60))]);
        final b = _Phone(now)..load = okPrefs(synced: true);
        final s2 = await boot(b, planFile: file(phone, 2000));
        expect(await s2.restoreSources((plan: file(backup, 1000), log: null)), isFalse);
        expect(s2.plan, phone);
        expect(decodePlanFile((s2.planFile as MemoryPlanFile).content), phone);
        expect(b.load.contains('ouraRefetchTo'), isFalse);
        expect(b.load.contains('ouraSyncedTo'), isTrue, reason: 'τίποτα δεν άλλαξε: καμία επανανάγνωση του Oura');
        s2.dispose();
      });

      test('S9-2: νέο κινητό (ποτέ σχέδιο): μπαίνει το σχέδιο του αντιγράφου και το Oura ξαναζητείται από την αρχή του', () async {
        final a = _Phone(now)..load = okPrefs();
        final s = await boot(a);
        final backup = SourcePlan([SourceEra(Source.oura, _add(today, -200))]);
        // Σαν να είχε διαβαστεί κάτι από το Oura πριν από την επαναφορά: το «ως πότε» πρέπει να μηδενιστεί.
        s.ouraSyncedTo = dateKey(_add(today, -1));
        expect(await s.restoreSources((plan: file(backup, 1000), log: null)), isTrue);
        expect(s.plan, backup);
        expect((jsonDecode((s.planFile as MemoryPlanFile).content!) as Map)['at'], 1000);
        expect(a.saved.last.containsKey('ouraSyncedTo'), isFalse, reason: 'ξανά οι 90 μέρες');
        expect(a.saved.last['ouraRefetchTo'], dateKey(_add(today, -91)), reason: 'και πιο πίσω, ανά 90 μέρες');
        final first = s.ouraOlderRange()!;
        expect((first.from, first.to, first.next), (_add(today, -180), _add(today, -91), _add(today, -181)));
        s.ouraRefetchTo = dateKey(first.next!);
        final second = s.ouraOlderRange()!;
        expect((second.from, second.to, second.next), (_add(today, -200), _add(today, -181), null));
        s.dispose();
      });

      test('σχέδιο χωρίς Oura από το αντίγραφο: καμία επανανάγνωση του Oura', () async {
        final a = _Phone(now)..load = okPrefs();
        final s = await boot(a);
        final backup = SourcePlan([SourceEra(Source.none, _add(today, -20))]);
        s.ouraSyncedTo = dateKey(_add(today, -1));
        expect(await s.restoreSources((plan: file(backup, 1000), log: null)), isTrue);
        expect(a.saved.last['ouraSyncedTo'], dateKey(_add(today, -1)));
        expect(a.saved.last.containsKey('ouraRefetchTo'), isFalse);
        s.dispose();
      });
    });
  });

  // -------------------------------------------------------------------------------------------------------------
  group('S9-7: planWithPast (το παρελθόν από το αντίγραφο, το παρόν από το κινητό)', () {
    DateTime d(int y, int m, int day) => DateTime(y, m, day);
    final phone = SourcePlan([SourceEra(Source.oura, d(2027, 3, 2))]);

    test('ίδια πηγή: οι εποχές ενώνονται σε μία (καμία «αλλαγή πηγής» στη μέρα της νέας σύνδεσης)', () {
      final p = planWithPast(phone, SourcePlan([SourceEra(Source.oura, d(2026, 11, 16))]))!;
      expect(p.eras, [SourceEra(Source.oura, d(2026, 11, 16))]);
      expect(p.nightSource(d(2026, 12, 10)), Source.oura);
      expect(p.nightSource(d(2027, 3, 2)), Source.oura);
      expect(p.nightSource(d(2026, 11, 15)), Source.watch);
    });

    test('το αντίγραφο τελείωνε με ρολόι ή «καμία»: η εποχή του κινητού προστίθεται', () {
      final p = planWithPast(phone, SourcePlan([SourceEra(Source.oura, d(2026, 11, 16)), SourceEra(Source.watch, d(2027, 1, 10))]))!;
      expect(p.eras, [SourceEra(Source.oura, d(2026, 11, 16)), SourceEra(Source.watch, d(2027, 1, 10)), SourceEra(Source.oura, d(2027, 3, 2))]);
      expect((p.nightSource(d(2026, 12, 10)), p.nightSource(d(2027, 2, 1)), p.nightSource(d(2027, 3, 2))),
          (Source.oura, Source.watch, Source.oura));
      final q = planWithPast(SourcePlan([SourceEra(Source.none, d(2027, 3, 2))]), SourcePlan([SourceEra(Source.oura, d(2026, 11, 16))]))!;
      expect((q.nightSource(d(2027, 3, 1)), q.nightSource(d(2027, 3, 2))), (Source.oura, Source.none));
    });

    test('δεν ενώνονται: εποχή του κινητού μέσα στο παρελθόν του αντιγράφου, ίδια μέρα, ή κάποιο χωρίς εποχές', () {
      final backup = SourcePlan([SourceEra(Source.oura, d(2026, 11, 16)), SourceEra(Source.watch, d(2027, 3, 5))]);
      expect(planWithPast(phone, backup), isNull, reason: 'το κινητό (2/3) αρχίζει πριν από την τελευταία εποχή του αντιγράφου (5/3)');
      expect(planWithPast(phone, SourcePlan([SourceEra(Source.watch, d(2027, 3, 2))])), isNull, reason: 'ίδια μέρα');
      expect(planWithPast(SourcePlan.samsungOnly, backup), isNull);
      expect(planWithPast(phone, SourcePlan.samsungOnly), isNull);
    });
  });

  // -------------------------------------------------------------------------------------------------------------
  group('S9-11: ζώνη περπατήματος και στόχοι στην επαναφορά', () {
    test('οι μετρήσεις που λείπουν από το κινητό έρχονται από το αντίγραφο· οι επιλογές του κινητού μένουν', () {
      final mine = <String, dynamic>{
        'zone': {
          'up': true,
          'down': false,
          'talk': [
            ['w-9', 'sing'],
          ],
        },
      };
      final backup = <String, dynamic>{
        'zone': {
          'rest': 58,
          'max': 176,
          'up': true,
          'down': true,
          'talk': [
            ['w-1', 'talk'],
          ],
        },
      };
      expect(mergePrefsForRestore(mine, backup)['zone'], {
        'rest': 58,
        'max': 176,
        'up': true,
        'down': false,
        'talk': [
          ['w-1', 'talk'],
          ['w-9', 'sing'],
        ],
      });
      expect(restoreNotes(mine, backup), ['Οι μετρημένοι παλμοί της ζώνης περπατήματος συμπληρώθηκαν από το αντίγραφο.']);
    });

    test('ό,τι έχει ήδη το κινητό μένει· η ζώνη γραμμένη με το χέρι δεν μπαίνει ποτέ από αντίγραφο· και τα δύο λέγονται', () {
      final mine = <String, dynamic>{
        'zone': {
          'rest': 62,
          'up': true,
          'down': false,
          'talk': [
            ['w-1', 'no'],
          ],
        },
        'goals': {'k': 2100, 'since': '2026-11-16'},
      };
      final backup = <String, dynamic>{
        'zone': {
          'rest': 58,
          'lo': 100,
          'hi': 125,
          'up': false,
          'down': true,
          'talk': [
            ['w-1', 'talk'],
          ],
        },
        'goals': {'k': 2250, 'since': '2026-10-01'},
      };
      final m = mergePrefsForRestore(mine, backup);
      expect(m['zone'], mine['zone'], reason: 'δικοί σου παλμοί ηρεμίας, δικές σου δονήσεις, δική σου απάντηση· όχι παλιά ζώνη');
      expect(m['goals'], mine['goals'], reason: 'Συμβούλιο 3, Α1: οι στόχοι του κινητού μένουν');
      expect(restoreNotes(mine, backup), [
        'Οι στόχοι διατροφής του κινητού έμειναν· του αντιγράφου δεν μπήκαν.',
        'Στη ζώνη περπατήματος έμειναν οι ρυθμίσεις του κινητού· του αντιγράφου δεν μπήκαν.',
      ]);
    });

    test('τίποτα να ειπωθεί: ίδιοι στόχοι, κινητό χωρίς στόχους ή ζώνη, αντίγραφο χωρίς ζώνη', () {
      const goals = {'k': 2100, 'since': '2026-11-16'};
      expect(restoreNotes({'goals': goals}, {'goals': goals}), isEmpty);
      expect(restoreNotes(const {}, {'goals': goals, 'zone': {'rest': 58}}), isEmpty, reason: 'μπαίνουν του αντιγράφου, όπως πάντα');
      expect(restoreNotes({'goals': goals, 'zone': {'up': true, 'down': false}}, const {}), isEmpty);
      expect(restoreNotes({'zone': {'rest': 58, 'up': true, 'down': false}}, {'zone': {'rest': 58.0, 'up': false, 'down': true}}), isEmpty,
          reason: 'ίδιοι παλμοί ηρεμίας· οι δονήσεις είναι επιλογή του κινητού');
      expect(mergePrefsForRestore({'zone': {'up': true, 'down': false}}, {'zone': <Object>[]})['zone'], {'up': true, 'down': false});
    });
  });

  // -------------------------------------------------------------------------------------------------------------
  group('S12: ανάγνωση δεδομένων και κανόνες του ιστορικού', () {
    test('Τ5.1: ημερολογιακές μέρες πάνω από την αλλαγή ώρας (28/3/2027 και 25/10/2026)', () {
      // Με TZ=Europe/Athens (όπως το CI) οι δύο πρώτες γραμμές περνούν πάνω από μέρα 23 ωρών. Σε ζώνη χωρίς αλλαγή ώρας η
      // δοκιμή δεν θα έλεγχε τίποτα: τότε αποτυγχάνει εδώ, με καθαρό μήνυμα (S12 Τ5).
      expect(DateTime(2027, 3, 29).timeZoneOffset - DateTime(2027, 3, 27).timeZoneOffset, const Duration(hours: 1),
          reason: 'οι δοκιμές τρέχουν με TZ=Europe/Athens');
      expect(daysBetween(DateTime(2027, 3, 27), DateTime(2027, 3, 29)), 2);
      expect(daysBetween(DateTime(2027, 3, 8), DateTime(2027, 3, 29)), 21);
      expect(daysBetween(DateTime(2027, 3, 27, 23, 30), DateTime(2027, 3, 28, 4, 30)), 1);
      expect(daysBetween(DateTime(2026, 10, 24), DateTime(2026, 10, 26)), 2);
      expect(daysBetween(DateTime(2026, 10, 25, 23, 59), DateTime(2026, 10, 26, 0, 1)), 1);
      expect(daysBetween(DateTime(2027, 3, 29), DateTime(2027, 3, 27)), -2);
      // Κλειδιά ημέρας: πάνω από την αλλαγή ώρας η επόμενη μέρα είναι πάντα η επόμενη ημερομηνία.
      expect(dateKey(_add(DateTime(2027, 3, 27), 1)), '2027-03-28');
      expect(dateKey(_add(DateTime(2027, 3, 28), 1)), '2027-03-29');
      expect(dateKey(_add(DateTime(2026, 10, 25), 1)), '2026-10-26');
      expect(parseDateKey('2027-03-28'), DateTime(2027, 3, 28));
    });

    test('ζυγαριά InBody: ίδια παραδείγματα με το Kotlin (R1F3Test.scaleAppSameExamplesAsDart)', () {
      for (final app in ['com.inbody2014.inbody', 'kr.co.InBody.x', 'COM.INBODY.APP']) {
        expect(isScaleApp(app), isTrue, reason: app);
      }
      for (final app in ['com.sec.android.app.shealth', 'com.samsung.android.wear.shealth', 'com.google.android.apps.healthdata', '']) {
        expect(isScaleApp(app), isFalse, reason: app);
      }
      // Μόνο οι ζυγίσεις της InBody μπαίνουν στη σειρά· οι άλλες μετριούνται ως «αγνοήθηκαν».
      final t = DateTime(2026, 11, 10, 7, 10).millisecondsSinceEpoch;
      final d = Dashboard.fromJson({
        'readAt': t,
        'body': [
          {'time': t, 'weight': 82.4, 'app': inbodyApp},
          {'time': t + 60000, 'weight': 85.0, 'app': 'com.sec.android.app.shealth'},
        ],
      });
      expect(d.body.single.weight, 82.4);
      expect(d.bodyOther, 1);
    });

    test('όρια λογικών τιμών: παλμοί 25–250, οξυγόνο 50–100, θερμοκρασία 20–42 (τα άκρα μετρούν)', () {
      final t0 = DateTime(2026, 11, 10, 3).millisecondsSinceEpoch;
      List<num> s(int i, num v) => [t0 + i * 60000, t0 + (i + 1) * 60000, v, v, v];
      final d = Dashboard.fromJson({
        'readAt': t0 + 3600000,
        'heart': [s(0, 24.9), s(1, 25), s(2, 250), s(3, 250.1)],
        'spo2': [s(0, 49.9), s(1, 50), s(2, 100), s(3, 100.1)],
        'skinTemp': [s(0, 19.9), s(1, 20), s(2, 42), s(3, 42.1)],
      });
      expect([for (final x in d.heart) x.avg], [25, 250]);
      expect([for (final x in d.spo2) x.avg], [50, 100]);
      expect([for (final x in d.skin) x.avg], [20, 42]);
      // Ζύγιση έξω από τα όρια = δεν μετρήθηκε, όχι «0 kg».
      final b = Dashboard.fromJson({
        'readAt': t0,
        'body': [
          {'time': t0, 'weight': 19.9, 'fatPct': 1.9, 'bmr': 499, 'app': inbodyApp},
          {'time': t0 + 60000, 'weight': 20, 'fatPct': 2, 'bmr': 500, 'app': inbodyApp},
          {'time': t0 + 120000, 'weight': 350, 'fatPct': 75, 'bmr': 5000, 'app': inbodyApp},
          {'time': t0 + 180000, 'weight': 350.1, 'fatPct': 75.1, 'bmr': 5001, 'app': inbodyApp},
        ],
      });
      expect([for (final x in b.body) (x.weight, x.fatPct, x.bmr)], [(null, null, null), (20.0, 2.0, 500), (350.0, 75.0, 5000), (null, null, null)]);
      // Χρόνος πριν από το 2000 (π.χ. «0»): η εγγραφή αγνοείται.
      expect(Dashboard.fromJson({'readAt': t0, 'heart': [[0, 60000, 60, 60, 60]]}).heart, isEmpty);
    });

    test('mergeHistory: όριο «sleepFrom», τιμές που κρατιούνται, και τι θεωρείται αλλαγή', () {
      final h = <String, Map<String, double>>{
        '2026-10-10': {K.sleepMin: 400, K.sleepScore: 70, K.steps: 5000},
        '2026-10-11': {K.sleepMin: 410, K.skinTemp: 34.2, K.steps: 6000},
        '2026-10-12': {K.steps: 7000},
      };
      final changed = mergeHistory(
        h,
        {
          '2026-10-10': {K.sleepMin: 380, K.steps: 5100},
          '2026-10-11': {K.sleepMin: 390, K.deepPct: 15, K.skinTemp: 35.0, K.steps: 6100},
          '2026-10-12': {K.steps: 7000},
        },
        sleepFrom: DateTime(2026, 10, 11),
        keepKeys: {K.skinTemp},
      );
      expect(h['2026-10-10'], {K.sleepMin: 400.0, K.sleepScore: 70.0, K.steps: 5100.0}, reason: 'πριν από το όριο: ο ύπνος μένει');
      expect(h['2026-10-11'], {K.sleepMin: 390.0, K.deepPct: 15.0, K.skinTemp: 34.2, K.steps: 6100.0},
          reason: 'από το όριο: ο ύπνος αντικαθίσταται· ό,τι κρατιέται μένει');
      expect(changed, {'2026-10-10', '2026-10-11'}, reason: 'η 12/10 δεν άλλαξε: δεν ξαναγράφεται στο κινητό');
    });

    test('ώρες ύπνου ως λεπτά μετά τις 18:00', () {
      expect(minutesFromSix(DateTime(2026, 11, 9, 18, 0)), 0);
      expect(minutesFromSix(DateTime(2026, 11, 9, 23, 30)), 330);
      expect(minutesFromSix(DateTime(2026, 11, 10, 0, 0)), 360);
      expect(minutesFromSix(DateTime(2026, 11, 10, 7, 0)), 780);
      expect(minutesFromSix(DateTime(2026, 11, 10, 17, 59)), 1439);
      expect(clockFromSix(330), '23:30');
      expect(clockFromSix(360), '00:00');
      expect(clockFromSix(1439), '17:59');
    });
  });
}
