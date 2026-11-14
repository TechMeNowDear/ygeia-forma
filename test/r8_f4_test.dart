// Round 8, f4 (αποθήκευση, ασφάλεια, CI): δοκιμές για τα ευρήματα R8-A9-1…3 (= R8-A12-1), R8-A11-1/3/4/5, R8-A12-2,
// R8-A3-2, R8-U4-4/5. Όλα τα δεδομένα είναι επινοημένα (καμία πραγματική τιμή).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/diagnostics.dart';
import 'package:ygeia_forma/error_report.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/oura/oura_api.dart';
import 'package:ygeia_forma/oura/oura_store.dart';
import 'package:ygeia_forma/pages/privacy_page.dart';
import 'package:ygeia_forma/pages/settings.dart';
import 'package:ygeia_forma/plan_file.dart';
import 'package:ygeia_forma/profile.dart';
import 'package:ygeia_forma/theme.dart';

import 'sample_checkin.dart';
import 'sample_data.dart';
import 'sample_food.dart';

DateTime _add(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// Η πλευρά Android στο «ygeia/samsung», με το συμβόλαιο του R8-A9-2: το «dbStatusSeen» γράφει μόνο «η κάρτα έκλεισε»
/// (ποτέ δεν σβήνει το σημάδι της βλάβης) και το «dbStatus» το λέει με «seen».
class _Phone {
  _Phone(this.now);
  final DateTime now;
  Map<String, dynamic> prefs = {};
  final days = <String, Map<String, double>>{};
  int? corrupt;
  int? seenAt;
  final seenCalls = <Object?>[];

  /// Οι ρυθμίσεις «δεν διαβάζονται τώρα» (kind «read») όσο είναι true.
  bool prefsFail = false;

  void install() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('ygeia/samsung'), (call) async {
      final args = call.arguments is Map ? call.arguments as Map : const {};
      switch (call.method) {
        case 'loadPrefs':
          if (prefsFail) return '{"ok":false,"kind":"read"}';
          return jsonEncode(prefs);
        case 'savePrefs':
          prefs = jsonDecode(args['json'] as String) as Map<String, dynamic>;
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
          return '{"ok":false,"kind":"other"}';
        case 'dbStatus':
          return jsonEncode({'ok': true, if (corrupt != null) 'corrupt': corrupt, 'seen': corrupt != null && seenAt == corrupt});
        case 'dbStatusSeen':
          seenCalls.add(args['at']);
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

/// Η βάση του φαγητού στο «ygeia/food» ([log], [mine] = η νέα βάση· [keptLog]/[keptMine] = ό,τι διαβάζεται από το
/// κρατημένο αρχείο). Το «restorePut» γράφει μόνο ό,τι λείπει (όπως το CONFLICT_IGNORE). [failDone]: τόσες φορές το
/// «salvageDone» απαντά «δεν γράφτηκε».
class _FoodDb {
  final log = <String, Map<String, dynamic>>{};
  final mine = <String, Map<String, dynamic>>{};
  List<Map<String, dynamic>> keptLog = [];
  List<Map<String, dynamic>> keptMine = [];
  bool keptComplete = true;
  int failDone = 0;
  String? done;
  bool? doneComplete;
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
          return jsonEncode(
              {'ok': true, 'found': true, 'entries': keptLog, 'foods': keptMine, 'complete': keptComplete, 'lost': keptComplete ? 0 : 1});
        case 'salvageDone':
          if (failDone > 0) {
            failDone--;
            return '{"ok":false,"kind":"other"}';
          }
          done = '${args['at']} ${args['entries']} ${args['foods']}';
          doneComplete = args['complete'] as bool?;
          return '{"ok":true}';
      }
      return '{"ok":true}';
    });
  }
}

Map<String, dynamic> _food(String id) => {
      'id': id,
      'name': 'Προϊόν $id',
      'cat': 'Τα προϊόντα μου',
      'source': 'Ετικέτα',
      'n': {'kcal': 120, 'protein': 8},
    };

Map<String, dynamic> _entry(String id, DateTime at) => {
      'id': id,
      'day': dateKey(at),
      'meal': 'lunch',
      'food': _food('F-$id'),
      'grams': 150,
      'time': at.millisecondsSinceEpoch,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final real = DateTime.now();
  final now = DateTime(real.year, real.month, real.day, 15);
  final today = dayOf(now);

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
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  // ---------------------------------------------------------------------------------------------------------------
  group('R8-A9-2: το «Εντάξει» της κάρτας «Η βάση χάλασε» δεν σταματά την επαναφορά', () {
    test('η κάρτα κρύβεται, αλλά η επαναφορά του φαγητού ξαναδοκιμάζεται ώσπου να γίνει', () async {
      final a = _Phone(now)
        ..prefs = {'historyVersion': historyRulesVersion}
        ..corrupt = 5678;
      final s = app(a);
      var ready = false;
      final asked = <int>[];
      // Η πρώτη προσπάθεια αποτυγχάνει (π.χ. γεμάτος χώρος για το αντίγραφο του αρχείου).
      s.onDatabaseReset = (at) async {
        asked.add(at);
        return ready ? (entries: 2, foods: 1) : null;
      };
      await s.loadPrefs();
      await s.start();
      await settle(s);
      expect(asked, isNotEmpty);
      expect(s.dbCorruptAt, 5678);
      expect(s.dbRecovered, isNull);
      await s.dismissDatabaseNotice();
      expect(s.dbCorruptAt, isNull);
      expect(a.seenCalls, [5678], reason: 'η κάρτα αυτής της βλάβης έκλεισε· το σημάδι της βλάβης μένει');
      final before = asked.length;
      ready = true;
      await s.refresh();
      await settle(s);
      expect(asked.length, greaterThan(before), reason: 'πριν: το «Εντάξει» έσβηνε το σημάδι και δεν ξαναγινόταν ποτέ');
      expect(s.dbRecovered, (entries: 2, foods: 1));
      expect(s.dbCorruptAt, isNull, reason: 'η κάρτα δεν ξαναβγαίνει');
      s.dispose();
    });

    test('ρυθμίσεις που διαβάστηκαν μετά το «Εντάξει»: το ιστορικό ξαναδιαβάζεται από την αρχή', () async {
      final a = _Phone(now)
        ..prefs = {'historyVersion': historyRulesVersion, 'backfillFrom': dateKey(_add(today, -4000))}
        ..prefsFail = true
        ..corrupt = 5678;
      final s = app(a);
      s.onDatabaseReset = (at) async => (entries: 0, foods: 0);
      await s.start();
      await settle(s);
      expect(s.prefsLoaded, isFalse);
      expect(a.prefs['dbReset'], isNull);
      await s.dismissDatabaseNotice();
      a.prefsFail = false;
      await s.loadPrefs();
      expect(s.prefsLoaded, isTrue);
      await s.refresh();
      await settle(s);
      expect(a.prefs['dbReset'], 5678, reason: 'η νέα (άδεια) βάση ξαναγεμίζει από την αρχή, όχι μόνο 30 μέρες');
      expect(s.dbCorruptAt, isNull);
      s.dispose();
    });

    test('η πλευρά Android: το «Εντάξει» δεν σβήνει πια το σημάδι της βλάβης', () {
      const dir = 'android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma';
      final bridge = File('$dir/SamsungHealthBridge.kt').readAsStringSync();
      final seen = bridge.substring(bridge.indexOf('"dbStatusSeen" -> respondDb(result)'));
      expect(seen.substring(0, seen.indexOf('JSONObject().put("ok", true)')), contains('DayStore.markSeen('));
      expect(bridge, isNot(contains('clearCorrupt')));
      expect(bridge, contains('.put("seen", seen)'));
      expect(File('$dir/DayStore.kt').readAsStringSync(), isNot(contains('marker(context).delete()')));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R8-A9-1 / R8-A9-3: η επαναφορά μετά από βλάβη', () {
    test('το σημάδι «έγινε» δεν γράφτηκε → ξαναγράφεται ΜΟΝΟ αυτό· ό,τι σβήστηκε στο μεταξύ δεν ξαναμπαίνει', () async {
      final db = _FoodDb()..install();
      final d1 = _add(today, -1);
      db.log['E1'] = _entry('E1', DateTime(d1.year, d1.month, d1.day, 13));
      db.log['E2'] = _entry('E2', DateTime(d1.year, d1.month, d1.day, 20));
      db.mine['M1'] = _food('M1');
      final s = FoodStore();
      addTearDown(s.dispose);
      await s.start();
      expect(s.loaded, isTrue);
      // Βλάβη: η Kotlin κράτησε το παλιό αρχείο και άνοιξε άδεια βάση.
      db.keptLog = db.log.values.map((e) => Map<String, dynamic>.from(e)).toList();
      db.keptMine = db.mine.values.map((e) => Map<String, dynamic>.from(e)).toList();
      db.log.clear();
      db.mine.clear();
      db.failDone = 1;
      expect(await s.recoverAfterDbReset(4242), isNull, reason: 'το σημάδι δεν γράφτηκε: δεν έγινε ακόμα');
      expect(db.done, isNull);
      expect(db.log.keys.toSet(), {'E1', 'E2'});
      // Μετά την επαναφορά ο χρήστης σβήνει το E2.
      await s.remove(s.entriesFor(d1).firstWhere((e) => e.id == 'E2'));
      expect(db.log.keys.toSet(), {'E1'});
      db.calls.clear();
      expect(await s.recoverAfterDbReset(4242), (entries: 2, foods: 1));
      expect(db.calls.map((c) => c.method), ['salvageDone'], reason: 'ούτε νέα ανάγνωση ούτε νέα εγγραφή');
      expect(db.log.keys.toSet(), {'E1'}, reason: 'το E2 που σβήστηκε δεν ξαναμπαίνει');
      expect(db.done, '4242 2 1');
      expect(db.doneComplete, isTrue);
      db.calls.clear();
      expect(await s.recoverAfterDbReset(4242), isNull);
      expect(db.calls, isEmpty);
    });

    test('ανάγνωση που δεν διάβασε όλο το αρχείο: το σημάδι το λέει (ξαναδιαβάζεται με νεότερο κανόνα)', () async {
      final db = _FoodDb()
        ..keptComplete = false
        ..install();
      db.keptLog = [_entry('EOLD', DateTime(2025, 3, 2, 13))];
      final s = FoodStore();
      addTearDown(s.dispose);
      await s.start();
      expect(await s.recoverAfterDbReset(99), (entries: 1, foods: 0));
      expect(db.log.keys, ['EOLD']);
      expect(db.doneComplete, isFalse);
    });

    test('Android: ανάγνωση σε κομμάτια και σημείωση διαγραφών (οι κανόνες ελέγχονται στο R8F4Test.kt)', () {
      const dir = 'android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma';
      final store = File('$dir/DayStore.kt').readAsStringSync();
      expect(store, contains(r'WHERE rowid >= $from ORDER BY rowid LIMIT $limit'));
      expect(store, isNot(contains('for (order in listOf("ASC", "DESC"))')));
      expect(store, contains('DbSalvage.read(sqlRows(db, "food_log"), removed.first, log)'));
      expect(store, contains('DbSalvage.read(sqlRows(db, "my_foods"), removed.second, foods)'));
      final food = File('$dir/FoodBridge.kt').readAsStringSync();
      expect(food, contains("DayStore.noteRemoved(activity.applicationContext, 'e', id)"));
      expect(food, contains("DayStore.noteRemoved(activity.applicationContext, 'f', id)"));
      expect(food, contains('DayStore.salvageDone(activity.applicationContext, at, entries, foods, complete)'));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R8-A11-1: κανένα «αποτύπωμα» πραγματικής τιμής στο δημόσιο repo', () {
    test('το check_privacy.py κρατά μόνο τις φράσεις', () {
      final py = File('tools/ci/check_privacy.py').readAsStringSync();
      expect(py, contains('OWNER_PHRASES'));
      expect(py, isNot(contains('OWNER_PRINTS')));
      expect(py, isNot(contains('def _print(')));
      expect(RegExp(r'[0-9a-f]{20}').hasMatch(py), isFalse, reason: 'καμία δεκαεξαδική σταθερά (αποτύπωμα) στο αρχείο');
    });

    test('καμία δοκιμή ή εργαλείο δεν κρατά αποτυπώματα με το δημόσιο «αλάτι» του γύρου 7', () {
      const salt = 'ygeia-forma/R7-A11-1|';
      for (final base in ['test', 'tools']) {
        for (final f in Directory(base).listSync(recursive: true).whereType<File>()) {
          if (!f.path.endsWith('.dart') && !f.path.endsWith('.py')) continue;
          if (f.path.endsWith('r8_f4_test.dart')) continue;
          expect(f.readAsStringSync().contains(salt), isFalse, reason: f.path);
        }
      }
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R8-A11-3 / R8-A3-2: «Αναφορά για έλεγχο»', () {
    // Παρασκευή 13/11/2026, 15:00 (επινοημένα δεδομένα).
    final at = DateTime(2026, 11, 13, 15);
    const me = Profile(birthYear: 1985, birthMonth: 12, sex: 'm', heightCm: 180);

    HealthStore store(List<(DateTime, double)> weights) {
      final s = HealthStore()..data = Dashboard.fromJson({...sampleDashboardJson(at), 'body': bodyJson(weights)});
      s
        ..history = sampleHistory(at, s.data!)
        ..setProfile(me)
        ..setGoals(checkinGoals(since: '2026-10-05'));
      return s;
    }

    test('A11-3: οι ζυγίσεις μόνο των τελευταίων 60 ημερών (όπως λέει η πολιτική)· και το άλμα βάρους μόνο μέσα σε αυτές', () {
      final old1 = DateTime(2026, 4, 27, 7, 30), old2 = DateTime(2026, 8, 5, 7, 30), old3 = DateTime(2026, 8, 7, 7, 30);
      final weights = [(old1, 93.0), (old2, 90.0), (old3, 94.0), ...simWeights(at)];
      final r = diagnosticsFrom(store: store(weights), food: checkinFood(at), now: at);
      final body = (((r['data'] as Map)['samsung'] as Map)['body'] as List).cast<Map>();
      final from = DateTime(2026, 9, 14); // 60 μέρες πριν από τις 13/11
      expect(body, isNotEmpty);
      for (final b in body) {
        expect(DateTime.parse(b['t'] as String).isBefore(from), isFalse, reason: '${b['t']}');
      }
      final checks = {for (final c in r['checks'] as List) (c as Map)['id']: c['ok']};
      expect(checks['weight-jumps'], isTrue, reason: 'το άλμα 5–7/8 είναι πριν από τις 60 μέρες');
      expect(jsonEncode(r), isNot(contains('2026-08-05')));
    });

    test('A3-2: όσπρια και ψάρι της εβδομάδας ΜΑΖΙ με σήμερα, όπως η κάρτα και η σελίδα', () {
      final lentils = foodNamed('Φακές (βρασμένες)');
      final sardine = foodNamed('Σαρδέλα (ψητή, χωρίς λάδι)');
      LogEntry e(String id, DateTime d, Food f, double g) =>
          LogEntry(id: id, day: dateKey(d), meal: Meal.lunch, food: f, grams: g, time: DateTime(d.year, d.month, d.day, 13));
      // Δευτέρα 9/11, Τετάρτη 11/11 και σήμερα (Παρασκευή 13/11): 300 g βρασμένες φακές (= 120 g ξερές ≥ 40)· ψάρι σήμερα.
      final food = FoodStore.preloaded(foods: basicFoods(), now: at, entries: [
        e('l1', DateTime(2026, 11, 9), lentils, 300),
        e('l2', DateTime(2026, 11, 11), lentils, 300),
        e('l3', DateTime(2026, 11, 13), lentils, 300),
        e('f1', DateTime(2026, 11, 13), sardine, 150),
      ]);
      final r = diagnosticsFrom(store: store(simWeights(at)), food: food, now: at);
      final chol = (r['calc'] as Map)['chol'] as Map;
      expect(chol['weekStart'], '2026-11-09');
      expect(chol['legumes'], 3, reason: 'πριν 2: η αναφορά δεν μετρούσε τη σημερινή μέρα');
      expect(chol['fish'], 1);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R8-A11-4: αποσύνδεση Oura όταν η αποθήκευση των κλειδιών δεν απαντά', () {
    String tokens() =>
        OuraTokens(access: 'A0', refresh: 'R0', expiresAt: DateTime(2030, 1, 1).millisecondsSinceEpoch).toJson();

    test('δεν διαβάστηκαν → «δεν ακυρώθηκε» (η οθόνη λέει να ακυρωθεί από την εφαρμογή Oura)', () async {
      final calls = <String>[];
      OuraLink link(MemoryVault v) => OuraLink(
            vault: v,
            send: (m, u, {headers = const {}, form}) async {
              calls.add(m);
              return const OuraResponse(200, '{}');
            },
            clientId: 'CID',
          );
      final unread = MemoryVault()
        ..data[vaultTokens] = tokens()
        ..failLoads = true;
      expect(await link(unread).disconnect(), isFalse);
      expect(calls, isEmpty);
      // Διαβάζονται → ανάκληση στην Oura → «ακυρώθηκε».
      final ok = MemoryVault()..data[vaultTokens] = tokens();
      expect(await link(ok).disconnect(), isTrue);
      expect(calls, hasLength(1));
      expect(ok.data.containsKey(vaultTokens), isFalse);
      // Κανένα token: τίποτα για ακύρωση.
      calls.clear();
      expect(await link(MemoryVault()).disconnect(), isTrue);
      expect(calls, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R8-A11-5: νέα ημερομηνία σε κάθε αλλαγή της πολιτικής απορρήτου', () {
    test('η σελίδα έχει την ημερομηνία της αλλαγής του γύρου 7 και το CI ελέγχει το αποτύπωμα', () {
      final page = File('site/public/privacy/index.html').readAsStringSync();
      final shown = RegExp(r'Τελευταία ενημέρωση: ([^<]*)<').firstMatch(page)!.group(1)!.trim();
      expect(shown, isNot('13 Νοεμβρίου 2026'));
      final stamp = File('tools/ci/privacy_stamp.txt').readAsStringSync().trim();
      final space = stamp.indexOf(' ');
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(stamp.substring(0, space)), isTrue);
      expect(stamp.substring(space + 1), shown);
      final py = File('tools/ci/check_privacy.py').readAsStringSync();
      expect(py, contains('privacy_stamp.txt'));
      expect(py, contains('hashlib.sha256(_body.encode('));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R8-A12-2: τα κατώτατα του CI κοντά στις δοκιμές', () {
    test('Dart, Kotlin κινητού και ρολογιού ≈ 3% κάτω από το #105· το Kotlin μετρά όσες έτρεξαν', () {
      for (final f in ['.github/workflows/check.yml', '.github/workflows/android.yml']) {
        final y = File(f).readAsStringSync();
        final floors = [for (final m in RegExp(r'-lt (\d+) \]').allMatches(y)) int.parse(m.group(1)!)];
        // #105: 1.832 δοκιμές Dart, 85 Kotlin κινητού, 167 ρολογιού.
        for (final (count, name) in [(1832, 'Dart'), (85, 'κινητό'), (167, 'ρολόι')]) {
          expect(floors.any((x) => x >= 0.96 * count && x <= count), isTrue, reason: '$f: $name');
        }
        expect(floors.any((x) => x < 0.9 * 85), isFalse, reason: '$f: κανένα παλιό, χαμηλό κατώτατο');
        expect('skipped="[0-9]+"'.allMatches(y).length, 2, reason: '$f: tests − skipped, κινητό και ρολόι');
        expect(r"grep -rhE '^\s*@Test\b'".allMatches(y).length, 2, reason: f);
      }
    });
  });

  // ---------------------------------------------------------------------------------------------------------------
  group('R8-U4-4 / R8-U4-5: Ρυθμίσεις', () {
    testWidgets('U4-4: ο διακόπτης «Αναφορές σφαλμάτων» έχει όνομα για το TalkBack και όλη η γραμμή πατιέται', (t) async {
      final handle = t.ensureSemantics();
      final saved = <bool>[];
      final r = ErrorReporter(persist: (on) async => saved.add(on));
      await t.pumpWidget(MaterialApp(
          theme: buildTheme(Brightness.light), home: Scaffold(body: ListView(children: [PrivacyGroup(reporter: r)]))));
      expect(t.getSemantics(find.byKey(const ValueKey('privacy-errors'))).label, contains('Αναφορές σφαλμάτων'));
      await t.tap(find.text('Αναφορές σφαλμάτων'));
      await t.pumpAndSettle();
      expect(saved, [false]);
      expect(r.enabled, isFalse);
      expect(find.text(errorsOffText), findsOneWidget);
      handle.dispose();
    });

    test('U4-5: η επαναφορά που σταμάτησε λέει ότι οι αναφορές σφαλμάτων έκλεισαν', () {
      final closed = restoreNotReadText(errorsClosed: true);
      expect(closed, isNot(contains('δεν άλλαξε τίποτα')));
      expect(closed, contains('Οι αναφορές σφαλμάτων έκλεισαν'));
      expect(closed, contains('Δοκίμασε ξανά.'));
      expect(restoreNotReadText(errorsClosed: false),
          'Δεν διαβάστηκε τι υπάρχει ήδη στο κινητό, οπότε δεν άλλαξε τίποτα. Δοκίμασε ξανά.');
      expect(File('lib/pages/settings.dart').readAsStringSync(), contains('_say(restoreNotReadText(errorsClosed: errorsClosed));'));
    });
  });
}
