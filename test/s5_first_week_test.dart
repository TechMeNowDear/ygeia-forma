// Έλεγχος 19/11 (#139): «η πρώτη εβδομάδα» — βαθμονόμηση 1ου σετ (W-2, W-3, W-5 του week-train). Επινοημένα δεδομένα.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/adaptive_check.dart' show firstCheckDay;
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/goals.dart';
import 'package:ygeia_forma/pages/goals_page.dart';
import 'package:ygeia_forma/profile.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/training_store.dart';

const _me = Profile(birthYear: 1985, birthMonth: 12, sex: 'm', heightCm: 180);

/// Στόχοι «λιγότερο λίπος» που μπήκαν στις 11/11, με δικό σου αριθμό 2.090.
Goals _old({int? kcalSet = 2090, String since = '2026-11-11'}) => Goals(
      aim: GoalAim.lose,
      rate: 0.005,
      activity: 1.65,
      doctor: false,
      since: since,
      kg: 90,
      age: 40,
      heightCm: 180,
      male: true,
      nutsG: 30,
      branG: 40,
      legumesWeek: 4,
      fishWeek: 6,
      kcalSet: kcalSet,
    );

Future<void> _wizard(WidgetTester t, HealthStore store, DateTime now) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = const Size(400, 3000);
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: GoalsWizard(store: store, now: now, fromPage: true)));
  await t.pumpAndSettle();
  await t.enterText(find.byKey(const ValueKey('wizard-kg')), '90');
  await t.pumpAndSettle();
  for (var k = 0; k < 4; k++) {
    await t.tap(find.byKey(const ValueKey('wizard-next')));
    await t.pumpAndSettle();
  }
}

/// Από την ερώτηση του γιατρού στη σύνοψη (ή, στη σύνοψη, αποθήκευση).
Future<void> _save(WidgetTester t) async {
  await t.ensureVisible(find.byKey(const ValueKey('wizard-next')));
  await t.tap(find.byKey(const ValueKey('wizard-next')));
  await t.pumpAndSettle();
}

final _now = DateTime(2026, 11, 30, 18);

/// Μία προηγούμενη προπόνηση με πλάγιες (3×12–15, φορτίο [load]) πριν από [daysAgo] μέρες.
Session _lat(int daysAgo, List<int> reps, {double load = 5.3, double? later, int? first, int? last, String? source}) => Session(
      id: 's$daysAgo',
      workout: 'A',
      name: 'Α',
      programId: 'p1',
      start: _now.subtract(Duration(days: daysAgo, hours: 1)),
      end: _now.subtract(Duration(days: daysAgo)),
      source: source,
      items: [
        ExLog(
          ex: 'lateral_raise',
          sets: 3,
          lo: 12,
          hi: 15,
          rir: 2,
          rest: 60,
          firstAnswer: first,
          rirAnswer: last,
          log: [
            for (var k = 0; k < reps.length; k++) SetLog(load: k == 0 ? load : (later ?? load), reps: reps[k], done: true),
          ],
        ),
      ],
    );

TrainingStore _store(List<Session> s) {
  final t = TrainingStore(io: MemoryTrainingIO(), clock: () => _now);
  t.replaceAll({'v': 1, 'sessions': [for (final x in s) x.toJson()]});
  t.ready = true;
  return t;
}

void main() {
  group('W-2: η ερώτηση του 1ου σετ ξαναγίνεται μόνο όταν όλη η άσκηση ήταν ελαφριά', () {
    test('1ο σετ «8–12», ανέβηκε, τα επόμενα σετ κάτω από το κάτω όριο και «Τελευταίο σετ: 1» → δεν ξαναρωτά', () {
      final t = _store([_lat(2, [13, 10, 9], later: 6.3, first: 10, last: 1)]);
      expect(t.stillCalibrating('lateral_raise'), isFalse);
    });

    test('όλα ελαφριά (1ο «13+», τελευταίο «4+», όλα στο εύρος) → ξαναρωτά', () {
      final t = _store([_lat(2, [15, 15, 15], first: 15, last: 4)]);
      expect(t.stillCalibrating('lateral_raise'), isTrue);
    });

    test('τελευταίο σετ χωρίς απάντηση → δεν ξαναρωτά (δεν ξέρουμε αν ήταν βαρύ)', () {
      final t = _store([_lat(2, [15, 15, 15], first: 15)]);
      expect(t.stillCalibrating('lateral_raise'), isFalse);
    });

    test('διακοπή πάνω από 90 μέρες → ξαναρωτά, σαν πρώτη φορά', () {
      final t = _store([_lat(95, [13, 12, 12], first: 2, last: 2)]);
      expect(t.stillCalibrating('lateral_raise'), isTrue);
    });
  });

  group('W-5: άσκηση που έγινε μόνο από το ρολόι, χωρίς ερώτηση 1ου σετ', () {
    test('μόνο ρολόι, ποτέ απάντηση → ρωτά στο κινητό την επόμενη φορά', () {
      final t = _store([_lat(2, [12, 12, 12], source: 'watch')]);
      expect(t.stillCalibrating('lateral_raise'), isTrue);
    });

    test('ρολόι με απάντηση 1ου σετ («fr») → κανονικός κανόνας', () {
      final t = _store([_lat(2, [12, 12, 12], source: 'watch', first: 2, last: 2)]);
      expect(t.stillCalibrating('lateral_raise'), isFalse);
    });

    test('μία φορά στο κινητό → όχι', () {
      final t = _store([_lat(5, [12, 12, 12], source: 'watch'), _lat(2, [12, 12, 12])]);
      expect(t.stillCalibrating('lateral_raise'), isFalse);
    });
  });

  group('Οδηγός στόχων: αρχή και δικός σου αριθμός (W-1, W-2 του week-food)', () {
    testWidgets('Δευτέρα 23/11 με στόχους της 11/11 χωρίς δεδομένα: προεπιλογή «Σήμερα» (V-1), αρχή 23/11· ο 2.090 μένει', (t) async {
      final store = HealthStore()..setProfile(_me)..setGoals(_old());
      await _wizard(t, store, DateTime(2026, 11, 23, 9));
      await _save(t);
      expect(find.byKey(const ValueKey('wizard-start-keep')), findsOneWidget);
      expect(t.widget<ChoiceChip>(find.byKey(const ValueKey('wizard-start-today'))).selected, isTrue);
      expect(find.byKey(const ValueKey('wizard-start-monday')), findsNothing, reason: 'σήμερα είναι Δευτέρα');
      expect(find.textContaining('Μένει ο δικός σου αριθμός 2.090 kcal'), findsOneWidget);
      expect(find.textContaining('ο δικός σου αριθμός ·'), findsOneWidget, reason: 'V-6');
      await _save(t);
      final g = store.goals!;
      expect((g.since, g.kcal, g.kcalSet), ('2026-11-23', 2090, 2090));
      expect(g.hist, isEmpty, reason: 'ο στόχος δεν άλλαξε');
    });

    testWidgets('Κυριακή 22/11: «Δευτέρα 23/11»· «Πάρε τον υπολογισμό» βγάζει τον δικό σου αριθμό', (t) async {
      final store = HealthStore()..setProfile(_me)..setGoals(_old());
      await _wizard(t, store, DateTime(2026, 11, 22, 20));
      await _save(t);
      // Την Κυριακή η προεπιλογή είναι η Δευτέρα.
      expect(t.widget<ChoiceChip>(find.byKey(const ValueKey('wizard-start-monday'))).selected, isTrue);
      await t.ensureVisible(find.byKey(const ValueKey('wizard-own-toggle')));
      await t.tap(find.byKey(const ValueKey('wizard-own-toggle')));
      await t.pumpAndSettle();
      expect(find.textContaining('δεν μένει: ισχύει ο υπολογισμός'), findsOneWidget);
      await _save(t);
      final g = store.goals!;
      expect(g.since, '2026-11-23');
      expect(g.kcalSet, isNull);
      expect(firstCheckDay(g).weekday, DateTime.monday);
    });

    testWidgets('Χωρίς παλιούς στόχους: αρχή σήμερα, χωρίς «Συνεχίζω»', (t) async {
      final store = HealthStore()..setProfile(_me);
      await _wizard(t, store, DateTime(2026, 11, 23, 9));
      // Χωρίς παλιούς στόχους η ερώτηση του γιατρού θέλει απάντηση.
      await t.tap(find.byKey(const ValueKey('opt-doc-no')));
      await t.pumpAndSettle();
      await _save(t);
      expect(find.byKey(const ValueKey('wizard-start-keep')), findsNothing);
      await _save(t);
      expect(store.goals!.since, '2026-11-23');
    });
  });

  test('V-2: νέοι στόχοι από σήμερα με άλλο αριθμό: η αλλαγή γράφεται χθες (σήμερα κρίνεται με τον νέο)', () {
    final o = _old(kcalSet: 2410);
    final g = _old(kcalSet: 2200, since: '2026-11-23').recordChangeFrom(o, DateTime(2026, 11, 23, 9));
    expect(g.hist.single.day, '2026-11-22');
  });

  test('W-5: δικός σου αριθμός την ίδια μέρα με την αρχή: καμία γραμμή στο ιστορικό', () {
    final g = _old(kcalSet: null, since: '2026-11-23');
    final own = g.copyWith(kcalSet: 2090).recordChangeFrom(g, DateTime(2026, 11, 23, 12));
    expect(own.hist, isEmpty);
    final later = g.copyWith(kcalSet: 2090).recordChangeFrom(g, DateTime(2026, 11, 25, 12));
    expect(later.hist, isNotEmpty);
  });
}
