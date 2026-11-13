// Round 2 · g4 («Φύλακας ζυγίσεων: «σε αναμονή» και «ξένη», Σώμα, Σήμερα και widget βάρους, όρια σύστασης σώματος»).
// Κάθε αναμενόμενη τιμή βγήκε από τον γραμμένο κανόνα με python (/home/claude/scratch/g4/guard2.py, r2_values.py,
// floor_sim.py), όχι από τη νέα υλοποίηση. Όλες οι τιμές είναι επινοημένες (καμία πραγματική μέτρηση).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/adaptive_check.dart' show CheckIn, CheckKind, guardedWeights;
import 'package:ygeia_forma/body_trend.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/format.dart' show shortDayDate;
import 'package:ygeia_forma/history.dart' show K, dateKey;
import 'package:ygeia_forma/home_widgets/widget_snapshot.dart' show buildWidgetSnapshot;
import 'package:ygeia_forma/home_widgets/widget_style.dart' show WKind;
import 'package:ygeia_forma/pages/body.dart' show BodyPage, pendingLatestText;
import 'package:ygeia_forma/pages/checkin_card.dart' show CheckInCard;
import 'package:ygeia_forma/pages/report_page.dart' show ReportPage;
import 'package:ygeia_forma/pages/today.dart' show TodayPage;
import 'package:ygeia_forma/profile.dart' show Profile;
import 'package:ygeia_forma/reference.dart' show RefRange, healthyWeight;
import 'package:ygeia_forma/report.dart' show buildReport;
import 'package:ygeia_forma/shown.dart' show shownDiff;
import 'package:ygeia_forma/sources.dart' show SourcePlan;
import 'package:ygeia_forma/theme.dart' show buildTheme;
import 'package:ygeia_forma/trends.dart' show TrendPeriod, computeTrend, foreignWeighIn, trendMetrics;
import 'package:ygeia_forma/weight_guard.dart';
import 'package:ygeia_forma/widgets.dart' show LineChart, Sparkline, StatCard, TrendPill;

import 'sample_checkin.dart' show checkinGoals;
import 'sample_data.dart' show sampleDashboardJson, sampleHistory;
import 'sample_food.dart' show sampleFoodStore;

const _inbody = 'com.inbody2014.inbody';

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 4000)}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: w)));
  await t.pumpAndSettle();
}

/// Κανονική τιμή (Box–Muller), όπως στο test/r1_f4_test.dart.
double _normal(math.Random r) => math.sqrt(-2 * math.log(1 - r.nextDouble())) * math.cos(2 * math.pi * r.nextDouble());

BodyMeasurement _m(DateTime t, double kg, {double? fat, double? smm}) =>
    BodyMeasurement(time: t, weight: kg, fatPct: fat, smm: smm, app: _inbody);

/// Μία ζύγιση τη μέρα στις 07:30.
List<BodyMeasurement> _body(List<(DateTime, double)> w) => [for (final (d, kg) in w) _m(DateTime(d.year, d.month, d.day, 7, 30), kg)];

Map<String, Map<String, double>> _hist(List<(DateTime, double)> w) => {for (final (d, kg) in w) dateKey(d): {K.weight: kg}};

List<WeighStatus> _statuses(List<(DateTime, double)> w) => [for (var i = 0; i < w.length; i++) weighStatusAt(w, i)];

List<(DateTime, double)> _upTo(List<(DateTime, double)> w, DateTime day) => [for (final x in w) if (!x.$1.isAfter(day)) x];

List<(DateTime, double)> _sorted(List<(DateTime, double)> w) => [...w]..sort((a, b) => a.$1.compareTo(b.$1));

Map<String, dynamic> _bodyJson(DateTime readAt, List<BodyMeasurement> rows) => {
      'ok': true,
      'readAt': readAt.millisecondsSinceEpoch,
      'body': [
        for (final b in rows)
          {
            'time': b.time.millisecondsSinceEpoch,
            'weight': b.weight,
            if (b.fatPct != null) 'fatPct': b.fatPct,
            if (b.smm != null) 'smm': b.smm,
            'app': _inbody,
          },
      ],
    };

/// 82 kg από Δευτέρα 16/11, −0,5% την εβδομάδα, ζύγιση Δευτέρα, Τετάρτη, Παρασκευή (r2_values.py: «pre»).
final _pre = <(DateTime, double)>[
  (DateTime(2026, 11, 16), 82.0),
  (DateTime(2026, 11, 18), 81.9),
  (DateTime(2026, 11, 20), 81.8),
  (DateTime(2026, 11, 23), 81.6),
  (DateTime(2026, 11, 25), 81.5),
  (DateTime(2026, 11, 27), 81.4),
  (DateTime(2026, 11, 30), 81.2),
  (DateTime(2026, 12, 2), 81.1),
  (DateTime(2026, 12, 4), 80.9),
];

/// Το σενάριο του R2-E-2: αρρώστια Σάββατο 5/12 – Κυριακή 13/12 χωρίς ζύγιση, −5 kg.
final _ill = <(DateTime, double)>[(DateTime(2026, 12, 14), 75.4), (DateTime(2026, 12, 16), 75.2), (DateTime(2026, 12, 18), 75.1)];

/// Οι ίδιες ζυγίσεις χωρίς αρρώστια, ως Παρασκευή 11/12.
final _reg = <(DateTime, double)>[..._pre, (DateTime(2026, 12, 7), 80.8), (DateTime(2026, 12, 9), 80.7), (DateTime(2026, 12, 11), 80.5)];

void main() {
  // ---------------------------------------------------------------------------------------------------------------
  group('R2-E-2: μετά από κενό με αληθινή αλλαγή, οι δικές σου ζυγίσεις δεν λέγονται «ξένες»', () {
    test('αρρώστια −5 kg: η 14/12 «σε αναμονή», με τη 16/12 (μία που συμφωνεί) μετρούν και οι δύο', () {
      final as14 = [..._pre, _ill[0]];
      expect(_statuses(as14), [for (var i = 0; i < _pre.length; i++) WeighStatus.counted, WeighStatus.pending]);
      final g14 = guardedWeights(_body(as14));
      expect(g14.foreign, isEmpty, reason: 'πριν (γύρος 1): «ξένη»');
      expect(g14.used, _pre, reason: 'ο έλεγχος θερμίδων την περιμένει');
      final b14 = guardBody(_body(as14));
      expect(b14.foreign, isEmpty);
      expect(b14.pending.single.weight, 75.4);
      expect(countedBody(_body(as14)).last.weight, 75.4, reason: 'φαίνεται κανονικά (Σώμα, γραφήματα)');

      final as16 = [..._pre, _ill[0], _ill[1]];
      expect(_statuses(as16), everyElement(WeighStatus.counted));
      final g16 = guardedWeights(_body(as16));
      expect(g16.foreign, isEmpty, reason: 'πριν: 14/12 και 16/12 «ξένες» ως τη Δευτέρα 21/12');
      expect(g16.used, as16);
      expect(guardBody(_body(as16)).pending, isEmpty);
      final as18 = [..._pre, ..._ill];
      expect(_statuses(as18), everyElement(WeighStatus.counted));
    });

    test('ίδιο με −4,5 kg (14/12 75,9 → «σε αναμονή», 16/12 75,7 → μετρούν)', () {
      final a = [..._pre, (DateTime(2026, 12, 14), 75.9)];
      expect(weighStatusAt(a, a.length - 1), WeighStatus.pending);
      final b = [...a, (DateTime(2026, 12, 16), 75.7)];
      expect(_statuses(b), everyElement(WeighStatus.counted));
    });

    test('Τάσεις και αναφορά: η ζύγιση «σε αναμονή» φαίνεται και μετρά· καμία δεν λείπει', () {
      final h = _hist([..._pre, _ill[0]]);
      final day = DateTime(2026, 12, 14);
      expect(foreignWeighIn(h, SourcePlan.samsungOnly, day), isFalse);
      final tr = computeTrend(trendMetrics.firstWhere((m) => m.key == K.weight), h, day, TrendPeriod.month);
      expect(tr.points.any((p) => p.$1 == day && p.$2 == 75.4), isTrue);
      final r = buildReport(h, DateTime(2026, 12, 14, 10));
      expect(r.foreignWeighIns, 0, reason: 'πριν: 1, με «πιθανόν άλλου ατόμου»');
      expect((r.weighIns.first.$1, r.weighIns.first.$2), (day, 75.4), reason: 'πριν: η τελευταία ζύγιση ήταν η 80,9 της 4/12');
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R2-E-2: παιδί ή επισκέπτης ανάμεσα στις ζυγίσεις σου μένουν «ξένοι»', () {
    test('παιδί 45 kg το Σάββατο 5/12: «σε αναμονή» ως τη Δευτέρα, «ξένη» με τη Δευτέρα 7/12', () {
      final w = _sorted([..._reg, (DateTime(2026, 12, 5), 45.0)]);
      for (final day in [DateTime(2026, 12, 5), DateTime(2026, 12, 6)]) {
        final s = _upTo(w, day);
        expect(weighStatusAt(s, s.length - 1), WeighStatus.pending, reason: '$day');
        final g = guardedWeights(_body(s));
        expect(g.foreign, isEmpty);
        expect(g.used.any((x) => x.$1 == DateTime(2026, 12, 5)), isFalse, reason: 'ούτε στον έλεγχο θερμίδων');
      }
      for (final day in [DateTime(2026, 12, 7), DateTime(2026, 12, 11)]) {
        final s = _upTo(w, day);
        final st = _statuses(s);
        expect(st[s.indexWhere((x) => x.$1 == DateTime(2026, 12, 5))], WeighStatus.foreign, reason: '$day');
        expect(st.where((x) => x != WeighStatus.counted).length, 1);
        expect(guardedWeights(_body(s)).foreign, [(DateTime(2026, 12, 5), 45.0)]);
        expect(foreignWeighIn(_hist(s), SourcePlan.samsungOnly, DateTime(2026, 12, 5)), isTrue);
        expect(guardBody(_body(s)).foreign.single.weight, 45.0);
      }
    });

    test('επισκέπτης 95 kg το Σάββατο: «ξένη» με τη Δευτέρα', () {
      final s = _upTo(_sorted([..._reg, (DateTime(2026, 12, 5), 95.0)]), DateTime(2026, 12, 7));
      expect(guardedWeights(_body(s)).foreign, [(DateTime(2026, 12, 5), 95.0)]);
    });

    test('επισκέπτης Σάββατο και Κυριακή (95,0 · 95,4): η Κυριακή τον «βεβαιώνει», η Δευτέρα σου τον βγάζει', () {
      final w = _sorted([..._reg, (DateTime(2026, 12, 5), 95.0), (DateTime(2026, 12, 6), 95.4)]);
      // Γνωστό όριο (Αποφάσεις, g4.md): με δύο συμφωνούσες στη σειρά ως την Κυριακή μετρούν (σαν αλλαγή του ίδιου).
      expect(_statuses(_upTo(w, DateTime(2026, 12, 6))), everyElement(WeighStatus.counted));
      expect(guardedWeights(_body(_upTo(w, DateTime(2026, 12, 7)))).foreign,
          [(DateTime(2026, 12, 5), 95.0), (DateTime(2026, 12, 6), 95.4)]);
    });

    test('την ίδια μέρα: το παιδί μετά από σένα ή πριν από σένα είναι «ξένο»· η δική σου μετρά', () {
      final mine = _body(_upTo(_reg, DateTime(2026, 12, 7)));
      final after = [...mine, _m(DateTime(2026, 12, 7, 9), 45.0)];
      final a = guardBody(after);
      expect(a.foreign.single.time, DateTime(2026, 12, 7, 9));
      expect(a.pending, isEmpty);
      expect(countedBody(after).last.weight, 80.8);

      final before = [...mine, _m(DateTime(2026, 12, 7, 7), 45.0)]..sort((x, y) => x.time.compareTo(y.time));
      final b = guardBody(before);
      expect(b.foreign.single.time, DateTime(2026, 12, 7, 7));
      expect(countedBody(before).last.weight, 80.8);
      expect(guardedWeights(before).used.last, (DateTime(2026, 12, 7), 80.8));
      expect(guardedWeights(before).foreign, isEmpty);
    });

    test('αρρώστια ΚΑΙ το παιδί πρώτο τη μέρα που σε βεβαιώνει (16/12): μετρούν οι δικές σου (δεύτερο πέρασμα)', () {
      final body = [
        ..._body([..._pre, _ill[0]]),
        _m(DateTime(2026, 12, 16, 7), 45.0),
        _m(DateTime(2026, 12, 16, 7, 30), 75.2),
      ];
      final g = guardedWeights(body);
      expect(g.used.sublist(g.used.length - 2), [(DateTime(2026, 12, 14), 75.4), (DateTime(2026, 12, 16), 75.2)]);
      expect(g.foreign, isEmpty);
      final b = guardBody(body);
      expect(b.foreign.single.time, DateTime(2026, 12, 16, 7));
      expect(b.pending, isEmpty, reason: 'με ένα πέρασμα η 14/12 θα έμενε «σε αναμονή» (python)');
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R2-E-2: τακτικές ζυγίσεις δεν κρύβονται ποτέ', () {
    test('κάθε μέρα, πρωί και βράδυ (+1,2 kg): καμία «ξένη», καμία «σε αναμονή»', () {
      final body = <BodyMeasurement>[
        for (var i = 0; i < 60; i++) ...[
          _m(DateTime(2026, 11, 16 + i, 7, 30), 82 * (1 - 0.005 * i / 7)),
          _m(DateTime(2026, 11, 16 + i, 20), 82 * (1 - 0.005 * i / 7) + 1.2),
        ],
      ];
      final g = guardBody(body);
      expect((g.foreign.length, g.pending.length), (0, 0));
      expect(guardedWeights(body).used.length, 60);
    });

    test('Δε/Τε/Πα με θόρυβο 0,6 kg, απώλεια ως 2,5% την εβδομάδα, 40% χαμένες ζυγίσεις: ποτέ «ξένη»· «σε αναμονή» μετρά με την επόμενη', () {
      // python (mc.py, mc2.py): 0 «ξένες»· κάθε «σε αναμονή» → «μετρά» μόλις έρθει η επόμενη.
      final r = math.Random(20261214);
      var foreign = 0, pending = 0, total = 0;
      for (final rate in [0.0, 0.005, 0.015, 0.025]) {
        for (final skip in [0.0, 0.4]) {
          for (var run = 0; run < 60; run++) {
            final s = <(DateTime, double)>[];
            for (var i = 0; i < 70; i++) {
              final d = DateTime(2026, 11, 16 + i);
              if ((d.weekday == 1 || d.weekday == 3 || d.weekday == 5) && r.nextDouble() >= skip) {
                s.add((d, 82 * (1 - rate * i / 7) + 0.6 * _normal(r)));
              }
            }
            for (var k = 0; k < s.length; k++) {
              total++;
              final now = weighStatusAt(s.sublist(0, k + 1), k);
              if (now == WeighStatus.foreign) foreign++;
              if (now == WeighStatus.pending) {
                pending++;
                // Η επόμενη ζύγιση (ως 14 μέρες μετά· 16/11–24/1, χωρίς αλλαγή ώρας) την κάνει «μετρά».
                if (k + 1 < s.length && s[k + 1].$1.difference(s[k].$1).inDays <= weightGuardDays) {
                  expect(weighStatusAt(s.sublist(0, k + 2), k), WeighStatus.counted);
                }
              }
              if (weighStatusAt(s, k) == WeighStatus.foreign) foreign++;
            }
          }
        }
      }
      expect(foreign, 0);
      expect(pending, lessThan(total ~/ 100), reason: '$pending από $total');
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  test('Τάσεις: το κομμάτι ±28 μερών του foreignWeighIn δίνει ό,τι και όλο το ιστορικό', () {
    final r = math.Random(7);
    var mismatches = 0, foreign = 0;
    for (var run = 0; run < 40; run++) {
      final s = <(DateTime, double)>[];
      var kg = 80.0;
      for (var i = 0; i < 200; i++) {
        kg += -0.05 + 0.3 * _normal(r);
        if (r.nextDouble() < 0.45) {
          final jump = r.nextDouble() < 0.08 ? [0.0, -35.0, 15.0, -6.0, 6.0][r.nextInt(5)] : 0.0;
          s.add((DateTime(2026, 1, 1 + i), ((kg + 0.6 * _normal(r) + jump) * 10).round() / 10));
        }
      }
      final h = _hist(s);
      for (var i = 0; i < s.length; i++) {
        final full = weighStatusAt(s, i) == WeighStatus.foreign;
        if (full) foreign++;
        if (foreignWeighIn(h, SourcePlan.samsungOnly, s[i].$1) != full) mismatches++;
      }
    }
    expect(mismatches, 0);
    expect(foreign, greaterThan(0), reason: 'η δοκιμή έχει και ξένες');
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R2-E-2: κείμενα', () {
    test('Σώμα, «σε αναμονή»: μία ζύγιση που συμφωνεί αρκεί', () {
      expect(pendingLatestText, contains('μόλις συμφωνήσει μαζί της η επόμενη ζύγιση'));
      expect(pendingLatestText, isNot(contains('οι επόμενες ζυγίσεις')));
    });

    testWidgets('Σώμα: η 14/12 μετά την αρρώστια φαίνεται κανονικά, με τη διαφορά και τη σημείωση «σε αναμονή»', (t) async {
      final s = HealthStore()..data = Dashboard.fromJson(_bodyJson(DateTime(2026, 12, 14, 9), _body([..._pre, _ill[0]])));
      await _pump(t, BodyPage(store: s, now: DateTime(2026, 12, 14, 9)));
      expect(find.byKey(const ValueKey('body-pending-latest')), findsOneWidget);
      expect(find.byKey(const ValueKey('body-foreign-latest')), findsNothing);
      expect(find.byKey(const ValueKey('body-weighings-foreign')), findsNothing);
      expect(t.widgetList<TrendPill>(find.byType(TrendPill)).where((p) => p.text == '−5,5 kg από 4/12'), hasLength(1));
    });

    testWidgets('κάρτα ελέγχου θερμίδων: «ξένη» = πριν και μετά συμφωνούν μεταξύ τους· χωρίς «θα μετρήσει μόλις…»', (t) async {
      final one = CheckIn(kind: CheckKind.foreign, goals: checkinGoals(), foreign: [(DateTime(2026, 12, 5), 45.0)]);
      await _pump(t, SingleChildScrollView(child: CheckInCard(check: one, store: HealthStore(), now: DateTime(2026, 12, 7, 9))));
      expect(find.textContaining('Δεν μπήκε στον έλεγχο θερμίδων: οι ζυγίσεις σου πριν και μετά από αυτήν συμφωνούν μεταξύ τους'),
          findsOneWidget);
      expect(find.textContaining('θα μετρήσει μόλις'), findsNothing);
      final two = CheckIn(
          kind: CheckKind.foreign,
          goals: checkinGoals(),
          foreign: [(DateTime(2026, 12, 5), 45.0), (DateTime(2026, 12, 6), 45.2)]);
      await _pump(t, SingleChildScrollView(child: CheckInCard(check: two, store: HealthStore(), now: DateTime(2026, 12, 7, 9))));
      expect(find.textContaining('Δεν μπήκαν στον έλεγχο θερμίδων: οι ζυγίσεις σου πριν και μετά από αυτές'), findsOneWidget);
    });

    testWidgets('αναφορά για γιατρό: «δεν μετρήθηκε στους υπολογισμούς», ποτέ «άλλου ατόμου»', (t) async {
      final now = DateTime(2026, 11, 13, 10);
      // 30 μέρες με 90 kg, και 30 kg στις 3/11 ανάμεσά τους (python: «ξένη»).
      final h = <String, Map<String, double>>{
        for (var i = 0; i < 30; i++) dateKey(DateTime(2026, 11, 13 - i)): {K.weight: i == 10 ? 30.0 : 90.0},
      };
      expect(buildReport(h, now).foreignWeighIns, 1);
      final store = HealthStore()
        ..data = Dashboard.fromJson(sampleDashboardJson(now))
        ..history = h;
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(680, 3600);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: ReportPage(store: store, now: now)));
      await t.pumpAndSettle();
      final note = t.widget<Text>(find.byKey(const ValueKey('report-weigh-note'))).data!;
      expect(note, endsWith(' 1 ζύγιση δεν μετρήθηκε στους υπολογισμούς.'));
      expect(note, isNot(contains('άλλου')));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R2-D-6 / R2-D-8: Σήμερα, widget και γραφήματα με τους κανόνες της τάσης', () {
    final now = DateTime(2026, 11, 13, 21);
    // Πρωινές ζυγίσεις, μία βραδινή (11/11 20:00, +1,4) και το παιδί σήμερα 09:00, μετά από σένα (python: μόνο αυτό «ξένο»).
    final rows = <BodyMeasurement>[
      for (final (d, kg) in [(2, 90.6), (4, 90.4), (6, 90.3), (9, 90.1), (11, 90.0), (13, 89.8)]) _m(DateTime(2026, 11, d, 7, 30), kg),
      _m(DateTime(2026, 11, 11, 20), 91.4),
      _m(DateTime(2026, 11, 13, 9), 30.0),
    ]..sort((a, b) => a.time.compareTo(b.time));

    HealthStore store() {
      final s = HealthStore()
        ..data = Dashboard.fromJson({...sampleDashboardJson(now), 'body': (_bodyJson(now, rows)['body'] as List)});
      s.history = sampleHistory(now, s.data!);
      return s;
    }

    testWidgets('Σήμερα: 89,8 kg (η πρώτη σου σήμερα), «−0,2 kg από 11/11», γράφημα μία τιμή τη μέρα', (t) async {
      await _pump(t, TodayPage(store: store(), food: sampleFoodStore(now), open: (_, [__]) {}, openSettings: () {}, now: now));
      final card = t.widgetList<StatCard>(find.byType(StatCard)).firstWhere((c) => c.icon == Icons.monitor_weight_rounded);
      expect(card.value, '89,8', reason: 'πριν: 30,0 (το παιδί)');
      expect((card.trend! as TrendPill).text, '−0,2 kg από 11/11', reason: 'πριν: «−59,8 kg από 13/11»');
      expect((card.chart! as Sparkline).values, [90.6, 90.4, 90.3, 90.1, 90.0, 89.8], reason: 'όχι η βραδινή 91,4, όχι το 30');
    });

    test('widget Σώμα: ίδια τιμή, διαφορά και κρίση εύρους από τη δική σου ζύγιση', () {
      final s = store()..setProfile(const Profile(birthYear: 1986, birthMonth: 1, sex: 'm', heightCm: 180));
      final snap = buildWidgetSnapshot(s, sampleFoodStore(now), now);
      final w = (((snap['kinds'] as Map)[WKind.body] as Map)['m'] as Map)['weight'] as Map;
      expect(w['v'], '89,8');
      expect(w['cap'], '${shortDayDate(DateTime(2026, 11, 13))} · −0,2 kg');
      expect(w['d'], -1);
      expect(w['s'], [null, 90.6, 90.4, 90.3, 90.1, 90.0, 89.8]);
      final hw = healthyWeight(180)!;
      final range = RefRange(low: hw.$1, high: hw.$2, text: '', cite: '');
      expect(w['r'], range.placeText(89.8));
      expect(w['r'], isNot(range.placeText(30.0)), reason: 'πριν: «κάτω από το εύρος» από το βάρος του παιδιού');
    });

    testWidgets('Σώμα: το γράφημα λίπους μόνο με τις πρωινές (όχι 26,0 → 24,6 → 26,1 ζιγκ-ζαγκ)', (t) async {
      final body = <BodyMeasurement>[
        for (final (d, fat) in [(2, 26.0), (4, 26.1), (6, 26.0), (9, 26.1), (11, 26.0), (13, 26.1)])
          _m(DateTime(2026, 11, d, 8), 90, fat: fat),
        for (final (d, fat) in [(9, 24.6), (11, 24.8), (13, 24.7)]) _m(DateTime(2026, 11, d, 20), 90.5, fat: fat),
      ]..sort((a, b) => a.time.compareTo(b.time));
      final s = HealthStore()..data = Dashboard.fromJson(_bodyJson(now, body));
      await _pump(t, BodyPage(store: s, now: now));
      final fat = t.widget<LineChart>(find.descendant(of: find.byKey(ValueKey('body-${K.fatPct}')), matching: find.byType(LineChart)));
      expect([for (final p in fat.points) p.$2], [26.0, 26.1, 26.0, 26.1, 26.0, 26.1]);
      expect(fat.points.every((p) => p.$1.hour == 8), isTrue);
      final kg = t.widget<LineChart>(find.descendant(of: find.byKey(ValueKey('body-${K.weight}')), matching: find.byType(LineChart)));
      expect([for (final p in kg.points) p.$2], everyElement(90.0));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R2-D-2: όριο θορύβου σύστασης σώματος', () {
    /// Πόσο συχνά, χωρίς ΚΑΜΙΑ αλλαγή, η κάρτα γράφει παρένθεση (3 + 3 ζυγίσεις με θόρυβο [sigma]).
    double noiseShown(double sigma, double floor, {int n = 3000, int seed = 11}) {
      final r = math.Random(seed);
      var shown = 0;
      for (var k = 0; k < n; k++) {
        final body = [for (var d = 0; d < 6; d++) _m(DateTime(2026, 11, 2 + 2 * d, 8), 90, smm: 34 + sigma * _normal(r))];
        final tr = bodyTrend(body, (b) => b.smm)!;
        if (bodyDiffShown(shownDiff(tr.now, tr.before, 1), floor)) shown++;
      }
      return shown / n;
    }

    test('McLester 2020, μεγαλύτερο σφάλμα: παρένθεση από θόρυβο < 6% (python 3,9% και 3,8%)· με τα όρια του γύρου 1 23% και 12%', () {
      expect(noiseShown(0.84, bodyFloorKg), lessThan(0.06));
      expect(noiseShown(0.84, 1.0), greaterThan(0.15));
      expect(noiseShown(0.99, bodyFloorFatPct), lessThan(0.06));
      expect(noiseShown(0.99, 1.5), greaterThan(0.08));
    });

    test('η σημείωση λέει τα όρια με τους αριθμούς τους', () {
      final note = bodyTrendNote(previous: null, days: 6, date: (d) => '${d.day}/${d.month}');
      expect(note, contains('2 μονάδες στο λίπος ή 1,7 kg και πάνω'));
      expect(note, contains('διακύμανση της ζυγαριάς'));
    });
  });
}
