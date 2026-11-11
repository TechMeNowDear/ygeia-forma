// Τρίτος γύρος ελέγχου (4/11), κομμάτι F: συνέπεια ανάμεσα στις οθόνες, κλινικά κείμενα, PDF, αναζήτηση τροφίμων και
// αλάτι, UX. Κάθε διόρθωση με έλεγχο που αποτυγχάνει χωρίς αυτήν (F1–F10 στο audit3_reports/0_triage.md· F9 όχι).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/food/off.dart';
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/main.dart';
import 'package:ygeia_forma/nav.dart';
import 'package:ygeia_forma/oxygen_note.dart';
import 'package:ygeia_forma/pages/body.dart';
import 'package:ygeia_forma/pages/food_add.dart';
import 'package:ygeia_forma/pages/heart.dart';
import 'package:ygeia_forma/pages/move.dart';
import 'package:ygeia_forma/pages/my_foods.dart';
import 'package:ygeia_forma/pages/oura_today.dart';
import 'package:ygeia_forma/pages/oxygen_widgets.dart';
import 'package:ygeia_forma/pages/report_page.dart';
import 'package:ygeia_forma/pages/sleep.dart';
import 'package:ygeia_forma/pages/today.dart';
import 'package:ygeia_forma/pages/trends.dart';
import 'package:ygeia_forma/pages/unusual_card.dart';
import 'package:ygeia_forma/report.dart';
import 'package:ygeia_forma/shown.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/ti_ftanei.dart';
import 'package:ygeia_forma/trends.dart';
import 'package:ygeia_forma/unusual.dart';
import 'package:ygeia_forma/widgets.dart';

import 'sample_data.dart';
import 'sample_food.dart';

DateTime _add(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 2400)}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: w)));
  await t.pumpAndSettle();
}

/// Το δείγμα της εφαρμογής: Dashboard και ιστορικό όπως τα γράφει η εφαρμογή (οι 30 τελευταίες μέρες = summarizeDay).
final _now = DateTime(2026, 10, 24, 16, 30);

HealthStore _sample({Map<String, dynamic> Function(Map<String, dynamic>)? edit}) {
  final j = sampleDashboardJson(_now);
  final s = HealthStore()..data = Dashboard.fromJson(edit == null ? j : edit(j));
  s.history = sampleHistory(_now, s.data!);
  return s;
}

void main() {
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
  });

  // -------------------------------------------------------------------------
  group('F1/F3: ένας κανόνας για «όπως συνήθως» και διαφορές από τα νούμερα που φαίνονται', () {
    test('shownDiff / asUsual: διαφορά των στρογγυλεμένων, «όπως συνήθως» μόνο για 0', () {
      expect(shownDiff(60.4, 59.4), 1, reason: '60 − 59');
      expect(asUsual(60.4, 59.6), isTrue, reason: '60 − 60');
      expect(asUsual(60.0, 59.0), isFalse, reason: 'πριν, η Σήμερα του Oura έλεγε «όπως συνήθως» ως ±2');
      expect(shownDiff(82.24, 83.36, 1), -1.2, reason: '82,2 − 83,4 (πριν: −1,1 από τις ακατέργαστες)');
      expect(shownDiff(35.1, 34.7, 1), 0.4, reason: 'χωρίς υπόλοιπα κινητής υποδιαστολής (0,3999…)');
      expect(signedShown(-1.0), '−1');
      expect(signedShown(0.3, 1), '+0,3');
      expect(sleepVsUsualText(0), 'Όσο κοιμάσαι συνήθως');
      expect(sleepVsUsualText(-5), startsWith('5 λεπτά λιγότερο'), reason: 'πριν: «Όσο κοιμάσαι συνήθως» ως ±9 λεπτά');
    });

    testWidgets('Oura «Καρδιά και θερμοκρασία»: 60 με συνήθως 59 → «+1 · συνήθως 59», όπως στην Καρδιά (πριν: «όπως συνήθως»)',
        (t) async {
      final s = _sample();
      final from = DateTime(2026, 11, 1);
      final day = DateTime(2026, 11, 14);
      s.debugSetPlan(SourcePlan.samsungOnly.withEra(Source.oura, from));
      for (var i = 1; i <= 12; i++) {
        s.history[dateKey(_add(day, -i))] = {'o.sleepHr': 59, 'o.hrv': 39, 'o.skinTemp': 0.0};
      }
      s.history[dateKey(day)] = {'o.sleepHr': 60, 'o.hrv': 41, 'o.skinTemp': 0.3};
      await _pump(t, SingleChildScrollView(child: OuraRestCard(store: s, now: DateTime(2026, 11, 14, 10), onTap: () {})));
      expect(find.text('+1 · συνήθως 59'), findsOneWidget);
      expect(find.text('+2 · συνήθως 39'), findsOneWidget);
      expect(find.text('όπως συνήθως'), findsNothing);
      // F2: ίδια ετικέτα θερμοκρασίας με το «Εκτός συνηθισμένου».
      expect(find.text(ouraTempDeviationLabel), findsOneWidget);
    });

    testWidgets('F3: Σήμερα, βάρος 82,24 μετά από 83,36 → «−1,2 kg» (82,2 − 83,4), και στο Σώμα', (t) async {
      Map<String, dynamic> edit(Map<String, dynamic> j) {
        final body = j['body'] as List;
        (body[body.length - 2] as Map)['weight'] = 83.36;
        (body.last as Map)['weight'] = 82.24;
        return j;
      }

      await _pump(
        t,
        TodayPage(store: _sample(edit: edit), food: sampleFoodStore(_now), open: (_, [__]) {}, openSettings: () {}, now: _now),
      );
      final pill = t.widgetList<TrendPill>(find.byType(TrendPill)).firstWhere((p) => p.text.contains(' kg από '));
      expect(pill.text, startsWith('−1,2 kg'));

      await _pump(t, BodyPage(store: _sample(edit: edit)), size: const Size(400, 3000));
      final row = t.widgetList<InfoRow>(find.byType(InfoRow)).firstWhere((r) => r.label == 'Βάρος');
      expect(row.value, endsWith('(−1,2)'));
    });

    testWidgets('F3: Σήμερα, θερμοκρασία καρπού = διαφορά των νούμερων όπως φαίνονται (ίδια με το «Εκτός συνηθισμένου»)',
        (t) async {
      final s = _sample();
      s.prefs.cards['skin'] = true;
      final base = s.data!.skinTempBaseline!;
      // Μια τιμή όπου η ακατέργαστη διαφορά στρογγυλεύει αλλιώς από τη διαφορά των στρογγυλεμένων.
      double? pick;
      for (var k = 0; k < 200 && pick == null; k++) {
        final t0 = base + 0.6 + k * 0.001;
        if (signedDec(t0 - base) != signedDec(shownDiff(t0, base, 1))) pick = t0;
      }
      expect(pick, isNotNull);
      s.data!.lastNight!.skinTemp = pick;
      await _pump(t, TodayPage(store: s, food: sampleFoodStore(_now), open: (_, [__]) {}, openSettings: () {}, now: _now));
      final card = t.widgetList<StatCard>(find.byType(StatCard)).firstWhere((c) => c.title.startsWith('Θερμοκρασία καρπού'));
      expect(card.value, signedDec(shownDiff(pick!, base, 1)));
    });
  });

  // -------------------------------------------------------------------------
  group('F2: θερμοκρασία ως απόκλιση, ένας ορισμός', () {
    test('Oura: το «Εκτός συνηθισμένου» δείχνει την απόκλιση του Oura (συνήθως 0), όχι δεύτερη αφαίρεση', () {
      final day = DateTime(2026, 11, 30);
      final plan = SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 1));
      final h = <String, Map<String, double>>{};
      for (var i = 1; i <= 28; i++) {
        h[dateKey(_add(day, -i))] = {'o.skinTemp': -0.2 + (i % 3 - 1) * 0.05, 'o.sleepHr': 59.0 + (i % 2)};
      }
      h[dateKey(day)] = {'o.skinTemp': 0.3, 'o.sleepHr': 66};
      final s = checkUnusual(h, day, plan: plan).signals.firstWhere((s) => s.rule.key == K.skinTemp);
      expect(s.source, Source.oura);
      expect(s.usual, 0, reason: 'πριν: η μεσαία τιμή των προηγούμενων αποκλίσεων (−0,2) → «+0,5»');
      expect(shownDiff(s.value, s.usual, 1), 0.3);
    });

    testWidgets('Oura: η κάρτα λέει «+0,3 °C» και «απόκλιση από το συνηθισμένο (Oura)», χωρίς δεύτερο «χάπι» (U6)', (t) async {
      final r = UnusualResult(
        day: DateTime(2026, 11, 30),
        signals: [
          UnusualSignal(
              rule: unusualRules.firstWhere((r) => r.key == K.sleepHr),
              value: 66,
              usual: 59,
              spread: 1,
              threshold: 3,
              baselineCount: 20,
              source: Source.oura),
          UnusualSignal(
              rule: unusualRules.firstWhere((r) => r.key == K.skinTemp),
              value: 0.3,
              usual: 0,
              spread: 0.05,
              threshold: 0.4,
              baselineCount: 20,
              source: Source.oura),
        ],
        previousDayOff: false,
      );
      await _pump(t, SingleChildScrollView(child: UnusualCard(result: r)));
      expect(find.text('+0,3 °C'), findsOneWidget, reason: 'μία φορά: χωρίς «χάπι» που λέει το ίδιο');
      expect(find.textContaining(ouraTempDeviationLabel), findsOneWidget);
      expect(t.widgetList<TrendPill>(find.byType(TrendPill)).where((p) => p.text.contains('°C')), isEmpty);
      // F1: ο δείκτης που δεν ξεφεύγει αλλά διαφέρει δεν λέγεται «όπως συνήθως».
    });

    testWidgets('F1: «Εκτός συνηθισμένου»: 61 με συνήθως 59 (όχι εκτός) → «+2 bpm», όχι «Όπως συνήθως»', (t) async {
      final r = UnusualResult(
        day: DateTime(2026, 11, 30),
        signals: [
          UnusualSignal(
              rule: unusualRules.firstWhere((r) => r.key == K.sleepHr),
              value: 61,
              usual: 59,
              spread: 1,
              threshold: 3,
              baselineCount: 20),
        ],
        previousDayOff: false,
      );
      await _pump(t, SingleChildScrollView(child: UnusualCard(result: r)));
      expect(find.text('+2 bpm'), findsOneWidget);
      expect(find.text(asUsualText), findsNothing);
    });

    testWidgets('Τάσεις (ρολόι): η θερμοκρασία καρπού μόνο ως αλλαγή, ποτέ «35,2 °C»', (t) async {
      await _pump(t, TrendsPage(store: _sample(), now: _now), size: const Size(400, 4000));
      expect(find.textContaining(RegExp(r'3\d,\d °C')), findsNothing);
      expect(find.text('σε σχέση με πριν · όχι θερμοκρασία σώματος'), findsWidgets);
    });

    test('Τάσεις: χωρίς σύγκριση (λίγα δεδομένα) η θερμοκρασία καρπού είναι «—», όχι «0 °C»', () {
      final s = _sample();
      final r = computeTrend(metricDef(K.skinTemp)!, s.history, dayOf(_now), TrendPeriod.year);
      expect(r.status, TrendStatus.insufficient);
      expect(relativeTempText(r), '—');
      final m = computeTrend(metricDef(K.skinTemp)!, s.history, dayOf(_now), TrendPeriod.month);
      expect(relativeTempText(m), matches(RegExp(r'^[+−]\d,\d °C$')));
    });

    testWidgets('Σώμα: χωρίς «Ο μέσος όρος σου είναι 35,2 °C»· γράφημα απόκλισης από το «συνήθως»', (t) async {
      final s = _sample();
      await _pump(t, BodyPage(store: s), size: const Size(400, 4000));
      expect(find.textContaining('μέσος όρος σου'), findsNothing);
      expect(find.textContaining(RegExp(r'3\d,\d °C')), findsNothing);
      final chart = t.widget<LineChart>(find.descendant(of: find.byKey(const ValueKey('body-skin')), matching: find.byType(LineChart)));
      expect(chart.points.every((p) => p.$2.abs() < 5), isTrue, reason: 'αποκλίσεις, όχι ~35 °C');
    });
  });

  // -------------------------------------------------------------------------
  group('F4: μικρές ασυνέπειες', () {
    testWidgets('Καρδιά: παλιότερη νύχτα με ημερομηνία (όπως στη Σήμερα)', (t) async {
      final s = _sample();
      final nights = s.data!.nights;
      nights.last.sleepingHr = null;
      final shown = nights.lastWhere((n) => n.sleepingHr != null);
      await _pump(t, HeartPage(store: s, now: _now), size: const Size(400, 3000));
      expect(find.text('Παλμοί στον ύπνο · ${shortDayDate(shown.date)}'), findsOneWidget);
    });

    test('Μέσο οξυγόνο: ποτέ στρογγυλοποίηση προς τα πάνω στο 90%', () {
      expect(spo2AvgText(89.5), '89,5');
      expect(spo2AvgText(89.96), '89,9');
      expect(spo2AvgText(89.4), '89');
      expect(spo2AvgText(94.6), '95');
      expect(spo2AvgText(90.0), '90');
    });

    testWidgets('Ύπνος: μέσο οξυγόνο 89,6 → «89,6%», όχι «90%»', (t) async {
      final s = _sample();
      s.data!.lastNight!.spo2Avg = 89.6;
      await _pump(t, SleepPage(store: s, now: _now), size: const Size(400, 3200));
      expect(find.text('89,6%'), findsOneWidget);
    });

    test('«Εκτός συνηθισμένου»: η απόκλιση από τα νούμερα που φαίνονται (62 − 59 = 3), όπως το κόκκινο της Καρδιάς', () {
      final s = UnusualSignal(
        rule: unusualRules.firstWhere((r) => r.key == K.sleepHr),
        value: 61.87,
        usual: 59.225,
        spread: 1,
        threshold: 3,
        baselineCount: 28,
      );
      expect(s.off, isTrue, reason: 'πριν: 2,6 < 3, ενώ η Καρδιά έδειχνε «+3 bpm» με κόκκινο');
    });

    test('PDF: νύχτες χωρίς φάσεις μετριούνται μέρα-μέρα (διάρκεια χωρίς ώρα ύπνου δεν «τρώει» μία)', () {
      final now = DateTime(2026, 11, 20, 10);
      final h = <String, Map<String, double>>{
        for (var d = _add(dayOf(now), -30); !d.isAfter(dayOf(now)); d = _add(d, 1))
          dateKey(d): {K.sleepMin: 420, K.bedtime: 330},
      };
      h[dateKey(_add(dayOf(now), -3))]!.remove(K.sleepMin); // χωρίς φάσεις
      h[dateKey(_add(dayOf(now), -5))]!.remove(K.bedtime); // κρατημένη διάρκεια, χωρίς ώρα ύπνου
      expect(buildReport(h, now).nightsWithoutStages, 1, reason: 'πριν: 31 − 31 = 0');
    });

    testWidgets('PDF: μήνες με τον παλιό ορισμό του ύπνου σημειώνονται και στην αναφορά', (t) async {
      final s = _sample();
      s.prefs.staleMonths.add('2026-08-15');
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(680, 3600);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: ReportPage(store: s, now: _now)));
      await t.pumpAndSettle();
      expect((t.widget<Text>(find.byKey(const ValueKey('report-stale-months')))).data, staleMonthsNote(['2026-08-15']));
    });
  });

  // -------------------------------------------------------------------------
  group('F5: κείμενα άπνοιας και οξυγόνου', () {
    test('Οι δύο φράσεις για το τεστ άπνοιας φαίνονται χωρίς πάτημα· «αποφρακτική (όχι την κεντρική)» στο πλήρες', () {
      expect(oxygenAboutShort, contains('Ένα αρνητικό τεστ άπνοιας του ρολογιού δεν την αποκλείει'));
      expect(oxygenAboutShort, contains('κεντρική άπνοια'));
      expect(oxygenAboutText, contains('αποφρακτική άπνοια (όχι την κεντρική)'));
      expect(oxygenRepeatText(3, 5), contains('Ένα αρνητικό τεστ άπνοιας του ρολογιού δεν το αποκλείει'));
    });

    test('2 νύχτες < 80%: το μήνυμα λέει ποιες (ημερομηνία: τιμή), «μέσα στις τελευταίες 30 μέρες», χωρίς «ενήλικες»', () {
      final last = DateTime(2026, 10, 30);
      final g = oxygenGuidance({_add(last, -16): 72, _add(last, -6): 74.6, last: 91}, last);
      final m = g.messages.single;
      expect(m, contains('σε 2 νύχτες μέσα στις τελευταίες 30 μέρες (14/10: 72%, 24/10: 74,6%)'));
      expect(m, contains('ένα αρνητικό τεστ άπνοιας του ρολογιού δεν αποκλείει πρόβλημα στην αναπνοή στον ύπνο'));  // κλινικός έλεγχος 4, C2/C5
      expect(m, isNot(contains('ενήλικες')));
    });

    testWidgets('Ύπνος (ρολόι): και εδώ το «Τι σημαίνει» με τις φράσεις για την άπνοια', (t) async {
      await _pump(t, SleepPage(store: _sample(), now: _now), size: const Size(400, 3200));
      expect(find.byKey(const ValueKey('oxygen-about')), findsOneWidget);
      expect(find.textContaining(oxygenApneaShort), findsOneWidget);
    });

    testWidgets('Σήμερα: η κάρτα οξυγόνου εμφανίζεται μόνη της όταν το χαμηλό επαναλαμβάνεται (κλειστή στις Ρυθμίσεις)',
        (t) async {
      final s = _sample();
      expect(s.prefs.show('spo2'), isFalse);
      final nights = s.data!.nights;
      // Χωρίς τις χαμηλές του δείγματος, ώστε να μετρούν μόνο αυτές που βάζει ο έλεγχος.
      for (final n in nights) {
        if (n.spo2Min != null) n.spo2Min = 90;
      }
      nights[nights.length - 3].spo2Min = 72;
      nights[nights.length - 9].spo2Min = 74;
      await _pump(t, TodayPage(store: s, food: sampleFoodStore(_now), open: (_, [__]) {}, openSettings: () {}, now: _now));
      expect(find.byKey(const ValueKey('today-oxygen-auto')), findsOneWidget);
      expect(find.textContaining('Κάτω από 80% σε 2 νύχτες'), findsOneWidget);
    });

    testWidgets('Σήμερα: μία μόνο χαμηλή νύχτα δεν ανοίγει την κάρτα', (t) async {
      final s = _sample();
      for (final n in s.data!.nights) {
        if (n.spo2Min != null) n.spo2Min = 90;
      }
      s.data!.nights[s.data!.nights.length - 3].spo2Min = 72;
      await _pump(t, TodayPage(store: s, food: sampleFoodStore(_now), open: (_, [__]) {}, openSettings: () {}, now: _now));
      expect(find.byKey(const ValueKey('today-oxygen-auto')), findsNothing);
    });

    test('Ρυθμίσεις: η ετικέτα λέει ότι η κάρτα εμφανίζεται μόνη της', () {
      expect(todayCards.firstWhere((c) => c.key == 'spo2').label, contains('εμφανίζεται μόνο του'));
    });

    testWidgets('Το κλειστό κείμενο δείχνει τις φράσεις για την άπνοια', (t) async {
      await _pump(t, const SingleChildScrollView(child: OxygenAbout()));
      expect(find.textContaining('δεν την αποκλείει'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('F6: PDF', () {
    final now = DateTime(2026, 11, 20, 10);
    Map<String, Map<String, double>> history() {
      final h = <String, Map<String, double>>{};
      var i = 0;
      for (var d = _add(dayOf(now), -120); !d.isAfter(dayOf(now)); d = _add(d, 1)) {
        h[dateKey(d)] = {
          // 40 νύχτες κάτω από 85% (πάνω από τις 30 της λίστας) και 3 κάτω από 80%, οι τελευταίες.
          K.spo2Min: i % 3 == 0 ? 84 : 91,
          K.spo2Avg: 95,
          K.steps: 5000,
          if (i > 60) K.sleepHr: 60,
        };
        i++;
      }
      for (final ago in [2, 5, 9]) {
        h[dateKey(_add(dayOf(now), -ago))]![K.spo2Min] = 75;
      }
      return h;
    }

    Future<HealthStore> pumpReport(WidgetTester t) async {
      final s = _sample()..history = history();
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(680, 3600);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: ReportPage(store: s, now: now)));
      await t.pumpAndSettle();
      return s;
    }

    testWidgets('C8: όλα τα γραφήματα έχουν τις ίδιες 90 μέρες στον άξονα', (t) async {
      await pumpReport(t);
      final r = buildReport(history(), now);
      final charts = t.widgetList<LineChart>(find.byType(LineChart)).toList();
      expect(charts, isNotEmpty);
      for (final c in charts) {
        expect(c.from, r.from);
        expect(c.to, r.to);
      }
    });

    testWidgets('C9: η χαμηλότερη μέτρηση δεν έχει σκέτη «—» στη «Διαφορά»', (t) async {
      await pumpReport(t);
      expect(find.text('Δεν συγκρίνεται (σελ. 3)'), findsOneWidget);
    });

    test('C9: με αλλαγή ορισμού, ίδια λέξη με το μέσο οξυγόνο', () {
      final r = buildReport(history(), now, plan: SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 6)));
      expect(lowestDiffText(r.stat(K.spo2Min)), 'Αλλαγή ορισμού');
    });

    testWidgets('C6: σελίδα 3 όπως η πηγή (ιατρικό οξύμετρο, ηλικία), και ΟΛΕΣ οι νύχτες κάτω από 80% με ημερομηνία',
        (t) async {
      await pumpReport(t);
      expect(find.textContaining('οξύμετρο δαχτύλου'), findsNothing);
      expect(find.textContaining('στους άνω των 60 οι τιμές ήταν χαμηλότερες'), findsOneWidget);
      final below80 = t.widget<Text>(find.byKey(const ValueKey('report-oxygen-below80'))).data!;
      for (final ago in [9, 5, 2]) {
        final d = _add(dayOf(now), -ago);
        expect(below80, contains('${d.day}/${d.month}/${d.year}: 75%'));
      }
      // Στη λίστα του 85% (ως 30) οι κάτω από 80% μπαίνουν πάντα.
      final wrap = t.widget<Wrap>(find.byKey(const ValueKey('report-oxygen-below85')));
      final texts = [for (final w in wrap.children) if (w is Text) w.data!];
      expect(texts.where((s) => s.endsWith(': 75%')).length, 3);
    });

    testWidgets('C11: η υπόδειξη της σημείωσης ζητά και το χαμηλό οξυγόνο του Samsung Health', (t) async {
      await pumpReport(t);
      expect(t.widget<TextField>(find.byKey(const ValueKey('report-note'))).decoration!.hintText,
          contains('χαμηλό οξυγόνο που είδες στο Samsung Health'));
    });
  });

  // -------------------------------------------------------------------------
  group('F7: αναζήτηση τροφίμων και αλάτι (τρίτος έλεγχος διατροφής N1, N2, N4–N7)', () {
    final store = FoodStore.preloaded(foods: basicFoods(), now: DateTime(2026, 11, 4, 13));
    String first(String q) => store.search(q).first.name;
    List<String> top(String q, int n) => [for (final f in store.search(q).take(n)) f.name];

    test('Πλήθος τροφίμων: 323 + 23 ψάρια, θαλασσινά και κεφίρ (έλεγχος 8/11, FOOD-02)', () {
      expect(basicFoods().length, 375); // + 24 τρόφιμα του ελέγχου 9/11 (fix-food) + πίτουρο βρώμης (12/11)
    });

    test('N1: «κοτόπουλο ψητό» → ψητό στήθος· «κοτόπουλο φούρνου» → ολόκληρο', () {
      expect(first('κοτόπουλο ψητό'), 'Κοτόπουλο στήθος χωρίς πέτσα (ψητό στο τηγάνι/σχάρα)');
      expect(first('kotopoulo psito'), 'Κοτόπουλο στήθος χωρίς πέτσα (ψητό στο τηγάνι/σχάρα)');
      expect(first('κοτόπουλο φούρνου'), 'Κοτόπουλο ολόκληρο με πέτσα (ψητό)');
      expect(first('κοτόπουλο'), 'Κοτόπουλο στήθος χωρίς πέτσα (ωμό)', reason: 'όπως πριν');
    });

    test('N2: «παγωτό» → παγωτό, όχι frozen yogurt', () {
      expect(first('παγωτό'), 'Παγωτό, σορμπέ ή γρανίτα (μέσος όρος)');
    });

    test('N4: «τυρί» → φέτα (όχι τυρί κρέμα)· «τυρί κρέμα» → τυρί κρέμα', () {
      expect(first('τυρί'), 'Φέτα (πρόβειο και κατσικίσιο)');
      expect(first('tiri'), 'Φέτα (πρόβειο και κατσικίσιο)');
      expect(first('τυρί κρέμα'), 'Τυρί κρέμα για άλειμμα');
    });

    test('N4: «βούτυρο» → βούτυρο, φυστικοβούτυρο· όχι το γάλα από το «…βουτυρωμένο»', () {
      expect(top('βούτυρο', 2), ['Βούτυρο ανάλατο', 'Φυστικοβούτυρο']);
      expect(top('voutiro', 2), ['Βούτυρο ανάλατο', 'Φυστικοβούτυρο']);
      expect(first('γάλα'), 'Γάλα ημιαποβουτυρωμένο 1,5%', reason: 'η προτίμηση μένει όπου ταιριάζει η λέξη');
    });

    test('N4: «φρυγανιά» → φρυγανιές· «τριμμένη φρυγανιά» → η τριμμένη· «μπέργκερ» → χάμπουργκερ', () {
      expect(first('φρυγανιά'), 'Φρυγανιές');
      expect(first('τριμμένη φρυγανιά'), 'Τριμμένη φρυγανιά');
      expect(first('μπέργκερ'), 'Χάμπουργκερ (fast food)');
      expect(first('ψωμάκι μπέργκερ'), 'Ψωμάκι για μπέργκερ');
    });

    test('N5: greeklish και αγγλικά', () {
      expect(first('beer'), 'Μπίρα');
      expect(first('yiaourti'), startsWith('Γιαούρτι'));
      expect(first('yaourti'), startsWith('Γιαούρτι'));
      expect(first('yogurt'), startsWith('Γιαούρτι'));
      expect(first('spaghetti'), 'Μακαρόνια (ξηρά, ωμά)');
      expect(top('πένες', 2), ['Μακαρόνια (ξηρά, ωμά)', 'Μακαρόνια (βρασμένα, χωρίς αλάτι)']);
      expect(first('olive oil'), startsWith('Ελαιόλαδο'));
      expect(first('wine'), 'Κρασί κόκκινο');
      expect(first('chocolate'), startsWith('Σοκολάτα'));
      expect(first('sugar'), startsWith('Ζάχαρη'));
      expect(first('water'), 'Νερό');
    });

    testWidgets('N6: το αλάτι της βάσης λέγεται «από νάτριο × 2,5» και φαίνεται το νάτριο', (t) async {
      final f = basicFoods().firstWhere((f) => f.id == 'C12066');
      await _pump(t, FoodDetailScreen(food: f), size: const Size(400, 2400));
      expect(find.text(saltFromSodiumLabel), findsOneWidget);
      expect(find.text('Νάτριο'), findsOneWidget);
      expect(find.text('Αλάτι'), findsNothing);
    });

    test('N7: Open Food Facts: αλάτι από νάτριο, «ανά 100 ml» από τη βάση των τιμών, kcal 0 με kJ = λείπει', () {
      final d = draftFromOff('1', {
        'nutriments': {'energy-kcal_100g': 0, 'energy_100g': 1000, 'sodium_100g': 0.4},
      });
      expect(d.values[Nk.salt], 1.0);
      expect(d.saltFromSodium, isTrue);
      expect(d.values[Nk.kcal], closeTo(239.0, 0.05));
      expect(draftFromOff('1', {'nutriments': {'salt_100g': 1.2, 'sodium_100g': 0.4}}).saltFromSodium, isFalse);
      // Έλεγχος 8/11 (FOOD-01): το OFF στέλνει πάντα «100g»· για υγρά οι τιμές είναι ανά 100 ml.
      expect(
        draftFromOff('1', {'quantity': '1 l', 'nutrition_data_per': '100g', 'nutriments': {'energy-kcal_100g': 824}}).perMl,
        isTrue,
        reason: 'ελαιόλαδο 1 l: οι τιμές του OFF είναι ανά 100 ml',
      );
      expect(draftFromOff('1', {'quantity': '500 g', 'nutrition_data_per': '100g', 'nutriments': {}}).perMl, isFalse);
      expect(draftFromOff('1', {'quantity': '500 g', 'nutrition_data_per': '100ml', 'nutriments': {}}).perMl, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  group('F8: UX', () {
    testWidgets('U1: Άσκηση: ο τίτλος δεν κόβεται· η ημερομηνία σε δική της γραμμή', (t) async {
      final s = _sample();
      await _pump(t, ExercisePage(store: s), size: const Size(860, 2400));
      expect(find.text('Ενεργός χρόνος'), findsOneWidget);
      expect(find.textContaining('Ενεργός χρόνος ·'), findsNothing);
    });

    testWidgets('U2: Τάσεις χωρίς αρκετές μέρες: «δεν υπάρχουν αρκετές μετρήσεις», όχι «καμία διαφορά»', (t) async {
      final s = _sample();
      s.history = {
        for (var i = 0; i < 5; i++) dateKey(_add(dayOf(_now), -i)): {K.sleepHr: 60.0, K.steps: 5000.0},
      };
      await _pump(t, TrendsPage(store: s, now: _now), size: const Size(400, 4000));
      expect(find.text(noComparisonText(TrendPeriod.month)), findsOneWidget);
      expect(find.textContaining('Καμία διαφορά δεν πέρασε'), findsNothing);
    });

    testWidgets('U5: ίδιο όνομα «Από ετικέτα» για την ίδια ενέργεια', (t) async {
      await _pump(t, MyFoodsScreen(food: sampleFoodStore(_now)));
      expect(find.text('Από ετικέτα'), findsOneWidget);
      expect(find.text('Χειροκίνητα'), findsNothing);
    });

    test('U7: σύντομα ονόματα γευμάτων', () {
      expect(mealLabel(Meal.lunch), 'Μεσημέρι');
      expect(mealLabel(Meal.dinner), 'Βράδυ');
    });

    test('U9: «Τι φτάνει»: χωρίς «SDK», τελεία χιλιάδων, «αγνοείται 1»', () {
      expect(unsupportedText, isNot(contains('SDK')));
      expect(countNumber(1965), '1.965');
      expect(countNumber(1965.4), '1.965');
      expect(countedIgnoredText(3, 1, 'μόνο ρολόι'), 'Μετρούν 3 · αγνοείται 1 από άλλη πηγή (μόνο ρολόι)');
      expect(countedIgnoredText(1965, 2, 'μόνο InBody'), 'Μετρούν 1.965 · αγνοούνται 2 από άλλη πηγή (μόνο InBody)');
    });

    test('U3: μία φράση για το κενό που ίσως ήταν ύπνος', () {
      expect(possibleSleepPhrase, 'ίσως ύπνος χωρίς καταγραφή (δεν μετρά)');
    });

    testWidgets('U10: Καρδιά στο tablet: το οξυγόνο στην αριστερή στήλη, κάτω από τους παλμούς ύπνου', (t) async {
      await _pump(t, HeartPage(store: _sample(), now: _now), size: const Size(1280, 2400));
      expect(t.getTopLeft(find.text('Οξυγόνο στον ύπνο')).dx, lessThan(640));
      expect(t.getTopLeft(find.text('Τελευταίες μετρήσεις')).dx, greaterThan(640));
    });

    testWidgets('U11: Διατροφή στο tablet: η σύνοψη δεξιά (κοντή στήλη κάτω από το «+ Φαγητό»), τα γεύματα αριστερά',
        (t) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(1280, 2400);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Shell(store: _sample(), food: sampleFoodStore(_now), initialIndex: Cat.food, now: _now),
      ));
      await t.pumpAndSettle();
      final summary = t.getTopLeft(find.text('Σύνολο ημέρας')).dx;
      final meal = t.getTopLeft(find.text('Μεσημέρι').last).dx;
      expect(summary, greaterThan(meal + 200), reason: 'η σύνοψη στη δεξιά στήλη, τα γεύματα στην αριστερή');
    });
  });

  // -------------------------------------------------------------------------
  // F10: ίδια νύχτα, ίδια νούμερα σε κάθε οθόνη και στους υπολογισμούς των Τάσεων και του PDF.
  group('F10: συνέπεια ανάμεσα στις οθόνες', () {
    testWidgets('Παλμοί ύπνου, διάρκεια, χαμηλότερο οξυγόνο, απόκλιση θερμοκρασίας: Σήμερα = Καρδιά = Ύπνος = «Εκτός '
        'συνηθισμένου» = Τάσεις = PDF', (t) async {
      final s = _sample();
      s.prefs.cards['rhr'] = true;
      s.prefs.cards['spo2'] = true;
      s.prefs.cards['skin'] = true;
      final d = s.data!;
      final n = d.lastNight!;
      final today = dayOf(_now);
      expect(dayOf(n.date), today, reason: 'το δείγμα έχει τη νύχτα του σημερινού πρωινού');
      expect(n.sleepingHr, isNotNull);
      expect(n.spo2Min, isNotNull);
      expect(n.skinTemp, isNotNull);
      final hr = '${n.sleepingHr!.round()}';
      final low = '${lowestText(n.spo2Min!)}%';

      // Σήμερα
      await _pump(t, TodayPage(store: s, food: sampleFoodStore(_now), open: (_, [__]) {}, openSettings: () {}, now: _now),
          size: const Size(400, 4000));
      final cards = t.widgetList<StatCard>(find.byType(StatCard)).toList();
      expect(cards.firstWhere((c) => c.title.startsWith('Παλμοί στον ύπνο')).value, hr);
      final todayTemp = cards.firstWhere((c) => c.title.startsWith('Θερμοκρασία καρπού')).value;
      final todayLow = t.widgetList<TrendPill>(find.byType(TrendPill)).firstWhere((p) => p.text.startsWith('Χαμηλότερη μέτρηση')).text;
      expect(todayLow, contains(low));
      expect(t.widgetList<DurationValue>(find.byType(DurationValue)).first.minutes, n.minutes);

      // Καρδιά
      await _pump(t, HeartPage(store: s, now: _now), size: const Size(400, 3000));
      expect(t.widgetList<BigValue>(find.byType(BigValue)).first.value, hr);
      expect(find.byKey(const ValueKey('heart-oxygen-columns')), findsOneWidget);
      final heartRow = t.widgetList<InfoRow>(find.byType(InfoRow)).firstWhere((r) => r.label == shortDayDate(n.date));
      expect(heartRow.value, endsWith('· $low'));

      // Ύπνος
      await _pump(t, SleepPage(store: s, now: _now), size: const Size(400, 3200));
      final rows = t.widgetList<InfoRow>(find.byType(InfoRow)).toList();
      expect(rows.firstWhere((r) => r.label == 'Παλμοί στον ύπνο').value, '$hr bpm');
      expect(rows.firstWhere((r) => r.label == 'Οξυγόνο τη νύχτα, χαμηλότερη τιμή').value, startsWith(low));
      expect(t.widgetList<DurationValue>(find.byType(DurationValue)).first.minutes, n.minutes);

      // «Εκτός συνηθισμένου» (από το ιστορικό, όπως η κάρτα)
      final u = checkUnusual(s.history, today, plan: s.analysisPlan);
      final uHr = u.signals.firstWhere((x) => x.rule.key == K.sleepHr);
      expect('${uHr.value.round()}', hr);
      final uTemp = u.signals.firstWhere((x) => x.rule.key == K.skinTemp);
      expect(signedDec(shownDiff(uTemp.value, uTemp.usual, 1)), todayTemp,
          reason: 'ίδια απόκλιση θερμοκρασίας στη Σήμερα και στο «Εκτός συνηθισμένου»');

      // Τάσεις: το τελευταίο σημείο είναι η ίδια νύχτα
      final trHr = computeTrend(metricDef(K.sleepHr)!, s.history, today, TrendPeriod.month, plan: s.analysisPlan).points.last;
      expect(dayOf(trHr.$1), today);
      expect('${trHr.$2.round()}', hr);
      // Διάρκεια στις Τάσεις και στο PDF μόνο για νύχτα με φάσεις (αλλιώς δεν μπαίνει πουθενά, C13).
      if (n.staged) {
        final trMin = computeTrend(metricDef(K.sleepMin)!, s.history, today, TrendPeriod.month, plan: s.analysisPlan).points.last;
        expect(trMin.$2.round(), n.minutes);
      }

      // PDF
      final r = buildReport(s.history, _now, plan: s.analysisPlan);
      expect('${r.stat(K.sleepHr).values.last.$2.round()}', hr);
      if (n.staged) expect(r.stat(K.sleepMin).values.last.$2.round(), n.minutes);
      expect('${lowestText(r.stat(K.spo2Min).values.last.$2)}%', low);
      expect(dayOf(r.stat(K.spo2Min).values.last.$1), today);
    });
  });
}
