// Round 4 · m1 (φύλακας ζυγίσεων: R4-A-1 … R4-A-5). Κάθε αναμενόμενη τιμή βγήκε από τον ΓΡΑΜΜΕΝΟ κανόνα με python
// (/home/claude/scratch/m1/guard5.py, expected_r4.py, expected_r4b.py, lightcone.py), όχι από τη νέα υλοποίηση.
// Όλες οι τιμές είναι επινοημένες (καμία πραγματική μέτρηση).
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/adaptive.dart' show fastLossSlope;
import 'package:ygeia_forma/adaptive_check.dart' show dailyWeights, guardedWeights;
import 'package:ygeia_forma/body_trend.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/format.dart' show shortDayDate;
import 'package:ygeia_forma/history.dart' show K, bodyRows, dateKey, mergeBody;
import 'package:ygeia_forma/home_widgets/widget_snapshot.dart' show buildWidgetSnapshot, widgetPendingCap;
import 'package:ygeia_forma/home_widgets/widget_style.dart' show WKind;
import 'package:ygeia_forma/pages/body.dart' show BodyPage, mixedLatestText, pendingLatestText;
import 'package:ygeia_forma/pages/info_sheet.dart' show RangeNote;
import 'package:ygeia_forma/pages/today.dart' show TodayPage, mixedWeightNote, pendingWeightNote;
import 'package:ygeia_forma/profile.dart' show Profile;
import 'package:ygeia_forma/report.dart' show buildReport;
import 'package:ygeia_forma/sources.dart' show SourcePlan;
import 'package:ygeia_forma/theme.dart' show buildTheme;
import 'package:ygeia_forma/trends.dart' show uncountedWeighIn, weighInStatus;
import 'package:ygeia_forma/weekly.dart' show buildWeekReview;
import 'package:ygeia_forma/weight_guard.dart';
import 'package:ygeia_forma/widgets.dart' show InfoRow, Sparkline, StatCard, TrendPill;

import 'sample_checkin.dart' show checkinGoals;
import 'sample_data.dart' show sampleDashboardJson, sampleHistory;
import 'sample_food.dart' show sampleFoodStore;

const _inbody = 'com.inbody2014.inbody';
final _plan = SourcePlan.samsungOnly;

BodyMeasurement _m(DateTime t, double kg, {double? fat}) => BodyMeasurement(time: t, weight: kg, fatPct: fat, app: _inbody);

List<BodyMeasurement> _sorted(List<BodyMeasurement> b) => [...b]..sort((x, y) => x.time.compareTo(y.time));

List<BodyMeasurement> _upTo(List<BodyMeasurement> b, DateTime t) => [for (final x in b) if (!x.time.isAfter(t)) x];

Map<String, Map<String, double>> _hist(List<BodyMeasurement> body) {
  final h = <String, Map<String, double>>{};
  mergeBody(h, bodyRows(body));
  return h;
}

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

Map _widgetBody(HealthStore s, DateTime now) =>
    ((buildWidgetSnapshot(s, sampleFoodStore(now), now)['kinds'] as Map)[WKind.body] as Map)['m'] as Map;

/// Δε/Τε/Πα 07:15 από Δευτέρα 16/11, 82,0 kg, −0,5 kg την εβδομάδα (python expected_r4.py «A own values»).
final _own = <(DateTime, double)>[
  (DateTime(2026, 11, 16), 82.0),
  (DateTime(2026, 11, 18), 81.9),
  (DateTime(2026, 11, 20), 81.7),
  (DateTime(2026, 11, 23), 81.5),
  (DateTime(2026, 11, 25), 81.4),
  (DateTime(2026, 11, 27), 81.2),
  (DateTime(2026, 11, 30), 81.0),
  (DateTime(2026, 12, 2), 80.9),
  (DateTime(2026, 12, 4), 80.7),
  (DateTime(2026, 12, 7), 80.5),
  (DateTime(2026, 12, 9), 80.4),
  (DateTime(2026, 12, 11), 80.2),
  (DateTime(2026, 12, 14), 80.0),
  (DateTime(2026, 12, 16), 79.9),
  (DateTime(2026, 12, 18), 79.7),
  (DateTime(2026, 12, 21), 79.5),
  (DateTime(2026, 12, 23), 79.4),
  (DateTime(2026, 12, 25), 79.2),
];

/// Το σενάριο του R4-A-1: οι δικές σου ζυγίσεις και ένα παιδί (35,0 το Σάββατο, 35,2 την Κυριακή, 09:30) κάθε
/// Σαββατοκύριακο από 28/11. Με [away]: καμία δική σου ζύγιση Δε 7/12 – Κυρ 13/12.
List<BodyMeasurement> _scenario({bool away = false}) {
  final out = <BodyMeasurement>[
    for (final (d, kg) in _own)
      if (!away || d.isBefore(DateTime(2026, 12, 7)) || d.isAfter(DateTime(2026, 12, 13))) _m(DateTime(d.year, d.month, d.day, 7, 15), kg),
  ];
  for (var d = DateTime(2026, 11, 28); d.isBefore(DateTime(2026, 12, 27)); d = DateTime(d.year, d.month, d.day + 1)) {
    if (d.weekday == DateTime.saturday) out.add(_m(DateTime(d.year, d.month, d.day, 9, 30), 35.0));
    if (d.weekday == DateTime.sunday) out.add(_m(DateTime(d.year, d.month, d.day, 9, 30), 35.2));
  }
  return _sorted(out);
}

/// Ο ΙΔΙΟΣ υπολογισμός: η κατάσταση κάθε μέρας στο ιστορικό ([weighInStatus], Τάσεις/εβδομάδα/αναφορά) = του φύλακα
/// ([weighInDays], Σώμα/Σήμερα/widget/θερμίδες).
void _sameEverywhere(List<BodyMeasurement> body) {
  final h = _hist(body);
  for (final g in weighInDays(body)) {
    expect(weighInStatus(h, _plan, g.day), g.status, reason: '${g.day}');
  }
}

void main() {
  // ---------------------------------------------------------------------------------------------------------------
  group('R4-A-1: παιδί κάθε Σαββατοκύριακο στο προφίλ σου', () {
    test('Κυριακή 13/12 20:00: η δική σου Παρασκευή 11/12 (80,2) μετρά παντού· ξένες μόνο οι 35,x', () {
      final body = _upTo(_scenario(), DateTime(2026, 12, 13, 20));
      final g = guardBody(body);
      expect([for (final b in g.foreign) b.weight], everyElement(lessThan(36)), reason: 'πριν: και η δική σου 80,2');
      expect(g.foreign.length, 4);
      expect({for (final b in g.pending) b.time.day}, {12, 13});
      final w = guardedWeights(body);
      expect(w.used.last, (DateTime(2026, 12, 11), 80.2));
      expect(w.foreign, [
        (DateTime(2026, 11, 28), 35.0),
        (DateTime(2026, 11, 29), 35.2),
        (DateTime(2026, 12, 5), 35.0),
        (DateTime(2026, 12, 6), 35.2),
      ]);
      final h = _hist(body);
      expect(uncountedWeighIn(h, _plan, DateTime(2026, 12, 11)), isFalse);
      final week = buildWeekReview(h, DateTime(2026, 12, 13), DateTime(2026, 12, 13, 20));
      expect(week.weightFirst, (DateTime(2026, 12, 7), 80.5));
      expect(week.weightLast, (DateTime(2026, 12, 11), 80.2), reason: 'πριν: «7/12 80,5 → 9/12 80,4»');
      _sameEverywhere(body);
    });

    test('Κυριακή 20/12: τα Σαββατοκύριακα 12–13/12 ξένα με τη Δευτέρα σου· οι δικές σου μετρούν όλες', () {
      final body = _upTo(_scenario(), DateTime(2026, 12, 20, 20));
      final w = guardedWeights(body);
      expect(w.used.last, (DateTime(2026, 12, 18), 79.7));
      expect(w.used.length, 15);
      expect(w.foreign.length, 6);
      expect([for (final b in guardBody(body).pending) b.time.day], unorderedEquals([19, 20]));
      _sameEverywhere(body);
    });

    group('και μία εβδομάδα χωρίς δική σου ζύγιση (7–13/12)', () {
      final all = _scenario(away: true);

      test('Σάββατο 12/12 και Κυριακή 13/12: το παιδί δεν μετρά πουθενά, καμία κάρτα γρήγορης απώλειας', () {
        for (final t in [DateTime(2026, 12, 12, 20), DateTime(2026, 12, 13, 20)]) {
          final body = _upTo(all, t);
          final w = guardedWeights(body);
          expect(w.used.last, (DateTime(2026, 12, 4), 80.7), reason: 'πριν: (12/12, 35,0)');
          expect(w.used.any((x) => x.$2 < 50), isFalse);
          expect(countedBody(body).last.weight, 80.7);
          expect(fastLossSlope(goals: checkinGoals(), weights: w.used, today: DateTime(t.year, t.month, t.day)), isNull,
              reason: 'πριν (R4-A): «−19,5 kg την εβδομάδα», +150 kcal');
          expect(guardBody(body).foreign.length, 2, reason: 'μόνο 28–29/11');
          _sameEverywhere(body);
        }
      });

      test('Δευτέρα 14/12 07:30 (80,0): η δική σου μετρά, τα 4 του παιδιού ξένα', () {
        final body = _upTo(all, DateTime(2026, 12, 14, 7, 30));
        final w = guardedWeights(body);
        expect(w.used.last, (DateTime(2026, 12, 14), 80.0), reason: 'πριν: «σε αναμονή», έλεγχος «implausible»');
        expect(w.foreign.length, 6);
        expect(guardBody(body).pending, isEmpty);
        _sameEverywhere(body);
      });

      test('Σάββατο 19/12: 14, 16, 18/12 μετρούν (πριν: «ξένες», δεύτερη κάρτα +150)', () {
        final body = _upTo(all, DateTime(2026, 12, 19, 20));
        final used = guardedWeights(body).used;
        expect(used.sublist(used.length - 3),
            [(DateTime(2026, 12, 14), 80.0), (DateTime(2026, 12, 16), 79.9), (DateTime(2026, 12, 18), 79.7)]);
        expect([for (final b in guardBody(body).pending) b.weight], [35.0]);
        _sameEverywhere(body);
      });
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R4-A-2: η αρχή· κάποιος άλλος ζυγίζεται πρώτος την ίδια μέρα', () {
    for (final other in [35.0, 95.0]) {
      final rows = _sorted([
        _m(DateTime(2026, 11, 16, 6, 50), other),
        _m(DateTime(2026, 11, 16, 7, 10), 82.0),
        _m(DateTime(2026, 11, 18, 7, 5), 81.6),
        _m(DateTime(2026, 11, 20, 7, 12), 81.4),
        _m(DateTime(2026, 11, 23, 7, 8), 81.5),
        _m(DateTime(2026, 11, 25, 7, 3), 81.0),
      ]);

      test('$other: Δευτέρα 16/11 07:30, καμία άλλη ζύγιση: «σε αναμονή» και οι δύο, τίποτα δεν μετρά, τίποτα ξένο', () {
        final body = _upTo(rows, DateTime(2026, 11, 16, 7, 30));
        final d = weighInDays(body).single;
        expect((d.status, d.unsure), (WeighStatus.pending, true));
        final g = guardBody(body);
        expect(g.foreign, isEmpty, reason: 'πριν: η δική σου 82,0 «ξένη»');
        expect(g.pending.length, 2);
        expect(guardedWeights(body).used, isEmpty, reason: 'πριν: $other μετρούσε');
        expect(dailyWeights(body), isEmpty, reason: 'ο οδηγός στόχων δεν προσυμπληρώνει (πριν: $other kg)');
        expect(mixedDayPending(g.pending, body.last), isTrue);
        final h = _hist(body);
        expect(h[dateKey(DateTime(2026, 11, 16))]![K.weighUnsure], 1);
        expect(weighInStatus(h, _plan, DateTime(2026, 11, 16)), WeighStatus.pending);
      });

      test('$other: Τετάρτη 18/11: η 16/11 είναι η δική σου 82,0 και μετρά· το σημάδι φεύγει', () {
        final h = _hist(_upTo(rows, DateTime(2026, 11, 16, 7, 30)));
        final body = _upTo(rows, DateTime(2026, 11, 18, 7, 30));
        expect(weighInDays(body).first.pick.weight, 82.0);
        expect(weighInDays(body).first.status, WeighStatus.counted);
        expect(guardBody(body).foreign.single.weight, other);
        expect(guardedWeights(body).used, [(DateTime(2026, 11, 16), 82.0), (DateTime(2026, 11, 18), 81.6)]);
        expect(mergeBody(h, bodyRows(body)), contains(dateKey(DateTime(2026, 11, 16))));
        expect(h[dateKey(DateTime(2026, 11, 16))], {K.weight: 82.0, K.inbody: 1}, reason: 'χωρίς το σημάδι [K.weighUnsure]');
        expect(mergeBody(h, bodyRows(body)), isEmpty, reason: 'δεύτερη ανάγνωση: τίποτα');
      });

      test('$other: Κυριακή 22/11: «Η εβδομάδα σου» 16/11 82,0 → 20/11 81,4', () {
        final body = _upTo(rows, DateTime(2026, 11, 22, 19));
        final week = buildWeekReview(_hist(body), DateTime(2026, 11, 22), DateTime(2026, 11, 22, 19));
        expect(week.weightFirst, (DateTime(2026, 11, 16), 82.0), reason: 'πριν: (16/11, $other)');
        expect(week.weightLast, (DateTime(2026, 11, 20), 81.4));
        _sameEverywhere(body);
      });
    }

    testWidgets('Σήμερα και Σώμα, Δευτέρα 16/11: η σημείωση των δύο διαφορετικών ζυγίσεων', (t) async {
      final now = DateTime(2026, 11, 16, 7, 30);
      final s = _store(now, [_m(DateTime(2026, 11, 16, 6, 50), 35.0), _m(DateTime(2026, 11, 16, 7, 10), 82.0)]);
      await _pump(t, TodayPage(store: s, food: sampleFoodStore(now), open: (_, [__]) {}, openSettings: () {}, now: now));
      final card = _weightCard(t);
      expect(card.note, mixedWeightNote);
      expect(card.trend, isNull);
      await _pump(t, BodyPage(store: s, now: now));
      expect(find.text(mixedLatestText), findsOneWidget);
      expect(find.text(pendingLatestText), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R4-A-3: σύντροφος 5 kg ελαφρύτερη', () {
    test('την ίδια Δευτέρα πριν από σένα (06:20 75,9 · 07:15 80,9): μετρά η δική σου, η άλλη ξένη', () {
      final body = _sorted([
        for (final (d, kg) in _own.where((x) => !x.$1.isAfter(DateTime(2026, 12, 4)))) _m(DateTime(d.year, d.month, d.day, 7, 15), kg),
        _m(DateTime(2026, 12, 7, 6, 20), 75.9),
        _m(DateTime(2026, 12, 7, 7, 15), 80.9),
      ]);
      expect(guardedWeights(body).used.last, (DateTime(2026, 12, 7), 80.9));
      expect(guardBody(body).foreign.single.weight, 75.9);
    });

    test('το σχόλιο του φύλακα δεν υπόσχεται πια «97% στα 5 kg»', () {
      final src = File('lib/weight_guard.dart').readAsStringSync();
      expect(src, isNot(contains('στο 97% τα 5 kg')));
      expect(src, contains('δικό του προφίλ στην εφαρμογή InBody'));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R4-A-4: ζύγιση «σε αναμονή» (παιδί 45,0 το Σάββατο 5/12): καμία κρίση, καμία διαφορά', () {
    final now = DateTime(2026, 12, 5, 12);
    final rows = _sorted([
      for (final (d, kg) in _own.where((x) => !x.$1.isAfter(DateTime(2026, 12, 4)))) _m(DateTime(d.year, d.month, d.day, 7, 15), kg, fat: 27.0),
      _m(DateTime(2026, 12, 5, 10), 45.0, fat: 15.0),
    ]);
    HealthStore store() => _store(now, rows)..setProfile(const Profile(birthYear: 1986, birthMonth: 1, sex: 'm', heightCm: 180));

    test('widget: τιμή με «δεν μετρά ακόμα», χωρίς βέλος, εύρος, δείκτη μάζας σώματος· γράφημα μόνο από όσες μετρούν', () {
      expect(guardBody(rows).pending.single.weight, 45.0);
      final m = _widgetBody(store(), now);
      final w = m['weight'] as Map;
      expect(w['v'], '45,0');
      expect(w['cap'], '${shortDayDate(DateTime(2026, 12, 5))} · $widgetPendingCap', reason: 'πριν: «… · −35,7 kg»');
      expect(w['capShort'], widgetPendingCap);
      expect(w.containsKey('d'), isFalse);
      expect(w.containsKey('r'), isFalse, reason: 'πριν: «κάτω από το εύρος»');
      expect(w['s'], [81.7, 81.5, 81.4, 81.2, 81.0, 80.9, 80.7]);
      expect(m.containsKey('bmi'), isFalse);
      expect((m['fatPct'] as Map).containsKey('r'), isFalse);
      expect(widgetPendingCap, 'δεν μετρά ακόμα');
    });

    testWidgets('Σήμερα: η τιμή με τη σημείωση, χωρίς «… kg από …»· Σώμα: χωρίς διαφορά και χωρίς εύρη', (t) async {
      final s = store();
      await _pump(t, TodayPage(store: s, food: sampleFoodStore(now), open: (_, [__]) {}, openSettings: () {}, now: now));
      final card = _weightCard(t);
      expect(card.value, '45,0');
      expect(card.note, pendingWeightNote);
      expect(card.trend, isNull, reason: 'πριν: «−35,7 kg από 4/12»');
      expect((card.chart! as Sparkline).values, [82.0, 81.9, 81.7, 81.5, 81.4, 81.2, 81.0, 80.9, 80.7]);
      await _pump(t, BodyPage(store: s, now: now));
      expect(find.byKey(const ValueKey('body-pending-latest')), findsOneWidget);
      expect(t.widgetList<TrendPill>(find.byType(TrendPill)).where((p) => p.text.contains(' kg από ')), isEmpty);
      expect(t.widgetList<InfoRow>(find.byType(InfoRow)).firstWhere((r) => r.label == 'Βάρος').value, '45,0 kg');
      expect(find.byType(RangeNote), findsNothing);
    });

    test('ζύγιση που μετρά: σύντομη λεζάντα για τη στήλη 1×3 (μόνο η διαφορά)', () {
      final s = _store(DateTime(2026, 12, 4, 12), _upTo(rows, DateTime(2026, 12, 4, 12)));
      final w = _widgetBody(s, DateTime(2026, 12, 4, 12))['weight'] as Map;
      expect(w['cap'], '${shortDayDate(DateTime(2026, 12, 4))} · −0,2 kg');
      expect(w['capShort'], '−0,2 kg');
      expect(w['d'], -1);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  test('R4-A-5: η αναφορά μετρά μόνο τις ξένες ζυγίσεις του διαστήματός της (πριν: όλου του ιστορικού)', () {
    final today = DateTime(2026, 11, 13);
    final h = <String, Map<String, double>>{
      for (var i = 0; i < 30; i++) dateKey(DateTime(today.year, today.month, today.day - i)): {K.weight: i == 10 ? 30.0 : 90.0},
      for (var i = 185; i < 216; i++) dateKey(DateTime(today.year, today.month, today.day - i)): {K.weight: i == 200 ? 30.0 : 90.0},
    };
    expect(weighInStatus(h, _plan, DateTime(today.year, today.month, today.day - 200)), WeighStatus.foreign);
    expect(weighInStatus(h, _plan, DateTime(today.year, today.month, today.day - 10)), WeighStatus.foreign);
    expect(buildReport(h, DateTime(2026, 11, 13, 10)).foreignWeighIns, 1, reason: 'πριν: 2');
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('Ο κανόνας: δικές σου ζυγίσεις, χωρίς αποκλεισμό, ένας υπολογισμός', () {
    const pat = [0, 2, -1, 1, -2, 1, 0, -1, 2, -2, 1, 0];

    test('αρρώστια −4,5/−5/−6 kg, 10 μέρες χωρίς ζύγιση, ξεκινώντας κάθε μέρα της εβδομάδας: ποτέ «ξένη», μετρά ως την 3η', () {
      // python expected_r4b.py: 21 περιπτώσεις, 0 παραβάσεις.
      var bad = 0, cases = 0;
      for (final drop in [4.5, 5.0, 6.0]) {
        for (var off = 56; off < 63; off++) {
          final s = <(DateTime, double)>[];
          for (var k = 0; k < 112; k++) {
            final d = DateTime(2026, 11, 16 + k);
            if ((k >= off && k < off + 10) || !(d.weekday == 1 || d.weekday == 3 || d.weekday == 5)) continue;
            final kg = 82 - 0.5 / 7 * k - (k >= off + 10 ? drop : 0) + 0.3 * pat[s.length % 12];
            s.add((d, (kg * 10).round() / 10));
          }
          final first = s.indexWhere((x) => x.$1.difference(DateTime(2026, 11, 16)).inDays >= off + 10);
          cases++;
          for (var n = 0; n < s.length; n++) {
            final sub = s.sublist(0, n + 1);
            for (var j = 0; j < sub.length; j++) {
              if (weighStatusAt(sub, j) == WeighStatus.foreign) bad++;
            }
            if (n >= first + 2 && weighStatusAt(sub, first) != WeighStatus.counted) bad++;
          }
        }
      }
      expect(cases, 21);
      expect(bad, 0);
    });

    test('μεγάλη αληθινή αλλαγή (90 → 75 kg μετά από 10 μέρες χωρίς ζύγιση): μετρά, ποτέ «ξένη»', () {
      // python lockout.py: καμία ζύγιση δεν περιμένει πάνω από 6 μέρες, καμία δεν μένει εκτός (και −9…−20 kg, κενό 7–21 μέρες).
      final s = <(DateTime, double)>[];
      for (var k = 0; k < 112; k++) {
        final d = DateTime(2026, 11, 16 + k);
        if ((k >= 28 && k < 38) || !(d.weekday == 1 || d.weekday == 3 || d.weekday == 5)) continue;
        s.add((d, ((90.0 - 0.3 / 7 * k - (k >= 38 ? 15 : 0)) * 10).round() / 10));
      }
      var waits = 0;
      for (var n = 0; n < s.length; n++) {
        final sub = s.sublist(0, n + 1);
        for (var j = 0; j < sub.length; j++) {
          final st = weighStatusAt(sub, j);
          expect(st, isNot(WeighStatus.foreign));
          if (st != WeighStatus.counted && sub[n].$1.difference(sub[j].$1).inDays > 6) waits++;
        }
      }
      expect(waits, 0);
      expect([for (var j = 0; j < s.length; j++) weighStatusAt(s, j)], everyElement(WeighStatus.counted));
    });

    test('ένας χρόνος, κάθε μέρα 07:00, και παιδί κάθε Σάββατο 09:00: παντού το ίδιο, το παιδί ποτέ', () {
      // python expected_r4b.py: 0 δικές σου εκτός, 52 «ξένες», όλες του παιδιού.
      final body = <BodyMeasurement>[];
      for (var k = 0; k < 365; k++) {
        final d = DateTime(2026, 11, 16 + k);
        body.add(_m(DateTime(d.year, d.month, d.day, 7), ((82 - 0.5 / 7 * k + 0.3 * pat[k % 12]) * 10).round() / 10));
        if (d.weekday == DateTime.saturday && k >= 5) body.add(_m(DateTime(d.year, d.month, d.day, 9), 35.0));
      }
      final days = weighInDays(body);
      expect(days.where((g) => g.status != WeighStatus.counted), isEmpty);
      expect(days.where((g) => g.pick.weight == 35.0), isEmpty);
      final g = guardBody(body);
      expect(g.foreign.length, 52);
      expect(g.foreign.every((b) => b.weight == 35.0), isTrue);
      _sameEverywhere(body);
    });

    test('ιστορικό ±42 μερών = όλο το ιστορικό, και με παιδιά, επισκέπτες και αλλαγές', () {
      final r = math.Random(4242);
      var mismatches = 0;
      final seen = <WeighStatus>{};
      for (var run = 0; run < 25; run++) {
        final s = <(DateTime, double)>[];
        var kg = 80.0;
        for (var i = 0; i < 200; i++) {
          kg += -0.05 + 0.3 * (r.nextDouble() * 2 - 1);
          if (r.nextDouble() < 0.5) {
            final jump = r.nextDouble() < 0.25 ? [0.0, -35.0, 15.0, -6.0, 6.0, -10.0, 9.0, -45.0][r.nextInt(8)] : 0.0;
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
      expect((weightGuardHorizon, weightGuardSameWeek), (42, 7));
      expect((weightConfirmKg, weightConfirmShare, weightConfirmBigKg, weightConfirmBigShare, weightConfirmGap), (8.0, 0.10, 12.0, 0.15, 7));
    });
  });
}
