// Έλεγχοι για τις διορθώσεις του ελέγχου 4/11 (υπολογισμοί, κλινικά κείμενα, αναφορά γιατρού).
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/oxygen_note.dart';
import 'package:ygeia_forma/pages/compare_page.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/report.dart';
import 'package:ygeia_forma/trends.dart';

void main() {
  final today = DateTime(2026, 11, 4);
  DateTime day(int ago) => DateTime(today.year, today.month, today.day - ago);

  group('Οξυγόνο: κλιμακωτή σημείωση (κλινικός έλεγχος C2)', () {
    test('Κανονικές νύχτες → τίποτα πέρα από τα σημάδια κινδύνου', () {
      final g = oxygenGuidance({for (var i = 0; i < 7; i++) day(i): 89.0}, today);
      expect(g.any, isFalse);
      expect(g.messages, isEmpty);
      expect(g.short, isNull);
    });

    test('Κάτω από 80% την τελευταία νύχτα → «Πολύ χαμηλή μεμονωμένη τιμή»', () {
      final g = oxygenGuidance({day(0): 77, day(1): 91, day(2): 92}, today);
      expect(g.veryLowLastNight, isTrue);
      expect(g.repeated, isFalse);
      expect(g.messages, [oxygenVeryLowText]);
    });

    test('Κάτω από 80% παλιότερα (όχι την τελευταία νύχτα) → όχι το μήνυμα της μίας νύχτας', () {
      expect(oxygenGuidance({day(3): 75, day(0): 91}, today).veryLowLastNight, isFalse);
    });

    // Δεύτερος κλινικός έλεγχος (M1, M2): όριο 85% (όχι 88%), μόνο νύχτες με μέτρηση στον παρονομαστή.
    test('Κάτω από 85% σε 3 από τις νύχτες με μέτρηση της εβδομάδας → «πες το στον γιατρό σου»', () {
      final g = oxygenGuidance({day(0): 90, day(2): 84.6, day(4): 83, day(6): 80, day(7): 70}, today);
      expect(g.lowNights, 3, reason: 'η 8η νύχτα πίσω δεν μετρά· το 84,6 μετρά (πριν από στρογγυλοποίηση)');
      expect(g.measuredNights, 4);
      expect(g.repeated, isTrue);
      expect(g.messages.single, contains('σε 3 από τις 4 νύχτες με μέτρηση της τελευταίας εβδομάδας'));
      expect(g.messages.single, contains('γιατρό σου'));
    });

    test('2 νύχτες κάτω από 85% → όχι ακόμα', () {
      expect(oxygenGuidance({day(1): 84, day(2): 83, day(3): 85}, today).repeated, isFalse);
    });

    test('Τα κείμενα δεν λένε ότι το τεστ άπνοιας είναι «το σωστό εργαλείο» (κλινικός έλεγχος C1)', () {
      expect(oxygenAboutText, isNot(contains('σωστό εργαλείο')));
      expect(oxygenAboutText, contains('αρνητικό αποτέλεσμα δεν αποκλείει άπνοια'));
      expect(oxygenAboutText, contains('μελέτη ύπνου'));
      expect(oxygenRedFlagText, contains('166 ή 112'));
      expect(heartRhythmNote, contains('δεν αποκλείεται κολπική μαρμαρυγή'));
    });
  });

  test('Χαμηλότερη μέτρηση: ποτέ στρογγυλεμένη προς τα πάνω (έλεγχος υπολογισμών F16)', () {
    expect(lowestText(89.6), '89,6');
    expect(lowestText(89.96), '89,9');
    expect(lowestText(88), '88');
    expect(lowestText(77), '77');
  });

  test('«Συνηθισμένο»: χρειάζεται τουλάχιστον 7 προηγούμενες τιμές (έλεγχος υπολογισμών F8)', () {
    expect(usualMean([52.0]), isNull, reason: 'πριν: μία νύχτα έφτανε για κόκκινο «+4 από τον μ.ό.»');
    expect(usualMean([60, 60, 60, null, 60, 60, 60]), isNull);
    // Από τον δεύτερο έλεγχο (C7): μεσαία τιμή, ΕΝΑ «συνήθως» σε όλη την εφαρμογή (πριν: μέσος όρος 60,43).
    expect(usualMean([60, 60, 60, 60, 60, 61, 62]), 60);
    // Το πολύ οι 14 πιο πρόσφατες.
    expect(usualMean([for (var i = 0; i < 20; i++) i < 6 ? 100.0 : 50.0]), 50);
  });

  test('Αναφορά: τα βήματα έχουν 90 μέρες, όσες και η «Διαφορά» τους (έλεγχος υπολογισμών F11)', () {
    final h = <String, Map<String, double>>{
      for (var ago = 0; ago < 200; ago++) dateKey(day(ago)): {K.steps: 5000.0 + ago},
    };
    final r = buildReport(h, DateTime(2026, 11, 4, 12));
    final steps = r.stat(K.steps);
    expect(steps.n, 90);
    expect(steps.values.first.$1, day(90));
    expect(steps.values.last.$1, day(1));
    expect(steps.trend!.currentFrom, day(90));
  });

  test('Στάδια ρολογιού: ποσοστά επί του πραγματικού ύπνου, όχι μαζί με τα ξυπνήματα (Τρ 3/11, B4)', () {
    // Πραγματική νύχτα: βαθύς 8, ελαφρύς 271, REM 51, ξύπνιος 47 λεπτά. Πριν: % επί 6:17 (2%, 72%, 14%, 12%).
    final n = Night(DateTime(2026, 11, 3))
      ..stageMinutes.addAll({'DEEP': 8, 'LIGHT': 271, 'REM': 51, 'AWAKE': 47});
    expect(n.asleepStageMinutes, 330);
    expect(n.stagePct('DEEP')!, closeTo(2.4, 0.05));
    expect(n.stagePct('LIGHT')!, closeTo(82.1, 0.05));
    expect(n.stagePct('REM')!, closeTo(15.5, 0.05));
    expect(n.stagePct('AWAKE'), isNull, reason: 'ο χρόνος ξύπνιος φαίνεται σε λεπτά, όχι ως μέρος του ύπνου');
    expect(n.awakeMinutes, 47);
  });

  test('Σύγκριση πηγών: και το ρολόι ως πραγματικός ύπνος, χωρίς τα ξυπνήματα (έλεγχος F7)', () {
    // Μετά τη συγχώνευση με το Track A: Night.minutes ΕΙΝΑΙ ο πραγματικός ύπνος (από τις φάσεις, staged), και η
    // διάρκεια της Samsung με τα ξυπνήματα είναι το spanMinutes. Η σύγκριση δείχνει 330, ποτέ 377.
    final n = Night(DateTime(2026, 11, 3))
      ..minutes = 330
      ..staged = true
      ..spanMinutes = 377 // από τον ύπνο ως το ξύπνημα, μαζί με τα ξυπνήματα
      ..start = DateTime(2026, 11, 3, 1, 20)
      ..end = DateTime(2026, 11, 3, 7, 37)
      ..stageMinutes.addAll({'DEEP': 8, 'LIGHT': 271, 'REM': 51, 'AWAKE': 47});
    final rows = buildCompareRows(
      plan: SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 1)),
      oura: const [],
      watch: [n],
      today: DateTime(2026, 11, 4),
    );
    expect(rows.single.watchMinutes, 330);
    expect(rows.single.watchMinutes, n.asleepStageMinutes, reason: 'ένας ορισμός: ίδιος με το άθροισμα των σταδίων');
    expect(rows.single.watchSpan, 377);
    expect(rows.single.watchAwake, 47);
  });
}
