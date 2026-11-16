// Πίεση, σάκχαρο, καρδιογραφήματα (16/11). Επινοημένες τιμές.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/backup.dart';
import 'package:ygeia_forma/pages/vitals_page.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/vitals.dart';

final now = DateTime(2026, 11, 18, 9);

Vital bp(String id, int s, int d, {int daysAgo = 0}) =>
    Vital(id: id, kind: VitalKind.bp, at: now.subtract(Duration(days: daysAgo)), sys: s, dia: d, pulse: 64);

void main() {
  test('Γράφεται και διαβάζεται· λάθος τιμές δεν περνούν', () {
    final v = bp('a', 128, 82);
    expect(Vital.fromJson(jsonDecode(jsonEncode(v.toJson())))!.sys, 128);
    expect(Vital.fromJson({'id': 'x', 'k': 'bp', 'at': 1, 'sys': 80, 'dia': 120}), isNull, reason: 'μικρή > μεγάλη');
    expect(Vital.fromJson({'id': 'x', 'k': 'glucose', 'at': 1, 'glu': 95, 'when': 'fasting'})!.glucose, 95);
    expect(Vital.fromJson({'id': 'x', 'k': 'glucose', 'at': 1, 'glu': 950, 'when': 'fasting'}), isNull);
    expect(Vital.fromJson({'id': 'x', 'k': 'ecg', 'at': 1, 'ecg': 'sinus'})!.ecg, EcgResult.sinus);
    expect(bpProblem(300, 80, null), isNotNull);
  });

  test('Μέσος όρος 7 ημερών και το όριο του σπιτιού (135/85)', () {
    final list = [bp('a', 130, 80), bp('b', 140, 86, daysAgo: 3), bp('c', 180, 110, daysAgo: 9)];
    final a = bpAverage(list, now)!;
    expect(a.n, 2);
    expect(bpAverageText(a), contains('135/83'));
    expect(bpAverageText(a), contains('Πάνω από το όριο'));
    expect(bpAverage([bp('c', 180, 110, daysAgo: 9)], now), isNull);
  });

  test('Σάκχαρο: σημείωση μόνο όπου είναι καθαρό', () {
    Vital g(double v, GlucoseWhen w) => Vital(id: 'g', kind: VitalKind.glucose, at: now, glucose: v, when: w);
    expect(glucoseNote(g(92, GlucoseWhen.fasting)), contains('φυσιολογικό'));
    expect(glucoseNote(g(110, GlucoseWhen.fasting)), contains('γιατρό'));
    expect(glucoseNote(g(140, GlucoseWhen.after)), isNull);
    expect(glucoseNote(g(60, GlucoseWhen.random)), contains('χαμηλό'));
  });

  test('Αποθήκευση, διαγραφή, επαναφορά από αντίγραφο, χαλασμένο αρχείο στην άκρη', () async {
    final io = MemoryVitalsIO();
    final s = VitalsStore(io: io);
    await s.load();
    expect(await s.add(bp('a', 128, 82)), isTrue);
    expect(await s.add(bp('b', 125, 80, daysAgo: 1)), isTrue);
    final s2 = VitalsStore(io: MemoryVitalsIO(io.json));
    await s2.load();
    expect(s2.of(VitalKind.bp).map((v) => v.id), ['a', 'b']);
    expect(await s2.remove(s2.all.first), isTrue);
    final text = buildBackup(foodLog: const [], myFoods: const [], prefs: const {}, now: now, vitals: s.forBackup());
    expect(await s2.importItems(parseBackup(text).vitals), 1, reason: 'μόνο η «a» λείπει');
    final bad = VitalsStore(io: MemoryVitalsIO('χαλασμένο'));
    await bad.load();
    expect(bad.read, isTrue);
    expect(bad.error, contains('κρατήθηκε'));
  });

  testWidgets('Νέα πίεση από τη σελίδα: λάθος → μήνυμα, σωστή → στη λίστα με τον μέσο όρο', (t) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(420, 1400);
    addTearDown(t.view.reset);
    final s = VitalsStore(io: MemoryVitalsIO());
    await s.load();
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: VitalsPage(store: s, now: () => now)));
    await t.tap(find.byKey(const ValueKey('vital-add')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('bp-sys')), '80');
    await t.enterText(find.byKey(const ValueKey('bp-dia')), '120');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('vital-error')), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('bp-sys')), '128');
    await t.enterText(find.byKey(const ValueKey('bp-dia')), '82');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('vital-save')));
    await t.pumpAndSettle();
    expect(find.text('128/82 mmHg'), findsOneWidget);
    expect(find.byKey(const ValueKey('bp-average')), findsOneWidget);
  });

  test('Έλεγχος 16/11: επαναφορά πριν διαβαστεί το αρχείο → το διαβάζει πρώτα· πολύ υψηλή πίεση λέει τι να κάνεις', () async {
    final io = MemoryVitalsIO(jsonEncode({
      'v': 1,
      'items': [bp('a', 120, 80).toJson()]
    }));
    final s = VitalsStore(io: io);
    expect(s.read, isFalse);
    expect(await s.importItems([bp('b', 125, 82).toJson(), bp('b', 125, 82).toJson(), bp('a', 120, 80).toJson()]), 1);
    expect(s.all.map((v) => v.id).toSet(), {'a', 'b'});
    expect(bpNote(bp('x', 182, 95)), contains('166'));
    expect(bpNote(bp('y', 150, 95)), isNull);
  });
}
