// Συγχώνευση audit-c + audit-d (4/11): ΕΝΑΣ κανόνας νύχτας για ρολόι και Oura, και το όριο της επανανάγνωσης στο
// οξυγόνο της αναφοράς (90 μέρες, ένα κομμάτι για κάθε ορισμό, ο παλιός κανόνας με το όνομά του).
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/oura/oura_model.dart';
import 'package:ygeia_forma/pages/compare_page.dart';
import 'package:ygeia_forma/report.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/trends.dart';

DateTime _add(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

void main() {
  group('Ένας κανόνας νύχτας: ρολόι και Oura δίνουν το ίδιο αποτέλεσμα για τα ίδια κομμάτια', () {
    DateTime at(int day, int h, int m) => DateTime(2026, 11, day, h, m);
    int ms(DateTime t) => t.millisecondsSinceEpoch;

    // Ρολόι: κομμάτια χωρίς φάσεις (η διάρκεια της Samsung), χωρίς βήματα ανά λεπτό (= άγνωστα, όπως στο Oura).
    ({int? night, int nap}) watch(List<(DateTime, DateTime, int)> pieces) {
      final d = Dashboard.fromJson({
        'readAt': ms(at(3, 18, 0)),
        'sleep': [
          for (final p in pieces) {'start': ms(p.$1), 'end': ms(p.$2), 'minutes': p.$3, 'stages': []},
        ],
      });
      final n = d.nights.where((x) => sameDay(x.date, DateTime(2026, 11, 3))).toList();
      return (night: n.isEmpty ? null : n.single.minutes, nap: d.naps[DateTime(2026, 11, 3)] ?? 0);
    }

    // Oura: οι ίδιες περίοδοι, ως «sleep» (ο τύπος της Oura δεν αποφασίζει).
    ({int? night, int nap}) oura(List<(DateTime, DateTime, int)> pieces, {String type = 'sleep'}) {
      var i = 0;
      final n = parseOura(sleep: [
        for (final p in pieces)
          {
            'id': 'p${i++}',
            'day': '2026-11-03',
            'type': type,
            'bedtime_start': p.$1.toUtc().toIso8601String(),
            'bedtime_end': p.$2.toUtc().toIso8601String(),
            'total_sleep_duration': p.$3 * 60,
          },
      ], dailySleep: const [], readiness: const [])
          .nights
          .single;
      return (night: n.nightMinutes, nap: n.napMinutes);
    }

    final cases = <String, (List<(DateTime, DateTime, int)>, int?, int)>{
      'νύχτα σε δύο κομμάτια, κενό 70′ (η νύχτα του χρήστη)': (
        [(at(2, 23, 43), at(3, 2, 40), 152), (at(3, 3, 50), at(3, 7, 8), 178)],
        330,
        0,
      ),
      'λαγοκοίμισμα 20:30–21:30 και ύπνος 23:30': ([(at(2, 20, 30), at(2, 21, 30), 60), (at(2, 23, 30), at(3, 7, 0), 420)], 420, 60),
      'μετά τις 22:00: μέρος της νύχτας': ([(at(2, 21, 0), at(2, 22, 30), 85), (at(2, 23, 30), at(3, 7, 0), 420)], 505, 0),
      'πρωί, κενό 60′, χωρίς βήματα: ίδια νύχτα': ([(at(2, 23, 30), at(3, 7, 0), 420), (at(3, 8, 0), at(3, 9, 0), 55)], 475, 0),
      'πρωί, κενό 2 ώρες 30 λεπτά: υπνάκος': ([(at(2, 23, 30), at(3, 7, 0), 420), (at(3, 9, 30), at(3, 10, 30), 55)], 420, 55),
      'απόγευμα 15:00: υπνάκος': ([(at(2, 23, 30), at(3, 7, 0), 420), (at(3, 15, 0), at(3, 15, 40), 35)], 420, 35),
      'κενό πάνω από 4 ώρες, ίδια μέρα: μέρος της νύχτας': ([(at(3, 0, 10), at(3, 0, 50), 35), (at(3, 5, 0), at(3, 7, 30), 145)], 180, 0),
      'μόνο λαγοκοίμισμα 20:00–21:40: υπνάκος, όχι νύχτα': ([(at(2, 20, 0), at(2, 21, 40), 95)], null, 95),
    };
    for (final e in cases.entries) {
      test(e.key, () {
        final (pieces, night, nap) = e.value;
        final w = watch(pieces);
        final o = oura(pieces);
        expect(w.night, night, reason: 'ρολόι');
        expect(o.night, night, reason: 'Oura');
        expect(w.nap, nap, reason: 'ρολόι');
        expect(o.nap, nap, reason: 'Oura');
        // Ο τύπος της Oura δεν αλλάζει τίποτα.
        expect(oura(pieces, type: 'long_sleep'), o);
      });
    }
  });

  group('Αναφορά: οξυγόνο 90 μέρες, χωρισμένο και στο όριο της επανανάγνωσης', () {
    final now = DateTime(2026, 11, 20, 10);
    final boundary = DateTime(2026, 10, 20);
    Map<String, Map<String, double>> history() => {
          for (var d = _add(dayOf(now), -120); !d.isAfter(dayOf(now)); d = _add(d, 1))
            dateKey(d): {K.spo2Min: d.isBefore(boundary) ? 88 : 91, K.spo2Avg: 94, K.sleepMin: 400},
        };

    test('Ένα κομμάτι με τον παλιό κανόνα και ένα με τον νέο· καμία σύγκριση πάνω από το όριο', () {
      final plan = SourcePlan.samsungOnly.withRulesFrom(boundary);
      final r = buildReport(history(), now, plan: plan);
      final s = r.stat(K.spo2Min);
      expect(s.n, 90, reason: 'όλες οι 90 μέρες, ποτέ κομμένες');
      expect(s.periods.length, 2);
      expect(s.periods.first.oldRules, isTrue);
      expect(s.periods.first.to, _add(boundary, -1));
      expect(s.periods.last.oldRules, isFalse);
      expect(s.periods.last.from, boundary);
      expect(s.periods.first.stat.n + s.periods.last.stat.n, 90);
      final t = r.stat(K.spo2Avg).trend!;
      expect(t.status, TrendStatus.sourceChange);
      expect(t.rereading, isTrue, reason: '«Ενημερώνεται το ιστορικό»');
      // Χωρίς επανανάγνωση: ένα κομμάτι, χωρίς ετικέτα παλιού κανόνα.
      final plain = buildReport(history(), now, plan: SourcePlan.samsungOnly).stat(K.spo2Min);
      expect(plain.periods, isEmpty);
      expect(plain.n, 90);
    });
  });

  test('Σύγκριση πηγών: νύχτα Oura σε κομμάτια = όλα τα κομμάτια (διάρκεια, ώρες, ξύπνιος, κομμάτια)', () {
    Map<String, dynamic> rec(String id, DateTime a, DateTime b, int awake) => {
          'id': id,
          'day': '2026-11-03',
          'type': 'sleep',
          'bedtime_start': a.toUtc().toIso8601String(),
          'bedtime_end': b.toUtc().toIso8601String(),
          'total_sleep_duration': b.difference(a).inSeconds - 600 - awake * 60,
          'awake_time': awake * 60,
          'latency': 600,
        };
    final oura = parseOura(sleep: [
      rec('a', DateTime(2026, 11, 2, 23, 0), DateTime(2026, 11, 3, 1, 30), 10),
      rec('b', DateTime(2026, 11, 3, 3, 0), DateTime(2026, 11, 3, 5, 45), 5),
    ], dailySleep: const [], readiness: const [])
        .nights;
    final plan = SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 3));
    final r = buildCompareRows(plan: plan, oura: oura, watch: const [], today: DateTime(2026, 11, 3)).single;
    expect(r.ouraMinutes, 130 + 150);
    expect(r.ouraParts, 2);
    expect(r.ouraStart!.millisecondsSinceEpoch, DateTime(2026, 11, 2, 23, 10).millisecondsSinceEpoch);
    expect(r.ouraEnd!.millisecondsSinceEpoch, DateTime(2026, 11, 3, 5, 45).millisecondsSinceEpoch);
    expect(r.ouraAwake, 15);
    expect(r.ouraSpan, 140 + 165, reason: 'από τον ύπνο ως το ξύπνημα κάθε κομματιού, χωρίς το κενό');
  });
}
