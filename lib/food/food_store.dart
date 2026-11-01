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
class FoodStore extends ChangeNotifier with WidgetsBindingObserver {
  FoodStore() : _offline = false;

  /// Για δοκιμές και στιγμιότυπα: χωρίς κανάλι προς το Android.
  FoodStore.preloaded({
    required List<Food> foods,
    List<LogEntry> entries = const [],
    List<Food> mine = const [],
    DateTime? now,
  }) : _offline = true {
    _basic = foods;
    _mine = mine;
    _index = FoodIndex([...mine, ...foods]);
    for (final e in entries) {
      _entries[e.id] = e;
    }
    if (now != null) day = dayOf(now);
    ready = true;
  }

  final bool _offline;
  bool ready = false;
  String? error;

  /// Τελευταία αλλαγή που δεν αποθηκεύτηκε στο κινητό (φαίνεται στη Διατροφή, μέχρι να κλείσει).
  String? saveError;

  void clearSaveError() {
    saveError = null;
    notifyListeners();
  }

  List<Food> _basic = const [];
  List<Food> _mine = const [];
  FoodIndex _index = FoodIndex(const []);
  final Map<String, LogEntry> _entries = {};

  /// Η μέρα που βλέπω στο ημερολόγιο.
  DateTime day = dayOf(DateTime.now());

  /// Αν βλέπω τη σημερινή μέρα: τότε, μετά τα μεσάνυχτα, το ημερολόγιο περνά στη νέα μέρα.
  bool _followToday = true;

  static const historyDays = 90;

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
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
      // Μία χαλασμένη εγγραφή δεν πρέπει να «κολλάει» όλη τη Διατροφή.
      final out = <Food>[];
      for (final f in r['foods'] as List) {
        if (f is! Map) continue;
        try {
          out.add(Food.fromJson(Map<String, dynamic>.from(f)));
        } catch (_) {}
      }
      _mine = out;
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

  Food? byId(String id) {
    for (final x in _mine) {
      if (x.id == id) return x;
    }
    for (final x in _basic) {
      if (x.id == id) return x;
    }
    return null;
  }

  /// Ωμό + μαγειρεμένες μορφές του ίδιου τροφίμου, με την ετικέτα κάθε κατάστασης.
  /// Κενή λίστα αν το τρόφιμο δεν έχει άλλες μορφές.
  List<(Food, String)> statesOf(Food f) {
    final raw = f.rawId != null ? byId(f.rawId!) : (f.isRawWithCooked ? f : null);
    if (raw == null) return const [];
    // Όσπρια: «Ξερές/Ξερά» είναι πιο κατανοητό από «Ωμό». Μόνο όταν η κατάσταση στην παρένθεση λέει «ξερ…»
    // (όχι το «Κρεμμύδι ξερό», που είναι είδος κρεμμυδιού), και στο γένος του ονόματος: «Φακές (ξερές)» → «Ξερές».
    final dry = RegExp(r'\((ξερ[^\s,)]*)').firstMatch(raw.name)?.group(1);
    final rawLabel = dry != null ? '${dry[0].toUpperCase()}${dry.substring(1)} (πριν το βράσιμο)' : 'Ωμό';
    return [
      (raw, rawLabel),
      for (final c in raw.cooked)
        if (byId(c.$1) case final cf?) (cf, c.$2),
    ];
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

  /// «Ίδιο με χθες»: ξαναγράφει τα τρόφιμα ενός γεύματος από άλλη μέρα, με τις ίδιες ποσότητες.
  /// Οι τιμές παίρνονται από τη βάση όπως είναι τώρα (σαν να τα κατέγραφα ξανά).
  Future<List<LogEntry>> copyMeal(DateTime from, Meal meal, DateTime to, {Meal? into}) async {
    final source = entriesFor(from, meal);
    final d = dayOf(to);
    final now = DateTime.now();
    final base = DateTime(d.year, d.month, d.day, now.hour, now.minute, now.second);
    final out = <LogEntry>[
      for (var i = 0; i < source.length; i++)
        LogEntry(
          id: _newId(),
          day: dateKey(d),
          meal: into ?? meal,
          food: _current(source[i].food),
          grams: source[i].grams,
          // Ίδια σειρά με το αρχικό γεύμα.
          time: base.add(Duration(milliseconds: i)),
        ),
    ];
    for (final e in out) {
      await _put(e);
    }
    return out;
  }

  Future<void> update(LogEntry e) => _put(e);

  Future<void> _put(LogEntry e) async {
    final before = _entries[e.id];
    _entries[e.id] = e;
    notifyListeners();
    if (_offline) return;
    final r = await FoodChannel.logPut(jsonEncode(e.toJson()));
    if (r['ok'] != true) {
      // Δεν γράφτηκε: η οθόνη να δείχνει ό,τι υπάρχει πραγματικά, και να το λέει.
      if (before == null) {
        _entries.remove(e.id);
      } else {
        _entries[e.id] = before;
      }
      saveError = 'Δεν αποθηκεύτηκε: ${e.food.name}. Δοκίμασε ξανά.';
      notifyListeners();
    }
  }

  Future<void> remove(LogEntry e) async {
    _entries.remove(e.id);
    notifyListeners();
    if (_offline) return;
    final r = await FoodChannel.logDelete(e.id);
    if (r['ok'] != true) {
      _entries[e.id] = e;
      saveError = 'Δεν διαγράφηκε: ${e.food.name}. Δοκίμασε ξανά.';
      notifyListeners();
    }
  }

  /// Αναίρεση διαγραφής: ξαναμπαίνει ακριβώς όπως ήταν.
  Future<void> restore(LogEntry e) => _put(e);

  /// Τα προϊόντα μου, το πιο πρόσφατο πρώτο.
  List<Food> get mine => _mine;

  Future<void> deleteMyFood(Food f) async {
    final before = _mine;
    _mine = _mine.where((x) => x.id != f.id).toList();
    _rebuildIndex();
    notifyListeners();
    if (_offline) return;
    final r = await FoodChannel.myFoodDelete(f.id);
    if (r['ok'] != true) {
      _mine = before;
      _rebuildIndex();
      saveError = 'Δεν διαγράφηκε: ${f.name}. Δοκίμασε ξανά.';
      notifyListeners();
    }
  }

  Future<void> saveMyFood(Food f) async {
    final before = _mine;
    _mine = [f, ..._mine.where((x) => x.id != f.id)];
    _rebuildIndex();
    notifyListeners();
    if (_offline) return;
    final r = await FoodChannel.myFoodPut(jsonEncode(f.toJson()));
    if (r['ok'] != true) {
      _mine = before;
      _rebuildIndex();
      saveError = 'Δεν αποθηκεύτηκε: ${f.name}. Δοκίμασε ξανά.';
      notifyListeners();
    }
  }

  void setDay(DateTime d) {
    day = dayOf(d);
    _followToday = sameDay(day, DateTime.now());
    notifyListeners();
  }

  /// Μετά τα μεσάνυχτα: αν έβλεπα τη «σήμερα», το ημερολόγιο περνά στη νέα σημερινή μέρα.
  /// Καλείται όταν επιστρέφω στην εφαρμογή και πριν από κάθε «+ Φαγητό».
  void syncToday() {
    if (_offline || !_followToday) return;
    final t = dayOf(DateTime.now());
    if (!sameDay(day, t)) {
      day = t;
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) syncToday();
  }

  @override
  void dispose() {
    if (!_offline) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  static String newFoodId() => 'M${_newId()}';

  // ---------- Αντίγραφο ασφαλείας ----------

  /// Όλο το ημερολόγιο (όχι μόνο οι 90 μέρες της οθόνης) και τα προϊόντα μου, όπως αποθηκεύονται.
  /// null αν δεν διαβάστηκαν (τότε δεν φτιάχνεται αρχείο: καλύτερα κανένα από ένα μισό).
  Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)?> exportRaw() async {
    final log = await FoodChannel.logRange('0000-01-01', '9999-12-31');
    final mine = await FoodChannel.myFoods();
    if (log['ok'] != true || log['entries'] is! List || mine['ok'] != true || mine['foods'] is! List) return null;
    return (
      [for (final e in log['entries'] as List) if (e is Map) Map<String, dynamic>.from(e)],
      [for (final f in mine['foods'] as List) if (f is Map) Map<String, dynamic>.from(f)],
    );
  }

  /// Επαναφορά: προσθέτει ό,τι λείπει και ενημερώνει ό,τι έχει το ίδιο id. Δεν σβήνει τίποτα.
  /// Επιστρέφει (καταχωρίσεις, προϊόντα, αποτυχίες).
  Future<(int, int, int)> importBackup(List<LogEntry> entries, List<Food> foods) async {
    var e = 0, f = 0, failed = 0;
    final today = dayOf(DateTime.now());
    final from = DateTime(today.year, today.month, today.day - historyDays);
    for (final le in entries) {
      final r = await FoodChannel.logPut(jsonEncode(le.toJson()));
      if (r['ok'] == true) {
        e++;
        // Στη μνήμη μόνο όσες φαίνονται (τελευταίες 90 μέρες), όπως όταν ανοίγει η εφαρμογή.
        if (!le.time.isBefore(from)) _entries[le.id] = le;
      } else {
        failed++;
      }
    }
    final mine = [..._mine];
    for (final food in foods) {
      final r = await FoodChannel.myFoodPut(jsonEncode(food.toJson()));
      if (r['ok'] == true) {
        f++;
        mine.removeWhere((x) => x.id == food.id);
        mine.insert(0, food);
      } else {
        failed++;
      }
    }
    _mine = mine;
    _rebuildIndex();
    notifyListeners();
    return (e, f, failed);
  }
}
