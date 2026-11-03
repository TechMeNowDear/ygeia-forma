/// Ημερήσιες συνόψεις: μία εγγραφή ανά μέρα, για Τάσεις και απολογισμούς.
///
/// Υπολογίζονται από τα ίδια δεδομένα και με τους ίδιους κανόνες με τις οθόνες
/// (νύχτες, παλμοί ημέρας), ώστε τα νούμερα να συμφωνούν παντού.
library;

import 'data.dart';
import 'format.dart';
import 'heart_day.dart';
import 'sources.dart';

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
  /// Λεπτά με οξυγόνο κάτω από 90% (ενδεικτικό· μόνο όταν βγαίνει από τις αναλυτικές μετρήσεις).
  static const spo2Low = 'spo2Low';
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
  // Μόνο από το Oura (αποθηκεύονται με πρόθεμα «o.», δες sources.dart).
  static const napMin = 'napMin';
  static const lowHr = 'lowHr';
  static const hrv = 'hrv';
  static const breath = 'breath';
}

/// Τιμές που βγαίνουν από τον ύπνο μιας νύχτας.
const sleepKeys = {
  K.sleepMin, K.sleepScore, K.deepPct, K.remPct, K.awakeMin, K.bedtime, K.wake,
  K.sleepHr, K.spo2Avg, K.spo2Min, K.spo2Low, K.skinTemp,
};

/// Έκδοση των κανόνων του ιστορικού. Όταν αλλάζει, οι τιμές ύπνου ξαναϋπολογίζονται από την αρχή.
/// 2 (1/11): η «εκτίμηση» στα κενά δεν μετρά στη διάρκεια· σπασμένη νύχτα χωρίς βαθμολογία·
/// διπλές εγγραφές δεν αθροίζονται.
/// 3 (4/11, έλεγχος): ποσοστά σταδίων επί του πραγματικού ύπνου (χωρίς τα ξυπνήματα).
const historyRulesVersion = 3;

/// Βάζει νέες συνόψεις στο [history] και επιστρέφει τις μέρες που άλλαξαν (για αποθήκευση).
///
/// Ο ύπνος κρίνεται με βήματα ανά λεπτό (κενά ανάμεσα στα κομμάτια). Για να έχει **ένα** ορισμό
/// όλο το ιστορικό, οι τιμές ύπνου μιας μέρας γράφονται μόνο όταν υπολογίστηκαν με βήματα:
/// - [sleepFrom]: από αυτή τη μέρα και μετά οι τιμές ύπνου αντικαθίστανται.
/// - πριν από αυτήν (ή αν είναι null): γράφονται μόνο αν η μέρα δεν έχει καθόλου τιμές ύπνου.
/// - [replaceSleep] true: όλες οι τιμές ύπνου των ημερών στο [rangeFrom, rangeTo] αντικαθίστανται
///   (ξαναϋπολογισμός ιστορικού με βήματα), και όσες δεν υπάρχουν πια σβήνονται.
///
/// [plan]: τις μέρες που η «νύχτα» ΔΕΝ έρχεται από το ρολόι (Oura ή καμία πηγή), οι τιμές νύχτας του
/// ρολογιού δεν γράφονται ποτέ (και όσες υπήρχαν φεύγουν)· μένει μόνο το οξυγόνο, που είναι πάντα του ρολογιού.
/// Οι τιμές του Oura («o.*») δεν αγγίζονται εδώ (δες [mergeOura]).
Set<String> mergeHistory(
  Map<String, Map<String, double>> history,
  Map<String, Map<String, double>> rows, {
  DateTime? sleepFrom,
  bool replaceSleep = false,
  DateTime? rangeFrom,
  DateTime? rangeTo,
  SourcePlan? plan,
}) {
  final changed = <String>{};
  final p = plan ?? SourcePlan.samsungOnly;
  if (replaceSleep && rangeFrom != null && rangeTo != null) {
    for (var day = dayOf(rangeFrom); !day.isAfter(dayOf(rangeTo)); day = DateTime(day.year, day.month, day.day + 1)) {
      final k = dateKey(day);
      final old = history[k];
      if (old == null) continue;
      // Η νύχτα του ρολογιού την πρώτη μέρα μιας εποχής Oura δεν σβήνεται ποτέ ([SourcePlan.keepsWatchNight]).
      final keep = p.keepsWatchNight(day);
      bool drop(String key) => sleepKeys.contains(key) && !(keep && watchNightKeys.contains(key));
      if (old.keys.any(drop)) {
        history[k] = {for (final e in old.entries) if (!drop(e.key)) e.key: e.value};
        changed.add(k);
      }
    }
  }
  for (final e in rows.entries) {
    final day = parseDateKey(e.key);
    final old = history[e.key] ?? const <String, double>{};
    // Μέρα που η νύχτα δεν είναι του ρολογιού: οι τιμές νύχτας του ρολογιού δεν μπαίνουν ποτέ, και το
    // οξυγόνο (το μόνο του ρολογιού εδώ, χωρίς ομαδοποίηση ύπνου) ανανεώνεται πάντα.
    final foreignNight = p.nightSource(day) != Source.watch;
    final keep = p.keepsWatchNight(day);
    final row = foreignNight
        ? {for (final v in e.value.entries) if (!watchNightKeys.contains(v.key)) v.key: v.value}
        : e.value;
    // Το οξυγόνο τέτοιων ημερών δεν θέλει βήματα ανά λεπτό: ανανεώνεται σε κάθε αξιόπιστη ανάγνωση
    // (όχι όταν απέτυχε κάποιο είδος του ύπνου, που τότε το [sleepFrom] είναι null).
    final trusted = replaceSleep || sleepFrom != null;
    final overwriteSleep = replaceSleep || (sleepFrom != null && !day.isBefore(dayOf(sleepFrom))) || (foreignNight && trusted);
    final keepOldSleep = !overwriteSleep && old.keys.any(sleepKeys.contains);
    final incoming = keepOldSleep
        ? {for (final v in row.entries) if (!sleepKeys.contains(v.key)) v.key: v.value}
        : row;
    final base = overwriteSleep
        ? {
            for (final v in old.entries)
              if ((keep && watchNightKeys.contains(v.key)) ||
                  (!sleepKeys.contains(v.key) && !(foreignNight && watchNightKeys.contains(v.key))))
                v.key: v.value,
          }
        : old;
    final next = {...base, ...incoming};
    // Μόνο ό,τι άλλαξε γράφεται ξανά στο κινητό.
    if (!_sameValues(history[e.key], next)) changed.add(e.key);
    history[e.key] = next;
  }
  return changed;
}

/// Βάζει τις τιμές του Oura ([rows], κλειδιά «o.*») για τις μέρες [from, to] και επιστρέφει όσες άλλαξαν.
/// Η ανάγνωση του διαστήματος ήταν πλήρης: ό,τι δεν ήρθε για μια μέρα (π.χ. σβήστηκε στην Oura) φεύγει.
/// Γράφονται μόνο οι μέρες που η «νύχτα» έρχεται από το Oura· οι άλλες αγνοούνται.
Set<String> mergeOura(
  Map<String, Map<String, double>> history,
  Map<String, Map<String, double>> rows, {
  required DateTime from,
  required DateTime to,
  required SourcePlan plan,
}) {
  final changed = <String>{};
  for (var day = dayOf(from); !day.isAfter(dayOf(to)); day = DateTime(day.year, day.month, day.day + 1)) {
    if (plan.nightSource(day) != Source.oura) continue;
    final k = dateKey(day);
    final old = history[k] ?? const <String, double>{};
    final next = {
      for (final v in old.entries) if (!ouraKeySet.contains(v.key)) v.key: v.value,
      for (final v in (rows[k] ?? const <String, double>{}).entries)
        if (ouraKeySet.contains(v.key) && v.value.isFinite) v.key: v.value,
    };
    if (next.isEmpty && history[k] == null) continue;
    if (!_sameValues(history[k], next)) changed.add(k);
    history[k] = next;
  }
  return changed;
}

/// Σβήνει τις τιμές νύχτας του ρολογιού από τις μέρες (από [from] και μετά) που η νύχτα έχει άλλη πηγή.
/// Εξαίρεση: η πρώτη νύχτα μιας εποχής Oura ([SourcePlan.keepsWatchNight]) — αν το ρολόι την είχε ήδη γράψει,
/// μένει (κρυφή).
Set<String> stripForeignWatchNight(Map<String, Map<String, double>> history, SourcePlan plan, {required DateTime from}) {
  final changed = <String>{};
  final fromKey = dateKey(from);
  for (final e in history.entries.toList()) {
    // Τα κλειδιά «2026-11-06» ταξινομούνται σαν ημερομηνίες: οι παλιές μέρες προσπερνιούνται χωρίς ανάλυση.
    if (e.key.compareTo(fromKey) < 0) continue;
    final day = parseDateKey(e.key);
    if (plan.nightSource(day) == Source.watch || plan.keepsWatchNight(day)) continue;
    if (!e.value.keys.any(watchNightKeys.contains)) continue;
    history[e.key] = {for (final v in e.value.entries) if (!watchNightKeys.contains(v.key)) v.key: v.value};
    changed.add(e.key);
  }
  return changed;
}

/// Πόσες μέρες στο [from, to] έχουν ήδη ύπνο στο ιστορικό.
int sleepDaysIn(Map<String, Map<String, double>> history, DateTime from, DateTime to) {
  var n = 0;
  for (var d = dayOf(from); !d.isAfter(dayOf(to)); d = DateTime(d.year, d.month, d.day + 1)) {
    if (history[dateKey(d)]?.containsKey(K.sleepMin) ?? false) n++;
  }
  return n;
}

/// Τιμές που έρχονται από τις ζυγίσεις.
const bodyKeys = {K.weight, K.fatPct, K.smm};

/// Σβήνει τις τιμές ζύγισης από μέρες (από [from] και μετά) που δεν έχουν πια ζύγιση στη Samsung
/// (π.χ. σβήστηκε μια λάθος ζύγιση). [bodyDays]: οι μέρες με ζύγιση τώρα. Επιστρέφει τις μέρες που άλλαξαν.
Set<String> removeMissingBody(Map<String, Map<String, double>> history, Set<String> bodyDays, {required DateTime from}) {
  final changed = <String>{};
  for (final e in history.entries.toList()) {
    if (bodyDays.contains(e.key) || !e.value.keys.any(bodyKeys.contains)) continue;
    if (parseDateKey(e.key).isBefore(dayOf(from))) continue;
    history[e.key] = {for (final v in e.value.entries) if (!bodyKeys.contains(v.key)) v.key: v.value};
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

/// Η σύνοψη μιας μέρας από τα δεδομένα της Samsung (ρολόι, ζυγαριά). Ό,τι λείπει, απλώς δεν υπάρχει στον χάρτη.
///
/// [plan]: τις μέρες που η «νύχτα» δεν είναι του ρολογιού, δεν βγαίνει καμία τιμή νύχτας από το ρολόι (ύπνος,
/// παλμοί ύπνου, θερμοκρασία, βαθμολογία, Energy Score)· μόνο το οξυγόνο της νύχτας, με ορισμό που δεν χρειάζεται
/// τον ύπνο του ρολογιού ([Dashboard.watchSpo2]).
/// [windows]: οι ώρες ύπνου του Oura, μόνο για να εξαιρούνται από τους παλμούς της μέρας.
Map<String, double> summarizeDay(Dashboard d, DateTime day, {SourcePlan? plan, SleepWindows windows = SleepWindows.empty}) {
  final p = plan ?? SourcePlan.samsungOnly;
  final out = <String, double>{};
  void put(String k, num? v) {
    if (v != null && v.isFinite) out[k] = v.toDouble();
  }

  final watchNight = p.nightSource(day) == Source.watch;

  // Ύπνος: η νύχτα με ημερομηνία το πρωί αυτής της μέρας.
  Night? night;
  for (final n in d.nights) {
    if (sameDay(n.date, day)) night = n;
  }
  if (!watchNight) {
    final ox = d.watchSpo2(day);
    if (ox != null) {
      put(K.spo2Avg, ox.avg);
      put(K.spo2Min, ox.min);
      put(K.spo2Low, ox.below90);
    }
  } else if (night != null) {
    put(K.sleepMin, night.minutes);
    put(K.sleepScore, night.score);
    // Ποσοστά επί του πραγματικού ύπνου (βαθύς + ελαφρύς + REM), όπως στο Oura· ο χρόνος ξύπνιος χωριστά σε λεπτά
    // (έλεγχος 4/11, B4: πριν, ποσοστά επί του χρόνου μαζί με τα ξυπνήματα).
    final staged = ['DEEP', 'LIGHT', 'REM', 'AWAKE'].fold<int>(0, (s, k) => s + (night!.stageMinutes[k] ?? 0));
    if (staged > 0) {
      put(K.deepPct, night.stagePct('DEEP'));
      put(K.remPct, night.stagePct('REM'));
      put(K.awakeMin, night.stageMinutes['AWAKE'] ?? 0);
    }
    put(K.bedtime, minutesFromSix(night.start));
    put(K.wake, minutesFromSix(night.end));
    put(K.sleepHr, night.sleepingHr);
    put(K.spo2Avg, night.spo2Avg);
    put(K.spo2Min, night.spo2Min);
    put(K.spo2Low, night.spo2Below90);
    put(K.skinTemp, night.skinTemp);
  }

  // Παλμοί μέσα στη μέρα (μόνο όταν υπάρχουν βήματα ανά λεπτό).
  // Ο ύπνος που εξαιρείται έρχεται από την πηγή ΚΑΘΕ νύχτας (της νύχτας που τελειώνει το πρωί και αυτής που
  // αρχίζει το βράδυ), όχι από το «αν συνδέθηκε ποτέ το Oura». Με το ρολόι και στις δύο: όπως πάντα.
  final next = DateTime(day.year, day.month, day.day + 1);
  final planned = p.nightSource(day) != Source.watch || p.nightSource(next) != Source.watch;
  final h = planned ? _heartWithPlan(d, day, p, windows) : d.heartForDay(day);
  if (h != null) {
    // Υπολογίζονται και κρατιούνται (για αργότερα), αλλά δεν φαίνονται πια: δικοί μας ορισμοί χωρίς επαλήθευση.
    put(K.restHr, h.resting.value);
    put(K.dayHr, h.awake.value);
    put(K.walkHr, h.bands[HeartBand.walk]?.value);
  }

  put(K.steps, d.valueFor(d.steps, day)?.value);
  put(K.floors, d.valueFor(d.floors, day)?.value);
  // Energy Score: της ίδιας ομάδας με τη νύχτα (μετά τη σύνδεση τη θέση του παίρνει η ετοιμότητα του Oura).
  if (watchNight) put(K.energy, d.valueFor(d.energy, day)?.value);
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

/// Παλμοί μέρας όταν υπάρχει Oura στο σχέδιο: ο ύπνος που εξαιρείται έρχεται από την πηγή κάθε νύχτας
/// (της νύχτας που τελειώνει το πρωί και αυτής που αρχίζει το βράδυ). Αν μία από τις δύο δεν είναι γνωστή,
/// δεν βγαίνει τιμή: αλλιώς ο ύπνος θα μετρούσε ως «μέρα». Οι τιμές είναι πάντα μόνο του ρολογιού.
DayHeart? _heartWithPlan(Dashboard d, DateTime day, SourcePlan p, SleepWindows windows) {
  final today = dayOf(d.readAt);
  final ranges = <(DateTime, DateTime)>[];
  var watchAdded = false;
  var ouraAdded = false;
  for (final n in [dayOf(day), DateTime(day.year, day.month, day.day + 1)]) {
    if (n.isAfter(today)) continue; // η νύχτα του απόψε δεν έχει γίνει ακόμα
    switch (p.nightSource(n)) {
      case Source.watch:
        if (!d.sleepOk) return null;
        if (!watchAdded) {
          watchAdded = true;
          // Μόνο ύπνος του ρολογιού από νύχτες που η πηγή τους είναι το ρολόι (ποτέ από νύχτες του Oura).
          DateTime nightOf(DateTime end) => end.hour >= 18 ? DateTime(end.year, end.month, end.day + 1) : dayOf(end);
          ranges.addAll([
            for (final r in d.sleepRecords)
              if (p.nightSource(nightOf(r.end)) == Source.watch) (r.start, r.end),
            for (final x in d.nights)
              if (p.nightSource(x.date) == Source.watch) ...x.estimatedGaps,
          ]);
        }
      case Source.oura:
        if (!windows.mains.containsKey(dateKey(n))) return null;
        if (!ouraAdded) {
          ouraAdded = true;
          ranges.addAll(windows.ranges);
        }
      case Source.none:
      case Source.scale:
        return null;
    }
  }
  return d.heartForDay(day, sleepRanges: ranges);
}

/// Συνόψεις για κάθε μέρα στο [from, to] (συμπεριλαμβανομένων), μόνο όσες έχουν κάτι.
Map<String, Map<String, double>> summarizeRange(Dashboard d, DateTime from, DateTime to,
    {SourcePlan? plan, SleepWindows windows = SleepWindows.empty}) {
  final out = <String, Map<String, double>>{};
  for (var day = dayOf(from); !day.isAfter(dayOf(to)); day = DateTime(day.year, day.month, day.day + 1)) {
    final s = summarizeDay(d, day, plan: plan, windows: windows);
    if (s.isNotEmpty) out[dateKey(day)] = s;
  }
  return out;
}

bool _sameValues(Map<String, double>? a, Map<String, double> b) {
  if (a == null || a.length != b.length) return false;
  for (final e in b.entries) {
    if (a[e.key] != e.value) return false;
  }
  return true;
}
