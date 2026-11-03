// «Πριν από το Oura, ακριβώς όπως πριν»: τα αποτελέσματα του σημερινού κώδικα (χωρίς σχέδιο πηγών) πάνω στο
// δείγμα πρέπει να είναι ΙΔΙΑ με όσα έβγαζε ο κώδικας του dfc10c8 (πριν από το Oura) πάνω στο ίδιο δείγμα.
// Το test/fixtures/golden_dfc10c8.json φτιάχτηκε τρέχοντας τον ίδιο υπολογισμό στο dfc10c8 στο GitHub Actions
// (ώρα Αθήνας), 2/11/2026. Συνόψεις ημερών, Τάσεις (3 περίοδοι), αναφορά γιατρού, εβδομάδα, «Εκτός συνηθισμένου».
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/report.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/trends.dart';
import 'package:ygeia_forma/unusual.dart';
import 'package:ygeia_forma/weekly.dart';

import 'sample_data.dart';

Map<String, Object?> trendJson(TrendResult r) => {
      'key': r.def.key,
      'status': r.status.name,
      'current': r.current,
      'previous': r.previous,
      'nCurrent': r.nCurrent,
      'nPrevious': r.nPrevious,
      'points': r.points.length,
    };

/// Ίδια μορφή με το πρόγραμμα που έτρεξε στο dfc10c8, με το σχέδιο «μόνο Samsung» (όπως πριν από τη σύνδεση).
Map<String, Object?> current() {
  final plan = SourcePlan.samsungOnly;
  final out = <String, Object?>{};
  for (final now in [DateTime(2026, 10, 24, 16, 30), DateTime(2026, 10, 25, 19, 10)]) {
    final tag = now.toIso8601String();
    final d = Dashboard.fromJson(sampleDashboardJson(now)).restrict(plan);
    final today = DateTime(now.year, now.month, now.day);
    out['summary@$tag'] = summarizeRange(d, DateTime(today.year, today.month, today.day - 30), today, plan: plan);
    final h = sampleHistory(now, d);
    for (final p in TrendPeriod.values) {
      out['trends@$tag@${p.name}'] = [for (final r in computeAllTrends(h, today, p, plan: plan)) trendJson(r)];
    }
    final rep = buildReport(h, now, plan: plan);
    out['report@$tag'] = {
      for (final e in rep.stats.entries)
        e.key: {
          'n': e.value.n,
          'median': e.value.median,
          'p10': e.value.p10,
          'p90': e.value.p90,
          'low': e.value.low,
          'high': e.value.high,
          'trend': e.value.trend?.status.name,
        },
      'lowOxygen': rep.lowOxygenNights.length,
      'weighIns': rep.weighIns.length,
    };
    final w = buildWeekReview(h, DateTime(2026, 10, 25), now, plan: plan);
    out['week@$tag'] = {
      'items': [for (final r in w.items) trendJson(r)],
      'bestNight': w.bestNight?.toIso8601String(),
      'bestNightScore': w.bestNightScore,
      'mostSteps': w.mostSteps?.toIso8601String(),
      'mostStepsValue': w.mostStepsValue,
      'activeTotal': w.activeTotal,
      'activeDays': w.activeDays,
    };
    for (var i = 0; i < 10; i++) {
      final day = DateTime(today.year, today.month, today.day - i);
      final u = checkUnusual(h, day, plan: plan);
      out['unusual@$tag@$i'] = {
        'off': u.offCount,
        'prev': u.previousDayOff,
        'signals': [
          for (final s in u.signals) {'key': s.rule.key, 'value': s.value, 'usual': s.usual, 'threshold': s.threshold, 'n': s.baselineCount},
        ],
      };
    }
  }
  return out;
}

/// Κάθε τιμή που διαφέρει, ως «διαδρομή: παλιό → νέο» (για να γράφεται ρητά τι άλλαξε και γιατί).
void diffJson(Object? a, Object? b, String path, List<String> out) {
  if (a is Map && b is Map) {
    for (final k in {...a.keys, ...b.keys}) {
      diffJson(a[k], b[k], '$path/$k', out);
    }
  } else if (a is List && b is List && a.length == b.length) {
    for (var i = 0; i < a.length; i++) {
      diffJson(a[i], b[i], '$path[$i]', out);
    }
  } else if (jsonEncode(a) != jsonEncode(b)) {
    out.add('$path: ${jsonEncode(a)} → ${jsonEncode(b)}');
  }
}

void main() {
  test('Χωρίς Oura: ίδια αποτελέσματα με τον κώδικα πριν από το Oura (dfc10c8)', () {
    final golden = jsonDecode(File('test/fixtures/golden_dfc10c8.json').readAsStringSync()) as Map<String, dynamic>;
    // Μέσα από JSON και τα δύο, ώστε οι αριθμοί να συγκρίνονται με τον ίδιο τρόπο.
    final now = jsonDecode(jsonEncode(current())) as Map<String, dynamic>;
    final diffs = <String>[];
    diffJson(golden, now, '', diffs);
    if (diffs.isNotEmpty) {
      // ignore: avoid_print
      print('GOLDEN-DIFF ${diffs.length}\n${diffs.join('\n')}\nGOLDEN-END');
    }
    expect(now.keys.toSet(), golden.keys.toSet());
    for (final k in golden.keys) {
      expect(now[k], golden[k], reason: k);
    }
  });
}
