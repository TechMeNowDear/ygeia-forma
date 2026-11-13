// Round 2 · g5: κουμπί μέσης (αντίθεση), άξονες διάρκειας, σύνοψη Τάσεων, έτος στις ημερομηνίες, διάρκειες με λέξεις
// (Πρόοδος, επεξεργαστής προγράμματος). Κάθε αναμενόμενη τιμή βγήκε από τον γραμμένο κανόνα (με το χέρι ή με python
// στο /home/claude/scratch/g5/: line_axis.py, contrast_weigh.py), όχι από τη νέα υλοποίηση. Φανταστικές τιμές
// (δημόσιο repo).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/exercise/ex_data.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/pages/today.dart' show TodayPage;
import 'package:ygeia_forma/pages/training/program_editor.dart' show WorkoutEditorPage;
import 'package:ygeia_forma/pages/training/progress_page.dart';
import 'package:ygeia_forma/pages/training/training_common.dart' show restText;
import 'package:ygeia_forma/pages/trends.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/training/program.dart' show Cardio, PlanItem, Workout;
import 'package:ygeia_forma/training/progress.dart' show walkHrrDef;
import 'package:ygeia_forma/training/session.dart' show Session;
import 'package:ygeia_forma/training/training_store.dart';
import 'package:ygeia_forma/trends.dart';
import 'package:ygeia_forma/widgets.dart';

import 'sample_data.dart';
import 'sample_food.dart';

const _all = [...Aigaio.dayThemes, ...Aigaio.nightThemes];

/// Χρώμα των γραμμάτων [text] μέσα στο [within], όπως τα ζωγραφίζει η Flutter (το στυλ του RichText).
Color _ink(WidgetTester t, Finder within, String text) => t
    .widget<RichText>(find.descendant(of: within, matching: find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText() == text)))
    .text
    .style!
    .color!;

Future<void> _pumpToday(WidgetTester t, Aigaio theme, HealthStore s, DateTime now) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = const Size(400, 6000);
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: buildTheme(theme.dark ? Brightness.dark : Brightness.light, theme),
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

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 4000)}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: w)));
  await t.pumpAndSettle();
}

/// Παλμοί ύπνου κάθε μέρα, γύρω στα 60, χωρίς αλλαγή (python, /home/claude/scratch/R2-D/trends_port.py: «Σταθερό»,
/// ~28 ανεξάρτητες μέρες, όχι «Λίγες μέρες για συμπέρασμα»).
const _pat = [0, 2, -1, 1, -2, 1, 0, -1, 2, -2, 1, 0];
Map<String, Map<String, double>> _sleepHrDays(DateTime today, int days) => {
      for (var i = 0; i < days; i++) dateKey(DateTime(today.year, today.month, today.day - i)): {K.sleepHr: 60.0 + _pat[i % 12]},
    };

MetricDef _def(String key) => trendMetrics.firstWhere((m) => m.key == key);

TrendResult _result(String key, TrendStatus status, {double? effective, bool rereading = false}) => TrendResult(
      def: _def(key),
      status: status,
      current: 60.0,
      previous: 60.0,
      nCurrent: 30,
      nPrevious: 30,
      needed: 20,
      z: 0.0,
      points: const [],
      currentFrom: DateTime(2026, 10, 15),
      previousFrom: DateTime(2026, 9, 15),
      previousEnd: DateTime(2026, 10, 14),
      end: DateTime(2026, 11, 13),
      changedOn: status == TrendStatus.sourceChange ? DateTime(2026, 10, 20) : null,
      rereading: rereading,
      effectiveCurrent: effective,
    );

// Ίδιο περπάτημα με το test/progress_test.dart (μόνο για την οθόνη της Προόδου).
final _now = DateTime(2026, 12, 31, 20, 0);
const _noise = [2, -2, 1, -1, 0, 2, -1, -2, 1, 0, -1, 2];

Session _walk(int daysAgo, {int hr = 110, double km = 2.3, int? hrr, int sec = 1800}) {
  final start = DateTime(_now.year, _now.month, _now.day - daysAgo, 18);
  return Session(
    id: 'w$daysAgo-$hr',
    workout: 'walk',
    name: 'Περπάτημα',
    programId: '',
    start: start,
    end: start.add(Duration(seconds: sec + 60)),
    cardioMinutes: sec ~/ 60,
    cardioSec: sec,
    meters: km * 1000,
    gps: true,
    hrAvg: hr,
    hr: [for (var t = 0; t <= sec; t += 10) [t, t < 300 ? hr - 12 : hr]],
    hrrEnd: hrr == null ? null : 120,
    hrr1: hrr == null ? null : 120 - hrr,
    source: 'watch',
  );
}

void main() {
  // ------------------------------------------------------------------ R2-D-3
  group('R2-D-3: «Γράψε τη μέση» στη Σήμερα (κάρτα πάνω στο φόντο της σελίδας)', () {
    testWidgets('γράμματα ≥ 4,5:1, εικονίδιο/περίγραμμα ≥ 3:1 πάνω στο απαλό φόντο του Σώματος, σε όλα τα θέματα', (t) async {
      // Δεδομένα της Πέμπτης 18:00, Παρασκευή πρωί: μέρα ζύγισης (Δε/Τε/Πα) και μέσης (Παρασκευή), χωρίς ζύγιση ακόμα.
      final read = DateTime(2026, 10, 22, 18, 0);
      final friday = DateTime(2026, 10, 23, 9, 0);
      expect(friday.weekday, DateTime.friday);
      for (final theme in _all) {
        final s = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(read));
        s.history = sampleHistory(read, s.data!);
        await _pumpToday(t, theme, s, friday);
        final bg = Color.alphaBlend(theme.tint(theme.body), theme.background);
        final waist = find.byKey(const ValueKey('today-waist'));
        expect(waist, findsOneWidget, reason: theme.id);
        // python (contrast_weigh.py): πριν, χρώμα Σώματος 4,25 / 4,02 / 4,39 στα φωτεινά.
        expect(Aigaio.contrast(_ink(t, waist, 'Γράψε τη μέση'), bg), greaterThanOrEqualTo(4.5), reason: '${theme.id}/${theme.dark}');
        final icon = t.widget<Icon>(find.descendant(of: waist, matching: find.byIcon(Icons.straighten_rounded)));
        expect(icon.color, theme.body, reason: 'το εικονίδιο κρατά το χρώμα του Σώματος');
        expect(Aigaio.contrast(icon.color!, bg), greaterThanOrEqualTo(3.0), reason: theme.id);
        // Ίδια κάρτα: «Πώς ζυγίζομαι σωστά» (πριν «Αυγή» 4,45:1 στο κύριο χρώμα).
        final how = find.widgetWithText(TextButton, 'Πώς ζυγίζομαι σωστά');
        expect(how, findsOneWidget, reason: theme.id);
        expect(Aigaio.contrast(_ink(t, how, 'Πώς ζυγίζομαι σωστά'), bg), greaterThanOrEqualTo(4.5), reason: '${theme.id}/${theme.dark}');
      }
    });
  });

  // ------------------------------------------------------------------ R2-D-4
  group('R2-D-4: άξονας διάρκειας σφιχτός και τίμιος', () {
    // 30 νύχτες 6:30–7:30 (390–450 λεπτά).
    final nights = [for (var i = 0; i < 30; i++) 390.0 + (i * 37 % 61)];

    test('νύχτες 6:30–7:30: 6:00 · 7:00 · 8:00 (πριν 3:00 · 6:00 · 9:00, η γραμμή στο 17% του ύψους)', () {
      expect(nights.reduce(math.min), 390.0);
      expect(nights.reduce(math.max), 450.0);
      // Τάσεις: ύψος 150 → γράφημα 102 px, ελάχιστο εύρος 2 ώρες, μαζί οι δύο μεσαίες τιμές.
      expect(lineAxis([...nights, 420.0, 418.0], minRange: 120, plotHeight: 102, steps: minuteTickSteps, minStep: 1), (360.0, 60.0, 2));
      // Αναφορά για τον γιατρό: ύψος 96 → 48 px (2 διαστήματα).
      expect(lineAxis([...nights, 420.0], minRange: 120, plotHeight: 48, steps: minuteTickSteps, minStep: 1), (360.0, 60.0, 2));
      // Σελίδα μέτρησης (χωρίς ελάχιστο εύρος, 122 px): ίδιο με πριν.
      expect(lineAxis(nights, minRange: 1, plotHeight: 122, steps: minuteTickSteps, minStep: 1), (360.0, 60.0, 2));
    });

    test('τιμές πάνω στη γραμμή του άξονα: περιθώριο, γραμμές σε ολόκληρες ώρες', () {
      // 6:00–8:00 στην αναφορά: 5:00 · 7:00 · 9:00 (πριν 3:00 · 6:00 · 9:00).
      expect(lineAxis([360.0, 480.0, 420.0], minRange: 120, plotHeight: 48, steps: minuteTickSteps, minStep: 1), (300.0, 120.0, 2));
      // 5:00–9:00 στην αναφορά: 4:00 · 7:00 · 10:00 (πριν 4:00 · 8:00 · 12:00).
      expect(lineAxis([300.0, 540.0], minRange: 120, plotHeight: 48, steps: minuteTickSteps, minStep: 1), (240.0, 180.0, 2));
      // Ξύπνιος 5–40 λεπτά: 0:00 · 0:15 · 0:30 · 0:45, όπως πριν.
      expect(lineAxis([5.0, 40.0], minRange: 30, plotHeight: 102, steps: minuteTickSteps, minStep: 1), (0.0, 15.0, 3));
    });

    test('κάθε τιμή μέσα στον άξονα· γραμμές σε πολλαπλάσια της ώρας (ή του τετάρτου/μισάωρου)', () {
      for (final h in [48.0, 102.0, 122.0]) {
        for (var lo = 180; lo <= 600; lo += 5) {
          for (var wdt = 0; wdt <= 240; wdt += 5) {
            final vals = [lo.toDouble(), (lo + wdt).toDouble()];
            final (a, step, n) = lineAxis(vals, minRange: 120, plotHeight: h, steps: minuteTickSteps, minStep: 1);
            expect(a, lessThanOrEqualTo(lo), reason: '$lo+$wdt @$h');
            expect(a + step * n, greaterThanOrEqualTo(lo + wdt), reason: '$lo+$wdt @$h');
            expect(n, inInclusiveRange(2, h >= 72 ? 3 : 2));
            expect(a % math.min(step, 60.0), 0.0, reason: '$lo+$wdt @$h: $a/$step');
          }
        }
      }
    });

    test('τα άλλα γραφήματα όπως πριν (round 1: παλμοί 50/55/60/65, οξυγόνο 90/95/100)', () {
      expect(lineAxis([55.0, 63.0], minRange: 8, plotHeight: 102, minStep: 1), (50.0, 5.0, 3));
      expect(lineAxis([91.7, 97.3], minRange: 4, plotHeight: 102), (90.0, 5.0, 2));
      // chartAxis χωρίς anchor: ίδιο με πριν· με anchor 60 ξεκινά σε ολόκληρη ώρα.
      expect(chartAxis(348, 492, maxIntervals: 3, steps: minuteTickSteps), (180.0, 180.0, 2));
      expect(chartAxis(348, 492, maxIntervals: 3, steps: minuteTickSteps, anchor: 60), (300.0, 120.0, 2));
    });
  });

  // ------------------------------------------------------------------ R2-D-7
  group('R2-D-7: η σύνοψη των Τάσεων δεν καθησυχάζει για γραμμές που δεν συγκρίθηκαν', () {
    final stable = _result(K.sleepHr, TrendStatus.stable, effective: 28.0);

    test('ετικέτες όπως τα «χάπια»', () {
      expect(notComparedLabel(stable), isNull);
      expect(notComparedLabel(_result(K.sleepMin, TrendStatus.insufficient)), 'Λίγα δεδομένα');
      expect(notComparedLabel(_result(K.steps, TrendStatus.sourceChange)), 'Αλλαγή πηγής');
      expect(notComparedLabel(_result(K.spo2Avg, TrendStatus.sourceChange)), 'Αλλαγή ορισμού');
      expect(notComparedLabel(_result(K.sleepHr, TrendStatus.sourceChange, rereading: true)), 'Ενημερώνεται το ιστορικό');
      expect(notComparedLabel(_result(K.weight, TrendStatus.stable, effective: 2.0)), 'Λίγες ζυγίσεις για συμπέρασμα');
      expect(notComparedLabel(_result(K.sleepHr, TrendStatus.stable, effective: 2.0)), 'Λίγες μέρες για συμπέρασμα');
    });

    test('κείμενο της σύνοψης', () {
      expect(notComparedText(const []), isNull);
      expect(notComparedText([stable]), isNull);
      // Μόνο «Λίγες … για συμπέρασμα»: το κείμενο του γύρου 1.
      expect(notComparedText([stable, _result(K.weight, TrendStatus.stable, effective: 2.0)]), someInconclusiveText);
      final one = notComparedText([stable, _result(K.sleepMin, TrendStatus.insufficient), _result(K.steps, TrendStatus.insufficient)])!;
      expect(one,
          'Καμία διαφορά δεν πέρασε τα όρια ελέγχου. Όπου γράφει «Λίγα δεδομένα», δεν φαίνεται αν άλλαξε κάτι. Αυτό δεν είναι ιατρικός έλεγχος.');
      final many = notComparedText([
        _result(K.weight, TrendStatus.stable, effective: 2.0),
        _result(K.sleepMin, TrendStatus.insufficient),
        _result(K.steps, TrendStatus.sourceChange),
        _result(K.spo2Avg, TrendStatus.sourceChange),
        _result(K.sleepHr, TrendStatus.sourceChange, rereading: true),
        stable,
      ])!;
      expect(
          many,
          'Καμία διαφορά δεν πέρασε τα όρια ελέγχου. Όπου γράφει «Λίγες ζυγίσεις για συμπέρασμα», «Λίγα δεδομένα», «Αλλαγή πηγής», '
          '«Αλλαγή ορισμού» ή «Ενημερώνεται το ιστορικό», δεν φαίνεται αν άλλαξε κάτι. Αυτό δεν είναι ιατρικός έλεγχος.');
      for (final s in [one, many]) {
        expect(s, isNot(contains('μέσα στις συνηθισμένες')));
      }
    });

    testWidgets('σελίδα: σταθεροί παλμοί ύπνου, όλα τα άλλα «Λίγα δεδομένα» → η σύνοψη το λέει', (t) async {
      final today = DateTime(2026, 11, 13, 10);
      final s = HealthStore()..history = _sleepHrDays(today, 120);
      await _pump(t, TrendsPage(store: s, now: today));
      expect(find.textContaining('μέσα στις συνηθισμένες'), findsNothing);
      expect(
          find.text(
              'Καμία διαφορά δεν πέρασε τα όρια ελέγχου. Όπου γράφει «Λίγα δεδομένα», δεν φαίνεται αν άλλαξε κάτι. Αυτό δεν είναι ιατρικός έλεγχος.'),
          findsOneWidget);
    });
  });

  // ------------------------------------------------------------------ R2-D-9
  group('R2-D-9: έτος στις ημερομηνίες όταν το διάστημα περνά σε άλλη χρονιά', () {
    test('ετικέτες γραφήματος και διαστήματα', () {
      final year = spanDateLabel(DateTime(2025, 8, 17), DateTime(2026, 11, 13));
      expect(year(DateTime(2025, 8, 17)), '17 Αυγ 2025');
      expect(year(DateTime(2026, 11, 13)), '13 Νοε 2026');
      final same = spanDateLabel(DateTime(2026, 8, 16), DateTime(2026, 11, 13));
      expect(same(DateTime(2026, 8, 16)), '16 Αυγ');
      expect(dateSpanText(DateTime(2026, 8, 16), DateTime(2026, 11, 13)), '16 Αυγ – 13 Νοε');
      expect(dateSpanText(DateTime(2026, 8, 16), DateTime(2026, 11, 13), withYear: true), '16 Αυγ – 13 Νοε 2026');
      expect(dateSpanText(DateTime(2026, 12, 12), DateTime(2027, 1, 10), withYear: true), '12 Δεκ 2026 – 10 Ιαν 2027');
    });

    testWidgets('Τάσεις › 1 χρόνος: τα δύο διαστήματα με το έτος· 30 μέρες του ίδιου έτους χωρίς', (t) async {
      final today = DateTime(2026, 11, 13, 10);
      final s = HealthStore()..history = _sleepHrDays(today, 470);
      await _pump(t, TrendsPage(store: s, now: today));
      final row = find.byKey(const ValueKey('trend-${K.sleepHr}'));
      await t.ensureVisible(row);
      await t.tap(row);
      await t.pumpAndSettle();
      // 30 μέρες: 15/10–13/11 και 15/9–14/10 (ίδια χρονιά).
      expect(find.text('Τώρα · 15 Οκτ – 13 Νοε'), findsOneWidget);
      expect(find.text('Πριν · 15 Σεπ – 14 Οκτ'), findsOneWidget);
      final year = find.byKey(const ValueKey('period-year'));
      await t.ensureVisible(year);
      await t.tap(year);
      await t.pumpAndSettle();
      // 1 χρόνος: οι τελευταίοι 90 μέρες (16/8–13/11/2026) με τις ίδιες πέρσι (17/8–14/11/2025).
      expect(find.text('Τώρα · 16 Αυγ – 13 Νοε 2026'), findsOneWidget);
      expect(find.text('Πριν · 17 Αυγ – 14 Νοε 2025'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------ R2-D-5 = R2-U2-06
  group('R2-D-5: διάρκειες με ολόκληρες λέξεις στην Πρόοδο και στον επεξεργαστή προγράμματος', () {
    test('κείμενα', () {
      expect(paceDiffText(26), '26 δευτερόλεπτα');
      expect(paceDiffText(1), '1 δευτερόλεπτο');
      expect(paceDiffText(60), '1 λεπτό');
      expect(paceDiffText(65), '1 λεπτό 5 δευτερόλεπτα');
      expect(paceDiffText(121), '2 λεπτά 1 δευτερόλεπτο');
      expect(walkHrrDef.label, 'Πτώση παλμών στο 1ο λεπτό');
      expect(restText(90), '1:30');
      expect(restText(45), '0:45');
      expect(restText(120), '2:00');
      expect(restText(600), '10:00');
    });

    testWidgets('Πρόοδος: κανένα «′/″», «1ο λεπτό», «15 λεπτά», ενεργός χρόνος σε ώρες/λεπτά', (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(400, 2600);
      addTearDown(t.view.reset);
      await t.runAsync(() => ExLibrary.load(inline: true));
      final tr = TrainingStore(io: MemoryTrainingIO(), clock: () => _now)..ready = true;
      tr.sessions.addAll([
        for (var i = 0; i < 6; i++) _walk(32 + i * 5, hr: 112 + _noise[i], hrr: 16 + _noise[i + 6]),
        for (var i = 0; i < 6; i++) _walk(1 + i * 5, hr: 105 + _noise[i + 3], hrr: 16 + _noise[i]),
      ]);
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: ProgressPage(training: tr, now: _now)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('prog-month')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('prog-walk-hr')), findsOneWidget);
      expect(find.textContaining(RegExp('[′″]')), findsNothing);
      // Round 3 (k1 · R3-B-2): «1ο λεπτό» με αδιάσπαστο κενό στη γραμμή της Προόδου.
      expect(find.text('Πτώση παλμών στο 1ο\u00A0λεπτό'), findsOneWidget);
      expect(find.textContaining('πάνω από 15 λεπτά και με GPS'), findsOneWidget);
      // 6 περπατήματα × 30 λεπτά = 3 ώρες (πριν «3,0 ώρες»).
      expect(find.text('6 → 6 · 3 ώρες'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('prog-walk-info')));
      await t.pumpAndSettle();
      expect(find.textContaining(RegExp('[′″]')), findsNothing);
      expect(find.textContaining('15 δευτερόλεπτα ανά km'), findsOneWidget);
    });

    testWidgets('επεξεργαστής: «30 λεπτά» στο αερόβιο, «ξεκούραση 1:30» στις ασκήσεις', (t) async {
      await _pump(t, WorkoutEditorPage(workout: Workout(id: 'c', name: 'Περπάτημα', cardio: Cardio(minutes: 30))), size: const Size(400, 900));
      expect(find.text('30 λεπτά'), findsOneWidget);
      expect(find.textContaining(RegExp('[′″]')), findsNothing);
      await _pump(t, WorkoutEditorPage(workout: Workout(id: 'a', name: 'Προπόνηση Α', items: [PlanItem(ex: 'db_curl', rest: 90)])),
          size: const Size(400, 900));
      // R7-U3-14 (f2): «άφησε», όπως στην προπόνηση (πριν «ρεζέρβα 2»).
      expect(find.textContaining('3 × 8–12 · ξεκούραση 1:30 · άφησε 2'), findsOneWidget);
      expect(find.textContaining(RegExp('[′″]')), findsNothing);
    });
  });
}
