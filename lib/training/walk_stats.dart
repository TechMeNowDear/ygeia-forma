/// Περπάτημα (9/11): ανά χιλιόμετρο, ρυθμός, βήματα ανά λεπτό, πτώση παλμών στο 1′.
///
/// - Ανά km μόνο με GPS: χωρίς GPS η απόσταση βγαίνει από τα βήματα και οι χρόνοι ανά km δεν είναι αξιόπιστοι.
/// - Χρόνος = ενεργός χρόνος του ρολογιού (χωρίς τις παύσεις). Παλμοί ανά km = μέσος όρος των τιμών μέσα στο km,
///   χωρίς όσες έπεσαν σε παύση, με τουλάχιστον [minSamples] τιμές (αλλιώς null).
library;

import 'session.dart';
import 'set_hr.dart' show minSamples;

class KmSplit {
  const KmSplit(this.label, this.sec, this.hr, {this.partial = false});

  /// «1», «2»… ή για το τελευταίο κομμάτι «0,41».
  final String label;

  /// Ενεργός χρόνος του κομματιού (δευτερόλεπτα).
  final int sec;

  /// Μέσοι παλμοί στο κομμάτι, ή null.
  final int? hr;

  /// Κομμάτι μικρότερο από 1 km: ο χρόνος του δεν είναι «ανά km».
  final bool partial;
}

/// Οι παλμοί χωρίς όσους έπεσαν σε παύση, ταξινομημένοι.
List<List<int>> activeHr(Session s) {
  // [αρχή, τέλος): ίδιος κανόνας με το ρολόι και τον χρόνο ζώνης (round1, S12-16).
  return [for (final p in s.hr) if (!Session.inPause(s.pauses, p[0])) p]..sort((a, b) => a[0].compareTo(b[0]));
}

int? _mean(List<List<int>> hr, int from, int to) {
  var sum = 0, n = 0;
  for (final p in hr) {
    if (p[0] <= from || p[0] > to) continue;
    sum += p[1];
    n++;
  }
  return n < minSamples ? null : (sum / n).round();
}

/// Ο πίνακας ανά km· κενός χωρίς GPS ή χωρίς ολόκληρο χιλιόμετρο.
List<KmSplit> walkSplits(Session s) {
  if (s.gps != true || s.splits.isEmpty) return const [];
  final hr = activeHr(s);
  final out = <KmSplit>[];
  var prevActive = 0, prevWall = 0;
  for (var k = 0; k < s.splits.length; k++) {
    final active = s.splits[k][0], wall = s.splits[k][1];
    out.add(KmSplit('${k + 1}', active - prevActive, _mean(hr, prevWall, wall)));
    prevActive = active;
    prevWall = wall;
  }
  final m = s.meters;
  final total = s.cardioSec;
  final end = s.end?.difference(s.start).inSeconds;
  if (m != null && total != null && end != null) {
    final rest = m - s.splits.length * 1000;
    // Το τελευταίο κομμάτι, αν είναι τουλάχιστον 50 m (αλλιώς είναι θόρυβος του GPS).
    if (rest >= 50 && total > prevActive) {
      out.add(KmSplit((rest / 1000).toStringAsFixed(2).replaceAll('.', ','), total - prevActive, _mean(hr, prevWall, end), partial: true));
    }
  }
  return out;
}

/// Ρυθμός (δευτερόλεπτα ανά km), από ενεργό χρόνο και την απόσταση που δείχνουμε ([shownMeters]: GPS, αλλιώς από τα
/// βήματα με «≈»)· null αν λείπουν ή η απόσταση < 100 m.
int? paceSecPerKm(Session s) {
  final d = shownMeters(s), t = s.cardioSec ?? (s.cardioMinutes == null ? null : s.cardioMinutes! * 60);
  if (d == null || t == null || d.meters < 100 || t <= 0) return null;
  return (t / (d.meters / 1000)).round();
}

/// Βήματα ανά λεπτό (ενεργός χρόνος)· null αν λείπουν.
int? cadence(Session s) {
  final st = s.steps, t = s.cardioSec;
  if (st == null || t == null || t < 60) return null;
  return (st / (t / 60)).round();
}

/// Η απόσταση που δείχνουμε (m) και αν είναι εκτίμηση από τα βήματα («≈»), ή null αν δεν μετρήθηκε. Ίδιος κανόνας με
/// το ρολόι (Protocol.kt: shownDistance, 14/11): του GPS όταν μέτρησε (τουλάχιστον 10 m και τουλάχιστον η μισή της
/// εκτίμησης από τα βήματα), αλλιώς η εκτίμηση ([Session.metersEst]: βήματα × μήκος βήματος). Χωρίς GPS (κλειστή
/// τοποθεσία) την απόσταση τη βγάζει το ρολόι από τα βήματα: κι αυτή «≈».
({double meters, bool approx})? pickMeters(double m, double est, bool? gps) {
  if (m >= 10 && (gps == false || est < 10 || m >= est * 0.5)) return (meters: m, approx: gps == false);
  if (est >= 10) return (meters: est, approx: true);
  return null;
}

({double meters, bool approx})? shownMeters(Session s) => s.isCardio ? pickMeters(s.meters ?? 0, s.metersEst ?? 0, s.gps) : null;

/// Ο ίδιος κανόνας για τα «ζωντανά» του ρολογιού («m», «mest», «gps»).
({double meters, bool approx})? liveMeters(Map<String, dynamic> l) =>
    pickMeters((l['m'] as num?)?.toDouble() ?? 0, (l['mest'] as num?)?.toDouble() ?? 0, l['gps'] is bool ? l['gps'] as bool : null);

/// Η απόσταση βγήκε από τα βήματα (έλεγχος 9/11, RT-12· 14/11 και μέσα στο σπίτι με GPS χωρίς σήμα): «≈».
bool distanceFromSteps(Session s) => s.isCardio && (shownMeters(s)?.approx ?? s.gps == false);

/// «2,31» από μέτρα.
String kmText(double meters) => (meters / 1000).toStringAsFixed(2).replaceAll('.', ',');

/// Απόσταση σε km για τις οθόνες: «2,31», «≈ 2,31» από τα βήματα, «—» (null) όταν δεν μετρήθηκε απόσταση (RT-18: πριν
/// «0,00»). Δοκιμή στις συσκευές 14/11: μέσα στο σπίτι, GPS ανοιχτό χωρίς σήμα, 812 βήματα και 0 m: η σύνοψη έγραφε
/// «0,00 km», σαν να μην περπάτησες. Τώρα: «≈» από τα βήματα (ρολόι από #114), αλλιώς «—».
String? kmValue(Session s) {
  final d = shownMeters(s);
  if (d == null) return null;
  return d.approx ? '≈ ${kmText(d.meters)}' : kmText(d.meters);
}

/// Το μήκος του βήματος (m) για την απόσταση χωρίς GPS (14/11): από τα δικά σου περπατήματα με GPS (μέτρα ÷ βήματα,
/// τα τελευταία ως 5 με τουλάχιστον 500 m και 500 βήματα), αλλιώς από το ύψος: περίπου 0,415 × ύψος στους άνδρες και
/// 0,413 στις γυναίκες (πρόχειρος κανόνας με απόκλιση ±10%· γι' αυτό φαίνεται με «≈»). null χωρίς τίποτα από τα δύο.
double? strideFor(List<Session> sessions, {double? heightCm, String? sex}) {
  var m = 0.0, st = 0;
  var n = 0;
  for (final s in sessions.reversed) {
    if (n >= 5) break;
    if (!s.isCardio || !s.finished || s.gps != true || (s.activity ?? 'walk') != 'walk') continue;
    final mm = s.meters ?? 0, ss = s.steps ?? 0;
    if (mm < 500 || ss < 500) continue;
    final r = mm / ss;
    if (r < 0.4 || r > 1.2) continue; // GPS που «πήδηξε» ή βήματα που δεν μετρήθηκαν
    m += mm;
    st += ss;
    n++;
  }
  if (st > 0) return m / st;
  if (heightCm == null || heightCm < 120 || heightCm > 230) return null;
  return heightCm / 100 * (sex == 'f' ? 0.413 : 0.415);
}
/// Ο ρυθμός γράφεται με το [paceText] του format.dart («11:15 /km»).

/// Συνολικός χρόνος παύσεων (δευτερόλεπτα).
int pausedSec(Session s) => s.pauses.fold(0, (a, p) => a + (p[1] - p[0]).clamp(0, 1 << 30));
