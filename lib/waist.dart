/// Μέση με μεζούρα (σχέδια 12/11): δύο μετρήσεις και ο μέσος όρος, τρίτη αν διαφέρουν πάνω από 1 cm. Μία τιμή τη μέρα.
/// Αποθηκεύεται στις ρυθμίσεις (κλειδί «waist»: λίγα byte τον χρόνο) και μπαίνει στο αντίγραφο ασφαλείας· στην
/// επαναφορά προστίθενται μόνο οι μέρες που λείπουν.
/// Εύρος αναφοράς ανδρών: κάτω από 94 cm, υψηλός κίνδυνος από 102 (ESC 2021)· γυναικών: κάτω από 80, υψηλός από 88.
library;

const waistMinCm = 50.0;
const waistMaxCm = 200.0;

/// Πάνω από τόση διαφορά ανάμεσα σε δύο μετρήσεις χρειάζεται τρίτη.
const waistSpreadCm = 1.0;

class WaistEntry {
  const WaistEntry(this.day, this.values);

  /// «2026-11-20»
  final String day;

  /// Οι μετρήσεις (2 ή 3), σε cm.
  final List<double> values;

  /// Ο μέσος όρος (με 3 μετρήσεις: των δύο πιο κοντινών, όπως τα πρωτόκολλα μέτρησης).
  double get cm {
    if (values.length < 3) return values.reduce((a, b) => a + b) / values.length;
    final v = [...values]..sort();
    return (v[1] - v[0]) <= (v[2] - v[1]) ? (v[0] + v[1]) / 2 : (v[1] + v[2]) / 2;
  }

  Map<String, dynamic> toJson() => {'d': day, 'v': values};

  static WaistEntry? fromJson(Object? j) {
    if (j is! Map || j['d'] is! String || j['v'] is! List) return null;
    final v = [
      for (final x in j['v'] as List)
        if (x is num && x >= waistMinCm && x <= waistMaxCm) x.toDouble(),
    ];
    if (v.isEmpty || v.length > 3) return null;
    return WaistEntry(j['d'] as String, v);
  }
}

/// Χρειάζεται τρίτη μέτρηση;
bool needsThird(double a, double b) => (a - b).abs() > waistSpreadCm + 1e-9;

List<WaistEntry> waistFromJson(Object? j) {
  final out = <String, WaistEntry>{};
  if (j is List) {
    for (final x in j) {
      final e = WaistEntry.fromJson(x);
      if (e != null) out[e.day] = e;
    }
  }
  return out.values.toList()..sort((a, b) => a.day.compareTo(b.day));
}

/// Ένωση για την επαναφορά: οι μέρες του κινητού μένουν όπως είναι, από το αντίγραφο μπαίνουν όσες λείπουν.
List<Map<String, dynamic>> mergeWaist(Object? device, Object? backup) {
  final m = {for (final e in waistFromJson(backup)) e.day: e};
  for (final e in waistFromJson(device)) {
    m[e.day] = e;
  }
  final list = m.values.toList()..sort((a, b) => a.day.compareTo(b.day));
  return [for (final e in list) e.toJson()];
}

/// Εύρος αναφοράς (ESC 2021).
({double ok, double high}) waistRef(bool male) => male ? (ok: 94, high: 102) : (ok: 80, high: 88);
