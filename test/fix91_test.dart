// Έκδοση #91 (έλεγχος 9/11): «ένα περπάτημα ή μια προπόνηση ποτέ δεν χάνεται, ποτέ δεν μπαίνει διπλό, ποτέ δεν ανακατεύεται»,
// και το αρχείο αντέχει χρόνια. V-A-02 παλμοί σε δικά τους αρχεία (μεταφορά, αντίγραφα, διαγραφή) · V-A-06 όριο που
// επιβεβαιώνει το ρολόι · V-A-07 άγνωστα κλειδιά μένουν · V-A-08 έκδοση μορφής · V-A-09 «Τέλος» στο ρολόι και ξεχασμένη
// προπόνηση · V-A-10 καραντίνα αντί για «δεν διαβάζεται» · V-A-11 δεύτερο «Παλμοί εδώ» · V-A-14 το τελικό κερδίζει.
// Όλα τα νούμερα είναι δοκιμαστικά.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/backup.dart';
import 'package:ygeia_forma/exercise/ex_data.dart';
import 'package:ygeia_forma/exercise/ex_player.dart';
import 'package:ygeia_forma/pages/training/session_page.dart';
import 'package:ygeia_forma/pages/training/training_page.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/training/hr_file.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/training_store.dart';
import 'package:ygeia_forma/training/wear_link.dart';

import 'training_sample.dart';

final now = DateTime(2026, 11, 20, 18, 0);

/// Αρχείο προπονήσεων όπως το έγραφε η #90: οι παλμοί μέσα σε κάθε προπόνηση.
Map<String, dynamic> _oldFile() {
  final t = sampleTraining(now);
  final j = jsonDecode(jsonEncode(t.toJson())) as Map<String, dynamic>;
  j['v'] = 1;
  final start = now.subtract(const Duration(days: 1)).millisecondsSinceEpoch;
  (j['sessions'] as List).add({
    'id': 'w-walk$start',
    'w': 'walk',
    'name': 'Περπάτημα',
    'prog': '',
    'start': start,
    'end': start + 1800 * 1000,
    'items': [],
    'cmin': 30,
    'hrAvg': 105,
    'hrMax': 121,
    'src': 'watch',
    'hr': [
      for (var s = 0; s < 1800; s++) [s, 100 + s % 22],
    ],
  });
  return j;
}

/// Περπάτημα από το ρολόι, όπως το στέλνει (Protocol.kt).
Map<String, dynamic> _walk(String id, {int start0 = 0, int sec = 1800, bool partial = false}) {
  final start = start0 == 0 ? now.subtract(const Duration(hours: 5)).millisecondsSinceEpoch : start0;
  return {
    'v': 1,
    'kind': 'cardio',
    'id': id,
    'w': 'walk',
    'name': 'Περπάτημα',
    'start': start,
    'end': start + (sec + 30) * 1000,
    'hrAvg': 110,
    'hrMax': 130,
    'hrT0': start,
    'hr': [
      for (var t = 0; t <= sec; t++) [t, 100 + t % 31],
    ],
    'cardio': {'activity': 'walk', 'sec': sec, 'm': sec * 1.3, 'steps': sec * 2, 'gps': true},
    'lim': 0,
    if (partial) 'partial': 1,
  };
}

/// IO χωρίς αρχεία παλμών (π.χ. γεμάτος δίσκος για αυτά): οι παλμοί μένουν μέσα στο training.json, όπως ως #90.
class _NoHrIO extends MemoryTrainingIO {
  @override
  Future<bool> writeHr(String id, String j) async => false;
}

/// Αρχείο παλμών που υπάρχει αλλά δεν διαβάζεται τώρα.
class _HrReadErrorIO extends MemoryTrainingIO {
  bool fail = true;
  @override
  Future<({String state, String? json})> readHr(String id) async => fail ? (state: 'error', json: null) : super.readHr(id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('V-A-02: συμπαγής μορφή παλμών', () {
    test('μπρος-πίσω χωρίς απώλεια, με κενά, ανακατεμένη σειρά, αρνητικά δευτερόλεπτα', () {
      final hr = [
        [5, 120],
        [-3, 90],
        [0, 100],
        [100000, 140],
        [6, 121],
        [6, 122],
      ];
      final back = decodeHr(encodeHr(hr));
      expect(back, sortedHr(hr));
      expect(decodeHr(encodeHr(const [])), isEmpty);
      // Περίπου 2,7 bytes ανά τιμή αντί για ~10.
      final walk = [for (var s = 0; s < 3600; s++) [s, 100 + s % 40]];
      expect(encodeHr(walk).length, lessThan(jsonEncode(walk).length ~/ 3));
      expect(decodeHr(encodeHr(walk)), walk);
    });

    test('χαλασμένο ή νεότερο αρχείο: κενό (το αρχείο μένει όπως είναι)· και η παλιά μορφή «[[sec,bpm]]»', () {
      expect(decodeHr('{χαλασμένο'), isEmpty);
      expect(decodeHr(null), isEmpty);
      expect(decodeHr(jsonEncode({'v': 9, 'n': 1, 's0': 0, 'e': 'AGQ='})), isEmpty);
      expect(decodeHr('[[0,100],[1,101],["x",1]]'), [
        [0, 100],
        [1, 101],
      ]);
    });
  });

  group('V-A-02: οι παλμοί σε δικά τους αρχεία', () {
    test('μεταφορά: τα παλιά «hr» φεύγουν από το training.json χωρίς απώλεια, και ξαναδιαβάζονται', () async {
      final io = MemoryTrainingIO(jsonEncode(_oldFile()));
      final t = TrainingStore(io: io, clock: () => now);
      await t.load();
      expect(await t.flush(), isTrue);
      final walk = t.sessions.firstWhere((s) => s.isCardio);
      expect(io.hrFiles.keys, [walk.id]);
      final j = jsonDecode(io.json!) as Map<String, dynamic>;
      expect(j['v'], TrainingStore.fileVersion);
      final saved = (j['sessions'] as List).cast<Map<String, dynamic>>().firstWhere((s) => s['id'] == walk.id);
      expect(saved.containsKey('hr'), isFalse);
      expect(saved['hrf'], 1800);
      expect(saved['hrAvg'], 105, reason: 'ο μέσος και ο υψηλότερος μένουν μέσα');
      // Έφυγαν από τη μνήμη· φορτώνονται μόνο όταν τους χρειαστεί μια σύνοψη.
      expect(walk.hrLoaded, isFalse);
      expect(walk.hasHr, isTrue);
      await t.ensureHr(walk);
      expect(walk.hr.length, 1800);
      expect(walk.hr[37], [37, 100 + 37 % 22]);
      // Ξανά από την αρχή: ίδιο αποτέλεσμα, και το αρχείο είναι πολύ μικρότερο.
      final back = TrainingStore(io: io, clock: () => now);
      await back.load();
      final w2 = back.sessions.firstWhere((s) => s.isCardio);
      expect(w2.hrLoaded, isFalse);
      await back.ensureHr(w2);
      expect(w2.hr, walk.hr);
      expect(io.json!.length, lessThan(jsonEncode(_oldFile()).length ~/ 2));
    });

    test('η παλιά μορφή διαβάζεται πάντα· χωρίς αρχεία παλμών μένουν μέσα (καμία απώλεια)', () async {
      final io = _NoHrIO()..json = jsonEncode(_oldFile());
      final t = TrainingStore(io: io, clock: () => now);
      await t.load();
      expect(await t.flush(), isTrue);
      final saved = ((jsonDecode(io.json!) as Map)['sessions'] as List).cast<Map>().firstWhere((s) => s['src'] == 'watch');
      expect((saved['hr'] as List).length, 1800);
      expect(saved.containsKey('hrf'), isFalse);
    });

    test('νέο περπάτημα: οι παλμοί γράφονται μία φορά· ένα ✓ μετά δεν τους ξαναγράφει', () async {
      final io = MemoryTrainingIO();
      final t = TrainingStore(io: io, clock: () => now);
      await t.load();
      t.replaceAll(sampleTraining(now).toJson());
      expect(t.importWatch(_walk('k1')), isTrue);
      expect(await t.flush(), isTrue);
      expect(io.hrFiles.keys, ['w-k1']);
      expect(io.json, isNot(contains('"hr":[')));
      final writes = io.hrWrites;
      final s = t.start(t.program!.workout('A')!);
      t.tick(s.items.first, 0);
      await t.flush();
      expect(io.hrWrites, writes, reason: 'οι παλμοί του περπατήματος δεν ξανακωδικοποιούνται σε κάθε ✓');
      expect(io.json, isNot(contains('"hr":[')));
    });

    test('πολλές αλλαγές μαζί: λιγότερες εγγραφές, τίποτα δεν χάνεται', () async {
      final io = MemoryTrainingIO();
      final t = TrainingStore(io: io, clock: () => now);
      await t.load();
      t.replaceAll(sampleTraining(now).toJson());
      final s = t.start(t.program!.workout('A')!);
      final before = io.writes;
      for (var i = 0; i < 3; i++) {
        t.tick(s.items.first, i);
      }
      t.answer(s.items.first, 2);
      expect(await t.flush(), isTrue);
      expect(io.writes - before, lessThan(5));
      final back = TrainingStore(io: io, clock: () => now);
      await back.load();
      expect(back.current!.items.first.done.length, 3);
      expect(back.current!.items.first.rirAnswer, 2);
    });

    test('αντίγραφο (εξαγωγή/επαναφορά): οι παλμοί πάνε μαζί και γράφονται στο νέο κινητό', () async {
      final io = MemoryTrainingIO(jsonEncode(_oldFile()));
      final src = TrainingStore(io: io, clock: () => now);
      await src.load();
      await src.flush();
      final walk = src.sessions.firstWhere((s) => s.isCardio);
      expect(walk.hrLoaded, isFalse);
      final b = parseBackup(buildBackup(foodLog: const [], myFoods: const [], prefs: const {}, now: now, training: await src.backupJson()));
      final io2 = MemoryTrainingIO();
      final fresh = TrainingStore(io: io2, clock: () => now);
      await fresh.load();
      expect(fresh.mergeBackup(b.training!), src.sessions.length);
      expect(fresh.mergeProblem, isNull);
      expect(await fresh.flush(), isTrue);
      expect(io2.hrFiles.keys, [walk.id]);
      final w2 = fresh.sessions.firstWhere((s) => s.isCardio);
      await fresh.ensureHr(w2);
      expect(w2.hr.length, 1800);
      // Αντίγραφο της #90 (παλμοί μέσα): το ίδιο.
      final io3 = MemoryTrainingIO();
      final f3 = TrainingStore(io: io3, clock: () => now);
      await f3.load();
      expect(f3.mergeBackup(_oldFile()), src.sessions.length);
      await f3.flush();
      expect(io3.hrFiles.keys, [walk.id]);
    });

    test('διαγραφή: το αρχείο παλμών σβήνεται (στο επόμενο άνοιγμα)· με «Αναίρεση» πριν, μένει', () async {
      final io = MemoryTrainingIO();
      final t = TrainingStore(io: io, clock: () => now);
      await t.load();
      t.importWatch(_walk('k1'));
      t.importWatch(_walk('k2', start0: now.subtract(const Duration(hours: 3)).millisecondsSinceEpoch));
      await t.flush();
      expect(io.hrFiles.keys.toSet(), {'w-k1', 'w-k2'});
      final gone = t.deleteSession('w-k1')!;
      final undo = t.deleteSession('w-k2')!;
      t.undoDelete(undo);
      await t.flush();
      final back = TrainingStore(io: io, clock: () => now);
      await back.load();
      await back.flush();
      expect(io.hrFiles.keys, ['w-k2']);
      expect(back.deleted, contains(gone.id));
      final k2 = back.sessions.single;
      await back.ensureHr(k2);
      expect(k2.hr.length, 1801);
    });
  });

  group('V-A-07 / V-A-10: άγνωστα κλειδιά μένουν· μία χαλασμένη προπόνηση δεν κλειδώνει όλες', () {
    test('κλειδιά άλλης έκδοσης (αρχείο, προπόνηση, άσκηση, σετ) ξαναγράφονται αυτούσια', () async {
      final j = jsonDecode(jsonEncode(sampleTraining(now).toJson())) as Map<String, dynamic>;
      j['sym'] = [
        {'at': 1, 'code': 'x'},
      ];
      j['limits'] = 'κείμενο γιατρού';
      final s0 = (j['sessions'] as List).first as Map<String, dynamic>;
      s0['future'] = {'a': 1};
      s0['gps'] = 1; // λάθος τύπος: μένει όπως ήταν
      final e0 = (s0['items'] as List).first as Map<String, dynamic>;
      e0['tempo'] = '3-1-1';
      ((e0['log'] as List).first as Map<String, dynamic>)['rpe'] = 8;
      final io = MemoryTrainingIO(jsonEncode(j));
      final t = TrainingStore(io: io, clock: () => now);
      await t.load();
      expect(t.readError, isFalse);
      t.setHrLimit(150);
      await t.flush();
      final out = jsonDecode(io.json!) as Map<String, dynamic>;
      expect(out['sym'], j['sym']);
      expect(out['limits'], 'κείμενο γιατρού');
      expect(out['hrLimit'], 150);
      final o0 = (out['sessions'] as List).first as Map<String, dynamic>;
      expect(o0['future'], {'a': 1});
      expect(o0['gps'], 1);
      final oe = (o0['items'] as List).first as Map<String, dynamic>;
      expect(oe['tempo'], '3-1-1');
      expect(((oe['log'] as List).first as Map)['rpe'], 8);
    });

    test('χαλασμένη προπόνηση/πρόγραμμα: σε καραντίνα (κρατιέται στο αρχείο), οι άλλες διαβάζονται και γράφονται', () async {
      final j = jsonDecode(jsonEncode(sampleTraining(now).toJson())) as Map<String, dynamic>;
      (j['sessions'] as List).add({'id': 'κακή', 'start': 'χθες'});
      (j['sessions'] as List).add('όχι αντικείμενο');
      (j['programs'] as List).add({'id': 'px', 'workouts': 'όχι λίστα'});
      final io = MemoryTrainingIO(jsonEncode(j));
      final t = TrainingStore(io: io, clock: () => now);
      await t.load();
      expect(t.readError, isFalse);
      expect(t.sessions.length, 2);
      expect(t.program, isNotNull);
      expect(t.quarantine.length, 3);
      t.setHrLimit(130);
      expect(await t.flush(), isTrue);
      final back = TrainingStore(io: io, clock: () => now);
      await back.load();
      expect(back.quarantine.length, 3, reason: 'δεν χάθηκαν');
      expect(back.hrLimit, 130);
      expect((jsonDecode(io.json!) as Map)['bad'], isA<List>());
    });

    test('αρχείο νεότερης έκδοσης: μόνο ανάγνωση, τίποτα δεν γράφεται, η επαναφορά λέει γιατί', () async {
      final text = jsonEncode({'v': 99, 'sessions': []});
      final io = MemoryTrainingIO(text);
      final t = TrainingStore(io: io, clock: () => now);
      await t.load();
      expect(t.readError, isTrue);
      expect(t.newerFile, isTrue);
      t.setHrLimit(120);
      await t.save();
      expect(io.json, text);
      expect(t.mergeBackup(sampleTraining(now).toJson()), 0);
      expect(t.mergeProblem, contains('νεότερη έκδοση'));
    });

    test('επαναφορά: ποτέ σιωπηλή άρνηση', () async {
      final bad = TrainingStore(io: MemoryTrainingIO('{χαλασμένο'), clock: () => now);
      await bad.load();
      expect(bad.mergeBackup(sampleTraining(now).toJson()), 0);
      expect(bad.mergeProblem, contains('δεν διαβάζεται'));
      final ok = TrainingStore(io: MemoryTrainingIO(), clock: () => now);
      await ok.load();
      final b = jsonDecode(jsonEncode(sampleTraining(now).toJson())) as Map<String, dynamic>;
      (b['sessions'] as List).add({'id': 'x'});
      expect(ok.mergeBackup(b), 2);
      expect(ok.mergeProblem, contains('δεν διαβάστηκε'));
      expect(ok.quarantine.length, 1);
      final newer = TrainingStore(io: MemoryTrainingIO(), clock: () => now);
      await newer.load();
      expect(newer.mergeBackup({'v': 99}), 0);
      expect(newer.mergeProblem, contains('νεότερη'));
    });
  });

  group('V-A-08: έκδοση μορφής ρολογιού ↔ κινητού', () {
    test('αποτέλεσμα νεότερης μορφής: ούτε εισάγεται ούτε σβήνεται από το ρολόι', () async {
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => now);
      await t.load();
      var newer = false;
      final r = _walk('n1')..['v'] = 2;
      expect(await WearLink.importDurably(t, jsonEncode(r), onNewer: () => newer = true), isFalse);
      expect(newer, isTrue);
      expect(t.sessions, isEmpty);
      expect(await WearLink.importDurably(t, jsonEncode(_walk('n1'))), isTrue);
    });

    test('εντολή νεότερης μορφής δεν εκτελείται· η προπόνηση πάει στο ρολόι με «v»', () {
      final t = sampleTraining(now);
      final link = WearLink()..attachForTest(t);
      final s = t.start(t.program!.workout('A')!);
      link.handle('/ygeia/cmd', {'v': 2, 'op': 'tick', 'i': 0, 's': 0, 'sid': s.id});
      expect(s.items.first.log.first.done, isFalse);
      link.handle('/ygeia/cmd', {'v': 1, 'op': 'tick', 'i': 0, 's': 0, 'sid': s.id});
      expect(s.items.first.log.first.done, isTrue);
      expect(watchSession(t, (x) => x)['v'], 1);
    });
  });

  group('V-A-11: δεύτερο «Παλμοί εδώ» στην ίδια προπόνηση', () {
    Map<String, dynamic> seg(String sid, DateTime t0, int from, int to, int bpm) => {
          'v': 1,
          'kind': 'hr',
          'id': 'hr$sid-${t0.millisecondsSinceEpoch}',
          'sid': sid,
          'hrT0': t0.millisecondsSinceEpoch,
          'hrAvg': bpm,
          'hrMax': bpm + 5,
          'hr': [
            for (var s = from; s <= to; s++) [s, bpm + (s % 2) * 2],
          ],
        };

    test('τα δύο κομμάτια ενώνονται (με όποια σειρά κι αν φτάσουν)· ο μέσος από όλες τις τιμές', () {
      for (final reversed in [false, true]) {
        final t = sampleTraining(now);
        final s = t.start(t.program!.workout('A')!);
        // ζωντανοί παλμοί ανά 10″ κατά το 1ο κομμάτι
        for (var i = 0; i < 12; i++) {
          t.addHr(125, s.start.add(Duration(seconds: 10 * i)), sid: s.id);
        }
        final a = seg(s.id, s.start, 0, 1199, 130);
        final b = seg(s.id, s.start.add(const Duration(minutes: 30)), 0, 1799, 100);
        for (final x in reversed ? [b, a] : [a, b]) {
          expect(t.importWatch(x), isTrue);
        }
        expect(s.hr.first[0], 0, reason: 'το 1ο κομμάτι δεν χάθηκε (reversed=$reversed)');
        expect(s.hr.last[0], 1800 + 1799);
        expect(s.hr.length, 1200 + 1800, reason: 'οι ζωντανοί ανά 10″ έδωσαν τη θέση τους στις τιμές ανά 1″');
        final mean = (s.hr.fold<int>(0, (x, p) => x + p[1]) / s.hr.length).round();
        expect(s.hrAvg, mean);
        expect(s.hrAvg, inInclusiveRange(110, 115));
        expect(s.hrMax, 135);
        // το ίδιο κομμάτι ξανά (ack που δεν έφτασε): τίποτα διπλό
        t.importWatch(a);
        expect(s.hr.length, 3000);
      }
    });

    test('σε τελειωμένη προπόνηση με τους παλμούς στο αρχείο τους: ένωση στην εγγραφή, χωρίς απώλεια', () async {
      final io = MemoryTrainingIO();
      var at = now;
      final t = TrainingStore(io: io, clock: () => at)..replaceAll(sampleTraining(now).toJson());
      await t.load();
      final s = t.start(t.program!.workout('A')!);
      t.tick(s.items.first, 0);
      at = now.add(const Duration(minutes: 60));
      t.finish();
      expect(t.importWatch(seg(s.id, s.start, 0, 1199, 130)), isTrue);
      expect(await t.flush(), isTrue);
      // ξανά από την αρχή: οι παλμοί είναι μόνο στο αρχείο
      final back = TrainingStore(io: io, clock: () => at);
      await back.load();
      final f = back.sessions.firstWhere((x) => x.id == s.id);
      expect(f.hrLoaded, isFalse);
      expect(back.importWatch(seg(s.id, s.start.add(const Duration(minutes: 30)), 0, 1799, 100)), isTrue);
      expect(await back.flush(), isTrue);
      await back.ensureHr(f);
      expect(f.hr.length, 3000);
      expect(f.hr.first[0], 0);
    });

    test('αρχείο παλμών που δεν διαβάζεται τώρα: κανένα ack (το κομμάτι μένει στο ρολόι), μετά κανονικά', () async {
      final io = _HrReadErrorIO();
      var at = now;
      final t = TrainingStore(io: io, clock: () => at)..replaceAll(sampleTraining(now).toJson());
      await t.load();
      final s = t.start(t.program!.workout('A')!);
      t.tick(s.items.first, 0);
      at = now.add(const Duration(minutes: 30));
      t.finish();
      t.importWatch(seg(s.id, s.start, 0, 99, 130));
      await t.flush();
      final back = TrainingStore(io: io, clock: () => at);
      await back.load();
      expect(await WearLink.importDurably(back, jsonEncode(seg(s.id, s.start.add(const Duration(minutes: 2)), 0, 99, 100))), isFalse);
      io.fail = false;
      expect(await back.flush(), isTrue);
      final f = back.sessions.firstWhere((x) => x.id == s.id);
      await back.ensureHr(f);
      expect(f.hr.length, 200);
    });
  });

  group('V-A-14 / V-A-03: μερικό αποτέλεσμα και «το τελικό κερδίζει»', () {
    test('μερικό, μετά το κανονικό με το ίδιο id: το κανονικό το αντικαθιστά (μία προπόνηση)', () {
      final t = sampleTraining(now);
      final start = now.subtract(const Duration(hours: 4)).millisecondsSinceEpoch;
      expect(t.importWatch(_walk('walkA', start0: start, sec: 900, partial: true)), isTrue);
      final p = t.sessions.firstWhere((s) => s.id == 'w-walkA');
      expect(p.partial, isTrue);
      expect(t.importWatch(_walk('walkA', start0: start, sec: 1800)), isTrue);
      final f = t.sessions.where((s) => s.id == 'w-walkA').toList();
      expect(f.length, 1);
      expect(f.single.partial, isFalse);
      expect(f.single.cardioSec, 1800);
      // και ξανά το μερικό (π.χ. καθυστερημένο): αγνοείται
      expect(t.importWatch(_walk('walkA', start0: start, sec: 900, partial: true)), isFalse);
      expect(t.sessions.firstWhere((s) => s.id == 'w-walkA').cardioSec, 1800);
      // ίδιο κανονικό ξανά: τίποτα
      expect(t.importWatch(_walk('walkA', start0: start, sec: 1800)), isFalse);
    });

    test('μερικό ξαναγράφεται και διαβάζεται· η σύνοψη το λέει', (/* καθαρό */) async {
      final io = MemoryTrainingIO();
      final t = TrainingStore(io: io, clock: () => now);
      await t.load();
      t.importWatch(_walk('walkB', sec: 600, partial: true));
      await t.flush();
      final back = TrainingStore(io: io, clock: () => now);
      await back.load();
      expect(back.sessions.single.partial, isTrue);
    });
  });

  group('V-A-09: «Τέλος» στο ρολόι και ξεχασμένη προπόνηση', () {
    test('εντολή «end» από το ρολόι: η προπόνηση κλείνει με την ώρα του ρολογιού', () {
      var at = now;
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => at)..replaceAll(sampleTraining(now).toJson());
      final link = WearLink()..attachForTest(t);
      final s = t.start(t.program!.workout('A')!);
      // κανένα σετ: μένει ανοιχτή (αποφασίζεις εσύ)
      link.handle('/ygeia/cmd', {'v': 1, 'op': 'end', 'sid': s.id, 'at': now.add(const Duration(minutes: 1)).millisecondsSinceEpoch});
      expect(t.current, isNotNull);
      at = now.add(const Duration(minutes: 5));
      t.tick(s.items.first, 0);
      at = now.add(const Duration(minutes: 50));
      final end = now.add(const Duration(minutes: 40));
      link.handle('/ygeia/cmd', {'v': 1, 'op': 'end', 'sid': s.id, 'at': end.millisecondsSinceEpoch});
      expect(t.current, isNull);
      expect(t.sessions.last.id, s.id);
      expect(t.sessions.last.end, end);
      expect(t.endedByWatch, same(s));
    });

    test('«fin» στο αποτέλεσμα (το κινητό ήταν κλειστό)· όχι αν συνέχισες στο κινητό μετά', () {
      var at = now;
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => at)..replaceAll(sampleTraining(now).toJson());
      final s = t.start(t.program!.workout('A')!);
      at = now.add(const Duration(minutes: 20));
      t.tick(s.items.first, 0);
      at = now.add(const Duration(minutes: 30));
      t.tick(s.items.first, 1);
      // «Τέλος» στο ρολόι στο 10′, αλλά στο κινητό συνέχισε ως το 30′: δεν κλείνει
      t.importWatch({'v': 1, 'kind': 'hr', 'sid': s.id, 'fin': now.add(const Duration(minutes: 10)).millisecondsSinceEpoch});
      expect(t.current, isNotNull);
      at = now.add(const Duration(hours: 9));
      final fin = now.add(const Duration(minutes: 31));
      t.importWatch({'v': 1, 'kind': 'hr', 'sid': s.id, 'fin': fin.millisecondsSinceEpoch});
      expect(t.current, isNull);
      expect(t.sessions.last.end, fin);
    });

    test('ξεχασμένη: «Τέλος» στο τελευταίο ✓, ποτέ 20 ώρες', () {
      var at = now;
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => at)..replaceAll(sampleTraining(now).toJson());
      final s = t.start(t.program!.workout('A')!);
      at = now.add(const Duration(minutes: 52));
      t.tick(s.items.first, 0);
      expect(s.lastActivity, at);
      at = now.add(const Duration(hours: 2));
      expect(t.isStale(s), isFalse);
      at = now.add(const Duration(hours: 20));
      expect(t.isStale(s), isTrue);
      t.finish();
      expect(t.sessions.last.duration, const Duration(minutes: 52));
    });

    testWidgets('κάρτα «Ξεχασμένη προπόνηση;» με ένα πάτημα «Τέλος (στις 18:52)»', (tester) async {
      ExClock.frozen = true;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 1400);
      addTearDown(tester.view.reset);
      await tester.runAsync(() => ExLibrary.load(inline: true));
      var at = now;
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => at)..replaceAll(sampleTraining(now).toJson());
      t.ready = true;
      final s = t.start(t.program!.workout('A')!);
      at = now.add(const Duration(minutes: 52));
      t.tick(s.items.first, 0);
      at = now.add(const Duration(hours: 21));
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: TrainingPage(training: t, now: at))));
      await tester.pumpAndSettle();
      expect(find.text('Ξεχασμένη προπόνηση;'), findsOneWidget);
      expect(find.textContaining('Τελευταίο σετ στις 18:52'), findsOneWidget);
      expect(find.byKey(const ValueKey('train-resume')), findsNothing);
      await tester.tap(find.text('Τέλος (στις 18:52)'));
      await tester.pumpAndSettle();
      expect(t.current, isNull);
      expect(t.sessions.last.end, now.add(const Duration(minutes: 52)));
      expect(find.text('Ξεχασμένη προπόνηση;'), findsNothing);
    });

    testWidgets('η οθόνη της προπόνησης πάει στη σύνοψη όταν το ρολόι την κλείσει', (tester) async {
      ExClock.frozen = true;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 1200);
      addTearDown(tester.view.reset);
      await tester.runAsync(() => ExLibrary.load(inline: true));
      var at = now;
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => at)..replaceAll(sampleTraining(now).toJson());
      t.ready = true;
      final s = t.start(t.program!.workout('A')!);
      at = now.add(const Duration(minutes: 3));
      t.tick(s.items.first, 0);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: SessionPage(training: t)));
      await tester.pump();
      t.endFromWatch(s.id, now.add(const Duration(minutes: 4)).millisecondsSinceEpoch);
      await tester.pumpAndSettle();
      expect(find.byType(SummaryPage), findsOneWidget);
      expect(t.endedByWatch, isNull);
    });
  });

  group('V-A-06: όριο που φτάνει στο ρολόι', () {
    const ch = MethodChannel('test/wear-known');
    test('ρολόι γνωστό αλλά μακριά: το όριο γράφεται (DataItem) και φτάνει μόλις συνδεθούν', () async {
      var puts = 0;
      final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      m.setMockMethodCallHandler(ch, (call) async {
        switch (call.method) {
          case 'status':
            return {'nodes': 0, 'app': 0, 'known': 1};
          case 'watchState':
            return '{"v":1,"lim":130,"planAt":0}';
          case 'takeResults':
            return <Object>[];
          case 'putPlan':
            puts++;
            return true;
        }
        return true;
      });
      const events = MethodChannel('test/wear-known-events');
      m.setMockMethodCallHandler(events, (call) async => null);
      addTearDown(() {
        m.setMockMethodCallHandler(ch, null);
        m.setMockMethodCallHandler(events, null);
      });
      final t = sampleTraining(now);
      final link = WearLink(channel: ch, events: const EventChannel('test/wear-known-events'));
      link.start(t);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(link.ready.value, isFalse);
      expect(puts, greaterThan(0), reason: 'πριν: τίποτα χωρίς ρολόι κοντά');
      expect(link.sentLimit.value, '140');
      // Το ρολόι έχει ακόμα το παλιό όριο: όχι «✓».
      expect(link.watchLimit.value, '130');
      link.applyWatchState('{"v":1,"lim":140,"planAt":0}');
      expect(link.watchLimit.value, '140');
      link.applyWatchState('{"v":1,"lim":0}');
      expect(link.watchLimit.value, 'null');
      link.dispose();
    });
  });

  group('κανάλι training.json', () {
    const ch = MethodChannel('ygeia/training');
    test('νέα (χάρτης) και παλιά (κείμενο μέσα σε JSON) απάντηση ανάγνωσης· αρχεία παλμών', () async {
      Object? answer;
      final files = <String, String>{};
      final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      m.setMockMethodCallHandler(ch, (call) async {
        final a = call.arguments is Map ? (call.arguments as Map) : const {};
        switch (call.method) {
          case 'read':
            return answer;
          case 'hrWrite':
            files[a['id'] as String] = a['json'] as String;
            return true;
          case 'hrRead':
            final id = a['id'] as String;
            return files.containsKey(id) ? {'state': 'ok', 'json': files[id]} : {'state': 'missing'};
          case 'hrList':
            return files.keys.toList();
        }
        return null;
      });
      addTearDown(() => m.setMockMethodCallHandler(ch, null));
      const io = ChannelTrainingIO();
      answer = {'state': 'ok', 'json': '{"v":2}'};
      expect((await io.read()).json, '{"v":2}');
      answer = jsonEncode({'state': 'ok', 'json': '{"v":1}'});
      expect((await io.read()).json, '{"v":1}');
      answer = {'state': 'missing'};
      expect((await io.read()).state, 'missing');
      expect(await io.writeHr('w-1', encodeHr([[0, 99]])), isTrue);
      expect(decodeHr((await io.readHr('w-1')).json), [
        [0, 99],
      ]);
      expect((await io.readHr('δεν')).state, 'missing');
      expect(await io.listHr(), ['w-1']);
      expect(hrFileId('w-walk1700000000000'), isTrue);
      expect(hrFileId('../x'), isFalse);
    });
  });

  group('σύνοψη', () {
    testWidgets('παλμοί από το αρχείο τους φορτώνονται· «μερικό» λέγεται', (tester) async {
      ExClock.frozen = true;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 2400);
      addTearDown(tester.view.reset);
      await tester.runAsync(() => ExLibrary.load(inline: true));
      final io = MemoryTrainingIO();
      final t0 = TrainingStore(io: io, clock: () => now);
      await tester.runAsync(() async {
        await t0.load();
        t0.importWatch(_walk('walkC', sec: 1200, partial: true));
        await t0.flush();
      });
      final t = TrainingStore(io: io, clock: () => now);
      await tester.runAsync(() => t.load());
      final s = t.sessions.single;
      expect(s.hrLoaded, isFalse);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: SummaryPage(training: t, session: s)));
      await tester.runAsync(() => t.ensureHr(s));
      await tester.pumpAndSettle();
      expect(s.hr.length, 1201);
      expect(find.byKey(const ValueKey('summary-partial')), findsOneWidget);
      expect(find.textContaining('έκλεισε πριν το «Τέλος»'), findsOneWidget);
    });
  });
}
