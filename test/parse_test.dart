import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';

import 'sample_data.dart';

/// Η απάντηση της Samsung διαβάζεται σε άλλο νήμα· ίδιο αποτέλεσμα με πριν, και τα σφάλματα περνούν.
void main() {
  test('Κανονική απάντηση: ίδια δεδομένα με την ανάγνωση στο κύριο νήμα', () async {
    final when = DateTime(2026, 10, 24, 20);
    final j = sampleDashboardJson(when);
    final p = await parseDashboard(jsonEncode(j));
    expect(p.status['ok'], isTrue);
    final direct = Dashboard.fromJson(j);
    expect(p.data!.nights.length, direct.nights.length);
    expect(p.data!.steps.length, direct.steps.length);
    expect(p.sleepFailed, isFalse);
  });

  test('Σφάλμα της Samsung: κρατά kind και message, χωρίς δεδομένα', () {
    final p = parseDashboardSync(jsonEncode({'ok': false, 'kind': 'no_permission', 'message': 'x', 'code': 3}));
    expect(p.data, isNull);
    expect(p.status['kind'], 'no_permission');
    expect(p.status['code'], 3);
  });

  test('Χαλασμένη απάντηση: σφάλμα, όχι κρασάρισμα', () {
    expect(parseDashboardSync('όχι json').data, isNull);
    expect(parseDashboardSync('[]').data, isNull);
  });

  test('Σφάλμα σε παλμούς: τα υπόλοιπα διαβάζονται, ο ύπνος σημειώνεται ότι δεν είναι πλήρης', () {
    final when = DateTime(2026, 10, 24, 20);
    final j = sampleDashboardJson(when)..['heart'] = {'error': 'x'};
    final p = parseDashboardSync(jsonEncode(j));
    expect(p.data, isNotNull);
    expect(p.sleepFailed, isTrue);
    expect(p.data!.failed, contains('heart'));
  });
}
