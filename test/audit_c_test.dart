// Έλεγχος 2 (4/11), κομμάτι C (δεδομένα, ανθεκτικότητα): κάθε διόρθωση με έλεγχο που αποτυγχάνει χωρίς αυτήν.
// C1 ομαδοποίηση νύχτας χωρίς βήματα · C3 άγνωστες φάσεις / κομμάτι χωρίς φάσεις · C6 φίλτρο ρολογιού ·
// C5 ζυγίσεις άλλων εφαρμογών · C7 δημοσίευση μόνο μετά το smoke · C10 μεσάζων · C11 ορισμοί μετά από επαναφορά ·
// C12 μικρά (λόγος κενής νύχτας, ρολόι, παλμοί μισής μέρας) · C13 σελίδα ύπνου.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/oura/oura_api.dart';
import 'package:ygeia_forma/oura/oura_store.dart';
import 'package:ygeia_forma/oura/oura_view.dart';
import 'package:ygeia_forma/pages/sleep.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/ti_ftanei.dart';

int ms(DateTime t) => t.millisecondsSinceEpoch;
DateTime t(int day, int h, int m) => DateTime(2026, 11, day, h, m);

List<List<Object>> seq(DateTime start, List<(String, int)> parts) {
  final out = <List<Object>>[];
  var x = start;
  for (final (name, m) in parts) {
    out.add([name, ms(x), ms(x.add(Duration(minutes: m)))]);
    x = x.add(Duration(minutes: m));
  }
  return out;
}

/// Νύχτα-δείγμα Δευ 2 → Τρ 3/11 (ρολόι): δύο κομμάτια της Samsung, φάσεις όπως τις δείχνει η εφαρμογή
/// (#65): βαθύς 8, ελαφρύς 271, REM 51, ξύπνιος 47· κενό 02:40–03:50. Samsung «Πραγματικός ύπνος» 5ω29.
List<Map<String, dynamic>> ownerNight() => [
      {
        'start': ms(t(2, 23, 43)),
        'end': ms(t(3, 2, 40)),
        'minutes': 177,
        'score': 18,
        'stages': seq(t(2, 23, 43), [('LIGHT', 60), ('DEEP', 8), ('LIGHT', 60), ('REM', 25), ('AWAKE', 25)]),
      },
      {
        'start': ms(t(3, 3, 50)),
        'end': ms(t(3, 7, 8)),
        'minutes': 198,
        'score': 31,
        'stages': seq(t(3, 3, 50), [('LIGHT', 80), ('AWAKE', 22), ('LIGHT', 71), ('REM', 26)]),
      },
    ];

Map<String, dynamic> rec(DateTime a, DateTime b) =>
    {'start': ms(a), 'end': ms(b), 'minutes': b.difference(a).inMinutes, 'stages': seq(a, [('LIGHT', b.difference(a).inMinutes)])};

void main() {
  group('C1: η νύχτα δεν εξαρτάται από βήματα', () {
    Map<String, dynamic> read({required DateTime readAt, required int gapSteps, required DateTime stepsFrom}) => {
          'readAt': ms(readAt),
          'sleep': ownerNight(),
          'stepsMin': [
            if (gapSteps > 0) [ms(t(3, 3, 10)), gapSteps],
          ],
          'stepsFrom': ms(stepsFrom),
        };

    test('Νύχτα 2→3/11: 5ω30 με 0 ή 200 βήματα στο κενό, σήμερα και σε 30 μέρες (χωρίς βήματα ανά λεπτό)', () {
      final cases = {
        'σήμερα, 0 βήματα': read(readAt: t(3, 12, 0), gapSteps: 0, stepsFrom: DateTime(2026, 10, 27)),
        'σήμερα, 200 βήματα': read(readAt: t(3, 12, 0), gapSteps: 200, stepsFrom: DateTime(2026, 10, 27)),
        'σε 30 μέρες (βήματα ανά λεπτό μόνο 7 μέρες)':
            read(readAt: DateTime(2026, 12, 3, 12), gapSteps: 200, stepsFrom: DateTime(2026, 11, 26)),
      };
      for (final e in cases.entries) {
        final d = Dashboard.fromJson(e.value);
        final n = d.nights.singleWhere((n) => n.date == DateTime(2026, 11, 3));
        expect(n.minutes, 330, reason: e.key);
        expect(n.start, t(2, 23, 43), reason: e.key);
        expect(n.end, t(3, 7, 8), reason: e.key);
        expect(n.napMinutes, 0, reason: e.key);
        expect(n.betweenMinutes + n.estimatedMinutes, 70, reason: '${e.key}: το κενό φαίνεται, δεν μετρά');
        final row = summarizeDay(d, DateTime(2026, 11, 3));
        expect(row[K.sleepMin], 330, reason: e.key);
        expect(row.containsKey(K.napMin), isFalse, reason: e.key);
        expect(row[K.bedtime], minutesFromSix(t(2, 23, 43)), reason: e.key);
      }
    });

    // Έλεγχος 3, E1 (σκόπιμη αλλαγή): πριν από την κύρια ομάδα μπαίνει ό,τι αρχίζει από τις 20:00 με κενό ως 4 ώρες·
    // πριν, το λαγοκοίμισμα ως τις 22:00 ήταν πάντα υπνάκος. Υπνάκος μένει ό,τι αρχίζει πριν από τις 20:00.
    test('Βραδινό λαγοκοίμισμα 19:30–20:30 και ύπνος 23:30: χωριστός υπνάκος (napMin)· από τις 20:00: μέρος της νύχτας', () {
      final d = Dashboard.fromJson({
        'readAt': ms(t(3, 12, 0)),
        'sleep': [rec(t(2, 19, 30), t(2, 20, 30)), rec(t(2, 23, 30), t(3, 7, 0))],
      });
      final n = d.nights.single;
      expect(n.start, t(2, 23, 30));
      expect(n.minutes, 450);
      expect(n.napMinutes, 60);
      final row = summarizeDay(d, DateTime(2026, 11, 3));
      expect(row[K.sleepMin], 450);
      expect(row[K.napMin], 60);
      // Από τις 20:00 και μετά, με κενό ως 4 ώρες: μέρος της νύχτας (το κενό δεν μετρά).
      for (final early in [rec(t(2, 20, 30), t(2, 21, 30)), rec(t(2, 21, 0), t(2, 22, 30))]) {
        final late = Dashboard.fromJson({
          'readAt': ms(t(3, 12, 0)),
          'sleep': [early, rec(t(2, 23, 30), t(3, 7, 0))],
        }).nights.single;
        expect(late.start.millisecondsSinceEpoch, early['start']);
        expect(late.minutes, (early['minutes'] as int) + 450);
        expect(late.napMinutes, 0);
      }
    });

    test('Πρωινός υπνάκος 09:30–10:30 μετά από ξύπνημα 07:00: υπνάκος, η νύχτα τελειώνει 07:00', () {
      final d = Dashboard.fromJson({
        'readAt': ms(t(3, 13, 0)),
        'sleep': [rec(t(2, 23, 30), t(3, 7, 0)), rec(t(3, 9, 30), t(3, 10, 30))],
      });
      final n = d.nights.single;
      expect(n.end, t(3, 7, 0));
      expect(n.minutes, 450);
      expect(n.napMinutes, 60);
      expect(summarizeDay(d, DateTime(2026, 11, 3))[K.napMin], 60);
      // Μισή ώρα μετά το ξύπνημα (06:30 → 07:00–08:00): ίδια νύχτα.
      final soon = Dashboard.fromJson({
        'readAt': ms(t(3, 13, 0)),
        'sleep': [rec(t(2, 23, 30), t(3, 6, 30)), rec(t(3, 7, 0), t(3, 8, 0))],
      }).nights.single;
      expect(soon.end, t(3, 8, 0));
      expect(soon.minutes, 420 + 60);
      expect(soon.napMinutes, 0);
    });

    // Συντονιστής (4/11): η Κυριακή 25/10 του χρήστη (05:55–09:50, 10:53–13:14, 0 βήματα, παλμοί ύπνου) ΔΕΝ ήταν
    // ξύπνημα. Πρωινό κομμάτι: ίδια νύχτα αν κενό ≤ 90′ ΚΑΙ (χωρίς βήματα ανά λεπτό Ή ≤ 30 βήματα)· αλλιώς υπνάκος.
    Map<String, dynamic> morning(List<Map<String, dynamic>> sleep, {List<List<num>> steps = const [], DateTime? stepsFrom}) => {
          'readAt': ms(DateTime(2026, 10, 26, 15)),
          'sleep': sleep,
          'stepsMin': steps,
          if (stepsFrom != null) 'stepsFrom': ms(stepsFrom),
        };
    final sun1 = rec(DateTime(2026, 10, 26, 5, 55), DateTime(2026, 10, 26, 9, 50));
    final sun2 = rec(DateTime(2026, 10, 26, 10, 53), DateTime(2026, 10, 26, 13, 14));

    test('25/10: κενό 63′ με 0 βήματα → η ίδια νύχτα (το κενό δεν μετρά)', () {
      final d = Dashboard.fromJson(morning([sun1, sun2], stepsFrom: DateTime(2026, 10, 19)));
      final n = d.nights.single;
      expect(n.parts.length, 2);
      expect(n.minutes, 235 + 141);
      expect(n.napMinutes, 0);
      expect(n.end, DateTime(2026, 10, 26, 13, 14));
      expect(n.betweenMinutes + n.estimatedMinutes, 63);
      expect(summarizeDay(d, DateTime(2026, 10, 26))[K.sleepMin], 376);
    });

    test('25/10 χωρίς βήματα ανά λεπτό (π.χ. σε 30 μέρες) → η ίδια νύχτα', () {
      for (final j in [
        morning([sun1, sun2], stepsFrom: DateTime(2026, 10, 26, 12)),
        {...morning([sun1, sun2]), 'stepsMin': null},
      ]) {
        final n = Dashboard.fromJson(j).nights.single;
        expect(n.minutes, 376);
        expect(n.napMinutes, 0);
      }
    });

    test('Ξύπνημα 07:00, 200 βήματα, υπνάκος 08:30–09:30 → υπνάκος', () {
      final d = Dashboard.fromJson(morning(
        [rec(t(2, 23, 0), t(3, 7, 0)), rec(t(3, 8, 30), t(3, 9, 30))],
        steps: [
          [ms(t(3, 7, 40)), 200],
        ],
        stepsFrom: DateTime(2026, 10, 27),
      ));
      final n = d.nights.single;
      expect(n.minutes, 480);
      expect(n.end, t(3, 7, 0));
      expect(n.napMinutes, 60);
      expect(summarizeDay(d, DateTime(2026, 11, 3))[K.napMin], 60);
    });

    test('Ξύπνημα 07:00, υπνάκος 10:00–11:00 (κενό 3 ώρες) → υπνάκος, ακόμα και χωρίς βήματα', () {
      final d = Dashboard.fromJson(morning(
        [rec(t(2, 23, 0), t(3, 7, 0)), rec(t(3, 10, 0), t(3, 11, 0))],
        stepsFrom: DateTime(2026, 10, 27),
      ));
      expect(d.nights.single.minutes, 480);
      expect(d.nights.single.napMinutes, 60);
    });

    test('Υπνάκος μέρας χωρίς νύχτα του ρολογιού: αποθηκεύεται (δεν χάνεται)', () {
      final d = Dashboard.fromJson({
        'readAt': ms(t(3, 18, 0)),
        'sleep': [rec(t(3, 14, 0), t(3, 15, 0))],
      });
      expect(d.nights, isEmpty);
      expect(summarizeDay(d, DateTime(2026, 11, 3))[K.napMin], 60);
      // Σε νύχτα του Oura ο υπνάκος του ρολογιού δεν γράφεται (μία πηγή για τη «νύχτα»).
      final plan = SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 1));
      expect(summarizeDay(d, DateTime(2026, 11, 3), plan: plan).containsKey(K.napMin), isFalse);
    });

    test('Η ανάγνωση 30 ημερών ξαναγράφει τον ύπνο όλων των ημερών (όχι μόνο των 7 με βήματα)', () {
      final d = Dashboard.fromJson({
        'readAt': ms(DateTime(2026, 11, 20, 12)),
        'sleep': ownerNight(),
        'stepsMin': <List<num>>[],
        'stepsFrom': ms(DateTime(2026, 11, 13)),
      });
      final h = <String, Map<String, double>>{
        '2026-11-03': {K.sleepMin: 177, K.napMin: 152, K.steps: 9000},
      };
      final changed = applyRecentRead(h, d, plan: SourcePlan.samsungOnly);
      expect(changed, contains('2026-11-03'));
      expect(h['2026-11-03']![K.sleepMin], 330);
      expect(h['2026-11-03']!.containsKey(K.napMin), isFalse, reason: 'ο παλιός «υπνάκος» ήταν το πρώτο κομμάτι της νύχτας');
      expect(h['2026-11-03']![K.steps], 9000);
    });
  });

  group('C3: άγνωστη φάση ή κομμάτι χωρίς φάσεις δεν σβήνει τη νύχτα', () {
    test('Μία σύντομη φάση UNDEFINED (<5%): η νύχτα μετρά, χωρίς αυτήν', () {
      final d = Dashboard.fromJson({
        'readAt': ms(t(3, 12, 0)),
        'sleep': [
          {
            'start': ms(t(2, 23, 0)),
            'end': ms(t(3, 7, 0)),
            'minutes': 480,
            'stages': seq(t(2, 23, 0), [('LIGHT', 200), ('UNDEFINED', 10), ('DEEP', 60), ('REM', 90), ('AWAKE', 30), ('LIGHT', 90)]),
          },
        ],
      });
      final n = d.nights.single;
      expect(n.staged, isTrue);
      expect(n.minutes, 200 + 60 + 90 + 90);
      expect(summarizeDay(d, DateTime(2026, 11, 3))[K.sleepMin], 440);
    });

    test('Πολλές άγνωστες φάσεις (>5%): δεν ξέρουμε τον πραγματικό ύπνο, χωρίς διάρκεια στο ιστορικό', () {
      final d = Dashboard.fromJson({
        'readAt': ms(t(3, 12, 0)),
        'sleep': [
          {
            'start': ms(t(2, 23, 0)),
            'end': ms(t(3, 7, 0)),
            'minutes': 480,
            'stages': seq(t(2, 23, 0), [('LIGHT', 300), ('UNDEFINED', 60), ('REM', 120)]),
          },
        ],
      });
      expect(d.nights.single.staged, isFalse);
      expect(summarizeDay(d, DateTime(2026, 11, 3)).containsKey(K.sleepMin), isFalse);
    });

    test('Κομμάτι χωρίς φάσεις μέσα σε νύχτα με φάσεις: μετρούν τα κομμάτια με φάσεις, σημείωση «μερικώς»', () {
      final sleep = ownerNight();
      sleep[0] = {...sleep[0], 'stages': <Object>[]};
      final d = Dashboard.fromJson({'readAt': ms(t(3, 12, 0)), 'sleep': sleep});
      final n = d.nights.single;
      expect(n.staged, isTrue);
      expect(n.partial, isTrue);
      expect(n.minutes, 177, reason: 'μόνο το κομμάτι με φάσεις (80+71+26), ποτέ τα 177 λεπτά «με τα ξυπνήματα» του άλλου');
      // Έλεγχος 8/11 (DATA-01): η μερική διάρκεια δεν μπαίνει στο ιστορικό (Τάσεις, εβδομάδα, αναφορά).
      expect(summarizeDay(d, DateTime(2026, 11, 3)).containsKey(K.sleepMin), isFalse);
      expect(n.fullDuration, isFalse);
      // Όλη με φάσεις: όχι «μερικώς».
      expect(Dashboard.fromJson({'readAt': ms(t(3, 12, 0)), 'sleep': ownerNight()}).nights.single.partial, isFalse);
    });
  });

  test('C3: η επανανάγνωση δεν σβήνει αποθηκευμένη διάρκεια χωρίς έγκυρη νέα (νύχτες του ρολογιού μόνο)', () {
    final h = <String, Map<String, double>>{
      '2026-10-10': {K.sleepMin: 410, K.sleepScore: 80, K.steps: 5000},
      '2026-10-11': {K.sleepMin: 400},
      '2026-11-07': {K.sleepMin: 380},
    };
    final plan = SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 6));
    mergeHistory(
      h,
      {
        '2026-10-10': {K.bedtime: 300},
        '2026-10-11': {K.sleepMin: 395},
      },
      replaceSleep: true,
      rangeFrom: DateTime(2026, 10, 1),
      rangeTo: DateTime(2026, 11, 30),
      plan: plan,
    );
    expect(h['2026-10-10'], {K.sleepMin: 410, K.bedtime: 300, K.steps: 5000});
    expect(h['2026-10-11']![K.sleepMin], 395, reason: 'έγκυρη νέα τιμή: αντικαθιστά');
    expect(h['2026-11-07']!.containsKey(K.sleepMin), isFalse, reason: 'νύχτα του Oura: η τιμή του ρολογιού φεύγει');
  });

  group('C6: το φίλτρο δεν βρήκε τίποτα ενώ υπάρχουν εγγραφές', () {
    test('Ο ύπνος γυρίζει σφάλμα (watch_filter_empty): ο αποθηκευμένος ύπνος μένει', () {
      final d = Dashboard.fromJson({
        'readAt': ms(t(10, 12, 0)),
        'sleep': {'error': 'java.lang.IllegalStateException: watch_filter_empty'},
        'steps': [
          [ms(t(9, 0, 0)), 5000],
        ],
      });
      expect(d.failed, contains('sleep'));
      final h = <String, Map<String, double>>{
        '2026-11-09': {K.sleepMin: 400, K.bedtime: 300},
      };
      applyRecentRead(h, d, plan: SourcePlan.samsungOnly, sleepFailed: true);
      expect(h['2026-11-09']![K.sleepMin], 400);
      expect(h['2026-11-09']![K.steps], 5000);
    });

    test('«Τι φτάνει» λέει τον λόγο (ρολόι και InBody)', () {
      expect(filterWarning({'key': 'sleep', 'state': 'ok', 'count': 12, 'counted': 0, 'ignored': 12}),
          contains('Το φίλτρο ρολογιού δεν βρήκε τίποτα'));
      expect(filterWarning({'key': 'body_composition', 'state': 'ok', 'count': 4, 'counted': 0, 'ignored': 4}),
          contains('Καμία ζύγιση από την InBody'));
      expect(filterWarning({'key': 'sleep', 'state': 'ok', 'count': 12, 'counted': 11, 'ignored': 1}), isNull);
      expect(filterWarning({'key': 'sleep', 'state': 'ok', 'count': 0, 'counted': 0, 'ignored': 0}), isNull);
    });

    test('Καμία ζύγιση InBody αλλά ζυγίσεις άλλων εφαρμογών: το ιστορικό ζυγίσεων μένει', () {
      final d = Dashboard.fromJson({
        'readAt': ms(t(10, 12, 0)),
        'body': [
          {'time': ms(t(9, 7, 0)), 'weight': 80.0, 'app': 'com.sec.android.app.shealth'},
        ],
      });
      expect(d.body, isEmpty);
      expect(d.bodyOther, 1);
      final h = <String, Map<String, double>>{
        '2026-11-01': {K.weight: 82.0},
        '2026-11-02': {K.weight: 82.1},
        '2026-11-03': {K.weight: 82.2},
        '2026-11-04': {K.weight: 82.3},
      };
      applyRecentRead(h, d, plan: SourcePlan.samsungOnly);
      expect(h['2026-11-04']![K.weight], 82.3);
      expect(h['2026-11-09'], isNull);
    });
  });

  group('C7: η έκδοση δημοσιεύεται μόνο μετά το χτίσιμο ΚΑΙ το άνοιγμα σε emulator', () {
    final yml = File('.github/workflows/android.yml').readAsStringSync();
    // Τα jobs ως κείμενα (κάθε job αρχίζει με «  όνομα:» στην αρχή της γραμμής).
    Map<String, String> jobs() {
      final out = <String, String>{};
      final body = yml.substring(yml.indexOf('\njobs:\n'));
      final re = RegExp(r'^  ([a-z_-]+):\s*$', multiLine: true);
      final found = re.allMatches(body).toList();
      for (var i = 0; i < found.length; i++) {
        out[found[i].group(1)!] = body.substring(found[i].start, i + 1 < found.length ? found[i + 1].start : body.length);
      }
      return out;
    }

    // Έλεγχος 9/11 (V-A-20): το κλειδί υπογραφής ΜΟΝΟ στο job «sign» (μετά από build ΚΑΙ smoke)· το publish μόνο από το main.
    test('publish: needs sign, μόνο main· sign: needs [build, smoke], μόνο εκεί το κλειδί· μόνο το publish δημοσιεύει', () {
      final j = jobs();
      expect(j.keys, containsAll(['build', 'smoke', 'sign', 'publish']));
      expect(j['publish'], contains('needs: sign'));
      expect(j['publish'], contains("if: github.ref == 'refs/heads/main'"));
      expect(j['publish'], contains('gh release create latest'));
      expect(j['sign'], contains('needs: [build, smoke]'));
      expect(j['sign'], contains('secrets.YGEIA_KEYSTORE_B64'));
      expect(j['sign'], contains('tools/ci/sign_apks.sh'));
      expect(j['sign'], contains('if: always()'), reason: 'το αρχείο του κλειδιού σβήνεται πάντα');
      for (final e in j.entries.where((e) => e.key != 'publish')) {
        expect(e.value.contains('gh release create'), isFalse, reason: '${e.key} δεν δημοσιεύει');
      }
      for (final e in j.entries.where((e) => e.key != 'sign')) {
        expect(e.value.contains('secrets.'), isFalse, reason: '${e.key} δεν βλέπει κανένα secret');
      }
      expect(yml.contains('GITHUB_ENV'), isFalse, reason: 'κανένα secret στο περιβάλλον των επόμενων βημάτων');
      expect(j['build'], contains('actions/upload-artifact'));
      final sign = File('tools/ci/sign_apks.sh').readAsStringSync();
      expect(sign, contains('assetlinks.json'));
      expect(sign, contains('YGEIA_CERT_SHA256'));
      expect(yml, contains('YGEIA_CERT_SHA256: a4433ab12214'));
    });

    test('όλα τα workflows: ενέργειες κλειδωμένες σε πλήρες SHA, permissions, χωρίς pull_request_target', () {
      for (final f in Directory('.github/workflows').listSync().whereType<File>().where((f) => f.path.endsWith('.yml'))) {
        final w = f.readAsStringSync();
        for (final m in RegExp(r'uses:\s*(\S+)').allMatches(w)) {
          expect(m.group(1), matches(RegExp(r'@[0-9a-f]{40}$')), reason: '${f.path}: ${m.group(1)}');
        }
        expect(w, contains('permissions:'), reason: f.path);
        expect(w.contains('pull_request_target'), isFalse, reason: f.path);
      }
    });
  });

  group('C10: σφάλματα του μεσάζοντα', () {
    test('503 proxy_not_configured: «ο μεσάζων δεν έχει ρυθμιστεί», όχι δίκτυο για πάντα', () {
      expect(tokenErrorKind(503, '{"error":"proxy_not_configured"}', refused: OuraErrorKind.reconnect),
          OuraErrorKind.proxyNotConfigured);
      expect(ouraErrorText(OuraErrorKind.proxyNotConfigured), startsWith('Ο μεσάζων δεν έχει ρυθμιστεί'));
      expect(ouraBackoffFor(OuraErrorKind.proxyNotConfigured), const Duration(hours: 1));
      expect(tokenErrorKind(503, '<html>', refused: OuraErrorKind.reconnect), OuraErrorKind.network);
      expect(tokenErrorKind(502, '{"error":"upstream_unreachable"}', refused: OuraErrorKind.reconnect), OuraErrorKind.network);
    });

    test('400 invalid_client/invalid_request: λάθος του μεσάζοντα, όχι «νέα σύνδεση»· invalid_grant: νέα σύνδεση', () {
      for (final c in ['invalid_client', 'invalid_request', 'unsupported_grant_type']) {
        expect(tokenErrorKind(400, '{"error":"$c"}', refused: OuraErrorKind.reconnect), OuraErrorKind.proxyRejected, reason: c);
      }
      expect(tokenErrorKind(400, '{"error":"invalid_grant"}', refused: OuraErrorKind.reconnect), OuraErrorKind.reconnect);
      expect(tokenErrorKind(401, '', refused: OuraErrorKind.reconnect), OuraErrorKind.reconnect);
    });

    test('Ανανέωση με 400 invalid_client από τον μεσάζοντα: proxyRejected, τα tokens μένουν', () async {
      final now = DateTime(2026, 11, 10, 9);
      final old = OuraTokens(access: 'A0', refresh: 'R0', expiresAt: now.millisecondsSinceEpoch).toJson();
      for (final (status, body, kind) in [
        (400, '{"error":"invalid_client","error_description":"unknown client"}', OuraErrorKind.proxyRejected),
        (503, '{"error":"proxy_not_configured"}', OuraErrorKind.proxyNotConfigured),
      ]) {
        final v = MemoryVault()..data[vaultTokens] = old;
        Future<OuraResponse> send(String m, Uri u, {Map<String, String> headers = const {}, String? form}) async =>
            OuraResponse(status, body);
        final l = OuraLink(vault: v, send: send, clock: () => now, clientId: 'CID');
        await expectLater(l.refresh(), throwsA(isA<OuraError>().having((e) => e.kind, 'kind', kind)));
        expect(v.data[vaultTokens], old);
      }
    });
  });

  test('C10: η σελίδα απορρήτου λέει ότι ο κωδικός σύνδεσης περνά από τον μεσάζοντα (χωρίς δεδομένα υγείας)', () {
    final p = File('site/public/privacy/index.html').readAsStringSync();
    expect(p, contains('μικρή υπηρεσία μας στο Netlify'));
    expect(p, contains('δεδομένα υγείας δεν περνούν ποτέ από εκεί'));
    expect(p, contains('small service of ours on Netlify'));
    expect(p.contains('Δεν υπάρχει δικός μας server ή λογαριασμός.'), isFalse);
  });

  // Έλεγχος 3, E2 (σκόπιμη αλλαγή του C5): οι ζυγίσεις άλλων εφαρμογών ΔΕΝ σβήνονται ποτέ· από την πρώτη της InBody
  // και μετά απλώς δεν φαίνονται (SourcePlan.scaleFrom, έλεγχοι στο audit_e_test).
  test('C5 → E2: ζυγίσεις άλλων εφαρμογών από παλιές εκδόσεις ΜΕΝΟΥΝ στο ιστορικό· η InBody κερδίζει τη μέρα της', () {
    final readAt = DateTime(2026, 11, 20, 12);
    final body = <Map<String, dynamic>>[
      // 10 μέρες με BIA του ρολογιού, χωρίς InBody (πριν: έμεναν για πάντα, όριο «ως 3»).
      for (var i = 1; i <= 10; i++)
        {'time': ms(DateTime(2026, 10, i, 8)), 'weight': 80.0 + i, 'fatPct': 20.0, 'app': 'com.samsung.android.wear.shealth'},
      // Μέρα με ρολόι ΚΑΙ InBody: μένει η InBody.
      {'time': ms(DateTime(2026, 10, 15, 8)), 'weight': 90.0, 'app': 'com.samsung.android.wear.shealth'},
      {'time': ms(DateTime(2026, 10, 15, 9)), 'weight': 82.0, 'fatPct': 24.0, 'app': 'com.inbody2014.inbody'},
    ];
    final d = Dashboard.fromJson({'readAt': ms(readAt), 'body': body});
    final h = <String, Map<String, double>>{
      for (var i = 1; i <= 10; i++) '2026-10-${i.toString().padLeft(2, '0')}': {K.weight: 80.0 + i, K.fatPct: 20, K.steps: 1000},
      '2026-10-15': {K.weight: 90.0},
      // Ζυγίσεις που δεν υπάρχουν τώρα στη Samsung (ίσως δεν συγχρόνισε ακόμα): δεν αγγίζονται εδώ.
      for (var i = 20; i <= 24; i++) '2026-10-$i': {K.weight: 81.0},
    };
    applyRecentRead(h, d, plan: SourcePlan.samsungOnly);
    for (var i = 1; i <= 10; i++) {
      final k = '2026-10-${i.toString().padLeft(2, '0')}';
      expect(h[k], {K.weight: 80.0 + i, K.fatPct: 20, K.steps: 1000}, reason: k);
    }
    expect(h['2026-10-15']![K.weight], 82.0);
    expect(h['2026-10-15']![K.fatPct], 24.0);
    expect(h['2026-10-15']![K.inbody], 1);
    for (var i = 20; i <= 24; i++) {
      expect(h['2026-10-$i']![K.weight], 81.0);
    }
  });

  test('C11: αλλαγή πηγής εκ των υστέρων σβήνει μόνο οξυγόνο/παλμούς μέρας των ημερών με άλλη πηγή νύχτας', () {
    final h = <String, Map<String, double>>{
      '2026-10-01': {K.spo2Avg: 95, K.dayHr: 70, K.sleepMin: 400},
      '2026-10-09': {K.dayHr: 72},
      '2026-10-10': {K.spo2Avg: 94, K.restHr: 55, 'o.sleepMin': 420},
    };
    final before = SourcePlan.samsungOnly;
    final after = SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 10, 10));
    expect(stripChangedDefinitions(h, before, after), {'2026-10-09', '2026-10-10'});
    expect(h['2026-10-01'], {K.spo2Avg: 95, K.dayHr: 70, K.sleepMin: 400});
    expect(h['2026-10-09'], isEmpty, reason: 'οι παλμοί της μέρας εξαιρούν τον ύπνο του βραδιού, που άλλαξε πηγή');
    expect(h['2026-10-10'], {'o.sleepMin': 420});
  });

  group('C12', () {
    test('Παλιά νύχτα που διαβάστηκε ήδη: «δεν υπάρχουν δεδομένα», όχι «πρόβλημα σύνδεσης» μετά από αποσύνδεση', () {
      final plan = SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 1));
      final nowT = DateTime(2026, 11, 10, 15);
      final r = emptyNightReason(
        plan: plan,
        day: DateTime(2026, 11, 5),
        now: nowT,
        night: null,
        hasTokens: false,
        synced: DateTime(2026, 11, 6, 9),
      );
      expect(r, EmptyNight.noRing);
      // Δεν διαβάστηκε ποτέ μετά το πρωί της: η σύνδεση λείπει → «νέα σύνδεση».
      expect(
        emptyNightReason(plan: plan, day: DateTime(2026, 11, 8), now: nowT, night: null, hasTokens: false,
            synced: DateTime(2026, 11, 6, 9)),
        EmptyNight.reconnect,
      );
    });

    test('Ρολόι κινητού μπροστά: η πρώτη νύχτα με την ώρα της Oura', () {
      final server = DateTime.utc(2026, 11, 10, 8);
      expect(clampToServer(DateTime(2027, 3, 1, 10), server), server.toLocal());
      final ok = DateTime(2026, 11, 10, 10, 30);
      expect(clampToServer(ok, server), ok);
      expect(clampToServer(ok, null), ok);
    });

    test('Παλμοί μέρας από μισή μέρα: φεύγουν όταν λείπει πια η νύχτα του Oura που χρειάζονται', () {
      final plan = SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 1));
      final readAt = DateTime(2026, 11, 10, 12);
      final d = Dashboard.fromJson({'readAt': ms(readAt), 'sleep': <Object>[], 'heart': <Object>[]});
      final windows = SleepWindows(const [], {
        '2026-11-08': (DateTime(2026, 11, 7, 23), DateTime(2026, 11, 8, 7)),
        '2026-11-09': (DateTime(2026, 11, 8, 23), DateTime(2026, 11, 9, 7)),
      });
      final h = <String, Map<String, double>>{
        // Η μέρα 9/11 γράφτηκε το απόγευμα της (μισή)· η νύχτα 10/11 δεν ήρθε από το δαχτυλίδι.
        '2026-11-09': {K.dayHr: 74, K.restHr: 60, K.steps: 5000},
        '2026-11-08': {K.dayHr: 70},
      };
      applyRecentRead(h, d, plan: plan, windows: windows);
      expect(h['2026-11-09'], {K.steps: 5000});
      expect(h['2026-11-08']![K.dayHr], 70, reason: 'οι νύχτες 8 και 9/11 υπάρχουν: δεν αγγίζεται');
      expect(dayHeartNeedsMissingWindow(plan, windows, DateTime(2026, 11, 9), DateTime(2026, 11, 10)), isTrue);
    });
  });

  group('C13: σελίδα ύπνου', () {
    test('Νύχτα χωρίς φάσεις: κενή στήλη, «—» και «χωρίς φάσεις»· μερικώς: διάρκεια και σημείωση', () {
      final staged = Dashboard.fromJson({'readAt': ms(t(3, 12, 0)), 'sleep': ownerNight()}).nights.single;
      final unstaged = Dashboard.fromJson({
        'readAt': ms(t(3, 12, 0)),
        'sleep': [
          for (final r in ownerNight()) {...r, 'stages': <Object>[]},
        ],
      }).nights.single;
      final partialSleep = ownerNight();
      partialSleep[0] = {...partialSleep[0], 'stages': <Object>[]};
      final partial = Dashboard.fromJson({'readAt': ms(t(3, 12, 0)), 'sleep': partialSleep}).nights.single;
      expect(sleepBarHours(staged), 5.5);
      expect(sleepBarHours(unstaged), isNull, reason: 'ποτέ η διάρκεια της Samsung (με τα ξυπνήματα) στο γράφημα');
      expect(nightRowDuration(unstaged), '—');
      expect(nightRowNote(unstaged), 'χωρίς φάσεις');
      expect(nightRowNote(partial), 'μερικώς χωρίς φάσεις');
      expect(nightRowNote(staged), isNull);
      expect(nightRowDuration(staged), isNot('—'));
    });
  });
}
