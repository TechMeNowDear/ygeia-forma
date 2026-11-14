// Συγχώνευση 3 (audit-e + audit-f, 4/11): οι δύο μικρές διορθώσεις της συγχώνευσης, με ελέγχους που αποτυγχάνουν
// χωρίς αυτές.
// S5 (έλεγχος 3, 1_sleep.md): νύχτα του Oura σε κομμάτια → το οξυγόνο του ρολογιού (μέσος όρος με στάθμιση
//    διάρκειας, χαμηλότερη μέτρηση, λεπτά κάτω από 90%) και οι σημειώσεις οξυγόνου από ΟΛΑ τα κομμάτια που μετρούν
//    (ένωση των διαστημάτων τους, χωρίς τα κενά), όχι μόνο από την κύρια περίοδο.
// PDF: η σημείωση 400 χαρακτήρων φαίνεται ολόκληρη (χωρίς όριο γραμμών, χωρίς «…»), και η σελίδα 1 δεν ξεχειλίζει.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/oura/oura_model.dart';
import 'package:ygeia_forma/oxygen_note.dart';
import 'package:ygeia_forma/pages/compare_page.dart';
import 'package:ygeia_forma/pages/report_page.dart';
import 'package:ygeia_forma/report.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/theme.dart';

import 'sample_data.dart';

int ms(DateTime t) => t.millisecondsSinceEpoch;

/// Περίοδος ύπνου του Oura (η «day» όπως στην Oura: έναρξη από τις 18:00 → η επόμενη μέρα).
Map<String, dynamic> ouraPeriod(String id, DateTime a, DateTime b) => {
      'id': id,
      'day': dateKey(a.hour >= 18 ? DateTime(a.year, a.month, a.day + 1) : dayOf(b)),
      'type': 'sleep',
      'bedtime_start': a.toUtc().toIso8601String(),
      'bedtime_end': b.toUtc().toIso8601String(),
      'total_sleep_duration': b.difference(a).inSeconds,
    };

/// Μέτρηση οξυγόνου του ρολογιού: [αρχή, τέλος, μέσο, ελάχιστο, μέγιστο, δευτερόλεπτα κάτω από 90%].
List<num> ox(DateTime a, DateTime b, num avg, num min, num belowSec) => [ms(a), ms(b), avg, min, avg, belowSec];

Future<void> _loadInter() async {
  final inter = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
  }
  await inter.load();
}

void main() {
  group('S5: νύχτα του Oura σε κομμάτια → οξυγόνο από όλα τα κομμάτια που μετρούν', () {
    // 23:00–01:30 + 03:00–06:45: κύρια η δεύτερη (περισσότερα λεπτά στο 22:00–08:00), η πρώτη ενώνεται (από τις
    // 20:00, κενό 90′ ≤ 4 ώρες). Το κενό 01:30–03:00 δεν μετρά.
    final a1 = DateTime(2026, 11, 2, 23);
    final b1 = DateTime(2026, 11, 3, 1, 30);
    final a2 = DateTime(2026, 11, 3, 3);
    final b2 = DateTime(2026, 11, 3, 6, 45);
    final day = DateTime(2026, 11, 3);
    final nights = parseOura(
      sleep: [ouraPeriod('p1', a1, b1), ouraPeriod('p2', a2, b2)],
      dailySleep: const [],
      readiness: const [],
    ).nights;
    final windows = ouraSleepWindows(nights);
    final d = Dashboard.fromJson({
      'readAt': ms(DateTime(2026, 11, 3, 10)),
      'sleep': <Object>[],
      'spo2': [
        // Πρώτο κομμάτι: 30′, μέσο 90, ελάχιστο 76, 10′ κάτω από 90%.
        ox(DateTime(2026, 11, 3, 0, 0), DateTime(2026, 11, 3, 0, 30), 90, 76, 600),
        // Στο κενό (ξύπνιος): ΔΕΝ μετρά.
        ox(DateTime(2026, 11, 3, 2, 0), DateTime(2026, 11, 3, 2, 30), 70, 60, 1800),
        // Κύριο κομμάτι: 180′, μέσο 96, ελάχιστο 92, 0′ κάτω από 90% (κάλυψη 210′ από 375′ ≥ 50%, 7/11).
        ox(DateTime(2026, 11, 3, 3, 30), DateTime(2026, 11, 3, 6, 30), 96, 92, 0),
      ],
    });

    test('Η νύχτα έχει δύο κομμάτια που μετρούν· τα παράθυρα έχουν και τα δύο, χωρίς το κενό', () {
      final n = nights.singleWhere((n) => n.main != null);
      expect(n.counted.length, 2);
      expect(windows.mains[dateKey(day)], (a2, b2), reason: 'η κύρια περίοδος μένει η ίδια (για «έχει νύχτα»)');
      expect(windows.nightPieces(dateKey(day)), [(a1, b1), (a2, b2)]);
      expect(windows.nightPieces('2026-11-04'), isEmpty);
    });

    test('Μέσος όρος (στάθμιση διάρκειας), χαμηλότερη και λεπτά < 90% από ΟΛΑ τα κομμάτια· το κενό έξω', () {
      final o = d.watchSpo2(day, windows)!;
      // Πριν: μόνο η κύρια περίοδος → μέσο 96, ελάχιστο 92, 0′.
      expect(o.avg, closeTo((90 * 30 + 96 * 180) / 210, 1e-9));
      expect(o.min, 76);
      expect(o.below90, closeTo(10, 1e-9));
      expect(o.cov, closeTo(210 / 375, 1e-9));
    });

    test('7/11: κάλυψη κάτω από 50% → η χαμηλότερη δεν μετρά (ούτε στις σημειώσεις)', () {
      final thin = Dashboard.fromJson({
        'readAt': ms(DateTime(2026, 11, 3, 10)),
        'sleep': <Object>[],
        'spo2': [ox(DateTime(2026, 11, 3, 4, 0), DateTime(2026, 11, 3, 5, 0), 90, 70, 600)],
      });
      final o = thin.watchSpo2(day, windows)!;
      expect(o.cov, closeTo(60 / 375, 1e-9));
      expect(spo2MinShown(o.cov), isFalse);
      final history = {dateKey(day): {K.spo2Min: 70.0, K.spo2Cov: 60 / 375}};
      expect(thin.spo2MinByNight(day, ouraNights: true, windows: windows, history: history), isEmpty);
      final plan = SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 10, 20));
      expect(summarizeDay(thin, day, plan: plan, windows: windows)[K.spo2Cov], closeTo(60 / 375, 1e-9));
    });

    test('Ίδια τιμή στο ιστορικό (Τάσεις, αναφορά) και στις σημειώσεις οξυγόνου', () {
      final plan = SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 10, 20));
      final row = summarizeDay(d, day, plan: plan, windows: windows);
      expect(row[K.spo2Min], 76);
      expect(row[K.spo2Avg], closeTo((90 * 30 + 96 * 180) / 210, 1e-9));
      expect(row[K.spo2Low], closeTo(10, 1e-9));
      // Μία ακόμα νύχτα < 80% στον μήνα: με την πρώτη περίοδο μέσα, «2 νύχτες» (πριν: η 76% χανόταν).
      final history = {
        dateKey(DateTime(2026, 10, 25)): {K.spo2Min: 74.0},
      };
      final m = d.spo2MinByNight(day, ouraNights: true, windows: windows, history: history);
      expect(m[day], 76);
      final g = oxygenGuidance(m, day, today: day);
      expect(g.veryLowRepeated, isTrue);
      expect(g.messages.single, contains('(25/10: 74%, 3/11: 76%)'));
    });

    test('Νύχτα σε ένα κομμάτι: όπως πριν (μόνο η κύρια)', () {
      final one = ouraSleepWindows(parseOura(
        sleep: [ouraPeriod('p2', a2, b2)],
        dailySleep: const [],
        readiness: const [],
      ).nights);
      expect(one.nightPieces(dateKey(day)), [(a2, b2)]);
      final o = d.watchSpo2(day, one)!;
      expect(o.min, 92);
      expect(o.avg, 96);
    });

    test('Ένωση διαστημάτων: επικαλυπτόμενα/διαδοχικά γίνονται ένα, τα κενά μένουν έξω', () {
      DateTime h(int x) => DateTime(2026, 11, 3, x);
      expect(unionOfRanges([(h(5), h(7)), (h(1), h(3)), (h(2), h(4)), (h(7), h(8))]), [(h(1), h(4)), (h(5), h(8))]);
      expect(unionOfRanges(const []), isEmpty);
    });
  });

  group('PDF: η σημείωση 400 χαρακτήρων ολόκληρη, χωρίς υπερχείλιση στη σελίδα 1', () {
    setUpAll(_loadInter);

    Future<void> pumpReport(WidgetTester t, String note, {bool withName = false}) async {
      final now = DateTime(2026, 10, 24, 16, 30);
      final store = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(now));
      store.history = sampleHistory(now, store.data!);
      if (withName) store.prefs.reportName = 'Γιάννης Παπαδόπουλος';
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(680, 3600);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: ReportPage(store: store, now: now, note: note)));
      await t.pumpAndSettle();
    }

    /// Ολόκληρη: χωρίς όριο γραμμών και «…», και το ύψος του κειμένου στην οθόνη = το ύψος όλου του κειμένου.
    void expectWhole(WidgetTester t, String note) {
      expect(t.takeException(), isNull, reason: 'καμία υπερχείλιση');
      final f = find.byKey(const ValueKey('report-note-text'));
      final w = t.widget<Text>(f);
      expect(w.maxLines, isNull);
      expect(w.overflow, isNot(TextOverflow.ellipsis));
      expect(w.data, 'Σημείωση: ${reportNoteText(note)}');
      final p = t.renderObject<RenderParagraph>(f);
      expect(p.didExceedMaxLines, isFalse);
      final tp = TextPainter(text: p.text, textDirection: TextDirection.ltr, textScaler: TextScaler.noScaling)
        ..layout(maxWidth: p.constraints.maxWidth);
      expect(p.size.height, closeTo(tp.height, 0.01), reason: 'όλες οι γραμμές φαίνονται');
      expect(tp.computeLineMetrics().length, greaterThanOrEqualTo(4));
      tp.dispose();
      // Η σημείωση και ο πίνακας μέσα στη σελίδα, πάνω από το υποσέλιδο.
      final footer = t.getRect(find.textContaining('σελίδα 1 από'));
      expect(t.getRect(f).bottom, lessThan(footer.top));
      expect(t.getRect(find.text('Πώς διαβάζεται').first).bottom, lessThan(footer.top));
    }

    testWidgets('Ρεαλιστική (επινοημένη) σημείωση 400 χαρακτήρων: ολόκληρη, και η σελίδα 1 χωρά όπως είναι (κλίμακα 1)', (t) async {
      final note = ('Φάρμακα: βισοπρολόλη 2,5 mg πρωί. Κάπνισμα 10/μέρα. Ροχαλητό (σύζυγος). Τεστ άπνοιας Samsung 13/10 '
              'και 16/10 αρνητικά. Ζαλάδα το πρωί κάποιες μέρες. ' * 3)
          .substring(0, 400);
      expect(note.length, reportNoteMax);
      await pumpReport(t, note, withName: true);
      expectWhole(t, note);
      expect(find.textContaining('13/10 και'), findsWidgets, reason: 'το τέλος της σημείωσης φαίνεται');
      // Round 1 (U1b-01, f4): το σώμα της σελίδας 1 είναι πια [RenderReportFit] (πριν RenderFittedBox).
      final box = t.renderObject<RenderReportFit>(find.byKey(const ValueKey('report-page1-body')));
      expect(box.scale, 1.0, reason: 'χωρίς σμίκρυνση');
    });

    testWidgets('Χειρότερη περίπτωση: 400 φαρδιοί χαρακτήρες με αλλαγές γραμμής → ολόκληρη, χωρίς υπερχείλιση', (t) async {
      final note = List.generate(40, (i) => i.isEven ? 'ΩΜΩΜΩΜΩΜΩ\n' : 'ΜΩΜΩΜΩΜΩΜ ').join();
      expect(note.length, 400);
      await pumpReport(t, note, withName: true);
      expectWhole(t, note);
      expect(reportNoteText(note), isNot(contains('\n')));
      final scale = t.renderObject<RenderReportFit>(find.byKey(const ValueKey('report-page1-body'))).scale;
      expect(scale, greaterThan(0.85), reason: 'το πολύ λίγη σμίκρυνση, ευανάγνωστο');
    });

    test('Αλλαγές γραμμής → « · », διπλά κενά → ένα· κανένας χαρακτήρας δεν χάνεται', () {
      expect(reportNoteText('Φάρμακα: Α\n\nΚάπνισμα  ναι \n Ροχαλητό'), 'Φάρμακα: Α · Κάπνισμα ναι · Ροχαλητό');
    });
  });

  test('Σύγκριση πηγών: Oura ύπνος + ξύπνιος = «με τα ξυπνήματα» και με δευτερόλεπτα (στιγμιότυπο 62: 7:16 + 22′ ≠ 7:37)', () {
    final bed = DateTime(2026, 11, 2, 23, 40);
    const latency = 630, sleep = 26190, awakeIn = 1290; // 10,5′ · 436,5′ · 21,5′
    final oura = parseOura(sleep: [
      {
        'id': 'x',
        'day': '2026-11-03',
        'type': 'long_sleep',
        'bedtime_start': bed.toUtc().toIso8601String(),
        'bedtime_end': bed.add(const Duration(seconds: latency + sleep + awakeIn)).toUtc().toIso8601String(),
        'time_in_bed': latency + sleep + awakeIn,
        'total_sleep_duration': sleep,
        'awake_time': awakeIn + latency,
        'latency': latency,
      },
    ], dailySleep: const [], readiness: const []).nights;
    final plan = SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 3));
    final r = buildCompareRows(plan: plan, oura: oura, watch: const [], today: DateTime(2026, 11, 3)).single;
    expect(r.ouraMinutes, 437);
    expect(r.ouraAwake, 22);
    expect(r.ouraSpan, r.ouraMinutes! + r.ouraAwake!, reason: 'πριν: 458 (κομμένα λεπτά)');
  });

  test('Δείγμα στιγμιοτύπων: οι ζυγίσεις της InBody έχουν το σημάδι της (όχι «όχι InBody» στην αναφορά)', () {
    final now = DateTime(2026, 11, 14, 10, 20);
    final d = Dashboard.fromJson(sampleDashboardJson(now));
    final r = buildReport(sampleHistory(now, d), now);
    expect(r.weighIns, isNotEmpty);
    expect(r.otherWeighIns, isEmpty);
  });

  test('Ο κώδικας της σελίδας 1 δεν έχει πια όριο γραμμών στη σημείωση', () {
    final src = File('lib/pages/report_page.dart').readAsStringSync();
    final i = src.indexOf("ValueKey('report-note-text')");
    expect(i, greaterThan(0));
    final block = src.substring(i, src.indexOf('style:', i));
    expect(block, isNot(contains('maxLines')));
    expect(block, isNot(contains('ellipsis')));
  });
}
