// Γύρος 7, f9 (κείμενα, προσβασιμότητα, καθαρισμός ιδιωτικών δεδομένων): δοκιμές για τα R7-U4-1/2/3/5/8/10/11/12/13/14,
// R7-U4 B1 και R7-A11-1. Οι αναμενόμενες τιμές βγαίνουν από τον κανόνα όπως γράφεται (γραμματική, θέσεις σε px, μετρήσεις
// Inter με python), όχι από την υλοποίηση. Όλες οι τιμές και τα ονόματα είναι επινοημένα.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart' show Dashboard, HealthStore, Night, Stage;
import 'package:ygeia_forma/exercise/ex_data.dart' show ExLibrary;
import 'package:ygeia_forma/format.dart' show thousands;
import 'package:ygeia_forma/history.dart' show K;
import 'package:ygeia_forma/pages/appearance.dart' show AppearancePage;
import 'package:ygeia_forma/pages/category.dart' show TabChip;
import 'package:ygeia_forma/pages/info_sheet.dart' show InfoButton;
import 'package:ygeia_forma/pages/metric_page.dart' show metricSpecs;
import 'package:ygeia_forma/pages/privacy_page.dart' show wipeOuraNotRevokedText;
import 'package:ygeia_forma/pages/report_page.dart' show ReportPage, pdfSavedText;
import 'package:ygeia_forma/pages/training/session_page.dart' show SessionPage, restLeftText, restSpeaksNow;
import 'package:ygeia_forma/pages/trends.dart' show trendCountText;
import 'package:ygeia_forma/reference.dart' show metricInfos;
import 'package:ygeia_forma/theme.dart' show buildTheme;
import 'package:ygeia_forma/training/program.dart' show parseProgram;
import 'package:ygeia_forma/training/training_store.dart' show MemoryTrainingIO, TrainingStore;
import 'package:ygeia_forma/widgets.dart'
    show BarChart, BigValue, Hypnogram, LineChart, PeriodPicker, ScoreRing, barChartSummary, hypnogramLabel, lineChartSummary, refHiddenTicks;

import 'sample_data.dart';
import 'training_sample.dart';

Future<void> _loadInter() async {
  final inter = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
  }
  await inter.load();
}

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 1400)}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: Center(child: w))));
  await t.pump();
}

/// Οι γραμμές κώδικα (όχι σχόλια) όλων των αρχείων του lib/.
Iterable<(String, int, String)> _libLines() sync* {
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
    final lines = f.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trim().startsWith('//')) continue;
      yield (f.path, i + 1, lines[i]);
    }
  }
}

void main() {
  // ---------------------------------------------------------------- R7-U4-1
  group('R7-U4-1: προστακτική «Αντίγραψε», όχι «Αντέγραψε»', () {
    test('μισό πρόγραμμα: «Αντίγραψέ το ξανά ολόκληρο»', () {
      final r = parseProgram('{"kind": "ygeia-program", "v": 1,,}', const {});
      expect(r.ok, isFalse);
      expect(r.errors.single, contains('Αντίγραψέ το ξανά ολόκληρο'));
    });

    test('χωρίς «{»: «Αντίγραψε ολόκληρο το κομμάτι»', () {
      expect(parseProgram('κανένα πρόγραμμα εδώ', const {}).errors.single, contains('Αντίγραψε ολόκληρο'));
    });
  });

  // ---------------------------------------------------------------- R7-U4-14 (και U4-1): κανόνες γλώσσας σε όλο το lib/
  test('R7-U4-14: κανένα κείμενο με «Αντέγραψ», «να μη» + φωνήεν/κ/π/τ…, «τη» + φωνήεν, «προηγ.», «(σελ. », «επαν.», «browser»', () {
    final rules = {
      'Αντέγραψ': RegExp('Αντέγραψ'),
      'να μη': RegExp('να μη (?:μπ|ντ|γκ|τσ|τζ|[κπτξψ]|[αεηιουωάέήίόύώ])'),
      'τη + φωνήεν': RegExp('(?:^|[\\s«(])τη [αεηιουωάέήίόύώ]'),
      'προηγ.': RegExp(r'προηγ\.'),
      '(σελ. ': RegExp(r'\(σελ\. '),
      'επαν.': RegExp(r'επαν\.'),
      'browser': RegExp(r'\bbrowser\b'),
    };
    final found = <String>[
      for (final (path, no, line) in _libLines())
        for (final e in rules.entries)
          if (e.value.hasMatch(line)) '$path:$no «${e.key}»',
    ];
    expect(found, isEmpty);
  });

  group('R7-U4-14: κείμενα του πίνακα', () {
    test('β «Ακύρωσέ την», ζ/στ/ι/η/μ/ν/π στον κώδικα', () {
      expect(wipeOuraNotRevokedText, endsWith('Ακύρωσέ την από την εφαρμογή Oura.'));
      expect(File('lib/pages/sources_page.dart').readAsStringSync(), contains('για να μην μπερδευτούν οι συσκευές'));
      expect(File('lib/ti_ftanei.dart').readAsStringSync(), contains('Αντιγραφή αναφοράς για τον Claude'));
      expect(File('lib/trends.dart').readAsStringSync(), isNot(contains('εκτίμηση του Oura')));
      expect(File('lib/pages/appearance.dart').readAsStringSync(), contains("('light', 'Φωτεινό')"));
      expect(File('lib/pages/settings.dart').readAsStringSync(), contains('Πάντα φωτεινό'));
      expect(File('lib/pages/settings.dart').readAsStringSync(), contains("'εγγραφές δεν γράφτηκαν'"));
      expect(metricSpecs[K.skinTemp]!.title, 'Θερμοκρασία δέρματος');
      expect(metricInfos[K.skinTemp]!.title, 'Θερμοκρασία δέρματος');
      final report = File('lib/pages/report_page.dart').readAsStringSync();
      expect(report, contains("'Διαφορά από τους\\n3 μήνες πριν'"));
      expect(report, contains("'Δεν συγκρίνεται (σελίδα 3)'"));
      expect(report, isNot(contains(r"$reportDays ημέρες")));
      expect(report, contains(r"$reportDays μέρες"));
    });

    test('γ «Με δεδομένα»: ενικός με το 1', () {
      expect(trendCountText(1, 30, sparse: true), '1 ζύγιση');
      expect(trendCountText(3, 30, sparse: true), '3 ζυγίσεις');
      expect(trendCountText(9, 9, sparse: false), '9 από 9 μέρες');
      expect(trendCountText(1, 1, sparse: false), '1 από 1 μέρα');
      expect(trendCountText(0, 30, sparse: false), '0 από 30 μέρες');
    });

    test('θ σύνοψη για τον Claude: «1 φορά», δεκαδικό κόμμα', () {
      final src = File('lib/training/training_store.dart').readAsStringSync();
      expect(src, contains("walks.length == 1 ? '1 φορά'"));
      expect(src, contains("toStringAsFixed(1).replaceAll('.', ',')} km"));
    });
  });

  // ---------------------------------------------------------------- R7-U4-2
  group('R7-U4-2: διάλειμμα στο TalkBack', () {
    test('ενικός στο 1', () {
      expect(restLeftText(1), 'μένει 1 δευτερόλεπτο');
      expect(restLeftText(2), 'μένουν 2 δευτερόλεπτα');
      expect(restLeftText(90), 'μένουν 90 δευτερόλεπτα');
    });

    /// Τα δευτερόλεπτα στα οποία ακούγεται το διάλειμμα όταν μετρά κάθε δευτερόλεπτο από [from] ως το 1.
    List<int> spoken(int from, {Set<int> skip = const {}}) {
      final out = <int>[];
      int? last;
      for (var s = from; s >= 1; s--) {
        if (skip.contains(s)) continue;
        if (restSpeaksNow(last, s)) {
          out.add(s);
          last = s;
        }
      }
      return out;
    }

    test('στην αρχή, κάθε μισό λεπτό και στα 10 τελευταία — όχι κάθε δευτερόλεπτο', () {
      expect(spoken(90), [90, 60, 30, 10]);
      expect(spoken(120), [120, 90, 60, 30, 10]);
      expect(spoken(45), [45, 30, 10]);
      expect(spoken(8), [8]);
      // Χαμένο δευτερόλεπτο του χρονομέτρου (60): λέγεται στο 59, όχι καθόλου.
      expect(spoken(90, skip: {60}), [90, 59, 30, 10]);
    });

    test('«+30″»: ξανά με τα νέα δευτερόλεπτα', () {
      expect(restSpeaksNow(60, 75), isTrue);
      expect(restSpeaksNow(75, 74), isFalse);
      expect(restSpeaksNow(75, 60), isTrue);
    });

    testWidgets('η ζωντανή περιοχή αλλάζει μόνο στις στιγμές της· η ακριβής μέτρηση χωριστά', (t) async {
      final start = DateTime(2026, 11, 13, 17, 30);
      var clock = start;
      await t.runAsync(() => ExLibrary.load(inline: true));
      final store = TrainingStore(io: MemoryTrainingIO(), clock: () => clock);
      final p = sampleProgram()
        ..version = 1
        ..savedAt = start.subtract(const Duration(days: 20));
      store.replaceAll({
        'v': 1,
        'programs': [p.toJson()],
        'active': p.id,
      });
      store.ready = true;
      store.start(store.program!.workout('A')!);
      store.restEnd = start.add(const Duration(seconds: 90));
      final handle = t.ensureSemantics();
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(400, 1400);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: SessionPage(training: store)));
      await t.pump();
      expect(find.bySemanticsLabel('Διάλειμμα, μένουν 90 δευτερόλεπτα'), findsOneWidget);

      clock = start.add(const Duration(seconds: 10));
      await t.pump(const Duration(seconds: 1));
      expect(find.bySemanticsLabel('Διάλειμμα, μένουν 90 δευτερόλεπτα'), findsOneWidget, reason: 'πριν: κάθε δευτερόλεπτο');
      expect(find.bySemanticsLabel('Τώρα μένουν 80 δευτερόλεπτα'), findsOneWidget);

      clock = start.add(const Duration(seconds: 30));
      await t.pump(const Duration(seconds: 1));
      expect(find.bySemanticsLabel('Διάλειμμα, μένουν 60 δευτερόλεπτα'), findsOneWidget);

      store.restEnd = clock.add(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      expect(find.bySemanticsLabel('Διάλειμμα, μένει 1 δευτερόλεπτο'), findsOneWidget);

      await t.pumpWidget(const SizedBox());
      await t.pump();
      handle.dispose();
    });

    test('ρολόι: ίδιος κανόνας στα κείμενα του TalkBack (WatchView.kt)', () {
      final src = File('android/wear/src/main/kotlin/gr/ygeiaforma/wear/WatchView.kt').readAsStringSync();
      expect(src, isNot(contains(r'"Έκανες $reps επαναλήψεις"')));
      expect(src, isNot(contains(r'Μένουν $left δευτερόλεπτα")')));
      expect(src, contains('secondsLeftText(left)'));
    });
  });

  // ---------------------------------------------------------------- R7-U4-3
  group('R7-U4-3: το όνομα του PDF που αποθηκεύτηκε πράγματι', () {
    test('δεύτερο PDF την ίδια μέρα: «… (1).pdf»· χωρίς όνομα από το σύστημα: αυτό που ζητήθηκε', () {
      const asked = 'Αναφορά υγείας 2026-11-16.pdf';
      expect(pdfSavedText('Αναφορά υγείας 2026-11-16 (1).pdf', asked), 'Αποθηκεύτηκε στις Λήψεις: Αναφορά υγείας 2026-11-16 (1).pdf');
      expect(pdfSavedText(null, asked), 'Αποθηκεύτηκε στις Λήψεις: $asked');
      expect(pdfSavedText('  ', asked), 'Αποθηκεύτηκε στις Λήψεις: $asked');
    });

    test('η γέφυρα επιστρέφει το DISPLAY_NAME (όπως το αντίγραφο ασφαλείας)', () {
      final src = File('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/SamsungHealthBridge.kt').readAsStringSync();
      final pdf = src.substring(src.indexOf('"savePdf" ->'), src.indexOf('"sharePdf", "openPdf" ->'));
      expect(pdf, contains('BackupFiles.displayName(activity, uri)'));
      expect(pdf, contains('.put("name", shown)'));
    });
  });

  // ---------------------------------------------------------------- R7-U4-5
  group('R7-U4-5: η ετικέτα αναφοράς κρύβει μόνο την πιο κοντινή τιμή του άξονα', () {
    test('PDF, ύψος 48 px, άξονας 60–80–100, αναφορά 90%: φαίνονται 60 και 100', () {
      // top 26, h 48, δύο διαστήματα: 60 → 74, 80 → 50, 100 → 26· το 90 στο 26 + 48·(1 − 30/40) = 38.
      const ticks = [74.0, 50.0, 26.0];
      final hidden = refHiddenTicks(ticks, 38, 1);
      expect(hidden, {1});
      expect([for (var i = 0; i < 3; i++) if (!hidden.contains(i)) [60, 80, 100][i]], [60, 100]);
    });

    test('αναφορά πάνω σε τιμή: μόνο αυτή· μακριά: καμία· πυκνός άξονας (15 px): και όποια θα ακουμπούσε', () {
      expect(refHiddenTicks(const [74, 50, 26], 50, 1), {1});
      expect(refHiddenTicks(const [74, 50, 26], 50, 2), {1});
      expect(refHiddenTicks(const [98, 74, 50, 26], 62, 1), {1}, reason: 'ισοπαλία 12 και 12 px: η πρώτη');
      expect(refHiddenTicks(const [74, 50, 26], 88, 1), isEmpty, reason: '14 px από το 74');
      expect(refHiddenTicks(const [56, 41, 26], 48.5, 1), {0, 1});
      expect(refHiddenTicks(const [74, 50, 26], null, 1), isEmpty);
    });
  });

  // ---------------------------------------------------------------- R7-U4-8
  group('R7-U4-8: γραφήματα με κείμενο για το TalkBack', () {
    final pts = [(DateTime(2026, 10, 16), 80.0), (DateTime(2026, 10, 30), 76.0), (DateTime(2026, 11, 14), 78.0)];
    String pct(double v) => '${v.round()}%';

    test('γραμμή: διάστημα, πλήθος, χαμηλότερη, υψηλότερη, τελευταία', () {
      expect(lineChartSummary(pts, pct),
          'Γράφημα, από 16 Οκτωβρίου ως 14 Νοεμβρίου, 3 τιμές: χαμηλότερη 76%, υψηλότερη 80%, τελευταία 78%');
      expect(lineChartSummary([pts.last], pct), 'Γράφημα, 14 Νοεμβρίου: μία τιμή, 78%');
      expect(lineChartSummary(const [], pct), 'Γράφημα χωρίς τιμές');
      expect(lineChartSummary(pts, pct, from: DateTime(2026, 8, 17), to: DateTime(2026, 11, 14)), startsWith('Γράφημα, από 17 Αυγούστου ως 14 Νοεμβρίου,'));
    });

    test('ράβδοι: μέρες, χαμηλότερη, υψηλότερη, τελευταία', () {
      String t(double v) => thousands(v.round());
      expect(barChartSummary(const [7000, null, 9000, 6500], t), 'Γράφημα 4 ημερών: χαμηλότερη 6.500, υψηλότερη 9.000, τελευταία 6.500');
      expect(barChartSummary(const [5000, null], t), 'Γράφημα 2 ημερών: χαμηλότερη 5.000, υψηλότερη 5.000, τελευταία χωρίς τιμή');
      expect(barChartSummary(const [null, null], t), 'Γράφημα 2 ημερών χωρίς τιμές');
    });

    testWidgets('LineChart, BarChart, υπνόγραμμα και δαχτυλίδι βαθμολογίας στο δέντρο του TalkBack', (t) async {
      final handle = t.ensureSemantics();
      final n = Night(DateTime(2026, 11, 3))
        ..start = DateTime(2026, 11, 2, 23, 30)
        ..end = DateTime(2026, 11, 3, 7, 15);
      n.stages
        ..add(Stage('LIGHT', n.start, DateTime(2026, 11, 3, 3)))
        ..add(Stage('DEEP', DateTime(2026, 11, 3, 3), n.end));
      expect(hypnogramLabel(n), 'Γράφημα: οι φάσεις του ύπνου με τη σειρά, από 23:30 ως 07:15');
      await _pump(
        t,
        SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            LineChart(points: pts, format: pct, height: 120),
            BarChart(values: const [7000, null, 9000, 6500], labels: const ['Δ', 'Τ', 'Τ', 'Π'], height: 100, valueLabel: (v) => thousands(v.round())),
            Hypnogram(night: n),
            Semantics(container: true, child: ScoreRing(value: 84, color: Colors.blue, track: Colors.grey)),
          ]),
        ),
      );
      expect(find.bySemanticsLabel('Γράφημα, από 16 Οκτωβρίου ως 14 Νοεμβρίου, 3 τιμές: χαμηλότερη 76%, υψηλότερη 80%, τελευταία 78%'),
          findsOneWidget);
      expect(find.bySemanticsLabel('Γράφημα 4 ημερών: χαμηλότερη 6.500, υψηλότερη 9.000, τελευταία 6.500'), findsOneWidget);
      expect(find.bySemanticsLabel('Γράφημα: οι φάσεις του ύπνου με τη σειρά, από 23:30 ως 07:15'), findsOneWidget);
      expect(find.bySemanticsLabel('84 από 100'), findsOneWidget, reason: 'πριν σκέτο «84»');
      handle.dispose();
    });
  });

  // ---------------------------------------------------------------- R7-U4-10 και B1
  group('R7-U4-10: στόχοι αφής 48 dp', () {
    testWidgets('επιλογέας περιόδου: 48 dp κάθε επιλογή, ίδιο συνολικό ύψος 52', (t) async {
      await _pump(
        t,
        SizedBox(
          width: 360,
          child: PeriodPicker<int>(
              values: const [30, 90, 365], days: (d) => d, selected: 90, onChanged: (_) {}, color: Colors.teal, keyOf: (d) => 'pp-$d'),
        ),
      );
      for (final d in [30, 90, 365]) {
        expect(t.getSize(find.byKey(ValueKey('pp-$d'))).height, greaterThanOrEqualTo(48));
      }
      expect(t.getSize(find.byType(PeriodPicker<int>)).height, 52);
    });

    testWidgets('B1: σκοτεινό θέμα: η επιλογή με περίγραμμα στο χρώμα της ενότητας', (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(400, 800);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: PeriodPicker<int>(values: const [30, 90], days: (d) => d, selected: 90, onChanged: (_) {}, color: Colors.teal),
            ),
          ),
        ),
      ));
      final shapes = [
        for (final m in t.widgetList<Material>(find.descendant(of: find.byType(PeriodPicker<int>), matching: find.byType(Material))))
          if (m.shape is RoundedRectangleBorder) (m.shape! as RoundedRectangleBorder).side,
      ];
      expect(shapes.where((s) => s.style != BorderStyle.none && s.color == Colors.teal && s.width == 1.5).length, 1);
    });

    testWidgets('TabChip: ορατό 40 dp, πατιέται σε 48· ένα πάτημα πάνω στο χάπι = μία κλήση', (t) async {
      var taps = 0;
      await _pump(t, TabChip(label: 'Όλες', selected: false, solid: Colors.orange, onTap: () => taps++));
      final r = t.getRect(find.byType(TabChip));
      expect(r.height, 48);
      await t.tapAt(Offset(r.center.dx, r.top + 2));
      await t.pump();
      expect(taps, 1, reason: 'η διάφανη ζώνη πάνω από το χάπι πατιέται');
      await t.tap(find.text('Όλες'));
      await t.pump(const Duration(milliseconds: 500));
      expect(taps, 2);
    });

    testWidgets('Εμφάνιση: «Αυτόματο · Φωτεινό · Σκοτεινό» 48 dp', (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(400, 2400);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: AppearancePage(store: HealthStore())));
      await t.pump();
      final box = find.ancestor(of: find.text('Φωτεινό'), matching: find.byType(AnimatedContainer)).first;
      expect(t.getSize(box).height, 48);
      expect(find.text('Ανοιχτό'), findsNothing);
    });
  });

  // ---------------------------------------------------------------- R7-U4-11
  testWidgets('R7-U4-11: το ⓘ λέγεται «Τι είναι: …», χωρίς «i», και πατιέται', (t) async {
    final handle = t.ensureSemantics();
    await _pump(t, Semantics(container: true, child: InfoButton(K.hrv)));
    final title = metricInfos[K.hrv]!.title;
    expect(find.bySemanticsLabel('Τι είναι: $title'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'\ni$')), findsNothing);
    expect(t.getSemantics(find.byKey(const ValueKey('info-${K.hrv}'))), containsSemantics(label: 'Τι είναι: $title', isButton: true, hasTapAction: true));
    handle.dispose();
  });

  // ---------------------------------------------------------------- R7-U4-12
  group('R7-U4-12: κεφαλίδα του PDF με όνομα 60 χαρακτήρων', () {
    setUpAll(_loadInter);

    testWidgets('δύο γραμμές, το διάστημα ολόκληρο σε κάθε σελίδα', (t) async {
      final now = DateTime(2026, 11, 14, 10);
      const name = 'Αλεξάνδρα-Κωνσταντίνα Χατζηγεωργίου-Παπαδημητροπούλου Δοκιμή';
      expect(name.length, 60);
      final store = HealthStore()..data = Dashboard.fromJson(sampleDashboardJson(now));
      store.history = sampleHistory(now, store.data!);
      store.prefs.reportName = name;
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(680, 3600);
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: ReportPage(store: store, now: now)));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final f = find.byKey(const ValueKey('report-header-period'));
      expect(f, findsNWidgets(3));
      for (var i = 0; i < 3; i++) {
        final text = t.widget<Text>(f.at(i)).data!;
        expect(text, startsWith('$name · '));
        expect(text, endsWith('90 μέρες'));
        // Inter 10,5: όνομα + « ·» 367,9 στιγμές, διάστημα 161,3· διαθέσιμα 440,8 → δύο γραμμές (python, fontTools).
        expect(t.renderObject<RenderParagraph>(f.at(i)).didExceedMaxLines, isFalse, reason: 'πριν: «… 14 Νοε 20…»');
      }
    });
  });

  // ---------------------------------------------------------------- R7-U4-13
  group('R7-U4-13: μονάδες στη σελίδα «Μέτρηση»', () {
    test('διαφορά ποσοστού σε μονάδες· βαθμολογία «από 100»· αναπνοές «το λεπτό»', () {
      final fat = metricSpecs[K.fatPct]!;
      expect(fat.diffSuffix(0.3), ' μονάδες');
      expect(fat.diffSuffix(1.0), ' μονάδα');
      expect(fat.diffSuffix(-1.0), ' μονάδα');
      expect(metricSpecs[K.sleepScore]!.unit, 'από 100');
      expect(metricSpecs[K.energy]!.unitSuffix, ' από 100');
      expect(metricSpecs[K.sleepScore]!.diffSuffix(3), '');
      expect(metricSpecs[K.breath]!.unitSuffix, ' το λεπτό');
      expect(metricSpecs[K.weight]!.diffSuffix(0.4), ' kg');
    });

    testWidgets('BigValue: «25,4%» κολλητά, «82,2 kg» με κενό', (t) async {
      await _pump(t, const Column(mainAxisSize: MainAxisSize.min, children: [BigValue('25,4', unit: '%'), BigValue('82,2', unit: 'kg')]));
      expect(find.text('25,4%', findRichText: true), findsOneWidget);
      expect(find.text('82,2 kg', findRichText: true), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------- R7-A11-1
  // Ο ίδιος ο έλεγχος τρέχει στο CI (tools/ci/check_privacy.py, check.yml και android.yml): αποτυγχάνει σε φράσεις που
  // παρουσιάζουν δεδομένα δοκιμής ως πραγματικά ή λένε ιατρικό ιστορικό, και σε αποτυπώματα πραγματικών τιμών.
  test('R7-A11-1: ο έλεγχος του δημόσιου repository υπάρχει και δεν γράφει τις τιμές ανοιχτά', () {
    final py = File('tools/ci/check_privacy.py').readAsStringSync();
    expect(py, contains('R7-A11-1'));
    expect(py, contains('OWNER_PRINTS'));
    expect(py, contains('OWNER_PHRASES'));
    expect(py, contains("for base in ('lib', 'test', 'android/app/src', 'android/wear/src', 'tools', 'assets/exercises')"));
  });
}
