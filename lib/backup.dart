/// Αντίγραφο ασφαλείας: ημερολόγιο φαγητού, «Τα προϊόντα μου» και ρυθμίσεις σε ένα αρχείο JSON.
///
/// Αυτά υπάρχουν μόνο στο κινητό (τα δεδομένα της Samsung ξαναδιαβάζονται, γι' αυτό δεν μπαίνουν). Και το σχέδιο
/// πηγών με το ημερολόγιό του (έλεγχος 4/11, A10): σε νέο κινητό, χωρίς αυτό, οι νύχτες του Oura θα γίνονταν σιωπηλά
/// νύχτες του ρολογιού.
/// Η επαναφορά **δεν σβήνει τίποτα** και **δεν αλλάζει ό,τι υπάρχει ήδη**: προσθέτει μόνο ό,τι λείπει· το σχέδιο πηγών
/// μπαίνει μόνο αν το κινητό δεν έχει νεότερο ([HealthStore.restoreSources]).
library;

import 'dart:convert';

import 'food/food_model.dart';
import 'format.dart';
import 'plan_file.dart';

const backupApp = 'ygeia-forma';
const backupVersion = 1;

/// Οι ρυθμίσεις που μπαίνουν στο αντίγραφο (όχι η πρόοδος του ιστορικού, που είναι τεχνική).
const backupPrefKeys = ['cards', 'kitchen', 'themeMode', 'dayTheme', 'nightTheme', 'me'];

String buildBackup({
  required List<Map<String, dynamic>> foodLog,
  required List<Map<String, dynamic>> myFoods,
  required Map<String, dynamic> prefs,
  required DateTime now,
  ({String plan, String? log})? sources,
  Map<String, dynamic>? training,
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
    // Προπονήσεις, προγράμματα, «Νιώθω κάτι» (έλεγχος 8/11, TRN-17): υπάρχουν μόνο στο κινητό.
    if (training != null) 'training': training,
  });
}

/// Ό,τι βρέθηκε σε ένα αρχείο αντιγράφου, ελεγμένο.
class BackupContents {
  BackupContents(this.entries, this.myFoods, this.prefs, this.created, this.skipped, {this.sources, this.training});

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
  if (v is! num || v.toInt() > backupVersion) {
    throw BackupError('Το αντίγραφο είναι από νεότερη έκδοση της εφαρμογής. Ενημέρωσε πρώτα την εφαρμογή.');
  }
  var skipped = 0;
  final entries = <LogEntry>[];
  for (final e in (j['foodLog'] is List ? j['foodLog'] as List : const [])) {
    try {
      final le = LogEntry.fromJson(Map<String, dynamic>.from(e as Map));
      if (le.id.isEmpty || le.day.isEmpty || !(le.grams > 0)) throw const FormatException();
      entries.add(le);
    } catch (_) {
      skipped++;
    }
  }
  final foods = <Food>[];
  for (final f in (j['myFoods'] is List ? j['myFoods'] as List : const [])) {
    try {
      final food = Food.fromJson(Map<String, dynamic>.from(f as Map));
      if (food.id.isEmpty) throw const FormatException();
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
  );
}


String entriesText(int n) => countText(n, 'καταχώριση', 'καταχωρίσεις');
String productsText(int n) => countText(n, 'προϊόν', 'προϊόντα');

/// «ygeia-antigrafo-2026-11-01.json.gz» (συμπιεσμένο· η επαναφορά δέχεται και τα παλιά .json).
String backupFileName(DateTime now) =>
    'ygeia-antigrafo-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.json.gz';
