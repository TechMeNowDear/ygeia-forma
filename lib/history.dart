/// Ημερήσιες συνόψεις: μία εγγραφή ανά μέρα, για Τάσεις και απολογισμούς.
///
/// Υπολογίζονται από τα ίδια δεδομένα και με τους ίδιους κανόνες με τις οθόνες
/// (νύχτες, παλμοί ημέρας), ώστε τα νούμερα να συμφωνούν παντού.
library;

import 'data.dart';
import 'format.dart';
import 'heart_day.dart';

/// Κλειδιά συνόψεων (σταθερά: αποθηκεύονται στη βάση).
abstract final class K {
  static const sleepMin = 'sleepMin';
  static const sleepScore = 'sleepScore';
  static const deepPct = 'deepPct';
  static const remPct = 'remPct';
  static const awakeMin = 'awakeMin';
  static const bedtime = 'bedtime'; // λεπτά μετά τις 18:00
  static const wake = 'wake'; // λεπτά μετά τις 18:00
  static const sleepHr = 'sleepHr';
  static const spo2Avg = 'spo2Avg';
  static const spo2Min = 'spo2Min';
  static const skinTemp = 'skinTemp';
  static const restHr = 'restHr';
  static const dayHr = 'dayHr';
  static const walkHr = 'walkHr';
  static const steps = 'steps';
  static const activeMin = 'activeMin';
  static const calories = 'calories';
  static const energy = 'energy';
  static const weight = 'weight';
  static const fatPct = 'fatPct';
  static const smm = 'smm';
  static const floors = 'floors';
}

/// Τιμές που βγαίνουν από τον ύπνο μιας νύχτας.
const sleepKeys = {
  K.sleepMin, K.sleepScore, K.deepPct, K.remPct, K.awakeMin, K.bedtime, K.wake,
  K.sleepHr, K.spo2Avg, K.spo2Min, K.skinTemp,
};

/// Έκδοση των κανόνων του ιστορικού. Όταν αλλάζει, οι τιμές ύπνου ξαναϋπολογίζονται από την αρχή.
/// 2 (1/11): η «εκτίμηση» στα κενά δεν μετρά στη διάρκεια· σπασμένη νύχτα χωρίς βαθμολογία·
/// διπλές εγγραφές δεν αθροίζονται.
const historyRulesVersion = 2;

/// Βάζει νέες συνόψεις στο [history] και επιστρέφει τις μέρες που άλλαξαν (για αποθήκευση).
///
/// Ο ύπνος κρίνεται με βήματα ανά λεπτό (κενά ανάμεσα στα κομμάτια). Για να έχει **ένα** ορισμό
/// όλο το ιστορικό, οι τιμές ύπνου μιας μέρας γράφονται μόνο όταν υπολογίστηκαν με βήματα:
/// - [sleepFrom]: από αυτή τη μέρα και μετά οι τιμές ύπνου αντικαθίστανται.
/// - πριν από αυτήν (ή αν είναι null): γράφονται μόνο αν η μέρα δεν έχει καθόλου τιμές ύπνου.
/// - [replaceSleep] true: όλες οι τιμές ύπνου των ημερών στο [rangeFrom, rangeTo] αντικαθίστανται
///   (ξαναϋπολογισμός ιστορικού με βήματα), και όσες δεν υπάρχουν πια σβήνονται.
Set<String> mergeHistory(
  Map<String, Map<String, double>> history,
  Map<String, Map<String, double>> rows, {
  DateTime? sleepFrom,
  bool replaceSleep = false,
  DateTime? rangeFrom,
  DateTime? rangeTo,
}) {
  final changed = <String>{};
  if (replaceSleep && rangeFrom != null && rangeTo != null) {
    for (var day = dayOf(rangeFrom); !day.isAfter(dayOf(rangeTo)); day = DateTime(day.year, day.month, day.day + 1)) {
      final k = dateKey(day);
      final old = history[k];
      if (old == null) continue;
      if (old.keys.any(sleepKeys.contains)) {
        history[k] = {for (final e in old.entries) if (!sleepKeys.contains(e.key)) e.key: e.value};
        changed.add(k);
      }
    }
  }
  for (final e in rows.entries) {
    final day = parseDateKey(e.key);
    final old = history[e.key] ?? const <String, double>{};
    final overwriteSleep = replaceSleep || (sleepFrom != null && !day.isBefore(dayOf(sleepFrom)));
    final keepOldSleep = !overwriteSleep && old.keys.any(sleepKeys.contains);
    final incoming = keepOldSleep
        ? {for (final v in e.value.entries) if (!sleepKeys.contains(v.key)) v.key: v.value}
        : e.value;
    final base = overwriteSleep
        ? {for (final v in old.entries) if (!sleepKeys.contains(v.key)) v.key: v.value}
        : old;
    history[e.key] = {...base, ...incoming};
    changed.add(e.key);
  }
  return changed;
}

/// Τα είδη δεδομένων από τα οποία βγαίνουν οι τιμές ύπνου ([sleepKeys]), με τα ονόματα της γέφυρας.
const sleepReadKeys = ['sleep', 'heart', 'stepsMin', 'spo2', 'skinTemp'];

/// Αν σε μια ανάγνωση της γέφυρας κάποιο από τα [sleepReadKeys] γύρισε σφάλμα ({"error": …}).
/// Τότε οι τιμές ύπνου εκείνων των ημερών **δεν** αντικαθίστανται (θα έμεναν κενά).
bool sleepReadFailed(Map<String, dynamic> r) => sleepReadKeys.any((k) {
      final v = r[k];
      return v is Map && v.containsKey('error');
    });

/// «2026-10-24»
String dateKey(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

DateTime parseDateKey(String s) {
  final p = s.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// Λεπτά μετά τις 18:00, ώστε τα μεσάνυχτα να μη «σπάνε» μέσους όρους.
int minutesFromSix(DateTime t) => (t.hour * 60 + t.minute - 18 * 60 + 1440) % 1440;

/// «00:35» από λεπτά μετά τις 18:00.
String clockFromSix(double minutesFromSix) {
  final m = (minutesFromSix.round() + 18 * 60) % 1440;
  return '${two(m ~/ 60)}:${two(m % 60)}';
}

/// Η σύνοψη μιας μέρας. Ό,τι λείπει, απλώς δεν υπάρχει στον χάρτη.
Map<String, double> summarizeDay(Dashboard d, DateTime day) {
  final out = <String, double>{};
  void put(String k, num? v) {
    if (v != null && v.isFinite) out[k] = v.toDouble();
  }

  // Ύπνος: η νύχτα με ημερομηνία το πρωί αυτής της μέρας.
  Night? night;
  for (final n in d.nights) {
    if (sameDay(n.date, day)) night = n;
  }
  if (night != null) {
    put(K.sleepMin, night.minutes);
    put(K.sleepScore, night.score);
    final staged = ['DEEP', 'LIGHT', 'REM', 'AWAKE'].fold<int>(0, (s, k) => s + (night!.stageMinutes[k] ?? 0));
    if (staged > 0) {
      put(K.deepPct, 100 * (night.stageMinutes['DEEP'] ?? 0) / staged);
      put(K.remPct, 100 * (night.stageMinutes['REM'] ?? 0) / staged);
      put(K.awakeMin, night.stageMinutes['AWAKE'] ?? 0);
    }
    put(K.bedtime, minutesFromSix(night.start));
    put(K.wake, minutesFromSix(night.end));
    put(K.sleepHr, night.sleepingHr);
    put(K.spo2Avg, night.spo2Avg);
    put(K.spo2Min, night.spo2Min);
    put(K.skinTemp, night.skinTemp);
  }

  // Παλμοί μέσα στη μέρα (μόνο όταν υπάρχουν βήματα ανά λεπτό).
  final h = d.heartForDay(day);
  if (h != null) {
    put(K.restHr, h.resting.value);
    put(K.dayHr, h.awake.value);
    put(K.walkHr, h.bands[HeartBand.walk]?.value);
  }

  put(K.steps, d.valueFor(d.steps, day)?.value);
  put(K.floors, d.valueFor(d.floors, day)?.value);
  put(K.energy, d.valueFor(d.energy, day)?.value);
  for (final a in d.activityDaily) {
    if (sameDay(a.$1, day)) {
      put(K.activeMin, a.$2);
      put(K.calories, a.$3);
    }
  }

  // Ζύγιση: η τελευταία της μέρας.
  BodyMeasurement? body;
  for (final b in d.body) {
    if (sameDay(b.time, day)) body = b;
  }
  if (body != null) {
    put(K.weight, body.weight);
    put(K.fatPct, body.fatPct);
    put(K.smm, body.smm);
  }
  return out;
}

/// Συνόψεις για κάθε μέρα στο [from, to] (συμπεριλαμβανομένων), μόνο όσες έχουν κάτι.
Map<String, Map<String, double>> summarizeRange(Dashboard d, DateTime from, DateTime to) {
  final out = <String, Map<String, double>>{};
  for (var day = dayOf(from); !day.isAfter(dayOf(to)); day = DateTime(day.year, day.month, day.day + 1)) {
    final s = summarizeDay(d, day);
    if (s.isNotEmpty) out[dateKey(day)] = s;
  }
  return out;
}
