// Round 2 · h1: UI (R2-U1, R2-U2), widgets αρχικής οθόνης (μόνο το κομμάτι της Dart) και αναφορά για τον γιατρό (R2-CI-1).
// Κάθε δοκιμή αποτυγχάνει χωρίς την αντίστοιχη διόρθωση. Οι αναμενόμενες τιμές βγήκαν από τον γραμμένο κανόνα (γεωμετρία
// του κώδικα, python με τη γραμματοσειρά Inter της εφαρμογής), όχι από τη νέα υλοποίηση. Φανταστικές τιμές (δημόσιο repo).
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/adaptive.dart' show Expenditure;
import 'package:ygeia_forma/adaptive_check.dart' show CheckIn, CheckKind;
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/exercise/ex_data.dart';
import 'package:ygeia_forma/exercise/ex_player.dart';
import 'package:ygeia_forma/food/food_model.dart' show Meal;
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/history.dart' show K, dateKey;
import 'package:ygeia_forma/home_widgets/widget_snapshot.dart' show buildWidgetSnapshot;
import 'package:ygeia_forma/home_widgets/widget_style.dart' show WKind;
import 'package:ygeia_forma/oura/oura_view.dart' show gluedValue;
import 'package:ygeia_forma/pages/checkin_card.dart' show CheckInCard, absurdDaysText;
import 'package:ygeia_forma/pages/food_add.dart' show AddFoodScreen, entryDayLabel;
import 'package:ygeia_forma/pages/goals_page.dart' show GoalsPage;
import 'package:ygeia_forma/pages/heart.dart' show HeartPage;
import 'package:ygeia_forma/pages/info_sheet.dart' show RangeNote;
import 'package:ygeia_forma/pages/me_page.dart' show MePage;
import 'package:ygeia_forma/pages/metric_page.dart' show MetricPage, metricSpecs;
import 'package:ygeia_forma/pages/move.dart' show ExercisePage, fullDayStepsLabel;
import 'package:ygeia_forma/pages/report_page.dart' show ReportPage, RenderReportFit;
import 'package:ygeia_forma/pages/today.dart' show TodayPage;
import 'package:ygeia_forma/pages/training/session_page.dart' show SessionPage, SummaryPage;
import 'package:ygeia_forma/pages/training/today_training_card.dart' show TodayTrainingCard;
import 'package:ygeia_forma/pages/training/training_page.dart' show TrainingPage, recentWorkoutLine;
import 'package:ygeia_forma/pages/training/zone_widgets.dart' show ZoneSheet;
import 'package:ygeia_forma/pages/week_card.dart' show WeekCard;
import 'package:ygeia_forma/profile.dart' show Profile;
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/training_store.dart';
import 'package:ygeia_forma/weekly.dart' show WeekReview;
import 'package:ygeia_forma/widgets.dart';

import 'sample_checkin.dart' show checkinGoals;
import 'sample_data.dart' show sampleDashboardJson, sampleHistory;
import 'sample_food.dart' show sampleFoodStore;
import 'training_sample.dart' show sampleTraining;

const _me = Profile(birthYear: 1985, birthMonth: 12, sex: 'm', heightCm: 180);

HealthStore _sample(DateTime at) {
  final s = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(at));
  s.history = sampleHistory(at, s.data!);
  return s;
}

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
    home: w,
  ));
  await t.pumpAndSettle();
}

/// Τα κείμενα (και τα RichText) κάτω από το [scope], όπως ζωγραφίστηκαν.
List<String> _texts(WidgetTester t, Finder scope) => [
      for (final r in t.widgetList<RichText>(find.descendant(of: scope, matching: find.byType(RichText))))
        r.text.toPlainText(),
    ];

/// Παλμοί ανά δευτερόλεπτο: [base] παντού, [peak] στα 30″ πριν από κάθε ✓ (όπως στο per_set_test).
List<List<int>> _hr(int seconds, List<int> ticks, {int base = 95, int peak = 120}) => [
      for (var t = 0; t <= seconds; t++) [t, ticks.any((x) => t > x - 30 && t <= x) ? peak : base],
    ];

Session _strength(DateTime start, List<int> tickSec, List<List<int>> hr) => Session(
      id: 'h1',
      workout: 'A',
      name: 'Προπόνηση Α',
      programId: 'p',
      start: start,
      end: start.add(const Duration(minutes: 20)),
      hr: hr,
      items: [
        ExLog(ex: 'db_press', sets: 3, lo: 8, hi: 12, rir: 2, rest: 90, log: [
          for (final t in tickSec) SetLog(load: 10.3, reps: 8, done: true, at: start.millisecondsSinceEpoch + t * 1000),
        ]),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Η γραμματοσειρά της εφαρμογής (όπως στα στιγμιότυπα): με τη γραμματοσειρά δοκιμών κάθε γράμμα είναι τετράγωνο.
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R2-U1: Σήμερα, Υγεία, Διατροφή, Εγώ, Στόχοι', () {
    testWidgets('R2-U1-1: ανοιχτό Fold (750): «Φάσεις · εκτίμηση της Samsung» 8 dp από τις ώρες, ίδιο μέγεθος, χωρίς σμίκρυνση',
        (t) async {
      final now = DateTime(2026, 11, 13, 10);
      await _pump(
        t,
        Scaffold(
          body: TodayPage(
            store: _sample(now),
            food: sampleFoodStore(now),
            open: (_, [__]) {},
            openSettings: () {},
            now: now,
            training: TrainingStore(io: MemoryTrainingIO()),
          ),
        ),
        size: const Size(750, 6000),
      );
      final label = find.byKey(const ValueKey('today-stages-label'));
      expect(label, findsOneWidget);
      final row = find.ancestor(of: label, matching: find.byType(Row)).first;
      final texts = find.descendant(of: row, matching: find.byType(Text));
      final start = t.getRect(texts.first), end = t.getRect(texts.last), mid = t.getRect(label);
      expect(mid.left - start.right, greaterThanOrEqualTo(8 - 0.01), reason: 'πριν 0–1 px («01:20Φάσεις»)');
      expect(end.left - mid.right, greaterThanOrEqualTo(8 - 0.01));
      expect(t.widget<Text>(label).style!.fontSize, 12.5);
      expect(find.ancestor(of: label, matching: find.byType(FittedBox)), findsNothing, reason: 'δεν μικραίνει');
      expect(t.widget<Text>(label).data, endsWith('της\u00A0Samsung'), reason: 'ποτέ «… της | Samsung» (U1a-14)');
    });

    testWidgets('R2-U1-2: «Η εβδομάδα σου» σε στενή στήλη: «Καλύτερη βαθμολογία ύπνου (εκτίμηση)» ολόκληρο, εικονίδιο πάνω',
        (t) async {
      final review = WeekReview(
        monday: DateTime(2026, 11, 2),
        sunday: DateTime(2026, 11, 8),
        items: const [],
        bestNight: DateTime(2026, 11, 4),
        bestNightScore: 85,
        mostSteps: DateTime(2026, 11, 5),
        mostStepsValue: 9100,
      );
      // 330 dp: πλακέτα (330 − 36 − 10) ÷ 2 = 142, ετικέτα 142 − 24 − 22 = 96 dp → 4 γραμμές (python: «ύπνου (εκτίμηση)»
      // 106 dp > 96).
      await _pump(t, Scaffold(body: Align(alignment: Alignment.topLeft, child: SizedBox(width: 330, child: WeekCard(review: review)))));
      const label = 'Καλύτερη βαθμολογία ύπνου (εκτίμηση)';
      expect(find.text(label), findsOneWidget);
      final p = t.renderObject<RenderParagraph>(find.text(label));
      expect(p.didExceedMaxLines, isFalse, reason: 'πριν: 3 γραμμές και «(εκτιμ…»');
      expect(t.widget<Text>(find.text(label)).overflow, isNot(TextOverflow.ellipsis));
      final icon = t.getRect(find.byIcon(Icons.bedtime_rounded));
      expect(icon.top, lessThanOrEqualTo(t.getRect(find.text(label)).top + 2), reason: 'εικονίδιο στην πρώτη γραμμή');
      expect(t.takeException(), isNull);
    });

    testWidgets('R2-U1-3 / R2-U1-5: κάρτα ελέγχου θερμίδων: αριθμός και «kcal»/«kg» ποτέ χωριστά· «κάθε Δευτέρα» μαζί', (t) async {
      final noSplit = RegExp(r'\d (kcal|kg)\b');
      // Γρήγορη απώλεια χωρίς πρόταση: το ημερολόγιο έδειχνε 1.600 kcal (68c).
      final fast = CheckIn(
          kind: CheckKind.fast, goals: checkinGoals(), fastSlope: -1.16, kgNow: 86.5, fastDays: 14, fastIntake: 1600);
      await _pump(t, Scaffold(body: SingleChildScrollView(child: CheckInCard(check: fast, store: HealthStore(), now: DateTime(2026, 12, 4, 9)))));
      final card = find.byKey(const ValueKey('today-checkin'));
      final all = _texts(t, card).join('\n');
      expect(all, contains('1.600\u00A0kcal τη μέρα'));
      expect(all, contains('−1,16\u00A0kg την εβδομάδα'));
      expect(noSplit.hasMatch(all), isFalse, reason: all);

      // Εβδομαδιαίος έλεγχος, στόχος ίδιος: «καις περίπου 2.600 kcal» και ο τίτλος «… · | κάθε Δευτέρα».
      final same = CheckIn(
        kind: CheckKind.same,
        goals: checkinGoals(),
        est: Expenditure(
            tdee: 2600,
            meanIntake: 2250,
            slopeKgWeek: -0.3,
            intakeDays: 20,
            weighIns: 9,
            from: DateTime(2026, 11, 23),
            to: DateTime(2026, 12, 13)),
      );
      await _pump(t, Scaffold(body: SingleChildScrollView(child: CheckInCard(check: same, store: HealthStore(), now: DateTime(2026, 12, 14, 9)))));
      expect(find.text('Έλεγχος θερμίδων · κάθε\u00A0Δευτέρα'), findsOneWidget);
      final all2 = _texts(t, find.byKey(const ValueKey('today-checkin'))).join('\n');
      expect(all2, contains('καις περίπου 2.600\u00A0kcal'));
      expect(noSplit.hasMatch(all2), isFalse, reason: all2);

      // Μέρες με πάρα πολλές θερμίδες (S11-3).
      expect(absurdDaysText([(DateTime(2026, 12, 2), 19710.0)]), contains('(19.710\u00A0kcal)'));
      expect(noSplit.hasMatch(absurdDaysText([(DateTime(2026, 12, 2), 19710.0), (DateTime(2026, 12, 3), 12000.0)])), isFalse);
    });

    testWidgets('R2-U1-4: χάπι σε δύο γραμμές: αγκαλιάζει τη μεγαλύτερη γραμμή, όχι όλο το πλάτος', (t) async {
      await _pump(
        t,
        const Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 240,
              child: Align(
                alignment: Alignment.topLeft,
                child: TrendPill('1 ώρα 43 λεπτά λιγότερο από ό,τι συνήθως', maxLines: 2, keepLastWords: true),
              ),
            ),
          ),
        ),
      );
      // python (Inter 12,5 w600): «1 ώρα 43 λεπτά λιγότερο από» 181 dp, «ό,τι συνήθως» 81 dp· όλο 265 > 240 − 18.
      final p = t.renderObject<RenderParagraph>(find.descendant(of: find.byType(TrendPill), matching: find.byType(RichText)));
      expect(p.getMaxIntrinsicWidth(double.infinity), greaterThan(222), reason: 'σπάει σε δύο γραμμές');
      expect(t.getSize(find.byType(TrendPill)).width, lessThan(215), reason: 'πριν: 240 (ως την άκρη)');
    });

    test('R2-U1-6: μόνο η τιμή μένει με τη λέξη πριν από αυτήν', () {
      expect(gluedValue('Οξυγόνο τη νύχτα, χαμηλότερη τιμή 77%'), 'Οξυγόνο τη νύχτα, χαμηλότερη τιμή\u00A077%');
      expect(gluedValue('Οξυγόνο τη νύχτα, μέσος όρος —'), 'Οξυγόνο τη νύχτα, μέσος όρος\u00A0—');
      expect(gluedValue('77%'), '77%');
    });

    testWidgets('R2-U1-6: 360 dp, γράμματα 1,3×: καμία γραμμή μόνο με «%» ή μόνο με τον αριθμό', (t) async {
      // Στήλη τίτλου ≈ 360 − 32 − 36 − 8 − ετικέτα πηγής: 200 dp είναι πιο στενό από την πραγματική.
      for (final width in [150.0, 180.0, 200.0, 230.0]) {
        final tp = TextPainter(
          text: TextSpan(
            text: gluedValue('Οξυγόνο τη νύχτα, χαμηλότερη τιμή 77%'),
            style: const TextStyle(fontFamily: fontFamily, fontSize: 15.5, fontWeight: FontWeight.w700),
          ),
          textDirection: TextDirection.ltr,
          textScaler: const TextScaler.linear(1.3),
        )..layout(maxWidth: width);
        final lines = tp.computeLineMetrics();
        // «τιμή 77%» ≈ 75 dp στα 20 px: κάθε γραμμή φαρδύτερη από σκέτο «77%» (≈ 40 dp).
        for (final l in lines) {
          expect(l.width, greaterThan(45), reason: 'πλάτος $width: γραμμή ${l.lineNumber} μόνη της');
        }
        tp.dispose();
      }
    });

    testWidgets('R2-U1-7: «Πηγές» και «Τι μετράει κάθε συσκευή» στην ίδια κάρτα', (t) async {
      final now = DateTime(2026, 11, 13, 10);
      await _pump(t, MePage(store: HealthStore(), food: sampleFoodStore(now), now: now), size: const Size(400, 3000));
      final a = find.ancestor(of: find.byKey(const ValueKey('me-sources')), matching: find.byType(AppCard)).first;
      final b = find.ancestor(of: find.byKey(const ValueKey('me-devices')), matching: find.byType(AppCard)).first;
      expect(t.element(a), same(t.element(b)));
    });

    testWidgets('R2-U1-8: η τιμή αριστερά της τελευταίας κουκκίδας χωρίς γραμμή ανάμεσα («82,2′»)', (t) async {
      const key = ValueKey('h1-line');
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
      // Γεωμετρία του _LinePainter: αριστερά 4, δεξιά 44, πάνω 26, κάτω 22 → w 252, h 112· άξονας 82–85 (lineAxis)·
      // τελευταίο σημείο x = 256, y = 26 + 112 × (1 − 0,2/3) ≈ 130,5· κάτω από αυτό δεν χωρά → πλάκα αριστερά.
      final (lo, step, n) = lineAxis([84.0, 83.5, 82.2], minRange: 1, plotHeight: 112);
      expect((lo, step, n), (82.0, 1.0, 3), reason: 'ο άξονας που υπέθεσε η δοκιμή');
      final lastY = 26 + 112 * (1 - (82.2 - lo) / (step * n));
      final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(key));
      final bytes = (await t.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 1);
        final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        img.dispose();
        return data!;
      }))!;
      int px(int x, int y) => bytes.getUint32((y * 300 + x) * 4);
      // Η στήλη x = 249 (6,5 px αριστερά του κέντρου): πριν εκεί περνούσε η γραμμή, ανάμεσα στην πλάκα (ως 249) και στο
      // λευκό περίγραμμα της κουκκίδας (από 250). Τώρα πλάκα ή περίγραμμα: λευκό.
      for (var y = lastY.round() - 4; y <= lastY.round() + 3; y++) {
        expect(px(249, y), 0xFFFFFFFF, reason: 'γραμμή ανάμεσα στον αριθμό και στην κουκκίδα (y $y)');
      }
      // Η κουκκίδα φαίνεται (χρώμα της γραμμής στο κέντρο).
      expect(px(256, lastY.round()), isNot(0xFFFFFFFF));
    });

    testWidgets('R2-U1-9: σελίδα «Βάρος»: ελάχιστο εύρος 3 kg όπως το γράφημα του Σώματος', (t) async {
      final day = DateTime(2026, 11, 13);
      final s = HealthStore()
        ..history = {
          dateKey(DateTime(2026, 11, 3)): {K.weight: 83.3},
          dateKey(day): {K.weight: 82.2},
        };
      await _pump(t, MetricPage(store: s, spec: metricSpecs[K.weight]!, now: DateTime(2026, 11, 13, 10)));
      expect(t.widget<LineChart>(find.byType(LineChart)).minRange, 3);
      // Άξονας του γραφήματος: ≥ 3 kg (πριν 82,0–83,5).
      final (lo, step, n) = lineAxis([83.3, 82.2], minRange: 3, plotHeight: 170 - 48);
      expect(step * n, greaterThanOrEqualTo(3));
      expect(lo, lessThanOrEqualTo(82.2));
      expect(metricSpecs[K.fatPct]!.minRange, 3);
      expect(metricSpecs[K.smm]!.minRange, 3);
      expect(metricSpecs[K.sleepHr]!.minRange, 8);
      expect(metricSpecs[K.dayHr]!.minRange, 8);
      expect(metricSpecs[K.sleepMin]!.minRange, 1, reason: 'διάρκειες: ο άξονας του R2-D-4, όπως πριν');
    });

    testWidgets('R2-U1-10: Καρδιά: το χάπι «Παλμοί ξύπνιος» γράφεται όπως των παλμών ύπνου («· συνήθως 75»)', (t) async {
      final now = DateTime(2026, 11, 13, 10);
      await _pump(t, HeartPage(store: _sample(now), now: now), size: const Size(400, 3000));
      final pills = t.widgetList<TrendPill>(
          find.descendant(of: find.byKey(const ValueKey('heart-awake')), matching: find.byType(TrendPill)));
      expect(pills, isNotEmpty);
      for (final p in pills) {
        expect(p.text, matches(RegExp(r'^(Όπως συνήθως|[+−]\d+ bpm · συνήθως \d+)$')), reason: p.text);
      }
    });

    test('R2-U1-11: η ημερομηνία της μέρας προσθήκης δεν σπάει', () {
      final now = DateTime(2026, 10, 24, 12);
      expect(entryDayLabel(DateTime(2026, 10, 24), now), 'Σήμερα · Σάβ\u00A024/10');
      expect(entryDayLabel(DateTime(2026, 10, 23), now), 'Χθες · Παρ\u00A023/10');
      expect(entryDayLabel(DateTime(2026, 10, 20), now), 'Τρί\u00A020/10');
    });

    testWidgets('R2-U1-12: «Προσθήκη στο Σνακ»: 20 dp δεξιά-αριστερά (πριν 0: με γράμματα 2× ακουμπούσε τις άκρες)', (t) async {
      final now = DateTime(2026, 11, 13, 12);
      await _pump(t, AddFoodScreen(food: sampleFoodStore(now), meal: Meal.snack, day: DateTime(2026, 11, 13), clock: () => now));
      await t.enterText(find.byType(TextField), 'μπανάνα');
      await t.pumpAndSettle();
      await t.tap(find.text('Μπανάνα').first);
      await t.pumpAndSettle();
      final text = find.text('Προσθήκη στο Σνακ');
      final button = find.ancestor(of: text, matching: find.byType(FilledButton));
      final pad = t.widget<FilledButton>(button).style!.padding!.resolve(<WidgetState>{})!;
      expect(pad, const EdgeInsets.symmetric(vertical: 16, horizontal: 20));
      expect(t.getRect(text).left - t.getRect(button).left, greaterThanOrEqualTo(16));
      expect(t.getRect(button).right - t.getRect(text).right, greaterThanOrEqualTo(16));
    });

    testWidgets('R2-U1-14: πίτουρο με ετικέτα που δεν φτάνει: όχι «γράψε τις β-γλυκάνες», αλλά πόσο χρειάζεται', (t) async {
      final s = HealthStore()
        ..setProfile(_me)
        ..setGoals(checkinGoals().copyWith(betaPer100: 7, branG: 40));
      await _pump(t, GoalsPage(store: s, now: DateTime(2026, 11, 12, 10)), size: const Size(400, 4000));
      // 3 g ÷ 7 g/100 g = 42,9 g → 45 g (πάνω, ανά 5).
      expect(find.textContaining('γράψε τις β\u2011γλυκάνες'), findsNothing);
      // Round 3 (k1 · R3-B-3): αδιάσπαστο ενωτικό στο «β‑γλυκάνες».
      expect(find.text('40\u00A0g τη μέρα · για 3\u00A0g β\u2011γλυκάνες χρειάζονται 45\u00A0g'), findsOneWidget);
      expect(find.textContaining('χρειάζονται 45\u00A0g πίτουρο· το πλάνο σου έχει 40\u00A0g'), findsOneWidget);
      // Χωρίς ετικέτα: όπως πριν.
      s.setGoals(checkinGoals().copyWith(branG: 40));
      await t.pumpAndSettle();
      // R7-U2-12 (f6): αδιάσπαστο ενωτικό και σε αυτό το κείμενο.
      expect(find.textContaining('γράψε τις β\u2011γλυκάνες'), findsOneWidget);
      // Ετικέτα που φτάνει: όπως πριν.
      s.setGoals(checkinGoals().copyWith(betaPer100: 7, branG: 45));
      await t.pumpAndSettle();
      expect(find.text('45 g · από την ετικέτα'), findsOneWidget);
      expect(find.textContaining('χρειάζονται 45'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R2-CI-1 / R2-U1-13: αναφορά για τον γιατρό', () {
    testWidgets('90 νύχτες κάτω από 80% και μεγάλη σημείωση: καμία σελίδα δεν ξεχειλίζει, η 3η μικραίνει',
        (t) async {
      final now = DateTime(2026, 11, 13, 10);
      final h = <String, Map<String, double>>{
        for (var i = 0; i < 90; i++)
          dateKey(DateTime(2026, 11, 13 - i)): {
            K.sleepHr: 56.0 + i % 5,
            K.spo2Avg: 94.0 + (i % 3) * 0.4,
            K.spo2Min: 75.0 + i % 5,
            K.sleepMin: 400.0 + (i % 7) * 10,
            K.steps: 7000.0 + (i % 9) * 400,
            if (i % 3 == 0) K.weight: 90.0 - i * 0.02,
          },
      };
      final store = HealthStore()
        ..data = Dashboard.fromJson(sampleDashboardJson(now))
        ..history = h;
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(680, 4200);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
          theme: buildTheme(Brightness.light), home: ReportPage(store: store, now: now, note: 'σημείωση ' * 40)));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: 'καμία σελίδα A4 δεν ξεχειλίζει');
      for (final k in ['report-page1-body', 'report-page2-body', 'report-page3-body']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      // Η σελίδα 3 γράφει ΟΛΕΣ τις νύχτες κάτω από 80% (F6): εδώ δεν χωρά όπως είναι, άρα μικραίνει (πριν: κομμένη).
      expect(t.renderObject<RenderReportFit>(find.byKey(const ValueKey('report-page3-body'))).scale, lessThan(1));
      expect(find.byKey(const ValueKey('report-oxygen-below80')), findsOneWidget);

      // R2-U1-13: η ετικέτα του δεύτερου πεδίου δεν κάθεται στη βοηθητική γραμμή του πρώτου.
      final name = t.getRect(find.byKey(const ValueKey('report-name')));
      final note = t.getRect(find.byKey(const ValueKey('report-note')));
      expect(note.top - name.bottom, greaterThanOrEqualTo(16));
    });

    testWidgets('συνηθισμένη αναφορά: οι σελίδες 2 και 3 χωρίς ξεχείλισμα και χωρίς ορατή σμίκρυνση', (t) async {
      final now = DateTime(2026, 11, 13, 10);
      final store = _sample(now);
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(680, 4200);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: ReportPage(store: store, now: now)));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      for (final k in ['report-page2-body', 'report-page3-body']) {
        expect(t.renderObject<RenderReportFit>(find.byKey(ValueKey(k))).scale, greaterThan(0.9), reason: k);
      }
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R2-U2: Άσκηση', () {
    setUp(() => ExClock.frozen = true);

    test('R2-U2-01: σε κάθε κατηγορία το ανενεργό κουμπί παίρνει το γκρι του Material, όχι το χρώμα της', () {
      final p = categoryForeground(Aigaio.light.exercise);
      expect(p.resolve(<WidgetState>{}), Aigaio.light.exercise);
      expect(p.resolve({WidgetState.disabled}), isNull);
      expect(p.resolve({WidgetState.hovered}), Aigaio.light.exercise);
    });

    testWidgets('R2-U2-01 / R2-U2-10: προπόνηση: «Παράλειψη» με γραμμένο σετ γκρι· οι δύο μετρητές στοιχισμένοι', (t) async {
      final now = DateTime(2026, 11, 13, 17, 30);
      await t.runAsync(() => ExLibrary.load(inline: true));
      final store = sampleTraining(now);
      store.start(store.program!.workout('A')!);
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(400, 1400);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: SessionPage(training: store)));
      await t.pump();

      // R2-U2-10: κιλά και επαναλήψεις ο ένας κάτω από τον άλλο (< 470 dp): τα «+» στην ίδια θέση (πριν 16 dp διαφορά).
      final plus = find.descendant(of: find.byKey(const ValueKey('sess-current-0')), matching: find.byIcon(Icons.add_rounded));
      expect(plus, findsNWidgets(2));
      expect(t.getTopLeft(plus.at(0)).dx, closeTo(t.getTopLeft(plus.at(1)).dx, 0.01));

      // R2-U2-01: ✓ στο 1ο σετ → η «Παράλειψη» ανενεργή, σε γκρι (πριν: το πορτοκαλί της Άσκησης).
      await t.ensureVisible(find.byKey(const ValueKey('sess-tick-0')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('sess-tick-0')));
      await t.pump();
      await t.pump();
      final skip = find.byKey(const ValueKey('sess-skip'));
      expect(t.widget<OutlinedButton>(skip).onPressed, isNull);
      // Το χρώμα του ανενεργού ελέγχεται στο στυλ του κουμπιού (η απόδοση της αλλαγής κατάστασης μέσα στη δοκιμή
      // δεν είναι αξιόπιστη)· την εικόνα τη δείχνει το στιγμιότυπο T4_session_rest.
      final fg = t.widget<OutlinedButton>(skip).style!.foregroundColor!;
      expect(fg.resolve({WidgetState.disabled}), Aigaio.light.textTertiary, reason: 'ανενεργό: αχνό γκρι (όπως στη Διατροφή)');
      expect(fg.resolve(<WidgetState>{}), Aigaio.light.text, reason: 'ενεργό: το κανονικό χρώμα κειμένου');
      // κλείνει η οθόνη (σταματά το ρολόι του δευτερολέπτου)
      await t.pumpWidget(const SizedBox());
      await t.pump();
    });

    testWidgets('R2-U2-02: σύνοψη: 8 dp ανάμεσα στην επικεφαλίδα «κιλά × επαναλήψεις» και στους παλμούς', (t) async {
      final now = DateTime(2026, 11, 20, 18);
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(360, 2400);
      addTearDown(t.view.reset);
      await t.runAsync(() => ExLibrary.load(inline: true));
      final tr = sampleTraining(now);
      final ticks = [60, 180, 300];
      final s = _strength(now.subtract(const Duration(days: 1)), ticks, _hr(400, ticks));
      tr.sessions.add(s);
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const ValueKey('open'),
                onPressed: () => Navigator.of(context).push(SummaryPage.route(tr, s)),
                child: const Text('άνοιγμα'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.byKey(const ValueKey('open')));
      await t.pumpAndSettle();
      final head = find.byKey(const ValueKey('sum-head-db_press'));
      expect(head, findsOneWidget);
      final card = find.ancestor(of: head, matching: find.byType(AppCard)).first;
      final heartText = find.descendant(of: card, matching: find.text('στο σετ'));
      final heartCell = t.getRect(find.ancestor(of: heartText, matching: find.byType(Row)).first);
      expect(heartCell.left - t.getRect(head).right, greaterThanOrEqualTo(8 - 0.01), reason: 'πριν 0 («…επαναλήψεις♥»)');
    });

    testWidgets('R2-U2-03 / R2-U2-04: «Το πρόγραμμα» 16 dp και δεξιά· «Ελεύθερη άσκηση» σε μία γραμμή στα 360', (t) async {
      final now = DateTime(2026, 11, 13, 17, 30);
      await t.runAsync(() => ExLibrary.load(inline: true));
      await _pump(t, Scaffold(body: TrainingPage(training: sampleTraining(now), now: now)), size: const Size(360, 5000));
      final note = find.byKey(const ValueKey('train-program-note'));
      expect(note, findsOneWidget);
      final card = find.ancestor(of: note, matching: find.byType(AppCard)).first;
      expect(t.getRect(card).right - t.getRect(note).right, greaterThanOrEqualTo(16 - 0.01), reason: 'πριν 4 (+ περίγραμμα)');
      expect(t.getRect(note).left - t.getRect(card).left, greaterThanOrEqualTo(16 - 0.01));

      final sub = find.byKey(const ValueKey('train-free-sub'));
      expect(sub, findsOneWidget);
      // Inter 13,5: μία γραμμή ≈ 16 dp ύψος· δύο γραμμές ≈ 33.
      expect(t.getSize(sub).height, lessThan(24), reason: 'πριν «…εκείνη την / ώρα.»');
      expect(t.widget<Text>(sub).data, endsWith('επί\u00A0τόπου.'));
    });

    test('R2-U2-05: ο αριθμός μένει με τη μονάδα του', () {
      expect(unitsGlued(hoursMinutes(2)), '2\u00A0λεπτά');
      expect(unitsGlued(hoursMinutes(65)), '1\u00A0ώρα 5\u00A0λεπτά');
      expect(unitsGlued('παύση · 2 λεπτά'), 'παύση · 2\u00A0λεπτά');
      expect(unitsGlued('χωρίς αριθμό'), 'χωρίς αριθμό');
    });

    testWidgets('R2-U2-07: ζώνη: η ετικέτα «Παλμοί ηρεμίας ξύπνιος» ολόκληρη στα 360 dp', (t) async {
      await _pump(t, Scaffold(body: ZoneSheet(health: HealthStore(), now: DateTime(2026, 11, 13, 10))), size: const Size(360, 3000));
      const label = 'Παλμοί ηρεμίας ξύπνιος';
      expect(find.text(label), findsOneWidget);
      expect(t.renderObject<RenderParagraph>(find.text(label)).didExceedMaxLines, isFalse);
      expect(find.textContaining('Αν τους μέτρησες: καθιστός, μετά από 5 λεπτά ηρεμίας'), findsOneWidget);
    });

    test('R2-U2-08: η μέρα που κρίνει η μπάρα των βημάτων, με τα βήματά της', () {
      final day = DayValue(DateTime(2026, 10, 23), 3900);
      expect(fullDayStepsLabel(day, DateTime(2026, 10, 24, 10)), 'Χθες, Παρ\u00A023/10 · 3.900\u00A0βήματα');
      expect(fullDayStepsLabel(day, DateTime(2026, 10, 26, 10)), 'Παρ\u00A023/10 · 3.900\u00A0βήματα');
    });

    testWidgets('R2-U2-08: η ετικέτα της μέρας ΠΑΝΩ από την μπάρα του εύρους', (t) async {
      final now = DateTime(2026, 11, 13, 10);
      final s = _sample(now)..setProfile(_me);
      await _pump(t, ExercisePage(store: s, now: now), size: const Size(400, 3000));
      final label = find.byKey(const ValueKey('move-fullday'));
      expect(label, findsOneWidget);
      expect(t.widget<Text>(label).data, startsWith('Χθες, Πέμ\u00A012/11 · '));
      expect(t.getRect(label).bottom, lessThanOrEqualTo(t.getRect(find.byType(RangeNote).first).top));
    });

    testWidgets('R2-U2-09: «Ξεκίνα την προπόνηση» με 10 dp πάνω-κάτω· στα 2× το κείμενο δεν ακουμπά τις άκρες', (t) async {
      final fri = DateTime(2026, 11, 13, 17, 30); // «A» στο δείγμα
      await t.runAsync(() => ExLibrary.load(inline: true));
      await _pump(t, Scaffold(body: SingleChildScrollView(child: TodayTrainingCard(training: sampleTraining(fri), now: fri))),
          size: const Size(360, 3000), textScale: 2.0);
      final button = find.byKey(const ValueKey('today-train-start'));
      final pad = t.widget<FilledButton>(button).style!.padding!.resolve(<WidgetState>{})!;
      expect(pad, const EdgeInsets.symmetric(horizontal: 16, vertical: 10));
      final text = find.descendant(of: button, matching: find.byType(RichText));
      expect(t.getRect(text).top - t.getRect(button).top, greaterThanOrEqualTo(8));
      expect(t.getRect(button).bottom - t.getRect(text).bottom, greaterThanOrEqualTo(8));
    });

    test('R2-U2-11: «Τελευταίες προπονήσεις»: διάρκεια σε λεπτά, όπως η «Τελευταία φορά»', () {
      final start = DateTime(2026, 11, 11, 18);
      final strength = Session(
          id: 'a', workout: 'A', name: 'Προπόνηση Α', programId: 'p', start: start, end: start.add(const Duration(minutes: 60)), hrAvg: 118);
      final line = recentWorkoutLine(strength);
      expect(line, startsWith('60\u00A0λεπτά · 0\u00A0σετ'));
      expect(line, endsWith('μέσοι παλμοί\u00A0118'));
      expect(line, isNot(contains('ώρα')));
      final walk = Session(
          id: 'w',
          workout: 'walk',
          name: 'Περπάτημα',
          programId: 'p',
          start: start,
          end: start.add(const Duration(minutes: 75)),
          cardioMinutes: 75);
      expect(recentWorkoutLine(walk), startsWith('75\u00A0λεπτά'));
      final one = Session(
          id: 'o', workout: 'A', name: 'Α', programId: 'p', start: start, end: start.add(const Duration(minutes: 1)));
      expect(recentWorkoutLine(one), startsWith('1\u00A0λεπτό ·'));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R2-U3-04: widgets, σύντομη πηγή για τη στήλη 1×3', () {
    test('χωρίς νύχτα και χωρίς ζύγιση: «srcShort» δίπλα στην κανονική πηγή', () {
      final now = DateTime(2026, 11, 13, 10);
      final snap = buildWidgetSnapshot(HealthStore(), sampleFoodStore(now), now);
      final kinds = snap['kinds'] as Map;
      expect((kinds[WKind.sleep] as Map)['src'], 'καμία πρόσφατη νύχτα');
      expect((kinds[WKind.sleep] as Map)['srcShort'], 'καμία νύχτα');
      expect((kinds[WKind.body] as Map)['src'], 'καμία ζύγιση ακόμα');
      expect((kinds[WKind.body] as Map)['srcShort'], 'καμία ζύγιση');
      // Με τιμές: round 8 (R8-U1-4) σύντομη πηγή = μόνο η μέρα της νύχτας (πριν κανένα «srcShort»: στη στήλη 1×3 με
      // «Μεγάλα» γράμματα ή «Σκιά» η πηγή κοβόταν).
      final full = buildWidgetSnapshot(_sample(now), sampleFoodStore(now), now)['kinds'] as Map;
      final sleep = full[WKind.sleep] as Map;
      expect(sleep['srcShort'], (sleep['src'] as String).split(' · ').last);
      expect(sleep['srcShort'], matches(RegExp(r'^\S+ \d{1,2}/\d{1,2}$')));
    });

    testWidgets('η σύντομη χωρά στη στήλη των 76 dp (92 − 2 × 8) με Inter Medium 10 sp· η κανονική όχι ούτε στα 85%', (t) async {
      double w(String s) {
        final tp = TextPainter(
          text: TextSpan(text: s, style: const TextStyle(fontFamily: fontFamily, fontSize: 10, fontWeight: FontWeight.w500)),
          textDirection: TextDirection.ltr,
        )..layout();
        final x = tp.width;
        tp.dispose();
        return x;
      }

      // python: 111,9 / 96,4 dp κανονικές, 59,6 / 62,7 dp σύντομες.
      expect(w('καμία πρόσφατη νύχτα') * 0.85, greaterThan(76));
      expect(w('καμία ζύγιση ακόμα') * 0.85, greaterThan(76));
      expect(w('καμία νύχτα'), lessThan(76));
      expect(w('καμία ζύγιση'), lessThan(76));
    });
  });
}
