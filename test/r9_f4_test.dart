// Round 9, f4 (αποθήκευση, ασφάλεια, CI, κείμενα): δοκιμές για τα ευρήματα R9-A9-B1, R9-U4-4, R9-U4-8, R9-A11-1,
// R9-A11-2 (= R9-U4-9), R9-A11-3. Οι κανόνες της ανάγνωσης της χαλασμένης βάσης (R9-A9-1…4) και η απάντηση «dbStatus»
// (R9-A12-2) ελέγχονται με τιμές στο android/app/src/test/…/R9F4Test.kt· τα κατώτατα του CI (R9-A12-1) στο r8_f4_test.
// Όλα τα δεδομένα είναι επινοημένα.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/oura/config.dart';
import 'package:ygeia_forma/oura/oura_api.dart';
import 'package:ygeia_forma/oura/oura_store.dart';
import 'package:ygeia_forma/pages/oura_pages.dart';
import 'package:ygeia_forma/pages/report_page.dart';
import 'package:ygeia_forma/pages/settings.dart';
import 'package:ygeia_forma/plan_file.dart';
import 'package:ygeia_forma/report.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/theme.dart';

import 'sample_data.dart';

/// Η πλευρά Android στο «ygeia/samsung», με το «dbStatus» του R9-A12-2 ({"corrupt", "seen", "partial"}).
class _Phone {
  _Phone(this.now);
  final DateTime now;
  Map<String, dynamic> prefs = {'historyVersion': historyRulesVersion};
  int? corrupt;
  int? seenAt;

  /// Το σημάδι «έγινε» της βλάβης λέει «δεν διαβάστηκαν όλα».
  bool partial = false;

  void install() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('ygeia/samsung'), (call) async {
      final args = call.arguments is Map ? call.arguments as Map : const {};
      switch (call.method) {
        case 'loadPrefs':
          return jsonEncode(prefs);
        case 'savePrefs':
          prefs = jsonDecode(args['json'] as String) as Map<String, dynamic>;
          return '{"ok":true}';
        case 'loadDays':
          return jsonEncode({'ok': true, 'days': []});
        case 'dashboard':
          return jsonEncode(sampleDashboardJson(now));
        case 'cachedDashboard':
          return '{}';
        case 'readRange':
          return '{"ok":false,"kind":"other"}';
        case 'dbStatus':
          return jsonEncode({
            'ok': true,
            'corrupt': corrupt,
            'seen': corrupt != null && seenAt == corrupt,
            'partial': corrupt != null && partial,
          });
        case 'dbStatusSeen':
          final at = args['at'];
          if (at is int) seenAt = at;
          return '{"ok":true}';
      }
      return '{"ok":true}';
    });
    m.setMockMethodCallHandler(const MethodChannel('ygeia/oura'), (call) async => null);
    m.setMockMethodCallHandler(const MethodChannel('ygeia/errors'), (call) async => null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final real = DateTime.now();
  final now = DateTime(real.year, real.month, real.day, 15);

  HealthStore app(_Phone a) {
    a.install();
    return HealthStore()
      ..planFile = MemoryPlanFile(null)
      ..ouraNightsFile = MemoryNightsFile()
      ..ouraClock = (() => now)
      ..ouraLink = OuraLink(
        vault: MemoryVault(),
        send: (m, u, {headers = const {}, form}) async => const OuraResponse(500, '{}'),
        clientId: 'CID',
      );
  }

  Future<void> settle(HealthStore s) async {
    for (var i = 0; i < 400 && (s.backfilling || s.loading); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  // ---------------------------------------------------------------------------------------------------------------
  group('R9-A9-B1: η κάρτα «Η βάση χάλασε» λέει καθαρά όταν κάτι δεν διαβάστηκε', () {
    const path = '(Ρυθμίσεις › Τα δεδομένα μου › Επαναφορά από αντίγραφο)';

    test('κείμενα: με και χωρίς «δεν διαβάστηκε όλο»', () {
      // Όλα διαβάστηκαν: τα κείμενα του γύρου 7, όπως ήταν.
      expect(databaseNoticeText((entries: 120, foods: 3)), contains('Ξαναμπήκαν 120 καταχωρίσεις φαγητού και 3 προϊόντα. Αν λείπει κάτι'));
      expect(databaseNoticeText(null), databaseNoticeText(null, partial: false));
      expect(databaseNoticeText((entries: 120, foods: 3)), isNot(contains('δεν διαβάστηκε όλο')));
      // Κάτι δεν διαβάστηκε: το λέει, χωρίς «αν».
      final some = databaseNoticeText((entries: 120, foods: 3), partial: true);
      expect(some, contains('Ξαναμπήκαν 120 καταχωρίσεις φαγητού και 3 προϊόντα, αλλά το παλιό αρχείο δεν διαβάστηκε όλο.'));
      expect(some, contains('Ό,τι λείπει ακόμα, βάλ’ το από το αντίγραφό σου $path: μπαίνουν μόνο όσα λείπουν.'));
      expect(some, isNot(contains('Αν λείπει')));
      expect(databaseNoticeText((entries: 1, foods: 0), partial: true), contains('Ξαναμπήκε 1 καταχώριση φαγητού, αλλά'));
      for (final r in [null, (entries: 0, foods: 0)]) {
        final none = databaseNoticeText(r, partial: true);
        expect(none, contains('Το παλιό αρχείο δεν διαβάστηκε όλο: ό,τι λείπει από το ημερολόγιο φαγητού και τα προϊόντα σου'));
        expect(none, contains(path));
        expect(none, isNot(contains('επανέρχονται')));
      }
    });

    test('η επαναφορά δεν διάβασε όλα: η κάρτα το ξέρει μόλις τελειώσει (όχι στο επόμενο άνοιγμα)· «Εντάξει» το σβήνει',
        () async {
      final a = _Phone(now)..corrupt = 5678;
      final s = app(a);
      s.onDatabaseReset = (at) async {
        // Η πλευρά Android γράφει το σημάδι «έγινε» με «δεν διαβάστηκαν όλα».
        a.partial = true;
        return (entries: 2, foods: 1);
      };
      await s.loadPrefs();
      await s.start();
      await settle(s);
      expect(s.dbCorruptAt, 5678);
      expect(s.dbRecovered, (entries: 2, foods: 1));
      expect(s.dbPartial, isTrue);
      expect(databaseNoticeText(s.dbRecovered, partial: s.dbPartial), contains('δεν διαβάστηκε όλο'));
      await s.dismissDatabaseNotice();
      expect(s.dbCorruptAt, isNull);
      expect(s.dbPartial, isFalse);
      s.dispose();
    });

    test('όλα διαβάστηκαν: κανένα «δεν διαβάστηκε»· και σημάδι από παλιότερο άνοιγμα διαβάζεται στην αρχή', () async {
      final a = _Phone(now)..corrupt = 5678;
      final s = app(a);
      s.onDatabaseReset = (at) async => (entries: 2, foods: 1);
      await s.loadPrefs();
      await s.start();
      await settle(s);
      expect(s.dbRecovered, (entries: 2, foods: 1));
      expect(s.dbPartial, isFalse);
      s.dispose();

      final b = _Phone(now)
        ..corrupt = 777
        ..partial = true;
      final t = app(b);
      t.onDatabaseReset = (at) async => null; // δεν τελείωσε ακόμα σε αυτή τη χρήση
      await t.loadPrefs();
      await t.start();
      await settle(t);
      expect(t.dbCorruptAt, 777);
      expect(t.dbPartial, isTrue);
      t.dispose();
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R9-U4-4: «Αναφορά για γιατρό»: αποτυχία αποθήκευσης χωρίς το κείμενο της Java', () {
    test('γεμάτος χώρος → τι να κάνεις· κάθε άλλο → «Δοκίμασε ξανά»· ποτέ το «message»', () {
      expect(pdfSaveFailText({'ok': false, 'kind': 'full', 'message': 'java.io.IOException: No space left on device'}),
          'Δεν αποθηκεύτηκε: δεν χωράει στο κινητό. Ελευθέρωσε χώρο και δοκίμασε ξανά.');
      for (final r in <Map<String, dynamic>?>[
        {'ok': false, 'kind': 'other', 'message': 'java.io.IOException: x'},
        {'ok': false, 'kind': 'other', 'message': 'java.lang.IllegalStateException: Δεν δημιουργήθηκε αρχείο στις Λήψεις'},
        {'ok': false, 'kind': 'not_android', 'message': 'Διαθέσιμο μόνο στο κινητό'},
        null,
      ]) {
        final text = pdfSaveFailText(r);
        expect(text, 'Δεν αποθηκεύτηκε. Δοκίμασε ξανά.');
        expect(text, isNot(contains('java')));
        expect(text, isNot(contains('Exception')));
      }
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R9-U4-8: «Κάρτες της Σήμερα» με το Oura: κανένας διακόπτης που δεν κάνει τίποτα', () {
    DateTime daysAgo(int n) => DateTime(now.year, now.month, now.day - n);

    test('με το Oura λείπουν Energy Score, παλμοί και θερμοκρασία ύπνου· χωρίς Oura όλες', () {
      final oura = SourcePlan.samsungOnly.withEra(Source.oura, daysAgo(10));
      final keys = [for (final c in todayCardsToChoose(oura, now)) c.key];
      expect(keys, isNot(contains('energy')));
      expect(keys, isNot(contains('rhr')));
      expect(keys, isNot(contains('skin')));
      expect(keys, containsAll(['sleep', 'food', 'steps', 'weight', 'calories', 'spo2']));
      expect(keys.length, todayCards.length - 3);
      expect(todayCardsToChoose(SourcePlan.samsungOnly, now), todayCards);
      // Το Oura από αύριο (η σύνδεση ισχύει από το βράδυ): σήμερα η νύχτα είναι ακόμα του ρολογιού.
      expect(todayCardsToChoose(SourcePlan.samsungOnly.withEra(Source.oura, daysAgo(-1)), now), todayCards);
    });

    testWidgets('η σελίδα: χωρίς τους τρεις διακόπτες και με το πού φαίνονται', (t) async {
      final s = HealthStore()..debugSetPlan(SourcePlan.samsungOnly.withEra(Source.oura, daysAgo(10)));
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: TodayCardsPage(store: s)));
      await t.pump();
      expect(find.text('Energy Score'), findsNothing);
      expect(find.text('Παλμοί στον ύπνο'), findsNothing);
      expect(find.text('Θερμοκρασία καρπού στον ύπνο'), findsNothing);
      expect(find.text('Βήματα'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsNWidgets(todayCards.length - 3));
      expect(find.text(todayCardsOuraNote), findsOneWidget);
      expect(todayCardsOuraNote, contains('«Ύπνος της νύχτας»'));

      final w = HealthStore()..debugSetPlan(SourcePlan.samsungOnly);
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: TodayCardsPage(store: w)));
      await t.pump();
      expect(find.text('Energy Score'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsNWidgets(todayCards.length));
      expect(find.byKey(const ValueKey('today-cards-oura-note')), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R9-A11-1 / R9-A11-2: τι λέμε για τα δεδομένα της Oura', () {
    test('A11-2: η σύνδεση Oura δεν υπόσχεται «ποτέ σε AI ή σε άλλους» (υπάρχουν αρχεία που στέλνει ο χρήστης)', () {
      expect(ouraConnectPrivacyText, isNot(contains('Δεν δίνονται ποτέ')));
      expect(ouraConnectPrivacyText, contains('δεν τα στέλνει σε AI'));
      expect(ouraConnectPrivacyText, contains('μπαίνουν μόνο σε αρχεία που φτιάχνεις και στέλνεις εσύ'));
      // Round 10 (R10-B8-2): «συνδρομή Oura.» με αδιάσπαστο κενό (χωρίς ορφανό «Oura.» στα 400 dp).
      expect(ouraConnectPrivacyText, contains('Χρειάζεται ενεργή συνδρομή\u00A0Oura.'));
      // Το ίδιο λάθος υπόσχεσης πουθενά στην εφαρμογή (σάρωση κειμένου: η υπόσχεση είναι κείμενο, όχι λογική).
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        expect(f.readAsStringSync(), isNot(contains('Δεν δίνονται ποτέ')), reason: f.path);
      }
    });

    test('A11-1: το PDF για τον γιατρό έχει δεδομένα της Oura → η πολιτική και οι όροι το λένε', () {
      final plan = SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 16));
      expect(reportKeysFor(plan), containsAll([K.lowHr, K.hrv, K.breath, K.ringSpo2]));
      expect(reportDays, 90);
      final page = File('site/public/privacy/index.html').readAsStringSync();
      final greek = page.split('lang="en"').first;
      final english = page.substring(greek.length);
      final oura = greek.substring(greek.indexOf('<h3>Oura</h3>'), greek.indexOf('<h3>', greek.indexOf('<h3>Oura</h3>') + 5));
      expect(oura, contains('«Αναφορά για γιατρό» (PDF, τελευταίες 90 μέρες)'));
      expect(oura, contains('«Αναφορά για έλεγχο» (τελευταίες 60 μέρες)'));
      expect(oura, isNot(contains('Μπαίνουν μόνο σε αρχείο που')));
      expect(greek, contains('με τις μετρήσεις των τελευταίων 90 ημερών (και του Oura, αν είναι συνδεδεμένο)'));
      expect(english, contains('doctor PDFs (the last 90 days of measurements, Oura data included when connected)'));
      // Η πολιτική άλλαξε: νέο αποτύπωμα στο stamp (το ελέγχει το CI, check_privacy.py).
      expect(File('tools/ci/privacy_stamp.txt').readAsStringSync(), isNot(startsWith('38b9def4')));
      final terms = File('site/public/terms/index.html').readAsStringSync();
      expect(terms, contains('«Αναφορά για γιατρό» (PDF, τελευταίες 90 μέρες)'));
      expect(terms, contains('doctor report PDF (last 90 days)'));
      expect(terms, isNot(contains('Μπαίνουν επίσης, των τελευταίων 60 ημερών, στο αρχείο')));
      expect(File('tools/ci/check_privacy.py').readAsStringSync(), contains("'«Αναφορά για γιατρό»' in oura_gr"));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R9-A11-3: οδηγίες σύνδεσης Oura = ό,τι κάνει ο κώδικας', () {
    test('η προεπιλογή είναι «daily spo2» στο portal, και το scope της απάντησης κρίνει το οξυγόνο', () {
      expect(ouraOAuth, same(OuraOAuthEndpoints.portal));
      expect(ouraScopes, isEmpty);
      final scopes = OuraOAuthEndpoints.portal.scopes;
      expect(scopes, 'daily spo2');
      final readme = File('README.md').readAsStringSync();
      expect(readme, contains('κενό = «$scopes» στο portal'));
      expect(readme, isNot(contains('Το «scope» της απάντησης δεν ελέγχεται')));
      final cfg = File('lib/oura/config.dart').readAsStringSync();
      expect(cfg, contains('(«$scopes» στο portal'));
      expect(cfg, isNot(contains('το «scope» της απάντησης δεν ελέγχεται')));
      // Η συμπεριφορά που περιγράφουν: μόνο «daily» → χωρίς οξυγόνο· «daily spo2» → με οξυγόνο.
      final at = DateTime(2026, 11, 16, 8);
      String body(String scope) =>
          jsonEncode({'access_token': 'A1', 'refresh_token': 'R1', 'expires_in': 86400, 'scope': scope});
      expect(OuraTokens.parseResponse(body('daily'), at, spo2: true).spo2, isFalse);
      expect(OuraTokens.parseResponse(body('daily spo2'), at).spo2, isTrue);
    });
  });
}
