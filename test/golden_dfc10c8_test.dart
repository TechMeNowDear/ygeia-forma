// «Πριν από το Oura, ακριβώς όπως πριν»: τα αποτελέσματα του σημερινού κώδικα (χωρίς σχέδιο πηγών) πάνω στο
// δείγμα πρέπει να είναι ΙΔΙΑ με όσα έβγαζε ο κώδικας του dfc10c8 (πριν από το Oura) πάνω στο ίδιο δείγμα.
// Το test/fixtures/golden_dfc10c8.json φτιάχτηκε τρέχοντας τον ίδιο υπολογισμό στο dfc10c8 στο GitHub Actions
// (ώρα Αθήνας), 2/11/2026. Συνόψεις ημερών, Τάσεις (3 περίοδοι), αναφορά γιατρού, εβδομάδα, «Εκτός συνηθισμένου».
// Ενημερώθηκε σκόπιμα 4/11/2026 (έλεγχος, Track A + Track B, συγχώνευση audit-final), μόνο με αυτές τις αλλαγές:
// Track A (ακεραιότητα δεδομένων):
// - sleepMin στις συνόψεις = πραγματικός ύπνος (ελαφρύς+βαθύς+REM από τις φάσεις, χωρίς τα ξυπνήματα και τα κενά·
//   το δείγμα έχει DURATION = διάστημα − 15′ και φάσεις με AWAKE, άρα κάθε νύχτα αλλάζει λίγα λεπτά). Γι' αυτό και
//   «Διάρκεια ύπνου · Μήνας» current 453,5 → 452,0, αναφορά sleepMin p90/low/high, εβδομάδα items[0] current/previous.
// - Οξυγόνο με στάθμιση διάρκειας (A4) στη σπασμένη νύχτα 25/10 (δύο εγγραφές διαφορετικής διάρκειας): spo2Avg
//   94,5 → 94,444, και «Οξυγόνο · Μήνας» current 94,75 → 94,722.
// - Οι ζυγίσεις του δείγματος έχουν πια το app id του InBody, οπότε το A2 δεν αλλάζει τίποτα· A5/A6 επίσης τίποτα.
// Track B (υπολογισμοί):
// - deepPct/remPct στις συνόψεις: ποσοστό του πραγματικού ύπνου (βαθύς+ελαφρύς+REM), όχι μαζί με τα ξυπνήματα.
//   Γι' αυτό και οι μεσαίες τιμές deepPct/remPct των Τάσεων, και «Βαθύς ύπνος · Μήνας» σταθερό → ↑ (οι 30 μέρες
//   του δείγματος με τον νέο ορισμό δίπλα στις συνθετικές παλιές τιμές του δείγματος).
// - Αναφορά, βήματα: 90 μέρες ως χθες (πριν 89), ίδιες με τη «Διαφορά» τους (n 88 → 89, μεσαία/p10/p90).
// - Τάσεις, «Θερμοκρασία καρπού · 3 μήνες»: σταθερό → ↑. Νέα εκτίμηση αυτοσυσχέτισης (κομμάτια 30 ημερών): το
//   δείγμα έχει πραγματικό άλμα επιπέδου (33,6 → ~35,2 °C) στις τελευταίες 30 μέρες, που πριν «κρυβόταν» ως
//   αυτοσυσχέτιση 0,8.
// Αλληλεπίδραση A × B: καμία. Το A αλλάζει μόνο sleepMin/spo2Avg, το B μόνο deepPct/remPct (από τα λεπτά των
// σταδίων, που δεν άλλαξαν), τα βήματα της αναφοράς και τα δύο status των Τάσεων. Με τη νέα αυτοσυσχέτιση του B
// τα status της διάρκειας ύπνου και του οξυγόνου (με τις τιμές του A) μένουν «σταθερό». Επιβεβαίωση: ο κώδικας της
// συγχώνευσης (audit-final) βγάζει ΑΚΡΙΒΩΣ το golden που προκύπτει αν εφαρμοστούν μαζί οι 70 αλλαγές του A και οι
// 140 του B πάνω στο αρχικό (CI run 41751975514, χωρίς καμία επιπλέον διαφορά).
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
