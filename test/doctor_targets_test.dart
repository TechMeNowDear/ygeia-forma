// Στόχοι του γιατρού για τα λιπίδια (απόφαση 12/11: μένουν στη διατροφή). Φανταστικές τιμές (δημόσιο repo).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/goals.dart';
import 'package:ygeia_forma/pages/goals_page.dart';
import 'package:ygeia_forma/theme.dart';

import 'sample_checkin.dart';

void main() {
  test('αποθήκευση· κενό = δεν έδωσε· άκυρα (π.χ. mmol/L) πετιούνται', () {
    final g = checkinGoals().copyWith(docTargets: const DoctorTargets(ldlMax: 110, hdlMin: 45, tgMax: 140));
    final back = Goals.fromJson(g.toJson())!;
    expect((back.docTargets.ldlMax, back.docTargets.hdlMin, back.docTargets.tgMax), (110, 45, 140));
    expect(back.docTargets.text, 'LDL < 110 · HDL > 45 · Τριγλυκερίδια < 140');
    expect(Goals.fromJson({...g.toJson(), 'ldl': 3})!.docTargets.ldlMax, isNull, reason: '3 = mmol/L, όχι mg/dL');
    expect(checkinGoals().docTargets.isEmpty, isTrue);
    expect(checkinGoals().toJson().containsKey('ldl'), isFalse);
    expect(Goals.fromJson(g.toJson())!.doctor, isTrue, reason: 'το «doc» (οδηγία γιατρού) δεν μπερδεύεται με τους αριθμούς');
  });

  testWidgets('Στόχοι: «Στόχοι του γιατρού» γράφονται από τη σελίδα', (t) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(400, 2400);
    addTearDown(t.view.reset);
    final s = HealthStore()..setGoals(checkinGoals());
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: GoalsPage(store: s, now: DateTime(2026, 11, 20))));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('goals-doc-targets')));
    await t.tap(find.byKey(const ValueKey('goals-doc-targets')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('doc-ldl')), '110');
    await t.enterText(find.byKey(const ValueKey('doc-tg')), '9');
    await t.tap(find.byKey(const ValueKey('doc-ok')));
    await t.pumpAndSettle();
    expect(find.text('Από 50 ως 500 mg/dL.'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('doc-tg')), '140');
    await t.tap(find.byKey(const ValueKey('doc-ok')));
    await t.pumpAndSettle();
    expect((s.goals!.docTargets.ldlMax, s.goals!.docTargets.hdlMin, s.goals!.docTargets.tgMax), (110, null, 140));
    expect(find.text('LDL < 110 · Τριγλυκερίδια < 140'), findsOneWidget);
  });
}
