// «Δοκιμή φωνής» (αίτημα χρήστη 15/11): κουμπί στις Ρυθμίσεις που ανοίγει την εφαρμογή στο ρολόι· το ρολόι λέει τη
// φράση με τον δρόμο του περπατήματος και γράφει πού ακούστηκε. Εδώ: τα κείμενα, η ανάγνωση του αποτελέσματος από το
// ρολόι, και ότι οι κωδικοί είναι ίδιοι με του ρολογιού.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/pages/settings.dart' show voiceTestGoText, voiceTestSubtitle, voiceTestText;
import 'package:ygeia_forma/training/wear_link.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('κείμενα', () {
    test('πού ακούστηκε, για κάθε κωδικό του ρολογιού', () {
      expect(voiceTestText('wh'), 'στα ακουστικά του ρολογιού');
      expect(voiceTestText('ph'), 'στα ακουστικά του κινητού');
      expect(voiceTestText('ws'), 'από το ηχείο του ρολογιού');
      expect(voiceTestText('m0'), contains('ένταση πολυμέσων'));
      expect(voiceTestText('mu'), startsWith('πουθενά'));
      expect(voiceTestText('nv'), startsWith('πουθενά'));
      expect(voiceTestText('bz'), contains('άσκηση'));
      // Άγνωστος κωδικός (νεότερο ρολόι): ό,τι κάνει το ρολόι από προεπιλογή.
      expect(voiceTestText('zz'), 'από το ηχείο του ρολογιού');
    });

    test('ίδιοι κωδικοί με το ρολόι (Protocol.kt: VoiceTest)', () {
      final kt = File('android/wear/src/main/kotlin/gr/ygeiaforma/wear/Protocol.kt').readAsStringSync();
      for (final code in ['wh', 'ph', 'ws', 'nv', 'mu', 'm0', 'bz']) {
        expect(kt, contains('= "$code"'), reason: code);
      }
      // 10 δευτερόλεπτα, όπως λέει το κείμενο.
      expect(kt, contains('const val DELAY_MS = 10_000L'));
      expect(voiceTestGoText, contains('Σε 10 δευτερόλεπτα'));
    });

    test('η γραμμή κάτω από το κουμπί', () {
      final now = DateTime(2026, 11, 15, 9, 30);
      String sub({bool on = true, bool near = true, bool knows = true, ({DateTime at, String code})? last}) =>
          voiceTestSubtitle(voiceOn: on, watchNear: near, watchKnows: knows, last: last, now: now);
      expect(sub(on: false), 'Άνοιξε πρώτα τη «Φωνή στην άσκηση».');
      expect(sub(near: false), 'Χρειάζεται το ρολόι κοντά, με την εφαρμογή.');
      expect(sub(knows: false), contains('119'));
      expect(sub(), contains('όπως στο περπάτημα'));
      expect(sub(last: (at: DateTime(2026, 11, 15, 9, 20), code: 'ws')), 'Τελευταία δοκιμή 09:20: από το ηχείο του ρολογιού.');
      expect(sub(last: (at: DateTime(2026, 11, 14, 23, 5), code: 'ph')), 'Τελευταία δοκιμή 14/11 23:05: στα ακουστικά του κινητού.');
    });
  });

  group('από το ρολόι', () {
    test('«vtok» και «vt» στο «/ygeia/wstate»', () {
      final link = WearLink();
      expect(link.watchVoiceTest.value, isFalse);
      link.applyWatchState('{"v":1,"lim":0,"planAt":5}');
      expect(link.watchVoiceTest.value, isFalse);
      expect(link.voiceTest.value, isNull);
      link.applyWatchState('{"v":1,"lim":0,"planAt":5,"vtok":1,"vt":{"at":1763190000000,"w":"ws"}}');
      expect(link.watchVoiceTest.value, isTrue);
      expect(link.voiceTest.value?.code, 'ws');
      expect(link.voiceTest.value?.at, DateTime.fromMillisecondsSinceEpoch(1763190000000));
      // Χαλασμένο «vt»: μένει το προηγούμενο.
      link.applyWatchState('{"v":1,"lim":0,"planAt":5,"vtok":1,"vt":{"at":"x"}}');
      expect(link.voiceTest.value?.code, 'ws');
    });

    test('χωρίς ρολόι κοντά ή χωρίς νέα έκδοση στο ρολόι: δεν ξεκινά', () async {
      final link = WearLink();
      expect(await link.startVoiceTest(), isFalse);
      link.ready.value = true;
      expect(await link.startVoiceTest(), isFalse);
    });
  });
}
