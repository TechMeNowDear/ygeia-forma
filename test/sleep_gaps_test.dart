import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/heart_day.dart';
import 'package:ygeia_forma/history.dart';

/// Η νύχτα 25→26/10 του χρήστη, όπως την έδωσε η Samsung: δύο κομμάτια με κενό 1,5 ώρας,
/// χωρίς βήματα και με παλμούς ύπνου μέσα στο κενό.
Map<String, dynamic> night({
  int gapSteps = 0,
  double gapHr = 69,
  DateTime? secondStart,
  bool stepsKnown = true,
  DateTime? firstStart,
  DateTime? firstEnd,
}) {
  int ms(DateTime t) => t.millisecondsSinceEpoch;
  final aStart = firstStart ?? DateTime(2026, 10, 26, 2, 52);
  final aEnd = firstEnd ?? DateTime(2026, 10, 26, 3, 55);
  final bStart = secondStart ?? DateTime(2026, 10, 26, 5, 34);
  final bEnd = bStart.add(const Duration(minutes: 141));
  final heart = <List<num>>[];
  for (var t = DateTime(2026, 10, 26, 2, 0); t.isBefore(DateTime(2026, 10, 26, 13, 0)); t = t.add(const Duration(minutes: 10))) {
    final inGap = !t.isBefore(aEnd) && t.isBefore(bStart);
    final hr = inGap ? gapHr : 66.0;
    heart.add([ms(t), ms(t.add(const Duration(minutes: 10))), hr, hr - 5, hr + 5]);
  }
  final midGap = aEnd.add(bStart.difference(aEnd) ~/ 2);
  return {
    'readAt': ms(DateTime(2026, 10, 26, 13, 0)),
    'sleep': [
      {'start': ms(aStart), 'end': ms(aEnd), 'minutes': 63, 'score': 17, 'stages': []},
      {'start': ms(bStart), 'end': ms(bEnd), 'minutes': 141, 'score': 30, 'stages': []},
    ],
    'heart': heart,
    'stepsMin': [
      [ms(DateTime(2026, 10, 26, 0, 51)), 29],
      if (gapSteps > 0) [ms(midGap), gapSteps],
      [ms(DateTime(2026, 10, 26, 9, 33)), 10],
    ],
    if (stepsKnown) 'stepsFrom': ms(DateTime(2026, 10, 19)),
    if (!stepsKnown) 'stepsFrom': ms(DateTime(2026, 10, 26, 12, 0)),
  };
}

void main() {
  test('Κενό χωρίς βήματα, με παλμούς ύπνου: μία νύχτα· το κενό φαίνεται χωριστά και δεν μετρά', () {
    final d = Dashboard.fromJson(night());
    expect(d.nights.length, 1);
    final n = d.nights.single;
    expect(n.parts.length, 2);
    expect(n.estimatedGaps.length, 1);
    expect(n.estimatedMinutes, 99);
    expect(n.minutes, 63 + 141, reason: 'η διάρκεια είναι μόνο ό,τι μέτρησε η Samsung');
    expect(n.score, isNull, reason: 'σπασμένη νύχτα: η Samsung βαθμολογεί κάθε κομμάτι χωριστά');
  });

  // Έλεγχος 2, C1: πριν (A6) τα 200 βήματα «έκοβαν» τη νύχτα και το πρώτο κομμάτι γινόταν υπνάκος. Τώρα κομμάτι με κενό
  // ως 4 ώρες είναι η ίδια νύχτα ανεξάρτητα από βήματα· τα βήματα αλλάζουν μόνο την ετικέτα του κενού.
  test('Βήματα στο κενό (C1): ίδια νύχτα· χωρίς «πιθανό ύπνο», το κενό δεν μετρά', () {
    final n = Dashboard.fromJson(night(gapSteps: 200)).nights.single;
    expect(n.estimatedMinutes, 0);
    expect(n.minutes, 63 + 141, reason: 'μια βόλτα στο κενό δεν κόβει τη νύχτα· το κενό των 99 λεπτών δεν μετρά');
    expect(n.betweenMinutes, 99);
    expect(n.napMinutes, 0);
    expect(n.start, DateTime(2026, 10, 26, 2, 52));
  });

  group('C1: κομμάτια με κενό ως 4 ώρες είναι η ίδια νύχτα· υπνάκοι μόνο το βράδυ ως τις 22:00 ή το πρωί', () {
    int ms(DateTime t) => t.millisecondsSinceEpoch;
    Map<String, dynamic> rec(DateTime a, DateTime b) =>
        {'start': ms(a), 'end': ms(b), 'minutes': b.difference(a).inMinutes, 'stages': []};
    Map<String, dynamic> json(List<Map<String, dynamic>> sleep, {List<List<num>> steps = const [], bool known = true}) => {
          'readAt': ms(DateTime(2026, 11, 2, 13)),
          'sleep': sleep,
          'stepsMin': steps,
          'stepsFrom': known ? ms(DateTime(2026, 10, 26)) : ms(DateTime(2026, 11, 2, 12)),
        };

    // Έλεγχος 3, E1 (σκόπιμα): πριν από την κύρια ομάδα, υπνάκος είναι ό,τι αρχίζει πριν από τις 20:00 (ή με κενό
    // πάνω από 4 ώρες)· από τις 20:00 με κενό ως 4 ώρες είναι αρχή της νύχτας (δες audit_c_test / audit_e_test).
    test('Λαγοκοίμισμα στον καναπέ 19:00–20:00, μετά περπάτημα, ύπνος 23:30: υπνάκος, όχι αρχή της νύχτας', () {
      final d = Dashboard.fromJson(json([
        rec(DateTime(2026, 11, 1, 19), DateTime(2026, 11, 1, 20)),
        rec(DateTime(2026, 11, 1, 23, 30), DateTime(2026, 11, 2, 7)),
      ], steps: [
        [ms(DateTime(2026, 11, 1, 22, 30)), 120],
      ]));
      final n = d.nights.single;
      expect(n.minutes, 450);
      expect(n.start, DateTime(2026, 11, 1, 23, 30));
      expect(n.score, isNull, reason: 'χωρίς βαθμολογία στο δείγμα');
      expect(n.parts.length, 1, reason: 'το λαγοκοίμισμα δεν είναι κομμάτι της νύχτας');
    });

    test('Λαγοκοίμισμα το πρωί 08:30–09:30 μετά από βήματα: υπνάκος, η ώρα ξυπνήματος μένει 07:00', () {
      final d = Dashboard.fromJson(json([
        rec(DateTime(2026, 11, 1, 23, 30), DateTime(2026, 11, 2, 7)),
        rec(DateTime(2026, 11, 2, 8, 30), DateTime(2026, 11, 2, 9, 30)),
      ], steps: [
        [ms(DateTime(2026, 11, 2, 7, 40)), 80],
      ]));
      final n = d.nights.single;
      expect(n.minutes, 450);
      expect(n.end, DateTime(2026, 11, 2, 7));
      expect(n.napMinutes, 60);
    });

    test('Κενό χωρίς βήματα (ως 30): μία νύχτα, όπως πριν', () {
      final d = Dashboard.fromJson(json([
        rec(DateTime(2026, 11, 1, 23, 30), DateTime(2026, 11, 2, 3)),
        rec(DateTime(2026, 11, 2, 4, 30), DateTime(2026, 11, 2, 7)),
      ], steps: [
        [ms(DateTime(2026, 11, 2, 3, 40)), 12],
      ]));
      expect(d.nights.single.minutes, 210 + 150);
      expect(d.nights.single.napMinutes, 0);
    });

    test('Χωρίς στοιχεία βημάτων για το κενό: ίδια νύχτα, όπως με βήματα (C1: καμία αλλαγή όταν η νύχτα παλιώσει)', () {
      Dashboard read(bool known) => Dashboard.fromJson(json([
            rec(DateTime(2026, 11, 1, 23, 30), DateTime(2026, 11, 2, 5)),
            rec(DateTime(2026, 11, 2, 6), DateTime(2026, 11, 2, 7)),
          ], known: known));
      for (final known in [false, true]) {
        expect(read(known).nights.single.minutes, 330 + 60, reason: 'βήματα γνωστά: $known');
        expect(read(known).nights.single.napMinutes, 0);
      }
    });

    test('Δεύτερο κομμάτι 3 ωρών και πάνω με βήματα στο κενό: μένει μέρος της νύχτας (δεν είναι λαγοκοίμισμα)', () {
      final d = Dashboard.fromJson(json([
        rec(DateTime(2026, 11, 1, 22), DateTime(2026, 11, 2, 2)),
        rec(DateTime(2026, 11, 2, 3, 30), DateTime(2026, 11, 2, 7)),
      ], steps: [
        [ms(DateTime(2026, 11, 2, 2, 30)), 200],
      ]));
      expect(d.nights.single.minutes, 240 + 210);
      expect(d.nights.single.napMinutes, 0);
    });
  });

  test('Παλμοί ξύπνιου στο κενό: χωρίς πιθανό ύπνο', () {
    final n = Dashboard.fromJson(night(gapHr: 85)).nights.single;
    expect(n.estimatedMinutes, 0);
  });

  test('Χωρίς στοιχεία βημάτων για το κενό: χωρίς πιθανό ύπνο (δεν μαντεύουμε)', () {
    final n = Dashboard.fromJson(night(stepsKnown: false)).nights.single;
    expect(n.estimatedMinutes, 0);
  });

  test('Δεύτερο κομμάτι μετά τις 10:00 με «καθαρό» κενό: μέρος της νύχτας, όχι υπνάκος', () {
    final d = Dashboard.fromJson(night(secondStart: DateTime(2026, 10, 26, 5, 0).add(const Duration(hours: 5, minutes: 30))));
    // κενό 03:55 → 10:30 = 6,5 ώρες: πάνω από το όριο των 4 ωρών, άρα υπνάκος όπως πριν
    expect(d.nights.single.napMinutes, 141);
    // Κυριακή 25/10: 05:55–09:50 και 10:53–… με κενό 63 λεπτών χωρίς βήματα (ο χρήστης ΔΕΝ ξύπνησε· η Samsung χώρισε
    // τη νύχτα). Κανόνας C1: πρωινό κομμάτι με κενό ως 90 λεπτά και χωρίς βήματα (ως 30) = η ίδια νύχτα.
    final sunday = Dashboard.fromJson(night(
      firstStart: DateTime(2026, 10, 26, 5, 55),
      firstEnd: DateTime(2026, 10, 26, 9, 50),
      secondStart: DateTime(2026, 10, 26, 10, 53),
    ));
    expect(sunday.nights.single.napMinutes, 0);
    expect(sunday.nights.single.estimatedMinutes, 63);
    expect(sunday.nights.single.minutes, 63 + 141);
    expect(summarizeDay(sunday, DateTime(2026, 10, 26)).containsKey(K.napMin), isFalse);
  });

  test('Υπνάκος με βήματα πριν: μένει υπνάκος', () {
    final d = Dashboard.fromJson(night(secondStart: DateTime(2026, 10, 26, 10, 53), gapSteps: 300));
    expect(d.nights.single.napMinutes, 141);
    expect(d.nights.single.estimatedMinutes, 0);
  });

  test('Παλμοί μόνο στην αρχή του κενού (ρολόι στον φορτιστή): χωρίς πιθανό ύπνο', () {
    int ms(DateTime t) => t.millisecondsSinceEpoch;
    final j = night();
    final aEnd = DateTime(2026, 10, 26, 3, 55);
    final bStart = DateTime(2026, 10, 26, 5, 34);
    // Κρατάμε μόνο τις μετρήσεις έξω από το κενό + μία στα πρώτα 8 λεπτά του.
    final heart = [
      for (final h in j['heart'] as List<List<num>>)
        if (h[1] <= ms(aEnd) || h[0] >= ms(bStart)) h,
      [ms(aEnd), ms(aEnd.add(const Duration(minutes: 8))), 66, 61, 71],
    ];
    final n = Dashboard.fromJson({...j, 'heart': heart}).nights.single;
    expect(n.estimatedMinutes, 0);
  });

  group('Διπλές και επικαλυπτόμενες εγγραφές', () {
    int ms(DateTime t) => t.millisecondsSinceEpoch;
    Map<String, dynamic> rec(DateTime a, DateTime b, int minutes, [int? score]) =>
        {'start': ms(a), 'end': ms(b), 'minutes': minutes, 'score': score, 'stages': []};

    test('Η ίδια νύχτα από δύο πηγές: μετρά μία φορά (η μεγαλύτερη)', () {
      final d = Dashboard.fromJson({
        'readAt': ms(DateTime(2026, 11, 2, 12)),
        'sleep': [
          rec(DateTime(2026, 11, 2, 2, 0), DateTime(2026, 11, 2, 9, 0), 420, 80),
          rec(DateTime(2026, 11, 2, 2, 10), DateTime(2026, 11, 2, 8, 50), 400, 75),
        ],
      });
      expect(d.nights.single.minutes, 420);
      expect(d.nights.single.parts.length, 1);
      expect(d.nights.single.score, 80);
    });

    test('Μικρή εγγραφή μέσα σε μεγάλη: δεν προστίθεται', () {
      final d = Dashboard.fromJson({
        'readAt': ms(DateTime(2026, 11, 2, 12)),
        'sleep': [
          rec(DateTime(2026, 11, 2, 2, 0), DateTime(2026, 11, 2, 9, 0), 420),
          rec(DateTime(2026, 11, 2, 4, 0), DateTime(2026, 11, 2, 7, 0), 180),
        ],
      });
      expect(d.nights.single.minutes, 420);
    });

    test('Μικρή επικάλυψη: τα κοινά λεπτά μετρούν μία φορά', () {
      final d = Dashboard.fromJson({
        'readAt': ms(DateTime(2026, 11, 2, 12)),
        'sleep': [
          rec(DateTime(2026, 11, 2, 1, 0), DateTime(2026, 11, 2, 5, 0), 240),
          rec(DateTime(2026, 11, 2, 4, 30), DateTime(2026, 11, 2, 8, 0), 210),
        ],
      });
      expect(d.nights.single.minutes, 240 + 180);
    });
  });

  test('Λαγοκοίμισμα το βράδυ πριν από τη νύχτα: υπνάκος, όχι αρχή της νύχτας', () {
    int ms(DateTime t) => t.millisecondsSinceEpoch;
    final d = Dashboard.fromJson({
      'readAt': ms(DateTime(2026, 11, 2, 12)),
      'sleep': [
        {'start': ms(DateTime(2026, 11, 1, 21, 0)), 'end': ms(DateTime(2026, 11, 1, 22, 0)), 'minutes': 60, 'stages': []},
        {'start': ms(DateTime(2026, 11, 2, 3, 30)), 'end': ms(DateTime(2026, 11, 2, 9, 0)), 'minutes': 330, 'stages': []},
      ],
    });
    final n = d.nights.single;
    expect(n.date, DateTime(2026, 11, 2));
    expect(n.start, DateTime(2026, 11, 2, 3, 30));
    expect(n.minutes, 330);
  });

  test('Αλλαγή ώρας: κομμάτι που τελειώνει μετά τις 18:00 στις 25/10 ανήκει στη νύχτα της 26/10', () {
    int ms(DateTime t) => t.millisecondsSinceEpoch;
    final d = Dashboard.fromJson({
      'readAt': ms(DateTime(2026, 10, 26, 12)),
      'sleep': [
        {'start': ms(DateTime(2026, 10, 25, 19, 0)), 'end': ms(DateTime(2026, 10, 25, 23, 30)), 'minutes': 270, 'stages': []},
      ],
    });
    expect(d.nights.single.date, DateTime(2026, 10, 26));
  });

  test('Ο χρόνος του κενού δεν μετρά ως «ξύπνιος» στους παλμούς ημέρας', () {
    final linked = Dashboard.fromJson(night()).heartForDay(DateTime(2026, 10, 26))!;
    final unlinked = Dashboard.fromJson(night(gapSteps: 200)).heartForDay(DateTime(2026, 10, 26))!;
    expect(linked.excludedSleepMinutes - unlinked.excludedSleepMinutes, greaterThanOrEqualTo(90));
  });
}
