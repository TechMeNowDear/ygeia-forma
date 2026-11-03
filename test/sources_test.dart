// Πηγές: μία πηγή ανά μέτρηση, ποτέ ανάμειξη (απόφαση 2/11, «πάρα πολύ σημαντικό»).
//
// Η ιδέα των ελέγχων: το ιστορικό έχει ΚΑΙ τιμές ρολογιού ΚΑΙ τιμές Oura τις ίδιες μέρες, με πολύ διαφορετικά
// νούμερα (ρολόι 300–399, Oura 700–799). Αν κάποιος υπολογισμός (σύνοψη, Τάσεις, εβδομάδα, «Εκτός συνηθισμένου»,
// αναφορά γιατρού) πάρει έστω μία τιμή από τη λάθος πηγή, το αποτέλεσμα βγαίνει έξω από το εύρος της σωστής
// πηγής και ο έλεγχος αποτυγχάνει.
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/oura/oura_view.dart';
import 'package:ygeia_forma/report.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/trends.dart';
import 'package:ygeia_forma/unusual.dart';
import 'package:ygeia_forma/weekly.dart';

import 'sample_data.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);
DateTime add(DateTime x, int n) => DateTime(x.year, x.month, x.day + n);

final ouraFrom = d(2026, 11, 6);
final plan = SourcePlan.samsungOnly.withEra(Source.oura, ouraFrom);

bool isWatch(double v) => v >= 300 && v < 400;
bool isOura(double v) => v >= 700 && v < 800;

/// Ιστορικό με δύο πηγές ΤΙΣ ΙΔΙΕΣ μέρες (όπως θα ήταν αν κάποιος κώδικας έγραφε και τις δύο).
Map<String, Map<String, double>> dualHistory(DateTime from, DateTime to) {
  final h = <String, Map<String, double>>{};
  var i = 0;
  for (var x = from; !x.isAfter(to); x = add(x, 1), i++) {
    final w = 300.0 + (i * 7) % 99;
    final o = 700.0 + (i * 11) % 99;
    h[dateKey(x)] = {
      for (final k in ouraKeys.keys)
        if (SourcePlan.storageKey(k, Source.watch) != null) k: w,
      for (final e in ouraKeys.entries) e.value: o,
      K.spo2Avg: w,
      K.spo2Min: w,
      K.steps: w,
      K.weight: w,
    };
  }
  return h;
}

void main() {
  // ---------------------------------------------------------------------------
  group('Ο πίνακας πηγών', () {
    test('Κάθε μέτρηση σε μία μόνο γραμμή, και κάθε μέτρηση των Τάσεων/αναφοράς έχει πηγή', () {
      final seen = <String>{};
      for (final r in sourceRows) {
        for (final m in r.metrics) {
          expect(seen.add(m), isTrue, reason: 'η $m είναι σε δύο γραμμές');
        }
      }
      for (final m in [...trendMetrics, ...ouraTrendMetrics]) {
        expect(metricGroups.containsKey(m.key), isTrue, reason: m.key);
      }
      for (final k in reportKeysFor(plan)) {
        expect(metricGroups.containsKey(k), isTrue, reason: k);
      }
    });

    test('Οι πηγές που αποφάσισε ο χρήστης', () {
      final day = add(ouraFrom, 1);
      for (final k in [K.sleepMin, K.bedtime, K.wake, K.deepPct, K.remPct, K.awakeMin, K.sleepHr, K.lowHr, K.hrv, K.breath, K.skinTemp, K.sleepScore, K.energy]) {
        expect(plan.sourceFor(k, day), Source.oura, reason: k);
      }
      for (final k in [K.spo2Avg, K.spo2Min, K.spo2Low, K.steps, K.floors, K.calories, K.activeMin, K.dayHr]) {
        expect(plan.sourceFor(k, day), Source.watch, reason: k);
      }
      for (final k in [K.weight, K.fatPct, K.smm]) {
        expect(plan.sourceFor(k, day), Source.scale, reason: k);
      }
    });

    test('Ένα κλειδί ανά μέρα: του ρολογιού πριν, του Oura από τη σύνδεση και μετά', () {
      expect(plan.keyFor(K.sleepMin, add(ouraFrom, -1)), K.sleepMin);
      expect(plan.keyFor(K.sleepMin, ouraFrom), 'o.sleepMin');
      expect(plan.keyFor(K.energy, add(ouraFrom, -1)), K.energy);
      expect(plan.keyFor(K.energy, ouraFrom), 'o.readiness');
      expect(plan.keyFor(K.hrv, add(ouraFrom, -1)), isNull, reason: 'το ρολόι δεν δίνει HRV: κενό, όχι εναλλακτική');
      expect(plan.keyFor(K.spo2Min, ouraFrom), K.spo2Min, reason: 'οξυγόνο πάντα του ρολογιού');
      expect(plan.keyFor(K.steps, ouraFrom), K.steps);
      // Κανένα κλειδί του Oura δεν είναι ίδιο με κλειδί του ρολογιού.
      for (final k in ouraKeySet) {
        expect(metricGroups.containsKey(k), isFalse, reason: k);
      }
    });

    test('Εποχές: αποσύνδεση → καμία πηγή (όχι πίσω στο ρολόι)· ρητή επιλογή → ρολόι', () {
      final off = plan.withEra(Source.none, d(2026, 12, 1));
      expect(off.nightSource(d(2026, 11, 30)), Source.oura);
      expect(off.nightSource(d(2026, 12, 1)), Source.none);
      expect(off.keyFor(K.sleepMin, d(2026, 12, 2)), isNull);
      expect(off.keyFor(K.spo2Avg, d(2026, 12, 2)), K.spo2Avg);
      final watch = off.withEra(Source.watch, d(2026, 12, 10));
      expect(watch.nightSource(d(2026, 12, 9)), Source.none);
      expect(watch.nightSource(d(2026, 12, 10)), Source.watch);
      // Αλλαγή πηγής = όπου αρχίζει άλλη συσκευή που ΔΙΝΕΙ τη μέτρηση· το κενό («καμία») δεν είναι αλλαγή.
      expect(watch.changeDates(K.sleepMin), [ouraFrom, d(2026, 12, 10)]);
      expect(watch.changeDates(K.steps), isEmpty);
      // HRV/αναπνοές/χαμηλότεροι παλμοί: μόνο Oura → ποτέ «αλλαγή πηγής».
      expect(watch.changeDates(K.hrv), isEmpty);
      expect(plan.changeDates(K.breath), isEmpty);
    });

    test('A5: κάθε νέα εποχή Oura είναι αλλαγή (Oura → καμία → Oura), και για τις μετρήσεις μόνο του Oura', () {
      final again = plan.withEra(Source.none, d(2026, 12, 1)).withEra(Source.oura, d(2027, 1, 5));
      expect(again.changeDates(K.sleepMin), [ouraFrom, d(2027, 1, 5)]);
      for (final k in [K.hrv, K.lowHr, K.breath, K.napMin]) {
        // Η πρώτη σύνδεση δεν είναι αλλαγή (απλώς αρχίζουν τιμές)· η δεύτερη εποχή είναι.
        expect(again.changeDates(k), [d(2027, 1, 5)], reason: k);
      }
      // Oura → ρολόι → Oura: και για το HRV (το ρολόι δεν δίνει τιμή, αλλά η νέα εποχή Oura είναι νέα αρχή).
      final viaWatch = plan.withEra(Source.watch, d(2026, 12, 1)).withEra(Source.oura, d(2027, 1, 5));
      expect(viaWatch.changeDates(K.hrv), [d(2027, 1, 5)]);
      expect(viaWatch.changeDates(K.sleepMin), [ouraFrom, d(2026, 12, 1), d(2027, 1, 5)]);
      // Συνηθισμένο του HRV στη 2η εποχή: μόνο νύχτες της 2ης εποχής.
      final h = dualHistory(d(2026, 6, 1), d(2027, 2, 10));
      final b = ouraBaseline(h, again, K.hrv, d(2027, 1, 20))!;
      expect(b.count, lessThanOrEqualTo(daysBetween(d(2027, 1, 5), d(2027, 1, 20))));
      final def = ouraTrendMetrics.firstWhere((m) => m.key == K.hrv);
      final r = computeTrend(def, h, d(2027, 1, 20), TrendPeriod.month, plan: again);
      expect(r.status, TrendStatus.sourceChange);
      expect(r.points.every((p) => !p.$1.isBefore(d(2027, 1, 5))), isTrue);
    });

    test('A4: οξυγόνο νύχτας και παλμοί μέρας κόβονται στη σύνδεση (ίδιο ρολόι, άλλος ορισμός)', () {
      for (final k in definitionMetrics) {
        expect(plan.changeDates(k), [ouraFrom], reason: k);
        expect(plan.sourceFor(k, add(ouraFrom, 3)), Source.watch, reason: 'η τιμή μένει του ρολογιού');
      }
      final back = plan.withEra(Source.none, d(2026, 12, 1)).withEra(Source.watch, d(2026, 12, 10));
      expect(back.changeDates(K.spo2Avg), [ouraFrom, d(2026, 12, 10)]);
      expect(SourcePlan.samsungOnly.changeDates(K.spo2Avg), isEmpty);
      expect(plan.changeDates(K.steps), isEmpty, reason: 'τα βήματα δεν αλλάζουν ορισμό');
      // Τάση οξυγόνου που περνά πάνω από τη σύνδεση: δεν συγκρίνεται.
      final h = dualHistory(d(2026, 6, 1), add(ouraFrom, 20));
      final def = trendMetrics.firstWhere((m) => m.key == K.spo2Avg);
      final r = computeTrend(def, h, add(ouraFrom, 10), TrendPeriod.month, plan: plan);
      expect(r.status, TrendStatus.sourceChange);
      expect(r.changedOn, ouraFrom);
      // Αναφορά: μόνο οι μέρες από τη σύνδεση.
      final rep = buildReport(h, add(ouraFrom, 20), plan: plan);
      expect(rep.stats[K.spo2Avg]!.since, ouraFrom);
      expect(rep.stats[K.spo2Avg]!.values.every((v) => !v.$1.isBefore(ouraFrom)), isTrue);
    });

    test('Αποθήκευση και ανάγνωση του σχεδίου', () {
      final p = plan.withEra(Source.none, d(2026, 12, 1)).withEra(Source.watch, d(2026, 12, 10));
      expect(SourcePlan.fromJson(p.toJson()), p);
      expect(SourcePlan.fromJson('χαλασμένο'), SourcePlan.samsungOnly);
      expect(SourcePlan.fromJson([{'src': 'x', 'from': '2026-01-01'}]), SourcePlan.samsungOnly);
    });

    test('Ύπνος ρολογιού: μόνο για τις 14 νύχτες της σύγκρισης και μόνο όσο είναι ανοιχτή', () {
      final last = add(ouraFrom, compareDays - 1);
      expect(plan.compareUntil, last);
      expect(plan.watchSleepAllowed(add(ouraFrom, -1), add(ouraFrom, 30)), isTrue, reason: 'νύχτα του ρολογιού');
      expect(plan.watchSleepAllowed(ouraFrom, ouraFrom), isTrue);
      expect(plan.watchSleepAllowed(last, last), isTrue);
      expect(plan.watchSleepAllowed(add(last, 1), add(last, 1)), isFalse);
      expect(plan.watchSleepAllowed(ouraFrom, add(last, 1)), isFalse, reason: 'η σύγκριση έκλεισε');
      // Το όριο της Samsung: όσο η σύγκριση είναι ανοιχτή, η τελευταία της νύχτα· μετά, η τελευταία του ρολογιού
      // (ώστε η ανάγνωση των 30 ημερών να μη φέρνει ξανά ύπνο ρολογιού για νύχτες του Oura).
      expect(plan.watchSleepCutoff(add(ouraFrom, 3)), last);
      expect(plan.watchSleepCutoff(add(last, 1)), add(ouraFrom, -1));
      expect(SourcePlan.samsungOnly.watchSleepCutoff(ouraFrom), isNull);
      // Αποσύνδεση την 3η μέρα: η σύγκριση κλείνει αμέσως και ο ύπνος του ρολογιού δεν διαβάζεται για το Oura.
      final off = plan.withEra(Source.none, add(ouraFrom, 3));
      expect(off.compareActive(add(ouraFrom, 3)), isFalse);
      expect(off.watchSleepCutoff(add(ouraFrom, 3)), add(ouraFrom, -1));
      expect(off.watchSleepAllowed(add(ouraFrom, 1), add(ouraFrom, 3)), isFalse);
      // Ρητά ξανά στο ρολόι: χωρίς όριο.
      expect(off.withEra(Source.watch, add(ouraFrom, 5)).watchSleepCutoff(add(ouraFrom, 6)), isNull);
    });

    test('«Σύγκριση πηγών»: ακριβώς 14 νύχτες· εξαφανίζεται μετά, και μετά από αποσύνδεση ή «ξανά ρολόι»', () {
      expect(plan.compareActive(add(ouraFrom, -1)), isFalse);
      expect(plan.compareActive(ouraFrom), isTrue);
      expect(plan.compareActive(add(ouraFrom, 13)), isTrue);
      expect(plan.compareActive(add(ouraFrom, 14)), isFalse);
      expect(SourcePlan.samsungOnly.compareActive(ouraFrom), isFalse);
      final off = plan.withEra(Source.none, add(ouraFrom, 4));
      expect(off.compareActive(add(ouraFrom, 5)), isFalse);
      expect(off.withEra(Source.watch, add(ouraFrom, 6)).compareActive(add(ouraFrom, 7)), isFalse);
    });

    test('Τάσεις για μετρήσεις μόνο του Oura: «Λίγα δεδομένα», ποτέ «Αλλαγή πηγής»', () {
      final h = dualHistory(d(2026, 6, 1), add(ouraFrom, 20));
      for (final key in [K.hrv, K.lowHr, K.breath]) {
        final def = ouraTrendMetrics.firstWhere((m) => m.key == key);
        final r = computeTrend(def, h, add(ouraFrom, 10), TrendPeriod.month, plan: plan);
        expect(r.status, TrendStatus.insufficient, reason: key);
        expect(r.points.every((p) => !p.$1.isBefore(ouraFrom)), isTrue);
      }
    });

    test('Η οθόνη «Πηγές» βγαίνει από τον ίδιο πίνακα: τίτλοι και πηγές', () {
      // Κάθε γραμμή της οθόνης παίρνει την πηγή της πρώτης της μέτρησης· όλες οι μετρήσεις μιας γραμμής έχουν
      // την ίδια πηγή κάθε μέρα (αλλιώς η οθόνη θα έλεγε κάτι άλλο από τον κώδικα).
      for (final day in [add(ouraFrom, -1), ouraFrom]) {
        for (final r in sourceRows) {
          final s = plan.sourceFor(r.metrics.first, day);
          for (final m in r.metrics) {
            expect(plan.sourceFor(m, day), s, reason: '${r.title} · $m');
          }
        }
      }
    });
  });

  // ---------------------------------------------------------------------------
  group('Καμία ανάμειξη: κάθε υπολογισμός παίρνει μόνο από την πηγή κάθε μέρας', () {
    final today = d(2027, 1, 20);
    final history = dualHistory(d(2026, 6, 1), today);

    test('SourcePlan.value: ρολόι πριν, Oura μετά, ποτέ το άλλο', () {
      for (var x = d(2026, 10, 1); !x.isAfter(today); x = add(x, 1)) {
        final v = plan.value(history, K.sleepMin, x)!;
        expect(x.isBefore(ouraFrom) ? isWatch(v) : isOura(v), isTrue, reason: dateKey(x));
        expect(isWatch(plan.value(history, K.steps, x)!), isTrue);
        expect(isWatch(plan.value(history, K.spo2Min, x)!), isTrue);
      }
    });

    test('Τάσεις: κάθε σύγκριση έχει τιμές από μία πηγή, ή «αλλαγή πηγής»', () {
      for (var x = d(2026, 10, 20); !x.isAfter(today); x = add(x, 3)) {
        for (final period in TrendPeriod.values) {
          for (final r in computeAllTrends(history, x, period, plan: plan)) {
            final vals = [for (final p in r.points) p.$2];
            final allWatch = vals.every(isWatch);
            final allOura = vals.every(isOura);
            expect(allWatch || allOura, isTrue, reason: '${r.def.key} ${dateKey(x)} $period: δύο πηγές στο ίδιο γράφημα');
            for (final v in [r.current, r.previous].whereType<double>()) {
              expect(allWatch ? isWatch(v) : isOura(v), isTrue, reason: '${r.def.key} ${dateKey(x)} $period');
            }
            final change = plan.changeWithin(r.def.key, r.previousFrom.isBefore(r.currentFrom) ? r.previousFrom : r.currentFrom, r.end);
            if (change != null) {
              expect(r.status, TrendStatus.sourceChange, reason: '${r.def.key} ${dateKey(x)} $period');
              expect(r.previous, isNull);
              expect(r.points.every((p) => !p.$1.isBefore(change)), isTrue);
            } else {
              expect(r.status, isNot(TrendStatus.sourceChange));
            }
          }
        }
      }
    });

    test('Τάσεις, όριο: 30 μέρες μετά τη σύνδεση η σύγκριση μήνα «πιάνει» την αλλαγή, στις 60 όχι πια', () {
      final def = trendMetrics.firstWhere((m) => m.key == K.sleepMin);
      // Σήμερα = σύνδεση + 59: τρέχον [σύνδεση+30, σύνδεση+59], προηγούμενο [σύνδεση, σύνδεση+29] → καθαρή σύγκριση.
      final clean = computeTrend(def, history, add(ouraFrom, 59), TrendPeriod.month, plan: plan);
      expect(clean.status, isNot(TrendStatus.sourceChange));
      expect(clean.previousFrom, ouraFrom);
      // Μία μέρα νωρίτερα, το προηγούμενο ξεκινά πριν από τη σύνδεση → αλλαγή πηγής.
      final straddle = computeTrend(def, history, add(ouraFrom, 58), TrendPeriod.month, plan: plan);
      expect(straddle.status, TrendStatus.sourceChange);
      expect(straddle.changedOn, ouraFrom);
      // Τα βήματα δεν αλλάζουν πηγή: συγκρίνονται κανονικά πάνω από τη μέρα της σύνδεσης.
      final steps = computeTrend(trendMetrics.firstWhere((m) => m.key == K.steps), history, add(ouraFrom, 10), TrendPeriod.month, plan: plan);
      expect(steps.status, isNot(TrendStatus.sourceChange));
    });

    test('Εβδομάδα: κάθε γραμμή από μία πηγή· η «καλύτερη βαθμολογία» ποτέ από εβδομάδα με δύο πηγές', () {
      for (var sunday = d(2026, 10, 25); !sunday.isAfter(today); sunday = add(sunday, 7)) {
        final w = buildWeekReview(history, sunday, add(sunday, 1), plan: plan);
        for (final r in w.items) {
          final vals = [for (final p in r.points) p.$2];
          expect(vals.every(isWatch) || vals.every(isOura), isTrue, reason: '${r.def.key} ${dateKey(sunday)}');
        }
        final monday = add(sunday, -6);
        final mixed = plan.changeWithin(K.sleepScore, monday, sunday) != null;
        if (mixed) {
          expect(w.bestNight, isNull, reason: 'εβδομάδα ${dateKey(sunday)} με δύο πηγές βαθμολογίας');
        } else if (w.bestNightScore != null) {
          expect(sunday.isBefore(ouraFrom) ? isWatch(w.bestNightScore!) : isOura(w.bestNightScore!), isTrue);
        }
        if (w.mostStepsValue != null) expect(isWatch(w.mostStepsValue!), isTrue);
      }
    });

    test('«Εκτός συνηθισμένου»: τιμή και συνηθισμένο από την ίδια πηγή· μετά την αλλαγή ξαναμαθαίνει', () {
      for (var x = d(2026, 10, 1); !x.isAfter(today); x = add(x, 1)) {
        final r = checkUnusual(history, x, plan: plan);
        for (final s in r.signals) {
          final oura = !x.isBefore(ouraFrom) && metricGroups[s.rule.key] == SourceGroup.night;
          expect(s.source, oura ? Source.oura : Source.watch, reason: 'η κάρτα λέει την πηγή');
          expect(oura ? isOura(s.value) : isWatch(s.value), isTrue, reason: '${s.rule.key} ${dateKey(x)}');
          expect(oura ? isOura(s.usual) : isWatch(s.usual), isTrue, reason: '${s.rule.key} ${dateKey(x)} συνηθισμένο');
        }
        // Τις πρώτες 13 μέρες μετά τη σύνδεση: λιγότερες από 14 νύχτες Oura → κανένας δείκτης νύχτας.
        if (!x.isBefore(ouraFrom) && x.isBefore(add(ouraFrom, unusualMinBaseline))) {
          expect(r.signals.where((s) => metricGroups[s.rule.key] == SourceGroup.night), isEmpty, reason: dateKey(x));
        }
        if (!x.isBefore(add(ouraFrom, unusualMinBaseline))) {
          expect(r.signals.where((s) => s.rule.key == K.sleepHr).single.baselineCount, greaterThanOrEqualTo(unusualMinBaseline));
        }
      }
    });

    test('Αναφορά γιατρού: κάθε δείκτης μία πηγή, που λέγεται ρητά· τιμές μόνο από τη νέα πηγή', () {
      for (final now in [add(ouraFrom, 5), add(ouraFrom, 40), add(ouraFrom, 120)]) {
        final r = buildReport(history, now, plan: plan);
        for (final e in r.stats.entries) {
          final vals = [for (final v in e.value.values) v.$2];
          expect(vals.every(isWatch) || vals.every(isOura), isTrue, reason: '${e.key} ${dateKey(now)}');
          final expected = plan.sourceFor(e.key, now);
          expect(e.value.source, expected, reason: e.key);
          if (expected == Source.oura) {
            expect(vals.every(isOura), isTrue, reason: e.key);
            final from = add(dayOf(now), -(reportDays - 1));
            // Μετρήσεις μόνο του Oura δεν είχαν άλλη πηγή πριν: χωρίς «από …».
            final expectSince = from.isBefore(ouraFrom) && !ouraOnlyMetrics.contains(e.key) ? ouraFrom : null;
            expect(e.value.since, expectSince, reason: e.key);
          }
        }
        for (final w in r.weighIns) {
          expect(isWatch(w.$2!), isTrue);
        }
      }
    });

    test('Συνηθισμένο του Oura (Σήμερα, Ύπνος): μόνο νύχτες Oura', () {
      for (var x = ouraFrom; !x.isAfter(add(ouraFrom, 30)); x = add(x, 1)) {
        final b = ouraBaseline(history, plan, K.hrv, x)!;
        expect(isOura(b.value), isTrue);
        if (b.usual != null) expect(isOura(b.usual!), isTrue);
        expect(b.count, lessThanOrEqualTo(daysBetween(ouraFrom, x)));
      }
      expect(ouraBaseline(history, plan, K.hrv, add(ouraFrom, -1)), isNull, reason: 'πριν από τη σύνδεση δεν υπάρχει');
    });

    test('planSeries: το γράφημα κόβεται στην αλλαγή πηγής', () {
      final s = planSeries(history, plan, K.sleepHr, add(ouraFrom, -20), add(ouraFrom, 9));
      expect(s.cut, ouraFrom);
      expect(s.points.length, 10);
      expect(s.points.every((p) => isOura(p.$2)), isTrue);
      final steps = planSeries(history, plan, K.steps, add(ouraFrom, -20), add(ouraFrom, 9));
      expect(steps.cut, isNull);
      expect(steps.points.length, 30);
    });
  });

  // ---------------------------------------------------------------------------
  group('Αποθήκευση: οι τιμές νύχτας του ρολογιού δεν γράφονται ποτέ για νύχτες του Oura', () {
    test('mergeHistory: μέρα Oura → μόνο οξυγόνο/βήματα του ρολογιού, οι παλιές τιμές νύχτας φεύγουν', () {
      final h = <String, Map<String, double>>{
        '2026-11-07': {K.sleepMin: 350, K.sleepHr: 60, K.energy: 70, 'o.sleepMin': 420, K.steps: 1000},
      };
      final changed = mergeHistory(
        h,
        {
          '2026-11-05': {K.sleepMin: 380, K.spo2Avg: 95, K.steps: 7000},
          '2026-11-07': {K.sleepMin: 355, K.sleepHr: 61, K.energy: 71, K.skinTemp: 34, K.spo2Avg: 94, K.spo2Min: 88, K.steps: 8000},
        },
        sleepFrom: d(2026, 11, 1),
        plan: plan,
      );
      expect(changed, containsAll(['2026-11-05', '2026-11-07']));
      expect(h['2026-11-05']![K.sleepMin], 380, reason: 'πριν από τη σύνδεση: όπως πάντα');
      expect(h['2026-11-07'], {'o.sleepMin': 420, K.steps: 8000, K.spo2Avg: 94, K.spo2Min: 88});
    });

    test('mergeHistory: η πρώτη νύχτα του Oura κρατά τη νύχτα του ρολογιού που υπήρχε (κρυφή), χωρίς νέες τιμές', () {
      final h = <String, Map<String, double>>{
        '2026-11-06': {K.sleepMin: 350, K.sleepHr: 60, K.energy: 70, 'o.sleepMin': 420, K.steps: 1000},
      };
      mergeHistory(
        h,
        {
          '2026-11-06': {K.sleepMin: 355, K.sleepHr: 61, K.energy: 71, K.skinTemp: 34, K.spo2Avg: 94, K.steps: 8000},
        },
        sleepFrom: d(2026, 11, 1),
        plan: plan,
      );
      expect(h['2026-11-06'], {K.sleepMin: 350, K.sleepHr: 60, K.energy: 70, 'o.sleepMin': 420, K.steps: 8000, K.spo2Avg: 94});
      // Οι οθόνες διαβάζουν μόνο το Oura εκείνη τη μέρα.
      expect(plan.value(h, K.sleepMin, d(2026, 11, 6)), 420);
      // Ούτε ο ξαναϋπολογισμός τη σβήνει.
      mergeHistory(h, {'2026-11-06': {K.spo2Avg: 95}},
          replaceSleep: true, rangeFrom: d(2026, 11, 1), rangeTo: d(2026, 11, 10), plan: plan);
      expect(h['2026-11-06']![K.sleepMin], 350);
    });

    test('Ξαναϋπολογισμός ιστορικού (replaceSleep) πάνω από τη σύνδεση: το Oura μένει, το ρολόι δεν μπαίνει', () {
      final h = <String, Map<String, double>>{
        '2026-11-04': {K.sleepMin: 300},
        '2026-11-07': {'o.sleepMin': 430, 'o.hrv': 40},
      };
      mergeHistory(
        h,
        {
          '2026-11-04': {K.sleepMin: 310},
          '2026-11-07': {K.sleepMin: 200, K.spo2Avg: 95},
        },
        replaceSleep: true,
        rangeFrom: d(2026, 11, 1),
        rangeTo: d(2026, 11, 10),
        plan: plan,
      );
      expect(h['2026-11-04']![K.sleepMin], 310);
      expect(h['2026-11-07'], {'o.sleepMin': 430, 'o.hrv': 40, K.spo2Avg: 95});
    });

    test('stripForeignWatchNight: οι μέρες του Oura χάνουν τις τιμές του ρολογιού· η πρώτη νύχτα της εποχής μένει', () {
      final h = <String, Map<String, double>>{
        '2026-11-05': {K.sleepMin: 300, K.steps: 1},
        '2026-11-06': {K.sleepMin: 300, K.energy: 50, K.spo2Avg: 95, K.steps: 2},
        '2026-11-07': {K.sleepMin: 310, K.energy: 51, K.spo2Avg: 96, K.steps: 3},
      };
      final c = stripForeignWatchNight(h, plan, from: ouraFrom);
      expect(c, {'2026-11-07'});
      expect(h['2026-11-05']![K.sleepMin], 300);
      expect(h['2026-11-06']![K.sleepMin], 300, reason: 'ποτέ δεν σβήνεται');
      expect(h['2026-11-07'], {K.spo2Avg: 96, K.steps: 3});
    });

    test('summarizeDay με Oura: καμία τιμή νύχτας από το ρολόι, οξυγόνο ναι (χωρίς τον ύπνο του ρολογιού)', () {
      final now = DateTime(2026, 11, 8, 16, 30);
      final dash = Dashboard.fromJson(sampleDashboardJson(now));
      final p = SourcePlan.samsungOnly.withEra(Source.oura, d(2026, 11, 6));
      final before = summarizeDay(dash, d(2026, 11, 5), plan: p);
      expect(before.containsKey(K.sleepMin), isTrue);
      expect(before.containsKey(K.energy), isTrue);
      for (final day in [d(2026, 11, 6), d(2026, 11, 7), d(2026, 11, 8)]) {
        final row = summarizeDay(dash, day, plan: p);
        for (final k in watchNightKeys) {
          expect(row.containsKey(k), isFalse, reason: '$k ${dateKey(day)}');
        }
        expect(row.containsKey(K.spo2Avg), isTrue, reason: 'οξυγόνο ρολογιού ${dateKey(day)}');
        expect(row.keys.any((k) => k.startsWith('o.')), isFalse);
      }
      // Παλμοί μέρας: χωρίς τις ώρες ύπνου του Oura δεν βγαίνουν (αλλιώς ο ύπνος θα μετρούσε ως μέρα).
      expect(summarizeDay(dash, d(2026, 11, 7), plan: p).containsKey(K.dayHr), isFalse);
    });

    test('Παλμοί μέρας με το σχέδιο της ΙΔΙΑΣ μέρας: σύνδεση και αποσύνδεση την ίδια μέρα δεν μετρά τον ύπνο ως μέρα', () {
      final now = DateTime(2026, 11, 8, 16, 30);
      final dash = Dashboard.fromJson(sampleDashboardJson(now));
      final day = d(2026, 11, 6);
      expect(summarizeDay(dash, day).containsKey(K.dayHr), isTrue, reason: 'με το ρολόι: όπως πάντα');
      // [καμία από 6/11] (χωρίς εποχή Oura): ο ύπνος του ρολογιού δεν διαβάζεται από τη Samsung → δεν ξέρουμε τον ύπνο.
      final none = SourcePlan([SourceEra(Source.none, day)]);
      expect(none.hasOura, isFalse);
      expect(summarizeDay(dash, day, plan: none).containsKey(K.dayHr), isFalse);
      expect(summarizeDay(dash, add(day, -1), plan: none).containsKey(K.dayHr), isFalse, reason: 'η νύχτα του βραδιού είναι χωρίς πηγή');
      expect(summarizeDay(dash, add(day, -2), plan: none).containsKey(K.dayHr), isTrue, reason: 'και οι δύο νύχτες του ρολογιού');
    });

    test('Dashboard.restrict: για τις οθόνες, μόνο νύχτες της τρέχουσας εποχής ρολογιού· σύγκριση μόνο όσο είναι ανοιχτή', () {
      final now = DateTime(2026, 11, 8, 16, 30);
      final dash = Dashboard.fromJson(sampleDashboardJson(now));
      final p = SourcePlan.samsungOnly.withEra(Source.oura, d(2026, 11, 6));
      final r = dash.restrict(p);
      expect(r.nights, isEmpty, reason: 'ο ύπνος είναι του Oura: καμία νύχτα ρολογιού στις οθόνες');
      expect(r.energy, isEmpty, reason: 'το Energy Score δεν φαίνεται μετά τη σύνδεση');
      expect(r.compareNights.map((n) => dateKey(n.date)), containsAll(['2026-11-06', '2026-11-07', '2026-11-08']));
      // Ξανά ρολόι από 5/11 μετά από Oura (20/10–4/11): φαίνονται μόνο νύχτες από 5/11, όχι από πριν το Oura.
      final again = SourcePlan([SourceEra(Source.oura, d(2026, 10, 20)), SourceEra(Source.watch, d(2026, 11, 5))]);
      final a = dash.restrict(again);
      expect(a.nights, isNotEmpty);
      expect(a.nights.every((n) => !n.date.isBefore(d(2026, 11, 5))), isTrue);
      expect(a.energy.every((e) => !e.day.isBefore(d(2026, 11, 5))), isTrue);
      expect(a.compareNights, isEmpty);
      // Χωρίς σχέδιο: ακριβώς τα ίδια δεδομένα.
      expect(identical(dash.restrict(SourcePlan.samsungOnly), dash), isTrue);
    });
  });

  group('Κενές νύχτες: λόγος, ποτέ ύπνος από το ρολόι', () {
    final n = DateTime(2026, 11, 8, 9);
    EmptyNight? reason({DateTime? now, bool tokens = true, String? error, DateTime? synced, SourcePlan? p}) => emptyNightReason(
          plan: p ?? plan,
          day: d(2026, 11, 8),
          now: now ?? n,
          night: null,
          hasTokens: tokens,
          error: error,
          synced: synced,
        );

    test('Πρωί πριν από τις 12 → περιμένει· μετά → δεν υπάρχει από το δαχτυλίδι', () {
      expect(reason(synced: DateTime(2026, 11, 8, 8, 50)), EmptyNight.waiting);
      expect(reason(now: DateTime(2026, 11, 8, 13), synced: DateTime(2026, 11, 8, 12, 59)), EmptyNight.noRing);
      expect(reason(now: DateTime(2026, 11, 8, 13), synced: DateTime(2026, 11, 7, 22)), EmptyNight.notRead);
    });

    test('Σύνδεση, συνδρομή, αποσύνδεση', () {
      expect(reason(tokens: false), EmptyNight.reconnect);
      expect(reason(error: 'reconnect'), EmptyNight.reconnect);
      expect(reason(error: 'subscription', synced: n), EmptyNight.subscription);
      expect(reason(p: plan.withEra(Source.none, d(2026, 11, 8))), EmptyNight.disconnected);
      expect(reason(p: SourcePlan.samsungOnly), isNull, reason: 'νύχτα του ρολογιού: δεν αφορά το Oura');
    });
  });
}
