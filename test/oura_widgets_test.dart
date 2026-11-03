// Η σελίδα «Oura» ως widget: «Αναίρεση» μόνο όταν είχε αρχίσει εποχή Oura (M-12), το «Ενημέρωση τώρα» ξανανοίγει
// μόνο του με ένα χρονόμετρο μίας χρήσης (M-10), «Η τελευταία νύχτα από το ρολόι» μόνο τη μέρα της σύνδεσης (N-1).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/oura/oura_api.dart';
import 'package:ygeia_forma/pages/oura_pages.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/theme.dart';

import 'sample_data.dart';

void main() {
  final now = DateTime(2026, 11, 14, 15);
  final today = DateTime(2026, 11, 14);

  HealthStore store(SourcePlan plan, {DateTime Function()? clock}) => HealthStore()
    ..data = Dashboard.fromJson(sampleDashboardJson(now))
    ..ouraLink = OuraLink(vault: MemoryVault(), clientId: 'TEST')
    ..ouraClock = (clock ?? () => now)
    ..ouraHasTokens = true
    ..debugSetPlan(plan);

  Future<void> pump(WidgetTester t, HealthStore s) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(420, 2600);
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: OuraManagePage(store: s, now: now)));
    await t.pump();
  }

  Future<void> disconnect(WidgetTester t) async {
    await t.ensureVisible(find.byKey(const ValueKey('oura-disconnect')));
    await t.tap(find.byKey(const ValueKey('oura-disconnect')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Αποσύνδεση'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
  }

  testWidgets('M-12: σύνδεση με αρχή απόψε → αποσύνδεση χωρίς «Αναίρεση»', (t) async {
    await pump(t, store(SourcePlan([SourceEra(Source.oura, DateTime(2026, 11, 15))])));
    await disconnect(t);
    expect(find.text('Αποσυνδέθηκε. Τα δεδομένα που είχαν έρθει μένουν.'), findsOneWidget);
    expect(find.text('Αναίρεση'), findsNothing);
  });

  testWidgets('M-12: εποχή Oura σε εξέλιξη → αποσύνδεση με «Αναίρεση»', (t) async {
    await pump(t, store(SourcePlan([SourceEra(Source.oura, DateTime(2026, 11, 6))])));
    await disconnect(t);
    expect(find.text('Αναίρεση'), findsOneWidget);
  });

  testWidgets('M-10: «Ενημέρωση τώρα» ανενεργό μέσα στο λεπτό, ενεργό μόνο του μετά', (t) async {
    var clock = now;
    final s = store(SourcePlan([SourceEra(Source.oura, DateTime(2026, 11, 6))]), clock: () => clock)
      ..ouraTriedMs = now.subtract(const Duration(seconds: 30)).millisecondsSinceEpoch;
    await pump(t, s);
    FilledButton button() => t.widget<FilledButton>(find.ancestor(
        of: find.text('Ενημέρωση τώρα'), matching: find.byWidgetPredicate((w) => w is FilledButton)));
    expect(button().onPressed, isNull);
    clock = now.add(const Duration(seconds: 31));
    await t.pump(const Duration(seconds: 31));
    expect(button().onPressed, isNotNull);
  });

  testWidgets('N-1: τη μέρα της σύνδεσης, με πρώτη νύχτα τη σημερινή: «Η τελευταία νύχτα από το ρολόι»', (t) async {
    final s = store(SourcePlan([SourceEra(Source.oura, today)]))
      ..ouraConnectedMs = DateTime(2026, 11, 14, 9).millisecondsSinceEpoch;
    await pump(t, s);
    expect(find.byKey(const ValueKey('oura-watch-last-night')), findsOneWidget);
    // Την επόμενη μέρα δεν φαίνεται.
    final s2 = store(SourcePlan([SourceEra(Source.oura, today)]), clock: () => DateTime(2026, 11, 15, 10))
      ..ouraConnectedMs = DateTime(2026, 11, 14, 9).millisecondsSinceEpoch;
    await pump(t, s2);
    expect(find.byKey(const ValueKey('oura-watch-last-night')), findsNothing);
  });
}
