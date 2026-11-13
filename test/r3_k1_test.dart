// Round 3 · k1 («Η ζύγιση της μέρας» ίδια παντού: R3-C-1, R3-C-2, R3-B-4· φύλακας ζυγίσεων R3-A-1, R3-A-2, R3-A-3·
// κείμενα R3-B-1, R3-B-2, R3-B-3). Κάθε αναμενόμενη τιμή βγήκε από τον ΓΡΑΜΜΕΝΟ κανόνα με python
// (/home/claude/scratch/k1/guard3.py, expected.py, test_values.py, scen_all.py), όχι από τη νέα υλοποίηση.
// Όλες οι τιμές είναι επινοημένες (καμία πραγματική μέτρηση).
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/adaptive.dart' show fastLossSlope;
import 'package:ygeia_forma/adaptive_check.dart' show guardedWeights;
import 'package:ygeia_forma/body_trend.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/format.dart' show shortDayDate, unitsGlued;
import 'package:ygeia_forma/history.dart' show K, bodyRows, dateKey, mergeBody, summarizeDay;
import 'package:ygeia_forma/home_widgets/widget_snapshot.dart' show buildWidgetSnapshot;
import 'package:ygeia_forma/home_widgets/widget_style.dart' show WKind;
import 'package:ygeia_forma/pages/goals_page.dart' show GoalsPage;
import 'package:ygeia_forma/pages/metric_page.dart' show MetricPage, metricSpecs;
import 'package:ygeia_forma/pages/report_page.dart' show ReportPage, reportPendingMark, reportPendingNote;
import 'package:ygeia_forma/pages/today.dart' show TodayPage, pendingWeightNote;
import 'package:ygeia_forma/pages/training/progress_page.dart' show paceDiffText;
import 'package:ygeia_forma/pages/week_card.dart' show WeekCard;
import 'package:ygeia_forma/profile.dart' show Profile;
import 'package:ygeia_forma/report.dart' show buildReport;
import 'package:ygeia_forma/sources.dart' show SourcePlan;
import 'package:ygeia_forma/theme.dart' show buildTheme;
import 'package:ygeia_forma/trends.dart' show TrendPeriod, computeTrend, foreignWeighIn, trendMetrics, uncountedWeighIn, weighInStatus;
import 'package:ygeia_forma/weekly.dart' show buildWeekReview;
import 'package:ygeia_forma/weight_guard.dart';
import 'package:ygeia_forma/widgets.dart' show InfoRow, LineChart, Sparkline, StatCard, TrendPill;

import 'sample_checkin.dart' show checkinGoals;
import 'sample_data.dart' show sampleDashboardJson, sampleHistory;
import 'sample_food.dart' show sampleFoodStore;

const _inbody = 'com.inbody2014.inbody';
final _plan = SourcePlan.samsungOnly;

BodyMeasurement _m(DateTime t, double kg, {double? fat}) => BodyMeasurement(time: t, weight: kg, fatPct: fat, app: _inbody);

/// Δικές σου ζυγίσεις Δε/Τε/Πα 07:30 (λίπος 27,0%).
List<BodyMeasurement> _own(List<(DateTime, double)> w) => [for (final (d, kg) in w) _m(DateTime(d.year, d.month, d.day, 7, 30), kg, fat: 27.0)];

List<BodyMeasurement> _sorted(List<BodyMeasurement> b) => [...b]..sort((x, y) => x.time.compareTo(y.time));

List<BodyMeasurement> _upTo(List<BodyMeasurement> b, DateTime day) => [for (final x in b) if (!x.time.isAfter(DateTime(day.year, day.month, day.day, 23, 59))) x];

Map<String, dynamic> _json(DateTime now, List<BodyMeasurement> rows) => {
      ...sampleDashboardJson(now),
      'body': [
        for (final b in rows)
          {
            'time': b.time.millisecondsSinceEpoch,
            'weight': b.weight,
            if (b.fatPct != null) 'fatPct': b.fatPct,
            'app': _inbody,
          },
      ],
    };

/// Η εφαρμογή όπως διαβάζει: ιστορικό του δείγματος και μετά η κανονική ανάγνωση ([applyRecentRead] → [mergeBody]).
HealthStore _store(DateTime now, List<BodyMeasurement> rows) {
  final s = HealthStore()..data = Dashboard.fromJson(_json(now, rows));
  s.history = sampleHistory(now, s.data!);
  applyRecentRead(s.history, s.data!, plan: _plan);
  return s;
}

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 4000)}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: w)));
  await t.pumpAndSettle();
}

StatCard _weightCard(WidgetTester t) =>
    t.widgetList<StatCard>(find.byType(StatCard)).firstWhere((c) => c.icon == Icons.monitor_weight_rounded);

String _row(WidgetTester t, String label) => t.widget<InfoRow>(find.widgetWithText(InfoRow, label)).value;

Map _widgetWeight(HealthStore s, DateTime now) =>
    (((buildWidgetSnapshot(s, sampleFoodStore(now), now)['kinds'] as Map)[WKind.body] as Map)['m'] as Map)['weight'] as Map;

/// 82 kg από Δευτέρα 16/11, −0,5% την εβδομάδα, Δε/Τε/Πα (python: test_values.py «reg values»).
final _reg = <(DateTime, double)>[
  (DateTime(2026, 11, 16), 82.0),
  (DateTime(2026, 11, 18), 81.9),
  (DateTime(2026, 11, 20), 81.8),
  (DateTime(2026, 11, 23), 81.6),
  (DateTime(2026, 11, 25), 81.5),
  (DateTime(2026, 11, 27), 81.4),
  (DateTime(2026, 11, 30), 81.2),
  (DateTime(2026, 12, 2), 81.1),
  (DateTime(2026, 12, 4), 80.9),
  (DateTime(2026, 12, 7), 80.8),
  (DateTime(2026, 12, 9), 80.7),
  (DateTime(2026, 12, 11), 80.5),
];

List<(DateTime, double)> _regUpTo(DateTime day) => [for (final x in _reg) if (!x.$1.isAfter(day)) x];

void main() {
  // ---------------------------------------------------------------------------------------------------------------
  group('R3-C-1: το παιδί πρώτο (38,0 kg, 08:00), εσύ μετά (80,8 kg, 08:05), Κυριακή 6/12: 80,8 παντού', () {
    final sun = DateTime(2026, 12, 6);
    final child = _m(DateTime(2026, 12, 6, 8), 38.0, fat: 18.0);
    final mine = _m(DateTime(2026, 12, 6, 8, 5), 80.8, fat: 27.0);
    final before = _sorted([..._own(_regUpTo(DateTime(2026, 12, 4))), child, mine]);
    final after = _sorted([...before, _m(DateTime(2026, 12, 7, 7, 30), 80.6, fat: 27.0)]);

    void allConsumers(HealthStore s, DateTime now) {
      final h = s.history;
      // Ιστορικό (Τάσεις, «Η εβδομάδα σου», αναφορά): η δική σου, ολόκληρη (βάρος και λίπος της ίδιας ζύγισης).
      expect(h[dateKey(sun)]![K.weight], 80.8);
      expect(h[dateKey(sun)]![K.fatPct], 27.0);
      expect(bodyRows(s.data!.body)[dateKey(sun)], {K.weight: 80.8, K.fatPct: 27.0, K.inbody: 1.0});
      expect(summarizeDay(s.data!, sun)[K.weight], 80.8);
      expect(foreignWeighIn(h, _plan, sun), isFalse);
      expect(uncountedWeighIn(h, _plan, sun), isFalse);
      // «Η εβδομάδα σου» 30/11–6/12: 81,2 → 80,8 (πριν: «81,2 → 38,0 kg»).
      final week = buildWeekReview(h, sun, now);
      expect(week.weightFirst, (DateTime(2026, 11, 30), 81.2));
      expect(week.weightLast, (sun, 80.8));
      // Τάσεις: η 6/12 με 80,8, καμία 38,0.
      final tr = computeTrend(trendMetrics.firstWhere((m) => m.key == K.weight), h, now, TrendPeriod.month);
      expect(tr.points.where((p) => p.$1 == sun).map((p) => p.$2).toList(), [80.8]);
      expect(tr.points.any((p) => p.$2 == 38.0), isFalse);
      // Αναφορά για γιατρό με τέλος την 6/12: πρώτη γραμμή 6/12 · 80,8 kg · 27,0%.
      final r = buildReport(h, now, end: sun);
      expect((r.weighIns.first.$1, r.weighIns.first.$2, r.weighIns.first.$3), (sun, 80.8, 27.0));
      expect(buildReport(h, now).weighIns.any((w) => w.$2 == 38.0), isFalse);
      expect(buildReport(h, now).foreignWeighIns, 0);
      // Διόρθωση θερμίδων.
      final g = guardedWeights(s.data!.body);
      expect(g.used.where((x) => x.$1 == sun).single, (sun, 80.8));
      expect(g.foreign, isEmpty);
      // Σώμα / Σήμερα / widget: η δική σου ως η ζύγιση της μέρας· το παιδί ξένο.
      expect(countedBody(s.data!.body).where((b) => sameDayOf(b.time, sun)).single.weight, 80.8);
      expect(guardBody(s.data!.body).foreign.single.weight, 38.0);
    }

    testWidgets('πριν από τη ζύγιση της Δευτέρας (Κυριακή 19:00)', (t) async {
      final now = DateTime(2026, 12, 6, 19);
      final s = _store(now, before);
      allConsumers(s, now);
      await _pump(t, TodayPage(store: s, food: sampleFoodStore(now), open: (_, [__]) {}, openSettings: () {}, now: now));
      final card = _weightCard(t);
      expect(card.value, '80,8');
      expect((card.trend! as TrendPill).text, '−0,1 kg από 4/12');
      expect((card.chart! as Sparkline).values, [82.0, 81.9, 81.8, 81.6, 81.5, 81.4, 81.2, 81.1, 80.9, 80.8]);
      expect(card.note, isNull);
      expect(find.textContaining('→ 38,0'), findsNothing);
      if (find.byType(WeekCard).evaluate().isNotEmpty) expect(find.textContaining('81,2 → 80,8 kg'), findsOneWidget);
      final w = _widgetWeight(s, now);
      expect(w['v'], '80,8');
      expect(w['cap'], '${shortDayDate(sun)} · −0,1 kg');
      expect(w['s'], [81.6, 81.5, 81.4, 81.2, 81.1, 80.9, 80.8]);
    });

    testWidgets('μετά τη ζύγιση της Δευτέρας 7/12 (80,6 kg): η 6/12 μένει 80,8 και μετρά', (t) async {
      final now = DateTime(2026, 12, 7, 19);
      final s = _store(now, after);
      allConsumers(s, now);
      expect(guardedWeights(s.data!.body).used.last, (DateTime(2026, 12, 7), 80.6));
      await _pump(t, TodayPage(store: s, food: sampleFoodStore(now), open: (_, [__]) {}, openSettings: () {}, now: now));
      final card = _weightCard(t);
      expect(card.value, '80,6');
      expect((card.trend! as TrendPill).text, '−0,2 kg από 6/12');
      expect((card.chart! as Sparkline).values, [81.9, 81.8, 81.6, 81.5, 81.4, 81.2, 81.1, 80.9, 80.8, 80.6]);
      final w = _widgetWeight(s, now);
      expect(w['v'], '80,6');
      expect(w['cap'], '${shortDayDate(DateTime(2026, 12, 7))} · −0,2 kg');
      expect(w['s'], [81.5, 81.4, 81.2, 81.1, 80.9, 80.8, 80.6]);
    });

    test('παλιές μέρες: γράφεται ξανά ΜΟΝΟ η μέρα με το παιδί πρώτο· τίποτα άλλο της μέρας και καμία άλλη μέρα', () {
      // Ιστορικό όπως το έγραφε ο γύρος 2 (πρώτη ζύγιση της μέρας χωρίς φύλακα), με βήματα, και μια μέρα του 2025.
      final h = <String, Map<String, double>>{
        for (final (d, kg) in _regUpTo(DateTime(2026, 12, 4))) dateKey(d): {K.steps: 5000, K.weight: kg, K.fatPct: 27.0, K.inbody: 1},
        dateKey(sun): {K.steps: 4000, K.weight: 38.0, K.fatPct: 18.0, K.inbody: 1},
        '2025-03-10': {K.weight: 85.0, K.inbody: 1},
      };
      final old = {for (final e in h.entries) e.key: Map<String, double>.of(e.value)};
      expect(mergeBody(h, bodyRows(before)), {dateKey(sun)});
      expect(h[dateKey(sun)], {K.steps: 4000, K.weight: 80.8, K.fatPct: 27.0, K.inbody: 1});
      for (final k in old.keys) {
        if (k != dateKey(sun)) expect(h[k], old[k], reason: k);
      }
      expect(mergeBody(h, bodyRows(before)), isEmpty, reason: 'δεύτερη ανάγνωση: τίποτα');
    });
  });

  test('ίδια μέρα 86 και 90 kg με τις γύρω στα 91: Σώμα, ιστορικό και θερμίδες διαλέγουν την ίδια (90)', () {
    // python (expected.py «[86, 90]»): πριν το Σώμα έπαιρνε 86, η διόρθωση θερμίδων 90.
    final body = _sorted([
      for (var i = 0; i < 30; i += 2) _m(DateTime(2026, 11, 2 + i, 7), 91.0, fat: 27.0),
      _m(DateTime(2026, 11, 17, 7), 86.0, fat: 25.0),
      _m(DateTime(2026, 11, 17, 7, 10), 90.0, fat: 27.0),
    ]);
    final day = DateTime(2026, 11, 17);
    expect(countedBody(body).where((b) => sameDayOf(b.time, day)).single.weight, 90.0);
    expect(guardedWeights(body).used.where((x) => x.$1 == day).single, (day, 90.0));
    expect(bodyRows(body)[dateKey(day)], {K.weight: 90.0, K.fatPct: 27.0, K.inbody: 1.0});
    expect(dayWeighIn(body, day)!.weight, 90.0);
  });

  // ---------------------------------------------------------------------------------------------------------------
  testWidgets('R3-C-2: σελίδα «Βάρος»/«Λίπος» χωρίς τη ζύγιση του παιδιού (Κυριακή 6/12 09:00, ανάμεσα στις δικές σου)', (t) async {
    final now = DateTime(2026, 12, 9, 10);
    final body = _sorted([..._own(_regUpTo(DateTime(2026, 12, 9))), _m(DateTime(2026, 12, 6, 9), 38.0, fat: 18.0)]);
    final h = <String, Map<String, double>>{};
    mergeBody(h, bodyRows(body));
    expect(foreignWeighIn(h, _plan, DateTime(2026, 12, 6)), isTrue);
    final s = HealthStore()..history = h;
    await _pump(t, MetricPage(store: s, spec: metricSpecs[K.weight]!, now: now));
    expect([for (final p in t.widget<LineChart>(find.byType(LineChart)).points) p.$2].contains(38.0), isFalse);
    expect(find.textContaining('38,0'), findsNothing);
    // python: 11 δικές σου τιμές, 80,7–82,0, μέσος όρος 81,3545 → 81,4.
    expect(_row(t, 'Χαμηλότερη · υψηλότερη'), '80,7 · 82,0 kg');
    expect(_row(t, 'Μέσος όρος'), '81,4 kg');
    expect(_row(t, 'Μέρες με τιμή'), '11 από 90');
    await _pump(t, MetricPage(store: s, spec: metricSpecs[K.fatPct]!, now: now));
    expect([for (final p in t.widget<LineChart>(find.byType(LineChart)).points) p.$2], everyElement(27.0));
    expect(find.textContaining('18,0'), findsNothing);
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R3-B-4: η κάρτα «Σήμερα ζύγιση και μέση» δείχνει την ίδια ζύγιση με την κάρτα «Βάρος»', () {
    final fri = DateTime(2026, 12, 4);
    final earlier = _own(_regUpTo(DateTime(2026, 12, 2)));

    testWidgets('07:10 80,9 kg και 19:30 82,1 kg μετά την προπόνηση: 80,9 και στις δύο', (t) async {
      final now = DateTime(2026, 12, 4, 20);
      final s = _store(now, _sorted([...earlier, _m(DateTime(2026, 12, 4, 7, 10), 80.9), _m(DateTime(2026, 12, 4, 19, 30), 82.1)]));
      await _pump(t, TodayPage(store: s, food: sampleFoodStore(now), open: (_, [__]) {}, openSettings: () {}, now: now));
      final weigh = find.byKey(const ValueKey('today-weigh'));
      expect(weigh, findsOneWidget, reason: 'Παρασκευή: μέρα μέσης');
      expect(find.descendant(of: weigh, matching: find.textContaining('80,9 kg')), findsOneWidget);
      expect(find.descendant(of: weigh, matching: find.textContaining('82,1')), findsNothing);
      expect(_weightCard(t).value, '80,9');
      expect(fri.weekday, DateTime.friday);
    });

    testWidgets('07:10 80,9 kg και 07:30 παιδί 34,6 kg: πουθενά 34,6', (t) async {
      final now = DateTime(2026, 12, 4, 9);
      final s = _store(now, _sorted([...earlier, _m(DateTime(2026, 12, 4, 7, 10), 80.9), _m(DateTime(2026, 12, 4, 7, 30), 34.6)]));
      await _pump(t, TodayPage(store: s, food: sampleFoodStore(now), open: (_, [__]) {}, openSettings: () {}, now: now));
      final weigh = find.byKey(const ValueKey('today-weigh'));
      expect(find.descendant(of: weigh, matching: find.textContaining('80,9 kg')), findsOneWidget);
      expect(find.descendant(of: weigh, matching: find.textContaining('34,6')), findsNothing);
      expect(_weightCard(t).value, '80,9');
      expect(_weightCard(t).note, isNull);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R3-A-1: επισκέπτης 6 kg ελαφρύτερος Σάββατο και Κυριακή στο προφίλ σου: δεν κινεί κανέναν αριθμό', () {
    final sun = DateTime(2026, 12, 6);
    final guest = [_m(DateTime(2026, 12, 5, 10), 74.8), _m(DateTime(2026, 12, 6, 10), 75.0)];

    test('Κυριακή (πριν από τη ζύγιση της Δευτέρας): «σε αναμονή», έξω από θερμίδες, γρήγορη απώλεια, εβδομάδα, Τάσεις', () {
      final body = _sorted([..._own(_regUpTo(DateTime(2026, 12, 4))), ...guest]);
      final g = guardedWeights(body);
      expect(g.used.last, (DateTime(2026, 12, 4), 80.9), reason: 'πριν (γύρος 2): (6/12, 75,0)');
      expect(g.foreign, isEmpty);
      expect(guardBody(body).pending.length, 2);
      // Η κάρτα «γρήγορη απώλεια» δεν βγαίνει (−0,5% την εβδομάδα· πριν: −1,45…−3,98 kg την εβδομάδα με τον επισκέπτη).
      expect(fastLossSlope(goals: checkinGoals(), weights: g.used, today: sun), isNull);
      final h = <String, Map<String, double>>{};
      mergeBody(h, bodyRows(body));
      expect(weighInStatus(h, _plan, DateTime(2026, 12, 5)), WeighStatus.pending);
      expect(weighInStatus(h, _plan, sun), WeighStatus.pending);
      final week = buildWeekReview(h, sun, DateTime(2026, 12, 6, 19));
      expect(week.weightLast, (DateTime(2026, 12, 4), 80.9), reason: 'πριν: «81,2 → 75,0 kg»');
      final tr = computeTrend(trendMetrics.firstWhere((m) => m.key == K.weight), h, sun, TrendPeriod.month);
      expect(tr.points.any((p) => p.$2 < 76), isFalse);
      // Φαίνεται ως η τελευταία ζύγιση (σημειωμένη), όχι στα γραφήματα.
      expect(shownBody(body).last.weight, 75.0);
      expect(countedBody(body).last.weight, 80.9);
    });

    test('Δευτέρα 7/12 με τη δική σου ζύγιση (80,8): και οι δύο «ξένες»', () {
      final body = _sorted([..._own(_regUpTo(DateTime(2026, 12, 7))), ...guest]);
      expect(guardedWeights(body).foreign, [(DateTime(2026, 12, 5), 74.8), (sun, 75.0)]);
      expect(guardedWeights(body).used.last, (DateTime(2026, 12, 7), 80.8));
    });

    test('ο επισκέπτης Σάββατο, Κυριακή και Δευτέρα 06:30 (πριν από σένα): η δική σου της Δευτέρας μετρά, όχι «ξένη»', () {
      // python (scen_more.py): πριν (γύρος 2) η δική σου 80,8 έβγαινε «ξένη» και μετρούσε ο επισκέπτης.
      final body = _sorted([..._own(_regUpTo(DateTime(2026, 12, 7))), ...guest, _m(DateTime(2026, 12, 7, 6, 30), 74.9)]);
      final g = guardedWeights(body);
      expect(g.used.last, (DateTime(2026, 12, 7), 80.8));
      expect(g.foreign, [(DateTime(2026, 12, 5), 74.8), (sun, 75.0)]);
      expect([for (final b in guardBody(body).foreign) b.weight], unorderedEquals([74.8, 75.0, 74.9]));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R3-A-2: επιστροφή μετά από αρρώστια, το παιδί πρώτο στη ζυγαριά (45,0 07:00), εσύ μετά (73,4 07:30)', () {
    final pre = <(DateTime, double)>[
      (DateTime(2026, 11, 16), 80.0),
      (DateTime(2026, 11, 18), 79.9),
      (DateTime(2026, 11, 20), 79.8),
      (DateTime(2026, 11, 23), 79.6),
      (DateTime(2026, 11, 25), 79.5),
      (DateTime(2026, 11, 27), 79.4),
      (DateTime(2026, 11, 30), 79.2),
      (DateTime(2026, 12, 2), 79.1),
      (DateTime(2026, 12, 4), 79.0),
    ];
    final mon = DateTime(2026, 12, 14);
    final all = _sorted([
      ..._own(pre),
      _m(DateTime(2026, 12, 14, 7), 45.0, fat: 15.0),
      _m(DateTime(2026, 12, 14, 7, 30), 73.4, fat: 27.0),
      ..._own([(DateTime(2026, 12, 16), 73.2), (DateTime(2026, 12, 18), 73.0)]),
    ]);

    testWidgets('Δευτέρα: η δική σου είναι η ζύγιση της μέρας («σε αναμονή», ποτέ «ξένη»)· το παιδί «ξένο»', (t) async {
      final body = _upTo(all, mon);
      final g = guardBody(body);
      expect(g.foreign.single.weight, 45.0, reason: 'πριν: «ξένη» η δική σου 73,4');
      expect(g.pending.single.weight, 73.4);
      expect(shownBody(body).last.weight, 73.4, reason: 'πριν: 45,0 στη Σήμερα και στο widget');
      expect(countedBody(body).last.weight, 79.0);
      expect(guardedWeights(body).used.last, (DateTime(2026, 12, 4), 79.0));
      expect(bodyRows(body)[dateKey(mon)]![K.weight], 73.4);
      final now = DateTime(2026, 12, 14, 19);
      final s = _store(now, body);
      await _pump(t, TodayPage(store: s, food: sampleFoodStore(now), open: (_, [__]) {}, openSettings: () {}, now: now));
      final card = _weightCard(t);
      expect(card.value, '73,4');
      expect(card.note, pendingWeightNote);
      // Round 4 (m1 · R4-A-4): καμία διαφορά από ζύγιση «σε αναμονή» (πριν: «−5,6 kg από 4/12»).
      expect(card.trend, isNull);
      expect(_widgetWeight(s, now)['v'], '73,4');
    });

    test('Παρασκευή 18/12 (3 μέρες σε 4 μέρες): μετρούν οι δικές σου', () {
      final g = guardedWeights(all);
      expect(g.used.sublist(g.used.length - 3), [(mon, 73.4), (DateTime(2026, 12, 16), 73.2), (DateTime(2026, 12, 18), 73.0)]);
      expect(guardBody(all).foreign.single.weight, 45.0);
      expect(guardBody(all).pending, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R3-A-3: αναφορά για γιατρό: ζύγιση «σε αναμονή» με σημάδι και σημείωση', () {
    final sat = DateTime(2026, 12, 5);
    final body = _sorted([..._own(_regUpTo(DateTime(2026, 12, 4))), _m(DateTime(2026, 12, 5, 10), 45.0, fat: 15.0)]);
    Map<String, Map<String, double>> hist() {
      final h = <String, Map<String, double>>{};
      mergeBody(h, bodyRows(body));
      return h;
    }

    test('ReportData: η γραμμή μένει, σημειωμένη· καμία «ξένη»', () {
      final r = buildReport(hist(), DateTime(2026, 12, 5, 12));
      expect((r.weighIns.first.$1, r.weighIns.first.$2), (sat, 45.0));
      expect(r.pendingWeighIns, {sat});
      expect(r.foreignWeighIns, 0);
      expect(reportPendingNote(0), '');
      expect(reportPendingNote(1), contains('δεν μπήκε στους υπολογισμούς'));
      expect(reportPendingNote(2), contains('δεν μπήκαν στους υπολογισμούς'));
    });

    testWidgets('η σελίδα γράφει «χωρίς επιβεβαίωση» στη γραμμή και τη σημείωση από κάτω', (t) async {
      final now = DateTime(2026, 12, 5, 12);
      final store = HealthStore()
        ..data = Dashboard.fromJson(sampleDashboardJson(now))
        ..history = hist();
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(680, 3600);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: ReportPage(store: store, now: now)));
      await t.pumpAndSettle();
      expect(find.text(reportPendingMark), findsOneWidget);
      final note = t.widget<Text>(find.byKey(const ValueKey('report-weigh-note'))).data!;
      expect(note, endsWith(reportPendingNote(1)));
      expect(note, isNot(contains('άλλου')));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('Φύλακας: οι δικές σου ζυγίσεις', () {
    test('κάθε μέρα ή Δε/Τε/Πα, απώλεια 0–2,5% την εβδομάδα, θόρυβος ±0,6 kg: ποτέ «σε αναμονή», ποτέ «ξένη»', () {
      // python (test_values.py «F8»): 0 στις 1.376.
      const pat = [0, 2, -1, 1, -2, 1, 0, -1, 2, -2, 1, 0];
      var bad = 0, views = 0;
      for (final rate in [0.0, 0.01, 0.015, 0.025]) {
        for (final daily in [true, false]) {
          final s = <(DateTime, double)>[];
          for (var i = 0; i < 120; i++) {
            final d = DateTime(2026, 11, 16 + i);
            if (daily || d.weekday == DateTime.monday || d.weekday == DateTime.wednesday || d.weekday == DateTime.friday) {
              s.add((d, ((80 * (1 - rate * i / 7) + 0.3 * pat[s.length % 12]) * 10).round() / 10));
            }
          }
          for (var k = 0; k < s.length; k++) {
            views++;
            if (weighStatusAt(s.sublist(0, k + 1), k) != WeighStatus.counted) bad++;
            if (weighStatusAt(s, k) != WeighStatus.counted) bad++;
          }
        }
      }
      expect(views, greaterThan(600));
      expect(bad, 0);
    });

    test('Τάσεις: το κομμάτι ±28 μερών δίνει την ίδια κατάσταση με όλο το ιστορικό (και «σε αναμονή»)', () {
      final r = math.Random(31);
      var mismatches = 0;
      final seen = <WeighStatus>{};
      for (var run = 0; run < 40; run++) {
        final s = <(DateTime, double)>[];
        var kg = 80.0;
        for (var i = 0; i < 200; i++) {
          kg += -0.05 + 0.3 * (r.nextDouble() * 2 - 1);
          if (r.nextDouble() < 0.45) {
            final jump = r.nextDouble() < 0.08 ? [0.0, -35.0, 15.0, -6.0, 6.0][r.nextInt(5)] : 0.0;
            s.add((DateTime(2026, 1, 1 + i), ((kg + jump) * 10).round() / 10));
          }
        }
        final h = {for (final (d, w) in s) dateKey(d): {K.weight: w}};
        for (var i = 0; i < s.length; i++) {
          final full = weighStatusAt(s, i);
          seen.add(full);
          if (weighInStatus(h, _plan, s[i].$1) != full) mismatches++;
        }
      }
      expect(mismatches, 0);
      expect(seen.contains(WeighStatus.counted) && seen.contains(WeighStatus.foreign), isTrue, reason: 'η δοκιμή έχει και ξένες');
    });

    test('σταθερές του κανόνα', () {
      expect((weightConfirmDays, weightConfirmSpan), (3, 4));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R3-B-1 / R3-B-2 / R3-B-3: κείμενα που δεν σπάνε', () {
    test('R3-B-1: «πιο γρήγορα 26 δευτερόλεπτα»: ο αριθμός μένει με τη μονάδα του', () {
      expect(unitsGlued(paceDiffText(26)), '26\u00A0δευτερόλεπτα');
      expect(unitsGlued(paceDiffText(65)), '1\u00A0λεπτό 5\u00A0δευτερόλεπτα');
      final src = File('lib/pages/training/progress_page.dart').readAsStringSync();
      expect(src, contains("'πιο αργά'} \${unitsGlued(paceDiffText("));
      expect(src, contains("label: 'Πτώση παλμών στο 1ο\\u00A0λεπτό'"));
    });

    testWidgets('R3-B-3: «β\u2011γλυκάνες» με αδιάσπαστο ενωτικό στη σημείωση της χοληστερίνης', (t) async {
      final s = HealthStore()
        ..setProfile(const Profile(birthYear: 1986, birthMonth: 1, sex: 'm', heightCm: 180))
        ..setGoals(checkinGoals().copyWith(betaPer100: 7, branG: 40));
      await _pump(t, GoalsPage(store: s, now: DateTime(2026, 11, 12, 10)));
      expect(find.textContaining('για 3\u00A0g β\u2011γλυκάνες τη μέρα (EFSA)'), findsOneWidget);
      expect(find.textContaining('β-γλυκάνες τη μέρα (EFSA)'), findsNothing);
    });
  });
}

bool sameDayOf(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
