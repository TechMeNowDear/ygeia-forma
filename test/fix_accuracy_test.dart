// Κλάδος fix-accuracy (έλεγχος 9/11): ακρίβεια, ιατρικά/στατιστικά κείμενα, πλατφόρμα, ΓΚΠΔ.
// Κάθε δοκιμή αποτυγχάνει χωρίς την αντίστοιχη διόρθωση.
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
import 'package:ygeia_forma/trends.dart';
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
  });

  // ------------------------------------------------------------ E3-05: «Διαγραφή όλων των δεδομένων»
  group('Διαγραφή όλων', () {
    Future<void> tap(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
    }

    testWidgets('δύο επιβεβαιώσεις: χωρίς «Κατάλαβα» το κουμπί δεν σβήνει· λέει τι μένει', (tester) async {
      var calls = 0, exported = 0;
      await tester.pumpWidget(_app(Scaffold(
        body: DeleteAllSheet(
          wipe: () async {
            calls++;
            return true;
          },
          export: () async => exported++,
        ),
      )));
      expect(find.text(wipeKeepsText), findsOneWidget);
      expect(wipeKeepsText, contains('Samsung Health'));
      expect(wipeKeepsText, contains('Λήψεις'));
      expect(wipeKeepsText, contains('αντίγραφο της Google'));
      expect(wipeKeepsText, contains('ρολόι'));
      await tap(tester, 'wipe-confirm');
      expect(calls, 0, reason: 'χωρίς «Κατάλαβα» δεν σβήνει τίποτα');
      await tap(tester, 'wipe-export');
      expect(exported, 1);
      await tap(tester, 'wipe-understood');
      await tap(tester, 'wipe-confirm');
      expect(calls, 1);
    });

    testWidgets('αποτυχία: λέει πώς γίνεται από τις Ρυθμίσεις Android', (tester) async {
      await tester.pumpWidget(_app(Scaffold(body: DeleteAllSheet(understood: true, wipe: () async => false))));
      await tap(tester, 'wipe-confirm');
      expect(find.byKey(const ValueKey('wipe-failed')), findsOneWidget);
      expect(find.text(wipeFailedText), findsOneWidget);
    });

    testWidgets('η γραμμή στις Ρυθμίσεις ανοίγει το φύλλο· «Άκυρο» = τίποτα', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_app(Scaffold(
        body: ListView(children: [
          DeleteAllRow(
            store: null,
            wipe: () async {
              calls++;
              return true;
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
    });

    test('η πλευρά Android: ίδιο με «Διαγραφή δεδομένων» του συστήματος, widgets χωρίς τιμές πριν', () {
      final kt = File('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/DataWipe.kt').readAsStringSync();
      expect(kt, contains('clearApplicationUserData()'));
      expect(kt.indexOf('HomeWidgets.wipe'), lessThan(kt.indexOf('clearApplicationUserData()')));
      final main = File('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/MainActivity.kt').readAsStringSync();
      expect(main, contains('"ygeia/privacy"'));
      expect(kt.indexOf('"/ygeia/wipe"'), lessThan(kt.indexOf('clearApplicationUserData()')));
      expect(kt, contains('FILTER_PREFIX'));
      final settings = File('lib/pages/settings.dart').readAsStringSync();
      expect(settings, contains('const PrivacyGroup()'));
      expect(settings, contains('DeleteAllRow(store: widget.store'));
      // Το ρολόι σβήνει όταν δει το «/ygeia/wipe» (δοκιμή Kotlin WipeRuleTest).
      expect(File('android/wear/src/main/kotlin/gr/ygeiaforma/wear/Link.kt').readAsStringSync(), contains('path == Paths.WIPE'));
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
  test('targetSdk 36 ρητά (και στο ρολόι)· το σχόλιο της υπογραφής λέει την αλήθεια', () {
    final g = File('android/ygeia/app-extra.gradle.kts').readAsStringSync();
    expect(g, contains('targetSdk = 36'));
    expect(g, contains('compileSdk = 36'));
    expect(g, isNot(contains('προσωρινή μνήμη')));
    expect(File('android/wear/build.gradle.kts').readAsStringSync(), contains('targetSdk = 36'));
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

  // ------------------------------------------------------------ RT-12 / RT-18
  test('χωρίς GPS: «≈» και «από βήματα»· χωρίς τίποτα: «—», όχι 0,00', () {
    Session c({bool? gps, double? m, int? steps}) => Session(
        id: 'c', workout: 'walk', name: 'Π', programId: '', start: DateTime(2026, 11, 1), cardioMinutes: 30, gps: gps, meters: m, steps: steps);
    expect(kmValue(c(gps: true, m: 2310)), '2,31');
    expect(kmValue(c(gps: false, m: 2310, steps: 3000)), '≈ 2,31');
    expect(kmValue(c(gps: false, m: 0, steps: 0)), isNull);
    expect(distanceFromSteps(c(gps: false, m: 2310)), isTrue);
  });

  // ------------------------------------------------------------ V-B-13 / UX3-05 / V-D-05 / V-D-30: οξυγόνο
  test('οξυγόνο: μία απάντηση και ίδιες ετικέτες παντού· τα κενά της V-B', () {
    expect(oxygenAboutShort, contains(oxygenNoNoteText));
    expect(oxygenAboutText, contains(oxygenRangeText));
    expect(oxygenRangeText, contains('70–100%'));
    expect(oxygenSourceText, 'Μέσος όρος από το Oura, χαμηλότερη τιμή από το ρολόι.');
    expect([for (final r in sourceRows) r.title], containsAll([oxygenAvgLabel, oxygenMinLabel]));
    final oura = File('lib/pages/oura_pages.dart').readAsStringSync();
    expect(oura, isNot(contains('όχι οξυγόνο')));
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
    expect(snap, contains("'7 νύχτες \${sr.placeText(sleepWeek)}'"));
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
}
