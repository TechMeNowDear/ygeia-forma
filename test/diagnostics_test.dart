// «Αναφορά για έλεγχο» (12/11). Φανταστικά δεδομένα (δημόσιο repo).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/diagnostics.dart';
import 'package:ygeia_forma/error_report.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/pages/diagnostics_sheet.dart';
import 'package:ygeia_forma/profile.dart';
import 'package:ygeia_forma/theme.dart';

import 'sample_checkin.dart';
import 'sample_data.dart';
import 'sample_food.dart';

final _at = DateTime(2026, 12, 7, 8, 20);
const _me = Profile(birthYear: 1986, birthMonth: 1, sex: 'm', heightCm: 180);

HealthStore _store({List<(DateTime, double)>? weights}) {
  final s = HealthStore()
    ..data = Dashboard.fromJson({...sampleDashboardJson(_at), 'body': bodyJson(weights ?? simWeights(_at))});
  s
    ..history = sampleHistory(_at, s.data!)
    ..setProfile(_me)
    ..setGoals(checkinGoals());
  return s;
}

void main() {
  test('περιέχει δεδομένα, υπολογισμούς και ελέγχους· γράφεται σε JSON', () {
    final rep = ErrorReporter()..recentErrors.add({'type': 'StateError', 'message': 'δοκιμή'});
    final r = diagnosticsFrom(store: _store(), food: checkinFood(_at), now: _at, note: 'δοκιμή', reporter: rep);
    final text = jsonEncode(r);
    expect(text.toLowerCase().contains('token'), isFalse);
    final calc = r['calc'] as Map;
    expect((calc['goals'] as Map)['inForce'], containsPair('kcal', 2250));
    expect(((calc['adaptive'] as Map)['pending'] as Map)['kind'], 'proposal');
    expect(((calc['adaptive'] as Map)['probe'] as Map)['status'], 'ok');
    expect((calc['days'] as List).length, 22, reason: '21 μέρες + σήμερα');
    expect((calc['zone'] as Map)['age'], 40);
    expect(calc['chol'], isNotNull);
    final checks = {for (final c in r['checks'] as List) (c as Map)['id']: c['ok']};
    expect(checks['food-grams'], isTrue);
    expect(checks['food-duplicates'], isTrue);
    expect(checks['weight-jumps'], isTrue);
    expect((r['data'] as Map)['foodLogSource'], 'memory-60d');
    expect(((r['data'] as Map)['foodLog'] as List).length, 64);
    expect(r['note'], 'δοκιμή');
    expect((r['errors'] as List).single['type'], 'StateError');
  });

  test('έλεγχοι: άλμα βάρους, 0 g, διπλή καταχώριση', () {
    final w = simWeights(_at);
    final jumped = [...w.take(w.length - 1), (w.last.$1, w.last.$2 + 4)];
    final day = DateTime(2026, 12, 6, 13);
    final bread = foodNamed('Ψωμί ολικής άλεσης');
    final food = FoodStore.preloaded(foods: basicFoods(), now: _at, entries: [
      LogEntry(id: 'a', day: dateKey(day), meal: Meal.lunch, food: bread, grams: 0, time: day),
      LogEntry(id: 'b', day: dateKey(day), meal: Meal.lunch, food: bread, grams: 60, time: day),
      LogEntry(id: 'c', day: dateKey(day), meal: Meal.lunch, food: bread, grams: 60, time: day),
    ]);
    final r = diagnosticsFrom(store: _store(weights: jumped), food: food, now: _at);
    final checks = {for (final c in r['checks'] as List) (c as Map)['id']: c['ok']};
    expect((checks['weight-jumps'], checks['food-grams'], checks['food-duplicates']), (false, false, false));
  });

  test('η αναφορά σφαλμάτων κρατά τα τελευταία και με κλειστή την αποστολή', () async {
    final rep = ErrorReporter()..sending.value = false;
    for (var i = 0; i < ErrorReporter.recentMax + 5; i++) {
      await rep.report(StateError('σφάλμα $i'), StackTrace.current);
    }
    expect(rep.recentErrors.length, ErrorReporter.recentMax);
    expect(rep.recentErrors.last['message'], contains('σφάλμα ${ErrorReporter.recentMax + 4}'));
  });

  testWidgets('φύλλο: σημείωση, αρχείο, αποτέλεσμα', (t) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(400, 1600);
    addTearDown(t.view.reset);
    String? saved;
    String? name;
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: DiagnosticsSheet(
          store: _store(),
          food: checkinFood(_at),
          save: (json, n) async {
            saved = json;
            name = n;
            return {'ok': true, 'uri': 'content://x', 'name': n};
          },
        ),
      ),
    ));
    await t.enterText(find.byKey(const ValueKey('diag-note')), 'Το μεσημεριανό λείπει');
    await t.tap(find.byKey(const ValueKey('diag-make')));
    await t.pumpAndSettle();
    expect(name, startsWith('ygeia-elegxos-'));
    expect(name, endsWith('.json.gz'));
    expect((jsonDecode(saved!) as Map)['note'], 'Το μεσημεριανό λείπει');
    expect(find.byKey(const ValueKey('diag-result')), findsOneWidget);
  });
}
