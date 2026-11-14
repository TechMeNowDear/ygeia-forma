/// Τα δεδομένα του Oura (API v2), όπως τα δίνει η Oura, και οι μετατροπές τους.
///
/// Πεδία επαληθευμένα στο επίσημο OpenAPI 1.43 (PublicModifiedSleepModel, PublicDailySleep,
/// PublicDailyReadiness) και στο sandbox της Oura. Κανόνες:
/// - Ό,τι λείπει (null) μένει κενό· ποτέ 0.
/// - Νύχτα και υπνάκοι: ο ΙΔΙΟΣ κανόνας με το ρολόι ([groupOura] → groupSleepPieces, συγχώνευση 4/11): κομμάτια
///   με κενό ως 4 ώρες = μία νύχτα (το κενό δεν μετρά)· λαγοκοίμισμα ως τις 22:00, πρωινό κομμάτι με κενό πάνω από
///   90 λεπτά και απογευματινό κάτω από 3 ώρες = υπνάκοι (χωριστά, δεν προστίθενται). Ο τύπος της Oura διαλέγει μόνο
///   την κύρια περίοδο (long_sleep με τον περισσότερο ύπνο, αλλιώς η μεγαλύτερη). «Σύντομη νύχτα»: κάτω από 3 ώρες.
///   Οι «rest» (λάθος ανίχνευση που απέρριψε ο χρήστης) και «deleted» αγνοούνται.
/// - Η μέρα κάθε νύχτας είναι το «day» της Oura (της μεγαλύτερης περιόδου: το πρωί που ξύπνησες).
/// - Οι ώρες έρχονται με τη ζώνη ώρας τους (π.χ. +02:00). Round 1 (S5-1): η ζώνη κρατιέται ([OuraSleep.offsetMin])·
///   «νύχτα ή υπνάκος» κρίνεται και οι ώρες δείχνονται στην ώρα του τόπου όπου κοιμήθηκες ([OuraSleep.wallStart]),
///   όχι στη ζώνη που έχει το κινητό όταν διαβάζει. Εγγραφή στη ζώνη του κινητού ή χωρίς ζώνη: όπως πάντα.
library;

import 'dart:convert';

import '../data.dart' show Stage, Night;
import '../format.dart';
import '../history.dart';
import '../sleep_gaps.dart' show groupSleepPieces;
import '../sources.dart';

int? _int(Object? v) => v is num && v.isFinite ? v.round() : null;
double? _dbl(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

DateTime? _time(Object? v) {
  if (v is! String) return null;
  try {
    return DateTime.parse(v).toLocal();
  } catch (_) {
    return null;
  }
}

/// Round 1 (S5-1): η ζώνη ώρας στο τέλος μιας ώρας ISO 8601 («…+02:00», «…-0800»), σε λεπτά ανατολικά του UTC.
/// Χωρίς ζώνη ή «Z» (UTC χωρίς τόπο): null, δηλαδή «άγνωστη» (ισχύει η ώρα του κινητού, όπως πριν).
int? _isoOffset(Object? v) {
  if (v is! String) return null;
  final m = RegExp(r'([+-])(\d{2}):?(\d{2})$').firstMatch(v);
  if (m == null) return null;
  final minutes = int.parse(m.group(2)!) * 60 + int.parse(m.group(3)!);
  return _offsetOk(m.group(1) == '-' ? -minutes : minutes);
}

/// Μόνο ζώνες που υπάρχουν (−12:00 … +14:00)· ό,τι άλλο = άγνωστη.
int? _offsetOk(Object? v) => v is num && v.isFinite && v >= -12 * 60 && v <= 14 * 60 ? v.round() : null;

/// Η στιγμή [t] ως ώρα «τοίχου» σε ζώνη [offsetMin] λεπτά ανατολικά του UTC: τοπική ώρα με τα ίδια ψηφία.
DateTime _wallAt(DateTime t, int offsetMin) {
  final u = t.toUtc().add(Duration(minutes: offsetMin));
  return DateTime(u.year, u.month, u.day, u.hour, u.minute, u.second, u.millisecond);
}

DateTime? _day(Object? v) {
  if (v is! String || v.length < 10) return null;
  try {
    final d = DateTime.parse(v.substring(0, 10));
    return DateTime(d.year, d.month, d.day);
  } catch (_) {
    return null;
  }
}

/// Μία περίοδος ύπνου του Oura (/v2/usercollection/sleep).
class OuraSleep {
  const OuraSleep({
    required this.id,
    required this.day,
    required this.type,
    required this.start,
    required this.end,
    this.timeInBed,
    this.total,
    this.deep,
    this.light,
    this.rem,
    this.awake,
    this.latency,
    this.efficiency,
    this.lowestHr,
    this.avgHr,
    this.avgHrv,
    this.avgBreath,
    this.phases,
    this.readinessTemp,
    this.offsetMin,
    this.endOffsetMin,
  });

  /// Round 1 (S5-1): η ζώνη ώρας της ίδιας της εγγραφής, σε λεπτά ανατολικά του UTC (π.χ. «+02:00» → 120), όπως τη
  /// δίνει η Oura στο bedtime_start ([offsetMin]) και στο bedtime_end ([endOffsetMin]· διαφέρουν μόνο τη νύχτα της
  /// αλλαγής ώρας). null = δεν δόθηκε (παλιά αποθηκευμένη νύχτα, δεδομένα δοκιμών): ισχύει η ώρα του κινητού.
  final int? offsetMin;
  final int? endOffsetMin;

  /// Η εγγραφή έγινε σε άλλη ζώνη από αυτή που έχει ΤΩΡΑ το κινητό για εκείνη τη στιγμή (ταξίδι). Μόνο τότε οι ώρες
  /// «τοίχου» διαφέρουν από τις ώρες του κινητού· αλλιώς όλα μένουν ακριβώς όπως πριν (και στην αλλαγή ώρας).
  bool get _abroad => offsetMin != null && start.timeZoneOffset.inMinutes != offsetMin;

  /// Η ώρα του τόπου όπου κοιμήθηκες: για «νύχτα ή υπνάκος», για «Κοιμήθηκες / Ξύπνησες» και για την ώρα ύπνου που
  /// αποθηκεύεται. Οι απόλυτες στιγμές ([start], [end]) μένουν για τη σειρά, τα κενά και τις ώρες ύπνου που βλέπει το
  /// ρολόι (οξυγόνο, παλμοί).
  DateTime get wallStart => _abroad ? _wallAt(start, offsetMin!) : start;
  DateTime get wallEnd => _abroad ? _wallAt(end, endOffsetMin ?? offsetMin!) : end;
  DateTime? get wallOnset {
    final o = onset;
    return o == null ? null : (_abroad ? _wallAt(o, offsetMin!) : o);
  }

  /// readiness.temperature_deviation μέσα στην περίοδο (όταν λείπει από το daily_readiness).
  final double? readinessTemp;

  final String id;

  /// Η μέρα που ανήκει (το πρωί), όπως τη δίνει η Oura.
  final DateTime day;

  /// long_sleep, sleep, late_nap, rest, deleted (ή κάτι άγνωστο).
  final String type;

  /// bedtime_start / bedtime_end, στην ώρα του κινητού.
  final DateTime start;
  final DateTime end;

  /// Δευτερόλεπτα.
  final int? timeInBed;
  final int? total;
  final int? deep;
  final int? light;
  final int? rem;
  final int? awake;
  final int? latency;
  final int? efficiency;

  final int? lowestHr;
  final double? avgHr;
  final double? avgHrv;
  final double? avgBreath;

  /// Φάσεις ανά 5 λεπτά από το bedtime_start: 1 βαθύς, 2 ελαφρύς, 3 REM, 4 ξύπνιος.
  final String? phases;

  bool get isMain => type == 'long_sleep';
  bool get isNap => type == 'sleep' || type == 'late_nap';

  /// Νύχτα κάτω από 3 ώρες (η Oura την καταγράφει ως «sleep» αντί για «long_sleep»).
  bool get isShortNight => type == 'sleep';

  /// Ξύπνιος ΜΕΣΑ στον ύπνο (δευτερόλεπτα), όπως το «ξύπνιος» του ρολογιού (έλεγχος 3, E7): το awake_time της Oura
  /// περιέχει και τον χρόνο ως τον ύπνο (latency· στα δεδομένα: time_in_bed = total + awake_time), οπότε αφαιρείται
  /// (ποτέ κάτω από 0). Έτσι ύπνος + ξύπνιος = από τον ύπνο ως το ξύπνημα, όπως στο ρολόι.
  int? get awakeInSleep {
    final a = awake;
    if (a == null) return null;
    final v = a - (latency ?? 0);
    return v < 0 ? 0 : v;
  }

  /// Πότε αποκοιμήθηκες (ξάπλωμα + χρόνος ως τον ύπνο). Χωρίς «latency» δεν το ξέρουμε.
  DateTime? get onset => latency == null ? null : start.add(Duration(seconds: latency!));

  int? get totalMinutes => total == null ? null : (total! / 60).round();

  /// Null αν λείπει κάποιο από τα απαραίτητα πεδία (id, day, bedtime_start, bedtime_end).
  static OuraSleep? fromJson(Map<String, dynamic> j) {
    final id = _str(j['id']);
    final day = _day(j['day']);
    final start = _time(j['bedtime_start']);
    final end = _time(j['bedtime_end']);
    if (id == null || day == null || start == null || end == null) return null;
    return OuraSleep(
      id: id,
      day: day,
      type: _str(j['type']) ?? '',
      start: start,
      end: end,
      timeInBed: _int(j['time_in_bed']),
      total: _int(j['total_sleep_duration']),
      deep: _int(j['deep_sleep_duration']),
      light: _int(j['light_sleep_duration']),
      rem: _int(j['rem_sleep_duration']),
      awake: _int(j['awake_time']),
      latency: _int(j['latency']),
      efficiency: _int(j['efficiency']),
      lowestHr: _int(j['lowest_heart_rate']),
      avgHr: _dbl(j['average_heart_rate']),
      avgHrv: _dbl(j['average_hrv']),
      avgBreath: _dbl(j['average_breath']),
      // Πρώτα το «sleep_phase_5_min»· αν λείπει, το «app_sleep_phase_5_min» (ίδια κωδικοποίηση).
      phases: _str(j['sleep_phase_5_min']) ?? _str(j['app_sleep_phase_5_min']),
      readinessTemp: j['readiness'] is Map ? _dbl((j['readiness'] as Map)['temperature_deviation']) : null,
      // Από την Oura: η ζώνη μέσα στην ίδια την ώρα. Από το δικό μας αρχείο (ώρες σε UTC): τα «tz» / «tz_end».
      offsetMin: _offsetOk(j['tz']) ?? _isoOffset(j['bedtime_start']),
      endOffsetMin: _offsetOk(j['tz_end']) ?? _isoOffset(j['bedtime_end']),
    );
  }

  /// Ίδια ονόματα με την Oura, ώστε το αποθηκευμένο να διαβάζεται με τον ίδιο κώδικα.
  Map<String, Object?> toJson() => {
        'id': id,
        'day': dateKey(day),
        'type': type,
        'bedtime_start': start.toUtc().toIso8601String(),
        'bedtime_end': end.toUtc().toIso8601String(),
        if (timeInBed != null) 'time_in_bed': timeInBed,
        if (total != null) 'total_sleep_duration': total,
        if (deep != null) 'deep_sleep_duration': deep,
        if (light != null) 'light_sleep_duration': light,
        if (rem != null) 'rem_sleep_duration': rem,
        if (awake != null) 'awake_time': awake,
        if (latency != null) 'latency': latency,
        if (efficiency != null) 'efficiency': efficiency,
        if (lowestHr != null) 'lowest_heart_rate': lowestHr,
        if (avgHr != null) 'average_heart_rate': avgHr,
        if (avgHrv != null) 'average_hrv': avgHrv,
        if (avgBreath != null) 'average_breath': avgBreath,
        if (phases != null) 'sleep_phase_5_min': phases,
        if (readinessTemp != null) 'readiness': {'temperature_deviation': readinessTemp},
        // Round 1 (S5-1), πρόσθετα κλειδιά: παλιός κώδικας τα αγνοεί· παλιό αρχείο χωρίς αυτά = ώρα κινητού.
        if (offsetMin != null) 'tz': offsetMin,
        if (endOffsetMin != null && endOffsetMin != offsetMin) 'tz_end': endOffsetMin,
      };

  /// Οι φάσεις ως κομμάτια χρόνου (για το υπνόγραμμα, «εκτίμηση της Oura»).
  List<Stage> get stages => ouraStages(phases, start, end);
}

/// Φάσεις από το «sleep_phase_5_min»: κάθε χαρακτήρας 5 λεπτά από το [start]. Διαδοχικοί ίδιοι ενώνονται.
/// Άγνωστος χαρακτήρας = κενό. Τίποτα δεν περνά το [end].
List<Stage> ouraStages(String? phases, DateTime start, DateTime end) {
  if (phases == null || phases.isEmpty) return const [];
  const names = {'1': 'DEEP', '2': 'LIGHT', '3': 'REM', '4': 'AWAKE'};
  final out = <Stage>[];
  String? cur;
  late DateTime curStart;
  void close(DateTime t) {
    if (cur == null) return;
    final e = t.isAfter(end) ? end : t;
    if (e.isAfter(curStart)) out.add(Stage(cur, curStart, e));
  }

  for (var i = 0; i < phases.length; i++) {
    final n = names[phases[i]];
    if (n == cur) continue;
    final t = start.add(Duration(minutes: 5 * i));
    close(t);
    cur = n;
    curStart = t;
  }
  close(start.add(Duration(minutes: 5 * phases.length)));
  return out;
}

/// Οι ημερήσιες τιμές του Oura για μια μέρα (daily_sleep + daily_readiness).
class OuraDaily {
  OuraDaily(this.day);
  final DateTime day;
  int? sleepScore;
  int? readiness;

  /// Απόκλιση θερμοκρασίας δέρματος (°C) από το συνηθισμένο σου, κατά την Oura.
  double? tempDeviation;

  /// Μέσος όρος οξυγόνου της νύχτας (%), από το daily_spo2 (spo2_percentage.average). Μόνο με την άδεια spo2.
  double? spo2Avg;
}

/// Μία μέρα του Oura: η νύχτα, οι υπνάκοι και οι ημερήσιες τιμές.
class OuraNight {
  OuraNight(
      {required this.day,
      this.main,
      this.naps = const [],
      this.others = const [],
      this.pieces = const [],
      this.daily,
      this.napLock});

  final DateTime day;

  /// Έλεγχος 3, E1.6: η απόφαση «πρωινός υπνάκος» που πάρθηκε με τα βήματα του ρολογιού (αρχή του κομματιού που έγινε
  /// υπνάκος)· αποθηκεύεται ([K.napLock] → «o.napLock») και δεν αλλάζει όταν τα βήματα δεν υπάρχουν πια.
  final DateTime? napLock;

  /// Η κύρια περίοδος της νύχτας (long_sleep με τον περισσότερο ύπνο, αλλιώς η μεγαλύτερη). Null = δεν υπάρχει νύχτα
  /// από το δαχτυλίδι αυτή τη μέρα.
  final OuraSleep? main;

  /// Υπνάκοι κατά τον κοινό κανόνα της νύχτας ([groupOura]): φαίνονται χωριστά, δεν προστίθενται στη νύχτα.
  final List<OuraSleep> naps;

  /// Περίοδοι της νύχτας που επικαλύπτονται με άλλη που ήδη μετρά (σπάνιο): φαίνονται, δεν προστίθενται (ο ίδιος
  /// χρόνος δεν μετρά ποτέ δύο φορές).
  final List<OuraSleep> others;

  /// Τα άλλα κομμάτια της νύχτας (εκτός από την κύρια περίοδο): κατά τον κοινό κανόνα με το ρολόι ([groupOura]),
  /// μετρούν μαζί της ([counted]). Το κενό ανάμεσα δεν μετρά.
  final List<OuraSleep> pieces;

  /// Οι περίοδοι ύπνου που μετρούν ως η νύχτα, παλιότερη πρώτη: η κύρια και τα [pieces] (ίδιος κανόνας με τη νύχτα
  /// του ρολογιού, έλεγχος 2, C1/U12). Το κενό ανάμεσα ΔΕΝ μετρά ως ύπνος. Πριν, μια νύχτα 23:00–01:30 και
  /// 03:00–05:45 έδειχνε μόνο 2 ώρες 35 λεπτά και «άλλο κομμάτι (χωριστά)».
  List<OuraSleep> get counted {
    final m = main;
    if (m == null) return const [];
    if (pieces.isEmpty) return [m];
    return [m, ...pieces]..sort((a, b) => a.start.compareTo(b.start));
  }

  /// Ο ύπνος της νύχτας σε λεπτά: το άθροισμα των περιόδων που μετρούν ([counted]), χωρίς τα κενά. Null αν η κύρια
  /// δεν έχει διάρκεια ύπνου.
  int? get nightMinutes {
    final m = main;
    if (m == null || m.total == null) return null;
    final secs = counted.fold<int>(0, (s, x) => s + (x.total ?? 0));
    return (secs / 60).round();
  }

  /// Η νύχτα είναι κάτω από 3 ώρες («Σύντομη νύχτα»). Ίδιος ορισμός για κάθε τύπο περιόδου (ο τύπος της Oura δεν αποφασίζει, συγχώνευση 4/11): ο ύπνος της νύχτας
  /// (όλα τα κομμάτια που μετρούν) είναι κάτω από 3 ώρες.
  bool get shortNight {
    final m = nightMinutes;
    return m != null && m < 180;
  }

  /// Υπάρχει μόνο υπνάκος από το δαχτυλίδι, καμία νύχτα.
  bool get onlyNap => main == null && naps.isNotEmpty;
  final OuraDaily? daily;

  int? get sleepScore => daily?.sleepScore;
  int? get readiness => daily?.readiness;

  /// Από το daily_readiness· αν λείπει, από την ίδια νύχτα (ίδια πηγή, ίδια τιμή της Oura).
  double? get tempDeviation => daily?.tempDeviation ?? main?.readinessTemp;
  double? get spo2Avg => daily?.spo2Avg;

  int get napMinutes => naps.fold(0, (s, n) => s + (n.totalMinutes ?? 0));
  bool get hasAny => main != null || naps.isNotEmpty || others.isNotEmpty || pieces.isNotEmpty || daily != null;

  /// Η νύχτα στη μορφή της εφαρμογής, για το υπνόγραμμα (μόνο φάσεις και ώρες). Νύχτα σε κομμάτια: από την αρχή
  /// του πρώτου ως το τέλος του τελευταίου, με τις φάσεις όλων (το κενό μένει κενό).
  Night? toNight() {
    final m = main;
    if (m == null) return null;
    final parts = counted;
    final n = Night(day)
      ..start = parts.first.start
      ..end = parts.last.end
      ..minutes = nightMinutes ?? 0;
    for (final p in parts) {
      n.stages.addAll(p.stages);
    }
    return n;
  }

  Map<String, Object?> toJson() => {
        'day': dateKey(day),
        if (main != null) 'main': main!.toJson(),
        if (naps.isNotEmpty) 'naps': [for (final x in naps) x.toJson()],
        if (others.isNotEmpty) 'others': [for (final x in others) x.toJson()],
        if (pieces.isNotEmpty) 'pieces': [for (final x in pieces) x.toJson()],
        if (daily?.sleepScore != null) 'score': daily!.sleepScore,
        if (daily?.readiness != null) 'readiness': daily!.readiness,
        if (daily?.tempDeviation != null) 'temp': daily!.tempDeviation,
        if (daily?.spo2Avg != null) 'spo2': daily!.spo2Avg,
        if (napLock != null) 'napLock': napLock!.millisecondsSinceEpoch ~/ 60000,
      };

  static OuraNight? fromJson(Object? j) {
    if (j is! Map) return null;
    final day = _day(j['day']);
    if (day == null) return null;
    List<OuraSleep> list(Object? v) => [
          if (v is List)
            for (final x in v)
              if (x is Map) OuraSleep.fromJson(Map<String, dynamic>.from(x)),
        ].whereType<OuraSleep>().toList();
    final main = j['main'] is Map ? OuraSleep.fromJson(Map<String, dynamic>.from(j['main'] as Map)) : null;
    final hasDaily = j['score'] != null || j['readiness'] != null || j['temp'] != null || j['spo2'] != null;
    return OuraNight(
      day: day,
      main: main,
      naps: list(j['naps']),
      others: list(j['others']),
      pieces: list(j['pieces']),
      napLock: j['napLock'] is num ? DateTime.fromMillisecondsSinceEpoch((j['napLock'] as num).toInt() * 60000) : null,
      daily: hasDaily
          ? (OuraDaily(day)
            ..sleepScore = _int(j['score'])
            ..readiness = _int(j['readiness'])
            ..tempDeviation = _dbl(j['temp'])
            ..spo2Avg = _dbl(j['spo2']))
          : null,
    );
  }
}

/// Η κύρια νύχτα μιας μέρας: η «long_sleep» με τον περισσότερο ύπνο (ισοπαλία: περισσότερος χρόνος στο κρεβάτι).
OuraSleep? selectMainSleep(Iterable<OuraSleep> periods) {
  OuraSleep? best;
  for (final p in periods) {
    if (!p.isMain) continue;
    if (best == null) {
      best = p;
      continue;
    }
    final a = p.total ?? -1, b = best.total ?? -1;
    if (a > b || (a == b && (p.timeInBed ?? -1) > (best.timeInBed ?? -1))) best = p;
  }
  return best;
}

/// Ομαδοποίηση ανά μέρα, παλιότερη πρώτη, με τον ΙΔΙΟ κανόνα νύχτας με το ρολόι ([groupSleepPieces], έλεγχος 2,
/// C1/U12, συγχώνευση 4/11): κομμάτια με κενό ως 4 ώρες = μία νύχτα (το κενό δεν μετρά)· λαγοκοίμισμα που
/// τελειώνει ως τις 22:00, πρωινό κομμάτι μετά τις 06:00 με κενό πάνω από 90 λεπτά (το Oura δεν έχει βήματα: «άγνωστα»)
/// και απογευματινό κάτω από 3 ώρες = υπνάκοι. Ο τύπος της Oura (long_sleep/sleep/late_nap) ΔΕΝ αποφασίζει νύχτα ή
/// υπνάκο· διαλέγει μόνο την κύρια περίοδο (της οποίας οι παλμοί/HRV/αναπνοές δείχνονται): η long_sleep με τον
/// περισσότερο ύπνο, αλλιώς η μεγαλύτερη περίοδος. Ημερομηνία: η «day» της Oura (της μεγαλύτερης περιόδου).
/// [stepsBetween]: τα βήματα ανά λεπτό του ΡΟΛΟΓΙΟΥ (έλεγχος 3, E1.5: μόνο για το πρωινό κενό, ποτέ ως τιμή)·
/// [napLocks]: οι αποθηκευμένες αποφάσεις «υπνάκος» («o.napLock» του ιστορικού, ανά «day»).
List<OuraNight> groupOura(List<OuraSleep> sleeps, Map<String, OuraDaily> dailies,
    {int? Function(DateTime from, DateTime to)? stepsBetween, Map<String, int> napLocks = const {}}) {
  final periods = [
    for (final s in sleeps)
      if (s.type != 'rest' && s.type != 'deleted') s,
  ]..sort((a, b) => a.start.compareTo(b.start));
  int mins(OuraSleep s) => s.totalMinutes ?? 0;
  final grouped = groupSleepPieces<OuraSleep>(
    periods,
    (s) => (start: s.start, end: s.end, minutes: mins(s)),
    // S5-1: «νύχτα ή υπνάκος» στην ώρα του τόπου όπου κοιμήθηκες (η ζώνη της ίδιας της εγγραφής).
    wall: (s) => (start: s.wallStart, end: s.wallEnd, minutes: mins(s)),
    dateOf: (parts) => parts.reduce((a, b) => mins(b) > mins(a) ? b : a).day,
    stepsBetween: stepsBetween,
    napLockOf: (date) {
      final m = napLocks[dateKey(date)];
      return m == null ? null : DateTime.fromMillisecondsSinceEpoch(m * 60000);
    },
  );
  final nightsByDay = <String, List<OuraSleep>>{
    for (final n in grouped.nights) dateKey(n.date): n.parts,
  };
  final locksByDay = <String, DateTime>{
    for (final n in grouped.nights)
      if (n.napLock != null) dateKey(n.date): n.napLock!,
  };
  final napsByDay = <String, List<OuraSleep>>{
    for (final e in grouped.naps.entries) dateKey(e.key): e.value,
  };
  final days = {...nightsByDay.keys, ...napsByDay.keys, ...dailies.keys}.toList()..sort();
  return [
    for (final k in days)
      () {
        final parts = (nightsByDay[k] ?? const <OuraSleep>[]).toList()..sort((a, b) => a.start.compareTo(b.start));
        final main = selectMainSleep(parts) ??
            (parts.isEmpty ? null : parts.reduce((a, b) => (b.total ?? -1) > (a.total ?? -1) ? b : a));
        // Κομμάτια που επικαλύπτονται με ό,τι ήδη μετρά (δεν συμβαίνει στην Oura): χωριστά, ποτέ δύο φορές.
        final counted = <OuraSleep>[if (main != null) main];
        final others = <OuraSleep>[];
        for (final p in parts) {
          if (identical(p, main)) continue;
          final overlaps = counted.any((x) => p.start.isBefore(x.end) && p.end.isAfter(x.start));
          (overlaps ? others : counted).add(p);
        }
        return OuraNight(
          day: parseDateKey(k),
          main: main,
          naps: (napsByDay[k] ?? const <OuraSleep>[]).toList()..sort((a, b) => a.start.compareTo(b.start)),
          others: others,
          pieces: [for (final p in counted) if (!identical(p, main)) p],
          daily: dailies[k],
          napLock: locksByDay[k],
        );
      }(),
  ];
}

/// Τα ημερήσια (daily_sleep, daily_readiness) ενωμένα ανά μέρα.
Map<String, OuraDaily> mergeDailies(List<Map<String, dynamic>> dailySleep, List<Map<String, dynamic>> readiness,
    [List<Map<String, dynamic>> spo2 = const []]) {
  final out = <String, OuraDaily>{};
  OuraDaily at(DateTime d) => out.putIfAbsent(dateKey(d), () => OuraDaily(d));
  for (final j in dailySleep) {
    final d = _day(j['day']);
    if (d == null) continue;
    at(d).sleepScore = _int(j['score']);
  }
  for (final j in readiness) {
    final d = _day(j['day']);
    if (d == null) continue;
    at(d)
      ..readiness = _int(j['score'])
      ..tempDeviation = _dbl(j['temperature_deviation']);
  }
  for (final j in spo2) {
    final d = _day(j['day']);
    if (d == null) continue;
    final p = j['spo2_percentage'];
    final v = p is Map ? _dbl(p['average']) : null;
    // Μόνο λογικές τιμές (όπως spo2Range του ρολογιού)· 0 ή κενό = δεν μετρήθηκε.
    if (v != null && v >= 50 && v <= 100) at(d).spo2Avg = v;
  }
  // Μέρα χωρίς καμία τιμή: δεν μένει άδεια εγγραφή.
  out.removeWhere((_, v) => v.sleepScore == null && v.readiness == null && v.tempDeviation == null && v.spo2Avg == null);
  return out;
}

/// Οι τιμές μιας μέρας του Oura για το ιστορικό, με τα κλειδιά του Oura («o.*», δες sources.dart).
/// [v] αν είναι μέσα στα λογικά όρια [lo, hi], αλλιώς null (σφάλμα ή «δεν μετρήθηκε»).
num? _within(num? v, num lo, num hi) => v != null && v.isFinite && v >= lo && v <= hi ? v : null;

Map<String, double> ouraRow(OuraNight n) {
  final out = <String, double>{};
  void put(String metric, num? v) {
    if (v != null && v.isFinite) out[ouraKeys[metric]!] = v.toDouble();
  }

  final m = n.main;
  if (m != null) {
    // Νύχτα σε κομμάτια ([OuraNight.counted]): διάρκεια, φάσεις και ξύπνιος από όλα τα κομμάτια που μετρούν, ώρα
    // ύπνου από το πρώτο, ξύπνημα από το τελευταίο (δεύτερος γύρος ελέγχου, U12). Παλμοί, HRV, αναπνοές: της κύριας
    // περιόδου (μέσοι όροι της Oura ανά περίοδο· δεν ανακατεύονται).
    final parts = n.counted;
    int? sum(int? Function(OuraSleep) f) => parts.any((x) => f(x) == null) ? null : parts.fold<int>(0, (s, x) => s + f(x)!);
    put(K.sleepMin, m.total == null ? null : parts.fold<int>(0, (s, x) => s + (x.total ?? 0)) / 60);
    // S5-1: ώρα ύπνου και ξυπνήματος στην ώρα του τόπου όπου κοιμήθηκες.
    final onset = parts.first.wallOnset;
    if (onset != null) put(K.bedtime, minutesFromSix(onset));
    put(K.wake, minutesFromSix(parts.last.wallEnd));
    // Ποσοστό του ύπνου (χωρίς τον χρόνο ξύπνιος), όπως στην εφαρμογή Oura (έλεγχος υπολογισμών F6, 4/11).
    final deep = sum((x) => x.deep), light = sum((x) => x.light), rem = sum((x) => x.rem);
    if (deep != null && light != null && rem != null) {
      final staged = deep + light + rem;
      if (staged > 0) {
        put(K.deepPct, 100 * deep / staged);
        put(K.remPct, 100 * rem / staged);
      }
    }
    // E7: ξύπνιος μέσα στον ύπνο, χωρίς τον χρόνο ως τον ύπνο (ίδιος ορισμός με το ρολόι).
    final awake = sum((x) => x.awakeInSleep);
    put(K.awakeMin, awake == null ? null : awake / 60);
    // Audit 7/11 (B1): μόνο λογικές τιμές, όπως στο ρολόι (hrRange)· 0 ή άκυρο = δεν μετρήθηκε, όχι «0 bpm».
    put(K.sleepHr, _within(m.avgHr, 25, 250));
    put(K.lowHr, _within(m.lowestHr, 25, 250));
    put(K.hrv, _within(m.avgHrv, 1, 400));
    put(K.breath, _within(m.avgBreath, 4, 40));
  }
  final napped = [for (final x in n.naps) if (x.total != null) x.total!];
  if (napped.isNotEmpty) put(K.napMin, napped.fold<int>(0, (a, b) => a + b) / 60);
  if (m != null && n.napLock != null) put(K.napLock, n.napLock!.millisecondsSinceEpoch ~/ 60000);
  // Βαθμολογία ύπνου μόνο για μέρα με κύρια νύχτα (όχι για μέρα με μόνο υπνάκο: η κάρτα λέει «Μόνο υπνάκος»).
  if (m != null) put(K.sleepScore, _within(n.sleepScore, 0, 100));
  put(K.energy, _within(n.readiness, 0, 100));
  put(K.skinTemp, _within(n.tempDeviation, -5, 5));
  // Οξυγόνο: μόνο για μέρα με κύρια νύχτα (όπως η βαθμολογία ύπνου).
  if (m != null) put(K.ringSpo2, n.spo2Avg);
  return out;
}

/// Γραμμές ιστορικού για όλες τις μέρες.
Map<String, Map<String, double>> ouraRows(List<OuraNight> nights) => {
      for (final n in nights)
        if (ouraRow(n).isNotEmpty) dateKey(n.day): ouraRow(n),
    };

/// Τα χρονικά παράθυρα ύπνου του Oura (για να μη μετρούν ως «μέρα» οι παλμοί του ρολογιού).
SleepWindows ouraSleepWindows(List<OuraNight> nights) => SleepWindows(
      [
        for (final n in nights) ...[
          if (n.main != null) (n.main!.start, n.main!.end),
          for (final x in [...n.naps, ...n.others, ...n.pieces]) (x.start, x.end),
        ],
      ],
      {for (final n in nights) if (n.main != null) dateKey(n.day): (n.main!.start, n.main!.end)},
      // Έλεγχος 3, S5: νύχτα σε κομμάτια → το οξυγόνο του ρολογιού από ΟΛΑ τα κομμάτια που μετρούν (όχι τα κενά).
      {
        for (final n in nights)
          if (n.main != null && n.pieces.isNotEmpty)
            dateKey(n.day): unionOfRanges([for (final x in n.counted) (x.start, x.end)]),
      },
    );

/// Όλη η απάντηση μιας ανάγνωσης, διαβασμένη.
class OuraBatch {
  OuraBatch(this.nights, {this.skipped = 0});
  final List<OuraNight> nights;

  /// Εγγραφές που δεν είχαν τα απαραίτητα πεδία (δεν μπήκαν).
  final int skipped;
}

/// Διαβάζει τα «data» των τριών endpoints (ό,τι ήρθε από όλες τις σελίδες).
OuraBatch parseOura({
  required List<Map<String, dynamic>> sleep,
  required List<Map<String, dynamic>> dailySleep,
  required List<Map<String, dynamic>> readiness,
  List<Map<String, dynamic>> spo2 = const [],
  int? Function(DateTime from, DateTime to)? stepsBetween,
  Map<String, int> napLocks = const {},
}) {
  var skipped = 0;
  final periods = <OuraSleep>[];
  for (final j in sleep) {
    final s = OuraSleep.fromJson(j);
    if (s == null) {
      skipped++;
    } else {
      periods.add(s);
    }
  }
  return OuraBatch(
      groupOura(periods, mergeDailies(dailySleep, readiness, spo2), stepsBetween: stepsBetween, napLocks: napLocks),
      skipped: skipped);
}

/// Μία σελίδα απάντησης: τα «data» και το «next_token». Πετάει [FormatException] αν δεν είναι η μορφή της Oura.
({List<Map<String, dynamic>> data, String? next}) parseOuraPage(Object? j) {
  if (j is! Map || j['data'] is! List) throw const FormatException('Μη αναμενόμενη μορφή απάντησης Oura');
  final next = j['next_token'];
  return (
    data: [
      for (final x in j['data'] as List)
        if (x is Map) Map<String, dynamic>.from(x),
    ],
    next: next is String && next.isNotEmpty ? next : null,
  );
}

/// Αποθήκευση των λεπτομερειών (τελευταίες νύχτες) σε ένα κείμενο JSON.
String encodeOuraNights(List<OuraNight> nights) => jsonEncode({
      'v': 1,
      'nights': [for (final n in nights) n.toJson()],
    });

List<OuraNight> decodeOuraNights(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final j = jsonDecode(raw);
    if (j is! Map || j['nights'] is! List) return const [];
    final out = [for (final x in j['nights'] as List) OuraNight.fromJson(x)].whereType<OuraNight>().toList()
      ..sort((a, b) => a.day.compareTo(b.day));
    return out;
  } catch (_) {
    return const [];
  }
}

/// Νέες νύχτες πάνω στις παλιές: οι μέρες στο [from, to] που ήρθαν αντικαθίστανται· όσες ΔΕΝ ήρθαν μένουν
/// (έλεγχος 4/11, A3: μια νύχτα που η Oura δεν έστειλε αυτή τη φορά δεν σβήνεται). Κρατιούνται οι τελευταίες
/// [keepDays] μέρες ως το [today].
List<OuraNight> mergeOuraNights(
  List<OuraNight> old,
  List<OuraNight> fresh, {
  required DateTime from,
  required DateTime to,
  required DateTime today,
  int keepDays = 45,
}) {
  final oldest = DateTime(today.year, today.month, today.day - keepDays);
  final byDay = <String, OuraNight>{for (final n in old) dateKey(n.day): n};
  for (final n in fresh) {
    if (n.day.isBefore(dayOf(from)) || n.day.isAfter(dayOf(to))) continue;
    // Το οξυγόνο έρχεται χωριστά: νέα νύχτα χωρίς αυτό κρατά το παλιό (όπως το «o.spo2» στο ιστορικό).
    final prev = byDay[dateKey(n.day)];
    final keep = prev?.spo2Avg;
    if (keep != null && n.spo2Avg == null) {
      byDay[dateKey(n.day)] = OuraNight(
          day: n.day,
          main: n.main,
          naps: n.naps,
          others: n.others,
          pieces: n.pieces,
          napLock: n.napLock,
          daily: (OuraDaily(n.day)
            ..sleepScore = n.daily?.sleepScore
            ..readiness = n.daily?.readiness
            ..tempDeviation = n.daily?.tempDeviation
            ..spo2Avg = keep));
      continue;
    }
    byDay[dateKey(n.day)] = n;
  }
  final out = [for (final n in byDay.values) if (!n.day.isBefore(oldest)) n]..sort((a, b) => a.day.compareTo(b.day));
  return out;
}
