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
import 'package:ygeia_forma/nav.dart';
import 'package:ygeia_forma/pages/kitchen.dart';
import 'package:ygeia_forma/pages/appearance.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/unusual.dart';
import 'package:ygeia_forma/oura/oura_api.dart';
import 'package:ygeia_forma/oura/oura_model.dart';
import 'package:ygeia_forma/pages/compare_page.dart';
import 'package:ygeia_forma/pages/oura_pages.dart';
import 'package:ygeia_forma/pages/sources_page.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/plan_file.dart';

import 'sample_data.dart';
import 'sample_food.dart';

final now = DateTime(2026, 10, 24, 16, 30);

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
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
  int sub = 0,
  bool backfilling = false,
  DateTime? at,
  void Function(HealthStore)? prepare,
  Future<void> Function(WidgetTester)? act,
  bool trends = false,
  Aigaio? palette,
  bool oura = false,
  bool ouraMissingToday = false,
}) async {
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = size * 2.0;
  addTearDown(tester.view.reset);

  final when = at ?? now;
  final store = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(when));
  store.history = sampleHistory(when, store.data!);
  if (oura) prepareOura(store, missingToday: ouraMissingToday, now: when);
  prepare?.call(store);
  if (backfilling) {
    store.backfilling = true;
    store.backfillReached = DateTime(when.year, when.month - 2, when.day);
  }
  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light, palette != null && !palette.dark ? palette : null),
        darkTheme: buildTheme(Brightness.dark, palette != null && palette.dark ? palette : null),
        themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        home: trends
            ? Scaffold(body: TrendsPage(store: store, now: when))
            : Shell(store: store, food: sampleFoodStore(when), initialIndex: tab, initialTab: sub, now: when),
      ),
    ),
  );
  // Η γραμμή συμπλήρωσης κινείται συνέχεια (χωρίς ποσοστό): ένα σταθερό καρέ αντί για «ησυχία».
  Future<void> settle() async {
    if (backfilling) {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    } else {
      await tester.pumpAndSettle();
    }
  }

  await settle();
  if (act != null) {
    await act(tester);
    await settle();
  }
  await expectLater(find.byKey(key), matchesGoldenFile('shots/$name.png'));
}

/// Μέρα στα στιγμιότυπα του Oura: Σάββατο 14/11, η σύνδεση στις 6/11 (8 μέρες πριν, η σύγκριση ανοιχτή).
final ouraNow = DateTime(2026, 11, 14, 10, 20);
final ouraStart = DateTime(2026, 11, 6);

/// Κατάσταση «Oura συνδεδεμένο» με δείγμα νυχτών (ίδιες μετατροπές με την εφαρμογή). [missingToday]: η χθεσινή
/// νύχτα δεν έχει έρθει (για την κάρτα «Περιμένει το Oura»).
void prepareOura(HealthStore store, {bool missingToday = false, DateTime? now}) {
  final at = now ?? ouraNow;
  final today = DateTime(at.year, at.month, at.day);
  store.debugSetPlan(SourcePlan.samsungOnly.withEra(Source.oura, ouraStart));
  final batch = parseOura(
    sleep: sampleOuraSleep(ouraStart, at, missing: {if (missingToday) today}),
    dailySleep: [
      for (var d = ouraStart; !d.isAfter(today); d = DateTime(d.year, d.month, d.day + 1))
        if (!(missingToday && d == today)) {'id': 'ds$d', 'day': dateKey(d), 'score': 70 + d.day % 15, 'timestamp': d.toIso8601String()},
    ],
    readiness: [
      for (var d = ouraStart; !d.isAfter(today); d = DateTime(d.year, d.month, d.day + 1))
        if (!(missingToday && d == today))
          {'id': 'dr$d', 'day': dateKey(d), 'score': 64 + d.day % 12, 'temperature_deviation': (d.day % 5 - 2) / 10, 'timestamp': d.toIso8601String()},
    ],
  );
  store.ouraNights = batch.nights;
  // Πριν από τη σύνδεση: λίγες «παλιές» νύχτες Oura δεν υπάρχουν· το ιστορικό του Oura γράφεται μόνο από τη σύνδεση.
  mergeOura(store.history, ouraRows(batch.nights), from: ouraStart, to: today, plan: store.plan);
  stripForeignWatchNight(store.history, store.plan, from: ouraStart);
  store.ouraHasTokens = true;
  store.ouraLink = OuraLink(vault: MemoryVault(), clientId: 'SCREENSHOT');
  store.ouraClock = () => at;
  store.ouraSyncedMs = at.subtract(const Duration(minutes: 12)).millisecondsSinceEpoch;
  store.ouraSyncedTo = dateKey(today);
}

Future<void> _page(
  WidgetTester tester, {
  required String name,
  required Size size,
  required Brightness brightness,
  required Widget Function(HealthStore) page,
  bool oura = true,
  void Function(HealthStore)? prepare,
}) async {
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = size * 2.0;
  addTearDown(tester.view.reset);
  final store = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(ouraNow));
  store.history = sampleHistory(ouraNow, store.data!);
  if (oura) prepareOura(store);
  prepare?.call(store);
  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: page(store),
    ),
  ));
  await tester.pumpAndSettle();
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
  testWidgets('Αναφορά για γιατρό · με σημείωση 160 χαρακτήρων (να χωράει)', (tester) async {
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
          home: ReportPage(store: store, now: now, note: 'Φάρμακα: ' * 16),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(find.byKey(key), matchesGoldenFile('shots/13b_report_note.png'));
  });
  testWidgets('Σήμερα · μικρό κινητό 360', (t) => _shot(t, name: '25_today_360', size: const Size(360, 1900), brightness: Brightness.light, tab: 0));
  testWidgets('Σήμερα · Fold ανοιχτό 750', (t) => _shot(t, name: '26_today_fold750', size: const Size(750, 1500), brightness: Brightness.light, tab: 0));
  testWidgets('Υγεία · Fold ανοιχτό 750', (t) => _shot(t, name: '27_body_fold750', size: const Size(750, 1500), brightness: Brightness.light, tab: Cat.health, sub: HealthTab.body));
  testWidgets('Διατροφή · Fold ανοιχτό 750', (t) => _shot(t, name: '28_nutrition_fold750', size: const Size(750, 1500), brightness: Brightness.light, tab: Cat.food));
  testWidgets('Τάσεις · κινητό', (t) => _shot(t, name: '04_trends_phone_light', size: tall, brightness: Brightness.light, tab: Cat.health, sub: HealthTab.trends));
  testWidgets('Διατροφή · κινητό', (t) => _shot(t, name: '14_nutrition_phone_light', size: tall, brightness: Brightness.light, tab: Cat.food));
  testWidgets('Διατροφή · Fold ανοιχτό · σκοτεινό', (t) => _shot(t, name: '15_nutrition_open_dark', size: open, brightness: Brightness.dark, tab: Cat.food));
  testWidgets('Διατροφή · προσθήκη · αναζήτηση', (t) => _shot(
        t,
        name: '16_add_food_search',
        size: phone,
        brightness: Brightness.light,
        tab: Cat.food,
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
        tab: Cat.food,
        act: (t) async {
          await t.tap(find.text('Φαγητό'));
        },
      ));
  testWidgets('Διατροφή · τα προϊόντα μου', (t) => _shot(
        t,
        name: '19_my_foods',
        size: phone,
        brightness: Brightness.light,
        tab: Cat.food,
        sub: FoodTab.mine,
        act: (t) async {
          await t.tap(find.byKey(const ValueKey('mine-products')));
        },
      ));
  testWidgets('Διατροφή · αναζήτηση με μάρκα', (t) => _shot(
        t,
        name: '20_search_branded',
        size: phone,
        brightness: Brightness.dark,
        tab: Cat.food,
        act: (t) async {
          await t.tap(find.text('Φαγητό'));
          await t.pumpAndSettle();
          await t.enterText(find.byType(TextField), 'giaourti');
        },
      ));
  testWidgets('Η κουζίνα μου', (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(400, 2400) * 2.0;
    addTearDown(tester.view.reset);
    final store = HealthStore();
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        home: KitchenScreen(store: store),
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(find.byKey(key), matchesGoldenFile('shots/21_kitchen.png'));
  });
  testWidgets('Διατροφή · ποσότητα', (t) => _shot(
        t,
        name: '18_quantity_sheet',
        size: phone,
        brightness: Brightness.light,
        tab: Cat.food,
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
        tab: Cat.health,
        sub: HealthTab.trends,
        backfilling: true,
        act: (t) async {
          final row = find.byKey(const ValueKey('trend-sleepHr'));
          await t.ensureVisible(row);
          for (var i = 0; i < 6; i++) {
            await t.pump(const Duration(milliseconds: 100)); // η γραμμή συμπλήρωσης κινείται συνέχεια
          }
          await t.tap(row);
        },
      ));
  testWidgets('Τάσεις · Fold ανοιχτό · χρόνος', (t) => _shot(
        t,
        name: '06_trends_open_light_year',
        size: open,
        brightness: Brightness.light,
        tab: Cat.health,
        sub: HealthTab.trends,
        act: (t) async {
          await t.tap(find.byKey(const ValueKey('period-year')));
        },
      ));
  testWidgets('Ύπνος · κινητό', (t) => _shot(t, name: '07_sleep_phone_light', size: phone, brightness: Brightness.light, tab: Cat.health, sub: HealthTab.sleep));
  testWidgets('Καρδιά · κινητό', (t) => _shot(t, name: '08_heart_phone_light', size: phone, brightness: Brightness.light, tab: Cat.health, sub: HealthTab.heart));
  testWidgets('Σώμα · κινητό', (t) => _shot(t, name: '09_body_phone_light', size: tall, brightness: Brightness.light, tab: Cat.health, sub: HealthTab.body));
  testWidgets('Σώμα · Fold ανοιχτό · σκοτεινό', (t) => _shot(t, name: '10_body_open_dark', size: open, brightness: Brightness.dark, tab: Cat.health, sub: HealthTab.body));
  testWidgets('Διατροφή · τα δικά μου', (t) => _shot(t, name: '22_mine_phone_light', size: phone, brightness: Brightness.light, tab: Cat.food, sub: FoodTab.mine));
  testWidgets('Άσκηση · κινητό', (t) => _shot(t, name: '23_exercise_phone_light', size: tall, brightness: Brightness.light, tab: Cat.exercise));
  testWidgets('Άσκηση · Fold ανοιχτό · σκοτεινό', (t) => _shot(t, name: '24_exercise_open_dark', size: open, brightness: Brightness.dark, tab: Cat.exercise));

  // Θέματα (1/11): η αρχική και ο ύπνος σε καθένα, και η οθόνη «Εμφάνιση».
  for (final (n, p) in [(30, Aigaio.elia), (32, Aigaio.avgi), (34, Aigaio.stivos), (36, Aigaio.anasa)]) {
    final b = p.dark ? Brightness.dark : Brightness.light;
    testWidgets('Θέμα ${p.name} · Σήμερα', (t) => _shot(t, name: '${n}_theme_${p.id}_today', size: phone, brightness: b, tab: 0, palette: p));
    testWidgets('Θέμα ${p.name} · Διατροφή', (t) => _shot(t, name: '${n + 1}_theme_${p.id}_food', size: phone, brightness: b, tab: Cat.food, palette: p));
  }
  testWidgets('Θέμα Ελιά · Fold ανοιχτό', (t) => _shot(t, name: '38_theme_elia_open', size: open, brightness: Brightness.light, tab: Cat.health, palette: Aigaio.elia));
  for (final p in [Aigaio.light, Aigaio.stivos]) {
    testWidgets('Εμφάνιση · ${p.name}', (tester) async {
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(400, 1700) * 2.0;
      addTearDown(tester.view.reset);
      final store = HealthStore()
        ..prefs.dayTheme = 'aigaio'
        ..prefs.nightTheme = p.dark ? p.id : 'anasa'
        ..prefs.themeMode = p.dark ? 'dark' : 'auto';
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light, p.dark ? null : p),
          darkTheme: buildTheme(Brightness.dark, p.dark ? p : null),
          themeMode: p.dark ? ThemeMode.dark : ThemeMode.light,
          home: AppearancePage(store: store),
        ),
      ));
      await tester.pumpAndSettle();
      await expectLater(find.byKey(key), matchesGoldenFile('shots/${p.dark ? 40 : 39}_appearance_${p.dark ? 'dark' : 'light'}.png'));
    });
  }

  // Oura (2/11): ύπνος μόνο από το δαχτυλίδι. Κλειστό Fold (400) και ανοιχτό (860), φωτεινό και σκοτεινό Αιγαίο.
  const fold = Size(400, 2200);
  const foldOpen = Size(860, 1700);
  for (final (n, size, b, tag) in [
    (50, fold, Brightness.light, 'closed_light'),
    (51, fold, Brightness.dark, 'closed_dark'),
    (52, foldOpen, Brightness.light, 'open_light'),
    (53, foldOpen, Brightness.dark, 'open_dark'),
  ]) {
    testWidgets('Oura · Σήμερα · $tag', (t) => _shot(t, name: '${n}_oura_today_$tag', size: size, brightness: b, tab: 0, at: ouraNow, oura: true));
    testWidgets('Oura · Ύπνος · $tag', (t) => _shot(
          t,
          name: '${n + 4}_oura_sleep_$tag',
          size: size == fold ? const Size(400, 3000) : foldOpen,
          brightness: b,
          tab: Cat.health,
          sub: HealthTab.sleep,
          at: ouraNow,
          oura: true,
        ));
    testWidgets('Πηγές · $tag', (t) => _page(t, name: '${n + 8}_sources_$tag', size: size, brightness: b, page: (s) => SourcesPage(store: s, now: ouraNow)));
    testWidgets('Σύγκριση πηγών · $tag',
        (t) => _page(t, name: '${n + 12}_compare_$tag', size: size, brightness: b, page: (s) => ComparePage(store: s, now: ouraNow)));
    testWidgets('Oura · διαχείριση · $tag',
        (t) => _page(t, name: '${n + 16}_oura_manage_$tag', size: size, brightness: b, page: (s) => OuraManagePage(store: s, now: ouraNow)));
    testWidgets('Σύνδεση Oura · $tag', (t) => _page(
          t,
          name: '${n + 20}_oura_connect_$tag',
          size: size,
          brightness: b,
          oura: false,
          page: (s) => OuraConnectPage(store: s, now: ouraNow),
        ));
  }
  testWidgets('Oura · Σήμερα · περιμένει τη νύχτα', (t) => _shot(
        t,
        name: '74_oura_today_waiting',
        size: fold,
        brightness: Brightness.light,
        tab: 0,
        at: DateTime(2026, 11, 14, 8, 5),
        oura: true,
        ouraMissingToday: true,
      ));
  testWidgets('Oura · Σήμερα · χρειάζεται νέα σύνδεση', (t) => _shot(
        t,
        name: '75_oura_today_reconnect',
        size: fold,
        brightness: Brightness.dark,
        tab: 0,
        at: ouraNow,
        oura: true,
        prepare: (s) {
          s.ouraHasTokens = false;
          s.ouraError = OuraErrorKind.reconnect;
        },
      ));
  testWidgets('Oura · Σήμερα · συνδρομή', (t) => _shot(
        t,
        name: '76_oura_today_subscription',
        size: fold,
        brightness: Brightness.light,
        tab: 0,
        at: ouraNow,
        oura: true,
        prepare: (s) => s.ouraError = OuraErrorKind.subscription,
      ));
  testWidgets('Oura · Καρδιά', (t) => _shot(
        t,
        name: '77_oura_heart',
        size: const Size(400, 2400),
        brightness: Brightness.light,
        tab: Cat.health,
        sub: HealthTab.heart,
        at: ouraNow,
        oura: true,
      ));
  testWidgets('Oura · Τάσεις · αλλαγή πηγής', (t) => _shot(
        t,
        name: '78_oura_trends',
        size: const Size(400, 3600),
        brightness: Brightness.light,
        tab: Cat.health,
        sub: HealthTab.trends,
        at: ouraNow,
        oura: true,
        act: (t) async {
          final row = find.byKey(const ValueKey('trend-sleepMin'));
          await t.ensureVisible(row);
          await t.pumpAndSettle();
          await t.tap(row);
        },
      ));
  testWidgets('Πηγές · πριν από το Oura', (t) => _page(
        t,
        name: '79_sources_before',
        size: fold,
        brightness: Brightness.light,
        oura: false,
        page: (s) => SourcesPage(store: s, now: ouraNow),
      ));
  testWidgets('Oura · Ύπνος · αποσυνδέθηκε', (t) => _shot(
        t,
        name: '80_oura_sleep_disconnected',
        size: fold,
        brightness: Brightness.light,
        tab: Cat.health,
        sub: HealthTab.sleep,
        at: ouraNow,
        oura: true,
        prepare: (s) {
          s.debugSetPlan(s.plan.withEra(Source.none, DateTime(2026, 11, 13)));
          s.ouraHasTokens = false;
        },
      ));
  testWidgets('Oura · διαχείριση · αποσυνδέθηκε', (t) => _page(
        t,
        name: '81_oura_manage_disconnected',
        size: fold,
        brightness: Brightness.light,
        page: (s) => OuraManagePage(store: s, now: ouraNow),
        prepare: (s) {
          s.debugSetPlan(s.plan.withEra(Source.none, DateTime(2026, 11, 13)));
          s.ouraHasTokens = false;
        },
      ));
  testWidgets('Oura · Σήμερα · συνδέθηκε σήμερα (από απόψε)', (t) => _shot(
        t,
        name: '82_oura_today_starting',
        size: fold,
        brightness: Brightness.light,
        tab: 0,
        at: ouraNow,
        prepare: (s) {
          s.debugSetPlan(SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 15)));
          s.ouraHasTokens = true;
          s.ouraClock = () => ouraNow;
        },
      ));
  testWidgets('Πηγές · άγνωστο σχέδιο (χαλασμένο αρχείο)', (t) => _page(
        t,
        name: '83_sources_plan_unknown',
        size: fold,
        brightness: Brightness.light,
        page: (s) => SourcesPage(store: s, now: ouraNow),
        prepare: (s) => s.debugSetPlan(SourcePlan([SourceEra(Source.none, ouraStart)]), state: PlanState.unknown),
      ));
  testWidgets('Σήμερα · άγνωστο σχέδιο', (t) => _shot(
        t,
        name: '84_today_plan_unknown',
        size: fold,
        brightness: Brightness.dark,
        tab: 0,
        at: ouraNow,
        oura: true,
        prepare: (s) => s.debugSetPlan(SourcePlan([SourceEra(Source.none, ouraStart)]), state: PlanState.unknown),
      ));
}
