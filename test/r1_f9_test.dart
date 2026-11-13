// Round 1 · f9: σύστημα σχεδίασης (θέματα, αντίθεση), «Σήμερα», γραφήματα, διάρκειες, widgets αρχικής οθόνης.
// Κάθε δοκιμή αποτυγχάνει χωρίς την αντίστοιχη διόρθωση. Οι αναμενόμενες τιμές υπολογίστηκαν χωριστά (python, κανόνας
// WCAG 2.x και ο γραμμένος κανόνας του άξονα), όχι από τον κώδικα. Φανταστικές τιμές (δημόσιο repo).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/home_widgets/widget_snapshot.dart';
import 'package:ygeia_forma/home_widgets/widget_style.dart';
import 'package:ygeia_forma/pages/nutrition.dart' show FoodTodayCard;
import 'package:ygeia_forma/pages/oura_today.dart' show OuraSleepTodayCard;
import 'package:ygeia_forma/pages/today.dart';
import 'package:ygeia_forma/pages/week_card.dart' show WeekCard;
import 'package:ygeia_forma/plan_file.dart' show PlanState;
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/training/training_store.dart';
import 'package:ygeia_forma/widgets.dart';

import 'sample_data.dart';
import 'sample_food.dart';

const _all = [...Aigaio.dayThemes, ...Aigaio.nightThemes];

/// Το απαλό φόντο ([Aigaio.tint]) πάνω σε [base], όπως το ζωγραφίζει η Flutter.
Color _tintOn(Aigaio t, Color c, Color base) => Color.alphaBlend(t.tint(c), base);

HealthStore _sample(DateTime at) {
  final s = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(at));
  s.history = sampleHistory(at, s.data!);
  return s;
}

Future<void> _pumpToday(WidgetTester t, HealthStore s, DateTime now, {Size size = const Size(400, 6000)}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.light),
    home: Scaffold(
      body: TodayPage(
        store: s,
        food: sampleFoodStore(now),
        open: (_, [__]) {},
        openSettings: () {},
        now: now,
        training: TrainingStore(io: MemoryTrainingIO()),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

/// Θέση που βάζει μόνη της το κενό (όπως CheckInSlot / BackupReminderSlot): ορατή ή άδεια.
class _Slot extends StatelessWidget with SelfSpaced {
  const _Slot({required this.visible, required this.k});
  final bool visible;
  final String k;

  @override
  Widget build(BuildContext context) => visible
      ? Padding(padding: const EdgeInsets.only(bottom: PageFrame.gap), child: SizedBox(key: ValueKey(k), height: 50))
      : const SizedBox.shrink();
}

Future<void> _pumpFrame(WidgetTester t, List<Widget> items) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = const Size(400, 1600);
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.light),
    home: Scaffold(body: PageFrame(title: 'Τίτλος', onRefresh: () async {}, left: items)),
  ));
  await t.pumpAndSettle();
}

void main() {
  // ------------------------------------------------------------------ U4-3 / U1b-06 / U6-13 / U1a-17 / U4-13
  group('U4-3: χρωματιστό κείμενο πάνω στο δικό του απαλό φόντο ≥ 4,5:1 σε όλα τα θέματα', () {
    test('good, bad, warn, food, exercise, primary πάνω στο tint τους (σε κάρτα)', () {
      for (final t in _all) {
        for (final (name, c) in [
          ('good', t.good),
          ('bad', t.bad),
          ('warn', t.warn),
          ('food («+ Φαγητό»)', t.food),
          ('exercise («Στήσιμο:»)', t.exercise),
          ('primary (ετικέτα μάρκας)', t.primary),
          ('textSecondary (ουδέτερο χάπι)', t.textSecondary),
        ]) {
          expect(Aigaio.contrast(c, _tintOn(t, c, t.card)), greaterThanOrEqualTo(4.5), reason: '${t.id}/${t.dark}: $name');
        }
      }
    });

    test('δεύτερο κείμενο και «good» πάνω σε απαλά φόντα άλλων χρωμάτων (κουτιά εβδομάδας, σημερινό κελί)', () {
      for (final t in _all) {
        for (final (name, bg) in [('exercise', t.exercise), ('sleep', t.sleep), ('move', t.move), ('body', t.body)]) {
          expect(Aigaio.contrast(t.textSecondary, _tintOn(t, bg, t.card)), greaterThanOrEqualTo(4.5),
              reason: '${t.id}/${t.dark}: textSecondary σε tint($name)');
        }
        expect(Aigaio.contrast(t.good, _tintOn(t, t.exercise, t.card)), greaterThanOrEqualTo(4.5), reason: '${t.id}: good/tint(exercise)');
      }
    });

    test('«Δείγμα» στην Εμφάνιση: γράμματα στο χρώμα του κειμένου πάνω στα απαλά χρώματα (φόντο σελίδας)', () {
      for (final t in _all) {
        for (final c in [t.move, t.body, t.sleep]) {
          expect(Aigaio.contrast(t.text, _tintOn(t, c, t.background)), greaterThanOrEqualTo(4.5), reason: t.id);
        }
      }
    });

    test('ενέργεια του SnackBar, ετικέτα πεδίου της Διατροφής (U3a-15), κεφάλι ελέγχου δεδομένων (U4-13)', () {
      for (final t in _all) {
        final action = buildTheme(t.dark ? Brightness.dark : Brightness.light, t).snackBarTheme.actionTextColor!;
        expect(Aigaio.contrast(action, t.snack), greaterThanOrEqualTo(4.5), reason: '${t.id}: SnackBar');
        expect(Aigaio.contrast(t.food, t.background), greaterThanOrEqualTo(4.5), reason: '${t.id}: food σε φόντο');
        expect(Aigaio.contrast(t.exercise, t.background), greaterThanOrEqualTo(4.5), reason: '${t.id}: exercise σε φόντο');
      }
    });

    test('οι αλλαγές κράτησαν την απόχρωση: μόνο λίγο πιο σκούρα / ανοιχτά (Αιγαίο φωτεινό)', () {
      expect(Aigaio.light.good, const Color(0xFF3C771F));
      expect(Aigaio.light.food, const Color(0xFF14793A));
      expect(Aigaio.light.exercise, const Color(0xFFBA3E0C));
      // Τα γεμάτα χρώματα (κουμπιά) δεν άλλαξαν.
      expect(Aigaio.light.foodSolid, const Color(0xFF15803D));
      expect(Aigaio.light.exerciseSolid, const Color(0xFFC2410C));
    });
  });

  // ------------------------------------------------------------------ U4-12 / U2a-10
  test('U4-12: ο βαθύς ύπνος φαίνεται (≥ 3:1) στα σκούρα θέματα και μένει η πιο σκούρα φάση', () {
    for (final t in Aigaio.nightThemes) {
      expect(Aigaio.contrast(t.stageDeep, t.card), greaterThanOrEqualTo(3.0), reason: t.id);
      for (final other in [t.stageLight, t.stageRem, t.stageAwake]) {
        expect(t.stageDeep.computeLuminance(), lessThan(other.computeLuminance()), reason: t.id);
      }
    }
  });

  // ------------------------------------------------------------------ U4-1 / U4-2 / U5-31 / U3a-15 / U5-30
  group('Θέμα: επιλογές, διακόπτες, διάλογοι, θέματα κατηγοριών', () {
    test('U4-1: επιλεγμένη ετικέτα στο κύριο χρώμα (όχι στο λαδί του «Σώματος»), λεπτό περίγραμμα', () {
      for (final t in _all) {
        final s = buildTheme(t.dark ? Brightness.dark : Brightness.light, t).colorScheme;
        expect(s.secondaryContainer, t.primary, reason: t.id);
        expect(s.onSecondaryContainer, t.onPrimary, reason: t.id);
        expect(s.secondaryContainer, isNot(t.body), reason: t.id);
        expect(s.outlineVariant, t.hairline, reason: t.id);
        expect(Aigaio.contrast(s.onSecondaryContainer, s.secondaryContainer), greaterThanOrEqualTo(4.5), reason: t.id);
      }
    });

    test('U4-2: ο ΚΛΕΙΣΤΟΣ διακόπτης έχει κουκκίδα και περίγραμμα ≥ 3:1· ο ανοιχτός όπως πριν', () {
      for (final t in _all) {
        final sw = buildTheme(t.dark ? Brightness.dark : Brightness.light, t).switchTheme;
        final off = <WidgetState>{};
        final on = {WidgetState.selected};
        expect(sw.thumbColor!.resolve(off), t.textTertiary, reason: t.id);
        expect(sw.trackOutlineColor!.resolve(off), t.textTertiary, reason: t.id);
        expect(sw.thumbColor!.resolve(on), isNull, reason: '${t.id}: ανοιχτός = προεπιλογή');
        expect(sw.trackOutlineColor!.resolve(on), Colors.transparent, reason: t.id);
        expect(sw.trackOutlineColor!.resolve({WidgetState.disabled}), Colors.transparent, reason: t.id);
        expect(Aigaio.contrast(t.textTertiary, t.background), greaterThanOrEqualTo(3.0), reason: '${t.id}: κουκκίδα σε ράγα');
        expect(Aigaio.contrast(t.textTertiary, t.card), greaterThanOrEqualTo(3.0), reason: '${t.id}: περίγραμμα σε κάρτα');
      }
    });

    test('U5-31 / U2b-20: τίτλοι διαλόγων όπως των φύλλων', () {
      final d = buildTheme(Brightness.light).dialogTheme;
      expect(d.titleTextStyle!.fontSize, 20);
      expect(d.titleTextStyle!.fontWeight, FontWeight.w800);
      expect(d.contentTextStyle!.fontSize, 15);
    });

    testWidgets('FoodTheme / ExerciseTheme: επιλογές, κέρσορας και ετικέτα πεδίου στο χρώμα της κατηγορίας', (t) async {
      late ThemeData food, exercise;
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Column(children: [
          FoodTheme(child: Builder(builder: (c) {
            food = Theme.of(c);
            return const SizedBox();
          })),
          ExerciseTheme(child: Builder(builder: (c) {
            exercise = Theme.of(c);
            return const SizedBox();
          })),
        ]),
      ));
      const p = Aigaio.darkTheme;
      expect(food.colorScheme.secondaryContainer, p.foodSolid, reason: 'U3a-11: όχι το λαδί του Σώματος');
      expect(food.colorScheme.primary, p.foodSolid);
      expect(food.textSelectionTheme.cursorColor, p.food, reason: 'U3a-15');
      final focused = WidgetStateProperty.resolveAs<TextStyle?>(food.inputDecorationTheme.floatingLabelStyle, {WidgetState.focused});
      expect(focused!.color, p.food, reason: 'U3a-15: #15803D σε σκούρο φόντο ήταν 3,8:1');
      final error = WidgetStateProperty.resolveAs<TextStyle?>(food.inputDecorationTheme.floatingLabelStyle, {WidgetState.focused, WidgetState.error});
      expect(error!.color, isNull, reason: 'στο λάθος μένει η προεπιλογή (κόκκινο)');
      expect(exercise.colorScheme.primary, p.exerciseSolid, reason: 'U5-30');
      expect(exercise.colorScheme.secondaryContainer, p.exerciseSolid);
      expect(Aigaio.contrast(p.food, p.background), greaterThanOrEqualTo(4.5));
    });
  });

  // ------------------------------------------------------------------ διάρκειες
  test('Διάρκειες: ένας τρόπος, ολόκληρες λέξεις (U2a-02, U1a-3, U1b-04)', () {
    expect(hmList(83), '1 ώρα 23 λεπτά');
    expect(hmList(425), '7 ώρες 5 λεπτά');
    expect(hmList(45), '45 λεπτά');
    expect(hmList(1), '1 λεπτό');
    expect(hmList(60), '1 ώρα');
    expect(hmList(-5), '−5 λεπτά');
    expect(hoursMinutesShort(436), '7 ώρες 16 λεπτά');
    expect(hoursMinutesShort(22), '22 λεπτά');
    for (final m in [0, 1, 2, 59, 60, 61, 119, 120, 436, 1439]) {
      expect(hmList(m), isNot(matches(RegExp(r'\d (ω|λ)\b'))), reason: '$m');
      expect(hoursMinutesShort(m), isNot(contains('.')), reason: '$m');
    }
  });

  // S12-05 (μέρος format.dart): ημερολογιακές μέρες σωστά πάνω από την αλλαγή ώρας (CI: TZ=Europe/Athens). Με το κλασικό
  // λάθος (διαφορά τοπικών μεσάνυχτων σε ώρες ÷ 24) η μέρα του Μαρτίου «χάνεται»: 20 αντί για 21 (πρώτος έλεγχος θερμίδων).
  test('S12-05: daysBetween πάνω από τις αλλαγές ώρας', () {
    expect(daysBetween(DateTime(2027, 3, 8), DateTime(2027, 3, 29)), 21);
    expect(daysBetween(DateTime(2027, 3, 20), DateTime(2027, 4, 4)), 15);
    expect(daysBetween(DateTime(2027, 3, 27, 23, 30), DateTime(2027, 3, 28, 0, 30)), 1);
    expect(daysBetween(DateTime(2026, 10, 24), DateTime(2026, 10, 26)), 2);
    expect(daysBetween(DateTime(2026, 10, 25, 23, 59), DateTime(2026, 10, 25, 0, 1)), 0);
    expect(daysBetween(DateTime(2027, 3, 29), DateTime(2027, 3, 8)), -21);
  });

  // ------------------------------------------------------------------ γραφήματα
  group('Γραφήματα', () {
    test('U1b-09 / U1a-19β: άξονας σε ίσες στρογγυλές τιμές που περιέχουν τα δεδομένα', () {
      // (κάτω, βήμα, διαστήματα): υπολογισμένα με τον κανόνα 1/2/5 × 10ⁿ (python).
      expect(chartAxis(91.14, 97.86, maxIntervals: 2, minStep: 1), (90.0, 5.0, 2), reason: 'οξυγόνο: 90 · 95 · 100');
      expect(chartAxis(54.2, 63.8, maxIntervals: 3, minStep: 1), (50.0, 5.0, 3), reason: 'παλμοί: 50 · 55 · 60 · 65');
      expect(chartAxis(59.4, 61.6, maxIntervals: 3, minStep: 1), (59.0, 1.0, 3), reason: 'ακέραιες ετικέτες: ποτέ βήμα 0,5');
      expect(chartAxis(81.8, 83.6, maxIntervals: 3), (81.0, 1.0, 3));
      expect(chartAxis(272.5, 614.5, maxIntervals: 3, steps: minuteTickSteps, minStep: 1), (240.0, 240.0, 2), reason: 'λεπτά: 4:00 · 8:00 · 12:00');
      expect(chartAxis(0, 12724, maxIntervals: 2, minStep: 1), (0.0, 10000.0, 2));
      final (lo, step, n) = chartAxis(-0.37, 0.47);
      expect(lo, closeTo(-0.5, 1e-9));
      expect(step, closeTo(0.5, 1e-9));
      expect(n, 2);
      // Ιδιότητα: πάντα περιέχει τα δεδομένα, βήμα από 1/2/5 × 10ⁿ.
      for (final (a, b) in [(0.3, 0.9), (12.0, 13.1), (101.0, 188.0), (-3.2, 7.7), (5000.0, 5002.0)]) {
        final (x, s, k) = chartAxis(a, b, maxIntervals: 3);
        expect(x, lessThanOrEqualTo(a + 1e-9));
        expect(x + s * k, greaterThanOrEqualTo(b - 1e-9));
        final m = s / _pow10(s);
        expect([1.0, 2.0, 5.0].any((v) => (v - m).abs() < 1e-6), isTrue, reason: '$s');
      }
    });

    test('U1b-10: η γραμμή κόβεται σε μεγάλο κενό, όχι σε συνηθισμένη απόσταση', () {
      final d0 = DateTime(2026, 8, 1);
      final daily = [for (var i = 0; i < 90; i++) if (i < 30 || i > 50) (DateTime(2026, 8, 1 + i), 60.0)];
      expect(longGaps(daily), [DateTime(2026, 9, 21)]);
      expect(lineSegments(daily, longGaps(daily)).length, 2);
      // Ζυγίσεις Δε/Τε/Πα: τα Σαββατοκύριακα (3 μέρες) δεν κόβουν.
      final mwf = [
        for (var i = 0; i < 56; i++)
          if ([1, 3, 5].contains(DateTime(2026, 8, 1 + i).weekday)) (DateTime(2026, 8, 1 + i), 82.0)
      ];
      expect(longGaps(mwf), isEmpty);
      // Τρεις εβδομάδες χωρίς ζύγιση: κόβεται.
      final hole = [for (final p in mwf) if (p.$1.isBefore(DateTime(2026, 8, 10)) || p.$1.isAfter(DateTime(2026, 8, 30))) p];
      expect(longGaps(hole), [DateTime(2026, 8, 31)]);
      // Κάθε μέρα: 2 μέρες που λείπουν (κενό 3) δεν κόβουν· 3 (κενό 4) κόβουν.
      expect(longGaps([for (var i = 0; i < 20; i++) if (i != 5 && i != 6) (d0.add(Duration(days: i)), 1.0)]), isEmpty);
      expect(longGaps([for (var i = 0; i < 20; i++) if (i < 5 || i > 7) (DateTime(2026, 8, 1 + i), 1.0)]), [DateTime(2026, 8, 9)]);
    });

    test('U1a-20: το μικρό γράφημα του βάρους δεν μεγαλώνει τον θόρυβο', () {
      final (lo, hi) = sparkRange([82.2, 82.0], 3);
      expect(hi - lo, closeTo(3, 1e-9));
      expect((82.2 - 82.0) / (hi - lo), lessThanOrEqualTo(0.1));
      final (a, b) = sparkRange([60, 70], 8);
      expect((a, b), (60.0, 70.0), reason: 'μεγαλύτερο εύρος: όπως είναι');
    });

    testWidgets('U1a-18: τα γράμματα των γραφημάτων ακολουθούν το μέγεθος του συστήματος (1× ως 1,6×)', (t) async {
      final got = <double>[];
      for (final s in [0.85, 1.0, 1.3, 2.0]) {
        await t.pumpWidget(MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(s)),
          child: Builder(builder: (c) {
            got.add(chartTextScale(c));
            return const SizedBox();
          }),
        ));
      }
      expect(got[0], closeTo(1.0, 1e-9), reason: 'ποτέ μικρότερα από πριν');
      expect(got[1], closeTo(1.0, 1e-9));
      expect(got[2], closeTo(1.3, 1e-9));
      expect(got[3], closeTo(1.6, 1e-9));
    });

    testWidgets('U1a-10: η τιμή της τελευταίας ράβδου ζωγραφίζεται πάνω σε πλάκα στο χρώμα της κάρτας', (t) async {
      // 4 ράβδοι σε 200 px: θέση 50 px, ράβδος 26 px. Η τρίτη (8) πιάνει x 112–138 σε όλο το ύψος. Η τελευταία (5) έχει
      // ετικέτα πλάτους W (62–86 px): ξεκινά στο x = 200 − W (ως το δεξί άκρο)· η πλάκα ξεκινά 3 px πιο αριστερά, μέσα
      // στη γειτονική ράβδο. Ύψος 170: πάνω 22, κάτω 20, ράβδος 5/8 × 128 = 80 → κορυφή στο 70, ετικέτα 4 px πιο πάνω.
      const style = TextStyle(fontFamily: fontFamily, fontSize: 12, fontWeight: FontWeight.w700, fontFeatures: tabular);
      var label = '8';
      var tp = TextPainter(text: TextSpan(text: label, style: style), textDirection: TextDirection.ltr)..layout();
      while (tp.width < 62) {
        tp.dispose();
        label += '8';
        tp = TextPainter(text: TextSpan(text: label, style: style), textDirection: TextDirection.ltr)..layout();
      }
      expect(tp.width, lessThanOrEqualTo(86));
      final x = 200 - tp.width;
      final probeX = (x - 1.5).floor(); // ολόκληρο pixel μέσα στα 3 px της πλάκας πριν από το κείμενο
      final probeY = (70 - 4 - tp.height / 2).floor();
      expect(probeX, inInclusiveRange(112, 137));
      const key = ValueKey('bars');
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 200,
                child: BarChart(values: const [8, 8, 8, 5], labels: const ['α', 'β', 'γ', 'δ'], valueLabel: (v) => label),
              ),
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
      final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(key));
      final bytes = (await t.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 1);
        final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        img.dispose();
        return data!;
      }))!;
      int px(int x, int y) => bytes.getUint32((y * 200 + x) * 4);
      expect(px(probeX, probeY), 0xFFFFFFFF, reason: 'πλάκα στο χρώμα της κάρτας πάνω από τη γειτονική ράβδο');
      expect(px(125, 35) & 0xFF, lessThan(0xFF), reason: 'έξω από την πλάκα η ράβδος (ημιδιάφανη) φαίνεται κανονικά');
      tp.dispose();
    });
  });

  testWidgets('S10-10 (αίτημα f4): η κρυμμένη καρτέλα δεν τρέχει κινήσεις, κρατά όμως την κατάστασή της', (t) async {
    Widget app(int i) => MaterialApp(
          home: LazyIndexedStack(index: i, children: const [SizedBox(key: ValueKey('p0')), SizedBox(key: ValueKey('p1'))]),
        );
    bool ticking(String k) => t
        .widgetList<TickerMode>(
            find.ancestor(of: find.byKey(ValueKey(k), skipOffstage: false), matching: find.byType(TickerMode, skipOffstage: false)))
        .every((m) => m.enabled);
    await t.pumpWidget(app(0));
    await t.pumpWidget(app(1));
    expect(ticking('p1'), isTrue);
    expect(find.byKey(const ValueKey('p0'), skipOffstage: false), findsOneWidget, reason: 'χτισμένη μία φορά, μένει');
    expect(ticking('p0'), isFalse);
  });

  // ------------------------------------------------------------------ TrendPill
  testWidgets('U1a-14: οι δύο τελευταίες λέξεις του χαπιού μένουν μαζί· το κείμενο της ρύθμισης ίδιο', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: const Scaffold(
        body: Column(children: [
          TrendPill('−1,1 kg από 13/8', keepLastWords: true),
          TrendPill('+1 · συνήθως 59'),
        ]),
      ),
    ));
    final pills = t.widgetList<TrendPill>(find.byType(TrendPill)).toList();
    expect(pills.first.text, '−1,1 kg από 13/8');
    expect(find.text('−1,1 kg από 13/8'), findsOneWidget);
    expect(find.text('+1 · συνήθως 59'), findsOneWidget, reason: 'χωρίς τη ρύθμιση: όπως πριν');
  });

  // ------------------------------------------------------------------ PageFrame (U1a-1 / U3b-13)
  group('U1a-1: θέσεις που βάζουν μόνες τους το κενό', () {
    testWidgets('πρώτη ορατή ή άδεια θέση: η πρώτη κάρτα ξεκινά στο ίδιο ύψος· ανάμεσα πάντα 14', (t) async {
      await _pumpFrame(t, const [SizedBox(key: ValueKey('a'), height: 40), SizedBox(key: ValueKey('b'), height: 40)]);
      final top = t.getTopLeft(find.byKey(const ValueKey('a'))).dy;
      expect(t.getTopLeft(find.byKey(const ValueKey('b'))).dy - top, 40 + PageFrame.gap);

      await _pumpFrame(t, const [_Slot(visible: true, k: 's'), SizedBox(key: ValueKey('b'), height: 40)]);
      expect(t.getTopLeft(find.byKey(const ValueKey('s'))).dy, top, reason: 'ορατή θέση πρώτη: χωρίς κενό από πάνω');
      expect(t.getTopLeft(find.byKey(const ValueKey('b'))).dy - top, 50 + PageFrame.gap);

      await _pumpFrame(t, const [_Slot(visible: false, k: 's'), SizedBox(key: ValueKey('b'), height: 40)]);
      expect(t.getTopLeft(find.byKey(const ValueKey('b'))).dy, top, reason: 'άδεια θέση πρώτη: τίποτα');
    });

    testWidgets('τίτλος ενότητας μετά από θέση: 22, όπως μετά από κάρτα', (t) async {
      await _pumpFrame(t, const [SizedBox(key: ValueKey('a'), height: 40), SectionHeader('Επίσης')]);
      final ref = t.getTopLeft(find.text('Επίσης')).dy - t.getBottomLeft(find.byKey(const ValueKey('a'))).dy;
      expect(ref, 22);
      await _pumpFrame(t, const [
        SizedBox(key: ValueKey('a'), height: 40),
        _Slot(visible: true, k: 's'),
        SectionHeader('Επίσης'),
      ]);
      expect(t.getTopLeft(find.text('Επίσης')).dy - t.getBottomLeft(find.byKey(const ValueKey('s'))).dy, 22);
      await _pumpFrame(t, const [
        SizedBox(key: ValueKey('a'), height: 40),
        _Slot(visible: false, k: 's'),
        SectionHeader('Επίσης'),
      ]);
      expect(t.getTopLeft(find.text('Επίσης')).dy - t.getBottomLeft(find.byKey(const ValueKey('a'))).dy, 22);
    });
  });

  // ------------------------------------------------------------------ Σήμερα
  group('Σήμερα', () {
    late TrainingStore previous;
    setUp(() {
      previous = TrainingStore.main;
      TrainingStore.main = TrainingStore(io: MemoryTrainingIO());
    });
    tearDown(() => TrainingStore.main = previous);

    testWidgets('U1a-13: Δευτέρα: η Διατροφή πάνω από την «Η εβδομάδα σου»', (t) async {
      final monday = DateTime(2026, 10, 26, 10, 0);
      expect(monday.weekday, DateTime.monday);
      await _pumpToday(t, _sample(monday), monday);
      expect(find.byType(WeekCard), findsOneWidget, reason: 'η κάρτα της εβδομάδας φαίνεται τη Δευτέρα');
      expect(t.getTopLeft(find.byType(FoodTodayCard)).dy, lessThan(t.getTopLeft(find.byType(WeekCard)).dy));
    });

    testWidgets('U1a-7: «Ενημέρωση χθες 18:40» με πεζό', (t) async {
      final read = DateTime(2026, 10, 23, 18, 40);
      final s = _sample(read);
      await _pumpToday(t, s, DateTime(2026, 10, 24, 9, 0));
      final text = t.widget<Text>(find.byKey(const ValueKey('today-updated'))).data!;
      expect(text, 'Ενημέρωση χθες 18:40');
    });

    testWidgets('U1a-22: «Γράψε τη μέση» με περίγραμμα (ένα γεμάτο κουμπί ανά οθόνη)', (t) async {
      final friday = DateTime(2026, 10, 23, 9, 0);
      expect(friday.weekday, DateTime.friday);
      await _pumpToday(t, _sample(friday), friday);
      expect(find.byKey(const ValueKey('today-waist')), findsOneWidget);
      expect(t.widget(find.byKey(const ValueKey('today-waist'))), isA<OutlinedButton>());
    });

    testWidgets('U1a-11: άγνωστο σχέδιο πηγών: η ειδοποίηση με το κουμπί, χωρίς δεύτερη κάρτα ύπνου', (t) async {
      final now = DateTime(2026, 11, 20, 9, 0);
      final s = _sample(now)..debugSetPlan(SourcePlan([SourceEra(Source.none, DateTime(2026, 11, 15))]), state: PlanState.unknown);
      await _pumpToday(t, s, now);
      expect(find.byKey(const ValueKey('plan-unknown')), findsOneWidget);
      expect(find.byType(OuraSleepTodayCard), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Διάλεξε πηγή'), findsOneWidget, reason: 'U2a-21: γεμάτο κουμπί');
    });

    testWidgets('U2a-21: η μία ενέργεια της κάρτας σφάλματος είναι γεμάτο κουμπί', (t) async {
      final now = DateTime(2026, 10, 24, 9, 0);
      final s = _sample(now)..error = {'kind': 'other'};
      await _pumpToday(t, s, now);
      expect(find.widgetWithText(FilledButton, 'Δοκίμασε ξανά'), findsOneWidget);
    });

    testWidgets('U1a-6: ένα όνομα για τη χαμηλότερη τιμή οξυγόνου', (t) async {
      final now = DateTime(2026, 10, 24, 9, 0);
      final s = _sample(now);
      await _pumpToday(t, s, now);
      final texts = t.widgetList<TrendPill>(find.byType(TrendPill)).map((p) => p.text).toList();
      expect(texts.where((x) => x.startsWith('Χαμηλότερη μέτρηση') || x.startsWith('Χαμηλότερο ')), isEmpty);
    });
  });

  // ------------------------------------------------------------------ widgets αρχικής οθόνης (Dart πλευρά)
  group('Widgets αρχικής οθόνης', () {
    test('U7-13: ολόκληρες λέξεις στο στιγμιότυπο· U7-16: χωρίς νύχτα/ζύγιση η πηγή το λέει', () {
      final now = DateTime(2026, 11, 7, 10, 20);
      final store = _sample(now);
      final snap = buildWidgetSnapshot(store, sampleFoodStore(now), now);
      final json = jsonEncode(snap);
      expect(json, isNot(contains('′')), reason: 'ποτέ «34′»');
      for (final abbr in ['Υδατ.', 'Μεταβολ.', 'Θερμοκρ.']) {
        expect(json, isNot(contains(abbr)), reason: abbr);
      }
      final kinds = snap['kinds'] as Map;
      final food = (kinds[WKind.food] as Map)['m'] as Map;
      expect((food['carbs'] as Map)['l'], 'Υδατάνθρακες');
      final sleep = (kinds[WKind.sleep] as Map)['m'] as Map;
      final sl = sleep['sleepMin'] as Map;
      expect(sl['u'], ' ώρες');
      if (sl['us'] != null) expect(sl['us'] as String, isNot(contains('ώρες')), reason: 'το «συνήθως» χωρίς μονάδα, να χωρά');
      final move = (kinds[WKind.move] as Map)['m'] as Map;
      if (move['activeMin'] != null) expect((move['activeMin'] as Map)['u'], ' λεπτά');

      final empty = buildWidgetSnapshot(HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(now)), sampleFoodStore(now),
          DateTime(2027, 6, 1));
      expect(((empty['kinds'] as Map)[WKind.sleep] as Map)['src'], 'καμία πρόσφατη νύχτα');
      final noBody = HealthStore()..data = Dashboard.fromJson({...sampleDashboardJson(now), 'body': <Object>[]});
      expect(((buildWidgetSnapshot(noBody, sampleFoodStore(now), now)['kinds'] as Map)[WKind.body] as Map)['src'], 'καμία ζύγιση ακόμα');
    });

    test('U7-17 ε: κάθε πόρος που ζητούν τα widgets υπάρχει μετά το patch του manifest', () {
      final dir = Directory.systemTemp.createTempSync('r1f9');
      addTearDown(() => dir.deleteSync(recursive: true));
      final m = File('${dir.path}/AndroidManifest.xml')
        ..writeAsStringSync('<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <application\n        android:label="ygeia_forma">\n'
            '        <activity\n            android:name=".MainActivity"\n            android:exported="true">\n'
            '        </activity>\n    </application>\n</manifest>\n');
      final r = Process.runSync('python3', ['tools/android/patch_manifest.py', m.path]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      final res = Directory('${dir.path}/res');
      final values = [
        for (final f in res.listSync(recursive: true).whereType<File>())
          if (f.path.contains('/values')) f.readAsStringSync(),
      ].join('\n');
      for (final f in res.listSync(recursive: true).whereType<File>()) {
        final x = f.readAsStringSync();
        for (final ref in RegExp(r'@(layout|drawable|color)/(\w+)').allMatches(x)) {
          final kind = ref.group(1)!, name = ref.group(2)!;
          if (kind == 'color') {
            expect(values, contains('name="$name"'), reason: '${f.path}: @color/$name');
          } else {
            expect(File('${res.path}/$kind/$name.xml').existsSync(), isTrue, reason: '${f.path}: @$kind/$name');
          }
        }
      }
      for (final k in ['sleep', 'move', 'food', 'body']) {
        expect(File('${res.path}/xml/widget_$k.xml').readAsStringSync(), contains('android:previewLayout="@layout/qw_preview_$k"'));
      }
      final quick = File('${res.path}/xml/widget_quickfood.xml').readAsStringSync();
      expect(quick, contains('android:minWidth="160dp"'), reason: 'U7-17 β');
      expect(quick, contains('android:minHeight="60dp"'), reason: 'U7-17 γ');
      expect(File('${res.path}/layout/quick_workout_widget.xml').readAsStringSync(), contains('android:id="@+id/qw_head"'));
      expect(File('${res.path}/drawable/qw_button_food.xml').readAsStringSync(), contains('<ripple'), reason: 'U7-17 δ');
    });

    test('U4-5: «Διαφάνεια φόντου» = 100 − αδιαφάνεια· η προεπιλογή Μπορντό (92) δείχνει 8%', () {
      final src = File('lib/pages/widget_config_page.dart').readAsStringSync();
      expect(src, contains(r"text: '${100 - _s.opacity}%'"));
      expect(src, contains('_s.opacity = 100 - v.round()'));
      expect(src, contains("if (!wall)\n        _Group(title: 'Διαφάνεια φόντου'"));
      expect(100 - wThemes.first.op, 8);
      expect(src.split('ChoiceChip(').length - 1, src.split('showCheckmark: false').length - 1, reason: 'U4-9');
    });
  });
}

double _pow10(double v) {
  var p = 1.0;
  while (p * 10 <= v + 1e-12) {
    p *= 10;
  }
  while (p > v + 1e-12) {
    p /= 10;
  }
  return p;
}
