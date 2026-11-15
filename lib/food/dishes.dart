/// «Τα φαγητά μου» (αίτημα χρήστη 15/11): φαγητά φτιαγμένα από υλικά της βάσης, που γράφονται με ένα πάτημα.
///
/// Κανόνες (έγγραφο προδιαγραφών › «Διατροφή: Τα φαγητά μου και συνταγές», 15/11):
/// - Ένα φαγητό είναι ΜΟΝΟ υλικά της βάσης (ή «Τα προϊόντα μου») με ποσότητα. Οι αριθμοί βγαίνουν πάντα από τη βάση,
///   τη στιγμή που γράφεται το φαγητό· το φαγητό δεν κρατά δικές του τιμές.
/// - Όταν γράφεται, στο ημερολόγιο μπαίνει ΚΑΘΕ υλικό ως κανονική καταχώριση, με το σημάδι [DishTag] (ίδιο «grp» για όλα
///   τα υλικά της ίδιας καταγραφής). Έτσι σύνολα, στόχοι, «Χοληστερίνη» (όσπρια, ψάρι), εβδομαδιαίος έλεγχος θερμίδων και
///   αντίγραφο μετρούν όπως πάντα, χωρίς καμία αλλαγή. Η οθόνη δείχνει τα υλικά μιας καταγραφής ως μία γραμμή.
/// - Τρία είδη ([DishKind]):
///   - πιάτο: το τρως όλο· κάθε φορά μπορείς να αλλάξεις την ποσότητα κάθε υλικού (ξεκινά από την τελευταία φορά).
///   - ίσες μερίδες: η συνταγή βγάζει [Dish.servings] μερίδες· γράφεις πόσες έφαγες (υλικό × έφαγα ÷ μερίδες).
///   - κατσαρόλα: ζυγίζεις όλο το έτοιμο φαγητό ([PotBatch.cooked]) και τη μερίδα σου (υλικό × μερίδα ÷ έτοιμο). Το βάρος
///     του έτοιμου κρατιέται για τα περισσεύματα, ώσπου να πεις «Νέο μαγείρεμα».
library;

import 'dart:math' as math;

import '../format.dart' show daysBetween;
import 'food_channel.dart';
import 'food_model.dart';
import 'food_search.dart' show phonetic, stem;

enum DishKind { plate, portions, pot }

DishKind? dishKindOf(Object? v) => switch (v) {
      'plate' => DishKind.plate,
      'portions' => DishKind.portions,
      'pot' => DishKind.pot,
      _ => null,
    };

/// Το όνομα του είδους στις λίστες.
String dishKindLabel(DishKind k) => switch (k) {
      DishKind.plate => 'Πιάτο',
      DishKind.portions => 'Ίσες μερίδες',
      DishKind.pot => 'Κατσαρόλα',
    };

/// Όρια (δική μας επιλογή, ώστε ένα χαλασμένο ή πειραγμένο αρχείο να μη φτιάχνει παράλογα φαγητά).
const maxDishItems = 40;
const maxDishServings = 50;
const maxDishNameLength = 80;

/// Το πολύ τόσο ζυγίζει όλο το έτοιμο φαγητό μιας κατσαρόλας (20 kg: πολύ μεγάλη κατσαρόλα ή δύο ταψιά).
const maxCookedGrams = 20000.0;

/// Το πολύ τόσες μερίδες γράφονται σε μία καταγραφή.
const maxEatenServings = 20.0;

/// Ακρίβεια των ποσοτήκων που γράφονται στο ημερολόγιο: εκατοστό του γραμμαρίου. Μικρότερη ποσότητα δεν γράφεται (π.χ.
/// 1 g αλάτι σε κατσαρόλα 5 kg, μερίδα 20 g = 0,004 g): η καταχώριση με 0 g δεν θα γινόταν δεκτή στην επαναφορά.
double roundAmount(double v) => (v * 100).round() / 100;

/// Υλικό: τρόφιμο (id της βάσης ή δικό μου προϊόν) και ποσότητα σε g (ή ml, για τρόφιμα ανά 100 ml), όπως ζυγίστηκε.
class DishItem {
  const DishItem(this.id, this.name, this.amount);
  final String id;

  /// Το όνομα τη στιγμή που μπήκε· φαίνεται μόνο αν το τρόφιμο δεν υπάρχει πια (π.χ. σβησμένο προϊόν).
  final String name;
  final double amount;

  DishItem withAmount(double a) => DishItem(id, name, a);

  Map<String, Object> toJson() => {'id': id, 'n': name, 'g': amount};

  /// null αν δεν είναι σωστό υλικό (χωρίς id, ποσότητα 0, αρνητική, πάνω από [maxEntryGrams], όχι αριθμός).
  static DishItem? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], n = j['n'], g = j['g'];
    if (id is! String || id.isEmpty || g is! num || !g.isFinite || g <= 0 || g > maxEntryGrams) return null;
    return DishItem(id, n is String ? n : id, g.toDouble());
  }
}

/// Ένα μαγείρεμα της κατσαρόλας: πότε ([at], ms), πόσο ζύγιζε όλο το έτοιμο φαγητό ([cooked], g) και με ποια υλικά.
class PotBatch {
  const PotBatch({required this.at, required this.cooked, required this.items});
  final int at;
  final double cooked;
  final List<DishItem> items;

  Map<String, Object> toJson() => {'at': at, 'c': cooked, 'items': [for (final i in items) i.toJson()]};

  static PotBatch? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = j['at'], c = j['c'], items = j['items'];
    if (at is! num || !at.isFinite || c is! num || !c.isFinite || c <= 0 || c > maxCookedGrams || items is! List) return null;
    final out = <DishItem>[];
    for (final i in items) {
      final d = DishItem.fromJson(i);
      if (d == null) return null;
      out.add(d);
    }
    if (out.isEmpty || out.length > maxDishItems) return null;
    return PotBatch(at: at.toInt(), cooked: c.toDouble(), items: out);
  }
}

/// Τα κλειδιά που ξέρει αυτή η έκδοση. Όσα άλλα έχει ένα φαγητό (από νεότερη έκδοση) μένουν όπως είναι ([Dish.extra]).
const _dishKeys = {'id', 'name', 'kind', 'items', 'serv', 'batch', 'lastPlate', 'lastQty', 'created', 'used', 'uses'};

class Dish {
  const Dish({
    required this.id,
    required this.name,
    required this.kind,
    required this.items,
    this.servings = 1,
    this.batch,
    this.lastPlate,
    this.lastQty,
    required this.created,
    this.used,
    this.uses = 0,
    this.extra = const {},
  });

  final String id;
  final String name;
  final DishKind kind;

  /// Τα υλικά της συνταγής, με τις ποσότητές τους (ωμά, όπως ζυγίζονται).
  final List<DishItem> items;

  /// Ίσες μερίδες: πόσες μερίδες βγάζει η συνταγή (1–[maxDishServings]). Στα άλλα είδη 1.
  final int servings;

  /// Κατσαρόλα: το τελευταίο μαγείρεμα (null: δεν έχει μαγειρευτεί ακόμα).
  final PotBatch? batch;

  /// Πιάτο: οι ποσότητες της τελευταίας φοράς, μία για κάθε υλικό με τη σειρά τους (0 = δεν το έφαγες). Σβήνεται όταν
  /// αλλάζουν τα υλικά.
  final List<double>? lastPlate;

  /// Ίσες μερίδες: πόσες μερίδες έφαγες την τελευταία φορά. Κατσαρόλα: η μερίδα σου (g) την τελευταία φορά.
  final double? lastQty;

  /// Πότε φτιάχτηκε, πότε γράφτηκε τελευταία φορά (ms) και πόσες φορές.
  final int created;
  final int? used;
  final int uses;

  /// Κλειδιά από νεότερη έκδοση της εφαρμογής: μένουν όπως είναι, ώστε να μη χαθούν όταν το φαγητό αποθηκευτεί ξανά.
  final Map<String, Object?> extra;

  Dish copyWith({
    String? name,
    DishKind? kind,
    List<DishItem>? items,
    int? servings,
    PotBatch? batch,
    bool clearBatch = false,
    List<double>? lastPlate,
    bool clearLastPlate = false,
    double? lastQty,
    bool clearLastQty = false,
    int? used,
    int? uses,
  }) =>
      Dish(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        items: items ?? this.items,
        servings: servings ?? this.servings,
        batch: clearBatch ? null : (batch ?? this.batch),
        lastPlate: clearLastPlate ? null : (lastPlate ?? this.lastPlate),
        lastQty: clearLastQty ? null : (lastQty ?? this.lastQty),
        created: created,
        used: used ?? this.used,
        uses: uses ?? this.uses,
        extra: extra,
      );

  Map<String, Object?> toJson() => {
        ...extra,
        'id': id,
        'name': name,
        'kind': kind.name,
        'items': [for (final i in items) i.toJson()],
        if (kind == DishKind.portions) 'serv': servings,
        if (batch != null) 'batch': batch!.toJson(),
        if (lastPlate != null) 'lastPlate': lastPlate,
        if (lastQty != null) 'lastQty': lastQty,
        'created': created,
        if (used != null) 'used': used,
        if (uses > 0) 'uses': uses,
      };

  /// null αν δεν είναι σωστό φαγητό. Ό,τι μικρό δεν στέκει (π.χ. χαλασμένο τελευταίο μαγείρεμα ή «τελευταία φορά») απλώς
  /// δεν διαβάζεται· το φαγητό μένει.
  static Dish? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'], kind = dishKindOf(j['kind']), items = j['items'];
    if (id is! String || id.isEmpty || name is! String || name.trim().isEmpty || kind == null || items is! List) return null;
    final list = <DishItem>[];
    for (final i in items) {
      final d = DishItem.fromJson(i);
      if (d == null) return null;
      list.add(d);
    }
    if (list.isEmpty || list.length > maxDishItems) return null;
    int? whole(Object? v) => v is num && v.isFinite ? v.toInt() : null;
    final serv = whole(j['serv']);
    final servings = kind == DishKind.portions ? (serv != null && serv >= 1 && serv <= maxDishServings ? serv : null) : 1;
    if (servings == null) return null;
    final lp = j['lastPlate'];
    final lastPlate = lp is List &&
            lp.length == list.length &&
            lp.every((x) => x is num && x.isFinite && x >= 0 && x <= maxEntryGrams)
        ? [for (final x in lp) (x as num).toDouble()]
        : null;
    final lq = j['lastQty'];
    final lastQty = lq is num && lq.isFinite && lq > 0 && lq <= maxCookedGrams ? lq.toDouble() : null;
    return Dish(
      id: id,
      name: name.trim(),
      kind: kind,
      items: list,
      servings: servings,
      batch: kind == DishKind.pot ? PotBatch.fromJson(j['batch']) : null,
      lastPlate: kind == DishKind.plate ? lastPlate : null,
      lastQty: kind == DishKind.plate ? null : lastQty,
      created: whole(j['created']) ?? 0,
      used: whole(j['used']),
      uses: math.max(0, whole(j['uses']) ?? 0),
      extra: {
        for (final e in j.entries)
          if (e.key is String && !_dishKeys.contains(e.key)) e.key as String: e.value,
      },
    );
  }
}

/// Το φαγητό [d] με την τιμή [value] στο κλειδί [key] των επιπλέον στοιχείων ([Dish.extra]: συνταγή, βιβλιοθήκη), ή χωρίς
/// το κλειδί αν [value] είναι null. Όλα τα άλλα μένουν όπως είναι.
Dish withExtra(Dish d, String key, Object? value) => Dish(
      id: d.id,
      name: d.name,
      kind: d.kind,
      items: d.items,
      servings: d.servings,
      batch: d.batch,
      lastPlate: d.lastPlate,
      lastQty: d.lastQty,
      created: d.created,
      used: d.used,
      uses: d.uses,
      extra: {
        for (final e in d.extra.entries)
          if (e.key != key) e.key: e.value,
        if (value != null) key: value,
      },
    );

/// Το σημάδι μιας καταχώρισης που γράφτηκε ως υλικό φαγητού (κλειδί «dish» στην καταχώριση· οι παλιές εκδόσεις το
/// αγνοούν και τη δείχνουν ως απλό τρόφιμο, με τα ίδια γραμμάρια και τις ίδιες θερμίδες).
class DishTag {
  const DishTag({required this.id, required this.name, required this.grp, required this.kind, required this.qty, this.batch});

  /// Το φαγητό ([Dish.id]) και το όνομά του τη στιγμή που γράφτηκε.
  final String id;
  final String name;

  /// Ίδιο για όλα τα υλικά της ίδιας καταγραφής.
  final String grp;
  final DishKind kind;

  /// Πόσο έφαγες: πιάτο = τα γραμμάρια όλων των υλικών μαζί· ίσες μερίδες = πόσες μερίδες· κατσαρόλα = η μερίδα σου (g
  /// του έτοιμου φαγητού).
  final double qty;

  /// Κατσαρόλα: το μαγείρεμα ([PotBatch.at]) από το οποίο έφαγες.
  final int? batch;

  DishTag withQty(double q) => DishTag(id: id, name: name, grp: grp, kind: kind, qty: q, batch: batch);
  DishTag withGrp(String g) => DishTag(id: id, name: name, grp: g, kind: kind, qty: qty, batch: batch);

  Map<String, Object> toJson() => {'id': id, 'n': name, 'grp': grp, 'k': kind.name, 'q': qty, if (batch != null) 'b': batch!};

  static DishTag? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], n = j['n'], grp = j['grp'], k = dishKindOf(j['k']), q = j['q'], b = j['b'];
    if (id is! String || grp is! String || grp.isEmpty || k == null || q is! num || !q.isFinite || q <= 0) return null;
    return DishTag(
      id: id,
      name: n is String && n.trim().isNotEmpty ? n : 'Φαγητό',
      grp: grp,
      kind: k,
      qty: q.toDouble(),
      batch: b is num && b.isFinite ? b.toInt() : null,
    );
  }
}

/// Οι ποσότητες που γράφονται για μία καταγραφή του φαγητού [d] (ήδη στρογγυλεμένες, χωρίς υλικά με 0):
/// - πιάτο: [plate] (μία ποσότητα για κάθε υλικό, 0 = δεν το έφαγες)·
/// - ίσες μερίδες: υλικό × [servings] ÷ μερίδες της συνταγής·
/// - κατσαρόλα: υλικό του μαγειρέματος [batch] × [portion] ÷ βάρος του έτοιμου.
List<DishItem> dishAmounts(Dish d, {List<double>? plate, double? servings, double? portion, PotBatch? batch}) {
  List<DishItem> scaled(List<DishItem> items, double factor) => [
        for (final i in items)
          if (roundAmount(i.amount * factor) > 0) i.withAmount(roundAmount(i.amount * factor)),
      ];
  switch (d.kind) {
    case DishKind.plate:
      final p = plate ?? [for (final i in d.items) i.amount];
      return [
        for (var k = 0; k < d.items.length && k < p.length; k++)
          if (roundAmount(p[k]) > 0) d.items[k].withAmount(roundAmount(p[k])),
      ];
    case DishKind.portions:
      final s = servings ?? 1;
      return s > 0 ? scaled(d.items, s / d.servings) : const [];
    case DishKind.pot:
      final b = batch ?? d.batch;
      final g = portion ?? 0;
      return b == null || g <= 0 ? const [] : scaled(b.items, g / b.cooked);
  }
}

/// Το άθροισμα των ποσοτήτων (g/ml).
double itemsSum(Iterable<DishItem> items) => items.fold(0.0, (a, i) => a + i.amount);

/// Μία καταγραφή που μοιάζει με λάθος: τόσες θερμίδες ή περισσότερες, όσες η πρόσληψη αναφοράς όλης της μέρας ([typoEntryKcal]).
/// Ρωτά μία φορά, δεν μπλοκάρει.
bool dishLooksLikeTypo(double kcal) => kcal >= typoEntryKcal;

/// Το έτοιμο φαγητό ζυγίζει πολύ λιγότερο από τα ωμά υλικά: λιγότερο από το [cookedTooLightShare] τους. Συνήθως το
/// έτοιμο ζυγίζει περισσότερο (όσπρια, ρύζι, ζυμαρικά ρουφούν νερό) ή λίγο λιγότερο (ψητά: το κρέας χάνει περίπου το
/// 25–35% του βάρους του). Κάτω από το 40% είναι σχεδόν σίγουρα λάθος (π.χ. ζύγισες μόνο ένα μέρος). Ρωτά μία φορά.
const cookedTooLightShare = 0.4;
bool cookedLooksWrong(double raw, double cooked) => raw > 0 && cooked < cookedTooLightShare * raw;

/// Αναζήτηση στα φαγητά μου: κάθε λέξη του [q] είναι αρχή μιας λέξης του ονόματος (χωρίς τόνους, και σε greeklish,
/// όπως η αναζήτηση τροφίμων). Τα πιο συχνά πρώτα.
List<Dish> searchDishes(List<Dish> all, String q) {
  List<String> words(String s) => phonetic(s).split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty).toList();
  final qs = words(q);
  if (qs.isEmpty) return const [];
  final out = <Dish>[];
  for (final d in all) {
    final ws = words(d.name);
    final stems = [for (final w in ws) stem(w)];
    var ok = true;
    for (final x in qs) {
      final sx = stem(x);
      if (!ws.any((w) => w.startsWith(x)) && !stems.any((w) => w == sx || (sx.length >= 3 && w.startsWith(sx)))) {
        ok = false;
        break;
      }
    }
    if (ok) out.add(d);
  }
  out.sort((a, b) => b.uses.compareTo(a.uses));
  return out;
}

/// Η σειρά στις λίστες: όσα έγραψες πιο πρόσφατα πρώτα, μετά τα καινούργια (πιο πρόσφατο πρώτο).
List<Dish> dishesInOrder(Iterable<Dish> all) => all.toList()
  ..sort((a, b) {
    final ua = a.used ?? a.created, ub = b.used ?? b.created;
    final c = ub.compareTo(ua);
    return c != 0 ? c : a.name.compareTo(b.name);
  });

/// Μέρες μετά το μαγείρεμα που το «ένα πάτημα» δεν γράφει πια από το ίδιο μαγείρεμα, αλλά ανοίγει την οθόνη (να φανεί
/// αν είναι νέο μαγείρεμα). Τα περισσεύματα κρατούν 3–4 μέρες στο ψυγείο (USDA FSIS, «Leftovers and Food Safety»).
const potQuickDays = 4;

/// «σήμερα», «χθες», «πριν από 3 μέρες»: πότε μαγειρεύτηκε.
String cookedAgo(DateTime at, DateTime now) {
  final d = daysBetween(at, now);
  if (d <= 0) return 'σήμερα';
  if (d == 1) return 'χθες';
  return 'πριν από $d μέρες';
}

// ---------------------------------------------------------------------------
// Αποθήκευση: το αρχείο «dishes.json» (δίπλα στο training.json· μπαίνει στο κρυπτογραφημένο αντίγραφο Google)
// ---------------------------------------------------------------------------

abstract class DishIO {
  /// «ok» (με το κείμενο), «missing» (δεν υπάρχει ακόμα) ή «error» (δεν διαβάστηκε: τότε δεν γράφεται τίποτα).
  Future<({String state, String? json})> read();
  Future<bool> write(String json);

  /// Το αρχείο που δεν διαβάζεται μπαίνει στην άκρη: το νέο όνομα, ή null αν δεν έγινε (τότε δεν αλλάζει τίποτα).
  Future<String?> setAside();
}

class ChannelDishIO implements DishIO {
  @override
  Future<({String state, String? json})> read() async {
    final r = await FoodChannel.dishesRead();
    if (r['ok'] != true) return (state: 'error', json: null);
    final st = r['state'];
    if (st == 'missing') return (state: 'missing', json: null);
    final j = r['json'];
    return st == 'ok' && j is String ? (state: 'ok', json: j) : (state: 'error', json: null);
  }

  @override
  Future<bool> write(String json) async => (await FoodChannel.dishesWrite(json))['ok'] == true;

  @override
  Future<String?> setAside() async {
    final r = await FoodChannel.dishesBad();
    return r['ok'] == true && r['name'] is String ? r['name'] as String : null;
  }
}

/// Για δοκιμές: το αρχείο στη μνήμη. [failWrites]: κάθε εγγραφή αποτυγχάνει· [unreadable]: η ανάγνωση αποτυγχάνει.
class MemoryDishIO implements DishIO {
  MemoryDishIO([this.json]);
  String? json;
  String? setAsideJson;
  bool failWrites = false;
  bool unreadable = false;
  int writes = 0;

  @override
  Future<({String state, String? json})> read() async =>
      unreadable ? (state: 'error', json: null) : (state: json == null ? 'missing' : 'ok', json: json);

  @override
  Future<bool> write(String j) async {
    if (failWrites) return false;
    json = j;
    writes++;
    return true;
  }

  @override
  Future<String?> setAside() async {
    if (json == null) return null;
    setAsideJson = json;
    json = null;
    return 'dishes.json.bad';
  }
}
