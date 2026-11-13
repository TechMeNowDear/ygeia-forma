// Round 1 (f6a): «Προπόνηση — λογική και δεδομένα στο κινητό». Ένα τεστ ανά διορθωμένο εύρημα (S6, S7, S9, S11, S12).
// Οι αναμενόμενες τιμές βγήκαν από τον γραμμένο κανόνα (Python: /home/claude/scratch/f6a/newprog.py, sim.py), όχι από τον
// κώδικα. Όλα τα νούμερα είναι δοκιμαστικά (κανένα πραγματικό δεδομένο υγείας).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/exercise/ex_data.dart';
import 'package:ygeia_forma/exercise/ex_names.dart';
import 'package:ygeia_forma/exercise/ex_player.dart';
import 'package:ygeia_forma/pages/training/training_common.dart';
import 'package:ygeia_forma/pages/training/training_page.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/training/equipment.dart';
import 'package:ygeia_forma/training/program.dart';
import 'package:ygeia_forma/training/progression.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/set_hr.dart';
import 'package:ygeia_forma/training/training_store.dart';
import 'package:ygeia_forma/training/walk_stats.dart';
import 'package:ygeia_forma/training/wear_link.dart';
import 'package:ygeia_forma/training/zone.dart';

import 'training_sample.dart';

final now = DateTime(2026, 11, 20, 18, 0); // Παρασκευή
final d = DateTime(2026, 11, 17, 18, 0);

/// Η άσκηση όπως στο πρόγραμμα του χρήστη: ρεζέρβα 3 (S12-01).
PlanItem item3(String ex, {int sets = 3, int lo = 8, int hi = 12, int rir = 3, double? load, String? next}) =>
    PlanItem(ex: ex, sets: sets, lo: lo, hi: hi, rir: rir, rest: 90, load: load, next: next);

/// Μια προηγούμενη φορά: [sets] όσα είχε ΕΚΕΙΝΗ η μέρα (μπορεί να είναι περισσότερα από όσα έγιναν).
ExLog done(String ex, double? load, List<int> reps, {int? ra, int lo = 8, int hi = 12, int? sets}) => ExLog(
      ex: ex,
      sets: sets ?? reps.length,
      lo: lo,
      hi: hi,
      rir: 3,
      rest: 90,
      rirAnswer: ra,
      log: [for (final r in reps) SetLog(load: load, reps: r, done: true)],
    );

/// training.json που δεν διαβάζεται προσωρινά (σφάλμα αρχείου) και μετά διαβάζεται.
class _FlakyIO extends MemoryTrainingIO {
  _FlakyIO(super.json);
  bool fail = true;

  @override
  Future<({String state, String? json})> read() async {
    if (fail) return (state: 'error', json: null);
    return super.read();
  }
}

/// Πρόγραμμα με πλάνο περπατήματος και κάμψεις με πιο δύσκολη παραλλαγή.
const _program = '{"kind":"ygeia-program","id":"p-r1","name":"Δοκιμή","from":"2026-11-16",'
    '"days":{"fri":"A","tue":"walk"},'
    '"workouts":[{"id":"A","name":"Πάνω","items":['
    '{"ex":"pushup_bench","sets":2,"reps":[8,12],"rir":3,"next":"pushup_handles"},'
    '{"ex":"db_press","sets":3,"reps":[8,12],"rir":3}]},'
    '{"id":"walk","name":"Περπάτημα","cardio":{"activity":"walk","minutes":20,"plan":[20,25,30,35]}}]}';

const _known = {'pushup_bench', 'pushup_handles', 'db_press', 'db_row'};

TrainingStore _store(DateTime Function() clock) {
  final p = parseProgram(_program, _known).program!;
  return TrainingStore(io: MemoryTrainingIO(), clock: clock)..replaceAll({'v': 1, 'programs': [p.toJson()], 'active': p.id});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ------------------------------------------------------------------ S6-2 / S7-01 (ΠΡΩΤΑ: η βιβλιοθήκη δεν έχει φορτώσει)
  group('S6-2 / S7-01: προπόνηση χωρίς φορτωμένη βιβλιοθήκη', () {
    test('ονόματα στο κινητό και στο ρολόι από τον σταθερό πίνακα, ποτέ το σκέτο id', () {
      expect(ExLibrary.loaded, isNull, reason: 'η δοκιμή θέλει τη βιβλιοθήκη ΜΗ φορτωμένη');
      expect(exName('db_press'), 'Πιεστικό με αλτήρες');
      expect(watchExName('db_press'), 'Πιεστικό με αλτήρες');
      expect(watchExName('άγνωστη'), 'άγνωστη');
      final plan = watchPlan(sampleTraining(now), now, watchExName);
      for (final w in (plan['workouts'] as List).cast<Map>()) {
        for (final i in (w['items'] as List).cast<Map>()) {
          expect(i['name'], exNamesById[i['ex']], reason: '${i['ex']}');
        }
      }
    });

    test('«με προσοχή» χωρίς βιβλιοθήκη: μόνο οι ασκήσεις της βιβλιοθήκης, όχι όλες', () {
      expect(ExLibrary.loaded, isNull);
      expect(TrainingStore.isCaution('dips'), isTrue);
      expect(TrainingStore.isCaution('db_press'), isFalse);
      // Χωρίς απάντηση για ρεζέρβα, μέσα στο εύρος: +1 όπως όταν η βιβλιοθήκη έχει φορτώσει (πριν: «ίδια»).
      final t = nextTarget(item3('db_row', rir: 2), [(d, done('db_row', 14.3, [10, 10, 9]))], now, caution: TrainingStore.isCaution('db_row'));
      expect(t.change, Change.more);
      expect(t.reps, [11, 11, 10]);
    });

    test('ο σταθερός πίνακας «με προσοχή» είναι ίδιος με τη βιβλιοθήκη', () {
      final lib = ExLibrary.fromJson(jsonDecode(File('assets/exercises/exercises.json').readAsStringSync()) as Map<String, dynamic>);
      expect(TrainingStore.cautionIds, {for (final e in lib.list) if (e.caution != null) e.id});
      expect(ExLibrary.loaded, isNull, reason: 'το fromJson δεν φορτώνει την κοινή βιβλιοθήκη');
    });
  });

  // ------------------------------------------------------------------ S6-1
  group('S6-1: η προηγούμενη φορά κρίνεται με τα σετ και το εύρος ΕΚΕΙΝΗΣ της μέρας', () {
    test('ίδια άσκηση, 3 σετ σήμερα, 2 σετ την προηγούμενη φορά: +1, όχι «δεν έγιναν όλα τα σετ»', () {
      final t = nextTarget(item3('db_row'), [(d, done('db_row', 6.8, [9, 9], ra: 3))], now);
      expect(t.change, Change.more);
      expect(t.load, 6.8);
      expect(t.reps, [10, 10, 9]);
      expect(t.reason, isNot(contains('δεν έγιναν όλα τα σετ')));
      final b = nextTarget(item3('band_pulldown', lo: 10, hi: 15), [(d, done('band_pulldown', 20, [10, 10], ra: 3, lo: 10, hi: 15))], now);
      expect(b.change, Change.more);
      expect(b.reps, [11, 11, 10]);
    });

    test('goblet 8–12 τη μία μέρα, 10–15 την άλλη: όχι κατέβασμα όταν βγήκαν οι στόχοι', () {
      final h = [(d, done('goblet', 10, [9, 9, 9], ra: 3)), (d.subtract(const Duration(days: 7)), done('goblet', 10, [8, 8, 8], ra: 3))];
      final t = nextTarget(item3('goblet', lo: 10, hi: 15), h, now);
      expect(t.change, Change.more);
      expect(t.load, 10);
      expect(t.reps, [10, 10, 10]);
    });

    test('εναλλαγή 3 σετ / 2 σετ, κάθε στόχος με ρεζέρβα 3: οι επαναλήψεις ανεβαίνουν, μετά το βάρος', () {
      final hist = <(DateTime, ExLog)>[];
      var day = DateTime(2026, 11, 20);
      final firsts = <int>[];
      for (var n = 0; n < 9; n++) {
        final it = item3('db_row', sets: n.isEven ? 3 : 2);
        final tg = nextTarget(it, hist, day);
        if (n < 8) {
          expect(tg.change, n == 0 ? Change.first : Change.more, reason: 'φορά ${n + 1}');
          expect(tg.load, 6.8);
          firsts.add(tg.reps.first);
        } else {
          expect(tg.change, Change.up);
          expect(tg.load, closeTo(7.8, 1e-9));
          expect(tg.reps, [8, 8, 8]);
        }
        hist.insert(
            0,
            (
              day,
              ExLog(
                ex: 'db_row',
                sets: it.sets,
                lo: TrainingStore.loFor(it, tg),
                hi: it.hi,
                rir: 3,
                rest: 90,
                rirAnswer: 3,
                log: [for (final r in tg.reps) SetLog(load: tg.load, reps: r, done: true)],
              )
            ));
        day = DateTime(day.year, day.month, day.day + (n.isEven ? 2 : 5));
      }
      expect(firsts, [8, 9, 10, 11, 12, 13, 14, 15]);
    });

    test('το κάτω όριο που γράφεται: του προγράμματος, ή ο στόχος της μέρας αν είναι πιο κάτω', () {
      final it = item3('goblet', lo: 10, hi: 15);
      expect(TrainingStore.loFor(it, const Target(load: 10, reps: [9, 9, 9], change: Change.more, reason: '')), 9);
      expect(TrainingStore.loFor(it, const Target(load: 10, reps: [11, 11, 11], change: Change.more, reason: '')), 10);
    });

    test('τελείωσες νωρίτερα: μέσα στο εύρος ίδια· κάτω από το εύρος δύο φορές → ένα σκαλί κάτω (όπως πριν)', () {
      final once = nextTarget(item3('db_press', rir: 2), [(d, done('db_press', 9.3, [5], sets: 3))], now);
      expect(once.change, Change.hold);
      expect(once.reps, [8, 8, 8]);
      expect(once.reason, contains('δεν έγιναν όλα τα σετ'));
      final twice = nextTarget(
          item3('db_press', rir: 2), [(d, done('db_press', 9.3, [5], sets: 3)), (d.subtract(const Duration(days: 3)), done('db_press', 9.3, [6, 5], sets: 3))], now);
      expect(twice.change, Change.down);
      expect(twice.load, closeTo(7.8, 1e-9));
      final inRange = nextTarget(item3('db_press', rir: 2), [(d, done('db_press', 9.3, [10, 9], ra: 2, sets: 3))], now);
      expect(inRange.change, Change.hold);
      expect(inRange.reps, [10, 9, 9]);
    });
  });

  // ------------------------------------------------------------------ S12-01 (Τ1)
  group('S12-01: πρόγραμμα με ρεζέρβα 3', () {
    Target t(List<int> reps, int ra) => nextTarget(item3('db_press'), [(d, done('db_press', 9.3, reps, ra: ra))], now);

    test('με 2 ρεζέρβα δεν ανεβαίνει τίποτα· με 3 ανεβαίνει', () {
      final a = t([12, 12, 12], 2);
      expect((a.change, a.load), (Change.hold, 9.3));
      expect(a.reps, [12, 12, 12]);
      expect(a.reason, contains('άφησες 2'));
      final b = t([12, 12, 12], 3);
      expect(b.change, Change.up);
      expect(b.load, closeTo(10.3, 1e-9));
      expect(b.reps, [8, 8, 8]);
      final c = t([10, 10, 9], 2);
      expect(c.change, Change.hold);
      expect(c.reps, [10, 10, 9]);
      expect(c.reason, contains('άφησες 2, λιγότερες από 3'));
      final e = t([10, 10, 9], 3);
      expect(e.change, Change.more);
      expect(e.reps, [11, 11, 10]);
      final f = t([10, 10, 9], 1);
      expect(f.change, Change.hold);
      expect(f.reason, contains('Άφησες 1'));
    });

    test('η ρεζέρβα 3 μένει στο πρόγραμμα και φτάνει στο ρολόι', () {
      final p = parseProgram(_program, _known);
      expect(p.ok, isTrue, reason: p.errors.join('\n'));
      expect(p.program!.workout('A')!.items[1].rir, 3);
      final t = _store(() => now);
      final plan = watchPlan(t, now, watchExName);
      expect((((plan['workouts'] as List)[0] as Map)['items'] as List)[1]['rir'], 3);
    });
  });

  // ------------------------------------------------------------------ S6-12 / S7-02 / S7-03 / S7-22
  group('S6-12: μεγάλο σκαλί εξοπλισμού → πρώτα επαναλήψεις', () {
    test('τύπος (Epley): 4,3 → 5,3 kg με 8–12 και ρεζέρβα 3 θέλει 18 επαναλήψεις πριν από το σκαλί', () {
      expect(repsBeforeStep(5.3 / 4.3, 8, 3), 18);
      expect(repsBeforeStep(5.3 / 4.3, 10, 3), 20);
      // λάστιχο 20 → 30 lb (+50%): πάνω από 12 + 10 → ποτέ αυτόματα
      expect(stepCeiling('pallof', LoadKind.band, 20, 30, 10, 12, 3), (reps: 17, step: false));
      // μικρό σκαλί (9,3 → 10,3 kg, +11%): στο πάνω όριο, όπως πριν
      expect(stepCeiling('db_press', LoadKind.dbPair, 9.3, 10.3, 8, 12, 3), (reps: 12, step: true));
    });

    test('Pallof 2 × 10–12, μπλε λάστιχο: +1 επανάληψη αντί για +50%· στο ανώτατο δεν ανεβαίνει μόνο του', () {
      final a = nextTarget(item3('pallof', sets: 2, lo: 10, hi: 12), [(d, done('pallof', 20, [12, 12], ra: 3, lo: 10, hi: 12))], now);
      expect((a.change, a.load), (Change.more, 20.0));
      expect(a.reps, [13, 13]);
      final b = nextTarget(item3('pallof', sets: 2, lo: 10, hi: 12), [(d, done('pallof', 20, [17, 17], ra: 3, lo: 10, hi: 12))], now);
      expect(b.change, Change.max);
      expect(b.load, 20);
    });

    test('αλτήρας 4,3 → 5,3 kg σε 10–15: ως τις 20, μετά ανεβαίνει', () {
      final a = nextTarget(item3('db_curl', sets: 2, lo: 10, hi: 15), [(d, done('db_curl', 4.3, [15, 15], ra: 3, lo: 10, hi: 15))], now);
      expect(a.change, Change.more);
      expect(a.reps, [16, 16]);
      final b = nextTarget(item3('db_curl', sets: 2, lo: 10, hi: 15), [(d, done('db_curl', 4.3, [20, 20], ra: 3, lo: 10, hi: 15))], now);
      expect(b.change, Change.up);
      expect(b.load, closeTo(5.3, 1e-9));
      expect(b.reps, [10, 10]);
    });
  });

  group('S7-02: εξωτερική στροφή ώμου με ελαφρύ λάστιχο', () {
    test('πρώτη φορά κίτρινο (10 lb)· ποτέ αυτόματα βαρύτερο', () {
      expect(nextTarget(item3('band_er', sets: 2, lo: 12, hi: 15), const [], now).load, 10);
      expect(nextTarget(item3('face_pull', sets: 2, lo: 12, hi: 15), const [], now).load, 10);
      final a = nextTarget(item3('band_er', sets: 2, lo: 12, hi: 15), [(d, done('band_er', 10, [15, 15], ra: 3, lo: 12, hi: 15))], now);
      expect((a.change, a.load), (Change.more, 10.0));
      expect(a.reps, [16, 16]);
      final b = nextTarget(item3('band_er', sets: 2, lo: 12, hi: 15), [(d, done('band_er', 10, [20, 20], ra: 4, lo: 12, hi: 15))], now);
      expect(b.change, Change.max);
      expect(b.load, 10);
      expect(calibrate(item3('band_er', sets: 2, lo: 12, hi: 15), 10, 15, 4), isNull);
    });
  });

  group('S7-03: πιο δύσκολη παραλλαγή', () {
    test('πρόταση με το όνομα της παραλλαγής, όχι σιωπηλό «2 × 8»', () {
      final t = nextTarget(item3('pushup_bench', sets: 2, next: 'pushup_handles'), [(d, done('pushup_bench', null, [17, 17], ra: 3))], now);
      expect(t.change, Change.variant);
      expect(t.variant, 'pushup_handles');
      expect(t.reps, [17, 17]);
      expect(t.reason, contains('Κάμψεις με λαβές'));
      expect(t.reason, contains('Αλλαγή άσκησης'));
    });

    test('αν πέρασες στην παραλλαγή, η επόμενη προπόνηση (και το ρολόι) ξεκινά με αυτήν· αν γύρισες πίσω, με την αρχική', () {
      final t = _store(() => now);
      t.sessions.add(Session(
        id: 'h1',
        workout: 'A',
        name: 'Πάνω',
        programId: 'p-r1',
        start: now.subtract(const Duration(days: 7)),
        end: now.subtract(const Duration(days: 7)).add(const Duration(hours: 1)),
        items: [
          ExLog(ex: 'pushup_handles', sets: 2, lo: 8, hi: 12, rir: 3, rest: 90, rirAnswer: 3, swappedFrom: 'pushup_bench', log: [
            SetLog(reps: 6, done: true),
            SetLog(reps: 6, done: true),
          ]),
        ],
      ));
      final s = t.start(t.program!.workout('A')!);
      expect(s.items.first.ex, 'pushup_handles');
      expect(s.items.first.swappedFrom, 'pushup_bench');
      final plan = watchPlan(t, now, watchExName);
      expect((((plan['workouts'] as List)[0] as Map)['items'] as List)[0]['ex'], 'pushup_handles');
      t.discard();
      t.sessions.add(Session(
        id: 'h2',
        workout: 'A',
        name: 'Πάνω',
        programId: 'p-r1',
        start: now.subtract(const Duration(days: 2)),
        end: now.subtract(const Duration(days: 2)).add(const Duration(hours: 1)),
        items: [
          ExLog(ex: 'pushup_bench', sets: 2, lo: 8, hi: 12, rir: 3, rest: 90, rirAnswer: 3, log: [
            SetLog(reps: 10, done: true),
            SetLog(reps: 10, done: true),
          ]),
        ],
      ));
      expect(t.start(t.program!.workout('A')!).items.first.ex, 'pushup_bench');
    });
  });

  group('S7-22: «4+» με ελαφρύ αλτήρα', () {
    test('η συμβουλή για το «+» μόνο με «4+» και μόνο όπου το σκαλί βγαίνει', () {
      final a = nextTarget(item3('db_press'), [(d, done('db_press', 4.3, [10, 10, 10], ra: 4))], now);
      expect(a.change, Change.more);
      expect(a.reps, [11, 11, 11]);
      expect(a.reason, contains('«+»'));
      final b = nextTarget(item3('db_press'), [(d, done('db_press', 4.3, [10, 10, 10], ra: 3))], now);
      expect(b.reason, isNot(contains('«+»')));
      final bar = nextTarget(item3('rdl'), [(d, done('rdl', 10, [10, 10, 10], ra: 4))], now);
      expect(bar.reason, isNot(contains('«+»')));
    });
  });

  // ------------------------------------------------------------------ S6-7 + S12-13 (Τ11)
  group('S6-7: βαθμονόμηση πρώτης φοράς', () {
    test('λιγότερη από 2 ρεζέρβα, όσες επαναλήψεις κι αν βγήκαν: ένα σκαλί πιο ελαφριά', () {
      final i = item3('db_press', rir: 2, load: 9.3);
      expect(calibrate(i, 9.3, 8, 0), closeTo(7.8, 1e-9));
      expect(calibrate(i, 9.3, 10, 1), closeTo(7.8, 1e-9));
      expect(calibrate(i, 9.3, 6, 1), closeTo(7.8, 1e-9));
      expect(calibrate(i, 9.3, 10, 2), isNull);
      expect(calibrate(i, 9.3, 10, 3), isNull);
      expect(calibrate(i, 9.3, 7, 4), isNull, reason: 'κάτω από το εύρος');
      expect(calibrate(i, 9.3, 10, 4), closeTo(10.3, 1e-9));
      // ρεζέρβα προγράμματος 3: το «4+» στις 10 δεν φτάνει για +11% (χρειάζονται 11 + 1)
      final i3 = item3('db_press', load: 9.3);
      expect(calibrate(i3, 9.3, 10, 4), isNull);
      expect(calibrate(i3, 9.3, 11, 4), closeTo(10.3, 1e-9));
    });

    test('όρια: ακριβώς 14 ημερολογιακές μέρες → όχι «μετά από διάλειμμα»· 15 → ναι', () {
      Target t(int days) => nextTarget(item3('db_press', rir: 2), [(DateTime(2026, 11, 20 - days, 18), done('db_press', 11.8, [12, 12, 12], ra: 2))], now);
      expect(t(14).change, isNot(Change.back));
      expect(t(15).change, Change.back);
    });
  });

  // ------------------------------------------------------------------ S6-6
  group('S6-6: επικόλληση — τίποτα δεν αλλάζει σιωπηλά', () {
    String prog({String days = '"mon":"A"', String item = '{"ex":"db_press"}'}) =>
        '{"kind":"ygeia-program","id":"p","name":"Π","days":{$days},"workouts":[{"id":"A","name":"Α","items":[$item]}]}';

    test('μέρες: ολόκληρα ονόματα γίνονται δεκτά, άγνωστα λέγονται', () {
      final ok = parseProgram(prog(days: '"monday":"A","Τετάρτη":"A","Fri.":"A","sat":"A"'), _known);
      expect(ok.ok, isTrue, reason: ok.errors.join('\n'));
      expect(ok.program!.days, {1: 'A', 3: 'A', 5: 'A', 6: 'A'});
      final bad = parseProgram(prog(days: '"lundi":"A"'), _known);
      expect(bad.ok, isFalse);
      expect(bad.errors.single, contains('μέρα «lundi»'));
    });

    test('επαναλήψεις που δεν είναι [από, ως], ρεζέρβα πάνω από 4, βάρος «άπειρο»: λάθος', () {
      expect(parseProgram(prog(item: '{"ex":"db_press","reps":"10-15"}'), _known).ok, isFalse);
      expect(parseProgram(prog(item: '{"ex":"db_press","reps":[10,12,15]}'), _known).ok, isFalse);
      final rir = parseProgram(prog(item: '{"ex":"db_press","rir":7}'), _known);
      expect(rir.ok, isFalse);
      expect(rir.errors.join(), contains('«άφησε»'));
      expect(parseProgram(prog(item: '{"ex":"pushup_bench","load":1e999}'), _known).ok, isFalse);
      // θετικός έλεγχος
      expect(parseProgram(prog(item: '{"ex":"db_press","reps":[10,15],"rir":4,"load":9.3}'), _known).ok, isTrue);
      expect(parseProgram(prog(item: '{"ex":"db_press","reps":12}'), _known).ok, isTrue);
    });
  });

  // ------------------------------------------------------------------ S6-8 + S12-13
  group('S6-8: «♥ διάλειμμα» πριν από το επόμενο σετ, όχι μέσα σε αυτό', () {
    Session hrSession(List<List<int>> hr, List<int> ticks, int reps, {String ex = 'band_pulldown'}) {
      final start = DateTime(2026, 11, 20, 18);
      return Session(id: 'h', workout: 'A', name: 'Α', programId: 'p', start: start, hr: hr, items: [
        ExLog(ex: ex, sets: ticks.length, lo: 10, hi: 15, rir: 3, rest: 90, log: [
          for (final t in ticks) SetLog(load: 20, reps: reps, done: true, at: start.millisecondsSinceEpoch + t * 1000),
        ]),
      ]);
    }

    test('σετ 15 επαναλήψεων (≈ 68″): το διάλειμμα διαβάζεται πριν ξεκινήσει το επόμενο', () {
      final hr = [
        for (var t = 0; t <= 450; t++) [t, (t >= 190 && t < 250) || (t >= 340 && t < 400) ? 135 : 100],
      ];
      final s = hrSession(hr, [250, 400], 15);
      final r = sessionSetHr(s, repSeconds: (_) => 4.5);
      expect(r[0].sets[0]!.set, 135);
      expect(r[0].sets[0]!.rest, 100, reason: 'πριν: 135 (μέσα στο επόμενο σετ)');
      expect(sessionSetHr(s)[0].sets[0]!.rest, 100, reason: 'χωρίς ρυθμό βιβλιοθήκης: 4,5″ ανά επανάληψη');
      expect(r[0].sets[1]!.rest, isNull, reason: 'τελευταίο σετ');
    });

    test('σύντομο σετ (8 × 2″): τουλάχιστον 20″', () {
      final hr = [
        for (var t = 0; t <= 450; t++) [t, (t >= 234 && t < 250) || (t >= 384 && t < 400) ? 135 : 100],
      ];
      expect(sessionSetHr(hrSession(hr, [250, 400], 8), repSeconds: (_) => 2.0)[0].sets[0]!.rest, 100);
      expect(setSeconds(8, 2.0), 20);
      expect(setSeconds(15), 67.5);
      expect(setSeconds(40), 120);
    });

    test('όρια (S12-13): διάλειμμα ακριβώς 15″ → τιμή· 14″ → «—»· μέσος με 3 τιμές, όχι με 2', () {
      final flat = [
        for (var t = 0; t <= 200; t++) [t, 100],
      ];
      // σετ 1 επανάληψης × 1″ → 20″ (το ελάχιστο): το επόμενο σετ ξεκινά 20″ πριν από το ✓ του
      expect(sessionSetHr(hrSession(flat, [60, 95], 1), repSeconds: (_) => 1.0)[0].sets[0]!.rest, 100);
      expect(sessionSetHr(hrSession(flat, [60, 94], 1), repSeconds: (_) => 1.0)[0].sets[0]!.rest, isNull);
      expect(meanIn([[0, 100], [1, 110], [2, 120]], 0, 30), 110);
      expect(meanIn([[0, 100], [1, 110]], 0, 30), isNull);
    });
  });

  // ------------------------------------------------------------------ S12-16 + S12-13: walk_stats
  group('S12-16: ένας κανόνας για παύση και έγκυρο παλμό', () {
    test('παύση [αρχή, τέλος): η τιμή στο τέλος της παύσης μετρά', () {
      expect(Session.inPause([[10, 20]], 9), isFalse);
      expect(Session.inPause([[10, 20]], 10), isTrue);
      expect(Session.inPause([[10, 20]], 19), isTrue);
      expect(Session.inPause([[10, 20]], 20), isFalse);
      final s = Session(id: 'w', workout: 'walk', name: 'Π', programId: 'p', start: now, hr: [[9, 100], [10, 101], [19, 102], [20, 103]], pauses: [[10, 20]]);
      expect(activeHr(s), [[9, 100], [20, 103]]);
      final z = zoneTimes([[0, 120], [5, 120], [10, 120]], [[5, 10]], 108, 131, endSec: 15);
      expect(z.inZone, 10);
    });

    test('παλμός άσκησης 26…249, όπως στο ρολόι', () {
      expect((TrainingStore.hrValidMin, TrainingStore.hrValidMax), (26, 249));
      var at = now;
      final t = sampleTraining(now);
      final st = TrainingStore(io: MemoryTrainingIO(), clock: () => at)..replaceAll(t.toJson());
      final s = st.start(st.program!.workout('A')!);
      for (final (sec, bpm) in [(0, 25), (10, 26), (20, 249), (30, 250)]) {
        at = now.add(Duration(seconds: sec));
        st.addHr(bpm, at);
      }
      expect(s.hr, [[10, 26], [20, 249]]);
    });

    test('όρια περπατήματος (S12-13): ρυθμός από 100 m, βήματα/λεπτό από 60″, τελευταίο κομμάτι από 50 m', () {
      Session walk({double? m, int? sec, int? steps, List<List<int>>? splits, bool gps = true}) => Session(
            id: 'w',
            workout: 'walk',
            name: 'Περπάτημα',
            programId: 'p',
            start: now,
            end: now.add(Duration(seconds: (sec ?? 0) + 20)),
            meters: m,
            steps: steps,
            cardioSec: sec,
            gps: gps,
            splits: splits,
          );
      expect(paceSecPerKm(walk(m: 99, sec: 60)), isNull);
      expect(paceSecPerKm(walk(m: 100, sec: 60)), 600);
      expect(cadence(walk(steps: 100, sec: 59)), isNull);
      expect(cadence(walk(steps: 100, sec: 60)), 100);
      expect(walkSplits(walk(m: 1049, sec: 700, splits: [[600, 610]])).length, 1);
      final last = walkSplits(walk(m: 1050, sec: 700, splits: [[600, 610]]));
      expect(last.length, 2);
      expect(last.last.partial, isTrue);
    });
  });

  // ------------------------------------------------------------------ S12-03 (Τ3)
  group('S12-03: Tanaka 208 − 0,7 × ηλικία (όχι 220 − ηλικία) σε άλλες ηλικίες', () {
    test('μέγιστοι και ζώνη', () {
      expect([tanakaMax(30), tanakaMax(50), tanakaMax(55)], [187, 173, 170]);
      final a = computeZone(age: 55, restHr: 58, s: const ZoneSettings())!;
      expect((a.lo, a.hi, a.rest, a.max), (103, 124, 58, 170));
      final b = computeZone(age: 55, restHr: null, s: const ZoneSettings())!;
      expect((b.lo, b.hi, b.rest), (109, 129, null));
      final c = computeZone(age: 30, restHr: 62, s: const ZoneSettings())!;
      expect((c.lo, c.hi, c.max), (112, 136, 187));
      final e = computeZone(restHr: 114, s: const ZoneSettings(maxHr: 135))!;
      expect((e.lo, e.hi, e.rest), (122, 126, 114));
      final f = computeZone(restHr: 115, s: const ZoneSettings(maxHr: 135))!;
      expect((f.lo, f.hi, f.rest), (86, 103, null));
      final z = zoneTimes([[0, 108], [10, 131], [20, 107], [30, 132]], [], 108, 131, endSec: 40);
      expect((z.below, z.inZone, z.above), (10, 20, 10));
    });
  });

  // ------------------------------------------------------------------ S6-10
  group('S6-10: ✓ από το ρολόι μόνο στην ίδια άσκηση', () {
    test('ξανασταλμένο ✓ για άσκηση που άλλαξε στο μεταξύ: δεν γράφεται· ίδια ή χωρίς «ex»: γράφεται', () {
      final t = sampleTraining(now);
      final s = t.start(t.program!.workout('A')!);
      final link = WearLink()..attachForTest(t);
      final e = s.items[0];
      link.apply(t, WatchCmd('tick', {'op': 'tick', 'i': 0, 's': 0, 'sid': s.id, 'ex': 'db_row', 'late': true}));
      expect(e.log[0].done, isFalse);
      link.apply(t, WatchCmd('tick', {'op': 'tick', 'i': 0, 's': 0, 'sid': s.id, 'ex': e.ex, 'late': true}));
      expect(e.log[0].done, isTrue);
      link.apply(t, WatchCmd('tick', {'op': 'tick', 'i': 0, 's': 1, 'sid': s.id, 'late': true}));
      expect(e.log[1].done, isTrue, reason: 'ρολόι παλιότερης έκδοσης: όπως πριν');
    });
  });

  // ------------------------------------------------------------------ S6-11 / S11-7
  group('S6-11 / S11-7: το ρολόι βρίσκει μόνο του τα λεπτά της εβδομάδας', () {
    test('«from» στο πάνω επίπεδο και «plan» μέσα στο «cardio»· το «minutes» μένει', () {
      final at = DateTime(2026, 11, 22, 10);
      final t = _store(() => at);
      final plan = watchPlan(t, at, watchExName);
      expect(plan['from'], '2026-11-16');
      final walk = (plan['workouts'] as List).cast<Map>().firstWhere((w) => w['id'] == 'walk');
      expect((walk['cardio'] as Map)['plan'], [20, 25, 30, 35]);
      expect((walk['cardio'] as Map)['minutes'], 20);
      expect(() => jsonEncode(plan), returnsNormally);
      // χωρίς ημερομηνία έναρξης: κανένα «from» (το ρολόι δείχνει το «minutes»)
      final noFrom = sampleTraining(now);
      noFrom.program!.from = null;
      expect(watchPlan(noFrom, now, watchExName).containsKey('from'), isFalse);
    });
  });

  // ------------------------------------------------------------------ S6-9
  group('S6-9: «Πώς ένιωσες;» μετά από «Τέλος» στο ρολόι', () {
    test('το feel της «Αποθήκευσης» γράφεται στην προπόνηση που έκλεισε το ρολόι· και αργότερα', () async {
      var at = now;
      final io = MemoryTrainingIO();
      final t = TrainingStore(io: io, clock: () => at)..replaceAll(sampleTraining(now).toJson());
      final s = t.start(t.program!.workout('A')!);
      at = now.add(const Duration(minutes: 5));
      t.tick(s.items.first, 0);
      at = now.add(const Duration(minutes: 10));
      expect(t.endFromWatch(s.id, at.millisecondsSinceEpoch), isTrue);
      expect(t.current, isNull);
      t.finish(feel: 4);
      expect(s.feel, 4);
      expect(await t.flush(), isTrue);
      final back = TrainingStore(io: io, clock: () => at);
      await back.load();
      expect(back.sessions.firstWhere((x) => x.id == s.id).feel, 4);
      t.setFeel(s, 2);
      expect(s.feel, 2);
      final stranger = Session(id: 'ξένη', workout: 'A', name: 'Α', programId: 'p', start: now);
      t.setFeel(stranger, 5);
      expect(stranger.feel, isNull);
    });
  });

  // ------------------------------------------------------------------ S6-15
  group('S6-15: οι προπονήσεις με τη σειρά της ώρας', () {
    Map<String, dynamic> walk(String id, DateTime start) => {
          'v': 1,
          'kind': 'cardio',
          'id': id,
          'w': 'walk',
          'name': 'Περπάτημα',
          'start': start.millisecondsSinceEpoch,
          'end': start.add(const Duration(minutes: 30)).millisecondsSinceEpoch,
          'cardio': {'activity': 'walk', 'sec': 1800, 'm': 2000.0, 'steps': 3000, 'gps': true},
        };

    test('«ξεχασμένη» προπόνηση που κλείνει μέρες μετά δεν μπαίνει πάνω από το περπάτημα του ενδιάμεσου', () {
      var at = now;
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => at)..replaceAll(sampleTraining(now).toJson());
      final s = t.start(t.program!.workout('A')!);
      at = now.add(const Duration(minutes: 10));
      t.tick(s.items.first, 0);
      expect(t.importWatch(walk('k1', now.add(const Duration(days: 1)))), isTrue);
      at = now.add(const Duration(days: 2));
      t.finish(end: s.lastActivity);
      final starts = [for (final x in t.sessions) x.start.millisecondsSinceEpoch];
      expect(starts, [...starts]..sort());
      expect(t.sessions.last.id, 'w-k1');
    });

    test('αρχείο με προπονήσεις εκτός σειράς (από πριν τη διόρθωση): διαβάζεται με τη σειρά', () {
      final j = jsonDecode(jsonEncode(sampleTraining(now).toJson())) as Map<String, dynamic>;
      j['sessions'] = (j['sessions'] as List).reversed.toList();
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => now)..replaceAll(j);
      final starts = [for (final x in t.sessions) x.start.millisecondsSinceEpoch];
      expect(starts, [...starts]..sort());
    });
  });

  // ------------------------------------------------------------------ S11-4
  group('S11-4: το κινητό έσβησε στη μέση, η προπόνηση τελείωσε στο ρολόι', () {
    test('«Τέλος (στις 18:35)» στο κινητό και μετά το αποτέλεσμα του ρολογιού: τέλος 19:20, κανένας παλμός δεν κόβεται', () {
      final t0 = now;
      var at = t0;
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => at)..replaceAll(sampleTraining(now).toJson());
      final s = t.start(t.program!.workout('A')!);
      at = t0.add(const Duration(minutes: 35));
      t.tick(s.items[0], 0);
      at = t0.add(const Duration(hours: 20));
      t.finish(end: s.lastActivity);
      expect(s.end, t0.add(const Duration(minutes: 35)));
      // το ρολόι: 6 ακόμα σετ (40′ … 75′), «Τέλος» στο 80′, παλμοί ανά 1″ για 80′
      final items = [for (final e in s.items) jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>];
      void wTick(int i, int k, int min) {
        final log = (items[i]['log'] as List).cast<Map<String, dynamic>>();
        log[k] = {...log[k], 'd': 1, 't': t0.add(Duration(minutes: min)).millisecondsSinceEpoch};
      }

      wTick(0, 1, 40);
      wTick(0, 2, 45);
      wTick(1, 0, 50);
      wTick(1, 1, 55);
      wTick(1, 2, 60);
      wTick(2, 0, 75);
      final fin = t0.add(const Duration(minutes: 80));
      expect(
          t.importWatch({
            'v': 1,
            'kind': 'hr',
            'sid': s.id,
            'hrT0': t0.millisecondsSinceEpoch,
            'hr': [
              for (var k = 0; k < 4800; k++) [k, 114],
            ],
            'hrAvg': 114,
            'fin': fin.millisecondsSinceEpoch,
            'items': items,
          }),
          isTrue);
      final f = t.sessions.firstWhere((x) => x.id == s.id);
      expect(f.end, fin);
      expect(f.setsDone, 7);
      expect(f.hr.length, 4800);
      expect(f.hr.last[0], 4799);
      expect(f.hrAvg, 114);
    });

    test('χωρίς ✓ του ρολογιού μετά το τέλος: το τέλος δεν αλλάζει (οι παλμοί μετά το τέλος κόβονται, DP-09)', () {
      final t0 = now;
      var at = t0;
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => at)..replaceAll(sampleTraining(now).toJson());
      final s = t.start(t.program!.workout('A')!);
      at = t0.add(const Duration(minutes: 35));
      t.tick(s.items[0], 0);
      at = t0.add(const Duration(hours: 20));
      t.finish(end: s.lastActivity);
      t.importWatch({
        'v': 1,
        'kind': 'hr',
        'sid': s.id,
        'hrT0': t0.millisecondsSinceEpoch,
        'hr': [
          for (var k = 0; k < 4800; k++) [k, 114],
        ],
        'fin': t0.add(const Duration(minutes: 80)).millisecondsSinceEpoch,
      });
      expect(s.end, t0.add(const Duration(minutes: 35)));
      expect(s.hr.last[0], 35 * 60 + 60);
    });
  });

  // ------------------------------------------------------------------ U6-01 (αίτημα του f6b, πλευρά αποθήκης)
  group('U6-01: «Σβήσιμο» χωρίς σετ στο κινητό, ενώ τα σετ έγιναν στο ρολόι', () {
    test('το αποτέλεσμα του ρολογιού που έρχεται μετά (και μετά από επανεκκίνηση) ξαναφέρνει την προπόνηση', () async {
      final t0 = now;
      var at = t0;
      final io = MemoryTrainingIO();
      final t = TrainingStore(io: io, clock: () => at)..replaceAll(sampleTraining(now).toJson());
      final s = t.start(t.program!.workout('A')!);
      final items = [for (final e in s.items) jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>];
      at = t0.add(const Duration(hours: 4));
      t.discard();
      expect(t.current, isNull);
      expect(await t.flush(), isTrue);
      // το κινητό ξανανοίγει· έρχεται το αποτέλεσμα: 2 σετ (10′, 20′), «Τέλος» στο 25′, παλμοί 25′
      final back = TrainingStore(io: io, clock: () => at);
      await back.load();
      final log = (items[0]['log'] as List).cast<Map<String, dynamic>>();
      log[0] = {...log[0], 'd': 1, 't': t0.add(const Duration(minutes: 10)).millisecondsSinceEpoch};
      log[1] = {...log[1], 'd': 1, 't': t0.add(const Duration(minutes: 20)).millisecondsSinceEpoch};
      final result = {
        'v': 1,
        'kind': 'hr',
        'sid': s.id,
        'hrT0': t0.millisecondsSinceEpoch,
        'hr': [
          for (var k = 0; k < 1500; k += 5) [k, 110],
        ],
        'fin': t0.add(const Duration(minutes: 25)).millisecondsSinceEpoch,
        'items': items,
      };
      expect(back.importWatch(result), isTrue);
      final f = back.sessions.firstWhere((x) => x.id == s.id);
      expect(f.setsDone, 2);
      expect(f.end, t0.add(const Duration(minutes: 25)));
      expect(f.hr.length, 300);
      final starts = [for (final x in back.sessions) x.start.millisecondsSinceEpoch];
      expect(starts, [...starts]..sort());
      // το ίδιο αποτέλεσμα ξανά: τίποτα διπλό
      back.importWatch(result);
      expect(back.sessions.where((x) => x.id == s.id).length, 1);
    });

    test('αποτέλεσμα χωρίς σετ και χωρίς παλμούς: τίποτα δεν ξαναμπαίνει', () {
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => now)..replaceAll(sampleTraining(now).toJson());
      final s = t.start(t.program!.workout('A')!);
      final n = t.sessions.length;
      t.discard();
      expect(t.importWatch({'v': 1, 'kind': 'hr', 'sid': s.id, 'fin': now.millisecondsSinceEpoch}), isFalse);
      expect(t.sessions.length, n);
    });
  });

  // ------------------------------------------------------------------ S11-11
  group('S11-11: «Σύνοψη για τον Claude» με ημερολογιακές μέρες', () {
    test('Δευτέρα 23:30, 8 εβδομάδες: από 21/9 (όχι 22/9), μαζί το περπάτημα της 21/9 το βράδυ', () {
      final at = DateTime(2026, 11, 16, 23, 30);
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => at)..replaceAll({'v': 1});
      final start = DateTime(2026, 9, 21, 20);
      expect(
          t.importWatch({
            'v': 1,
            'kind': 'cardio',
            'id': 'old',
            'w': 'walk',
            'name': 'Περπάτημα',
            'start': start.millisecondsSinceEpoch,
            'end': start.add(const Duration(minutes: 30)).millisecondsSinceEpoch,
            'cardio': {'activity': 'walk', 'sec': 1800, 'm': 2000.0, 'steps': 3000, 'gps': true},
          }),
          isTrue);
      final text = t.exportForClaude();
      expect(text, contains('(21/9/2026–16/11/2026)'));
      expect(text, contains('Περπάτημα: 1 φορές'));
    });
  });

  // ------------------------------------------------------------------ S6-5 / S9-9
  group('S6-5 / S9-9: αρχείο προπονήσεων που δεν διαβάζεται', () {
    test('χαλασμένο: τίποτα δεν γράφεται (και φαίνεται)· «στην άκρη» → ξανά αποθήκευση και επαναφορά', () async {
      final io = MemoryTrainingIO('{χαλασμένο');
      final t = TrainingStore(io: io, clock: () => now);
      await t.load();
      expect((t.readError, t.damaged, t.newerFile), (true, true, false));
      t.setHrLimit(150);
      await t.save();
      expect(io.json, '{χαλασμένο');
      expect(t.saveError, TrainingStore.notSavedUnreadable);
      expect(t.mergeBackup(sampleTraining(now).toJson()), 0);
      expect(t.mergeProblem, contains('Κράτα το στην άκρη'));
      expect(await t.setAsideUnreadable(), isTrue);
      expect(io.badJson, '{χαλασμένο', reason: 'κρατιέται, δεν σβήνεται');
      expect((t.readError, t.damaged, t.saveError), (false, false, null));
      expect(t.mergeBackup(sampleTraining(now).toJson()), greaterThan(0));
      expect(await t.flush(), isTrue);
      expect(io.writes, greaterThan(0));
      expect(io.json, isNot('{χαλασμένο'));
    });

    test('σφάλμα ανάγνωσης (όχι χαλασμένο): ποτέ «στην άκρη»· «Δοκίμασε ξανά» διαβάζει το αρχείο όπως είναι', () async {
      final text = jsonEncode(sampleTraining(now).toJson());
      final io = _FlakyIO(text);
      final t = TrainingStore(io: io, clock: () => now);
      await t.load();
      expect((t.readError, t.damaged), (true, false));
      expect(await t.setAsideUnreadable(), isFalse);
      expect(io.json, text);
      io.fail = false;
      await t.retryLoad();
      expect(t.readError, isFalse);
      expect(t.sessions.length, 2);
      expect(t.program, isNotNull);
    });

    test('νεότερη έκδοση: ούτε «στην άκρη»', () async {
      final io = MemoryTrainingIO(jsonEncode({'v': 99, 'sessions': []}));
      final t = TrainingStore(io: io, clock: () => now);
      await t.load();
      expect((t.readError, t.newerFile, t.damaged), (true, true, false));
      expect(await t.setAsideUnreadable(), isFalse);
      expect(io.badJson, isNull);
    });

    testWidgets('η σελίδα: μόνο η κάρτα σφάλματος, καμία «Ελεύθερη άσκηση» ή επικόλληση· μετά το «στην άκρη», κανονικά', (tester) async {
      ExClock.frozen = true;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 2400);
      addTearDown(tester.view.reset);
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final io = MemoryTrainingIO('{χαλασμένο');
      final t = TrainingStore(io: io, clock: () => now);
      await tester.runAsync(() => t.load());
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: TrainingPage(training: t, now: now))));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('train-read-error')), findsOneWidget);
      expect(find.text('Το αρχείο προπονήσεων χάλασε'), findsOneWidget);
      expect(find.byKey(const ValueKey('train-free')), findsNothing);
      expect(find.byKey(const ValueKey('train-paste')), findsNothing);
      await tester.tap(find.text('Κράτα το στην άκρη και συνέχισε'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('train-set-aside-ok')));
      await tester.pumpAndSettle();
      expect(t.readError, isFalse);
      expect(io.badJson, '{χαλασμένο');
      expect(find.byKey(const ValueKey('train-read-error')), findsNothing);
      expect(find.byKey(const ValueKey('train-paste')), findsOneWidget);
      expect(find.byKey(const ValueKey('train-free')), findsOneWidget);
    });
  });
}
