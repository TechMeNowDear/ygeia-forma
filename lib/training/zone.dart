/// Ζώνη περπατήματος (σχέδια 12/11, εγκρίθηκαν 11/11): μέτρια ένταση, 40–59% του αποθέματος παλμών (ACSM, μέτρια
/// ένταση· τύπος Karvonen). Αντικαθιστά στην Προπόνηση το «Όριο παλμών από τον γιατρό», που συνήθως δεν δίνεται (το όριο
/// γιατρού μένει στις Ρυθμίσεις › Για προχωρημένους και, αν υπάρχει, νικά πάντα).
///
/// - Ηρεμία: η μεσαία τιμή των παλμών ύπνου των 14 τελευταίων νυχτών (τουλάχιστον 7), από την πηγή του ύπνου.
///   Χωρίς αρκετές νύχτες: ζώνη 64–76% των μέγιστων (ACSM, μέτρια ένταση).
/// - Μέγιστοι: 208 − 0,7 × ηλικία (Tanaka 2001), εκτός αν ο χρήστης δώσει τιμή από τεστ ως την εξάντληση.
/// - Ειλικρινές: η «ζώνη καύσης λίπους» δεν αλλάζει την απώλεια λίπους· μετρά ο όγκος της άσκησης (Kraus 2002, Kodama 2007).
library;

import 'dart:math' as math;

import 'session.dart';

const zoneLoPct = 0.40;
const zoneHiPct = 0.59;
const zoneLoMaxPct = 0.64;
const zoneHiMaxPct = 0.76;

/// Το ρολόι δεν δονείται τα πρώτα 5 λεπτά (οι παλμοί ακόμα ανεβαίνουν, Buchheit 2014) και πρέπει οι παλμοί να μείνουν
/// πάνω από τη ζώνη 5″ (απόφαση χρήστη 14/11· πριν 20″), με δόνηση και φωνή «Εκτός εύρους». Ξανά μετά από 2′, αν δεν
/// κατέβεις. Ίδιες σταθερές με το ρολόι (Protocol.kt: ZONE_HOLD_MS).
const zoneWarmupSec = 5 * 60;
const zoneHoldSec = 5;
const zoneRepeatSec = 120;

/// Ερώτηση «τεστ ομιλίας» μόνο στα πρώτα περπατήματα.
const talkAskWalks = 3;

int tanakaMax(int age) => (208 - 0.7 * age).round();

/// Όρια για τους παλμούς ηρεμίας που γράφει ο χρήστης.
const zoneRestMin = 30, zoneRestMax = 120;

/// Ρυθμίσεις του χρήστη (στις ρυθμίσεις της εφαρμογής, κλειδί «zone»).
class ZoneSettings {
  const ZoneSettings({this.lo, this.hi, this.maxHr, this.restHr, this.alertHigh = true, this.alertLow = false, this.talk = const []});

  /// Ζώνη που έγραψε ο χρήστης (αλλιώς ο υπολογισμός).
  final int? lo, hi;

  /// Μέγιστοι παλμοί από τεστ ως την εξάντληση (αλλιώς Tanaka).
  final int? maxHr;

  /// Παλμοί ηρεμίας ξύπνιος, μετρημένοι από τον χρήστη (καθιστός, μετά από 5′ ηρεμίας, πρωί), προαιρετικά (13/11).
  /// Ο τύπος του Karvonen ορίζεται με παλμούς ηρεμίας ξύπνιου· οι παλμοί ύπνου είναι λίγο χαμηλότεροι και δίνουν ζώνη
  /// λίγους παλμούς πιο κάτω (πόσους, εξαρτάται από τη διαφορά των δύο σε κάθε άνθρωπο). Χωρίς τιμή μένουν οι παλμοί ύπνου, όπως πριν.
  final int? restHr;
  final bool alertHigh, alertLow;

  /// Απαντήσεις στο «τεστ ομιλίας»: id του περπατήματος → «sing» | «talk» | «no».
  final List<List<String>> talk;

  bool get manual => lo != null && hi != null;

  ZoneSettings copyWith(
          {int? lo,
          int? hi,
          int? maxHr,
          int? restHr,
          bool? alertHigh,
          bool? alertLow,
          List<List<String>>? talk,
          bool clearManual = false,
          bool clearMax = false,
          bool clearRest = false}) =>
      ZoneSettings(
        lo: clearManual ? null : (lo ?? this.lo),
        hi: clearManual ? null : (hi ?? this.hi),
        maxHr: clearMax ? null : (maxHr ?? this.maxHr),
        restHr: clearRest ? null : (restHr ?? this.restHr),
        alertHigh: alertHigh ?? this.alertHigh,
        alertLow: alertLow ?? this.alertLow,
        talk: talk ?? this.talk,
      );

  Map<String, dynamic> toJson() => {
        if (lo != null) 'lo': lo,
        if (hi != null) 'hi': hi,
        if (maxHr != null) 'max': maxHr,
        if (restHr != null) 'rest': restHr,
        'up': alertHigh,
        'down': alertLow,
        if (talk.isNotEmpty) 'talk': talk,
      };

  static ZoneSettings fromJson(Object? j) {
    if (j is! Map) return const ZoneSettings();
    int? i(Object? v, int lo, int hi) => v is num && v >= lo && v <= hi ? v.toInt() : null;
    var lo = i(j['lo'], 50, 220);
    var hi = i(j['hi'], 50, 220);
    if (lo == null || hi == null || lo >= hi) lo = hi = null;
    return ZoneSettings(
      lo: lo,
      hi: hi,
      maxHr: i(j['max'], 100, 230),
      restHr: i(j['rest'], zoneRestMin, zoneRestMax),
      alertHigh: j['up'] != false,
      alertLow: j['down'] == true,
      talk: [
        if (j['talk'] is List)
          for (final t in j['talk'] as List)
            if (t is List && t.length == 2 && t[0] is String && t[1] is String) [t[0] as String, t[1] as String],
      ],
    );
  }
}

/// Η ζώνη που ισχύει και από πού βγήκε.
class Zone {
  const Zone({required this.lo, required this.hi, this.rest, required this.max, required this.maxMeasured, required this.manual, this.restMeasured = false});
  final int lo, hi;

  /// Παλμοί ηρεμίας που χρησιμοποιήθηκαν (null: δεν υπήρχαν αρκετές νύχτες, ζώνη από το % των μέγιστων).
  final int? rest;
  final int max;
  final bool maxMeasured;

  /// Οι παλμοί ηρεμίας είναι η μέτρηση του χρήστη ξύπνιος (όχι οι παλμοί ύπνου).
  final bool restMeasured;

  /// Τη ζώνη την έγραψε ο χρήστης.
  final bool manual;
}

/// null αν δεν ξέρουμε την ηλικία (και δεν υπάρχουν μέγιστοι από τεστ) ούτε ζώνη του χρήστη.
Zone? computeZone({int? age, double? restHr, required ZoneSettings s}) {
  final max = s.maxHr ?? (age == null ? null : tanakaMax(age));
  // Η μέτρηση του χρήστη ξύπνιος, αν υπάρχει, αλλιώς οι παλμοί ύπνου ([restHr]).
  final own = s.restHr;
  restHr = own?.toDouble() ?? restHr;
  if (s.manual) {
    return Zone(lo: s.lo!, hi: s.hi!, rest: restHr?.round(), max: max ?? 0, maxMeasured: s.maxHr != null, manual: true, restMeasured: own != null);
  }
  if (max == null) return null;
  final rest = restHr == null || restHr < 30 || restHr >= max - 20 ? null : restHr.round();
  if (rest == null) {
    return Zone(lo: (max * zoneLoMaxPct).round(), hi: (max * zoneHiMaxPct).round(), max: max, maxMeasured: s.maxHr != null, manual: false);
  }
  return Zone(
    lo: (rest + zoneLoPct * (max - rest)).round(),
    hi: (rest + zoneHiPct * (max - rest)).round(),
    rest: rest,
    max: max,
    maxMeasured: s.maxHr != null,
    manual: false,
    restMeasured: own != null,
  );
}

/// Χρόνος (δευτερόλεπτα ενεργού χρόνου) κάτω, μέσα και πάνω από τη ζώνη. [samples]: [″ από την αρχή, bpm], [pauses]:
/// [αρχή, τέλος] σε ″. Κάθε τιμή ισχύει ως την επόμενη, το πολύ [maxGap]″ (μετά: χωρίς μέτρηση, δεν μετρά πουθενά).
({int below, int inZone, int above, int measured}) zoneTimes(List<List<int>> samples, List<List<int>> pauses, int lo, int hi,
    {int maxGap = 15, int? endSec}) {
  var below = 0, inZone = 0, above = 0;
  bool paused(int t) => Session.inPause(pauses, t);
  for (var k = 0; k < samples.length; k++) {
    final t0 = samples[k][0];
    // Μετά το «Τέλος» (λεπτό αποκατάστασης) δεν μετρά.
    if (endSec != null && t0 >= endSec) break;
    final next = k + 1 < samples.length ? samples[k + 1][0] : (endSec ?? t0 + 1);
    var until = math.min(next, t0 + maxGap);
    if (endSec != null) until = math.min(until, endSec);
    final bpm = samples[k][1];
    if (bpm <= 0) continue;
    for (var t = t0; t < until; t++) {
      if (paused(t)) continue;
      if (bpm < lo) {
        below++;
      } else if (bpm > hi) {
        above++;
      } else {
        inZone++;
      }
    }
  }
  return (below: below, inZone: inZone, above: above, measured: below + inZone + above);
}

/// Πρόταση μετά το «τεστ ομιλίας»: +5 αν μπορούσες και να τραγουδήσεις, −5 αν λαχάνιαζες, τίποτα αλλιώς.
int talkShift(String answer) => switch (answer) { 'sing' => 5, 'no' => -5, _ => 0 };

/// Η ζώνη όπως τη στέλνουμε στο ρολόι και την κρατά κάθε περπάτημα: κάτω/πάνω όριο και ποιες δονήσεις είναι ανοιχτές.
class WalkZone {
  const WalkZone(this.lo, this.hi, {this.up = true, this.down = false});
  final int lo, hi;
  final bool up, down;

  Map<String, dynamic> toJson() => {'lo': lo, 'hi': hi, 'up': up, 'down': down};

  static WalkZone? fromJson(Object? j) {
    if (j is! Map || j['lo'] is! num || j['hi'] is! num) return null;
    final lo = (j['lo'] as num).toInt(), hi = (j['hi'] as num).toInt();
    if (lo < 50 || hi > 220 || lo >= hi) return null;
    return WalkZone(lo, hi, up: j['up'] != false, down: j['down'] == true);
  }

  @override
  bool operator ==(Object o) => o is WalkZone && o.lo == lo && o.hi == hi && o.up == up && o.down == down;

  @override
  int get hashCode => Object.hash(lo, hi, up, down);
}

/// Η εβδομάδα (Δευτέρα–Κυριακή) της [now]: λεπτά μέτριας άσκησης από τα περπατήματα (στη ζώνη ή πιο πάνω), μέρες με
/// βάρη, και περπατήματα που δεν μετρούν (χωρίς παλμούς ή ζώνη).
({int moderateMin, int strengthDays, int unmeasuredWalks}) weekMovement(Iterable<Session> sessions, DateTime now) {
  final from = DateTime(now.year, now.month, now.day - (now.weekday - 1));
  final to = DateTime(from.year, from.month, from.day + 7);
  var sec = 0, unmeasured = 0;
  final strength = <String>{};
  for (final s in sessions) {
    if (!s.finished || s.start.isBefore(from) || !s.start.isBefore(to)) continue;
    if (s.isCardio) {
      if (s.activity != null && s.activity != 'walk') continue;
      final z = s.zoneTimes;
      if (z == null) {
        unmeasured++;
      } else {
        sec += z[1] + z[2];
      }
    } else if (!s.stopped && s.setsDone > 0) {
      strength.add('${s.start.year}-${s.start.month}-${s.start.day}');
    }
  }
  return (moderateMin: (sec / 60).round(), strengthDays: strength.length, unmeasuredWalks: unmeasured);
}
