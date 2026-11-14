// Round 7 · f7 («Ύπνος, καρδιά, Τάσεις»): R7-A5-1 … R7-A5-5, R7-U1-4, R7-U1-13, R7-U4-4, R7-U4-6, R7-U4-9 και η
// σπασμένη λέξη «τουλάχιστο|ν» στον Ύπνο του ρολογιού. Οι αναμενόμενες τιμές βγήκαν από τον γραμμένο κανόνα (με το χέρι
// ή με python στο /home/claude/scratch/f7/), όχι από τη νέα υλοποίηση. Όλες οι τιμές είναι επινοημένες.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/oura/oura_api.dart';
import 'package:ygeia_forma/oura/oura_model.dart';
import 'package:ygeia_forma/oura/oura_store.dart';
import 'package:ygeia_forma/oura/oura_view.dart';
import 'package:ygeia_forma/pages/heart.dart';
import 'package:ygeia_forma/pages/metric_page.dart';
import 'package:ygeia_forma/pages/oura_sleep.dart';
import 'package:ygeia_forma/pages/oura_today.dart';
import 'package:ygeia_forma/pages/sleep.dart';
import 'package:ygeia_forma/pages/source_widgets.dart';
import 'package:ygeia_forma/pages/trends.dart';
import 'package:ygeia_forma/shown.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/trends.dart';
import 'package:ygeia_forma/widgets.dart';

import 'sample_data.dart';

// ---------------------------------------------------------------------------
// Βοηθοί
// ---------------------------------------------------------------------------

DateTime _add(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

String _utc(DateTime t) => t.toUtc().toIso8601String();

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
    home: Scaffold(body: w),
  ));
  await t.pumpAndSettle();
}

/// Λέξεις του [p] που ζωγραφίστηκαν σε δύο γραμμές («λεπτ|ό»), όπως ο έλεγχος premium (M3/S10).
List<String> _broken(RenderParagraph p) {
  final out = <String>[];
  final text = p.text.toPlainText();
  for (final m in RegExp(r'[^\s·,.:()/]+').allMatches(text)) {
    if (m.end - m.start < 2) continue;
    final boxes = p.getBoxesForSelection(TextSelection(baseOffset: m.start, extentOffset: m.end));
    if ({for (final b in boxes) b.top.round()}.length > 1) out.add(m.group(0)!);
  }
  return out;
}

/// Μία περίοδος ύπνου όπως τη δίνει η Oura (νύχτα 23:00 → 07:30).
Map<String, dynamic> _night(DateTime morning,
    {int deep = 3600, int light = 14400, int rem = 5400, int? awake = 1800, int latency = 600, String type = 'long_sleep'}) {
  final start = DateTime(morning.year, morning.month, morning.day - 1, 23);
  final end = DateTime(morning.year, morning.month, morning.day, 7, 30);
  return {
    'id': 'n-${dateKey(morning)}',
    'day': dateKey(morning),
    'type': type,
    'bedtime_start': _utc(start),
    'bedtime_end': _utc(end),
    'time_in_bed': end.difference(start).inSeconds,
    'total_sleep_duration': deep + light + rem,
    'deep_sleep_duration': deep,
    'light_sleep_duration': light,
    'rem_sleep_duration': rem,
    if (awake != null) 'awake_time': awake,
    'latency': latency,
  };
}

List<OuraNight> _nights(List<Map<String, dynamic>> sleep) =>
    parseOura(sleep: sleep, dailySleep: const [], readiness: const []).nights;

/// Store με Oura από [from] και τις νύχτες του δείγματος ως το [at] (εκτός από [missing]), όπως στα στιγμιότυπα.
/// [replace]: δικές μου περίοδοι ύπνου για κάποιες μέρες (στη θέση του δείγματος).
HealthStore _ouraStore(DateTime at,
    {DateTime? from, Set<DateTime> missing = const {}, List<Map<String, dynamic>> replace = const []}) {
  final start = from ?? DateTime(2026, 11, 1);
  final today = DateTime(at.year, at.month, at.day);
  final s = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(at));
  s.history = sampleHistory(at, s.data!);
  s.debugSetPlan(SourcePlan.samsungOnly.withEra(Source.oura, start));
  final mine = {for (final r in replace) r['day'] as String};
  final sleep = [
    for (final r in sampleOuraSleep(start, at, missing: missing)) if (!mine.contains(r['day'])) r,
    ...replace,
  ];
  final batch = parseOura(sleep: sleep, dailySleep: const [], readiness: const []);
  s.ouraNights = batch.nights;
  mergeOura(s.history, ouraRows(batch.nights), from: start, to: today, plan: s.plan);
  s.ouraHasTokens = true;
  s.ouraLink = OuraLink(vault: MemoryVault(), clientId: 'TEST');
  s.ouraClock = () => at;
  s.ouraSyncedMs = at.subtract(const Duration(minutes: 12)).millisecondsSinceEpoch;
  return s;
}

/// CIELAB (D65) από sRGB, για την απόσταση χρωμάτων ΔE76.
List<double> _lab(Color c) {
  double lin(double v) => v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  final r = lin(c.r), g = lin(c.g), b = lin(c.b);
  final x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047;
  final y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b;
  final z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883;
  double f(double v) => v > 216 / 24389 ? math.pow(v, 1 / 3).toDouble() : (24389 / 27 * v + 16) / 116;
  return [116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))];
}

double _de76(Color a, Color b) {
  final p = _lab(a), q = _lab(b);
  return math.sqrt(math.pow(p[0] - q[0], 2) + math.pow(p[1] - q[1], 2) + math.pow(p[2] - q[2], 2));
}

void main() {
  // Τα πλάτη μετριούνται με το Inter της εφαρμογής (όχι με τη γραμματοσειρά δοκιμών), όπως στο premium_test.
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
  });

  // ------------------------------------------------------------------ R7-A5-1
  group('R7-A5-1: σελίδα μέτρησης «Θερμοκρασία στον ύπνο»', () {
    final now = DateTime(2026, 11, 13, 10);
    final day = DateTime(2026, 11, 13);

    testWidgets('Oura: η απόκλιση όπως είναι, χωρίς δεύτερο «συνήθως»', (t) async {
      final s = HealthStore()
        ..history = {
          for (var i = 1; i <= 14; i++) dateKey(_add(day, -i)): {'o.skinTemp': -0.1},
          dateKey(day): {'o.skinTemp': 0.2},
        };
      s.debugSetPlan(SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 10, 1)));
      await _pump(t, MetricPage(store: s, spec: metricSpecs[K.skinTemp]!, now: now));
      expect(find.text(ouraTempDeviationLabel), findsOneWidget);
      // Πριν: «+0,3 °C · συνήθως −0,1 °C» για νύχτα που η κάρτα του Ύπνου λέει «+0,2».
      expect(find.textContaining('συνήθως'), findsNothing);
      expect(find.textContaining('+0,3'), findsNothing);
    });

    // Round 8 (R8-U4-2): η δοκιμή του round 7 κλείδωνε το «+0,2 °C · συνήθως 33,4 °C» και το μεγάλο «33,6 °C», δηλαδή
    // απόλυτη θερμοκρασία καρπού, που ο κλινικός κανόνας L5/F2 απαγορεύει (Σήμερα, Σώμα, Τάσεις, widget δείχνουν μόνο
    // απόκλιση). Τώρα η σελίδα δείχνει μόνο την απόκλιση.
    testWidgets('Ρολόι (θερμοκρασία καρπού): μόνο η απόκλιση από τα συνηθισμένα, ποτέ βαθμοί', (t) async {
      final s = HealthStore()
        ..history = {
          for (var i = 1; i <= 14; i++) dateKey(_add(day, -i)): {K.skinTemp: 33.4},
          dateKey(day): {K.skinTemp: 33.6},
        };
      await _pump(t, MetricPage(store: s, spec: metricSpecs[K.skinTemp]!, now: now));
      expect(t.widget<BigValue>(find.byType(BigValue)).value, '+0,2');
      expect(find.text(wristDeviationText), findsOneWidget);
      expect(find.textContaining('33,4'), findsNothing);
      expect(find.textContaining('33,6'), findsNothing);
      expect(find.text(ouraTempDeviationLabel), findsNothing);
    });
  });

  // ------------------------------------------------------------------ R7-A5-2
  group('R7-A5-2: «Φάσεις · μέσος όρος 7 νυχτών» από τις ίδιες νύχτες', () {
    final day = DateTime(2026, 11, 14);
    final plan = SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 6));

    test('4 νύχτες, η μία χωρίς awake_time: καμία φάση (όλες null μαζί), 3 νύχτες', () {
      final n = _nights([
        _night(DateTime(2026, 11, 11)),
        _night(DateTime(2026, 11, 12)),
        _night(DateTime(2026, 11, 13), awake: null),
        _night(DateTime(2026, 11, 14)),
      ]);
      final a = ouraStageAverages(n, day, plan);
      expect(a.nights, 3);
      // Πριν: ο βαθύς έβγαινε (4 νύχτες) και ο ξύπνιος όχι (3) → `stages.awake!` έσπαγε τη σελίδα.
      expect([a.deep, a.light, a.rem, a.awake], [null, null, null, null]);
    });

    test('5 νύχτες, η μία χωρίς awake_time: οι 4 φάσεις από τις ίδιες 4 νύχτες', () {
      final n = _nights([
        _night(DateTime(2026, 11, 10), deep: 3000, light: 15000, rem: 5400, awake: 2400, latency: 600),
        _night(DateTime(2026, 11, 11), deep: 3600, light: 14400, rem: 6000, awake: 2100, latency: 300),
        _night(DateTime(2026, 11, 12), deep: 4200, light: 13800, rem: 4800, awake: 1500, latency: 900),
        _night(DateTime(2026, 11, 13), deep: 3900, light: 14100, rem: 5100, awake: null),
        _night(DateTime(2026, 11, 14), deep: 2400, light: 16260, rem: 5700, awake: 3000, latency: 540),
      ]);
      final a = ouraStageAverages(n, day, plan);
      expect(a.nights, 4);
      // Νύχτες 10, 11, 12, 14: βαθύς (3000 + 3600 + 4200 + 2400) / 4 / 60 = 55 (πριν, με τις 5 νύχτες: 57).
      expect(a.deep, 55);
      // (15000 + 14400 + 13800 + 16260) / 240 = 247,75 → 248.
      expect(a.light, 248);
      // (5400 + 6000 + 4800 + 5700) / 240 = 91,25 → 91.
      expect(a.rem, 91);
      // ξύπνιος μέσα στον ύπνο = awake_time − latency: (1800 + 1800 + 600 + 2460) / 240 = 27,75 → 28.
      expect(a.awake, 28);
    });

    testWidgets('«Ύπνος 30 νυχτών» με τέτοια νύχτα: χωρίς σφάλμα, «χρειάζονται τουλάχιστον 4»', (t) async {
      final s = HealthStore();
      s.debugSetPlan(plan);
      s.ouraNights = _nights([
        _night(DateTime(2026, 11, 11)),
        _night(DateTime(2026, 11, 12)),
        _night(DateTime(2026, 11, 13), awake: null),
        _night(DateTime(2026, 11, 14)),
      ]);
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(400, 3000);
      addTearDown(t.view.reset);
      await t.pumpWidget(
          MaterialApp(theme: buildTheme(Brightness.light), home: OuraNightsPage(store: s, now: DateTime(2026, 11, 14, 10))));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.textContaining('(τώρα 3 νύχτες)'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------ R7-A5-3
  group('R7-A5-3: «Τι άλλαξε» λέει ότι κάτι μπορεί να βγει από τύχη', () {
    final now = DateTime(2026, 11, 14, 10);
    final today = DateTime(2026, 11, 14);

    Map<String, Map<String, double>> sleepHr(double before, double after) => {
          for (var i = 0; i < 60; i++)
            dateKey(_add(today, -i)): {K.sleepHr: (i < 30 ? after : before) + (i.isEven ? 0.5 : -0.5)},
        };

    test('η πρόταση', () {
      expect(chanceNote(16),
          'Με 16 μετρήσεις μαζί, περίπου μία φορά στις 10 κάποια γραμμή λέει «άλλαξε» από τύχη· αν η αλλαγή φαίνεται '
          'και τις επόμενες εβδομάδες, είναι πιο σίγουρη.');
    });

    testWidgets('με αλλαγή (παλμοί ύπνου 55 → 62): η πρόταση κάτω από τη λίστα, με τις 16 γραμμές του ρολογιού', (t) async {
      final s = HealthStore()..history = sleepHr(55, 62);
      await _pump(t, TrendsPage(store: s, now: now), size: const Size(400, 4000));
      final note = find.byKey(const ValueKey('trends-chance-note'));
      expect(note, findsOneWidget);
      // Round 9 (R9-A5-1 = R9-U4-5): μόνο οι παλμοί ύπνου ελέγχθηκαν (οι άλλες 15 γραμμές «Λίγα δεδομένα»): η πρόταση για 1
      // ελεγμένη γραμμή, όχι για τις 16 της λίστας (πριν: «Με 16 μετρήσεις μαζί … μία φορά στις 10»).
      expect(t.widget<Text>(note).data, chanceNote(1));
      expect(trendMetrics.length, 16);
    });

    testWidgets('χωρίς αλλαγή: καμία πρόταση', (t) async {
      final s = HealthStore()..history = sleepHr(58, 58);
      await _pump(t, TrendsPage(store: s, now: now), size: const Size(400, 4000));
      expect(find.byKey(const ValueKey('trends-chance-note')), findsNothing);
    });
  });

  // ------------------------------------------------------------------ R7-A5-4
  testWidgets('R7-A5-4: «Ξύπνιος» της τελευταίας νύχτας (Oura) με «τουλάχιστον»', (t) async {
    final at = DateTime(2026, 11, 14, 10);
    // awake_time 1920 − latency 600 = 1320 δευτερόλεπτα = 22 λεπτά.
    final s = _ouraStore(at, replace: [_night(DateTime(2026, 11, 14), awake: 1920, latency: 600)]);
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(400, 4000);
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: OuraSleepPage(store: s, now: at)));
    await t.pumpAndSettle();
    // 400 dp: τρεις στήλες, «22 λεπτά» και από κάτω «τουλάχιστον».
    expect(find.text('22 λεπτά'), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const ValueKey('oura-awake-note'))).data, 'τουλάχιστον');
  });

  // ------------------------------------------------------------------ R7-A5-5
  group('R7-A5-5: Καρδιά › «Παλμοί ξύπνιος» χωρίς τιμή', () {
    final now = DateTime(2026, 11, 13, 10);

    testWidgets('ύπνος από το ρολόι: όχι «δαχτυλίδι»', (t) async {
      final s = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(now));
      await _pump(t, HeartPage(store: s, now: now), size: const Size(400, 4000));
      final note = t.widget<Text>(find.byKey(const ValueKey('heart-awake-note'))).data!;
      expect(note, 'Βγαίνει για μέρες με αρκετές μετρήσεις του ρολογιού (τουλάχιστον 6 ώρες).');
      expect(note, isNot(contains('δαχτυλίδι')));
    });

    testWidgets('ύπνος από το Oura: το δαχτυλίδι', (t) async {
      final s = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(now));
      s.debugSetPlan(SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 1)));
      await _pump(t, HeartPage(store: s, now: now), size: const Size(400, 4000));
      expect(t.widget<Text>(find.byKey(const ValueKey('heart-awake-note'))).data, contains('νύχτα από το δαχτυλίδι'));
    });
  });

  // ------------------------------------------------------------------ R7-U1-4
  testWidgets('R7-U1-4: το «χάπι» της κάρτας ύπνου (Oura) κρατά μαζί τις δύο τελευταίες λέξεις', (t) async {
    final at = DateTime(2026, 11, 14, 10);
    final s = _ouraStore(at);
    await _pump(t, SingleChildScrollView(child: OuraSleepTodayCard(store: s, now: at, onTap: () {})),
        size: const Size(360, 1800), textScale: 1.3);
    final pill = t.widget<TrendPill>(find.byType(TrendPill));
    expect(pill.keepLastWords, isTrue);
    expect(pill.maxLines, 2);
  });

  // ------------------------------------------------------------------ R7-U1-13
  group('R7-U1-13: η κάρτα ύπνου δεν επαναλαμβάνει την κάρτα κατάστασης', () {
    testWidgets('05:00, η νύχτα δεν ήρθε: «Περιμένει το Oura» μία φορά, και η τελευταία νύχτα που ήρθε', (t) async {
      final at = DateTime(2026, 11, 14, 5);
      final s = _ouraStore(at, missing: {DateTime(2026, 11, 14)});
      s.ouraSyncedMs = DateTime(2026, 11, 13, 9).millisecondsSinceEpoch;
      expect(s.ouraStatus, OuraStatus.waiting);
      await _pump(
        t,
        SingleChildScrollView(
          child: Column(children: [OuraStatusCard(store: s, now: at), OuraSleepTodayCard(store: s, now: at, onTap: () {})]),
        ),
      );
      expect(find.text('Περιμένει το Oura'), findsOneWidget);
      expect(find.byKey(const ValueKey('oura-today-older-night')), findsOneWidget);
    });

    testWidgets('14:00, μόνο υπνάκος: οι ώρες του μία φορά (στην κάρτα κατάστασης)', (t) async {
      final at = DateTime(2026, 11, 14, 14);
      final a = DateTime(2026, 11, 13, 20);
      final b = DateTime(2026, 11, 13, 21, 40);
      final s = _ouraStore(at, replace: [
        {
          'id': 'nap',
          'day': '2026-11-14',
          'type': 'sleep',
          'bedtime_start': _utc(a),
          'bedtime_end': _utc(b),
          'time_in_bed': b.difference(a).inSeconds,
          'total_sleep_duration': b.difference(a).inSeconds - 300,
        },
      ]);
      s.history[dateKey(DateTime(2026, 11, 14))]?.removeWhere((k, _) => k.startsWith('o.'));
      expect(s.ouraStatus, OuraStatus.missing);
      await _pump(
        t,
        SingleChildScrollView(
          child: Column(children: [OuraStatusCard(store: s, now: at), OuraSleepTodayCard(store: s, now: at, onTap: () {})]),
        ),
      );
      expect(find.textContaining('20:00–21:40'), findsOneWidget);
      expect(find.text('Μόνο υπνάκος από το δαχτυλίδι'), findsNothing);
      expect(find.byKey(const ValueKey('oura-only-nap-times')), findsNothing);
    });
  });

  // ------------------------------------------------------------------ R7-U4-4
  group('R7-U4-4: Τάσεις μετά από αλλαγή πηγής', () {
    final now = DateTime(2026, 11, 14, 10);
    final today = DateTime(2026, 11, 14);
    final change = _add(today, -8);

    HealthStore store() {
      final s = HealthStore()
        ..history = {
          for (var i = 0; i < 60; i++)
            dateKey(_add(today, -i)): {
              K.sleepMin: 420.0 + (i % 3) * 5,
              if (i <= 8) 'o.sleepMin': 400.0 + (i % 2) * 10,
            },
        };
      s.debugSetPlan(SourcePlan.samsungOnly.withEra(Source.oura, change));
      return s;
    }

    test('η τιμή «τώρα» είναι από την αλλαγή: 9 νύχτες από 6/11', () {
      final s = store();
      final r = computeTrend(metricDef(K.sleepMin)!, s.history, today, TrendPeriod.month, plan: s.plan);
      expect(r.status, TrendStatus.sourceChange);
      expect(r.currentFrom, _add(today, -29));
      expect(r.shownFrom, change);
      expect(r.nCurrent, 9);
    });

    testWidgets('λεπτομέρεια: «Από την αλλαγή · 6 Νοε – 14 Νοε», «9 από 9 μέρες», χωρίς «Πριν» και «0 από 30»', (t) async {
      await _pump(t, TrendsPage(store: store(), now: now), size: const Size(400, 5000));
      final row = find.byKey(const ValueKey('trend-${K.sleepMin}'));
      await t.ensureVisible(row);
      await t.tap(row);
      await t.pumpAndSettle();
      expect(find.text('Από την αλλαγή · 6 Νοε – 14 Νοε'), findsOneWidget);
      final rows = t.widgetList<InfoRow>(find.byType(InfoRow)).toList();
      expect(rows.singleWhere((r) => r.label == 'Με δεδομένα').value, '9 από 9 μέρες');
      expect(rows.where((r) => r.label.startsWith('Πριν ·')), isEmpty);
      expect(rows.where((r) => r.value.contains('από 30')), isEmpty);
    });
  });

  // ------------------------------------------------------------------ R7-U4-6
  testWidgets('R7-U4-6: «Αναπνοή και οξυγόνο» στα 360 dp με γράμματα 2×: η πηγή κάτω από τον τίτλο, καμία σπασμένη λέξη',
      (t) async {
    final at = DateTime(2026, 11, 14, 10);
    final s = _ouraStore(at);
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(360, 7000);
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)), child: child!),
      home: OuraSleepPage(store: s, now: at),
    ));
    await t.pumpAndSettle();
    final breath = find.byKey(const ValueKey('sleep-breath'));
    final title = find.descendant(of: breath, matching: find.textContaining('Αναπνοές'));
    final tag = find.descendant(of: breath, matching: find.byType(SourceTag));
    expect(title, findsOneWidget);
    expect(t.getTopLeft(tag).dy, greaterThanOrEqualTo(t.getBottomLeft(title).dy - 0.5), reason: 'η πηγή κάτω από τον τίτλο');
    final titles = [
      for (final e in find.byType(RichText).evaluate())
        if ((e.renderObject! as RenderParagraph).text.toPlainText().startsWith(RegExp('Αναπνοές|Οξυγόνο τη νύχτα')))
          e.renderObject! as RenderParagraph,
    ];
    expect(titles.length, greaterThanOrEqualTo(3));
    for (final p in titles) {
      expect(_broken(p), isEmpty, reason: p.text.toPlainText());
    }
    // R7-A5-4 με πολύ μεγάλα γράμματα: γραμμές «ετικέτα … τιμή», ο ξύπνιος «τουλάχιστον …».
    final awake = t.widgetList<InfoRow>(find.byType(InfoRow)).where((r) => r.label == 'Ξύπνιος').toList();
    expect(awake.length, 1);
    expect(awake.single.value, startsWith('τουλάχιστον '));
  });

  // ------------------------------------------------------------------ R7-U4-9
  test('R7-U4-9: φάσεις ύπνου ≥ 3:1 με την κάρτα σε ΚΑΘΕ θέμα, ο βαθύς ο πιο σκούρος, ξεχωριστές μεταξύ τους', () {
    for (final th in [...Aigaio.dayThemes, ...Aigaio.nightThemes]) {
      final stages = [th.stageDeep, th.stageLight, th.stageRem, th.stageAwake];
      for (final s in stages) {
        expect(Aigaio.contrast(s, th.card), greaterThanOrEqualTo(3.0), reason: '${th.id} ${th.dark} $s');
      }
      for (final other in stages.skip(1)) {
        expect(th.stageDeep.computeLuminance(), lessThan(other.computeLuminance()), reason: '${th.id} ${th.dark}');
      }
      for (var i = 0; i < stages.length; i++) {
        for (var j = i + 1; j < stages.length; j++) {
          expect(_de76(stages[i], stages[j]), greaterThanOrEqualTo(20), reason: '${th.id} ${th.dark} $i–$j');
        }
      }
    }
    // Τα φωτεινά θέματα πριν: Αιγαίο REM 1,86 και ξύπνιος 2,01· Ελιά REM 1,78· Αυγή ξύπνιος 2,04.
    expect(Aigaio.contrast(Aigaio.light.stageRem, Aigaio.light.card), greaterThan(4.0));
  });

  // ------------------------------------------------------------------ R7-U1 (sleep.dart:258)
  testWidgets('Ύπνος του ρολογιού: «Ξύπνιος» με «τουλάχιστον» χωρίς σπασμένη λέξη (360 και 400 dp)', (t) async {
    final now = DateTime(2026, 11, 13, 10);
    // Το τελευταίο κομμάτι της τελευταίας νύχτας του δείγματος με δικές μου φάσεις: 4 λεπτά ξύπνιος στη μέση.
    final j = sampleDashboardJson(now);
    final last = (j['sleep'] as List).last as Map<String, dynamic>;
    final a = last['start'] as int, b = last['end'] as int;
    const m = 60 * 1000;
    last['stages'] = [
      ['LIGHT', a, a + 60 * m],
      ['AWAKE', a + 60 * m, a + 64 * m],
      ['DEEP', a + 64 * m, a + 94 * m],
      ['LIGHT', a + 94 * m, b],
    ];
    final s = HealthStore()..data = Dashboard.fromJson(j);
    s.history = sampleHistory(now, s.data!);
    // 360 dp: στήλη 292 / 3 ≈ 97 dp, στενότερη από το «τουλάχιστον» με 16 sp έντονα (≈ 101 dp, Inter): πριν έσπαγε.
    for (final w in [360.0, 400.0]) {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = Size(w, 5000);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: SleepPage(store: s, now: now)));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      for (final e in find.byType(RichText).evaluate()) {
        final p = e.renderObject! as RenderParagraph;
        if (p.text.toPlainText().contains('τουλάχιστον')) {
          expect(_broken(p), isEmpty, reason: '$w: ${p.text.toPlainText()}');
        }
      }
      // Οι τρεις στήλες (η τελευταία νύχτα του δείγματος έχει ξύπνιο), με «τουλάχιστον» κάτω από τη διάρκεια.
      final awake = find.byKey(const ValueKey('sleep-awake'));
      expect(awake, findsOneWidget);
      expect(find.descendant(of: awake, matching: find.text('τουλάχιστον')), findsOneWidget);
    }
  });
}
