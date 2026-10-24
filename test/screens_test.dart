// Ζωγραφίζει τις οθόνες με δείγμα δεδομένων, για έλεγχο της εμφάνισης.
// Τρέχει μόνο με: flutter test test/screens_test.dart --update-goldens
// Τα PNG γράφονται στο test/shots/ και ανεβαίνουν στο branch «screenshots».
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/main.dart';
import 'package:ygeia_forma/pages/report_page.dart';
import 'package:ygeia_forma/pages/trends.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/unusual.dart';

import 'sample_data.dart';
import 'sample_food.dart';

final now = DateTime(2026, 10, 24, 16, 30);

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
  }
  await inter.load();

  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final file = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (file.existsSync()) {
      final icons = FontLoader('MaterialIcons');
      icons.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      await icons.load();
    }
  }
}

Future<void> _shot(
  WidgetTester tester, {
  required String name,
  required Size size,
  required Brightness brightness,
  required int tab,
  bool backfilling = false,
  DateTime? at,
  void Function(HealthStore)? prepare,
  Future<void> Function(WidgetTester)? act,
  bool trends = false,
}) async {
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = size * 2.0;
  addTearDown(tester.view.reset);

  final when = at ?? now;
  final store = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(when));
  store.history = sampleHistory(when, store.data!);
  prepare?.call(store);
  if (backfilling) {
    store.backfilling = true;
    store.backfillProgress = 0.42;
  }
  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        home: trends
            ? Scaffold(body: TrendsPage(store: store, now: when))
            : Shell(store: store, food: sampleFoodStore(when), initialIndex: tab, now: when),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (act != null) {
    await act(tester);
    await tester.pumpAndSettle();
  }
  await expectLater(find.byKey(key), matchesGoldenFile('shots/$name.png'));
}

void main() {
  setUpAll(_loadFonts);

  const phone = Size(400, 1900);
  const open = Size(860, 1500);

  const tall = Size(400, 3200);

  testWidgets('Σήμερα · κινητό · ανοιχτό', (t) => _shot(t, name: '01_today_phone_light', size: phone, brightness: Brightness.light, tab: 0));
  testWidgets('Σήμερα · κινητό · σκοτεινό', (t) => _shot(t, name: '02_today_phone_dark', size: phone, brightness: Brightness.dark, tab: 0));
  testWidgets('Σήμερα · Fold ανοιχτό', (t) => _shot(t, name: '03_today_open_light', size: open, brightness: Brightness.light, tab: 0));
  testWidgets('Σήμερα · Κυριακή βράδυ · απολογισμός', (t) => _shot(
        t,
        name: '11_week_phone_light',
        size: tall,
        brightness: Brightness.light,
        tab: 0,
        at: DateTime(2026, 10, 25, 19, 10),
      ));
  testWidgets('Σήμερα · εκτός συνηθισμένου', (t) => _shot(
        t,
        name: '12_unusual_phone_dark',
        size: phone,
        brightness: Brightness.dark,
        tab: 0,
        prepare: (store) {
          final today = DateTime(now.year, now.month, now.day);
          // Παλμοί και δέρμα ξεκάθαρα πάνω από το όριο του καθενός (όριο × 1,3).
          final yesterday = store.history[dateKey(today.subtract(const Duration(days: 1)))] ?? {};
          store.history[dateKey(today)] = {
            K.sleepHr: yesterday[K.sleepHr] ?? 60,
            K.skinTemp: yesterday[K.skinTemp] ?? 34,
            ...?store.history[dateKey(today)],
          };
          final row = {...store.history[dateKey(today)]!};
          for (final sig in checkUnusual(store.history, today).signals) {
            if (sig.rule.key == K.energy) continue;
            row[sig.rule.key] = sig.usual + sig.threshold * 1.3;
          }
          store.history[dateKey(today)] = row;
        },
      ));
  testWidgets('Αναφορά για γιατρό', (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(680, 2200) * 2.0;
    addTearDown(tester.view.reset);
    final store = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(now));
    store.history = sampleHistory(now, store.data!);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          home: ReportPage(store: store, now: now),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(find.byKey(key), matchesGoldenFile('shots/13_report.png'));
  });
  testWidgets('Τάσεις · κινητό', (t) => _shot(t, name: '04_trends_phone_light', size: tall, brightness: Brightness.light, tab: 0, trends: true));
  testWidgets('Διατροφή · κινητό', (t) => _shot(t, name: '14_nutrition_phone_light', size: tall, brightness: Brightness.light, tab: 1));
  testWidgets('Διατροφή · Fold ανοιχτό · σκοτεινό', (t) => _shot(t, name: '15_nutrition_open_dark', size: open, brightness: Brightness.dark, tab: 1));
  testWidgets('Διατροφή · προσθήκη · αναζήτηση', (t) => _shot(
        t,
        name: '16_add_food_search',
        size: phone,
        brightness: Brightness.light,
        tab: 1,
        act: (t) async {
          await t.tap(find.text('Φαγητό'));
          await t.pumpAndSettle();
          await t.enterText(find.byType(TextField), 'kotopoulo');
        },
      ));
  testWidgets('Διατροφή · προσθήκη · πρόσφατα', (t) => _shot(
        t,
        name: '17_add_food_recent',
        size: phone,
        brightness: Brightness.dark,
        tab: 1,
        act: (t) async {
          await t.tap(find.text('Φαγητό'));
        },
      ));
  testWidgets('Διατροφή · ποσότητα', (t) => _shot(
        t,
        name: '18_quantity_sheet',
        size: phone,
        brightness: Brightness.light,
        tab: 1,
        act: (t) async {
          await t.tap(find.text('Φαγητό'));
          await t.pumpAndSettle();
          await t.enterText(find.byType(TextField), 'fakes');
          await t.pumpAndSettle();
          await t.tap(find.text('Φακές (βρασμένες)').first);
        },
      ));
  testWidgets('Τάσεις · κινητό · ανοιχτή γραμμή', (t) => _shot(
        t,
        name: '05_trends_phone_dark_open_row',
        size: phone,
        brightness: Brightness.dark,
        tab: 0,
        trends: true,
        backfilling: true,
        act: (t) async {
          final row = find.byKey(const ValueKey('trend-sleepHr'));
          await t.ensureVisible(row);
          await t.pumpAndSettle();
          await t.tap(row);
        },
      ));
  testWidgets('Τάσεις · Fold ανοιχτό · χρόνος', (t) => _shot(
        t,
        name: '06_trends_open_light_year',
        size: open,
        brightness: Brightness.light,
        tab: 0,
        trends: true,
        act: (t) async {
          await t.tap(find.byKey(const ValueKey('period-year')));
        },
      ));
  testWidgets('Ύπνος · κινητό', (t) => _shot(t, name: '07_sleep_phone_light', size: phone, brightness: Brightness.light, tab: 2));
  testWidgets('Καρδιά · κινητό', (t) => _shot(t, name: '08_heart_phone_light', size: phone, brightness: Brightness.light, tab: 3));
  testWidgets('Σώμα και κίνηση · κινητό', (t) => _shot(t, name: '09_body_phone_light', size: tall, brightness: Brightness.light, tab: 4));
  testWidgets('Σώμα και κίνηση · Fold ανοιχτό · σκοτεινό', (t) => _shot(t, name: '10_body_open_dark', size: open, brightness: Brightness.dark, tab: 4));
}
