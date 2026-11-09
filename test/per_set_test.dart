// 9/11: παλμοί ανά σετ, διαγραφή από παντού, ευθυγράμμιση παλμών ρολογιού, ώρα ✓ από το ρολόι.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/exercise/ex_data.dart';
import 'package:ygeia_forma/exercise/ex_player.dart';
import 'package:ygeia_forma/pages/training/session_page.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/set_hr.dart';
import 'package:ygeia_forma/training/training_store.dart';
import 'package:ygeia_forma/training/wear_link.dart';

import 'training_sample.dart';

final now = DateTime(2026, 11, 20, 18, 0);

/// Παλμοί ανά δευτερόλεπτο: [base] παντού, [peak] στα 30″ πριν από κάθε ✓ (σε δευτερόλεπτα από την αρχή).
List<List<int>> _hr(int seconds, List<int> ticks, {int base = 95, int peak = 120}) => [
      for (var t = 0; t <= seconds; t++) [t, ticks.any((x) => t > x - 30 && t <= x) ? peak : base],
    ];

Session _session(DateTime start, List<int> tickSec, List<List<int>> hr) => Session(
      id: 'x1',
      workout: 'A',
      name: 'Προπόνηση Α',
      programId: 'p',
      start: start,
      end: start.add(const Duration(minutes: 20)),
      hr: hr,
      items: [
        ExLog(ex: 'db_press', sets: 3, lo: 8, hi: 12, rir: 2, rest: 90, log: [
          for (final t in tickSec.take(3)) SetLog(load: 10.3, reps: 8, done: true, at: start.millisecondsSinceEpoch + t * 1000),
        ]),
        ExLog(ex: 'db_row', sets: 2, lo: 8, hi: 12, rir: 2, rest: 90, log: [
          for (final t in tickSec.skip(3)) SetLog(load: 14.3, reps: 10, done: true, at: start.millisecondsSinceEpoch + t * 1000),
          SetLog(load: 14.3, reps: 10),
        ]),
      ],
    );

void main() {
  group('παλμοί ανά σετ', () {
    final ticks = [60, 180, 300, 420];

    test('♥ σετ = μέσος στα 30″ ως το ✓· ♥ διάλειμμα = χαμηλότερος 10″ ως το επόμενο σετ', () {
      final s = _session(now, ticks, _hr(500, ticks));
      final r = sessionSetHr(s);
      expect(r.length, 2);
      // Τα 30″ ως το ✓ (t−29 … t) είναι 120, και η τιμή ακριβώς στο t−30 είναι 95: (95 + 30×120) / 31 = 119.
      expect(r[0].sets[0]!.set, 119);
      expect(r[0].sets[0]!.rest, 95);
      expect(r[0].avg, 119);
      // Το τελευταίο σετ της προπόνησης: χωρίς διάλειμμα.
      expect(r[1].sets[0]!.rest, isNull);
      // Σετ που δεν έγινε: null.
      expect(r[1].sets[1], isNull);
    });

    test('διάλειμμα ως την επόμενη άσκηση, όχι μόνο μέσα στην ίδια', () {
      final s = _session(now, ticks, _hr(500, ticks));
      // Το 3ο σετ του πιεστικού (300″) ακολουθείται από την κωπηλασία (420″).
      expect(sessionSetHr(s)[0].sets[2]!.rest, 95);
    });

    test('λίγες τιμές (παλιό ρολόι, ανά 10″ ή κενό): «—» αντί για αριθμό από 1–2 τιμές', () {
      final sparse = [
        [0, 90],
        [45, 118],
        [200, 100],
      ];
      final r = sessionSetHr(_session(now, ticks, sparse));
      expect(r[0].sets[0]!.set, isNull);
      expect(r[0].avg, isNull);
    });

    test('χωρίς παλμούς: τίποτα', () {
      expect(sessionSetHr(_session(now, ticks, [])), isEmpty);
    });

    test('μικρό διάλειμμα (<15″): χωρίς τιμή διαλείμματος', () {
      final close = [60, 100, 140, 180];
      final r = sessionSetHr(_session(now, close, _hr(300, close)));
      // 60 → επόμενο ✓ στα 100: το επόμενο σετ ξεκινά στα 70, άρα διάλειμμα 10″.
      expect(r[0].sets[0]!.rest, isNull);
    });
  });

  group('διαγραφή από παντού', () {
    test('σβήνει, μένει σβησμένη μετά από φόρτωμα, αναίρεση', () async {
      final io = MemoryTrainingIO();
      final t = TrainingStore(io: io, clock: () => now)..replaceAll(sampleTraining(now).toJson());
      final id = t.sessions.last.id;
      final n = t.sessions.length;
      final gone = t.deleteSession(id);
      expect(gone, isNotNull);
      expect(t.sessions.length, n - 1);
      expect(t.historyOf('db_press').length, n - 1, reason: 'και από την πρόοδο');
      await t.save();
      final back = TrainingStore(io: io, clock: () => now);
      await back.load();
      expect(back.sessions.any((x) => x.id == id), isFalse);
      expect(back.deleted, contains(id));
      back.undoDelete(gone!);
      expect(back.sessions.any((x) => x.id == id), isTrue);
      expect(back.deleted, isNot(contains(id)));
      expect(back.sessions.map((x) => x.start).toList(), [...back.sessions.map((x) => x.start)]..sort());
    });

    test('ούτε από παλιό αντίγραφο ούτε από το ρολόι ξαναγυρίζει', () {
      final backup = sampleTraining(now).toJson();
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => now)..replaceAll(backup);
      t.ready = true;
      final id = t.sessions.first.id;
      t.deleteSession(id);
      expect(t.mergeBackup(backup), 0);
      expect(t.sessions.any((x) => x.id == id), isFalse);
      // Περπάτημα από το ρολόι που σβήστηκε: το ίδιο αποτέλεσμα ξανά (π.χ. ξανασταλμένο) δεν μπαίνει.
      final walk = {'v': 1, 'kind': 'cardio', 'id': 'k1', 'start': now.millisecondsSinceEpoch, 'end': now.millisecondsSinceEpoch + 600000, 'cardio': {'sec': 600}};
      expect(t.importWatch(walk), isTrue);
      t.deleteSession('w-k1');
      expect(t.importWatch(walk), isFalse);
      expect(t.sessions.any((x) => x.id == 'w-k1'), isFalse);
    });
  });

  group('ακρίβεια παλμών ρολογιού', () {
    test('οι παλμοί μπαίνουν στη σωστή ώρα της προπόνησης (hrT0)', () {
      final t = sampleTraining(now);
      final s = t.start(t.program!.workout('A')!);
      // Το ρολόι μπήκε 95″ μετά την αρχή της προπόνησης του κινητού.
      final t0 = s.start.millisecondsSinceEpoch + 95000;
      t.importWatch({
        'v': 1,
        'kind': 'hr',
        'sid': s.id,
        'hrT0': t0,
        'hr': [
          [0, 100],
          [1, 101],
          [2, 102],
        ],
      });
      expect(s.hr.first, [95, 100]);
      expect(s.hr.last, [97, 102]);
    });

    test('χωρίς hrT0 (ρολόι ως #87): όπως ήρθαν', () {
      expect(TrainingStore.alignHr([
        [3, 90],
      ], null, now), [
        [3, 90],
      ]);
    });

    test('✓ από το ρολόι κρατά την ώρα του ρολογιού, όχι της άφιξης', () {
      var at = now;
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => at)..replaceAll(sampleTraining(now).toJson());
      t.ready = true;
      final s = t.start(t.program!.workout('A')!);
      final link = WearLink();
      at = now.add(const Duration(minutes: 5));
      final watchAt = now.add(const Duration(minutes: 2)).millisecondsSinceEpoch;
      link.apply(t, WatchCmd('tick', {'op': 'tick', 'i': 0, 's': 0, 'at': watchAt, 'late': true}));
      expect(s.items[0].log[0].at, watchAt);
      // Ώρα έξω από την προπόνηση (λάθος ρολόι): η ώρα του κινητού.
      link.apply(t, WatchCmd('tick', {'op': 'tick', 'i': 0, 's': 1, 'at': 5}));
      expect(s.items[0].log[1].at, at.millisecondsSinceEpoch);
    });
  });

  group('οθόνη', () {
    setUp(() => ExClock.frozen = true);

    testWidgets('σύνοψη: πίνακας ανά σετ, ⓘ, διαγραφή με επιβεβαίωση και αναίρεση', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 2400);
      addTearDown(tester.view.reset);
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final t = sampleTraining(now);
      final ticks = [60, 180, 300, 420];
      final s = _session(now.subtract(const Duration(days: 1)), ticks, _hr(500, ticks));
      t.sessions.add(s);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const ValueKey('open'),
                onPressed: () => Navigator.of(context).push(SummaryPage.route(t, s)),
                child: const Text('άνοιγμα'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      expect(find.text('~119'), findsWidgets);
      expect(find.text('↓ 95'), findsWidgets);
      expect(find.byKey(const ValueKey('sum-ex-avg-db_press')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('hr-info')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('hr-info-sheet')), findsOneWidget);
      await tester.tapAt(const Offset(200, 20));
      await tester.pumpAndSettle();

      final del = find.byKey(const ValueKey('summary-delete'));
      await tester.scrollUntilVisible(del, 300, scrollable: find.byType(Scrollable).last);
      await tester.pumpAndSettle();
      await tester.tap(del);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('del-cancel')));
      await tester.pumpAndSettle();
      expect(t.sessions.contains(s), isTrue, reason: '«Άκυρο»: τίποτα δεν σβήνεται');

      await tester.tap(del);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('del-ok')));
      await tester.pumpAndSettle();
      expect(t.sessions.any((x) => x.id == s.id), isFalse);
      expect(find.byType(SummaryPage), findsNothing);
      expect(find.text('Αναίρεση'), findsOneWidget);
      await tester.tap(find.text('Αναίρεση'));
      await tester.pumpAndSettle();
      expect(t.sessions.any((x) => x.id == s.id), isTrue);
    });

    testWidgets('σύνοψη αμέσως μετά την προπόνηση: χωρίς κουμπί διαγραφής', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 2000);
      addTearDown(tester.view.reset);
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final t = sampleTraining(now);
      final s = t.start(t.program!.workout('A')!);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: SummaryPage(training: t, session: s, live: true)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('summary-delete')), findsNothing);
    });
  });
}
