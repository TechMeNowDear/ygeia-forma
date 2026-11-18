// «Τι συνδέεται με τον ύπνο σου» (18/11). Επινοημένα δεδομένα, χωρίς πραγματικά στοιχεία.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/history.dart';
import 'package:ygeia_forma/pages/sleep_links_card.dart';
import 'package:ygeia_forma/sleep_links.dart';
import 'package:ygeia_forma/sources.dart';
import 'package:ygeia_forma/theme.dart';

final _today = DateTime(2026, 12, 31);
final _plan = SourcePlan.samsungOnly;

/// Ψευδοτυχαίοι αριθμοί 0–1, ίδιοι σε κάθε εκτέλεση.
class _Rng {
  _Rng(this._s);
  int _s;
  double next() {
    _s = (_s * 1103515245 + 12345) & 0x7fffffff;
    return _s / 0x7fffffff;
  }
}

final _bread = Food(id: 'T-bread', name: 'Ψωμί (δοκιμή)', cat: 'Ψωμί', source: 'Ετικέτα', n: Nutrients({Nk.kcal: const NValue(250)}));

/// [nights] νύχτες ως σήμερα. [gapH]: ώρες από το τελευταίο φαγητό ως τον ύπνο, ανά νύχτα· [hr]: παλμοί ύπνου από αυτές.
({Map<String, Map<String, double>> history, Map<String, List<LogEntry>> food, Set<String> done}) _data(
  int nights, {
  required double Function(int i, _Rng r) gapH,
  required double Function(int i, double gap, _Rng r) hr,
  bool markDone = true,
  bool lateLog = false,
}) {
  final r = _Rng(7);
  final history = <String, Map<String, double>>{};
  final food = <String, List<LogEntry>>{};
  final done = <String>{};
  for (var i = 0; i < nights; i++) {
    final night = DateTime(_today.year, _today.month, _today.day - (nights - 1 - i));
    final prev = DateTime(night.year, night.month, night.day - 1);
    final bed = 300 + (r.next() * 60).round(); // 23:00–00:00 (λεπτά μετά τις 18:00)
    final gap = gapH(i, r);
    final bedAt = DateTime(prev.year, prev.month, prev.day, 18).add(Duration(minutes: bed));
    final ate = bedAt.subtract(Duration(minutes: (gap * 60).round()));
    history[dateKey(night)] = {K.bedtime: bed.toDouble(), K.sleepHr: hr(i, gap, r), K.sleepMin: 400 + r.next() * 60};
    history[dateKey(prev)] = {...?history[dateKey(prev)], K.steps: 6000 + r.next() * 4000};
    food[dateKey(prev)] = [
      LogEntry(id: 'l$i', day: dateKey(prev), meal: Meal.lunch, food: _bread, grams: 100,
          time: DateTime(prev.year, prev.month, prev.day, 14)),
      LogEntry(id: 'd$i', day: dateKey(prev), meal: Meal.dinner, food: _bread, grams: 100 + r.next() * 200,
          time: lateLog ? bedAt.add(const Duration(hours: 9)) : ate),
    ];
    if (markDone) done.add(dateKey(prev));
  }
  return (history: history, food: food, done: done);
}

SleepLinksResult _run(({Map<String, Map<String, double>> history, Map<String, List<LogEntry>> food, Set<String> done}) d) =>
    sleepLinks(
      history: d.history,
      plan: _plan,
      today: _today,
      entries: (day) => d.food[dateKey(day)] ?? const [],
      mark: (day) => d.done.contains(dateKey(day)) ? DayMark.done : null,
    );

void main() {
  test('κατανομή t: γνωστές τιμές', () {
    expect(studentTwoSidedP(2.228, 10), closeTo(0.0500, 0.0005));
    expect(studentTwoSidedP(2.0, 10), closeTo(0.0734, 0.0005));
    expect(studentTwoSidedP(3.0, 30), closeTo(0.0054, 0.0002));
    expect(studentTwoSidedP(0, 20), closeTo(1, 1e-9));
  });

  test('λιγότερες από 28 νύχτες: «μαζεύω», καμία κρίση', () {
    final r = _run(_data(20, gapH: (i, r) => 1 + r.next() * 4, hr: (i, g, r) => 58 + r.next() * 4));
    expect(r.ready, isFalse);
    expect(r.nights, 20);
  });

  test('καμία πραγματική σύνδεση: δεν βγαίνει «συνδέεται»', () {
    final r = _run(_data(84, gapH: (i, r) => 1 + r.next() * 4, hr: (i, g, r) => 58 + r.next() * 4));
    expect(r.ready, isTrue);
    expect(r.found, isEmpty);
  });

  test('φαγητό κοντά στον ύπνο → ψηλότεροι παλμοί: βρίσκεται, με τις δύο ομάδες', () {
    final r = _run(_data(84, gapH: (i, r) => 0.5 + r.next() * 4, hr: (i, g, r) => 56 + (g < 2.5 ? 4 : 0) + r.next() * 2));
    final l = r.found.singleWhere((l) => l.cause == LinkCause.mealGap && l.sleep == LinkSleep.sleepHr);
    expect(l.rho, lessThan(-0.25));
    expect(l.lowMean, greaterThan(l.highMean + 2));
    final (low, high) = linkGroups(l);
    expect(low, startsWith('Τελευταίο φαγητό ως '));
    expect(high, startsWith('Πάνω από '));
    expect(linkValues(l).$1, endsWith(' bpm'));
    expect(r.found.where((l) => l.cause == LinkCause.steps), isEmpty);
  });

  test('χωρίς «Τελείωσα για σήμερα» το φαγητό δεν μετρά', () {
    final r = _run(_data(84,
        markDone: false, gapH: (i, r) => 0.5 + r.next() * 4, hr: (i, g, r) => 56 + (g < 2.5 ? 4 : 0) + r.next() * 2));
    expect(r.links.where((l) => l.cause == LinkCause.mealGap || l.cause == LinkCause.dinnerKcal), isEmpty);
    expect(r.links.where((l) => l.cause == LinkCause.steps), isNotEmpty);
  });

  test('βραδινό γραμμένο μετά τον ύπνο: η ώρα δεν μετρά (οι θερμίδες μετρούν)', () {
    final r = _run(_data(84,
        lateLog: true, gapH: (i, r) => 0.5 + r.next() * 4, hr: (i, g, r) => 56 + (g < 2.5 ? 4 : 0) + r.next() * 2));
    expect(r.links.where((l) => l.cause == LinkCause.mealGap), isEmpty);
    expect(r.links.where((l) => l.cause == LinkCause.dinnerKcal), isNotEmpty);
  });

  testWidgets('κάρτα: «Μαζεύω νύχτες» χωρίς δεδομένα, και «Πώς το βρίσκω»', (t) async {
    final store = HealthStore();
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: SingleChildScrollView(child: SleepLinksCard(store: store, now: _today))),
    ));
    expect(find.text('Μαζεύω νύχτες: 0 από 28.'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('sleep-links-how')));
    await t.pump();
    expect(find.byKey(const ValueKey('sleep-links-how-text')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
