// Έλεγχος 4/11, κομμάτι A (ακρίβεια δεδομένων): κάθε διόρθωση με έλεγχο που αποτυγχάνει χωρίς αυτήν.
// A1 ζυγίσεις σε παλιές μέρες δεν σβήνουν το οξυγόνο · A2 μόνο InBody, μία ολόκληρη ζύγιση τη μέρα ·
// A4 οξυγόνο μέσα στις ώρες ύπνου του Oura, με στάθμιση διάρκειας · A12 παλμοί που δεν διαβάστηκαν ·
// A15 τιμές έξω από τα λογικά όρια.
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/oura/oura_model.dart';
import 'package:ygeia_forma/pages/compare_page.dart';
import 'package:ygeia_forma/sources.dart';

import 'sample_data.dart';

int ms(DateTime t) => t.millisecondsSinceEpoch;
DateTime add(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

void main() {
  final now = DateTime(2026, 12, 20, 15);
  final today = DateTime(2026, 12, 20);

  Map<String, dynamic> withBody(List<Map<String, dynamic>> body) => {...sampleDashboardJson(now), 'body': body};

  group('A1: ζύγιση σε παλιά μέρα του Oura', () {
    test('Το οξυγόνο και οι τιμές του Oura της μέρας μένουν· μπαίνει μόνο η ζύγιση', () {
      final day = add(today, -45);
      final plan = SourcePlan.samsungOnly.withEra(Source.oura, add(today, -60));
      final d = Dashboard.fromJson(withBody([
        {'time': ms(day.add(const Duration(hours: 7))), 'weight': 82.0, 'fatPct': 24.0, 'smm': 35.0, 'app': inbodyApp},
      ]));
      final h = <String, Map<String, double>>{
        dateKey(day): {K.spo2Avg: 95.1, K.spo2Min: 88, K.spo2Low: 3, 'o.sleepMin': 420, K.steps: 8000},
      };
      final changed = applyRecentRead(h, d, plan: plan);
      expect(h[dateKey(day)], {
        K.spo2Avg: 95.1,
        K.spo2Min: 88,
        K.spo2Low: 3,
        'o.sleepMin': 420,
        K.steps: 8000,
        K.weight: 82.0,
        K.fatPct: 24.0,
        K.smm: 35.0,
      });
      expect(changed, contains(dateKey(day)));
    });

    test('mergeBody: αγγίζει μόνο τις τιμές ζύγισης', () {
      final h = <String, Map<String, double>>{
        '2026-11-10': {K.spo2Avg: 95, K.weight: 83, K.fatPct: 25, 'o.hrv': 40},
      };
      expect(mergeBody(h, {'2026-11-10': {K.weight: 82}}), {'2026-11-10'});
      expect(h['2026-11-10'], {K.spo2Avg: 95, 'o.hrv': 40, K.weight: 82},
          reason: 'το λίπος της παλιάς ζύγισης δεν μένει δίπλα στο βάρος της νέας');
      expect(mergeBody(h, {'2026-11-10': {K.weight: 82}}), isEmpty, reason: 'ίδια τιμή: δεν ξαναγράφεται');
    });

    test('Οι κανόνες του ιστορικού άλλαξαν (3): το οξυγόνο που είχε σβηστεί ξαναδιαβάζεται', () {
      expect(historyRulesVersion, 3);
    });
  });

  group('A2: ζυγίσεις μόνο από την InBody, μία ολόκληρη τη μέρα', () {
    final day = add(today, -3);
    test('Χειροκίνητο βάρος (Samsung Health) και ρολόι δεν μπαίνουν ποτέ', () {
      final d = Dashboard.fromJson(withBody([
        {'time': ms(day.add(const Duration(hours: 7, minutes: 2))), 'weight': 82.4, 'fatPct': 21.3, 'smm': 36.1, 'app': inbodyApp},
        {'time': ms(day.add(const Duration(hours: 21, minutes: 40))), 'weight': 81.0, 'app': 'com.sec.android.app.shealth'},
        {'time': ms(day.add(const Duration(hours: 22))), 'weight': 80.0, 'fatPct': 27.5, 'app': 'com.samsung.android.wear.shealth'},
        {'time': ms(day.add(const Duration(hours: 23))), 'weight': 79.0}, // χωρίς εφαρμογή
      ]));
      expect(d.body.length, 1);
      expect(d.bodyOther, 3);
      expect(d.latestBody!.weight, 82.4);
      final h = <String, Map<String, double>>{};
      applyRecentRead(h, d, plan: SourcePlan.samsungOnly);
      expect(h[dateKey(day)]![K.weight], 82.4);
      expect(h[dateKey(day)]![K.fatPct], 21.3);
      // Και στη σύνοψη της μέρας (συμπλήρωση, στιγμιότυπα).
      expect(summarizeDay(d, day)[K.weight], 82.4);
    });

    test('Δύο ζυγίσεις InBody την ίδια μέρα: η τελευταία ολόκληρη, ποτέ πεδία από δύο ζυγίσεις', () {
      final d = Dashboard.fromJson(withBody([
        {'time': ms(day.add(const Duration(hours: 7))), 'weight': 82.4, 'fatPct': 21.3, 'smm': 36.1, 'app': inbodyApp},
        {'time': ms(day.add(const Duration(hours: 20))), 'weight': 83.0, 'app': inbodyApp},
      ]));
      final h = <String, Map<String, double>>{
        dateKey(day): {K.weight: 80, K.fatPct: 20, K.smm: 30, K.steps: 9000},
      };
      applyRecentRead(h, d, plan: SourcePlan.samsungOnly);
      expect(h[dateKey(day)]![K.weight], 83.0);
      expect(h[dateKey(day)]!.containsKey(K.fatPct), isFalse);
      expect(h[dateKey(day)]!.containsKey(K.smm), isFalse);
      expect(h[dateKey(day)]![K.steps], isNotNull);
    });

    test('Ο κανόνας της InBody: ίδιος με την ετικέτα στο «Τι φτάνει»', () {
      expect(isScaleApp('com.inbody2014.inbody'), isTrue);
      expect(isScaleApp('kr.co.InBody.app'), isTrue);
      expect(isScaleApp('com.sec.android.app.shealth'), isFalse);
      expect(isScaleApp(''), isFalse);
    });
  });

  group('A4: οξυγόνο της νύχτας', () {
    List<num> ox(DateTime a, DateTime b, num avg, [num? min]) => [ms(a), ms(b), avg, min ?? avg, avg];
    final night = DateTime(2026, 12, 19, 23, 30);
    final wake = DateTime(2026, 12, 20, 7, 10);
    final windows = SleepWindows([(night, wake)], {'2026-12-20': (night, wake)});

    test('Μόνο μέσα στις ώρες ύπνου του Oura· μέσος όρος με στάθμιση διάρκειας· σύντομες μόνο στο ελάχιστο', () {
      final d = Dashboard.fromJson({
        'readAt': ms(now),
        'spo2': [
          ox(DateTime(2026, 12, 19, 23, 40), DateTime(2026, 12, 20, 6, 40), 94, 89), // 7 ώρες, 94%
          ox(DateTime(2026, 12, 20, 6, 40), DateTime(2026, 12, 20, 7, 0), 98), // 20 λεπτά, 98%
          ox(DateTime(2026, 12, 20, 2, 0), DateTime(2026, 12, 20, 2, 0, 30), 99, 86), // 30″ μέτρηση: μόνο στο ελάχιστο
          ox(DateTime(2026, 12, 20, 10, 45), DateTime(2026, 12, 20, 10, 46), 84, 84), // μέρα: έξω από τον ύπνο
          ox(DateTime(2026, 12, 19, 21, 0), DateTime(2026, 12, 19, 21, 30), 80, 80), // βράδυ πριν από τον ύπνο
        ],
      });
      final o = d.watchSpo2(DateTime(2026, 12, 20), windows)!;
      expect(o.avg, closeTo((94 * 420 + 98 * 20) / 440, 1e-9));
      expect(o.min, 86, reason: 'η χαμηλότερη μέτρηση από όλες τις εγγραφές μέσα στον ύπνο (ενδεικτική)');
    });

    test('Χωρίς νύχτα του Oura: κενό (όχι 18:00–12:00)', () {
      final d = Dashboard.fromJson({
        'readAt': ms(now),
        'spo2': [ox(DateTime(2026, 12, 20, 1), DateTime(2026, 12, 20, 6), 95)],
      });
      expect(d.watchSpo2(DateTime(2026, 12, 20), SleepWindows.empty), isNull);
      final plan = SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 12, 1));
      final row = summarizeDay(d, DateTime(2026, 12, 20), plan: plan);
      expect(row.keys.where(spo2Keys.contains), isEmpty);
    });

    test('Μόνο σύντομες μετρήσεις: χωρίς μέσο όρο, με ενδεικτικό ελάχιστο', () {
      final d = Dashboard.fromJson({
        'readAt': ms(now),
        'spo2': [ox(DateTime(2026, 12, 20, 3), DateTime(2026, 12, 20, 3, 0, 20), 97, 93)],
      });
      final o = d.watchSpo2(DateTime(2026, 12, 20), windows)!;
      expect(o.avg, isNull);
      expect(o.min, 93);
    });

    test('Νύχτα του ρολογιού (πριν από το Oura): ο ίδιος κανόνας στάθμισης', () {
      final d = Dashboard.fromJson({
        'readAt': ms(now),
        'sleep': [
          {'start': ms(night), 'end': ms(wake), 'minutes': 440, 'stages': []},
        ],
        'spo2': [
          ox(DateTime(2026, 12, 19, 23, 40), DateTime(2026, 12, 20, 6, 40), 94),
          ox(DateTime(2026, 12, 20, 6, 40), DateTime(2026, 12, 20, 7, 0), 98),
          ox(DateTime(2026, 12, 20, 2, 0), DateTime(2026, 12, 20, 2, 0, 30), 99, 86),
        ],
      });
      final n = d.nights.single;
      expect(n.spo2Avg, closeTo((94 * 420 + 98 * 20) / 440, 1e-9), reason: 'όχι (94+98+99)/3');
      expect(n.spo2Min, 86);
    });

    test('Μέρα του Oura χωρίς γνωστές ώρες ύπνου: το αποθηκευμένο οξυγόνο ΜΕΝΕΙ', () {
      final plan = SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 12, 1));
      final h = <String, Map<String, double>>{
        '2026-12-18': {K.spo2Avg: 95, K.spo2Min: 90, 'o.sleepMin': 400},
        '2026-12-19': {K.spo2Avg: 96, K.spo2Min: 91, 'o.sleepMin': 410},
      };
      // Και οι δύο μέρες χωρίς οξυγόνο στη νέα ανάγνωση· μόνο η 19/12 έχει γνωστές ώρες.
      mergeHistory(h, {'2026-12-18': {K.steps: 5000}, '2026-12-19': {K.steps: 6000}},
          sleepFrom: DateTime(2026, 12, 14), plan: plan, ouraNights: {'2026-12-19'});
      expect(h['2026-12-18']![K.spo2Avg], 95, reason: 'χωρίς ώρες ύπνου δεν ξέρουμε· δεν σβήνεται');
      expect(h['2026-12-19']!.containsKey(K.spo2Avg), isFalse, reason: 'γνωστές ώρες, καμία μέτρηση: κενό');
      // Και η πλήρης ξαναδιάβαση του ιστορικού (replaceSleep).
      final h2 = <String, Map<String, double>>{'2026-12-18': {K.spo2Avg: 95, 'o.sleepMin': 400}};
      mergeHistory(h2, const {}, replaceSleep: true, rangeFrom: DateTime(2026, 12, 15), rangeTo: DateTime(2026, 12, 19),
          plan: plan, ouraNights: const {});
      expect(h2['2026-12-18']![K.spo2Avg], 95);
    });
  });

  group('A12: παλμοί που δεν διαβάστηκαν', () {
    test('Ο ύπνος ενημερώνεται· οι τιμές από τους παλμούς μένουν ως είχαν', () {
      final j = sampleDashboardJson(now);
      j['heart'] = {'error': 'Πάρα πολλές εγγραφές'};
      expect(sleepReadFailed(j), isFalse);
      expect(heartReadFailed(j), isTrue);
      final d = Dashboard.fromJson(j);
      final k = dateKey(add(today, -1));
      final h = <String, Map<String, double>>{
        k: {K.sleepMin: 1, K.sleepHr: 58, K.restHr: 61, K.dayHr: 72, K.walkHr: 95},
      };
      applyRecentRead(h, d, plan: SourcePlan.samsungOnly, heartFailed: true);
      expect(h[k]![K.sleepMin], isNot(1), reason: 'ο ύπνος ενημερώθηκε');
      expect(h[k]![K.sleepHr], 58);
      expect(h[k]![K.restHr], 61);
      expect(h[k]![K.dayHr], 72);
      expect(h[k]![K.walkHr], 95);
    });
  });

  group('A15: τιμές έξω από τα λογικά όρια', () {
    test('Παλμοί 0, οξυγόνο 0%, θερμοκρασία 0: αγνοούνται· «ελάχιστο 0» δεν είναι μέτρηση', () {
      final a = DateTime(2026, 12, 20, 9);
      final b = a.add(const Duration(minutes: 5));
      final d = Dashboard.fromJson({
        'readAt': ms(now),
        'heart': [
          [ms(a), ms(b), 0, 0, 0],
          [ms(b), ms(b.add(const Duration(minutes: 5))), 64, 0, 300],
        ],
        'spo2': [
          [ms(a), ms(b), 0, 0, 0],
          [ms(b), ms(b.add(const Duration(minutes: 5))), 95, 0, 100],
        ],
        'skinTemp': [
          [ms(a), ms(b), 0],
          [ms(b), ms(b), 34.5],
        ],
      });
      expect(d.heart.length, 1);
      expect(d.heart.single.min, 64);
      expect(d.heart.single.max, 64);
      expect(d.spo2.length, 1);
      expect(d.spo2.single.min, 95);
      expect(d.skin.single.avg, 34.5);
      expect(d.heartRange(a), (64, 64));
    });

    test('Εγγραφή ύπνου με χρόνο 1970: αγνοείται (δεν «καταπίνει» τις νύχτες)', () {
      final d = Dashboard.fromJson({
        'readAt': ms(now),
        'sleep': [
          {'start': 0, 'end': ms(DateTime(2026, 12, 20, 7)), 'minutes': 999999, 'stages': []},
          {'start': ms(DateTime(2026, 12, 19, 23)), 'end': ms(DateTime(2026, 12, 20, 7)), 'minutes': 450, 'stages': []},
        ],
      });
      expect(d.nights.single.minutes, 450);
    });
  });

  // Η πραγματική νύχτα Δευ 2 → Τρ 3/11 όπως τη δείχνει η Samsung Health (στοιχεία του χρήστη, 4/11):
  // - «υπνάκος» 23:43–02:40: χρόνος ύπνου 2ω57, πραγματικός ύπνος 2ω32,
  // - κύρια 03:50–07:08: χρόνος ύπνου 3ω18, πραγματικός ύπνος 2ω57, βαθύς 0,
  // - σύνολο μέρας: χρόνος ύπνου 6ω15, πραγματικός 5ω29. Κενό 02:40–03:50 (70 λεπτά ξύπνιος).
  group('Πραγματικός ύπνος από τις φάσεις (νύχτα 2→3/11)', () {
    List<Object> st(String name, DateTime a, DateTime b) => [name, ms(a), ms(b)];
    DateTime t(int day, int h, int m) => DateTime(2026, 11, day, h, m);
    final first = {
      'start': ms(t(2, 23, 43)),
      'end': ms(t(3, 2, 40)),
      'minutes': 177,
      'stages': [
        st('LIGHT', t(2, 23, 43), t(3, 1, 0)),
        st('AWAKE', t(3, 1, 0), t(3, 1, 25)),
        st('DEEP', t(3, 1, 25), t(3, 2, 0)),
        st('REM', t(3, 2, 0), t(3, 2, 40)),
      ],
    };
    final main = {
      'start': ms(t(3, 3, 50)),
      'end': ms(t(3, 7, 8)),
      'minutes': 198,
      'score': 40,
      'stages': [
        st('LIGHT', t(3, 3, 50), t(3, 5, 30)),
        st('AWAKE', t(3, 5, 30), t(3, 5, 51)),
        st('REM', t(3, 5, 51), t(3, 7, 8)),
      ],
    };
    Map<String, dynamic> json({int gapSteps = 0}) => {
          'readAt': ms(t(3, 12, 0)),
          'sleep': [first, main],
          'stepsMin': [
            if (gapSteps > 0) [ms(t(3, 3, 10)), gapSteps],
          ],
          'stepsFrom': ms(DateTime(2026, 10, 28)),
        };

    test('Κενό χωρίς βήματα: μία νύχτα 5ω29 πραγματικός ύπνος (όπως η Samsung), το κενό ΔΕΝ μετρά', () {
      final n = Dashboard.fromJson(json()).nights.single;
      expect(n.date, DateTime(2026, 11, 3));
      expect(n.minutes, 152 + 177, reason: '5ω29: «Πραγματικός ύπνος» της Samsung');
      expect(n.staged, isTrue);
      expect(n.spanMinutes, 177 + 198, reason: '6ω15: «Χρόνος ύπνου» της Samsung, με τα ξυπνήματα');
      expect(n.estimatedMinutes, 0, reason: 'χωρίς παλμούς δεν υπάρχει «πιθανός ύπνος»· τα 70 λεπτά δεν προστίθενται');
      expect(n.start, t(2, 23, 43));
      expect(n.score, isNull, reason: 'σπασμένη νύχτα');
      expect(summarizeDay(Dashboard.fromJson(json()), DateTime(2026, 11, 3))[K.sleepMin], 329);
    });

    // Έλεγχος 2, C1: πριν (A6) 120 βήματα στο κενό έκοβαν τη νύχτα στα 2ω57. Τώρα: ίδια νύχτα, όπως η Samsung (5ω29).
    test('Σηκώθηκε στο κενό (βήματα): ίδια νύχτα 5ω29, το κενό δεν μετρά (C1)', () {
      final n = Dashboard.fromJson(json(gapSteps: 120)).nights.single;
      expect(n.minutes, 152 + 177);
      expect(n.spanMinutes, 177 + 198);
      expect(n.start, t(2, 23, 43));
      expect(n.napMinutes, 0);
      expect(n.betweenMinutes, 70);
      expect(n.stageMinutes['DEEP'], 35);
    });

    test('Σύγκριση πηγών: πραγματικός ύπνος με πραγματικό, «με τα ξυπνήματα» με «με τα ξυπνήματα»', () {
      final watch = Dashboard.fromJson(json()).nights;
      final oura = parseOura(sleep: [
        {
          'id': 'x',
          'day': '2026-11-03',
          'type': 'long_sleep',
          'bedtime_start': t(2, 23, 30).toUtc().toIso8601String(),
          'bedtime_end': t(3, 7, 10).toUtc().toIso8601String(),
          'total_sleep_duration': 330 * 60,
          'awake_time': 70 * 60,
          'latency': 10 * 60,
        },
      ], dailySleep: const [], readiness: const []).nights;
      final plan = SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 3));
      final r = buildCompareRows(plan: plan, oura: oura, watch: watch, today: DateTime(2026, 11, 3)).single;
      expect(r.ouraMinutes, 330);
      expect(r.watchMinutes, 329);
      expect(r.diff, -1);
      expect(r.ouraSpan, 450, reason: '23:40 → 07:10');
      expect(r.watchSpan, 375);
      // Ρολόι χωρίς φάσεις: δεν μπαίνει δίπλα στον πραγματικό ύπνο του Oura.
      final unstaged = Dashboard.fromJson({
        ...json(),
        'sleep': [
          {...first, 'stages': []},
          main,
        ],
      }).nights;
      final r2 = buildCompareRows(plan: plan, oura: oura, watch: unstaged, today: DateTime(2026, 11, 3)).single;
      expect(r2.watchMinutes, isNull);
      expect(r2.diff, isNull);
    });
  });

  // Η ΙΔΙΑ νύχτα όπως την έδειχνε η εφαρμογή (#65): 6ω15 (= «Χρόνος ύπνου» της Samsung, με τα ξυπνήματα), φάσεις
  // βαθύς 8′, ελαφρύς 4ω31, REM 51′, ξύπνιος 47′, 2 κομμάτια με βαθμολογίες 18 · 31. Πραγματικός ύπνος = 330′.
  test('Παλινδρόμηση: νύχτα 3/11 με τα νούμερα της εφαρμογής → 5ω30 πραγματικός ύπνος, όχι 6ω15', () {
    DateTime t(int day, int h, int m) => DateTime(2026, 11, day, h, m);
    List<Object> st(String name, DateTime a, int minutes) => [name, ms(a), ms(a.add(Duration(minutes: minutes)))];
    List<List<Object>> seq(DateTime start, List<(String, int)> parts) {
      final out = <List<Object>>[];
      var x = start;
      for (final (name, m) in parts) {
        out.add(st(name, x, m));
        x = x.add(Duration(minutes: m));
      }
      return out;
    }

    final j = {
      'readAt': ms(t(3, 12, 0)),
      'sleep': [
        {
          'start': ms(t(2, 23, 43)),
          'end': ms(t(3, 2, 40)),
          'minutes': 177,
          'score': 18,
          'stages': seq(t(2, 23, 43), [('LIGHT', 60), ('DEEP', 8), ('LIGHT', 60), ('REM', 25), ('AWAKE', 25)]),
        },
        {
          'start': ms(t(3, 3, 50)),
          'end': ms(t(3, 7, 8)),
          'minutes': 198,
          'score': 31,
          'stages': seq(t(3, 3, 50), [('LIGHT', 80), ('AWAKE', 22), ('LIGHT', 71), ('REM', 26)]),
        },
      ],
      'stepsMin': <List<num>>[],
      'stepsFrom': ms(DateTime(2026, 10, 28)),
    };
    final d = Dashboard.fromJson(j);
    final n = d.nights.single;
    expect(n.stageMinutes, {'LIGHT': 271, 'DEEP': 8, 'REM': 51, 'AWAKE': 47});
    expect(n.spanMinutes, 375, reason: 'αυτό έδειχνε πριν η εφαρμογή ως «ύπνο» (6ω15)');
    expect(n.minutes, 330, reason: '8 + 271 + 51: «Πραγματικός ύπνος» της Samsung (5ω29)');
    expect(n.staged, isTrue);
    expect(n.betweenMinutes, 70, reason: '02:40–03:50: φαίνεται χωριστά, δεν μετρά ως ύπνος');
    expect(n.estimatedMinutes, 0);
    expect(n.start, t(2, 23, 43));
    expect(n.end, t(3, 7, 8));
    expect(n.parts.map((p) => p.score), [18, 31]);
    expect(n.score, isNull);
    final row = summarizeDay(d, DateTime(2026, 11, 3));
    expect(row[K.sleepMin], 330);
    expect(row[K.awakeMin], 47);
    // Νύχτα χωρίς φάσεις: όχι στα στατιστικά διάρκειας (μόνο ώρες).
    final unstaged = Dashboard.fromJson({
      ...j,
      'sleep': [
        for (final r in j['sleep'] as List) {...(r as Map<String, dynamic>), 'stages': <Object>[]},
      ],
    });
    expect(unstaged.nights.single.staged, isFalse);
    final r2 = summarizeDay(unstaged, DateTime(2026, 11, 3));
    expect(r2.containsKey(K.sleepMin), isFalse);
    expect(r2[K.bedtime], isNotNull);
  });
}
