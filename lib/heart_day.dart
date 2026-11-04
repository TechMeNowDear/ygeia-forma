/// Παλμοί μέσα στη μέρα, ανά κατάσταση (ακινησία, περπάτημα κ.λπ.).
///
/// Ορισμοί και κανόνες ακρίβειας: έγγραφο προδιαγραφών › «Παλμοί μέσα στη μέρα».
/// - Κατάσταση από τα βήματα στο ίδιο διάστημα με τη μέτρηση παλμών.
/// - Ηρεμία (ξύπνιος): χωρίς βήματα στη μέτρηση ΚΑΙ στα προηγούμενα 20 λεπτά.
/// - Εξαιρούνται ύπνος και ασκήσεις.
/// - Διάμεσος με βάρος τη διάρκεια· κάτω από 30 λεπτά δεδομένων δεν βγαίνει τιμή.
/// - «Μέσος όρος ημέρας» (ξύπνιος, όλες οι καταστάσεις): μόνο με τουλάχιστον 6 ώρες μετρήσεων (δεύτερος έλεγχος
///   υπολογισμών C11). Πριν αρκούσαν 30 λεπτά: μια μέρα με το ρολόι 35 λεπτά το βράδυ έδινε «μέσο όρο ημέρας» ίσο
///   με τους παλμούς ηρεμίας και μετρούσε στις Τάσεις.
library;

import 'data.dart';
import 'format.dart';

enum HeartBand { still, light, walk, brisk }

const minMinutesForValue = 30;
const minMinutesForDayValue = 360;
const restLeadMinutes = 20;

String bandLabel(HeartBand b) => switch (b) {
      HeartBand.still => 'Ακινησία',
      HeartBand.light => 'Λίγη κίνηση',
      HeartBand.walk => 'Περπάτημα',
      HeartBand.brisk => 'Γρήγορο περπάτημα',
    };

String bandHint(HeartBand b) => switch (b) {
      HeartBand.still => 'χωρίς βήματα',
      HeartBand.light => 'κάτω από 60 βήματα το λεπτό',
      HeartBand.walk => '60–99 βήματα το λεπτό',
      HeartBand.brisk => '100+ βήματα το λεπτό',
    };

/// Μία τιμή με τον χρόνο που τη στηρίζει.
class HeartFigure {
  const HeartFigure(this.value, this.minutes);

  /// null όταν ο χρόνος είναι κάτω από [minMinutesForValue].
  final double? value;
  final double minutes;

  bool get enough => value != null;
}

class DayHeart {
  DayHeart({
    required this.day,
    required this.samples,
    required this.typicalInterval,
    required this.excludedSleepMinutes,
    required this.excludedExerciseMinutes,
    required this.awake,
    required this.resting,
    required this.bands,
  });

  final DateTime day;

  /// Μετρήσεις παλμών μέσα στη μέρα (όλες, πριν από τις εξαιρέσεις).
  final int samples;

  /// Συνηθισμένη διάρκεια μιας μέτρησης σε λεπτά (διάμεσος).
  final double? typicalInterval;
  final double excludedSleepMinutes;
  final double excludedExerciseMinutes;

  /// Μέσος όρος ημέρας (ξύπνιος), με βάρος τη διάρκεια.
  final HeartFigure awake;

  /// Παλμοί ηρεμίας, ξύπνιος (διάμεσος).
  final HeartFigure resting;

  final Map<HeartBand, HeartFigure> bands;
}

class _W {
  _W(this.value, this.weight);
  final double value;
  final double weight;
}

double? weightedMedian(List<_W> items) {
  if (items.isEmpty) return null;
  final sorted = [...items]..sort((a, b) => a.value.compareTo(b.value));
  final total = sorted.fold<double>(0, (s, w) => s + w.weight);
  if (total <= 0) return null;
  var acc = 0.0;
  for (final w in sorted) {
    acc += w.weight;
    if (acc >= total / 2) return w.value;
  }
  return sorted.last.value;
}

double? weightedMean(List<_W> items) {
  final total = items.fold<double>(0, (s, w) => s + w.weight);
  if (total <= 0) return null;
  return items.fold<double>(0, (s, w) => s + w.value * w.weight) / total;
}

extension HeartByDay on Dashboard {
  /// Αν υπάρχουν βήματα ανά λεπτό για αυτή τη μέρα (χωρίς αυτά δεν ξέρουμε την κατάσταση).
  bool hasStepCoverage(DateTime day) {
    final from = stepsMinuteFrom;
    return from != null && !dayOf(day).isBefore(dayOf(from));
  }

  int _stepsBetween(DateTime a, DateTime b) {
    var total = 0;
    final startMin = a.millisecondsSinceEpoch ~/ 60000;
    final endMin = (b.millisecondsSinceEpoch + 59999) ~/ 60000;
    for (var m = startMin; m < endMin; m++) {
      total += stepsByMinute[m] ?? 0;
    }
    return total;
  }

  bool _overlaps(Sample s, List<(DateTime, DateTime)> ranges) =>
      ranges.any((r) => s.start.isBefore(r.$2) && s.end.isAfter(r.$1));

  /// [sleepRanges]: ποιες ώρες εξαιρούνται ως ύπνος. Χωρίς αυτό: ο ύπνος της Samsung (πριν από το Oura).
  /// Μετά τη σύνδεση του Oura τις δίνει ο υπολογισμός του ιστορικού από την πηγή κάθε νύχτας.
  DayHeart? heartForDay(DateTime day, {List<(DateTime, DateTime)>? sleepRanges}) {
    if (!hasStepCoverage(day)) return null;
    final start = dayOf(day);
    final end = DateTime(start.year, start.month, start.day + 1); // ημερολογιακή μέρα (23/25 ώρες στην αλλαγή ώρας)
    final daySamples = heart.where((h) => !h.start.isBefore(start) && h.start.isBefore(end)).toList();
    if (daySamples.isEmpty) return null;

    // Έξω από τον «ξύπνιο» χρόνο: ο ύπνος της Samsung και τα κενά με παλμούς ύπνου ανάμεσα στα
    // κομμάτια (δεν ξέρουμε αν κοιμόσουν, άρα δεν μετρούν ούτε ως ύπνος ούτε ως ηρεμία).
    final ranges = sleepRanges ??
        [
          for (final r in sleepRecords) (r.start, r.end),
          for (final n in nights) ...n.estimatedGaps,
        ];

    var sleepMinutes = 0.0;
    var exerciseMinutes = 0.0;
    final intervals = <double>[];
    final awake = <_W>[];
    final resting = <_W>[];
    final bands = {for (final b in HeartBand.values) b: <_W>[]};

    for (final s in daySamples) {
      final minutes = s.end.difference(s.start).inSeconds / 60;
      final dur = minutes > 0 ? minutes : 1.0;
      intervals.add(dur);
      if (_overlaps(s, ranges)) {
        sleepMinutes += dur;
        continue;
      }
      if (_overlaps(s, exercise)) {
        exerciseMinutes += dur;
        continue;
      }
      // Στιγμιαία μέτρηση (αρχή = τέλος): το λεπτό της, όπως και στη διάρκεια (dur = 1).
      final steps = _stepsBetween(s.start, s.end.isAfter(s.start) ? s.end : s.start.add(const Duration(minutes: 1)));
      final cadence = steps / dur;
      final band = steps == 0
          ? HeartBand.still
          : cadence < 60
              ? HeartBand.light
              : cadence < 100
                  ? HeartBand.walk
                  : HeartBand.brisk;
      final w = _W(s.avg, dur);
      awake.add(w);
      bands[band]!.add(w);
      if (steps == 0 && _stepsBetween(s.start.subtract(const Duration(minutes: restLeadMinutes)), s.start) == 0) {
        resting.add(w);
      }
    }

    double minutesOf(List<_W> l) => l.fold<double>(0, (t, w) => t + w.weight);
    HeartFigure figure(List<_W> l, {bool mean = false, num min = minMinutesForValue}) {
      final m = minutesOf(l);
      if (m < min) return HeartFigure(null, m);
      return HeartFigure(mean ? weightedMean(l) : weightedMedian(l), m);
    }

    intervals.sort();
    return DayHeart(
      day: start,
      samples: daySamples.length,
      typicalInterval: intervals.isEmpty ? null : intervals[intervals.length ~/ 2],
      excludedSleepMinutes: sleepMinutes,
      excludedExerciseMinutes: exerciseMinutes,
      awake: figure(awake, mean: true, min: minMinutesForDayValue),
      resting: figure(resting),
      bands: {for (final b in HeartBand.values) b: figure(bands[b]!)},
    );
  }

  /// Παλμοί ηρεμίας (ξύπνιος) για τις τελευταίες μέρες με βήματα ανά λεπτό, παλιότερη πρώτη.
  List<DayHeart> recentHeartDays([int days = 7]) {
    final out = <DayHeart>[];
    for (var i = days - 1; i >= 0; i--) {
      final today = dayOf(readAt);
      final d = heartForDay(DateTime(today.year, today.month, today.day - i));
      if (d != null) out.add(d);
    }
    return out;
  }
}
