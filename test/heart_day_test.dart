import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/heart_day.dart';

/// Μια μέρα με γνωστά νούμερα, για να ελέγχουμε ότι οι υπολογισμοί βγάζουν ακριβώς ό,τι περιμένουμε.
void main() {
  final day = DateTime(2026, 10, 24);
  int ms(DateTime t) => t.millisecondsSinceEpoch;
  DateTime at(int h, int m) => DateTime(day.year, day.month, day.day, h, m);

  final heart = <List<num>>[];
  void bins(DateTime from, DateTime to, num hr) {
    for (var t = from; t.isBefore(to); t = t.add(const Duration(minutes: 4))) {
      heart.add([ms(t), ms(t.add(const Duration(minutes: 4))), hr, hr - 3, hr + 3]);
    }
  }

  final steps = <List<num>>[];
  void walk(DateTime from, DateTime to, int perMinute) {
    for (var t = from; t.isBefore(to); t = t.add(const Duration(minutes: 1))) {
      steps.add([ms(t), perMinute]);
    }
  }

  bins(at(0, 0), at(7, 0), 55); // ύπνος → εξαιρείται
  walk(at(8, 50), at(9, 0), 100); // περπάτημα πριν κάτσω (χωρίς παλμούς)
  bins(at(9, 0), at(10, 0), 65); // ακινησία· ηρεμία μόνο από 09:20
  bins(at(10, 0), at(10, 40), 95);
  walk(at(10, 0), at(10, 40), 80); // περπάτημα
  bins(at(10, 40), at(11, 0), 110);
  walk(at(10, 40), at(11, 0), 120); // γρήγορο περπάτημα (20 λεπτά → λίγα δεδομένα)
  bins(at(11, 0), at(12, 0), 68); // ακινησία· ηρεμία από 11:20
  bins(at(18, 0), at(19, 0), 140); // άσκηση → εξαιρείται

  final json = {
    'ok': true,
    'readAt': ms(at(20, 0)),
    'granted': 17,
    'total': 17,
    'sleep': [
      {'start': ms(at(0, 0)), 'end': ms(at(7, 0)), 'minutes': 420, 'score': 80, 'stages': []},
    ],
    'heart': heart,
    'stepsMin': steps,
    'exercise': [
      [ms(at(18, 0)), ms(at(19, 0))],
    ],
  };

  final d = Dashboard.fromJson(json);
  final h = d.heartForDay(day)!;

  test('Ύπνος και άσκηση εξαιρούνται', () {
    expect(h.excludedSleepMinutes, closeTo(420, 0.01));
    expect(h.excludedExerciseMinutes, closeTo(60, 0.01));
  });

  test('Ηρεμία μόνο μετά από 20 λεπτά χωρίς βήματα', () {
    expect(h.resting.minutes, closeTo(80, 0.01));
    expect(h.resting.value, 65);
  });

  test('Κατάταξη ανά βήματα', () {
    expect(h.bands[HeartBand.still]!.minutes, closeTo(120, 0.01));
    expect(h.bands[HeartBand.walk]!.value, 95);
    expect(h.bands[HeartBand.walk]!.minutes, closeTo(40, 0.01));
    expect(h.bands[HeartBand.brisk]!.minutes, closeTo(20, 0.01));
    expect(h.bands[HeartBand.brisk]!.value, isNull, reason: 'κάτω από 30 λεπτά');
    expect(h.bands[HeartBand.light]!.value, isNull);
  });

  test('Μέσος όρος ημέρας με βάρος τη διάρκεια', () {
    expect(h.awake.value!, closeTo(13980 / 180, 0.01));
  });

  test('Διάρκεια μέτρησης', () {
    expect(h.typicalInterval, closeTo(4, 0.01));
  });
}
