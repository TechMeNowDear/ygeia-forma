// Βαθύς έλεγχος 20/11/2026, κατηγορία 3 (καρδιά, ύπνος, πίεση, σάκχαρο, οξυγόνο, τάσεις): οι διορθώσεις K3-S-01…13 και
// K3C-01…08. Μόνο επινοημένες τιμές και σταθερές ημερομηνίες. Οι αριθμοί βγήκαν από τις αναφορές k3-science / k3-calc και
// από τη μεταφορά του κανόνα της νύχτας σε Python (audit-141/main-k3/takeover.py).
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

    test('μεσημεριανός ύπνος μετά από κανονική σύντομη νύχτα μένει υπνάκος (θέλει 2 φορές τον ύπνο της νύχτας)', () {
      expect(_grouped([_p(24, 0, 0, 24, 4, 30, 250), _p(24, 11, 30, 24, 16, 30, 280)]), '24: 250 | υπνάκοι 24: 280');
      expect(_grouped([_p(23, 23, 0, 24, 2, 0, 170), _p(24, 10, 30, 24, 14, 0, 200)]), '24: 170 | υπνάκοι 24: 200');
      expect(_grouped([_p(24, 3, 30, 24, 6, 0, 140), _p(24, 9, 0, 24, 12, 30, 200)]), '24: 140 | υπνάκοι 24: 200');
      // Ακριβώς 2 φορές: γίνεται κύρια (το πρώτο κομμάτι απέχει πάνω από 4 ώρες: υπνάκος).
      expect(_grouped([_p(24, 3, 30, 24, 5, 0, 85), _p(24, 10, 0, 24, 13, 0, 170)]), '24: 170 | υπνάκοι 24: 85');
      expect(mainTakeoverRatio, 2.0);
    });

    test('ίδια λεπτά ύπνου: μένει η κύρια του παραθύρου· οι πρωινοί υπνάκοι με βήματα μένουν υπνάκοι', () {
      expect(_grouped([_p(24, 3, 30, 24, 5, 30, 110), _p(24, 7, 10, 24, 9, 30, 110)]), '24: 110 | υπνάκοι 24: 110');
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

    test('οι κανόνες του Oura ξαναδιαβάζονται (έκδοση 2)· οι 9 παλιές περιπτώσεις του merge2_test μένουν ίδιες', () {
      expect(ouraRulesVersion, 2);
      expect(_grouped([_p(2, 23, 43, 3, 2, 40, 152), _p(3, 3, 50, 3, 7, 8, 178)]), '3: 152+178');
      expect(_grouped([_p(2, 20, 30, 2, 21, 30, 60), _p(2, 23, 30, 3, 7, 0, 420)]), '3: 60+420');
      expect(_grouped([_p(2, 19, 30, 2, 20, 30, 60), _p(2, 23, 30, 3, 7, 0, 420)]), '3: 420 | υπνάκοι 3: 60');
      expect(_grouped([_p(2, 23, 30, 3, 7, 0, 420), _p(3, 9, 30, 3, 10, 30, 55)]), '3: 420 | υπνάκοι 3: 55');
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
    });

    test('K3-S-02: σφυγμοί πάνω από 100 ή κάτω από 40 στο πιεσόμετρο παίρνουν σημείωση· 40–100 και χωρίς σφυγμούς όχι', () {
      expect(pulseNote(_bp(126, 84, pulse: 101)), contains('Σφυγμοί πάνω από 100 σε ηρεμία'));
      expect(pulseNote(_bp(126, 84, pulse: 130)), contains('166 ή 112'));
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
    expect((glucoseLow, glucoseVeryLow), (70, 55));
  });

  test('K3-S-07: «Ασαφές» δεν σημαίνει «εντάξει»· η μαρμαρυγή παίρνει χρόνο', () {
    expect(ecgNote(EcgResult.inconclusive), contains('δεν σημαίνει «εντάξει»'));
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
      expect(down, contains('4+ νύχτες του μήνα'));
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
