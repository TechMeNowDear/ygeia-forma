// Round 1 · f8: αντίγραφο ασφαλείας (υπενθύμιση, πλήρες ή μισό), «Αναφορά για έλεγχο», «Διαγραφή όλων», άγνωστες
// διαδρομές, άνοιγμα/κλείσιμο του Fold, κανόνες αντιγράφου Google, πολιτική απορρήτου, CI.
// Κάθε δοκιμή αποτυγχάνει χωρίς την αντίστοιχη διόρθωση. Φανταστικές τιμές (δημόσιο repo).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/backup.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/diagnostics.dart';
import 'package:ygeia_forma/food/food_model.dart' show Nk;
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/goals.dart';
import 'package:ygeia_forma/main.dart';
import 'package:ygeia_forma/pages/backup_reminder_card.dart';
import 'package:ygeia_forma/pages/nutrition.dart' show FoodTodayCard;
import 'package:ygeia_forma/pages/privacy_page.dart';
import 'package:ygeia_forma/pages/settings.dart';
import 'package:ygeia_forma/pages/today.dart';
import 'package:ygeia_forma/plan_file.dart';
import 'package:ygeia_forma/profile.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/training/training_store.dart';
import 'package:ygeia_forma/waist.dart' show waistFromJson;
import 'package:ygeia_forma/widgets.dart';

import 'sample_checkin.dart';
import 'sample_data.dart';
import 'sample_food.dart';

const _samsung = MethodChannel('ygeia/samsung');
const _foodChannel = MethodChannel('ygeia/food');
const _kotlin = 'android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma';

TestDefaultBinaryMessenger get _messenger => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// Η πλευρά Android για τις ρυθμίσεις: το «loadPrefs» δίνει το [prefs] και κάθε εγγραφή πετυχαίνει.
void _mockPrefs(Map<String, dynamic> prefs) {
  _messenger.setMockMethodCallHandler(_samsung, (call) async {
    if (call.method == 'loadPrefs') return jsonEncode(prefs);
    return '{"ok":true}';
  });
  addTearDown(() => _messenger.setMockMethodCallHandler(_samsung, null));
}

/// Το αρχείο που «έγραψε» η τελευταία εξαγωγή στις Λήψεις.
String? _savedBackup;

/// Η πλευρά Android για το φαγητό: άδειο ημερολόγιο, κανένα προϊόν, και η αποθήκευση του αντιγράφου πετυχαίνει.
void _mockFood() {
  _savedBackup = null;
  _messenger.setMockMethodCallHandler(_foodChannel, (call) async {
    switch (call.method) {
      case 'logRange':
        return jsonEncode({'ok': true, 'entries': <Object>[]});
      case 'myFoods':
        return jsonEncode({'ok': true, 'foods': <Object>[]});
      case 'saveBackup':
        final args = call.arguments as Map;
        _savedBackup = args['json'] as String;
        return jsonEncode({'ok': true, 'uri': 'content://ygeia/backup', 'name': args['name']});
    }
    return '{"ok":true}';
  });
  addTearDown(() => _messenger.setMockMethodCallHandler(_foodChannel, null));
}

HealthStore _sample(DateTime at) {
  final s = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(at));
  s.history = sampleHistory(at, s.data!);
  return s;
}

/// Τα jobs ενός workflow ως κείμενα (κάθε job αρχίζει με «  όνομα:» στην αρχή της γραμμής).
Map<String, String> _jobs(String yml) {
  final out = <String, String>{};
  final body = yml.substring(yml.indexOf('\njobs:\n'));
  final found = RegExp(r'^  ([a-z_-]+):\s*$', multiLine: true).allMatches(body).toList();
  for (var i = 0; i < found.length; i++) {
    out[found[i].group(1)!] = body.substring(found[i].start, i + 1 < found.length ? found[i + 1].start : body.length);
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ------------------------------------------------------------------------- S9-3
  group('S9-3: υπενθύμιση αντιγράφου στη «Σήμερα»', () {
    test('κανόνας: ποτέ ή 7 ημερολογιακές μέρες, μόνο αν υπάρχει κάτι να χαθεί· «Αργότερα» = 3 μέρες', () {
      final now = DateTime(2026, 11, 23, 9);
      expect(backupReminderAfterDays, 7);
      expect(backupSnoozeDays, 3);
      // Χωρίς δικά του δεδομένα δεν υπάρχει τι να χαθεί.
      expect(backupReminderDue(last: null, hasData: false, now: now), isFalse);
      // Ποτέ αντίγραφο.
      expect(backupReminderDue(last: null, hasData: true, now: now), isTrue);
      // Ημερολογιακές μέρες, όπως το «Τελευταίο αντίγραφο»: 16/11 22:00 → 22/11 23:00 = 6 μέρες· 23/11 00:05 = 7.
      final last = DateTime(2026, 11, 16, 22);
      expect(backupReminderDue(last: last, hasData: true, now: DateTime(2026, 11, 22, 23)), isFalse);
      expect(backupReminderDue(last: last, hasData: true, now: DateTime(2026, 11, 23, 0, 5)), isTrue);
      // Αντίγραφο «στο μέλλον» (άλλαξε το ρολόι): όχι υπενθύμιση.
      expect(backupReminderDue(last: DateTime(2026, 11, 24, 8), hasData: true, now: now), isFalse);
      // «Αργότερα» στις 23/11: κρυφή ως το πρωί της 26/11.
      final until = backupSnoozeUntil(now);
      expect(until, DateTime(2026, 11, 26));
      expect(backupReminderDue(last: null, hasData: true, now: DateTime(2026, 11, 25, 23, 59), snoozedUntil: until), isFalse);
      expect(backupReminderDue(last: null, hasData: true, now: DateTime(2026, 11, 26), snoozedUntil: until), isTrue);
      // Το ρολόι γύρισε πίσω: ένα «αργότερα» μηνών δεν κρύβει την κάρτα για πάντα.
      expect(backupReminderDue(last: null, hasData: true, now: now, snoozedUntil: DateTime(2027, 3, 1)), isTrue);
    });

    test('κείμενα: πόσο παλιό είναι, τι κινδυνεύει, και να φύγει από το κινητό', () {
      final now = DateTime(2026, 11, 23, 9);
      expect(backupReminderText(null, now),
          'Δεν έχεις βγάλει αντίγραφο ακόμα. Το φαγητό, τα προϊόντα σου, οι προπονήσεις και οι στόχοι υπάρχουν μόνο σε αυτό το κινητό.');
      expect(backupReminderText(DateTime(2026, 11, 14, 8), now), startsWith('Τελευταίο αντίγραφο: πριν 9 μέρες. '));
      expect(backupOffPhoneText, contains('έξω από το κινητό'));
      expect(backupOffPhoneText, contains('Λήψεις'));
    });

    test('το «Αργότερα» σώζεται στις ρυθμίσεις (πρόσθετο κλειδί), όχι στο αντίγραφο', () {
      final until = DateTime(2026, 11, 26);
      final p = Prefs.fromJson(const {})..backupSnooze = until.millisecondsSinceEpoch;
      expect(Prefs.fromJson(jsonDecode(p.toJson()) as Map<String, dynamic>).backupSnooze, until.millisecondsSinceEpoch);
      expect((jsonDecode(Prefs.fromJson(const {}).toJson()) as Map).containsKey('backupSnooze'), isFalse);
      expect(Prefs.fromJson(const {'backupSnooze': 'αύριο'}).backupSnooze, isNull);
      expect(Prefs.fromJson(const {'backupSnooze': double.infinity}).backupSnooze, isNull);
      expect(backupPrefKeys.contains('backupSnooze'), isFalse);
      final s = HealthStore();
      expect(s.backupSnoozedUntil, isNull);
      s.snoozeBackupReminder(until);
      expect(s.backupSnoozedUntil, until);
      // Μια επαναφορά αντιγράφου δεν το σβήνει (είναι του κινητού).
      expect(mergePrefsForRestore(s.prefsJson(), const {'themeMode': 'dark'})['backupSnooze'], until.millisecondsSinceEpoch);
    });

    testWidgets('κάρτα: φαίνεται, «Αργότερα» την κρύβει 3 μέρες, μισό αντίγραφο τη αφήνει, πλήρες τη σβήνει και ανοίγει την αποστολή',
        (t) async {
      final now = DateTime(2026, 11, 23, 9);
      _mockPrefs({'lastExport': DateTime(2026, 11, 14, 8).millisecondsSinceEpoch});
      final store = HealthStore();
      await t.runAsync(() => store.loadPrefs());
      expect(store.prefsLoaded, isTrue);
      final food = sampleFoodStore(now);
      final training = TrainingStore(io: MemoryTrainingIO());
      var exports = 0;
      var complete = false;
      final shared = <String>[];
      Widget slot(DateTime at) => MaterialApp(
            theme: buildTheme(Brightness.light),
            home: Scaffold(
              body: ListenableBuilder(
                listenable: store,
                builder: (context, _) => ListView(children: [
                  BackupReminderSlot(
                    store: store,
                    food: food,
                    training: training,
                    now: at,
                    export: () async {
                      exports++;
                      if (complete) store.markExported(at);
                      return (ok: complete, text: complete ? 'πλήρες αντίγραφο' : 'μισό αντίγραφο', uri: 'content://ygeia/backup');
                    },
                    share: (uri) async {
                      shared.add(uri);
                    },
                  ),
                ]),
              ),
            ),
          );
      await t.pumpWidget(slot(now));
      expect(find.byKey(const ValueKey('today-backup')), findsOneWidget);
      expect(find.text('Αντίγραφο ασφαλείας'), findsOneWidget);
      expect(find.text(backupReminderText(DateTime(2026, 11, 14, 8), now)), findsOneWidget);
      expect(find.text(backupOffPhoneText), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('today-backup-later')));
      await t.pump();
      expect(find.byKey(const ValueKey('today-backup')), findsNothing);
      expect(store.backupSnoozedUntil, DateTime(2026, 11, 26));
      await t.pumpWidget(slot(DateTime(2026, 11, 25, 23, 59)));
      expect(find.byKey(const ValueKey('today-backup')), findsNothing, reason: 'ακόμα μέσα στις 3 μέρες');
      final later = DateTime(2026, 11, 26, 7);
      await t.pumpWidget(slot(later));
      expect(find.byKey(const ValueKey('today-backup')), findsOneWidget, reason: 'το πρωί της τρίτης μέρας ξαναφαίνεται');

      await t.tap(find.byKey(const ValueKey('today-backup-export')));
      await t.pumpAndSettle();
      expect(exports, 1);
      expect(find.text('μισό αντίγραφο'), findsOneWidget, reason: 'το αποτέλεσμα λέγεται');
      expect(shared, isEmpty, reason: 'μισό αντίγραφο δεν ανοίγει μόνο του την αποστολή');
      expect(find.byKey(const ValueKey('today-backup')), findsOneWidget, reason: 'και η κάρτα μένει');

      complete = true;
      await t.tap(find.byKey(const ValueKey('today-backup-export')));
      await t.pumpAndSettle();
      expect(exports, 2);
      expect(shared, ['content://ygeia/backup'], reason: 'πλήρες αντίγραφο: κατευθείαν η αποστολή');
      expect(store.lastExport, later);
      expect(find.byKey(const ValueKey('today-backup')), findsNothing);
    });

    testWidgets('στη «Σήμερα»: κάτω από το φαγητό και πάνω από το «Ενημέρωση…»· χωρίς διαβασμένες ρυθμίσεις καμία κάρτα',
        (t) async {
      final now = DateTime(2026, 10, 24, 16, 30);
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(400, 5000);
      addTearDown(t.view.reset);
      Future<void> pumpToday(HealthStore s) async {
        await t.pumpWidget(MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: TodayPage(
              store: s,
              food: sampleFoodStore(now),
              open: (_, [__]) {},
              openSettings: () {},
              now: now,
              training: TrainingStore(io: MemoryTrainingIO()),
            ),
          ),
        ));
        await t.pumpAndSettle();
      }

      // Πριν διαβαστούν οι ρυθμίσεις δεν ξέρουμε πότε βγήκε το τελευταίο αντίγραφο: καμία κάρτα.
      await pumpToday(_sample(now));
      expect(find.byKey(const ValueKey('today-backup')), findsNothing);
      expect(find.byKey(const ValueKey('today-backup-none')), findsOneWidget);

      _mockPrefs(const {});
      final s = _sample(now);
      await t.runAsync(() => s.loadPrefs());
      expect(s.prefsLoaded, isTrue);
      await pumpToday(s);
      expect(t.takeException(), isNull);
      expect(find.text(backupReminderText(null, now)), findsOneWidget);
      final card = t.getRect(find.byKey(const ValueKey('today-backup')));
      expect(card.top, greaterThan(t.getRect(find.byType(FoodTodayCard)).bottom), reason: 'ποτέ πάνω από τα δεδομένα');
      expect(card.bottom, lessThan(t.getRect(find.byKey(const ValueKey('today-updated'))).top));
    });
  });

  // ------------------------------------------------------------------------- S9-8
  group('S9-8: ένα μισό αντίγραφο δεν λέγεται πλήρες', () {
    late TrainingStore previous;
    setUp(() {
      previous = TrainingStore.main;
      TrainingStore.main = TrainingStore(io: MemoryTrainingIO());
      _mockFood();
    });
    tearDown(() => TrainingStore.main = previous);

    test('ρυθμίσεις που δεν διαβάστηκαν: το λέει, δεν σημειώνεται ως αντίγραφο', () async {
      final s = HealthStore()
        ..planFile = MemoryPlanFile()
        ..debugSetPlan(SourcePlan.samsungOnly);
      expect(s.prefsLoaded, isFalse);
      final r = await exportBackupNow(s, FoodStore.preloaded(foods: const []));
      expect(r.ok, isFalse);
      expect(r.uri, 'content://ygeia/backup', reason: 'το αρχείο γράφτηκε· απλώς δεν είναι πλήρες');
      expect(r.text, contains('Οι ρυθμίσεις (στοιχεία, στόχοι, μέση) δεν μπήκαν: δεν διαβάστηκαν.'));
      expect(r.text.contains('Στείλ’ το και έξω από το κινητό'), isFalse);
      expect(s.lastExport, isNull);
      expect((jsonDecode(_savedBackup!) as Map)['prefs'], isEmpty);
    });

    test('όλα διαβασμένα: πλήρες, σημειώνεται, και λέει να φύγει από το κινητό', () async {
      _mockPrefs(const {'themeMode': 'dark'});
      final s = HealthStore()
        ..planFile = MemoryPlanFile()
        ..debugSetPlan(SourcePlan.samsungOnly);
      await s.loadPrefs();
      expect(s.prefsLoaded, isTrue);
      final r = await exportBackupNow(s, FoodStore.preloaded(foods: const []));
      expect(r.ok, isTrue, reason: r.text);
      expect(r.text, startsWith('Αποθηκεύτηκε στις Λήψεις: ygeia-antigrafo-'));
      expect(r.text, endsWith('. Στείλ’ το και έξω από το κινητό (π.χ. στο Drive ή με email).'));
      expect(s.lastExport, isNotNull);
      expect(((jsonDecode(_savedBackup!) as Map)['prefs'] as Map)['themeMode'], 'dark');
    });

    test('σχέδιο πηγών με Oura που δεν διαβάζεται: «οι πηγές ύπνου δεν μπήκαν», όχι πλήρες', () async {
      _mockPrefs(const {});
      final s = HealthStore()
        ..planFile = MemoryPlanFile()
        ..debugSetPlan(SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 6)));
      await s.loadPrefs();
      final r = await exportBackupNow(s, FoodStore.preloaded(foods: const []));
      expect(r.ok, isFalse);
      expect(r.text, contains('Οι πηγές ύπνου δεν μπήκαν: δεν διαβάστηκαν.'));
      expect(r.text.contains('Οι ρυθμίσεις'), isFalse);
      expect(s.lastExport, isNull);
      expect((jsonDecode(_savedBackup!) as Map).containsKey('sources'), isFalse);
    });

    test('και οι προεπιλογές μετά από χαλασμένο αρχείο μετρούν ως «δεν μπήκαν»', () {
      final src = File('lib/pages/settings.dart').readAsStringSync();
      expect(src, contains('final prefsOut = !store.prefsLoaded || store.prefsFromDefaults;'));
      expect(src, contains('final complete = !trainingOut && hrMissing == 0 && !prefsOut && !sourcesOut;'));
    });
  });

  // ------------------------------------------------------------------------- S9-6
  test('S9-6: η «Αναφορά για έλεγχο» δεν έχει το όνομα της αναφοράς γιατρού', () async {
    final at = DateTime(2026, 12, 14, 8, 20);
    _mockPrefs(const {'reportName': 'Δοκιμή Όνομα', 'themeMode': 'dark'});
    final s = HealthStore()..data = Dashboard.fromJson({...sampleDashboardJson(at), 'body': bodyJson(simWeights(at))});
    s.history = sampleHistory(at, s.data!);
    await s.loadPrefs();
    s
      ..setProfile(const Profile(birthYear: 1986, birthMonth: 1, sex: 'm', heightCm: 180))
      ..setGoals(checkinGoals());
    expect(s.prefsJson()['reportName'], 'Δοκιμή Όνομα', reason: 'το όνομα υπάρχει στις ρυθμίσεις του κινητού');
    final r = diagnosticsFrom(store: s, food: checkinFood(at), now: at);
    final prefs = (r['data'] as Map)['prefs'] as Map;
    expect(prefs.containsKey('reportName'), isFalse);
    expect(prefs['themeMode'], 'dark', reason: 'οι υπόλοιπες ρυθμίσεις μένουν στην αναφορά');
    expect(jsonEncode(r).contains('Δοκιμή Όνομα'), isFalse);
    expect(diagnosticsDeviceOnlyPrefs, contains('reportName'));
  });

  // ------------------------------------------------------------------------- S10-7
  group('S10-7: άγνωστη διαδρομή', () {
    testWidgets('«Η διαγραφή δεν τελείωσε»: καμία κατάρρευση, μένει η οθόνη', (t) async {
      await t.pumpWidget(WipeUnfinishedApp(
        status: WipeStatus(at: DateTime(2026, 11, 10), done: false, seen: false, watchPending: true, oura: 'none'),
      ));
      final nav = t.state<NavigatorState>(find.byType(Navigator));
      nav.pushNamed('/ygeia-widget://open/1/0');
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('Η διαγραφή δεν τελείωσε'), findsOneWidget);
      expect(nav.canPop(), isFalse);
      // U4-6: εδώ δεν υπάρχει «μόλις ξεκινήσεις».
      expect(find.text(wipedRereadText), findsNothing);
    });

    test('κάθε MaterialApp της εφαρμογής έχει onUnknownRoute', () {
      for (final path in ['lib/main.dart', 'lib/pages/privacy_page.dart', 'lib/pages/widget_config_page.dart']) {
        expect(File(path).readAsStringSync(), contains('onUnknownRoute:'), reason: path);
      }
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final src = f.readAsStringSync();
        expect('MaterialApp('.allMatches(src).length, lessThanOrEqualTo('onUnknownRoute:'.allMatches(src).length), reason: f.path);
      }
    });
  });

  // ------------------------------------------------------------------------- S10-4
  testWidgets('S10-4: άνοιγμα και κλείσιμο του Fold: οι σελίδες μετακινούνται, δεν ξαναχτίζονται', (t) async {
    final now = DateTime(2026, 10, 24, 16, 30);
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(400, 900);
    addTearDown(t.view.reset);
    addTearDown(() => FoodStore.shared = null);
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Shell(store: _sample(now), food: sampleFoodStore(now), initialIndex: Cat.today, now: now),
    ));
    await t.pumpAndSettle();
    final stack = t.state(find.byType(LazyIndexedStack));
    final page = t.element(find.byType(TodayPage));

    // Ανοιχτό Fold (φαρδιά διάταξη, πλαϊνή μπάρα).
    t.view.physicalSize = const Size(860, 900);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(identical(t.state(find.byType(LazyIndexedStack)), stack), isTrue, reason: 'ανοιχτό: η ίδια κατάσταση');
    expect(identical(t.element(find.byType(TodayPage)), page), isTrue);

    // Κλειστό ξανά (κάτω μπάρα).
    t.view.physicalSize = const Size(400, 900);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(identical(t.state(find.byType(LazyIndexedStack)), stack), isTrue, reason: 'κλειστό ξανά: η ίδια κατάσταση');
    expect(identical(t.element(find.byType(TodayPage)), page), isTrue);
  });

  // ------------------------------------------------------------------------- U4-6
  group('U4-6: μετά τη «Διαγραφή όλων» τίποτα δεν διαβάζεται ώσπου να φύγει ο χρήστης από το «Όλα διαγράφηκαν»', () {
    testWidgets('οι αποθήκες ξεκινούν με το «Ξεκίνα από την αρχή», μία φορά· η οθόνη λέει ότι θα ξαναδιαβάσει', (t) async {
      addTearDown(() => FoodStore.shared = null);
      var started = 0;
      await t.pumpWidget(YgeiaFormaApp(
        store: HealthStore(),
        food: FoodStore.preloaded(foods: const []),
        wiped: WipeStatus(at: DateTime(2026, 11, 15, 9), done: true, seen: false, watchPending: false, oura: 'none'),
        onLeaveWiped: () => started++,
      ));
      await t.pump();
      expect(find.text('Όλα διαγράφηκαν'), findsOneWidget);
      expect(find.text(wipedRereadText), findsOneWidget);
      expect(wipedRereadText, contains('ξαναδιαβάζει'));
      expect(started, 0, reason: 'όσο φαίνεται η οθόνη τίποτα δεν ξεκινά');
      await t.tap(find.byKey(const ValueKey('wiped-start')));
      await t.pumpAndSettle();
      expect(started, 1);
      expect(find.text('Όλα διαγράφηκαν'), findsNothing);
    });

    test('main: οι αναγνώσεις μόνο μέσα από το startStores· Kotlin: η ανανέωση στο παρασκήνιο περιμένει το «wipeSeen»', () {
      final main = File('lib/main.dart').readAsStringSync();
      final body = main.substring(main.indexOf('Future<void> main() async {'), main.indexOf('class YgeiaFormaApp'));
      expect(body, contains('onLeaveWiped: showWiped ? startStores : null'));
      expect(body, contains('if (!showWiped) startStores();'));
      expect(body, contains('\n    store.start();'));
      expect(body.contains('\n  store.start();'), isFalse, reason: 'καμία ανάγνωση έξω από το startStores');
      expect(body.contains('\n  food.start();'), isFalse);
      final activity = File('$_kotlin/MainActivity.kt').readAsStringSync();
      expect(activity, contains('if (!DataWipe.unfinished(this) && !DataWipe.awaitsStart(this)) RefreshWorker.schedule(this)'));
      final wipe = File('$_kotlin/DataWipe.kt').readAsStringSync();
      final seen = wipe.substring(wipe.indexOf('"wipeSeen" -> {'), wipe.indexOf('"wipeRetry"'));
      expect(seen, contains('RefreshWorker.schedule(activity)'));
    });
  });

  // ------------------------------------------------------------------------- U4-7, U4-10
  group('U4-7, U4-10: το φύλλο «Διαγραφή όλων»', () {
    testWidgets('«Δεν σβήνονται» ως λίστα, με το αντίγραφο της Google εξηγημένο· και με γράμματα 2× χωρίς σφάλμα', (t) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(400, 3200);
      addTearDown(t.view.reset);
      Future<void> sheet(double scale) async {
        await t.pumpWidget(MaterialApp(
          theme: buildTheme(Brightness.light),
          builder: (context, child) =>
              MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
          home: Scaffold(body: DeleteAllSheet(wipe: () async => 'x', export: () async => (ok: true, text: 'εντάξει'))),
        ));
        await t.pumpAndSettle();
      }

      await sheet(1);
      expect(find.text('Δεν σβήνονται:'), findsOneWidget);
      for (final line in wipeKeeps) {
        expect(find.text(line), findsOneWidget, reason: line);
      }
      expect(find.text(wipeWatchNoteText), findsOneWidget);
      for (final line in wipeDeletes) {
        expect(find.text(line), findsOneWidget, reason: line);
      }
      final google = wipeKeeps.singleWhere((l) => l.contains('αντίγραφο της Google'));
      expect(google, contains('μπορεί να φέρει πίσω'));
      expect(google, contains('Αντίγραφα ασφαλείας'));
      await sheet(2);
      expect(t.takeException(), isNull);
      expect(find.text('Δεν σβήνονται:'), findsOneWidget);
    });

    test('η κουκκίδα στο μέσο της πρώτης γραμμής σε κάθε μέγεθος γραμμάτων', () {
      // Ύψος γραμμής 1,4 × μέγεθος· μέσο της γραμμής μείον μισή κουκκίδα (3,5).
      expect(wipeBulletTop(15.5), closeTo(7.35, 1e-9));
      expect(wipeBulletTop(31), closeTo(18.2, 1e-9), reason: 'γράμματα 2×: πριν έμενε στα 7');
      expect(wipeBulletTop(14.5), closeTo(6.65, 1e-9));
      expect(wipeBulletTop(2), 0);
    });

    testWidgets('«Επαναφορά από αντίγραφο» στο κέντρο (δύο γραμμές με μεγάλα γράμματα)', (t) async {
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: WipedPage(
          status: WipeStatus(at: DateTime(2026, 11, 10), done: true, seen: false, watchPending: false, oura: 'none'),
          onStart: () {},
          onRestore: () {},
        ),
      ));
      final label = t.widget<Text>(find.descendant(of: find.byKey(const ValueKey('wiped-restore')), matching: find.byType(Text)));
      expect(label.textAlign, TextAlign.center);
    });
  });

  // ------------------------------------------------------------------------- U4-8
  test('U4-8: οι Ρυθμίσεις και η πολιτική λένε ότι η εφαρμογή διαβάζει και στο παρασκήνιο', () {
    expect(settingsFooterText.contains('μόνο όταν την ανοίγεις'), isFalse);
    expect(settingsFooterText, contains('κάθε 3 ώρες'));
    expect(settingsFooterText, contains('όχι από τα μεσάνυχτα ως τις 6 το πρωί'));
    // Όπως το κάνει ο κώδικας: κάθε 3 ώρες, ποτέ πριν από τις 06:00.
    final worker = File('$_kotlin/RefreshWorker.kt').readAsStringSync();
    expect(worker, contains('PeriodicWorkRequestBuilder<RefreshWorker>(3, TimeUnit.HOURS)'));
    expect(worker, contains('if (hour < 6) return Result.success()'));
    final policy = File('site/public/privacy/index.html').readAsStringSync();
    expect(policy, contains('περίπου κάθε 3 ώρες στο παρασκήνιο'));
    expect(policy, contains('about every 3 hours in the background'));
    expect(File('tools/ci/check_privacy.py').readAsStringSync(), contains('PeriodicWorkRequestBuilder<RefreshWorker>'));
  });

  // ------------------------------------------------------------------------- S9-10 = S10-3
  test('S9-10 / S10-3: η επιλογή «Αναφορές σφαλμάτων» ταξιδεύει με το αντίγραφο Google και τη μεταφορά· κανένα άλλο shared_prefs', () {
    final rules = File('tools/android/xml/data_extraction_rules.xml').readAsStringSync();
    final cloud = RegExp(r'<cloud-backup[^>]*>([\s\S]*?)</cloud-backup>').firstMatch(rules)![1]!;
    final transfer = RegExp(r'<device-transfer>([\s\S]*?)</device-transfer>').firstMatch(rules)![1]!;
    final old = File('tools/android/xml/backup_rules.xml').readAsStringSync().replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
    for (final block in [cloud, transfer, old]) {
      final prefs = RegExp(r'<include domain="sharedpref" path="([^"]+)"').allMatches(block).map((m) => m[1]).toList();
      expect(prefs, ['errors.xml']);
    }
    expect(old, contains('<include domain="sharedpref" path="errors.xml" requireFlags="clientSideEncryption" />'));
    // Το ίδιο αρχείο που γράφει ο διακόπτης και που κρατά η «Διαγραφή όλων».
    final queue = File('$_kotlin/ErrorQueue.kt').readAsStringSync();
    expect(queue, contains('private const val PREFS = "errors"'));
    expect(File('$_kotlin/DataWipe.kt').readAsStringSync(), contains('"errors.xml"'));
    expect(File('site/public/privacy/index.html').readAsStringSync(), contains('της επιλογής σου για τις αναφορές σφαλμάτων'));
  });

  // ------------------------------------------------------------------------- S10-1
  test('S10-1: τα extras της Flutter από άλλη εφαρμογή σβήνονται πριν τα δει η Flutter, και στις δύο οθόνες', () {
    final main = File('$_kotlin/MainActivity.kt').readAsStringSync();
    final config = File('$_kotlin/WidgetConfigActivity.kt').readAsStringSync();
    const drop = 'for (k in FlutterLaunchExtras.NAMES) intent?.removeExtra(k)';
    for (final src in [main, config]) {
      expect(src, contains(drop));
      expect(src.indexOf(drop), lessThan(src.indexOf('super.onCreate(savedInstanceState)')), reason: 'πριν από τη Flutter');
    }
    expect(main, contains('override fun getInitialRoute(): String = "/"'));
    expect(config, contains('override fun getInitialRoute(): String = "/widget"'));
    for (final name in ['"route"', '"cached_engine_id"', '"cached_engine_group_id"', '"dart_entrypoint"', '"background_mode"']) {
      expect(main, contains(name));
    }
    // Και στο emulator: άνοιγμα με αυτά τα extras πρέπει να δείχνει την κανονική εφαρμογή.
    final smoke = File('tools/perf/smoke.sh').readAsStringSync();
    expect(smoke, contains('--es route /widget --es cached_engine_id x'));
  });

  // ------------------------------------------------------------------------- S12-10 (γ)
  test('S12-10: αντίγραφο στη μορφή παλιότερης έκδοσης (στόχοι χωρίς τα νέα πεδία, μία μέρα ζυγίσματος, παλμοί μέσα στην '
      'προπόνηση) επανέρχεται τιμή προς τιμή', () async {
    // Συνθετικό αρχείο, γραμμένο με το χέρι (όχι με το buildBackup της τωρινής έκδοσης).
    final start = DateTime(2026, 11, 2, 18).millisecondsSinceEpoch;
    final product = {
      'id': 'old-food',
      'name': 'Φακές δοκιμής',
      'cat': '',
      'source': 'Ετικέτα',
      'n': {'kcal': 116, 'protein': 9, 'carbs': 20, 'fat': 0.4},
    };
    final old = jsonEncode({
      'app': 'ygeia-forma',
      'version': 1,
      'created': '2026-11-08T21:15:00.000',
      'foodLog': [
        {
          'id': 'old-1',
          'day': '2026-11-08',
          'meal': 'lunch',
          'food': product,
          'grams': 180,
          'time': DateTime(2026, 11, 8, 14).millisecondsSinceEpoch,
        },
      ],
      'myFoods': [product],
      'prefs': {
        'themeMode': 'dark',
        'historyVersion': 3,
        'me': {'by': 1986, 'sex': 'm', 'h': 180, 'wd': 3},
        'goals': {
          'v': 1,
          'aim': 'lose',
          'rate': 0.005,
          'pal': 1.5,
          'doc': true,
          'since': '2026-11-02',
          'kg': 90,
          'age': 40,
          'h': 180,
          'm': true,
          'kcal': 2250,
        },
        'waist': [
          {'d': '2026-11-06', 'v': [98.5, 98.0]},
        ],
      },
      'training': {
        'v': 1,
        'hrLimit': 137,
        'programs': <Object>[],
        'active': null,
        'sessions': [
          {
            'id': 'old-s1',
            'w': '',
            'name': 'Παλιά προπόνηση',
            'prog': '',
            'start': start,
            'end': start + 35 * 60000,
            'items': <Object>[],
            'hrAvg': 101,
            'hrMax': 118,
            'cmin': 35,
            'hr': [
              [0, 92],
              [60, 101],
              [120, 118],
            ],
          },
        ],
        'del': <Object>[],
      },
    });
    final b = parseBackup(old);
    expect(b.skipped, 0);
    expect(b.created, DateTime(2026, 11, 8, 21, 15));
    expect(b.entries.single.id, 'old-1');
    expect(b.entries.single.day, '2026-11-08');
    expect(b.entries.single.total(Nk.kcal), closeTo(208.8, 1e-9), reason: '116 kcal στα 100 g × 180 g');
    expect(b.myFoods.single.name, 'Φακές δοκιμής');
    expect(b.prefs.containsKey('historyVersion'), isFalse, reason: 'η τεχνική πρόοδος δεν έρχεται από αντίγραφο');

    // Σε κινητό χωρίς ρυθμίσεις (νέο, ή μετά από «Διαγραφή όλων») μπαίνουν όλα.
    final merged = mergePrefsForRestore(const {}, b.prefs);
    expect(merged['themeMode'], 'dark');
    final g = Goals.fromJson(merged['goals'])!;
    expect(g.kcal, 2250);
    expect((g.kcalSet, g.since, g.kg, g.age, g.heightCm, g.male, g.doctor), (2250, '2026-11-02', 90.0, 40, 180.0, true, true));
    expect((g.kcalAdapt, g.tdeeEst), (null, null));
    expect(g.log, isEmpty);
    final me = Profile.fromJson(merged['me']);
    expect((me.birthYear, me.sex, me.heightCm, me.waistDay), (1986, 'm', 180.0, 3));
    expect(me.weighDays, {3}, reason: 'η μία μέρα ζυγίσματος της παλιάς μορφής («wd»)');
    final waist = waistFromJson(merged['waist']).single;
    expect(waist.day, '2026-11-06');
    expect(waist.values, [98.5, 98.0]);

    final t = TrainingStore(io: MemoryTrainingIO(), clock: () => DateTime(2026, 11, 13, 10));
    await t.load();
    expect(t.mergeBackup(b.training!), 1);
    expect(t.mergeProblem, isNull);
    expect(await t.flush(), isTrue);
    final session = t.sessions.single;
    expect((session.id, session.start.millisecondsSinceEpoch), ('old-s1', start));
    await t.ensureHr(session);
    expect(session.hr, [
      [0, 92],
      [60, 101],
      [120, 118],
    ]);
    expect(t.hrLimit, isNull, reason: 'το όριο παλμών του γιατρού δεν μπαίνει από αντίγραφο (το λέει το παράθυρο της επαναφοράς)');
  });

  // ------------------------------------------------------------------------- CI: S10-2, S10-6, S10-8, S10-9, S12-09, S12-10, S12-17, S9-4
  group('CI', () {
    final yml = File('.github/workflows/android.yml').readAsStringSync();
    final j = _jobs(yml);

    test('S10-9 / S12-09: η υπογραφή περιμένει και τα στιγμιότυπα· ο μεσάζων Oura και το targetSdk ελέγχονται και στο main', () {
      expect(j['sign'], contains('needs: [build, smoke, shots]'));
      expect(j['publish'], contains('needs: sign'));
      expect(j['build'], contains('node test/node/oura_token_test.mjs site/netlify/functions/oura-token.mjs'));
      expect(j['build'], contains('tools/ci/check_privacy.py'));
      expect(j['build'], contains("targetSdkVersion:'37'"));
    });

    test('S12-17: κατώτατο πλήθος δοκιμών (Dart, Kotlin κινητού, Kotlin μαζί με το ρολόι) και στα δύο workflows', () {
      final check = File('.github/workflows/check.yml').readAsStringSync();
      for (final w in [j['build']!, check]) {
        expect(w, contains(r'if [ "${n:-0}" -lt 950 ]; then'));
        expect(w, contains(r'if [ "${n:-0}" -lt 40 ]; then'));
        expect(w, contains(r'if [ "${n:-0}" -lt 120 ]; then'));
        expect(w, contains("grep -aoE '[0-9]+ tests passed' tests.log"));
      }
    });

    test('S10-6 / S12-10: στο main η δοκιμή αναβάθμισης δεν παραλείπεται σιωπηλά', () {
      final smoke = j['smoke']!;
      expect(smoke, contains(r'bash tools/ci/build_old_apk.sh old.apk new.apk || rc=$?'));
      expect(smoke.contains('if bash tools/ci/build_old_apk.sh old.apk new.apk; then'), isFalse);
      expect(smoke, contains(r'elif [ "$GITHUB_REF" = "refs/heads/main" ] && [ "$SKIP_UPGRADE" != "true" ]; then'));
      expect(smoke, contains("contains(github.event.head_commit.message, '[skip-upgrade]')"));
      final script = File('tools/ci/build_old_apk.sh').readAsStringSync();
      expect(script, contains('exit 3'));
      expect(script, contains('exit 4'));
      expect(script, contains("remote_refs 'refs/tags/build-*'"), reason: 'S10-8: χωρίς «latest», η νεότερη build-N');
    });

    test('S10-6: το build_old_apk.sh ξεχωρίζει «δεν υπάρχει προηγούμενη έκδοση» (3) από «δεν απάντησε το GitHub» (4)', () {
      final dir = Directory.systemTemp.createTempSync('oldapk');
      addTearDown(() => dir.deleteSync(recursive: true));
      void tool(String name, String body) {
        File('${dir.path}/$name').writeAsStringSync('#!/bin/sh\n$body\n');
        expect(Process.runSync('chmod', ['+x', '${dir.path}/$name']).exitCode, 0);
      }

      int run(int lsRemote) {
        // Ψεύτικο git: το «ls-remote» απαντά με τον κωδικό που του δίνουμε (2 = καμία τέτοια ετικέτα, 128 = δίκτυο).
        tool('git', 'case "\$1" in ls-remote) exit $lsRemote ;; esac\nexit 0');
        tool('sleep', 'exit 0');
        final r = Process.runSync('bash', ['tools/ci/build_old_apk.sh', '${dir.path}/old.apk', '${dir.path}/new.apk'],
            environment: {'PATH': '${dir.path}:${Platform.environment['PATH']}', 'RUNNER_TEMP': dir.path});
        return r.exitCode;
      }

      expect(run(2), 3);
      expect(run(128), 4);
    });

    test('S10-8: η δημοσίευση ξανατρέχει μετά από μισή αποτυχία· μικρότερος αριθμός από τη «latest» είναι σφάλμα', () {
      final publish = j['publish']!;
      const view = r'gh release view "build-$N" > /dev/null 2>&1 || gh release create "build-$N"';
      expect(publish, contains(view));
      expect(RegExp(r'gh release create "build-\$N"').allMatches(publish).length, 1);
      expect(publish.indexOf(view), lessThan(publish.indexOf('gh release delete latest')));
      final older = publish.substring(publish.indexOf(r'if [ -n "$cur" ] && [ "$cur" -gt "$N" ]; then'), publish.indexOf('sums='));
      expect(older, contains('::error title=Δημοσίευση::'));
      expect(older, contains('exit 1'));
      expect(older.contains('exit 0'), isFalse);
      expect(yml, contains('name: Χτίσιμο Android'));
      expect(yml, contains('ΜΗΝ μετονομάσεις'));
    });

    test('S10-2 / S9-4: το σχόλιο δεν υπόσχεται environment που δεν υπάρχει· το κλειδί μόνο στο «sign»· οδηγίες στο README', () {
      expect(yml.contains('ο άλλος κλάδος ΔΕΝ υπογράφει'), isFalse);
      expect(yml, contains('ΣΗΜΕΡΑ υπογράφει και ο άλλος κλάδος'));
      for (final e in j.entries.where((e) => e.key != 'sign')) {
        expect(e.value.contains('YGEIA_KEYSTORE'), isFalse, reason: e.key);
      }
      for (final f in Directory('.github/workflows').listSync().whereType<File>().where((f) => f.path.endsWith('.yml'))) {
        if (f.path.endsWith('android.yml')) continue;
        final w = f.readAsStringSync();
        expect(w.contains('secrets.'), isFalse, reason: f.path);
        expect(w.contains('YGEIA_KEYSTORE'), isFalse, reason: f.path);
      }
      // S9-4 (β): καμία μνήμη Actions (actions/cache) δεν κρατά κλειδί υπογραφής, σε κανένα workflow.
      var caches = 0;
      for (final f in Directory('.github/workflows').listSync().whereType<File>().where((f) => f.path.endsWith('.yml'))) {
        for (final step in f.readAsStringSync().split('\n      - ').where((s) => s.contains('actions/cache@'))) {
          caches++;
          for (final bad in ['signing', 'keystore', '.jks']) {
            expect(step.toLowerCase().contains(bad), isFalse, reason: '${f.path}: $bad');
          }
        }
      }
      expect(caches, greaterThan(0), reason: 'ο έλεγχος βρήκε τα βήματα actions/cache');
      // S9-4 (γ): το job που σβήνει την παλιά μνήμη «ygeia-signing-v1» μένει.
      expect(j.keys, contains('old-cache'));
      expect(File('tools/ci/sign_apks.sh').readAsStringSync(), contains('exit 1'));
      final readme = File('README.md').readAsStringSync();
      expect(readme, contains('### Κλειδί υπογραφής'));
      expect(readme, contains('Ένα αντίγραφο εκτός GitHub είναι υποχρεωτικό'));
      expect(readme, contains('Environment «release»: δεν υπάρχει ακόμα'));
    });

    test('S12-10: η δοκιμή αναβάθμισης σπέρνει ρυθμίσεις με στόχους, ημερολόγιο φαγητού και ιστορικό, και τα συγκρίνει τιμή προς τιμή', () {
      final up = File('tools/perf/upgrade.sh').readAsStringSync();
      for (final part in [
        '"goals": {"v": 1, "aim": "lose"',
        '"waist": [',
        '"zone": {',
        '"me": {',
        'INSERT OR REPLACE INTO food_log(id, day, json, updated)',
        'INSERT OR REPLACE INTO days(date, json, updated)',
        'check_more()',
        'ui_find_scroll "στόχος 2.250" 3',
      ]) {
        expect(up, contains(part), reason: part);
      }
      // Μετά την αναβάθμιση: σύγκριση των αρχείων, και αποτυχία αν διαφέρουν.
      final after = up.substring(up.indexOf('# 5. Η νέα ανοίγει και διαβάζει.'));
      expect(after, contains('if check_more; then'));
      expect(after, contains('fail "μετά την αναβάθμιση άλλαξαν ή χάθηκαν δεδομένα του δείγματος'));
    });
  });
}
