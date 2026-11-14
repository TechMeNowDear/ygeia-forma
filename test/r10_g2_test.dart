// Round 10 · g2 («Σώμα, Σήμερα, widgets, γραφήματα, κείμενα»): R10-B2-2 (= R10-B3-2 = R10-B3-3 = R10-B8-B2), R10-B2-3,
// R10-B3-1, R10-B8-1 (= R10-B2-B1), R10-B8-2, R10-B8-B1. (R10-B2-1 στην Kotlin: R10G2Test.kt.)
// Οι αναμενόμενες τιμές βγήκαν από τον γραμμένο κανόνα (με το χέρι ή με python στο /home/claude/scratch/g2r10/), όχι από
// τη νέα υλοποίηση. Όλες οι τιμές είναι επινοημένες.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart' show Dashboard, HealthStore, applyRecentRead;
import 'package:ygeia_forma/exercise/ex_data.dart' show ExLibrary;
import 'package:ygeia_forma/format.dart' show thousands;
import 'package:ygeia_forma/history.dart' show K, dateKey;
import 'package:ygeia_forma/pages/body.dart' show BodyPage;
import 'package:ygeia_forma/pages/metric_page.dart' show MetricPage, metricPageTitle, metricSpecs;
import 'package:ygeia_forma/pages/oura_pages.dart' show ouraConnectPrivacyText;
import 'package:ygeia_forma/pages/today.dart' show TodayPage;
import 'package:ygeia_forma/pages/training/today_training_card.dart' show TodayTrainingCard;
import 'package:ygeia_forma/pages/trends.dart' show trendChartFormat, trendChartLabel;
import 'package:ygeia_forma/pages/week_card.dart' show WeekCard;
import 'package:ygeia_forma/profile.dart' show Profile;
import 'package:ygeia_forma/sources.dart' show Source, SourcePlan, ouraKeys;
import 'package:ygeia_forma/theme.dart' show buildTheme;
import 'package:ygeia_forma/trends.dart' show TrendResult, TrendStatus, metricDef;
import 'package:ygeia_forma/widgets.dart' show LineChart, lastValueLabelAt;

import 'sample_data.dart' show sampleDashboardJson, sampleHistory;
import 'sample_food.dart' show sampleFoodStore;
import 'training_sample.dart' show sampleTraining;

const _inbody = 'com.inbody2014.inbody';

/// Το φανταστικό προφίλ των δοκιμών (R10-FIX): άνδρας, 180 cm, γεννημένος 12/1985.
const _me = Profile(birthYear: 1985, birthMonth: 12, sex: 'm', heightCm: 180);

DateTime _add(DateTime x, int n) => DateTime(x.year, x.month, x.day + n);

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 4000), double textScale = 1.0}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.light),
    builder: (context, child) =>
        MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
    home: Scaffold(body: w),
  ));
  await t.pumpAndSettle();
}

/// Η περιγραφή του (πρώτου) γραφήματος γραμμής για το TalkBack, όπως στο r9_f7.
String _chartLabel(WidgetTester t) {
  final chart = find.byType(LineChart);
  final sem = t.widget<Semantics>(find.descendant(of: chart.first, matching: find.byType(Semantics)).first);
  return sem.properties.label ?? '';
}

/// Αν κάποιο σημείο της γραμμής (δείγμα κάθε 1/400 του τμήματος, με μισό πάχος γραμμής 1,25 px) πέφτει πάνω στην πλάκα
/// της τιμής (3 px αριστερά-δεξιά, 1 px πάνω-κάτω γύρω από το κείμενο).
bool _plateCoversLine(Offset o, Size label, List<Offset> pts) {
  final r = Rect.fromLTWH(o.dx - 3, o.dy - 1, label.width + 6, label.height + 2).inflate(1.25);
  for (var i = 1; i < pts.length; i++) {
    for (var k = 0; k <= 400; k++) {
      if (r.contains(Offset.lerp(pts[i - 1], pts[i], k / 400)!)) return true;
    }
  }
  return false;
}

TrendResult _trend(String key, Source source) {
  final end = DateTime(2026, 11, 14);
  return TrendResult(
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
    source: source,
  );
}

void main() {
  // Τα πλάτη μετριούνται με το Inter της εφαρμογής (όχι με τη γραμματοσειρά δοκιμών), όπως στο r9_f7.
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
  });

  // ------------------------------------------------------------------ R10-B2-2 = R10-B3-2 = R10-B3-3 = R10-B8-B2
  group('R10-B2-2: η πλάκα της τελευταίας τιμής ποτέ μέσα στη στήλη των τιμών του άξονα', () {
    // Γεωμετρία του _LinePainter για γράφημα 332 × 150 με γράμματα 2× (κλίμακα 1,6): αριστερά 4, δεξιά 70,4, πάνω 41,6,
    // κάτω 35,2 → πλαίσιο (4, 41,6, 257,6 × 73,2), δεξιά άκρη 261,6· οι τιμές του άξονα αρχίζουν στο 261,6 + 8 = 269,6.
    final plot = Rect.fromLTWH(4, 41.6, 257.6, 73.2);
    // «5.400» (Inter Bold 12 × 1,6, περίπου).
    const label = Size(55, 23.2);

    test('γραμμή που ανεβαίνει: πάνω από το σημείο, με τη δεξιά άκρη της πλάκας ως το plot.right + 2', () {
      // Πριν: κέντρο στο min(261,6, 261,6 − 16) → x = 245,6 − 27,5 = 218,1, πλάκα ως το 276,1 (6,5 px μέσα στις τιμές).
      // Τώρα: x = 261,6 − 1 − 55 = 205,6 (πλάκα ως το 263,6)· y = 70 − 9 − 23,2 = 37,8.
      final o = lastValueLabelAt(
        last: const Offset(261.6, 70),
        prev: const Offset(200, 100),
        lines: const [
          [Offset(150, 110), Offset(200, 100), Offset(261.6, 70)]
        ],
        label: label,
        plot: plot,
        width: 332,
      );
      expect(o.dx, closeTo(205.6, 1e-6));
      expect(o.dy, closeTo(37.8, 1e-6));
      expect(o.dx + label.width + 3, lessThanOrEqualTo(plot.right + 2 + 1e-9));
    });

    test('γραμμή που πέφτει, χωρίς χώρο από κάτω (βήματα 8.100 → 5.400): πάνω από το σημείο, έξω από τη στήλη', () {
      const pts = [
        Offset(4, 48),
        Offset(40, 52),
        Offset(75, 50),
        Offset(110, 58),
        Offset(145, 70),
        Offset(180, 82),
        Offset(220, 90),
        Offset(261.6, 97.7),
      ];
      final last = pts.last;
      // Το σενάριο: η γραμμή έρχεται από ψηλότερα και από κάτω δεν χωρά (97,7 + 9 + 23,2 > 114,8).
      expect(pts[pts.length - 2].dy, lessThan(last.dy - 2));
      expect(last.dy + 9 + label.height, greaterThan(plot.bottom));
      final o = lastValueLabelAt(last: last, prev: pts[pts.length - 2], lines: const [pts], label: label, plot: plot, width: 332);
      // Python (scratch/g2r10/label_cap.py): πριν (218,1, 61,5) με πλάκα ως το 276,1· τώρα (205,6, 59,5).
      expect(o.dx + label.width + 3, lessThanOrEqualTo(plot.right + 2 + 1e-9), reason: 'πλάκα στο $o');
      expect(_plateCoversLine(o, label, pts), isFalse, reason: 'πλάκα στο $o');
      expect(o.dy + label.height, lessThanOrEqualTo(last.dy), reason: 'πάνω από το σημείο');
      expect(last.dy - (o.dy + label.height), lessThan(2 * label.height), reason: 'κοντά στο σημείο της');
    });

    test('κανονικά γράμματα, στενή ετικέτα: η θέση δεν αλλάζει (R9-U4-1)', () {
      // Κέντρο στο min(256, 240) = 240 → x = 240 − 14,5 = 225,5 < 256 − 1 − 29 = 226: το όριο δεν πιάνει.
      final o = lastValueLabelAt(
        last: const Offset(256, 80),
        prev: const Offset(130, 120),
        lines: const [
          [Offset(130, 120), Offset(256, 80)]
        ],
        label: const Size(29, 14.5),
        plot: Rect.fromLTWH(4, 26, 252, 112),
        width: 300,
      );
      expect(o.dx, closeTo(225.5, 1e-9));
      expect(o.dy, closeTo(56.5, 1e-9));
    });

    testWidgets('ζωγραφισμένο με γράμματα 2×: καμία λευκή κουκκίδα της πλάκας στη στήλη των τιμών του άξονα', (t) async {
      const key = ValueKey('r10-line');
      // Βήματα που πέφτουν, η τελευταία τιμή η χαμηλότερη (Τάσεις › Βήματα, R10-B3-2). Άξονας 4.000–10.000 (python).
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
      const values = [8100.0, 7900.0, 8000.0, 7600.0, 7000.0, 6400.0, 5900.0, 5400.0];
      await _pump(
        t,
        Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 332,
              height: 150,
              child: LineChart(
                height: 150,
                points: [for (var i = 0; i < values.length; i++) (dates[i], values[i])],
                format: (v) => thousands(v),
              ),
            ),
          ),
        ),
        size: const Size(400, 800),
        textScale: 2,
      );
      final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(key));
      final bytes = (await t.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 1);
        final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        img.dispose();
        return data!;
      }))!;
      int px(int x, int y) => bytes.getUint32((y * 332 + x) * 4);
      // Η στήλη των τιμών αρχίζει στο 269,6. Λευκό αδιαφανές (το χρώμα της κάρτας) ζωγραφίζουν μόνο η πλάκα και το
      // περίγραμμα της κουκκίδας (ακτίνα 6 γύρω από το 261,6 → ως το 267,6). Πριν: πλάκα ως το 276,1, στα 64–90 px ύψος.
      for (var x = 271; x < 332; x++) {
        for (var y = 0; y < 150; y++) {
          expect(px(x, y), isNot(0xFFFFFFFF), reason: 'πλάκα στη στήλη του άξονα, x $x y $y');
        }
      }
    });
  });

  // ------------------------------------------------------------------ R10-B3-1
  group('R10-B3-1: η θερμοκρασία του Oura στο γράφημα με πρόσημο και μονάδα, όπως του ρολογιού', () {
    test('Τάσεις: μορφή του άξονα/της πλάκας και περιγραφή για το TalkBack', () {
      for (final src in [Source.oura, Source.watch]) {
        final f = trendChartFormat(_trend(K.skinTemp, src));
        expect(f(0.3), '+0,3', reason: '$src');
        expect(f(-0.2), '\u22120,2', reason: '$src: «−», όχι «-»');
        expect(f(0), '0', reason: '$src');
      }
      // Οι άλλες μετρήσεις όπως πριν (παλμοί: ακέραιοι, χωρίς πρόσημο).
      expect(trendChartFormat(_trend(K.sleepHr, Source.oura))(55), '55');
      final end = DateTime(2026, 11, 14);
      final pts = [(_add(end, -1), -0.2), (end, 0.4)];
      final oura = trendChartLabel(_trend(K.skinTemp, Source.oura), pts)!;
      expect(oura, contains('+0,4 °C'));
      expect(oura, contains('\u22120,2 °C'));
      expect(trendChartLabel(_trend(K.sleepHr, Source.oura), pts), isNull);
    });

    testWidgets('σελίδα «Θερμοκρασία δέρματος» με Oura: το TalkBack με πρόσημο και «°C»', (t) async {
      final now = DateTime(2026, 11, 14, 10);
      final today = DateTime(2026, 11, 14);
      final key = ouraKeys[K.skinTemp]!;
      final s = HealthStore()
        ..history = {
          for (var i = 0; i < 20; i++) dateKey(_add(today, -i)): {key: i == 0 ? 0.3 : (i == 1 ? -0.2 : 0.1)},
        };
      s.debugSetPlan(SourcePlan.samsungOnly.withEra(Source.oura, _add(today, -60)));
      await _pump(t, MetricPage(store: s, spec: metricSpecs[K.skinTemp]!, now: now));
      final label = _chartLabel(t);
      expect(label, contains('τελευταία +0,3 °C'));
      expect(label, contains('χαμηλότερη \u22120,2 °C'));
    });
  });

  // ------------------------------------------------------------------ R10-B3-1 (δίδυμο στο Σώμα)
  testWidgets('R10-B3-1 δίδυμο: Σώμα › «Θερμοκρασία καρπού στον ύπνο»: το TalkBack με «°C»', (t) async {
    // Ίδιο δείγμα με το audit_f_test («Σώμα: … γράφημα απόκλισης από το «συνήθως»»).
    final now = DateTime(2026, 10, 24, 16, 30);
    final s = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(now));
    s.history = sampleHistory(now, s.data!);
    await _pump(t, BodyPage(store: s, now: now));
    final chart =
        t.widget<LineChart>(find.descendant(of: find.byKey(const ValueKey('body-skin')), matching: find.byType(LineChart)));
    // Πριν: χωρίς δική του περιγραφή, άρα «… τελευταία +0,1» χωρίς μονάδα.
    expect(chart.semanticLabel, isNotNull);
    expect(chart.semanticLabel, matches(RegExp(r'τελευταία (0|[+−]\d,\d) °C$')));
  });

  // ------------------------------------------------------------------ R10-B2-3
  group('R10-B2-3: η σελίδα της μέτρησης «energy» με το όνομα της πηγής', () {
    final now = DateTime(2026, 11, 14, 10);
    final today = DateTime(2026, 11, 14);

    test('ο κανόνας του τίτλου', () {
      final spec = metricSpecs[K.energy]!;
      expect(metricPageTitle(spec, Source.watch), 'Energy Score');
      expect(metricPageTitle(spec, Source.none), 'Energy Score');
      expect(metricPageTitle(spec, Source.oura), 'Ετοιμότητα');
      expect(metricPageTitle(metricSpecs[K.hrv]!, Source.oura), 'HRV');
      expect(metricPageTitle(metricSpecs[K.sleepHr]!, Source.watch), 'Παλμοί στον ύπνο');
    });

    testWidgets('νύχτες του ρολογιού: «Energy Score» στον τίτλο και στη διαδρομή, χωρίς το «i» της Oura', (t) async {
      final s = HealthStore()
        ..history = {
          for (var i = 0; i < 10; i++) dateKey(_add(today, -i)): {K.energy: 70.0 + i},
        };
      expect(MetricPage.route(s, K.energy, now: now).settings.name, 'Μέτρηση · Energy Score');
      await _pump(t, MetricPage(store: s, spec: metricSpecs[K.energy]!, now: now));
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Energy Score')), findsOneWidget);
      expect(find.text('Ετοιμότητα'), findsNothing);
      expect(find.byKey(const ValueKey('info-${K.energy}')), findsNothing);
    });

    testWidgets('νύχτες του Oura: «Ετοιμότητα», με το «i»', (t) async {
      final s = HealthStore()
        ..history = {
          for (var i = 0; i < 10; i++) dateKey(_add(today, -i)): {ouraKeys[K.energy]!: 70.0 + i},
        };
      s.debugSetPlan(SourcePlan.samsungOnly.withEra(Source.oura, _add(today, -60)));
      expect(MetricPage.route(s, K.energy, now: now).settings.name, 'Μέτρηση · Ετοιμότητα');
      await _pump(t, MetricPage(store: s, spec: metricSpecs[K.energy]!, now: now));
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Ετοιμότητα')), findsOneWidget);
      expect(find.text('Energy Score'), findsNothing);
      expect(find.byKey(const ValueKey('info-${K.energy}')), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------ R10-B8-1 = R10-B2-B1
  group('R10-B8-1: «Η εβδομάδα σου» στο ανοιχτό Fold όρθιο (750 dp με την πλαϊνή μπάρα)', () {
    final mon = DateTime(2026, 11, 16, 9);

    HealthStore store() {
      final json = {
        ...sampleDashboardJson(mon),
        'body': [
          {'time': DateTime(2026, 11, 16, 7, 15).millisecondsSinceEpoch, 'weight': 82.0, 'fatPct': 27.0, 'app': _inbody},
        ],
      };
      final s = HealthStore()..data = Dashboard.fromJson(json);
      s.history = sampleHistory(mon, s.data!);
      applyRecentRead(s.history, s.data!, plan: SourcePlan.samsungOnly);
      s.setProfile(_me);
      return s;
    }

    testWidgets('σελίδα 652 dp (750 − 98 της μπάρας): κάρτα 596 dp, γραμμές σε δύο στήλες', (t) async {
      await _pump(
        t,
        TodayPage(store: store(), food: sampleFoodStore(mon), open: (_, [__]) {}, openSettings: () {}, now: mon),
        size: const Size(652, 4000),
      );
      final week = t.getRect(find.byType(WeekCard));
      // 652 − 2 × 28 = 596 dp περιεχομένου (δύο στήλες από 580)· η κάρτα κάτω από τις στήλες, σε όλο το πλάτος.
      expect(week.width, closeTo(596, 1));
      final rows = [
        for (final e in find.descendant(of: find.byType(WeekCard), matching: find.textContaining('4 προηγούμενες: ')).evaluate())
          t.getRect(find.byWidget(e.widget)),
      ];
      expect(rows.length, greaterThanOrEqualTo(2));
      // Πριν: εσωτερικό 560 < 600 → μία στήλη γραμμών 560 dp, όλες αριστερά.
      expect(rows.any((r) => r.left > week.center.dx), isTrue, reason: 'δεύτερη στήλη γραμμών');
      expect(rows.any((r) => r.left < week.center.dx), isTrue, reason: 'πρώτη στήλη γραμμών');
      expect(t.takeException(), isNull);
    });
  });

  // ------------------------------------------------------------------ R10-B8-2
  group('R10-B8-2: «συνδρομή Oura.» δεν σπάει', () {
    testWidgets('σε κάθε πλάτος 200–400 px η τελευταία γραμμή δεν είναι μόνο «Oura.»', (t) async {
      expect(ouraConnectPrivacyText, endsWith('συνδρομή\u00A0Oura.'));
      // Ίδια γράμματα με την κάρτα «Μένουν στο κινητό σου» (Inter 14,5, ύψος γραμμής 1,4). Πριν (κανονικό κενό): μόνο
      // «Oura.» στην τελευταία γραμμή σε 44 πλάτη από τα 201 (python, άπληστο σπάσιμο γραμμών), και στα ~325 της κάρτας
      // στα 400 dp (στιγμιότυπο 70).
      for (var w = 200; w <= 400; w++) {
        final tp = TextPainter(
          text: const TextSpan(
              text: ouraConnectPrivacyText, style: TextStyle(fontFamily: 'Inter', fontSize: 14.5, height: 1.4)),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: w.toDouble());
        final line = tp.getLineBoundary(TextPosition(offset: ouraConnectPrivacyText.length - 1));
        final text = ouraConnectPrivacyText.substring(line.start, line.end);
        tp.dispose();
        expect(text, contains('συνδρομή'), reason: 'πλάτος $w: «$text»');
      }
    });
  });

  // ------------------------------------------------------------------ R10-B8-B1
  group('R10-B8-B1 / R11-C2-3: «Άσκηση σήμερα»: αδιάσπαστο κενό μετά από κάθε «·» και στα λεπτά (όπως τα τρόφιμα)', () {
    Future<void> card(WidgetTester t, DateTime at) async {
      await t.runAsync(() => ExLibrary.load(inline: true));
      await _pump(t, SingleChildScrollView(child: TodayTrainingCard(training: sampleTraining(at), now: at)),
          size: const Size(400, 2400));
    }

    testWidgets('μέρα βαρών (Παρασκευή 13/11)', (t) async {
      await card(t, DateTime(2026, 11, 13, 17, 30));
      expect(find.textContaining(' ·\u00A0περίπου '), findsOneWidget);
      expect(find.textContaining(RegExp('περίπου \\d+\u00A0λεπτά ·\u00A0όριο\u00A0παλμών\u00A0140')), findsOneWidget);
    });

    testWidgets('μέρα περπατήματος (Τρίτη 17/11)', (t) async {
      await card(t, DateTime(2026, 11, 17, 17, 30));
      expect(find.textContaining('30\u00A0λεπτά ·\u00A0'), findsOneWidget);
      expect(find.textContaining(' ·\u00A0όριο\u00A0παλμών\u00A0140'), findsOneWidget);
    });
  });
}
