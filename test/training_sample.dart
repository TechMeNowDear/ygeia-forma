// Δοκιμαστικό πρόγραμμα (όπως θα το έδινε ο Claude) και ιστορικό για τα τεστ και τα στιγμιότυπα.
import 'dart:convert';

import 'package:ygeia_forma/training/program.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/training_store.dart';

const sampleProgramText = '''
Ορίστε το πρόγραμμα. Αντέγραψε όλο το κομμάτι από κάτω:
```json
{"kind":"ygeia-program","v":1,"id":"p-claude-1","name":"Πρόγραμμα 1","author":"claude","from":"2026-11-13",
 "note":"Έμφαση: στήθος, χέρια, κοιλιακοί. Πλάτη και πόδια για ισορροπία.",
 "days":{"fri":"A","sat":"B","sun":"A","mon":"B","tue":"walk","wed":"walk","thu":"walk"},
 "workouts":[
  {"id":"A","name":"Προπόνηση Α","items":[
    {"ex":"db_press","sets":3,"reps":[8,12],"rir":2,"rest":120,"load":9.3},
    {"ex":"db_row","sets":3,"reps":[8,12],"rir":2,"rest":90,"load":14.3},
    {"ex":"goblet","sets":3,"reps":[8,12],"rir":2,"rest":120,"load":12},
    {"ex":"incline_curl","sets":3,"reps":[10,15],"rir":2,"rest":75,"load":5.3},
    {"ex":"band_pushdown","sets":3,"reps":[12,15],"rir":2,"rest":60,"load":30},
    {"ex":"reverse_crunch","sets":3,"reps":[10,15],"rir":2,"rest":60}]},
  {"id":"B","name":"Προπόνηση Β","items":[
    {"ex":"incline_press","sets":3,"reps":[8,12],"rir":2,"rest":120,"load":7.8},
    {"ex":"band_pulldown","sets":3,"reps":[10,15],"rir":2,"rest":90,"load":40},
    {"ex":"rdl","sets":3,"reps":[8,12],"rir":2,"rest":120,"load":20},
    {"ex":"hammer_curl","sets":3,"reps":[10,15],"rir":2,"rest":75,"load":6.8},
    {"ex":"lying_ext","sets":3,"reps":[10,15],"rir":2,"rest":75,"load":4.3},
    {"ex":"pushup_bench","sets":2,"reps":[10,15],"rir":2,"rest":60,"next":"pushup_handles"},
    {"ex":"ab_wheel","sets":3,"reps":[6,10],"rir":2,"rest":60}]},
  {"id":"walk","name":"Περπάτημα","cardio":{"activity":"walk","minutes":30,"note":"χαλαρά, να μπορείς να μιλάς"}}
 ]}
```
''';

Program sampleProgram() => Program.fromJson(jsonDecode(sampleProgramText.substring(sampleProgramText.indexOf('{'), sampleProgramText.lastIndexOf('}') + 1)) as Map<String, dynamic>);

/// Αποθήκη με εγκεκριμένη άσκηση, το δοκιμαστικό πρόγραμμα και δύο προηγούμενες προπονήσεις Α.
TrainingStore sampleTraining(DateTime now, {bool approved = true, bool program = true, bool history = true}) {
  final store = TrainingStore(io: MemoryTrainingIO(), clock: () => now);
  final j = <String, dynamic>{'v': 1, 'approved': approved, if (approved) 'hrLimit': 140};
  if (program) {
    final p = sampleProgram()
      ..version = 1
      ..savedAt = now.subtract(const Duration(days: 20));
    j['programs'] = [p.toJson()];
    j['active'] = p.id;
  }
  if (history) {
    Session a(int daysAgo, List<int> press, int rir) => Session(
          id: 's$daysAgo',
          workout: 'A',
          name: 'Προπόνηση Α',
          programId: 'p-claude-1',
          start: now.subtract(Duration(days: daysAgo, hours: 1)),
          end: now.subtract(Duration(days: daysAgo)),
          feel: 3,
          items: [
            ExLog(ex: 'db_press', sets: 3, lo: 8, hi: 12, rir: 2, rest: 120, rirAnswer: rir, log: [for (final r in press) SetLog(load: 9.3, reps: r, done: true)]),
            ExLog(ex: 'db_row', sets: 3, lo: 8, hi: 12, rir: 2, rest: 90, rirAnswer: 2, log: [for (final r in [10, 10, 9]) SetLog(load: 14.3, reps: r, done: true)]),
            ExLog(ex: 'goblet', sets: 3, lo: 8, hi: 12, rir: 2, rest: 120, rirAnswer: 3, log: [for (final r in [12, 12, 12]) SetLog(load: 12, reps: r, done: true)]),
            ExLog(ex: 'incline_curl', sets: 3, lo: 10, hi: 15, rir: 2, rest: 75, rirAnswer: 2, log: [for (final r in [12, 11, 11]) SetLog(load: 5.3, reps: r, done: true)]),
            ExLog(ex: 'band_pushdown', sets: 3, lo: 12, hi: 15, rir: 2, rest: 60, rirAnswer: 2, pain: ['elbow'], log: [for (final r in [14, 14, 13]) SetLog(load: 30, reps: r, done: true)]),
            ExLog(ex: 'reverse_crunch', sets: 3, lo: 10, hi: 15, rir: 2, rest: 60, rirAnswer: 2, log: [for (final r in [12, 12, 11]) SetLog(reps: r, done: true)]),
          ],
        );
    j['sessions'] = [a(9, [11, 10, 10], 2).toJson(), a(2, [12, 12, 12], 2).toJson()];
  }
  store.replaceAll(j);
  store.ready = true;
  return store;
}
