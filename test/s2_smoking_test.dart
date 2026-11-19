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

  test('Έλεγχος 19/11: μέρα διακοπής που δεν υπάρχει ή χωρίς «ex» δεν διαβάζεται· μελλοντική μετρά ως σήμερα (L-9/L-10)', () {
    final base = _me.withSmoking(smoke: 'ex', cigs: 10, smokeFrom: 20, quit: '2026-02-28').toJson();
    expect(Profile.fromJson({...base, 'quit': '2026-02-30'}).quit, isNull);
    expect(Profile.fromJson({...base, 'smk': 'now'}).quit, isNull);
    expect(Profile.fromJson({...base, 'smk': 'no'}).cigs, isNull);
    final future = Profile.fromJson({...base, 'quit': '2030-01-01'});
    expect(future.packYears(DateTime(2026, 11, 17)), closeTo(10 / 20 * (40 - 20), 1e-9));
  });

  test('Επαναφορά: το κάπνισμα του κινητού μένει ολόκληρο (L-9)', () {
    final mine = {'me': {'h': 180, 'smk': 'now'}};
    final backup = {'me': {'h': 175, 'by': 1985, 'smk': 'ex', 'cig': 10, 'smf': 20, 'quit': '2026-11-23'}};
    final m = mergePrefsForRestore(mine, backup)['me'] as Map;
    expect(m, {'h': 180, 'by': 1985, 'smk': 'now'});
    // Χωρίς απάντηση στο κινητό: έρχεται όλο από το αντίγραφο.
    final m2 = mergePrefsForRestore({'me': {'h': 180}}, backup)['me'] as Map;
    expect((m2['smk'], m2['quit'], m2['h']), ('ex', '2026-11-23', 180));
  });

  testWidgets('«Το έκοψα» χωρίς «Καπνίζω» πριν: ρωτά πότε· «Άκυρο» δεν αλλάζει τίποτα (L-1)· «Ποτέ» ρωτά (L-8)· κενό πεδίο σβήνει (L-7)', (t) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(400, 2600);
    addTearDown(t.view.reset);
    final store = HealthStore()..setProfile(_me);
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: MePage(store: store, now: _now)));
    await t.pumpAndSettle();
    await t.tap(find.text('Το έκοψα').first);
    await t.pumpAndSettle();
    expect(find.text('Πότε το έκοψες;'), findsOneWidget);
    await t.tap(find.text('Cancel').last); // το ημερολόγιο του Flutter, χωρίς ελληνικά στη δοκιμή
    await t.pumpAndSettle();
    expect((store.profile.smoke, store.profile.quit), (null, null));
    await t.tap(find.text('Το έκοψα').first);
    await t.pumpAndSettle();
    await t.tap(find.text('OK').last);
    await t.pumpAndSettle();
    expect((store.profile.smoke, store.profile.quit), ('ex', '2026-11-17'));
    await t.enterText(find.byKey(const ValueKey('me-cigs')), '20');
    await t.pumpAndSettle();
    expect(store.profile.cigs, 20);
    await t.enterText(find.byKey(const ValueKey('me-cigs')), '');
    await t.pumpAndSettle();
    expect(store.profile.cigs, isNull);
    await t.enterText(find.byKey(const ValueKey('me-cigs')), '100');
    await t.pumpAndSettle();
    expect(store.profile.cigs, isNull);
    expect(find.text('Από 1 ως 80'), findsOneWidget);
    await t.tap(find.text('Ποτέ'));
    await t.pumpAndSettle();
    expect(find.text('Δεν κάπνισες ποτέ;'), findsOneWidget);
    await t.tap(find.text('Άκυρο').last);
    await t.pumpAndSettle();
    expect(store.profile.smoke, 'ex');
    await t.tap(find.text('Ποτέ'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ναι, ποτέ'));
    await t.pumpAndSettle();
    expect((store.profile.smoke, store.profile.quit), ('no', null));
    expect(t.takeException(), isNull);
  });

  testWidgets('«Τα στοιχεία μου»: καπνίζω → πακέτα-έτη· «Το έκοψα» → σήμερα, και ο έλεγχος δεν κατεβάζει θερμίδες', (t) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(400, 2600);
    addTearDown(t.view.reset);
    final store = HealthStore()..setProfile(_me);
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: MePage(store: store, now: _now)));
    await t.pumpAndSettle();
    expect(find.textContaining('Για τον γιατρό (πακέτα-έτη)'), findsOneWidget);
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
