/// Αντίγραφο ασφαλείας: ημερολόγιο φαγητού, «Τα προϊόντα μου» και ρυθμίσεις σε ένα αρχείο JSON.
///
/// Αυτά υπάρχουν μόνο στο κινητό (τα δεδομένα της Samsung ξαναδιαβάζονται, γι' αυτό δεν μπαίνουν). Και το σχέδιο
/// πηγών με το ημερολόγιό του (έλεγχος 4/11, A10): σε νέο κινητό, χωρίς αυτό, οι νύχτες του Oura θα γίνονταν σιωπηλά
/// νύχτες του ρολογιού.
/// Η επαναφορά **δεν σβήνει τίποτα** και **δεν αλλάζει ό,τι υπάρχει ήδη**: προσθέτει μόνο ό,τι λείπει· το σχέδιο πηγών
/// μπαίνει μόνο αν το κινητό δεν έχει νεότερο ([HealthStore.restoreSources]).
library;

import 'dart:convert';

import 'error_report.dart' show ErrorReporter;
import 'food/food_model.dart';
import 'format.dart';
import 'plan_file.dart';
import 'waist.dart' show isDayKey;

const backupApp = 'ygeia-forma';
const backupVersion = 1;

/// Οι ρυθμίσεις που μπαίνουν στο αντίγραφο (όχι η πρόοδος του ιστορικού, που είναι τεχνική).
const backupPrefKeys = ['cards', 'kitchen', 'themeMode', 'dayTheme', 'nightTheme', 'me', 'goals', 'zone', 'waist'];

/// [errorsOff]: Round 7 (R7-A11-4) ο χρήστης έχει κλειστές τις «Αναφορές σφαλμάτων» (αντίρρηση, ΓΚΠΔ άρθρο 21). Μπαίνει
/// στο αρχείο (πρόσθετο κλειδί «errorsOff», μόνο όταν είναι κλειστές), ώστε η επαναφορά σε νέο κινητό να τις κρατά
/// κλειστές, όπως ήδη το αντίγραφο της Google. Παλιά αντίγραφα χωρίς το κλειδί: ο διακόπτης δεν αλλάζει.
String buildBackup({
  required List<Map<String, dynamic>> foodLog,
  required List<Map<String, dynamic>> myFoods,
  required Map<String, dynamic> prefs,
  required DateTime now,
  ({String plan, String? log})? sources,
  Map<String, dynamic>? training,
  bool errorsOff = false,
}) {
  // Χωρίς κενά: το αρχείο συμπιέζεται κιόλας (gzip, στο Android), ώστε να μένει μικρό για χρόνια.
  return jsonEncode({
    'app': backupApp,
    'version': backupVersion,
    'created': now.toIso8601String(),
    'foodLog': foodLog,
    'myFoods': myFoods,
    'prefs': {
      for (final k in backupPrefKeys)
        if (prefs[k] != null) k: prefs[k],
    },
    // Τα αρχεία του σχεδίου πηγών όπως είναι (με την ώρα τους, «at»).
    if (sources != null) 'sources': {'plan': sources.plan, if (sources.log != null) 'log': sources.log},
    // Προπονήσεις και προγράμματα (έλεγχος 8/11, TRN-17): υπάρχουν μόνο στο κινητό.
    if (training != null) 'training': training,
    if (errorsOff) 'errorsOff': true,
  });
}

/// Ό,τι βρέθηκε σε ένα αρχείο αντιγράφου, ελεγμένο.
class BackupContents {
  BackupContents(this.entries, this.myFoods, this.prefs, this.created, this.skipped,
      {this.sources, this.training, this.errorsOff = false});

  /// Round 7 (R7-A11-4): στο κινητό του αντιγράφου οι «Αναφορές σφαλμάτων» ήταν κλειστές.
  final bool errorsOff;

  /// Οι προπονήσεις (όπως το training.json), αν υπήρχαν.
  final Map<String, dynamic>? training;

  /// Το σχέδιο πηγών και το ημερολόγιό του (κείμενο των αρχείων), αν υπήρχαν και διαβάζονται.
  final ({String plan, String? log})? sources;
  final List<LogEntry> entries;
  final List<Food> myFoods;
  final Map<String, dynamic> prefs;
  final DateTime? created;

  /// Εγγραφές που δεν διαβάστηκαν (χαλασμένες) και παραλείπονται.
  final int skipped;
}

class BackupError implements Exception {
  BackupError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Η μεγαλύτερη ποσότητα καταχώρισης που δέχεται η επαναφορά (g): 100 κιλά. Η οθόνη δέχεται ως 5.000 g· εδώ το όριο
/// είναι πολύ πιο πάνω, ώστε να μη χαθεί ποτέ κάτι που έγραψε η ίδια η εφαρμογή, αλλά να μην περνά ένας αριθμός που
/// δεν γίνεται να είναι φαγητό (χαλασμένο ή πειραγμένο αρχείο).
const backupMaxGrams = 100000.0;

/// Τιμές θρεπτικών που η εφαρμογή δεν γράφει ποτέ: αρνητικές ή μη πεπερασμένες (1e999 στο JSON γίνεται «άπειρο»).
bool _badNutrients(Food f) => f.n.values.values.any((v) => !v.value.isFinite || v.value < 0);

/// Καταχώριση που η εφαρμογή θα μπορούσε να έχει γράψει (για την επαναφορά από αρχείο: αντίγραφο ή, R7-A9-1, το
/// αρχείο της χαλασμένης βάσης). Υπαρκτή μέρα, ποσότητα πεπερασμένη ως [backupMaxGrams], θρεπτικά ≥ 0 και πεπερασμένα.
bool restorableEntry(LogEntry le) =>
    le.id.isNotEmpty && isDayKey(le.day) && le.grams > 0 && le.grams <= backupMaxGrams && !_badNutrients(le.food);

/// Προϊόν που η εφαρμογή θα μπορούσε να έχει γράψει: με id, όνομα και θρεπτικά ≥ 0 και πεπερασμένα.
bool restorableFood(Food f) => f.id.isNotEmpty && f.name.trim().isNotEmpty && !_badNutrients(f);

/// Round 7 (R7-A9-1): τι ξαναμπαίνει στη νέα βάση μετά από βλάβη (μία κλήση «restorePut», όπου ό,τι υπάρχει ήδη στη
/// νέα βάση μένει όπως είναι). Πρώτα ό,τι έχει η μνήμη ([memoryEntries], [memoryFoods]: όπως τα βλέπει ο χρήστης), μετά
/// ό,τι διαβάστηκε από το αρχείο που κρατήθηκε ([keptEntries], [keptFoods]: JSON όπως στη βάση) και δεν είναι ήδη από
/// τη μνήμη. Από το αρχείο ΔΕΝ ξαναμπαίνει ό,τι έσβησε ο χρήστης σε αυτή τη χρήση της εφαρμογής ([removedEntries],
/// [removedFoods]): μετά τη βλάβη το σβήσιμο έγινε μόνο στη μνήμη. Ό,τι δεν διαβάζεται ή δεν θα το έγραφε ποτέ η
/// εφαρμογή ([restorableEntry], [restorableFood]) παραλείπεται και μετριέται ([skipped]).
({List<Map<String, Object?>> log, List<Map<String, Object?>> foods, int skipped}) dbRecoveryRows({
  required Iterable<LogEntry> memoryEntries,
  required Iterable<Food> memoryFoods,
  required List<Object?> keptEntries,
  required List<Object?> keptFoods,
  Set<String> removedEntries = const {},
  Set<String> removedFoods = const {},
}) {
  var skipped = 0;
  final log = <Map<String, Object?>>[];
  final logIds = <String>{};
  for (final e in memoryEntries) {
    if (logIds.add(e.id)) log.add(e.toJson());
  }
  for (final raw in keptEntries) {
    LogEntry le;
    try {
      le = LogEntry.fromJson(Map<String, dynamic>.from(raw as Map));
    } catch (_) {
      skipped++;
      continue;
    }
    if (!restorableEntry(le)) {
      skipped++;
      continue;
    }
    if (removedEntries.contains(le.id) || !logIds.add(le.id)) continue;
    log.add(le.toJson());
  }
  final foods = <Map<String, Object?>>[];
  final foodIds = <String>{};
  for (final f in memoryFoods) {
    if (foodIds.add(f.id)) foods.add(f.toJson());
  }
  for (final raw in keptFoods) {
    Food f;
    try {
      f = Food.fromJson(Map<String, dynamic>.from(raw as Map));
    } catch (_) {
      skipped++;
      continue;
    }
    if (!restorableFood(f)) {
      skipped++;
      continue;
    }
    if (removedFoods.contains(f.id) || !foodIds.add(f.id)) continue;
    foods.add(f.toJson());
  }
  return (log: log, foods: foods, skipped: skipped);
}

BackupContents parseBackup(String text) {
  Object? j;
  try {
    j = jsonDecode(text);
  } catch (_) {
    throw BackupError('Το αρχείο δεν είναι αντίγραφο της εφαρμογής.');
  }
  if (j is! Map || j['app'] != backupApp) {
    throw BackupError('Το αρχείο δεν είναι αντίγραφο της εφαρμογής.');
  }
  final v = j['version'];
  // Τελικός έλεγχος (Συμβούλιο 3): έκδοση που δεν είναι αριθμός ή είναι «άπειρη» (1e999) = όχι δικό μας αρχείο. Πριν, το
  // toInt() πετούσε άλλο σφάλμα, που η οθόνη δεν έπιανε: η επαναφορά σταματούσε χωρίς κανένα μήνυμα.
  if (v is! num || !v.isFinite) {
    throw BackupError('Το αρχείο δεν είναι αντίγραφο της εφαρμογής.');
  }
  if (v.toInt() > backupVersion) {
    throw BackupError('Το αντίγραφο είναι από νεότερη έκδοση της εφαρμογής. Ενημέρωσε πρώτα την εφαρμογή.');
  }
  // Τελικός έλεγχος (Συμβούλιο 3): παραλείπεται (και μετριέται στο «χαλασμένες εγγραφές») ό,τι η εφαρμογή δεν γράφει ποτέ:
  // μέρα που δεν είναι υπαρκτή ημερομηνία (η καταχώριση δεν θα φαινόταν σε καμία μέρα), ποσότητα μη πεπερασμένη ή πάνω
  // από [backupMaxGrams], αρνητικές ή άπειρες τιμές θρεπτικών, και δεύτερη εγγραφή με το ίδιο id μέσα στο ίδιο αρχείο.
  var skipped = 0;
  final entries = <LogEntry>[];
  final entryIds = <String>{};
  for (final e in (j['foodLog'] is List ? j['foodLog'] as List : const [])) {
    try {
      final le = LogEntry.fromJson(Map<String, dynamic>.from(e as Map));
      if (!restorableEntry(le) || !entryIds.add(le.id)) throw const FormatException();
      entries.add(le);
    } catch (_) {
      skipped++;
    }
  }
  final foods = <Food>[];
  final foodIds = <String>{};
  for (final f in (j['myFoods'] is List ? j['myFoods'] as List : const [])) {
    try {
      final food = Food.fromJson(Map<String, dynamic>.from(f as Map));
      if (!restorableFood(food) || !foodIds.add(food.id)) throw const FormatException();
      foods.add(food);
    } catch (_) {
      skipped++;
    }
  }
  final prefs = j['prefs'] is Map
      ? {
          for (final e in (j['prefs'] as Map).entries)
            if (backupPrefKeys.contains(e.key)) e.key.toString(): e.value,
        }
      : <String, dynamic>{};
  final src = j['sources'];
  final plan = src is Map && src['plan'] is String && decodePlanFile(src['plan'] as String) != null ? src['plan'] as String : null;
  return BackupContents(
    entries,
    foods,
    prefs,
    j['created'] is String ? DateTime.tryParse(j['created'] as String) : null,
    skipped,
    sources: plan == null ? null : (plan: plan, log: (src as Map)['log'] is String ? src['log'] as String : null),
    training: j['training'] is Map ? Map<String, dynamic>.from(j['training'] as Map) : null,
    errorsOff: j['errorsOff'] == true,
  );
}

/// Round 7 (R7-A11-4): αντίγραφο από κινητό με κλειστές «Αναφορές σφαλμάτων»: κλείνουν και εδώ, πριν από οτιδήποτε
/// άλλο της επαναφοράς. Δεν ανοίγει ποτέ τίποτα (ένα αντίγραφο με ανοιχτές δεν αλλάζει τον διακόπτη). `true` αν
/// έκλεισαν τώρα.
Future<bool> restoreErrorsChoice(BackupContents b, ErrorReporter r) async {
  if (!b.errorsOff || !r.enabled) return false;
  return r.setEnabled(false);
}

/// Round 7 (R7-A9-5): το μήνυμα όταν το αντίγραφο δεν αποθηκεύτηκε. Από το είδος του σφάλματος («kind» της πλευράς
/// Android: «full» = γεμάτος χώρος), ποτέ το αγγλικό κείμενο της Java (πριν: «write failed: ENOSPC …»).
String backupSaveFailText(Map<String, dynamic> r) => switch (r['kind']) {
      'full' => 'Δεν αποθηκεύτηκε το αντίγραφο: δεν χωράει στο κινητό. Ελευθέρωσε χώρο και δοκίμασε ξανά.',
      _ => 'Δεν αποθηκεύτηκε το αντίγραφο. Δοκίμασε ξανά.',
    };

/// Round 7 (R7-A9-5): το μήνυμα όταν το αρχείο που διάλεξες δεν διαβάστηκε. «damaged» = κομμένο ή χαλασμένο συμπιεσμένο
/// αρχείο (π.χ. κατέβηκε μισό από το Drive), «too_big» = πάνω από το όριο ανάγνωσης (πριν: «Unexpected end of ZLIB
/// input stream»). Τίποτα δεν άλλαξε στο κινητό: η ανάγνωση σταματά πριν από την επαναφορά.
String backupOpenFailText(Map<String, dynamic> r) => switch (r['kind']) {
      'damaged' => 'Το αρχείο είναι κομμένο ή χαλασμένο, οπότε δεν άλλαξε τίποτα. Πάρε ξανά το αντίγραφο '
          '(π.χ. κατέβασέ το ξανά) και δοκίμασε πάλι.',
      'too_big' => 'Το αρχείο είναι πολύ μεγάλο για αντίγραφο της εφαρμογής, οπότε δεν άλλαξε τίποτα.',
      _ => 'Δεν άνοιξε το αρχείο, οπότε δεν άλλαξε τίποτα. Δοκίμασε ξανά.',
    };


/// Η γραμμή κάτω από την «Εξαγωγή αντιγράφου» (13/11): φαγητό, προϊόντα και προπονήσεις υπάρχουν μόνο στο κινητό, άρα
/// να φαίνεται πόσο παλιό είναι το τελευταίο αντίγραφο. Μετρά ημερολογιακές μέρες. Ώρα στο μέλλον (άλλαξε το ρολόι): «σήμερα».
String lastBackupText(DateTime? last, DateTime now) {
  if (last == null) return 'Δεν έχεις βγάλει αντίγραφο ακόμα.';
  final d = daysBetween(last, now);
  if (d <= 0) return 'Τελευταίο αντίγραφο: σήμερα.';
  if (d == 1) return 'Τελευταίο αντίγραφο: χθες.';
  return 'Τελευταίο αντίγραφο: πριν $d μέρες.';
}

/// Υπενθύμιση αντιγράφου στη «Σήμερα» (έλεγχος 13/11, S9-3): φαγητό, προϊόντα, προπονήσεις και στόχοι υπάρχουν μόνο στο
/// κινητό, και ως τώρα τίποτα δεν θύμιζε την εξαγωγή. Μετά από τόσες μέρες χωρίς αντίγραφο φαίνεται η κάρτα.
const backupReminderAfterDays = 7;

/// «Αργότερα»: η κάρτα κρύβεται για τόσες μέρες.
const backupSnoozeDays = 3;

/// Αν φαίνεται η κάρτα «Αντίγραφο ασφαλείας» στη «Σήμερα». [hasData]: υπάρχει κάτι που έγραψε ο χρήστης και ζει μόνο σε
/// αυτό το κινητό (φαγητό, προϊόν, προπόνηση, μέτρηση μέσης)· χωρίς αυτό δεν υπάρχει τι να χαθεί. [last]: το τελευταίο
/// πλήρες αντίγραφο (null = ποτέ). Μετρά ημερολογιακές μέρες, όπως το [lastBackupText]· ώρα στο μέλλον (άλλαξε το
/// ρολόι) = «σήμερα», όχι υπενθύμιση. [snoozedUntil]: ως πότε είπε «Αργότερα»· μετρά μόνο αν είναι μέσα στις επόμενες
/// [backupSnoozeDays] μέρες (αν το ρολόι γύρισε πίσω, ένα «αργότερα» μηνών δεν κρύβει την κάρτα για πάντα).
bool backupReminderDue({required DateTime? last, required bool hasData, required DateTime now, DateTime? snoozedUntil}) {
  if (!hasData) return false;
  if (snoozedUntil != null && now.isBefore(snoozedUntil) && daysBetween(now, snoozedUntil) <= backupSnoozeDays) return false;
  return last == null || daysBetween(last, now) >= backupReminderAfterDays;
}

/// Ως πότε κρύβεται η κάρτα μετά το «Αργότερα»: η αρχή της μέρας σε [backupSnoozeDays] μέρες (ξαναφαίνεται το πρωί).
DateTime backupSnoozeUntil(DateTime now) => DateTime(now.year, now.month, now.day + backupSnoozeDays);

/// Το κείμενο της κάρτας: πόσο παλιό είναι το τελευταίο αντίγραφο και τι κινδυνεύει.
String backupReminderText(DateTime? last, DateTime now) =>
    '${lastBackupText(last, now)} Το φαγητό, τα προϊόντα σου, οι προπονήσεις και οι στόχοι υπάρχουν μόνο σε αυτό το κινητό.';

/// Το αρχείο μένει στις Λήψεις του ίδιου κινητού: να φύγει και από το κινητό.
const backupOffPhoneText = 'Μετά στείλ’ το και έξω από το κινητό (π.χ. στο Drive ή με email): αν χαθεί το κινητό, χάνεται '
    'και το αρχείο στις Λήψεις.';

String entriesText(int n) => countText(n, 'καταχώριση', 'καταχωρίσεις');
String productsText(int n) => countText(n, 'προϊόν', 'προϊόντα');

/// «ygeia-antigrafo-2026-11-01.json.gz» (συμπιεσμένο· η επαναφορά δέχεται και τα παλιά .json).
String backupFileName(DateTime now) =>
    'ygeia-antigrafo-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.json.gz';
