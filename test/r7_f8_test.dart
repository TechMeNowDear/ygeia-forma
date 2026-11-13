// Round 7 · f8: «Τι φτάνει» › Σήμερα › Βήματα της μέρας της ανάγνωσης (R7-A10-3), το «readAt» είναι η ΑΡΧΗ της
// ανάγνωσης (R7-A10-4), ελληνικά κείμενα του ίδιου του Flutter (R7-U4-7). Φανταστικές τιμές (δημόσιο repo).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/history.dart' show dateKey;
import 'package:ygeia_forma/main.dart';
import 'package:ygeia_forma/pages/privacy_page.dart' show WipeStatus;
import 'package:ygeia_forma/system_texts.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/ti_ftanei.dart';

const _samsung = MethodChannel('ygeia/samsung');
const _kotlin = 'android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma';

TestDefaultBinaryMessenger get _messenger => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// «Τι φτάνει» με απάντηση της γέφυρας όπως στο κινητό: όλες οι άδειες, καμία κάρτα είδους, μόνο η κάρτα «Σήμερα».
Future<void> _tiFtanei(WidgetTester t, {required String readAt, required List<Map<String, dynamic>> stepsByDay}) async {
  final all = {
    'ok': true,
    'readAt': readAt,
    'days': 30,
    'today': {'stepsByDay': stepsByDay, 'totalCalories': 120.4, 'activeCalories': 0.0},
    'types': <Object>[],
  };
  _messenger.setMockMethodCallHandler(_samsung, (call) async => switch (call.method) {
        'status' => jsonEncode({'ok': true, 'granted': 10, 'total': 10}),
        'readAll' => jsonEncode(all),
        _ => jsonEncode({'ok': false, 'kind': 'other'}),
      });
  addTearDown(() => _messenger.setMockMethodCallHandler(_samsung, null));
  await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: const TiFtaneiScreen()));
  await t.pumpAndSettle();
}

void main() {
  // ------------------------------------------------------------------------- R7-A10-3
  group('R7-A10-3: «Σήμερα › Βήματα» μόνο με τιμή της μέρας της ανάγνωσης', () {
    test('η Samsung δίνει μόνο μέρες με βήματα: μετά τα μεσάνυχτα η πρώτη είναι η χθεσινή → καμία τιμή', () {
      final yesterdayOnly = [
        {'date': '2026-11-12', 'value': 11240},
      ];
      expect(stepsOfReadDay(yesterdayOnly, '2026-11-13T00:20'), isNull);
      final both = [
        {'date': '2026-11-13', 'value': 1500},
        {'date': '2026-11-12', 'value': 11240},
      ];
      expect(stepsOfReadDay(both, '2026-11-13T00:20'), 1500);
      // Ανάγνωση 23:59:30 της 12/11: η Kotlin μετρά «σήμερα» από την ίδια στιγμή (to.toLocalDate()).
      expect(stepsOfReadDay(both, '2026-11-12T23:59:30'), 11240);
      expect(stepsOfReadDay([{'date': '2026-11-13', 'value': null}], '2026-11-13T09:00'), isNull);
      expect(stepsOfReadDay(const [], '2026-11-13T09:00'), isNull);
    });

    testWidgets('00:20, μόνο χθεσινά βήματα: η κάρτα δείχνει «—», όχι 11.240', (t) async {
      await _tiFtanei(t, readAt: '2026-11-13T00:20:00', stepsByDay: [
        {'date': '2026-11-12', 'value': 11240},
      ]);
      expect(find.text('Σήμερα'), findsOneWidget);
      expect(find.text('11.240'), findsNothing);
      expect(find.text('—'), findsOneWidget, reason: 'μόνο τα βήματα· θερμίδες 120 και 0');
      expect(find.text('120'), findsOneWidget);
    });

    testWidgets('με σημερινή τιμή: η σημερινή (1.500), όχι η πρώτη οποιασδήποτε μέρας', (t) async {
      await _tiFtanei(t, readAt: '2026-11-13T09:30:00', stepsByDay: [
        {'date': '2026-11-13', 'value': 1500},
        {'date': '2026-11-12', 'value': 11240},
      ]);
      expect(find.text('1.500'), findsOneWidget);
      expect(find.text('—'), findsNothing);
    });

    test('Kotlin: βήματα και θερμίδες της κάρτας από τη μέρα του «readAt», όχι από νέο «τώρα» σε κάθε ερώτηση', () {
      final bridge = File('$_kotlin/SamsungHealthBridge.kt').readAsStringSync();
      expect(bridge, contains('val day = to.toLocalDate()'));
      expect(bridge, contains('dailySteps(s, 7, day)'));
      expect(bridge, contains('DataType.ActivitySummaryType.TOTAL_CALORIES_BURNED, day, to)'));
      expect(bridge, contains('LocalTimeFilter.of(day.atStartOfDay(), until)'));
      expect(bridge, isNot(contains('LocalDate.now()')));
    });
  });

  // ------------------------------------------------------------------------- R7-A10-4
  group('R7-A10-4: το «readAt» είναι η αρχή της ανάγνωσης', () {
    test('ανάγνωση 23:59:55 → 00:00:04: βήματα και σύνολα μένουν της 12/11 (το widget δείχνει «—» στις 13/11)', () {
      final start = DateTime(2026, 11, 12, 23, 59, 55);
      final d = Dashboard.fromJson({
        'ok': true,
        'readAt': start.millisecondsSinceEpoch,
        'steps': [
          [DateTime(2026, 11, 12).millisecondsSinceEpoch, 9000],
        ],
        'activity': {'calories': 2810.0, 'activeCalories': 640.0},
        'granted': 10,
        'total': 10,
      });
      expect(d.todaySteps, 9000);
      expect(dateKey(d.readAt), '2026-11-12', reason: 'η μέρα του «day» του στιγμιοτύπου (widget_snapshot.dart)');
    });

    test('Kotlin: ένα «readAt» από τον DashboardReader· η γέφυρα και ο RefreshWorker δεν βάζουν δικό τους', () {
      final reader = File('$_kotlin/DashboardReader.kt').readAsStringSync();
      expect(reader, contains('val moment = DataRules.readMoment(System.currentTimeMillis(), java.time.ZoneId.systemDefault())'));
      expect(reader, contains('o.put("readAt", moment.ms)'));
      expect(reader, contains('o.put("activity", safe { activity(today, now) })'));
      expect(reader, contains('val filter = LocalTimeFilter.of(today.atStartOfDay(), now)'));
      for (final f in ['SamsungHealthBridge.kt', 'RefreshWorker.kt']) {
        final src = File('$_kotlin/$f').readAsStringSync();
        expect(src, isNot(contains('.put("readAt", System.currentTimeMillis())')), reason: f);
      }
      // Ο RefreshWorker: η μέρα του widget «Κίνηση» είναι η μέρα του readAt, όχι η μέρα που τελείωσε η ανάγνωση.
      final widgets = File('$_kotlin/HomeWidgets.kt').readAsStringSync();
      expect(widgets, contains('dashboard.optLong("readAt", System.currentTimeMillis())).atZone(zone).toLocalDate()'));
      expect(widgets, contains('dashboard, readDay, zone)'));
    });
  });

  // ------------------------------------------------------------------------- R7-U4-7
  group('R7-U4-7: τα κείμενα του Flutter στα ελληνικά, χωρίς νέα βιβλιοθήκη', () {
    testWidgets('κύρια εφαρμογή: Επικόλληση, Πίσω, Άδειες λογισμικού, Κλείσιμο, Ανανέωση', (t) async {
      addTearDown(() => FoodStore.shared = null);
      await t.pumpWidget(YgeiaFormaApp(
        store: HealthStore(),
        food: FoodStore.preloaded(foods: const []),
        wiped: WipeStatus(at: DateTime(2026, 11, 15, 9), done: true, seen: false, watchPending: false, oura: 'none'),
        onLeaveWiped: () {},
      ));
      await t.pump();
      final l = MaterialLocalizations.of(t.element(find.text('Όλα διαγράφηκαν')));
      expect(l.cutButtonLabel, 'Αποκοπή');
      expect(l.copyButtonLabel, 'Αντιγραφή');
      expect(l.pasteButtonLabel, 'Επικόλληση');
      expect(l.selectAllButtonLabel, 'Επιλογή όλων');
      expect(l.backButtonTooltip, 'Πίσω');
      expect(l.closeButtonTooltip, 'Κλείσιμο');
      expect(l.modalBarrierDismissLabel, 'Κλείσιμο');
      expect(l.bottomSheetLabel, 'Φύλλο στο κάτω μέρος');
      expect(l.refreshIndicatorSemanticLabel, 'Ανανέωση');
      expect(l.licensesPageTitle, 'Άδειες λογισμικού');
      expect(l.licensesPackageDetailText(1), '1 άδεια');
      expect(l.licensesPackageDetailText(3), '3 άδειες');
      expect(l.remainingTextFieldCharacterCount(1), 'Απομένει 1 χαρακτήρας');
      expect(l.remainingTextFieldCharacterCount(12), 'Απομένουν 12 χαρακτήρες');
    });

    testWidgets('το μενού επιλογής κειμένου του Android: «Αντιγραφή», «Επικόλληση» (όχι Copy, Paste)', (t) async {
      await t.pumpWidget(MaterialApp(
        localizationsDelegates: greekSystemTexts,
        home: Scaffold(
          body: AdaptiveTextSelectionToolbar.buttonItems(
            anchors: TextSelectionToolbarAnchors(primaryAnchor: const Offset(200, 200)),
            buttonItems: [
              ContextMenuButtonItem(onPressed: () {}, type: ContextMenuButtonType.copy),
              ContextMenuButtonItem(onPressed: () {}, type: ContextMenuButtonType.paste),
            ],
          ),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.text('Αντιγραφή'), findsOneWidget);
      expect(find.text('Επικόλληση'), findsOneWidget);
      expect(find.text('Paste'), findsNothing);
    });

    test('κάθε MaterialApp της εφαρμογής δηλώνει τα ελληνικά· καμία νέα εξάρτηση στο pubspec', () {
      for (final f in ['lib/main.dart', 'lib/pages/privacy_page.dart', 'lib/pages/widget_config_page.dart']) {
        final src = File(f).readAsStringSync();
        expect('MaterialApp('.allMatches(src).length, 'localizationsDelegates: greekSystemTexts'.allMatches(src).length,
            reason: f);
        expect(src, contains('localizationsDelegates: greekSystemTexts'), reason: f);
      }
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, isNot(contains('flutter_localizations')));
      expect(pubspec, isNot(contains('intl')));
    });
  });
}
