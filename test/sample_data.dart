import 'dart:math' as math;

/// Δείγμα δεδομένων στη μορφή που επιστρέφει η γέφυρα Kotlin (DashboardReader),
/// κοντά στα πραγματικά (ύπνος σε κομμάτια, InBody κάθε μερικές εβδομάδες).
Map<String, dynamic> sampleDashboardJson(DateTime now) {
  final rnd = math.Random(7);
  int ms(DateTime t) => t.millisecondsSinceEpoch;
  final today = DateTime(now.year, now.month, now.day);

  final sleep = <Map<String, dynamic>>[];
  final heart = <List<num>>[];
  final spo2 = <List<num>>[];
  final skin = <List<num>>[];
  final stepsMin = <List<num>>[];

  List<List<Object>> stagesFor(DateTime start, DateTime end) {
    final out = <List<Object>>[];
    var t = start;
    const cycle = ['LIGHT', 'DEEP', 'LIGHT', 'REM', 'LIGHT', 'AWAKE'];
    var i = 0;
    while (t.isBefore(end)) {
      final name = cycle[i % cycle.length];
      final len = switch (name) {
        'DEEP' => 15 + rnd.nextInt(20),
        'REM' => 12 + rnd.nextInt(18),
        'AWAKE' => 2 + rnd.nextInt(6),
        _ => 20 + rnd.nextInt(25),
      };
      var e = t.add(Duration(minutes: len));
      if (e.isAfter(end)) e = end;
      out.add([name, ms(t), ms(e)]);
      t = e;
      i++;
    }
    return out;
  }

  for (var d = 30; d >= 1; d--) {
    final wake = today.subtract(Duration(days: d - 1));
    final bed = wake.subtract(const Duration(minutes: 60)).add(Duration(minutes: rnd.nextInt(120)));
    final getUp = wake.add(Duration(hours: 7, minutes: rnd.nextInt(100)));
    final split = d == 1; // η τελευταία νύχτα σε δύο κομμάτια, όπως στην πραγματικότητα
    final parts = split
        ? [
            (DateTime(wake.year, wake.month, wake.day, 1, 20), DateTime(wake.year, wake.month, wake.day, 4, 5)),
            (DateTime(wake.year, wake.month, wake.day, 5, 40), DateTime(wake.year, wake.month, wake.day, 8, 40)),
          ]
        : [(bed, getUp)];
    for (final (s, e) in parts) {
      final minutes = e.difference(s).inMinutes - (split ? 9 : 15);
      sleep.add({
        'start': ms(s),
        'end': ms(e),
        'minutes': minutes,
        'score': split ? 54 : 60 + rnd.nextInt(30),
        'stages': stagesFor(s, e),
      });
      // παλμοί, οξυγόνο, θερμοκρασία στον ύπνο
      for (var t = s; t.isBefore(e); t = t.add(const Duration(minutes: 30))) {
        final hr = 56 + rnd.nextInt(8) + (d < 5 ? 2 : 0);
        heart.add([ms(t), ms(t.add(const Duration(minutes: 30))), hr, hr - 4, hr + 6]);
      }
      final ox = 93 + rnd.nextInt(4);
      spo2.add([ms(s), ms(e), ox, split ? 77 : ox - 4 - rnd.nextInt(3), 98]);
      skin.add([ms(s), ms(e), 34.8 + rnd.nextDouble() * 0.8]);
    }
    // παλμοί μέσα στη μέρα: ανά 4 λεπτά τις τελευταίες 7 μέρες, με βήματα ανά λεπτό
    if (d <= 7) {
      int cadenceAt(DateTime t) {
        final m = t.hour * 60 + t.minute;
        if (m >= 9 * 60 + 30 && m < 10 * 60 + 10) return 90;
        if (m >= 13 * 60 && m < 13 * 60 + 25) return 115;
        if (m >= 18 * 60 && m < 18 * 60 + 40) return 85;
        if (m >= 10 * 60 && m < 17 * 60 && m % 60 < 3) return 30;
        return 0;
      }
      for (var t = wake.add(const Duration(hours: 9)); t.isBefore(wake.add(const Duration(hours: 23))); t = t.add(const Duration(minutes: 4))) {
        if (t.isAfter(now)) break;
        final cad = cadenceAt(t);
        final hr = cad >= 100 ? 108 + rnd.nextInt(8) : cad >= 60 ? 92 + rnd.nextInt(8) : cad > 0 ? 78 + rnd.nextInt(6) : 64 + rnd.nextInt(7);
        heart.add([ms(t), ms(t.add(const Duration(minutes: 4))), hr, hr - 4, hr + 5]);
        if (cad > 0) {
          for (var k = 0; k < 4; k++) {
            stepsMin.add([ms(t.add(Duration(minutes: k))), cad]);
          }
        }
      }
    } else {
      for (var h = 9; h <= 22; h++) {
        final t = wake.add(Duration(hours: h));
        final hr = 70 + rnd.nextInt(18);
        heart.add([ms(t), ms(t.add(const Duration(hours: 1))), hr, hr - 8, hr + 15]);
      }
    }
  }

  final energy = [
    for (var d = 14; d >= 1; d--) [ms(today.subtract(Duration(days: d))), 55 + rnd.nextInt(35)],
  ];
  final steps = [
    for (var d = 30; d >= 0; d--)
      [ms(today.subtract(Duration(days: d))), d == 0 ? 1965 : 1800 + rnd.nextInt(6500)],
  ];
  final floors = [
    for (var d = 14; d >= 0; d--)
      for (var k = 0; k < rnd.nextInt(4); k++) [ms(today.subtract(Duration(days: d)).add(Duration(hours: 10 + k))), 1],
  ];

  final weights = [86.9, 86.1, 85.4, 84.9, 84.2, 83.6, 83.3, 82.2];
  final fat = [28.9, 28.4, 27.9, 27.5, 27.0, 26.6, 26.3, 25.4];
  final smm = [34.1, 34.2, 34.3, 34.2, 34.4, 34.5, 34.6, 34.3];
  final body = [
    for (var i = 0; i < weights.length; i++)
      {
        'time': ms(i == weights.length - 1
            ? DateTime(now.year, now.month, now.day, 16, 13)
            : today.subtract(Duration(days: 300 - i * 38))),
        'weight': weights[i],
        'fatPct': fat[i],
        'fatKg': weights[i] * fat[i] / 100,
        'smm': smm[i],
        'bmi': weights[i] / (1.745 * 1.745),
        'bmr': 1650 + i * 6,
      },
  ];

  return {
    'ok': true,
    'readAt': ms(now),
    'granted': 17,
    'total': 17,
    'sleep': sleep,
    'heart': heart,
    'spo2': spo2,
    'skinTemp': skin,
    'energy': energy,
    'steps': steps,
    'floors': floors,
    'body': body,
    'stepsMin': stepsMin,
    'exercise': <List<num>>[],
    'activity': {'calories': 1237.6, 'activeCalories': 69.8, 'activeMinutes': 21, 'distance': 1489.7},
  };
}
