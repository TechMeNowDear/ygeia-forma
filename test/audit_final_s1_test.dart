// Τελικός έλεγχος, Συμβούλιο 1 (ιατρικό): δοκιμές για όσα διορθώθηκαν στο κινητό. Φανταστικές τιμές (δημόσιο repo).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/pages/training/hr_widgets.dart';
import 'package:ygeia_forma/theme.dart';

import 'sample_data.dart';
import 'training_sample.dart';

void main() {
  group('μ2: βασικός μεταβολισμός της ζύγισης', () {
    final when = DateTime(2026, 10, 24, 20);

    /// Η τελευταία ζύγιση του δείγματος με άλλο «bmr», όπως θα ερχόταν από τη Samsung Health.
    BodyMeasurement last(Object? bmr) {
      final j = sampleDashboardJson(when);
      final body = [for (final b in j['body'] as List) Map<String, dynamic>.from(b as Map)];
      body.last['bmr'] = bmr;
      j['body'] = body;
      return Dashboard.fromJson(jsonDecode(jsonEncode(j)) as Map<String, dynamic>).body.last;
    }

    test('μέσα στα 500–5.000 kcal: μένει, στρογγυλεμένο', () {
      expect(last(1700).bmr, 1700);
      expect(last(1699.6).bmr, 1700);
      expect(last(500).bmr, 500);
      expect(last(5000).bmr, 5000);
    });

    test('0, πολύ μικρό, πολύ μεγάλο, κενό ή κείμενο: «δεν μετρήθηκε», όχι «0 kcal» και όχι σφάλμα', () {
      expect(last(0).bmr, isNull);
      expect(last(499).bmr, isNull);
      expect(last(5001).bmr, isNull);
      expect(last(-1700).bmr, isNull);
      expect(last(null).bmr, isNull);
      expect(last('1700').bmr, isNull);
    });

    test('η υπόλοιπη ζύγιση δεν χάνεται', () {
      final b = last(0);
      expect(b.weight, isNotNull);
      expect(b.fatPct, isNotNull);
      expect(b.smm, isNotNull);
    });
  });

  group('μ4: κείμενο στη μέτρηση μέσης (εγκρίθηκε 12/11)', () {
    test('λέει τι συστήνουν οι οδηγίες, όχι «ο κίνδυνος είναι υψηλός»', () {
      final page = File('lib/pages/waist_sheet.dart').readAsStringSync();
      expect(page, contains('οι οδηγίες συστήνουν μείωση βάρους (ESC 2021).'));
      expect(page, isNot(contains('ο κίνδυνος για την καρδιά είναι υψηλός')));
    });
  });

  group('μ5: ο υψηλότερος παλμός στα βάρη (εγκρίθηκε 12/11)', () {
    test('στα βάρη «~181», στο περπάτημα «134»', () {
      expect(hrMaxText(181, cardio: false), '~181');
      expect(hrMaxText(134, cardio: true), '134');
      expect(hrMaxApproxText, 'Υψηλότερος: στιγμιαία τιμή, κατά προσέγγιση.');
    });

    testWidgets('η κάρτα παλμών μιας προπόνησης με βάρη το γράφει', (tester) async {
      final t = sampleTraining(DateTime(2026, 11, 20, 18));
      final s = t.sessions.last
        ..hrAvg = 118
        ..hrMax = 181;
      expect(s.isCardio, isFalse);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: SingleChildScrollView(child: HrCard(session: s))),
      ));
      expect(find.text('~181'), findsOneWidget);
      expect(find.text('181'), findsNothing);
      expect(find.byKey(const ValueKey('hr-max-approx')), findsOneWidget);
      expect(find.text(hrMaxApproxText), findsOneWidget);
    });
  });
}
