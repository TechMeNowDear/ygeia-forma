import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/home_widgets/widget_snapshot.dart';
import 'package:ygeia_forma/home_widgets/widget_style.dart';

import 'sample_data.dart';
import 'sample_food.dart';

void main() {
  test('WidgetStyle: JSON πάει και έρχεται· άγνωστα κλειδιά και τιμές εκτός ορίων αγνοούνται', () {
    final s = WidgetStyle(kind: WKind.body)
      ..hero = 'fatPct'
      ..values = ['weight', 'smm']
      ..valueColors = {'smm': 0xFF7DDB9C}
      ..opacity = 40
      ..gradient = false
      ..textColor = 0xFFFFFFFF;
    final back = WidgetStyle.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(back.toJson(), s.toJson());

    final bad = WidgetStyle.fromJson({
      'kind': 'sleep',
      'hero': 'weight', // όχι του Ύπνου
      'values': ['hrv', 'xyz', 3],
      'op': 400,
      'rad': -5,
      'tap': 'add', // μόνο για το Φαγητό
    });
    expect(bad.hero, 'sleepMin');
    expect(bad.values, ['hrv']);
    expect(bad.opacity, 100);
    expect(bad.radius, 0);
    expect(bad.tap, WTap.section);
    expect(WidgetStyle(kind: WKind.food).tap, WTap.add);
  });

  test('Προεπιλογή «Μπορντό» (απόφαση 7/11)', () {
    final s = WidgetStyle(kind: WKind.sleep);
    expect(s.theme, 'bordeaux');
    expect(s.c1, wThemes.first.c1);
    expect(wThemes.first.name, 'Μπορντό');
  });

  test('Στιγμιότυπο: κάθε είδος με τιμές από το δείγμα, κείμενα όπως στις οθόνες', () {
    final now = DateTime(2026, 11, 7, 10, 20);
    final store = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(now));
    store.history = sampleHistory(now, store.data!);
    final snap = buildWidgetSnapshot(store, sampleFoodStore(now), now);
    final kinds = snap['kinds'] as Map<String, dynamic>;
    expect(kinds.keys, containsAll(WKind.all));
    for (final k in WKind.all) {
      final m = (kinds[k] as Map)['m'] as Map;
      expect(m, isNotEmpty, reason: k);
      for (final e in m.values) {
        expect((e as Map)['v'], isA<String>());
        expect(e['l'], isA<String>());
        if (e['s'] != null) expect((e['s'] as List).length, 7);
      }
    }
    // Ο ύπνος: «ώρες:λεπτά».
    final sleep = ((kinds[WKind.sleep] as Map)['m'] as Map)['sleepMin'] as Map;
    expect(sleep['v'], matches(RegExp(r'^\d+:\d\d$')));
    // Έλεγχος 8/11 (DATA-03/04): ύπνος 419,5′ = 7:00· θερμοκρασία ποτέ «+33,6°».
    final temp = ((kinds[WKind.sleep] as Map)['m'] as Map)['skinTemp'] as Map?;
    if (temp != null) expect(double.parse((temp['v'] as String).replaceAll(RegExp(r'[^0-9,]'), '').replaceAll(',', '.')), lessThan(10));
    // Έλεγχος 8/11 (DATA-02): κίνηση και φαγητό λένε για ποια μέρα είναι (άλλη μέρα → «—» στο widget).
    expect((kinds[WKind.move] as Map)['day'], '2026-11-07');
    expect((kinds[WKind.food] as Map)['day'], '2026-11-07');
    // Το JSON βγαίνει (το διαβάζει η Kotlin).
    expect(() => jsonEncode(snap), returnsNormally);
  });
}
