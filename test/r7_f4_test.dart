// Round 7, f4 (αποθήκευση, ασφάλεια, CI): δοκιμές για τα ευρήματα R7-A9-1…5, R7-A11-2/4/5, R7-A12-10/11.
// Όλα τα δεδομένα είναι επινοημένα (καμία πραγματική τιμή).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/backup.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/error_report.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/oura/oura_api.dart';
import 'package:ygeia_forma/oura/oura_store.dart';
import 'package:ygeia_forma/pages/diagnostics_sheet.dart';
import 'package:ygeia_forma/pages/privacy_page.dart';
import 'package:ygeia_forma/pages/settings.dart';
import 'package:ygeia_forma/plan_file.dart';
import 'package:ygeia_forma/sources.dart';

import 'sample_data.dart';

DateTime _add(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// Η πλευρά Android στο «ygeia/samsung» (ρυθμίσεις, μέρες, ανάγνωση κομματιών, κατάσταση βάσης).
class _Phone {
  _Phone(this.now);
  final DateTime now;
  Map<String, dynamic> prefs = {};
  final days = <String, Map<String, double>>{};
  String range = '{"ok":false,"kind":"other"}';
  int? corrupt;
  final rangeCalls = <String>[];

  /// Καλείται σε κάθε αποθήκευση ρυθμίσεων, πριν απαντήσει η «Android».
  Future<void> Function(Map<String, dynamic> saved)? onSave;

  void install() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('ygeia/samsung'), (call) async {
      final args = call.arguments is Map ? call.arguments as Map : const {};
      switch (call.method) {
        case 'loadPrefs':
          return jsonEncode(prefs);
        case 'savePrefs':
          prefs = jsonDecode(args['json'] as String) as Map<String, dynamic>;
          final hook = onSave;
          if (hook != null) await hook(prefs);
          return '{"ok":true}';
        case 'loadDays':
          return jsonEncode({
            'ok': true,
            'days': [for (final e in days.entries) {'date': e.key, 'data': e.value}],
          });
        case 'saveDays':
          for (final row in jsonDecode(args['json'] as String) as List) {
            final r = row as Map;
            days[r['date'] as String] = {
              for (final e in (r['data'] as Map).entries) e.key as String: (e.value as num).toDouble(),
            };
          }
          return '{"ok":true}';
        case 'dashboard':
          return jsonEncode(sampleDashboardJson(now));
        case 'cachedDashboard':
          return '{}';
        case 'readRange':
          rangeCalls.add('${args['from']}..${args['to']}');
          return range;
        case 'dbStatus':
          return jsonEncode({'ok': true, if (corrupt != null) 'corrupt': corrupt});
      }
      return '{"ok":true}';
    });
    m.setMockMethodCallHandler(const MethodChannel('ygeia/oura'), (call) async => null);
    m.setMockMethodCallHandler(const MethodChannel('ygeia/errors'), (call) async => null);
  }
}

/// Η βάση του φαγητού στο «ygeia/food»: [log] και [mine] είναι η «νέα» βάση· [keptLog]/[keptMine] ό,τι διαβάζεται από
/// το αρχείο που κρατήθηκε μετά από βλάβη. Το «restorePut» γράφει μόνο ό,τι λείπει (όπως το CONFLICT_IGNORE).
class _FoodDb {
  final log = <String, Map<String, dynamic>>{};
  final mine = <String, Map<String, dynamic>>{};
  List<Map<String, dynamic>> keptLog = [];
  List<Map<String, dynamic>> keptMine = [];
  String? done;
  final calls = <MethodCall>[];

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('ygeia/food'), (call) async {
      calls.add(call);
      final args = call.arguments is Map ? Map<String, dynamic>.from(call.arguments as Map) : <String, dynamic>{};
      switch (call.method) {
        case 'logRange':
          final from = args['from'] as String, to = args['to'] as String;
          return jsonEncode({
            'ok': true,
            'entries': [
              for (final e in log.values)
                if ((e['day'] as String).compareTo(from) >= 0 && (e['day'] as String).compareTo(to) <= 0) e,
            ],
          });
        case 'myFoods':
          return jsonEncode({'ok': true, 'foods': mine.values.toList()});
        case 'logPut':
          final j = jsonDecode(args['json'] as String) as Map<String, dynamic>;
          log[j['id'] as String] = j;
          return '{"ok":true}';
        case 'logDelete':
          log.remove(args['id']);
          return '{"ok":true}';
        case 'myFoodDelete':
          mine.remove(args['id']);
          return '{"ok":true}';
        case 'restorePut':
          var e = 0, f = 0;
          for (final x in jsonDecode(args['log'] as String) as List) {
            final j = Map<String, dynamic>.from(x as Map);
            if (!log.containsKey(j['id'])) {
              log[j['id'] as String] = j;
              e++;
            }
          }
          for (final x in jsonDecode(args['foods'] as String) as List) {
            final j = Map<String, dynamic>.from(x as Map);
            if (!mine.containsKey(j['id'])) {
              mine[j['id'] as String] = j;
              f++;
            }
          }
          return jsonEncode({'ok': true, 'entries': e, 'foods': f});
        case 'salvageRead':
          final d = done;
          if (d != null) {
            final p = d.split(' ');
            return jsonEncode({'ok': true, 'done': true, 'entries': int.parse(p[1]), 'foods': int.parse(p[2])});
          }
          return jsonEncode({'ok': true, 'found': true, 'entries': keptLog, 'foods': keptMine});
        case 'salvageDone':
          done = '${args['at']} ${args['entries']} ${args['foods']}';
          return '{"ok":true}';
      }
      return '{"ok":true}';
    });
  }
}

Map<String, dynamic> _food(String id, {double kcal = 120}) => {
      'id': id,
      'name': 'Προϊόν $id',
      'cat': 'Τα προϊόντα μου',
      'source': 'Ετικέτα',
      'n': {'kcal': kcal, 'protein': 8},
    };

Map<String, dynamic> _entry(String id, DateTime at, {double grams = 150, Map<String, dynamic>? food}) => {
      'id': id,
      'day': dateKey(at),
      'meal': 'lunch',
      'food': food ?? _food('F-$id'),
      'grams': grams,
      'time': at.millisecondsSinceEpoch,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Σταθερό «τώρα» για όσα το δέχονται· ό,τι διαβάζει το ρολόι του μηχανήματος έχει μεγάλα περιθώρια (μέρες, όχι ώρες).
  final real = DateTime.now();
  final now = DateTime(real.year, real.month, real.day, 15);
  final today = dayOf(now);

  HealthStore app(_Phone a, {SourcePlan? plan, DateTime? clock}) {
    a.install();
    final at = clock ?? now;
    return HealthStore()
      ..planFile = MemoryPlanFile(plan == null ? null : encodePlanFile(plan, at, at: 1))
      ..ouraNightsFile = MemoryNightsFile()
      ..ouraClock = (() => at)
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
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  // ---------------------------------------------------------------------------------------------------------------
  group('R7-A9-1: μετά από βλάβη της βάσης ξαναμπαίνουν και το φαγητό και τα προϊόντα', () {
    test('dbRecoveryRows: πρώτα η μνήμη, μετά ό,τι λείπει από το αρχείο· όχι ό,τι σβήστηκε, όχι ό,τι δεν θα έγραφε η εφαρμογή', () {
      final m1 = LogEntry.fromJson(_entry('E1', DateTime(2026, 3, 2, 13)));
      final kept = [
        _entry('E1', DateTime(2026, 3, 2, 13), grams: 999), // ίδιο id με τη μνήμη: μετρά η μνήμη
        _entry('E2', DateTime(2026, 3, 1, 13)),
        _entry('E3', DateTime(2026, 3, 1, 20)), // σβήστηκε σε αυτή τη χρήση
        _entry('E4', DateTime(2026, 2, 28, 9), grams: 0), // 0 g: δεν το γράφει ποτέ η εφαρμογή
        {'id': 'E5', 'day': '2026-02-31', 'meal': 'lunch', 'food': _food('F5'), 'grams': 100, 'time': 1}, // μέρα που δεν υπάρχει
        {'χαλασμένο': true},
      ];
      final r = dbRecoveryRows(
        memoryEntries: [m1],
        memoryFoods: [Food.fromJson(_food('M1'))],
        keptEntries: kept,
        keptFoods: [_food('M1', kcal: 1), _food('M2'), _food('M3'), {'id': 'M4', 'name': ' ', 'n': <String, Object>{}}],
        removedEntries: {'E3'},
        removedFoods: {'M3'},
      );
      expect([for (final x in r.log) x['id']], ['E1', 'E2']);
      expect(r.log.first['grams'], 150, reason: 'η μνήμη (ό,τι βλέπει ο χρήστης) πριν από το παλιό αρχείο');
      expect([for (final x in r.foods) x['id']], ['M1', 'M2']);
      expect(r.skipped, 4, reason: 'E4 (0 g), E5 (μέρα), το χαλασμένο, M4 (χωρίς όνομα)');
    });

    test('FoodStore: η μνήμη και το κρατημένο αρχείο στη νέα βάση, σε μία κλήση· όχι ό,τι έσβησε ο χρήστης· μία φορά', () async {
      final db = _FoodDb()..install();
      final d1 = _add(today, -1), d2 = _add(today, -2), old = _add(today, -200);
      for (final e in [_entry('E1', DateTime(d1.year, d1.month, d1.day, 13)), _entry('E2', DateTime(d2.year, d2.month, d2.day, 9)),
        _entry('E3', DateTime(d2.year, d2.month, d2.day, 20)), _entry('EOLD', DateTime(old.year, old.month, old.day, 13))]) {
        db.log[e['id'] as String] = e;
      }
      db.mine['M1'] = _food('M1');
      final s = FoodStore();
      addTearDown(s.dispose);
      await s.start();
      expect(s.loaded, isTrue);
      expect(s.entriesFor(d2).map((e) => e.id), containsAll(['E2', 'E3']));
      // Βλάβη: η Kotlin κράτησε το παλιό αρχείο και άνοιξε άδεια βάση.
      db.keptLog = db.log.values.map((e) => Map<String, dynamic>.from(e)).toList();
      db.keptMine = db.mine.values.map((e) => Map<String, dynamic>.from(e)).toList();
      db.log.clear();
      db.mine.clear();
      // Μετά τη βλάβη: σβήνει το E3 (μόνο στη μνήμη) και γράφει το E4 (στη νέα βάση).
      await s.remove(s.entriesFor(d2).firstWhere((e) => e.id == 'E3'));
      await s.update(LogEntry.fromJson(_entry('E4', DateTime(today.year, today.month, today.day, 8))));
      db.calls.clear();
      final r = await s.recoverAfterDbReset(4242);
      expect(r, (entries: 3, foods: 1), reason: 'E1, E2 (μνήμη), EOLD (αρχείο)· M1');
      expect(db.log.keys.toSet(), {'E1', 'E2', 'E4', 'EOLD'}, reason: 'το E3 που σβήστηκε δεν ξαναμπαίνει');
      expect(db.mine.keys.toSet(), {'M1'});
      expect(db.calls.where((c) => c.method == 'restorePut'), hasLength(1));
      expect(db.done, '4242 3 1');
      expect(s.mine.map((f) => f.id), ['M1']);
      expect(s.entriesFor(d1).map((e) => e.id), ['E1']);
      // Ξανά (π.χ. επόμενη ανανέωση): τίποτα δεν ξαναγράφεται.
      db.calls.clear();
      expect(await s.recoverAfterDbReset(4242), isNull);
      expect(db.calls.where((c) => c.method == 'restorePut'), isEmpty);
    });

    test('FoodStore: έγινε ήδη σε προηγούμενο άνοιγμα → τα ίδια νούμερα, καμία εγγραφή', () async {
      final db = _FoodDb()
        ..done = '777 5 2'
        ..install();
      final s = FoodStore();
      addTearDown(s.dispose);
      await s.start();
      db.calls.clear();
      expect(await s.recoverAfterDbReset(777), (entries: 5, foods: 2));
      expect(db.calls.map((c) => c.method), ['salvageRead']);
    });

    test('HealthStore: η βλάβη ζητά την επαναφορά του φαγητού ΜΙΑ φορά και την κάρτα με τα νούμερα', () async {
      final a = _Phone(now)
        ..prefs = {'historyVersion': historyRulesVersion}
        ..corrupt = 5678;
      final s = app(a);
      final asked = <int>[];
      s.onDatabaseReset = (at) async {
        asked.add(at);
        return (entries: 2, foods: 1);
      };
      await s.loadPrefs();
      await s.start();
      await settle(s);
      await s.refresh();
      await settle(s);
      expect(asked, [5678], reason: 'στην εκκίνηση και στις ανανεώσεις: μία φορά για κάθε βλάβη');
      expect(s.dbCorruptAt, 5678);
      expect(s.dbRecovered, (entries: 2, foods: 1));
      expect(a.prefs['dbReset'], 5678);
      s.dispose();
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R7-A9-2: η κάρτα «Η βάση χάλασε»', () {
    test('σωστή διαδρομή, και τα προϊόντα· πόσα ξαναμπήκαν', () {
      final none = databaseNoticeText(null);
      expect(none, contains('Ρυθμίσεις › Τα δεδομένα μου › Επαναφορά από αντίγραφο'));
      expect(none, contains('τα προϊόντα σου'));
      expect(none, isNot(contains('Ρυθμίσεις › Αντίγραφο ασφαλείας')));
      expect(databaseNoticeText((entries: 0, foods: 0)), none);
      final some = databaseNoticeText((entries: 120, foods: 3));
      expect(some, contains('Ξαναμπήκαν 120 καταχωρίσεις φαγητού και 3 προϊόντα.'));
      expect(some, contains('Επαναφορά από αντίγραφο'));
      expect(databaseNoticeText((entries: 1, foods: 0)), contains('Ξαναμπήκε 1 καταχώριση φαγητού.'));
      expect(databaseNoticeText((entries: 0, foods: 1)), contains('Ξαναμπήκε 1 προϊόν.'));
      // Round 9 (R9-A9-B1): η κάρτα λέει και όταν κάτι δεν διαβάστηκε.
      expect(File('lib/pages/today.dart').readAsStringSync(),
          contains('databaseNoticeText(store.dbRecovered, partial: store.dbPartial)'));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R7-A9-3: η σύνοψη λέει γιατί δεν μπήκαν οι πηγές ύπνου', () {
    String file(SourcePlan p, int at) => encodePlanFile(p, now, at: at);

    test('ρυθμίσεις που δεν διαβάστηκαν → «δεν διαβάζονται», όχι «νεότερες»', () async {
      final a = _Phone(now);
      final s = app(a);
      final r = await s.restoreSourcesWhy((plan: file(SourcePlan.samsungOnly.withEra(Source.oura, _add(today, -30)), 1000), log: null));
      expect(r, SourcesRestore.notReady);
      expect(sourcesRestoreText(r), isNot(contains('νεότερες')));
      s.dispose();
    });

    test('η εγγραφή απέτυχε → «δεν γράφτηκαν»· ίδιο αντίγραφο δεύτερη φορά → «ίδιες»', () async {
      final a = _Phone(now)..prefs = {'historyVersion': historyRulesVersion, 'backfillFrom': dateKey(_add(today, -4000))};
      final s = app(a);
      await s.loadPrefs();
      await s.start();
      await settle(s);
      final backup = (plan: file(SourcePlan.samsungOnly.withEra(Source.oura, _add(today, -30)), 1000), log: null);
      (s.planFile as MemoryPlanFile).failWrites = true;
      expect(await s.restoreSourcesWhy(backup), SourcesRestore.writeFailed);
      (s.planFile as MemoryPlanFile).failWrites = false;
      expect(await s.restoreSourcesWhy(backup), SourcesRestore.restored);
      expect(await s.restoreSourcesWhy(backup), SourcesRestore.same);
      expect(await s.restoreSources(backup), isFalse, reason: 'το παλιό API μένει ίδιο');
      s.dispose();
    });

    test('κάθε λόγος έχει δική του πρόταση· «νεότερες» μόνο όταν είναι νεότερες', () {
      for (final r in SourcesRestore.values) {
        expect(sourcesRestoreText(r).contains('νεότερες'), r == SourcesRestore.phoneNewer, reason: '$r');
      }
      expect(sourcesRestoreText(SourcesRestore.writeFailed), contains('δεν γράφτηκαν'));
      expect(sourcesRestoreText(SourcesRestore.same), contains('ίδιες'));
      expect(sourcesRestoreText(SourcesRestore.restored), 'Οι πηγές ύπνου μπήκαν από το αντίγραφο.');
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R7-A9-4: η επαναφορά πηγών στη μέση μιας συμπλήρωσης', () {
    test('το «ξαναδιάβασε από την αρχή» δεν χάνεται: η συμπλήρωση που τρέχει σταματά χωρίς να γράψει τη θέση της', () async {
      final x = _add(today, -200);
      final a = _Phone(now)
        ..prefs = {'historyVersion': historyRulesVersion}
        // Κάθε κομμάτι «διαβάζεται» (ύπνος μόνο από άλλη συσκευή, πριν από τον πρώτο του ρολογιού): προχωρά κανονικά.
        ..range = jsonEncode({
          'ok': true,
          'sleep': [],
          'nonWatch': ['sleep'],
          'firstWatchSleep': _add(today, -6).millisecondsSinceEpoch,
          'readAt': now.millisecondsSinceEpoch,
        });
      a.days[dateKey(_add(x, 5))] = {K.spo2Avg: 94, K.dayHr: 71, K.steps: 2000};
      a.days[dateKey(_add(x, -5))] = {K.spo2Avg: 95, K.dayHr: 70, K.steps: 1000};
      final s = app(a);
      var triggered = false;
      Future<bool>? restoring;
      // Μόλις η συμπλήρωση γράψει την πρώτη της θέση, μπαίνει αντίγραφο με Oura από τη μέρα x: οι μέρες γύρω από το x
      // χάνουν οξυγόνο/παλμούς μέρας του άλλου ορισμού και το ιστορικό πρέπει να ξαναδιαβαστεί από την αρχή.
      a.onSave = (saved) async {
        if (triggered || saved['backfillFrom'] == null) return;
        triggered = true;
        restoring = s.restoreSources((plan: encodePlanFile(SourcePlan.samsungOnly.withEra(Source.oura, x), now, at: 99), log: null));
        for (var i = 0; i < 500 && s.prefs.backfillFrom != null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      };
      await s.loadPrefs();
      await s.start();
      await settle(s);
      expect(triggered, isTrue, reason: 'η συμπλήρωση έγραψε θέση (το σενάριο έγινε)');
      expect(await restoring, isTrue);
      await settle(s);
      expect(a.days[dateKey(_add(x, 5))], {K.steps: 2000}, reason: 'ο άλλος ορισμός έφυγε');
      expect(s.prefs.backfillFrom, isNull, reason: 'ξαναδιαβάζεται από την αρχή (πριν: η παλιά θέση ξαναγραφόταν)');
      expect(a.prefs['backfillFrom'], isNull);
      s.dispose();
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R7-A9-5: ελληνικά μηνύματα αντί για το κείμενο της Java', () {
    test('αποθήκευση και άνοιγμα αντιγράφου', () {
      expect(backupSaveFailText({'ok': false, 'kind': 'full', 'message': 'write failed: ENOSPC (No space left on device)'}),
          contains('δεν χωράει στο κινητό'));
      final other = backupSaveFailText({'ok': false, 'kind': 'other', 'message': 'write failed: ENOSPC (No space left on device)'});
      expect(other, isNot(contains('ENOSPC')));
      expect(other, contains('Δοκίμασε ξανά'));
      final cut = backupOpenFailText({'ok': false, 'kind': 'damaged'});
      expect(cut, contains('κομμένο ή χαλασμένο'));
      expect(cut, contains('δεν άλλαξε τίποτα'));
      expect(backupOpenFailText({'ok': false, 'kind': 'too_big'}), contains('πολύ μεγάλο'));
      expect(backupOpenFailText({'ok': false, 'kind': 'other', 'message': 'Unexpected end of ZLIB input stream'}),
          isNot(contains('ZLIB')));
      for (final f in ['lib/pages/settings.dart', 'lib/pages/diagnostics_sheet.dart']) {
        expect(File(f).readAsStringSync(), isNot(contains("r['message']")), reason: f);
      }
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R7-A11-2: «Αναφορά για έλεγχο»: τα κείμενα λένε την αλήθεια', () {
    test('φύλλο, λίστα «Δεν σβήνονται», πολιτική απορρήτου, αρχική σελίδα', () {
      expect(diagnosticsIntroText, contains('Oura'));
      expect(diagnosticsIntroText, contains('ύπνο'));
      expect(diagnosticsPrivacyText, contains('χωρίς κλείδωμα'));
      expect(diagnosticsPrivacyText, contains('AI'));
      expect(wipeKeeps.any((k) => k.contains('αναφορές για έλεγχο')), isTrue);
      final page = File('site/public/privacy/index.html').readAsStringSync();
      final greek = page.split('lang="en"').first;
      final english = page.substring(greek.length);
      expect(greek, contains('«Αναφορά για έλεγχο» (Ρυθμίσεις › Τα δεδομένα μου)'));
      expect(greek, contains('(αντίγραφο, PDF, «Αναφορά για έλεγχο»)'));
      expect(english, contains('diagnostics'));
      expect(greek, isNot(contains('Τα δεδομένα της Oura δεν δίνονται σε τρίτους και δεν χρησιμοποιούνται για εκπαίδευση ή λειτουργία')));
      final index = File('site/public/index.html').readAsStringSync();
      expect(index, isNot(contains('Δεν δίνονται ποτέ σε άλλους ούτε σε AI')));
      expect(File('tools/ci/check_privacy.py').readAsStringSync(), contains("'«Αναφορά για έλεγχο»' in greek"));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R7-A11-4: η αντίρρηση στις αναφορές σφαλμάτων ταξιδεύει με το αντίγραφο', () {
    String backup({bool errorsOff = false}) => buildBackup(
          foodLog: const [],
          myFoods: const [],
          prefs: const {},
          now: DateTime(2026, 11, 1, 10),
          errorsOff: errorsOff,
        );

    test('μπαίνει μόνο όταν είναι κλειστές· τα παλιά αντίγραφα διαβάζονται όπως πριν', () {
      expect((jsonDecode(backup(errorsOff: true)) as Map)['errorsOff'], isTrue);
      expect((jsonDecode(backup()) as Map).containsKey('errorsOff'), isFalse);
      expect(parseBackup(backup(errorsOff: true)).errorsOff, isTrue);
      expect(parseBackup(backup()).errorsOff, isFalse);
    });

    test('η επαναφορά τις κλείνει (γράφεται πρώτα η επιλογή)· ποτέ δεν τις ανοίγει', () async {
      final persisted = <bool>[];
      final r = ErrorReporter(persist: (on) async => persisted.add(on));
      expect(await restoreErrorsChoice(parseBackup(backup()), r), isFalse);
      expect(r.enabled, isTrue);
      expect(persisted, isEmpty);
      expect(await restoreErrorsChoice(parseBackup(backup(errorsOff: true)), r), isTrue);
      expect(r.enabled, isFalse);
      expect(persisted, [false]);
      expect(await restoreErrorsChoice(parseBackup(backup(errorsOff: true)), r), isFalse, reason: 'ήδη κλειστές');
      expect(persisted, [false]);
      final settings = File('lib/pages/settings.dart').readAsStringSync();
      expect(settings, contains('errorsOff: !errors.enabled'));
      expect(settings.indexOf('restoreErrorsChoice(b, errors)'), lessThan(settings.indexOf('importBackup(b.entries')),
          reason: 'πριν από οτιδήποτε άλλο της επαναφοράς');
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R7-A11-5: μόνο η https διεύθυνση επιστροφής (ο μεσάζων δεν δέχεται άλλη)', () {
    test('καμία «αλλαγή μίας γραμμής» προς το ygeiaforma:// στα κείμενα', () {
      expect(File('lib/oura/config.dart').readAsStringSync(), isNot(contains('const ouraRedirectUri = ouraRedirectCustom;')));
      expect(File('README.md').readAsStringSync(), isNot(contains('αλλαγή μίας γραμμής στο `ouraRedirectUri`')));
      expect(File('site/README.md').readAsStringSync(), isNot(contains('μία από τις δύο δηλωμένες διευθύνσεις επιστροφής')));
      expect(File('site/netlify/functions/oura-token.mjs').readAsStringSync(), isNot(contains("'ygeiaforma://oura-callback',")));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R7-A12-10: πύλες του CI', () {
    test('όλα τα *_test.dart (και σε υποφακέλους)· κατώτατα κοντά στο πλήθος· ρολόι χωριστά', () {
      for (final f in ['.github/workflows/check.yml', '.github/workflows/android.yml']) {
        final y = File(f).readAsStringSync();
        expect(y, isNot(contains('ls test/*_test.dart')), reason: f);
        expect(y, contains("find test -name '*_test.dart'"), reason: f);
        // Round 8 (R8-A12-2): ≈ 3% κάτω από το #105 (1.832 / 85 / 167)· πριν 1550 / 70 / 128 (15–23% κάτω).
        // Round 9 (R9-A12-1): το ύψος των τριών κατώτατων το ελέγχει το r8_f4_test (κοντά στις τωρινές δοκιμές).
        expect(RegExp(r'-lt \d+ \]').allMatches(y).length, 3, reason: f);
        for (final old in ['-lt 950 ', '-lt 1550 ', '-lt 1777 ', '-lt 82 ', '-lt 162 ']) {
          expect(y, isNot(contains(old)), reason: '$f: $old');
        }
      }
      // Κάθε αρχείο δοκιμών είναι κάτω από το test/ (το «find» τα βρίσκει όλα).
      final tests = Directory('test').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('_test.dart'));
      expect(tests.length, greaterThan(70));
    });

    test('η αναβάθμιση στο main αποτυγχάνει όταν δεν μπορεί να δοκιμάσει με δείγμα (εκτός «[skip-upgrade]»)', () {
      final sh = File('tools/perf/upgrade.sh').readAsStringSync();
      expect(sh, contains('if [ "\${GITHUB_REF:-}" = "refs/heads/main" ] && [ "\${SKIP_UPGRADE:-false}" != "true" ]; then strict=1; fi'));
      expect(sh, contains('weak "Χωρίς root στον emulator'));
      expect(sh, contains('weak "Ο emulator δεν έχει sqlite3'));
      expect('::warning'.allMatches(sh).length, 1, reason: 'μία μόνο προειδοποίηση, μέσα στο weak()');
      final yml = File('.github/workflows/android.yml').readAsStringSync();
      final step = yml.substring(yml.indexOf('- name: Άνοιγμα και αναβάθμιση σε emulator'));
      expect(step.substring(0, 400), contains("SKIP_UPGRADE: \${{ contains(github.event.head_commit.message, '[skip-upgrade]') }}"));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R7-A12-11: η συμπλήρωση του ιστορικού με το ρολόι της αποθήκης (όχι του μηχανήματος)', () {
    final fixed = DateTime(2031, 3, 10, 15);
    final fixedDay = dayOf(fixed);

    test('rereadBoundary και backfillVisible από το ouraClock', () {
      final s = HealthStore()..ouraClock = (() => fixed);
      s.prefs.rereadVersion = historyRulesVersion;
      s.prefs.backfillFrom = null;
      expect(s.rereadBoundary, _add(fixedDay, -(recentSummaryDays - 1)));
      s.backfilling = true;
      s.backfillReached = _add(fixedDay, -460);
      expect(s.backfillVisible, isFalse, reason: 'πάνω από 455 μέρες πριν από το «σήμερα» της αποθήκης');
      s.backfillReached = _add(fixedDay, -400);
      expect(s.backfillVisible, isTrue);
      s.dispose();
    });

    test('το πρώτο κομμάτι της συμπλήρωσης μετριέται από το «σήμερα» της αποθήκης', () async {
      final a = _Phone(fixed)..prefs = {'historyVersion': historyRulesVersion};
      a.days[dateKey(_add(fixedDay, -100))] = {K.steps: 5000};
      final s = app(a, clock: fixed);
      await s.loadPrefs();
      await s.start();
      await settle(s);
      expect(a.rangeCalls, isNotEmpty);
      expect(a.rangeCalls.first, '${dateKey(_add(fixedDay, -36))}..${dateKey(_add(fixedDay, -6))}');
      s.dispose();
    });
  });
}
