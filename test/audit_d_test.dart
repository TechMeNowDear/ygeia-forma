// Δεύτερος γύρος ελέγχου (4/11), κομμάτι D: κλινικά κείμενα, υπολογισμοί στην οθόνη, PDF για γιατρό, αναζήτηση
// τροφίμων, UX. Κάθε διόρθωση με έλεγχο που αποτυγχάνει χωρίς αυτήν (D1–D13 στο audit2_reports/0_triage.md).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/backup.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_search.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/food/off.dart';
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/heart_day.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/oura/oura_api.dart';
import 'package:ygeia_forma/oura/oura_model.dart';
import 'package:ygeia_forma/oura/oura_view.dart';
import 'package:ygeia_forma/oxygen_note.dart';
import 'package:ygeia_forma/pages/heart.dart';
import 'package:ygeia_forma/pages/oura_today.dart';
import 'package:ygeia_forma/pages/oxygen_widgets.dart';
import 'package:ygeia_forma/pages/report_page.dart';
import 'package:ygeia_forma/pages/sleep.dart';
import 'package:ygeia_forma/pages/today.dart';
import 'package:ygeia_forma/pages/unusual_card.dart';
import 'package:ygeia_forma/pages/week_card.dart';
import 'package:ygeia_forma/report.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/trends.dart';
import 'package:ygeia_forma/unusual.dart';
import 'package:ygeia_forma/weekly.dart';
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

void main() {
  final today = DateTime(2026, 11, 4);
  DateTime day(int ago) => _add(today, -ago);

  // -------------------------------------------------------------------------
  group('D2/D3: σημειώσεις οξυγόνου (δεύτερος κλινικός έλεγχος K2, K3, M1, M2, M3)', () {
    test('K2: κάτω από 80% σε 2 από τις 30 τελευταίες νύχτες → «πες το στον γιατρό σου» (πριν: ποτέ)', () {
      final g = oxygenGuidance({for (var i = 0; i < 30; i++) day(i): i == 3 ? 75.0 : (i == 20 ? 78.0 : 90.0)}, today);
      expect(g.veryLowNights30, 2);
      expect(g.veryLowRepeated, isTrue);
      expect(g.messages, [oxygenVeryLowRepeatText(2)]);
      expect(g.messages.single, contains('σε 2 από τις 30 τελευταίες νύχτες'));
      expect(g.short, contains('30 μέρες'));
    });

    test('K3: ΕΝΑ μήνυμα όταν ισχύουν πολλά (τελευταία νύχτα 72%, 74% και 83% στην ίδια εβδομάδα)', () {
      final g = oxygenGuidance({day(0): 72, day(2): 74, day(4): 83, day(5): 91}, today);
      expect(g.messages.length, 1);
      expect(g.messages.single, oxygenVeryLowRepeatText(2), reason: 'το σημαντικότερο: δύο νύχτες κάτω από 80%');
      expect(g.messages.single, isNot(contains('δες αν επαναλαμβάνεται')));
    });

    test('M2: μόνο νύχτες με μέτρηση στον παρονομαστή («3 από τις 3», ποτέ «3 από 7»)', () {
      final g = oxygenGuidance({day(0): 84, day(1): 83, day(2): 82}, today);
      expect(g.measuredNights, 3);
      expect(g.messages.single, contains('σε 3 από τις 3 νύχτες με μέτρηση'));
      expect(g.messages.single, isNot(contains('όλες τις νύχτες')));
      expect(g.short, 'Κάτω από 85% σε 3 από 3 νύχτες · δες την Καρδιά');
    });

    test('M1: τρεις νύχτες στο 87% δεν βγάζουν σημείωση (όριο 85%, όχι 88%)', () {
      final g = oxygenGuidance({day(0): 87, day(1): 87, day(2): 87.9, day(3): 90}, today);
      expect(g.any, isFalse);
      expect(oxygenLow, 85);
    });

    test('K2: μία νύχτα κάτω από 80%: ουδέτερο, χωρίς «συνήθως λάθος του αισθητήρα»', () {
      final g = oxygenGuidance({day(0): 77, day(1): 91}, today, today: today);
      expect(g.messages, [oxygenVeryLowText]);
      expect(oxygenVeryLowText, isNot(contains('Συνήθως')));
      expect(oxygenVeryLowText, contains('από μία νύχτα δεν ξεχωρίζει'));
    });

    test('Παλιότερη νύχτα δεν λέγεται «χθεσινή» (UX U5)', () {
      final g = oxygenGuidance({day(2): 77}, day(2), today: today);
      expect(g.messages.single, isNot(contains('χθεσινή')));
      expect(g.messages.single, contains(shortDayDate(day(2))));
    });

    test('M3: το κείμενο για το τεστ άπνοιας λέει ευαισθησία, για ποιους δεν προορίζεται, πίεση και αρρυθμία', () {
      expect(oxygenAboutText, contains('χάνει περίπου 1 στους 6'));
      expect(oxygenAboutText, contains('κολπική μαρμαρυγή, καρδιακή ανεπάρκεια ή πάθηση των πνευμόνων'));
      expect(oxygenAboutText, contains('υψηλή πίεση ή αρρυθμία'));
      expect(oxygenAboutText, isNot(contains('συχνά λάθος μέτρησης')));
    });

    test('Οι νύχτες για τον κανόνα των 30 έρχονται από τα δεδομένα (πριν μόνο 7)', () {
      final now = DateTime(2026, 10, 24, 16, 30);
      final d = Dashboard.fromJson(sampleDashboardJson(now));
      final m = d.spo2MinByNight(d.lastNight!.date);
      expect(m.length, greaterThan(7));
      expect(m.keys.every((k) => !k.isBefore(_add(dayOf(d.lastNight!.date), -29))), isTrue);
    });

    testWidgets('U9: το πλήρες κείμενο του οξυγόνου ανοίγει με «Τι σημαίνει»', (t) async {
      await _pump(t, const SingleChildScrollView(child: OxygenAbout(lead: 'Μέσο ανά νύχτα.')));
      expect(find.textContaining('χάνει περίπου 1 στους 6'), findsNothing);
      expect(find.textContaining(oxygenAboutShort), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('oxygen-about-toggle')));
      await t.pumpAndSettle();
      expect(find.textContaining('χάνει περίπου 1 στους 6'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('D1/D4/D8/D10: αναφορά για γιατρό', () {
    final now = DateTime(2026, 11, 20, 10);
    final ouraFrom = DateTime(2026, 11, 6);
    final plan = SourcePlan.samsungOnly.withEra(Source.oura, ouraFrom);

    Map<String, Map<String, double>> history() {
      final h = <String, Map<String, double>>{};
      for (var d = _add(dayOf(now), -120); !d.isAfter(dayOf(now)); d = _add(d, 1)) {
        final before = d.isBefore(ouraFrom);
        h[dateKey(d)] = {
          K.spo2Min: before ? 88 : 91,
          K.spo2Avg: before ? 94 : 95,
          K.steps: 5000,
          if (before) K.sleepMin: 400,
          if (before) K.bedtime: 330,
          if (!before) 'o.sleepMin': 420,
        };
      }
      // Οι νύχτες που ήταν ο λόγος της επίσκεψης, πριν από το Oura.
      h[dateKey(DateTime(2026, 10, 12))]![K.spo2Min] = 72;
      h[dateKey(DateTime(2026, 10, 19))]![K.spo2Min] = 74;
      h[dateKey(DateTime(2026, 10, 25))]![K.spo2Min] = 84.6;
      // Δύο νύχτες χωρίς φάσεις: ώρα ύπνου αλλά όχι διάρκεια.
      h[dateKey(DateTime(2026, 10, 1))]!.remove(K.sleepMin);
      h[dateKey(DateTime(2026, 10, 2))]!.remove(K.sleepMin);
      return h;
    }

    test('K1: το οξυγόνο καλύπτει όλες τις 90 μέρες, με ένα κομμάτι για κάθε ορισμό της νύχτας', () {
      final r = buildReport(history(), now, plan: plan);
      final s = r.stat(K.spo2Min);
      expect(s.n, 90, reason: 'πριν: μόνο οι νύχτες από τη σύνδεση του Oura');
      expect(s.since, isNull);
      expect(s.periods.length, 2);
      expect(s.periods.first.night, Source.watch);
      expect(s.periods.first.to, _add(ouraFrom, -1));
      expect(s.periods.last.night, Source.oura);
      expect(s.periods.last.from, ouraFrom);
      expect(s.periods.first.stat.n + s.periods.last.stat.n, 90);
      expect(r.stat(K.spo2Avg).trend?.status, TrendStatus.sourceChange, reason: 'η «Διαφορά» μένει «Αλλαγή ορισμού»');
      expect(r.stat(K.spo2Avg).n, 90);
      // Η διάρκεια ύπνου (άλλη συσκευή) μένει μία πηγή, κομμένη στην αλλαγή.
      expect(r.stat(K.sleepMin).since, ouraFrom);
    });

    test('M4: ζώνες 90/85/80 και νύχτες κάτω από 85% με χρονολογική σειρά (84,6 μετρά)', () {
      final r = buildReport(history(), now, plan: plan);
      expect([for (final n in r.oxygenBelow(85)) dateKey(n.$1)], ['2026-10-12', '2026-10-19', '2026-10-25']);
      expect(r.oxygenBelow(80).length, 2);
      expect(r.lowOxygenNights.first.$1.isBefore(r.lowOxygenNights.last.$1), isTrue, reason: 'χρονολογικά, όχι κατά τιμή');
    });

    test('C10: νύχτες χωρίς φάσεις μετριούνται και λέγονται', () {
      final r = buildReport(history(), now, plan: SourcePlan.samsungOnly);
      expect(r.nightsWithoutStages, greaterThanOrEqualTo(2));
    });

    test('C12: ίδια τελευταία μέρα με τις Τάσεις· η ώρα δημιουργίας μένει η τωρινή', () {
      final r = buildReport(history(), now, plan: plan, end: _add(dayOf(now), -1));
      expect(r.to, _add(dayOf(now), -1));
      expect(r.created, now);
      expect(r.stat(K.spo2Min).values.last.$1, _add(dayOf(now), -1));
    });

    testWidgets('PDF: όνομα (μόνο στο κινητό), σημείωση 400, πίεση, ζώνες, κατά προσέγγιση, χωρίς στρογγυλοποίηση', (t) async {
      final store = HealthStore()
        ..data = Dashboard.fromJson(sampleDashboardJson(now))
        ..history = history();
      store.debugSetPlan(plan);
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(680, 3600);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: ReportPage(store: store, now: now)));
      await t.pumpAndSettle();

      expect(t.widget<TextField>(find.byKey(const ValueKey('report-note'))).maxLength, 400);
      expect(t.widget<TextField>(find.byKey(const ValueKey('report-note'))).decoration!.hintText, contains('τεστ άπνοιας'));
      expect(find.textContaining('μετρήσεις πίεσης'), findsWidgets);
      expect(find.text('Μέρες'), findsOneWidget, reason: 'όχι «Μέρες με / μέτρηση» που έσπαγε');
      expect(find.textContaining('κατά προσέγγιση'), findsOneWidget);
      expect(find.textContaining('90,4% ± 3,1%'), findsOneWidget);
      expect((t.widget<Text>(find.byKey(const ValueKey('report-oxygen-counts')))).data, contains('κάτω από 85%'));
      expect(find.byKey(const ValueKey('report-oxygen-definition')), findsOneWidget);

      await t.enterText(find.byKey(const ValueKey('report-name')), 'Γιάννης Π.');
      await t.pump();
      expect(find.textContaining('Γιάννης Π. · '), findsNWidgets(3), reason: 'σε κάθε σελίδα');
      await t.pumpWidget(const SizedBox());
      expect(store.prefs.reportName, 'Γιάννης Π.');
      expect(store.prefs.toJson(), contains('reportName'));
      expect(backupPrefKeys.contains('reportName'), isFalse, reason: 'μένει μόνο στο κινητό');
    });
  });

  testWidgets('C5/L2: PDF σελ. 1: η μεσαία τιμή του ελάχιστου οξυγόνου 89,5 → «89,5%», ποτέ «90%»', (t) async {
    final now = DateTime(2026, 11, 20, 10);
    final h = <String, Map<String, double>>{};
    var i = 0;
    for (var d = _add(dayOf(now), -89); !d.isAfter(dayOf(now)); d = _add(d, 1)) {
      h[dateKey(d)] = {K.spo2Min: i++.isEven ? 89 : 90, K.spo2Avg: 95};
    }
    final store = HealthStore()
      ..data = Dashboard.fromJson(sampleDashboardJson(now))
      ..history = h;
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(680, 3600);
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: ReportPage(store: store, now: now)));
    await t.pumpAndSettle();
    expect(find.text('89,5%'), findsOneWidget);
    expect(find.text('90%'), findsNothing);
  });

  // -------------------------------------------------------------------------
  group('D5/D9: «Εκτός συνηθισμένου», ένα «συνήθως»', () {
    UnusualSignal sig(String key, double value, double usual, {Source source = Source.watch}) => UnusualSignal(
          rule: unusualRules.firstWhere((r) => r.key == key),
          value: value,
          usual: usual,
          spread: 0.1,
          threshold: 0.3,
          baselineCount: 20,
          source: source,
        );

    testWidgets('M7: θερμοκρασία καρπού ως απόκλιση, ποτέ «35,9 °C»· C6: διαφορά των νούμερων που φαίνονται', (t) async {
      final r = UnusualResult(day: today, signals: [sig(K.sleepHr, 61.6, 58.4), sig(K.skinTemp, 35.9, 35.2)], previousDayOff: false);
      await _pump(t, SingleChildScrollView(child: UnusualCard(result: r)));
      expect(find.textContaining('35,9'), findsNothing);
      expect(find.text('+0,7 °C'), findsWidgets);
      expect(find.textContaining('όχι θερμοκρασία σώματος'), findsOneWidget);
      expect(find.text('62 bpm'), findsOneWidget);
      expect(find.text('συνήθως 58 bpm'), findsOneWidget);
      expect(find.text('+4 bpm'), findsOneWidget, reason: '62 − 58 = 4 (πριν: «+3» από 61,6 − 58,4)');
    });

    test('C7: «συνήθως» = μεσαία τιμή έως 14 προηγούμενων (≥ 7), και στο «Εκτός συνηθισμένου»', () {
      expect(usualOf([60, 60, 60, 60, 60, 61, 90]), 60, reason: 'μέσος όρος θα ήταν 64,4');
      expect(usualOf([60, 60, 60, 60, 60, 61]), isNull);
      final h = <String, Map<String, double>>{};
      for (var i = 1; i <= 28; i++) {
        h[dateKey(day(i))] = {K.sleepHr: i > 14 ? 56 : 59, K.skinTemp: 34.0};
      }
      h[dateKey(today)] = {K.sleepHr: 62, K.skinTemp: 34.0};
      final s = checkUnusual(h, today).signals.firstWhere((s) => s.rule.key == K.sleepHr);
      expect(s.usual, 59, reason: 'πριν: μεσαία των 28 ημερών (57,5)');
    });

    test('C7: το «συνήθως» του Oura είναι το ίδιο (μεσαία τιμή)', () {
      final plan = SourcePlan.samsungOnly.withEra(Source.oura, day(20));
      final h = <String, Map<String, double>>{
        for (var i = 0; i <= 19; i++) dateKey(day(i)): {'o.hrv': i == 0 ? 40 : (i == 1 ? 90 : 30)},
      };
      expect(ouraBaseline(h, plan, K.hrv, today)!.usual, 30);
    });

    test('Ρυθμίσεις: η ετικέτα λέει τον κανόνα (παλμοί ΚΑΙ θερμοκρασία)', () {
      expect(todayCards.firstWhere((c) => c.key == 'unusual').label, contains('παλμοί ύπνου και θερμοκρασία'));
    });
  });

  // -------------------------------------------------------------------------
  group('D6/D7: Τάσεις και εβδομάδα', () {
    test('M8: το μέσο οξυγόνο δεν βάφεται «καλό» ή «κακό»', () {
      expect(metricDef(K.spo2Avg)!.better, 0);
    });

    TrendResult result(TrendStatus status, {double? eff, double? crit}) => TrendResult(
          def: metricDef(K.sleepHr)!,
          status: status,
          current: 63,
          previous: 58,
          nCurrent: 7,
          nPrevious: 28,
          needed: 5,
          z: 2.4,
          points: const [],
          currentFrom: day(6),
          previousFrom: day(34),
          previousEnd: day(7),
          end: today,
          effectiveCurrent: eff,
          tCritical: crit,
        );

    test('C1: «Σταθερό» με ~2 «πραγματικές» μέρες = «Λίγες μέρες για συμπέρασμα»', () {
      expect(result(TrendStatus.stable, eff: 2.0, crit: 9.925).inconclusive, isTrue);
      expect(result(TrendStatus.stable, eff: 12, crit: 2.7).inconclusive, isFalse);
      expect(result(TrendStatus.up, eff: 2.0, crit: 9.925).inconclusive, isFalse);
    });

    test('C1: ο έλεγχος κρατά το πλήθος και την κρίσιμη τιμή', () {
      final h = <String, Map<String, double>>{
        for (var i = 0; i < 200; i++) dateKey(day(i)): {K.sleepHr: (i ~/ 5).isEven ? 59.0 : 58.0},
      };
      final r = buildWeekReview(h, DateTime(2026, 11, 1), DateTime(2026, 11, 2, 9));
      final hr = r.items.firstWhere((x) => x.def.key == K.sleepHr);
      expect(hr.effectiveCurrent, isNotNull);
      expect(hr.tCritical, isNotNull);
    });

    testWidgets('C1: η κάρτα της εβδομάδας δεν λέει «Σταθερό» όταν οι μέρες δεν φτάνουν', (t) async {
      final review = WeekReview(monday: day(6), sunday: today, items: [result(TrendStatus.stable, eff: 2.0, crit: 9.925)]);
      await _pump(t, SingleChildScrollView(child: WeekCard(review: review)));
      expect(find.text('Λίγες μέρες για συμπέρασμα'), findsOneWidget);
      expect(find.text('Σταθερό'), findsNothing);
      expect(find.textContaining('χωράει στις συνηθισμένες'), findsNothing);
      expect(find.text('πριν 58 bpm'), findsOneWidget, reason: 'όχι «συνήθως»: είναι η μεσαία των 4 εβδομάδων');
    });
  });

  // -------------------------------------------------------------------------
  group('D10: υπολογισμοί', () {
    test('C11: «μέσος όρος ημέρας» με 6 ώρες μετρήσεων, με βάρος τη διάρκεια', () {
      final d0 = DateTime(2026, 10, 24);
      int ms(DateTime t) => t.millisecondsSinceEpoch;
      final heart = <List<num>>[
        for (var t = DateTime(2026, 10, 24, 9); t.isBefore(DateTime(2026, 10, 24, 15)); t = t.add(const Duration(minutes: 4)))
          [ms(t), ms(t.add(const Duration(minutes: 4))), t.hour < 12 ? 70 : 80, 66, 84],
      ];
      final d = Dashboard.fromJson({
        'ok': true,
        'readAt': ms(DateTime(2026, 10, 24, 20)),
        'granted': 17,
        'total': 17,
        'sleep': [],
        'heart': heart,
        'stepsMin': [],
      });
      final h = d.heartForDay(d0)!;
      expect(h.awake.minutes, closeTo(360, 0.01));
      expect(h.awake.value, closeTo(75, 0.01));
      expect(minMinutesForDayValue, 360);
    });

    testWidgets('C14: «Χαμηλότεροι σήμερα» χωρίς τους παλμούς του ύπνου και με το ρολόι', (t) async {
      final day0 = DateTime(2026, 10, 24);
      int ms(DateTime t) => t.millisecondsSinceEpoch;
      DateTime at(int h) => DateTime(day0.year, day0.month, day0.day, h);
      final heart = <List<num>>[
        for (var t = at(0); t.isBefore(at(7)); t = t.add(const Duration(minutes: 30))) [ms(t), ms(t.add(const Duration(minutes: 30))), 50, 47, 53],
        for (var t = at(9); t.isBefore(at(19)); t = t.add(const Duration(minutes: 30))) [ms(t), ms(t.add(const Duration(minutes: 30))), 66, 63, 69],
        [ms(at(19)), ms(at(19)), 80, 80, 80],
      ];
      final store = HealthStore()
        ..data = Dashboard.fromJson({
          'ok': true,
          'readAt': ms(at(20)),
          'granted': 17,
          'total': 17,
          'sleep': [
            {'start': ms(at(0)), 'end': ms(at(7)), 'minutes': 420, 'score': 80, 'stages': []},
          ],
          'heart': heart,
        });
      await _pump(t, HeartPage(store: store, now: at(20)), size: const Size(400, 3000));
      expect(find.text('63 bpm'), findsOneWidget);
      expect(find.text('47 bpm'), findsNothing, reason: 'πριν: ο χαμηλότερος παλμός του ύπνου');
    });
  });

  // -------------------------------------------------------------------------
  group('D11: αναζήτηση τροφίμων (δεύτερος έλεγχος διατροφής N1–N5, N9)', () {
    final index = FoodIndex(basicFoods());
    List<String> names(String q) => [for (final f in index.search(q).take(8)) f.name];

    test('N1: φράσεις ως φράσεις: σύκα/δαμάσκηνα → πρώτα τα φρέσκα, καφές ≠ καφέ ρύζι, γιαούρτι ≠ παγωτό', () {
      expect(names('σύκα').first, 'Σύκο (φρέσκο)');
      expect(names('δαμάσκηνα').first, 'Δαμάσκηνο (φρέσκο)');
      expect(names('ξερά σύκα').first, 'Σύκο ξερό');
      expect(names('καφές').any((n) => n.startsWith('Ρύζι')), isFalse);
      expect(names('καφέ ρύζι').first, startsWith('Ρύζι καστανό'));
      expect(names('γιαούρτι').take(6).every((n) => n.startsWith('Γιαούρτι')), isTrue);
      expect(names('φασόλια').any((n) => n.startsWith('Φασολάκια')), isFalse);
      // Η μάρκα και τα μονολεκτικά άλλα ονόματα δουλεύουν όπως πριν.
      expect(names('τυρί'), containsAll(['Γκούντα', 'Ένταμ']));
      expect(names('freddo').first, startsWith('Εσπρέσο'));
      expect(names('φραπέ'), ['Στιγμιαίος καφές έτοιμος (χωρίς ζάχαρη)']);
    });

    test('N2/N4: κοτόπουλο → στήθος· ψωμί → μέσος όρος· ρύζι βραστό → λευκό (προτίμηση της βάσης)', () {
      final s = FoodStore.preloaded(foods: basicFoods(), now: DateTime(2026, 11, 4, 13));
      expect(s.search('κοτόπουλο').first.name, 'Κοτόπουλο στήθος χωρίς πέτσα (ωμό)');
      expect(s.search('kotopoulo').first.name, 'Κοτόπουλο στήθος χωρίς πέτσα (ωμό)');
      expect(s.search('ψωμί').first.name, 'Ψωμί (μέσος όρος όλων των ειδών)');
      expect(s.search('ρυζι βραστο').first.name, 'Ρύζι λευκό (βρασμένο, χωρίς αλάτι)');
    });

    test('N3: λέξεις της καθημερινής ζωής βρίσκουν το ίδιο ακριβώς τρόφιμο', () {
      expect(names('καλαμαράκια').first, startsWith('Καλαμάρι'));
      expect(names('κουάκερ'), ['Νιφάδες βρώμης']);
      expect(names('ketchup').first, 'Κέτσαπ');
      expect(names('κέτσαπ').first, 'Κέτσαπ');
      expect(names('pizza').first, startsWith('Πίτσα'));
      expect(names('πίτσα').first, startsWith('Πίτσα'));
      expect(names('cashew').first, startsWith('Κάσιους'));
      expect(names('yogurt').first, startsWith('Γιαούρτι'));
    });

    test('N5: «σαλάτα» → κανένα (όχι μόνο φρουτοσαλάτα)· η ολόκληρη λέξη μέσα σε άλλη δεν είναι απάντηση', () {
      expect(names('σαλάτα'), isEmpty);
      expect(names('φρουτοσαλάτα').first, startsWith('Φρουτοσαλάτα'));
    });

    test('N9: το «ανά 100 ml» μένει στο προϊόν, και το αλκοόλ μετρά στον έλεγχο θερμίδων', () {
      final d = draftFromOff('1', {
        'product_name': 'Μπίρα',
        'quantity': '330 ml',
        'nutriments': {'energy-kcal_100g': 43, 'proteins_100g': 0.5, 'carbohydrates_100g': 3.6, 'fat_100g': 0, 'alcohol_100g': 5},
      });
      expect(d.perMl, isTrue);
      expect(d.alcohol, closeTo(3.945, 0.001));
      expect(energyMismatch(d.values, alcohol: d.alcohol!), isNull);
      expect(energyMismatch(d.values), isNotNull, reason: 'χωρίς το αλκοόλ: «οι θερμίδες δεν ταιριάζουν»');
      final f = foodFromDraft(d, 'mine-1');
      expect(f.perMl, isTrue);
      expect(Food.fromJson(f.toJson()).perMl, isTrue);
      expect(draftFromFood(f).perMl, isTrue, reason: 'η διόρθωση λέει ξανά «ανά 100 ml»');
      expect(energyMismatch({Nk.kcal: 240, Nk.protein: 6, Nk.carbs: 60, Nk.fat: 2}, polyols: 40), isNull,
          reason: 'πολυόλες 2,4 kcal/g (μέσα στους υδατάνθρακες)');
    });
  });

  // -------------------------------------------------------------------------
  group('D12: UX', () {
    final now = DateTime(2026, 10, 24, 16, 30);

    HealthStore sample() {
      final s = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(now));
      s.history = sampleHistory(now, s.data!);
      return s;
    }

    testWidgets('U2: στα 360 dp το βάρος με σύντομη ημερομηνία και έως 2 γραμμές', (t) async {
      await _pump(
        t,
        TodayPage(store: sample(), food: sampleFoodStore(now), open: (_, [__]) {}, openSettings: () {}, now: now),
        size: const Size(360, 2400),
      );
      final pill = t.widgetList<TrendPill>(find.byType(TrendPill)).firstWhere((p) => p.text.contains(' kg από '));
      expect(pill.text, matches(RegExp(r'kg από \d{1,2}/\d{1,2}$')));
      expect(pill.maxLines, 2);
    });

    testWidgets('U6/U8: Ύπνος: τα διαστήματα γραμμένα μία φορά· χωρίς άδειο δαχτυλίδι «—» σε νύχτα χωρίς βαθμολογία', (t) async {
      final s = sample();
      expect(s.data!.lastNight!.score, isNull, reason: 'η τελευταία νύχτα του δείγματος είναι σε δύο κομμάτια');
      await _pump(t, SleepPage(store: s, now: now), size: const Size(400, 3000));
      expect(find.text('Η τελευταία νύχτα · μέσοι όροι 7 νυχτών · γράφημα 14 νυχτών'), findsOneWidget);
      expect(find.byType(ScoreRing), findsNothing);
      expect(find.textContaining('Μέσος όρος εβδομάδας'), findsNothing);
    });

    HealthStore oura({required DateTime clock, OuraErrorKind? error, List<OuraNight> nights = const []}) {
      final s = sample();
      s.debugSetPlan(SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 6)));
      s.ouraHasTokens = true;
      s.ouraLink = OuraLink(vault: MemoryVault(), clientId: 'TEST');
      s.ouraClock = () => clock;
      s.ouraNights = nights;
      s.ouraError = error;
      s.ouraSyncedMs = DateTime(2026, 11, 11, 10, 8).millisecondsSinceEpoch;
      return s;
    }

    OuraNight night(DateTime morning) => parseOura(sleep: [
          {
            'id': 'n${morning.day}',
            'day': dateKey(morning),
            'type': 'long_sleep',
            'bedtime_start': DateTime(morning.year, morning.month, morning.day - 1, 23).toUtc().toIso8601String(),
            'bedtime_end': DateTime(morning.year, morning.month, morning.day, 7).toUtc().toIso8601String(),
            'time_in_bed': 8 * 3600,
            'total_sleep_duration': 7 * 3600 + 16 * 60,
          },
        ], dailySleep: const [], readiness: const [])
            .nights
            .single;

    testWidgets('U5: σφάλμα του Oura: η κάρτα λέει ως πότε είναι τα δεδομένα, η παλιά νύχτα με ημερομηνία', (t) async {
      final clock = DateTime(2026, 11, 14, 15);
      final s = oura(clock: clock, error: OuraErrorKind.subscription, nights: [night(DateTime(2026, 11, 11))]);
      await _pump(
        t,
        SingleChildScrollView(
          child: Column(children: [OuraStatusCard(store: s, now: clock), OuraSleepTodayCard(store: s, now: clock, onTap: () {})]),
        ),
      );
      expect(find.textContaining('τελευταίο συγχρονισμό, Τετ 11/11 10:08'), findsOneWidget);
      expect(find.text('Τελευταία νύχτα που ήρθε: Τετ 11/11 · 7 ώρες 16 λεπτά'), findsOneWidget);
      expect(find.text('Η Oura δεν δίνει νέα δεδομένα'), findsOneWidget);
    });

    testWidgets('U4: η θερμοκρασία του Oura λέγεται απόκλιση από το συνηθισμένο', (t) async {
      final clock = DateTime(2026, 11, 14, 15);
      final s = oura(clock: clock, nights: [night(DateTime(2026, 11, 14))]);
      s.history[dateKey(DateTime(2026, 11, 14))] = {'o.skinTemp': 0.2, 'o.hrv': 41, 'o.sleepHr': 60};
      await _pump(t, SingleChildScrollView(child: OuraRestCard(store: s, now: clock, onTap: () {})));
      expect(find.text('απόκλιση από το συνηθισμένο'), findsOneWidget);
      expect(find.text('συνηθισμένη'), findsNothing);
    });

    testWidgets('U11: κουμπί με ρήμα/προορισμό, όχι σκέτο «Oura»', (t) async {
      final clock = DateTime(2026, 11, 14, 15);
      final s = oura(clock: clock);
      s.debugSetPlan(s.plan.withEra(Source.none, DateTime(2026, 11, 13)));
      await _pump(t, SingleChildScrollView(child: OuraStatusCard(store: s, now: clock)));
      expect(find.text('Ρυθμίσεις Oura'), findsOneWidget);
      expect(find.text('Oura'), findsNothing);
    });

    test('U12: σύντομη νύχτα σε δύο κομμάτια = άθροισμα· κομμάτι με κενό πάνω από 4 ώρες μένει χωριστά', () {
      Map<String, dynamic> rec(String id, DateTime a, DateTime b) => {
            'id': id,
            'day': '2026-11-14',
            'type': 'sleep',
            'bedtime_start': a.toUtc().toIso8601String(),
            'bedtime_end': b.toUtc().toIso8601String(),
            'time_in_bed': b.difference(a).inSeconds,
            'total_sleep_duration': b.difference(a).inSeconds - 600,
          };
      final two = parseOura(sleep: [
        rec('a', DateTime(2026, 11, 13, 23), DateTime(2026, 11, 14, 1, 30)),
        rec('b', DateTime(2026, 11, 14, 3), DateTime(2026, 11, 14, 5, 45)),
      ], dailySleep: const [], readiness: const [])
          .nights
          .single;
      expect(two.nightMinutes, 140 + 155);
      expect(two.toNight()!.minutes, 295);
      expect(hm(two.toNight()!.start), '23:00');
      final far = parseOura(sleep: [
        rec('a', DateTime(2026, 11, 14, 0, 10), DateTime(2026, 11, 14, 0, 50)),
        rec('b', DateTime(2026, 11, 14, 5, 0), DateTime(2026, 11, 14, 7, 30)),
      ], dailySleep: const [], readiness: const [])
          .nights
          .single;
      expect(far.counted.length, 1, reason: 'κενό 4 ώρες 10 λεπτά');
      expect(far.separatePieces.length, 1);
      expect(far.nightMinutes, 140);
    });
  });
}
