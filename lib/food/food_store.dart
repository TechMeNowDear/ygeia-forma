import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../format.dart';
import '../history.dart' show dateKey;
import 'food_channel.dart';
import 'food_model.dart';
import 'food_search.dart';

/// Η κατάσταση της Διατροφής: βάση τροφίμων, δικά μου τρόφιμα, ημερολόγιο.
/// Όλα τοπικά στο κινητό. Δίκτυο μόνο για το barcode (Open Food Facts).
class FoodStore extends ChangeNotifier {
  FoodStore() : _offline = false;

  /// Για δοκιμές και στιγμιότυπα: χωρίς κανάλι προς το Android.
  FoodStore.preloaded({required List<Food> foods, List<LogEntry> entries = const [], DateTime? now})
      : _offline = true {
    _basic = foods;
    _index = FoodIndex(foods);
    for (final e in entries) {
      _entries[e.id] = e;
    }
    if (now != null) day = dayOf(now);
    ready = true;
  }

  final bool _offline;
  bool ready = false;
  String? error;

  List<Food> _basic = const [];
  List<Food> _mine = const [];
  FoodIndex _index = FoodIndex(const []);
  final Map<String, LogEntry> _entries = {};

  /// Η μέρα που βλέπω στο ημερολόγιο.
  DateTime day = dayOf(DateTime.now());

  static const historyDays = 90;

  Future<void> start() async {
    try {
      final raw = await rootBundle.loadString('assets/foods/basic_foods.json');
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _basic = [for (final f in j['foods'] as List) Food.fromJson(Map<String, dynamic>.from(f as Map))];
    } catch (e) {
      error = 'Δεν φορτώθηκε η βάση τροφίμων: $e';
    }
    await _loadMine();
    await _loadEntries();
    _rebuildIndex();
    ready = true;
    notifyListeners();
  }

  Future<void> _loadMine() async {
    if (_offline) return;
    final r = await FoodChannel.myFoods();
    if (r['ok'] == true && r['foods'] is List) {
      _mine = [
        for (final f in r['foods'] as List)
          if (f is Map) Food.fromJson(Map<String, dynamic>.from(f)),
      ];
    }
  }

  Future<void> _loadEntries() async {
    if (_offline) return;
    final to = dayOf(DateTime.now());
    final from = DateTime(to.year, to.month, to.day - historyDays);
    final r = await FoodChannel.logRange(dateKey(from), dateKey(DateTime(to.year, to.month, to.day + 1)));
    if (r['ok'] == true && r['entries'] is List) {
      for (final e in r['entries'] as List) {
        if (e is! Map) continue;
        try {
          final le = LogEntry.fromJson(Map<String, dynamic>.from(e));
          _entries[le.id] = le;
        } catch (_) {}
      }
    }
  }

  void _rebuildIndex() => _index = FoodIndex([..._mine, ..._basic]);

  // ---------- Ανάγνωση ----------

  List<LogEntry> entriesFor(DateTime d, [Meal? meal]) {
    final k = dateKey(d);
    final list = _entries.values.where((e) => e.day == k && (meal == null || e.meal == meal)).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    return list;
  }

  /// Ημέρες με καταχωρίσεις (για «αντιγραφή από χθες» κ.λπ. αργότερα).
  bool hasEntries(DateTime d) => _entries.values.any((e) => e.day == dateKey(d));

  /// Πόσες φορές έχω φάει κάθε τρόφιμο τις τελευταίες 90 μέρες.
  Map<String, int> get _counts {
    final c = <String, int>{};
    for (final e in _entries.values) {
      c[e.food.id] = (c[e.food.id] ?? 0) + 1;
    }
    return c;
  }

  /// Πρόσφατα: τα τελευταία διαφορετικά τρόφιμα.
  List<Food> recent({int limit = 15}) {
    final sorted = _entries.values.toList()..sort((a, b) => b.time.compareTo(a.time));
    final seen = <String>{};
    final out = <Food>[];
    for (final e in sorted) {
      if (seen.add(e.food.id)) out.add(_current(e.food));
      if (out.length >= limit) break;
    }
    return out;
  }

  /// Συχνά: όσα έχω φάει τουλάχιστον 2 φορές, πιο συχνό πρώτο.
  List<Food> frequent({int limit = 15}) {
    final counts = _counts.entries.where((e) => e.value >= 2).toList()..sort((a, b) => b.value.compareTo(a.value));
    final latest = <String, LogEntry>{};
    for (final e in _entries.values) {
      final p = latest[e.food.id];
      if (p == null || e.time.isAfter(p.time)) latest[e.food.id] = e;
    }
    return [for (final c in counts.take(limit)) _current(latest[c.key]!.food)];
  }

  int timesEaten(String foodId) => _counts[foodId] ?? 0;

  /// Η ποσότητα της τελευταίας φοράς (έγγραφο › «ποσότητα από την τελευταία φορά»).
  double? lastGrams(String foodId) {
    LogEntry? last;
    for (final e in _entries.values) {
      if (e.food.id == foodId && (last == null || e.time.isAfter(last.time))) last = e;
    }
    return last?.grams;
  }

  /// Αν το τρόφιμο υπάρχει ακόμα στη βάση, η τρέχουσα μορφή του· αλλιώς το αντίγραφο.
  Food _current(Food f) {
    for (final x in _mine) {
      if (x.id == f.id) return x;
    }
    for (final x in _basic) {
      if (x.id == f.id) return x;
    }
    return f;
  }

  List<Food> search(String q) {
    final counts = _counts;
    return _index.search(q, boost: {for (final e in counts.entries) e.key: math.min(6, e.value * 1.5)});
  }

  Food? byBarcode(String code) {
    for (final f in _mine) {
      if (f.barcode == code) return f;
    }
    return null;
  }

  // ---------- Αλλαγές ----------

  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 20).toRadixString(36)}';

  Future<LogEntry> add(Food food, double grams, Meal meal, {DateTime? on}) async {
    final d = dayOf(on ?? day);
    final now = DateTime.now();
    // Η ώρα κρατά τη σειρά μέσα στη μέρα· για άλλη μέρα, ώρα «τώρα» πάνω σε εκείνη τη μέρα.
    final t = DateTime(d.year, d.month, d.day, now.hour, now.minute, now.second, now.millisecond);
    final e = LogEntry(id: _newId(), day: dateKey(d), meal: meal, food: food, grams: grams, time: t);
    await _put(e);
    return e;
  }

  Future<void> update(LogEntry e) => _put(e);

  Future<void> _put(LogEntry e) async {
    _entries[e.id] = e;
    notifyListeners();
    if (!_offline) await FoodChannel.logPut(jsonEncode(e.toJson()));
  }

  Future<void> remove(LogEntry e) async {
    _entries.remove(e.id);
    notifyListeners();
    if (!_offline) await FoodChannel.logDelete(e.id);
  }

  /// Αναίρεση διαγραφής: ξαναμπαίνει ακριβώς όπως ήταν.
  Future<void> restore(LogEntry e) => _put(e);

  Future<void> saveMyFood(Food f) async {
    _mine = [f, ..._mine.where((x) => x.id != f.id)];
    _rebuildIndex();
    notifyListeners();
    if (!_offline) await FoodChannel.myFoodPut(jsonEncode(f.toJson()));
  }

  void setDay(DateTime d) {
    day = dayOf(d);
    notifyListeners();
  }

  static String newFoodId() => 'M${_newId()}';
}
