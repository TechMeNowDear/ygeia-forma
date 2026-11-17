// Έλεγχος 17/11, κατηγορία 5 (προπόνηση). Φανταστικά βάρη.
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/training/equipment.dart';
import 'package:ygeia_forma/training/program.dart';
import 'package:ygeia_forma/training/progression.dart';
import 'package:ygeia_forma/training/session.dart';

void main() {
  group('Κ5-H1: «πόσες περίπου;» μετά το «4+» στο 1ο σετ', () {
    test('αλτήρες 4,3 kg × 8 με «13+»: πιο βαρύ, το πολύ +25%', () {
      final it = PlanItem(ex: 'db_press', lo: 8, hi: 12, rir: 2);
      final v = calibrate(it, 4.3, 8, 15);
      expect(v, isNotNull);
      expect(v!, greaterThan(4.3));
      expect(v, lessThanOrEqualTo(4.3 * 1.25 + 1e-9));
    });

    test('μπάρα 10 kg × 10 με «13+»: ως +5 kg', () {
      final it = PlanItem(ex: 'rdl', lo: 8, hi: 12, rir: 2);
      final v = calibrate(it, 10, 10, 15)!;
      expect(v, greaterThan(12.5));
      expect(v, lessThanOrEqualTo(15 + 1e-9));
    });

    test('«4» μένει όπως πριν (ένα σκαλί ή τίποτα)', () {
      final it = PlanItem(ex: 'db_press', lo: 8, hi: 12, rir: 3);
      expect(calibrate(it, 4.3, 8, 4), isNull);
    });

    test('κάτω από το κάτω όριο: καμία αύξηση και με «13+»', () {
      final it = PlanItem(ex: 'rdl', lo: 8, hi: 12, rir: 2);
      expect(calibrate(it, 10, 6, 15), isNull);
    });
  });

  test('Κ5-M4: ✓ με 0 επαναλήψεις δεν κρίνεται ως σετ', () {
    final e = ExLog(ex: 'db_press', sets: 3, lo: 8, hi: 12, rir: 2, rest: 90, log: [
      SetLog(load: 9.3, reps: 11, done: true),
      SetLog(load: 9.3, reps: 11, done: true),
      SetLog(load: 9.3, reps: 0, done: true),
    ]);
    expect(e.judged.length, 2);
    expect(hasLoad(LoadKind.dbPair), isTrue);
  });
}
