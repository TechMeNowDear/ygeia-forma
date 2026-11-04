// Έλεγχος 2 (4/11), κομμάτι C (δεδομένα, ανθεκτικότητα): κάθε διόρθωση με έλεγχο που αποτυγχάνει χωρίς αυτήν.
// C1 ομαδοποίηση νύχτας χωρίς βήματα · C3 άγνωστες φάσεις / κομμάτι χωρίς φάσεις · C6 φίλτρο ρολογιού ·
// C7 δημοσίευση μόνο μετά το smoke · C10 σφάλματα του μεσάζοντα.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/oura/oura_api.dart';
import 'package:ygeia_forma/oura/oura_store.dart';
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

/// Η πραγματική νύχτα Δευ 2 → Τρ 3/11 του χρήστη (ρολόι): δύο κομμάτια της Samsung, φάσεις όπως τις έδειξε η εφαρμογή
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

    test('Βραδινό λαγοκοίμισμα 20:30–21:30 και ύπνος 23:30: χωριστός υπνάκος, αποθηκεύεται ως napMin', () {
      final d = Dashboard.fromJson({
        'readAt': ms(t(3, 12, 0)),
        'sleep': [rec(t(2, 20, 30), t(2, 21, 30)), rec(t(2, 23, 30), t(3, 7, 0))],
      });
      final n = d.nights.single;
      expect(n.start, t(2, 23, 30));
      expect(n.minutes, 450);
      expect(n.napMinutes, 60);
      final row = summarizeDay(d, DateTime(2026, 11, 3));
      expect(row[K.sleepMin], 450);
      expect(row[K.napMin], 60);
      // Το ίδιο, αλλά συνεχίζει μετά τις 22:00: μέρος της νύχτας (το κενό δεν μετρά).
      final late = Dashboard.fromJson({
        'readAt': ms(t(3, 12, 0)),
        'sleep': [rec(t(2, 21, 0), t(2, 22, 30)), rec(t(2, 23, 30), t(3, 7, 0))],
      }).nights.single;
      expect(late.start, t(2, 21, 0));
      expect(late.minutes, 90 + 450);
      expect(late.napMinutes, 0);
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
      expect(summarizeDay(d, DateTime(2026, 11, 3))[K.sleepMin], 177);
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

    test('publish: needs [build, smoke]· μόνο εκεί «gh release create»· το αποτύπωμα του κλειδιού μένει στο build', () {
      final j = jobs();
      expect(j.keys, containsAll(['build', 'smoke', 'publish']));
      expect(j['publish'], contains('needs: [build, smoke]'));
      expect(j['publish'], contains('gh release create latest'));
      for (final e in j.entries.where((e) => e.key != 'publish')) {
        expect(e.value.contains('gh release create'), isFalse, reason: '${e.key} δεν δημοσιεύει');
      }
      expect(j['build'], contains('keytool -list'));
      expect(j['build'], contains('assetlinks.json'));
      expect(j['build'], contains('actions/upload-artifact'));
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
}
