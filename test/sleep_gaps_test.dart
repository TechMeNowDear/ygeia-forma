import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';

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
  test('Κενό χωρίς βήματα, με παλμούς ύπνου: μία νύχτα, το κενό μετρά ως εκτίμηση', () {
    final d = Dashboard.fromJson(night());
    expect(d.nights.length, 1);
    final n = d.nights.single;
    expect(n.parts.length, 2);
    expect(n.estimatedGaps.length, 1);
    expect(n.estimatedMinutes, 99);
    expect(n.minutes, 63 + 141 + 99);
    expect(n.score, 30, reason: 'η βαθμολογία της Samsung, από το μεγαλύτερο κομμάτι');
  });

  test('Βήματα στο κενό: δεν γεμίζει', () {
    final n = Dashboard.fromJson(night(gapSteps: 200)).nights.single;
    expect(n.estimatedMinutes, 0);
    expect(n.minutes, 63 + 141);
  });

  test('Παλμοί ξύπνιου στο κενό: δεν γεμίζει', () {
    final n = Dashboard.fromJson(night(gapHr: 85)).nights.single;
    expect(n.estimatedMinutes, 0);
  });

  test('Χωρίς στοιχεία βημάτων για το κενό: δεν γεμίζει (δεν μαντεύουμε)', () {
    final n = Dashboard.fromJson(night(stepsKnown: false)).nights.single;
    expect(n.estimatedMinutes, 0);
  });

  test('Δεύτερο κομμάτι μετά τις 10:00 με «καθαρό» κενό: μέρος της νύχτας, όχι υπνάκος', () {
    final d = Dashboard.fromJson(night(secondStart: DateTime(2026, 10, 26, 5, 0).add(const Duration(hours: 5, minutes: 30))));
    // κενό 03:55 → 10:30 = 6,5 ώρες: πάνω από το όριο των 4 ωρών, άρα υπνάκος όπως πριν
    expect(d.nights.single.napMinutes, 141);
    // Κυριακή 25/10: 05:55–09:50 και 10:53–… με κενό 63 λεπτών χωρίς βήματα.
    final sunday = Dashboard.fromJson(night(
      firstStart: DateTime(2026, 10, 26, 5, 55),
      firstEnd: DateTime(2026, 10, 26, 9, 50),
      secondStart: DateTime(2026, 10, 26, 10, 53),
    )).nights;
    expect(sunday.single.napMinutes, 0);
    expect(sunday.single.estimatedMinutes, 63);
  });

  test('Υπνάκος με βήματα πριν: μένει υπνάκος', () {
    final d = Dashboard.fromJson(night(secondStart: DateTime(2026, 10, 26, 10, 53), gapSteps: 300));
    expect(d.nights.single.napMinutes, 141);
    expect(d.nights.single.estimatedMinutes, 0);
  });
}
