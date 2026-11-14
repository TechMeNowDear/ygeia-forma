import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../backup.dart' show dbRecoveryRows;
import '../format.dart';
import '../history.dart' show dateKey;
import 'food_channel.dart';
import 'food_model.dart';
import 'food_search.dart';
import 'off.dart' show normalizeBarcode;
import 'replaced_foods.dart';

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
    _mineRead = true;
    _rebuildIndex();
    for (final e in entries) {
      _entries[e.id] = e;
    }
    if (now != null) day = dayOf(now);
    ready = true;
  }

  final bool _offline;
  bool ready = false;
  String? error;

  /// Η μέρα ακολουθεί το ρολόι του κινητού (όχι στις δοκιμές και τα στιγμιότυπα).
  bool get followsClock => !_offline;

  /// Διαβάστηκαν το ημερολόγιο και «Τα προϊόντα μου». Αν όχι, η προσθήκη κλειδώνει ώσπου να πετύχει το
  /// «Ξαναδοκίμασε» (έλεγχος 9/11, Χ6: αλλιώς ό,τι γραφόταν μπορούσε να βγει διπλό).
  bool get loaded => _offline || (_logRead && _mineRead);
  bool _logRead = false;

  /// Γραμμές της βάσης (καταχωρίσεις ή δικά μου προϊόντα) που δεν διαβάστηκαν και παραλείφθηκαν. Μία χαλασμένη γραμμή
  /// δεν «κολλάει» τη Διατροφή, αλλά δεν χάνεται και σιωπηλά: μετριέται εδώ και φαίνεται στην «Αναφορά για έλεγχο»
  /// (τελικός έλεγχος, Συμβούλιο 3). Οι γραμμές μένουν στη βάση και μπαίνουν όπως είναι στο αντίγραφο ασφαλείας.
  int skippedRows = 0;

  /// Ξαναδιαβάζει ό,τι απέτυχε στο άνοιγμα.
  Future<void> retry() async {
    if (_offline) return;
    error = null;
    notifyListeners();
    if (_basic.isEmpty) {
      try {
        final raw = await rootBundle.loadString('assets/foods/basic_foods.json');
        final j = jsonDecode(raw) as Map<String, dynamic>;
        _basic = [for (final f in j['foods'] as List) Food.fromJson(Map<String, dynamic>.from(f as Map))];
      } catch (e) {
        error = 'Δεν φορτώθηκε η βάση τροφίμων: $e';
      }
    }
    if (!_mineRead) await _loadMine();
    if (!_logRead) await _loadEntries();
    _rebuildIndex();
    notifyListeners();
  }

  /// Τελευταία αλλαγή που δεν αποθηκεύτηκε στο κινητό (φαίνεται στη Διατροφή, μέχρι να κλείσει).
  String? saveError;

  void clearSaveError() {
    saveError = null;
    notifyListeners();
  }

  List<Food> _basic = const [];
  List<Food> _mine = const [];

  /// «Τα προϊόντα μου» διαβάστηκαν σωστά (αλλιώς δεν κρύβεται κανένα δικό μου από τα «Πρόσφατα/Συχνά»).
  bool _mineRead = false;
  FoodIndex _index = FoodIndex(const []);
  final Map<String, LogEntry> _entries = {};

  /// Η μέρα που βλέπω στο ημερολόγιο.
  DateTime day = dayOf(DateTime.now());

  /// Αν βλέπω τη σημερινή μέρα: τότε, μετά τα μεσάνυχτα, το ημερολόγιο περνά στη νέα μέρα.
  bool _followToday = true;

  static const historyDays = 90;

  /// Η αποθήκη φαγητού της εφαρμογής (τη δηλώνει το Shell), για οθόνες που ανοίγουν από αλλού, π.χ. «Τα στοιχεία
  /// μου» από τις Ρυθμίσεις (σχέδια 9/11: τα προϊόντα και η κουζίνα ζουν εκεί).
  static FoodStore? shared;

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      await _readAll();
    } finally {
      // Ό,τι κι αν έγινε, όποιος περιμένει το [waitLoaded] συνεχίζει (και βλέπει αν διαβάστηκε).
      if (!_firstRead.isCompleted) _firstRead.complete();
    }
  }

  Future<void> _readAll() async {
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

  /// Τελείωσε η πρώτη ανάγνωση στο άνοιγμα της εφαρμογής (είτε πέτυχε είτε όχι).
  final Completer<void> _firstRead = Completer<void>();

  /// Περιμένει να τελειώσει η πρώτη ανάγνωση και λέει αν το ημερολόγιο διαβάστηκε ([loaded]).
  ///
  /// Έλεγχος round1 (S2-11): όταν η εφαρμογή ανοίγει από το widget «+ Φαγητό» / «Barcode» χωρίς να τρέχει ήδη, το
  /// πάτημα φτάνει πριν διαβαστούν η βάση τροφίμων, «Τα προϊόντα μου» και το ημερολόγιο. Πριν, η προσθήκη απλώς δεν
  /// άνοιγε (με μήνυμα για ένα «Ξαναδοκίμασε» που δεν υπήρχε). Τώρα περιμένει λίγο και ανοίγει μόλις διαβαστούν.
  /// Αν η ανάγνωση έχει ήδη τελειώσει (ή δεν θα τελειώσει μέσα στο [timeout]), απαντά αμέσως με ό,τι ισχύει.
  Future<bool> waitLoaded({Duration timeout = const Duration(seconds: 10)}) async {
    if (!loaded && !_firstRead.isCompleted) {
      await _firstRead.future.timeout(timeout, onTimeout: () {});
    }
    return loaded;
  }

  Future<void> _loadMine() async {
    if (_offline) return;
    final r = await FoodChannel.myFoods();
    if (r['ok'] != true) {
      // Να φαίνεται: αλλιώς θα έμοιαζε ότι δεν έχω προϊόντα και θα τα ξανάγραφα (διπλά).
      error = 'Δεν διαβάστηκαν «Τα προϊόντα μου». Κλείσε και άνοιξε ξανά την εφαρμογή.';
    }
    if (r['ok'] == true && r['foods'] is List) {
      // Μία χαλασμένη εγγραφή δεν πρέπει να «κολλάει» όλη τη Διατροφή.
      final out = <Food>[];
      for (final f in r['foods'] as List) {
        try {
          out.add(Food.fromJson(Map<String, dynamic>.from(f as Map)));
        } catch (_) {
          skippedRows++;
        }
      }
      _mine = out;
      _mineRead = true;
    }
  }

  Future<void> _loadEntries() async {
    if (_offline) return;
    final to = dayOf(DateTime.now());
    final from = DateTime(to.year, to.month, to.day - historyDays);
    final r = await FoodChannel.logRange(dateKey(from), dateKey(DateTime(to.year, to.month, to.day + 1)));
    _loadedFrom = from;
    if (r['ok'] != true) {
      error = 'Δεν διαβάστηκε το ημερολόγιο φαγητού. Κλείσε και άνοιξε ξανά την εφαρμογή πριν γράψεις κάτι.';
    }
    if (r['ok'] == true && r['entries'] is List) {
      _logRead = true;
      for (final e in r['entries'] as List) {
        try {
          final le = LogEntry.fromJson(Map<String, dynamic>.from(e as Map));
          _entries[le.id] = le;
        } catch (_) {
          skippedRows++;
        }
      }
    }
  }

  void _rebuildIndex() {
    _index = FoodIndex([..._mine, ..._basic]);
    _byId = {for (final f in _basic) f.id: f, for (final f in _mine) f.id: f};
  }

  Map<String, Food> _byId = const {};

  /// Κάθε αλλαγή (ημερολόγιο, προϊόντα) περνά από εδώ: τα έτοιμα μετρημένα ξαναμετριούνται.
  @override
  void notifyListeners() {
    _countsCache = null;
    super.notifyListeners();
  }

  /// Από ποια μέρα υπάρχουν στη μνήμη καταχωρίσεις (οι παλιότερες φορτώνονται όταν τις ανοίξω).
  DateTime? _loadedFrom;

  // ---------- Ανάγνωση ----------

  List<LogEntry> entriesFor(DateTime d, [Meal? meal]) {
    final k = dateKey(d);
    final list = _entries.values.where((e) => e.day == k && (meal == null || e.meal == meal)).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    return list;
  }

  /// Ημέρες με καταχωρίσεις (για «αντιγραφή από χθες» κ.λπ. αργότερα).
  bool hasEntries(DateTime d) => _entries.values.any((e) => e.day == dateKey(d));

  /// Πόσες φορές έχω φάει κάθε τρόφιμο τις τελευταίες 90 μέρες (με το τωρινό id του τροφίμου).
  /// Κρατιέται έτοιμο και ξαναμετριέται μόνο όταν αλλάξει το ημερολόγιο.
  Map<String, int>? _countsCache;
  Map<String, int> get _counts {
    final cached = _countsCache;
    if (cached != null) return cached;
    final c = <String, int>{};
    for (final e in _entries.values) {
      final id = _idNow(e.food.id);
      c[id] = (c[id] ?? 0) + 1;
    }
    return _countsCache = c;
  }

  /// Το τωρινό id ενός τροφίμου (αν άλλαξε σε νεότερη λίστα).
  static String _idNow(String id) => replacedFoods[id] ?? id;

  /// Τρόφιμο της βάσης που δεν υπάρχει πια (ούτε με νέο id): δεν προτείνεται ξανά.
  /// (Αν η βάση δεν φορτώθηκε, δεν κρύβεται τίποτα.)
  /// Δικό μου προϊόν που σβήστηκε (π.χ. είχε λάθος τιμές): ούτε αυτό ξαναπροτείνεται (έλεγχος 8/11, FOOD-04).
  /// Οι παλιές καταχωρίσεις κρατούν τις τιμές τους.
  bool _gone(Food f) => f.isMine ? _mineRead && byId(f.id) == null : _basic.isNotEmpty && byId(_idNow(f.id)) == null;

  /// Πρόσφατα: τα τελευταία διαφορετικά τρόφιμα.
  List<Food> recent({int limit = 15}) {
    final sorted = _entries.values.toList()..sort((a, b) => b.time.compareTo(a.time));
    final seen = <String>{};
    final out = <Food>[];
    for (final e in sorted) {
      if (_gone(e.food)) continue;
      if (seen.add(_idNow(e.food.id))) out.add(_current(e.food));
      if (out.length >= limit) break;
    }
    return out;
  }

  /// Συχνά: όσα έχω φάει τουλάχιστον 2 φορές, πιο συχνό πρώτο.
  List<Food> frequent({int limit = 15}) {
    final counts = _counts.entries.where((e) => e.value >= 2).toList()..sort((a, b) => b.value.compareTo(a.value));
    final latest = <String, LogEntry>{};
    for (final e in _entries.values) {
      final id = _idNow(e.food.id);
      final p = latest[id];
      if (p == null || e.time.isAfter(p.time)) latest[id] = e;
    }
    return [
      for (final c in counts)
        if (!_gone(latest[c.key]!.food)) _current(latest[c.key]!.food),
    ].take(limit).toList();
  }

  int timesEaten(String foodId) => _counts[_idNow(foodId)] ?? 0;

  /// Η ποσότητα της τελευταίας φοράς (έγγραφο › «ποσότητα από την τελευταία φορά»).
  double? lastGrams(String foodId) {
    final id = _idNow(foodId);
    LogEntry? last;
    for (final e in _entries.values) {
      if (_idNow(e.food.id) == id && (last == null || e.time.isAfter(last.time))) last = e;
    }
    return last?.grams;
  }

  /// Η τωρινή μορφή του τροφίμου (από τη βάση ή «Τα προϊόντα μου», και με το νέο id αν άλλαξε)·
  /// αν δεν υπάρχει πια, το αντίγραφο της καταχώρισης.
  Food _current(Food f) => byId(_idNow(f.id)) ?? f;

  /// Για την οθόνη: η μορφή που θα γραφτεί αν το ξαναδιαλέξω (π.χ. το «Όπως χθες»).
  Food currentOf(Food f) => _current(f);

  /// Το πιο συνηθισμένο είδος, όταν όλα ταιριάζουν το ίδιο στην αναζήτηση (π.χ. «γάλα» → 1,5%).
  // C2013: «χυμός» → πρώτα ο χυμός πορτοκάλι, όχι ο χυμός λεμονιού (έλεγχος διατροφής M7, 4/11).
  // Δεύτερος έλεγχος διατροφής (N2, N4): «κοτόπουλο» → πρώτα το στήθος χωρίς πέτσα (όχι το μπούτι με πέτσα, το πιο
  // λιπαρό)· «ψωμί» → ο μέσος όρος όλων των ειδών (όχι το πολύσπορο επειδή έχει το πιο σύντομο όνομα)· «ρύζι βραστό»
  // → το λευκό (όχι το μπασμάτι).
  // Τρίτος έλεγχος διατροφής (N1, N2, N4): «κοτόπουλο ψητό» → το ψητό στήθος (όχι ολόκληρο με πέτσα)· «παγωτό» → το
  // παγωτό (όχι το frozen yogurt)· «τυρί» → η φέτα (όχι το τυρί κρέμα). Τα «τυρί κρέμα», «κοτόπουλο φούρνου» δεν αλλάζουν.
  // Έλεγχος 9/11: «γιαούρτι» → πρώτα το στραγγιστό 2% (το πιο συνηθισμένο· πριν έβγαινε πρώτο το 0% μόνο επειδή έχει
  // πιο σύντομο όνομα, V-C-12)· «μπακαλιάρος παστός» → πρώτα ο ξαλμυρισμένος, όπως τρώγεται (όχι ο ξερός με 12 g αλάτι)·
  // «καλαμάκι» → πρώτα το ανάμεικτο (το σκέτο καλαμάκι είναι συνήθως χοιρινό, πιο λιπαρό από κοτόπουλο/μοσχάρι).
  static const _preferred = {
    'C19033': 0.5, 'C2013': 0.5, 'C36017': 0.5, 'C7000': 0.5, 'C9104': 0.5,
    'C36018': 0.5, 'C39500': 0.5, 'C12066': 1.5, 'U170903': 0.5, 'C26024': 0.5, 'C25506': 0.5,
  };

  /// Η συχνότητα βοηθά μόνο ανάμεσα σε όσα ταιριάζουν περίπου το ίδιο: το πολύ +1,5, λιγότερο από
  /// τη διαφορά «ακριβώς η λέξη» / «ξεκινά με τη λέξη». Αλλιώς, μετά από 2 μελιτζάνες, το «μέλι»
  /// έβγαζε πρώτη τη μελιτζάνα.
  List<Food> search(String q) => find(q).foods;

  /// Όπως [search], μαζί με τις λέξεις που αγνοήθηκαν ή διορθώθηκαν για να βρεθεί κάτι (η οθόνη τις λέει).
  FoodSearchResult find(String q) {
    final counts = _counts;
    return _index.find(q, boost: {
      ..._preferred,
      for (final e in counts.entries) e.key: math.min(1.5, e.value * 0.5) + (_preferred[e.key] ?? 0) + _habitCooked(e.key, e.value, counts),
    });
  }

  /// Round7 (R7-U2-5): μαγειρεμένη μορφή που έχεις γράψει τουλάχιστον 3 φορές, ενώ την ωμή της ποτέ, παίρνει όσο παίρνει
  /// η ωμή επειδή «ζυγίζουμε ωμά» ([rawFirstBonus]). Αλλιώς το «κοτόπουλο» έβγαζε πάντα πρώτο το ωμό στήθος (ισοπαλία, και
  /// νικούσε η σειρά της λίστας), και ένα βιαστικό πάτημα έγραφε 200 g ψητό ως ωμό: 220 αντί για 282 kcal.
  double _habitCooked(String id, int times, Map<String, int> counts) {
    if (times < 3) return 0;
    final raw = byId(id)?.rawId;
    return raw != null && (counts[raw] ?? 0) == 0 ? rawFirstBonus : 0;
  }

  Food? byId(String id) => _byId[id];

  /// Ωμό + μαγειρεμένες μορφές του ίδιου τροφίμου, με την ετικέτα κάθε κατάστασης.
  /// Κενή λίστα αν το τρόφιμο δεν έχει άλλες μορφές.
  ///
  /// Οι μορφές βγαίνουν από τη βάση (το αντίγραφο μιας καταχώρισης δεν κρατά τη λίστα τους)· η μορφή
  /// που είναι ήδη η καταχώριση μένει το δικό της αντίγραφο, με τις τιμές της.
  List<(Food, String)> statesOf(Food f) {
    final cur = byId(_idNow(f.id)) ?? f;
    final raw = cur.rawId != null ? byId(cur.rawId!) : (cur.isRawWithCooked ? cur : null);
    if (raw == null) return const [];
    Food same(Food x) => x.id == f.id ? f : x;
    // Όσπρια: «Ξερές/Ξερά» είναι πιο κατανοητό από «Ωμό». Μόνο όταν η κατάσταση στην παρένθεση λέει «ξερ…»
    // (όχι το «Κρεμμύδι ξερό», που είναι είδος κρεμμυδιού), και στο γένος του ονόματος: «Φακές (ξερές)» → «Ξερές».
    final dry = RegExp(r'\((ξερ[^\s,)]*)').firstMatch(raw.name)?.group(1);
    // Round8 (R8-A2-4 / R8-U2-2): και το «ωμ…» στο γένος και τον αριθμό του ονόματος, όπου κι αν είναι μέσα στην παρένθεση:
    // «Μακαρόνια (ξηρά, ωμά)» → «Ωμά», «Κινόα (ωμή)» → «Ωμή», «Κιμάς … (ωμός)» → «Ωμός». Πριν ήταν πάντα «Ωμό», δίπλα σε
    // «Βρασμένα»/«Βρασμένη» (και στην ερώτηση «300 g ωμό = …»).
    final rawWord = RegExp(r'\((?:[^)]*[\s,])?(ωμ[^\s,)]*)').firstMatch(raw.name)?.group(1);
    String cap(String w) => '${w[0].toUpperCase()}${w.substring(1)}';
    final rawLabel = dry != null
        ? '${cap(dry)} (πριν το βράσιμο)'
        : rawWord != null
            ? cap(rawWord)
            : 'Ωμό';
    return [
      (same(raw), rawLabel),
      for (final c in raw.cooked)
        if (byId(c.$1) case final cf?) (same(cf), c.$2),
    ];
  }

  /// Το ίδιο προϊόν με όποια μορφή του barcode: UPC-A 12 ψηφίων = EAN-13 με «0» μπροστά, GTIN-14 με «0» μπροστά =
  /// EAN-13 (έλεγχος 9/11, Χ5· πριν, το ίδιο προϊόν μπορούσε να περαστεί δύο φορές).
  Food? byBarcode(String code) {
    final c = normalizeBarcode(code);
    // Κωδικός χωρίς ψηφία δεν «βρίσκει» προϊόν που αποθηκεύτηκε κάποτε με κενό barcode (τελικός έλεγχος, Συμβούλιο 3).
    if (c.isEmpty) return null;
    for (final f in _mine) {
      if (f.barcode != null && normalizeBarcode(f.barcode!) == c) return f;
    }
    return null;
  }

  // ---------- Αλλαγές ----------

  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 20).toRadixString(36)}';

  /// [now]: για δοκιμές (αλλιώς το ρολόι του κινητού).
  Future<LogEntry> add(Food food, double grams, Meal meal, {DateTime? on, DateTime? now}) async {
    final d = dayOf(on ?? day);
    final e = LogEntry(id: _newId(), day: dateKey(d), meal: meal, food: food, grams: grams, time: entryTime(d, now ?? DateTime.now()));
    await _put(e);
    return e;
  }

  /// Η ώρα μιας νέας καταχώρισης στη μέρα [d], γραμμένης [now]. Κρατά τη σειρά μέσα στη μέρα· για άλλη μέρα, ώρα «τώρα»
  /// πάνω σε εκείνη τη μέρα. Round7 (R7-A2-4): εξαίρεση το βραδινό που γράφεται μετά τα μεσάνυχτα (00:00–03:59) στη
  /// χθεσινή μέρα (η ερώτηση «Σε ποια μέρα;» → «Χθες»): κρατά την πραγματική ώρα. Πριν έπαιρνε «Πέμ 00:20» και έβγαινε
  /// πρώτο στο «Βράδυ» της Πέμπτης, όχι στα «Πρόσφατα», και η επόμενη ποσότητα ερχόταν από παλιότερη φορά. Η μέρα της
  /// καταχώρισης είναι πάντα το [d] (τίποτα δεν κρίνει τη μέρα από την ώρα).
  static DateTime entryTime(DateTime d, DateTime now) {
    final today = dayOf(now);
    if (now.hour < 4 && sameDay(d, DateTime(today.year, today.month, today.day - 1))) return now;
    return DateTime(d.year, d.month, d.day, now.hour, now.minute, now.second, now.millisecond);
  }

  /// Οι καταχωρίσεις ενός γεύματος που ξαναγράφονται με το «Όπως χθες»: χωρίς όσα δικά μου προϊόντα σβήστηκαν
  /// (π.χ. είχαν λάθος τιμές) και όσα τρόφιμα της βάσης δεν υπάρχουν πια (έλεγχος 9/11, Μ3).
  List<LogEntry> copyable(DateTime from, Meal meal) => [for (final e in entriesFor(from, meal)) if (!_gone(e.food)) e];

  /// Πόσα από το γεύμα δεν ξαναγράφονται με το «Όπως χθες» (σβησμένα προϊόντα).
  int notCopyable(DateTime from, Meal meal) => entriesFor(from, meal).length - copyable(from, meal).length;

  /// «Ίδιο με χθες»: ξαναγράφει τα τρόφιμα ενός γεύματος από άλλη μέρα, με τις ίδιες ποσότητες.
  /// Οι τιμές παίρνονται από τη βάση όπως είναι τώρα (σαν να τα κατέγραφα ξανά). Όσα έχουν σβηστεί δεν ξαναγράφονται.
  Future<List<LogEntry>> copyMeal(DateTime from, Meal meal, DateTime to, {Meal? into}) async {
    final source = copyable(from, meal);
    final d = dayOf(to);
    final base = entryTime(d, DateTime.now());
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
    final saved = <LogEntry>[];
    for (final e in out) {
      if (await _put(e)) saved.add(e);
    }
    return saved;
  }

  Future<void> update(LogEntry e) => _put(e);

  /// Αν η καταχώριση είναι αποθηκευμένη όπως είναι (όχι αν απέτυχε η αποθήκευσή της).
  bool isSaved(LogEntry e) => identical(_entries[e.id], e);

  Future<bool> _put(LogEntry e) async {
    final before = _entries[e.id];
    _entries[e.id] = e;
    notifyListeners();
    if (_offline) return true;
    final r = await FoodChannel.logPut(jsonEncode(e.toJson()));
    if (r['ok'] == true) return true;
    // Δεν γράφτηκε: η οθόνη να δείχνει ό,τι υπάρχει πραγματικά, και να το λέει. Αν στο μεταξύ
    // ήρθε νεότερη αλλαγή στο ίδιο, δεν την πατάμε.
    if (identical(_entries[e.id], e)) {
      if (before == null) {
        _entries.remove(e.id);
      } else {
        _entries[e.id] = before;
      }
    }
    saveError = 'Δεν αποθηκεύτηκε: ${e.food.name}. Δοκίμασε ξανά.';
    notifyListeners();
    return false;
  }

  /// `false` αν δεν διαγράφηκε (τότε ξαναφαίνεται και βγαίνει μήνυμα).
  Future<bool> remove(LogEntry e) async {
    _entries.remove(e.id);
    _removedIds.add(e.id);
    notifyListeners();
    if (_offline) return true;
    final r = await FoodChannel.logDelete(e.id);
    if (r['ok'] == true) return true;
    _entries.putIfAbsent(e.id, () => e);
    saveError = 'Δεν διαγράφηκε: ${e.food.name}. Δοκίμασε ξανά.';
    notifyListeners();
    return false;
  }

  /// Αναίρεση διαγραφής: ξαναμπαίνει ακριβώς όπως ήταν.
  Future<void> restore(LogEntry e) => _put(e);

  /// Τα προϊόντα μου, το πιο πρόσφατο πρώτο.
  List<Food> get mine => _mine;

  /// `false` αν δεν διαγράφηκε.
  Future<bool> deleteMyFood(Food f) async {
    final before = _mine;
    final after = _mine = _mine.where((x) => x.id != f.id).toList();
    _removedFoodIds.add(f.id);
    _rebuildIndex();
    notifyListeners();
    if (_offline) return true;
    final r = await FoodChannel.myFoodDelete(f.id);
    if (r['ok'] == true) return true;
    if (identical(_mine, after)) {
      _mine = before;
      _rebuildIndex();
    }
    saveError = 'Δεν διαγράφηκε: ${f.name}. Δοκίμασε ξανά.';
    notifyListeners();
    return false;
  }

  Future<bool> saveMyFood(Food f) async {
    final before = _mine;
    final after = _mine = [f, ..._mine.where((x) => x.id != f.id)];
    _rebuildIndex();
    notifyListeners();
    if (_offline) return true;
    final r = await FoodChannel.myFoodPut(jsonEncode(f.toJson()));
    if (r['ok'] == true) return true;
    if (identical(_mine, after)) {
      _mine = before;
      _rebuildIndex();
    }
    saveError = 'Δεν αποθηκεύτηκε: ${f.name}. Δοκίμασε ξανά.';
    notifyListeners();
    return false;
  }

  void setDay(DateTime d) {
    day = dayOf(d);
    _followToday = sameDay(day, DateTime.now());
    _shownOn = dayOf(DateTime.now());
    notifyListeners();
    _loadDayIfOld(day);
  }

  /// Η μέρα που δείχνει το ημερολόγιο όταν ΔΕΝ είναι η σημερινή ([today])· null όταν δείχνει τη σημερινή.
  /// Για την κεφαλίδα της Διατροφής (έλεγχος round1, U3a-1): έγραφε πάντα τη σημερινή ημερομηνία, και όταν από κάτω
  /// φαινόταν άλλη μέρα.
  DateTime? otherDayShown(DateTime today) => sameDay(day, today) ? null : day;

  /// Ποια μέρα (του ημερολογίου) διάλεξα να βλέπω μια παλιότερη μέρα.
  DateTime? _shownOn;

  /// Μέρα πριν από τις 90 που φορτώνονται στο άνοιγμα: φορτώνεται τώρα, ώστε να μη φαίνεται άδεια.
  Future<void> _loadDayIfOld(DateTime d) async {
    final from = _loadedFrom;
    if (_offline || from == null || !d.isBefore(from)) return;
    final r = await FoodChannel.logRange(dateKey(d), dateKey(DateTime(d.year, d.month, d.day + 1)));
    if (r['ok'] != true || r['entries'] is! List) return;
    for (final e in r['entries'] as List) {
      if (e is! Map) continue;
      try {
        final le = LogEntry.fromJson(Map<String, dynamic>.from(e));
        _entries.putIfAbsent(le.id, () => le);
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Μετά τα μεσάνυχτα: αν έβλεπα τη «σήμερα», το ημερολόγιο περνά στη νέα σημερινή μέρα.
  /// Και αν είχα αφήσει ανοιχτή μια παλιότερη μέρα από χθες ή πιο πριν, την επόμενη μέρα ξεκινά
  /// πάλι από τη σήμερα (να μη γραφτεί το πρωινό σε λάθος μέρα).
  /// Καλείται όταν επιστρέφω στην εφαρμογή και πριν από κάθε «+ Φαγητό».
  void syncToday() {
    if (_offline) return;
    final t = dayOf(DateTime.now());
    if (!_followToday) {
      final shown = _shownOn;
      if (shown == null || sameDay(shown, t)) return;
      _followToday = true;
    }
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

  /// Επαναφορά: προσθέτει **μόνο ό,τι λείπει**. Ό,τι υπάρχει ήδη στο κινητό (ίδιο id) μένει όπως
  /// είναι, ώστε ένα παλιό αντίγραφο να μη γυρίσει πίσω διορθώσεις που έγιναν μετά. Δεν σβήνει τίποτα.
  /// Επιστρέφει (καταχωρίσεις, προϊόντα, αποτυχίες, όσα υπήρχαν ήδη) ή null αν δεν διαβάστηκε
  /// τι υπάρχει ήδη (τότε δεν γράφεται τίποτα).
  Future<(int, int, int, int)?> importBackup(List<LogEntry> entries, List<Food> foods) async {
    var e = 0, f = 0, failed = 0, existing = 0;
    final have = await FoodChannel.logRange('0000-01-01', '9999-12-31');
    if (have['ok'] != true || have['entries'] is! List) return null;
    // Τα προϊόντα από το κινητό (όχι από τη μνήμη, που μπορεί να μη φορτώθηκαν).
    final haveMine = await FoodChannel.myFoods();
    if (haveMine['ok'] != true || haveMine['foods'] is! List) return null;
    final mineIds = {
      for (final x in haveMine['foods'] as List)
        if (x is Map && x['id'] is String) x['id'] as String,
    };
    final haveIds = {
      for (final x in have['entries'] as List)
        if (x is Map && x['id'] is String) x['id'] as String,
    };
    final today = dayOf(DateTime.now());
    final from = DateTime(today.year, today.month, today.day - historyDays);
    // Ό,τι λείπει από το κινητό, μία φορά το καθένα (το ίδιο id δύο φορές στο αντίγραφο: μένει το πρώτο, όπως στη βάση).
    final newEntries = <LogEntry>[];
    for (final le in entries) {
      if (!haveIds.add(le.id)) {
        existing++;
        continue;
      }
      newEntries.add(le);
    }
    final newFoods = <Food>[];
    for (final food in foods) {
      if (!mineIds.add(food.id)) {
        existing++;
        continue;
      }
      newFoods.add(food);
    }
    // Η λίστα από το κινητό (αν δεν είχε φορτωθεί στο άνοιγμα, να φαίνονται όλα, όχι μόνο τα νέα).
    final mine = <Food>[];
    for (final x in haveMine['foods'] as List) {
      if (x is! Map) continue;
      try {
        mine.add(Food.fromJson(Map<String, dynamic>.from(x)));
      } catch (_) {}
    }
    // Τελικός έλεγχος, Συμβούλιο 4 (Γ1): όλα σε ΜΙΑ κλήση και μία συναλλαγή στη βάση. Πριν γράφονταν ένα-ένα· με χιλιάδες
    // καταχωρίσεις αργούσε, και μια διακοπή στη μέση άφηνε μισή επαναφορά. Τώρα ή γράφονται όλα ή τίποτα.
    if (newEntries.isNotEmpty || newFoods.isNotEmpty) {
      final r = await FoodChannel.restorePut(
        jsonEncode([for (final le in newEntries) le.toJson()]),
        jsonEncode([for (final food in newFoods) food.toJson()]),
      );
      if (r['ok'] == true) {
        // Όσα έγραψε πραγματικά η βάση· ό,τι βρήκε ήδη εκεί (γράφτηκε στο μεταξύ) μετρά στα «υπήρχαν ήδη».
        final wroteE = r['entries'], wroteF = r['foods'];
        e = wroteE is num && wroteE.isFinite ? wroteE.toInt().clamp(0, newEntries.length) : newEntries.length;
        f = wroteF is num && wroteF.isFinite ? wroteF.toInt().clamp(0, newFoods.length) : newFoods.length;
        existing += (newEntries.length - e) + (newFoods.length - f);
        for (final le in newEntries) {
          // Στη μνήμη μόνο όσες φαίνονται (τελευταίες 90 μέρες), όπως όταν ανοίγει η εφαρμογή.
          if (!le.time.isBefore(from)) _entries.putIfAbsent(le.id, () => le);
        }
        for (final food in newFoods) {
          mine.removeWhere((x) => x.id == food.id);
          mine.insert(0, food);
        }
      } else {
        failed = newEntries.length + newFoods.length;
      }
    }
    _mine = mine;
    _rebuildIndex();
    notifyListeners();
    return (e, f, failed, existing);
  }

  // ---------- Μετά από βλάβη της βάσης (Round 7, R7-A9-1, f4) ----------

  /// Ό,τι έσβησε ο χρήστης σε αυτή τη χρήση της εφαρμογής: μετά από βλάβη δεν ξαναμπαίνει από το παλιό αρχείο.
  final Set<String> _removedIds = {};
  final Set<String> _removedFoodIds = {};
  int? _recoveredAt;
  bool _recovering = false;

  /// Round 8 (R8-A9-3, f4): η επαναφορά έγινε αλλά το σημάδι «έγινε» δεν γράφτηκε· η επόμενη προσπάθεια γράφει ΜΟΝΟ το
  /// σημάδι (δεν ξαναδιαβάζει το αρχείο, που θα ξανάβαζε ό,τι σβήστηκε στο μεταξύ).
  ({int at, int entries, int foods, bool complete})? _unmarked;

  /// Η βάση βρέθηκε χαλασμένη (ώρα [at], ms) και ξεκίνησε καινούργια: το ημερολόγιο και «Τα προϊόντα μου» ξαναμπαίνουν
  /// σε αυτήν, σε ΜΙΑ συναλλαγή όπου ό,τι υπάρχει ήδη στη νέα βάση μένει όπως είναι ([FoodChannel.restorePut]): πρώτα
  /// ό,τι έχει η μνήμη (ό,τι βλέπει ο χρήστης), μετά ό,τι διαβάζεται από το αρχείο που κρατήθηκε ([dbRecoveryRows]).
  /// Πριν, ξαναγραφόταν μόνο το ιστορικό· το φαγητό χανόταν στο επόμενο άνοιγμα. Μία φορά για κάθε βλάβη (σημειώνεται
  /// στην πλευρά Android). Απάντηση: πόσα ξαναμπήκαν, ή null αν δεν έγινε τώρα (ξαναδοκιμάζεται στην επόμενη ανανέωση).
  Future<({int entries, int foods})?> recoverAfterDbReset(int at) async {
    if (_offline || _recovering || _recoveredAt == at) return null;
    _recovering = true;
    try {
      final u = _unmarked;
      if (u != null && u.at == at) {
        final m = await FoodChannel.salvageDone(at, u.entries, u.foods, complete: u.complete);
        if (m['ok'] != true) return null;
        _unmarked = null;
        _recoveredAt = at;
        return (entries: u.entries, foods: u.foods);
      }
      await waitLoaded();
      final kept = await FoodChannel.salvageRead(at);
      if (kept['ok'] != true) return null;
      int count(Object? v) => v is num && v.isFinite ? v.toInt() : 0;
      if (kept['done'] == true) {
        _recoveredAt = at;
        return (entries: count(kept['entries']), foods: count(kept['foods']));
      }
      final rows = dbRecoveryRows(
        memoryEntries: _entries.values,
        memoryFoods: _mine,
        keptEntries: kept['entries'] is List ? kept['entries'] as List : const [],
        keptFoods: kept['foods'] is List ? kept['foods'] as List : const [],
        removedEntries: _removedIds,
        removedFoods: _removedFoodIds,
      );
      var entries = 0, foods = 0;
      if (rows.log.isNotEmpty || rows.foods.isNotEmpty) {
        final r = await FoodChannel.restorePut(jsonEncode(rows.log), jsonEncode(rows.foods));
        if (r['ok'] != true) return null;
        entries = count(r['entries']);
        foods = count(r['foods']);
      }
      // Round 8 (R8-A9-1/3, f4): αν διαβάστηκε όλο το αρχείο (αλλιώς η πλευρά Android το ξαναδιαβάζει με νεότερο κανόνα).
      // Το σημάδι ελέγχεται: χωρίς αυτό, το επόμενο άνοιγμα θα ξαναδιάβαζε το αρχείο· τότε ξαναδοκιμάζεται μόνο το σημάδι.
      final complete = kept['complete'] == true;
      final marked = await FoodChannel.salvageDone(at, entries, foods, complete: complete);
      if (marked['ok'] == true) {
        _recoveredAt = at;
      } else {
        _unmarked = (at: at, entries: entries, foods: foods, complete: complete);
      }
      skippedRows += rows.skipped;
      // Η οθόνη από τη νέα βάση: και όσα ήρθαν από το αρχείο (π.χ. οι μέρες της εβδομάδας, τα προϊόντα). Όπως στο
      // [retry]: ένα παλιό «δεν διαβάστηκε» φεύγει, και ξαναμπαίνει αν η ανάγνωση αποτύχει πάλι.
      if (_basic.isNotEmpty) error = null;
      await _loadMine();
      await _loadEntries();
      _rebuildIndex();
      notifyListeners();
      return marked['ok'] == true ? (entries: entries, foods: foods) : null;
    } finally {
      _recovering = false;
    }
  }

  /// Καταχωρίσεις (των τελευταίων 90 ημερών) με αυτό το προϊόν, που έχουν άλλες τιμές από το [f], ή άλλο «μετρά ως»
  /// για την κάρτα «Χοληστερίνη» ([Food.cholKind]· έλεγχος round1, S2-1: αλλιώς, όταν ορίζεις αργότερα ότι το προϊόν
  /// είναι π.χ. ξηροί καρποί, οι μέρες που το είχες ήδη γράψει θα έμεναν να μη μετρούν, χωρίς τρόπο να διορθωθούν).
  List<LogEntry> entriesWithOldValues(Food f) => [
        for (final e in _entries.values)
          if (e.food.id == f.id && (!_sameNutrients(e.food.n, f.n) || e.food.cholKind != f.cholKind)) e,
      ];

  static bool _sameNutrients(Nutrients a, Nutrients b) {
    final ka = a.values.keys.toSet(), kb = b.values.keys.toSet();
    if (ka.length != kb.length || !ka.containsAll(kb)) return false;
    for (final k in ka) {
      if (jsonEncode(a.values[k]!.toJson()) != jsonEncode(b.values[k]!.toJson())) return false;
    }
    return true;
  }

  /// Διόρθωση προϊόντος: οι καταχωρίσεις του παίρνουν τις νέες τιμές (ίδια γραμμάρια).
  /// Επιστρέφει πόσες γράφτηκαν.
  Future<int> applyFoodToEntries(Food f, List<LogEntry> entries) async {
    var n = 0;
    for (final e in entries) {
      if (await _put(e.copyWith(food: f))) n++;
    }
    return n;
  }
}
