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
  bool paused(int t) => s.pauses.any((p) => t >= p[0] && t <= p[1]);
  return [for (final p in s.hr) if (!paused(p[0])) p]..sort((a, b) => a[0].compareTo(b[0]));
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

/// Ρυθμός (δευτερόλεπτα ανά km), από ενεργό χρόνο και απόσταση· null αν λείπουν ή η απόσταση < 100 m.
int? paceSecPerKm(Session s) {
  final m = s.meters, t = s.cardioSec ?? (s.cardioMinutes == null ? null : s.cardioMinutes! * 60);
  if (m == null || t == null || m < 100 || t <= 0) return null;
  return (t / (m / 1000)).round();
}

/// Βήματα ανά λεπτό (ενεργός χρόνος)· null αν λείπουν.
int? cadence(Session s) {
  final st = s.steps, t = s.cardioSec;
  if (st == null || t == null || t < 60) return null;
  return (st / (t / 60)).round();
}

/// «13′17″».
String paceText(int sec) => '${sec ~/ 60}′${(sec % 60).toString().padLeft(2, '0')}″';

/// Συνολικός χρόνος παύσεων (δευτερόλεπτα).
int pausedSec(Session s) => s.pauses.fold(0, (a, p) => a + (p[1] - p[0]).clamp(0, 1 << 30));
