// Round 8 · f7 («Ύπνος, καρδιά, Τάσεις, σελίδες υγείας»): R8-A5-1 … R8-A5-6, R8-U4-1, U4-2, U4-3, U4-6, U4-7, U4-8,
// U4-9, U4-11, U4-12, U4 Β2, U4 Β3. Οι αναμενόμενες τιμές βγήκαν από τον γραμμένο κανόνα (με το χέρι ή με python στο
// /home/claude/scratch/f7r8/), όχι από τη νέα υλοποίηση. Όλες οι τιμές είναι επινοημένες.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/oura/oura_model.dart';
import 'package:ygeia_forma/oura/oura_view.dart';
import 'package:ygeia_forma/pages/info_sheet.dart';
import 'package:ygeia_forma/pages/metric_page.dart';
import 'package:ygeia_forma/pages/oxygen_widgets.dart';
import 'package:ygeia_forma/pages/sleep.dart';
import 'package:ygeia_forma/pages/trends.dart';
import 'package:ygeia_forma/pages/week_card.dart';
import 'package:ygeia_forma/reference.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/trends.dart';
import 'package:ygeia_forma/weekly.dart';
import 'package:ygeia_forma/widgets.dart';

import 'sample_data.dart';

// ---------------------------------------------------------------------------
// Βοηθοί
// ---------------------------------------------------------------------------

DateTime _d(int y, int m, int day) => DateTime(y, m, day);
DateTime _add(DateTime x, int n) => DateTime(x.year, x.month, x.day + n);

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 2400), double textScale = 1.0}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(body: w),
  ));
  await t.pumpAndSettle();
}

String _row(WidgetTester t, String label) =>
    t.widgetList<InfoRow>(find.byType(InfoRow)).firstWhere((r) => r.label == label).value;

bool _isWatch(double v) => v >= 300 && v < 400;
bool _isOura(double v) => v >= 700 && v < 800;

/// Ιστορικό με τιμές ρολογιού (300–399) ΚΑΙ Oura (700–799) τις ίδιες μέρες: αν κάποιος υπολογισμός πάρει έστω μία τιμή
/// από τη λάθος πηγή, βγαίνει έξω από το εύρος της σωστής (ίδια ιδέα με το sources_test).
Map<String, Map<String, double>> _dual(DateTime from, DateTime to) {
  final h = <String, Map<String, double>>{};
  var i = 0;
  for (var x = from; !x.isAfter(to); x = _add(x, 1), i++) {
    final w = 300.0 + (i * 7) % 99;
    final o = 700.0 + (i * 11) % 99;
    h[dateKey(x)] = {
      for (final k in ouraKeys.keys)
        if (SourcePlan.storageKey(k, Source.watch) != null) k: w,
      for (final e in ouraKeys.entries) e.value: o,
      K.spo2Avg: w,
      K.spo2Min: w,
      K.steps: w,
    };
  }
  return h;
}

/// Νύχτα του ρολογιού με λεπτά φάσεων (μόνο ό,τι χρειάζεται ο μέσος όρος φάσεων).
Night _stagedNight(DateTime date, {required int deep, required int light, required int rem, required int awake, bool partial = false}) {
  final n = Night(date)
    ..staged = true
    ..partial = partial;
  n.stageMinutes.addAll({'DEEP': deep, 'LIGHT': light, 'REM': rem, 'AWAKE': awake});
  return n;
}

TrendResult _trend(String key, {required double previous, required double current, Source source = Source.watch}) {
  final end = _d(2026, 11, 14);
  return TrendResult(
    def: metricDef(key)!,
    status: TrendStatus.up,
    current: current,
    previous: previous,
    nCurrent: 30,
    nPrevious: 30,
    needed: 20,
    z: 5,
    points: const [],
    currentFrom: _add(end, -29),
    previousFrom: _add(end, -59),
    previousEnd: _add(end, -30),
    end: end,
    source: source,
  );
}

/// Μία περίοδος ύπνου της Oura «sleep» 20:00–21:00 της 13/11, με ημερομηνία 14/11 (βραδινός υπνάκος, καμία νύχτα).
OuraNight _eveningNapOnly() => parseOura(
      sleep: [
        {
          'id': 'nap-14',
          'day': '2026-11-14',
          'type': 'sleep',
          'bedtime_start': DateTime(2026, 11, 13, 20).toUtc().toIso8601String(),
          'bedtime_end': DateTime(2026, 11, 13, 21).toUtc().toIso8601String(),
          'time_in_bed': 3600,
          'total_sleep_duration': 3300,
        },
      ],
      dailySleep: const [],
      readiness: const [],
    ).nights.single;

void main() {
  // Τα πλάτη μετριούνται με το Inter της εφαρμογής (όχι με τη γραμματοσειρά δοκιμών), όπως στο r7_f7.
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
  });

  // ------------------------------------------------------------------ R8-A5-1
  group('R8-A5-1: δύο αλλαγές πηγής μέσα στο διάστημα των Τάσεων (ρολόι → Oura 1/12 → ρολόι 27/12)', () {
    final x = _d(2026, 12, 1);
    final y = _d(2026, 12, 27);
    final plan = SourcePlan.samsungOnly.withEra(Source.oura, x).withEra(Source.watch, y);
    final today = _d(2027, 1, 15);
    final history = _dual(_d(2026, 6, 1), _d(2027, 4, 30));

    test('lastChangeWithin: η τελευταία αλλαγή (27/12)· το changeWithin μένει η πρώτη (1/12)', () {
      expect(plan.changeDates(K.sleepMin), [x, y]);
      expect(plan.changeWithin(K.sleepMin, _d(2026, 11, 1), today), x);
      expect(plan.lastChangeWithin(K.sleepMin, _d(2026, 11, 1), today), y);
      expect(plan.lastChangeWithin(K.sleepMin, _d(2026, 11, 1), _d(2026, 12, 26)), x);
      expect(plan.lastChangeWithin(K.sleepMin, y, today), isNull, reason: 'το (after, until] δεν περιέχει το after');
    });

    test('«30 μέρες» στις 15/1: τιμή, γράφημα και «Αλλαγή πηγής 27 Δεκ» μόνο από το ρολόι (python: 20 νύχτες)', () {
      final r = computeTrend(metricDef(K.sleepMin)!, history, today, TrendPeriod.month, plan: plan);
      expect(r.status, TrendStatus.sourceChange);
      // Πριν: 1/12, με 26 νύχτες Oura και 20 ρολογιού στο ίδιο γράφημα και «από το Galaxy Watch» από 1/12.
      expect(r.changedOn, y);
      expect(r.source, Source.watch);
      expect(r.points.length, 20);
      expect(r.points.first.$1, y);
      expect(r.points.every((p) => _isWatch(p.$2)), isTrue);
      expect(r.nCurrent, 20);
      expect(_isWatch(r.current!), isTrue);
      expect(r.shownFrom, y);
    });

    test('κάθε περίοδος, κάθε 3 μέρες: κάθε γραμμή από ΜΙΑ πηγή· η αλλαγή είναι η τελευταία μέσα στο διάστημα', () {
      for (var t = _add(x, -3); !t.isAfter(_add(y, 95)); t = _add(t, 3)) {
        for (final period in TrendPeriod.values) {
          for (final r in computeAllTrends(history, t, period, plan: plan)) {
            final why = '${r.def.key} ${dateKey(t)} $period';
            final vals = [for (final p in r.points) p.$2];
            final allWatch = vals.every(_isWatch);
            final allOura = vals.every(_isOura);
            expect(allWatch || allOura, isTrue, reason: '$why: δύο πηγές στο ίδιο γράφημα');
            if (r.current != null && vals.isNotEmpty) {
              expect(allWatch ? _isWatch(r.current!) : _isOura(r.current!), isTrue, reason: why);
            }
            if (r.status == TrendStatus.sourceChange) {
              final from = r.previousFrom.isBefore(r.currentFrom) ? r.previousFrom : r.currentFrom;
              final inside = [for (final c in plan.changeDates(r.def.key)) if (c.isAfter(from) && !c.isAfter(r.end)) c];
              expect(inside, isNotEmpty, reason: why);
              expect(r.changedOn, inside.last, reason: why);
              expect(r.points.every((p) => !p.$1.isBefore(inside.last)), isTrue, reason: why);
            }
          }
        }
      }
    });

    test('Oura → καμία → Oura: τιμή και γράφημα μόνο από τη δεύτερη εποχή του Oura', () {
      final z = _d(2026, 12, 15);
      final p = SourcePlan.samsungOnly.withEra(Source.oura, x).withEra(Source.none, z).withEra(Source.oura, y);
      final h = <String, Map<String, double>>{
        for (var t = _d(2026, 10, 1); !t.isAfter(today); t = _add(t, 1))
          dateKey(t): {K.sleepMin: 360.0, ouraKeys[K.sleepMin]!: t.isBefore(z) ? 420.0 : 450.0},
      };
      final r = computeTrend(metricDef(K.sleepMin)!, h, today, TrendPeriod.month, plan: p);
      expect(r.status, TrendStatus.sourceChange);
      expect(r.changedOn, y);
      expect(r.source, Source.oura);
      // Πριν: από 1/12, με τις νύχτες 420 του πρώτου δαχτυλιδιού δίπλα στις 450 του δεύτερου.
      expect({for (final e in r.points) e.$2}, {450.0});
      expect(r.current, 450.0);
    });

    test('«Η εβδομάδα σου» 21–27/12: κάθε γραμμή από μία πηγή, η διάρκεια από 27/12', () {
      final w = buildWeekReview(history, y, DateTime(2026, 12, 28, 10), plan: plan);
      for (final r in w.items) {
        final vals = [for (final p in r.points) p.$2];
        expect(vals.every(_isWatch) || vals.every(_isOura), isTrue, reason: r.def.key);
      }
      final sleep = w.items.firstWhere((r) => r.def.key == K.sleepMin);
      expect(sleep.status, TrendStatus.sourceChange);
      expect(sleep.changedOn, y);
      expect(sleep.nCurrent, 1);
    });
  });

  // ------------------------------------------------------------------ R8-A5-2
  group('R8-A5-2: «Φάσεις · μέσος όρος 7 νυχτών» του ρολογιού μόνο από ολόκληρες νύχτες', () {
    test('4 πλήρεις + 1 «μερικώς χωρίς φάσεις»: η μερική δεν μετρά· ελαφρύς 4 ώρες (πριν (4·240 + 120) / 5 = 3 ώρες 36 λεπτά)', () {
      final nights = [
        for (var i = 0; i < 4; i++) _stagedNight(_d(2026, 11, 9 + i), deep: 60, light: 240, rem: 90, awake: 20),
        _stagedNight(_d(2026, 11, 13), deep: 50, light: 120, rem: 40, awake: 10, partial: true),
      ];
      final used = watchStageNights(nights);
      expect(used.length, 4);
      expect(used.any((n) => n.partial), isFalse);
      int avg(String k) => (used.fold<int>(0, (s, n) => s + n.stageMinutes[k]!) / used.length).round();
      expect(hoursMinutes(avg('LIGHT')), '4 ώρες');
      expect(hoursMinutes(avg('REM')), '1 ώρα 30 λεπτά');
      expect(stagesFromText(used.length), 'από 4 νύχτες');
    });

    test('3 πλήρεις + 2 μερικές: 3 νύχτες, λιγότερες από τις 4 που χρειάζονται', () {
      final nights = [
        for (var i = 0; i < 3; i++) _stagedNight(_d(2026, 11, 9 + i), deep: 60, light: 240, rem: 90, awake: 20),
        for (var i = 0; i < 2; i++)
          _stagedNight(_d(2026, 11, 12 + i), deep: 50, light: 120, rem: 40, awake: 10, partial: true),
      ];
      expect(watchStageNights(nights).length, 3);
      expect(watchStageNights(nights).length, lessThan(minNightsForAverage));
    });
  });

  // ------------------------------------------------------------------ R8-A5-3
  testWidgets('R8-A5-3: «Η εβδομάδα σου» με Oura από την Κυριακή: «—», όχι μία νύχτα ως «μεσαία τιμή της εβδομάδας»',
      (t) async {
    // Σύνδεση Σάββατο 21/11 «από απόψε» → Oura από Κυριακή 22/11· η κάρτα τη Δευτέρα 23/11.
    final sunday = _d(2026, 11, 22);
    final plan = SourcePlan.samsungOnly.withEra(Source.oura, sunday);
    final h = <String, Map<String, double>>{
      for (var i = 0; i < 60; i++) dateKey(_add(sunday, -i)): {K.sleepMin: 400.0 + (i % 3) * 10},
    };
    h[dateKey(sunday)]![ouraKeys[K.sleepMin]!] = 436.0;
    final w = buildWeekReview(h, sunday, DateTime(2026, 11, 23, 10), plan: plan);
    final sleep = w.items.firstWhere((r) => r.def.key == K.sleepMin);
    expect(sleep.status, TrendStatus.sourceChange);
    expect(sleep.nCurrent, 1);
    expect(sleep.needed, 5);
    expect(sleep.current, 436.0);
    await _pump(t, SingleChildScrollView(child: WeekCard(review: w)));
    // Πριν: «7 ώρες 16 λεπτά» (η μία νύχτα του Oura) κάτω από «Μεσαία τιμή της εβδομάδας». Round 11 (R11-C2-1): η τιμή
    // γράφεται πλέον με αδιάσπαστο κενό ανάμεσα σε αριθμό και μονάδα (unitsGlued)· και οι δύο μορφές δεν πρέπει να φαίνονται.
    expect(find.text('7 ώρες 16 λεπτά'), findsNothing);
    expect(find.text('7\u00A0ώρες 16\u00A0λεπτά'), findsNothing);
    expect(find.text('—'), findsOneWidget);
  });

  // ------------------------------------------------------------------ R8-A5-4
  test('R8-A5-4: νύχτα σε κομμάτια: «Μέσα στα κομμάτια», όχι «Από τον ύπνο ως το ξύπνημα»', () {
    final day = _d(2026, 11, 13);
    final split = Night(day)
      ..parts.addAll([
        SleepRecord(DateTime(2026, 11, 13, 1, 20), DateTime(2026, 11, 13, 3, 0), 95, null, const []),
        SleepRecord(DateTime(2026, 11, 13, 4, 35), DateTime(2026, 11, 13, 8, 40), 240, null, const []),
      ]);
    expect(spanLabel(split), 'Μέσα στα κομμάτια (με τα ξυπνήματα)');
    final one = Night(day)
      ..parts.add(SleepRecord(DateTime(2026, 11, 13, 0, 30), DateTime(2026, 11, 13, 7, 30), 400, 80, const []));
    expect(spanLabel(one), 'Από τον ύπνο ως το ξύπνημα (με τα ξυπνήματα)');
  });

  testWidgets('R8-A5-4: Ύπνος του ρολογιού, η χωρισμένη νύχτα του δείγματος (01:20–04:05 και 05:40–08:40)', (t) async {
    final now = DateTime(2026, 11, 13, 10);
    // Το δεύτερο κομμάτι με δικές μου φάσεις, με 4 λεπτά ξύπνιο (όπως στο r7_f7): ο πραγματικός ύπνος είναι σίγουρα
    // λιγότερος από τον χρόνο μέσα στα κομμάτια, άρα η γραμμή φαίνεται.
    final j = sampleDashboardJson(now);
    final last = (j['sleep'] as List).last as Map<String, dynamic>;
    final a = last['start'] as int, b = last['end'] as int;
    const m = 60 * 1000;
    last['stages'] = [
      ['LIGHT', a, a + 60 * m],
      ['AWAKE', a + 60 * m, a + 64 * m],
      ['DEEP', a + 64 * m, a + 94 * m],
      ['LIGHT', a + 94 * m, b],
    ];
    final s = HealthStore()..data = Dashboard.fromJson(j);
    s.history = sampleHistory(now, s.data!);
    expect(s.data!.nights.last.parts.length, 2);
    await _pump(t, SleepPage(store: s, now: now), size: const Size(400, 5000));
    expect(find.text('Μέσα στα κομμάτια (με τα ξυπνήματα)'), findsOneWidget);
    expect(find.text('Από τον ύπνο ως το ξύπνημα (με τα ξυπνήματα)'), findsNothing);
  });

  // ------------------------------------------------------------------ R8-A5-5
  test('R8-A5-5: αναπνοές: «9 στις 10 μετρήσεις νύχτας» (Natarajan 2021), όχι «9 στους 10 χρήστες»', () {
    expect(breathRange.text, 'περίπου 12–19 το λεπτό στον ύπνο (9 στις 10 μετρήσεις νύχτας σε χρήστες Fitbit)');
    final compare = metricInfos[K.breath]!.compare!;
    expect(compare, contains('9 στις 10 μετρήσεις νύχτας'));
    for (final s in [breathRange.text, compare]) {
      expect(s, isNot(contains('9 στους 10')));
    }
    expect([breathRange.low, breathRange.high], [11.8, 19.25]);
  });

  // ------------------------------------------------------------------ R8-A5-6
  group('R8-A5-6: το πρωί, με μόνο βραδινό υπνάκο διαβασμένο: «Περιμένει το Oura», όχι «μόνο υπνάκος»', () {
    final plan = SourcePlan.samsungOnly.withEra(Source.oura, _d(2026, 11, 1));
    final day = _d(2026, 11, 14);

    test('ο υπνάκος 20:00–21:00 είναι «μόνο υπνάκος» (καμία νύχτα)', () {
      final nap = _eveningNapOnly();
      expect(nap.main, isNull);
      expect(nap.onlyNap, isTrue);
    });

    test('07:15 και 11:59 → «Περιμένει το Oura»· 12:00 και 13:00 → «Μόνο υπνάκος»', () {
      final nap = _eveningNapOnly();
      EmptyNight? at(DateTime now) =>
          emptyNightReason(plan: plan, day: day, now: now, night: nap, hasTokens: true, synced: now);
      expect(at(DateTime(2026, 11, 14, 7, 15)), EmptyNight.waiting);
      expect(at(DateTime(2026, 11, 14, 11, 59)), EmptyNight.waiting);
      expect(at(DateTime(2026, 11, 14, 12)), EmptyNight.onlyNap);
      expect(at(DateTime(2026, 11, 14, 13)), EmptyNight.onlyNap);
    });

    test('παλιότερη μέρα με μόνο υπνάκο: «Μόνο υπνάκος» και το πρωί', () {
      final now = DateTime(2026, 11, 14, 7, 15);
      expect(
          emptyNightReason(plan: plan, day: _d(2026, 11, 13), now: now, night: _eveningNapOnly(), hasTokens: true, synced: now),
          EmptyNight.onlyNap);
    });
  });

  // ------------------------------------------------------------------ R8-U4-1
  testWidgets('R8-U4-1: 6 νύχτες στις 7 μέρες, όλες με βαθμολογία: «Μέση βαθμολογία 7 νυχτών (από 6 νύχτες)»', (t) async {
    final now = DateTime(2026, 11, 13, 10);
    final j = sampleDashboardJson(now);
    // Το δείγμα: μία εγγραφή ανά νύχτα (30 … 2 μέρες πριν, δείκτες 0–28) και η τελευταία νύχτα σε δύο κομμάτια (29, 30).
    // Βγαίνουν η χωρισμένη (χωρίς βαθμολογία) και η νύχτα 10/11 (δείκτης 26): μένουν 6/11–12/11 χωρίς την 10/11.
    final sleep = j['sleep'] as List;
    sleep.removeRange(sleep.length - 2, sleep.length);
    sleep.removeAt(26);
    final s = HealthStore()..data = Dashboard.fromJson(j);
    s.history = sampleHistory(now, s.data!);
    await _pump(t, SleepPage(store: s, now: now), size: const Size(400, 5000));
    // Πριν: «Μέση βαθμολογία 7 νυχτών» (6 == 6 νύχτες της εβδομάδας), δίπλα στο «Μέσος όρος 7 νυχτών (από 6 νύχτες)».
    expect(find.text('Μέση βαθμολογία 7 νυχτών (από 6 νύχτες)'), findsOneWidget);
    expect(find.text('Μέσος όρος 7 νυχτών (από 6 νύχτες)'), findsOneWidget);
    // Και η κάρτα φάσεων λέει από πόσες νύχτες.
    expect(find.descendant(of: find.byKey(const ValueKey('watch-stages')), matching: find.text('από 6 νύχτες')), findsOneWidget);
  });

  test('R8-U4-1: «από N νύχτες» μόνο κάτω από 7', () {
    expect(stagesFromText(7), isNull);
    expect(stagesFromText(5), 'από 5 νύχτες');
    expect(stagesFromText(1), 'από 1 νύχτα');
  });

  // ------------------------------------------------------------------ R8-U4-2
  group('R8-U4-2: σελίδα «Θερμοκρασία δέρματος» με ύπνο από το ρολόι: μόνο απόκλιση, ποτέ βαθμοί', () {
    final day = _d(2026, 11, 13);
    final now = DateTime(2026, 11, 13, 10);

    testWidgets('14 νύχτες 33,4 και απόψε 33,6: «+0,2», οι τιμές και τα στατιστικά ως απόκλιση', (t) async {
      final s = HealthStore()
        ..history = {
          for (var i = 1; i <= 14; i++) dateKey(_add(day, -i)): {K.skinTemp: 33.4},
          dateKey(day): {K.skinTemp: 33.6},
        };
      await _pump(t, MetricPage(store: s, spec: metricSpecs[K.skinTemp]!, now: now));
      expect(t.widget<BigValue>(find.byType(BigValue)).value, '+0,2');
      expect(find.text(wristDeviationText), findsOneWidget);
      expect(find.text(wristChartNote), findsOneWidget);
      // 14 × 0 και +0,2: μέσος όρος 0,013 → «0»· χαμηλότερη 0, υψηλότερη +0,2.
      expect(_row(t, 'Μέσος όρος'), '0 °C');
      expect(_row(t, 'Χαμηλότερη ·\u00A0υψηλότερη'), '0 ·\u00A0+0,2 °C');
      expect(_row(t, shortDayDate(day)), '+0,2 °C');
      expect(find.textContaining('33,'), findsNothing);
    });

    testWidgets('λιγότερες από 7 προηγούμενες νύχτες: «Μαθαίνει το συνηθισμένο σου», καμία τιμή', (t) async {
      final s = HealthStore()
        ..history = {
          for (var i = 1; i <= 5; i++) dateKey(_add(day, -i)): {K.skinTemp: 33.4},
          dateKey(day): {K.skinTemp: 33.6},
        };
      await _pump(t, MetricPage(store: s, spec: metricSpecs[K.skinTemp]!, now: now));
      expect(find.text(wristLearningText), findsOneWidget);
      expect(t.widget<BigValue>(find.byType(BigValue)).value, '—');
      expect(find.textContaining('33,'), findsNothing);
    });

    test('το ⓘ λέει «δάχτυλο (Oura) ή καρπό (ρολόι)»', () {
      expect(metricInfos[K.skinTemp]!.what, contains('στον καρπό (ρολόι)'));
    });
  });

  // ------------------------------------------------------------------ R8-U4-3
  test('R8-U4-3: «Τι άλλαξε»: ο αριθμός μένει με τη μονάδα του', () {
    expect(changeRowText(_trend(K.sleepMin, previous: 411, current: 452)),
        'από 6 ώρες 51 λεπτά σε 7 ώρες 32 λεπτά');
    expect(changeRowText(_trend(K.sleepHr, previous: 55, current: 62)), 'από 55 bpm σε 62 bpm');
    expect(changeRowText(_trend(K.skinTemp, previous: 33.5, current: 34.0)),
        '+0,5 °C σε σχέση με πριν ·\u00A0όχι θερμοκρασία σώματος');
  });

  // ------------------------------------------------------------------ R8-U4-6
  testWidgets('R8-U4-6: το «i» δεν μεγαλώνει με τα γράμματα (2×): χωρά στον κύκλο των 26 dp', (t) async {
    await _pump(t, const Center(child: InfoButton(K.weight)), textScale: 2);
    final i = find.descendant(of: find.byKey(const ValueKey('info-${K.weight}')), matching: find.text('i'));
    expect(i, findsOneWidget);
    expect(t.widget<Text>(i).textScaler, TextScaler.noScaling);
    // Πριν: 14 × 2 = 28 px μέσα σε κύκλο 26.
    expect(t.getSize(i).height, lessThanOrEqualTo(26));
    expect(t.getSize(find.byKey(const ValueKey('info-${K.weight}'))), const Size(48, 48));
  });

  // ------------------------------------------------------------------ R8-U4-7
  testWidgets('R8-U4-7: «Τι σημαίνει» του οξυγόνου: στόχος αφής 48 dp (πριν 40)', (t) async {
    await _pump(t, const SingleChildScrollView(child: OxygenAbout()));
    expect(t.getSize(find.byKey(const ValueKey('oxygen-about-toggle'))).height, greaterThanOrEqualTo(48));
  });

  // ------------------------------------------------------------------ R8-U4-8
  testWidgets('R8-U4-8: σελίδα μέτρησης μετά από αλλαγή πηγής: «9 από 9 μέρες»· χωρίς αλλαγή «20 από 30 μέρες»', (t) async {
    final now = DateTime(2026, 11, 14, 10);
    final today = _d(2026, 11, 14);
    final change = _d(2026, 11, 6);
    final oura = SourcePlan.storageKey(K.sleepHr, Source.oura)!;
    final s = HealthStore()
      ..history = {
        for (var i = 0; i < 30; i++)
          dateKey(_add(today, -i)): _add(today, -i).isBefore(change) ? {K.sleepHr: 60.0} : {oura: 55.0},
      };
    s.debugSetPlan(SourcePlan.samsungOnly.withEra(Source.oura, change));
    await _pump(t, MetricPage(store: s, spec: metricSpecs[K.sleepHr]!, now: now));
    // 6/11–14/11 = 9 νύχτες του Oura (python/χέρι)· πριν «9 από 30».
    expect(_row(t, 'Μέρες με τιμή'), '9 από 9 μέρες');
    expect(metricShownDays(change, today, 30), 9);
    expect(metricShownDays(null, today, 30), 30);

    final watch = HealthStore()
      ..history = {
        for (var i = 0; i < 30; i++)
          if (i % 3 != 0) dateKey(_add(today, -i)): {K.sleepHr: 58.0},
      };
    await _pump(t, MetricPage(store: watch, spec: metricSpecs[K.sleepHr]!, now: now));
    expect(_row(t, 'Μέρες με τιμή'), '20 από 30 μέρες');
  });

  // ------------------------------------------------------------------ R8-U4-9
  testWidgets('R8-U4-9: γραμμή των Τάσεων: το TalkBack ακούει αν είναι ανοιχτή ή κλειστή', (t) async {
    final handle = t.ensureSemantics();
    final today = _d(2026, 11, 14);
    final s = HealthStore()
      ..history = {
        for (var i = 0; i < 60; i++) dateKey(_add(today, -i)): {K.sleepHr: 58.0 + (i % 3)},
      };
    await _pump(t, TrendsPage(store: s, now: DateTime(2026, 11, 14, 10)), size: const Size(400, 5000));
    final row = find.byKey(const ValueKey('trend-${K.sleepHr}'));
    expect(t.getSemantics(row), containsSemantics(isButton: true, hasExpandedState: true, isExpanded: false));
    await t.ensureVisible(row);
    await t.tap(row);
    await t.pumpAndSettle();
    expect(t.getSemantics(row), containsSemantics(isButton: true, hasExpandedState: true, isExpanded: true));
    handle.dispose();
  });

  // ------------------------------------------------------------------ R8-U4-11
  testWidgets('R8-U4-11: InfoRow με τιμή που τυλίγεται (2×): κάθε γραμμή της τιμής δεξιά, στην άκρη της γραμμής', (t) async {
    const value = 'τουλάχιστον 22 λεπτά';
    await _pump(
      t,
      const Align(alignment: Alignment.topLeft, child: SizedBox(width: 260, child: InfoRow('Ξύπνιος', value))),
      textScale: 2,
    );
    final text = find.descendant(of: find.byType(InfoRow), matching: find.text(value));
    expect(text, findsOneWidget);
    expect(t.widget<Text>(text).textAlign, TextAlign.right);
    final p = t.renderObject<RenderParagraph>(text);
    final boxes = p.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: value.length));
    final rightByLine = <int, double>{};
    for (final b in boxes) {
      final top = b.top.round();
      final r = rightByLine[top];
      rightByLine[top] = r == null || b.right > r ? b.right : r;
    }
    expect(rightByLine.length, greaterThan(1), reason: 'η τιμή τυλίγεται σε δύο γραμμές');
    // Πριν: το τυλιγμένο κείμενο έπιανε όλο το πλάτος και η γραμμή «22 λεπτά» άρχιζε αριστερά.
    for (final r in rightByLine.values) {
      expect(r, greaterThanOrEqualTo(p.size.width - 1.5));
    }
    expect(t.getTopRight(text).dx, closeTo(t.getTopRight(find.byType(InfoRow)).dx, 0.5));
  });

  // ------------------------------------------------------------------ R8-U4-12
  testWidgets('R8-U4-12: σελίδα μέτρησης: «Όπως συνήθως (59 bpm)», όχι «Όπως συνήθως · συνήθως 59 bpm»', (t) async {
    final day = _d(2026, 11, 13);
    final s = HealthStore()
      ..history = {
        for (var i = 0; i <= 14; i++) dateKey(_add(day, -i)): {K.sleepHr: 59.0},
      };
    await _pump(t, MetricPage(store: s, spec: metricSpecs[K.sleepHr]!, now: DateTime(2026, 11, 13, 10)));
    expect(find.text('Όπως συνήθως (59 bpm)'), findsOneWidget);
    expect(find.textContaining('συνήθως ·\u00A0συνήθως'), findsNothing);
  });

  // ------------------------------------------------------------------ U4 Β2
  testWidgets('U4 Β2: «Ίσως ύπνος χωρίς καταγραφή»: κουκκίδα με περίγραμμα στο χρώμα του ύπνου (≥ 3:1 σε κάθε θέμα)', (t) async {
    final th = Aigaio.light;
    await _pump(
      t,
      InfoRow('Ίσως ύπνος χωρίς καταγραφή (δεν μετρά)', '35 λεπτά', dot: th.tint(th.sleep), dotBorder: th.sleep),
    );
    final dot = t
        .widgetList<Container>(find.descendant(of: find.byType(InfoRow), matching: find.byType(Container)))
        .firstWhere((c) => c.decoration is BoxDecoration && (c.decoration! as BoxDecoration).shape == BoxShape.circle);
    final border = (dot.decoration! as BoxDecoration).border! as Border;
    expect(border.top.color, th.sleep);
    for (final x in [...Aigaio.dayThemes, ...Aigaio.nightThemes]) {
      // Το απαλό γέμισμα μόνο του: 1,2–1,5:1 (python, R8-U4)· το περίγραμμα:
      expect(Aigaio.contrast(x.sleep, x.card), greaterThanOrEqualTo(3.0), reason: '${x.id} ${x.dark}');
    }
  });

  // ------------------------------------------------------------------ U4 Β3
  test('U4 Β3: «Ετοιμότητα»: «υπολογίζει η Oura», «κατά την Oura» (η εταιρεία), όπως «εκτίμηση της Oura»', () {
    final e = metricInfos[K.energy]!;
    expect(e.what, contains('υπολογίζει η Oura'));
    expect(e.shows, contains('κατά την Oura'));
    expect(e.up, contains('κατά την Oura'));
    for (final s in [e.what, e.shows, e.up!]) {
      expect(s, isNot(contains('το Oura')));
    }
  });
}
