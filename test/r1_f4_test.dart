// Round 1 · f4 («Μετρήσεις υγείας, όρια αναφοράς, Τάσεις, Σώμα, Καρδιά, Ύπνος, αναφορά γιατρού»).
// Κάθε αναμενόμενη τιμή βγήκε από τον γραμμένο κανόνα (υπολογισμός με το χέρι ή με python στο
// /home/claude/scratch/f4/: dart_tests_expect.py με το ίδιο Random της Dart), όχι από τη νέα υλοποίηση.
// Όλες οι τιμές είναι επινοημένες (καμία πραγματική μέτρηση).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/body_trend.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/heart_day.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/hrv_trend.dart';
import 'package:ygeia_forma/oxygen_note.dart';
import 'package:ygeia_forma/pages/body.dart';
import 'package:ygeia_forma/pages/category.dart';
import 'package:ygeia_forma/pages/info_sheet.dart';
import 'package:ygeia_forma/pages/metric_page.dart';
import 'package:ygeia_forma/pages/report_page.dart';
import 'package:ygeia_forma/pages/trends.dart';
import 'package:ygeia_forma/pages/week_card.dart';
import 'package:ygeia_forma/profile.dart';
import 'package:ygeia_forma/reference.dart';
import 'package:ygeia_forma/report.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/ti_ftanei.dart';
import 'package:ygeia_forma/trends.dart';
import 'package:ygeia_forma/unusual.dart';
import 'package:ygeia_forma/weekly.dart';
import 'package:ygeia_forma/widgets.dart';

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 2400)}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: w)));
  await t.pumpAndSettle();
}

DateTime _add(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// Κανονική τιμή (Box–Muller), όπως στο test/trends_test.dart: πρώτα το log, μετά το cos.
double _normal(math.Random r) => math.sqrt(-2 * math.log(1 - r.nextDouble())) * math.cos(2 * math.pi * r.nextDouble());

const _inbody = 'com.inbody2014.inbody';

BodyMeasurement _m(DateTime t, double kg, {double? fat, double? smm}) =>
    BodyMeasurement(time: t, weight: kg, fatPct: fat, smm: smm, app: _inbody);

Map<String, dynamic> _bodyJson(DateTime readAt, List<(DateTime, double, double?)> rows) => {
      'ok': true,
      'readAt': readAt.millisecondsSinceEpoch,
      'body': [
        for (final (t, kg, fat) in rows)
          {'time': t.millisecondsSinceEpoch, 'weight': kg, 'fatPct': fat, 'smm': 34.0, 'app': _inbody},
      ],
    };

void main() {
  // ---------------------------------------------------------------------------------------------------------------
  group('S4-1: σταθερή απώλεια βάρους με ζύγιση Δευτέρα, Τετάρτη, Παρασκευή', () {
    final today = DateTime(2026, 10, 24);
    final weight = trendMetrics.firstWhere((m) => m.key == K.weight);

    /// 200 μέρες, ζύγιση Δε/Τε/Πα, 90 kg + [perWeek] kg την εβδομάδα + θόρυβος 0,4 kg. Επιστρέφει (κάτω, πάνω).
    (int, int) run(TrendPeriod period, int seed, {double perWeek = -0.45, int sims = 100}) {
      final r = math.Random(seed);
      var down = 0, up = 0;
      for (var s = 0; s < sims; s++) {
        final h = <String, Map<String, double>>{};
        for (var ago = 199; ago >= 0; ago--) {
          final d = _add(today, -ago);
          if (d.weekday == DateTime.monday || d.weekday == DateTime.wednesday || d.weekday == DateTime.friday) {
            h[dateKey(d)] = {K.weight: 90 + perWeek / 7 * (200 - ago) + 0.4 * _normal(r)};
          }
        }
        final t = computeTrend(weight, h, today, period);
        if (t.status == TrendStatus.down) down++;
        if (t.status == TrendStatus.up) up++;
      }
      return (down, up);
    }

    test('−0,45 kg/εβδομάδα: «↓» στις 30 μέρες και στους 3 μήνες (πριν: «Λίγες ζυγίσεις για συμπέρασμα» σχεδόν πάντα)', () {
      // python (ίδιο Random): μήνας 100/100, τρίμηνο 100/100· ο παλιός κανόνας 0/100 και 2/100.
      expect(run(TrendPeriod.month, 4101).$1, greaterThanOrEqualTo(95));
      expect(run(TrendPeriod.quarter, 4102).$1, greaterThanOrEqualTo(95));
    });

    test('χωρίς αλλαγή (μόνο θόρυβος 0,4 kg): σχεδόν ποτέ «άλλαξε»', () {
      // python: 0/100 και 0/100.
      final m = run(TrendPeriod.month, 4103, perWeek: 0);
      final q = run(TrendPeriod.quarter, 4104, perWeek: 0);
      expect(m.$1 + m.$2, lessThanOrEqualTo(3));
      expect(q.$1 + q.$2, lessThanOrEqualTo(3));
    });

    test('αυτοσυσχέτιση: μια γραμμή δεν μετρά ως «μέρες που μοιάζουν» όταν αφαιρείται ([detrend])', () {
      // 13 ζυγίσεις Δε/Τε/Πα σε 30 μέρες: 90 − 0,45/7·t ± 0,2 εναλλάξ. python: 0,95 (μόνο ο μέσος όρος) και 3/13 = 0,2308.
      final w = <(DateTime, double)>[];
      var k = 0;
      for (var ago = 29; ago >= 0; ago--) {
        final d = _add(today, -ago);
        if (d.weekday == DateTime.monday || d.weekday == DateTime.wednesday || d.weekday == DateTime.friday) {
          w.add((d, 90 - 0.45 / 7 * (30 - ago) + (k.isEven ? 0.2 : -0.2)));
          k++;
        }
      }
      expect(w.length, 13);
      expect(dailyCorrelation([w])!, closeTo(0.95, 1e-9));
      expect(dailyCorrelation([w], detrend: true)!, closeTo(3 / 13, 1e-9));
    });

    test('η σύνοψη δεν λέει «ό,τι αλλάζει είναι μέσα στις διακυμάνσεις» όταν κάποια γραμμή δεν συγκρίθηκε', () {
      expect(someInconclusiveText, isNot(contains('μέσα στις συνηθισμένες')));
      expect(someInconclusiveText, contains('Λίγες ζυγίσεις για συμπέρασμα'));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('S11-2: ξένη ζύγιση (άλλος άνθρωπος στη ζυγαριά)', () {
    final today = DateTime(2026, 11, 13);

    test('Τάσεις: η μέρα της ξένης ζύγισης δεν μετρά (ούτε στο λίπος)', () {
      final h = <String, Map<String, double>>{
        for (var i = 0; i < 20; i++) dateKey(_add(today, -i)): {K.weight: 90.0, K.fatPct: 25.0},
      };
      h[dateKey(_add(today, -5))] = {K.weight: 31.0, K.fatPct: 18.0};
      expect(foreignWeighIn(h, SourcePlan.samsungOnly, _add(today, -5)), isTrue);
      expect(foreignWeighIn(h, SourcePlan.samsungOnly, _add(today, -6)), isFalse);
      final t = computeTrend(trendMetrics.firstWhere((m) => m.key == K.fatPct), h, today, TrendPeriod.month);
      expect(t.points.any((p) => p.$2 == 18.0), isFalse);
      expect(t.nCurrent, 19);
    });

    test('Σώμα: η ξένη δεν μετρά· αν η πρώτη της μέρας είναι ξένη, μετρά η επόμενη της ίδιας μέρας', () {
      final body = [
        for (final d in [1, 3, 5, 9, 11]) _m(DateTime(2026, 11, d, 8), 90, fat: 25),
        _m(DateTime(2026, 11, 7, 7), 30, fat: 15),
        _m(DateTime(2026, 11, 7, 8), 90.2, fat: 25.1),
      ]..sort((a, b) => a.time.compareTo(b.time));
      final foreign = foreignBody(body);
      expect(foreign.length, 1);
      expect(foreign.single.weight, 30);
      final counted = countedBody(body);
      expect(counted.length, 6);
      expect(counted.any((b) => b.weight == 30), isFalse);
      expect(counted.firstWhere((b) => b.time.day == 7).weight, 90.2);
      // Η «προηγούμενη» ζύγιση για το «−1,1 kg από …» δεν είναι ποτέ η ξένη.
      final last = body.last;
      expect(previousCounted(countedBody(body), last)!.time, DateTime(2026, 11, 9, 8));
    });

    test('Αναφορά: η ξένη ζύγιση δεν μπαίνει στον πίνακα και μετριέται', () {
      final h = <String, Map<String, double>>{
        for (var i = 0; i < 30; i++) dateKey(_add(today, -i)): {K.weight: 90.0},
      };
      h[dateKey(_add(today, -2))] = {K.weight: 30.0};
      final r = buildReport(h, DateTime(2026, 11, 13, 10));
      expect(r.foreignWeighIns, 1);
      expect(r.weighIns.any((w) => w.$2 == 30.0), isFalse);
    });

    testWidgets('Σώμα: τελευταία ζύγιση ξένη → φαίνεται σημειωμένη, χωρίς «… kg από …»', (t) async {
      // Round 2 (g4 · R2-E-2): τελευταία ξένη ζύγιση = άλλο βάρος την ίδια μέρα με μια δική σου (εδώ 08:00 εσύ, 09:00 το
      // παιδί). Πριν: μόνο το παιδί στις 13/11, που με τον νέο κανόνα (καμία ζύγιση μετά) είναι «σε αναμονή».
      // Round 7 (f5 · A4-1): πάνω η ζύγιση της μέρας (08:00 90,0), όπως η Σήμερα και το widget· η ξένη 09:00 σε γκρι γραμμή
      // και στον πίνακα με «*» (πριν: η ξένη 30,0 ως «Τελευταία ζύγιση», με τη σημείωση «διαφέρει πολύ…»).
      final s = HealthStore()
        ..data = Dashboard.fromJson(_bodyJson(DateTime(2026, 11, 13, 20), [
          for (final d in [2, 4, 6, 9, 11]) (DateTime(2026, 11, d, 8), 90.0, 25.0),
          (DateTime(2026, 11, 13, 8), 90.0, 25.0),
          (DateTime(2026, 11, 13, 9), 30.0, 15.0),
        ]));
      await _pump(t, BodyPage(store: s, now: DateTime(2026, 11, 13, 21)), size: const Size(400, 4000));
      expect(find.byKey(const ValueKey('body-foreign-latest')), findsNothing);
      expect(t.widget<Text>(find.byKey(const ValueKey('body-later-weighin'))).data, contains('09:00: 30,0 kg'));
      expect(t.widgetList<InfoRow>(find.byType(InfoRow)).firstWhere((r) => r.label == 'Βάρος').value, '90,0 kg  (0)'); // R9-A4-3: και το 0
      expect(find.byKey(const ValueKey('body-weighings-foreign')), findsOneWidget);
      expect(t.widgetList<TrendPill>(find.byType(TrendPill)).where((p) => p.text.contains(' kg από ')), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('S4-2: HRV, «συνηθισμένο σου εύρος» = μέσος ± 1 τυπική απόκλιση', () {
    final today = DateTime(2026, 11, 20);
    DateTime back(int i) => DateTime(today.year, today.month, today.day - i);
    final plan = SourcePlan([SourceEra(Source.oura, back(400))]);
    Map<String, Map<String, double>> hist(double week) => {
          for (var i = 0; i < 7; i++) dateKey(back(i)): {'o.hrv': week},
          for (var i = 7; i < 67; i++) dateKey(back(i)): {'o.hrv': i.isEven ? 36.0 : 44.0},
        };

    test('η θέση κρίνεται από τα νούμερα που φαίνονται (36–44)', () {
      // ln 36 / ln 44 εναλλάξ: ± 1 SD → 35,97–44,04 ms → «36–44».
      expect(hrvTrendText(hrvTrend(hist(44.2), plan, today)!), '7 νύχτες: 44 ms, μέσα στο συνηθισμένο σου εύρος (36–44)');
      expect(hrvTrend(hist(35.6), plan, today)!.band, HrvBand.within, reason: 'φαίνεται 36, όσο το κάτω άκρο');
      expect(hrvTrend(hist(44.6), plan, today)!.band, HrvBand.above);
      expect(hrvTrend(hist(35.4), plan, today)!.band, HrvBand.below);
    });

    test('προσομοίωση (AR(1) φ = 0,5, σ = 0,2 σε λογάριθμο): σπάνια «κάτω/πάνω» χωρίς αλλαγή· μέσα ~2 στις 3 νύχτες', () {
      // python (ίδιο Random): έξω 13,8% (παλιός κανόνας ±½ SD: 47,3%), μέσα στο εύρος 71,1% των νυχτών βάσης.
      final r = math.Random(20261113);
      final start = DateTime(2026, 1, 1);
      final h = <String, Map<String, double>>{};
      var x = _normal(r);
      for (var i = 0; i < 400; i++) {
        x = 0.5 * x + math.sqrt(1 - 0.25) * _normal(r);
        h[dateKey(_add(start, i))] = {'o.hrv': 45 * math.exp(0.2 * x)};
      }
      final p = SourcePlan([SourceEra(Source.oura, DateTime(2025, 1, 1))]);
      var outside = 0, n = 0, inside = 0, nights = 0;
      for (var i = 66; i < 400; i++) {
        final day = _add(start, i);
        final tr = hrvTrend(h, p, day)!;
        n++;
        if (tr.band != HrvBand.within) outside++;
        for (var k = 7; k < 67; k++) {
          final v = h[dateKey(_add(day, -k))]!['o.hrv']!;
          nights++;
          if (v >= tr.lowMs && v <= tr.highMs) inside++;
        }
      }
      expect(outside / n, lessThanOrEqualTo(0.18), reason: '$outside από $n');
      expect(inside / nights, greaterThanOrEqualTo(0.6));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('S4-3 / S4-4: Σώμα, τάση λίπους και μυών', () {
    test('S4-4: μετρά η ΠΡΩΤΗ (πρωινή) ζύγιση της μέρας, όχι η βραδινή μετά την προπόνηση', () {
      final body = <BodyMeasurement>[
        for (final (d, fat) in [(2, 26.0), (4, 26.1), (6, 26.0), (9, 26.1), (11, 26.0), (13, 26.1)])
          _m(DateTime(2026, 11, d, 8), 90, fat: fat),
        for (final (d, fat) in [(9, 24.6), (11, 24.8), (13, 24.7)]) _m(DateTime(2026, 11, d, 20), 90.5, fat: fat),
      ]..sort((a, b) => a.time.compareTo(b.time));
      final t = bodyTrend(body, (b) => b.fatPct)!;
      // πρωινές: 26,0 · 26,1 · 26,0 | 26,1 · 26,0 · 26,1 → μεσαίες 26,0 και 26,1.
      expect((t.now, t.before), (26.1, 26.0));
      expect(bodyDaily(body, (b) => b.fatPct).every((e) => e.$1.hour == 8), isTrue);
    });

    // Round 2 (g4 · R2-D-2): όρια στο πάνω άκρο του θορύβου της μελέτης (πριν 1,5 / 1,0).
    test('S4-3: όριο θορύβου 2 μονάδες λίπους και 1,7 kg (McLester 2020)', () {
      expect(bodyFloorFatPct, 2.0);
      expect(bodyFloorKg, 1.7);
      expect(bodyDiffShown(1.9, bodyFloorFatPct), isFalse);
      expect(bodyDiffShown(2.0, bodyFloorFatPct), isTrue);
      expect(bodyDiffShown(-2.1, bodyFloorFatPct), isTrue);
      expect(bodyDiffShown(1.6, bodyFloorKg), isFalse);
      expect(bodyDiffShown(-1.7, bodyFloorKg), isTrue);
      expect(bodyDiffShown(0, 0), isFalse);
    });

    testWidgets('S4-3 + S3-3: «(−2,1)» φαίνεται· η ημερομηνία σε σχέση με τώρα («Χθες»), όχι με την ανάγνωση', (t) async {
      final s = HealthStore()
        ..data = Dashboard.fromJson(_bodyJson(DateTime(2026, 11, 13, 20), [
          for (final (d, fat) in [(2, 27.9), (4, 27.5), (6, 27.0), (9, 25.6), (11, 25.3), (13, 25.4)])
            (DateTime(2026, 11, d, 8), 90.0, fat),
        ]));
      await _pump(t, BodyPage(store: s, now: DateTime(2026, 11, 14, 9)), size: const Size(400, 4000));
      String row(String label) => t.widgetList<InfoRow>(find.byType(InfoRow)).firstWhere((r) => r.label == label).value;
      // μεσαίες 27,5 και 25,4 → −2,1 (πάνω από το όριο 1,5)· «%» χωρίς κενό.
      expect(row('Λίπος'), '25,4%  (−2,1)');
      expect(row('Σκελετικοί μύες'), '34,0 kg');
      expect(find.text('Χθες 08:00'), findsOneWidget);
    });

    test('κείμενα: όχι «σχεδόν ίδια τιμή από μέρα σε μέρα»', () {
      expect(metricInfos[K.fatPct]!.accuracy, isNot(contains('σχεδόν ίδια')));
      expect(metricInfos[K.fatPct]!.accuracy, contains('DXA'));
      expect(metricInfos[K.smm]!.accuracy, contains('McLester'));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('S12-04: εύρη αναφοράς με αριθμούς', () {
    final today = DateTime(2027, 11, 16); // ένας χρόνος μετά: ίδιες ηλικίες με επινοημένα έτη
    Profile p(String? sex, int? by) => Profile(birthYear: by, birthMonth: 1, sex: sex, heightCm: 180);

    test('λίπος (Gallagher 2000): όρια ανά φύλο και ηλικία, κείμενο με «DXA»', () {
      final m39 = fatRange(p('m', 1988), today)!;
      expect((m39.low, m39.high), (8.0, 20.0));
      expect(m39.text, startsWith('8–19,9% για άνδρες 20–39 ετών'));
      expect(m39.text, contains('DXA'));
      final m40 = fatRange(p('m', 1987), today)!;
      expect((m40.low, m40.high), (11.0, 22.0));
      expect(m40.text, startsWith('11–21,9% για άνδρες 40–59 ετών'));
      expect((fatRange(p('m', 1968), today)!.low, fatRange(p('m', 1968), today)!.high), (11.0, 22.0));
      expect((fatRange(p('m', 1967), today)!.low, fatRange(p('m', 1967), today)!.high), (13.0, 25.0));
      expect((fatRange(p('f', 1988), today)!.low, fatRange(p('f', 1988), today)!.high), (21.0, 33.0));
      expect((fatRange(p('f', 1987), today)!.low, fatRange(p('f', 1987), today)!.high), (23.0, 34.0));
      expect((fatRange(p('f', 1967), today)!.low, fatRange(p('f', 1967), today)!.high), (24.0, 36.0));
      expect(fatRange(p('m', 2008), today), isNull, reason: '19 ετών');
      expect(fatRange(p('m', 1947), today), isNull, reason: '80 ετών');
      expect(fatRange(p(null, 1987), today), isNull);
      expect(fatRange(p('m', null), today), isNull);
    });

    test('λίπος: θέση και «κοντά στο όριο» (η ζυγαριά δείχνει συνήθως λιγότερο από το DXA, S4-6)', () {
      final r = fatRange(p('m', 1987), today)!;
      expect([r.place(10.9), r.place(11.0), r.place(21.9), r.place(22.0)], [-1, 0, 0, 1]);
      expect(r.placeText(21.4), 'κοντά στο πάνω όριο');
      expect(r.placeText(21.0), 'κοντά στο πάνω όριο');
      expect(r.placeText(20.9), 'μέσα στο εύρος');
      expect(r.placeText(22.0), 'πάνω από το εύρος');
      expect(r.placeText(10.5), 'κοντά στο κάτω όριο');
      expect(r.placeText(9.9), 'κάτω από το εύρος');
    });

    test('ύπνος (AASM/SRS): 18–60 ετών, «κοντά στο κάτω όριο» ως 30 λεπτά κάτω (S4-5)', () {
      final s = sleepRange(p('m', 1987), today)!;
      expect(s.low, 420);
      expect([s.place(419), s.place(420)], [-1, 0]);
      expect(s.placeText(400), 'κοντά στο κάτω όριο', reason: '6 ώρες 40 λεπτά μετρημένα ≈ 7 ώρες δηλωμένες (Lauderdale 2008)');
      expect(s.placeText(390), 'κοντά στο κάτω όριο');
      expect(s.placeText(389), 'κάτω από το εύρος');
      expect(s.placeText(420), 'μέσα στο εύρος');
      expect(s.cite, contains('Lauderdale'));
      expect(sleepRange(p('m', 2010), today), isNull, reason: '17 ετών');
      expect(sleepRange(p('m', 1966), today), isNull, reason: '61 ετών');
      expect(sleepRange(p('m', 2009), today), isNotNull);
      expect(sleepRange(p('m', 1967), today), isNotNull);
      expect(sleepRange(p('m', null), today), isNotNull);
    });

    test('βήματα, δείκτης μάζας σώματος, βάρος, αναπνοές, ηλικία', () {
      expect(stepsRange(p('m', 1968), today)!.low, 8000);
      expect(stepsRange(p('m', 1967), today)!.low, 6000);
      expect(stepsRange(p('m', null), today)!.low, 8000);
      expect([bmiRange.place(18.4), bmiRange.place(18.5), bmiRange.place(24.9), bmiRange.place(25.0)], [-1, 0, 0, 1]);
      expect(bmiRange.placeText(24.9), 'μέσα στο εύρος', reason: 'χωρίς περιθώριο: ο δείκτης δεν είναι εκτίμηση συσκευής');
      final w = healthyWeight(180)!;
      expect(w.$1, closeTo(59.94, 1e-9));
      expect(w.$2, closeTo(81.0, 1e-9));
      expect(healthyWeight(null), isNull);
      expect(bmiOf(81, 180)!, closeTo(25.0, 1e-9));
      expect(bmiOf(null, 180), isNull);
      expect(inBodyHeight(81, 25)!, closeTo(180.0, 1e-9));
      expect(inBodyHeight(81, 0), isNull);
      expect([breathRange.place(11.7), breathRange.place(11.8), breathRange.place(19.2), breathRange.place(19.25)], [-1, 0, 0, 1]);
      expect(const Profile(birthYear: 1987, birthMonth: 11).ageOn(DateTime(2027, 10, 31)), 39);
      expect(const Profile(birthYear: 1987, birthMonth: 11).ageOn(DateTime(2027, 11, 1)), 40);
    });

    test('κείμενα «i»: βάρος ίδια ώρα (S4-9), παλμοί ύπνου από μία συσκευή (S4-8), HRV εύρος (S4-2)', () {
      expect(metricInfos[K.weight]!.accuracy, contains('ίδια ώρα'));
      expect(metricInfos[K.weight]!.accuracy, isNot(contains('ίδια μέρα')));
      expect(metricInfos[K.weight]!.accuracy, contains('0,5–1 kg'));
      expect(metricInfos[K.sleepHr]!.what, isNot(contains('ή από το ρολόι, τις νύχτες χωρίς δαχτυλίδι')));
      expect(metricInfos[K.sleepHr]!.shows, contains('αργά το βράδυ'));
      expect(metricInfos[K.hrv]!.compare, contains('συνηθισμένο σου εύρος'));
      expect(metricInfos[K.sleepMin]!.down, contains('δήλωναν'));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('Τάσεις: ονόματα, σειρά, κάλυψη οξυγόνου', () {
    test('U1b-16: «Παλμοί ξύπνιος» ίδιο με τη σελίδα της μέτρησης', () {
      expect(metricDef(K.dayHr)!.label, metricSpecs[K.dayHr]!.title);
    });

    test('U2a-12: ο μέσος όρος οξυγόνου του Oura με τις λέξεις των καρτών, πριν από του ρολογιού', () {
      expect(metricDef(K.ringSpo2)!.label, '$oxygenAvgLabel (Oura)');
      expect(metricDef(K.spo2Avg)!.label, '$oxygenAvgLabel (ρολόι)');
      final keys = [for (final m in trendMetricsFor(SourcePlan([SourceEra(Source.oura, DateTime(2026, 11, 1))]))) m.key];
      expect(keys.indexOf(K.ringSpo2), lessThan(keys.indexOf(K.spo2Avg)));
      expect(keys.where((k) => k == K.ringSpo2).length, 1);
      expect(trendMetricsFor(SourcePlan.samsungOnly), trendMetrics);
    });

    test('S4-8 (4): οξυγόνο ρολογιού σε νύχτα Oura μόνο με κάλυψη ≥ 50%', () {
      final plan = SourcePlan([SourceEra(Source.oura, DateTime(2026, 10, 1))]);
      final day = DateTime(2026, 11, 10);
      expect(watchOxygenCovered({dateKey(day): {K.spo2Cov: 0.3}}, plan, day), isFalse);
      expect(watchOxygenCovered({dateKey(day): {K.spo2Cov: 0.5}}, plan, day), isTrue);
      expect(watchOxygenCovered({dateKey(day): {K.spo2Avg: 95}}, plan, day), isTrue, reason: 'παλιά νύχτα χωρίς κάλυψη');
      final before = DateTime(2026, 9, 20);
      expect(watchOxygenCovered({dateKey(before): {K.spo2Cov: 0.1}}, plan, before), isTrue, reason: 'νύχτα του ρολογιού');
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('Αναφορά για γιατρό', () {
    test('U1b-13: με ζύγιση κάθε μέρα, η πρώτη και η τελευταία του διαστήματος (6 γραμμές)', () {
      final to = DateTime(2026, 11, 13);
      final h = <String, Map<String, double>>{
        for (var i = 0; i < 120; i++) dateKey(_add(to, -i)): {K.weight: 85 + 0.05 * i},
      };
      final r = buildReport(h, DateTime(2026, 11, 13, 10));
      expect(r.weighInsInPeriod, 90);
      expect(r.weighInsSpread, isTrue);
      expect(r.weighIns.length, 6);
      expect(r.weighIns.first.$1, to);
      expect(r.weighIns.last.$1, _add(to, -89));
      expect(reportWeighTitle(r), 'Ζυγίσεις (InBody H40) · 6 από τις 90 του διαστήματος, από την πρώτη ως την τελευταία');
      expect(spreadPick([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 6), [1, 3, 5, 6, 8, 10]);
      expect(spreadPick([1, 2, 3], 6), [1, 2, 3]);
    });

    test('U1b-13: λίγες ζυγίσεις στο διάστημα → οι τελευταίες, όπως πριν', () {
      final to = DateTime(2026, 11, 13);
      final h = <String, Map<String, double>>{
        for (final ago in [0, 40, 80, 120, 160, 200, 240]) dateKey(_add(to, -ago)): {K.weight: 90.0},
      };
      final r = buildReport(h, DateTime(2026, 11, 13, 10));
      expect(r.weighInsSpread, isFalse);
      expect(r.weighIns.length, 6);
      expect(reportWeighTitle(r), 'Ζυγίσεις (InBody H40) · οι 6 τελευταίες');
    });

    testWidgets('U1b-01: το σώμα της σελίδας στήνεται φαρδύτερα και μικραίνει, χωρίς στενή στήλη', (t) async {
      Future<RenderReportFit> fit(double childHeight) async {
        await t.pumpWidget(MaterialApp(
          home: Center(
            child: SizedBox(
              width: 500,
              height: 300,
              child: ReportFit(
                key: const ValueKey('fit'),
                child: Column(
                  key: const ValueKey('fit-child'),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [SizedBox(height: childHeight)],
                ),
              ),
            ),
          ),
        ));
        return t.renderObject<RenderReportFit>(find.byKey(const ValueKey('fit')));
      }

      expect((await fit(200)).scale, 1.0);
      // 360 × κλίμακα ≤ 300 → η μεγαλύτερη κλίμακα που χωρά είναι 300 / 360 = 0,8333.
      expect((await fit(360)).scale, closeTo(300 / 360, 0.001));
      final r = t.getRect(find.byKey(const ValueKey('fit-child')));
      expect(r.width, closeTo(500, 0.01), reason: 'όλο το πλάτος (στήθηκε σε 500 ÷ κλίμακα), όχι στενή στήλη');
      expect(r.height, closeTo(300, 0.05));
      // Πολύ ψηλό: μικραίνει όσο χρειάζεται (ποτέ κομμένο), και πάλι σε όλο το πλάτος.
      expect((await fit(1000)).scale, closeTo(0.3, 0.001));
      expect(t.getRect(find.byKey(const ValueKey('fit-child'))).width, closeTo(500, 0.01));
    });

    test('S11-9: ενικός στο «Τι φτάνει»', () {
      expect(filterWarning({'key': 'body_composition', 'state': 'ok', 'count': 1, 'counted': 0, 'ignored': 1}),
          contains('η 1 ζύγιση είναι από άλλη εφαρμογή'));
      expect(filterWarning({'key': 'sleep', 'state': 'ok', 'count': 1, 'counted': 0, 'ignored': 1}), contains('η 1 εγγραφή είναι'));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('Οθόνες', () {
    testWidgets('S10-10: μόνο σημείωση μηνών (χωρίς ανάγνωση): καμία γραμμή που κινείται, η σελίδα ησυχάζει', (t) async {
      final s = HealthStore();
      s.prefs.staleMonths.add('2026-08-15');
      await _pump(t, TrendsPage(store: s, now: DateTime(2026, 11, 13, 10)), size: const Size(400, 3000));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text(staleMonthsNote(['2026-08-15'])), findsOneWidget);
      expect(find.text('Μήνες με παλιό υπολογισμό ύπνου'), findsOneWidget);
      expect(find.textContaining('Φέρνω το ιστορικό'), findsNothing);
    });

    testWidgets('S4-7: ⓘ αναπνοών: και το εύρος και «Με τι το συγκρίνεις» (η σημείωση «ενδεικτική»)', (t) async {
      await _pump(t, const Center(child: InfoButton(K.breath, range: breathRange)), size: const Size(400, 900));
      await t.tap(find.byKey(const ValueKey('info-${K.breath}')));
      await t.pumpAndSettle();
      expect(find.text('Εύρος αναφοράς'), findsOneWidget);
      expect(find.text('Με τι το συγκρίνεις'), findsOneWidget);
      expect(find.textContaining('ενδεικτική'), findsOneWidget);
    });

    testWidgets('U1a-21: στόχοι αφής 48 dp (καρτέλες, «i»)', (t) async {
      await _pump(
        t,
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            SegmentTabs(tabs: const ['Ύπνος', 'Καρδιά', 'Σώμα', 'Τάσεις'], selected: 0, solid: Aigaio.light.healthSolid, onTap: (_) {}),
            const InfoButton(K.weight),
          ]),
        ),
        size: const Size(400, 900),
      );
      expect(t.getSize(find.byKey(const ValueKey('tab-Καρδιά'))).height, greaterThanOrEqualTo(48));
      expect(t.getSize(find.byKey(const ValueKey('info-${K.weight}'))), const Size(48, 48));
    });

    testWidgets('U1b-04 / U1a-3: «Διάρκεια ύπνου» με ολόκληρες λέξεις και διαφορά με μονάδα', (t) async {
      final day = DateTime(2026, 11, 13);
      final s = HealthStore()
        ..history = {
          for (var i = 1; i <= 10; i++) dateKey(_add(day, -i)): {K.sleepMin: 425.0},
          dateKey(day): {K.sleepMin: 392.0},
        };
      await _pump(t, MetricPage(store: s, spec: metricSpecs[K.sleepMin]!, now: DateTime(2026, 11, 13, 10)), size: const Size(400, 2400));
      // συνήθως 425 (7 ώρες 5 λεπτά), χθες 392 → 33 λεπτά λιγότερο.
      expect(find.text('33 λεπτά λιγότερο από ό,τι συνήθως · συνήθως 7 ώρες 5 λεπτά'), findsOneWidget);
      final texts = [for (final w in t.widgetList<Text>(find.byType(Text))) w.data ?? w.textSpan?.toPlainText() ?? ''];
      expect(texts.where((x) => RegExp(r'\d (ω|λ)(\s|$)').hasMatch(x)), isEmpty, reason: 'ποτέ «ω/λ»');
      expect(find.text('Άξονας: ώρες:λεπτά'), findsOneWidget);
    });

    testWidgets('U1b-11: στατιστικά με μονάδα· με μία τιμή χωρίς «Μέσος όρος»', (t) async {
      final day = DateTime(2026, 11, 13);
      final three = HealthStore()
        ..history = {
          dateKey(_add(day, -2)): {K.sleepHr: 58.0},
          dateKey(_add(day, -1)): {K.sleepHr: 60.0},
          dateKey(day): {K.sleepHr: 62.0},
        };
      await _pump(t, MetricPage(store: three, spec: metricSpecs[K.sleepHr]!, now: DateTime(2026, 11, 13, 10)));
      String row(String label) => t.widgetList<InfoRow>(find.byType(InfoRow)).firstWhere((r) => r.label == label).value;
      expect(row('Μέσος όρος'), '60 bpm');
      expect(row('Χαμηλότερη · υψηλότερη'), '58 · 62 bpm');
      final one = HealthStore()..history = {dateKey(day): {K.sleepHr: 62.0}};
      await _pump(t, MetricPage(store: one, spec: metricSpecs[K.sleepHr]!, now: DateTime(2026, 11, 13, 10)));
      expect(t.widgetList<InfoRow>(find.byType(InfoRow)).where((r) => r.label == 'Μέσος όρος'), isEmpty);
    });

    testWidgets('U1b-05 / U1b-17: εβδομάδα: κουτιά ίδιου ύψους, μονό σε όλο το πλάτος· «—» χωρίς «πριν» με λίγες μέρες', (t) async {
      final sunday = DateTime(2026, 11, 8);
      final monday = _add(sunday, -6);
      final few = TrendResult(
        def: metricDef(K.sleepMin)!,
        status: TrendStatus.insufficient,
        current: 250,
        previous: 458,
        nCurrent: 1,
        nPrevious: 25,
        needed: 5,
        z: 0,
        points: const [],
        currentFrom: monday,
        previousFrom: _add(monday, -28),
        previousEnd: _add(monday, -1),
        end: sunday,
      );
      final review = WeekReview(
        monday: monday,
        sunday: sunday,
        items: [few],
        bestNight: _add(sunday, -2),
        bestNightScore: 84,
        mostSteps: _add(sunday, -3),
        mostStepsValue: 9100,
        activeTotal: 125,
        activeDays: 7,
      );
      await _pump(t, SingleChildScrollView(child: WeekCard(review: review)));
      Rect tile(String label) => t.getRect(find.ancestor(of: find.text(label), matching: find.byType(Container)).first);
      final a = tile('Καλύτερη βαθμολογία ύπνου (εκτίμηση)');
      final b = tile('Περισσότερα βήματα');
      final c = tile('Ενεργός χρόνος, σύνολο');
      expect(a.height, closeTo(b.height, 0.01));
      expect(c.width, greaterThan(a.width * 1.5));
      expect(find.text('—'), findsOneWidget);
      expect(find.textContaining('πριν 7 ώρες'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('S12-13: όρια ακριβώς στο όριο', () {
    final day = DateTime(2026, 11, 13);
    Map<String, Map<String, double>> base(int n, {double hr = 63, double temp = 34.4, double energy = 65}) => {
          for (var i = 1; i <= n; i++) dateKey(_add(day, -i)): {K.sleepHr: 60.0, K.skinTemp: 34.0, K.energy: 75.0},
          dateKey(day): {K.sleepHr: hr, K.skinTemp: temp, K.energy: energy},
        };
    bool off(UnusualResult r, String key) => r.signals.firstWhere((s) => s.rule.key == key).off;

    test('«Εκτός συνηθισμένου»: +3 bpm, +0,4 °C, −10 πιάνουν· +2, +0,3, −9 όχι', () {
      final hit = checkUnusual(base(28), day, checkPrevious: false);
      expect([off(hit, K.sleepHr), off(hit, K.skinTemp), off(hit, K.energy)], [true, true, true]);
      expect(hit.show, isTrue);
      final miss = checkUnusual(base(28, hr: 62, temp: 34.3, energy: 66), day, checkPrevious: false);
      expect([off(miss, K.sleepHr), off(miss, K.skinTemp), off(miss, K.energy)], [false, false, false]);
    });

    test('«Εκτός συνηθισμένου»: 13 μέρες βάσης → κανένα σήμα· 14 → σήμα', () {
      expect(checkUnusual(base(13), day, checkPrevious: false).signals, isEmpty);
      expect(checkUnusual(base(14), day, checkPrevious: false).signals.length, 3);
    });

    group('παλμοί μέσα στη μέρα', () {
      int ms(DateTime t) => t.millisecondsSinceEpoch;
      DateTime at(int h, int m) => DateTime(day.year, day.month, day.day, h, m);
      Dashboard dash(List<(DateTime, DateTime, num, int)> chunks) {
        final heart = <List<num>>[];
        final steps = <List<num>>[];
        for (final (from, to, hr, perMinute) in chunks) {
          for (var t = from; t.isBefore(to); t = t.add(const Duration(minutes: 4))) {
            heart.add([ms(t), ms(t.add(const Duration(minutes: 4))), hr, hr - 3, hr + 3]);
          }
          if (perMinute > 0) {
            for (var t = from; t.isBefore(to); t = t.add(const Duration(minutes: 1))) {
              steps.add([ms(t), perMinute]);
            }
          }
        }
        return Dashboard.fromJson({
          'ok': true,
          'readAt': ms(at(20, 0)),
          'granted': 17,
          'total': 17,
          'sleep': <Object>[],
          'heart': heart,
          'stepsMin': steps,
          'exercise': <Object>[],
        });
      }

      test('βήματα το λεπτό 59 / 60 / 99 / 100 → λίγη κίνηση / περπάτημα / περπάτημα / γρήγορο', () {
        final h = dash([
          (at(9, 0), at(9, 40), 70, 59),
          (at(10, 0), at(10, 40), 80, 60),
          (at(11, 0), at(11, 40), 90, 99),
          (at(12, 0), at(12, 40), 100, 100),
        ]).heartForDay(day)!;
        expect(h.bands[HeartBand.light]!.minutes, closeTo(40, 0.01));
        expect(h.bands[HeartBand.light]!.value, 70);
        expect(h.bands[HeartBand.walk]!.minutes, closeTo(80, 0.01));
        expect(h.bands[HeartBand.brisk]!.minutes, closeTo(40, 0.01));
        expect(h.bands[HeartBand.brisk]!.value, 100);
      });

      test('28 λεπτά → χωρίς τιμή· 32 λεπτά → τιμή (όριο 30)', () {
        expect(dash([(at(9, 0), at(9, 28), 65, 0)]).heartForDay(day)!.bands[HeartBand.still]!.value, isNull);
        expect(dash([(at(9, 0), at(9, 32), 65, 0)]).heartForDay(day)!.bands[HeartBand.still]!.value, 65);
      });
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('S12-05: αλλαγή ώρας 28/3/2027 (TZ=Europe/Athens όπως το CI)', () {
    setUp(() {
      // Αν οι δοκιμές τρέξουν σε ζώνη χωρίς αλλαγή ώρας, να αποτύχουν καθαρά αντί να περάσουν χωρίς να ελέγξουν τίποτα.
      expect(DateTime(2027, 3, 29).timeZoneOffset - DateTime(2027, 3, 27).timeZoneOffset, const Duration(hours: 1),
          reason: 'οι δοκιμές αυτές θέλουν TZ=Europe/Athens');
    });

    test('Τάσεις: 30 μέρες πάνω από την αλλαγή = 30 τιμές, σωστά άκρα', () {
      final today = DateTime(2027, 4, 10);
      final h = <String, Map<String, double>>{
        for (var i = 0; i < 120; i++) dateKey(_add(today, -i)): {K.sleepHr: 60.0 + (i % 3)},
      };
      final t = computeTrend(metricDef(K.sleepHr)!, h, today, TrendPeriod.month);
      expect(t.currentFrom, DateTime(2027, 3, 12));
      expect(t.previousEnd, DateTime(2027, 3, 11));
      expect(t.nCurrent, 30);
      expect(t.nPrevious, 30);
      final across = [for (var i = 0; i < 10; i++) DateTime(2027, 3, 24 + i)];
      final winter = [for (var i = 0; i < 10; i++) DateTime(2027, 1, 10 + i)];
      expect(effectiveN(across, 0.6), closeTo(effectiveN(winter, 0.6), 1e-12));
      expect(daysBetween(DateTime(2027, 3, 27), DateTime(2027, 3, 29)), 2);
    });

    test('HRV 7 νυχτών: όλες οι νύχτες πάνω από την αλλαγή', () {
      final today = DateTime(2027, 3, 31);
      final h = <String, Map<String, double>>{
        for (var i = 0; i < 80; i++) dateKey(_add(today, -i)): {'o.hrv': i.isEven ? 40.0 : 44.0},
      };
      final tr = hrvTrend(h, SourcePlan([SourceEra(Source.oura, DateTime(2026, 6, 1))]), today)!;
      expect((tr.weekNights, tr.baseNights), (7, 60));
    });

    test('«Εκτός συνηθισμένου»: 28 μέρες βάσης πάνω από την αλλαγή', () {
      final day = DateTime(2027, 4, 5);
      final h = <String, Map<String, double>>{
        for (var i = 0; i <= 28; i++) dateKey(_add(day, -i)): {K.sleepHr: 60.0},
      };
      expect(checkUnusual(h, day, checkPrevious: false).signals.single.baselineCount, 28);
    });

    test('Σώμα: ξένη ζύγιση τη μέρα της αλλαγής ώρας', () {
      final body = <BodyMeasurement>[
        for (var d = 20; d <= 31; d++) _m(DateTime(2027, 3, d, 8), d == 28 ? 30.0 : 90.0),
      ];
      final foreign = foreignBody(body);
      expect(foreign.single.time, DateTime(2027, 3, 28, 8));
      expect(countedBody(body).length, 11);
    });

    test('Εβδομάδα 22–28/3/2027: Δευτέρα ως Κυριακή, 7 νύχτες', () {
      final sunday = DateTime(2027, 3, 28);
      final h = <String, Map<String, double>>{
        for (var i = 0; i < 40; i++) dateKey(_add(sunday, -i)): {K.sleepHr: 60.0},
      };
      final r = buildWeekReview(h, sunday, DateTime(2027, 3, 29, 9));
      expect(r.monday, DateTime(2027, 3, 22));
      expect(r.items.firstWhere((x) => x.def.key == K.sleepHr).nCurrent, 7);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  test('S4-10: πολύ χαμηλή τιμή την προηγούμενη νύχτα, σήμερα χωρίς τιμή → η σημείωση με την ημερομηνία', () {
    final last = DateTime(2026, 11, 12);
    final g = oxygenGuidance({last: 78.0}, last, today: DateTime(2026, 11, 13));
    expect(g.messages.single, contains('την τελευταία νύχτα με μέτρηση'));
  });

  test('U1b-20: «φαγητό αργά το βράδυ», όχι «αργό φαγητό»', () {
    expect(metricInfos[K.sleepHr]!.shows, isNot(contains('αργό ')));
  });
}
