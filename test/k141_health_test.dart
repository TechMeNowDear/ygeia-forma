// Βαθύς έλεγχος 20/11/2026, κατηγορία 3 (καρδιά, ύπνος, πίεση, σάκχαρο, οξυγόνο, τάσεις): οι διορθώσεις K3-S-01…13 και
// K3C-01…08, και όσα βρήκε ο ανεξάρτητος ελεγκτής (K3-review R1–R13). Μόνο επινοημένες τιμές και σταθερές ημερομηνίες.
// Οι αναμενόμενες τιμές του κανόνα της νύχτας επαληθεύτηκαν με δύο ανεξάρτητες μεταφορές σε Python (του ειδικού k3-calc
// για τον παλιό κανόνα και του ανεξάρτητου ελεγκτή για τον νέο: audit-141/k3-review/r_nights.py, t07_variant.py).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart' show NightOxygen, ouraRulesVersion;
import 'package:ygeia_forma/history.dart' show K;
import 'package:ygeia_forma/hrv_trend.dart';
import 'package:ygeia_forma/oxygen_note.dart';
import 'package:ygeia_forma/pages/oxygen_widgets.dart' show watchLowText;
import 'package:ygeia_forma/pages/vitals_page.dart';
import 'package:ygeia_forma/reference.dart';
import 'package:ygeia_forma/sleep_gaps.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/trends.dart';
import 'package:ygeia_forma/vitals.dart';

final _now = DateTime(2026, 11, 24, 9);

/// Ένα κομμάτι ύπνου: μέρα και ώρα αρχής/τέλους του Νοεμβρίου 2026, και λεπτά πραγματικού ύπνου.
SleepSpan _p(int d1, int h1, int m1, int d2, int h2, int m2, int minutes) =>
    (start: DateTime(2026, 11, d1, h1, m1), end: DateTime(2026, 11, d2, h2, m2), minutes: minutes);

/// «24: 94+144 | υπνάκοι 24: 81» (ημερομηνία: λεπτά κάθε κομματιού).
String _grouped(List<SleepSpan> pieces,
    {int? Function(DateTime from, DateTime to)? stepsBetween, DateTime? Function(DateTime date)? napLockOf}) {
  final sorted = [...pieces]..sort((a, b) => a.start.compareTo(b.start));
  final g = groupSleepPieces<SleepSpan>(sorted, (x) => x, stepsBetween: stepsBetween, napLockOf: napLockOf);
  final nights = [for (final n in g.nights) '${n.date.day}: ${n.parts.map((x) => x.minutes).join('+')}'].join(' , ');
  final napDays = g.naps.keys.toList()..sort();
  final naps = [for (final d in napDays) '${d.day}: ${g.naps[d]!.map((x) => x.minutes).join('+')}'].join(' , ');
  // Κανένα κομμάτι δεν χάνεται ούτε μετριέται δύο φορές.
  final all = [for (final n in g.nights) ...n.parts, for (final v in g.naps.values) ...v];
  expect(all.length, pieces.length);
  expect(all.toSet().length, pieces.length);
  return naps.isEmpty ? nights : '$nights | υπνάκοι $naps';
}

Vital _bp(int s, int d, {int? pulse, int daysAgo = 0, String id = 'a'}) =>
    Vital(id: id, kind: VitalKind.bp, at: _now.subtract(Duration(days: daysAgo)), sys: s, dia: d, pulse: pulse);

String _avgText(int s, int d) =>
    bpAverageText(bpAverage([for (var i = 0; i < 12; i++) _bp(s, d, daysAgo: i % 3, id: 'm$i')], _now)!);

Vital _glu(double v, [GlucoseWhen w = GlucoseWhen.random]) => Vital(id: 'g', kind: VitalKind.glucose, at: _now, glucose: v, when: w);

void main() {
  // ---------------------------------------------------------------------------------------------------------- K3C-01
  group('K3C-01: ο κανόνας της νύχτας για ύπνο μετά τις 03:00 (κύρια ομάδα 1γ)', () {
    test('03:30–05:15, ξύπνιος 95 λεπτά, 06:50–09:30: μία νύχτα 238 λεπτών (πριν: 94 λεπτά και «υπνάκος» 144)', () {
      expect(_grouped([_p(24, 3, 30, 24, 5, 15, 94), _p(24, 6, 50, 24, 9, 30, 144)]), '24: 94+144');
    });

    test('λαγοκοίμισμα 22:15–23:45 και ύπνος 06:30–12:30: νύχτα ο ύπνος, υπνάκος το λαγοκοίμισμα (πριν: ανάποδα)', () {
      expect(_grouped([_p(23, 22, 15, 23, 23, 45, 81), _p(24, 6, 30, 24, 12, 30, 324)]), '24: 324 | υπνάκοι 24: 81');
      // Και όταν ο ύπνος αρχίζει μετά τις 08:00 (κανένα λεπτό στο 22:00–08:00): θέλει 2 φορές τον ύπνο της κύριας.
      expect(_grouped([_p(23, 23, 10, 23, 23, 30, 18), _p(24, 8, 10, 24, 14, 0, 315)]), '24: 315 | υπνάκοι 24: 18');
      expect(_grouped([_p(23, 22, 15, 23, 23, 45, 81), _p(24, 8, 10, 24, 14, 0, 315)]), '24: 315 | υπνάκοι 24: 81');
    });

    test('τρία κομμάτια και δύο μέρες: η επόμενη νύχτα δεν επηρεάζεται', () {
      expect(
          _grouped([_p(23, 22, 30, 23, 23, 0, 28), _p(24, 3, 30, 24, 5, 15, 94), _p(24, 6, 50, 24, 9, 30, 144)]),
          '24: 94+144 | υπνάκοι 24: 28',
          reason: 'το λαγοκοίμισμα απέχει πάνω από 4 ώρες');
      expect(
          _grouped([_p(23, 22, 15, 23, 23, 45, 81), _p(24, 6, 30, 24, 12, 30, 324), _p(25, 3, 30, 25, 8, 30, 270)]),
          '24: 324 , 25: 270 | υπνάκοι 24: 81');
    });

    test('ποτέ προς τα πίσω: μεγάλος βραδινός ύπνος 18:00–22:30 δεν παίρνει τη θέση της νύχτας που ακολουθεί', () {
      expect(_grouped([_p(23, 18, 0, 23, 22, 30, 250), _p(24, 3, 0, 24, 7, 0, 230)]), '24: 230 | υπνάκοι 24: 250');
      expect(_grouped([_p(23, 18, 0, 23, 22, 30, 250), _p(24, 2, 0, 24, 6, 0, 230)]), '24: 230 | υπνάκοι 24: 250');
    });

    // Απόφαση χρήστη 21/11 (Α9β): «πάντα ο μεγαλύτερος». Ως την #150 ήθελε 3 ώρες ΚΑΙ 2 φορές τον ύπνο της κύριας.
    test('Α9β: ύπνος που αρχίζει μετά τις 08:00 (ως τις 12:00) γίνεται νύχτα όταν είναι μεγαλύτερος από τη νύχτα', () {
      // Κενό πάνω από 4 ώρες: δεν ενώνονται· νύχτα ο μεγαλύτερος, το άλλο υπνάκος (απέχει πάνω από 2 ώρες, Α10).
      expect(_grouped([_p(24, 0, 0, 24, 4, 30, 250), _p(24, 11, 30, 24, 16, 30, 280)]), '24: 280 | υπνάκοι 24: 250');
      expect(_grouped([_p(23, 23, 0, 24, 2, 0, 170), _p(24, 10, 30, 24, 14, 0, 200)]), '24: 200 | υπνάκοι 24: 170');
      expect(_grouped([_p(24, 3, 30, 24, 5, 0, 85), _p(24, 10, 0, 24, 13, 0, 170)]), '24: 170 | υπνάκοι 24: 85');
      expect(_grouped([_p(24, 2, 52, 24, 3, 55, 63), _p(24, 10, 30, 24, 12, 51, 141)]), '24: 141 | υπνάκοι 24: 63');
      expect(_grouped([_p(24, 3, 30, 24, 5, 0, 85), _p(24, 10, 0, 24, 13, 30, 190)]), '24: 190 | υπνάκοι 24: 85');
      expect(_grouped([_p(24, 0, 10, 24, 1, 0, 45), _p(24, 8, 10, 24, 14, 0, 315)]), '24: 315 | υπνάκοι 24: 45');
      // Κενό ως 4 ώρες το πρωί, χωρίς βήματα (Α9α): μία νύχτα με τα δύο κομμάτια.
      expect(_grouped([_p(24, 3, 30, 24, 6, 0, 140), _p(24, 9, 0, 24, 12, 30, 200)]), '24: 140+200');
      // Μικρότερος: μένει υπνάκος. Από τις 12:00: πάντα υπνάκος.
      expect(_grouped([_p(24, 1, 0, 24, 5, 0, 230), _p(24, 10, 30, 24, 12, 0, 85)]), '24: 230 | υπνάκοι 24: 85');
      expect(_grouped([_p(24, 1, 0, 24, 2, 30, 85), _p(24, 12, 0, 24, 16, 0, 230)]), '24: 85 | υπνάκοι 24: 230');
      expect(fallbackMainMinutes, 60);
    });

    // Απόφαση χρήστη 21/11 (Α9α, Α10).
    test('Α9α: πρωινό κομμάτι ως 4 ώρες μετά, χωρίς περπάτημα: μία νύχτα· με περπάτημα: υπνάκος', () {
      // 03:30–07:00 (200) και 08:40–10:00 (75): κενό 1 ώρα 40 λεπτά (πριν: πάνω από 90 λεπτά → υπνάκος).
      final pieces = [_p(24, 3, 30, 24, 7, 0, 200), _p(24, 8, 40, 24, 10, 0, 75)];
      expect(_grouped(pieces), '24: 200+75');
      expect(_grouped(pieces, stepsBetween: (a, b) => 12), '24: 200+75');
      expect(_grouped(pieces, stepsBetween: (a, b) => 900), '24: 200 | υπνάκοι 24: 75');
      // Κενό πάνω από 4 ώρες: υπνάκος, όπως πριν.
      expect(_grouped([_p(24, 3, 30, 24, 7, 0, 200), _p(24, 11, 10, 24, 11, 50, 35)]), '24: 200 | υπνάκοι 24: 35');
      expect((morningJoinGap, morningLongJoinGap, maxGap), (const Duration(minutes: 90), const Duration(hours: 4), const Duration(hours: 4)));
      // Από τις 12:00, με κενό πάνω από 90 λεπτά: υπνάκος (όπως πριν). Ως 90 λεπτά: όπως πριν, και μετά τις 12:00.
      expect(_grouped([_p(24, 6, 0, 24, 10, 0, 230), _p(24, 12, 0, 24, 13, 0, 55)]), '24: 230 | υπνάκοι 24: 55');
      expect(_grouped([_p(24, 6, 0, 24, 11, 0, 290), _p(24, 12, 20, 24, 13, 0, 35)]), '24: 290+35');
    });

    test('Α10: λαγοκοίμισμα πριν από τη νύχτα: χωριστά όταν απέχει πάνω από 2 ώρες', () {
      // Καναπές 22:15–23:45 (85) και ύπνος 03:30–09:00 (310): κενό 3 ώρες 45 λεπτά (πριν: ΜΙΑ νύχτα, «ώρα ύπνου 22:25»).
      expect(_grouped([_p(23, 22, 15, 23, 23, 45, 85), _p(24, 3, 30, 24, 9, 0, 310)]), '24: 310 | υπνάκοι 24: 85');
      // Ως 2 ώρες: η ίδια νύχτα.
      expect(_grouped([_p(23, 22, 15, 23, 23, 45, 85), _p(24, 1, 30, 24, 8, 0, 360)]), '24: 85+360');
      expect(eveningJoinGap, const Duration(hours: 2));
    });

    test('K3-review R2: όταν η «νύχτα» είναι λαγοκοίμισμα κάτω από 60 λεπτά, αρκεί ύπνος 60 λεπτών και 2 φορές (όπως το 1β)', () {
      // Λαγοκοίμισμα 18 λεπτών + ύπνος 08:30–11:15 (150): χωρίς το λαγοκοίμισμα ο ίδιος ύπνος ΕΙΝΑΙ νύχτα (1β).
      expect(_grouped([_p(23, 23, 10, 23, 23, 30, 18), _p(24, 8, 30, 24, 11, 15, 150)]), '24: 150 | υπνάκοι 24: 18');
      expect(_grouped([_p(24, 8, 30, 24, 11, 15, 150)]), '24: 150');
      // 42 λεπτά στις 04:36 και 175 στις 09:06: νύχτα και τα δύο (το πρώτο απέχει κάτω από 4 ώρες).
      expect(_grouped([_p(24, 4, 36, 24, 5, 20, 42), _p(24, 9, 6, 24, 12, 28, 175)]), '24: 42+175');
      // Το «σκαλοπάτι» των 08:00 έφυγε (απόφαση χρήστη 21/11, Α9): νύχτα 80 λεπτών και 165 λεπτά από τις 08:05, με
      // κενό ως 4 ώρες και χωρίς βήματα → μία νύχτα, όπως και από τις 07:55.
      expect(_grouped([_p(24, 4, 30, 24, 6, 0, 80), _p(24, 8, 5, 24, 11, 0, 165)]), '24: 80+165');
      expect(_grouped([_p(24, 4, 30, 24, 6, 0, 80), _p(24, 7, 55, 24, 10, 50, 165)]), '24: 80+165');
    });

    test('K3-review R1: η σύγκριση γίνεται με ΟΛΗ τη νύχτα (όλα τα κομμάτια της), όχι με ένα κομμάτι', () {
      int walk(DateTime a, DateTime b) => 1500;
      // F1: η νύχτα 03:30–06:00 κομμένη σε 70 + 68 λεπτά (κενό 4 λεπτά) και ύπνος 09:00–12:30 (200). Από την #151 (Α9α):
      // κενό 3 ώρες το πρωί χωρίς βήματα → μία νύχτα (πριν: 200 < 2 × 138, υπνάκος).
      expect(_grouped([_p(24, 3, 30, 24, 4, 43, 70), _p(24, 4, 47, 24, 6, 0, 68), _p(24, 9, 0, 24, 12, 30, 200)]),
          '24: 70+68+200');
      // F3: συμβατική νύχτα 375 λεπτών σε 3 κομμάτια και ύπνος 11:00–15:30 (265): η νύχτα ΔΕΝ γίνεται υπνάκος.
      expect(
          _grouped([_p(23, 23, 30, 24, 1, 40, 120), _p(24, 1, 50, 24, 4, 0, 125), _p(24, 4, 5, 24, 6, 20, 130), _p(24, 11, 0, 24, 15, 30, 265)]),
          '24: 120+125+130 | υπνάκοι 24: 265');
      // F4: νύχτα 290 λεπτών σε 3 κομμάτια, ξύπνιος 3 ώρες 45 λεπτά με βήματα, 07:45–09:45 (115): υπνάκος.
      expect(
          _grouped([_p(23, 22, 30, 24, 0, 15, 100), _p(24, 0, 30, 24, 2, 0, 85), _p(24, 2, 10, 24, 4, 0, 105), _p(24, 7, 45, 24, 9, 45, 115)],
              stepsBetween: walk),
          '24: 100+85+105 | υπνάκοι 24: 115');
      // F5: νύχτα 340 λεπτών σε 3 κομμάτια, σηκώθηκε 90 λεπτά με 1.500 βήματα, 07:30–10:00 (145): υπνάκος, με βήματα ΚΑΙ με
      // το αποθηκευμένο κλείδωμα όταν τα βήματα δεν υπάρχουν πια (ο κανόνας 4 και το κλείδωμα ισχύουν όπως πριν).
      final f5 = [_p(23, 23, 30, 24, 1, 30, 115), _p(24, 1, 45, 24, 3, 15, 85), _p(24, 3, 30, 24, 6, 0, 140), _p(24, 7, 30, 24, 10, 0, 145)];
      expect(_grouped(f5, stepsBetween: walk), '24: 115+85+140 | υπνάκοι 24: 145');
      expect(_grouped(f5, napLockOf: (_) => DateTime(2026, 11, 24, 7, 30)), '24: 115+85+140 | υπνάκοι 24: 145');
      // F6: 03:30–05:15 (94) + 05:40–07:30 (100) και ύπνος 11:40–15:10 (200). Από την #151 (Α9β, «πάντα ο μεγαλύτερος»):
      // 200 > 194 → νύχτα ο ύπνος των 11:40· τα δύο πρώτα απέχουν πάνω από 2 ώρες (Α10) → υπνάκοι.
      expect(_grouped([_p(24, 3, 30, 24, 5, 15, 94), _p(24, 5, 40, 24, 7, 30, 100), _p(24, 11, 40, 24, 15, 10, 200)]),
          '24: 200 | υπνάκοι 24: 94+100');
      // F7: το σενάριο του K3C-01 (94 + 144) και τρίτος ύπνος 10:30–14:00 (200) μετά από 1 ώρα με βήματα: η νύχτα είναι
      // 238 λεπτά, ο τρίτος ύπνος υπνάκος (πρώτα γίνεται κύρια το 144, η νύχτα ξαναχτίζεται, και 200 < 2 × 238).
      expect(_grouped([_p(24, 3, 30, 24, 5, 15, 94), _p(24, 6, 50, 24, 9, 30, 144), _p(24, 10, 30, 24, 14, 0, 200)], stepsBetween: walk),
          '24: 94+144 | υπνάκοι 24: 200');
    });

    test('αλλαγή ώρας 25/10/2026 (25 ώρες): 03:30–05:15 και 06:50–09:30 μένουν μία νύχτα', () {
      SleepSpan o(int h1, int m1, int h2, int m2, int minutes) =>
          (start: DateTime(2026, 10, 25, h1, m1), end: DateTime(2026, 10, 25, h2, m2), minutes: minutes);
      final g = groupSleepPieces<SleepSpan>([o(3, 30, 5, 15, 94), o(6, 50, 9, 30, 144)], (x) => x);
      expect(g.nights.single.parts.map((x) => x.minutes), [94, 144]);
      expect(g.nights.single.date, DateTime(2026, 10, 25));
      expect(g.naps, isEmpty);
    });

    test('ίδια λεπτά ύπνου: μένει η κύρια του παραθύρου· οι πρωινοί υπνάκοι με βήματα μένουν υπνάκοι', () {
      // Χωρίς βήματα (άγνωστα), κενό 1 ώρα 40 λεπτά το πρωί: από την #151 (Α9α) μία νύχτα.
      expect(_grouped([_p(24, 3, 30, 24, 5, 30, 110), _p(24, 7, 10, 24, 9, 30, 110)]), '24: 110+110');
      int steps(DateTime a, DateTime b) => 300;
      expect(_grouped([_p(24, 3, 30, 24, 8, 0, 243), _p(24, 9, 0, 24, 9, 40, 36)], stepsBetween: steps), '24: 243 | υπνάκοι 24: 36');
      expect(_grouped([_p(23, 23, 30, 24, 6, 30, 380), _p(24, 7, 30, 24, 8, 15, 40)], stepsBetween: steps), '24: 380 | υπνάκοι 24: 40');
      expect(_grouped([_p(24, 3, 30, 24, 8, 30, 270), _p(24, 9, 15, 24, 10, 0, 40)], stepsBetween: steps), '24: 270 | υπνάκοι 24: 40');
    });

    test('συμβατικό ωράριο: όταν το πρωινό κομμάτι είναι το μεγαλύτερο, το πρώτο ενώνεται μαζί του (κανόνας 2, ως 4 ώρες)', () {
      int steps(DateTime a, DateTime b) => 200;
      expect(_grouped([_p(24, 0, 0, 24, 5, 0, 280), _p(24, 6, 30, 24, 12, 0, 300)], stepsBetween: steps), '24: 280+300');
      expect(_grouped([_p(23, 23, 30, 24, 4, 0, 240), _p(24, 7, 30, 24, 12, 0, 250)]), '24: 240+250');
    });

    test('αποθηκευμένη απόφαση «υπνάκος» ως την αρχή της νέας κύριας δεν μετρά (είχε παρθεί με άλλη κύρια)', () {
      // Με τους παλιούς κανόνες: κύρια το 00:00–05:00, και το 06:30 είχε γίνει «υπνάκος λόγω βημάτων» (κλείδωμα 06:30).
      // Τώρα κύρια είναι το 06:30–12:00· το 12:40–13:30 (κενό 40 λεπτά, βήματα άγνωστα) ενώνεται, δεν το κόβει το παλιό κλείδωμα.
      final lock = DateTime(2026, 11, 24, 6, 30);
      expect(
          _grouped([_p(24, 0, 0, 24, 5, 0, 280), _p(24, 6, 30, 24, 12, 0, 300), _p(24, 12, 40, 24, 13, 30, 45)],
              napLockOf: (_) => lock),
          '24: 280+300+45');
    });

    test('οι κανόνες του Oura ξαναδιαβάζονται (έκδοση 3, αποφάσεις 21/11)· οι παλιές περιπτώσεις του merge2_test', () {
      expect(ouraRulesVersion, 3);
      expect(_grouped([_p(2, 23, 43, 3, 2, 40, 152), _p(3, 3, 50, 3, 7, 8, 178)]), '3: 152+178');
      expect(_grouped([_p(2, 20, 30, 2, 21, 30, 60), _p(2, 23, 30, 3, 7, 0, 420)]), '3: 60+420');
      expect(_grouped([_p(2, 19, 30, 2, 20, 30, 60), _p(2, 23, 30, 3, 7, 0, 420)]), '3: 420 | υπνάκοι 3: 60');
      // Α9α (21/11): κενό 2 ώρες 30 λεπτά το πρωί, χωρίς βήματα: μία νύχτα (πριν: υπνάκος).
      expect(_grouped([_p(2, 23, 30, 3, 7, 0, 420), _p(3, 9, 30, 3, 10, 30, 55)]), '3: 420+55');
      expect(_grouped([_p(3, 0, 10, 3, 0, 50, 35), _p(3, 5, 0, 3, 7, 30, 145)]), '3: 145 | υπνάκοι 3: 35');
      expect(_grouped([_p(2, 20, 0, 2, 21, 40, 95)]), ' | υπνάκοι 3: 95');
      expect(_grouped([_p(3, 8, 30, 3, 13, 0, 250)]), '3: 250', reason: 'πρωινός ύπνος μόνο (1β)');
    });
  });

  // ------------------------------------------------------------------------------------------------- πίεση και σφυγμοί
  group('πίεση', () {
    test('K3-S-04 / K3C-02: 120 ή 70 ακριβώς είναι ήδη «αυξημένη» (ESC 2024: μη αυξημένη κάτω από 120 ΚΑΙ κάτω από 70)', () {
      for (final (s, d) in [(120, 70), (120, 65), (115, 70)]) {
        expect(_avgText(s, d), contains('«αυξημένη»'), reason: '$s/$d');
        expect(_avgText(s, d), contains('Από 120/70 ως κάτω από 135/85'));
      }
      expect(_avgText(119, 69), contains('Κάτω από 120/70: όχι αυξημένη (ESC 2024).'));
      expect(_avgText(134, 84), contains('«αυξημένη»'));
      expect(_avgText(135, 80), contains('πάνω από το όριο'));
    });

    test('K3-S-05: μέσος όρος από 160/100 λέει και πότε («μέσα σε λίγες μέρες»)· κάτω από αυτό όχι', () {
      expect(_avgText(160, 90), contains('μέσα σε λίγες μέρες'));
      expect(_avgText(150, 100), contains('μέσα σε λίγες μέρες'));
      expect(_avgText(165, 102), contains('πολύ πάνω από το όριο των 135/85'));
      expect(_avgText(159, 99), isNot(contains('λίγες μέρες')));
      expect(_avgText(159, 99), contains('πάνω από το όριο'));
      // K3-review R5: μέσος όρος από 180/110 → «σήμερα», όπως λέει η σημείωση κάθε τέτοιας μέτρησης.
      expect(_avgText(182, 112), contains('Μίλα σήμερα με γιατρό'));
      expect(_avgText(182, 112), contains('166 ή 112'));
      expect(_avgText(180, 90), contains('Μίλα σήμερα με γιατρό'));
      expect(_avgText(170, 110), contains('Μίλα σήμερα με γιατρό'));
      expect(_avgText(179, 109), contains('μέσα σε λίγες μέρες'));
      expect(_avgText(179, 109), isNot(contains('σήμερα')));
    });

    test('K3-S-11: η γραμμή της αναφοράς για τον γιατρό έχει αριθμούς και όρια, όχι προτροπές προς τον ασθενή', () {
      final many = bpAverage([for (var i = 0; i < 14; i++) _bp(128, 82, daysAgo: i % 5, id: 'm$i')], _now)!;
      final few = bpAverage([_bp(128, 82), _bp(130, 84, daysAgo: 1, id: 'b')], _now)!;
      for (final t in [bpAverageReportText(many), bpAverageReportText(few)]) {
        expect(t, isNot(contains('γιατρό σου')));
        expect(t, isNot(contains('Μέτρα')));
        expect(t, startsWith('Μέσος όρος 7 ημερών: '));
      }
      expect(bpAverageReportText(many), contains('128/82 (14 μετρήσεις σε 5 μέρες). Όρια για μετρήσεις στο σπίτι (ESC 2024)'));
      expect(bpAverageReportText(few), contains('Λίγες μετρήσεις για συμπέρασμα'));
      final high = bpAverage([for (var i = 0; i < 14; i++) _bp(165, 102, daysAgo: i % 5, id: 'h$i')], _now)!;
      expect(bpAverageReportText(high), isNot(contains('λίγες μέρες')));
    });

    test('K3-S-02: σφυγμοί πάνω από 100 ή κάτω από 40 στο πιεσόμετρο παίρνουν σημείωση· 40–100 και χωρίς σφυγμούς όχι', () {
      expect(pulseNote(_bp(126, 84, pulse: 101)), contains('Σφυγμοί πάνω από 100 σε ηρεμία'));
      expect(pulseNote(_bp(126, 84, pulse: 130)), contains('166 ή 112'));
      // K3-review R4: πάνω από 120 που μένει και μετά την ηρεμία → γιατρός την ίδια μέρα (όπως το κείμενο του ΗΚΓ).
      expect(pulseNote(_bp(126, 84, pulse: 135)), contains('μίλα με γιατρό την ίδια μέρα'));
      expect(pulseNote(_bp(126, 84, pulse: 121)), contains('πάνω από 120'));
      expect(pulseNote(_bp(126, 84, pulse: 120)), isNot(contains('την ίδια μέρα')));
      expect(pulseNote(_bp(126, 84, pulse: 110)), isNot(contains('την ίδια μέρα')));
      expect(pulseNote(_bp(126, 84, pulse: 39)), contains('δεν είναι το συνηθισμένο σου'));
      expect(pulseNote(_bp(126, 84, pulse: 39)), contains('Πολύ αργοί σφυγμοί'));
      expect(pulseNote(_bp(126, 84, pulse: 100)), isNull);
      expect(pulseNote(_bp(126, 84, pulse: 40)), isNull);
      expect(pulseNote(_bp(126, 84, pulse: 64)), isNull);
      expect(pulseNote(_bp(126, 84)), isNull);
      expect(pulseNote(_glu(95)), isNull);
      expect(restHrException, contains('πιεσόμετρο'), reason: 'το ⓘ λέει ΠΟΥ βλέπεις παλμούς ηρεμίας');
    });

    testWidgets('K3-S-01 και K3-S-02 στην οθόνη: «με πιεσόμετρο μπράτσου (όχι … το ρολόι)» και η σημείωση σφυγμών', (t) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(420, 1600);
      addTearDown(t.view.reset);
      final s = VitalsStore(io: MemoryVitalsIO());
      await s.load();
      await s.add(_bp(128, 82, pulse: 112, id: 'fast'));
      await s.add(_bp(127, 81, pulse: 70, id: 'ok', daysAgo: 1));
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: VitalsPage(store: s, now: () => _now)));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('vital-pulse-note-fast')), findsOneWidget);
      expect(find.byKey(const ValueKey('vital-pulse-note-ok')), findsNothing);
      await t.tap(find.byKey(const ValueKey('vital-add')));
      await t.pumpAndSettle();
      expect(find.textContaining('Με πιεσόμετρο μπράτσου (όχι καρπού και όχι το ρολόι'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------------------------- σάκχαρο, καρδιογράφημα
  test('K3-S-06: σάκχαρο 55–69 χωρίς φάρμακα «συνήθως δεν σημαίνει κάτι»· κάτω από 55 «χαμηλό» με 166/112', () {
    expect(glucoseNote(_glu(67, GlucoseWhen.fasting)), contains('συνήθως δεν σημαίνει κάτι'));
    expect(glucoseNote(_glu(67)), isNot(contains('χαμηλό σάκχαρο')));
    expect(glucoseNote(_glu(67)), contains('166 ή 112'), reason: 'με συμπτώματα');
    expect(glucoseNote(_glu(55)), contains('55–69'));
    expect(glucoseNote(_glu(54.6)), contains('55–69'), reason: 'κρίνεται όπως φαίνεται (55)');
    expect(glucoseNote(_glu(54)), contains('Κάτω από 55 mg/dL: χαμηλό σάκχαρο'));
    expect(glucoseNote(_glu(50)), contains('166 ή 112'));
    expect(glucoseNote(_glu(70, GlucoseWhen.after)), isNull);
    expect(glucoseNote(_glu(69.5, GlucoseWhen.after)), isNull, reason: 'κρίνεται όπως φαίνεται (70)');
    // K3-review R6: όποιος παίρνει ινσουλίνη ή χάπια που ρίχνουν το σάκχαρο δεν περιμένει συμπτώματα.
    expect(glucoseNote(_glu(62)), contains('ινσουλίνη ή χάπια που ρίχνουν το σάκχαρο: 15 g ζάχαρη τώρα'));
    expect((glucoseLow, glucoseVeryLow), (70, 55));
  });

  test('K3-S-07: «Ασαφές» δεν σημαίνει «εντάξει»· η μαρμαρυγή παίρνει χρόνο', () {
    expect(ecgNote(EcgResult.inconclusive), contains('δεν σημαίνει «εντάξει»'));
    // K3-review R3: χωρίς αριθμούς που αλλάζουν με την έκδοση της εφαρμογής ECG του ρολογιού (100–120 ή 150).
    expect(ecgNote(EcgResult.inconclusive), contains('πολύ αργοί (κάτω από 50) ή πολύ γρήγοροι'));
    expect(ecgNote(EcgResult.inconclusive), isNot(contains('100–120')));
    expect(ecgNote(EcgResult.inconclusive), contains('παλμούς πάνω από 120 σε ηρεμία, μίλα με γιατρό την ίδια μέρα'));
    expect(ecgNote(EcgResult.afib), contains('μέσα σε λίγες μέρες'));
    expect(ecgNote(EcgResult.afib), contains('166 ή 112'));
  });

  // ------------------------------------------------------------------------------------------------------------ οξυγόνο
  group('K3-S-03: οξυγόνο με το ρολόι στον ύπνο λίγες νύχτες (κανόνας 2β)', () {
    final last = DateTime(2026, 11, 24);
    Map<DateTime, double> nights(Map<int, double> byDaysAgo) =>
        {for (final e in byDaysAgo.entries) DateTime(2026, 11, 24 - e.key): e.value};

    test('2 νύχτες την εβδομάδα, όλες 83%: σημείωση από τις 4 νύχτες (πριν: καμία, ποτέ)', () {
      final g = oxygenGuidance(nights({0: 83, 1: 83, 7: 83, 8: 83, 14: 83, 15: 83, 21: 83, 22: 83}), last);
      expect((g.repeated, g.repeatedMonth, g.any), (false, true, true));
      expect(g.messages.single, contains('σε 8 από τις 8 νύχτες με μέτρηση των τελευταίων 30 ημερών'));
      expect(g.short, contains('8 από 8 νύχτες (30 μέρες)'));
      final three = oxygenGuidance(nights({0: 83, 7: 83, 14: 83}), last);
      expect((three.repeatedMonth, three.any), (false, false), reason: 'θέλει τουλάχιστον 4 νύχτες');
    });

    test('οι μισές τουλάχιστον από τις νύχτες με μέτρηση: 4 από 8 ναι, 3 από 8 όχι, 4 από 30 όχι', () {
      final half = oxygenGuidance(nights({0: 83, 1: 92, 7: 83, 8: 92, 14: 83, 15: 92, 21: 83, 22: 92}), last);
      expect(half.repeatedMonth, isTrue);
      final less = oxygenGuidance(nights({0: 92, 1: 92, 7: 83, 8: 92, 14: 83, 15: 92, 21: 83, 22: 92}), last);
      expect((less.repeatedMonth, less.any), (false, false));
      final healthy = oxygenGuidance(nights({for (var i = 0; i < 30; i++) i: (i == 2 || i == 10 || i == 18 || i == 26) ? 84.0 : 92.0}), last);
      expect((healthy.lowNights30, healthy.measuredNights30, healthy.repeatedMonth, healthy.any), (4, 30, false, false));
      // K3-review: 4 από 9 όχι, 4 από 7 ναι· και όταν η «τελευταία νύχτα» δεν έχει μέτρηση (νύχτες −8, −15, −22, −29).
      final of9 = oxygenGuidance(nights({1: 83, 8: 83, 15: 83, 22: 83, 2: 92, 9: 92, 16: 92, 23: 92, 27: 92}), last);
      expect((of9.lowNights30, of9.measuredNights30, of9.repeatedMonth), (4, 9, false));
      final of7 = oxygenGuidance(nights({1: 83, 8: 83, 15: 83, 22: 83, 9: 92, 16: 92, 23: 92}), last);
      expect((of7.lowNights30, of7.measuredNights30, of7.repeatedMonth), (4, 7, true));
      final noLast = oxygenGuidance(nights({8: 83, 15: 83, 22: 83, 29: 83}), last);
      expect((noLast.repeatedMonth, noLast.veryLowLastNight), (true, false));
      expect(oxygenGuidance(nights({8: 84.99, 15: 84.99, 22: 84.99, 29: 85.0}), last).repeatedMonth, isFalse, reason: '85,0 δεν μετρά');
    });

    test('η σειρά των μηνυμάτων: κάτω από 80% σε 2 νύχτες, μετά η εβδομάδα, μετά ο μήνας', () {
      final week = oxygenGuidance(nights({0: 83, 1: 83, 2: 83, 9: 83}), last);
      expect(week.messages.single, contains('της τελευταίας εβδομάδας'));
      final veryLow = oxygenGuidance(nights({0: 78, 7: 79, 14: 83, 21: 83}), last);
      expect(veryLow.messages.single, contains('κάτω από 80%'));
      expect(oxygenMonthRepeatNights, 4);
    });

    test('το ⓘ λέει τον νέο κανόνα, ότι χωρίς το ρολόι στον ύπνο δεν βγαίνει σημείωση, και κάτι για τον μέσο όρο', () {
      final down = metricInfos[K.ringSpo2]!.down!;
      expect(down, contains('στις μισές και πάνω από τις νύχτες του μήνα που φόρεσες το ρολόι, αν είναι τουλάχιστον 4'));
      expect(down, contains('Χωρίς το ρολόι στον ύπνο'));
      expect(down, contains('κάτω από 92%'));
      expect(oxygenAboutText, contains('περίπου 4 ώρες ύπνου'), reason: 'K3-S-12');
    });
  });

  // ------------------------------------------------------------------------------------------------- κείμενα και τάσεις
  test('K3C-07: η τάση HRV γράφει πόσες νύχτες μέτρησαν όταν είναι λιγότερες από 7', () {
    HrvTrend t(int n) => HrvTrend(weekMs: 40, lowMs: 36, highMs: 44, band: HrvBand.within, weekNights: n, baseNights: 40);
    expect(hrvTrendText(t(7)), '7 νύχτες: 40 ms, μέσα στο συνηθισμένο σου εύρος (36–44)');
    expect(hrvTrendText(t(5)), '5 από 7 νύχτες: 40 ms, μέσα στο συνηθισμένο σου εύρος (36–44)');
  });

  test('K3C-08: «Λίγη κάλυψη» με το ποσοστό προς τα κάτω (49,6% δεν γράφεται 50%)', () {
    const NightOxygen low = (avg: 94, min: 88, below90: null, cov: 0.496);
    expect(watchLowText(low), 'Λίγη κάλυψη: το ρολόι μέτρησε το 49% του ύπνου');
    const NightOxygen ok = (avg: 94, min: 88, below90: null, cov: 0.5);
    expect(watchLowText(ok), 'Μέτρησε το 50% του ύπνου');
    // K3-review R12: 0,29 × 100 = 28,999999999999996 → «29%», όχι «28%».
    const NightOxygen c29 = (avg: 94, min: 88, below90: null, cov: 0.29);
    expect(watchLowText(c29), 'Λίγη κάλυψη: το ρολόι μέτρησε το 29% του ύπνου');
  });

  test('K3-S-10: η «Βαθμολογία ύπνου» έχει ουδέτερο χρώμα στις Τάσεις· η διάρκεια μένει «περισσότερο = καλύτερα»', () {
    MetricDef def(String key) => trendMetrics.firstWhere((m) => m.key == key);
    expect(def(K.sleepScore).better, 0);
    expect(def(K.sleepMin).better, 1);
    expect(def(K.energy).better, 0);
  });

  test('K3-S-08 / K3-S-09: τα κείμενα για REM και θερμοκρασία λένε ό,τι λένε οι μελέτες', () {
    final stages = metricInfos[stagesInfoKey]!.accuracy!;
    expect(stages, contains('δεν σημαίνει από μόνος του κακό ύπνο'));
    expect(stages, contains('αν ξυπνάς κουρασμένος, πες το στον γιατρό σου'));
    expect(stages, isNot(contains('δεν σημαίνουν κακό ύπνο')));
    final temp = metricInfos[K.skinTemp]!.accuracy!;
    expect(temp, contains('σε 38 από 50'));
    expect(temp, contains('χωρίς σύγκριση με υγιείς'));
  });
}
