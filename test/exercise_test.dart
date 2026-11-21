// Βιβλιοθήκη ασκήσεων (8/11): δεδομένα, ρυθμός, ζωγραφική, σελίδες.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/exercise/ex_data.dart';
import 'package:ygeia_forma/exercise/ex_painter.dart';
import 'package:ygeia_forma/exercise/ex_player.dart';
import 'package:ygeia_forma/pages/exercise_detail.dart';
import 'package:ygeia_forma/pages/exercise_library.dart';
import 'package:ygeia_forma/theme.dart';

ExLibrary _lib() => ExLibrary.fromJson(jsonDecode(File('assets/exercises/exercises.json').readAsStringSync()) as Map<String, dynamic>);

void main() {
  final lib = _lib();

  // Α24 (απόφαση χρήστη 21/11): ελληνικό όνομα σε κάθε άσκηση· το αγγλικό, όπου υπάρχει, μικρό από κάτω.
  test('Α24: κανένα όνομα άσκησης με αγγλική λέξη· 13 ασκήσεις έχουν και σύντομο αγγλικό όνομα', () {
    for (final e in lib.list) {
      expect(RegExp(r'[A-Za-z]').hasMatch(e.name), isFalse, reason: '${e.id}: «${e.name}»');
      // Το ρολόι δείχνει το ελληνικό όνομα· κανένα νέο όνομα πιο μακρύ από το μακρύτερο παλιό (31 χαρακτήρες).
      expect(e.name.length, lessThanOrEqualTo(31), reason: e.id);
      if (e.enName case final en?) {
        expect(RegExp(r'^[A-Z][A-Za-z ]+$').hasMatch(en), isTrue, reason: '${e.id}: «$en»');
        // Η αναζήτηση βρίσκει την άσκηση και με το αγγλικό της όνομα (λέξεις αναζήτησης).
        for (final w in en.toLowerCase().split(' ')) {
          expect('${e.en} ${e.id}'.contains(w), isTrue, reason: '${e.id}: η αναζήτηση δεν έχει «$w»');
        }
      }
    }
    expect({for (final e in lib.list) if (e.enName != null) e.id: e.enName}, {
      'dips': 'Dips',
      'hammer_curl': 'Hammer curl',
      'band_pushdown': 'Band pushdown',
      'crunch': 'Crunch',
      'reverse_crunch': 'Reverse crunch',
      'pallof': 'Pallof press',
      'face_pull': 'Face pull',
      'goblet': 'Goblet squat',
      'rdl': 'Romanian deadlift',
      'split_squat': 'Split squat',
      'leg_curl': 'Leg curl',
      'leg_ext': 'Leg extension',
      'hip_thrust': 'Hip thrust',
    });
    expect(lib.byId('goblet')!.name, 'Κάθισμα με βάρος στο στήθος');
    expect(lib.byId('rdl')!.name, 'Ρουμανική άρση θανάτου');
    // Ανεξάρτητος έλεγχος 21/11 (Α24-1): κανένα κείμενο της βιβλιοθήκης δεν λέει πια άσκηση με το παλιό αγγλικό όνομα.
    for (final e in lib.list) {
      final texts = [e.feel, ...e.setup, ...e.steps, ...e.mistakes, ...e.tips, for (final c in e.cues) c.text].join(' ').toLowerCase();
      for (final old in ['crunch', 'pushdown', 'deadlift', 'goblet', 'squat', 'leg curl', 'leg extension', 'hip thrust', 'face pull', 'pallof', 'hammer']) {
        expect(texts.contains(old), isFalse, reason: '${e.id}: «$old»');
      }
    }
    // Τα ονόματα μένουν μοναδικά.
    expect({for (final e in lib.list) e.name}.length, lib.list.length);
    // Η γραμμή των λιστών επιλογής: με αγγλικό όνομα μπροστά, αλλιώς μόνο ο εξοπλισμός (όπως πριν).
    expect(exEquipLine(lib.byId('goblet')), 'Goblet squat ·\u00A0Kettlebell');
    expect(exEquipLine(lib.byId('db_press')), lib.byId('db_press')!.equip);
    expect(exEquipLine(null), '');
  });

  test('όλες οι ασκήσεις έχουν πλήρη κείμενα και σωστά δεδομένα κίνησης', () {
    expect(lib.list.length, greaterThanOrEqualTo(29));
    final ids = <String>{};
    for (final e in lib.list) {
      expect(ids.add(e.id), isTrue, reason: 'διπλό ${e.id}');
      expect(exGroups.containsKey(e.group), isTrue, reason: e.id);
      expect(e.primary, isNotEmpty, reason: e.id);
      for (final k in [e.setup, e.steps, e.mistakes, e.tips]) {
        expect(k, isNotEmpty, reason: e.id);
      }
      expect(e.feel, isNotEmpty);
      for (final cue in e.cues) {
        for (final i in cue.phases) {
          expect(i, inInclusiveRange(0, e.tempo.length - 1), reason: e.id);
        }
      }
      for (final a in e.alt) {
        expect(lib.byId(a), isNotNull, reason: '${e.id} → $a');
      }
      final a = e.anim;
      expect(a.frames.length, lib.n);
      for (final f in a.frames) {
        expect(f.length, a.nd * 3);
      }
      expect(a.stat.length, a.ns * 3);
      expect(a.joints.length, exBody.length);
      bool ok(int k) => k >= 0 && k < a.count;
      expect(a.joints.every(ok), isTrue);
      for (final p in a.prims) {
        expect([...p.pts, if (p.kind == 'rod') ...[p.a, p.b], if (p.kind == 'disc') ...[p.c, p.n], if (p.kind == 'ball') p.c].every(ok), isTrue, reason: e.id);
      }
      for (final m in a.muscles) {
        expect([m.c, m.u, m.v].every(ok), isTrue);
        expect(e.tone(m.id) >= 0, isTrue);
      }
    }
    // Έμφαση που ζήτησε ο χρήστης: στήθος, χέρια, κοιλιακοί.
    int count(String g) => lib.list.where((e) => e.group == g).length;
    expect(count('chest'), greaterThanOrEqualTo(6));
    expect(count('arms'), greaterThanOrEqualTo(6));
    expect(count('abs'), greaterThanOrEqualTo(4));
  });

  test('κανόνες ώμων: τίποτα πίσω από τον αυχένα, όχι όρθια κωπηλασία, σήμανση στις επικίνδυνες', () {
    for (final e in lib.list) {
      final t = '${e.name} ${e.en}'.toLowerCase();
      expect(t.contains('upright row'), isFalse);
      expect(t.contains('behind'), isFalse);
    }
    for (final id in ['dips', 'overhead_ext', 'shoulder_press']) {
      expect(lib.byId(id)!.caution, isNotNull, reason: id);
    }
  });

  test('ρυθμός: το p μένει στο [0, 1] και οι φάσεις κάνουν κύκλο', () {
    for (final e in lib.list) {
      final seen = <int>{};
      for (var t = 0.0; t < e.cycle * 2; t += 0.05) {
        final (p, i) = e.at(t);
        expect(p, inInclusiveRange(0.0, 1.0));
        seen.add(i);
      }
      expect(seen.length, e.tempo.length, reason: e.id);
    }
  });

  test('οι αρθρώσεις κρατούν τα μήκη τους σε όλη την κίνηση (± 2 cm)', () {
    double dist(ExAnim a, List<double> P, String x, String y) {
      final i = a.joints[exBody.indexOf(x)], j = a.joints[exBody.indexOf(y)];
      final dx = P[3 * i] - P[3 * j], dy = P[3 * i + 1] - P[3 * j + 1], dz = P[3 * i + 2] - P[3 * j + 2];
      return (dx * dx + dy * dy + dz * dz);
    }

    for (final e in lib.list) {
      final a = e.anim;
      for (final (x, y) in [('hipL', 'kneeL'), ('kneeR', 'ankR'), ('shL', 'elbL'), ('elbR', 'wriR')]) {
        final p0 = a.points(0), p1 = a.points(1), ph = a.points(0.5);
        final d0 = dist(a, p0, x, y), d1 = dist(a, p1, x, y), dh = dist(a, ph, x, y);
        expect((d0 - d1).abs(), lessThan(0.02), reason: '${e.id} $x-$y');
        expect((d0 - dh).abs(), lessThan(0.03), reason: '${e.id} $x-$y');
      }
      // Τίποτα από το σώμα κάτω από το πάτωμα.
      for (final p in [0.0, 0.5, 1.0]) {
        final P = a.points(p);
        for (final k in a.joints) {
          expect(P[3 * k + 1], greaterThan(-0.01), reason: '${e.id} p=$p');
        }
      }
    }
  });

  test('η ζωγραφική δουλεύει για κάθε άσκηση, όψη και θέμα', () {
    for (final dark in [false, true]) {
      final colors = ExColors.of(dark: dark, accent: const Color(0xFFC2410C), good: const Color(0xFF3F7D20));
      for (final e in lib.list) {
        for (final yaw in [e.yaw, e.yaw2, 45.0]) {
          for (final p in [0.0, 0.37, 1.0]) {
            final rec = ui.PictureRecorder();
            ExPainter(ex: e, p: p, yaw: yaw, elev: e.elev, colors: colors, guides: true).paint(Canvas(rec), const Size(320, 260));
            rec.endRecording().dispose();
          }
        }
      }
    }
  });

  group('σελίδες', () {
    setUp(() => ExClock.frozen = true);

    Future<void> pump(WidgetTester t, Widget w, {Size size = const Size(400, 900)}) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = size;
      addTearDown(t.view.reset);
      await t.runAsync(() => ExLibrary.load(inline: true));
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: w)));
      await t.pumpAndSettle();
    }

    testWidgets('αναζήτηση χωρίς τόνους και ομάδες', (t) async {
      await pump(t, const ExerciseLibraryPage());
      expect(find.byKey(const ValueKey('ex-row-db_press')), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('ex-search')), 'κοιλιακοι');
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('ex-row-crunch')), findsOneWidget);
      expect(find.byKey(const ValueKey('ex-row-rdl')), findsNothing);
      await t.enterText(find.byKey(const ValueKey('ex-search')), 'lastixo');
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('ex-row-band_fly')), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('ex-search')), '');
      await t.tap(find.byKey(const ValueKey('ex-group-arms')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('ex-row-db_curl')), findsOneWidget);
      expect(find.byKey(const ValueKey('ex-row-db_press')), findsNothing);
    });

    testWidgets('Α24: βιβλιοθήκη και σελίδα άσκησης δείχνουν το αγγλικό όνομα κάτω από το ελληνικό, όπου υπάρχει', (t) async {
      await pump(t, const ExerciseLibraryPage());
      await t.enterText(find.byKey(const ValueKey('ex-search')), 'goblet');
      await t.pumpAndSettle();
      final row = find.byKey(const ValueKey('ex-row-goblet'));
      expect(row, findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('Κάθισμα με βάρος στο στήθος')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey('ex-en-goblet'))).data, 'Goblet squat');
      // Το αγγλικό κάτω από το ελληνικό, όχι δίπλα.
      expect(t.getTopLeft(find.byKey(const ValueKey('ex-en-goblet'))).dy,
          greaterThan(t.getTopLeft(find.descendant(of: row, matching: find.text('Κάθισμα με βάρος στο στήθος'))).dy));
      // Ανεξάρτητος έλεγχος 21/11 (Α24-2): η αναζήτηση βρίσκει το αγγλικό όνομα ακριβώς όπως γράφεται στην οθόνη.
      await t.enterText(find.byKey(const ValueKey('ex-search')), 'band pushdown');
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('ex-row-band_pushdown')), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('ex-search')), '');
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('ex-row-db_press')), findsOneWidget);
      expect(find.byKey(const ValueKey('ex-en-db_press')), findsNothing);
      expect(t.takeException(), isNull);

      // Σελίδα άσκησης, κινητό και ανοιχτό Fold: μία γραμμή, χωρίς υπερχείλιση. (Με τη γραμματοσειρά των δοκιμών, που έχει
      // τετράγωνα γράμματα, η γραμμή είναι πολύ πιο φαρδιά από την οθόνη: ελέγχεται ότι μικραίνει αντί να σπάει ή να κόβεται.)
      final l = ExLibrary.loaded!;
      for (final size in const [Size(400, 900), Size(860, 900)]) {
        await pump(t, ExerciseDetailPage(ex: l.byId('leg_curl')!, lib: l, key: UniqueKey()), size: size);
        expect(find.text('Κάμψεις ποδιών στον πάγκο'), findsOneWidget);
        final line = t.widget<Text>(find.byKey(const ValueKey('ex-en-name')));
        expect(line.data, 'Leg curl ·\u00A0Πόδια ·\u00A0${l.byId('leg_curl')!.equip}');
        expect(t.getSize(find.byKey(const ValueKey('ex-en-name'))).height, lessThan(22), reason: '$size: μία γραμμή');
        expect(t.takeException(), isNull, reason: '$size');
      }
      // Άσκηση χωρίς αγγλικό όνομα: η γραμμή όπως πριν.
      await pump(t, ExerciseDetailPage(ex: l.byId('db_press')!, lib: l, key: UniqueKey()));
      expect(find.byKey(const ValueKey('ex-en-name')), findsNothing);
      expect(find.text('${l.byId('db_press')!.groupName} ·\u00A0${l.byId('db_press')!.equip}'), findsOneWidget);
    });

    testWidgets('σελίδα άσκησης: κίνηση, σημεία προσοχής, όψη, εναλλακτικές', (t) async {
      final l = ExLibrary.loaded!;
      await pump(t, ExerciseDetailPage(ex: l.byId('db_press')!, lib: l));
      expect(find.byKey(const ValueKey('ex-anim-db_press')), findsOneWidget);
      expect(find.text('Πρόσεξε τώρα'), findsOneWidget);
      await t.scrollUntilVisible(find.text('Συχνά λάθη'), 300);
      expect(find.text('Συχνά λάθη'), findsOneWidget);
      await t.scrollUntilVisible(find.byKey(const ValueKey('ex-view')), -300);
      await t.tap(find.byKey(const ValueKey('ex-view')));
      await t.pump();
      // Παίζει και σταματά χωρίς σφάλματα.
      await t.tap(find.byKey(const ValueKey('ex-play')));
      for (var i = 0; i < 30; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.tap(find.byKey(const ValueKey('ex-play')));
      await t.pump();
      expect(t.takeException(), isNull);
    });

    testWidgets('Fold ανοιχτό: δύο στήλες χωρίς υπερχείλιση', (t) async {
      final l = ExLibrary.loaded!;
      await pump(t, ExerciseDetailPage(ex: l.byId('ab_wheel')!, lib: l), size: const Size(860, 900));
      expect(t.takeException(), isNull);
      final anim = t.getRect(find.byKey(const ValueKey('ex-anim-ab_wheel')));
      expect(anim.right, lessThan(470));
    });
  });
}
