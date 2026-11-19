// Αποφάσεις χρήστη 17/11, βήμα 1: μέση/ύψος, μέσος όρος 7 ημερών στο βάρος, πρωτεΐνη 1,8 g/kg στην απώλεια.
// Φανταστικό προφίλ (180 cm, 90 kg).
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/body_trend.dart';
import 'package:ygeia_forma/goals.dart';
import 'package:ygeia_forma/waist.dart';

DateTime _d(int n) => DateTime(2026, 11, 1 + n, 7, 30);

void main() {
  group('Μέση/ύψος (NICE)', () {
    test('όρια στα δύο δεκαδικά', () {
      expect(waistHeightText(88, 180), 'Μέση/ύψος: 0,48 · υγιές (0,40–0,49) (NICE 2025)');
      // Έλεγχος 19/11 (L-12): 0,497 δεν είναι «0,50 · αυξημένος».
      expect(waistHeightText(88, 177), contains('0,49 · υγιές'));
      expect(waistHeightText(88.5, 177), contains('0,50 · αυξημένος'));
      expect(waistHeightText(90, 180), 'Μέση/ύψος: 0,50 · αυξημένος κίνδυνος (0,50–0,59) (NICE 2025)');
      expect(waistHeightText(107.9, 180), contains('0,59 · αυξημένος'));
      expect(waistHeightText(108, 180), contains('0,60 · ακόμα πιο αυξημένος'));
      expect(waistHeightText(70, 180), contains('κάτω από το 0,40'));
      expect(waistHeightText(72, 180), contains('0,40 · υγιές'));
    });
    test('χωρίς ύψος ή με αδύνατο ύψος: τίποτα', () {
      expect(waistHeightText(90, null), isNull);
      expect(waistHeightText(90, 50), isNull);
    });
  });

  group('Μέσος όρος 7 ημερών', () {
    test('από την τρίτη τιμή, με παράθυρο 7 ημερολογιακών ημερών', () {
      final pts = [for (var n = 0; n < 10; n++) (_d(n), 90.0 + n)];
      final a = average7Days(pts);
      expect(a.length, 8);
      expect(a.first.$1, _d(2));
      expect(a.first.$2, closeTo(91, 1e-9)); // (90+91+92)/3
      expect(a.last.$2, closeTo(96, 1e-9)); // 93..99
    });
    test('κενό: οι παλιές τιμές βγαίνουν από το παράθυρο', () {
      final pts = [(_d(0), 90.0), (_d(1), 90.0), (_d(2), 90.0), (_d(10), 80.0), (_d(11), 80.0)];
      final a = average7Days(pts);
      expect(a.map((p) => p.$1), [_d(2)]); // στις 10 και 11 μόνο 1–2 τιμές
    });
    test('Έλεγχος 19/11 (L-4): Δε/Τε/Πα με μία Τετάρτη που λείπει → η γραμμή δεν κόβεται', () {
      // Δε 30/11 = _d(0)· λείπει η Τε 9/12 (_d(9)).
      final days = [0, 2, 4, 7, 11, 14, 16, 18];
      final a = average7Days([for (final n in days) (_d(n), 82.0 - n / 10)]);
      expect(a.map((p) => p.$1), [for (final n in [4, 7, 11, 14, 16, 18]) _d(n)]);
    });
    test('λίγες τιμές: κενή λίστα', () {
      expect(average7Days([(_d(0), 90.0), (_d(1), 89.0)]), isEmpty);
    });
  });

  group('Πρωτεΐνη', () {
    GoalCalc c(double kg, GoalAim aim) =>
        computeGoals(male: true, age: 40, heightCm: 180, kg: kg, aim: aim, rate: aim == GoalAim.keep ? 0 : 0.005, activity: 1.5, doctor: false);
    test('απώλεια 1,8 g/kg· ίδιο βάρος και αύξηση 1,6', () {
      expect(c(90, GoalAim.lose).protein, 160); // 162
      expect(c(90, GoalAim.keep).protein, 145); // 144
      expect(c(90, GoalAim.gain).protein, 145);
    });
    test('ΔΜΣ πάνω από 30 στην απώλεια: με το βάρος στο ΔΜΣ 30, χωρίς σκαλοπάτι', () {
      // ΔΜΣ 30 στα 180 cm = 97,2 kg × 1,8 = 174,96 → 175
      expect(c(110, GoalAim.lose).protein, 175);
      expect(c(97, GoalAim.lose).protein, 175); // 174,6
      expect(c(98, GoalAim.lose).protein, 175); // όχι πτώση στο όριο
      // στο ίδιο βάρος μένει 1,6 × πραγματικό
      expect(c(110, GoalAim.keep).protein, 175); // 176
    });
  });
}
