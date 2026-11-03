// Έλεγχοι για τις διορθώσεις του ελέγχου 4/11 (υπολογισμοί, κλινικά κείμενα, αναφορά γιατρού).
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/oxygen_note.dart';
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

    test('Κάτω από 88% σε 3 από τις 7 τελευταίες νύχτες → «πες το στον γιατρό σου»', () {
      final g = oxygenGuidance({day(0): 90, day(2): 87.6, day(4): 86, day(6): 85, day(7): 70}, today);
      expect(g.lowNights, 3, reason: 'η 8η νύχτα πίσω δεν μετρά· το 87,6 μετρά (πριν από στρογγυλοποίηση)');
      expect(g.repeated, isTrue);
      expect(g.messages.first, contains('σε 3 από τις 7 τελευταίες νύχτες'));
      expect(g.messages.first, contains('γιατρό σου'));
    });

    test('2 νύχτες κάτω από 88% → όχι ακόμα', () {
      expect(oxygenGuidance({day(1): 86, day(2): 85, day(3): 88}, today).repeated, isFalse);
    });

    test('Τα κείμενα δεν λένε ότι το τεστ άπνοιας είναι «το σωστό εργαλείο» (κλινικός έλεγχος C1)', () {
      expect(oxygenAboutText, isNot(contains('σωστό εργαλείο')));
      expect(oxygenAboutText, contains('αρνητικό αποτέλεσμα δεν την αποκλείει'));
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
    expect(usualMean([60, 60, 60, 60, 60, 61, 62]), closeTo(60.43, 0.01));
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
}
