// Στόχοι, χοληστερίνη, ζώνη περπατήματος, μέση (12/11). Όλοι οι αριθμοί εδώ είναι φανταστικοί (δημόσιο repo).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/backup.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/food/chol.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/goals.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/pages/goals_page.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/main.dart';
import 'package:ygeia_forma/nav.dart';
import 'package:ygeia_forma/pages/waist_sheet.dart';
import 'package:ygeia_forma/profile.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/zone.dart';
import 'package:ygeia_forma/waist.dart';

import 'sample_data.dart';
import 'sample_food.dart';

final _now = DateTime(2026, 11, 12, 10);

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 2400), double textScale = 1.0}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.light),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: w,
  ));
  await t.pumpAndSettle();
}

/// Η Διατροφή όπως στην εφαρμογή (μέσα στο Shell, με την κεφαλίδα της κατηγορίας).
Widget _shell(HealthStore store) {
  store
    ..data ??= Dashboard.fromJson(sampleDashboardJson(_now))
    ..history = sampleHistory(_now, store.data!);
  addTearDown(() => FoodStore.shared = null);
  return Shell(store: store, food: sampleFoodStore(_now), initialIndex: Cat.food, now: _now);
}

/// Φανταστικός χρήστης: άνδρας 40 ετών, 180 cm.
const _me = Profile(birthYear: 1985, birthMonth: 12, sex: 'm', heightCm: 180);

Goals _goals({bool doctor = true, int? kcalSet}) => Goals(
      aim: GoalAim.lose,
      rate: 0.005,
      activity: 1.5,
      doctor: doctor,
      since: '2026-11-12',
      kg: 90,
      age: 40,
      heightCm: 180,
      male: true,
      nutsG: 30,
      branG: 40,
      legumesWeek: 4,
      fishWeek: 6,
      kcalSet: kcalSet,
    );


void main() {
  testWidgets('DIAG 2x 360', (t) async {
    final store = HealthStore()..setProfile(_me)..setGoals(_goals());
    final old = FlutterError.onError;
    FlutterError.onError = (d) {
      // ignore: avoid_print
      print('DIAG-ERROR ${d.toString()}');
      final ctx = d.informationCollector?.call().map((x) => x.toString()).join('\n');
      // ignore: avoid_print
      print('DIAG-INFO $ctx');
    };
    await _pump(t, _shell(store), size: const Size(360, 5000), textScale: 2.0);
    FlutterError.onError = old;
  });
}
