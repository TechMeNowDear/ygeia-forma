/// Βραδινή υπενθύμιση φαγητού (16/11): ΜΙΑ ειδοποίηση το βράδυ, μόνο όταν η μέρα έχει πολύ λίγο φαγητό γραμμένο.
///
/// Τίποτα δεν τρέχει στο παρασκήνιο. Κάθε φορά που αλλάζει το ημερολόγιο (ή ανοίγει η εφαρμογή) υπολογίζεται εδώ ΑΝ
/// χρειάζεται υπενθύμιση και ΠΟΤΕ ([nextReminder]), και το Android κρατά ένα ξυπνητήρι (FoodReminder.kt). Αν η μέρα
/// συμπληρωθεί ή πατήσεις «Τελείωσα για σήμερα», το ξυπνητήρι πάει για αύριο.
///
/// «Πολύ λίγο» = κάτω από το [fullDayShare] (60%) του στόχου: το ίδιο όριο με τον εβδομαδιαίο έλεγχο (μέρα κάτω από αυτό
/// δεν μετρά, γιατί συνήθως κάτι δεν γράφτηκε).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../format.dart' show thousands;
import '../goals.dart' show fullDayShare;
import '../history.dart' show dateKey;
import 'food_model.dart';
import 'food_store.dart';

/// Προτεινόμενη ώρα: 21:30 (μετά το βραδινό των περισσότερων· πριν από τον ύπνο).
const remindDefaultMinutes = 21 * 60 + 30;

const remindTitle = 'Φαγητό σήμερα';

/// Πότε και τι λέει η επόμενη υπενθύμιση. [kcalToday]: όσα γράφτηκαν σήμερα. [target]: ο στόχος θερμίδων (null: χωρίς
/// στόχο → μόνο αν δεν γράφτηκε τίποτα).
({DateTime at, String text}) nextReminder({
  required DateTime now,
  required int atMinutes,
  required double kcalToday,
  required double? target,
  required DayMark? markToday,
}) {
  final today = DateTime(now.year, now.month, now.day);
  // Ώρα τοίχου (όχι «μεσάνυχτα + λεπτά»): τις μέρες που αλλάζει η ώρα έρχεται και πάλι στις 21:30 (έλεγχος 16/11).
  final todayAt = DateTime(now.year, now.month, now.day, atMinutes ~/ 60, atMinutes % 60);
  final low = target == null || target <= 0 ? kcalToday <= 0 : kcalToday < target * fullDayShare;
  if (now.isBefore(todayAt) && markToday == null && low) {
    return (at: todayAt, text: reminderText(kcalToday, target));
  }
  // Αύριο: αν ως τότε δεν ανοίξει η εφαρμογή, δεν θα έχει γραφτεί τίποτα.
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  return (
    at: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, atMinutes ~/ 60, atMinutes % 60),
    text: reminderText(0, target),
  );
}

String reminderText(double kcal, double? target) {
  if (kcal <= 0) {
    return 'Δεν έχεις γράψει φαγητό σήμερα. Αν έφαγες, γράψ’ το τώρα που το θυμάσαι.';
  }
  final t = target == null || target <= 0 ? '' : ' (στόχος ${thousands(target.round())})';
  return 'Σήμερα έχεις γράψει ${thousands(kcal.round())} kcal$t. Λείπει κάτι; Αν όχι, πάτα «Τελείωσα για σήμερα».';
}

/// Κρατά το ξυπνητήρι του Android σύμφωνο με το ημερολόγιο. Ένα κάλεσμα στο κανάλι μόνο όταν αλλάζει κάτι.
class FoodReminderLink with WidgetsBindingObserver {
  FoodReminderLink(this.food, {required this.target});
  final FoodStore food;

  /// Ο στόχος θερμίδων τώρα (null: δεν έχει οριστεί).
  final double? Function() target;

  static const _channel = MethodChannel('ygeia/food');
  Timer? _debounce;
  String? _last;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    food.addListener(_changed);
    _changed();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _changed();
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), _sync);
  }

  Future<void> _sync() async {
    if (!food.loaded || !food.dishesRead) return;
    final at = food.remindAt;
    if (at == null) {
      if (_last != 'off') {
        _last = 'off';
        await _invoke('remindCancel');
      }
      return;
    }
    final now = DateTime.now();
    final r = nextReminder(
      now: now,
      atMinutes: at,
      kcalToday: Totals(food.entriesFor(now)).kcal,
      target: target(),
      markToday: food.dayMark(now),
    );
    final key = '${r.at.millisecondsSinceEpoch}|${r.text}|${dateKey(now)}';
    if (key == _last) return;
    _last = key;
    // Έλεγχος 20/11 (K6C-02): «next» = το κείμενο της επόμενης μέρας, αν η εφαρμογή δεν ανοίξει ως τότε (τότε δεν θα
    // έχει γραφτεί τίποτα): το Android ξαναβάζει μόνο του την υπενθύμιση όταν χτυπήσει (FoodReminder.kt).
    await _invoke('remindSet', {
      'at': r.at.millisecondsSinceEpoch,
      'title': remindTitle,
      'text': r.text,
      'next': reminderText(0, target()),
    });
  }

  static Future<Map<String, dynamic>> _invoke(String m, [Map<String, Object>? args]) async {
    try {
      final raw = await _channel.invokeMethod<String>(m, args);
      final d = raw == null ? null : jsonDecode(raw);
      return d is Map<String, dynamic> ? d : const {};
    } on PlatformException {
      return const {};
    } on MissingPluginException {
      return const {};
    }
  }

  /// Μπορεί να δείξει ειδοποιήσεις; (Android 13+: η άδεια «Ειδοποιήσεις».)
  static Future<bool> canNotify() async => (await _invoke('remindCanNotify'))['canNotify'] == true;
}
