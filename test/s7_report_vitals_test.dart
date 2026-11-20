// Αποφάσεις 20/11: πίεση, σάκχαρο και καρδιογράφημα στην αναφορά για τον γιατρό, μόνο όταν υπάρχουν μετρήσεις στο
// διάστημα (σελίδα 4). Επινοημένα δεδομένα.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/pages/report_page.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/vitals.dart';

import 'sample_data.dart';

final now = DateTime(2026, 11, 20, 18, 0);

Map<String, Object> _bp(String id, DateTime at, int s, int d) => {'id': id, 'k': 'bp', 'at': at.millisecondsSinceEpoch, 'sys': s, 'dia': d, 'pulse': 72};

Future<VitalsStore> _store(List<Map<String, Object>> items) async {
  final v = VitalsStore(io: MemoryVitalsIO(jsonEncode({'v': 1, 'items': items})));
  await v.ensureLoaded();
  return v;
}

Future<void> _pump(WidgetTester t, VitalsStore v) async {
  final store = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(now));
  store.history = sampleHistory(now, store.data!);
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = const Size(680, 5200);
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: ReportPage(store: store, now: now, vitals: v)));
  await t.pumpAndSettle();
}

void main() {
  test('μόνο οι μετρήσεις του διαστήματος, νεότερη πρώτη', () {
    final a = Vital(id: 'a', kind: VitalKind.bp, at: DateTime(2026, 11, 1, 8), sys: 130, dia: 80);
    final b = Vital(id: 'b', kind: VitalKind.bp, at: DateTime(2026, 11, 20, 23, 30), sys: 128, dia: 82);
    final old = Vital(id: 'c', kind: VitalKind.bp, at: DateTime(2026, 8, 1), sys: 140, dia: 90);
    final after = Vital(id: 'd', kind: VitalKind.bp, at: DateTime(2026, 11, 21, 0, 10), sys: 120, dia: 80);
    final r = reportVitals([a, b, old, after], DateTime(2026, 8, 23), DateTime(2026, 11, 20));
    expect([for (final v in r) v.id], ['b', 'a']);
  });

  testWidgets('χωρίς μετρήσεις: 3 σελίδες, και το λέει', (t) async {
    await _pump(t, await _store(const []));
    expect(find.byKey(const ValueKey('report-page4-body')), findsNothing);
    expect(find.textContaining('σελίδα 3 από 3'), findsOneWidget);
    expect(find.textContaining('σε τρεις σελίδες'), findsOneWidget);
    final not = t.widget<Text>(find.descendant(of: find.byKey(const ValueKey('report-not-included')), matching: find.byType(Text)));
    expect(not.textSpan!.toPlainText(), contains('καμία μέτρηση σε αυτό το διάστημα'));
  });

  testWidgets('με πίεση και σάκχαρο: σελίδα 4, μέσος όρος με τους κανόνες της οθόνης', (t) async {
    final items = [
      for (var i = 0; i < 14; i++) _bp('bp$i', DateTime(2026, 11, 20 - i ~/ 2, i.isEven ? 8 : 21), 126, 78),
      {'id': 'g1', 'k': 'glucose', 'at': DateTime(2026, 11, 18, 8).millisecondsSinceEpoch, 'glu': 104, 'when': 'fasting'},
      {'id': 'e1', 'k': 'ecg', 'at': DateTime(2026, 11, 10, 9).millisecondsSinceEpoch, 'ecg': 'sinus'},
    ];
    await _pump(t, await _store(items));
    expect(find.byKey(const ValueKey('report-page4-body')), findsOneWidget);
    expect(find.textContaining('σελίδα 4 από 4'), findsOneWidget);
    expect(find.textContaining('σελίδα 1 από 4'), findsOneWidget);
    expect(find.textContaining('σε τέσσερις σελίδες'), findsOneWidget);
    expect(find.text('Πίεση (14 μετρήσεις)'), findsOneWidget);
    expect(find.textContaining('«αυξημένη» κατά ESC 2024'), findsOneWidget);
    expect(find.text('104'), findsOneWidget);
    expect(find.text(ecgText(EcgResult.sinus)), findsOneWidget);
    final not = t.widget<Text>(find.descendant(of: find.byKey(const ValueKey('report-not-included')), matching: find.byType(Text)));
    expect(not.textSpan!.toPlainText(), contains('στη σελίδα 4'));
    expect(not.textSpan!.toPlainText(), contains('Πίεση, σάκχαρο'));
  });
}
