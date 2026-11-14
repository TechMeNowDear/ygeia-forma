// Round 12 · i1 (κείμενα και ξερά κουκιά): R12-D1-1, R12-D2-1, R12-D2-2, R12-D2-3, R12-D2-4, R12-D2-5. Οι αναμενόμενες
// τιμές βγήκαν με το χέρι (python, Inter της εφαρμογής: /home/claude/scratch/i1/) από τον γραμμένο κανόνα: «·» με κανονικό
// κενό πριν και αδιάσπαστο μετά (η γραμμή δεν τελειώνει ποτέ σε «·», UAX #14), ο αριθμός με τη μονάδα του (R2-U2-05), καμία
// λέξη κομμένη στη μέση. Προϊόντα, προπονήσεις, ζυγίσεις και άνθρωπος φανταστικά.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart' show Dashboard, HealthStore, applyRecentRead;
import 'package:ygeia_forma/exercise/ex_data.dart' show ExLibrary;
import 'package:ygeia_forma/exercise/ex_player.dart' show ExClock;
import 'package:ygeia_forma/food/chol.dart' show CholDay, isLegumes;
import 'package:ygeia_forma/food/food_model.dart' show Food, LogEntry, Meal, NValue, Nk, Nutrients;
import 'package:ygeia_forma/food/off.dart' show legumesByName, myFoodsCategory;
import 'package:ygeia_forma/format.dart' show datedTitle, dotJoin, shortDayDate;
import 'package:ygeia_forma/history.dart' show K, dateKey;
import 'package:ygeia_forma/pages/today.dart' show TodayPage;
import 'package:ygeia_forma/pages/training/program_editor.dart' show ProgramEditorPage;
import 'package:ygeia_forma/pages/training/progress_page.dart' show progressHighlights;
import 'package:ygeia_forma/pages/training/today_training_card.dart' show TodayTrainingCard;
import 'package:ygeia_forma/pages/training/training_page.dart' show recentWorkoutLine;
import 'package:ygeia_forma/pages/trends.dart' show TrendsPage;
import 'package:ygeia_forma/pages/week_card.dart' show WeekCard;
import 'package:ygeia_forma/sources.dart' show SourcePlan;
import 'package:ygeia_forma/theme.dart' show buildTheme, tabular;
import 'package:ygeia_forma/training/progress.dart' show walkProgress;
import 'package:ygeia_forma/training/session.dart' show ExLog, Session, SetLog;
import 'package:ygeia_forma/training/training_store.dart' show MemoryTrainingIO, TrainingStore;
import 'package:ygeia_forma/trends.dart' show TrendPeriod, TrendResult, TrendStatus, metricDef;
import 'package:ygeia_forma/weekly.dart' show WeekReview;
import 'package:ygeia_forma/widgets.dart' show gluedIfFits;

import 'sample_data.dart' show sampleDashboardJson, sampleHistory;
import 'sample_food.dart' show basicFoods, sampleFoodStore;
import 'training_sample.dart' show sampleProgram, sampleTraining;

const _dot = '\u00B7';
const _nb = '\u00A0';

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 3000), double textScale = 1.0}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.light),
    builder: (context, child) =>
        MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
    home: Scaffold(body: w),
  ));
  await t.pumpAndSettle();
}

/// Δικό μου προϊόν (από ετικέτα), τιμές ανά 100 g.
Food _mine(String id, String name, Map<String, double> n) => Food(
      id: id,
      name: name,
      cat: myFoodsCategory,
      source: 'Ετικέτα',
      n: Nutrients({for (final e in n.entries) e.key: NValue(e.value)}),
    );

var _seq = 0;
LogEntry _le(DateTime d, Food f, double grams) => LogEntry(
      id: 'r12i1-${_seq++}',
      day: dateKey(d),
      meal: Meal.lunch,
      food: f,
      grams: grams,
      time: DateTime(d.year, d.month, d.day, 13),
    );

/// Η πάνω άκρη (στρογγυλεμένη) του χαρακτήρα [i] όπως ζωγραφίστηκε· null αν δεν ζωγραφίστηκε.
typedef _Top = int? Function(int i);

_Top _painterTop(TextPainter tp) => (i) {
      final b = tp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
      return b.isEmpty ? null : b.first.top.round();
    };

_Top _paragraphTop(RenderParagraph p) => (i) {
      final b = p.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
      return b.isEmpty ? null : b.first.top.round();
    };

/// Πόσα «·» του [s] ΤΕΛΕΙΩΝΟΥΝ γραμμή και πόσα ΑΡΧΙΖΟΥΝ γραμμή (όπως στο r11_h1).
({int atEnd, int atStart}) _dots(String s, _Top top) {
  var atEnd = 0, atStart = 0;
  bool space(int k) => s[k] == ' ' || s[k] == _nb;
  for (var i = s.indexOf(_dot); i >= 0; i = s.indexOf(_dot, i + 1)) {
    final y = top(i);
    var j = i + 1;
    while (j < s.length && space(j)) {
      j++;
    }
    var k = i - 1;
    while (k >= 0 && space(k)) {
      k--;
    }
    if (j >= s.length || top(j) != y) atEnd++;
    if (k >= 0 && top(k) != y) atStart++;
  }
  return (atEnd: atEnd, atStart: atStart);
}

/// Αριθμός και λέξη διάρκειας («7 ώρες», «13 λεπτά»), με κανονικό ή αδιάσπαστο κενό.
final _unit = RegExp('\\d+[ $_nb](?:ώρες|ώρα|λεπτά|λεπτό)');

/// Οι λέξεις του [s] που ζωγραφίστηκαν σε δύο γραμμές (κομμένες μέσα στη λέξη)· λέξη = ό,τι δεν είναι κενό ή U+00A0.
List<String> _cutWords(String s, _Top top) => [
      for (final m in RegExp('[^ $_nb]+').allMatches(s))
        if (top(m.start) != top(m.end - 1)) m.group(0)!,
    ];

/// Οι διάρκειες του [s] που ζωγραφίστηκαν σε δύο γραμμές («13» / «λεπτά»).
List<String> _splitUnits(String s, _Top top) => [
      for (final m in _unit.allMatches(s))
        if (top(m.start) != top(m.end - 1)) m.group(0)!,
    ];

/// Ο κανόνας του «·» για το [s] (Inter [size], ύψος 1,4) σε κάθε πλάτος από [from] ως [to]: κανένα «·» στο τέλος γραμμής
/// και καμία διάρκεια σε δύο γραμμές. Επιστρέφει σε πόσα πλάτη κάποιο «·» βρέθηκε στην ΑΡΧΗ γραμμής.
int _checkDots(String s, {double size = 13, int from = 140, int to = 420, FontWeight weight = FontWeight.w400}) {
  var startsLine = 0;
  for (var w = from; w <= to; w++) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontFamily: 'Inter', fontSize: size, height: 1.4, fontWeight: weight)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w.toDouble());
    final top = _painterTop(tp);
    final d = _dots(s, top);
    final units = _splitUnits(s, top);
    tp.dispose();
    expect(d.atEnd, 0, reason: 'πλάτος $w: γραμμή που τελειώνει σε «$_dot» στο «$s»');
    expect(units, isEmpty, reason: 'πλάτος $w: διάρκεια σε δύο γραμμές στο «$s»');
    if (d.atStart > 0) startsLine++;
  }
  return startsLine;
}

TrendResult _trend(String key, double current, {double? previous, required bool inconclusive, TrendStatus status = TrendStatus.stable}) =>
    TrendResult(
      def: metricDef(key)!,
      status: status,
      current: current,
      previous: previous ?? current,
      nCurrent: 7,
      nPrevious: 28,
      needed: 4,
      z: 0,
      points: const [],
      currentFrom: DateTime(2026, 11, 9),
      previousFrom: DateTime(2026, 10, 12),
      previousEnd: DateTime(2026, 11, 8),
      end: DateTime(2026, 11, 15),
      // Με 7 μέρες που μοιάζουν πολύ: ~2 «πραγματικές» μέρες → «Λίγες μέρες για συμπέρασμα» (TrendResult.inconclusive).
      effectiveCurrent: inconclusive ? 2.0 : null,
    );

/// Οι παράγραφοι της «Η εβδομάδα σου» με τιμή διάρκειας («7 ώρες 13 λεπτά») ή με «4 προηγούμενες» (όχι ο υπότιτλος
/// «9–15 Νοε · …», που κι αυτός αρχίζει με ψηφίο).
final _weekLine = RegExp('^(\\d+$_nb(?:ώρες|ώρα|λεπτά|λεπτό)|4 προηγούμενες)');

List<RenderParagraph> _weekValues(WidgetTester t) => [
      for (final e in find.descendant(of: find.byType(WeekCard), matching: find.byType(RichText)).evaluate())
        if (_weekLine.hasMatch((e.renderObject! as RenderParagraph).text.toPlainText())) e.renderObject! as RenderParagraph,
    ];

void main() {
  // Τα πλάτη μετριούνται με το Inter της εφαρμογής (όχι με τη γραμματοσειρά δοκιμών), όπως στο r11_h1.
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
  });

  // ---------------------------------------------------------------------------------------------------------------- D1-1
  group('R12-D1-1: δικά σου ξερά κουκιά μετρούν «Όσπρια», όπως τα «Κουκιά (ξερά)» της βάσης', () {
    final day = DateTime(2026, 11, 16);

    test('από το όνομα: ξερά (από 300 kcal) ναι· κατεψυγμένα, αλεύρι, ζυμαρικό από κουκιά, πραλίνα φουντουκιού όχι', () {
      expect(legumesByName(_mine('MK', 'Κουκιά ξερά Χ', {Nk.kcal: 301})), isTrue);
      expect(legumesByName(_mine('MK1', 'ΚΟΥΚΙΑ χοντρά', {Nk.kcal: 330})), isTrue, reason: 'κεφαλαία, χωρίς τόνους');
      expect(legumesByName(_mine('MK2', 'Κουκιά κατεψυγμένα', {Nk.kcal: 72})), isFalse, reason: 'κάτω από 300 kcal (R9-A3-1)');
      expect(legumesByName(_mine('MK3', 'Αλεύρι από κουκιά', {Nk.kcal: 340})), isFalse, reason: '«αλεύρι»: όχι ξερό όσπριο');
      expect(legumesByName(_mine('MK4', 'Ζυμαρικά από κουκιά', {Nk.kcal: 350})), isFalse, reason: 'ζυμαρικό (R10-B1-3)');
      expect(legumesByName(_mine('MK5', 'Πραλίνα φουντουκιού', {Nk.kcal: 549})), isFalse, reason: 'λέξη που δεν αρχίζει «κουκι»');
      // Η βάση: από την κατηγορία, όπως πριν.
      final base = basicFoods().firstWhere((f) => f.id == 'C20518');
      expect((base.cat, isLegumes(base)), ('Όσπρια', true));
    });

    test('80 g ξερά κουκιά: η μέρα μετρά «Όσπρια» με 80 g ξερά (όριο 40 g), όπως 80 g από τη βάση· 200 g κατεψυγμένα όχι', () {
      final own = _mine('MK', 'Κουκιά ξερά Χ', {Nk.kcal: 301, Nk.protein: 26, Nk.carbs: 37, Nk.fat: 1.5, Nk.fiber: 25});
      final base = basicFoods().firstWhere((f) => f.id == 'C20518');
      for (final f in [own, base]) {
        final d = CholDay([_le(day, f, 80)]);
        // Πριν: το δικό σου προϊόν 0 g («Τίποτα»), της βάσης 80 g.
        expect((d.legumes, d.legumesDryG), (true, 80.0), reason: f.name);
      }
      final frozen = CholDay([_le(day, _mine('MK2', 'Κουκιά κατεψυγμένα', {Nk.kcal: 72}), 200)]);
      expect((frozen.legumes, frozen.legumesDryG), (false, 0.0));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- D2-1
  group('R12-D2-1: «Η εβδομάδα σου»: καμία λέξη κομμένη, ο αριθμός με τη μονάδα του και στο «4 προηγούμενες»', () {
    WeekReview week({required bool inconclusive}) => WeekReview(
          monday: DateTime(2026, 11, 9),
          sunday: DateTime(2026, 11, 15),
          items: [
            _trend(K.sleepMin, 433, previous: 446, inconclusive: inconclusive), // 7 ώρες 13 λεπτά, πριν 7 ώρες 26 λεπτά
            _trend(K.activeMin, 85, previous: 70, inconclusive: inconclusive), // 1 ώρα 25 λεπτά, πριν 1 ώρα 10 λεπτά
          ],
        );

    void checkValues(WidgetTester t, String when) {
      final ps = _weekValues(t);
      expect(ps.length, 4, reason: '$when: δύο τιμές και δύο «4 προηγούμενες»');
      for (final p in ps) {
        final s = p.text.toPlainText();
        final top = _paragraphTop(p);
        expect(_cutWords(s, top), isEmpty, reason: '$when: λέξη κομμένη στο «$s»');
        expect(_splitUnits(s, top), isEmpty, reason: '$when: διάρκεια σε δύο γραμμές στο «$s»');
      }
    }

    double left(RenderParagraph p) => p.localToGlobal(Offset.zero).dx;

    testWidgets('ανοιχτό Fold (κάρτα 596 dp), 1,3×, «Λίγες μέρες για συμπέρασμα» (στήλη ~121 dp): τίποτα κομμένο', (t) async {
      await _pump(
        t,
        Align(alignment: Alignment.topLeft, child: SizedBox(width: 596, child: WeekCard(review: week(inconclusive: true)))),
        size: const Size(700, 2000),
        textScale: 1.3,
      );
      // Πριν: «4 προηγούμενες: 7 ώρες 26 λεπτά» με ΟΛΑ τα κενά αδιάσπαστα: ένα κομμάτι 131 dp σε στήλη 121 dp, κομμένο.
      // Τώρα «7 ώρες» / «26 λεπτά» (και, αν το «προηγούμενες:» ~121 dp δεν χωρά δίπλα στο «χάπι», μία στήλη γραμμών).
      expect(find.text('4 προηγούμενες: 7${_nb}ώρες 26${_nb}λεπτά'), findsOneWidget);
      expect(find.text('4 προηγούμενες: 1${_nb}ώρα 10${_nb}λεπτά'), findsOneWidget);
      checkValues(t, '596 dp, 1,3×');
    });

    testWidgets('ανοιχτό Fold (κάρτα 596 dp), 2×: μία στήλη, τα «χάπια» κάτω από τις τιμές, τίποτα κομμένο', (t) async {
      // Πριν (R12-D2-1 (b)): δύο στήλες και η στήλη της τιμής ~119–121 dp: «13 λεπτά» (έντονα 16, ~147 dp) κομμένο.
      for (final inconclusive in [true, false]) {
        await _pump(
          t,
          Align(alignment: Alignment.topLeft, child: SizedBox(width: 596, child: WeekCard(review: week(inconclusive: inconclusive)))),
          size: const Size(700, 3000),
          textScale: 2.0,
        );
        checkValues(t, '596 dp, 2×, inconclusive $inconclusive');
        final lefts = {for (final p in _weekValues(t)) left(p).round()};
        expect(lefts.length, 1, reason: 'μία στήλη γραμμών');
      }
    });

    testWidgets('κινητό 360 dp (κάρτα 328 dp), 2×, «Σταθερό»: «προηγούμενες:» και «13 λεπτά» ολόκληρα, «Σταθερό» από κάτω',
        (t) async {
      await _pump(
        t,
        Align(alignment: Alignment.topLeft, child: SizedBox(width: 328, child: WeekCard(review: week(inconclusive: false)))),
        size: const Size(360, 3000),
        textScale: 2.0,
      );
      // Πριν: «Σταθερό» δίπλα, στήλη ~143 dp: «προηγούμενες:» (~181 dp στα 2×) κομμένο μέσα στη λέξη.
      checkValues(t, '360 dp, 2×');
      final previous = _weekValues(t).firstWhere((p) => p.text.toPlainText().startsWith('4 προηγούμενες'));
      final previousBottom = previous.localToGlobal(Offset.zero).dy + previous.size.height;
      expect(t.getRect(find.text('Σταθερό').first).top, greaterThanOrEqualTo(previousBottom - 0.5), reason: 'το «χάπι» κάτω από την τιμή');
    });

    testWidgets('ανοιχτό Fold (κάρτα 596 dp), 1×: όπως πριν, δύο στήλες και «Σταθερό» δίπλα στην τιμή', (t) async {
      await _pump(
        t,
        Align(alignment: Alignment.topLeft, child: SizedBox(width: 596, child: WeekCard(review: week(inconclusive: false)))),
        size: const Size(700, 2000),
      );
      checkValues(t, '596 dp, 1×');
      expect({for (final p in _weekValues(t)) left(p).round()}.length, 2);
      final value = _weekValues(t).first;
      expect(t.getRect(find.text('Σταθερό').first).left, greaterThan(value.localToGlobal(Offset.zero).dx + 100));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- D2-2
  group('R12-D2-2: «Τάσεις» και «Πρόοδος»: η διάρκεια με τον αριθμό κολλημένο στη λέξη του', () {
    testWidgets('gluedIfFits: κολλά μόνο όταν το κομμάτι χωρά (έντονα 17, ψηφία ίσου πλάτους)', (t) async {
      const style = TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w700, fontFeatures: tabular);
      final got = <String>[];
      Widget probe() => Builder(builder: (context) {
            got
              ..clear()
              ..add(gluedIfFits(context, '7 ώρες 13 λεπτά', style, 177))
              ..add(gluedIfFits(context, '7 ώρες 13 λεπτά', style, 137))
              ..add(gluedIfFits(context, '—', style, 137));
            return const SizedBox();
          });
      // 2×: «13 λεπτά» = 4,60 em × 34 = 156 dp: χωρά στα 177 (κινητό 400 dp), όχι στα 137 (360 dp) → όπως ήταν.
      await _pump(t, probe(), textScale: 2.0);
      expect(got, ['7${_nb}ώρες 13${_nb}λεπτά', '7 ώρες 13 λεπτά', '—']);
      // 1×: 78 dp, χωρά παντού.
      await _pump(t, probe());
      expect(got, ['7${_nb}ώρες 13${_nb}λεπτά', '7${_nb}ώρες 13${_nb}λεπτά', '—']);
    });

    testWidgets('Τάσεις, κινητό 400 dp, 2×: η τιμή του ύπνου ποτέ «7 ώρες 13» / «λεπτά», καμία λέξη κομμένη', (t) async {
      final today = DateTime(2026, 11, 14);
      final s = HealthStore()
        ..history = {
          // 433 ± 0,4 λεπτά: φαίνεται «7 ώρες 13 λεπτά» και στα δύο διαστήματα.
          for (var i = 0; i <= 60; i++) dateKey(DateTime(today.year, today.month, today.day - i)): {K.sleepMin: 433.0 + (i.isEven ? 0.4 : -0.4)},
        };
      await _pump(t, TrendsPage(store: s, now: DateTime(2026, 11, 14, 10)), size: const Size(400, 8000), textScale: 2.0);
      final values = [
        for (final e in find.descendant(of: find.byType(TrendsPage), matching: find.byType(RichText)).evaluate())
          if (RegExp('^7[ $_nb]ώρες 13[ $_nb]λεπτά\$').hasMatch((e.renderObject! as RenderParagraph).text.toPlainText()))
            e.renderObject! as RenderParagraph,
      ];
      expect(values, isNotEmpty);
      for (final p in values) {
        final text = p.text.toPlainText();
        final top = _paragraphTop(p);
        expect(_cutWords(text, top), isEmpty, reason: text);
        // Κολλημένο (χωρά): ο αριθμός με τη λέξη του. Πριν: «7 ώρες 13» / «λεπτά».
        if (text.contains('13${_nb}λεπτά')) expect(_splitUnits(text, top), isEmpty, reason: text);
      }
      expect(values.any((p) => p.text.toPlainText() == '7${_nb}ώρες 13${_nb}λεπτά'), isTrue, reason: 'στα 400 dp χωρά κολλημένο');
    });

    test('Πρόοδος › «Τι άλλαξε»: «6 ώρες 58 λεπτά → 7 ώρες 13 λεπτά», σε κάθε πλάτος ο αριθμός με τη λέξη του', () {
      final r = TrendResult(
        def: metricDef(K.sleepMin)!,
        status: TrendStatus.up,
        current: 433,
        previous: 418,
        nCurrent: 30,
        nPrevious: 30,
        needed: 20,
        z: 3,
        points: const [],
        currentFrom: DateTime(2026, 10, 16),
        previousFrom: DateTime(2026, 9, 16),
        previousEnd: DateTime(2026, 10, 15),
        end: DateTime(2026, 11, 14),
      );
      final h = progressHighlights(walkProgress(const <Session>[], DateTime(2026, 11, 14), TrendPeriod.quarter), const [], [r]);
      final s = h.single.$1;
      expect(s, endsWith(': 6${_nb}ώρες 58${_nb}λεπτά → 7${_nb}ώρες 13${_nb}λεπτά'));
      for (var w = 150; w <= 330; w++) {
        final tp = TextPainter(
          text: TextSpan(text: s, style: const TextStyle(fontFamily: 'Inter', fontSize: 14, height: 1.4)),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: w.toDouble());
        expect(_splitUnits(s, _painterTop(tp)), isEmpty, reason: 'πλάτος $w');
        tp.dispose();
      }
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- D2-3
  group('R12-D2-3: Επεξεργασία προγράμματος: η γραμμή κάθε προπόνησης με τον κανόνα της «Άσκησης»', () {
    setUp(() => ExClock.frozen = true);
    tearDown(() => ExClock.frozen = false);

    testWidgets('«6 ασκήσεις ·\u00A0περίπου N\u00A0λεπτά» και το πλάνο περπατήματος «30 → 45 λεπτά»: το «·» ποτέ στο τέλος', (t) async {
      await t.runAsync(() => ExLibrary.load(inline: true));
      final p = sampleProgram();
      final walk = p.workouts.firstWhere((w) => w.isCardio).cardio!;
      walk
        ..activity = 'brisk'
        ..plan = [30, 35, 40, 45];
      final store = TrainingStore(io: MemoryTrainingIO(), clock: () => DateTime(2026, 11, 14, 10))..ready = true;
      await _pump(t, ProgramEditorPage(training: store, program: p), size: const Size(400, 2400));
      // Πριν: «6 ασκήσεις · περίπου 53 λεπτά» με κανονικά κενά (400 dp, 1,3×: «… περίπου 53» / «λεπτά»).
      for (final n in [6, 7]) {
        final line = find.textContaining(RegExp('^$n ασκήσεις $_dot${_nb}περίπου \\d+${_nb}λεπτά\$'));
        expect(line, findsOneWidget, reason: '$n ασκήσεις');
        // Από 100 dp: σε κάποια πλάτη η γραμμή σπάει ΠΡΙΝ από το «·» (στα 140–420 σπάει μόνο στο «περίπου»).
        expect(_checkDots(t.widget<Text>(line).data!, size: 13.5, from: 100), greaterThan(0));
      }
      const cardio = 'Γρήγορο περπάτημα $_dot${_nb}30$_nb→ 45${_nb}λεπτά (ανά εβδομάδα)';
      expect(find.text(cardio), findsOneWidget);
      expect(_checkDots(cardio, size: 13.5), greaterThan(0));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- D2-4
  group('R12-D2-4: «Άσκηση σήμερα»: «Έγινε σήμερα και: Περπάτημα · 1 ώρα 5 λεπτά»', () {
    setUp(() => ExClock.frozen = true);
    tearDown(() => ExClock.frozen = false);

    testWidgets('Παρασκευή (βάρη) με περπάτημα 65′ από το ρολόι, 360 dp: «5 λεπτά» μαζί, το «·» ποτέ στο τέλος', (t) async {
      final fri = DateTime(2026, 11, 13, 17, 30); // «A» (βάρη) στο δείγμα
      await t.runAsync(() => ExLibrary.load(inline: true));
      final store = sampleTraining(fri);
      final walk = Session(
        id: 'w-r12',
        workout: 'walk',
        name: 'Περπάτημα',
        programId: 'p-claude-1',
        start: DateTime(2026, 11, 13, 8),
        end: DateTime(2026, 11, 13, 9, 5),
        cardioMinutes: 65,
        cardioSec: 3900,
        source: 'watch',
        activity: 'walk',
      );
      final j = store.toJson();
      j['sessions'] = [...(j['sessions'] as List), walk.toJson()];
      store
        ..replaceAll(j)
        ..ready = true;
      expect(TodayTrainingCard.otherToday(store, fri)?.id, 'w-r12');
      await _pump(t, SingleChildScrollView(child: TodayTrainingCard(training: store, now: fri)), size: const Size(360, 3000));
      final line = find.descendant(of: find.byKey(const ValueKey('today-training-other')), matching: find.byType(Text));
      expect(line, findsOneWidget);
      final s = t.widget<Text>(line).data!;
      // Πριν: «… Περπάτημα · 1 ώρα 5» / «λεπτά» στα 360 dp.
      expect(s, 'Έγινε σήμερα και: Περπάτημα $_dot${_nb}1${_nb}ώρα 5${_nb}λεπτά');
      final p = t.renderObject<RenderParagraph>(find.descendant(of: line, matching: find.byType(RichText)));
      final top = _paragraphTop(p);
      expect(_dots(s, top).atEnd, 0);
      expect(_splitUnits(s, top), isEmpty);
      expect(_checkDots(s), greaterThan(0));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- D2-5
  group('R12-D2-5: ο ΕΝΑΣ κανόνας για το «·»: κανονικό κενό πριν, αδιάσπαστο μετά, σε όλες τις γραμμές', () {
    setUp(() => ExClock.frozen = true);
    tearDown(() => ExClock.frozen = false);

    test('ο κανόνας και ο τίτλος με ημερομηνία («Βάρος · Δευ 16/11»)', () {
      expect(dotJoin, ' $_dot$_nb');
      final mon = DateTime(2026, 11, 16);
      expect(datedTitle('Βάρος', mon, DateTime(2026, 11, 17)), 'Βάρος$dotJoin${shortDayDate(mon)}');
      expect(datedTitle('Βάρος', mon, mon), 'Βάρος');
    });

    test('Άσκηση › «Τελευταίες προπονήσεις»: «52 λεπτά · 9 σετ · … kg · μέσοι παλμοί 118»', () {
      final start = DateTime(2026, 11, 11, 18);
      final s = Session(
        id: 'r12',
        workout: 'A',
        name: 'Προπόνηση Α',
        programId: 'p',
        start: start,
        end: start.add(const Duration(minutes: 52)),
        hrAvg: 118,
        items: [
          for (final ex in ['db_press', 'db_row', 'goblet'])
            ExLog(ex: ex, sets: 3, lo: 8, hi: 12, rir: 2, rest: 90, log: [for (var i = 0; i < 3; i++) SetLog(load: 12, reps: 10, done: true)]),
        ],
      );
      final line = recentWorkoutLine(s);
      // Πριν (360 dp, 1,3×): «52 λεπτά · 18 σετ · 3.450 kg ·» / «μέσοι παλμοί 118».
      expect(line, startsWith('52${_nb}λεπτά $_dot${_nb}9${_nb}σετ $_dot$_nb'));
      expect(line, endsWith(' $_dot${_nb}μέσοι παλμοί${_nb}118'));
      expect(_checkDots(line), greaterThan(0));
    });

    testWidgets('«Άσκηση σήμερα» σε εξέλιξη, 360 dp, 2×: «0 σετ ως τώρα · ξεκίνησες 17:30», το «·» ποτέ στο τέλος', (t) async {
      final fri = DateTime(2026, 11, 13, 17, 30);
      await t.runAsync(() => ExLibrary.load(inline: true));
      final store = sampleTraining(fri);
      store.start(store.program!.workout('A')!);
      await _pump(t, SingleChildScrollView(child: TodayTrainingCard(training: store, now: fri)), size: const Size(360, 3000), textScale: 2.0);
      final line = find.textContaining('σετ ως τώρα');
      expect(line, findsOneWidget);
      final s = t.widget<Text>(line).data!;
      expect(s, '0 σετ ως τώρα $_dot${_nb}ξεκίνησες 17:30');
      // Πριν (360 dp, 2×): «… σετ ως τώρα ·» / «ξεκίνησες …».
      expect(_dots(s, _paragraphTop(t.renderObject<RenderParagraph>(line))).atEnd, 0);
      expect(_checkDots(s, from: 100), greaterThan(0));
    });

    testWidgets('Σήμερα › «Σήμερα ζύγιση και μέση», 360 dp, 2×: «Ζύγιση InBody · 80,9 kg» (πριν «Ζύγιση InBody ·» / «…»)',
        (t) async {
      final now = DateTime(2026, 12, 4, 9); // Παρασκευή: ζύγιση και μέση
      const inbody = 'com.inbody2014.inbody';
      final days = [16, 18, 20, 23, 25, 27, 30].map((d) => DateTime(2026, 11, d)).toList()
        ..addAll([DateTime(2026, 12, 2), DateTime(2026, 12, 4)]);
      final kgs = [82.0, 81.9, 81.8, 81.6, 81.5, 81.4, 81.2, 81.1, 80.9];
      final s = HealthStore()
        ..data = Dashboard.fromJson({
          ...sampleDashboardJson(now),
          'body': [
            for (var i = 0; i < days.length; i++)
              {
                'time': DateTime(days[i].year, days[i].month, days[i].day, 7, 30).millisecondsSinceEpoch,
                'weight': kgs[i],
                'fatPct': 27.0,
                'app': inbody,
              },
          ],
        });
      s.history = sampleHistory(now, s.data!);
      applyRecentRead(s.history, s.data!, plan: SourcePlan.samsungOnly);
      await _pump(t, TodayPage(store: s, food: sampleFoodStore(now), open: (_, [__]) {}, openSettings: () {}, now: now),
          size: const Size(360, 6000), textScale: 2.0);
      const text = 'Ζύγιση InBody $_dot${_nb}80,9${_nb}kg';
      final line = find.descendant(of: find.byKey(const ValueKey('today-weigh')), matching: find.text(text));
      expect(line, findsOneWidget);
      final top = _paragraphTop(t.renderObject<RenderParagraph>(line));
      expect(_dots(text, top).atEnd, 0);
      expect(top(text.indexOf('80')), top(text.length - 1), reason: '«80,9 kg» σε μία γραμμή');
      expect(_checkDots(text, size: 15, from: 100, to: 300, weight: FontWeight.w600), greaterThan(0));
    });
  });
}
