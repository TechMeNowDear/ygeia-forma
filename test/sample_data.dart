import 'dart:math' as math;

import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/history.dart';

/// Η εφαρμογή της InBody στη Samsung Health (Google Play: com.inbody2014.inbody).
const inbodyApp = 'com.inbody2014.inbody';

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
    // Στο κενό ανάμεσα στα κομμάτια το ρολόι συνεχίζει να μετρά: παλμοί ύπνου, κανένα βήμα.
    if (split) {
      for (var t = parts[0].$2; t.isBefore(parts[1].$1); t = t.add(const Duration(minutes: 30))) {
        final hr = 58 + rnd.nextInt(4);
        heart.add([ms(t), ms(t.add(const Duration(minutes: 30))), hr, hr - 4, hr + 5]);
      }
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
        'app': inbodyApp,
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
    'stepsFrom': ms(today.subtract(const Duration(days: 6))),
    'exercise': <List<num>>[],
    'activity': {'calories': 1237.6, 'activeCalories': 69.8, 'activeMinutes': 21, 'distance': 1489.7},
  };
}

/// Ιστορικό 12 μηνών για τα στιγμιότυπα των Τάσεων: οι τελευταίες 30 μέρες από το δείγμα
/// (ίδιοι υπολογισμοί με την εφαρμογή), οι παλιότερες συνθετικές με γνωστές αλλαγές.
Map<String, Map<String, double>> sampleHistory(DateTime now, Dashboard d) {
  final rnd = math.Random(11);
  final today = DateTime(now.year, now.month, now.day);
  double noise(double a) => (rnd.nextDouble() * 2 - 1) * a;
  final out = <String, Map<String, double>>{};
  for (var ago = 364; ago > 30; ago--) {
    final day = DateTime(today.year, today.month, today.day - ago);
    final old = ago > 60; // πριν από 2 μήνες: λίγο χειρότερη φόρμα
    out[dateKey(day)] = {
      K.sleepMin: (old ? 405 : 415) + noise(45),
      K.sleepScore: (old ? 74 : 77) + noise(8),
      K.deepPct: 15 + noise(4),
      K.remPct: 21 + noise(4),
      K.awakeMin: 22 + noise(10),
      K.bedtime: 330 + noise(40),
      K.sleepHr: (old ? 63 : 61) + noise(2.5),
      K.spo2Avg: 95 + noise(1),
      K.skinTemp: 33.6 + noise(0.3),
      K.restHr: (old ? 70 : 68) + noise(3),
      K.walkHr: (old ? 101 : 98) + noise(5),
      K.dayHr: (old ? 77 : 75) + noise(3),
      K.steps: 7200 + noise(3000),
      K.activeMin: 55 + noise(25),
      K.energy: (old ? 68 : 71) + noise(10),
    };
  }
  final recent = summarizeRange(d, DateTime(today.year, today.month, today.day - 30), today);
  for (final b in d.body) {
    recent[dateKey(b.time)] = {
      ...?recent[dateKey(b.time)],
      if (b.weight != null) K.weight: b.weight!,
      if (b.fatPct != null) K.fatPct: b.fatPct!,
      if (b.smm != null) K.smm: b.smm!,
    };
  }
  out.addAll(recent);
  return out;
}

/// Δείγμα Oura για τα στιγμιότυπα: σύνδεση στις [ouraFrom], νύχτες ως το πρωί του [now] (εκτός από [missing]),
/// με τις ίδιες μετατροπές που κάνει η εφαρμογή (ouraRows → ιστορικό με κλειδιά «o.*»).
List<Map<String, dynamic>> sampleOuraSleep(DateTime ouraFrom, DateTime now, {Set<DateTime> missing = const {}}) {
  final rnd = math.Random(5);
  final out = <Map<String, dynamic>>[];
  String iso(DateTime t) => t.toUtc().toIso8601String();
  const phases = '4422211112223332222111222333322224222111222333222111223332222244';
  for (var d = DateTime(ouraFrom.year, ouraFrom.month, ouraFrom.day); !d.isAfter(now); d = DateTime(d.year, d.month, d.day + 1)) {
    if (missing.any((m) => m.year == d.year && m.month == d.month && m.day == d.day)) continue;
    final bed = DateTime(d.year, d.month, d.day - 1, 23, 40).add(Duration(minutes: rnd.nextInt(80)));
    final wake = DateTime(d.year, d.month, d.day, 7, 0).add(Duration(minutes: rnd.nextInt(90)));
    final inBed = wake.difference(bed).inSeconds;
    final latency = 600 + rnd.nextInt(900);
    final awake = 1200 + rnd.nextInt(1500);
    final total = inBed - latency - awake;
    final deep = (total * (0.14 + rnd.nextDouble() * 0.05)).round();
    final rem = (total * (0.2 + rnd.nextDouble() * 0.05)).round();
    out.add({
      'id': 'sample-${d.month}-${d.day}',
      'day': '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      'type': 'long_sleep',
      'bedtime_start': iso(bed),
      'bedtime_end': iso(wake),
      'time_in_bed': inBed,
      'total_sleep_duration': total,
      'deep_sleep_duration': deep,
      'rem_sleep_duration': rem,
      'light_sleep_duration': total - deep - rem,
      'awake_time': awake,
      'latency': latency,
      'efficiency': 85 + rnd.nextInt(8),
      'lowest_heart_rate': 51 + rnd.nextInt(5),
      'average_heart_rate': 57 + rnd.nextDouble() * 5,
      'average_hrv': 32 + rnd.nextInt(14),
      'average_breath': 13.6 + rnd.nextDouble(),
      'sleep_phase_5_min': phases.substring(0, (inBed / 300).floor().clamp(1, phases.length)),
      'period': 0,
      'low_battery_alert': false,
    });
  }
  return out;
}
