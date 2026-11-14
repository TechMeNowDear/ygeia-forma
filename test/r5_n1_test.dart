// Round 5 · n1 (R5-B-1, R5-B-2, R5-B-4, απόδοση του φύλακα, R5-B-5). Κάθε αναμενόμενη τιμή βγήκε από ΔΥΟ ανεξάρτητα
// ports του κανόνα σε python, γραμμένα από τη Dart από άλλους ελεγκτές (/home/claude/scratch/R5-B/g.py,
// /home/claude/scratch/R5-A/port.py: ίδιο αποτέλεσμα και στα δύο), με τα σενάρια του /home/claude/scratch/n1-r5/
// (expect_n1.py, seam_b.py, width.py, widecap.py), όχι από την υλοποίηση. Όλες οι τιμές είναι επινοημένες.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/adaptive_check.dart' show guardedWeights;
import 'package:ygeia_forma/body_trend.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/format.dart' show dayOf, daysBetween, shortDayDate;
import 'package:ygeia_forma/history.dart' show bodyRows, mergeBody;
import 'package:ygeia_forma/home_widgets/widget_snapshot.dart' show buildWidgetSnapshot, widgetPendingCap, widgetPendingCapShort;
import 'package:ygeia_forma/home_widgets/widget_style.dart' show WKind, wSizes;
import 'package:ygeia_forma/pages/body.dart' show BodyPage, pendingLatestText;
import 'package:ygeia_forma/pages/today.dart' show TodayPage;
import 'package:ygeia_forma/profile.dart' show Profile;
import 'package:ygeia_forma/sources.dart' show SourcePlan;
import 'package:ygeia_forma/theme.dart' show buildTheme, fontFamily;
import 'package:ygeia_forma/trends.dart' show weighInStatus;
import 'package:ygeia_forma/weight_guard.dart';
import 'package:ygeia_forma/widgets.dart' show InfoRow, StatCard, TrendPill;

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

/// Η εφαρμογή όπως διαβάζει (όπως το r4_m1): ιστορικό του δείγματος και μετά η κανονική ανάγνωση. Ύψος 180 cm.
HealthStore _store(DateTime now, List<BodyMeasurement> rows) {
  final s = HealthStore()..data = Dashboard.fromJson(_json(now, rows));
  s.history = sampleHistory(now, s.data!);
  applyRecentRead(s.history, s.data!, plan: _plan);
  s.setProfile(const Profile(birthYear: 1985, birthMonth: 12, sex: 'm', heightCm: 180));
  return s;
}

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 4000)}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: w)));
  await t.pumpAndSettle();
}

Map _widgetBody(HealthStore s, DateTime now) =>
    ((buildWidgetSnapshot(s, sampleFoodStore(now), now)['kinds'] as Map)[WKind.body] as Map)['m'] as Map;

String? _row(WidgetTester t, String label) {
  for (final r in t.widgetList<InfoRow>(find.byType(InfoRow))) {
    if (r.label == label) return r.value;
  }
  return null;
}

String _note(WidgetTester t) => t.widget<Text>(find.byKey(const ValueKey('body-trend-note'))).data!;

/// Δε/Τε/Πα 07:15 από Δευτέρα 16/11, 82,0 kg, −0,5 kg την εβδομάδα (ίδιες τιμές με το r4_m1, python expect_n1.py OWN).
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
];

/// Οι δικές σου ζυγίσεις ως και τη μέρα [until], 07:15, με λίπος 27,0.
List<BodyMeasurement> _ownUntil(DateTime until) => [
      for (final (d, kg) in _own)
        if (!d.isAfter(until)) _m(DateTime(d.year, d.month, d.day, 7, 15), kg, fat: 27.0),
    ];

/// Αρρώστια: ως Παρ 4/12, καμία ζύγιση 5–13/12, μετά Δε 14/12, Τε 16/12, Πα 18/12 07:15 με [kgs].
List<BodyMeasurement> _illness(List<double> kgs) => [
      ..._ownUntil(DateTime(2026, 12, 4)),
      for (var k = 0; k < kgs.length; k++) _m(DateTime(2026, 12, 14 + 2 * k, 7, 15), kgs[k], fat: 25.0),
    ];

Map<DateTime, WeighStatus> _statuses(List<BodyMeasurement> body) => {for (final g in weighInDays(body)) g.day: g.status};

/// Ο ΙΔΙΟΣ υπολογισμός: η κατάσταση κάθε μέρας στο ιστορικό ([weighInStatus], Τάσεις/εβδομάδα/αναφορά) = του φύλακα.
void _sameEverywhere(List<BodyMeasurement> body) {
  final h = _hist(body);
  for (final g in weighInDays(body)) {
    expect(weighInStatus(h, _plan, g.day), g.status, reason: '${g.day}');
  }
}

/// Ανεξάρτητος, «φρέσκος» υπολογισμός (χωρίς την κρυφή μνήμη του [weighInDays]): ίδια είσοδος με τη γραμμένη στο
/// body_trend.dart (μέρες με τη σειρά, ζυγίσεις κάθε μέρας με την ώρα, μόνο με βάρος) απευθείας στο [guardDays].
List<(DateTime, double, WeighStatus, bool)> _fresh(List<BodyMeasurement> body) {
  final byDay = <DateTime, List<BodyMeasurement>>{};
  for (final b in body) {
    if (b.weight != null && b.weight!.isFinite) byDay.putIfAbsent(dayOf(b.time), () => []).add(b);
  }
  final days = byDay.keys.toList()..sort();
  for (final d in days) {
    byDay[d]!.sort((a, b) => a.time.compareTo(b.time));
  }
  final r = guardDays([for (final d in days) (d, [for (final b in byDay[d]!) b.weight!])]);
  return [for (var i = 0; i < days.length; i++) (days[i], byDay[days[i]]![r[i].pick].weight!, r[i].status, r[i].unsure)];
}

List<(DateTime, double, WeighStatus, bool)> _cached(List<BodyMeasurement> body) => [
      for (final g in weighInDays(body))
        if (g.pick.weight != null) (g.day, g.pick.weight!, g.status, g.unsure),
    ];

void main() {
  // Η γραμματοσειρά της εφαρμογής (όπως στα στιγμιότυπα): με τη γραμματοσειρά δοκιμών κάθε γράμμα είναι τετράγωνο.
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R5-B-4: widget Σώμα, λεζάντα «δεν μετρά» στη στήλη 1×3, σε κάθε ρύθμιση', () {
    testWidgets('πλάτη με την Inter Medium 10,5 sp × γράμματα: η σύντομη χωρά χωρίς σμίκρυνση· η παλιά κοβόταν', (t) async {
      double w(String s, double fs) {
        final tp = TextPainter(
          text: TextSpan(text: s, style: TextStyle(fontFamily: fontFamily, fontSize: 10.5 * fs, fontWeight: FontWeight.w500)),
          textDirection: TextDirection.ltr,
        )..layout();
        final x = tp.width;
        tp.dispose();
        return x;
      }

      // WidgetRenderer.kt:183–185: περιθώριο σκιάς 4 dp, pad 8 dp (στήλη 1×3) / 11 dp (οι άλλες)· μικρή γραμμή ως 0,85
      // (WidgetText.MIN_SCALE_SMALL), μετά «…». Γράμματα: «Μικρά» 0,9, «Κανονικά» 1,0, «Μεγάλα» 1,12 (widget_config_page).
      final column = wSizes.firstWhere((s) => s.name == 'Στήλη 1×3').w;
      final wide = wSizes.firstWhere((s) => s.name == 'Μικρό 2×2').w;
      expect(column, 92);
      final narrow = column - 2 * 8 - 2 * 4; // 68 dp, με «Σκιά»
      // python (width.py, raqm): «δεν μετρά» 51,7 dp· × 1,12 = 57,9 ≤ 68 χωρίς σμίκρυνση.
      for (final fs in [0.9, 1.0, 1.12]) {
        expect(w(widgetPendingCapShort, fs), lessThanOrEqualTo(narrow), reason: 'fs $fs');
      }
      // Πριν: «δεν μετρά ακόμα» 87,1 dp: «Μεγάλα» 87,1 × 1,12 × 0,85 = 82,9 > 76· «Σκιά» 87,1 × 0,85 = 74,0 > 68 → «δεν μετρά ακ…».
      expect(w(widgetPendingCap, 1.12) * 0.85, greaterThan(column - 2 * 8));
      expect(w(widgetPendingCap, 1.0) * 0.85, greaterThan(narrow));
      // Η κανονική λεζάντα στις φαρδιές μορφές (180 − 2 × 11 − 2 × 4 = 150 dp): η μακρύτερη «Παρ 30/10 · δεν μετρά ακόμα»
      // 148,4 dp × 1,12 × 0,85 = 141,3 ≤ 150 (widecap.py): εκεί μένει ολόκληρη.
      expect(w('Παρ 30/10 · $widgetPendingCap', 1.12) * 0.85, lessThanOrEqualTo(wide - 2 * 11 - 2 * 4));
    });

    test('δική σου ζύγιση μετά από αρρώστια «σε αναμονή»: capShort «δεν μετρά», η κανονική λεζάντα ίδια', () {
      // python expect_n1.py S2: Δε 14/12 74,0 «σε αναμονή»· Πα 18/12 (3η ζύγιση, 4 μέρες, μετά από κενό) μετρούν όλες.
      final now = DateTime(2026, 12, 14, 8);
      final body = _illness([74.0]);
      expect(_statuses(body)[DateTime(2026, 12, 14)], WeighStatus.pending);
      final m = _widgetBody(_store(now, body), now);
      final w = m['weight'] as Map;
      expect(w['v'], '74,0');
      expect(w['cap'], '${shortDayDate(DateTime(2026, 12, 14))} · δεν μετρά ακόμα');
      expect(w['capShort'], 'δεν μετρά');
      expect(widgetPendingCapShort, 'δεν μετρά');
      expect(m.containsKey('bmi'), isFalse);
      final later = DateTime(2026, 12, 18, 8);
      final w2 = _widgetBody(_store(later, _illness([74.0, 73.6, 73.3])), later)['weight'] as Map;
      expect(w2['capShort'], '−0,3 kg', reason: 'μετρά πια: η διαφορά από την Τε 16/12 (73,6)');
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R5-B-2: Σώμα, ζύγιση που δεν μετρά: χωρίς δείκτη μάζας σώματος και χωρίς «σε παρένθεση η αλλαγή από…»', () {
    testWidgets('Δε 14/12 74,0 μετά από αρρώστια («σε αναμονή»)', (t) async {
      final now = DateTime(2026, 12, 14, 8);
      await _pump(t, BodyPage(store: _store(now, _illness([74.0])), now: now));
      expect(t.widget<Text>(find.byKey(const ValueKey('body-pending-latest'))).data, pendingLatestText);
      expect(_row(t, 'Βάρος'), '74,0 kg');
      expect(_row(t, 'Δείκτης μάζας σώματος'), isNull, reason: 'πριν: «22,8» (74,0 / 1,8²)');
      expect(_note(t), isNot(contains('σε παρένθεση η αλλαγή από')), reason: 'πριν: «… από τις 4 Δεκ.» χωρίς παρένθεση');
      expect(_note(t), contains('Σε λίπος και μύες'));
      expect(t.widgetList<TrendPill>(find.byType(TrendPill)).where((p) => p.text.contains(' kg από ')), isEmpty);
    });

    testWidgets('ζύγιση που μετρά (Πα 4/12 80,7): δείκτης, διαφορά και σημείωση όπως πριν', (t) async {
      final now = DateTime(2026, 12, 4, 8);
      await _pump(t, BodyPage(store: _store(now, _illness([])), now: now));
      expect(_row(t, 'Δείκτης μάζας σώματος'), '24,9'); // 80,7 / 1,8² = 24,907
      expect(_row(t, 'Βάρος'), '80,7 kg  (−0,2)');
      // Round 8 (A4 Β2 / U4 Β4): ίδια μορφή μέρας με το χάπι («2/12»· πριν «2 Δεκ.»).
      expect(_note(t), contains('Στο βάρος, σε παρένθεση η αλλαγή από τις 2/12.'));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R5-B-1: Σώμα, η διαφορά βάρους από την προηγούμενη ζύγιση που ΜΕΤΡΑ (όπως η Σήμερα)', () {
    // python expect_n1.py S1: Σάβ 19/12 19:00 ζύγιση με τη βαλίτσα (94,7), διακοπές 16 μέρες, Δε 4/1 07:15 78,9.
    // Στις 4/1: 19/12 «σε αναμονή» (για πάντα: η επόμενη ζύγιση είναι 16 μέρες μετά)· 4/1 μετρά· η προηγούμενη που μετρά:
    // Παρ 18/12 79,7.
    final rows = _sorted([
      ..._ownUntil(DateTime(2026, 12, 18)),
      _m(DateTime(2026, 12, 19, 19), 94.7, fat: 40.0),
      _m(DateTime(2027, 1, 4, 7, 15), 78.9, fat: 26.8),
    ]);

    test('ο φύλακας και η «προηγούμενη»', () {
      final st = _statuses(rows);
      expect(st[DateTime(2026, 12, 19)], WeighStatus.pending);
      expect(st[DateTime(2027, 1, 4)], WeighStatus.counted);
      final p = previousCounted(countedBody(rows), rows.last)!;
      expect((p.time, p.weight), (DateTime(2026, 12, 18, 7, 15), 79.7), reason: 'πριν: η 19/12 94,7 («−15,8 kg από 19/12»)');
      // Ίδια μέρα: μια δεύτερη ζύγιση της 4/1 συγκρίνεται κι αυτή με την 18/12, όχι με την πρωινή της ίδιας μέρας.
      final evening = _m(DateTime(2027, 1, 4, 20), 79.6);
      final p2 = previousCounted(countedBody([...rows, evening]), evening)!;
      expect(p2.time, DateTime(2026, 12, 18, 7, 15));
    });

    testWidgets('Σώμα και Σήμερα: «−0,8 kg από 18/12»', (t) async {
      final now = DateTime(2027, 1, 4, 8);
      final s = _store(now, rows);
      await _pump(t, BodyPage(store: s, now: now));
      final pills = [for (final p in t.widgetList<TrendPill>(find.byType(TrendPill))) if (p.text.contains(' kg από ')) p.text];
      expect(pills, ['−0,8 kg από 18/12']);
      expect(_row(t, 'Βάρος'), '78,9 kg  (−0,8)', reason: 'πριν: «78,9 kg  (−15,8)»');
      // Round 8 (A4 Β2 / U4 Β4): ίδια μορφή μέρας με το χάπι («18/12»· πριν «18 Δεκ.»).
      expect(_note(t), contains('σε παρένθεση η αλλαγή από τις 18/12.'));
      await _pump(t, TodayPage(store: s, food: sampleFoodStore(now), open: (_, [__]) {}, openSettings: () {}, now: now));
      final card = t.widgetList<StatCard>(find.byType(StatCard)).firstWhere((c) => c.icon == Icons.monitor_weight_rounded);
      expect((card.trend! as TrendPill).text, '−0,8 kg από 18/12');
    });

    testWidgets('Σάβ 19/12 20:00, η τελευταία είναι η «σε αναμονή»: χωρίς διαφορά, δείκτη και «σε παρένθεση…»', (t) async {
      final now = DateTime(2026, 12, 19, 20);
      await _pump(t, BodyPage(store: _store(now, _upTo(rows, now)), now: now));
      expect(find.byKey(const ValueKey('body-pending-latest')), findsOneWidget);
      expect(_row(t, 'Βάρος'), '94,7 kg');
      expect(_row(t, 'Δείκτης μάζας σώματος'), isNull);
      expect(_note(t), isNot(contains('σε παρένθεση η αλλαγή από')));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('Απόδοση: ο φύλακας μία φορά για κάθε νέα είσοδο, ίδιο αποτέλεσμα με φρέσκο υπολογισμό', () {
    test('ίδια είσοδος → ένας υπολογισμός· νέα, αλλαγμένη, σβησμένη ζύγιση, άλλη σειρά → νέος, ίδιος με φρέσκο', () {
      weighInDays([_m(DateTime(2020, 1, 1, 8), 70.0)]); // άλλη είσοδος στη μνήμη
      final list = _illness([74.0, 73.6]);
      var runs = guardDaysRuns;
      for (var k = 0; k < 6; k++) {
        expect(_cached(list), _fresh(list));
      }
      expect(guardDaysRuns - runs, 1, reason: '6 κλήσεις, ίδια είσοδος');
      final before = _cached(list);

      // Νέα ζύγιση (στην ΙΔΙΑ λίστα): Πα 18/12 73,3 → μετρούν και οι τρεις (κενό πριν, 3 μέρες σε 4).
      list.add(_m(DateTime(2026, 12, 18, 7, 15), 73.3));
      expect(_cached(list), _fresh(list));
      expect(_statuses(list)[DateTime(2026, 12, 14)], WeighStatus.counted);
      expect(_cached(list), isNot(before));

      // Αλλαγμένη τιμή (νέο αντικείμενο στην ίδια θέση της ίδιας λίστας): 18/12 66,0 (−7,6 από τις άλλες δύο).
      list[list.length - 1] = _m(DateTime(2026, 12, 18, 7, 15), 66.0);
      expect(_cached(list), _fresh(list));
      expect(_statuses(list)[DateTime(2026, 12, 14)], WeighStatus.pending);

      // Σβησμένη ζύγιση.
      list.removeLast();
      expect(_cached(list), _fresh(list));
      expect(_cached(list), before);

      // Δύο ζυγίσεις την ίδια μέρα που αλλάζουν σειρά (η ώρα): άλλη είσοδος.
      final a = [...list, _m(DateTime(2026, 12, 16, 6, 0), 80.6), _m(DateTime(2026, 12, 16, 9, 0), 73.5)];
      final b = [...list, _m(DateTime(2026, 12, 16, 9, 0), 80.6), _m(DateTime(2026, 12, 16, 6, 0), 73.5)];
      expect(_cached(a), _fresh(a));
      expect(_cached(b), _fresh(b));

      // Μόνο η ώρα αλλάζει, χωρίς αλλαγή σειράς: ίδια είσοδος (κανένας νέος υπολογισμός)· η ζύγιση της μέρας είναι η ΝΕΑ.
      final c = [for (final x in list) x];
      weighInDays(c);
      runs = guardDaysRuns;
      final moved = _m(DateTime(2026, 12, 16, 7, 40), 73.6);
      c[c.length - 1] = moved;
      final g = weighInDays(c).last;
      expect(guardDaysRuns - runs, 0);
      expect(identical(g.pick, moved), isTrue);
      expect(_cached(c), _fresh(c));
    });

    testWidgets('μία σχεδίαση του Σώματος και της Σήμερας = ένας υπολογισμός (πριν: 6 και 3)', (t) async {
      final now = DateTime(2026, 12, 16, 8);
      final s = _store(now, _illness([74.0, 73.6]));
      weighInDays([_m(DateTime(2020, 1, 1, 8), 70.0)]);
      var runs = guardDaysRuns;
      await _pump(t, BodyPage(store: s, now: now));
      expect(guardDaysRuns - runs, 1);
      weighInDays([_m(DateTime(2020, 1, 1, 8), 70.0)]);
      runs = guardDaysRuns;
      await _pump(t, TodayPage(store: s, food: sampleFoodStore(now), open: (_, [__]) {}, openSettings: () {}, now: now));
      expect(guardDaysRuns - runs, 1);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R5-B-5: τα μέρη του κανόνα του γύρου 4 που αφορούν τις δικές σου ζυγίσεις', () {
    test('όριο επιβεβαίωσης 8 kg / 10%: −10 kg από τη μια μέρα στην άλλη, 4 μέρες σε 6, ΧΩΡΙΣ κενό → «σε αναμονή»', () {
      // python S3 (και τα δύο ports): Σάβ 5/12, Δε 7/12, Τε 9/12, Πα 11/12 70,7 μετά την Πα 4/12 80,7· διάμεσος 80,7,
      // διαφορά 10,0 > 8,07 (όριο), κενό 1 μέρα → όλες «σε αναμονή». Χωρίς το όριο (ή με κενό πάντα): «μετρά».
      final body = [
        ..._ownUntil(DateTime(2026, 12, 4)),
        for (final d in [5, 7, 9, 11]) _m(DateTime(2026, 12, d, 7, 15), 70.7),
      ];
      final st = _statuses(body);
      for (final d in [5, 7, 9, 11]) {
        expect(st[DateTime(2026, 12, d)], WeighStatus.pending, reason: '$d/12');
      }
      expect(guardedWeights(body).used.last, (DateTime(2026, 12, 4), 80.7));
      _sameEverywhere(body);
    });

    test('ως 12 kg / 15% μετά από κενό > 7 μερών (αρρώστια): −9,7 kg μετρά με την 3η ζύγιση σε 4 μέρες', () {
      // python S4: Δε 14/12 71,0, Τε 16/12 70,8 «σε αναμονή»· Πα 18/12 70,9 → μετρούν και οι τρεις (κενό 10 μερών πριν).
      // Χωρίς την εξαίρεση (ή κενό > 14): η 14/12 και η 16/12 μένουν «σε αναμονή» (διαφορά 9,7 > 8,07).
      final all = _illness([71.0, 70.8, 70.9]);
      final wed = _upTo(all, DateTime(2026, 12, 16, 8));
      expect(_statuses(wed)[DateTime(2026, 12, 14)], WeighStatus.pending);
      expect(_statuses(wed)[DateTime(2026, 12, 16)], WeighStatus.pending);
      _sameEverywhere(wed);
      final st = _statuses(all);
      for (final d in [14, 16, 18]) {
        expect(st[DateTime(2026, 12, d)], WeighStatus.counted, reason: '$d/12');
      }
      expect(guardedWeights(all).used.sublist(guardedWeights(all).used.length - 3), [
        (DateTime(2026, 12, 14), 71.0),
        (DateTime(2026, 12, 16), 70.8),
        (DateTime(2026, 12, 18), 70.9),
      ]);
      _sameEverywhere(all);
    });

    test('πάνω από 12 kg / 15%, ακόμα και μετά από κενό: ποτέ με επιβεβαίωση', () {
      // python S5: 67,0 / 66,8 / 66,9· η Δε 14/12 (διαφορά 13,7 από 80,7 > 12,1) «σε αναμονή»· η 16/12 και η 18/12 μετρούν
      // επειδή οι ±14 μέρες τους είναι πια κυρίως στο νέο βάρος (αναφορά 73,85 και 67,0). Χωρίς το όριο 12/15%: μετρά και η 14/12.
      final st = _statuses(_illness([67.0, 66.8, 66.9]));
      expect(st[DateTime(2026, 12, 14)], WeighStatus.pending);
      expect(st[DateTime(2026, 12, 16)], WeighStatus.counted);
      expect(st[DateTime(2026, 12, 18)], WeighStatus.counted);
    });

    test('Τάσεις ±42 μέρες = φύλακας σε μακρύ ιστορικό· με ±28 (γύρος 3) θα διαφωνούσαν', () {
      // python seam_b.py (το (b) του R5-B-5): εσύ ως Πα 4/12, μετά καμία ζύγιση ως 2/1· παιδί 35,0 κάθε Σάβ και Κυρ 09:30
      // από 28/11. Σάβ 2/1 20:00: φύλακας = ιστορικό ±42 σε ΚΑΘΕ μέρα (όλες οι 35,0 μετά τις 4/12 «σε αναμονή»)· ένα
      // κομμάτι ±28 θα έλεγε «μετρά» τις 26/12, 27/12 και 2/1 (Τάσεις/εβδομάδα/αναφορά, ενώ Σώμα/θερμίδες «σε αναμονή»).
      final body = _sorted([
        ..._ownUntil(DateTime(2026, 12, 4)),
        for (var d = DateTime(2026, 11, 28); !d.isAfter(DateTime(2027, 1, 2)); d = DateTime(d.year, d.month, d.day + 1))
          if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) _m(DateTime(d.year, d.month, d.day, 9, 30), 35.0),
      ]);
      _sameEverywhere(body);
      final days = weighInDays(body);
      final series = [for (final g in days) (g.day, g.pick.weight!)];
      WeighStatus within(int i, int n) {
        final sub = [for (final e in series) if (daysBetween(e.$1, series[i].$1).abs() <= n) e];
        return weighStatusAt(sub, sub.indexWhere((e) => e.$1 == series[i].$1));
      }

      for (final d in [DateTime(2026, 12, 26), DateTime(2026, 12, 27), DateTime(2027, 1, 2)]) {
        final i = series.indexWhere((e) => e.$1 == d);
        expect(days[i].status, WeighStatus.pending, reason: '$d');
        expect(within(i, weightGuardHorizon), WeighStatus.pending, reason: '$d');
        expect(within(i, 28), WeighStatus.counted, reason: '$d: το σενάριο ξεχωρίζει ±28 από ±42');
      }
      expect(weightGuardHorizon, 42);
    });

    test('δικές σου ζυγίσεις με αρρώστια: ιστορικό = φύλακας σε κάθε στιγμή', () {
      for (final kgs in [
        [74.0, 73.6, 73.3],
        [71.0, 70.8, 70.9],
        [67.0, 66.8, 66.9],
      ]) {
        final all = _illness(kgs);
        for (var k = 1; k <= all.length; k++) {
          _sameEverywhere(all.sublist(0, k));
        }
      }
    });
  });
}
