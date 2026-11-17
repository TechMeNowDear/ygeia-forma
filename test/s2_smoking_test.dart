// Αποφάσεις χρήστη 17/11, βήμα 2: κάπνισμα στα «Τα στοιχεία μου». Φανταστικό προφίλ (1985/12, άνδρας, 180 cm).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/pages/me_page.dart';
import 'package:ygeia_forma/profile.dart';
import 'package:ygeia_forma/theme.dart';

const _me = Profile(birthYear: 1985, birthMonth: 12, sex: 'm', heightCm: 180);
final _now = DateTime(2026, 11, 17, 10);

void main() {
  group('Profile', () {
    test('πακέτα-έτη: ως σήμερα όσο καπνίζεις, ως τη μέρα που το έκοψες μετά', () {
      final now = _me.withSmoking(smoke: 'now', cigs: 20, smokeFrom: 18);
      expect(now.packYears(DateTime(2026, 11, 17)), closeTo(22, 1e-9)); // 40 − 18 = 22 χρόνια × 1 πακέτο
      final ex = _me.withSmoking(smoke: 'ex', cigs: 10, smokeFrom: 20, quit: '2020-06-01');
      expect(ex.packYears(DateTime(2026, 11, 17)), closeTo(7, 1e-9)); // 34 − 20 = 14 × 0,5
      expect(ex.quitDate, DateTime(2020, 6, 1));
      expect(_me.withSmoking(smoke: 'now', cigs: 20).packYears(DateTime(2026, 11, 17)), isNull, reason: 'λείπει η ηλικία έναρξης');
    });

    test('«Όχι» σβήνει τα υπόλοιπα· η μέρα μόνο με «Το έκοψα»', () {
      final no = _me.withSmoking(smoke: 'no', cigs: 20, smokeFrom: 18, quit: '2026-11-23');
      expect((no.cigs, no.smokeFrom, no.quit, no.quitDate), (null, null, null, null));
      final now = _me.withSmoking(smoke: 'now', cigs: 20, smokeFrom: 18, quit: '2026-11-23');
      expect((now.quit, now.quitDate), (null, null));
    });

    test('JSON: πάει και έρχεται· άκυρες τιμές πετιούνται· τα άλλα πεδία μένουν', () {
      final p = _me.withSmoking(smoke: 'ex', cigs: 15, smokeFrom: 19, quit: '2026-11-23');
      final back = Profile.fromJson(p.toJson());
      expect((back.smoke, back.cigs, back.smokeFrom, back.quit, back.heightCm), ('ex', 15, 19, '2026-11-23', 180.0));
      final bad = Profile.fromJson({...p.toJson(), 'smk': 'x', 'cig': 500, 'smf': 2, 'quit': '23/11/2026'});
      expect((bad.smoke, bad.cigs, bad.smokeFrom, bad.quit), (null, null, null, null));
      expect(_me.copyWith(heightCm: 181).toJson().containsKey('smk'), isFalse);
      expect(p.copyWith(heightCm: 181).cigs, 15, reason: 'το copyWith δεν σβήνει το κάπνισμα');
    });
  });

  testWidgets('«Τα στοιχεία μου»: καπνίζω → πακέτα-έτη· «Το έκοψα» → σήμερα, και ο έλεγχος δεν κατεβάζει θερμίδες', (t) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(400, 2600);
    addTearDown(t.view.reset);
    final store = HealthStore()..setProfile(_me);
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: MePage(store: store, now: _now)));
    await t.pumpAndSettle();
    expect(find.text('Χρειάζεται για τον κίνδυνο της καρδιάς στις εξετάσεις.'), findsOneWidget);
    await t.tap(find.text('Καπνίζω'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('me-cigs')), '20');
    await t.enterText(find.byKey(const ValueKey('me-smoke-from')), '18');
    await t.pumpAndSettle();
    expect(store.profile.smoke, 'now');
    expect(find.textContaining('Πακέτα-έτη: 22 '), findsOneWidget);
    await t.tap(find.text('Το έκοψα').first);
    await t.pumpAndSettle();
    expect(store.profile.quit, '2026-11-17');
    expect((store.profile.cigs, store.profile.smokeFrom), (20, 18));
    expect(find.text('Το έκοψα στις 17 Νοε 2026'), findsOneWidget);
    expect(find.byKey(const ValueKey('me-quit-hold')), findsOneWidget);
    expect(find.textContaining('Πακέτα-έτη: 22 '), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
