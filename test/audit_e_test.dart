// Έλεγχος 3 (4/11), κομμάτι E (δεδομένα, κανόνας νύχτας, ανθεκτικότητα): κάθε διόρθωση με έλεγχο που αποτυγχάνει
// χωρίς αυτήν.
// E1 νέος κανόνας νύχτας (κύρια ομάδα στο 22:00–08:00, ίδιος για ρολόι και Oura, κλείδωμα απόφασης με βήματα).
// E2 ζυγίσεις: ποτέ διαγραφή· φίλτρο εμφάνισης από την πρώτη ζύγιση InBody.
// E5 σημειώσεις οξυγόνου από όλες τις 30 νύχτες (πάνω από τη σύνδεση του Oura και την επανανάγνωση), με ημερομηνίες.
// E7 ξύπνιος του Oura χωρίς τον χρόνο ως τον ύπνο.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/oura/oura_model.dart';
import 'package:ygeia_forma/oxygen_note.dart';
import 'package:ygeia_forma/report.dart';
import 'package:ygeia_forma/sleep_gaps.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/ti_ftanei.dart';

int ms(DateTime t) => t.millisecondsSinceEpoch;
DateTime at(int month, int day, int h, [int m = 0]) => DateTime(2026, month, day, h, m);

/// Κομμάτι του ρολογιού με φάσεις (όλο ελαφρύς ύπνος): πραγματικός ύπνος = η διάρκεια.
Map<String, dynamic> rec(DateTime a, DateTime b) => {
      'start': ms(a),
      'end': ms(b),
      'minutes': b.difference(a).inMinutes,
      'stages': [
        ['LIGHT', ms(a), ms(b)],
      ],
    };

/// Η «day» της Oura: περίοδος που αρχίζει από τις 18:00 → η επόμενη μέρα, αλλιώς η μέρα που τελειώνει.
String ouraDay(DateTime a, DateTime b) => dateKey(a.hour >= 18 ? DateTime(a.year, a.month, a.day + 1) : dayOf(b));

typedef Piece = (DateTime, DateTime);

/// Βήματα του ρολογιού: [(λεπτό, βήματα)], γνωστά από [from] (null = κανένα βήμα ανά λεπτό, π.χ. παλιά νύχτα).
class Steps {
  const Steps(this.from, [this.counts = const []]);
  final DateTime? from;
  final List<(DateTime, int)> counts;
  static const unknown = Steps(null);

  Map<int, int> get byMinute => {for (final (t, n) in counts) ms(t) ~/ 60000: n};
  int? between(DateTime a, DateTime b) => gapSteps(a, b, stepsByMinute: byMinute, stepsFrom: from);
  Map<String, dynamic> json() => {
        if (from != null) 'stepsMin': [for (final (t, n) in counts) [ms(t), n]],
        if (from != null) 'stepsFrom': ms(from!),
      };
}

/// Ρολόι: νύχτες (λεπτά ανά ημερομηνία) και υπνάκοι.
({Map<String, int> nights, Map<String, int> naps, Dashboard d}) watch(List<Piece> pieces, Steps steps,
    {DateTime? readAt, Map<String, int> napLocks = const {}}) {
  final d = Dashboard.fromJson({
    'readAt': ms(readAt ?? pieces.last.$2.add(const Duration(hours: 6))),
    'sleep': [for (final p in pieces) rec(p.$1, p.$2)],
    ...steps.json(),
  }, napLocks: napLocks);
  return (
    nights: {for (final n in d.nights) dateKey(n.date): n.minutes},
    naps: {for (final e in d.naps.entries) dateKey(e.key): e.value},
    d: d,
  );
}

/// Oura: οι ίδιες περίοδοι, με τα βήματα του ΡΟΛΟΓΙΟΥ (E1.5).
({Map<String, int> nights, Map<String, int> naps, List<OuraNight> list}) oura(List<Piece> pieces, Steps steps,
    {Map<String, int> napLocks = const {}, bool withSteps = true}) {
  var i = 0;
  final list = parseOura(
    sleep: [
      for (final p in pieces)
        {
          'id': 'p${i++}',
          'day': ouraDay(p.$1, p.$2),
          'type': 'sleep',
          'bedtime_start': p.$1.toUtc().toIso8601String(),
          'bedtime_end': p.$2.toUtc().toIso8601String(),
          'total_sleep_duration': p.$2.difference(p.$1).inSeconds,
        },
    ],
    dailySleep: const [],
    readiness: const [],
    stepsBetween: withSteps ? steps.between : null,
    napLocks: napLocks,
  ).nights;
  return (
    nights: {for (final n in list) if (n.nightMinutes != null) dateKey(n.day): n.nightMinutes!},
    naps: {for (final n in list) if (n.napMinutes > 0) dateKey(n.day): n.napMinutes},
    list: list,
  );
}

void main() {
  group('E1: νέος κανόνας νύχτας, ίδιος για ρολόι και Oura (ίδια κομμάτια, ίδια βήματα)', () {
    final early = Steps(DateTime(2026, 10, 1));
    // (κομμάτια, βήματα, νύχτες, υπνάκοι)
    final cases = <String, (List<Piece>, Steps, Map<String, int>, Map<String, int>)>{
      'η νύχτα του χρήστη 2→3/11 (κενό 70′, 0 βήματα)': (
        [(at(11, 2, 23, 43), at(11, 3, 2, 40)), (at(11, 3, 3, 50), at(11, 3, 7, 8))],
        early,
        {'2026-11-03': 177 + 198},
        {},
      ),
      'η νύχτα του χρήστη 2→3/11 με 200 βήματα στο κενό (πριν από τις 06:00: τα βήματα δεν κρίνουν)': (
        [(at(11, 2, 23, 43), at(11, 3, 2, 40)), (at(11, 3, 3, 50), at(11, 3, 7, 8))],
        Steps(DateTime(2026, 10, 1), [(at(11, 3, 3, 10), 200)]),
        {'2026-11-03': 177 + 198},
        {},
      ),
      'η νύχτα του χρήστη 2→3/11 χωρίς βήματα ανά λεπτό': (
        [(at(11, 2, 23, 43), at(11, 3, 2, 40)), (at(11, 3, 3, 50), at(11, 3, 7, 8))],
        Steps.unknown,
        {'2026-11-03': 177 + 198},
        {},
      ),
      'Κυριακή 25/10: κενό 63′, 0 βήματα → μία νύχτα': (
        [(at(10, 25, 5, 55), at(10, 25, 9, 50)), (at(10, 25, 10, 53), at(10, 25, 12, 10))],
        early,
        {'2026-10-25': 235 + 77},
        {},
      ),
      'Κυριακή 25/10 χωρίς βήματα ανά λεπτό → μία νύχτα': (
        [(at(10, 25, 5, 55), at(10, 25, 9, 50)), (at(10, 25, 10, 53), at(10, 25, 12, 10))],
        Steps.unknown,
        {'2026-10-25': 235 + 77},
        {},
      ),
      '25/10 με 45 βήματα στο κενό → υπνάκος': (
        [(at(10, 25, 5, 55), at(10, 25, 9, 50)), (at(10, 25, 10, 53), at(10, 25, 12, 10))],
        Steps(DateTime(2026, 10, 1), [(at(10, 25, 10, 20), 45)]),
        {'2026-10-25': 235},
        {'2026-10-25': 77},
      ),
      'σχολείο: 23:30–06:30, 1200 βήματα, 08:00–09:30 → υπνάκος': (
        [(at(11, 2, 23, 30), at(11, 3, 6, 30)), (at(11, 3, 8, 0), at(11, 3, 9, 30))],
        Steps(DateTime(2026, 10, 1), [(at(11, 3, 7, 15), 1200)]),
        {'2026-11-03': 420},
        {'2026-11-03': 90},
      ),
      '01:00–05:00 και 10:30–16:00: κύρια η 01:00–05:00, η μεγαλύτερη μεσημεριανή είναι υπνάκος': (
        [(at(11, 2, 1, 0), at(11, 2, 5, 0)), (at(11, 2, 10, 30), at(11, 2, 16, 0))],
        early,
        {'2026-11-02': 240},
        {'2026-11-02': 330},
      ),
      '19:00–22:05 και 03:00–08:00: αρχή πριν από τις 20:00 → υπνάκος': (
        [(at(11, 2, 19, 0), at(11, 2, 22, 5)), (at(11, 3, 3, 0), at(11, 3, 8, 0))],
        Steps(DateTime(2026, 10, 1), [(at(11, 3, 0, 0), 1500)]),
        {'2026-11-03': 300},
        {'2026-11-03': 185},
      ),
      '20:30–21:50 και 22:00–06:00 (κενό 10′): μία νύχτα': (
        [(at(11, 2, 20, 30), at(11, 2, 21, 50)), (at(11, 2, 22, 0), at(11, 3, 6, 0))],
        early,
        {'2026-11-03': 80 + 480},
        {},
      ),
      // Ισοπαλία 150/150 στο 22:00–08:00 → κύρια η νωρίτερη· η μετά αρχίζει πριν από τις 06:00 με κενό 5 ώρες > 4 ώρες
      // → υπνάκος (κανόνας 3· έτσι ορίζεται, δεν «γεμίζει» νύχτα με 5 ώρες ξύπνιος στη μέση).
      '22:00–00:30 και 05:30–08:00 (κενό 5 ώρες) → νύχτα η πρώτη, υπνάκος η δεύτερη': (
        [(at(11, 1, 22, 0), at(11, 2, 0, 30)), (at(11, 2, 5, 30), at(11, 2, 8, 0))],
        early,
        {'2026-11-02': 150},
        {'2026-11-02': 150},
      ),
      'απογευματινός υπνάκος και δύο νύχτες': (
        [(at(11, 1, 23, 0), at(11, 2, 7, 0)), (at(11, 2, 15, 0), at(11, 2, 16, 0)), (at(11, 2, 23, 30), at(11, 3, 6, 45))],
        early,
        {'2026-11-02': 480, '2026-11-03': 435},
        {'2026-11-02': 60},
      ),
    };
    for (final e in cases.entries) {
      test(e.key, () {
        final (pieces, steps, nights, naps) = e.value;
        final w = watch(pieces, steps);
        final o = oura(pieces, steps);
        expect(w.nights, nights, reason: 'ρολόι');
        expect(w.naps, naps, reason: 'ρολόι');
        expect(o.nights, nights, reason: 'Oura (με τα βήματα του ρολογιού)');
        expect(o.naps, naps, reason: 'Oura (με τα βήματα του ρολογιού)');
      });
    }
  });

  group('E1.6: η απόφαση «υπνάκος» με βήματα κλειδώνει (μέρα 8, επανανάγνωση, Oura)', () {
    final pieces = [(at(11, 2, 23, 30), at(11, 3, 6, 30)), (at(11, 3, 8, 0), at(11, 3, 9, 30))];
    final day0Steps = Steps(DateTime(2026, 10, 27), [(at(11, 3, 7, 15), 1200)]);
    // Μέρα 8: η κανονική ανάγνωση έχει βήματα ανά λεπτό μόνο για 7 μέρες (από 4/11).
    final day8Steps = Steps(DateTime(2026, 11, 4));

    test('Ρολόι: μέρα 0 υπνάκος 90′ → μέρα 8 (ξαναγράφονται 30 μέρες χωρίς βήματα) μένει υπνάκος', () {
      final h = <String, Map<String, double>>{};
      final d0 = watch(pieces, day0Steps, readAt: at(11, 3, 12)).d;
      applyRecentRead(h, d0, plan: SourcePlan.samsungOnly);
      final row0 = Map.of(h['2026-11-03']!);
      expect(row0[K.sleepMin], 420);
      expect(row0[K.napMin], 90);
      expect(row0[K.wake], minutesFromSix(at(11, 3, 6, 30)));
      expect(row0[K.napLock], ms(at(11, 3, 8, 0)) ~/ 60000, reason: 'η απόφαση αποθηκεύεται');

      final d8 = watch(pieces, day8Steps, readAt: at(11, 11, 12), napLocks: napLocksOf(h)).d;
      applyRecentRead(h, d8, plan: SourcePlan.samsungOnly);
      expect(h['2026-11-03'], row0, reason: 'καμία αλλαγή χωρίς νέα δεδομένα');
      // Και ξανά (κάθε ανανέωση ως τη μέρα 29): ποτέ αναστροφή.
      final d9 = watch(pieces, day8Steps, readAt: at(11, 12, 12), napLocks: napLocksOf(h)).d;
      applyRecentRead(h, d9, plan: SourcePlan.samsungOnly);
      expect(h['2026-11-03'], row0);

      // Χωρίς την αποθηκευμένη απόφαση (πριν από τη διόρθωση): η νύχτα θα γινόταν 510′ με ξύπνημα 09:30.
      final bare = watch(pieces, day8Steps, readAt: at(11, 11, 12));
      expect(bare.nights['2026-11-03'], 510);
    });

    test('Επανανάγνωση κομματιού (με ή χωρίς βήματα): η ίδια απόφαση', () {
      final h = <String, Map<String, double>>{};
      applyRecentRead(h, watch(pieces, day0Steps, readAt: at(11, 3, 12)).d, plan: SourcePlan.samsungOnly);
      for (final steps in [day0Steps, day8Steps, Steps.unknown]) {
        final raw = jsonEncode({
          'ok': true,
          'readAt': ms(at(11, 30, 23)),
          'sleep': [for (final p in pieces) rec(p.$1, p.$2)],
          ...steps.json(),
        });
        final r = parseRangeSync(raw, DateTime(2026, 11, 1), DateTime(2026, 11, 29), napLocks: napLocksOf(h));
        expect(r.rows['2026-11-03']![K.sleepMin], 420, reason: '${steps.from}');
        expect(r.rows['2026-11-03']![K.napMin], 90, reason: '${steps.from}');
        expect(r.rows['2026-11-03']![K.napLock], h['2026-11-03']![K.napLock]);
      }
    });

    test('Με λίγα βήματα (≤ 30) η απόφαση «ίδια νύχτα» δεν κλειδώνει τίποτα', () {
      final r = watch(pieces, Steps(DateTime(2026, 10, 27), [(at(11, 3, 7, 15), 10)]), readAt: at(11, 3, 12));
      expect(r.nights['2026-11-03'], 510);
      expect(summarizeDay(r.d, DateTime(2026, 11, 3)).containsKey(K.napLock), isFalse);
    });

    test('Oura: τα βήματα του ρολογιού κρίνουν το κενό· η απόφαση μένει και χωρίς βήματα (ξαναδιάβασμα της Oura)', () {
      final first = oura(pieces, day0Steps);
      expect(first.nights['2026-11-03'], 420);
      expect(first.naps['2026-11-03'], 90);
      final row = ouraRow(first.list.single);
      expect(row[ouraKeys[K.napLock]!], ms(at(11, 3, 8, 0)) ~/ 60000);
      // Το αρχείο νυχτών κρατά την απόφαση.
      final back = decodeOuraNights(encodeOuraNights(first.list)).single;
      expect(back.napLock, first.list.single.napLock);
      final locks = {'2026-11-03': row[ouraKeys[K.napLock]!]!.round()};
      final again = oura(pieces, day8Steps, napLocks: locks);
      expect(again.nights['2026-11-03'], 420);
      expect(again.naps['2026-11-03'], 90);
      final noSteps = oura(pieces, Steps.unknown, napLocks: locks, withSteps: false);
      expect(noSteps.nights['2026-11-03'], 420);
      // Χωρίς αποθηκευμένη απόφαση και χωρίς βήματα: μία νύχτα (ο κανόνας λέει «άγνωστα βήματα → ίδια νύχτα»).
      expect(oura(pieces, Steps.unknown, withSteps: false).nights['2026-11-03'], 510);
    });

    test('Ρολόι και Oura δίνουν την ίδια κλειδωμένη απόφαση για τα ίδια κομμάτια', () {
      final w = watch(pieces, day0Steps, readAt: at(11, 3, 12));
      final o = oura(pieces, day0Steps);
      expect(w.d.nights.single.napLock, o.list.single.napLock);
    });
  });

  group('E2: ζυγίσεις άλλων εφαρμογών δεν σβήνονται ποτέ· φίλτρο εμφάνισης από την πρώτη InBody', () {
    const inbodyApp = 'com.inbody2014.inbody';
    const watchApp = 'com.samsung.android.wear.shealth';
    Map<String, dynamic> w(DateTime day, double kg, String app, {double? fat}) =>
        {'time': ms(day.add(const Duration(hours: 8))), 'weight': kg, if (fat != null) 'fatPct': fat, 'app': app};

    test('Καμία ζύγιση InBody, ίδιες μέρες με το ιστορικό: τίποτα δεν σβήνεται, τίποτα δεν κρύβεται, σημείωση στο «Τι φτάνει»', () {
      final days = [for (var i = 1; i <= 6; i++) DateTime(2026, 10, i)];
      final d = Dashboard.fromJson({
        'readAt': ms(DateTime(2026, 11, 20, 12)),
        'body': [for (final day in days) w(day, 82.0, watchApp, fat: 22)],
      });
      expect(d.body, isEmpty);
      final h = <String, Map<String, double>>{
        for (final day in days) dateKey(day): {K.weight: 82.0, K.fatPct: 22, K.steps: 5000},
      };
      final before = {for (final e in h.entries) e.key: Map.of(e.value)};
      final changed = applyRecentRead(h, d, plan: SourcePlan.samsungOnly);
      expect(h, before, reason: 'πριν (C5) έσβηνε ΚΑΘΕ ζύγιση σε αυτή την περίπτωση');
      expect(changed.intersection(before.keys.toSet()), isEmpty);
      expect(scaleFromOf(h), isNull, reason: 'χωρίς InBody τίποτα δεν κρύβεται');
      expect(SourcePlan.samsungOnly.withScaleFrom(scaleFromOf(h)).value(h, K.weight, days.first), 82.0);
      expect(filterWarning({'key': 'body_composition', 'state': 'ok', 'count': 6, 'counted': 0, 'ignored': 6}),
          contains('Το ιστορικό ζυγίσεων μένει όπως ήταν'));
    });

    test('Παλιές ζυγίσεις ρολογιού πριν ΚΑΙ μετά την πρώτη InBody (ίδιες μέρες): μένουν όλες· φαίνονται μόνο πριν', () {
      final first = DateTime(2026, 10, 10);
      final d = Dashboard.fromJson({
        'readAt': ms(DateTime(2026, 11, 20, 12)),
        'body': [
          w(DateTime(2026, 10, 1), 84.0, watchApp),
          w(DateTime(2026, 10, 5), 83.5, watchApp),
          w(first, 82.0, inbodyApp, fat: 24),
          w(DateTime(2026, 10, 12), 81.0, watchApp),
          // Ίδια μέρα: ρολόι και InBody → η InBody.
          w(DateTime(2026, 10, 14), 90.0, watchApp),
          w(DateTime(2026, 10, 14), 81.8, inbodyApp, fat: 23.5),
        ],
      });
      final h = <String, Map<String, double>>{
        '2026-10-01': {K.weight: 84.0},
        '2026-10-05': {K.weight: 83.5},
        '2026-10-12': {K.weight: 81.0, K.steps: 7000},
        '2026-10-14': {K.weight: 90.0},
      };
      applyRecentRead(h, d, plan: SourcePlan.samsungOnly);
      expect(h['2026-10-01']![K.weight], 84.0);
      expect(h['2026-10-05']![K.weight], 83.5);
      expect(h['2026-10-12']![K.weight], 81.0, reason: 'μένει αποθηκευμένη (κρυφή)');
      expect(h['2026-10-14'], {K.weight: 81.8, K.fatPct: 23.5, K.inbody: 1});
      expect(h['2026-10-10'], {K.weight: 82.0, K.fatPct: 24, K.inbody: 1});

      expect(scaleFromOf(h), first);
      final plan = SourcePlan.samsungOnly.withScaleFrom(scaleFromOf(h));
      expect(plan.value(h, K.weight, DateTime(2026, 10, 1)), 84.0, reason: 'πριν από την πρώτη InBody: φαίνεται');
      expect(plan.value(h, K.weight, DateTime(2026, 10, 12)), isNull, reason: 'μετά: μόνο InBody');
      expect(plan.value(h, K.steps, DateTime(2026, 10, 12)), 7000);
      expect(plan.value(h, K.weight, DateTime(2026, 10, 14)), 81.8);
      expect(plan.changeDates(K.weight), [first]);
      expect(plan.changeDates(K.fatPct), [first]);
      expect(plan.changeDates(K.smm), [first]);
      expect(plan.changeDates(K.steps), isEmpty);
      expect(plan.changeWithin(K.weight, DateTime(2026, 10, 1), DateTime(2026, 10, 20)), first,
          reason: 'καμία σύγκριση/τάση πάνω από την αλλαγή');
      // Η αναφορά: οι παλιές ζυγίσεις με την πηγή τους, ποτέ ως InBody.
      final r = buildReport(h, DateTime(2026, 11, 20, 12), plan: plan);
      expect([for (final x in r.weighIns) dateKey(x.$1)], ['2026-10-14', '2026-10-10', '2026-10-05', '2026-10-01']);
      expect(r.otherWeighIns, {DateTime(2026, 10, 5), DateTime(2026, 10, 1)});
      // Το σχέδιο κρατά το όριο και με όριο επανανάγνωσης ή νέα εποχή.
      expect(plan.withRulesFrom(DateTime(2026, 11, 1)).scaleFrom, first);
      expect(plan.withEra(Source.oura, DateTime(2026, 11, 2)).scaleFrom, first);
      expect(plan.withScaleFrom(null) == plan, isTrue, reason: 'δεν μετρά στην ισότητα (δεν αποθηκεύεται)');
    });

    test('Ζύγιση που σβήστηκε στη Samsung: φεύγει (ως 3)· ζύγιση άλλης εφαρμογής που υπάρχει ακόμα: ποτέ', () {
      final d = Dashboard.fromJson({
        'readAt': ms(DateTime(2026, 11, 20, 12)),
        'body': [w(DateTime(2026, 10, 10), 82.0, inbodyApp), w(DateTime(2026, 10, 2), 85.0, watchApp)],
      });
      final h = <String, Map<String, double>>{
        '2026-10-02': {K.weight: 85.0},
        '2026-10-03': {K.weight: 84.0}, // δεν υπάρχει πια στη Samsung
      };
      applyRecentRead(h, d, plan: SourcePlan.samsungOnly);
      expect(h['2026-10-02']![K.weight], 85.0);
      expect(h['2026-10-03']!.containsKey(K.weight), isFalse);
    });
  });

  group('E5: οξυγόνο, όλες οι 30 νύχτες (ίδιος αισθητήρας), με ημερομηνίες', () {
    // Oura από τη μέρα X· οι νύχτες X−10 (72%) και X−4 (74%) είναι νύχτες του ρολογιού στο ιστορικό.
    final x = DateTime(2026, 11, 6);
    DateTime dx(int n) => DateTime(x.year, x.month, x.day + n);
    final history = <String, Map<String, double>>{
      for (var i = -25; i <= 0; i++) dateKey(dx(i)): {K.spo2Min: 91, K.spo2Avg: 95},
      dateKey(dx(-10)): {K.spo2Min: 72, K.spo2Avg: 93},
      dateKey(dx(-4)): {K.spo2Min: 74, K.spo2Avg: 93},
    };
    // Η ανάγνωση της μέρας X+1: καμία νύχτα ρολογιού (ο ύπνος είναι του Oura), οξυγόνο μέσα στο παράθυρο του Oura.
    final d = Dashboard.fromJson({
      'readAt': ms(DateTime(2026, 11, 7, 10)),
      'sleep': <Object>[],
      'spo2': [
        [ms(DateTime(2026, 11, 7, 3)), ms(DateTime(2026, 11, 7, 3, 5)), 93.0, 90.0, 95.0],
      ],
    });
    final windows = SleepWindows(const [], {
      dateKey(dx(1)): (DateTime(2026, 11, 6, 23), DateTime(2026, 11, 7, 7)),
    });

    test('Μετά τη σύνδεση του Oura: «2 νύχτες» από τις νύχτες του ρολογιού πριν (Καρδιά/Ύπνος Oura/Σήμερα)', () {
      final m = d.spo2MinByNight(dx(1), ouraNights: true, windows: windows, history: history);
      expect(m[dx(-10)], 72);
      expect(m[dx(-4)], 74);
      expect(m[dx(1)], 90, reason: 'η νύχτα του Oura: το ρολόι μέσα στις ώρες του Oura');
      final g = oxygenGuidance(m, dx(1), today: dx(1));
      expect(g.veryLowRepeated, isTrue, reason: 'πριν (since = σύνδεση) δεν έβγαινε καμία σημείωση');
      expect(g.messages.single, contains('σε 2 νύχτες μέσα στις τελευταίες 30 μέρες'));
      expect(g.messages.single, contains('(27/10: 72%, 2/11: 74%)'));
      expect(g.messages.single, contains('ένα αρνητικό τεστ άπνοιας του ρολογιού δεν το αποκλείει'));
    });

    test('Οθόνες του ρολογιού (νύχτες ρολογιού) και κατά την επανανάγνωση: το ίδιο', () {
      // Χωρίς νύχτες στην ανάγνωση (π.χ. οθόνη ρολογιού μετά από «ξανά από το ρολόι»): από το ιστορικό.
      final m = d.spo2MinByNight(dx(0), history: history);
      expect(oxygenGuidance(m, dx(0)).veryLowRepeated, isTrue);
      // Το όριο της επανανάγνωσης δεν κόβει τίποτα: δεν υπάρχει πια «since».
      expect(m.length, 26);
    });

    test('Χωρίς ιστορικό: μόνο ό,τι έχει η ανάγνωση (όπως πριν)', () {
      final m = d.spo2MinByNight(dx(1), ouraNights: true, windows: windows);
      expect(m.keys.toList(), [dx(1)]);
    });
  });

  test('E7: ξύπνιος του Oura = awake_time − latency (ποτέ κάτω από 0)· ύπνος + ξύπνιος = από τον ύπνο ως το ξύπνημα', () {
    OuraSleep s(int awake, int? latency) => OuraSleep.fromJson({
          'id': 'a',
          'day': '2026-11-03',
          'type': 'long_sleep',
          'bedtime_start': DateTime(2026, 11, 2, 23).toUtc().toIso8601String(),
          'bedtime_end': DateTime(2026, 11, 3, 7).toUtc().toIso8601String(),
          'time_in_bed': 8 * 3600,
          'total_sleep_duration': 8 * 3600 - awake,
          'awake_time': awake,
          if (latency != null) 'latency': latency,
        })!;
    expect(s(2610, 900).awakeInSleep, 1710);
    expect(s(300, 900).awakeInSleep, 0);
    expect(s(1200, null).awakeInSleep, 1200);
    final n = parseOura(sleep: [
      {
        'id': 'a',
        'day': '2026-11-03',
        'type': 'long_sleep',
        'bedtime_start': DateTime(2026, 11, 2, 23).toUtc().toIso8601String(),
        'bedtime_end': DateTime(2026, 11, 3, 7).toUtc().toIso8601String(),
        'time_in_bed': 8 * 3600,
        'total_sleep_duration': 8 * 3600 - 2610,
        'awake_time': 2610,
        'latency': 900,
      },
    ], dailySleep: const [], readiness: const []).nights.single;
    final row = ouraRow(n);
    expect(row[ouraKeys[K.awakeMin]], 28.5);
    // Από τον ύπνο (23:15) ως το ξύπνημα (07:00) = 465′ = ύπνος 436,5′ + ξύπνιος 28,5′.
    expect(row[ouraKeys[K.sleepMin]]! + row[ouraKeys[K.awakeMin]]!, 465);
  });
}
