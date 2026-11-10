// Κλάδος fix-accuracy (έλεγχος 9/11): ακρίβεια, ιατρικά/στατιστικά κείμενα, πλατφόρμα, ΓΚΠΔ.
// Κάθε δοκιμή αποτυγχάνει χωρίς την αντίστοιχη διόρθωση.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/error_report.dart';
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

    testWidgets('ο διακόπτης στην κάρτα «Απόρρητο»', (tester) async {
      final saved = <bool>[];
      final r = ErrorReporter(persist: (on) async => saved.add(on));
      await tester.pumpWidget(_app(Scaffold(body: ListView(children: [PrivacyCard(store: null, reporter: r)]))));
      expect(find.text('Αναφορές σφαλμάτων'), findsOneWidget);
      expect(find.textContaining('ποτέ δεδομένα υγείας ή φαγητού'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('privacy-errors')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('privacy-errors')));
      await tester.pumpAndSettle();
      expect(saved, [false]);
      expect(r.enabled, isFalse);
      expect(find.textContaining('δεν στέλνεται τίποτα'), findsOneWidget);
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
    testWidgets('δύο επιβεβαιώσεις· λέει τι ΔΕΝ σβήνεται· Ακύρωση = τίποτα', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_app(DeleteAllPage(store: null, wipe: () async {
        calls++;
        return true;
      })));
      expect(find.text('Τι ΔΕΝ σβήνεται'), findsOneWidget);
      expect(find.textContaining('Samsung Health μένουν εκεί'), findsOneWidget);
      expect(find.textContaining('Λήψεις'), findsWidgets);
      expect(find.textContaining('αντίγραφο της Google'), findsOneWidget);
      expect(find.textContaining('ρολόι'), findsWidgets);
      expect(find.byKey(const ValueKey('wipe-confirm')), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('wipe-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wipe-next')));
      await tester.pumpAndSettle();
      expect(calls, 0, reason: 'το πρώτο πάτημα δεν σβήνει τίποτα');
      expect(find.text('Σίγουρα;'), findsOneWidget);
      expect(find.textContaining('δεν αναιρείται'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('wipe-confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wipe-confirm')));
      await tester.pumpAndSettle();
      expect(calls, 1);
    });

    testWidgets('αποτυχία: λέει πώς γίνεται από τις Ρυθμίσεις Android', (tester) async {
      await tester.pumpWidget(_app(DeleteAllPage(store: null, initialStep: 2, wipe: () async => false)));
      await tester.ensureVisible(find.byKey(const ValueKey('wipe-confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wipe-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wipe-failed')), findsOneWidget);
      expect(find.text(wipeFailedText), findsOneWidget);
    });

    testWidgets('Ακύρωση στο 2ο βήμα: δεν σβήνει', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(DeleteAllPage.route(null, wipe: () async {
              calls++;
              return true;
            })),
            child: const Text('άνοιγμα'),
          ),
        ),
      )));
      await tester.tap(find.text('άνοιγμα'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('wipe-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wipe-next')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('wipe-cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wipe-cancel')));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.text('άνοιγμα'), findsOneWidget);
    });

    test('η πλευρά Android: ίδιο με «Διαγραφή δεδομένων» του συστήματος, widgets χωρίς τιμές πριν', () {
      final kt = File('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/DataWipe.kt').readAsStringSync();
      expect(kt, contains('clearApplicationUserData()'));
      expect(kt.indexOf('HomeWidgets.wipe'), lessThan(kt.indexOf('clearApplicationUserData()')));
      final main = File('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/MainActivity.kt').readAsStringSync();
      expect(main, contains('"ygeia/privacy"'));
      expect(File('lib/pages/settings.dart').readAsStringSync(), contains('PrivacyCard(store: store)'));
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
}
