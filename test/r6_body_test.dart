// Round 6 (R6-1, R6-2): Σώμα › «Τελευταία ζύγιση» όταν η τελευταία ζύγιση δεν μετρά. Δοκιμαστικές τιμές, φανταστικές.
// Μόνο ο ίδιος στη ζυγαριά (απόφαση χρήστη 13/11): αρρώστια με αφυδάτωση, βραδινή ζύγιση με ρούχα και τσάντα.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/body_trend.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/pages/body.dart' show BodyPage;
import 'package:ygeia_forma/profile.dart' show Profile;
import 'package:ygeia_forma/sources.dart' show SourcePlan;
import 'package:ygeia_forma/theme.dart' show buildTheme;
import 'package:ygeia_forma/weight_guard.dart';
import 'package:ygeia_forma/widgets.dart' show InfoRow;

import 'sample_data.dart' show sampleDashboardJson, sampleHistory;

const _inbody = 'com.inbody2014.inbody';
final _plan = SourcePlan.samsungOnly;

BodyMeasurement _m(DateTime t, double kg, double fat) => BodyMeasurement(time: t, weight: kg, fatPct: fat, app: _inbody);

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

/// Όπως στο r5_n1_test: ιστορικό του δείγματος και μετά η κανονική ανάγνωση. Ύψος 180 cm.
HealthStore _store(DateTime now, List<BodyMeasurement> rows) {
  final s = HealthStore()..data = Dashboard.fromJson(_json(now, rows));
  s.history = sampleHistory(now, s.data!);
  applyRecentRead(s.history, s.data!, plan: _plan);
  s.setProfile(const Profile(birthYear: 1986, birthMonth: 1, sex: 'm', heightCm: 180));
  return s;
}

Future<void> _pump(WidgetTester t, Widget w) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = const Size(400, 4000);
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: w)));
  await t.pumpAndSettle();
}

String? _row(WidgetTester t, String label) {
  for (final r in t.widgetList<InfoRow>(find.byType(InfoRow))) {
    if (r.label == label) return r.value;
  }
  return null;
}

String _note(WidgetTester t) => t.widget<Text>(find.byKey(const ValueKey('body-trend-note'))).data!;

/// Δε/Τε/Πα 07:15 από Δευτέρα 16/11, 82,0 kg, −0,5 kg την εβδομάδα (ίδιες τιμές με το r5_n1_test). Λίπος 27,0, εκτός από
/// τις 30/11, 2/12 και 4/12 (29,0: αφυδάτωση στην αρχή μιας αρρώστιας· η ζυγαριά BIA δείχνει τότε περισσότερο λίπος).
final _own = <(DateTime, double, double)>[
  (DateTime(2026, 11, 16, 7, 15), 82.0, 27.0),
  (DateTime(2026, 11, 18, 7, 15), 81.9, 27.0),
  (DateTime(2026, 11, 20, 7, 15), 81.7, 27.0),
  (DateTime(2026, 11, 23, 7, 15), 81.5, 27.0),
  (DateTime(2026, 11, 25, 7, 15), 81.4, 27.0),
  (DateTime(2026, 11, 27, 7, 15), 81.2, 27.0),
  (DateTime(2026, 11, 30, 7, 15), 81.0, 29.0),
  (DateTime(2026, 12, 2, 7, 15), 80.9, 29.0),
  (DateTime(2026, 12, 4, 7, 15), 80.7, 29.0),
];

List<BodyMeasurement> get _ownRows => [for (final (t, kg, fat) in _own) _m(t, kg, fat)];

void main() {
  group('R6-1: καμία τάση λίπους/μυών δίπλα σε ζύγιση που δεν μετρά', () {
    // Μετά από 9 μέρες αρρώστιας χωρίς ζύγιση: Δε 14/12 74,0 kg (−6,7 από 80,7: πάνω από 4 kg και 5%) με λίπος 25,0.
    final rows = [..._ownRows, _m(DateTime(2026, 12, 14, 7, 15), 74.0, 25.0)];

    test('ο φύλακας: η 14/12 είναι «σε αναμονή»· η τάση λίπους (3 τελευταίες που μετρούν, 29,0, με τις 3 πριν, 27,0) = +2,0', () {
      final st = {for (final g in weighInDays(rows)) g.day: g.status};
      expect(st[DateTime(2026, 12, 14)], WeighStatus.pending);
      final tr = bodyTrend(rows, (b) => b.fatPct)!;
      expect(tr.now, 29.0);
      expect(tr.before, 27.0);
    });

    testWidgets('Δε 14/12: «Λίπος 25,0%» χωρίς «(+2,0)» (πριν: «25,0%  (+2,0)», αλλαγή που δεν περιέχει την τιμή)', (t) async {
      final now = DateTime(2026, 12, 14, 8);
      await _pump(t, BodyPage(store: _store(now, rows), now: now));
      expect(_row(t, 'Λίπος'), '25,0%');
    });

    testWidgets('ζύγιση που μετρά (Πα 4/12): η τάση φαίνεται όπως πριν, «29,0%  (+2,0)»', (t) async {
      final now = DateTime(2026, 12, 4, 8);
      await _pump(t, BodyPage(store: _store(now, _ownRows), now: now));
      expect(_row(t, 'Λίπος'), '29,0%  (+2,0)');
    });
  });

  group('R6-2: βραδινή ζύγιση με ρούχα και τσάντα την ίδια μέρα (δεν μετρά): χωρίς δείκτη και «σε παρένθεση…»', () {
    // Πα 4/12 80,7 το πρωί, 85,4 στις 19:30 (+4,7: πάνω από 4 kg και 5% της 80,7). Ζύγιση της μέρας η πρωινή.
    final rows = [..._ownRows, _m(DateTime(2026, 12, 4, 19, 30), 85.4, 27.0)];

    test('ο φύλακας: η ζύγιση της 4/12 είναι η πρωινή και μετρά· η βραδινή δεν είναι στις «μετρούν»', () {
      final g = weighInDays(rows).last;
      expect(g.day, DateTime(2026, 12, 4));
      expect(g.pick.weight, 80.7);
      expect(g.status, WeighStatus.counted);
      expect(countedBody(rows).any((b) => b.weight == 85.4), isFalse);
    });

    testWidgets('Πα 4/12 20:00: «Βάρος 85,4 kg» χωρίς διαφορά και δείκτη (πριν: δείκτης 26,4 και «… από τις 2 Δεκ.»)', (t) async {
      final now = DateTime(2026, 12, 4, 20);
      await _pump(t, BodyPage(store: _store(now, rows), now: now));
      expect(_row(t, 'Βάρος'), '85,4 kg');
      expect(_row(t, 'Δείκτης μάζας σώματος'), isNull); // 85,4 / 1,8² = 26,36
      expect(_note(t), isNot(contains('σε παρένθεση η αλλαγή από')));
    });
  });
}
