// Τα features της #100 (13/11): «Τελευταίο αντίγραφο», διαστάσεις οθόνης, παλμοί ηρεμίας ξύπνιος, τάση HRV 7 νυχτών,
// ποιότητα μετρήσεων παλμών, καθυστέρηση στο τέλος του διαλείμματος. Φανταστικές τιμές (δημόσιο repo).
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/backup.dart';
import 'package:ygeia_forma/body_trend.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/home_widgets/widget_snapshot.dart';
import 'package:ygeia_forma/hrv_trend.dart';
import 'package:ygeia_forma/pages/body.dart';
import 'package:ygeia_forma/pages/training/hr_widgets.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/theme.dart';
import 'package:ygeia_forma/ti_ftanei.dart';
import 'package:ygeia_forma/training/hr_quality.dart';
import 'package:ygeia_forma/training/zone.dart';
import 'package:ygeia_forma/widgets.dart';

import 'sample_data.dart';
import 'sample_food.dart';
import 'training_sample.dart';

void main() {
  group('1. «Τελευταίο αντίγραφο»', () {
    final now = DateTime(2026, 11, 20, 9);

    test('σήμερα, χθες, πριν Ν μέρες, ποτέ· ώρα στο μέλλον = σήμερα', () {
      expect(lastBackupText(null, now), 'Δεν έχεις βγάλει αντίγραφο ακόμα.');
      expect(lastBackupText(DateTime(2026, 11, 20, 0, 5), now), 'Τελευταίο αντίγραφο: σήμερα.');
      expect(lastBackupText(DateTime(2026, 11, 19, 23, 59), now), 'Τελευταίο αντίγραφο: χθες.');
      expect(lastBackupText(DateTime(2026, 11, 6, 12), now), 'Τελευταίο αντίγραφο: πριν 14 μέρες.');
      expect(lastBackupText(DateTime(2026, 11, 25), now), 'Τελευταίο αντίγραφο: σήμερα.');
    });

    test('η ώρα σώζεται στις ρυθμίσεις, αλλά δεν μπαίνει στο αντίγραφο', () {
      final p = Prefs.fromJson(const {})..lastExport = now.millisecondsSinceEpoch;
      expect(Prefs.fromJson(p.toJson()).lastExport, now.millisecondsSinceEpoch);
      expect(Prefs.fromJson(const {}).toJson().containsKey('lastExport'), isFalse);
      expect(Prefs.fromJson(const {'lastExport': 'χθες'}).lastExport, isNull);
      expect(Prefs.fromJson(const {'lastExport': double.infinity}).lastExport, isNull);
      // Σε νέο κινητό, μετά από επαναφορά, δεν έχει βγει αντίγραφο ΑΠΟ ΑΥΤΟ το κινητό.
      expect(backupPrefKeys.contains('lastExport'), isFalse);
    });

    test('το store τη δίνει ως ώρα· αριθμός εκτός ορίων = καμία', () {
      final s = HealthStore();
      expect(s.lastExport, isNull);
      s.markExported(now);
      expect(s.lastExport, now);
      s.prefs.lastExport = 9000000000000000;
      expect(s.lastExport, isNull);
    });

    test('σημειώνεται μόνο όταν το αντίγραφο βγήκε ολόκληρο', () {
      final src = File('lib/pages/settings.dart').readAsStringSync();
      expect(src, contains('if (!trainingOut && hrMissing == 0) widget.store.markExported(now);'));
    });
  });

  group('2. Διαστάσεις οθόνης στο «Τι φτάνει»', () {
    test('πλάτος × ύψος σε dp και μέγεθος γραμμάτων', () {
      expect(screenSizeText(const Size(411.4, 914.3), 1), 'Οθόνη τώρα: 411 × 914 dp · γράμματα 100%');
      expect(screenSizeText(const Size(882, 968), 1.3), 'Οθόνη τώρα: 882 × 968 dp · γράμματα 130%');
    });

    testWidgets('φαίνονται στην οθόνη', (t) async {
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: const TiFtaneiScreen()));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const ValueKey('ti-ftanei-screen'))).data, 'Οθόνη τώρα: 800 × 600 dp · γράμματα 100%');
    });
  });

  group('3. Widgets «Προπόνηση σήμερα» και «Γρήγορο φαγητό»', () {
    test('το στιγμιότυπο έχει όλη την εβδομάδα του προγράμματος με έτοιμα κείμενα', () {
      final now = DateTime(2026, 11, 20, 18);
      final t = sampleTraining(now);
      final w = workoutSnapshot(t, DateTime(2026, 11, 20));
      expect(w['has'], isTrue);
      final week = w['week'] as Map;
      expect(week.keys.toSet(), {'1', '2', '3', '4', '5', '6', '7'});
      // Παρασκευή = Α (6 ασκήσεις), Δευτέρα = Β (7 ασκήσεις), Τρίτη = περπάτημα 30′.
      expect(week['5'], {'t': 'Προπόνηση Α', 's': '6 ασκήσεις · περίπου 50′'});
      expect(week['1'], {'t': 'Προπόνηση Β', 's': '7 ασκήσεις · περίπου 56′'});
      expect(week['2'], {'t': 'Περπάτημα', 's': '30 λεπτά'});
      expect(w.containsKey('done'), isFalse);
      // Τη μέρα που έγινε προπόνηση: «έγινε», με όνομα και διάρκεια.
      final last = t.sessions.last;
      final d = workoutSnapshot(t, DateTime(last.start.year, last.start.month, last.start.day));
      expect(d['done'], dateKey(last.start));
      expect(d['doneText'], '${last.name} · ${last.end!.difference(last.start).inMinutes}′');
    });

    test('χωρίς πρόγραμμα: το λέει· μπαίνει στο στιγμιότυπο μόνο όταν η προπόνηση έχει φορτωθεί', () {
      final now = DateTime(2026, 11, 20, 18);
      final none = sampleTraining(now, program: false, history: false);
      expect(workoutSnapshot(none, now), {'has': false, 'week': <String, dynamic>{}});
      final store = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(now));
      final food = sampleFoodStore(now);
      expect(buildWidgetSnapshot(store, food, now).containsKey('workout'), isFalse);
      expect(buildWidgetSnapshot(store, food, now, training: sampleTraining(now)).containsKey('workout'), isTrue);
      expect(buildWidgetSnapshot(store, food, now, training: sampleTraining(now)..ready = false).containsKey('workout'), isFalse);
    });

    test('manifest και πόροι: δύο νέοι παροχείς, χωρίς περιοδική ανανέωση, χωρίς οθόνη ρύθμισης', () {
      final dir = Directory.systemTemp.createTempSync('manifest100');
      final m = File('${dir.path}/AndroidManifest.xml')
        ..writeAsStringSync('<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <application\n        android:label="ygeia_forma">\n'
            '        <activity\n            android:name=".MainActivity"\n            android:exported="true">\n'
            '        </activity>\n    </application>\n</manifest>\n');
      for (var i = 0; i < 2; i++) {
        final r = Process.runSync('python3', ['tools/android/patch_manifest.py', m.path]);
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      }
      final s = m.readAsStringSync();
      for (final (cls, label, res) in [('WorkoutWidget', 'Προπόνηση σήμερα', 'workout'), ('QuickFoodWidget', 'Γρήγορο φαγητό', 'quickfood')]) {
        expect(RegExp('android:name="\\.$cls"').allMatches(s).length, 1);
        expect(s, contains('android:label="$label"'));
        final xml = File('${dir.path}/res/xml/widget_$res.xml').readAsStringSync();
        expect(xml, contains('android:updatePeriodMillis="0"'));
        expect(xml, isNot(contains('android:configure')));
      }
      for (final f in ['layout/quick_workout_widget.xml', 'layout/quick_food_widget.xml', 'drawable/qw_bg.xml', 'values/quick_widgets.xml', 'values-night/quick_widgets.xml']) {
        expect(File('${dir.path}/res/$f').existsSync(), isTrue, reason: f);
      }
      dir.deleteSync(recursive: true);
    });

    test('χρώματα των widgets: αντίθεση γραμμάτων ≥ 4,5:1, ημέρα και νύχτα', () {
      for (final folder in ['values', 'values-night']) {
        final x = File('tools/android/$folder/quick_widgets.xml').readAsStringSync();
        Color c(String name) => Color(0xFF000000 | int.parse(RegExp('name="$name">#([0-9A-Fa-f]{6})<').firstMatch(x)!.group(1)!, radix: 16));
        for (final (fg, bg) in [('qw_text', 'qw_bg'), ('qw_sub', 'qw_bg'), ('qw_workout', 'qw_bg'), ('qw_on_food', 'qw_food'), ('qw_text', 'qw_plain')]) {
          expect(Aigaio.contrast(c(fg), c(bg)), greaterThanOrEqualTo(4.5), reason: '$folder: $fg πάνω σε $bg');
        }
      }
    });

    test('τα πατήματα: «+ Φαγητό», «Barcode» (σαρωτής αμέσως) και Άσκηση › Προπόνηση', () {
      final kt = File('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/QuickWidgets.kt').readAsStringSync();
      for (final target in ['w:workout:section:', 'w:food:add:', 'w:food:scan:']) {
        expect(kt, contains('"$target"'));
      }
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains("'workout' => _open(Cat.exercise, ExerciseTab.train)"));
      expect(main, contains('openAddFood(context, _food, scan: true)'));
      // Το widget της προπόνησης δεν ξεκινά ποτέ προπόνηση από την αρχική οθόνη (πάτημα κατά λάθος).
      expect(kt, isNot(contains('start')));
    });
  });

  group('9. Σώμα: λίπος και μύες ως τάση από 3 ζυγίσεις', () {
    BodyMeasurement m(int day, double? fat, {int hour = 8, double? smm}) =>
        BodyMeasurement(time: DateTime(2026, 11, day, hour), weight: 90, fatPct: fat, smm: smm);

    test('μεσαία των 3 τελευταίων με τη μεσαία των 3 πριν· μία περίεργη ζύγιση δεν την αλλάζει', () {
      final body = [m(2, 27.9), m(4, 27.5), m(6, 27.0), m(9, 26.6), m(11, 31.0), m(13, 26.3)];
      final t = bodyTrend(body, (b) => b.fatPct)!;
      expect((t.now, t.before), (26.6, 27.5));
      expect((t.from, t.to), (DateTime(2026, 11, 2, 8), DateTime(2026, 11, 6, 8)));
    });

    test('λιγότερες από 6 μέρες ζύγισης: καμία αλλαγή· ζυγίσεις της ίδιας μέρας μετρούν μία (η τελευταία)', () {
      final five = [m(2, 27.9), m(4, 27.5), m(6, 27.0), m(9, 26.6), m(11, 26.4)];
      expect(bodyTrend(five, (b) => b.fatPct), isNull);
      // Τρεις ζυγίσεις το ίδιο πρωί δεν κάνουν 6 μέρες.
      final sameDay = [...five, m(11, 26.0, hour: 9), m(11, 25.0, hour: 10)];
      expect(bodyCompositionDays(sameDay), 5);
      expect(bodyTrend(sameDay, (b) => b.fatPct), isNull);
      expect(bodyDaily(sameDay, (b) => b.fatPct).last, (DateTime(2026, 11, 11, 10), 25.0));
      // Ζύγιση χωρίς λίπος δεν μετρά στο λίπος.
      expect(bodyCompositionDays([...five, m(13, null)]), 5);
      // Κάθε μέτρηση με τις δικές της μέρες.
      expect(bodyTrend([...five, m(13, 26.3)], (b) => b.smm), isNull);
    });

    test('η γραμμή λέει τι συγκρίνεται, ή πόσες ζυγίσεις λείπουν', () {
      String d(DateTime t) => '${t.day}/${t.month}';
      expect(bodyTrendNote(previous: DateTime(2026, 11, 11), days: 6, date: d),
          'Στο βάρος, σε παρένθεση η αλλαγή από τις 11/11. Σε λίπος και μύες, οι 3 τελευταίες ζυγίσεις σε σύγκριση με τις 3 πριν.');
      expect(bodyTrendNote(previous: null, days: 1, date: d),
          'Η αλλαγή σε λίπος και μύες φαίνεται μετά από 6 μέρες ζύγισης (έχεις 1): μία ζύγιση μόνη της ανεβοκατεβαίνει με το νερό.');
    });

    testWidgets('η οθόνη Σώμα: σε παρένθεση η τάση, όχι η διαφορά από την προηγούμενη ζύγιση', (t) async {
      final at = DateTime(2026, 10, 24, 20);
      final s = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(at));
      await t.binding.setSurfaceSize(const Size(400, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: BodyPage(store: s))));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const ValueKey('body-trend-note'))).data, contains('οι 3 τελευταίες ζυγίσεις σε σύγκριση με τις 3 πριν'));
      String row(String label) => t.widgetList<InfoRow>(find.byType(InfoRow)).firstWhere((r) => r.label == label).value;
      // Δείγμα: λίπος 27,9 · 27,5 · 27,0 | 26,6 · 26,3 · 25,4 → μεσαίες 27,5 και 26,3 → −1,2 (από την προηγούμενη θα ήταν −0,9).
      expect(row('Λίπος'), '25,4 %  (−1,2)');
      // Σκελετικοί μύες 34,3 · 34,2 · 34,4 | 34,5 · 34,6 · 34,3 → 34,3 και 34,5 → +0,2 (από την προηγούμενη θα ήταν −0,3).
      expect(row('Σκελετικοί μύες'), '34,3 kg  (+0,2)');
      // Το βάρος μένει η αλλαγή από την προηγούμενη ζύγιση (83,3 → 82,2).
      expect(row('Βάρος'), '82,2 kg  (−1,1)');
    });
  });

  group('10γ. Παλμοί ηρεμίας ξύπνιος', () {
    test('η δική σου μέτρηση μετρά πριν από τους παλμούς ύπνου', () {
      final own = computeZone(age: 40, restHr: 52, s: const ZoneSettings(restHr: 60))!;
      expect((own.lo, own.hi, own.rest, own.restMeasured), (108, 131, 60, true));
      final sleep = computeZone(age: 40, restHr: 52, s: const ZoneSettings())!;
      expect((sleep.rest, sleep.restMeasured), (52, false));
      // Και χωρίς καμία νύχτα: η μέτρησή σου αρκεί για τον τύπο του Karvonen.
      final alone = computeZone(age: 40, restHr: null, s: const ZoneSettings(restHr: 60))!;
      expect((alone.lo, alone.hi, alone.restMeasured), (108, 131, true));
    });

    test('σώζεται, καθαρίζει, και τιμή εκτός 30–120 δεν διαβάζεται', () {
      const z = ZoneSettings(restHr: 58);
      expect(ZoneSettings.fromJson(z.toJson()).restHr, 58);
      expect(z.copyWith(clearRest: true).restHr, isNull);
      expect(z.copyWith(alertLow: true).restHr, 58);
      expect(const ZoneSettings().toJson().containsKey('rest'), isFalse);
      for (final bad in [29, 121, 'α', double.nan]) {
        expect(ZoneSettings.fromJson({'rest': bad}).restHr, isNull);
      }
    });

    test('τιμή πολύ κοντά στους μέγιστους: ζώνη από το % των μέγιστων, όπως πριν', () {
      final z = computeZone(age: 40, restHr: null, s: const ZoneSettings(restHr: 120, maxHr: 135))!;
      expect((z.rest, z.restMeasured), (null, false));
    });
  });

  group('10α. Τάση HRV 7 νυχτών', () {
    final today = DateTime(2026, 11, 20);
    DateTime back(int i) => DateTime(today.year, today.month, today.day - i);
    final plan = SourcePlan([SourceEra(Source.oura, back(200))]);

    /// Ιστορικό: οι 7 τελευταίες νύχτες [week], οι 60 πριν εναλλάξ [a], [b].
    Map<String, Map<String, double>> hist({required double week, double a = 36, double b = 44, int base = 60, Set<int> missing = const {}}) => {
          for (var i = 0; i < 7; i++)
            if (!missing.contains(i)) dateKey(back(i)): {'o.hrv': week},
          for (var i = 7; i < 7 + base; i++) dateKey(back(i)): {'o.hrv': i.isEven ? a : b},
        };

    test('μέσα, κάτω και πάνω από το δικό σου εύρος (σε λογάριθμο, μισή τυπική απόκλιση)', () {
      final within = hrvTrend(hist(week: 40), plan, today)!;
      expect(within.band, HrvBand.within);
      expect((within.weekNights, within.baseNights), (7, 60));
      // Με το χέρι: ln 36 και ln 44 εναλλάξ → μέσος = ln √(36·44), SD ≈ |ln 44 − ln 36| / 2 (με n−1 λίγο πάνω).
      final m = (math.log(36) + math.log(44)) / 2;
      final sd = math.sqrt(60 * math.pow((math.log(44) - math.log(36)) / 2, 2) / 59);
      expect(within.lowMs, closeTo(math.exp(m - 0.5 * sd), 1e-9));
      expect(within.highMs, closeTo(math.exp(m + 0.5 * sd), 1e-9));
      expect(within.weekMs, closeTo(40, 1e-9));
      expect(hrvTrendText(within), '7 νύχτες: 40 ms, μέσα στο δικό σου εύρος (38–42)');
      expect(hrvTrend(hist(week: 33), plan, today)!.band, HrvBand.below);
      expect(hrvTrendText(hrvTrend(hist(week: 33), plan, today)!), '7 νύχτες: 33 ms, κάτω από το δικό σου εύρος (38–42)');
      expect(hrvTrend(hist(week: 47), plan, today)!.band, HrvBand.above);
    });

    test('λίγες νύχτες: καμία γραμμή (ούτε εκτίμηση)', () {
      expect(hrvTrend(hist(week: 40, missing: {1, 3, 5}), plan, today), isNull); // 4 από 7
      expect(hrvTrend(hist(week: 40, missing: {1, 3}), plan, today)!.weekNights, 5);
      expect(hrvTrend(hist(week: 40, base: 20), plan, today), isNull);
      expect(hrvTrend(hist(week: 40, base: 21), plan, today)!.baseNights, 21);
      expect(hrvTrend(const {}, plan, today), isNull);
    });

    test('δεν περνά πάνω από αλλαγή πηγής· μηδενικές ή άπειρες τιμές δεν μετρούν', () {
      // Oura → καμία → Oura πριν από 20 μέρες: νέα «βάση», άρα μόνο 13 νύχτες πριν από την εβδομάδα.
      final cut = SourcePlan([SourceEra(Source.oura, back(200)), SourceEra(Source.none, back(40)), SourceEra(Source.oura, back(19))]);
      expect(hrvTrend(hist(week: 40), cut, today), isNull);
      final h = hist(week: 40);
      h[dateKey(back(0))] = {'o.hrv': 0};
      h[dateKey(back(1))] = {'o.hrv': double.infinity};
      expect(hrvTrend(h, plan, today)!.weekNights, 5);
    });

    test('η οθόνη ύπνου τη δείχνει κάτω από το HRV, μόνο ως περιγραφή', () {
      final src = File('lib/pages/oura_sleep.dart').readAsStringSync();
      expect(src, contains("ValueKey('sleep-hrv-trend')"));
      final lib = File('lib/hrv_trend.dart').readAsStringSync();
      final texts = RegExp(r"'[^']*'").allMatches(lib).map((m) => m.group(0)!).join(' ');
      for (final w in ['ξεκούρα', 'προπον', 'κούραση', 'άρρωστ', 'πρόσεξε']) {
        expect(texts.contains(w), isFalse, reason: w);
      }
    });
  });

  group('10β. Ποιότητα μετρήσεων παλμών', () {
    test('διαβάζεται από το κείμενο του ρολογιού', () {
      final q = hrQualityFromDiag('5s=1 wake=1 q=5400/120/15')!;
      expect((q.ok, q.low, q.bad, q.total), (5400, 120, 15, 5535));
      expect(hrQualityFromDiag('q=10/0/0')!.ok, 10);
      for (final none in [null, '', '5s=1 wake=1', 'q=0/0/0', 'q=1/2', 'xq=1/2/3', 'q=1/2/3x', 'q=-1/2/3', 'q=1/2/α']) {
        expect(hrQualityFromDiag(none), isNull, reason: '$none');
      }
      // 40 χαρακτήρες = ίσως κομμένο από το κινητό: τίποτα, αντί για λάθος αριθμό.
      expect('5s=1 wake=1 q=123456789/123456789/123456'.length, 40);
      expect(hrQualityFromDiag('5s=1 wake=1 q=123456789/123456789/123456'), isNull);
    });

    test('κείμενο με χιλιάδες· γράφει μόνο ό,τι υπάρχει', () {
      expect(hrQualityText(const HrQualityCounts(5400, 120, 15)),
          'Μετρήσεις ρολογιού: 5.400 με καλή επαφή · 120 χαμηλής ακρίβειας · 15 χωρίς επαφή (δεν μέτρησαν).');
      expect(hrQualityText(const HrQualityCounts(900, 0, 0)), 'Μετρήσεις ρολογιού: 900, όλες με καλή επαφή.');
      expect(hrQualityText(const HrQualityCounts(900, 0, 4)), 'Μετρήσεις ρολογιού: 900 με καλή επαφή · 4 χωρίς επαφή (δεν μέτρησαν).');
    });

    testWidgets('η κάρτα παλμών το δείχνει μόνο όταν το ρολόι έστειλε καταμέτρηση', (tester) async {
      final t = sampleTraining(DateTime(2026, 11, 20, 18));
      final s = t.sessions.last
        ..hrAvg = 118
        ..hrMax = 150
        ..watchDiag = '5s=1 wake=1 q=5400/120/15';
      Future<void> pump() => tester.pumpWidget(MaterialApp(
            theme: buildTheme(Brightness.light),
            home: Scaffold(body: SingleChildScrollView(child: HrCard(session: s, key: UniqueKey()))),
          ));
      await pump();
      expect(tester.widget<Text>(find.byKey(const ValueKey('hr-quality'))).data, startsWith('Μετρήσεις ρολογιού: 5.400 με καλή επαφή'));
      s.watchDiag = '5s=1 wake=1';
      await pump();
      expect(find.byKey(const ValueKey('hr-quality')), findsNothing);
    });
  });

  group('11. Καθυστέρηση στο τέλος του διαλείμματος', () {
    test('το κινητό τη μετρά μόνο του και μπαίνει στην «Αναφορά για έλεγχο»', () {
      final bridge = File('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/TrainingBridge.kt').readAsStringSync();
      expect(bridge, contains('"restStats" -> result.success(restStats(activity.applicationContext))'));
      expect(bridge, contains('noteLate(ctx, SystemClock.elapsedRealtime() - dueElapsed, viaAlarm)'));
      final diag = File('lib/diagnostics.dart').readAsStringSync();
      expect(diag, contains("'rest': rest,"));
      final sheet = File('lib/pages/diagnostics_sheet.dart').readAsStringSync();
      expect(sheet, contains('rest: await TrainingDevice.restStats(),'));
    });
  });
}
