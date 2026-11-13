// 9/11: περπάτημα με παύσεις, ανά km (GPS), βήματα/λεπτό, πτώση παλμών στο 1′ από το ρολόι.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/exercise/ex_data.dart';
import 'package:ygeia_forma/exercise/ex_player.dart';
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/pages/training/session_page.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/training_store.dart';
import 'package:ygeia_forma/training/walk_stats.dart';

import 'training_sample.dart';

final now = DateTime(2026, 11, 20, 18, 0);

/// Αποτέλεσμα περπατήματος όπως το στέλνει το ρολόι #89: 2,41 km, παύση 300″–310″, πτώση 120 → 102.
Map<String, dynamic> walkResult({bool gps = true, Map<String, dynamic>? hrr}) {
  final start = now.millisecondsSinceEpoch;
  int hrAt(int t) => t >= 300 && t <= 310 ? 80 : t <= 610 ? 100 : t <= 1230 ? 110 : 120;
  return {
    'v': 1,
    'kind': 'cardio',
    'id': 'walk$start',
    'w': 'walk',
    'name': 'Περπάτημα',
    'start': start,
    'end': start + 1760 * 1000,
    'hrAvg': 108,
    'hrMax': 125,
    'hrT0': start,
    'hr': [
      for (var t = 0; t <= 1760; t++) [t, hrAt(t)],
    ],
    'cardio': {
      'activity': 'walk',
      'sec': 1700,
      'm': 2410.0,
      'steps': 3300,
      'gps': gps,
      'km': [
        [600, 610],
        [1210, 1230],
      ],
      'pz': [
        [300, 310],
      ],
      'hrr': hrr ?? {'e': 120, 'm': 102},
    },
  };
}

void main() {
  group('από το ρολόι στο κινητό', () {
    test('παύσεις, χιλιόμετρα, GPS, ενεργός χρόνος, πτώση παλμών: γράφονται και μένουν μετά από αποθήκευση', () async {
      final io = MemoryTrainingIO();
      final t = TrainingStore(io: io, clock: () => now)..replaceAll(sampleTraining(now).toJson());
      expect(t.importWatch(walkResult()), isTrue);
      final s = t.sessions.firstWhere((x) => x.isCardio);
      expect(s.cardioSec, 1700);
      expect(s.gps, isTrue);
      expect(s.splits, [
        [600, 610],
        [1210, 1230],
      ]);
      expect(s.pauses, [
        [300, 310],
      ]);
      expect((s.hrrEnd, s.hrr1), (120, 102));
      await t.save();
      final back = TrainingStore(io: io, clock: () => now);
      await back.load();
      final b = back.sessions.firstWhere((x) => x.isCardio);
      expect(b.splits, s.splits);
      expect(b.pauses, s.pauses);
      expect((b.hrrEnd, b.hrr1, b.cardioSec, b.gps), (120, 102, 1700, true));
    });

    test('παράλογη πτώση παλμών (εκτός 30–230): δεν γράφεται', () {
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => now);
      t.importWatch(walkResult(hrr: {'e': 400, 'm': 102}));
      expect(t.sessions.single.hrrEnd, isNull);
    });

    test('ρολόι ως #88 (χωρίς τα νέα πεδία): όπως πριν', () {
      final r = walkResult()..['cardio'] = {'activity': 'walk', 'sec': 1700, 'm': 2410.0, 'steps': 3300};
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => now);
      t.importWatch(r);
      final s = t.sessions.single;
      expect(s.splits, isEmpty);
      expect(s.gps, isNull);
      expect(walkSplits(s), isEmpty);
    });
  });

  group('υπολογισμοί', () {
    Session walk({bool gps = true}) {
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => now);
      t.importWatch(walkResult(gps: gps));
      return t.sessions.single;
    }

    test('ανά km: χρόνος χωρίς παύσεις, παλμοί του km χωρίς όσους έπεσαν στην παύση', () {
      final k = walkSplits(walk());
      expect(k.length, 3);
      expect((k[0].label, k[0].sec, k[0].hr), ('1', 600, 100), reason: 'η παύση (80) δεν μετρά στους παλμούς του 1ου km');
      expect((k[1].label, k[1].sec, k[1].hr), ('2', 610, 110));
      expect((k[2].label, k[2].sec, k[2].hr, k[2].partial), ('0,41', 490, 120, true));
    });

    test('χωρίς GPS: κανένας πίνακας ανά km', () {
      expect(walkSplits(walk(gps: false)), isEmpty);
    });

    test('ρυθμός και βήματα ανά λεπτό από τον ενεργό χρόνο', () {
      final s = walk();
      expect(paceSecPerKm(s), (1700 / 2.41).round());
      expect(paceText(paceSecPerKm(s)!), '11:45 /km');
      expect(cadence(s), (3300 / (1700 / 60)).round());
      expect(pausedSec(s), 10);
    });
  });

  group('οθόνη', () {
    setUp(() => ExClock.frozen = true);

    testWidgets('σύνοψη περπατήματος: ανά km, πτώση παλμών, οδηγίες', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 2400);
      addTearDown(tester.view.reset);
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => now)..ready = true;
      t.importWatch(walkResult());
      final s = t.sessions.single;
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: SummaryPage(training: t, session: s)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('walk-km')), findsOneWidget);
      expect(find.text('0,41'), findsOneWidget);
      expect(find.text('10:00'), findsOneWidget);
      expect(find.byKey(const ValueKey('hrr-drop')), findsOneWidget);
      expect(find.text('−18'), findsOneWidget);
      // Round 1 (f6b · U5-15 / U6-10): η μονάδα πήγε στην ετικέτα («11:45» με «ρυθμός ανά km»· πριν «11:45 /km» / «ρυθμός»).
      final extra = find.byKey(const ValueKey('walk-extra'));
      expect(find.descendant(of: extra, matching: find.text('11:45')), findsOneWidget);
      expect(find.descendant(of: extra, matching: find.text('ρυθμός ανά km')), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('hrr-info')), 200, scrollable: find.byType(Scrollable).last);
      await tester.tap(find.byKey(const ValueKey('hrr-info')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('hrr-info-sheet')), findsOneWidget);
    });
  });
}
