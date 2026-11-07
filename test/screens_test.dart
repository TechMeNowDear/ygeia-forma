// Ζωγραφίζει τις οθόνες με δείγμα δεδομένων, για έλεγχο της εμφάνισης.
// Τρέχει μόνο με: flutter test test/screens_test.dart --update-goldens
// Τα PNG γράφονται στο test/shots/ και ανεβαίνουν στο branch «screenshots».
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/format.dart' show sameDay;
import 'package:ygeia_forma/main.dart';
import 'package:ygeia_forma/pages/report_page.dart';
import 'package:ygeia_forma/pages/sleep.dart';
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
import 'package:ygeia_forma/pages/widget_config_page.dart';
import 'package:ygeia_forma/home_widgets/widget_bridge.dart';
import 'package:ygeia_forma/home_widgets/widget_style.dart';
import 'package:ygeia_forma/pages/oura_pages.dart';
import 'package:ygeia_forma/pages/sources_page.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/plan_file.dart';
import 'package:ygeia_forma/ti_ftanei.dart';

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

/// Συγχώνευση 3: η σημείωση της αναφοράς φαίνεται ολόκληρη (χωρίς όριο γραμμών και «…», το ύψος στην οθόνη = το
/// ύψος όλου του κειμένου) και η σελίδα 1 δεν ξεχειλίζει (η σημείωση και ο πίνακας πάνω από το υποσέλιδο).
void _expectWholeNote(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  final f = find.byKey(const ValueKey('report-note-text'));
  final w = tester.widget<Text>(f);
  expect(w.maxLines, isNull);
  expect(w.overflow, isNot(TextOverflow.ellipsis));
  final p = tester.renderObject<RenderParagraph>(f);
  expect(p.didExceedMaxLines, isFalse);
  final tp = TextPainter(text: p.text, textDirection: TextDirection.ltr, textScaler: TextScaler.noScaling)
    ..layout(maxWidth: p.constraints.maxWidth);
  expect(p.size.height, closeTo(tp.height, 0.01));
  tp.dispose();
  final footer = tester.getRect(find.textContaining('σελίδα 1 από'));
  expect(tester.getRect(f).bottom, lessThan(footer.top));
  expect(tester.getRect(find.text('Πώς διαβάζεται').first).bottom, lessThan(footer.top));
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
  Future<void> Function(WidgetTester)? act,
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
  if (act != null) {
    await act(tester);
    await tester.pumpAndSettle();
  }
  await expectLater(find.byKey(key), matchesGoldenFile('shots/$name.png'));
}

/// «Τι φτάνει» με απαντήσεις της γέφυρας Samsung όπως στο κινητό (κανάλι «ygeia/samsung», χωρίς συσκευή).
Future<void> _tiFtanei(WidgetTester tester, {required String name, required Size size, required Brightness brightness}) async {
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = size * 2.0;
  addTearDown(tester.view.reset);
  const channel = MethodChannel('ygeia/samsung');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Map<String, dynamic> src(String device, int n, {bool? counts}) =>
      {'app': 'com.sec.android.app.shealth', 'device': device, 'count': n, if (counts != null) 'counts': counts};
  final all = {
    'ok': true,
    'readAt': '2026-11-14T10:20:00',
    'days': 30,
    'today': {
      'stepsByDay': [
        for (var i = 0; i < 7; i++) {'date': dateKey(DateTime(2026, 11, 14 - i)), 'value': i == 0 ? 1965 : 5200 + 731 * i},
      ],
      'totalCalories': 1843.6,
      'activeCalories': 312.4,
    },
    'types': [
      {'key': 'sleep', 'state': 'ok', 'count': 34, 'latest': '2026-11-14T08:40:00', 'sources': [src('Galaxy Watch Ultra 2', 34)], 'fields': [
        {'name': 'duration', 'value': '347', 'seen': true},
        {'name': 'sessions', 'value': '2', 'seen': true},
      ]},
      {'key': 'heart_rate', 'state': 'ok', 'count': 5000, 'capped': true, 'latest': '2026-11-14T10:12:00', 'sources': [src('Galaxy Watch Ultra 2', 5000)]},
      {'key': 'body_composition', 'state': 'ok', 'count': 7, 'counted': 6, 'ignored': 1, 'latest': '2026-11-10T07:42:00', 'sources': [
        {'app': 'com.inbody2014.inbody', 'device': 'InBody H40', 'count': 6, 'counts': true},
        src('Galaxy Z Fold 8', 1, counts: false),
      ], 'fields': [
        {'name': 'weight', 'value': '82.4', 'seen': true},
        {'name': 'bodyFat', 'value': '21.3', 'seen': true},
        {'name': 'height', 'seen': false},
      ]},
      {'key': 'blood_oxygen', 'state': 'ok', 'count': 31, 'latest': '2026-11-14T08:40:00', 'sources': [src('Galaxy Watch Ultra 2', 31)]},
      {'key': 'skin_temperature', 'state': 'ok', 'count': 30, 'latest': '2026-11-14T08:40:00', 'sources': [src('Galaxy Watch Ultra 2', 30)]},
      {'key': 'blood_pressure', 'state': 'empty', 'days': 30},
      {'key': 'body_temperature', 'state': 'empty', 'days': 30},
      {'key': 'sleep_apnea', 'state': 'unsupported'},
      {'key': 'water_intake', 'state': 'no_permission'},
    ],
  };
  messenger.setMockMethodCallHandler(channel, (call) async => switch (call.method) {
        'status' || 'requestPermissions' => jsonEncode({'ok': true, 'granted': 17, 'total': 17}),
        'readAll' => jsonEncode(all),
        _ => jsonEncode({'ok': false, 'kind': 'other', 'message': call.method}),
      });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      // Έλεγχος 4: η γραμμή «νύχτες από άλλη συσκευή» στο στιγμιότυπο του κινητού.
      home: TiFtaneiScreen(otherDeviceNights: name.startsWith('140') ? 12 : 0),
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
          // Τρίτος έλεγχος (συνέπεια, εύρημα 0): ίδια τιμή και στη νύχτα του Dashboard, όπως στην εφαρμογή (η γραμμή της
          // μέρας = summarizeDay(dashboard)). Πριν, το στιγμιότυπο έδειχνε 63 εδώ και 61 στην Καρδιά.
          final n = store.data!.lastNight;
          if (n != null && dateKey(n.date) == dateKey(today)) {
            n.sleepingHr = row[K.sleepHr];
            n.skinTemp = row[K.skinTemp];
          }
        },
      ));
  testWidgets('Αναφορά για γιατρό', (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(680, 3200) * 2.0;
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
    tester.view.physicalSize = const Size(680, 3200) * 2.0;
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
  testWidgets('Αναφορά για γιατρό · με Oura (να χωράει η σελίδα 1 με τις 3 επιπλέον γραμμές)', (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(680, 3200) * 2.0;
    addTearDown(tester.view.reset);
    final store = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(ouraNow));
    store.history = sampleHistory(ouraNow, store.data!);
    prepareOura(store);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          home: ReportPage(store: store, now: ouraNow, note: 'Φάρμακα: ' * 16),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(find.byKey(key), matchesGoldenFile('shots/13c_report_oura.png'));
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
  testWidgets('Σελίδα μέτρησης · βάρος · κινητό', (t) => _shot(
        t,
        name: '40_metric_weight_phone',
        size: phone,
        brightness: Brightness.light,
        tab: Cat.health,
        sub: HealthTab.body,
        act: (t) async {
          await t.ensureVisible(find.byKey(const ValueKey('body-weight')));
          await t.tap(find.byKey(const ValueKey('body-weight')));
          await t.pumpAndSettle();
        },
      ));
  testWidgets('Σελίδα μέτρησης · HRV · Fold ανοιχτό · σκοτεινό', (t) => _shot(
        t,
        name: '41_metric_hrv_open_dark',
        size: open,
        brightness: Brightness.dark,
        tab: Cat.health,
        sub: HealthTab.recovery,
        at: ouraNow,
        oura: true,
        act: (t) async {
          await t.tap(find.byKey(const ValueKey('recovery-hrv')));
          await t.pumpAndSettle();
        },
      ));
  for (final (name, tab) in [('42_widget_config_content', 0), ('43_widget_config_look', 1)]) {
    testWidgets('Ρύθμιση widget · $name', (t) async {
      t.view.devicePixelRatio = 2.0;
      t.view.physicalSize = phone * 2.0;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      await t.pumpWidget(RepaintBoundary(
        key: key,
        child: const WidgetConfigApp(bridge: _NoRender(), initial: WidgetTarget(id: 5, kind: 'sleep', width: 92, height: 300)),
      ));
      await t.pumpAndSettle();
      if (tab == 1) {
        await t.tap(find.text('Εμφάνιση'));
        await t.pumpAndSettle();
      }
      await expectLater(find.byKey(key), matchesGoldenFile('shots/$name.png'));
    });
  }
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
        prepare: (s) {
          s.debugSetPlan(SourcePlan([SourceEra(Source.none, ouraStart)]), state: PlanState.unknown);
          s.debugSetRecovery(evidence: true);
        },
      ));
  testWidgets('Πηγές · άγνωστο σχέδιο · επιβεβαίωση χρονογραμμής', (t) => _page(
        t,
        name: '85_sources_plan_confirm',
        size: fold,
        brightness: Brightness.light,
        page: (s) => SourcesPage(store: s, now: ouraNow),
        prepare: (s) {
          s.debugSetPlan(SourcePlan([SourceEra(Source.none, ouraStart)]), state: PlanState.unknown);
          s.debugSetRecovery(evidence: true);
        },
        act: (t) async {
          await t.tap(find.textContaining('Κράτα: '));
        },
      ));
  testWidgets('Πηγές · άγνωστο σχέδιο · ιστορικό όχι ακόμα', (t) => _page(
        t,
        name: '86_sources_plan_retry',
        size: phone,
        brightness: Brightness.dark,
        page: (s) => SourcesPage(store: s, now: ouraNow),
        prepare: (s) {
          s.debugSetPlan(SourcePlan([SourceEra(Source.none, ouraStart)]), state: PlanState.unknown);
          s.debugSetRecovery(historyLoaded: false, evidence: true);
        },
      ));
  testWidgets('Oura · Σήμερα · η νύχτα που κοιμάσαι τώρα', (t) => _shot(
        t,
        name: '87_oura_today_starting_now',
        size: phone,
        brightness: Brightness.light,
        tab: 0,
        at: ouraNow,
        prepare: (s) {
          s.debugSetPlan(SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 14)));
          s.ouraHasTokens = true;
          s.ouraClock = () => ouraNow;
          s.ouraConnectedMs = DateTime(2026, 11, 14, 0, 40).millisecondsSinceEpoch;
        },
      ));
  testWidgets('Oura · Ύπνος · σύντομη νύχτα σε δύο κομμάτια', (t) => _shot(
        t,
        name: '88_oura_sleep_short',
        size: fold,
        brightness: Brightness.light,
        tab: Cat.health,
        sub: HealthTab.sleep,
        at: ouraNow,
        oura: true,
        prepare: (s) {
          String iso(DateTime t) => t.toUtc().toIso8601String();
          Map<String, dynamic> rec(String id, DateTime a, DateTime b) => {
                'id': id,
                'day': '2026-11-14',
                'type': 'sleep',
                'bedtime_start': iso(a),
                'bedtime_end': iso(b),
                'time_in_bed': b.difference(a).inSeconds,
                'total_sleep_duration': b.difference(a).inSeconds - 600,
                'latency': 420,
                'sleep_phase_5_min': '42221112223332221112',
              };
          final short = parseOura(sleep: [
            rec('a', DateTime(2026, 11, 13, 23, 0), DateTime(2026, 11, 14, 1, 30)),
            rec('b', DateTime(2026, 11, 14, 3, 0), DateTime(2026, 11, 14, 5, 45)),
          ], dailySleep: const [], readiness: const [])
              .nights
              .single;
          s.ouraNights = [for (final n in s.ouraNights) if (dateKey(n.day) != '2026-11-14') n, short];
        },
      ));
  testWidgets('Σύνδεση Oura · 04:00–23:59 · ερώτηση για την τελευταία νύχτα', (t) => _page(
        t,
        name: '89_oura_connect_question',
        size: fold,
        brightness: Brightness.light,
        oura: false,
        page: (s) => OuraConnectPage(store: s, now: ouraNow),
        prepare: (s) {
          s.ouraLink = OuraLink(vault: MemoryVault(), clientId: 'SCREENSHOT');
          s.ouraClock = () => ouraNow;
        },
        act: (t) async {
          await t.tap(find.byKey(const ValueKey('oura-connect')));
        },
      ));
  // release-fix2: μέρα με μόνο υπνάκο (15:00–21:00, καμία νύχτα) στη λίστα του Ύπνου.
  testWidgets('Ύπνος · μέρα με μόνο υπνάκο', (t) => _page(
        t,
        name: '07b_sleep_nap_only_phone_light',
        size: const Size(400, 3600),
        brightness: Brightness.light,
        oura: false,
        page: (s) => SleepPage(store: s, now: ouraNow),
        prepare: (s) {
          final day = DateTime(ouraNow.year, ouraNow.month, ouraNow.day - 1);
          int ms(DateTime x) => x.millisecondsSinceEpoch;
          final a = DateTime(day.year, day.month, day.day, 15);
          final b = DateTime(day.year, day.month, day.day, 21);
          final j = sampleDashboardJson(ouraNow);
          j['sleep'] = [
            for (final r in j['sleep'] as List)
              if (!sameDay(DateTime.fromMillisecondsSinceEpoch((r as Map)['end'] as int), day)) r,
            {
              'start': ms(a),
              'end': ms(b),
              'minutes': 360,
              'stages': [
                ['LIGHT', ms(a), ms(a.add(const Duration(minutes: 340)))],
                ['AWAKE', ms(a.add(const Duration(minutes: 340))), ms(b)],
              ],
            },
          ];
          s.data = Dashboard.fromJson(j);
          s.history = sampleHistory(ouraNow, s.data!);
        },
      ));
  testWidgets('Σύνδεση Oura · 20:30 · η ερώτηση και το βράδυ (απόφαση 4/11)', (t) => _page(
        t,
        name: '89b_oura_connect_question_evening',
        size: fold,
        brightness: Brightness.light,
        oura: false,
        page: (s) => OuraConnectPage(store: s, now: DateTime(2026, 11, 14, 20, 30)),
        prepare: (s) {
          s.ouraLink = OuraLink(vault: MemoryVault(), clientId: 'SCREENSHOT');
          s.ouraClock = () => DateTime(2026, 11, 14, 20, 30);
        },
        act: (t) async {
          await t.tap(find.byKey(const ValueKey('oura-connect')));
        },
      ));
  testWidgets('Oura · διαχείριση · μέρα σύνδεσης (η τελευταία νύχτα από το ρολόι)', (t) => _page(
        t,
        name: '90_oura_manage_first_day',
        size: fold,
        brightness: Brightness.light,
        page: (s) => OuraManagePage(store: s, now: ouraNow),
        prepare: (s) {
          s.debugSetPlan(SourcePlan.samsungOnly.withEra(Source.oura, DateTime(2026, 11, 14)));
          s.ouraNights = [for (final n in s.ouraNights) if (dateKey(n.day) != '2026-11-14') n];
          s.ouraConnectedMs = DateTime(2026, 11, 14, 9, 5).millisecondsSinceEpoch;
        },
      ));
  testWidgets('Oura · Σήμερα · η σύνδεση έμεινε μισή', (t) => _shot(
        t,
        name: '91_oura_today_incomplete',
        size: phone,
        brightness: Brightness.dark,
        tab: 0,
        at: ouraNow,
        prepare: (s) {
          s.ouraLink = OuraLink(vault: MemoryVault(), clientId: 'SCREENSHOT');
          s.ouraClock = () => ouraNow;
          s.ouraIncomplete = true;
        },
      ));
  // Συγχώνευση 4/11 (κοινός κανόνας με το ρολόι): «μόνο υπνάκος» = λαγοκοίμισμα που τελειώνει ως τις 22:00 χωρίς νύχτα.
  // Ύπνος που τελειώνει μετά τις 22:00 (π.χ. 21:30–23:50) είναι πλέον η νύχτα, όπως στο ρολόι.
  testWidgets('Oura · Σήμερα · μόνο υπνάκος (λαγοκοίμισμα ως τις 22:00, χωρίς νύχτα)', (t) => _shot(
        t,
        name: '92_oura_today_only_nap',
        size: phone,
        brightness: Brightness.light,
        tab: 0,
        at: DateTime(2026, 11, 14, 14),
        oura: true,
        prepare: (s) {
          final a = DateTime(2026, 11, 13, 20, 0);
          final b = DateTime(2026, 11, 13, 21, 40);
          final nap = parseOura(sleep: [
            {
              'id': 'nap',
              'day': '2026-11-14',
              'type': 'sleep',
              'bedtime_start': a.toUtc().toIso8601String(),
              'bedtime_end': b.toUtc().toIso8601String(),
              'time_in_bed': b.difference(a).inSeconds,
              'total_sleep_duration': b.difference(a).inSeconds - 300,
            },
          ], dailySleep: const [], readiness: const [])
              .nights
              .single;
          s.ouraNights = [for (final n in s.ouraNights) if (dateKey(n.day) != '2026-11-14') n, nap];
          s.history[dateKey(DateTime(2026, 11, 14))]?.removeWhere((k, _) => k.startsWith('o.'));
        },
      ));
  // Δεύτερος έλεγχος UX (U1, D13): tablet οριζόντια (1280×800) και παράθυρο PC (1600×1000), φωτεινό και σκοτεινό,
  // και το «Τι φτάνει» (400 και 860), που δεν είχε κανένα στιγμιότυπο.
  const tablet = Size(1280, 800);
  const pc = Size(1600, 1000);
  for (final (n, size, b, tag) in [
    (100, tablet, Brightness.light, 'tablet_light'),
    (110, tablet, Brightness.dark, 'tablet_dark'),
    (120, pc, Brightness.light, 'pc_light'),
    (130, pc, Brightness.dark, 'pc_dark'),
  ]) {
    testWidgets('Μεγάλη οθόνη · Σήμερα · $tag', (t) => _shot(t, name: '${n}_today_$tag', size: size, brightness: b, tab: 0));
    testWidgets('Μεγάλη οθόνη · Διατροφή · $tag', (t) => _shot(t, name: '${n + 1}_nutrition_$tag', size: size, brightness: b, tab: Cat.food));
    testWidgets('Μεγάλη οθόνη · Ύπνος · $tag',
        (t) => _shot(t, name: '${n + 2}_sleep_$tag', size: size, brightness: b, tab: Cat.health, sub: HealthTab.sleep));
    testWidgets('Μεγάλη οθόνη · Καρδιά · $tag',
        (t) => _shot(t, name: '${n + 3}_heart_$tag', size: size, brightness: b, tab: Cat.health, sub: HealthTab.heart));
    testWidgets('Μεγάλη οθόνη · Σύγκριση · $tag',
        (t) => _page(t, name: '${n + 4}_compare_$tag', size: size, brightness: b, page: (s) => ComparePage(store: s, now: ouraNow)));
    testWidgets('Μεγάλη οθόνη · Πηγές · $tag',
        (t) => _page(t, name: '${n + 5}_sources_$tag', size: size, brightness: b, page: (s) => SourcesPage(store: s, now: ouraNow)));
    testWidgets('Μεγάλη οθόνη · Αναφορά · $tag', (t) => _page(
          t,
          name: '${n + 6}_report_$tag',
          size: size,
          brightness: b,
          page: (s) => ReportPage(store: s, now: ouraNow),
        ));
    testWidgets('Μεγάλη οθόνη · Oura Σήμερα · $tag',
        (t) => _shot(t, name: '${n + 7}_oura_today_$tag', size: size, brightness: b, tab: 0, at: ouraNow, oura: true));
  }
  testWidgets('Τι φτάνει · κινητό', (t) => _tiFtanei(t, name: '140_ti_ftanei_400', size: const Size(400, 2600), brightness: Brightness.light));
  testWidgets('Τι φτάνει · Fold ανοιχτό · σκοτεινό',
      (t) => _tiFtanei(t, name: '141_ti_ftanei_860_dark', size: const Size(860, 1800), brightness: Brightness.dark));
  testWidgets('Τι φτάνει · μικρό κινητό 360', (t) => _tiFtanei(t, name: '142_ti_ftanei_360', size: const Size(360, 2600), brightness: Brightness.light));
  // Δεύτερος γύρος (D1/D4): αναφορά με Oura, όνομα και σημείωση 400 χαρακτήρων· η σελίδα 1 πρέπει να χωράει τις δύο
  // γραμμές οξυγόνου (μία ανά ορισμό της νύχτας) χωρίς υπερχείλιση.
  testWidgets('Αναφορά για γιατρό · Oura + όνομα + σημείωση 400 χαρακτήρων', (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(680, 3600) * 2.0;
    addTearDown(tester.view.reset);
    final store = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(ouraNow));
    store.history = sampleHistory(ouraNow, store.data!);
    prepareOura(store);
    store.prefs.reportName = 'Γιάννης Παπαδόπουλος';
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          home: ReportPage(
            store: store,
            now: ouraNow,
            note: ('Φάρμακα: βισοπρολόλη 2,5 mg πρωί. Κάπνισμα 10/μέρα. Ροχαλητό (σύζυγος). Τεστ άπνοιας Samsung 20/10 '
                    'και 23/10 αρνητικά. Ζαλάδα το πρωί κάποιες μέρες. ' * 3)
                .substring(0, 400),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    _expectWholeNote(tester);
    await expectLater(find.byKey(key), matchesGoldenFile('shots/13d_report_oura_note400.png'));
  });
  // Συγχώνευση 3: χειρότερη περίπτωση, 400 φαρδιοί χαρακτήρες με αλλαγές γραμμής, Oura και όνομα: η σημείωση
  // ολόκληρη και η σελίδα 1 χωρίς υπερχείλιση (μικραίνει λίγο αν χρειαστεί, δεν κόβεται).
  testWidgets('Αναφορά για γιατρό · Oura + όνομα + σημείωση 400 φαρδιών χαρακτήρων με αλλαγές γραμμής', (tester) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(680, 3600) * 2.0;
    addTearDown(tester.view.reset);
    final store = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(ouraNow));
    store.history = sampleHistory(ouraNow, store.data!);
    prepareOura(store);
    store.prefs.reportName = 'Γιάννης Παπαδόπουλος';
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          home: ReportPage(
            store: store,
            now: ouraNow,
            note: List.generate(40, (i) => i.isEven ? 'ΩΜΩΜΩΜΩΜΩ\n' : 'ΜΩΜΩΜΩΜΩΜ ').join(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    _expectWholeNote(tester);
    await expectLater(find.byKey(key), matchesGoldenFile('shots/13e_report_oura_note400_wide.png'));
  });
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

/// Η προεπισκόπηση τη ζωγραφίζει η Kotlin· στα τεστ Flutter δεν υπάρχει (τη δείχνει ο έλεγχος στο emulator).
class _NoRender extends WidgetConfigBridge {
  const _NoRender();

  @override
  Future<Uint8List?> render(WidgetStyle style, double w, double h, {required bool dark}) async => null;
}
