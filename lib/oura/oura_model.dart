/// Τα δεδομένα του Oura (API v2), όπως τα δίνει η Oura, και οι μετατροπές τους.
///
/// Πεδία επαληθευμένα στο επίσημο OpenAPI 1.43 (PublicModifiedSleepModel, PublicDailySleep,
/// PublicDailyReadiness) και στο sandbox της Oura. Κανόνες:
/// - Ό,τι λείπει (null) μένει κενό· ποτέ 0.
/// - Η νύχτα μιας μέρας είναι η περίοδος «long_sleep» με τον περισσότερο ύπνο. Αν δεν υπάρχει (νύχτα κάτω από
///   3 ώρες: η Oura τη λέει «sleep»), νύχτα είναι η μεγαλύτερη «sleep» μέσα στο νυχτερινό παράθυρο ([inNightWindow])
///   — «Σύντομη νύχτα». Άλλα κομμάτια στο ίδιο παράθυρο φαίνονται ως «άλλο κομμάτι» και ΔΕΝ προστίθενται.
///   Οι υπνάκοι («sleep» εκτός παραθύρου, «late_nap») φαίνονται χωριστά και δεν προστίθενται. Οι «rest» (λάθος
///   ανίχνευση που απέρριψε ο χρήστης) και «deleted» αγνοούνται.
/// - Η μέρα κάθε περιόδου είναι το «day» της Oura (το πρωί που ξύπνησες)· δεν την ξαναϋπολογίζουμε.
/// - Οι ώρες έρχονται με τη ζώνη ώρας τους (π.χ. +02:00) και δείχνονται στην ώρα του κινητού.
library;

import 'dart:convert';

import '../data.dart' show Stage, Night;
import '../format.dart';
import '../history.dart';
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
  });

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
      };

  /// Οι φάσεις ως κομμάτια χρόνου (για το υπνόγραμμα, «εκτίμηση του Oura»).
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
    if (e.isAfter(curStart)) out.add(Stage(cur!, curStart, e));
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
}

/// Μία μέρα του Oura: η νύχτα, οι υπνάκοι και οι ημερήσιες τιμές.
class OuraNight {
  OuraNight({required this.day, this.main, this.naps = const [], this.others = const [], this.pieces = const [], this.daily});

  final DateTime day;

  /// Η νύχτα (long_sleep). Null = δεν υπάρχει νύχτα από το δαχτυλίδι αυτή τη μέρα.
  final OuraSleep? main;

  /// Υπνάκοι (sleep, late_nap): φαίνονται χωριστά, δεν προστίθενται στη νύχτα.
  final List<OuraSleep> naps;

  /// Άλλες μεγάλες περίοδοι της ίδιας μέρας (σπάνιο): φαίνονται, δεν προστίθενται.
  final List<OuraSleep> others;

  /// Σύντομη νύχτα σε κομμάτια: τα άλλα κομμάτια του νυχτερινού παραθύρου («άλλο κομμάτι»). Φαίνονται κάτω
  /// από τη νύχτα, ΔΕΝ προστίθενται ούτε στη νύχτα ούτε στους υπνάκους.
  final List<OuraSleep> pieces;

  /// Η νύχτα είναι κάτω από 3 ώρες («Σύντομη νύχτα»).
  bool get shortNight => main?.isShortNight ?? false;

  /// Υπάρχει μόνο υπνάκος από το δαχτυλίδι, καμία νύχτα.
  bool get onlyNap => main == null && naps.isNotEmpty;
  final OuraDaily? daily;

  int? get sleepScore => daily?.sleepScore;
  int? get readiness => daily?.readiness;

  /// Από το daily_readiness· αν λείπει, από την ίδια νύχτα (ίδια πηγή, ίδια τιμή της Oura).
  double? get tempDeviation => daily?.tempDeviation ?? main?.readinessTemp;

  int get napMinutes => naps.fold(0, (s, n) => s + (n.totalMinutes ?? 0));
  bool get hasAny => main != null || naps.isNotEmpty || others.isNotEmpty || pieces.isNotEmpty || daily != null;

  /// Η νύχτα στη μορφή της εφαρμογής, για το υπνόγραμμα (μόνο φάσεις και ώρες).
  Night? toNight() {
    final m = main;
    if (m == null) return null;
    final n = Night(day)
      ..start = m.start
      ..end = m.end
      ..minutes = m.totalMinutes ?? 0;
    n.stages.addAll(m.stages);
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
    final hasDaily = j['score'] != null || j['readiness'] != null || j['temp'] != null;
    return OuraNight(
      day: day,
      main: main,
      naps: list(j['naps']),
      others: list(j['others']),
      pieces: list(j['pieces']),
      daily: hasDaily
          ? (OuraDaily(day)
            ..sleepScore = _int(j['score'])
            ..readiness = _int(j['readiness'])
            ..tempDeviation = _dbl(j['temp']))
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

/// Το νυχτερινό παράθυρο της μέρας [day] (πρωινό): η περίοδος επικαλύπτει 00:00–06:00 της ίδιας μέρας (ώρα κινητού).
bool inNightWindow(OuraSleep s, DateTime day) {
  // Επικάλυψη με 00:00–06:00 (ώρα κινητού) της μέρας D: όχι απογευματινοί/βραδινοί υπνάκοι (π.χ. 19:00–21:00).
  final from = DateTime(day.year, day.month, day.day);
  final to = DateTime(day.year, day.month, day.day, 6);
  return s.start.isBefore(to) && s.end.isAfter(from);
}

/// Χωρίς «long_sleep»: η σύντομη νύχτα = η «sleep» με τον περισσότερο ύπνο μέσα στο νυχτερινό παράθυρο
/// (ποτέ «late_nap», «rest», «deleted»).
OuraSleep? selectShortNight(Iterable<OuraSleep> periods, DateTime day) {
  OuraSleep? best;
  for (final p in periods) {
    if (!p.isShortNight || !inNightWindow(p, day)) continue;
    if (best == null || (p.total ?? -1) > (best.total ?? -1)) best = p;
  }
  return best;
}

/// Ομαδοποίηση ανά μέρα, παλιότερη πρώτη.
List<OuraNight> groupOura(List<OuraSleep> sleeps, Map<String, OuraDaily> dailies) {
  final byDay = <String, List<OuraSleep>>{};
  for (final s in sleeps) {
    if (s.type == 'rest' || s.type == 'deleted') continue;
    byDay.putIfAbsent(dateKey(s.day), () => []).add(s);
  }
  final days = {...byDay.keys, ...dailies.keys}.toList()..sort();
  return [
    for (final k in days)
      () {
        final list = (byDay[k] ?? const <OuraSleep>[]).toList()..sort((a, b) => a.start.compareTo(b.start));
        final day = parseDateKey(k);
        final long = selectMainSleep(list);
        final main = long ?? selectShortNight(list, day);
        // Τα άλλα κομμάτια μιας σύντομης νύχτας (ίδιο παράθυρο): «άλλο κομμάτι», όχι υπνάκοι.
        final pieces = long != null || main == null
            ? const <OuraSleep>[]
            : [for (final p in list) if (!identical(p, main) && p.isShortNight && inNightWindow(p, day)) p];
        return OuraNight(
          day: day,
          main: main,
          naps: [for (final p in list) if (p.isNap && !identical(p, main) && !pieces.any((x) => identical(x, p))) p],
          others: [for (final p in list) if (p.isMain && !identical(p, main)) p],
          pieces: pieces,
          daily: dailies[k],
        );
      }(),
  ];
}

/// Τα ημερήσια (daily_sleep, daily_readiness) ενωμένα ανά μέρα.
Map<String, OuraDaily> mergeDailies(List<Map<String, dynamic>> dailySleep, List<Map<String, dynamic>> readiness) {
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
  // Μέρα χωρίς καμία τιμή: δεν μένει άδεια εγγραφή.
  out.removeWhere((_, v) => v.sleepScore == null && v.readiness == null && v.tempDeviation == null);
  return out;
}

/// Οι τιμές μιας μέρας του Oura για το ιστορικό, με τα κλειδιά του Oura («o.*», δες sources.dart).
Map<String, double> ouraRow(OuraNight n) {
  final out = <String, double>{};
  void put(String metric, num? v) {
    if (v != null && v.isFinite) out[ouraKeys[metric]!] = v.toDouble();
  }

  final m = n.main;
  if (m != null) {
    put(K.sleepMin, m.total == null ? null : m.total! / 60);
    final onset = m.onset;
    if (onset != null) put(K.bedtime, minutesFromSix(onset));
    put(K.wake, minutesFromSix(m.end));
    if (m.deep != null && m.light != null && m.rem != null && m.awake != null) {
      final staged = m.deep! + m.light! + m.rem! + m.awake!;
      if (staged > 0) {
        put(K.deepPct, 100 * m.deep! / staged);
        put(K.remPct, 100 * m.rem! / staged);
      }
    }
    put(K.awakeMin, m.awake == null ? null : m.awake! / 60);
    put(K.sleepHr, m.avgHr);
    put(K.lowHr, m.lowestHr);
    put(K.hrv, m.avgHrv);
    put(K.breath, m.avgBreath);
  }
  final napped = [for (final x in n.naps) if (x.total != null) x.total!];
  if (napped.isNotEmpty) put(K.napMin, napped.fold<int>(0, (a, b) => a + b) / 60);
  // Βαθμολογία ύπνου μόνο για μέρα με κύρια νύχτα (όχι για μέρα με μόνο υπνάκο: η κάρτα λέει «Μόνο υπνάκος»).
  if (m != null) put(K.sleepScore, n.sleepScore);
  put(K.energy, n.readiness);
  put(K.skinTemp, n.tempDeviation);
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
  return OuraBatch(groupOura(periods, mergeDailies(dailySleep, readiness)), skipped: skipped);
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
    byDay[dateKey(n.day)] = n;
  }
  final out = [for (final n in byDay.values) if (!n.day.isBefore(oldest)) n]..sort((a, b) => a.day.compareTo(b.day));
  return out;
}
