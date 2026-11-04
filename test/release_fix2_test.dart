// release-fix2: μέρα με μόνο υπνάκο (καμία νύχτα) φαίνεται στη λίστα του Ύπνου ως «Μόνο υπνάκος», με ώρες και σύνολο,
// χωρίς να μετρά σε κανένα στατιστικό νύχτας. Ρολόι και Oura.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/oura/oura_model.dart';
import 'package:ygeia_forma/pages/sleep.dart';
import 'package:ygeia_forma/report.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/widgets.dart';

import 'sample_data.dart';

int ms(DateTime t) => t.millisecondsSinceEpoch;

/// Το δείγμα, με τη νύχτα της μέρας [day] αφαιρεμένη και στη θέση της ένας υπνάκος 15:00–21:00 (340′ ύπνος).
Map<String, dynamic> napOnlyJson(DateTime now, DateTime day) {
  final j = sampleDashboardJson(now);
  final a = DateTime(day.year, day.month, day.day, 15);
  final b = DateTime(day.year, day.month, day.day, 21);
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
  return j;
}

void main() {
  final now = DateTime(2026, 10, 24, 16, 30);
  final today = dayOf(now);
  final day = DateTime(today.year, today.month, today.day - 3);

  group('Μόνο υπνάκος: ρολόι', () {
    test('Ο υπνάκος μιας μέρας χωρίς νύχτα: napMin στο ιστορικό, οι ώρες στη Samsung ανάγνωση, κανένα στατιστικό νύχτας', () {
      final d = Dashboard.fromJson(napOnlyJson(now, day));
      expect(d.nights.any((n) => sameDay(n.date, day)), isFalse);
      expect(d.napTimes[day], [(DateTime(day.year, day.month, day.day, 15), DateTime(day.year, day.month, day.day, 21), 340)]);
      final row = summarizeDay(d, day);
      expect(row[K.napMin], 340, reason: 'αποθηκεύεται ήδη (C1), και μέρα χωρίς νύχτα');
      expect(row.containsKey(K.sleepMin), isFalse);
      expect(row.containsKey(K.bedtime), isFalse);
      expect(row.containsKey(K.sleepHr), isFalse);
      expect(row.containsKey(K.spo2Min), isFalse);
      final h = sampleHistory(now, d);
      expect(buildReport(h, now).stat(K.sleepMin).values.any((v) => sameDay(v.$1, day)), isFalse, reason: 'ούτε στο PDF');
      expect(napOnlyText(d.napTimes[day]!), 'Υπνάκος 15:00–21:00 · 5 ώρες 40 λεπτά');
      expect(
        napOnlyText([
          (DateTime(2026, 1, 1, 13), DateTime(2026, 1, 1, 14), 55),
          (DateTime(2026, 1, 1, 16), DateTime(2026, 1, 1, 17, 30), 80),
        ]),
        'Υπνάκοι 13:00–14:00, 16:00–17:30 · 2 ώρες 15 λεπτά',
      );
    });

    testWidgets('Λίστα «Νύχτα προς νύχτα»: γραμμή «Μόνο υπνάκος» με ώρες και σύνολο· κενή στήλη στο γράφημα· ποτέ «χωρίς ύπνο»',
        (t) async {
      final s = HealthStore()..data = Dashboard.fromJson(napOnlyJson(now, day));
      s.history = sampleHistory(now, s.data!);
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(400, 6000);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: SleepPage(store: s, now: now)));
      await t.pumpAndSettle();
      final row = find.byKey(ValueKey('nap-only-${day.year}-${day.month}-${day.day}'));
      expect(row, findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('Υπνάκος 15:00–21:00 · 5 ώρες 40 λεπτά')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('Μόνο υπνάκος')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.textContaining('σκορ')), findsNothing);
      expect(find.textContaining('χωρίς ύπνο'), findsNothing);
      expect(find.textContaining('Χωρίς ύπνο'), findsNothing);
      final bars = t.widget<BarChart>(find.byType(BarChart));
      expect(bars.values.length, 15, reason: '14 νύχτες και η μέρα με μόνο υπνάκο');
      expect(bars.labels.length, 15);
      // Ο μέσος όρος 7 νυχτών μόνο από νύχτες (ο υπνάκος δεν μετρά).
      final week = s.data!.nights.where((n) => n.date.isAfter(DateTime(today.year, today.month, today.day - 7)) && n.staged);
      final avg = week.map((n) => n.minutes).reduce((a, b) => a + b) / week.length;
      expect(bars.average, closeTo(avg / 60, 1e-9));
    });
  });

  group('Μόνο υπνάκος: Oura', () {
    testWidgets('Μέρα του Oura με μόνο υπνάκο: «Υπνάκος 15:00–21:00 · 5 ώρες 40 λεπτά» και «Μόνο υπνάκος»', (t) async {
      final ouraFrom = DateTime(today.year, today.month, today.day - 6);
      final s = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(now));
      s.history = sampleHistory(now, s.data!);
      s.debugSetPlan(SourcePlan.samsungOnly.withEra(Source.oura, ouraFrom));
      String iso(DateTime x) => x.toUtc().toIso8601String();
      final a = DateTime(day.year, day.month, day.day, 15);
      final b = DateTime(day.year, day.month, day.day, 21);
      s.ouraNights = parseOura(
        sleep: [
          {
            'id': 'nap',
            'day': dateKey(day),
            'type': 'sleep',
            'bedtime_start': iso(a),
            'bedtime_end': iso(b),
            'total_sleep_duration': 340 * 60,
          },
          {
            'id': 'night',
            'day': dateKey(today),
            'type': 'long_sleep',
            'bedtime_start': iso(DateTime(today.year, today.month, today.day - 1, 23)),
            'bedtime_end': iso(DateTime(today.year, today.month, today.day, 7)),
            'total_sleep_duration': 450 * 60,
          },
        ],
        dailySleep: const [],
        readiness: const [],
      ).nights;
      s.ouraHasTokens = true;
      s.ouraClock = () => now;
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(400, 6000);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: SleepPage(store: s, now: now)));
      await t.pumpAndSettle();
      expect(find.text('Υπνάκος 15:00–21:00 · 5 ώρες 40 λεπτά'), findsOneWidget);
      expect(find.text('Μόνο υπνάκος'), findsOneWidget);
      expect(find.textContaining('χωρίς ύπνο'), findsNothing);
    });
  });
}
