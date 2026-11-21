// Βαθύς έλεγχος 20/11/2026, κατηγορία 4 (άσκηση, πρόοδος φορτίου, ρολόι): οι διορθώσεις των K4-science και K4-calc.
// Επινοημένα δεδομένα. Κάθε δοκιμή γράφει τι έβγαινε ΠΡΙΝ.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/exercise/ex_data.dart';
import 'package:ygeia_forma/pages/training/program_paste.dart';
import 'package:ygeia_forma/pages/training/progress_page.dart';
import 'package:ygeia_forma/pages/training/session_page.dart';
import 'package:ygeia_forma/pages/training/training_common.dart';
import 'package:ygeia_forma/pages/training/zone_widgets.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/training/equipment.dart';
import 'package:ygeia_forma/training/progress.dart';
import 'package:ygeia_forma/training/program.dart';
import 'package:ygeia_forma/training/progression.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/training_store.dart';
import 'package:ygeia_forma/trends.dart';
import 'package:ygeia_forma/widgets.dart';

import 'training_sample.dart';

final _now = DateTime(2026, 12, 31, 20);

DateTime _ago(int days) => DateTime(_now.year, _now.month, _now.day - days, 18);

ExLog _log(String ex, double? load, List<int> reps,
        {int? rir, int? first, int lo = 8, int hi = 12, List<String> pain = const [], bool skipped = false, bool done = true, int? at}) =>
    ExLog(
      ex: ex,
      sets: reps.length,
      lo: lo,
      hi: hi,
      rir: 2,
      rest: 90,
      rirAnswer: rir,
      firstAnswer: first,
      pain: List.of(pain),
      skipped: skipped,
      log: [for (var i = 0; i < reps.length; i++) SetLog(load: load, reps: reps[i], done: done, at: at == null ? null : at + i * 1000)],
    );

Session _lift(int daysAgo, List<ExLog> items, {String? source}) {
  final start = _ago(daysAgo);
  return Session(
      id: 's$daysAgo', workout: 'A', name: 'Προπόνηση Α', programId: 'p', start: start, end: start.add(const Duration(minutes: 50)), items: items, source: source);
}

TrainingStore _store(List<Session> s) {
  final t = TrainingStore(io: MemoryTrainingIO(), clock: () => _now);
  t.replaceAll({'v': 1, 'sessions': [for (final x in s) x.toJson()]});
  t.ready = true;
  return t;
}

PlanItem _item(String ex, {int lo = 8, int hi = 12, double? load}) => PlanItem(ex: ex, sets: 3, lo: lo, hi: hi, rir: 2, rest: 90, load: load);

String _prog({String days = '"mon":"A"', required String items}) =>
    '{"kind":"ygeia-program","v":1,"id":"p1","name":"Πρόγραμμα","author":"claude","days":{$days},'
    '"workouts":[{"id":"A","name":"Προπόνηση Α","items":[$items]},{"id":"B","name":"Προπόνηση Β","items":[{"ex":"goblet","sets":2,"reps":[10,15],"rir":3,"rest":90}]}]}';

String _ex(String id, {String extra = ''}) => '{"ex":"$id","sets":3,"reps":[8,12],"rir":2,"rest":90$extra}';

void main() {
  setUp(() => equip = Equipment.standard);
  tearDown(() => equip = Equipment.standard);
  final known = exerciseLoad.keys.toSet();

  // ------------------------------------------------------------------ K4C-01 (κρίσιμο)
  group('K4C-01: μετά από ενόχληση η ερώτηση του 1ου σετ δεν ξαναγίνεται', () {
    final easy = _lift(5, [_log('db_press', 9.3, [10, 10, 10], rir: 4, first: 4)]);
    final painNoSets = _lift(2, [_log('db_press', 9.3, [8, 8, 8], pain: const ['shoulderR'], skipped: true, done: false)]);

    test('χωρίς την ενόχληση: η άνετη φορά ξαναρωτά (όπως πριν)', () {
      expect(_store([easy]).stillCalibrating('db_press'), isTrue);
    });

    test('ενόχληση σε προπόνηση χωρίς κανένα σετ (πριν: ξαναρωτούσε και ανέβαζε στο φορτίο του πόνου)', () {
      final t = _store([easy, painNoSets]);
      expect(t.stillCalibrating('db_press'), isFalse);
      expect(t.isFirstTime('db_press'), isFalse);
      final tg = nextTarget(_item('db_press'), t.historyOf('db_press'), _now);
      expect(tg.change, Change.pain);
      expect(tg.load, 7.8);
    });

    test('ενόχληση με σετ: όχι (όπως πριν)', () {
      final t = _store([easy, _lift(2, [_log('db_press', 9.3, [8, 8, 8], pain: const ['shoulderR'])])]);
      expect(t.stillCalibrating('db_press'), isFalse);
    });

    test('ενόχληση πριν από 100 μέρες χωρίς σετ: ούτε τότε (ο στόχος βγαίνει από τον κανόνα της ενόχλησης)', () {
      final t = _store([
        _lift(105, [_log('db_press', 9.3, [10, 10, 10], rir: 4, first: 4)]),
        _lift(100, [_log('db_press', 9.3, [8, 8, 8], pain: const ['shoulderR'], skipped: true, done: false)]),
      ]);
      expect(t.stillCalibrating('db_press'), isFalse);
    });

    test('η φορά ΜΕΤΑ την ενόχληση, χωρίς πόνο: κανονικοί κανόνες (διακοπή πάνω από 90 μέρες ξαναρωτά)', () {
      final t = _store([
        _lift(130, [_log('db_press', 9.3, [8, 8, 8], pain: const ['shoulderR'], skipped: true, done: false)]),
        _lift(120, [_log('db_press', 7.8, [8, 8, 8], rir: 2)]),
      ]);
      expect(t.stillCalibrating('db_press'), isTrue);
    });
  });

  // ------------------------------------------------------------------ K4-R-01 (ανεξάρτητος έλεγχος)
  group('K4-R-01: ενόχληση γραμμένη ΣΗΜΕΡΑ → τα επόμενα σετ δεν γίνονται ποτέ βαρύτερα', () {
    final t0 = DateTime(2026, 11, 20, 17, 30);

    test('χωρίς ενόχληση: 1ο σετ «8–12» → τα επόμενα σετ βαρύτερα (όπως πριν)', () {
      final t = sampleTraining(t0, history: false);
      final e = t.start(t.program!.workout('A')!).items.first;
      t.tick(e, 0);
      expect(t.answerFirst(e, 10).load, 10.3);
      expect(e.log[1].load, 10.3);
    });

    test('ενόχληση πριν από το ✓ του 1ου σετ, απάντηση «8–12»: το βάρος μένει, και το λέει (πριν: 10,3 kg)', () {
      final t = sampleTraining(t0, history: false);
      final e = t.start(t.program!.workout('A')!).items.first;
      t.togglePain(e, 'shoulderR');
      expect(t.painToday('db_press'), isTrue);
      t.tick(e, 0);
      final r = t.answerFirst(e, 10);
      expect(r.applied, isTrue);
      expect(r.load, isNull);
      expect([for (final x in e.log) x.load], [9.3, 9.3, 9.3]);
      expect(t.firstSetNote(e, 10), TrainingStore.firstSetPainNote);
    });

    test('ενόχληση και απάντηση «0»: πιο ελαφριά, όπως πριν', () {
      final t = sampleTraining(t0, history: false);
      final e = t.start(t.program!.workout('A')!).items.first;
      t.togglePain(e, 'shoulderR');
      t.tick(e, 0);
      expect(t.answerFirst(e, 0).load, 7.8);
      expect(e.log[1].load, 7.8);
    });

    test('ενόχληση → «Αλλαγή άσκησης» → πίσω στην αρχική: ο στόχος είναι πιο ελαφρύς (πριν: ίδιος με πριν από τον πόνο)', () {
      final t = sampleTraining(t0);
      final s = t.start(t.program!.workout('A')!);
      final e = s.items.first;
      expect(e.ex, 'db_press');
      final before = e.log.first.load!;
      t.togglePain(e, 'shoulderR');
      t.swap(e, 'incline_press');
      expect(s.items.first.ex, 'incline_press');
      t.swap(s.items.first, 'db_press');
      final back = s.items.first;
      expect(back.ex, 'db_press');
      expect(back.log.first.load, lessThan(before));
      expect(back.reason, contains('ενόχληση'));
      expect(t.painToday('db_press'), isTrue);
    });

    // K4-R-03 (παλινδρόμηση που έπιασε ο ανεξάρτητος έλεγχος στην πρώτη μορφή της διόρθωσης).
    test('ΧΩΡΙΣ ενόχληση: «Αλλαγή άσκησης» και πίσω → ο στόχος της μέρας, όχι της επόμενης φοράς', () {
      final t = sampleTraining(t0);
      final s = t.start(t.program!.workout('A')!);
      final e = s.items.first;
      final before = e.log.first.load!;
      final reps = [for (final x in e.log) x.reps];
      for (var i = 0; i < e.log.length; i++) {
        t.tick(e, i);
      }
      e.rirAnswer = 3;
      t.swap(e, 'incline_press');
      t.swap(s.items.first, 'db_press');
      final back = s.items.first;
      expect(back.ex, 'db_press');
      expect(back.log.first.load, before);
      expect([for (final x in back.log) x.reps], reps);
      expect(t.painToday('db_press'), isFalse);
    });

    // K4-R-10: «0–1» στο 1ο σετ με το ελαφρύτερο φορτίο που υπάρχει (σκέτη μπάρα).
    test('1ο σετ «0» με σκέτη μπάρα (10 kg): δεν υπάρχει πιο ελαφρύ → τα επόμενα σετ 2 επαναλήψεις λιγότερες, και το λέει', () {
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => t0)..ready = true;
      t.saveProgram(parseProgram(_prog(items: _ex('rdl', extra: ',"load":10')), exerciseLoad.keys.toSet()).program!, author: 'claude');
      final e = t.start(t.program!.workout('A')!).items.first;
      expect(e.log.first.load, 10);
      t.tick(e, 0);
      final r = t.answerFirst(e, 0);
      expect(r.applied, isTrue);
      expect(r.load, isNull);
      expect([for (final x in e.log) x.reps], [8, 6, 6]);
      expect([for (final x in e.log) x.load], [10, 10, 10]);
      expect(t.firstSetNote(e, 0), TrainingStore.firstSetNoLighterNote);
    });
  });

  // ------------------------------------------------------------------ K4C-06
  group('K4C-06: ένα ✓ με 0 επαναλήψεις δεν είναι «φορά» της άσκησης', () {
    test('πρώτη προπόνηση με ένα ✓ × 0: μένει «πρώτη φορά» και ο στόχος είναι το ξεκίνημα', () {
      final t = _store([_lift(3, [_log('db_press', 4.3, [0])])]);
      expect(t.isFirstTime('db_press'), isTrue);
      expect(nextTarget(_item('db_press'), t.historyOf('db_press'), _now).change, Change.first);
    });

    test('με κανονικό σετ: όχι πρώτη φορά', () {
      final t = _store([_lift(3, [_log('db_press', 4.3, [10])])]);
      expect(t.isFirstTime('db_press'), isFalse);
    });
  });

  // ------------------------------------------------------------------ K4C-02
  group('K4C-02: «πιο ελαφριά» είναι πραγματικά πιο ελαφριά και στη μπάρα', () {
    test('lighterStep: μπάρα και κέρατο περίπου −10%, αλτήρες και kettlebell όπως πριν', () {
      expect(stepDown(LoadKind.bar, 30), 29.5, reason: 'το παλιό «ένα σκαλί»');
      final bar = lighterStep(LoadKind.bar, 30)!;
      expect(bar, lessThanOrEqualTo(27.0));
      expect(bar, greaterThanOrEqualTo(24.0));
      final horn = lighterStep(LoadKind.horn, 10)!;
      expect(horn, lessThanOrEqualTo(9.0));
      expect(horn, greaterThanOrEqualTo(8.0));
      for (final v in [5.3, 6.8, 7.8, 9.3, 10.3, 11.8, 14.3]) {
        expect(lighterStep(LoadKind.dbPair, v), stepDown(LoadKind.dbPair, v), reason: 'αλτήρες $v');
      }
      for (final v in available(LoadKind.kb)) {
        expect(lighterStep(LoadKind.kb, v), stepDown(LoadKind.kb, v), reason: 'kettlebell $v');
      }
      for (final v in available(LoadKind.band)) {
        expect(lighterStep(LoadKind.band, v), stepDown(LoadKind.band, v), reason: 'λάστιχο $v');
      }
    });

    test('lighterStep: πάντα διαθέσιμο βάρος, πάντα ελαφρύτερο, ποτέ κάτω από το 80% όταν υπάρχει ενδιάμεσο', () {
      for (final k in [LoadKind.bar, LoadKind.horn, LoadKind.plate, LoadKind.dbPair, LoadKind.db, LoadKind.kb]) {
        final a = available(k);
        for (final v in a) {
          final d = lighterStep(k, v, allowZero: k == LoadKind.plate);
          final one = stepDown(k, v, allowZero: k == LoadKind.plate);
          expect(d == null, one == null, reason: '$k $v');
          if (d == null) continue;
          expect(a.contains(d), isTrue, reason: '$k $v → $d');
          expect(d, lessThan(v), reason: '$k $v');
          expect(d, lessThanOrEqualTo(one!), reason: '$k $v');
          if (d < one) expect(d, greaterThanOrEqualTo(v * lighterFloor - 1e-6), reason: '$k $v → $d');
        }
      }
    });

    test('χωρίς δίσκους δεν υπάρχει ελαφρύτερο από τη λαβή: null (τότε «ίδια κιλά με 2 επαναλήψεις λιγότερες»)', () {
      equip = const Equipment(handleKg: 1.8, handles: 2, counts: [0, 0, 0, 0]);
      expect(lighterStep(LoadKind.dbPair, 1.8), isNull);
    });

    test('Romanian deadlift 30 kg με ενόχληση στη μέση → ως 27 kg (πριν 29,5 kg), «πιο ελαφριά»', () {
      final t = nextTarget(_item('rdl'), [(_ago(3), _log('rdl', 30, [10, 10, 10], rir: 2, pain: const ['back']))], _now);
      expect(t.change, Change.pain);
      expect(t.load, lessThanOrEqualTo(27.0));
      expect(t.reason, contains('πιο ελαφριά'));
      expect(t.reason, isNot(contains('ένα σκαλί')));
    });

    test('leg curl 10 kg με ενόχληση → ως 9 kg (πριν 9,75 kg)', () {
      final t = nextTarget(_item('leg_curl', lo: 10, hi: 15), [(_ago(3), _log('leg_curl', 10, [10, 10, 10], rir: 2, lo: 10, hi: 15, pain: const ['knee']))], _now);
      expect(t.change, Change.pain);
      expect(t.load, lessThanOrEqualTo(9.0));
    });

    test('πιεστικό με αλτήρες 9,3 kg με ενόχληση → 7,8 kg, «ένα σκαλί πιο ελαφριά» (όπως πριν)', () {
      final t = nextTarget(_item('db_press'), [(_ago(3), _log('db_press', 9.3, [10, 10, 10], rir: 2, pain: const ['shoulderR']))], _now);
      expect(t.load, 7.8);
      expect(t.reason, contains('ένα σκαλί πιο ελαφριά, 7,8 kg'));
    });

    test('«δεν άφησες καμία και δεν βγήκαν οι 8» στη μπάρα: ως 27 kg (πριν 29,5 kg)', () {
      final t = nextTarget(_item('rdl'), [(_ago(3), _log('rdl', 30, [6, 5, 5], rir: 0))], _now);
      expect(t.change, Change.down);
      expect(t.load, lessThanOrEqualTo(27.0));
    });

    test('δύο φορές κάτω από το εύρος στη μπάρα: ως 27 kg', () {
      final h = [(_ago(3), _log('rdl', 30, [8, 7, 6])), (_ago(6), _log('rdl', 30, [8, 7, 7]))];
      final t = nextTarget(_item('rdl'), h, _now);
      expect(t.change, Change.down);
      expect(t.load, lessThanOrEqualTo(27.0));
    });

    test('1ο σετ πρώτης φοράς με «0–1» στη μπάρα: τα επόμενα σετ ως 27 kg (πριν 29,5 kg)', () {
      expect(calibrate(_item('rdl'), 30, 8, 0), lessThanOrEqualTo(27.0));
      expect(calibrate(_item('db_press'), 9.3, 8, 0), 7.8);
    });
  });

  // ------------------------------------------------------------------ K4-S-08, K4C-03, ενόχληση + διακοπή
  group('διακοπή: K4-S-08 (μήνες), K4C-03 (άλλος εξοπλισμός), ενόχληση μαζί με διακοπή', () {
    test('breakRatio: 15–28 μέρες 0,9 · 29–90 0,8 · 91–180 0,7 · πάνω από 180 0,6', () {
      expect([15, 28, 29, 90, 91, 180, 181, 400].map(breakRatio).toList(), [0.9, 0.9, 0.8, 0.8, 0.7, 0.7, 0.6, 0.6]);
    });

    test('πιεστικό 14,3 kg: 30 μέρες → 10,3 kg (όπως πριν)· 100 μέρες → 9,3 kg· 200 μέρες → ως 9,3 kg (πριν 10,3 kg)', () {
      double? after(int days) => nextTarget(_item('db_press'), [(_ago(days), _log('db_press', 14.3, [12, 12, 12], rir: 2))], _now).load;
      expect(after(30), 10.3);
      expect(after(100), 9.3);
      expect(after(200), lessThanOrEqualTo(9.3));
      expect(after(200), greaterThanOrEqualTo(4.3), reason: 'ποτέ κάτω από το ελαφρύ ξεκίνημα');
    });

    test('K4C-03: με λαβή 2,2 kg ο στόχος μετά από διακοπή είναι βάρος που φτιάχνεται (πριν 4,3 kg, που δεν βγαίνει)', () {
      equip = const Equipment(handleKg: 2.2);
      final a = available(LoadKind.dbPair);
      final last = a.firstWhere((x) => x > 4.3);
      final t = nextTarget(_item('db_press'), [(_ago(20), _log('db_press', last, [12, 12, 12], rir: 2))], _now);
      expect(a.contains(t.load), isTrue, reason: '${t.load} δεν βγαίνει με λαβή 2,2 kg');
      expect(t.load, lessThanOrEqualTo(last));
    });

    // K4-R-09: στο λάστιχο βοήθειας η αναλογία δεν ισχύει· μετά από πάνω από 90 μέρες, δύο λάστιχα περισσότερη βοήθεια.
    test('έλξεις με λάστιχο βοήθειας 20 lb: 20 μέρες → 30 lb· 200 μέρες → 40 lb (πριν 30 lb)', () {
      double? after(int days) =>
          nextTarget(_item('assisted_pullup'), [(_ago(days), _log('assisted_pullup', 20, [8, 8, 8], rir: 2))], _now).load;
      expect(after(20), 30);
      expect(after(200), 40);
    });

    test('ενόχληση ΚΑΙ 40 μέρες διακοπή: το ελαφρύτερο από τα δύο (πριν μόνο ένα σκαλί)', () {
      final t = nextTarget(_item('db_press'), [(_ago(40), _log('db_press', 14.3, [10, 10, 10], rir: 2, pain: const ['shoulderR']))], _now);
      expect(t.change, Change.pain);
      expect(t.load, 10.3);
    });
  });

  // ------------------------------------------------------------------ K4C-07
  group('K4C-07: «το βαρύτερο δοκιμάστηκε και γύρισες πίσω» μόνο όταν ΔΕΝ βγήκε', () {
    List<(DateTime, ExLog)> hist(ExLog heavier) => [
          (_ago(3), _log('db_press', 7.8, [9, 9, 9], rir: 4)),
          (_ago(6), _log('db_press', 7.8, [8, 8, 8], rir: 4)),
          (_ago(30), heavier),
        ];

    test('γύρισε πίσω η εφαρμογή μετά από διακοπή (9,3 kg είχαν βγει): η συμβουλή «ανέβασε με το +» φαίνεται (πριν: ποτέ)', () {
      final t = nextTarget(_item('db_press'), hist(_log('db_press', 9.3, [12, 12, 12], rir: 3)), _now);
      expect(t.change, Change.more);
      expect(t.reason, contains('Αν είναι πολύ ελαφρύ'));
    });

    test('τα 9,3 kg δεν είχαν βγει (κάτω από το εύρος): καμία συμβουλή (όπως πριν)', () {
      final t = nextTarget(_item('db_press'), hist(_log('db_press', 9.3, [7, 6, 6], rir: 2)), _now);
      expect(t.reason, isNot(contains('Αν είναι πολύ ελαφρύ')));
    });

    test('τα 9,3 kg με «άφησα 0»: καμία συμβουλή', () {
      final t = nextTarget(_item('db_press'), hist(_log('db_press', 9.3, [8, 8, 8], rir: 0)), _now);
      expect(t.reason, isNot(contains('Αν είναι πολύ ελαφρύ')));
    });

    // K4-R-02 (ανεξάρτητος έλεγχος): πριν, η ενόχληση χωρίς κανένα σετ δεν μετρούσε εδώ.
    test('ενόχληση στα 9,3 kg ΧΩΡΙΣ κανένα σετ, μετά άνετη φορά στα 7,8 kg: καμία συμβουλή «ανέβασε» προς το φορτίο του πόνου', () {
      final h = [
        (_ago(3), _log('db_press', 7.8, [9, 9, 9], rir: 4)),
        (_ago(6), _log('db_press', 9.3, [8, 8, 8], pain: const ['shoulderR'], skipped: true, done: false)),
        (_ago(9), _log('db_press', 9.3, [10, 10, 10], rir: 4, first: 4)),
      ];
      final t = nextTarget(_item('db_press'), h, _now);
      expect(t.change, Change.more);
      expect(t.load, 7.8);
      expect(t.reason, isNot(contains('Αν είναι πολύ ελαφρύ')));
      expect(t.reason, isNot(contains('Άφησες 4+ και τις δύο')));
      // Έλεγχος της δοκιμής: χωρίς την καταγραφή της ενόχλησης η συμβουλή βγαίνει.
      expect(nextTarget(_item('db_press'), [h[0], h[2]], _now).reason, contains('Αν είναι πολύ ελαφρύ'));
    });

    // K4-R-11: στη μπάρα το «ένα σκαλί πάνω» προσπερνά φορτία (29,5 → 31 kg)· μια φορά που δεν βγήκε στα 30 kg μετρά.
    test('μπάρα: δεν βγήκαν στα 30 kg, τώρα 29,5 kg με δύο «4+»: καμία συμβουλή «ανέβασε εσύ» προς τα 31 kg', () {
      final h = [
        (_ago(3), _log('rdl', 29.5, [9, 9, 9], rir: 4)),
        (_ago(6), _log('rdl', 29.5, [8, 8, 8], rir: 4)),
        (_ago(30), _log('rdl', 30, [7, 6, 6], rir: 2)),
      ];
      final t = nextTarget(_item('rdl'), h, _now);
      expect(t.load, 29.5);
      expect(t.reason, isNot(contains('Άφησες 4+ και τις δύο')));
    });

    test('ενόχληση ΜΕ σετ στα 9,3 kg: το ίδιο (όπως πριν)', () {
      final h = [
        (_ago(3), _log('db_press', 7.8, [9, 9, 9], rir: 4)),
        (_ago(6), _log('db_press', 9.3, [9, 8, 8], rir: 2, pain: const ['shoulderR'])),
      ];
      expect(nextTarget(_item('db_press'), h, _now).reason, isNot(contains('Αν είναι πολύ ελαφρύ')));
    });
  });

  // ------------------------------------------------------------------ K4-S-07
  test('K4-S-07: κάθε άνοδος φορτίου λέει ότι η ρεζέρβα μετράει περισσότερο από τον αριθμό', () {
    final t = nextTarget(_item('db_press'), [(_ago(3), _log('db_press', 9.3, [12, 12, 12], rir: 2))], _now);
    expect(t.change, Change.up);
    expect(t.reason, contains('σταμάτα νωρίτερα'));
    expect(calibrateUpNote(3), startsWith('Αν δεν βγαίνουν αφήνοντας 3, σταμάτα νωρίτερα'));
  });

  // ------------------------------------------------------------------ K4C-05, K4C-12
  group('K4C-05 / K4C-12: λάστιχο βοήθειας και κείμενο δίσκου', () {
    test('λάστιχο βοήθειας: 45 → 50 (περισσότερη βοήθεια· πριν 40), 0 → 0 (πριν «κίτρινο, 10 lb»)', () {
      expect(snap(LoadKind.bandAssist, 45), 50);
      expect(snap(LoadKind.bandAssist, 0), 0);
      expect(snap(LoadKind.bandAssist, 40), 40);
      expect(snap(LoadKind.band, 45), 40, reason: 'το λάστιχο αντίστασης μένει προς τα κάτω');
    });

    test('επικόλληση με «χωρίς βοήθεια» (0): καμία προειδοποίηση', () {
      final r = parseProgram(_prog(items: _ex('assisted_pullup', extra: ',"load":0')), known);
      expect(r.errors, isEmpty);
      expect(r.warnings.where((w) => w.contains('λάστιχ')), isEmpty);
    });

    test('ο δίσκος στο στήθος δεν έχει «άκρες»', () {
      expect(plateChange(LoadKind.plate, 5, LoadKind.plate, 7.5), isNot(contains('άκρη')));
      expect(plateChange(LoadKind.dbPair, 11.8, LoadKind.db, 14.3), 'βάλε 1,25 σε κάθε άκρη');
    });
  });

  // ------------------------------------------------------------------ K4C-13
  group('K4C-13: η ίδια άσκηση δύο φορές σε μία προπόνηση', () {
    test('ενόχληση → αλλαγή → πίσω στην αρχική με 12, 12, 12: ο κανόνας της ενόχλησης ισχύει (πριν «ανέβα σε 10,3 kg»)', () {
      final t = _store([
        _lift(3, [
          _log('db_press', 9.3, [12, 12, 12], rir: 2, at: 2000000),
          _log('db_row', 9.3, [10, 10, 10], rir: 2, at: 1500000),
          _log('db_press', 9.3, [9], pain: const ['shoulderR'], at: 1000000),
        ]),
      ]);
      final h = t.historyOf('db_press');
      expect(h.first.$2.pain, isNotEmpty);
      final tg = nextTarget(_item('db_press'), h, _now);
      expect(tg.change, Change.pain);
      expect(tg.load, 7.8);
    });

    test('χωρίς ενόχληση: πρώτη η καταγραφή με το πιο πρόσφατο ✓ (πριν: όποια ήταν πιο πάνω στη λίστα)', () {
      final t = _store([
        _lift(3, [
          _log('db_press', 9.3, [12, 12, 12], rir: 4, at: 1000000),
          _log('db_press', 9.3, [8, 7, 6], rir: 1, at: 2000000),
        ]),
      ]);
      expect([for (final s in t.historyOf('db_press').first.$2.log) s.reps], [8, 7, 6]);
    });

    test('μία καταγραφή ανά προπόνηση: η σειρά δεν αλλάζει (νεότερη προπόνηση πρώτη)', () {
      final t = _store([_lift(6, [_log('db_press', 7.8, [8, 8, 8])]), _lift(3, [_log('db_press', 9.3, [9, 9, 9])])]);
      expect([for (final h in t.historyOf('db_press')) h.$2.log.first.load], [9.3, 7.8]);
    });
  });

  // ------------------------------------------------------------------ K4C-14
  group('K4C-14: επικόλληση προγράμματος', () {
    List<String> errs(String text) => parseProgram(text, known).errors;

    test('σωστό πρόγραμμα: κανένα λάθος', () {
      expect(errs(_prog(items: '${_ex('db_press', extra: ',"load":9.3')},${_ex('db_row')}')), isEmpty);
    });

    test('βάρος πάνω από το μεγαλύτερο που βγαίνει («93» αντί για «9.3»): λάθος (πριν γινόταν 20,3 kg με γκρι σημείωση)', () {
      final e = errs(_prog(items: _ex('db_press', extra: ',"load":93')));
      expect(e.single, contains('είναι πάνω από το μεγαλύτερο που βγαίνει'));
    });

    test('βάρος ανάμεσα σε δύο διαθέσιμα: στρογγύλεμα με σημείωση, όχι λάθος (όπως πριν)', () {
      final r = parseProgram(_prog(items: _ex('db_press', extra: ',"load":10')), known);
      expect(r.errors, isEmpty);
      expect(r.warnings.single, contains('9,3'));
    });

    test('η ίδια άσκηση δύο φορές στην ίδια προπόνηση: λάθος', () {
      expect(errs(_prog(items: '${_ex('db_press')},${_ex('db_row')},${_ex('db_press')}')).single, contains('δύο φορές'));
    });

    test('η ίδια μέρα δύο φορές με άλλη προπόνηση («mon» και «1»): λάθος (πριν κέρδιζε σιωπηλά η τελευταία)', () {
      expect(errs(_prog(days: '"mon":"A","1":"B"', items: _ex('db_press'))).single, startsWith('Η Δευτέρα γράφτηκε δύο φορές'));
      expect(errs(_prog(days: '"mon":"A","1":"A"', items: _ex('db_press'))), isEmpty, reason: 'ίδια προπόνηση δύο φορές: δεν πειράζει');
    });
  });

  // ------------------------------------------------------------------ K4C-15
  testWidgets('K4C-15: η επικόλληση δείχνει το βάρος που θα γίνει («συνεχίζεις από 9,3 kg»), όχι το «load» του προγράμματος', (tester) async {
    await tester.runAsync(() => ExLibrary.load(inline: true));
    final t = _store([_lift(3, [_log('db_press', 9.3, [11, 10, 10], rir: 2)])]);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 2400);
    addTearDown(tester.view.reset);
    // Νέο πρόγραμμα με πιο ελαφρύ «load» (6,8 kg) για άσκηση που έχει ήδη γίνει με 9,3 kg, και για μία που δεν έχει γίνει ποτέ.
    final text = _prog(items: '${_ex('db_press', extra: ',"load":6.8')},${_ex('db_row', extra: ',"load":6.8')}');
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: ProgramPastePage(training: t, initial: text)));
    await tester.pump();
    expect(find.textContaining('συνεχίζεις από 9,3 kg'), findsOneWidget);
    expect(find.byKey(const ValueKey('paste-continues')), findsOneWidget);
    expect(find.textContaining('6,8 kg'), findsOneWidget, reason: 'η κωπηλασία δεν έχει γίνει ποτέ: ισχύει το βάρος του προγράμματος');
  });

  // ------------------------------------------------------------------ Α15 (απόφαση χρήστη 21/11)
  group('Α15 (απόφαση 21/11): νέο πρόγραμμα με πιο ελαφριά κιλά από την τελευταία φορά ισχύει· ψηλότερα ποτέ μόνα τους', () {
    final lastDay = _ago(3);
    final hist = [(lastDay, _log('db_press', 9.3, [11, 10, 10], rir: 2))];
    int ms(DateTime d) => d.millisecondsSinceEpoch;
    Program prog(String items) => Program.fromJson(jsonDecode(_prog(items: items)) as Map<String, dynamic>);
    PlanItem pressOf(Program p) => p.workout('A')!.items.firstWhere((i) => i.ex == 'db_press');

    test('nextTarget: φορτίο που γράφτηκε ΜΕΤΑ την τελευταία φορά και είναι πιο ελαφρύ → ισχύει του προγράμματος', () {
      final plain = nextTarget(_item('db_press', load: 6.8), hist, _now);
      expect(plain.load, 9.3, reason: 'χωρίς σημείωση (παλιό πρόγραμμα): όπως πριν, από την τελευταία φορά');
      final lighter = nextTarget(_item('db_press', load: 6.8)..loadAt = ms(_now), hist, _now);
      expect((lighter.load, lighter.change, lighter.reps), (6.8, Change.back, [8, 8, 8]));
      expect(lighter.reason, startsWith('Το νέο σου πρόγραμμα γράφει πιο ελαφριά: 6,8 kg αντί για 9,3 kg'));
      // Φορτίο που γράφτηκε ΠΡΙΝ από την τελευταία φορά (το έχεις ήδη περάσει): όπως πριν.
      final old = nextTarget(_item('db_press', load: 6.8)..loadAt = ms(_ago(10)), hist, _now);
      expect((old.load, old.change, old.reason), (plain.load, plain.change, plain.reason));
      // Μία φορά με το νέο φορτίο και μετά η πρόοδος συνεχίζει από εκεί.
      final after = nextTarget(_item('db_press', load: 6.8)..loadAt = ms(_ago(2)),
          [(_ago(1), _log('db_press', 6.8, [8, 8, 8], rir: 3)), ...hist], _now);
      expect(after.load, 6.8);
      expect(after.change, isNot(Change.back));
      // Ψηλότερο φορτίο προγράμματος: ποτέ μόνο του.
      final higher = nextTarget(_item('db_press', load: 11.8)..loadAt = ms(_now), hist, _now);
      final higherPlain = nextTarget(_item('db_press', load: 11.8), hist, _now);
      expect((higher.load, higher.change, higher.reason), (higherPlain.load, higherPlain.change, higherPlain.reason));
      expect(higher.load, 9.3);
      // Πρώτη φορά της άσκησης: το φορτίο του προγράμματος, όπως πάντα.
      final first = nextTarget(_item('db_press', load: 6.8)..loadAt = ms(_now), const [], _now);
      expect((first.load, first.change), (6.8, Change.first));
    });

    test('μετά από ενόχληση: ο στόχος της ενόχλησης μένει, με το ακόμα πιο ελαφρύ φορτίο του προγράμματος', () {
      final pain = [(lastDay, _log('db_press', 9.3, [10, 10, 10], rir: 2, pain: ['shoulderR']))];
      final plain = nextTarget(_item('db_press', load: 4.3), pain, _now);
      expect(plain.change, Change.pain);
      expect(plain.load, greaterThan(4.3));
      final t = nextTarget(_item('db_press', load: 4.3)..loadAt = ms(_now), pain, _now);
      expect((t.load, t.change, t.reps), (4.3, Change.pain, plain.reps));
      expect(t.reason, startsWith(plain.reason));
      expect(t.reason, endsWith('Το νέο σου πρόγραμμα γράφει ακόμα πιο ελαφριά (4,3 kg): ισχύει αυτό.'));
    });

    test('stampLoadTimes: σημειώνεται μόνο φορτίο διαφορετικό από του προγράμματος που ίσχυε', () {
      final at = DateTime(2026, 12, 31, 20);
      final old = prog('${_ex('db_press', extra: ',"load":9.3')},${_ex('db_row', extra: ',"load":6.8')}');
      // Χωρίς παλιό πρόγραμμα: τίποτα (και ό,τι «loadAt» έφερε το κείμενο αγνοείται).
      final first = prog(_ex('db_press', extra: ',"load":9.3,"loadAt":123'));
      expect(pressOf(first).loadAt, 123, reason: 'το κείμενο το διαβάζει…');
      stampLoadTimes(first, null, at);
      expect(pressOf(first).loadAt, isNull, reason: '…αλλά η αποθήκευση το αγνοεί');
      // Ίδιο φορτίο με πριν: καμία σημείωση. Άλλο φορτίο, ή νέα άσκηση με φορτίο: σημειώνεται.
      final next = prog('${_ex('db_press', extra: ',"load":9.3,"loadAt":123')},${_ex('db_row', extra: ',"load":4.3')},'
          '${_ex('goblet', extra: ',"load":11.8')},${_ex('db_curl')}');
      stampLoadTimes(next, old, at);
      final byEx = {for (final i in next.workout('A')!.items) i.ex: i.loadAt};
      expect(byEx, {'db_press': null, 'db_row': ms(at), 'goblet': ms(at), 'db_curl': null});
      // Τρίτο πρόγραμμα με τα ίδια φορτία: οι σημειώσεις μένουν όπως ήταν (δεν γίνονται «τώρα»).
      final third = prog('${_ex('db_press', extra: ',"load":9.3')},${_ex('db_row', extra: ',"load":4.3')}');
      stampLoadTimes(third, next, at.add(const Duration(days: 7)));
      expect({for (final i in third.workout('A')!.items) i.ex: i.loadAt}, {'db_press': null, 'db_row': ms(at)});
      // Γράφεται και διαβάζεται από το αρχείο.
      final back = Program.fromJson(jsonDecode(jsonEncode(next.toJson())) as Map<String, dynamic>);
      expect({for (final i in back.workout('A')!.items) i.ex: i.loadAt}, byEx);
      expect(jsonEncode(old.toJson()), isNot(contains('loadAt')), reason: 'χωρίς σημείωση το αρχείο μένει όπως πριν');
    });

    test('αποθήκευση: μια αλλαγή αλλού (π.χ. σετ) ΔΕΝ ξαναγράφει φορτία· νέο πιο ελαφρύ φορτίο ισχύει στην επόμενη προπόνηση', () {
      final t = _store([_lift(3, [_log('db_press', 9.3, [11, 10, 10], rir: 2)])]);
      // Το πρόγραμμα με το παλιό αρχικό φορτίο (4,3 kg), ενώ η άσκηση έχει φτάσει τα 9,3 kg.
      final v1 = t.saveProgram(prog(_ex('db_press', extra: ',"load":4.3')));
      expect(t.targetFor(pressOf(v1)).load, 9.3);
      // Αλλάζεις τα σετ και αποθηκεύεις ξανά: το φορτίο του προγράμματος είναι το ίδιο → τα 9,3 kg μένουν.
      final edited = v1.copy();
      pressOf(edited).sets = 4;
      final v2 = t.saveProgram(edited);
      expect(pressOf(v2).loadAt, isNull);
      expect(t.targetFor(pressOf(v2)).load, 9.3, reason: 'πριν από αυτή τη φύλαξη, κάθε αποθήκευση θα γύριζε την άσκηση στα 4,3 kg');
      // Νέο πρόγραμμα που γράφει 6,8 kg (πιο ελαφριά εβδομάδα): ισχύει.
      final v3 = t.saveProgram(prog(_ex('db_press', extra: ',"load":6.8')), author: 'claude');
      expect(pressOf(v3).loadAt, ms(_now));
      final target = t.targetFor(pressOf(v3));
      expect((target.load, target.change), (6.8, Change.back));
      // Νέο πρόγραμμα που γράφει 11,8 kg (ψηλότερα): δεν ισχύει μόνο του.
      final v4 = t.saveProgram(prog(_ex('db_press', extra: ',"load":11.8')), author: 'claude');
      expect(t.targetFor(pressOf(v4)).load, 9.3);
    });

    testWidgets('η επικόλληση το δείχνει πριν αποθηκεύσεις: «6,8 kg (πιο ελαφριά από την τελευταία φορά)»', (tester) async {
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final t = _store([_lift(3, [_log('db_press', 9.3, [11, 10, 10], rir: 2)])]);
      t.saveProgram(prog(_ex('db_press', extra: ',"load":9.3')));
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 2400);
      addTearDown(tester.view.reset);
      final text = _prog(items: _ex('db_press', extra: ',"load":6.8'));
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: ProgramPastePage(training: t, initial: text)));
      await tester.pump();
      expect(find.textContaining('6,8 kg (πιο ελαφριά από την τελευταία φορά)'), findsOneWidget);
      expect(find.byKey(const ValueKey('paste-lighter')), findsOneWidget);
      expect(find.byKey(const ValueKey('paste-continues')), findsNothing);
      // Το πρόγραμμα που ίσχυε δεν άλλαξε από την προεπισκόπηση.
      expect(t.program!.workout('A')!.items.single.loadAt, isNull);
      // Ίδιο φορτίο με του τωρινού προγράμματος (9,3 → 9,3) ενώ έχεις προχωρήσει: «συνεχίζεις από …», όπως πριν.
    });
  });

  testWidgets('K4C-15: χωρίς ιστορικό, η επικόλληση δείχνει τα κιλά του προγράμματος και καμία σημείωση', (tester) async {
    await tester.runAsync(() => ExLibrary.load(inline: true));
    final t = _store(const []);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light), home: ProgramPastePage(training: t, initial: _prog(items: _ex('db_press', extra: ',"load":6.8')))));
    await tester.pump();
    expect(find.textContaining('6,8 kg'), findsOneWidget);
    expect(find.byKey(const ValueKey('paste-continues')), findsNothing);
  });

  // ------------------------------------------------------------------ K4-S-03
  group('K4-S-03: «Πρόοδος» στη δύναμη — «πτώση» μόνο πάνω από τον θόρυβο και όχι όταν το έκανε η εφαρμογή', () {
    ExProgress one(List<Session> s, String ex) => strengthProgress(s, _now, TrendPeriod.month).firstWhere((p) => p.ex == ex);

    test('ίδια δύναμη, κακή μέρα: 12, 12, 11 → 12, 11, 10 = «Ίδιο» (πριν «πτώση −2»)', () {
      final p = one([_lift(10, [_log('db_press', 9.3, [12, 12, 11])]), _lift(3, [_log('db_press', 9.3, [12, 11, 10])])], 'db_press');
      expect(p.change, StrengthChange.same);
    });

    test('έκανε ό,τι του είπε ο στόχος: 11, 11, 11 → 10, 10, 10 = «Ίδιο» (πριν «πτώση −3»)', () {
      final p = one([_lift(10, [_log('db_press', 9.3, [11, 11, 11])]), _lift(3, [_log('db_press', 9.3, [10, 10, 10])])], 'db_press');
      expect(p.change, StrengthChange.same);
    });

    test('πραγματική πτώση: 12, 12, 12 → 9, 9, 9 με ίδιο βάρος = «πτώση» (μένει)', () {
      final p = one([_lift(10, [_log('db_press', 9.3, [12, 12, 12])]), _lift(3, [_log('db_press', 9.3, [9, 9, 9])])], 'db_press');
      expect(p.change, StrengthChange.down);
      expect(strengthPill(p).$2, TrendKind.bad);
    });

    test('πραγματική πρόοδος: 9, 9, 9 → 12, 12, 12 = «πάνω»· +1 σε κάθε σετ = «Ίδιο»', () {
      final up = one([_lift(10, [_log('db_press', 9.3, [9, 9, 9])]), _lift(3, [_log('db_press', 9.3, [12, 12, 12])])], 'db_press');
      expect(up.change, StrengthChange.up);
      final same = one([_lift(10, [_log('db_press', 9.3, [10, 10, 10])]), _lift(3, [_log('db_press', 9.3, [11, 11, 11])])], 'db_press');
      expect(same.change, StrengthChange.same);
    });

    test('διακοπή 37 ημερών και πιο ελαφρύ φορτίο: ουδέτερο, «πιο ελαφριά μετά από διακοπή» (πριν κόκκινη «πτώση»)', () {
      final p = one([_lift(40, [_log('db_press', 9.3, [12, 12, 12])]), _lift(3, [_log('db_press', 7.8, [8, 8, 8])])], 'db_press');
      expect(p.eased, Eased.pause);
      expect(p.change, StrengthChange.mixed);
      expect(strengthPill(p), ('πιο ελαφριά μετά από διακοπή', TrendKind.neutral, null));
      final walk = walkProgress(const <Session>[], _now, TrendPeriod.month);
      expect(progressHighlights(walk, [p], const []), isEmpty, reason: 'δεν μπαίνει στο «Τι άλλαξε»');
    });

    test('ενόχληση και πιο ελαφρύ φορτίο: ουδέτερο, «πιο ελαφριά μετά από ενόχληση»', () {
      final p = one([
        _lift(10, [_log('db_press', 9.3, [10, 10, 9], pain: const ['shoulderR'])]),
        _lift(3, [_log('db_press', 7.8, [10, 10, 9])]),
      ], 'db_press');
      expect(p.eased, Eased.pain);
      expect(strengthPill(p), ('πιο ελαφριά μετά από ενόχληση', TrendKind.neutral, null));
    });

    test('ενόχληση σε προπόνηση χωρίς κανένα σετ ανάμεσα: μετρά', () {
      final p = one([
        _lift(10, [_log('db_press', 9.3, [10, 10, 10])]),
        _lift(7, [_log('db_press', 9.3, [8, 8, 8], pain: const ['shoulderR'], skipped: true, done: false)]),
        _lift(3, [_log('db_press', 7.8, [10, 10, 10])]),
      ], 'db_press');
      expect(p.eased, Eased.pain);
      expect(p.change, StrengthChange.mixed);
    });

    test('πιο ελαφρύ φορτίο χωρίς διακοπή και χωρίς ενόχληση: «πτώση» (μένει)', () {
      final p = one([_lift(10, [_log('db_press', 9.3, [8, 8, 8])]), _lift(3, [_log('db_press', 7.8, [8, 8, 8])])], 'db_press');
      expect(p.eased, isNull);
      expect(p.change, StrengthChange.down);
      // Πιο ελαφρύ με περισσότερες επαναλήψεις: «βάρος ↓, επαναλήψεις ↑», όπως πριν (η ανοχή με άλλο φορτίο δεν άλλαξε).
      final more = one([_lift(10, [_log('db_press', 9.3, [8, 7, 6])]), _lift(3, [_log('db_press', 7.8, [8, 8, 8])])], 'db_press');
      expect(more.change, StrengthChange.mixed);
    });

    // K4-R-04: με ΑΛΛΟ φορτίο μένει η παλιά ανοχή (1 στο σύνολο)· αλλιώς αντιφάσκει με το ⓘ της ίδιας οθόνης.
    test('περισσότερο βάρος με όλα τα σετ κάτω από το εύρος (8, 8, 8 → 7, 7, 7): «ούτε καλύτερα ούτε χειρότερα»', () {
      final p = one([_lift(10, [_log('db_press', 9.3, [8, 8, 8])]), _lift(3, [_log('db_press', 10.3, [7, 7, 7])])], 'db_press');
      expect(p.change, StrengthChange.mixed);
      expect(strengthPill(p).$2, TrendKind.neutral);
    });

    // K4-R-05: χωρίς φορτίο (ή με το ίδιο), ο στόχος μετά από διακοπή είναι «ξανά από το κάτω όριο».
    test('κάμψεις 15, 15, 15 → διακοπή 37 ημερών → 10, 10, 10: ουδέτερο «λιγότερες επαναλήψεις μετά από διακοπή» (πριν κόκκινη «πτώση −15»)', () {
      final p = one([
        _lift(40, [_log('pushup_bench', null, [15, 15, 15], lo: 10, hi: 15)]),
        _lift(3, [_log('pushup_bench', null, [10, 10, 10], lo: 10, hi: 15)]),
      ], 'pushup_bench');
      expect(p.eased, Eased.pause);
      expect(p.easedReps, isTrue);
      expect(p.change, StrengthChange.mixed);
      expect(strengthPill(p), ('λιγότερες επαναλήψεις μετά από διακοπή', TrendKind.neutral, null));
    });

    test('κάμψεις 15, 15, 15 → 10, 10, 10 ΧΩΡΙΣ διακοπή ή ενόχληση: «πτώση» (μένει)', () {
      final p = one([
        _lift(10, [_log('pushup_bench', null, [15, 15, 15], lo: 10, hi: 15)]),
        _lift(3, [_log('pushup_bench', null, [10, 10, 10], lo: 10, hi: 15)]),
      ], 'pushup_bench');
      expect(p.eased, isNull);
      expect(p.change, StrengthChange.down);
    });

    // K4-R-06: στο Τρίμηνο μια παλιά διακοπή «ξεπληρώνεται» όταν το φορτίο ξαναφτάσει το «πριν».
    test('τρίμηνο: διακοπή, επιστροφή στα ίδια κιλά, και ΜΕΤΑ πτώση χωρίς διακοπή: «πτώση» (δεν κρύβεται πίσω από την παλιά διακοπή)', () {
      ExProgress q(List<Session> s) => strengthProgress(s, _now, TrendPeriod.quarter).firstWhere((p) => p.ex == 'db_press');
      final repaid = q([
        _lift(100, [_log('db_press', 9.3, [10, 10, 10])]),
        _lift(70, [_log('db_press', 7.8, [8, 8, 8])]),
        _lift(60, [_log('db_press', 9.3, [10, 10, 10])]),
        _lift(50, [_log('db_press', 9.3, [8, 7, 6])]),
        _lift(40, [_log('db_press', 7.8, [8, 8, 8])]),
      ]);
      expect(repaid.eased, isNull);
      expect(repaid.change, StrengthChange.down);
      // Χωρίς την επιστροφή στα 9,3 kg: η διακοπή εξηγεί ακόμα το πιο ελαφρύ φορτίο.
      final still = q([
        _lift(100, [_log('db_press', 9.3, [10, 10, 10])]),
        _lift(70, [_log('db_press', 7.8, [8, 8, 8])]),
        _lift(60, [_log('db_press', 7.8, [9, 9, 9])]),
      ]);
      expect(still.eased, Eased.pause);
      expect(still.change, StrengthChange.mixed);
    });

    test('διακοπή αλλά περισσότερο βάρος: «πάνω» (η διακοπή δεν κρύβει την πρόοδο)', () {
      final p = one([_lift(40, [_log('db_press', 9.3, [12, 12, 12])]), _lift(3, [_log('db_press', 10.3, [8, 8, 8])])], 'db_press');
      expect(p.change, StrengthChange.up);
    });
  });

  // ------------------------------------------------------------------ κείμενα
  group('κείμενα ασφάλειας και οδηγιών', () {
    test('K4-S-01: η γραμμή ασφάλειας της προπόνησης', () {
      for (final w in ['λιποθυμ', 'πλάτη', 'σαγόνι', 'λίγα λεπτά', 'ξαναέρθει', '166 ή 112', 'πριν από την επόμενη προπόνηση']) {
        expect(sessionSafetyText, contains(w), reason: w);
      }
      expect(sessionSafetyText, isNot(contains('δεν περνούν με την ξεκούραση')));
      expect(sessionSafetyText.length, lessThan(330));
    });

    test('K4-S-10: υπενθύμιση ζεστάματος όταν το πρόγραμμα δεν έχει', () {
      expect(sessionWarmupText, contains('ζέσταμα'));
    });

    test('K4-S-02: το ⓘ της ζώνης λέει ότι το γρήγορο περπάτημα κάτω από τη ζώνη μετρά για τον Π.Ο.Υ.', () {
      expect(zoneInfo.down, contains('100 βήματα το λεπτό'));
      expect(zoneInfo.cite, contains('ACSM 2011'));
    });

    test('K4-S-06: το ⓘ «Άφησε» δεν υπόσχεται ότι «με την ώρα γίνεται πιο εύκολο»', () {
      expect(rirInfo.accuracy, isNot(contains('Με την ώρα')));
      expect(rirInfo.accuracy, contains('πάνω από 12'));
    });

    test('K4-S-09 / K4-S-12: η βιβλιοθήκη (ρόδα κοιλιακών, πλάγιες, hip thrust)', () {
      final j = jsonDecode(File('assets/exercises/exercises.json').readAsStringSync()) as Map<String, dynamic>;
      final all = {for (final e in j['ex'] as List) (e as Map<String, dynamic>)['id'] as String: e};
      final wheel = (all['ab_wheel']!['tips'] as List).join(' ');
      expect(wheel, contains('εκπνοή όσο τραβάς πίσω'));
      expect(wheel, isNot(contains('εισπνοή όταν επιστρέφεις')));
      expect((all['lateral_raise']!['tips'] as List).join(' '), isNot(contains('δουλεύουν καλύτερα')));
      expect((all['hip_thrust']!['tips'] as List).join(' '), isNot(contains('Από τις καλύτερες')));
    });
  });
}
