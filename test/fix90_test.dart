// Έκδοση #90 (έλεγχος 9/11): ό,τι πρέπει να είναι σωστό πριν από την επίσκεψη στον καρδιολόγο (11/11).
// V-B-01 «Λίγες μέρες για συμπέρασμα» αντί για «Σταθερό» (Τάσεις, Πρόοδος, PDF) · V-B-02 σωστή φράση στο PDF ·
// V-B-04 όριο μέσα σε κάθε προπόνηση · V-B-05/06 έντιμα κείμενα στο όριο · V-A-05 «το όριο δεν σε προσέχει» στο κινητό ·
// V-B-08 ουδέτερη πτώση παλμών · V-A-01 ack μόνο μετά από ασφαλή εγγραφή · V-B-12 κιλά ↑ μέσα στο εύρος = πρόοδος.
// Όλα τα νούμερα είναι δοκιμαστικά.
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/exercise/ex_data.dart';
import 'package:ygeia_forma/exercise/ex_player.dart';
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/pages/report_page.dart';
import 'package:ygeia_forma/pages/training/hr_widgets.dart';
import 'package:ygeia_forma/pages/training/progress_page.dart';
import 'package:ygeia_forma/pages/training/session_page.dart';
import 'package:ygeia_forma/pages/training/training_page.dart';
import 'package:ygeia_forma/pages/training/walk_widgets.dart';
import 'package:ygeia_forma/pages/trends.dart';
import 'package:ygeia_forma/report.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/training/progress.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/training_store.dart';
import 'package:ygeia_forma/training/wear_link.dart';
import 'package:ygeia_forma/trends.dart';
import 'package:ygeia_forma/widgets.dart';

import 'sample_data.dart';
import 'training_sample.dart';

final now = DateTime(2026, 11, 20, 18, 0);

DateTime _add(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// Εγγραφή που αποτυγχάνει όσο [fail] (γεμάτος δίσκος, σφάλμα IO).
class _FlakyIO extends MemoryTrainingIO {
  bool fail = true;
  bool throws = false;
  @override
  Future<bool> write(String j) async {
    if (throws) throw const FileSystemExceptionLike();
    return fail ? false : super.write(j);
  }
}

class FileSystemExceptionLike implements Exception {
  const FileSystemExceptionLike();
}

/// Αρχείο που υπάρχει αλλά δεν διαβάστηκε.
class _ErrorIO extends MemoryTrainingIO {
  @override
  Future<({String state, String? json})> read() async => (state: 'error', json: null);
}

/// Περπάτημα από το ρολόι, όπως το στέλνει (μορφή του Protocol.kt).
Map<String, dynamic> _walk(String id, {Object? lim = _none}) {
  final start = now.subtract(const Duration(hours: 3)).millisecondsSinceEpoch;
  return {
    'v': 1,
    'kind': 'cardio',
    'id': id,
    'w': 'walk',
    'name': 'Περπάτημα',
    'start': start,
    'end': start + 1900 * 1000,
    'hrAvg': 112,
    'hrMax': 131,
    'hr': [
      for (var t = 0; t <= 1800; t += 10) [t, t < 600 ? 110 : 134],
    ],
    'cardio': {'activity': 'walk', 'sec': 1800, 'm': 2300.0, 'steps': 3100, 'gps': true},
    if (lim != _none) 'lim': lim,
  };
}

const _none = Object();

TrendResult _result(MetricDef def, TrendStatus status, {double? eff, double? crit}) => TrendResult(
      def: def,
      status: status,
      current: 80.2,
      previous: 80.0,
      nCurrent: 4,
      nPrevious: 4,
      needed: 3,
      z: 0.4,
      points: const [],
      currentFrom: _add(now, -89),
      previousFrom: _add(now, -179),
      previousEnd: _add(now, -90),
      end: now,
      effectiveCurrent: eff,
      tCritical: crit,
    );

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 1600)}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: w)));
  await t.pumpAndSettle();
}

/// Ζυγίσεις κάθε 25 μέρες (4 σε κάθε τρίμηνο): σταθερές τιμές, αλλά πολύ λίγες ανεξάρτητες για σύγκριση.
Map<String, Map<String, double>> _sparseWeighIns() => {
      for (var i = 0; i < 8; i++)
        dateKey(_add(dayOf(now), -(3 + 25 * i))): {K.weight: 80.0 + (i % 3) * 0.1, K.fatPct: 24.0 + (i % 2) * 0.2, K.smm: 33.0 + (i % 2) * 0.1},
    };

/// Παλμοί ύπνου κάθε νύχτα, σε αργό κύμα 30 ημερών (60 ± 3): οι νύχτες μοιάζουν πολύ με τις διπλανές τους, οπότε σε
/// 90 μέρες μένουν < 4 «πραγματικές» ανεξάρτητες. Ίδιο μοτίβο στα δύο τρίμηνα: σταθερό, αλλά χωρίς δύναμη σύγκρισης.
Map<String, Map<String, double>> _slowSleepHr() => {
      for (var i = 0; i < 400; i++) dateKey(_add(dayOf(now), -i)): {K.sleepHr: 60 + 3 * math.sin(2 * math.pi * i / 30)},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Η γραμματοσειρά της εφαρμογής: με τη γραμματοσειρά δοκιμών οι σελίδες A4 «ξεχειλίζουν» χωρίς λόγο.
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
  });

  // -------------------------------------------------------------------------
  group('V-B-01: «Δεν φτάνουν τα δεδομένα» δεν λέγεται «Σταθερό»', () {
    final hr = metricDef(K.sleepHr)!, weight = metricDef(K.weight)!;

    testWidgets('Τάσεις/Πρόοδος: το χάπι λέει «Λίγες μέρες για συμπέρασμα»', (t) async {
      await _pump(t, Column(children: [
        TrendStatusPill(r: _result(hr, TrendStatus.stable, eff: 2.0, crit: 9.925)),
        TrendStatusPill(r: _result(weight, TrendStatus.stable, eff: 3.5, crit: 9.925)),
        TrendStatusPill(r: _result(hr, TrendStatus.stable, eff: 12, crit: 2.7)),
      ]));
      expect(find.text('Λίγες μέρες για συμπέρασμα'), findsOneWidget);
      expect(find.text('Λίγες ζυγίσεις για συμπέρασμα'), findsOneWidget, reason: 'στο βάρος μετρούν οι ζυγίσεις');
      expect(find.text('Σταθερό'), findsOneWidget, reason: 'μόνο το πραγματικά σταθερό');
    });

    test('PDF: «Δεν φτάνουν για σύγκριση», ποτέ «Σταθερό» με λίγες μέρες', () {
      expect(reportTrendText(_result(weight, TrendStatus.stable, eff: 3.5, crit: 9.925), weight), 'Δεν φτάνουν για σύγκριση');
      expect(reportTrendText(_result(weight, TrendStatus.stable, eff: 12, crit: 2.7), weight), 'Σταθερό');
      expect(reportTrendText(_result(weight, TrendStatus.insufficient), weight), '—');
      expect(reportTrendText(_result(weight, TrendStatus.up, eff: 12, crit: 2.7), weight), startsWith('↑'));
    });

    test('αραιές ζυγίσεις στο τρίμηνο: «δεν φτάνουν» (όχι «σταθερό»)', () {
      final r = buildReport(_sparseWeighIns(), now);
      final w = r.stat(K.weight).trend!;
      expect(w.status, TrendStatus.stable);
      expect(w.inconclusive, isTrue, reason: '4 ζυγίσεις ανά 25 μέρες: < 4 «πραγματικές»');
    });

    test('παλμοί ύπνου που αλλάζουν πολύ αργά: η αναφορά τους βρίσκει «δεν φτάνουν»', () {
      final hr = buildReport(_slowSleepHr(), now).stat(K.sleepHr).trend!;
      expect(hr.status, TrendStatus.stable);
      expect(hr.inconclusive, isTrue, reason: 'αυτοσυσχέτιση ~0,95: λιγότερες από 4 «πραγματικές» νύχτες');
    });

    testWidgets('PDF στην οθόνη: «Δεν φτάνουν για σύγκριση» και σωστή φράση για ΗΚΓ/πίεση (V-B-02)', (t) async {
      final store = HealthStore()
        ..data = Dashboard.fromJson(sampleDashboardJson(now))
        ..history = _slowSleepHr();
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(680, 3600);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: ReportPage(store: store, now: now)));
      await t.pumpAndSettle();
      expect(find.text('Δεν φτάνουν για σύγκριση'), findsWidgets);
      final not = t.widget<Text>(find.descendant(of: find.byKey(const ValueKey('report-not-included')), matching: find.byType(Text)));
      final text = not.textSpan!.toPlainText();
      expect(text, isNot(contains('δεν έχει πρόσβαση')), reason: 'η εφαρμογή ζητά τις άδειες· η φράση ήταν ψευδής');
      expect(text, contains('ΗΚΓ'));
      expect(text, contains('πίεση'));
      expect(text, contains('Samsung Health Monitor'));
      expect(text, contains('δεν σημαίνει ότι ήταν φυσιολογικά'));
      // Έλεγχος του #90 (M-1): η εξήγηση δεν διαβάζεται σαν «δεν άλλαξε».
      expect(find.textContaining('δεν σημαίνει ότι δεν άλλαξε'), findsOneWidget);
      expect(find.textContaining('οι τιμές μοιάζουν πολύ μεταξύ τους'), findsNothing);
    });

    testWidgets('Πρόοδος · Σώμα: αραιές ζυγίσεις = «Λίγες ζυγίσεις για συμπέρασμα»', (t) async {
      await t.runAsync(() => ExLibrary.load(inline: true));
      final health = HealthStore()..history = _sparseWeighIns();
      final tr = TrainingStore(io: MemoryTrainingIO(), clock: () => now)..ready = true;
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(400, 2600);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: ProgressPage(training: tr, health: health, now: now)));
      await t.pumpAndSettle();
      // 3 μήνες: οι 4 ζυγίσεις του τριμήνου.
      await t.tap(find.byKey(const ValueKey('prog-quarter')));
      await t.pumpAndSettle();
      final body = find.byKey(const ValueKey('prog-body'));
      expect(find.descendant(of: body, matching: find.text('Λίγες ζυγίσεις για συμπέρασμα')), findsWidgets);
      expect(find.descendant(of: body, matching: find.text('Σταθερό')), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  group('V-B-04: το όριο μένει μέσα σε κάθε προπόνηση', () {
    test('κινητό: στην αρχή (και στην ελεύθερη άσκηση)· 0 = χωρίς όριο· γράφεται και διαβάζεται', () async {
      final t = sampleTraining(now);
      final s = t.start(t.program!.workout('A')!);
      expect(s.limit, 140);
      t.setHrLimit(120);
      expect(s.limit, 140, reason: 'αλλαγή ορίου μετά την αρχή δεν αλλάζει την προπόνηση');
      t.discard();
      t.setHrLimit(null);
      final f = t.startFree();
      expect(f.limit, 0);
      expect(f.limitUsed, isNull);
      final back = Session.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.limit, 140);
      expect(s.toJson()['lim'], 140);
    });

    test('παλιές προπονήσεις (χωρίς «lim»): δεν καταγράφηκε', () {
      final t = sampleTraining(now);
      expect(t.sessions.first.limit, isNull);
      expect(t.sessions.first.toJson().containsKey('lim'), isFalse);
    });

    test('ρολόι: το όριο που είχε· παλιό ρολόι (χωρίς «lim»): το όριο του κινητού τη στιγμή της εισαγωγής', () {
      final t = sampleTraining(now);
      t.importWatch(_walk('a', lim: 130));
      t.importWatch(_walk('b', lim: 0));
      t.importWatch(_walk('c'));
      Session byId(String id) => t.sessions.firstWhere((s) => s.id == 'w-$id');
      expect(byId('a').limit, 130);
      expect(byId('b').limit, 0);
      expect(byId('c').limit, 140);
    });

    test('παλμοί ρολογιού σε προπόνηση του κινητού χωρίς όριο μέσα: συμπληρώνεται, ποτέ δεν αλλάζει υπάρχον', () {
      final t = sampleTraining(now);
      final s = t.start(t.program!.workout('A')!)..limit = null;
      t.importWatch({'v': 1, 'kind': 'hr', 'sid': s.id, 'lim': 125});
      expect(s.limit, 125);
      t.importWatch({'v': 1, 'kind': 'hr', 'sid': s.id, 'lim': 150});
      expect(s.limit, 125);
    });

    test('προπόνηση του κινητού χωρίς όριο (0): το «lim» του ρολογιού δεν το αλλάζει', () {
      final t = sampleTraining(now)..setHrLimit(null);
      final s = t.start(t.program!.workout('A')!);
      expect(s.limit, 0);
      t.importWatch({'v': 1, 'kind': 'hr', 'sid': s.id, 'lim': 140});
      expect(s.limit, 0);
    });

    testWidgets('σύνοψη: κρίνεται μόνο με το δικό της όριο· χωρίς όριο τότε ή παλιά: καμία γραμμή, καμία κρίση', (tester) async {
      final s = Session(
        id: 'x',
        workout: 'walk',
        name: 'Περπάτημα',
        programId: '',
        start: now,
        end: now.add(const Duration(minutes: 30)),
        cardioMinutes: 30,
        hrMax: 134,
        hr: [
          for (var t = 0; t <= 1800; t += 10) [t, t < 600 ? 110 : 134],
        ],
      );
      Future<void> card(int? sessionLimit) async {
        s.limit = sessionLimit;
        await _pump(tester, SingleChildScrollView(child: HrCard(session: s, key: UniqueKey())));
      }

      // Τότε 130 (σήμερα ό,τι κι αν είναι): κρίνεται με το 130.
      await card(130);
      expect(find.textContaining('Πάνω από το όριο (130)'), findsOneWidget);
      // Τότε χωρίς όριο: καμία κρίση αναδρομικά.
      await card(0);
      expect(find.byKey(const ValueKey('hr-limit-line')), findsNothing);
      // Παλιά προπόνηση (πριν από την #90, δεν κράτησε όριο): μόνο οι παλμοί (V-B-04).
      await card(null);
      expect(find.byKey(const ValueKey('hr-limit-line')), findsNothing);
      expect(find.textContaining('όριο'), findsNothing);
      expect(find.text('134'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('V-B-05/06, V-A-05: κάρτα και φόρμα ορίου', () {
    setUp(() => ExClock.frozen = true);
    tearDown(() {
      WearLink.main.ready.value = false;
      WearLink.main.sentLimit.value = null;
      WearLink.main.watchLimit.value = null;
      WearLink.main.hr.value = null;
    });

    Future<void> page(WidgetTester t, TrainingStore store) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(400, 1400);
      addTearDown(t.view.reset);
      await t.runAsync(() => ExLibrary.load(inline: true));
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: TrainingPage(training: store, now: now))));
      await t.pumpAndSettle();
    }

    testWidgets('κάρτα: όχι απόλυτη υπόσχεση· φαίνεται αν το όριο έφτασε στο ρολόι', (t) async {
      final store = sampleTraining(now);
      await page(t, store);
      expect(find.textContaining('δονείται αν το ξεπεράσεις'), findsNothing);
      expect(find.textContaining('140 bpm · δόνηση στο ρολόι όσο μετρά άσκηση'), findsOneWidget);
      expect(find.textContaining('Το ρολόι δεν βρέθηκε τώρα'), findsOneWidget);
      WearLink.main.ready.value = true;
      WearLink.main.sentLimit.value = '140';
      await t.pumpAndSettle();
      // Έλεγχος 9/11 (V-A-06): «στάλθηκε» δεν είναι «το έχει»· το ✓ μόνο όταν το επιβεβαιώσει το ρολόι.
      expect(find.textContaining('Στάλθηκε· θα επιβεβαιωθεί'), findsOneWidget);
      expect(find.textContaining('Στο ρολόι ✓'), findsNothing);
      WearLink.main.applyWatchState('{"v":1,"lim":140,"planAt":0}');
      await t.pumpAndSettle();
      expect(find.text('Στο ρολόι ✓ όριο 140'), findsOneWidget);
      // Άλλαξε το όριο: το παλιό που στάλθηκε/επιβεβαιώθηκε δεν μετρά.
      store.setHrLimit(130);
      await t.pumpAndSettle();
      expect(find.textContaining('Στο ρολόι ✓'), findsNothing);
      expect(find.text('Στέλνεται στο ρολόι…'), findsOneWidget);
    });

    testWidgets('φόρμα: «βοηθά, δεν εγγυάται», πρώτα πώς νιώθεις, β-αναστολέας· λεπτομέρειες πίσω από ⓘ', (t) async {
      await page(t, sampleTraining(now));
      final card = find.byKey(const ValueKey('train-hrlimit'));
      await t.ensureVisible(card);
      await t.pumpAndSettle();
      await t.tap(card);
      await t.pumpAndSettle();
      expect(find.textContaining('δονείται όταν τον ξεπεράσεις'), findsNothing);
      expect(find.textContaining('βοηθά, δεν εγγυάται'), findsOneWidget);
      expect(find.textContaining('πρώτα μετράει πώς νιώθεις'), findsOneWidget);
      expect(find.text(hrLimitBetaBlockerText), findsOneWidget);
      expect(hrLimitBetaBlockerText, contains('β-αναστολέα'));
      expect(hrLimitBetaBlockerText, contains('τεστ κοπώσεως'));
      expect(hrLimitBetaBlockerText, contains('ρώτα τον γιατρό'));
      expect(find.textContaining('φτάσουν ή ξεπεράσουν τον αριθμό'), findsOneWidget);
      expect(find.byKey(const ValueKey('train-hr-more-text')), findsNothing);
      await t.tap(find.byKey(const ValueKey('train-hr-more')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('train-hr-more-text')), findsOneWidget);
      // Έλεγχος του #90 (M-2): ποτέ υπόσχεση δόνησης όταν το ρολόι είναι μακριά / δεν μετρά.
      expect(hrLimitMoreText, isNot(contains('ρολόι μακριά), το ρολόι δονείται')));
      expect(hrLimitMoreText, contains('• Στο ρολόι:'));
      expect(hrLimitMoreText, contains('• Στο κινητό:'));
      expect(hrLimitMoreText, contains('δεν έρχεται καμία δόνηση'));
    });

    Future<void> session(WidgetTester t, TrainingStore store) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(400, 900);
      addTearDown(t.view.reset);
      await t.runAsync(() => ExLibrary.load(inline: true));
      WearLink.main.attachForTest(store);
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: SessionPage(training: store)));
      await t.pump();
    }

    testWidgets('προπόνηση με όριο, χωρίς ρολόι: «το όριο δεν σε προσέχει τώρα» (πριν: τίποτα)', (t) async {
      final store = sampleTraining(now);
      store.start(store.program!.workout('A')!);
      await session(t, store);
      expect(find.byKey(const ValueKey('hr-stale')), findsOneWidget);
      expect(find.text('Το όριο (140) δεν σε προσέχει τώρα.'), findsOneWidget);
      expect(find.textContaining('Το ρολόι δεν βρέθηκε'), findsOneWidget);
      expect(find.textContaining('να μπορείς να μιλάς'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('ρολόι κοντά αλλά χωρίς παλμούς: «πάτα Παλμοί εδώ»· παλμοί που χάθηκαν: «σφίξε το λουρί»', (t) async {
      // Με την πραγματική ώρα: η οθόνη συγκρίνει με το «τώρα» της συσκευής (φρέσκοι παλμοί, πρώτα δευτερόλεπτα).
      final started = DateTime.now().subtract(const Duration(minutes: 10));
      final store = sampleTraining(started);
      final s = store.start(store.program!.workout('A')!);
      WearLink.main.ready.value = true;
      await session(t, store);
      expect(find.text('Το όριο (140) δεν σε προσέχει τώρα.'), findsOneWidget);
      expect(find.textContaining('Στο ρολόι πάτα «Παλμοί εδώ»'), findsOneWidget);
      WearLink.main.hr.value = (120, s.start.add(const Duration(minutes: 1)));
      await t.pump();
      await t.pump();
      expect(find.textContaining('Σφίξε λίγο το λουρί'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('ρολόι κοντά, πρώτα 30″: ήρεμο «Περιμένω παλμούς» (όσο και το ρολόι)· χωρίς ρολόι: αμέσως το πλαίσιο', (t) async {
      final started = DateTime.now().subtract(const Duration(seconds: 5));
      final store = sampleTraining(started);
      store.start(store.program!.workout('A')!);
      WearLink.main.ready.value = true;
      await session(t, store);
      expect(hrWaitSeconds, 30);
      expect(find.byKey(const ValueKey('hr-waiting')), findsOneWidget);
      expect(find.byKey(const ValueKey('hr-stale')), findsNothing);
      WearLink.main.ready.value = false;
      await t.pump();
      expect(find.byKey(const ValueKey('hr-waiting')), findsNothing);
      expect(find.text('Το όριο (140) δεν σε προσέχει τώρα.'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('χωρίς όριο και χωρίς ρολόι: τίποτα (όπως πριν)', (t) async {
      final store = sampleTraining(now)..setHrLimit(null);
      store.start(store.program!.workout('A')!);
      await session(t, store);
      expect(find.byKey(const ValueKey('hr-stale')), findsNothing);
      await t.pumpWidget(const SizedBox());
    });
  });

  // -------------------------------------------------------------------------
  group('V-B-08: πτώση παλμών στο 1′ ουδέτερη', () {
    test('ούτε «καλύτερα» ούτε «χειρότερα» στην Πρόοδο', () {
      expect(walkHrrDef.better, 0);
    });

    testWidgets('κάρτα: χωρίς πράσινο, με τους παλμούς τέλους δίπλα· ⓘ χωρίς θνησιμότητα', (tester) async {
      final s = Session(
        id: 'w',
        workout: 'walk',
        name: 'Περπάτημα',
        programId: '',
        start: now,
        end: now.add(const Duration(minutes: 30)),
        cardioMinutes: 30,
        cardioSec: 1800,
        hrrEnd: 112,
        hrr1: 94,
      );
      await _pump(tester, SingleChildScrollView(child: RecoveryCard(session: s)));
      final c = Aigaio.of(tester.element(find.byKey(const ValueKey('hrr-drop'))));
      final drop = tester.widget<Text>(find.byKey(const ValueKey('hrr-drop')));
      expect(drop.data, '−18');
      expect(drop.style!.color, isNot(c.good));
      expect(find.text('παλμοί · 112 → 94'), findsOneWidget);
      expect(find.textContaining('παρόμοιας έντασης'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hrr-info')));
      await tester.pumpAndSettle();
      final sheet = find.byKey(const ValueKey('hrr-info-sheet'));
      expect(find.descendant(of: sheet, matching: find.textContaining('mortality')), findsNothing);
      expect(find.descendant(of: sheet, matching: find.textContaining('θνησιμ')), findsNothing);
      expect(find.descendant(of: sheet, matching: find.textContaining('τόσο καλύτερα')), findsNothing);
      expect(find.descendant(of: sheet, matching: find.textContaining('Cole CR')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.textContaining('πιο γρήγορο βάδισμα')), findsOneWidget);
    });

    test('«Τι άλλαξε»: ουδέτερο, χωρίς βέλος, με τους παλμούς στο τέλος', () {
      Session walk(int daysAgo, int drop, int end) {
        final start = DateTime(now.year, now.month, now.day - daysAgo, 18);
        return Session(
          id: 'w$daysAgo',
          workout: 'walk',
          name: 'Περπάτημα',
          programId: '',
          start: start,
          end: start.add(const Duration(minutes: 31)),
          cardioMinutes: 30,
          cardioSec: 1800,
          meters: 2300,
          gps: true,
          hrAvg: 110,
          hrrEnd: end,
          hrr1: end - drop,
          source: 'watch',
        );
      }

      const noise = [2, -2, 1, -1, 0, 2];
      final sessions = [
        for (var i = 0; i < 6; i++) walk(32 + i * 5, 16 + noise[i], 112),
        for (var i = 0; i < 6; i++) walk(1 + i * 5, 24 + noise[(i + 3) % 6], 120),
      ];
      final w = walkProgress(sessions, now, TrendPeriod.month);
      expect(w.hrr.status, TrendStatus.up);
      expect(w.hrr.goodness, 0);
      final h = progressHighlights(w, const [], const []).where((e) => e.$1.startsWith('Πτώση')).single;
      expect(h.$2, TrendKind.neutral);
      expect(h.$3, isNull);
      expect(h.$1, contains('παλμοί στο τέλος 112 → 120'));
    });
  });

  // -------------------------------------------------------------------------
  group('V-A-01: το ρολόι σβήνει το αποτέλεσμα μόνο αφού γραφτεί στο κινητό', () {
    const ch = MethodChannel('test/wear-ack');
    late List<Map<String, String>> results;
    late List<String> acks;

    setUp(() {
      acks = [];
      results = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (call) async {
        switch (call.method) {
          case 'takeResults':
            return results;
          case 'ackResult':
            acks.add((call.arguments as Map)['path'] as String);
            return true;
        }
        return null;
      });
    });
    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, null));

    test('αποτυχημένη εγγραφή: κανένα ack· μόλις γραφτεί: ack', () async {
      final io = _FlakyIO();
      final t = TrainingStore(io: io, clock: () => now);
      await t.load();
      results = [
        {'path': '/ygeia/result/walk1', 'json': jsonEncode(_walk('walk1', lim: 0))},
      ];
      final link = WearLink(channel: ch)..attachForTest(t);
      await link.importResults();
      expect(t.sessions.length, 1, reason: 'στη μνήμη, για να φαίνεται');
      expect(t.saveError, isNotNull);
      expect(acks, isEmpty, reason: 'δεν γράφτηκε: μένει στο ρολόι');
      // Ο δίσκος ξανά εντάξει: το ίδιο αποτέλεσμα ξαναέρχεται, ήδη στη μνήμη· γράφεται και τώρα σβήνεται.
      io.fail = false;
      await link.importResults();
      expect(t.sessions.length, 1);
      expect(acks, ['/ygeia/result/walk1']);
      expect(io.json, contains('w-walk1'));
    });

    test('εξαίρεση στην εγγραφή: κανένα ack, και οι επόμενες εγγραφές συνεχίζουν', () async {
      final io = _FlakyIO()..throws = true;
      final t = TrainingStore(io: io, clock: () => now);
      await t.load();
      results = [
        {'path': '/ygeia/result/walk1', 'json': jsonEncode(_walk('walk1'))},
      ];
      final link = WearLink(channel: ch)..attachForTest(t);
      await link.importResults();
      expect(acks, isEmpty);
      io
        ..throws = false
        ..fail = false;
      await link.importResults();
      expect(acks, ['/ygeia/result/walk1']);
    });

    test('αρχείο που δεν διαβάστηκε (readError): κανένα ack, τίποτα δεν γράφεται', () async {
      final io = _ErrorIO();
      final t = TrainingStore(io: io, clock: () => now);
      await t.load();
      expect(t.readError, isTrue);
      results = [
        {'path': '/ygeia/result/walk1', 'json': jsonEncode(_walk('walk1'))},
      ];
      await (WearLink(channel: ch)..attachForTest(t)).importResults();
      expect(acks, isEmpty);
      expect(io.writes, 0);
    });

    test('αποτέλεσμα που δεν διαβάζεται: κανένα ack (μένει στο ρολόι)· τα υπόλοιπα περνούν κανονικά', () async {
      final io = MemoryTrainingIO();
      final t = TrainingStore(io: io, clock: () => now);
      await t.load();
      results = [
        {'path': '/ygeia/result/bad', 'json': '{χαλασμένο'},
        {'path': '/ygeia/result/walk2', 'json': jsonEncode(_walk('walk2'))},
        {'path': '/ygeia/result/sym', 'json': jsonEncode({'v': 1, 'kind': 'sym'})},
      ];
      await (WearLink(channel: ch)..attachForTest(t)).importResults();
      expect(acks, ['/ygeia/result/walk2', '/ygeia/result/sym'], reason: 'το παλιό «Νιώθω κάτι» δεν υπάρχει πια: σβήνεται');
      expect(io.json, contains('w-walk2'));
    });
  });

  // -------------------------------------------------------------------------
  group('Έλεγχος του #90 (Σ-8): όριο που δεν στάλθηκε', () {
    const ch = MethodChannel('test/wear-plan');
    test('αποτυχημένο putPlan: όχι «Στάλθηκε», και ξαναστέλνεται στην επόμενη αλλαγή', () async {
      var ok = false;
      var puts = 0;
      final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      m.setMockMethodCallHandler(ch, (call) async {
        switch (call.method) {
          case 'status':
            return {'nodes': 1, 'app': 1};
          case 'takeResults':
            return <Object>[];
          case 'putPlan':
            puts++;
            return ok;
        }
        return true;
      });
      const events = MethodChannel('test/wear-plan-events');
      m.setMockMethodCallHandler(events, (call) async => null);
      addTearDown(() {
        m.setMockMethodCallHandler(ch, null);
        m.setMockMethodCallHandler(events, null);
      });
      final t = sampleTraining(now);
      final link = WearLink(channel: ch, events: const EventChannel('test/wear-plan-events'));
      link.start(t);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(puts, greaterThan(0));
      expect(link.sentLimit.value, isNull);
      ok = true;
      final before = puts;
      t.setHrLimit(140); // ίδιο όριο, ίδιο σχέδιο: στέλνεται μόνο επειδή το προηγούμενο απέτυχε
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(puts, before + 1);
      expect(link.sentLimit.value, '140');
      link.dispose();
    });
  });

  // -------------------------------------------------------------------------
  group('V-B-12: δύναμη', () {
    ExLog ex(double load, List<int> reps, {int lo = 8}) =>
        ExLog(ex: 'goblet', sets: reps.length, lo: lo, hi: 12, rir: 2, rest: 90, log: [for (final r in reps) SetLog(load: load, reps: r, done: true)]);
    ExProgress p(ExLog a, ExLog b) => ExProgress(ex: 'goblet', kind: a.kind, beforeDay: _add(now, -30), before: a, nowDay: now, now: b);

    test('κιλά ↑ με τις επαναλήψεις μέσα στο εύρος: πρόοδος', () {
      expect(p(ex(12, [12, 12, 12]), ex(14, [9, 9, 8])).change, StrengthChange.up);
    });

    test('κιλά ↑ αλλά ένα σετ κάτω από το εύρος: μικτό', () {
      expect(p(ex(12, [12, 12, 12]), ex(14, [9, 8, 7])).change, StrengthChange.mixed);
    });

    test('το κάτω όριο της πιο πρόσφατης φοράς (το πρόγραμμα εκείνη τη μέρα)', () {
      expect(p(ex(12, [12, 12, 12], lo: 6), ex(14, [9, 9, 7], lo: 6)).change, StrengthChange.up);
      expect(p(ex(12, [12, 12, 12], lo: 6), ex(14, [9, 9, 7], lo: 8)).change, StrengthChange.mixed);
    });

    test('η ανοχή ±1 μένει: κιλά ↑ και −1 επανάληψη = πρόοδος· ίδια κιλά ±1 = ίδιο', () {
      expect(p(ex(12, [10, 10, 10]), ex(13, [10, 10, 9], lo: 10)).change, StrengthChange.up);
      expect(p(ex(12, [10, 10, 10]), ex(12, [10, 10, 9])).change, StrengthChange.same);
    });
  });
}
