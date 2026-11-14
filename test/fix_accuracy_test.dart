// Κλάδος fix-accuracy (έλεγχος 9/11): ακρίβεια, ιατρικά/στατιστικά κείμενα, πλατφόρμα, ΓΚΠΔ.
// Κάθε δοκιμή αποτυγχάνει χωρίς την αντίστοιχη διόρθωση.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/error_report.dart';
import 'package:ygeia_forma/heart_day.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/oxygen_note.dart';
import 'package:ygeia_forma/reference.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/training/progress.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/set_hr.dart';
import 'package:ygeia_forma/training/walk_stats.dart';
import 'package:ygeia_forma/pages/training/hr_widgets.dart';
import 'package:ygeia_forma/training/hr_file.dart';
import 'package:ygeia_forma/training/training_store.dart';
import 'package:ygeia_forma/trends.dart';
import 'package:ygeia_forma/home_widgets/widget_snapshot.dart';
import 'package:ygeia_forma/home_widgets/widget_style.dart' show WKind;

import 'sample_data.dart';
import 'sample_food.dart';
import 'package:ygeia_forma/main.dart' show unknownRoute;
import 'package:ygeia_forma/pages/privacy_page.dart';
import 'package:ygeia_forma/theme.dart';

Widget _app(Widget home) => MaterialApp(theme: buildTheme(Brightness.light), home: home);

void main() {
  // ------------------------------------------------------------ E3-05 / V-A-23: αναφορές σφαλμάτων με διακόπτη
  group('Αναφορές σφαλμάτων: διακόπτης', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('errq'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('κλειστός από την πλευρά Android: τίποτα δεν στέλνεται, και όσα περίμεναν (και της Kotlin) σβήνονται', () async {
      // Ένα σφάλμα που έγραψε η Kotlin πριν ανοίξει η Flutter.
      File('${dir.path}/00000000000001_abc.json').writeAsStringSync('{"event_id":"abc"}');
      final sent = <String>[];
      final r = ErrorReporter(post: (b) async {
        sent.add(b);
        return 200;
      });
      // Σφάλμα στα πρώτα κλάσματα, πριν μάθουμε την επιλογή: δεν πρέπει να φύγει ποτέ.
      await r.report(StateError('νωρίς'), StackTrace.current);
      await r.configure(dir: dir, release: 'x', device: const {}, enabled: false);
      expect(r.enabled, isFalse);
      expect(await r.pending(), 0);
      await r.report(StateError('μετά'), StackTrace.current);
      await r.flush();
      expect(sent, isEmpty);
      expect(await r.pending(), 0);
    });

    test('ανοιχτός (όπως λέει η πολιτική): στέλνει κανονικά', () async {
      final sent = <String>[];
      final r = ErrorReporter(post: (b) async {
        sent.add(b);
        return 200;
      });
      await r.configure(dir: dir, release: 'x', device: const {});
      await r.report(StateError('κάτι'), StackTrace.current);
      expect(sent, hasLength(1));
    });

    test('κλείσιμο από τις Ρυθμίσεις: γράφεται πρώτα, σβήνει την ουρά· αποτυχία εγγραφής = μένει ανοιχτός', () async {
      final saved = <bool>[];
      var online = false;
      final r = ErrorReporter(
        persist: (on) async => saved.add(on),
        post: (b) async {
          if (!online) throw const SocketException('χωρίς ίντερνετ');
          return 200;
        },
      );
      await r.configure(dir: dir, release: 'x', device: const {});
      await r.report(StateError('περιμένει'), StackTrace.current);
      expect(await r.pending(), 1);
      expect(await r.setEnabled(false), isTrue);
      expect(saved, [false]);
      expect(r.enabled, isFalse);
      expect(await r.pending(), 0);
      online = true;
      await r.report(StateError('μετά το κλείσιμο'), StackTrace.current);
      expect(await r.pending(), 0);

      final broken = ErrorReporter(persist: (_) async => throw StateError('δίσκος'));
      expect(await broken.setEnabled(false), isFalse);
      expect(broken.enabled, isTrue);
    });

    testWidgets('ο διακόπτης στην ενότητα «Απόρρητο»', (tester) async {
      final saved = <bool>[];
      final r = ErrorReporter(persist: (on) async => saved.add(on));
      await tester.pumpWidget(_app(Scaffold(body: ListView(children: [PrivacyGroup(reporter: r)]))));
      expect(find.text('Αναφορές σφαλμάτων'), findsOneWidget);
      expect(find.text(errorsOnText), findsOneWidget);
      expect(find.text('Πολιτική απορρήτου'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('privacy-errors')));
      await tester.pumpAndSettle();
      expect(saved, [false]);
      expect(r.enabled, isFalse);
      expect(find.text(errorsOffText), findsOneWidget);
    });

    test('η πλευρά Android κρατά την επιλογή και δεν γράφει στην ουρά όταν είναι κλειστή', () {
      final kt = File('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/ErrorQueue.kt').readAsStringSync();
      expect(kt, contains('"enabled" to enabled'));
      expect(kt, contains('"setEnabled" ->'));
      expect(RegExp(r'private fun write\([^)]*\) \{\s*try \{\s*if \(!enabled\) return').hasMatch(kt), isTrue);
      final dart = File('lib/error_report.dart').readAsStringSync();
      expect(dart, contains("enabled: info['enabled'] != false"));
    });

    test('N5: ArgumentError / RangeError στέλνουν μόνο τον τύπο (η τιμή μένει στο κινητό)', () async {
      final sent = <String>[];
      final r = ErrorReporter(post: (b) async {
        sent.add(b);
        return 200;
      });
      await r.configure(dir: dir, release: 'x', device: const {});
      await r.report(ArgumentError.value(82.4, 'βάρος'), StackTrace.current);
      await r.report(RangeError.range(98765, 0, 3), StackTrace.current);
      expect(sent, hasLength(2));
      for (final b in sent) {
        expect(b, isNot(contains('82.4')));
        expect(b, isNot(contains('98765')));
      }
      expect(sent.first, contains('ArgumentError'));
    });
  });

  // ------------------------------------------------------------ E3-05: «Διαγραφή όλων των δεδομένων»
  group('Διαγραφή όλων', () {
    Future<void> tap(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
    }

    bool enabled(WidgetTester tester, String key) => tester.widget<ButtonStyleButton>(find.byKey(ValueKey(key))).onPressed != null;

    testWidgets('δύο επιβεβαιώσεις και αντίγραφο ή ρητά «χωρίς»· λέει τι μένει', (tester) async {
      var calls = 0, exported = 0;
      await tester.pumpWidget(_app(Scaffold(
        body: DeleteAllSheet(
          wipe: () async {
            calls++;
            return 'x';
          },
          export: () async {
            exported++;
            return (ok: true, text: 'Αποθηκεύτηκε στις Λήψεις: a.json');
          },
        ),
      )));
      // Round 1 (f8 · U4-7): τι ΔΕΝ σβήνεται είναι πια λίστα, μία γραμμή το καθένα, και η σημείωση για το ρολόι από κάτω.
      for (final line in wipeKeeps) {
        expect(find.text(line), findsOneWidget);
      }
      expect(find.text(wipeWatchNoteText), findsOneWidget);
      final keeps = [...wipeKeeps, wipeWatchNoteText].join(' ');
      for (final t in ['Samsung Health', 'Λήψεις', 'αντίγραφο της Google', 'ρολόι', 'άδειες', 'αναφορές σφαλμάτων']) {
        expect(keeps, contains(t));
      }
      await tap(tester, 'wipe-understood');
      expect(enabled(tester, 'wipe-confirm'), isFalse, reason: 'ούτε αντίγραφο ούτε «Χωρίς αντίγραφο»');
      await tap(tester, 'wipe-confirm');
      expect(calls, 0);
      await tap(tester, 'wipe-export');
      expect(exported, 1);
      expect(find.text('Αποθηκεύτηκε στις Λήψεις: a.json'), findsOneWidget, reason: 'το αποτέλεσμα μέσα στο φύλλο');
      expect(enabled(tester, 'wipe-confirm'), isTrue);
      await tap(tester, 'wipe-confirm');
      expect(calls, 1);
    });

    testWidgets('M2: η εξαγωγή περιμένεται· αποτυχία φαίνεται στο φύλλο και η διαγραφή μένει κλειστή ως «Χωρίς αντίγραφο»',
        (tester) async {
      final done = Completer<BackupResult>();
      await tester.pumpWidget(_app(Scaffold(
        body: DeleteAllSheet(understood: true, wipe: () async => 'x', export: () => done.future),
      )));
      await tester.ensureVisible(find.byKey(const ValueKey('wipe-export')));
      await tester.tap(find.byKey(const ValueKey('wipe-export')));
      await tester.pump();
      expect(find.text('Αποθηκεύεται…'), findsOneWidget);
      expect(enabled(tester, 'wipe-confirm'), isFalse, reason: 'όσο γράφεται το αντίγραφο');
      expect(enabled(tester, 'wipe-cancel'), isFalse);
      done.complete((ok: false, text: 'Δεν αποθηκεύτηκε το αντίγραφο: γεμάτος χώρος'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wipe-export-result')), findsOneWidget);
      expect(find.text('Δεν αποθηκεύτηκε το αντίγραφο: γεμάτος χώρος'), findsOneWidget);
      expect(enabled(tester, 'wipe-confirm'), isFalse);
      await tap(tester, 'wipe-no-backup');
      expect(find.text(wipeNoBackupText), findsOneWidget);
      expect(enabled(tester, 'wipe-confirm'), isTrue);
    });

    testWidgets('μισό αντίγραφο (προπονήσεις έξω) δεν ανοίγει μόνο του τη διαγραφή', (tester) async {
      await tester.pumpWidget(_app(Scaffold(
        body: DeleteAllSheet(
          understood: true,
          wipe: () async => 'x',
          export: () async => (ok: false, text: 'Αποθηκεύτηκε… Οι προπονήσεις δεν μπήκαν'),
        ),
      )));
      await tap(tester, 'wipe-export');
      expect(enabled(tester, 'wipe-confirm'), isFalse);
      // Round 1 (f8 · S9-8): πλήρες μόνο αν μπήκαν ΚΑΙ οι ρυθμίσεις και οι πηγές ύπνου.
      final settings = File('lib/pages/settings.dart').readAsStringSync();
      expect(settings, contains('final complete = !trainingOut && hrMissing == 0 && !prefsOut && !sourcesOut;'));
      expect(settings, contains('ok: complete,'));
    });

    testWidgets('δεν ξεκίνησε: το φύλλο λέει τι έγινε (Oura) και τι όχι', (tester) async {
      await tester.pumpWidget(_app(Scaffold(
        body: DeleteAllSheet(understood: true, noBackup: true, wipe: () async => wipeNotStartedText(ouraClosed: true), export: () async => (ok: true, text: '')),
      )));
      await tap(tester, 'wipe-confirm');
      expect(find.byKey(const ValueKey('wipe-failed')), findsOneWidget);
      expect(find.text(wipeNotStartedText(ouraClosed: true)), findsOneWidget);
      expect(wipeNotStartedText(ouraClosed: true), contains('Oura'));
      expect(wipeNotStartedText(ouraClosed: false), isNot(contains('Oura')));
    });

    testWidgets('S3: όσο σβήνει, το φύλλο δεν κλείνει (πίσω/έξω)· «Άκυρο» πριν = τίποτα', (tester) async {
      var calls = 0;
      final hold = Completer<String>();
      await tester.pumpWidget(_app(Scaffold(
        body: ListView(children: [
          DeleteAllRow(
            store: null,
            wipe: () {
              calls++;
              return hold.future;
            },
          ),
        ]),
      )));
      expect(find.text('Από αυτό το κινητό και το ρολόι'), findsOneWidget);
      await tap(tester, 'privacy-delete');
      expect(find.text('Διαγραφή όλων των δεδομένων;'), findsOneWidget);
      await tap(tester, 'wipe-understood');
      await tap(tester, 'wipe-cancel');
      expect(calls, 0);
      expect(find.text('Διαγραφή όλων των δεδομένων;'), findsNothing);
      await tap(tester, 'privacy-delete');
      await tap(tester, 'wipe-understood');
      await tester.ensureVisible(find.byKey(const ValueKey('wipe-confirm')));
      await tester.tap(find.byKey(const ValueKey('wipe-confirm')));
      await tester.pump();
      expect(calls, 1);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Διαγραφή όλων των δεδομένων;'), findsOneWidget, reason: 'το «πίσω» δεν το κλείνει στη μέση');
      hold.complete('δεν έγινε');
      await tester.pumpAndSettle();
      expect(find.text('δεν έγινε'), findsOneWidget);
    });

    testWidgets('«Όλα διαγράφηκαν»: το ρολόι «περιμένει» ώσπου να επιβεβαιώσει· Oura χωρίς ανάκληση λέγεται', (tester) async {
      var answer = 'waiting';
      var started = 0;
      await tester.pumpWidget(_app(WipedPage(
        status: WipeStatus(at: DateTime(2026, 11, 10), done: true, seen: false, watchPending: true, oura: 'failed'),
        onStart: () => started++,
        onRestore: () {},
        watch: () async => answer,
      )));
      await tester.pump();
      expect(find.text('Όλα διαγράφηκαν'), findsOneWidget);
      expect(find.text(wipeWatchWaitingText), findsOneWidget);
      expect(find.text(wipeOuraNotRevokedText), findsOneWidget);
      answer = 'acked';
      await tester.pump(const Duration(seconds: 16));
      await tester.pump();
      expect(find.text(wipeWatchDoneText), findsOneWidget);
      await tap(tester, 'wiped-start');
      expect(started, 1);
    });

    testWidgets('δεν τελείωσε: «Συνέχεια διαγραφής», όχι «Όλα διαγράφηκαν»', (tester) async {
      var retried = 0;
      await tester.pumpWidget(_app(WipedPage(
        status: WipeStatus(at: DateTime(2026, 11, 10), done: false, seen: false, watchPending: true, oura: 'none'),
        onStart: () {},
        onRestore: () {},
        watch: () async => 'waiting',
        retry: () async => retried++,
      )));
      expect(find.text('Όλα διαγράφηκαν'), findsNothing);
      expect(find.byKey(const ValueKey('wiped-start')), findsNothing);
      await tap(tester, 'wiped-retry');
      expect(retried, 1);
    });

    test('N2: με διαγραφή που δεν τελείωσε, τίποτα δεν ξεκινά (ούτε ρολόι ούτε αναγνώσεις)', () {
      expect(startsApp(null), isTrue);
      expect(startsApp(WipeStatus(at: DateTime(2026, 11, 10), done: true, seen: false, watchPending: true, oura: 'none')), isTrue);
      expect(startsApp(WipeStatus(at: DateTime(2026, 11, 10), done: false, seen: false, watchPending: true, oura: 'none')), isFalse);
      final main = File('lib/main.dart').readAsStringSync();
      final body = main.substring(main.indexOf('Future<void> main() async {'));
      expect(body.indexOf('await readWipeStatus()'), lessThan(body.indexOf('HealthStore()')));
      expect(body.indexOf('runApp(WipeUnfinishedApp('), lessThan(body.indexOf('HealthStore()')));
      expect(body.indexOf('return;\n  }\n  final store = HealthStore();'), greaterThan(0));
      final kt = File('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/MainActivity.kt').readAsStringSync();
      // Round 1 (f8 · U4-6): ούτε όσο φαίνεται το «Όλα διαγράφηκαν».
      expect(kt, contains('if (!DataWipe.unfinished(this) && !DataWipe.awaitsStart(this)) RefreshWorker.schedule(this)'));
      // N3: το κινητό σβήνει ό,τι παλιό «/ygeia/…» έμεινε (π.χ. πρόγραμμα, όριο) όσο περιμένει το ρολόι.
      expect(File('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/DataWipe.kt').readAsStringSync(),
          contains('DataRules.writtenBeforeWipe(t, at)'));
    });

    testWidgets('N4: στις Ρυθμίσεις φαίνεται ότι το ρολόι δεν απάντησε· μετά από 2 μέρες λέει τι να κάνεις', (tester) async {
      final at = DateTime(2026, 11, 10, 9);
      var now = at.add(const Duration(hours: 1));
      addTearDown(() => wipeState.value = null);
      wipeState.value = WipeStatus(at: at, done: true, seen: true, watchPending: true, oura: 'none');
      await tester.pumpWidget(_app(Scaffold(body: ListView(children: [DeleteAllRow(store: null, clock: () => now)]))));
      expect(find.textContaining(wipeWatchPendingText), findsOneWidget);
      now = at.add(const Duration(days: 3));
      wipeState.value = WipeStatus(at: at, done: true, seen: true, watchPending: true, oura: 'none');
      await tester.pump();
      expect(find.textContaining(wipeWatchSilentText), findsOneWidget);
      wipeState.value = WipeStatus(at: at, done: true, seen: true, watchPending: false, oura: 'none');
      await tester.pump();
      expect(find.textContaining('Ρολόι:'), findsNothing);
      expect(find.text('Από αυτό το κινητό και το ρολόι'), findsOneWidget);
    });

    test('κατάσταση από την Kotlin', () {
      expect(WipeStatus.fromMap(null), isNull);
      expect(WipeStatus.fromMap({'at': 0}), isNull);
      final s = WipeStatus.fromMap({'at': 1762800000000, 'stage': 'done', 'seen': true, 'pending': true, 'oura': 'revoked'})!;
      expect(s.show, isFalse);
      expect(s.watchPending, isTrue);
      expect(WipeStatus.fromMap({'at': 1762800000000, 'stage': 'deleting', 'seen': true})!.show, isTrue);
    });

    test('η πλευρά Android: σβήνει μόνη της (όχι «Διαγραφή δεδομένων» του συστήματος), σημάδι πρώτα, τελειώνει πριν τη Flutter', () {
      final kt = File('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/DataWipe.kt').readAsStringSync();
      expect(kt, isNot(contains('clearApplicationUserData()')));
      final code = kt.substring(kt.indexOf('"wipe" -> scope.launch'));
      expect(code.indexOf('begin(activity, at, oura)'), lessThan(code.indexOf('sendWipe(activity, at, deleteOld = true)')));
      expect(code.indexOf('sendWipe(activity, at, deleteOld = true)'), lessThan(code.indexOf('wipeLocal(activity)')));
      expect(code.indexOf('HomeWidgets.wipe(activity)'), lessThan(code.indexOf('wipeLocal(activity)')));
      expect(kt, contains('KeyStore.getInstance("AndroidKeyStore")'));
      expect(kt, contains('"\$MARKER.xml"'));
      final main = File('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/MainActivity.kt').readAsStringSync();
      expect(main, contains('"ygeia/privacy"'));
      expect(main.indexOf('DataWipe.finishIfNeeded(this)'), lessThan(main.indexOf('super.onCreate(savedInstanceState)')));
      // M1: παλιά αποτελέσματα του ρολογιού δεν μπαίνουν ποτέ (δοκιμή Kotlin AccuracyRulesTest).
      final wear = File('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/WearBridge.kt').readAsStringSync();
      expect(wear, contains('DataRules.droppedByWipe('));
      final settings = File('lib/pages/settings.dart').readAsStringSync();
      expect(settings, contains('const PrivacyGroup()'));
      expect(settings, contains('DeleteAllRow(store: widget.store, export: hasFood ? _exportForWipe : null)'));
      // Το ρολόι: δοκιμή Kotlin WipeRuleTest.
      final link = File('android/wear/src/main/kotlin/gr/ygeiaforma/wear/Link.kt').readAsStringSync();
      expect(link, contains('path == Paths.WIPE'));
      expect(File('lib/main.dart').readAsStringSync(), contains('WipedPage('));
    });

    test('S4: η ανάκληση της Oura λέει αν πέτυχε', () {
      final api = File('lib/oura/oura_api.dart').readAsStringSync();
      expect(api, contains('Future<bool> disconnect('));
      expect(api, contains('return r.status >= 200 && r.status < 300;'));
      final page = File('lib/pages/privacy_page.dart').readAsStringSync();
      expect(page, contains("oura = revoked ? 'revoked' : 'failed';"));
    });

    test('S5: η πολιτική λέει πού είναι η διαγραφή και ότι η «Διαγραφή δεδομένων» του Android ΔΕΝ σβήνει το ρολόι', () {
      final html = File('site/public/privacy/index.html').readAsStringSync();
      expect(html, contains('Ρυθμίσεις › Τα δεδομένα μου › «Διαγραφή όλων των δεδομένων»'));
      expect(html, isNot(contains('Το ίδιο κάνει το Ρυθμίσεις Android')));
      expect(html, contains('σβήνει μόνο το κινητό'));
    });
  });

  // ------------------------------------------------------------ E3-06 / V-B-02: μόνο οι άδειες Samsung που διαβάζονται
  test('άδειες Samsung = ακριβώς όσα διαβάζει το DashboardReader (όχι πίεση, άπνοια, ρυθμός, γλυκόζη…)', () {
    final bridge = File('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/SamsungHealthBridge.kt').readAsStringSync();
    final lists = RegExp(r'val (?:readTypes|aggregateTypes)[^=]*= listOf\((.*?)\n\s*\)', dotAll: true).allMatches(bridge).map((m) => m.group(1)!).join();
    final asked = RegExp(r'DataTypes\.(\w+)').allMatches(lists).map((m) => m.group(1)!).toSet();
    final reader = File('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/DashboardReader.kt').readAsStringSync();
    final used = RegExp(r'has\(DataTypes\.(\w+)\)').allMatches(reader).map((m) => m.group(1)!).toSet();
    expect(asked, used);
    for (final t in ['BLOOD_PRESSURE', 'BODY_TEMPERATURE', 'BLOOD_GLUCOSE', 'WATER_INTAKE', 'NUTRITION', 'SLEEP_APNEA', 'IRREGULAR_HEART_RHYTHM_NOTIFICATION']) {
      expect(asked, isNot(contains(t)));
    }
    // Η πολιτική δεν λέει πια ότι ζητούνται.
    final policy = File('site/public/privacy/index.html').readAsStringSync();
    expect(policy, isNot(contains('γλυκόζη αίματος')));
  });

  // ------------------------------------------------------------ E3-08 / D2-06: deep links
  testWidgets('άγνωστη διαδρομή (π.χ. URI από άλλη εφαρμογή): καμία κατάρρευση, μένει η αρχική', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: nav, home: const Text('αρχική'), onUnknownRoute: unknownRoute));
    nav.currentState!.pushNamed('/ygeia-widget://open/1/0');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('αρχική'), findsOneWidget);
    expect(nav.currentState!.canPop(), isFalse);
    expect(File('lib/main.dart').readAsStringSync(), contains('onUnknownRoute: unknownRoute'));
    expect(File('lib/pages/widget_config_page.dart').readAsStringSync(), contains('onUnknownRoute:'));
  });

  test('manifest: deep linking της Flutter κλειστό σε MainActivity και WidgetConfigActivity', () {
    final dir = Directory.systemTemp.createTempSync('manifest');
    final m = File('${dir.path}/AndroidManifest.xml')
      ..writeAsStringSync('<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
          '    <application\n        android:label="ygeia_forma">\n'
          '        <activity\n            android:name=".MainActivity"\n            android:exported="true">\n'
          '        </activity>\n    </application>\n</manifest>\n');
    for (var i = 0; i < 2; i++) {
      final r = Process.runSync('python3', ['tools/android/patch_manifest.py', m.path]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    }
    final s = m.readAsStringSync();
    expect(RegExp('flutter_deeplinking_enabled" android:value="false"').allMatches(s).length, 2);
    final main = s.substring(s.indexOf('.MainActivity'), s.indexOf('</activity>', s.indexOf('.MainActivity')));
    expect(main, contains('flutter_deeplinking_enabled'));
    dir.deleteSync(recursive: true);
  });

  // ------------------------------------------------------------ E3-23 / E3-22
  test('targetSdk 37 ρητά (και στο ρολόι)· το σχόλιο της υπογραφής λέει την αλήθεια', () {
    final g = File('android/ygeia/app-extra.gradle.kts').readAsStringSync();
    expect(g, contains('targetSdk = 37'));
    expect(g, contains('compileSdk = 37'));
    expect(g, isNot(contains('προσωρινή μνήμη')));
    final wear = File('android/wear/build.gradle.kts').readAsStringSync();
    expect(wear, contains('targetSdk = 37'));
    expect(wear, contains('compileSdk = 37'));
  });

  // ------------------------------------------------------------ V-B-11 / 03-M2α / 08-N-03 / 03-Χ3: σταθερό βάδισμα
  group('παλμοί περπατήματος από το 5′', () {
    Session w({required List<List<int>> hr, List<List<int>> pz = const [], int? avg}) => Session(
          id: 'w1',
          workout: 'walk',
          name: 'Περπάτημα',
          programId: '',
          start: DateTime(2026, 11, 1, 18),
          end: DateTime(2026, 11, 1, 18, 31),
          cardioMinutes: 30,
          cardioSec: 1800,
          meters: 2300,
          gps: true,
          hrAvg: avg,
          hr: hr,
          pauses: pz,
          source: 'watch',
        );

    test('τα πρώτα 5′ (ζέσταμα) και οι παύσεις δεν μετράνε· όχι ο μέσος του ρολογιού', () {
      // Ζέσταμα 90 τα πρώτα 5′, μετά 110· μια παύση 600–660″ με 80.
      final hr = [
        for (var t = 0; t <= 1800; t += 5) [t, t < 300 ? 90 : (t >= 600 && t <= 660 ? 80 : 110)],
      ];
      final s = w(hr: hr, pz: [
        [600, 660],
      ], avg: 104);
      expect(walkHr(s), 110);
      expect(s.toJson()['hrs'], 110);
    });

    test('το 5′ είναι ενεργός χρόνος: παύση πριν από το 5′ το μεταθέτει', () {
      // Παύση 100–220″: το 5ο λεπτό ενεργού χρόνου είναι στα 420″.
      final hr = [for (var t = 0; t <= 1800; t += 5) [t, t < 420 ? 90 : 110]];
      expect(Session.steadyFrom(hr, [
        [100, 220],
      ]), 110);
      expect(Session.steadyFrom(hr, const []), isNot(110));
    });

    test('λίγες τιμές μετά το 5′: τίποτα (ούτε εφεδρικός μέσος με παύσεις)', () {
      expect(walkHr(w(hr: [for (var t = 0; t < 330; t += 5) [t, 100]], avg: 100)), isNull);
    });

    test('μένει όταν οι παλμοί φύγουν από τη μνήμη (αρχείο παλμών): «hrs» στο training.json', () {
      final s = Session.fromJson({...w(hr: [for (var t = 0; t <= 1800; t += 5) [t, t < 300 ? 90 : 112]]).toJson(), 'hr': null, 'hrf': 361});
      expect(s.hrLoaded, isFalse);
      expect(walkHr(s), 112);
    });

    test('S6: παλιά περπατήματα (παλμοί στο αρχείο, χωρίς «hrs») παίρνουν την τιμή μία φορά στο άνοιγμα', () async {
      final hr = [for (var t = 0; t <= 1800; t += 5) [t, t < 300 ? 90 : 112]];
      final j = {...w(hr: hr).toJson(), 'hrf': hr.length}
        ..remove('hr')
        ..remove('hrs');
      final io = MemoryTrainingIO()
        ..json = jsonEncode({'v': 2, 'sessions': [j]})
        ..hrFiles['w1'] = encodeHr(hr);
      final t = TrainingStore(io: io, clock: () => DateTime(2026, 11, 2));
      await t.load();
      await t.flush();
      final s = t.sessions.single;
      expect(s.hrLoaded, isFalse, reason: 'οι παλμοί δεν μένουν στη μνήμη');
      expect(walkHr(s), 112);
      expect(io.json, contains('"hrs":112'));
      expect(io.json, contains('"hrsDone":1'));
      // Δεύτερο άνοιγμα: καμία ανάγνωση αρχείων παλμών ξανά.
      final t2 = TrainingStore(io: io..hrFiles.clear(), clock: () => DateTime(2026, 11, 2));
      await t2.load();
      await t2.flush();
      expect(walkHr(t2.sessions.single), 112);
    });

    testWidgets('S8: η σύνοψη του περπατήματος δείχνει την τιμή της Προόδου («από το 5′»)', (tester) async {
      final hr = [for (var t = 0; t <= 1800; t += 5) [t, t < 300 ? 90 : 112]];
      await tester.pumpWidget(_app(Scaffold(body: SingleChildScrollView(child: HrCard(session: w(hr: hr, avg: 104))))));
      expect(find.byKey(const ValueKey('hr-steady')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('hr-steady')), matching: find.text('112')), findsOneWidget);
      expect(find.text('από το 5ο λεπτό'), findsOneWidget);
    });

    test('Πρόοδος: 3 μήνες από προεπιλογή· κάρτα και ⓘ το λένε', () {
      final page = File('lib/pages/training/progress_page.dart').readAsStringSync();
      expect(page, contains('TrendPeriod _period = TrendPeriod.quarter;'));
      expect(page, contains('Η ζέστη και οι ανηφόρες ανεβάζουν τους παλμούς'));
      expect(page, contains('άλλος ρυθμός, δεν συγκρίνεται'));
      expect(File('lib/pages/training/training_page.dart').readAsStringSync(), contains('walkProgress(t.sessions, _now, TrendPeriod.quarter)'));
    });
  });

  // ------------------------------------------------------------ 03-Χ1 / 03-Χ4: «♥ διάλειμμα»
  test('«♥ διάλειμμα» = μέσος των τελευταίων 10″, όχι το χαμηλότερο (μία βουτιά στη μέση δεν μετρά)', () {
    final start = DateTime(2026, 11, 1, 18);
    final hr = [
      for (var t = 0; t <= 400; t++) [t, t >= 150 && t < 165 ? 80 : 100],
    ];
    final s = Session(
      id: 's',
      workout: 'A',
      name: 'Α',
      programId: 'p',
      start: start,
      hr: hr,
      items: [
        ExLog(ex: 'db_press', sets: 2, lo: 8, hi: 12, rir: 2, rest: 90, log: [
          SetLog(load: 10, reps: 8, done: true, at: start.millisecondsSinceEpoch + 100 * 1000),
          SetLog(load: 10, reps: 8, done: true, at: start.millisecondsSinceEpoch + 300 * 1000),
        ]),
      ],
    );
    expect(sessionSetHr(s)[0].sets[0]!.rest, 100);
    // [από, έως): 30″ = 30 τιμές.
    expect(meanIn([for (var t = 0; t <= 30; t++) [t, t == 30 ? 1000 : 100]], 0, 30), 100);
  });

  // ------------------------------------------------------------ V-B-17 / RT-17: αλλαγή ώρας
  test('15 ημερολογιακές μέρες πάνω από την αλλαγή ώρας του Μαρτίου = 15 (ελάφρυνση 10%)', () {
    final src = File('lib/training/progression.dart').readAsStringSync();
    expect(src, contains('final gap = daysBetween(lastDay, today);'));
  });

  // ------------------------------------------------------------ 08-N-05: Energy Score ουδέτερο
  test('Energy Score/ετοιμότητα: ουδέτερο χρώμα', () {
    expect(metricDef(K.energy)!.better, 0);
  });

  // ------------------------------------------------------------ RT-15 / V-A-29: πρώτη ζύγιση της μέρας
  test('δύο ζυγίσεις την ίδια μέρα: μετρά η πρώτη (πρωινή)', () {
    final rows = bodyRows([
      BodyMeasurement(time: DateTime(2026, 11, 1, 7, 30), weight: 82.0, fatPct: 24.0),
      BodyMeasurement(time: DateTime(2026, 11, 1, 21, 0), weight: 83.4, fatPct: 25.1),
    ]);
    expect(rows['2026-11-01']![K.weight], 82.0);
    expect(rows['2026-11-01']![K.fatPct], 24.0);
  });

  // ------------------------------------------------------------ DP-07 / V-A-15
  test('οι προπονήσεις της εφαρμογής εξαιρούνται από τους παλμούς της μέρας', () {
    final day = DateTime(2026, 10, 24);
    int ms(DateTime t) => t.millisecondsSinceEpoch;
    DateTime at(int h, int m) => DateTime(day.year, day.month, day.day, h, m);
    final heart = <List<num>>[
      for (var t = at(9, 0); t.isBefore(at(12, 0)); t = t.add(const Duration(minutes: 4))) [ms(t), ms(t.add(const Duration(minutes: 4))), 70, 67, 73],
      for (var t = at(18, 0); t.isBefore(at(19, 0)); t = t.add(const Duration(minutes: 4))) [ms(t), ms(t.add(const Duration(minutes: 4))), 120, 117, 123],
    ];
    final steps = <List<num>>[for (var t = at(0, 0); t.isBefore(at(23, 0)); t = t.add(const Duration(minutes: 1))) [ms(t), 0]];
    final d = Dashboard.fromJson({'ok': true, 'readAt': ms(at(20, 0)), 'granted': 10, 'total': 10, 'heart': heart, 'stepsMin': steps});
    addTearDown(() => appExerciseRanges = () => const []);
    final before = d.heartForDay(day)!;
    appExerciseRanges = () => [(at(18, 0), at(19, 0))];
    final after = d.heartForDay(day)!;
    expect(after.excludedExerciseMinutes, greaterThan(before.excludedExerciseMinutes));
    expect(after.excludedExerciseMinutes, closeTo(60, 0.01));
    expect(File('lib/main.dart').readAsStringSync(), contains('appExerciseRanges = () => ['));
  });

  test('M3: DP-07 ισχύει και μέσα στο isolate (parseDashboard / parseRange): οι συνόψεις του ιστορικού χωρίς την προπόνηση',
      () async {
    final day = DateTime(2026, 10, 24);
    int ms(DateTime t) => t.millisecondsSinceEpoch;
    DateTime at(int h, int m) => DateTime(day.year, day.month, day.day, h, m);
    final raw = jsonEncode({
      'ok': true,
      'readAt': ms(at(20, 0)),
      'granted': 10,
      'total': 10,
      // Round 1 (S3-7): ο ύπνος «διαβάστηκε» (άδεια λίστα)· χωρίς το κλειδί δεν βγαίνουν παλμοί μέρας.
      'sleep': <Object>[],
      'heart': [
        for (var t = at(8, 0); t.isBefore(at(16, 0)); t = t.add(const Duration(minutes: 4))) [ms(t), ms(t.add(const Duration(minutes: 4))), 70, 67, 73],
        for (var t = at(18, 0); t.isBefore(at(19, 0)); t = t.add(const Duration(minutes: 4))) [ms(t), ms(t.add(const Duration(minutes: 4))), 130, 127, 133],
      ],
      'stepsMin': [for (var t = at(0, 0); t.isBefore(at(23, 0)); t = t.add(const Duration(minutes: 1))) [ms(t), 0]],
    });
    addTearDown(() => appExerciseRanges = () => const []);
    // Χωρίς προπόνηση: ο μέσος της μέρας ανεβαίνει από την ώρα με 120 (έλεγχος ότι η δοκιμή «βλέπει» τη διαφορά).
    final plain = await parseDashboard(raw, plan: SourcePlan.samsungOnly);
    expect(plain.rows!['2026-10-24']![K.dayHr]!, greaterThan(75));
    // Η προπόνηση της εφαρμογής 18:00–19:00, όπως την ορίζει η main() στο κύριο isolate.
    appExerciseRanges = () => [(at(18, 0), at(19, 0))];
    final p = await parseDashboard(raw, plan: SourcePlan.samsungOnly);
    expect(p.rows!['2026-10-24']![K.dayHr]!, closeTo(70, 1));
    final r = await parseRange(raw, day, day, plan: SourcePlan.samsungOnly);
    expect(r.rows['2026-10-24']![K.dayHr]!, closeTo(70, 1));
  });

  // ------------------------------------------------------------ RT-12 / RT-18
  test('χωρίς GPS: «≈» και «από βήματα»· χωρίς τίποτα: «—», όχι 0,00', () {
    Session c({bool? gps, double? m, int? steps}) => Session(
        id: 'c', workout: 'walk', name: 'Π', programId: '', start: DateTime(2026, 11, 1), cardioMinutes: 30, gps: gps, meters: m, steps: steps);
    expect(kmValue(c(gps: true, m: 2310)), '2,31');
    expect(kmValue(c(gps: false, m: 2310, steps: 3000)), '≈ 2,31');
    expect(kmValue(c(gps: false, m: 0, steps: 0)), isNull);
    expect(distanceFromSteps(c(gps: false, m: 2310)), isTrue);
    // Δοκιμή στις συσκευές 14/11: μέσα στο σπίτι, GPS ανοιχτό χωρίς σήμα, 812 βήματα, 0 m: «—», όχι «0,00».
    expect(kmValue(c(gps: true, m: 0, steps: 812)), isNull);
    expect(kmValue(c(gps: true, m: 6, steps: 812)), isNull);
    expect(kmValue(c(gps: false, m: 0, steps: 812)), isNull);
    expect(kmValue(c(gps: true, m: 10)), '0,01');
  });

  // ------------------------------------------------------------ V-B-13 / UX3-05 / V-D-05 / V-D-30: οξυγόνο
  test('οξυγόνο: μία απάντηση και ίδιες ετικέτες παντού· τα κενά της V-B', () {
    expect(oxygenAboutShort, contains(oxygenNoNoteText));
    expect(oxygenAboutText, contains(oxygenRangeText));
    expect(oxygenRangeText, contains('70–100%'));
    expect(oxygenSourceText, 'Μέσος όρος από το Oura, χαμηλότερη τιμή από το ρολόι.');
    expect([for (final r in sourceRows) r.title], containsAll([oxygenAvgLabel, oxygenMinLabel]));
    final oura = File('lib/pages/oura_pages.dart').readAsStringSync();
    expect(oura, isNot(contains("όχι βήματα, όχι οξυγόνο")));
    expect(oura, isNot(contains("'Οξυγόνο δαχτυλιδιού', 'Όχι · από το ρολόι'")));
    expect(File('lib/pages/oxygen_widgets.dart').readAsStringSync(), isNot(contains('developer.ouraring.com')));
    expect(metricInfos[K.ringSpo2]!.accuracy, contains('70–100%'));
    expect(metricInfos[K.ringSpo2]!.accuracy, contains('Sjoding'));
    expect(File('lib/pages/report_page.dart').readAsStringSync(), contains(r'80%. $oxygenRangeText'));
  });

  // ------------------------------------------------------------ V-B-15 / 04-M5 / 04-L1–L8 / V-B-07 / 03-Χ2: κείμενα
  test('κείμενα: όχι «υγιείς» στις αναπνοές, εύρος από 7 νύχτες, ρεζέρβα, βάρος, λίπος, βήματα', () {
    expect(breathRange.text, isNot(contains('υγιείς')));
    expect(metricInfos[K.breath]!.compare, contains('χρήστες Fitbit'));
    final snap = File('lib/home_widgets/widget_snapshot.dart').readAsStringSync();
    expect(snap, contains(r"'${countText(sleepWeek.$2, 'νύχτα', 'νύχτες')} ${sr.placeText(sleepWeek.$1)}'"));
    expect(metricInfos[K.weight]!.accuracy, contains('0,5–1 kg'));
    expect(metricInfos[K.fatPct]!.accuracy, contains('DXA'));
    expect(metricInfos[K.steps]!.accuracy, contains('στη μέση'));
    expect(metricInfos[K.sleepMin]!.accuracy, contains('η συσκευή'));
    expect(metricInfos[K.energy]!.down, isNot(contains('ήπια μέρα')));
    expect(metricInfos[K.ringSpo2]!.down, contains('85%'));
    expect(File('lib/training/progression.dart').readAsStringSync(), isNot(contains('δεν ανεβαίνει απότομα')));
    expect(File('lib/pages/unusual_card.dart').readAsStringSync(), contains('1 στις 20 νύχτες'));
    final ex = File('assets/exercises/exercises.json').readAsStringSync();
    expect(ex, isNot(contains('Σε ίδια κούραση')));
    expect(ex, isNot(contains('ως κάτω και αργά')));
  });

  test('DATA-13: στάδιο που περνά το όριο δύο επικαλυπτόμενων κομματιών κόβεται, δεν χάνεται', () {
    DateTime t(int h, int m) => DateTime(2026, 11, 1, h, m);
    final a = SleepRecord(t(0, 0), t(3, 0), 180, null, [Stage('deep', t(0, 0), t(3, 0))]);
    // Επικάλυψη 30′ (λιγότερο από το μισό του μικρότερου): μένει το κομμάτι μετά το 03:00.
    final b = SleepRecord(t(2, 30), t(6, 0), 210, null, [Stage('light', t(2, 30), t(4, 0)), Stage('rem', t(4, 0), t(6, 0))]);
    final out = dedupeSleep([a, b]);
    expect(out, hasLength(2));
    final st = out[1].stages;
    expect(st.first.name, 'light');
    expect(st.first.start, t(3, 0));
    expect(st.first.end, t(4, 0));
    expect(st.length, 2);
  });

  test('E3-21: η άδεια της Inter μπαίνει στο APK και στη σελίδα «Άδειες»· E3-20: αντιγραφή ως ευαίσθητο', () {
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/fonts/Inter-OFL.txt'));
    expect(File('lib/main.dart').readAsStringSync(), contains('registerLicenses();'));
    expect(File('lib/pages/settings.dart').readAsStringSync(), contains('openLicenses(context)'));
    for (final f in ['lib/ti_ftanei.dart', 'lib/pages/training/training_page.dart', 'lib/pages/my_foods.dart']) {
      final src = File(f).readAsStringSync();
      expect(src, contains('copySensitive('), reason: f);
      expect(src, isNot(contains('Clipboard.setData')), reason: f);
    }
    expect(File('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/DataWipe.kt').readAsStringSync(), contains('EXTRA_IS_SENSITIVE'));
  });

  test('D2-05: widget «Κίνηση» με τη μέρα της ανάγνωσης· στο κινητό καθαρίζει το «χθες» άλλης μέρας', () {
    final read = DateTime(2026, 11, 6, 23, 40);
    final store = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(read));
    store.history = sampleHistory(read, store.data!);
    final snap = buildWidgetSnapshot(store, sampleFoodStore(read), DateTime(2026, 11, 7, 0, 5));
    expect(((snap['kinds'] as Map)[WKind.move] as Map)['day'], '2026-11-06');
    final kt = File('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/HomeWidgets.kt').readAsStringSync();
    // Round 7 (f5 · R7-A10-2): η ανανέωση στο παρασκήνιο είναι πια στο WidgetText.moveFromDashboard: σε άλλη μέρα ξεκινά
    // από κενό (άρα ούτε τα χθεσινά «Παλμοί χθες» της προηγούμενης μέρας)· δοκιμή συμπεριφοράς: R7F5Test.kt.
    final text = File('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/WidgetText.kt').readAsStringSync();
    expect(text, contains('old.optString("day", "") == today.toString()) JSONObject(old.toString()) else JSONObject()'));
    expect(kt, contains('WidgetText.moveFromDashboard('));
    expect(kt, contains('HomeWidgets.ensureMidnight(context)'));
    expect(kt, contains('Intent.ACTION_TIMEZONE_CHANGED'));
  });
}
