// Βαθύς έλεγχος 20/11/2026, κατηγορία 7 (οθόνες και κείμενα): διάταξη και συνέπεια λέξεων. Επινοημένα δεδομένα.
// Κάθε δοκιμή γράφει τι έβγαινε πριν.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/history.dart' show K;
import 'package:ygeia_forma/oura/oura_model.dart' show pieceMinutesShown;
import 'package:ygeia_forma/pages/info_sheet.dart';
import 'package:ygeia_forma/pages/vitals_page.dart';
import 'package:ygeia_forma/reference.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/vitals.dart';

void main() {
  // ------------------------------------------------------------------------------------------------------- K7A-03
  test('K7A-03: στο ⓘ τα μακριά «Πάνω / Κάτω» πάνε το ένα κάτω από το άλλο (πριν: πάντα δύο στενές στήλες)', () {
    final oxygen = metricInfos[K.ringSpo2]!;
    expect(oxygen.down!.length, greaterThan(infoPillSideMax), reason: 'το «Κάτω» του οξυγόνου είναι κείμενο ασφαλείας, μακρύ');
    expect(infoPillsSideBySide(oxygen.up, oxygen.down, veryLarge: false), isFalse);
    expect(infoPillsSideBySide('Περισσότερη κίνηση.', 'Λιγότερη κίνηση.', veryLarge: false), isTrue);
    expect(infoPillsSideBySide('Περισσότερη κίνηση.', 'Λιγότερη κίνηση.', veryLarge: true), isFalse, reason: 'πολύ μεγάλα γράμματα');
    expect(infoPillsSideBySide(null, 'x' * infoPillSideMax, veryLarge: false), isTrue);
    expect(infoPillsSideBySide('x' * (infoPillSideMax + 1), null, veryLarge: false), isFalse);
    // Και οι δύο διατάξεις υπάρχουν στα ⓘ της εφαρμογής (αν όλα γίνουν στήλη ή όλα σειρά, το όριο θέλει ξανά κοίταγμα).
    final withPills = metricInfos.values.where((i) => i.up != null || i.down != null).toList();
    expect(withPills.where((i) => infoPillsSideBySide(i.up, i.down, veryLarge: false)), isNotEmpty);
    expect(withPills.where((i) => !infoPillsSideBySide(i.up, i.down, veryLarge: false)), isNotEmpty);
  });

  testWidgets('K7A-03: το ⓘ του οξυγόνου στα 344 dp: «Κάτω» σε όλο το πλάτος (πριν: στήλη 130 dp, 34 γραμμές)', (t) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(344, 2400);
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showMetricInfo(context, metricInfos[K.ringSpo2]!),
            child: const Text('άνοιξε'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('άνοιξε'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('info-pills-column')), findsOneWidget);
    expect(find.byKey(const ValueKey('info-pills-row')), findsNothing);
    expect(t.getSize(find.byKey(const ValueKey('info-pills-column'))).width, greaterThan(280));
    expect(find.text(metricInfos[K.ringSpo2]!.down!), findsOneWidget, reason: 'το κείμενο ασφαλείας ολόκληρο, αυτούσιο');
  });

  // ------------------------------------------------------------------------------------------------------- K7A-02
  testWidgets('K7A-02: σελίδα πίεσης στα 344 dp: η καρτέλα «Καρδιογράφημα» ολόκληρη (πριν: κομμένη σε τρία ίσα τμήματα)',
      (t) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(344, 800);
    addTearDown(t.view.reset);
    final s = VitalsStore(io: MemoryVitalsIO());
    await s.load();
    await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light), home: VitalsPage(store: s, now: () => DateTime(2026, 11, 20, 18))));
    await t.pumpAndSettle();
    for (final label in ['Πίεση', 'Σάκχαρο', 'Καρδιογράφημα']) {
      final p = t.renderObject<RenderParagraph>(find.descendant(
          of: find.byKey(ValueKey('tab-$label')), matching: find.text(label)));
      expect(p.didExceedMaxLines, isFalse, reason: label);
      final natural = TextPainter(text: p.text, textDirection: TextDirection.ltr, textScaler: p.textScaler, maxLines: 1)..layout();
      expect(p.size.width, greaterThanOrEqualTo(natural.width - 0.01), reason: '$label: ολόκληρη η λέξη');
      natural.dispose();
    }
    expect(find.text('Νέα μέτρηση'), findsOneWidget);
    expect(find.textContaining('Νέα: '), findsNothing);
    // Η καρτέλα αλλάζει το είδος όπως πριν.
    await t.tap(find.byKey(const ValueKey('tab-Σάκχαρο')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('vital-add')), findsOneWidget);
  });

  // ------------------------------------------------------------------------------------------------------- K7A-15
  test('K7A-15: τα κομμάτια της νύχτας αθροίζουν στον μεγάλο αριθμό (πριν: 1 λεπτό διαφορά από το στρογγύλεμα)', () {
    // 5.429 s + 8.669 s = 14.098 s → νύχτα 235 λεπτά. Πριν: «1 ώρα 30» + «2 ώρες 24» = 234 κάτω από «3 ώρες 55».
    expect(pieceMinutesShown([5429, 8669], 235), [90, 145]);
    expect(pieceMinutesShown([8669, 5429], 235), [145, 90], reason: 'το μεγαλύτερο κομμάτι παίρνει τη διαφορά, όπου κι αν είναι');
    // Όταν ήδη συμφωνούν, τίποτα δεν αλλάζει.
    expect(pieceMinutesShown([5400, 9000], 240), [90, 150]);
    expect(pieceMinutesShown([3630, 3630, 3630], 182), [60, 61, 61], reason: '3 × 60,5 λεπτά = 181,5 → 182· όχι 61 + 61 + 61 = 183');
    // Κομμάτι χωρίς διάρκεια, νύχτα χωρίς διάρκεια, ή διαφορά που δεν είναι στρογγύλεμα: όπως είναι.
    expect(pieceMinutesShown([5429, null], 235), [90, null]);
    expect(pieceMinutesShown([5429, 8669], null), [90, 144]);
    expect(pieceMinutesShown([5429, 8669], 300), [90, 144]);
    expect(pieceMinutesShown(const [], 0), isEmpty);
  });

  // ------------------------------------------------------------------------------------------------------- K7B
  test('K7B-03: «Άλλαξέ το με AI»: κανένα δεκαδικό με τελεία στην οθόνη (πριν: «Κορεσμένα: 4.2 → 3.1 g»)', () {
    final src = File('lib/pages/ai_week.dart').readAsStringSync();
    expect(src, isNot(contains('toStringAsFixed')));
    expect(src, contains(r"'Κορεσμένα: ${dec(oldT.satFat)} → ${dec(newT.satFat)} g\n'"));
  });

  test('K7B-16: «διάλειμμα» ανάμεσα στα σετ· «Ξεκούραση» μόνο για τη μέρα χωρίς προπόνηση', () {
    final editor = File('lib/pages/training/program_editor.dart').readAsStringSync();
    expect(editor, contains(r"'διάλειμμα ${restText(i.rest)}'"));
    expect(editor, contains("child: Text('Ξεκούραση')"), reason: 'η μέρα ξεκούρασης στη λίστα ημερών μένει');
    final session = File('lib/pages/training/session_page.dart').readAsStringSync();
    expect(session, contains(r'διάλειμμα\u00A0${restText(e.rest)}'));
    expect(session, isNot(contains(r'ξεκούραση\u00A0${restText(e.rest)}')));
  });

  test('K7B-04: «οι συνταγές, όταν έρθουν» δεν γράφεται πια (υπάρχουν από 15/11)', () {
    for (final f in ['lib/pages/kitchen.dart', 'lib/pages/me_page.dart']) {
      expect(File(f).readAsStringSync(), isNot(contains('όταν έρθουν')), reason: f);
    }
  });
}
