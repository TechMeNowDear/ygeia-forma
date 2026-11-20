// Αποφάσεις 20/11: χαμένη προπόνηση (lib/training/catch_up.dart). Πρόγραμμα όπως του πρώτου μήνα: Παρασκευή–Δευτέρα βάρη
// (πάνω/κάτω), Τρίτη–Πέμπτη περπάτημα. Επινοημένα δεδομένα.
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/training/catch_up.dart';
import 'package:ygeia_forma/training/program.dart';
import 'package:ygeia_forma/training/session.dart';

Program _p() => Program.fromJson({
      'id': 'p1',
      'name': 'Δοκιμή',
      'from': '2026-11-16',
      'days': {'fri': 'P1', 'sat': 'K2', 'sun': 'P2', 'mon': 'K1', 'tue': 'walk', 'wed': 'walk', 'thu': 'walk'},
      'workouts': [
        for (final (id, name) in [('P1', 'Πάνω μέρος 1'), ('K2', 'Κάτω μέρος 2'), ('P2', 'Πάνω μέρος 2'), ('K1', 'Κάτω μέρος 1')])
          {
            'id': id,
            'name': name,
            'items': [
              {'ex': 'goblet_squat', 'sets': 2, 'reps': [8, 12]}
            ],
          },
        {
          'id': 'walk',
          'name': 'Περπάτημα',
          'cardio': {'activity': 'walk', 'minutes': 30},
        },
      ],
    });

Session _done(String w, DateTime day, {bool cardio = false}) => Session(
      id: 's-$w-${day.day}',
      workout: w,
      name: w,
      programId: 'p1',
      start: DateTime(day.year, day.month, day.day, 18),
      end: DateTime(day.year, day.month, day.day, 19),
      cardioMinutes: cardio ? 30 : null,
    );

void main() {
  final p = _p();
  // Δευτέρα 23/11 (Κ1), Τρίτη 24/11 (περπάτημα), Τετάρτη 25/11, Πέμπτη 26/11, Παρασκευή 27/11 (Π1), Σάββατο 28/11 (Κ2).
  final mon = DateTime(2026, 11, 23), tue = DateTime(2026, 11, 24, 10), wed = DateTime(2026, 11, 25, 10);
  final thu = DateTime(2026, 11, 26, 10), sat = DateTime(2026, 11, 28, 10);
  final sun0 = DateTime(2026, 11, 22), fri = DateTime(2026, 11, 27);

  test('Δευτέρα χάθηκε → προτείνεται Τρίτη (περπάτημα σήμερα, χωρίς βάρη χθες και αύριο)', () {
    final m = missedToCatchUp(p, [_done('P2', sun0)], tue);
    expect(m?.workout.id, 'K1');
    expect(m?.missed, DateTime(2026, 11, 23));
  });

  test('και την Τετάρτη (ως 2 μέρες), όχι την Πέμπτη', () {
    expect(missedToCatchUp(p, [_done('P2', sun0)], wed)?.workout.id, 'K1');
    expect(missedToCatchUp(p, [_done('P2', sun0)], thu), isNull);
  });

  test('έγινε τη Δευτέρα ή την Τρίτη: τίποτα', () {
    expect(missedToCatchUp(p, [_done('K1', mon)], tue), isNull);
    expect(missedToCatchUp(p, [_done('K1', tue)], wed), isNull);
  });

  test('ποτέ δύο βαριές μέρες στη σειρά, ποτέ δύο προπονήσεις με βάρη την ίδια μέρα', () {
    // Παρασκευή χάθηκε: το Σάββατο έχει δική του (Κ2) → όχι.
    expect(missedToCatchUp(p, const [], sat), isNull);
    // Βάρη χθες (με το χέρι, Τρίτη): όχι την Τετάρτη.
    expect(missedToCatchUp(p, [_done('P1', DateTime(2026, 11, 24))], wed), isNull);
    // Πέμπτη: αύριο (Παρασκευή) βάρη → όχι.
    expect(missedToCatchUp(p, const [], DateTime(2026, 11, 26, 9)), isNull);
    // Ήδη βάρη σήμερα.
    expect(missedToCatchUp(p, [_done('P1', DateTime(2026, 11, 24))], tue), isNull);
  });

  test('το περπάτημα σήμερα δεν εμποδίζει· το περπάτημα δεν είναι «χαμένη»', () {
    expect(missedToCatchUp(p, [_done('walk', DateTime(2026, 11, 24), cardio: true)], tue)?.workout.id, 'K1');
    // Χάθηκε το περπάτημα της Τρίτης: τίποτα για αναπλήρωση την Τετάρτη (μόνο βάρη).
    expect(missedToCatchUp(p, [_done('K1', mon)], wed), isNull);
  });

  test('πριν από την αρχή του προγράμματος: τίποτα', () {
    final early = Program.fromJson({...p.toJson(), 'from': '2026-11-30'});
    expect(missedToCatchUp(early, const [], tue), isNull);
  });

  test('η Παρασκευή που έγινε δεν αλλάζει τίποτα (σταθερό)', () {
    expect(missedToCatchUp(p, [_done('P1', fri)], sat), isNull);
  });
}
