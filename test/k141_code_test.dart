// Βαθύς έλεγχος 20/11/2026, κατηγορία 6 (λάθη κώδικα και αντοχή των δεδομένων): οι διορθώσεις των K6-code και K6-storage
// που δεν έχουν δοκιμή αλλού (η επαναφορά από αντίγραφο και η ανανέωση είναι στο r1_f3_test.dart, το χρονόμετρο
// μαγειρέματος στο recipes_test.dart). Επινοημένα δεδομένα. Κάθε δοκιμή γράφει τι έβγαινε ΠΡΙΝ.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/food/dishes.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/home_widgets/widget_bridge.dart';
import 'package:ygeia_forma/pages/backup_reminder_card.dart';
import 'package:ygeia_forma/pages/week.dart' show weekSlotNotSavedText;
import 'package:ygeia_forma/training/catch_up.dart';
import 'package:ygeia_forma/training/program.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/training_store.dart';

import 'sample_data.dart';
import 'sample_food.dart';

/// Κυριακή βάρη («P2»), όλες οι άλλες μέρες περπάτημα.
Program _sundayOnly() => Program.fromJson({
      'id': 'p1',
      'name': 'Δοκιμή',
      'from': '2027-10-01',
      'days': {'sun': 'P2', 'mon': 'walk', 'tue': 'walk', 'wed': 'walk', 'thu': 'walk', 'fri': 'walk', 'sat': 'walk'},
      'workouts': [
        for (final id in ['P2', 'K2'])
          {
            'id': id,
            'name': id,
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ------------------------------------------------------------------------------------------------------- K6C-05
  test('K6C-05: «χαμένη προπόνηση» τη μέρα που αλλάζει η ώρα: η Κυριακή 31/10/2027 έχει 25 ώρες, όχι 24', () {
    final p = _sundayOnly();
    // Κυριακή 31/10/2027, 23:30: άλλη προπόνηση με βάρη («K2») στη θέση της προγραμματισμένης («P2»).
    final late = Session(
      id: 's1',
      workout: 'K2',
      name: 'K2',
      programId: 'p1',
      start: DateTime(2027, 10, 31, 23, 30),
      end: DateTime(2027, 11, 1, 0, 20),
    );
    final tuesday = DateTime(2027, 11, 2, 10);
    // Πριν: το «τέλος της Κυριακής» έβγαινε 23:00 (μεσάνυχτα + 24 ώρες), η προπόνηση των 23:30 δεν μετρούσε ως Κυριακής,
    // και η κάρτα πρότεινε την Τρίτη «χαμένη προπόνηση» που είχε γίνει.
    expect(missedToCatchUp(p, [late], tuesday), isNull);
    // Χωρίς καμία προπόνηση την Κυριακή: η χαμένη προτείνεται κανονικά.
    final m = missedToCatchUp(p, const [], tuesday);
    expect((m?.workout.id, m?.missed), ('P2', DateTime(2027, 10, 31)));
    // Και μια προπόνηση στις 00:30 της Κυριακής (η μέρα αρχίζει κανονικά στα μεσάνυχτα).
    final early = Session(
      id: 's2',
      workout: 'K2',
      name: 'K2',
      programId: 'p1',
      start: DateTime(2027, 10, 31, 0, 30),
      end: DateTime(2027, 10, 31, 1, 20),
    );
    expect(missedToCatchUp(p, [early], tuesday), isNull);
  });

  // ------------------------------------------------------------------------------------------------------- K6C-06
  test('K6C-06: τα widgets ξαναγράφονται όταν η εγγραφή τους απέτυχε (πριν: έμεναν με τις παλιές τιμές)', () async {
    final calls = <String>[];
    var ok = false;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(widgetChannel, (call) async {
      calls.add(call.method);
      if (call.method == 'count') return 1;
      return call.method == 'update' ? ok : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(widgetChannel, null));
    final read = DateTime(2026, 11, 16, 9);
    final store = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(read));
    final publisher = WidgetPublisher(store, sampleFoodStore(read), clock: () => DateTime(2026, 11, 16, 9, 30));
    int updates() => calls.where((c) => c == 'update').length;

    await publisher.publish();
    expect(updates(), 1);
    // Η Kotlin απάντησε «δεν γράφτηκε» (π.χ. γεμάτος χώρος): τα ίδια δεδομένα ξαναστέλνονται.
    await publisher.publish();
    expect(updates(), 2, reason: 'πριν: 1 («ίδιο με το τελευταίο», ενώ το τελευταίο δεν είχε γραφτεί)');
    ok = true;
    await publisher.publish();
    expect(updates(), 3);
    // Γράφτηκε: τα ίδια δεδομένα δεν ξαναστέλνονται.
    await publisher.publish();
    expect(updates(), 3);
  });

  // ------------------------------------------------------------------------------------------------------- K6S-12
  test('K6S-12: το «Ζύγισα ένα» ακολουθεί τρόφιμο που άλλαξε id στη βάση (πριν: χανόταν σιωπηλά)', () async {
    final now = DateTime(2026, 11, 18, 14);
    final io = MemoryDishIO();
    final s = FoodStore.preloaded(foods: basicFoods(), dishIO: io, now: now);
    await s.loadDishes();
    expect(await s.setMyUnit('C13005', 125), isTrue);
    // Το αρχείο όπως θα το είχε γράψει παλιότερη έκδοση: με το παλιό id του πεπονιού (C13026 → U169092).
    final j = jsonDecode(io.json!) as Map<String, dynamic>;
    j['units'] = {'C13026': 900.0, 'C13005': 125.0};
    final s2 = FoodStore.preloaded(foods: basicFoods(), dishIO: MemoryDishIO(jsonEncode(j)), now: now);
    await s2.loadDishes();
    expect(s2.myUnit('U169092'), 900);
    expect(s2.myUnit('C13005'), 125);
    // Και στην επαναφορά από αντίγραφο.
    expect(await s2.importUnits({'C13742': 1200.0, 'C13026': 950.0}), 1, reason: 'το πεπόνι κανταλούπ έχει ήδη δικό σου βάρος');
    expect(s2.myUnit('U169911'), 1200);
    expect(s2.myUnit('U169092'), 900);
  });

  // ------------------------------------------------------------------------------------------------------- K6S-11
  test('K6S-11: η κάρτα αντιγράφου μετρά και «Τα φαγητά μου» (πριν: μόνο φαγητό, προϊόντα, προπονήσεις, μέση)', () async {
    final now = DateTime(2026, 11, 18, 14);
    final training = TrainingStore(io: MemoryTrainingIO(), clock: () => now)..ready = true;
    final empty = FoodStore.preloaded(foods: basicFoods(), dishIO: MemoryDishIO(), now: now);
    await empty.loadDishes();
    expect(BackupReminderSlot.hasOwnData(HealthStore(), empty, training), isFalse);
    final withDish = FoodStore.preloaded(foods: basicFoods(), dishIO: MemoryDishIO(), now: now);
    await withDish.loadDishes();
    expect(
        await withDish.saveDish(Dish(
            id: 'D1', name: 'Φακές', kind: DishKind.plate, items: const [DishItem('C20359', 'Φακές', 80)], created: 1)),
        isTrue);
    expect(BackupReminderSlot.hasOwnData(HealthStore(), withDish, training), isTrue);
  });

  // ------------------------------------------------------------------------------------------------------- K6S-07
  test('K6S-07: «Το έφαγα» που έγραψε το φαγητό αλλά όχι το πρόγραμμα το λέει (πριν: «Γράφτηκε»)', () {
    final t = weekSlotNotSavedText('Φακές');
    expect(t, contains('«Φακές» γράφτηκε στο ημερολόγιο'));
    expect(t, contains('το πρόγραμμα δεν ενημερώθηκε'));
    expect(t, contains('δύο φορές'));
  });
}
