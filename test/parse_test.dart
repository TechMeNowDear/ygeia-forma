import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/history.dart';

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

  test('Ανάγνωση εύρους: ίδιες γραμμές με το summarizeRange, σφάλματα χωρίς κρασάρισμα', () async {
    final when = DateTime(2026, 10, 24, 20);
    final j = sampleDashboardJson(when);
    final from = DateTime(2026, 10, 1), to = DateTime(2026, 10, 25);
    final p = await parseRange(jsonEncode(j), from, to);
    expect(p.ok, isTrue);
    expect(p.anyError, isFalse);
    expect(p.sleepFailed, isFalse);
    final direct = summarizeRange(Dashboard.fromJson(j), from, to);
    expect(p.rows.keys.toSet(), direct.keys.toSet());
    for (final k in direct.keys) {
      expect(p.rows[k], direct[k]);
    }
    final bad = parseRangeSync('όχι json', from, to);
    expect(bad.ok, isFalse);
    expect(bad.rows, isEmpty);
    expect(parseRangeSync(jsonEncode({'ok': false, 'kind': 'x'}), from, to).ok, isFalse);
    final heartErr = parseRangeSync(jsonEncode(sampleDashboardJson(when)..['heart'] = {'error': 'x'}), from, to);
    expect(heartErr.ok, isTrue);
    expect(heartErr.anyError, isTrue);
    expect(heartErr.sleepFailed, isTrue);
  });
}
