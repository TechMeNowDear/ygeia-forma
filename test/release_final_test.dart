// Τελικός γύρος πριν από την κυκλοφορία (έλεγχος 4): κάθε διόρθωση με έλεγχο που αποτυγχάνει χωρίς αυτήν.
// 2: PDF μετά το Oura, μία γραμμή για κάθε συσκευή (2_calcs M2 = κλινικός C3).
// 5: κλινικά (C1 κόκκινο μόνο με τον κανόνα του «Εκτός συνηθισμένου», C2 κείμενο οξυγόνου).
// 6: αναζήτηση τροφίμων (N2 καταλήξεις, N3 άλλα ονόματα).
// 4β: η κανονική ανάγνωση (30 μέρες) κρύβει, δεν σβήνει, τις τιμές ύπνου νύχτας χωρίς έγκυρη διάρκεια· «Τι φτάνει».
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/food/food_store.dart';
import 'package:ygeia_forma/format.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/oxygen_note.dart';
import 'package:ygeia_forma/pages/heart.dart';
import 'package:ygeia_forma/pages/report_page.dart';
import 'package:ygeia_forma/pages/today.dart';
import 'package:ygeia_forma/report.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/ti_ftanei.dart';
import 'package:ygeia_forma/unusual.dart';
import 'package:ygeia_forma/widgets.dart';

import 'sample_data.dart';
import 'sample_food.dart';

DateTime _add(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 3000)}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: w)));
  await t.pumpAndSettle();
}

void main() {
  // -------------------------------------------------------------------------
  group('2: PDF μετά το Oura: ύπνος και παλμοί ύπνου, μία γραμμή για κάθε συσκευή, ποτέ μαζί', () {
    // Η γραμματοσειρά της εφαρμογής (όπως στο PDF): με την προεπιλογή των δοκιμών κάθε γράμμα είναι τετράγωνο.
    setUpAll(() async {
      final inter = FontLoader('Inter');
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
        inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
      }
      await inter.load();
    });
    final now = DateTime(2026, 11, 14, 10, 20);
    final ouraFrom = DateTime(2026, 11, 6);
    final plan = SourcePlan.samsungOnly.withEra(Source.oura, ouraFrom);
    const watch = {K.sleepHr: 60.0, K.sleepMin: 400.0, K.bedtime: 330.0, K.wake: 780.0};
    const oura = {K.sleepHr: 55.0, K.sleepMin: 420.0, K.bedtime: 340.0, K.wake: 800.0};

    /// Και οι δύο πηγές ΤΙΣ ΙΔΙΕΣ μέρες: η αναφορά πρέπει να διαλέγει την πηγή κάθε μέρας.
    Map<String, Map<String, double>> history() => {
          for (var i = 0; i < 200; i++)
            dateKey(_add(dayOf(now), -i)): {
              for (final e in watch.entries) e.key: e.value + (i % 3),
              for (final e in oura.entries) ouraKeys[e.key]!: e.value + (i % 3),
            },
        };

    test('Τέσσερις δείκτες: δύο περίοδοι (ρολόι ως 5/11, Oura από 6/11), όλες οι 90 μέρες, κάθε τιμή από την πηγή της', () {
      final r = buildReport(history(), now, plan: plan);
      for (final k in reportDeviceKeys) {
        final s = r.stat(k);
        expect(s.since, isNull, reason: k);
        expect([for (final p in s.periods) p.night], [Source.watch, Source.oura], reason: k);
        final w = s.periods.first;
        final o = s.periods.last;
        expect(w.from, r.from, reason: k);
        expect(w.to, _add(ouraFrom, -1), reason: k);
        expect(o.from, ouraFrom, reason: k);
        expect(w.stat.n + o.stat.n, reportDays, reason: '$k: όλες οι 90 μέρες (πριν: μόνο οι 9 του Oura)');
        expect(w.stat.values.every((v) => v.$2 >= watch[k]! && v.$2 < watch[k]! + 3), isTrue, reason: '$k ρολόι');
        expect(o.stat.values.every((v) => v.$2 >= oura[k]! && v.$2 < oura[k]! + 3), isTrue, reason: '$k Oura');
        // Κάθε περίοδος με τη δική της μεσαία τιμή, ποτέ μαζί.
        expect(w.stat.median, inInclusiveRange(watch[k]!, watch[k]! + 2));
        expect(o.stat.median, inInclusiveRange(oura[k]!, oura[k]! + 2));
      }
      // Χωρίς αλλαγή συσκευής μέσα στις 90 μέρες: όπως πριν (μία γραμμή, καμία περίοδος).
      final later = buildReport(history(), _add(now, 120), plan: plan);
      for (final k in reportDeviceKeys) {
        expect(later.stat(k).periods, isEmpty, reason: k);
      }
      final plain = buildReport(history(), now, plan: SourcePlan.samsungOnly);
      for (final k in reportDeviceKeys) {
        expect(plain.stat(k).periods, isEmpty, reason: k);
        expect(plain.stat(k).n, reportDays);
      }
    });

    testWidgets('Σελίδα 1: «ως 5/11: ρολόι» και «↳ από 6/11: Oura» σε κάθε γραμμή, «Αλλαγή συσκευής» στη Διαφορά', (t) async {
      final s = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(now));
      s.history = history();
      s.debugSetPlan(plan);
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(680, 3600);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: ReportPage(store: s, now: now)));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.textContaining('\nως 5/11: ρολόι'), findsNWidgets(4));
      expect(find.text('  ↳ από 6/11: Oura'), findsNWidgets(4));
      expect(find.text('Αλλαγή συσκευής'), findsNWidgets(4), reason: 'μία ανά δείκτη, στη γραμμή του Oura (και η ώρα ξυπνήματος)');
      expect(find.textContaining('Oura, από 6/11'), findsNothing, reason: 'πριν: μόνο οι νύχτες του Oura');
      // Σελίδα 2: μία μεσαία τιμή για κάθε συσκευή, γραμμένη στον τίτλο.
      expect(find.text('Παλμοί στον ύπνο, μέσος όρος νύχτας (bpm) · ρολόι ως 5/11, Oura από 6/11'), findsOneWidget);
      expect(find.text('Διάρκεια ύπνου (ώρες:λεπτά) · ρολόι ως 5/11, Oura από 6/11'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('5: κλινικά', () {
    final now = DateTime(2026, 10, 24, 16, 30);
    final today = dayOf(now);

    /// Η τελευταία νύχτα 62 bpm, οι προηγούμενες 58 (η κάρτα: «+4 · συνήθως 58»). [spread]: πόσο πάνω-κάτω πήγαιναν οι
    /// προηγούμενες 28 νύχτες στο ιστορικό (από αυτό κρίνει ο κανόνας του «Εκτός συνηθισμένου»).
    HealthStore sample({required double spread}) {
      final s = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(now));
      s.history = sampleHistory(now, s.data!);
      s.prefs.cards['rhr'] = true;
      final nights = s.data!.nights;
      for (final n in nights) {
        n.sleepingHr = 58;
      }
      nights.last.sleepingHr = 62;
      expect(dayOf(nights.last.date), today);
      for (var i = 1; i <= 28; i++) {
        s.history.putIfAbsent(dateKey(_add(today, -i)), () => {})[K.sleepHr] = 58 + (i.isEven ? spread : -spread);
      }
      s.history.putIfAbsent(dateKey(today), () => {})[K.sleepHr] = 62;
      return s;
    }

    TrendPill heartPill(WidgetTester t) =>
        t.widgetList<TrendPill>(find.byType(TrendPill)).firstWhere((p) => p.text.contains('bpm · συνήθως'));
    TrendPill todayPill(WidgetTester t) =>
        t.widgetList<StatCard>(find.byType(StatCard)).firstWhere((c) => c.title.startsWith('Παλμοί στον ύπνο')).trend! as TrendPill;

    testWidgets('C1: +4 bpm μέσα στη συνηθισμένη διακύμανση → γκρι (όχι κόκκινο) στην Καρδιά και στη Σήμερα', (t) async {
      final s = sample(spread: 6);
      expect(sleepHrOff(s.history, today, plan: s.analysisPlan), isFalse, reason: 'ο κανόνας δεν το πιάνει');
      await _pump(t, HeartPage(store: s, now: now));
      expect(heartPill(t).text, startsWith('+4'));
      expect(heartPill(t).up, isTrue, reason: 'το βέλος και το νούμερο μένουν');
      expect(heartPill(t).kind, TrendKind.neutral);
      await _pump(t, TodayPage(store: s, food: sampleFoodStore(now), open: (_, [__]) {}, openSettings: () {}, now: now),
          size: const Size(400, 4000));
      expect(todayPill(t).text, startsWith('+4'));
      expect(todayPill(t).kind, TrendKind.neutral);
    });

    testWidgets('C1: όταν ο κανόνας «Εκτός συνηθισμένου» το πιάνει → κόκκινο, ίδιο και στις δύο οθόνες', (t) async {
      final s = sample(spread: 0.4);
      expect(sleepHrOff(s.history, today, plan: s.analysisPlan), isTrue);
      await _pump(t, HeartPage(store: s, now: now));
      expect(heartPill(t).kind, TrendKind.bad);
      await _pump(t, TodayPage(store: s, food: sampleFoodStore(now), open: (_, [__]) {}, openSettings: () {}, now: now),
          size: const Size(400, 4000));
      expect(todayPill(t).kind, TrendKind.bad);
    });

    test('C2: χωρίς «δύο σε έναν μήνα δύσκολα»· το κείμενο του ελέγχου, λέξη προς λέξη', () {
      final text = oxygenVeryLowRepeatText(2, [(DateTime(2026, 10, 12), 72.0), (DateTime(2026, 10, 19), 74.0)]);
      expect(text, isNot(contains('δύσκολα')));
      expect(
        text,
        'Το οξυγόνο έπεσε κάτω από 80% σε 2 νύχτες μέσα στις τελευταίες 30 μέρες (12/10: 72%, 19/10: 74%). '
        'Με ιατρικό οξύμετρο, σε υγιείς ανθρώπους τέτοιες τιμές στον ύπνο είναι σπάνιες. Το ρολόι μπορεί να κάνει '
        'λάθος, αλλά όταν το χαμηλό επαναλαμβάνεται, αξίζει να ελεγχθεί με ιατρική μέτρηση. Δεν είναι διάγνωση, και '
        'ένα αρνητικό τεστ άπνοιας του ρολογιού δεν αποκλείει πρόβλημα στην αναπνοή στον ύπνο. Πες το στον γιατρό σου '
        'και δείξε του την αναφορά (Τάσεις › Για γιατρό).',
      );
    });
  });

  // -------------------------------------------------------------------------
  group('6: αναζήτηση τροφίμων (N2, N3)', () {
    final store = FoodStore.preloaded(foods: basicFoods(), now: DateTime(2026, 11, 4, 13));
    List<String> top(String q, int n) => [for (final f in store.search(q).take(n)) f.name];

    test('Καμία νέα τροφή', () {
      expect(basicFoods().length, 323);
    });

    test('N2: «μαγιά» δεν βγάζει μάνγκο (η μαγιά δεν είναι στη βάση)', () {
      expect(store.search('μαγιά').map((f) => f.name), isNot(contains('Μάνγκο')));
      expect(store.search('magia').map((f) => f.name), isNot(contains('Μάνγκο')));
      expect(top('μάνγκο', 1), ['Μάνγκο'], reason: 'το μάνγκο βρίσκεται όπως πριν');
    });

    test('N2: «πιπεριές» → οι τρεις πιπεριές πρώτες, όχι το μαύρο πιπέρι', () {
      final t3 = top('πιπεριές', 3);
      expect(t3.every((n) => n.startsWith('Πιπεριά')), isTrue, reason: '$t3');
      expect(top('πιπεριά', 3).every((n) => n.startsWith('Πιπεριά')), isTrue);
      expect(top('πιπέρι', 1), ['Πιπέρι μαύρο'], reason: 'το πιπέρι βρίσκεται όπως πριν');
    });

    test('N2: οι πληθυντικοί «-ια» βρίσκουν ακόμα τον ενικό (κρεμμύδια → κρεμμύδι)', () {
      expect(top('κρεμμύδια', 1).single, startsWith('Κρεμμύδι'));
      expect(top('kremidia', 1).single, startsWith('Κρεμμύδι'));
    });

    test('N2: «μοσχαρίσια» → μοσχαρίσιο· «πρόβεια» → πρόβειο γάλα και γιαούρτι', () {
      expect(top('μοσχαρίσια', 1).single, startsWith('Μοσχαρίσιο φιλέτο'));
      expect(top('πρόβεια', 3), containsAll(['Γάλα πρόβειο', 'Γιαούρτι πρόβειο (~6% λιπαρά)']));
    });

    test('N3: «σοκολάτα υγείας» → οι δύο μαύρες σοκολάτες· «μοσχαρίσια μπριζόλα» → μοσχαράκι μπριζόλα', () {
      expect(top('σοκολάτα υγείας', 5), ['Σοκολάτα μαύρη 70%', 'Σοκολάτα μαύρη 50%']);
      expect(top('μοσχαρίσια μπριζόλα', 1), ['Μοσχαράκι μπριζόλα (ψητή)']);
      // Τα άλλα ονόματα μόνο σε αυτά τα τρόφιμα (όχι στη σοκολάτα γάλακτος ή στη χοιρινή μπριζόλα).
      expect(basicFoods().where((f) => f.aliases.contains('σοκολάτα υγείας')).map((f) => f.name).toSet(),
          {'Σοκολάτα μαύρη 70%', 'Σοκολάτα μαύρη 50%'});
      expect(basicFoods().where((f) => f.aliases.contains('μοσχαρίσια μπριζόλα')).map((f) => f.name).toList(),
          ['Μοσχαράκι μπριζόλα (ψητή)']);
    });
  });

  // -------------------------------------------------------------------------
  group('4β: τιμές ύπνου κρυφές, ποτέ σβησμένες', () {
    final now = DateTime(2026, 10, 24, 16, 30);
    final today = dayOf(now);

    test('1_data M2: νύχτα του ρολογιού χωρίς έγκυρη διάρκεια στην κανονική ανάγνωση → ΟΛΕΣ οι παλιές τιμές ύπνου σε «nw.*»', () {
      final d = Dashboard.fromJson(sampleDashboardJson(now));
      final x = dateKey(_add(today, -12));
      final y = dateKey(_add(today, -11));
      final h = <String, Map<String, double>>{
        x: {K.sleepMin: 452, K.bedtime: 330, K.wake: 800, K.deepPct: 10, K.sleepHr: 60, K.spo2Min: 74, K.napMin: 20, K.steps: 5000},
        y: {K.sleepMin: 400, K.bedtime: 340, K.steps: 6000},
      };
      // Η νέα ανάγνωση: η νύχτα x χωρίς φάσεις (ώρα ύπνου, όχι διάρκεια)· η y κανονική.
      final rows = {
        x: {K.bedtime: 335.0, K.wake: 805.0, K.steps: 5100.0},
        y: {K.sleepMin: 410.0, K.bedtime: 345.0, K.steps: 6100.0},
      };
      final changed = applyRecentRead(h, d, plan: SourcePlan.samsungOnly, rows: rows);
      expect(changed, containsAll([x, y]));
      final r = h[x]!;
      expect(r.containsKey(K.sleepMin), isFalse, reason: 'η διάρκεια «με τα ξυπνήματα» δεν φαίνεται ως ύπνος');
      expect(r[nonWatchSleepKey], 452, reason: 'πριν: σβηνόταν');
      for (final (k, v) in [(K.bedtime, 330.0), (K.wake, 800.0), (K.deepPct, 10.0), (K.sleepHr, 60.0), (K.spo2Min, 74.0), (K.napMin, 20.0)]) {
        expect(r['$archivePrefix$k'], v, reason: k);
      }
      expect(r[K.bedtime], 335, reason: 'οι νέες τιμές γράφονται κανονικά');
      expect(r[K.steps], 5100);
      expect(r.containsKey(otherDeviceKey), isFalse);
      expect(h[y], {K.sleepMin: 410, K.bedtime: 345, K.steps: 6100}, reason: 'κανονική νύχτα: όπως πριν');
      // Οθόνες, Τάσεις, αναφορά: μόνο κλειδιά K, ποτέ «nw.*».
      expect(SourcePlan.samsungOnly.value(h, K.sleepMin, _add(today, -12)), isNull);
      expect(buildReport(h, now).stat(K.sleepMin).values.any((v) => v.$2 == 452), isFalse);
      // Ξανά η ίδια ανάγνωση: τίποτα δεν αλλάζει (η αρχική τιμή μένει στο «nw.*»).
      applyRecentRead(h, d, plan: SourcePlan.samsungOnly, rows: rows);
      expect(h[x]![nonWatchSleepKey], 452);
      // Ανάγνωση με σφάλμα στον ύπνο: τίποτα δεν κρύβεται.
      final h2 = <String, Map<String, double>>{x: {K.sleepMin: 452, K.bedtime: 330}};
      applyRecentRead(h2, d, plan: SourcePlan.samsungOnly, rows: rows, sleepFailed: true);
      expect(h2[x]![K.sleepMin], 452);
      expect(h2[x]!.containsKey(nonWatchSleepKey), isFalse);
    });

    testWidgets('«Τι φτάνει»: πόσες νύχτες κρατήθηκαν χωριστά ως «από άλλη συσκευή»', (t) async {
      const channel = MethodChannel('ygeia/samsung');
      final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      m.setMockMethodCallHandler(channel, (call) async => '{"ok":false,"kind":"other"}');
      addTearDown(() => m.setMockMethodCallHandler(channel, null));
      final h = {
        '2020-01-01': {nonWatchSleepKey: 400.0, otherDeviceKey: 1.0},
        '2020-01-02': {nonWatchSleepKey: 410.0, otherDeviceKey: 1.0},
        '2020-01-03': {nonWatchSleepKey: 420.0},
      };
      expect(otherDeviceNights(h), 2);
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: TiFtaneiScreen(otherDeviceNights: otherDeviceNights(h))));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const ValueKey('ti-ftanei-other-device'))).data, startsWith('2 νύχτες του ιστορικού ήρθαν από άλλη συσκευή'));
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: const TiFtaneiScreen()));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('ti-ftanei-other-device')), findsNothing);
    });
  });
}
