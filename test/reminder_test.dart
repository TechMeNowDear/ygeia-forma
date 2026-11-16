// Βραδινή υπενθύμιση (16/11): πότε και τι.
import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/food/food_model.dart';
import 'package:ygeia_forma/food/reminder.dart';

void main() {
  test('Λίγο φαγητό πριν τις 21:30 → σήμερα στις 21:30· αρκετό ή «Τελείωσα» → αύριο', () {
    final now = DateTime(2026, 11, 18, 15);
    final low = nextReminder(now: now, atMinutes: 1290, kcalToday: 600, target: 2090, markToday: null);
    expect(low.at, DateTime(2026, 11, 18, 21, 30));
    expect(low.text, contains('600 kcal'));
    final ok = nextReminder(now: now, atMinutes: 1290, kcalToday: 1500, target: 2090, markToday: null);
    expect(ok.at, DateTime(2026, 11, 19, 21, 30));
    expect(ok.text, contains('Δεν έχεις γράψει'));
    final marked = nextReminder(now: now, atMinutes: 1290, kcalToday: 300, target: 2090, markToday: DayMark.done);
    expect(marked.at, DateTime(2026, 11, 19, 21, 30));
    final late = nextReminder(now: DateTime(2026, 11, 18, 22), atMinutes: 1290, kcalToday: 0, target: 2090, markToday: null);
    expect(late.at, DateTime(2026, 11, 19, 21, 30));
  });

  test('Χωρίς στόχο: μόνο αν δεν γράφτηκε τίποτα', () {
    final now = DateTime(2026, 11, 18, 10);
    expect(nextReminder(now: now, atMinutes: 1290, kcalToday: 0, target: null, markToday: null).at.day, 18);
    expect(nextReminder(now: now, atMinutes: 1290, kcalToday: 100, target: null, markToday: null).at.day, 19);
  });

  test('Ώρα τοίχου τις μέρες που αλλάζει η ώρα (28/3/2027, 31/10/2027)', () {
    for (final d in [DateTime(2027, 3, 28, 9), DateTime(2027, 10, 31, 9), DateTime(2027, 3, 27, 23)]) {
      final r = nextReminder(now: d, atMinutes: 1290, kcalToday: 0, target: 2090, markToday: null);
      expect(r.at.hour, 21, reason: '$d');
      expect(r.at.minute, 30, reason: '$d');
    }
  });
}
