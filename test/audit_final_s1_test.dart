// Τελικός έλεγχος, Συμβούλιο 1 (ιατρικό): δοκιμές για όσα διορθώθηκαν στο κινητό. Φανταστικές τιμές (δημόσιο repo).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';

import 'sample_data.dart';

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
}
