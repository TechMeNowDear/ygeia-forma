/// «Η κουζίνα μου»: συσκευές και σκεύη, για συνταγές που γίνονται μόνο με ό,τι υπάρχει
/// (μάρκα, μέγεθος). Το απόβαρο το κάνει η ζυγαριά του χρήστη, όχι η εφαρμογή (απόφαση 25/10).
library;

import '../format.dart' show dotJoin;

/// Συσκευές που αλλάζουν το πώς γίνεται μια συνταγή.
const kitchenDevices = <(String, String, String)>[
  ('oven', 'Φούρνος', 'με ταψιά'),
  ('hob', 'Μάτια κουζίνας', 'για κατσαρόλες, τηγάνια, μπρίκι'),
  ('steamer', 'Ατμομάγειρας', 'ρύζι, πατάτες, κοτόπουλο, λαχανικά, αυγά'),
  ('gasGrill', 'Ψησταριά υγραερίου', 'π.χ. Weber'),
  ('charcoalGrill', 'Ψησταριά κάρβουνου', ''),
  ('deepFryer', 'Φριτέζα λαδιού', 'πολλές θερμίδες· μόνο όταν το επιτρέπουν οι στόχοι'),
  ('airFryer', 'Φριτέζα αέρος (air fryer)', ''),
  ('kettle', 'Βραστήρας', ''),
  ('briki', 'Μπρίκι', ''),
  ('scale', 'Ζυγαριά κουζίνας', 'για ζύγισμα ωμών και μαγειρεμένων'),
  ('microwave', 'Φούρνος μικροκυμάτων', ''),
  ('blender', 'Μπλέντερ / πολυμίξερ', ''),
  ('toaster', 'Τοστιέρα / γκριλιέρα', ''),
  ('pressureCooker', 'Χύτρα ταχύτητας', ''),
];

const cookwareKinds = <(String, String)>[
  ('panNonstick', 'Τηγάνι αντικολλητικό'),
  ('panCastIron', 'Τηγάνι μαντεμένιο'),
  ('panSteel', 'Τηγάνι ανοξείδωτο'),
  ('pot', 'Κατσαρόλα'),
  ('tray', 'Ταψί'),
  ('glass', 'Γυάλινο πυρίμαχο'),
  ('other', 'Άλλο σκεύος'),
];

const cookwareSizes = ['Μικρό', 'Μεσαίο', 'Μεγάλο'];

/// Το μέγεθος συμφωνεί με το σκεύος: «κατσαρόλα μικρή», «τηγάνι μικρό».
/// Αποθηκεύεται πάντα στο ουδέτερο ([cookwareSizes]).
String cookwareSizeLabel(String kind, String size) {
  if (kind != 'pot') return size;
  return switch (size) { 'Μικρό' => 'Μικρή', 'Μεσαίο' => 'Μεσαία', 'Μεγάλο' => 'Μεγάλη', _ => size };
}

String cookwareKindLabel(String k) => cookwareKinds.firstWhere((e) => e.$1 == k, orElse: () => (k, k)).$2;

class Cookware {
  Cookware({required this.id, required this.kind, this.size, this.brand, this.note});
  final String id;
  String kind;
  String? size;
  String? brand;

  String? note;

  String get label => [
        cookwareKindLabel(kind),
        if (size != null) cookwareSizeLabel(kind, size!).toLowerCase(),
        if (brand != null && brand!.isNotEmpty) brand!,
        if (note != null && note!.isNotEmpty) note!,
        // Round 11 (R11-C2-3): το «·» με τον κανόνα [dotJoin] (κανονικό κενό πριν, αδιάσπαστο μετά): η γραμμή δεν τελειώνει
        // σε «·» («… μεσαίο» / «· Tefal»). Πριν (R9-U2 ΒΕΛΤΙΩΣΗ-Α) το αδιάσπαστο ήταν πριν από το «·», και η γραμμή
        // έσπαγε «… μεσαίο ·» / «Tefal», ενώ το σχόλιο έλεγε το αντίθετο.
      ].join(dotJoin);

  factory Cookware.fromJson(Map<String, dynamic> j) => Cookware(
        id: j['id'] as String,
        kind: j['kind'] as String,
        size: j['size'] is String ? j['size'] as String : null,
        brand: j['brand'] is String ? j['brand'] as String : null,
        note: j['note'] is String ? j['note'] as String : null,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind,
        if (size != null) 'size': size,
        if (brand != null) 'brand': brand,
        if (note != null) 'note': note,
      };
}

class Kitchen {
  Kitchen({
    Set<String>? devices,
    this.hob,
    this.ovenFan,
    this.steamerTiers,
    this.airFryerLiters,
    this.scaleMaxKg,
    List<Cookware>? cookware,
  })  : devices = devices ?? {},
        cookware = cookware ?? [];

  final Set<String> devices;

  /// «Κεραμικά», «Επαγωγικά», «Γκάζι», «Εμαγιέ».
  String? hob;
  bool? ovenFan;
  int? steamerTiers;
  double? airFryerLiters;
  double? scaleMaxKg;
  final List<Cookware> cookware;

  bool has(String d) => devices.contains(d);

  /// Έκδοση των προσωπικών προεπιλογών. Όταν ο χρήστης μου λέει κάτι νέο για την κουζίνα του,
  /// ανεβαίνει και το [_upgrade] το προσθέτει χωρίς να σβήσει ό,τι έχει ήδη γράψει.
  static const seedVersion = 2;

  /// Τελικός έλεγχος (Συμβούλιο 3): ανεκτική ανάγνωση. Η κουζίνα έρχεται και από αντίγραφο ασφαλείας· ένα πεδίο με λάθος
  /// τύπο («hob»: 5, σκεύος χωρίς id, 1e999) αγνοείται. Πριν πετούσε σφάλμα κάθε φορά που άνοιγαν «Τα στοιχεία μου».
  factory Kitchen.fromJson(Map<String, dynamic>? j) {
    if (j == null) return Kitchen.initial();
    double? number(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
    final k = Kitchen(
      devices: {for (final d in j['devices'] is List ? j['devices'] as List : const []) d.toString()},
      hob: j['hob'] is String ? j['hob'] as String : null,
      ovenFan: j['ovenFan'] is bool ? j['ovenFan'] as bool : null,
      steamerTiers: number(j['steamerTiers'])?.toInt(),
      airFryerLiters: number(j['airFryerLiters']),
      scaleMaxKg: number(j['scaleMaxKg']),
      cookware: [
        for (final c in j['cookware'] is List ? j['cookware'] as List : const [])
          if (c is Map && c['id'] is String && c['kind'] is String) Cookware.fromJson(Map<String, dynamic>.from(c)),
      ],
    );
    final seed = number(j['seed'])?.toInt() ?? 1;
    if (seed < 2) k._upgradeTo2();
    return k;
  }

  /// 24/10 βράδυ: μάτια κεραμικά, φούρνος με αέρα, 3 κατσαρόλες, Pyrex, τοστιέρα, μπλέντερ.
  /// Συμπληρώνει μόνο ό,τι λείπει· δεν αλλάζει όσα έγραψε ήδη ο χρήστης.
  void _upgradeTo2() {
    devices.addAll(const {'toaster', 'blender'});
    hob ??= 'Κεραμικά';
    ovenFan ??= true;
    final pots = cookware.where((c) => c.kind == 'pot').toList();
    // Η αρχική «Κατσαρόλα» χωρίς μέγεθος γίνεται τρεις.
    if (pots.length == 1 && pots.first.size == null) {
      final i = cookware.indexOf(pots.first);
      cookware
        ..removeAt(i)
        ..insertAll(i, [
          Cookware(id: 'c6', kind: 'pot', size: 'Μικρό'),
          Cookware(id: 'c8', kind: 'pot', size: 'Μεσαίο'),
          Cookware(id: 'c9', kind: 'pot', size: 'Μεγάλο'),
        ]);
    }
    if (!cookware.any((c) => c.kind == 'glass')) {
      cookware.add(Cookware(id: 'c10', kind: 'glass', brand: 'Pyrex'));
    }
  }

  Map<String, dynamic> toJson() => {
        'seed': seedVersion,
        'devices': devices.toList()..sort(),
        if (hob != null) 'hob': hob,
        if (ovenFan != null) 'ovenFan': ovenFan,
        if (steamerTiers != null) 'steamerTiers': steamerTiers,
        if (airFryerLiters != null) 'airFryerLiters': airFryerLiters,
        if (scaleMaxKg != null) 'scaleMaxKg': scaleMaxKg,
        'cookware': [for (final c in cookware) c.toJson()],
      };

  /// Αρχική κατάσταση: ό,τι έχει πει ο χρήστης στο αρχείο «Συσκευές Μαγειρέματος» (24/10).
  /// ΣΗΜΕΙΩΣΗ: προσωπικές προεπιλογές· πριν από δημόσια έκδοση η κουζίνα ξεκινά άδεια.
  factory Kitchen.initial() => Kitchen(
        devices: {
          'oven', 'hob', 'steamer', 'gasGrill', 'deepFryer', 'kettle', 'briki', 'scale', 'toaster', 'blender',
        },
        hob: 'Κεραμικά',
        ovenFan: true,
        steamerTiers: 2,
        cookware: [
          Cookware(id: 'c1', kind: 'panNonstick', size: 'Μικρό', brand: 'Tefal'),
          Cookware(id: 'c2', kind: 'panNonstick', size: 'Μεσαίο', brand: 'Tefal'),
          Cookware(id: 'c3', kind: 'panNonstick', size: 'Μεγάλο', brand: 'Tefal'),
          Cookware(id: 'c4', kind: 'panCastIron'),
          Cookware(id: 'c5', kind: 'panCastIron'),
          Cookware(id: 'c6', kind: 'pot', size: 'Μικρό'),
          Cookware(id: 'c8', kind: 'pot', size: 'Μεσαίο'),
          Cookware(id: 'c9', kind: 'pot', size: 'Μεγάλο'),
          Cookware(id: 'c7', kind: 'tray'),
          Cookware(id: 'c10', kind: 'glass', brand: 'Pyrex'),
        ],
      );
}
