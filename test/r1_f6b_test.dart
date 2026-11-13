// round1 · f6b: οθόνες προπόνησης και βιβλιοθήκη ασκήσεων. Οι αναμενόμενες τιμές βγήκαν από τους κανόνες (python στο
// /home/claude/scratch/f6b), όχι από τον νέο κώδικα. Όλα τα πρόσωπα και οι αριθμοί είναι φανταστικά.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/exercise/ex_data.dart';
import 'package:ygeia_forma/exercise/ex_painter.dart';
import 'package:ygeia_forma/exercise/ex_player.dart';
import 'package:ygeia_forma/pages/training/hr_widgets.dart';
import 'package:ygeia_forma/pages/training/session_page.dart';
import 'package:ygeia_forma/pages/training/today_training_card.dart';
import 'package:ygeia_forma/pages/training/training_common.dart';
import 'package:ygeia_forma/pages/training/training_page.dart';
import 'package:ygeia_forma/pages/training/zone_widgets.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/training/progression.dart' show calibrate;
import 'package:ygeia_forma/training/program.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/training_store.dart';

import 'training_sample.dart';

final _json = File('assets/exercises/exercises.json').readAsStringSync();
ExLibrary _lib() => ExLibrary.fromJson(jsonDecode(_json) as Map<String, dynamic>);

/// Τα δευτερόλεπτα του ρυθμού κάθε άσκησης στο #100: δεν πρέπει να αλλάξουν (ο ρυθμός μπαίνει στους παλμούς ανά σετ, S6-8).
const _tempo100 = <String, List<double>>{
  'db_press': [2.0, 0.3, 1.2, 0.8],
  'incline_press': [2.0, 0.3, 1.2, 0.8],
  'pushup_handles': [2.0, 0.3, 1.1, 0.8],
  'pushup_bench': [2.0, 0.3, 1.1, 0.8],
  'band_fly': [1.3, 0.8, 2.2, 0.6],
  'dips': [2.2, 0.2, 1.2, 0.8],
  'db_curl': [1.2, 0.4, 2.4, 0.5],
  'incline_curl': [1.3, 0.3, 2.6, 0.6],
  'hammer_curl': [1.2, 0.4, 2.4, 0.5],
  'lying_ext': [2.2, 0.3, 1.2, 0.6],
  'overhead_ext': [2.4, 0.4, 1.3, 0.6],
  'band_pushdown': [1.1, 0.5, 2.0, 0.4],
  'crunch': [1.2, 1.0, 2.0, 0.6],
  'reverse_crunch': [1.4, 0.6, 2.2, 0.6],
  'ab_wheel': [2.4, 0.4, 1.6, 0.7],
  'pallof': [1.2, 2.0, 1.2, 0.6],
  'db_row': [1.2, 0.5, 2.0, 0.6],
  'band_pulldown': [1.3, 0.5, 2.2, 0.5],
  'assisted_pullup': [1.5, 0.4, 2.4, 0.6],
  'face_pull': [1.2, 1.0, 2.0, 0.5],
  'band_er': [1.4, 0.8, 2.2, 0.4],
  'shoulder_press': [2.0, 0.3, 1.2, 0.6],
  'lateral_raise': [1.4, 0.4, 2.4, 0.4],
  'goblet': [2.4, 0.5, 1.5, 0.8],
  'rdl': [2.6, 0.4, 1.4, 0.8],
  'split_squat': [2.2, 0.3, 1.4, 0.7],
  'leg_curl': [1.2, 0.5, 2.4, 0.4],
  'leg_ext': [1.2, 0.6, 2.4, 0.4],
  'hip_thrust': [1.2, 1.0, 2.0, 0.4],
};

/// Όλα τα κείμενα μιας άσκησης που βλέπει ο χρήστης.
List<String> _texts(Ex e) => [
      e.name,
      e.equip,
      e.feel,
      if (e.caution != null) e.caution!,
      ...e.setup,
      ...e.steps,
      ...e.mistakes,
      ...e.tips,
      for (final c in e.cues) c.text,
      for (final p in e.tempo) p.name,
      for (final g in e.anim.guides)
        if (g.label != null) g.label!,
    ];

/// Θέσεις των αρθρώσεων στο δείγμα [i] (x, y, z σε μέτρα).
Map<String, List<double>> _joints(Ex e, double p) {
  final a = e.anim;
  final pts = a.points(p);
  return {
    for (var n = 0; n < exBody.length; n++) exBody[n]: [pts[3 * a.joints[n]], pts[3 * a.joints[n] + 1], pts[3 * a.joints[n] + 2]],
  };
}

List<double> _sub(List<double> a, List<double> b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
double _len(List<double> a) => math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
double _angle(List<double> a, List<double> b) =>
    math.acos(((a[0] * b[0] + a[1] * b[1] + a[2] * b[2]) / (_len(a) * _len(b))).clamp(-1.0, 1.0)) * 180 / math.pi;

/// Ψεύτικο bundle: θυμάται το `cache` και μπορεί να αποτύχει την πρώτη φορά.
class _Bundle extends CachingAssetBundle {
  _Bundle({this.failFirst = false});
  final bool failFirst;
  int calls = 0;
  bool? lastCache;

  @override
  Future<ByteData> load(String key) => Future.error(FlutterError('μόνο κείμενο'));

  @override
  Future<String> loadString(String key, {bool cache = true}) {
    calls++;
    lastCache = cache;
    if (failFirst && calls == 1) return Future.error(FlutterError('δεν διαβάστηκε'));
    return Future.value(_json);
  }
}

/// Περπάτημα 30′ με παλμούς [bpm] κάθε 5″ (ζώνη 104–127), προαιρετικά με παύση.
Session _walk(int bpm, {List<List<int>> pauses = const []}) {
  final start = DateTime(2026, 11, 20, 8);
  return Session(
    id: 'w-$bpm',
    workout: 'walk',
    name: 'Περπάτημα',
    programId: '',
    start: start,
    end: start.add(const Duration(seconds: 1800)),
    cardioMinutes: 30,
    cardioSec: 1800,
    activity: 'walk',
    zoneLo: 104,
    zoneHi: 127,
    pauses: [for (final p in pauses) [...p]],
    hr: [for (var t = 0; t <= 1800; t += 5) [t, bpm]],
  );
}

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 1400)}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: w));
  await t.pumpAndSettle();
}

void main() {
  final lib = _lib();

  group('Βιβλιοθήκη ασκήσεων: κείμενα (round1)', () {
    test('S7-04: κανένα προσωπικό στοιχείο υγείας στα κείμενα του δημόσιου αρχείου', () {
      final personal = RegExp(r'ιστορικ|τενοντίτιδ|ώμους σου|ώμων σου|για σένα');
      for (final e in lib.list) {
        for (final x in _texts(e)) {
          expect(personal.hasMatch(x), isFalse, reason: '${e.id}: $x');
        }
      }
    });

    test('S7-05: στις ασκήσεις που σπρώχνουν/σηκώνουν, η ανάσα δεν λέει «τράβηγμα»', () {
      for (final id in ['shoulder_press', 'lateral_raise', 'db_press', 'incline_press', 'dips', 'pushup_bench', 'pushup_handles']) {
        final e = lib.byId(id)!;
        expect(e.tips.any((t) => t.contains('τράβηγμα')), isFalse, reason: id);
        expect(e.tips.any((t) => t.contains('εκπνοή')), isTrue, reason: id);
      }
    });

    test('S7-06: καμία φάση «Ανάσα»· κάθε άσκηση λέει πότε εισπνοή/εκπνοή στην κίνηση', () {
      for (final e in lib.list) {
        expect(e.tempo.any((p) => p.name == 'Ανάσα'), isFalse, reason: e.id);
        expect(e.tempo.any((p) => p.name.contains('πνοή')), isTrue, reason: e.id);
      }
      expect(lib.byId('pallof')!.tempo[1].name, contains('ανάσαινε'), reason: 'κράτημα 2″ χωρίς κράτημα της ανάσας');
    });

    test('S7-07: καμία αναφορά σε φωτογραφία ή ενότητα που δεν υπάρχει στην εφαρμογή', () {
      final ref = RegExp(r'Φ\d\d|\(\d{1,2}(\.\d)?\)');
      for (final e in lib.list) {
        for (final x in _texts(e)) {
          expect(ref.hasMatch(x), isFalse, reason: '${e.id}: $x');
        }
      }
    });

    test('S7-17: κάθε άσκηση με αλτήρες λέει να σφίξεις τα αστεράκια', () {
      final ids = [for (final e in lib.list) if (e.equip.toLowerCase().contains('αλτήρ')) e.id];
      expect(ids.length, 12);
      for (final id in ids) {
        expect(lib.byId(id)!.setup.join(' ').contains('αστεράκια'), isTrue, reason: id);
      }
    });

    test('S7-18: RDL ξεκινά με σκέτη τη μπάρα, όχι 20 kg', () {
      final s = lib.byId('rdl')!.setup.first;
      expect(s.contains('20 kg'), isFalse);
      expect(s, contains('10 kg'));
    });

    test('S7-19: leg curl χωρίς γλουτούς· «Ο λόγος:» όχι βέβαιος· Pedrosa σε άλλη άσκηση', () {
      expect(lib.byId('leg_curl')!.tone('glutes'), 0);
      expect(lib.byId('overhead_ext')!.tips.any((t) => t.contains('Ο λόγος:')), isFalse);
      expect(lib.byId('incline_curl')!.tips.any((t) => t.contains('Pedrosa 2023, σε άλλη άσκηση')), isTrue);
    });

    test('S7-23: στα λάστιχα, σημάδι στο πάτωμα για ίδια απόσταση κάθε φορά', () {
      for (final id in ['band_fly', 'band_pushdown', 'pallof', 'band_pulldown', 'face_pull', 'band_er']) {
        final e = lib.byId(id)!;
        expect([...e.setup, ...e.steps].join(' ').contains('σημάδι'), isTrue, reason: id);
      }
    });

    test('τα 29 ids και τα δευτερόλεπτα του ρυθμού ίδια με το #100', () {
      expect([for (final e in lib.list) e.id], _tempo100.keys.toList());
      for (final e in lib.list) {
        final want = _tempo100[e.id]!;
        expect(e.tempo.length, want.length, reason: e.id);
        for (var i = 0; i < want.length; i++) {
          expect(e.tempo[i].sec, closeTo(want[i], 1e-9), reason: '${e.id} φάση $i');
        }
      }
    });
  });

  group('Βιβλιοθήκη ασκήσεων: κίνηση (round1)', () {
    test('U5-20: πιεστικά και πίεση ώμων: ο πήχης κάθετος σε κάθε καρέ (≤ 8°)', () {
      for (final id in ['db_press', 'incline_press', 'shoulder_press']) {
        final e = lib.byId(id)!;
        for (var i = 0; i < lib.n; i++) {
          final j = _joints(e, i / (lib.n - 1));
          for (final s in ['L', 'R']) {
            expect(_angle(_sub(j['wri$s']!, j['elb$s']!), [0, 1, 0]), lessThanOrEqualTo(8), reason: '$id καρέ $i $s');
          }
        }
      }
    });

    test('S7-16: κωπηλασία, «Σφίξε»: αγκώνας < 15 cm πάνω από τον ώμο και < 45° πίσω από τον κορμό', () {
      final j = _joints(lib.byId('db_row')!, 1);
      expect(j['elbR']![1] - j['shR']![1], lessThan(0.15));
      expect(_angle(_sub(j['elbR']!, j['shR']!), _sub(j['pelvis']!, j['shC']!)), lessThan(45));
    });

    test('S7-16: leg extension: ο μηρός οριζόντιος πάνω στο κάθισμα', () {
      final j = _joints(lib.byId('leg_ext')!, 0);
      expect((j['kneeL']![1] - j['hipL']![1]).abs(), lessThan(0.04));
    });
  });

  group('Βιβλιοθήκη ασκήσεων: φόρτωση και ζωγραφική (round1)', () {
    setUp(resetExLibraryForTests);
    tearDown(resetExLibraryForTests);

    test('S7-08: το κείμενο δεν μένει στην κρυφή μνήμη του bundle', () async {
      final b = _Bundle();
      final l = await ExLibrary.load(bundle: b, inline: true);
      expect(l.list.length, 29);
      expect(b.lastCache, isFalse);
    });

    test('S7-20: αποτυχία φόρτωσης δεν μένει για πάντα· η δεύτερη φορά ξαναδιαβάζει', () async {
      final b = _Bundle(failFirst: true);
      await expectLater(ExLibrary.load(bundle: b, inline: true), throwsA(isA<FlutterError>()));
      expect(ExLibrary.loaded, isNull);
      final l = await ExLibrary.load(bundle: b, inline: true);
      expect(l.list.length, 29);
      expect(b.calls, 2);
    });

    test('S7-09: ίδια χρώματα = καμία ξαναζωγραφική της μικρής εικόνας', () {
      final e = lib.byId('db_press')!;
      final a = ExPainter(ex: e, p: .5, yaw: e.yaw, elev: e.elev, colors: ExColors.of(dark: false, accent: const Color(0xFFC2410C), good: const Color(0xFF3F7D20)));
      final b = ExPainter(ex: e, p: .5, yaw: e.yaw, elev: e.elev, colors: ExColors.of(dark: false, accent: const Color(0xFFC2410C), good: const Color(0xFF3F7D20)));
      expect(b.shouldRepaint(a), isFalse);
      final dark = ExPainter(ex: e, p: .5, yaw: e.yaw, elev: e.elev, colors: ExColors.of(dark: true, accent: const Color(0xFFC2410C), good: const Color(0xFF3F7D20)));
      expect(dark.shouldRepaint(a), isTrue);
    });

    testWidgets('S7-10: η κίνηση σταματά μόνη της μετά από ένα λεπτό', (t) async {
      ExClock.frozen = false;
      addTearDown(() => ExClock.frozen = false);
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(400, 1000);
      addTearDown(t.view.reset);
      // Χωρίς pumpAndSettle: η κίνηση ζητά καρέ όσο παίζει.
      await t.pumpWidget(MaterialApp(
          theme: buildTheme(Brightness.light), home: Scaffold(body: SingleChildScrollView(child: ExPlayer(ex: lib.byId('db_press')!)))));
      await t.pump();
      expect(find.byTooltip('Παύση'), findsOneWidget);
      for (var i = 0; i < 62; i++) {
        await t.pump(const Duration(seconds: 1));
      }
      expect(find.byTooltip('Συνέχεια'), findsOneWidget);
    });
  });

  group('Ζώνη περπατήματος (round1)', () {
    test('S6-4: το ⓘ λέει το πραγματικό λάθος του τύπου και για ποιους βγήκε', () {
      final a = zoneInfo.accuracy;
      expect(a.contains('±10'), isFalse);
      expect(a, contains('1 στους 3'));
      expect(a, contains('κάπνιζαν'));
      expect(a, contains('φάρμακα'));
      expect(zoneInfo.cite, contains('Papathanasiou 2013'));
    });

    test('U5-06: οι δονήσεις της ζώνης σε λέξεις', () {
      expect(zoneHighText,
          'Δύο σύντομες δονήσεις όταν μείνεις πάνω 20 δευτερόλεπτα. Ξανά μετά από 2 λεπτά, αν δεν κατέβεις. Όχι τα πρώτα 5 λεπτά.');
      expect(zoneLowText, 'Μία δόνηση όταν μείνεις κάτω 1 λεπτό. Ξανά μετά από 5 λεπτά.');
      for (final s in [zoneHighText, zoneLowText]) {
        expect(s.contains('′') || s.contains('″'), isFalse);
      }
      expect(hrGapText(1800, 'default', 300, false).$1, 'Οι παλμοί έλειπαν έως 30 λεπτά.');
      expect(hrGapText(8, '5s', 400, false).$1, contains('μεγαλύτερο κενό 8 δευτερόλεπτα'));
    });

    test('U5-28: με όριο γιατρού το κείμενο λέει ότι οι δονήσεις της ζώνης είναι κλειστές', () {
      expect(zoneLimitText(140), 'Έχεις όριο γιατρού (140): το ρολόι δονείται μόνο σε εκείνο. Οι δονήσεις της ζώνης είναι κλειστές.');
    });

    test('S6-3: χρόνος κοντά στο πάνω όριο (127 − 7 … 127 + 5)', () {
      expect(talkSeconds(_walk(106), 127).near, 0, reason: 'σταθερά 106: ποτέ κοντά στο 127');
      expect(talkSeconds(_walk(124), 127).near, 1800);
      expect(talkSeconds(_walk(124, pauses: [
        [600, 900],
      ]), 127).near, 1500, reason: 'η παύση δεν μετρά');
      expect(talkSeconds(_walk(140), 127), (near: 0, above: 1800));
    });

    test('S6-3: πρόταση μόνο αν έφτασε κοντά στο όριο, και το πολύ ±10 από τον υπολογισμό', () {
      (int, int)? p(String a, int lo, int hi, {int near = 300, int above = 0, bool base = true}) =>
          talkProposal(answer: a, walkLo: lo, walkHi: hi, baseLo: base ? 104 : null, baseHi: base ? 127 : null, nearSec: near, aboveSec: above);
      expect(p('sing', 104, 127, near: 1500), (109, 132));
      expect(p('sing', 109, 132), (114, 137));
      expect(p('sing', 114, 137), isNull, reason: 'ήδη +10 από τον υπολογισμό');
      expect(p('sing', 104, 127, near: 179), isNull, reason: 'λιγότερο από 3 λεπτά κοντά στο όριο');
      expect(p('talk', 104, 127), isNull);
      expect(p('no', 104, 127, near: 600, above: 100), (99, 122));
      expect(p('no', 104, 127, near: 300, above: 1200), isNull, reason: 'κυρίως πάνω από τη ζώνη: το λαχάνιασμα είναι αναμενόμενο');
      expect(p('no', 99, 122), (94, 117));
      expect(p('no', 94, 117), isNull, reason: 'ήδη −10 από τον υπολογισμό');
      expect(p('sing', 104, 127, base: false), (109, 132));
    });
  });

  group('Οθόνες προπόνησης: καθαρές συναρτήσεις (round1)', () {
    test('U5-27: σύντομο ελληνικό όνομα στην «Η εβδομάδα», όχι ο κωδικός', () {
      Workout w(String id, String name) => Workout(id: id, name: name);
      expect(shortWorkoutName(w('UA', 'Πάνω μέρος Α')), 'ΠΑ');
      expect(shortWorkoutName(w('LB', 'Κάτω μέρος Β')), 'ΚΒ');
      expect(shortWorkoutName(w('B', 'Προπόνηση Β')), 'Β');
      expect(shortWorkoutName(w('legs', 'Πόδια')), 'ΠΟ');
    });

    test('U6-14: άρθρο πριν από τη μέρα', () {
      expect(onDay(DateTime(2026, 11, 16)), 'τη Δευτέρα 16 Νοεμβρίου');
      expect(onDay(DateTime(2026, 11, 12)), 'την Πέμπτη 12 Νοεμβρίου');
      expect(onDay(DateTime(2026, 11, 21)), 'το Σάββατο 21 Νοεμβρίου');
    });

    test('S7-11: οι σημειώσεις του προγράμματος και της προπόνησης', () {
      final p = sampleProgram()..note = 'ΚΑΝΟΝΑΣ-166';
      final w = p.workout('A')!..note = 'ΣΗΜ-Α';
      expect(programNotes(p, w), [('Το πρόγραμμα', 'ΚΑΝΟΝΑΣ-166'), ('Προπόνηση Α', 'ΣΗΜ-Α')]);
      p.note = '  ';
      w.note = null;
      expect(programNotes(p, w), isEmpty);
    });

    test('S6-13: πρωινό περπάτημα σε μέρα βαρών δεν «κλείνει» τη μέρα', () {
      final fri = DateTime(2026, 11, 13, 17, 30); // «A» στο δείγμα
      final t = sampleTraining(fri);
      final walk = Session(
        id: 'w-morning',
        workout: 'walk',
        name: 'Περπάτημα',
        programId: '',
        start: DateTime(2026, 11, 13, 8),
        end: DateTime(2026, 11, 13, 8, 25),
        cardioMinutes: 25,
      );
      t.sessions.add(walk);
      expect(TodayTrainingCard.doneToday(t, fri), isNull);
      expect(TodayTrainingCard.otherToday(t, fri)?.id, 'w-morning');
      expect(TodayTrainingCard.shows(t, fri), isTrue);
    });

    test('U6-02: «Ελεύθερη άσκηση»: η ερώτηση μετά το 1ο σετ αλλάζει το βάρος όπως στο πρόγραμμα', () {
      final now = DateTime(2026, 11, 20, 18);
      final t = sampleTraining(now)..startFree();
      final e = t.addExercise('incline_press')!;
      t.tick(e, 0);
      final first = e.log.first;
      final want = calibrate(PlanItem(ex: e.ex, sets: e.sets, lo: e.lo, hi: e.hi, rir: e.rir, rest: e.rest), first.load, first.reps, 0);
      expect(want, isNotNull, reason: '0 στη ρεζέρβα: ένα σκαλί πιο ελαφριά');
      expect(t.calibrateAfterFirst(e, 0), want);
      expect(e.log[1].load, want);
    });
  });

  group('Οθόνες προπόνησης (round1)', () {
    final now = DateTime(2026, 11, 20, 18, 0);
    setUp(() => ExClock.frozen = true);

    testWidgets('S6-14: ξεχασμένη προπόνηση και στη «Σήμερα»: «Τέλος (στις …)», όχι «Συνέχισε»', (tester) async {
      await tester.runAsync(() => ExLibrary.load(inline: true));
      var at = now;
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => at)..replaceAll(sampleTraining(now).toJson());
      t.ready = true;
      final s = t.start(t.program!.workout('A')!);
      at = now.add(const Duration(minutes: 52));
      t.tick(s.items.first, 0);
      at = now.add(const Duration(hours: 21));
      await _pump(tester, Scaffold(body: SingleChildScrollView(child: TodayTrainingCard(training: t, now: at))));
      expect(find.text('Ξεχασμένη προπόνηση;'), findsOneWidget);
      expect(find.byKey(const ValueKey('today-train-resume')), findsNothing);
      expect(find.textContaining('την Παρασκευή 20 Νοεμβρίου στις 18:00'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('today-forgotten-end')));
      await tester.pumpAndSettle();
      expect(t.current, isNull);
      expect(t.sessions.last.end, now.add(const Duration(minutes: 52)));
    });

    testWidgets('U6-01: «Σβήσιμο» ξεχασμένης προπόνησης χωρίς σετ ρωτά πρώτα', (tester) async {
      await tester.runAsync(() => ExLibrary.load(inline: true));
      var at = now;
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => at)..replaceAll(sampleTraining(now).toJson());
      t.ready = true;
      t.start(t.program!.workout('A')!);
      at = now.add(const Duration(hours: 21));
      await _pump(tester, Scaffold(body: TrainingPage(training: t, now: at)));
      expect(find.text('Ξεχασμένη προπόνηση;'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('train-forgotten-drop')));
      await tester.pumpAndSettle();
      expect(t.current, isNotNull, reason: 'ένα πάτημα δεν σβήνει τίποτα');
      await tester.tap(find.byKey(const ValueKey('train-forgotten-drop-ok')));
      await tester.pumpAndSettle();
      expect(t.current, isNull);
    });

    testWidgets('S7-21: ⓘ δίπλα στο «άφησε» πριν από το 1ο σετ', (tester) async {
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final t = sampleTraining(now);
      t.start(t.program!.workout('A')!);
      await _pump(tester, SessionPage(training: t));
      expect(find.byKey(const ValueKey('rir-info')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('rir-info')));
      await tester.pumpAndSettle();
      expect(find.textContaining('θα έβγαζες ακόμα'), findsOneWidget);
    });

    testWidgets('U5-08: όλες οι ασκήσεις έγιναν με άλλη σειρά → «Τέλος προπόνησης»', (tester) async {
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final t = sampleTraining(now);
      final s = t.start(t.program!.workout('A')!);
      for (final e in s.items) {
        for (var i = 0; i < e.log.length; i++) {
          t.tick(e, i);
        }
      }
      await _pump(tester, SessionPage(training: t));
      await tester.tap(find.byKey(const ValueKey('sess-ex-0')));
      await tester.pumpAndSettle();
      expect(find.text('Τέλος προπόνησης'), findsOneWidget);
      expect(find.text('Επόμενη άσκηση'), findsNothing);
    });

    testWidgets('U6-27: «πίσω» από άδεια «Ελεύθερη άσκηση» δεν αφήνει ανοιχτή προπόνηση', (tester) async {
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final t = sampleTraining(now)..startFree();
      await _pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: FilledButton(key: const ValueKey('open'), onPressed: () => Navigator.of(context).push(SessionPage.route(t)), child: const Text('άνοιγμα')),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('free-empty')), findsOneWidget);
      Navigator.of(tester.element(find.byKey(const ValueKey('free-empty')))).pop();
      await tester.pumpAndSettle();
      expect(t.current, isNull);
    });

    testWidgets('U5-16 / U5-19: σύνοψη: βέλος μόνο όταν οι παλμοί πέφτουν, και η ενόχληση γραμμένη', (tester) async {
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final start = now.subtract(const Duration(days: 1));
      final s = Session(
        id: 'p1',
        workout: 'A',
        name: 'Προπόνηση Α',
        programId: 'p',
        start: start,
        end: start.add(const Duration(minutes: 10)),
        // Παλμοί που ανεβαίνουν συνέχεια: το «διάλειμμα» (πριν το 2ο σετ) είναι ΠΙΟ ΨΗΛΑ από το σετ.
        hr: [for (var x = 0; x <= 400; x++) [x, 90 + x ~/ 4]],
        items: [
          ExLog(ex: 'db_press', sets: 2, lo: 8, hi: 12, rir: 2, rest: 120, pain: ['elbow'], log: [
            SetLog(load: 10.3, reps: 8, done: true, at: start.millisecondsSinceEpoch + 60 * 1000),
            SetLog(load: 10.3, reps: 8, done: true, at: start.millisecondsSinceEpoch + 300 * 1000),
          ]),
        ],
      );
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => now)..ready = true;
      t.sessions.add(s);
      await _pump(tester, SummaryPage(training: t, session: s));
      expect(find.textContaining('↓'), findsNothing);
      expect(find.byKey(const ValueKey('sum-pain-db_press')), findsOneWidget);
      expect(find.textContaining('Ενόχληση: αγκώνας'), findsOneWidget);
    });
  });
}
