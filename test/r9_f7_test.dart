// Round 9 · f7 («Ύπνος, καρδιά, Τάσεις, σελίδες υγείας»): R9-A5-1 (= R9-U4-5), R9-A5-2, R9-A5-3, R9-A5-4, R9-U4-1,
// R9-U4-2, R9-U4-3, R9-U4-6. Οι αναμενόμενες τιμές βγήκαν από τον γραμμένο κανόνα (με το χέρι ή με python στο
// /home/claude/scratch/f7r9/), όχι από τη νέα υλοποίηση. Όλες οι τιμές είναι επινοημένες.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/oura/oura_api.dart';
import 'package:ygeia_forma/oura/oura_model.dart';
import 'package:ygeia_forma/pages/heart.dart';
import 'package:ygeia_forma/pages/metric_page.dart';
import 'package:ygeia_forma/pages/oura_sleep.dart';
import 'package:ygeia_forma/pages/trends.dart';
import 'package:ygeia_forma/reference.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/trends.dart';
import 'package:ygeia_forma/widgets.dart';

import 'sample_data.dart';

// ---------------------------------------------------------------------------
// Βοηθοί
// ---------------------------------------------------------------------------

DateTime _add(DateTime x, int n) => DateTime(x.year, x.month, x.day + n);

int _ms(DateTime t) => t.millisecondsSinceEpoch;

String _utc(DateTime t) => t.toUtc().toIso8601String();

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 4000)}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: w)));
  await t.pumpAndSettle();
}

/// Όλες οι ετικέτες του κόμβου σημασιολογίας του [f] και των παιδιών του, με τη σειρά (ό,τι διαβάζει το TalkBack).
String _spoken(WidgetTester t, Finder f) {
  final out = <String>[];
  void walk(SemanticsNode n) {
    if (n.label.isNotEmpty) out.add(n.label);
    n.visitChildren((c) {
      walk(c);
      return true;
    });
  }

  walk(t.getSemantics(f));
  return out.join(' ');
}

/// Η περιγραφή που δίνει στο TalkBack το (πρώτο) γράφημα γραμμής κάτω από το [scope].
String _chartLabel(WidgetTester t, {Finder? scope}) {
  final chart = scope == null ? find.byType(LineChart) : find.descendant(of: scope, matching: find.byType(LineChart));
  final sem = t.widget<Semantics>(find.descendant(of: chart.first, matching: find.byType(Semantics)).first);
  return sem.properties.label ?? '';
}

/// Μία περίοδος ύπνου της Oura (νύχτα 23:00 → 07:30), όπως στο r7_f7.
Map<String, dynamic> _ouraNight(DateTime morning) {
  final start = DateTime(morning.year, morning.month, morning.day - 1, 23);
  final end = DateTime(morning.year, morning.month, morning.day, 7, 30);
  return {
    'id': 'n-${dateKey(morning)}',
    'day': dateKey(morning),
    'type': 'long_sleep',
    'bedtime_start': _utc(start),
    'bedtime_end': _utc(end),
    'time_in_bed': end.difference(start).inSeconds,
    'total_sleep_duration': 3600 + 14400 + 5400,
    'deep_sleep_duration': 3600,
    'light_sleep_duration': 14400,
    'rem_sleep_duration': 5400,
    'awake_time': 1800,
    'latency': 600,
  };
}

/// Φάσεις της Samsung στη σειρά, από [start].
List<List<Object>> _seq(DateTime start, List<(String, int)> parts) {
  final out = <List<Object>>[];
  var x = start;
  for (final (name, m) in parts) {
    out.add([name, _ms(x), _ms(x.add(Duration(minutes: m)))]);
    x = x.add(Duration(minutes: m));
  }
  return out;
}

TrendResult _result(String key, TrendStatus status, {double? effective}) {
  final end = DateTime(2026, 11, 14);
  return TrendResult(
    def: metricDef(key)!,
    status: status,
    current: 60,
    previous: 60,
    nCurrent: 30,
    nPrevious: 30,
    needed: 20,
    z: 0,
    points: const [],
    currentFrom: _add(end, -29),
    previousFrom: _add(end, -59),
    previousEnd: _add(end, -30),
    end: end,
    effectiveCurrent: effective,
  );
}

/// Η γεωμετρία του γραφήματος γραμμής (σχόλια του _LinePainter: αριστερά 4, δεξιά 44·s, πάνω 26·s, κάτω 22·s) και τα
/// σημεία σε px, με τον άξονα του [lineAxis].
({List<Offset> pts, Rect plot}) _geometry(List<double> values, List<DateTime> dates,
    {required double scale, required double width, required double height, double minRange = 3}) {
  const left = 4.0;
  final right = 44.0 * scale;
  final top = 26.0 * scale;
  final bottom = 22.0 * scale;
  final w = width - left - right;
  final h = height - top - bottom;
  final (lo, step, n) = lineAxis(values, minRange: minRange, plotHeight: h);
  final t0 = dates.first.millisecondsSinceEpoch.toDouble();
  final t1 = dates.last.millisecondsSinceEpoch.toDouble();
  return (
    pts: [
      for (var i = 0; i < values.length; i++)
        Offset(left + w * (dates[i].millisecondsSinceEpoch - t0) / (t1 - t0), top + h * (1 - (values[i] - lo) / (step * n))),
    ],
    plot: Rect.fromLTWH(left, top, w, h),
  );
}

/// Αν κάποιο σημείο της γραμμής (δείγμα κάθε 1/400 του τμήματος, με μισό πάχος γραμμής 1,25 px) πέφτει πάνω στην πλάκα
/// της τιμής ([_plate]: 3 px αριστερά-δεξιά, 1 px πάνω-κάτω γύρω από το κείμενο).
bool _plateCoversLine(Offset o, Size label, List<Offset> pts) {
  final r = Rect.fromLTWH(o.dx - 3, o.dy - 1, label.width + 6, label.height + 2).inflate(1.25);
  for (var i = 1; i < pts.length; i++) {
    for (var k = 0; k <= 400; k++) {
      final p = Offset.lerp(pts[i - 1], pts[i], k / 400)!;
      if (r.contains(p)) return true;
    }
  }
  return false;
}

void main() {
  // Τα πλάτη μετριούνται με το Inter της εφαρμογής (όχι με τη γραμματοσειρά δοκιμών), όπως στο r7_f7 / r8_f7.
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
  });

  // ------------------------------------------------------------------ R9-A5-1 = R9-U4-5
  group('R9-A5-1 / R9-U4-5: η σημείωση τύχης μετρά μόνο τις γραμμές που ελέγχθηκαν', () {
    test('16 γραμμές: 6 «Λίγα δεδομένα» και 2 «Αλλαγή πηγής» δεν ελέγχθηκαν → 8 (μαζί 1 «Λίγες μέρες για συμπέρασμα»)', () {
      final results = [
        for (var i = 0; i < 6; i++) _result(K.sleepHr, TrendStatus.insufficient),
        for (var i = 0; i < 2; i++) _result(K.sleepHr, TrendStatus.sourceChange),
        _result(K.sleepHr, TrendStatus.up),
        _result(K.sleepHr, TrendStatus.down),
        for (var i = 0; i < 5; i++) _result(K.sleepHr, TrendStatus.stable),
        // «Λίγες μέρες για συμπέρασμα»: ο έλεγχος έγινε (με μεγάλη κρίσιμη τιμή), άρα μετρά.
        _result(K.sleepHr, TrendStatus.stable, effective: 2),
      ];
      expect(results.length, 16);
      expect(results.last.inconclusive, isTrue);
      expect(testedRows(results), 8);
    });

    test('η πιθανότητα ανάλογη με τις ελεγμένες γραμμές (1 − 0,99^k ως 1 − 0,9945^k)', () {
      // python: k=1 → 0,5–1% · k=2–3 → 1,1–3% · k=4–9 → 2,2–8,6% · k≥10 → 5,4–18% (προσομοίωση 16–20 γραμμών: 10%).
      expect([for (final k in [1, 2, 3, 4, 9, 10, 16, 20]) chanceOneIn(k)], [100, 50, 50, 20, 20, 10, 10, 10]);
      expect(chanceNote(10),
          'Με 10 μετρήσεις μαζί, περίπου μία φορά στις 10 κάποια γραμμή λέει «άλλαξε» από τύχη· αν η αλλαγή φαίνεται και '
          'τις επόμενες εβδομάδες, είναι πιο σίγουρη.');
      expect(chanceNote(1),
          'Ο έλεγχος λέει «άλλαξε» από τύχη περίπου μία φορά στις 100· αν η αλλαγή φαίνεται και τις επόμενες εβδομάδες, '
          'είναι πιο σίγουρη.');
    });

    testWidgets('Τάσεις: παλμοί ύπνου 55 → 62 και σταθερά βήματα, όλα τα άλλα χωρίς δεδομένα → «Με 2 μετρήσεις … στις 50»',
        (t) async {
      final today = DateTime(2026, 11, 14);
      final s = HealthStore()
        ..history = {
          for (var i = 0; i <= 60; i++)
            dateKey(_add(today, -i)): {
              K.sleepHr: (i < 30 ? 62.0 : 55.0) + (i.isEven ? 0.5 : -0.5),
              K.steps: 8000.0 + (i.isEven ? 100 : -100),
            },
        };
      await _pump(t, TrendsPage(store: s, now: DateTime(2026, 11, 14, 10)));
      final note = t.widget<Text>(find.byKey(const ValueKey('trends-chance-note'))).data!;
      // Πριν: «Με 16 μετρήσεις μαζί, περίπου μία φορά στις 10 …» (όλες οι γραμμές της λίστας).
      expect(note,
          'Με 2 μετρήσεις μαζί, περίπου μία φορά στις 50 κάποια γραμμή λέει «άλλαξε» από τύχη· αν η αλλαγή φαίνεται και '
          'τις επόμενες εβδομάδες, είναι πιο σίγουρη.');
    });
  });

  // ------------------------------------------------------------------ R9-A5-2
  testWidgets('R9-A5-2: Ύπνος (Oura) › «Αναπνοή και οξυγόνο»: η πολύ χαμηλή τιμή της χθεσινής νύχτας, όπως Καρδιά/Σήμερα',
      (t) async {
    // Νύχτα 15/11: ρολόι στο χέρι, χαμηλότερη 78% (κάλυψη 7 από 8½ ώρες). Νύχτα 16/11: ήρθε από το Oura, το ρολόι
    // φόρτιζε (καμία μέτρηση). 16/11 08:30.
    final at = DateTime(2026, 11, 16, 8, 30);
    final s = HealthStore();
    s.debugSetPlan(SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 1)));
    s.ouraNights = parseOura(
      sleep: [_ouraNight(DateTime(2026, 11, 15)), _ouraNight(DateTime(2026, 11, 16))],
      dailySleep: const [],
      readiness: const [],
    ).nights;
    mergeOura(s.history, ouraRows(s.ouraNights), from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 16), plan: s.plan);
    s.data = Dashboard.fromJson({
      'readAt': _ms(at),
      'sleep': <Object>[],
      'spo2': [
        [_ms(DateTime(2026, 11, 14, 23, 30)), _ms(DateTime(2026, 11, 15, 6, 30)), 92.0, 78.0, 96.0],
      ],
    });
    s.ouraHasTokens = true;
    s.ouraLink = OuraLink(vault: MemoryVault(), clientId: 'TEST');
    s.ouraClock = () => at;
    s.ouraSyncedMs = at.subtract(const Duration(minutes: 12)).millisecondsSinceEpoch;
    await _pump(t, OuraSleepPage(store: s, now: at));
    expect(t.takeException(), isNull);
    // Πριν: καμία σημείωση στον Ύπνο (η νύχτα της κάρτας, 16/11, δεν έχει τιμή ρολογιού), ενώ η Καρδιά και η Σήμερα την
    // έδειχναν.
    expect(
      find.descendant(
          of: find.byKey(const ValueKey('oxygen-notes')),
          matching: find.textContaining('την τελευταία νύχτα με μέτρηση (Κυρ 15/11)')),
      findsOneWidget,
    );
  });

  // ------------------------------------------------------------------ R9-A5-3
  group('R9-A5-3: νύχτα ρολογιού «μερικώς χωρίς φάσεις» έξω από τις Τάσεις (φάσεις και ξύπνιος)', () {
    final day = DateTime(2026, 11, 3);
    // Κομμάτι 1: 2/11 23:30 – 3/11 02:30 με φάσεις (βαθύς 50, ελαφρύς 100, REM 25, ξύπνιος 5)· κενό 70 λεπτά·
    // κομμάτι 2: 03:40 – 07:30, με ή χωρίς φάσεις.
    Map<String, dynamic> read({required bool secondStaged}) => {
          'readAt': _ms(DateTime(2026, 11, 3, 12)),
          'sleep': [
            {
              'start': _ms(DateTime(2026, 11, 2, 23, 30)),
              'end': _ms(DateTime(2026, 11, 3, 2, 30)),
              'minutes': 180,
              'stages': _seq(DateTime(2026, 11, 2, 23, 30), [('DEEP', 50), ('LIGHT', 100), ('REM', 25), ('AWAKE', 5)]),
            },
            {
              'start': _ms(DateTime(2026, 11, 3, 3, 40)),
              'end': _ms(DateTime(2026, 11, 3, 7, 30)),
              'minutes': 230,
              'stages': secondStaged
                  ? _seq(DateTime(2026, 11, 3, 3, 40), [('LIGHT', 150), ('DEEP', 30), ('REM', 40), ('AWAKE', 10)])
                  : <Object>[],
            },
          ],
        };

    test('μερική νύχτα: καμία από βαθύ %, REM %, ξύπνιο (πριν: του ενός κομματιού, ξύπνιος 5 λεπτά)', () {
      final d = Dashboard.fromJson(read(secondStaged: false));
      expect(d.nights.single.partial, isTrue);
      final row = summarizeDay(d, day);
      expect(row.containsKey(K.deepPct), isFalse);
      expect(row.containsKey(K.remPct), isFalse);
      expect(row.containsKey(K.awakeMin), isFalse);
      expect(row.containsKey(K.sleepMin), isFalse, reason: 'όπως πριν (έλεγχος 8/11, DATA-01)');
      expect(row.containsKey(K.bedtime), isTrue, reason: 'οι ώρες ύπνου/ξυπνήματος μένουν');
    });

    test('ολόκληρη νύχτα με φάσεις: όπως πριν', () {
      final d = Dashboard.fromJson(read(secondStaged: true));
      expect(d.nights.single.fullDuration, isTrue);
      final row = summarizeDay(d, day);
      // Βαθύς 80, ελαφρύς 250, REM 65 → ύπνος 395 λεπτά· ξύπνιος 5 + 10.
      expect(row[K.sleepMin], 395);
      expect(row[K.deepPct], closeTo(100 * 80 / 395, 1e-9));
      expect(row[K.remPct], closeTo(100 * 65 / 395, 1e-9));
      expect(row[K.awakeMin], 15);
    });
  });

  // ------------------------------------------------------------------ R9-A5-4
  group('R9-A5-4: Καρδιά χωρίς πηγή ύπνου: καμία υπόσχεση «από το δαχτυλίδι»', () {
    const rangeText = 'Χωρίς πηγή ύπνου δεν ξεχωρίζει ο ύπνος από τη μέρα, οπότε οι χαμηλότεροι και υψηλότεροι της μέρας '
        'δεν φαίνονται. Η πηγή του ύπνου αλλάζει στις «Ρυθμίσεις Oura».';
    const awakeText =
        'Χωρίς πηγή ύπνου δεν ξεχωρίζει ο ύπνος από τη μέρα, οπότε δεν βγαίνει. Η πηγή του ύπνου αλλάζει στις «Ρυθμίσεις Oura».';
    const watchText = 'Βγαίνει για μέρες με αρκετές μετρήσεις του ρολογιού (τουλάχιστον 6 ώρες).';
    const ringText = 'Βγαίνει για μέρες με νύχτα από το δαχτυλίδι και αρκετές μετρήσεις του ρολογιού.';

    testWidgets('Oura από 1/11, αποσύνδεση χωρίς ρολόι από 12/11: 13/11 και οι δύο κάρτες λένε «χωρίς πηγή ύπνου»',
        (t) async {
      final now = DateTime(2026, 11, 13, 10);
      final s = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(now));
      s.debugSetPlan(
          SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 1)).withEra(Source.none, DateTime(2026, 11, 12)));
      expect(s.plan.nightSource(DateTime(2026, 11, 13)), Source.none);
      await _pump(t, HeartPage(store: s, now: now));
      final range = t.widget<Text>(find.byKey(const ValueKey('heart-day-range-note'))).data!;
      final awake = t.widget<Text>(find.byKey(const ValueKey('heart-awake-note'))).data!;
      expect(range, rangeText);
      expect(awake, awakeText);
      expect('$range $awake', isNot(contains('δαχτυλίδι')));
    });

    test('η σημείωση «Παλμοί ξύπνιος» σε κάθε αλλαγή πηγής', () {
      final d = DateTime(2026, 11, 13);
      final oura = SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 1));
      expect(awakeHeartNote(SourcePlan.samsungOnly, d), watchText);
      expect(awakeHeartNote(oura, d), ringText);
      // Αποσύνδεση: από την πρώτη μέρα χωρίς πηγή (η χθεσινή νύχτα ήταν ακόμα του Oura).
      expect(awakeHeartNote(oura.withEra(Source.none, d), d), awakeText);
      expect(awakeHeartNote(oura.withEra(Source.none, DateTime(2026, 11, 12)), d), awakeText);
      // Μετά «το ρολόι από απόψε»: ρολόι, ποτέ δαχτυλίδι.
      final back = oura.withEra(Source.none, DateTime(2026, 11, 12)).withEra(Source.watch, d);
      expect(awakeHeartNote(back, d), watchText);
      // Νέα σύνδεση του Oura μετά από μέρες χωρίς πηγή: το δαχτυλίδι.
      expect(awakeHeartNote(oura.withEra(Source.none, DateTime(2026, 11, 10)).withEra(Source.oura, d), d), ringText);
    });
  });

  // ------------------------------------------------------------------ R9-U4-1
  group('R9-U4-1: η ετικέτα της τελευταίας τιμής δεν σκεπάζει το τελευταίο κομμάτι της γραμμής', () {
    // Σώμα › Βάρος (ύψος 170, ελάχιστο εύρος 3 kg), κάρτα ~292 px σε κινητό 360 dp· ζυγίσεις από 28/12 ως 24/10.
    final dates = [
      DateTime(2025, 12, 28),
      DateTime(2026, 2, 1),
      DateTime(2026, 3, 10),
      DateTime(2026, 4, 15),
      DateTime(2026, 5, 20),
      DateTime(2026, 6, 25),
      DateTime(2026, 8, 13),
      DateTime(2026, 10, 24),
    ];
    final cases = <String, (List<double>, double)>{
      '… 83,3 → 82,2 με γράμματα 1,3×': ([86.9, 86.1, 85.4, 84.9, 84.2, 83.6, 83.3, 82.2], 1.3),
      '… 83,3 → 82,2 με γράμματα 2× (09b)': ([86.9, 86.1, 85.4, 84.9, 84.2, 83.6, 83.3, 82.2], 1.6),
      '… 82,0 → 81,0 με κανονικά γράμματα': ([86.9, 86.1, 85.4, 84.9, 84.2, 83.6, 82.0, 81.0], 1.0),
    };
    for (final e in cases.entries) {
      test(e.key, () {
        final (values, scale) = e.value;
        final g = _geometry(values, dates, scale: scale, width: 292, height: 170);
        // Μέγεθος του «82,2» (Inter 12·s, έντονα), περίπου.
        final label = Size(27 * scale, 14.5 * scale);
        final last = g.pts.last;
        // Το σενάριο του ευρήματος: η γραμμή έρχεται από ψηλότερα, από κάτω δεν χωρά, και η παλιά θέση (αριστερά, στο ύψος
        // του σημείου) σκέπαζε το τελευταίο κομμάτι.
        expect(g.pts[g.pts.length - 2].dy, lessThan(last.dy - 2));
        expect(last.dy + 9 + label.height, greaterThan(g.plot.bottom));
        expect(_plateCoversLine(Offset(last.dx - 8 - label.width, last.dy - label.height / 2), label, g.pts), isTrue);

        final o = lastValueLabelAt(
            last: last, prev: g.pts[g.pts.length - 2], lines: [g.pts], label: label, plot: g.plot, width: 292);
        expect(_plateCoversLine(o, label, g.pts), isFalse, reason: 'πλάκα στο $o');
        // Μέσα στο γράφημα, και κοντά στο σημείο της (όχι στην άλλη άκρη).
        expect(o.dx, greaterThanOrEqualTo(0));
        expect(o.dx + label.width, lessThanOrEqualTo(292));
        expect(o.dy, greaterThanOrEqualTo(0));
        expect(o.dy + label.height, lessThanOrEqualTo(g.plot.bottom + 1e-9));
        final plate = Rect.fromLTWH(o.dx - 3, o.dy - 1, label.width + 6, label.height + 2);
        final gap = Offset((last.dx - last.dx.clamp(plate.left, plate.right)).toDouble(),
            (last.dy - last.dy.clamp(plate.top, plate.bottom)).toDouble());
        expect(gap.distance, lessThan(3 * label.height));
      });
    }

    test('οι άλλες θέσεις όπως πριν: γραμμή από κάτω → πάνω από το σημείο· από πάνω με χώρο → κάτω από αυτό', () {
      final plot = Rect.fromLTWH(4, 26, 252, 112);
      const label = Size(27, 14.5);
      // Από κάτω: κέντρο στο min(256, 256 − 16) = 240 → x = 240 − 13,5· y = 80 − 9 − 14,5.
      expect(
          lastValueLabelAt(
              last: const Offset(256, 80),
              prev: const Offset(130, 120),
              lines: const [
                [Offset(130, 120), Offset(256, 80)]
              ],
              label: label,
              plot: plot,
              width: 300),
          const Offset(226.5, 56.5));
      // Από πάνω, με χώρο από κάτω: y = 60 + 9.
      expect(
          lastValueLabelAt(
              last: const Offset(256, 60),
              prev: const Offset(130, 30),
              lines: const [
                [Offset(130, 30), Offset(256, 60)]
              ],
              label: label,
              plot: plot,
              width: 300),
          const Offset(226.5, 69));
    });

    testWidgets('ζωγραφισμένο: η γραμμή φαίνεται ως την κουκκίδα (84,0 → 83,5 → 82,2, 300 × 160)', (t) async {
      const key = ValueKey('r9-line');
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 300,
                height: 160,
                child: LineChart(
                  height: 160,
                  points: [(DateTime(2026, 11, 1), 84.0), (DateTime(2026, 11, 8), 83.5), (DateTime(2026, 11, 15), 82.2)],
                  format: (v) => dec(v),
                  color: Aigaio.light.body,
                ),
              ),
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
      final (lo, step, n) = lineAxis([84.0, 83.5, 82.2], minRange: 1, plotHeight: 112);
      double yOf(double v) => 26 + 112 * (1 - (v - lo) / (step * n));
      // Σημεία: (130, y(83,5)) και (256, y(82,2)).
      final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(key));
      final bytes = (await t.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 1);
        final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        img.dispose();
        return data!;
      }))!;
      int px(int x, int y) => bytes.getUint32((y * 300 + x) * 4);
      for (final x in [240, 244, 248]) {
        final y = yOf(82.2) + (yOf(83.5) - yOf(82.2)) * (256 - x) / (256 - 130);
        // Πριν: λευκή πλάκα («82,2») πάνω στη γραμμή, από x ≈ 218 ως την κουκκίδα.
        expect(px(x, y.floor()), isNot(0xFFFFFFFF), reason: 'η γραμμή κρυμμένη στο x $x');
      }
    });
  });

  // ------------------------------------------------------------------ R9-U4-2
  group('R9-U4-2: TalkBack: διάρκειες με λέξεις, όχι «6:12»', () {
    final today = DateTime(2026, 11, 14);
    final now = DateTime(2026, 11, 14, 10);
    Map<String, Map<String, double>> sleep() => {
          for (var i = 0; i < 60; i++) dateKey(_add(today, -i)): {K.sleepMin: 372.0 + (i % 3) * 30},
        };

    testWidgets('σελίδα «Διάρκεια ύπνου»', (t) async {
      final s = HealthStore()..history = sleep();
      await _pump(t, MetricPage(store: s, spec: metricSpecs[K.sleepMin]!, now: now));
      final label = _chartLabel(t);
      expect(label, contains('6 ώρες 12 λεπτά'));
      expect(label, isNot(matches(RegExp(r'\d:\d\d'))));
    });

    testWidgets('Τάσεις › «Διάρκεια ύπνου» ανοιχτή', (t) async {
      final s = HealthStore()..history = sleep();
      await _pump(t, TrendsPage(store: s, now: now));
      final row = find.byKey(const ValueKey('trend-${K.sleepMin}'));
      await t.ensureVisible(row);
      await t.tap(row);
      await t.pumpAndSettle();
      final label = _chartLabel(t);
      expect(label, contains('ώρες'));
      expect(label, isNot(matches(RegExp(r'\d:\d\d'))));
    });

    test('θερμοκρασία καρπού (ρολόι): η διαφορά με τη μονάδα· παλμοί: η περιγραφή του άξονα (null)', () {
      final end = DateTime(2026, 11, 14);
      TrendResult r(String key) => TrendResult(
            def: metricDef(key)!,
            status: TrendStatus.stable,
            current: 0,
            previous: 0,
            nCurrent: 30,
            nPrevious: 30,
            needed: 20,
            z: 0,
            points: const [],
            currentFrom: _add(end, -29),
            previousFrom: _add(end, -59),
            previousEnd: _add(end, -30),
            end: end,
          );
      final pts = [(_add(end, -1), -0.2), (end, 0.4)];
      final temp = trendChartLabel(r(K.skinTemp), pts)!;
      expect(temp, contains('+0,4 °C'));
      expect(temp, contains('0,2 °C'));
      expect(trendChartLabel(r(K.sleepHr), pts), isNull);
    });
  });

  // ------------------------------------------------------------------ R9-U4-3
  group('R9-U4-3: TalkBack: η κατεύθυνση του «χαπιού» χωρίς πρόσημο', () {
    Future<String> spokenPill(WidgetTester t, TrendPill pill) async {
      await _pump(t, Center(child: Semantics(container: true, child: pill)), size: const Size(400, 800));
      return _spoken(t, find.byType(TrendPill));
    }

    testWidgets('«2.449» με βελάκι κάτω → «μείωση 2.449»', (t) async {
      final handle = t.ensureSemantics();
      final said = await spokenPill(t, const TrendPill('2.449', up: false));
      expect(said, contains('μείωση'));
      expect(said, contains('2.449'));
      expect(said.indexOf('μείωση'), lessThan(said.indexOf('2.449')));
      handle.dispose();
    });

    testWidgets('«5 kg» με βελάκι πάνω → «αύξηση»', (t) async {
      final handle = t.ensureSemantics();
      expect(await spokenPill(t, const TrendPill('5 kg', up: true)), contains('αύξηση'));
      handle.dispose();
    });

    testWidgets('με πρόσημο στο κείμενο («+2 bpm · συνήθως 59»): χωρίς δεύτερη λέξη', (t) async {
      final handle = t.ensureSemantics();
      final said = await spokenPill(t, const TrendPill('+2 bpm · συνήθως 59', up: true));
      expect(said, contains('+2 bpm'));
      expect(said, isNot(contains('αύξηση')));
      handle.dispose();
    });

    testWidgets('Τάσεις › Βήματα 8.000 → 5.500: η γραμμή λέει «μείωση»', (t) async {
      final handle = t.ensureSemantics();
      final today = DateTime(2026, 11, 14);
      final s = HealthStore()
        ..history = {
          for (var i = 0; i <= 60; i++)
            dateKey(_add(today, -i)): {K.steps: (i <= 30 ? 5500.0 : 8000.0) + (i.isEven ? 100 : -100)},
        };
      await _pump(t, TrendsPage(store: s, now: DateTime(2026, 11, 14, 10)));
      final row = find.byKey(const ValueKey('trend-${K.steps}'));
      await t.ensureVisible(row);
      await t.pumpAndSettle();
      expect(_spoken(t, row), contains('μείωση'));
      handle.dispose();
    });
  });

  // ------------------------------------------------------------------ R9-U4-6
  test('R9-U4-6: ⓘ Διάρκεια ύπνου › «Πάνω»: «Πιο κοντά στις 7 ώρες ή πάνω από αυτές»', () {
    // Κείμενο: δεν υπάρχει άλλη συμπεριφορά να ελεγχθεί.
    final up = metricInfos[K.sleepMin]!.up;
    expect(up, 'Πιο κοντά στις 7 ώρες ή πάνω από αυτές: σύμφωνα με τις οδηγίες.');
    expect(up, isNot(contains('κοντά ή πάνω από')));
  });
}
