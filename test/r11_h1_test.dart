// Round 11 · h1 (φαγητό, «Αναφορά για έλεγχο», κείμενα, CI): R11-C1-1, R11-C1-2, R11-C1-3, R11-C2-1, R11-C2-2, R11-C2-3,
// R11-C4-1, R11-C4-2 (το (1) του R11-C4-2 στην Kotlin: R11H1Test.kt). Όλες οι αναμενόμενες τιμές βγήκαν με το χέρι (python)
// από τον γραμμένο κανόνα και τις τιμές της βάσης, όχι από τον κώδικα. Προϊόντα, στόχοι και άνθρωπος φανταστικά.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart' show Dashboard, HealthStore;
import 'package:ygeia_forma/diagnostics.dart' show diagnosticsFrom;
import 'package:ygeia_forma/exercise/ex_data.dart' show ExLibrary;
import 'package:ygeia_forma/exercise/ex_player.dart' show ExClock;
import 'package:ygeia_forma/food/chol.dart' show CholDay, isLegumes;
import 'package:ygeia_forma/food/food_model.dart' show CholKind, Food, LogEntry, Meal, NValue, Nk, Nutrients, Totals;
import 'package:ygeia_forma/food/food_store.dart' show FoodStore;
import 'package:ygeia_forma/food/kitchen.dart' show Cookware;
import 'package:ygeia_forma/food/off.dart' show FoodDraft, dryStapleRawId, legumesByName, myFoodsCategory;
import 'package:ygeia_forma/format.dart' show dotJoin;
import 'package:ygeia_forma/goals.dart' show GoalAim, Goals;
import 'package:ygeia_forma/history.dart' show K, dateKey;
import 'package:ygeia_forma/pages/food_add.dart' show FoodFormScreen, foodTileSubtitle;
import 'package:ygeia_forma/pages/nutrition_goals.dart' show GoalsSummaryCard, satVerdict;
import 'package:ygeia_forma/pages/training/today_training_card.dart' show TodayTrainingCard;
import 'package:ygeia_forma/pages/training/training_page.dart' show TrainingPage;
import 'package:ygeia_forma/pages/week_card.dart' show WeekCard;
import 'package:ygeia_forma/profile.dart' show Profile;
import 'package:ygeia_forma/theme.dart' show buildTheme;
import 'package:ygeia_forma/trends.dart' show TrendResult, TrendStatus, metricDef;
import 'package:ygeia_forma/weekly.dart' show WeekReview;

import 'sample_checkin.dart' show bodyJson, checkinGoals, simWeights;
import 'sample_data.dart' show sampleDashboardJson, sampleHistory;
import 'sample_food.dart' show basicFoods;
import 'training_sample.dart' show sampleTraining;

/// Το φανταστικό προφίλ των δοκιμών (R11-FIX): άνδρας, 180 cm, γεννημένος 12/1985.
const _me = Profile(birthYear: 1985, birthMonth: 12, sex: 'm', heightCm: 180);

const _dot = '\u00B7';
const _nb = '\u00A0';

/// Σάββατο 28/11/2026, μεσημέρι (στόχοι από Δευτέρα 16/11: η πρώτη μέρα που μετρά στη διόρθωση είναι η 23/11).
final _at = DateTime(2026, 11, 28, 12);

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

/// Φανταστικό τρόφιμο της βάσης με τιμές ανά 100 g.
Food _f(String id, Map<String, double> n) => Food(
      id: id,
      name: 'Τρόφιμο $id',
      cat: 'Άλλα',
      source: 'CIQUAL 2025',
      n: Nutrients({for (final e in n.entries) e.key: NValue(e.value)}),
    );

/// Δικό μου προϊόν (από ετικέτα).
Food _mine(String id, String name, Map<String, double> n, {String? ck}) => Food(
      id: id,
      name: name,
      cat: myFoodsCategory,
      source: 'Ετικέτα',
      cholKind: ck,
      n: Nutrients({for (final e in n.entries) e.key: NValue(e.value)}),
    );

var _seq = 0;
LogEntry _le(DateTime d, Food f, double grams) => LogEntry(
      id: 'r11h1-${_seq++}',
      day: dateKey(d),
      meal: Meal.lunch,
      food: f,
      grams: grams,
      time: DateTime(d.year, d.month, d.day, 13),
    );

HealthStore _store(Goals g) {
  final s = HealthStore()..data = Dashboard.fromJson({...sampleDashboardJson(_at), 'body': bodyJson(simWeights(_at))});
  s
    ..history = sampleHistory(_at, s.data!)
    ..setProfile(_me)
    ..setGoals(g);
  return s;
}

/// Οι μέρες της «Αναφοράς για έλεγχο» με φαγητό [kcal] (και [sat] g κορεσμένα) τη μέρα d του Νοεμβρίου 2026.
Map<String, Map> _reportDays(Goals g, Map<int, (double, double)> food) {
  final store = FoodStore.preloaded(foods: basicFoods(), now: _at, entries: [
    for (final e in food.entries)
      _le(DateTime(2026, 11, e.key), _f('D${e.key}', {Nk.kcal: e.value.$1, Nk.satFat: e.value.$2}), 100),
  ]);
  final r = diagnosticsFrom(store: _store(g), food: store, now: _at);
  return {for (final d in (r['calc'] as Map)['days'] as List) (d as Map)['d'] as String: d};
}

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

/// Πόσα «·» του [s] ΤΕΛΕΙΩΝΟΥΝ γραμμή (ο επόμενος χαρακτήρας που δεν είναι κενό είναι σε άλλη γραμμή) και πόσα ΑΡΧΙΖΟΥΝ
/// γραμμή (ο προηγούμενος είναι σε άλλη γραμμή).
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

/// Ο κανόνας του R11-C2-3 για το [s], στοιχισμένο με Inter [size] (ύψος 1,4) σε κάθε πλάτος από [from] ως [to]: κανένα «·»
/// στο τέλος γραμμής. Επιστρέφει σε πόσα πλάτη κάποιο «·» βρέθηκε στην ΑΡΧΗ γραμμής (η γραμμή έσπασε πριν από αυτό).
int _checkDots(String s, {double size = 13, int from = 140, int to = 420}) {
  var startsLine = 0;
  for (var w = from; w <= to; w++) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontFamily: 'Inter', fontSize: size, height: 1.4)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w.toDouble());
    final d = _dots(s, _painterTop(tp));
    tp.dispose();
    expect(d.atEnd, 0, reason: 'πλάτος $w: γραμμή που τελειώνει σε «$_dot» στο «$s»');
    if (d.atStart > 0) startsLine++;
  }
  return startsLine;
}

TrendResult _trend(String key, double current, {required bool inconclusive}) => TrendResult(
      def: metricDef(key)!,
      status: TrendStatus.stable,
      current: current,
      previous: current,
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

void main() {
  // Τα πλάτη μετριούνται με το Inter της εφαρμογής (όχι με τη γραμματοσειρά δοκιμών), όπως στο r9_f7.
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
  });

  // ---------------------------------------------------------------------------------------------------------------- C1-1
  group('R11-C1-1: «countsForAdaptive» με τον κανόνα της διόρθωσης θερμίδων', () {
    test('πριν από τους στόχους, πρώτη εβδομάδα, κάτω από 60%, πάνω από 2,5 × TDEE, σήμερα: δεν μετρούν', () {
      // checkinGoals: στόχοι από 16/11, τύπος 2.250 kcal (60% = 1.350), TDEE 1.830 × 1,5 = 2.745 → όριο «αδύνατης» μέρας
      // max(6.000, 2,5 × 2.745) = 6.862,5. Μετρούν οι μέρες από 23/11 (16/11 + 7) ως χθες (27/11).
      final days = _reportDays(checkinGoals(), {
        14: (1800.0, 10.0), // πριν από τους στόχους
        16: (1800.0, 10.0), // πρώτη μέρα των στόχων
        22: (1800.0, 10.0), // τελευταία μέρα της πρώτης εβδομάδας
        23: (1800.0, 10.0), // η πρώτη μέρα που μετρά
        24: (1300.0, 10.0), // κάτω από 1.350
        25: (7000.0, 10.0), // πάνω από 6.862,5 (λάθος ποσότητα)
        26: (6800.0, 10.0), // κάτω από 6.862,5: μετρά (το όριο δεν είναι το σκέτο 6.000)
        27: (1360.0, 10.0),
        28: (1800.0, 10.0), // σήμερα: δεν έχει τελειώσει
      });
      expect(days.keys.toList(), [for (final d in [14, 16, 22, 23, 24, 25, 26, 27, 28]) '2026-11-$d']);
      expect([for (final d in days.values) d['countsForAdaptive']], [false, false, false, true, false, false, true, true, false]);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- C1-2
  group('R11-C1-2: κορεσμένα: η αναφορά λέει τον κανόνα και την ετυμηγορία της Διατροφής', () {
    Totals tot(double kcal, double sat) => Totals([_le(DateTime(2026, 11, 24), _f('T$kcal-$sat', {Nk.kcal: kcal, Nk.satFat: sat}), 100)]);

    test('satVerdict: μέρα που πέρασε με πλήρη καταγραφή → %, αλλιώς γραμμάρια', () {
      // Στόχος 2.250 με οδηγία γιατρού (έως 6%)· πλήρης μέρα από 1.350 kcal.
      final g = checkinGoals();
      final a = satVerdict(tot(2000, 14), g, today: false, day: DateTime(2026, 11, 24));
      // 14 × 9 / 2.000 = 6,3% > 6%, ενώ 14,0 g < 15,0 g.
      expect((a.pctDay == null ? null : double.parse(a.pctDay!.toStringAsFixed(1)), a.over), (6.3, true));
      final b = satVerdict(tot(2600, 16), g, today: false, day: DateTime(2026, 11, 25));
      // 16 × 9 / 2.600 = 5,54% → «5,5%», εντάξει, ενώ 16,0 g > 15,0 g.
      expect((b.pctDay == null ? null : double.parse(b.pctDay!.toStringAsFixed(1)), b.over), (5.5, false));
      // Σήμερα: πάντα γραμμάρια (πόσα «χωράνε» ακόμα): 14,0 g / έως 15,0 g.
      final c = satVerdict(tot(2000, 14), g, today: true, day: DateTime(2026, 11, 28));
      expect((c.pctDay, c.limitG, c.overG, c.over), (null, 15.0, -1.0, false));
      // Μέρα που πέρασε με λίγη καταγραφή (1.000 < 1.350): γραμμάρια, 16,0 − 15,0 = 1,0 g πάνω.
      final d = satVerdict(tot(1000, 16), g, today: false, day: DateTime(2026, 11, 26));
      expect((d.pctDay, d.limitG, d.overG, d.over), (null, 15.0, 1.0, true));
    });

    test('η αναφορά: «sat» ανά μέρα, «satLimit» μόνο όπου η οθόνη κρίνει με γραμμάρια', () {
      final days = _reportDays(checkinGoals(), {
        14: (2000.0, 14.0), // πριν από τους στόχους: τίποτα
        24: (2000.0, 14.0),
        25: (2600.0, 16.0),
        26: (1000.0, 16.0),
        28: (2000.0, 14.0),
      });
      Object? sat(int d) => days['2026-11-$d']!['sat'];
      Object? limit(int d) => days['2026-11-$d']!['satLimit'];
      expect((sat(14), limit(14)), (null, null));
      // Πριν: «satLimit» 15,0 και «satFat» 14,0 → «κάτω από το όριο», ενώ η οθόνη λέει «Πάνω από το 6%».
      expect(sat(24), {'rule': 'pct', 'shown': 6.3, 'limitPct': 6, 'over': true});
      expect(limit(24), isNull);
      expect(sat(25), {'rule': 'pct', 'shown': 5.5, 'limitPct': 6, 'over': false});
      expect(limit(25), isNull);
      expect(sat(26), {'rule': 'g', 'shown': 16.0, 'limit': 15.0, 'over': true});
      expect(limit(26), 15.0);
      expect(sat(28), {'rule': 'g', 'shown': 14.0, 'limit': 15.0, 'over': false});
      expect(limit(28), 15.0);
    });

    test('όριο σε γραμμάρια μιας μέρας που πέρασε: ο στόχος που ίσχυε τότε (2.250 → 15,0· 2.340 → 15,6)', () {
      // Όπως στο r10_g1: δικός σου 2.340 την Τετ 25/11 το βράδυ, 2.160 σήμερα το πρωί (60% = 1.296).
      final g1 = checkinGoals(kcalSet: 2340).recordChangeFrom(checkinGoals(), DateTime(2026, 11, 25, 20));
      final g2 = checkinGoals(kcalSet: 2160).recordChangeFrom(g1, DateTime(2026, 11, 28, 9));
      final days = _reportDays(g2, {23: (1000.0, 10.0), 27: (1000.0, 10.0), 28: (1000.0, 10.0)});
      expect([for (final d in days.values) d['satLimit']], [15.0, 15.6, 14.4]);
      expect([for (final d in days.values) (d['sat'] as Map)['limit']], [15.0, 15.6, 14.4]);
    });

    testWidgets('η κάρτα της Διατροφής λέει το ίδιο με την αναφορά', (t) async {
      final g = checkinGoals();
      Future<void> card(double kcal, double sat, int day) => _pump(
          t,
          SingleChildScrollView(
              child: GoalsSummaryCard(
                  key: ValueKey('$kcal-$sat-$day'),
                  totals: tot(kcal, sat),
                  goals: g,
                  today: false,
                  health: HealthStore(),
                  day: DateTime(2026, 11, day))));
      await card(2000, 14, 24);
      expect(find.text('Πάνω από το 6% των θερμίδων που έφαγες'), findsOneWidget);
      await card(2600, 16, 25);
      expect(find.textContaining('των θερμίδων που έφαγες'), findsNothing);
      expect(find.textContaining('πάνω από το όριο'), findsNothing);
      await card(1000, 16, 26);
      expect(find.text('1 g πάνω από το όριο'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- C1-3
  group('R11-C1-3: δικό μου ξερό όσπριο χωρίς «μετρά ως»: ξερό και βρασμένο μετρούν το ίδιο', () {
    Food lentils({String? ck}) =>
        _mine('ML', 'Φακές ψιλές Χ', {Nk.kcal: 334, Nk.protein: 24, Nk.carbs: 50, Nk.fat: 2, Nk.fiber: 8}, ck: ck);
    final today = DateTime(2026, 11, 20);

    test('ποια προϊόντα μετρούν «Όσπρια» από το όνομα', () {
      expect(legumesByName(lentils()), isTrue);
      // Κάθε ξερό όσπριο που βρίσκει το όνομα είναι «Όσπρια» στη βάση.
      for (final name in ['Φακές ψιλές', 'Ρεβίθια χοντρά', 'Φάβα Σαντορίνης', 'Μαυρομάτικα', 'Γίγαντες Πρεσπών', 'Φασόλια μέτρια']) {
        final p = _mine('MX', name, {Nk.kcal: 340});
        expect(legumesByName(p), isTrue, reason: name);
        final base = basicFoods().firstWhere((f) => f.id == dryStapleRawId(p));
        expect(base.cat, 'Όσπρια', reason: name);
      }
      expect(legumesByName(_mine('MP', 'Fusilli κόκκινες φακές', {Nk.kcal: 334})), isFalse, reason: 'ζυμαρικό (R10-B1-3)');
      expect(legumesByName(_mine('MK', 'Φακές κονσέρβα', {Nk.kcal: 90})), isFalse, reason: 'μαγειρεμένο: όπως πριν');
      expect(legumesByName(_mine('MR', 'Ρύζι κίτρινο', {Nk.kcal: 350})), isFalse);
      expect(legumesByName(basicFoods().firstWhere((f) => f.id == 'C20359')), isFalse, reason: 'της βάσης: από την κατηγορία');
    });

    test('80 g ξερές ή 200 g «Βρασμένες»: η ίδια μέρα «Όσπρια» (40 g ξερά = μία φορά)', () {
      for (final ck in [null, CholKind.legumes]) {
        final p = lentils(ck: ck);
        final states = FoodStore.preloaded(foods: basicFoods(), mine: [p], now: today).statesOf(p);
        expect(states.length, 2, reason: '$ck');
        final dry = CholDay([_le(today, states[0].$1, 80)]);
        final cooked = CholDay([_le(today, states[1].$1, 200)]);
        // Πριν, με ck null: ξερές 0 g («Τα προϊόντα μου» δεν είναι «Όσπρια»), βρασμένες 200 ÷ 2,5 = 80 g.
        expect((dry.legumes, dry.legumesDryG), (true, 80.0), reason: '$ck');
        expect((cooked.legumes, cooked.legumesDryG), (true, 80.0), reason: '$ck');
      }
      // «Τίποτα» που το διάλεξες: ισχύει (κανένα όνομα δεν το αλλάζει, R7-A3-1).
      expect(isLegumes(lentils(ck: CholKind.none)), isFalse);
    });

    testWidgets('φόρμα: χωρίς επιλογή δείχνει «Όσπρια» (αυτό θα μετρήσει) και το προϊόν μετρά', (t) async {
      Food? saved;
      await _pump(
        t,
        Builder(
          builder: (ctx) => Center(
            child: TextButton(
              onPressed: () async {
                saved = await Navigator.of(ctx).push<Food>(MaterialPageRoute(
                    builder: (_) => FoodFormScreen(
                        draft: FoodDraft(
                            name: 'Φακές ψιλές Χ',
                            values: {Nk.kcal: 334, Nk.protein: 24, Nk.carbs: 50, Nk.fat: 2, Nk.fiber: 8}),
                        cholChoice: true)));
              },
              child: const Text('άνοιξε'),
            ),
          ),
        ),
      );
      await t.tap(find.text('άνοιξε'));
      await t.pumpAndSettle();
      ChoiceChip chip(String label) => t.widget<ChoiceChip>(find.ancestor(
          of: find.descendant(of: find.byKey(const ValueKey('chol-kind')), matching: find.text(label)), matching: find.byType(ChoiceChip)));
      expect(chip('Όσπρια').selected, isTrue);
      expect(chip('Τίποτα').selected, isFalse);
      await t.ensureVisible(find.text('Αποθήκευση'));
      await t.tap(find.text('Αποθήκευση'));
      await t.pumpAndSettle();
      expect(saved!.cholKind, isNull, reason: 'όπως το πίτουρο από το όνομα: δεν αποθηκεύεται, ακολουθεί το όνομα');
      expect(isLegumes(saved!), isTrue);
    });

    testWidgets('φόρμα: ζυμαρικό από όσπρια δείχνει «Τίποτα», όπως μετρά', (t) async {
      await _pump(
          t,
          FoodFormScreen(
              draft: FoodDraft(name: 'Fusilli κόκκινες φακές', values: {Nk.kcal: 334, Nk.protein: 24, Nk.carbs: 50, Nk.fat: 2}),
              cholChoice: true));
      ChoiceChip chip(String label) => t.widget<ChoiceChip>(find.ancestor(
          of: find.descendant(of: find.byKey(const ValueKey('chol-kind')), matching: find.text(label)), matching: find.byType(ChoiceChip)));
      expect(chip('Τίποτα').selected, isTrue);
      expect(chip('Όσπρια').selected, isFalse);
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- C2-1
  group('R11-C2-1: «Η εβδομάδα σου»: ο αριθμός με τη μονάδα του στη διάρκεια', () {
    WeekReview week({required bool inconclusive}) => WeekReview(
          monday: DateTime(2026, 11, 9),
          sunday: DateTime(2026, 11, 15),
          items: [
            _trend(K.sleepMin, 433, inconclusive: inconclusive), // 7 ώρες 13 λεπτά
            _trend(K.activeMin, 85, inconclusive: inconclusive), // 1 ώρα 25 λεπτά
          ],
        );
    final unit = RegExp('\\d+[ \u00A0](?:ώρες|ώρα|λεπτά|λεπτό)');

    testWidgets('ανοιχτό Fold (κάρτα 596 dp, δύο στήλες): «7 ώρες | 13 λεπτά», ποτέ «7 ώρες 13 | λεπτά»', (t) async {
      // 1× με «Λίγες μέρες για συμπέρασμα» (στήλη ~121 dp) και 1,3× με «Σταθερό» (στήλη ~155 dp): τα δύο σενάρια του ευρήματος.
      for (final (scale, inconclusive) in [(1.0, true), (1.3, false)]) {
        await _pump(
          t,
          Align(alignment: Alignment.topLeft, child: SizedBox(width: 596, child: WeekCard(review: week(inconclusive: inconclusive)))),
          size: const Size(700, 2000),
          textScale: scale,
        );
        final values = <String>[];
        for (final e in find.descendant(of: find.byType(WeekCard), matching: find.byType(RichText)).evaluate()) {
          final p = e.renderObject! as RenderParagraph;
          final s = p.text.toPlainText();
          if (s.startsWith('4 προηγούμενες') || !s.startsWith(RegExp('\\d'))) continue;
          values.add(s);
          final top = _paragraphTop(p);
          for (final m in unit.allMatches(s)) {
            expect(top(m.start), top(m.end - 1), reason: '×$scale: «${m.group(0)}» σε δύο γραμμές στο «$s»');
          }
        }
        expect(values, containsAll(['7\u00A0ώρες 13\u00A0λεπτά', '1\u00A0ώρα 25\u00A0λεπτά']), reason: '×$scale');
      }
    });

    test('σε κάθε πλάτος 80–200 px (Inter έντονα 16): ο αριθμός μένει με τη λέξη του', () {
      for (final s in ['7\u00A0ώρες 13\u00A0λεπτά', '1\u00A0ώρα 25\u00A0λεπτά']) {
        var wrapped = false;
        // Από 80 px: το μεγαλύτερο αδιάσπαστο κομμάτι («25 λεπτά») έχει ~73 px· πιο στενά σπάει αναγκαστικά μέσα του.
        for (var w = 80; w <= 200; w++) {
          final tp = TextPainter(
            text: TextSpan(text: s, style: const TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w700)),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: w.toDouble());
          final top = _painterTop(tp);
          if (tp.computeLineMetrics().length > 1) wrapped = true;
          for (final m in unit.allMatches(s)) {
            expect(top(m.start), top(m.end - 1), reason: 'πλάτος $w: «${m.group(0)}»');
          }
          tp.dispose();
        }
        expect(wrapped, isTrue, reason: 'το «$s» σπάει σε κάποιο πλάτος (αλλιώς η δοκιμή δεν ελέγχει τίποτα)');
      }
    });
  });

  // ---------------------------------------------------------------------------------------------------------- C2-2 / C2-3
  group('R11-C2-2 / R11-C2-3 / R11-C4-2 (3): ένας κανόνας για το «·»: ποτέ στο τέλος γραμμής', () {
    setUp(() => ExClock.frozen = true);
    tearDown(() => ExClock.frozen = false);

    Future<void> page(WidgetTester t, DateTime at) async {
      await t.runAsync(() => ExLibrary.load(inline: true));
      await _pump(t, TrainingPage(training: sampleTraining(at), now: at), size: const Size(400, 4000));
    }

    test('ο κανόνας: κανονικό κενό πριν από το «·», αδιάσπαστο μετά', () {
      expect(dotJoin, ' $_dot$_nb');
    });

    testWidgets('Άσκηση › Προπόνηση, μέρα βαρών (Παρασκευή 13/11): «6 ασκήσεις ·\u00A0περίπου N\u00A0λεπτά»', (t) async {
      await page(t, DateTime(2026, 11, 13, 17, 30));
      // Πριν (R11-C2-2): «6 ασκήσεις · περίπου 55 λεπτά» με κανονικά κενά (με μεγάλα γράμματα «… περίπου 55» / «λεπτά»).
      final line = find.textContaining(RegExp('^6 ασκήσεις $_dot${_nb}περίπου \\d+${_nb}λεπτά\$'));
      expect(line, findsOneWidget);
      _checkDots(t.widget<Text>(line).data!);
    });

    testWidgets('Άσκηση › Προπόνηση, μέρα περπατήματος (Τρίτη 17/11): η γραμμή «train-cardio-line»', (t) async {
      await page(t, DateTime(2026, 11, 17, 17, 30));
      final s = t.widget<Text>(find.byKey(const ValueKey('train-cardio-line'))).data!;
      // Το R10-B8-B1 της σελίδας Άσκηση δεν το έλεγχε καμία δοκιμή (R11-C4-2): «30 λεπτά» αδιάσπαστο και ο κανόνας του «·».
      expect(s, '30${_nb}λεπτά $_dot${_nb}χαλαρά, να μπορείς να μιλάς');
      _checkDots(s);
    });

    testWidgets('κάρτα «Άσκηση σήμερα» (Τρίτη 17/11, 400 dp): όπως ζωγραφίστηκε, το «·» δεν τελειώνει γραμμή', (t) async {
      final at = DateTime(2026, 11, 17, 17, 30);
      await t.runAsync(() => ExLibrary.load(inline: true));
      await _pump(t, SingleChildScrollView(child: TodayTrainingCard(training: sampleTraining(at), now: at)), size: const Size(400, 2400));
      final line = find.textContaining(RegExp('^30${_nb}λεπτά '));
      expect(line, findsOneWidget);
      final s = t.widget<Text>(line).data!;
      // Η γραμμή του στιγμιότυπου TT5: πριν «30 λεπτά · χαλαρά, να μπορείς να μιλάς ·» / «όριο παλμών 140».
      expect(s, '30${_nb}λεπτά $_dot${_nb}χαλαρά, να μπορείς να μιλάς $_dot${_nb}όριο${_nb}παλμών${_nb}140');
      final p = t.renderObject<RenderParagraph>(line);
      expect(_dots(s, _paragraphTop(p)).atEnd, 0);
      // Σε κάθε πλάτος 140–420 px: το «·» ποτέ στο τέλος· και σε κάποια πλάτη η γραμμή σπάει ΠΡΙΝ από αυτό.
      expect(_checkDots(s), greaterThan(0));
    });

    test('τρόφιμα (foodTileSubtitle) και σκεύη (Cookware.label): ο ίδιος κανόνας', () {
      final f = _f('S', {Nk.kcal: 125, Nk.protein: 10.1});
      final sub = foodTileSubtitle(f, 6);
      expect(sub, '125${_nb}kcal $_dot${_nb}πρωτεΐνη 10,1${_nb}g ανά 100${_nb}g $_dot${_nb}6${_nb}φορές');
      expect(_checkDots(sub, from: 100), greaterThan(0));
      final pan = Cookware(id: 'c1', kind: 'panNonstick', size: 'Μικρό', brand: 'Tefal').label;
      expect(pan, 'Τηγάνι αντικολλητικό $_dot${_nb}μικρό $_dot${_nb}Tefal');
      // Από 120 px: το «αντικολλητικό» (Inter 16) έχει ~110 px.
      expect(_checkDots(pan, size: 16, from: 120, to: 300), greaterThan(0));
    });
  });

  // ---------------------------------------------------------------------------------------------------------------- C4-2
  test('R11-C4-2 (2): «formula.satMax» με ένα δεκαδικό όταν δεν είναι ακέραιο (2.290 kcal × 6% ÷ 9 = 15,3 g)', () {
    // Άνδρας 40, 180 cm, 94 kg, «λιγότερο λίπος» 0,5%/εβδ., δραστηριότητα 1,5, γιατρός: BMR 940 + 1.125 − 200 + 5 = 1.870,
    // TDEE 2.805, −94 × 0,005 × 7.700 ÷ 7 = −517 → 2.288 → 2.290. Πριν: (2.290 × 6 / 100 / 9).round() = 15, και στη Dart
    // 15 == 15.0, άρα η δοκιμή του r10_g1 (2.250 → 15,0) δεν έπιανε την επαναφορά.
    final g = Goals(
        aim: GoalAim.lose, rate: 0.005, activity: 1.5, doctor: true, since: '2026-11-16', kg: 94, age: 40, heightCm: 180, male: true);
    final r = diagnosticsFrom(store: _store(g), food: FoodStore.preloaded(foods: basicFoods(), now: _at), now: _at);
    final goals = (r['calc'] as Map)['goals'] as Map;
    final formula = goals['formula'] as Map;
    expect((formula['kcal'], formula['satMax']), (2290, 15.3));
    expect((goals['inForce'] as Map)['satMax'], 15.3);
  });

  // ---------------------------------------------------------------------------------------------------------------- C4-1
  for (final wf in ['.github/workflows/check.yml', '.github/workflows/android.yml']) {
    group('R11-C4-1: πύλη δοκιμών Dart ανά αρχείο και χωρίς skip ($wf)', () {
      late Directory dir;
      setUp(() => dir = Directory.systemTemp.createTempSync('r11h1'));
      tearDown(() => dir.deleteSync(recursive: true));

      final y = File(wf).readAsStringSync();
      final a = y.indexOf(r"n=$(grep -aoE '[0-9]+ tests passed' tests.log");
      // Η πύλη όπως ως το #109 (ως το «fi» του ελέγχου «όσες δηλώνονται») και μαζί με τους ελέγχους του γύρου 11 (ως το «fi»
      // μετά το «done» του ελέγχου ανά αρχείο).
      String before() {
        const declared = r'if [ "${n:-0}" -lt "${want:-0}" ]; then';
        final b = y.indexOf(declared, a);
        return y.substring(a, y.indexOf('fi', b + declared.length) + 2);
      }

      String after() {
        final loop = y.indexOf(r'for f in $files; do', a);
        expect(loop, greaterThan(a), reason: '$wf: ο έλεγχος ανά αρχείο');
        final done = y.indexOf('\n            done\n', loop);
        expect(done, greaterThan(loop), reason: wf);
        return y.substring(a, y.indexOf('fi', done + 1) + 2);
      }

      // Δύο αρχεία: το Α δηλώνει 1 δοκιμή σε βρόχο (τρέχουν N), το Β 6. Το N πάνω από το κατώτατο.
      final floor = int.parse(RegExp(r'if \[ "\$\{n:-0\}" -lt (\d+) \]; then').firstMatch(y)!.group(1)!);
      final n = floor + 100;
      const fa = 'test/f0_test.dart', fb = 'test/f1_test.dart';
      final files = {
        fa: "void main() {\n  for (var i = 0; i < 3000; i++) {\n    test('a', () {});\n  }\n}\n",
        fb: "void main() {\n${[for (var i = 0; i < 6; i++) "  test('b$i', () {});\n"].join()}}\n",
      };
      String ok(String file, int count, {String prefix = ''}) =>
          [for (var i = 0; i < count; i++) '$prefix✅ /home/runner/work/ygeia-forma/ygeia-forma/$file: δοκιμή $i\n'].join();

      ({int code, String out}) run(String gate, String log, {bool github = true}) {
        Directory('${dir.path}/test').createSync(recursive: true);
        for (final e in files.entries) {
          File('${dir.path}/${e.key}').writeAsStringSync(e.value);
        }
        File('${dir.path}/tests.log').writeAsStringSync(log);
        final list = files.keys.join(' ');
        final r = Process.runSync('bash', ['-e', '-c', 'set -o pipefail\nfiles="$list"\n$gate\n'],
            workingDirectory: dir.path,
            environment: {'GITHUB_ACTIONS': github ? 'true' : 'false'},
            stdoutEncoding: utf8,
            stderrEncoding: utf8);
        return (code: r.exitCode, out: '${r.stdout}');
      }

      test('όλα έτρεξαν (και μια δοκιμή μέσα σε «::group::»): πράσινο', () {
        final log = '${ok(fa, n)}${ok(fb, 1, prefix: '::group::')}::endgroup::\n${ok(fb, 5)}🎉 ${n + 6} tests passed.\n';
        final r = run(after(), log);
        expect(r.code, 0, reason: r.out);
      });

      test('6 δοκιμές με skip: πριν πράσινο (σύνολο ≥ δηλωμένες), τώρα κόκκινο', () {
        final log = '${ok(fa, n)}🎉 $n tests passed, 6 skipped.\n';
        expect(run(before(), log).code, 0, reason: 'η τρύπα του ευρήματος');
        final r = run(after(), log);
        expect(r.code, isNot(0));
        expect(r.out, contains('skip'));
        // Και με τη μορφή εκτός GitHub («+N ~M: All tests passed!»).
        expect(run(after(), '00:40 +$n ~6: All tests passed!\n', github: false).code, isNot(0));
      });

      test('ένα αρχείο έτρεξε 5 από τις 6 δοκιμές του, χωρίς skip: τώρα κόκκινο', () {
        final log = '${ok(fa, n)}${ok(fb, 5)}🎉 ${n + 5} tests passed.\n';
        expect(run(before(), log).code, 0, reason: 'η τρύπα του ευρήματος');
        final r = run(after(), log);
        expect(r.code, isNot(0));
        expect(r.out, contains('$fb: πέρασαν 5 δοκιμές, ενώ το αρχείο δηλώνει 6'));
      });

      test('στο GitHub χωρίς γραμμές «✅» (άλλαξε ο reporter): κόκκινο· εκτός GitHub μόνο το σύνολο', () {
        expect(run(after(), '🎉 ${n + 6} tests passed.\n').code, isNot(0));
        expect(run(after(), '🎉 ${n + 6} tests passed.\n', github: false).code, 0);
        expect(run(after(), '00:40 +${n + 6}: All tests passed!\n', github: false).code, 0);
      });

      test('κατώτατο ≈ 3% κάτω από το #109 (2.203 έτρεξαν)', () {
        expect(floor, greaterThanOrEqualTo(2135));
        expect(floor, lessThan(2203));
      });
    });
  }
}
