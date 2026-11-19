// 18/11: μετρητής αντιγράφου Google και εξαγωγή σε άλλο isolate.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/backup.dart';
import 'package:ygeia_forma/pages/cloud_backup_size.dart';
import 'package:ygeia_forma/theme.dart';

void main() {
  test('κείμενο μεγέθους', () {
    expect(cloudBackupText(3355443), 'Αντίγραφο Google: 3,2 MB από 25 MB');
    expect(cloudBackupText(21 * 1024 * 1024), 'Αντίγραφο Google: 21 MB από 25 MB');
    // Έλεγχος 19/11 (CB-3): κάτω από το όριο ποτέ «25 από 25».
    expect(cloudBackupText(25 * 1024 * 1024 - 1000), 'Αντίγραφο Google: 24,9 MB από 25 MB');
    expect(cloudBackupText(26 * 1024 * 1024), 'Αντίγραφο Google: 26 MB από 25 MB');
  });

  test('buildBackupFrom = buildBackup (ίδια ορίσματα, ίδιο αρχείο)', () {
    final now = DateTime(2026, 11, 18, 22);
    final BackupArgs a = (
      foodLog: const [],
      myFoods: const [],
      prefs: const {'me': {'by': 1985}},
      now: now,
      sources: null,
      training: null,
      dishes: null,
      foodLikes: null,
      foodDays: const {'2026-11-17': 'done'},
      foodUnits: null,
      vitals: null,
      foodWeek: null,
      foodRemind: 21,
      history: const {'2026-11-17': {'steps': 8000.0}},
      errorsOff: true,
    );
    final viaArgs = buildBackupFrom(a);
    final direct = buildBackup(
      foodLog: const [],
      myFoods: const [],
      prefs: const {'me': {'by': 1985}},
      now: now,
      foodDays: const {'2026-11-17': 'done'},
      foodRemind: 21,
      history: const {'2026-11-17': {'steps': 8000.0}},
      errorsOff: true,
    );
    expect(viaArgs, direct);
    expect((jsonDecode(viaArgs) as Map)['foodRemind'], 21);
  });

  Widget app(Widget w) => MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: Column(children: [w])));

  testWidgets('Σήμερα: κάρτα μόνο από 20 MB και πάνω', (t) async {
    CloudBackupMeter.debugSet(5 * 1024 * 1024);
    await t.pumpWidget(app(const CloudBackupWarningCard()));
    await t.pump();
    expect(find.byKey(const ValueKey('today-cloud-size')), findsNothing);
    CloudBackupMeter.debugSet(22 * 1024 * 1024);
    await t.pumpWidget(app(const CloudBackupWarningCard(key: ValueKey('x'))));
    await t.pump();
    expect(find.byKey(const ValueKey('today-cloud-size')), findsOneWidget);
    expect(find.text('Αντίγραφο Google: 22 MB από 25 MB.'), findsOneWidget);
  });

  testWidgets('Ρυθμίσεις: γραμμή μεγέθους· χωρίς μέτρηση τίποτα', (t) async {
    CloudBackupMeter.debugSet(null);
    await t.pumpWidget(app(const CloudBackupLine()));
    await t.pump();
    expect(find.byKey(const ValueKey('settings-cloud-size')), findsNothing);
    CloudBackupMeter.debugSet(3355443);
    await t.pumpWidget(app(const CloudBackupLine(key: ValueKey('y'))));
    await t.pump();
    expect(find.text('Αντίγραφο Google: 3,2 MB από 25 MB'), findsOneWidget);
  });
}
