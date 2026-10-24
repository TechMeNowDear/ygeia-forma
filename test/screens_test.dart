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
import 'package:ygeia_forma/theme.dart';

import 'sample_data.dart';

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
}) async {
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = size * 2.0;
  addTearDown(tester.view.reset);

  final store = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(now));
  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        home: Shell(store: store, initialIndex: tab, now: now),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await expectLater(find.byKey(key), matchesGoldenFile('shots/$name.png'));
}

void main() {
  setUpAll(_loadFonts);

  const phone = Size(400, 1900);
  const open = Size(860, 1500);

  testWidgets('Σήμερα · κινητό · ανοιχτό', (t) => _shot(t, name: '01_today_phone_light', size: phone, brightness: Brightness.light, tab: 0));
  testWidgets('Σήμερα · κινητό · σκοτεινό', (t) => _shot(t, name: '02_today_phone_dark', size: phone, brightness: Brightness.dark, tab: 0));
  testWidgets('Σήμερα · Fold ανοιχτό', (t) => _shot(t, name: '03_today_open_light', size: open, brightness: Brightness.light, tab: 0));
  testWidgets('Σήμερα · Fold ανοιχτό · σκοτεινό', (t) => _shot(t, name: '04_today_open_dark', size: open, brightness: Brightness.dark, tab: 0));
  testWidgets('Ύπνος · κινητό', (t) => _shot(t, name: '05_sleep_phone_light', size: phone, brightness: Brightness.light, tab: 1));
  testWidgets('Καρδιά · κινητό', (t) => _shot(t, name: '06_heart_phone_light', size: phone, brightness: Brightness.light, tab: 2));
  testWidgets('Σώμα · κινητό', (t) => _shot(t, name: '07_body_phone_light', size: phone, brightness: Brightness.light, tab: 3));
  testWidgets('Κίνηση · κινητό', (t) => _shot(t, name: '08_move_phone_light', size: phone, brightness: Brightness.light, tab: 4));
  testWidgets('Ύπνος · Fold ανοιχτό · σκοτεινό', (t) => _shot(t, name: '09_sleep_open_dark', size: open, brightness: Brightness.dark, tab: 1));
}
