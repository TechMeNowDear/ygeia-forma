// Α13 (απόφαση χρήστη 21/11): η μέρα της προπόνησης αλλάζει στις 04:00, όπως του φαγητού. Επινοημένα δεδομένα.
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/exercise/ex_data.dart';
import 'package:ygeia_forma/home_widgets/widget_snapshot.dart';
import 'package:ygeia_forma/pages/training/today_training_card.dart';
import 'package:ygeia_forma/training/catch_up.dart';
import 'package:ygeia_forma/training/program.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/training_day.dart';
import 'package:ygeia_forma/training/training_store.dart';
import 'package:ygeia_forma/training/wear_link.dart';
import 'package:ygeia_forma/training/zone.dart';

// Πρόγραμμα: Παρασκευή Π1, Σάββατο Κ2, Κυριακή Π2, Δευτέρα Κ1, Τρίτη–Πέμπτη περπάτημα (όπως του πρώτου μήνα).
Program _p() => Program.fromJson({
      'id': 'p1',
      'name': 'Δοκιμή',
      'from': '2026-11-16',
      'days': {'fri': 'P1', 'sat': 'K2', 'sun': 'P2', 'mon': 'K1', 'tue': 'walk', 'wed': 'walk', 'thu': 'walk'},
      'workouts': [
        for (final id in ['P1', 'K2', 'P2', 'K1'])
          {
            'id': id,
            'name': 'Προπόνηση $id',
            'items': [
              {'ex': 'db_press', 'sets': 2, 'reps': [8, 12]}
            ],
          },
        {
          'id': 'walk',
          'name': 'Περπάτημα',
          'cardio': {'activity': 'walk', 'minutes': 30},
        },
      ],
    });

Session _lift(String id, String workout, DateTime start) => Session(
      id: id,
      workout: workout,
      name: 'Προπόνηση $workout',
      programId: 'p1',
      start: start,
      end: start.add(const Duration(minutes: 50)),
      items: [
        ExLog(ex: 'db_press', sets: 2, lo: 8, hi: 12, rir: 2, rest: 90, rirAnswer: 2, log: [
          for (final r in [10, 10]) SetLog(load: 9.3, reps: r, done: true),
        ]),
      ],
    );

Session _walk(String id, DateTime start, {List<int> zone = const [0, 1200, 0]}) => Session(
      id: id,
      workout: 'walk',
      name: 'Περπάτημα',
      programId: 'p1',
      start: start,
      end: start.add(const Duration(minutes: 21)),
      cardioMinutes: 20,
      cardioSec: 1200,
      activity: 'walk',
    )..zoneTimes = zone;

TrainingStore _store(DateTime Function() clock, List<Session> sessions) {
  final t = TrainingStore(io: MemoryTrainingIO(), clock: clock)..ready = true;
  t.saveProgram(_p());
  t.sessions.addAll(sessions);
  return t;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('trainingDay: 00:00–03:59 ανήκει στην προηγούμενη μέρα· τα μεσάνυχτα ακριβώς είναι ημερομηνία', () {
    expect(trainingDayStartHour, 4);
    expect(trainingDay(DateTime(2026, 11, 21, 0, 30)), DateTime(2026, 11, 20));
    expect(trainingDay(DateTime(2026, 11, 21, 3, 59, 59, 999)), DateTime(2026, 11, 20));
    expect(trainingDay(DateTime(2026, 11, 21, 4)), DateTime(2026, 11, 21));
    expect(trainingDay(DateTime(2026, 11, 21, 23, 59)), DateTime(2026, 11, 21));
    expect(trainingDay(DateTime(2026, 11, 21)), DateTime(2026, 11, 21), reason: 'ημερομηνία: μένει ίδια');
    expect(trainingDay(DateTime(2026, 11, 21, 0, 0, 0, 1)), DateTime(2026, 11, 20), reason: 'στιγμή ένα χιλιοστό μετά');
    // Ξανά πάνω στο αποτέλεσμα: ίδιο.
    for (final t in [DateTime(2026, 11, 21, 0, 30), DateTime(2026, 11, 21, 12), DateTime(2026, 11, 1, 2)]) {
      expect(trainingDay(trainingDay(t)), trainingDay(t));
    }
    // Αρχή μήνα και χρονιάς.
    expect(trainingDay(DateTime(2026, 12, 1, 1)), DateTime(2026, 11, 30));
    expect(trainingDay(DateTime(2027, 1, 1, 2)), DateTime(2026, 12, 31));
    // Η μέρα που αλλάζει η ώρα (Κυριακή 25/10/2026): μισή ώρα πριν από το όριο είναι ακόμα του Σαββάτου.
    expect(trainingDay(DateTime(2026, 10, 25, 3, 30)), DateTime(2026, 10, 24));
    expect(sameTrainingDay(DateTime(2026, 11, 20, 23, 30), DateTime(2026, 11, 21, 1)), isTrue);
    expect(sameTrainingDay(DateTime(2026, 11, 21, 3, 59), DateTime(2026, 11, 21, 4)), isFalse);
  });

  test('η «σημερινή» προπόνηση στις 00:30 του Σαββάτου είναι της Παρασκευής· στις 04:00 του Σαββάτου', () {
    var at = DateTime(2026, 11, 21, 0, 30);
    final t = _store(() => at, const []);
    expect(TodayTrainingCard.shows(t, at), isTrue);
    expect(t.program!.forDay(trainingDay(at))!.id, 'P1');
    expect(watchPlan(t, at, (id) => id)['today'], 'P1', reason: 'και το ρολόι παίρνει την ίδια');
    at = DateTime(2026, 11, 21, 4);
    expect(watchPlan(t, at, (id) => id)['today'], 'K2');
  });

  test('προπόνηση που τελείωσε στις 00:30 μετρά «έγινε» για την Παρασκευή, όχι για το Σάββατο', () {
    var at = DateTime(2026, 11, 21, 1, 30);
    final late = _lift('s1', 'P1', DateTime(2026, 11, 21, 0, 30));
    final t = _store(() => at, [late]);
    expect(TodayTrainingCard.doneToday(t, at)?.id, 's1');
    // Το Σάββατο το πρωί: η Παρασκευή πέρασε, η προπόνηση του Σαββάτου δεν έγινε ακόμα.
    at = DateTime(2026, 11, 21, 10);
    expect(TodayTrainingCard.doneToday(t, at), isNull);
    // Το widget της αρχικής οθόνης: το «έγινε» της Παρασκευής.
    expect(workoutSnapshot(t, DateTime(2026, 11, 20))['done'], '2026-11-20');
    expect(workoutSnapshot(t, DateTime(2026, 11, 21)).containsKey('done'), isFalse);
  });

  test('η επιλογή «για σήμερα» στις 23:00 ισχύει ακόμα στις 00:30, όχι στις 04:00', () {
    final t = _store(() => DateTime(2026, 11, 20, 23), const []);
    t.choose('K1', DateTime(2026, 11, 20, 23));
    expect(t.chosenOn(DateTime(2026, 11, 21, 0, 30)), 'K1');
    expect(t.chosenOn(DateTime(2026, 11, 21, 4)), isNull);
  });

  test('χαμένη προπόνηση: η προπόνηση της Κυριακής που έγινε στις 00:30 της Δευτέρας δεν είναι χαμένη', () {
    final p = _p();
    // Τρίτη 24/11 στις 10:00: η Δευτέρα (Κ1) χάθηκε· η Κυριακή (Π2) έγινε στις 00:30 της Δευτέρας.
    final tue = DateTime(2026, 11, 24, 10);
    final p2Late = _lift('s1', 'P2', DateTime(2026, 11, 23, 0, 30));
    // Πριν: η Π2 μετρούσε στη Δευτέρα, «προπόνηση με βάρη χθες» → καμία πρόταση για την Κ1.
    expect(missedToCatchUp(p, [p2Late], tue)?.workout.id, 'K1');
    // Η Κ1 της Δευτέρας στις 01:00 της Τρίτης: έγινε (της Δευτέρας).
    final k1Late = _lift('s2', 'K1', DateTime(2026, 11, 24, 1));
    expect(missedToCatchUp(p, [p2Late, k1Late], tue), isNull);
  });

  test('η εβδομάδα: περπάτημα και βάρη στις 00:30 της Δευτέρας μετρούν στην εβδομάδα που τελειώνει', () {
    final sessions = [
      _walk('w1', DateTime(2026, 11, 30, 0, 30), zone: const [0, 900, 0]),
      _walk('w2', DateTime(2026, 11, 30, 4), zone: const [0, 600, 0]),
      _lift('s1', 'P2', DateTime(2026, 11, 30, 1)),
    ];
    final sun = weekMovement(sessions, DateTime(2026, 11, 29, 20));
    expect((sun.moderateMin, sun.strengthDays), (15, 1));
    final mon = weekMovement(sessions, DateTime(2026, 11, 30, 10));
    expect((mon.moderateMin, mon.strengthDays), (10, 0));
    // Στις 02:00 της Δευτέρας είναι ακόμα Κυριακή.
    expect(weekMovement(sessions, DateTime(2026, 11, 30, 2)).moderateMin, 15);
    // Η «Άσκηση» (εβδομάδα Δευτέρα–Κυριακή): ίδιο.
    final t = _store(() => DateTime(2026, 11, 29, 20), sessions);
    expect([for (final s in t.weekOf(DateTime(2026, 11, 29))) s.id], containsAll(['w1', 's1']));
    expect([for (final s in t.weekOf(DateTime(2026, 11, 30))) s.id], ['w2']);
  });

  // Α14 (απόφαση χρήστη 21/11): χαμένη προπόνηση, 48 ώρες στους ΙΔΙΟΥΣ μύες.
  group('Α14: πρόταση μέρας για χαμένη προπόνηση', () {
    // Π1, Π2 = πάνω (πιεστικό: στήθος), Κ1, Κ2 = κάτω (κάθισμα: πόδια).
    Program split() => Program.fromJson({
          'id': 'p1',
          'name': 'Δοκιμή',
          'from': '2026-11-16',
          'days': {'fri': 'P1', 'sat': 'K2', 'sun': 'P2', 'mon': 'K1', 'tue': 'walk', 'wed': 'walk', 'thu': 'walk'},
          'workouts': [
            for (final (id, ex) in [('P1', 'db_press'), ('K2', 'goblet'), ('P2', 'db_press'), ('K1', 'goblet')])
              {
                'id': id,
                'name': 'Προπόνηση $id',
                'items': [
                  {'ex': ex, 'sets': 2, 'reps': [8, 12]}
                ],
              },
            {'id': 'walk', 'name': 'Περπάτημα', 'cardio': {'activity': 'walk', 'minutes': 30}},
          ],
        });

    test('η «Πάνω» της Κυριακής χωρά την Τρίτη, μετά από «Κάτω» τη Δευτέρα', () async {
      await ExLibrary.load(inline: true);
      final p = split();
      final tue = DateTime(2026, 11, 24, 18);
      final mon = _lift('m', 'K1', DateTime(2026, 11, 23, 19));
      final m = missedToCatchUp(p, [mon], tue);
      expect((m?.workout.id, m?.missed), ('P2', DateTime(2026, 11, 22)));
      // Αν χθες έγινε «Πάνω» (ίδιοι μύες): όχι.
      final monUpper = _lift('m', 'P1', DateTime(2026, 11, 23, 19));
      expect(missedToCatchUp(p, [monUpper], tue), isNull);
      // Ελεύθερη προπόνηση χθες (άγνωστοι μύες): όχι, όπως πριν.
      final free = _lift('f', 'free', DateTime(2026, 11, 23, 19));
      expect(missedToCatchUp(p, [free], tue), isNull);
      // Πέμπτη: οι δύο προηγούμενες μέρες είναι περπάτημα (η Κυριακή απέχει πάνω από [catchUpDays]): τίποτα.
      expect(missedToCatchUp(p, [mon], DateTime(2026, 11, 26, 18)), isNull);
      expect(catchUpDays, 2);
    });
  });
}
